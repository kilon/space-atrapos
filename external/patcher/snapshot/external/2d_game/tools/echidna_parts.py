#!/usr/bin/env python3
"""Echidna (EchidnaBeast), the mother of monsters, a creature of the monster
signals, cut out of the reference art (external/images/echidna/) into
animatable parts - the pictures themselves, every line, shape and colour kept.

  echidna_top.png    from above, coiled: the creature as it fights
  echidna_front.png  from the front, rearing: shown when she calls her brood

Steps: the flat purple background is cleared by colour - all of it that
reaches the picture's edge, and inside the holes of her coils only large
patches very close to it (her dark hair is near that purple) - with soft
edges by colour distance; from the
top view both arms and the crescent of her tail are cut along polygons traced
on the art (the body runs OVERLAP px under each); the front view stays whole.

  data/sprites/monster_echidna_{body,left_arm,right_arm,tail,front}.png
  data/sprites/monster_echidna.json   crop origins, pivots, mouth, eyes

Needs the art venv (opencv, numpy, pillow):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/echidna_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "echidna")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48
OVERLAP = 30
BG = np.array([66, 2, 75])        # the purple of the art's background
BG_NEAR = 26
BG_EDGE = 45                      # the purple round her (reaching the picture's edge)
BG_PATCH = 1500                   # px: a patch of background this big is a hole, not a shadow in her hair

# Traced on the top view (1199 x 1312): region polygon and the joint it swings at.
PARTS = {
    "left_arm": {"region": [(400, 585), (470, 570), (500, 640), (430, 690), (360, 735), (310, 790), (335, 850), (325, 925),
                            (265, 905), (215, 885), (150, 885), (95, 925), (90, 880), (150, 800), (205, 765), (225, 690), (320, 635)],
                 "pivot": (455, 625)},
    "right_arm": {"region": [(760, 585), (835, 595), (860, 680), (905, 720), (1005, 780), (1015, 830), (1075, 880), (1085, 965),
                             (1030, 985), (975, 945), (950, 940), (925, 900), (885, 840), (860, 800), (815, 745), (775, 705), (755, 645)],
                  "pivot": (795, 630)},
    "tail": {"region": [(645, 100), (700, 40), (820, 5), (980, 5), (1100, 60), (1185, 200), (1199, 360), (1180, 520), (1130, 610),
                        (1060, 640), (990, 570), (930, 530), (905, 470), (960, 420), (1000, 330), (990, 220), (950, 130), (820, 85), (700, 100)],
             "pivot": (980, 480)},
}
MOUTH = (610, 610)
EYES = [(570, 545), (650, 545)]
HUB = (600, 760)                  # the middle of her (her waist)


def cutout(path) -> np.ndarray:
    orig = np.array(Image.open(path).convert("RGB"))
    d = np.sqrt(((orig.astype(int) - BG) ** 2).sum(axis=2))
    # The background: the purple reaching the picture's edge, and the large
    # patches of it closed in by her coils.
    n, labels, stats, _ = cv2.connectedComponentsWithStats((d < BG_EDGE).astype(np.uint8), connectivity=4)
    edge = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    bg = np.isin(labels, [i for i in edge if i != 0])
    n, labels, stats, _ = cv2.connectedComponentsWithStats((d < BG_NEAR).astype(np.uint8), connectivity=4)
    bg |= np.isin(labels, [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= BG_PATCH])
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    # Soft edges: along the border, by how far the colour is from the purple.
    rim = cv2.dilate(bg.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool) & ~bg
    alpha[rim] = np.clip((d[rim] - 15.0) / 40.0 * 255.0, 0, 255).astype(np.uint8)
    return np.dstack([orig, alpha])


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
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_echidna_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    top = cutout(os.path.join(ART, "echidna_top.png"))
    solid = top[..., 3] > 0
    meta = {"parts": {}, "mouth": MOUTH, "eyes": EYES, "hub": HUB, "size": [top.shape[1], top.shape[0]]}
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
    front = cutout(os.path.join(ART, "echidna_front.png"))
    save(front, front[..., 3] > 0, "front", meta)
    meta["front_size"] = [front.shape[1], front.shape[0]]
    with open(os.path.join(OUT, "monster_echidna.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
