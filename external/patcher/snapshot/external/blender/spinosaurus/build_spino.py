"""The spinosaurus of reference/reference.png, modelled in the picture's pose.

  blender -b --factory-startup --python external/blender/spinosaurus/build_spino.py [-- draft]
Saves spinosaurus.blend and renders/view.png (through the picture's camera, cam.py);
tools/compare.py puts the render beside the picture. "draft": a coarser skin and a quicker render.

Every size below is written in the picture's pixels and turned into metres through the camera
(U(pixel, y): the point of the plane y = const seen there; the spine, sail and head are on y = 0, each
limb on its own plane). The animal faces +x, its left is +y, the ground is z = 0.

How it is made:
  skin     the body (tail to snout), lower jaw, legs, arms, toes and fingers are tubes of rings
           (SKIN: every part with what it is and where along it each point lies), fused into one
           seamless surface by a voxel remesh and smoothed -> SPINO_Skin
  paint    each skin point looks up the part it came from and is coloured by rule (paint(): tail
           stripes, dark back, tan belly, the neck's orange and black, the head, the mouth) into
           the colour attribute "Col"; the material adds scales (bump, cracks, shade) on top
  sail     a thin fan on the back with a rib and a scallop per spine, painted in bands
  rest     neck and tail spikes, teeth, claws, tongue, eyes, nostrils - separate objects
All objects are in the collection "Spinosaurus", children of the empty SPINO_Root. Nothing of the
picture is in the model."""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cam  # noqa: E402

V = Vector
Xv, Yv, Zv = V((1, 0, 0)), V((0, 1, 0)), V((0, 0, 1))
COLL = "Spinosaurus"
NEAR, FAR = -1, 1            # the side toward the camera is the animal's right (y < 0)


def U(p, y=0.0):
    return V(cam.U(p[0], p[1], y))


def coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def cr(vals, sub):
    """Catmull-Rom through the values (numbers or vectors), sub pieces per span."""
    out, n = [], len(vals)
    for i in range(n - 1):
        p1, p2 = vals[i], vals[i + 1]
        p0 = vals[i - 1] if i > 0 else p1 + (p1 - p2)
        p3 = vals[i + 2] if i + 2 < n else p2 + (p2 - p1)
        for k in range(sub):
            t = k / sub
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3))
    out.append(vals[-1])
    return out


def ring(c, up, side, ru, rs, n=40, e=2.3, pinch=0.0):
    """n points round c: ru along `up` (the first point), rs along `side`; e: 2 an ellipse, more =
    boxier; pinch: narrows the upper half."""
    out = []
    for k in range(n):
        a = 2 * math.pi * k / n
        ca, sa = math.cos(a), math.sin(a)
        cu = math.copysign(abs(ca) ** (2 / e), ca)
        su = math.copysign(abs(sa) ** (2 / e), sa)
        out.append(c + up * (ru * cu) + side * (rs * su * (1 - pinch * max(cu, 0.0) ** 1.5)))
    return out


# ---------------------------------------------------------------- the skin's parts

PARTS = ["trunk", "jaw", "leg", "arm", "digit", "brow", "gape"]


class Soup:
    """Rings skinned into closed shells, each point remembering its part, how far along the part
    it is (t) and where round its ring (dv: 1 = top / front, -1 = underside)."""

    def __init__(self):
        self.v, self.f, self.part, self.t, self.dv = [], [], [], [], []

    def loft(self, rings, part, ts):
        n, o, pid = len(rings[0]), len(self.v), PARTS.index(part)
        for r, t in zip(rings, ts):
            for k, p in enumerate(r):
                self.v.append(p)
                self.part.append(pid)
                self.t.append(t)
                self.dv.append(math.cos(2 * math.pi * k / n))
        for i in range(len(rings) - 1):
            for j in range(n):
                k = (j + 1) % n
                self.f.append((o + i * n + j, o + i * n + k, o + (i + 1) * n + k, o + (i + 1) * n + j))
        for r, base, t in ((rings[0], o, ts[0]), (rings[-1], o + (len(rings) - 1) * n, ts[-1])):
            self.v.append(sum(r, V()) / n)
            self.part.append(pid)
            self.t.append(t)
            self.dv.append(0.0)
            ci = len(self.v) - 1
            for j in range(n):
                self.f.append((base + j, base + (j + 1) % n, ci))


def stations(soup, st, part, sub=8, n=48):
    """A body made of stations across it: (top pixel, bottom pixel, half width in metres, boxiness,
    pinch). Returns its dense top points, bottom points and the length along it at each (m)."""
    T = cr([U(s[0]) for s in st], sub)
    B = cr([U(s[1]) for s in st], sub)
    HW, E, PN = cr([s[2] for s in st], sub), cr([s[3] for s in st], sub), cr([s[4] for s in st], sub)
    rings, cs = [], []
    for tp, bt, hw, e, pn in zip(T, B, HW, E, PN):
        d = tp - bt
        rings.append(ring((tp + bt) / 2, d.normalized(), Yv, d.length / 2, max(hw, 0.006), n, max(e, 2.0), max(pn, 0.0)))
        cs.append((tp + bt) / 2)
    arc = [0.0]
    for a, b in zip(cs, cs[1:]):
        arc.append(arc[-1] + (b - a).length)
    soup.loft(rings, part, arc)
    return T, B, arc


def tube(soup, part, pts, radii, lat=0.85, n=24, sub=5, t0=0.0, t1=1.0):
    """A limb: rings along the smoothed path; radii in the plane it bends in, lat x that sideways."""
    Pn, R = cr(pts, sub), cr(radii, sub)
    L = cr(lat, sub) if isinstance(lat, list) else [lat] * len(Pn)
    rings = []
    for i, p in enumerate(Pn):
        tg = (Pn[min(i + 1, len(Pn) - 1)] - Pn[max(i - 1, 0)]).normalized()
        side = Yv - tg * tg.dot(Yv)
        side = side.normalized() if side.length > 1e-4 else Xv
        r = max(R[i], 0.004)
        rings.append(ring(p, side.cross(tg), side, r, r * L[i], n, 2.0))
    soup.loft(rings, part, [t0 + (t1 - t0) * i / (len(Pn) - 1) for i in range(len(Pn))])


