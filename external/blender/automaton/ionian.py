"""The Ionian android: the Minoan android's build (minoan.py) in Ionia's
colours - white marble plates over a dark frame, lapis-blue panels, gold
trim, a blue glow - under its own head: a lapis hadrosaur, duck-billed (the
bill tipped with gold), with a long golden hollow crest sweeping back over
the neck, banded with lapis; a gold scroll on each cheek. Its mark: the
volute, the Ionic capital's scroll, on the pauldrons, the apron and the
buckle. A laser rifle, no cape."""
import math

import kit
import minoan as Mn
from kit import bone, mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#f3f2ee", shade=0.62, hi=0.06),
        "armor2": kit.mat_toon("AUT_Armor2", "#d5d8de", shade=0.64),
        "joint": kit.mat_toon("ION_Joint", "#2b2a3a", shade=0.62),
        "grey": kit.mat_toon("ION_Blue", "#4173d6", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#2243b0", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#162c78", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#3d9bff", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#bfe0ff", 1.8),
        "gold": kit.mat_toon("ION_Gold", "#e9bb3e", shade=0.66, hi=0.15),
        "claw": kit.mat_toon("ION_ClawGold", "#dcae36", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("ION_Cloth", "#f5f3ef", shade=0.66),
        "head": kit.mat_toon("ION_LapisArmor", "#2747b2", shade=0.64, hi=0.08),
        "head2": kit.mat_toon("ION_LapisArmor2", "#1b3384", shade=0.66, hi=0.08),
        "tube": kit.mat_toon("ION_TubeGold", "#ecc040", shade=0.66, hi=0.15),
        "eye": kit.mat_glow("ION_EyeGlow", "#ffe27a", 1.8),
        "rifle": kit.mat_toon("MIN_RifleBody", "#eeeeea", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#1f3a9a", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#e9bb3e", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#5ab0ff", 1.8),
    })
    Mn.paints("grey", "gold")


# ---------------------------------------------------------------- its mark

def m_volute(surf, r, mat="gold", lift=0.005, walls=True):
    """The Ionic capital's scroll: two spirals joined by a band, the abacus over them."""
    a0 = math.radians(90.0) - 1.6 * math.tau
    left = Mn.spiral_path(0.06 * r, 0.4 * r, 1.6, n=14, hand=-1.0, a0=a0, c=(-0.5 * r, -0.12 * r))
    right = Mn.spiral_path(0.06 * r, 0.4 * r, 1.6, n=14, hand=1.0, a0=a0, c=(0.5 * r, -0.12 * r))
    Mn.stroke("Volute", left + right[::-1], 0.13 * r, surf, mat, lift=lift, walls=walls)
    Mn.stroke("VoluteAbacus", [(-0.82 * r, 0.52 * r), (0.82 * r, 0.52 * r)], 0.13 * r, surf, mat, lift=lift, walls=walls)
    for s in (1.0, -1.0):
        Mn.patch("VoluteEye", Mn.circle(0.09 * r, 8, (0.5 * r * s, -0.12 * r)), surf, mat, lift=lift, walls=walls)


def pauldron_mark(at, axis, r, sx):
    m_volute(Mn.roundel("PauldronDisc", at, axis, r, [(0.86, 0), (1.0, 1)], ["red", "gold"]), r * 0.74)


def thigh_mark(at, axis, r, sx):
    Mn.m_spiral(Mn.roundel("ThighDisc", at, axis, r, [(0.84, 0), (1.0, 1)], ["armor2", "gold"], h=0.012, seg=14), r * 0.8, "red", hand=sx)


def apron_mark(surf, r):
    """A column's head: the volute, the fluted shaft under it."""
    m_volute(lambda u, v: surf(u, v + 0.42 * r), r * 0.8, "red")
    for k in range(4):
        u = (k - 1.5) * 0.3 * r
        Mn.stroke("Flute", [(u, 0.12 * r), (u, -0.95 * r)], 0.12 * r, surf, "paint" if k % 2 else "red", lift=0.004, walls=False)


def pec_mark(surf, r, sx):
    Mn.m_spiral(surf, r, "gold", hand=sx, lift=0.004, walls=False)


# ---------------------------------------------------------------- the head: a hadrosaur, its long hollow crest

def head():
    bone("head")
    Mn.neck()
    st = [(0.09, 0.074, 1.855, 1.70), (0.01, 0.092, 1.88, 1.69), (-0.08, 0.088, 1.868, 1.698), (-0.17, 0.072, 1.836, 1.704),
          (-0.26, 0.058, 1.8, 1.71), (-0.33, 0.058, 1.77, 1.714, 3.4), (-0.385, 0.064, 1.752, 1.718, 3.6), (-0.415, 0.056, 1.744, 1.722, 3.6)]
    Mn.hull("Skull", st, "head", n=2.8)
    Mn.hull("Bill", [(-0.33, 0.06, 1.772, 1.713, 3.4), (-0.385, 0.068, 1.755, 1.716, 3.6), (-0.422, 0.059, 1.746, 1.72, 3.6)], "tube", seg=16,
            cap=0.6)
    jaw = [(0.04, 0.078, 1.702, 1.642), (-0.08, 0.078, 1.702, 1.636), (-0.2, 0.06, 1.708, 1.65), (-0.32, 0.052, 1.716, 1.674, 3.4),
           (-0.4, 0.055, 1.722, 1.692, 3.6)]
    Mn.hull("Jaw", jaw, "head2", n=2.8, seg=16)
    Mn.hull("JawBill", [(-0.335, 0.054, 1.718, 1.676, 3.4), (-0.405, 0.058, 1.723, 1.69, 3.6)], "tube", seg=16, cap=0.5)
    # the crest: a long hollow tube of gold, out of the snout's line, back over the head and the neck; lapis bands round it
    path = [(0, -0.2, 1.812), (0, -0.12, 1.86), (0, -0.03, 1.905), (0, 0.07, 1.95), (0, 0.17, 1.99), (0, 0.27, 2.024), (0, 0.36, 2.05),
            (0, 0.42, 2.063)]
    rad = [(0.02, 0.03), (0.036, 0.038), (0.044, 0.04), (0.045, 0.038), (0.043, 0.035), (0.039, 0.032), (0.034, 0.028), (0.025, 0.021)]
    Mn.sweep("Crest", path, rad, mat="tube", seg=12, tip=False)
    Mn.sweep("CrestEnd", [path[-1], (0, 0.44, 2.067)], [rad[-1], (0.01, 0.009)], mat="tube", seg=12, tip=False)
    for i in (3, 5):
        p0, p1 = Mn.Vector(path[i]), Mn.Vector(path[i + 1])
        Mn.sweep("CrestBand", [p0 + (p1 - p0) * 0.3, p0 + (p1 - p0) * 0.6], [(rad[i][0] + 0.004, rad[i][1] + 0.004)] * 2, mat="head",
                 seg=12, tip=False)
    # the struts holding it over the neck
    Mn.sweep("CrestStrut", [(0, 0.07, 1.85), (0, 0.13, 1.96)], [(0.012, 0.016), (0.01, 0.012)], mat="head2", seg=6, tip=False)
    for sx in (1.0, -1.0):
        Mn.lathe("Eye", (0.088 * sx, -0.115, 1.806), (sx, -0.35, 0.08),
                 [(0, 0.007, 1), (0.014, 0.004, 1), (0.016, 0.008, 0), (0.022, 0.008, 0), (0.026, -0.01, 0)], ["tube", "eye"], seg=12)
        Mn.loft("Brow", (0.084 * sx, -0.05, 1.848), (0.074 * sx, -0.18, 1.826), [(0, 0.02, 0.013, 3), (1, 0.013, 0.009, 3)], mat="head2",
                front=(sx, 0, 0.6), seg=8, cap=0.4)
        Mn.lathe("Nostril", (0.03 * sx, -0.36, 1.764), (0.4 * sx, -0.3, 1), [(0, 0.002), (0.008, 0.002), (0.01, -0.004)], ["joint"], seg=8)
        # the scroll on the cheek
        Mn.m_spiral(Mn.flat((0.0935 * sx, 0.0, 1.772), (sx, 0, 0)), 0.042, "tube", hand=sx, lift=0.004, name="CheekScroll")
    Mn.grow("head", 1.18, lift=0.052, tilt=-4, back=0.04)      # (high and back: clear of its fists in a guard)


def build():
    materials()
    Mn.style(pauldron=pauldron_mark, thigh=thigh_mark, apron=apron_mark, back=lambda surf, r: m_volute(surf, r * 0.8, "red"), pec=pec_mark,
             buckle=lambda surf, r: m_volute(surf, r * 0.85, "red"))
    mirror(Mn.legs)
    Mn.body()
    head()
    mirror(Mn.arms)
    Mn.rifle()
