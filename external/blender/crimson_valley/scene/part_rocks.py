"""The rock formations of the Crimson Valley scene: part "rocks".

  tools/cv part rocks --render renders/rocks/a.png --with sky,terrain,water

One object per group of formations (CV_Rocks_<group>), from meshes/rocks_<group>.npz - closed solids
whose camera-facing side follows the depth measured in the picture (tools/build_meshes.py explains how
they are made). The groups and the rock each is made of:

  near_hill        the hill the camera stands on: the left arch and its wall, the slope, the slabs
  outcrop          the bladed outcrop at the bottom right
  waterfall_cliff  pieces of the plateau the big waterfalls fall from
  river_spires     the small spires standing in the river
  mid_ridges       the ridges, spires and far spires in the mist left of centre (one continuous relief)
  mid_spires       detached pieces of the tall spires
  far_spires       detached pieces of the far spires seen under the left arch
  big_arch         the city's arch, the cliffs and towers behind it, the waterfall plateau
  right_towers     detached pieces of the towers
  far              the mountains on the horizon

Materials come from mat_rock.py (rock_material(name, preset)) when that module exists; until then a
plain rock colour. Vertex attributes (ref_uv, dist, veg, moss, mist, front) are on every mesh."""
import json
import os

import bpy
import numpy as np

import common

PRESETS = {
    "near_hill": "sandstone", "outcrop": "boulder", "waterfall_cliff": "cliff", "river_spires": "spire",
    "mid_ridges": "spire", "mid_spires": "spire", "far_spires": "far", "big_arch": "cliff",
    "right_towers": "cliff", "far": "far",
}
PLAIN = {
    "sandstone": "#8a6a52", "boulder": "#7a5c48", "cliff": "#5a4a44", "spire": "#6e5c52", "far": "#6f6a78",
}
TUNE = dict(crack_dark=0.35, block_crack=0.04, chip_crack=0.008, dist_from="attribute")
ATTRS = ("ref_uv", "dist", "veg", "moss", "mist", "front")


def plain_material(preset):
    name = "CV_Rock_Plain_" + preset
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat, nodes, links = common.new_material(name)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = common.rgba(PLAIN[preset])
    bsdf.inputs["Roughness"].default_value = 0.85
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def material_for(group):
    preset = PRESETS.get(group, "cliff")
    try:
        import mat_rock
        return mat_rock.rock_material("CV_Rock_" + group, preset=preset, **TUNE)
    except Exception as ex:          # the library is not there yet (or failed): plain colour
        print("rock material library not used for", group, "-", repr(ex)[:200])
        return plain_material(preset)


def build(col):
    with open(os.path.join(common.MESHES, "rocks.json")) as fh:
        info = json.load(fh)
    for group in info["groups"]:
        path = os.path.join(common.MESHES, f"rocks_{group}.npz")
        if not os.path.exists(path):
            continue
        m = common.load_npz_mesh(path)
        kind = m["face_kind"]
        mat = material_for(group)
        # the rock itself (front and back shells), and its unseen sides (the curtains) as a second
        # object, so the sides can be kept from casting shadows into the picture
        for suffix, sel in (("", kind != 3), ("_sides", kind == 3)):
            faces = m["faces"][sel]
            if not len(faces):
                continue
            used = np.unique(faces)
            remap = np.full(len(m["verts"]), -1, np.int64)
            remap[used] = np.arange(len(used))
            ob = common.mesh_object("CV_Rocks_" + group + suffix, m["verts"][used], remap[faces].astype(np.int32), col,
                                    attributes={k: m[k][used] for k in ATTRS if k in m}, smooth=not suffix)
            ob.data.materials.append(mat)
            ob["cv_group"] = group
            if suffix:
                ob.visible_shadow = os.environ.get("CV_SIDE_SHADOWS", "") == "1"
                ob.visible_camera = os.environ.get("CV_SIDES_VISIBLE", "") == "1"   # they show through in places: off for renders
            print(f"  {ob.name}: {len(used)} verts")
