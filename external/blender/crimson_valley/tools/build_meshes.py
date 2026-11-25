"""Geometry of the Crimson Valley scene from the picture's calibrated depth.

  python -I build_meshes.py [--emboss 0.004] [--debug]

Reads analysis/ (depth.npy, camera.json, the masks; optional city.png, waterfall.png) and writes meshes/.
Everything is worked out on the picture grown by PAD pixels on every side (the edge pixels repeated), so
the geometry runs on past the picture's frame instead of stopping at it.

  rocks_<group>.npz   the rock formations, one file per group (see GROUPS). A formation is a piece of
                      land that stands above the valley floor and whose depth is continuous: pieces are
                      cut apart where the depth steps (one rock in front of another). Each is a "pillow":
                        FRONT  one quad per picture pixel, corners unprojected with the measured depth -
                               from the scene camera it has exactly the picture's outline and relief;
                        BACK   a coarser shell: the front pushed away from the camera by a thickness that
                               grows from zero at the piece's border (so pieces are about as deep as they
                               are wide). It is never seen from the scene camera.
                      Where a piece disappears behind a nearer one or into the ground it is continued
                      EXTEND pixels (hidden there), so no cracks open up when the view moves a little.
                      Outlines are smoothed (no pixel stairs).
                      CURTAINS ground the pieces: from the border of every part of a piece that has
                      nothing but nearer land below it in the picture, a wall drops straight down to the
                      ground just behind the surface. From the scene camera they are hidden (behind the
                      rock below); from anywhere else they are the unseen sides of the formation.
  terrain.npz         the valley floor: one sheet over everything below the horizon, at the measured
                      height where the floor is visible and filled in smoothly where rocks hide it or
                      past the picture's edges; river beds are carved under the water mask and banks
                      kept above the water. An apron continues it as flat ground to 30 km.
  water.npz           the water surface: the plane z = 0 under the sheet.
  rocks.json          the list of formations (group, picture box, depth, size) and the groups.

Per-vertex attributes in every file: ref_uv (picture u / 1672, 1 - v / 941; outside 0..1 past the frame),
dist (metres from the camera), veg / moss / mist (cover masks sampled from the picture), front (1 on the
camera-facing vertices), and for the terrain seen (1 where the floor is visible in the picture) and wet
(1 at the water's edge and under water). Faces are quads (M, 4); face_kind says which are front (0),
back (1), curtain (3) - curtains are flat-shaded.

Fine relief: `--emboss` adds the picture's fine light / dark pattern to the depth (dark = deeper), scaled
with distance so it is always a few pixels deep, and weaker on surfaces seen edge-on.
"""
import json
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import color

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cvlib  # noqa: E402

OUT = os.path.join(cvlib.ROOT, "meshes")
W, H = cvlib.W, cvlib.H
PAD = 80             # pixels the picture is grown by on every side
CUT_MIN = 0.006      # a depth step smaller than this (relative, between neighbours) never separates
CUT_RATIO = 3.5      # ... a larger one does when it is this many times the local depth gradient
CUT_MAX = 0.04       # ... or whenever it is larger than this
MIN_PIECE = 120      # smaller pieces are joined to a neighbour
EXTEND = 16          # pixels a formation is continued behind nearer things / into the ground
BACK_STEP = 4        # the back is made of blocks of this many pixels
THICK = 1.3          # thickness = THICK x distance from the piece's border
THICK_CAP = 40.0     # ... but never more than this (m), nor more than 0.4 of the distance
GROUND_Z = 0.6       # the level the terrain settles to away from the picture (m)
BURY_Z = -0.5        # curtains end here, under the ground
CURTAIN_BACK = (0.012, 0.3)   # curtains stand this far behind the surface: fraction of the range + metres
SUPPORT_TOL = (0.008, 0.2)    # how much farther the land below may be and still hide a curtain

# Groups of formations: first match wins. f: a formation's median depth (m), picture box and its centre.
GROUPS = [
    ("far",             lambda f: f["depth"] > 900),
    ("near_hill",       lambda f: f["depth"] < 62 and (f["cx"] < 800 or f["y1"] > 930) and not (f["cx"] > 830 and f["depth"] > 30 and f["y1"] < 930)),
    ("outcrop",         lambda f: f["depth"] < 62 and 800 <= f["cx"] < 1300),
    ("waterfall_cliff", lambda f: f["depth"] < 125 and f["cx"] >= 1200),
    ("river_spires",    lambda f: f["depth"] < 150 and 760 <= f["cx"] < 1300 and f["cy"] > 520),
    ("far_spires",      lambda f: f["depth"] >= 330 and f["cx"] < 520),
    ("mid_spires",      lambda f: f["depth"] >= 205 and 440 <= f["cx"] < 760),
    ("mid_ridges",      lambda f: f["cx"] < 880 and f["depth"] < 330),
    ("right_towers",    lambda f: f["cx"] >= 1380 and f["cy"] < 330),
    ("big_arch",        lambda f: True),
]


