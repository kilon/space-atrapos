import math, os, sys, bpy
from mathutils import Vector
out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
sc.render.resolution_x, sc.render.resolution_y = 800, 640
bpy.data.objects["AndroidRig"].data.pose_position = "REST"
for ob in bpy.data.objects:
    if ob.type == "MESH":
        ob.hide_render = not (ob.parent_type == "BONE" and ob.parent_bone in ("head",))
root = bpy.data.objects["AndroidRoot"]; root.rotation_euler = (0, 0, math.radians(64))
bpy.context.view_layer.update()
cam = bpy.data.objects["SpriteCam"]
tgt = root.matrix_world @ Vector((0, -0.04 - 0.27, 1.80 + 0.13 - 0.05))
e = math.radians(8)
cam.location = tgt + Vector((0, -math.cos(e), math.sin(e))) * 8
cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
cam.data.ortho_scale = 0.3
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
