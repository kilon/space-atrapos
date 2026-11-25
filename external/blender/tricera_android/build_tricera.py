"""The triceratops android, modelled from reference/reference.png (a model sheet: left view and
front view in a T-pose, 1980s anime style).

  blender -b --factory-startup --python external/blender/tricera_android/build_tricera.py
Saves tricera_android.blend and renders/front.png, renders/left.png (orthographic, like the sheet).

Everything is in the collection "TriceraAndroid". The android faces -Y, feet on z = 0, 2.2 m to the
top of the frill; its sizes are read off the sheet's front view (0.00228 m per pixel; z = (985 - y) px).
It is built from rigid parts with the toolkit of the Minoan android (../android/build_android.py:
tapered limbs, boxes, cones, cloth sheets, cel-shaded materials with an inverted-hull ink outline):
  head     skull, tapering snout and beak, two long brow horns, a nose horn, cyan eyes, the round
           frill (a painted fan: cream, red spirals, gold rim with studs), gold earrings with cyan drops
  torso    cream chest and abdomen plates over a navy core, the gold sun with a cyan core on the chest,
           shoulder pads with gold trim, gold belt with a bull's-head buckle, red tassels
  arms     straight out (T-pose): navy joints, cream plates, gold bracers with a cyan stone, navy claws
  legs     cream thigh, knee and shin plates over navy joints, three-toed feet with gold claws
  cloth    the cream kilt panel with a red wave border, the red cape with a gold hem and triskelions
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "android"))
import build_android as A  # noqa: E402

A.COLL = "TriceraAndroid"
A.INK = 1.5
CREAM, GOLD, RED, NAVY = (0.93, 0.83, 0.62), (0.90, 0.62, 0.14), (0.60, 0.11, 0.10), (0.17, 0.22, 0.38)
V = Vector


def tex_frill(n=1024):
    """The frill's face, seen from the front (x right, y up, the head at the bottom centre)."""
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2.0 - 1.0
    y = -y
    out = np.empty((n, n, 3), np.float32)
    out[:] = CREAM
    red = np.zeros((n, n), bool)
    for cx, cy, r, flip in ((-0.56, 0.22, 0.24, 1), (0.56, 0.22, 0.24, -1), (-0.13, 0.64, 0.17, -1), (0.13, 0.64, 0.17, 1)):
        red |= A._spiral(x * flip, y, cx * flip, cy, r, turns=1.9, width=0.38)
    red |= (np.abs(x) < 0.03) & (y > 0.3) & (y < 0.62)
    out[red] = (0.78, 0.22, 0.18)
    r = np.sqrt(x * x + y * y)
    out[r > 0.88] = GOLD
    return out


def tex_kilt(w=1024, h=1024):
    """The kilt panel (v: 1 at the belt, 0 at the hem): cream, near the hem a red band between two
    red lines carrying a row of cream running spirals."""
    v, u = np.mgrid[0:h, 0:w] / np.array([h - 1, w - 1])[:, None, None]
    v = 1.0 - v
    out = np.empty((h, w, 3), np.float32)
    out[:] = CREAM
    band = (v > 0.07) & (v < 0.19)
    x, t = u * 6.0, (v - 0.07) / 0.12
    curl = A._spiral(x % 1.0, t * 0.9, 0.5, 0.45, 0.4, turns=1.5, width=0.45)
    out[band & curl] = (0.78, 0.22, 0.18)
    out[((v > 0.20) & (v < 0.215)) | ((v > 0.045) & (v < 0.06))] = (0.78, 0.22, 0.18)
    return out


def tex_cape(n=1024):
    """The cape (u round the back from one front edge to the other, v down): red, a gold hem,
    a gold triskelion low on each side."""
    v, u = np.mgrid[0:n, 0:n] / (n - 1)
    out = np.empty((n, n, 3), np.float32)
    out[:] = RED
    out[((u * 14.0) % 1.0) < 0.35] = tuple(c * 0.86 for c in RED)          # folds
    out[v > 0.95] = GOLD
    out[(v > 0.925) & (v < 0.935)] = GOLD
    gold = np.zeros((n, n), bool)
    for cx in (0.24, 0.76):
        for k in range(3):
            a = math.radians(90 + k * 120)
            gold |= A._spiral(u * 1.3, v, cx * 1.3 + 0.034 * math.cos(a), 0.72 - 0.034 * math.sin(a), 0.036, turns=1.6, width=0.42)
    out[gold] = GOLD
    return out


