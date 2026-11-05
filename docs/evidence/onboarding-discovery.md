# #104 Onboarding connected to personalized discovery: verification evidence

Issue: [relax-mode/lagaw#104](https://github.com/relax-mode/lagaw/issues/104).
Branch: `feat/s4-04-onboarding-discovery`. Contracts:
[onboarding preferences (#102)](../onboarding-preferences-api.md),
[cold-start recommendations (#103)](../onboarding-recommendations-api.md).
Builds on the #101 screens ([evidence](onboarding-ui.md)).

## What was built

- **Real preferences.** In signed-in builds, the #101 mock is replaced by `DiscoveryService`:
  - it loads with `GET /api/v1/me/preferences` and saves the full four-key body with `PUT`;
  - it uses the Supabase bearer token, with one refresh and retry after a 401 (the request was rejected before running).
  - Other failures are never retried automatically. A save whose outcome is unknown says so, and notes that saving again is safe because PUT is idempotent.
  - 422 errors name the rejected fields. 403, 404, profile-link 409 and 503 each get their own message.
- **First-run routing.**
  - After sign-in, `FirstRunGate` checks the account once per app run.
  - With **no saved preferences** (no tags, budget or style), onboarding opens with a **Skip for now** option.
  - Returning users are not interrupted.
  - If the check fails (offline or 503), the app opens normally, and **Travel preferences** in the account sheet still works.
- **Picked for you.** After saving, **See places for me** opens recommendations from `POST /api/v1/me/recommendations`.
  - **Who's coming** and **Max you'd spend per place, per person** are both required by the API. They are **asked, with nothing preselected**: the #103 contract says the profile budget has no per-visit meaning, and a silent default would hide places without saying why.
  - Quick limits: Free only (₱0), ₱200, ₱500, ₱1,000, or Custom (validated: up to 2 decimals, non-negative).
  - Each card shows the location, the backend match %, its reason and the real price; unknown values stay unknown.
  - States:
    - loading ("Finding places…");
    - empty ("No places match yet…");
    - 409 preferences changed (**Reload**);
    - 503 and network errors (**Try again**; earlier results stay visible);
    - 422 (adjust the inputs).
  - Nothing is saved from this screen. Swipes, saves and ratings belong to #110.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 205 passed, 0 failed (17 new in `test/discovery_test.dart`) |

The new tests cover:
- request method, path, token and body for GET, PUT and POST;
- a new account reading as unset;
- 422 field names;
- no retry after an unconfirmed save;
- 409 "preferences changed" versus the profile-link 409;
- the 503 message;
- the screen refusing to search until both answers are chosen;
- custom-limit validation;
- the empty state;
- 409 → Reload;
- 503 keeping earlier results;
- first-run routing (onboarding with skip; returning user not interrupted; a failed check opens the app; checked once per run);
- onboarding Save → See places for me → picked for you.

## Android (POCO Pad, staging API, 2026-11-05)

Debug build against `lagaw-api-staging` with real Supabase accounts.
Screenshots: [`img/onboarding-discovery-android/`](img/onboarding-discovery-android/).

| Shot | Check | Result |
| --- | --- | --- |
| [104_1](img/onboarding-discovery-android/104_1.jpg) | Signed-in account with no saved preferences: onboarding opened by itself, with **Skip for now** | Pass |
| [104_2](img/onboarding-discovery-android/104_2.jpg) | Skip for now → home, nothing blocked | Pass |
| [104_3](img/onboarding-discovery-android/104_3.jpg) | Travel preferences: Café, Food, Heritage · no budget · Moderate on Review | Pass |
| [104_4](img/onboarding-discovery-android/104_4.jpg) | Saved to staging: "You're all set!" with **See places for me** | Pass |
| [104_5](img/onboarding-discovery-android/104_5.jpg) | Picked for you with both questions unselected | Pass |
| [104_6](img/onboarding-discovery-android/104_6.jpg) | Show my places disabled with nothing chosen | Pass |
| [104_7](img/onboarding-discovery-android/104_7.jpg) | Couple + ₱500: "Finding places…" | Pass |
| [104_8](img/onboarding-discovery-android/104_8.jpg) | Ranked result from staging: The Negros Museum, 43%, backend reason, ₱70 – ₱100 | Pass |
| [104_9](img/onboarding-discovery-android/104_9.jpg) | Free only: "No places match yet…" (the museum charges admission) | Pass |
| [104_10](img/onboarding-discovery-android/104_10.jpg) | Custom 1.234: "Use a peso amount with up to 2 decimals.", no request sent | Pass |
| [104_12](img/onboarding-discovery-android/104_12.jpg) | Closed and reopened: onboarding did **not** open again | Pass |
| [104_13](img/onboarding-discovery-android/104_13.jpg) | Travel preferences reloads the saved answers from the server | Pass |
| [104_14](img/onboarding-discovery-android/104_14.jpg) | Brand-new account after sign-up: onboarding opened automatically | Pass |
| [104_15](img/onboarding-discovery-android/104_15.jpg) | New account (no history), Solo + ₱1,000: cold-start recommendation returned | Pass |

**Notes**
- 104_11 was meant to show the airplane-mode error, but it captured the same custom-limit state as 104_10. The offline and 503 behaviour (error with **Try again**, earlier results kept) is covered by widget tests, not by a device screenshot.
- Staging returns one place for these answers. Per `docs/location-data-sources.md`, only the Negros Museum has verified prices; places with unknown prices are excluded by the API rather than shown with invented prices.

## Pending

- [x] Android deployed journey on staging (above).
- [ ] Web after merge.
- [ ] PR review and CI.
