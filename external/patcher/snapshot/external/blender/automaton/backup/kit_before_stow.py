"""The android kit: what the automaton (automaton.py) and the pirate android
(pirate.py) are built from, rigged with and rendered by.

  materials   cel shading (a toon ramp on a flat colour, an ink outline drawn
              as an inverted hull), glowing lights
  meshes      box / loft / tube / ball / plate - rigid armour parts, each
              parented to ONE bone (androids: no weight painting)
  the rig     build_rig(): an armature "Rig" under the empty "Root" (turned to
              face the 8 directions). The character faces -Y, its left is +X,
              feet on z = 0. Bones: pelvis, spine, chest, head, pauldron.L/R,
              upper.L/R, fore.L/R, hand.L/R, fingers.L/R, thigh.L/R, shin.L/R,
              foot.L/R, gun, + extra "tail" bones a skin may add (coat tails: chains
              of bones - chain(), skin_chains(), bent clear of the legs, a seat
              and the floor by drape_chain()).
  the solver  solve(pose) -> every bone's matrix from a pose of a few controls
              (pelvis, chest twist / lean, head, the hands' and feet's targets:
              analytic two-bone IK) - moves.py describes every animation as
              key poses of those controls; bake() keys them into actions. The
              pauldrons are slid clear of the chest (fit_pauldron).
  rendering   stage() (the game's view: orthographic, 30 degrees above, lights
              fixed to the camera), render_clip().

Run through build.py (blender -b --python build.py -- <skin> ...).
"""
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
COLL = "Android"
FPS = 30
DIRS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

# ---------------------------------------------------------------- the skeleton (m)
HIP_X = 0.105
HIP_Z = 0.99
THIGH = 0.45
SHIN = 0.43
ANKLE_Z = HIP_Z - THIGH - SHIN        # 0.11
FOOT = 0.24                            # ankle -> toe tip (forward)
PELVIS_Z = 0.97                        # the pelvis bone's head
SPINE_Z = 1.10
CHEST_Z = 1.26
NECK_Z = 1.60
HEAD_TOP = 1.90
SHOULDER = Vector((0.235, 0.0, 1.50))
UPPER = 0.30
FORE = 0.27
HAND = 0.10

M = {}
INK = 0.0          # (no ink outlines: the look is photoreal - was 1.6 for the old cel look; backup/kit_toon.py)


# ---------------------------------------------------------------- materials

def _new_mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return m, nt


def _lin(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def surface(name):
    """A part's metal and roughness by its material's name - the same rules as
    the game (Stage3D.surface_look): gold, bronze and guns polished metal,
    armour painted metal plates, joints rubber, cloth and leather matte."""
    n = name.lower()
    if any(k in n for k in ("bone", "hide", "wing", "skin", "crest")):
        return 0.0, 0.7                     # (bone, hide, membrane: matte)
    for k in ("gold", "bronze", "gun", "trim"):
        if k in n:
            return 0.9, 0.28
    if "armor" in n or "armour" in n or "horn" in n or "blade" in n:
        return 0.55, 0.32
    if "grey" in n or "red" in n or "navy" in n or "blue" in n:
        return 0.45, 0.38
    if "joint" in n or "cable" in n or "claw" in n or "boot" in n:
        return 0.2, 0.6
    if any(k in n for k in ("leather", "coat", "cape", "hat", "cloth", "quiver", "haft")):
        return 0.0, 0.75
    return 0.4, 0.45


def mat_toon(name, color, shade=0.62, hi=0.0, tint=(0.92, 0.9, 1.08)):
    """A part's material - physically based (Principled BSDF: the colour, its
    metal and roughness by name - surface()), as the game draws it. (The name
    stays from the old cel-shaded look; shade / hi / tint are unused now.)"""
    if isinstance(color, str):
        color = hexc(color)
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = (*_lin(color), 1)
    metal, rough = surface(name)
    bs.inputs["Metallic"].default_value = metal
    bs.inputs["Roughness"].default_value = rough
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*_lin(color), 1)      # (the viewport's solid colour too)
    m.metallic = metal
    m.roughness = rough
    return m


def mat_glow(name, color, strength=1.6):
    if isinstance(color, str):
        color = hexc(color)
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")   # (a lit part: dark glass, glowing)
    bs.inputs["Base Color"].default_value = (*_lin(color), 1)
    bs.inputs["Roughness"].default_value = 0.3
    bs.inputs["Emission Color"].default_value = (*_lin(color), 1)
    bs.inputs["Emission Strength"].default_value = strength * 2.0
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    m.diffuse_color = (*_lin(color), 1)
    return m


def mat_outline(name="KIT_Ink", color=(0.012, 0.008, 0.02)):
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True
    return m


# ---------------------------------------------------------------- mesh helpers

def coll():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.context.scene.collection.children.link(c)
    return c


def obj(name):
    return bpy.data.objects.get(name)


PARTS = []          # (object, bone name): parented by rig_parts()
_bone = [None]      # the bone the parts being made belong to


def bone(name):
    """Parts made from now on hang on this bone."""
    _bone[0] = name


def mesh_object(name, bm, mats, smooth=False, outline=0.007, bevel=0.0, auto=40.0):
    k = 2
    base = name
    while name in bpy.data.objects:
        name = "%s.%d" % (base, k)
        k += 1
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    for m in mats:
        me.materials.append(M[m])
    if bevel > 0:
        b = ob.modifiers.new("Bevel", "BEVEL")
        b.width, b.segments, b.limit_method = bevel, 2, "ANGLE"
        b.angle_limit = math.radians(35)
    outline *= INK
    if outline > 0:
        me.materials.append(M["ink"])
        s = ob.modifiers.new("Ink", "SOLIDIFY")
        s.thickness = -outline
        s.offset = -1.0
        s.use_flip_normals = True
        s.use_rim = False
        s.material_offset = len(me.materials) - 1
    PARTS.append((ob, _bone[0]))
    return ob


def rot(rx=0.0, ry=0.0, rz=0.0):
    """A rotation from degrees (XYZ)."""
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix()


