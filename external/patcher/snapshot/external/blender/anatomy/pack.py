# Copies the anatomy renders (build.py) into art/anatomy/ - the four layers,
# as the game loads them (AnatomyArt).
#   python3 external/blender/anatomy/pack.py
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "renders")
DST = os.path.join(HERE, "..", "..", "..", "art", "anatomy")
os.makedirs(DST, exist_ok=True)
for n in ("muscles", "veins", "nerves", "skeleton"):
    im = Image.open(os.path.join(SRC, n + ".png")).convert("RGBA")
    assert im.size == (4096, 1848), im.size
    im.save(os.path.join(DST, n + ".png"), optimize=True)
    print(n, im.size)
