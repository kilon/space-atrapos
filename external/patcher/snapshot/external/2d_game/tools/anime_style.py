#!/usr/bin/env python3
"""80s-anime look for the game's sprites (after the exhaust-trail reference sheet's
jets): bold dark outlines, cel shading in a few flat tones, livelier colours and a
bright rim along the edges facing the light (top left) - the designs themselves
stay as they are.

The untouched PNGs are kept in external/sprite_originals/ (copied there the first
time a sprite is styled); data/sprites/<key>.png is always made from that copy, so
running this again (or with other settings) never compounds.

  python3 tools/anime_style.py              -> ships, stations, citizens
  python3 tools/anime_style.py ship_player  -> just those keys
  python3 tools/anime_style.py --restore    -> put the originals back
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "data", "sprites")
ORIGINALS = os.path.join(ROOT, "external", "sprite_originals")
PREFIXES = ("ship_", "station_", "npc_")

OUTLINE = np.array([0.04, 0.05, 0.11])        # the ink: a deep navy
LEVELS = 4                                     # cel tones
CEL_MIX = 0.85                                 # how much of the flat tones (the rest: the original detail)
SIMPLIFY = 0.6                                 # how much fine surface detail is smoothed away first
SATURATION = 1.38
RIM = 0.38                                     # the light rim's strength


def _shift(a, dx, dy):
    """a shifted by (dx, dy), zero-filled."""
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    out[yd, xd] = a[ys, xs]
    return out


def _dilate(mask, r):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r + 0.5 and (dx or dy):
                out |= _shift(mask, dx, dy)
    return out


def style(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    h, w = alpha.shape
    solid = alpha > 0.5
    # Flatter panels: smooth away fine surface noise (within the silhouette).
    blur = rgb.copy()
    for _ in range(2):
        acc = np.zeros_like(blur)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                acc += _shift(blur, dx, dy)
        blur = acc / 9.0
    rgb = np.where(solid[..., None], rgb * (1.0 - SIMPLIFY) + blur * SIMPLIFY, rgb)
    # Cel shading: luminance snapped to a few flat tones, colour kept.
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    q = np.clip(np.round(lum * LEVELS) / LEVELS, 0.06, 1.0)
    cel = np.clip(rgb * (q / np.maximum(lum, 0.02))[..., None], 0.0, 1.0)
    rgb = rgb * (1.0 - CEL_MIX) + cel * CEL_MIX
    # Livelier colours: more saturation, a touch more contrast.
    grey = (rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    rgb = np.clip(grey + (rgb - grey) * SATURATION, 0.0, 1.0)
    rgb = np.clip((rgb - 0.5) * 1.08 + 0.5, 0.0, 1.0)
    # Line width in texture pixels: about 2.5 px at the size the sprite is shown.
    k = max(2, int(round(max(w, h) / 75.0)))
    # The rim: a bright band along the edges facing the light (top left).
    lit_edge = solid & ~_shift(solid, k, k)
    rgb = np.where(lit_edge[..., None], rgb + (1.0 - rgb) * RIM, rgb)
    # Inner ink: a dark line just inside the silhouette.
    inner = solid & ~(_shift(solid, 1, 0) & _shift(solid, -1, 0) & _shift(solid, 0, 1) & _shift(solid, 0, -1))
    rgb = np.where(inner[..., None], rgb * 0.35 + OUTLINE * 0.65, rgb)
    # The bold outline: the silhouette grown by k px, in ink, under the sprite.
    grown = _dilate(solid, k)
    ring = grown & ~solid
    out = np.zeros((h, w, 4), dtype=np.float32)
    out[..., :3] = np.where(ring[..., None], OUTLINE, rgb)
    out[..., 3] = np.where(ring, 1.0, alpha)
    # Keep soft edges where the sprite was half transparent over the ink.
    soft = (alpha > 0.02) & ~solid
    out[..., :3] = np.where(soft[..., None], rgb * alpha[..., None] + OUTLINE * (1 - alpha[..., None]), out[..., :3])
    out[..., 3] = np.where(soft, 1.0, out[..., 3])
    return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")


def keys(args):
    names = sorted(f[:-4] for f in os.listdir(SPRITES) if f.endswith(".png"))
    if args:
        return [n for n in names if n in args]
    return [n for n in names if n.startswith(PREFIXES)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    os.makedirs(ORIGINALS, exist_ok=True)
    if "--restore" in sys.argv:
        for f in os.listdir(ORIGINALS):
            shutil.copy2(os.path.join(ORIGINALS, f), os.path.join(SPRITES, f))
        print("restored", len(os.listdir(ORIGINALS)), "sprites")
        return
    n = 0
    for key in keys(args):
        src = os.path.join(ORIGINALS, key + ".png")
        dst = os.path.join(SPRITES, key + ".png")
        if not os.path.exists(src):
            shutil.copy2(dst, src)
        style(Image.open(src)).save(dst)
        n += 1
    print("styled", n, "sprites (originals in external/sprite_originals/)")


if __name__ == "__main__":
    main()