def load_mask(name, soft=False):
    p = os.path.join(cvlib.ANALYSIS, name + ".png")
    if not os.path.exists(p):
        return None
    a = np.asarray(Image.open(p).convert("L")).astype(np.float32) / 255
    return a if soft else a > 0.5


def pad(a):
    return np.pad(a, PAD, mode="edge")


def bilinear(a, x, y):
    """Sample array a at continuous array coordinates (x, y), where pixel [j, i] has centre (i + 0.5, j + 0.5)."""
    return ndi.map_coordinates(a, [np.clip(y - 0.5, 0, a.shape[0] - 1), np.clip(x - 0.5, 0, a.shape[1] - 1)],
                               order=1, mode="nearest")


def norm_blur(a, m, sigma):
    """Gaussian blur of a where m, ignoring everything else."""
    num = ndi.gaussian_filter(np.where(m, a, 0.0), sigma)
    den = ndi.gaussian_filter(m.astype(np.float64), sigma)
    return np.where(den > 1e-6, num / np.maximum(den, 1e-6), a)


def label_cut(mask, cut_h, cut_v):
    """Connected pieces of `mask` (4-neighbours) that are not joined across the cut edges.
    cut_h[j, i]: the edge between (j, i) and (j, i + 1); cut_v[j, i]: between (j, i) and (j + 1, i)."""
    h, w = mask.shape
    big = np.zeros((2 * h - 1, 2 * w - 1), bool)
    big[::2, ::2] = mask
    big[::2, 1::2] = mask[:, :-1] & mask[:, 1:] & ~cut_h
    big[1::2, ::2] = mask[:-1] & mask[1:] & ~cut_v
    lab, n = ndi.label(big)
    return lab[::2, ::2].astype(np.int32), n


def merge_small(lab, logz, min_size):
    """Join pieces smaller than min_size to the touching piece nearest in depth."""
    for _ in range(5):
        n = int(lab.max())
        sizes = np.bincount(lab.ravel(), minlength=n + 1)
        small = [k for k in range(1, n + 1) if 0 < sizes[k] < min_size]
        if not small:
            break
        objs = ndi.find_objects(lab)
        med = ndi.median(logz, lab, range(1, n + 1))
        changed = False
        for k in small:
            sl = objs[k - 1]
            if sl is None:
                continue
            y0, y1 = max(sl[0].start - 1, 0), min(sl[0].stop + 1, lab.shape[0])
            x0, x1 = max(sl[1].start - 1, 0), min(sl[1].stop + 1, lab.shape[1])
            sub = lab[y0:y1, x0:x1]
            me = sub == k
            if not me.any():
                continue
            ring = ndi.binary_dilation(me) & ~me
            nb = np.unique(sub[ring])
            nb = nb[(nb != 0) & (nb != k)]
            if len(nb) == 0:
                continue
            best = nb[np.argmin(np.abs(med[nb - 1] - med[k - 1]))]
            sub[me] = best
            changed = True
        if not changed:
            break
    ids = np.unique(lab)
    ids = ids[ids != 0]
    remap = np.zeros(int(lab.max()) + 1, np.int32)
    remap[ids] = np.arange(1, len(ids) + 1)
    return remap[lab], len(ids)


