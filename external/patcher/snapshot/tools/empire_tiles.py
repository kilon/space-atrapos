#!/usr/bin/env python3
"""The empires' buildings, drawn procedurally: every wall, floor, roof,
column, roof crown and decoration piece of a culture, written as
data/sprites/tile_<set>_*.png in the Minoan sheets' conventions, so
MinoanTiles builds them the same way (its EMPIRE_STYLES name the pieces):

  walls   <set>_wallx_<design> / <set>_wally_<design>: a FLAT front view,
          112 x 216 (MinoanTiles._compose_wall samples it column by column
          and slants it onto the wall's isometric line; 216 high = exactly
          one storey, its top CAP_CROP rows hidden under the course above)
  floors  <set>_floor_* / _mosaic_* / _roof_*: the top face only, a 2:1
          diamond (MinoanTiles._compose_diamond finds its corners)
  pieces  columns, roof crowns, decor: standalone sprites, standing on
          their bottom centre (drawn at MinoanTiles.PIECE_SCALE)

Each culture is a spec (colours, course heights, its motifs, its pieces);
change it and run again to redesign:
    python3 tools/empire_tiles.py [set ...]      (then godot --import)
"""
import math
import os
import random
import sys
import zlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "sprites")
FONT = os.path.join(ROOT, "assets", "fonts", "NotoSans-Black.ttf")

WALL_W, WALL_H = 112, 216
CAP = 6                       # MinoanTiles.CAP_CROP: rows hidden under the course above
DIA_W, DIA_H = 160, 80
DOOR = (0.27, 0.73)           # SurfaceTiles.DOOR (the opening along the wall)
DOOR_TOP = 0.36               # the doorway starts this far down the face


# --- Colour helpers -------------------------------------------------------------------

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


# --- Walls ------------------------------------------------------------------------------

def ashlar(spec, rnd, w=WALL_W, h=WALL_H):
    """Stone courses: blocks of the culture's size and colour, mortar, grain."""
    img = Image.new("RGBA", (w, h), rgba(spec["stone"]))
    d = ImageDraw.Draw(img)
    y = CAP
    ch = spec["course"]
    row = 0
    while y < h:
        x = -rnd.randint(0, spec["block"][1])
        while x < w:
            bw = rnd.randint(*spec["block"])
            tint = 1.0 + rnd.uniform(-spec["vary"], spec["vary"])
            d.rectangle([x, y, x + bw, y + ch], fill=rgba(shade(spec["stone"], tint)))
            # a highlight on the top edge, a shadow under it: each block stands out a little
            d.line([x + 1, y + 1, x + bw - 1, y + 1], fill=rgba(shade(spec["stone"], tint * 1.12)))
            d.line([x, y + ch, x + bw, y + ch], fill=rgba(shade(spec["mortar"], 1.0)), width=2)
            d.line([x, y, x, y + ch], fill=rgba(shade(spec["mortar"], 1.0)), width=2)
            x += bw
        y += ch
        row += 1
    grain(img, rnd, spec.get("grain", 10))
    return img


def grain(img, rnd, amount):
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            n = rnd.randint(-amount, amount)
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)), a)


def band(d, y0, y1, col, w=WALL_W, edge=None):
    d.rectangle([0, y0, w, y1], fill=rgba(col))
    if edge:
        d.line([0, y0, w, y0], fill=rgba(edge), width=2)
        d.line([0, y1, w, y1], fill=rgba(edge), width=2)


def shield(d, cx, cy, r, spec, emblem="lambda"):
    """A round hoplite shield: bronze rim, its face, the emblem."""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgba(shade(spec["bronze"], 0.75)))
    d.ellipse([cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2], fill=rgba(spec["bronze"]))
    d.ellipse([cx - r + 5, cy - r + 5, cx + r - 5, cy + r - 5], fill=rgba(spec.get("shield_face", spec["bronze"])))
    d.arc([cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2], 200, 300, fill=rgba(shade(spec["bronze"], 1.35)), width=2)
    if emblem == "lambda":
        k = r * 0.55
        d.line([cx - k, cy + k, cx, cy - k], fill=rgba(spec["accent"]), width=max(2, int(r / 5)))
        d.line([cx + k, cy + k, cx, cy - k], fill=rgba(spec["accent"]), width=max(2, int(r / 5)))


def wall(spec, design, seed):
    rnd = random.Random(seed)
    img = spec.get("masonry", ashlar)(spec, rnd)
    d = ImageDraw.Draw(img)
    face = WALL_H - CAP
    # every wall: a cornice at the top and a plinth at the foot (the culture's colours)
    band(d, CAP, CAP + spec["cornice"], spec["cornice_col"], edge=shade(spec["cornice_col"], 0.7))
    band(d, WALL_H - spec["plinth"], WALL_H, spec["plinth_col"], edge=shade(spec["plinth_col"], 0.7))
    mid = CAP + face * 0.48
    drawer = spec["designs"].get(design)
    if drawer:
        drawer(img, d, spec, rnd, mid)
    if design == "door":
        x0, x1 = DOOR[0] * WALL_W, DOOR[1] * WALL_W
        yt = CAP + face * DOOR_TOP
        d.rectangle([x0 - 7, yt - 9, x1 + 7, WALL_H], fill=rgba(spec["door_frame"]))
        d.rectangle([x0, yt, x1, WALL_H], fill=rgba(spec["door_dark"]))
        d.line([x0 - 7, yt - 9, x1 + 7, yt - 9], fill=rgba(shade(spec["door_frame"], 1.3)), width=2)
    if design == "window":
        spec["window"](img, d, spec, rnd, mid)
    return img


# --- Diamonds (floors, roofs) -----------------------------------------------------------

def diamond(fn, seed):
    """A floor / roof top face: fn(u, v, rnd) -> colour, over a 2:1 diamond
    (u along its right edge from the top corner, v along its left)."""
    rnd = random.Random(seed)
    img = Image.new("RGBA", (DIA_W, DIA_H), (0, 0, 0, 0))
    px = img.load()
    cache = {}
    for y in range(DIA_H):
        for x in range(DIA_W):
            u = (x + 0.5 - DIA_W / 2) / DIA_W + (y + 0.5) / DIA_H
            v = (y + 0.5) / DIA_H - (x + 0.5 - DIA_W / 2) / DIA_W
            if u < 0 or v < 0 or u > 1 or v > 1:
                continue
            c = fn(u, v, rnd, cache)
            n = rnd.randint(-6, 6)
            px[x, y] = (max(0, min(255, c[0] + n)), max(0, min(255, c[1] + n)), max(0, min(255, c[2] + n)), 255)
    return img


def flags(stone, mortar, n=3, vary=0.08):
    """Stone flags in an n x n grid (each its own tint), mortar between."""
    def fn(u, v, rnd, cache):
        i, j = int(u * n), int(v * n)
        key = (i, j)
        if key not in cache:
            cache[key] = 1.0 + rnd.uniform(-vary, vary)
        fu, fv = u * n - i, v * n - j
        if fu < 0.05 or fv < 0.05:
            return mortar
        return shade(stone, cache[key])
    return fn


def border(inner, edge, col, width=0.1):
    """A floor with a coloured border round its edge (mosaics)."""
    def fn(u, v, rnd, cache):
        if min(u, v, 1 - u, 1 - v) < width:
            return col
        return inner(u, v, rnd, cache)
    return fn


def meander(base, line, cells=6):
    """A Greek key: a band of meander along the diamond's border."""
    def fn(u, v, rnd, cache):
        m = min(u, v, 1 - u, 1 - v)
        if m < 0.16:
            t = u if min(v, 1 - v) == m else v
            a = (t * cells * 4) % 4
            b = m / 0.16 * 4
            on = (int(b) in (0, 3)) or (int(a) == 0 and b < 3) or (int(a) == 2 and b > 1) or (1 <= b < 2 and int(a) in (0, 1))
            return line if on else base
        return base
    return fn


# --- Standing pieces ---------------------------------------------------------------------

def canvas(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def cylinder(d, cx, y0, y1, r, col, flutes=0):
    """A shaded vertical cylinder (a column's shaft): light from the left."""
    for x in range(int(cx - r), int(cx + r) + 1):
        t = (x - (cx - r)) / max(1, 2 * r)
        k = 1.25 - 0.75 * t + (0.08 if flutes and int((x - cx + r) / max(1, (2 * r / flutes))) % 2 == 0 else 0)
        d.line([x, y0, x, y1], fill=rgba(shade(col, k)))


def ellipse_top(d, cx, cy, rx, ry, col):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=rgba(shade(col, 1.15)))


def doric_column(spec, h=200):
    img, d = canvas(96, h)
    cx = 48
    # base steps (stylobate), shaft with flutes, echinus and square abacus
    d.polygon([(10, h - 10), (48, h - 1), (86, h - 10), (48, h - 19)], fill=rgba(shade(spec["stone"], 0.95)))
    cylinder(d, cx, 36, h - 14, 20, spec["column"], flutes=spec.get("flutes", 10))
    ellipse_top(d, cx, h - 14, 20, 6, shade(spec["column"], 0.8))
    cylinder(d, cx, 26, 38, 27, spec["column"])
    d.polygon([(14, 26), (48, 14), (82, 26), (48, 38)], fill=rgba(shade(spec["column"], 1.2)))
    d.polygon([(14, 26), (48, 38), (48, 44), (14, 32)], fill=rgba(shade(spec["column"], 0.95)))
    d.polygon([(82, 26), (48, 38), (48, 44), (82, 32)], fill=rgba(shade(spec["column"], 0.75)))
    if spec.get("column_band"):
        d.rectangle([cx - 20, 44, cx + 20, 50], fill=rgba(spec["column_band"]))
    return img


