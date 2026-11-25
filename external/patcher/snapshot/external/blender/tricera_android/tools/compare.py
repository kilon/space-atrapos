"""Puts the model's renders beside the sheet:  python -I compare.py [<renders dir> [<prefix>]]

Writes <renders dir>/vs_reference.png: the sheet's left and front views above, the renders below
(on the sheet's purple), and prints how much of each view's silhouette agrees (intersection over union)."""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PURPLE = (166, 3, 238)
VIEWS = (("left", 30, 520), ("front", 537, 1000))


def main():
    rd = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "renders")
    prefix = sys.argv[2] if len(sys.argv) > 2 else ""
    ref = np.asarray(Image.open(os.path.join(ROOT, "reference", "reference.png")).convert("RGB")).astype(np.int32)
    ref = np.pad(ref, ((0, 0), (0, 8), (0, 0)), mode="edge")            # (the front view's frame runs a pixel past the sheet)
    fg_ref = np.abs(ref - np.array((152, 2, 232))).sum(axis=2) > 90
    top, bottom, edge = [], [], []
    for name, x0, w in VIEWS:
        r = np.asarray(Image.open(os.path.join(rd, prefix + name + ".png")).convert("RGBA")).astype(np.float32)
        a = r[..., 3:4] / 255
        comp = (r[..., :3] * a + np.array(PURPLE, np.float32) * (1 - a)).astype(np.uint8)
        fr = fg_ref[:, x0:x0 + w]
        fm = a[..., 0] > 0.5
        iou = (fr & fm).sum() / max((fr | fm).sum(), 1)
        print(f"{name}: silhouette agreement {iou:.3f}  (sheet only {int((fr & ~fm).sum())} px, model only {int((fm & ~fr).sum())} px)")
        top.append(ref[:, x0:x0 + w].astype(np.uint8))
        bottom.append(comp)
        # where they differ: the model's picture, the sheet-only area in green, the model-only area in blue
        d = comp.copy()
        d[fr & ~fm] = (0, 255, 0)
        d[fm & ~fr] = (0, 80, 255)
        edge.append(d)
    out = np.vstack([np.hstack(top), np.hstack(bottom)])
    Image.fromarray(out).save(os.path.join(rd, prefix + "vs_reference.png"))
    Image.fromarray(np.hstack(edge)).save(os.path.join(rd, prefix + "difference.png"))


if __name__ == "__main__":
    main()
