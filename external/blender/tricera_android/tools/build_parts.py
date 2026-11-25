"""The android's parts as meshes whose front and side outlines are the model sheet's own.

  python -I tools/build_parts.py        (after tools/partition.py)  ->  meshes/<part>.npz, tex/<part>_{front,side}.png

For every part the sheet gives two outlines: in the front view (x across, z up) and in the left view
(y front-to-back, z up); both views are at the same scale (K metres per pixel) and height. Each part is
carved row by row: at a height z the front view says how wide the part is there (from x0 to x1) and the
left view how deep (y0 to y1), and the part's section at that height is a rounded shape (a superellipse)
touching all four. Stacked up and skinned (marching cubes on the smooth field), the solid has exactly the
sheet's outline from the front and from the side. Arms point at the viewer in the left view, so they are
built column by column instead: round sections whose height is the front view's.
Hidden portions (the cape behind the body, thighs under the kilt...) are continued from what shows.
The drawing itself is the paint: each part gets the sheet's front and left pictures of it (cut out, the
surroundings filled with the part's own nearest colour), mapped straight on from the front and the side."""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import measure

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K = 0.00228                      # metres per sheet pixel
FX, SX, GROUND = 1037.0, 262.0, 985.0     # the front view's centre line, the left view's body axis, the feet (px)
STEP = {"head": 1, "frill": 1, "armR": 1, "armL": 1}      # voxel size in pixels (default 2)
S = 2
FRONT = ["cape", "frill", "legR", "legL", "armR", "armL", "torso", "kilt", "head"]
SIDE = ["cape", "frill", "legs", "torso", "kilt", "arm", "head"]
SIDE_OF = {"legR": "legs", "legL": "legs", "armR": "arm", "armL": "arm"}
POWER = {"cape": 5.0, "frill": 8.0, "torso": 3.2, "kilt": 3.2, "head": 3.0, "legR": 3.2, "legL": 3.2}

ref = np.asarray(Image.open(os.path.join(HERE, "reference", "reference.png")).convert("RGB"))
lf = np.asarray(Image.open(os.path.join(HERE, "masks", "labels_front.png")))
ls = np.asarray(Image.open(os.path.join(HERE, "masks", "labels_side.png")))
H, W = lf.shape


def runs(row):
    """[(start, end)] of the True stretches of a 1D mask."""
    d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
    return list(zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]))


def span_fill(m):
    """Every row filled from its first to its last pixel (what is hidden behind nearer parts)."""
    out = np.zeros_like(m)
    for r in np.nonzero(m.any(1))[0]:
        c = np.nonzero(m[r])[0]
        out[r, c[0]:c[-1] + 1] = True
    return out


def extend(m, up=0, down=0):
    """Repeat the part's top / bottom row upwards / downwards (a limb running on under cloth)."""
    out = m.copy()
    rows = np.nonzero(m.any(1))[0]
    for k in range(1, up + 1):
        out[rows[0] - k] = m[rows[0] + 3]
    for k in range(1, down + 1):
        out[rows[-1] + k] = m[rows[-1] - 3]
    return out


def geometry_masks(name):
    f = lf == FRONT.index(name) + 1
    sname = SIDE_OF.get(name, name)
    s = ls == SIDE.index(sname) + 1
    f = ndi.binary_closing(f, iterations=2)
    s = ndi.binary_closing(s, iterations=2)
    if name in ("cape", "frill"):
        f, s = span_fill(f), span_fill(s)
    if name in ("legR", "legL"):
        f, s = extend(f, up=70), extend(span_fill(s), up=70)
    if name == "torso":
        s = s | (ls == SIDE.index("arm") + 1)      # the left view draws the arm over the torso's side
        f, s = extend(span_fill(f), down=80), extend(span_fill(s), down=80)
    if name == "kilt":
        f, s = span_fill(f), span_fill(s)
    if name == "head":
        s = ndi.binary_fill_holes(s)
    return f, s


def field_rows(f, s, n):
    """The smooth field (> 0 inside) of a part carved row by row. Returns it with its pixel origin.
    Where one view shows the part higher or lower than the other (the sheet's two drawings do not agree
    to the pixel), the other view's nearest row stands in. Where the left view shows two separate pieces
    at one height (the nose horn in front of the face), the smaller piece gets a round section."""
    frows, srows = np.nonzero(f.any(1))[0], np.nonzero(s.any(1))[0]
    xs = np.nonzero(f.any(0))[0]
    ys = np.nonzero(s.any(0))[0]
    top, bot = min(frows[0], srows[0]), max(frows[-1], srows[-1])
    x0, y0, r0 = xs[0] - 6, ys[0] - 6, top - 6
    gx = np.arange(x0, xs[-1] + 7, S, dtype=np.float64)
    gy = np.arange(y0, ys[-1] + 7, S, dtype=np.float64)
    gr = np.arange(r0, bot + 7, S)
    vol = np.full((len(gx), len(gy), len(gr)), -1.0, np.float32)
    for k, r in enumerate(gr):
        if r < top or r > bot:
            continue
        frow = f[min(max(r, frows[0]), frows[-1])]
        srow = s[min(max(r, srows[0]), srows[-1])]
        if not (frow.any() and srow.any()):
            continue
        sruns = sorted(runs(srow), key=lambda t: t[0] - t[1])          # longest first
        fruns = runs(frow)
        for j, (c, d) in enumerate(sruns):
            yc, ry = 0.5 * (c + d), max(0.5 * (d - c), 1.0)
            ty = np.abs(gy - yc) / ry
            for a, b in fruns:
                xc, rx = 0.5 * (a + b), max(0.5 * (b - a), 1.0)
                if j > 0:                      # a smaller piece in front of / behind the main one: round
                    if abs(xc - (xs[0] + xs[-1]) / 2) > rx:
                        continue
                    rx = min(rx, ry)
                tx = np.abs(gx - xc) / rx
                q = (tx[:, None] ** n + ty[None, :] ** n) ** (1.0 / n)
                vol[:, :, k] = np.maximum(vol[:, :, k], np.clip((1.0 - q) * min(rx, ry) / S, -1, 1))
    return vol, (x0, y0, r0)