def statue_hoplite(spec):
    """A bronze hoplite on a plinth: crested helmet, round shield, spear."""
    img, d = canvas(110, 210)
    st, br = spec["stone"], spec["bronze"]
    d.polygon([(15, 196), (55, 209), (95, 196), (55, 183)], fill=rgba(shade(st, 1.1)))
    d.polygon([(15, 196), (55, 209), (55, 180), (15, 168)], fill=rgba(shade(st, 0.95)))
    d.polygon([(95, 196), (55, 209), (55, 180), (95, 168)], fill=rgba(shade(st, 0.75)))
    d.polygon([(15, 168), (55, 181), (95, 168), (55, 155)], fill=rgba(shade(st, 1.15)))
    body = shade(br, 0.85)
    d.rectangle([47, 110, 54, 165], fill=rgba(body))         # legs
    d.rectangle([57, 110, 64, 165], fill=rgba(shade(body, 0.8)))
    d.polygon([(42, 70), (70, 70), (66, 112), (46, 112)], fill=rgba(br))   # cuirass
    d.rectangle([44, 108, 68, 118], fill=rgba(spec["accent"]))             # the scarlet cloak's hem
    d.ellipse([46, 44, 66, 70], fill=rgba(br))                            # helmet
    d.rectangle([52, 56, 60, 66], fill=rgba(shade(br, 0.4)))               # its T-shaped face opening
    d.polygon([(44, 46), (56, 26), (70, 46), (56, 40)], fill=rgba(spec["accent"]))   # the crest
    d.line([80, 20, 80, 166], fill=rgba(shade(spec["wood"], 1.0)), width=3)          # spear
    d.polygon([(76, 22), (80, 8), (84, 22)], fill=rgba(shade(br, 1.2)))
    shield(d, 40, 98, 18, spec)
    return img


def tripod(spec):
    img, d = canvas(90, 150)
    br = spec["bronze"]
    for x0, x1 in [(18, 34), (72, 56), (45, 45)]:
        d.line([x0, 146, x1, 60], fill=rgba(shade(br, 0.8)), width=4)
    d.pieslice([14, 30, 76, 86], 0, 180, fill=rgba(br))
    d.ellipse([14, 48, 76, 66], fill=rgba(shade(br, 1.25)))
    d.ellipse([20, 51, 70, 63], fill=rgba(shade(br, 0.55)))
    for x in (22, 68):
        d.ellipse([x - 8, 22, x + 8, 38], outline=rgba(shade(br, 1.1)), width=3)   # ring handles
    return img


def shield_stack(spec):
    img, d = canvas(120, 110)
    for k, (x, y) in enumerate([(40, 80), (78, 82), (58, 60)]):
        shield(d, x, y, 24, spec)
    return img


def spear_rack(spec):
    img, d = canvas(110, 190)
    wd = spec["wood"]
    d.rectangle([12, 168, 98, 180], fill=rgba(shade(wd, 0.8)))
    d.rectangle([12, 70, 98, 78], fill=rgba(wd))
    for k in range(6):
        x = 20 + k * 14
        d.line([x, 182, x + 2, 16], fill=rgba(shade(wd, 1.05)), width=3)
        d.polygon([(x - 2, 20), (x + 2, 4), (x + 6, 20)], fill=rgba(shade(spec["bronze"], 1.2)))
    return img


def training_post(spec):
    img, d = canvas(90, 170)
    wd = spec["wood"]
    d.polygon([(15, 160), (45, 169), (75, 160), (45, 151)], fill=rgba(shade(spec["stone"], 0.9)))
    cylinder(d, 45, 30, 160, 9, wd)
    for y in (60, 100):
        d.rectangle([20, y, 70, y + 8], fill=rgba(shade(wd, 0.85)))
    d.ellipse([33, 18, 57, 40], fill=rgba(shade(wd, 1.1)))
    return img


def brazier(spec):
    img, d = canvas(80, 150)
    br = spec["bronze"]
    d.line([40, 146, 40, 60], fill=rgba(shade(br, 0.8)), width=6)
    d.polygon([(22, 146), (40, 136), (58, 146)], fill=rgba(shade(br, 0.7)))
    d.pieslice([12, 30, 68, 86], 0, 180, fill=rgba(br))
    d.ellipse([12, 50, 68, 66], fill=rgba(shade(br, 1.2)))
    for k, c in enumerate([(255, 210, 90), (255, 140, 40), (230, 70, 20)]):
        d.polygon([(26 + k * 4, 58), (40, 18 + k * 10), (54 - k * 4, 58)], fill=rgba(c))
    return img


def banner(spec, emblem="lambda"):
    img, d = canvas(70, 200)
    d.line([12, 196, 12, 10], fill=rgba(shade(spec["wood"], 0.9)), width=4)
    d.polygon([(12, 22), (62, 22), (62, 120), (37, 108), (12, 120)], fill=rgba(spec["accent"]))
    d.line([12, 22, 62, 22], fill=rgba(spec["bronze"]), width=3)
    if emblem == "lambda":
        d.line([24, 96, 37, 44], fill=rgba(spec["bronze"]), width=5)
        d.line([50, 96, 37, 44], fill=rgba(spec["bronze"]), width=5)
    return img


def helmet_crown(spec):
    """A roof's crown: a great bronze crested helmet on a block."""
    img, d = canvas(150, 150)
    st, br = spec["stone"], spec["bronze"]
    d.polygon([(30, 128), (75, 146), (120, 128), (75, 110)], fill=rgba(shade(st, 1.1)))
    d.polygon([(30, 128), (75, 146), (75, 132), (30, 114)], fill=rgba(shade(st, 0.9)))
    d.polygon([(120, 128), (75, 146), (75, 132), (120, 114)], fill=rgba(shade(st, 0.7)))
    d.pieslice([45, 40, 105, 130], 180, 360, fill=rgba(br))
    d.rectangle([45, 84, 105, 118], fill=rgba(br))
    d.rectangle([68, 86, 82, 116], fill=rgba(shade(br, 0.35)))     # the face opening
    d.rectangle([56, 92, 94, 98], fill=rgba(shade(br, 0.35)))
    d.pieslice([30, 8, 120, 80], 180, 360, fill=rgba(spec["accent"]))   # the horsehair crest
    d.rectangle([70, 40, 80, 50], fill=rgba(spec["accent"]))
    return img


def corner_block(spec):
    """A roof corner's cap: a plain block with the culture's band."""
    img, d = canvas(148, 134)
    st = spec["stone"]
    d.polygon([(10, 60), (74, 92), (138, 60), (74, 28)], fill=rgba(shade(st, 1.15)))
    d.polygon([(10, 60), (74, 92), (74, 130), (10, 98)], fill=rgba(shade(st, 0.95)))
    d.polygon([(138, 60), (74, 92), (74, 130), (138, 98)], fill=rgba(shade(st, 0.72)))
    d.polygon([(10, 72), (74, 104), (74, 112), (10, 80)], fill=rgba(spec["accent"]))
    d.polygon([(138, 72), (74, 104), (74, 112), (138, 80)], fill=rgba(shade(spec["accent"], 0.75)))
    return img


def spear_mast(spec):
    img, d = canvas(119, 200)
    d.line([60, 196, 60, 18], fill=rgba(spec["wood"]), width=5)
    d.polygon([(54, 22), (60, 2), (66, 22)], fill=rgba(shade(spec["bronze"], 1.2)))
    d.polygon([(63, 40), (110, 48), (63, 70)], fill=rgba(spec["accent"]))
    return img


# --- Sparta ------------------------------------------------------------------------------

def _sp_shields(img, d, spec, rnd, mid):
    for k in range(3):
        shield(d, 20 + k * 36, int(mid), 15, spec)


def _sp_lambda(img, d, spec, rnd, mid):
    y0, y1 = int(mid - 12), int(mid + 12)
    band(d, y0, y1, spec["accent"], edge=spec["bronze"])
    for k in range(5):
        x = 12 + k * 22
        d.line([x - 6, y1 - 4, x, y0 + 4], fill=rgba(spec["bronze"]), width=3)
        d.line([x + 6, y1 - 4, x, y0 + 4], fill=rgba(spec["bronze"]), width=3)


def _sp_spears(img, d, spec, rnd, mid):
    for k in range(4):
        x = 16 + k * 26
        d.line([x, mid + 50, x + 8, mid - 50], fill=rgba(shade(spec["stone"], 0.6)), width=3)
        d.polygon([(x + 4, mid - 44), (x + 9, mid - 62), (x + 12, mid - 42)], fill=rgba(shade(spec["stone"], 0.55)))


def _sp_inscription(img, d, spec, rnd, mid):
    y0, y1 = int(mid - 14), int(mid + 14)
    band(d, y0, y1, shade(spec["stone"], 0.82), edge=shade(spec["stone"], 0.6))
    try:
        f = ImageFont.truetype(FONT, 15)
        d.text((WALL_W / 2, mid), "ΜΟΛΩΝ ΛΑΒΕ", fill=rgba(spec["accent"]), font=f, anchor="mm")
    except OSError:
        pass


def _sp_window(img, d, spec, rnd, mid):
    """Narrow slits, as in a fortress wall."""
    for x in (34, 78):
        d.rectangle([x - 6, mid - 38, x + 6, mid + 30], fill=rgba(shade(spec["bronze"], 0.7)))
        d.rectangle([x - 3, mid - 34, x + 3, mid + 26], fill=rgba((20, 18, 22)))


SPARTA = {
    "set": "spa",
    "stone": rgb("9a9184"), "mortar": rgb("4f4a44"), "course": 30, "block": (26, 52), "vary": 0.07, "grain": 9,
    "bronze": rgb("b6833c"), "shield_face": rgb("8f2a1c"), "accent": rgb("a3221a"), "wood": rgb("6b4a2c"),
    "cornice": 10, "cornice_col": rgb("7c7468"), "plinth": 22, "plinth_col": rgb("8a1f17"),
    "door_frame": rgb("8a6430"), "door_dark": rgb("1b1714"),
    "column": rgb("a69d90"), "column_band": rgb("8a1f17"), "flutes": 12,
    "designs": {"shields": _sp_shields, "lambda": _sp_lambda, "spears": _sp_spears, "inscription": _sp_inscription},
    "window": _sp_window,
    "plain": ["stone", "shields", "lambda", "stone", "spears", "inscription"],
    "floors": {
        "floor_flags": flags(rgb("8d857a"), rgb("4a453f")),
        "floor_flags_b": flags(rgb("7f786d"), rgb("403c36"), n=2),
        "floor_earth": flags(rgb("8b7357"), rgb("6d5a44"), n=4, vary=0.04),
        "mosaic_lambda": border(flags(rgb("1f1c1a"), rgb("2a2623"), n=4, vary=0.03), None, rgb("8a1f17"), 0.14),
        "mosaic_meander": meander(rgb("2a2522"), rgb("a3221a")),
        "roof_laconian": None, "roof_bronze": None, "roof_flat": flags(rgb("6e675d"), rgb("4a453f"), n=2),
    },
}


