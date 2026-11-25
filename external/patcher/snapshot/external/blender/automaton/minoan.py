"""The Minoan android (the towns' guards and citizens), from the 2D game's
sheets (external/images/minoan_npc_android*.png, minoan_npc_guard_idle.png): a
machine of ceramic and bronze in a triceratops's image - a big beaked head
with two long brow horns curving forward and a nose horn, a great scalloped
frill as wide as the shoulders, painted with spirals and radial petals, its
edge studded; a broad chest of layered plates round a glowing core, lit
seams; big round pauldrons with spiral roundels; a meander belt, a short
patterned apron front and back (the armoured legs show); heavy thighs with
painted bosses, greaves, three-toed clawed feet. Armed three ways - a laser
rifle, a laser bow (a quiver on its back) and a labrys, the Minoan double axe
- each weapon on its own materials (MIN_Rifle*, MIN_Bow*, MIN_Axe*): the game
shows one of them (CosmosModels.apply's `hide`), so the three are one model.

The body is shared: the palace guard (guard.py) and the other empires'
androids (athenian.py, spartan.py, mycenaean.py, ionian.py, cycladic.py) are
this build in their own palettes, with their own marks (STYLE) and heads.
Its parts are the kit's (box / loft / tube / ball) and a few of its own:
slab (a chamfered plate of any outline), sweep (a tube along a path: horns,
crests), lathe (turned parts: roundels, eyes), hull (a skull through
stations), and paint laid proud of a surface - stroke (a line) and patch (a
filled shape) - on `flat` planes or any surface function (the frill's dish).
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import kit
from kit import ball, bone, box, mirror, rot, tube

GUN_HAND_R = (0.0, -0.075, -0.03)
GUN_HAND_L = (0.0, 0.26, -0.03)
KNEE_Z = kit.HIP_Z - kit.THIGH
AZ = kit.ANKLE_Z
TAU = math.tau

# The cape: a bone of its own, hanging from the shoulders down the back (tail_solver).
EXTRA_BONES = {
    "coat.B": ("pelvis", (0.0, 0.14, 1.52), (0, 0, -1), (0, -1, 0), 1.2),
}


CAPE_CLEAR = 0.07       # (m: how far behind a leg the cape keeps - the leg's half-thickness, less the cape's own offset back)
CAPE_BAND = (1.545, 1.42)   # (z at rest: the cape's top band, on the chest above the first, on its bone below the second -
CAPE_CUTS = [1.52, 1.495, 1.47, 1.445, 1.42]   # a soft fold under the clasp, where it bends over a chair's back)
# In a chair (kit.SEATS["sit"]): the cape's bone moved back over the chair's top rail and swung back - the band
# folds over the rail, the rest hangs behind the back, its hem clear of the floor. (angle back (degrees), where
# its head goes: forward of the top rail's back face, up from its top (m))
CAPE_SIT = (24.0, 0.047, 0.12)


def tail_solver(name, P, mats):
    """The cape: it hangs from the shoulders - carried by the chest, turning
    with it, staying upright as the body leans - a little out behind, pushed
    further by a leg swung back; lying down, it lies with the body."""
    follow = mats["chest"] @ (kit.REST["chest"].inverted() @ kit.REST[name])
    tip = abs(((P["ppitch"] + 180.0) % 360.0) - 180.0)
    w = min(1.0, tip / 55.0)               # (0 upright .. 1 lying / flipping: with the body)
    yaw = kit._rz(P["pyaw"] + P["twist"])
    fwd = yaw @ Vector((0, -1, 0))
    back = 0.0
    for sf in (".L", ".R"):
        back = max(back, -(mats["thigh" + sf].to_3x3() @ Vector((0, 1, 0))).dot(fwd))
    ang = 5.0 + math.degrees(math.asin(max(0.0, min(1.0, back)))) * 0.75
    # ... and further, out over the legs: clear of a knee, a shin, a heel kicked up behind
    piv = follow.translation
    seat = P.get("seat") or ""
    if seat == "sit":                       # (over the chair's back: kit.SEATS)
        a, fwd_, up_ = CAPE_SIT
        lo, hi = kit.SEATS["sit"]["rail"]
        hang = Matrix.Rotation(math.radians(a), 3, yaw @ Vector((1, 0, 0))) @ yaw @ kit.REST[name].to_3x3()
        return kit._m4(hang, Vector((0.0, hi[1] - fwd_, hi[2] + up_)))
    pts = []
    for sf in (".L", ".R"):
        kn, an = mats["shin" + sf].translation, mats["foot" + sf].translation
        pts += [(q, CAPE_CLEAR) for q in (kn, (kn + an) * 0.5, an, an + (an - kn).normalized() * 0.06)]
    if seat == "stool":                     # (clear of the seat of its own pelvis, and the stool's cushion)
        pel = mats["pelvis"]
        pts.append((pel.translation + pel.to_3x3() @ Vector((0, -0.06, -0.17)), 0.0))
        lo, hi = kit.SEATS["stool"]["seat"]
        pts.append((Vector((0.0, hi[1], hi[2])), -0.01))
    for q, clear in pts:
        r = q - piv
        drop = -r.z
        if drop > 0.15:
            ang = max(ang, math.degrees(math.atan2(r.dot(-fwd) + clear, drop)))
    hang = Matrix.Rotation(math.radians(ang), 3, yaw @ Vector((1, 0, 0))) @ yaw @ kit.REST[name].to_3x3()
    q = hang.to_quaternion().slerp(follow.to_3x3().to_quaternion(), w)
    return kit._m4(q.to_matrix(), follow.translation)


def materials():
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#efe2c2", shade=0.62, hi=0.06, tint=(0.95, 0.9, 0.96)),
        "armor2": kit.mat_toon("AUT_Armor2", "#d6c294", shade=0.64, tint=(0.95, 0.9, 0.96)),
        "joint": kit.mat_toon("MIN_Joint", "#1d2c4c", shade=0.62),
        "grey": kit.mat_toon("MIN_Navy", "#30507e", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#b8261c", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#7a1712", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#48e2ff", 1.6),
        "glow_y": kit.mat_glow("AUT_GlowY", "#c8f8ff", 1.7),
        "gold": kit.mat_toon("MIN_Gold", "#e6b440", shade=0.66, hi=0.15),
        "horn": kit.mat_toon("MIN_HornBone", "#f2ead6", shade=0.64, hi=0.05),
        "claw": kit.mat_toon("MIN_Claw", "#2b2420", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("MIN_Cloth", "#f1ebdd", shade=0.66),
        "coat": kit.mat_toon("MIN_CapeCloth", "#a5241d", shade=0.62),
        "coat2": kit.mat_toon("MIN_CapeCloth2", "#6c1511", shade=0.66),
        # the weapons, each its own (a variant shows one)
        "rifle": kit.mat_toon("MIN_RifleBody", "#e9d9ae", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#2c3c5e", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#e9b84a", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#4fe6ff", 1.8),
        "bow": kit.mat_toon("MIN_BowGold", "#e9b84a", shade=0.66, hi=0.15),
        "bow_g": kit.mat_glow("MIN_BowGlow", "#5ef0ff", 2.0),
        "bow_q": kit.mat_toon("MIN_BowQuiver", "#c99a3a", shade=0.66),
        "axe": kit.mat_toon("MIN_AxeBlade", "#efe2c2", shade=0.64, hi=0.1),
        "axe_r": kit.mat_toon("MIN_AxeRed", "#a8241c", shade=0.66),
        "axe_g": kit.mat_glow("MIN_AxeGlow", "#5ef0ff", 2.0),
        "axe_h": kit.mat_toon("MIN_AxeHaft", "#7a1d18", shade=0.66, hi=0.05),
        "ink": kit.mat_outline(),
    })
    paints()


def paints(paint="grey", line="red"):
    """The painted patterns' two colours, by the palette's keys: `paint` (the
    spirals, the petals' hearts) and `line` (thin borders)."""
    kit.M["paint"] = kit.M[paint]
    kit.M["line"] = kit.M[line]


# ---------------------------------------------------------------- parts of its own

def _obj(name, bm, mats, smooth=True, deg=50.0, recalc=True):
    """A mesh made here, on the current bone (as kit.mesh_object; no outline):
    smooth, its edges sharper than `deg` kept hard."""
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    lim = math.radians(deg) if deg else 9.0
    for f in bm.faces:
        f.smooth = smooth
    if smooth:
        for e in bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
                e.smooth = False
    k = 2
    base = name
    while name in bpy.data.objects:
        name = "%s.%d" % (base, k)
        k += 1
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    kit.coll().objects.link(ob)
    for m in mats:
        me.materials.append(kit.M[m])
    kit.PARTS.append((ob, kit._bone[0]))
    return ob


def crease(ob, deg=50.0):
    """A kit part's hard edges kept hard (its caps, a boxy section's corners)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.normal_update()
    lim = math.radians(deg)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
            e.smooth = False
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def loft(*a, **k):
    k.setdefault("outline", 0.0)
    return crease(kit.loft(*a, **k))


def mir(v, sx):
    return Vector((v[0] * sx, v[1], v[2]))


def slab(name, pts, at, nrm, uhint=(1, 0, 0), thick=0.02, mat="armor", bevel=0.006, off=(0.0, 0.0, 0.0), vhint=(0, 0, 1)):
    """A flat plate of any outline, its face chamfered: pts (u, v; m) in the
    plane facing `nrm` at `at` - u along `uhint` (squared to the plane), v the
    other way (toward `vhint`); `thick` deep, half sunk; off = (u, v, out)
    shifts it in its own plane and out along the normal."""
    n = Vector(nrm).normalized()
    eu = Vector(uhint) - n * Vector(uhint).dot(n)
    eu.normalize()
    ev = n.cross(eu)
    if ev.dot(Vector(vhint)) < 0:
        ev = -ev
    o = Vector(at) + eu * off[0] + ev * off[1] + n * off[2]
    k = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % k][1] - pts[(i + 1) % k][0] * pts[i][1] for i in range(k))
    if area < 0:
        pts = pts[::-1]
    ins = []
    c = min(bevel, thick * 0.6)
    for i in range(k):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % k])
        d1, d2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((-d1.y, d1.x)), Vector((-d2.y, d2.x))     # (inward, the outline counter-clockwise)
        m = (n1 + n2) / max(0.4, 1.0 + n1.dot(n2))
        ins.append(p1 + m * c)
    bm = bmesh.new()
    lo = [bm.verts.new(o + eu * p[0] + ev * p[1] - n * thick * 0.5) for p in pts]
    if c > 0:
        mid = [bm.verts.new(o + eu * p[0] + ev * p[1] + n * (thick * 0.5 - c)) for p in pts]
        top = [bm.verts.new(o + eu * p.x + ev * p.y + n * thick * 0.5) for p in ins]
    else:
        mid = top = [bm.verts.new(o + eu * p[0] + ev * p[1] + n * thick * 0.5) for p in pts]
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((lo[i], lo[j], mid[j], mid[i]))
        if c > 0:
            bm.faces.new((mid[i], mid[j], top[j], top[i]))
    bm.faces.new(top)
    bm.faces.new(lo[::-1])
    return _obj(name, bm, [mat], smooth=False)


def sweep(name, pts, rad, mat="horn", seg=10, n=2.0, hint=(1, 0, 0), tip=True, deg=50.0):
    """A tube along the path pts (a horn, a crest, a claw): round each point a
    superellipse - rad: a number or (a, b) per point, b along `hint`, a across
    it; tip: the last point closes to a point."""
    pts = [Vector(p) for p in pts]
    last = len(pts) - 1
    bm = bmesh.new()
    rows = []
    for i, p in enumerate(pts):
        if tip and i == last:
            rows.append([bm.verts.new(p)])
            continue
        fr = kit.frame(pts[min(i + 1, last)] - pts[max(i - 1, 0)], hint)
        r = rad[i]
        a, b = (r, r) if isinstance(r, (int, float)) else r
        rows.append([bm.verts.new(p + fr @ Vector((x, 0.0, z))) for (x, z) in kit._se(a, b, n, seg)])
    for k in range(len(rows) - 1):
        r0, r1 = rows[k], rows[k + 1]
        for i in range(seg):
            j = (i + 1) % seg
            if len(r1) == 1:
                bm.faces.new((r0[i], r0[j], r1[0]))
            else:
                bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(rows[0][::-1])
    if len(rows[-1]) > 1:
        bm.faces.new(rows[-1])
    return _obj(name, bm, [mat], deg=deg)


def lathe(name, at, axis, prof, mats, seg=16, up=(0, 0, 1), oval=1.0):
    """A turned part: the profile prof = [(radius, height[, k])...] spun round
    `axis` at `at` - k: the material (index into mats) of the band ending at
    that point. A radius of 0 closes it to a point; an open end gets a cap."""
    fr = kit.frame(Vector(axis).normalized(), up)       # x across, y = the axis, z up
    at = Vector(at)
    bm = bmesh.new()
    rows = []
    for p in prof:
        r, h = p[0], p[1]
        if r <= 1e-6:
            rows.append([bm.verts.new(at + fr @ Vector((0.0, h, 0.0)))])
        else:
            rows.append([bm.verts.new(at + fr @ Vector((math.cos(i / seg * TAU) * r * oval, h, math.sin(i / seg * TAU) * r)))
                         for i in range(seg)])
    for k in range(len(rows) - 1):
        mi = prof[k + 1][2] if len(prof[k + 1]) > 2 else 0
        r0, r1 = rows[k], rows[k + 1]
        if len(r0) == 1 and len(r1) == 1:
            continue
        for i in range(seg):
            j = (i + 1) % seg
            if len(r0) == 1:
                f = bm.faces.new((r0[0], r1[j], r1[i]))
            elif len(r1) == 1:
                f = bm.faces.new((r0[i], r0[j], r1[0]))
            else:
                f = bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
            f.material_index = mi
    if len(rows[0]) > 1:
        bm.faces.new(rows[0][::-1])
    if len(rows[-1]) > 1:
        f = bm.faces.new(rows[-1])
        f.material_index = prof[-1][2] if len(prof[-1]) > 2 else 0
    return _obj(name, bm, mats, deg=32.0)


def hull(name, st, mat="armor", n=2.8, seg=20, cap=0.5):
    """A skull, a snout, a jaw: lofted from back to front through the stations
    st = [(y, half-width, top z, bottom z[, n])...] (y: + back, - forward)."""
    y0, y1 = st[0][0], st[-1][0]
    secs = [((y0 - s[0]) / (y0 - y1), s[1], (s[2] - s[3]) * 0.5, s[4] if len(s) > 4 else n, 0.0, (s[2] + s[3]) * 0.5) for s in st]
    return loft(name, (0, y0, 0), (0, y1, 0), secs, mat=mat, front=(0, 0, 1), seg=seg, cap=cap)


def at_y(st, y):
    """A hull's stations at y: (half-width, top z, bottom z), between the two nearest."""
    for s0, s1 in zip(st, st[1:]):
        if s1[0] <= y <= s0[0]:
            t = (s0[0] - y) / (s0[0] - s1[0])
            return tuple(s0[i] + (s1[i] - s0[i]) * t for i in (1, 2, 3))
    s = st[0] if y > st[0][0] else st[-1]
    return s[1], s[2], s[3]


def jaw_teeth(name, st, ys, size, mat="tooth", inset=0.92, up=False, drop=0.006):
    """Teeth along both sides of a jaw: down from a skull's lower edge at each y (or up from a jaw's upper edge)."""
    roots = []
    for sx in (1.0, -1.0):
        for y in ys:
            w, zt, zb = at_y(st, y)
            roots.append((w * inset * sx, y, (zt - drop) if up else (zb + drop)))
    sz = (list(size) * 2) if isinstance(size, (list, tuple)) else size
    return teeth(name, roots, sz, mat, down=(0, 0, 1) if up else (0, 0, -1))


def grow(bone_name, s=1.0, pivot=(0.0, 0.02, 1.70), lift=0.0, skip=("Neck",), tilt=0.0, back=0.0):
    """The parts made so far on a bone, about a point: scaled (a head made
    bigger on its neck), tipped forward (tilt, degrees: a head carried nose
    down; negative: nose up), lifted and moved back (the big heads carried
    high and back on the neck, clear of the fists held up in a guard)."""
    pv = Vector(pivot)
    r = Matrix.Rotation(math.radians(tilt), 3, "X")
    for ob, bn in kit.PARTS:
        if bn != bone_name or ob.name.startswith(skip):
            continue
        for v in ob.data.vertices:
            v.co = pv + (r @ (v.co - pv)) * s + Vector((0, back, lift))


def teeth(name, roots, size, mat="tooth", down=(0, 0, -1), fat=0.3, sides=6):
    """A row of teeth: a cone at each root point, `size` long (a number, or one
    per tooth) along `down`."""
    d = Vector(down).normalized()
    t1 = d.orthogonal().normalized()
    t2 = d.cross(t1)
    bm = bmesh.new()
    for i, p in enumerate(roots):
        s = size[i] if isinstance(size, (list, tuple)) else size
        p = Vector(p)
        ring = [bm.verts.new(p - d * s * 0.25 + (t1 * math.cos(k / sides * TAU) + t2 * math.sin(k / sides * TAU)) * s * fat) for k in range(sides)]
        tipv = bm.verts.new(p + d * s)
        for k in range(sides):
            bm.faces.new((ring[k], ring[(k + 1) % sides], tipv))
        bm.faces.new(ring[::-1])
    return _obj(name, bm, [mat], deg=75.0)


# ---------------------------------------------------------------- paint: lines and shapes proud of a surface

def flat(at, normal, up=(0, 0, 1)):
    """A plane as a surface to paint on: (u, v) -> (point, normal); u to the
    right of one looking at it, v up."""
    n = Vector(normal).normalized()
    ex = Vector(up).cross(n)
    ex.normalize()
    ev = n.cross(ex)
    at = Vector(at)

    def f(u, v):
        return at + ex * u + ev * v, n
    return f


def _open(name, bm, mat, top, want):
    """An open skin (a painted shape's top and walls): wound alike, its top facing `want`."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    top.normal_update()
    if top.normal.dot(want) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    return _obj(name, bm, [mat], deg=40.0, recalc=False)


def stroke(name, path, w, surf, mat="red", lift=0.005, walls=True):
    """A painted line: along path [(u, v)...] on the surface, w wide (or a
    width per point), `lift` proud of it."""
    k = len(path)
    bm = bmesh.new()
    rows = []
    for i, (u, v) in enumerate(path):
        a = Vector(path[max(i - 1, 0)])
        b = Vector(path[min(i + 1, k - 1)])
        c = Vector((u, v))
        d1 = (c - a).normalized() if i > 0 else (b - c).normalized()
        d2 = (b - c).normalized() if i < k - 1 else d1
        t = (d1 + d2)
        t = t.normalized() if t.length > 1e-6 else d1
        wi = (w[i] if isinstance(w, (list, tuple)) else w) * 0.5 / max(0.5, t.dot(d1))
        nx, ny = -t.y, t.x
        pl, nl = surf(u + nx * wi, v + ny * wi)
        pr, nr = surf(u - nx * wi, v - ny * wi)
        row = [bm.verts.new(pl + nl * lift), bm.verts.new(pr + nr * lift)]
        if walls:
            row = [bm.verts.new(pl - nl * 0.003)] + row + [bm.verts.new(pr - nr * 0.003)]
        rows.append(row)
    top = None
    m = len(rows[0])
    for i in range(k - 1):
        for j in range(m - 1):
            f = bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
            if top is None and j == (1 if walls else 0):
                top = f
    if walls:
        bm.faces.new(rows[0])
        bm.faces.new(rows[-1][::-1])
    return _open(name, bm, mat, top, surf(*path[0])[1])


def patch(name, pts, surf, mat="red", lift=0.005, walls=True):
    """A painted shape: the outline pts [(u, v)...] filled, `lift` proud of the surface."""
    bm = bmesh.new()
    vs = [bm.verts.new((u, v, 0.0)) for (u, v) in pts]
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f])
    top = bm.faces[:][0]
    base = []
    for vtx, (u, v) in zip(vs, pts):
        p, nr = surf(u, v)
        vtx.co = p + nr * lift
        if walls:
            base.append(bm.verts.new(p - nr * 0.003))
    k = len(pts)
    if walls:
        for i in range(k):
            bm.faces.new((vs[i], vs[(i + 1) % k], base[(i + 1) % k], base[i]))
    return _open(name, bm, mat, top, surf(*pts[0])[1])


def spiral_path(r0, r1, turns, n=16, hand=1.0, a0=0.0, c=(0.0, 0.0)):
    out = []
    for i in range(n + 1):
        t = i / n
        r = r0 + (r1 - r0) * t
        a = a0 + t * turns * TAU
        out.append((c[0] + hand * r * math.cos(a), c[1] + r * math.sin(a)))
    return out


def circle(r, n=10, c=(0.0, 0.0), sy=1.0):
    return [(c[0] + r * math.cos(i / n * TAU), c[1] + r * sy * math.sin(i / n * TAU)) for i in range(n)]


def moved(pts, c=(0.0, 0.0), s=1.0, ang=0.0, flip=1.0):
    """An outline scaled, turned (degrees) and moved."""
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(c[0] + flip * s * (x * ca - y * sa), c[1] + s * (x * sa + y * ca)) for (x, y) in pts]


# ---- the marks: each drawn within a radius r on a surface

def m_spiral(surf, r, mat="red", hand=1.0, turns=1.8, w=0.2, lift=0.005, name="Spiral", walls=True):
    stroke(name, spiral_path(r * 0.1, r * 0.9, turns, n=int(turns * 9), hand=hand, a0=math.pi), w * r, surf, mat, lift=lift, walls=walls)
    patch(name + "Eye", circle(r * 0.17, 8), surf, mat, lift=lift, walls=walls)


def m_key(surf, s, mat="red", lift=0.004, name="Key", flip=1.0, walls=False):
    """A meander's key: a squared spiral."""
    pts = [(-1, -1), (-1, 1), (1, 1), (1, -0.42), (-0.2, -0.42), (-0.2, 0.3), (0.35, 0.3)]
    stroke(name, [(x * s * flip, y * s) for (x, y) in pts], 0.34 * s, surf, mat, lift=lift, walls=walls)


def m_lily(surf, r, mat="red", mat2="paint", lift=0.005, name="Lily"):
    """The Minoan lily: a pointed petal between two that curl outward, on a stem with a curled foot."""
    patch(name + "Petal", moved([(0, 0.95), (0.17, 0.5), (0.13, 0.05), (0, -0.12), (-0.13, 0.05), (-0.17, 0.5)], s=r), surf, mat, lift=lift)
    for fl in (1.0, -1.0):
        side = [(0.1, -0.12), (0.26, 0.16), (0.46, 0.42), (0.66, 0.44), (0.76, 0.24), (0.64, 0.1)]
        stroke(name + "Side", moved(side, s=r, flip=fl), [x * r for x in (0.15, 0.19, 0.17, 0.14, 0.11, 0.07)], surf, mat2, lift=lift)
        foot = [(0.0, -0.5), (0.24, -0.56), (0.42, -0.46), (0.46, -0.3), (0.33, -0.24)]
        stroke(name + "Foot", moved(foot, s=r, flip=fl), 0.09 * r, surf, mat, lift=lift, walls=False)
    stroke(name + "Stem", [(0, -0.1 * r), (0, -0.8 * r)], 0.11 * r, surf, mat, lift=lift)
    patch(name + "Base", moved([(-0.3, -0.78), (0.3, -0.78), (0.2, -0.95), (-0.2, -0.95)], s=r), surf, mat2, lift=lift)


def m_trisk(surf, r, mat="gold", lift=0.006, name="Trisk"):
    """A triskelion: three spirals round a point."""
    for k in range(3):
        a = math.radians(90 + 120 * k)
        c = (math.cos(a) * r * 0.5, math.sin(a) * r * 0.5)
        pts = spiral_path(r * 0.05, r * 0.42, 1.5, n=13, a0=a + math.pi)
        stroke(name, [(c[0] + x, c[1] + y) for (x, y) in pts] + [(0.0, 0.0)], 0.13 * r, surf, mat, lift=lift, walls=False)


def roundel(name, at, axis, r, bands, mats, h=0.02, seg=18):
    """A boss: a round plate, its face painted in rings - bands = [(how far
    out 0..1, k)...] from the middle (k: index into mats; the last, its edge)."""
    prof = [(0.0, h, bands[0][1])] + [(r * f, h, k) for (f, k) in bands]
    prof += [(r * 1.04, h - 0.006, bands[-1][1]), (r * 1.04, -0.02, bands[-1][1])]
    lathe(name, at, axis, prof, mats, seg=seg)
    return flat(Vector(at) + Vector(axis).normalized() * h, axis)


# ---------------------------------------------------------------- what a skin makes its own

def _pauldron_mark(at, axis, r, sx):
    m_spiral(roundel("PauldronDisc", at, axis, r, [(0.84, 0), (1.0, 1)], ["gold", "red2"]), r * 0.8, "red", hand=sx)


def _thigh_mark(at, axis, r, sx):
    m_spiral(roundel("ThighDisc", at, axis, r, [(0.86, 0), (1.0, 1)], ["armor2", "red"], h=0.012, seg=14), r * 0.8, "paint", hand=sx)


def _apron_mark(surf, r):
    m_lily(surf, r)


def _back_mark(surf, r):
    m_spiral(surf, r * 0.8, "red")


def _buckle_mark(surf, r):
    m_key(surf, r * 0.62, "red2", walls=True)


def _pec_mark(surf, r, sx):
    """A small labrys on each pec."""
    patch("PecMark", [(-r, 0.6 * r), (0, 0.12 * r), (r, 0.6 * r), (r, -0.6 * r), (0, -0.12 * r), (-r, -0.6 * r)], surf, "red", lift=0.004, walls=False)


STYLE = {}
STYLE0 = dict(
    pauldron=_pauldron_mark,      # (at, axis, r, sx): the pauldron's roundel
    thigh=_thigh_mark,            # (at, axis, r, sx): the boss on the thigh's outside
    apron=_apron_mark,            # (surf, r): the front apron's motif
    back=_back_mark,              # (surf, r): the back apron's
    buckle=_buckle_mark,          # (surf, r): on the belt's buckle
    pec=_pec_mark,                # (surf, r, sx): on each pec
    # the frill's paint (the triceratops head): the band inside its edge, the thin line inside that, the edge
    # itself, the petals at the top and their hearts, the spirals on the side lobes, the studs, the back's ribs
    frill=dict(band="gold", line="red", rim="armor2", petal="red", heart=None, spiral="red", stud="gold", rib="armor2"),
)


def style(**over):
    STYLE.clear()
    STYLE.update(STYLE0)
    STYLE.update(over)


# ---------------------------------------------------------------- the legs

def legs(sx, sf):
    hx = kit.HIP_X * sx
    # ---- thigh: a dark core, a heavy plate over the front and the outside, a raised plate with a red slit, a painted boss
    bone("thigh" + sf)
    ball("Hip", (hx, 0, kit.HIP_Z), 0.088, "joint", seg=12)
    loft("ThighCore", (hx, 0.005, kit.HIP_Z - 0.03), (hx, 0.0, KNEE_Z + 0.02), [(0, 0.082, 0.09), (1, 0.06, 0.066)], mat="joint", seg=14)
    loft("ThighArmor", (hx + 0.02 * sx, -0.016, kit.HIP_Z - 0.05), (hx + 0.008 * sx, -0.014, KNEE_Z + 0.085),
         [(0, 0.076, 0.088, 3), (0.3, 0.107, 0.117, 3.2), (0.7, 0.093, 0.101, 3.2), (1, 0.07, 0.078, 3)], cap=0.7)
    front = (hx + 0.024 * sx, -0.128, 0.8)
    fn = (0.1 * sx, -1, -0.07)
    slab("ThighPlate", [(-0.05, 0.095), (0.05, 0.095), (0.062, 0.03), (0.036, -0.105), (-0.036, -0.105), (-0.062, 0.03)], front, fn,
         thick=0.024, mat="armor2", bevel=0.007)
    slab("ThighRed", [(-0.03, 0.075), (0.03, 0.075), (0.036, 0.03), (0.0, -0.02), (-0.036, 0.03)], front, fn, thick=0.024, mat="red",
         bevel=0.004, off=(0, 0, 0.004))
    slab("ThighSlit", [(-0.009, -0.035), (0.009, -0.035), (0.007, -0.09), (-0.007, -0.09)], front, fn, thick=0.024, mat="glow", bevel=0.002,
         off=(0, 0, 0.003))
    STYLE["thigh"]((hx + 0.124 * sx, -0.012, 0.8), (sx, 0, 0), 0.062, sx)
    slab("ThighBack", [(-0.04, 0.09), (0.04, 0.09), (0.03, -0.09), (-0.03, -0.09)], (hx + 0.018 * sx, 0.092, 0.79), (0, 1, 0.07), thick=0.022,
         mat="red", bevel=0.005)
    tube("ThighBand", (hx, -0.004, KNEE_Z + 0.105), (hx, -0.004, KNEE_Z + 0.07), 0.07, 0.064, mat="grey", seg=14)
    # ---- shin: a big knee cap, a heavy greave, an arched panel on its outside, a plate down its front, a light down the calf
    bone("shin" + sf)
    ball("Knee", (hx, 0.0, KNEE_Z), 0.066, "joint", seg=12)
    tube("KneeBolt", (hx - 0.078, 0, KNEE_Z), (hx + 0.078, 0, KNEE_Z), 0.03, mat="red2", seg=10)
    box("KneeCap", (0.108, 0.058, 0.135), (hx, -0.072, KNEE_Z + 0.006), taper=((0.78, 1.0), (0.7, 0.8)), r=rot(8), mat="armor")
    loft("ShinCore", (hx, 0.01, KNEE_Z - 0.03), (hx, 0.02, AZ + 0.02), [(0, 0.058, 0.064), (1, 0.046, 0.052)], mat="joint", seg=14)
    loft("Greave", (hx, -0.008, KNEE_Z - 0.075), (hx, 0.0, AZ + 0.045),
         [(0, 0.064, 0.07, 3), (0.28, 0.093, 0.107, 3.2, 0, -0.012), (0.7, 0.079, 0.087, 3.2), (1, 0.082, 0.092, 3.4)], cap=0.6)
    out = (hx + 0.09 * sx, -0.004, 0.345)
    slab("ShinPlate", [(-0.054, 0.115), (0.048, 0.115), (0.062, 0.03), (0.042, -0.12), (-0.042, -0.12), (-0.062, 0.03)], out, (sx, 0, 0),
         (0, -1, 0), thick=0.03, bevel=0.008)
    sf_ = flat((out[0] + 0.015 * sx, out[1], out[2]), (sx, 0, 0))
    arch = [(-0.038, -0.1), (-0.038, 0.03), (-0.026, 0.07), (0, 0.09), (0.026, 0.07), (0.038, 0.03), (0.038, -0.1),
            (0.021, -0.1), (0.021, 0.03), (0.013, 0.054), (0, 0.064), (-0.013, 0.054), (-0.021, 0.03), (-0.021, -0.1)]
    patch("ShinArch", arch, sf_, "red", lift=0.004)
    patch("ShinArchIn", [(-0.017, -0.1), (-0.017, 0.028), (-0.01, 0.048), (0, 0.056), (0.01, 0.048), (0.017, 0.028), (0.017, -0.1)], sf_,
          "paint", lift=0.003, walls=False)
    patch("ShinGlow", [(-0.007, -0.092), (0.007, -0.092), (0.007, 0.022), (0, 0.034), (-0.007, 0.022)], sf_, "glow", lift=0.006)
    sp_ = (hx, -0.1, 0.36)
    slab("ShinFront", [(-0.03, 0.095), (0.03, 0.095), (0.04, 0.02), (0.026, -0.115), (-0.026, -0.115), (-0.04, 0.02)], sp_, (0, -1, 0.07),
         thick=0.022, mat="armor2", bevel=0.006)
    slab("ShinRed", [(-0.016, -0.03), (0.016, -0.03), (0.014, -0.09), (-0.014, -0.09)], sp_, (0, -1, 0.07), thick=0.022, mat="red",
         bevel=0.003, off=(0, 0, 0.004))
    slab("CalfDark", [(-0.032, 0.095), (0.032, 0.095), (0.026, -0.095), (-0.026, -0.095)], (hx, 0.093, 0.31), (0, 1, -0.23), thick=0.014,
         mat="joint", bevel=0.004)
    slab("CalfGlow", [(-0.011, 0.076), (0.011, 0.076), (0.009, -0.076), (-0.009, -0.076)], (hx, 0.093, 0.31), (0, 1, -0.23), thick=0.014,
         mat="glow", bevel=0.002, off=(0, 0, 0.004))
    # the ankle: a gold ring, a flared cuff of plates
    tube("AnkleRing", (hx, 0.0, AZ + 0.128), (hx, 0.0, AZ + 0.1), 0.084, 0.086, mat="gold", seg=14)
    loft("AnkleCuff", (hx, 0.0, AZ + 0.11), (hx, 0.004, AZ + 0.02), [(0, 0.08, 0.09, 3.4), (1, 0.102, 0.116, 3.4)], seg=16)
    slab("AnkleGuard", [(-0.05, 0.045), (0.05, 0.045), (0.062, -0.01), (0.04, -0.05), (-0.04, -0.05), (-0.062, -0.01)], (hx, -0.112, AZ + 0.06),
         (0, -1, 0.42), thick=0.024, bevel=0.007)
    for s in (1.0, -1.0):
        slab("AnkleSide", [(-0.05, 0.04), (0.05, 0.04), (0.058, -0.012), (0.036, -0.045), (-0.036, -0.045), (-0.058, -0.012)],
             (hx + 0.1 * s, 0.006, AZ + 0.058), (s, 0, 0.42), (0, -1, 0), thick=0.022, bevel=0.007)
    # ---- the foot: a dinosaur's, armoured - a heavy instep, three broad toes with capped claws, a spur back
    bone("foot" + sf)
    ball("Ankle", (hx, 0.0, AZ), 0.054, "joint", seg=10)
    box("Sole", (0.15, 0.26, 0.034), (hx, -0.04, 0.017), mat="joint", taper=(0.94, 0.97), bevel=0.008)
    box("Heel", (0.13, 0.11, 0.094), (hx, 0.05, 0.075), taper=(0.85, 0.8))
    box("Instep", (0.15, 0.17, 0.096), (hx, -0.058, 0.078), taper=(0.8, 0.74), shear=(0, 0.036))
    slab("FootRed", [(-0.034, 0.036), (0.034, 0.036), (0.026, -0.044), (-0.026, -0.044)], (hx, -0.064, 0.129), (0, -0.26, 1), thick=0.012,
         mat="red", bevel=0.003, vhint=(0, 1, 0))
    slab("HeelLight", [(-0.026, 0.014), (0.026, 0.014), (0.026, -0.014), (-0.026, -0.014)], (hx, 0.102, 0.07), (0, 1, 0.18), thick=0.012,
         mat="glow", bevel=0.002)
    for dx, ln, spl in ((-0.05, 0.075, -0.014), (0.0, 0.092, 0.0), (0.05, 0.075, 0.014)):
        x = hx + dx
        y1 = -0.13 - ln
        loft("Toe", (x, -0.12, 0.05), (x + spl, y1, 0.04), [(0, 0.024, 0.033, 3.4), (0.6, 0.024, 0.031, 3.4), (1, 0.022, 0.027, 3.2)],
             mat="armor", front=(0, 0, 1), seg=10, cap=0.4)
        sweep("Claw", [(x + spl, y1 + 0.008, 0.04), (x + spl * 1.2, y1 - 0.03, 0.034), (x + spl * 1.35, y1 - 0.055, 0.01)],
              [(0.028, 0.023), (0.021, 0.019), 0], mat="claw", seg=8)
    sweep("Spur", [(hx, 0.08, 0.055), (hx, 0.125, 0.04), (hx, 0.15, 0.006)], [0.02, 0.014, 0], mat="claw", seg=8)


# ---------------------------------------------------------------- the body

def _belt_at(x, back=False, a=0.166, b=0.121, n=3.2, cy=0.004):
    """The belt's surface at side position x (front or back): the point, its outward normal."""
    y = b * (1.0 - abs(x / a) ** n) ** (1.0 / n)
    nx = abs(x / a) ** (n - 1) / a * (1 if x >= 0 else -1)
    ny = abs(y / b) ** (n - 1) / b
    s = 1.0 if back else -1.0
    return Vector((x, cy + s * y, 0.0)), Vector((nx, s * ny, 0.0)).normalized()


def belt(cz=1.08):
    """The meander belt: a band of plate between two thin lines, a key of the meander every few fingers, the buckle."""
    loft("Belt", (0, 0.004, cz - 0.042), (0, 0.004, cz + 0.062), [(0, 0.168, 0.123, 3.2), (0.8, 0.165, 0.12, 3.2), (1, 0.132, 0.098, 3.2)],
         mat="armor")
    for z in (cz - 0.042, cz + 0.025):
        loft("BeltRim", (0, 0.004, z), (0, 0.004, z + 0.012), [(0, 0.173, 0.128, 3.2), (1, 0.173, 0.128, 3.2)], mat="line")
    for back in (False, True):
        for k, x in enumerate((-0.118, -0.072, 0.072, 0.118) if not back else (-0.118, -0.072, -0.026, 0.026, 0.072, 0.118)):
            p, nr = _belt_at(x, back)
            m_key(flat((p.x, p.y, cz), nr), 0.017, "line", flip=1.0 if (x > 0) != back else -1.0, name="BeltKey")
    for sx in (1.0, -1.0):
        m_key(flat((0.166 * sx, 0.004, cz), (sx, 0, 0)), 0.017, "line", name="BeltKey")
    box("Buckle", (0.09, 0.034, 0.09), (0, -0.126, cz), mat="gold", bevel=0.01, outline=0)
    STYLE["buckle"](flat((0, -0.143, cz), (0, -1, 0)), 0.036)


APRON = []          # the apron's parts (objects): hung from the thighs when the parts are merged (_hang_apron)
APRON_TOP, APRON_LOW = 1.035, 0.93  # (pelvis only above TOP, the thighs' only below LOW: the back panel)
APRON_FRONT = (1.09, 0.99)          # (the front panel's: its top already half on the thighs - a knee raised high lifts it
                                    #  instead of passing up through it; the belt covers its top edge)
APRON_CUTS = ([0.93, 0.96, 0.99, 1.02], [0.0])   # (z: where it bends - between LOW and TOP; x: its split)
APRON_GAP = 0.0012                   # (the apron split down the middle: each half on its own thigh)


def apron():
    """The short apron, front and back: a bordered panel, the skin's motif on it, a band of meander at its hem.
    It hangs from the belt and moves with the legs: split down the middle, each half's lower part carried by
    its thigh, so a stride or a kick swings it instead of passing through it."""
    first = len(kit.PARTS)
    for ny, y, w, h, key in ((-1.0, -0.163, 0.2, 0.3, "apron"), (1.0, 0.142, 0.18, 0.26, "back")):
        nrm = (0, ny, 0.24)                  # (flared: its hem stands off the thighs)
        at = (0, y, 1.045 - h * 0.5)
        ux = (-ny, 0, 0)
        slab("ApronEdge", [(-w / 2, h / 2), (w / 2, h / 2), (w / 2 + 0.006, -h / 2), (-w / 2 - 0.006, -h / 2)], at, nrm, ux, thick=0.016,
             mat="red2", bevel=0.004)
        wi, hi = w / 2 - 0.014, h / 2 - 0.012
        slab("ApronField", [(-wi, hi), (wi, hi), (wi + 0.005, -hi + 0.04), (-wi - 0.005, -hi + 0.04)], at, nrm, ux, thick=0.016, mat="cloth",
             bevel=0.003, off=(0, 0, 0.006))
        slab("ApronLine", [(-wi, hi - 0.012), (wi, hi - 0.012), (wi, hi - 0.024), (-wi, hi - 0.024)], at, nrm, ux, thick=0.016, mat="paint",
             bevel=0.0, off=(0, 0, 0.009))
        slab("ApronBand", [(-w / 2 - 0.008, -hi + 0.042), (w / 2 + 0.008, -hi + 0.042), (w / 2 + 0.01, -h / 2 - 0.006),
                           (-w / 2 - 0.01, -h / 2 - 0.006)], at, nrm, ux, thick=0.026, mat="gold", bevel=0.004, off=(0, 0, 0.004))
        n = Vector(nrm).normalized()
        face = flat(Vector(at) + n * 0.0145, nrm)
        STYLE[key](lambda u, v, f=face, c=0.035 - 0.012: f(u, v + c), min(w, h) * 0.36)
        band = flat(Vector(at) + n * 0.017, nrm)
        for k in range(4):
            m_key(lambda u, v, f=band, c=((k - 1.5) * (w / 4.2), -h / 2 + 0.027): f(u + c[0], v + c[1]), 0.013, "red", name="ApronKey",
                  flip=1.0 if k % 2 else -1.0)
    APRON[:] = [ob for ob, _b in kit.PARTS[first:]]
    if not getattr(kit.merge_parts, "hangs_apron", False):
        merge = kit.merge_parts

        def merge_parts():
            w = _fold_apron()
            made = merge()
            _hang_apron(made, w)
            return made
        merge_parts.hangs_apron = True
        kit.merge_parts = merge_parts        # (build.py: rig_parts, then merge_parts - the apron's weights set after)


def _smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def apron_weights(p):
    """(pelvis, thigh.L, thigh.R) for a point of the apron at rest."""
    if p.y < 0.0:
        t = _smooth(APRON_FRONT[0], APRON_FRONT[1], p.z)
    else:
        t = _smooth(APRON_TOP, APRON_LOW, p.z)
    s = 1.0 if p.x > 0.0 else 0.0
    return 1.0 - t, t * s, t * (1.0 - s)


def _fold_apron():
    """The apron's parts cut across into rows and columns (so they bend where the
    weights change); each vertex's weights, by its place at rest."""
    w = {}
    for ob in APRON:
        if ob.name not in bpy.data.objects or ob.type != "MESH":
            continue
        mw = ob.matrix_world
        inv = mw.inverted()
        nm = mw.to_3x3().transposed()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        for axis, cuts in ((2, APRON_CUTS[0]), (0, APRON_CUTS[1])):
            d = Vector((0, 0, 0))
            d[axis] = 1.0
            for c in cuts:
                pt = Vector((0, 0, 0))
                pt[axis] = c
                bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=inv @ pt,
                                       plane_no=(nm @ d).normalized())
        # split down the middle: the cut's vertices doubled, each copy a hair toward its own half
        mid = [e for e in bm.edges if all(abs((mw @ v.co).x) < 1e-5 for v in e.verts)]
        if mid:
            bmesh.ops.split_edges(bm, edges=mid)
        for v in bm.verts:
            p = mw @ v.co
            if abs(p.x) < 1e-5 and v.link_faces:
                side = sum((mw @ f.calc_center_median()).x for f in v.link_faces)
                v.co = inv @ (p + Vector((APRON_GAP if side > 0 else -APRON_GAP, 0, 0)))
        bm.to_mesh(ob.data)
        bm.free()
        for v in ob.data.vertices:
            p = mw @ v.co
            w[_key(p)] = apron_weights(p)
    return w


