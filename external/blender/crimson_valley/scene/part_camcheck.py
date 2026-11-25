"""A check of the camera, not part of the scene: glowing balls at known picture positions.

  blender -b --factory-startup --python scene/build_part.py -- camcheck --no-save --no-sun --render renders/camcheck.png --scale 100 --samples 4

Each ball is put where cvlib says a picture point lies in the world; tools/camcheck_verify.py then
finds the balls in the render and reports how many pixels off they are (it should be under one)."""
import bpy

import common

POINTS = [(100.5, 100.5, 50.0), (836.0, 470.5, 80.0), (1500.5, 800.5, 45.0), (300.5, 880.5, 15.6),
          (1560.5, 60.5, 198.0), (836.0, 432.0, 3000.0), (1150.5, 620.5, 118.0), (50.5, 900.5, 30.0)]


def build(col):
    cm = common.cam_model()
    mat, nodes, links = common.new_material("CV_CamCheck")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    em.inputs["Strength"].default_value = 5.0
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(em.outputs["Emission"], out.inputs["Surface"])
    for k, (u, v, z) in enumerate(POINTS):
        p = cm.unproject(u, v, z)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=6.0 * z / cm.f, location=tuple(p), segments=24, ring_count=12)
        ob = bpy.context.active_object
        ob.name = f"CV_CamCheck_{k}"
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        col.objects.link(ob)
        ob.data.materials.append(mat)
    w = bpy.data.worlds.new("CV_Black")
    nt = common.node_tree(w)
    nt.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    bpy.context.scene.world = w
