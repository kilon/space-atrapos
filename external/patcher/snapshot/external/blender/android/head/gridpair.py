"""Reference | render (same reference-pixel frame, OV_W=1000 render head/ov_wide.png) with a labelled
grid, cropped to x0..x1, y0..y1 (reference px), scaled -> head/gridpair.png."""
import sys
from PIL import Image, ImageDraw
x0, y0, x1, y1 = [int(v) for v in sys.argv[1:5]]
k = float(sys.argv[5]) if len(sys.argv) > 5 else 1.5
step = int(sys.argv[6]) if len(sys.argv) > 6 else 20
ref = Image.open("head/ref_head.png").convert("RGBA")
ren = Image.new("RGBA", (1000, 640), (90, 110, 90, 255)); ren.alpha_composite(Image.open("head/ov_wide.png").convert("RGBA"))
big = Image.new("RGBA", (1000, 700), (40, 40, 40, 255)); big.paste(ref, (0, 0))
a = big.crop((x0, y0, x1, y1))
b = ren.crop((x0 + 200, y0 + 20, x1 + 200, y1 + 20))
W, H = int((x1 - x0) * k), int((y1 - y0) * k)
out = Image.new("RGB", (2 * W + 10, H), (0, 0, 0))
for i, im in enumerate((a, b)):
    im = im.resize((W, H), Image.LANCZOS).convert("RGB")
    d = ImageDraw.Draw(im)
    for x in range((x0 // step + 1) * step, x1, step):
        X = (x - x0) * k
        d.line([(X, 0), (X, H)], fill=(255, 0, 255) if x % 100 == 0 else (255, 255, 255), width=1)
        d.text((X + 2, 2), str(x), fill=(255, 255, 0))
    for y in range((y0 // step + 1) * step, y1, step):
        Y = (y - y0) * k
        d.line([(0, Y), (W, Y)], fill=(255, 0, 255) if y % 100 == 0 else (255, 255, 255), width=1)
        d.text((2, Y + 2), str(y), fill=(255, 255, 0))
    out.paste(im, (i * (W + 10), 0))
out.save("head/gridpair.png")
