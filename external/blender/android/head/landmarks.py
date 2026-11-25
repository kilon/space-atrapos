"""Centroids of cyan blobs (the eye, the earring gem) in the reference and the render."""
import sys, numpy as np
from PIL import Image
sys.path.insert(0, "../../../tools")
from extract_sprites import components
def blobs(path, off=(0, 0)):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    m = (b > 200) & (g > 170) & (r < 170) & (al > 200)
    h, w = m.shape
    out = []
    for c in components(m):
        if len(c) > 60:
            ys, xs = np.divmod(np.asarray(c), w)
            out.append((int(xs.mean()) - off[0], int(ys.mean()) - off[1], len(c), int(xs.min()) - off[0], int(xs.max()) - off[0], int(ys.min()) - off[1], int(ys.max()) - off[1]))
    return sorted(out, key=lambda t: -t[2])[:4]
print("ref   ", blobs(sys.argv[1]))
print("render", blobs(sys.argv[2], (100, 20)))   # (in reference pixels)
