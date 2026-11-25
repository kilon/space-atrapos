"""Semantic classes of the reference picture (ADE20K labels: sky, rock, water, waterfall, plant...).

  python -I semantic_segment.py <image> <out.npz> [model id]

Saves `labels` (H, W) uint8 class ids, `names` (the id -> name list) and `logits_small` for the
classes that matter. A starting point for the class map (classes.py refines it with colour and depth)."""
import sys
import numpy as np
import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForUniversalSegmentation

src, out = sys.argv[1], sys.argv[2]
model_id = sys.argv[3] if len(sys.argv) > 3 else "facebook/mask2former-swin-large-ade-semantic"
img = Image.open(src).convert("RGB")
proc = AutoImageProcessor.from_pretrained(model_id)
model = AutoModelForUniversalSegmentation.from_pretrained(model_id).eval()
inputs = proc(images=img, return_tensors="pt")
with torch.no_grad():
    o = model(**inputs)
seg = proc.post_process_semantic_segmentation(o, target_sizes=[img.size[::-1]])[0].cpu().numpy().astype(np.uint8)
names = [model.config.id2label[i] for i in range(len(model.config.id2label))]
np.savez_compressed(out, labels=seg, names=np.array(names))
ids, counts = np.unique(seg, return_counts=True)
for i, c in sorted(zip(ids, counts), key=lambda t: -t[1]):
    print(f"{i:4d} {names[i]:32s} {100 * c / seg.size:6.2f}%")