def laconian_tiles(base, cover):
    """Laconian roof tiles: wide pans and round cover tiles in rows."""
    def fn(u, v, rnd, cache):
        a = (u * 8) % 1.0
        c = shade(base, 0.85 + 0.3 * math.sin(a * math.pi))
        if a > 0.82:
            c = shade(cover, 1.0 + 0.2 * (a - 0.82) / 0.18)
        if (v * 5) % 1.0 < 0.06:
            c = shade(c, 0.65)
        return c
    return fn


def sheet_metal(col):
    def fn(u, v, rnd, cache):
        a = (u * 6) % 1.0
        c = shade(col, 1.0 + (0.18 if a < 0.12 else 0.0) - 0.1 * v)
        return c
    return fn


SPARTA["floors"]["roof_laconian"] = laconian_tiles(rgb("a0522d"), rgb("7a3a1e"))
SPARTA["floors"]["roof_laconian_b"] = laconian_tiles(rgb("98502e"), rgb("74381e"))   # (the roof's 2nd tile: barely different)
SPARTA["floors"]["roof_bronze"] = sheet_metal(rgb("9a6e34"))
SPARTA["floors"]["roof_bronze_b"] = sheet_metal(rgb("936a33"))
SPARTA["floors"]["roof_flat_b"] = flags(rgb("6a6359"), rgb("4a453f"), n=2)
SPARTA["pieces"] = {
    "column_doric": doric_column,
    "crown_helmet": helmet_crown, "cap_block": corner_block, "mast_spear": spear_mast, "tripod_great": tripod,
    "statue_hoplite": statue_hoplite, "tripod": tripod, "shield_stack": shield_stack, "spear_rack": spear_rack,
    "training_post": training_post, "brazier": brazier, "banner": banner,
}

# --- Athens ------------------------------------------------------------------------------

def _ath_triglyphs(img, d, spec, rnd, mid):
    """A Doric frieze: triglyphs (three grooves) and painted metopes, under the cornice."""
    y0, y1 = CAP + spec["cornice"] + 2, CAP + spec["cornice"] + 30
    band(d, y0, y1, shade(spec["stone"], 0.96))
    for k in range(5):
        x = k * 24
        d.rectangle([x, y0, x + 9, y1], fill=rgba(spec["blue"]))
        for g in (2, 5):
            d.line([x + g, y0 + 2, x + g, y1 - 2], fill=rgba(shade(spec["blue"], 0.6)), width=1)
        d.rectangle([x + 12, y0 + 6, x + 21, y1 - 4], fill=rgba(shade(spec["red"], 0.95)))   # a metope's painted ground
        d.ellipse([x + 13, y0 + 9, x + 20, y0 + 16], fill=rgba(shade(spec["stone"], 1.05)))  # its figure, in relief
        d.line([x + 16, y0 + 16, x + 16, y1 - 6], fill=rgba(shade(spec["stone"], 1.05)), width=3)


def _ath_procession(img, d, spec, rnd, mid):
    """The Panathenaic procession: marble figures walking on a blue ground."""
    y0, y1 = int(mid - 22), int(mid + 22)
    band(d, y0, y1, spec["blue"], edge=shade(spec["stone"], 0.8))
    for k in range(6):
        x = 8 + k * 18 + rnd.randint(-2, 2)
        c = rgba(shade(spec["stone"], 1.05))
        d.ellipse([x - 3, y0 + 5, x + 3, y0 + 11], fill=c)                      # head
        d.polygon([(x - 4, y0 + 12), (x + 4, y0 + 12), (x + 6, y1 - 4), (x - 6, y1 - 4)], fill=c)   # robe
        if k % 3 == 1:   # one leads a horse
            d.polygon([(x + 6, y0 + 16), (x + 15, y0 + 13), (x + 15, y0 + 24), (x + 7, y0 + 24)], fill=c)


def _ath_meander(img, d, spec, rnd, mid):
    y0 = int(mid - 9)
    band(d, y0 - 3, y0 + 21, spec["blue"])
    c = rgba(shade(spec["stone"], 1.05))
    for k in range(0, WALL_W, 14):   # a running Greek key
        d.line([k, y0 + 16, k, y0 + 2, k + 10, y0 + 2, k + 10, y0 + 12, k + 4, y0 + 12, k + 4, y0 + 7], fill=c, width=2)
        d.line([k, y0 + 16, k + 14, y0 + 16], fill=c, width=2)


def _ath_owl(img, d, spec, rnd, mid):
    """Athena's owl in relief, between olive sprays."""
    cx, cy = WALL_W // 2, int(mid)
    br = shade(spec["stone"], 0.82)
    d.ellipse([cx - 13, cy - 8, cx + 13, cy + 24], fill=rgba(br))
    d.ellipse([cx - 11, cy - 20, cx + 11, cy + 2], fill=rgba(br))
    for s in (-1, 1):
        d.ellipse([cx + s * 5 - 4, cy - 14, cx + s * 5 + 4, cy - 6], fill=rgba(spec["gold"]))
        d.ellipse([cx + s * 5 - 1.5, cy - 11.5, cx + s * 5 + 1.5, cy - 8.5], fill=rgba((20, 20, 20)))
        for k in range(5):   # olive leaves
            lx, ly = cx + s * (22 + k * 6), cy + 4 - k * 5
            d.ellipse([lx - 4, ly - 2, lx + 4, ly + 2], fill=rgba(spec["olive"]))
    d.polygon([(cx - 2, cy - 7), (cx + 2, cy - 7), (cx, cy - 3)], fill=rgba(spec["gold"]))


def _ath_decree(img, d, spec, rnd, mid):
    """A carved decree: 'it was resolved by the people' - the opening of every Athenian law."""
    y0, y1 = int(mid - 30), int(mid + 30)
    d.rectangle([22, y0, WALL_W - 22, y1], fill=rgba(shade(spec["stone"], 0.94)), outline=rgba(shade(spec["stone"], 0.7)))
    try:
        f = ImageFont.truetype(FONT, 10)
        d.text((WALL_W / 2, y0 + 10), "ΕΔΟΞΕΝ", fill=rgba(spec["blue"]), font=f, anchor="mm")
        d.text((WALL_W / 2, y0 + 22), "ΤΩΙ ΔΗΜΩΙ", fill=rgba(spec["blue"]), font=f, anchor="mm")
    except OSError:
        pass
    for k in range(4):
        y = y0 + 32 + k * 6
        d.line([30, y, WALL_W - 30 - rnd.randint(0, 14), y], fill=rgba(shade(spec["stone"], 0.7)), width=1)


def _ath_window(img, d, spec, rnd, mid):
    """Tall windows with blue-painted shutters thrown open."""
    for x in (30, 82):
        d.rectangle([x - 11, mid - 34, x + 11, mid + 22], fill=rgba(shade(spec["stone"], 0.85)))
        d.rectangle([x - 8, mid - 31, x + 8, mid + 19], fill=rgba((26, 30, 40)))
        d.rectangle([x - 17, mid - 31, x - 10, mid + 19], fill=rgba(spec["blue"]))
        d.rectangle([x + 10, mid - 31, x + 17, mid + 19], fill=rgba(spec["blue"]))


def marble_flags(stone, vein, n=2):
    base = flags(stone, shade(stone, 0.8), n=n, vary=0.04)

    def fn(u, v, rnd, cache):
        c = base(u, v, rnd, cache)
        w = math.sin((u * 7 + v * 3) * 3.0 + math.sin(v * 11) * 1.5)
        if abs(w) < 0.06:
            return mix(c, vein, 0.5)
        return c
    return fn


def pebble_mosaic(dark, light, emblem):
    """Black and white pebbles: a meander border, an emblem in the middle."""
    edge = meander(dark, light, cells=5)

    def fn(u, v, rnd, cache):
        if min(u, v, 1 - u, 1 - v) < 0.16:
            return edge(u, v, rnd, cache)
        du, dv = u - 0.5, v - 0.5
        if emblem == "owl":
            r = math.hypot(du, dv * 1.2)
            if r < 0.16 or (abs(du) < 0.14 and -0.25 < dv < 0.0 and math.hypot(du, dv + 0.12) < 0.15):
                if math.hypot(abs(du) - 0.06, dv + 0.1) < 0.035:
                    return (230, 190, 70)
                return light
        elif emblem == "rosette":
            a = math.atan2(dv, du)
            r = math.hypot(du, dv)
            if r < 0.2 + 0.06 * math.cos(a * 8):
                return light if r > 0.05 else (200, 60, 50)
        return dark
    return fn


def attic_tiles(base, line):
    def fn(u, v, rnd, cache):
        a, b = (u * 7) % 1.0, (v * 4) % 1.0
        c = shade(base, 0.9 + 0.2 * math.sin(a * math.pi))
        if a > 0.88 or b < 0.07:
            c = line
        return c
    return fn


def pediment(spec):
    """A roof's crown: a temple front's triangle, its sculpture painted on blue."""
    img, d = canvas(170, 140)
    st = spec["stone"]
    d.polygon([(10, 110), (85, 60), (160, 110)], fill=rgba(shade(st, 1.1)))
    d.polygon([(24, 104), (85, 68), (146, 104)], fill=rgba(spec["blue"]))
    for k, x in enumerate((50, 68, 85, 102, 120)):
        h = 30 - abs(x - 85) * 0.5
        d.rectangle([x - 4, 104 - h, x + 4, 104], fill=rgba(shade(st, 1.15)))
        d.ellipse([x - 4, 104 - h - 8, x + 4, 104 - h], fill=rgba(shade(st, 1.15)))
    d.rectangle([6, 110, 164, 122], fill=rgba(shade(st, 0.95)))
    d.rectangle([6, 122, 164, 138], fill=rgba(shade(st, 0.8)))
    for x in range(10, 160, 16):   # triglyphs
        d.rectangle([x, 123, x + 6, 137], fill=rgba(spec["blue"]))
    return img


