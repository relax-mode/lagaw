# S2-04 Flutter trip screens: development evidence

Issue: `relax-mode/lagaw#27`, [S2-04] Build Flutter Trip Creation and Editing Screens.
Branch: `feat/frontend-shell` (local, uncommitted at time of writing).
Recorded: 2026-10-22.

## What was verified

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 52 passed, 0 failed |
| Web (Chrome), 390×844 phone layout | Create, validate, detail and edit (saved through `PATCH`) all worked |
| Web (Chrome), 1280×860 wide layout | Header **My Trips** button and trips grid render; data survives a full page reload |
| Requests go through FastAPI | Yes: Flutter → `POST/GET /api/v1/trips` with Bearer token; CORS preflight allowed for the app origin |
| Backend 422 shape matches the client parser | `{"detail":[{"loc":["body","title"],"msg":...}]}` |
| Android | Debug APK builds; not run on a device. See [Android](#android) |

### How the live web check was run

No `.env` (Supabase credentials) exists on this machine, so PostgreSQL itself was
**not** reachable. To still exercise the real request path, the actual FastAPI app
(`app.main.create_app`: routing, Bearer auth, Pydantic validation, CORS, 422
handler) ran locally with **only** `get_trip_database` overridden by an in-memory
store. A throwaway local token and demo user id were generated for that run only.

```text
no token          GET /api/v1/trips  -> 401
with token        GET /api/v1/trips  -> 200 {"items":[],"limit":10,"offset":0}
CORS preflight    OPTIONS from http://localhost:8733 -> 200, allow-origin echoed
invalid payload   POST /api/v1/trips -> 422 {"detail":[{"loc":["body","title"],...}]}
after UI create   GET /api/v1/trips  -> 1 item:
  title "Weekend food crawl", 2026-11-14..2026-11-15, budget 1500.00–3000.00,
  jeepney, friends, ["cafe","food"], status draft
PATCH preflight   OPTIONS from the app origin -> 200, allow-methods includes PATCH
after UI edit     PATCH /api/v1/trips/{id} body sent by Flutter (changed fields only):
  {"budget_max":"3500.00","transportation_mode":"taxi","group_type":null}
after reload      GET /api/v1/trips -> budget 1500.00–3500.00, taxi, group null,
  other fields unchanged
```

The update check ran after `main` gained `PATCH`/`DELETE` (relax-mode/lagaw#41),
with the in-memory store extended to implement `update_trip`/`delete_trip` the
same way: apply only the supplied fields.

The web build used
`--dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=TRIP_DEMO_TOKEN=<local token>`.

## Screenshots (`docs/evidence/s2-04/`)

| File | Shows |
| --- | --- |
| `01-home-mobile.jpg` | Home with the new **Plan a Trip** button and the three-pill dock (Home, Spots, Trips) |
| `02-trips-empty.jpg` | My Trips empty state, loaded from the live API |
| `03-create-validation.jpg` | Empty submit: inline errors on name, dates and both budgets |
| `04-create-filled.jpg` | Filled form with date range, ₱ budgets and selected chips |
| `05-created-detail.jpg` | After `POST`: detail page with the "Trip saved!" banner |
| `06-edit-saved.jpg` | After `PATCH`: detail page shows "Changes saved.", ₱3,500, Taxi / Grab, group cleared |
| `07-trips-list-web-after-reload.jpg` | Wide layout after a full page reload; the saved trip is still listed |
| `08-edited-trip-after-reload.jpg` | Phone layout after a full page reload; the edited values are still shown |

## Acceptance criteria status

| Criterion | Status |
| --- | --- |
| Users can create a trip through Flutter | Done: verified on web against FastAPI |
| Created trips persist in PostgreSQL | **Not verified here**: no database credentials on this machine. The client sends the exact `TripCreate` contract; repeat against the dev Supabase project |
| Existing trips can be edited | Done: edit form sends changed fields through `PATCH`; 404/409/422 handled |
| Updated values persist after refreshing | Done against FastAPI (in-memory store); repeat against the dev Supabase project for PostgreSQL |
| Invalid inputs are rejected with clear feedback | Done: client checks mirror backend rules, and backend 422s show on the matching field |
| All requests go through FastAPI | Done: `TripService` only calls `/api/v1/trips` |
| Android and Web functionality works | Web: done. Android: see below |

## Android

No Android emulator or device is configured on this machine (`flutter emulators`
lists none), so the app was **not run on Android**. `flutter build apk --debug`
**succeeded** (`build/app/outputs/flutter-apk/app-debug.apk`), so the code compiles
for Android. The code uses no web-only APIs. When testing
on an emulator, use `--dart-define=API_BASE_URL=http://10.0.2.2:8000`.

## Notes for reviewers

- `TRIP_DEMO_TOKEN` is compiled into the client through `--dart-define`. Anyone
  can read it in a web build, so use it only for local development until the team
  agrees on a client-safe approach (see the open decision in the milestones doc).
- `TripService.updateTrip` sends `PATCH` with only the fields that changed
  (`TripDraft.changedFieldsFrom`). Cleared transport or group goes out as `null`,
  cleared tags as `[]`, matching `docs/trip-mutations-api.md`. A 409 conflict
  shows a **Reload** action that refreshes the form from the server.
- `DELETE` exists on the backend but is out of scope for S2-04 (it belongs to
  S2-05 #28), so the app does not call it yet.
- Some home-screen rows (hero and category pills) already overflowed by a few
  pixels in widget tests at phone widths before this work. That wasn't changed
  here, and the layout tests drain only those known errors.
