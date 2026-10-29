# #56 Flutter recommendations and generated itineraries: verification evidence

Issue: [relax-mode/lagaw#56](https://github.com/relax-mode/lagaw/issues/56).
Branch: `feat/trip-recommendations-ui`. Contracts: [ROEL_START_HERE.md](../../ROEL_START_HERE.md),
[recommendations (#53)](../trip-recommendations-api.md),
[generation (#54)](../itinerary-generation-api.md),
[interactions (#52)](../interactions-api.md), [manual items (#26)](../trip-items-api.md).

## What was built

- **Plan with AI** on Trip Details opens a planner for the saved trip:
  - Party size and total stops for the whole trip; neither is inferred from the group label.
  - Time of day and pace.
  - A check that blocks requests the API would reject: unsupported group (e.g.
    `students`), tags outside the six approved ones, a missing or unsupported
    transport mode, or a trip over 31 days. It offers **Edit trip**.
- **Recommendations** (`POST /trips/{id}/recommendations`) show actual location
  details, the backend's score and reason, and a no-matches state. Nothing is saved.
- **Interactions** (`POST /interactions`): Like (right swipe), Not for me (left swipe,
  confirmed first because it permanently excludes the place), Save, and Rate (1–5).
  - Each card is locked while its request is in flight. Like and Save are sent once.
  - A dislike or a rating refreshes the recommendations.
  - A failure shows an error and keeps the list.
- **Generate itinerary** (`POST /trips/{id}/generate-itinerary`):
  - No double submits.
  - A trip with stops gets a **"Replace this itinerary?"** confirmation. Cancel makes
    no write; Replace resends the same options with `replace_existing: true` and the
    returned revision.
  - `itinerary_changed` offers **Try again**, which gets a fresh confirmation.
  - Infeasible plans explain why and how many places were skipped.
  - 422, 503 and network errors keep the saved plan. There are no automatic retries.
- **Itinerary section** (#34) shows each generated stop's Manila-time window, travel
  minutes, cost and reason, plus the trip's estimated total. Manual stops show
  "Added by you · not scheduled". Manual add/remove is unchanged. After planning, the
  trip and items are always reloaded from the API, even after a timeout. Opening a
  screen never triggers generation.
- All calls go through `TripService` with the signed-in Supabase token (#80).

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 149 passed, 0 failed (24 new in `test/trip_plan_test.dart`) |

## Android (POCO Pad, staging API, 2026-10-29)

Debug build against `lagaw-api-staging`, signed in with Supabase accounts A and B.
Screenshots are in [`img/trip-planning-android/`](img/trip-planning-android/).

| Shot | Check | Result |
| --- | --- | --- |
| [56_2](img/trip-planning-android/56_2.jpg) | Account A trip (Café, Photography, Relaxing, Heritage, Food, Nature; Jeepney): planner and ranked recommendation with match %, reason and price | Pass |
| [56_1](img/trip-planning-android/56_1.jpg) | Like and Save sent; both buttons lock to "Liked" and "Saved" | Pass |
| [56_4](img/trip-planning-android/56_4.jpg) | Rated 4 ★ ("Rated 4"), then the "Not for you?" confirmation | Pass |
| [56_6](img/trip-planning-android/56_6.jpg) | After confirming, the disliked place is gone; the empty state explains why | Pass |
| [56_9](img/trip-planning-android/56_9.jpg) | Regenerating a trip with stops asks "Replace this itinerary?"; Cancel kept the plan | Pass |
| [56_7](img/trip-planning-android/56_7.jpg) | Cold-start account B (no interactions): generated plan with Manila time window, travel minutes, cost, reason and estimated total; manual stop shows "Added by you · not scheduled" | Pass (stale total, see below) |
| [56_17](img/trip-planning-android/56_17.jpg) | Account B after fully closing and reopening the app: plan persisted | Pass |
| [56_10](img/trip-planning-android/56_10.jpg) | Account A generate after its only candidate was disliked: clear "no destinations" error, saved plan unchanged | Pass |
| [56_12](img/trip-planning-android/56_12.jpg) | Account A manual stops after reopening the app: persisted, unscheduled | Pass |
| [56_13](img/trip-planning-android/56_13.jpg) | Manual-only trip (no Describe): recommendations returned | Pass |
| [56_14](img/trip-planning-android/56_14.jpg) | Trip with Students, Art and no transport: "Update this trip to plan with AI" with Edit trip; planning buttons disabled | Pass |
| [56_15](img/trip-planning-android/56_15.jpg) | 10 stops: "Only 1 of 10 stops fit the schedule…", saved plan unchanged | Pass |
| [56_16](img/trip-planning-android/56_16.jpg) | Airplane mode: network error, saved plan unchanged | Pass |

**Found and fixed during testing:** in 56_7 the old "Estimated total" stayed visible
after a stop was added by hand. The backend clears the trip total on any manual item
change (see 56_17 after reload), so the itinerary section now hides the total after a
manual add or remove. A widget test covers this.

**Not captured:** a successful **Replace** (the generate after confirming in 56_9
was not screenshotted), and a generated plan for the manual-only trip (56_13 shows
its recommendations only). Staging has very few venues with known hours and prices,
so most trips return one candidate.


## Pending

- [x] Android against staging (see above; gaps noted).
- [ ] PR review and CI.
- [ ] Web on `staging.lagaw.pages.dev` after merge.
