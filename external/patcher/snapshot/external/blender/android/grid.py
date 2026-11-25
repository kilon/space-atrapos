"""Frames cropped to the union of their figures, in a labelled grid (checking animations)."""
import sys
from PIL import Image, ImageDraw
out, cols, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
ims = [Image.open(f).convert("RGBA") for f in files]
box = None
for i in ims:
    b = i.getbbox()
    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
box = (box[0] - 6, box[1] - 6, box[2] + 6, box[3] + 6)
w, h = box[2] - box[0], box[3] - box[1] + 16
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGBA", (w * cols, h * rows), (90, 110, 90, 255))
d = ImageDraw.Draw(sheet)
for k, (f, i) in enumerate(zip(files, ims)):
    x, y = (k % cols) * w, (k // cols) * h
    sheet.alpha_composite(i.crop(box), (x, y + 16))
    d.text((x + 3, y + 2), f.split("/")[-1][:-4], fill=(255, 255, 0))
sheet.save(out)
