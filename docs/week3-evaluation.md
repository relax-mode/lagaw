# Week 3 offline evaluation suite (#57)

This suite extends S3-01 fixtures and reuses the existing #50 extraction API,
#33 content baseline and #51 held-out hybrid evaluation. It satisfies the Week 3
requirement for example inputs with acceptance checks and mocked LLM regression
tests. It does not repeat Sprint 1 connectivity or change endpoint/model behavior.

## One offline command

After installing `backend/requirements-dev.txt`, run from `backend`:

```powershell
python evaluate_week3.py --check
```

The command evaluates the fixtures, writes `backend/test-results/week3-evaluation.json`
(gitignored), then runs the existing provider, extraction API, contract, content,
hybrid and new evaluation tests. It returns nonzero on fixture acceptance failures
or failing tests. It never contacts DeepSeek or requires a real provider key.
The harness replaces configuration with dummy values, blocks dotenv loading,
uses HTTPX MockTransport and blocks real HTTPX transport. Trip reads/writes use a
fake store; real database persistence/ownership defects remain with feature owners.

To evaluate without the combined pytest suite, omit `--check`. To deliberately
refresh the reviewable committed report after reviewing a fixture/prompt change:

```powershell
python evaluate_week3.py --output ../docs/evidence/week3-evaluation.json
```

Do not refresh the committed report automatically in CI: it is the comparison
baseline, and silently overwriting it would defeat drift detection. Compare its
diff and update the fixture revision for intentional semantic changes.

## Fixtures and acceptance checks

`backend/fixtures/extraction/manifest.json` identifies revision **week3-eval-v1**,
the implementation base `fd5a31e`, synthetic provenance and the related fixture
files. The original six extraction cases remain, extended to **12 representative
success cases** in `cases.json`; `regressions-v1.json` adds **15 rejection/failure
cases**. All IDs are unique. The versioned manifest also references the existing
ten recommendation cases and the fixed-seed hybrid dataset, without duplicating
or relabeling their data as real user interactions.

Coverage includes low/medium/high and unspecified budgets, all approved tags,
morning/afternoon/evening/full-day and missing duration, different pace values,
ambiguous budget/time choices, negated tags, numeric free-text without numeric
form input, explicit form precedence/clearing, zero budget, invalid budget ordering,
unsupported tags/values, adversarial instructions and non-travel requests.

Each success has a prompt, a **stubbed** provider body, explicit form values and
seven explicit expected fields: `preferred_tags`, `budget_level`, `duration`,
`pace`, `budget_min`, `budget_max`, `group_type`. The HTTP harness checks each field
(84 assertions), schema validity, confirmation flag, total-trip budget scope,
missing-field reporting, provider call count, response sanitization, no writes and
saved-trip equality before/after extraction. The API's actual helper and validators
process every stub; outputs are not simply returned from a fake route.

Each rejection/failure fixture supplies its expected status, stable error code,
provider call count and simulated provider/configuration condition. Cases cover
timeouts, rate limits, authentication/provider/network failures, malformed/truncated
JSON, extra/missing fields, unsupported tags/budget values, missing/invalid provider
configuration and pre-provider request rejection. All errors must remain sanitized,
manual-fallback compatible and leave saved data unchanged. Existing
`test_deepseek.py` and `test_preference_extraction.py` retain their broader checks;
the evaluation reuses them rather than moving endpoint defect ownership here.

For non-travel/adversarial input, the stub supplies an `unspecified`/empty draft
or an intentionally invalid schema. A valid empty draft requires confirmation and
does not create a trip. These cases do **not** prove the live provider recognizes
irrelevant input or withstands prompt injection; the API has no semantic
non-travel classifier. That is an explicit evaluation limitation, not a measured
security guarantee.

## Identifiers and report interpretation

The [committed report](evidence/week3-evaluation.json) records:

- Fixture revision and canonical JSON SHA-256 digests for the manifest, extraction
  success/failure sets, S3-01 recommendation cases and #51 dataset. Canonical hashing
  avoids Windows/Linux line-ending differences.
- SHA-256 of the **actual system prompt (including its schema)** captured from the
  first mocked outbound request, and a configuration digest. It is not a separately
  maintained copy of the prompt.
- Requested model alias `deepseek-flash`, `response_format=json_object`, thinking
  disabled, `max_tokens=512`, streaming disabled and 30-second timeout components,
  captured from the real helper's mocked HTTP request. The actual provider model
  revision is `unknown_not_contacted`; a configurable alias is not a frozen model.
- Python/platform/package observations, per-case accepted/rejected checks and safe
  failed-check names, field-level totals, content acceptance cases, and synthetic
  content/hybrid top-N metric summaries with training digest/seed and split counts.

`test_week3_evaluation.py` compares fresh prompt/configuration/fixture identifiers
and extraction/content behavior to the committed baseline. Recommendation metric
summaries allow a small floating-point tolerance for NumPy platforms. Machine/runtime
observations are recorded without requiring identical OS/Python patch versions.
Changing a prompt, fixture or request configuration therefore surfaces as drift
even when the same stub outputs still validate. An intentional wrong expected
pace is also tested to ensure a field mismatch is reported and the CLI's failure
exit path works. Individual failed-check names identify regressions without logging
provider bodies, tokens or submitted private prompts.

## Three distinct kinds of evidence

1. **Stub-based extraction regression:** proves schema validation, normalization,
   explicit-choice precedence, safe errors and no writes under controlled outputs.
   The field acceptance rate is not DeepSeek extraction accuracy.
2. **Synthetic recommendation evidence:** reuses the ten content cases and #51's
   24 held-out targets, absent from training/history. Reports Recall@3, NDCG@3 and
   HitRate@1 for both algorithms. Recoverable clusters, uniform costs and missing
   tag/category preferences favor this synthetic collaborative comparison; they
   do not establish real-user quality.
3. **Live provider evaluation:** **not performed**. A separately authorized paid
   activity should preserve this fixture revision/prompt/configuration, record
   actual provider/model metadata, score newly observed fields against acceptance
   expectations and report every failure separately. It must never become a PR
   dependency or be represented by copying the stub results. No new live runner or
   connectivity test is introduced here.

See the [measured local results](evidence/week3-results.md), the
[extraction contract](preference-extraction-api.md) and
[hybrid limitations](hybrid-recommender.md).

## Handoff for Kyle (prepared, not sent)

The current backend CI already installs development requirements and runs pytest,
so the new tests are automatically discoverable. Kyle can add the dedicated
`python evaluate_week3.py --check` command after installation, or keep the existing
full pytest job and add the report-only command to avoid duplicate test execution.
Use Python 3.12 and no real API credentials or `.env` in the job. Upload
`backend/test-results/week3-evaluation.json` even on failure when it exists; lint
and all required existing backend/database/frontend checks still apply.
No CI workflow ownership or deploy policy is changed in this issue.

After the PR exists, Kyle should link the actual successful run and uploaded report,
record the reviewed merged commit and verify the evaluation fixtures/report/tests
are present in that integrated checkout. This test/documentation work introduces no
runtime functionality requiring a new paid/deployed endpoint smoke call. Actual CI,
teammate review, merged artifacts and issue links are still Definition of Done gates;
local results and this handoff document do not claim they have happened.
