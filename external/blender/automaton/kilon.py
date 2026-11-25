"""Kilon Alios, the hooded wanderer who keeps the worlds for Ephestos (the
2D game's sheet: external/images/kilon_alios_sheet.png): an automaton of grey
steel under a deep pointed hood - its rim piped, two slanted orange eyes in
its shadow - and a long indigo coat to the ankles, open in front: wide lapels,
sleeves to cuffs at the forearms, a belt and crossed straps, pockets at the
hips, its skirts in folds on bones of their own (the pirate's coat-tail
solver), piped at the hem and the front edges. Steel pauldrons with an orange
light, steel gauntlets, heavy boots. Unarmed."""
import math

import automaton as A
import kit
import pirate
from kit import ball, bone, box, decal, loft, mirror, plate, rot, tube

GUN_HAND_R = A.GUN_HAND_R
GUN_HAND_L = A.GUN_HAND_L

EXTRA_BONES = {}         # (the skirts: chains of bones, as the pirate's tails - kit.chain, kit.drape_chain)
EXTRA_BONES.update(kit.chain("coat.B", "pelvis", (0.0, 0.12, 1.10), (0.175, 0.225, 0.25, 0.31)))
EXTRA_BONES.update(kit.chain("coat.L", "pelvis", (0.17, 0.0, 1.10), (0.19, 0.22, 0.24, 0.30)))
EXTRA_BONES.update(kit.chain("coat.R", "pelvis", (-0.17, 0.0, 1.10), (0.19, 0.22, 0.24, 0.30)))
tail_solver = pirate.tail_solver


def materials():
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#a9b0ba", shade=0.6, hi=0.12, tint=(0.92, 0.92, 1.0)),
        "armor2": kit.mat_toon("AUT_Armor2", "#7d8592", shade=0.62, hi=0.08),
        "joint": kit.mat_toon("KIL_Joint", "#24262e", shade=0.62),
        "grey": kit.mat_toon("KIL_Grey", "#6a7180", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#36405a", shade=0.66),
        "red2": kit.mat_toon("AUT_Red2", "#242a3c", shade=0.66),
        "glow": kit.mat_glow("AUT_Glow", "#ff8a24", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#ffc060", 1.8),
        "coat": kit.mat_toon("KIL_Coat", "#383a62", shade=0.6, tint=(0.9, 0.92, 1.05)),
        "coat2": kit.mat_toon("KIL_Coat2", "#1d2138", shade=0.62),
        "gold": kit.mat_toon("KIL_Trim", "#c9a070", shade=0.66, hi=0.12),
        "leather": kit.mat_toon("KIL_Leather", "#6e5b4a", shade=0.64),
        "boot": kit.mat_toon("KIL_Boot", "#8a909b", shade=0.62, hi=0.1),
        "ink": kit.mat_outline(),
    })


# The coat round the chest: (z, rx, ry, cy, how far round each side its front edge is - degrees from behind)
COAT = [(1.085, 0.200, 0.150, 0.004, 150), (1.20, 0.188, 0.138, 0.004, 150), (1.32, 0.212, 0.146, 0.004, 148), (1.46, 0.234, 0.153, 0.004, 147),
        (1.565, 0.228, 0.148, 0.006, 150), (1.615, 0.175, 0.125, 0.012, 152), (1.655, 0.115, 0.105, 0.025, 150)]
TOP = (0.0, 0.004, 0.200, 0.150, 1.085)          # the skirts: where they hang from, their hems
HEM_B = (0.0, 0.06, 0.40, 0.38, 0.13)
HEM_S = (0.0, 0.03, 0.41, 0.31, 0.13)


