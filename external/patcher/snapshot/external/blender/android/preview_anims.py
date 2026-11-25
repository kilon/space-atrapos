"""Renders a strip of clip frames from one direction (checking the animations)."""
import os, sys, bpy
sys.path.insert(0, os.path.dirname(bpy.data.filepath))
import android_anims as a
argv = sys.argv[sys.argv.index("--") + 1:]
out, d = argv[0], argv[1]
sc = bpy.context.scene
sc.render.resolution_x = sc.render.resolution_y = 400
root = bpy.data.objects["AndroidRoot"]
for clip, frames in (("Walk", range(0, 28, 4)), ("Aim", (0, 5, 9)), ("Fire", (0, 2)), ("Idle", (0, 25))):
    a.use_clip(clip)
    for k in frames:
        sc.frame_set(k + 1)
        root.rotation_euler = (0, 0, a.facing_angle(d))
        sc.render.filepath = os.path.join(out, "%s_%02d_%s.png" % (clip.lower(), k + 1, d))
        bpy.ops.render.render(write_still=True)
