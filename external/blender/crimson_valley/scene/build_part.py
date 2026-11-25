"""Build one part of the Crimson Valley scene, alone, and (optionally) render it from the camera.

  blender -b --factory-startup --python scene/build_part.py -- <name> [--render out.png] [--scale 50]
          [--samples 48] [--with sky,planet,...] [--no-save] [--no-sun] [--transparent]

Runs scene/part_<name>.py's build(col) in an empty scene (camera and render settings from common.py),
saves parts/<name>.blend, and with --render writes a picture of the camera view. --with brings in other
parts that are already built (their saved parts/<x>.blend), to see this one in context. Without a
"lighting" part in --with a plain preview sun is added (--no-sun: none), and without the "sky" part a
plain preview sky colour - both for the picture only, they are not saved into the part.
--transparent renders on a transparent background (RGBA), to look at the part's own outline."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import bpy  # noqa: E402


def main():
    a = common.args_after_dashes()
    name = a[0]
    opt = {"--render": "", "--scale": "50", "--samples": "48", "--with": ""}
    flags = set()
    i = 1
    while i < len(a):
        if a[i] in opt:
            opt[a[i]] = a[i + 1]
            i += 2
        else:
            flags.add(a[i])
            i += 1
    t0 = time.time()
    scene = common.reset_scene()
    col = common.new_collection(scene, name)
    mod = common.part_module(name)
    mod.build(col)
    print(f"BUILT part {name}: {len(col.all_objects)} objects in {time.time() - t0:.1f} s")
    if "--no-save" not in flags:
        common.save_blend(common.part_path(name))
    if opt["--render"]:
        others = [p for p in opt["--with"].split(",") if p and p != name]
        for p in common.PART_ORDER:
            if p in others:
                if common.append_part(scene, p) is None and not os.path.exists(common.part_path(p)):
                    print("part", p, "is not built yet - left out")
        mods = [(p, common.part_module(p)) for p in [name] + others if os.path.exists(common.part_path(p)) or p == name]
        for p, m in mods:
            if hasattr(m, "finalize"):
                m.finalize(scene)
        if scene.world is None:
            common.preview_world(scene)
        if "lighting" not in others and name != "lighting" and "--no-sun" not in flags:
            common.preview_sun(scene)
        if "--transparent" in flags:
            scene.render.film_transparent = True
            scene.render.image_settings.color_mode = "RGBA"
        common.render(scene, os.path.abspath(opt["--render"]), scale=int(opt["--scale"]), samples=int(opt["--samples"]))


main()
