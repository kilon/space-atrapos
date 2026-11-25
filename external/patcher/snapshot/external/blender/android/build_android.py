"""Builds the Minoan android (the citizen of data/rigs/android.json; reference:
external/images/minoan_npc_android.png and minoan_npc_android_parts_*.png) in
Blender, from scratch, for animated sprites at 25 fps.

  blender -b --python build_android.py                 # builds, saves android.blend + previews
  (or inside Blender: exec it, then build())

Everything is in the collection "Android", under the empty "AndroidRoot"
(turn it to face the 8 directions). Facing -Y, feet on z = 0, about 2.2 m to
the top of the frill. An android: every part is a rigid object parented to
one bone of "AndroidRig" (no weight painting). The legs are IK chains to the
foot controls FootIK.L / .R (the feet hang on them, kept flat); the hands are
IK chains to the rifle (GripR / ForeL on it); the rifle hangs on RifleCtrl
(child of the chest bone). Animations (25 fps): see android_anims.py.

Look: 1980s anime cel shading - every material is a toon ramp (lit / shade,
hard edge) on a flat colour, with an ink outline (an inverted hull: a
Solidify modifier drawing the back faces black). Cream ceramic, bronze-gold
trim, navy joints, grey-blue ball joints, red cloth, glowing cyan lights; the
frill, kilt border and cape emblem are painted textures made here (numpy).
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    "/home/kilon/MEGA/Dimitris/godot/space-atrapos/external/blender/android"
COLL = "Android"
ROOT = "AndroidRoot"
RIG = "AndroidRig"

# The skeleton's joints (m; the character's right is -X, it faces -Y).
ANKLE_Z, KNEE_Z, HIP_Z = 0.15, 0.66, 1.0
LIFT = 0.13          # the body above the hips is built at HIP_Z = 1.0, then lifted (long legs)
LEG_HIP = HIP_Z + LIFT
HIP_X = 0.13
SHOULDER = Vector((0.30, 0.0, 1.52))
ELBOW_Z, WRIST_Z = 1.21, 0.93
NECK_Z = 1.58
HEAD = Vector((0.0, -0.04, 1.80))

# ---------------------------------------------------------------- palette
CREAM = (0.93, 0.84, 0.66)
CREAM_DARK = (0.80, 0.68, 0.50)
GOLD = (0.95, 0.66, 0.16)
BRONZE = (0.62, 0.38, 0.12)
NAVY = (0.16, 0.22, 0.36)
BALL = (0.47, 0.49, 0.60)
RED = (0.62, 0.08, 0.07)
CYAN = (0.25, 0.95, 1.0)
IVORY = (0.97, 0.93, 0.82)
GUNMETAL = (0.28, 0.30, 0.34)
DARK = (0.10, 0.11, 0.14)


# ---------------------------------------------------------------- textures

def _image(name, rgb):
    """A Blender image from an (h, w, 3) float array (top row first)."""
    h, w = rgb.shape[:2]
    img = bpy.data.images.get(name)
    if img and (img.size[0], img.size[1]) != (w, h):
        bpy.data.images.remove(img)
        img = None
    img = img or bpy.data.images.new(name, w, h, alpha=False)
    px = np.ones((h, w, 4), np.float32)
    px[:, :, :3] = rgb[::-1]            # (Blender's rows go bottom-up)
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def _srgb(c):
    return np.array(c, np.float32)


def _spiral(px, py, cx, cy, r, turns=2.2, width=0.42):
    """Mask of an Archimedean spiral of radius r centred at (cx, cy)."""
    dx, dy = px - cx, py - cy
    rho = np.sqrt(dx * dx + dy * dy) / r
    phi = (np.arctan2(dy, dx) / (2 * math.pi)) % 1.0
    arm = ((rho * turns - phi) % 1.0) < width
    return arm & (rho < 1.0) & (rho > 0.08) | (rho <= 0.08)


def tex_frill(n=1024):
    """The frill's painted face (the fan is the lower half of the image, v < 0.5:
    the plates' -y is up once the frill leans back): cream, bold red petals
    fanning out from the head, big red spirals round the rim."""
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2.0 - 1.0     # (y down the image = up the fan)
    out = np.empty((n, n, 3), np.float32)
    out[:] = _srgb(CREAM)
    red = np.zeros((n, n), bool)
    # Petals: long lens shapes fanning out from the head.
    for k in range(7):
        ang = math.radians(-160 + k * (140 / 6))
        u = x * math.cos(ang) - y * math.sin(ang) * -1.0
        u = x * math.cos(ang) + y * -math.sin(ang) * -1.0
        cx, cy = math.cos(ang), -math.sin(ang)
        u = x * cx + y * cy
        v = -x * cy + y * cx
        red |= (u > 0.2) & (u < 0.62) & (np.abs(v) < 0.085 * np.sin(np.clip((u - 0.2) / 0.42, 0, 1) * math.pi))
    # Big spirals round the rim.
    for k in range(7):
        ang = math.radians(-205 + k * (230 / 6))
        cx, cy = 0.74 * math.cos(ang), -0.74 * math.sin(ang)
        red |= _spiral(x, y, cx, cy, 0.19, turns=2.1, width=0.36)
    out[red] = _srgb(RED)
    r = np.sqrt(x * x + y * y)
    out[(r > 0.9) & (r < 0.94)] = _srgb(CREAM_DARK)     # (a band inside the rim)
    return out


def tex_band(w=1024, h=256):
    """The kilt's cloth: cream, a red border with a cream running wave near
    the hem, a thin red stripe above it."""
    v, u = np.mgrid[0:h, 0:w] / np.array([h - 1, w - 1])[:, None, None]
    v = 1.0 - v                      # 0 = hem, 1 = belt
    out = np.empty((h, w, 3), np.float32)
    out[:] = _srgb(CREAM)
    out[((u * 32.0) % 1.0) < 0.5] = _srgb(tuple(c * 0.93 for c in CREAM))   # (the pleats' shaded halves)
    band = (v > 0.04) & (v < 0.26)
    out[band] = _srgb(RED)
    t = (v - 0.04) / 0.22
    x = u * 18.0
    wave = np.abs(t - (0.5 + 0.28 * np.sin(2 * math.pi * x))) < 0.13
    curl = _spiral(x % 1.0, t, 0.25, 0.42, 0.22, turns=1.5, width=0.45)
    out[band & (wave | curl)] = _srgb(CREAM)
    out[(v > 0.30) & (v < 0.32)] = _srgb(RED)
    out[v < 0.02] = _srgb(CREAM_DARK)
    return out


def tex_belt(w=1024, h=128):
    """The belt: gold with a row of bronze chevrons (u round the waist)."""
    v, u = np.mgrid[0:h, 0:w] / np.array([h - 1, w - 1])[:, None, None]
    out = np.empty((h, w, 3), np.float32)
    out[:] = _srgb(GOLD)
    x = (u * 28.0) % 1.0
    y = np.abs(v - 0.5) * 2.0                     # 0 at the middle, 1 at the edges
    chev = (np.abs(x - 0.5 - 0.25 * y) < 0.09) & (y < 0.6)
    out[chev] = _srgb(BRONZE)
    out[(v < 0.1) | (v > 0.9)] = _srgb(BRONZE)
    return out


def tex_wave(w=1024, h=128):
    """A red Minoan band with a cream running wave and gold edges (cuffs)."""
    v, u = np.mgrid[0:h, 0:w] / np.array([h - 1, w - 1])[:, None, None]
    out = np.empty((h, w, 3), np.float32)
    out[:] = _srgb(RED)
    x = u * 10.0
    t = (v - 0.12) / 0.76
    wave = (t > 0) & (t < 1) & (np.abs(t - (0.5 + 0.28 * np.sin(2 * math.pi * x))) < 0.14)
    curl = _spiral(x % 1.0, t, 0.3, 0.45, 0.26, turns=1.5, width=0.45) & (t > 0) & (t < 1)
    out[wave | curl] = _srgb(CREAM)
    out[(v < 0.1) | (v > 0.9)] = _srgb(GOLD)
    return out


def tex_cape(n=1024):
    """The cape: red, a gold border band on the hem and sides, a gold
    triskelion in the middle of the back (u: around, v: down from the top)."""
    v, u = np.mgrid[0:n, 0:n] / (n - 1)
    out = np.empty((n, n, 3), np.float32)
    out[:] = _srgb(RED)
    border = (v > 0.92) | (u < 0.035) | (u > 0.965)
    out[border] = _srgb(GOLD)
    # Triskelion: three spirals round a centre.
    cx, cy, R = 0.5, 0.38, 0.17
    gold = np.zeros((n, n), bool)
    for k in range(3):
        ang = math.radians(90 + k * 120)
        sx, sy = cx + 0.55 * R * math.cos(ang), cy - 0.55 * R * math.sin(ang)
        gold |= _spiral(u, v, sx, sy, 0.55 * R, turns=1.6, width=0.4)
    gold |= np.hypot(u - cx, v - cy) < 0.018
    out[gold] = _srgb(GOLD)
    return out


# ---------------------------------------------------------------- materials

def _new_mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return m, nt


def _lin(c):
    """sRGB (as painted) -> the linear values Blender's colour inputs take."""
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat_toon(name, color, shade=0.58, image=None, mapping=None, hi=0.0):
    """Cel shading: diffuse light -> two hard tones (lit, shade) times the
    colour (or a painted image); a thin bright rim on the lit edge."""
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.location = (-400, 200)
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    s2r.location = (-200, 200)
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    bw.location = (0, 200)
    nt.links.new(s2r.outputs["Color"], bw.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (150, 200)
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    sh = _lin((shade, shade * 0.95, min(1.0, shade * 1.05)))
    els[0].position, els[0].color = 0.0, (*sh, 1)
    els[1].position, els[1].color = 0.42, (1.0, 1.0, 1.0, 1)
    if hi > 0:       # (a third tone: the anime highlight where the light hits square)
        e = els.new(0.86)
        e.color = (1.0 + hi, 1.0 + hi, 1.0 + hi * 0.9, 1)
    nt.links.new(bw.outputs[0], ramp.inputs["Fac"])
    if image is not None:
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.location = (-200, -150)
        tx.image = image
        tx.interpolation = "Closest" if image.size[0] < 300 else "Linear"
        col = tx.outputs["Color"]
    else:
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.location = (-200, -150)
        rgb.outputs[0].default_value = (*_lin(color), 1)
        col = rgb.outputs[0]
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.location = (450, 100)
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(col, mul.inputs[6])
    nt.links.new(ramp.outputs["Color"], mul.inputs[7])
    em = nt.nodes.new("ShaderNodeEmission")
    em.location = (680, 0)
    nt.links.new(mul.outputs[2], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def mat_glow(name, color, strength=2.2):
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*_lin(color), 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def mat_outline(name="AND_Ink", color=(0.006, 0.004, 0.005)):
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True
    return m


M = {}
INK = 2.7          # outline thickness multiplier (the sprites are small: bold ink)


def make_materials():
    M.update({
        "cream": mat_toon("AND_Cream", CREAM, hi=0.07),
        "cream_dark": mat_toon("AND_CreamDark", CREAM_DARK, hi=0.07),
        "gold": mat_toon("AND_Gold", GOLD, shade=0.5, hi=0.3),
        "bronze": mat_toon("AND_Bronze", BRONZE, shade=0.55, hi=0.2),
        "belt": mat_toon("AND_Belt", GOLD, shade=0.5, hi=0.3, image=_image("AND_belt", tex_belt())),
        "wave": mat_toon("AND_Wave", RED, shade=0.6, image=_image("AND_wave", tex_wave())),
        "navy": mat_toon("AND_Navy", NAVY, shade=0.6),
        "ball": mat_toon("AND_Ball", BALL, shade=0.6),
        "red": mat_toon("AND_Red", RED, shade=0.6, hi=0.08),
        "ivory": mat_toon("AND_Ivory", IVORY, shade=0.66, hi=0.1),
        "gunmetal": mat_toon("AND_Gunmetal", GUNMETAL, shade=0.6),
        "steel": mat_toon("AND_Steel", (0.56, 0.58, 0.63), shade=0.55, hi=0.25),
        "dark": mat_toon("AND_Dark", DARK, shade=0.7),
        "cyan": mat_glow("AND_Cyan", CYAN, 2.4),
        "eye": mat_glow("AND_Eye", (0.55, 1.0, 1.0), 3.0),
        "ink": mat_outline(),
        "frill": mat_toon("AND_Frill", CREAM, image=_image("AND_frill", tex_frill())),
        "kilt": mat_toon("AND_Kilt", CREAM, image=_image("AND_kilt", tex_band())),
        "cape": mat_toon("AND_Cape", RED, shade=0.6, image=_image("AND_cape", tex_cape())),
    })


# ---------------------------------------------------------------- mesh helpers

def _coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def _obj(name):
    return bpy.data.objects.get(name)


def _link(name, data):
    ob = bpy.data.objects.new(name, data)
    _coll().objects.link(ob)
    return ob


def mesh_object(name, bm, mats, smooth=False, outline=0.006, bevel=0.0):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = _link(name, me)
    for m in mats:
        me.materials.append(M[m])
    if bevel > 0:
        b = ob.modifiers.new("Bevel", "BEVEL")
        b.width, b.segments, b.limit_method = bevel, 2, "ANGLE"
    outline *= INK
    if outline > 0:
        me.materials.append(M["ink"])
        s = ob.modifiers.new("Ink", "SOLIDIFY")
        s.thickness = -outline        # (outward from the surface)
        s.offset = -1.0
        s.use_flip_normals = True
        s.use_rim = False
        s.material_offset = len(me.materials) - 1
    return ob


def _orient(bm, verts, p1, p2):
    """Moves verts made along +Z (0..1 long) to run from p1 to p2."""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p1) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((1, 1, d.length, 1)), verts=verts)


