#!/usr/bin/env python3
"""The empires' furniture, drawn procedurally: every picture the Minoan
furniture uses (Furniture.KINDS), in a culture's own forms and materials,
written to art/furniture/<culture>/<picture>.png with its anchors
(art/furniture/<culture>/anchors.json: the footprint's centre in the
picture). Furniture.picture() takes a culture's own where it has one.

Pieces are built from isometric boxes, cylinders and flat shapes in the
game's projection (one floor cell = I (+i, down-right) and J (+j,
down-left), at the pictures' scale: Furniture.ART_K), lit like the
code-drawn vault (+i face darkest, +j face a little, the top bright).
Pieces with a front come in two facings: "_a" faces down-left (+j, against
the "ne" wall), "_b" down-right (+i, against "nw") - the mirror image.

    python3 tools/empire_furniture.py        (then godot --import)
"""
import json
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART_K = 0.534
I = (64 / ART_K, 32 / ART_K)       # one cell along +i, picture px
J = (-64 / ART_K, 32 / ART_K)
H = 1 / ART_K                      # one game px of height, picture px
C = (300, 360)                     # the anchor on the work canvas


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def sh(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)


class Pic:
    def __init__(self):
        self.img = Image.new("RGBA", (600, 480), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def p(self, i, j, h=0.0):
        return (C[0] + I[0] * i + J[0] * j, C[1] + I[1] * i + J[1] * j - h * H)

    def box(self, i0, i1, j0, j1, h0, h1, col, line=True):
        P = self.p
        top = [P(i0, j0, h1), P(i1, j0, h1), P(i1, j1, h1), P(i0, j1, h1)]
        fi = [P(i1, j0, h0), P(i1, j1, h0), P(i1, j1, h1), P(i1, j0, h1)]
        fj = [P(i0, j1, h0), P(i1, j1, h0), P(i1, j1, h1), P(i0, j1, h1)]
        o = (20, 14, 10, 160)
        for poly, k in ((fi, 0.72), (fj, 0.92), (top, 1.14)):
            self.d.polygon(poly, fill=sh(col, k), outline=o if line else None)

    def cyl(self, i, j, r, h0, h1, col, n=24):
        """A vertical cylinder (radius r cells) - lit from the left."""
        cx, cy0 = self.p(i, j, h0)
        _, cy1 = self.p(i, j, h1)
        rx, ry = r * I[0] * 1.414, r * I[1] * 1.414
        for x in range(int(cx - rx), int(cx + rx) + 1):
            t = (x - (cx - rx)) / max(1, 2 * rx)
            k = 1.2 - 0.6 * t
            dy = ry * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2))
            self.d.line([x, cy1 + dy, x, cy0 + dy], fill=sh(col, k))
        self.d.ellipse([cx - rx, cy1 - ry, cx + rx, cy1 + ry], fill=sh(col, 1.18), outline=(20, 14, 10, 140))

    def disc(self, i, j, r, h, col):
        cx, cy = self.p(i, j, h)
        rx, ry = r * I[0] * 1.414, r * I[1] * 1.414
        self.d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=sh(col, 1.0), outline=(20, 14, 10, 140))

    def flat(self, pts, col, h=0.5):
        self.d.polygon([self.p(i, j, h) for i, j in pts], fill=sh(col, 1.05), outline=(20, 14, 10, 120))

    def line(self, a, b, col, w=3):
        self.d.line([self.p(*a), self.p(*b)], fill=sh(col, 1.0), width=w)

    def fire(self, i, j, h, s=1.0):
        x, y = self.p(i, j, h)
        for k, c in enumerate([(255, 210, 90), (255, 140, 40), (220, 60, 20)]):
            w = (14 - k * 3) * s
            self.d.polygon([(x - w, y), (x, y - (34 - k * 8) * s), (x + w, y)], fill=c + (255,))

    def done(self):
        bb = self.img.getbbox()
        img = self.img.crop(bb)
        return img, [round(C[0] - bb[0], 1), round(C[1] - bb[1], 1)]


# --- Sparta: plain wood, iron, bronze, scarlet wool, black-glazed clay ------------------

SP = {"wood": rgb("6a4528"), "dark": rgb("3e2a1a"), "iron": rgb("57534f"), "bronze": rgb("b07a36"),
      "scarlet": rgb("a8231b"), "stone": rgb("9a9184"), "wool": rgb("d8cfbf"), "clay": rgb("2b2522"),
      "orange": rgb("c9763a"), "reed": rgb("8f8a4e"), "glow": rgb("ff6a2a")}


