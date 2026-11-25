"""The gas giant of the Crimson Valley scene: part "planet".

  tools/cv part planet --with sky,clouds,moons --render renders/planet/a.png --no-sun

CV_Planet is a true sphere 60 km away, placed from the limb measured in the picture
(analysis/planet.json, tools/measure_planet.py: the sphere fit lands on the picture's limb within
about 1 px). Its material mixes its own light with the sky behind it by how lit it is, so where the
planet is dark you see sky - as in the picture, where the disc fades into the blue on the left. The
shader does its own lighting from a fixed direction (lit from the lower right, towards the sunset),
with a bright atmospheric rim; the bands are a colour ramp over latitude about an axis tilted as the
picture's bands are, stirred by noise (wavy edges, festoons, fine streaks)."""
import json
import math
import os

import bpy
import numpy as np

import common

DIST = 60000.0
BANDS = [(0.00, "#2a2c44"), (0.20, "#3a3048"), (0.30, "#5a2638"), (0.36, "#9a5a58"), (0.42, "#4a1626"),
         (0.50, "#b06858"), (0.56, "#5c1a24"), (0.62, "#c88a74"), (0.68, "#74222a"), (0.74, "#d8a080"),
         (0.80, "#8a3028"), (0.86, "#e0b090"), (0.92, "#a04c36"), (1.00, "#f0c8a0")]


def build(col):
    cm = common.cam_model()
    with open(os.path.join(common.ANALYSIS, "planet.json")) as fh:
        P = json.load(fh)["planet"]
    cu, cv = P["sphere"]["centre_px"]
    ang = math.radians(P["sphere"]["angular_radius_deg"])
    d = cm.rays(np.array(cu), np.array(cv))
    d = d / np.linalg.norm(d)
    centre = cm.pos + d * DIST
    radius = DIST * math.sin(ang)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=tuple(centre), segments=192, ring_count=96)
    ob = bpy.context.active_object
    ob.name = "CV_Planet"
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    col.objects.link(ob)
    bpy.ops.object.shade_smooth()
    for flag in ("visible_diffuse", "visible_shadow", "visible_transmission", "visible_volume_scatter"):
        setattr(ob, flag, False)
    # screen axes at the planet, in world space
    right, up = cm.right, cm.up
    axis = right * math.cos(math.radians(32)) + up * math.sin(math.radians(32)) - d * 0.45
    axis /= np.linalg.norm(axis)
    light = right * 0.86 - up * 0.42 - d * 0.28
    light /= np.linalg.norm(light)

    mat, N, L = common.new_material("CV_Planet")
    out = N.new("ShaderNodeOutputMaterial")
    geo = N.new("ShaderNodeNewGeometry")
    def dot(v):
        n = N.new("ShaderNodeVectorMath")
        n.operation = "DOT_PRODUCT"
        n.inputs[1].default_value = tuple(v)
        L.new(geo.outputs["Normal"], n.inputs[0])
        return n
    lat = dot(axis)
    # turbulence of the bands
    tc = N.new("ShaderNodeTexCoord")
    def noise(scale, detail, rough, stretch):
        mp = N.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        n = N.new("ShaderNodeTexNoise")
        n.noise_type = "FBM"
        n.inputs["Scale"].default_value = scale / radius
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        L.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n
    n1 = noise(5.0, 5.0, 0.6, (1, 1, 1))
    n2 = noise(22.0, 6.0, 0.65, (1, 1, 1))
    def lin(sock, a, b):
        m = N.new("ShaderNodeMath"); m.operation = "MULTIPLY_ADD"
        m.inputs[1].default_value = a; m.inputs[2].default_value = b
        L.new(sock, m.inputs[0])
        return m
    t0 = lin(lat.outputs["Value"], 0.5, 0.5)                      # 0..1 from one pole to the other
    w1 = lin(n1.outputs["Fac"], 0.05, -0.025)
    w2 = lin(n2.outputs["Fac"], 0.03, -0.015)
    s1 = N.new("ShaderNodeMath"); L.new(t0.outputs[0], s1.inputs[0]); L.new(w1.outputs[0], s1.inputs[1])
    s2 = N.new("ShaderNodeMath"); L.new(s1.outputs[0], s2.inputs[0]); L.new(w2.outputs[0], s2.inputs[1])
    ramp = N.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    while len(cr.elements) < len(BANDS):
        cr.elements.new(0.5)
    for el, (p, c) in zip(cr.elements, BANDS):
        el.position = p
        el.color = common.rgba(c)
    L.new(s2.outputs[0], ramp.inputs["Fac"])
    # fine streaks along the bands
    n3 = noise(60.0, 4.0, 0.7, (1, 1, 1))
    streak = N.new("ShaderNodeMapRange")
    streak.inputs["To Min"].default_value = 0.8
    streak.inputs["To Max"].default_value = 1.2
    L.new(n3.outputs["Fac"], streak.inputs["Value"])
    # lighting: day side, soft terminator, bright rim
    nl = dot(light)
    day = N.new("ShaderNodeMapRange")
    day.interpolation_type = "SMOOTHSTEP"
    day.inputs["From Min"].default_value = -0.30
    day.inputs["From Max"].default_value = 0.80
    L.new(nl.outputs["Value"], day.inputs["Value"])
    lw = N.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.12
    rim = N.new("ShaderNodeMath"); rim.operation = "MULTIPLY"
    L.new(lw.outputs["Facing"], rim.inputs[0]); L.new(day.outputs["Result"], rim.inputs[1])
    col1 = N.new("ShaderNodeVectorMath"); col1.operation = "SCALE"
    L.new(ramp.outputs["Color"], col1.inputs[0]); L.new(streak.outputs["Result"], col1.inputs["Scale"])
    shade = lin(day.outputs["Result"], 0.55, 0.45)
    col2 = N.new("ShaderNodeVectorMath"); col2.operation = "SCALE"
    L.new(col1.outputs[0], col2.inputs[0]); L.new(shade.outputs[0], col2.inputs["Scale"])
    rimc = N.new("ShaderNodeMix"); rimc.data_type = "RGBA"; rimc.blend_type = "ADD"
    rimc.inputs[7].default_value = common.rgba("#ffb080")
    rs = lin(rim.outputs[0], 0.35, 0.0)
    L.new(rs.outputs[0], rimc.inputs[0]); L.new(col2.outputs[0], rimc.inputs[6])
    em = N.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.15
    L.new(rimc.outputs[2], em.inputs["Color"])
    # where the planet is dark you see the sky behind it: mix by how lit it is
    tr = N.new("ShaderNodeBsdfTransparent")
    vis = N.new("ShaderNodeMapRange")
    vis.inputs["From Min"].default_value = 0.0
    vis.inputs["From Max"].default_value = 0.55
    vis.inputs["To Min"].default_value = 0.12
    vis.inputs["To Max"].default_value = 0.93
    L.new(day.outputs["Result"], vis.inputs["Value"])
    mixs = N.new("ShaderNodeMixShader")
    L.new(vis.outputs["Result"], mixs.inputs["Fac"])
    L.new(tr.outputs[0], mixs.inputs[1]); L.new(em.outputs[0], mixs.inputs[2])
    L.new(mixs.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(mat)
