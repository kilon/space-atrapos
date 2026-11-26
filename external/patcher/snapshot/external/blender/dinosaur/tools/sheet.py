"""Tiles the animation stills of renders/frames/ into one picture per animation:  python -I sheet.py
(renders/walk.png, renders/attack.png; each still is labelled with its frame)."""
import glob
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RD = os.path.join(os.path.dirname(HERE), "renders")


def main():
    names = sorted({os.path.basename(f).rsplit("_", 1)[0] for f in glob.glob(os.path.join(RD, "frames", "*.png"))})
    for name in names:
        files = sorted(glob.glob(os.path.join(RD, "frames", name + "_*.png")))
        ims = [Image.open(f).convert("RGB") for f in files]
        w, h = ims[0].size
        cols = 4
        sheet = Image.new("RGB", (cols * w, ((len(ims) + cols - 1) // cols) * h), "white")
        d = ImageDraw.Draw(sheet)
        for i, (im, f) in enumerate(zip(ims, files)):
            x, y = (i % cols) * w, (i // cols) * h
            sheet.paste(im, (x, y))
            d.text((x + 8, y + 6), "frame " + os.path.basename(f).rsplit("_", 1)[1][:-4].lstrip("0"), fill=(255, 255, 0))
        out = os.path.join(RD, name.replace("DINO_", "").lower() + ".png")
        sheet.save(out)
        print(out, sheet.size)


if __name__ == "__main__":
    main()