def limb(soup, part, pts, y0, y1, lat=0.85, **kw):
    """A limb drawn in the picture: (pixel x, pixel y, radius in pixels) points, on planes from
    y0 (its first point) to y1 (its last)."""
    P = [U(p, y0 + (y1 - y0) * i / (len(pts) - 1)) for i, p in enumerate(pts)]
    tube(soup, part, P, [p[2] * cam.mpp(q) for p, q in zip(pts, P)], lat, **kw)
    return P


# the body from the tail's tip to the snout: (top, bottom, half width, boxiness, pinch)
TRUNK = [
    ((58, 553), (64, 549), 0.012, 2.0, 0.0), ((28, 520), (50, 512), 0.05, 2.0, 0.0), ((6, 480), (38, 478), 0.07, 2.0, 0.0),
    ((12, 440), (40, 455), 0.09, 2.0, 0.0), ((40, 418), (55, 452), 0.11, 2.0, 0.1), ((95, 408), (95, 487), 0.20, 2.0, 0.2),
    ((190, 398), (185, 518), 0.30, 2.1, 0.3), ((286, 386), (280, 541), 0.40, 2.1, 0.35), ((380, 376), (375, 555), 0.50, 2.2, 0.35),
    ((455, 366), (455, 578), 0.62, 2.2, 0.35),                                                         # 9: the tail's base
    ((524, 333), (535, 600), 0.78, 2.3, 0.35), ((619, 295), (625, 618), 0.88, 2.3, 0.35), ((714, 281), (720, 630), 0.92, 2.3, 0.35),
    ((810, 267), (815, 628), 0.92, 2.3, 0.35), ((900, 264), (905, 586), 0.85, 2.3, 0.35), ((975, 262), (1018, 568), 0.74, 2.3, 0.3),
    ((1040, 245), (1070, 528), 0.60, 2.2, 0.25),                                                       # 16: the neck
    ((1082, 188), (1118, 455), 0.52, 2.2, 0.2), ((1132, 140), (1183, 380), 0.47, 2.2, 0.2), ((1192, 92), (1240, 335), 0.44, 2.2, 0.2),
    ((1262, 58), (1290, 200), 0.42, 2.5, 0.2),                                                         # 20: the back of the skull
    ((1326, 46), (1330, 172), 0.40, 2.7, 0.25), ((1398, 48), (1405, 160), 0.36, 2.7, 0.3), ((1493, 58), (1493, 148), 0.25, 2.6, 0.3),
    ((1588, 50), (1588, 129), 0.20, 2.5, 0.25), ((1650, 27), (1660, 108), 0.20, 2.5, 0.2), ((1715, 16), (1728, 100), 0.19, 2.4, 0.1),
    ((1762, 40), (1766, 92), 0.10, 2.2, 0.0),
]
TAIL_END, NECK_AT, HEAD_AT, EYE_AT, SNOUT_AT = 9, 16, 20, 22, 24
JAW = [
    ((1272, 205), (1262, 334), 0.40, 2.3, 0.0), ((1330, 222), (1320, 338), 0.38, 2.4, 0.0), ((1398, 245), (1392, 350), 0.33, 2.5, 0.0),
    ((1445, 270), (1449, 388), 0.27, 2.5, 0.0), ((1493, 308), (1499, 424), 0.21, 2.5, 0.0), ((1541, 346), (1549, 448), 0.17, 2.5, 0.0),
    ((1588, 380), (1592, 462), 0.15, 2.4, 0.0), ((1628, 408), (1628, 466), 0.13, 2.3, 0.0), ((1652, 428), (1652, 456), 0.06, 2.0, 0.0),
]
GAPE = [      # the cheeks and throat that close the back of the open mouth, narrowing to a rounded front
    ((1285, 180), (1290, 240), 0.38, 2.2, 0.0), ((1330, 168), (1336, 246), 0.36, 2.2, 0.0), ((1375, 166), (1385, 262), 0.31, 2.1, 0.0),
    ((1410, 170), (1422, 276), 0.21, 2.0, 0.0), ((1432, 188), (1442, 278), 0.07, 2.0, 0.0),
]
LAT = [0.5, 0.32, 0.40, 0.45, 0.6, 0.8, 0.85, 0.88, 0.9, 0.95]
LEG_NEAR = [(602, 296, 30), (592, 335, 72), (585, 372, 94), (558, 432, 90), (525, 500, 76), (495, 565, 66), (446, 640, 58), (384, 700, 54), (346, 750, 54), (326, 800, 68)]
LEG_FAR = [(650, 300, 30), (652, 340, 70), (655, 385, 90), (700, 470, 80), (730, 560, 62), (724, 614, 58), (706, 660, 54), (684, 704, 46), (676, 756, 44), (664, 812, 52)]
ARM_NEAR = [(915, 425, 34), (880, 440, 55), (790, 465, 55), (725, 505, 52), (775, 560, 48), (848, 608, 44), (880, 640, 44)]
ARM_FAR = [(1005, 510, 34), (1030, 535, 52), (1080, 585, 50), (1130, 630, 44), (1163, 662, 40), (1188, 690, 37), (1194, 712, 37)]
# fingers and toes: (plane y, the digit's pixels, its radius in pixels, the claw's three pixels)
FINGERS = [
    (-1.00, [(858, 640), (858, 712)], 26, [(858, 706), (855, 736), (864, 758)]),
    (-0.86, [(888, 650), (918, 734)], 29, [(916, 728), (920, 756), (929, 781)]),
    (-0.72, [(925, 635), (968, 698)], 28, [(966, 692), (979, 712), (976, 735)]),
    (0.66, [(1184, 700), (1144, 722)], 22, [(1148, 720), (1122, 730), (1112, 754)]),
    (0.80, [(1194, 706), (1178, 764)], 24, [(1180, 758), (1160, 794), (1131, 814)]),
    (0.94, [(1208, 706), (1208, 784)], 23, [(1208, 778), (1192, 824), (1157, 847)]),
]
TOES_FAR = [
    (0.52, [(668, 832), (716, 842)], 26, [(710, 842), (734, 842), (750, 858)]),
    (0.78, [(676, 830), (760, 840)], 27, [(754, 840), (786, 838), (806, 855)]),
    (1.00, [(682, 828), (800, 834)], 26, [(794, 834), (828, 830), (848, 848)]),
    (0.62, [(640, 770), (618, 798)], 20, [(620, 794), (603, 806), (602, 824)]),
]
TOES_NEAR = [(456, 1.08, 0.20), (376, 0.95, 0.21), (268, 0.86, 0.20), (236, 0.76, 0.17)]      # (the claw tip's pixel x, the toe's length, its radius)
CLAWS = []          # (three points, radius): filled as the digits are built


