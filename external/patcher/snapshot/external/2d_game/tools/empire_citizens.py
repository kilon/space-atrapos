#!/usr/bin/env python3
"""The empires' citizens, made procedurally from the Minoan guard's sheets
(art/guard/guard_<pose>_<dir>.png): each frame's triceratops head is cut
off at the neck and a culture's own head drawn in its place, facing the
same way, and the body recoloured to the culture's materials. Written as a
rig of its own (art/<rig>/<rig>_<pose>_<dir>.png) - SheetPuppet loads it
like any other; PlanetSurface's citizens use it on the culture's worlds.

    Sparta: a tyrannosaur head in bronze plates with a scarlet horsehair
            crest along the skull (a hoplite's helmet), on an iron body.

    python3 tools/empire_citizens.py        (then godot --import)
"""
import colorsys
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "guard")
DIRS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
POSES = ["idle", "aim"]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)


def neck_row(img):
    """The neck: the narrowest opaque row between the frill and the shoulders."""
    w, h = img.size
    a = img.split()[3].load()
    widths = []
    for y in range(h):
        xs = [x for x in range(w) if a[x, y] > 100]
        widths.append((max(xs) - min(xs) + 1, (min(xs) + max(xs)) / 2) if xs else (0, w / 2))
    lo, hi = int(h * 0.2), int(h * 0.36)
    best = min(range(lo, hi), key=lambda y: widths[y][0] if widths[y][0] > 0 else 999)
    return best, widths[best][1], widths


def recolor(img, spec):
    """The body's materials: cream ceramic -> the culture's metal; reds kept
    (darkened to its scarlet); gold -> its bronze."""
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if 0.05 <= hh <= 0.16 and ss < 0.62 and vv > 0.5:          # cream / tan ceramic
                c = spec["body"]
                k = vv * 0.95
                px[x, y] = (int(c[0] * k), int(c[1] * k), int(c[2] * k), a)
            elif 0.08 <= hh <= 0.16 and ss >= 0.62:                       # gold trim
                c = spec["bronze"]
                k = 0.6 + vv * 0.5
                px[x, y] = (min(255, int(c[0] * k)), min(255, int(c[1] * k)), min(255, int(c[2] * k)), a)
            elif (hh < 0.04 or hh > 0.95) and ss > 0.45 and vv > 0.55:    # bright reds: the culture's scarlet
                c = spec["scarlet"]
                k = 0.45 + vv * 0.7
                px[x, y] = (min(255, int(c[0] * k)), min(255, int(c[1] * k)), min(255, int(c[2] * k)), a)
            elif (hh < 0.06 or hh > 0.93) and ss > 0.35 and vv > 0.12:    # the Minoan maroons (dark reds): the culture's own, deep
                c = spec.get("dark", spec["scarlet"])
                k = 0.25 + vv * 0.75
                px[x, y] = (min(255, int(c[0] * k)), min(255, int(c[1] * k)), min(255, int(c[2] * k)), a)
            elif 0.04 <= hh < 0.08 and ss > 0.5 and vv > 0.3:             # oranges (glowing vents, terracotta): its metal
                c = spec["bronze"]
                k = 0.5 + vv * 0.6
                px[x, y] = (min(255, int(c[0] * k)), min(255, int(c[1] * k)), min(255, int(c[2] * k)), a)
    return img


# --- The tyrannosaur head ------------------------------------------------------------

