# Lagaw panel readiness: combined audit and release checklist

**Baseline:** `f4076c61c81885ef94cb55051634a43189bb6bc2` on `main`.
**Reviews:**
- November 26: source reviews by GPT-6.2 Astra High and Antigravity Gemini 4 Neon Extra High, through Agent Hub.
- November 27: a live break-it test of staging. It included API probes with two throwaway confirmed accounts, live DeepSeek calls, a headless-browser walkthrough of the deployed web app, and load bursts up to 150 concurrent requests. A third static backend review ran through Agent Hub alongside it.

**Scope:** Flutter, API and storage, AI and recommendations, and release readiness. This is not a certification of the deployed app. Production was only checked read-only and unauthenticated. This public document records hardening goals and acceptance criteria. Reproduction details, prepared changes and per-owner instructions are in a restricted handoff, not in this file, until fixes ship.

**P1** means fix or verify before the panel. **P2** is follow-up unless it affects the chosen demo flow.

**Status values (November 27):**
- **Prepared:** a change exists in the restricted handoff and passed CI on a closed branch. The owner applies it and opens the PR.
- **Confirmed:** reproduced live.
- **Verified:** works as intended live.
- **Open:** not addressed.
- **Not live-tested:** not exercised on November 27.

## Frontend (FE)

| Priority | Work item | Acceptance criteria | Status (Nov 27) |
| --- | --- | --- | --- |
| P1 | Isolate account state across navigation and asynchronous requests | Reset protected navigation and account-scoped state when identity changes. Discard stale responses and never retry a write under a different identity. Recovery for the same account may retain an unsaved draft. | Not live-tested |
| P1 | Recover from uncertain trip saves | Restore interactive state after a timeout or unexpected response. Offer a clear recovery path through My Trips. Preserve the submission ID if the user retries. | Open. Offline itinerary generation already shows a clear recovery message (verified). |
| P1 | Tolerate an idle API's cold start | The first screen after the API has been idle loads without a "could not reach the server" error. Client timeouts allow for an instance start plus token verification. | Confirmed. The instance start took longer than the client's request timeout. Prepared. |
| P1 | Explain quota cooldowns | Distinguish temporary provider errors from an account cooldown. Show a retry time when available and keep manual entry accessible. Never show a raw HTTP status. | Confirmed. The account cooldown showed a raw HTTP status. Prepared: a try-later message. A retry time also needs the backend header item below. |
| P2 | Make destination browsing incremental | Load additional results on demand, keep scrolling responsive, and ignore or cancel outstanding results when the view closes. | Open |
| P2 | Fit extreme but valid values | The largest budget the form accepts stays on one line in trip summaries. | Confirmed. Prepared. |
| P2 | Handle in-app URL changes | Changing the address bar while the app is open goes to a valid screen without runtime errors. A fresh deep link already loads normally. | Confirmed (console error only; no visible effect). Open. |

Verified on staging:
- Sign-in errors, onboarding and trip form validation, and AI suggestions (empty input, double-submit, unsupported preferences).
- Itinerary generation, confirmation before replacing a plan, and a stale-plan conflict.
- Offline recovery and recovery from a corrupted session.
- Hostile titles and search text, which render as text.

## Backend (BE)

| Priority | Work item | Acceptance criteria | Status (Nov 27) |
| --- | --- | --- | --- |
| P1 | Verify production request controls | Confirm route-level rate, request-size, timeout, and concurrency settings at the API ingress. Bound database-backed public reads and distinguish platform instance caps from per-request controls. | Load: no errors at 150 concurrent requests, but latency rose to about 10 s (instance cap 2). Prepared: request-body size limit and pagination bounds. Route-level rate limiting is still open. |
| P1 | Return client errors, never server errors, for malformed input | Malformed identity tokens, unstorable text, out-of-range pagination, implausible trip dates and over-precise ratings get 4xx responses with readable messages, before any paid or database work. | Confirmed (several 5xx cases, some reachable without an account). Prepared, with regression tests. |
| P1 | Make first sign-in safe under concurrent requests | A new account's simultaneous first requests resolve to one profile without a false "profile needs review" response. | Confirmed (also an intermittent CI test failure). Prepared. |
| P1 | Make writes safe to retry | Use owner-scoped action IDs. Repeating the same action returns the original outcome; unrelated actions remain independent. Apply to trip creation and interaction events. | Open. The UI already blocks double-submit (verified). |
| P1 | Enforce trip and itinerary consistency | Date changes and itinerary updates maintain a consistent trip window. Reject conflicting changes clearly or require explicit adjustment. Recompute or invalidate derived costs when inputs change. | Confirmed: shortening a trip keeps stops outside the new dates. Open. |
| P2 | Bound recommendation work | Cache appropriate catalog data, bound history processing by design, and retain meaningful user exclusions. Test the ordinary path for a long-lived account using controlled fixtures. | Open |
| P2 | Tighten release inputs and browser response headers | Keep local/demo-only auth inputs out of release builds. Expose the intended cooldown header to approved web origins. | Open |

