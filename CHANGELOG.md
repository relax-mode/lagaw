# Changelog

All notable changes to Lagaw are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version follows [Semantic Versioning](https://semver.org/).

Entries are factual: each one is taken from a merged pull request (`#<number>`) or a recorded repository document. Nothing here is a release until it is tagged and approved under [docs/release-process.md](docs/release-process.md).

## [1.0.0] - 2026-11-27

Sprint assignment follows the sprint log and issue numbering: Sprint 1 covers PRs #1-#20, Sprint 2 covers the Trip API, Trip UI and CI issues (#22-#31), Sprint 3 covers the recommendation, AI and authentication work (#26, #32-#34, #50-#58, #79, #80, #94), and Sprint 4 covers PRs #100-#191 (onboarding, destination data and images, safeguards, Android release build, CI/CD security, rollback and release preparation). The final panel hardening of November 27 covers PRs #205-#212. Documentation-only evidence PRs that only record a verification, and the deployment rehearsal PRs (#179, #180, #191), are not listed individually. Dependabot pull requests are listed together under Sprint 4 Security.

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
- Collaborative model served from the deployed recommendation API (#95).
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

### Sprint 4 - Hardening, polish and release

#### Added

- First-time travel preference onboarding UI (#161), the onboarding preferences API with persistence (#129), and onboarding connected to saved preferences and cold-start "Picked for you" discovery in Flutter (#162).
- Authenticated cold-start recommendations from saved onboarding tags, before a trip exists (#131).
- Discovery swipes, saves and ratings persisted from the Flutter app (#164).
- Destination data source validation (#128), a source-reviewed catalogue enrichment workflow (#130), and metadata for existing destinations from supplied values (#181, #183).
- Twenty additional Bacolod destinations with qualified opening hours and price ranges (#185).
- Destination photo pipeline: Supabase Storage workflow for approved photos (#136), image license manifest (#163, #173), licensed photos shown with credits in Flutter (#175), and photos for the twenty new destinations (#189).
- Backend `GET /health` liveness, `GET /ready` database readiness, and safe API documentation (#134).
- Shared per-account rate limits and cost safeguards for AI preference extraction (#135).
- Forgot-password request and password reset form in Flutter (#150).
- Android release build with the intended application identity and honest loading, empty and error states (#174).
- Phone app redesign v3 and v4 across Home, Spots, swipe, Trips and You (#176, #188).
- Content-first cold-start evaluation (#132) and AI failure coverage tests (#133).
- Secret scanning (gitleaks), dependency audit, pinned GitHub Actions and Dependabot configuration (#125).
- Rollback runbook and a dry-run-by-default rollback helper (#126), with the staged rollback verified (#160).
- Release process, release readiness check, changelog and draft release notes (#124).
- Resend SMTP preparation for Supabase Auth email (#123) and the Brevo versus Resend decision evidence (#145).
- Sprint 3 consultation record (#154), Sprint 4 DevOps records and CI/CD diagram (#127), and Sprint 4 pipeline metrics (#187).
- Production collaborative-model rollout verification (#157).

#### Changed

- The scheduled live AI check signs in as a dedicated smoke account instead of sending the retired demo token (#100).
- The dependency audit runs only for relevant pull request changes, and still runs on every push to `main` (#146).
- Auth email documentation reflects Brevo SMTP and the required live verification (#156).
- Page title, web manifest and app icons say Lagaw, and em dashes are removed from UI text (#182).
- The unused `cupertino_icons` dependency is removed from Flutter (#155).
- Local release APKs are git-ignored (#178).

#### Fixed

- Scheduled live AI check failing with HTTP 401 (#100).
- Password recovery email now opens the password reset form, and password-update errors from Supabase are reported accurately (#150, #159).
- Destination categories are merged and shown with readable labels (#186), and personal attribution is removed from destination descriptions (#184).
- A historical gitleaks false positive on a public destination UUID is scoped out without weakening other rules (#152).

#### Security

- Gitleaks secret scanning on every pull request and push, a dependency-audit gate, explicit least-privilege job permissions and SHA-pinned third-party actions (#125).
- Atomic per-account AI quota reservations before paid provider calls, with a safe 429 and a fail-closed 503 (#135).
- Dependency and action updates from Dependabot (#137, #138, #139, #140, #141, #142, #143, #165, #166, #167, #168, #169, #170, #171).

### Final panel hardening (November 27)

#### Added

- Real photos and credits on the intro swipe cards, bundled with the app (#209).
- Incident log entries INC-5 and INC-6, a corrected rollback runbook, a refreshed PIPELINE.md, and the Sprint 4 plan and retrospective (#211).
- README live links, architecture diagram, local setup and final deliverables index (#212).

#### Changed

- The home headline wording was changed and then restored (#206, #208).

#### Fixed

- A trip date edit that would strand a saved visit is rejected with a conflict, and the trip and its visits are preserved (#205).
- The generated cost estimate is cleared when it exceeds a new budget, and the saved visits are kept (#205).
- Itinerary edits and generation use one lock order for competing writes (#205).
- The first screen after the API has been idle no longer fails with "Could not reach the Lagaw server", because client requests allow time for the server to start (#210).
- The AI suggestion limit shows a readable try-later message instead of a raw HTTP status, and manual entry still works (#210).
- Signing out or switching accounts closes open pop-ups and starts fresh, so nothing from the previous account is shown or sent (#210).
- After a timed-out or unexpected trip save, the form offers "Open My Trips" instead of Retry, so the same trip is not saved twice (#210).
- The largest allowed budget stays on one line in the trip summary (#210).

#### Security

- Shared, configurable AI extraction budget with controlled 429 and 503 responses (#205).
- Request bodies over 64 KiB are rejected with 413 (#205).
- A JWT with a non-string subject or role claim returns 401 instead of an error, and a concurrent first request for the same identity reuses its profile link (#205).

## Known limitations at release

These are open at the time of release and verified against `main` and the issue tracker on November 27, 2026.

- **Cloud Run traffic is not forced to the latest revision.** CI does not yet route traffic to the new revision after a deploy, and the staging smoke check does not compare the served revision. A rollback or manual tagged deploy can pin a service (see INC-5 in [docs/incident-log.md](docs/incident-log.md)). Production deploys with `--min-instances=0`. Tracked in [#204](https://github.com/relax-mode/lagaw/issues/204), open.
- **Final-panel staging evidence is pending.** [#202](https://github.com/relax-mode/lagaw/issues/202) and [#203](https://github.com/relax-mode/lagaw/issues/203) are still open, although their pull requests (#205, #210) are merged.
- **The trip demo token is still compiled into the public web bundles.** The hosted API does not accept it, but the bundle exposes the value. See "Open risks" in [PIPELINE.md](PIPELINE.md).
- **One Cloudflare token serves both environments.** An expired token blocks staging and production web deploys together (INC-1, INC-6), and a failed scheduled check notifies no one. See "Open risks" in [PIPELINE.md](PIPELINE.md).
- **Rollback is only partly rehearsed.** A staging Cloud Run rollback was executed on November 5; no production rollback and no Cloudflare Pages rollback has been rehearsed.
- **Trip archive is not implemented.** Trips can be created, edited and deleted. The trip update API has no status field and Flutter has no archive action.
- **Android release signing.** Without a private `key.properties`, release builds are signed with the debug key.
