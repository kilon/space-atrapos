"""Monocular depth for the reference picture (relative inverse depth, affine-invariant).

  python -I depth_estimate.py <image> <out.npy> [model id]

Uses the transformers depth-estimation models (weights from the Hugging Face hub, safetensors).
The output is float32 (H, W): larger = nearer (disparity-like), not metric - calibrate.py turns it
into distances using the flat water as the ruler."""
import sys
import numpy as np
import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForDepthEstimation

src, out = sys.argv[1], sys.argv[2]
model_id = sys.argv[3] if len(sys.argv) > 3 else "depth-anything/Depth-Anything-V2-Small-hf"
img = Image.open(src).convert("RGB")
W, H = img.size
proc = AutoImageProcessor.from_pretrained(model_id)
model = AutoModelForDepthEstimation.from_pretrained(model_id).eval()
# Run at a higher resolution than the default 518 px for finer relief (multiple of the 14 px patch).
long_side = int(sys.argv[4]) if len(sys.argv) > 4 else 1218
scale = long_side / max(W, H)
h, w = int(round(H * scale / 14)) * 14, int(round(W * scale / 14)) * 14
inputs = proc(images=img, return_tensors="pt", do_resize=True, size={"height": h, "width": w},
              keep_aspect_ratio=False)
with torch.no_grad():
    pred = model(**inputs).predicted_depth          # (1, h', w')
pred = torch.nn.functional.interpolate(pred[None], size=(H, W), mode="bicubic", align_corners=False)[0, 0]
d = pred.cpu().numpy().astype(np.float32)
np.save(out, d)
print("saved", out, d.shape, "min", float(d.min()), "max", float(d.max()), "input", (h, w))
