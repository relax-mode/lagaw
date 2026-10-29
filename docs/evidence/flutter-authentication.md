# #80 Flutter Supabase sign-in: verification evidence

Issue: [relax-mode/lagaw#80](https://github.com/relax-mode/lagaw/issues/80).
Branch: `feat/flutter-supabase-auth`. Contract: [authentication.md](../authentication.md)
(#79). Design and configuration: [flutter-authentication.md](../flutter-authentication.md).
Recorded: 2026-10-29.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 125 passed, 0 failed (21 new in `test/auth_test.dart`) |
| `flutter build apk --debug` / `flutter build web --release` | Both build |

All new tests use a fake Auth client and mocked HTTP. No real accounts, tokens or
hosted data were used.

## Android, against deployed staging

Device: POCO Pad (model 2405CPCFBG), debug APK. Build used
`API_BASE_URL=https://lagaw-api-staging-i5kvldluga-as.a.run.app`,
`SUPABASE_URL=https://vnpkyvtbupnquvirzlzp.supabase.co` and the development
project's **publishable** key from the git-ignored `.env`
(`STAGING_SUPABASE_ANON_KEY`), checked by type only. The project's public Auth
settings were confirmed: sign-up on, email provider on, email confirmation
required, anonymous sign-in off.

Two accounts were used: Roel's own address (A) and a second address (B). Accounts
were created and signed in by Roel; no passwords, tokens or confirmation links are
recorded.

| # | Check | Result | Screenshot |
| --- | --- | --- | --- |
| 1 | Sign-in screen in the app's sky/badge art style | Pass | [80_1](img/flutter-auth-android/80_1.jpg) |
| 2 | Empty submit shows field validation, with no request sent | Pass | [80_2](img/flutter-auth-android/80_2.jpg) |
| 2b | Create-account mode with confirm password; earlier errors cleared | Pass | [80_2b](img/flutter-auth-android/80_2b.jpg) |
| 3 | Sign-up for A: "Account created. Check … for a confirmation link", still on sign-in | Pass | [80_3](img/flutter-auth-android/80_3.jpg) |
| 4 | Supabase Auth confirmation email received for A | Pass | [80_4](img/flutter-auth-android/80_4.jpg) |
| 5 | After confirming, A signs in and reaches the app | Pass | [80_5](img/flutter-auth-android/80_5.jpg) |
| 6 | Wrong password: "Email or password is incorrect.", with the email kept | Pass | [80_6](img/flutter-auth-android/80_6.jpg) |
| 7 | Signed in as A: trip created, two itinerary items added, vibes saved (authenticated create, items and extraction) | Pass | [80_7](img/flutter-auth-android/80_7.jpg) |
| 8 | App fully closed and reopened: restored straight into the app, no sign-in | Pass | [80_8](img/flutter-auth-android/80_8.jpg) |
| 9 | Avatar opens "Signed in as" A, with Sign out | Pass | [80_9](img/flutter-auth-android/80_9.jpg) |
| 10 | Signed in as B: My Trips is empty, so A's trip is not visible | Pass | [80_10](img/flutter-auth-android/80_10.jpg) |
| 10A | B creates "Account B Test Trip"; B sees only it | Pass | [80_10A](img/flutter-auth-android/80_10A.jpg) |
| 11 | Back as A: only "Account A Test Trip", not B's | Pass | [80_11](img/flutter-auth-android/80_11.jpg) |

**Notes**
- The "Confirm your email first" message for signing in before confirming was not
  captured on device; `auth_test.dart` covers it.
- Session expiry was not forced on device (tokens last about an hour); the
  expiry banner and keeping unsaved input are covered by `auth_test.dart`.
- An Android confirmation link opens in the browser (no deep link). The user then
  returns to the app and signs in, as expected for this version.

## Web, against deployed staging (2026-10-29)

Chrome on macOS at `https://staging.lagaw.pages.dev`, deployed from `a507305`
([main run 40815760387](https://github.com/relax-mode/lagaw/actions/runs/40815760387)). CI built it with
the fixed development Supabase URL and the staging environment's public key.

| # | Check | Result | Screenshot |
| --- | --- | --- | --- |
| 1 | Sign-in page on Web | Pass | [w80_1](img/web-staging/w80_1.jpg) |
| 2 | Signed in as A, reaching the app | Pass | [w80_2](img/web-staging/w80_2.jpg) |
| 3 | Full page reload: still signed in (session restored from browser storage) | Pass | [w80_3](img/web-staging/w80_3.jpg) |
| 4 | Avatar: "Signed in as" A, with Sign out | Pass | [w80_4](img/web-staging/w80_4.jpg) |
| 5 | Signed out, signed in as B: Trips shows only "Account B Test Trip" | Pass | [w80_5](img/web-staging/w80_5.jpg) |
| 6 | Back as A: only "Account A Test Trip" | Pass | [w80_6](img/web-staging/w80_6.jpg) |

The same Web session also passed the #34 and #55 checks while signed in
([itinerary evidence](trip-itinerary-ui.md), [extraction evidence](trip-preference-extraction.md)).

## Links and remaining

- Implementation: [PR #96](https://github.com/relax-mode/lagaw/pull/96), reviewed by CyGray, merged as `a507305`.
- [ ] Contract confirmation from Andrew (#79) on [#80](https://github.com/relax-mode/lagaw/issues/80).
- [ ] Supabase Auth settings with Kyle: Web redirect allowlist and rate limits.

Never record passwords, access or refresh tokens, or confirmation links here.
