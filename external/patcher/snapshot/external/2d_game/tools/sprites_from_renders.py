#!/usr/bin/env python3
"""Turns Blender renders of a character (<renders>/<frame>_<dir>.png, all from
the same orthographic camera, transparent background) into the game's sprites
art/<id>/<id>_<frame>_<dir>.png (SheetPuppet's 8 views per frame).

Every picture is cropped to what's opaque (plus a margin) and scaled by ONE
factor, the one that makes idle_s `--height` pixels tall - so all the frames
keep the same size.

If the renders come with meta.json ({"ground": [x, y]} - where the character
stands, the point it turns about, in render pixels; pirate_sprites.py writes
it), every sprite's anchor (that point, in the sprite) goes into
art/<id>/<id>_anchors.json {"<frame>_<dir>": [x, y]}: SheetPuppet stands the
sprite on it - steady through a walk cycle, whatever the feet are doing.

  python3 tools/sprites_from_renders.py <renders dir> <id> [--height 258]

e.g. external/blender/pirate/renders -> art/pirate/ (pirate_sprites.py renders them).
"""
import argparse
import glob
import json
import os

from PIL import Image

PAD = 3


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("renders")
    ap.add_argument("id")
    ap.add_argument("--height", type=int, default=258)
    a = ap.parse_args()
    files = sorted(glob.glob(os.path.join(a.renders, "*_*.png")))
    if not files:
        raise SystemExit("no renders in " + a.renders)
    meta_path = os.path.join(a.renders, "meta.json")
    ground = json.load(open(meta_path))["ground"] if os.path.exists(meta_path) else None
    ref = Image.open(os.path.join(a.renders, "idle_s.png")).convert("RGBA")
    l, t, r, b = ref.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    k = a.height / float(b - t)
    out_dir = os.path.join("art", a.id)
    os.makedirs(out_dir, exist_ok=True)
    anchors = {}
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]       # <frame>_<dir>
        im = Image.open(f).convert("RGBA")
        bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if bb is None:
            print("  (empty)", name)
            continue
        l, t, r, b = bb
        box = (max(0, l - PAD), max(0, t - PAD), min(im.width, r + PAD), min(im.height, b + PAD))
        im = im.crop(box)
        size = (max(1, round(im.width * k)), max(1, round(im.height * k)))
        # (resized premultiplied, so the edges don't pick up the black background)
        im = im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
        dst = os.path.join(out_dir, "%s_%s.png" % (a.id, name))
        im.save(dst, optimize=True)
        if ground:
            anchors[name] = [round((ground[0] - box[0]) * k, 1), round((ground[1] - box[1]) * k, 1)]
        print("  %-28s %dx%d" % (dst, size[0], size[1]))
    if anchors:
        with open(os.path.join(out_dir, "%s_anchors.json" % a.id), "w") as fh:
            json.dump(anchors, fh, indent=0, sort_keys=True)
    print("scale %.3f, %d sprites%s" % (k, len(files), ", anchors" if anchors else ""))


if __name__ == "__main__":
    main()