def acroterion(spec):
    """A corner's palmette, on a block."""
    img = corner_block(spec)
    d = ImageDraw.Draw(img)
    for k in range(7):
        a = math.pi * (0.15 + k * 0.7 / 6)
        d.ellipse([74 + 26 * math.cos(a) - 6, 30 - 26 * math.sin(a) - 9, 74 + 26 * math.cos(a) + 6, 30 - 26 * math.sin(a) + 9],
                  fill=rgba(spec["red"] if k % 2 else spec["gold"]))
    return img


def athena_promachos(spec):
    """Athena Promachos: the goddess in arms, her spear's gilded tip."""
    img, d = canvas(119, 200)
    br = spec["bronze"]
    d.polygon([(30, 190), (60, 199), (90, 190), (60, 181)], fill=rgba(shade(spec["stone"], 1.1)))
    d.polygon([(48, 182), (72, 182), (68, 110), (52, 110)], fill=rgba(br))      # robe
    d.polygon([(46, 112), (74, 112), (70, 86), (50, 86)], fill=rgba(shade(br, 1.15)))   # aegis
    d.ellipse([52, 66, 68, 86], fill=rgba(br))
    d.polygon([(50, 70), (60, 52), (70, 70)], fill=rgba(shade(br, 0.8)))       # crested helm
    d.line([84, 186, 84, 12], fill=rgba(shade(br, 0.9)), width=3)
    d.polygon([(80, 16), (84, 0), (88, 16)], fill=rgba(spec["gold"]))
    d.ellipse([30, 108, 54, 140], fill=rgba(shade(br, 0.9)))                    # shield
    return img


def owl_statue(spec):
    img, d = canvas(90, 150)
    st = spec["stone"]
    d.polygon([(15, 140), (45, 149), (75, 140), (45, 131)], fill=rgba(shade(st, 1.1)))
    d.polygon([(15, 140), (45, 149), (45, 110), (15, 101)], fill=rgba(shade(st, 0.95)))
    d.polygon([(75, 140), (45, 149), (45, 110), (75, 101)], fill=rgba(shade(st, 0.75)))
    d.polygon([(15, 101), (45, 110), (75, 101), (45, 92)], fill=rgba(shade(st, 1.15)))
    br = spec["bronze"]
    d.ellipse([28, 50, 62, 104], fill=rgba(br))
    d.ellipse([30, 30, 60, 60], fill=rgba(shade(br, 1.1)))
    for s in (-1, 1):
        d.ellipse([45 + s * 8 - 6, 38, 45 + s * 8 + 6, 50], fill=rgba(spec["gold"]))
        d.ellipse([45 + s * 8 - 2, 42, 45 + s * 8 + 2, 46], fill=rgba((15, 15, 15)))
        d.polygon([(45 + s * 9, 32), (45 + s * 15, 22), (45 + s * 13, 34)], fill=rgba(shade(br, 0.9)))
    d.polygon([(43, 50), (47, 50), (45, 56)], fill=rgba(spec["gold"]))
    return img


def herm(spec):
    """A herm: a square pillar with the bearded head of Hermes - at every Athenian door."""
    img, d = canvas(70, 170)
    st = spec["stone"]
    d.rectangle([24, 50, 46, 166], fill=rgba(shade(st, 1.0)))
    d.rectangle([46, 54, 52, 166], fill=rgba(shade(st, 0.75)))
    d.ellipse([22, 14, 48, 46], fill=rgba(shade(st, 1.05)))
    d.polygon([(25, 34), (45, 34), (35, 56)], fill=rgba(shade(st, 0.88)))      # the beard
    d.rectangle([20, 70, 50, 74], fill=rgba(spec["red"]))
    return img


def stele(spec):
    img, d = canvas(70, 160)
    st = spec["stone"]
    d.polygon([(14, 150), (35, 158), (56, 150), (35, 142)], fill=rgba(shade(st, 0.9)))
    d.rectangle([18, 30, 52, 150], fill=rgba(shade(st, 1.05)))
    d.rectangle([52, 34, 58, 150], fill=rgba(shade(st, 0.75)))
    d.polygon([(16, 32), (35, 14), (54, 32)], fill=rgba(spec["red"]))         # a palmette crown
    for k in range(12):
        y = 44 + k * 8
        d.line([22, y, 48 - (k % 3) * 4, y], fill=rgba(shade(st, 0.6)), width=1)
    return img


def prize_amphora(spec):
    """A Panathenaic prize amphora: black figures on orange - Athena with spear and shield."""
    img, d = canvas(80, 140)
    o, k = rgb("c9763a"), rgb("1c1714")
    d.polygon([(30, 134), (50, 134), (46, 124), (34, 124)], fill=rgba(k))
    d.polygon([(34, 124), (46, 124), (62, 92), (64, 60), (50, 34), (30, 34), (16, 60), (18, 92)], fill=rgba(k))
    d.polygon([(20, 60), (60, 60), (60, 92), (20, 92)], fill=rgba(o))
    d.line([40, 62, 40, 90], fill=rgba(k), width=3)                          # the goddess
    d.ellipse([35, 63, 45, 71], fill=rgba(k))
    d.ellipse([24, 70, 34, 84], fill=rgba(k))                                  # her shield
    d.line([50, 60, 46, 90], fill=rgba(k), width=1)                            # her spear
    d.rectangle([34, 18, 46, 34], fill=rgba(k))
    for x in (24, 56):
        d.arc([x - 10, 22, x + 10, 50], 180, 360, fill=rgba(k), width=3)
    return img


def olive_tree(spec):
    img, d = canvas(110, 190)
    d.polygon([(35, 180), (55, 188), (75, 180), (70, 160), (40, 160)], fill=rgba(rgb("b0643a")))
    d.line([55, 162, 50, 120, 58, 90], fill=rgba(rgb("5d4a36")), width=7)
    d.line([52, 120, 34, 96], fill=rgba(rgb("5d4a36")), width=4)
    rnd = random.Random(3)
    for k in range(60):
        x, y = 55 + rnd.uniform(-38, 38), 70 + rnd.uniform(-38, 34)
        d.ellipse([x - 7, y - 3, x + 7, y + 3], fill=rgba(mix(spec["olive"], (200, 210, 190), rnd.uniform(0, 0.4))))
    return img


def mask_stand(spec):
    """Theatre masks on a stand: tragedy and comedy."""
    img, d = canvas(90, 160)
    d.line([45, 156, 45, 40], fill=rgba(spec["wood"]), width=5)
    d.line([20, 60, 70, 60], fill=rgba(spec["wood"]), width=4)
    for x, sad in ((28, True), (62, False)):
        d.ellipse([x - 13, 62, x + 13, 96], fill=rgba(shade(spec["stone"], 1.05)))
        for e in (-5, 5):
            d.ellipse([x + e - 3, 72, x + e + 3, 77], fill=rgba((20, 20, 30)))
        d.arc([x - 7, 80 if sad else 76, x + 7, 92 if sad else 88], 200 if sad else 20, 340 if sad else 160, fill=rgba((20, 20, 30)), width=3)
    return img


ATHENS = {
    "set": "ath",
    "stone": rgb("e9e4d8"), "mortar": rgb("c9c2b2"), "course": 26, "block": (36, 64), "vary": 0.03, "grain": 6,
    "bronze": rgb("a77a3e"), "gold": rgb("e0b84a"), "blue": rgb("2e5aa8"), "red": rgb("b8402e"), "olive": rgb("6f7f52"),
    "accent": rgb("2e5aa8"), "wood": rgb("6a4a2c"),
    "cornice": 12, "cornice_col": rgb("d8d1c1"), "plinth": 16, "plinth_col": rgb("c9c2b2"),
    "door_frame": rgb("2e5aa8"), "door_dark": rgb("1c2230"),
    "column": rgb("ece7dc"), "column_band": None, "flutes": 16,
    "designs": {"triglyphs": _ath_triglyphs, "procession": _ath_procession, "meander": _ath_meander,
                "owl": _ath_owl, "decree": _ath_decree},
    "window": _ath_window,
    "plain": ["stone", "triglyphs", "procession", "meander", "owl", "decree"],
    "floors": {
        "floor_marble": marble_flags(rgb("ece7dc"), rgb("b9b2a4")),
        "floor_marble_b": marble_flags(rgb("e2ddd2"), rgb("b0a99b"), n=3),
        "floor_stone": flags(rgb("cfc8b8"), rgb("9f988a")),
        "mosaic_owl": pebble_mosaic(rgb("1e1c1a"), rgb("e9e4d8"), "owl"),
        "mosaic_rosette": pebble_mosaic(rgb("1e1c1a"), rgb("e9e4d8"), "rosette"),
        "roof_attic": attic_tiles(rgb("b8643a"), rgb("8a4628")),
        "roof_attic_b": attic_tiles(rgb("b0603a"), rgb("844426")),
        "roof_marble": flags(rgb("e2ddd2"), rgb("bdb6a8"), n=3, vary=0.03),
        "roof_marble_b": flags(rgb("dcd7cc"), rgb("b7b0a2"), n=3, vary=0.03),
    },
}
ATHENS["pieces"] = {
    "column_doric": doric_column, "crown_pediment": pediment, "cap_acroterion": acroterion, "cap_block": corner_block,
    "mast_promachos": athena_promachos, "owl_statue": owl_statue, "herm": herm, "stele": stele,
    "amphora": prize_amphora, "olive_tree": olive_tree, "masks": mask_stand, "brazier": brazier,
}

# --- Mycenae ------------------------------------------------------------------------------

