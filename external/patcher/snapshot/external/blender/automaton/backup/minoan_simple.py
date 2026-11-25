"""The Minoan android (the towns' guards and citizens), from the 2D game's
sheets (external/2d_game/art/android_rifle, android_bow, android_axe): a
machine of ceramic and bronze in a triceratops's image - a beaked head with
two brow horns and a nose horn, a great bone frill painted with red spirals
and ringed with gold studs, glowing cyan eyes; cream ceramic plates over a
navy frame, a red cape, a white kilt with a patterned hem and a gold belt,
clawed three-toed feet. Armed three ways - a laser rifle, a laser bow (a
quiver on its back) and a labrys, the Minoan double axe - each weapon on its
own materials (MIN_Rifle*, MIN_Bow*, MIN_Axe*): the game shows one of them
(CosmosModels.apply's `hide`), so the three are one model."""
import math

from mathutils import Vector

import automaton as A
import kit
import pirate
from kit import ball, bone, box, decal, loft, mirror, plate, rot, tube

GUN_HAND_R = (0.0, -0.075, -0.03)
GUN_HAND_L = (0.0, 0.26, -0.03)
KNEE_Z = kit.HIP_Z - kit.THIGH
AZ = kit.ANKLE_Z

# The cape: hanging from the shoulders down the back (the pirate's coat-tail solver).
EXTRA_BONES = {
    "coat.B": ("pelvis", (0.0, 0.14, 1.52), (0, 0, -1), (0, -1, 0), 1.2),
}
tail_solver = pirate.tail_solver


