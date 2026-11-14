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
| Screen recording (frames reviewed, not committed) | Card grows from its grid spot and shrinks back on close; the grid stays in place; tapping Save turned the heart and button to Saved live | Pass |

Note: that Save stayed on account B (Calea Pastries & Coffee). The app can't remove saves yet ("Removing saved places isn't available yet"), so it couldn't be undone from the app.

### Feedback round: one Save, centered Spots title, elements, travel preferences pop-up

- **Open card:** the heart beside the × is gone; the Save button is the one way to save there. Grid cards keep their heart.
- **Spots:** "Explore Bacolod" and "Showing N places" are centered; the piaya moved up beside the title, where it shows.
- **Home:** the piaya and carabao moved down to frame the "See N" pill (where Roel marked them).
- **Travel preferences** is no longer a separate full page. It opens as one white card over the blurred app, in the same style as the swipe menu and Spots cards (fades and rises in, about 380 ms; fade only under reduced motion):
  - welcome and done steps have a sky header with the sun, two Bacolod elements and the Lagaw logo (done adds a check);
  - question steps have a slim sky strip with "Step N of 4" and four segments;
  - interests are soft pills that turn orange; budget is two plain peso fields; travel style is three soft rows with an orange outline; review is one grouped list with Edit;
  - buttons match the Spots card: orange pill for the main action, outlined pill for Back.
  - Steps cross-fade inside the card and the card resizes smoothly. × and tapping the background close it only on welcome and done, so answers aren't lost by a stray tap; Back steps back as before. Same data, validation and saving as before.

| Shot | Check | Result |
| --- | --- | --- |
| [prefs_1](img/home-v3-android/prefs_1.jpg) | First-run welcome over the blurred home: sky header with masskara, inasal, logo, ×; Get started; Skip for now | Pass |
| [prefs_2](img/home-v3-android/prefs_2.jpg) | Step 1: Café and Heritage picked (orange), progress 1 of 4 | Pass |
| [prefs_3](img/home-v3-android/prefs_3.jpg) | Step 3: Moderate selected | Pass |
| [prefs_4](img/home-v3-android/prefs_4.jpg) | Review: Café, Heritage · No preference · Moderate, Edit links, Save preferences (not saved, to keep the account unchanged) | Pass |
| [home_lowered](img/home-v3-android/home_lowered.jpg) | Home: piaya and carabao lowered beside the See pill | Pass |
| [spots_5](img/home-v3-android/spots_5.jpg) | Spots: centered title and count, piaya visible beside it | Pass |
| [spots_6](img/home-v3-android/spots_6.jpg) | Open card: only × at the top, Save button below | Pass |

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

### Round: smoother pop-up, Trips, You, Picked for you, per-page elements

- **Spots pop-up morph:** now a container transform. The frame grows from the card's grid spot with Material's emphasized easing (520 ms open, 400 ms close). The grid card fades out early and the full card fades in, laid out once at its final size and scaled with the frame, so no text reflows and nothing switches size halfway. The grid card hides while it is lifted, one frame after the pop-up draws, so there is never a frame with neither.
- **Trips:** "My Trips" and the count are centered like Spots, with an orange "Plan a new trip" pill and a round refresh button. Trips are white cards with a sky date tile (month and day), title, status, "N days · dates", and soft pills for budget, transport and group.
- **You:** a profile hero like the reference. A big avatar with a white ring and a pencil (shows "Changing your photo is coming soon."; uploads aren't built), a name from the email, liked-and-saved count, and interest chips. Below are the travel preferences in full (interests, budget, pace, with Edit), or a "Take travel preferences" button if not set. Liked and saved shows the first two picks as Spots cards (tapping one opens the same pop-up) with "See all N" to Your picks.
- **Picked for you** (after travel preferences): sky page with the sun and still elements, centered title, a white card with orange pill choices, an orange search button, and white recommendation cards (photo, name, category · price, reason, match %). Same API calls and validation as before.
- **Per-page elements:** one shared element layer for the phone tabs: Home (all four), Spots (inasal, piaya), Trips (carabao, masskara), You (all four around the avatar like stickers), swipe (none). Switching tabs glides each element to its new spot over 720 ms; elements not on the next page shrink and fade, new ones grow in. The bob stops on pages with none and under reduced motion.

| Shot | Check | Result |
| --- | --- | --- |
| [spots_morph_frames](img/home-v3-android/spots_morph_frames.jpg) | 30 fps frames: Cafetolyo grows from its grid spot into the centered card over the blur, no empty slot, no jump | Pass |
| [trips_v3](img/home-v3-android/trips_v3.jpg) | Centered My Trips, 3 saved trips, Plan a new trip, refresh, three white trip cards with date tiles | Pass |
| [you_1](img/home-v3-android/you_1.jpg) | Avatar with pencil, stickers around it, name, liked count, Take travel preferences, Calea pick, See all 1 (email blurred) | Pass |
| Tab recording (frames reviewed, not committed) | Spots → Trips → You: elements glide between sets | Pass |
| Pencil | Shows "Changing your photo is coming soon." | Pass |

Not checked on the phone: the Picked for you screen, because reaching it means saving preferences on account B; it is covered by the widget tests.

### Round: Swipe your vibe redesign

Roel asked for the swipe page to match the other pages, with the title centered and cards like his reference.

- **Centered title:** "Swipe your vibe", with "Drag right to like · left to pass" and the count (for example 2 / 10) in a glass pill.
- **Card:** a full-photo card with a white rim. The next two places sit tilted behind it like a stack of photos, and the one right behind leans in as you drag.
- **Frosted panel on the card:** the area, the name, two lines of description, glass tags (price, visit length, two vibe tags), a glass × (pass) and an orange Like button.
- **Dragging:** the card tilts and dips, the color warms toward Like or Pass, and a LIKE or PASS stamp fades in. Short drags spring back. A new top card settles in from the stack.
- **Unchanged:** swipes are still recorded only after the server confirms, the first pass still explains itself, and Rate stays under the card.

| Shot | Check | Result |
| --- | --- | --- |
| [swipe_v3](img/home-v3-android/swipe_v3.jpg) | Centered title and count, smaller stacked cards, frosted panel with ×, ☆ and Like | Pass |
| Drag recording (frames reviewed, not committed) | Partial right drag: tilt, LIKE stamp, back card leans in, springs back; no swipe sent (still 2/10) | Pass |

Follow-up (Roel): the cards are smaller, then sized to the area Roel marked (1.08 × the screen width tall, 360–440 pt, with a 10 pt side inset), so the card ends just above the nav. "Been here? Rate it" is gone. Rating is now a star button between × and Like, which shows your stars once you rate (for example ★ 4).
