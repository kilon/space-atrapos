"""Writes data/sprites/sizes.json: every sprite's pixel size, its two main colours and
where its opaque part sits - what the game needs to draw a procedural placeholder for a
sprite before its picture is loaded (PlaceholderArt, ProcArt.sprite).
  "<key>": [w, h, "rrggbb" (main colour), "rrggbb" (its shade), x0, y0, x1, y1]
  (x0..y1: the opaque part's box, in hundredths of the width / height)
Run after adding or changing sprites:  ~/.cache/sa-venv/bin/python tools/sprite_sizes.py
(needs Pillow)"""
import json, os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "sprites")
out = {}
for f in sorted(os.listdir(DIR)):
    if not f.endswith(".png"):
        continue
    im = Image.open(os.path.join(DIR, f)).convert("RGBA")
    w, h = im.size
    small = im.resize((max(1, w // 8), max(1, h // 8)), Image.BILINEAR)
    px = [p for p in small.getdata() if p[3] > 128]
    if not px:
        px = [(128, 128, 128, 255)]
    # The main colour: the opaque pixels' mean; its shade: the mean of the darker half.
    lum = lambda p: p[0] * 0.3 + p[1] * 0.59 + p[2] * 0.11
    px.sort(key=lum)
    def mean(ps):
        n = len(ps)
        return "%02x%02x%02x" % tuple(int(sum(p[i] for p in ps) / n) for i in range(3))
    main = mean(px)
    shade = mean(px[: max(1, len(px) // 2)])
    box = im.getchannel("A").point(lambda a: 255 if a > 64 else 0).getbbox() or (0, 0, w, h)
    out[f[:-4]] = [w, h, main, shade,
                   int(100 * box[0] / w), int(100 * box[1] / h), int(100 * box[2] / w), int(100 * box[3] / h)]
json.dump(out, open(os.path.join(DIR, "sizes.json"), "w"), separators=(",", ":"))
print(len(out), "sprites")