def cyclopean(spec, rnd, w=WALL_W, h=WALL_H):
    """Cyclopean masonry: huge irregular boulders fitted together (a jittered
    grid of centres; each pixel belongs to its nearest - its edges dark)."""
    pts = []
    for gy in range(-1, h // 34 + 2):
        for gx in range(-1, w // 40 + 2):
            pts.append((gx * 40 + rnd.uniform(-14, 14) + (20 if gy % 2 else 0), gy * 34 + rnd.uniform(-10, 10) + CAP,
                        1.0 + rnd.uniform(-spec["vary"], spec["vary"])))
    img = Image.new("RGBA", (w, h), rgba(spec["stone"]))
    px = img.load()
    for y in range(h):
        for x in range(w):
            best, second, tint = 1e9, 1e9, 1.0
            for (cx, cy, t) in pts:
                dd = (x - cx) ** 2 + ((y - cy) * 1.15) ** 2
                if dd < best:
                    second, best, tint = best, dd, t
                elif dd < second:
                    second = dd
            edge = math.sqrt(second) - math.sqrt(best)
            if edge < 2.2:
                px[x, y] = rgba(spec["mortar"])
            else:
                k = tint * (1.0 + 0.12 * min(1.0, edge / 18.0))
                px[x, y] = rgba(shade(spec["stone"], k))
    grain(img, rnd, spec.get("grain", 10))
    return img


def _myc_spirals(img, d, spec, rnd, mid):
    y0, y1 = int(mid - 13), int(mid + 13)
    band(d, y0, y1, spec["red"], edge=spec["gold"])
    for k in range(5):
        cx = 12 + k * 22
        for r in (8, 5, 2):
            d.arc([cx - r, mid - r, cx + r, mid + r], 0, 300, fill=rgba(spec["gold"]), width=2)


def _myc_rosettes(img, d, spec, rnd, mid):
    y0, y1 = int(mid - 12), int(mid + 12)
    band(d, y0, y1, spec["blue"], edge=spec["gold"])
    for k in range(4):
        cx = 14 + k * 28
        for a in range(8):
            t = a * math.pi / 4
            d.ellipse([cx + 6 * math.cos(t) - 3, mid + 6 * math.sin(t) - 3, cx + 6 * math.cos(t) + 3, mid + 6 * math.sin(t) + 3], fill=rgba(spec["gold"]))
        d.ellipse([cx - 3, mid - 3, cx + 3, mid + 3], fill=rgba(spec["red"]))


def _myc_lions(img, d, spec, rnd, mid):
    """The Lion Gate's relief: two lions rampant either side of a column."""
    cx, cy = WALL_W // 2, int(mid)
    st = shade(spec["stone"], 1.12)
    d.polygon([(cx - 40, cy + 26), (cx, cy - 34), (cx + 40, cy + 26)], fill=rgba(shade(spec["stone"], 1.05)))
    d.polygon([(cx - 4, cy + 26), (cx + 4, cy + 26), (cx + 6, cy - 6), (cx - 6, cy - 6)], fill=rgba(spec["red"]))
    for s in (-1, 1):
        d.polygon([(cx + s * 8, cy + 24), (cx + s * 30, cy + 24), (cx + s * 28, cy + 4), (cx + s * 12, cy - 20), (cx + s * 8, cy - 10)], fill=rgba(st))
        d.ellipse([cx + s * 9 - 5, cy - 28, cx + s * 9 + 5, cy - 18], fill=rgba(st))


def _myc_chariot(img, d, spec, rnd, mid):
    """A painted frieze: a warrior's chariot, its four-spoked wheel."""
    y0, y1 = int(mid - 22), int(mid + 22)
    band(d, y0, y1, shade(spec["plaster"], 1.0), edge=spec["red"])
    hx, hy = 30, int(mid)
    d.polygon([(hx - 18, hy + 4), (hx + 10, hy - 4), (hx + 16, hy - 14), (hx + 20, hy - 10), (hx + 14, hy + 2), (hx + 8, hy + 12), (hx - 16, hy + 12)], fill=rgba(spec["red"]))
    for lx in (hx - 14, hx - 6, hx + 2, hx + 8):
        d.line([lx, hy + 10, lx - 2, y1 - 3], fill=rgba(spec["red"]), width=2)
    d.rectangle([62, hy - 12, 84, hy + 4], fill=rgba(spec["gold"]))
    d.ellipse([60, hy, 80, hy + 20], outline=rgba(shade(spec["dark"], 1.0)), width=3)
    d.line([70, hy, 70, hy + 20], fill=rgba(spec["dark"]), width=2)
    d.line([60, hy + 10, 80, hy + 10], fill=rgba(spec["dark"]), width=2)
    d.ellipse([74, hy - 26, 84, hy - 16], fill=rgba(spec["dark"]))      # the warrior
    d.line([80, hy - 30, 96, hy - 4], fill=rgba(spec["dark"]), width=2)


def _myc_gold(img, d, spec, rnd, mid):
    band(d, int(mid - 4), int(mid + 4), spec["gold"], edge=shade(spec["gold"], 0.7))


def _myc_window(img, d, spec, rnd, mid):
    for x in (32, 80):
        d.rectangle([x - 12, mid - 30, x + 12, mid - 22], fill=rgba(shade(spec["stone"], 0.8)))   # a heavy lintel
        d.rectangle([x - 8, mid - 22, x + 8, mid + 10], fill=rgba((26, 20, 18)))


def _myc_door_triangle(img, d, spec, rnd, mid):
    """Over the door: a relieving triangle (the Lion Gate's)."""
    face = WALL_H - CAP
    x0, x1 = DOOR[0] * WALL_W, DOOR[1] * WALL_W
    yt = CAP + face * DOOR_TOP
    d.polygon([(x0 - 2, yt - 12), ((x0 + x1) / 2, yt - 52), (x1 + 2, yt - 12)], fill=rgba(shade(spec["stone"], 0.7)))
    d.polygon([(x0 + 8, yt - 16), ((x0 + x1) / 2, yt - 44), (x1 - 8, yt - 16)], fill=rgba(spec["red"]))


def painted_floor(base, grid, emblem_col):
    """A Mycenaean palace floor: painted squares in a grid, one with an octopus."""
    def fn(u, v, rnd, cache):
        n = 4
        i, j = int(u * n), int(v * n)
        fu, fv = u * n - i, v * n - j
        if fu < 0.06 or fv < 0.06:
            return grid
        c = base if (i + j) % 2 else shade(base, 0.9)
        if (i, j) == (1, 2):
            du, dv = fu - 0.5, fv - 0.5
            r = math.hypot(du, dv)
            a = math.atan2(dv, du)
            if r < 0.14 or (r < 0.42 and abs(math.sin(a * 4 + r * 9)) < 0.18):
                return emblem_col
        return c
    return fn


def tholos(spec):
    """A roof's crown: a beehive tomb's dome, its gold doorway."""
    img, d = canvas(164, 140)
    st = spec["stone"]
    d.pieslice([22, 20, 142, 190], 180, 360, fill=rgba(shade(st, 1.0)))
    for k in range(6):
        y = 30 + k * 13
        d.arc([22 + k * 2, 20 + k * 2, 142 - k * 2, 190], 200, 340, fill=rgba(shade(st, 0.75)), width=1)
    d.rectangle([22, 104, 142, 136], fill=rgba(shade(st, 0.9)))
    d.rectangle([70, 82, 94, 136], fill=rgba((24, 18, 16)))
    d.polygon([(66, 82), (82, 62), (98, 82)], fill=rgba(spec["gold"]))
    return img


def lions_crown(spec):
    img, d = canvas(150, 147)
    st = spec["stone"]
    d.rectangle([20, 118, 130, 140], fill=rgba(shade(st, 0.9)))
    d.polygon([(20, 118), (75, 30), (130, 118)], fill=rgba(shade(st, 1.08)))
    d.polygon([(70, 118), (80, 118), (82, 66), (68, 66)], fill=rgba(spec["red"]))
    for s in (-1, 1):
        d.polygon([(75 + s * 10, 116), (75 + s * 44, 116), (75 + s * 40, 86), (75 + s * 16, 52), (75 + s * 10, 70)], fill=rgba(spec["gold"]))
        d.ellipse([75 + s * 13 - 8, 40, 75 + s * 13 + 8, 56], fill=rgba(spec["gold"]))
    return img


def gold_mask(spec):
    img, d = canvas(80, 160)
    d.line([40, 156, 40, 80], fill=rgba(spec["dark"]), width=6)
    d.polygon([(26, 156), (40, 146), (54, 156)], fill=rgba(spec["dark"]))
    g = spec["gold"]
    d.ellipse([18, 26, 62, 86], fill=rgba(g))
    for e in (-9, 9):
        d.line([40 + e - 6, 48, 40 + e + 6, 48], fill=rgba(shade(g, 0.55)), width=2)   # closed eyes
    d.line([40, 50, 40, 64], fill=rgba(shade(g, 1.2)), width=3)
    d.line([32, 72, 48, 72], fill=rgba(shade(g, 0.55)), width=2)
    d.arc([28, 66, 52, 86], 20, 160, fill=rgba(shade(g, 0.7)), width=2)       # the beard
    return img


def boar_helmet(spec):
    """A boar's-tusk helmet on a stand: rows of tusk plates."""
    img, d = canvas(80, 150)
    d.line([40, 146, 40, 76], fill=rgba(spec["dark"]), width=5)
    d.polygon([(24, 146), (40, 138), (56, 146)], fill=rgba(spec["dark"]))
    d.pieslice([16, 22, 64, 96], 180, 360, fill=rgba((235, 228, 205)))
    for k in range(4):
        y = 30 + k * 10
        for x in range(18 + k * 2, 62 - k * 2, 7):
            d.arc([x, y, x + 8, y + 8], 180, 360, fill=rgba((150, 140, 120)), width=2)
    d.rectangle([16, 58, 64, 64], fill=rgba(spec["red"]))
    d.line([40, 22, 40, 10], fill=rgba(spec["dark"]), width=3)
    return img


def chariot_wheel(spec):
    img, d = canvas(90, 120)
    w = spec["wood"]
    d.ellipse([10, 20, 80, 110], outline=rgba(w), width=7)
    d.line([45, 22, 45, 108], fill=rgba(w), width=5)
    d.line([12, 65, 78, 65], fill=rgba(w), width=5)
    d.ellipse([38, 58, 52, 72], fill=rgba(spec["gold"]))
    return img


def ingots(spec):
    """Oxhide copper ingots, stacked - the bronze age's money."""
    img, d = canvas(100, 90)
    cu = rgb("b0603a")
    for k, y in enumerate((70, 58, 46)):
        x = 50 + (k % 2) * 4
        d.polygon([(x - 34, y - 8), (x - 24, y), (x + 24, y), (x + 34, y - 8), (x + 24, y - 14), (x - 24, y - 14)], fill=rgba(shade(cu, 1.0 - k * 0.05)))
        d.line([x - 24, y - 14, x + 24, y - 14], fill=rgba(shade(cu, 1.3)), width=1)
    return img


def anvil(spec):
    """The Cyclops's anvil and hammer, the forge's coals beside it."""
    img, d = canvas(100, 110)
    ir = rgb("4a4744")
    d.polygon([(30, 104), (70, 104), (64, 76), (36, 76)], fill=rgba(shade(ir, 0.9)))
    d.polygon([(16, 76), (84, 76), (84, 60), (30, 60), (8, 66)], fill=rgba(ir))
    d.line([60, 58, 82, 28], fill=rgba(spec["wood"]), width=4)
    d.rectangle([76, 18, 92, 30], fill=rgba(shade(ir, 1.1)))
    for k in range(5):
        d.ellipse([10 + k * 6, 96, 18 + k * 6, 104], fill=rgba((255, 120 - k * 10, 40)))
    return img


def stirrup_jars(spec):
    img, d = canvas(100, 110)
    for x, s in ((34, 1.0), (68, 0.8)):
        h = 70 * s
        d.ellipse([x - 22 * s, 104 - h, x + 22 * s, 104], fill=rgba(rgb("d8b98a")))
        for k in range(3):
            y = 104 - h * (0.25 + k * 0.2)
            d.arc([x - 22 * s, y - 5, x + 22 * s, y + 5], 0, 180, fill=rgba(spec["red"]), width=2)
        d.arc([x - 8 * s, 104 - h - 10 * s, x + 8 * s, 104 - h + 6 * s], 180, 360, fill=rgba(rgb("d8b98a")), width=4)
    return img


def tapering_column(spec, h=200):
    """A column wider at the top than the foot (the Lion Gate's), a round capital."""
    img, d = canvas(96, h)
    c = spec["column"]
    for y in range(40, h - 12):
        t = (y - 40) / (h - 52)
        r = 22 - 6 * t
        for x in range(int(48 - r), int(48 + r) + 1):
            k = 1.2 - 0.6 * (x - (48 - r)) / max(1, 2 * r)
            d.point((x, y), fill=rgba(shade(c, k)))
    d.ellipse([20, 26, 76, 46], fill=rgba(spec["dark"]))
    d.rectangle([18, 16, 78, 28], fill=rgba(spec["gold"]))
    d.ellipse([30, h - 18, 66, h - 6], fill=rgba(shade(spec["stone"], 0.9)))
    return img


MYCENAE = {
    "set": "myc",
    "stone": rgb("8d8579"), "mortar": rgb("3e3a34"), "course": 34, "block": (40, 70), "vary": 0.1, "grain": 11,
    "bronze": rgb("b08a3a"), "gold": rgb("e3b33a"), "red": rgb("8a2a1c"), "blue": rgb("2c4a7a"), "plaster": rgb("e4d2b0"),
    "dark": rgb("2a221c"), "accent": rgb("8a2a1c"), "wood": rgb("5e4228"),
    "cornice": 10, "cornice_col": rgb("6e675d"), "plinth": 14, "plinth_col": rgb("5e574e"),
    "door_frame": rgb("6e675d"), "door_dark": rgb("1e1814"),
    "column": rgb("7a2a1e"), "flutes": 0,
    "masonry": cyclopean,
    "designs": {"spirals": _myc_spirals, "rosettes": _myc_rosettes, "lions": _myc_lions, "chariot": _myc_chariot,
                "gold": _myc_gold, "door": _myc_door_triangle},
    "window": _myc_window,
    "plain": ["stone", "spirals", "lions", "rosettes", "chariot", "gold"],
    "floors": {
        "floor_painted": painted_floor(rgb("d9b98a"), rgb("8a2a1c"), rgb("2c4a7a")),
        "floor_painted_b": painted_floor(rgb("cfae80"), rgb("8a2a1c"), rgb("2c4a7a")),
        "floor_earth": flags(rgb("8a7458"), rgb("6a5842"), n=4, vary=0.05),
        "mosaic_octopus": border(painted_floor(rgb("d9b98a"), rgb("2c4a7a"), rgb("8a2a1c")), None, rgb("8a2a1c"), 0.1),
        "roof_flat": flags(rgb("7d6f5c"), rgb("5e5244"), n=3, vary=0.05),
        "roof_flat_b": flags(rgb("776a58"), rgb("5a4e40"), n=3, vary=0.05),
    },
}
MYCENAE["pieces"] = {
    "column_taper": tapering_column, "crown_lions": lions_crown, "dome_tholos": tholos, "cap_block": corner_block,
    "mast_banner": lambda spec: banner(spec, emblem=None), "gold_mask": gold_mask, "boar_helmet": boar_helmet,
    "wheel": chariot_wheel, "ingots": ingots, "anvil": anvil, "jars": stirrup_jars, "brazier": brazier,
}


# --- Ionia --------------------------------------------------------------------------------

def _ion_eggdart(img, d, spec, rnd, mid):
    y0 = CAP + spec["cornice"] + 2
    band(d, y0, y0 + 14, spec["blue"])
    for x in range(2, WALL_W, 12):
        d.ellipse([x, y0 + 2, x + 8, y0 + 12], fill=rgba(spec["gold"]))
        d.polygon([(x + 9, y0 + 3), (x + 11, y0 + 12), (x + 13, y0 + 3)], fill=rgba(shade(spec["gold"], 0.8)))


def _ion_palmettes(img, d, spec, rnd, mid):
    """An anthemion: palmettes and lotus on lapis."""
    y0, y1 = int(mid - 16), int(mid + 16)
    band(d, y0, y1, spec["blue"], edge=spec["gold"])
    for k in range(5):
        cx = 12 + k * 22
        for a in range(5):
            t = math.pi * (0.2 + a * 0.15)
            d.line([cx, y1 - 4, cx + 12 * math.cos(t) * (1 if a % 2 else -1) * 0.6, y1 - 4 - 22 * math.sin(t)], fill=rgba(spec["gold"]), width=2)


def _ion_stars(img, d, spec, rnd, mid):
    """A star chart: the sky's circles and stars in gold on lapis."""
    y0, y1 = int(mid - 38), int(mid + 38)
    band(d, y0, y1, shade(spec["blue"], 0.7), edge=spec["gold"])
    cx, cy = WALL_W // 2, int(mid)
    for r in (14, 26, 34):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=rgba(shade(spec["gold"], 0.8)), width=1)
    for k in range(18):
        x, y = rnd.uniform(6, WALL_W - 6), rnd.uniform(y0 + 4, y1 - 4)
        d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=rgba((255, 240, 190)))
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=rgba(spec["gold"]))


