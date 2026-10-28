-- #79 PRODUCTION migration prerequisite, after staging verification.
-- Run in https://supabase.com/dashboard/project/zjnuqqtbapbpudsjbpif/sql/new
-- Preserves application rows. Same filename/version/source as the reviewed migration.
-- Development marker guard, short lock/statement timeouts and transaction-wide rollback.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
lock table public.users, public.locations, public.trips, public.itinerary_items,
    public.user_location_interactions in share row exclusive mode;
create temporary table issue79_before (table_name text primary key, row_count bigint, digest text) on commit drop;

do $issue79$
declare
    t text;
    n bigint;
    h text;
    b record;
    applied boolean;
    installed boolean;
begin
    if exists (select 1 from public.users where id in
        ('32e75bf5-a314-4e98-bc49-6a2ea7eb8173'::uuid,
         '72e23403-1ad4-4ee3-b2f9-049e29e1c3aa'::uuid)) then
        raise exception 'STOP: development verification profiles detected; select the production project';
    end if;
    if not exists (select 1 from public.users where id='23000000-0000-4000-8000-000000000001'::uuid) then
        raise exception 'STOP: known legacy production profile is absent; verify the target';
    end if;
    foreach t in array array['users','locations','trips','itinerary_items','user_location_interactions'] loop
        execute format($issue79_snapshot$select count(*), md5(coalesce(string_agg(md5((to_jsonb(x) - 'auth_user_id')::text), '' order by x.id), '')) from public.%I x$issue79_snapshot$, t)
            into n, h;
        insert into issue79_before values(t,n,h);
    end loop;
    select exists(select 1 from supabase_migrations.schema_migrations where version='20261029090000') into applied;
    select exists(select 1 from information_schema.columns where table_schema='public'
        and table_name='users' and column_name='auth_user_id') into installed;
    if applied is distinct from installed then
        raise exception 'STOP: migration history and Auth column disagree';
    end if;
    if not applied then
        if (select array_agg(version order by version) from supabase_migrations.schema_migrations)
            is distinct from array['20261014114320','20261014154651','20261028130000']::text[] then
            raise exception 'STOP: unexpected migration history; review before applying';
        end if;
-- #79: additive identity mapping; no existing profile/trip/event is reassigned.
-- No auth.users FK: application profiles survive Auth lifecycle changes. Account
-- deletion is out of scope, and privileged backend credentials own this mapping.
alter table public.users
    add column auth_user_id uuid,
    add constraint users_auth_user_id_key unique (auth_user_id),
    add constraint users_auth_user_id_nonzero
        check (auth_user_id <> '00000000-0000-0000-0000-000000000000'::uuid);

comment on column public.users.auth_user_id is
    'Supabase Auth subject, linked only after server verification. NULL preserves legacy/demo ownership.';

notify pgrst, 'reload schema';

        insert into supabase_migrations.schema_migrations(version,name,statements)
            values ('20261029090000','link_verified_auth_profiles',array[$issue79_source$-- #79: additive identity mapping; no existing profile/trip/event is reassigned.
-- No auth.users FK: application profiles survive Auth lifecycle changes. Account
-- deletion is out of scope, and privileged backend credentials own this mapping.
alter table public.users
    add column auth_user_id uuid,
    add constraint users_auth_user_id_key unique (auth_user_id),
    add constraint users_auth_user_id_nonzero
        check (auth_user_id <> '00000000-0000-0000-0000-000000000000'::uuid);

comment on column public.users.auth_user_id is
    'Supabase Auth subject, linked only after server verification. NULL preserves legacy/demo ownership.';

notify pgrst, 'reload schema';
$issue79_source$]);
        if exists(select 1 from public.users where auth_user_id is not null) then
            raise exception 'STOP: a legacy profile was unexpectedly assigned';
        end if;
    end if;
    if (select count(*) from pg_constraint where conrelid='public.users'::regclass
        and conname in ('users_auth_user_id_key','users_auth_user_id_nonzero')) <> 2 then
        raise exception 'STOP: expected identity-link constraints are missing';
    end if;
    foreach t in array array['users','locations','trips','itinerary_items','user_location_interactions'] loop
        execute format($issue79_snapshot$select count(*), md5(coalesce(string_agg(md5((to_jsonb(x) - 'auth_user_id')::text), '' order by x.id), '')) from public.%I x$issue79_snapshot$, t)
            into n, h;
        select * into b from issue79_before where table_name=t;
        if n is distinct from b.row_count or h is distinct from b.digest then
            raise exception 'STOP: existing application rows changed; transaction rolled back';
        end if;
    end loop;
end;
$issue79$;
commit;
select 'PASS: Issue79 Auth migration installed; matching history and constraints verified; existing application records preserved.' as result,
       '20261029090000' as migration_version;