def sp_dining_table(p, m):    # a long mess-hall table (the syssitia)
    for i, j in ((-0.4, -0.2), (0.35, -0.2), (-0.4, 0.15), (0.35, 0.15)):
        p.box(i, i + 0.05, j, j + 0.05, 0, 34, m["dark"])
    p.box(-0.45, 0.45, -0.25, 0.22, 34, 40, m["wood"])
    p.box(-0.3, -0.15, -0.05, 0.05, 40, 44, m["clay"])     # a bowl of black broth


def sp_chair(p, m):           # a folding stool (diphros) with a sheepskin
    for a, b in (((-0.12, -0.12), (0.12, 0.12)), ((0.12, -0.12), (-0.12, 0.12))):
        p.line((a[0], a[1], 0), (b[0], b[1], 26), m["dark"], 4)
        p.line((b[0], b[1], 0), (a[0], a[1], 26), m["dark"], 4)
    p.box(-0.15, 0.15, -0.15, 0.15, 26, 30, m["wool"])


def sp_throne(p, m):          # a stone seat, high back, the lambda in scarlet
    p.box(-0.22, 0.22, -0.2, 0.2, 0, 30, m["stone"])
    p.box(-0.22, 0.22, -0.2, -0.12, 30, 92, m["stone"])
    a, b, c = p.p(0.0, -0.11, 78), p.p(-0.12, -0.11, 44), p.p(0.12, -0.11, 44)
    p.d.line([b, a, c], fill=sh(m["scarlet"], 1.0), width=6)
    p.box(-0.2, 0.2, -0.12, 0.18, 30, 34, m["scarlet"])


def sp_bench(p, m):
    p.box(-0.4, 0.4, -0.12, 0.12, 0, 22, m["stone"])
    p.box(-0.42, 0.42, -0.14, 0.14, 22, 27, sh(m["stone"], 1.08))


def sp_couch(p, m):           # a plain wooden couch with a scarlet blanket
    p.box(-0.42, 0.42, -0.2, 0.2, 0, 22, m["wood"])
    p.box(-0.4, 0.4, -0.18, 0.18, 22, 27, m["scarlet"])
    p.box(-0.42, -0.32, -0.2, 0.2, 22, 40, m["wood"])


def sp_bed(p, m):             # reeds on a low frame - Spartans slept on rushes from the Eurotas
    p.box(-0.42, 0.42, -0.24, 0.24, 0, 12, m["dark"])
    p.box(-0.4, 0.4, -0.22, 0.22, 12, 17, m["reed"])
    for k in range(9):
        j = -0.2 + k * 0.05
        p.line((-0.38, j, 17.5), (0.38, j, 17.5), sh(m["reed"], 0.75), 1)
    p.box(-0.38, -0.2, -0.18, 0.18, 17, 21, m["wool"])


def sp_tech_desk(p, m):
    p.box(-0.35, 0.35, -0.18, 0.18, 0, 36, m["iron"])
    p.box(-0.25, 0.25, -0.16, -0.12, 36, 62, m["dark"])
    a, b = p.p(-0.2, -0.115, 58), p.p(0.2, -0.115, 40)
    p.d.rectangle([min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])], fill=sh(m["glow"], 0.8))


def sp_cabinet(p, m):         # a tall wooden cupboard bound in iron
    p.box(-0.2, 0.2, -0.16, 0.16, 0, 86, m["wood"])
    for h in (18, 50, 78):
        p.box(-0.205, 0.205, 0.155, 0.165, h, h + 3, m["iron"], line=False)
    p.disc(0.0, 0.17, 0.02, 44, m["bronze"])


def sp_pithoi(p, m):          # black-glazed jars, an orange band
    for i, j, s in ((-0.12, 0.0, 1.0), (0.14, 0.08, 0.8)):
        p.cyl(i, j, 0.11 * s, 0, 60 * s, m["clay"])
        p.cyl(i, j, 0.115 * s, 34 * s, 42 * s, m["orange"])
        p.cyl(i, j, 0.06 * s, 60 * s, 68 * s, m["clay"])


def sp_amphora_rack(p, m):
    p.box(-0.32, 0.32, -0.1, 0.1, 0, 6, m["dark"])
    p.box(-0.32, 0.32, -0.1, 0.1, 44, 48, m["dark"])
    for k in range(3):
        i = -0.2 + k * 0.2
        p.cyl(i, 0.0, 0.07, 4, 48, m["clay"])
        p.cyl(i, 0.0, 0.03, 48, 58, m["clay"])


