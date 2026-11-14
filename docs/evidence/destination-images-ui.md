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

## Pending

- [ ] **Upload the approved photos** with the #108 script (the Storage service key is held by the #108 owner, aranxshx), and clear staging's mislinked cathedral `image_url` first.
- [ ] Deployed screenshots of a licensed photo with its credit and the credit sheet, plus the fallback, once uploaded.
- [ ] PR review and CI. After updating from `main` (with #173 and #174 merged), `flutter test` passes 239 and `pytest -m "not db"` passes 1108.
