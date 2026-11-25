"""Assemble the Crimson Valley scene from its built parts and (optionally) render it.

  blender -b --factory-startup --python scene/assemble.py -- [--render out.png] [--scale 100] [--samples 256]
          [--parts a,b,c] [--skip x,y] [--out file.blend] [--no-save]

Appends parts/<name>.blend for every part in common.PART_ORDER that is built (or only --parts), runs
the parts' finalize(scene) hooks, and saves crimson_valley.blend (or --out). Without a "lighting" part
a plain preview sun is used, without "sky" a plain sky colour."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import bpy  # noqa: E402


def main():
    a = common.args_after_dashes()
    opt = {"--render": "", "--scale": "100", "--samples": "256", "--parts": "", "--skip": "", "--out": common.FINAL_BLEND}
    flags = set()
    i = 0
    while i < len(a):
        if a[i] in opt:
            opt[a[i]] = a[i + 1]
            i += 2
        else:
            flags.add(a[i])
            i += 1
    only = [p for p in opt["--parts"].split(",") if p]
    skip = [p for p in opt["--skip"].split(",") if p]
    t0 = time.time()
    scene = common.reset_scene()
    used = []
    for p in common.PART_ORDER:
        if (only and p not in only) or p in skip:
            continue
        if common.append_part(scene, p) is not None or os.path.exists(common.part_path(p)):
            used.append(p)
    for p in used:
        try:
            m = common.part_module(p)
        except ModuleNotFoundError:
            continue
        if hasattr(m, "finalize"):
            m.finalize(scene)
    if scene.world is None:
        common.preview_world(scene)
    if "lighting" not in used:
        common.preview_sun(scene)
    print(f"ASSEMBLED {used} in {time.time() - t0:.1f} s: {len(scene.objects)} objects")
    if "--no-save" not in flags:
        common.save_blend(os.path.abspath(opt["--out"]))
    if opt["--render"]:
        common.render(scene, os.path.abspath(opt["--render"]), scale=int(opt["--scale"]), samples=int(opt["--samples"]))


main()
