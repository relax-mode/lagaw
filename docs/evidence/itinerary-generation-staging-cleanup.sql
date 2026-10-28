-- Issue54 STAGING exact acceptance-fixture cleanup, single-use.
-- Select project vnpkyvtbupnquvirzlzp; production execution belongs to Andrew's SQL Editor.
-- Removes only the exact synthetic trip (cascading its three items) and three
-- exact synthetic locations after comparing the COMPLETE verified saved state.
-- The existing demo profile, other records, migration and functions are retained.
-- Any changed state/reference/count/profile check aborts the entire transaction.
begin;
do $issue54_cleanup$
declare
    p_owner constant uuid := '16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c'::uuid;
    p_trip constant uuid := '03b7f114-9b91-4985-9bf5-3efdb3a54d76'::uuid;
    p_locations constant uuid[] := array['ad2ca02d-b441-402c-9b01-be576dfc660c'::uuid,'7d465cf0-25fb-4a60-9ae1-55f557aa9a68'::uuid,'2b418dcb-b520-4eff-bdae-b9577bf7547d'::uuid];
    p_items constant uuid[] := array['7b99d4e1-853f-41db-8c26-6ff660ac89b9'::uuid,'f7c0a84f-0e17-4f47-b86c-bcfe463f84fc'::uuid,'582e663d-052a-45db-88ab-beee1d905084'::uuid];
    p_expected constant jsonb := $issue54_expected${"trip":{"title":"Issue 54 SYNTHETIC staging acceptance","start_date":"2026-11-02","end_date":"2026-11-03","budget_min":0,"budget_max":180,"transportation_mode":"walking","group_type":"friends","preferred_tags":["cafe"],"id":"03b7f114-9b91-4985-9bf5-3efdb3a54d76","user_id":"16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c","status":"draft","estimated_total_cost":120},"revision":"710c2399e657678caae1bf63cd82b5bc","items":[{"location_id":"ad2ca02d-b441-402c-9b01-be576dfc660c","day_number":1,"visit_order":1,"id":"7b99d4e1-853f-41db-8c26-6ff660ac89b9","trip_id":"03b7f114-9b91-4985-9bf5-3efdb3a54d76","location":{"id":"ad2ca02d-b441-402c-9b01-be576dfc660c","name":"Issue 54 SYNTHETIC staging Monday A","description":"Synthetic issue54 acceptance fixture; not a real destination","category":"cafe","vibe_tags":["cafe"],"address":null,"latitude":10.67,"longitude":122.95,"opening_hours":{"monday":[{"open":"09:00","close":"12:00"}]},"estimated_cost_min":10.0,"estimated_cost_max":10.0,"typical_visit_duration":30,"suitable_group_types":["friends"],"image_url":null,"is_active":true},"arrival_time":"09:00:00","departure_time":"09:30:00","estimated_travel_time":0,"estimated_cost":20,"recommendation_score":0.9333333333333332,"recommendation_reason":"Tags: cafe; category: not specified; budget headroom: 0.67; group: friends; all requested hard constraints satisfied."},{"location_id":"7d465cf0-25fb-4a60-9ae1-55f557aa9a68","day_number":1,"visit_order":2,"id":"f7c0a84f-0e17-4f47-b86c-bcfe463f84fc","trip_id":"03b7f114-9b91-4985-9bf5-3efdb3a54d76","location":{"id":"7d465cf0-25fb-4a60-9ae1-55f557aa9a68","name":"Issue 54 SYNTHETIC staging Monday B","description":"Synthetic issue54 acceptance fixture; not a real destination","category":"cafe","vibe_tags":["cafe"],"address":null,"latitude":10.671,"longitude":122.95,"opening_hours":{"monday":[{"open":"09:00","close":"12:00"}]},"estimated_cost_min":20.0,"estimated_cost_max":20.0,"typical_visit_duration":30,"suitable_group_types":["friends"],"image_url":null,"is_active":true},"arrival_time":"09:53:00","departure_time":"10:23:00","estimated_travel_time":8,"estimated_cost":40,"recommendation_score":0.8666666666666667,"recommendation_reason":"Tags: cafe; category: not specified; budget headroom: 0.33; group: friends; all requested hard constraints satisfied."},{"location_id":"2b418dcb-b520-4eff-bdae-b9577bf7547d","day_number":2,"visit_order":1,"id":"582e663d-052a-45db-88ab-beee1d905084","trip_id":"03b7f114-9b91-4985-9bf5-3efdb3a54d76","location":{"id":"2b418dcb-b520-4eff-bdae-b9577bf7547d","name":"Issue 54 SYNTHETIC staging Tuesday","description":"Synthetic issue54 acceptance fixture; not a real destination","category":"cafe","vibe_tags":["cafe"],"address":null,"latitude":10.672,"longitude":122.95,"opening_hours":{"tuesday":[{"open":"09:00","close":"12:00"}]},"estimated_cost_min":30.0,"estimated_cost_max":30.0,"typical_visit_duration":60,"suitable_group_types":["friends"],"image_url":null,"is_active":true},"arrival_time":"09:00:00","departure_time":"10:00:00","estimated_travel_time":0,"estimated_cost":60,"recommendation_score":0.7999999999999999,"recommendation_reason":"Tags: cafe; category: not specified; budget headroom: 0.00; group: friends; all requested hard constraints satisfied."}]}$issue54_expected$::jsonb;
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
select 'PASS: Issue 54 staging fixtures cleaned; one trip, three items and three locations removed; existing demo profile preserved.' as result,
       '03b7f114-9b91-4985-9bf5-3efdb3a54d76' as cleaned_trip_id;
