"""A demon of the deep places: hulking and stooped, its hide dark and cracked
with the fire inside it (glowing seams), great ram's horns curling from its
brow, eyes of fire, a fanged maw, clawed hands and feet, bat's wings folded
on its back, a barbed tail (its own bone, swinging with its stride), plates
of black horn on its shoulders and shins. Photoreal (the kit's PBR)."""
import math

from mathutils import Vector

import kit
import pirate
from kit import ball, bone, box, loft, mirror, plate, rot, tube

GUN_HAND_R = (0.0, -0.075, -0.03)
GUN_HAND_L = (0.0, 0.26, -0.03)
KNEE_Z = kit.HIP_Z - kit.THIGH
AZ = kit.ANKLE_Z

# The tail: from the pelvis, down and back (the pirate's coat-tail solver swings it).
EXTRA_BONES = {
    "coat.B": ("pelvis", (0.0, 0.12, 1.0), (0, 0.5, -0.86), (0, -1, 0), 0.8),
}
tail_solver = pirate.tail_solver


def materials():
    kit.M.update({
        "armor": kit.mat_toon("DEM_Hide", "#3a1612", shade=0.6),
        "armor2": kit.mat_toon("DEM_HideDark", "#1f0c0a", shade=0.6),
        "joint": kit.mat_toon("DEM_Joint", "#2a100d", shade=0.6),
        "horn": kit.mat_toon("DEM_Horn", "#211a16", shade=0.6, hi=0.1),
        "claw": kit.mat_toon("DEM_Claw", "#141110", shade=0.6, hi=0.1),
        "wing": kit.mat_toon("DEM_Wing", "#2c0f0d", shade=0.6),
        "glow": kit.mat_glow("DEM_Glow", "#ff5a14", 2.2),
        "eye": kit.mat_glow("DEM_Eye", "#ffb020", 2.8),
        "ink": kit.mat_outline(),
    })


def _cracks(name, a, b, n, seed):
    """Glowing seams down a limb, from a to b (the fire inside)."""
    a, b = Vector(a), Vector(b)
    for k in range(n):
        t0 = k / n
        t1 = (k + 0.7) / n
        off = Vector((0.012 * math.sin(seed + k * 2.1), -0.012 * math.cos(seed + k * 1.7), 0))
        tube(name, tuple(a.lerp(b, t0) + off), tuple(a.lerp(b, t1) - off), 0.006, mat="glow", seg=5, outline=0.0)


def legs(sx, sf):
    hx = kit.HIP_X * 1.2 * sx
    bone("thigh" + sf)
    ball("Hip", (hx, 0, kit.HIP_Z), 0.1, "armor")
    loft("Thigh", (hx, 0.0, kit.HIP_Z - 0.03), (hx, 0.0, KNEE_Z + 0.03), [(0, 0.1, 0.11, 2.6), (0.5, 0.09, 0.1, 2.6), (1, 0.065, 0.07, 2.6)], mat="armor")
    _cracks("ThighCrack", (hx + 0.06 * sx, -0.07, kit.HIP_Z - 0.06), (hx + 0.04 * sx, -0.06, KNEE_Z + 0.08), 3, sx)
    bone("shin" + sf)
    ball("Knee", (hx, -0.02, KNEE_Z), 0.07, "armor2")
    loft("Shin", (hx, 0.01, KNEE_Z - 0.03), (hx, 0.03, AZ + 0.03), [(0, 0.06, 0.07, 2.6), (1, 0.045, 0.05, 2.6)], mat="armor")
    box("ShinPlate", (0.08, 0.04, 0.26), (hx, -0.06, KNEE_Z - 0.17), mat="horn", r=rot(6), bevel=0.016, taper=(0.8, 0.9))
    bone("foot" + sf)
    ball("Ankle", (hx, 0.02, AZ), 0.05, "armor")
    box("Foot", (0.11, 0.16, 0.07), (hx, -0.05, 0.04), mat="armor", taper=(0.9, 0.8), bevel=0.02)
    for k in range(3):
        x = hx + (k - 1) * 0.035 * sx
        tube("Talon", (x, -0.12, 0.04), (x, -0.2, 0.0), 0.016, 0.002, mat="claw", seg=6)


def body():
    bone("pelvis")
    loft("Hips", (0, 0.02, 0.9), (0, 0.02, 1.1), [(0, 0.13, 0.1, 2.6), (0.6, 0.17, 0.12, 2.6), (1, 0.15, 0.11, 2.6)], mat="armor")
    box("Loin", (0.2, 0.04, 0.22), (0, -0.12, 0.92), mat="horn", bevel=0.02, taper=((0.6, 1.0), (1.0, 1.0)))
    bone("spine")
    loft("Belly", (0, 0.0, 1.08), (0, 0.01, 1.3), [(0, 0.15, 0.12, 2.6), (1, 0.18, 0.13, 2.6)], mat="armor2")
    bone("chest")
    # a great barrel of a chest, hunched forward
    loft("Chest", (0, -0.01, 1.26), (0, 0.03, 1.62), [(0, 0.19, 0.14, 2.6), (0.5, 0.25, 0.17, 2.6), (1, 0.2, 0.14, 2.6)], mat="armor", cap=0.5)
    _cracks("ChestCrack", (-0.08, -0.15, 1.55), (0.06, -0.15, 1.3), 4, 1.0)
    _cracks("ChestCrack", (0.1, -0.13, 1.52), (0.14, -0.12, 1.34), 3, 2.0)
    for sx in (1.0, -1.0):
        box("Shoulder", (0.2, 0.2, 0.12), (0.22 * sx, 0.0, 1.6), mat="horn", r=rot(0, 20 * sx), bevel=0.03, taper=(0.8, 0.9))
        for k in range(3):
            tube("Spike", (0.22 * sx + (k - 1) * 0.05 * sx, 0.0, 1.65), (0.27 * sx + (k - 1) * 0.06 * sx, 0.02, 1.76), 0.02, 0.002,
                 mat="horn", seg=6)
        # the folded wings: a bony arm, the membrane in panels
        root = Vector((0.12 * sx, 0.15, 1.55))
        tip = Vector((0.45 * sx, 0.3, 1.95))
        low = Vector((0.35 * sx, 0.28, 1.0))
        tube("WingBone", tuple(root), tuple(tip), 0.024, 0.012, mat="horn", seg=8)
        tube("WingFinger", tuple(tip), tuple(low), 0.012, 0.004, mat="horn", seg=6)
        n = (tip - root).cross(low - root).normalized()
        pts = [root, tip, (tip + low) * 0.5 + Vector((0.04 * sx, 0.04, 0)), low]
        c = (root + tip + low) / 3.0
        fr = kit.frame(n, Vector((0, 0, 1)))
        local = [(fr.transposed() @ (p - c)) for p in pts]
        plate("Wing", [(v.x, v.z) for v in local], tuple(c), tuple(n), up=(0, 0, 1), thick=0.008, mat="wing", outline=0.0)


