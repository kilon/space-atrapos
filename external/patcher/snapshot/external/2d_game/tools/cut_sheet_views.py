#!/usr/bin/env python3
"""Cuts an 8-view character sheet (two rows of four figures, angle labels
under them, a plain dark backdrop) into transparent pictures.

    python3 -I tools/cut_sheet_views.py <sheet.png> <out_dir> <prefix> [legend_px]

(legend_px: the sheet's legend panel on the left, skipped - 140 by default;
0 for a sheet without one, like the pirate's frame 3.)

Writes <out_dir>/<prefix>_<angle>.png for 315 0 45 90 / 135 180 225 270 at the
sheet's size. Each figure gets a whole cell (up to its neighbours' middles),
so thin parts - a rifle barrel - aren't cut off; only the figure and pieces
inside its outline are kept (not neighbours, labels or the legend). It prints
TOUCHES <angle> <side> if a figure reaches its cell's edge (check it by eye).
Then scale / mirror / name the views for the game (see the pirate in
external/patcher/history and art/pirate/).
"""
import sys, json
from collections import deque
from PIL import Image, ImageFilter
import numpy as np
src, out, prefix = sys.argv[1:4]
LEGEND = int(sys.argv[4]) if len(sys.argv) > 4 else 140
im = np.asarray(Image.open(src).convert('RGB')).astype(int)
H, W = im.shape[:2]
# The backdrop: the most common colour of the sheet's middle band.
def _backdrop(y0, y1):
    band = im[y0:y1, 150:W - 40].reshape(-1, 3)
    vals, counts = np.unique((band // 2) * 2, axis=0, return_counts=True)
    return vals[counts.argmax()] + 1
BG = _backdrop(int(H * 0.44), int(H * 0.46))
mask = np.abs(im - BG).sum(2) > 55
# Two rows of figures (labels below each), split at the emptiest line near the
# middle (sheets differ: the pirate's labels at y 445, the player's at 465).
rows_fill = mask[:, LEGEND + 10:W - 40].sum(1).astype(float)
mid0, mid1 = int(H * 0.40), int(H * 0.56)
smooth = np.convolve(rows_fill, np.ones(9) / 9, mode="same")
split = mid0 + int(np.argmin(smooth[mid0:mid1]))
BG = _backdrop(split - 3, split + 3)
mask = np.abs(im - BG).sum(2) > 55
cells = []
for (y0, y1) in [(0, split - 8), (split + 8, H - 60)]:
    cols = mask[y0:y1].sum(0)
    runs = []; on = False
    for x, c in enumerate(cols):
        if c > 25 and not on: s = x; on = True
        if c <= 25 and on: runs.append((s, x)); on = False
    if on: runs.append((s, W))
    runs = [r for r in runs if r[1] - r[0] > 60 and r[0] > LEGEND and r[1] < W - 40]
    # merge runs separated by small gaps (a rifle barrel etc.)
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < 25: merged[-1] = (merged[-1][0], r[1])
        else: merged.append(r)
    merged = sorted(merged, key=lambda r: -(r[1] - r[0]))[:4]
    merged.sort()
    # Whole cells: borders halfway between neighbouring figures (a thin rifle
    # barrel has too few pixels per column to be found by counting them).
    centres = [(r[0] + r[1]) / 2 for r in merged]
    for k, r in enumerate(merged):
        left = int(centres[k - 1] + 30) if k > 0 else max(0, int(centres[0] - 300))
        right = int(centres[k + 1] - 30) if k < 3 else min(W - 30, int(centres[3] + 300))
        cells.append((left, right, y0, min(H, y1 + 15)))
assert len(cells) == 8, cells
ANG = [315, 0, 45, 90, 135, 180, 225, 270]
DIRS = {0: "s", 45: "sw", 90: "w", 135: "ne", 180: "n", 225: "nw", 270: "e", 315: "se"}
STEP, LUM, SAT = 6, 120, 26
for ang, (x0, x1, y0, y1) in zip(ANG, cells):
    c = im[y0:y1, x0:x1]; h, w = c.shape[:2]
    dist = np.abs(c - BG).sum(2); lum = c.sum(2); sat = c.max(2) - c.min(2)
    bglike = dist < 12
    seen = np.zeros((h, w), bool)
    q = deque()
    for y in range(h):
        for x in (0, w - 1):
            if bglike[y, x]: seen[y, x] = True; q.append((y, x))
    for x in range(w):
        for y in (0, h - 1):
            if bglike[y, x] and not seen[y, x]: seen[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                ok = bglike[ny, nx] or (np.abs(c[ny, nx] - c[y, x]).sum() <= STEP and lum[ny, nx] < LUM and sat[ny, nx] < SAT)
                if ok: seen[ny, nx] = True; q.append((ny, nx))
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    # Keep the figure: its biggest piece, plus any piece lying within its outline
    # (a barrel tip separated by a gap) - not neighbours' parts, the legend or labels.
    from collections import deque as _dq
    on = alpha > 0
    lab = np.zeros((h, w), np.int32); comps = []
    for y in range(h):
        for x in range(w):
            if on[y, x] and not lab[y, x]:
                cid = len(comps) + 1; q = _dq([(y, x)]); lab[y, x] = cid; n = 0
                y0c, y1c, x0c, x1c = y, y, x, x
                while q:
                    cy, cx = q.popleft(); n += 1
                    y0c = min(y0c, cy); y1c = max(y1c, cy); x0c = min(x0c, cx); x1c = max(x1c, cx)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and on[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cid; q.append((ny, nx))
                comps.append((n, y0c, y1c, x0c, x1c))
    main = max(range(len(comps)), key=lambda i: comps[i][0])
    _, my0, my1, mx0, mx1 = comps[main]
    keep = np.zeros(len(comps) + 1, bool)
    for i, (n, a0, a1, b0, b1) in enumerate(comps):
        # (or reaching up to a quarter of its height above it if it comes down to its top:
        # a helmet the dark neck separates - not the angle label of the view above)
        above = a0 >= my0 - 20 or (a0 >= my0 - (my1 - my0) // 4 and a1 >= my0 - 6)
        if i == main or (n > 30 and above and a1 <= my1 and b0 >= mx0 - 40 and b1 <= mx1 + 40):
            keep[i + 1] = True
    alpha = np.where(keep[lab], 255, 0).astype(np.uint8)
    edge = []
    if alpha[:, :2].max() > 0: edge.append("left")
    if alpha[:, -2:].max() > 0: edge.append("right")
    if alpha[:2, :].max() > 0: edge.append("top")
    if edge: print("  TOUCHES", ang, edge)
    a = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    rgba = Image.fromarray(c.astype(np.uint8)).convert('RGBA'); rgba.putalpha(a)
    rgba = rgba.crop(rgba.getbbox())
    rgba.save('%s/%s_%d.png' % (out, prefix, ang))
print("bg", BG, "cells", cells)
