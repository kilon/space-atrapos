"""Fuse two calibrated depth maps: the fine relief of one, the large-scale distances of both.

  python -I fuse_depth.py <detail depth.npy> <second depth.npy> <out depth.npy> [--weight 0.5]

Both inputs are calibrate.py outputs (metres, 0 = sky). The two models agree on the valley floor (it is
the ruler) but not on how far in front of it the near hill stands or how far back the far spires are,
so the output takes the detail map and moves each surface towards the second map by `weight` (in log
depth). The correction is smoothed with the detail map as the guide (a joint bilateral filter), so it
is smooth on every surface and still jumps at silhouettes - no halos where the two maps' edges differ.
Sky = the detail map's sky."""
import sys

import numpy as np
from scipy import ndimage as ndi


def joint_bilateral(val, guide, valid, radius=6, sigma_s=5.0, sigma_r=0.04, iters=6):
    """Smooth `val` where `valid`, weighting neighbours by distance and by similarity of `guide`."""
    out = np.where(valid, val, 0.0)
    w_valid = valid.astype(np.float64)
    offs = [(dy, dx) for dy in range(-radius, radius + 1, 2) for dx in range(-radius, radius + 1, 2)]
    for _ in range(iters):
        acc = np.zeros_like(out)
        wsum = np.zeros_like(out)
        for dy, dx in offs:
            ws = np.exp(-(dx * dx + dy * dy) / (2 * sigma_s * sigma_s))
            sv = np.roll(out, (dy, dx), (0, 1))
            sg = np.roll(guide, (dy, dx), (0, 1))
            sw = np.roll(w_valid, (dy, dx), (0, 1))
            w = ws * np.exp(-((sg - guide) ** 2) / (2 * sigma_r * sigma_r)) * sw
            acc += w * sv
            wsum += w
        out = np.where(wsum > 1e-9, acc / np.maximum(wsum, 1e-9), out)
        w_valid = np.maximum(w_valid, (wsum > 1e-9).astype(np.float64))
    return out


def main():
    a = sys.argv[1:]
    za, zb, out = np.load(a[0]).astype(np.float64), np.load(a[1]).astype(np.float64), a[2]
    weight = float(a[a.index("--weight") + 1]) if "--weight" in a else 0.5
    land = za > 0
    la = np.log(np.where(land, za, 1.0))
    both = land & (zb > 0)
    diff = np.where(both, np.log(np.where(zb > 0, zb, 1.0)) - la, 0.0)
    # Outliers of the difference sit in thin bands where the two maps put a silhouette a few pixels
    # apart: leave those out as sources (they get the value of their own side from the filter).
    edge = ndi.maximum_filter(la, 5) - ndi.minimum_filter(la, 5) > 0.12
    src = both & ~ndi.binary_dilation(edge, iterations=3)
    diff = np.clip(diff, -1.2, 1.2)
    corr = joint_bilateral(diff, la, src)
    zf = np.where(land, np.exp(la + weight * corr), 0.0)
    np.save(out, zf.astype(np.float32))
    r = zf[land] / za[land]
    print("fused", out, "land fraction", round(float(land.mean()), 4), "ratio to detail map: percentiles",
          [round(float(np.percentile(r, p)), 3) for p in (1, 25, 50, 75, 99)])


if __name__ == "__main__":
    main()