def _crest_side(d, P, s, spec, kind, L, Hs):
    c = spec["crest"] + (255,)
    if kind == "horsehair":     # a hoplite's crest: a ridge of horsehair from the back of the skull forward
        for k in range(12):
            x0 = -12 + k * 3.6
            top = -Hs - 8 - 10 * (1 - abs(k - 5.5) / 6)
            d.line([P(x0, -Hs * 0.8 if k > 2 else -14), P(x0 - 2, top)], fill=c, width=max(2, int(3 * s)))
    elif kind == "feathers":    # a raptor's feathers, swept back like an owl's tufts
        for k in range(9):
            x0 = -4 - k * 2.5
            d.polygon([P(x0 + 6, -Hs + 2), P(x0 - 10, -Hs - 6 - k * 1.2), P(x0 - 2, -Hs + 6)], fill=c)
        for k in range(5):
            d.polygon([P(-10 - k * 3, -6 + k * 3), P(-22 - k * 3, -2 + k * 4), P(-12 - k * 3, 0 + k * 3)], fill=shade(spec["crest"], 0.85))
    elif kind == "dome":        # a pachycephalosaur's thick bony dome, studded
        d.ellipse([P(-14, -Hs - 16)[0] if P(-14, 0)[0] < P(26, 0)[0] else P(26, 0)[0], P(0, -Hs - 16)[1],
                   P(26, 0)[0] if P(-14, 0)[0] < P(26, 0)[0] else P(-14, 0)[0], P(0, -Hs + 8)[1]], fill=c)
        for k in range(5):
            x, y = P(-10 + k * 8, -Hs - 4 + abs(k - 2) * 3)
            d.ellipse([x - 2 * s, y - 2 * s, x + 2 * s, y + 2 * s], fill=shade(spec["crest"], 0.7))
    elif kind == "tube":        # a parasaurolophus's long hollow crest, sweeping back
        d.polygon([P(18, -Hs + 2), P(-30, -Hs - 22), P(-36, -Hs - 16), P(8, -Hs + 8)], fill=c)
        d.line([P(14, -Hs + 1), P(-32, -Hs - 18)], fill=shade(spec["crest"], 1.3), width=max(1, int(2 * s)))
    elif kind == "sail":        # a spinosaur's spines, rising behind the skull
        for k in range(8):
            x0 = -2 - k * 4
            d.line([P(x0, -Hs + 6), P(x0 - 2, -Hs - 6 - 8 * math.sin(k / 7 * math.pi))], fill=c, width=max(2, int(3 * s)))
        d.polygon([P(0, -Hs + 6), P(-30, -Hs + 6), P(-30, -Hs - 4), P(-2, -Hs - 10)], fill=spec["crest"] + (140,))


def head_side(d, nx, ny, s, spec, flip=False, fore=1.0):
    """In profile, snout towards +x (or -x if flip). (nx, ny): the neck's top;
    s: scale; fore < 1: foreshortened (three-quarter). The head's shape from
    spec["head"]: snout length, skull height, teeth or not, crest kind."""
    hd = spec["head"]
    L, Hs = hd["snout"], hd["skull"]
    f = -1 if flip else 1

    def P(x, y):
        return (nx + f * x * s * fore, ny + y * s)
    br, dark = spec["bronze"], shade(spec["bronze"], 0.55)
    skull = [P(-14, 2), P(-16, -Hs * 0.56), P(-6, -Hs * 0.94), P(14, -Hs), P(L * 0.65, -Hs * 0.81), P(L * 0.94, -Hs * 0.62),
             P(L, -Hs * 0.38), P(L * 0.97, -4), P(L * 0.5, -2), P(6, 4)]
    jaw = [P(4, 2), P(L * 0.5, 0), P(L * 0.9, 2), P(L * 0.87, 10), P(L * 0.45, 12), P(0, 14), P(-8, 8)]
    _crest_side(d, P, s, spec, hd["crest"], L, Hs)
    d.polygon(jaw, fill=shade(br, 0.8))
    d.polygon(skull, fill=br + (255,))
    d.line([P(8, -2), P(L * 0.94, -4)], fill=dark, width=max(1, int(2 * s)))            # the mouth line
    if hd.get("teeth", True):
        n = int(L / 9)
        for k in range(n):
            x = 14 + k * (L * 0.75 / n)
            d.polygon([P(x, -3), P(x + 2.5, 4), P(x + 5, -3)], fill=(240, 236, 220, 255))
    else:   # a beak's edge
        d.line([P(L * 0.6, -2), P(L, -6)], fill=shade(spec["crest"], 0.9), width=max(2, int(3 * s)))
    d.line([P(-4, -Hs * 0.7), P(L * 0.55, -Hs * 0.84)], fill=shade(br, 1.35), width=max(1, int(2 * s)))   # light on the plates
    d.polygon([P(10, -Hs * 0.75), P(22, -Hs * 0.88), P(18, -Hs * 0.62)], fill=dark)       # brow ridge
    ex, ey = P(16, -Hs * 0.62)
    r = 2.6 * s * hd.get("eye", 1.0)
    d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=spec["eye"] + (255,))
    nx2, ny2 = P(L * 0.92, -Hs * 0.5)
    d.ellipse([nx2 - 1.6 * s, ny2 - 1.2 * s, nx2 + 1.6 * s, ny2 + 1.2 * s], fill=dark)   # nostril