def materials():
    A.make_materials()
    A.M["cream"] = A.mat_toon("TRI_Cream", CREAM, shade=0.72, hi=0.05)
    A.M["gold"] = A.mat_toon("TRI_Gold", GOLD, shade=0.6, hi=0.3)
    A.M["navy"] = A.mat_toon("TRI_Navy", NAVY, shade=0.65)
    A.M["red"] = A.mat_toon("TRI_Red", RED, shade=0.62)
    A.M["horn"] = A.mat_toon("TRI_Horn", (0.86, 0.76, 0.58), shade=0.75, hi=0.08)
    A.M["frill"] = A.mat_toon("TRI_Frill", CREAM, shade=0.8, image=A._image("TRI_frill", tex_frill()))
    A.M["kilt"] = A.mat_toon("TRI_Kilt", CREAM, shade=0.78, image=A._image("TRI_kilt", tex_kilt()))
    A.M["cape"] = A.mat_toon("TRI_Cape", RED, shade=0.62, image=A._image("TRI_cape", tex_cape()))


def both(fn):
    for sx in (-1.0, 1.0):
        fn(sx, "L" if sx > 0 else "R")


def G(name, pts, r=0.0032):
    """A drawn panel line on a plate."""
    return A.groove(name, pts, "x", r=r)


def T(name, pts, r=0.006, mat="gold"):
    """Piping along a plate's edge."""
    return A.trim(name, pts, "x", r=r, mat=mat)


SKULL = [(0.07, 0, 1.86, 0.08, 0.065, 3.0), (-0.02, 0, 1.875, 0.118, 0.092, 3.3), (-0.12, 0, 1.875, 0.108, 0.086, 3.3),
         (-0.22, 0, 1.85, 0.078, 0.066, 3.0), (-0.31, 0, 1.815, 0.052, 0.05, 2.8), (-0.365, 0, 1.79, 0.03, 0.036, 2.5)]


def head():
    A.tube("Neck", [(0, 0.01, 1.60), (0, -0.01, 1.70), (0, -0.04, 1.80)], 0.058, "navy", ribs=0.035, seg=14)
    A.loft("NeckGuard", [(1.60, 0, 0.0, 0.10, 0.085, 3), (1.66, 0, -0.005, 0.085, 0.075, 3)], "cream", seg=20)
    A.loft("Skull", SKULL, "cream", axis="y", seg=28)
    A.cone("Beak", (0, -0.345, 1.795), (0, -0.43, 1.68), 0.05, "cream", curve=0.22, side=(0, -1, 0), seg=14)
    A.loft("Jaw", [(-0.03, 0, 1.778, 0.075, 0.024, 3), (-0.18, 0, 1.765, 0.058, 0.022, 3), (-0.30, 0, 1.752, 0.03, 0.016, 2.5)], "cream", axis="y", seg=18)
    A.cone("JawTip", (0, -0.30, 1.752), (0, -0.36, 1.71), 0.024, "cream", curve=0.15, side=(0, -1, 0))
    A.cone("NoseHorn", (0, -0.335, 1.84), (0, -0.40, 1.97), 0.036, "horn", seg=14)
    A.torus("NoseHornRing", (0, -0.337, 1.846), 0.03, 0.008, "gold", normal=(0, -0.45, 1), seg=18, outline=0.003)
    for sx, sd in ((-1.0, "R"), (1.0, "L")):
        A.cone("BrowHorn." + sd, (sx * 0.07, -0.13, 1.94), (sx * 0.125, -0.43, 2.19), 0.044, "horn", curve=0.10, side=(0, 0, -1), seg=16)
        A.torus("BrowHornRing." + sd, (sx * 0.072, -0.14, 1.948), 0.04, 0.011, "gold", normal=(sx * 0.18, -0.77, 0.64), seg=20, outline=0.003)
        A.box("Brow." + sd, (0.05, 0.15, 0.035), (sx * 0.096, -0.16, 1.918), "cream", rot=(0.28, 0, sx * 0.3), bevel=0.01)
        A.box("EyeSocket." + sd, (0.02, 0.085, 0.045), (sx * 0.094, -0.165, 1.878), "dark", rot=(0.3, 0, sx * 0.32), bevel=0.006, outline=0.0)
        A.box("Eye." + sd, (0.02, 0.06, 0.026), (sx * 0.099, -0.17, 1.878), "eye", rot=(0.3, 0, sx * 0.32), bevel=0.005, outline=0.0)
        A.box("Cheek." + sd, (0.03, 0.17, 0.085), (sx * 0.112, -0.07, 1.835), "cream", taper=(1.0, 0.7), rot=(0.1, 0, sx * 0.1), bevel=0.012)
        A.box("CheekSpike." + sd, (0.03, 0.06, 0.05), (sx * 0.118, 0.02, 1.80), "cream", taper=(0.3, 0.3), rot=(2.4, 0, 0), bevel=0.008)
        A.box("JawHinge." + sd, (0.025, 0.06, 0.06), (sx * 0.095, -0.03, 1.79), "navy", bevel=0.01)
        A.torus("Earring." + sd, (sx * 0.135, -0.02, 1.80), 0.03, 0.009, "gold", normal=(1, 0, 0))
        A.ball("EarStone." + sd, (sx * 0.14, -0.02, 1.80), 0.017, "cyan", outline=0.002)
        A.limb("EarLink." + sd, (sx * 0.135, -0.02, 1.772), (sx * 0.135, -0.02, 1.745), 0.004, 0.004, "gold", seg=6, outline=0.002)
        A.cone("EarDrop." + sd, (sx * 0.135, -0.02, 1.69), (sx * 0.135, -0.02, 1.748), 0.012, "cyan", outline=0.002)
        # panel lines on the skull: along the snout, round the cheek, across the nose
        G("SnoutLine." + sd, [A.on_loft(SKULL, "y", sx * 0.75, t) for t in (-0.10, -0.2, -0.29, -0.35)])
        G("SkullLine." + sd, [A.on_loft(SKULL, "y", sx * th, -0.06) for th in (0.15, 0.7, 1.3, 1.9)])
        G("NoseLine." + sd, [A.on_loft(SKULL, "y", sx * th, -0.255) for th in (0.0, 0.5, 1.0, 1.5)])
        G("MouthLine." + sd, [(sx * 0.082, -0.06, 1.795), (sx * 0.07, -0.18, 1.785), (sx * 0.04, -0.29, 1.772)], r=0.004)
        A.ball("Nostril." + sd, A.on_loft(SKULL, "y", sx * 1.0, -0.33, lift=0.0), 0.007, "dark", outline=0.0)
    G("CrownLine", [A.on_loft(SKULL, "y", 0.0, t) for t in (0.04, -0.03, -0.1)])
    # the frill: a fan leaning back behind the head, painted; a gold fan just behind it is the rim
    c, R, lean = V((0, 0.04, 1.84)), 0.325, math.radians(30)
    up, back = V((0, math.sin(lean), math.cos(lean))), V((0, math.cos(lean), -math.sin(lean)))

    def fan(name, r1, mat, off, bulge):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("UVMap")
        nu, nv = 40, 6
        a0, a1 = math.radians(-22), math.radians(202)
        grid = []
        for j in range(nv + 1):
            row = []
            for i in range(nu + 1):
                a, r = a0 + (a1 - a0) * i / nu, 0.10 + (r1 - 0.10) * j / nv
                p = c + V((1, 0, 0)) * r * math.cos(a) + up * r * math.sin(a) + back * (off - bulge * (r / r1) ** 2)
                row.append((bm.verts.new(p), (0.5 + 0.5 * r / R * math.cos(a) * 0.98, 0.5 + 0.5 * r / R * math.sin(a) * 0.98)))
            grid.append(row)
        for j in range(nv):
            for i in range(nu):
                q = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
                f = bm.faces.new([v for v, _ in q][::-1])
                for loop in f.loops:
                    loop[uvl].uv = next(uv for v, uv in q if v == loop.vert)
        ob = A.mesh_object(name, bm, [mat], smooth=True, outline=0.004)
        s = ob.modifiers.new("Thick", "SOLIDIFY")
        s.thickness = 0.02
        ob.modifiers.move(len(ob.modifiers) - 1, 0)
    fan("Frill", R, "frill", 0.0, 0.05)
    fan("FrillRim", R * 1.045, "gold", 0.022, 0.05)
    for k in range(11):
        a = math.radians(-14 + 208 * k / 10)
        p = c + V((1, 0, 0)) * R * 1.03 * math.cos(a) + up * R * 1.03 * math.sin(a) + back * -0.04
        A.ball("FrillStud.%02d" % k, p, 0.024, "gold", outline=0.003)


