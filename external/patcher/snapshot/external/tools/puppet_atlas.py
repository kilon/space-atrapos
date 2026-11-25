#!/usr/bin/env python3
"""Packs a character's rendered animation frames into the game's atlases.

  python3 tools/puppet_atlas.py <skin> [--id <art id>] [--page 2048]

Reads external/blender/automaton/renders/<skin>/<clip>_<dir>_<frame>.png (all
from one orthographic camera, transparent; build.py renders them) and its
meta.json, and writes art/<id>_clips/ (SheetPuppet's clip mode):

  p00.png, p01.png ...   pages of trimmed frames (identical pictures stored once)
  clips.json             {"fps", "stand_h" (px: the standing figure's height),
                          "pages", "clips": {name: {"loop", "gun", "marks", "air": [px per frame],
                          "points": {name: {dir: [x, y]}}, "frames": {dir: [[page, x, y, w, h, ox, oy]...]}}}}
                         (ox, oy: the trimmed picture's corner from the point the character stands on)
  <id>_idle_s.png        the standing picture on its own (the health gauge's outline, portraits)
  web/                   the same at half size (web builds: phones)

The pages' .import files are written here too (VRAM compressed, high quality,
on desktops; lossless at half size for the web) - Godot keeps what it finds.
Skins: automaton -> player, pirate -> pirate.
"""
import argparse
import hashlib
import json
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENDERS = os.path.join(ROOT, "external", "blender", "automaton", "renders")
IDS = {"automaton": "player", "pirate": "pirate"}
DIRS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
PAD = 2

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=%d
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def pack(items, page):
    """Shelf packing, tallest first: items [(key, w, h)] -> {key: (page, x, y)}, pages."""
    order = sorted(items, key=lambda it: (-it[2], -it[1]))
    out = {}
    pages = 0
    shelves = []          # [page, y, h, x]
    for key, w, h in order:
        w2, h2 = w + PAD, h + PAD
        put = None
        for s in shelves:
            if s[2] >= h2 and s[3] + w2 <= page:
                put = s
                break
        if put is None:
            p = pages - 1
            y = 0
            last = [s for s in shelves if s[0] == p]
            if last:
                y = last[-1][1] + last[-1][2]
            if pages == 0 or y + h2 > page:
                pages += 1
                p = pages - 1
                y = 0
            put = [p, y, h2, 0]
            shelves.append(put)
        out[key] = (put[0], put[3], put[1])
        put[3] += w2
    return out, pages


def build(skin, art_id, page, scale, out_dir, compress_mode):
    src = os.path.join(RENDERS, skin)
    meta = json.load(open(os.path.join(src, "meta.json")))
    gx, gy = meta["ground"]
    files = {}
    for f in os.listdir(src):
        m = re.match(r"^(.+)_(e|se|s|sw|w|nw|n|ne)_(\d+)\.png$", f)
        if m:
            files[(m.group(1), m.group(2), int(m.group(3)))] = os.path.join(src, f)
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if re.match(r"^p\d+\.png$", f):
            os.remove(os.path.join(out_dir, f))
    uniq = {}        # hash -> (image, w, h)
    frames = {}      # (clip, dir, i) -> (hash, ox, oy)
    for key in sorted(files):
        im = Image.open(files[key]).convert("RGBA")
        g0x, g0y = gx, gy
        if scale != 1.0:
            size = (max(1, round(im.width * scale)), max(1, round(im.height * scale)))
            im = im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
            g0x, g0y = gx * scale, gy * scale
        bb = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
        if bb is None:
            bb = (0, 0, 1, 1)
        im = im.crop(bb)
        h = hashlib.md5(im.tobytes() + bytes(str(im.size), "ascii")).hexdigest()
        if h not in uniq:
            uniq[h] = im
        frames[key] = (h, round(bb[0] - g0x, 1), round(bb[1] - g0y, 1))
    where, pages = pack([(h, im.width, im.height) for h, im in uniq.items()], page)
    sheets = [Image.new("RGBA", (page, page), (0, 0, 0, 0)) for _ in range(pages)]
    for h, im in uniq.items():
        p, x, y = where[h]
        sheets[p].paste(im, (x, y))
    for i, s in enumerate(sheets):
        path = os.path.join(out_dir, "p%02d.png" % i)
        if i == pages - 1:               # (the last page: only as tall as it's filled)
            bb = s.getbbox()
            s = s.crop((0, 0, page, min(page, ((bb[3] + 3) // 4 + 1) * 4))) if bb else s
        s.save(path)
        imp = path + ".import"
        if not os.path.exists(imp) or ("compress/mode=%d" % compress_mode) not in open(imp).read():
            open(imp, "w").write(IMPORT % compress_mode)
    clips = {}
    for name, c in meta["clips"].items():
        fr = {}
        for d in DIRS:
            row = []
            for i in range(c["frames"]):
                if (name, d, i) not in frames:
                    row = None
                    break
                h, ox, oy = frames[(name, d, i)]
                p, x, y = where[h]
                row.append([p, x, y, uniq[h].width, uniq[h].height, ox, oy])
            if row is None:
                fr = None
                break
            fr[d] = row
        if fr is None:
            print("  (not rendered: %s)" % name)
            continue
        pts = {k: {d: [round(v[0] * scale, 1), round(v[1] * scale, 1)] for d, v in per.items()} for k, per in c.get("points", {}).items()}
        clips[name] = {"loop": c["loop"], "gun": c["gun"], "marks": c["marks"], "air": [round(a * scale, 1) for a in c["air"]],
                       "points": pts, "frames": fr}
    stand = "gun_idle" if "gun_idle" in clips else "idle"
    h0 = frames[(stand, "s", 0)][0]
    stand_h = uniq[h0].height
    with open(os.path.join(out_dir, "clips.json"), "w") as fh:
        json.dump({"fps": meta["fps"], "stand_h": stand_h, "pages": pages, "px_per_m": meta["px_per_m"] * scale, "clips": clips},
                  fh, separators=(",", ":"))
    portrait = "idle" if "idle" in clips else stand
    uniq[frames[(portrait, "s", 0)][0]].save(os.path.join(out_dir, "%s_idle_s.png" % art_id))
    px = sum(im.width * im.height for im in uniq.values())
    print("%s -> %s: %d frames (%d different), %d page(s) of %d px, %.1f M px, standing %d px" % (
        skin, os.path.relpath(out_dir, ROOT), len(frames), len(uniq), pages, page, px / 1e6, stand_h))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skin")
    ap.add_argument("--id", default=None)
    ap.add_argument("--page", type=int, default=2048)
    a = ap.parse_args()
    art_id = a.id or IDS.get(a.skin, a.skin)
    out = os.path.join(ROOT, "art", art_id + "_clips")
    build(a.skin, art_id, a.page, 1.0, out, 2)
    build(a.skin, art_id, a.page, 0.5, os.path.join(out, "web"), 0)


if __name__ == "__main__":
    sys.exit(main())
