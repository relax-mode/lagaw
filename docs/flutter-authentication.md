# Flutter Supabase sign-in — #80

Flutter side of the [backend authentication contract](authentication.md) (#79).
Users sign up and sign in with email/password through Supabase Auth. Every
protected FastAPI call then sends that user's access token. Application data
still goes only through FastAPI; Flutter never reads application tables.

## Configuration

Only **public** values are compiled into the app:

| `--dart-define` | Staging / development | Production |
| --- | --- | --- |
| `SUPABASE_URL` | `https://vnpkyvtbupnquvirzlzp.supabase.co` | `https://zjnuqqtbapbpudsjbpif.supabase.co` |
| `SUPABASE_ANON_KEY` | That project's publishable/anon key | That project's publishable/anon key |
| `API_BASE_URL` | Staging API | Production API |

At startup the app refuses a `sb_secret_…` key or a JWT whose role is not
`anon`, so a service-role key can never back the client. CI builds both web
bundles with the URL above and the environment's existing public
`SMOKE_SUPABASE_KEY` variable, and fails the build if it is missing.

Local Android run against staging (public values only):

```bash
flutter run -d <device> --dart-define=API_BASE_URL=https://lagaw-api-staging-i5kvldluga-as.a.run.app --dart-define=SUPABASE_URL=https://vnpkyvtbupnquvirzlzp.supabase.co --dart-define=SUPABASE_ANON_KEY=<staging publishable key>
```

Without `SUPABASE_URL`/`SUPABASE_ANON_KEY` the app runs in the old local demo
mode (compiled `TRIP_DEMO_TOKEN`). That only works against a backend explicitly
started with `TRIP_AUTH_MODE=demo`. With Supabase configured, the demo token is
never sent, including as a fallback.

## Behavior

- **Sign-up:** email, password (at least 8 characters) and confirmation. When the
  project requires email confirmation, the app explains that a link was sent and
  makes no protected call until the user signs in. On Web the link returns to the
  page's origin.
- **Sign-in:** validation first; then Supabase errors are shown as readable
  messages (wrong password, unconfirmed email, existing account, rate limits,
  service outage, offline). The form keeps its values for another try.
- **Session restore:** `supabase_flutter` persists the session (Android storage,
  browser storage on Web) and refreshes it automatically. A token expiring within
  30 seconds is refreshed before a request.
- **API authorization:** `TripService` (trips, itinerary items) and
  `PreferenceService` (extraction) send `Authorization: Bearer <access token>`.
  The refresh token is never sent to FastAPI. Public `/locations` stays
  unauthenticated.
- **401:** one SDK refresh (shared by concurrent requests), then one retry, which
  is safe because a 401 means the operation never ran. If refresh fails, the
  session is marked expired. No loops and no demo-token fallback.
- **Expiry without data loss:** an expired session does not leave the current
  screen. A banner offers **Sign in**, which opens sign-in on top; afterwards the
  user is back where they were with unsaved form values intact and can retry
  Save. Signing in as a *different* account rebuilds the app so no data carries
  across accounts.
- **Backend outcomes:** 403 `email_confirmation_required` and 409
  `profile_link_required` show their own messages. Other 409s keep their trip
  meaning. A 503 keeps the session and offers retry.
- **Sign-out:** tap the avatar in the header and choose **Sign out**.

## Tests

`frontend/test/auth_test.dart` runs without network or credentials, using a fake
Auth client. It covers the key guard, refresh-before-expiry, a single shared
refresh, expiry versus explicit sign-out, bearer tokens on trip and extraction
calls, 401 refresh-and-retry, failed refresh with no loop, no request without a
session, 403/409 auth codes, and the sign-in, sign-up (with and without
confirmation), restore, sign-out and expiry-with-unsaved-input flows.

## Remaining limitations and coordination

- **Kyle:** confirm Auth settings per project: email confirmation on, Web
  redirect allowlist containing `https://staging.lagaw.pages.dev` and
  `https://lagaw.pages.dev`, token lifetime, and rate limits.
- **Android confirmation links:** no app deep link is configured, so the email
  link opens the project's Site URL in a browser. After confirming, the user
  returns to the app and signs in. Deep links are a follow-up.
- **Demo token:** CI still compiles the old `TRIP_DEMO_TOKEN` into web builds,
  but a Supabase-configured build never sends it. Removing it from the workflow
  and its secrets is a follow-up with Kyle.
- **Interactions (#52) and #56 screens** are not in Flutter yet; when added they
  should reuse `ApiCredentials` the same way.
- **Two-user isolation** is enforced by the backend (#79) and must be verified
  end to end on Android and Web with two safe test accounts. See
  [evidence](evidence/flutter-authentication.md).
