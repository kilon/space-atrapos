"""Look at the scene (or some of its parts) from other viewpoints, to check it holds up as 3D.

  blender -b --factory-startup --python scene/orbit.py -- <out prefix> [--parts a,b,c] [--blend file.blend]
          [--views right,high,top,left,close] [--scale 50] [--samples 32]

Assembles the given parts (default: all built ones; or opens --blend) and renders each view to
<out prefix>_<view>.png. Views: right / left (the camera moved 40 m sideways and turned back to the
valley), high (a hill-top view from behind and above), top (straight down on the valley), close (from
the river bank looking back at the hill the camera stands on)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import bpy  # noqa: E402
import mathutils  # noqa: E402

VIEWS = {   # name: (camera position, target, lens mm)
    "right": ((45.0, -5.0, 26.0), (10.0, 160.0, 12.0), 24.0),
    "left": ((-45.0, 0.0, 30.0), (30.0, 160.0, 12.0), 24.0),
    "high": ((20.0, -120.0, 110.0), (20.0, 170.0, 5.0), 28.0),
    "top": ((20.0, 150.0, 520.0), (20.0, 150.5, 0.0), 35.0),
    "close": ((60.0, 95.0, 6.0), (-20.0, 20.0, 18.0), 24.0),
}


def main():
    a = common.args_after_dashes()
    prefix = a[0]
    opt = {"--parts": "", "--blend": "", "--views": "right,high,top", "--scale": "50", "--samples": "32"}
    i = 1
    while i < len(a):
        opt[a[i]] = a[i + 1]
        i += 2
    if opt["--blend"]:
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(opt["--blend"]))
        scene = bpy.context.scene
        common.enable_gpu()
        scene.cycles.device = "GPU"
    else:
        scene = common.reset_scene()
        only = [p for p in opt["--parts"].split(",") if p]
        used = [p for p in common.PART_ORDER if (not only or p in only) and common.append_part(scene, p) is not None]
        for p in used:
            m = common.part_module(p)
            if hasattr(m, "finalize"):
                m.finalize(scene)
        if scene.world is None:
            common.preview_world(scene)
        if "lighting" not in used:
            common.preview_sun(scene)
    cam = scene.camera
    for name in opt["--views"].split(","):
        pos, target, lens = VIEWS[name]
        cam.location = pos
        d = mathutils.Vector(target) - mathutils.Vector(pos)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        common.render(scene, os.path.abspath(f"{prefix}_{name}.png"), scale=int(opt["--scale"]), samples=int(opt["--samples"]))


main()