def smooth_outline(E, sil, iters=3):
    """Corner positions of a pixel box (h + 1, w + 1) with the outline's pixel stairs smoothed.
    E: the piece's pixels; sil: outside pixels that are true outline (sky or farther things)."""
    h, w = E.shape
    U, V = np.meshgrid(np.arange(w + 1, dtype=np.float64), np.arange(h + 1, dtype=np.float64))
    Ep, Sp = np.pad(E, 1), np.pad(sil, 1)
    up, dn = Ep[:-1, 1:-1], Ep[1:, 1:-1]
    sup, sdn = Sp[:-1, 1:-1], Sp[1:, 1:-1]
    eh = (up & sdn) | (dn & sup)
    lf, rt = Ep[1:-1, :-1], Ep[1:-1, 1:]
    slf, srt = Sp[1:-1, :-1], Sp[1:-1, 1:]
    ev = (lf & srt) | (rt & slf)
    jh, ih = np.nonzero(eh)
    jv, iv = np.nonzero(ev)
    a = np.concatenate([jh * (w + 1) + ih, jv * (w + 1) + iv])
    b = np.concatenate([jh * (w + 1) + ih + 1, (jv + 1) * (w + 1) + iv])
    if len(a) == 0:
        return U, V
    U0, V0 = U.ravel().copy(), V.ravel().copy()
    Uf, Vf = U0.copy(), V0.copy()
    n = np.zeros(Uf.shape)
    np.add.at(n, a, 1)
    np.add.at(n, b, 1)
    on = n > 0
    for _ in range(iters):
        su, sv = np.zeros(Uf.shape), np.zeros(Vf.shape)
        np.add.at(su, a, Uf[b])
        np.add.at(su, b, Uf[a])
        np.add.at(sv, a, Vf[b])
        np.add.at(sv, b, Vf[a])
        Uf[on] = 0.5 * Uf[on] + 0.5 * su[on] / n[on]
        Vf[on] = 0.5 * Vf[on] + 0.5 * sv[on] / n[on]
        Uf = np.clip(Uf, U0 - 0.5, U0 + 0.5)
        Vf = np.clip(Vf, V0 - 0.5, V0 + 0.5)
    return Uf.reshape(U.shape), Vf.reshape(V.shape)


def border_edges(S):
    """Pixel edges on the border of the pixel set S, as corner index pairs of the (h + 1, w + 1) grid:
    list of (j0, i0, j1, i1) arrays, one per side (top, bottom, left, right)."""
    Sp = np.pad(S, 1)
    jj, ii = np.nonzero(S)
    top = ~Sp[jj, ii + 1]
    bot = ~Sp[jj + 2, ii + 1]
    lef = ~Sp[jj + 1, ii]
    rig = ~Sp[jj + 1, ii + 2]
    return [(jj[top], ii[top], jj[top], ii[top] + 1), (jj[bot] + 1, ii[bot] + 1, jj[bot] + 1, ii[bot]),
            (jj[lef] + 1, ii[lef], jj[lef], ii[lef]), (jj[rig], ii[rig] + 1, jj[rig] + 1, ii[rig] + 1)]


