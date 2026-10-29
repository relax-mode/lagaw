# #34 Flutter itinerary locations: verification evidence

Issue: [relax-mode/lagaw#34](https://github.com/relax-mode/lagaw/issues/34), integrate
itinerary locations into Flutter trip details.
Branch: `feat/trip-itinerary-ui`. Depends on the manual association API (#26).
Recorded: 2026-10-28.

## What was built

- **Itinerary Locations** section on Trip Details (`widgets/itinerary_section.dart`):
  items from `GET /api/v1/trips/{id}/items`, grouped by day and ordered by visit
  order, each showing the location name, category, address, cost and duration.
  Loading, empty, and error-with-Retry states; a failed load or removal keeps the
  trip details and the current list on screen.
- **Destination picker** (`screens/destination_picker_sheet.dart`): lists real
  locations from `GET /locations` (all pages), lets the user pick a day within the
  trip's dates, and appends after that day's last stop via
  `POST /api/v1/trips/{id}/items`. The submit button is disabled while saving;
  409/422/404 responses are shown in the sheet and keep the selection.
- **Remove** on each item, with a confirmation dialog, calling
  `DELETE /api/v1/trips/{id}/items/{item_id}` and then reloading.
- `TripService.listTripItems / addTripItem / removeTripItem` reuse the existing
  bearer token, 6 s timeout and error mapping. No itinerary records are hardcoded.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 80 passed, 0 failed (19 new) |

New tests cover request shapes, pagination, nested location parsing, 404/409/422
and timeout mapping, and the screen flows: empty state, grouped list, load
error + Retry, add (with next stop number), picker errors keeping the selection,
picker location-load failure, remove cancel/confirm/failure, and that only the
opened trip's items are read or changed.

## Android, against the deployed staging API

Device: POCO Pad (model 2405CPCFBG), debug APK, USB install.
Build: `--dart-define=API_BASE_URL=https://lagaw-api-staging-i5kvldluga-as.a.run.app`
plus the staging Trip demo token from a local, git-ignored `.env`. The token is not
recorded here. Staging writes go to the development Supabase project only.

| # | Step | Result | Screenshot |
| --- | --- | --- | --- |
| 01 | New 2-day trip "Itinerary UI Verification" shows **No destinations yet** | Pass | [01](img/trip-itinerary-android/01-empty-itinerary.jpg) |
| 02 | Picker lists real Bacolod locations from PostgreSQL; Day 1 / Day 2 chips; Add disabled until a place is picked | Pass | [02a](img/trip-itinerary-android/02a-picker-day1.jpg), [02b](img/trip-itinerary-android/02b-picker-day2.jpg) |
| 03 | San Sebastian Cathedral added to Day 1 (stop 1) | Pass | [03](img/trip-itinerary-android/03-added-day1.jpg) |
| 04 | The Negros Museum added to Day 2 (stop 1); both listed by day with category, address, cost, duration | Pass | [04](img/trip-itinerary-android/04-added-day2.jpg) |
| 05 | Remove asks for confirmation; Cancel keeps the item | Pass | [05](img/trip-itinerary-android/05-remove-confirm.jpg) |
| 06 | Confirmed removal deletes only the Cathedral; Museum remains | Pass | [06](img/trip-itinerary-android/06-removed.jpg) |
| 07 | App fully closed and reopened: only the Museum (Day 2) is still shown | Pass | [07](img/trip-itinerary-android/07-after-app-restart.jpg) |
| 08 | Second trip "Itinerary Isolation Check" shows **No destinations yet** | Pass | [08](img/trip-itinerary-android/08-second-trip-empty.jpg) |
| 09 | Airplane mode: "Could not reach the Lagaw server" with Retry; back online, Retry reloads the Museum | Pass | [09a](img/trip-itinerary-android/09a-offline-error.jpg), [09b](img/trip-itinerary-android/09b-retry-recovered.jpg) |

## Web, against the deployed staging API (2026-10-29)

Web: Chrome on macOS at `https://staging.lagaw.pages.dev`, deployed from `a507305` ([main run 40815760387](https://github.com/relax-mode/lagaw/actions/runs/40815760387), after [PR #96](https://github.com/relax-mode/lagaw/pull/96)), signed in as Supabase test account A. Since #79 the deployed API accepts only signed-in Supabase sessions, so Web verification waited for #80.

| # | Step | Result | Screenshot |
| --- | --- | --- | --- |
| 01 | New 2-day trip "w34_1 Test" shows **No destinations yet** | Pass | [w34_1](img/web-staging/w34_1.jpg) |
| 02 | Picker lists real locations; Day 1 / Day 2 chips; Add disabled until a place is picked | Pass | [w34_2a](img/web-staging/w34_2a.jpg), [w34_2b](img/web-staging/w34_2b.jpg) |
| 03 | San Sebastian Cathedral added to Day 1 | Pass | [w34_3](img/web-staging/w34_3.jpg) |
| 04 | The Negros Museum added to Day 2; both grouped by day with details | Pass | [w34_4](img/web-staging/w34_4.jpg) |
| 05 | Remove asks for confirmation | Pass | [w34_5](img/web-staging/w34_5.jpg) |
| 06 | Removal deletes only the Cathedral | Pass | [w34_6](img/web-staging/w34_6.jpg) |
| 07 | Full page reload: only the Museum (Day 2) remains | Pass | [w34_7](img/web-staging/w34_7.jpg) |
| 08 | Another trip ("Account A Test Trip") shows only its own items | Pass | [w34_8](img/web-staging/w34_8.jpg) |

## Links and remaining

- Implementation: [PR #87](https://github.com/relax-mode/lagaw/pull/87), merged as `2c3a659`.
- Android and Web verified against deployed staging (above).
- [ ] Optional: SQL check in the development project (`vnpkyvtbupnquvirzlzp`) using the
      query in [trip-items-api.md](../trip-items-api.md).
