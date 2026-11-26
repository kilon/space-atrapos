#!/usr/bin/env python3
"""Cetus (CetusBeast), the sea monster of the monster signals, cut out of the
reference art (external/images/cetus/) into animatable parts - the pictures
themselves, every line, shape and colour kept.

  cetus_top.png   top view, head to the left: the creature as it swims
  cetus_side.png  side view: shown when it breaches out of the void

Steps: rembg's anime segmentation (isnet-anime) removes the background, and
the deep purple background left inside the loops of spray is cleared by colour;
from the top view the two pectoral fins and the tail fin are cut along polygons
traced on the art (the body runs OVERLAP px under each), the rest is the body,
which a shader bends as it swims; the side view stays whole.

  data/sprites/monster_cetus_{body,fin_top,fin_bottom,tail,side}.png
  data/sprites/monster_cetus.json   crop origins, pivots, mouth, eyes

Needs the art venv (rembg, opencv, scipy):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/cetus_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "cetus")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48
OVERLAP = 30
BG = np.array([63, 1, 78])        # the deep purple of the art's background

PARTS = {
    "fin_top": {"region": [(410, 190), (430, 120), (520, 40), (700, 5), (915, 15), (780, 110), (640, 200), (600, 250), (560, 272), (470, 262)],
                "pivot": (520, 245)},
    "fin_bottom": {"region": [(410, 697), (430, 767), (520, 847), (700, 882), (915, 872), (780, 777), (640, 687), (600, 637), (560, 615), (470, 625)],
                   "pivot": (520, 642)},
    "tail": {"region": [(1450, 330), (1540, 160), (1774, 120), (1774, 760), (1560, 720), (1450, 560)], "pivot": (1470, 443)},
}
MOUTH = (40, 435)
EYES = [(255, 345), (255, 525)]
HUB = (800, 443)                  # the middle of the body
HEAD_X = 30                       # the snout (bending starts behind it)


def cutout(path) -> np.ndarray:
    from rembg import new_session, remove
    orig = np.array(Image.open(path).convert("RGB"))
    cut = np.array(remove(Image.fromarray(orig), session=new_session("isnet-anime")))
    bg = np.sqrt(((orig.astype(int) - BG) ** 2).sum(axis=2)) < 48
    cut[bg, 3] = 0
    cut[..., :3] = orig
    return cut


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
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_cetus_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    top = cutout(os.path.join(ART, "cetus_top.png"))
    solid = top[..., 3] > 0
    meta = {"parts": {}, "mouth": MOUTH, "eyes": EYES, "hub": HUB, "head_x": HEAD_X, "size": [top.shape[1], top.shape[0]]}
    body = solid.copy()
    regions = {}
    for name, part in PARTS.items():
        regions[name] = poly_mask(top.shape, part["region"]) & solid
        body &= ~regions[name]
    near = cv2.distanceTransform((~body).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
    for name, region in regions.items():
        save(top, region, name, meta)
        meta[name + "_pivot"] = list(PARTS[name]["pivot"])
        body |= region & near
    save(top, body, "body", meta)
    side = cutout(os.path.join(ART, "cetus_side.png"))
    save(side, side[..., 3] > 0, "side", meta)
    meta["side_size"] = [side.shape[1], side.shape[0]]
    with open(os.path.join(OUT, "monster_cetus.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