def build_soup():
    soup = Soup()
    T, B, arc = stations(soup, TRUNK, "trunk")
    stations(soup, JAW, "jaw", n=40)
    stations(soup, GAPE, "gape", sub=4, n=32)
    limb(soup, "leg", LEG_NEAR, -0.56, -0.80, LAT, n=32)
    limb(soup, "leg", LEG_FAR, 0.56, 0.80, LAT, n=32)
    limb(soup, "arm", ARM_NEAR, -0.50, -0.86)
    limb(soup, "arm", ARM_FAR, 0.50, 0.82)
    for y, pts, r, claw in FINGERS + TOES_FAR:
        P = [U(p, y) for p in pts]
        rm = r * cam.mpp(P[0])
        tube(soup, "digit", [P[0], (P[0] + P[1]) / 2 + Zv * 0.01, P[1]], [rm * 1.05, rm * 1.1, rm * 0.9], 0.9, n=16)
        CLAWS.append(([U(p, y) for p in claw], rm * 0.8))
    # the near foot's toes fan out toward the camera: each from the foot's end to where its claw shows
    base = U((326, 800), -0.80)
    rh, nh = V(cam.RIGHT), V((cam.D[0], cam.D[1], 0)).normalized()
    for px, L, r in TOES_NEAR:
        a = (px - 326) * cam.mpp(base)
        tip = base + rh * a + nh * math.sqrt(max(L * L - a * a, 0.01))
        tip.z = 0.04
        d = tip - base
        knuckle, end = base + d * 0.42 + Zv * 0.02, base + d * 0.66
        end.z = 0.21
        tube(soup, "digit", [base, knuckle, end], [r * 1.1, r * 1.1, r * 0.9], 0.9, n=16)
        CLAWS.append(([end - d * 0.04, end + d * 0.17 + Zv * 0.05, tip], r * 0.62))
    for side in (NEAR, FAR):          # the ridge over each eye
        tube(soup, "brow", [U(p, side * 0.27) for p in ((1335, 60), (1395, 64), (1445, 84))],
             [0.10, 0.11, 0.07], 0.75, n=16)
    return soup, T, B, arc


def make_skin(soup, voxel):
    me = bpy.data.meshes.new("SPINO_Skin")
    me.from_pydata([tuple(p) for p in soup.v], [], soup.f)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("SPINO_Skin", me)
    coll().objects.link(ob)
    m = ob.modifiers.new("Remesh", "REMESH")
    m.mode, m.voxel_size, m.adaptivity, m.use_smooth_shade = "VOXEL", voxel, 0.0, True
    s = ob.modifiers.new("Smooth", "SMOOTH")
    s.factor, s.iterations = 0.5, 8
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    new = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    ob.data = new
    bpy.data.meshes.remove(me)
    new.name = "SPINO_Skin"
    new.polygons.foreach_set("use_smooth", np.ones(len(new.polygons), bool))
    return ob


def transfer(ob, soup):
    """For every skin point: the part it came from, how far along it, where round it."""
    kd = KDTree(len(soup.v))
    for i, p in enumerate(soup.v):
        kd.insert(p, i)
    kd.balance()
    n = len(ob.data.vertices)
    co = np.empty(n * 3, np.float32)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    part, t, dv = np.empty(n, np.int32), np.empty(n), np.empty(n)
    sp, st, sd = soup.part, soup.t, soup.dv
    for i in range(n):
        res = kd.find_n(co[i], 4)
        p0 = sp[res[0][1]]
        w = tt = dd = 0.0
        for _, j, d in res:
            if sp[j] == p0:
                k = 1.0 / (d + 1e-4)
                w += k
                tt += k * st[j]
                dd += k * sd[j]
        part[i], t[i], dv[i] = p0, tt / w, dd / w
    return co.astype(np.float64), part, t, dv


# ---------------------------------------------------------------- paint

def C(h):
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)])
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)        # (linear, as colour attributes are)


PAL = {k: C(v) for k, v in dict(
    pale="#b98e50", tan="#a67434", ochre="#a9611e", brown="#5c3516", dbrown="#2c1a0d", black="#161312", grey="#32302d",
    orange="#d4590f", red="#a8240e", crimson="#851a0e", pink="#c05058", throat="#7a2428", cream="#e6cf8f").items()}


def _hash(ix, iy, iz, seed):
    h = (ix * np.uint64(374761393) + iy * np.uint64(668265263) + iz * np.uint64(2147483647) + np.uint64(seed * 1442695041 + 7)) & np.uint64(0xffffffff)
    h = ((h ^ (h >> np.uint64(13))) * np.uint64(1274126177)) & np.uint64(0xffffffff)
    return ((h ^ (h >> np.uint64(16))) & np.uint64(0xffff)).astype(np.float64) / 65535.0


def vnoise(P, seed):
    i = np.floor(P)
    f = P - i
    u = f * f * (3 - 2 * f)
    i = (i + 4096).astype(np.uint64)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out = out + w * _hash(i[:, 0] + np.uint64(dx), i[:, 1] + np.uint64(dy), i[:, 2] + np.uint64(dz), seed)
    return out


def fbm(P, freq, seed, octaves=3):
    """Cloudy noise, 0..1, about `freq` blobs per metre."""
    out, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        out = out + amp * vnoise(P * (freq * 2 ** o), seed + o * 17)
        tot += amp
        amp *= 0.5
    return out / tot


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    a = np.broadcast_to(a, (len(t), 3)) if np.ndim(a) == 1 else a
    return a + (np.asarray(b) - a) * np.asarray(t)[:, None]