CHEST = [(1.40, 0, -0.005, 0.145, 0.115, 3.2), (1.48, 0, -0.012, 0.195, 0.14, 3.5), (1.585, 0, -0.005, 0.215, 0.138, 3.5), (1.65, 0, 0.005, 0.165, 0.11, 3.0)]
PELVIS = [(1.08, 0, 0.01, 0.11, 0.095, 3.0), (1.16, 0, 0.01, 0.158, 0.118, 3.4), (1.235, 0, 0.01, 0.15, 0.112, 3.2)]
BELT = [(1.245, 0, 0.01, 0.168, 0.132, 3.2), (1.305, 0, 0.01, 0.165, 0.13, 3.2)]


def torso():
    A.loft("Core", [(1.10, 0, 0.01, 0.12, 0.095, 2.6), (1.26, 0, 0.01, 0.112, 0.09, 2.6), (1.36, 0, 0.01, 0.118, 0.095, 2.6),
                    (1.50, 0, 0.01, 0.17, 0.12, 2.8), (1.63, 0, 0.01, 0.12, 0.10, 2.6)], "navy", seg=24)
    A.loft("Chest", CHEST, "cream", seg=32)
    for sx, sd in ((-1.0, "R"), (1.0, "L")):
        A.box("Pec." + sd, (0.17, 0.06, 0.15), (sx * 0.098, -0.128, 1.535), "cream", taper=(1.0, 1.0), rot=(0.14, 0, sx * -0.16), bevel=0.028)
        A.box("PecLow." + sd, (0.13, 0.05, 0.06), (sx * 0.085, -0.118, 1.435), "cream", taper=(1.25, 1.0), rot=(-0.2, 0, sx * -0.1), bevel=0.014)
        A.box("Rib1." + sd, (0.05, 0.13, 0.05), (sx * 0.125, -0.02, 1.375), "cream", rot=(0, sx * 0.35, 0), bevel=0.012)
        A.box("Rib2." + sd, (0.045, 0.12, 0.045), (sx * 0.118, -0.02, 1.318), "cream", rot=(0, sx * 0.25, 0), bevel=0.012)
        G("ChestSide." + sd, [A.on_loft(CHEST, "z", sx * th, 1.54) for th in (1.1, 1.6, 2.2)])
        G("ChestDown." + sd, [A.on_loft(CHEST, "z", sx * 1.25, z) for z in (1.43, 1.5, 1.6)])
        T("ChestTrim." + sd, [A.on_loft(CHEST, "z", sx * th, 1.415) for th in (0.5, 0.9, 1.3, 1.8, 2.4)], r=0.005)
        G("PelvisLine." + sd, [A.on_loft(PELVIS, "z", sx * 0.9, z) for z in (1.10, 1.16, 1.22)])
        A.tube("WaistCable." + sd, [(sx * 0.07, -0.085, 1.40), (sx * 0.085, -0.092, 1.33), (sx * 0.075, -0.09, 1.26)], 0.011, "dark", ribs=0.02, seg=8)
    for k, (z, w) in enumerate(((1.385, 0.075), (1.335, 0.065), (1.288, 0.055))):
        A.loft("Abs%d" % k, [(z - 0.02, 0, -0.098, w * 0.9, 0.02, 3.4), (z + 0.02, 0, -0.10, w, 0.022, 3.4)], "cream", seg=16)
    A.loft("Collar", [(1.615, 0, 0.0, 0.125, 0.10, 3.0), (1.665, 0, 0.0, 0.10, 0.085, 3.0)], "navy", seg=20)
    A.loft("Pelvis", PELVIS, "cream", seg=24)
    A.loft("Crotch", [(1.02, 0, 0.0, 0.05, 0.07, 3), (1.10, 0, 0.0, 0.075, 0.09, 3)], "navy", seg=16)
    A.loft("Belt", BELT, "gold", seg=32)
    for z, nm in ((1.25, "Lo"), (1.30, "Hi")):
        T("BeltEdge" + nm, [A.on_loft(BELT, "z", th, z, lift=0.002) for th in [k * math.pi / 12 for k in range(25)]], r=0.007, mat="bronze")
    for k in range(10):
        th = 0.5 + k * (2 * math.pi - 1.0) / 9
        A.ball("BeltStud%d" % k, A.on_loft(BELT, "z", th, 1.275, lift=0.0), 0.011, "bronze", seg=8, outline=0.0)
    # the sun on the chest
    A.limb("SunDisc", (0, -0.16, 1.53), (0, -0.178, 1.53), 0.07, 0.066, "gold", seg=24)
    A.torus("SunRing", (0, -0.18, 1.53), 0.056, 0.009, "bronze", normal=(0, 1, 0), seg=24, outline=0.002)
    A.ball("SunCore", (0, -0.182, 1.53), 0.05, "cyan", scale=(1, 0.35, 1), outline=0.002)
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        d = V((math.cos(a), 0, math.sin(a)))
        A.cone("SunRay.%d" % k, V((0, -0.168, 1.53)) + d * 0.06, V((0, -0.168, 1.53)) + d * (0.14 if k % 2 else 0.105), 0.021, "gold", seg=4, outline=0.003)
    # the bull's head on the belt
    A.loft("Bull", [(1.30, 0, -0.165, 0.062, 0.035, 3.2), (1.25, 0, -0.17, 0.05, 0.038, 3.0), (1.19, 0, -0.18, 0.034, 0.034, 2.8), (1.165, 0, -0.185, 0.036, 0.03, 2.6)], "gold", seg=18)
    A.box("BullBrow", (0.11, 0.025, 0.02), (0, -0.20, 1.285), "bronze", bevel=0.006, outline=0.003)
    for sx, sd in ((-1.0, "R"), (1.0, "L")):
        A.cone("BullHorn." + sd, (sx * 0.05, -0.17, 1.295), (sx * 0.125, -0.18, 1.35), 0.018, "gold", seg=10, curve=0.32, side=(0, 0, -1), outline=0.003)
        A.cone("BullEar." + sd, (sx * 0.055, -0.17, 1.27), (sx * 0.10, -0.165, 1.262), 0.014, "gold", seg=8, outline=0.003)
        A.ball("BullEye." + sd, (sx * 0.027, -0.207, 1.258), 0.008, "dark", outline=0.0)
        A.ball("BullNostril." + sd, (sx * 0.014, -0.214, 1.178), 0.006, "dark", outline=0.0)
        # shoulder pads: two layered plates with gold piping, a gold inner edge, a cyan stone in front
        A.box("Pad." + sd, (0.29, 0.31, 0.12), (sx * 0.325, 0, 1.69), "cream", taper=(0.62, 0.74), rot=(0, sx * 0.24, 0), bevel=0.03)
        A.box("PadLow." + sd, (0.23, 0.33, 0.07), (sx * 0.36, 0, 1.625), "cream", taper=(1.12, 1.0), rot=(0, sx * 0.42, 0), bevel=0.02)
        A.box("PadTrim." + sd, (0.04, 0.34, 0.18), (sx * 0.20, 0, 1.635), "gold", rot=(0, sx * 0.3, 0), bevel=0.012)
        A.box("PadCrest." + sd, (0.17, 0.05, 0.035), (sx * 0.32, 0, 1.752), "cream", taper=(0.6, 0.6), rot=(0, sx * 0.24, 0), bevel=0.01)
        G("PadLine." + sd, [(sx * 0.25, -0.118, 1.722), (sx * 0.33, -0.125, 1.70), (sx * 0.42, -0.118, 1.672)])
        G("PadLineTop." + sd, [(sx * 0.27, -0.09, 1.745), (sx * 0.27, 0.0, 1.752), (sx * 0.27, 0.09, 1.745)])
        A.ball("PadStone." + sd, (sx * 0.215, -0.15, 1.64), 0.04, "cyan", scale=(1, 0.5, 1.25), outline=0.003)
        A.torus("PadStoneRing." + sd, (sx * 0.215, -0.155, 1.64), 0.043, 0.008, "gold", normal=(0, 1, 0), seg=18, outline=0.002)
        # tassels: a cord, a gold bead, the tassel's head and skirt
        A.tube("Cord." + sd, [(sx * 0.13, -0.15, 1.25), (sx * 0.14, -0.20, 1.12), (sx * 0.14, -0.21, 0.99)], 0.008, "red", seg=8)
        A.ball("TasselBead." + sd, (sx * 0.14, -0.21, 0.985), 0.016, "gold", outline=0.003)
        A.ball("TasselHead." + sd, (sx * 0.14, -0.21, 0.96), 0.02, "red", outline=0.003)
        A.cone("Tassel." + sd, (sx * 0.14, -0.21, 0.84), (sx * 0.14, -0.21, 0.965), 0.027, "red", seg=12, outline=0.003)
        # hip skirts: an outer plate and a smaller one under it
        A.box("Skirt." + sd, (0.06, 0.24, 0.34), (sx * 0.235, 0.0, 1.085), "cream", taper=(1.0, 0.72), rot=(0, sx * -0.16, math.pi), bevel=0.02)
        A.box("SkirtLow." + sd, (0.045, 0.17, 0.16), (sx * 0.262, 0.0, 0.90), "cream", taper=(1.0, 0.6), rot=(0, sx * -0.2, math.pi), bevel=0.014)
        G("SkirtLine." + sd, [(sx * 0.262, -0.07, 1.20), (sx * 0.276, -0.075, 1.07), (sx * 0.287, -0.05, 0.95)])
        A.ball("SkirtStud." + sd, (sx * 0.263, 0.0, 1.20), 0.013, "gold", outline=0.002)


