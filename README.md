# Lagaw

**Swipe through Bacolod. Get a trip that fits you.**

Lagaw (Hiligaynon for roaming around) is a swipe-based travel planner for Bacolod City, built as an Android app with a companion web build. It learns what you like, then turns it into a day-by-day itinerary that respects your budget, opening hours, and travel time. No more scrolling through generic "top 10" lists.

## How it works

1. **Swipe.** Right on places you like, left on ones you don't. Save favorites and rate the places you've visited.
2. **Say what you want.** Set a budget and pick tags, or just type it: *"a cheap, relaxing afternoon with coffee and photography spots."*
3. **Get a plan.** Lagaw ranks destinations for you and arranges them into an itinerary you can edit, save, or archive.

## Under the hood

**Hybrid recommender.** Matrix factorization finds taste patterns across users. Content-based filtering matches your preferences to each place's category, tags, cost, group fit, setting, visit length, and accessibility. The two scores are blended, and new users lean on tags and budget until their swipes give the model more to work with.

**Structured extraction.** DeepSeek-V4.1-Flash, accessed through the official DeepSeek API platform, turns free-text requests into structured preferences (budget level, tags, duration, pace). It only extracts. It never generates recommendations, and it is called from the backend only, never from the app.

**Validated output.** Nothing from the models reaches the frontend raw. The backend checks extracted values against a schema and approved tags, then filters recommendations for inactive, duplicate, or incompatible places and applies budget, group, accessibility, and distance limits. The itinerary planner then checks operating hours, travel time, and cost for conflicts.

The recommender is our own Python model and runs on our backend. If DeepSeek is unavailable, users fall back to the standard trip form.

## Tech stack

| Layer | Tools |
| --- | --- |
| Frontend | Flutter (Dart): Android app, plus a Flutter Web build from the same codebase |
| Backend | FastAPI, Python |
| Recommender | pandas, NumPy, scikit-learn, LightFM |
| Extraction | DeepSeek-V4.1-Flash via the official DeepSeek API (`httpx`) |
| Database | PostgreSQL on Supabase |
| Hosting | Android APK for testing, web build on Cloudflare Pages, backend on Google Cloud Run, Supabase for database and storage |
| DevOps | GitHub Actions CI/CD; Wrangler CLI for managing and deploying Cloudflare Pages, run locally and from CI/CD |

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

Trip create/list/retrieve API, controlled demo-user setup, and development-first
verification: [trip API guide](docs/trips-api.md).

Trip partial updates, deletion, and development-first cascade verification:
[trip update/delete guide](docs/trip-mutations-api.md).

Manual trip-location association endpoints and development-first verification:
[trip items API guide](docs/trip-items-api.md).

Independent recommendation contracts, synthetic fixtures and AI/backend handoff:
[recommendation foundation](docs/recommendation-contract.md).

Offline scoring, ranking, cold-start behavior and evaluation:
[content-based recommender](docs/content-based-recommender.md).

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
