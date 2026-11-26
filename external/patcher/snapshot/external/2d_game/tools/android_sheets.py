#!/usr/bin/env python3
"""The Minoan androids' pictures (SheetPuppet) from their green-screen sheets
(external/images/minoan_android_<weapon>.png; prompt:
external/prompt_templates/npc__minoan_android_weapons_prompt_template.txt):
rows of 8 figures, one per view, left to right: front, front 3/4 (down-right),
side (right), back 3/4 (up-right), back, back 3/4 (up-left), opposite side
(left), front 3/4 (down-left) - every view drawn, none mirrored.
    rifle  idle, aim                  -> art/android_rifle/
    bow    idle, aim (string drawn)   -> art/android_bow/
    axe    idle, raise1 (wind-up), aim (the strike, with its slash) -> art/android_axe/

    python3 -I tools/android_sheets.py [rifle|bow|axe ...] [--preview out.png]

The green is keyed out (and its spill on the edges taken off); rows and
columns are split at the emptiest lines near their even spacing, so a figure
keeps everything in its cell (an axe's slash too). Specks are dropped. A sheet
is scaled once (its idle row averages HEIGHT px tall), so every pose of it
matches. Writes <id>_anchors.json: the point each picture stands on - the
row's baseline under the middle of the body - so the poses don't jump.
"""
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(ROOT, "external", "images")
SHEETS = {
    "rifle": ("minoan_android_rifle.png", ["idle", "aim"]),
    "bow": ("minoan_android_bow.png", ["idle", "aim"]),
    "axe": ("minoan_android_axe.png", ["idle", "raise1", "aim"]),
}
DIRS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]   # the sheet's columns
HEIGHT = 255


def key(rgb):
    """Alpha: 0 on the green screen, soft on its edge; the green spill taken off."""
    a = rgb.astype(np.float32)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    over = g - np.maximum(r, b)              # how much greener than anything else
    alpha = np.clip(1.0 - (over - 30.0) / 50.0, 0.0, 1.0)
    g2 = np.minimum(g, np.maximum(r, b) + 12.0)   # despill
    out = np.dstack([r, np.where(alpha < 1.0, g2, g), b, alpha * 255.0])
    return out.clip(0, 255).astype(np.uint8)


def splits(profile, n):
    """n-1 cut positions: the emptiest line within a window round each even split."""
    size = len(profile)
    cuts = [0]
    for k in range(1, n):
        c = int(k * size / n)
        w = int(size / n * 0.3)
        seg = profile[c - w:c + w]
        cuts.append(c - w + int(np.argmin(seg)))
    cuts.append(size)
    return cuts


def drop_specks(rgba):
    solid = rgba[:, :, 3] > 60
    h, w = solid.shape
    seen = np.zeros_like(solid)
    comps = []
    for y0, x0 in zip(*np.nonzero(solid)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pix = []
        while q:
            y, x = q.popleft()
            pix.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and solid[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True
                    q.append((yy, xx))
        comps.append(pix)
    total = sum(len(c) for c in comps) or 1
    out = rgba.copy()
    for c in comps:
        if len(c) < 0.003 * total:
            for y, x in c:
                out[max(0, y - 1):y + 2, max(0, x - 1):x + 2, 3] = 0
    return out


def cut(name):
    fname, poses = SHEETS[name]
    rgba = key(np.asarray(Image.open(os.path.join(IMAGES, fname)).convert("RGB")))
    solid = rgba[:, :, 3] > 60
    rows = splits(solid.sum(axis=1), len(poses))
    out = {}                        # (pose, dir) -> (picture, anchor in it)
    for r, pose in enumerate(poses):
        band = rgba[rows[r]:rows[r + 1]]
        cols = splits((band[:, :, 3] > 60).sum(axis=0), 8)
        figs = [drop_specks(band[:, cols[c]:cols[c + 1]]) for c in range(8)]
        # The row's baseline: where the feet stand (the median of the figures' bottoms).
        bottoms = []
        for f in figs:
            ys = np.nonzero((f[:, :, 3] > 60).any(axis=1))[0]
            bottoms.append(ys.max())
        base = float(np.median(bottoms))
        for c, f in enumerate(figs):
            m = f[:, :, 3] > 60
            ys, xs = np.nonzero(m)
            y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            # The body's middle: the legs and kilt (40-85 % down the figure), the
            # widest weapon parts aside - the median opaque column there.
            hy0, hy1 = int(y0 + (y1 - y0) * 0.45), int(y0 + (y1 - y0) * 0.85)
            body_x = float(np.median(np.nonzero(m[hy0:hy1])[1])) if m[hy0:hy1].any() else (x0 + x1) / 2
            out[(pose, DIRS[c])] = (f[y0:y1, x0:x1], (body_x - x0, min(base, y1 - 1) - y0))
    idle_h = np.mean([out[("idle", d)][0].shape[0] for d in DIRS])
    k = HEIGHT / idle_h
    cid = "android_" + name
    dst = os.path.join(ROOT, "art", cid)
    os.makedirs(dst, exist_ok=True)
    anchors = {}
    pics = {}
    for (pose, d), (arr, (ax, ay)) in out.items():
        im = Image.fromarray(arr, "RGBA")
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        im.save(os.path.join(dst, "%s_%s_%s.png" % (cid, pose, d)))
        anchors["%s_%s" % (pose, d)] = [round(ax * k, 1), round(ay * k, 1)]
        pics[(pose, d)] = im
    with open(os.path.join(dst, cid + "_anchors.json"), "w") as fh:
        json.dump(anchors, fh, indent=1, sort_keys=True)
    print("%-6s %s" % (name, " ".join("%s:%dx%d" % (p, pics[(p, "s")].width, pics[(p, "s")].height) for p in poses)))
    return cid, poses, pics, anchors


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--") and not a.endswith(".png")]
    names = args or list(SHEETS)
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    sheets = [cut(n) for n in names]
    if preview:
        from PIL import ImageDraw
        cw, chh = 190, 300
        nrows = sum(len(p) for _, p, _, _ in sheets)
        sheet = Image.new("RGB", (cw * 8, chh * nrows), (70, 110, 60))
        d = ImageDraw.Draw(sheet)
        r = 0
        for cid, poses, pics, anchors in sheets:
            for pose in poses:
                for c, dr in enumerate(DIRS):
                    im = pics[(pose, dr)]
                    ax, ay = anchors["%s_%s" % (pose, dr)]
                    ox, oy = c * cw + cw // 2 - int(ax), r * chh + chh - 20 - int(ay)
                    sheet.paste(im, (ox, oy), im)
                    d.line([(c * cw + 20, r * chh + chh - 20), (c * cw + cw - 20, r * chh + chh - 20)], fill=(255, 255, 0))
                    d.text((c * cw + 4, r * chh + 4), "%s %s %s" % (cid[8:], pose, dr), fill=(255, 255, 255))
                r += 1
        sheet.save(preview)


if __name__ == "__main__":
    main()
