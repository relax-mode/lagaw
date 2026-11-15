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

Follow-up (Roel): the cards are smaller, then sized to the area Roel marked (1.08 × the screen width tall, 360–440 pt, with a 10 pt side inset), so the card ends just above the nav. The deck then moved 30 pt lower (52 pt gap under the subtitle), so the tilted back cards no longer touch "Drag right to like". "Been here? Rate it" is gone. Rating is now a star button between × and Like, which shows your stars once you rate (for example ★ 4).

Follow-up (Roel): no more waiting on Like. Swipes are now **optimistic**: the card flies off (220 ms) and the next place shows at once while the swipe is sent in the background. If sending fails, the swipe is undone, the place comes back to the top, and the error explains why (a response that never arrived still says it may have been recorded). The swipe is still sent once and never retried automatically. Saves and ratings still wait for the server.

| Shot | Check | Result |
| --- | --- | --- |
| [swipe_instant_frames](img/home-v3-android/swipe_instant_frames.jpg) | 30 fps: Like on Capitol Park flies the card off with the LIKE stamp; Negros Forest Park (6 / 10) shows straight after, with no "Saving…" | Pass |

### Round: elements on Swipe and smoother page changes

- **Swipe your vibe has elements:** piaya and masskara peek out from behind the card's sides, with carabao and inasal at its bottom corners.
- **Smoother element glide (950 ms):** elements start a beat apart (70 ms) and each eases in and out. Ones that stay on the same side rise in a slight arc. Ones that change sides drift out past their old edge and back in from the new one, instead of flying across the page. New and leaving elements drift in and out from the nearest edge instead of shrinking in the middle.
- **Pages cross-fade (280 ms)** while the elements move, instead of snapping. Each phone tab fades as a whole with its own header, so nothing jumps when the greeting pill comes or goes.
- Tests: swipe-deck tests run with reduced motion (the elements hold still) so they can settle. A new test checks that an element changing sides never crosses the middle.

| Shot | Check | Result |
| --- | --- | --- |
| [swipe_elements](img/home-v3-android/swipe_elements.jpg) | Swipe page with four elements around the card | Pass |
| [elements_glide_frames](img/home-v3-android/elements_glide_frames.jpg) | Swipe → Home at 10 fps: pages cross-fade in place, masskara leaves right and returns left, nothing crosses the page | Pass |

### Round: intro and sign-in redesign

Roel asked for a swipeable introduction before sign-in, with the swiping cards first and a welcome page last, and for log in and sign up in the v3 style. Email only; Lagaw has no social sign-in.

- **Intro (`WelcomeFlow`, signed out):** four pages on the sky, with a white panel holding the title, words, page dots (the active one stretches, orange) and Next. Skip is at the top right.
  1. **Swipe your vibe:** a small deck on a loop. The top card gets a LIKE stamp, flies right, and the next one settles in. Masskara and inasal float around it.
  2. **Find spots around Bacolod:** floating category pills (Cafés, Heritage, Parks, Food, Art, Landmarks, Sweets) with piaya and carabao.
  3. **Plan a trip in seconds:** a "Planned for you" Day 1 card whose stops tick in one by one.
  4. **Welcome to Lagaw:** the logo with the four elements, "Maayong pag-abot!", and **Create account** (orange) and **Log in** (outlined).
- After the welcome page is reached once (or Skip is tapped), later sign-outs open straight on the welcome page (`lagaw.intro.seen` in shared preferences).
- **Log in / Create account (`SignInScreen`):** a sky header with the sun, masskara, inasal and the Lagaw logo, plus a white sheet with a centered title ("Welcome back", "Create your account"), soft filled fields, "Forgot password?" on the right, an orange pill button, and "Don't have an account? Sign up" / "Already have an account? Log in". Back returns to the welcome page.
- **Unchanged:** validation, the rate-limit cooldown, password reset, the email-confirmation message, and re-sign-in after an expired session (still pushed over the app, so unsaved forms are kept).
- Reduced motion stops the intro loops.
- Tests: auth tests open the form directly (`AuthGate(intro: false)`); a new `welcome_flow_test.dart` covers the walkthrough (Next, a swipe, Skip), the seen flag, Create account / Log in / Back, and signing in from the intro. `flutter test` passes 275.
- Device check (Infinix, staging build installed fresh with app data cleared): the intro opens on Swipe your vibe with the demo running; Next, swipes and Skip work; the welcome page shows both buttons; and a relaunch opens straight on the welcome page. Fixed while checking: the Art and Landmarks pills overlapped on page 2, and the white "Back" text was hard to read over the sun (now a white pill).

