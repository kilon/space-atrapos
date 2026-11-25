"""The sky's layout guide: analysis/cloud_guide.png.

  python -I make_cloud_guide.py

A quarter-size, blurred picture of the sky only (418 x 130: the picture's rows 0-520), with the land,
the planet and the moons filled in from the sky around them. RGB = the sky's colour there, A = how
much cloud / haze covers the planet (0 over the planet's disc, rising to 1 where its lower limb sinks
into the haze; 1 everywhere else). It says WHERE the cloud masses, the glow and the colours are; the
cloud part warps and breaks it up with procedural noise for the detail."""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cvlib

ROWS, STEP = 520, 4
ref = np.asarray(Image.open(cvlib.REFERENCE).convert("RGB")).astype(np.float64) / 255
sky = np.asarray(Image.open(os.path.join(cvlib.ANALYSIS, "sky.png")).convert("L")) > 127
pj = json.load(open(os.path.join(cvlib.ANALYSIS, "planet.json")))
v, u = np.mgrid[0:cvlib.H, 0:cvlib.W] + 0.5
P = pj["planet"]
dp = np.hypot(u - P["cx"], v - P["cy"])
disc = dp < P["r"] + 3
valid = sky & ~disc
for m in pj["moons"]:
    valid &= np.hypot(u - m["cx"], v - m["cy"]) > m["r"] + 3
valid = ndi.binary_erosion(valid, iterations=2)
# fill everything else from the nearest valid sky, then blur the fill
idx = ndi.distance_transform_edt(~valid, return_distances=False, return_indices=True)
fill = ref[idx[0], idx[1]]
soft = np.stack([ndi.gaussian_filter(fill[..., c], 14) for c in range(3)], -1)
dist = ndi.distance_transform_edt(~valid)
w = np.clip(dist / 10.0, 0, 1)[..., None]
img = fill * (1 - w) + soft * w
img = np.stack([ndi.gaussian_filter(img[..., c], 2.2) for c in range(3)], -1)
alpha = np.where(dp < P["r"], np.clip((v - 330) / 45.0, 0, 1) * np.clip((P["r"] - dp) / 6 + 1, 0, 1), 1.0)
alpha = np.where(disc & (dp >= P["r"]), np.maximum(alpha, 0.0), alpha)
alpha[~disc] = 1.0
for m in pj["moons"]:
    alpha[np.hypot(u - m["cx"], v - m["cy"]) < m["r"] + 1] = 0.0
alpha = ndi.gaussian_filter(alpha, 2.0)
out = np.concatenate([img, alpha[..., None]], -1)[:ROWS]
small = out[STEP // 2::STEP, STEP // 2::STEP]
Image.fromarray((np.clip(small, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(cvlib.ANALYSIS, "cloud_guide.png"))
print("cloud_guide.png", small.shape)
