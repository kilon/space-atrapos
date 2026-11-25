"""Crop a region of a picture, enlarge it and (optionally) draw a labelled pixel grid on it.

  python -I crop.py <image> <x0> <y0> <x1> <y1> <out.png> [--scale 2] [--grid 50] [--to WxH]

Coordinates are in the picture's own pixels; with --to the picture is first resized to WxH (so a
half-size render can be cropped with reference coordinates: --to 1672x941). The grid labels are
those coordinates, for reading positions off the picture."""
import sys
from PIL import Image, ImageDraw, ImageFont


def main():
    a = sys.argv[1:]
    src, x0, y0, x1, y1, out = a[0], int(a[1]), int(a[2]), int(a[3]), int(a[4]), a[5]
    scale, grid, to = 2.0, 0, None
    i = 6
    while i < len(a):
        if a[i] == "--scale":
            scale = float(a[i + 1]); i += 2
        elif a[i] == "--grid":
            grid = int(a[i + 1]); i += 2
        elif a[i] == "--to":
            to = tuple(int(v) for v in a[i + 1].split("x")); i += 2
        else:
            i += 1
    img = Image.open(src).convert("RGB")
    if to and img.size != to:
        img = img.resize(to, Image.LANCZOS)
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(img.width, x1), min(img.height, y1)
    c = img.crop((x0, y0, x1, y1))
    c = c.resize((int(c.width * scale), int(c.height * scale)), Image.LANCZOS)
    if grid:
        d = ImageDraw.Draw(c, "RGBA")
        try:
            font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", 13)
        except OSError:
            font = ImageFont.load_default()
        gx = (x0 // grid + 1) * grid if x0 % grid else x0
        while gx < x1:
            X = (gx - x0) * scale
            d.line([(X, 0), (X, c.height)], fill=(255, 255, 255, 70), width=1)
            d.rectangle([X + 2, 2, X + 40, 18], fill=(0, 0, 0, 150))
            d.text((X + 4, 3), str(gx), fill=(255, 255, 0, 255), font=font)
            gx += grid
        gy = (y0 // grid + 1) * grid if y0 % grid else y0
        while gy < y1:
            Y = (gy - y0) * scale
            d.line([(0, Y), (c.width, Y)], fill=(255, 255, 255, 70), width=1)
            d.rectangle([2, Y + 2, 40, Y + 18], fill=(0, 0, 0, 150))
            d.text((4, Y + 3), str(gy), fill=(0, 255, 255, 255), font=font)
            gy += grid
    c.save(out)
    print(out, c.size)


if __name__ == "__main__":
    main()
