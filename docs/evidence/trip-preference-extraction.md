# #55 Flutter preference extraction: verification evidence

Issue: [relax-mode/lagaw#55](https://github.com/relax-mode/lagaw/issues/55), natural-language
preference extraction in the Flutter trip form.
Branch: `feat/trip-preference-extraction`. Depends on #27 (Trip CRUD UI) and #50
(extraction API, [contract](../preference-extraction-api.md)).
Recorded: 2026-10-29.

## What was built

- **Describe your trip** box at the top of the shared create/edit form
  (`widgets/trip_form/describe_trip_card.dart`). It sends only the trimmed prompt to
  `POST /api/v1/preferences/extract` through `PreferenceService`, with the existing demo
  bearer token. The app holds no provider key and never calls DeepSeek or the database.
- **Review sheet** (`widgets/trip_form/preference_review_sheet.dart`): suggested vibes not
  already on the trip appear as checkboxes. Vibes already chosen are listed as kept.
  Budget level, time of day and pace appear for reference only, numeric budgets are never
  inferred, and unmentioned fields are listed.
- **Apply to form** only adds the ticked vibes; nothing the user entered is removed or
  changed. **Cancel** changes nothing. Nothing is saved until the normal Save, which uses
  the existing `POST /api/v1/trips` or changed-fields-only `PATCH`. Review-only fields
  (`budget_level`, `duration`, `pace`, `budget_scope`) are never sent to Trip CRUD.
- **Why only the prompt is sent:** the API lets explicit values override extraction, so
  sending the current tags would echo them back and hide every suggestion. Merging on the
  client, with per-vibe confirmation, keeps the user's existing values authoritative.
- **Failures:** each backend code (`extraction_timeout`, `extraction_unavailable`,
  `invalid_extraction_output`, `extraction_failed`, `extraction_rate_limited`,
  `invalid_request`), the inherited 401/503 string details, a malformed 200 body, a 40 s
  client timeout and network errors each show a readable message that points to manual
  entry. Form values stay intact. There are no automatic retries; the button is disabled
  while a request is pending.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 104 passed, 0 failed (24 new) |

`test/preference_service_test.dart` covers the request shape (prompt only, bearer token,
endpoint), success and partial/unspecified parsing, every error code, inherited string
details, a malformed 200 body, client timeout and offline errors, and refusing to call
without a token.

`test/preference_extraction_test.dart` uses a mocked extraction service. It covers:
- success, then review, then applying only the ticked vibes, then saving with every
  explicit field unchanged;
- extraction never saving by itself;
- cancel leaving the form unchanged;
- a partial result with no vibes;
- timeout, unavailable, invalid-output and network failures keeping the form and allowing
  a manual save;
- retry after a failure;
- a blank prompt making no call;
- duplicate-submit prevention;
- new-trip validation still applying after an apply.

## Android, against the deployed staging API

Device: POCO Pad (model 2405CPCFBG), debug APK, USB install.
Build: `--dart-define=API_BASE_URL=https://lagaw-api-staging-i5kvldluga-as.a.run.app`
plus the staging Trip demo token from the git-ignored `.env` (`STAGING_TRIP_DEMO_TOKEN`).
The token value is not recorded. Staging writes go to the development Supabase project
only. Extraction was performed by the deployed staging backend; the suggestions shown are
its actual output.

| # | Step | Result | Screenshot |
| --- | --- | --- | --- |
| 1 | New trip form shows the Describe box; prompt "A slow, relaxing afternoon with coffee and photography" | Pass | [55_1](img/trip-preference-extraction-android/55_1.jpg) |
| 2 | Suggest shows "Reading your description…"; the button is disabled and the field locked | Pass | [55_2](img/trip-preference-extraction-android/55_2.jpg) |
| 3 | Review sheet from staging: Café, Photography, Relaxing; for reference, budget feel Not mentioned, time of day Afternoon, pace Slow; "Not mentioned: Budget, Group Type" | Pass | [55_3](img/trip-preference-extraction-android/55_3.jpg) |
| 4 | Cancel: no vibes selected and the form unchanged | Pass | [55_4](img/trip-preference-extraction-android/55_4.jpg) |
| 5 | Suggest again, untick Relaxing, Apply: "Added 2 vibes", with only Café and Photography selected | Pass | [55_5](img/trip-preference-extraction-android/55_5.jpg) |
| 6 | Created "Extraction verification" (Nov 17–18, ₱500–₱2,000) with Café and Photography; same after fully closing and reopening the app | Pass | [55_6](img/trip-preference-extraction-android/55_6.jpg), [55_6b](img/trip-preference-extraction-android/55_6b.jpg) |
| 7 | Edit, prompt "Heritage walk and local food", Apply: Food and Heritage added, Café and Photography kept; saved as four vibes (see 55_8b) | Pass | [55_7](img/trip-preference-extraction-android/55_7.jpg) |
| 8 | Edit with an unsaved title change, airplane mode, Suggest: "Could not reach the Lagaw server… fill in the form yourself", with the edited title and vibes still there. Back online, a manual Save persisted the new title and all four vibes | Pass | [55_8](img/trip-preference-extraction-android/55_8.jpg), [55_8b](img/trip-preference-extraction-android/55_8b.jpg) |
| 9 | Blank prompt: "Describe your trip first." with no request sent | Pass | [55_9](img/trip-preference-extraction-android/55_9.jpg) |

**Not shown on device:**
- The edit-time review sheet's "Already in your trip" line was not captured; widget tests
  cover it.
- Provider 503, 504 and 502 cannot be forced on the live staging service without changing
  its secrets, so they are verified with mocked responses only. The deployed failure path
  was exercised as a real network failure (step 8).

## Still to record

- [ ] PR link, teammate review and passing CI run.
- [ ] Web: after merge, repeat steps 1–9 on `https://staging.lagaw.pages.dev`, using a full
      page reload for step 6.
- [ ] Contract agreement comment on #55, per the extraction contract's pending sign-off.
