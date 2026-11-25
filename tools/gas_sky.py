#!/usr/bin/env python3
"""The gas giants' cloud bands (external/images/gas_giant_cloud_bands.png: six
full-width strips on magenta, each a band of the planet) -> data/sprites/
sky_gg_band1..6.png, each made to tile left to right: its last BLEND columns
are cross-faded into its first ones and cut off, so scrolling it wraps
without a seam (GasSky scrolls them at different speeds).
    python3 tools/gas_sky.py
"""
import os
import sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "external", "images", "gas_giant_cloud_bands.png")
OUT = os.environ.get("SPRITES_OUT") or os.path.join(ROOT, "data", "sprites")
BLEND = 180   # px cross-faded at the wrap


def magenta(rgb):
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    return (r - g > 110) & (b - g > 110)


def main():
    img = np.asarray(Image.open(SRC).convert("RGB")).astype(np.int32)
    m = magenta(img)
    rows = m.mean(axis=1) < 0.5          # rows that are mostly picture
    bands, start = [], None
    for y, v in enumerate(rows):
        if v and start is None:
            start = y
        if not v and start is not None:
            bands.append((start, y))
            start = None
    if start is not None:
        bands.append((start, len(rows)))
    bands = [(a + 2, b - 2) for a, b in bands if b - a > 40]   # (a hair of fringe off top and bottom)
    for i, (y0, y1) in enumerate(bands):
        strip = img[y0:y1].astype(np.float32)
        # columns that are picture (the strips touch the image's sides; trim any fringe)
        cols = np.nonzero(m[y0:y1].mean(axis=0) < 0.5)[0]
        strip = strip[:, cols.min() + 1:cols.max()]
        w = strip.shape[1]
        out = strip[:, :w - BLEND].copy()
        t = np.linspace(0.0, 1.0, BLEND, dtype=np.float32)[None, :, None]
        out[:, :BLEND] = strip[:, :BLEND] * t + strip[:, w - BLEND:] * (1.0 - t)
        path = os.path.join(OUT, "sky_gg_band%d.png" % (i + 1))
        Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(path)
        print("%-28s %d x %d" % (os.path.basename(path), out.shape[1], out.shape[0]))
    print(len(bands), "bands")


if __name__ == "__main__":
    main()