def _arch(y, w, zc, h, zb, peak=0.0, lean=0.0, n=14):
    """One arch of the hood (across it, at y): down its left side, over the top (lean: its top that far forward), down its right."""
    pts = [(-w * 0.74, y + 0.035 + lean, zb), (-w * 0.95, y + 0.012 + lean * 0.5, (zb + zc) * 0.5)]
    for i in range(n + 1):
        a = math.radians(-90 + 180 * i / n)
        c = max(0.0, math.cos(a))
        pts.append((w * math.sin(a), y - lean * c, zc + h * c ** 0.8 + peak * c ** 6))
    return pts + [(w * 0.95, y + 0.012 + lean * 0.5, (zb + zc) * 0.5), (w * 0.74, y + 0.035 + lean, zb)]


def head():
    bone("head")
    tube("Neck", (0, 0.012, 1.57), (0, 0.006, 1.68), 0.05, 0.048, mat="joint")
    # the face in the hood's shadow: a dark mask, a paler plate down its middle, two slanted lights
    loft("Face", (0, -0.02, 1.645), (0, -0.03, 1.83), [(0, 0.04, 0.056, 3), (0.3, 0.064, 0.078, 3), (0.7, 0.078, 0.086, 2.8), (1, 0.066, 0.074, 2.4)],
         mat="joint", cap=0.5)
    box("Mask", (0.06, 0.016, 0.105), (0, -0.104, 1.705), mat="grey", bevel=0.007, taper=((0.5, 1.0), (1.0, 1.0)), r=rot(-5))
    box("MaskTop", (0.05, 0.016, 0.05), (0, -0.108, 1.80), mat="grey", bevel=0.006, taper=((1.0, 1.0), (0.6, 1.0)), r=rot(10))
    box("MaskBrow", (0.13, 0.034, 0.026), (0, -0.094, 1.80), mat="joint", bevel=0.008, r=rot(14), taper=((1.0, 1.0), (0.85, 0.8)))
    for sx in (1.0, -1.0):
        box("Eye", (0.044, 0.012, 0.014), (0.037 * sx, -0.105, 1.764), mat="glow", bevel=0.0, r=rot(0, 12 * sx, -18 * sx))
        box("Cheek", (0.024, 0.06, 0.07), (0.066 * sx, -0.06, 1.70), mat="grey", bevel=0.008, r=rot(0, -12 * sx, 26 * sx), taper=((0.6, 0.8), (1.0, 1.0)))
    # the hood: deep and pointed, its rim forward of the face, falling behind onto the shoulders
    arches = [_arch(-0.130, 0.108, 1.745, 0.150, 1.60, lean=0.05), _arch(-0.105, 0.130, 1.750, 0.170, 1.59, lean=0.03),
              _arch(-0.040, 0.144, 1.760, 0.188, 1.58, 0.008, lean=0.01), _arch(0.050, 0.140, 1.765, 0.192, 1.575, 0.02),
              _arch(0.120, 0.120, 1.75, 0.172, 1.57, 0.026, lean=-0.02), _arch(0.168, 0.082, 1.69, 0.13, 1.56, 0.01, lean=-0.03),
              _arch(0.20, 0.004, 1.62, 0.05, 1.55)]
    A.skin("Hood", arches, "coat", closed=False, thick=0.016, lining="coat2", inside=(0, 0.0, 1.74))
    A.cable("HoodTrim", [(x, y - 0.004, z) for (x, y, z) in arches[0]], 0.0075, mat="gold", seg=6, steps=1, hint=(0, 1, 0))


