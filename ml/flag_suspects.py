"""
Non-destructive: flag likely-contaminant crops in each class (green/leaf by color,
or shape-outlier by the model) and write a review collage. Removes nothing — emits
report/suspects.html + suspects.json (the removal list to act on after you review).
"""
from pathlib import Path
from collections import defaultdict
import json, html, colorsys
from PIL import Image
from ultralytics import YOLO

HERE = Path(__file__).parent
CLS = HERE / "cls_ds"
OUT = HERE / "report"
TH = OUT / "suspect_thumbs"
CLASSES = ["ROUND", "OVAL", "FLAT", "FASCIATED"]
SIZE = 120

model = YOLO(str(HERE / "runs/tomato_cls_v1/weights/best.pt"))
order = [model.names[i] for i in range(len(model.names))]

def green_score(im):
    """Fraction of saturated pixels whose hue is green (leaf / unripe)."""
    s = im.resize((48, 48)).convert("RGB")
    px = list(s.getdata()); green = 0; sat_n = 0
    for r, g, b in px:
        h, sa, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if sa > 0.25 and v > 0.15:
            sat_n += 1
            if 0.18 < h < 0.45:      # ~65°–160° = green
                green += 1
    return green / sat_n if sat_n else 0.0

# Review TRAIN crops (those that actually trained the model); val too for completeness.
items = [(f, c, sp) for sp in ("train", "val") for c in CLASSES
         for f in sorted((CLS / sp / c).glob("*.jpg"))]

for c in CLASSES:
    (TH / c).mkdir(parents=True, exist_ok=True)

suspects = defaultdict(list)
B = 512
preds = {}
for i in range(0, len(items), B):
    chunk = [str(p) for p, _, _ in items[i:i + B]]
    for (p, c, sp), r in zip(items[i:i + B], model.predict(chunk, imgsz=224, device="mps", verbose=False)):
        preds[p] = (order[int(r.probs.top1)], float(r.probs.top1conf))

    # Shape "families": round↔oval is a fuzzy boundary (NOT contamination), so we
    # only flag a crop whose model-predicted shape is in a *different family* than
    # its assigned label — e.g. a small round fruit that strayed into a fasciated tray.
FAMILY = {"ROUND": "smooth", "OVAL": "smooth", "FLAT": "flat", "FASCIATED": "lumpy"}

for path, c, sp in items:
    im = Image.open(path).convert("RGB")
    gs = green_score(im)
    pred, conf = preds[path]
    reasons = []
    if gs > 0.5:                              # mostly green → likely leaf/unripe stray
        reasons.append(f"green {gs:.0%}")
    if FAMILY[pred] != FAMILY[c] and conf > 0.60:   # cross-family → likely a stray
        reasons.append(f"looks {pred} {conf:.0%}")
    if not reasons:
        continue
    rel = f"suspect_thumbs/{c}/{path.stem}.jpg"
    t = im.copy(); t.thumbnail((SIZE, SIZE)); t.save(OUT / rel, quality=80)
    suspects[c].append(dict(path=str(path), rel=rel, reasons=", ".join(reasons),
                            green=gs, split=sp))

CSS = """<style>body{background:#111;color:#eee;font:14px -apple-system,Arial;margin:0;padding:22px}
a{color:#6cf}h2{margin:22px 0 6px;border-bottom:1px solid #333;padding-bottom:4px}
.grid{display:flex;flex-wrap:wrap;gap:8px}.cell{width:120px}
.cell img{width:120px;height:120px;object-fit:cover;border:3px solid #d33;border-radius:6px}
.cap{font-size:10px;color:#f99;margin-top:2px}</style>"""

secs = []
total = 0
for c in CLASSES:
    rows = sorted(suspects[c], key=lambda d: -d["green"])
    total += len(rows)
    cells = "".join(
        f"<div class='cell'><img src='{html.escape(d['rel'])}'>"
        f"<div class='cap'>{d['reasons']} · {d['split']}</div></div>" for d in rows)
    secs.append(f"<h2>{c} — {len(rows)} suspect crops</h2><div class='grid'>{cells}</div>")

page = (f"<html><head><meta charset='utf-8'>{CSS}</head><body>"
        f"<p><a href='index.html'>← report</a></p><h1>Suspect crops (review before removal)</h1>"
        f"<p>{total} flagged as green/leaf or shape-outliers. Nothing deleted yet — "
        f"this is the removal candidate list (suspects.json).</p>{''.join(secs)}</body></html>")
(OUT / "suspects.html").write_text(page)
json.dump({c: [d["path"] for d in suspects[c]] for c in CLASSES},
          open(OUT / "suspects.json", "w"), indent=1)
print("flagged:", {c: len(suspects[c]) for c in CLASSES}, "total", total)
print("review ->", OUT / "suspects.html")
