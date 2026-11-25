"""Look at the calibrated depth as a coloured point cloud from above and from the side.

  python -I pointcloud_views.py <image> <depth.npy> <camera.json> <out prefix> [--range 400]

Writes <prefix>_top.png (X right, Y up the page = into the picture) and <prefix>_side.png (Y right,
Z up; seen from the right), both orthographic, coloured with the picture's pixels. For checking that
cliffs stand upright, the floor is flat and distances make sense."""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import cvlib  # noqa: E402


def splat(px, py, key, col, w, h):
    """Draw points; larger `key` wins (drawn last)."""
    ok = (px >= 0) & (px < w) & (py >= 0) & (py < h)
    px, py, key, col = px[ok], py[ok], key[ok], col[ok]
    order = np.argsort(key)
    img = np.zeros((h, w, 3), np.uint8)
    img[py[order], px[order]] = col[order]
    return img


def main():
    a = sys.argv[1:]
    ref = np.asarray(Image.open(a[0]).convert("RGB"))
    z = np.load(a[1]).astype(np.float64)
    with open(a[2]) as fh:
        cam = cvlib.Camera(**json.load(fh))
    rng = float(a[a.index("--range") + 1]) if "--range" in a else 400.0
    u, v = cvlib.pixel_grid(z.shape[1], z.shape[0])
    land = z > 0
    p = cam.unproject(u[land], v[land], z[land])
    col = ref[land]
    S = 1000
    # top view: x in [-rng/2, rng/2], y in [0, rng]
    px = ((p[:, 0] + rng / 2) / rng * S).astype(int)
    py = (S - 1 - p[:, 1] / rng * S).astype(int)
    top = Image.fromarray(splat(px, py, p[:, 2], col, S, S))
    d = ImageDraw.Draw(top)
    for m in range(0, int(rng) + 1, 50):
        yy = S - 1 - m / rng * S
        d.line([(0, yy), (12, yy)], fill=(255, 255, 0))
        d.text((14, yy - 6), f"{m} m", fill=(255, 255, 0))
    d.text((S // 2 - 20, S - 14), "camera", fill=(0, 255, 255))
    top.save(a[3] + "_top.png")
    # side view from the right: y in [0, rng] across, z in [-rng*0.05, rng*0.35] up
    zr = rng * 0.4
    px = (p[:, 1] / rng * S).astype(int)
    hh = int(S * 0.4)
    py = (hh - 1 - (p[:, 2] + rng * 0.05) / zr * hh).astype(int)
    side = Image.fromarray(splat(px, py, p[:, 0], col, S, hh))
    d = ImageDraw.Draw(side)
    y0 = hh - 1 - (rng * 0.05) / zr * hh
    d.line([(0, y0), (S, y0)], fill=(0, 120, 255))
    for m in range(0, int(rng) + 1, 50):
        xx = m / rng * S
        d.line([(xx, y0), (xx, y0 + 6)], fill=(255, 255, 0))
        d.text((xx + 2, y0 + 6), f"{m}", fill=(255, 255, 0))
    side.save(a[3] + "_side.png")
    print("wrote", a[3] + "_top.png", a[3] + "_side.png")


if __name__ == "__main__":
    main()