def plated(name, a, b, core, plates, front=(0, -1, 0)):
    """A limb: a navy core with cream armour shells over it."""
    A.limb_loft(name + "Core", a, b, [(f, 0, 0, r, r, 2.4) for f, r in core], "navy", front=front, seg=18)
    for k, (secs, th0, th1) in enumerate(plates):
        A.shell("%sPlate%d" % (name, k), a, b, secs, th0, th1, thick=0.02, front=front, seg=20)


def arms():
    for sx, sd in ((-1.0, "R"), (1.0, "L")):
        z = 1.60
        S, E, W = V((sx * 0.31, 0, z)), V((sx * 0.615, 0, z)), V((sx * 0.90, 0, z))
        up = (0, 0, 1)
        A.ball("Shoulder." + sd, S, 0.078, "navy")
        A.torus("ShoulderRing." + sd, S + V((sx * 0.055, 0, 0)), 0.06, 0.012, "cream", normal=(1, 0, 0), seg=20)
        ua = [(0.16, 0.074, 0.08, 3.4), (0.5, 0.078, 0.084, 3.5), (0.84, 0.068, 0.074, 3.4)]
        plated("UpperArm." + sd, S, E, [(0, 0.058), (1, 0.05)], [(ua, -2.5, 2.5)], front=up)
        G("UpperArmLine." + sd, [A.on_limb(S, E, ua, 0.0, f, front=up) for f in (0.2, 0.5, 0.8)])
        G("UpperArmBand." + sd, [A.on_limb(S, E, ua, th, 0.62, front=up) for th in (-1.6, -0.8, 0.0, 0.8, 1.6)])
        A.ball("Elbow." + sd, E, 0.058, "navy")
        A.box("ElbowCap." + sd, (0.08, 0.09, 0.05), E + V((0, 0.045, 0.0)), "cream", taper=(0.7, 0.7), rot=(-math.pi / 2, 0, 0), bevel=0.014)
        fa = [(0.10, 0.09, 0.082, 3.8), (0.35, 0.095, 0.085, 3.8), (0.72, 0.07, 0.066, 3.5)]
        plated("Forearm." + sd, E, W, [(0, 0.05), (1, 0.045)], [(fa, -3.0, 3.0)], front=up)
        A.box("ForearmFin." + sd, (0.17, 0.035, 0.05), (sx * 0.73, 0, z + 0.085), "cream", taper=(0.55, 0.6), bevel=0.01)
        G("ForearmLine." + sd, [A.on_limb(E, W, fa, 0.9, f, front=up) for f in (0.14, 0.4, 0.68)])
        G("ForearmLine2." + sd, [A.on_limb(E, W, fa, -0.9, f, front=up) for f in (0.14, 0.4, 0.68)])
        T("ForearmTrim." + sd, [A.on_limb(E, W, fa, th, 0.115, front=up) for th in (-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4)], r=0.005)
        A.limb("Bracer." + sd, (sx * 0.845, 0, z), (sx * 0.935, 0, z), 0.07, 0.066, "gold", seg=20)
        for xx in (0.848, 0.932):
            A.torus("BracerRim%d.%s" % (int(xx * 1000), sd), (sx * xx, 0, z), 0.068, 0.008, "bronze", normal=(1, 0, 0), seg=20, outline=0.002)
        A.ball("BracerStone." + sd, (sx * 0.89, -0.035, z + 0.058), 0.028, "cyan", scale=(1.3, 1, 0.6), outline=0.002)
        A.ball("BracerStoneF." + sd, (sx * 0.89, -0.066, z), 0.024, "cyan", scale=(1.3, 0.5, 1.0), outline=0.002)
        A.ball("Wrist." + sd, (sx * 0.95, 0, z), 0.042, "navy")
        A.loft("Palm." + sd, [(-0.05, sx * 0.975, z, 0.03, 0.02, 3), (0.0, sx * 1.0, z, 0.045, 0.022, 3.2), (0.05, sx * 0.99, z, 0.04, 0.02, 3)], "navy", axis="y", seg=14)
        A.box("HandPlate." + sd, (0.07, 0.08, 0.016), (sx * 1.0, 0, z + 0.024), "cream", bevel=0.006)
        for k, dy in enumerate((-0.042, -0.014, 0.014, 0.042)):
            p0 = V((sx * 1.04, dy, z))
            p1 = V((sx * (1.095 - abs(dy) * 0.3), dy * 1.3, z - 0.004))
            p2 = V((sx * (1.14 - abs(dy) * 0.5), dy * 1.5, z - 0.012))
            A.limb("Finger%dA.%s" % (k, sd), p0, p1, 0.016, 0.014, "navy", seg=8, outline=0.003)
            A.ball("Finger%dK.%s" % (k, sd), p1, 0.015, "ball", seg=8, outline=0.002)
            A.limb("Finger%dB.%s" % (k, sd), p1, p2, 0.014, 0.012, "navy", seg=8, outline=0.003)
            A.cone("Finger%dC.%s" % (k, sd), p2, p2 + (p2 - p1).normalized() * 0.05, 0.012, "navy", seg=8, outline=0.003)
        t0, t1 = V((sx * 0.985, -0.045, z)), V((sx * 1.03, -0.085, z - 0.005))
        A.limb("ThumbA." + sd, t0, t1, 0.017, 0.014, "navy", seg=8, outline=0.003)
        A.cone("ThumbC." + sd, t1, t1 + V((sx * 0.045, -0.035, -0.005)), 0.014, "navy", seg=8, outline=0.003)


