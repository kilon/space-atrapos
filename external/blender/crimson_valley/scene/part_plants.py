"""The plant prototype library of the Crimson Valley scene: part "plants".

  tools/cv part plants

Builds parts/plants.blend: the red vegetation of the picture as small real meshes (leaf blades and
leaf cards as polygons, no image textures), each variant its own object at the origin, base at
z = 0, +Z up, in metres. Nothing here is placed in the valley: the vegetation scatter instances
these by the tens of thousands. So the part's own render is empty - the child collections are
hidden (hide_render, hide_viewport) and only show through an instancer.

What the picture shows, and the prototypes made from it (collection: variants):
  CV_Plants_Fern    A B C D   the spiky plants at the bottom left (x 0-80, y 700-770): rosettes of
                              radiating pointed blades, bright orange-red where lit - a broad-leaved
                              one like the picture's (A), a stiff narrow-leaved burst (B), arching
                              pinnate fronds (C), a small young rosette (D).
  CV_Plants_Shrub   A B C D   the bushy scarlet clumps next to them (x 100-400, y 700-790): a dome of
                              feathery sprigs (A), a clump of small-leaved tufts (B), branching fleshy
                              coral-like stems (C), a small low clump (D).
  CV_Plants_Carpet  A B C D   the red carpet of the left slope and the valley floor (x 0-450,
                              y 480-640): low mats - a dark cushion carrying rosettes of small pointed
                              leaves - round (A), flat and creeping (B), a taller grassy clump (C),
                              a long three-lobed mat (D). Made to be massed and seen from 30-300 m.
  CV_Plants_Bush    A B C     the rounded dark-red bushes and small trees by the river at the right
                              (x 1540-1672, y 760-860) and along the bottom edge: a trunk, a few
                              branches and a crown of leafy puffs (each a dark core under leaf cards).
  CV_Plants_Moss    A B C     the yellow-green tufts on rock tops (x 540-650, y 595-640): a cushion
                              with short blades (A), a grass tuft (B), a flat creeping patch (C).

Sizes come from the picture: every category has a RULER - a region of the picture where its plants
are, and the metres one picture pixel spanned there when the plants were authored. At build time the
depth map (analysis/depth.npy) is read in that region again and the plants are scaled by the ratio,
so a recalibration of the scene resizes the plants with everything else.

Each mesh carries one colour attribute, "cv_leaf" (per vertex): R = height in the plant (0 at the
base and in the heart, 1 at the leaf tips), G = a random number per leaf, B = 1 on woody stems.
Two materials use it, CV_Foliage_Red and CV_Foliage_Moss (foliage_material): the leaf colour is picked
from a ramp (crimson > scarlet > orange) by a random number per instance (Object Info > Random), the
random number per leaf and a slow noise over the world (drifts of one tint); it is darker toward the
base, a few leaves are pale gold, and part of the light goes through the leaf (a Translucent BSDF
mixed in), so back-lit leaves glow. No image textures.

For the scatter
  import part_plants
  part_plants.build(col)            # in the scatter's own part: the library under its collection
  part_plants.prototypes()          # {"fern": ["CV_Plants_Fern_A", ...], "shrub": ..., "carpet": ...,
                                    #  "bush": ..., "moss": ...}
  part_plants.COLLECTIONS           # {"fern": "CV_Plants_Fern", ...}
(or append the collections from parts/plants.blend). In geometry nodes: Collection Info (Separate
Children and Reset Children on) > Instance on Points (Pick Instance on, Instance Index = a random
integer, Rotation = a random turn about Z, Scale 0.7-1.3). Hidden collections still instance. Keep
them instances (do not realize): Object Info > Random then differs per instance, which is where the
plant-to-plant colour variation comes from. Every object has custom properties cv_width, cv_height
(metres) and cv_tris. Guide densities for a closed cover: carpets 5-7 per square metre, with shrubs
0.3-0.6 and, close to the camera only, ferns 0.05-0.1; bushes singly or in groups of 2-5 at the
water; moss 4-8 per square metre in patches on rock tops. The meshes reach a little under z = 0
(a skirt of a few centimetres), so they do not float on sloping ground.
"""
import math
import os

import bpy
import numpy as np

import common

SEED = 20261115
GOLDEN = math.radians(137.508)
ATTR = "cv_leaf"
RED, MOSS = "CV_Foliage_Red", "CV_Foliage_Moss"

COLLECTIONS = {"fern": "CV_Plants_Fern", "shrub": "CV_Plants_Shrub", "carpet": "CV_Plants_Carpet",
               "bush": "CV_Plants_Bush", "moss": "CV_Plants_Moss"}
VARIANTS = {"fern": "ABCD", "shrub": "ABCD", "carpet": "ABCD", "bush": "ABC", "moss": "ABC"}

# Where each kind of plant is in the picture (x0, y0, x1, y1) and the metres per picture pixel there
# when the sizes below were chosen (depth / focal length). See scale_factors().
RULERS = {"fern": ((0, 700, 80, 770), 0.0176), "shrub": ((180, 725, 400, 785), 0.0203),
          "carpet": ((0, 530, 250, 600), 0.0293), "bush": ((1540, 760, 1672, 860), 0.0484),
          "moss": ((540, 595, 650, 640), 0.0281)}

