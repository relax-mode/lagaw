-- Issue54 PRODUCTION exact acceptance-fixture cleanup, single-use.
-- Select project zjnuqqtbapbpudsjbpif; production execution belongs to Andrew's SQL Editor.
-- Removes only the exact synthetic trip (cascading its three items) and three
-- exact synthetic locations after comparing the COMPLETE verified saved state.
-- The existing demo profile, other records, migration and functions are retained.
-- Any changed state/reference/count/profile check aborts the entire transaction.
begin;
do $issue54_cleanup$
declare
    p_owner constant uuid := '23000000-0000-4000-8000-000000000001'::uuid;
    p_trip constant uuid := '5b4497d1-a946-4845-bed5-441fbb563180'::uuid;
    p_locations constant uuid[] := array['6fe3ecfb-2435-4ef5-bd15-4fc5a4803227'::uuid,'035843d7-c6c8-498e-9c0a-86dc0d60527e'::uuid,'010d414e-50ce-4be3-82e3-8e30ab8207be'::uuid];
    p_items constant uuid[] := array['83386a42-04f3-45c8-9218-7cd1819a12ec'::uuid,'83327ba8-f3fd-4efd-8372-3e608be0cc7b'::uuid,'8ff6b063-c621-41af-9c7c-76f303919992'::uuid];
    p_expected constant jsonb := $issue54_expected${"trip":{"title":"Issue 54 SYNTHETIC production acceptance","start_date":"2026-11-02","end_date":"2026-11-03","budget_min":0,"budget_max":180,"transportation_mode":"walking","group_type":"friends","preferred_tags":["cafe"],"id":"5b4497d1-a946-4845-bed5-441fbb563180","user_id":"23000000-0000-4000-8000-000000000001","status":"draft","estimated_total_cost":120},"revision":"c906b3caf89e3fa668ba434c8c7f3df4","items":[{"location_id":"6fe3ecfb-2435-4ef5-bd15-4fc5a4803227","day_number":1,"visit_order":1,"id":"83386a42-04f3-45c8-9218-7cd1819a12ec","trip_id":"5b4497d1-a946-4845-bed5-441fbb563180","location":{"id":"6fe3ecfb-2435-4ef5-bd15-4fc5a4803227","name":"Issue 54 SYNTHETIC production Monday A","description":"Synthetic issue54 acceptance fixture; not a real destination","category":"cafe","vibe_tags":["cafe"],"address":null,"latitude":10.67,"longitude":122.95,"opening_hours":{"monday":[{"open":"09:00","close":"12:00"}]},"estimated_cost_min":10.0,"estimated_cost_max":10.0,"typical_visit_duration":30,"suitable_group_types":["friends"],"image_url":null,"is_active":true},"arrival_time":"09:00:00","departure_time":"09:30:00","estimated_travel_time":0,"estimated_cost":20,"recommendation_score":0.9333333333333332,"recommendation_reason":"Tags: cafe; category: not specified; budget headroom: 0.67; group: friends; all requested hard constraints satisfied."},{"location_id":"035843d7-c6c8-498e-9c0a-86dc0d60527e","day_number":1,"visit_order":2,"id":"83327ba8-f3fd-4efd-8372-3e608be0cc7b","trip_id":"5b4497d1-a946-4845-bed5-441fbb563180","location":{"id":"035843d7-c6c8-498e-9c0a-86dc0d60527e","name":"Issue 54 SYNTHETIC production Monday B","description":"Synthetic issue54 acceptance fixture; not a real destination","category":"cafe","vibe_tags":["cafe"],"address":null,"latitude":10.671,"longitude":122.95,"opening_hours":{"monday":[{"open":"09:00","close":"12:00"}]},"estimated_cost_min":20.0,"estimated_cost_max":20.0,"typical_visit_duration":30,"suitable_group_types":["friends"],"image_url":null,"is_active":true},"arrival_time":"09:53:00","departure_time":"10:23:00","estimated_travel_time":8,"estimated_cost":40,"recommendation_score":0.8666666666666667,"recommendation_reason":"Tags: cafe; category: not specified; budget headroom: 0.33; group: friends; all requested hard constraints satisfied."},{"location_id":"010d414e-50ce-4be3-82e3-8e30ab8207be","day_number":2,"visit_order":1,"id":"8ff6b063-c621-41af-9c7c-76f303919992","trip_id":"5b4497d1-a946-4845-bed5-441fbb563180","location":{"id":"010d414e-50ce-4be3-82e3-8e30ab8207be","name":"Issue 54 SYNTHETIC production Tuesday","description":"Synthetic issue54 acceptance fixture; not a real destination","category":"cafe","vibe_tags":["cafe"],"address":null,"latitude":10.672,"longitude":122.95,"opening_hours":{"tuesday":[{"open":"09:00","close":"12:00"}]},"estimated_cost_min":30.0,"estimated_cost_max":30.0,"typical_visit_duration":60,"suitable_group_types":["friends"],"image_url":null,"is_active":true},"arrival_time":"09:00:00","departure_time":"10:00:00","estimated_travel_time":0,"estimated_cost":60,"recommendation_score":0.7999999999999999,"recommendation_reason":"Tags: cafe; category: not specified; budget headroom: 0.00; group: friends; all requested hard constraints satisfied."}]}$issue54_expected$::jsonb;
    v_owner_before text;
    v_owner_after text;
    v_locked_count integer;
    v_removed integer;
    v_saved jsonb;
