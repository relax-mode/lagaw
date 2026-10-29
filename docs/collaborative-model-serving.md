# Serving the collaborative model (#94)

The deployed `POST /api/v1/trips/{trip_id}/recommendations` blends content and
collaborative scores (60/40, see [hybrid-recommender.md](hybrid-recommender.md)) when a valid,
digest-pinned artifact is mounted, and otherwise serves the content baseline. This page
is the operating procedure. The artifacts are trained on a handful of **seeded demo
accounts**: they prove the serving path works, they say nothing about recommendation
quality. Quality claims stay on the labelled synthetic evaluation.

## Where the training snapshot comes from

Since [#79](authentication.md) every API request is owner-scoped: a user's token can read
only that user's `user_location_interactions`. Collaborative training needs several users'
events together, so it cannot go through the API. The snapshot is therefore an **offline
read with the existing server (service-role) credential**, limited to an explicit
allowlist of seeded demo profile IDs.

- **Who:** Kyle (DevOps) runs it, and holds the service-role credential (Secret Manager
  `STAGING_SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SERVICE_ROLE_KEY`, plus local shells).
  Never CI, never request handling.
- **Allowlist:** a private file of profile UUIDs outside the repository (the command
  refuses a path inside it). Real profile UUIDs are never committed.
- **Widening to organic users** is not allowed by this procedure. It needs a separate,
  recorded team decision in the sprint log covering consent/notice, data minimisation and
  who reviews the allowlist.
- The `user_location_interactions` table has no provenance column, so seeded rows are
  identified by an exact event-ID manifest, not by a flag.

## Seeding the demo accounts

`backend/seed_demo_interactions.py seed` creates five confirmed Supabase Auth accounts
(`lagaw-demo-<env>-a..e@example.invalid`) and writes their interactions **through the API
with each account's own token**, so the real owner-scoped path is used. Development and
staging share one Supabase project, so they share one set; production has its own.

| Account | Role |
| --- | --- |
| A | Target user with deep history (clears the 3-location gate); owns a demo trip |
| B, C, D | Overlapping histories so most items have at least 2 training users |
| E | Only 2 locations: `Content fallback (insufficient_history)`; owns a demo trip |

Three catalog places have a single supporter (`sparse_location`). The seed uses the 10
active catalog locations, with the one priced place first.

Current catalog limit: the content engine fails closed on an unknown cost, and only the
Negros Museum has a cost in either environment. Any trip can therefore receive at most
**one** recommendation, so a single response cannot contain both a `Hybrid:` and a
`Content fallback` item. Fallback evidence comes from account E's response instead.

Private files go to `--private-dir` (outside the repository, mode 0600, never overwritten):
credentials, an exact profile/event/trip/Auth-user manifest, the profile allowlist and
cleanup SQL. Passwords are generated in the shell and stored in Secret Manager
(`STAGING_DEMO_SEED_CREDENTIALS`, `DEMO_SEED_CREDENTIALS`); nothing is printed.

```bash
export SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_ANON_KEY=...   # from Secret Manager / the environment's SMOKE_SUPABASE_KEY
python seed_demo_interactions.py seed --environment staging \
    --api-url https://lagaw-api-staging-i5kvldluga-as.a.run.app --private-dir ~/.lagaw-private
```

### Cleanup

`python seed_demo_interactions.py cleanup-sql --environment staging --private-dir ...`
prints exact-ID SQL (interactions, trips, profiles, Auth users). It ends in `ROLLBACK`; add
`--commit` only after a rehearsal with the rollback version, run as the postgres role in
the Supabase SQL editor. Review the `events_beyond_manifest` row first: it must be 0 or
you must understand the extra rows, because deleting a profile cascades to what it owns.

## Training an artifact

```bash
python train_collaborative_model.py --environment staging \
    --profiles-file ~/.lagaw-private/staging-profiles.txt \
    --output model_artifacts/staging-real-svd.json
```

It refuses a Supabase project other than the named environment's, an allowlist inside the
repository, and any output outside the gitignored `backend/model_artifacts/`. It prints
only counts, the training digest, the file SHA-256 and the model state. **Secret Manager's
limit is 64 KiB** per version; the command refuses to write a larger artifact (about 1,000
training events fit). The artifact embeds training event IDs, so it is private data:
never commit it. **Train one artifact per environment; never promote staging's to production.**

## Delivery

One Secret Manager secret per environment holds the artifact JSON:
`STAGING_MODEL_ARTIFACT` and `MODEL_ARTIFACT`. Only that environment's Cloud Run runtime
service account gets `roles/secretmanager.secretAccessor` on it. The production deploy
reuses the image staging tested, so the model is **never baked into the image**.

```bash
gcloud secrets create STAGING_MODEL_ARTIFACT --replication-policy=automatic
gcloud secrets versions add STAGING_MODEL_ARTIFACT --data-file=model_artifacts/staging-real-svd.json
gcloud secrets add-iam-policy-binding STAGING_MODEL_ARTIFACT \
    --member=serviceAccount:<runtime service account> --role=roles/secretmanager.secretAccessor
sha256sum model_artifacts/staging-real-svd.json   # the pin; must equal the stored bytes' digest
```

Two **environment-scoped GitHub variables** (Settings > Environments > `staging` /
`production`) switch it on, and the deploy jobs apply them through
`scripts/resolve_model_delivery.py`:

| Variable | Value |
| --- | --- |
| `MODEL_ARTIFACT_SECRET` | `SECRET_NAME:VERSION`, numeric version (never `latest`) |
| `MODEL_FILE_SHA256` | the artifact file's SHA-256 (64 hex characters) |

Set together they mount the pinned version read-only at `/secrets/model/artifact.json`
(a dedicated directory, never under `/app`) and set `MODEL_FILE_PATH` and
`MODEL_FILE_SHA256`. One without the other fails the deploy. Environments are independent:
production stays content-only until its own variables are set.

### Retraining and rotation

1. Re-run the export/train command; `gcloud secrets versions add` the new file.
2. Set `MODEL_ARTIFACT_SECRET` to the new version and `MODEL_FILE_SHA256` to the new digest
   (change both in the same sitting), then redeploy (a push to `main`, or a manual run).
3. Check the startup log line (below) shows the new digest, then disable the old version.

New events never affect a running model: support counts come from the artifact.

### Rollback

Delete both variables for the environment and redeploy. The deploy overwrites the service's
secrets, which removes the mount, and explicitly removes `MODEL_FILE_PATH` and
`MODEL_FILE_SHA256`, so the service returns to the content-only baseline. Cloud Run drops
the now-unused volume entry on the following deploy (verified); do not delete or disable the
artifact secret until `gcloud run services describe` shows no volume for it, or later deploys
fail with a secret permission error. A merge-strategy deploy using only `--remove-secrets`
leaves exactly that dangling volume, which is why the workflow overwrites secrets.

## What the service does with the file

The model loads **once, at startup** (not on the first request) and logs one line with no
identifiers:

```text
recommendation_model status=present reason=loaded version=signed-svd-v1 provenance=real training_digest=<sha256> users=5 items=10 pairs=22 file_sha256=<sha256>
```

An unusable file logs `status=absent` with a reason (`missing`, `unreadable`, `corrupt`,
`too_large`, `wrong_version`, `invalid_artifact`, `provenance_mismatch`, `digest_mismatch`,
`invalid_expected_digest`; `not_configured` when `MODEL_FILE_PATH` is unset) and every
request returns 200 with the content baseline. If `MODEL_FILE_SHA256` is set, a file with
any other digest is refused before it is parsed. Requests cannot select a model, inference
is read-only and owner-scoped, and nothing trains during a request.

## Resources created for #94

See the sprint log for the dated record and the final inventory of secrets, IAM bindings,
GitHub variables and Auth accounts, with removal commands.