# Leaf colours (albedo, as sRGB): the ramp runs from the darkest crimson plants to the orange ones.
RED_RAMP = ((0.00, "#7a0c1e"), (0.30, "#b01018"), (0.55, "#cf2414"), (0.80, "#de4a16"), (1.00, "#e87a22"))
RED_ACCENT = "#f0b45a"        # the few pale gold leaves
RED_BARK = "#2e1a16"
MOSS_RAMP = ((0.00, "#5c5a1c"), (0.35, "#8f8a2a"), (0.65, "#b9a83a"), (1.00, "#d8bc4c"))
MOSS_ACCENT = "#ecd98a"
MOSS_BARK = "#3a3018"


def prototypes():
    """{category: [object names]} of the library (the names build() gives; no Blender data needed)."""
    return {cat: [f"{COLLECTIONS[cat]}_{v}" for v in VARIANTS[cat]] for cat in COLLECTIONS}


def scale_factors():
    """{category: factor}: how much bigger a picture pixel is at each category's ruler now than when
    the plants were authored (1.0 when the analysis is missing)."""
    out = {cat: 1.0 for cat in RULERS}
    try:
        depth = np.load(os.path.join(common.ANALYSIS, "depth.npy"), mmap_mode="r")
        f = common.cam_model().f
    except Exception as ex:
        print("plants: no depth map, sizes as authored:", ex)
        return out
    for cat, ((x0, y0, x1, y1), mpp) in RULERS.items():
        d = np.asarray(depth[y0:y1, x0:x1], dtype=np.float64)
        d = d[d > 0]
        if d.size:
            out[cat] = float(np.median(d)) / f / mpp
    return out


# ------------------------------------------------------------------------------------------ geometry
class Mesh:
    """Triangles with the cv_leaf attribute, gathered piece by piece."""

    def __init__(self):
        self.v, self.f, self.a = [], [], []
        self.n = 0

    def add(self, verts, tris, h, rnd=0.5, wood=0.0):
        verts = np.asarray(verts, dtype=np.float64).reshape(-1, 3)
        k = len(verts)
        a = np.empty((k, 4))
        a[:, 0] = np.clip(h, 0.0, 1.0)
        a[:, 1] = rnd
        a[:, 2] = wood
        a[:, 3] = 1.0
        self.v.append(verts)
        self.f.append(np.asarray(tris, dtype=np.int64).reshape(-1, 3) + self.n)
        self.a.append(a)
        self.n += k

    @property
    def tris(self):
        return sum(len(f) for f in self.f)

    def object(self, name, col, mat, scale=1.0, floor=-0.04):
        v = np.concatenate(self.v) * scale
        v[:, 2] = np.maximum(v[:, 2], floor * scale)
        ob = common.mesh_object(name, v, np.concatenate(self.f), col, smooth=True,
                                attributes={ATTR: np.concatenate(self.a)})
        ob.data.materials.append(mat)
        ext = v.max(0) - v.min(0)
        ob["cv_width"] = float(max(ext[0], ext[1]))
        ob["cv_height"] = float(v[:, 2].max())
        ob["cv_tris"] = int(self.tris)
        return ob


def _unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-9)