def _key(p):
    return (round(p.x, 4), round(p.y, 4), round(p.z, 4))


def _hang_apron(made, w):
    """The merged torso's apron vertices: weighted between the pelvis and the thighs."""
    for part in made:
        if part.name != "Torso":
            continue
        groups = {n: part.vertex_groups.get(n) or part.vertex_groups.new(name=n) for n in ("pelvis", "thigh.L", "thigh.R")}
        mw = part.matrix_world
        hit = 0
        for v in part.data.vertices:
            ws = w.get(_key(mw @ v.co))
            if ws is None:
                continue
            hit += 1
            for g, x in zip(("pelvis", "thigh.L", "thigh.R"), ws):
                if x > 1e-4:
                    groups[g].add([v.index], x, "REPLACE")
                else:
                    groups[g].remove([v.index])
        print("APRON: %d of the torso's vertices hung from the thighs (%d keys)" % (hit, len(w)))


def body():
    # ---- pelvis: the hips, the belt, plates over the hip joints, the apron
    bone("pelvis")
    loft("Hips", (0, 0.005, 0.885), (0, 0.005, 1.085), [(0, 0.10, 0.088, 3), (0.5, 0.165, 0.112, 3), (1, 0.132, 0.096, 3)], mat="joint")
    box("Cod", (0.11, 0.07, 0.17), (0, -0.088, 0.965), taper=((0.4, 0.8), (1.0, 1.0)), r=rot(-10), mat="armor2", outline=0)
    box("Rear", (0.2, 0.06, 0.13), (0, 0.095, 0.975), taper=((0.6, 0.8), (1.0, 1.0)), r=rot(10), outline=0)
    belt()
    for sx in (1.0, -1.0):
        at = (0.196 * sx, 0.0, 0.975)
        slab("HipPlate", [(-0.085, 0.07), (0.085, 0.07), (0.07, -0.05), (0.0, -0.088), (-0.07, -0.05)], at, (sx, 0, 0.14), (0, -1, 0),
             thick=0.03, bevel=0.008)
        slab("HipRed", [(-0.055, 0.045), (0.055, 0.045), (0.044, -0.03), (0.0, -0.055), (-0.044, -0.03)], at, (sx, 0, 0.14), (0, -1, 0),
             thick=0.03, mat="red", bevel=0.004, off=(0, 0, 0.005))
    apron()
    # ---- spine: the dark waist, the glowing core between ab plates, lit seams
    bone("spine")
    loft("Waist", (0, 0.0, 1.07), (0, 0.0, 1.30), [(0, 0.114, 0.09, 3), (0.5, 0.1, 0.082, 3), (1, 0.136, 0.104, 3)], mat="joint")
    core = (0, -0.09, 1.2)
    cn = (0, -1, 0.06)
    slab("CoreFrame", [(-0.064, 0.105), (0.064, 0.105), (0.042, -0.03), (0.03, -0.118), (-0.03, -0.118), (-0.042, -0.03)], core, cn,
         thick=0.03, mat="joint", bevel=0.006)
    slab("Core", [(-0.046, 0.09), (0.046, 0.09), (0.027, -0.03), (0.018, -0.102), (-0.018, -0.102), (-0.027, -0.03)], core, cn, thick=0.03,
         mat="glow", bevel=0.004, off=(0, 0, 0.005))
    slab("CoreHot", [(-0.022, 0.07), (0.022, 0.07), (0.011, -0.02), (0.006, -0.075), (-0.006, -0.075), (-0.011, -0.02)], core, cn, thick=0.03,
         mat="glow_y", bevel=0.003, off=(0, 0, 0.009))
    for sx in (1.0, -1.0):
        slab("Ab", [(-0.034, 0.04), (0.04, 0.052), (0.046, -0.03), (-0.03, -0.045)], (0.094 * sx, -0.07, 1.238), (0.6 * sx, -1, 0), (sx, 0, 0),
             thick=0.03, mat="armor2")
        slab("Ab", [(-0.03, 0.036), (0.036, 0.042), (0.04, -0.03), (-0.024, -0.04)], (0.082 * sx, -0.066, 1.146), (0.6 * sx, -1, 0),
             (sx, 0, 0), thick=0.03, mat="armor2")
        slab("CoreSeam", [(0.0, 0.1), (0.005, 0.1), (-0.021, -0.1), (-0.026, -0.1)], (0.062 * sx, -0.086, 1.195), (0.35 * sx, -1, 0),
             (sx, 0, 0), thick=0.014, mat="glow", bevel=0.0)
        box("Flank", (0.035, 0.11, 0.12), (0.106 * sx, 0.0, 1.19), mat="grey", taper=(0.9, 0.8), r=rot(0, -6 * sx), outline=0)
    slab("BackCoreFrame", [(-0.04, 0.085), (0.04, 0.085), (0.03, -0.085), (-0.03, -0.085)], (0, 0.084, 1.19), (0, 1, 0), thick=0.02,
         mat="joint", bevel=0.004)
    slab("BackCore", [(-0.018, 0.07), (0.018, 0.07), (0.012, -0.07), (-0.012, -0.07)], (0, 0.084, 1.19), (0, 1, 0), thick=0.02, mat="glow",
         bevel=0.003, off=(0, 0, 0.004))
    # ---- chest: a dark frame carrying layered plates
    bone("chest")
    loft("ChestFrame", (0, 0.0, 1.27), (0, 0.0, 1.59),
         [(0, 0.14, 0.106, 3.2), (0.35, 0.202, 0.136, 3.2, 0, 0.004), (0.75, 0.222, 0.136, 3.2), (1, 0.155, 0.1, 3)], mat="joint", cap=0.5)
    loft("Gorget", (0, 0.012, 1.56), (0, 0.012, 1.635), [(0, 0.105, 0.105, 3), (1, 0.08, 0.085, 3)], mat="joint", seg=16)
    box("Sternum", (0.034, 0.02, 0.2), (0, -0.136, 1.46), mat="joint", bevel=0.004, outline=0)
    slab("SternumGlow", [(-0.006, 0.045), (0.006, 0.045), (0.006, -0.045), (-0.006, -0.045)], (0, -0.146, 1.41), (0, -1, 0.1), thick=0.01,
         mat="glow", bevel=0.0)
    bar = (0, -0.108, 1.558)
    slab("ChestBar", [(-0.075, 0.032), (0.075, 0.032), (0.052, -0.034), (-0.052, -0.034)], bar, (0, -1, 0.5), thick=0.034, bevel=0.008)
    slab("ChestBarRed", [(-0.03, 0.014), (0.03, 0.014), (0.018, -0.018), (-0.018, -0.018)], bar, (0, -1, 0.5), thick=0.034, mat="red",
         bevel=0.003, off=(0, 0, 0.004))
    for sx in (1.0, -1.0):
        pn = (0.24 * sx, -1, 0.14)
        pec = (0.107 * sx, -0.13, 1.468)
        slab("Pec", [(-0.088, 0.07), (0.056, 0.082), (0.11, 0.036), (0.1, -0.052), (0.012, -0.1), (-0.088, -0.062)], pec, pn, (sx, 0, 0),
             thick=0.05, bevel=0.012)
        slab("PecUnder", [(-0.09, 0.062), (0.064, 0.074), (0.122, 0.03), (0.11, -0.068), (0.012, -0.116), (-0.09, -0.076)], pec, pn, (sx, 0, 0),
             thick=0.05, mat="armor2", bevel=0.008, off=(0, 0, -0.014))
        slab("PecTrim", [(-0.08, 0.062), (0.052, 0.073), (0.07, 0.052), (-0.08, 0.038)], pec, pn, (sx, 0, 0), thick=0.05, mat="red",
             bevel=0.003, off=(0, 0, 0.004))
        STYLE["pec"](flat(Vector(pec) + Vector(pn).normalized() * 0.025 + Vector((0.012 * sx, 0, -0.012)), pn), 0.026, sx)
        slab("PecSeam", [(-0.085, 0.0), (0.014, -0.036), (0.014, -0.046), (-0.085, -0.01)], pec, pn, (sx, 0, 0), thick=0.03, mat="glow",
             bevel=0.0, off=(0, -0.066, 0.0))
        slab("Rib", [(-0.058, 0.03), (0.062, 0.045), (0.07, -0.012), (-0.03, -0.042)], (0.122 * sx, -0.112, 1.332), (0.34 * sx, -1, -0.12),
             (sx, 0, 0), thick=0.036, mat="armor2", bevel=0.008)
        slab("RibLine", [(-0.046, 0.012), (0.058, 0.025), (0.06, 0.011), (-0.042, -0.002)], (0.122 * sx, -0.112, 1.332),
             (0.34 * sx, -1, -0.12), (sx, 0, 0), thick=0.036, mat="paint", bevel=0.0, off=(0, 0, 0.003))
        box("SidePlate", (0.04, 0.16, 0.16), (0.214 * sx, 0.0, 1.42), taper=((0.8, 0.8), (1.0, 1.0)), bevel=0.014, outline=0)
        # over the collar bones, sloping from the neck to the shoulders
        cl = (0.118 * sx, -0.012, 1.596)
        cnr = (0.3 * sx, -0.3, 1)
        slab("Clavicle", [(-0.062, 0.075), (0.08, 0.06), (0.09, -0.06), (-0.062, -0.085)], cl, cnr, (sx, 0, 0), thick=0.032, bevel=0.008,
             vhint=(0, 1, 0))
        slab("ClavicleRed", [(-0.03, 0.04), (0.055, 0.03), (0.062, -0.035), (-0.03, -0.05)], cl, cnr, (sx, 0, 0), thick=0.032, mat="red",
             bevel=0.003, off=(0, 0, 0.004), vhint=(0, 1, 0))
        # the shoulder blades
        bl = (0.118 * sx, 0.122, 1.462)
        bn = (0.22 * sx, 1, 0.1)
        slab("Blade", [(-0.082, 0.09), (0.07, 0.1), (0.086, -0.03), (0.0, -0.1), (-0.082, -0.07)], bl, bn, (sx, 0, 0), thick=0.046,
             bevel=0.012)
        slab("Lat", [(-0.06, 0.05), (0.07, 0.07), (0.075, -0.02), (-0.03, -0.07)], (0.105 * sx, 0.108, 1.33), (0.3 * sx, 1, -0.1), (sx, 0, 0),
             thick=0.034, mat="armor2", bevel=0.008)
        slab("BladeRed", [(-0.07, 0.078), (0.06, 0.087), (0.066, 0.058), (-0.07, 0.05)], bl, bn, (sx, 0, 0), thick=0.046, mat="red",
             bevel=0.003, off=(0, 0, 0.004))
        slab("BladePaint", [(-0.07, 0.03), (0.07, 0.036), (0.072, 0.012), (-0.07, 0.006)], bl, bn, (sx, 0, 0), thick=0.046, mat="paint",
             bevel=0.003, off=(0, 0, 0.004))
    # the spine's housing down the back, its lit vents
    box("BackSpine", (0.09, 0.056, 0.3), (0, 0.134, 1.44), mat="armor", bevel=0.012, outline=0)
    box("BackHump", (0.13, 0.08, 0.07), (0, 0.105, 1.588), mat="armor", taper=(0.75, 0.8), bevel=0.012, outline=0)
    for k in range(3):
        slab("BackVent", [(-0.026, 0.014), (0.026, 0.014), (0.02, -0.014), (-0.02, -0.014)], (0, 0.162, 1.53 - k * 0.07), (0, 1, 0),
             thick=0.012, mat="glow" if k else "joint", bevel=0.002)


