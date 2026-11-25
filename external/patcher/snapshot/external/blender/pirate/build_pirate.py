"""Builds the pirate android (the NPC of art/pirate/, references in
external/images/npc_pirate_*.png) in the open Blender, from scratch.

Run inside Blender (MCP execute, or `blender -b --python build_pirate.py`).
Everything goes in the collection "Pirate", under the empty "PirateRoot".
Every body part is its own rigid object (an android: later each part is
parented to one bone - no weight painting), named <part>.L / <part>.R.
Facing -Y, feet on z = 0, about 1.95 m tall with the hat; the right hand
(-X) holds the rifle, barrel down. Materials are procedural (PIR_*): rusty
bronze armour, dark metal joints, crimson tattered cloth, leather, gold
trim, bone skulls, glowing green / yellow cells and red eyes.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

COLL = "Pirate"
ROOT = "PirateRoot"
rng = random.Random(7)


# ---------------------------------------------------------------- materials

def _principled(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (600, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m, nt, bsdf


def _ramp(nt, stops, loc):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.location = loc
    els = r.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1.0)
    for p, c in stops[1:]:
        e = els.new(p)
        e.color = (*c, 1.0)
    return r


def mat_worn(name, colors, metallic, rough, scale=6.0, pits=0.0, bump=0.25, sheen=0.0):
    """A noisy, worn surface: noise -> colour ramp; pits (voronoi dots) push
    to the darkest colour; rust (the bright end) is rougher and less metallic."""
    m, nt, bsdf = _principled(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tc.location = (-1100, 0)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.location = (-900, 100)
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.62
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    fac = noise.outputs["Fac"]
    if pits > 0:
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.location = (-900, -200)
        vor.inputs["Scale"].default_value = scale * 5
        nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
        mask = nt.nodes.new("ShaderNodeMapRange")
        mask.location = (-700, -200)
        mask.inputs["From Min"].default_value = 0.0
        mask.inputs["From Max"].default_value = pits
        nt.links.new(vor.outputs["Distance"], mask.inputs["Value"])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.location = (-500, 0)
        nt.links.new(fac, mul.inputs[0])
        nt.links.new(mask.outputs["Result"], mul.inputs[1])
        fac = mul.outputs["Value"]
    col = _ramp(nt, colors, (-300, 200))
    nt.links.new(fac, col.inputs["Fac"])
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.location = (-300, -100)
    rr.inputs["To Min"].default_value = rough[0]
    rr.inputs["To Max"].default_value = rough[1]
    nt.links.new(fac, rr.inputs["Value"])
    nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.location = (-300, -300)
    mr.inputs["To Min"].default_value = metallic[0]
    mr.inputs["To Max"].default_value = metallic[1]
    nt.links.new(fac, mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], bsdf.inputs["Metallic"])
    b = nt.nodes.new("ShaderNodeBump")
    b.location = (0, -400)
    b.inputs["Strength"].default_value = bump
    b.inputs["Distance"].default_value = 0.02
    nt.links.new(fac, b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    if sheen:
        bsdf.inputs["Sheen Weight"].default_value = sheen
        bsdf.inputs["Sheen Tint"].default_value = (1.0, 0.5, 0.5, 1.0)
    return m


def mat_glow(name, color, strength):
    m, nt, bsdf = _principled(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.2
    return m


def make_materials():
    M = {}
    # Rusty bronze armour: dark brown pits, bronze, copper, orange rust.
    M["bronze"] = mat_worn("PIR_RustyBronze", [
        (0.0, (0.02, 0.006, 0.004)), (0.3, (0.12, 0.045, 0.018)),
        (0.48, (0.33, 0.16, 0.06)), (0.64, (0.48, 0.26, 0.10)), (0.82, (0.42, 0.09, 0.02))],
        metallic=(0.9, 0.55), rough=(0.35, 0.8), scale=7.0, pits=0.18, bump=0.35)
    M["dark"] = mat_worn("PIR_DarkMetal", [
        (0.0, (0.012, 0.008, 0.008)), (0.6, (0.05, 0.03, 0.025)), (1.0, (0.16, 0.08, 0.04))],
        metallic=(0.85, 0.7), rough=(0.35, 0.6), scale=12.0, bump=0.15)
    M["cloth"] = mat_worn("PIR_CrimsonCloth", [
        (0.0, (0.02, 0.002, 0.004)), (0.35, (0.09, 0.006, 0.012)),
        (0.6, (0.17, 0.012, 0.02)), (0.85, (0.24, 0.03, 0.025)), (1.0, (0.32, 0.09, 0.03))],
        metallic=(0.0, 0.0), rough=(0.7, 0.95), scale=5.0, pits=0.12, bump=0.2, sheen=0.15)
    M["leather"] = mat_worn("PIR_Leather", [
        (0.0, (0.015, 0.004, 0.004)), (0.5, (0.07, 0.02, 0.015)), (1.0, (0.16, 0.05, 0.03))],
        metallic=(0.0, 0.0), rough=(0.45, 0.75), scale=9.0, bump=0.3)
    M["gold"] = mat_worn("PIR_Gold", [
        (0.0, (0.25, 0.12, 0.03)), (0.6, (0.75, 0.48, 0.16)), (1.0, (0.95, 0.72, 0.35))],
        metallic=(1.0, 0.9), rough=(0.25, 0.5), scale=15.0, bump=0.1)
    M["bone"] = mat_worn("PIR_Bone", [
        (0.0, (0.25, 0.15, 0.08)), (0.5, (0.62, 0.47, 0.30)), (1.0, (0.85, 0.74, 0.55))],
        metallic=(0.0, 0.0), rough=(0.5, 0.8), scale=10.0, pits=0.2, bump=0.4)
    M["tentacle"] = mat_worn("PIR_Tentacle", [
        (0.0, (0.05, 0.006, 0.03)), (0.5, (0.18, 0.03, 0.08)), (1.0, (0.36, 0.10, 0.16))],
        metallic=(0.0, 0.0), rough=(0.3, 0.5), scale=14.0, bump=0.3, sheen=0.3)
    M["green"] = mat_glow("PIR_GlowGreen", (0.35, 1.0, 0.05), 1.8)
    M["yellow"] = mat_glow("PIR_GlowYellow", (1.0, 0.55, 0.02), 1.4)
    M["eye"] = mat_glow("PIR_EyeRed", (1.0, 0.08, 0.01), 6.0)
    M["teal"] = mat_glow("PIR_GlowTeal", (0.1, 1.0, 0.7), 2.5)
    return M


# ------------------------------------------------------------------ objects

_coll = None
_root = None


def _link(name, data, parent=None):
    ob = bpy.data.objects.new(name, data)
    _coll.objects.link(ob)
    ob.parent = parent or _root
    return ob


def _obj_from_bm(name, bm, mats, smooth=False, parent=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    if smooth:
        me.shade_smooth()
    return _link(name, me, parent)


def _bevel(ob, w=0.006, seg=2):
    b = ob.modifiers.new("Bevel", "BEVEL")
    b.width = w
    b.segments = seg
    b.limit_method = "ANGLE"
    return ob


def rivets(bm, pts, r=0.011, mat_index=1):
    for p in pts:
        res = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=r, matrix=Matrix.Translation(p))
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = mat_index


def box(name, size, loc, mats, rot=(0, 0, 0), taper=None, bevel=0.008, rivet_face=None, parent=None):
    """A bevelled box; taper=(sx, sy) scales the bottom; rivet_face='-y' etc.
    puts rivets on the corners of that face (material 2)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        if taper and v.co.z < 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    if rivet_face:
        ax = "xyz".index(rivet_face[1])
        sgn = 1 if rivet_face[0] == "+" else -1
        others = [i for i in range(3) if i != ax]
        pts = []
        for a in (-0.38, 0.38):
            for b in (-0.38, 0.38):
                p = [0.0, 0.0, 0.0]
                p[ax] = sgn * size[ax] * 0.5
                p[others[0]] = a * size[others[0]]
                p[others[1]] = b * size[others[1]]
                pts.append(Vector(p))
        rivets(bm, pts)
    ob = _obj_from_bm(name, bm, mats, parent=parent)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel:
        _bevel(ob, bevel)
    return ob