def field_arm(f, s):
    """An arm: round sections column by column (it points at the viewer in the left view)."""
    cols = np.nonzero(f.any(0))[0]
    rows = np.nonzero(f.any(1))[0]
    sy = np.nonzero(s.any(0))[0]
    yc = 0.5 * (sy[0] + sy[-1])
    x0, r0, y0 = cols[0] - 6, rows[0] - 6, int(yc) - 90
    gx = np.arange(x0, cols[-1] + 7, S)
    gy = np.arange(y0, y0 + 181, S, dtype=np.float64)
    gr = np.arange(r0, rows[-1] + 7, S, dtype=np.float64)
    vol = np.full((len(gx), len(gy), len(gr)), -1.0, np.float32)
    for k, x in enumerate(gx):
        if x < 0 or x >= W:
            continue
        for a, b in runs(f[:, x]):
            zc, rz = 0.5 * (a + b), max(0.5 * (b - a), 1.0)
            ry = min(rz * 0.92, 78.0)
            q = np.sqrt(((gy - yc) / ry)[:, None] ** 2 + ((gr - zc) / rz)[None, :] ** 2)
            vol[k] = np.maximum(vol[k], np.clip((1.0 - q) * min(ry, rz) / S, -1, 1))
    return vol, (x0, y0, r0)


def texture(view_labels, index, tag, name):
    """The part's picture in one view: the sheet inside the part, the part's nearest colour around it."""
    m = ndi.binary_erosion(view_labels == index + 1, iterations=1)
    if not m.any():
        m = view_labels == index + 1
    idx = ndi.distance_transform_edt(~m, return_distances=False, return_indices=True)
    img = ref[idx[0], idx[1]]
    rr, cc = np.nonzero(m)
    box = (max(cc.min() - 40, 0), max(rr.min() - 40, 0), min(cc.max() + 40, W), min(rr.max() + 40, H))
    Image.fromarray(img[box[1]:box[3], box[0]:box[2]]).save(os.path.join(HERE, "tex", f"{name}_{tag}.png"))
    return box


def main():
    os.makedirs(os.path.join(HERE, "meshes"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "tex"), exist_ok=True)
    global S
    for name in FRONT:
        S = STEP.get(name, 2)
        f, s = geometry_masks(name)
        if name.startswith("arm"):
            vol, (x0, y0, r0) = field_arm(f, s)
        else:
            vol, (x0, y0, r0) = field_rows(f, s, POWER[name])
        vol = ndi.gaussian_filter(vol, (0.4, 0.4, 0.7))
        v, faces, nrm, _ = measure.marching_cubes(vol, level=0.0)
        px, py, pr = x0 + v[:, 0] * S, y0 + v[:, 1] * S, r0 + v[:, 2] * S
        verts = np.stack([(px - FX) * K, (py - SX) * K, (GROUND - pr) * K], 1).astype(np.float32)
        bf = texture(lf, FRONT.index(name), "front", name)
        if name.startswith("arm") or name == "torso":     # from the side an arm shows the shoulder pad and the hand: the sheet's picture of both
            both = np.where((ls == SIDE.index("arm") + 1) | ((ls == SIDE.index("torso") + 1)), 1, 0).astype(np.uint8)
            bs = texture(both, 0, "side", name)
        else:
            bs = texture(ls, SIDE.index(SIDE_OF.get(name, name)), "side", name)
        uvf = np.stack([(px - bf[0]) / (bf[2] - bf[0]), 1 - (pr - bf[1]) / (bf[3] - bf[1])], 1).astype(np.float32)
        uvs = np.stack([(py - bs[0]) / (bs[2] - bs[0]), 1 - (pr - bs[1]) / (bs[3] - bs[1])], 1).astype(np.float32)
        # which way the surface faces, from the smoothed field (steadier than the facets' own normals)
        g = np.stack(np.gradient(ndi.gaussian_filter(vol, 2.5)), -1)
        gv = np.stack([ndi.map_coordinates(g[..., c], v.T, order=1) for c in range(3)], 1)
        gv /= np.maximum(np.linalg.norm(gv, axis=1, keepdims=True), 1e-9)
        nx, ny = np.abs(gv[:, 0]), np.abs(gv[:, 1])
        wside = ((nx > 0.6 * ny) & (nx > 0.3)).astype(np.float32)
        if name.startswith("arm"):
            wside = (nx > 0.8).astype(np.float32)      # only an arm's outer end shows the left view's picture      # a quick switch where the surface turns
        np.savez(os.path.join(HERE, "meshes", name + ".npz"), verts=verts, faces=faces[:, ::-1].astype(np.int32),
                 uv_front=uvf, uv_side=uvs, wside=wside)
        print(f"{name}: {len(verts)} verts, {len(faces)} tris, x {verts[:,0].min():.2f}..{verts[:,0].max():.2f} "
              f"y {verts[:,1].min():.2f}..{verts[:,1].max():.2f} z {verts[:,2].min():.2f}..{verts[:,2].max():.2f}")


main()
