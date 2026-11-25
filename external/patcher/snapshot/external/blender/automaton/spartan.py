"""The Spartan android: the Minoan android's build (minoan.py) in Sparta's
colours - crimson plates and cream ones over a dark iron frame, gold trim, an
amber glow - under its own head: a bronze tyrannosaur, heavy-jawed and
toothed, orange eyes under brow bosses, cheek guards like a helmet's, and a
tall red crest running front to back like a Spartan helmet's plume. Its mark:
the gold lambda, on the pauldrons, the apron and the buckle. A laser rifle,
no cape."""
import kit
import minoan as Mn
from kit import bone, mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#a8221f", shade=0.62, hi=0.06),
        "armor2": kit.mat_toon("AUT_Armor2", "#e3d7b9", shade=0.64),
        "joint": kit.mat_toon("SPA_Joint", "#232328", shade=0.62),
        "grey": kit.mat_toon("SPA_Grey", "#4b4b54", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#dccfa9", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#33333a", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#ff9a1e", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#ffd66a", 1.8),
        "gold": kit.mat_toon("SPA_Gold", "#e6b23a", shade=0.66, hi=0.15),
        "claw": kit.mat_toon("SPA_ClawBronze", "#9a6a2e", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("SPA_Cloth", "#7e1716", shade=0.66),
        "head": kit.mat_toon("SPA_HeadBronze", "#93602c", shade=0.64, hi=0.1),
        "head2": kit.mat_toon("SPA_JawBronze", "#6f4620", shade=0.66, hi=0.1),
        "crest": kit.mat_toon("SPA_Crest", "#c41f1c", shade=0.64),
        "tooth": kit.mat_toon("SPA_ToothBone", "#f3ecd8", shade=0.64),
        "eye": kit.mat_glow("SPA_EyeGlow", "#ff8a1a", 1.8),
        "rifle": kit.mat_toon("MIN_RifleBody", "#8e1c1a", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#26262b", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#e6b23a", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#ffb03a", 1.8),
    })
    Mn.paints("gold", "gold")


# ---------------------------------------------------------------- its mark

def m_lambda(surf, r, mat="gold", lift=0.005, walls=True):
    """The lambda of Lakedaimon: an upside-down V."""
    Mn.stroke("Lambda", [(-0.56 * r, -0.62 * r), (0, 0.72 * r), (0.56 * r, -0.62 * r)], 0.24 * r, surf, mat, lift=lift, walls=walls)


def pauldron_mark(at, axis, r, sx):
    """A hoplite's shield: crimson, rimmed with gold, the lambda on it."""
    m_lambda(Mn.roundel("PauldronDisc", at, axis, r, [(0.82, 0), (1.0, 1)], ["armor", "gold"]), r * 0.74)


def thigh_mark(at, axis, r, sx):
    Mn.roundel("ThighDisc", at, axis, r, [(0.24, 1), (0.6, 0), (0.78, 1), (1.0, 0)], ["armor2", "gold"], h=0.012, seg=14)


def pec_mark(surf, r, sx):
    m_lambda(surf, r, lift=0.004, walls=False)


# ---------------------------------------------------------------- the head: a tyrannosaur, crested

def head():
    bone("head")
    Mn.neck()
    st = [(0.1, 0.08, 1.87, 1.70), (0.02, 0.102, 1.9, 1.69), (-0.08, 0.104, 1.9, 1.695), (-0.17, 0.094, 1.885, 1.70),
          (-0.26, 0.085, 1.868, 1.705), (-0.33, 0.077, 1.852, 1.71), (-0.375, 0.064, 1.832, 1.716)]
    Mn.hull("Skull", st, "head", n=3.2)
    jaw = [(0.05, 0.088, 1.702, 1.626), (-0.08, 0.092, 1.702, 1.618), (-0.22, 0.082, 1.706, 1.63), (-0.32, 0.069, 1.71, 1.648),
           (-0.362, 0.056, 1.712, 1.662)]
    Mn.hull("Jaw", jaw, "head2", n=3.2, seg=16)
    ys = [-0.07 - 0.031 * k for k in range(10)]
    Mn.jaw_teeth("Teeth", st, ys, [0.028, 0.036, 0.03, 0.038, 0.032, 0.038, 0.03, 0.034, 0.028, 0.03], inset=0.9)
    Mn.jaw_teeth("TeethLow", jaw, [y - 0.015 for y in ys[1:9]], 0.02, inset=0.97, up=True, drop=0.004)
    Mn.teeth("TeethFront", [(x, -0.378 + abs(x) * 0.25, 1.724) for x in (-0.042, -0.014, 0.014, 0.042)], 0.032, "tooth")
    # the crest: a gold holder along the skull and down the neck, the red plume standing in it
    top = [(0, s[0], s[2] + 0.002) for s in st[::-1][1:6]]
    Mn.sweep("CrestHolder", top + [(0, 0.125, 1.84), (0, 0.15, 1.74)], [(0.012, 0.022)] * 7, mat="gold", seg=6, tip=False)
    base = [(0.255, 1.872), (0.17, 1.888), (0.08, 1.902), (-0.02, 1.902), (-0.1, 1.874), (-0.132, 1.82), (-0.15, 1.73)]
    arc = [(-0.205, 1.7), (-0.225, 1.82), (-0.2, 1.93), (-0.135, 2.015), (-0.03, 2.062), (0.075, 2.07), (0.17, 2.045), (0.24, 1.995),
           (0.285, 1.93)]
    plume = []
    for i in range(len(arc) - 1):                     # (the plume's top: bristles, a little ragged)
        for k in range(3):
            t = k / 3
            u = arc[i][0] + (arc[i + 1][0] - arc[i][0]) * t
            v = arc[i][1] + (arc[i + 1][1] - arc[i][1]) * t
            out = 1.0 + (0.028 if (i * 3 + k) % 2 else 0.0)
            plume.append((u * out, 1.9 + (v - 1.9) * out))
    plume.append(arc[-1])
    Mn.slab("Crest", base + plume, (0, 0, 0), (1, 0, 0), (0, -1, 0), thick=0.056, mat="crest", bevel=0.018)
    for sx in (1.0, -1.0):
        # a boss over the eye, the eye under it; the nostril
        kit.ball("BrowBoss", (0.082 * sx, -0.105, 1.89), 0.034, "head", scale=(0.9, 1.5, 0.6), seg=10)
        Mn.eye((0.1 * sx, -0.118, 1.835), (sx, -0.35, 0.05), 0.012, sock="head2", lit="eye", oval=1.3)
        Mn.lathe("Nostril", (0.03 * sx, -0.35, 1.848), (0.5 * sx, -0.3, 1), [(0, 0.003), (0.009, 0.003), (0.012, -0.005)], ["joint"], seg=8)
        # the cheek guard: a helmet's, rimmed with gold
        ck = (0.103 * sx, -0.03, 1.765)
        pts = [(-0.062, 0.05), (0.05, 0.05), (0.075, 0.0), (0.045, -0.06), (-0.03, -0.07), (-0.062, -0.02)]
        Mn.slab("CheekRim", [(x * 1.12, y * 1.12) for (x, y) in pts], ck, (sx, 0, 0), (0, -1, 0), thick=0.014, mat="gold", bevel=0.003)
        Mn.slab("CheekGuard", pts, ck, (sx, 0, 0), (0, -1, 0), thick=0.022, mat="head2", bevel=0.005)
    Mn.grow("head", 1.14, lift=0.062, tilt=-8, back=0.03)      # (high and back: clear of its fists in a guard)


def build():
    materials()
    Mn.style(pauldron=pauldron_mark, thigh=thigh_mark, apron=lambda surf, r: m_lambda(surf, r * 0.95), back=lambda surf, r: m_lambda(surf, r * 0.8),
             pec=pec_mark, buckle=lambda surf, r: m_lambda(surf, r * 0.75, "armor"))
    mirror(Mn.legs)
    Mn.body()
    head()
    mirror(Mn.arms)
    Mn.rifle()
