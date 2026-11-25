"""The valley floor of the Crimson Valley scene: part "terrain".

  tools/cv part terrain --render renders/terrain/a.png --with sky,rocks,water

CV_Terrain is one sheet (meshes/terrain.npz, from tools/build_meshes.py): the valley floor at the height
measured in the picture, filled in where rocks hide it and past the picture's edges, with river beds
carved under the picture's water, and an apron of flat ground around it out to 30 km, so the world has
a ground everywhere. Vertex attributes: ref_uv, dist, veg (red plant cover), moss, mist, seen (1 where the
floor is visible in the picture), wet (1 at the water's edge and under water)."""
import os

import bpy
import numpy as np

import common

ATTRS = ("ref_uv", "dist", "veg", "moss", "mist", "front", "seen", "wet")


def ground_material():
    """Soil with red plant cover where the picture has it (the veg attribute), darker when wet."""
    mat, nodes, links = common.new_material("CV_Ground")
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.9
    veg = nodes.new("ShaderNodeAttribute")
    veg.attribute_name = "veg"
    wet = nodes.new("ShaderNodeAttribute")
    wet.attribute_name = "wet"
    geo = nodes.new("ShaderNodeNewGeometry")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.noise_type = "FBM"
    noise.inputs["Scale"].default_value = 0.35
    noise.inputs["Detail"].default_value = 6.0
    links.new(geo.outputs["Position"], noise.inputs["Vector"])
    soil = nodes.new("ShaderNodeMix")
    soil.data_type = "RGBA"
    soil.inputs[6].default_value = common.rgba("#5e4338")
    soil.inputs[7].default_value = common.rgba("#8a6048")
    links.new(noise.outputs["Fac"], soil.inputs[0])
    red = nodes.new("ShaderNodeMix")
    red.data_type = "RGBA"
    red.inputs[7].default_value = common.rgba("#5a1410")
    links.new(veg.outputs["Fac"], red.inputs[0])
    links.new(soil.outputs[2], red.inputs[6])
    dark = nodes.new("ShaderNodeMix")
    dark.data_type = "RGBA"
    dark.blend_type = "MULTIPLY"
    dark.inputs[7].default_value = (0.45, 0.45, 0.5, 1.0)
    links.new(wet.outputs["Fac"], dark.inputs[0])
    links.new(red.outputs[2], dark.inputs[6])
    links.new(dark.outputs[2], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build(col):
    m = common.load_npz_mesh(os.path.join(common.MESHES, "terrain.npz"))
    ob = common.mesh_object("CV_Terrain", m["verts"], m["faces"], col,
                            attributes={k: m[k] for k in ATTRS if k in m})
    ob.data.materials.append(ground_material())
    print(f"  CV_Terrain: {len(m['verts'])} verts")