def relief_solid(cam, E, zf, zb, sil, S, u0, v0):
    """One formation over the pixels E of a box of the (padded) picture whose top-left pixel is (u0, v0):
    the FRONT (a quad per pixel), a coarse BACK (a quad per BACK_STEP x BACK_STEP block of pixels that lies
    wholly inside the piece) and CURTAINS under the border of the pixel set S. zf / zb: front / back depth
    per pixel. Returns verts (N, 3), faces (M, 4), (u, v) per vertex, front flag per vertex, kind per face."""
    h, w = E.shape
    Ep = np.pad(E, 1)
    cnt = (Ep[:-1, :-1].astype(np.int32) + Ep[:-1, 1:] + Ep[1:, :-1] + Ep[1:, 1:])
    used = cnt > 0

    def corner(a):
        ap = np.pad(np.where(E, a, 0.0), 1)
        return (ap[:-1, :-1] + ap[:-1, 1:] + ap[1:, :-1] + ap[1:, 1:]) / np.maximum(cnt, 1)
    zfc, zbc = corner(zf), corner(zb)
    U, V = smooth_outline(E, sil)
    idx = -np.ones((h + 1, w + 1), np.int64)
    n = int(used.sum())
    idx[used] = np.arange(n)
    uu, vv = U[used] + u0, V[used] + v0
    jj, ii = np.nonzero(E)
    c00, c01, c10, c11 = idx[jj, ii], idx[jj, ii + 1], idx[jj + 1, ii], idx[jj + 1, ii + 1]
    faces = [np.stack([c00, c10, c11, c01], 1)]
    kinds = [np.zeros(len(jj), np.int8)]
    verts = [cam.unproject(uu, vv, zfc[used])]
    uvs = [np.stack([uu, vv], 1)]
    front = [np.ones(n, np.float32)]
    nv = n
    # coarse back
    st = BACK_STEP
    hc, wc = h // st, w // st
    if hc and wc:
        blocks = E[:hc * st, :wc * st].reshape(hc, st, wc, st).all(axis=(1, 3))
        if blocks.any():
            bp = np.pad(blocks, 1)
            bused = bp[:-1, :-1] | bp[:-1, 1:] | bp[1:, :-1] | bp[1:, 1:]
            bidx = -np.ones((hc + 1, wc + 1), np.int64)
            nb = int(bused.sum())
            bidx[bused] = np.arange(nb) + nv
            bj, bi = np.nonzero(bused)
            verts.append(cam.unproject(bi * st + float(u0), bj * st + float(v0), zbc[bj * st, bi * st]))
            uvs.append(np.stack([bi * st + float(u0), bj * st + float(v0)], 1))
            front.append(np.zeros(nb, np.float32))
            qj, qi = np.nonzero(blocks)
            faces.append(np.stack([bidx[qj, qi], bidx[qj, qi + 1], bidx[qj + 1, qi + 1], bidx[qj + 1, qi]], 1))
            kinds.append(np.ones(len(qj), np.int8))
            nv += nb
    if S is not None and S.any():                               # curtains
        cu, cv, cz, quads = [], [], [], []
        for j0, i0, j1, i1 in border_edges(S):
            if len(j0) == 0:
                continue
            k = len(j0)
            base = nv + sum(len(x) for x in cu)
            cu += [U[j0, i0] + u0, U[j1, i1] + u0]
            cv += [V[j0, i0] + v0, V[j1, i1] + v0]
            cz += [zfc[j0, i0], zfc[j1, i1]]
            quads.append((base + np.arange(k), base + k + np.arange(k)))
        if cu:
            cu, cv, cz = np.concatenate(cu), np.concatenate(cv), np.concatenate(cz)
            top = cam.unproject(cu, cv, cz)
            hd = top[:, :2] - cam.pos[:2]
            rng = np.linalg.norm(hd, axis=1)
            top[:, :2] += hd / np.maximum(rng, 1e-6)[:, None] * (CURTAIN_BACK[0] * rng + CURTAIN_BACK[1])[:, None]
            top[:, 2] -= 0.15
            keep = top[:, 2] > BURY_Z + 0.2
            botm = top.copy()
            botm[:, 2] = BURY_Z
            m = len(top)
            verts += [top, botm]
            uvs += [np.stack([cu, cv], 1)] * 2
            front += [np.zeros(2 * m, np.float32)]
            for ia, ib in quads:
                ok = keep[ia - nv] | keep[ib - nv]
                q = np.stack([ia, ib, ib + m, ia + m], 1)[ok]
                faces.append(q)
                kinds.append(np.full(len(q), 3, np.int8))
    return (np.concatenate(verts).astype(np.float32), np.concatenate(faces).astype(np.int32), np.concatenate(uvs),
            np.concatenate(front), np.concatenate(kinds))


