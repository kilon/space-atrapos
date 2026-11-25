"""Puts the render beside the reference picture:  python -I compare.py [<render>]
Writes renders/vs_reference.png (the picture above, the render below, both on dark grey) and
renders/overlay.png (the picture's outline in green over the render), and prints how much of the
two silhouettes agrees (intersection over union)."""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def on_grey(im):
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    al = a[..., 3:4] / 255
    return (a[..., :3] * al + 34 * (1 - al)).astype(np.uint8), al[..., 0] > 0.5


def main():
    render = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "renders", "view.png")
    ref, mr = on_grey(Image.open(os.path.join(ROOT, "reference", "reference.png")))
    ren, mm = on_grey(Image.open(render))
    print("silhouette agreement %.3f  (picture only %d px, model only %d px)" % ((mr & mm).sum() / (mr | mm).sum(), (mr & ~mm).sum(), (mm & ~mr).sum()))
    Image.fromarray(np.vstack([ref, ren])).save(os.path.join(ROOT, "renders", "vs_reference.png"))
    edge = mr ^ ndi.binary_erosion(mr, iterations=2)
    ov = ren.copy()
    ov[edge] = (0, 255, 0)
    g = np.asarray(Image.fromarray(ref).convert("L")).astype(np.float32)
    inner = (np.hypot(ndi.sobel(g, 0), ndi.sobel(g, 1)) > 260) & mr          # the picture's strong inner edges too, faintly
    ov[inner & ~edge] = (ov[inner & ~edge] * 0.5 + np.array((0, 200, 255)) * 0.5).astype(np.uint8)
    Image.fromarray(ov).save(os.path.join(ROOT, "renders", "overlay.png"))


if __name__ == "__main__":
    main()
