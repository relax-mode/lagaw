# Serving the collaborative model (#94)

`POST /api/v1/trips/{trip_id}/recommendations` blends content and collaborative scores
(60% / 40%, see [hybrid-recommender.md](hybrid-recommender.md)) when the backend process
has a valid, version-pinned artifact, and otherwise serves the exact content baseline.
Staging and production each have **their own** artifact trained from **their own**
Supabase project; a staging artifact is never promoted to production.

## What this does and does not show

The artifacts are trained on five seeded demo accounts (23 interactions in staging).
They demonstrate the serving path: startup load, digest pin, `Hybrid:` and
`Content fallback (…)` reasons, and rollback. They are **not** evidence of recommendation
quality; quality claims stay on the labelled synthetic evaluation in
[week3-evaluation.md](week3-evaluation.md) and [evidence/hybrid-results.md](evidence/hybrid-results.md).

**Catalog limit (verified October 29, 2026):** both environments have 10 active locations
and only the Negros Museum has a known `estimated_cost_max`. The content engine fails
closed on an unknown cost, so any trip can currently be offered at most that one place.
A response therefore holds one item: either `Hybrid:` (a supported user) or
`Content fallback (insufficient_history)` (an under-supported user), never both. Item-side
fallbacks (`sparse_location`, `unseen_location`) and several-item reordering are covered
by the offline tests and become visible once more locations have costs.

## How the training snapshot is obtained

Since #79 every API read is owner-scoped: a user's token can only list that user's events,
so the API cannot supply the cross-user matrix a collaborative model needs. Training
therefore uses an **offline, allowlisted read with the existing server credential**
(`SUPABASE_SERVICE_ROLE_KEY`), not a new endpoint or a request-time query.

- **Who runs it:** Kyle (DevOps), who holds the service-role key (Secret Manager
  `STAGING_SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SERVICE_ROLE_KEY`) and passes it through
  the shell environment. The value is never an argument, file, log or commit.
- **What it may read:** only `user_location_interactions` rows for an explicit allowlist of
  seeded demo profile IDs, kept in a private file outside the repository. The command
  refuses a Supabase project that does not match `--environment`, refuses a repository
  path for the allowlist, and writes only to gitignored `backend/model_artifacts/`.
- **Output:** counts, the training digest, the artifact SHA-256, size and model state.
  No identifiers.
- **Never in CI or request handling.** No schedule, no registry, no automatic retraining.
- **Widening to organic users** needs a separate recorded team decision (what is collected,
  notice and consent, retention, who may run it) in `docs/scope-changes.md` and the sprint
  log, plus a review of this document. Until then the allowlist is demo accounts only.

## Seeded demo accounts

`backend/seed_demo_interactions.py` creates five confirmed Auth accounts per Supabase
project (`lagaw-demo-<environment>-a` … `e` at `example.invalid`, random passwords generated
in-process) and writes their swipes and saves through the API with each account's own
access token. Accounts A and E also get a saved trip. Development and staging share one
project, so one set serves both. The plan (`PLAN` in the script) is:

| Account | Role | Distinct places | Purpose |
| --- | --- | --- | --- |
| A | target | 5 (one left swipe) | Clears the 3-place history gate: `Hybrid:` |
| B, C, D | support | 5 each | Give the museum and others ≥2 supporting users |
| E | thin history | 2 | `Content fallback (insufficient_history)` |

The script prints counts only. Everything else goes to `--private-dir` (outside the
repository, `0600`, never overwritten): credentials, an exact profile/event/trip manifest
(`<env>-manifest.json`), the training allowlist, and `<env>-cleanup.sql`.

```bash
export SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… SUPABASE_ANON_KEY=…   # from the shell, not typed in the log
python seed_demo_interactions.py seed --environment staging \
    --api-url https://<staging-api-host> --private-dir ~/.lagaw-private
```

Passwords live in Secret Manager only (`STAGING_DEMO_SEED_CREDENTIALS`,
`DEMO_SEED_CREDENTIALS`); the runtime service accounts have no access to them.

**Cleanup.** `python seed_demo_interactions.py cleanup-sql --environment <env> --private-dir …`
prints exact-ID SQL (events, trips, profiles and Auth users named by the manifest, with
before/after counts and a count of events beyond the manifest). It ends in `rollback;` by
default; add `--commit` to apply. Run it as the `postgres` role in the Supabase SQL editor.
Deleting a profile cascades only to rows that profile owns.

## Training the artifact