def _ion_flows(img, d, spec, rnd, mid):
    """Herakleitos: 'everything flows'."""
    y0, y1 = int(mid - 13), int(mid + 13)
    band(d, y0, y1, shade(spec["stone"], 0.95), edge=spec["gold"])
    try:
        f = ImageFont.truetype(FONT, 14)
        d.text((WALL_W / 2, mid), "ΠΑΝΤΑ ΡΕΙ", fill=rgba(spec["blue"]), font=f, anchor="mm")
    except OSError:
        pass
    for k in range(3):
        y = y1 + 6 + k * 5
        d.line([(x, y + 2 * math.sin(x / 6.0 + k)) for x in range(4, WALL_W - 4, 2)], fill=rgba(spec["blue"]), width=1)


def _ion_pythagoras(img, d, spec, rnd, mid):
    """The squares on a right triangle's sides, in gold."""
    cx, cy = WALL_W // 2 - 6, int(mid) + 4
    g = rgba(spec["gold"])
    a, b = 18, 24
    tri = [(cx, cy), (cx + b, cy), (cx, cy - a)]
    d.polygon(tri, outline=g)
    d.rectangle([cx, cy, cx + b, cy + b], outline=g, width=2)
    d.rectangle([cx - a, cy - a, cx, cy], outline=g, width=2)
    ang = math.atan2(-a, b)
    hx, hy = (cx + b - cx) * 1.0, 0
    p1, p2 = (cx + b, cy), (cx, cy - a)
    vx, vy = p2[0] - p1[0], p2[1] - p1[1]
    d.polygon([p1, p2, (p2[0] - vy, p2[1] + vx), (p1[0] - vy, p1[1] + vx)], outline=g)


def _ion_garden(img, d, spec, rnd, mid):
    """Vines on a trellis (the garden isles)."""
    for x in range(6, WALL_W, 18):
        d.line([x, CAP + 20, x, WALL_H - 24], fill=rgba(spec["wood"]), width=2)
    for k in range(40):
        x, y = rnd.uniform(4, WALL_W - 4), rnd.uniform(CAP + 24, WALL_H - 40)
        d.ellipse([x - 4, y - 3, x + 4, y + 3], fill=rgba(mix(spec["olive"], (90, 160, 80), rnd.random())))
    for k in range(6):
        x, y = rnd.uniform(10, WALL_W - 10), rnd.uniform(CAP + 30, WALL_H - 50)
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=rgba((110, 40, 120)))


def _ion_window(img, d, spec, rnd, mid):
    for x in (30, 82):
        d.rectangle([x - 12, mid - 32, x + 12, mid + 16], fill=rgba(spec["gold"]))
        d.rectangle([x - 9, mid - 29, x + 9, mid + 13], fill=rgba(shade(spec["blue"], 0.6)))
        d.line([x, mid - 29, x, mid + 13], fill=rgba(spec["gold"]), width=1)


def checker(a, b, n=6):
    def fn(u, v, rnd, cache):
        return a if (int(u * n) + int(v * n)) % 2 else b
    return fn


def sun_mosaic(ground, gold, blue):
    def fn(u, v, rnd, cache):
        du, dv = u - 0.5, v - 0.5
        r = math.hypot(du, dv)
        a = math.atan2(dv, du)
        if r < 0.1:
            return gold
        if r < 0.32 and abs(math.sin(a * 6)) > 0.75 and r > 0.12:
            return gold
        for k, rr in enumerate((0.36, 0.42)):
            if abs(r - rr) < 0.01:
                return gold
        if min(u, v, 1 - u, 1 - v) < 0.06:
            return blue
        return ground
    return fn