begin
    select md5(to_jsonb(u)::text) into v_owner_before
        from public.users u where u.id = p_owner for share;
    if v_owner_before is null then
        raise exception 'STOP: existing demo profile is missing';
    end if;
    perform 1 from public.trips where id = p_trip and user_id = p_owner for update;
    if not found then
        raise exception 'STOP: exact synthetic trip is missing; cleanup is single-use';
    end if;
    perform 1 from public.locations where id = any(p_locations) order by id for update;
    get diagnostics v_locked_count = row_count;
    if v_locked_count <> 3 then
        raise exception 'STOP: expected three exact synthetic locations';
    end if;
    v_saved := public.itinerary_state(p_owner,p_trip);
    if v_saved is distinct from p_expected then
        raise exception 'STOP: complete saved state changed; do not delete or repair blindly';
    end if;
    if exists(select 1 from public.itinerary_items where location_id = any(p_locations) and trip_id <> p_trip)
       or exists(select 1 from public.user_location_interactions where location_id = any(p_locations)) then
        raise exception 'STOP: synthetic locations acquired other references; investigate before cleanup';
    end if;

    delete from public.trips where id = p_trip and user_id = p_owner;
    get diagnostics v_removed = row_count;
    if v_removed <> 1 then
        raise exception 'STOP: exact trip delete count differs';
    end if;
    if exists(select 1 from public.itinerary_items where trip_id = p_trip or id = any(p_items)) then
        raise exception 'STOP: exact itinerary items survived the cascade';
    end if;
    delete from public.locations where id = any(p_locations);
    get diagnostics v_removed = row_count;
    if v_removed <> 3 then
        raise exception 'STOP: exact location delete count differs';
    end if;
    if exists(select 1 from public.trips where id = p_trip)
       or exists(select 1 from public.locations where id = any(p_locations)) then
        raise exception 'STOP: exact fixtures remain';
    end if;
    select md5(to_jsonb(u)::text) into v_owner_after from public.users u where u.id = p_owner;
    if v_owner_after is distinct from v_owner_before then
        raise exception 'STOP: existing demo profile changed; cleanup rolled back';
    end if;
end;
$issue54_cleanup$;
commit;
select 'PASS: Issue 54 production fixtures cleaned; one trip, three items and three locations removed; existing demo profile preserved.' as result,
       '5b4497d1-a946-4845-bed5-441fbb563180' as cleaned_trip_id;
