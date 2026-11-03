# Sprint 4 staging-only acceptance handoff

**Prepared November 3, 2026. Do not merge this validation branch.**

Candidate branch: `test/s4-integrated-validation`, based on `main` `ccf2e38`.
It combines the reviewed implementation branches of PR #136 (#108 destination
Storage), PR #135 (#114 extraction quotas), and PR #134 (#116 health/API docs).
The original PRs remain separate and are the intended review/merge units.

## Evidence already obtained

- Both additive migrations are applied and listed as remote in **development**
  Supabase project `vnpkyvtbupnquvirzlzp`.
- Storage bucket `destination-images`: public retrieval, 5 MiB cap, JPEG/PNG/WebP;
  three restrictive client-write policies; anonymous upload rejected by RLS.
- The development admin-console image upload was publicly retrievable and the
  temporary asset was deleted by the developer.
- The database quota minute/day assertions passed in a rolled-back transaction.
- Local combined branch: focused tests **28 passed**, non-DB regression
  **1,091 passed** (excluding known Windows POSIX-mode tests), Ruff/compile and
  whitespace checks passed. The three individual PRs have green CI and CyGray
  approvals, but this branch has not yet had combined Linux DB CI.
- Public **current staging** probes returned `/health` HTTP 404,
  `/ready` HTTP 404, and `/openapi.json` HTTP 200. The new backend is **not**
  currently deployed to staging.

## Gate 1: combined GitHub CI without deployment

In GitHub Actions > **Lagaw CI** > **Run workflow**, choose
`test/s4-integrated-validation`, **not** `main`. The workflow has
`workflow_dispatch`, and `staging-changes` requires
`github.ref == 'refs/heads/main'`. Therefore its staging and production deploy
jobs are skipped for this branch while Backend, Database, and Frontend checks run.
Confirm the run's branch before clicking Run. Preserve the run URL and results.
Do not dispatch this workflow on `main`: that path can deploy production.

## Gate 2: DevOps-only zero-traffic staging canary

The connected local Windows environment has neither `gcloud` nor `docker`
installed and cannot deploy a Cloud Run image itself. A team member with the
existing GCP staging-deployer permissions may use Google Cloud Shell or their
configured development machine. Use the *candidate branch*, not `main`:

```sh
git clone --branch test/s4-integrated-validation https://github.com/relax-mode/lagaw.git
cd lagaw
gcloud run deploy lagaw-api-staging \
  --source backend \
  --project relax-mode-lagaw \
  --region asia-southeast1 \
  --no-traffic \
  --tag s4-qa
```

If the repository is private, authenticate Git using the operator's usual safe
method; do **not** put a PAT into a clone URL. Confirm the project and service
identity **before** deploying. Verify this creates a **zero-traffic tagged
revision** of **`lagaw-api-staging`**, using the current staging runtime service
account and **staging** Supabase and DeepSeek secret bindings. Do not add or
replace secret values, expose API credentials, deploy `lagaw-api`, change
live staging traffic, or promote to production.

Copy the **actual tagged revision URL** from the Cloud Run output or console.
It should have the tag `s4-qa`. From the candidate repo:

```sh
python scripts/staging_canary_probe.py --url "https://s4-qa---lagaw-api-staging-i5kvldluga-as.a.run.app"
```

Use the actual tagged URL; the example illustrates the expected hostname, not
a verified deployed URL. The probe strictly allows the two known Lagaw staging
service host patterns and their `s4-qa` tags. It checks `GET /health`,
`GET /ready`, and `GET /openapi.json`, makes no writes or paid-provider
calls, and never requests authentication.

Expected after canary: `/health` returns HTTP 200 `status=ok`, `/ready`
returns HTTP 200 `status=ready`, OpenAPI includes both routes and the
extraction route. A 503 readiness response indicates an integration/config
problem, **not** success; inspect sanitized staging logs and bindings.

## Gate 3: authenticated development acceptance

- #114: with a dedicated synthetic **development** Auth account/profile, verify
  a quota-exhausted authenticated extraction request returns HTTP 429 and
  `Retry-After`, before any DeepSeek provider call. Plan quota reservation
  carefully against the development RPC; do not consume an actual user's quota
  or test with real paid extraction prompts by default.
- #108: use an explicitly approved/owned destination image and an existing
  development location with `image_url IS NULL`; run the repo's
  `scripts/destination_images.py` offline dry-run, then a separately approved
  `--execute --approved-usage --link-location`. Verify public retrieval and
  `GET /locations` image URL. Do not overwrite curated image URLs.
- #116: verify `GET /health`, `GET /ready`, `GET /openapi.json`, and
  failure-mode status/sanitization against the tagged revision.

## Remove the staging canary after acceptance

An authorized GCP operator can remove only the test tag:

```sh
gcloud run services update-traffic lagaw-api-staging \
  --project relax-mode-lagaw \
  --region asia-southeast1 \
  --remove-tags s4-qa
```

This does not set any traffic percentage and is not a production action.
Check the existing staging traffic assignments before and after.
Never use `--to-latest` as cleanup: that could redirect live staging traffic.

## Production gate (not authorized)

No change to production Supabase project `zjnuqqtbapbpudsjbpif`, no PR
merge, and no production deployment has been made as part of this handoff.
Merging backend changes into `main` automatically deploys staging **and
production** after CI. Before **any** merge, obtain a separate explicit release
decision, review production quota migration sequencing and image Storage
dependencies, plan rollback, and ensure the authorized deployment owner is
available. In particular, #114's backend fails closed if the production quota
RPC is missing. Never use `gh workflow run ci.yml --ref main` for staging
testing: it is a production recovery deployment path.
