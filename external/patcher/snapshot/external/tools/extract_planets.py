"""Cuts the six planets out of external/images/planets_sheet.png (3 x 2 grid on
black) into data/sprites/planet_<name>.png with transparency.

Each output is square with the planet disk centred and its radius exactly
DISK of the half-size, so the game can size planets by their disk
(Planets.make_planet). Inside the disk is opaque; outside, the black
background becomes transparent and glow / smoke keep a soft edge
(alpha = brightness, colour un-premultiplied from black)."""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "external", "images", "planets_sheet.png")
OUT = os.path.join(ROOT, "data", "sprites")
NAMES = [["earth", "desert", "volcanic"], ["ice", "ocean", "giant"]]
DISK = 0.86      # disk radius / half the output size (Planets.DISK)
SIZE = 512       # output px


def main():
    src = np.asarray(Image.open(SHEET).convert("RGB")).astype(np.float32)
    H, W = src.shape[:2]
    ch, cw = H // 2, W // 3
    for r, row in enumerate(NAMES):
        for c, name in enumerate(row):
            cell = src[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
            lum = cell.max(axis=2)
            m = lum > 40
            ys, xs = np.nonzero(m)
            cy0, cx0 = int(ys.mean()), int(xs.mean())
            # The disk from its widest row and tallest column (smoke, glow
            # and moons stick out elsewhere).
            row_x = np.nonzero(m[cy0])[0]
            col_y = np.nonzero(m[:, cx0])[0]
            cx = (row_x.min() + row_x.max()) / 2.0
            cy = (col_y.min() + col_y.max()) / 2.0
            rad = ((row_x.max() - row_x.min()) + (col_y.max() - col_y.min())) / 4.0
            # Resample a square window around the disk to SIZE px.
            half = rad / DISK
            k = 2.0 * half / SIZE
            gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
            sx = cx - half + (gx + 0.5) * k
            sy = cy - half + (gy + 0.5) * k
            img = Image.fromarray(cell.astype(np.uint8))
            # (affine resize of the window; outside the cell reads as black)
            win = img.transform((SIZE, SIZE), Image.EXTENT,
                                (cx - half, cy - half, cx + half, cy + half), Image.BICUBIC)
            rgb = np.asarray(win).astype(np.float32)
            d = np.hypot(sx - cx, sy - cy) / rad          # 1 = the disk's edge
            a_out = np.clip((rgb.max(axis=2) - 6.0) / 120.0, 0.0, 1.0)
            inside = np.clip((1.0 - d) / 0.012 + 0.5, 0.0, 1.0)   # 1 px soft edge
            a = np.maximum(inside, a_out)
            col = np.where(inside[..., None] >= 1.0, rgb,
                           np.clip(rgb / np.maximum(a, 1e-3)[..., None], 0, 255))
            out = np.dstack([col, a * 255.0]).astype(np.uint8)
            path = os.path.join(OUT, "planet_%s.png" % name)
            Image.fromarray(out, "RGBA").save(path)
            print("%s: centre (%.0f, %.0f) radius %.0f -> %s" % (name, cx, cy, rad, path))


if __name__ == "__main__":
    main()
