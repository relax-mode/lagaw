# #101 First-time travel preference onboarding UI: verification evidence

Issue: [relax-mode/lagaw#101](https://github.com/relax-mode/lagaw/issues/101).
Branch: `feat/s4-01-onboarding-ui`. Contract followed:
[onboarding preferences (#102)](../onboarding-preferences-api.md).

## What was built

- **Flow:** Welcome → Interests → Budget → Travel style → Review → All set. A progress bar shows "Step N of 4". Back and system back return to the previous step.
- **Interests:** only the six approved tags (`cafe`, `food`, `heritage`, `photography`, `nature`, `relaxing`). At least one is required; Next shows "Choose at least one interest." otherwise.
- **Budget:** optional PHP min and max.
  - Both must be filled or both left empty.
  - The amount must be non-negative, have at most 2 decimals, and fit `numeric(12,2)`; min must be ≤ max.
  - Amounts are stored as exact strings (`"1500.00"`).
  - **Skip** clears the budget.
- **Travel style:** optional `slow`, `moderate` or `fast`. Tapping the selected style again clears it.
- **Review:** each answer has **Edit**, which opens that step; Next or Back then returns to Review. **Save** shows a spinner and blocks double taps.
  - A failed save keeps every answer and offers **Try again**.
- **Loading:** existing answers load first with a visible loading state. A failed load offers **Retry**.
  - Saved values outside the approved vocabulary are dropped.
- **Mock data only, as the issue requires:**
  - `MockOnboardingRepository` keeps answers in memory with a short delay. Nothing is sent to the backend.
  - `--dart-define=MOCK_ONBOARDING_SAVE_FAILURE=true` makes the first save fail, to demonstrate the error state.
  - #104 replaces the mock with `GET/PUT /api/v1/me/preferences`. `OnboardingPreferences.toJson()` already produces the four-key PUT body.
- **Entry point:** **Travel preferences** in the account sheet (avatar). Sending first-time users to onboarding automatically is part of #104.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 173 passed, 0 failed (14 new in `test/onboarding_test.dart`) |

The new tests cover:
- budget parsing and range rules;
- the contract JSON shape;
- loading → full flow → saving → saved body;
- the required interest;
- that only approved tags are offered;
- invalid budgets blocking Next;
- skipping the budget and style (nulls saved);
- Edit from Review;
- Back;
- save failure and retry;
- load failure and retry;
- prefilled answers and the popped result.

## Android (POCO Pad, 2026-11-05)

Debug build with `MOCK_ONBOARDING_SAVE_FAILURE=true`, signed in to staging (mock data only; nothing sent to the API).
Screenshots: [`img/onboarding-android/`](img/onboarding-android/).

| Shot | Check | Result |
| --- | --- | --- |
| [101_1](img/onboarding-android/101_1.jpg) | Account sheet shows **Travel preferences** | Pass |
| [101_2](img/onboarding-android/101_2.jpg) | Loading state while answers load | Pass |
| [101_3](img/onboarding-android/101_3.jpg) | Welcome screen | Pass |
| [101_4](img/onboarding-android/101_4.jpg) | Next with no interest: "Choose at least one interest.", Step 1 of 4 | Pass |
| [101_5](img/onboarding-android/101_5.jpg) | Café and Heritage selected, error cleared | Pass |
| [101_6](img/onboarding-android/101_6.jpg) | Min 900 / Max 500: "Max budget must be at least the min." | Pass |
| [101_7](img/onboarding-android/101_7.jpg) | Max empty: "Enter both amounts, or leave both empty." | Pass |
| [101_8](img/onboarding-android/101_8.jpg) | Max 1.234: "Use a peso amount with up to 2 decimals." | Pass |
| [101_9](img/onboarding-android/101_9.jpg) | Slow selected, Step 3 of 4 | Pass |
| [101_10](img/onboarding-android/101_10.jpg) | Review: Café, Heritage · ₱500 – ₱2,000 · Slow, each with Edit | Pass |
| [101_11](img/onboarding-android/101_11.jpg) | Edit Interests → added Nature → back on Review | Pass |
| [101_12](img/onboarding-android/101_12.jpg) | Save shows "Saving…" with Edit and Back disabled | Pass |
| [101_13](img/onboarding-android/101_13.jpg) | Forced first-save failure: error banner, **Try again**, answers kept | Pass |
| [101_14](img/onboarding-android/101_14.jpg) | Try again → "You're all set!" | Pass |
| [101_15](img/onboarding-android/101_15.jpg) | Reopened: saved answers prefilled on Review | Pass |
| [101_16](img/onboarding-android/101_16.jpg) | Skip budget → Budget "No preference" | Pass |

## Pending

- [x] Android screenshots (above).
- [ ] Web on `staging.lagaw.pages.dev` after merge.
- [ ] PR review and CI.