def limb(name, p1, p2, r1, r2, mat="cream", seg=14, squash=(1.0, 1.0), smooth=True, outline=0.006):
    """A tapered cylinder from p1 to p2 (radius r1 -> r2), capped."""
    bm = bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r1, radius2=r2, depth=1.0)
    bmesh.ops.translate(bm, vec=(0, 0, 0.5), verts=res["verts"])
    bmesh.ops.scale(bm, vec=(squash[0], squash[1], 1), verts=res["verts"])
    _orient(bm, res["verts"], p1, p2)
    return mesh_object(name, bm, [mat], smooth=smooth, outline=outline)


def ball(name, loc, r, mat="ball", scale=(1, 1, 1), seg=16, outline=0.005, half=False, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    if half:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    if rot != (0, 0, 0):
        bmesh.ops.transform(bm, matrix=_euler(rot).to_matrix().to_4x4(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
    return mesh_object(name, bm, [mat], smooth=True, outline=outline)


def box(name, size, loc, mat="cream", rot=(0, 0, 0), taper=None, bevel=0.01, outline=0.006):
    """A box (size x, y, z) at loc; taper = (top x scale, top y scale)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        if taper and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    bmesh.ops.transform(bm, matrix=Matrix.LocRotScale(Vector(loc), Matrix.Rotation(0, 3, "Z").to_quaternion() if rot == (0, 0, 0) else
                                                      _euler(rot), None), verts=bm.verts)
    return mesh_object(name, bm, [mat], bevel=bevel, outline=outline)


def _euler(rot):
    from mathutils import Euler
    return Euler(rot, "XYZ").to_quaternion()


def torus(name, loc, R, r, mat="gold", normal=(0, 0, 1), seg=32, outline=0.004):
    bm = bmesh.new()
    verts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(8):
            b = 2 * math.pi * j / 8
            verts.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
    for i in range(seg):
        for j in range(8):
            a, b = i * 8 + j, i * 8 + (j + 1) % 8
            c, d = ((i + 1) % seg) * 8 + (j + 1) % 8, ((i + 1) % seg) * 8 + j
            bm.faces.new((verts[a], verts[b], verts[c], verts[d]))
    q = Vector((0, 0, 1)).rotation_difference(Vector(normal).normalized())
    bmesh.ops.transform(bm, matrix=Matrix.Translation(loc) @ q.to_matrix().to_4x4(), verts=bm.verts)
    return mesh_object(name, bm, [mat], smooth=True, outline=outline)


def cone(name, base, tip, r, mat="ivory", seg=12, outline=0.005, curve=0.0, side=None):
    """A horn / claw: a cone from base to tip, optionally curved toward side."""
    base, tip = Vector(base), Vector(tip)
    bm = bmesh.new()
    rings = 6
    side = Vector(side or (0, 0, 1)).normalized()
    rows = []
    for k in range(rings + 1):
        t = k / rings
        c = base.lerp(tip, t) + side * curve * math.sin(math.pi * t) * (base - tip).length
        rr = r * (1 - t) + 0.002
        d = (tip - base).normalized()
        q = Vector((0, 0, 1)).rotation_difference(d)
        row = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            row.append(bm.verts.new(c + q @ Vector((rr * math.cos(a), rr * math.sin(a), 0))))
        rows.append(row)
    for k in range(rings):
        for i in range(seg):
            bm.faces.new((rows[k][i], rows[k][(i + 1) % seg], rows[k + 1][(i + 1) % seg], rows[k + 1][i]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])
    return mesh_object(name, bm, [mat], smooth=True, outline=outline)


def sheet(name, fn, nu, nv, mat, thick=0.012, outline=0.005, uv=True):
    """A cloth sheet: fn(u, v) -> point, u, v in 0..1, given thickness."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = [[bm.verts.new(fn(i / nu, j / nv)) for i in range(nu + 1)] for j in range(nv + 1)]
    for j in range(nv):
        for i in range(nu):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uvl].uv = (a / nu, 1.0 - b / nv)
    ob = mesh_object(name, bm, [mat], smooth=True, outline=outline)
    if thick:
        s = ob.modifiers.new("Thick", "SOLIDIFY")
        s.thickness = thick
        ob.modifiers.move(len(ob.modifiers) - 1, 0)
    return ob


# ---------------------------------------------------------------- shaped helpers (v2)

def _se(a, b, n, seg, th0=0.0, th1=2 * math.pi, closed=True):
    """Points of a superellipse (half-sizes a, b; n = 2 round .. 6 boxy);
    angle 0 = +b (the front), going round toward +a."""
    out = []
    count = seg if closed else seg + 1
    for i in range(count):
        t = th0 + (th1 - th0) * i / seg
        s, c = math.sin(t), math.cos(t)
        out.append((a * math.copysign(abs(s) ** (2.0 / n), s), b * math.copysign(abs(c) ** (2.0 / n), c)))
    return out


def _frame_to(p1, p2, front=(0, -1, 0)):
    """A matrix taking local z (0..1 = p1..p2 in metres), local y = front,
    x = y cross z... to the world."""
    p1, p2 = Vector(p1), Vector(p2)
    z = (p2 - p1).normalized()
    f = Vector(front)
    y = (f - z * f.dot(z))
    if y.length < 1e-6:
        y = Vector((0, -1, 0)) - z * z.y * -1
    y.normalize()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = p1
    return m


def _flat_caps(ob, n):
    """The last n faces (a loft's caps) shaded flat."""
    ps = ob.data.polygons
    for i in range(len(ps) - n, len(ps)):
        if i >= 0:
            ps[i].use_smooth = False


def loft(name, secs, mat="cream", axis="z", seg=24, outline=0.006, bevel=0.0, frame=None, smooth=True, round_ends=True):
    """A lofted solid through rounded cross-sections secs = [(t, c1, c2, a, b, n)].
    axis "z": rings at z = t centred (x=c1, y=c2), half-sizes a (x), b (y);
    axis "y": rings at y = t centred (x=c1, z=c2), a (x), b (z).
    frame: a matrix applied after (limb space: local z along the limb)."""
    if round_ends and len(secs) >= 2:
        # (rounded ends: a smaller ring a little beyond each end, so the flat
        # caps are small and the ends read as rounded plates, not cut blocks)
        def _end(p, q):
            t, c1, c2, a, b, n = p
            d = math.copysign(min(a, b) * 0.3, p[0] - q[0])
            return (t + d, c1, c2, a * 0.7, b * 0.7, n)
        secs = [_end(secs[0], secs[1])] + list(secs) + [_end(secs[-1], secs[-2])]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rings = []
    for (t, c1, c2, a, b, n) in secs:
        ring = []
        for (u, w) in _se(a, b, n, seg):
            co = (c1 + u, c2 + w, t) if axis == "z" else (c1 + u, t, c2 + w)
            ring.append(bm.verts.new(co))
        rings.append(ring)
    t0, t1 = secs[0][0], secs[-1][0]
    for k in range(len(rings) - 1):
        v0 = (secs[k][0] - t0) / (t1 - t0) if t1 != t0 else 0.0
        v1 = (secs[k + 1][0] - t0) / (t1 - t0) if t1 != t0 else 1.0
        for i in range(seg):
            j = (i + 1) % seg
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            for loop, (uu, vv) in zip(f.loops, ((i / seg, v0), ((i + 1) / seg, v0), ((i + 1) / seg, v1), (i / seg, v1))):
                loop[uvl].uv = (uu, 1.0 - vv)
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if frame is not None:
        bmesh.ops.transform(bm, matrix=frame, verts=bm.verts)
    ob = mesh_object(name, bm, [mat], smooth=smooth, outline=outline, bevel=bevel)
    _flat_caps(ob, 2)
    return ob


def limb_loft(name, p1, p2, secs, mat="cream", front=(0, -1, 0), seg=24, outline=0.006):
    """A loft along a limb from p1 to p2: secs = [(f, dx, dy, a, b, n)] with
    f = 0..1 along it, dy toward `front`."""
    L = (Vector(p2) - Vector(p1)).length
    return loft(name, [(f * L, dx, dy, a, b, n) for (f, dx, dy, a, b, n) in secs], mat, "z", seg,
                outline=outline, frame=_frame_to(p1, p2, front))


def shell(name, p1, p2, secs, th0, th1, thick=0.018, mat="cream", front=(0, -1, 0), seg=24, outline=0.005):
    """An armour plate wrapping a limb: the part of the rounded section between
    angles th0..th1 (radians, 0 = front, + toward local +x), from f0 to f1
    along p1 -> p2; secs = [(f, a, b, n)] (outer half-sizes)."""
    L = (Vector(p2) - Vector(p1)).length
    bm = bmesh.new()
    outer, inner = [], []
    for (f, a, b, n) in secs:
        o = [bm.verts.new((u, w, f * L)) for (u, w) in _se(a, b, n, seg, th0, th1, closed=False)]
        i = [bm.verts.new((u, w, f * L)) for (u, w) in _se(a - thick, b - thick, n, seg, th0, th1, closed=False)]
        outer.append(o)
        inner.append(i)
    for k in range(len(secs) - 1):
        for j in range(seg):
            bm.faces.new((outer[k][j], outer[k][j + 1], outer[k + 1][j + 1], outer[k + 1][j]))
            bm.faces.new((inner[k][j + 1], inner[k][j], inner[k + 1][j], inner[k + 1][j + 1]))
        for j in (0, seg):   # (the side edges)
            bm.faces.new((outer[k][j], outer[k + 1][j], inner[k + 1][j], inner[k][j]))
    for k in (0, len(secs) - 1):   # (the ends)
        for j in range(seg):
            bm.faces.new((outer[k][j], inner[k][j], inner[k][j + 1], outer[k][j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=_frame_to(p1, p2, front), verts=bm.verts)
    return mesh_object(name, bm, [mat], smooth=True, outline=outline)


def tube(name, pts, r, mat="dark", seg=10, ribs=0.0, outline=0.004, steps=6):
    """A hose along points pts (smoothed), radius r; ribs = rib spacing (m)."""
    P = [Vector(p) for p in pts]
    path = []
    for i in range(len(P) - 1):           # Catmull-Rom through the points
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for s in range(steps):
            t = s / steps
            path.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    path.append(P[-1])
    bm = bmesh.new()
    rings = []
    dist = 0.0
    nrm = None
    for k, p in enumerate(path):
        d = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
        if nrm is None:
            nrm = d.orthogonal().normalized()
        nrm = (nrm - d * nrm.dot(d)).normalized()
        bin_ = d.cross(nrm)
        if k:
            dist += (p - path[k - 1]).length
        rr = r * (1.0 + (0.22 if ribs and (dist / ribs) % 1.0 < 0.45 else 0.0))
        rings.append([bm.verts.new(p + (nrm * math.cos(2 * math.pi * i / seg) + bin_ * math.sin(2 * math.pi * i / seg)) * rr) for i in range(seg)])
    for k in range(len(rings) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = mesh_object(name, bm, [mat], smooth=True, outline=outline)
    _flat_caps(ob, 2)
    return ob


def _se_pt(a, b, n, th):
    s, c = math.sin(th), math.cos(th)
    return (a * math.copysign(abs(s) ** (2.0 / n), s), b * math.copysign(abs(c) ** (2.0 / n), c))


def _interp(secs, t):
    """The section at t, linearly between the given ones (by their first value)."""
    secs = sorted(secs, key=lambda q: q[0])
    if t <= secs[0][0]:
        return secs[0]
    if t >= secs[-1][0]:
        return secs[-1]
    for p, q in zip(secs, secs[1:]):
        if p[0] <= t <= q[0]:
            k = (t - p[0]) / (q[0] - p[0]) if q[0] != p[0] else 0.0
            return tuple(x + (y - x) * k for x, y in zip(p, q))
    return secs[-1]


def on_limb(p1, p2, secs, th, f, front=(0, -1, 0), lift=0.004):
    """A point on a limb_loft's / shell's surface (angle th, fraction f),
    lifted a little off it (for lines and trim laid on the plate)."""
    L = (Vector(p2) - Vector(p1)).length
    v = _interp(secs, f)
    if len(v) == 4:
        _, a, b, n = v
        dx = dy = 0.0
    else:
        _, dx, dy, a, b, n = v
    u, w = _se_pt(a + lift, b + lift, n, th)
    return _frame_to(p1, p2, front) @ Vector((dx + u, dy + w, f * L))


def on_loft(secs, axis, th, t, lift=0.004):
    """A point on a loft's surface (angle th, at t along its axis)."""
    _, c1, c2, a, b, n = _interp(secs, t)
    u, w = _se_pt(a + lift, b + lift, n, th)
    return Vector((c1 + u, c2 + w, t)) if axis == "z" else Vector((c1 + u, t, c2 + w))


def groove(name, pts, bone, r=0.0035, mat="dark"):
    """A drawn panel line: a thin dark tube laid on a plate."""
    return part(tube(name, pts, r, mat, seg=6, steps=3, outline=0.0), bone)


def trim(name, pts, bone, r=0.007, mat="gold"):
    """Gold piping along a plate's edge."""
    return part(tube(name, pts, r, mat, seg=8, steps=3, outline=0.003), bone)


def piston(name, p1, p2, bone_cyl, bone_rod, r=0.013):
    """A hydraulic piston from p1 (its cylinder, on one bone) to p2 (its rod,
    on the next): in the rest pose they line up; as the joint bends the rod
    slides in its cylinder."""
    p1, p2 = Vector(p1), Vector(p2)
    mid = p1.lerp(p2, 0.55)
    part(limb(name + "Cyl", p1, mid, r, r, "gunmetal", seg=10, outline=0.003), bone_cyl)
    part(ball(name + "CylCap", p1, r * 1.25, "dark", seg=10, outline=0.002), bone_cyl)
    part(limb(name + "Rod", p1.lerp(p2, 0.45), p2, r * 0.55, r * 0.55, "ball", seg=8, outline=0.002), bone_rod)
    part(ball(name + "RodEnd", p2, r * 0.95, "dark", seg=10, outline=0.002), bone_rod)


def rivets(prefix, pts, bone, r=0.009, mat="gold"):
    for k, p in enumerate(pts):
        part(ball("%s%d" % (prefix, k), p, r, mat, seg=8, outline=0.0), bone)


# ---------------------------------------------------------------- the body (v2: detailed)

PARTS = {}      # object name -> bone


def part(ob, bone):
    PARTS[ob.name] = bone
    return ob


def build_legs():
    for s, sx in (("L", 1), ("R", -1)):
        x = HIP_X * sx
        hip = Vector((x, 0, LEG_HIP))
        knee = Vector((x, -0.01, KNEE_Z))
        ank = Vector((x, 0, ANKLE_Z))
        T, H = "thigh." + s, "shin." + s
        # Thigh: a navy core, two cream plates in front (a seam between), a side plate.
        part(ball("HipBall." + s, hip, 0.085), T)
        a, b = hip + Vector((0, 0, -0.02)), knee + Vector((0, 0, 0.05))
        part(limb_loft("ThighCore." + s, a, b, [(0, 0, 0, 0.088, 0.085, 2.4), (0.5, 0, 0, 0.098, 0.092, 2.6), (1, 0, 0, 0.075, 0.075, 2.3)], "navy"), T)
        part(shell("ThighPlateUp." + s, a, b, [(0.06, 0.112, 0.112, 3.5), (0.3, 0.12, 0.12, 3.6), (0.47, 0.118, 0.118, 3.6)], -1.3, 1.3), T)
        part(shell("ThighPlateLow." + s, a, b, [(0.53, 0.116, 0.116, 3.6), (0.75, 0.108, 0.108, 3.6), (0.93, 0.094, 0.094, 3.4)], -1.1, 1.1), T)
        side = (1.35, 2.3) if sx > 0 else (-2.3, -1.35)
        part(shell("ThighSide." + s, a, b, [(0.15, 0.118, 0.11, 3.5), (0.5, 0.124, 0.115, 3.5), (0.8, 0.11, 0.1, 3.5)], *side), T)
        rivets("ThighRiv%s" % s, [a.lerp(b, f) + Vector((dx, -0.122, 0)) for f, dx in ((0.12, -0.05), (0.12, 0.05), (0.62, -0.045), (0.62, 0.045))], T, mat="dark")
        low = [(0.53, 0.116, 0.116, 3.6), (0.75, 0.108, 0.108, 3.6), (0.93, 0.094, 0.094, 3.4)]
        groove("ThighLine." + s, [on_limb(a, b, low, 0.0, f) for f in (0.56, 0.7, 0.9)], T)
        trim("ThighTrim." + s, [on_limb(a, b, low, th, 0.92) for th in (-1.05, -0.5, 0.0, 0.5, 1.05)], T, r=0.006)
        ta, tb = a, b
        # Knee: a ball joint, a gold disc on the outside, a cream cap in front.
        part(ball("KneeBall." + s, knee, 0.075), H)
        out = Vector((sx, 0, 0))
        part(limb_loft("KneeDisc." + s, knee + out * 0.07, knee + out * 0.105, [(0, 0, 0, 0.055, 0.055, 2), (1, 0, 0, 0.05, 0.05, 2)], "gold", front=(0, 0, 1)), H)
        part(torus("KneeDiscRim." + s, knee + out * 0.105, 0.042, 0.009, "bronze", normal=out, seg=20, outline=0.003), H)
        part(ball("KneeDiscHub." + s, knee + out * 0.107, 0.025, "gold", scale=(0.45, 1, 1), outline=0.003), H)
        part(loft("KneeCap." + s, [(KNEE_Z - 0.06, x, -0.075, 0.06, 0.03, 3), (KNEE_Z + 0.0, x, -0.09, 0.07, 0.04, 3.2), (KNEE_Z + 0.06, x, -0.08, 0.055, 0.03, 3)], "cream"), H)
        # Shin: a navy core under two big angular guards, a cyan light strip, a gold band.
        a, b = knee + Vector((0, 0, -0.04)), ank + Vector((0, 0, 0.07))
        part(limb_loft("ShinCore." + s, a, b, [(0, 0, 0, 0.07, 0.07, 2.2), (1, 0, 0, 0.055, 0.055, 2.2)], "navy"), H)
        part(shell("ShinGuardUp." + s, a, b, [(0.02, 0.1, 0.105, 4.0), (0.25, 0.112, 0.12, 4.2), (0.5, 0.104, 0.112, 4.2)], -2.75, 2.75, thick=0.022), H)
        part(shell("ShinGuardLow." + s, a, b, [(0.54, 0.1, 0.108, 4.2), (0.75, 0.092, 0.1, 4.0), (0.95, 0.085, 0.09, 3.6)], -2.7, 2.7, thick=0.022), H)
        strip = (0.25, 0.5) if sx > 0 else (-0.5, -0.25)
        part(shell("ShinLight." + s, a, b, [(0.18, 0.118, 0.126, 4.2), (0.5, 0.11, 0.118, 4.2), (0.82, 0.098, 0.105, 4.0)], *strip, thick=0.008, mat="cyan", outline=0.003), H)
        part(torus("ShinBand." + s, ank + Vector((0, 0, 0.085)), 0.078, 0.016, "gold"), H)
        up = [(0.02, 0.1, 0.105, 4.0), (0.25, 0.112, 0.12, 4.2), (0.5, 0.104, 0.112, 4.2)]
        lo = [(0.54, 0.1, 0.108, 4.2), (0.75, 0.092, 0.1, 4.0), (0.95, 0.085, 0.09, 3.6)]
        trim("ShinTrim." + s, [on_limb(a, b, up, th, 0.035) for th in (-1.9, -1.2, -0.6, 0.0, 0.6, 1.2, 1.9)], H, r=0.0065)
        groove("ShinChevron." + s, [on_limb(a, b, up, -0.85, 0.08), on_limb(a, b, up, -0.4, 0.22), on_limb(a, b, up, 0.0, 0.3), on_limb(a, b, up, 0.4, 0.22), on_limb(a, b, up, 0.85, 0.08)], H)
        groove("ShinLine." + s, [on_limb(a, b, lo, 0.0, f) for f in (0.58, 0.75, 0.92)], H)
        groove("ShinSideLine." + s, [on_limb(a, b, up, -1.4 * sx, f) for f in (0.1, 0.3, 0.48)], H)
        # Pistons: behind the knee (thigh to shin) and the ankle (shin to heel).
        piston("KneePiston." + s, ta.lerp(tb, 0.68) + Vector((0.0, 0.1, 0)), a.lerp(b, 0.3) + Vector((0.0, 0.085, 0)), T, H)
        piston("AnklePiston." + s, a.lerp(b, 0.62) + Vector((0.0, 0.075, 0)), Vector((x, 0.09, 0.07)), H, "foot." + s, r=0.011)
        rivets("ShinRiv%s" % s, [a.lerp(b, f) + Vector((dx, -0.118, 0)) for f, dx in ((0.08, -0.06), (0.08, 0.06), (0.6, -0.05))], H, mat="dark")
        # Ankle and foot (the foot hangs on FootIK, flat): ball joint, gold guard,
        # a cream instep, three jointed toes with dark claws, a spur behind.
        F = "foot." + s
        part(ball("AnkleBall." + s, ank, 0.065), F)
        part(box("AnkleGuard." + s, (0.07, 0.07, 0.06), ank + Vector((0.06 * sx, -0.04, 0.0)), "gold", rot=(0, 0, 0.6 * sx), bevel=0.012), F)
        part(loft("Instep." + s, [(0.07, x, 0.085, 0.07, 0.05, 3), (0.0, x, 0.085, 0.085, 0.06, 3.2), (-0.08, x, 0.07, 0.085, 0.05, 3.2), (-0.13, x, 0.055, 0.075, 0.04, 3)], "cream", axis="y"), F)
        part(loft("InstepPlate." + s, [(0.02, x, 0.135, 0.05, 0.015, 3), (-0.1, x, 0.1, 0.045, 0.012, 3)], "gold", axis="y"), F)
        instep = [(0.07, x, 0.085, 0.07, 0.05, 3), (0.0, x, 0.085, 0.085, 0.06, 3.2), (-0.08, x, 0.07, 0.085, 0.05, 3.2), (-0.13, x, 0.055, 0.075, 0.04, 3)]
        for side in (-1, 1):
            groove("InstepLine%d.%s" % (side, s), [on_loft(instep, "y", 0.9 * side, t) for t in (0.04, -0.04, -0.11)], F)
        rivets("FootRiv%s" % s, [on_loft(instep, "y", 1.3 * side, -0.02, lift=0.002) for side in (-1, 1)], F, r=0.008, mat="dark")
        for k, dx in enumerate((-0.06, 0.0, 0.06)):
            d = Vector((dx * 1.6, -1.0, 0.0)).normalized()
            p0 = Vector((x + dx, -0.12, 0.05))
            p1 = p0 + d * 0.065 + Vector((0, 0, -0.008))
            p2 = p1 + d * 0.055 + Vector((0, 0, -0.012))
            part(limb("Toe%dA.%s" % (k, s), p0, p1, 0.039, 0.035, "cream", seg=12), F)
            part(ball("Toe%dK.%s" % (k, s), p1, 0.031, "navy", outline=0.003), F)
            part(limb("Toe%dB.%s" % (k, s), p1, p2, 0.032, 0.028, "cream", seg=12), F)
            part(cone("Claw%d.%s" % (k, s), p2 + Vector((0, 0, 0.0)), p2 + d * 0.08 + Vector((0, 0, -0.045)), 0.03, "dark", curve=0.18, side=(0, 0, 1)), F)
        part(cone("Spur." + s, (x, 0.07, 0.05), (x, 0.15, 0.0), 0.028, "dark", curve=0.12), F)


def build_body():
    S = "spine"
    # Pelvis (navy) and the belt: wide gold, bronze chevrons, the bull boss.
    part(loft("Pelvis", [(0.94, 0, 0, 0.15, 0.11, 3), (1.02, 0, 0, 0.185, 0.13, 3.2), (1.1, 0, 0, 0.17, 0.12, 3)], "navy"), "hips")
    part(loft("Belt", [(1.04, 0, 0, 0.252, 0.228, 2.3), (1.08, 0, 0, 0.258, 0.234, 2.3), (1.12, 0, 0, 0.25, 0.226, 2.3)], "belt", seg=48, round_ends=False), "hips")
    part(limb_loft("BeltBoss", (0, -0.225, 1.08), (0, -0.26, 1.08), [(0, 0, 0, 0.055, 0.05, 2.6), (1, 0, 0, 0.05, 0.045, 2.6)], "gold", front=(0, 0, 1)), "hips")
    part(ball("BullHead", (0, -0.262, 1.075), 0.024, "bronze", scale=(1, 0.6, 1.1), outline=0.003), "hips")
    for sx in (1, -1):
        part(cone("BullHorn%d" % sx, (0.018 * sx, -0.262, 1.09), (0.045 * sx, -0.265, 1.115), 0.008, "bronze", seg=6, outline=0.002, curve=0.3, side=(0, 0, 1)), "hips")
    # Kilt: pleated cream cloth with the painted red border; navy under-panels
    # at the sides; the apron in front.

    def kilt(u, v):
        a = 2 * math.pi * u - math.pi / 2
        z = 1.07 - v * 0.36
        r = 0.236 + v * 0.085
        tri = abs(((a * 32 / (2 * math.pi)) % 1.0) - 0.5) * 2.0   # (sharp pleats)
        r += 0.008 * tri * (0.4 + v)
        return Vector((r * math.cos(a), r * math.sin(a) * 0.9, z))
    part(sheet("Kilt", kilt, 96, 8, "kilt", thick=0.01), "hips")
    for sx in (1, -1):
        def under(u, v, sx=sx):
            a = math.radians(-35 + 70 * u) + (0 if sx > 0 else math.pi)
            r = 0.23 + v * 0.07
            return Vector((r * math.cos(a), r * math.sin(a) * 0.9, 1.04 - v * 0.42))
        part(sheet("UnderPanel%d" % sx, under, 12, 6, "navy", thick=0.008), "hips")

    def apron(u, v):
        x = (u - 0.5) * 0.24 * (1 + 0.25 * v)
        return Vector((x, -0.237 - 0.06 * v - 0.02 * math.cos((u - 0.5) * math.pi), 1.03 - v * 0.4))
    part(sheet("Apron", apron, 10, 8, "kilt", thick=0.008), "hips")
    # Red bead cords with tassels.
    for k, x in enumerate((-0.17, -0.12, 0.12, 0.17)):
        y = -0.24 if abs(x) < 0.15 else -0.205
        for j in range(6):
            part(ball("Bead%d_%d" % (k, j), (x, y - 0.01 - 0.002 * j, 1.03 - j * 0.03), 0.015, "red", seg=10, outline=0.003), "hips")
        part(limb("TasselCap%d" % k, (x, y - 0.025, 0.86), (x, y - 0.025, 0.835), 0.018, 0.02, "gold", seg=10, outline=0.003), "hips")
        for j in range(5):
            a = 2 * math.pi * j / 5
            off = Vector((0.01 * math.cos(a), 0.01 * math.sin(a), 0))
            part(cone("Tassel%d_%d" % (k, j), Vector((x, y - 0.025, 0.835)) + off, Vector((x, y - 0.025, 0.74)) + off * 2.2, 0.009, "red", seg=6, outline=0.002), "hips")
    # Waist: three ribbed navy rings, side hoses, small cream plates in front.
    for k, (z0, z1, w) in enumerate(((1.1, 1.17, 0.15), (1.17, 1.24, 0.14), (1.24, 1.31, 0.15))):
        part(loft("WaistRing%d" % k, [(z0, 0, 0, w * 0.93, w * 0.68, 3), (z0 + 0.035, 0, 0, w, w * 0.73, 3.2), (z1, 0, 0, w * 0.95, w * 0.69, 3)], "navy"), S)
    for sx in (1, -1):
        part(tube("WaistHose%d" % sx, [(0.13 * sx, 0.04, 1.11), (0.165 * sx, 0.03, 1.2), (0.15 * sx, 0.04, 1.32)], 0.017, "gunmetal", ribs=0.018), S)
        for k, z in enumerate((1.15, 1.22)):
            part(box("AbPlate%d_%d" % (k, sx), (0.07, 0.03, 0.055), (0.042 * sx, -0.108, z), "cream", taper=(1.1, 1.0), bevel=0.01), S)
        part(box("AbLight%d" % sx, (0.012, 0.01, 0.06), (0.1 * sx, -0.112, 1.2), "cyan", bevel=0.003, outline=0.002), S)
    # Chest: a navy frame, two cream breast plates (a navy channel between),
    # a back plate, a collar; the gold sun medallion with its glowing core.
    part(loft("ChestFrame", [(1.28, 0, 0, 0.19, 0.12, 3), (1.42, 0, 0, 0.235, 0.14, 3.2), (1.55, 0, 0, 0.23, 0.13, 3), (1.6, 0, 0, 0.16, 0.1, 2.6)], "navy"), S)
    for sx, s in ((1, "L"), (-1, "R")):
        part(loft("BreastPlate." + s, [(1.29, 0.105 * sx, -0.045, 0.085, 0.09, 3), (1.4, 0.12 * sx, -0.06, 0.115, 0.1, 3.6), (1.52, 0.12 * sx, -0.045, 0.115, 0.095, 3.4), (1.585, 0.1 * sx, -0.02, 0.08, 0.075, 2.8)], "cream"), S)
        part(loft("SidePlate." + s, [(1.27, 0.185 * sx, 0.01, 0.04, 0.1, 3), (1.45, 0.22 * sx, 0.01, 0.045, 0.12, 3.4), (1.56, 0.2 * sx, 0.01, 0.04, 0.1, 3)], "cream_dark"), S)
        rivets("ChestRiv%s" % s, [(0.19 * sx, -0.12, 1.33), (0.2 * sx, -0.13, 1.47), (0.06 * sx, -0.14, 1.55), (0.21 * sx, -0.1, 1.56)], S, mat="dark")
        bp = [(1.29, 0.105 * sx, -0.045, 0.085, 0.09, 3), (1.4, 0.12 * sx, -0.06, 0.115, 0.1, 3.6), (1.52, 0.12 * sx, -0.045, 0.115, 0.095, 3.4), (1.585, 0.1 * sx, -0.02, 0.08, 0.075, 2.8)]
        groove("ChestLine." + s, [on_loft(bp, "z", 0.45 * sx, t) for t in (1.31, 1.42, 1.54)], S)
        groove("ChestLineB." + s, [on_loft(bp, "z", th * sx, 1.46) for th in (-0.6, -0.3, 0.0, 0.3)], S)
        trim("ChestTrim." + s, [on_loft(bp, "z", -0.95 * sx, t) for t in (1.31, 1.4, 1.49, 1.57)], S)
        trim("ChestTrimLow." + s, [on_loft(bp, "z", th * sx, 1.3) for th in (-0.9, -0.4, 0.1, 0.6, 1.1)], S, r=0.006)
        part(box("ChestLight." + s, (0.016, 0.01, 0.07), (0.175 * sx, -0.145, 1.31), "cyan", bevel=0.003, outline=0.002), S)
    part(loft("BackPlate", [(1.3, 0, 0.07, 0.17, 0.08, 3), (1.45, 0, 0.09, 0.2, 0.09, 3.4), (1.57, 0, 0.07, 0.17, 0.07, 3)], "cream"), S)
    part(loft("Collar", [(1.56, 0, 0.0, 0.13, 0.1, 2.4), (1.6, 0, 0.0, 0.14, 0.11, 2.4), (1.625, 0, 0.0, 0.11, 0.085, 2.4)], "navy"), S)
    part(torus("CollarRim", (0, 0.0, 1.623), 0.1, 0.012, "gold", seg=24, outline=0.003), S)
    mc = Vector((0, -0.165, 1.43))
    part(limb_loft("Medallion", mc + Vector((0, 0.03, 0)), mc, [(0, 0, 0, 0.088, 0.088, 2), (1, 0, 0, 0.082, 0.082, 2)], "gold", front=(0, 0, 1)), S)
    for k in range(14):
        a = 2 * math.pi * k / 14
        d = Vector((math.cos(a), 0, math.sin(a)))
        part(cone("MedPetal%d" % k, mc + d * 0.07 + Vector((0, 0.008, 0)), mc + d * 0.128 + Vector((0, 0.012, 0)), 0.026, "gold", seg=8, outline=0.003), S)
    part(torus("MedRing", mc + Vector((0, -0.004, 0)), 0.064, 0.011, "bronze", normal=(0, -1, 0), seg=28, outline=0.003), S)
    part(ball("Core", mc + Vector((0, -0.004, 0)), 0.052, "cyan", scale=(1, 0.55, 1), outline=0.004), S)
    # Shoulders: a cream pauldron under the red pad, a gold rim and stud.
    for s, sx in (("L", 1), ("R", -1)):
        sh = Vector((SHOULDER.x * sx, SHOULDER.y, SHOULDER.z))
        U = "upper_arm." + s
        c = sh + Vector((0.035 * sx, 0, 0))
        part(loft("Pauldron." + s, [(c.z - 0.09, c.x, 0, 0.13, 0.125, 2.6), (c.z - 0.02, c.x, 0, 0.135, 0.13, 2.6), (c.z + 0.02, c.x, 0, 0.11, 0.105, 2.4)], "cream"), U)
        c = sh + Vector((0.02 * sx, 0, 0.03))
        part(loft("ShoulderPad." + s, [(c.z - 0.005, c.x, 0, 0.15, 0.148, 2.2), (c.z + 0.04, c.x, 0, 0.138, 0.136, 2.2), (c.z + 0.08, c.x, 0, 0.1, 0.098, 2.1), (c.z + 0.105, c.x, 0, 0.05, 0.05, 2)], "red", round_ends=False), U)
        part(torus("PadRim." + s, sh + Vector((0.02 * sx, 0, 0.032)), 0.148, 0.015, "gold"), U)
        # The gold spiral emblem, laid on the dome; a groove round the pad's rim.
        pad = [(c.z - 0.005, c.x, 0, 0.15, 0.148, 2.2), (c.z + 0.04, c.x, 0, 0.138, 0.136, 2.2), (c.z + 0.08, c.x, 0, 0.1, 0.098, 2.1), (c.z + 0.105, c.x, 0, 0.05, 0.05, 2)]
        dome = sorted((((q[3] + q[4]) / 2, q[0]) for q in pad), key=lambda q: q[0])
        def dome_z(r, dome=dome):
            return _interp([(rr, zz) for rr, zz in dome], r)[1] + 0.004
        pts = []
        for i in range(40):
            tt = i / 39.0
            rr = 0.012 + 0.07 * tt
            ang = tt * 2.0 * 2 * math.pi
            px, py = c.x + 0.04 * sx + rr * math.cos(ang), -0.03 + rr * math.sin(ang)
            pts.append(Vector((px, py, dome_z(math.hypot(px - c.x, py)))))
        part(tube("PadSpiral." + s, pts, 0.007, "gold", seg=8, steps=2, outline=0.003), U)
        part(ball("PadStud." + s, pts[0] + Vector((0, 0, 0.004)), 0.012, "gold", outline=0.002), U)
        groove("PadLine." + s, [on_loft(pad, "z", th, c.z + 0.05) for th in (-2.6, -1.3, 0.0, 1.3, 2.6)], U)
        # the cream pauldron's gold edge
        cp = sh + Vector((0.035 * sx, 0, 0))
        pl = [(cp.z - 0.09, cp.x, 0, 0.13, 0.125, 2.6), (cp.z - 0.02, cp.x, 0, 0.135, 0.13, 2.6), (cp.z + 0.02, cp.x, 0, 0.11, 0.105, 2.4)]
        trim("PauldronTrim." + s, [on_loft(pl, "z", th, cp.z - 0.085) for th in (-2.9, -2.0, -1.0, 0.0, 1.0, 2.0, 2.9)], U, r=0.006)
        # hoses from the chest into the shoulder
        part(tube("ShoulderHose." + s, [(0.17 * sx, 0.06, 1.46), (0.24 * sx, 0.07, 1.5), (0.29 * sx, 0.04, 1.46)], 0.012, "gunmetal", ribs=0.014, seg=8), "spine")


def build_arms():
    for s, sx in (("L", 1), ("R", -1)):
        x = SHOULDER.x * sx
        sh = Vector((x, 0, SHOULDER.z))
        el = Vector((x + 0.01 * sx, 0.02, ELBOW_Z))
        wr = Vector((x + 0.01 * sx, -0.01, WRIST_Z))
        U, F, Hd = "upper_arm." + s, "forearm." + s, "hand." + s
        part(ball("ShoulderBall." + s, sh, 0.072), U)
        a, b = sh - Vector((0, 0, 0.05)), el + Vector((0, 0, 0.045))
        part(limb_loft("UpperArmCore." + s, a, b, [(0, 0, 0, 0.062, 0.062, 2.2), (1, 0, 0, 0.055, 0.055, 2.2)], "navy"), U)
        part(shell("UpperArmPlate." + s, a, b, [(0.12, 0.085, 0.085, 3.2), (0.45, 0.09, 0.088, 3.4), (0.78, 0.08, 0.078, 3.2)], -2.5, 2.5), U)
        strip = (1.35, 1.65) if sx > 0 else (-1.65, -1.35)
        part(shell("UpperArmLight." + s, a, b, [(0.25, 0.092, 0.09, 3.4), (0.65, 0.088, 0.086, 3.4)], *strip, thick=0.006, mat="cyan", outline=0.002), U)
        part(torus("ElbowBand." + s, a.lerp(b, 0.88), 0.066, 0.014, "gold"), U)
        up = [(0.12, 0.085, 0.085, 3.2), (0.45, 0.09, 0.088, 3.4), (0.78, 0.08, 0.078, 3.2)]
        groove("UpperArmLine." + s, [on_limb(a, b, up, 0.0, f) for f in (0.16, 0.45, 0.74)], U)
        groove("UpperArmLineB." + s, [on_limb(a, b, up, th, 0.3) for th in (0.25, 0.7, 1.2)], U)
        ua, ub = a, b
        part(ball("ElbowBall." + s, el, 0.062), F)
        part(ball("ElbowCap." + s, el + Vector((0, 0.05, 0)), 0.045, "gold", scale=(0.9, 0.6, 1.0), outline=0.003), F)
        a, b = el - Vector((0, 0, 0.035)), wr + Vector((0, 0, 0.03))
        part(limb_loft("Forearm." + s, a, b, [(0, 0, 0, 0.066, 0.066, 3), (0.35, 0, -0.004, 0.082, 0.08, 3.4), (0.75, 0, 0, 0.072, 0.07, 3.4), (1, 0, 0, 0.06, 0.058, 3)], "cream"), F)
        part(shell("ForearmInner." + s, a, b, [(0.15, 0.084, 0.082, 3.4), (0.6, 0.082, 0.08, 3.4)], *((-2.2, -1.2) if sx > 0 else (1.2, 2.2)), thick=0.012, mat="cream_dark"), F)
        part(shell("ForearmLight." + s, a, b, [(0.2, 0.086, 0.084, 3.4), (0.62, 0.08, 0.078, 3.4)], *strip, thick=0.006, mat="cyan", outline=0.002), F)
        part(limb_loft("Cuff." + s, a.lerp(b, 0.78), a.lerp(b, 1.02), [(0, 0, 0, 0.074, 0.072, 2.6), (0.5, 0, 0, 0.08, 0.078, 2.6), (1, 0, 0, 0.072, 0.07, 2.6)], "wave"), F)
        part(torus("CuffRim." + s, a.lerp(b, 0.78), 0.074, 0.008, "gold", seg=24, outline=0.003), F)
        part(torus("CuffRimB." + s, a.lerp(b, 1.0), 0.07, 0.008, "gold", seg=24, outline=0.003), F)
        fa = [(0, 0, 0, 0.066, 0.066, 3), (0.35, 0, -0.004, 0.082, 0.08, 3.4), (0.75, 0, 0, 0.072, 0.07, 3.4), (1, 0, 0, 0.06, 0.058, 3)]
        groove("ForearmLine." + s, [on_limb(a, b, fa, 0.0, f) for f in (0.08, 0.35, 0.7)], F)
        groove("ForearmLineB." + s, [on_limb(a, b, fa, th, 0.5) for th in (-1.0, -0.6, -0.2)], F)
        piston("ElbowPiston." + s, ua.lerp(ub, 0.6) + Vector((0, 0.075, 0)), a.lerp(b, 0.35) + Vector((0, 0.07, 0)), U, F, r=0.011)
        part(box("HandPlate." + s, (0.012, 0.05, 0.06), wr + Vector((0.03 * sx, -0.0, -0.055)), "gold", bevel=0.004, outline=0.003), Hd)
        # The hand: palm and back plate, four fingers of three segments with
        # dark knuckles curled round a grip, the thumb.
        hb = wr + Vector((0, 0, -0.012))
        he = wr + Vector((0, 0, -0.1))
        part(limb_loft("Palm." + s, hb, he, [(0, 0, 0, 0.032, 0.042, 3), (0.6, 0, 0, 0.034, 0.05, 3.4), (1, 0, 0, 0.028, 0.045, 3)], "cream", front=(-sx, 0, 0)), Hd)
        part(ball("Wrist." + s, wr, 0.03, "navy", outline=0.003), Hd)
        for k in range(4):
            y = -0.033 + k * 0.022
            p = he + Vector((0, y, 0.005))
            d = Vector((0, 0, -1))
            for j, ln in enumerate((0.034, 0.028, 0.024)):
                ang = (0.55 + 0.25 * j)
                d = (Matrix.Rotation(ang * -sx, 3, Vector((0, 1, 0))) @ d).normalized() if j else (Matrix.Rotation(0.35 * -sx, 3, Vector((0, 1, 0))) @ d).normalized()
                q = p + d * ln
                part(ball("Knuckle%d%d.%s" % (k, j, s), p, 0.011, "navy", seg=8, outline=0.0), Hd)
                part(limb("Finger%d%d.%s" % (k, j, s), p, q, 0.0105, 0.0095, "cream", seg=8, outline=0.002), Hd)
                p = q
        t0 = hb + Vector((-0.02 * sx, -0.045, -0.03))
        t1 = t0 + Vector((-0.025 * sx, -0.025, -0.03))
        t2 = t1 + Vector((-0.01 * sx, -0.01, -0.03))
        part(limb("Thumb0." + s, t0, t1, 0.013, 0.012, "cream", seg=8, outline=0.002), Hd)
        part(ball("ThumbK." + s, t1, 0.012, "navy", seg=8, outline=0.0), Hd)
        part(limb("Thumb1." + s, t1, t2, 0.011, 0.01, "cream", seg=8, outline=0.002), Hd)


# ---------------------------------------------------------------- the head (traced)
# The skull is traced from the reference board's head panel: head/ref_head.png
# (external/images/minoan_npc_android.png, crop (560,385)-(960,705), scaled x2;
# head/ref_grid.png has the grid). Every outline below is in that picture's
# pixels (x forward, y down); HP() puts them on the model. The parts are flat-
# faceted plates (straight edges, flat shading), so their ink outlines draw the
# panel lines as the painting does.
K_V = 0.00101                  # m per reference pixel
REF_YAW, REF_EL = math.radians(64), math.radians(8)   # the panel's view: turned 64 degrees, 8 above


def HP(px, py, x=0.0):
    """A reference pixel -> (y, z) on the head (before LIFT), for a point at
    lateral x (the near side is -x): in the panel's 3/4 view a point's sideways
    offset moves it on the picture too, so it's undone here (head/overlay.py
    renders the same view to check)."""
    st, ct = math.sin(REF_YAW), math.cos(REF_YAW)
    f = ((px - 300) * K_V - x * ct) / st
    dY = x * st - f * ct
    dz = ((300 - py) * K_V - dY * math.sin(REF_EL)) / math.cos(REF_EL)
    return (HEAD.y - f, HEAD.z + dz)


def near(px, py, w_fn, it=2):
    """(x, y, z) of a near-side point traced at (px, py), at w_fn(pc, py) off
    the centre line (pc: the centre-line pixel of the same forward position)."""
    pc = px
    for _ in range(it):
        x = -w_fn(pc, py)
        y, z = HP(px, py, x)
        pc = 300 + (HEAD.y - y) * math.sin(REF_YAW) / K_V
    return (x, y, z)


# The skull's core, faceted sections along it: (px, top py, mouth-line py,
# half-width m, top-flat fraction, bottom fraction); chamfers in px.
SKULL = [(195, 196, 380, 0.095, 0.55, 0.7),
         (236, 156, 395, 0.108, 0.6, 0.75),
         (330, 150, 412, 0.115, 0.6, 0.75),
         (344, 186, 414, 0.115, 0.6, 0.75),
         (400, 190, 430, 0.112, 0.55, 0.75),
         (470, 248, 442, 0.098, 0.5, 0.75),
         (550, 312, 440, 0.078, 0.45, 0.75),
         (615, 372, 432, 0.06, 0.4, 0.75),
         (640, 396, 436, 0.054, 0.45, 0.75),
         (668, 404, 434, 0.044, 0.45, 0.75)]
CH_TOP, CH_BOT = 34.0, 20.0


def _skull_m():
    """SKULL in model space: (f forward of HEAD, top z, mouth z, half-width,
    top half-width, bottom half-width) - linear in f between stations, as the
    core's faces are, so skull_xm is exactly the core's surface."""
    out = []
    for (px, top, bot, hw, ft, fb) in SKULL:
        y, zt = HP(px, top)
        _, zb = HP(px, bot)
        out.append((HEAD.y - y, zt, zb, hw, ft * hw, fb * hw))
    return out


def skull_xm(f, z):
    """The core's half-width at forward f, height z (model space)."""
    _, zt, zb, hw, wt, wb = _interp(_skull_m(), f)
    ct, cb = CH_TOP * K_V, CH_BOT * K_V
    if z >= zt:
        return wt
    if z > zt - ct:
        return wt + (hw - wt) * (zt - z) / ct
    if z >= zb + cb:
        return hw
    if z > zb:
        return wb + (hw - wb) * (z - zb) / cb
    return wb


def on_skull(px, py, base=0.0, it=4):
    """(x, y, z) of the near-side point drawn at reference pixel (px, py) on
    the skull's surface (base off it)."""
    x = -(skull_x(px, py) + base)
    for _ in range(it):
        y, z = HP(px, py, x)
        x = -(skull_xm(HEAD.y - y, z) + base)
    y, z = HP(px, py, x)
    return (x, y, z)


def skull_sec(px):
    return _interp([tuple(float(v) for v in q) for q in SKULL], px)


def skull_x(px, py):
    """The skull's half-width at reference pixel (px, py) (clamped to its outline)."""
    _, top, bot, hw, ft, fb = skull_sec(px)
    if py <= top:
        return ft * hw
    if py < top + CH_TOP:
        return hw * (ft + (1 - ft) * (py - top) / CH_TOP)
    if py <= bot - CH_BOT:
        return hw
    if py < bot:
        return hw * (1 - (1 - fb) * (py - (bot - CH_BOT)) / CH_BOT)
    return fb * hw


def _mesh_from(name, rings_or_none, verts, faces, mat, outline, bevel, smooth=False):
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    caps = []
    for f in faces:
        try:
            face = bm.faces.new([vs[i] for i in f])
            if len(f) > 4:
                caps.append(face)
        except ValueError:
            pass
    if caps:
        bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = mesh_object(name, bm, [mat], smooth=smooth, outline=outline)
    if bevel > 0:
        b = ob.modifiers.new("Bevel", "BEVEL")
        b.width, b.segments, b.limit_method, b.angle_limit = bevel, 1, "ANGLE", math.radians(40)
        ob.modifiers.move(len(ob.modifiers) - 1, 0)
    return ob


def skull_core(name="Skull"):
    """The skull: an octagonal section at each SKULL station, joined by flat faces."""
    verts, faces = [], []
    n = 8
    ct, cb = CH_TOP * K_V, CH_BOT * K_V
    for (f, zt, zb, hw, wt, wb) in _skull_m():
        y = HEAD.y - f
        for (x, z) in ((wt, zt), (hw, zt - ct), (hw, zb + cb), (wb, zb),
                       (-wb, zb), (-hw, zb + cb), (-hw, zt - ct), (-wt, zt)):
            verts.append((x, y, z))
    for k in range(len(SKULL) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
    faces.append(tuple(range(n))[::-1])
    last = (len(SKULL) - 1) * n
    faces.append(tuple(range(last, last + n)))
    ob = _mesh_from(name, None, verts, faces, "cream", 0.005, 0.0)
    ob.modifiers.new("Tri", "TRIANGULATE").min_vertices = 4   # (as the plates see it)
    ob.modifiers.move(len(ob.modifiers) - 1, 0)
    return ob


def inset(pts, g):
    """A polygon (reference px) shrunk by g px all round (each edge moved in)."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sgn = 1.0 if area > 0 else -1.0
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0, e1 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n0 = Vector((-e0.y, e0.x)) * sgn
        n1 = Vector((-e1.y, e1.x)) * sgn
        m = (n0 + n1)
        if m.length < 1e-6:
            m = n0
        m.normalize()
        k = g / max(0.35, m.dot(n0))
        q = p1 + m * k
        out.append((q.x, q.y))
    return out


def panel(name, pts, sx, mat="cream", thick=0.013, base=0.0, gap=4.0, bone="head"):
    """A plate with a panel line all round it: a dark backing of the full outline
    under the plate, inset gap px (the painting's ink seams between plates)."""
    part(side_plate(name + "Seam", pts, sx, "dark", thick=0.003, base=0.0008, bevel=0.0, outline=0.0, cuts=10), bone)
    return part(side_plate(name, inset(pts, gap), sx, mat, thick=thick, base=0.0028 + base, bevel=0.0, outline=0.0, cuts=10), bone)


SKULL_OB = []      # the skull core object (plates are shrink-wrapped onto it)


def side_plate(name, pts, sx, mat="cream", thick=0.014, base=-0.004, bevel=0.003, outline=0.004, cuts=6):
    """A plate on the skull's side, outline pts traced (reference px): the
    outline is subdivided in the picture's pixels and every vertex put on the
    skull's surface (skull_x - the same shape the core is built from), so the
    plate follows its facets and chamfers; then it's given its thickness
    outward. base: its offset off the skull (stack plates with it)."""
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((px, py, 0.0)) for (px, py) in pts])
    bmesh.ops.triangulate(bm, faces=[f], quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    for v in bm.verts:
        px, py = v.co.x, v.co.y
        x, y, z = on_skull(px, py, base)
        v.co = (-sx * x, y, z)
    bm.normal_update()
    zmid = HEAD.z - 0.05
    flip = [fc for fc in bm.faces if fc.normal.dot(Vector((fc.calc_center_median().x, 0, fc.calc_center_median().z - zmid))) < 0]
    bmesh.ops.reverse_faces(bm, faces=flip)            # (every face facing out of the skull)
    ob = mesh_object(name, bm, [mat], smooth=False, outline=0.0)
    so = ob.modifiers.new("Thick", "SOLIDIFY")
    so.thickness = thick
    so.offset = 1.0
    if bevel > 0:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width, bv.segments, bv.limit_method, bv.angle_limit = bevel, 1, "ANGLE", math.radians(50)
    if outline * INK > 0:
        ob.data.materials.append(M["ink"])
        ink = ob.modifiers.new("Ink", "SOLIDIFY")
        ink.thickness = -outline * INK
        ink.offset = -1.0
        ink.use_flip_normals = True
        ink.use_rim = False
        ink.material_offset = len(ob.data.materials) - 1
    return ob


def profile_solid(name, pts, hw, mat="ivory", bevel=0.004, outline=0.005):
    """A solid from a side outline (reference px), across the head: half-width
    hw(px, py) at each outline point (tapering shapes - the beak, the jaw)."""
    verts = []
    for (px, py) in pts:
        x, y, z = near(px, py, hw)
        w = -x
        verts.append((w, y, z))
        verts.append((-w, y, z))
    n = len(pts)
    faces = [tuple(2 * i for i in range(n)), tuple(2 * i + 1 for i in range(n))[::-1]]
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
    return _mesh_from(name, None, verts, faces, mat, outline, bevel)


def _smooth(P, steps=4):
    P = [Vector(p) for p in P]
    out = []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = P[max(i - 1, 0)], P[i], P[i + 1], P[min(i + 2, len(P) - 1)]
        for s in range(steps):
            t = s / steps
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1])
    return out


def ribbon(name, pts, sx, width, thick, mat="gold", outline=0.004):
    """A flat band along pts (3D), lying against the skull's side (normal +-x)."""
    pts = _smooth(pts)
    out = Vector((sx, 0, 0))
    verts, faces = [], []
    for k, p in enumerate(pts):
        t = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
        up = t.cross(out).normalized()
        for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append(tuple(p + up * (a * width / 2) + out * (b * thick / 2)))
    m = len(pts)
    for k in range(m - 1):
        for i in range(4):
            j = (i + 1) % 4
            faces.append((4 * k + i, 4 * k + j, 4 * (k + 1) + j, 4 * (k + 1) + i))
    faces.append((3, 2, 1, 0))
    faces.append((4 * (m - 1), 4 * (m - 1) + 1, 4 * (m - 1) + 2, 4 * (m - 1) + 3))
    return _mesh_from(name, None, verts, faces, mat, outline, 0.0, smooth=False)


def at_side(px, py, sx, off=0.0):
    """A point on the skull's side at reference pixel (px, py), off it by off."""
    x, y, z = on_skull(px, py, off)
    return Vector((-sx * x, y, z))


# Outlines (reference px), the near side; the far side mirrors them.
TEMPLE = [(212, 196), (362, 188), (404, 250), (390, 282), (360, 322), (212, 312)]
TOP_PLATE = [(240, 160), (330, 152), (342, 186), (240, 192)]
BROW = [(362, 188), (400, 190), (452, 240), (536, 304), (518, 326), (474, 290), (396, 280), (404, 250)]
SOCKET = [(386, 312), (426, 288), (468, 290), (502, 334), (470, 348), (412, 342)]
EYE = [(398, 314), (430, 298), (462, 300), (490, 331), (468, 339), (420, 333)]
CHEEKS = [   # (outline, thickness): small stepped plates under the eye
    ([(345, 322), (402, 330), (424, 342), (440, 348), (432, 378), (348, 378)], 0.013),
    ([(440, 348), (508, 348), (522, 354), (500, 378), (432, 378)], 0.019),
    ([(348, 378), (432, 378), (440, 404), (350, 406)], 0.017),
    ([(432, 378), (500, 378), (470, 400), (440, 404)], 0.023),
    ([(350, 406), (410, 404), (414, 440), (352, 428)], 0.02),
    ([(410, 404), (470, 400), (478, 446), (414, 440)], 0.026)]
SNOUT = [(514, 335), (536, 306), (578, 340), (560, 380), (556, 428), (480, 436), (470, 400), (522, 354)]
NOSE_PLATE = [(578, 340), (598, 362), (632, 418), (662, 432), (604, 434), (556, 430), (560, 380)]   # (its top edge runs under the horn's ring)
TOP_LIGHT = [(302, 205), (346, 218), (344, 225), (300, 212)]
TOP_LIGHT_SLOT = [(295, 200), (352, 214), (349, 230), (292, 217)]
REAR_JAW = [(212, 312), (345, 322), (348, 406), (300, 414), (226, 384)]
BRACKET = [(323, 352), (370, 356), (368, 396), (326, 394)]
BEAK = [(586, 424), (626, 420), (656, 426), (666, 446), (660, 474), (646, 500), (628, 522), (612, 538), (604, 520), (598, 494), (592, 466), (586, 444)]
JAW = [(440, 430), (500, 432), (560, 446), (596, 480), (592, 502), (540, 500), (470, 484), (440, 470)]
LIP = [(480, 438), (532, 440), (576, 458), (598, 500), (584, 506), (544, 492), (498, 472)]
MOUTH = [(530, 428), (614, 428), (618, 470), (606, 494), (580, 470), (540, 450)]
CROWN = [(418, 150), (340, 146), (265, 150), (215, 172), (186, 215), (173, 265), (177, 315), (198, 352)]
RIVETS = [(240, 214), (232, 296), (300, 290), (392, 252), (468, 282), (380, 346), (455, 382), (512, 418), (596, 380), (420, 424), (548, 352)]


def build_skull():
    Hd = "head"
    SKULL_OB[:] = [part(skull_core(), Hd)]
    beak_hw = lambda px, py: max(0.004, 0.016 - max(0.0, py - 450) * 0.00014)
    for s, sx in (("L", 1), ("R", -1)):
        panel("Temple." + s, TEMPLE, sx)
        panel("TopPlate." + s, TOP_PLATE, sx, thick=0.016)
        # (the brow juts out over the eye: a thick plate; the eye sits in a deep socket under it)
        panel("BrowPlate." + s, BROW, sx, thick=0.034)
        part(side_plate("EyeSocket." + s, SOCKET, sx, "dark", thick=0.004, base=0.001, bevel=0.0, outline=0.002, cuts=8), Hd)
        part(side_plate("Eye." + s, EYE, sx, "cyan", thick=0.006, base=0.002, bevel=0.0, outline=0.0, cuts=8), Hd)
        part(side_plate("EyeGlint." + s, inset(EYE, 8), sx, "eye", thick=0.007, base=0.002, bevel=0.0, outline=0.0, cuts=8), Hd)
        for k, (pts, th) in enumerate(CHEEKS):
            panel("Cheek%d.%s" % (k, s), pts, sx, "cream" if k < 4 else "cream_dark", thick=th)
        panel("SnoutPlate." + s, SNOUT, sx)
        panel("NosePlate." + s, NOSE_PLATE, sx, thick=0.01)
        part(side_plate("TopLightSlot." + s, TOP_LIGHT_SLOT, sx, "dark", thick=0.003, base=0.0225, bevel=0.0, outline=0.0), Hd)
        part(side_plate("TopLight." + s, TOP_LIGHT, sx, "cyan", thick=0.003, base=0.0245, bevel=0.0, outline=0.0), Hd)
        panel("RearJaw." + s, REAR_JAW, sx, "cream_dark")
        part(side_plate("Bracket." + s, BRACKET, sx, "gold", thick=0.012, base=0.009), Hd)
        for k, (px, py) in enumerate(RIVETS):
            part(ball("HeadRivet%d.%s" % (k, s), at_side(px, py, sx, 0.011), 0.0055, "cream_dark", seg=8, outline=0.0025), Hd)
        # The crown band: flat gold, round the back of the skull where the
        # frill meets it, with studs.
        band = [at_side(px, max(py, skull_sec(px)[1] + 10), sx, 0.006) for (px, py) in CROWN]
        part(ribbon("CrownBand." + s, band, sx, 0.024, 0.01), Hd)
        for k, i in enumerate((1, 3, 5, 7)):
            part(ball("CrownStud%d.%s" % (k, s), band[i] + Vector((sx * 0.008, 0, 0)), 0.007, "bronze", seg=10, outline=0.002), Hd)
        # Brow horns, traced: thick at the base on the brow, sweeping up and
        # forward, bending upward toward the tip (the lower edge concave). The
        # near one from (420, 236) to (712, 38); the far one from (500, 262)
        # to (790, 135) (the picture's near side is R).
        (b0, t0) = ((420, 236), (712, 38)) if sx < 0 else ((468, 250), (830, 150))
        xb, xt = 0.075, 0.17
        y0, z0 = HP(b0[0], b0[1], -xb if sx < 0 else xb)
        y1, z1 = HP(t0[0], t0[1], -xt if sx < 0 else xt)
        base, tip = Vector((xb * sx, y0, z0)), Vector((xt * sx, y1, z1))
        d = (tip - base).normalized()
        down = (Vector((0, 0, -1)) - d * d.z * -1).normalized()
        part(cone("BrowHorn." + s, base, tip, 0.044, "ivory", curve=0.09, side=tuple(down)), Hd)
        part(limb_loft("HornCollar." + s, base - d * 0.004, base + d * 0.012, [(0, 0, 0, 0.047, 0.047, 2), (1, 0, 0, 0.046, 0.046, 2)], "gold", front=(0, 0, 1), seg=32), Hd)
        # Ear: a gold fitting at the back of the jaw; the earring hangs from it.
        ec = at_side(268, 372, sx, 0.0)
        out = Vector((sx, 0, 0))
        part(limb_loft("EarFitting." + s, ec, ec + out * 0.034, [(0, 0, 0, 0.036, 0.036, 2), (1, 0, 0, 0.034, 0.034, 2)], "gold", front=(0, 0, 1)), Hd)
        part(torus("EarRim." + s, ec + out * 0.035, 0.026, 0.006, "bronze", normal=out, seg=24, outline=0.002), Hd)
        part(ball("EarBoss." + s, ec + out * 0.034, 0.017, "gold", scale=(0.6, 1, 1), seg=12, outline=0.002), Hd)
        part(ball("EarBolt." + s, ec + out * 0.045, 0.006, "bronze", seg=8, outline=0.0), Hd)
        a0 = ec + out * 0.022
        a1 = at_side(330, 372, sx, 0.02)
        part(limb("EarArm." + s, a0, a1, 0.011, 0.01, "gold", seg=10, outline=0.003), Hd)
        part(ball("EarArmEnd." + s, a1, 0.013, "gold", seg=10, outline=0.002), Hd)
        hang = ec + out * 0.03
        hx = -abs(hang.x)
        ring_c = Vector((hang.x, *HP(266, 456, hx)))
        part(torus("EarLink." + s, Vector((hang.x, *HP(268, 408, hx))), 0.012, 0.005, "gold", normal=(0, 1, 0), seg=12, outline=0.002), Hd)
        part(limb("EarPost." + s, Vector((hang.x, *HP(268, 395, hx))), Vector((hang.x, *HP(268, 422, hx))), 0.007, 0.007, "gold", seg=8, outline=0.002), Hd)
        part(torus("Earring." + s, ring_c, 0.033, 0.009, "gold", normal=out, seg=20, outline=0.003), Hd)
        part(ball("EarGem." + s, ring_c, 0.021, "cyan", scale=(0.6, 1, 1), outline=0.002), Hd)
        # The nostril: a dark slit on the beak's side.
        part(ball("Nostril." + s, at_side(604, 402, sx, 0.012), 0.022, "dark", scale=(0.4, 1.0, 0.5), seg=14, outline=0.0, rot=(0.45, 0, 0)), Hd)
    # The hooked beak, the lower jaw with its gold lip, the mouth between.
    beak = part(profile_solid("Beak", BEAK, beak_hw, "ivory", bevel=0.008), Hd)
    beak.modifiers["Bevel"].segments = 2
    jaw_hw = lambda px, py: max(0.02, skull_sec(min(px, 560))[3] * 0.8 - max(0.0, px - 540) * 0.0004)
    part(profile_solid("LowerJaw", JAW, jaw_hw, "cream_dark", bevel=0.004), Hd)
    part(profile_solid("Lip", LIP, lambda px, py: skull_sec(min(px, 560))[3] * 0.92 + 0.004, "gold", bevel=0.003), Hd)
    part(profile_solid("Mouth", MOUTH, lambda px, py: 0.042, "dark", bevel=0.0, outline=0.0), Hd)
    # The nose horn: short and thick on a cream socket, curving back a little.
    # (as painted: the back edge concave, the front almost straight - the horn
    # bows forward from a broad base and sweeps up to a tip pointing up)
    # The ring at its base, traced: as painted it's a thin gold line seen almost
    # edge-on, from (612, 362) to (676, 428) - its diameter, so its centre is the
    # horn's base and the horn grows out along its normal.
    r1, r2 = Vector((0, *HP(604, 366))), Vector((0, *HP(638, 416)))
    nb = (r1 + r2) / 2
    R = (r2 - r1).length / 2
    across = (r2 - r1).normalized()
    dn = Vector((0, across.z, -across.y))            # (perpendicular, in the side plane)
    if dn.z < 0:
        dn = -dn                                     # (pointing up, out of the snout)
    nb = nb + dn * 0.018       # (raised a little on its socket: the ring clear of the snout's ridge)
    nt = Vector((0, *HP(700, 277)))
    # The horn: from the ring (its radius) to the traced tip, leaving the ring along
    # its normal - so it bows forward and sweeps up (the back edge concave).
    c = nt - nb
    side = (dn - c.normalized() * dn.dot(c.normalized()))
    bend = math.atan2(side.length, dn.dot(c.normalized()))
    side = side.normalized() if side.length > 1e-6 else Vector((0, -1, 0))
    # (the horn fills the ring: the ring is the band round its base, as painted)
    part(cone("NoseHorn", nb, nt, R - 0.003, "ivory", curve=math.tan(bend) / math.pi, side=tuple(side)), Hd)
    part(torus("NoseRing", nb + dn * 0.003, R + 0.0005, 0.0055, "gold", normal=dn, seg=40, outline=0.003), Hd)
    part(limb_loft("NoseSocket", nb - dn * 0.045, nb - dn * 0.001, [(0, 0, 0, R * 1.02, R * 1.02, 2.4), (1, 0, 0, R * 0.97, R * 0.97, 2.4)], "cream", front=(0, -1, 0), outline=0.004), Hd)


def build_head():
    hz, hy = HEAD.z, HEAD.y
    N, Hd = "neck", "head"
    # Neck: a stacked spine column, ribbed hoses round it, one gold pipe.
    for k in range(5):
        z = NECK_Z - 0.03 + k * (hz - NECK_Z - 0.02) / 5
        part(limb_loft("NeckVert%d" % k, (0, hy * (k / 5), z), (0, hy * (k / 5), z + 0.026), [(0, 0, 0, 0.04, 0.04, 2.4), (1, 0, 0, 0.036, 0.036, 2.4)], "gunmetal"), N)
    for k, (dx, dy) in enumerate(((-0.06, 0.0), (0.06, 0.0), (-0.035, 0.045), (0.035, 0.045), (-0.04, -0.04), (0.04, -0.04))):
        # (as painted: grey segmented cables - steel bands on a dark core)
        part(tube("NeckHose%d" % k, [(dx, dy, NECK_Z - 0.05), (dx * 1.15, dy * 0.8 + hy * 0.5, (NECK_Z + hz) / 2 - 0.04), (dx * 0.8, dy * 0.5 + hy, hz - 0.08)], 0.017 if k % 2 else 0.012, "dark" if k % 2 else "steel", ribs=0.0 if k % 2 else 0.018), N)
    # Two neck pistons, grey, from the collar up under the jaw.
    for sx in (1, -1):
        p0 = Vector((0.085 * sx, -0.03, NECK_Z - 0.03))
        p1 = Vector((0.07 * sx, hy - 0.06, hz - 0.1))
        part(limb("NeckPistonCyl%d" % sx, p0, p0.lerp(p1, 0.6), 0.011, 0.011, "steel", seg=12, outline=0.003), N)
        part(limb("NeckPistonRod%d" % sx, p0.lerp(p1, 0.5), p1, 0.006, 0.006, "ball", seg=10, outline=0.002), N)
        for t in (0.15, 0.35):
            part(torus("NeckPistonBand%d_%d" % (sx, int(t * 100)), p0.lerp(p1, t), 0.012, 0.003, "dark", normal=p1 - p0, seg=14, outline=0.0), N)
    part(tube("NeckPipe", [(0.0, 0.07, NECK_Z - 0.04), (0.0, 0.06 + hy * 0.4, (NECK_Z + hz) / 2), (0.0, hy + 0.06, hz - 0.06)], 0.014, "gold", seg=8), N)
    build_skull()
    # The frill: nine painted plates fanning up behind the head (seams between),
    # a gold rim with round studs, a gold crown band where it meets the skull.
    fc = Vector((0, hy + 0.12, hz + 0.1))
    tilt = math.radians(22)
    rot = Matrix.Rotation(-math.pi / 2 - tilt, 3, "X")
    R = 0.32
    a0, a1, n = math.radians(-218), math.radians(38), 9   # (the plate's -y is up once tilted back)
    gap = math.radians(1.6)
    for k in range(n):
        s0 = a0 + (a1 - a0) * k / n + gap / 2
        s1 = a0 + (a1 - a0) * (k + 1) / n - gap / 2
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("UVMap")
        cols = 10
        rows = [0.0, 0.25, 0.5, 0.75, 1.0]
        grid = []
        for rr in rows:
            row = []
            for i in range(cols + 1):
                a = s0 + (s1 - s0) * i / cols
                r = 0.04 + (R - 0.04) * rr
                row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0.045 * rr * rr)))
            grid.append(row)
        for j in range(len(rows) - 1):
            for i in range(cols):
                f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
                for loop in f.loops:
                    p = loop.vert.co
                    loop[uvl].uv = (0.5 + p.x / (2 * R), 0.5 + p.y / (2 * R))
        bmesh.ops.transform(bm, matrix=Matrix.Translation(fc) @ rot.to_4x4(), verts=bm.verts)
        ob = mesh_object("FrillPlate%d" % k, bm, ["frill"], smooth=True, outline=0.005)
        th = ob.modifiers.new("Thick", "SOLIDIFY")
        th.thickness = 0.022
        ob.modifiers.move(len(ob.modifiers) - 1, 0)
        part(ob, Hd)
    rim_n = rot @ Vector((0, 0, 1))
    for k in range(n):
        s0 = a0 + (a1 - a0) * k / n
        s1 = a0 + (a1 - a0) * (k + 1) / n
        pts = [fc + rot @ Vector((R * math.cos(s0 + (s1 - s0) * i / 6), R * math.sin(s0 + (s1 - s0) * i / 6), 0.046)) for i in range(7)]
        part(tube("FrillRim%d" % k, pts, 0.019, "gold", seg=10, steps=2, outline=0.003), Hd)
    for k in range(14):
        a = a0 + (a1 - a0) * k / 13
        p = fc + rot @ Vector(((R + 0.005) * math.cos(a), (R + 0.005) * math.sin(a), 0.05))
        part(ball("FrillStud%d" % k, p, 0.031, "gold", outline=0.003), Hd)
        part(torus("FrillStudRim%d" % k, p - rim_n * 0.022, 0.02, 0.006, "bronze", normal=-rim_n, seg=14, outline=0.0), Hd)


def build_cape():
    """A red cape over the shoulders, hanging down the back to the knees (a
    rolled collar at the neck), folds deepening toward the hem."""
    def cape(u, v):
        a = math.radians(-100 + 200 * u)          # 0 = straight back (+Y); behind the shoulder pads
        z = 1.6 - v * 0.9
        r = 0.21 + 0.17 * min(1.0, v * 3.0) + 0.07 * v
        fold = (0.006 + 0.022 * v) * math.sin(a * 11 + v * 2)
        x = (r + fold) * math.sin(a)
        y = (r + fold) * math.cos(a) * 0.8 + 0.02
        if abs(a) > math.radians(80):
            z = max(z, 1.6 - 0.35)
        return Vector((x, y, z))
    part(sheet("Cape", cape, 64, 16, "cape", thick=0.012), "spine")
    part(torus("CapeCollar", (0, 0.02, 1.6), 0.19, 0.035, "red", normal=(0, 0.25, 1), seg=32), "spine")
    for sx in (1, -1):
        part(ball("CapeClasp%d" % sx, (0.17 * sx, -0.09, 1.585), 0.026, "gold", scale=(1, 0.6, 1), outline=0.003), "spine")
        part(ball("CapeClaspGem%d" % sx, (0.17 * sx, -0.105, 1.585), 0.012, "cyan", outline=0.002), "spine")


def build_rifle():
    """The laser rifle: origin at the pistol grip, -Y = the muzzle, +Z up.
    A gold receiver with two cyan glow panels, a gunmetal top cover and rail,
    a scope, a vented barrel shroud, a skeletal dark stock, pistol grip,
    trigger guard, magazine and fore-grip."""
    P = []
    P.append(loft("Receiver", [(0.06, 0, 0.07, 0.034, 0.05, 4), (-0.02, 0, 0.075, 0.037, 0.058, 4.5), (-0.24, 0, 0.075, 0.036, 0.056, 4.5), (-0.36, 0, 0.068, 0.03, 0.044, 4)], "gold", axis="y"))
    P.append(loft("TopCover", [(0.03, 0, 0.128, 0.026, 0.012, 3), (-0.3, 0, 0.125, 0.024, 0.012, 3)], "gunmetal", axis="y"))
    for sx in (1, -1):
        P.append(box("GlowPanel%d" % sx, (0.004, 0.13, 0.026), (0.037 * sx, -0.12, 0.08), "cyan", bevel=0.002, outline=0.002))
        P.append(box("GlowPanelB%d" % sx, (0.004, 0.05, 0.016), (0.035 * sx, -0.3, 0.075), "cyan", bevel=0.002, outline=0.002))
    P.append(box("Rail", (0.022, 0.2, 0.014), (0, -0.07, 0.143), "dark", bevel=0.003))
    for y in (-0.37, -0.45):
        P.append(torus("ShroudRing%d" % int(-y * 100), (0, y, 0.07), 0.034, 0.006, "gold", normal=(0, 1, 0), seg=16, outline=0.002))
    for sx in (1, -1):
        P.append(box("ReceiverLine%d" % sx, (0.003, 0.3, 0.004), (0.038 * sx, -0.14, 0.108), "dark", bevel=0.0, outline=0.0))
    P.append(limb_loft("Scope", (0, 0.0, 0.17), (0, -0.15, 0.17), [(0, 0, 0, 0.022, 0.022, 2), (0.15, 0, 0, 0.026, 0.026, 2), (0.85, 0, 0, 0.024, 0.024, 2), (1, 0, 0, 0.028, 0.028, 2)], "gunmetal", front=(0, 0, 1)))
    P.append(ball("ScopeLens", (0, -0.152, 0.17), 0.02, "cyan", scale=(1, 0.3, 1), outline=0.002))
    for y in (-0.03, -0.11):
        P.append(box("ScopeMount%d" % int(-y * 100), (0.018, 0.02, 0.03), (0, y, 0.152), "dark", bevel=0.003, outline=0.003))
    P.append(limb_loft("Shroud", (0, -0.35, 0.07), (0, -0.53, 0.07), [(0, 0, 0, 0.03, 0.034, 3), (1, 0, 0, 0.026, 0.03, 3)], "gunmetal", front=(0, 0, 1)))
    for k in range(3):
        P.append(box("Vent%d" % k, (0.062, 0.018, 0.01), (0, -0.39 - k * 0.04, 0.1), "dark", bevel=0.002, outline=0.0))
    P.append(limb("Barrel", (0, -0.52, 0.07), (0, -0.6, 0.07), 0.018, 0.018, "dark", seg=12))
    P.append(limb("Muzzle", (0, -0.58, 0.07), (0, -0.625, 0.07), 0.028, 0.026, "gold", seg=14))
    P.append(torus("MuzzleGlow", (0, -0.626, 0.07), 0.018, 0.006, "cyan", normal=(0, -1, 0), seg=14, outline=0.0))
    # Skeletal stock: a top bar (cyan strip), a lower strut, the butt plate.
    P.append(box("StockTop", (0.03, 0.24, 0.03), (0, 0.17, 0.1), "gunmetal", bevel=0.006))
    P.append(box("StockLight", (0.032, 0.12, 0.008), (0, 0.15, 0.112), "cyan", bevel=0.002, outline=0.002))
    P.append(box("StockStrut", (0.028, 0.24, 0.026), (0, 0.15, 0.02), "gunmetal", rot=(-0.28, 0, 0), bevel=0.006))
    P.append(box("ButtPlate", (0.04, 0.035, 0.15), (0, 0.29, 0.06), "dark", bevel=0.01))
    P.append(box("Grip", (0.04, 0.05, 0.12), (0, 0.01, -0.03), "gold", rot=(-0.32, 0, 0), bevel=0.012))
    P.append(torus("TriggerGuard", (0, -0.045, 0.0), 0.03, 0.006, "gunmetal", normal=(1, 0, 0), seg=16, outline=0.002))
    P.append(box("Trigger", (0.008, 0.01, 0.025), (0, -0.04, 0.0), "dark", bevel=0.002, outline=0.0))
    P.append(box("ForeGrip", (0.045, 0.12, 0.045), (0, -0.27, 0.005), "gunmetal", bevel=0.01))
    P.append(box("Mag", (0.045, 0.06, 0.1), (0, -0.1, -0.02), "dark", rot=(0.15, 0, 0), bevel=0.008))
    return P


# ---------------------------------------------------------------- the rig

BONES = [
    # name, head, tail, parent
    ("root", (0, 0, 0), (0, 0.25, 0), None),
    ("hips", (0, 0, HIP_Z), (0, 0, 1.12), "root"),
    ("spine", (0, 0, 1.12), (0, 0, NECK_Z - 0.04), "hips"),
    ("neck", (0, 0, NECK_Z - 0.04), (0, HEAD.y, HEAD.z - 0.08), "spine"),
    ("head", (0, HEAD.y, HEAD.z - 0.08), (0, HEAD.y - 0.2, HEAD.z), "neck"),
]
for _s, _sx in (("L", 1), ("R", -1)):
    _x = SHOULDER.x * _sx
    BONES += [
        ("upper_arm." + _s, (_x, 0, SHOULDER.z), (_x + 0.01 * _sx, 0.02, ELBOW_Z), "spine"),
        ("forearm." + _s, (_x + 0.01 * _sx, 0.02, ELBOW_Z), (_x + 0.01 * _sx, -0.01, WRIST_Z), "upper_arm." + _s),
        ("hand." + _s, (_x + 0.01 * _sx, -0.01, WRIST_Z), (_x + 0.01 * _sx, -0.01, WRIST_Z - 0.12), "forearm." + _s),
        ("thigh." + _s, (HIP_X * _sx, 0, HIP_Z + LIFT), (HIP_X * _sx, -0.02, KNEE_Z), "hips"),
        ("shin." + _s, (HIP_X * _sx, -0.02, KNEE_Z), (HIP_X * _sx, 0, ANKLE_Z), "thigh." + _s),
        ("foot." + _s, (HIP_X * _sx, 0, ANKLE_Z), (HIP_X * _sx, -0.18, ANKLE_Z), "root"),
    ]


def _empty(name, loc, parent=None, size=0.05, shape="SPHERE"):
    ob = _obj(name) or _link(name, None)
    ob.empty_display_type = shape
    ob.empty_display_size = size
    ob.parent = parent
    ob.location = loc
    return ob


def build_rig():
    root = _empty(ROOT, (0, 0, 0), size=0.4, shape="CIRCLE")
    root.rotation_mode = "XYZ"
    arm_data = bpy.data.armatures.new(RIG)
    arm = _link(RIG, arm_data)
    arm.parent = root
    arm.show_in_front = True
    arm_data.display_type = "STICK"
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, h, t, par in BONES:
        b = arm_data.edit_bones.new(name)
        up = 0.0 if name == "root" or name.split(".")[0] in ("thigh", "shin", "foot") else LIFT
        b.head, b.tail = Vector(h) + Vector((0, 0, up)), Vector(t) + Vector((0, 0, up))
        if name.startswith("thigh."):
            b.head.z = LEG_HIP
        if par:
            b.parent = eb[par]
            b.use_connect = False
        eb[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    # Controls: the feet (on the ground, the feet hang on them, flat), the
    # knees' and elbows' poles, the rifle.
    for s, sx in (("L", 1), ("R", -1)):
        _empty("FootIK." + s, (HIP_X * sx, 0, ANKLE_Z), root, 0.08, "CUBE")
        _empty("KneePole." + s, (HIP_X * sx, -0.8, KNEE_Z), root, 0.04)
        _empty("ElbowPole." + s, (0.6 * sx, 0.5, ELBOW_Z + LIFT), arm, 0.04)
    rc = _empty("RifleCtrl", (0, 0, 0), arm, 0.08, "ARROWS")
    rc.parent_type = "BONE"
    rc.parent_bone = "spine"
    rc.rotation_mode = "XYZ"
    return root, arm


def parent_to_bone(ob, arm, bone):
    mw = ob.matrix_world.copy()
    ob.parent = arm
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    ob.matrix_world = mw


def rig_parts(arm, rifle):
    for name, bone in PARTS.items():
        ob = _obj(name)
        if bone.startswith("foot."):
            # The feet hang on their IK controls (kept flat on the ground).
            mw = ob.matrix_world.copy()
            ob.parent = _obj("FootIK." + bone.split(".")[1])
            ob.matrix_world = mw
        else:
            parent_to_bone(ob, arm, bone)
    rc = _obj("RifleCtrl")
    for ob in rifle:
        mw = ob.matrix_world.copy()
        ob.parent = rc
        ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.matrix_basis = mw
    # Grip points on the rifle (rifle space: origin = the pistol grip).
    _empty("GripR", (0, 0.0, -0.02), rc, 0.03)
    _empty("ForeL", (0, -0.27, -0.03), rc, 0.03)
    # IK: legs to the feet, hands to the rifle.
    pb = arm.pose.bones
    for s in ("L", "R"):
        c = pb["shin." + s].constraints.new("IK")
        c.target = _obj("FootIK." + s)
        c.pole_target = _obj("KneePole." + s)
        c.chain_count = 2
        c = pb["forearm." + s].constraints.new("IK")
        c.target = _obj("GripR" if s == "R" else "ForeL")
        c.pole_target = _obj("ElbowPole." + s)
        c.chain_count = 2
        h = pb["hand." + s].constraints.new("COPY_ROTATION")
        h.target = rc
        h.mix_mode = "REPLACE"
        h.influence = 0.0     # (set per pose: the hands follow the rifle)
    for b in pb:
        b.rotation_mode = "XYZ"


def rifle_at(grip, fwd, up=(0, 0, 1)):
    """Puts the rifle (RifleCtrl) with its grip at `grip` (world, the
    character at rest facing -Y), the muzzle along fwd, its top toward up."""
    y = -Vector(fwd).normalized()
    z = Vector(up).normalized()
    x = y.cross(z).normalized()
    z = x.cross(y).normalized()
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(grip)
    rc = _obj("RifleCtrl")
    rc.matrix_world = _obj(ROOT).matrix_world @ m
    bpy.context.view_layer.update()


CARRY = dict(grip=(-0.12, -0.24, 1.12 + LIFT), fwd=(0.55, -0.75, -0.35), up=(0.3, 0.1, 1.0))


def best_poles(arm):
    """The IK pole angle that bends the knees forward and the elbows back and
    out (Blender's pole angle depends on the bone axes, so: tried in steps,
    with the limb forced to bend)."""
    pb = arm.pose.bones
    for s, sx in (("L", 1), ("R", -1)):
        ft = _obj("FootIK." + s)
        keep = ft.location.copy()
        ft.location.z += 0.2                       # (bend the knee)
        c = pb["shin." + s].constraints["IK"]
        best = max(range(-180, 180, 10), key=lambda d: _score(arm, c, d, "shin." + s, lambda p: -p.y - 2 * abs(p.x - HIP_X * sx)))
        c.pole_angle = math.radians(best)
        ft.location = keep
        c = pb["forearm." + s].constraints["IK"]
        best = max(range(-180, 180, 10), key=lambda d: _score(arm, c, d, "forearm." + s, lambda p: p.y + 0.5 * p.x * sx))
        c.pole_angle = math.radians(best)
    bpy.context.view_layer.update()


def _score(arm, c, deg, bone, fn):
    c.pole_angle = math.radians(deg)
    bpy.context.view_layer.update()
    return fn(arm.matrix_world @ arm.pose.bones[bone].head)


# ---------------------------------------------------------------- the stage

def stage():
    """The game's view: orthographic, 30 degrees above; lights fixed to the
    camera (the character turns, the light doesn't); 25 fps; transparent."""
    sc = bpy.context.scene
    sc.render.fps = 25
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.5, 0.5, 0.55, 1.0)
        bg.inputs["Strength"].default_value = 0.35
    coll = _coll()

    def light(name, kind, loc, energy, color, size=1.0):
        ld = bpy.data.lights.get(name) or bpy.data.lights.new(name, kind)
        ld.energy, ld.color = energy, color
        ld.use_shadow = False      # (cel shading: tones from the light's angle, no blocky shadow maps)
        if kind == "AREA":
            ld.size = size
        ob = _obj(name) or bpy.data.objects.new(name, ld)
        if ob.name not in coll.objects:
            coll.objects.link(ob)
        ob.location = loc
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat("-Z", "Y")
    light("AND_Key", "SUN", (-1.3, -3.0, 3.0), 3.2, (1.0, 0.96, 0.9))   # (near the camera: every facing mostly lit)
    light("AND_Fill", "SUN", (2.5, -1.0, 1.0), 0.6, (0.8, 0.85, 1.0))
    cd = bpy.data.cameras.get("SpriteCam") or bpy.data.cameras.new("SpriteCam")
    cd.type = "ORTHO"
    cd.ortho_scale = 3.0
    cam = _obj("SpriteCam") or bpy.data.objects.new("SpriteCam", cd)
    if cam.name not in coll.objects:
        coll.objects.link(cam)
    tgt = Vector((0, 0, 1.1))
    el = math.radians(30)
    cam.location = tgt + Vector((0, -math.cos(el), math.sin(el))) * 8
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 800
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"


def clear():
    c = bpy.data.collections.get(COLL)
    if c:
        for ob in list(c.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    for d in (bpy.data.meshes, bpy.data.armatures):
        for x in list(d):
            if x.users == 0:
                d.remove(x)
    for ob in list(bpy.context.scene.objects):
        if ob.name in ("Cube", "Light", "Camera"):
            bpy.data.objects.remove(ob, do_unlink=True)
    PARTS.clear()


def lift_body():
    """Everything above the legs up by LIFT (built at hip height HIP_Z)."""
    for name, bone in PARTS.items():
        if not (bone.startswith("thigh.") or bone.startswith("shin.") or bone.startswith("foot.")):
            _obj(name).location.z += LIFT


def build():
    clear()
    make_materials()
    build_legs()
    build_body()
    build_arms()
    build_head()
    build_cape()
    lift_body()
    rifle = build_rifle()
    root, arm = build_rig()
    rig_parts(arm, rifle)
    rifle_at(**CARRY)
    best_poles(arm)
    stage()
    return root, arm


def preview(out_dir, name="preview"):
    """Stills from the game's camera: facing S, SE, E, NE, N."""
    sc = bpy.context.scene
    root = _obj(ROOT)
    shots = {"s": 0.0, "se": math.pi / 4, "e": math.pi / 2, "ne": 3 * math.pi / 4, "n": math.pi}
    files = []
    for d, a in shots.items():
        root.rotation_euler = (0, 0, a)
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (name, d))
        bpy.ops.render.render(write_still=True)
        files.append(sc.render.filepath)
    root.rotation_euler = (0, 0, 0)
    return files


if __name__ == "__main__":
    build()
    import importlib.util
    spec = importlib.util.spec_from_file_location("android_anims", os.path.join(HERE, "android_anims.py"))
    if os.path.exists(spec.origin):
        anims = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(anims)
        anims.setup_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "android.blend"))
    preview(os.path.join(HERE, "previews"))
