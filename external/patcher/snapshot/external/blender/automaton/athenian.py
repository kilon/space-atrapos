"""The Athenian android: the Minoan android's build (minoan.py) in Athens's
colours - white-cream marble plates over a dark frame, navy panels, gold
trim, a cyan glow - under its own head: a tan-grey horned theropod, two tall
pointed horns over the brows like an owl's ear tufts, round yellow eyes
ringed with gold, a toothed jaw, a gold nasal strip like a helmet's. Its
marks: a laurel wreath round an owl's face on the pauldrons, Athena's owl on
the apron. A laser rifle, no cape."""
import math

from mathutils import Vector

import kit
import minoan as Mn
from kit import bone, mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#f1ead8", shade=0.62, hi=0.06),
        "armor2": kit.mat_toon("AUT_Armor2", "#d2cab4", shade=0.64),
        "joint": kit.mat_toon("ATH_Joint", "#2a2533", shade=0.62),
        "grey": kit.mat_toon("ATH_Blue", "#3767bd", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#1d3a8c", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#12255a", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#3fe0ff", 1.6),
        "glow_y": kit.mat_glow("AUT_GlowY", "#c9f6ff", 1.7),
        "gold": kit.mat_toon("ATH_Gold", "#e8b93c", shade=0.66, hi=0.15),
        "claw": kit.mat_toon("ATH_ClawGold", "#d9a732", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("ATH_Cloth", "#f3eee1", shade=0.66),
        "hide": kit.mat_toon("ATH_Hide", "#b9a583", shade=0.64),
        "hide2": kit.mat_toon("ATH_Hide2", "#93815f", shade=0.66),
        "horn": kit.mat_toon("ATH_HornBone", "#e0cfa8", shade=0.64, hi=0.05),
        "tooth": kit.mat_toon("ATH_ToothBone", "#f6f1e2", shade=0.64),
        "eye": kit.mat_glow("ATH_EyeGlow", "#ffd21e", 1.8),
        "rifle": kit.mat_toon("MIN_RifleBody", "#ebe4d0", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#1c2f6e", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#e8b93c", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#4fe6ff", 1.8),
    })
    Mn.paints("grey", "gold")


# ---------------------------------------------------------------- its marks

LEAF = [(0, 0.2), (0.085, 0.05), (0.07, -0.1), (0, -0.2), (-0.07, -0.1), (-0.085, 0.05)]


def m_laurel(surf, r, mat="gold", lift=0.005):
    """A laurel wreath, open at the top, round an owl's face: two round eyes, a beak."""
    for s in (1.0, -1.0):
        for k in range(5):
            th = -90.0 + s * (17.0 + k * 31.0)
            c = (0.74 * r * math.cos(math.radians(th)), 0.74 * r * math.sin(math.radians(th)))
            Mn.patch("Laurel", Mn.moved(LEAF, c, r * 1.05, th + 90.0 * s - 90.0 - 24.0 * s), surf, mat, lift=lift, walls=False)
    for s in (1.0, -1.0):
        Mn.patch("OwlEye", Mn.circle(0.2 * r, 10, (0.23 * r * s, 0.1 * r)), surf, mat, lift=lift)
        Mn.patch("OwlPupil", Mn.circle(0.1 * r, 8, (0.23 * r * s, 0.1 * r)), surf, "red2", lift=lift + 0.003, walls=False)
    Mn.patch("OwlBeak", [(-0.08 * r, -0.08 * r), (0.08 * r, -0.08 * r), (0, -0.3 * r)], surf, mat, lift=lift)


def m_owl(surf, r):
    """Athena's owl: a navy body, round gold eyes, a beak, feathers on its breast."""
    Mn.patch("OwlBody", Mn.moved([(0, 0.8), (0.3, 0.74), (0.5, 0.42), (0.5, 0.0), (0.34, -0.5), (0, -0.74), (-0.34, -0.5), (-0.5, 0.0),
                                  (-0.5, 0.42), (-0.3, 0.74)], s=r), surf, "red", lift=0.004)
    for s in (1.0, -1.0):
        Mn.patch("OwlEye", Mn.circle(0.2 * r, 10, (0.22 * r * s, 0.38 * r)), surf, "gold", lift=0.007, walls=False)
        Mn.patch("OwlPupil", Mn.circle(0.09 * r, 8, (0.22 * r * s, 0.38 * r)), surf, "red2", lift=0.009, walls=False)
        Mn.stroke("OwlFoot", [(0.14 * r * s, -0.72 * r), (0.2 * r * s, -0.95 * r)], 0.07 * r, surf, "gold", lift=0.004, walls=False)
    Mn.patch("OwlBeak", [(-0.08 * r, 0.2 * r), (0.08 * r, 0.2 * r), (0, 0.0)], surf, "gold", lift=0.007, walls=False)
    for k in range(3):
        v = (-0.12 - 0.17 * k) * r
        Mn.stroke("OwlFeather", [(-0.2 * r, v), (0, v - 0.1 * r), (0.2 * r, v)], 0.05 * r, surf, "gold", lift=0.007, walls=False)


def pauldron_mark(at, axis, r, sx):
    m_laurel(Mn.roundel("PauldronDisc", at, axis, r, [(0.88, 0), (1.0, 1)], ["red", "gold"]), r * 0.84)


def thigh_mark(at, axis, r, sx):
    Mn.m_key(Mn.roundel("ThighDisc", at, axis, r, [(0.84, 0), (1.0, 1)], ["armor2", "red"], h=0.012, seg=14), r * 0.42, "paint", flip=sx,
             walls=True)


def back_mark(surf, r):
    m_laurel(surf, r * 0.9, "red")


def pec_mark(surf, r, sx):
    Mn.patch("PecMark", [(0, r), (0.6 * r, 0), (0, -r), (-0.6 * r, 0)], surf, "gold", lift=0.004, walls=False)


# ---------------------------------------------------------------- the head: a horned theropod, owl-eyed

def head():
    bone("head")
    Mn.neck()
    st = [(0.09, 0.076, 1.86, 1.70), (0.02, 0.096, 1.89, 1.69), (-0.07, 0.098, 1.89, 1.695), (-0.16, 0.088, 1.868, 1.70),
          (-0.24, 0.076, 1.846, 1.705), (-0.3, 0.064, 1.826, 1.71), (-0.338, 0.05, 1.802, 1.716)]
    Mn.hull("Skull", st, "hide", n=3.0)
    jaw = [(0.04, 0.082, 1.702, 1.636), (-0.07, 0.086, 1.702, 1.628), (-0.2, 0.072, 1.706, 1.64), (-0.29, 0.056, 1.71, 1.656),
           (-0.325, 0.044, 1.712, 1.668)]
    Mn.hull("Jaw", jaw, "hide2", n=3.0, seg=16)
    # the teeth: a row down each side of the upper jaw over the lower, smaller ones up from the lower, fangs across the front
    ys = [-0.075 - 0.031 * k for k in range(9)]
    Mn.jaw_teeth("Teeth", st, ys, [0.024, 0.03, 0.026, 0.032, 0.027, 0.03, 0.025, 0.027, 0.022], inset=0.9)
    Mn.jaw_teeth("TeethLow", jaw, [y - 0.015 for y in ys[1:8]], 0.017, inset=0.97, up=True, drop=0.004)
    Mn.teeth("TeethFront", [(x, -0.34 + abs(x) * 0.25, 1.722) for x in (-0.03, -0.01, 0.01, 0.03)], 0.026, "tooth")
    # a gold strip down the snout, like a helmet's nasal
    Mn.sweep("Nasal", [(0, s[0], s[2] + 0.001) for s in st[2:]], [(0.004, 0.016), (0.004, 0.015), (0.004, 0.013), (0.004, 0.011),
                                                                 (0.004, 0.009)], mat="gold", seg=6, tip=False)
    for sx in (1.0, -1.0):
        # the horn over the brow: tall and pointed, an owl's ear tuft; a gold ring round its root
        base = Vector((0.064 * sx, -0.03, 1.868))
        pts, rad = [], []
        for i in range(7):
            t = i / 6
            pts.append(base + Vector((sx * (0.03 * t + 0.04 * t * t), 0.02 * t + 0.05 * t * t, 0.225 * t)))
            rad.append(0.041 * (1 - t) ** 0.9 + 0.002)
        Mn.sweep("Horn", pts, rad, mat="horn", seg=10, hint=(0, -1, 0))
        Mn.sweep("HornRing", [pts[0] - Vector((0, 0, 0.012)), pts[0] + Vector((0.004 * sx, 0, 0.022))], [0.047, 0.044], mat="gold", seg=10,
                 tip=False, hint=(0, -1, 0))
        # a heavy brow, the eye under it: round and yellow, ringed with gold
        Mn.loft("Brow", (0.09 * sx, -0.045, 1.862), (0.08 * sx, -0.2, 1.842), [(0, 0.026, 0.018, 3), (1, 0.017, 0.012, 3)], mat="hide2",
                front=(sx, 0, 0.6), seg=8, cap=0.4)
        Mn.lathe("Eye", (0.095 * sx, -0.132, 1.806), (sx, -0.42, 0.05),
                 [(0, 0.008, 2), (0.008, 0.008, 2), (0.022, 0.005, 1), (0.024, 0.009, 0), (0.031, 0.009, 0), (0.035, -0.012, 0)],
                 ["gold", "eye", "joint"], seg=14)
        Mn.lathe("Nostril", (0.022 * sx, -0.312, 1.821), (0.3 * sx, -0.4, 1), [(0, 0.003), (0.007, 0.003), (0.009, -0.004)], ["joint"], seg=8)
        # the jaw's hinge: a round boss
        Mn.lathe("Hinge", (0.094 * sx, 0.02, 1.712), (sx, 0, 0), [(0, 0.014, 1), (0.014, 0.014, 1), (0.03, 0.01, 0), (0.034, -0.006, 0)],
                 ["hide2", "gold"], seg=12)
        # the cheek bone: a ridge from under the eye back to the hinge; knobs along the skull's edge
        Mn.sweep("Cheek", [(0.09 * sx, -0.2, 1.762), (0.099 * sx, -0.1, 1.756), (0.097 * sx, 0.0, 1.744)],
                 [(0.01, 0.006), (0.014, 0.007), (0.011, 0.006)], mat="hide2", seg=6, tip=False, hint=(sx, 0, 0))
        for k in range(4):
            y = 0.06 - 0.03 * k
            w, zt, _zb = Mn.at_y(st, y)
            kit.ball("Knob", (w * 0.72 * sx, y, zt - 0.012), 0.014, "hide2", seg=6)
    Mn.grow("head", 1.2, lift=0.062, tilt=-4, back=0.03)       # (high and back: clear of its fists in a guard)


def build():
    materials()
    Mn.style(pauldron=pauldron_mark, thigh=thigh_mark, apron=m_owl, back=back_mark, pec=pec_mark,
             buckle=lambda surf, r: Mn.m_key(surf, r * 0.62, "red", walls=True))
    mirror(Mn.legs)
    Mn.body()
    head()
    mirror(Mn.arms)
    Mn.rifle()