def sp_chest(p, m):
    p.box(-0.25, 0.25, -0.16, 0.16, 0, 28, m["wood"])
    for i in (-0.18, 0.18):
        p.box(i - 0.02, i + 0.02, -0.165, 0.165, 0, 29, m["iron"], line=False)
    a, b, c = p.p(0.0, 0.165, 22), p.p(-0.06, 0.165, 8), p.p(0.06, 0.165, 8)
    p.d.line([b, a, c], fill=sh(m["bronze"], 1.1), width=3)


def sp_locker(p, m):
    p.box(-0.18, 0.18, -0.16, 0.16, 0, 70, m["iron"])
    p.box(-0.17, 0.17, 0.155, 0.165, 8, 64, sh(m["iron"], 1.1), line=False)
    p.box(0.08, 0.12, 0.16, 0.17, 34, 40, m["bronze"], line=False)


def sp_round_table(p, m):
    p.cyl(0, 0, 0.05, 0, 30, m["stone"])
    p.cyl(0, 0, 0.22, 30, 34, m["stone"])


def sp_cauldron(p, m):        # black broth on a tripod
    for a in range(3):
        t = a * 2 * math.pi / 3
        p.line((0.16 * math.cos(t), 0.16 * math.sin(t), 0), (0.08 * math.cos(t), 0.08 * math.sin(t), 30), m["iron"], 4)
    p.cyl(0, 0, 0.17, 26, 50, m["iron"])
    p.disc(0, 0, 0.14, 50, sh(m["clay"], 0.8))


def sp_hearth(p, m):
    p.box(-0.25, 0.25, -0.25, 0.25, 0, 12, m["stone"])
    p.box(-0.18, 0.18, -0.18, 0.18, 12, 13, m["dark"], line=False)
    p.fire(0, 0, 13, 1.1)


def sp_fruit_basket(p, m):    # barley loaves and figs
    p.cyl(0, 0, 0.14, 0, 16, m["reed"])
    for i, j in ((-0.05, -0.03), (0.05, 0.0), (0.0, 0.06)):
        p.disc(i, j, 0.05, 18, rgb("c4924e"))
    p.disc(0.06, -0.06, 0.025, 20, rgb("5a2a4a"))


def sp_water_basin(p, m):
    p.cyl(0, 0, 0.04, 0, 34, m["bronze"])
    p.cyl(0, 0, 0.17, 34, 40, m["bronze"])
    p.disc(0, 0, 0.14, 40, rgb("4a7aa0"))


def sp_altar(p, m):           # a stone altar, its top stained, scrolls at the ends
    p.box(-0.25, 0.25, -0.18, 0.18, 0, 44, m["stone"])
    p.box(-0.22, 0.22, -0.15, 0.15, 44, 46, sh(m["scarlet"], 0.6), line=False)
    for i in (-0.25, 0.25):
        p.cyl(i, 0.0, 0.05, 44, 50, sh(m["stone"], 1.05))
    p.fire(0, 0, 46, 0.7)


def sp_goddess_statue(p, m):  # Artemis Orthia: a stiff old wooden figure, bow in hand
    p.box(-0.14, 0.14, -0.14, 0.14, 0, 16, m["stone"])
    p.cyl(0, 0, 0.07, 16, 84, m["wood"])
    p.disc(0, 0, 0.055, 92, sh(m["wood"], 1.1))
    p.cyl(0, 0, 0.055, 84, 98, sh(m["wood"], 1.05))
    x, y = p.p(0.05, 0.07, 60)
    p.d.arc([x - 10, y - 26, x + 10, y + 26], 270, 90, fill=sh(m["dark"], 1.0), width=3)
    p.cyl(0, 0, 0.075, 40, 46, m["scarlet"])


def sp_offering_table(p, m):
    p.box(-0.25, 0.25, -0.15, 0.15, 0, 24, m["stone"])
    for i in (-0.12, 0.02, 0.14):
        p.disc(i, 0.0, 0.05, 25, rgb("c4924e"))


def sp_lamp_stand(p, m):
    p.cyl(0, 0, 0.08, 0, 4, m["bronze"])
    p.cyl(0, 0, 0.02, 4, 92, m["bronze"])
    p.cyl(0, 0, 0.07, 92, 98, m["bronze"])
    p.fire(0, 0, 98, 0.45)


