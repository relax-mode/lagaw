-- #202: reserve against a per-project UTC-day ceiling shared by every profile.
-- The operator provisions the AI owner's approved ceiling in each environment.
create table public.ai_extraction_budget (
    singleton boolean primary key default true check (singleton),
    attempt_limit integer not null check (attempt_limit > 0),
    window_start timestamptz,
    request_count bigint not null default 0 check (request_count >= 0)
);

alter table public.ai_extraction_budget enable row level security;
revoke all on public.ai_extraction_budget from public, anon, authenticated, service_role;
grant select, update (window_start, request_count) on public.ai_extraction_budget to service_role;

create or replace function public.consume_ai_extraction_quota(
    p_profile_id uuid, p_per_minute integer, p_per_day integer
)
returns table (allowed boolean, retry_after_seconds integer, exhausted_window text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
    budget public.ai_extraction_budget;
    at_time timestamptz;
    minute_start timestamptz;
    day_start timestamptz;
    minute_used integer;
    day_used integer;
    aggregate_used bigint := 0;
    day_retry integer;
begin
    if p_profile_id is null or p_per_minute is null or p_per_minute not between 1 and 10
        or p_per_day is null or p_per_day not between 1 and 200 then
        raise exception 'Invalid extraction quota configuration';
    end if;

    -- The same row serializes all reservations, including distinct profiles.
    select * into budget from public.ai_extraction_budget where singleton for update;
    if not found then
        raise sqlstate 'PT503' using message = 'Extraction budget is unavailable';
    end if;
    at_time := clock_timestamp();
    minute_start := date_trunc('minute', at_time, 'UTC');
    day_start := date_trunc('day', at_time, 'UTC');
    day_retry := greatest(1, ceil(extract(epoch from (day_start + interval '24 hours' - at_time)))::integer);

    if budget.window_start = day_start then
        aggregate_used := budget.request_count;
    elsif budget.window_start is null then
        -- On first use, include today's reservations made before the upgrade.
        select coalesce(sum(q.request_count), 0) into aggregate_used
        from public.ai_extraction_quotas q
        where q.window_kind = 'day' and q.window_start = day_start;
        update public.ai_extraction_budget
        set window_start = day_start, request_count = aggregate_used where singleton;
    end if;

    select q.request_count into day_used
    from public.ai_extraction_quotas q
    where q.profile_id = p_profile_id and q.window_kind = 'day'
      and q.window_start = day_start;
    if aggregate_used >= budget.attempt_limit or coalesce(day_used, 0) >= p_per_day then
        return query select false, day_retry, 'day'::text;
        return;
    end if;

    select q.request_count into minute_used
    from public.ai_extraction_quotas q
    where q.profile_id = p_profile_id and q.window_kind = 'minute'
      and q.window_start = minute_start;
    if coalesce(minute_used, 0) >= p_per_minute then
        return query select false,
            greatest(1, ceil(extract(epoch from (minute_start + interval '1 minute' - at_time)))::integer),
            'minute'::text;
        return;
    end if;

    insert into public.ai_extraction_quotas
        (profile_id, window_kind, window_start, request_count)
    values (p_profile_id, 'minute', minute_start, 1),
           (p_profile_id, 'day', day_start, 1)
    on conflict (profile_id, window_kind, window_start)
    do update set request_count = public.ai_extraction_quotas.request_count + 1;
    update public.ai_extraction_budget
    set window_start = day_start, request_count = aggregate_used + 1 where singleton;
    return query select true, 0, null::text;
end;
$$;

comment on function public.consume_ai_extraction_quota(uuid, integer, integer) is
    'Atomically reserves a DeepSeek attempt against shared UTC-day and per-profile UTC-minute/day quotas.';
notify pgrst, 'reload schema';
