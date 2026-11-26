#!/usr/bin/env python3
"""Skylla, the sea witch (SeaWitch), cut out of the reference art into
animatable parts - the picture itself, every line, shape and colour kept.

  external/images/skylla/skylla_parts.png      the art: the upper body above,
                                               the tentacles below, apart
  external/images/skylla/skylla_assembled.png  how they go together (layout)

Steps: the background is removed with rembg's anime segmentation model
(isnet-anime); the two separate shapes are the upper body and the tentacle
cluster; each arm is cut from the body along polygons at the shoulder, and
again at the elbow (upper arm, forearm with the clawed hand). Written to
data/sprites/monster_skylla_<part>.png with data/sprites/monster_skylla.json:
for each part its crop's top-left in the art's pixels, plus the pivots
(shoulders, elbows), the tentacles' hub, the eyes, the mouth, and where the
tentacles go under her and how big (measured on the assembled picture).

Needs the art venv (rembg, opencv, scipy):
  ~/.local/share/space-atrapos-art/venv/bin/python tools/skylla_parts.py
"""
import json
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "external", "images", "skylla", "skylla_parts.png")
OUT = os.path.join(ROOT, "data", "sprites")
PAD = 48                       # transparent margin round each part (room for the shaders' sway)
OVERLAP = 30                   # px each piece runs on past its joint cut (no gaps when bending)

# Joints in the art's pixels (1536 x 1024), traced from it.
LEFT = {   # her right arm, on the left of the picture
    "region": [(250, 380), (480, 330), (560, 300), (612, 292), (668, 378), (610, 650), (240, 650)],
    "shoulder": (636, 330), "elbow": (548, 372), "cut": [(500, 300), (595, 445)],
}
RIGHT = {
    "region": [(1290, 380), (1100, 340), (1000, 300), (950, 292), (900, 380), (960, 650), (1300, 650)],
    "shoulder": (936, 335), "elbow": (1040, 392), "cut": [(1085, 320), (990, 465)],
}
EYES = [(775, 340), (829, 345)]
MOUTH = (800, 386)
TENTACLE_HUB = (790, 690)
# Where the tentacles go under her - measured on skylla_assembled.png: there
# the hub is 210 px below the crown's gem and the tentacles span 1480 px, the
# body (earring to earring) 1.13x the size it is here; so in this art's pixels
# the hub sits 186 px below the gem (800, 322) and the tentacles are 1.19x.
TENTACLE_AT = (804, 370)   # (then lowered onto them: her chest sits over the hub)
TENTACLE_SCALE = 1.19


def cutout() -> np.ndarray:
    from rembg import new_session, remove
    im = Image.open(ART).convert("RGB")
    rgba = np.array(remove(im, session=new_session("isnet-anime")))
    return rgba


def poly_mask(shape, pts) -> np.ndarray:
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [np.array(pts, np.int32)], 1)
    return m.astype(bool)


def side_of(shape, a, b, p) -> np.ndarray:
    """Pixels on the same side of the line a-b as point p."""
    h, w = shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    cross = (b[0] - a[0]) * (yy - a[1]) - (b[1] - a[1]) * (xx - a[0])
    ref = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
    return (cross > 0) == (ref > 0)


def save(rgba, mask, name, meta) -> None:
    ys, xs = np.nonzero(mask & (rgba[..., 3] > 0))
    x0, y0, x1, y1 = xs.min() - PAD, ys.min() - PAD, xs.max() + PAD + 1, ys.max() + PAD + 1
    part = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    sx0, sy0 = max(x0, 0), max(y0, 0)
    sx1, sy1 = min(x1, rgba.shape[1]), min(y1, rgba.shape[0])
    src = rgba[sy0:sy1, sx0:sx1].copy()
    src[~mask[sy0:sy1, sx0:sx1]] = 0
    part[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = src
    Image.fromarray(part, "RGBA").save(os.path.join(OUT, "monster_skylla_%s.png" % name))
    meta["parts"][name] = [int(x0), int(y0)]
    print(name, part.shape[1], "x", part.shape[0])


def main() -> None:
    rgba = cutout()
    solid = (rgba[..., 3] > 128).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(solid)
    big = sorted(range(1, n), key=lambda i: -st[i, 4])[:2]
    upper, lower = sorted(big, key=lambda i: st[i, 1])     # by top edge
    # Each part: its component, grown a little so the soft edge comes along.
    grow = lambda m: cv2.dilate(m.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
    body = grow(lab == upper)
    tent = grow(lab == lower) & ~body
    meta = {"parts": {}, "eyes": EYES, "mouth": MOUTH, "hub": TENTACLE_HUB, "tentacle_at": TENTACLE_AT, "tentacle_scale": TENTACLE_SCALE,
            "size": [rgba.shape[1], rgba.shape[0]]}
    save(rgba, tent, "tentacles", meta)
    # The joints overlap so bending them never opens a gap: each piece goes on
    # OVERLAP px past its cut (the forearm under the upper arm, the torso under
    # the arms), and the bend uncovers more of the same arm, not empty space.
    torso = body.copy()
    arms = poly_mask(rgba.shape, LEFT["region"]) | poly_mask(rgba.shape, RIGHT["region"])
    torso &= ~arms
    near_torso = cv2.distanceTransform((~torso).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
    for side, arm in (("left", LEFT), ("right", RIGHT)):
        region = poly_mask(rgba.shape, arm["region"]) & body
        upper_side = side_of(rgba.shape, arm["cut"][0], arm["cut"][1], arm["shoulder"])
        upper_arm = region & upper_side
        fore = region & ~upper_side
        near_upper = cv2.distanceTransform((~upper_arm).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
        near_fore = cv2.distanceTransform((~fore).astype(np.uint8), cv2.DIST_L2, 5) <= OVERLAP
        # (each gets the strip of the other within OVERLAP px of the cut)
        save(rgba, upper_arm | (fore & near_upper), side + "_upper", meta)
        save(rgba, fore | (upper_arm & near_fore), side + "_fore", meta)
        torso_ext = region & near_torso
        torso |= torso_ext
        meta[side + "_shoulder"] = list(arm["shoulder"])
        meta[side + "_elbow"] = list(arm["elbow"])
    save(rgba, torso & body, "torso", meta)
    with open(os.path.join(OUT, "monster_skylla.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