def main():
    t0 = time.time()
    a = sys.argv[1:]
    emboss_k = float(a[a.index("--emboss") + 1]) if "--emboss" in a else 0.004
    debug = "--debug" in a
    os.makedirs(OUT, exist_ok=True)
    cam0 = cvlib.load_camera()
    z = np.load(os.path.join(cvlib.ANALYSIS, "depth.npy")).astype(np.float64)
    land = z > 0
    floor = load_mask("floor")
    water = load_mask("water")
    veg, moss, mist = load_mask("veg", True), load_mask("moss", True), load_mask("mist", True)
    city, fall = load_mask("city"), load_mask("waterfall")
    ref = np.asarray(Image.open(cvlib.REFERENCE).convert("RGB")).astype(np.float32) / 255
    L = color.rgb2lab(ref)[..., 0]
    u, v = cvlib.pixel_grid(W, H)

    # --- the city is modelled separately: take its pixels off the rock --------------------------------
    if city is not None:
        city = ndi.binary_dilation(city, iterations=3) & land
        rock = land & ~city
        rows = np.arange(H)[:, None]
        first_rock = np.where(rock.any(0), rock.argmax(0), H)            # top-most rock row per column
        to_sky = city & (rows < first_rock[None, :])
        behind = city & ~to_sky
        idx = ndi.distance_transform_edt(~rock, return_distances=False, return_indices=True)
        zfill = z[idx[0], idx[1]]
        z = np.where(behind, norm_blur(zfill, rock | behind, 2.0), z)
        z[to_sky] = 0.0
        land = z > 0
        print(f"city mask: {int(to_sky.sum())} px to sky, {int(behind.sum())} px refilled with rock")
    if fall is not None:
        soft = ndi.gaussian_filter((fall & land).astype(np.float64), 1.5)
        z = np.where(land, z + 1.0 * soft, 0.0)

    # --- which way surfaces face (1 = seen face-on, 0 = edge-on) ------------------------------------
    zs = norm_blur(z, land, 1.5)
    ps = cam0.unproject(u, v, np.where(land, zs, 1.0))
    nrm = np.cross(np.gradient(ps, axis=0), np.gradient(ps, axis=1))
    nrm /= np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-9)
    ray = cam0.rays(u, v)
    ray /= np.linalg.norm(ray, axis=-1, keepdims=True)
    facing = ndi.gaussian_filter(np.abs((nrm * ray).sum(-1)), 2.0)

    # --- fine relief from the picture's light and dark -------------------------------------------
    hp = ndi.gaussian_filter(L, 1.0) - ndi.gaussian_filter(L, 6.0)
    e = np.clip(hp / 12.0, -1, 1)
    keep = 1.0 - np.clip(veg * 1.5 + mist * 2.0, 0, 1)
    keep = np.where(water, 0.0, keep)
    if city is not None:
        keep = np.where(ndi.binary_dilation(city, iterations=2), 0.0, keep)
    e = e * keep * np.clip(facing / 0.5, 0.25, 1.0)

    # --- floor or formation --------------------------------------------------------------------------
    floor = floor & land & ((facing < 0.55) | water)
    floor = ndi.binary_opening(floor, iterations=1) | water
    fl, nf = ndi.label(floor)
    fs = ndi.sum(floor, fl, range(1, nf + 1))
    floor = np.isin(fl, 1 + np.nonzero(fs > 300)[0])
    hgt = cam0.unproject(u, v, np.where(land, z, 1.0))[..., 2]

    # --- grow the picture ------------------------------------------------------------------------------
    cam = cvlib.Camera(f=cam0.f, cx=cam0.cx + PAD, cy=cam0.cy + PAD, pitch=cam0.pitch, cam_h=cam0.cam_h,
                       w=W + 2 * PAD, h=H + 2 * PAD)
    Hp, Wp = H + 2 * PAD, W + 2 * PAD
    zP, landP, floorP, waterP = pad(z), pad(land), pad(floor), pad(water)
    eP = np.pad(e, PAD, mode="constant")
    vegP, mossP, mistP = pad(veg), pad(moss), pad(mist)
    inframe = np.zeros((Hp, Wp), bool)
    inframe[PAD:PAD + H, PAD:PAD + W] = True
    d_frame = ndi.distance_transform_edt(~inframe)
    uP, vP = cvlib.pixel_grid(Wp, Hp)
    v_top = int(np.ceil(cam.horizon_v)) + 3                      # first terrain row (padded coordinates)

    # --- the valley floor's height everywhere below the horizon -----------------------------------
    known = floorP & inframe
    known[:v_top] = False
    hgtP = pad(hgt)
    hk = norm_blur(np.where(known, hgtP, 0.0), known, 1.2)
    ind = ndi.distance_transform_edt(~known, return_distances=False, return_indices=True)
    hfill = hk[ind[0], ind[1]]
    dist_k = ndi.distance_transform_edt(~known)
    hsm = ndi.gaussian_filter(hfill, 10.0)
    wgt = np.clip(dist_k / 12.0, 0, 1)
    hF = np.where(known, hk, hfill * (1 - wgt) + np.clip(hsm, 0.2, 2.5) * wgt)
    t = np.clip(d_frame / 70.0, 0, 1)
    hF = hF * (1 - t) + GROUND_Z * t                              # settle to flat ground past the frame
    wat = waterP & inframe
    d_in = ndi.distance_transform_edt(wat)
    d_out = ndi.distance_transform_edt(~wat)
    bank = 0.10 + 0.35 * (1 - np.exp(-d_out / 5.0))
    hF = np.where(wat, -0.25 - np.minimum(0.6, 0.08 * d_in), np.maximum(hF, bank))
    hF = ndi.gaussian_filter(hF, 0.7)
    zF = cam.ground_z(vP, 0.0) * (cam.cam_h - hF) / cam.cam_h   # the depth of that floor along each ray
    zF[:v_top] = np.inf
    # floor pixels take the floor's depth; land past the frame's bottom that is floor too
    floorP = floorP & (vP > v_top)
    zP = np.where(floorP & np.isfinite(zF), zF, zP)

    # --- formations: pieces of continuous depth ---------------------------------------------------
    form = landP & ~floorP
    logz = np.log(np.where(landP, zP, 1.0))
    disp = np.where(landP, 1.0 / np.maximum(zP, 1e-6), 0.0)
    gx = np.abs(np.diff(disp, axis=1))                           # (Hp, Wp-1)
    gy = np.abs(np.diff(disp, axis=0))                           # (Hp-1, Wp)
    g = np.zeros((Hp, Wp))
    g[:, :-1] += gx
    g[:-1, :] += gy
    small = ndi.zoom(g, 0.25, order=1)
    gref = ndi.zoom(ndi.median_filter(small, size=9), (Hp / small.shape[0], Wp / small.shape[1]), order=1)
    gref = np.maximum(gref, 1e-12)
    rx = np.abs(np.diff(logz, axis=1))
    ry = np.abs(np.diff(logz, axis=0))
    cut_h = (rx > CUT_MAX) | ((rx > CUT_MIN) & (gx > CUT_RATIO * 0.5 * (gref[:, :-1] + gref[:, 1:])))
    cut_v = (ry > CUT_MAX) | ((ry > CUT_MIN) & (gy > CUT_RATIO * 0.5 * (gref[:-1] + gref[1:])))
    lab, n = label_cut(form, cut_h, cut_v)
    lab, n = merge_small(lab, logz, MIN_PIECE)
    print(f"{n} formations ({time.time() - t0:.1f} s)")

    # --- where a curtain can hang unseen: nothing but nearer land below, all the way down ------------
    pP = cam.unproject(uP, vP, np.where(landP, zP, 1.0))
    rngP = np.hypot(pP[..., 0], pP[..., 1])
    rs = norm_blur(rngP, landP, 2.0)
    below = np.zeros((Hp, Wp))
    bm = np.zeros(Wp)
    for j in range(Hp - 1, -1, -1):
        below[j] = bm
        bm = np.where(landP[j], np.maximum(bm, rs[j]), np.inf)
    supported = landP & (below <= rs * (1 + SUPPORT_TOL[0]) + SUPPORT_TOL[1])
    supported = ndi.binary_closing(ndi.binary_opening(supported, iterations=2), iterations=2) & landP

    emb = np.where(landP, zP * (1.0 - emboss_k * eP), 0.0)
    objs = ndi.find_objects(lab)
    med_depth = np.exp(ndi.median(logz, lab, range(1, n + 1)))
    groups = {g_: {"verts": [], "faces": [], "uv": [], "front": [], "kind": [], "nv": 0} for g_, _ in GROUPS}
    index = []
    for k in range(1, n + 1):
        sl = objs[k - 1]
        y0, y1 = max(sl[0].start - EXTEND - 2, 0), min(sl[0].stop + EXTEND + 2, Hp)
        x0, x1 = max(sl[1].start - EXTEND - 2, 0), min(sl[1].stop + EXTEND + 2, Wp)
        M = lab[y0:y1, x0:x1] == k
        zc = zP[y0:y1, x0:x1]
        lnd = landP[y0:y1, x0:x1]
        ind = ndi.distance_transform_edt(~M, return_distances=False, return_indices=True)
        dist_out = np.hypot(ind[0] - np.arange(y1 - y0)[:, None], ind[1] - np.arange(x1 - x0)[None, :])
        zext = zc[ind[0], ind[1]]                                  # the piece's depth continued outwards
        hidden = lnd & ~M & (zc <= zext * (1 + CUT_MIN)) & (dist_out <= EXTEND)
        el, ne = ndi.label(M | hidden)
        E = np.isin(el, np.unique(el[M]))                          # only what hangs together with the piece
        zf = np.where(M, emb[y0:y1, x0:x1], np.maximum(zext, zc * 1.004 + 0.02))
        sil = ~E & (~lnd | (zc > zext * (1 + CUT_MIN)))            # true outline: sky or farther land
        d_b = ndi.distance_transform_edt(np.pad(E, 1))[1:-1, 1:-1]
        thick = THICK * np.maximum(d_b - 0.5, 0.3) * zf / cam.f
        thick = np.minimum(np.minimum(ndi.gaussian_filter(thick, 2.0), 0.4 * zf), THICK_CAP)
        zlp = norm_blur(np.where(E, zf, 0.0), E, 5.0)
        zb = np.maximum(zf + 0.3 * thick, zlp + thick)
        S = M & supported[y0:y1, x0:x1]
        verts, faces, uv, front, kind = relief_solid(cam, E, zf, zb, sil, S, x0, y0)
        ys, xs = np.nonzero(M)
        info = {"id": k, "depth": float(med_depth[k - 1]), "area": int(M.sum()),
                "x0": int(xs.min() + x0 - PAD), "y0": int(ys.min() + y0 - PAD),
                "x1": int(xs.max() + x0 + 1 - PAD), "y1": int(ys.max() + y0 + 1 - PAD)}
        info["cx"], info["cy"] = 0.5 * (info["x0"] + info["x1"]), 0.5 * (info["y0"] + info["y1"])
        g_ = next(name for name, test in GROUPS if test(info))
        info["group"] = g_
        index.append(info)
        G = groups[g_]
        G["verts"].append(verts)
        G["faces"].append(faces + G["nv"])
        G["uv"].append(uv)
        G["front"].append(front)
        G["kind"].append(kind)
        G["nv"] += len(verts)
    print(f"formation solids built ({time.time() - t0:.1f} s)")

    def attributes(uv, verts):
        """uv: padded-picture coordinates per vertex."""
        x, y = uv[:, 0], uv[:, 1]
        return {"ref_uv": np.stack([(x - PAD) / W, 1 - (y - PAD) / H], 1).astype(np.float32),
                "dist": np.linalg.norm(verts - cam.pos, axis=1).astype(np.float32),
                "veg": bilinear(vegP, x, y).astype(np.float32), "moss": bilinear(mossP, x, y).astype(np.float32),
                "mist": bilinear(mistP, x, y).astype(np.float32)}

    summary = {}
    for g_, G in groups.items():
        path = os.path.join(OUT, f"rocks_{g_}.npz")
        if not G["verts"]:
            if os.path.exists(path):
                os.remove(path)
            continue
        verts, faces = np.concatenate(G["verts"]), np.concatenate(G["faces"])
        uv, front, kind = np.concatenate(G["uv"]), np.concatenate(G["front"]), np.concatenate(G["kind"])
        np.savez(path, verts=verts, faces=faces, front=front, face_kind=kind, **attributes(uv, verts))
        summary[g_] = {"verts": int(len(verts)), "faces": int(len(faces)), "curtain_faces": int((kind == 3).sum()),
                       "formations": sum(1 for f in index if f["group"] == g_)}
        print(f"  rocks_{g_}: {len(verts)} verts, {len(faces)} quads ({summary[g_]['curtain_faces']} curtain), "
              f"{summary[g_]['formations']} formations")

    # --- terrain: one sheet under everything below the horizon ---------------------------------------
    hT = hF[v_top:]
    eT = eP[v_top:] * 0.35
    hh, ww = hT.shape
    CU, CV = np.meshgrid(np.arange(ww + 1, dtype=np.float64), np.arange(hh + 1, dtype=np.float64) + v_top)

    def corners(arr):
        ap = np.pad(arr, 1, mode="edge")
        return 0.25 * (ap[:-1, :-1] + ap[:-1, 1:] + ap[1:, :-1] + ap[1:, 1:])
    hc = corners(hT)
    zc_ = cam.ground_z(CV, 0.0) * (cam.cam_h - hc) / cam.cam_h
    zc_ = zc_ * (1.0 - emboss_k * corners(eT))
    pts = cam.unproject(CU, CV, zc_)
    nvr, nvc = hh + 1, ww + 1
    vid = np.arange(nvr * nvc).reshape(nvr, nvc)
    quads = np.stack([vid[:-1, :-1], vid[1:, :-1], vid[1:, 1:], vid[:-1, 1:]], -1).reshape(-1, 4)
    verts = pts.reshape(-1, 3)
    # apron: flat ground from the sheet's border out to 30 km. Each side of the sheet is pushed its own
    # way (the far edge on along the view, the sides sideways, the near edge back under the camera).
    border = np.concatenate([vid[0, :], vid[1:, -1], vid[-1, -2::-1], vid[-2:0:-1, 0]])
    bp = verts[border]
    n_far, n_right, n_near = nvc, nvr - 1, nvc - 1
    away = bp[:, :2] - cam.pos[:2]
    away /= np.maximum(np.linalg.norm(away, axis=1, keepdims=True), 1e-6)
    dirs = away.copy()                                              # far edge: on along the view
    dirs[n_far:n_far + n_right] = (0.76, -0.65)                     # right edge: out to the right
    dirs[n_far + n_right:n_far + n_right + n_near] = (0.0, -1.0)    # near edge: back
    dirs[n_far + n_right + n_near:] = (-0.76, -0.65)                # left edge: out to the left
    ap = np.concatenate([bp[:, :2] + dirs * 30000.0, np.full((len(border), 1), GROUND_Z)], 1)
    sid = np.arange(len(border)) + len(verts)
    nb_ = np.roll(np.arange(len(border)), -1)
    apron = np.stack([border, sid, sid[nb_], border[nb_]], 1)
    tv = np.concatenate([verts, ap]).astype(np.float32)
    tf = np.concatenate([quads, apron]).astype(np.int32)
    tuv = np.concatenate([np.stack([CU.ravel(), CV.ravel()], 1), np.stack([CU.ravel()[border], CV.ravel()[border]], 1)])
    at = attributes(tuv, tv)
    z0 = np.zeros(len(border))
    seen = np.concatenate([corners(known[v_top:].astype(np.float64)).ravel(), z0]).astype(np.float32)
    wet = np.concatenate([corners((np.exp(-d_out / 6.0) * (~wat) + wat)[v_top:]).ravel(), z0]).astype(np.float32)
    np.savez(os.path.join(OUT, "terrain.npz"), verts=tv, faces=tf, front=np.ones(len(tv), np.float32),
             seen=seen, wet=wet, **at)
    summary["terrain"] = {"verts": int(len(tv)), "faces": int(len(tf))}
    print(f"  terrain: {len(tv)} verts, {len(tf)} quads; height {hT.min():.2f}..{hT.max():.2f} m ({time.time() - t0:.1f} s)")

    # --- water: the plane z = 0 under the sheet --------------------------------------------------------
    quad_uv = np.array([[2.0, v_top + 1.0], [Wp - 2.0, v_top + 1.0], [Wp - 2.0, Hp - 2.0], [2.0, Hp - 2.0]])
    wv = cam.unproject(quad_uv[:, 0], quad_uv[:, 1], cam.ground_z(quad_uv[:, 1], 0.0)).astype(np.float32)
    wv[:, 2] = 0.0
    np.savez(os.path.join(OUT, "water.npz"), verts=wv, faces=np.array([[0, 3, 2, 1]], np.int32),
             front=np.ones(4, np.float32), **attributes(quad_uv, wv))
    summary["water"] = {"verts": 4, "faces": 1}

    with open(os.path.join(OUT, "rocks.json"), "w") as fh:
        json.dump({"groups": [g_ for g_, _ in GROUPS], "summary": summary, "ground_z": GROUND_Z, "pad": PAD,
                   "formations": sorted(index, key=lambda f: -f["area"])}, fh, indent=1)
    print("groups:", json.dumps(summary))

    if debug:
        dbg = os.path.join(cvlib.ROOT, "renders", "meshes")
        os.makedirs(dbg, exist_ok=True)
        rng = np.random.default_rng(5)
        gcol = {g_: rng.integers(60, 255, 3) for g_, _ in GROUPS}
        gid = {f["id"]: f["group"] for f in index}
        pal = np.zeros((n + 1, 3))
        for k in range(1, n + 1):
            pal[k] = np.clip(gcol[gid[k]] + rng.integers(-55, 55, 3), 0, 255)
        refP = np.pad(ref, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
        ov = refP * 255 * 0.35 + pal[lab] * 0.65
        ov[floorP] = refP[floorP] * 255 * 0.5 + np.array([0, 160, 255]) * 0.5
        ov[~landP] = refP[~landP] * 255 * 0.4
        edge = (lab != np.roll(lab, 1, 0)) | (lab != np.roll(lab, 1, 1))
        ov[edge & form] = (0, 0, 0)
        ov[~inframe] *= 0.6
        Image.fromarray(np.clip(ov, 0, 255).astype(np.uint8)).save(os.path.join(dbg, "formations.png"))
        sv = refP * 255 * 0.5
        sv[supported] = sv[supported] * 0.5 + np.array([0, 255, 0]) * 0.5
        sv[landP & ~supported] = sv[landP & ~supported] * 0.5 + np.array([255, 0, 0]) * 0.5
        Image.fromarray(np.clip(sv, 0, 255).astype(np.uint8)).save(os.path.join(dbg, "supported.png"))
        print("debug pictures in", dbg)
    print(f"done in {time.time() - t0:.1f} s")


if __name__ == "__main__":
    main()
