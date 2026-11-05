# S4 acceptance evidence: #108, #114 and #116

Recorded November 4, 2026 (Asia/Manila), for the development and zero-traffic staging checks performed November 3–4. **This record is not release authorization.**

## Scope and reviewed changes

- [#108](https://github.com/relax-mode/lagaw/issues/108) — [PR #136](https://github.com/relax-mode/lagaw/pull/136), destination-image Storage.
- [#114](https://github.com/relax-mode/lagaw/issues/114) — [PR #135](https://github.com/relax-mode/lagaw/pull/135), backend AI extraction quotas.
- [#116](https://github.com/relax-mode/lagaw/issues/116) — [PR #134](https://github.com/relax-mode/lagaw/pull/134), backend health/readiness/API documentation.
- All three feature PRs had reviewer approvals and passing individual CI when checked. All remain **open and unmerged**.
- Integration-only candidate `test/s4-integrated-validation` at commit `81f2645`; [draft PR #148](https://github.com/relax-mode/lagaw/pull/148) is **not for merging**.
- [PR-scoped CI run 41613721297](https://github.com/relax-mode/lagaw/actions/runs/41613721297): gitleaks, backend, and database passed; frontend/dependency audit skipped under path filtering. The manually dispatched [run 41613030891](https://github.com/relax-mode/lagaw/actions/runs/41613030891) had successful backend, database, frontend and dependency jobs but **failed its full-history gitleaks scan** (one finding among 166 commits). This is an outstanding security review, not a passing full-history scan.
- Focused offline tests for quota, image-storage and health: **28 passed** on the integration candidate. Earlier non-database regression: **1,091 passed**, excluding known Windows-only file-mode assertions.

## #108 — destination image Storage: development acceptance

- Only Supabase **development** project `vnpkyvtbupnquvirzlzp` was modified. Migration `20261103100000_destination_image_storage_policies.sql` was applied there.
- `destination-images` permits public retrieval, JPEG/PNG/WebP, and files at most 5 MiB. Anonymous client upload was rejected by RLS.
- An operator-provided 22,143-byte JPEG for **San Sebastian Cathedral**, destination UUID `1a3bca09-5532-5de6-8587-2440c4e5830d`, passed the offline `scripts/destination_images.py` dry run.
- Following the operator's explicit `--approved-usage` confirmation, the development-only upload/link script reported successful public-image retrieval and location linking. Source licensing was not independently audited here.
- Development `public.locations.image_url` changed from NULL to a public Storage URL without overwriting a pre-existing reference.
- Independent credential-free public image GET returned **HTTP 200**. Staging `GET /locations` returned **HTTP 200** and included the matching linked image URL for the cathedral.

## #114 — extraction quota: development acceptance

- Only Supabase **development** project `vnpkyvtbupnquvirzlzp` was used. Migration `20261103090000_ai_extraction_quotas.sql` was applied there.
- The operator set the disposable QA account's current UTC daily counter to its maximum supported value (**200**), after verifying the corresponding linked development profile. No actual provider requests were needed to exhaust quota.
- The zero-traffic staging canary accepted the QA account's Supabase authentication and returned **HTTP 429**, `Retry-After: 26687`, and `extraction_quota_exceeded` for a request with exhausted quota.
- The backend checks quota before the DeepSeek invocation; separate automated tests mock the provider and verify that rejected requests do not call it. No paid DeepSeek request was initiated by this verification.
- This is acceptance evidence for an **exhausted** quota, not independent proof of paid-provider billing limits or production rollout.

## #116 — health/readiness/API docs: staging acceptance

- Cloud Run staging-only revision `lagaw-api-staging-00038-cuc` was built from candidate `81f2645` and tagged `s4-qa` with **0% normal staging traffic**.
- Live tagged revision: `GET /health` **200** (`{"status":"ok"}`); `GET /ready` **200** (`{"status":"ready"}`); `GET /openapi.json` **200** with liveness, readiness and extraction operations.
- Public locations endpoint **200**, missing-auth extraction request **401**, API docs **200**.
- After acceptance the operator removed the `s4-qa` tag, and checked Cloud Run traffic again: old staging revision `lagaw-api-staging-00035-xp9` remained at **100%**.

## Pending definition-of-done and release gates

1. Post or link this evidence on issues #108, #114 and #116 (and the corresponding feature PRs); review evidence with the assignees.
2. Triage the single **full-history** gitleaks finding (without printing a credential); rotate if genuine, document any false-positive decision narrowly.
3. Confirm production Supabase image-storage and quota migration sequencing, availability of deployment/rollback owners, and the impact of quota RPC fail-closed behavior. **No production migrations have been authorized.**
4. Obtain explicit authorization before any merge: merging app feature PRs to `main` invokes the staging-to-production deployment pipeline. The issues' course definition of done requires reviewed merge, successful pipeline and deployed verification. **Acceptance-tested does not yet mean fully closed.**

This document records observations only; no production Supabase, production API, or production Cloud Run changes were made during this validation.