def head():
    bone("head")
    tube("Neck", (0, 0.0, 1.58), (0, -0.04, 1.68), 0.08, 0.07, mat="armor")
    loft("Skull", (0, 0.03, 1.66), (0, -0.04, 1.86), [(0, 0.09, 0.1, 2.6), (0.5, 0.1, 0.11, 2.5), (1, 0.06, 0.07, 2.3)], mat="armor", cap=0.5)
    loft("Snout", (0, -0.05, 1.7), (0, -0.17, 1.69), [(0, 0.07, 0.06, 2.4), (1, 0.045, 0.04, 2.2)], mat="armor", cap=0.4)
    box("Jaw", (0.11, 0.12, 0.04), (0, -0.09, 1.645), mat="armor2", r=rot(10), bevel=0.016)
    for sx in (1.0, -1.0):
        for k in range(3):
            tube("Fang", (0.025 * sx + k * 0.012 * sx, -0.14 - k * 0.01, 1.67), (0.025 * sx + k * 0.012 * sx, -0.145 - k * 0.01, 1.63), 0.008, 0.001,
                 mat="horn", seg=5)
        ball("Eye", (0.045 * sx, -0.1, 1.76), 0.016, "eye", seg=8, outline=0)
        box("Brow", (0.06, 0.03, 0.025), (0.045 * sx, -0.1, 1.79), mat="armor2", r=rot(0, 0, -20 * sx), bevel=0.008)
        # the ram's horns: curling back and round
        p0 = Vector((0.07 * sx, -0.02, 1.84))
        pts = [p0]
        d = Vector((0.6 * sx, 0.3, 0.75)).normalized()
        for k in range(8):
            d = d.lerp(Vector((0.0, 0.9, -0.4 - k * 0.1)), 0.18).normalized()
            pts.append(pts[-1] + d * 0.06)
        for k in range(len(pts) - 1):
            tube("Horn", tuple(pts[k]), tuple(pts[k + 1]), 0.04 - k * 0.0045, 0.04 - (k + 1) * 0.0045, mat="horn", seg=10)


def arms(sx, sf):
    S = kit.SHOULDER
    x = S.x * 1.15 * sx
    ez = S.z - kit.UPPER
    wz = ez - kit.FORE
    bone("upper" + sf)
    ball("ShoulderJ", (x, 0, S.z), 0.08, "armor")
    loft("Upper", (x, 0, S.z - 0.03), (x, 0, ez + 0.03), [(0, 0.075, 0.08, 2.6), (0.5, 0.08, 0.085, 2.6), (1, 0.06, 0.065, 2.6)], mat="armor")
    _cracks("ArmCrack", (x + 0.05 * sx, -0.05, S.z - 0.06), (x + 0.04 * sx, -0.05, ez + 0.06), 3, sx * 2)
    bone("fore" + sf)
    ball("Elbow", (x, 0.01, ez), 0.06, "armor2")
    loft("Fore", (x, 0, ez - 0.03), (x, 0, wz + 0.02), [(0, 0.06, 0.065, 2.6), (1, 0.05, 0.055, 2.6)], mat="armor")
    box("Bracer", (0.11, 0.11, 0.14), (x, 0, ez - 0.14), mat="horn", bevel=0.02, taper=(0.9, 0.9))
    bone("hand" + sf)
    box("Hand", (0.07, 0.09, 0.08), (x, -0.004, wz - 0.03), mat="armor", bevel=0.02)
    bone("fingers" + sf)
    for k in range(4):
        y = -0.035 + k * 0.023
        tube("Claw", (x, y, wz - 0.07), (x - 0.01 * sx, y - 0.02, wz - 0.17), 0.012, 0.002, mat="claw", seg=6)


def tail():
    bone("coat.B")
    pts = [Vector((0, 0.12, 1.0))]
    d = Vector((0, 0.5, -0.86))
    for k in range(7):
        d = d.lerp(Vector((0, 0.95, -0.2)), 0.25).normalized()
        pts.append(pts[-1] + d * 0.12)
    for k in range(len(pts) - 1):
        tube("Tail", tuple(pts[k]), tuple(pts[k + 1]), 0.05 - k * 0.006, 0.05 - (k + 1) * 0.006, mat="armor", seg=10)
    tube("Barb", tuple(pts[-1]), tuple(pts[-1] + Vector((0, 0.1, 0.03))), 0.03, 0.001, mat="horn", seg=6)


def build():
    materials()
    mirror(legs)
    body()
    head()
    mirror(arms)
    tail()
