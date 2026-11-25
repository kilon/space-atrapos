# The automaton's anatomy (AnatomyArt): four layers - muscles, veins (the
# vessels and the heart), nerves (with the brain and the spinal cord) and the
# skeleton - each modelled here and rendered from the front, the body lying
# with its head to the left. Run headless:
#   blender -b -P external/blender/anatomy/build.py -- [layer ...] [--preview]
# then pack.py copies them into art/anatomy/.
import bpy, sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = "--preview" in ARGS
LAYERS = [a for a in ARGS if not a.startswith("--")] or ["skeleton", "muscles", "veins", "nerves"]

for layer in LAYERS:
    t0 = time.time()
    common.reset(samples=24 if PREVIEW else 128)
    common._mats.clear()
    mod = __import__({"veins": "vessels"}.get(layer, layer))
    mod.build()
    print("built", layer, "%.1f s" % (time.time() - t0))
    common.render(layer + ("_preview" if PREVIEW else ""), 0.5 if PREVIEW else 1.0)
    print("done", layer, "%.1f s" % (time.time() - t0))