def legs():
    for sx, sd in ((-1.0, "R"), (1.0, "L")):
        H, K, AK = V((sx * 0.12, 0.01, 1.10)), V((sx * 0.18, -0.06, 0.70)), V((sx * 0.23, 0.06, 0.27))
        A.ball("Hip." + sd, H, 0.088, "navy")
        tu = [(0.05, 0.118, 0.122, 3.6), (0.3, 0.125, 0.128, 3.7), (0.52, 0.116, 0.12, 3.6)]
        tl = [(0.57, 0.112, 0.116, 3.6), (0.78, 0.10, 0.104, 3.5), (0.94, 0.086, 0.09, 3.3)]
        side = (1.25, 2.5) if sx > 0 else (-2.5, -1.25)
        plated("Thigh." + sd, H, K, [(0, 0.09), (0.5, 0.095), (1, 0.07)], [(tu, -1.2, 1.2), (tl, -1.35, 1.35), ([(0.1, 0.124, 0.118, 3.5), (0.5, 0.128, 0.12, 3.5), (0.85, 0.108, 0.10, 3.4)], *side)])
        G("ThighLine." + sd, [A.on_limb(H, K, tl, 0.0, f) for f in (0.6, 0.75, 0.92)])
        G("ThighV." + sd, [A.on_limb(H, K, tu, -0.9, 0.12), A.on_limb(H, K, tu, 0.0, 0.34), A.on_limb(H, K, tu, 0.9, 0.12)])
        T("ThighTrim." + sd, [A.on_limb(H, K, tu, th, 0.5) for th in (-1.15, -0.6, 0.0, 0.6, 1.15)], r=0.005)
        A.ball("Knee." + sd, K, 0.072, "navy")
        A.limb("KneeDisc." + sd, K + V((sx * 0.06, 0, 0)), K + V((sx * 0.095, 0, 0)), 0.05, 0.044, "gold", seg=16)
        A.ball("KneeHub." + sd, K + V((sx * 0.097, 0, 0)), 0.022, "bronze", scale=(0.5, 1, 1), outline=0.002)
        A.loft("KneeCap." + sd, [(K.z - 0.11, K.x, K.y - 0.075, 0.05, 0.028, 3.2), (K.z - 0.02, K.x, K.y - 0.10, 0.082, 0.045, 3.6),
                                 (K.z + 0.07, K.x, K.y - 0.095, 0.074, 0.04, 3.6), (K.z + 0.14, K.x, K.y - 0.07, 0.045, 0.024, 3.0)], "cream", seg=20)
        G("KneeLine." + sd, [(K.x - 0.05, K.y - 0.148, K.z + 0.02), (K.x, K.y - 0.153, K.z - 0.01), (K.x + 0.05, K.y - 0.148, K.z + 0.02)])
        su = [(0.03, 0.10, 0.112, 4.0), (0.25, 0.118, 0.132, 4.2), (0.55, 0.098, 0.108, 4.0)]
        sl = [(0.60, 0.09, 0.098, 4.0), (0.8, 0.078, 0.084, 3.8), (0.95, 0.07, 0.076, 3.5)]
        plated("Shin." + sd, K, AK, [(0, 0.072), (1, 0.052)], [(su, -2.8, 2.8), (sl, -2.7, 2.7)])
        A.box("ShinRidge." + sd, (0.05, 0.035, 0.25), K.lerp(AK, 0.33) + V((0, -0.118, 0)), "cream", taper=(0.6, 1.0), rot=(0.33, 0, 0), bevel=0.012)
        G("ShinChevron." + sd, [A.on_limb(K, AK, su, th, f) for th, f in ((-1.2, 0.1), (-0.6, 0.24), (-0.3, 0.3))])
        G("ShinChevron2." + sd, [A.on_limb(K, AK, su, th, f) for th, f in ((1.2, 0.1), (0.6, 0.24), (0.3, 0.3))])
        G("ShinSide." + sd, [A.on_limb(K, AK, su, sx * 1.5, f) for f in (0.08, 0.3, 0.52)])
        G("ShinLow." + sd, [A.on_limb(K, AK, sl, 0.0, f) for f in (0.63, 0.78, 0.93)])
        T("ShinTrim." + sd, [A.on_limb(K, AK, sl, th, 0.94) for th in (-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4)], r=0.005)
        A.piston("KneePiston." + sd, H.lerp(K, 0.7) + V((0, 0.105, 0)), K.lerp(AK, 0.28) + V((0, 0.10, 0)), "x", "x")
        A.ball("Ankle." + sd, AK, 0.062, "navy")
        A.loft("AnkleCuff." + sd, [(0.215, AK.x, AK.y - 0.01, 0.105, 0.11, 3.6), (0.27, AK.x, AK.y - 0.005, 0.092, 0.098, 3.6), (0.325, AK.x, AK.y, 0.07, 0.076, 3.4)], "cream", seg=22)
        A.box("AnkleFin." + sd, (0.04, 0.09, 0.11), (AK.x + sx * 0.095, AK.y + 0.02, 0.29), "cream", taper=(0.6, 0.5), bevel=0.01)
        x = sx * 0.25
        instep = [(0.13, x, 0.12, 0.055, 0.05, 3), (0.03, x, 0.115, 0.085, 0.07, 3.2), (-0.10, x, 0.09, 0.105, 0.058, 3.3), (-0.185, x, 0.065, 0.098, 0.042, 3.1)]
        A.loft("FootCore." + sd, [(0.14, x, 0.10, 0.05, 0.06, 2.6), (-0.15, x, 0.055, 0.09, 0.04, 2.8)], "navy", axis="y", seg=16)
        A.loft("Instep." + sd, instep, "cream", axis="y", seg=22)
        for side_ in (-1, 1):
            G("InstepLine%d.%s" % (side_, sd), [A.on_loft(instep, "y", 0.85 * side_, t) for t in (0.08, -0.03, -0.15)])
        G("InstepCross." + sd, [A.on_loft(instep, "y", th, -0.07) for th in (-1.2, -0.6, 0.0, 0.6, 1.2)])
        for k, (dx, ln) in enumerate(((-0.085, 0.085), (0.0, 0.105), (0.085, 0.085))):
            d = V((dx * 1.5, -1.0, 0.0)).normalized()
            p0 = V((x + dx * 0.75, -0.175, 0.062))
            p1 = p0 + d * ln * 0.75 + V((0, 0, -0.008))
            p2 = p1 + d * ln * 0.6 + V((0, 0, -0.012))
            A.limb("Toe%dA.%s" % (k, sd), p0, p1, 0.046, 0.04, "cream", seg=12)
            A.ball("Toe%dK.%s" % (k, sd), p1, 0.036, "navy", outline=0.003)
            A.limb("Toe%dB.%s" % (k, sd), p1, p2, 0.038, 0.032, "cream", seg=12)
            A.torus("Toe%dRing.%s" % (k, sd), p2, 0.03, 0.007, "bronze", normal=tuple(d), seg=12, outline=0.002)
            A.cone("Claw%d.%s" % (k, sd), p2, p2 + d * 0.10 + V((0, 0, -0.045)), 0.034, "gold", seg=12, curve=0.2, side=(0, 0, 1), outline=0.004)
        A.limb("Heel." + sd, (x, 0.10, 0.10), (x, 0.17, 0.06), 0.04, 0.03, "navy", seg=10)
        A.cone("HeelClaw." + sd, (x, 0.165, 0.062), (x, 0.235, 0.005), 0.028, "gold", seg=10, curve=0.15, side=(0, 0, 1), outline=0.003)


