"""The clear sky of the Crimson Valley scene: part "sky" (the world CV_World).

  tools/cv part sky --render renders/sky/sky.png --no-sun

A sunset gradient by view direction: steel blue overhead, violet-grey lower, a peach band at the
horizon, and a warm glow around the direction of the picture's brightest sky (behind the big arch, at
picture point (1150, 380)); below the horizon a dark warm haze. The colours are sampled from the
picture's clear patches. It is the scene's ambient light and what shows past the cloud card's edges."""
import bpy
import numpy as np

import common


def build(col):
    cm = common.cam_model()
    w = bpy.data.worlds.new(common.WORLD_NAME)
    nt = common.node_tree(w)
    nt.nodes.clear()
    N, L = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputWorld")
    bg = N.new("ShaderNodeBackground")
    geo = N.new("ShaderNodeTexCoord")             # Generated = the view direction in the world shader
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(geo.outputs["Generated"], sep.inputs[0])
    ramp = N.new("ShaderNodeValToRGB")            # by height of the direction: z = sin(elevation)
    mp = N.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -0.25
    mp.inputs["From Max"].default_value = 0.75
    L.new(sep.outputs["Z"], mp.inputs["Value"])
    L.new(mp.outputs["Result"], ramp.inputs["Fac"])
    stops = [(0.0, "#2e2224"), (0.22, "#4a3434"), (0.25, "#e8a070"), (0.30, "#c98f86"), (0.40, "#8f8298"),
             (0.60, "#66708e"), (1.0, "#4a5878")]
    cr = ramp.color_ramp
    while len(cr.elements) < len(stops):
        cr.elements.new(0.5)
    for el, (p, c) in zip(cr.elements, stops):
        el.position = p
        el.color = common.rgba(c)
    # the glow: a lobe around the direction of the brightest sky
    g = cm.rays(np.array(1150.0), np.array(385.0))
    g = g / np.linalg.norm(g)
    dot = N.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = tuple(g)
    L.new(geo.outputs["Generated"], dot.inputs[0])
    pw = N.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 10.0
    cl = N.new("ShaderNodeClamp")
    L.new(dot.outputs["Value"], cl.inputs["Value"])
    L.new(cl.outputs["Result"], pw.inputs[0])
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "ADD"
    mix.inputs[7].default_value = common.rgba("#b05a20")
    L.new(pw.outputs["Value"], mix.inputs[0])
    L.new(ramp.outputs["Color"], mix.inputs[6])
    L.new(mix.outputs[2], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.5
    L.new(bg.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = w
