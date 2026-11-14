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

## Spots page (second round)

- **Same header as home** on every phone tab: the greeting pill replaces the old "Maayong hapon!" header bar on Spots, Trips, You and Swipe. The pill and the floating elements are now shared widgets (`GreetingPill`, `FloatingElements` with per-page `ElementPlacement` sets), ready for per-page element sequences later.
- **Spots layout:** "Explore Bacolod" headline with the inasal beside it and the piaya tucked behind the cards; a white glass search pill (clear button; the pill's search icon focuses it); glass category chips **built from the real categories** (so "See 1 museum" from home highlights Museums), and the selected chip scrolls into view.
- **Places as photo cards:** two columns with the photo, a category-colored fade, the name, category · price, and a heart. Tapping a card **expands it in place** to full width, showing the description, vibe tags, address, visit length, price, your rating, **Save** and **Rate**, and **Show less**. One card is open at a time, and the details appear once the card is wide enough so nothing squeezes mid-animation.
- **The saved view** ("Your picks") and empty and loading states share the same design.
- **The menu's Start matching option** now shows the Lagaw logo.

| Shot | Check | Result |
| --- | --- | --- |
| [spots_1](img/home-v3-android/spots_1.jpg) | Spots: greeting pill, headline, search, chips, two-column cards with category fades, name, category · price, heart | Pass |
| [spots_2](img/home-v3-android/spots_2.jpg) | Arima expanded in place: larger title, description, tags, address | Pass |
| [spots_3](img/home-v3-android/spots_3.jpg) | Expanded details: 75 mins, Price unknown, Save, Rate, Show less | Pass |

### Feedback round: cards pop up instead of expanding in place

Roel found the in-place expansion odd, because it pushed the other cards around. Tapping a card now **pops it up** in the same style as the swipe menu: the background blurs and dims, and the card grows smoothly from its spot in the grid (about 420 ms, ease-in-out) into one centered card that is **the same size for every place**. The grid underneath never moves. The photo grows, the × fades in, then the details fade in (description, tags, address, visit length, price, rating, Save and Rate). Close it with the ×, by tapping the blurred background, or with Back; it shrinks back into its spot. Save updates live inside the open card. Under reduced motion it only fades.

| Shot | Check | Result |
| --- | --- | --- |
| [spots_4](img/home-v3-android/spots_4.jpg) | Calea popped up over the blurred grid: photo, name, details, Save, Rate, × | Pass |
| Screen recording (frames reviewed, not committed) | Card grows from its grid spot and shrinks back on close; the grid stays in place; tapping Save turned the heart and button to Saved live (undone afterwards) | Pass |

## Automated checks

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 259 passed, 0 failed |

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
