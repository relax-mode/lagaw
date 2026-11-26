# Lagaw panel readiness: combined audit and release checklist

**Baseline:** `f4076c61c81885ef94cb55051634a43189bb6bc2` on `main`.
**Reviews:** GPT-6.2 Astra High and Antigravity Gemini 4 Neon Extra High, through Agent Hub.
**Scope:** Flutter, API and storage, AI and recommendations, and release readiness. This is a source review, not a penetration test or a certification of the deployed app. This public document records hardening goals and acceptance criteria. Detailed security evidence belongs in a restricted team channel until fixes ship.

**P1** means fix or verify before the panel. **P2** is follow-up unless it affects the chosen demo flow.

## Frontend (FE)

| Priority | Work item | Acceptance criteria |
| --- | --- | --- |
| P1 | Isolate account state across navigation and asynchronous requests | Reset protected navigation and account-scoped state when identity changes. Discard stale responses and never retry a write under a different identity. Recovery for the same account may retain an unsaved draft. |
| P1 | Recover from uncertain trip saves | Restore interactive state after a timeout or unexpected response. Offer a clear recovery path through My Trips. Preserve the submission ID if the user retries. |
| P2 | Explain quota cooldowns | Distinguish temporary provider errors from an account cooldown. Show a retry time when available and keep manual entry accessible. |
| P2 | Make destination browsing incremental | Load additional results on demand, keep scrolling responsive, and ignore or cancel outstanding results when the view closes. |

## Backend (BE)

| Priority | Work item | Acceptance criteria |
| --- | --- | --- |
| P1 | Verify production request controls | Confirm route-level rate, request-size, timeout, and concurrency settings at the API ingress. Bound database-backed public reads and distinguish platform instance caps from per-request controls. |
| P1 | Make writes safe to retry | Use owner-scoped action IDs. Repeating the same action returns the original outcome; unrelated actions remain independent. Apply to trip creation and interaction events. |
| P1 | Enforce trip and itinerary consistency | Date changes and itinerary updates maintain a consistent trip window. Reject conflicting changes clearly or require explicit adjustment. Recompute or invalidate derived costs when inputs change. |
| P2 | Bound recommendation work | Cache appropriate catalog data, bound history processing by design, and retain meaningful user exclusions. Test the ordinary path for a long-lived account using controlled fixtures. |
| P2 | Tighten release inputs and browser response headers | Keep local/demo-only auth inputs out of release builds. Expose the intended cooldown header to approved web origins. |

## AI and recommendations

| Priority | Work item | Acceptance criteria |
| --- | --- | --- |
| P1 | Add a shared paid-call budget | Keep per-account limits and add an app-wide daily budget and bounded concurrency. Use a provider-side cap if supported. The manual form remains usable when the AI route cannot run. |
| P2 | Honor rejected destinations | The discovery recommendation surface applies the signed-in user's saved exclusions. The deterministic recommender still returns a helpful empty state when appropriate. |
| P2 | Label manual fields accurately | Do not imply that exact peso budget or party size was extracted. Keep those fields editable and distinguish them from suggested qualitative preferences. |
| P2 | Preserve the AI trust boundary | Separate fixed instructions from user data, enforce bounded schema-validated outputs, keep the output as an editable draft, and require explicit confirmation before saving. Reassess the boundary before adding retrieved context or tools. Offline provider stubs verify application behavior, not live-model prompt-injection resistance. |

## DevOps (P1): establish the release path before relying on it

The [Nov 26 scheduled checks](https://github.com/relax-mode/lagaw/actions/runs/45790667724) passed the staging AI job and failed the Pages deployment preflight. The [Nov 15 release](https://github.com/relax-mode/lagaw/actions/runs/43727841016) passed production web deployment and skipped production API. The failed preflight does not establish an outage or a credential-expiry cause.

1. Verify the production Pages configuration and confirm that the deployment preflight passes before depending on a new web release.
2. Record the production Pages commit and the Cloud Run revision receiving traffic independently. A web deployment alone does not establish the API version.
3. Preserve a known-good demo revision. Verify the manual trip path and budget fallback before enabling optional AI suggestions in the rehearsal.
4. Rehearse sign-in, trip creation and safe retry, itinerary editing, reopening a saved trip, and basic offline recovery with pre-verified, separate demo accounts.

**Verification limits:** No live security tests, production load tests, provider calls, or deployment changes were performed as part of the two audits. The serving revisions and live limits should be checked in the release dashboards before the panel.
