"""A skeleton warrior (the dungeons' and caves' dead): bare bones - a skull
with a jaw and two red embers for eyes, a spine of vertebrae, a ribcage, the
pelvis, the long bones of the limbs, knuckled hands and feet - in the
remains of a hoplite's panoply: a bronze helmet with its horsehair crest, a
round bronze shield on the left arm, a short sword, a torn red kilt.
Photoreal (the kit's PBR): weathered bone, tarnished bronze."""
import math

from mathutils import Vector

import kit
from kit import ball, bone, box, loft, mirror, plate, rot, tube

GUN_HAND_R = (0.0, -0.075, -0.03)
GUN_HAND_L = (0.0, 0.26, -0.03)
KNEE_Z = kit.HIP_Z - kit.THIGH
AZ = kit.ANKLE_Z


def materials():
    kit.M.update({
        "armor": kit.mat_toon("SKL_Bone", "#d9ccb0", shade=0.6),
        "armor2": kit.mat_toon("SKL_BoneDark", "#9c8d72", shade=0.6),
        "joint": kit.mat_toon("SKL_Joint", "#6b5d4a", shade=0.6),
        "bronze": kit.mat_toon("SKL_Bronze", "#8a6a34", shade=0.6),
        "red": kit.mat_toon("SKL_ClothRed", "#6e1c16", shade=0.6),
        "crest": kit.mat_toon("SKL_ClothCrest", "#8c1f18", shade=0.6),
        "glow": kit.mat_glow("SKL_Eye", "#ff3a14", 2.4),
        "iron": kit.mat_toon("SKL_Gun", "#5a5c60", shade=0.6),
        "ink": kit.mat_outline(),
    })


def legs(sx, sf):
    hx = kit.HIP_X * sx
    bone("thigh" + sf)
    ball("HipBall", (hx, 0, kit.HIP_Z), 0.05, "armor")
    tube("Femur", (hx, 0, kit.HIP_Z - 0.02), (hx, 0, KNEE_Z + 0.03), 0.026, 0.024, mat="armor", seg=10)
    bone("shin" + sf)
    ball("Knee", (hx, -0.01, KNEE_Z), 0.042, "armor")
    tube("Tibia", (hx - 0.012 * sx, 0, KNEE_Z - 0.02), (hx - 0.01 * sx, 0, AZ + 0.02), 0.022, 0.018, mat="armor", seg=10)
    tube("Fibula", (hx + 0.022 * sx, 0.01, KNEE_Z - 0.04), (hx + 0.02 * sx, 0.01, AZ + 0.04), 0.011, mat="armor2", seg=8)
    bone("foot" + sf)
    ball("Ankle", (hx, 0, AZ), 0.03, "armor")
    box("Heel", (0.05, 0.07, 0.05), (hx, 0.02, 0.04), mat="armor", bevel=0.012)
    for k in range(4):
        x = hx + (k - 1.5) * 0.018 * sx
        tube("Toe", (x, -0.02, 0.04), (x * 1.0, -0.17, 0.012), 0.009, 0.006, mat="armor", seg=6)
    # bronze greaves, what's left of them
    bone("shin" + sf)
    loft("Greave", (hx, -0.035, KNEE_Z - 0.06), (hx, -0.03, AZ + 0.12), [(0, 0.045, 0.03, 3), (0.4, 0.05, 0.034, 3), (1, 0.038, 0.026, 3)],
         mat="bronze", cap=0.4)


def body():
    bone("pelvis")
    loft("Pelvis", (0, 0.01, 0.92), (0, 0.01, 1.06), [(0, 0.06, 0.05, 2.4), (0.5, 0.13, 0.07, 2.4), (1, 0.1, 0.05, 2.4)], mat="armor", cap=0.5)
    # the torn kilt: strips hanging from a bronze belt
    box("Belt", (0.27, 0.19, 0.045), (0, 0.004, 1.07), mat="bronze", bevel=0.012)
    for k in range(9):
        a = math.pi * (0.15 + 0.7 * k / 8.0)
        x, y = math.cos(a) * 0.14, -math.sin(a) * 0.1
        ln = 0.18 + 0.08 * ((k * 7) % 3) / 2.0
        box("Strip", (0.05, 0.012, ln), (x, y - 0.01, 1.05 - ln / 2), mat="red", r=rot(0, 0, math.degrees(a) - 90), bevel=0.003)
    bone("spine")
    for k in range(6):
        z = 1.08 + k * 0.035
        ball("Vertebra", (0, 0.04, z), 0.022, "armor2", scale=(1.2, 1.0, 0.7))
    bone("chest")
    tube("Spine", (0, 0.05, 1.28), (0, 0.04, 1.6), 0.02, mat="armor2", seg=8)
    tube("Sternum", (0, -0.1, 1.33), (0, -0.11, 1.52), 0.018, 0.014, mat="armor", seg=8)
    for k in range(7):
        z = 1.33 + k * 0.035
        w = 0.13 - abs(k - 3) * 0.008
        for sx in (1.0, -1.0):
            pts = []
            for j in range(7):
                a = math.pi * j / 6.0
                pts.append(Vector((sx * w * math.sin(a), 0.05 - 0.15 * (1 - math.cos(a)) * 0.5 - 0.0, z - 0.03 * math.sin(a))))
            for j in range(len(pts) - 1):
                tube("Rib", tuple(pts[j]), tuple(pts[j + 1]), 0.009, mat="armor", seg=6, outline=0.0)
    for sx in (1.0, -1.0):
        tube("Clavicle", (0.02 * sx, -0.08, 1.56), (0.2 * sx, -0.02, 1.53), 0.013, mat="armor", seg=6)
        ball("Scapula", (0.1 * sx, 0.08, 1.46), 0.05, "armor2", scale=(1.0, 0.3, 1.2))