def head_front(d, nx, ny, s, spec):
    hd = spec["head"]
    br, dark = spec["bronze"], shade(spec["bronze"], 0.55)
    w = 24 * s * hd.get("width", 1.0)
    Hs = hd["skull"]
    kind = hd["crest"]
    c = spec["crest"] + (255,)
    if kind == "dome":
        d.ellipse([nx - w * 0.85, ny - (Hs + 18) * s, nx + w * 0.85, ny - (Hs - 10) * s], fill=c)
    elif kind == "tube":
        d.polygon([(nx - 4 * s, ny - Hs * s), (nx - 6 * s, ny - (Hs + 26) * s), (nx + 6 * s, ny - (Hs + 26) * s), (nx + 4 * s, ny - Hs * s)], fill=c)
    elif kind == "feathers":
        for side in (-1, 1):
            d.polygon([(nx + side * w * 0.5, ny - Hs * s), (nx + side * w * 1.1, ny - (Hs + 14) * s), (nx + side * w * 0.9, ny - (Hs - 4) * s)], fill=c)
    elif kind == "sail":
        for k in range(5):
            d.line([(nx - 2 * s + k, ny - Hs * s), (nx - 2 * s + k, ny - (Hs + 16) * s)], fill=c, width=max(2, int(2 * s)))
    d.polygon([(nx - w, ny), (nx - w * 1.05, ny - Hs * 0.62 * s), (nx - w * 0.6, ny - Hs * s), (nx + w * 0.6, ny - Hs * s),
               (nx + w * 1.05, ny - Hs * 0.62 * s), (nx + w, ny)], fill=br + (255,))
    d.polygon([(nx - w * 0.9, ny - 2 * s), (nx + w * 0.9, ny - 2 * s), (nx + w * 0.75, ny + 10 * s), (nx - w * 0.75, ny + 10 * s)], fill=shade(br, 0.8))
    d.line([(nx - w * 0.9, ny - 3 * s), (nx + w * 0.9, ny - 3 * s)], fill=dark, width=max(1, int(2 * s)))
    if hd.get("teeth", True):
        for k in range(8):
            x = nx - w * 0.8 + k * w * 0.23
            d.polygon([(x, ny - 4 * s), (x + 2.5 * s, ny + 3 * s), (x + 5 * s, ny - 4 * s)], fill=(240, 236, 220, 255))
    for side in (-1, 1):
        ex, ey = nx + side * w * 0.62, ny - Hs * 0.68 * s
        r = 3 * s * hd.get("eye", 1.0)
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=spec["eye"] + (255,))
        d.polygon([(ex - 5 * s, ey - 5 * s), (ex + 5 * s, ey - 6 * s), (ex, ey - 2 * s)], fill=dark)
        d.ellipse([nx + side * 5 * s - 1.5 * s, ny - 12 * s, nx + side * 5 * s + 1.5 * s, ny - 9 * s], fill=dark)
    if kind == "horsehair":
        d.polygon([(nx - 4 * s, ny - Hs * s), (nx, ny - (Hs + 20) * s), (nx + 4 * s, ny - Hs * s)], fill=c)   # crest, end-on


