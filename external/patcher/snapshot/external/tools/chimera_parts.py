#!/usr/bin/env python3
"""The Chimera (ChimeraBeast), lion, goat and serpent in one beast, a creature
of the monster signals, cut out of the reference art (external/images/chimera/)
into animatable parts - the pictures themselves, every line, shape and colour
kept.

  chimera_top.png    from above, stalking toward you: the creature as it fights
  chimera_front.png  from the front, rearing: its rampage

Steps: the flat purple background is cleared by colour - all of it that
reaches the picture's edge, and inside the creature only large patches very
close to it - with soft edges by colour distance; from the top view the lion's
head, the goat's head, the serpent tail and three legs are cut along polygons
traced on the art, plus every bit left outside the body nearest them (the
body runs OVERLAP px under each); the front view stays whole.

  data/sprites/monster_chimera_{body,lion,goat,serpent,front_left_leg,front_right_leg,back_right_leg,front}.png
  data/sprites/monster_chimera.json   crop origins, pivots, mouths

Needs the art venv (opencv, numpy, pillow):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/chimera_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "chimera")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48
OVERLAP = 30
BG = np.array([68, 2, 78])        # the purple of the art's background
BG_NEAR = 26
BG_EDGE = 45                      # the purple round it (reaching the picture's edge)
BG_PATCH = 1500                   # px: a patch of background this big is a hole, not a shadow

# Traced on the top view (1536 x 1024): region polygon, the joint it moves at,
# and for the heads their mouths (their fire, embers and venom come from there).
PARTS = {
    "serpent": {"region": [(880, 120), (930, 40), (1010, 10), (1120, 15), (1190, 60), (1240, 150), (1260, 260), (1240, 340), (1210, 380),
                           (1195, 480), (1130, 490), (1130, 380), (1105, 320), (1100, 250), (1090, 160), (1040, 120), (990, 140), (970, 200),
                           (980, 290), (940, 310), (905, 280), (895, 200)], "pivot": (930, 290), "mouth": (1170, 365)},
    "goat": {"region": [(380, 330), (400, 250), (405, 180), (430, 130), (470, 100), (560, 90), (640, 130), (700, 170), (700, 230), (680, 280),
                        (640, 330), (620, 380), (580, 450), (560, 520), (520, 550), (470, 540), (440, 500), (420, 440), (385, 390)],
             "pivot": (620, 330), "mouth": (480, 470)},
    "lion": {"region": [(500, 560), (560, 470), (640, 440), (740, 430), (840, 440), (930, 480), (970, 560), (970, 640), (950, 720),
                        (900, 770), (850, 820), (830, 880), (790, 960), (740, 970), (690, 940), (640, 880), (580, 840), (530, 780),
                        (500, 700), (495, 620)], "pivot": (735, 520), "mouth": (740, 830)},
    "front_left_leg": {"region": [(285, 720), (310, 660), (330, 600), (360, 520), (400, 470), (450, 480), (460, 540), (430, 600), (410, 660),
                                  (410, 720), (400, 800), (360, 815), (310, 805), (285, 760)], "pivot": (430, 500)},
    "front_right_leg": {"region": [(855, 860), (880, 800), (900, 775), (960, 770), (995, 800), (995, 880), (985, 965), (940, 995), (880, 985),
                                   (855, 940)], "pivot": (930, 790)},
    "back_right_leg": {"region": [(1000, 520), (1050, 480), (1080, 520), (1115, 600), (1125, 675), (1080, 685), (1030, 665), (1010, 600)],
                       "pivot": (1020, 500)},
}
HUB = (760, 450)                  # the middle of its back
ERODE = 13                        # px: bridges thinner than this between a part's bits and the body are cut


def cutout(path) -> np.ndarray:
    orig = np.array(Image.open(path).convert("RGB"))
    d = np.sqrt(((orig.astype(int) - BG) ** 2).sum(axis=2))
    # The background: the purple reaching the picture's edge, and the large
    # patches of it closed in by its coils.
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
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_chimera_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    top = cutout(os.path.join(ART, "chimera_top.png"))
    solid = top[..., 3] > 0
    meta = {"parts": {}, "mouths": {n: p["mouth"] for n, p in PARTS.items() if "mouth" in p}, "hub": HUB, "size": [top.shape[1], top.shape[0]]}
    body = solid.copy()
    regions = {}
    for name, part in PARTS.items():
        regions[name] = poly_mask(top.shape, part["region"]) & solid
        body &= ~regions[name]
    # The polygons miss bits (claws, horn tips, a tongue): the body is only
    # its largest mass once thin bridges are eroded away - every other piece
    # goes to the nearest part.
    k = np.ones((ERODE, ERODE), np.uint8)
    er = cv2.erode(body.astype(np.uint8), k)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(er, connectivity=4)
    core = labels == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    core = cv2.dilate(core.astype(np.uint8), k).astype(bool) & body
    n, labels, stats, cents = cv2.connectedComponentsWithStats((body & ~core).astype(np.uint8), connectivity=8)
    centres = {name: np.argwhere(r).mean(axis=0)[::-1] for name, r in regions.items()}
    for i in range(1, n):
        c = cents[i]
        near_part = min(centres, key=lambda h: np.hypot(*(centres[h] - c)))
        regions[near_part] |= labels == i
    body = core
    near = cv2.distanceTransform((~body).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
    for name, region in regions.items():
        save(top, region, name, meta)
        meta[name + "_pivot"] = list(PARTS[name]["pivot"])
        body |= region & near
    save(top, body, "body", meta)
    front = cutout(os.path.join(ART, "chimera_front.png"))
    save(front, front[..., 3] > 0, "front", meta)
    meta["front_size"] = [front.shape[1], front.shape[0]]
    with open(os.path.join(OUT, "monster_chimera.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