# ---------------------------------------------------------------- the arms

def arms(sx, sf):
    S = kit.SHOULDER
    x = S.x * sx
    ez = S.z - kit.UPPER
    wz = ez - kit.FORE
    # ---- the pauldron: big and round, a band round its root, the skin's roundel on its end - its root clear of
    # the chest's side (the side plates reach x 0.234; kit.fit_pauldron keeps it clear as the arm moves)
    bone("pauldron" + sf)
    loft("Pauldron", (x + 0.022 * sx, 0, S.z + 0.014), (x + 0.13 * sx, 0, S.z + 0.004),
         [(0, 0.088, 0.075, 2.6), (0.25, 0.116, 0.102, 2.6), (0.7, 0.124, 0.112, 2.6), (1, 0.106, 0.096, 2.6)], front=(0, 0, 1), cap=0.3)
    loft("PauldronBand", (x + 0.03 * sx, 0, S.z + 0.013), (x + 0.048 * sx, 0, S.z + 0.012), [(0, 0.11, 0.097, 2.6), (1, 0.12, 0.106, 2.6)],
         mat="line", front=(0, 0, 1))
    STYLE["pauldron"]((x + 0.136 * sx, 0, S.z + 0.004), (sx, 0, 0), 0.09, sx)
    # ---- upper arm
    bone("upper" + sf)
    ball("Shoulder", (x, 0, S.z), 0.07, "joint", seg=12)
    loft("UpperCore", (x, 0, S.z - 0.03), (x, 0, ez + 0.02), [(0, 0.052, 0.056), (1, 0.044, 0.048)], mat="joint", seg=14)
    loft("UpperArmor", (x + 0.016 * sx, 0, S.z - 0.115), (x + 0.008 * sx, 0, ez + 0.066),
         [(0, 0.056, 0.062, 3), (0.45, 0.071, 0.077, 3.2), (1, 0.052, 0.056, 3)], cap=0.5, seg=16)
    up = (x + 0.079 * sx, 0, S.z - 0.19)
    slab("UpperPlate", [(-0.036, 0.062), (0.036, 0.062), (0.044, 0.01), (0.026, -0.066), (-0.026, -0.066), (-0.044, 0.01)], up, (sx, 0, 0),
         (0, -1, 0), thick=0.022, mat="armor2", bevel=0.006)
    slab("UpperRed", [(-0.02, 0.046), (0.02, 0.046), (0.024, 0.01), (0.0, -0.03), (-0.024, 0.01)], up, (sx, 0, 0), (0, -1, 0), thick=0.022,
         mat="red", bevel=0.003, off=(0, 0, 0.004))
    # ---- forearm: a heavy gauntlet, a shield plate on its outside with a lit arch
    bone("fore" + sf)
    ball("Elbow", (x, 0.0, ez), 0.056, "joint", seg=12)
    tube("ElbowBolt", (x - 0.06, 0, ez), (x + 0.06, 0, ez), 0.025, mat="red2", seg=10)
    lathe("ElbowCap", (x, 0.04, ez), (0, 1, 0), [(0, 0.032), (0.032, 0.028), (0.048, 0.008), (0.048, -0.01)], ["armor"], seg=10)
    loft("ForeCore", (x, 0, ez - 0.02), (x, 0, wz), [(0, 0.046, 0.05), (1, 0.038, 0.042)], mat="joint", seg=14)
    loft("Gauntlet", (x + 0.018 * sx, -0.004, ez - 0.05), (x + 0.018 * sx, -0.004, wz + 0.018),
         [(0, 0.052, 0.058, 3), (0.25, 0.079, 0.087, 3.2), (0.8, 0.072, 0.078, 3.2), (1, 0.056, 0.06, 3)], cap=0.5)
    sh = (x + 0.088 * sx, -0.004, ez - 0.148)
    slab("GauntletShield", [(-0.054, 0.112), (0.054, 0.112), (0.07, 0.03), (0.05, -0.106), (-0.05, -0.106), (-0.07, 0.03)], sh, (sx, 0, 0),
         (0, -1, 0), thick=0.034, bevel=0.009)
    fs = flat((sh[0] + 0.017 * sx, sh[1], sh[2]), (sx, 0, 0))
    patch("GauntletArch", [(-0.037, -0.08), (-0.037, 0.03), (-0.024, 0.068), (0, 0.086), (0.024, 0.068), (0.037, 0.03), (0.037, -0.08),
                           (0.02, -0.08), (0.02, 0.026), (0.011, 0.048), (0, 0.058), (-0.011, 0.048), (-0.02, 0.026), (-0.02, -0.08)], fs,
          "red", lift=0.004)
    patch("GauntletArchIn", [(-0.016, -0.08), (-0.016, 0.024), (-0.009, 0.042), (0, 0.05), (0.009, 0.042), (0.016, 0.024), (0.016, -0.08)], fs,
          "paint", lift=0.003, walls=False)
    patch("GauntletGlow", [(-0.006, -0.074), (0.006, -0.074), (0.006, 0.018), (0, 0.028), (-0.006, 0.018)], fs, "glow", lift=0.006)
    slab("ForeStrip", [(-0.006, 0.06), (0.006, 0.06), (0.006, -0.06), (-0.006, -0.06)], (x + 0.018 * sx, -0.086, ez - 0.15), (0, -1, 0),
         thick=0.012, mat="glow", bevel=0.0)
    tube("WristCuff", (x + 0.01 * sx, -0.004, wz + 0.034), (x + 0.01 * sx, -0.004, wz + 0.01), 0.062, 0.059, mat="gold", seg=14)
    # ---- the hand: a broad palm, three thick fingers and a thumb
    bone("hand" + sf)
    tube("Wrist", (x, 0, wz + 0.02), (x, 0, wz - 0.012), 0.042, mat="joint", seg=10)
    box("Palm", (0.05, 0.104, 0.082), (x, -0.004, wz - 0.036), mat="joint", bevel=0.01)
    hb = (x + 0.028 * sx, -0.004, wz - 0.032)
    slab("HandBack", [(-0.05, 0.04), (0.05, 0.04), (0.044, -0.044), (-0.044, -0.044)], hb, (sx, 0, 0), (0, -1, 0), thick=0.018, bevel=0.005)
    slab("HandRed", [(0, 0.024), (0.022, 0.0), (0, -0.026), (-0.022, 0.0)], hb, (sx, 0, 0), (0, -1, 0), thick=0.018, mat="red", bevel=0.002,
         off=(0, 0, 0.003))
    loft("Thumb", (x - 0.004 * sx, -0.056, wz - 0.03), (x - 0.014 * sx, -0.082, wz - 0.098), [(0, 0.019, 0.021, 3), (1, 0.014, 0.015, 3)],
         mat="armor2", seg=8, cap=0.5)
    bone("fingers" + sf)
    for fy in (-0.038, -0.004, 0.03):
        loft("Finger", (x, fy, wz - 0.056), (x, fy, wz - 0.142), [(0, 0.023, 0.0155, 3), (1, 0.018, 0.012, 3)], mat="armor2", seg=8, cap=0.5)
    box("Knuckles", (0.016, 0.098, 0.034), (x + 0.027 * sx, -0.004, wz - 0.074), bevel=0.005)


