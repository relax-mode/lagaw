# Staging deployment investigation — October 25, 2026

Status after recovery work: staging backend repaired and verified; Kyle replaced the GitHub Cloudflare token. Reviewed CI deployment and Pages/browser acceptance remain pending. Initial observations below preserve the pre-recovery state; the recovery follow-up records subsequent changes. Related backlog: [#30](https://github.com/relax-mode/lagaw/issues/30), [#31](https://github.com/relax-mode/lagaw/issues/31), and [#58](https://github.com/relax-mode/lagaw/issues/58).

## Scope and evidence

Inspected fetched `origin/main` at `708707f170c18009a9641b61580d8d43f0d286d7`, the workflow, staging runbook, pipeline documentation/metrics, sprint history, approved pitch/course requirements, GitHub issues, Actions logs, repository/environment configuration, and Cloud Run service metadata. The working branch was 34 commits behind remote main, with existing uncommitted changes; it was not pulled, reset, or switched. Live HTTP checks ran around 04:32–04:34 UTC (12:32–12:34 Singapore time).

No credential values were opened or printed. GitHub secrets were inspected by name/update time only; Cloud Run environment metadata was restricted to variable names and Secret Manager reference names/versions. No secrets, infrastructure settings, deployments, GitHub issues, or environment policies were changed.

## Immediate failure: Cloudflare rejects the deploy credential

Two main-branch runs reached `Deploy staging Flutter Web` and failed:

- [Run 39743812096](https://github.com/relax-mode/lagaw/actions/runs/39743812096/job/119707890863), commit `2cde152`; its deploy executed October 24 after the run was originally created October 22.
- [Run 40098046876, attempt 3](https://github.com/relax-mode/lagaw/actions/runs/40098046876/attempts/3), commit `708707f`; latest staging job [120909855204](https://github.com/relax-mode/lagaw/actions/runs/40098046876/job/120909855204), failed October 24 at 15:25 UTC. Earlier attempts of this run also failed staging.

Both logs report:

```text
A request to the Cloudflare API (/accounts/***/pages/projects/lagaw) failed.
Authentication error [code: 10000]
A request to the Cloudflare API (/accounts) failed.
Invalid access token [code: 9109]
```

Backend, PostgreSQL, and Flutter validation passed. The staging backend deployed successfully, its location smoke test passed, and staging Flutter Web built using `https://lagaw-api-staging-i5kvldluga-as.a.run.app`. Wrangler failed before publishing the Pages deployment. The later web smoke step therefore did not run.

`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` exist as repository Actions secrets, last updated October 15. The staging environment has no secret overrides. The workflow uses these repository credentials for both staging and production Pages uploads. Their presence passes the workflow's nonempty check but does not prove validity. Local `npx --no-install wrangler whoami` independently returned `9109`; this does not establish that local authentication and CI use the same credential.

The evidence establishes a rejected Cloudflare deploy credential. It does not identify whether the token expired, was revoked, was copied incorrectly, or has unsuitable account access/restrictions. GitHub owner access cannot reveal an Actions secret's stored value or provide Cloudflare account authority. The sprint log identifies Kyle as the Cloudflare account/token holder.

## Live checks

| Check | Observed result |
| --- | --- |
| `https://staging.lagaw.pages.dev` | HTTP 404 |
| `https://lagaw.pages.dev` | HTTP 200; browser interaction not tested |
| Staging API `GET /locations?limit=1`, with staging Origin | HTTP 200, one location, exact `access-control-allow-origin: https://staging.lagaw.pages.dev` |
| Staging API Trip POST preflight, requesting Authorization/Content-Type headers | HTTP 200, staging origin and required methods/headers allowed |
| Staging API `GET /api/v1/trips`, without a bearer token | HTTP 503, `Trip demo context is not configured.` |
| Production API `GET /locations?limit=1` | HTTP 200, one location |

The staging service serves image `api:staging-708707f170c18009a9641b61580d8d43f0d286d7`, ready revision `lagaw-api-staging-00004-b7n`, with 100% traffic. Its runtime identity is the dedicated staging runtime account. Supabase references are `STAGING_SUPABASE_URL:2` and `STAGING_SUPABASE_SERVICE_ROLE_KEY:2`. These metadata checks do not prove database write isolation; that acceptance remains pending.

The absent web deployment and authentication failure explain the observed staging 404. The current workflow's `--project-name lagaw --branch staging` matches the expected branch alias; the failure happens before that alias can receive the build. There is no evidence here that changing DNS, CORS, or Flutter's API URL would repair this publishing failure.

## Separate blocker: staging Trip demo configuration is absent

The staging Cloud Run service lists only these environment names:

- `CORS_ALLOWED_ORIGINS`
- `SUPABASE_URL` (staging Secret Manager reference)
- `SUPABASE_SERVICE_ROLE_KEY` (staging Secret Manager reference)

It has neither `TRIP_DEMO_TOKEN` nor `TRIP_DEMO_USER_ID`. In `backend/app/trips.py`, `get_trip_user` validates those settings before checking the request bearer token, explaining the live 503 even without credentials. A correctly configured service should reject that unauthenticated request with 401 instead.

The staging workflow builds Flutter with only `--dart-define=API_BASE_URL=...`. It omits `TRIP_DEMO_TOKEN`, whose default in `frontend/lib/config.dart` is empty; `TripService` uses that setting for its bearer header. The production frontend job supplies the token, but staging rebuilds its own bundle instead of using that artifact. Fixing the Cloudflare credential alone will therefore not enable staging Trip CRUD.

The staging API smoke check covers locations only, and the Pages check covers an HTTP page response. Neither detects missing Trip demo configuration.

## Configuration and documentation drift

- `STAGING_DEPLOY_ENABLED=true` is set. The current GitHub `staging` environment allows protected branches, but its API response contains only a branch-policy protection rule; no required-reviewer rule is currently present. The runbook and historical sprint entries describe an `aranxshx` approval requirement. Approval is not the current blocker: the deploy job actually executed and reached Cloudflare.
- The current workflow deploys staging on qualifying main pushes and reserves manual dispatch for production; PRs run checks only. This agrees with current `PIPELINE.md` and issue #31 but conflicts with the approved pitch's automatic production/PR-preview plan and the course's deploy-on-merge requirement. This conflict was already flagged under Sprint 3/#58 and needs an explicit reconciliation.
- The staging runbook's statement that Pages has not deployed remains consistent with the observed failure, but its waiting-for-approval explanation does not describe the later authentication failure.
- Issue #30 remains open appropriately: web availability, full application operation, and database write-isolation acceptance are incomplete.

## Recovery order

1. Kyle, or another authorized member of the Cloudflare account owning Pages project `lagaw`, should validate or replace the deploy token. Use **Account → Cloudflare Pages → Edit**, limited to the owning account, and verify that `CLOUDFLARE_ACCOUNT_ID` refers to that account. Cloudflare's [Direct Upload CI guide](https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/) documents these permissions and secret names. Store the replacement directly in GitHub Actions secrets without pasting it into an issue, command transcript, or chat. Both production and staging currently consume the repository secret.
2. Configure a staging-only demo token and a demo user that exists in the development/staging database. Make the staging runtime able to read its token, wire the required user setting into Cloud Run, and pass the matching token to the staging Flutter build. Follow the existing public-demo-token design; do not put production backend credentials into Flutter.
3. After credential repair, retry the failed main push run to exercise the existing staging path. `gh run rerun 40098046876 --failed` retries the failed work under that original push event; it may also redeploy the staging API. **Do not use `gh workflow run ci.yml` as a staging retry: current manual dispatch targets production.** Workflow changes for Trip configuration require a reviewed PR and passing CI before a qualifying main push deploys them.
4. Verify the stable staging alias returns 200, location browsing works in a browser, Trip operations succeed, writes reach only development/staging, and production remains functional. Use the stable staging alias for browser checks because it is the configured API CORS origin.
5. Record the successful run and isolation evidence under #30, update the runbook/environment-policy description, and add a meaningful Trip deployment smoke check so a location-only success cannot stand in for a working Trip demo.

No recovery action above was executed during this investigation. Staging remains unresolved until a valid Cloudflare credential is available and the missing application configuration is supplied.

## Recovery follow-up — October 25, 2026

The user authorized staging configuration and a safe recovery commit after the investigation. Work started on a new worktree/branch `fix/staging-recovery`, based on fetched main `708707f`; the original working tree and its unrelated edits were preserved.

### Wrangler authentication correction

Running pinned Wrangler from a neutral directory, without repository dotenv loading, successfully authenticated using Kyle's saved OAuth session and listed Pages project `lagaw` on account `9582ca1b33f83b4cdf83e129340c03d7`. Thus the earlier local `whoami` failure came from a repository-local token override; it did not establish an invalid saved OAuth login. No secret file was opened or edited to reach this conclusion.

The valid OAuth credential was handed directly between subprocesses for a token-management check, with no credential output. `GET /user/tokens` returned HTTP 403, code `9109`, unauthorized for that resource. The CLI can manage Pages but cannot manage the CI token with this session. The user was asked to replace the existing GitHub `CLOUDFLARE_API_TOKEN` secret directly using a new account-scoped Pages Edit token. The OAuth credential was not copied into GitHub. Cloudflare documents the separate token-creation permissions in its [token provisioning guide](https://developers.cloudflare.com/fundamentals/api/how-to/create-via-api/).

### Completed staging backend repair

- Verified that pinned staging database credentials select the approved development project before any write.
- Created dedicated synthetic profile `16a4e7d4-ed4d-58fb-af4b-ded3c32ca95c`, separate from the production demo profile.
- Generated a new staging demo token without printing it. Stored it in Secret Manager `STAGING_TRIP_DEMO_TOKEN:1` and the GitHub `staging` environment secret of the same name. Set the staging environment variable `STAGING_TRIP_DEMO_USER_ID` to the synthetic profile UUID.
- Granted the staging runtime account Secret Accessor on that token alone. Its existing two Supabase secret grants remain intact.
- Added only `TRIP_DEMO_USER_ID` and the pinned token reference to the existing staging service. Ready revision is now `lagaw-api-staging-00005-pkz`, using the existing main image.
- Authenticated Trip list/create/retrieve/update/delete all passed against the live API. Direct development-database lookup confirmed the temporary trip was saved there; exact cleanup removed it. The dedicated demo profile remains for staging use.
- Production ready revision remained `lagaw-api-00007-hfl` throughout setup.

### Prepared workflow repair

Only the staging deployment job changes: it requires the new staging settings, persists them on backend deployment, passes the staging token to Flutter, and invokes `scripts/smoke_staging.py`. The script makes GET requests only, checks locations and unauthenticated/authenticated Trips with staging CORS, checks returned owner IDs, and refuses production API URLs before sending credentials. Production jobs, triggers, database verifier steps from #26, and application source remain intact.

The runbook now describes the live environment policy without claiming a required reviewer that is absent. No protection settings were changed. The approved pitch/course deployment-policy discrepancy remains a separate follow-up under #58.

For CI recovery, merge the reviewed recovery PR and use its new main push run. Rerunning old run `40098046876` cannot apply the new workflow or staging Flutter token wiring. If a retry is necessary after token replacement, use `gh run rerun <recovery-main-push-run-id> --failed`, then `gh run watch <recovery-main-push-run-id> --exit-status`. Manual workflow dispatch currently targets production.

### Credential update and validation

Kyle confirmed replacing the GitHub Cloudflare token. Secret-name-only metadata confirmed that the existing `CLOUDFLARE_API_TOKEN` was updated at 04:47:59 UTC on October 25. No differently named Cloudflare demo secret was added. GitHub does not expose its stored value for a local API check; the next reviewed main-push staging run must validate it.

Validation completed locally after incorporating PR #61: 141 backend pytest tests passed (135 from current main plus six new deployment smoke regressions); Ruff passed; Actionlint passed with shellcheck disabled because it is not installed; and the deployed read-only smoke script passed against the repaired staging API. Separate negative checks confirmed production URLs, missing tokens, and an invalid owner are rejected before network access. The existing Starlette HTTPX deprecation warning remains non-fatal.

Local Flutter tests/analysis stopped at dependency resolution: installed Flutter 3.44.2 supplies Dart 3.12.2, while the repository requires Dart 3.13.5. The project SDK constraint and global SDK were left intact. Supported-Flutter build/tests and the disposable PostgreSQL integration job must pass in PR CI before merge. No release version or tag is part of this infrastructure repair.

### New main merge incorporated

During recovery, PR #61 merged as `57e011dbfd9b76c457693119a3b26615be4d4cdb`, adding recommendation contracts, reproducible fixtures, and 38 tests. The recovery worktree was advanced to that merge before the recovery commit; the additive sprint-log conflict was resolved by retaining both entries. The recovery diff does not alter the recommendation implementation, fixtures, application source, frontend SDK requirement, or README changes from that merge.

Its [main CI run 40163301832](https://github.com/relax-mode/lagaw/actions/runs/40163301832) succeeded, including the existing validation jobs and staging backend deploy. It deployed image `api:staging-57e011dbfd9b76c457693119a3b26615be4d4cdb` as revision `lagaw-api-staging-00006-6cw`. The new authenticated read-only smoke check passed against that revision, proving the repaired demo settings survived the existing deployment workflow. The run skipped `Build staging Flutter Web` and `Deploy staging Flutter Web` because the merge had no qualifying frontend/workflow changes. Its green conclusion therefore does not establish Cloudflare-token validity or staging web availability; the recovery workflow commit must still publish the web build.
