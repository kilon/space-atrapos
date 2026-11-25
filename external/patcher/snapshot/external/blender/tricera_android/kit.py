"""Modelling kit of the triceratops android (build_model.py): the sheet's measures, cel materials,
and the handful of ways its parts are made.

Measures: every size in build_model.py is written in the model sheet's pixels and turned into metres
here - Q(dx, s, row): dx = pixels right of the front view's centre line (the android's left is +X),
s = the left view's pixel column (the android faces -Y, so a larger s is farther back), row = the
pixel row (the ground is row GY).

Shapes:
  loft      a skin over a stack of rings (ring(): a superellipse, round to boxy); zloft / xloft /
            yloft take the rings as sheet measures along the height, the arm, or the snout
  tube      a ring swept along a smoothed path (belts, rims, cords, fingers; with a taper: horns, claws)
  sheet     a grid from a function of (u, v), thickened behind its face (cloth, the frill, shoulder
            shells); the face looks along du x dv (flip: the other way)
  plate     an armour plate: its outline drawn in one view, laid on the surface under it, thickened
            and bevelled
  ink_line  a thin black line laid on the surface under it (a panel line)
Every part is smooth shaded with sharp creases and carries an inverted-hull ink outline (a Solidify
modifier named "Ink")."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector, geometry
from mathutils.bvhtree import BVHTree

K = 0.00228          # metres per sheet pixel
FX = 1037.0          # the front view's centre line (pixel column)
SX = 262.0           # the left view's column of y = 0
GY = 985.0           # the ground's pixel row
COLL = "TriceraAndroid"
INK_W = 0.0052       # the ink outline's thickness (m)
M = {}               # materials by short name


def Q(dx, s, row):
    return Vector((dx * K, (s - SX) * K, (GY - row) * K))


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------- materials

def lin(c):
    """sRGB (as painted) -> the linear values Blender's colour inputs take."""
    if isinstance(c, str):
        c = tuple(int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# The cel shading needs no lamp and looks the same from the front, the back and both sides: a
# surface's tone comes from how its normal n points - weights (x, y, z) give |n.x|*x + |n.y|*y + n.z*z,
# and below `edge` the surface is in shade. The usual weights put undersides in shade; the cape's
# put the flanks of its folds in shade.
TONE = (0.15, 0.50, 0.85)


def image(name, rgb):
    """A Blender image from an (h, w, 3) float array of sRGB values (top row first)."""
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), np.float32)
    px[:, :, :3] = rgb[::-1]
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def mat_toon(name, color, shade, img=None, hi=None, tone=TONE, edge=0.0):
    """Cel shading: two flat tones (the colour, and `shade`: the colour it has in shadow), and with
    `hi` a third (the bright streak on metal, where a surface faces up). The colour is flat or a
    painted image (then `color` is the image's main colour). tone, edge: see TONE."""
    base = lin(color)

    def ratio(c):
        return tuple(min(x / max(b, 1e-4), 4.0) for x, b in zip(lin(c), base))
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    geo = N("ShaderNodeNewGeometry")
    sep = N("ShaderNodeSeparateXYZ")
    L(geo.outputs["Normal"], sep.inputs[0])
    comb = N("ShaderNodeCombineXYZ")
    for i in (0, 1):
        ab = N("ShaderNodeMath")
        ab.operation = "ABSOLUTE"
        L(sep.outputs[i], ab.inputs[0])
        L(ab.outputs[0], comb.inputs[i])
    L(sep.outputs[2], comb.inputs[2])
    dot = N("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = tone
    L(comb.outputs[0], dot.inputs[0])
    ramp = N("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (*ratio(shade), 1)
    els[1].position, els[1].color = 0.5 + edge / 4, (1, 1, 1, 1)
    if hi:
        e = els.new(0.5 + 0.80 / 4)
        e.color = (*ratio(hi), 1)
    remap = N("ShaderNodeMapRange")                       # -2..2 -> 0..1
    remap.inputs[1].default_value, remap.inputs[2].default_value = -2.0, 2.0
    L(dot.outputs["Value"], remap.inputs[0])
    L(remap.outputs[0], ramp.inputs["Fac"])
    if img is not None:
        tx = N("ShaderNodeTexImage")
        tx.image = img
        col = tx.outputs["Color"]
    else:
        rgb = N("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*base, 1)
        col = rgb.outputs[0]
    mul = N("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    L(col, mul.inputs[6])
    L(ramp.outputs["Color"], mul.inputs[7])
    em = N("ShaderNodeEmission")
    L(mul.outputs[2], em.inputs["Color"])
    L(em.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*base, 1)
    return m


def mat_flat(name, color, strength=1.0, cull=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*lin(color), 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = cull
    m.diffuse_color = (*lin(color), 1)
    return m


# ---------------------------------------------------------------- objects

def coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def _bake(ob):
    """Applies the object's modifiers."""
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    name = old.name
    bpy.data.meshes.remove(old)
    me.name = name


def _twin_name(name):
    for a, b in ((".R", ".L"), (".L", ".R")):
        if a in name:
            return name.replace(a, b)
    return name + ".L"


def obj(name, verts, faces, mat="cream", sharp=40.0, ink=1.0, uv=None, recalc=True, sub=0, bevel=0.0,
        solid=0.0, solid_offset=1.0, back=None, mirror=False, flat=False):
    """A mesh object in the collection. sub: subdivision levels; solid: a thickness for open sheets
    (back: the material of the far side); bevel: a bevel on sharp edges; ink: the outline's weight
    (0 = none); mirror: also its twin across the centre line (".R" <-> ".L")."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    if uv is not None:
        layer = me.uv_layers.new(name="UV")
        vi = np.empty(len(me.loops), np.int32)
        me.loops.foreach_get("vertex_index", vi)
        layer.data.foreach_set("uv", np.asarray(uv, np.float32)[vi].ravel())
    if recalc:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    mats = [mat] + ([back] if back else [])
    for k in mats:
        me.materials.append(M[k])
    if sub or solid or bevel:
        if sub:
            s = ob.modifiers.new("Sub", "SUBSURF")
            s.levels = s.render_levels = sub
        if solid:
            s = ob.modifiers.new("Solid", "SOLIDIFY")
            s.thickness, s.offset, s.use_rim = solid, solid_offset, True
            if back:
                s.material_offset = 1
        if bevel:
            b = ob.modifiers.new("Bevel", "BEVEL")
            b.width, b.segments, b.limit_method, b.angle_limit = bevel, 2, "ANGLE", math.radians(35)
        _bake(ob)
        me = ob.data
        if solid:
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(me)
            bm.free()
    me.polygons.foreach_set("use_smooth", np.full(len(me.polygons), not flat, bool))
    if not flat:
        me.set_sharp_from_angle(angle=math.radians(sharp))
    me.update()
    if ink > 0:
        me.materials.append(M["ink"])
        s = ob.modifiers.new("Ink", "SOLIDIFY")
        s.thickness, s.offset, s.use_flip_normals, s.use_rim = -INK_W * ink, -1.0, True, False
        s.material_offset = len(me.materials) - 1
    if mirror:
        me2 = me.copy()
        me2.name = _twin_name(name)
        co = np.empty(len(me2.vertices) * 3, np.float32)
        me2.vertices.foreach_get("co", co)
        co[0::3] *= -1.0
        me2.vertices.foreach_set("co", co)
        me2.flip_normals()
        me2.update()
        ob2 = bpy.data.objects.new(me2.name, me2)
        coll().objects.link(ob2)
        for md in ob.modifiers:
            s = ob2.modifiers.new(md.name, md.type)
            s.thickness, s.offset, s.use_flip_normals, s.use_rim = md.thickness, md.offset, md.use_flip_normals, md.use_rim
            s.material_offset = md.material_offset
    return ob


# ---------------------------------------------------------------- rings, lofts

def ring(c, u, v, ru, rv, n=2.4, m=28, rv_neg=None, ru_neg=None, pinch=0.0):
    """A superellipse of m points around c in the plane of the unit vectors u, v (n = 2 an ellipse,
    larger = boxier). rv_neg / ru_neg: other radii on the negative side; pinch: narrows the
    negative-v side toward a keel (0 = none)."""
    e = 2.0 / n
    pts = []
    for k in range(m):
        a = 2 * math.pi * k / m
        ca, sa = math.cos(a), math.sin(a)
        pu = math.copysign(abs(ca) ** e, ca) * (ru if ca >= 0 or ru_neg is None else ru_neg)
        pv = math.copysign(abs(sa) ** e, sa) * (rv if sa >= 0 or rv_neg is None else rv_neg)
        if pinch and sa < 0:
            pu *= 1 - pinch * abs(sa) ** 1.5
        pts.append(c + u * pu + v * pv)
    return pts


def loft(name, rings, mat="cream", caps=("fan", "fan"), loop=False, **kw):
    """Skins the rings (lists of the same number of points). caps: "fan" or None for each end;
    loop: the last ring joins the first."""
    n = len(rings[0])
    verts = [p for r in rings for p in r]
    faces = []
    R = len(rings)
    for i in range(R if loop else R - 1):
        a0, b0 = i * n, ((i + 1) % R) * n
        for j in range(n):
            k = (j + 1) % n
            faces.append((a0 + j, a0 + k, b0 + k, b0 + j))
    if not loop:
        for end, base in ((0, 0), (1, (R - 1) * n)):
            if caps[end] == "fan":
                c = sum(rings[-1 if end else 0], Vector()) / n
                verts.append(c)
                ci = len(verts) - 1
                for j in range(n):
                    faces.append((base + j, base + (j + 1) % n, ci))
    return obj(name, verts, faces, mat, **kw)


X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def zloft(name, st, mat="cream", n=2.6, m=28, **kw):
    """Rings stacked along the height. st: (row, dx0, dx1, s0, s1[, n]) - the part's left and right
    edges in the front view (pixels from the centre line) and its front and back in the left view."""
    return loft(name, zrings(st, n, m), mat, **kw)


def zrings(st, n=2.6, m=28):
    rings = []
    for s in st:
        row, x0, x1, s0, s1 = s[:5]
        nn = s[5] if len(s) > 5 else n
        rings.append(ring(Q((x0 + x1) / 2, (s0 + s1) / 2, row), X, Y, abs(x1 - x0) / 2 * K, abs(s1 - s0) / 2 * K, nn, m))
    return rings


def xloft(name, st, mat="cream", n=2.4, m=24, **kw):
    """Rings stacked along the arm. st: (dx, row_top, row_bottom, s0, s1[, n])."""
    rings = []
    for s in st:
        dx, r0, r1, s0, s1 = s[:5]
        nn = s[5] if len(s) > 5 else n
        rings.append(ring(Q(dx, (s0 + s1) / 2, (r0 + r1) / 2), Y, Z, abs(s1 - s0) / 2 * K, abs(r1 - r0) / 2 * K, nn, m))
    return loft(name, rings, mat, **kw)


def yloft(name, st, mat="cream", n=2.6, m=28, **kw):
    """Rings stacked front to back. st: (s, row_top, row_bottom, half width[, pinch]) - pinch
    narrows the ring's underside toward a keel."""
    rings = []
    for s in st:
        sp, r0, r1, hw = s[:4]
        rings.append(ring(Q(0.0, sp, (r0 + r1) / 2), X, Z, hw * K, abs(r1 - r0) / 2 * K, n, m, pinch=s[4] if len(s) > 4 else 0.0))
    return loft(name, rings, mat, **kw)


# ---------------------------------------------------------------- paths, tubes

def smooth(pts, sub=6, closed=False):
    """Catmull-Rom through the points (2D or 3D vectors), sub pieces per span."""
    Pn = [p.copy() for p in pts]
    n = len(Pn)
    if n < 3 or sub <= 1:
        return Pn
    out = []
    for i in range(n if closed else n - 1):
        p1, p2 = Pn[i], Pn[(i + 1) % n]
        p0 = Pn[(i - 1) % n] if (closed or i > 0) else p1 + (p1 - p2)
        p3 = Pn[(i + 2) % n] if (closed or i + 2 < n) else p2 + (p2 - p1)
        for k in range(sub):
            t = k / sub
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3))
    if not closed:
        out.append(Pn[-1])
    return out


def bezier(p0, pc, p1, steps=12):
    return [p0 * (1 - t) ** 2 + pc * (2 * t * (1 - t)) + p1 * t * t for t in (i / steps for i in range(steps + 1))]


def _val(r, t, i):
    if callable(r):
        return r(t)
    if isinstance(r, (list, tuple)):
        return r[i]
    return r


def tube(name, pts, ru, rv=None, mat="gold", m=10, n=2.0, sub=0, closed=False, up=None, caps=("fan", "fan"), **kw):
    """A ring swept along the path. ru / rv: the section's radii (numbers, one per point, or
    functions of 0..1 along the path); up: the direction the section's v axis keeps to (a vector or
    a function of the point), else the section just avoids twisting."""
    Pn = smooth([Vector(p) for p in pts], sub, closed) if sub else [Vector(p) for p in pts]
    rv = ru if rv is None else rv
    rings = []
    prev = None
    L = len(Pn)
    for i, p in enumerate(Pn):
        a = Pn[i - 1] if (i > 0 or closed) else Pn[0]
        b = Pn[(i + 1) % L] if (i < L - 1 or closed) else Pn[-1]
        t = (b - a).normalized()
        if isinstance(up, list):
            w = up[i]
        elif up is not None:
            w = Vector(up(p)) if callable(up) else Vector(up)
        elif prev is not None:
            w = prev
        else:
            w = Z if abs(t.z) < 0.9 else X
        v = w - t * w.dot(t)
        v = v.normalized() if v.length > 1e-6 else (prev or X)
        prev = v
        u = t.cross(v)
        f = i / max(L - 1, 1)
        rings.append(ring(p, u, v, _val(ru, f, i), _val(rv, f, i), n, m))
    return loft(name, rings, mat, caps=caps, loop=closed, **kw)


def horn(name, p0, p1, bend, r0, r1=None, mat="horn", steps=14, m=14, power=0.8, up=None, **kw):
    """A curved, pointed cone from p0 to p1; bend: how far its middle is pushed aside (a vector);
    r0 / r1: the base's radii across and along `up`."""
    r1 = r0 if r1 is None else r1
    pts = bezier(p0, (p0 + p1) / 2 + bend, p1, steps)

    def tp(t):
        return max(1 - t, 0.0) ** power * 0.96 + 0.04
    return tube(name, pts, lambda t: r0 * tp(t), lambda t: r1 * tp(t), mat, m=m, up=up, **kw)


def ball(name, c, rx, ry=None, rz=None, mat="navy", m=20, rows=10, **kw):
    ry = rx if ry is None else ry
    rz = rx if rz is None else rz
    rings = []
    for i in range(1, rows):
        a = math.pi * i / rows
        rings.append(ring(c + Z * (rz * math.cos(a)), X, Y, rx * math.sin(a), ry * math.sin(a), 2.0, m))
    verts = [p for r in rings for p in r] + [c + Z * rz, c - Z * rz]
    faces = []
    for i in range(len(rings) - 1):
        for j in range(m):
            k = (j + 1) % m
            faces.append((i * m + j, i * m + k, (i + 1) * m + k, (i + 1) * m + j))
    top, bot = len(verts) - 2, len(verts) - 1
    for j in range(m):
        faces.append((j, (j + 1) % m, top))
        faces.append(((len(rings) - 1) * m + j, (len(rings) - 1) * m + (j + 1) % m, bot))
    return obj(name, verts, faces, mat, **kw)


def sheet(name, fn, nu, nv, mat="cream", thick=0.006, uvfn=None, loop_u=False, flip=False, **kw):
    """A grid of fn(u, v) (u, v in 0..1), given a thickness. uvfn(u, v) -> its texture coordinates."""
    verts, uvs, faces = [], [], []
    cu = nu if loop_u else nu + 1
    for j in range(nv + 1):
        for i in range(cu):
            u, v = i / nu, j / nv
            verts.append(Vector(fn(u, v)))
            uvs.append(uvfn(u, v) if uvfn else (u, 1.0 - v))
    for j in range(nv):
        for i in range(nu):
            a, b = j * cu + i, j * cu + (i + 1) % cu
            faces.append((a, a + cu, b + cu, b) if flip else (a, b, b + cu, a + cu))
    kw.setdefault("solid_offset", -1.0)
    return obj(name, verts, faces, mat, uv=uvs, recalc=False, solid=thick, **kw)


# ---------------------------------------------------------------- laying things on surfaces

class Caster:
    """Drops points onto the surfaces of some objects along a view: "F" from the front (the front
    view's pixels: dx, row), "S" from the android's left (the left view's pixels: s, row),
    "B" from behind (dx, row)."""

    def __init__(self, names=(), rings=None):
        """names: the objects to lay things on; rings: or a guide shape that is not part of the
        model (a stack of rings, as for loft())."""
        self.trees = []
        for nme in names:
            me = bpy.data.objects[nme].data
            self.trees.append(BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons]))
        if rings:
            n = len(rings[0])
            faces = [(i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j)
                     for i in range(len(rings) - 1) for j in range(n)]
            self.trees.append(BVHTree.FromPolygons([p for r in rings for p in r], faces))

    @staticmethod
    def ray(view, a, row):
        z = (GY - row) * K
        if view == "F":
            return Vector((a * K, -10.0, z)), Vector((0, 1, 0))
        if view == "B":
            return Vector((a * K, 10.0, z)), Vector((0, -1, 0))
        if view == "R":                                   # from the android's right (the left view mirrored)
            return Vector((-10.0, (a - SX) * K, z)), Vector((1, 0, 0))
        return Vector((10.0, (a - SX) * K, z)), Vector((-1, 0, 0))

    def depths(self, view, pts2, maxdev=0.10):
        """For each 2D point: the ray's origin, and how far along the view direction the surface is
        (those that miss, or land far from the rest, take the depth of the nearest good one)."""
        hits, d, origins = [], None, []
        for a, row in pts2:
            o, d = self.ray(view, a, row)
            origins.append(o)
            best = None
            for t in self.trees:
                loc, nor, idx, dist = t.ray_cast(o, d)
                if loc is not None and (best is None or dist < best):
                    best = dist
            hits.append(best)
        good = [h for h in hits if h is not None]
        if not good:
            raise RuntimeError("nothing under the outline")
        med = sorted(good)[len(good) // 2]
        ok = [h is not None and abs(h - med) < maxdev for h in hits]
        idx_ok = [i for i, g in enumerate(ok) if g]
        out = []
        for i, (a, row) in enumerate(pts2):
            if ok[i]:
                out.append(hits[i])
            else:
                j = min(idx_ok, key=lambda q: (pts2[q][0] - a) ** 2 + (pts2[q][1] - row) ** 2)
                out.append(hits[j])
        return origins, d, out

    def drop(self, view, pts2, maxdev=0.10):
        """The 3D points under the 2D ones, and the view direction."""
        origins, d, h = self.depths(view, pts2, maxdev)
        return [o + d * x for o, x in zip(origins, h)], d


def _resample_closed(poly, step):
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        k = max(1, int(round((b - a).length / step)))
        out += [a.lerp(b, j / k) for j in range(k)]
    return out


def _inside(p, poly):
    x, y, c = p[0], p[1], False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            c = not c
    return c


def chaikin(poly, it=2, closed=True):
    P = [Vector(p) for p in poly]
    for _ in range(it):
        out = []
        n = len(P)
        for i in range(n if closed else n - 1):
            a, b = P[i], P[(i + 1) % n]
            out += [a.lerp(b, 0.25), a.lerp(b, 0.75)]
        if not closed:
            out = [P[0]] + out + [P[-1]]
        P = out
    return P


def plate(name, poly, view, cast, mat="cream", thick=0.010, lift=0.0, grid=5.0, rnd=0, bevel=0.0025, maxdev=0.10, wrap=0.035,
          relax=3, **kw):
    """An armour plate: the outline `poly` (pixels of the view) laid on the surfaces of `cast`,
    `thick` m thick, raised by `lift`. rnd: rounds the outline's corners; wrap: how deep the plate
    follows the surface round to the side at most; relax: evens the plate out (0 = hugs the surface)."""
    P = chaikin(poly, rnd) if rnd else [Vector(p) for p in poly]
    edge = _resample_closed(P, grid)
    xs = [p[0] for p in P]
    ys = [p[1] for p in P]
    inner = []
    y = min(ys) + grid * 0.5
    row_i = 0
    while y < max(ys):
        x = min(xs) + grid * (0.5 if row_i % 2 else 0.25)
        while x < max(xs):
            q = Vector((x, y))
            if _inside(q, P) and min((q - e).length for e in edge) > grid * 0.55:
                inner.append(q)
            x += grid
        y += grid * 0.87
        row_i += 1
    pts2 = edge + inner
    res = geometry.delaunay_2d_cdt(pts2, [(i, (i + 1) % len(edge)) for i in range(len(edge))], [], 0, 1e-5)
    v2, tris = res[0], res[2]
    origins, d, h = cast.depths(view, [(p[0], p[1]) for p in v2], maxdev)
    near = min(h)
    h = [min(x, near + wrap) for x in h]
    nb = [set() for _ in v2]
    for t in tris:
        for i in t:
            nb[i].update(j for j in t if j != i)
    for _ in range(relax):
        h = [0.5 * x + 0.5 * sum(h[j] for j in nb[i]) / len(nb[i]) if nb[i] else x for i, x in enumerate(h)]
    pts3 = [o + d * x for o, x in zip(origins, h)]
    faces = []
    for t in tris:
        if len(t) != 3:
            continue
        c = (v2[t[0]] + v2[t[1]] + v2[t[2]]) / 3
        if not _inside(c, P):
            continue
        a, b, cc = pts3[t[0]], pts3[t[1]], pts3[t[2]]
        if (b - a).cross(cc - a).dot(d) > 0:      # (facing away from the viewer: turn it)
            t = (t[0], t[2], t[1])
        faces.append(tuple(t))
    verts = [p - d * lift for p in pts3]
    return obj(name, verts, faces, mat, recalc=False, solid=thick, bevel=bevel, **kw)


def ink_line(name, pts, view, cast, r=0.0026, sub=4, step=3.0, mirror=False, maxdev=0.10):
    """A panel line: the polyline `pts` (pixels of the view) laid on the surfaces of `cast`."""
    P = [Vector(p) for p in pts]
    if sub and len(P) > 2:
        P = smooth(P, sub)
    dense = []
    for a, b in zip(P, P[1:]):
        k = max(1, int((b - a).length / step))
        dense += [a.lerp(b, j / k) for j in range(k)]
    dense.append(P[-1])
    pts3, d = cast.drop(view, [(p[0], p[1]) for p in dense], maxdev)
    return tube(name, [p - d * (r * 0.25) for p in pts3], r, mat="ink", m=5, ink=0, mirror=mirror)


# ---------------------------------------------------------------- painting textures

class Canvas:
    """A picture drawn with soft-edged strokes (for the painted patterns)."""

    def __init__(self, w, h, color):
        self.a = np.empty((h, w, 3), np.float32)
        self.a[:] = color
        self.w, self.h = w, h

    def mask_stroke(self, pts, width):
        m = np.zeros((self.h, self.w), np.float32)
        r = width / 2
        P = [np.array(p, np.float64) for p in pts]
        for a, b in zip(P, P[1:]):
            x0, x1 = int(min(a[0], b[0]) - r - 2), int(max(a[0], b[0]) + r + 3)
            y0, y1 = int(min(a[1], b[1]) - r - 2), int(max(a[1], b[1]) + r + 3)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, self.w), min(y1, self.h)
            if x1 <= x0 or y1 <= y0:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1]
            ab = b - a
            L2 = float(ab @ ab) or 1e-9
            t = np.clip(((xx - a[0]) * ab[0] + (yy - a[1]) * ab[1]) / L2, 0, 1)
            dist = np.hypot(xx - (a[0] + t * ab[0]), yy - (a[1] + t * ab[1]))
            m[y0:y1, x0:x1] = np.maximum(m[y0:y1, x0:x1], np.clip(r - dist + 0.5, 0, 1))
        return m

    def paint(self, mask, color):
        self.a = self.a * (1 - mask[..., None]) + np.array(color, np.float32) * mask[..., None]

    def stroke(self, pts, width, color):
        self.paint(self.mask_stroke(pts, width), color)

    def rect(self, x0, y0, x1, y1, color):
        self.a[max(int(y0), 0):int(y1), max(int(x0), 0):int(x1)] = color


def spiral(cx, cy, r0, r1, a0, turns, n=90):
    """Points of a spiral growing from radius r0 to r1 over `turns` turns, starting at angle a0
    (radians, picture coordinates: y down); negative turns wind the other way."""
    return [(cx + lerp(r0, r1, i / n) * math.cos(a0 + 2 * math.pi * turns * i / n),
             cy + lerp(r0, r1, i / n) * math.sin(a0 + 2 * math.pi * turns * i / n)) for i in range(n + 1)]


def interp(vals):
    """A function of 0..1 running through the values (evenly spaced, straight between them)."""
    def f(t):
        x = min(max(t, 0.0), 1.0) * (len(vals) - 1)
        i = min(int(x), len(vals) - 2)
        return lerp(vals[i], vals[i + 1], x - i)
    return f
