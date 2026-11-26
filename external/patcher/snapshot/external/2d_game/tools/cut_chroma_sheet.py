#!/usr/bin/env python3
"""Cuts an 8-view character sheet on a flat chroma backdrop (purple, green...)
- two rows of four figures, no labels - into transparent pictures for a
SheetPuppet, plus a head-and-shoulders portrait.

    python3 -I tools/cut_chroma_sheet.py <sheet.png> <out_dir> <id> [--height 280]
        [--order sw,s,se,e,ne,n,nw,w] [--portrait s]

Writes <out_dir>/<id>_idle_<dir>.png (each figure cropped to itself, scaled
to --height px tall, its feet at the bottom) and <out_dir>/<id>_portrait.png
(the top of the --portrait view, square). --order names the eight figures
left to right, top row first (default: one turn of the character starting
front-left - sw s se e / ne n nw w). The backdrop is the sheet's border
colour; pixels near it become transparent, edges are softened and the
backdrop's tint is taken out of them (despill).
"""
import sys, argparse
import numpy as np
from PIL import Image, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("sheet"); ap.add_argument("out"); ap.add_argument("id")
ap.add_argument("--height", type=int, default=280)
ap.add_argument("--order", default="sw,s,se,e,ne,n,nw,w")
ap.add_argument("--portrait", default="s")
a = ap.parse_args()
order = a.order.split(",")
assert len(order) == 8

src = Image.open(a.sheet).convert("RGB")
im = np.asarray(src).astype(float)
H, W = im.shape[:2]
border = np.concatenate([im[:6].reshape(-1, 3), im[-6:].reshape(-1, 3), im[:, :6].reshape(-1, 3), im[:, -6:].reshape(-1, 3)])
BG = np.median(border, axis=0)
dist = np.sqrt(((im - BG) ** 2).sum(2))
# Opacity: 0 near the backdrop, 1 well away from it, a ramp between (soft edges).
alpha = np.clip((dist - 60.0) / 70.0, 0.0, 1.0)
# Keep only real figures: drop specks.
solid = Image.fromarray((alpha > 0.5).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))
solid = np.asarray(solid) > 0
alpha = alpha * solid
# Despill: take the backdrop's tint out of edge pixels (purple: too much red+blue vs green).
rgb = im.copy()
bg_dir = BG / max(np.linalg.norm(BG), 1)
grey = rgb.mean(2, keepdims=True)
edge = (1.0 - alpha)[..., None]
rgb = rgb * (1 - edge * 0.85) + grey * (edge * 0.85)
# Also cap the backdrop's dominant channels at the others' level across the figure (spill on cloth).
dom = np.argsort(BG)[::-1][:2]
other = [c for c in range(3) if c not in dom][0]
for c in dom:
    rgb[..., c] = np.minimum(rgb[..., c], np.maximum(rgb[..., other] * 1.35 + 18, rgb[..., c] * (1 - 0.6 * edge[..., 0])))

# The rows split at the emptiest line around the middle (figures may reach past it).
prof = (alpha > 0.3).sum(1)
mid = int(H * 0.4) + int(np.argmin(prof[int(H * 0.4):int(H * 0.6)]))
rows = [(0, mid), (mid, H)]
done = {}
for r, (y0, y1) in enumerate(rows):
    for k in range(4):
        x0, x1 = W * k // 4, W * (k + 1) // 4
        al = alpha[y0:y1, x0:x1]
        ys, xs = np.nonzero(al > 0.3)
        if len(ys) == 0:
            sys.exit("no figure in cell %d,%d" % (r, k))
        by0, by1, bx0, bx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        if bx0 == 0 or bx1 == x1 - x0 or by0 == 0 or by1 == y1 - y0:
            print("TOUCHES cell", r, k)
        cut = np.dstack([rgb[y0:y1, x0:x1], al * 255])[by0:by1, bx0:bx1]
        pic = Image.fromarray(np.clip(cut, 0, 255).astype(np.uint8), "RGBA")
        s = a.height / pic.height
        pic = pic.resize((max(1, round(pic.width * s)), a.height), Image.LANCZOS)
        d = order[r * 4 + k]
        pic.save("%s/%s_idle_%s.png" % (a.out, a.id, d))
        done[d] = pic
        print(d, pic.size)
# Portrait: the top of the chosen view (head and shoulders), square, on transparent.
p = done[a.portrait]
w = p.width
top = p.crop((0, 0, w, int(w * 1.0)))
side = max(top.size)
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
sq.paste(top, ((side - top.width) // 2, 0))
sq = sq.resize((256, 256), Image.LANCZOS)
sq.save("%s/%s_portrait.png" % (a.out, a.id))
print("portrait", sq.size)
