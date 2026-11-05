# S4-20 — Executed staging API rollback and restoration (2026-11-05)

Issue: [#120](https://github.com/relax-mode/lagaw/issues/120). Existing runbook and dry-run-first helper: reviewed/merged [PR #126](https://github.com/relax-mode/lagaw/pull/126). This is a **real Cloud Run staging traffic drill**, not a simulation. All timestamps are UTC.

## Scope, authorization and guardrails

- The user explicitly requested end-to-end completion of #120, including the staging drill, on 2026-11-05. The operation ran with the operator's authenticated Google Cloud CLI and explicit project `relax-mode-lagaw`, region `asia-southeast1`, service `lagaw-api-staging`. The shell's default project was **not** Lagaw, so every command explicitly named the Lagaw project.
- Only the **staging Cloud Run traffic split** was changed. There were no image builds, revision deletions, database or secret changes, migration operations, or modifications to Cloudflare Pages deployments. Production service `lagaw-api` was read-only.
- The helper's required `ROLLBACK_AUTHORIZED=staging`, `--execute` and exact `--confirm staging:<revision>` guards were used for both changes. A shell exit handler attempted restoration even if intermediate verification failed. The target was never chosen automatically.
- The Pages staging URL was checked for HTTP 200, but a **Pages deployment rollback was not exercised**. No authenticated `smoke_deployed.py` run was performed: this shell did not have the environment-scoped smoke credentials, which are stored for CI.

## Revision selection and compatibility checks

| Field | Pre-drill serving and final restored | Drill rollback target |
| --- | --- | --- |
| Service | `lagaw-api-staging` | `lagaw-api-staging` |
| Revision | `lagaw-api-staging-00035-xp9` | `lagaw-api-staging-00033-hvh` |
| Commit label | `ccf2e383114d17cc349115530b604ffaa29310be` | `ed595abe7b24862e9884bf27ac4f3b152ecc26b6` |
| Image digest (sha256) | `17f8b32c44bb9a49fd6269528f2aab03c29ac7e05c9451e218bd7276d80a34f3` | `ac29d404c4bc4471aaeb9cf6d719ff8a0585a3b21ec277ab3580fd30ed3a2d86` |
| Creation (UTC) | `2026-11-03T06:17:31.999167Z` | `2026-11-01T14:08:53.018624Z` |
| Readiness | `Ready=True`, `ContainerHealthy=True` | `Ready=True`, `ContainerHealthy=True` |

- The rollback helper's `plan` passed: single serving revision at 100%, distinct target, different image digest, same service, no migration warning.
- `git diff --name-status ed595abe7b24 ccf2e383114d -- supabase/migrations/` returned **no changes**. This compares repository migrations between the two commit labels; it is not a live migration-history query.
- Target commit's [Lagaw CI run 41314460309](https://github.com/relax-mode/lagaw/actions/runs/41314460309) reported success, including its staging deploy job.

## Recorded execution

| Event | Time (UTC) | Observation |
| --- | --- | --- |
| Authorization and original state captured | 08:54:46–08:54:51 | Staging `00035-xp9=100%`; production `lagaw-api-00032-287=100%` |
| Pre-drill HTTP smoke | 08:54:52 | Staging locations 200, unauthenticated trips 401, unauthenticated extraction POST 401, staging Pages 200 |
| Rollback command initiated | 08:54:52 | Helper `execute --env staging --to-revision lagaw-api-staging-00033-hvh` |
| Rollback traffic independently observed | **08:55:12** | Staging `00033-hvh=100%` |
| Rolled-back smoke checked | 08:55:13–08:55:14 | All four checks passed with the same expected HTTP statuses |
| Restoration started | 08:55:14 | Explicit `execute --to-revision lagaw-api-staging-00035-xp9`; **not** `restore --to-latest` |
| Restored traffic independently observed | **08:55:36** | Staging `00035-xp9=100%` |
| Post-restoration smoke | 08:55:37–08:55:38 | All four HTTP checks passed |
| Production traffic read again | **08:55:41** | `lagaw-api-00032-287=100%`, unchanged from the start |

Verification covered HTTP status only. `GET /locations?limit=1` returned **200**; unauthenticated `GET /api/v1/trips?limit=1` returned **401**; unauthenticated **POST** `/api/v1/preferences/extract` with `{"prompt":""}` returned **401**; `GET https://staging.lagaw.pages.dev/` returned **200**. The extraction check did **not** invoke DeepSeek. These are externally observable, non-destructive checks, not authenticated full-flow verification.

The first pass (08:52–08:53 UTC) also rolled back and restored traffic, but a test mistakenly issued **GET** to the POST-only extraction endpoint and received HTTP 405. It stopped verification, not the application; the restoration safeguard returned staging to the original revision. The HTTP method was corrected, and the entire drill was repeated with expected statuses at all three stages. The second shell wrapper emitted a Bash cleanup error after printing all successful checks; independent post-drill CLI and HTTP reads confirmed the traffic and service state. Preserve both observations rather than presenting the wrapper exit code as a green test.

## Command pattern and recovery detail

From the repository root, with the explicit Lagaw project and region:

```sh
python3 scripts/rollback_helper.py plan --env staging \
  --to-revision lagaw-api-staging-00033-hvh \
  --project relax-mode-lagaw --region asia-southeast1

ROLLBACK_AUTHORIZED=staging python3 scripts/rollback_helper.py execute \
  --env staging --to-revision lagaw-api-staging-00033-hvh \
  --project relax-mode-lagaw --region asia-southeast1 \
  --execute --confirm staging:lagaw-api-staging-00033-hvh

# Restore the *captured original* revision explicitly, not --to-latest:
ROLLBACK_AUTHORIZED=staging python3 scripts/rollback_helper.py execute \
  --env staging --to-revision lagaw-api-staging-00035-xp9 \
  --project relax-mode-lagaw --region asia-southeast1 \
  --execute --confirm staging:lagaw-api-staging-00035-xp9
```

The distinction matters: there were newer zero-traffic staging revisions (`00038` through `00043`). `--to-latest` could have chosen a **different** revision from the original 100%-serving `00035-xp9`. The drill deliberately preserved the pre-drill serving configuration.

**Outcome:** Cloud Run staging traffic rollback and exact restoration verified, with both stages externally reachable. Production traffic was unchanged by this drill; staging Pages was not redeployed. The authenticated user-flow smoke and Cloudflare Pages rollback remain separate tests, not implied by this evidence.
