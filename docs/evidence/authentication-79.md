# #79 authentication verification evidence

## October 29, 2026 — implementation preparation

- Andrew requested backend issue #79 only; Flutter authentication stays in #80.
- Reread approved pitch/course requirements, backend ownership, database,
  integration-test and staging documentation. Fetched `origin`: local main and
  origin/main both `e630759`; zero commits ahead/behind. No pull was required.
- Created `feat/79-supabase-auth-ownership`; preserved the pre-existing untracked
  root `test-results/` directory. Private `.env` was not opened or edited.
- Prepared the [identity/session/environment contract](../authentication.md).
  Andrew requested a handoff for Roel and Kyle; their agreement is pending.
- Added Supabase Auth-server verification plus issuer/audience/lifetime/role/
  subject checks, explicit idempotent profile links and owner-scoped integration.
  Retained demo access requires explicit non-production process configuration.
- Added an additive migration: existing demo profiles, trips, items and events
  stay intact and unassigned. No hosted migration or environment setting has
  been changed. Development project is `vnpkyvtbupnquvirzlzp`; production is
  `zjnuqqtbapbpudsjbpif`.
- First full offline run after the new Auth tests: **693 passed, 106 database
  tests deselected**, 13.29 seconds. Subsequent smoke/verifier changes require a
  final validation run before commit. This is local/offline evidence only.
- Docker/PostgreSQL are unavailable on the current PATH. Disposable Database CI
  is required; no hosted database is used as a substitute. The available GitHub
  CLI currently has no authenticated host; Andrew was asked to log in privately
  so a draft PR and CI evidence can be prepared. No login code/token was requested.
- Final local validation: **719 passed, 106 database tests deselected**, 13.52
  seconds; `python -m pytest -q -c backend/pytest.ini backend -m "not db"`.
  `ruff check backend scripts/smoke_deployed.py`, Python compile checks and
  `git diff --check` passed. Actionlint **1.7.12** validated the scoped workflow
  change successfully. The AI evaluation passed 27/27 extraction cases, 10/10
  content cases and 84/84 extraction field checks; comparison reported no metric
  regression against the committed baseline. Reports remain in ignored
  `backend/test-results/`, not the user's existing root results directory.
- The existing Supabase CLI project-ref file names the development project;
  only that non-secret project reference was inspected. No CLI link, database
  migration, Auth setting, secret or hosted deployment was changed.
