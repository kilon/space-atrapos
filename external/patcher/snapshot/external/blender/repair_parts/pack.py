# Packs the Repair Bay renders (build.py) into art/repair/: atlas.png + atlas.json
# ({name: [x, y, w, h]}) for the pieces, table.png and lid.png on their own.
#   python3 external/blender/repair_parts/pack.py
import json, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "renders")
DST = os.path.join(HERE, "..", "..", "..", "art", "repair")
os.makedirs(DST, exist_ok=True)
ALONE = ["table", "lid"]
PAD = 4
WIDTH = 2048

names = sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".png") and f[:-4] not in ALONE)
ims = {n: Image.open(os.path.join(SRC, n + ".png")).convert("RGBA") for n in names}
order = sorted(names, key=lambda n: -ims[n].height)
x = y = PAD
row = 0
at = {}
for n in order:
    w, h = ims[n].size
    if x + w + PAD > WIDTH:
        x = PAD
        y += row + 2 * PAD
        row = 0
    at[n] = [x, y, w, h]
    x += w + 2 * PAD
    row = max(row, h)
H = y + row + PAD
atlas = Image.new("RGBA", (WIDTH, H), (0, 0, 0, 0))
for n, (x, y, w, h) in at.items():
    atlas.paste(ims[n], (x, y))
atlas.save(os.path.join(DST, "atlas.png"), optimize=True)
with open(os.path.join(DST, "atlas.json"), "w") as f:
    json.dump(at, f, indent=1, sort_keys=True)
for n in ALONE:
    Image.open(os.path.join(SRC, n + ".png")).convert("RGBA").save(os.path.join(DST, n + ".png"), optimize=True)
print("atlas %dx%d, %d pieces" % (WIDTH, H, len(at)))
