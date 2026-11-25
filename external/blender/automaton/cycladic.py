"""The Cycladic android: the Minoan android's build (minoan.py) in the
Cyclades' colours - pure white marble, its panels barely a shade off it, thin
lines of blue and terracotta, a teal glow - under its own head: smooth, pale
and abstract, a Cycladic idol crossed with an ichthyosaur - a long smooth
snout with rows of small teeth, a nose ridge like an idol's, tiny teal eyes,
thin painted bands, and one flat dark fin standing on top of the skull. Its
mark: a simple spiral. A laser rifle, no cape."""
import kit
import minoan as Mn
from kit import bone, mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#f7f6f2", shade=0.62, hi=0.06),
        "armor2": kit.mat_toon("AUT_Armor2", "#e7e6e1", shade=0.64),
        "joint": kit.mat_toon("CYC_Joint", "#2f2d38", shade=0.62),
        "grey": kit.mat_toon("CYC_LineBlue", "#3f86c9", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#dedfdb", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#c6c9c8", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#2fd6c4", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#b8fff4", 1.8),
        "gold": kit.mat_toon("CYC_LineTerra", "#c8683f", shade=0.66),
        "claw": kit.mat_toon("CYC_ClawBone", "#dcdad2", shade=0.62),
        "cloth": kit.mat_toon("CYC_Cloth", "#f8f7f3", shade=0.66),
        "marble": kit.mat_toon("CYC_MarbleSkin", "#f4f2eb", shade=0.64),
        "marble2": kit.mat_toon("CYC_MarbleSkin2", "#e6e3da", shade=0.66),
        "fin": kit.mat_toon("CYC_FinHide", "#262b34", shade=0.64),
        "tooth": kit.mat_toon("CYC_ToothBone", "#fbf9f2", shade=0.64),
        "eye": kit.mat_glow("CYC_EyeGlow", "#30e0cc", 1.9),
        "rifle": kit.mat_toon("MIN_RifleBody", "#f2f1ec", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#3a3f4c", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#3f86c9", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#4fe8d6", 1.8),
    })
    Mn.paints("grey", "gold")


# ---------------------------------------------------------------- its mark: a spiral, thinly drawn

def m_thin(surf, r, mat="paint", hand=1.0, lift=0.004, walls=True):
    Mn.stroke("Spiral", Mn.spiral_path(r * 0.06, r * 0.92, 2.25, n=22, hand=hand, a0=3.14159), 0.085 * r, surf, mat, lift=lift, walls=walls)


def pauldron_mark(at, axis, r, sx):
    m_thin(Mn.roundel("PauldronDisc", at, axis, r, [(0.9, 0), (1.0, 1)], ["armor", "gold"]), r * 0.8, hand=sx)


def thigh_mark(at, axis, r, sx):
    m_thin(Mn.roundel("ThighDisc", at, axis, r, [(0.9, 0), (1.0, 1)], ["armor", "paint"], h=0.012, seg=14), r * 0.78, "gold", hand=sx)


def apron_mark(surf, r):
    m_thin(surf, r * 0.75)
    for v, mat in ((0.98, "gold"), (-0.98, "gold"), (-1.12, "paint")):
        Mn.stroke("ApronThin", [(-0.8 * r, v * r), (0.8 * r, v * r)], 0.05 * r, surf, mat, lift=0.004, walls=False)


def pec_mark(surf, r, sx):
    Mn.stroke("PecMark", [(-r, 0), (r, 0)], 0.22 * r, surf, "paint", lift=0.004, walls=False)


# ---------------------------------------------------------------- the head: an idol's, an ichthyosaur's

