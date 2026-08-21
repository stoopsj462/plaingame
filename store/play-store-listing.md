# Jason's Game — Google Play Store Listing Copy

Paste-ready metadata for Google Play Console. Character limits noted in parentheses.

---

## App Name (30)
`Jason's Game: Platform Jumper`

## Short Description (80)
`Dodge barrels, bombs, and platforms in this classic run-and-jump adventure.`

## Full Description (4000)
Climb, jump, and run for it.

Jason's Game is a classic run-and-jump platform adventure. Cross a chain of floating platforms while a plane drops bombs from above and a barrel-throwing troublemaker sends rolling drums straight at you. One touch of a barrel, a bomb, or a bottomless pit sends you back to the start — so time every jump and keep moving.

FEATURES
• Simple touch controls — on-screen left/right/jump/crouch buttons, plus full keyboard support (WASD or arrow keys + space)
• Three difficulty levels — Easy, Medium, and Hard change enemy speed and how often barrels drop
• Hand-drawn characters and a painted mountain backdrop
• No ads. No in-app purchases. No accounts. No tracking. Works fully offline.

How far can you make it before gravity — or a rolling barrel — wins?

---

## Google Play Console settings
- **Price:** Free
- **Category:** Games → Arcade / Action
- **Content Rating:** PEGI 3 / ESRB E
- **Data Safety:** No data collected
- **Support URL:** https://github.com/stoopsj462/plaingame
- **Privacy Policy URL:** https://github.com/stoopsj462/plaingame/blob/main/PRIVACY_POLICY.md
  - (Also mirrored at https://stoopsj462.github.io/plaingame/privacy.html if GitHub Pages is enabled for this repo — Settings → Pages → Deploy from branch `main` / `docs`.)

## Graphical Assets
- **Icon:** [store/assets/icon_512.png](assets/icon_512.png) — 512x512 PNG
- **Feature Graphic:** [store/assets/feature_graphic.png](assets/feature_graphic.png) — 1024x500 PNG
- **Screenshots:** [store/screenshots/](screenshots/) — phone-01-menu.png, phone-02-gameplay.png, phone-03-barrels.png (2560x1510, more than covers the 320–3840px requirement)

## Release Bundle
- **AAB:** `app/build/outputs/bundle/release/app-release.aab` (run `./gradlew bundleRelease` to (re)generate)
- Signed with `app/release.keystore` — **back this file and `keystore.properties` up somewhere safe.** If you lose them, you lose the ability to publish updates to this app under the same listing.
