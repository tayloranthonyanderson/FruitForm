"""Convert LaboroTomato COCO -> single-class YOLO detection dataset."""
import json, os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "data" / "laboro_tomato"
DST = ROOT / "yolo_ds"

splits = {"train": ("train", SRC / "annotations" / "train.json"),
          "val":   ("test",  SRC / "annotations" / "test.json")}

for split, (img_dir, ann_path) in splits.items():
    (DST / "images" / split).mkdir(parents=True, exist_ok=True)
    (DST / "labels" / split).mkdir(parents=True, exist_ok=True)
    coco = json.load(open(ann_path))
    images = {im["id"]: im for im in coco["images"]}
    anns_by_img = {}
    for a in coco["annotations"]:
        anns_by_img.setdefault(a["image_id"], []).append(a)

    n_img = n_box = 0
    for img_id, im in images.items():
        fn = im["file_name"]
        W, H = im["width"], im["height"]
        src_img = SRC / img_dir / fn
        if not src_img.exists():
            continue
        # symlink image (avoids duplicating 1.5GB)
        link = DST / "images" / split / fn
        if not link.exists():
            os.symlink(src_img, link)
        # write label file (single class 0)
        lines = []
        for a in anns_by_img.get(img_id, []):
            x, y, w, h = a["bbox"]
            if w <= 0 or h <= 0:
                continue
            xc, yc = (x + w / 2) / W, (y + h / 2) / H
            lines.append(f"0 {xc:.6f} {yc:.6f} {w/W:.6f} {h/H:.6f}")
            n_box += 1
        (DST / "labels" / split / (Path(fn).stem + ".txt")).write_text("\n".join(lines))
        n_img += 1
    print(f"{split}: {n_img} images, {n_box} boxes")

(DST / "data.yaml").write_text(
    f"path: {DST}\ntrain: images/train\nval: images/val\nnames:\n  0: tomato\n"
)
print("wrote", DST / "data.yaml")
