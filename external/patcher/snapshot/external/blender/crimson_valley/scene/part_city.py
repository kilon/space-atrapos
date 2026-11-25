"""The city on the arch and the cliffs: part "city".

  tools/cv part city --with sky,clouds,rocks --render renders/city/a.png

Towers, a dome and galleries measured off the picture (base and top in picture pixels, width in
pixels; STRUCTURES below) and stood on the rock: each one's distance is the depth of the rock just
under its base (analysis/depth.npy), its height and width the pixel sizes times depth / f. Towers are
tapered shafts with a spire, the dome a half sphere on a drum with a mast, galleries long low blocks.
The material is dark teal-grey stone with a procedural grid of warm lit windows (emission)."""
import math

import bpy
import numpy as np

import common

# kind, base u, base v, top v, width px
STRUCTURES = [
    ("tower", 1283, 289, 205, 15), ("tower", 1300, 290, 186, 12), ("tower", 1326, 289, 160, 11),
    ("tower", 1341, 290, 214, 10), ("tower", 1266, 291, 236, 12), ("tower", 1313, 290, 226, 16),
    ("dome", 1226, 291, 262, 34), ("block", 1193, 294, 276, 34), ("block", 1250, 293, 272, 30),
    ("tower", 1440, 301, 214, 10), ("tower", 1462, 301, 236, 9), ("tower", 1421, 302, 250, 10),
    ("tower", 1480, 302, 258, 8), ("block", 1385, 303, 280, 70), ("block", 1505, 306, 286, 90),
    ("mast", 1597, 82, 20, 5), ("mast", 1650, 182, 132, 6), ("mast", 1337, 215, 190, 3),
]


def material():
    mat, N, L = common.new_material("CV_City")
    out = N.new("ShaderNodeOutputMaterial")
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = common.rgba("#3c4648")
    bsdf.inputs["Roughness"].default_value = 0.5
    bsdf.inputs["Metallic"].default_value = 0.3
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.6, 1.6, 0.9)
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    br = N.new("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Mortar Size"].default_value = 0.35
    br.inputs["Color1"].default_value = (1, 1, 1, 1)
    br.inputs["Color2"].default_value = (1, 1, 1, 1)
    br.inputs["Mortar"].default_value = (0, 0, 0, 1)
    L.new(mp.outputs["Vector"], br.inputs["Vector"])
    wn = N.new("ShaderNodeTexWhiteNoise")
    sn = N.new("ShaderNodeVectorMath"); sn.operation = "SNAP"
    sn.inputs[1].default_value = (0.31, 0.31, 0.55)
    L.new(mp.outputs["Vector"], sn.inputs[0])
    L.new(sn.outputs[0], wn.inputs["Vector"])
    lit = N.new("ShaderNodeMath"); lit.operation = "GREATER_THAN"; lit.inputs[1].default_value = 0.62
    L.new(wn.outputs["Value"], lit.inputs[0])
    m = N.new("ShaderNodeMath"); m.operation = "MULTIPLY"
    L.new(lit.outputs[0], m.inputs[0]); L.new(br.outputs["Fac"], m.inputs[1])
    inv = N.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
    L.new(br.outputs["Fac"], inv.inputs[1])
    m2 = N.new("ShaderNodeMath"); m2.operation = "MULTIPLY"
    L.new(lit.outputs[0], m2.inputs[0]); L.new(inv.outputs[0], m2.inputs[1])
    bsdf.inputs["Emission Color"].default_value = common.rgba("#ffcf80")
    st = N.new("ShaderNodeMath"); st.operation = "MULTIPLY"; st.inputs[1].default_value = 6.0
    L.new(m2.outputs[0], st.inputs[0])
    L.new(st.outputs[0], bsdf.inputs["Emission Strength"])
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def add(col, mat, name, prim, **kw):
    getattr(bpy.ops.mesh, prim)(**kw)
    ob = bpy.context.active_object
    ob.name = name
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def build(col):
    cm = common.cam_model()
    z = np.load(common.ANALYSIS + "/depth.npy")
    mat = material()
    for k, (kind, u, vb, vt, wpx) in enumerate(STRUCTURES):
        patch = z[vb + 2:vb + 10, max(u - wpx // 2, 0):u + wpx // 2 + 1]
        patch = patch[patch > 0]
        if not len(patch):
            continue
        d = float(np.median(patch))
        base = cm.unproject(np.array(float(u)), np.array(float(vb) + 4), np.array(d))
        h = (vb - vt) * d / cm.f
        w = wpx * d / cm.f
        loc = lambda zc: (base[0], base[1], base[2] + zc)
        n = f"CV_City_{k:02d}_{kind}"
        if kind == "tower":
            add(col, mat, n, "primitive_cone_add", vertices=10, radius1=w / 2, radius2=w * 0.3, depth=h * 0.72, location=loc(h * 0.36 - 1))
            add(col, mat, n + "_spire", "primitive_cone_add", vertices=10, radius1=w * 0.33, radius2=0.0, depth=h * 0.3, location=loc(h * 0.85))
            add(col, mat, n + "_ring", "primitive_cylinder_add", vertices=10, radius=w * 0.42, depth=h * 0.04, location=loc(h * 0.70))
        elif kind == "dome":
            add(col, mat, n, "primitive_cylinder_add", vertices=16, radius=w / 2, depth=h * 0.5, location=loc(h * 0.25 - 1))
            add(col, mat, n + "_cap", "primitive_uv_sphere_add", segments=16, ring_count=8, radius=w * 0.46, location=loc(h * 0.5))
            add(col, mat, n + "_mast", "primitive_cone_add", vertices=6, radius1=w * 0.04, radius2=0.0, depth=h * 0.6, location=loc(h * 1.05))
        elif kind == "block":
            ob = add(col, mat, n, "primitive_cube_add", size=1.0, location=loc(h * 0.5 - 1))
            ob.scale = (w, w * 0.5, h + 2)
        else:
            add(col, mat, n, "primitive_cone_add", vertices=6, radius1=w / 2, radius2=0.0, depth=h + 2, location=loc(h * 0.5 - 1))