def sp_incense_burner(p, m):
    p.cyl(0, 0, 0.03, 0, 34, m["bronze"])
    p.cyl(0, 0, 0.09, 34, 46, m["bronze"])
    x, y = p.p(0, 0, 50)
    for k in range(3):
        p.d.arc([x - 6 + k * 3, y - 30 - k * 8, x + 6 + k * 3, y - 14 - k * 8], 90, 270, fill=(200, 200, 200, 150), width=2)


def sp_console(p, m):
    p.box(-0.25, 0.25, -0.18, 0.18, 0, 40, m["iron"])
    p.box(-0.22, 0.22, -0.05, 0.05, 40, 66, m["dark"])
    a, b = p.p(-0.18, 0.052, 62), p.p(0.18, 0.052, 44)
    p.d.polygon([p.p(-0.18, 0.052, 62), p.p(0.18, 0.052, 62), p.p(0.18, 0.052, 44), p.p(-0.18, 0.052, 44)], fill=sh(m["glow"], 0.75))
    x, y = p.p(0, 0.052, 53)
    p.d.line([(x - 6, y + 6), (x, y - 6), (x + 6, y + 6)], fill=(255, 230, 200, 255), width=2)


def sp_holo_table(p, m):
    p.cyl(0, 0, 0.2, 0, 30, m["iron"])
    x, y = p.p(0, 0, 30)
    p.d.polygon([(x - 18, y), (x, y - 50), (x + 18, y)], fill=(255, 90, 40, 90))
    p.d.line([(x - 12, y - 10), (x, y - 40), (x + 12, y - 10)], fill=(255, 150, 90, 220), width=3)


def sp_power_core(p, m):
    p.cyl(0, 0, 0.16, 0, 12, m["iron"])
    p.cyl(0, 0, 0.1, 12, 70, m["glow"])
    p.cyl(0, 0, 0.16, 70, 80, m["iron"])


def sp_med_pod(p, m):
    p.box(-0.4, 0.4, -0.18, 0.18, 0, 22, m["iron"])
    p.box(-0.36, 0.36, -0.14, 0.14, 22, 34, rgb("7aa0b0"))
    p.box(-0.36, -0.25, -0.14, 0.14, 22, 40, m["iron"])


def sp_weapon_rack(p, m):     # spears and two round shields
    p.box(-0.32, 0.32, -0.08, 0.08, 0, 6, m["dark"])
    for k in range(5):
        i = -0.26 + k * 0.13
        p.line((i, 0, 0), (i, 0, 92), m["wood"], 3)
        x, y = p.p(i, 0, 92)
        p.d.polygon([(x - 3, y), (x, y - 12), (x + 3, y)], fill=sh(m["bronze"], 1.2))
    for i in (-0.15, 0.15):
        x, y = p.p(i, 0.09, 40)
        p.d.ellipse([x - 16, y - 18, x + 16, y + 18], fill=sh(m["bronze"], 1.0), outline=(30, 20, 10, 200))
        p.d.line([(x - 8, y + 9), (x, y - 9), (x + 8, y + 9)], fill=sh(m["scarlet"], 1.0), width=3)


def sp_charging_alcove(p, m):
    p.box(-0.22, 0.22, -0.18, -0.1, 0, 100, m["iron"])
    p.box(-0.22, 0.22, -0.18, 0.1, 0, 6, m["iron"])
    p.box(-0.15, 0.15, -0.1, -0.09, 10, 92, sh(m["glow"], 0.6), line=False)


def sp_workbench(p, m):
    for i, j in ((-0.35, -0.12), (0.3, -0.12), (-0.35, 0.08), (0.3, 0.08)):
        p.box(i, i + 0.05, j, j + 0.05, 0, 32, m["dark"])
    p.box(-0.38, 0.38, -0.15, 0.15, 32, 38, m["wood"])
    p.box(-0.1, 0.05, -0.05, 0.05, 38, 44, m["iron"])


def sp_rug(p, m):             # scarlet wool with a black border
    p.flat([(-0.42, -0.3), (0.42, -0.3), (0.42, 0.3), (-0.42, 0.3)], m["dark"])
    p.flat([(-0.36, -0.24), (0.36, -0.24), (0.36, 0.24), (-0.36, 0.24)], m["scarlet"], 0.8)


def sp_cushions(p, m):        # sheepskins
    for i, j in ((-0.1, 0.0), (0.12, 0.05)):
        p.flat([(i - 0.12, j - 0.08), (i + 0.12, j - 0.1), (i + 0.14, j + 0.08), (i - 0.1, j + 0.1)], m["wool"], 2)