def glazed_tiles(base, line):
    def fn(u, v, rnd, cache):
        a, b = (u * 6) % 1.0, (v * 6) % 1.0
        c = shade(base, 1.05 if (int(u * 6) + int(v * 6)) % 2 else 0.95)
        if a < 0.06 or b < 0.06:
            return line
        return c
    return fn


def garden_roof(green, path):
    def fn(u, v, rnd, cache):
        if abs(u - 0.5) < 0.07 or abs(v - 0.5) < 0.07:
            return path
        return shade(green, 0.85 + 0.3 * rnd.random())
    return fn


def ionic_column(spec, h=200):
    img, d = canvas(96, h)
    cx = 48
    d.ellipse([22, h - 18, 74, h - 4], fill=rgba(shade(spec["stone"], 0.95)))
    d.ellipse([26, h - 26, 70, h - 14], fill=rgba(shade(spec["stone"], 1.05)))
    cylinder(d, cx, 40, h - 20, 16, spec["column"], flutes=20)
    d.rectangle([20, 26, 76, 36], fill=rgba(spec["gold"]))
    for sx in (24, 72):   # the volutes
        d.ellipse([sx - 11, 26, sx + 11, 48], fill=rgba(spec["gold"]))
        d.arc([sx - 7, 30, sx + 7, 44], 0, 330, fill=rgba(shade(spec["gold"], 0.6)), width=2)
        d.ellipse([sx - 2, 35, sx + 2, 39], fill=rgba(shade(spec["gold"], 0.5)))
    d.rectangle([18, 20, 78, 26], fill=rgba(shade(spec["stone"], 1.1)))
    return img


def armillary(spec):
    img, d = canvas(110, 170)
    g = spec["gold"]
    d.line([55, 166, 55, 108], fill=rgba(shade(g, 0.8)), width=5)
    d.polygon([(35, 166), (55, 156), (75, 166)], fill=rgba(shade(g, 0.7)))
    d.ellipse([15, 30, 95, 110], outline=rgba(g), width=4)
    d.ellipse([15, 58, 95, 82], outline=rgba(g), width=3)
    d.ellipse([41, 30, 69, 110], outline=rgba(shade(g, 0.85)), width=3)
    d.line([25, 40, 85, 100], fill=rgba(shade(g, 0.9)), width=2)
    d.ellipse([49, 64, 61, 76], fill=rgba(spec["blue"]))
    return img


def gnomon(spec):
    """Anaximander's sundial: a pointer and the hour lines on a stone."""
    img, d = canvas(110, 90)
    st = spec["stone"]
    d.polygon([(10, 60), (55, 82), (100, 60), (55, 38)], fill=rgba(shade(st, 1.1)))
    d.polygon([(10, 60), (55, 82), (55, 88), (10, 66)], fill=rgba(shade(st, 0.9)))
    d.polygon([(100, 60), (55, 82), (55, 88), (100, 66)], fill=rgba(shade(st, 0.72)))
    for k in range(7):
        t = math.pi * (0.1 + k * 0.8 / 6)
        d.line([55, 66, 55 + 38 * math.cos(t), 66 - 18 * math.sin(t)], fill=rgba(shade(st, 0.6)), width=1)
    d.polygon([(52, 66), (58, 66), (55, 18)], fill=rgba(spec["gold"]))
    return img


def lyre(spec):
    img, d = canvas(80, 160)
    d.line([40, 156, 40, 110], fill=rgba(spec["wood"]), width=5)
    d.polygon([(24, 156), (40, 148), (56, 156)], fill=rgba(spec["wood"]))
    g = spec["gold"]
    d.ellipse([22, 84, 58, 114], fill=rgba(rgb("8a6a3a")))      # the tortoise-shell body
    d.line([26, 92, 18, 30], fill=rgba(g), width=4)
    d.line([54, 92, 62, 30], fill=rgba(g), width=4)
    d.line([14, 34, 66, 34], fill=rgba(g), width=4)
    for k in range(7):
        x = 28 + k * 4
        d.line([x, 36, x, 104], fill=rgba((240, 230, 200)), width=1)
    return img


def philosopher(spec):
    """A seated sage in marble, a scroll on his knee."""
    img, d = canvas(100, 180)
    st = spec["stone"]
    d.rectangle([24, 140, 76, 176], fill=rgba(shade(st, 0.95)))
    d.polygon([(30, 140), (70, 140), (66, 96), (34, 96)], fill=rgba(shade(st, 1.08)))
    d.polygon([(34, 140), (74, 140), (72, 124), (40, 120)], fill=rgba(shade(st, 1.0)))
    d.ellipse([38, 70, 62, 98], fill=rgba(shade(st, 1.12)))
    d.polygon([(40, 88), (60, 88), (50, 108)], fill=rgba(shade(st, 0.95)))
    d.rectangle([56, 116, 74, 122], fill=rgba(rgb("e8dcc0")))
    return img


def observatory_dish(spec):
    img, d = canvas(119, 200)
    d.line([60, 196, 60, 90], fill=rgba(shade(spec["stone"], 0.8)), width=6)
    d.pieslice([20, 30, 100, 110], 200, 340, fill=rgba(spec["gold"]))
    d.chord([20, 30, 100, 110], 200, 340, fill=rgba(spec["gold"]))
    d.line([60, 64, 60, 28], fill=rgba(shade(spec["gold"], 0.8)), width=2)
    d.ellipse([56, 22, 64, 30], fill=rgba(spec["blue"]))
    return img


def planter(spec):
    img, d = canvas(100, 140)
    d.polygon([(22, 136), (78, 136), (84, 104), (16, 104)], fill=rgba(spec["blue"]))
    d.rectangle([16, 100, 84, 106], fill=rgba(spec["gold"]))
    rnd = random.Random(5)
    for k in range(45):
        x, y = 50 + rnd.uniform(-34, 34), 70 + rnd.uniform(-34, 30)
        d.ellipse([x - 6, y - 4, x + 6, y + 4], fill=rgba(mix(spec["olive"], (110, 170, 90), rnd.random())))
    for k in range(6):
        x, y = 50 + rnd.uniform(-28, 28), 70 + rnd.uniform(-26, 20)
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=rgba((230, 120, 150)))
    return img


IONIA = {
    "set": "ion",
    "stone": rgb("e4dfd2"), "mortar": rgb("b9b2a2"), "course": 24, "block": (34, 58), "vary": 0.03, "grain": 5,
    "bronze": rgb("b08a3a"), "gold": rgb("e3b74a"), "blue": rgb("23377a"), "olive": rgb("5f7a4a"),
    "accent": rgb("23377a"), "wood": rgb("7a5a36"),
    "cornice": 12, "cornice_col": rgb("23377a"), "plinth": 18, "plinth_col": rgb("23377a"),
    "door_frame": rgb("e3b74a"), "door_dark": rgb("141a32"),
    "column": rgb("2d4590"), "flutes": 20,
    "designs": {"eggdart": _ion_eggdart, "palmettes": _ion_palmettes, "stars": _ion_stars, "flows": _ion_flows,
                "pythagoras": _ion_pythagoras, "garden": _ion_garden},
    "window": _ion_window,
    "plain": ["eggdart", "palmettes", "stars", "flows", "pythagoras", "garden", "stone"],
    "floors": {
        "floor_checker": checker(rgb("e4dfd2"), rgb("2d4590")),
        "floor_marble": marble_flags(rgb("e4dfd2"), rgb("a9b3d2")),
        "floor_marble_b": marble_flags(rgb("dcd7ca"), rgb("a0aac8"), n=3),
        "mosaic_sun": sun_mosaic(rgb("1c2a62"), rgb("e3b74a"), rgb("e3b74a")),
        "mosaic_checker": border(checker(rgb("e3b74a"), rgb("23377a"), n=8), None, rgb("e4dfd2"), 0.12),
        "roof_glazed": glazed_tiles(rgb("2d4590"), rgb("e3b74a")),
        "roof_glazed_b": glazed_tiles(rgb("2a4188"), rgb("dcb046")),
        "roof_garden": garden_roof(rgb("4f7a3e"), rgb("d8cfb8")),
        "roof_garden_b": garden_roof(rgb("4a7239"), rgb("d0c7b0")),
    },
}
IONIA["pieces"] = {
    "column_ionic": ionic_column, "crown_armillary": armillary, "mast_dish": observatory_dish, "cap_block": corner_block,
    "armillary": armillary, "gnomon": gnomon, "lyre": lyre, "philosopher": philosopher, "planter": planter,
    "brazier": brazier,
}


# --- The Cyclades --------------------------------------------------------------------------

def whitewash(spec, rnd, w=WALL_W, h=WALL_H):
    """Smooth lime plaster, not blocks: a soft unevenness, nothing more."""
    img = Image.new("RGBA", (w, h), rgba(spec["stone"]))
    px = img.load()
    for y in range(h):
        for x in range(w):
            k = 1.0 + 0.03 * math.sin(x / 9.0 + y / 23.0) + 0.02 * math.sin(y / 7.0)
            px[x, y] = rgba(shade(spec["stone"], k))
    grain(img, rnd, spec.get("grain", 4))
    return img


def _cyc_spirals(img, d, spec, rnd, mid):
    """Running spirals, as on the 'frying pans' of Syros."""
    y0, y1 = int(mid - 12), int(mid + 12)
    band(d, y0, y1, spec["blue"])
    for k in range(6):
        cx = 9 + k * 19
        pts = [(cx + (1 + t * 0.9) * math.cos(t), mid + (1 + t * 0.9) * math.sin(t)) for t in [i * 0.3 for i in range(32)]]
        d.line(pts, fill=rgba(spec["stone"]), width=2)


def _cyc_longboat(img, d, spec, rnd, mid):
    """An engraved longboat: a high stern, a fish standard, many oars."""
    cy = int(mid)
    c = rgba(spec["blue"])
    d.line([14, cy + 6, 96, cy + 6], fill=c, width=3)
    d.line([96, cy + 6, 100, cy - 22], fill=c, width=3)
    d.line([14, cy + 6, 10, cy], fill=c, width=3)
    d.polygon([(97, cy - 24), (106, cy - 28), (106, cy - 20)], fill=c)       # the fish
    for x in range(20, 94, 6):
        d.line([x, cy + 7, x - 4, cy + 16], fill=c, width=1)