def coat():
    rings = pirate._mantle_rings
    # ---- round the chest: open in front, wide lapels, the edges piped; the cowl the hood falls into
    bone("chest")
    zs = [1.30, 1.38, 1.46, 1.52, 1.565, 1.615, 1.655]
    # (a little proud of the waist's part, which it overlaps: a seam, nothing in one plane)
    A.skin("Coat", rings(zs, table=COAT, grow=0.004), "coat", closed=False, thick=0.016, lining="coat2", inside=(0, 0, 1.45))
    for sx in (1.0, -1.0):
        lap = rings(zs[:-1], a_from=(sx, 24), grow=0.014, table=COAT)
        A.skin("Lapel", lap, "coat", closed=False, thick=0.014)
        A.cable("LapelTrim", [r[-1] for r in lap], 0.0065, mat="gold", seg=6, steps=1, hint=(0, 1, 0))
        A.cable("LapelTrim2", [r[0] for r in lap], 0.005, mat="gold", seg=6, steps=1, hint=(0, 1, 0))
        for k in range(2):         # the tabs on the chest, buckled
            z = 1.40 + k * 0.10
            rx, ry, cy, op = pirate._mantle(z, COAT)
            a = math.radians((op - 15) * sx)
            box("Tab", (0.05, 0.012, 0.022), ((rx + 0.024) * math.sin(a), cy + (ry + 0.024) * math.cos(a), z), mat="leather", bevel=0.004,
                r=rot(0, 0, -(180 - (op - 15)) * sx))
            ball("TabStud", ((rx + 0.03) * math.sin(a), cy + (ry + 0.03) * math.cos(a), z), 0.009, "gold", seg=6)
    yoke = [A.arc((0, 0.006, z), rx + 0.017, ry + 0.017, -112, 112, 22) for (z, rx, ry) in ((1.475, 0.234, 0.153), (1.52, 0.232, 0.151), (1.565, 0.228, 0.148),
                                                                                            (1.612, 0.178, 0.127))]
    A.skin("Yoke", yoke, "coat", closed=False, thick=0.012)
    A.cable("YokeTrim", [(x, y, z - 0.004) for (x, y, z) in yoke[0]], 0.006, mat="gold", seg=6, steps=1)
    for sx in (1.0, -1.0):
        box("YokeStrap", (0.03, 0.014, 0.10), (0.11 * sx, 0.172, 1.50), mat="leather", bevel=0.004, r=rot(6))
        box("YokeBuckle", (0.04, 0.016, 0.03), (0.11 * sx, 0.174, 1.47), mat="gold", bevel=0.004, r=rot(6))
    cowl = [A.arc((0, cy, z), rx, ry, -152, 152, 22) for (z, rx, ry, cy) in ((1.555, 0.236, 0.160, 0.008), (1.59, 0.215, 0.152, 0.01),
                                                                           (1.63, 0.16, 0.13, 0.02), (1.672, 0.112, 0.112, 0.03))]
    A.skin("Cowl", cowl, "coat", closed=False, thick=0.016)
    # ---- the waist, the belt over it, crossed straps in front
    bone("spine")
    zw = [1.085, 1.14, 1.20, 1.26, 1.32]
    A.skin("CoatWaist", rings(zw, table=COAT), "coat", closed=False, thick=0.016, lining="coat2", inside=(0, 0, 1.2))
    for sx in (1.0, -1.0):
        lap = rings(zw, a_from=(sx, 24), grow=0.01, table=COAT)
        A.skin("LapelWaist", lap, "coat", closed=False, thick=0.014)
        A.cable("LapelTrim", [r[-1] for r in lap], 0.0065, mat="gold", seg=6, steps=1, hint=(0, 1, 0))
        A.cable("LapelTrim2", [r[0] for r in lap], 0.005, mat="gold", seg=6, steps=1, hint=(0, 1, 0))
        box("Strap", (0.25, 0.014, 0.032), (0, -0.108, 1.165), mat="leather", bevel=0.005, r=rot(0, 30 * sx, 0))
    tube("StrapBuckle", (0, -0.112, 1.165), (0, -0.13, 1.165), 0.034, mat="gold", seg=6)
    tube("StrapBuckleIn", (0, -0.126, 1.165), (0, -0.134, 1.165), 0.018, mat="joint", seg=6)
    bone("pelvis")
    loft("Belt", (0, 0.004, 1.068), (0, 0.004, 1.118), [(0, 0.226, 0.176, 2), (1, 0.224, 0.174, 2)], mat="leather", seg=28)
    box("Buckle", (0.07, 0.02, 0.064), (0, -0.176, 1.093), mat="gold", bevel=0.008)
    box("BuckleIn", (0.036, 0.012, 0.032), (0, -0.186, 1.093), mat="leather", bevel=0.004)
    for sx in (1.0, -1.0):
        box("BeltLoop", (0.02, 0.016, 0.066), (0.085 * sx, 0.176, 1.093), mat="gold", bevel=0.004)
        box("BeltPouch", (0.03, 0.075, 0.085), (0.238 * sx, -0.01, 1.07), mat="leather", bevel=0.01)
    # ---- the skirts, to the ankles: in folds, piped at the hem and down the front edges, pockets at the hips
    bone("coat.B")
    A.drape("TailBack", -64, 64, TOP, HEM_B, cols=20, rows=8, thick=0.016, pleat=0.022, waves=3.5, phase=math.pi, lining="coat2")
    A.drape("TailBackHem", -64, 64, TOP, HEM_B, mat="gold", cols=20, rows=1, thick=0.026, pleat=0.022, waves=3.5, phase=math.pi, t0=0.974, grow=0.002)
    for sx in (1.0, -1.0):
        box("PocketB", (0.12, 0.03, 0.14), (0.125 * sx, 0.202, 0.90), mat="coat", bevel=0.01, r=rot(-10, 0, -12 * sx))
        box("PocketBFlap", (0.13, 0.036, 0.045), (0.125 * sx, 0.194, 0.962), mat="coat", bevel=0.008, r=rot(-10, 0, -12 * sx))
    for sx, sf in ((1.0, ".L"), (-1.0, ".R")):
        bone("coat" + sf)
        arc = (44 * sx, (150 * sx, 161 * sx))          # (over the back skirt's edge, a little proud of it: a vent)
        A.drape("TailSide", arc[0], arc[1], TOP, HEM_S, cols=16, rows=8, thick=0.016, pleat=0.02, waves=3.0, lining="coat2", grow=0.014)
        A.drape("TailSideHem", arc[0], arc[1], TOP, HEM_S, mat="gold", cols=16, rows=1, thick=0.026, pleat=0.02, waves=3.0, t0=0.974, grow=0.016)
        edge = A.drape_rings(arc[0], arc[1], TOP, HEM_S, cols=16, rows=8, pleat=0.02, waves=3.0, grow=0.018)
        A.cable("TailTrim", [r[-1] for r in edge], 0.0075, mat="gold", seg=6, steps=1, hint=(0, 1, 0))
        # a pocket on the hip, its flap; a smaller one in front
        box("Pocket", (0.03, 0.13, 0.15), (0.236 * sx, 0.0, 0.90), mat="coat", bevel=0.01, r=rot(0, 7 * sx, 0))
        box("PocketFlap", (0.036, 0.14, 0.05), (0.236 * sx, 0.0, 0.965), mat="coat", bevel=0.008, r=rot(0, 7 * sx, 0))
        ball("PocketStud", (0.256 * sx, 0.0, 0.95), 0.009, "gold", seg=6)
        box("PocketF", (0.03, 0.10, 0.11), (0.168 * sx, -0.128, 0.92), mat="coat", bevel=0.01, r=rot(0, 5 * sx, 52 * sx))
        box("PocketFFlap", (0.036, 0.108, 0.04), (0.168 * sx, -0.128, 0.968), mat="coat", bevel=0.008, r=rot(0, 5 * sx, 52 * sx))


