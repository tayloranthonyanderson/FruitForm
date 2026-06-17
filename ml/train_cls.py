"""
Train the 4-class tomato shape classifier on the per-fruit crops, then export to
Core ML for the app. Fine-tunes ImageNet-pretrained YOLOv8n-cls.
"""
from pathlib import Path
from ultralytics import YOLO

import sys
HERE = Path(__file__).parent
DATA = str(HERE / "cls_ds_bal")
DEV = sys.argv[1] if len(sys.argv) > 1 else "mps"   # cls uses plain CE — MPS is fine

model = YOLO("yolov8n-cls.pt")
model.train(
    data=DATA,
    epochs=40,
    imgsz=224,
    batch=64,
    device=DEV,
    project=str(HERE / "runs"),
    name="tomato_cls_v1",
    exist_ok=True,         # overwrite in place so the export path stays stable
    patience=12,
    seed=42,
    fliplr=0.5, degrees=15, hsv_v=0.3, hsv_s=0.3,   # robustness to angle/lighting
)

best = YOLO(str(HERE / "runs/tomato_cls_v1/weights/best.pt"))

# Validate + print per-class so we see minority-class quality, not just top-1.
metrics = best.val(data=DATA, imgsz=224, device=DEV, split="val", verbose=True)
print("\ntop-1:", metrics.top1)

# Export to Core ML (no NMS — this is a classifier).
best.export(format="coreml", imgsz=224, nms=False, device=DEV)
print("exported Core ML to runs/tomato_cls_v1/weights/best.mlpackage")
