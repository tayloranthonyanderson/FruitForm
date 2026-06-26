# Installing FruitForm on your iPhone

This covers getting the **app** running on a device. (The Python/ML pipeline is
optional and only needed for retraining — see the README.)

## Prerequisites

- **A Mac** with **Xcode 26+** (Xcode is macOS-only).
- **A LiDAR iPhone** — iPhone 12 Pro or any newer **Pro** model — on **iOS 17+**.
  Size, volume, and flatness all come from LiDAR; non-Pro phones won't measure.
- **An Apple ID.** A *free* one works for installing to your own device — no paid
  Apple Developer account required.

## Steps

```bash
# 1. Clone
git clone https://github.com/tayloranthonyanderson/FruitForm.git
cd FruitForm

# 2. Install XcodeGen (the .xcodeproj is generated, not committed)
brew install xcodegen

# 3. Generate the Xcode project from project.yml
xcodegen generate

# 4. Open it
open FruitForm.xcodeproj
```

Then in Xcode:

5. **Add your Apple ID:** Xcode → **Settings → Accounts → +** → sign in (free is fine).
6. **Sign with your team:** select the **FruitForm** target → **Signing &
   Capabilities** → check **Automatically manage signing** → choose **your** team
   in the **Team** dropdown.
   > `DEVELOPMENT_TEAM` in `project.yml` ships empty — you set your own 10-character
   > Team ID for device builds, then re-run `xcodegen generate` (or just pick your
   > team in Step 6). Simulator builds — what CI runs — need no signing team.
7. **Connect your iPhone**, unlock it, tap **Trust** on the phone, and pick it as
   the run destination in the top bar.
8. Press **⌘R** to build & run.
9. **First launch** shows "Untrusted Developer." On the phone: **Settings →
   General → VPN & Device Management** → tap your developer profile → **Trust**.
   Re-open the app.
10. **Allow camera access** when prompted.

All three trained models (`TomatoSegmenter`, `TomatoShapeNet`, `TomatoRatingNet`)
are already in the repo, so there's nothing else to download for the app to work.

## Two common first-time snags

- **A build stalls on a component download.** Xcode 26 ships "skinny" — the first
  device build may need to fetch iOS platform support (several GB) via Xcode →
  **Settings → Components**. Let it finish, then build again.
- **Free Apple ID builds expire after 7 days.** Fine for tinkering — just re-run
  ⌘R from Xcode to reinstall. A paid ($99/yr) account removes the expiry; you
  don't need it to develop.

## Command-line deploy (optional, once it builds in Xcode)

```bash
DEV=<device-udid>            # xcrun devicectl list devices
APP=$(xcodebuild -project FruitForm.xcodeproj -scheme FruitForm \
      -destination "id=$DEV" -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/FruitForm.app
xcodebuild -project FruitForm.xcodeproj -scheme FruitForm -destination "id=$DEV" build
xcrun devicectl device install app --device "$DEV" "$APP"
xcrun devicectl device process launch --device "$DEV" com.fruitform.app   # phone must be unlocked
```

## Licensing note

The fruit **detector** is trained on [LaboroTomato] (CC BY-NC-SA 4.0 —
**non-commercial**). Fine for research and tinkering; not for a commercial
release.

[LaboroTomato]: https://github.com/laboroai/LaboroTomato
