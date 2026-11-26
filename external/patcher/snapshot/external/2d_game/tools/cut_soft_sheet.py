#!/usr/bin/env python3
"""Cuts an 8-view prop sheet (two rows of four) whose backdrop is a smooth
gradient (glows, vignettes - not a flat colour) into transparent pictures.

    python3 -I tools/cut_soft_sheet.py <sheet.png> <out_dir> <prefix> --views a,b,c,d,e,f,g,h
        [--keep sw,se,...] [--height 200] [--smooth 7.0]

The backdrop is told apart by being smooth: pixels whose local contrast is
low and that connect to the cell's border through other smooth pixels are
backdrop; the rest is the object (smooth patches it encloses - a cushion -
stay). Edges are softened by a pixel. --views names the eight figures left to
right, top row first; --keep writes only those; each picture is cropped to
the object and scaled to --height px tall: <out_dir>/<prefix>_<view>.png.
"""
import argparse
import numpy as np
from PIL import Image, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("sheet"); ap.add_argument("out"); ap.add_argument("prefix")
ap.add_argument("--views", required=True)
ap.add_argument("--keep", default="")
ap.add_argument("--height", type=int, default=200)
ap.add_argument("--smooth", type=float, default=7.0)
a = ap.parse_args()
views = a.views.split(",")
keep = set(a.keep.split(",")) if a.keep else set(views)
src = Image.open(a.sheet).convert("RGB")
W, H = src.size
blur = np.asarray(src.filter(ImageFilter.GaussianBlur(1.5))).astype(float)
gx = np.abs(np.diff(blur, axis=1, prepend=blur[:, :1])).sum(2)
gy = np.abs(np.diff(blur, axis=0, prepend=blur[:1])).sum(2)
grad = np.maximum(gx, gy)
smooth = np.asarray(Image.fromarray((grad < a.smooth).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(3))) > 0
rgb = np.asarray(src)
for r in range(2):
    for k in range(4):
        name = views[r * 4 + k]
        if name not in keep:
            continue
        x0, x1, y0, y1 = W * k // 4, W * (k + 1) // 4, H * r // 2, H * (r + 1) // 2
        sm = smooth[y0:y1, x0:x1]
        bg = np.zeros_like(sm)
        bg[0, :] = sm[0, :]; bg[-1, :] = sm[-1, :]; bg[:, 0] = sm[:, 0]; bg[:, -1] = sm[:, -1]
        while True:   # grow the backdrop through smooth pixels
            g = bg.copy()
            g[1:] |= bg[:-1]; g[:-1] |= bg[1:]; g[:, 1:] |= bg[:, :-1]; g[:, :-1] |= bg[:, 1:]
            g &= sm
            if (g == bg).all():
                break
            bg = g
        obj = ~bg
        # Keep the biggest blob (drop specks), fill it out by a pixel back (the smoothness test ate its rim).
        m = Image.fromarray(obj.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))
        alpha = np.asarray(m.filter(ImageFilter.GaussianBlur(0.8))).astype(float) / 255.0
        alpha = np.clip((alpha - 0.15) / 0.7, 0, 1) * obj.astype(float) ** 0 
        ys, xs = np.nonzero(alpha > 0.5)
        # Despill: edge pixels tinted by the backdrop (here a purple floor glow:
        # more blue than red) fade out; inside the object nothing changes.
        cell = rgb[y0:y1, x0:x1].astype(float)
        near_edge = np.asarray(Image.fromarray((alpha < 0.98).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
        tinted = (cell[..., 2] > cell[..., 0] * 0.95) & (cell[..., 2] > 40)
        alpha = np.where(near_edge & tinted, alpha * 0.15, alpha)
        cut = np.dstack([rgb[y0:y1, x0:x1], (alpha * 255).astype(np.uint8)])
        cut = cut[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        pic = Image.fromarray(cut, "RGBA")
        s = a.height / pic.height
        pic = pic.resize((max(1, round(pic.width * s)), a.height), Image.LANCZOS)
        pic.save("%s/%s_%s.png" % (a.out, a.prefix, name))
        print(name, pic.size, "touches" if xs.min() == 0 or xs.max() == x1 - x0 - 1 or ys.min() == 0 or ys.max() == y1 - y0 - 1 else "")
