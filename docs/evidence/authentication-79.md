# #79 authentication verification evidence

Backend delivery: **reviewed, merged and deployed**, with development first,
then deployed staging and production verification. [PR #92](https://github.com/relax-mode/lagaw/pull/92)
merged as `7186a08`; [main run 40739574662](https://github.com/relax-mode/lagaw/actions/runs/40739574662)
passed every check and deployment job. Temporary fixtures were cleaned and the
production promotion policy restored. Flutter #80 and teammate acknowledgment
remain explicit follow-up at Andrew's direction; no frontend Auth completion is
claimed. Final operational evidence and the SQL-wrapper correction are published
through the separate release-evidence PR.

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

## October 29, 2026 — independent backend rollout preparation

- Andrew explicitly directed #79 to proceed independently of #80 and the pending
  teammate follow-up. Recorded the expected Flutter demo-token 401 limitation;
  no Flutter implementation or frontend acceptance is claimed by this decision.
- Jayperson approved `c818a96`. The documentation update recording Andrew's
  release-order instruction at `6fc3960` caused GitHub to dismiss that approval.
  CI on `6fc3960` passed; one fresh teammate approval on the final preparation
  commit is required. PR #92 is now ready for review, not draft.
- Andrew ran the private staging setup helper and reported every PASS: public
  key/confirmed sign-in/profile verified and all four staging smoke settings
  configured. Independently checked GitHub configuration names only; both secrets
  and both variables are present. No credential values were retrieved.
  [Safe staging setup record](authentication-79-staging-configuration.json)
  records the non-secret profile ID and configured names. Andrew retains his
  private test-account password; the runner reads its environment secret.
- Installed a temporary required reviewer (`aranxshx`) on GitHub's production
  Environment, preserving its protected-branch restriction. Its prior setting
  had no required reviewer. [Hold record](authentication-79-production-hold.json)
  records the reason and restoration requirement. This changes promotion
  control only; no production service, database or credential was changed.
- Prepared [production migration SQL](authentication-79-production-migration.sql)
  with history checks, a development-marker refusal, short timeouts and complete
  existing-row comparisons. Rehearsed its expected refusal against development;
  the transaction rolled back. Production execution is pending and follows
  successful deployed staging verification. The exact original migration had
  already passed disposable CI, development rollback rehearsal and application.
- After reviewed merge, staging can deploy with the configured smoke account;
  production must remain waiting until its migration/configuration and staging
  acceptance are complete. The temporary reviewer rule must be restored after
  the backend rollout. This preparation does not mark #79 complete.

## October 29, 2026 — completed backend deployment and production acceptance

- Jayperson's final approval matched `e80f86f`; all required checks passed.
  Merged PR #92 through the normal reviewed-PR path as `7186a08`. Main CI passed
  **719 backend tests** (11.64 seconds), **106 database tests** (zero failures,
  errors or skips), **104 Flutter tests**, syntax/lint and AI checks, then all
  staging/API/web deployment and smoke jobs.
  [Machine-readable CI record](authentication-79-main-ci.json) links each job.
- [Deployed staging acceptance](authentication-79-staging-acceptance.json) used
  actual HTTPS Cloud Run requests and development Supabase Auth/Data API, without
  identity/database mocks. Missing/invalid auth, unconfirmed password sign-in,
  two-owner trip CRUD/items, interaction history/recommendation isolation and
  rejected owner spoofing passed. Exact temporary accounts/profiles/trips/events
  were removed; all five application tables matched full before/after row hashes.
  Andrew's two reusable development profiles remain intentionally.
- Andrew privately configured production smoke credentials/public key and
  verified two distinct confirmed production identities. Matched reported SQL
  profile IDs to the exact generated plan. The first wrapper attempt failed in
  the pre-change snapshot because generation lost empty-string quotes; no
  migration/profile inserts were reached. Corrected both snapshot templates with
  dollar quoting, validated each on all five development tables, and rehearsed
  the full installed-migration verification path in a rolled-back development
  transaction. The original schema migration was unchanged. Andrew reported
  the successful corrected SQL execution and exact profile mappings in production.
  [Preparation/provenance record](authentication-79-production-preparation.json)
  distinguishes this from direct agent production SQL execution.
- Approved API promotion only after staging acceptance and reported production
  prerequisites passed. The production API's authenticated smoke passed, followed
  by production web deployment/smoke for the same reviewed main merge. Independently
  confirmed the deployed Supabase security scheme, missing-token 401, exact
  production CORS and denial of profile reads with the public key alone; no
  profile rows or credential values were retrieved in that public-key check.
- Andrew ran the production-only verifier with credentials hidden in his
  terminal. [Production acceptance](authentication-79-production-acceptance.json)
  records all PASS lines and exact expected profile IDs: two verified owners
  could create/update their own trips, cross-user GET/PATCH/DELETE/item requests
  returned 404, exact temporary trips were removed and both accounts' existing
  trip histories matched their baselines. Reusable production profiles remain
  for safe smoke/acceptance use. Production interaction events were not created;
  live interaction write/isolation coverage passed in staging, plus isolated CI.
- Restored the prior production Environment policy after the entire workflow
  and production ownership acceptance passed: no required reviewer, existing
  protected-branch restriction retained. [Hold/restoration record](authentication-79-production-hold.json)
  captures both phases. Later main changes again use the existing automatic
  staging-to-production promotion flow.
- Private `.env` and the pre-existing root `test-results/` remained unchanged.
  No credentials, tokens or email confirmation links are included. Real email
  delivery/Flutter session journeys and teammate acknowledgment are deferred to
  #80/operations handoff at Andrew's instruction. Genuine expired-token rejection
  was covered in isolated tests; no live token-lifetime setting was shortened.

## Delivery status and explicitly deferred follow-up

| Requirement | Status |
| --- | --- |
| Final offline lint/regression/AI evaluation | Passed locally; 719 offline tests, no AI regression |
| Disposable migration + real PostgreSQL/PostgREST Auth mapping/isolation tests | Passed: [run 40731191149](https://github.com/relax-mode/lagaw/actions/runs/40731191149), 106 DB tests |
| Roel agrees #80 token/confirmation/refresh contract | Handoff published; acknowledgment deferred by Andrew to #80 |
| Environment Auth smoke configuration | Both environments configured by Andrew; Kyle operations handoff deferred |
| Development migration and two-account verified acceptance | Passed; linked migration/live acceptance JSON above; exact fixtures cleaned |
| Deployed staging acceptance, with safe result links | Passed; live HTTPS/interaction/cleanup evidence above |
| Reviewed implementation PR, required CI and merge | #92 approved on final head, merged `7186a08`; main checks/deployments passed |
| Production migration/configuration after development/staging acceptance | Reported SQL PASS matched plan; both environments' smoke configuration verified |
| Deployed production acceptance and cleanup | Passed; both owner histories preserved and exact temporary trips removed |
| Temporary production promotion hold | Restored to previous reviewer policy after successful rollout |

The backend delivery is supported by reviewed merge, main CI, actual staging and
production deployment and ownership evidence above. This does not claim Flutter
or email-delivery acceptance or teammate agreement that was not recorded.
Never add passwords, access/refresh tokens, keys or confirmation links.