def paint(P, part, t, dv, L):
    """The colour of every skin point. L: the length along the body at each of its stations."""
    n = len(P)
    h = (dv + 1) / 2
    f1, f2, f3 = fbm(P, 0.8, 1), fbm(P, 2.4, 2), fbm(P, 6.5, 3)
    blot = fbm(P, 3.4, 7, 2)
    streak = fbm(P * np.array([3.2, 3.2, 0.8]), 1.0, 4)                 # (tall, narrow marks)
    col = np.empty((n, 3))
    coarse = np.zeros(n)
    # --- the body
    base = mix(PAL["pale"], PAL["tan"], ss(0.08, 0.38, h))
    base = mix(base, PAL["ochre"], 0.6 * ss(0.45, 0.7, f2))
    # tail: black bars over tan and orange, a red ridge
    bar = 0.5 + 0.5 * np.sin(2 * np.pi * t / 0.175 + 7.0 * (f1 - 0.5))
    bars = ss(0.34, 0.52, bar) * ss(0.14, 0.40, h + 0.3 * (f3 - 0.5))
    tail = mix(base, PAL["orange"], 0.9 * ss(0.42, 0.56, blot) * ss(0.25, 0.45, h))
    tail = mix(tail, PAL["black"], bars)
    tail = mix(tail, PAL["red"], 0.8 * ss(0.88, 0.96, h))
    # torso: a black back, dark streaks down the flank, flecks of orange high up
    torso = mix(base, PAL["ochre"], 0.7 * ss(0.3, 0.5, h))
    torso = mix(torso, PAL["brown"], 0.6 * ss(0.45, 0.65, f1))
    torso = mix(torso, PAL["dbrown"], 0.9 * ss(0.44, 0.58, streak) * ss(0.26, 0.46, h))
    torso = mix(torso, PAL["black"], ss(0.56, 0.74, h + 0.30 * (f2 - 0.5)))
    torso = mix(torso, PAL["orange"], 0.8 * ss(0.56, 0.66, blot) * ss(0.82, 0.92, h))
    # neck: black with orange and red blotches above, pale below, the edge between them toothed
    edge = h + 0.07 * np.sin(2 * np.pi * t / 0.24) + 0.22 * (f2 - 0.5)
    upper = mix(PAL["black"], PAL["orange"], ss(0.50, 0.58, blot))
    upper = mix(upper, PAL["red"], ss(0.62, 0.70, blot))
    upper = mix(upper, PAL["red"], 0.7 * ss(0.9, 0.97, h))
    neck = mix(mix(PAL["pale"], PAL["tan"], 0.6 * ss(0.4, 0.7, f3)), upper, ss(0.44, 0.52, edge))
    # head: dark grey over the skull and round the eye, a brown mottled snout, the mouth inside
    along = ss(L[EYE_AT], L[SNOUT_AT], t)
    thr = 0.40 + 0.42 * along
    head = mix(PAL["tan"], PAL["brown"], 0.75 * ss(0.4, 0.62, f3))
    head = mix(head, PAL["dbrown"], 0.6 * ss(0.55, 0.7, f2))
    head = mix(head, mix(PAL["grey"], PAL["black"], ss(0.4, 0.6, f3)), ss(thr - 0.06, thr + 0.08, h + 0.16 * (f2 - 0.5)))
    band = ss(L[EYE_AT] + 0.1, L[EYE_AT] - 0.2, t) * ss(0.25, 0.4, h + 0.25 * ss(L[EYE_AT] - 0.1, L[HEAD_AT], t))
    head = mix(head, PAL["grey"], 0.85 * band)
    head = mix(head, PAL["dbrown"], 0.7 * ss(L[SNOUT_AT + 1], L[-1], t))
    head = mix(head, PAL["dbrown"], 0.8 * ss(-0.30, -0.45, dv) * (1 - ss(-0.55, -0.7, dv)))      # the dark lip
    mouth = mix(PAL["pink"], PAL["throat"], ss(L[EYE_AT + 1], L[HEAD_AT], t))
    head = mix(head, mouth, ss(-0.52, -0.66, dv))
    w_tail = 1 - ss(L[TAIL_END] - 0.5, L[TAIL_END] + 0.7, t)
    w_neck = ss(L[NECK_AT - 1] - 0.2, L[NECK_AT], t)
    w_head = ss(L[HEAD_AT - 1], L[HEAD_AT], t)
    body = mix(mix(torso, tail, w_tail), neck, w_neck)
    body = body * (0.66 + 0.34 * ss(-0.85, -0.25, dv))[:, None]                # (the underside in shade)
    body = mix(body, head, w_head)
    k = part == PARTS.index("trunk")
    col[k] = body[k]
    coarse[k] = (0.25 + 0.5 * w_head)[k]
    # --- the lower jaw: pebbled grey-brown, pale under, a dark rim, the mouth's floor inside
    jaw = mix(PAL["pale"], PAL["ochre"], ss(0.3, 0.6, h))
    jaw = mix(jaw, PAL["brown"], 0.7 * ss(0.42, 0.62, f3))
    jaw = mix(jaw, PAL["dbrown"], 0.8 * ss(0.68, 0.78, h))
    jaw = mix(jaw, mix(PAL["pink"], PAL["throat"], ss(1.6, 0.2, t)), ss(0.80, 0.9, h))
    k = part == PARTS.index("jaw")
    col[k], coarse[k] = jaw[k], 0.9
    # --- legs: the thigh like the flank, darker and coarser toward the foot
    leg = mix(mix(PAL["tan"], PAL["ochre"], ss(0.35, 0.55, f2)), PAL["brown"], 0.62 + 0.3 * ss(0.4, 0.6, f1))
    leg = mix(leg, PAL["dbrown"], 0.6 * ss(0.5, 0.64, f3) * (1 - ss(0.3, 0.5, t)))
    leg = mix(leg, PAL["black"], ss(0.17, 0.07, t + 0.06 * (f2 - 0.5)))
    leg = mix(leg, mix(PAL["dbrown"], PAL["brown"], ss(0.5, 0.7, f3)), ss(0.28, 0.55, t))
    k = part == PARTS.index("leg")
    col[k], coarse[k] = leg[k], (0.4 + 0.6 * ss(0.2, 0.6, t))[k]
    arm = mix(mix(PAL["ochre"], PAL["brown"], 0.4 + 0.6 * ss(0.4, 0.65, f2)), PAL["dbrown"], 0.7 * ss(0.46, 0.64, f3))
    arm = mix(arm, PAL["grey"], 0.7 * (1 - ss(0.0, 0.18, t)))
    arm = mix(arm, PAL["dbrown"], 0.6 * ss(0.6, 0.95, t))
    k = part == PARTS.index("arm")
    col[k], coarse[k] = arm[k], 0.8
    k = part == PARTS.index("digit")
    col[k], coarse[k] = mix(PAL["dbrown"], PAL["brown"], 0.6 * ss(0.4, 0.7, f3))[k], 1.0
    k = part == PARTS.index("gape")
    col[k], coarse[k] = mix(mix(PAL["pink"], PAL["throat"], 0.6 * ss(0.45, 0.6, f2)), PAL["throat"] * 0.15, ss(0.6, 0.98, t))[k], 0.0
    k = part == PARTS.index("brow")
    col[k], coarse[k] = mix(PAL["grey"], PAL["black"], ss(0.4, 0.6, f3))[k], 0.6
    return col, coarse