# ---------------------------------------------------------------- the head: a triceratops

def neck():
    loft("Neck", (0, 0.03, 1.56), (0, 0.012, 1.74), [(0, 0.07, 0.076), (1, 0.062, 0.068)], mat="joint", seg=14)
    for z in (1.615, 1.665):
        tube("NeckRing", (0, 0.027, z), (0, 0.024, z + 0.022), 0.077, 0.075, mat="red2", seg=14)


def eye(pos, d, r=0.016, sock="joint", lit="glow", seg=10, oval=1.0):
    """A glowing eye in its dark socket, at pos, looking along d (oval: wider than tall)."""
    lathe("EyeSocket", pos, d, [(0, 0.003), (r * 1.4, 0.003), (r * 1.75, -0.012)], [sock], seg=seg, oval=oval)
    lathe("Eye", pos, d, [(0, 0.011), (r * 0.55, 0.009), (r * 0.92, 0.005), (r, 0.0)], [lit], seg=seg, oval=oval)


HEAD_TILT = 6.0          # (the skull carried nose down - was 26: its horns and jaw ran through the fists held up in a guard)


def frill(C=(0, 0.075, 1.79), R=0.41, tilt=28.0 + HEAD_TILT, span=115.0, lobes=9, cup=0.07, th=0.022):
    """The great frill: a scalloped dish of bone behind the skull, tilted back,
    its rim curling forward - painted (STYLE["frill"]): a band and a thin line
    inside the edge, petals fanning from the middle between raised ribs, a
    spiral on each side lobe; a knob on every scallop; ribs down its back."""
    P = STYLE["frill"]
    tl = math.radians(tilt)
    ex = Vector((1, 0, 0))
    eu = Vector((0, math.sin(tl), math.cos(tl)))
    nf = Vector((0, -math.cos(tl), math.sin(tl)))
    C = Vector(C)
    sp = math.radians(span)

    def edge(a):
        ph = (a + sp) / (2 * sp) * lobes
        return R * (0.915 + 0.085 * abs(math.sin(ph * math.pi)) ** 0.5)

    def dish(u, v):                 # (u toward the character's left: the right of one facing it; v up the frill)
        p = C + ex * u + eu * v + nf * (cup * (u * u + v * v) / (R * R))
        n = (nf - (ex * u + eu * v) * (2 * cup / (R * R))).normalized()
        return p, n

    def front(u, v):
        p, n = dish(u, v)
        return p + n * th * 0.5, n

    def back(u, v):
        p, n = dish(-u, v)
        return p - n * th * 0.5, -n

    na = lobes * 5
    rings = [0.1, 0.42, 0.62, 0.77, 0.805, 0.895, 1.0]
    mats = ["armor", P["band"], P["line"], P["rim"], "armor2"]
    fm = [0, 0, 0, 2, 1, 3]          # the front's bands, from the middle out
    bk = [4, 4, 4, 4, 1, 3]
    bm = bmesh.new()
    gf, gb = [], []
    for j in range(na + 1):
        a = -sp + 2 * sp * j / na
        cf, cb = [], []
        for i, f in enumerate(rings):
            r = edge(a) if i == len(rings) - 1 else f * R
            p, n = dish(r * math.sin(a), r * math.cos(a))
            cf.append(bm.verts.new(p + n * th * 0.5))
            cb.append(bm.verts.new(p - n * th * 0.5))
        gf.append(cf)
        gb.append(cb)
    nr = len(rings)
    for j in range(na):
        for i in range(nr - 1):
            f = bm.faces.new((gf[j][i], gf[j + 1][i], gf[j + 1][i + 1], gf[j][i + 1]))
            f.material_index = fm[i]
            f = bm.faces.new((gb[j][i], gb[j][i + 1], gb[j + 1][i + 1], gb[j + 1][i]))
            f.material_index = bk[i]
        f = bm.faces.new((gf[j][nr - 1], gf[j + 1][nr - 1], gb[j + 1][nr - 1], gb[j][nr - 1]))
        f.material_index = 3
        bm.faces.new((gf[j][0], gb[j][0], gb[j + 1][0], gf[j + 1][0]))
    for j in (0, na):
        for i in range(nr - 1):
            f = bm.faces.new((gf[j][i], gf[j][i + 1], gb[j][i + 1], gb[j][i]))
            f.material_index = 3
    _obj("Frill", bm, mats, deg=60.0)
    # the knobs on the scallops
    step = 2 * sp / lobes
    for k in range(lobes):
        a = -sp + step * (k + 0.5)
        p, n = dish(edge(a) * 0.98 * math.sin(a), edge(a) * 0.98 * math.cos(a))
        ball("FrillStud", tuple(p), 0.026, P["stud"], scale=(1, 0.8, 1), seg=8)
    # the petals fanning over the top, a raised rib between each two
    pet = [(0.3, 0.0), (0.5, 5.4), (0.65, 8.4), (0.725, 6.8), (0.752, 0.0), (0.725, -6.8), (0.65, -8.4), (0.5, -5.4)]

    def polar(pts, a0, s=1.0, mid=0.57):
        out = []
        for (f, da) in pts:
            r = (mid + (f - mid) * s) * R
            a = a0 + math.radians(da) * s
            out.append((r * math.sin(a), r * math.cos(a)))
        return out
    mid = lobes // 2
    for k in range(mid - 2, mid + 3):
        a = -sp + step * (k + 0.5)
        if P["petal"]:
            patch("FrillPetal", polar(pet, a), front, P["petal"], lift=0.004)
        if P["heart"]:
            patch("FrillHeart", polar(pet, a, 0.5, 0.6), front, P["heart"], lift=0.008)
    for k in range(mid - 2, mid + 4):
        a = -sp + step * k
        stroke("FrillRidge", [(f * R * math.sin(a), f * R * math.cos(a)) for f in (0.24, 0.6, 0.9)], [0.012, 0.016, 0.02], front, "armor",
               lift=0.007)
    # a spiral on each side lobe
    if P["spiral"]:
        for sx in (1.0, -1.0):
            a = sx * (sp - step * 1.0)
            c = (0.55 * R * math.sin(a), 0.55 * R * math.cos(a))
            pts = spiral_path(0.014, 0.088, 1.85, n=17, hand=-sx, a0=math.radians(200), c=c)
            stroke("FrillSpiral", pts, 0.03, front, P["spiral"], lift=0.005)
            patch("FrillSpiralEye", circle(0.02, 8, c), front, P["spiral"], lift=0.005)
    # ribs down the back
    for k in range(1, lobes):
        a = -sp + step * k
        pts = [(f * R * math.sin(a), f * R * math.cos(a)) for f in (0.22, 0.5, 0.78)]
        stroke("FrillRib", [(-u, v) for (u, v) in pts], 0.022, back, P["rib"], lift=0.008, walls=True)
    return front