def sp_lilies(p, m):          # a laurel in a black pot
    p.cyl(0, 0, 0.09, 0, 26, m["clay"])
    x, y = p.p(0, 0, 26)
    for k in range(9):
        a = k * 0.7
        p.d.ellipse([x + 16 * math.cos(a) - 9, y - 30 - 14 * math.sin(a) - 7, x + 16 * math.cos(a) + 9, y - 30 - 14 * math.sin(a) + 7], fill=rgb("3f6a34") + (255,))


def sp_olive_pot(p, m):
    p.cyl(0, 0, 0.1, 0, 26, m["clay"])
    p.line((0, 0, 26), (0, 0, 70), m["dark"], 5)
    x, y = p.p(0, 0, 76)
    for k in range(11):
        a = k * 0.57
        p.d.ellipse([x + 22 * math.cos(a) - 12, y - 16 * math.sin(a) - 7, x + 22 * math.cos(a) + 12, y - 16 * math.sin(a) + 7], fill=rgb("6f7f52") + (255,))


def sp_tablets(p, m):         # the scytale: staffs to wind a message round
    p.box(-0.25, 0.25, -0.08, 0.08, 0, 6, m["dark"])
    for k in range(4):
        i = -0.18 + k * 0.12
        p.line((i, 0, 6), (i, 0, 56), m["wood"], 5)
        for h in range(12, 50, 7):
            p.line((i - 0.02, 0.02, h), (i + 0.02, 0.02, h + 4), m["wool"], 2)


def sp_loom(p, m):            # an upright loom, warp weights hanging
    for i in (-0.3, 0.3):
        p.line((i, 0, 0), (i, 0, 96), m["wood"], 5)
    p.line((-0.3, 0, 92), (0.3, 0, 92), m["wood"], 5)
    for k in range(12):
        i = -0.26 + k * 0.047
        p.line((i, 0, 90), (i, 0, 24), m["scarlet"] if k % 3 else m["wool"], 2)
        p.disc(i, 0, 0.012, 20, m["clay"])


def sp_shards(p, m):
    for i, j in ((-0.1, 0.0), (0.08, -0.06), (0.12, 0.08), (-0.02, 0.1)):
        p.flat([(i - 0.05, j - 0.03), (i + 0.05, j - 0.04), (i + 0.03, j + 0.04)], m["clay"], 1)


FACING = ["dining_table", "chair", "throne", "bench", "couch", "bed", "tech_desk", "cabinet"]
SPARTA = {"folder": "sparta", "m": SP, "pieces": {
    "dining_table": sp_dining_table, "chair": sp_chair, "throne": sp_throne, "bench": sp_bench, "couch": sp_couch,
    "bed": sp_bed, "tech_desk": sp_tech_desk, "cabinet": sp_cabinet, "pithoi": sp_pithoi, "amphora_rack": sp_amphora_rack,
    "chest": sp_chest, "locker": sp_locker, "round_table": sp_round_table, "cauldron": sp_cauldron, "hearth": sp_hearth,
    "fruit_basket": sp_fruit_basket, "water_basin": sp_water_basin, "altar": sp_altar, "goddess_statue": sp_goddess_statue,
    "offering_table": sp_offering_table, "lamp_stand": sp_lamp_stand, "incense_burner": sp_incense_burner,
    "console": sp_console, "holo_table": sp_holo_table, "power_core": sp_power_core, "med_pod": sp_med_pod,
    "weapon_rack": sp_weapon_rack, "charging_alcove": sp_charging_alcove, "workbench": sp_workbench,
    "rug_spiral": sp_rug, "cushions": sp_cushions, "lilies": sp_lilies, "olive_pot": sp_olive_pot,
    "tablets": sp_tablets, "loom": sp_loom, "shards": sp_shards}}


# --- Athens: pale wood, marble, painted blue and red, black-figure clay -----------------

ATH = {"wood": rgb("9a7448"), "dark": rgb("5e4630"), "iron": rgb("7c7a76"), "bronze": rgb("b08a4a"),
       "scarlet": rgb("2e5aa8"), "stone": rgb("e2ddd2"), "wool": rgb("efe9dc"), "clay": rgb("1e1a17"),
       "orange": rgb("c9763a"), "reed": rgb("b8a878"), "glow": rgb("5aa0ff")}


