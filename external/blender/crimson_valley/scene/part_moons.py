"""The two moons of the Crimson Valley scene: part "moons".

  tools/cv part moons --with sky,clouds,planet --render renders/moons/a.png --no-sun

CV_Moon_1 / CV_Moon_2: true spheres 50 km away, placed from the discs measured in the picture
(analysis/planet.json). Like the planet they add their light to the sky behind (so the unlit side is
sky-coloured haze, as in the picture) and are lit in the shader from a fixed direction (from the left
and above); the surface is a grey-tan mottle with soft craters (noise and Voronoi)."""
import json
import math
import os

import bpy
import numpy as np

import common

DIST = 50000.0


def build(col):
    cm = common.cam_model()
    with open(os.path.join(common.ANALYSIS, "planet.json")) as fh:
        moons = json.load(fh)["moons"]
    light = -cm.right * 0.62 + cm.up * 0.42 - cm.fwd * 0.66
    light /= np.linalg.norm(light)
    mat, N, L = common.new_material("CV_Moon")
    out = N.new("ShaderNodeOutputMaterial")
    geo = N.new("ShaderNodeNewGeometry")
    tc = N.new("ShaderNodeTexCoord")
    n1 = N.new("ShaderNodeTexNoise"); n1.noise_type = "FBM"
    n1.inputs["Scale"].default_value = 2.2; n1.inputs["Detail"].default_value = 6.0
    L.new(tc.outputs["Generated"], n1.inputs["Vector"])
    vo = N.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = 7.0
    L.new(tc.outputs["Generated"], vo.inputs["Vector"])
    crater = N.new("ShaderNodeMapRange")
    crater.inputs["From Min"].default_value = 0.0; crater.inputs["From Max"].default_value = 0.35
    crater.inputs["To Min"].default_value = 0.78; crater.inputs["To Max"].default_value = 1.0
    L.new(vo.outputs["Distance"], crater.inputs["Value"])
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3; ramp.color_ramp.elements[0].color = common.rgba("#6e6468")
    ramp.color_ramp.elements[1].position = 0.7; ramp.color_ramp.elements[1].color = common.rgba("#b9aba6")
    L.new(n1.outputs["Fac"], ramp.inputs["Fac"])
    dot = N.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = tuple(light)
    L.new(geo.outputs["Normal"], dot.inputs[0])
    day = N.new("ShaderNodeMapRange"); day.interpolation_type = "SMOOTHSTEP"
    day.inputs["From Min"].default_value = -0.35; day.inputs["From Max"].default_value = 0.6
    L.new(dot.outputs["Value"], day.inputs["Value"])
    m = N.new("ShaderNodeMath"); m.operation = "MULTIPLY"
    L.new(day.outputs["Result"], m.inputs[0]); L.new(crater.outputs["Result"], m.inputs[1])
    sc = N.new("ShaderNodeVectorMath"); sc.operation = "SCALE"
    L.new(ramp.outputs["Color"], sc.inputs[0]); L.new(m.outputs[0], sc.inputs["Scale"])
    em = N.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = 0.95
    L.new(sc.outputs[0], em.inputs["Color"])
    tr = N.new("ShaderNodeBsdfTransparent")
    vis = N.new("ShaderNodeMapRange")
    vis.inputs["To Min"].default_value = 0.35
    vis.inputs["To Max"].default_value = 0.95
    L.new(day.outputs["Result"], vis.inputs["Value"])
    add = N.new("ShaderNodeMixShader")
    L.new(vis.outputs["Result"], add.inputs["Fac"])
    L.new(tr.outputs[0], add.inputs[1]); L.new(em.outputs[0], add.inputs[2])
    L.new(add.outputs[0], out.inputs["Surface"])
    for k, mo in enumerate(moons):
        cu, cv = mo["sphere"]["centre_px"]
        ang = math.radians(mo["sphere"]["angular_radius_deg"])
        d = cm.rays(np.array(cu), np.array(cv)); d = d / np.linalg.norm(d)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=DIST * math.sin(ang), location=tuple(cm.pos + d * DIST), segments=64, ring_count=32)
        ob = bpy.context.active_object
        ob.name = f"CV_Moon_{k + 1}"
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        col.objects.link(ob)
        bpy.ops.object.shade_smooth()
        ob.rotation_euler = (0.7 * k, 1.3 * k, 0.4)
        for flag in ("visible_diffuse", "visible_shadow", "visible_transmission", "visible_volume_scatter"):
            setattr(ob, flag, False)
        ob.data.materials.append(mat)
