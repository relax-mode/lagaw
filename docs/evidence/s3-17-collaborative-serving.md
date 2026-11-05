# S3-17 collaborative-model serving — staged and production acceptance

**Recorded:** November 5, 2026 (Asia/Manila; Cloud Run log times are UTC).  **Issue:** [#94](https://github.com/relax-mode/lagaw/issues/94).  **Implementation:** independently approved and merged [PR #95](https://github.com/relax-mode/lagaw/pull/95).  **Deployment:** [Lagaw CI manual recovery run 41991947345](https://github.com/relax-mode/lagaw/actions/runs/41991947345) — all backend, database, Flutter, dependency-audit, secret-scan, staging, production API and production web jobs **successful**.

## Scope and access controls

All tests used the existing `CyGray`-authenticated `gh` CLI, private operator GCP access and **separately configured** staging/production Supabase service-role credentials; every script checks the expected environment/project. The demo interactions belong to five deliberately created, confirmed Auth users per environment; **not organic users**. No API request performed model training. The training allowlists, credentials, exact-ID manifests, cleanup SQL and artifact bytes stayed outside Git; this report contains no private user, trip, event or Auth UUIDs, passwords, bearer tokens or learned factor values.

## Stage 1 — Staging authenticated acceptance (PASS)

Staging serves 100% traffic from **`lagaw-api-staging-00035-xp9`**, with a mounted and SHA-pinned model. The startup line on Nov 5 at 08:09:31 UTC reports `status=present`, `reason=loaded`, version `signed-svd-v1`, provenance `real`, **5 users / 10 locations / 22 pairs**. `real` here is the model's *data provenance category*, not evidence of organic users: these are seeded demo interactions.

| Same saved trip / options | Authenticated result | Score for the same eligible destination |
| --- | --- | --- |
| Demo account A, deployed staging | HTTP 200; **one `Hybrid:`** item | **0.920360071763** |
| Account A, local content-only FastAPI against staging Supabase, same request | HTTP 200; content-only | **0.996** |
| Demo account E, deployed staging | HTTP 200; **one `Content fallback (insufficient_history)`** item | 0.996 |

The separate local baseline ran with `MODEL_FILE_PATH` and `MODEL_FILE_SHA256` unset and was shut down afterward. No staging model or database write was introduced for the comparison. The hybrid/content score difference is **0.075639928237** in this seeded acceptance scenario. No ranking-quality claim is made from the small demo data.

Staging startup metadata: model version `signed-svd-v1`; training digest `d1e802b4930d913e2c39227ef89d4c63091235970dc98e4a2482aa7305e22f5a`; SHA-256 `76b8f0c974d03bf315d4fa8c374726b3387af96347b815789163bfd3cdff9cb3`; pinned Secret Manager reference `STAGING_MODEL_ARTIFACT:1`. Startup metadata was checked on the **100%-traffic** revision, not merely the latest-created revision.

## Stage 2 — Production-specific training, secret delivery, deployment (PASS)

- Production Supabase catalog preflight: **10 active locations**, **one** with the required known maximum cost. No organic profile was included in the private training allowlist.
- Production-only seed: **5 confirmed synthetic Auth accounts**, **5 profiles**, **23 interaction events**, **2 demo trips** and a 10-item catalog, written through the real owner-scoped API. The private exact-ID manifest and `ROLLBACK` cleanup SQL are retained under the operator's private directory.
- The independent, read-only service-role audit checked all five Auth identities and linked profiles, all 23 individual manifest events, both trips, and **zero interaction events outside the manifest** for those profiles.
- Production-only offline snapshot/training: `signed-svd-v1`, provenance `real` (seeded demo dataset), rank 3; **5 users, 10 locations, 22 distinct user/item pairs**; 23 interaction events read/used; four users meet the minimum-history gate and seven locations meet the per-item support gate.
- Production training digest: `8314445d4d1445699715887c7f3ec9441c1a6fd1900764e7db0357fd55595eba`. Production file SHA-256: `a9eb39b0616949786192e78dbfc16427b6bd47e3bf1e34ef0469334ed16fa780`. Artifact is **3,527 bytes**, below the 64 KiB Secret Manager payload limit.
- Uploaded only to private GCP Secret Manager **`MODEL_ARTIFACT:1`**, separately from staging; readback digest exactly matched the local file. Granted the production Cloud Run runtime service account `roles/secretmanager.secretAccessor` on this secret. Production GitHub environment variables `MODEL_ARTIFACT_SECRET` and `MODEL_FILE_SHA256` pin the numeric version and digest, and the existing workflow mounts the secret under `/secrets/model` (file `/secrets/model/artifact.json`) in the Cloud Run service.
- Normal `main` `workflow_dispatch` [41991947345](https://github.com/relax-mode/lagaw/actions/runs/41991947345) passed **every job**, including the staging-tested backend deployment and production API/web smoke checks. No code or CI skip/force-merge was used for production promotion.

## Stage 3 — Production API, provenance, privacy and rollback checks (PASS)

Production now serves **100%** traffic from **`lagaw-api-00032-287`**, with `MODEL_FILE_PATH` and `MODEL_FILE_SHA256` configured and a Secret Manager volume pinned to `MODEL_ARTIFACT` **version `1`**, mounted at `/secrets/model`. Its revision-scoped startup log at **2026-11-05T08:12:27Z** reports `status=present reason=loaded`, `signed-svd-v1`, provenance `real`, **5 users / 10 items / 22 pairs**, with the **exact production training digest and file SHA-256 above**.

| Same saved trip / options | Authenticated result | Score for the same eligible destination |
| --- | --- | --- |
| Demo account A, **before** production deployment (content-only) | HTTP 200; no hybrid result | **0.996** |
| Demo account A, **after** production deployment | HTTP 200; **one `Hybrid:`** result | **0.920360071763** |
| Demo account E, after deployment | HTTP 200; **one `Content fallback (insufficient_history)`** result | **0.996** |

The comparison uses identical trip/options and matches the same public catalog location. A and E are different authenticated demo owners; inference remains owner-scoped through the original API. Existing mocked backend ownership/fallback tests and full [CI run](https://github.com/relax-mode/lagaw/actions/runs/41991947345) passed. Read-only dataset audit reported **no extra interaction events**. The production secret is **different from staging's** (distinct training/file SHA-256 digests).

**Privacy:** the production artifact remains gitignored and untracked; staging and production private manifests remain outside the checkout. The full 1,062,010-byte CI log of the deployment run and the #94 issue text were scanned against production demo Auth/profile/trip/event identifiers and demo-account passwords; **zero exact matches**. CI Gitleaks also passed. Only counts, score values, digest hashes, public revision names and redacted recommendation modes are reported. The API does not expose artifact selection or run training on inference requests.

**Production cleanup rollback rehearsal (PASS after PAT rotation, November 5):** The operator rotated the expired Supabase Management API personal access token. Fresh **read-only SQL queries** to **both staging and production** returned HTTP 201. Before the rehearsal, production SQL aggregates confirmed **5 Auth users, 5 profiles, 23 manifest interactions, 2 trips, and zero events beyond the manifest**. Static verification checked that the private generated SQL refers to exactly **35 manifest identifiers**, contains only the four expected table-specific `DELETE` statements, begins with `BEGIN`, and ends in `ROLLBACK` (never `COMMIT`). A hosted production SQL transaction returned HTTP 201, with the **in-transaction `auth_users_left = 0`** confirming the temporary deletion path executed. After `ROLLBACK`, a separate read-only SQL query returned **exactly the original counts**, proving the seeded demo accounts and all 23 events/trips remain intact. No permanent deletion was performed. The configuration rollback resolver for model delivery also passed in enabled and disabled modes. To return to content-only later, delete the **two production GitHub variables together**, redeploy using `ci.yml`, verify `not_configured`, then remove the now-unused secret only after Cloud Run has no mount; see [the runbook](../collaborative-model-serving.md#rollback). No live production *model-service* rollback was performed during acceptance; this rehearsal only tested demo-data cleanup under a rolled-back SQL transaction. Follow-up [#158](https://github.com/relax-mode/lagaw/issues/158) records the PAT restoration and transaction evidence.

## Stage 4 — Acceptance interpretation: separate fallback response

The original #94 criterion requested a **hybrid and fallback item in the same response**. This is infeasible with the **current production and staging catalog**: only one active destination has sufficient known cost data and all other candidates fail eligibility before ranking. Rather than inventing production destinations or weaken cost checks, the team tracks the equivalent two-response acceptance: **account A** (sufficient history) must return `Hybrid:` and **account E** (insufficient history) must return `Content fallback (insufficient_history)`, with **identical recommendation options** and separate authenticated responses in *each environment*. Also compare account A's same-trip content baseline with its hybrid response. Both environments have passed the equivalent acceptance today. Future catalog enrichment could allow a same-response mixed-mode test; it is not claimed here.

## Reproduction and outstanding operational hygiene

Use the restricted existing operator commands in [the collaborative serving runbook](../collaborative-model-serving.md) with the private manifests, not data or credentials pasted into issues or CI. Staging and production accounts were tested via `backend/seed_demo_interactions.py recommend`; training used `backend/train_collaborative_model.py` offline; project/version guards remained active. The private cleanup script is reversible and preserves unrelated data by explicit IDs and an extra-event guard. Its **hosted production `ROLLBACK` transaction was successfully rehearsed after the PAT rotation**, with an in-transaction zero Auth-user count and unchanged before/after demo aggregates. The synthetic production demo accounts remain intentionally active while the model is serving. When retiring the model, remove model delivery and verify Cloud Run no longer depends on the artifact before independently authorizing the final exact-ID cleanup (which would be a **different, committed operation**, not part of this rehearsal).