def head():
    bone("head")
    tube("Neck", (0, 0.03, 1.57), (0, 0.02, 1.67), 0.018, mat="armor2", seg=8)
    loft("Skull", (0, 0.02, 1.68), (0, 0.025, 1.86), [(0, 0.06, 0.075, 2.6), (0.5, 0.075, 0.09, 2.5), (1, 0.04, 0.05, 2.2)], mat="armor", cap=0.5)
    box("Jaw", (0.09, 0.08, 0.04), (0, -0.04, 1.655), mat="armor", r=rot(8), bevel=0.014, taper=(0.8, 0.9))
    box("Teeth", (0.07, 0.02, 0.03), (0, -0.085, 1.69), mat="armor2", bevel=0.004)
    for sx in (1.0, -1.0):
        ball("Socket", (0.03 * sx, -0.072, 1.755), 0.022, "joint", seg=10)
        ball("Ember", (0.03 * sx, -0.08, 1.755), 0.011, "glow", seg=8, outline=0)
    ball("Nose", (0, -0.085, 1.72), 0.01, "joint", seg=6)
    # the bronze helmet, its cheek guards, the crest
    loft("Helmet", (0, 0.025, 1.74), (0, 0.03, 1.9), [(0, 0.085, 0.1, 2.4), (0.5, 0.085, 0.1, 2.4), (1, 0.03, 0.04, 2.2)], mat="bronze", cap=0.5)
    for sx in (1.0, -1.0):
        box("Cheek", (0.02, 0.09, 0.1), (0.075 * sx, -0.03, 1.72), mat="bronze", r=rot(0, 0, 12 * sx), bevel=0.008)
    box("CrestHolder", (0.02, 0.2, 0.04), (0, 0.03, 1.92), mat="bronze", bevel=0.006)
    # the horsehair: an arc from brow to nape
    plate("Crest", [(-0.17, 0.0), (0.17, 0.0)] + [(0.17 * math.cos(math.pi * k / 8.0), 0.02 + 0.13 * math.sin(math.pi * k / 8.0)) for k in range(9)],
          (0, 0.03, 1.93), (1, 0, 0), up=(0, 0, 1), thick=0.022, mat="crest", outline=0.0)


def arms(sx, sf):
    S = kit.SHOULDER
    x = S.x * sx
    ez = S.z - kit.UPPER
    wz = ez - kit.FORE
    bone("upper" + sf)
    ball("Shoulder", (x, 0, S.z), 0.04, "armor")
    tube("Humerus", (x, 0, S.z - 0.02), (x, 0, ez + 0.02), 0.022, 0.019, mat="armor", seg=10)
    bone("pauldron" + sf)
    loft("Pauldron", (x + 0.02 * sx, 0, S.z + 0.05), (x + 0.04 * sx, 0, S.z - 0.08), [(0, 0.05, 0.065, 3), (1, 0.05, 0.065, 3)], mat="bronze", cap=0.5)
    bone("fore" + sf)
    ball("Elbow", (x, 0, ez), 0.032, "armor")
    tube("Radius", (x + 0.01 * sx, -0.008, ez - 0.02), (x + 0.01 * sx, -0.008, wz + 0.02), 0.014, mat="armor", seg=8)
    tube("Ulna", (x - 0.01 * sx, 0.008, ez - 0.02), (x - 0.01 * sx, 0.008, wz + 0.02), 0.013, mat="armor2", seg=8)
    if sx > 0:   # the round bronze shield on the left forearm
        tube("Aspis", (x + 0.07, 0, ez - 0.14), (x + 0.1, 0, ez - 0.14), 0.36, 0.33, mat="bronze", seg=28)
        tube("AspisBoss", (x + 0.1, 0, ez - 0.14), (x + 0.12, 0, ez - 0.14), 0.09, 0.05, mat="bronze", seg=16)
        tube("AspisRim", (x + 0.085, 0, ez - 0.14), (x + 0.105, 0, ez - 0.14), 0.37, mat="iron", seg=28)
    bone("hand" + sf)
    box("Carpals", (0.035, 0.05, 0.04), (x, -0.004, wz - 0.02), mat="armor", bevel=0.008)
    bone("fingers" + sf)
    for k in range(4):
        tube("Finger", (x, -0.03 + k * 0.016, wz - 0.04), (x, -0.03 + k * 0.016, wz - 0.1), 0.006, mat="armor", seg=6)


def sword():
    """The short sword (xiphos) on the gun bone: a leaf blade forward."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    box("Grip", (0.03, 0.12, 0.03), at(-0.02, 0.0), mat="joint", bevel=0.006)
    box("Guard", (0.03, 0.03, 0.12), at(0.05, 0.0), mat="bronze", bevel=0.006)
    plate("Blade", [(-0.022, 0.0), (0.03, 0.15), (0.032, 0.32), (0.0, 0.5), (-0.032, 0.32), (-0.03, 0.15)], at(0.06, 0.0), (0, 0, 1),
          up=(0, -1, 0), thick=0.008, mat="iron", outline=0.0)


def build():
    materials()
    mirror(legs)
    body()
    head()
    mirror(arms)
    sword()
