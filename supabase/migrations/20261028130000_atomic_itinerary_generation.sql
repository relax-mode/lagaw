-- #54: keep existing tables. Server-only RPCs provide a transaction boundary.
-- Apply/verify on disposable PostgreSQL, then development, before production.

create function public.itinerary_revision(p_trip uuid) returns text
language sql stable security invoker set search_path = '' as $$
    select md5(to_jsonb(t)::text || coalesce((
        select jsonb_agg(to_jsonb(i) order by i.day_number, i.visit_order, i.id)::text
        from public.itinerary_items i where i.trip_id = t.id
    ), '[]')) from public.trips t where t.id = p_trip;
$$;

create function public.itinerary_state(p_owner uuid, p_trip uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select jsonb_build_object(
        'trip', to_jsonb(t), 'revision', public.itinerary_revision(t.id),
        'items', coalesce((select jsonb_agg(to_jsonb(i) || jsonb_build_object('location', to_jsonb(l))
            order by i.day_number, i.visit_order, i.id)
            from public.itinerary_items i join public.locations l on l.id = i.location_id
            where i.trip_id = t.id), '[]'::jsonb)
    ) from public.trips t where t.id = p_trip and t.user_id = p_owner;
$$;

-- Manual adds/removals/edits use the same parent lock as generation. They
-- invalidate the complete-plan estimate: a manually edited plan is unverified.
create function public.lock_itinerary_parent() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
    if tg_op = 'UPDATE' and new.trip_id <> old.trip_id then
        raise exception using errcode = '23514', message = 'Item parent is immutable';
    end if;
    if tg_op = 'DELETE' then
        update public.trips set estimated_total_cost = null where id = old.trip_id;
        return old;
    end if;
    update public.trips set estimated_total_cost = null where id = new.trip_id;
    return new;
end;
$$;

create trigger itinerary_parent_lock before insert or update or delete on public.itinerary_items
for each row execute function public.lock_itinerary_parent();

create function public.save_generated_itinerary(
    p_owner uuid, p_trip uuid, p_revision text, p_replace boolean,
    p_items jsonb, p_locations jsonb
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    saved_trip public.trips;
    candidate public.locations;
    proposed record;
    snapshot jsonb;
    total numeric;
    previous_departure time;
    previous_day integer := 0;
    previous_order integer := 0;
    weekday text;
begin
    select * into saved_trip from public.trips
        where id = p_trip and user_id = p_owner for update;
    if not found then
        raise sqlstate 'PT404' using message = 'Trip not found';
    end if;
    if p_revision is distinct from public.itinerary_revision(p_trip) then
        raise sqlstate 'PT409' using message = 'Itinerary changed';
    end if;
    if p_replace is not true and exists(select 1 from public.itinerary_items where trip_id = p_trip) then
        raise sqlstate 'PT409' using message = 'Replacement confirmation required';
    end if;
    if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100
       or jsonb_typeof(p_locations) is distinct from 'array' then
        raise sqlstate 'PT409' using message = 'Invalid itinerary';
    end if;
    -- Lock referenced catalog rows in UUID order and compare the exact facts
    -- validated by the backend. No catalog edit can race this transaction.
    perform 1 from public.locations where id in (
        select (value->>'location_id')::uuid from jsonb_array_elements(p_items)
    ) order by id for share;
    for proposed in select * from jsonb_to_recordset(p_items) as x(
        location_id uuid, day_number integer, visit_order integer,
        arrival_time time, departure_time time, estimated_travel_time integer,
        estimated_cost numeric, recommendation_score numeric, recommendation_reason text
    ) order by day_number, visit_order loop
        select * into candidate from public.locations where id = proposed.location_id;
        select value into snapshot from jsonb_array_elements(p_locations)
            where value->>'id' = proposed.location_id::text;
        if candidate.id is null or not candidate.is_active or snapshot is distinct from to_jsonb(candidate)
           or exists(select 1 from public.user_location_interactions
               where user_id = p_owner and location_id = proposed.location_id and interaction_type = 'left_swipe') then
            raise sqlstate 'PT409' using message = 'Recommended location changed';
        end if;
        if proposed.day_number is null or proposed.day_number not between 1 and (saved_trip.end_date - saved_trip.start_date + 1)
           or proposed.visit_order is distinct from (case when previous_day = proposed.day_number then previous_order + 1 else 1 end)
           or proposed.arrival_time is null or proposed.departure_time is null
           or proposed.departure_time <= proposed.arrival_time
           or proposed.estimated_travel_time is null or proposed.estimated_travel_time < 0
           or candidate.typical_visit_duration is null
           or extract(epoch from (proposed.departure_time - proposed.arrival_time))/60 < candidate.typical_visit_duration
           or proposed.estimated_cost is null or proposed.estimated_cost < candidate.estimated_cost_max
           or candidate.estimated_cost_max is null
           or proposed.recommendation_score is null or proposed.recommendation_score not between 0 and 1
           or proposed.recommendation_reason is null or length(btrim(proposed.recommendation_reason)) not between 1 and 500 then
            raise sqlstate 'PT409' using message = 'Invalid schedule';
        end if;
        if previous_day = proposed.day_number and
           extract(epoch from (proposed.arrival_time - previous_departure))/60 < proposed.estimated_travel_time then
            raise sqlstate 'PT409' using message = 'Overlapping schedule';
        end if;
        weekday := (array['monday','tuesday','wednesday','thursday','friday','saturday','sunday'])[
            extract(isodow from saved_trip.start_date + proposed.day_number - 1)::integer];
        if not exists(select 1 from jsonb_array_elements(coalesce(candidate.opening_hours->weekday, '[]'::jsonb)) h
            where proposed.arrival_time >= (h->>'open')::time and proposed.departure_time <= (h->>'close')::time
              and (h->>'close')::time > (h->>'open')::time) then
            raise sqlstate 'PT409' using message = 'Destination is closed';
        end if;
        previous_day := proposed.day_number;
        previous_order := proposed.visit_order;
        previous_departure := proposed.departure_time;
    end loop;
    if (select count(distinct value->>'location_id') from jsonb_array_elements(p_items)) <> jsonb_array_length(p_items) then
        raise sqlstate 'PT409' using message = 'Duplicate destination';
    end if;
    select sum((value->>'estimated_cost')::numeric) into total from jsonb_array_elements(p_items);
    if total is null or total < 0 or total > saved_trip.budget_max then
        raise sqlstate 'PT409' using message = 'Budget exceeded';
    end if;
    -- Any statement/trigger failure rolls back deletion, insertions and total.
    delete from public.itinerary_items where trip_id = p_trip;
    insert into public.itinerary_items (
        trip_id, location_id, day_number, visit_order, arrival_time, departure_time,
        estimated_travel_time, estimated_cost, recommendation_score, recommendation_reason
    ) select p_trip, x.* from jsonb_to_recordset(p_items) as x(
        location_id uuid, day_number integer, visit_order integer,
        arrival_time time, departure_time time, estimated_travel_time integer,
        estimated_cost numeric, recommendation_score numeric, recommendation_reason text
    );
    update public.trips set estimated_total_cost = total where id = p_trip;
    return public.itinerary_state(p_owner, p_trip);
end;
$$;

revoke all on function public.itinerary_revision(uuid), public.itinerary_state(uuid,uuid),
    public.lock_itinerary_parent(), public.save_generated_itinerary(uuid,uuid,text,boolean,jsonb,jsonb)
from public, anon, authenticated;
grant execute on function public.itinerary_revision(uuid), public.itinerary_state(uuid,uuid),
    public.lock_itinerary_parent(), public.save_generated_itinerary(uuid,uuid,text,boolean,jsonb,jsonb)
to service_role;

notify pgrst, 'reload schema';
