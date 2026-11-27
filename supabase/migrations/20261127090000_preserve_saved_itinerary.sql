-- #202: serialize trip date edits with itinerary writes on the parent row.
create function public.protect_saved_itinerary() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
    if new.end_date >= new.start_date
       and (new.start_date, new.end_date) is distinct from (old.start_date, old.end_date)
       and exists (
           select 1 from public.itinerary_items
           where trip_id = new.id and day_number > new.end_date - new.start_date + 1
       ) then
        raise sqlstate 'PT409' using message = 'Saved visits would fall outside the trip dates';
    end if;

    if new.estimated_total_cost > new.budget_max then
        new.estimated_total_cost := null;
    end if;
    return new;
end;
$$;

create trigger protect_saved_itinerary before update of start_date, end_date, budget_max on public.trips
for each row execute function public.protect_saved_itinerary();

-- Clear legacy totals invalidated by earlier budget edits. Leave all visits in place.
update public.trips set estimated_total_cost = null where estimated_total_cost > budget_max;
alter table public.trips add constraint trips_total_cost_within_budget
    check (estimated_total_cost <= budget_max);

create or replace function public.lock_itinerary_parent() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
    trip_days integer;
begin
    if tg_op = 'DELETE' then
        update public.trips set estimated_total_cost = null where id = old.trip_id;
        return old;
    end if;

    if tg_op = 'UPDATE' and new.trip_id <> old.trip_id then
        -- Administrative moves still lock both parents in UUID order.
        perform 1 from public.trips where id in (old.trip_id, new.trip_id) order by id for update;
        update public.trips set estimated_total_cost = null where id = old.trip_id;
    end if;

    update public.trips set estimated_total_cost = null where id = new.trip_id
        returning end_date - start_date + 1 into trip_days;
    if new.day_number > trip_days and (tg_op = 'INSERT'
        or (new.trip_id, new.day_number) is distinct from (old.trip_id, old.day_number)) then
        raise sqlstate 'PT409' using message = 'Visit would fall outside the trip dates';
    end if;
    return new;
end;
$$;

revoke all on function public.protect_saved_itinerary() from public, anon, authenticated;
grant execute on function public.protect_saved_itinerary() to service_role;

-- Match generation's parent-first lock order before acquiring any item row lock.
create function public.remove_itinerary_item(p_owner uuid, p_trip uuid, p_item uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
    perform 1 from public.trips where id = p_trip and user_id = p_owner for update;
    if not found then
        return false;
    end if;

    delete from public.itinerary_items where id = p_item and trip_id = p_trip;
    return found;
end;
$$;

revoke all on function public.remove_itinerary_item(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.remove_itinerary_item(uuid, uuid, uuid) to service_role;
notify pgrst, 'reload schema';
