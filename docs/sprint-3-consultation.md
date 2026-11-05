# Sprint 3 Consultation Pack (November 1, 2026)

Prepared by CyGray for [#59](https://github.com/relax-mode/lagaw/issues/59). Re-check every item marked *pending* on October 31 and update this file with what actually happened. Never mark a check done ahead of time.

## 1. Live demo (4 min, from the deployed app)

### Before the session

- [ ] Confirm #68 and #73 are merged and the latest `main` run shows `Deploy - Production API` and `Deploy - Production web` green. Until then, production lacks the AI routes ([INC-3](incident-log.md#inc-3-production-drifted-behind-main)).
- [ ] 10 minutes before: wake both APIs (`curl -s <api>/locations?limit=1`). They scale to zero, and a cold start takes a few seconds.
- [ ] Open `https://lagaw.pages.dev` (production) and `https://staging.lagaw.pages.dev` (fallback) in separate tabs.
- [ ] Confirm the DeepSeek balance covers the demo. Holder: Kyle.

### Demo path

Steps 3 and 4 depend on #53, #54, #55 and #56; mark any that have not shipped as *not shipped* and explain why.

1. Type a request in the trip form, for example *"a cheap, relaxing afternoon with coffee and photography spots"*. Show the validated preference draft and that it requires confirmation (#55).
2. Show what the backend did with the output: schema validation, canonical tags, budget scope, missing fields, and no trip written until the user confirms (#50).
3. Get recommendations for the confirmed preferences (#53 → #56).
4. Generate and save the itinerary, then reload to show it persisted (#54 → #56).

### Failure handling

- **AI failure.** Point the app, or an API call, at the zero-traffic `aifail` staging revision (drill steps in [`PIPELINE.md`](../PIPELINE.md#ai-failure-drill)). Expect `503 extraction_unavailable` with `manual_fallback: true`, and the standard trip form in the app. Verified on staging October 26 ([evidence](evidence/ai-ci-cd-2026-10-26.md)).
- **Malformed request.**

  ```sh
  curl -s -X POST <api>/api/v1/preferences/extract \
    -H "Authorization: Bearer <demo token>" -H "Content-Type: application/json" -d '{"prompt": ""}'
  ```

  This returns 422 with a readable validation body. The provider is never called.

## 2. Board walkthrough (3 min)

Use the [Sprint 3 plan and status table](sprint-log.md#sprint-3-plan-and-status-recorded-october-26) and the [milestone](https://github.com/relax-mode/lagaw/milestone/3). Before presenting, refresh each row's status and the reason for any slip.

## 3. AI evidence

| Requirement | Evidence |
|---|---|
| Structured output processed by the backend | Extraction API (#50, PR [#64](https://github.com/relax-mode/lagaw/pull/64)), [preference extraction write-up](preference-extraction-api.md) |
| Small evaluation set | 12 success and 15 regression extraction fixtures, plus 10 recommendation cases ([evaluation suite](week3-evaluation.md), [results](evidence/week3-results.md), PR [#66](https://github.com/relax-mode/lagaw/pull/66)) |
| Mocked LLM tests in CI, no paid calls | Green run [40308275898](https://github.com/relax-mode/lagaw/actions/runs/40308275898) with no provider key in GitHub. Failure probes [40307281405](https://github.com/relax-mode/lagaw/actions/runs/40307281405) and [40308048372](https://github.com/relax-mode/lagaw/actions/runs/40308048372) ([AI CI/CD evidence](evidence/ai-ci-cd-2026-10-26.md)) |
| Evaluation reruns on prompt or AI changes | Backend job summary "AI evaluation versus baseline", compared with the target branch's baseline |
| AI error handling | Safe failure codes with `manual_fallback` ([regression fixtures](week3-evaluation.md)); staging failure drill |
| Recommendation quality | [Content-based results](evidence/content-based-results.md), [hybrid results](evidence/hybrid-results.md) |

## 4. DevOps report (3 min)

### What changed this sprint

1. **Path-filtered PR checks** (#31, PR [#68](https://github.com/relax-mode/lagaw/pull/68)).
   - Docs-only PRs: 83 s → **9 s**.
   - Backend-only PRs: 90 s → **54 s**.
   - The `psql` step: 8 s → 0 s.
2. **AI evaluation gate and network guard** (#58, PR [#73](https://github.com/relax-mode/lagaw/pull/73)). CI cannot call DeepSeek, and a quality drop fails even if the author refreshes the baseline.
3. **Automatic production promotion** (#58). Every qualifying merge goes staging → production with no manual step. This resolves the earlier manual-production policy and INC-3.
4. **Scheduled live checks**, twice a week: one real extraction through staging, plus the Cloudflare credential.
5. **Staging acceptance** (#30, PR [#67](https://github.com/relax-mode/lagaw/pull/67)). A browser write landed in the development database only.

### Metrics log

[Weekly metrics log](pipeline-metrics.md#weekly-metrics-log): fill the Sprint 3 row on October 31 with `python scripts/pipeline_metrics.py --since 2026-10-26 --until 2026-11-01`.

| Week | Avg PR time (min) | Main time (min) | Success rate (%) | Production deploys | Lead time (min) | Failed deploys | Time to recover (min) |
|---|---|---|---|---|---|---|---|
| Sprint 1 | 4.5 | 1.9 | 96.8 | 2 | 4.2 | 0 | n/a |
| Sprint 2 | 1.6 | 2.2 | 96.6 | 3 | 1.9 | 2 | 863.9 |
| Sprint 3, Oct 26 only (partial) | 1.5 | n/a | 100.0 | 0 | n/a | 0 | n/a |

The Sprint 3 partial row excludes 9 deliberate probe runs that proved the gates fail when they should. The final row replaces it.

### Incidents ([incident log](incident-log.md))

| ID | What | Postmortem |
|---|---|---|
| INC-1 | Staging Cloudflare credential rejected | Fixed by a token replacement; prevented by the scheduled credential check |
| INC-2 | A staging approval wait blocked `main` CI for about 53 h | Fixed by per-run concurrency and job timeouts |
| INC-3 | Production four days behind `main` under manual deploys | Fixed by automatic promotion; closes on the first promotion run |

### Next sprint (DevOps)

- A rollback workflow and a tested rollback drill.
- A tagged release with a changelog.
- A second optimization: the Flutter build time.
- Secret scanning and dependency audit.
- Per-environment Cloudflare tokens and deployer identities.

## 5. After the consultation

Record in the [sprint log](sprint-log.md), only after the session:

- Instructor feedback, as given.
- A retrospective: what went well, what did not, and one change for Sprint 4.
- Re-planned items, with reasons.

## 5a. Week 3 pipeline report completed after the consultation

The Sprint 3 pipeline row, formerly partial as of October 30, was regenerated
on November 5 from completed GitHub Actions metadata for the full October
26–November 1 UTC window: **98 runs (94 success, 2 failed, 2 cancelled),
97.9% success rate** (excluding cancelled runs), **1.1 min average PR pipeline,
4.7 min average main pipeline, 27 successful production deployment jobs,
6.3 min measured merge-to-deploy lead time (16 of 30 merges), zero failed
main deploy jobs, no measured failed-deploy recovery time**. Nine deliberate
probe runs are excluded. These are **post-consultation backfilled metrics**;
they must not be represented as numbers shown to the instructor during the
consultation. The dated source, metric definitions and incident caveats are in
[pipeline-metrics.md](pipeline-metrics.md#sprint-3-source-completed-week-queried-november-5-2026).

## 6. Actual consultation outcome — user-reported November 5, 2026

The team subsequently reported that its **Week 3 consultation occurred**, with a
**live demonstration of the staging Lagaw app**. The instructor's feedback was:

1. **Address corner cases** in the application (which cases were not specified,
   so this is a broad QA action rather than verified issue-specific acceptance).
2. **Set up the Storage bucket** for destination images (tracked in Sprint 4
   [#108](https://github.com/relax-mode/lagaw/issues/108)); implementation,
   hosted setup and image acceptance must be evidenced separately.
3. **Be ready for the November 11, 2026 deadline with a 90%-complete app**;
   this is the instructor's target, not a verified completion percentage.

**Evidence limits:** this report was supplied by a team member on November 5,
2026. The exact consultation date, participants, demonstrated individual
backend/AI workflows, the instructor's exact wording beyond this summary, and
a formal retrospective were **not supplied**. Do not infer they occurred.
The earlier checklist above is **preparation**, not proof each step was
performed live. Link completed corner-case tests and the Storage acceptance
separately as they happen.

## 7. Historical AI demo-readiness evidence reconciliation — November 5, 2026

The consultation pack above was written before the application path was fully
implemented. By November 5 the team had **separate, documented deployed
acceptance evidence** supporting each stage of the planned live demonstration:

| Planned stage / acceptance dimension | Actual dated evidence | Limitation |
| --- | --- | --- |
| Natural-language request -> backend structured output -> user-reviewed preferences | [S3-10 Flutter extraction evidence](evidence/trip-preference-extraction.md) records an Android trial and a **staging Web trial on October 29**, including a real API suggestion, review/apply and an account-scoped saved trip; [extraction API contract](preference-extraction-api.md) documents backend validation and confirmation. | The professor's reported demo did not identify which individual screens were shown. |
| Ranked recommendations | [S3-08 API evidence](evidence/trip-recommendations.md) records authenticated **staging and production** responses from saved trips, including score, reason, and an empty match; [S3-11 Android evidence](evidence/trip-planning-ui.md) records ranking UI from staging on October 29. | Separate acceptance cases, not a single recorded consultation interaction. |
| Generate persisted itinerary / reload | [S3-09 deployed itinerary evidence](evidence/itinerary-generation.md) records authenticated **staging and production** generation, persistence and reload with synthetic venues; [S3-11 Android evidence](evidence/trip-planning-ui.md) shows a generated plan and persistence after completely restarting the staging-connected app (shots 56_7 and 56_17). | Screenshots of a successful replacement and an Android generated plan from a manual-only trip were not captured. |
| Controlled AI failure and manual fallback | [S3-13 staging failure drill](evidence/ai-ci-cd-2026-10-26.md) returned HTTP 503 `extraction_unavailable` with `manual_fallback: true` from a zero-traffic `aifail` revision on October 26; [S3-10 Android/Web fallback evidence](evidence/trip-preference-extraction.md) shows an offline network failure retaining input and permitting a manual save. | The 503 drill and manual-save UI were exercised separately, not recorded as one combined live user action. |
| Backend AI response processing and deterministic evaluation | [S3-05 API contract](preference-extraction-api.md), [Week 3 evaluation](week3-evaluation.md) and [results](evidence/week3-results.md), plus [S3-13 AI pipeline evidence](evidence/ai-ci-cd-2026-10-26.md) linking passing CI and deliberate failure probes. | Fixtures and metrics are designed evaluation evidence, not measured organic recommendation quality. |
| Mocked AI CI without paid calls | [Green CI run 40308275898](https://github.com/relax-mode/lagaw/actions/runs/40308275898) and failing probes [40307281405](https://github.com/relax-mode/lagaw/actions/runs/40307281405) and [40308048372](https://github.com/relax-mode/lagaw/actions/runs/40308048372) document no-provider-key mocked validation and the regression gate. | This proves CI behavior, not that the CI was discussed in consultation. |

**Conclusion:** the end-to-end demo path was prepared and its steps had
**independently verified deployed examples**. A single continuous staged run
(request -> extraction -> recommendations -> generated persisted itinerary ->
forced AI failure) was **not recorded**, and the professor's observed steps
remain unspecified. Do not state that all stages were shown during the
consultation. These evidence links establish **demo readiness and the evidence
pack's coverage**, not an invented witnessed demonstration.

## 8. Sprint 3 team coordination — asynchronous updates, not standups

The team reported on November 5 that **no formal Sprint 3 standup meetings
were held**. Progress coordination happened in its group chat, and the GitHub
PR review/request cycle was used as a repeatable status handoff. The group-chat
messages were not supplied; do not quote or infer their contents.

Three dated, GitHub-verifiable PR-based checkpoints provide the equivalent
progress evidence for issue #59: [Oct 27, #77](https://github.com/relax-mode/lagaw/pull/77)
(Kyle's CI promotion recovery and the blocked `main` deploy),
[Oct 28, #89](https://github.com/relax-mode/lagaw/pull/89)
(Andrew's itinerary generation, contract/migration acceptance pending), and
[Oct 29, #99](https://github.com/relax-mode/lagaw/pull/99)
(Roel's Flutter planner with staging Android validation, Web acceptance still
pending). Their summaries record done/next/blockers with real review/merge
links and dates in the [Sprint 3 log](sprint-log.md#november-5-2026--sprint-3-asynchronous-pr-reviews-as-team-status-updates-59).
The original course requirement is for **2–3 asynchronous team-channel
standup posts in the sprint**, each identifying done/next/blockers per person.
PR review requests are verifiable **partial progress evidence**, but the
unprovided group-chat exchanges cannot be audited and are not assumed to meet
the rubric. Therefore the corresponding original S3-14 standup checkbox is
**still pending**. No scheduled meetings or standup attendance are claimed.