def arms(sx, sf):
    """An arm in its sleeve: a steel pauldron over the shoulder, the cuff at the forearm, a gauntlet and the hand below it."""
    S = kit.SHOULDER
    x = S.x * sx
    ez = S.z - kit.UPPER
    wz = ez - kit.FORE
    bone("pauldron" + sf)
    pd = loft("Pauldron", (x + 0.066 * sx, 0, S.z + 0.045), (x + 0.082 * sx, 0, S.z - 0.115),
              [(0, 0.036, 0.054, 3.6), (0.25, 0.058, 0.082, 4.0), (0.7, 0.062, 0.088, 4.0), (1, 0.05, 0.072, 3.6)], cap=0.45, seg=20)
    hexa = [(0.05 * math.cos(math.tau * k / 6), 0.05 * math.sin(math.tau * k / 6)) for k in range(6)]
    A.dec("PauldronHex", hexa, (x + 0.15 * sx, 0.0, S.z - 0.025), (sx, 0, 0.1), pd, mat="armor2", outline=0)
    A.dec("PauldronGlow", [(-0.026, 0.007), (0.026, 0.007), (0.02, -0.009), (-0.02, -0.009)], (x + 0.15 * sx, 0.0, S.z - 0.037), (sx, 0, 0.1), pd,
          mat="glow", outline=0, offset=0.009, cuts=1)
    bone("upper" + sf)
    ball("SleeveCap", (x + 0.004 * sx, 0, S.z - 0.005), 0.084, "coat", scale=(1.0, 1.06, 0.96), seg=14)
    loft("Sleeve", (x, 0, S.z - 0.03), (x, 0, ez + 0.005), [(0, 0.074, 0.080, 2.4), (0.5, 0.067, 0.073, 2.4), (1, 0.061, 0.067, 2.4)], mat="coat", seg=16)
    tube("SleeveFold", (x, 0, S.z - 0.15), (x, 0, S.z - 0.19), 0.072, 0.069, mat="coat", seg=14)
    bone("fore" + sf)
    ball("Elbow", (x, 0.0, ez), 0.064, "coat", seg=12)
    loft("SleeveFore", (x, 0, ez + 0.01), (x, 0, ez - 0.115), [(0, 0.058, 0.064, 2.4), (1, 0.066, 0.070, 2.4)], mat="coat", seg=16)
    loft("SleeveCuff", (x, 0, ez - 0.085), (x, 0, ez - 0.135), [(0, 0.070, 0.074, 2.4), (1, 0.072, 0.076, 2.4)], mat="coat2", seg=16)
    tube("CuffTrim", (x, 0, ez - 0.128), (x, 0, ez - 0.14), 0.076, mat="gold", seg=14)
    ga = loft("Gauntlet", (x, -0.004, ez - 0.11), (x, -0.004, wz + 0.02),
              [(0, 0.05, 0.054, 3), (0.45, 0.054, 0.058, 3.2, -0.004 * sx), (1, 0.044, 0.048, 3)], cap=0.5)
    loft("ForeCore", (x, 0, ez - 0.02), (x, 0, wz), [(0, 0.04, 0.044), (1, 0.034, 0.038)], mat="joint", seg=12)
    A.dec("GauntletGlow", [(-0.007, 0.02), (0.007, 0.02), (0.007, -0.02), (-0.007, -0.02)], (x + 0.07 * sx, -0.004, wz + 0.075), (sx, -0.1, 0), ga,
          mat="glow", outline=0, cuts=1)
    A.hand(sx, sf)