def head():
    """The triceratops: the beaked skull, long brow horns curving forward, a nose horn, glowing eyes, the frill."""
    bone("head")
    neck()
    st = [(0.09, 0.078, 1.86, 1.70), (0.02, 0.102, 1.895, 1.685), (-0.06, 0.108, 1.9, 1.68), (-0.14, 0.098, 1.878, 1.684),
          (-0.21, 0.086, 1.848, 1.688), (-0.27, 0.074, 1.815, 1.69), (-0.31, 0.06, 1.784, 1.692)]
    hull("Skull", st, "armor", n=3.1)
    hull("Jaw", [(0.035, 0.084, 1.694, 1.635), (-0.08, 0.084, 1.69, 1.625), (-0.19, 0.066, 1.69, 1.636), (-0.275, 0.044, 1.69, 1.652)],
         "armor2", n=3.1, seg=16)
    sweep("Beak", [(0, -0.285, 1.742), (0, -0.335, 1.73), (0, -0.364, 1.7), (0, -0.372, 1.652)],
          [(0.045, 0.058), (0.037, 0.046), (0.023, 0.026), 0], mat="horn", seg=10)
    sweep("JawBeak", [(0, -0.25, 1.666), (0, -0.305, 1.668), (0, -0.337, 1.692)], [(0.02, 0.034), (0.014, 0.022), 0], mat="horn", seg=8)
    # the stripe down the snout (a thin line of the plate's colour in it), the cheeks' stripes
    top = [(0, s[0], s[2] + 0.001) for s in st[1:]]
    sweep("SnoutStripe", top, [(0.004, 0.024), (0.004, 0.026), (0.004, 0.023), (0.004, 0.019), (0.004, 0.015), (0.004, 0.011)], mat="red",
          seg=6, tip=False)
    sweep("SnoutLine", top[1:], [(0.006, 0.007)] * 5, mat="armor", seg=6, tip=False)
    for sx in (1.0, -1.0):
        sweep("CheekStripe", [((s[1] + 0.001) * sx, s[0], (s[2] + s[3]) * 0.5 - 0.04) for s in st[1:5]],
              [(0.012, 0.004), (0.014, 0.004), (0.012, 0.004), (0.008, 0.004)], mat="red", seg=6, tip=False, hint=(sx, 0, 0))
        # the brow horn: long, thick at its root, curving forward and up; a ring round the root
        base = Vector((0.062 * sx, -0.06, 1.868))
        pts, rad = [], []
        for i in range(8):
            t = i / 7
            pts.append(base + Vector((sx * (0.012 * t + 0.075 * t * t), -(0.34 * t - 0.07 * t * t), 0.14 * t + 0.2 * t ** 1.9)))
            rad.append(0.041 * (1 - t) ** 0.85 + 0.002)
        sweep("BrowHorn", pts, rad, mat="horn", seg=10)
        sweep("HornRing", [pts[0] + (pts[0] - pts[1]) * 0.3, pts[0] + (pts[1] - pts[0]) * 0.3], [0.048, 0.044], mat="red", seg=10, tip=False)
        # the eye: a glowing slit on the snout's shoulder, looking forward and out under a heavy brow; a plate over the cheek
        eye((0.0765 * sx, -0.176, 1.849), (0.68 * sx, -0.22, 0.7), 0.0155, oval=1.8, seg=12)
        loft("Brow", (0.066 * sx, -0.085, 1.888), (0.05 * sx, -0.215, 1.857), [(0, 0.024, 0.016, 3), (1, 0.014, 0.01, 3)], front=(0.3 * sx, 0, 1),
             seg=8, cap=0.4)
        slab("CheekPlate", [(-0.075, 0.03), (0.03, 0.036), (0.1, 0.012), (0.09, -0.03), (-0.02, -0.05), (-0.075, -0.03)],
             (0.1 * sx, -0.07, 1.775), (sx, -0.1, 0), (0, -1, 0), thick=0.022, mat="armor2", bevel=0.006)
        lathe("Nostril", (0.03 * sx, -0.292, 1.8), (0.5 * sx, -0.4, 1), [(0, 0.002), (0.008, 0.002), (0.011, -0.005)], ["joint"], seg=8)
        # the ear: a dark can, a red disc in it
        lathe("Ear", (0.104 * sx, 0.04, 1.757), (sx, 0, 0), [(0, 0.03, 1), (0.032, 0.03, 1), (0.037, 0.024, 0), (0.054, 0.024, 0), (0.06, 0.0, 0)],
              ["joint", "red"], seg=14)
        # the cheek's spike
        sweep("Jugal", [(0.096 * sx, -0.02, 1.705), (0.124 * sx, -0.014, 1.676), (0.14 * sx, -0.004, 1.642)], [0.022, 0.014, 0], mat="horn",
              seg=8)
    sweep("NoseHorn", [(0, -0.262, 1.812), (0, -0.28, 1.858), (0, -0.276, 1.906)], [(0.026, 0.022), (0.016, 0.014), 0], mat="horn", seg=8)
    frill()
    grow("head", tilt=HEAD_TILT, lift=0.04, back=0.03)   # (the beak a little down, the frill standing behind; high and back enough
    #                                                      to keep the horns and the jaw clear of its fists in a guard)


