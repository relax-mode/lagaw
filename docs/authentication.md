# Supabase authentication and backend ownership — #79

Status: [draft PR #92](https://github.com/relax-mode/lagaw/pull/92), required CI
and live development backend acceptance passed. Teammate contract agreement,
review, merge and deployed staging/production acceptance remain pending.
Evidence: [authentication verification record](evidence/authentication-79.md).
Flutter screens and session management belong to Roel's #80.

## Proposed contract for Roel and Kyle

This is ready for agreement; it is not a record that either teammate has approved
it. Andrew requested preparation of this handoff on October 29, 2026.

| Boundary | Contract |
| --- | --- |
| Sign-up/sign-in | Flutter uses Supabase Auth email/password only and that environment's public publishable/anon key. Application data continues through FastAPI. No backend password/session storage. |
| Confirmation | Enable email confirmation. Sign-up can return a user with no session: show confirmation instructions and do not call protected APIs yet. Backend requires the Auth server's `email_confirmed_at`. |
| API token | `Authorization: Bearer <session.accessToken>` on every trip, item, recommendation, generation, interaction and extraction request. Never send the refresh token to FastAPI. |
| Identity | Supabase `user.id`/JWT `sub` identifies the Auth account. `public.users.id` is the application profile ID and can differ. Flutter must not supply either as the owner. Existing request bodies/response schemas stay the same. |
| Missing/invalid/expired token | HTTP 401 with `WWW-Authenticate: Bearer`. Flutter refreshes through the Supabase SDK; if refresh fails, clear the session and show sign-in. Do not retry indefinitely or fall back to a demo token. |
| Write retries | Refresh proactively. If a write received 401, authentication failed before the operation, so one retry after successful refresh is safe. After timeout/network loss, reload first; do not automatically repeat a potentially committed create/generation. |
| Unconfirmed email | HTTP 403, `detail.code=email_confirmation_required`; show confirmation instructions. |
| Existing profile conflict | HTTP 409, `detail.code=profile_link_required`; show a support/review message. Do not retry linking or assign old trips in Flutter. Other 409 bodies retain their existing trip/generation meanings. |
| Auth/profile outage | HTTP 503 with a safe message. Retain the session, offer retry, and do not interpret an outage as a bad password. |
| Ownership | Other-owner resources return the same 404 as missing resources. Client owner fields remain forbidden. Extra owner headers/query parameters grant no authority. |
| Public locations | Existing unauthenticated `/locations` behavior is retained. |

Roel: apply the token to #34/#53/#54/#55/#56 calls as well as trip CRUD and #52
interactions. Replace compiled `TRIP_DEMO_TOKEN` in the normal journey in #80;
refresh/expiry handling must be shared across these calls. This PR implements no
Flutter screen or session changes. `ROEL_START_HERE.md` remains the #56 payload and
replacement-confirmation reference; this document supersedes its demo Auth setup.

Kyle: agree Auth enablement, confirmation mail delivery/rate limits, exact web
redirect allowlists, Android deep links, token lifetime and refresh settings in
each project with Roel. Do not turn off confirmation to make a smoke test pass.
No production setting is inferred from development settings. Disable anonymous
sign-in and leave social providers outside this first version. The backend's
confirmed-email check applies even if confirmation is accidentally disabled in a
project. Agree #80's public Auth build configuration separately from server keys.

## Verification implementation

`app/auth.py` reuses `SUPABASE_URL` and the server-only
`SUPABASE_SERVICE_ROLE_KEY`. No signing secret, additional provider credential or
private `.env` edit is needed. The token goes to the configured project's
`GET /auth/v1/user`, the endpoint used by Supabase's `get_user(jwt)` flow.
Supabase verifies its signature and checks the live user/session; this supports
legacy HS256 and asymmetric signing without copying private signing keys.

PyJWT additionally requires and checks issuer (`<SUPABASE_URL>/auth/v1`), audience
(`authenticated`), expiry, issued-at, optional not-before, authenticated role and
a nonzero UUID subject. It accepts HS256/ES256/RS256 headers only. Signature
verification is deliberately delegated to Supabase; locally decoded claims
alone never authorize. The successful Auth response must match the subject and
contain a confirmed, non-anonymous user with an email. Expiry is rechecked after
the network response. Redirects are disabled. Missing/invalid tokens cannot reach
profiles or owner-scoped data. Auth outages fail closed with 503.

References: [Supabase server-side get_user validation](https://supabase.com/docs/reference/python/auth-getuser),
[JWT verification guidance](https://supabase.com/docs/guides/auth/jwts), and
[JWT claims](https://supabase.com/docs/guides/auth/jwt-fields).

## Profile mapping and existing data

Migration `20261029090000_link_verified_auth_profiles.sql` adds nullable, unique,
nonzero `public.users.auth_user_id`. It changes no existing ID, email, preference,
trip, itinerary item or interaction. Multiple legacy NULL links remain valid.
There is intentionally no cascading FK to `auth.users`: profile preservation is
independent of Auth-account lifecycle; account deletion is outside #79.

After verification, the backend finds the profile by `auth_user_id`. If absent,
it inserts a new profile (`name=Traveler`, verified Auth email, generated profile
UUID). An atomic conflict-ignore insert on the unique Auth link makes concurrent
first requests idempotent. It rereads the winner and never overwrites existing
names, tags or budgets. No client metadata chooses a profile. No email or UUID
match grants access to a legacy profile. An existing unique email collision
returns `profile_link_required` and leaves both accounts and all data unchanged.
Email normalization is Supabase's responsibility; this change does not rewrite
existing case-sensitive application emails or sync profile emails on every call.

The existing service-role database credential bypasses RLS. Therefore all trip
and interaction reads/writes continue filtering by the verified **profile** ID,
and response ownership is checked. Item operations first check the parent trip;
generation passes the verified owner into the existing transactional RPCs. Auth
does not grant direct Flutter access to application tables.

### Reversible legacy/demo transition

1. Preserve legacy profiles and their current trips/items/interactions. The
   migration leaves their Auth links NULL. Normal real users do not see them.
2. Keep an environment-specific backup and record migration version and row
   counts before applying the additive migration. Never reset hosted databases.
3. No bulk migration, email-based claiming, automatic cleanup or trip transfer
   is included. Any future claim needs an explicit reviewed decision naming the
   exact Auth subject, profile and records, with before/after evidence and inverse
   SQL. A UUID/email coincidence is insufficient.
4. Roll back application traffic to the prior revision with its corresponding
   frontend if required; leave the additive column and all records in place.
   Old code ignores the column. Old demo-based production code has the old shared
   access limitation, so restrict access during such an emergency rollback.
5. A schema rollback is normally unnecessary. If later explicitly approved,
   export the exact new Auth-to-profile mappings first and stop authenticated
   writes, then remove the new constraints/column in a **new reviewed migration**.
   Retain profiles/trips/events and the export for restoration; dropping the
   mapping without an export loses the account association. Do not edit applied
   migrations or delete profiles to resolve an email conflict.

## Explicit non-production demo access

The default `TRIP_AUTH_MODE=supabase` ignores old demo settings completely.
`TRIP_AUTH_MODE=demo` is an explicit process-only opt-in for synthetic fixtures,
the known development project `vnpkyvtbupnquvirzlzp`, or HTTP loopback. It replaces
Auth for that process; it does not coexist as a fallback. Production
`zjnuqqtbapbpudsjbpif` and other hosted projects refuse demo mode with 503.
The demo UUID/token checks remain in place. Do not use this mode for real users
or claim it proves Supabase verification. Existing CRUD/AI fixture suites and
development-only legacy verifiers explicitly select it; the new Auth suites
exercise the verified path separately. No deployed service is configured to use
demo mode by this change.

## Development first: exact sequence

| Environment | Supabase project | API |
| --- | --- | --- |
| Development/local and staging | `vnpkyvtbupnquvirzlzp` | local FastAPI or `lagaw-api-staging` |
| Production | `zjnuqqtbapbpudsjbpif` | `lagaw-api` |
| Automated database tests | disposable loopback `lagaw_test` | local PostgREST only |

1. Finish offline and disposable PostgreSQL/PostgREST CI. Do not use hosted
   credentials in either suite. Keep this PR draft until coordinated release
   prerequisites are ready.
2. In **development**, review the additive migration and back up relevant data.
   With the CLI explicitly linked to the development project, inspect
   `npx supabase db push --dry-run`; only then apply the reviewed new migration
   through the team's migration process. Check migration history. Never use
   `db reset` on a hosted project or apply unreviewed SQL in production.
3. Kyle configures development email/password Auth, confirmation/redirects and
   two dedicated confirmed-email test accounts. Use safe test accounts; never
   share their passwords, access/refresh tokens or confirmation links in chat.
4. Start the local backend with the current development credentials, preserving
   `.env`. From the repository root, in a separate PowerShell terminal:

   ```powershell
   $env:TRIP_AUTH_MODE = 'supabase'
   .\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000
   ```

5. In another terminal, run the guarded verifier:

   ```powershell
   .\.venv\Scripts\python.exe backend/verify_auth.py --api-url http://127.0.0.1:8000
   ```

   It consumes existing backend configuration without editing it, refuses
   production before account prompts/network access, and prompts for two safe
   test-account credentials with hidden input. It checks missing/invalid auth,
   real verified sessions, two-owner CRUD/item isolation, exact temporary-trip
   cleanup and before/after equality of each account's existing trips. New test
   profiles remain intentionally. A lost create response can prevent learning a
   fixture ID; inspect only that account's uniquely titled `Issue79 verification`
   trip for exact recovery. Never delete shared data to clean a verifier run.
6. Record only PASS/FAIL, commit, API host, migration version and safe fixture
   IDs. Record failed cleanup and resolve it before retrying. Invalid/expired,
   two-user interaction and legacy-data preservation coverage also run in the
   isolated automated suites. Repeat deployed verification on staging using
   `--api-url https://lagaw-api-staging-i5kvldluga-as.a.run.app` after deploying
   the reviewed candidate with Kyle. Do not run the old main recovery dispatch:
   it deploys production, not a feature-branch staging candidate.
7. After development/staging evidence passes, coordinate production migration,
   #80 readiness, production Auth settings, a production-only synthetic acceptance
   account and CI smoke settings with Kyle. Production acceptance follows
   reviewed merge/deployment and the same ownership/error matrix, with exact
   fixture cleanup; the development-only verifier deliberately refuses production.

## CI and release coordination with Kyle

The existing offline Backend job and disposable Database job collect the new
tests automatically. `test_auth.py` uses synthetic signed tokens and a fake Auth
server that verifies signatures. `tests/integration/test_auth_ownership.py`
substitutes only the external Auth identity, retaining real PostgreSQL/PostgREST
profile creation, uniqueness/race behavior, owner-scoped CRUD, interaction
isolation and preservation. It uses the existing fail-closed loopback fixture
guard and exact cleanup. Existing legacy fixture tests remain explicit demo
tests, not evidence of real-user identity.

The scoped workflow update sets backend `TRIP_AUTH_MODE=supabase` and removes
backend demo owner/token injection. Its smoke script signs in to a fixed
environment-specific Supabase Auth host on each run, then checks the deployed
API with that short-lived token. No account password or token reaches output.
Redirects are refused. Smoke checks create no trips/events and call no AI
provider; the first call can create the dedicated account's profile.

Kyle must provision the following independently in **each** GitHub Environment
(`staging`, then `production`), before enabling the release:

| Kind | Name | Purpose |
| --- | --- | --- |
| Environment secret | `SMOKE_AUTH_EMAIL` | Dedicated, confirmed synthetic account in that environment |
| Environment secret | `SMOKE_AUTH_PASSWORD` | Its password; holder Kyle |
| Environment variable | `SMOKE_SUPABASE_KEY` | That project's public publishable/anon key for Auth sign-in |
| Environment variable | `SMOKE_PROFILE_ID` | The verified account's application profile UUID, not its Auth subject |

Existing Secret Manager Supabase URL/server-key settings remain separate for
staging and production. The smoke script has fixed Auth hosts for both projects,
so it cannot silently send credentials to an arbitrary configured host. Account
rate limits/confirmation mail delivery remain operational dependencies. Backend
authentication itself has a live Supabase Auth dependency and fails closed when
it is unavailable; no local-signature-only fallback is introduced.

**Release blockers:** do not merge/deploy to production before #80's normal
authenticated Flutter flow is ready, development acceptance passes, both target
schemas are ready under the agreed release plan, and Kyle provisions smoke
accounts/settings. The current pipeline automatically promotes a successful
main staging deployment to production. A staging pass alone is not an approval
to prepare production later. Existing Flutter demo build flags are left to #80;
they no longer authorize the new normal backend. No production change has been
made as part of preparing this implementation.