def boots(sx, sf):
    hx = kit.HIP_X * sx
    bone("shin" + sf)
    loft("BootShaft", (hx, 0.0, 0.34), (hx, 0.0, 0.10), [(0, 0.074, 0.088, 3), (1, 0.078, 0.092, 3)], mat="boot", cap=0.3)
    for z in (0.30, 0.19):
        tube("BootStrap", (hx, 0.0, z + 0.016), (hx, 0.0, z - 0.016), 0.094, mat="leather", seg=14)
        box("BootBuckle", (0.03, 0.014, 0.03), (hx + 0.03 * sx, -0.092, z), mat="gold", bevel=0.004)
    bone("foot" + sf)
    box("BootFoot", (0.128, 0.31, 0.10), (hx, -0.075, 0.062), mat="boot", taper=(0.86, 0.8), bevel=0.022, shear=(0, 0.02))
    box("BootToe", (0.132, 0.10, 0.07), (hx, -0.19, 0.05), mat="armor2", taper=(0.85, 0.7), bevel=0.02)
    box("BootSole", (0.136, 0.325, 0.03), (hx, -0.078, 0.013), mat="joint", bevel=0.006)


def build():
    materials()
    mirror(A.legs)
    mirror(boots)
    A.body()
    head()
    mirror(arms)
    coat()
