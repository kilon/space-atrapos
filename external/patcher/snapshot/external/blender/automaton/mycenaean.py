"""The Mycenaean android: the Minoan android's build (minoan.py) in Mycenae's
colours - bronze and gold plates over a dark frame, dark red panels, an amber
glow - under its own head: a thick-domed pachycephalosaur made as a gold
death mask - the dome dark red, ringed with gold studs, spikes behind it,
knobs down the short snout, slit eyes under arched brows, small teeth. Its
mark: the 8-petal rosette, on the pauldrons (ringed with studs), the thighs,
the apron and the buckle. A laser rifle, no cape."""
import math

import kit
import minoan as Mn
from kit import ball, bone, mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#b67c38", shade=0.62, hi=0.08),
        "armor2": kit.mat_toon("AUT_Armor2", "#dba842", shade=0.64, hi=0.1),
        "joint": kit.mat_toon("MYC_Joint", "#2b1c13", shade=0.62),
        "grey": kit.mat_toon("MYC_Grey", "#5e3c1f", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#801c17", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#4e100d", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#ffa826", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#ffe08a", 1.8),
        "gold": kit.mat_toon("MYC_Gold", "#f2c544", shade=0.66, hi=0.15),
        "claw": kit.mat_toon("MYC_ClawGold", "#e3b23a", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("MYC_Cloth", "#6f1814", shade=0.66),
        "mask": kit.mat_toon("MYC_MaskGold", "#ecbc3c", shade=0.64, hi=0.15),
        "mask2": kit.mat_toon("MYC_JawGold", "#c9962e", shade=0.66, hi=0.12),
        "dome": kit.mat_toon("MYC_DomeRed", "#74160f", shade=0.66, hi=0.08),
        "tooth": kit.mat_toon("MYC_ToothBone", "#f5eeda", shade=0.64),
        "eye": kit.mat_glow("MYC_EyeGlow", "#ffb02a", 1.8),
        "rifle": kit.mat_toon("MIN_RifleBody", "#b67c38", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#3a2416", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#f2c544", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#ffc04a", 1.8),
    })
    Mn.paints("gold", "gold")


# ---------------------------------------------------------------- its mark

PETAL = [(0, 0.24), (0.15, 0.52), (0.13, 0.84), (0, 1.0), (-0.13, 0.84), (-0.15, 0.52)]


def m_rosette(surf, r, mat="gold", heart="gold", lift=0.005, walls=True):
    """The rosette: eight petals round a boss."""
    for k in range(8):
        Mn.patch("Rosette", Mn.moved(PETAL, s=r, ang=45.0 * k), surf, mat, lift=lift, walls=walls)
    Mn.patch("RosetteHeart", Mn.circle(0.19 * r, 8), surf, heart, lift=lift + 0.003, walls=walls)


def pauldron_mark(at, axis, r, sx):
    m_rosette(Mn.roundel("PauldronDisc", at, axis, r, [(0.8, 0), (1.0, 1)], ["red", "gold"]), r * 0.72)
    fr = kit.frame(axis, (0, 0, 1))
    for k in range(10):                               # (studs round its rim)
        a = math.tau * k / 10
        p = Mn.Vector(at) + fr @ Mn.Vector((math.cos(a) * r * 0.9, 0.02, math.sin(a) * r * 0.9))
        ball("PauldronStud", tuple(p), 0.011, "gold", seg=6)


def thigh_mark(at, axis, r, sx):
    m_rosette(Mn.roundel("ThighDisc", at, axis, r, [(0.84, 0), (1.0, 1)], ["red", "gold"], h=0.012, seg=14), r * 0.74, lift=0.004,
              walls=False)


def pec_mark(surf, r, sx):
    m_rosette(surf, r * 0.9, lift=0.004, walls=False)


# ---------------------------------------------------------------- the head: a domed pachycephalosaur, a gold death mask

def head():
    bone("head")
    Mn.neck()
    st = [(0.1, 0.072, 1.84, 1.70), (0.02, 0.098, 1.866, 1.69), (-0.07, 0.098, 1.862, 1.693), (-0.15, 0.084, 1.838, 1.70),
          (-0.22, 0.066, 1.808, 1.704), (-0.27, 0.05, 1.78, 1.708), (-0.305, 0.036, 1.758, 1.712)]
    Mn.hull("Skull", st, "mask", n=2.9)
    jaw = [(0.04, 0.082, 1.702, 1.64), (-0.07, 0.084, 1.702, 1.632), (-0.18, 0.064, 1.705, 1.646), (-0.26, 0.044, 1.709, 1.662),
           (-0.29, 0.034, 1.712, 1.672)]
    Mn.hull("Jaw", jaw, "mask2", n=2.9, seg=16)
    Mn.jaw_teeth("Teeth", st, [-0.12 - 0.026 * k for k in range(7)], 0.016, inset=0.9)
    # the dome: thick, dark red, a gold band and a ring of studs round its foot, spikes behind it
    ball("Dome", (0, 0.0, 1.862), 0.1, "dome", scale=(0.93, 1.16, 1.06), seg=16)
    Mn.lathe("DomeBand", (0, 0.0, 1.868), (0, 0, 1), [(0.0, -0.01), (0.098, -0.01), (0.1, 0.006), (0.09, 0.016), (0.0, 0.016)], ["mask"],
             seg=20, up=(0, 1, 0), oval=0.82)
    for k in range(14):
        a = math.tau * (k + 0.5) / 14
        ball("DomeStud", (0.086 * math.cos(a), 0.108 * math.sin(a), 1.882), 0.0135, "mask", seg=6)
    for k in range(5):
        a = math.radians(-50 + 25 * k)
        Mn.sweep("Spike", [(0.07 * math.sin(a), 0.096 * math.cos(a), 1.85), (0.105 * math.sin(a), 0.135 * math.cos(a), 1.868 - 0.02 * abs(k - 2))],
                 [0.016, 0], mat="mask2", seg=6, hint=(0, 0, 1))
    for k, (y, r) in enumerate(((-0.17, 0.014), (-0.215, 0.012), (-0.255, 0.011))):
        ball("SnoutKnob", (0, y, Mn.at_y(st, y)[1] + 0.002), r, "mask2", seg=6)
    for sx in (1.0, -1.0):
        # the mask's eye: a glowing slit between gold lids, under an arched brow
        Mn.eye((0.079 * sx, -0.158, 1.79), (0.75 * sx, -0.62, 0.12), 0.011, sock="mask2", lit="eye", oval=2.0)
        Mn.sweep("BrowArch", [(0.03 * sx, -0.212, 1.812), (0.062 * sx, -0.185, 1.828), (0.09 * sx, -0.135, 1.83), (0.099 * sx, -0.08, 1.816)],
                 [0.006, 0.008, 0.008, 0.005], mat="mask2", seg=6, tip=False, hint=(0, 0, 1))
        Mn.sweep("CheekLine", [(0.05 * sx, -0.24, 1.75), (0.082 * sx, -0.17, 1.744), (0.098 * sx, -0.08, 1.74)], [0.004, 0.006, 0.004],
                 mat="mask2", seg=6, tip=False, hint=(0, 0, 1))
        Mn.lathe("Nostril", (0.016 * sx, -0.288, 1.762), (0.4 * sx, -0.6, 1), [(0, 0.002), (0.005, 0.002), (0.007, -0.004)], ["joint"], seg=8)
        # the ear: a small rosette of gold
        Mn.lathe("Ear", (0.097 * sx, 0.025, 1.765), (sx, 0, 0), [(0, 0.016, 1), (0.012, 0.016, 1), (0.03, 0.01, 0), (0.034, -0.006, 0)],
                 ["mask2", "dome"], seg=12)
    Mn.grow("head", 1.22, lift=0.052, tilt=0, back=0.03)       # (high and back: clear of its fists in a guard)


def build():
    materials()
    Mn.style(pauldron=pauldron_mark, thigh=thigh_mark, apron=lambda surf, r: m_rosette(surf, r * 0.95),
             back=lambda surf, r: m_rosette(surf, r * 0.8), pec=pec_mark, buckle=lambda surf, r: m_rosette(surf, r * 0.8, "red", "red"))
    mirror(Mn.legs)
    Mn.body()
    head()
    mirror(Mn.arms)
    Mn.rifle()