def colored(name, verts, faces, col, coarse=0.3, smooth=True):
    """A mesh object carrying the colour attribute "Col" and the scale size "coarse"."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in verts], [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    set_colors(ob, col, coarse)
    me.polygons.foreach_set("use_smooth", np.full(len(me.polygons), smooth, bool))
    me.materials.append(bpy.data.materials["SPINO_Skin"])
    return ob


def set_colors(ob, col, coarse):
    me = ob.data
    n = len(me.vertices)
    c4 = np.ones((n, 4), np.float32)
    c4[:, :3] = np.broadcast_to(col, (n, 3))
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT").data.foreach_set("color", c4.ravel())
    me.attributes.new("coarse", "FLOAT", "POINT").data.foreach_set("value", np.broadcast_to(np.asarray(coarse, np.float32), (n,)).copy())


# ---------------------------------------------------------------- sail, spikes

SAIL_BASE = [(300, 392), (380, 386), (428, 380), (524, 343), (619, 305), (714, 291), (810, 277), (900, 274), (975, 272), (1035, 266)]
SAIL_EDGE = [(300, 384), (364, 326), (410, 270), (436, 214), (486, 150), (516, 100), (574, 50), (620, 29), (714, 12), (764, 5), (836, 28),
             (900, 83), (946, 155), (968, 210), (1000, 248), (1035, 262)]
SPINES = 44


def resample(pts, n):
    P = cr(pts, 12)
    d = [0.0]
    for a, b in zip(P, P[1:]):
        d.append(d[-1] + (b - a).length)
    out, j = [], 0
    for i in range(n + 1):
        s = d[-1] * i / n
        while j < len(d) - 2 and d[j + 1] < s:
            j += 1
        f = (s - d[j]) / max(d[j + 1] - d[j], 1e-9)
        out.append(P[j].lerp(P[j + 1], min(max(f, 0.0), 1.0)))
    return out


def sail():
    nu, nv = 660, 56
    base, edge = resample([U(p) for p in SAIL_BASE], nu), resample([U(p) for p in SAIL_EDGE], nu)
    verts, us, vs, faces = [], [], [], []
    n = 2 * (nv + 1)
    for i in range(nu + 1):
        u = i / nu
        ph = u * SPINES
        d = abs(ph - round(ph)) * 2                           # 0 on a spine, 1 between two
        top = base[i].lerp(edge[i], 1 - 0.035 * d * d)        # (the edge dips between the spines)
        for side in (1, -1):
            for j in (range(nv + 1) if side == 1 else range(nv, -1, -1)):
                v = j / nv
                th = (0.17 + (0.028 - 0.17) * v ** 0.55) * (0.7 + 0.6 * (1 - d) ** 3)
                verts.append(base[i].lerp(top, v) + Yv * (side * th / 2))
                us.append(u)
                vs.append(v)
    for i in range(nu):
        for j in range(n):
            k = (j + 1) % n
            faces.append((i * n + j, i * n + k, (i + 1) * n + k, (i + 1) * n + j))
    faces += [tuple(range(n)), tuple(range(nu * n, (nu + 1) * n))]
    u, v = np.array(us), np.array(vs)
    P = np.array([tuple(p) for p in verts])
    Q = np.stack([u * 9.0, v * 3.0, np.zeros(len(u))], axis=1)                 # (the sail unrolled, about metres)
    b1, b2, b3 = fbm(Q, 1.3, 11), fbm(Q, 3.2, 12), fbm(Q * np.array([1.0, 0.35, 1.0]), 6.0, 13)
    col = mix(PAL["orange"], PAL["tan"], 0.85 * ss(0.52, 0.68, b1))
    col = mix(col, PAL["red"], 0.85 * ss(0.5, 0.66, b2) * (1 - ss(0.3, 0.6, u) * ss(0.45, 0.6, v) * (1 - ss(0.75, 0.85, v))))
    band = ss(0.30, 0.36, v + 0.10 * (b1 - 0.5)) * (1 - ss(0.42, 0.50, v + 0.10 * (b1 - 0.5)))
    col = mix(col, mix(PAL["crimson"], PAL["black"], ss(0.45, 0.6, b3)), 0.85 * band)
    col = mix(col, PAL["red"], 0.9 * ss(0.80, 0.93, v + 0.08 * (b2 - 0.5)))
    col = mix(col, PAL["orange"], 0.5 * ss(0.95, 1.0, v))
    ph = u * SPINES
    between = np.abs(ph - np.round(ph)) * 2
    col = mix(col, PAL["black"], 0.7 * ss(0.62, 0.95, between) * (1 - 0.45 * v))        # dark creases between the spines
    col = mix(col, PAL["black"], ss(0.27, 0.10, v + 0.10 * (b3 - 0.5)))                 # the dark foot of the sail
    return colored("SPINO_Sail", verts, faces, col.astype(np.float32), 0.15)


def cone_rings(base, tip, along, w_along, w_lat, bend=None, steps=7, n=10):
    """A flattened, pointed spike: its base w_along wide along the body, w_lat thick."""
    axis = tip - base
    side = Yv
    al = (along - axis * along.dot(axis) / axis.length_squared).normalized()
    rings = []
    for i in range(steps):
        f = i / (steps - 1)
        k = (1 - f) ** 0.85 * 0.97 + 0.03
        c = base + axis * f + (bend or V()) * math.sin(math.pi * f)
        rings.append([c + al * (w_along * k * math.cos(2 * math.pi * j / n)) + side * (w_lat * k * math.sin(2 * math.pi * j / n)) for j in range(n)])
    return rings


def add_rings(V_, F_, rings):
    n, o = len(rings[0]), len(V_)
    for r in rings:
        V_ += r
    for i in range(len(rings) - 1):
        for j in range(n):
            k = (j + 1) % n
            F_.append((o + i * n + j, o + i * n + k, o + (i + 1) * n + k, o + (i + 1) * n + j))
    F_.append(tuple(range(o, o + n)))
    F_.append(tuple(range(o + (len(rings) - 1) * n, o + len(rings) * n)))
    return o, len(V_)


def spikes(T, arc, L):
    """Spikes along the neck (large, swept back, dark) and the tail's ridge (small, red)."""
    Vs, Fs, cols = [], [], []

    def at(s):
        i = min(range(len(arc)), key=lambda q: abs(arc[q] - s))
        i = min(max(i, 1), len(arc) - 2)
        tg = (T[i + 1] - T[i - 1]).normalized()
        return T[i], tg, V((-tg.z, 0, tg.x))
    s0, s1 = L[NECK_AT] - 0.1, L[EYE_AT] + 0.25
    lengths = [0.10, 0.14, 0.20, 0.26, 0.32, 0.38, 0.44, 0.50, 0.54, 0.52, 0.46, 0.38, 0.30, 0.24, 0.20, 0.17, 0.14]
    for i, ln in enumerate(lengths):
        p, tg, nrm = at(s0 + (s1 - s0) * i / (len(lengths) - 1))
        d = (nrm * (0.42 + 0.3 * i / 16) - tg * 0.9).normalized()
        a, b = add_rings(Vs, Fs, cone_rings(p - nrm * 0.06, p + d * ln, tg, 0.085 + ln * 0.13, 0.035, bend=-tg * ln * 0.10))
        base = PAL["orange"] if i % 3 == 1 else PAL["dbrown"]
        for q in range(a, b):
            f = min(max(((Vs[q] - p).length) / ln, 0), 1)
            cols.append(base + (PAL["black"] - base) * min(f * 1.6, 1.0))
    s0, s1 = 0.35, L[TAIL_END] - 0.9
    for i in range(34):
        f = i / 33
        p, tg, nrm = at(s0 + (s1 - s0) * f)
        ln = 0.05 + 0.10 * f
        d = (nrm - tg * 0.35).normalized()
        a, b = add_rings(Vs, Fs, cone_rings(p - nrm * 0.03, p + d * ln, tg, 0.035 + 0.035 * f, 0.02, steps=4, n=8))
        cols += [PAL["red"]] * (b - a)
    return colored("SPINO_Spikes", Vs, Fs, np.array(cols, np.float32), 0.2)


