-- Issue #52: run this ENTIRE script in PRODUCTION Supabase SQL Editor.
-- Expected project: zjnuqqtbapbpudsjbpif. No credentials or .env edits needed.
-- Verifies only the four reported acceptance events, then removes those IDs.
-- Any mismatch raises an error and rolls back the whole transaction.
-- Supabase warning: choose "Run without RLS" for this script. The helper
-- table is session-temporary and ON COMMIT DROP, not an application table.
-- The deliberate DELETE targets only the four exact verified test events.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create temporary table issue52_expected_events (
    id uuid primary key,
    interaction_type text not null,
    interaction_value numeric not null,
    rating_value numeric
) on commit drop;

insert into issue52_expected_events values
    ('1d20e029-a544-4619-b047-792b4a4763e8', 'save', 1, null),
    ('acdc4adf-05cb-47de-8259-ae070245a3fe', 'left_swipe', -1, null),
    ('ffe32188-3b95-4f6e-9485-fe16766cec85', 'right_swipe', 1, null),
    ('faba69d4-961b-4431-bea7-2262db70878a', 'rating', 1, 3.75);

do $$
declare
    owner_id constant uuid := '23000000-0000-4000-8000-000000000001';
    destination_id constant uuid := '1a3bca09-5532-5de6-8587-2440c4e5830d';
    removed integer;
begin
    perform 1 from public.users where id = owner_id for key share;
    if not found then
        raise exception 'Expected demo user missing; no events deleted.';
    end if;
    perform 1 from public.locations
        where id = destination_id and is_active = true for share;
    if not found then
        raise exception 'Expected active location missing; no events deleted.';
    end if;

    perform 1 from public.user_location_interactions i
        join issue52_expected_events e on e.id = i.id for update of i;
    if exists (
        select 1 from issue52_expected_events e
        left join public.user_location_interactions i on i.id = e.id
        where i.id is null or i.user_id is distinct from owner_id
            or i.location_id is distinct from destination_id
            or i.interaction_type is distinct from e.interaction_type
            or i.interaction_value is distinct from e.interaction_value
            or i.rating_value is distinct from e.rating_value
    ) then
        raise exception 'Exact event verification failed; no events deleted.';
    end if;
    if (select count(*) from public.user_location_interactions
        where user_id = owner_id) <> 4 then
        raise exception 'History differs from the four-event baseline; no events deleted.';
    end if;

    delete from public.user_location_interactions i using issue52_expected_events e
    where i.id = e.id and i.user_id = owner_id and i.location_id = destination_id;
    get diagnostics removed = row_count;
    if removed <> 4 or exists (
        select 1 from public.user_location_interactions i
        join issue52_expected_events e on e.id = i.id
    ) then
        raise exception 'Exact cleanup failed; transaction rolled back.';
    end if;
    if not exists (select 1 from public.users where id = owner_id)
        or not exists (select 1 from public.locations
            where id = destination_id and is_active = true) then
        raise exception 'Parent preservation failed; transaction rolled back.';
    end if;
end;
$$;

select 'PASS' as result,
    4 as verified_and_deleted_events,
    (select count(*) from public.user_location_interactions
        where user_id = '23000000-0000-4000-8000-000000000001') as remaining_owner_events,
    exists (select 1 from public.users
        where id = '23000000-0000-4000-8000-000000000001') as user_preserved,
    exists (select 1 from public.locations
        where id = '1a3bca09-5532-5de6-8587-2440c4e5830d' and is_active = true)
        as active_location_preserved;

commit;
