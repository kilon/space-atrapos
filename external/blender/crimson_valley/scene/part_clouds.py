"""The clouds of the Crimson Valley scene: part "clouds".

  tools/cv part clouds --with sky,planet,moons --render renders/clouds/a.png --no-sun

CV_Clouds is a card 20 km in front of the camera (in front of the planet at 60 km, behind the far
mountains at 9 km), parallel to the picture plane and larger than the frame. Its material is self-lit
(emission) and takes the cloud masses, the glow and their colours from the layout guide
analysis/cloud_guide.png (tools/make_cloud_guide.py: the picture's sky at quarter size, blurred, with
the land, planet and moons filled in) - and makes the detail itself: the guide is looked up through
two scales of noise (billows and wisps), and a finer noise brightens and darkens the cloud bodies.
The guide's alpha is the cloud cover over the planet: clear over its disc, closing where its lower
limb sinks into the haze. Past the frame the card fades out to the world's clear sky.
Ray visibility: camera and glossy (the river mirrors it); it casts no shadow and lights nothing."""
import os

import bpy
import numpy as np

import common

DIST = 20000.0
U0, U1, V0, V1 = -700.0, 2372.0, -500.0, 520.0      # the card, in picture pixels (the guide covers rows 0-520)


def build(col):
    cm = common.cam_model()
    nu, nv = 48, 16
    uu, vv = np.meshgrid(np.linspace(U0, U1, nu + 1), np.linspace(V0, V1, nv + 1))
    pts = cm.unproject(uu.ravel(), vv.ravel(), np.full(uu.size, DIST))
    idx = np.arange(uu.size).reshape(nv + 1, nu + 1)
    faces = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]], -1).reshape(-1, 4)
    uvs = np.stack([uu.ravel() / common.W, 1 - vv.ravel() / 520.0], 1)      # guide UV: rows 0-520
    ob = common.mesh_object("CV_Clouds", pts, faces.astype(np.int32), col, smooth=False, uvs=uvs)
    ob.visible_diffuse = False
    ob.visible_shadow = False
    ob.visible_transmission = False
    ob.visible_volume_scatter = False

    mat, N, L = common.new_material("CV_Clouds")
    out = N.new("ShaderNodeOutputMaterial")
    uv = N.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    # warp: billows (large) and wisps (small), in guide UV units
    def noise(scale, detail, rough):
        n = N.new("ShaderNodeTexNoise")
        n.noise_type = "FBM"
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0, 0.31, 1.0)       # the guide is 3.2 times wider than tall
    L.new(uv.outputs["UV"], mp.inputs["Vector"])
    n1, n2 = noise(14.0, 6.0, 0.6), noise(70.0, 5.0, 0.65)
    L.new(mp.outputs["Vector"], n1.inputs["Vector"])
    L.new(mp.outputs["Vector"], n2.inputs["Vector"])
    def offset(n, amount):
        sub = N.new("ShaderNodeVectorMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = (0.5, 0.5, 0.5)
        L.new(n.outputs["Color"], sub.inputs[0])
        sc = N.new("ShaderNodeVectorMath")
        sc.operation = "SCALE"
        sc.inputs["Scale"].default_value = amount
        L.new(sub.outputs[0], sc.inputs[0])
        return sc
    o1, o2 = offset(n1, 0.012), offset(n2, 0.006)
    add1 = N.new("ShaderNodeVectorMath")
    L.new(uv.outputs["UV"], add1.inputs[0])
    L.new(o1.outputs[0], add1.inputs[1])
    add2 = N.new("ShaderNodeVectorMath")
    L.new(add1.outputs[0], add2.inputs[0])
    L.new(o2.outputs[0], add2.inputs[1])
    img = bpy.data.images.load(os.path.join(common.ANALYSIS, "cloud_guide.png"))
    img.name = "CV_CloudGuide"
    img.pack()
    tex = N.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Cubic"
    tex.extension = "EXTEND"
    L.new(add2.outputs[0], tex.inputs["Vector"])
    texa = N.new("ShaderNodeTexImage")              # the cover over the planet: not warped
    texa.image = img
    texa.interpolation = "Cubic"
    texa.extension = "EXTEND"
    L.new(uv.outputs["UV"], texa.inputs["Vector"])
    # body detail: contrast by a fine noise, stronger where the guide is bright (lit cloud)
    n3 = noise(160.0, 6.0, 0.7)
    L.new(mp.outputs["Vector"], n3.inputs["Vector"])
    gain = N.new("ShaderNodeMapRange")
    gain.inputs["From Min"].default_value = 0.25
    gain.inputs["From Max"].default_value = 0.75
    gain.inputs["To Min"].default_value = 0.86
    gain.inputs["To Max"].default_value = 1.16
    L.new(n3.outputs["Fac"], gain.inputs["Value"])
    mul = N.new("ShaderNodeVectorMath")
    mul.operation = "SCALE"
    L.new(tex.outputs["Color"], mul.inputs[0])
    L.new(gain.outputs["Result"], mul.inputs["Scale"])
    em = N.new("ShaderNodeEmission")
    L.new(mul.outputs[0], em.inputs["Color"])
    # fade out past the frame (guide UV outside 0..1 by more than a margin)
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(uv.outputs["UV"], sep.inputs[0])
    def edge(sock, lo, hi):
        a = N.new("ShaderNodeMapRange")
        a.inputs["From Min"].default_value = lo
        a.inputs["From Max"].default_value = hi
        L.new(sock, a.inputs["Value"])
        return a
    fx0, fx1 = edge(sep.outputs["X"], -0.40, -0.05), edge(sep.outputs["X"], 1.40, 1.05)
    fy1 = edge(sep.outputs["Y"], 1.95, 1.3)
    m1 = N.new("ShaderNodeMath"); m1.operation = "MULTIPLY"
    L.new(fx0.outputs["Result"], m1.inputs[0]); L.new(fx1.outputs["Result"], m1.inputs[1])
    m2 = N.new("ShaderNodeMath"); m2.operation = "MULTIPLY"
    L.new(m1.outputs[0], m2.inputs[0]); L.new(fy1.outputs["Result"], m2.inputs[1])
    m3 = N.new("ShaderNodeMath"); m3.operation = "MULTIPLY"
    L.new(m2.outputs[0], m3.inputs[0]); L.new(texa.outputs["Alpha"], m3.inputs[1])
    tr = N.new("ShaderNodeBsdfTransparent")
    mix = N.new("ShaderNodeMixShader")
    L.new(m3.outputs[0], mix.inputs["Fac"])
    L.new(tr.outputs[0], mix.inputs[1])
    L.new(em.outputs[0], mix.inputs[2])
    L.new(mix.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(mat)
