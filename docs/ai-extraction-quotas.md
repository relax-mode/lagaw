# #114 — Paid extraction quotas

The authenticated `POST /api/v1/preferences/extract` endpoint first verifies a
Supabase session, resolves its server-owned `public.users.id` profile UUID, then
reserves quota through `public.consume_ai_extraction_quota`. It only calls DeepSeek
after a successful reservation. Client-supplied IDs and network IP addresses do
not select the quota owner. This does not change the confirmation-only extraction
response or write trip preferences.

## Limits and behavior

- Defaults: **5 attempts per UTC minute** and **40 attempts per UTC day** per profile.
- Optional, nonsecret backend settings: `AI_EXTRACT_PER_MINUTE` (1–10) and
  `AI_EXTRACT_PER_DAY` (1–200). Invalid settings return safe HTTP 503, not unlimited access.
- The PostgreSQL RPC obtains a transaction-scoped per-profile advisory lock and
  checks both counters before incrementing both. It applies to all Cloud Run instances.
- Windows follow the database clock, not client clocks: e.g., daily reset at
  **00:00 UTC** (08:00 in the Philippines). A minute window resets on the next UTC minute.
- A reservation counts even on DeepSeek failure, timeout or malformed output.
  This is intentional: requests that may incur a charge cannot be refunded reliably.
  There are **no automatic provider retries**.
- Excess requests return HTTP **429**, `Retry-After` (seconds), and:
  `{"detail":{"code":"extraction_quota_exceeded","message":"Preference extraction limit reached. Try later.","manual_fallback":true}}`.
  This is separate from a provider-originated 429 (`extraction_rate_limited`).
- Database/RPC failure or invalid configuration returns HTTP **503** with a
  generic `extraction_unavailable` and manual fallback, **before a provider call**.
- These count-based quotas bound the number of attempts, **not exact monetary spend**.
  Provider token costs can vary; monitor provider billing separately.

## Permissions, deployment, rollback

The additive migration `20261103090000_ai_extraction_quotas.sql` creates a
private, RLS-enabled counter table and RPC. Direct `anon` and `authenticated`
table access and RPC execution are revoked. Only the backend's `service_role`
may reserve attempts. Never expose that credential in Flutter, log it, or add it
to a feature flag. Run this migration **in development first**, check PostgREST
schema reload and real session-based requests, then obtain explicit approval
before a production schema change or merge. The backend deliberately fails closed
when the RPC is missing, preventing an unbounded paid call during a staggered rollout.

Back up the migration state before production promotion. Roll back the backend to
the previous reviewed Cloud Run revision if necessary **only with a conscious
decision about removal of rate limiting**; the additive table/function can remain
in place harmlessly. Do not delete quota rows or downgrade controls simply to
restore extraction. Keep staging checks and normal CI/CD gates enabled.

Offline tests mock DeepSeek and PostgREST. Database concurrency and grant checks
require the disposable PostgreSQL/PostgREST CI service; mocked checks alone do not
prove a deployed or production quota.
