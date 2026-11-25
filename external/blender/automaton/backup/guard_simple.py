"""The Minoan palace guard, from the 2D game's sheet (external/2d_game/art/
guard): the Minoan android's build (minoan.py) in the guard's palette -
terracotta and ochre ceramic over a dark red frame, a great fan crest painted
in red and blue, a glowing orange core, the patterned kilt - with a laser
rifle and no cape."""
import automaton as A
import kit
import minoan as Mn
from kit import mirror

GUN_HAND_R = Mn.GUN_HAND_R
GUN_HAND_L = Mn.GUN_HAND_L


def materials():
    Mn.materials()
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#e3a25c", shade=0.62, hi=0.06, tint=(0.95, 0.88, 0.92)),
        "armor2": kit.mat_toon("AUT_Armor2", "#c4763a", shade=0.64, tint=(0.95, 0.88, 0.92)),
        "joint": kit.mat_toon("GRD_Joint", "#6a2418", shade=0.62),
        "grey": kit.mat_toon("GRD_Blue", "#2c4f8c", shade=0.64),
        "red": kit.mat_toon("AUT_Red", "#c2281c", shade=0.68, hi=0.05),
        "red2": kit.mat_toon("AUT_Red2", "#1f3c78", shade=0.66),
        "glow": kit.mat_glow("AUT_Glow", "#ff9a2a", 1.7),
        "glow_y": kit.mat_glow("AUT_GlowY", "#ffd870", 1.8),
        "cloth": kit.mat_toon("GRD_Cloth", "#e9c99a", shade=0.66),
        "rifle": kit.mat_toon("MIN_RifleBody", "#7d9a3a", shade=0.64, hi=0.08),
        "rifle_d": kit.mat_toon("MIN_RifleDark", "#3a3020", shade=0.62, hi=0.1),
        "rifle_g": kit.mat_glow("MIN_RifleGlow", "#c8ff5a", 1.8),
    })


def build():
    materials()
    A.MARK = "spiral"
    A.PAULDRON_MARK[0] = Mn.pauldron_mark
    mirror(Mn.legs)
    A.body()
    Mn.kilt()
    Mn.head()
    mirror(A.arms)
    Mn.rifle()