def cloth():
    def kilt(u, v):
        return ((u - 0.5) * 0.34 * (1 + 0.32 * v), -0.135 - 0.075 * v - 0.02 * math.sin(math.pi * u), 1.245 - 0.49 * v)
    A.sheet("Kilt", kilt, 12, 10, "kilt", thick=0.012)

    def cape(u, v):
        a = math.radians(-112 + 224 * u)
        R = 0.36 + 0.30 * v + 0.03 * math.sin(u * 14 * 2 * math.pi) * v ** 1.5
        return (R * math.sin(a), 0.05 + R * math.cos(a) * 0.62 + 0.12 * v, 1.69 - v * (1.20 - 0.22 * abs(math.sin(a))))
    A.sheet("Cape", cape, 112, 24, "cape", thick=0.014)
    A.tube("CapeCollar", [(-0.22, -0.09, 1.69), (-0.3, 0.1, 1.70), (-0.17, 0.26, 1.70), (0.0, 0.3, 1.70), (0.17, 0.26, 1.70), (0.3, 0.1, 1.70), (0.22, -0.09, 1.69)], 0.022, "gold", seg=10)
    both(lambda sx, s: A.ball("CapeClasp." + s, (sx * 0.215, -0.14, 1.64), 0.04, "cyan", scale=(1, 0.5, 1.2), outline=0.003))


