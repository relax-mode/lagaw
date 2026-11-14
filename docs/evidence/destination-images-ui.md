# #109 Real destination images in Flutter: verification evidence

Issue: [relax-mode/lagaw#109](https://github.com/relax-mode/lagaw/issues/109).
Branch: `feat/s4-09-destination-images`. Builds on #117 (PR #174: `DestinationPhoto`, no stock photos) and the #107 venue photos (PR #173, all 10 locations approved). Both are merged into `main`, and this branch is updated from `main`.

## What was built

- **Only licensed, correctly linked photos are shown.** The #108 upload script stores each file at `locations/<location id>/<sha256>.<ext>`. The app ships `assets/image_credits.json` (generated from the #107 manifest by `scripts/build_image_credits.py`), listing each approved file's SHA-256 and its location. A photo is displayed only when its URL's SHA-256 is approved **for that same location**.
  - Anything else shows the honest placeholder: an unknown file, a URL outside the upload layout, or a photo linked to the wrong place.
- **Credit on every photo:** a "Photo: <photographer> · <license>" chip, or a © button on small thumbnails. Tapping it opens the full attribution, any changes made (for example "Resized from 4745x3164…"), and links to the original photo and the license (`url_launcher`; http and https only).
- **Loading and failure:** the category placeholder while loading; "Photo unavailable" if loading fails; "No photo yet" when there is no approved photo.
- **Practical caching:** images are decoded near display size (`cacheWidth`) and kept in Flutter's in-memory image cache; Web also uses the browser cache. No extra caching package.
- **Upload pack:** every approved photo has an exact upload file and SHA-256 in the manifest (`upload_file`, `upload_sha256`). Commons originals were verified against the reviewed SHA-1; three were resized to at most 2048 px to fit the 5 MiB bucket, with the change recorded. Commands for the #108 owner are in [destination-image-sources.md](../destination-image-sources.md#upload-pack-for-108-added-for-109).

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 239 passed (`test/destination_images_test.dart` is new) |
| `pytest -m "not db"` | 1108 passed (2 new manifest tests) |
| `python scripts/build_image_credits.py --check` | Up to date |

The widget tests cover the issue's **valid, missing and failed** images, plus a **mislinked** image (the staging case below), the credit chip, the credit sheet with links and changes, and rejection of unknown or out-of-layout URLs. The backend tests check that every upload file exists, fits 5 MiB and matches its SHA-256, and that the Flutter asset matches the manifest.

## Device (Infinix X6850, release APK against staging, 2026-11-14)

| Shot | Check | Result |
| --- | --- | --- |
| [109_1](img/destination-images-android/109_1.jpg) | Staging links the **Negros Museum** photo to **San Sebastian Cathedral** (left over from the #108 test upload; compare [117_3](img/release-build-android/117_3.jpg)). The app now refuses it and shows the cathedral's placeholder. | Pass |

### Upload to staging (2026-11-14, Roel and Claude)

Andrew gave Roel the staging Supabase service-role key for this upload. It stays in Roel's git-ignored `.env`; its value was never printed. The production keys Andrew sent first were caught before any use, because the key itself names its project (`zjnuqqtbapbpudsjbpif`), and the script only allows staging.

1. **Dry run** of all 14 files: every path is `locations/<location id>/<sha256>.jpg`, matching the manifest.
2. **Cleared the mislinked cathedral link:** San Sebastian Cathedral's `image_url` was set back to empty, only if it still pointed at the Negros Museum test image.
3. **Uploaded** the 10 main photos with `--execute --approved-usage --link-location`, and the 4 extras without linking. For each file, the script downloaded the public copy and confirmed its SHA-256.
4. **Checked every link:** all 10 places point to their own approved file, by the same SHA-256 rule the app uses.

| Shot | Check | Result |
| --- | --- | --- |
| [109_2](img/destination-images-android/109_2.jpg) | Home carousel: real photos, with credit chips ("Photo: Rauxilian · CC BY-SA 4.0" on the cathedral) | Pass |
| [109_3](img/destination-images-android/109_3.jpg) | Spots: every card has its photo and a © credit button in the top-left corner | Pass |
| [109_4](img/destination-images-android/109_4.jpg) | Open Cafetolyo card: "Photo: Roel Jr. S. Lumauag · Permission" at the top | Pass |
| [109_5](img/destination-images-android/109_5.jpg) | Credit sheet for the cathedral: attribution, "Changes: Resized from 4745x3164 to 2048x1366…", links to the original photo and to CC BY-SA 4.0 | Pass |

**Fixed while checking (on the home-redesign branch):** on Spots cards and swipe cards, the name and color fade covered the credit chip in the bottom-left corner. Those cards now show the credit in a free top corner (`CreditCorner`): top-left on Spots, top-right on swipe. The credit sheet was also narrow, because Material 3 sheets shrink to their content; it is now full width with a drag handle and opens above any pop-up.

**Fallback:** all 10 staging places now have approved photos, so "No photo yet" and "Photo unavailable" can't appear on staging. They are covered by `test/destination_images_test.dart` (missing, failed and mislinked images), and [109_1](img/destination-images-android/109_1.jpg) shows the placeholder from before the upload.

## Pending

- [x] **Upload the approved photos** to staging, and clear the mislinked cathedral `image_url` first (done 2026-11-14, see above).
- [x] Deployed screenshots of licensed photos with credits and the credit sheet (above). The fallback is covered by tests and 109_1.
- [x] PR review and CI (PR #175, merged).
- [ ] Production upload, when the team releases to production. The same script and files apply; it needs a production-approved run by the key holder.