def limb(name, p1, p2, r1, r2, mats, seg=16, squash=1.0, parent=None):
    """A tapered cylinder from p1 to p2."""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r1, radius2=r2, depth=d.length)
    for v in bm.verts:
        v.co.y *= squash
    ob = _obj_from_bm(name, bm, mats, smooth=True, parent=parent)
    ob.location = (p1 + p2) * 0.5
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = d.to_track_quat("Z", "Y")
    return ob


def ball(name, loc, radius, mats, scale=(1, 1, 1), half=False, seg=20, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=radius)
    if half:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
    for v in bm.verts:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    ob = _obj_from_bm(name, bm, mats, smooth=True, parent=parent)
    ob.location = loc
    return ob


def spikes(name, base_pts, dirs, length, radius, mats, parent=None):
    bm = bmesh.new()
    for p, d in zip(base_pts, dirs):
        d = Vector(d).normalized()
        m = Matrix.Translation(Vector(p) + d * length * 0.5) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=0.0, depth=length, matrix=m)
    return _obj_from_bm(name, bm, mats, parent=parent)


def tattered(name, center, z_top, z_bot, r_top, r_bot, a0, a1, mats, cols=28, rows=9,
             squash=0.8, rag=0.18, thick=0.012, parent=None):
    """An open, flaring skirt of cloth around `center` (x, y), from angle a0 to
    a1 (0 = back (+y), +-pi = front (-y)), its hem torn into points of
    random length."""
    bm = bmesh.new()
    grid = []
    hem = []
    for i in range(cols + 1):
        if i % 2 == 0:
            hem.append(z_bot - rng.uniform(0.0, rag))          # a point hanging down
        else:
            hem.append(z_bot + rng.uniform(0.02, rag * 0.9))    # a tear up into the cloth
    for j in range(rows + 1):
        t = j / rows
        row = []
        for i in range(cols + 1):
            a = a0 + (a1 - a0) * i / cols
            zb = hem[i]
            z = z_top + (zb - z_top) * t
            r = r_top + (r_bot - r_top) * t ** 1.3
            wav = 0.012 * math.sin(i * 1.7 + j * 0.6) * t
            row.append(bm.verts.new((center[0] + (r + wav) * math.sin(a),
                                     center[1] + (r + wav) * math.cos(a) * squash, z)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _obj_from_bm(name, bm, mats, smooth=True, parent=parent)
    s = ob.modifiers.new("Solidify", "SOLIDIFY")
    s.thickness = thick
    s.offset = 1.0
    return ob


def tentacle(name, pts, r0, mats, parent=None):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r0
    cu.bevel_resolution = 4
    cu.resolution_u = 10
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for k, p in enumerate(pts):
        sp.points[k].co = (*p, 1.0)
        sp.points[k].radius = max(0.08, 1.0 - k / (len(pts) - 1)) ** 0.8
    sp.order_u = 4
    sp.use_endpoint_u = True
    for m in mats:
        cu.materials.append(m)
    return _link(name, cu, parent)


# ------------------------------------------------------------------- pieces

def skull(name, loc, s, M, parent=None):
    """A little bone skull (belt / hat ornament): cranium + jaw + dark eyes."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=s,
                              matrix=Matrix.Translation((0, 0, s * 0.25)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, -s * 0.25, -s * 0.55)) @
                          Matrix.Diagonal((s * 1.0, s * 0.9, s * 0.6, 1.0)))
    for x in (-0.38, 0.38):
        res = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=s * 0.28,
                                        matrix=Matrix.Translation((x * s, -s * 0.82, s * 0.15)))
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = 1
    ob = _obj_from_bm(name, bm, [M["bone"], M["dark"]], smooth=True, parent=parent)
    ob.location = loc
    return ob


def build_legs(M):
    for side, sx in (("L", 1), ("R", -1)):
        x = 0.13 * sx
        box("Boot." + side, (0.16, 0.30, 0.12), (x, -0.04, 0.06), [M["bronze"], M["gold"]], taper=(1.05, 1.0))
        box("BootToe." + side, (0.17, 0.10, 0.08), (x, -0.17, 0.05), [M["dark"]], rot=(0.2, 0, 0))
        box("BootCuff." + side, (0.17, 0.17, 0.08), (x, 0.0, 0.15), [M["bronze"], M["gold"]], rivet_face="-y")
        ball("Ankle." + side, (x, 0.0, 0.17), 0.06, [M["dark"]])
        limb("Shin." + side, (x, 0, 0.17), (x, 0.01, 0.53), 0.06, 0.08, [M["dark"]])
        box("ShinPlate." + side, (0.13, 0.05, 0.32), (x, -0.075, 0.35), [M["bronze"], M["gold"]],
            rot=(0.06, 0, 0), taper=(0.75, 1.0), rivet_face="-y")
        ball("Knee." + side, (x, -0.03, 0.56), 0.075, [M["bronze"]], scale=(1, 1, 0.9))
        box("KneePlate." + side, (0.12, 0.05, 0.11), (x, -0.095, 0.57), [M["bronze"], M["gold"]],
            rot=(-0.25, 0, 0), rivet_face="-y")
        limb("Thigh." + side, (x, 0, 0.58), (x * 1.08, 0, 0.93), 0.085, 0.11, [M["dark"]])
        box("ThighPlate." + side, (0.16, 0.05, 0.26), (x * 1.06, -0.095, 0.77), [M["bronze"], M["gold"]],
            rot=(-0.05, 0, 0), taper=(0.8, 1.0), rivet_face="-y")
        box("HipPlate." + side, (0.05, 0.16, 0.2), (x * 1.55, 0.0, 0.9), [M["bronze"], M["gold"]],
            rot=(0, sx * 0.15, 0), rivet_face=("+x" if sx > 0 else "-x"))


def build_body(M):
    box("Pelvis", (0.36, 0.24, 0.14), (0, 0, 0.98), [M["dark"]])
    box("Codpiece", (0.14, 0.05, 0.14), (0, -0.13, 0.94), [M["bronze"], M["gold"]], taper=(0.6, 1), rivet_face="-y")
    limb("Belt", (0, 0, 1.01), (0, 0, 1.07), 0.21, 0.21, [M["leather"]], seg=24, squash=0.72)
    box("Buckle", (0.09, 0.025, 0.07), (0, -0.155, 1.04), [M["gold"]])
    for k, (bx, by) in enumerate(((-0.12, -0.14), (0.12, -0.14), (0.2, -0.04))):
        skull("BeltSkull.%d" % k, (bx, by, 0.99), 0.035, M)
    limb("Waist", (0, 0, 1.06), (0, 0, 1.22), 0.14, 0.17, [M["dark"]], squash=0.75)
    for k, z in enumerate((1.1, 1.16, 1.22)):
        box("AbPlate.%d" % k, (0.2 - k * 0.0, 0.05, 0.05), (0, -0.12 - k * 0.01, z), [M["bronze"]], bevel=0.006)
    box("Chest", (0.44, 0.28, 0.30), (0, 0, 1.37), [M["bronze"], M["gold"]], taper=(0.72, 0.85), bevel=0.02)
    for side, sx in (("L", 1), ("R", -1)):
        box("Pec." + side, (0.19, 0.06, 0.17), (sx * 0.1, -0.145, 1.39), [M["bronze"], M["gold"]],
            rot=(0.1, sx * 0.12, 0), taper=(0.85, 1), rivet_face="-y")
    ball("ChestGemSetting", (0, -0.17, 1.43), 0.042, [M["gold"]], scale=(1, 0.5, 1.2))
    ball("ChestGem", (0, -0.185, 1.43), 0.03, [M["green"]], scale=(1, 0.6, 1.25))
    box("Backpack", (0.3, 0.12, 0.26), (0, 0.17, 1.37), [M["dark"], M["gold"]], rivet_face="+y")
    for side, sx in (("L", 1), ("R", -1)):   # glowing cells on the back
        limb("BackCell." + side, (sx * 0.08, 0.24, 1.26), (sx * 0.08, 0.24, 1.46), 0.025, 0.025, [M["yellow"]])
    limb("Neck", (0, 0, 1.5), (0, -0.005, 1.6), 0.06, 0.05, [M["dark"]])


def build_head(M):
    ball("Head", (0, -0.01, 1.67), 0.1, [M["dark"]], scale=(0.95, 1.1, 1.2))
    box("FacePlate", (0.15, 0.06, 0.12), (0, -0.095, 1.64), [M["bronze"], M["gold"]], taper=(0.55, 0.9),
        rot=(0.12, 0, 0), bevel=0.012)
    box("Brow", (0.17, 0.05, 0.03), (0, -0.11, 1.705), [M["bronze"]], rot=(-0.25, 0, 0))
    for side, sx in (("L", 1), ("R", -1)):
        ball("Eye." + side, (sx * 0.037, -0.13, 1.685), 0.02, [M["eye"]], scale=(1.4, 0.6, 0.85), seg=12)
    for k in range(3):
        box("Grille.%d" % k, (0.06 - k * 0.012, 0.012, 0.01), (0, -0.128, 1.615 - k * 0.018), [M["dark"]], bevel=0)


def build_hat(M):
    hat = bpy.data.objects.new("Hat", None)
    _coll.objects.link(hat)
    hat.parent = _root
    hat.location = (0, 0.0, 1.765)
    hat.rotation_euler = (-0.05, 0, 0)     # tipped forward a little
    # The brim: three sides turned up, three corners (front, back-left, back-right).
    bm = bmesh.new()
    seg, rings = 72, 6
    front = math.pi
    grid = []
    edge = []
    for j in range(rings + 1):
        t = j / rings
        row = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            c3 = math.cos(3 * (a - front))
            r = 0.11 + t * (0.1 + 0.07 * (c3 + 1) * 0.5)
            lift = 0.2 * t ** 1.1 * (0.5 - 0.5 * c3) + 0.03 * t
            co = (r * math.sin(a), r * math.cos(a), lift)
            row.append(bm.verts.new(co))
            if j == rings:
                edge.append(co)
        grid.append(row)
    for j in range(rings):
        for i in range(seg):
            bm.faces.new((grid[j][i], grid[j][(i + 1) % seg], grid[j + 1][(i + 1) % seg], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    brim = _obj_from_bm("HatBrim", bm, [M["leather"]], smooth=True, parent=hat)
    s = brim.modifiers.new("Solidify", "SOLIDIFY")
    s.thickness = 0.014
    # Gold trim along the edge.
    cu = bpy.data.curves.new("HatTrim", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.007
    sp = cu.splines.new("POLY")
    sp.points.add(len(edge) - 1)
    for k, co in enumerate(edge):
        sp.points[k].co = (*co, 1.0)
    sp.use_cyclic_u = True
    cu.materials.append(M["gold"])
    _link("HatTrim", cu, hat)
    # The crown, a dome on top.
    limb("HatCrown", (0, 0, -0.01), (0, 0, 0.12), 0.12, 0.105, [M["leather"]], seg=24, parent=hat)
    ball("HatDome", (0, 0, 0.12), 0.105, [M["leather"]], scale=(1, 1, 0.45), half=True, parent=hat)
    skull("HatSkull", (0, -0.125, 0.065), 0.03, M, parent=hat)
    for k, rz in enumerate((0.5, -0.5)):
        b = box("HatBone.%d" % k, (0.08, 0.01, 0.012), (0, -0.128, 0.05), [M["bone"]], rot=(0, rz, 0),
                bevel=0.003, parent=hat)
    # Spikes on the turned-up sides.
    pts, dirs = [], []
    for i in range(0, seg, 6):
        a = 2 * math.pi * i / seg
        c3 = math.cos(3 * (a - front))
        if c3 < -0.3:
            r = 0.11 + 0.1 + 0.07 * (c3 + 1) * 0.5
            lift = 0.2 * (0.5 - 0.5 * c3) + 0.03
            pts.append((r * 0.95 * math.sin(a), r * 0.95 * math.cos(a), lift))
            dirs.append((math.sin(a) * 0.6, math.cos(a) * 0.6, 1.0))
    spikes("HatSpikes", pts, dirs, 0.045, 0.01, [M["gold"]], parent=hat)


def build_arms(M):
    for side, sx in (("L", 1), ("R", -1)):
        sh = (sx * 0.29, 0.0, 1.44)
        el = (sx * 0.34, 0.03, 1.15)
        wr = (sx * 0.33, -0.03, 0.9)
        ball("ShoulderJoint." + side, sh, 0.075, [M["dark"]])
        ball("Pauldron." + side, (sx * 0.31, 0.0, 1.47), 0.145, [M["bronze"]], scale=(1.0, 0.95, 0.8), half=True)
        ball("PauldronRim." + side, (sx * 0.33, 0.0, 1.43), 0.15, [M["gold"]], scale=(0.95, 0.9, 0.25))
        box("PauldronPlate." + side, (0.05, 0.2, 0.12), (sx * 0.43, 0.0, 1.38), [M["bronze"], M["gold"]],
            rot=(0, sx * -0.35, 0), rivet_face=("+x" if sx > 0 else "-x"))
        spikes("PauldronSpikes." + side,
               [(sx * 0.31, -0.06, 1.58), (sx * 0.33, 0.0, 1.59), (sx * 0.31, 0.06, 1.58)],
               [(sx * 0.4, -0.2, 1), (sx * 0.4, 0, 1), (sx * 0.4, 0.2, 1)], 0.06, 0.016, [M["dark"]])
        limb("UpperArm." + side, sh, el, 0.06, 0.055, [M["dark"]])
        box("BicepPlate." + side, (0.05, 0.11, 0.2), (sx * 0.38, 0.015, 1.27), [M["bronze"], M["gold"]],
            rot=(0, sx * -0.1, 0), rivet_face=("+x" if sx > 0 else "-x"))
        ball("Elbow." + side, el, 0.058, [M["bronze"]])
        limb("Forearm." + side, el, wr, 0.055, 0.045, [M["dark"]])
        limb("Vambrace." + side, (sx * 0.338, 0.015, 1.1), (sx * 0.332, -0.02, 0.95), 0.075, 0.062, [M["bronze"]])
        limb("VambraceBand." + side, (sx * 0.337, 0.01, 1.075), (sx * 0.336, 0.007, 1.06), 0.079, 0.078, [M["gold"]])
        box("Hand." + side, (0.07, 0.1, 0.11), (sx * 0.33, -0.05, 0.84), [M["dark"]], bevel=0.015)
    # Glowing teal strip on the right forearm (as in the reference).
    box("ForearmLight", (0.012, 0.02, 0.1), (-0.405, -0.01, 1.02), [M["teal"]], bevel=0.003)


def build_rifle(M):
    """The rifle in the right hand, barrel down and a little forward; built
    along local -Z (muzzle) .. +Z (stock), the grip at the origin."""
    rig = bpy.data.objects.new("Rifle", None)
    _coll.objects.link(rig)
    rig.parent = _root
    rig.location = (-0.35, -0.09, 0.84)
    rig.scale = (1.2, 1.2, 1.2)
    top, muzzle = Vector((-0.34, 0.06, 1.08)), Vector((-0.39, -0.22, 0.3))
    rig.rotation_mode = "QUATERNION"
    rig.rotation_quaternion = (top - muzzle).to_track_quat("Z", "Y")
    P = rig
    box("RifleReceiver", (0.07, 0.11, 0.34), (0, -0.06, -0.05), [M["bronze"], M["gold"]], rivet_face="+x", parent=P)
    box("RifleStock", (0.05, 0.09, 0.2), (0, 0.0, 0.2), [M["dark"]], taper=(1, 0.7), parent=P)
    box("RifleGrip", (0.04, 0.05, 0.1), (0, 0.0, 0.0), [M["dark"]], parent=P)
    limb("RifleShroud", (0, -0.06, -0.2), (0, -0.06, -0.45), 0.045, 0.04, [M["bronze"]], parent=P)
    limb("RifleBarrel", (0, -0.06, -0.45), (0, -0.06, -0.66), 0.022, 0.022, [M["dark"]], parent=P)
    limb("RifleMuzzle", (0, -0.06, -0.64), (0, -0.06, -0.7), 0.032, 0.03, [M["gold"]], parent=P)
    for k, z in enumerate((-0.27, -0.36)):
        limb("RifleBand.%d" % k, (0, -0.06, z), (0, -0.06, z - 0.02), 0.049, 0.049, [M["gold"]], parent=P)
    limb("RifleCell", (0.0, -0.13, -0.12), (0, -0.13, -0.32), 0.022, 0.022, [M["green"]], parent=P)
    limb("RifleCell2", (0.045, -0.05, -0.18), (0.045, -0.05, -0.38), 0.016, 0.016, [M["yellow"]], parent=P)
    for z in (-0.11, -0.33):
        limb("RifleCellCap", (0, -0.13, z), (0, -0.13, z + (0.015 if z < -0.2 else -0.015)), 0.026, 0.026, [M["dark"]], parent=P)
    box("RifleScope", (0.035, 0.04, 0.16), (0, -0.13, 0.02), [M["dark"]], parent=P)


def build_cloth(M):
    # The long coat: open in front, hem torn to points.
    tattered("Coat", (0, 0.0), 1.06, 0.34, 0.215, 0.34, -math.pi + 0.85, math.pi - 0.85, [M["cloth"]],
             cols=34, rows=10, squash=0.78, rag=0.2)
    # Rags hanging off the shoulders, over the outer side of the arms.
    for side, sx in (("L", 1), ("R", -1)):
        a0, a1 = (0.0, math.pi * 0.95) if sx > 0 else (-math.pi * 0.95, 0.0)
        tattered("ShoulderRag." + side, (sx * 0.3, 0.0), 1.5, 1.12, 0.155, 0.19, a0, a1, [M["cloth"]],
                 cols=12, rows=6, squash=0.9, rag=0.12)
    # A high collar.
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=0.2, radius2=0.14, depth=0.12)
    for v in bm.verts:
        v.co.y *= 0.8
    ob = _obj_from_bm("Collar", bm, [M["cloth"]], smooth=True)
    ob.location = (0, 0.01, 1.53)
    ob.modifiers.new("Solidify", "SOLIDIFY").thickness = 0.012


def build_tentacles(M):
    specs = [
        ((0.1, 0.12, 1.55), 1, 0.042),
        ((-0.12, 0.13, 1.54), -1, 0.04),
        ((0.24, 0.1, 1.52), 1, 0.034),
        ((-0.25, 0.1, 1.5), -1, 0.032),
        ((0.0, 0.17, 1.45), 1, 0.036),
    ]
    for k, (p, sx, r) in enumerate(specs):
        x, y, z = p
        pts = [p]
        for s in range(1, 7):
            t = s / 6
            pts.append((x + sx * (0.09 * t + 0.03 * math.sin(t * 7 + k)),
                        y + 0.06 * math.sin(t * 3.0 + k) + 0.05 * t,
                        z - 0.62 * t + 0.04 * math.sin(t * 9)))
        pts[-1] = (pts[-1][0] + sx * 0.04, pts[-1][1] - 0.03, pts[-1][2] + 0.05)   # the tip curls
        tentacle("Tentacle.%d" % k, pts, r, [M["tentacle"]])


# -------------------------------------------------------- lights and camera

def stage():
    sc = bpy.context.scene
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.035, 0.02, 0.05, 1.0)
        bg.inputs["Strength"].default_value = 1.0
    def light(name, kind, loc, energy, color, size=1.0):
        ld = bpy.data.lights.get(name) or bpy.data.lights.new(name, kind)
        ld.energy, ld.color = energy, color
        if kind == "AREA":
            ld.size = size
        ob = bpy.data.objects.get(name) or _link(name, ld)
        ob.parent = None
        ob.location = loc
        d = Vector((0, 0, 1.0)) - Vector(loc)
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = d.to_track_quat("-Z", "Y")
    light("PIR_Key", "AREA", (-2.2, -2.8, 3.4), 260, (1.0, 0.82, 0.62), 2.0)
    light("PIR_Rim", "AREA", (2.0, 2.6, 2.8), 450, (1.0, 0.35, 0.3), 1.5)
    light("PIR_Fill", "AREA", (2.6, -2.0, 1.4), 50, (0.7, 0.55, 1.0), 2.5)
    vs = sc.view_settings
    vs.view_transform = "AgX"
    try:
        vs.look = "AgX - Punchy"
    except TypeError:
        pass
    cd = bpy.data.cameras.get("PIR_Cam") or bpy.data.cameras.new("PIR_Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.35
    cam = bpy.data.objects.get("PIR_Cam") or _link("PIR_Cam", cd)
    cam.parent = None
    # The game's view: from the front, 30 degrees above.
    tgt = Vector((0, 0, 0.98))
    el = math.radians(30)
    cam.location = tgt + Vector((0, -math.cos(el), math.sin(el))) * 10
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
    sc.camera = cam
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.film_transparent = True
    sc.render.resolution_x = 900
    sc.render.resolution_y = 900
    sc.render.resolution_percentage = 100


# ----------------------------------------------------------------------- main

def clear():
    old = bpy.data.collections.get(COLL)
    if old:
        for ob in list(old.all_objects):
            data = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if data is not None and data.users == 0:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                elif isinstance(data, bpy.types.Curve):
                    bpy.data.curves.remove(data)
    return old


def build():
    global _coll, _root, rng
    rng = random.Random(7)
    _coll = clear() or bpy.data.collections.new(COLL)
    if _coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(_coll)
    _root = bpy.data.objects.new(ROOT, None)
    _coll.objects.link(_root)
    M = make_materials()
    build_legs(M)
    build_body(M)
    build_head(M)
    build_hat(M)
    build_arms(M)
    build_rifle(M)
    build_cloth(M)
    build_tentacles(M)
    stage()
    return {"objects": len(_coll.all_objects), "materials": len(M)}


if __name__ == "__main__":
    print(build())