def box(name, size, loc, mat="armor", r=None, taper=None, shear=None, bevel=0.012, outline=0.007):
    """A box (x, y, z) centred at loc. taper = (x, y) scale of the top face
    (or ((x, y) bottom, (x, y) top)); shear = (x, y) shift of the top; r: a
    rotation matrix (rot())."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        top = v.co.z > 0
        if taper:
            t = taper if not isinstance(taper[0], tuple) else taper[1 if top else 0]
            if top or isinstance(taper[0], tuple):
                v.co.x *= t[0]
                v.co.y *= t[1]
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if shear and top:
            v.co.x += shear[0]
            v.co.y += shear[1]
    m = Matrix.Translation(Vector(loc)) @ (r.to_4x4() if r is not None else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return mesh_object(name, bm, [mat], bevel=bevel, outline=outline)


def _se(a, b, n, seg):
    """A superellipse ring (half-sizes a along X, b along Y; n = 2 round .. 6 boxy)."""
    pts = []
    for i in range(seg):
        th = 2 * math.pi * i / seg
        c, s = math.cos(th), math.sin(th)
        pts.append((a * (abs(c) ** (2.0 / n)) * (1 if c >= 0 else -1), b * (abs(s) ** (2.0 / n)) * (1 if s >= 0 else -1)))
    return pts


def frame(y, hint):
    """A rotation whose Y axis is `y` and whose Z axis is `hint`, squared up to it."""
    y = Vector(y).normalized()
    z = Vector(hint) - y * Vector(hint).dot(y)
    if z.length < 1e-6:
        z = y.orthogonal()
    z.normalize()
    x = y.cross(z).normalized()
    return Matrix((x, y, z)).transposed()


def loft(name, p1, p2, secs, mat="armor", front=(0, -1, 0), seg=20, n=2.6, outline=0.007, smooth=True, cap=0.0):
    """A shape lofted from p1 to p2 through sections (t, a, b[, n[, dx, dy]]):
    at t (0..1 along the axis) a superellipse of half-width a (side to side)
    and half-depth b (front to back; +dy = toward `front`), shifted (dx, dy).
    cap: rounds the two ends (0..1)."""
    p1, p2 = Vector(p1), Vector(p2)
    fr = frame(p2 - p1, front)          # x = side, y = axis, z = front
    L = (p2 - p1).length
    bm = bmesh.new()
    rows = []
    secs = list(secs)
    if cap > 0:                           # (a smaller ring before / after: rounded ends)
        s0, s1 = secs[0], secs[-1]
        d = cap * min(s0[1], s0[2]) / L
        secs = [(s0[0] - d * 0.6, s0[1] * 0.55, s0[2] * 0.55) + tuple(s0[3:])] + secs
        d = cap * min(s1[1], s1[2]) / L
        secs = secs + [(s1[0] + d * 0.6, s1[1] * 0.55, s1[2] * 0.55) + tuple(s1[3:])]
    for s in secs:
        t, a, b = s[0], s[1], s[2]
        nn = s[3] if len(s) > 3 and s[3] else n
        dx = s[4] if len(s) > 4 else 0.0
        dy = s[5] if len(s) > 5 else 0.0
        row = []
        for (x, z) in _se(a, b, nn, seg):
            row.append(bm.verts.new(p1 + fr @ Vector((x + dx, t * L, z + dy))))
        rows.append(row)
    for k in range(len(rows) - 1):
        for i in range(seg):
            bm.faces.new((rows[k][i], rows[k][(i + 1) % seg], rows[k + 1][(i + 1) % seg], rows[k + 1][i]))
    bm.faces.new(rows[0][::-1])
    bm.faces.new(rows[-1])
    return mesh_object(name, bm, [mat], smooth=smooth, outline=outline)


def tube(name, p1, p2, r1, r2=None, mat="joint", seg=12, outline=0.006, smooth=True):
    r2 = r1 if r2 is None else r2
    return loft(name, p1, p2, [(0, r1, r1, 2), (1, r2, r2, 2)], mat=mat, seg=seg, outline=outline, smooth=smooth)


def ball(name, loc, r, mat="joint", scale=(1, 1, 1), seg=14, outline=0.006):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=r)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
    return mesh_object(name, bm, [mat], smooth=True, outline=outline)


def plate(name, pts, at, normal, up=(0, 0, 1), thick=0.012, mat="red", outline=0.004, bevel=0.0):
    """A flat panel: the polygon pts (2D: x across, y up, m) laid at `at`,
    facing `normal`, `thick` deep (sunk half into the surface)."""
    nrm = Vector(normal).normalized()
    fr = frame(nrm, up)                   # x = across, y = normal, z = up
    bm = bmesh.new()
    a = [bm.verts.new(Vector(at) + fr @ Vector((x, thick * 0.5, y))) for (x, y) in pts]
    b = [bm.verts.new(Vector(at) + fr @ Vector((x, -thick * 0.5, y))) for (x, y) in pts]
    bm.faces.new(a)
    bm.faces.new(b[::-1])
    k = len(pts)
    for i in range(k):
        bm.faces.new((a[i], b[i], b[(i + 1) % k], a[(i + 1) % k]))
    return mesh_object(name, bm, [mat], outline=outline, bevel=bevel)


def mirror(fn):
    """Calls fn(sx, suffix) for the left (+1, ".L") and the right (-1, ".R")."""
    fn(1.0, ".L")
    fn(-1.0, ".R")


# ---------------------------------------------------------------- the rig

# name: (parent, head, tail direction, the Z hint) - at rest: standing, arms down.
def _rest_bones(extra):
    S = SHOULDER
    b = {
        "pelvis": (None, (0, 0, PELVIS_Z), (0, 0, 1), (0, -1, 0), SPINE_Z - PELVIS_Z),
        "spine": ("pelvis", (0, 0, SPINE_Z), (0, 0, 1), (0, -1, 0), CHEST_Z - SPINE_Z),
        "chest": ("spine", (0, 0, CHEST_Z), (0, 0, 1), (0, -1, 0), NECK_Z - CHEST_Z),
        "head": ("chest", (0, 0, NECK_Z), (0, 0, 1), (0, -1, 0), HEAD_TOP - NECK_Z),
        "gun": (None, (0, -0.4, 1.2), (0, -1, 0), (0, 0, 1), 0.3),
    }
    for sx, sf in ((1.0, ".L"), (-1.0, ".R")):
        b["pauldron" + sf] = ("chest", (S.x * sx, S.y, S.z), (0, 0, -1), (0, -1, 0), 0.12)
        b["upper" + sf] = ("chest", (S.x * sx, S.y, S.z), (0, 0, -1), (0, -1, 0), UPPER)
        b["fore" + sf] = ("upper" + sf, (S.x * sx, S.y, S.z - UPPER), (0, 0, -1), (0, -1, 0), FORE)
        b["hand" + sf] = ("fore" + sf, (S.x * sx, S.y, S.z - UPPER - FORE), (0, 0, -1), (0, -1, 0), HAND * 0.55)
        b["fingers" + sf] = ("hand" + sf, (S.x * sx, S.y, S.z - UPPER - FORE - HAND * 0.55), (0, 0, -1), (0, -1, 0), HAND * 0.45)
        b["thigh" + sf] = ("pelvis", (HIP_X * sx, 0, HIP_Z), (0, 0, -1), (0, -1, 0), THIGH)
        b["shin" + sf] = ("thigh" + sf, (HIP_X * sx, 0, HIP_Z - THIGH), (0, 0, -1), (0, -1, 0), SHIN)
        b["foot" + sf] = ("shin" + sf, (HIP_X * sx, 0, ANKLE_Z), (0, -1, 0), (0, 0, 1), FOOT)
    b.update(extra or {})
    return b


REST = {}           # bone -> its rest matrix (armature space, 4x4)
PARENT = {}
EXTRA = {}          # a skin's extra bones (coat tails...): name -> (parent, head, dir, hint, length)


def build_rig(extra=None):
    EXTRA.clear()
    EXTRA.update(extra or {})
    bones = _rest_bones(extra)
    root = bpy.data.objects.new("Root", None)
    root.empty_display_size = 0.3
    coll().objects.link(root)
    ad = bpy.data.armatures.new("Rig")
    arm = bpy.data.objects.new("Rig", ad)
    coll().objects.link(arm)
    arm.parent = root
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (parent, head, d, hint, length) in bones.items():
        eb = ad.edit_bones.new(name)
        m = frame(d, hint).to_4x4()
        m.translation = Vector(head)
        eb.head = Vector(head)
        eb.tail = Vector(head) + Vector(d).normalized() * length
        eb.matrix = m
        eb.length = length
    for name, (parent, *_rest) in bones.items():
        if parent:
            ad.edit_bones[name].parent = ad.edit_bones[parent]
            ad.edit_bones[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    REST.clear()
    PARENT.clear()
    for b in ad.bones:
        REST[b.name] = b.matrix_local.copy()
        PARENT[b.name] = b.parent.name if b.parent else None
    ad.display_type = "STICK"
    arm.show_in_front = True
    return arm


def rig_parts():
    """Every part made so far onto its bone (rigid)."""
    arm = obj("Rig")
    for ob, bn in PARTS:
        if bn is None:
            ob.parent = obj("Root")
            continue
        ob.parent = arm
        ob.parent_type = "BONE"
        ob.parent_bone = bn
        b = arm.data.bones[bn]
        # (a bone parent's origin is the bone's TAIL)
        ob.matrix_parent_inverse = (b.matrix_local @ Matrix.Translation((0, b.length, 0))).inverted()
    PARTS.clear()


# ---------------------------------------------------------------- the main parts

# The few parts the model is made of in the end (merge_parts): each a mesh of its
# own, skinned to the bones it covers - the many rigid pieces it's built from
# joined into them. A skin's extra bones (the pirate's coat tails) go to "Coat".
REGIONS = {
    "Head": ["head"],
    "Torso": ["pelvis", "spine", "chest"],
    "Arm.L": ["pauldron.L", "upper.L", "fore.L", "hand.L", "fingers.L"],
    "Arm.R": ["pauldron.R", "upper.R", "fore.R", "hand.R", "fingers.R"],
    "Leg.L": ["thigh.L", "shin.L", "foot.L"],
    "Leg.R": ["thigh.R", "shin.R", "foot.R"],
    "Rifle": ["gun"],
}
INK_MAX = 0.007          # the thickest outline (m, before INK): the "ink" vertex group's weight 1


def merge_parts():
    """Joins every rigid part into the REGIONS' meshes: their bevels and
    thickness applied, each part's vertices held by its own bone (a vertex
    group: the mesh is skinned, an Armature modifier), its outline's thickness
    kept as the "ink" vertex group's weight - one Ink modifier (the inverted
    hull) for the whole part. The model looks as before; in Blender it's a
    handful of objects to select and edit."""
    arm = obj("Rig")
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    region_of = {}
    for reg, bones in REGIONS.items():
        for b in bones:
            region_of[b] = reg
    pieces = {}
    for ob in list(coll().objects):
        if ob.type != "MESH" or ob.parent != arm or ob.parent_type != "BONE":
            continue
        ink = ob.modifiers.get("Ink")
        thick = abs(ink.thickness) / INK if ink else 0.0
        if ink:
            ob.modifiers.remove(ink)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        me.transform(ob.matrix_world)
        if len(me.materials) and me.materials[-1] == M.get("ink"):
            me.materials.pop()                   # (the outline's slot: the region's Ink modifier has its own)
        t = bpy.data.objects.new(ob.name, me)
        coll().objects.link(t)
        t.vertex_groups.new(name=ob.parent_bone).add(list(range(len(me.vertices))), 1.0, "REPLACE")
        t.vertex_groups.new(name="ink").add(list(range(len(me.vertices))), min(1.0, thick / INK_MAX), "REPLACE")
        pieces.setdefault(region_of.get(ob.parent_bone, "Coat"), []).append(t)
        old = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if old.users == 0:
            bpy.data.meshes.remove(old)
    made = []
    for reg, obs in pieces.items():
        bpy.ops.object.select_all(action="DESELECT")
        for t in obs:
            t.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        part = bpy.context.view_layer.objects.active
        part.name = reg
        part.data.name = reg
        part.data.materials.append(M["ink"])
        part.parent = arm
        part.matrix_parent_inverse = arm.matrix_world.inverted()
        am = part.modifiers.new("Armature", "ARMATURE")
        am.object = arm
        s = part.modifiers.new("Ink", "SOLIDIFY")
        s.thickness = -INK_MAX * INK
        s.offset = -1.0
        s.use_flip_normals = True
        s.use_rim = False
        s.material_offset = len(part.data.materials) - 1
        s.vertex_group = "ink"
        s.thickness_vertex_group = 0.0
        made.append(part)
    skin_chains(made)
    _SAMPLES.clear()
    _PAD.clear()
    arm.data.pose_position = "POSE"
    bpy.ops.object.select_all(action="DESELECT")
    return made


# ---------------------------------------------------------------- the solver

def V(side, fwd, up):
    """A point given as (to the character's left, forward, up) -> Blender's."""
    return Vector((side, -fwd, up))


def _rz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def _rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def _ry(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def _m4(r, t):
    m = r.to_4x4()
    m.translation = t
    return m


def _two_bone(root, target, l1, l2, pole):
    """The middle joint (knee / elbow) of a two-bone chain from root to target,
    bent toward `pole` (a direction); the end is pulled in if out of reach."""
    d = target - root
    dist = d.length
    reach = (l1 + l2) * 0.999
    if dist > reach:
        d = d * (reach / dist)
        dist = reach
    if dist < abs(l1 - l2) + 1e-4:
        dist = abs(l1 - l2) + 1e-4
        d = d.normalized() * dist if d.length > 1e-6 else Vector((0, 0, -dist))
    end = root + d
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    p = Vector(pole) - n * Vector(pole).dot(n)
    if p.length < 1e-5:
        p = n.orthogonal()
    p.normalize()
    return root + n * a + p * h, end, p


DEFAULT = {
    # the pelvis: its shift from rest (left, forward, up; m) and turn (degrees: yaw to
    # its left, pitch forward, roll: its left hip up)
    "pelvis": (0.0, 0.0, 0.0), "pyaw": 0.0, "ppitch": 0.0, "proll": 0.0,
    # the chest against the pelvis: twist (to its left), lean (forward), bend (to the left)
    "twist": 0.0, "lean": 0.0, "bend": 0.0,
    # the head: yaw to its left against the ROOT (0: it looks where the character faces, however
    # the body's turned - as far as the neck goes; hfree 1: against the chest instead), pitch
    # (nodding down) and tilt (to its right) against the chest
    "hyaw": 0.0, "hpitch": 0.0, "htilt": 0.0, "hfree": 0.0,
    # hands: (space, (left, forward, up)) - space "c" the chest's (from the neck's
    # base; the pose turns with the chest), "w" the root's (the world: a target to hit)
    "handL": ("c", (0.27, 0.02, -0.66)), "handR": ("c", (-0.27, 0.02, -0.66)),
    # the elbows' side: a direction (same space as the hand)
    "elbowL": (0.25, -1.0, -0.35), "elbowR": (-0.25, -1.0, -0.35),
    # wrists: bend (degrees, toward the inside of the elbow) and the fingers' curl (0 open .. 1 fist)
    "wristL": 0.0, "wristR": 0.0, "gripL": 0.75, "gripR": 0.75,
    # feet: the ankle, (space, (left, forward, up)) - "w" the root's (on the ground:
    # up = 0), "p" the pelvis's (from the hip: a kick turns with the pelvis)
    "footL": ("w", (0.115, 0.0, 0.0)), "footR": ("w", (-0.115, 0.0, 0.0)),
    # the foot's turn out (degrees) and its pitch (toes down)
    "fyawL": 9.0, "fyawR": 9.0, "fpitchL": 0.0, "fpitchR": 0.0,
    # the knees' side: a direction (the foot's space)
    "kneeL": (0.12, 1.0, 0.0), "kneeR": (-0.12, 1.0, 0.0),
    # the rifle: None (not there), or (space, grip (left, fwd, up), muzzle direction, top direction, hands)
    #   hands: "both" / "right" (the left hand free)
    "gun": None,
    # lifted off the ground (m): taken off again when rendered (the game lifts the sprite)
    "air": 0.0,
    # in a seat: "" (not), "sit" (the game's chair), "stool" (its bar stool) - a skin's tail solver keeps
    # the cloth (a cape, coat tails: drape_chain) out of the seat's proxies (SEATS) and off the floor
    "seat": "",
}

# ---------------------------------------------------------------- cloth chains (coat tails)
# A long cloth panel (a coat's tail) hangs on a chain of bones - name, name.2, name.3 ... end to end, each under the
# same parent (not each other: one may be gathered alone) - its vertices skinned smoothly along it (skin_chains).
# drape_chain() bends the chain to hang the panel clear of the legs, the pelvis, a seat's proxies (SEATS) and the
# floor: segment by segment from the top, the turn of each (pitch / roll, the first also a yaw; the back one in a
# chair a little gathered) found by trying them out on points of the panel itself.

def chain(name, parent, head, lengths, d=(0, 0, -1), hint=(0, -1, 0)):
    """A cloth chain's bones (EXTRA_BONES entries): `lengths` segments from `head` along d."""
    out = {}
    h = Vector(head)
    for k, ln in enumerate(lengths):
        out[name if k == 0 else "%s.%d" % (name, k + 1)] = (parent, tuple(h), tuple(d), tuple(hint), ln)
        h = h + Vector(d).normalized() * ln
    return out


def chains():
    """{root: [its segments' bone names, from the top]} of the skin's extra bones."""
    out = {}
    for name in EXTRA:
        k = 2
        names = [name]
        while "%s.%d" % (name, k) in EXTRA:
            names.append("%s.%d" % (name, k))
            k += 1
        if len(names) > 1:
            out[name] = names
    return out


CHAIN_BLEND = 0.3        # (the blend round a joint of a chain: that share of the shorter segment, each side)


def chain_weights(s, lengths):
    """Each segment's weight for a point s (m) down a chain of `lengths`: smooth across the joints."""
    w = [0.0] * len(lengths)
    j = 0.0
    edges = []
    for ln in lengths[:-1]:
        j += ln
        edges.append(j)
    lo = 1.0
    for k, e in enumerate(edges):
        b = CHAIN_BLEND * min(lengths[k], lengths[k + 1])
        t = max(0.0, min(1.0, (s - (e - b)) / (2 * b)))
        t = t * t * (3 - 2 * t)                 # (0 above the joint's blend, 1 below it)
        w[k] = lo * (1.0 - t)
        lo *= t
    w[-1] = lo
    return w


def skin_chains(made):
    """The chains' cloth (made on its root bone) skinned along its segments, by each vertex's place at rest."""
    ch = chains()
    if not ch:
        return
    for part in made:
        _cut_chains(part, ch)
        for root, names in ch.items():
            g = part.vertex_groups.get(root)
            if g is None:
                continue
            groups = [part.vertex_groups.get(n) or part.vertex_groups.new(name=n) for n in names]
            head = REST[root].translation
            d = REST[root].to_3x3() @ Vector((0, 1, 0))
            lengths = [EXTRA[n][4] for n in names]
            mw = part.matrix_world
            hit = 0
            for v in part.data.vertices:
                if not any(gr.group == g.index and gr.weight > 0.5 for gr in v.groups):
                    continue
                hit += 1
                ws = chain_weights((mw @ v.co - head).dot(d), lengths)
                for gr, x in zip(groups, ws):
                    if x > 1e-4:
                        gr.add([v.index], x, "REPLACE")
                    else:
                        gr.remove([v.index])
            print("CHAIN %s: %d vertices along %d bones" % (root, hit, len(names)))


CHAIN_CUT = 0.045        # (m: the chains' cloth cut across this often, so it bends smoothly - and is tried out closely)


def _cut_chains(part, ch):
    """The part's cloth on the chains cut across (level cuts at rest: its shape kept)."""
    idx = set(part.vertex_groups[r].index for r in ch if part.vertex_groups.get(r))
    if not idx:
        return
    mw = part.matrix_world
    zs = [(mw @ v.co).z for v in part.data.vertices if any(g.group in idx and g.weight > 0.5 for g in v.groups)]
    if not zs:
        return
    bm = bmesh.new()
    bm.from_mesh(part.data)
    inv = mw.inverted()
    nrm = (mw.to_3x3().transposed() @ Vector((0, 0, 1))).normalized()
    z = max(zs) - CHAIN_CUT
    while z > min(zs):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=inv @ Vector((0, 0, z)),
                               plane_no=nrm)
        z -= CHAIN_CUT
    bm.to_mesh(part.data)
    bm.free()


