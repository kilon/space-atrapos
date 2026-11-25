"""Close-up renders (head, torso, legs) from a few angles: checking details."""
import math, os, sys, bpy
from mathutils import Vector
out = sys.argv[sys.argv.index("--") + 1]
sc = bpy.context.scene
sc.render.resolution_x = sc.render.resolution_y = 700
cam = bpy.data.objects["SpriteCam"]
root = bpy.data.objects["AndroidRoot"]
keep = (cam.location.copy(), cam.rotation_quaternion.copy(), cam.data.ortho_scale)
for name, tgt, scale in (("head", (0, -0.05, 2.0), 0.9), ("torso", (0, 0, 1.45), 1.0), ("legs", (0, 0, 0.55), 1.2)):
    for d, a in (("s", 0.0), ("se", math.pi / 4), ("e", math.pi / 2), ("n", math.pi)):
        root.rotation_euler = (0, 0, a)
        t = Vector(tgt)
        el = math.radians(20)
        cam.location = t + Vector((0, -math.cos(el), math.sin(el))) * 8
        cam.rotation_quaternion = (t - cam.location).to_track_quat("-Z", "Y")
        cam.data.ortho_scale = scale
        sc.render.filepath = os.path.join(out, "%s_%s.png" % (name, d))
        bpy.ops.render.render(write_still=True)