def materials():
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#efe2c2", shade=0.62, hi=0.06, tint=(0.95, 0.9, 0.96)),
        "armor2": kit.mat_toon("AUT_Armor2", "#d6c294", shade=0.64, tint=(0.95, 0.9, 0.96)),
        "joint": kit.mat_toon("MIN_Joint", "#22365c", shade=0.62),
        "grey": kit.mat_toon("MIN_Navy", "#30507e", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#b8261c", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#7a1712", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#48e2ff", 1.6),
        "glow_y": kit.mat_glow("AUT_GlowY", "#c8f8ff", 1.7),
        "gold": kit.mat_toon("MIN_Gold", "#e6b440", shade=0.66, hi=0.15),
        "horn": kit.mat_toon("MIN_Horn", "#f2ead6", shade=0.64, hi=0.05),
        "claw": kit.mat_toon("MIN_Claw", "#2b2420", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("MIN_Cloth", "#f1ebdd", shade=0.66),
        "coat": kit.mat_toon("MIN_Cape", "#a5241d", shade=0.62),
        "coat2": kit.mat_toon("MIN_Cape2", "#6c1511", shade=0.66),
        # the weapons, each its own (a variant shows one)
        "rifle": kit.mat_toon("MIN_RifleBody", "#e9d9ae", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#2c3c5e", shade=0.62, hi=0.1),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#4fe6ff", 1.8),
        "bow": kit.mat_toon("MIN_BowGold", "#e9b84a", shade=0.66, hi=0.15),
        "bow_g": kit.mat_glow("MIN_BowGlow", "#5ef0ff", 2.0),
        "bow_q": kit.mat_toon("MIN_BowQuiver", "#c99a3a", shade=0.66),
        "axe": kit.mat_toon("MIN_AxeBlade", "#efe2c2", shade=0.64, hi=0.1),
        "axe_r": kit.mat_toon("MIN_AxeRed", "#a8241c", shade=0.66),
        "axe_g": kit.mat_glow("MIN_AxeGlow", "#5ef0ff", 2.0),
        "axe_h": kit.mat_toon("MIN_AxeHaft", "#7a1d18", shade=0.66, hi=0.05),
        "ink": kit.mat_outline(),
    })


def spiral(r0, r1, turns, w, n=18):
    """A painted spiral, as one outline: out along it, back on its other edge."""
    outer, inner = [], []
    for i in range(n + 1):
        t = i / n
        a = t * turns * math.tau
        r = r0 + (r1 - r0) * t
        outer.append(((r + w / 2) * math.cos(a), (r + w / 2) * math.sin(a)))
        inner.append(((r - w / 2) * math.cos(a), (r - w / 2) * math.sin(a)))
    return outer + inner[::-1]


def legs(sx, sf):
    hx = kit.HIP_X * sx
    bone("thigh" + sf)
    ball("Hip", (hx, 0, kit.HIP_Z), 0.085, "joint")
    loft("ThighCore", (hx, 0.005, kit.HIP_Z - 0.03), (hx, 0.0, KNEE_Z + 0.02), [(0, 0.08, 0.088), (1, 0.056, 0.062)], mat="joint")
    loft("ThighArmor", (hx + 0.012 * sx, -0.016, kit.HIP_Z - 0.06), (hx + 0.004 * sx, -0.016, KNEE_Z + 0.09),
         [(0, 0.07, 0.08, 3), (0.3, 0.085, 0.094, 3), (1, 0.058, 0.066, 3)], cap=0.7)
    bone("shin" + sf)
    ball("Knee", (hx, 0.0, KNEE_Z), 0.06, "joint")
    box("KneeCap", (0.09, 0.05, 0.11), (hx, -0.06, KNEE_Z), taper=((0.8, 1.0), (0.7, 0.8)), r=rot(8), mat="armor")
    loft("ShinCore", (hx, 0.01, KNEE_Z - 0.03), (hx, 0.02, AZ + 0.02), [(0, 0.052, 0.058), (1, 0.04, 0.046)], mat="joint")
    loft("Greave", (hx, -0.01, KNEE_Z - 0.08), (hx, 0.0, AZ + 0.06), [(0, 0.056, 0.062, 3), (0.35, 0.066, 0.08, 3), (1, 0.05, 0.058, 3)],
         cap=0.6, mat="armor")
    tube("AnkleRing", (hx, 0.0, AZ + 0.07), (hx, 0.0, AZ + 0.04), 0.06, 0.058, mat="gold", seg=14)
    # the foot: a dinosaur's - three toes forward, a spur back, dark claws
    bone("foot" + sf)
    ball("Ankle", (hx, 0.0, AZ), 0.05, "joint")
    box("Instep", (0.11, 0.14, 0.07), (hx, -0.04, 0.05), mat="armor", taper=(0.9, 0.85), bevel=0.016)
    for k, (dx, ln) in enumerate(((-0.035, 0.1), (0.0, 0.12), (0.035, 0.1))):
        x = hx + dx * sx
        box("Toe", (0.034, ln, 0.04), (x, -0.13 - ln * 0.3, 0.025), mat="armor", taper=(0.8, 0.7), bevel=0.01, r=rot(0, 0, dx * 300 * sx))
        tube("Claw", (x + dx * 0.4 * sx, -0.13 - ln * 0.75, 0.03), (x + dx * 0.6 * sx, -0.13 - ln * 1.05, 0.004), 0.016, 0.003,
             mat="claw", seg=8, outline=0.003)
    tube("Spur", (hx, 0.05, 0.04), (hx, 0.11, 0.005), 0.016, 0.003, mat="claw", seg=8, outline=0.003)


def kilt():
    bone("pelvis")
    # the white kilt, wider at the hem, its patterned band, the gold belt
    loft("Kilt", (0, 0.005, 1.06), (0, 0.01, 0.74), [(0, 0.17, 0.125, 3), (0.6, 0.19, 0.15, 3), (1, 0.21, 0.17, 3)], mat="cloth", cap=0.0)
    loft("KiltHem", (0, 0.01, 0.80), (0, 0.01, 0.735), [(0, 0.203, 0.165, 3), (1, 0.212, 0.172, 3)], mat="red", cap=0.0)
    for k in range(10):
        a = k / 10 * math.tau
        p = (math.sin(a) * 0.21, -math.cos(a) * 0.172 + 0.01, 0.768)
        ball("HemDot", p, 0.012, "gold", seg=8)
    box("Belt", (0.32, 0.24, 0.05), (0, 0.004, 1.08), mat="gold", bevel=0.014)
    bk = box("MinBuckle", (0.08, 0.03, 0.07), (0, -0.125, 1.08), mat="gold", bevel=0.012)
    decal("BuckleSpiral", spiral(0.004, 0.024, 1.6, 0.006), (0, -0.142, 1.08), (0, -1, 0), bk, mat="red2", outline=0, offset=0.006, cuts=0)
    # an apron panel down the front, its spirals
    ap = box("Apron", (0.12, 0.02, 0.26), (0, -0.155, 0.92), mat="cloth", bevel=0.006)
    for z in (0.98, 0.88):
        decal("ApronSpiral", spiral(0.004, 0.03, 1.7, 0.008), (0, -0.166, z), (0, -1, 0), ap, mat="red", outline=0, cuts=0)


def cape():
    bone("chest")
    box("CapeClasp", (0.36, 0.12, 0.06), (0, 0.06, 1.57), mat="coat2", bevel=0.016)
    for sx in (1.0, -1.0):
        ball("CapeBrooch", (0.17 * sx, -0.06, 1.55), 0.03, "gold", seg=12)
    bone("coat.B")
    pts = [(-0.18, 0.0), (0.18, 0.0), (0.27, -1.18), (0.1, -1.22), (-0.1, -1.2), (-0.27, -1.18)]
    cb = plate("CapeBack", pts, (0.0, 0.16, 1.52), (0, 1, 0), thick=0.018, mat="coat", outline=0.006)
    plate("CapeBackIn", [(x * 0.92, y * 0.97) for (x, y) in pts], (0.0, 0.145, 1.51), (0, 1, 0), thick=0.01, mat="coat2", outline=0)
    decal("CapeSpiral", spiral(0.01, 0.08, 1.8, 0.02), (0.0, 0.175, 1.05), (0, 1, 0), cb, mat="gold", outline=0, cuts=0)



def head():
    bone("head")
    tube("Neck", (0, 0.02, 1.57), (0, 0.0, 1.69), 0.055, 0.05, mat="joint")
    # the skull and its beak, reaching forward
    skull = loft("Skull", (0, 0.06, 1.72), (0, -0.16, 1.70),
                 [(0, 0.075, 0.085, 2.6), (0.4, 0.07, 0.08, 2.6), (0.8, 0.045, 0.055, 2.4), (1, 0.02, 0.03, 2)], mat="horn", cap=0.5,
                 front=(0, 0, 1))
    loft("Beak", (0, -0.13, 1.69), (0, -0.21, 1.655), [(0, 0.03, 0.035, 2.4), (1, 0.006, 0.01, 2)], mat="horn2" if "horn2" in kit.M else "armor2",
         cap=0.3, front=(0, 0, 1))
    loft("Jaw", (0, 0.02, 1.66), (0, -0.14, 1.65), [(0, 0.055, 0.03, 2.4), (1, 0.02, 0.016, 2)], mat="armor2", cap=0.4, front=(0, 0, 1))
    # the horns: two over the brows, curving forward; a small one on the nose
    for sx in (1.0, -1.0):
        tube("BrowHorn", (0.04 * sx, -0.02, 1.77), (0.06 * sx, -0.11, 1.86), 0.022, 0.012, mat="horn", seg=10)
        tube("BrowHornTip", (0.06 * sx, -0.11, 1.86), (0.065 * sx, -0.21, 1.89), 0.012, 0.002, mat="horn", seg=10)
        ball("EyeRim", (0.05 * sx, -0.07, 1.74), 0.022, "joint", seg=10)
        ball("Eye", (0.058 * sx, -0.08, 1.742), 0.015, "glow", seg=10, outline=0)
    tube("NoseHorn", (0, -0.15, 1.72), (0, -0.17, 1.77), 0.016, 0.002, mat="horn", seg=8)
    # the frill: a great fan of bone behind the head, its blue rim, red spirals, gold studs
    fan = []
    for k in range(25):
        a = math.radians(-105 + 210 * k / 24)
        r = 0.23 * (1.0 + 0.04 * math.cos(k * math.pi))      # (a scalloped edge)
        fan.append((math.sin(a) * r, math.cos(a) * r))
    fan.append((0.0, -0.05))
    frill_at = (0, 0.07, 1.80)
    nrm = (0, -1, 0.35)
    plate("FrillRim", [(x * 1.08, y * 1.08) for (x, y) in fan], (0, 0.085, 1.80), nrm, up=(0, 0.35, 1), thick=0.016, mat="grey", outline=0.006)
    fr = plate("Frill", fan, frill_at, nrm, up=(0, 0.35, 1), thick=0.02, mat="armor", outline=0.004)
    for sx in (1.0, -1.0):
        decal("FrillSpiral", spiral(0.008, 0.06, 1.8, 0.018), (0.11 * sx, 0.04, 1.89), nrm, fr, mat="red", up=(0, 0.35, 1), outline=0, cuts=0)
    decal("FrillSpiralTop", spiral(0.006, 0.045, 1.6, 0.016), (0, 0.04, 1.96), nrm, fr, mat="red", up=(0, 0.35, 1), outline=0, cuts=0)
    for k in range(13):
        a = math.radians(-95 + 190 * k / 12)
        p = Vector(frill_at) + Vector((math.sin(a) * 0.235, 0.025 - math.cos(a) * 0.235 * 0.33, math.cos(a) * 0.235 * 0.94))
        ball("FrillStud", tuple(p), 0.017, "gold", seg=8, outline=0.003)


def pauldron_mark(pd, x, sx, S):
    decal("PauldronDisc", [(0.06 * math.cos(a / 12 * math.tau), 0.06 * math.sin(a / 12 * math.tau)) for a in range(12)],
          (x + 0.14 * sx, 0.0, S.z - 0.02), (sx, -0.05, 0.1), pd, mat="gold", outline=0.002, offset=0.003, thick=0.005, cuts=1)
    decal("PauldronSpiral", spiral(0.004, 0.04, 1.6, 0.01), (x + 0.14 * sx, 0.0, S.z - 0.015), (sx, -0.05, 0.1), pd,
          mat="red", outline=0, offset=0.009, cuts=1)


def rifle():
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    box("RGrip", (0.036, 0.048, 0.10), at(-0.012, -0.02), mat="rifle_d", r=rot(-14), bevel=0.008)
    box("RReceiver", (0.068, 0.36, 0.10), at(0.07, 0.072), mat="rifle", bevel=0.014)
    box("RTrim", (0.072, 0.30, 0.018), at(0.07, 0.125), mat="bow", bevel=0.004, outline=0.003)
    box("RStock", (0.05, 0.22, 0.08), at(-0.21, 0.058), mat="rifle", taper=(1.0, 0.8), bevel=0.014)
    box("RFore", (0.064, 0.26, 0.08), at(0.36, 0.07), mat="rifle_d", bevel=0.012)
    for k in range(3):
        box("RCell", (0.07, 0.04, 0.05), at(0.29 + k * 0.07, 0.07), mat="rifle_g", bevel=0.006, outline=0.003)
    tube("RBarrel", at(0.48, 0.08), at(0.74, 0.08), 0.026, mat="rifle", seg=12)
    tube("RMuzzle", at(0.72, 0.08), at(0.80, 0.08), 0.036, mat="rifle_d", seg=12)
    tube("RMuzzleGlow", at(0.795, 0.08), at(0.806, 0.08), 0.02, mat="rifle_g", seg=10, outline=0)
    box("RMag", (0.045, 0.08, 0.11), at(0.10, -0.025), mat="rifle_d", r=rot(8), bevel=0.008)


def bow():
    """The laser bow: gold limbs curving back from the grip (upright, at the
    left hand), a string of light drawn back to the right hand, an arrow of light."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))
    grip_y = 0.26

    def at(fwd, up, side=0.0):
        return Vector((g.x + side, g.y - fwd, g.z + up))
    box("BGrip", (0.04, 0.05, 0.12), tuple(at(grip_y, 0.0)), mat="bow_q", bevel=0.01)
    for s in (1.0, -1.0):
        pts = [at(grip_y, 0.05 * s)]
        for k in range(1, 7):
            t = k / 6
            pts.append(at(grip_y - 0.05 * t * t - 0.02 * math.sin(t * math.pi), (0.05 + 0.5 * t) * s))
        for k in range(len(pts) - 1):
            tube("BLimb", tuple(pts[k]), tuple(pts[k + 1]), 0.018 - 0.002 * k, mat="bow", seg=8, outline=0.004)
        ball("BTip", tuple(pts[-1]), 0.02, "bow", seg=8)
        tube("BString", tuple(pts[-1]), tuple(at(-0.075, 0.0)), 0.004, mat="bow_g", seg=6, outline=0)
    tube("BArrow", tuple(at(-0.075, 0.0)), tuple(at(grip_y + 0.12, 0.0)), 0.006, mat="bow_g", seg=6, outline=0)
    tube("BArrowHead", tuple(at(grip_y + 0.12, 0.0)), tuple(at(grip_y + 0.18, 0.0)), 0.016, 0.001, mat="bow_g", seg=6, outline=0)
    # the quiver on the back (the bow's material: shown with it)
    bone("chest")
    tube("BQuiver", (-0.1, 0.17, 1.22), (0.12, 0.2, 1.62), 0.05, mat="bow_q", seg=12)
    tube("BQuiverRim", (0.11, 0.2, 1.6), (0.125, 0.2, 1.63), 0.056, mat="bow", seg=12)
    for k in range(4):
        tube("BQuiverArrow", (0.10 + k * 0.012 - 0.02, 0.2, 1.6), (0.15 + k * 0.012 - 0.02, 0.21, 1.72), 0.007, mat="bow_g", seg=5, outline=0)


def axe():
    """The labrys: a long red haft, the double blade at its end (two crescents,
    gold-rimmed, red spirals painted on them), its edges of light."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    tube("AHaft", at(-0.2, 0.0), at(0.82, 0.0), 0.022, mat="axe_h", seg=10)
    tube("AButt", at(-0.24, 0.0), at(-0.2, 0.0), 0.03, mat="bow", seg=10)
    tube("ACollar", at(0.66, 0.0), at(0.74, 0.0), 0.034, mat="bow", seg=10)
    for s in (1.0, -1.0):
        blade = [(0.0, 0.03), (0.06, 0.06), (0.15, 0.2), (0.17, 0.26), (0.08, 0.27), (-0.08, 0.27), (-0.17, 0.26), (-0.15, 0.2),
                 (-0.06, 0.06), (0.0, 0.03)]
        pts = [(x, y * s) for (x, y) in blade]
        if s < 0:
            pts = pts[::-1]
        bl = plate("ABlade", pts, at(0.70, 0.0), (1, 0, 0), up=(0, 0, 1), thick=0.02, mat="axe", outline=0.004)
        plate("ABladeRim", [(x * 1.06, y * 1.04) for (x, y) in pts], at(0.70, 0.0, -0.003), (1, 0, 0), up=(0, 0, 1), thick=0.012,
              mat="bow", outline=0.0)
        tube("AEdge", at(0.53, 0.26 * s), at(0.87, 0.26 * s), 0.008, mat="axe_g", seg=6, outline=0)
        for side in (1.0, -1.0):
            decal("ASpiral", spiral(0.004, 0.045, 1.6, 0.012), at(0.70, 0.16 * s, 0.012 * side), (side, 0, 0), bl,
                  mat="axe_r", up=(0, 0, 1), outline=0, cuts=0)


def build():
    materials()
    A.MARK = "spiral"
    A.PAULDRON_MARK[0] = pauldron_mark
    mirror(legs)
    A.body()
    kilt()
    head()
    mirror(A.arms)
    cape()
    rifle()
    bow()
    axe()
