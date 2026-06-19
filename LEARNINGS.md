# Learnings — design decisions & gotchas

The *why* behind the code. If you're going to change the vision/ML parts, read
this first; several non-obvious decisions will otherwise look wrong.

## The product

Photograph a pile of processing tomatoes; get per-fruit **shape class, size,
eccentricity, flatness, volume, weight, color**. Capture is a pile on the ground
in random orientations — not a controlled lightbox. LiDAR is used for scale (no
physical scale card). Hybrid: on-device first, optional cloud refinement.

## The one insight that shapes everything: pole-on viewpoint

A tomato resting on a surface sits **pole-up** (the stem→blossom axis vertical),
because oblate fruit are stable that way. So a top-down photo looks *straight down
the polar axis*, and the silhouette you get is the **equatorial cross-section**.
The dimension that separates round from oblate ("flat") from elongated — the polar
height — points **at the lens** and is invisible in 2D.

Consequences:
- A flat beefsteak and a round globe both project a round-ish top. A pure 2D
  silhouette classifier (and even a generic cloud vision model) calls both
  "round." This is a *viewpoint* limit, not a model bug.
- You do **not** need stem-end detection to classify shape. But you **do** need
  the polar axis to be *recoverable* — either seen side-on, or via 3D/LiDAR.
- Fixes used: (1) LiDAR `flatness` (`FruitForm3D`) recovers the missing axis and
  upgrades round-but-flat fruit to "flat"; (2) a classifier trained on *your*
  top-down photos learns the human-visible cues (blossom-end star scar, lobing)
  that correlate with shape even from above. The human label supplies what the
  pixels alone can't.

## Two models, not one (a pipeline)

- **Detector** (`TomatoSegmenter`, YOLOv8-seg): *where* + outline. Trained on the
  public LaboroTomato set; general to any tomato.
- **Shape classifier** (`TomatoShapeNet`, YOLOv8-cls): *what shape*, on a single
  fruit crop. Trained on the user's labels.
- They run **sequentially**. Keeping them separate means you can improve shape
  by collecting more *shape* labels without ever retraining detection, and the
  detector stays general. Neat trick: the detector is what chops the labeled
  group photos into per-fruit crops to *build* the classifier's training set.

## Measurement

- Size from LiDAR depth × silhouette extent and camera intrinsics (`fx,fy`).
  `~±1 cm`. Shape ratios (`shape_index`, `eccentricity`) are depth-independent.
- `flatness = LiDAR cap-height ÷ equatorial radius` — **provisional**: a single
  top-down view sees only the top cap, so it's a partial estimate. Good enough to
  *flag* clearly flat fruit; calibrate vs calipers before trusting the number.
- Volume = ellipsoid from mask area + depth shell; weight = volume × ~0.98 g/cm³.

## Data collection: the pre-sort trade-off

Training captures use **pre-sort → label the whole photo**: sort a tray to one
shape, shoot it, every detected fruit inherits that label. Hugely efficient (one
tap = a dozen labeled fruit) and unambiguous *if the tray is pure*.

The cost: stray fruit and **detector false positives (leaf/green blobs)** in the
frame also inherit the label → mislabeled crops, worst in the small classes.
Mitigations: keep trays pure; `flag_suspects.py` surfaces green/leaf + cross-family
strays for review (note: round↔oval disagreement is the *fuzzy boundary*, NOT
contamination — don't auto-remove those); a "not-a-fruit" reject class is the
durable fix and isn't built yet.

## Training notes

- `extract_crops.py` does a **grouped split by source photo** so the same fruit
  can't leak across train/val (otherwise val accuracy lies).
- Fruit-level imbalance is severe even when *photo* counts are balanced (round/oval
  are small → many per tray; flat/fasciated are big → few). `train_cls.py` balances
  to ~1000/class by undersampling majors + oversampling minors with augmentation.
- v2 (current): val top-1 0.87; recall fasciated .96 / flat .97 / oval .87 /
  round .87. Only round↔oval confuse. v1→v2 removed 19 green/leaf crops mislabeled
  fasciated.

## Gotchas (will bite you)

- **MPS:** YOLO *detection/seg* loss assigner crashes on Apple MPS on this box —
  train seg with `device=cpu`. *Classification* (plain cross-entropy) is fine on
  MPS.
- **Core ML name collision:** a bundled `Foo.mlpackage` makes Xcode auto-generate
  `Foo.swift` / a `Foo` class. If you also hand-write `Foo.swift`, the build fails
  ("filename used twice"). That's why the model resource is `TomatoShapeNet` while
  the hand-written class is `TomatoShapeClassifier`, and the detector is
  `TomatoSegmenter` vs `TomatoDetector`. Keep resource names ≠ your class names.
- **Coordinate flips:** the photo is stored in raw sensor (landscape) orientation;
  the UI shows it rotated `.right` (portrait). Masks are 160×160 in *sensor* space.
  Display↔sensor mapping: `rawX = dispY`, `rawY = 1 − dispX` (and inverse). Get
  this wrong and taps/markers land on the wrong fruit. See `SessionImageView`,
  `CaptureViewModel`.
- **YOLO-seg mask decode:** the model letterboxes (`.scaleFit`) into 640²; you must
  un-letterbox before using boxes/masks, and threshold the mask logit at 0 (==
  sigmoid>0.5). Decoded with a BLAS GEMV over the 32 prototype coeffs. See
  `TomatoDetector`.
- **Solidity:** must build the convex hull from cell **corners**, not centers —
  center-hull is systematically smaller than the cell-counted area, so solidity
  clamps to 1.00 for everything. (Fixed; don't reintroduce.)
- **XcodeGen:** the `.xcodeproj` is generated and git-ignored. Add a file → run
  `xcodegen generate`, or the build won't see it.
- **Classifier crop padding = fraction of the BOX, not the image.** The on-device
  crop fed to the shape/rating classifier must pad by `box_width * 0.06`, matching
  `ml/extract_crops.py`. An earlier bug padded by `image_width * 0.06` (~115 px on a
  1920px frame), burying each fruit in background — the classifier then called
  everything flat/fasciated / rating 9 at high confidence, while every offline test
  on the *stored* photos looked fine. Train/serve crop framing must match. See
  `CaptureProcessor.paddedPixelRect` (and the same fix in `ManualFruit`,
  `ARCaptureController.cropNorm`).
- **Codable + new manifest fields:** Swift's synthesized `Decodable` does NOT honor
  a property's default value for a missing key — it throws `keyNotFound`. Adding a
  non-optional `mode` to `TrainingSample` made the app fail to load every old
  manifest entry (then overwrite it). Make new manifest fields **Optional** so old
  records decode (missing key → nil). See `TrainingSample.mode`.
- **Capture resolution:** ARKit's live frame is only 1920×1440 (2.8 MP). For a
  zoomable archive + sharp classifier crops, set
  `config.videoFormat = recommendedVideoFormatForHighResolutionFrameCapturing` and
  grab the shutter still via `session.captureHighResolutionFrame` (→ 12 MP). LiDAR
  depth is a separate stream and survives the format change (verify it does, and
  keep the fallback). Depth itself stays 256×192 regardless. See `ARCaptureController`.
