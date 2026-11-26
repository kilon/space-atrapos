#!/usr/bin/env python3
"""Cerberus (CerberusBeast), a creature of the monster signals, cut out of the
reference art (external/images/cerberus/cerberus.png) into animatable parts -
the picture itself, every line, shape and colour kept.

Steps: rembg's anime segmentation (isnet-anime) removes the background; the
golden background haze it kept inside the arc of the tail is removed (pixels
close to a smooth model of the background, there only); the tail, the two side
heads and the four legs are cut along polygons traced on the art, the body
running OVERLAP px under each joint so swinging them never opens a gap.

  data/sprites/monster_cerberus_{body,tail,left_head,right_head,
      left_leg,right_leg,front_left_leg,front_right_leg}.png
  data/sprites/monster_cerberus.json   crop origins, pivots, eyes, mouths

Needs the art venv (rembg, opencv, scipy):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/cerberus_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "cerberus", "cerberus.png")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48
OVERLAP = 30

# Parts traced on the art (1536 x 1024): region polygon and the joint it swings at.
PARTS = {
    "tail": {"region": [(480, 150), (520, 60), (600, 40), (700, 15), (800, 5), (900, 25), (985, 75), (1015, 150), (1012, 235),
                        (965, 235), (935, 150), (880, 92), (800, 62), (700, 72), (620, 102), (560, 132)], "pivot": (985, 225)},
    "left_head": {"region": [(305, 560), (300, 480), (330, 415), (380, 355), (470, 325), (545, 330), (580, 400), (565, 520),
                             (505, 600), (440, 655), (365, 655)], "pivot": (555, 470)},
    "right_head": {"region": [(1231, 560), (1236, 480), (1206, 415), (1156, 355), (1066, 325), (991, 330), (956, 400), (971, 520),
                              (1031, 600), (1096, 655), (1171, 655)], "pivot": (981, 470)},
    "left_leg": {"region": [(0, 450), (120, 415), (240, 430), (300, 520), (300, 660), (240, 830), (0, 830)], "pivot": (250, 470)},
    "right_leg": {"region": [(1536, 450), (1416, 415), (1296, 430), (1236, 520), (1236, 660), (1296, 830), (1536, 830)], "pivot": (1286, 470)},
    "front_left_leg": {"region": [(185, 1024), (485, 1024), (475, 830), (465, 700), (405, 655), (360, 700), (300, 800), (185, 900)],
                       "pivot": (430, 700)},
    "front_right_leg": {"region": [(1351, 1024), (1051, 1024), (1061, 830), (1071, 700), (1131, 655), (1176, 700), (1236, 800), (1351, 900)],
                        "pivot": (1106, 700)},
}
EYES = [(425, 470), (737, 535), (828, 535), (1110, 470)]
MOUTHS = {"left_head": (400, 575), "body": (790, 660), "right_head": (1170, 575)}   # the three jaws: his fire comes from them
HUB = (768, 560)


def cutout() -> np.ndarray:
    from rembg import new_session, remove
    orig = np.array(Image.open(ART).convert("RGB"))
    cut = np.array(remove(Image.fromarray(orig), session=new_session("isnet-anime")))
    solid = (cut[..., 3] > 0).astype(np.uint8)
    # The haze inside the tail's arc: close to the background (inpainted from
    # round it, blurred) and smooth - unlike the inked art.
    bgm = cv2.GaussianBlur(cv2.inpaint(orig, cv2.dilate(solid, np.ones((15, 15), np.uint8)), 25, cv2.INPAINT_TELEA), (0, 0), 20)
    diff = np.abs(orig.astype(int) - bgm.astype(int)).max(axis=2)
    g = cv2.cvtColor(orig, cv2.COLOR_RGB2GRAY).astype(np.float32)
    mu = cv2.blur(g, (9, 9))
    sd = np.sqrt(np.maximum(cv2.blur(g * g, (9, 9)) - mu * mu, 0))
    reg = np.zeros(solid.shape, np.uint8)
    cv2.fillPoly(reg, [np.array([(470, 150), (540, 120), (620, 95), (700, 70), (800, 55), (880, 85), (935, 140), (975, 215),
                                 (950, 240), (880, 200), (800, 170), (700, 165), (600, 185), (540, 215), (470, 220)], np.int32)], 1)
    haze = (reg > 0) & (diff < 60) & (sd < 12)
    haze = cv2.morphologyEx(haze.astype(np.uint8), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8)).astype(bool)
    cut[haze, 3] = 0
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
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_cerberus_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    rgba = cutout()
    solid = rgba[..., 3] > 0
    meta = {"parts": {}, "eyes": EYES, "mouths": MOUTHS, "hub": HUB, "size": [rgba.shape[1], rgba.shape[0]]}
    body = solid.copy()
    regions = {}
    for name, part in PARTS.items():
        regions[name] = poly_mask(rgba.shape, part["region"]) & solid
        body &= ~regions[name]
    near_body = cv2.distanceTransform((~body).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
    for name, region in regions.items():
        save(rgba, region, name, meta)
        meta[name + "_pivot"] = list(PARTS[name]["pivot"])
        if name != "tail":                     # (the tail goes behind the body: no fill needed)
            body |= region & near_body
    save(rgba, body, "body", meta)
    with open(os.path.join(OUT, "monster_cerberus.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
