"""Head-only renders matching the reference board's head panel (3/4, snout to
screen right, a little from below eye level) plus side / front / top views."""
import math, os, sys, bpy
from mathutils import Vector
out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
sc.render.resolution_x, sc.render.resolution_y = 800, 640
cam = bpy.data.objects["SpriteCam"]
root = bpy.data.objects["AndroidRoot"]
tgt = Vector((0, -0.12, 1.98))
views = {"ref": (math.radians(62), 6, 0.95), "side": (math.pi / 2, 0, 0.95), "front": (0.0, 0, 0.95),
         "top": (math.pi / 2, 70, 0.95), "q": (math.radians(35), 15, 0.95), "game": (math.radians(45), 30, 0.95),
         "back": (math.radians(150), 20, 0.95)}
only = sys.argv[sys.argv.index("--") + 2:] or list(views)
bpy.data.objects["AndroidRig"].data.pose_position = "REST"
for ob in bpy.data.objects:
    if ob.type == "MESH":
        ob.hide_render = not (ob.parent_type == "BONE" and ob.parent_bone in ("head", "neck"))
for name in only:
    yaw, el, scale = views[name]
    root.rotation_euler = (0, 0, yaw)
    e = math.radians(el)
    cam.location = tgt + Vector((0, -math.cos(e), math.sin(e))) * 8
    cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
    cam.data.ortho_scale = scale
    sc.render.filepath = os.path.join(out, "head_%s.png" % name)
    bpy.ops.render.render(write_still=True)
