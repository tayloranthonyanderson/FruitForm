"""
Turn the pre-sorted group photos into a per-fruit classification dataset.

For each labeled photo, run the trained segmenter to find every fruit, crop it
(box + small pad — same crop the app will feed the classifier at inference), and
write it under <out>/<split>/<CATEGORY>/. The train/val split is *grouped by
source photo*: all crops from one photo stay on the same side, so no fruit leaks
across the split and the val score is honest.

Two modes (matches the app's TrainingMode):
  --mode shape_class   shape labels (ROUND/OVAL/FLAT/FASCIATED) -> cls_ds   [default]
  --mode shape_rating  the 1-9 desirability scale               -> rating_ds
Legacy samples have no "mode" key; they're treated as shape_class, so
`--mode shape_class` reproduces the original dataset exactly.
"""
import argparse, json, os, random
from pathlib import Path
from collections import defaultdict, Counter
from PIL import Image
from ultralytics import YOLO

ap = argparse.ArgumentParser()
ap.add_argument("--mode", default="shape_class",
                choices=["shape_class", "shape_rating"])
ap.add_argument("--src", default="~/Desktop/tomato_training_pull",
                help="folder with the pulled photos + manifest.json")
args = ap.parse_args()
DEFAULT_MODE = "shape_class"   # legacy samples (no "mode" key) bucket here

SRC = Path(os.path.expanduser(args.src))
SEG = str(Path(__file__).parent / "runs/tomato_seg_v1/weights/best.pt")
if args.mode == "shape_class":
    CLASSES = ["ROUND", "OVAL", "FLAT", "FASCIATED"]   # the 4 with data
    OUT = Path(__file__).parent / "cls_ds"
else:  # shape_rating
    CLASSES = [str(i) for i in range(1, 10)]           # "1".."9"
    OUT = Path(__file__).parent / "rating_ds"
CONF = 0.50          # match the app's detector; high precision = clean crops
PAD = 0.06           # same pad as the app's cloud-crop
VAL_FRAC = 0.15
MIN_PX = 24

manifest = json.load(open(SRC / "manifest.json"))
by_label = defaultdict(list)
for s in manifest:
    if s.get("mode", DEFAULT_MODE) == args.mode and s["label"] in CLASSES:
        by_label[s["label"]].append(s["id"])

# Grouped, stratified split: per class, hold out VAL_FRAC of the *photos*.
random.seed(42)
split = {}
for label in CLASSES:
    ids = by_label[label][:]
    random.shuffle(ids)
    nval = max(1, int(round(len(ids) * VAL_FRAC)))
    for i, _id in enumerate(ids):
        split[_id] = "val" if i < nval else "train"

for sub in ("train", "val"):
    for c in CLASSES:
        (OUT / sub / c).mkdir(parents=True, exist_ok=True)

model = YOLO(SEG)
crops = Counter()
photos_used = Counter()
for label in CLASSES:
    for _id in by_label[label]:
        jpg = SRC / f"{_id}.jpg"
        if not jpg.exists():
            continue
        img = Image.open(jpg).convert("RGB")
        W, H = img.size
        res = model.predict(str(jpg), conf=CONF, imgsz=640, verbose=False)[0]
        if res.boxes is None or len(res.boxes) == 0:
            continue
        sub = split[_id]
        photos_used[(sub, label)] += 1
        for i, box in enumerate(res.boxes.xyxy.cpu().numpy()):
            x0, y0, x1, y1 = box
            bw, bh = x1 - x0, y1 - y0
            cx0 = max(0, x0 - bw * PAD); cy0 = max(0, y0 - bh * PAD)
            cx1 = min(W, x1 + bw * PAD); cy1 = min(H, y1 + bh * PAD)
            if cx1 - cx0 < MIN_PX or cy1 - cy0 < MIN_PX:
                continue
            img.crop((cx0, cy0, cx1, cy1)).save(OUT / sub / label / f"{_id}_{i}.jpg", quality=92)
            crops[(sub, label)] += 1

print("\n=== crops per class ===")
for sub in ("train", "val"):
    tot = 0
    for c in CLASSES:
        n = crops[(sub, c)]
        tot += n
        print(f"  {sub:5s} {c:10s} {n:5d}  (from {photos_used[(sub, c)]} photos)")
    print(f"  {sub:5s} {'TOTAL':10s} {tot:5d}")
print(f"\nwrote {args.mode} dataset to {OUT}")
