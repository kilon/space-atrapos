"""Renders the head alone at the reference panel's scale and angle (ref pixel
(300, 300) = the model's HEAD point at the image centre), for overlaying."""
import math, os, sys, bpy
from mathutils import Vector
sys.path.insert(0, os.path.dirname(bpy.data.filepath))
out = sys.argv[sys.argv.index("--") + 1]
yaw = math.radians(float(sys.argv[sys.argv.index("--") + 2]) if len(sys.argv) > sys.argv.index("--") + 2 else 64)
sc = bpy.context.scene
W = int(os.environ.get("OV_W", "800"))
sc.render.resolution_x, sc.render.resolution_y = W, 640
for ob in bpy.data.objects:
    if ob.type == "MESH":
        ob.hide_render = not (ob.parent_type == "BONE" and ob.parent_bone in ("head", "neck"))
cam = bpy.data.objects["SpriteCam"]
root = bpy.data.objects["AndroidRoot"]
root.rotation_euler = (0, 0, yaw)
bpy.data.objects["AndroidRig"].data.pose_position = "REST"   # (not the idle clip's frame)
bpy.context.view_layer.update()
LIFT = 0.13
tgt = Vector((0.0, -0.04, 1.80 + LIFT))       # HEAD (lifted), turned with the root
tgt = root.matrix_world @ tgt
e = math.radians(8)
cam.location = tgt + Vector((0, -math.cos(e), math.sin(e))) * 8
cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
cam.data.ortho_scale = W * 0.00101
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
