#!/usr/bin/env python3
"""The Minoan furniture (Furniture) from its sheet: external/images/
minoan_furniture_sheet.png (prompt: external/prompt_templates/
building__minoan_furniture_prompt_template.txt) - 8 x 6 pieces on magenta.

    python3 -I tools/furniture_sheet.py [--preview out.png]

Per cell: the magenta is keyed out, its fringe un-mixed from the edge pixels
(colour = (c - (1 - a) * magenta) / a); each solid piece goes to the cell its
bulk lies in (the generator doesn't keep to an even grid); specks are dropped.
Scale: SCALE (a floor cell's 2 x 2 m diamond is 155 px in the sheet - measured
on the first take, whose pieces stood on tiles - and 128 px in the game).
anchors.json: where each piece stands - the middle of its footprint: the
middle of its outline, a quarter of its width above its lowest pixel (a footprint as wide as the
piece is a diamond half as tall). Writes art/furniture/<name>.png.
"""
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "external", "images", "minoan_furniture_sheet.png")
OUT = os.path.join(ROOT, "art", "furniture")
SCALE = 128.0 / 155.0
NAMES = [
    ["throne_a", "chair_a", "bench_a", "couch_a", "bed_a", "dining_table_a", "tech_desk_a", "cabinet_a"],
    ["throne_b", "chair_b", "bench_b", "couch_b", "bed_b", "dining_table_b", "tech_desk_b", "cabinet_b"],
    ["pithoi", "chest", "round_table", "cauldron", "hearth", "fruit_basket", "amphora_rack", "water_basin"],
    ["altar", "goddess_statue", "bull_rhyton", "labrys_stand", "offering_table", "lamp_stand", "incense_burner", "lustral_basin"],
    ["console", "holo_table", "power_core", "med_pod", "weapon_rack", "charging_alcove", "workbench", "locker"],
    ["rug_spiral", "rug_dolphins", "cushions", "lilies", "olive_pot", "tablets", "loom", "shards"],
]


def key(rgb):
    """RGBA: alpha from how magenta a pixel is, the edges un-mixed from it."""
    f = rgb.astype(np.float32)
    r, g, b = f[:, :, 0], f[:, :, 1], f[:, :, 2]
    m = np.minimum(r, b) - g                      # magenta-ness
    a = np.clip(1.0 - (m - 45.0) / 90.0, 0.0, 1.0)
    mag = np.array([255.0, 0.0, 255.0])
    safe = np.maximum(a, 0.05)[:, :, None]
    un = (f - (1.0 - a[:, :, None]) * mag) / safe
    out = np.where((a < 1.0)[:, :, None], un, f).clip(0, 255)
    return np.dstack([out, a * 255.0]).astype(np.uint8)


def components(mask):
    h, w = mask.shape
    seen = np.zeros_like(mask)
    comps = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pix = []
        while q:
            y, x = q.popleft()
            pix.append((y, x))
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1), (y + 1, x + 1), (y - 1, x - 1), (y + 1, x - 1), (y - 1, x + 1)):
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    q.append((yy, xx))
        comps.append(np.array(pix))
    return comps


def main():
    rgba = key(np.asarray(Image.open(SHEET).convert("RGB")))
    H, W = rgba.shape[:2]
    rows, cols = len(NAMES), len(NAMES[0])
    solid = rgba[:, :, 3] > 40
    # Every solid piece to the cell its bulk lies in.
    owner = {}
    for comp in components(solid):
        span = comp[:, 1].max() - comp[:, 1].min()
        if span > 1.3 * W / cols:   # two touching pieces (the rugs): split at the cell line
            parts = {}
            for k, (y, x) in enumerate(comp):
                parts.setdefault(min(cols - 1, int(x * cols / W)), []).append(k)
            subs = [comp[idx] for idx in parts.values()]
        else:
            subs = [comp]
        for sub in subs:
            cy, cx = sub.mean(axis=0)
            r, c = min(rows - 1, int(cy * rows / H)), min(cols - 1, int(cx * cols / W))
            owner.setdefault((r, c), []).append(sub)
    os.makedirs(OUT, exist_ok=True)
    anchors, pics = {}, {}
    for r in range(rows):
        for c in range(cols):
            comps = owner.get((r, c), [])
            total = sum(len(p) for p in comps)
            keep = np.zeros((H, W), bool)
            for p in comps:
                if len(p) >= 0.01 * total:
                    keep[p[:, 0], p[:, 1]] = True
            # (the soft edge round what's kept)
            grown = keep.copy()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    grown |= np.roll(np.roll(keep, dy, 0), dx, 1)
            ys, xs = np.nonzero(keep)
            y0, y1, x0, x1 = ys.min() - 1, ys.max() + 2, xs.min() - 1, xs.max() + 2
            piece = rgba[y0:y1, x0:x1].copy()
            piece[:, :, 3] = np.where(grown[y0:y1, x0:x1], piece[:, :, 3], 0)
            im = Image.fromarray(piece, "RGBA")
            im = im.resize((max(1, round(im.width * SCALE)), max(1, round(im.height * SCALE))), Image.LANCZOS)
            name = NAMES[r][c]
            im.save(os.path.join(OUT, name + ".png"))
            # Where it stands: the middle of its outline (a footprint's projection is
            # symmetric about its centre), a quarter of its width above its lowest pixel.
            ax = (xs.min() + xs.max()) / 2.0 - x0
            ay = ys.max() - y0 - (xs.max() - xs.min()) / 4.0
            anchors[name] = [round(ax * SCALE, 1), round(ay * SCALE, 1)]
            pics[name] = im
    with open(os.path.join(OUT, "anchors.json"), "w") as fh:
        json.dump(anchors, fh, indent=1, sort_keys=True)
    print(len(pics), "pieces")
    if "--preview" in sys.argv:
        from PIL import ImageDraw
        out = sys.argv[sys.argv.index("--preview") + 1]
        cw, chh = 200, 230
        sheet = Image.new("RGB", (cw * cols, chh * rows), (120, 110, 95))
        d = ImageDraw.Draw(sheet)
        for r in range(rows):
            for c in range(cols):
                name = NAMES[r][c]
                ox, oy = c * cw + cw // 2, r * chh + chh - 50
                d.polygon([(ox, oy - 32), (ox + 64, oy), (ox, oy + 32), (ox - 64, oy)], outline=(255, 255, 0))
                im = pics[name]
                ax, ay = anchors[name]
                sheet.paste(im, (int(ox - ax), int(oy - ay)), im)
                d.text((c * cw + 4, r * chh + 4), name, fill=(255, 255, 255))
        sheet.save(out)


if __name__ == "__main__":
    main()