def stage():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("TRI_World")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*A._lin((0.58, 0.0, 0.90)), 1)
    sc.world = w
    coll = A._coll()
    for name, loc, e in (("TRI_Key", (-1.5, -3.0, 3.5), 3.2), ("TRI_Fill", (3.0, -1.5, 1.5), 0.9)):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = e
        ld.use_shadow = False
        ob = bpy.data.objects.new(name, ld)
        coll.objects.link(ob)
        ob.rotation_euler = (V((0, 0, 1.0)) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    for name, loc, rot, scale, res in (("TRI_CamFront", (0, -8, 1.12), (math.pi / 2, 0, 0), 2.33, (1150, 1020)),
                                       ("TRI_CamLeft", (8, 0, 1.12), (math.pi / 2, 0, math.pi / 2), 2.33, (700, 1020))):
        cd = bpy.data.cameras.new(name)
        cd.type = "ORTHO"
        cd.ortho_scale = scale * max(res[0] / res[1], 1.0)
        cam = bpy.data.objects.new(name, cd)
        cam.location, cam.rotation_euler = loc, rot
        cam["res"] = res
        coll.objects.link(cam)
    sc.camera = bpy.data.objects["TRI_CamFront"]


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials()
    before = set(bpy.data.objects.keys())
    head()
    pivot = V((0, 0.0, 1.66))                 # the head is a little larger than it was laid out: the sheet's is big
    for name in set(bpy.data.objects.keys()) - before:
        for v in bpy.data.objects[name].data.vertices:
            v.co = pivot + (v.co - pivot) * 1.17
    torso(); arms(); legs(); cloth(); stage()


def previews():
    sc = bpy.context.scene
    for cam, name in (("TRI_CamFront", "front"), ("TRI_CamLeft", "left")):
        ob = bpy.data.objects[cam]
        sc.camera = ob
        sc.render.resolution_x, sc.render.resolution_y = ob["res"]
        sc.render.filepath = os.path.join(HERE, "renders", name + ".png")
        bpy.ops.render.render(write_still=True)
    sc.camera = bpy.data.objects["TRI_CamFront"]
    sc.render.resolution_x, sc.render.resolution_y = bpy.data.objects["TRI_CamFront"]["res"]


if __name__ == "__main__":
    build()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "tricera_android.blend"))
    previews()