def _cyc_niche(img, d, spec, rnd, mid):
    """A niche with a folded-arm figure in it."""
    cx, cy = WALL_W // 2, int(mid)
    d.rounded_rectangle([cx - 14, cy - 40, cx + 14, cy + 30], radius=12, fill=rgba(shade(spec["stone"], 0.82)))
    w = rgba((250, 250, 246))
    d.ellipse([cx - 4, cy - 34, cx + 4, cy - 24], fill=w)
    d.polygon([(cx - 5, cy - 22), (cx + 5, cy - 22), (cx + 3, cy + 24), (cx - 3, cy + 24)], fill=w)
    d.line([cx - 5, cy - 10, cx + 5, cy - 8], fill=rgba((190, 190, 185)), width=1)


def _cyc_obsidian(img, d, spec, rnd, mid):
    band(d, int(mid - 6), int(mid + 6), spec["obsidian"], edge=spec["blue"])


def _cyc_window(img, d, spec, rnd, mid):
    for x in (34, 80):
        d.rectangle([x - 10, mid - 22, x + 10, mid - 2], fill=rgba(spec["blue"]))
        d.rectangle([x - 7, mid - 19, x + 7, mid - 5], fill=rgba((22, 30, 44)))


def schist(base, line):
    def fn(u, v, rnd, cache):
        k = int(u * 5 + 0.3 * math.sin(v * 9))
        if k not in cache:
            cache[k] = 1.0 + rnd.uniform(-0.1, 0.1)
        if (u * 5 + 0.3 * math.sin(v * 9)) % 1.0 < 0.05:
            return line
        return shade(base, cache[k])
    return fn


def spiral_pebbles(ground, line):
    def fn(u, v, rnd, cache):
        du, dv = u - 0.5, v - 0.5
        r = math.hypot(du, dv)
        a = math.atan2(dv, du)
        if r < 0.42 and abs(((a / (2 * math.pi)) + r * 5) % 1.0 - 0.5) < 0.12:
            return line
        if min(u, v, 1 - u, 1 - v) < 0.06:
            return line
        return ground
    return fn


def plain_pillar(spec, h=200):
    img, d = canvas(96, h)
    st = spec["stone"]
    d.polygon([(30, 30), (48, 22), (66, 30), (48, 38)], fill=rgba(shade(st, 1.08)))
    d.polygon([(30, 30), (48, 38), (48, h - 4), (30, h - 12)], fill=rgba(shade(st, 0.98)))
    d.polygon([(66, 30), (48, 38), (48, h - 4), (66, h - 12)], fill=rgba(shade(st, 0.82)))
    d.polygon([(30, h - 30), (48, h - 22), (48, h - 18), (30, h - 26)], fill=rgba(spec["blue"]))
    d.polygon([(66, h - 30), (48, h - 22), (48, h - 18), (66, h - 26)], fill=rgba(shade(spec["blue"], 0.8)))
    return img


def great_figure(spec):
    """A great marble figure: folded arms, a lyre-shaped face, only a nose."""
    img, d = canvas(90, 200)
    w = (250, 250, 246)
    d.polygon([(20, 194), (45, 199), (70, 194), (45, 188)], fill=rgba(spec["obsidian"]))
    d.polygon([(38, 190), (52, 190), (54, 120), (60, 96), (52, 70), (38, 70), (30, 96), (36, 120)], fill=rgba(w))
    d.line([31, 100, 59, 104], fill=rgba((195, 195, 190)), width=2)
    d.line([32, 108, 58, 112], fill=rgba((195, 195, 190)), width=2)
    d.polygon([(34, 66), (56, 66), (58, 40), (32, 40)], fill=rgba(w))
    d.line([45, 46, 45, 58], fill=rgba((200, 200, 196)), width=3)   # the nose
    d.line([45, 190, 45, 150], fill=rgba((215, 215, 210)), width=1)
    return img


def harpist(spec):
    """The harpist of Keros: a seated figure playing a triangular harp."""
    img, d = canvas(100, 160)
    w = (250, 250, 246)
    d.rectangle([28, 120, 64, 156], fill=rgba(w))
    d.polygon([(40, 120), (56, 120), (54, 80), (42, 80)], fill=rgba(w))
    d.ellipse([42, 62, 56, 82], fill=rgba(w))
    d.line([66, 150, 66, 60, 82, 72, 70, 150], fill=rgba(w), width=4)
    return img


def kernos(spec):
    """A kernos: many little cups joined in a ring, for offerings."""
    img, d = canvas(110, 90)
    c = rgb("c69a6a")
    d.ellipse([12, 50, 98, 84], outline=rgba(c), width=6)
    for k in range(8):
        t = k * math.pi / 4
        x, y = 55 + 40 * math.cos(t), 67 + 15 * math.sin(t)
        d.ellipse([x - 7, y - 14, x + 7, y], fill=rgba(shade(c, 1.0)))
        d.ellipse([x - 5, y - 14, x + 5, y - 10], fill=rgba(shade(c, 0.6)))
    return img


def frying_pan(spec):
    img, d = canvas(90, 140)
    c = rgb("4c4440")
    d.line([45, 136, 45, 90], fill=rgba(spec["wood"]), width=4)
    d.ellipse([12, 30, 78, 96], fill=rgba(c))
    for r in (8, 16, 24):
        d.arc([45 - r, 63 - r, 45 + r, 63 + r], 0, 320, fill=rgba(shade(c, 1.6)), width=2)
    d.rectangle([40, 92, 50, 106], fill=rgba(c))
    return img


def obsidian_cores(spec):
    img, d = canvas(100, 70)
    ob = spec["obsidian"]
    rnd = random.Random(9)
    for k in range(7):
        x, y = 20 + k * 10 + rnd.uniform(-4, 4), 50 + rnd.uniform(-8, 8)
        d.polygon([(x - 7, y + 8), (x, y - 12), (x + 7, y + 8)], fill=rgba(shade(ob, 1.0 + 0.3 * rnd.random())))
        d.line([x - 2, y + 4, x, y - 8], fill=rgba((140, 150, 170)), width=1)
    return img


def marble_bowl(spec):
    img, d = canvas(90, 80)
    w = (248, 248, 244)
    d.pieslice([10, 18, 80, 76], 0, 180, fill=rgba(w))
    d.ellipse([10, 32, 80, 52], fill=rgba((232, 232, 226)))
    d.ellipse([16, 36, 74, 50], fill=rgba((210, 210, 204)))
    return img


CYCLADES = {
    "set": "cyc",
    "stone": rgb("eee8dc"), "mortar": rgb("d8d0c0"), "course": 30, "block": (40, 70), "vary": 0.02, "grain": 4,
    "bronze": rgb("a8854a"), "gold": rgb("d8b44a"), "blue": rgb("2f6fb0"), "obsidian": rgb("1a1c22"),
    "accent": rgb("2f6fb0"), "wood": rgb("7a5a3a"),
    "cornice": 12, "cornice_col": rgb("2f6fb0"), "plinth": 26, "plinth_col": rgb("5a5a58"),   # (a blue cornice, a dark schist footing: they stand out on snow)
    "door_frame": rgb("e6e3dc"), "door_dark": rgb("2f6fb0"),
    "column": rgb("f2f0ea"),
    "masonry": whitewash,
    "designs": {"spirals": _cyc_spirals, "longboat": _cyc_longboat, "niche": _cyc_niche, "obsidian": _cyc_obsidian},
    "window": _cyc_window,
    "plain": ["stone", "spirals", "longboat", "niche", "obsidian", "stone"],
    "floors": {
        "floor_schist": schist(rgb("8a8a86"), rgb("5a5a58")),
        "floor_schist_b": schist(rgb("807f7b"), rgb("545350")),
        "floor_white": flags(rgb("ecebe5"), rgb("cfcbc1"), n=3, vary=0.02),
        "mosaic_spiral": spiral_pebbles(rgb("ecebe5"), rgb("2f6fb0")),
        "mosaic_spiral_b": spiral_pebbles(rgb("2f6fb0"), rgb("ecebe5")),
        "roof_white": border(flags(rgb("d9cdb4"), rgb("b8ab90"), n=2, vary=0.03), None, rgb("2f6fb0"), 0.08),   # (sun-warmed plaster, a blue edge)
        "roof_white_b": border(flags(rgb("d2c6ac"), rgb("b2a58a"), n=2, vary=0.03), None, rgb("2f6fb0"), 0.08),
    },
}
CYCLADES["pieces"] = {
    "column_pillar": plain_pillar, "crown_figure": great_figure, "dome_kernos": kernos, "cap_block": corner_block,
    "mast_pan": frying_pan, "figure": great_figure, "harpist": harpist, "kernos": kernos, "pan": frying_pan,
    "obsidian": obsidian_cores, "bowl": marble_bowl, "brazier": brazier,
}

CULTURES = {"spa": SPARTA, "ath": ATHENS, "myc": MYCENAE, "ion": IONIA, "cyc": CYCLADES}


def build(spec):
    s = spec["set"]
    n = 0
    designs = sorted(set(spec["plain"] + ["window", "door"]))
    for di, design in enumerate(designs):
        for orient in ("x", "y"):
            img = wall(spec, design, zlib.crc32(("%s|%s|%s" % (s, design, orient)).encode()))   # (stable from run to run)
            if orient == "y":   # (the other way along: a little less light - drawn, not mirrored, so writing reads right)
                img = Image.eval(img, lambda v: v).point(lambda v: v)
                r, g, b, a = img.split()
                img = Image.merge("RGBA", [ch.point(lambda v: int(v * 0.9)) for ch in (r, g, b)] + [a])
            img.save(os.path.join(OUT, "tile_%s_wall%s_%s.png" % (s, orient, design)))
            n += 1
    for name, fn in spec["floors"].items():
        diamond(fn, zlib.crc32(("%s|%s" % (s, name)).encode())).save(os.path.join(OUT, "tile_%s_%s.png" % (s, name)))
        n += 1
    for name, fn in spec["pieces"].items():
        fn(spec).save(os.path.join(OUT, "tile_%s_%s.png" % (s, name)))
        n += 1
    return n


def main():
    sets = sys.argv[1:] or list(CULTURES)
    for s in sets:
        print("%s: %d pieces" % (s, build(CULTURES[s])))


if __name__ == "__main__":
    main()
