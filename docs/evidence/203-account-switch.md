# #203 account switching on a device

November 27, 2026. Staging release build of `fix/frontend-panel-hardening` on an Infinix X6525 (Android). Roel signed in with two staging test accounts; screenshots were taken over adb. No credentials or email addresses are shown.

| Step | Result | Screenshot |
| --- | --- | --- |
| 1. Sign in as A | Home, avatar "R", 9 liked | [01](203-account-switch/01-account-A_1.png) |
| 2. A's My Trips | fff, yrsd, Web extraction… | [02](203-account-switch/02-account-A_2_trips.png) |
| 3. Open A's trip | "fff" pop-up open, then sign out | [03](203-account-switch/03-account-A_3_popup.png) |
| 4. Sign in as B | Starts fresh on Home, avatar "S", 1 liked; nothing from A | [04](203-account-switch/04-account-B_1.png) |
| 5. B's My Trips | Only B's trips: Account B Test…, problem cases, manual trip | [05](203-account-switch/05-account-B_2_trips.png) |
| 6. Back to A | A's three trips unchanged | [06](203-account-switch/06-account-A_5_trips.png) |

**Result: pass.** Signing out and in as another account reset navigation and account data; nothing from the previous account was shown. DevOps staging evidence is separate.
