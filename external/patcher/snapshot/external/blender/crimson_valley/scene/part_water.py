"""The river of the Crimson Valley scene: part "water".

  tools/cv part water --render renders/water/a.png --with sky,clouds,terrain,rocks

CV_Water is the plane z = 0 under the whole valley floor (meshes/water.npz). The terrain's river beds
are carved below it exactly where the picture has water, and its banks are kept above it, so the
river's outline is the picture's. The material is still water: a mirror with a faint tint and soft,
slow ripples that stretch the reflections of the sky and the rocks a little, as in the picture."""
import os

import bpy

import common


def water_material():
    mat, nodes, links = common.new_material("CV_Water")
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = common.rgba("#141c20")
    bsdf.inputs["Roughness"].default_value = 0.06
    bsdf.inputs["IOR"].default_value = 1.333
    bsdf.inputs["Specular IOR Level"].default_value = 1.0
    bsdf.inputs["Coat Weight"].default_value = 0.6          # a brighter mirror at shallow angles
    bsdf.inputs["Coat Roughness"].default_value = 0.04
    geo = nodes.new("ShaderNodeNewGeometry")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (0.5, 0.12, 1.0)   # ripples stretched across the view
    links.new(geo.outputs["Position"], mapping.inputs["Vector"])
    noise = nodes.new("ShaderNodeTexNoise")
    noise.noise_type = "FBM"
    noise.inputs["Scale"].default_value = 1.2
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.55
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.06
    bump.inputs["Distance"].default_value = 0.05
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Coat Normal"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build(col):
    m = common.load_npz_mesh(os.path.join(common.MESHES, "water.npz"))
    ob = common.mesh_object("CV_Water", m["verts"], m["faces"], col, smooth=False)
    ob.data.materials.append(water_material())
    ob.visible_shadow = False
