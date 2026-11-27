# Lagaw

**Swipe through Bacolod. Get a trip that fits you.**

> **Final technical documentation — 27 November 2026**
>
> [Three-page Google Doc](https://docs.google.com/document/d/1Gt111rJOuAyD71V0g4stY_aYvAIWGpyVKfVhEG4Pt3w/edit) · [Current scope, architecture and evidence](docs/final-project-evidence.md) · [Dated verification record](docs/evidence/final-documentation-check-2026-11-27.json).
> The brief records the implemented system, source/deployment revisions, dated test results and remaining submission items. Confirm panel access and complete its release-evidence items before submission.

**Roel and coding assistants working on #56: [START HERE — agreed backend APIs and complete frontend flow](ROEL_START_HERE.md).**

Lagaw (Hiligaynon for roaming around) is a destination discovery and trip-planning app for Bacolod City, built for Android with a companion web build. It uses saved preferences and supported recommendation models to suggest places, then builds an editable itinerary using catalogue hours, estimated travel time and budget constraints.

## How it works

1. **Swipe.** Right on places you like, left on ones you don't. Save favorites and rate the places you've visited.
2. **Say what you want.** Set a budget and pick tags, or just type it: *"a cheap, relaxing afternoon with coffee and photography spots."*
3. **Get a plan.** Review ranked suggestions and generate an itinerary you can edit, reopen or delete. Trip archive is not implemented.

## Under the hood

**Hybrid recommender.** Onboarding discovery uses content scoring. Saved-trip recommendations can blend 60% content scoring with 40% rank-3 SVD for users and places supported by the fitted artifact; otherwise they fall back to content. The artifact was fitted on seeded demo-account interactions and does not retrain on each swipe. The swipe deck itself follows catalogue order. Working accessibility and indoor/outdoor filtering are outside the implemented scope.

**Structured extraction.** The official DeepSeek API, configured with the `deepseek-flash` alias, turns free-text requests into a preference draft. Its immutable provider model revision is not pinned. The backend validates the draft and requires confirmation; extraction itself writes nothing. Numeric budget and group size remain explicit form inputs. Recommendation ranking is separate from extraction.

**Validated output.** The backend checks extraction output against a strict schema and approved tags. Recommendation and itinerary code apply their supported eligibility, budget and group constraints. A separate greedy planner checks operating hours, visit duration, estimated travel and cumulative cost before an atomic save; catalogue estimates do not guarantee optimal routes or venue availability.

The recommender is our own Python model and runs on our backend. If DeepSeek is unavailable, users fall back to the standard trip form.

## Tech stack

| Layer | Tools |
| --- | --- |
| Frontend | Flutter (Dart): Android app, plus a Flutter Web build from the same codebase |
| Backend | FastAPI, Python |
| Recommender | NumPy: content-based scoring plus a rank-3 SVD matrix-factorization model (`signed-svd-v1`) as the approved equivalent to LightFM; see [`docs/hybrid-recommender.md`](docs/hybrid-recommender.md) |
| Extraction | Official DeepSeek API via `httpx`, configurable `deepseek-flash` alias; immutable provider revision unpinned |
| Database | PostgreSQL on Supabase |
| Hosting | Android APK for testing, web build on Cloudflare Pages, backend on Google Cloud Run, Supabase for database and storage |
| DevOps | GitHub Actions CI/CD; Wrangler CLI for managing and deploying Cloudflare Pages, run locally and from CI/CD |

## Team

| Member | GitHub | Role | Owns |
| --- | --- | --- | --- |
| Kyle | [@CyGray](https://github.com/CyGray) | DevOps Engineer | CI/CD pipeline, environments and secrets, deployments, pipeline metrics and incidents ([`PIPELINE.md`](PIPELINE.md)) |
| Andrew | [@aranxshx](https://github.com/aranxshx) | Backend / API Engineer | FastAPI endpoints, validation, database access, backend and database tests |
| Roel | [@roellumauagjr](https://github.com/roellumauagjr) | Frontend Engineer | Flutter app, web build, wiring the UI to the API |
| Jayperson | [@s2302663-del](https://github.com/s2302663-del) | AI Engineer | Preference extraction, recommendation models, AI evaluation |

Roles follow the issue assignments. Record any role change, with its reason, in the [sprint log](docs/sprint-log.md).

## Configuration

Copy `.env.example` to `.env` and fill in your own values, including a DeepSeek API key (`DEEPSEEK_API_KEY`). The `.env` file is gitignored and no secret should ever be hardcoded.

Full project pitch: [docs/pitch.md](docs/pitch.md)

Database schema, local migrations, and verification:
[docs/database.md](docs/database.md).

Backend DeepSeek setup and verification: [step-by-step guide](docs/deepseek-setup.md).

Versioned structured extraction API, confirmation and manual fallback:
[preference extraction contract](docs/preference-extraction-api.md).

Run and verify the database-backed locations API: [setup guide](docs/locations-api.md).

Connect Flutter Web to FastAPI locally and on Cloudflare Pages:
[CORS setup and verification](docs/cors.md).

Provider decision and follow-up work: [docs/sprint-log.md](docs/sprint-log.md)

Backend and Flutter regression checks, CI behavior, and test isolation:
[testing guide](docs/regression-tests.md).

Trip CRUD tests against disposable PostgreSQL and PostgREST, fixture isolation,
and CI evidence: [Trip integration tests](docs/trip-integration-tests.md).

Trip create/list/retrieve API, controlled demo-user setup, and development-first
verification: [trip API guide](docs/trips-api.md).

Verified Supabase identities, backend ownership, the #80 session handoff and
development-first release checks: [authentication contract (#79)](docs/authentication.md).

Trip partial updates, deletion, and development-first cascade verification:
[trip update/delete guide](docs/trip-mutations-api.md).

Manual trip-location association endpoints and development-first verification:
[trip items API guide](docs/trip-items-api.md).

Independent recommendation contracts, synthetic fixtures and AI/backend handoff:
[recommendation foundation](docs/recommendation-contract.md).

Persisted swipes, saves and ratings, owner-scoped history and safe verification:
[interaction API](docs/interactions-api.md).

Validated recommendations for saved trips, budget allocation and model fallback:
[trip recommendation API](docs/trip-recommendations-api.md).

Cold-start discovery from saved onboarding tags, without a saved trip or model:
[onboarding recommendation API](docs/onboarding-recommendations-api.md).

Realistic cold-start scenarios, catalog coverage and content-first/hybrid roadmap:
[content-first evaluation](docs/content-first-evaluation.md).

Constraint-aware generated schedules, atomic persistence and replacement confirmation:
[itinerary generation API](docs/itinerary-generation-api.md).

Offline scoring, ranking, cold-start behavior and evaluation:
[content-based recommender](docs/content-based-recommender.md).

Offline matrix factorization, hybrid scoring, artifacts and held-out comparison:
[hybrid recommender](docs/hybrid-recommender.md).

Week 3 versioned extraction/model evaluation and one offline CI command:
[evaluation suite and handoff](docs/week3-evaluation.md).

AI-specific malformed output, outage, recovery and fallback guarantees:
[failure coverage and technical limits](docs/ai-failure-coverage.md).

## Branch Strategy

Lagaw uses a simple feature-branch workflow to keep the `main` branch stable and organized.

### Main Branch

The `main` branch contains the latest stable and deployable version of the project.

Direct commits to `main` should be avoided. All changes should be introduced through pull requests.

### Branch Naming Convention

Each task, feature, fix, or maintenance work should be developed in its own branch created from `main`.

Use the following naming conventions:

- `feat/<name>` — for new features
- `fix/<name>` — for bug fixes
- `chore/<name>` — for configuration, CI/CD, repository setup, or maintenance
- `docs/<name>` — for documentation changes
- `test/<name>` — for testing-related work

Examples:

- `feat/backend-skeleton`
- `feat/flutter-skeleton`
- `feat/ai-connectivity`
- `chore/sprint-1-bootstrap`
- `chore/ci-pipeline`

### Development Workflow

1. Pull the latest changes from `main`.
2. Create a new task-specific branch from `main`.
3. Make and commit the required changes.
4. Push the branch to GitHub.
5. Open a pull request targeting `main`.
6. Wait for the required CI checks to complete successfully.
7. Review and merge the pull request into `main`.

The team should avoid working directly on `main` to reduce conflicts and help ensure that the main branch remains stable.
