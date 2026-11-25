"""The waterfalls: part "waterfalls".

  tools/cv part waterfalls --with sky,rocks,terrain,water --render renders/waterfalls/a.png

Six falls traced off the picture (FALLS: top and bottom of the centre line and the width at each, in
picture pixels). Each is a ribbon of two crossed, slightly bulged sheets hung half a metre in front of
the rock: the distance of every row is the depth the picture has along the fall (analysis/depth.npy,
smoothed down the fall). The material is self-lit cool white broken into long vertical streaks by
noise stretched along the fall, denser at the lip and thinning into veils below."""
import bpy
import numpy as np

import common

# u top, v top, u bottom, v bottom, width top, width bottom (picture pixels)
FALLS = [(1566, 546, 1562, 772, 46, 72), (1432, 540, 1421, 705, 14, 30), (1300, 458, 1298, 525, 8, 15),
         (1390, 330, 1392, 436, 12, 24), (1508, 340, 1506, 424, 8, 15), (1527, 342, 1526, 424, 8, 15)]


def material():
    mat, N, L = common.new_material("CV_Waterfall")
    out = N.new("ShaderNodeOutputMaterial")
    uv = N.new("ShaderNodeUVMap"); uv.uv_map = "UVMap"
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (22.0, 1.3, 1.0)
    L.new(uv.outputs["UV"], mp.inputs["Vector"])
    no = N.new("ShaderNodeTexNoise"); no.noise_type = "FBM"
    no.inputs["Scale"].default_value = 1.0; no.inputs["Detail"].default_value = 5.0; no.inputs["Roughness"].default_value = 0.6
    L.new(mp.outputs["Vector"], no.inputs["Vector"])
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(uv.outputs["UV"], sep.inputs[0])
    # denser at the lip (v = 1), thinner below; soft at the sides
    side = N.new("ShaderNodeMath"); side.operation = "PINGPONG"; side.inputs[1].default_value = 0.5
    L.new(sep.outputs["X"], side.inputs[0])
    sf = N.new("ShaderNodeMapRange"); sf.inputs["From Max"].default_value = 0.22
    L.new(side.outputs[0], sf.inputs["Value"])
    th = N.new("ShaderNodeMapRange")
    th.inputs["To Min"].default_value = 0.62; th.inputs["To Max"].default_value = 0.30
    L.new(sep.outputs["Y"], th.inputs["Value"])
    a = N.new("ShaderNodeMapRange")
    a.inputs["From Max"].default_value = 0.8
    L.new(th.outputs["Result"], a.inputs["From Min"])
    L.new(no.outputs["Fac"], a.inputs["Value"])
    al = N.new("ShaderNodeMath"); al.operation = "MULTIPLY"
    L.new(a.outputs["Result"], al.inputs[0]); L.new(sf.outputs["Result"], al.inputs[1])
    em = N.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = common.rgba("#cfd6dc")
    em.inputs["Strength"].default_value = 0.85
    tr = N.new("ShaderNodeBsdfTransparent")
    mix = N.new("ShaderNodeMixShader")
    L.new(al.outputs[0], mix.inputs["Fac"]); L.new(tr.outputs[0], mix.inputs[1]); L.new(em.outputs[0], mix.inputs[2])
    L.new(mix.outputs[0], out.inputs["Surface"])
    return mat


def build(col):
    cm = common.cam_model()
    z = np.load(common.ANALYSIS + "/depth.npy")
    mat = material()
    for k, (ut, vt, ub, vb, wt, wb) in enumerate(FALLS):
        rows = np.arange(vt, vb + 1)
        t = (rows - vt) / max(vb - vt, 1)
        uc = ut + (ub - ut) * t
        d = np.array([np.median(z[r, int(u) - 2:int(u) + 3][z[r, int(u) - 2:int(u) + 3] > 0]) for r, u in zip(rows, uc)])
        d = np.convolve(np.pad(d, 6, mode="edge"), np.ones(13) / 13, mode="valid") - 0.5
        w = wt + (wb - wt) * t ** 0.7
        verts, uvs = [], []
        for bulge in (0.0, 0.35):
            for side in (-1.0, 0.0, 1.0):
                verts.append(cm.unproject(uc + side * w / 2, rows.astype(float), d - (bulge + (0.4 if side == 0 else 0.0)) * w * d / cm.f * 0.4))
                uvs.append(np.stack([np.full(len(rows), 0.5 + side * 0.5 + bulge), 1 - t], 1))
        n = len(rows)
        faces = []
        for s in range(2):
            for c in range(2):
                a0 = (s * 3 + c) * n + np.arange(n - 1)
                b0 = a0 + n
                faces.append(np.stack([a0, a0 + 1, b0 + 1, b0], 1))
        ob = common.mesh_object(f"CV_Waterfall_{k + 1}", np.concatenate(verts), np.concatenate(faces).astype(np.int32),
                                col, uvs=np.concatenate(uvs))
        ob.data.materials.append(mat)
        ob.visible_shadow = False
