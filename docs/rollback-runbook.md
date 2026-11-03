# Rollback Runbook

Operational runbook for rolling Lagaw back to a known-good deployment. It covers the Cloud Run API (`lagaw-api-staging` and `lagaw-api`) and the Cloudflare Pages web app (project `lagaw`). It complements [`PIPELINE.md`](../PIPELINE.md#rollback) and [`docs/staging.md`](staging.md#rollback).

## Authorization and scope

- A real rollback needs **separate, explicit authorization** for each change. Record who authorized it and when.
- Every rollback names **one environment** (`staging` or `production`) and a **manually supplied revision**. Do not pick a target automatically in a script or CI job.
- A Cloud Run rollback moves **traffic only**. It does not roll back the database schema, the Secret Manager versions the revision already uses, or the Pages web bundle. Migrations are forward-only (see [Compatibility check](#compatibility-check)).
- Do not delete revisions, Pages deployments, or deployment history during an incident. Keep the failed and good IDs with the incident notes ([`docs/incident-log.md`](incident-log.md)).
- Do not paste tokens, passwords, or `.env` values into tickets, logs, or this runbook. Load them from the operator's secret store into the shell.

## Snapshot of observed deployments (read-only, 2026-10-30 12:38 UTC)

This snapshot will go stale. Re-run the read-only commands in [Identify the current deployment](#identify-the-current-deployment) before you rely on it. It is not an approval of any target.

| Environment | Serving revision (100%) | Commit-sha label | Image digest (sha256) | Created (UTC) |
| --- | --- | --- | --- | --- |
| staging `lagaw-api-staging` | `lagaw-api-staging-00029-hx5` | `a5073051754b5ddad5b34be1d0e437dda1c0f8f0` | `aa64c33192e315355e7416b2cd30cca0ed53812c97a37baaf8ec62fb99427138` | 2026-10-29 04:20:36 |
| production `lagaw-api` | `lagaw-api-00019-mq8` | `a5073051754b5ddad5b34be1d0e437dda1c0f8f0` | `909ecc0769d8c3a01160a6917abfd6109441015f1c03ad7815c28d286262a814` | 2026-10-29 04:23:03 |

Observed neighbours that matter for target selection:

- Staging `lagaw-api-staging-00028-46r` and `-00027-2kk` share the current digest (`aa64c3...`), so they are not rollback targets. The nearest different digest is `lagaw-api-staging-00024-96t` (`38b631f7...`, label `7186a080336838d0b2fdba5590d445ef3a6b0ffb`, created 2026-10-28 17:54:03).
- Production `lagaw-api-00018-r8g` has **the same digest** as `00019-mq8` (`909ecc...`), a config-only redeploy. Rolling back to it is a no-op. This is the trap the helper refuses.
- Production `lagaw-api-00016-c7j` has the same digest as `00019-mq8` but a different commit label (`6412bad9...`). The commit label does not identify the image; the digest does.
- The nearest different production digest is `lagaw-api-00017-m5m` (`aa64c3...`, label `a5073051...`, created 2026-10-29 04:11:32). Its commit label matches the current revision but its digest does not, so build provenance is unverified. It is **not approved** as a rollback target.

No Cloudflare Pages deployment state was observed (see [Cloudflare Pages restoration](#cloudflare-pages-restoration)).

## Identify the current deployment

### Cloud Run

Each revision carries a `commit-sha` label (the commit of the deploy that created it) and an image digest. The helper reads only these fields:

```sh
python scripts/rollback_helper.py status --env staging   --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --limit 6
python scripts/rollback_helper.py status --env production --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --limit 6
```

Raw equivalents (the projection avoids printing environment variables):

```sh
gcloud run services describe lagaw-api --project "$GCP_PROJECT_ID" --region "$GCP_REGION" \
  --format="json(metadata.name,status.traffic,status.latestReadyRevisionName)"
gcloud run revisions list --service lagaw-api --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --limit 6 \
  --format="json(metadata.name,metadata.creationTimestamp,metadata.labels,status.imageDigest)"
```

Read the output this way:

- `status.traffic` entries with `percent: 100` identify the serving revision. More than one revision with traffic means a split; resolve it before any rollback.
- Compare `status.imageDigest` values, not commit labels. Identical digests mean identical images.

### Cloudflare Pages

Pages deployments are built by CI with `--branch` and `--commit-hash` (see the `Deploy staging Flutter Web` step and the `Deploy - Production web` job in `.github/workflows/ci.yml`). Staging uses branch `staging`; production uses branch `main`.

- Dashboard: Workers & Pages → project `lagaw` → Deployments. Each row shows its branch, commit hash, status, and URL. The production row is the one serving `https://lagaw.pages.dev`.
- CLI (unverified here, see below): `npx wrangler pages deployment list --project-name lagaw`, run with an account-scoped token from the operator's secret store.

## Identify a known-good deployment

Pick a target only when all of these hold:

1. It is a **different image digest** from the serving revision. A config-only redeploy with the same digest is not a rollback (`plan` refuses it unless `--allow-same-image` is passed, and that flag should be used only for a deliberate configuration-only restore).
2. Its **commit-sha label is a commit in the local clone** (`git cat-file -e <sha>^{commit}`). Otherwise the migration check cannot run.
3. It **passed health checks** when it served traffic, or it was smoke-tested before (look for the matching run in GitHub Actions or the sprint/incident log). A revision that was never verified is not known-good.
4. It is **schema-compatible** with the current database (see below).
5. It belongs to the same service (`plan` checks the `serving.knative.dev/service` label).

For the web app, choose a Pages deployment built from a commit that the matching API revision also supports.

## Compatibility check

Migrations are forward-only and are applied by hand with the Supabase CLI (`npx supabase db push`, see [`docs/database.md`](database.md#deploy-after-review)). Rolling back the API does **not** undo a migration. Older code therefore runs against a newer schema. The helper lists `supabase/migrations/` files changed between the target commit and the current commit.

The four migrations in the repository:

| File | Introduced | Kind | Rollback implication |
| --- | --- | --- | --- |
| `20261014114320_initial_lagaw_schema.sql` | `6ee270e` (2026-10-14) | Additive: creates five tables, indexes, RLS and grants | Never reverse. Dropping the tables destroys data. |
| `20261014154651_seed_sample_locations.sql` | `97460cb` (2026-10-15) | Data-changing: inserts 10 sample locations with fixed IDs; reruns leave existing rows (including admin edits) alone | Reversing deletes seeded rows and any admin edits. Not needed for an API rollback. |
| `20261028130000_atomic_itinerary_generation.sql` | `43dda7a` (2026-10-28) | Additive functions and a trigger, but behaviour-changing: the `itinerary_items` trigger clears `trips.estimated_total_cost` on writes, and `save_generated_itinerary` deletes and reinserts items | Dropping the functions and trigger is not data-destructive but changes behaviour. Review before rolling back to a revision that predates the itinerary API. |
| `20261029090000_link_verified_auth_profiles.sql` | `91929f1` (2026-10-29) | Additive: nullable `users.auth_user_id` with unique and non-zero checks | Dropping the column deletes the identity mapping for every linked profile. Treat as irreversible once any row is linked. |

Consequences:

- A rollback to a revision built **before** `91929f1` runs code that does not read `auth_user_id`. Review its ownership behaviour before choosing it.
- A rollback to a revision built before `43dda7a` runs code that predates the itinerary trigger. Review how it writes `itinerary_items`.
- Any data-changing or irreversible migration applied after the target means the rollback is a **schema-incompatible decision**. Escalate; do not roll back on your own.
- Whether each migration is applied to production or staging is **not verified read-only**. Check it with the operator's own session: `npx supabase migration list` against the project (never paste its output with credentials).

The helper's warning is a prompt for this review, not a verdict. An `UNKNOWN` result (missing label, commit not in the clone, or git failure) means the check did not run.

## Safe Cloud Run rollback

Run the dry run first. It is read-only and prints the exact commands.

```sh
python scripts/rollback_helper.py plan --env staging --to-revision <REVISION_NAME> \
  --project "$GCP_PROJECT_ID" --region "$GCP_REGION"
```

After the review and the written authorization, execute with every guard present. Production also needs a named approver:

```sh
ROLLBACK_AUTHORIZED=staging python scripts/rollback_helper.py execute --env staging \
  --to-revision <REVISION_NAME> --project "$GCP_PROJECT_ID" --region "$GCP_REGION" \
  --execute --confirm "staging:<REVISION_NAME>"

ROLLBACK_AUTHORIZED=production python scripts/rollback_helper.py execute --env production \
  --to-revision <REVISION_NAME> --project "$GCP_PROJECT_ID" --region "$GCP_REGION" \
  --execute --confirm "production:<REVISION_NAME>" --production-authorized-by "<approver name>"
```

The helper refuses (exit 2, nothing changed) unless `--execute`, an exact `--confirm`, `ROLLBACK_AUTHORIZED` equal to the environment, and (production) a non-empty `--production-authorized-by` are all present. A failed traffic change exits 1.

Raw gcloud equivalent (the same command the helper prints):

```sh
gcloud run services update-traffic lagaw-api --project "$GCP_PROJECT_ID" --region "$GCP_REGION" \
  --to-revisions <REVISION_NAME>=100
```

Staging uses `lagaw-api-staging` in the same form.

After the change, verify health (see [Health verification](#health-verification)) and record the times (see [Timestamp record](#timestamp-record)).

## Cloudflare Pages restoration

**Not verified read-only from this machine.** The `wrangler` CLI is not installed here, and the commands below were not run. Confirm the dashboard labels and the API shape on your own account before relying on them.

Dashboard path (the one the pipeline documentation names):

1. Open Workers & Pages → project `lagaw` → Deployments.
2. Find the known-good row for the same branch (`main` for production, `staging` for staging). Confirm its commit hash.
3. Open its menu and choose **Rollback to this deployment** (or promote it, if that label appears instead). Confirm the URL serves the expected build.
4. Keep the failed deployment and its commit hash in the incident notes.

Optional CLI and API (placeholders only; load tokens from the secret store and do not echo them):

```sh
npx wrangler pages deployment list --project-name lagaw
```

```sh
# Unverified endpoint shape. Confirm against current Cloudflare API documentation first.
curl -sS -X POST \
  "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/pages/projects/lagaw/deployments/<DEPLOYMENT_ID>/rollback" \
  -H "Authorization: Bearer <CLOUDFLARE_API_TOKEN>"
```

Notes:

- The web bundle embeds the API URL and the public demo token for its environment. After a Pages rollback, run the smoke check against the matching API.
- The next qualifying push to `main` redeploys production automatically. Land the fix through a reviewed PR, or pause the path, before merging anything else, or the rollback will be overwritten.

## Health verification

Use the existing read-only check. Its usage line is `python scripts/smoke_deployed.py staging|production`. It needs the environment variables `SMOKE_API_URL`, `SMOKE_PROFILE_ID`, `SMOKE_AUTH_EMAIL`, `SMOKE_AUTH_PASSWORD`, and `SMOKE_SUPABASE_KEY`, all from the operator's secret store for that one environment. It rejects URLs outside its allowlist, writes nothing, and never prints credentials.

```sh
python scripts/smoke_deployed.py staging     # SMOKE_* values for staging loaded from the secret store
python scripts/smoke_deployed.py production  # SMOKE_* values for production loaded from the secret store
```

It checks locations, Trip authentication and ownership, the extraction route (422 for a blank prompt, without calling the provider), and CORS. Also open the matching web URL (`https://staging.lagaw.pages.dev` or `https://lagaw.pages.dev`) and confirm it loads. Record the result with the timestamp.

## Restoring the latest approved version

`restore` routes traffic to `--to-latest`, which means the **newest ready revision**. After a rollback that is usually the failed one. Run it only when that revision is the approved fix and has passed health checks:

```sh
python scripts/rollback_helper.py restore --env staging --project "$GCP_PROJECT_ID" --region "$GCP_REGION"
```

The dry run prints the latest ready revision. Confirm it, then add `--execute --confirm "<env>:latest"`, `ROLLBACK_AUTHORIZED`, and (production) `--production-authorized-by`. Raw equivalent:

```sh
gcloud run services update-traffic lagaw-api --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --to-latest
```

Afterwards, run the health verification again. For Pages, promote the approved deployment in the dashboard.

## Timestamp record

Record every event in UTC. Fill in only what happened; leave the rest blank. The helper prints this template with each plan.

| Event | UTC timestamp | Authorized by | Evidence (link or note) |
| --- | --- | --- | --- |
| failure_detected | | | |
| rollback_authorized | | | |
| traffic_moved (Cloud Run) | | | |
| pages_rolled_back | | | |
| health_verified | | | |
| restore_started | | | |
| restored | | | |
| fix_merged | | | |

Compute durations from these rows (for example, failure to traffic moved) and put them in the incident log.

## Escalation and troubleshooting

Escalate to the project owner before any production rollback that changes schema compatibility, and whenever authorization is unclear. Name the approver in the record.

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `REFUSED: target runs the same image digest` | Config-only redeploy | Choose an older revision with a different digest, or accept a configuration-only restore explicitly with `--allow-same-image` |
| `could not read revision` or gcloud exit 2 | Wrong name, project, or region; or no gcloud login | Run `status` first; check `gcloud auth list` (never print tokens) |
| `traffic is not 100% on one revision` | Split traffic or a tag | Resolve the split manually; do not roll back until one revision serves 100% |
| `UNKNOWN` migration compatibility | Commit label missing or not in the clone | `git fetch`, then rerun `plan`; if still unknown, escalate |
| Smoke check fails after rollback | Target revision unhealthy, CORS or web bundle mismatch | Check the revision's logs; compare the Pages build with the API URL and token; escalate if the API is down |
| Rollback reverted by a deploy | Automatic promotion on the next `main` push | Land the fix through PR or pause before merging |
| Pages and API disagree | Web build from a different commit than the API revision | Roll Pages to a build matching the chosen API revision |

## Staging rollback drill record

**Status: PENDING. No drill has been performed.** Fill rows only after a drill runs with explicit authorization. Leave values blank until then.

| Drill | UTC date | Revision from | Revision to | Traffic moved (UTC) | Smoke result | Restored to latest (UTC) | Operator | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Cloud Run staging drill | not yet performed | | | | not yet performed | | | |
| Pages staging drill | not yet performed | | | | not yet performed | | | |