# ---------------------------------------------------------------- the cape (the Minoan android's)

CAPE = []           # the cape's parts on its bone (objects): their top band on the chest too (_band_cape)


def cape():
    bone("chest")
    box("CapeClasp", (0.44, 0.05, 0.05), (0, 0.172, 1.575), mat="coat2", bevel=0.014, outline=0)
    for sx in (1.0, -1.0):
        ball("CapeBrooch", (0.2 * sx, 0.19, 1.575), 0.028, "gold", seg=10, outline=0)
    bone("coat.B")
    first = len(kit.PARTS)
    pts = [(-0.23, 0.0), (0.23, 0.0), (0.31, -1.12), (0.1, -1.16), (-0.1, -1.14), (-0.31, -1.12)]
    slab("CapeBackIn", [(x * 0.94, y * 0.98) for (x, y) in pts], (0.0, 0.186, 1.56), (0, 1, 0), thick=0.012, mat="coat2", bevel=0.0)
    slab("CapeBack", pts, (0.0, 0.196, 1.56), (0, 1, 0), thick=0.016, mat="coat", bevel=0.005)
    slab("CapeHem", [(0.305, -1.06), (0.31, -1.12), (0.1, -1.16), (-0.1, -1.14), (-0.31, -1.12), (-0.305, -1.06), (-0.1, -1.085),
                     (0.1, -1.1)], (0.0, 0.196, 1.56), (0, 1, 0), thick=0.016, mat="gold", bevel=0.003, off=(0, 0, 0.003))
    m_trisk(flat((0.0, 0.205, 1.02), (0, 1, 0)), 0.12)
    CAPE[:] = [ob for ob, _b in kit.PARTS[first:]]
    if not getattr(kit.merge_parts, "bands_cape", False):
        merge = kit.merge_parts

        def merge_parts():
            w = _fold_cape()
            made = merge()
            _band_cape(made, w)
            return made
        merge_parts.bands_cape = True
        kit.merge_parts = merge_parts