```bash
export SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=…
python train_collaborative_model.py --environment staging \
    --profiles-file ~/.lagaw-private/staging-profiles.txt \
    --output model_artifacts/staging-real-svd.json
```

It builds a `real` `TrainingData` snapshot restricted to the active catalog, calls
`train()` and refuses to write if the snapshot is below the global gates (3 users, 3 items,
8 pairs) or the serialized artifact exceeds Secret Manager's 64 KiB limit. Record the
printed training digest and SHA-256 with the environment; they must match the startup log.

## Delivery and wiring

| Item | Staging | Production |
| --- | --- | --- |
| Artifact secret | `STAGING_MODEL_ARTIFACT` | `MODEL_ARTIFACT` |
| Accessor (only) | `lagaw-api-staging-runtime` | the production runtime service account |
| Seed credentials secret | `STAGING_DEMO_SEED_CREDENTIALS` | `DEMO_SEED_CREDENTIALS` |

Upload with `gcloud secrets create … --data-file=model_artifacts/<file>.json`, grant
`roles/secretmanager.secretAccessor` on that secret to that environment's runtime service
account only, and check `gcloud secrets versions access N --secret … | sha256sum` equals the
file's SHA-256 (the stored bytes are exactly what Cloud Run mounts).

Enable it per environment with two **environment-scoped GitHub variables** (GitHub →
Settings → Environments → `staging` / `production`):

| Variable | Value |
| --- | --- |
| `MODEL_ARTIFACT_SECRET` | `SECRET_NAME:VERSION`, a numeric version (never `latest`) |
| `MODEL_FILE_SHA256` | the artifact file's SHA-256, 64 hex characters |

`scripts/resolve_model_delivery.py` (a step in `deploy-staging` and `deploy-backend`)
turns them into a read-only file mount at `/secrets/model/artifact.json` (a dedicated
directory, never under `/app`), `MODEL_FILE_PATH` and `MODEL_FILE_SHA256`. Setting only
one, an unpinned version or a malformed digest fails the deploy before anything changes.
With neither set, the job removes the mount and both variables. The deploy action merges
rather than replaces, so removal is explicit (`--remove-secrets`, `--remove-env-vars`).

A staging deploy runs on a push to `main` that changes the backend, or on a manual run of
the CI workflow on `main`. Production follows staging for a push and has the same manual run.

## Startup behavior

The model loads once, during application startup (before the first request), and logs one
line with no identifiers:

```text
recommendation_model status=present reason=loaded version=signed-svd-v1 provenance=real training_digest=<64 hex> users=5 items=10 pairs=22 file_sha256=<64 hex>
```

`status=absent` lines carry a `reason`: `not_configured` (no path, normal content-only),
`missing`, `unreadable`, `too_large`, `corrupt`, `wrong_version`, `invalid_artifact`,
`provenance_mismatch`, `digest_mismatch` or `invalid_expected_digest`. Every absent case
serves the content baseline with HTTP 200; none can produce a 5xx. A pin mismatch is
checked before the file is parsed. Absent-with-a-path is logged at WARNING so it stands out.

## Retraining, rotation and rollback

- **Retrain** after demo data changes: run the training command, upload a new secret
  **version**, set `MODEL_ARTIFACT_SECRET` to the new version and `MODEL_FILE_SHA256` to
  the new digest, redeploy. Old versions stay available until the new one is verified.
- **Rotate** the demo accounts by running cleanup (rollback first), reseeding, retraining
  and replacing the secret version as above. The service-role key is rotated through its
  existing Secret Manager process; the artifact does not contain it.
- **Roll back**: delete both variables in the environment and redeploy. The job removes the
  mount and `MODEL_FILE_PATH` / `MODEL_FILE_SHA256`, and the log reads `reason=not_configured`.
  Cloud Run drops the now-unused volume entry on the *next* deploy, and while it exists the
  deploy still needs the secret; so do not delete the secret or revoke its accessor binding
  until one more deploy has completed.
- **Emergency** (variables cannot be changed): `gcloud run services update <service>
  --remove-secrets=/secrets/model/artifact.json --remove-env-vars=MODEL_FILE_PATH,MODEL_FILE_SHA256`.

## Verification commands

`seed_demo_interactions.py recommend --environment <env> --api-url <url> --account A|E
--output <file>.json` signs in as the demo account, calls the trip's recommendations
endpoint and writes a response with only the trip ID redacted (catalog location IDs are
public). It prints the HTTP status and a count of reason modes.
