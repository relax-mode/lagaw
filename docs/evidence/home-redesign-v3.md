# Home redesign v3: verification evidence

Branch: `feat/home-redesign-v3`, stacked on #109 (`feat/s4-09-destination-images`) and #117 (PR #174). Designed by Roel with Claude; it went through three mockups, with Roel's feedback after each.

## Why

The old phone home stacked eight bands: the wordmark and tagline, a header with three buttons, chips, a card fan, two equal buttons, empty stats, the nav and a separate orange button. Problems:
- The **Outfit** font the code asked for was never bundled, so Android used its default font.
- The greeting **"Maayong Aga, Roel!" was hardcoded** for every user, at every time of day.

## What changed (phones; the wide/web layout keeps its top-header navigation)

- **Greeting pill:** avatar, a time-of-day Hiligaynon greeting (Maayong aga, udto, hapon or gab-i) and "Bacolod City", the liked-and-saved count on the heart, and search. No invented name.
- **Headline:** "Where to today?" with the real spot count ("10 spots to explore") and the existing tagline.
- **Floating Bacolod elements:** Roel's masskara, chicken inasal, ube piaya and golden carabao.
  - The copies are color-graded to the sky (cooler shadows, warm sun-side light, a soft rim) and shipped as WebP files, about 160 KB in total, with no metadata.
  - They get a sky-tinted drop shadow, are cut off by the screen edges on purpose, and float gently. The floating stops when the system's reduce-motion setting is on.
- **Category carousel:** the categories with real counts (parks 3, cafés 2, then the 1-spot categories). The side cards bend away in perspective. It always opens on **heritage** (or the middle card when there is none), so cards peek from both sides.
  - Each cover uses a place with a licensed photo when one exists (#109); otherwise the honest "No photo yet" placeholder.
- **"See N … →" pill** under the card follows the carousel ("See 3 parks", "See 1 place to eat") and opens Spots with that filter.
- **Nav:** Home · Spots · raised orange **swipe button** · Trips · **You**. The old dock, the separate orange button and the header's duplicate swipe button are removed on phones.
- **Swipe menu:** tapping the button dims and blurs the screen and shows "What do you feel like?" with **Start matching** and **Plan a trip**.
  - The swipe button is in the **app-logo style**: a blue tile with the yellow mascot card, redrawn as vector art from the logo, standing straight. Tapping it **opens the cards**: the glass back card fans out and the yellow card tilts into the logo pose (about 380 ms, eased), on the button's exact spot. The options rise above it with space between. Tapping outside, the logo button or back closes it, folding the cards back. With reduced motion, it shows the open logo with no fan.
  - With reduce motion on, it only fades.
- **You tab:** the account email, Travel preferences, Liked and saved, and Sign out. These already existed, but were hidden behind the avatar.
- **Font:** Outfit is bundled at weights 400–900 (`assets/fonts`, SIL Open Font License 1.1, license file included) and is now the app's default font.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 251 passed, 0 failed |

New `test/home_v3_test.dart` covers:
- the greeting by hour;
- category grouping, order, labels and singular/plural ("See 1 heritage spot");
- choosing a cover with a licensed photo;
- the home view's greeting, real counts and callbacks;
- the pill following the carousel;
- the places-state fallback;
- nav selection;
- the swipe menu: Start matching, Plan a trip, tapping outside, ×, and reduced motion;
- the You tab without a session.

The swipe-deck tests now open the deck through the nav menu. The test that asserts the hardcoded "Maayong Aga, Roel!" no longer appears is part of the home view tests.

## Device (Infinix X6850, release APK against staging, 2026-11-14)

| Shot | Check | Result |
| --- | --- | --- |
| [v3_1](img/home-v3-android/v3_1.jpg) | Home opens on **heritage** (Roel's choice) with dining and landmarks peeking on both sides; "See 1 heritage spot →"; the swipe button sits lower, into the white nav | Pass |
| [v3_2](img/home-v3-android/v3_2.jpg) | Carousel mid-way: dining · 1 spot between art and heritage; pill reads "See 1 place to eat" | Pass |
| [v3_3](img/home-v3-android/v3_3.jpg) | Swipe menu: dimmed and blurred, Start matching / Plan a trip, × in the button's place | Pass |
| [v3_4](img/home-v3-android/v3_4.jpg) | Start matching opens the swipe deck | Pass |
| [v3_5](img/home-v3-android/v3_5.jpg) | "See 3 parks →" opens Spots with exactly the 3 parks; header "Maayong hapon!", no duplicate swipe button | Pass |
| [v3_6](img/home-v3-android/v3_6.jpg) | You tab: account, Travel preferences, Liked and saved, Sign out | Pass |
| [v3_7](img/home-v3-android/v3_7_open.jpg) | Frames from a screen recording: the straight yellow mascot card **opens** as the glass back card fans out behind it, settling into the Lagaw logo pose at the button's spot (the doubled eyes mid-motion are recorder frame blending) | Pass |

**Notes**
- No photos are uploaded to staging yet (#109), so the category covers show the honest "No photo yet" placeholder. They switch to the licensed photos with credits once the upload is done.
- Staging's first request after idling sometimes times out; Retry works, which is the honest error state from #117.
- Minor: after "See 3 parks", the selected Parks chip is scrolled just out of view in the Spots chip row.
