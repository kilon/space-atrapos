#!/usr/bin/env python3
"""The Hydra (HydraBeast), the many-headed serpent of Lerna, a creature of the
monster signals, cut out of the reference art (external/images/hydra/) into
animatable parts - the pictures themselves, every line, shape and colour kept.

  hydra_top.png    from above: eight heads round a knot of coils - as it fights
  hydra_front.png  from the front, rearing out of the waves: its poison breath
  hydra_double_head.png  two heads on one neck: what grows where a head is cut

Steps: the flat purple background is cleared by colour - all of it that
reaches the picture's edge, and inside the holes of its coils only large
patches very close to it (the dark shadows between the coils are near that purple) - with soft
edges by colour distance; from the
top view each of the eight heads is cut along a polygon traced
on the art, plus every bit left outside the knot of coils nearest it (the
body runs OVERLAP px under each); the front view stays whole.

  data/sprites/monster_hydra_{body,head1..head8,front,double_head}.png
  data/sprites/monster_hydra.json   crop origins, pivots, mouths

Needs the art venv (opencv, numpy, pillow):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/hydra_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "hydra")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48
OVERLAP = 30
BG = np.array([68, 1, 73])        # the purple of the art's background
BG_NEAR = 26
BG_EDGE = 45                      # the purple round it (reaching the picture's edge)
BG_PATCH = 1500                   # px: a patch of background this big is a hole, not a shadow

# Traced on the top view (1536 x 1024), clockwise from the top: region polygon,
# the neck it swings at, its mouth (its bullets come from there).
PARTS = {
    "head1": {"region": [(640, 140), (680, 55), (760, 0), (810, 55), (860, 140), (870, 200), (815, 240), (800, 290), (775, 380),
                         (705, 380), (685, 300), (665, 240), (645, 200)], "pivot": (755, 130), "mouth": (740, 270)},
    "head2": {"region": [(1100, 190), (1110, 140), (1100, 65), (1170, 80), (1230, 110), (1250, 160), (1280, 210), (1295, 250), (1270, 280),
                         (1260, 320), (1270, 360), (1240, 350), (1220, 300), (1180, 280), (1140, 260), (1110, 230)], "pivot": (1110, 190), "mouth": (1235, 265)},
    "head3": {"region": [(1180, 375), (1260, 360), (1330, 370), (1380, 400), (1395, 470), (1425, 540), (1410, 580), (1395, 620), (1405, 690),
                         (1375, 680), (1360, 630), (1330, 610), (1300, 580), (1270, 540), (1230, 480), (1200, 440)], "pivot": (1210, 460), "mouth": (1350, 580)},
    "head4": {"region": [(880, 760), (930, 690), (990, 660), (1030, 660), (1070, 710), (1110, 800), (1070, 855), (1025, 875), (985, 905),
                         (965, 945), (905, 975), (860, 1005), (840, 985), (880, 940), (885, 880), (875, 820)], "pivot": (990, 720), "mouth": (930, 880)},
    "head5": {"region": [(595, 600), (650, 515), (710, 460), (770, 515), (820, 600), (830, 690), (800, 760), (790, 850), (775, 990),
                         (720, 990), (690, 900), (625, 840), (610, 760), (595, 700)], "pivot": (710, 560), "mouth": (715, 820)},
    "head6": {"region": [(340, 780), (370, 690), (420, 640), (470, 600), (530, 640), (560, 700), (560, 790), (540, 850), (530, 900),
                         (550, 985), (510, 1005), (465, 955), (435, 935), (415, 885), (385, 845), (350, 815)], "pivot": (460, 720), "mouth": (480, 880)},
    "head7": {"region": [(90, 530), (100, 490), (125, 440), (160, 380), (240, 355), (310, 365), (280, 420), (270, 470), (250, 520),
                         (220, 560), (200, 600), (185, 630), (160, 670), (125, 665), (120, 600), (95, 570)], "pivot": (280, 460), "mouth": (170, 560)},
    "head8": {"region": [(240, 180), (290, 110), (330, 90), (440, 55), (490, 70), (450, 130), (440, 200), (420, 240), (370, 290),
                         (320, 315), (300, 345), (265, 340), (260, 270), (245, 250)], "pivot": (430, 190), "mouth": (300, 265)},
}
HUB = (760, 520)                  # the knot of its coils
DOUBLE_MOUTHS = [(250, 560), (1290, 560)]   # the double head's two jaws (its own picture, 1536 x 1024)
DOUBLE_NECK = (765, 760)
ERODE = 13                        # px: bridges thinner than this between a head's bits and the coils are cut


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
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_hydra_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    top = cutout(os.path.join(ART, "hydra_top.png"))
    solid = top[..., 3] > 0
    meta = {"parts": {}, "heads": list(PARTS), "mouths": {n: p["mouth"] for n, p in PARTS.items()}, "hub": HUB, "size": [top.shape[1], top.shape[0]]}
    body = solid.copy()
    regions = {}
    for name, part in PARTS.items():
        regions[name] = poly_mask(top.shape, part["region"]) & solid
        body &= ~regions[name]
    # The polygons miss bits of the heads (crest spikes, snouts, tongues): the
    # body is only the knot of coils - the largest mass once thin bridges are
    # eroded away - and every other piece goes to the nearest head.
    k = np.ones((ERODE, ERODE), np.uint8)
    er = cv2.erode(body.astype(np.uint8), k)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(er, connectivity=4)
    core = labels == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    core = cv2.dilate(core.astype(np.uint8), k).astype(bool) & body
    n, labels, stats, cents = cv2.connectedComponentsWithStats((body & ~core).astype(np.uint8), connectivity=8)
    centres = {name: np.argwhere(r).mean(axis=0)[::-1] for name, r in regions.items()}
    for i in range(1, n):
        c = cents[i]
        near_head = min(centres, key=lambda h: np.hypot(*(centres[h] - c)))
        regions[near_head] |= labels == i
    body = core
    near = cv2.distanceTransform((~body).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
    for name, region in regions.items():
        save(top, region, name, meta)
        meta[name + "_pivot"] = list(PARTS[name]["pivot"])
        body |= region & near
    save(top, body, "body", meta)
    front = cutout(os.path.join(ART, "hydra_front.png"))
    save(front, front[..., 3] > 0, "front", meta)
    meta["front_size"] = [front.shape[1], front.shape[0]]
    # The double head: two heads on one neck, whole - what grows from a stump.
    double = cutout(os.path.join(ART, "hydra_double_head.png"))
    save(double, double[..., 3] > 0, "double_head", meta)
    meta["double_head_mouths"] = DOUBLE_MOUTHS
    meta["double_head_neck"] = DOUBLE_NECK
    with open(os.path.join(OUT, "monster_hydra.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
