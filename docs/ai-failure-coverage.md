# AI failure coverage, recovery and evaluation limits

Assessed November 1, 2026 on `test/ai-failure-coverage`, based on merged main
`baf1e9d` (content-first evaluation PR #132). Related:
[#50](https://github.com/relax-mode/lagaw/issues/50) extraction,
[#57](https://github.com/relax-mode/lagaw/issues/57) evaluation,
[#58](https://github.com/relax-mode/lagaw/issues/58) manual fallback,
[#114](https://github.com/relax-mode/lagaw/issues/114) coordination.

The [approved pitch](pitch.md) and [course instructions](official-instructions.md)
remain ground truth. This is a targeted coverage/documentation update: existing
production error handling and ranking behavior did not need changes. General
infrastructure, rate limiting, UI redesign, live provider calls, collaborative
deployment and catalog edits are outside this work.

## Assessment: what was already covered

Existing suites already exercise these failure paths; this task retains and reuses
them rather than introducing duplicate coverage:

| Existing behavior | Evidence in `backend/` |
| --- | --- |
| Invalid prompt/configuration rejected; missing provider key | `test_deepseek.py`, `test_preference_extraction.py` |
| Unsupported values, extra/missing fields, malformed JSON, truncated output and content-filter finishes rejected | `test_invalid_provider_output`, `FailureTests.test_truncated_and_malformed_outputs_are_rejected` |
| HTTP 400/401/402/403/404/429/500/503, read timeout and connection failure have safe error mappings | `test_provider_http_failures_are_safe_and_leave_trip_unchanged`, `test_transport_failures` |
| Confirmation required, explicit form precedence, extraction does not save | `test_evaluation_cases` and Week 3 fixtures |
| Missing/corrupt/incompatible artifacts produce content fallback with a safe logged reason | `test_unusable_artifacts_serve_the_content_baseline_with_a_logged_reason` in `test_trip_recommendations.py` |
| Unseen/sparse users and places use content scores | `test_unseen_users_locations_and_sparse_user_fallback`, `test_sparse_item_support` |
| Invalid recommendation output and engine exceptions fail safely | `test_malformed_model_output_fails_safely_without_writes`, `test_model_exception_is_sanitized` |
| Budget/group/activity checks, exclusions and database freshness remain enforced | `test_hybrid_recommendations.py`, `test_trip_recommendations.py`, `test_onboarding_recommendations.py` |

## Missing cases added

The audit identified **28 additional parameterized test cases** across the existing
test files. No existing fixture expectations or committed evaluation baseline were
replaced to obtain passing results.

### Provider envelope/content failures: 18 cases

Extended `test_invalid_provider_output` in `test_preference_extraction.py` with:

- Null/list top-level response bodies.
- Null/object/string `choices`, null choice entries and missing finish reason.
- Null/list message objects.
- Null, numeric, boolean, list and object `message.content` instead of JSON text.
- JSON text containing null or an array rather than the required object.
- HTTP 200 with HTML or undecodable bytes rather than a JSON response envelope.

These use real HTTPX responses through MockTransport and the actual helper and
Pydantic validation, not a mocked extraction result. Existing malformed-output
cases now also verify exactly one provider call, `manual_fallback: true`, unchanged
saved-trip retrieval and no create/update/delete calls. Sensitive sentinel values
must not appear in the HTTP response. This tests response sanitization, not a
general claim that every possible logging system is secret-free.

### Additional transport stages: 3 cases

Extended `test_transport_failures` with connection timeout, interrupted-response
protocol failure and response-read failure. Connection timeout maps to HTTP 504
`extraction_timeout`; protocol/read transport errors map to HTTP 503
`extraction_unavailable`. The earlier read-timeout/connect-error cases remain.
All cases now check one provider attempt, manual-fallback metadata, safe errors
and unchanged saved data with no trip mutation calls.

### Explicit later extraction recovery: 3 cases

`test_failure_then_explicit_new_request_recovers_without_writes` sequences an HTTP
503 outage, null content or interrupted response, followed by a separate valid
request in the same test session. It verifies the first failure causes no hidden
retry, the later request succeeds with confirmation still required, explicit tags
and budget take precedence, and the saved trip remains unchanged throughout.

This is an explicit second client request, not a new retry feature. Mocking recovery
does not measure actual provider recovery time or guarantee the real service will
recover on the next request. The backend tests do not control a Flutter form.

### Nonfinite collaborative prediction: 3 cases

`test_nonfinite_prediction_uses_full_content_and_preserves_exclusions` in
`test_hybrid_recommendations.py` injects NaN, positive infinity and negative
infinity at the dot-product boundary of a validated synthetic fitted model.
It exercises `CollaborativeModel.score` and real hybrid ranking, verifies
`invalid_model_score` is identified, compares the returned scores with the **full**
content scores (not 60% of them), checks ordered IDs and explicit exclusions,
revalidates output, and confirms model state was not mutated.

This tests a numerical serving failure. It does not prove training quality,
production artifact correctness or universal recovery from unexpected exceptions.

### Later recommendation recovery: 1 case

`test_engine_error_does_not_poison_later_content_only_request` in
`test_trip_recommendations.py` first supplies a failing engine and verifies a
sanitized 503 with unchanged saved trip. A later explicit request using the
existing no-model engine returns content recommendations. Database requests are
asserted GET-only. The test changes the injected test engine between requests;
it does not introduce or claim a production hot-reload or automatic engine switch.

## What actually happens at runtime

| Condition | Implemented outcome | Boundary/limitation |
| --- | --- | --- |
| Malformed provider envelope, JSON, schema or unfinished output | 502 `invalid_extraction_output`, `manual_fallback: true` | No partial extracted preferences are accepted or saved |
| Provider/network unavailable or configured credentials/model unusable | 503 `extraction_unavailable`, manual fallback metadata | Backend signals that the manual form can be used; it does not render that form |
| Provider timeout | 504 `extraction_timeout`, manual fallback metadata | Existing timeout configuration applies; no automatic paid retry |
| Provider rejects request | 502 `extraction_failed` | Safe public message, no raw provider response |
| Provider rate limit | Existing 429 `extraction_rate_limited` | No rate-limiting mechanism was added or changed |
| Missing/unusable collaborative artifact | Existing loader selects content-only engine | Supported artifact load failures, not every conceivable process failure |
| User/place unseen or insufficiently supported | Full content score for that candidate | Request events do not instantly retrain fitted factors |
| Predicted collaborative affinity is nonfinite | Full content score with `invalid_model_score` reason | Does not bypass budget, exclusions or other eligibility rules |
| Unexpected engine exception or invalid output at saved-trip API boundary | Sanitized 503 | No automatic retry using a different engine is promised |
| No eligible destinations | Valid HTTP 200 with empty `items` | No fabricated places or forced schedule; incomplete catalog can cause this |

Preference extraction returns only a draft for confirmation and never persists
preferences/trips itself. Saving confirmed fields uses the existing Trip API.
Recommendation APIs are read-only. These tests use fake stores/mock transports;
they verify calls and response behavior, not live database transactions. Existing
Flutter manual fallback behavior remains #58's scope; this task adds no UI tests
or redesign and makes no new browser/device acceptance claim.

The onboarding endpoint remains intentionally content-only and does not consult
interaction history. For history-aware exclusions, use the saved-trip path. Existing
conservative catalog filtering and missing facts still limit coverage; see the
[content-first evaluation and roadmap](content-first-evaluation.md).

## Reproducible evaluation and measured results

Use the declared development dependencies and the project Python environment.
From the repository root, then `backend`:

```powershell
Set-Location backend
python -m pytest -q test_preference_extraction.py test_hybrid_recommendations.py test_trip_recommendations.py
python evaluate_week3.py --check --output test-results/ai-failure-evaluation.json
python -m app.recommendations.evaluate_cold_start --output test-results/ai-failure-cold-start.json
python -m ruff check .
```

The targeted three-suite run passed **222 tests in 11.47 seconds**. The expanded
Week 3 `--check` run passed **350 tests in 11.90 seconds** and reported:

- **27/27 extraction fixture scenarios** passed: 12 accepted, 15 rejected.
- **84/84 expected extraction fields** passed.
- **10 existing content scenarios** passed; no evaluation failures.
- The existing synthetic hybrid comparison remains unchanged; it is not organic
  relevance or live-provider evidence. The existing evaluation internally fits its
  synthetic fixture model, as before; no production retraining or artifact change
  is performed.
- The separate cold-start command exited successfully with all **32 case/catalog
  behavior checks** passing.
- Backend Ruff passed. Runtime observed: Python 3.12.10 on Windows, FastAPI
  0.143.1, Pydantic 2.14.1, HTTPX 0.28.1, HTTPX2 2.16.0, NumPy 2.5.4.

The 28 new test cases supplement the existing fixture scenarios; they are not
claimed as additional Week 3 fixture cases. The evaluation's `TEST_FILES` list now
also runs `test_trip_recommendations.py` and `test_onboarding_recommendations.py`
so `--check` includes the existing HTTP recommendation fallback/output boundaries.
No CI workflow or general infrastructure was modified; pytest already discovers
the changed test files.

Both generated reports live under gitignored `backend/test-results/`; regenerate
them with the commands above. The existing committed
[Week 3 baseline](evidence/week3-evaluation.json) remains unchanged and its drift
checks pass. Its fixture revision is still `week3-eval-v1`, with outgoing prompt
SHA-256 `92a8614f8bcff4aff3017d52be3e996684ca64cfdc8db8c16329280fd8ed444f`.
Test counts/timings are dated local observations and will change as suites grow.

## Interpretation and delivery limits

Mocked extraction checks schema/error/confirmation handling; it does not measure
live model semantic accuracy, prompt-injection resistance, latency, actual outages
or availability. Seeded/synthetic hybrid results do not establish organic traveler
quality or deployed collaborative reliability; those remain separate
[#94](https://github.com/relax-mode/lagaw/issues/94) evidence and evaluation concerns.
The approved pitch's older connectivity-pending statement conflicts with the
existing Sprint 1 smoke evidence; neither proves current provider availability.

No raw environment values or real keys were read. No paid provider, real database
write, live endpoint acceptance, deployment, production retraining or new infrastructure was
used. CodeGraph/fd were unavailable locally; known source paths and rg were used.
The sprint log records actual local work. Review, CI, merge and issue linkage remain
delivery gates; these local checks do not claim teammate agreement or completed
integration. The full repository suite was not rerun for this targeted change.
