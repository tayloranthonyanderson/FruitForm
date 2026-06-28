# FruitForm

[![CI](https://github.com/tayloranthonyanderson/FruitForm/actions/workflows/ci.yml/badge.svg)](https://github.com/tayloranthonyanderson/FruitForm/actions/workflows/ci.yml)

An iPhone app that turns a pile of tomatoes into per-fruit shape & size data —
shape class, a 1–9 shape-quality rating, size (cm), volume, weight, eccentricity,
flatness, and color — using the LiDAR depth camera and three on-device neural nets (a
detector plus two classifiers). Runs fully offline by default; no scale card. A personal
side project exploring on-device computer vision and LiDAR depth measurement.

> *Personal project, built on my own time and equipment using publicly available or
> self-collected data. Not affiliated with, funded by, or derived from any employer's
> work, data, or systems.*

![FruitForm detecting and grading a tray of tomatoes](docs/demo.jpg)

*A single example tray, captured on-device: each fruit is segmented, then run through the
shape and rating classifiers while LiDAR measures absolute size — all on-device.*

## How it works — a detector + two classifiers (three on-device models)

```
Photo (12 MP) ─► Segmenter (YOLOv8-seg, Core ML) ──► box + mask per fruit
                     └─ per fruit ─► crop ─► Shape classifier (YOLOv8-cls)  → round/oval/flat/fasciated
                                        └─► Rating classifier (YOLOv8-cls)  → 1–9 desirability
                     └─ box + mask + LiDAR depth + intrinsics ─► size · volume · weight · flatness · color
```

Three small models — one detector and two classifiers (shape + rating) — run
sequentially on-device (Core ML / Vision / the Neural Engine).
Keeping detection and classification separate means shape can improve from more *shape*
labels without ever retraining detection. The detector even doubles as the tool that
chops labeled group photos into per-fruit crops to *build* the classifier's training set.

Everything above runs on-device. An optional cloud step — the Anthropic API, **off by
default** (enable it and add your own key in Settings) — can second-guess the shape call on
ambiguous fruit; results that used it are tagged `device+cloud`. See
[`FruitForm/Cloud/`](FruitForm/Cloud/).

[LEARNINGS.md](LEARNINGS.md) documents the *why* behind the non-obvious decisions and the
gotchas (coordinate frames, Core ML name collisions, MPS quirks). Read it before changing
the vision code.

## Tech stack

- **App:** Swift, SwiftUI, ARKit, SceneKit, Core ML, Vision, Accelerate.
- **ML:** Python, Ultralytics YOLOv8 (seg + cls), PyTorch, Core ML Tools; trained on
  device-collected data with leak-free grouped train/val splits.
- **Tooling:** XcodeGen (project generated from `project.yml`), XCTest, GitHub Actions CI.

## What it captures (CSV, one row per fruit)

`major_axis_cm`, `minor_axis_cm`, `shape_index`, `eccentricity`, `flatness`, `solidity`,
`volume_cm3`, `weight_g_est`, `shape_category`, `shape_rating`, `ripeness`, `color_hex`,
`occluded`, `source`.

## Build & run

Requires Xcode 26+, [XcodeGen], and a LiDAR iPhone (12 Pro or newer Pro, iOS 17+).

```bash
brew install xcodegen
xcodegen generate            # generates FruitForm.xcodeproj from project.yml
open FruitForm.xcodeproj # set your own signing team, pick your iPhone, ⌘R
```

Full walkthrough: [INSTALL.md](INSTALL.md). Run the tests with:

```bash
xcodebuild test -scheme FruitForm -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Repo layout

```
FruitForm/   SwiftUI app — Capture/ Vision/ UI/ Data/ Models/ Cloud/  + committed .mlpackage models
Tests/           XCTest unit tests (crop geometry, training modes, letterbox math)
ml/              Python training pipeline (extract crops → train → export Core ML)
docs/            demo media
project.yml      XcodeGen spec (the .xcodeproj is generated, not committed)
```

## ML pipeline (`ml/`)

```bash
python3 -m venv ml/.venv && source ml/.venv/bin/activate && pip install -r ml/requirements.txt
```

`extract_crops.py` (group photos → per-fruit crops, leak-free split) → `train_cls.py` /
`train_rating.py` (YOLOv8-cls → Core ML) → copy `best.mlpackage` into the app → rebuild.

## Notes & limits

- **Shape v2 = 4 classes**, **rating = odd anchors 1/3/5/7/9** so far — proof-of-concept
  models from a small single-rater dataset; accuracy improves with more diverse capture.
- The fruit **detector is trained on [LaboroTomato] (CC BY-NC-SA 4.0 — non-commercial)**;
  any redistribution of those weights inherits that license. Research/personal use only.
  See [NOTICE.md](NOTICE.md) for the full source-code (MIT) vs. bundled-model licensing split.
- **Classifier training data:** the shape/rating models were trained on my own photos of
  grocery-store tomatoes I bought myself. No proprietary or employer germplasm, data, or
  imagery is used anywhere in this project.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[LaboroTomato]: https://github.com/laboroai/LaboroTomato
