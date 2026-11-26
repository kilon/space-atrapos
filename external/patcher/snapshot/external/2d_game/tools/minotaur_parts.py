#!/usr/bin/env python3
"""The Minotaur (MinotaurBoss), the main quest's guardian of the Labyrinth, cut
out of the reference art (external/images/minotaur/minotaur.png) into
animatable parts - the picture itself, every line, shape and colour kept.

Steps: rembg's anime segmentation (isnet-anime) removes the black background;
enclosed areas it dropped (the starfield inside the gold ring, the gems) are
put back unless they're the pure-black background; each arm and the kicking
leg are cut from the body along polygons traced on the art - the red cape
behind them stays with the body - each running OVERLAP px under the body at its
joint, so swinging them never opens a gap. Also written: a cape mask (where the
red cape is, softened) that shaders/minotaur_cape.gdshader ripples.

  data/sprites/monster_minotaur_{body,left_arm,right_arm,left_leg}.png
  data/masks/monster_minotaur_cape.png  the cape mask
  data/sprites/monster_minotaur.json   crop origins, pivots, eyes, crest gem

Needs the art venv (rembg, opencv, scipy):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/minotaur_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "minotaur", "minotaur.png")
OUT = os.path.join(ROOT, "data", "sprites")
MASKS = os.path.join(ROOT, "data", "masks")   # (not sprites: masks for the shaders)
PAD = 48
OVERLAP = 30

# Limbs, traced on the art (1254 x 1254): the region, the joint it swings at,
# and where red cape pixels inside the region stay with the body (x/y limits).
LIMBS = {
    "left_arm": {"region": [(392, 236), (425, 330), (385, 505), (305, 565), (318, 745), (0, 745), (0, 410), (55, 300), (250, 226)],
                 "pivot": (400, 330), "cape": lambda x, y: (x < 255) & (y < 425)},
    "right_arm": {"region": [(775, 700), (880, 688), (1082, 700), (1095, 1060), (1065, 1254), (655, 1254), (676, 958), (788, 878), (758, 760)],
                  "pivot": (885, 720), "cape": lambda x, y: x > 1048},
    "left_leg": {"region": [(468, 742), (522, 800), (502, 980), (382, 1100), (282, 1215), (128, 1215), (138, 1078), (228, 878), (296, 768)],
                 "pivot": (470, 790), "cape": lambda x, y: (y < 885) & (x < 452)},
}
EYES = [(583, 500), (690, 512)]
CREST = (660, 447)                 # the blue gem on his helmet: his attacks come from it
HUB = (620, 640)                   # his centre (chest)


def cutout() -> np.ndarray:
    from rembg import new_session, remove
    orig = np.array(Image.open(ART).convert("RGB"))
    cut = np.array(remove(Image.fromarray(orig), session=new_session("isnet-anime")))
    a = cut[..., 3]
    solid = (a > 40).astype(np.uint8)
    _, lab = cv2.connectedComponents(1 - solid)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bg = np.isin(lab, border) & (solid == 0)
    holes = ~bg & (solid == 0) & (orig.max(axis=2) >= 14)
    out = cut.copy()
    out[..., :3] = orig
    out[..., 3] = np.where(holes | (~bg & (a > 40)), 255, a)
    return out


def red_mask(rgba: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(np.ascontiguousarray(rgba[..., :3]), cv2.COLOR_RGB2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return ((h < 8) | (h > 170)) & (s > 110) & (v > 60)


def poly_mask(shape, pts) -> np.ndarray:
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [np.array(pts, np.int32)], 1)
    return m.astype(bool)


def save(rgba, mask, name, meta) -> None:
    ys, xs = np.nonzero(mask & (rgba[..., 3] > 0))
    x0, y0, x1, y1 = xs.min() - PAD, ys.min() - PAD, xs.max() + PAD + 1, ys.max() + PAD + 1
    part = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    sx0, sy0 = max(x0, 0), max(y0, 0)
    sx1, sy1 = min(x1, rgba.shape[1]), min(y1, rgba.shape[0])
    src = rgba[sy0:sy1, sx0:sx1].copy()
    src[~mask[sy0:sy1, sx0:sx1]] = 0
    part[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = src
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_minotaur_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    rgba = cutout()
    h, w = rgba.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    solid = rgba[..., 3] > 0
    red = red_mask(rgba)
    meta = {"parts": {}, "eyes": EYES, "crest": CREST, "hub": HUB, "size": [w, h]}
    body = solid.copy()
    limbs = {}
    for name, limb in LIMBS.items():
        region = poly_mask(rgba.shape, limb["region"]) & solid & ~(red & limb["cape"](xx, yy))
        limbs[name] = region
        body &= ~region
    near_body = cv2.distanceTransform((~body).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
    for name, region in limbs.items():
        save(rgba, region, name, meta)
        meta[name + "_pivot"] = list(LIMBS[name]["pivot"])
        body |= region & near_body                 # (the body runs on under each limb)
    save(rgba, body, "body", meta)
    # The cape mask, same crop as the body: the red cape outside the kilt,
    # softened so the ripple fades in from where it hangs.
    cape = red & body & ((xx < 330) | (xx > 980) | ((yy > 640) & (xx < 460)))
    soft = cv2.GaussianBlur(cv2.dilate(cape.astype(np.uint8) * 255, np.ones((9, 9), np.uint8)), (0, 0), 6)
    x0, y0 = meta["parts"]["body"]
    bw, bh = Image.open(os.path.join(OUT, "monster_minotaur_body.png")).size
    m = np.zeros((bh, bw), np.uint8)
    sx0, sy0 = max(x0, 0), max(y0, 0)
    sx1, sy1 = min(x0 + bw, w), min(y0 + bh, h)
    m[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = soft[sy0:sy1, sx0:sx1]
    os.makedirs(MASKS, exist_ok=True)
    Image.fromarray(m, "L").save(os.path.join(MASKS, "monster_minotaur_cape.png"))
    with open(os.path.join(OUT, "monster_minotaur.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