CLOTH_PART = "Coat"                        # (the merged part the chains' cloth is in: its points are tried out)
CLOTH_CLEAR = 0.014                        # (m: how far the cloth's middle keeps off what it hangs over - half its thickness, a gap)
CLOTH_LEGS = (0.10, 0.09, 0.06)            # (the legs' proxies' radii: thigh, shin, foot - a skin with boots sets its own)
CLOTH_PELVIS = (0.075, 0.105)              # (... and the pelvis's: a capsule across the hips (half-length, radius))
_SAMPLES = {}


def _chain_samples(root, names):
    """Points of the chain's cloth at rest (armature space; a few hundred) and their weights on its segments."""
    import numpy as np
    key = (root, tuple(names))
    if key in _SAMPLES:
        return _SAMPLES[key]
    part = obj(CLOTH_PART)
    pts, ws = [], []
    if part is not None and part.type == "MESH":
        idx = {part.vertex_groups[n].index: k for k, n in enumerate(names) if part.vertex_groups.get(n)}
        mw = part.matrix_world
        for v in part.data.vertices:
            w = [0.0] * len(names)
            for gr in v.groups:
                if gr.group in idx:
                    w[idx[gr.group]] = gr.weight
            if sum(w) > 0.5:
                pts.append(tuple(mw @ v.co))
                ws.append([x / sum(w) for x in w])
    step = max(1, len(pts) // 1500)
    out = (np.array(pts[::step]).reshape(-1, 3), np.array(ws[::step]).reshape(-1, len(names)))
    _SAMPLES[key] = out
    return out


def cloth_proxies(P, mats):
    """What the cloth keeps off: capsules (a, b, r) - the legs, the pelvis - and boxes (lo, hi) - a seat's -
    and the floor (z = 0)."""
    caps = []
    rt, rs, rf = CLOTH_LEGS
    for sf in (".L", ".R"):
        hip, knee, ankle = mats["thigh" + sf].translation, mats["shin" + sf].translation, mats["foot" + sf].translation
        toe = ankle + mats["foot" + sf].to_3x3() @ Vector((0, FOOT * 0.8, 0))
        caps += [(hip, knee, rt), (knee, ankle, rs), (ankle, toe, rf)]
    pel = mats["pelvis"]
    hl, hr = CLOTH_PELVIS
    caps.append((pel @ Vector((hl, -0.01, 0.0)), pel @ Vector((-hl, -0.01, 0.0)), hr))
    boxes = list(SEATS.get(P.get("seat") or "", {}).values())
    return caps, boxes


def _cloth_cost(pts, caps, boxes, clear):
    """Sum over the points (..., 3) of the squared depth (m) they're inside the proxies grown by `clear`."""
    import numpy as np
    pen = np.zeros(pts.shape[:-1])
    for a, b, r in caps:
        a, b = np.array(a), np.array(b)
        ab = b - a
        t = np.clip(((pts - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
        d = np.linalg.norm(pts - (a + t[..., None] * ab), axis=-1) - r
        pen += np.maximum(0.0, clear - d) ** 2
    for lo, hi in boxes:
        lo, hi = np.array(lo), np.array(hi)
        c, h = (lo + hi) * 0.5, (hi - lo) * 0.5
        q = np.abs(pts - c) - h
        d = np.linalg.norm(np.maximum(q, 0.0), axis=-1) + np.minimum(q.max(axis=-1), 0.0)
        pen += np.maximum(0.0, clear - d) ** 2
    pen += np.maximum(0.0, clear - pts[..., 2]) ** 2
    return pen.sum(axis=-1)


def _turns(pitch, roll, yaw, side, fwd):
    import numpy as np
    out = []
    for p in pitch:
        for r in roll:
            for y in yaw:
                m = (Matrix.Rotation(math.radians(y), 3, "Z") @ Matrix.Rotation(math.radians(p), 3, -side)
                     @ Matrix.Rotation(math.radians(r), 3, -fwd))
                out.append(((p, r, y), np.array(m)))
    return out


def drape_chain(root, P, mats, head, prefs, side, fwd, reach=(90.0, 60.0, 0.0), gather=(1.0,), stiff=1.0, follow=0.0,
                stretch=(1.0,), down=None, sag=0.0, body=1.0):
    """A cloth chain's matrices {bone: matrix}: from `head`, each segment turned from its preferred rotation
    (prefs[k]: a 3x3 - or None: straight on from the segment above) as little as it can while its cloth keeps
    clear of cloth_proxies(). reach: how far it may turn (pitch, roll, and - the first segment only - yaw, degrees);
    gather: the widths each segment may be gathered to; stiff: how much a turn costs against a clash;
    follow: how much a bend from the segment above costs (so what can't hang down - on the floor - goes on its way);
    stretch: the lengths the lower segments may be gathered up to (cloth bunching on the floor);
    down, sag: a segment going straight on from the one above turns that share of the way to `down` (a 3x3: hanging
    straight) - the cloth sags; body: the share of the legs' and the pelvis's proxies' size (0: only the floor, the
    seat - lying down, the cloth lies with the body)."""
    import numpy as np
    names = chains()[root]
    caps, boxes = cloth_proxies(P, mats)
    caps = [(a, b, r * body) for a, b, r in caps if body > 0.0]
    key = (root, _rkey([head]), _rkey([c[0] for c in caps] + [c[1] for c in caps]),
           tuple(_rkey([m.col[i] for i in range(3)]) for m in prefs if m is not None), len(prefs), P.get("seat") or "",
           reach, gather, stiff, follow, stretch, round(sag, 3), round(body, 3),
           _rkey([down.col[i] for i in range(3)]) if down is not None else None)
    if key in _DRAPED:              # (a still pose - a seat's - the same frame after frame)
        return {n: m.copy() for n, m in _DRAPED[key].items()}
    sp, sw = _chain_samples(root, names)
    out = {}
    fixed = np.zeros_like(sp)          # (the points' share carried by the segments posed so far)
    h = Vector(head)
    prev = None
    for k, n in enumerate(names):
        pref = prefs[k] if k < len(prefs) and prefs[k] is not None else prev
        if (k >= len(prefs) or prefs[k] is None) and down is not None and sag > 0:
            pref = prev.to_quaternion().slerp(down.to_quaternion(), sag).to_matrix()
        pref_np = np.array(pref)
        rest = (sw[:, k:].sum(1) > 0.02) & (sw[:, :k + 1].sum(1) > 0.02)   # (the points this segment moves)
        cw = sw[rest, k:].sum(1)[:, None]          # (as the segments below go straight on with it)
        ri = np.array(REST[n].inverted())
        q = sp[rest] @ ri[:3, :3].T + ri[:3, 3]
        fx = fixed[rest]
        ln = EXTRA[n][4]
        hn = np.array(h)
        best = None
        gs = [(g, x) for g in gather for x in ((1.0,) if k == 0 else stretch)]
        for rnd in range(3):
            if rnd == 0:
                step = 10.0
                rng = [np.arange(-reach[i], reach[i] + 0.1, step) if reach[i] > 0 else np.array([0.0]) for i in range(3)]
            else:
                step = 10.0 / (3.0 ** rnd)
                c = best[1]
                rng = [np.array([c[i] - step, c[i], c[i] + step]) if reach[i] > 0 else np.array([0.0]) for i in range(3)]
            yaw = rng[2] if k == 0 else np.array([0.0])
            turns = _turns(rng[0], rng[1], yaw, side, fwd)
            for g, sy in gs:
                sc = np.diag([g, sy, g])
                R = np.array([t[1] @ pref_np for t in turns])                  # (n, 3, 3)
                if len(q):
                    pts = fx + cw * (np.einsum("nij,mj->nmi", R @ sc, q) + hn)
                    cost = 1e4 * _cloth_cost(pts, caps, boxes, CLOTH_CLEAR) / max(1, len(q)) * 90.0
                else:
                    cost = np.zeros(len(turns))
                ang = np.array([t[0] for t in turns])
                cost = cost + stiff * ((ang / 30.0) ** 2).sum(axis=1) + 6.0 * (1.0 - g) ** 2 + 3.0 * (1.0 - sy) ** 2
                if follow > 0 and prev is not None:
                    up_prev = np.array(prev.col[1])
                    bend = np.degrees(np.arccos(np.clip(R[:, :, 1] @ up_prev, -1.0, 1.0)))
                    cost = cost + follow * (bend / 30.0) ** 2
                i = int(np.argmin(cost))
                if best is None or cost[i] < best[0] - 1e-9:
                    best = (float(cost[i]), tuple(float(x) for x in turns[i][0]), Matrix(R[i].tolist()), g, sy)
        r = best[2]
        m = _m4(r, h) @ Matrix.Diagonal((best[3], best[4], best[3], 1.0))
        out[n] = m
        mm = np.array(m @ REST[n].inverted())
        fixed += sw[:, k:k + 1] * (sp @ mm[:3, :3].T + mm[:3, 3])
        prev = r
        h = h + r @ Vector((0, ln * best[4], 0))
    if len(_DRAPED) > 4000:
        _DRAPED.clear()
    _DRAPED[key] = {n: m.copy() for n, m in out.items()}
    return out


_DRAPED = {}


def _rkey(vs):
    return tuple(round(float(x), 4) for v in vs for x in v)


# The seats' collision proxies (the game's furniture - CosmosHangar._chair / _stool - round the root: the sitter's
# origin 0.02 m behind the seat's middle): boxes (min, max) in Blender's axes (x its left, -y forward, z up).
SEAT_Y = -0.02
SEATS = {
    "sit": {"seat": ((-0.24, SEAT_Y - 0.23, 0.28), (0.24, SEAT_Y + 0.23, 0.465)),          # (cushion, board, rail)
            "postL": ((0.175, SEAT_Y + 0.195, 0.43), (0.225, SEAT_Y + 0.275, 0.995)),       # (the back: two posts,
            "postR": ((-0.225, SEAT_Y + 0.195, 0.43), (-0.175, SEAT_Y + 0.275, 0.995)),     #  a padded panel,
            "panel": ((-0.212, SEAT_Y + 0.205, 0.565), (0.212, SEAT_Y + 0.265, 0.915)),     #  its top rail; open under
            "rail": ((-0.232, SEAT_Y + 0.22, 0.94), (0.232, SEAT_Y + 0.28, 0.995)),         #  the panel, between the posts)
            "legs": ((-0.226, SEAT_Y - 0.226, 0.0), (0.226, SEAT_Y + 0.226, 0.40))},
    "stool": {"seat": ((-0.20, SEAT_Y - 0.20, 0.74), (0.20, SEAT_Y + 0.20, 0.80)),          # (its round cushion, as a box)
              "column": ((-0.045, SEAT_Y - 0.045, 0.0), (0.045, SEAT_Y + 0.045, 0.74))},
}


def _space_point(space, p, mats):
    if space == "c":
        return mats["chest"] @ Vector((0, NECK_Z - CHEST_Z, 0)) + mats["chest"].to_3x3() @ _local(p)
    if space == "p":
        return mats["pelvis"].translation + mats["pelvis"].to_3x3() @ _local(p)
    return V(*p)


def _local(p):
    """(left, forward, up) in a spine bone's axes (x = left, y = up, z = forward)."""
    return Vector((p[0], p[2], p[1]))


def _space_dir(space, d, mats):
    if space == "c":
        return mats["chest"].to_3x3() @ _local(d)
    if space == "p":
        return mats["pelvis"].to_3x3() @ _local(d)
    return V(*d)


def solve(pose, extra=True):
    """Every bone's matrix (armature space) for a pose (DEFAULT's controls) - a skin's extra bones' (its cloth)
    too and the pauldrons fitted to the chest, unless `extra` is False (only where the limbs go is wanted)."""
    P = dict(DEFAULT)
    P.update(pose)
    mats = {}
    rest_r = frame((0, 0, 1), (0, -1, 0))          # the spine bones' rest rotation
    # The pelvis.
    pr = _rz(P["pyaw"]) @ rest_r @ _rx(P["ppitch"]) @ _rz(P["proll"])
    ppos = Vector((0, 0, PELVIS_Z)) + V(*P["pelvis"])
    mats["pelvis"] = _m4(pr, ppos)
    # Spine and chest: half the twist / lean / bend each.
    half = _ry(P["twist"] * 0.5) @ _rx(P["lean"] * 0.5) @ _rz(-P["bend"] * 0.5)
    sr = pr @ half
    spos = ppos + pr @ Vector((0, SPINE_Z - PELVIS_Z, 0))
    mats["spine"] = _m4(sr, spos)
    cr = sr @ half
    cpos = spos + sr @ Vector((0, CHEST_Z - SPINE_Z, 0))
    mats["chest"] = _m4(cr, cpos)
    hy = max(-85.0, min(85.0, P["hyaw"] - P["pyaw"] - P["twist"])) if P["hfree"] < 0.5 else P["hyaw"]
    hr = cr @ _ry(hy) @ _rx(P["hpitch"]) @ _rz(P["htilt"])
    mats["head"] = _m4(hr, cpos + cr @ Vector((0, NECK_Z - CHEST_Z, 0)))
    # The rifle.
    gun = P["gun"]
    grip_pts = {}
    if gun is not None:
        space, grip, fwd, top, hands = gun
        gp = _space_point(space, grip, mats)
        gr = frame(_space_dir(space, fwd, mats), _space_dir(space, top, mats))
        mats["gun"] = _m4(gr, gp)
        grip_pts["R"] = gp + gr @ Vector(GUN_HAND_R)
        if hands == "both":
            grip_pts["L"] = gp + gr @ Vector(GUN_HAND_L)
    else:
        mats["gun"] = _m4(frame((0, -1, 0), (0, 0, 1)), Vector((0, 0, -5.0)))   # (out of sight)
    # Arms.
    for sx, sf, s in ((1.0, ".L", "L"), (-1.0, ".R", "R")):
        sh = cpos + cr @ Vector((SHOULDER.x * sx, SHOULDER.z - CHEST_Z, -SHOULDER.y))
        space, p = P["hand" + s]
        tgt = grip_pts.get(s)
        if tgt is None:
            tgt = _space_point(space, p, mats)
        pole = _space_dir(space, P["elbow" + s], mats)
        elbow, wrist, pp = _two_bone(sh, tgt, UPPER, FORE, pole)
        ur = frame(elbow - sh, -pp)
        mats["upper" + sf] = _m4(ur, sh)
        fr_ = frame(wrist - elbow, -pp)
        mats["fore" + sf] = _m4(fr_, elbow)
        if s in grip_pts:        # (on the rifle: a fist round the grip)
            hr_ = fr_
            grip = 1.0
        else:
            hr_ = fr_ @ _rx(P["wrist" + s])
            grip = P["grip" + s]
        mats["hand" + sf] = _m4(hr_, wrist)
        mats["fingers" + sf] = _m4(hr_ @ _rz(-95.0 * grip * sx), wrist + hr_ @ Vector((0, HAND * 0.55, 0)))
        # The pauldron: between the chest and the upper arm.
        rest_p = cr @ rest_r.inverted() @ frame((0, 0, -1), (0, -1, 0))
        qa = rest_p.to_quaternion()
        qb = ur.to_quaternion()
        mats["pauldron" + sf] = _m4(qa.slerp(qb, 0.4).to_matrix(), sh)
        if extra:                # (kept clear of the chest)
            mats["pauldron" + sf] = fit_pauldron(sf, sx, mats["pauldron" + sf], mats["chest"])
    # Legs.
    for sx, sf, s in ((1.0, ".L", "L"), (-1.0, ".R", "R")):
        hip = ppos + pr @ Vector((HIP_X * sx, HIP_Z - PELVIS_Z, 0))
        space, p = P["foot" + s]
        if space == "w":
            ankle = V(p[0], p[1], p[2] + ANKLE_Z)
            base = Matrix.Identity(3)
        else:
            ankle = hip + pr @ _local(p)
            base = pr @ rest_r.inverted()
        pole = _space_dir("p" if space == "p" else "w", P["knee" + s], mats)
        if space == "w":       # (the knee follows the foot's turn and half the pelvis's)
            pole = _rz(P["fyaw" + s] * sx * 0.7 + P["pyaw"] * 0.5) @ pole
        knee, ankle, pp = _two_bone(hip, ankle, THIGH, SHIN, pole)
        mats["thigh" + sf] = _m4(frame(knee - hip, pp), hip)
        mats["shin" + sf] = _m4(frame(ankle - knee, pp), knee)
        fr2 = base @ _rz(P["fyaw" + s] * sx) @ _rx(P["fpitch" + s]) @ frame((0, -1, 0), (0, 0, 1))
        mats["foot" + sf] = _m4(fr2, ankle)
    # A skin's extra bones.
    for name in (EXTRA if extra else ()):
        if name not in mats:          # (a tail solver may pose a whole chain at its root)
            mats[name] = TAIL_SOLVER[0](name, P, mats) if TAIL_SOLVER[0] else mats[EXTRA[name][0]] @ (REST[EXTRA[name][0]].inverted() @ REST[name])
    if P["air"]:
        for k in mats:
            mats[k] = Matrix.Translation((0, 0, P["air"])) @ mats[k]
    return mats


# ---------------------------------------------------------------- the pauldrons' fit
# A pauldron turns with the arm (part of the way) about the shoulder: turned, its inner end could sink into the
# chest's side. fit_pauldron() slides it out along the chest's side axis just as far as it takes to keep it clear
# of the chest's rigid parts (both ways: none of its points in them, none of theirs in it) - tried out on the
# merged parts themselves (Torso, Arm.L / Arm.R; their rest shapes), when there are any.

PAD_CLEAR = 0.004            # (m: the gap kept)
_PAD = {}


def _islands(me, keep_vert):
    """The mesh's loose parts whose vertices all pass keep_vert(index): (vertex indices, polygons)."""
    import numpy as np
    n = len(me.vertices)
    parent = np.arange(n)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    roots = np.array([find(i) for i in range(n)])
    out = {}
    for i in range(n):
        out.setdefault(roots[i], []).append(i)
    polys = {}
    for p in me.polygons:
        polys.setdefault(roots[p.vertices[0]], []).append(p)
    res = []
    for r, vs in out.items():
        if all(keep_vert(i) for i in vs) and r in polys:
            res.append((vs, polys[r]))
    return res


def _solids(me, isl, co):
    """BVH trees of islands (a list of (vertices, polygons)), with their bounding boxes."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    out = []
    for vs, ps in isl:
        pts = co[vs]
        out.append((pts.min(0), pts.max(0), BVHTree.FromPolygons([tuple(c) for c in co], [tuple(p.vertices) for p in ps])))
    return out


def _depth(solids, pts):
    """The deepest any of the points (n, 3) is inside any of the solids (m)."""
    import numpy as np
    best = 0.0
    for lo, hi, tree in solids:
        inb = np.where(((pts > lo) & (pts < hi)).all(1))[0]
        for i in inb:
            v = Vector(pts[i])
            loc, nrm, _k, dist = tree.find_nearest(v)
            if loc is not None and (v - loc).dot(nrm) < 0 and dist > best:
                best = dist
    return best


def _pad_data(sf):
    import numpy as np
    if sf in _PAD:
        return _PAD[sf]
    torso, part = obj("Torso"), obj("Arm" + sf)
    data = None
    if torso is not None and part is not None and torso.type == "MESH" and part.type == "MESH" and part.vertex_groups.get("pauldron" + sf):
        def co_of(ob):
            a = np.zeros(len(ob.data.vertices) * 3)
            ob.data.vertices.foreach_get("co", a)
            a = a.reshape(-1, 3)
            mw = np.array(ob.matrix_world)
            return a @ mw[:3, :3].T + mw[:3, 3]

        def weight(ob, name):
            g = ob.vertex_groups.get(name)
            w = np.zeros(len(ob.data.vertices))
            if g is None:
                return w
            for v in ob.data.vertices:
                for gr in v.groups:
                    if gr.group == g.index:
                        w[v.index] = gr.weight
            return w
        pco, tco = co_of(part), co_of(torso)
        pw = weight(part, "pauldron" + sf)
        cw = weight(torso, "chest")
        pad_isl = _islands(part.data, lambda i: pw[i] > 0.99)
        cloth = set(k for k, m in enumerate(torso.data.materials) if m and any(w in m.name.lower() for w in ("coat", "cloth", "cape")))
        chest_isl = _islands(torso.data, lambda i: cw[i] > 0.99)
        hard, soft = [], []
        for vs, ps in chest_isl:
            (soft if ps[0].material_index in cloth else hard).append((vs, ps))
        if soft:           # (what's laid on the cloth - studs, piping - goes with it: a pauldron sits over a coat)
            from mathutils.bvhtree import BVHTree
            vs_all = sorted(set(v for vs, _ps in soft for v in vs))
            ct = BVHTree.FromPolygons([tuple(c) for c in tco], [tuple(p.vertices) for _vs, ps in soft for p in ps])
            keep = []
            for vs, ps in hard:
                c = tco[vs].mean(0)
                loc, _n, _i, dist = ct.find_nearest(Vector(c))
                if loc is None or dist > 0.025:
                    keep.append((vs, ps))
            hard = keep
        pv = np.array(sorted(set(v for vs, _ps in pad_isl for v in vs)))
        if len(pv) and hard:
            lo, hi = pco[pv].min(0) - 0.06, pco[pv].max(0) + 0.06
            hv = np.array(sorted(set(v for vs, _ps in hard for v in vs)))
            near = hv[((tco[hv] > lo) & (tco[hv] < hi)).all(1)]
            data = {"pad_pts": pco[pv], "pad": _solids(part.data, pad_isl, pco),
                    "chest_pts": tco[near], "chest": [s for s in _solids(torso.data, hard, tco)
                                                      if (s[1] > lo).all() and (s[0] < hi).all()]}
    _PAD[sf] = data
    return data


def fit_pauldron(sf, sx, m, chest):
    """The pauldron's matrix m slid out along the chest's side axis till it's clear of the chest (PAD_CLEAR)."""
    import numpy as np
    d = _pad_data(sf)
    if d is None:
        return m
    to_chest = REST["chest"] @ chest.inverted()           # (posed -> the chest's rest place)
    rp = REST["pauldron" + sf]
    lat = Vector((sx, 0.0, 0.0))
    shift = 0.0
    for _it in range(5):
        x = Matrix.Translation(lat * shift) @ to_chest @ m @ rp.inverted()     # (the pad's rest shape -> the chest's rest place)
        xa = np.array(x)
        pp = d["pad_pts"] @ xa[:3, :3].T + xa[:3, 3]
        xi = np.array(x.inverted())
        cp = d["chest_pts"] @ xi[:3, :3].T + xi[:3, 3]
        dep = max(_depth(d["chest"], pp), _depth(d["pad"], cp))
        if dep <= 1e-5:
            break
        shift += dep + PAD_CLEAR
    if shift == 0.0:
        return m
    return chest @ REST["chest"].inverted() @ Matrix.Translation(lat * shift) @ to_chest @ m


GUN_HAND_R = (0.0, 0.0, 0.0)       # the grip (the gun bone's head), bone axes: y = muzzle, z = top
GUN_HAND_L = (0.0, 0.30, 0.0)      # the fore-grip
TAIL_SOLVER = [None]


def apply(mats, arm=None):
    """Poses the armature from solve()'s matrices."""
    arm = arm or obj("Rig")
    for pb in arm.pose.bones:       # (parents come first)
        name = pb.name
        par = PARENT[name]
        if par:
            basis = (REST[par].inverted() @ REST[name]).inverted() @ mats[par].inverted() @ mats[name]
        else:
            basis = REST[name].inverted() @ mats[name]
        loc, q, sc = basis.decompose()
        pb.location = loc
        pb.rotation_quaternion = q
        if name in EXTRA:          # (a skin's cloth may be gathered up - shorter, narrower - in a seat: tail solvers)
            pb.scale = sc


# ---------------------------------------------------------------- key poses -> frames

def _ease(kind, t):
    if kind == "l":
        return t
    if kind == "i":       # slow, then fast (winding up into a strike)
        return t * t
    if kind == "o":       # fast, then slow
        return 1 - (1 - t) * (1 - t)
    if kind == "snap":    # nearly there at once
        return 1 - (1 - t) ** 3
    return t * t * (3 - 2 * t)


def _lerp(a, b, t):
    if a is None or b is None:
        return b if t >= 0.5 else a
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    if isinstance(a, str):
        return b if t >= 0.5 else a
    if isinstance(a, (tuple, list)):
        if len(a) and isinstance(a[0], str):       # (space, point...)
            if a[0] != b[0]:
                return b if t >= 0.5 else a
            return (a[0],) + tuple(_lerp(x, y, t) for x, y in zip(a[1:], b[1:]))
        return tuple(_lerp(x, y, t) for x, y in zip(a, b))
    return b


def _to_world(pose, key):
    """A hand / foot target of a full pose, as a root-space one."""
    mats = solve(pose, extra=False)
    s = key[-1]
    sf = "." + s
    if key.startswith("hand"):
        w = mats["hand" + sf].translation
        return ("w", (w.x, -w.y, w.z))
    w = mats["foot" + sf].translation
    return ("w", (w.x, -w.y, w.z - ANKLE_Z))


def full(pose):
    P = dict(DEFAULT)
    P.update(pose)
    return P


def blend(a, b, t):
    """Between two full poses; targets given in different spaces meet in the root's."""
    out = {}
    for k in a:
        x, y = a[k], b[k]
        if k[:4] in ("hand", "foot") and x[0] != y[0]:
            x, y = _to_world(a, k), _to_world(b, k)
        out[k] = _lerp(x, y, t)
    return out


def frames_of(keys):
    """keys: [(frame, pose[, ease])...] -> a full pose per frame, frame 0 .. the last."""
    keys = [(k[0], full(k[1]), k[2] if len(k) > 2 else "io") for k in keys]
    out = []
    for i in range(len(keys) - 1):
        f0, p0, _e = keys[i]
        f1, p1, e1 = keys[i + 1]
        for f in range(f0, f1):
            out.append(blend(p0, p1, _ease(e1, (f - f0) / float(f1 - f0))))
    out.append(keys[-1][1])
    return out


def bake(name, poses):
    """Keys a list of full poses into the action `name` (frame 1...)."""
    arm = obj("Rig")
    ad = arm.animation_data or arm.animation_data_create()
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    for i, pose in enumerate(poses):
        apply(solve(pose), arm)
        for pb in arm.pose.bones:
            pb.keyframe_insert("location", frame=i + 1)
            pb.keyframe_insert("rotation_quaternion", frame=i + 1)
            if pb.name in EXTRA:
                pb.keyframe_insert("scale", frame=i + 1)
    curves = list(getattr(act, "fcurves", []) or [])
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves += list(bag.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    act["frames"] = len(poses)
    return act


# ---------------------------------------------------------------- the stage

PX_PER_M = 100.0       # the sprites' scale: the automaton (1.9 m) about 190 px tall
RES = 380
ORTHO = RES / PX_PER_M  # m across the picture
ELEVATION = 22.0       # the camera above the horizon (degrees)


def stage(res=RES, ortho=None):
    sc = bpy.context.scene
    sc.render.fps = FPS
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.42, 0.46, 0.55, 1.0)
        bg.inputs["Strength"].default_value = 0.6     # (a sky to light and reflect in: the parts are physically based)

    def light(name, loc, energy, color):
        ld = bpy.data.lights.get(name) or bpy.data.lights.new(name, "SUN")
        ld.energy, ld.color = energy, color
        ld.use_shadow = False
        ob = obj(name) or bpy.data.objects.new(name, ld)
        if ob.name not in coll().objects:
            coll().objects.link(ob)
        ob.location = loc
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat("-Z", "Y")
    light("KIT_Key", (-3.4, -2.4, 4.2), 3.5, (1.0, 0.96, 0.9))     # (a sun, a cool fill from the other side, a rim behind)
    light("KIT_Fill2", (3.5, -1.5, 1.5), 0.8, (0.7, 0.8, 1.0))
    light("KIT_Rim", (0.5, 4.0, 3.0), 1.5, (1.0, 1.0, 1.0))
    fill = obj("KIT_Fill")
    if fill:
        bpy.data.objects.remove(fill, do_unlink=True)
    cd = bpy.data.cameras.get("SpriteCam") or bpy.data.cameras.new("SpriteCam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho or ORTHO
    cam = obj("SpriteCam") or bpy.data.objects.new("SpriteCam", cd)
    if cam.name not in coll().objects:
        coll().objects.link(cam)
    tgt = Vector((0, 0, 0.95))
    el = math.radians(ELEVATION)
    cam.location = tgt + Vector((0, -math.cos(el), math.sin(el))) * 9
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.compression = 15
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "None"
    try:
        sc.eevee.taa_render_samples = 16
    except Exception:
        pass
    sc.render.filter_size = 1.0


def facing_angle(d):
    """Root's Z rotation to face screen direction d (e = right, s = toward the camera)."""
    return math.pi / 2 - DIRS.index(d) * math.pi / 4


def ground_px():
    """Where the root (the point the character stands on) is in the picture (px, y down)."""
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    uv = world_to_camera_view(sc, sc.camera, Vector((0, 0, 0)))
    return [uv.x * sc.render.resolution_x, (1.0 - uv.y) * sc.render.resolution_y]


def px_per_m():
    return bpy.context.scene.render.resolution_x / ORTHO


def render_poses(poses, out_dir, name, dirs=DIRS):
    """Renders a list of full poses from the given directions:
    out_dir/<name>_<dir>_<frame %03d>.png (air taken off: the sprite stands on the ground)."""
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    root, arm = obj("Root"), obj("Rig")
    if arm.animation_data:
        arm.animation_data.action = None
    for i, pose in enumerate(poses):
        p = dict(pose)
        p["air"] = 0.0
        apply(solve(p), arm)
        for d in dirs:
            root.rotation_euler = (0, 0, facing_angle(d))
            sc.render.filepath = os.path.join(out_dir, "%s_%s_%03d.png" % (name, d, i))
            bpy.ops.render.render(write_still=True)
    root.rotation_euler = (0, 0, 0)


# ---------------------------------------------------------------- decals

DECALS = []


def decal(name, pts, at, normal, target, mat="red", up=(0, 0, 1), offset=0.004, thick=0.008, outline=0.0035, cuts=3):
    """A coloured panel laid ON a part: the polygon pts (x across, y up; m)
    held over `at` (a point about on the surface) facing `normal`, pressed
    onto the part `target` along the normal (baked by bake_decals()), `thick`
    proud of it."""
    at = Vector(at) + Vector(normal).normalized() * 0.12
    fr = frame(Vector(normal).normalized(), up)          # x across, y = normal, z up
    bm = bmesh.new()
    vs = [bm.verts.new(Vector((x, 0.0, y))) for (x, y) in pts]
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f])
    for _i in range(cuts):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    ob = mesh_object(name, bm, [mat], outline=0.0)
    m = fr.to_4x4()
    m.translation = Vector(at)
    ob.matrix_world = m
    sw = ob.modifiers.new("Wrap", "SHRINKWRAP")
    sw.target = target
    sw.wrap_method = "PROJECT"
    sw.use_project_x = sw.use_project_z = False
    sw.use_project_y = True
    sw.use_negative_direction = True
    sw.use_positive_direction = True
    sw.offset = offset
    DECALS.append((ob, thick, outline))
    return ob


def bake_decals():
    """Presses the decals onto their parts for good (run before rig_parts())."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for ob, thick, outline in DECALS:
        ev = ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        # (corners that missed the part stay where they were: cut them off)
        missed = [i for i, v in enumerate(me.vertices) if (v.co - ob.data.vertices[i].co).length < 1e-6]
        if missed:
            bm = bmesh.new()
            bm.from_mesh(me)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.verts[i] for i in missed], context="VERTS")
            bm.to_mesh(me)
            bm.free()
        me.transform(ob.matrix_world)
        old = ob.data
        ob.modifiers.clear()
        ob.data = me
        bpy.data.meshes.remove(old)
        ob.matrix_world = Matrix.Identity(4)
        for p in me.polygons:
            p.use_smooth = True
        s = ob.modifiers.new("Thick", "SOLIDIFY")
        s.thickness = thick
        s.offset = 0.0
        if outline > 0 and INK > 0:
            me.materials.append(M["ink"])
            k = ob.modifiers.new("Ink", "SOLIDIFY")
            k.thickness = -outline * INK
            k.offset = -1.0
            k.use_flip_normals = True
            k.use_rim = False
            k.material_offset = len(me.materials) - 1
    DECALS.clear()


def clear():
    c = bpy.data.collections.get(COLL)
    if c:
        for ob in list(c.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    for ob in list(bpy.data.objects):
        if ob.name in ("Cube", "Light", "Camera"):
            bpy.data.objects.remove(ob, do_unlink=True)
    PARTS.clear()
    DECALS.clear()


def preview(path, poses_dirs, res=420, bg=(0.2, 0.22, 0.3, 1.0), ortho=None, cols=0, crop=0.0):
    """A contact sheet: poses_dirs = [(full pose, dir)...] side by side."""
    import numpy as np
    sc = bpy.context.scene
    stage(res, ortho)
    arm = obj("Rig")
    if arm.animation_data:                 # (the poses set by hand: no action over them)
        arm.animation_data.action = None
    tiles = []
    tmp = os.path.join(bpy.app.tempdir, "kit_prev.png")
    for pose, d in poses_dirs:
        p = dict(full(pose))
        apply(solve(p))
        obj("Root").rotation_euler = (0, 0, facing_angle(d))
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        a = np.array(img.pixels[:], dtype=np.float32).reshape(res, res, 4)[::-1]
        if crop:
            c = int(res * crop)
            a = a[:, c:res - c]
        bpy.data.images.remove(img)
        tiles.append(a)
    obj("Root").rotation_euler = (0, 0, 0)
    if cols and len(tiles) > cols:
        while len(tiles) % cols:
            tiles.append(np.zeros_like(tiles[0]))
        sheet = np.concatenate([np.concatenate(tiles[i:i + cols], axis=1) for i in range(0, len(tiles), cols)], axis=0)
    else:
        sheet = np.concatenate(tiles, axis=1)
    rgb = sheet[:, :, :3] * sheet[:, :, 3:4] + np.array(bg[:3], dtype=np.float32) * (1 - sheet[:, :, 3:4])
    out = np.concatenate([rgb, np.ones_like(sheet[:, :, 3:4])], axis=2)[::-1]
    im = bpy.data.images.new("kit_sheet", sheet.shape[1], sheet.shape[0], alpha=False)
    im.pixels = out.ravel().tolist()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