Verified on staging:
- Cross-account access was refused on every trip, item, recommendation, generation and interaction route.
- Concurrent itinerary generation and replacement left one consistent plan.
- Stale replacements were refused.

## AI and recommendations

| Priority | Work item | Acceptance criteria | Status (Nov 27) |
| --- | --- | --- | --- |
| P1 | Add a shared paid-call budget | Keep per-account limits and add an app-wide daily budget and bounded concurrency. Use a provider-side cap if supported. The manual form remains usable when the AI route cannot run. | Open. The per-account limit held atomically under concurrent requests (verified). The provider balance is currently the only app-wide cap. |
| P2 | Honor rejected destinations | The discovery recommendation surface applies the signed-in user's saved exclusions. The deterministic recommender still returns a helpful empty state when appropriate. | Not live-tested |
| P2 | Label manual fields accurately | Do not imply that exact peso budget or party size was extracted. Keep those fields editable and distinguish them from suggested qualitative preferences. | Open |
| P2 | Preserve the AI trust boundary | Separate fixed instructions from user data, enforce bounded schema-validated outputs, keep the output as an editable draft, and require explicit confirmation before saving. Reassess the boundary before adding retrieved context or tools. | Verified against live direct injection attempts: outputs stayed schema-valid and nothing leaked. Some instructions make the model return unusable output, and the UI then shows a "could not understand" fallback. Indirect injection is not applicable today, because no stored text enters the prompt. |

## DevOps (P1): establish the release path before relying on it

The [Nov 26 scheduled checks](https://github.com/relax-mode/lagaw/actions/runs/45790667724) passed the staging AI job and failed the Pages deployment preflight. The [Nov 15 release](https://github.com/relax-mode/lagaw/actions/runs/43727841016) passed production web deployment and skipped production API. The failed preflight does not establish an outage or a credential-expiry cause.

1. Verify the production Pages configuration and confirm that the deployment preflight passes before depending on a new web release.
2. Record the production Pages commit and the Cloud Run revision receiving traffic independently. A web deployment alone does not establish the API version.
   - **Nov 27 finding:** staging API traffic had stayed pinned to a November 3 revision since a manual QA deploy that day, and the November 5 rollback drill's exact restore kept the pin ([INC-5](incident-log.md#inc-5-staging-api-traffic-pinned-to-an-old-revision)). Later staging deploys received no traffic, while their smoke tests still passed. Traffic was returned to the latest revision on November 27. Production was already serving its latest revision.
   - **Prepared:** a deploy step that routes traffic to the new revision and fails unless it serves 100%.
3. Preserve a known-good demo revision. Verify the manual trip path and budget fallback before enabling optional AI suggestions in the rehearsal.
4. Rehearse sign-in, trip creation and safe retry, itinerary editing, reopening a saved trip, and basic offline recovery with pre-verified, separate demo accounts.
5. Decide the idle-instance policy for panel day. With scale-to-zero, the first request after idle waits for an instance start. A minimum of one warm production instance is prepared as a separate, optional change.
6. Confirm hosted sign-up email limits. The built-in mailer allows only a few confirmation emails per hour per project, and this was not re-checked on November 27 because the management token was rejected.

**Verification limits:**
- The November 26 reviews were source-only.
- The November 27 tests ran against staging, with read-only, unauthenticated checks on production. No production writes or production load tests were performed.
- The only deployment change was the staging traffic routing above.
- The prepared changes were not deployed when this audit was written.

## Status update (November 27, later the same day)

The status column above records the audit itself. Since then, owners have merged and deployed their fixes:

- **Backend:** [#202](https://github.com/relax-mode/lagaw/issues/202) via [PR #205](https://github.com/relax-mode/lagaw/pull/205), deployed to production (`lagaw-api-00041-465`). It covers the trip and itinerary consistency checks, the malformed-input and authentication changes reused from the prepared handoff, and the aggregate extraction budget. See #202 for the acceptance record.
- **Frontend:** [#203](https://github.com/relax-mode/lagaw/issues/203) via [PR #210](https://github.com/relax-mode/lagaw/pull/210), deployed to production web. It covers the idle cold start, readable quota cooldowns, account switching and uncertain trip saves.
- **DevOps:** the Pages preflight passed after the token rotation ([run 45989252146](https://github.com/relax-mode/lagaw/actions/runs/45989252146), [INC-6](incident-log.md#inc-6-cloudflare-pages-token-rejected-again)). Routing traffic to the latest revision after every deploy, and the warm-instance policy, remain open in [#204](https://github.com/relax-mode/lagaw/issues/204).

Items not named in those issues, such as incremental destination browsing, retry-safe writes and recommendation work bounds, remain open after the panel.