| Shot | Check | Result |
| --- | --- | --- |
| [intro_1](img/home-v3-android/intro_1.jpg) | Swipe your vibe: card deck demo, dots 1 of 4, Next, Skip | Pass |
| [intro_2](img/home-v3-android/intro_2.jpg) | Find spots around Bacolod: floating category pills, none overlapping | Pass |
| [intro_3](img/home-v3-android/intro_3.jpg) | Plan a trip in seconds: Day 1 card with stops ticking in | Pass |
| [intro_4](img/home-v3-android/intro_4.jpg) | Welcome to Lagaw: logo and elements, Create account and Log in | Pass |
| [auth_login](img/home-v3-android/auth_login.jpg) | Welcome back: sky header with logo, email, password, Forgot password?, Log in, Sign up link | Pass |
| [auth_signup](img/home-v3-android/auth_signup.jpg) | Create your account: Back pill, email, password, confirm, Create account, Log in link | Pass |

Follow-up (Roel): the form sheet left a large empty white area at the bottom. It is now only as tall as the form, sitting at the bottom; the spare height goes to the sky, with a larger logo in the middle. Everything scrolls when the keyboard is up (checked on the Infinix; the Log in button stays visible above the keyboard). On the "Sign in again" screen after an expired session, the sheet leaves room for the expiry banner at the bottom, which would otherwise cover the button (caught by the existing re-sign-in test).

### Round: lighter swipe card, collapsing header, Liked and saved on You, budget rule

