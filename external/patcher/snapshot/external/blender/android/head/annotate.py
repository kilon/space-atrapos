"""head/zoom.png (reference | model) with numbered problem areas and a legend -> head/face_review.png."""
from PIL import Image, ImageDraw, ImageFont
import sys
SRC = sys.argv[1] if len(sys.argv) > 1 else "head/zoom.png"
DST = sys.argv[2] if len(sys.argv) > 2 else "head/face_review.png"
im = Image.open(SRC).convert("RGB")
W, H = im.size
LEG = 470 if len(__import__('sys').argv) < 3 else 14 + 37 * 12 + 10
out = Image.new("RGB", (W, H + LEG), (24, 26, 30))
out.paste(im, (0, 0))
d = ImageDraw.Draw(out)
try:
    f_num, f_txt, f_hd = ImageFont.load_default(26), ImageFont.load_default(21), ImageFont.load_default(24)
except TypeError:
    f_num = f_txt = f_hd = ImageFont.load_default()
# number: (ref point, model point, radius, title, what's wrong)
NOTES = [
    ((450, 280), (1315, 280), 55, "Eye", "Reference: slanted almond, pointed at both ends. Model: rounded hexagon in an oversized black blob."),
    ((745, 500), (1585, 525), 65, "Beak", "Reference: long ivory hook curving down to a point. Model: short, blunt, boxy."),
    ((700, 400), (1555, 400), 50, "Nose plate", "Reference: broad flat plate, horn on top of it. Model: horn ring at the very tip, plate too small."),
    ((330, 205), (1060, 75), 55, "Cranium shape", "Reference: stepped plates rising to the horn. Model: one long flat-topped box."),
    ((680, 150), (1600, 205), 55, "Far horn", "Reference: comes from behind, points up-forward. Model: lower, crosses the near horn's base."),
    ((430, 440), (1250, 400), 60, "Cheek plates", "Reference: 5-6 small stepped plates under the eye. Model: two big flat slabs."),
    ((575, 495), (1440, 505), 50, "Jaw", "Reference: angular gold jaw plate, dark mouth inside. Model: thin gold sliver."),
    ((225, 350), (1085, 355), 60, "Ear fitting", "Reference: big boss, earring hangs from it, arm to a bracket. Model: small boss, floating bar."),
    ((265, 130), (1110, 105), 40, "Cranium light", "Reference: thin slot slanting along the plate edge. Model: upright boxy rectangle."),
    ((80, 530), (1010, 570), 60, "Neck", "Reference: dark cables with grey segmented hoses. Model: big grey slabs."),
    (None, (1060, 220), 70, "Stray seams", "Model: dark lines cutting across the temple plates that aren't in the painting."),
    ((40, 300), (900, 300), 0, "Ink outline", "Reference: bold black outline everywhere. Model: thinner brown outline, missing on inner edges."),
]
RED = (255, 60, 60)
for i, (pr, pm, r, title, text) in enumerate(NOTES, 1):
    if not r:
        continue                      # (no single spot: in the legend only)
    for (x, y) in [q for q in (pr, pm) if q]:
        if r:
            d.ellipse((x - r, y - r, x + r, y + r), outline=RED, width=4)
        bx, by = x + (r * 0.7 if r else 0), y - (r * 0.7 if r else 0)
        d.ellipse((bx - 17, by - 17, bx + 17, by + 17), fill=RED)
        d.text((bx, by), str(i), font=f_num, fill=(255, 255, 255), anchor="mm")
d.text((14, 10), "REFERENCE", font=f_hd, fill=(255, 255, 255), stroke_width=3, stroke_fill=(0, 0, 0))
d.text((W // 2 + 14, 10), "3D MODEL", font=f_hd, fill=(255, 255, 255), stroke_width=3, stroke_fill=(0, 0, 0))
LEG_ROWS = len(NOTES)
for i, (_, _, _, title, text) in enumerate(NOTES, 1):
    x, y = 20, H + 14 + (i - 1) * 37
    d.ellipse((x, y, x + 30, y + 30), fill=RED)
    d.text((x + 15, y + 15), str(i), font=f_num, fill=(255, 255, 255), anchor="mm")
    d.text((x + 42, y + 3), title, font=f_hd, fill=(255, 220, 120))
    d.text((x + 230, y + 5), text, font=f_txt, fill=(225, 225, 225))
out.save(DST)