def head_back(d, nx, ny, s, spec, snout=0):
    hd = spec["head"]
    br = spec["bronze"]
    w = 20 * s * hd.get("width", 1.0)
    Hs = hd["skull"] + 6
    kind = hd["crest"]
    c = spec["crest"] + (255,)
    if kind == "tube":
        d.polygon([(nx - 5 * s, ny - (Hs - 4) * s), (nx - 7 * s, ny - (Hs + 24) * s), (nx + 7 * s, ny - (Hs + 24) * s), (nx + 5 * s, ny - (Hs - 4) * s)], fill=c)
    if kind == "dome":
        d.ellipse([nx - w * 0.95, ny - (Hs + 14) * s, nx + w * 0.95, ny - (Hs - 14) * s], fill=c)
    d.polygon([(nx - w * 0.7, ny + 2 * s), (nx - w, ny - Hs * 0.42 * s), (nx - w * 0.75, ny - Hs * 0.84 * s), (nx, ny - Hs * s),
               (nx + w * 0.75, ny - Hs * 0.84 * s), (nx + w, ny - Hs * 0.42 * s), (nx + w * 0.7, ny + 2 * s)], fill=shade(br, 0.85))
    for k in range(4):   # (the plates' edges)
        y = ny - Hs * 0.78 * s + k * 8 * s
        d.arc([nx - w * 0.9, y - 4 * s, nx + w * 0.9, y + 6 * s], 20, 160, fill=shade(br, 0.6), width=max(1, int(1.5 * s)))
    if snout:   # (three-quarter from behind: the snout's end shows past the skull)
        d.polygon([(nx + snout * w * 0.6, ny - 20 * s), (nx + snout * (w + 18 * s), ny - 12 * s), (nx + snout * w * 0.7, ny - 4 * s)], fill=br + (255,))
    if kind == "horsehair":
        for k in range(9):
            y = ny - (Hs + 8) * s + k * 4.6 * s
            d.line([(nx - 3 * s, y), (nx + 3 * s, y + 2 * s)], fill=c, width=max(2, int(4 * s)))
        d.line([(nx, ny - (Hs + 12) * s), (nx, ny - 4 * s)], fill=c, width=max(3, int(6 * s)))
    elif kind == "feathers":
        for k in range(7):
            x = nx - w * 0.7 + k * w * 0.23
            d.polygon([(x, ny - Hs * 0.8 * s), (x + 3 * s, ny - (Hs + 8) * s), (x + 6 * s, ny - Hs * 0.8 * s)], fill=c)
    elif kind == "sail":
        for k in range(6):
            y = ny - (Hs + 4) * s + k * 6 * s
            d.line([(nx, y), (nx, y - 10 * s)], fill=c, width=max(2, int(3 * s)))


def head(d, view, nx, ny, s, spec):
    if view == "s":
        head_front(d, nx, ny, s, spec)
    elif view == "e":
        head_side(d, nx - 4 * s, ny, s, spec)
    elif view == "w":
        head_side(d, nx + 4 * s, ny, s, spec, flip=True)
    elif view == "se":
        head_side(d, nx - 8 * s, ny, s, spec, fore=0.7)
    elif view == "sw":
        head_side(d, nx + 8 * s, ny, s, spec, flip=True, fore=0.7)
    elif view == "n":
        head_back(d, nx, ny, s, spec)
    elif view == "ne":
        head_back(d, nx, ny, s, spec, snout=1)
    elif view == "nw":
        head_back(d, nx, ny, s, spec, snout=-1)


def painted_head(view, nx, ny, s, spec, size, k=3):
    """The head drawn k times larger, then lit from above, speckled with
    scales, outlined dark like the painted bodies, and shrunk (smooth)."""
    W, H = size[0] * k, size[1] * k
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    head(ImageDraw.Draw(layer), view, nx * k, ny * k, s * k, spec)
    a = layer.split()[3]
    bbox = a.getbbox()
    if not bbox:
        return Image.new("RGBA", size, (0, 0, 0, 0))
    top, bottom = bbox[1], bbox[3]
    px = layer.load()
    import random
    rnd = random.Random(7)
    for y in range(top, bottom):
        light = 1.18 - 0.45 * (y - top) / max(1, bottom - top)
        for x in range(bbox[0], bbox[2]):
            r, g, b, al = px[x, y]
            if al == 0:
                continue
            sc = 0.9 if rnd.random() < 0.08 else 1.0          # scales
            kk = light * sc
            px[x, y] = (min(255, int(r * kk)), min(255, int(g * kk)), min(255, int(b * kk)), al)
    # a dark outline round it all (the bodies' painted line)
    from PIL import ImageFilter
    grown = a.filter(ImageFilter.MaxFilter(2 * k + 1))
    outline = Image.new("RGBA", (W, H), (28, 18, 12, 255))
    outline.putalpha(grown)
    outline.alpha_composite(layer)
    return outline.resize(size, Image.LANCZOS)


