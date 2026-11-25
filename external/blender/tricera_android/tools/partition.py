"""Split the model sheet into the android's parts: masks/labels_front.png, labels_side.png (+ overlay).

  python -I tools/partition.py
Foreground = everything that is not the sheet's purple. The Segment Anything cut-outs (masks/f_*.png for
the front view, s_*.png for the left view) are laid over each other in order of what is in front; what
no cut-out claimed goes to the cape (below the shoulders) or to the nearest part."""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref = np.asarray(Image.open(os.path.join(HERE, "reference", "reference.png")).convert("RGB")).astype(np.int32)
fg = np.abs(ref - np.array([152, 2, 232])).sum(-1) > 90
fg = ndi.binary_opening(fg, iterations=1)
FRONT = ["cape", "frill", "legR", "legL", "armR", "armL", "torso", "kilt", "head"]      # back to front
SIDE = ["cape", "frill", "legs", "torso", "kilt", "arm", "head"]
def load(n):
    return np.asarray(Image.open(os.path.join(HERE, "masks", n + ".png")).convert("L")) > 127
def split(names, prefix, x0, x1, cape_top):
    lab = np.zeros(fg.shape, np.uint8)
    region = np.zeros(fg.shape, bool); region[:, x0:x1] = True
    for k, n in enumerate(names):
        if n == "cape":
            continue
        lab[load(prefix + n) & fg & region] = k + 1
    rest = fg & region & (lab == 0)
    yy = np.mgrid[0:fg.shape[0], 0:fg.shape[1]][0]
    # the cape is the big crimson cloth among what is left (its gold hem and emblems join it as the
    # nearest part); everything else unclaimed - belt, neck, tassels - goes to the nearest part
    red = (ref[..., 0] > 55) & (ref[..., 0] > 2.0 * ref[..., 1]) & (ref[..., 0] > 2.0 * ref[..., 2])
    l2, n2 = ndi.label(rest & red & (yy > cape_top))
    sizes = ndi.sum(rest, l2, range(1, n2 + 1))
    cape = np.isin(l2, 1 + np.nonzero(sizes > 2500)[0])
    cape = ndi.binary_fill_holes(ndi.binary_closing(cape, iterations=4)) & rest
    lab[cape] = names.index("cape") + 1
    rest = fg & region & (lab == 0)
    idx = ndi.distance_transform_edt(lab == 0, return_distances=False, return_indices=True)
    lab[rest] = lab[idx[0][rest], idx[1][rest]]
    lab = ndi.median_filter(lab, size=5) * (fg & region)
    idx = ndi.distance_transform_edt(lab == 0, return_distances=False, return_indices=True)
    lab = np.where(fg & region, lab[idx[0], idx[1]], 0).astype(np.uint8)
    return lab
lf = split(FRONT, "f_", 500, 1536, 225)
ls = split(SIDE, "s_", 0, 500, 225)
Image.fromarray(lf).save(os.path.join(HERE, "masks", "labels_front.png"))
Image.fromarray(ls).save(os.path.join(HERE, "masks", "labels_side.png"))
pal = np.array([[0,0,0],[230,40,40],[240,200,40],[40,200,80],[40,220,220],[60,90,240],[200,60,240],[255,140,0],[150,255,150],[255,255,255]])
ov = ref * 0.35 + pal[np.maximum(lf, ls)] * 0.65
Image.fromarray(ov.astype(np.uint8)).save(os.path.join(HERE, "renders", "partition.png"))
for nm, lab, names in (("front", lf, FRONT), ("side", ls, SIDE)):
    print(nm, {n: int((lab == k + 1).sum()) for k, n in enumerate(names)})
