"""A contact sheet: preview renders side by side (+ the reference board), for checking."""
import sys
from PIL import Image
out, files = sys.argv[1], sys.argv[2:]
ims = [Image.open(f).convert("RGBA") for f in files]
h = max(i.height for i in ims)
sheet = Image.new("RGBA", (sum(i.width for i in ims), h), (90, 110, 90, 255))
x = 0
for i in ims:
    sheet.alpha_composite(i, (x, h - i.height))
    x += i.width
sheet.save(out)
