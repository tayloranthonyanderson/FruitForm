"""Convert LaboroTomato COCO polygons -> single-class YOLO segmentation dataset."""
import json, os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "data" / "laboro_tomato"
DST = ROOT / "seg_ds"

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

    n_img = n_poly = 0
    for img_id, im in images.items():
        fn = im["file_name"]
        W, H = im["width"], im["height"]
        src_img = SRC / img_dir / fn
        if not src_img.exists():
            continue
        link = DST / "images" / split / fn
        if not link.exists():
            os.symlink(src_img, link)

        lines = []
        for a in anns_by_img.get(img_id, []):
            polys = a["segmentation"]
            if not isinstance(polys, list) or not polys:
                continue
            # pick the largest polygon piece for this instance
            poly = max(polys, key=len)
            if len(poly) < 6:        # need >= 3 points
                continue
            coords = []
            for i in range(0, len(poly) - 1, 2):
                x = min(max(poly[i] / W, 0.0), 1.0)
                y = min(max(poly[i + 1] / H, 0.0), 1.0)
                coords.append(f"{x:.6f} {y:.6f}")
            lines.append("0 " + " ".join(coords))
            n_poly += 1
        (DST / "labels" / split / (Path(fn).stem + ".txt")).write_text("\n".join(lines))
        n_img += 1
    print(f"{split}: {n_img} images, {n_poly} instance masks")

(DST / "data.yaml").write_text(
    f"path: {DST}\ntrain: images/train\nval: images/val\nnames:\n  0: tomato\n"
)
print("wrote", DST / "data.yaml")
