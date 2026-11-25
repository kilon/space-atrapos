"""The Minoan palace guard, from its sheet (external/images/
minoan_npc_guard_idle.png, art/guard): the Minoan android's build (minoan.py)
in the guard's palette - sand and ochre ceramic over a dark red-brown frame,
red and blue paint, a glowing orange core - its frill banded red with blue
spirals and red-and-blue petals, target roundels on the pauldrons, blue
spirals on the thighs, the lily on its apron - with a laser rifle and no cape."""
import kit
import minoan as Mn
from kit import mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#f4c47c", shade=0.62, hi=0.06, tint=(0.95, 0.88, 0.92)),
        "armor2": kit.mat_toon("AUT_Armor2", "#da964a", shade=0.64, tint=(0.95, 0.88, 0.92)),
        "joint": kit.mat_toon("GRD_Joint", "#3d1a17", shade=0.62),
        "grey": kit.mat_toon("GRD_Blue", "#24508c", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#c8281a", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#7c1a14", shade=0.66),
        "glow": kit.mat_glow("AUT_Glow", "#ff8a1e", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#ffd860", 1.8),
        "gold": kit.mat_toon("GRD_Gold", "#f0b030", shade=0.66, hi=0.15),
        "horn": kit.mat_toon("GRD_HornBone", "#e6c07c", shade=0.64, hi=0.05),
        "claw": kit.mat_toon("GRD_ClawGold", "#e8a628", shade=0.62, hi=0.1),
        "cloth": kit.mat_toon("GRD_Cloth", "#edd2a0", shade=0.66),
        "rifle": kit.mat_toon("MIN_RifleBody", "#7d9a3a", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#3a3020", shade=0.62, hi=0.1),
        "rifle_t": kit.mat_toon("MIN_RifleGold", "#d8b23a", shade=0.66, hi=0.15),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#c8ff5a", 1.8),
    })
    Mn.paints("grey", "red")


def pauldron_mark(at, axis, r, sx):
    """A target: rings of red and sand."""
    Mn.roundel("PauldronDisc", at, axis, r, [(0.2, 0), (0.42, 1), (0.64, 0), (0.84, 1), (1.0, 0)], ["red", "armor"], seg=20)


def build():
    materials()
    Mn.style(pauldron=pauldron_mark,
             frill=dict(band="red", line="paint", rim="armor2", petal="paint", heart="red", spiral="paint", stud="horn", rib="armor2"))
    mirror(Mn.legs)
    Mn.body()
    Mn.head()
    mirror(Mn.arms)
    Mn.rifle()
