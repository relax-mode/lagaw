# #110 Persist discovery swipes, saves and ratings: verification evidence

Issue: [relax-mode/lagaw#110](https://github.com/relax-mode/lagaw/issues/110).
Branch: `feat/s4-10-discovery-interactions`. Contract:
[interactions (#52)](../interactions-api.md). Reuses `TripService.recordInteraction` from #56,
so the trip-recommendation interactions are not duplicated.

## Before

The home swipe deck, the hearts and the "View Itinerary" count lived only in memory and reset on every launch.
- The app started with **two hardcoded, truncated "saved" IDs** that matched no real place.
- A right swipe silently counted as a save.
- The heart could un-save, although the API has no un-save.
- There was no rating.

## What changed

- **Writes** (`POST /api/v1/interactions`, one event per action):
  - swipe right → `right_swipe`;
  - swipe left → `left_swipe`;
  - heart → `save`, now separate from liking;
  - **Been here? Rate it** → `rating` (1–5), using the star dialog shared with #56.
- **Honest writes:**
  - the card only advances after the server confirms;
  - the card and its buttons are locked while a request is in flight, so double taps can't send duplicates;
  - a failure keeps the card and shows the reason;
  - **no automatic retries**, because a retry can append a duplicate event. When no response arrived, the message says the event *may* have been recorded and to reopen the app before trying again.
- **No un-save:** a saved heart stays filled. Tapping it explains that removing saved places isn't available, which matches the append-only API.
- **Left swipes are permanent exclusions**, so a one-time explainer ("Not for you?") appears before the first one on a device. Cancelling it sends nothing; after it's confirmed, left swipes go straight through. The choice is stored on the device only (`shared_preferences`).
- **Restore:** `GET /api/v1/interactions` is read across all pages on launch.
  - Already-swiped places are skipped, and the counter resumes (for example "2 / 10").
  - Hearts show real saves, the header count and "liked spots" persona use real likes and saves, and ratings show on the card.
  - A left swipe overrides other signals, matching the #52 exclusion policy.
  - Until history is known, the deck is hidden behind a loading state, or a Retry state if loading fails, so a place is never shown or recorded twice.
- The fake saved IDs are removed, and "Restart Swipe Deck" became **Browse all spots**, because swipes can't be undone.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 220 passed, 0 failed (15 new in `test/discovery_interactions_test.dart`) |

The new tests cover:
- reading every history page and skipping unknown event types;
- restoring liked, passed, saved and rated state, with a left swipe winning;
- one request per action, with the exact bodies;
- no re-save;
- the in-flight lock;
- failed writes changing nothing, with no retry and the "may still have been recorded" message;
- a failed history load;
- the deck resuming after a previous swipe;
- a like advancing only after the server responds;
- the explainer appearing once, and cancelling it sending nothing;
- a failed swipe keeping the card;
- rating;
- the history-failure Retry;
- a failed places load never swiping the offline list.

## Android (POCO Pad, staging API, 2026-11-06)

Debug build against `lagaw-api-staging`. Claude drove the Pad over adb at Roel's request, and Roel signed in to Account B himself.
Screenshots: [`img/discovery-interactions-android/`](img/discovery-interactions-android/).

| Shot | Check | Result |
| --- | --- | --- |
| [110_1](img/discovery-interactions-android/110_1.jpg) | Account A: live deck from the API at 1 / 10 (Arima Restaurant), header heart 0. The fake saved IDs are gone. | Pass |
| [110_2](img/discovery-interactions-android/110_2.jpg) | Like recorded: next card at 2 / 10, header heart 1 | Pass |
| [110_3](img/discovery-interactions-android/110_3.jpg) | First left swipe shows the one-time "Not for you?" explainer | Pass |
| [110_4](img/discovery-interactions-android/110_4.jpg) | Cancel: same card, nothing sent | Pass |
| [110_5](img/discovery-interactions-android/110_5.jpg) | "Got it, pass": next card at 3 / 10 | Pass |
| [110_6](img/discovery-interactions-android/110_6.jpg) | Second left swipe goes straight through, with no explainer (4 / 10) | Pass |
| [110_7](img/discovery-interactions-android/110_7.jpg) | Rated Capitol Park and Lagoon 4: "You rated it 4 · Rate again"; the card stays | Pass |
| [110_8](img/discovery-interactions-android/110_8.jpg) | Spots Directory: saving Negros Forest Park fills its heart, header 2. Arima, which was liked but not saved, keeps an empty heart. | Pass |
| [110_9](img/discovery-interactions-android/110_9.jpg) | Tapping a saved heart: "Already saved. Removing saved places isn't available yet." | Pass |
| [110_10](img/discovery-interactions-android/110_10.jpg) | **Force-closed and relaunched:** the deck resumes at 4 / 10, with the rating and heart count intact | Pass |
| [110_11](img/discovery-interactions-android/110_11.jpg) | Offline like: the card stays, with "…It may still have been recorded; reopen the app to check…" | Pass |
| [110_12](img/discovery-interactions-android/110_12.jpg) | Relaunched offline: "Couldn't load places to swipe" with Retry, never the offline list | Pass |
| [110_12b](img/discovery-interactions-android/110_12b.jpg) | Back online → Retry: the deck resumes at 5 / 10 on the same card, so the offline like was not recorded and nothing was duplicated | Pass |
| [110_13a](img/discovery-interactions-android/110_13a.jpg) | Account B (signed in by Roel): home with B's own heart count (1) | Pass |
| [110_13](img/discovery-interactions-android/110_13.jpg) | Account B's deck: Arima (liked by A) is still unswiped for B, at 2 / 10. Only B's own #56 swipe is skipped. | Pass |

**Found and fixed during device testing:**
- The Pad's Wi-Fi dropped at launch, and the locations request failed. The home screen then silently used its built-in offline list, whose IDs were **truncated UUIDs**, so a like returned 422 with a misleading "trip details" message.
- Fixes:
  - the deck now requires live API places (otherwise it shows Retry);
  - the offline list's IDs were corrected to the full seed UUIDs;
  - interaction 422s get an accurate message.
- A regression test covers this; 220 tests pass.

**Notes:**
- One intended like on Capitol Park was recorded while airplane mode was on, because this Pad keeps Wi-Fi connected in airplane mode. Wi-Fi was then disabled for the offline checks.
- A network drop during sign-in token refresh showed "session expired". That message is misleading, and it is noted for #117.

## Pending

- [x] Android on staging (above).
- [ ] Web after merge.
- [ ] PR review and CI.