def cape_weight(p):
    """The chest's share of a point of the cape at rest (its bone's the rest)."""
    return 1.0 - _smooth(CAPE_BAND[0], CAPE_BAND[1], p.z)


def _fold_cape():
    """The cape's parts cut across in its band (so it folds there); each vertex's chest weight, by its place at rest."""
    w = {}
    for ob in CAPE:
        if ob.name not in bpy.data.objects or ob.type != "MESH":
            continue
        mw = ob.matrix_world
        inv = mw.inverted()
        nm = mw.to_3x3().transposed()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        for c in CAPE_CUTS:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=inv @ Vector((0, 0, c)),
                                   plane_no=(nm @ Vector((0, 0, 1))).normalized())
        bm.to_mesh(ob.data)
        bm.free()
        for v in ob.data.vertices:
            p = mw @ v.co
            w[_key(p)] = cape_weight(p)
    return w


def _band_cape(made, w):
    """The merged cape's band: weighted between the chest and the cape's bone."""
    for part in made:
        if part.name != "Coat":
            continue
        gc = part.vertex_groups.get("chest") or part.vertex_groups.new(name="chest")
        gb = part.vertex_groups.get("coat.B")
        mw = part.matrix_world
        hit = 0
        for v in part.data.vertices:
            x = w.get(_key(mw @ v.co))
            if x is None or x < 1e-4:
                continue
            hit += 1
            gc.add([v.index], x, "REPLACE")
            if x > 1.0 - 1e-4:
                gb.remove([v.index])
            else:
                gb.add([v.index], 1.0 - x, "REPLACE")
        print("CAPE: %d of its vertices on the chest too" % hit)


