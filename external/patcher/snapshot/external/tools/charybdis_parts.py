#!/usr/bin/env python3
"""Charybdis (CharybdisBeast), the whirlpool that swallows the sea, a creature
of the monster signals, cut out of the reference art
(external/images/charybdis/charybdis_top.png) - the picture itself, every line,
shape and colour kept. It stays whole: a shader turns its vortex and writhes
its tentacles (shaders/charybdis_whirl.gdshader).

Steps: the flat purple background is cleared by colour - all of it that
reaches the picture's edge, and inside only large patches very close to it -
with soft edges by colour distance.

  data/sprites/monster_charybdis.png
  data/sprites/monster_charybdis.json   crop origin, the vortex's centre, its radius, the maw's

Needs the art venv (opencv, numpy, pillow):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/charybdis_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "charybdis", "charybdis_top.png")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48
BG = np.array([68, 2, 78])
BG_NEAR = 26
BG_EDGE = 45
BG_PATCH = 1500
CENTRE = (766, 530)               # the eye of the vortex
VORTEX = 125                      # px: inside the teeth's tips - it turns
MAW = 255                         # px: the ring of teeth and gums
REACH = 580                       # px: the tips of its tentacles


def cutout(path) -> np.ndarray:
    orig = np.array(Image.open(path).convert("RGB"))
    d = np.sqrt(((orig.astype(int) - BG) ** 2).sum(axis=2))
    n, labels, stats, _ = cv2.connectedComponentsWithStats((d < BG_EDGE).astype(np.uint8), connectivity=4)
    edge = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    bg = np.isin(labels, [i for i in edge if i != 0])
    n, labels, stats, _ = cv2.connectedComponentsWithStats((d < BG_NEAR).astype(np.uint8), connectivity=4)
    bg |= np.isin(labels, [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= BG_PATCH])
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    rim = cv2.dilate(bg.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool) & ~bg
    alpha[rim] = np.clip((d[rim] - 15.0) / 40.0 * 255.0, 0, 255).astype(np.uint8)
    return np.dstack([orig, alpha])


def main() -> None:
    art = cutout(ART)
    ys, xs = np.nonzero(art[..., 3] > 0)
    x0, y0, x1, y1 = xs.min() - PAD, ys.min() - PAD, xs.max() + PAD + 1, ys.max() + PAD + 1
    part = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    sx0, sy0, sx1, sy1 = max(x0, 0), max(y0, 0), min(x1, art.shape[1]), min(y1, art.shape[0])
    part[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = art[sy0:sy1, sx0:sx1]
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_charybdis.png"))
    meta = {"origin": [int(x0), int(y0)], "size": [part.shape[1], part.shape[0]], "centre": CENTRE,
            "vortex": VORTEX, "maw": MAW, "reach": REACH}
    with open(os.path.join(OUT, "monster_charybdis.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("charybdis", part.shape[1], "x", part.shape[0])


if __name__ == "__main__":
    main()