# ---------------------------------------------------------------- claws, teeth, tongue, eyes

def simple(name, V_, F_, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in V_], [], F_)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", np.full(len(me.polygons), smooth, bool))
    me.materials.append(bpy.data.materials[mat])
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    return ob


def horn_rings(pts, r, lat=0.62, n=12, power=0.8):
    """A curved, pointed horn through the points (a claw, a tooth)."""
    Pn = cr(pts, 6)
    rings = []
    for i, p in enumerate(Pn):
        f = i / (len(Pn) - 1)
        tg = (Pn[min(i + 1, len(Pn) - 1)] - Pn[max(i - 1, 0)]).normalized()
        side = Yv - tg * tg.dot(Yv)
        side = side.normalized() if side.length > 1e-4 else Xv
        up = side.cross(tg)
        k = r * ((1 - f) ** power * 0.97 + 0.03)
        rings.append([p + up * (k * math.cos(2 * math.pi * j / n)) + side * (k * lat * math.sin(2 * math.pi * j / n)) for j in range(n)])
    return rings


def claws():
    Vs, Fs = [], []
    for pts, r in CLAWS:
        add_rings(Vs, Fs, horn_rings(pts, r))
    return simple("SPINO_Claws", Vs, Fs, "SPINO_Horn")


def along(poly, t):
    """The point a fraction t along a polyline of pixels."""
    d = [0.0]
    for a, b in zip(poly, poly[1:]):
        d.append(d[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    s = t * d[-1]
    for i in range(len(poly) - 1):
        if s <= d[i + 1] or i == len(poly) - 2:
            f = (s - d[i]) / (d[i + 1] - d[i])
            return (poly[i][0] + (poly[i + 1][0] - poly[i][0]) * f, poly[i][1] + (poly[i + 1][1] - poly[i][1]) * f)


UPPER_LINE = [(1310, 180), (1421, 159), (1493, 150), (1588, 131), (1683, 104), (1750, 99)]
LOWER_LINE = [(1405, 248), (1445, 272), (1493, 310), (1541, 348), (1588, 382), (1640, 414)]
UPPER_TEETH = [10, 12, 15, 17, 20, 22, 25, 30, 27, 37, 32, 52, 35, 42, 56, 37, 50, 40, 30, 22]     # lengths in pixels, back to front
LOWER_TEETH = [10, 13, 16, 18, 21, 23, 26, 29, 23, 31, 26, 34, 29, 34, 31, 26, 21, 16]


def teeth(bvh):
    Vs, Fs = [], []
    for line, lens, sgn in ((UPPER_LINE, UPPER_TEETH, -1), (LOWER_LINE, LOWER_TEETH, 1)):
        for i, ln in enumerate(lens):
            t = i / (len(lens) - 1)
            a, b = U(along(line, max(t - 0.02, 0))), U(along(line, min(t + 0.02, 1)))
            p = (a + b) / 2
            tg = (b - a).normalized()
            out = V((-tg.z, 0, tg.x)) * sgn                    # the way the tooth points: away from its jaw
            lm = ln * cam.mpp(p)
            for side in (NEAR, FAR):
                o = p - out * 0.05 + Yv * (side * 3.0)
                hit = bvh.ray_cast(o, Yv * -side)[0]
                if hit is None or abs(hit.y) < 0.02:
                    continue
                base = V((hit.x, hit.y * 0.86, hit.z)) - out * 0.02
                tip = base + out * lm - tg * (0.12 * lm) + Yv * (-side * 0.02)
                add_rings(Vs, Fs, horn_rings([base, base.lerp(tip, 0.5) + tg * (0.05 * lm), tip], max(lm * 0.25, 0.02), lat=0.85, n=10, power=0.9))
    return simple("SPINO_Teeth", Vs, Fs, "SPINO_Tooth")


def tongue():
    pts = [(1295, 250, 26), (1370, 268, 30), (1440, 300, 26), (1500, 334, 17), (1532, 354, 7)]
    P = cr([U(p) for p in pts], 6)
    R = cr([p[2] * cam.K for p in pts], 6)
    rings = []
    for i, p in enumerate(P):
        tg = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        rings.append(ring(p, Yv.cross(tg) * -1, Yv, max(R[i], 0.01) * 0.75, max(R[i], 0.01) * 1.5, 20, 2.0))
    Vs, Fs = [], []
    add_rings(Vs, Fs, rings)
    return simple("SPINO_Tongue", Vs, Fs, "SPINO_Tongue")


def ball_data(c, ax, ay, az, n=16, rows=10):
    """A stretched ball: its three half axes as vectors."""
    Vs, Fs = [], []
    rings = []
    for i in range(1, rows):
        a = math.pi * i / rows
        rings.append([c + az * math.cos(a) + (ax * math.cos(2 * math.pi * j / n) + ay * math.sin(2 * math.pi * j / n)) * math.sin(a) for j in range(n)])
    add_rings(Vs, Fs, rings)
    return Vs, Fs


def eyes(bvh):
    """An eye on each side where the picture has it, a nostril on each side of the snout's end."""
    c = V(cam.location())
    made = []
    for name, px, kind in (("Eye", (1400, 88), "eye"), ("Nostril", (1667, 38), "nostril")):
        d = V(cam._ray(*px)).normalized()
        hit, nrm = bvh.ray_cast(c, d)[:2]
        if hit is None:
            print("no skin under the", name)
            continue
        for side, tag in ((1, "R"), (-1, "L")):                # (the hit is on the right side; mirror it for the left)
            h, n = V((hit.x, hit.y * side, hit.z)), V((nrm.x, nrm.y * side, nrm.z))
            t1 = n.cross(Zv).normalized()
            t2 = t1.cross(n)
            if kind == "eye":
                made.append(simple("SPINO_Eye." + tag, *ball_data(h - n * 0.035, t1 * 0.078, t2 * 0.078, n * 0.078), "SPINO_Eye"))
                made.append(simple("SPINO_Pupil." + tag, *ball_data(h + n * 0.034, t1 * 0.02, t2 * 0.045, n * 0.012, 12, 6), "SPINO_Black"))
                lid_v, lid_f = [], []
                rings = []
                for i in range(20):                              # the lid: a dark ring round the eye
                    a = 2 * math.pi * i / 20
                    cc = h + n * 0.008 + (t1 * 1.25 * math.cos(a) + t2 * 0.85 * math.sin(a)) * 0.082
                    rad = (t1 * math.cos(a) + t2 * math.sin(a))
                    rings.append([cc + (rad * math.cos(2 * math.pi * j / 8) + n * math.sin(2 * math.pi * j / 8)) * 0.03 for j in range(8)])
                for i in range(20):
                    o = len(lid_v)
                    lid_v += rings[i]
                    for j in range(8):
                        lid_f.append((i * 8 + j, i * 8 + (j + 1) % 8, ((i + 1) % 20) * 8 + (j + 1) % 8, ((i + 1) % 20) * 8 + j))
                made.append(colored("SPINO_Lid." + tag, lid_v, lid_f, PAL["black"].astype(np.float32), 0.0))
            else:
                made.append(simple("SPINO_Nostril." + tag, *ball_data(h - n * 0.004, t1 * 0.05, t2 * 0.028, n * 0.012, 12, 6), "SPINO_Black"))
    return made


# ---------------------------------------------------------------- materials, stage

def _nodes(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return m, nt, nt.nodes.new("ShaderNodeOutputMaterial")


def _math(nt, op, a, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation, n.use_clamp = op, clamp
    for sock, v in ((n.inputs[0], a), (n.inputs[1], b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            nt.links.new(v, sock)
    return n.outputs[0]


def _mixf(nt, a, b, fac):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "FLOAT"
    for sock, v in ((n.inputs[2], a), (n.inputs[3], b), (n.inputs[0], fac)):
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            nt.links.new(v, sock)
    return n.outputs[0]


def mat_skin():
    """Scaly skin: the painted colour ("Col") broken into scales - each a little lighter or darker,
    dark in the cracks between them, raised - small ones, or large where "coarse" says so."""
    m, nt, out = _nodes("SPINO_Skin")
    N, L = nt.nodes.new, nt.links.new
    colr = N("ShaderNodeAttribute")
    colr.attribute_name = "Col"
    crs = N("ShaderNodeAttribute")
    crs.attribute_name = "coarse"
    tc = N("ShaderNodeTexCoord")
    layers = []
    for scale in (58.0, 26.0):
        e = N("ShaderNodeTexVoronoi")
        e.feature = "DISTANCE_TO_EDGE"
        e.inputs["Scale"].default_value = scale
        L(tc.outputs["Object"], e.inputs["Vector"])
        cl = N("ShaderNodeTexVoronoi")
        cl.inputs["Scale"].default_value = scale
        L(tc.outputs["Object"], cl.inputs["Vector"])
        sep = N("ShaderNodeSeparateColor")
        L(cl.outputs["Color"], sep.inputs[0])
        mr = N("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        mr.inputs[1].default_value, mr.inputs[2].default_value = 0.0, 0.08
        L(e.outputs["Distance"], mr.inputs[0])
        layers.append((mr.outputs[0], sep.outputs[0]))
    height = _mixf(nt, layers[0][0], layers[1][0], crs.outputs["Fac"])
    cell = _mixf(nt, layers[0][1], layers[1][1], crs.outputs["Fac"])
    shade = _math(nt, "MULTIPLY", _math(nt, "ADD", 0.56, _math(nt, "MULTIPLY", cell, 0.82)), _math(nt, "ADD", 0.36, _math(nt, "MULTIPLY", height, 0.64)))
    mul = N("ShaderNodeVectorMath")
    mul.operation = "SCALE"
    L(colr.outputs["Color"], mul.inputs[0])
    L(shade, mul.inputs["Scale"])
    bs = N("ShaderNodeBsdfPrincipled")
    L(mul.outputs[0], bs.inputs["Base Color"])
    L(_math(nt, "SUBTRACT", 0.60, _math(nt, "MULTIPLY", height, 0.28)), bs.inputs["Roughness"])
    bs.inputs["Specular IOR Level"].default_value = 0.65
    bs.inputs["Coat Weight"].default_value = 0.10
    bs.inputs["Coat Roughness"].default_value = 0.25
    wr = N("ShaderNodeTexNoise")
    wr.inputs["Scale"].default_value = 5.0
    wr.inputs["Detail"].default_value = 5.0
    L(tc.outputs["Object"], wr.inputs["Vector"])
    b1 = N("ShaderNodeBump")
    b1.inputs["Strength"].default_value, b1.inputs["Distance"].default_value = 0.25, 0.05
    L(wr.outputs["Fac"], b1.inputs["Height"])
    b2 = N("ShaderNodeBump")
    b2.inputs["Strength"].default_value, b2.inputs["Distance"].default_value = 1.0, 0.012
    L(height, b2.inputs["Height"])
    L(b1.outputs[0], b2.inputs["Normal"])
    L(b2.outputs[0], bs.inputs["Normal"])
    L(bs.outputs[0], out.inputs["Surface"])
    return m


def mat_plain(name, color, rough, emit=0.0, coat=0.0, sss=0.0):
    m, nt, out = _nodes(name)
    c = C(color)
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = (*c, 1)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Coat Weight"].default_value = coat
    if emit:
        bs.inputs["Emission Color"].default_value = (*c, 1)
        bs.inputs["Emission Strength"].default_value = emit
    if sss:
        bs.inputs["Subsurface Weight"].default_value = sss
        bs.inputs["Subsurface Radius"].default_value = (0.02, 0.008, 0.005)
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*c, 1)
    return m


def materials():
    mat_skin()
    mat_plain("SPINO_Horn", "#231f1c", 0.22, coat=0.5)
    mat_plain("SPINO_Tooth", "#e2c988", 0.28, coat=0.3)
    mat_plain("SPINO_Tongue", "#c2575c", 0.22, coat=0.6, sss=0.3)
    mat_plain("SPINO_Eye", "#e3a511", 0.08, emit=0.25, coat=1.0)
    mat_plain("SPINO_Black", "#050505", 0.15, coat=1.0)


def stage(draft):
    sc = bpy.context.scene
    root = bpy.data.objects.new("SPINO_Root", None)
    root.empty_display_size = 1.0
    coll().objects.link(root)
    for ob in coll().objects:
        if ob is not root:
            ob.parent = root
    cd = bpy.data.cameras.new("SPINO_RefCamera")
    cd.lens, cd.sensor_width, cd.sensor_fit, cd.clip_end = cam.F * 36.0 / cam.W, 36.0, "HORIZONTAL", 300
    ob = bpy.data.objects.new("SPINO_RefCamera", cd)
    fw, up, right = V(cam.FW), V(cam.UP), V(cam.RIGHT)
    ob.matrix_world = Matrix.Translation(V(cam.location())) @ Matrix((right, up, -fw)).transposed().to_4x4()
    coll().objects.link(ob)
    sc.camera = ob
    sc.render.resolution_x, sc.render.resolution_y = cam.W, cam.H
    sc.render.film_transparent = True
    for name, loc, energy, color, angle in (("SPINO_Key", (4, -12, 18), 4.8, (1.0, 0.97, 0.92), 10), ("SPINO_Fill", (14, -12, 2), 0.6, (1.0, 0.95, 0.9), 30),
                                            ("SPINO_Rim", (-10, 10, 8), 1.5, (0.9, 0.95, 1.0), 15)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy, ld.color, ld.angle = energy, color, math.radians(angle)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = (V((0, 0, 3)) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        lo.location = loc
        coll().objects.link(lo)
    w = bpy.data.worlds.new("SPINO_World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.85, 0.87, 0.9, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28
    sc.world = w
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24 if draft else 128
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                for d in prefs.devices:
                    d.use = True
                sc.cycles.device = "GPU"
                break
            except Exception:
                continue
    except Exception as ex:
        print("rendering on the CPU:", ex)
    sc.view_settings.view_transform = "Standard"


def build(draft=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials()
    soup, T, B, arc = build_soup()
    L = [arc[i * 8] for i in range(len(TRUNK))]
    skin = make_skin(soup, 0.022 if draft else 0.013)
    P, part, t, dv = transfer(skin, soup)
    col, coarse = paint(P, part, t, dv, L)
    set_colors(skin, col.astype(np.float32), coarse)
    skin.data.materials.append(bpy.data.materials["SPINO_Skin"])
    print("skin: %d points" % len(P))
    me = skin.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    sail()
    spikes(T, arc, L)
    claws()
    teeth(bvh)
    tongue()
    eyes(bvh)
    stage(draft)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build("draft" in args)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "spinosaurus.blend"))
    bpy.context.scene.render.filepath = os.path.join(HERE, "renders", "view.png")
    bpy.ops.render.render(write_still=True)