# ---------------------------------------------------------------- the weapons

def rifle():
    """The laser rifle. On the gun bone: its head = the grip, its Y = the muzzle (world -Y at rest), Z = top."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    box("RGrip", (0.036, 0.048, 0.10), at(-0.012, -0.02), mat="rifle_d", r=rot(-14), bevel=0.008, outline=0)
    box("RReceiver", (0.068, 0.36, 0.10), at(0.07, 0.072), mat="rifle", bevel=0.014, outline=0)
    box("RTrim", (0.072, 0.30, 0.018), at(0.07, 0.125), mat="rifle_t", bevel=0.004, outline=0)
    box("RSight", (0.02, 0.07, 0.022), at(0.16, 0.144), mat="rifle_d", bevel=0.004, outline=0)
    box("RStock", (0.05, 0.22, 0.08), at(-0.21, 0.058), mat="rifle", taper=(1.0, 0.8), bevel=0.014, outline=0)
    box("RButt", (0.056, 0.03, 0.11), at(-0.325, 0.05), mat="rifle_d", bevel=0.008, outline=0)
    box("RFore", (0.064, 0.26, 0.08), at(0.36, 0.07), mat="rifle_d", bevel=0.012, outline=0)
    for k in range(3):
        box("RCell", (0.07, 0.04, 0.05), at(0.29 + k * 0.07, 0.07), mat="rifle_g", bevel=0.006, outline=0)
    tube("RBarrel", at(0.48, 0.08), at(0.74, 0.08), 0.026, mat="rifle", seg=12, outline=0)
    for k in range(2):
        tube("RRing", at(0.55 + k * 0.08, 0.08), at(0.57 + k * 0.08, 0.08), 0.032, mat="rifle_t", seg=12, outline=0)
    tube("RMuzzle", at(0.72, 0.08), at(0.80, 0.08), 0.036, mat="rifle_d", seg=12, outline=0)
    tube("RMuzzleGlow", at(0.795, 0.08), at(0.806, 0.08), 0.02, mat="rifle_g", seg=10, outline=0)
    box("RMag", (0.045, 0.08, 0.11), at(0.10, -0.025), mat="rifle_d", r=rot(8), bevel=0.008, outline=0)


def bow():
    """The laser bow: gold limbs curving back from the grip (upright, at the
    left hand), a string of light drawn back to the right hand, an arrow of light."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))
    grip_y = 0.26

    def at(fwd, up, side=0.0):
        return Vector((g.x + side, g.y - fwd, g.z + up))
    box("BGrip", (0.04, 0.05, 0.12), tuple(at(grip_y, 0.0)), mat="bow_q", bevel=0.01, outline=0)
    for s in (1.0, -1.0):
        pts = [at(grip_y, 0.05 * s)]
        for k in range(1, 7):
            t = k / 6
            pts.append(at(grip_y - 0.05 * t * t - 0.02 * math.sin(t * math.pi), (0.05 + 0.5 * t) * s))
        sweep("BLimb", pts, [(0.016 - 0.0016 * k, 0.02 - 0.002 * k) for k in range(7)], mat="bow", seg=8, tip=False)
        ball("BTip", tuple(pts[-1]), 0.02, "bow", seg=8, outline=0)
        tube("BString", tuple(pts[-1]), tuple(at(-0.075, 0.0)), 0.004, mat="bow_g", seg=6, outline=0)
    tube("BArrow", tuple(at(-0.075, 0.0)), tuple(at(grip_y + 0.12, 0.0)), 0.006, mat="bow_g", seg=6, outline=0)
    tube("BArrowHead", tuple(at(grip_y + 0.12, 0.0)), tuple(at(grip_y + 0.18, 0.0)), 0.016, 0.001, mat="bow_g", seg=6, outline=0)
    # the quiver on the back (the bow's material: shown with it)
    bone("chest")
    tube("BQuiver", (-0.1, 0.2, 1.22), (0.12, 0.23, 1.62), 0.05, mat="bow_q", seg=12, outline=0)
    tube("BQuiverRim", (0.11, 0.23, 1.6), (0.125, 0.23, 1.63), 0.056, mat="bow", seg=12, outline=0)
    for k in range(4):
        tube("BQuiverArrow", (0.10 + k * 0.012 - 0.02, 0.23, 1.6), (0.15 + k * 0.012 - 0.02, 0.24, 1.72), 0.007, mat="bow_g", seg=5, outline=0)


def axe():
    """The labrys: a long red haft, the double blade at its end (two crescents,
    gold-rimmed, a red spiral painted on each face), its edges of light."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    tube("AHaft", at(-0.2, 0.0), at(0.82, 0.0), 0.022, mat="axe_h", seg=10, outline=0)
    tube("AButt", at(-0.24, 0.0), at(-0.2, 0.0), 0.03, mat="bow", seg=10, outline=0)
    tube("ACollar", at(0.66, 0.0), at(0.74, 0.0), 0.034, mat="bow", seg=10, outline=0)
    for s in (1.0, -1.0):
        blade = [(0.0, 0.03), (0.06, 0.06), (0.15, 0.2), (0.17, 0.26), (0.08, 0.27), (-0.08, 0.27), (-0.17, 0.26), (-0.15, 0.2), (-0.06, 0.06)]
        pts = [(x, y * s) for (x, y) in blade]
        slab("ABladeRim", [(x * 1.06, y * 1.04) for (x, y) in pts], at(0.70, 0.0), (1, 0, 0), (0, -1, 0), thick=0.012, mat="bow", bevel=0.0)
        slab("ABlade", pts, at(0.70, 0.0), (1, 0, 0), (0, -1, 0), thick=0.02, mat="axe", bevel=0.005)
        tube("AEdge", at(0.53, 0.26 * s), at(0.87, 0.26 * s), 0.008, mat="axe_g", seg=6, outline=0)
        for side in (1.0, -1.0):
            m_spiral(flat(at(0.70, 0.165 * s, 0.01 * side), (side, 0, 0)), 0.055, "axe_r", hand=side, lift=0.003, name="ASpiral", walls=False)


def build():
    materials()
    style()
    mirror(legs)
    body()
    head()
    mirror(arms)
    cape()
    rifle()
    bow()
    axe()
