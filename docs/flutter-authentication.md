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
| `AUTH_REDIRECT_URL` (optional) | Defaults to `https://staging.lagaw.pages.dev` | Defaults to `https://lagaw.pages.dev` |

At startup the app refuses a `sb_secret_…` key or a JWT whose role is not
`anon`, so a service-role key can never back the client. CI builds both web
bundles with the URL above and the environment's existing public
`SMOKE_SUPABASE_KEY` variable, and fails the build if it is missing.

Confirmation emails return to the Web page's own origin. Android has no deep
link, so its links go to the same project's deployed web app (known project URLs
above), or to `AUTH_REDIRECT_URL` when set. Supabase only honors a redirect on the
project's allow-list and otherwise uses its Site URL; see
[Hosted Auth settings](#hosted-auth-settings).

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
  makes no protected call until the user signs in. Signing up again with an
  already confirmed email says to sign in instead, rather than "Account created".
- **Sign-in:** validation first; then Supabase errors are shown as readable
  messages (wrong password, unconfirmed email, existing account, rate limits,
  service outage, offline). The form keeps its values for another try.
- **Rate limits:** Supabase's email limit is told apart from request limits. A
  per-address cooldown names the seconds left; the project's hourly email cap
  tells people who already signed up to check their inbox and sign in. After any
  limit the submit button counts down ("Try again in 42s") instead of sending
  more requests. Switching to sign-in clears a sign-up cooldown.
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

- **Hosted Auth settings** (below) must be applied in each Supabase project; the
  app cannot fix localhost links or the email cap by itself.
- **Android confirmation links:** no app deep link is configured, so the email
  link opens the deployed web app in a browser. After confirming, the user
  returns to the app and signs in. Deep links are a follow-up.
- **Demo token:** CI still compiles the old `TRIP_DEMO_TOKEN` into web builds,
  but a Supabase-configured build never sends it. Removing it from the workflow
  and its secrets is a follow-up with Kyle.
- **Interactions (#52) and #56 screens** are not in Flutter yet; when added they
  should reuse `ApiCredentials` the same way.
- **Two-user isolation** is enforced by the backend (#79) and must be verified
  end to end on Android and Web with two safe test accounts. See
  [evidence](evidence/flutter-authentication.md).

## Hosted Auth settings

Set in the Supabase dashboard of each project (**Authentication**). These are not
in `supabase/config.toml`, which only configures a local `supabase start` stack.

Status (October 29, 2026): Site URL and Redirect URLs are applied and verified in
both projects. Custom SMTP and the higher email limit are still pending; Supabase
refuses to change the limit until SMTP is configured.

| Setting | Development `vnpkyvtbupnquvirzlzp` | Production `zjnuqqtbapbpudsjbpif` |
| --- | --- | --- |
| URL Configuration → Site URL | `https://staging.lagaw.pages.dev` | `https://lagaw.pages.dev` |
| URL Configuration → Redirect URLs | `https://staging.lagaw.pages.dev`, `https://staging.lagaw.pages.dev/**`, `https://*.lagaw.pages.dev` | `https://lagaw.pages.dev`, `https://lagaw.pages.dev/**` |
| Emails → SMTP Settings | Custom SMTP on | Custom SMTP on |
| Rate Limits → emails sent per hour | 30 or more (only editable with custom SMTP) | 30 or more |

- **Localhost links:** a new project's Site URL is `http://localhost:3000`, and
  Supabase uses it whenever the requested redirect is missing or not
  allow-listed. Setting both rows above fixes the links for Web and Android.
- **"Too many attempts" on sign-up:** without custom SMTP, Supabase's built-in
  mailer sends only 2 auth emails per rolling hour per project, shared by every
  user, and each sign-up (or repeated sign-up of an unconfirmed address) sends
  one. A rejected sign-up creates no account, so even a first attempt fails once
  two other people have signed up in the past hour. Measured on development on
  October 29: confirmation emails at 03:16:34 and 03:21:57 UTC (two teammates)
  blocked every later sign-up until 04:16:37, three seconds after the first left
  the hour window. The built-in mailer also delivers only to the organization's team
  members. The app now explains the limit and stops resending, but only custom
  SMTP (for example Brevo or Resend) with a higher hourly limit removes it. Keep the SMTP
  password in the dashboard only; never commit it.
- Keep email confirmation on and anonymous sign-in off (see the
  [#79 contract](authentication.md)).