- **Budget:** an empty minimum now counts as ₱0 when a maximum is given, so "up to ₱2,000" saves as ₱0 – ₱2,000. A minimum without a maximum still asks for the maximum. The Min field is labeled "(optional)", with "0" as its hint, and the step explains it ([prefs_budget_v2](img/home-v3-android/prefs_budget_v2.jpg)).
- **Picked for you:** the two questions are now separate numbered cards (the number turns into a check once answered), with roomier chips and the search button below them ([picked_v2](img/home-v3-android/picked_v2.jpg)).
- **Swipe card:** the panel on the photo shows only the name, a two-line description and the price; time, area and hashtags are gone. Tapping the card opens the same details pop-up as Spots ([swipe_details](img/home-v3-android/swipe_details.jpg)). Pass (×), Rate (★) and Like (♥) are round buttons under the card ([swipe_v4](img/home-v3-android/swipe_v4.jpg)).
- **Swipe header:** the greeting pill folds away to just its heart, docked top-right, with a 560 ms collapse as the page opens.
- **The heart opens You** (no longer Spots' "Your picks") and scrolls to Liked and saved. **See all** expands the list right there, with a search bar and category chips; **Show less** folds it back ([you_liked_all](img/home-v3-android/you_liked_all.jpg), Cafés chip: [you_liked_cafes](img/home-v3-android/you_liked_cafes.jpg)). Removing a like or save is still not possible; the interaction history is append-only by design (#110).
- **Category names:** staging now has 30 places in 23 finer categories (for example `local_food`, `coastal_day_resort`). Each has a friendly name (Local food, Beaches, Farms…), and any future id shows with spaces instead of underscores.
- Device check (Infinix, staging): all of the above. Roel's travel preferences were saved again unchanged (Food, no budget, Slow) to reach Picked for you. `flutter test` passes 277.

Follow-up (Roel): in the details pop-up (Spots, You and the swipe card), the description shows three lines with **See more** / **See less** (shown only when it runs longer). **Rate is on the left and Save on the right**, pinned at the bottom of the card so they are always in view, while the details above them scroll ([details_short](img/home-v3-android/details_short.jpg), [details_more](img/home-v3-android/details_more.jpg)). `flutter test` passes 278 (1 new).

Follow-up (Roel): places liked by swiping right appeared in Liked and saved with hollow hearts, because the heart only checked **saved**. Hearts (Spots, You, details, and the wide layout) now fill for any place that is liked **or** saved and not passed (`DiscoveryInteractions.isPicked`); tapping a filled heart explains that removing isn't available yet ([you_hearts_filled](img/home-v3-android/you_hearts_filled.jpg)). Un-liking needs a backend change (see the sprint log). `flutter test` passes 279.

### Round: See places for me on You, Picked for you as a pop-up, tidier swipe deck

- **You:** the interest chips under the name are gone (they're in the preferences card). The preferences card has even 20 pt margins and a compact Edit pill. A **See places for me** button sits under it ([you_prefs_v2](img/home-v3-android/you_prefs_v2.jpg), email blurred).
- **Picked for you is now one pop-up** over the blurred app, in three steps:
  1. **Review:** interests, budget and pace, with **Edit** (opens travel preferences, then the review reloads) and **Looks good** ([picked_review](img/home-v3-android/picked_review.jpg)).
  2. **Who's coming and max spend** ([picked_setup](img/home-v3-android/picked_setup.jpg)).
  3. **Your top places:** a numbered list in rank order with a small photo, name and category · price, and a heart to like each place. There are no percentages or reasons; tapping a place opens the full details ([picked_results](img/home-v3-android/picked_results.jpg), [picked_details](img/home-v3-android/picked_details.jpg)).

  Finishing travel preferences continues into the same pop-up at step 2. If a refresh fails, earlier results stay in view under the error.
- **Categories:** the chips in the expanded Liked and saved list use the same categories, in the same order, as Spots.
- **Swipe deck:** the card is sized from the screen height (300–400 pt, about 4:5) and centered between the title and the buttons. The cards behind tilt and offset less (2.5°, 8 pt), so they only peek ([swipe_v5](img/home-v3-android/swipe_v5.jpg)).
- `flutter test` passes 280 (a new test covers review → Edit → questions → places → heart). Verified on the Infinix.

### Round: trip screens, collapsed headers, swipe to delete

**Verified reports (all confirmed in the code, now fixed):**
1. *Pace and people not carried into Plan with AI.* Trips have no pace column, and "Describe your trip" only applied vibes; its pace and group were shown for reference only. Plan with AI always started on "Moderate". Now Plan with AI starts from the pace saved in travel preferences (until the user picks another), and Describe your trip fills in **Who's coming** and the **budget** when those fields are still empty ("Added 1 vibe, who's coming, budget…"). People going follows Who's coming (solo 1, couple 2, friends 3, family 4) as before.
2. *"plan with AI" lowercase:* now "Plan with AI" (and "Edit trip").
3. *"plan a trip" lowercase, with an em dash:* now "Plan a trip", with "Set the basics, and Lagaw fills in the stops later."
4. *Describe your trip in a different style:* it used a purple, bevelled 3D look. It now uses the same type, filled field and pill button as the rest of the form.

**Changes:**
- **Plan a trip is a pop-up** over the blurred app (shared `blurPopupRoute` / `PopupCard`). Inside, the form's sections are separated by dividers instead of being cards inside the card ([plan_trip_popup](img/home-v3-android/plan_trip_popup.jpg), [plan_trip_popup_2](img/home-v3-android/plan_trip_popup_2.jpg)).
- **Shared v3 styling:** the app's card (`GlassContainer`) and button (`Vector3DButton`) are now flat, with soft shadows and a gentle press, instead of 3D bevels. Trip-form fields are filled with an orange focus ring; chips are soft pills that turn orange with a check. The trip pages (Plan with AI, trip details, Edit trip) get the sky with the sun, a round back button and centered titles.
- **Min budget optional on trips:** empty saves as ₱0, matching travel preferences.
- **Headers:** the greeting pill folds to its heart on every tab except Home (Spots, Trips, Swipe; You has its own profile header) ([spots_v6](img/home-v3-android/spots_v6.jpg), [trips_v4](img/home-v3-android/trips_v4.jpg)). The Spots chip "All spots" is now "All".
- **My Trips:** swipe a trip left to delete it, after a confirmation pop-up. The card only leaves once the server confirms; a failure keeps it and explains why. "Trip deleted." fades away after 3 s. Date tiles fit the dates: "NOV / 10–14" within a month, "NOV 28 to DEC 2" across months, "DEC / 5" for one day.
- `flutter test` passes 285. On the Infinix: Trips, the Plan a trip pop-up and Spots were checked. Swipe-to-delete and the Plan with AI page were covered by tests only, to avoid deleting real trips or generating plans on staging.