def ath_throne(p, m):         # a marble chair of honour, the owl carved on its back
    p.box(-0.22, 0.22, -0.2, 0.2, 0, 30, m["stone"])
    p.box(-0.22, 0.22, -0.2, -0.12, 30, 84, m["stone"])
    x, y = p.p(0.0, -0.11, 62)
    p.d.ellipse([x - 9, y - 12, x + 9, y + 12], fill=sh(m["stone"], 0.8))
    for e in (-4, 4):
        p.d.ellipse([x + e - 3, y - 7, x + e + 3, y - 1], fill=(225, 185, 70, 255))
    p.box(-0.2, 0.2, -0.12, 0.18, 30, 34, m["scarlet"])


def ath_goddess_statue(p, m):  # Athena: helmet, spear, shield
    p.box(-0.15, 0.15, -0.15, 0.15, 0, 16, m["stone"])
    p.cyl(0, 0, 0.08, 16, 80, sh(m["stone"], 1.02))
    p.cyl(0, 0, 0.055, 80, 96, sh(m["stone"], 1.05))
    x, y = p.p(0, 0, 100)
    p.d.polygon([(x - 8, y + 4), (x, y - 12), (x + 8, y + 4)], fill=sh(m["bronze"], 1.0))
    p.line((0.1, 0.0, 16), (0.1, 0.0, 110), m["bronze"], 3)
    x, y = p.p(-0.06, 0.1, 46)
    p.d.ellipse([x - 13, y - 16, x + 13, y + 16], fill=sh(m["scarlet"], 1.0), outline=sh(m["bronze"], 1.0), width=2)


def ath_tablets(p, m):        # a rack of papyrus scrolls
    p.box(-0.25, 0.25, -0.12, 0.12, 0, 50, m["wood"])
    for row in (10, 26, 42):
        for k in range(5):
            x, y = p.p(-0.18 + k * 0.09, 0.125, row)
            p.d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(232, 220, 190, 255), outline=(120, 100, 70, 255))


def ath_rug(p, m):            # blue, a Greek key round it
    p.flat([(-0.42, -0.3), (0.42, -0.3), (0.42, 0.3), (-0.42, 0.3)], m["scarlet"])
    p.flat([(-0.34, -0.22), (0.34, -0.22), (0.34, 0.22), (-0.34, 0.22)], m["wool"], 0.8)
    for k in range(8):
        i = -0.38 + k * 0.1
        p.line((i, -0.26, 1), (i + 0.05, -0.26, 1), m["wool"], 2)
        p.line((i, 0.26, 1), (i + 0.05, 0.26, 1), m["wool"], 2)


def ath_pithoi(p, m):         # black-figure jars, an orange band of figures
    for i, j, s in ((-0.12, 0.0, 1.0), (0.14, 0.08, 0.8)):
        p.cyl(i, j, 0.11 * s, 0, 60 * s, m["clay"])
        p.cyl(i, j, 0.115 * s, 26 * s, 44 * s, m["orange"])
        x, y = p.p(i, j + 0.1 * s, 35 * s)
        for k in range(3):
            p.d.line([(x - 8 + k * 7, y + 6), (x - 7 + k * 7, y - 6)], fill=sh(m["clay"], 1.0), width=2)
        p.cyl(i, j, 0.06 * s, 60 * s, 68 * s, m["clay"])


def ath_lilies(p, m):         # a myrtle in a painted pot
    p.cyl(0, 0, 0.09, 0, 26, m["orange"])
    x, y = p.p(0, 0, 26)
    for k in range(10):
        a = k * 0.63
        p.d.ellipse([x + 15 * math.cos(a) - 8, y - 28 - 13 * math.sin(a) - 6, x + 15 * math.cos(a) + 8, y - 28 - 13 * math.sin(a) + 6], fill=rgb("4f7a44") + (255,))
        p.d.ellipse([x + 15 * math.cos(a) - 2, y - 28 - 13 * math.sin(a) - 2, x + 15 * math.cos(a) + 2, y - 28 - 13 * math.sin(a) + 2], fill=(250, 250, 245, 255))


ATHENS = {"folder": "athens", "m": ATH, "pieces": dict(SPARTA["pieces"])}
ATHENS["pieces"].update({"throne": ath_throne, "goddess_statue": ath_goddess_statue, "tablets": ath_tablets,
                         "rug_spiral": ath_rug, "pithoi": ath_pithoi, "lilies": ath_lilies})
# --- Mycenae: dark wood, gold, red, grey stone -------------------------------------------

