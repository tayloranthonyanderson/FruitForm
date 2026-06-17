"""
Run the trained classifier over every *unique* crop (cls_ds, no duplicates),
group by the model's PREDICTION, and write an HTML performance report:
  report/index.html         -- summary + confusion matrices + links
  report/<class>.html       -- all crops predicted as <class>, errors first
  report/thumbs/...         -- 88px thumbnails referenced by the pages
"""
from pathlib import Path
from collections import Counter, defaultdict
import html
from PIL import Image
from ultralytics import YOLO

HERE = Path(__file__).parent
CLS = HERE / "cls_ds"            # ORIGINAL crops — no duplicates
OUT = HERE / "report"
THUMBS = OUT / "thumbs"
CLASSES = ["ROUND", "OVAL", "FLAT", "FASCIATED"]
THUMB = 88
DEV = "mps"

model = YOLO(str(HERE / "runs/tomato_cls_v1/weights/best.pt"))
order = [model.names[i] for i in range(len(model.names))]   # model's class order

# 1) Gather every unique crop with its human label + split.
items = []   # (path, true_label, split)
for split in ("train", "val"):
    for c in CLASSES:
        for f in sorted((CLS / split / c).glob("*.jpg")):
            items.append((f, c, split))
print(f"{len(items)} unique crops")

# 2) Predict in chunks.
preds = {}   # path -> (pred_label, conf)
B = 512
for i in range(0, len(items), B):
    chunk = [str(p) for p, _, _ in items[i:i + B]]
    for p, r in zip(items[i:i + B], model.predict(chunk, imgsz=224, device=DEV, verbose=False)):
        probs = r.probs
        preds[p[0]] = (order[int(probs.top1)], float(probs.top1conf))
    print(f"  predicted {min(i+B, len(items))}/{len(items)}")

# 3) Thumbnails + per-prediction buckets.
for c in CLASSES:
    (THUMBS / c).mkdir(parents=True, exist_ok=True)
buckets = defaultdict(list)   # pred_label -> list of dicts
conf_val = Counter(); conf_train = Counter()   # (true,pred) -> n
for path, true_label, split in items:
    pred, conf = preds[path]
    rel = f"thumbs/{pred}/{path.stem}.jpg"
    try:
        im = Image.open(path).convert("RGB")
        im.thumbnail((THUMB, THUMB))
        im.save(OUT / rel, quality=72)
    except Exception:
        continue
    buckets[pred].append(dict(rel=rel, true=true_label, pred=pred, conf=conf,
                              split=split, ok=(pred == true_label)))
    (conf_val if split == "val" else conf_train)[(true_label, pred)] += 1

# 4) HTML helpers.
CSS = """
<style>
 body{background:#111;color:#eee;font:14px -apple-system,Helvetica,Arial;margin:0;padding:20px}
 a{color:#6cf} h1,h2{font-weight:600}
 .grid{display:flex;flex-wrap:wrap;gap:4px;margin-top:10px}
 .cell{width:88px}
 .cell img{width:88px;height:88px;object-fit:cover;display:block;border:3px solid #2a2}
 .cell.bad img{border-color:#d33}
 .cap{font-size:10px;color:#aaa;line-height:1.2;margin-top:1px}
 .cap .t{color:#fff}
 table{border-collapse:collapse;margin:12px 0}
 td,th{border:1px solid #444;padding:6px 10px;text-align:center}
 th{background:#222} .diag{background:#163} .off{background:#411}
 .pill{display:inline-block;background:#222;border-radius:10px;padding:2px 8px;margin:2px;font-size:12px}
</style>
"""

def matrix_html(counts, title):
    rows = "".join(
        "<tr><th>%s</th>%s</tr>" % (
            t, "".join(
                "<td class='%s'>%d</td>" % ("diag" if t == p else ("off" if counts[(t, p)] else ""), counts[(t, p)])
                for p in order))
        for t in order)
    head = "".join("<th>%s</th>" % p for p in order)
    total = sum(counts.values()); correct = sum(counts[(c, c)] for c in order)
    acc = correct / total if total else 0
    return (f"<h2>{title} — acc {acc:.1%} (n={total})</h2>"
            f"<table><tr><th>true \\ pred</th>{head}</tr>{rows}</table>")

# 5) Per-class gallery pages (errors first, then lowest confidence).
for c in CLASSES:
    rows = sorted(buckets[c], key=lambda d: (d["ok"], d["conf"]))   # mismatches + low-conf first
    n = len(rows); wrong = sum(1 for d in rows if not d["ok"])
    cells = []
    for d in rows:
        cls = "cell" if d["ok"] else "cell bad"
        cap = f"<div class='cap'>{d['conf']:.2f} · <span class='t'>{d['true']}</span> · {d['split']}</div>"
        cells.append(f"<div class='{cls}'><img loading='lazy' src='{html.escape(d['rel'])}'>{cap}</div>")
    page = (f"<html><head><meta charset='utf-8'>{CSS}</head><body>"
            f"<p><a href='index.html'>← report</a></p>"
            f"<h1>Predicted: {c}</h1>"
            f"<p>{n} crops · <b>{wrong}</b> disagree with the human label "
            f"(red border). Sorted: disagreements + lowest-confidence first. "
            f"Precision here = {(n-wrong)/n:.1%} vs human labels.</p>"
            f"<div class='grid'>{''.join(cells)}</div></body></html>")
    (OUT / f"{c}.html").write_text(page)

# 6) Index.
pills = " ".join(f"<a class='pill' href='{c}.html'>{c}: {len(buckets[c])}</a>" for c in CLASSES)
index = (f"<html><head><meta charset='utf-8'>{CSS}</head><body>"
         f"<h1>Tomato shape model — visual report</h1>"
         f"<p>{len(items)} unique crops, grouped by the <b>model's prediction</b>. "
         f"Green border = matches your label, red = disagrees. Each thumb shows "
         f"confidence · your-label · train/val. <b>val</b> crops are the honest test "
         f"(the model never trained on them); <b>train</b> predictions are optimistic.</p>"
         f"<p>{pills}</p>"
         f"{matrix_html(conf_val, 'VAL (held-out — honest)')}"
         f"{matrix_html(conf_train, 'TRAIN (optimistic)')}"
         f"</body></html>")
(OUT / "index.html").write_text(index)
print("report ->", OUT / "index.html")
