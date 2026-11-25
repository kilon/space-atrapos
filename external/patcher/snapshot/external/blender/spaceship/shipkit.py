"""Modelling kit of the spaceship (build_ship.py): materials and the ways its parts are made.

The ship's frame: x forward (the nose), y to port, z up, metres; the origin is midway between the
two lift fans, level with their rims. Everything is built in place (objects keep an identity
transform), parts on the port side with mirror=True get a starboard twin (".P" -> ".S").

Shapes: mesh() any verts / faces; box(); prism() a flat outline pushed out along an axis; lathe() a
profile turned round an axis; skin() a stack of same-sized rings; plates() armour plates laid over the
facets of a skin, with gaps; greebles() small machinery scattered on a patch; decal() a painted mark.
Materials (Cycles): painted armour with panel lines, chips and scratches made in the shader from the
point's place in space (no UVs needed), dark machinery, gold, glass, glowing lamps, engine flame."""
import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector

COLL = "Spaceship"
M = {}


def coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def lin(c):
    if isinstance(c, str):
        c = tuple(int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# ---------------------------------------------------------------- materials

def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return m, nt, out


def _mix(nt, a, b, fac, kind="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = kind
    for sock, v in ((n.inputs[6], a), (n.inputs[7], b), (n.inputs[0], fac)):
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = (*v, 1)
        else:
            nt.links.new(v, sock)
    return n.outputs[2]


def _math(nt, op, a, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for sock, v in ((n.inputs[0], a), (n.inputs[1], b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            sock.default_value = v
        else:
            nt.links.new(v, sock)
    return n.outputs[0]


def _noise(nt, vec, scale, detail=4.0, rough=0.6, stretch=None):
    if stretch:
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        nt.links.new(vec, mp.inputs["Vector"])
        vec = mp.outputs[0]
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    nt.links.new(vec, n.inputs["Vector"])
    return n.outputs["Fac"]


def _step(nt, v, lo, hi):
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP"
    n.inputs[1].default_value, n.inputs[2].default_value = lo, hi
    nt.links.new(v, n.inputs[0])
    return n.outputs[0]


def mat_armour(name, color, panel=(0.7, 1.1, 1.3), dark="#1b1a1c", metal=0.0, rough=0.42, chips=1.0, lines=1.0, tint=0.14, seam_w=0.022):
    """Painted armour: rectangular panels (`panel` of them per metre along x, y, z, each row
    staggered) of slightly different shades with dark seams between them, chipped and scratched
    paint, grime - all from the point's place in the ship's frame."""
    m, nt, out = _mat(name)
    N, L = nt.nodes.new, nt.links.new
    tc = N("ShaderNodeTexCoord")
    co = tc.outputs["Object"]
    sep = N("ShaderNodeSeparateXYZ")
    L(co, sep.inputs[0])
    geo = N("ShaderNodeNewGeometry")
    sn = N("ShaderNodeSeparateXYZ")
    L(geo.outputs["Normal"], sn.inputs[0])
    c = [_math(nt, "MULTIPLY", sep.outputs[i], panel[i]) for i in range(3)]
    fl = [_math(nt, "FLOOR", c[i]) for i in range(3)]
    seam, ids = None, []
    for a in range(3):
        b1, b2 = [i for i in range(3) if i != a]
        cb = N("ShaderNodeCombineXYZ")
        L(fl[b1], cb.inputs[0])
        L(fl[b2], cb.inputs[1])
        cb.inputs[2].default_value = 7.3 * (a + 1)
        wn = N("ShaderNodeTexWhiteNoise")
        wn.noise_dimensions = "3D"
        L(cb.outputs[0], wn.inputs["Vector"])
        pa = _math(nt, "ADD", c[a], wn.outputs["Value"])              # each row of panels starts somewhere else
        d = _math(nt, "ABSOLUTE", _math(nt, "SUBTRACT", _math(nt, "FRACT", pa), 0.5))
        w = seam_w * panel[a]
        line = _step(nt, d, 0.5 - w, 0.5 - w * 0.35)
        flat = _math(nt, "SUBTRACT", 1.0, _step(nt, _math(nt, "ABSOLUTE", sn.outputs[a]), 0.75, 0.92))   # (no seams lying in the face)
        line = _math(nt, "MULTIPLY", line, flat)
        seam = line if seam is None else _math(nt, "MAXIMUM", seam, line)
        ids.append(_math(nt, "FLOOR", pa))
    seam = _math(nt, "MULTIPLY", seam, lines)
    cid = N("ShaderNodeCombineXYZ")
    for i in range(3):
        L(ids[i], cid.inputs[i])
    rnd = N("ShaderNodeTexWhiteNoise")
    rnd.noise_dimensions = "3D"
    L(cid.outputs[0], rnd.inputs["Vector"])
    base = lin(color)
    shade = _mix(nt, tuple(c * (1 - tint) for c in base), tuple(min(c * (1 + tint * 0.5), 1.0) for c in base), rnd.outputs["Value"])
    grime = _step(nt, _noise(nt, co, 0.45, 5.0, 0.65), 0.35, 0.75)
    shade = _mix(nt, shade, tuple(c * 0.5 for c in base), _math(nt, "MULTIPLY", grime, 0.55))
    chip = _step(nt, _noise(nt, co, 5.0, 7.0, 0.78), 0.60, 0.63)                                         # flakes of paint gone
    scratch = _step(nt, _noise(nt, co, 2.2, 6.0, 0.8, stretch=(0.2, 4.0, 4.0)), 0.63, 0.66)
    worn = _math(nt, "MULTIPLY", _math(nt, "MAXIMUM", chip, scratch), chips)
    shade = _mix(nt, shade, lin(dark), worn)
    shade = _mix(nt, shade, lin("#08080a"), seam)
    bs = N("ShaderNodeBsdfPrincipled")
    L(shade, bs.inputs["Base Color"])
    bs.inputs["Metallic"].default_value = metal
    L(_math(nt, "ADD", rough - 0.08, _math(nt, "MULTIPLY", grime, 0.22)), bs.inputs["Roughness"])
    bump = N("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.04
    L(_math(nt, "SUBTRACT", 1.0, _math(nt, "MAXIMUM", seam, _math(nt, "MULTIPLY", worn, 0.4))), bump.inputs["Height"])
    L(bump.outputs[0], bs.inputs["Normal"])
    L(bs.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*base, 1)
    return m


def mat_metal(name, color, rough=0.25, metal=1.0):
    m, nt, out = _mat(name)
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = (*lin(color), 1)
    bs.inputs["Metallic"].default_value = metal
    tc = nt.nodes.new("ShaderNodeTexCoord")
    r = _math(nt, "ADD", rough, _math(nt, "MULTIPLY", _noise(nt, tc.outputs["Object"], 2.5, 4.0, 0.6), 0.18))
    nt.links.new(r, bs.inputs["Roughness"])
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*lin(color), 1)
    return m


def mat_glow(name, color, strength):
    m, nt, out = _mat(name)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*lin(color), 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*lin(color), 1)
    return m


def mat_glass(name):
    m, nt, out = _mat(name)
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = (0.012, 0.016, 0.03, 1)
    bs.inputs["Roughness"].default_value = 0.04
    bs.inputs["Transmission Weight"].default_value = 0.85
    bs.inputs["IOR"].default_value = 1.2
    bs.inputs["Coat Weight"].default_value = 1.0
    bs.inputs["Coat Roughness"].default_value = 0.02
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (0.02, 0.03, 0.06, 1)
    return m


def mat_flame(name, x_hot, x_end):
    """Engine flame: bright blue-white at x_hot fading to nothing at x_end, soft at its edge."""
    m, nt, out = _mat(name)
    N, L = nt.nodes.new, nt.links.new
    tc = N("ShaderNodeTexCoord")
    sep = N("ShaderNodeSeparateXYZ")
    L(tc.outputs["Object"], sep.inputs[0])
    t = N("ShaderNodeMapRange")
    t.inputs[1].default_value, t.inputs[2].default_value = x_hot, x_end
    L(sep.outputs[0], t.inputs[0])
    fade = _math(nt, "POWER", _math(nt, "SUBTRACT", 1.0, t.outputs[0]), 1.6)
    lw = N("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.35
    soft = _math(nt, "SUBTRACT", 1.0, lw.outputs["Facing"])
    a = _math(nt, "MULTIPLY", fade, _math(nt, "POWER", soft, 1.5), clamp=True)
    col = _mix(nt, lin("#0a3cff"), lin("#7fd0ff"), _math(nt, "POWER", fade, 3.0))
    em = N("ShaderNodeEmission")
    L(col, em.inputs["Color"])
    em.inputs["Strength"].default_value = 7.0
    tr = N("ShaderNodeBsdfTransparent")
    mix = N("ShaderNodeMixShader")
    L(a, mix.inputs[0])
    L(tr.outputs[0], mix.inputs[1])
    L(em.outputs[0], mix.inputs[2])
    L(mix.outputs[0], out.inputs["Surface"])
    return m


def mat_decal(name, image, color):
    """Paint laid over the armour: `color` where the picture is white, nothing elsewhere, chipped."""
    m, nt, out = _mat(name)
    N, L = nt.nodes.new, nt.links.new
    tx = N("ShaderNodeTexImage")
    tx.image = image
    tx.extension = "CLIP"
    tc = N("ShaderNodeTexCoord")
    co = tc.outputs["Object"]
    chip = _step(nt, _noise(nt, co, 5.0, 7.0, 0.78), 0.60, 0.63)
    scratch = _step(nt, _noise(nt, co, 2.2, 6.0, 0.8, stretch=(0.2, 4.0, 4.0)), 0.63, 0.66)
    a = _math(nt, "MULTIPLY", tx.outputs["Color"], _math(nt, "SUBTRACT", 1.0, _math(nt, "MAXIMUM", chip, scratch)), clamp=True)
    bs = N("ShaderNodeBsdfPrincipled")
    base = lin(color)
    shade = _mix(nt, base, tuple(c * 0.6 for c in base), _step(nt, _noise(nt, co, 0.35, 5.0, 0.65), 0.35, 0.75))
    L(shade, bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.42
    L(a, bs.inputs["Alpha"])
    L(bs.outputs[0], out.inputs["Surface"])
    return m


def image(name, a):
    """A Blender image from an (h, w) or (h, w, 3) float array (top row first)."""
    if a.ndim == 2:
        a = np.repeat(a[..., None], 3, axis=2)
    h, w = a.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False, is_data=True)       # (a mask: no colour management)
    px = np.ones((h, w, 4), np.float32)
    px[:, :, :3] = a[::-1]
    img.pixels.foreach_set(px.ravel())
    img.update()
    img.pack()
    return img


def stroke_mask(w, h, pts, width, m=None):
    """A soft-edged stroke along the points (picture pixels), added to the mask m."""
    m = np.zeros((h, w), np.float32) if m is None else m
    r = width / 2
    P = [np.array(p, np.float64) for p in pts]
    for a, b in zip(P, P[1:]):
        x0, x1 = max(int(min(a[0], b[0]) - r - 2), 0), min(int(max(a[0], b[0]) + r + 3), w)
        y0, y1 = max(int(min(a[1], b[1]) - r - 2), 0), min(int(max(a[1], b[1]) + r + 3), h)
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        ab = b - a
        t = np.clip(((xx - a[0]) * ab[0] + (yy - a[1]) * ab[1]) / (float(ab @ ab) or 1e-9), 0, 1)
        d = np.hypot(xx - (a[0] + t * ab[0]), yy - (a[1] + t * ab[1]))
        m[y0:y1, x0:x1] = np.maximum(m[y0:y1, x0:x1], np.clip(r - d + 0.5, 0, 1))
    return m


def spiral(cx, cy, r0, r1, a0, turns, n=80):
    return [(cx + (r0 + (r1 - r0) * i / n) * math.cos(a0 + 2 * math.pi * turns * i / n),
             cy + (r0 + (r1 - r0) * i / n) * math.sin(a0 + 2 * math.pi * turns * i / n)) for i in range(n + 1)]


# ---------------------------------------------------------------- meshes

def _twin(name):
    return name.replace(".P", ".S") if ".P" in name else name + ".S"


def mesh(name, verts, faces, mat="white", bevel=0.0, smooth=False, mirror=False, uv=None, mats=None, fmat=None, weld=False, recalc=True):
    """A mesh object. bevel: rounds its sharp edges (m); mats: more materials, fmat: each face's
    material number; uv: one coordinate per face corner, in order."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    if uv is not None:
        me.uv_layers.new(name="UV").data.foreach_set("uv", np.asarray(uv, np.float32).ravel())
    bm = bmesh.new()
    bm.from_mesh(me)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for k in [mat] + list(mats or []):
        me.materials.append(M[k])
    if fmat is not None:
        me.polygons.foreach_set("material_index", np.asarray(fmat, np.int32))
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    if bevel > 0:
        b = ob.modifiers.new("Bevel", "BEVEL")
        b.width, b.segments, b.limit_method, b.angle_limit = bevel, 2, "ANGLE", math.radians(30)
        b.harden_normals = True
    me.polygons.foreach_set("use_smooth", np.full(len(me.polygons), True, bool))
    me.set_sharp_from_angle(angle=math.radians(40 if smooth else 16))
    if mirror:
        mirror_obj(ob)
    return ob


def mirror_obj(ob):
    """The starboard twin of a port part."""
    me2 = ob.data.copy()
    me2.name = _twin(ob.name)
    co = np.empty(len(me2.vertices) * 3, np.float32)
    me2.vertices.foreach_get("co", co)
    co[1::3] *= -1.0
    me2.vertices.foreach_set("co", co)
    me2.flip_normals()
    ob2 = bpy.data.objects.new(me2.name, me2)
    coll().objects.link(ob2)
    for md in ob.modifiers:
        b = ob2.modifiers.new(md.name, md.type)
        b.width, b.segments, b.limit_method, b.angle_limit, b.harden_normals = md.width, md.segments, md.limit_method, md.angle_limit, True
    return ob2


def cut_hole(ob, center, radius, z0, z1, seg=64):
    """Cuts a round hole (a vertical cylinder) through the object."""
    c = cyl("_cutter", (center[0], center[1], z0), (center[0], center[1], z1), radius, seg=seg)
    mods = [(m.width, m.segments, m.limit_method, m.angle_limit) for m in ob.modifiers]
    ob.modifiers.clear()
    b = ob.modifiers.new("Cut", "BOOLEAN")
    b.operation, b.object, b.solver = "DIFFERENCE", c, "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    me.name = old.name
    bpy.data.meshes.remove(old)
    bpy.data.objects.remove(c, do_unlink=True)
    me.polygons.foreach_set("use_smooth", np.full(len(me.polygons), True, bool))
    me.set_sharp_from_angle(angle=math.radians(16))
    for w, sg, lm, al in mods:
        m = ob.modifiers.new("Bevel", "BEVEL")
        m.width, m.segments, m.limit_method, m.angle_limit, m.harden_normals = w, sg, lm, al, True


def box_data(lo, hi):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def box(name, lo, hi, mat="white", bevel=0.03, **kw):
    v, f = box_data(lo, hi)
    return mesh(name, v, f, mat, bevel=bevel, **kw)


def prism(name, outline, lo, hi, axis="z", mat="white", bevel=0.03, taper=None, **kw):
    """The outline (2D points) pushed from lo to hi along the axis: "z" - outline (x, y); "y" -
    outline (x, z); "x" - outline (y, z). taper: the far end's outline instead (same point count)."""
    def P(p, h):
        return {"z": (p[0], p[1], h), "y": (p[0], h, p[1]), "x": (h, p[0], p[1])}[axis]
    n = len(outline)
    far = taper or outline
    verts = [P(p, lo) for p in outline] + [P(p, hi) for p in far]
    faces = [tuple(range(n)), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return mesh(name, verts, faces, mat, bevel=bevel, **kw)


def skin(name, rings, mat="dark", caps=True, bevel=0.0, loop=False, **kw):
    """Skins a stack of rings (lists of the same number of points). loop: the last joins the first."""
    n = len(rings[0])
    R = len(rings)
    verts = [p for r in rings for p in r]
    faces = []
    for i in range(R if loop else R - 1):
        i2 = (i + 1) % R
        for j in range(n):
            k = (j + 1) % n
            faces.append((i * n + j, i * n + k, i2 * n + k, i2 * n + j))
    if caps and not loop:
        faces += [tuple(range(n)), tuple(range((len(rings) - 1) * n, len(rings) * n))]
    return mesh(name, verts, faces, mat, bevel=bevel, **kw)


def lathe(name, profile, origin, axis="z", seg=48, mat="gold", smooth=True, caps=False, loop=False, **kw):
    """The profile - (radius, height) points - turned round the axis through origin. loop: the
    profile is a closed outline (a ring's section)."""
    o = Vector(origin)
    rings = []
    for r, h in profile:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            c, s = r * math.cos(a), r * math.sin(a)
            ring.append(o + Vector({"z": (c, s, h), "x": (h, c, s), "y": (c, h, s)}[axis]))
        rings.append(ring)
    return skin(name, rings, mat, caps=caps, loop=loop, smooth=smooth, **kw)


def cyl(name, p0, p1, r0, r1=None, mat="dark", seg=16, **kw):
    p0, p1 = Vector(p0), Vector(p1)
    r1 = r0 if r1 is None else r1
    t = (p1 - p0).normalized()
    u = t.cross(Vector((0, 0, 1)))
    u = u.normalized() if u.length > 1e-5 else Vector((1, 0, 0))
    v = t.cross(u)
    rings = [[p + u * (r * math.cos(2 * math.pi * k / seg)) + v * (r * math.sin(2 * math.pi * k / seg)) for k in range(seg)]
             for p, r in ((p0, r0), (p1, r1))]
    return skin(name, rings, mat, smooth=True, **kw)


def quad_plate(q, thick, gap):
    """A plate over the quad q (4 points, counter-clockwise seen from outside): shrunk by gap from its
    edges and raised by thick. Returns verts, faces."""
    q = [Vector(p) for p in q]
    n = (q[1] - q[0]).cross(q[3] - q[0])
    if n.length < 1e-9:
        n = (q[2] - q[1]).cross(q[0] - q[1])
    n.normalize()
    c = sum(q, Vector()) / 4
    inner = []
    for p in q:
        d = c - p
        inner.append(p + d.normalized() * min(gap * 1.4, d.length * 0.3))
    v = [p - n * 0.02 for p in inner] + [p + n * thick for p in inner]
    f = [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def merge(parts):
    """Joins (verts, faces) lists into one."""
    V, F = [], []
    for v, f in parts:
        o = len(V)
        V += list(v)
        F += [tuple(i + o for i in face) for face in f]
    return V, F


def greebles(name, origin, u, v, count, seed, size=(0.25, 0.9), height=(0.08, 0.45), mat="dark", mirror=False, bevel=0.012, lamps=0, n=None):
    """Small machinery scattered on the patch origin + a*u + b*v (a, b in 0..1), standing along the
    patch's normal: boxes and a few pipes; `lamps` of them are glowing lamps (a second object)."""
    rng = random.Random(seed)
    o, u, v = Vector(origin), Vector(u), Vector(v)
    nrm = Vector(n).normalized() if n is not None else u.cross(v).normalized()
    ul, vl = u.length, v.length
    uu, vv = u / ul, v / vl
    parts, glow = [], []
    for i in range(count):
        w, d = rng.uniform(*size), rng.uniform(*size) * rng.choice((0.4, 0.7, 1.0))
        if rng.random() < 0.5:
            w, d = d, w
        w, d = min(w, ul * 0.9), min(d, vl * 0.9)
        a, b = rng.uniform(0, ul - w), rng.uniform(0, vl - d)
        h = rng.uniform(*height) * rng.choice((0.5, 1.0, 1.0, 1.6))
        base = o + uu * a + vv * b
        pts = [base, base + uu * w, base + uu * w + vv * d, base + vv * d]
        verts = [p - nrm * 0.05 for p in pts] + [p + nrm * h for p in pts]
        faces = [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        (glow if i < lamps else parts).append((verts, faces))
    obs = []
    if parts:
        V, F = merge(parts)
        obs.append(mesh(name, V, F, mat, bevel=bevel, mirror=mirror))
    if glow:
        V, F = merge(glow)
        obs.append(mesh(name + "_Lamps", V, F, "lamp", mirror=mirror))
    return obs


def decal(name, corners, mat, lift=0.012):
    """A painted mark on the quad `corners` (its picture's bottom-left, bottom-right, top-right,
    top-left), a hair above the surface."""
    q = [Vector(p) for p in corners]
    n = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
    ob = mesh(name, [p + n * lift for p in q], [(0, 1, 2, 3)], mat, uv=[(0, 0), (1, 0), (1, 1), (0, 1)], recalc=False)
    return ob