- Committed the implementation as [`91929f1`](https://github.com/relax-mode/lagaw/commit/91929f1)
  and pushed `feat/79-supabase-auth-ownership`. A draft PR can be prepared from
  [the published branch](https://github.com/relax-mode/lagaw/pull/new/feat/79-supabase-auth-ownership).
  Git push used the existing Git authentication; the GitHub CLI still needs a
  private login before it can create the PR and inspect Actions. No PR, CI run,
  review, merge or deployment is claimed by this branch publication.

## October 29, 2026 — PR CI and live development acceptance

- Andrew completed private GitHub CLI login. Created [draft PR #92](https://github.com/relax-mode/lagaw/pull/92).
  A fresh fetch found Roel's #55 PR #91 had merged as `bd17ccf` after the earlier
  main check. Integrated current main as `1007440`, preserving both sides of the
  sprint-log-only conflict and leaving Roel's implementation unchanged.
- [CI run 40731191149](https://github.com/relax-mode/lagaw/actions/runs/40731191149)
  passed changed-area detection, Backend, Database and Flutter on `1007440`.
  Backend: **719 passed, 106 deselected**, 15.04 seconds; lint, compile and AI
  baseline comparison passed. Database artifact `trip-integration-results`:
  **106 tests, 0 failures, 0 errors, 0 skips**, including all four new Auth-profile
  creation/race/legacy-collision/interaction tests. Flutter: **104 passed**, web
  build passed. All deployment jobs correctly skipped for the draft PR.
- A guarded read-only development check established that the new profile column
  was absent. The existing SQLAlchemy connection independently passed the known
  development target guard; history contained exactly the three preceding
  repository migration versions. No connection string or credential was shown.
- Rehearsed the exact additive SQL in a transaction and rolled it back. Verified
  schema/history restoration and equality of all existing application rows.
  Then applied `20261029090000_link_verified_auth_profiles.sql` in development
  through that guarded SQLAlchemy connection, recording the matching version,
  name and source in Supabase migration history in the same transaction. No CLI
  link, private `.env`, Auth setting or production database was changed.
  [Migration evidence](authentication-79-development-migration.json) records
  rollback rehearsal, both new constraints, zero assigned legacy Auth links,
  migration source hash and before/after row counts/hashes.
- Development's read-only Auth settings reported email enabled, anonymous sign-in
  disabled, sign-ups enabled and email autoconfirm disabled. Confirmation mail
  delivery and redirect configuration still need Kyle/Roel coordination.
- Executed local FastAPI through ASGI TestClient against **actual development
  Supabase Auth and Data API**, without identity/database substitution. Created
  two confirmed synthetic email/password accounts and one unconfirmed account
  through the admin fixture API; generated passwords and access tokens remained
  solely in process memory. No mail was sent or credentials shared/stored.
- Live checks passed: unconfirmed password sign-in rejected; missing/invalid
  backend tokens rejected; two verified owners could create/update their own
  trips; cross-user GET/PATCH/DELETE and item access returned 404; verified event
  writes/readback worked while other-user history/recommendation input stayed
  isolated; forged owner fields returned 422.
- Removed only the exact created fixture profiles and their trips/events plus
  the three synthetic Auth accounts; verified their absence. All five application
  tables matched complete before/after counts and hashes, including the new Auth
  column: **3 existing profiles, 10 locations, 7 trips, 3 itinerary items, 0
  interactions** remained unchanged. [Live acceptance evidence](authentication-79-development-acceptance.json)
  records safe fixture IDs, method and limits. This is development backend
  acceptance, not deployed staging, Flutter, email-delivery or production evidence.
  Genuine expired-session rejection remains covered by isolated automated tests;
  no project token-lifetime setting was changed for acceptance.

## October 29, 2026 — Andrew's interactive local verification

- Andrew reported two reusable development Auth accounts ready; passwords remain
  private with Andrew. Started local FastAPI on `127.0.0.1:8000` after guarding
  its existing Supabase configuration against the development project. Selected
  Supabase Auth through the process environment; private `.env` was unchanged.
- Andrew ran `backend/verify_auth.py --api-url http://127.0.0.1:8000` and supplied:

  ```text
  PASS: Missing and invalid tokens rejected.
  INFO: Test account A profile UUID: 32e75bf5-a314-4e98-bc49-6a2ea7eb8173
  INFO: Test account B profile UUID: 72e23403-1ad4-4ee3-b2f9-049e29e1c3aa
  PASS: Two verified owners can create/update trips; cross-user reads/writes/items return 404.
  PASS: Exact temporary trips removed; both accounts' existing trips preserved.
  PASS: Development Auth verified. Test profiles retained; production was not contacted.
  ```

- Recorded this as Andrew-reported interactive HTTP verification. Independently
  checked development only: both exact profile UUIDs exist, their Auth links are
  non-null and distinct, their profile IDs differ from their Auth subjects, and
  no `Issue79*` verification trips remain for either profile. No passwords or
  tokens were requested, retrieved or included in the evidence. The two reusable
  profiles intentionally remain; they are separate from the earlier temporary
  fixtures that were removed after automated live acceptance.
- Final implementation/evidence head `39f480a` passed all required checks in
  [CI run 40732759940](https://github.com/relax-mode/lagaw/actions/runs/40732759940).
  PR #92 remains draft and mergeable, with no published reviews or comments at
  this check. Roel/Kyle agreement and deployed acceptance remain pending.

## Required evidence before completion

| Requirement | Status |
| --- | --- |
| Final offline lint/regression/AI evaluation | Passed locally; 719 offline tests, no AI regression |
| Disposable migration + real PostgreSQL/PostgREST Auth mapping/isolation tests | Passed: [run 40731191149](https://github.com/relax-mode/lagaw/actions/runs/40731191149), 106 DB tests |
| Roel agrees #80 token/confirmation/refresh contract | Handoff prepared; agreement pending |
| Kyle agrees/configures development Auth + environment smoke accounts | Handoff prepared; confirmation pending |
| Development migration and two-account verified acceptance | Passed; linked migration/live acceptance JSON above; exact fixtures cleaned |
| Candidate deployed staging acceptance, with safe result links | Not run |
| Reviewed PR, required CI and merge | Draft #92; CI passed; teammate review and merge pending |
| Production migration/configuration after development acceptance | Not performed |
| Deployed production acceptance and cleanup | Not run |

Do not mark #79 complete from offline tests alone. Add actual commit/PR/run links,
safe results, migration versions and provenance as these steps occur. Never add
passwords, access/refresh tokens, API keys or email confirmation links.