def make(spec):
    out = os.path.join(ROOT, "art", spec["rig"])
    os.makedirs(out, exist_ok=True)
    n = 0
    scales = {}
    for pose in POSES:
        for view in DIRS:
            src = os.path.join(SRC, "guard_%s_%s.png" % (pose, view))
            img = Image.open(src).convert("RGBA")
            ny, nx, widths = neck_row(img)
            w, h = img.size
            px = img.load()
            for y in range(ny + 1):         # the old head and frill: gone
                for x in range(w):
                    px[x, y] = (0, 0, 0, 0)
            img = recolor(img, spec)
            # the new head stands on the neck; its size from the shoulders' width
            shoulders = max(wd for wd, _ in widths[ny:ny + int(h * 0.12)])
            s = scales.setdefault(view, max(0.75, min(1.15, shoulders / 82.0)))   # (the idle frame's: a rifle widens the aiming ones)
            img.alpha_composite(painted_head(view, nx, ny + 6 * s, s, spec, img.size))
            # the same canvas size, so the feet anchor stays where it was
            img.save(os.path.join(out, "%s_%s_%s.png" % (spec["rig"], pose, view)))
            n += 1
    return n


# Each people: its rig (art/<rig>/), the head's metal, the body's material,
# its reds, the eye, the crest; the head's shape (tyrannosaur, raptor...).
SPARTA = {"rig": "spartan", "bronze": rgb("b07a36"), "body": rgb("6e6a66"), "scarlet": rgb("a8231b"), "dark": rgb("5a1410"),
          "crest": rgb("a8231b"), "eye": (255, 170, 40),
          "head": {"snout": 62, "skull": 32, "teeth": True, "crest": "horsehair"}}           # tyrannosaur
ATHENS = {"rig": "athenian", "bronze": rgb("c9b48a"), "body": rgb("e6e1d6"), "scarlet": rgb("2e5aa8"), "dark": rgb("1c2e5a"),
          "crest": rgb("8a7a62"), "eye": (240, 200, 60),
          "head": {"snout": 46, "skull": 26, "teeth": True, "crest": "feathers", "eye": 1.5, "width": 0.85}}   # raptor, owl-eyed

MYCENAE = {"rig": "mycenaean", "bronze": rgb("d6a842"), "body": rgb("8a6a40"), "scarlet": rgb("8a2a1c"), "dark": rgb("3a2a1a"),
           "crest": rgb("7a2418"), "eye": (255, 220, 120),
           "head": {"snout": 40, "skull": 30, "teeth": True, "crest": "dome", "width": 1.05}}      # pachycephalosaur
IONIA = {"rig": "ionian", "bronze": rgb("3a52a0"), "body": rgb("d8d2c4"), "scarlet": rgb("2a3e8a"), "dark": rgb("1a2450"),
         "crest": rgb("e3b74a"), "eye": (250, 230, 150),
         "head": {"snout": 50, "skull": 24, "teeth": False, "crest": "tube", "width": 0.9}}        # parasaurolophus
CYCLADES = {"rig": "cycladic", "bronze": rgb("c8c4b8"), "body": rgb("f0eee8"), "scarlet": rgb("2f6fb0"), "dark": rgb("1a1c22"),
            "crest": rgb("1a1c22"), "eye": (120, 200, 255),
            "head": {"snout": 66, "skull": 22, "teeth": True, "crest": "sail", "width": 0.8}}       # spinosaur

PEOPLES = {"spartan": SPARTA, "athenian": ATHENS, "mycenaean": MYCENAE, "ionian": IONIA, "cycladic": CYCLADES}

if __name__ == "__main__":
    import sys
    for k in (sys.argv[1:] or list(PEOPLES)):
        print("%s: %d frames" % (k, make(PEOPLES[k])))
