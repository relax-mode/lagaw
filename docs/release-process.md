# Release process

This document describes how Lagaw prepares, verifies and publishes a tagged release, using `v1.0.0` as the first target. It is the release procedure for [issue #121](https://github.com/relax-mode/lagaw/issues/121).

**Status: prepared, not performed.** As of this document, no release tag exists and no GitHub Release has been created. The tag and release steps in [section 6](#6-publishing-human-run-not-performed) are human-run commands. They are not run by this repository's tooling or by CI.

Related documents: [CHANGELOG.md](../CHANGELOG.md), [draft release notes](release-notes/v1.0.0-draft.md), [PIPELINE.md](../PIPELINE.md), [staging environment](staging.md), [incident log](incident-log.md), [rollback runbook](rollback-runbook.md) (being added in a sibling pull request on `chore/s4-rollback-readiness`; this link resolves once that PR is merged).

## 1. Release gates

Issue #121 lists the Sprint 4 issues that gate the release. Each must be **closed with verification evidence linked from the release notes**. A gate that cannot be completed is a recorded blocker, and an unresolved blocker prevents publication.

| Issue | Gate | Evidence required |
|---|---|---|
| [#104](https://github.com/relax-mode/lagaw/issues/104) | Onboarding connected to personalized destination discovery | Widget/integration tests, and a deployed journey for a new authenticated user |
| [#106](https://github.com/relax-mode/lagaw/issues/106) | Destination catalogue enriched for feasible itineraries | Source and freshness records, idempotent rerun test, and a feasible three-stop production itinerary or the specific blocker |
| [#110](https://github.com/relax-mode/lagaw/issues/110) | Discovery swipes, saves and ratings persist | Widget tests for success and recoverable failure, and reload evidence |
| [#113](https://github.com/relax-mode/lagaw/issues/113) | Production authentication email delivery verified | Successful signup confirmation and password recovery, with no credentials recorded |
| [#114](https://github.com/relax-mode/lagaw/issues/114) | AI endpoint rate limiting and cost safeguards | Tests for independent users, quota exhaustion, reset and multi-instance enforcement; safe 429 demonstrated |
| [#117](https://github.com/relax-mode/lagaw/issues/117) | Android release build and honest UI states | Release-mode build reaching the production API with the intended identity; screenshots or tests for loading, empty and error states |
| [#118](https://github.com/relax-mode/lagaw/issues/118) | Scheduled AI smoke check and production verification | A succeeding scheduled or manually dispatched authenticated extraction run, with its URL |
| [#120](https://github.com/relax-mode/lagaw/issues/120) | Staging rollback drill executed | Runbook with real revision IDs and timestamps, and restored staging verified; production untouched |
| [#122](https://github.com/relax-mode/lagaw/issues/122) | Sprint 4 records current | Sprint log and evidence links reflect actual work; Sprint 3 gaps remain tracked in [#59](https://github.com/relax-mode/lagaw/issues/59) |

Course requirements that also apply (from [docs/official-instructions.md](official-instructions.md), Sprint 4 and the final deliverables checklist):

- A tagged release (for example `v1.0.0`) and a changelog.
- A production URL for the tagged release.
- A deploy and rollback runbook, with the rollback demonstrated.
- Code freeze observed before the presentation; the instructor announces the cutoff.

Run the read-only validator before tagging:

```sh
python scripts/release_check.py --version 1.0.0 --commit <approved-commit> --remote --ci
```

It checks the version, the changelog and notes entries, `frontend/pubspec.yaml`, that the tag is absent locally (and on `origin` with `--remote`), that the commit is contained in `origin/main`, that the working tree is clean, and (with `--ci`) that the latest `Lagaw CI` run for the commit succeeded. It never creates a tag. A FAIL on any line means do not tag.

## 2. Required CI and production smoke evidence

For the approved commit, record the following in the release notes:

1. **Lagaw CI** on the `main` push for that commit is green (`Backend - Python`, `Database - PostgreSQL migrations and smoke tests`, `Frontend - Flutter`), with the run URL.
2. **Deploy - Staging** succeeded for the same commit, including `scripts/smoke_deployed.py staging` (locations, Trip 401/200 and ownership, extraction route returning 422 for a blank prompt, and exact CORS).
3. **Deploy - Production API** and **Deploy - Production web** succeeded for the same commit, with the production smoke check (`scripts/smoke_deployed.py production`) passing.
4. **Scheduled live checks** (#118) succeeded recently against staging, with the run URL.
5. `https://lagaw.pages.dev` and the production Cloud Run service `lagaw-api` respond as expected after promotion.

The smoke script never writes data. Do not paste its credentials or response bodies into the release notes.

## 3. Identifying the deployed version

Use the commit SHA as the source of truth. Each deployed component can be matched to it as follows.

| Component | How to identify the version | Notes |
|---|---|---|
| Git | Commit SHA the tag points to (`git rev-parse v1.0.0^{commit}`) | Annotated tag points to the approved commit |
| Backend (Cloud Run `lagaw-api`) | The running image. Read-only check: `gcloud run services describe lagaw-api --project relax-mode-lagaw --region asia-southeast1 --format='value(spec.template.spec.containers[0].image)'`. It should end in `api:<sha>`. | The deploy workflow does **not** set a `commit-sha` revision label, so do not rely on a label. |
| Web (Cloudflare Pages `lagaw`, branch `main`) | The Pages deployment's commit hash | The web deploy runs `wrangler pages deploy ... --commit-hash "$GITHUB_SHA"`, so the deployment records the commit. |
| Flutter app | `frontend/pubspec.yaml` `version: 1.0.0+1` (build name `1.0.0`, build number `1`) | Matches `X.Y.Z+N` as checked by `scripts/release_check.py`. |
| Health or version endpoint | **None exists yet.** `backend/app` exposes no health or version route. Issue [#116](https://github.com/relax-mode/lagaw/issues/116) may add readiness behaviour. | Until a version endpoint is merged and verified, do not cite one in evidence. |

## 4. Artifact provenance

- **Backend image.** Deploy - Staging builds and pushes `api:staging-<sha>` and deploys `lagaw-api-staging`. After the staging smoke check passes, Deploy - Production API runs `gcloud artifacts docker tags add api:staging-<sha> api:<sha>`, so production runs the image staging tested rather than a rebuild. The manual recovery path builds `api:<sha>` directly instead.
- **Web build.** The staging and production web bundles are built separately, each with its own API URL and demo-token configuration, from the same commit. Provenance is therefore commit-level, not a byte-identical bundle.
- **Pages deployments.** Both staging and production deploys pass `--commit-hash "$GITHUB_SHA"`.
- **Database.** Migrations are applied through the database workflow and `supabase/`; record the migration revision that production runs.

## 5. Acceptance checklists

Tick a box only with linked evidence. Nothing below is ticked by this document.

### Android

- [ ] Release-mode build installs and reaches the production API (#117).
- [ ] Application identity matches the intended package and display name (#117).
- [ ] Sign-in, trip list, trip create/edit/delete, and itinerary view work against production (#80, #56).
- [ ] Loading, empty and error states show real API outcomes, with no fabricated scores, prices or saved states (#117).
- [ ] Onboarding reaches backend-generated recommendations (#104).
- [ ] Swipes, saves and ratings persist across an app restart (#110).

### Web

- [ ] `https://lagaw.pages.dev` loads the release commit's build (Pages commit hash recorded).
- [ ] Sign-in and sign-up confirmation email flows work from production (#113).
- [ ] CORS permits the production web origin only (`scripts/smoke_deployed.py production`).
- [ ] Trip flows and recommendations work against production.
- [ ] Empty, loading and error states render without fabricated data (#117).

### API

- [ ] `GET /locations` returns items from the production database.
- [ ] Trip endpoints return 401 without a token and 200 with an owner-scoped token.
- [ ] Extraction returns 422 for a blank prompt before any provider call; AI rate limits return a safe 429 (#114).
- [ ] Scheduled authenticated extraction succeeds against staging (#118).
- [ ] A rollback to the previous revision has been rehearsed in staging (#120).

## 6. Publishing (human-run, NOT performed)

The following commands are a procedure for a human release owner. They are **not performed** and must not be run by an agent or by CI. Run them only after `scripts/release_check.py` reports all PASS, every gate in section 1 is closed, and the release-notes draft has been promoted to `docs/release-notes/v1.0.0.md` in its own reviewed pull request.

```sh
# NOT PERFORMED - human release owner only
git fetch origin main --tags
git tag --list 'v1.0.0'                       # must print nothing
git tag -a v1.0.0 <approved-production-commit> -m "Lagaw v1.0.0"
git push origin v1.0.0                        # pushes the tag only
gh release create v1.0.0 --repo relax-mode/lagaw --verify-tag \
  --title "Lagaw v1.0.0" --notes-file docs/release-notes/v1.0.0.md
```

`<approved-production-commit>` is the commit whose production deployment passed section 2, and it must be reachable from `origin/main`.

## 7. Failed release

- **Gate fails before tagging.** Do not tag. Fix forward, or record the blocker in the release notes and the sprint log. Re-run `scripts/release_check.py` after the fix.
- **Tag created locally but not pushed.** Delete the local tag (`git tag -d v1.0.0`) and re-check. This is safe because nothing left the machine.
- **Tag pushed but production is broken.** Do not move or delete the tag and do not force-push. Roll production back to the last good revision using the [rollback runbook](rollback-runbook.md), record the incident in the [incident log](incident-log.md), and prepare a new patch version (for example `v1.0.1`) from a fixed commit. Any deletion of a published tag or GitHub Release is a human decision and is recorded.
- **Smoke check fails after deploy.** Nothing after the failing stage runs, and production keeps serving the previous version (see [PIPELINE.md](../PIPELINE.md)). Investigate, record the run URL, and do not tag until a passing run exists for the approved commit.

## 8. Version rules

Versions follow Semantic Versioning. `frontend/pubspec.yaml` carries `X.Y.Z+N`, and `X.Y.Z` must match the tag without the leading `v`. `scripts/release_check.py` enforces both.
