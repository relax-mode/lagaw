# Preference extraction verification — October 25, 2026

Implementation builds on the existing Sprint 1 DeepSeek helper and S3-01 contracts
at local base commit `5e043c0`. The [API contract](../preference-extraction-api.md)
documents the implemented request/response/error shapes, normalization, confirmation,
manual fallback and deployment handoff. Andrew/Roel agreement remains pending.

Initial focused command from `backend`:

```powershell
python -m pytest test_preference_extraction.py test_deepseek.py -q
```

Result: **58 passed**, one existing Starlette HTTPX deprecation warning. All calls
use dummy environment configuration, blocked dotenv loading and mocked provider
HTTP. No network call, paid request, real credential, saved-trip change or deployment
was made by these tests.

Coverage includes six synthetic evaluation cases: cheap cafe afternoon, heritage
morning, explicit form choices overriding extraction, explicit tag clearing/zero
budget, unspecified defaults and numeric free text requiring form confirmation.
HTTP checks cover pre-provider request validation, authentication/context gating,
success, canonical tag validation, deduplication, budget/type validation, prompt
limits, timeout/rate/provider/configuration/transport failures, malformed/truncated
output, sanitized responses and unchanged saved Trip data. OpenAPI exposes the
versioned route and existing TripDemoToken scheme. A catalog-vocabulary regression
check prevents silent divergence from the approved source tags.

Follow-up verification after adding development-only `httpx2>=2.16,<3` passed
**217 backend tests in 3.25 seconds with no warnings**. Starlette now selects
httpx2 for TestClient; runtime DeepSeek/database clients retain their existing
httpx dependency. The first lint pass found an import-formatting issue left from
the blocked final verification; it was corrected before the final lint check.

These tests
establish API behavior and mocked integration, not live extraction model accuracy.
No CI, reviewed PR, merged artifact or deployed revision is claimed yet.

Remaining evidence: teammate agreement/review, issue/PR links, actual required CI
run, merged commit, deployed revision, controlled authorized backend extraction and
saved-trip preservation in the deployed environment. Use the contract's deployment
handoff checklist; do not mark the issue Done before those gates are complete.
