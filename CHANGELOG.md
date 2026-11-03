# Changelog

All notable changes to Lagaw are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version follows [Semantic Versioning](https://semver.org/).

Entries are factual: each one is taken from a merged pull request (`#<number>`) or a recorded repository document. Nothing here is a release until it is tagged and approved under [docs/release-process.md](docs/release-process.md).

## [Unreleased] - v1.0.0 candidate

Sprint assignment follows the sprint log and issue numbering: Sprint 1 covers PRs #1-#20, Sprint 2 covers the Trip API, Trip UI and CI issues (#22-#31), and Sprint 3 covers the recommendation, AI and authentication work (#26, #32-#34, #50-#58, #79, #80, #94). Documentation-only evidence PRs that only record a verification are not listed individually.

### Sprint 1 - Foundation and walking skeleton

#### Added

- Repository setup, environment example and branch strategy (#1, #3).
- Approved project pitch and AGENTS.md, tooling setup and official instructions (#2, #5).
- CI pipeline with project guards (#4).
- PostgreSQL schema and initial migration (#15).
- Seeded sample locations and a database-backed FastAPI locations endpoint (#16).
- Flutter shell with the tactile UI and FastAPI locations integration (#17).
- DeepSeek API backend tests (#14).
- Cloud Run backend deployment workflow (#20).
- Flutter Web deployment to Cloudflare Pages with Wrangler (#18).

#### Changed

- Web hosting is Cloudflare Pages, and backend hosting is Google Cloud Run (#13, #18, #20; see [docs/scope-changes.md](docs/scope-changes.md)).
- Structured preference extraction uses DeepSeek rather than the Gemini provider named in the original pitch (#14; see [docs/scope-changes.md](docs/scope-changes.md)).

#### Fixed

- None recorded in the Sprint 1 pull request titles.

#### Security

- Configurable FastAPI CORS with an origin allowlist for Flutter Web (#19).

### Sprint 2 - Trip management and CI foundations

#### Added

- Trip and itinerary database relationships, verified (#37).
- Trip create, list and retrieve API (#39).
- Trip update and delete API (#41).
- Trip creation and editing screens in Flutter (#45).
- Trip deletion with confirmation in Flutter (#47).
- Trip CRUD database integration tests using isolated fixtures (#82).
- Sprint 2 backlog and week 2 planning record (#36).

#### Changed

- Deployments are gated on CI checks (#44).
- Regression tests are automated and APK builds removed from CI (#35).
- Pull request checks are path-filtered, with a database test hook and pipeline hardening (#68).

#### Fixed

- Database CI check aligned with the schema check (#43).
- `TRIP_DEMO_TOKEN` is passed into the web build (#49).

#### Security

- Staging deployments use protected environments (#46).
- Deployments are gated on CI checks (#44).

### Sprint 3 - Recommendations, AI and authentication

#### Added

- Trip-itinerary location association API (#60) and itinerary locations on the Flutter trip details screen (#87).
- Recommendation data contracts and reproducible evaluation fixtures (#61).
- Content-based recommendations and their evaluation (#63).
- Structured preference extraction API (#64).
- Collaborative and hybrid recommendations (#65).
- Versioned Week 3 AI evaluation suite (#66).
- Validated recommendations in the Trip API (#86).
- Persisted user swipes, saves and ratings through the interactions API (#84).
- Constraint-aware trip itinerary generation and persistence (#89).
- Natural-language preference extraction in the Flutter trip form (#91).
- Trip planning with AI recommendations and generated itineraries in Flutter (#99).
- Supabase sign-in and authenticated Flutter sessions (#96).
- Collaborative model served from the deployed recommendation API (#95; issue #94 remains open).
- AI evaluation gate and automatic staging-to-production promotion (#73, landed on `main` through #77).

#### Changed

- Trip endpoints verify Supabase sessions and enforce backend ownership (#92).
- Production promotion waits for staging smoke checks (#77).

#### Fixed

- Isolated staging Trip demo configuration and CI verification (#62).
- Preservation SQL quoting in the authentication migration record (#93).
- Supabase sign-up rate-limit explanation, and localhost confirmation links no longer emitted (#97).

#### Security

- Backend ownership enforcement for Trip data under Supabase sessions (#92).
- Flutter sessions use Supabase sign-in and access tokens (#96).

## Not yet included (open Sprint 4 work)

These items are **not shipped** and are **not part of the v1.0.0 candidate** until their issues are closed with verification evidence. They are listed so readers can see what is still open.

- #59 - Record Sprint 3 progress and prepare AI consultation evidence
- #94 - Serve the trained collaborative model from the deployed recommendation API (PR #95 merged; issue still open)
- #101 - Implement first-time travel preference onboarding UI
- #102 - Implement onboarding preferences API and persistence
- #103 - Integrate content-based recommendations for cold-start users
- #104 - Connect onboarding to personalized destination discovery
- #105 - Research and validate Bacolod destination data sources
- #106 - Enrich destination catalogue for feasible itineraries
- #107 - Research and curate destination image sources
- #108 - Configure Supabase Storage for destination images
- #109 - Integrate real destination images into Flutter
- #110 - Persist discovery swipes, saves and ratings
- #111 - Evaluate content-based recommendations and cold-start quality
- #112 - Evaluate Brevo and Resend for Supabase authentication emails
- #113 - Configure and verify production authentication email delivery
- #114 - Add AI endpoint rate limiting and cost safeguards
- #115 - Finalize AI failure handling and evaluation documentation
- #116 - Improve backend health checks and API documentation
- #117 - Fix Android release build and misleading UI states
- #118 - Restore scheduled AI smoke checks and production verification
- #119 - Improve CI/CD security and pipeline efficiency
- #120 - Document and execute a staging rollback drill
- #122 - Maintain Sprint 4 records and consultation evidence
- #121 - Prepare and publish the verified v1.0.0 release (this release process)
