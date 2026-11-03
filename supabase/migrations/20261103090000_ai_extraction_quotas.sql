-- #114: atomic, shared extraction quotas (UTC windows) for the verified profile UUID.
-- The backend alone calls this RPC with a server-derived public.users.id.
-- All operations share one database transaction and an advisory lock per profile.
create table public.ai_extraction_quotas (
    profile_id uuid not null references public.users(id) on delete cascade,
    window_kind text not null check (window_kind in ('minute', 'day')),
    window_start timestamptz not null,
    request_count integer not null check (request_count between 1 and 200),
    primary key (profile_id, window_kind, window_start)
);

alter table public.ai_extraction_quotas enable row level security;
revoke all on public.ai_extraction_quotas from public, anon, authenticated;
grant select, insert, update, delete on public.ai_extraction_quotas to service_role;

create function public.consume_ai_extraction_quota(
    p_profile_id uuid, p_per_minute integer, p_per_day integer
)
returns table (allowed boolean, retry_after_seconds integer, exhausted_window text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
    at_time timestamptz;
    minute_start timestamptz;
    day_start timestamptz;
    minute_used integer;
    day_used integer;
begin
    if p_profile_id is null or p_per_minute not between 1 and 10
        or p_per_day not between 1 and 200 then
        raise exception 'Invalid extraction quota configuration';
    end if;

    -- This lock is held until both counters are committed. A hash collision
    -- only over-serializes unrelated users; it cannot allow excess requests.
    perform pg_advisory_xact_lock(
        hashtextextended('lagaw:extraction:' || p_profile_id::text, 0)
    );
    at_time := clock_timestamp();
    minute_start := date_trunc('minute', at_time, 'UTC');
    day_start := date_trunc('day', at_time, 'UTC');

    select q.request_count into minute_used
    from public.ai_extraction_quotas q
    where q.profile_id = p_profile_id and q.window_kind = 'minute'
      and q.window_start = minute_start;
    select q.request_count into day_used
    from public.ai_extraction_quotas q
    where q.profile_id = p_profile_id and q.window_kind = 'day'
      and q.window_start = day_start;

    if coalesce(day_used, 0) >= p_per_day then
        return query select false,
            greatest(1, ceil(extract(epoch from (day_start + interval '1 day' - at_time)))::integer),
            'day'::text;
        return;
    end if;
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

    return query select true, 0, null::text;
end;
$$;

revoke all on function public.consume_ai_extraction_quota(uuid, integer, integer)
    from public, anon, authenticated;
grant execute on function public.consume_ai_extraction_quota(uuid, integer, integer)
    to service_role;

comment on function public.consume_ai_extraction_quota(uuid, integer, integer) is
    'Atomically reserves one billable extraction attempt per verified profile, limited by UTC minute/day.';
notify pgrst, 'reload schema';