def _perp(axis):
    """Two unit vectors square to `axis` (and to each other)."""
    axis = _unit(axis)
    a = _unit(np.cross(axis, (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (1.0, 0.0, 0.0)))
    return a, np.cross(axis, a)


def _profile(t, shape):
    """Half-width of a leaf along its length t = 0..1, as a fraction of the full width."""
    t = np.clip(t, 0.0, 1.0)
    if shape == "strap":        # broad for most of its length, then a point (bromeliad, agave)
        return (1.0 - t ** 2.5) ** 0.8 * (0.7 + 0.3 * np.minimum(t / 0.25, 1.0))
    if shape == "lance":        # widest a third of the way along
        return np.maximum(np.sin(np.pi * t ** 0.7) ** 0.9, 0.3 * (1.0 - t))
    return (1.0 - t) ** 0.6     # needle


def _spine(base, yaw, elev, droop, length, n, power=1.4, bend=0.0):
    """The centre line of a leaf or twig: n + 1 points from `base`, leaving at `elev` radians above
    the horizontal towards `yaw` and drooping by `droop` radians over its length (bend: a sideways
    curl). Returns points, and per point the forward / side / up vectors and t = 0..1."""
    t = np.linspace(0.0, 1.0, n + 1)
    a = elev - droop * t ** power
    y = yaw + bend * t
    fwd = np.stack([np.cos(a) * np.cos(y), np.cos(a) * np.sin(y), np.sin(a)], 1)
    side = np.stack([-np.sin(y), np.cos(y), np.zeros_like(y)], 1)
    up = np.cross(fwd, side)
    step = 0.5 * (fwd[:-1] + fwd[1:]) * (length / n)
    pts = np.asarray(base, dtype=np.float64) + np.concatenate([np.zeros((1, 3)), np.cumsum(step, 0)])
    return pts, fwd, side, up, t


def _at(sp, tt):
    """Point and frame of a spine at parameter tt (linear between its points)."""
    pts, fwd, side, up, t = sp
    x = min(max(tt, 0.0), 1.0) * (len(t) - 1)
    i = min(int(x), len(t) - 2)
    w = x - i
    return tuple(q[i] * (1.0 - w) + q[i + 1] * w for q in (pts, fwd, side, up))


def blade(m, base, yaw, elev, droop, length, width, n=5, fold=0.5, roll=0.0, shape="strap",
          h=(0.1, 1.0), rnd=0.5, power=1.4, bend=0.0):
    """A long leaf folded along its midrib (a V in section): 4 triangles per segment, 2 at the tip."""
    sp = _spine(base, yaw, elev, droop, length, n, power, bend)
    p, _, side, up, t = sp
    if roll:
        c, s = math.cos(roll), math.sin(roll)
        side, up = side * c + up * s, up * c - side * s
    w = (0.5 * width * _profile(t, shape))[:, None]
    lift = up * w * math.sin(fold)
    left = p + side * w * math.cos(fold) + lift
    right = p - side * w * math.cos(fold) + lift
    verts = np.concatenate([left[:-1], p[:-1], right[:-1], p[-1:]])
    tris = []
    for i in range(n - 1):
        a, b, c = i, n + i, 2 * n + i
        tris += [(a, b, b + 1), (a, b + 1, a + 1), (b, c, c + 1), (b, c + 1, b + 1)]
    tris += [(n - 1, 2 * n - 1, 3 * n), (2 * n - 1, 3 * n - 1, 3 * n)]
    hh = h[0] + (h[1] - h[0]) * t ** 0.8
    m.add(verts, tris, np.concatenate([hh[:-1], hh[:-1], hh[:-1], hh[-1:]]), rnd)
    return sp


def ribbon(m, sp, width, h=(0.1, 1.0), rnd=0.5, wood=0.0, t0=0.0):
    """A flat tapering strip along a spine (a stalk, a grass blade): 2 triangles per segment, 1 at the tip."""
    p, _, side, _, t = sp
    n = len(t) - 1
    w = (0.5 * width * (1.0 - 0.8 * t))[:, None]
    verts = np.concatenate([p[:-1] + side[:-1] * w[:-1], p[:-1] - side[:-1] * w[:-1], p[-1:]])
    tris = []
    for i in range(n - 1):
        tris += [(i, n + i, n + i + 1), (i, n + i + 1, i + 1)]
    tris += [(n - 1, 2 * n - 1, 2 * n)]
    hh = h[0] + (h[1] - h[0]) * (t0 + (1.0 - t0) * t)
    m.add(verts, tris, np.concatenate([hh[:-1], hh[:-1], hh[-1:]]), rnd, wood)


def frond(m, rng, base, yaw, elev, droop, length, width, pairs=10, n=5, sweep=0.45, vee=0.25,
          stalk=0.12, gap=0.25, h=(0.15, 1.0), rnd=0.5, rachis=0.02, power=1.3, bend=0.0):
    """A pinnate leaf (fern frond, heather sprig): a thin rachis with a pointed leaflet - one triangle -
    on each side of it per pair, longest a third of the way along. Returns its spine."""
    sp = _spine(base, yaw, elev, droop, length, n, power, bend)
    if rachis > 0.0:
        ribbon(m, sp, rachis, h, rnd)
    edges = np.linspace(stalk, 1.0, pairs + 1)
    for j in range(pairs):
        ta, tb = edges[j], edges[j + 1]
        tm = 0.5 * (ta + tb)
        u = (tm - stalk) / (1.0 - stalk)
        ll = 0.5 * width * float(np.sin(np.pi * u ** 0.6) ** 0.8 + 0.12) * rng.uniform(0.85, 1.12)
        pa = _at(sp, ta)[0]
        pb = _at(sp, ta + (tb - ta) * (1.0 - gap))[0]
        pm, fwd, side, up = _at(sp, tm)
        hm = h[0] + (h[1] - h[0]) * tm
        for sgn in (1.0, -1.0):
            apex = pm + side * (sgn * ll * math.cos(vee)) + up * (ll * math.sin(vee) + rng.normal(0, 0.1) * ll) \
                + fwd * (ll * sweep)
            tri = (pa, pb, apex) if sgn > 0 else (pb, pa, apex)
            m.add(tri, [(0, 1, 2)], (hm - 0.1, hm - 0.1, min(1.0, hm + 0.25)), (rnd + 0.37 * j * sgn) % 1.0 if rng.random() < 0.3 else rnd)
    return sp


def leaf(m, base, d, nrm, length, width, h=(0.5, 1.0), rnd=0.5):
    """One small pointed leaf: a triangle from a `width` wide foot at `base` to its tip along d,
    lying in the plane whose normal is (about) nrm."""
    d = _unit(d)
    b = _unit(np.cross(d, nrm)) * (0.5 * width)
    base = np.asarray(base, dtype=np.float64)
    m.add((base - b, base + b, base + d * length), [(0, 1, 2)], (h[0], h[0], h[1]), rnd)


def whorl(m, rng, centre, axis, count, length, width, spread=1.0, h=(0.4, 1.0), rnd=None):
    """A tuft: `count` leaves around an axis, opened by `spread` radians from it."""
    axis = _unit(axis)
    a, b = _perp(axis)
    centre = np.asarray(centre, dtype=np.float64)
    turn = rng.uniform(0, 2 * math.pi)
    for j in range(count):
        ang = turn + 2 * math.pi * j / count + rng.uniform(-0.3, 0.3)
        radial = a * math.cos(ang) + b * math.sin(ang)
        tilt = max(0.1, spread + rng.normal(0, 0.22))
        d = axis * math.cos(tilt) + radial * math.sin(tilt)
        nrm = axis * math.sin(tilt) - radial * math.cos(tilt)
        leaf(m, centre, d, nrm, length * rng.uniform(0.75, 1.15), width * rng.uniform(0.85, 1.15), h,
             rng.random() if rnd is None else rnd)


def dome(m, rng, centre, rx, ry, height, n=6, rings=2, jitter=0.15, h=(0.05, 0.3), rnd=0.5, sink=0.04):
    """A low-poly mound (the dark body under the leaves of a mat): `rings` bands of n segments and a cap."""
    centre = np.asarray(centre, dtype=np.float64)
    verts, hs = [], []
    for i in range(rings):
        phi = 0.5 * math.pi * i / rings
        for j in range(n):
            ang = 2 * math.pi * (j + 0.5 * i) / n
            k = math.cos(phi) * (1.0 + rng.uniform(-jitter, jitter))
            z = height * math.sin(phi) * (1.0 + rng.uniform(-jitter, jitter)) - (sink if i == 0 else 0.0)
            verts.append(centre + (rx * k * math.cos(ang), ry * k * math.sin(ang), z))
            hs.append(h[0] + (h[1] - h[0]) * i / rings)
    verts.append(centre + (0.0, 0.0, height))
    hs.append(h[1])
    tris = []
    for i in range(rings - 1):
        for j in range(n):
            a, a1 = i * n + j, i * n + (j + 1) % n
            b, b1 = a + n, a1 + n
            tris += [(a, a1, b), (a1, b1, b)]
    top = rings * n
    for j in range(n):
        tris.append(((rings - 1) * n + j, (rings - 1) * n + (j + 1) % n, top))
    m.add(verts, tris, hs, rnd)


_ICO_T = (1.0 + 5.0 ** 0.5) / 2.0
_ICO_V = np.array([(-1, _ICO_T, 0), (1, _ICO_T, 0), (-1, -_ICO_T, 0), (1, -_ICO_T, 0), (0, -1, _ICO_T), (0, 1, _ICO_T),
                   (0, -1, -_ICO_T), (0, 1, -_ICO_T), (_ICO_T, 0, -1), (_ICO_T, 0, 1), (-_ICO_T, 0, -1), (-_ICO_T, 0, 1)])
_ICO_V = _ICO_V / np.linalg.norm(_ICO_V[0])
_ICO_F = np.array([(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
                   (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
                   (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)])


def blob(m, rng, centre, radius, jitter=0.2, h=0.15, rnd=0.5):
    """A rough ball of 20 triangles: the dark heart of a puff of leaves."""
    v = _ICO_V * (radius * (1.0 + rng.uniform(-jitter, jitter, (12, 1))))
    hs = np.clip(h * (0.7 + 0.6 * (v[:, 2] / radius * 0.5 + 0.5)), 0, 1)
    m.add(np.asarray(centre, dtype=np.float64) + v, _ICO_F, hs, rnd)


def tube(m, pts, radii, sides=3, h=0.08, rnd=0.5, wood=1.0, cap=True):
    """A stem: a prism of `sides` sides through the points, radius per point; cap: closed by a point."""
    pts = np.asarray(pts, dtype=np.float64)
    k = len(pts)
    hv = np.broadcast_to(np.asarray(h, dtype=np.float64), (k,)) if np.ndim(h) else np.full(k, float(h))
    verts, hs = [], []
    for i in range(k):
        d = _unit(pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)])
        a, b = _perp(d)
        for j in range(sides):
            ang = 2 * math.pi * j / sides + 0.4 * i
            verts.append(pts[i] + (a * math.cos(ang) + b * math.sin(ang)) * radii[i])
            hs.append(hv[i])
    tris = []
    for i in range(k - 1):
        for j in range(sides):
            a, a1 = i * sides + j, i * sides + (j + 1) % sides
            tris += [(a, a1, a + sides), (a1, a1 + sides, a + sides)]
    if cap:
        d = _unit(pts[-1] - pts[-2])
        verts.append(pts[-1] + d * radii[-1] * 1.5)
        hs.append(hv[-1])
        for j in range(sides):
            tris.append(((k - 1) * sides + j, (k - 1) * sides + (j + 1) % sides, k * sides))
    m.add(verts, tris, hs, rnd, wood)


def _fib(n, zmin=0.0, zmax=1.0):
    """n directions spread evenly over the part of the unit sphere with zmin <= z <= zmax."""
    i = np.arange(n) + 0.5
    z = zmax - (zmax - zmin) * i / n
    r = np.sqrt(np.maximum(0.0, 1.0 - z * z))
    return np.stack([r * np.cos(i * GOLDEN), r * np.sin(i * GOLDEN), z], 1)


# -------------------------------------------------------------------------------------------- plants
def rosette(m, rng, leaves, length, width, n=5, fold=0.5, elev=(1.3, 0.3), droop=(0.25, 0.85),
            shape="strap", stem=0.0):
    """A spiky plant: blades spiralling out of one heart, the young ones upright in the middle."""
    for i in range(leaves):
        u = i / max(leaves - 1, 1)
        yaw = i * GOLDEN + rng.normal(0, 0.15)
        e = elev[0] + (elev[1] - elev[0]) * u ** 0.8 + rng.normal(0, 0.07)
        d = droop[0] + (droop[1] - droop[0]) * u + rng.normal(0, 0.1)
        ln = length * (0.6 + 0.4 * math.sin(math.pi * min(1.0, 0.15 + 1.1 * u))) * rng.uniform(0.88, 1.1)
        r = 0.04 * width / 0.1 * u
        base = (r * math.cos(yaw), r * math.sin(yaw), stem - 0.03 * u)
        blade(m, base, yaw, e, d, ln, width * rng.uniform(0.85, 1.1) * (0.75 + 0.25 * u), n, fold,
              roll=rng.normal(0, 0.18), shape=shape, h=(0.04 + 0.1 * u, 1.0), rnd=rng.random(),
              bend=rng.normal(0, 0.12))


def fern(v, rng):
    m = Mesh()
    if v == "A":      # the picture's: broad channelled blades, the outer ones arching to the ground
        rosette(m, rng, 22, 0.80, 0.125, n=5, fold=0.55, elev=(1.3, 0.32), droop=(0.25, 0.8))
    elif v == "B":    # a stiff burst of narrow blades on a short stock
        tube(m, [(0, 0, -0.04), (0.01, 0.0, 0.1), (0.0, 0.01, 0.2)], [0.06, 0.05, 0.04], sides=4, h=0.05, cap=False)
        rosette(m, rng, 34, 0.56, 0.05, n=4, fold=0.35, elev=(1.45, -0.1), droop=(0.05, 0.25), shape="needle", stem=0.2)
    elif v == "C":    # arching pinnate fronds
        for i in range(11):
            u = i / 10.0
            yaw = i * GOLDEN + rng.normal(0, 0.2)
            frond(m, rng, (0.02 * math.cos(yaw), 0.02 * math.sin(yaw), -0.02), yaw, 1.3 - 0.75 * u + rng.normal(0, 0.06),
                  0.9 + 0.5 * u + rng.normal(0, 0.1), 0.78 * (0.7 + 0.3 * math.sin(math.pi * (0.2 + 0.8 * u))) * rng.uniform(0.9, 1.1),
                  0.26, pairs=11, n=5, h=(0.08, 1.0), rnd=rng.random(), rachis=0.025, bend=rng.normal(0, 0.15))
    else:             # a small young rosette
        rosette(m, rng, 14, 0.43, 0.085, n=4, fold=0.6, elev=(1.25, 0.45), droop=(0.2, 0.7))
    return m


def shrub(v, rng):
    m = Mesh()
    if v in "AD":     # a dome of feathery sprigs, some forked
        count, ln, wd, fork = (26, 0.46, 0.085, 0.4) if v == "A" else (16, 0.27, 0.07, 0.25)
        for i in range(count):
            u = (i + 0.5) / count
            yaw = i * GOLDEN + rng.normal(0, 0.2)
            e = 1.4 - 1.15 * u ** 0.75 + rng.normal(0, 0.08)
            base = (0.05 * u * math.cos(yaw), 0.05 * u * math.sin(yaw), -0.02)
            sp = frond(m, rng, base, yaw, e, rng.uniform(0.1, 0.5), ln * rng.uniform(0.75, 1.1), wd, pairs=6, n=3,
                       sweep=0.7, vee=0.35, stalk=0.2, h=(0.1, 1.0), rnd=rng.random(), rachis=0.022, bend=rng.normal(0, 0.25))
            if rng.random() < fork:
                p, fwd, _, _ = _at(sp, rng.uniform(0.35, 0.55))
                yaw2 = math.atan2(fwd[1], fwd[0]) + rng.choice((-1, 1)) * rng.uniform(0.5, 0.9)
                frond(m, rng, p, yaw2, math.asin(max(-1, min(1, fwd[2]))) + rng.uniform(0.0, 0.3), rng.uniform(0.0, 0.4),
                      ln * rng.uniform(0.4, 0.6), wd * 0.9, pairs=5, n=2, sweep=0.7, vee=0.35, stalk=0.15,
                      h=(0.45, 1.0), rnd=rng.random(), rachis=0.0)
    elif v == "B":    # a clump of small-leaved tufts over a dark body
        rx, hz = 0.3, 0.42
        dome(m, rng, (0, 0, 0), rx * 0.8, rx * 0.8, hz * 0.72, n=6, rings=2, h=(0.04, 0.22))
        for d in _fib(40, zmin=0.05):
            d = _unit(d + rng.normal(0, 0.12, 3))
            c = d * (rx, rx, hz) * rng.uniform(0.82, 1.05)
            whorl(m, rng, c, d + (0, 0, 0.35), 12, 0.085, 0.04, spread=1.0, h=(0.25 + 0.3 * d[2], 0.6 + 0.4 * d[2]))
    else:             # C: fleshy branching stems, like red coral
        def stem(base, yaw, elev, length, r, depth):
            sp = _spine(base, yaw, elev, rng.uniform(-0.35, 0.1), length, 2, bend=rng.normal(0, 0.3))
            z0 = base[2] / 0.7
            tube(m, sp[0], [r, r * 0.85, r * 0.7], sides=3, h=np.clip([z0, z0 + 0.2, z0 + 0.4], 0.05, 1.0) if depth else (0.55, 0.8, 1.0),
                 rnd=rng.random(), wood=0.0, cap=depth == 0)
            if depth:
                for _ in range(2 if depth == 1 or rng.random() < 0.6 else 3):
                    p, fwd, _, _ = _at(sp, rng.uniform(0.55, 1.0))
                    stem(p, yaw + rng.normal(0, 0.9), min(1.5, elev + rng.uniform(0.0, 0.5)), length * rng.uniform(0.55, 0.8),
                         r * 0.72, depth - 1)
        for i in range(6):
            yaw = i * GOLDEN + rng.normal(0, 0.2)
            stem(np.array([0.04 * math.cos(yaw), 0.04 * math.sin(yaw), -0.03]), yaw, rng.uniform(0.75, 1.35),
                 rng.uniform(0.26, 0.36), 0.026, 2)
    return m


def mat(m, rng, rx, ry, height, tufts, per, leaf_len, leaf_w, spread=0.9, lobes=((0.0, 0.0, 1.0),), sides=6):
    """A low mat: per lobe (x, y, size) a dark mound, and tufts of small pointed leaves all over it."""
    for (lx, ly, ls) in lobes:
        dome(m, rng, (lx * rx, ly * ry, 0.0), rx * ls * 0.85, ry * ls * 0.85, height * 0.62 * ls, n=sides, rings=2,
             h=(0.03, 0.25), jitter=0.2)
    done = 0
    while done < tufts:
        lx, ly, ls = lobes[done % len(lobes)]
        ang, rad = rng.uniform(0, 2 * math.pi), math.sqrt(rng.uniform(0.0, 1.0))
        x, y = rad * math.cos(ang), rad * math.sin(ang)
        z = height * 0.62 * ls * math.sqrt(max(0.0, 1.0 - rad * rad)) * 0.9
        c = np.array([(lx + x * ls * 0.9) * rx, (ly + y * ls * 0.9) * ry, z])
        axis = _unit((x * 0.7, y * 0.7, 1.0))
        whorl(m, rng, c, axis, per, leaf_len, leaf_w, spread=spread, h=(0.3 + 0.2 * (1 - rad), 1.0))
        done += 1


def carpet(v, rng):
    m = Mesh()
    if v == "A":      # a round cushion of leaf rosettes
        mat(m, rng, 0.36, 0.36, 0.2, 22, 6, 0.12, 0.05, spread=0.9)
    elif v == "B":    # flat and creeping, bigger leaves lying down
        mat(m, rng, 0.5, 0.42, 0.11, 22, 6, 0.13, 0.065, spread=1.25)
    elif v == "C":    # a taller grassy clump
        dome(m, rng, (0, 0, 0), 0.17, 0.17, 0.1, n=5, rings=2, h=(0.03, 0.2))
        for i in range(45):
            u = (i + 0.5) / 45
            yaw = i * GOLDEN + rng.normal(0, 0.2)
            sp = _spine((0.1 * u * math.cos(yaw), 0.1 * u * math.sin(yaw), 0.0), yaw, 1.45 - 1.0 * u + rng.normal(0, 0.08),
                        rng.uniform(0.3, 1.0), 0.27 * rng.uniform(0.7, 1.1), 2)
            ribbon(m, sp, 0.035, h=(0.12, 1.0), rnd=rng.random())
    else:             # D: a long mat of three lobes
        mat(m, rng, 0.5, 0.3, 0.18, 21, 6, 0.115, 0.05, spread=0.95,
            lobes=((-0.55, 0.05, 0.62), (0.05, -0.1, 0.7), (0.6, 0.12, 0.55)), sides=5)
    return m


def bush(v, rng):
    m = Mesh()
    width, height, trunk, puffs, per, stems = {"A": (2.3, 2.0, 0.45, 13, 80, 3), "B": (3.0, 2.9, 1.15, 13, 80, 1),
                                               "C": (1.7, 1.45, 0.25, 12, 76, 4)}[v]
    rad = np.array([width / 2, width / 2, (height - trunk) / 2])
    cc = np.array([0.0, 0.0, trunk + rad[2]])
    dirs = _fib(puffs, zmin=-0.45)
    pr = 0.42 * float(rad.mean()) * (13.0 / puffs) ** 0.33
    centres = []
    for d in dirs:
        d = _unit(d + rng.normal(0, 0.15, 3))
        r = pr * rng.uniform(0.8, 1.15)
        c = cc + d * (rad - r * 0.75) * rng.uniform(0.9, 1.05)
        centres.append(c)
        blob(m, rng, c, r * 0.78, h=0.12)
        ld = _fib(per, zmin=-0.75)
        a, b = _perp(_unit(rng.normal(0, 1, 3)))
        for q in ld:
            # the leaves of a puff: on its outer side, pointing out and a little down, like shingles
            o = _unit(q + d * 0.9 + rng.normal(0, 0.1, 3))
            pos = c + o * r * rng.uniform(0.82, 1.08)
            e = (pos - cc) / rad
            out = float(np.clip((np.linalg.norm(e) - 0.55) / 0.45, 0.0, 1.0))
            hh = (0.22 + 0.78 * out) * (0.62 + 0.38 * float(np.clip(e[2] * 0.5 + 0.5, 0, 1)))
            t = _unit(np.cross(o, rng.normal(0, 1, 3)))
            dr = _unit(t + o * rng.uniform(0.2, 0.9) - (0, 0, rng.uniform(0.0, 0.5)))
            leaf(m, pos, dr, o, 0.17 * rng.uniform(0.75, 1.2), 0.1 * rng.uniform(0.8, 1.2), h=(hh * 0.8, hh), rnd=rng.random())
    # the wood: stems from the ground into the crown, forking towards the puffs
    order = np.argsort([c[2] for c in centres])
    for s in range(stems):
        yaw = s * GOLDEN + rng.uniform(0, 1)
        off = (0.0 if stems == 1 else 0.12 * width / 2) * np.array([math.cos(yaw), math.sin(yaw), 0.0])
        top = cc * (0, 0, 1) + off * 2.0 - (0, 0, rad[2] * 0.55)
        r0 = (0.085 if stems == 1 else 0.05) * width / 2.3
        mid = (off + top) / 2 + rng.normal(0, 0.04, 3) * (1, 1, 0)
        tube(m, [off - (0, 0, 0.05), mid, top], [r0, r0 * 0.8, r0 * 0.62], sides=4 if stems == 1 else 3, h=0.3, cap=False)
        for c in [centres[i] for i in order[s::stems][:4]]:
            tube(m, [top, (top + c) / 2 + rng.normal(0, 0.05, 3), c], [r0 * 0.5, r0 * 0.38, r0 * 0.22], sides=3, h=0.25, cap=False)
    return m


def moss(v, rng):
    m = Mesh()
    if v == "A":      # a cushion with short blades
        dome(m, rng, (0, 0, 0), 0.17, 0.15, 0.1, n=5, rings=2, h=(0.1, 0.5))
        for d in _fib(14, zmin=0.15):
            c = d * (0.15, 0.13, 0.09)
            whorl(m, rng, c, d + (0, 0, 0.6), 6, 0.07, 0.022, spread=0.75, h=(0.4, 1.0))
    elif v == "B":    # a tuft of grass
        for i in range(32):
            u = (i + 0.5) / 32
            yaw = i * GOLDEN + rng.normal(0, 0.2)
            sp = _spine((0.05 * u * math.cos(yaw), 0.05 * u * math.sin(yaw), -0.02), yaw, 1.45 - 0.95 * u + rng.normal(0, 0.08),
                        rng.uniform(0.4, 1.3), 0.3 * rng.uniform(0.6, 1.1), 2)
            ribbon(m, sp, 0.022, h=(0.15, 1.0), rnd=rng.random())
    else:             # C: a flat creeping patch
        dome(m, rng, (0, 0, 0), 0.25, 0.19, 0.05, n=6, rings=2, h=(0.15, 0.6), jitter=0.3)
        for i in range(14):
            ang, rad = rng.uniform(0, 2 * math.pi), math.sqrt(rng.uniform(0, 1))
            c = (0.23 * rad * math.cos(ang), 0.17 * rad * math.sin(ang), 0.045 * math.sqrt(1 - rad * rad))
            whorl(m, rng, c, (0.3 * math.cos(ang), 0.3 * math.sin(ang), 1.0), 6, 0.06, 0.03, spread=1.2, h=(0.45, 1.0))
    return m


MAKERS = {"fern": fern, "shrub": shrub, "carpet": carpet, "bush": bush, "moss": moss}


# ------------------------------------------------------------------------------------------ materials
def foliage_material(name, ramp, accent, bark, translucency=0.38, hue_spread=(0.5, 0.25, 0.9, 0.12)):
    """The leaf material (see the module's docstring). ramp: ((position, "#rrggbb"), ...) from the
    darkest plants to the brightest; hue_spread: how far the random number per instance, the one per
    leaf and the world noise move a leaf along the ramp, and the offset."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat_, nodes, links = common.new_material(name)

    def node(kind, **props):
        n = nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def math_(op, a, b=None, clamp=False):
        n = node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for sock, v in zip(n.inputs, (a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                sock.default_value = v
            else:
                links.new(v, sock)
        return n.outputs[0]

    def mix(kind, fac, a, b, blend="MIX"):
        n = node("ShaderNodeMix", data_type=kind, blend_type=blend) if kind == "RGBA" else node("ShaderNodeMix", data_type=kind)
        ia, ib = (6, 7) if kind == "RGBA" else (2, 3)
        for sock, v in ((n.inputs[0], fac), (n.inputs[ia], a), (n.inputs[ib], b)):
            if isinstance(v, (int, float, tuple)):
                sock.default_value = v
            else:
                links.new(v, sock)
        return n.outputs[2 if kind == "RGBA" else 0]

    attr = node("ShaderNodeAttribute", attribute_type="GEOMETRY", attribute_name=ATTR)
    sep = node("ShaderNodeSeparateColor")
    links.new(attr.outputs["Color"], sep.inputs[0])
    h, per_leaf, wood = sep.outputs[0], sep.outputs[1], sep.outputs[2]
    # three independent random numbers per instance
    info = node("ShaderNodeObjectInfo")
    white = node("ShaderNodeTexWhiteNoise", noise_dimensions="1D")
    links.new(info.outputs["Random"], white.inputs["W"])
    isep = node("ShaderNodeSeparateColor")
    links.new(white.outputs["Color"], isep.inputs[0])
    i1, i2 = isep.outputs[0], isep.outputs[1]
    # drifts of one tint over the ground
    geo = node("ShaderNodeNewGeometry")
    noise = node("ShaderNodeTexNoise", noise_dimensions="3D", noise_type="FBM")
    noise.inputs["Scale"].default_value = 0.11
    noise.inputs["Detail"].default_value = 2.0
    noise.inputs["Roughness"].default_value = 0.55
    links.new(geo.outputs["Position"], noise.inputs["Vector"])
    patch = math_("SUBTRACT", noise.outputs["Fac"], 0.5)
    k = math_("ADD", math_("MULTIPLY", i1, hue_spread[0]), math_("MULTIPLY", per_leaf, hue_spread[1]))
    k = math_("ADD", k, math_("MULTIPLY", patch, hue_spread[2]))
    k = math_("ADD", k, hue_spread[3], clamp=True)
    cr = node("ShaderNodeValToRGB")
    els = cr.color_ramp.elements
    for i, (pos, colr) in enumerate(ramp):
        e = els[i] if i < 2 else els.new(pos)
        e.position = pos
        e.color = common.rgba(colr)
    links.new(k, cr.inputs["Fac"])
    # a few pale leaves; brightness per instance; dark toward the base
    pale = math_("GREATER_THAN", per_leaf, 0.94)
    colr = mix("RGBA", math_("MULTIPLY", pale, 0.75), cr.outputs["Color"], common.rgba(accent))
    value = math_("MULTIPLY", mix("FLOAT", i2, 0.62, 1.12), mix("FLOAT", math_("POWER", h, 1.25), 0.1, 1.0))
    lit = node("ShaderNodeVectorMath", operation="SCALE")
    links.new(colr, lit.inputs[0])
    links.new(value, lit.inputs["Scale"])
    base = mix("RGBA", wood, lit.outputs[0], common.rgba(bark))
    glow = node("ShaderNodeVectorMath", operation="MULTIPLY")
    links.new(base, glow.inputs[0])
    glow.inputs[1].default_value = (1.15, 1.7, 0.8)
    bsdf = node("ShaderNodeBsdfPrincipled")
    links.new(base, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.48
    bsdf.inputs["Specular IOR Level"].default_value = 0.4
    trans = node("ShaderNodeBsdfTranslucent")
    links.new(glow.outputs[0], trans.inputs["Color"])
    sh = node("ShaderNodeMixShader")
    links.new(math_("MULTIPLY", math_("SUBTRACT", 1.0, wood), translucency), sh.inputs[0])
    links.new(bsdf.outputs[0], sh.inputs[1])
    links.new(trans.outputs[0], sh.inputs[2])
    out = node("ShaderNodeOutputMaterial")
    links.new(sh.outputs[0], out.inputs["Surface"])
    return mat_


# ---------------------------------------------------------------------------------------------- part
def build(col):
    """The library under `col`: one hidden child collection per category, one object per variant."""
    red = foliage_material(RED, RED_RAMP, RED_ACCENT, RED_BARK)
    green = foliage_material(MOSS, MOSS_RAMP, MOSS_ACCENT, MOSS_BARK, translucency=0.3, hue_spread=(0.6, 0.3, 0.8, 0.1))
    factors = scale_factors()
    made = {}
    for ci, cat in enumerate(COLLECTIONS):
        sub = bpy.data.collections.new(COLLECTIONS[cat])
        col.children.link(sub)
        for vi, v in enumerate(VARIANTS[cat]):
            m = MAKERS[cat](v, np.random.default_rng([SEED, ci, vi]))
            ob = m.object(f"{COLLECTIONS[cat]}_{v}", sub, green if cat == "moss" else red, scale=factors[cat])
            made.setdefault(cat, []).append(ob)
            print(f"  {ob.name:22s} {ob['cv_tris']:5d} triangles   {ob['cv_width']:.2f} m wide   {ob['cv_height']:.2f} m tall")
        sub.hide_render = True
        sub.hide_viewport = True
    print("plants: scale from the picture", {k: round(v, 3) for k, v in factors.items()})
    return made
