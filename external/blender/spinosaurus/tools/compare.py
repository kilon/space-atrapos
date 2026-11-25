"""Puts the render beside the reference picture:  python -I compare.py [<render>]
Writes renders/vs_reference.png (the picture above, the render below, on white), renders/overlay.png
(the picture's outline in green over the render) and reference/mask.png (the animal cut from the
picture's checkered background), and prints how much of the two silhouettes agrees."""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def ref_mask(ref):
    a = ref.astype(np.int32)
    bg = (a.min(axis=2) > 222) & (a.max(axis=2) - a.min(axis=2) < 16)
    fg = ndi.binary_opening(~bg, iterations=2)
    lab, n = ndi.label(fg)
    sizes = ndi.sum(fg, lab, range(1, n + 1))
    fg = np.isin(lab, 1 + np.nonzero(sizes > 150)[0])
    return ndi.binary_fill_holes(fg)


def main():
    render = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "renders", "view.png")
    ref = np.asarray(Image.open(os.path.join(ROOT, "reference", "reference.png")).convert("RGB"))
    mr = ref_mask(ref)
    Image.fromarray((mr * 255).astype(np.uint8)).save(os.path.join(ROOT, "reference", "mask.png"))
    r = np.asarray(Image.open(render).convert("RGBA")).astype(np.float32)
    al = r[..., 3:4] / 255
    ren = (r[..., :3] * al + 255 * (1 - al)).astype(np.uint8)
    mm = al[..., 0] > 0.5
    print("silhouette agreement %.3f  (picture only %d px, model only %d px)" % ((mr & mm).sum() / (mr | mm).sum(), (mr & ~mm).sum(), (mm & ~mr).sum()))
    refw = ref.copy()
    refw[~mr] = 255
    Image.fromarray(np.vstack([refw, ren])).save(os.path.join(ROOT, "renders", "vs_reference.png"))
    edge = mr ^ ndi.binary_erosion(mr, iterations=2)
    ov = ren.copy()
    ov[mm & ~mr] = (ov[mm & ~mr] * 0.5 + np.array((60, 110, 255)) * 0.5).astype(np.uint8)        # model outside the picture: blue
    ov[mr & ~mm] = (255, 190, 190)                                                                  # picture the model misses: pink
    ov[edge] = (0, 200, 0)
    Image.fromarray(ov).save(os.path.join(ROOT, "renders", "overlay.png"))


if __name__ == "__main__":
    main()
