# FruitForm

An iPhone app that photographs piles of tomatoes and extracts **per-fruit shape,
size, eccentricity, flatness, volume, weight, and color** for breeding work — plus
the ML pipeline that trains the on-device shape classifier from your own labeled
photos. On-device LiDAR measurement + a trained YOLOv8 detector/segmenter + a
trained shape classifier, all running offline. Exports to CSV.

> See **[LEARNINGS.md](LEARNINGS.md)** for the *why* — the design decisions, the
> pole-on viewpoint problem, the two-model pipeline, and the gotchas. Read it
> before changing the vision code.

## How it works (two models, a pipeline)

```
Photo ─► Detector/segmenter (TomatoSegmenter, YOLOv8-seg)  →  box + mask per fruit
            └─► per fruit: crop  ─► Shape classifier (TomatoShapeNet, YOLOv8-cls)  →  shape label
                              └─► LiDAR depth + mask  ─► size / volume / flatness / color
```

- **Detector** finds *where* each fruit is and its outline. Trained on
  [LaboroTomato] (CC BY-NC-SA — see Licensing).
- **Shape classifier** says *what shape* one fruit is: `round / oval / flat /
  fasciated` (v2, 4 classes). Trained on the user's own labeled captures.
- **Measurement** comes from the LiDAR depth + silhouette mask (no scale card).

If the classifier isn't confident (or absent), shape falls back to a LiDAR-flatness
+ silhouette heuristic, or optionally a cloud (Claude vision) call.

## What it captures (CSV columns)

Per fruit, one row: `major_axis_cm`, `minor_axis_cm`, `shape_index`,
`eccentricity`, `flatness` (LiDAR height÷width), `solidity`, `volume_cm3`,
`weight_g_est`, `shape_category`, `ripeness`, `color_hex`, `occluded`, `source`
(`device` heuristic / `device+model` trained / `device+cloud` / `manual`).

## Repo layout

```
TomatoBreeder/            SwiftUI app
  App/ Capture/ UI/       app shell, ARKit capture, screens
  Vision/                 detector, classifier, morphometrics, 3D form, manual-add
  Data/ Models/ Cloud/    persistence, CSV, model defs, Claude client
  TomatoShapeNet.mlpackage          shape classifier (committed)
  Models/TomatoSegmenter.mlpackage  fruit detector (committed)
project.yml               XcodeGen project spec (the .xcodeproj is generated)
ml/                       Python training pipeline (see ml/ below)
```

## Build & run on a phone

> New here? **[INSTALL.md](INSTALL.md)** has the full clone-to-phone walkthrough.

Requires **Xcode 26+**, **[XcodeGen]**, and a **LiDAR iPhone** (12 Pro or newer Pro).

```bash
brew install xcodegen          # if you don't have it
# Set your own Apple Developer Team id (10 chars) — replace the one in project.yml:
#   project.yml → settings.base.DEVELOPMENT_TEAM
xcodegen generate              # creates TomatoBreeder.xcodeproj from project.yml
open TomatoBreeder.xcodeproj   # pick your iPhone, ⌘R
```

First launch: allow camera access. Re-run `xcodegen generate` whenever you add or
rename files, or change `project.yml`.

> **Signing:** `project.yml` hard-codes a `DEVELOPMENT_TEAM`. Change it to yours.
> It's an Apple *Team ID*, not a secret, but it must be your own to sign builds.

### Deploy from the command line (optional)

```bash
DEV=<your-device-udid>   # xcrun devicectl list devices
APP=$(xcodebuild -project TomatoBreeder.xcodeproj -scheme TomatoBreeder \
      -destination "id=$DEV" -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/TomatoBreeder.app
xcodebuild -project TomatoBreeder.xcodeproj -scheme TomatoBreeder -destination "id=$DEV" build
xcrun devicectl device install app --device "$DEV" "$APP"
xcrun devicectl device process launch --device "$DEV" com.tomatobreeder.app  # phone must be unlocked
```

## ML pipeline (`ml/`)

```bash
python3 -m venv ml/.venv && source ml/.venv/bin/activate
pip install -r ml/requirements.txt
```

| Script | Does |
|---|---|
| `prepare_seg.py` | build the YOLOv8-seg dataset from LaboroTomato |
| `extract_crops.py` | run the detector over labeled group photos → per-fruit crops (leak-free grouped split) |
| `train_cls.py [mps\|cpu]` | train the shape classifier → exports Core ML to `runs/tomato_cls_v1/weights/best.mlpackage` |
| `report_gen.py` | HTML report: per-prediction galleries + confusion matrices |
| `sample_report.py` | collage of the model on unseen (val) fruit |
| `flag_suspects.py` | flag likely-mislabeled crops (green/leaf + cross-family) for review |

**Retrain loop:** pull `Documents/training/` off the phone (Finder file sharing,
or `devicectl device copy from --domain-type appDataContainer --domain-identifier
com.tomatobreeder.app --source Documents/training <dest>`), then
`extract_crops.py` → `train_cls.py` → copy `best.mlpackage` to
`TomatoBreeder/TomatoShapeNet.mlpackage` → rebuild.

> Datasets, crops, training photos, `runs/`, reports, and the venv are
> **git-ignored** (multi-GB). Get them via the shared drive / release, not git.

## Cloud (optional)

Off by default; fully offline otherwise. **Settings → Use cloud shape
classification**, paste an Anthropic API key, pick Haiku (cheap) or Sonnet. Each
clean fruit crop is sent to Claude for a shape category — used only when the
trained model is absent/unsure. ⚠️ v1 stores the key in `UserDefaults`, not
Keychain — fine for a personal device, move to Keychain before wider distribution.

## Known limits

- **Shape v2 = 4 classes** (round/oval/flat/fasciated); no elongated/heart/pear
  data yet. Round↔oval is the fuzzy boundary; flat/fasciated are strong.
- **Size ≈ ±1 cm** (LiDAR). Great for ratios, marginal for 2–3 mm sib differences.
- **`flatness` is provisional** — single top-down view sees only the fruit's top
  cap; calibrate against calipers before trusting it as an absolute.
- **Detector false positives** (leaf/green blobs) can enter minority classes when
  collecting via pre-sorted trays — keep trays pure and run `flag_suspects.py`.

## Licensing

The **detector is trained on [LaboroTomato]**, which is **CC BY-NC-SA 4.0
(non-commercial)**. Any redistribution of the detector weights inherits that
license. The user's own captured tomato data and the shape classifier trained on
it are the user's. Keep this in mind before making anything public or commercial.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[LaboroTomato]: https://github.com/laboroai/LaboroTomato