MYC = {"wood": rgb("5e4228"), "dark": rgb("2e2218"), "iron": rgb("5a554e"), "bronze": rgb("c99a3a"),
       "scarlet": rgb("8a2a1c"), "stone": rgb("8d8579"), "wool": rgb("d9c4a0"), "clay": rgb("d8b98a"),
       "orange": rgb("8a2a1c"), "reed": rgb("9a8a5a"), "glow": rgb("ffb040")}


def myc_throne(p, m):         # gold-inlaid, a griffin-red back
    p.box(-0.22, 0.22, -0.2, 0.2, 0, 30, m["wood"])
    p.box(-0.22, 0.22, -0.2, -0.12, 30, 88, m["wood"])
    p.box(-0.18, 0.18, -0.115, -0.11, 40, 82, m["scarlet"], line=False)
    for h in (36, 60, 84):
        p.box(-0.22, 0.22, -0.2, -0.12, h, h + 3, m["bronze"], line=False)
    p.box(-0.2, 0.2, -0.12, 0.18, 30, 34, m["bronze"])


def myc_goddess_statue(p, m):  # the boar's-tusk helmet on its stand
    p.box(-0.12, 0.12, -0.12, 0.12, 0, 8, m["stone"])
    p.cyl(0, 0, 0.03, 8, 70, m["dark"])
    p.cyl(0, 0, 0.12, 70, 96, rgb("ebe2c8"))
    for h in (74, 82, 90):
        p.cyl(0, 0, 0.125, h, h + 2, rgb("a8987a"))
    p.cyl(0, 0, 0.05, 96, 104, m["scarlet"])


def myc_rug(p, m):
    p.flat([(-0.42, -0.3), (0.42, -0.3), (0.42, 0.3), (-0.42, 0.3)], m["bronze"])
    p.flat([(-0.34, -0.22), (0.34, -0.22), (0.34, 0.22), (-0.34, 0.22)], m["scarlet"], 0.8)
    for k in range(4):
        p.disc(-0.24 + k * 0.16, 0.0, 0.04, 1.2, m["bronze"])


MYCENAE = {"folder": "mycenae", "m": MYC, "pieces": dict(SPARTA["pieces"])}
MYCENAE["pieces"].update({"throne": myc_throne, "goddess_statue": myc_goddess_statue, "rug_spiral": myc_rug})


# --- Ionia: pale wood, lapis, gold, marble ------------------------------------------------

ION = {"wood": rgb("8a6a44"), "dark": rgb("4a3a2a"), "iron": rgb("6a7088"), "bronze": rgb("e3b74a"),
       "scarlet": rgb("23377a"), "stone": rgb("e4dfd2"), "wool": rgb("ece6d6"), "clay": rgb("23377a"),
       "orange": rgb("e3b74a"), "reed": rgb("b8a878"), "glow": rgb("8ab8ff")}


def ion_throne(p, m):         # a lapis chair with gold scrolls
    p.box(-0.2, 0.2, -0.18, 0.18, 0, 28, m["scarlet"])
    p.box(-0.2, 0.2, -0.18, -0.11, 28, 76, m["scarlet"])
    for i in (-0.2, 0.2):
        x, y = p.p(i, -0.15, 78)
        p.d.ellipse([x - 7, y - 7, x + 7, y + 7], fill=sh(m["bronze"], 1.0))
    p.box(-0.18, 0.18, -0.11, 0.16, 28, 31, m["bronze"])


def ion_goddess_statue(p, m):  # a seated sage in marble
    p.box(-0.18, 0.18, -0.18, 0.18, 0, 30, m["stone"])
    p.box(-0.12, 0.12, -0.14, 0.05, 30, 70, sh(m["stone"], 1.05))
    p.cyl(-0.02, -0.04, 0.06, 70, 86, sh(m["stone"], 1.1))
    p.box(-0.1, 0.1, 0.05, 0.14, 30, 46, sh(m["stone"], 1.0))


def ion_tablets(p, m):        # scroll rack (the libraries of Miletos)
    p.box(-0.25, 0.25, -0.12, 0.12, 0, 56, m["wood"])
    for row in (8, 24, 40):
        for k in range(5):
            x, y = p.p(-0.18 + k * 0.09, 0.125, row)
            p.d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(232, 220, 190, 255), outline=sh(m["bronze"], 1.0))


