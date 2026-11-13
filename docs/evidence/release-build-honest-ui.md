# #117 Android release build and honest UI states: verification evidence

Issue: [relax-mode/lagaw#117](https://github.com/relax-mode/lagaw/issues/117).
Branch: `fix/s4-17-release-build-honest-ui`.

## Audit of `main` (2026-11-14, at `2330ede`)

| # | Finding | Verified |
| --- | --- | --- |
| 1 | `INTERNET` permission only in the debug/profile manifests, so a **release APK could not reach any server** | Yes |
| 2 | App identity `com.example.frontend`, label "frontend" | Yes |
| 3 | Release builds signed with the debug key (`TODO` in `build.gradle.kts`) | Yes |
| 4 | A release build without `API_BASE_URL` silently used `http://127.0.0.1:8000` | Yes |
| 5 | Hardcoded match scores ("92% Match", 98%, 96%…) on home and swipe cards | Yes |
| 6 | Unknown prices shown as "Free", unknown visit length as "60 mins" | Yes |
| 7 | Unsplash stock photos shown as if they were the places | Yes |
| 8 | Hardcoded weather "Bacolod City • 28° Sunny" | Yes |
| 9 | When the API failed, home silently showed a built-in sample list (fake scores, stock photos); a "Use Sample Spots" button did the same | Yes |
| 10 | "Trip Matches" actually counted likes and saves | Yes |
| 11 | No internet during token refresh → session marked **expired** and the user signed out | Yes (seen in #110 device testing) |
| 12 | Error card showed developer text ("make sure the FastAPI server is running", endpoint URL) and a developer state switcher | Yes |

## What changed

**Release build**
- `INTERNET` permission in the main manifest; label **"Lagaw"**.
- App identity **`com.lagaw.bacolod`** (`applicationId` and `namespace`; `MainActivity` moved), chosen by Roel.
- Release signing reads a private, git-ignored `android/key.properties`. Without one, it falls back to the debug key, which is labeled in the build file as test-only. The keystore belongs to the release owner (#121) and is never committed.
- `releaseConfigError`: a release build without `API_BASE_URL` and Supabase settings shows "This build of Lagaw is not configured with a server" instead of calling localhost.

**Honest data**
- `LocationItem` no longer has a match score. Real scores appear only on recommendation screens, where the backend supplies them.
- `formatCostRange`: "Free" only when the API says ₱0; otherwise a range, "Up to ₱X" or "From ₱X", and otherwise **"Price unknown"**. Decimal-string amounts are understood. `formatVisitLength`: **"Visit length unknown"** instead of a default.
- `DestinationPhoto` replaces all five `Image.network` uses. It shows the real photo, or the category colors with an icon and **"No photo yet"** ("Photo unavailable" if loading fails). No stock photos.
- The weather text is removed; "Trip Matches" is renamed **"Liked & saved"**.
- **Sample spots removed (Roel's choice, option B):** the app only ever shows live API places. The home carousel shows loading, "No places to show yet" or a connection error with **Retry**.
- User-facing error text; the developer state switcher is hidden in release builds.

**Session honesty**
- `SupabaseAuthClient.refresh` throws `AuthUnreachable` when Supabase can't be reached, and returns false only when the session is actually rejected. `AuthSession` marks the session expired only in the second case. Trips, discovery and AI-suggestion requests report **"Could not reach the Lagaw server"** instead, and the user stays signed in.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 231 passed, 0 failed |

New and changed tests:
- `test/honest_display_test.dart`: the cost and visit-length rules, decimal strings, the release config guard, and `DestinationPhoto` with no photo, a real URL, and a failed load.
- `test/auth_test.dart`: an unreachable auth server keeps the session signed in; a refresh with no connection is a network error, not expiry.
- `test/api_service_test.dart`: the old test that *required* "Free", "60 mins" and a stock image now requires "Price unknown", "Visit length unknown" and no image.

## Release APK

Built with `flutter build apk --release` against staging (debug-key fallback signing):

```
package: name='com.lagaw.bacolod' versionCode='1' versionName='1.0.0'
uses-permission: name='android.permission.INTERNET'
application-label:'Lagaw'
```

Production build command (values come from the shell, never committed):

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://lagaw-api-i5kvldluga-as.a.run.app --dart-define=SUPABASE_URL=https://zjnuqqtbapbpudsjbpif.supabase.co --dart-define=SUPABASE_ANON_KEY="$PROD_SUPABASE_ANON_KEY"
```

## Pending

- [ ] Release APK against **production**: needs the production publishable key in `.env`, and a production test account.
- [ ] Device screenshots: home, swipe card with real price and no score, "No photo yet", offline error with Retry, and offline refresh not signing out.
- [ ] A real release keystore (#121, CyGray).
- [ ] PR review and CI.
