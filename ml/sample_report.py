"""
Collage of the model on UNSEEN fruit: random sample of val-only crops, grouped by
the model's predicted shape. Writes report/samples.html and links it from index.
"""
from pathlib import Path
from collections import defaultdict
import random, html
from PIL import Image
from ultralytics import YOLO

HERE = Path(__file__).parent
CLS = HERE / "cls_ds"
OUT = HERE / "report"
TH = OUT / "sample_thumbs"
CLASSES = ["ROUND", "OVAL", "FLAT", "FASCIATED"]
PER_CLASS = 18
SIZE = 150
random.seed(7)

model = YOLO(str(HERE / "runs/tomato_cls_v1/weights/best.pt"))
order = [model.names[i] for i in range(len(model.names))]

# val crops only
items = [(f, c) for c in CLASSES for f in sorted((CLS / "val" / c).glob("*.jpg"))]
print(f"{len(items)} val crops")

buckets = defaultdict(list)
B = 512
for i in range(0, len(items), B):
    chunk = [str(p) for p, _ in items[i:i + B]]
    for (p, true), r in zip(items[i:i + B], model.predict(chunk, imgsz=224, device="mps", verbose=False)):
        buckets[order[int(r.probs.top1)]].append((p, true, float(r.probs.top1conf)))

for c in CLASSES:
    (TH / c).mkdir(parents=True, exist_ok=True)

CSS = """
<style>
 body{background:#111;color:#eee;font:15px -apple-system,Helvetica,Arial;margin:0;padding:24px}
 a{color:#6cf} h1{font-weight:600}
 h2{font-weight:600;margin:26px 0 6px;border-bottom:1px solid #333;padding-bottom:4px}
 .grid{display:flex;flex-wrap:wrap;gap:8px}
 .cell{width:150px}
 .cell img{width:150px;height:150px;object-fit:cover;border:3px solid #2a2;border-radius:6px;display:block}
 .cell.bad img{border-color:#d33}
 .cap{font-size:11px;color:#bbb;margin-top:2px}.cap .t{color:#fff}
</style>
"""

sections = []
for c in CLASSES:
    pool = buckets.get(c, [])
    pick = random.sample(pool, min(PER_CLASS, len(pool)))
    cells = []
    for (p, true, conf) in pick:
        rel = f"sample_thumbs/{c}/{p.stem}.jpg"
        im = Image.open(p).convert("RGB"); im.thumbnail((SIZE * 2, SIZE * 2))
        w, h = im.size; s = min(w, h)
        im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((SIZE, SIZE))
        im.save(OUT / rel, quality=85)
        ok = (true == c)
        cells.append(f"<div class='cell{'' if ok else ' bad'}'><img src='{html.escape(rel)}'>"
                     f"<div class='cap'>{conf:.2f} · <span class='t'>{true}</span></div></div>")
    sections.append(f"<h2>Predicted {c} — {len(pick)} of {len(pool)} unseen</h2>"
                    f"<div class='grid'>{''.join(cells)}</div>")

page = (f"<html><head><meta charset='utf-8'>{CSS}</head><body>"
        f"<p><a href='index.html'>← report</a></p>"
        f"<h1>Model on unseen fruit (val only)</h1>"
        f"<p>Random sample grouped by the model's prediction. Caption = confidence · "
        f"your label. Red border = the model disagreed with your label.</p>"
        f"{''.join(sections)}</body></html>")
(OUT / "samples.html").write_text(page)

# Add a prominent link at the top of index.html (once).
idx = OUT / "index.html"; t = idx.read_text()
banner = "<p style='font-size:16px'>👉 <a href='samples.html'><b>Sample collage — model on unseen fruit</b></a></p>"
if "samples.html" not in t:
    t = t.replace("</h1>", "</h1>" + banner, 1)
    idx.write_text(t)
print("wrote", OUT / "samples.html")