def ion_rug(p, m):            # a star map
    p.flat([(-0.42, -0.3), (0.42, -0.3), (0.42, 0.3), (-0.42, 0.3)], m["bronze"])
    p.flat([(-0.37, -0.25), (0.37, -0.25), (0.37, 0.25), (-0.37, 0.25)], sh(m["scarlet"], 0.75), 0.8)
    for i, j in ((-0.2, -0.1), (0.1, 0.12), (0.25, -0.15), (-0.05, 0.05), (0.2, 0.05), (-0.25, 0.15)):
        p.disc(i, j, 0.015, 1.4, rgb("fff0c0"))


IONIA = {"folder": "ionia", "m": ION, "pieces": dict(SPARTA["pieces"])}
IONIA["pieces"].update({"throne": ion_throne, "goddess_statue": ion_goddess_statue, "tablets": ion_tablets,
                        "rug_spiral": ion_rug, "lilies": ath_lilies})


# --- The Cyclades: whitewash, marble, sea blue, obsidian ----------------------------------

CYC = {"wood": rgb("8a6a48"), "dark": rgb("1a1c22"), "iron": rgb("7a7c82"), "bronze": rgb("c8a868"),
       "scarlet": rgb("2f6fb0"), "stone": rgb("f0eee8"), "wool": rgb("f4f2ec"), "clay": rgb("c69a6a"),
       "orange": rgb("2f6fb0"), "reed": rgb("b8a878"), "glow": rgb("6ac8ff")}


def cyc_throne(p, m):         # a whitewashed bench-seat built into the room
    p.box(-0.24, 0.24, -0.2, 0.2, 0, 26, m["stone"])
    p.box(-0.24, 0.24, -0.2, -0.12, 26, 60, m["stone"])
    p.box(-0.24, 0.24, -0.2, -0.12, 56, 60, m["scarlet"], line=False)
    p.box(-0.22, 0.22, -0.12, 0.18, 26, 30, m["scarlet"])


def cyc_goddess_statue(p, m):  # a folded-arm figure on an obsidian base
    p.box(-0.12, 0.12, -0.12, 0.12, 0, 10, m["dark"])
    p.cyl(0, 0, 0.06, 10, 76, (250, 250, 246))
    p.cyl(0, 0, 0.045, 76, 92, (250, 250, 246))
    p.cyl(0, 0, 0.065, 46, 50, (215, 215, 210))


def cyc_rug(p, m):
    p.flat([(-0.42, -0.3), (0.42, -0.3), (0.42, 0.3), (-0.42, 0.3)], m["scarlet"])
    p.flat([(-0.34, -0.22), (0.34, -0.22), (0.34, 0.22), (-0.34, 0.22)], m["wool"], 0.8)
    for k in range(3):
        p.disc(-0.2 + k * 0.2, 0.0, 0.06, 1.2, m["scarlet"])
        p.disc(-0.2 + k * 0.2, 0.0, 0.035, 1.4, m["wool"])


def cyc_pithoi(p, m):         # marble bowls and a collared jar
    p.cyl(-0.1, 0.0, 0.1, 0, 46, m["clay"])
    p.cyl(-0.1, 0.0, 0.05, 46, 54, m["clay"])
    p.cyl(0.15, 0.08, 0.12, 0, 12, (248, 248, 244))
    p.disc(0.15, 0.08, 0.1, 12, (225, 225, 220))


CYCLADES = {"folder": "cyclades", "m": CYC, "pieces": dict(SPARTA["pieces"])}
CYCLADES["pieces"].update({"throne": cyc_throne, "goddess_statue": cyc_goddess_statue, "rug_spiral": cyc_rug,
                           "pithoi": cyc_pithoi})

PEOPLES = {"sparta": SPARTA, "athens": ATHENS, "mycenae": MYCENAE, "ionia": IONIA, "cyclades": CYCLADES}


def build(spec):
    out = os.path.join(ROOT, "art", "furniture", spec["folder"])
    os.makedirs(out, exist_ok=True)
    anchors = {}
    for name, fn in spec["pieces"].items():
        p = Pic()
        fn(p, spec["m"])
        img, at = p.done()
        if name in FACING:
            img.save(os.path.join(out, name + "_a.png"))
            anchors[name + "_a"] = at
            img.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(out, name + "_b.png"))
            anchors[name + "_b"] = [round(img.width - at[0], 1), at[1]]
        else:
            img.save(os.path.join(out, name + ".png"))
            anchors[name] = at
    with open(os.path.join(out, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=1)
    return len(anchors)


if __name__ == "__main__":
    import sys
    for k in (sys.argv[1:] or list(PEOPLES)):
        print("%s: %d pictures" % (k, build(PEOPLES[k])))