def head():
    bone("head")
    Mn.neck()
    st = [(0.1, 0.07, 1.86, 1.70), (0.02, 0.086, 1.888, 1.69), (-0.08, 0.08, 1.878, 1.698), (-0.2, 0.058, 1.846, 1.71),
          (-0.32, 0.04, 1.812, 1.722), (-0.42, 0.027, 1.786, 1.734), (-0.5, 0.017, 1.768, 1.744)]
    Mn.hull("Skull", st, "marble", n=2.4, cap=0.8)
    jaw = [(0.04, 0.072, 1.702, 1.648), (-0.08, 0.07, 1.702, 1.645), (-0.2, 0.05, 1.713, 1.668), (-0.32, 0.034, 1.724, 1.69),
           (-0.42, 0.022, 1.735, 1.71), (-0.49, 0.014, 1.745, 1.728)]
    Mn.hull("Jaw", jaw, "marble2", n=2.4, seg=16, cap=0.8)
    ys = [-0.15 - 0.026 * k for k in range(13)]
    Mn.jaw_teeth("Teeth", st, ys, [0.013 - 0.0004 * k for k in range(13)], inset=0.9, drop=0.004)
    Mn.jaw_teeth("TeethLow", jaw, [y - 0.013 for y in ys[:12]], 0.009, inset=0.98, up=True, drop=0.003)
    # the idol's nose: a ridge down the snout
    Mn.sweep("NoseRidge", [(0, s[0], s[2]) for s in st[2:]], [(0.007, 0.011), (0.007, 0.01), (0.006, 0.008), (0.005, 0.006), (0.004, 0.004)],
             mat="marble", seg=8, tip=False)
    # thin painted bands round the snout
    for y, mat in ((-0.235, "paint"), (-0.252, "gold"), (-0.38, "paint")):
        a = Mn.at_y(st, y)
        b = Mn.at_y(st, y - 0.008)
        Mn.hull("SnoutBand", [(y, a[0] + 0.002, a[1] + 0.002, a[2] + 0.001), (y - 0.008, b[0] + 0.002, b[1] + 0.002, b[2] + 0.001)], mat, n=2.4,
                seg=16, cap=0.0)
    # the fin: flat and dark, standing on the skull, swept back
    Mn.slab("Fin", [(0.075, 1.868), (0.045, 1.93), (-0.005, 1.99), (-0.065, 2.04), (-0.125, 2.062), (-0.108, 2.0), (-0.098, 1.93),
                    (-0.095, 1.86)], (0, 0, 0), (1, 0, 0), (0, -1, 0), thick=0.016, mat="fin", bevel=0.006)
    Mn.slab("FinFoot", [(0.09, 1.862), (0.08, 1.884), (-0.1, 1.884), (-0.108, 1.855)], (0, 0, 0), (1, 0, 0), (0, -1, 0), thick=0.03,
            mat="marble2", bevel=0.008)
    for sx in (1.0, -1.0):
        Mn.lathe("Eye", (0.0765 * sx, -0.105, 1.802), (sx, -0.22, 0.1), [(0, 0.005, 1), (0.008, 0.003, 1), (0.01, 0.004, 0), (0.014, 0.004, 0),
                                                                        (0.016, -0.006, 0)], ["joint", "eye"], seg=10)
        Mn.stroke("CheekSpiral", Mn.spiral_path(0.004, 0.032, 2.0, n=18, hand=sx, c=(0.0, 0.0)), 0.0045,
                  Mn.flat((0.084 * sx, 0.01, 1.775), (sx, 0, 0)), "paint", lift=0.0035)
    Mn.grow("head", 1.2, lift=0.052, tilt=-2, back=0.03)       # (high and back: clear of its fists in a guard)


def build():
    materials()
    Mn.style(pauldron=pauldron_mark, thigh=thigh_mark, apron=apron_mark, back=lambda surf, r: m_thin(surf, r * 0.7, "gold"), pec=pec_mark,
             buckle=lambda surf, r: m_thin(surf, r * 0.8, "armor"))
    mirror(Mn.legs)
    Mn.body()
    head()
    mirror(Mn.arms)
    Mn.rifle()
