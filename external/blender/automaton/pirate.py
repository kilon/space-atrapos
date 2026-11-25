"""The pirate android (the raiders on foot), from its reference sheets
(external/images/npc_pirate_frame_1..4.png, npc_pirate_views.png): the
automaton's frame in cream and gold armour, a helmet with red eye slits and a
grille to the chin under a wide tricorn hat (its brim turned up on three
sides, gold-bound, a skull on each front flap), a long tattered crimson coat
open in front - a mantle round the chest, studded lapels, a standing collar,
its tails on chains of bones of their own (EXTRA_BONES, tail_solver: they
hang, swing with the legs, bend round them and over a seat), the skull and its tentacles in gold on the back - red
skull pauldrons with gold teeth, a belt of pouches with a skull hanging from
it, hoses down the back like tentacles, a heavy rifle with glowing cells."""
import math

from mathutils import Matrix, Vector

import automaton as A
import kit
from kit import ball, bone, box, decal, loft, mirror, plate, rot, tube

GUN_HAND_R = (0.0, -0.075, -0.03)
GUN_HAND_L = (0.0, 0.27, -0.03)

# The coat's tails: each a chain of four bones (kit.chain: coat.B, coat.B.2, coat.B.3, coat.B.4), the cloth
# skinned smoothly along it - it bends where it meets a leg, a seat, the floor (tail_solver, kit.drape_chain).
EXTRA_BONES = {}
EXTRA_BONES.update(kit.chain("coat.B", "pelvis", (0.0, 0.10, 1.07), (0.19, 0.19, 0.19, 0.2)))
EXTRA_BONES.update(kit.chain("coat.L", "pelvis", (0.17, 0.02, 1.07), (0.18, 0.18, 0.17, 0.2)))
EXTRA_BONES.update(kit.chain("coat.R", "pelvis", (-0.17, 0.02, 1.07), (0.18, 0.18, 0.17, 0.2)))


def tail_solver(name, P, mats):
    """A coat tail (its chain, posed at its root): it hangs from the belt (turning with the pelvis, staying
    upright as the pelvis tips), the side ones half following their thigh, the back one pushed out by a leg
    swung back - its lower segments sagging a little toward hanging straight, bent where they'd meet a leg;
    lying down, it lies with the body (clear of the floor only); in a seat, every segment hangs straight down as far as the seat, the legs and the floor let it: the
    side tails over the seat's sides and down beside its legs, the back one over the seat's back edge (under
    a chair's back, between its posts) and down behind it."""
    pel = mats["pelvis"]
    rest_rel = kit.REST["pelvis"].inverted() @ kit.REST[name]
    follow = pel @ rest_rel
    head = follow.translation
    yr = kit._rz(P["pyaw"])
    side, fwd = yr @ Vector((1, 0, 0)), yr @ Vector((0, -1, 0))
    up = yr @ kit.REST[name].to_3x3()
    if P.get("seat"):
        out = kit.drape_chain(name, P, mats, head, [up] * 4, side, fwd, reach=(100.0, 100.0, 40.0),
                              gather=(1.0, 0.9, 0.8, 0.7) if name == "coat.B" else (1.0,), stiff=0.6, follow=0.4,
                              stretch=(1.0, 0.85, 0.7, 0.55))
    else:
        tip = abs(((P["ppitch"] + 180.0) % 360.0) - 180.0)
        w = min(1.0, tip / 55.0)               # (0 upright .. 1 lying / flipping: with the body)
        if name == "coat.B":
            back = 0.0
            for sf in (".L", ".R"):
                d = mats["thigh" + sf].to_3x3() @ Vector((0, 1, 0))
                back = max(back, -d.dot(fwd))
            ang = 12.0 + math.degrees(math.asin(max(0.0, min(1.0, back)))) * 0.85
            hang = Matrix.Rotation(math.radians(-ang), 3, side) @ up
        else:
            th = mats["thigh" + name[-2:]].to_3x3()
            hang = up.to_quaternion().slerp(th.to_quaternion(), 0.5).to_matrix()
        r0 = hang.to_quaternion().slerp(follow.to_3x3().to_quaternion(), w).to_matrix()
        out = kit.drape_chain(name, P, mats, head, [r0], side, fwd, reach=(90.0, 60.0, 0.0), stiff=1.0,
                              down=up.to_quaternion().slerp(follow.to_3x3().to_quaternion(), w).to_matrix(), sag=0.3,
                              body=max(0.0, 1.0 - 2.0 * w))
    for n, m in out.items():
        mats[n] = m
    return out[name]


def materials():
    kit.M.update({
        "armor": kit.mat_toon("PIR_Armor", "#ecd29a", shade=0.68, hi=0.05, tint=(0.95, 0.85, 0.9)),
        "armor2": kit.mat_toon("PIR_Armor2", "#c89548", shade=0.68, tint=(0.95, 0.85, 0.9)),
        "armor_r": kit.mat_toon("PIR_ArmorRed", "#96202c", shade=0.66),          # (the pauldrons: red lacquer)
        "joint": kit.mat_toon("PIR_Joint", "#3d3554", shade=0.62),
        "grey": kit.mat_toon("PIR_Grey", "#62597a", shade=0.66),
        "red": kit.mat_toon("PIR_Bronze", "#b9772c", shade=0.68, tint=(0.95, 0.8, 0.9)),
        "red2": kit.mat_toon("PIR_Bronze2", "#7a4a1c", shade=0.7),
        "glow": kit.mat_glow("PIR_Glow", "#ffcf30", 1.5),
        "glow_y": kit.mat_glow("PIR_GlowY", "#fff0a0", 1.6),
        "eye": kit.mat_glow("PIR_Eye", "#ff2a1e", 1.8),
        "coat": kit.mat_toon("PIR_Coat", "#9c1c2c", shade=0.62, tint=(0.9, 0.75, 1.0)),
        "coat2": kit.mat_toon("PIR_Coat2", "#701424", shade=0.66),
        "gold": kit.mat_toon("PIR_Gold", "#f0b83c", shade=0.66, hi=0.15),
        "leather": kit.mat_toon("PIR_Leather", "#8a5530", shade=0.66),
        "hat": kit.mat_toon("PIR_Hat", "#5e1f33", shade=0.62),
        "cable": kit.mat_toon("PIR_Cable", "#8a3d78", shade=0.62),
        "gun": kit.mat_toon("PIR_Gun", "#4b4a5c", shade=0.62, hi=0.12),
        "gun_o": kit.mat_toon("PIR_GunGold", "#d8a23a", shade=0.7),
        "ink": kit.mat_outline(),
    })


SKULL = [(-0.6, 0.9), (0.6, 0.9), (1.0, 0.3), (0.8, -0.3), (0.45, -0.45), (0.4, -1.0), (-0.4, -1.0), (-0.45, -0.45), (-0.8, -0.3), (-1.0, 0.3)]


def _skull(name, at, normal, target, size, up=(0, 0, 1), cuts=1):
    """A skull painted on a part: gold, its sockets dark."""
    decal(name, A._scale(SKULL, size), at, normal, target, mat="gold", up=up, cuts=cuts, outline=0)
    for ex in (-0.4, 0.4):
        decal(name + "Eye", [(ex * size - size * 0.22, size * 0.32), (ex * size + size * 0.22, size * 0.32),
                             (ex * size + size * 0.22, -size * 0.12), (ex * size - size * 0.22, -size * 0.12)],
              at, normal, target, mat="joint", up=up, offset=0.009, outline=0, cuts=cuts)


def skull3d(name, c, s, mat="gold"):
    """A skull in the round (facing forward), s its half-width: the dome, the cheeks, the jaw, the dark sockets."""
    c = Vector(c)
    ball(name, tuple(c + Vector((0, 0, s * 0.25))), s, mat, scale=(1.0, 1.05, 0.95), seg=12)
    box(name + "Jaw", (s * 1.15, s * 1.0, s * 0.8), tuple(c + Vector((0, -s * 0.25, -s * 0.8))), mat=mat, bevel=s * 0.14,
        taper=((0.75, 0.9), (1.0, 1.0)))
    for ex in (-1.0, 1.0):
        ball(name + "Socket", tuple(c + Vector((ex * s * 0.4, -s * 0.84, s * 0.12))), s * 0.3, "joint", seg=8)
        box(name + "Tooth", (s * 0.2, s * 0.06, s * 0.36), tuple(c + Vector((ex * s * 0.22, -s * 0.76, -s * 0.98))), mat="joint", bevel=0.0)
    box(name + "Nose", (s * 0.22, s * 0.1, s * 0.3), tuple(c + Vector((0, -s * 0.94, -s * 0.36))), mat="joint", bevel=0.0,
        taper=((1.0, 1.0), (0.3, 1.0)))


def pauldron_mark(pd, x, sx, S):
    """The pauldron: red lacquer, the gold skull on it, gold teeth under its rim."""
    pd.data.materials[0] = kit.M["armor_r"]
    _skull("PauldronSkull", (x + 0.15 * sx, 0.0, S.z - 0.012), (sx, -0.05, 0.12), pd, 0.05)
    for k in range(4):
        y = -0.082 + k * 0.055
        tube("PauldronTooth", (x + (0.078 + 0.006 * (k in (1, 2))) * sx, y, S.z - 0.115), (x + 0.086 * sx, y, S.z - 0.185 - 0.02 * (k % 2)),
             0.017, 0.003, mat="gold", seg=6)
    for k in range(3):
        ball("PauldronStud", (x + 0.04 * sx, -0.066 + k * 0.066, S.z + 0.094 - 0.012 * abs(k - 1)), 0.014, "gold", seg=6)


def head():
    """The helmet: a dark shell, a mask with red eye slits under a heavy brow, a grille narrowing to the chin, gold jaw guards."""
    bone("head")
    tube("Neck", (0, 0.012, 1.57), (0, 0.006, 1.68), 0.05, 0.048, mat="joint")
    loft("Skull", (0, 0.02, 1.645), (0, 0.022, 1.86), [(0, 0.058, 0.075, 2.6), (0.45, 0.088, 0.104, 2.6), (0.8, 0.092, 0.107, 2.4), (1, 0.07, 0.08, 2.2)],
         mat="joint", cap=0.5)
    loft("Face", (0, -0.066, 1.63), (0, -0.07, 1.80),
         [(0, 0.014, 0.016, 3), (0.3, 0.038, 0.03, 3.2), (0.62, 0.064, 0.038, 3.4), (0.86, 0.074, 0.036, 3.4), (1, 0.07, 0.03, 3)],
         mat="grey", cap=0.3)
    box("Brow", (0.15, 0.04, 0.03), (0, -0.088, 1.792), mat="joint", bevel=0.009, taper=((1.0, 1.0), (0.86, 0.8)), r=rot(14))
    box("Snout", (0.044, 0.03, 0.115), (0, -0.098, 1.69), mat="joint", bevel=0.008, taper=((0.45, 1.0), (1.0, 1.0)), r=rot(-5))
    for k in range(3):
        box("Grille", (0.007, 0.012, 0.075 - 0.012 * abs(k - 1)), ((k - 1) * 0.012, -0.113, 1.70), mat="grey", bevel=0.0, r=rot(-5))
    for sx in (1.0, -1.0):
        box("Eye", (0.046, 0.012, 0.014), (0.036 * sx, -0.105, 1.758), mat="eye", bevel=0.0, r=rot(0, 12 * sx, -16 * sx))
        box("EyeLid", (0.056, 0.016, 0.012), (0.038 * sx, -0.106, 1.772), mat="joint", bevel=0.004, r=rot(0, 16 * sx, -16 * sx))
        box("Jaw", (0.026, 0.09, 0.07), (0.07 * sx, -0.04, 1.685), mat="armor2", bevel=0.008, r=rot(0, -12 * sx, 22 * sx),
            taper=((0.7, 0.7), (1.0, 1.0)))
        tube("EarBolt", (0.08 * sx, 0.02, 1.75), (0.1 * sx, 0.02, 1.75), 0.028, 0.022, mat="armor2", seg=10)
        A.cable("NeckHose", [(0.045 * sx, -0.03, 1.66), (0.07 * sx, -0.045, 1.60), (0.06 * sx, -0.07, 1.555)], 0.013, mat="cable", seg=6, steps=3)


def tricorn():
    """The hat: a low crown, a wide brim turned up on three sides - a point in front, two behind - bound in gold,
    a gold band, a skull on each front flap."""
    bone("head")
    z0 = 1.835
    cy = 0.025
    crown = loft("Crown", (0, cy, z0 - 0.012), (0, cy + 0.01, z0 + 0.12),
                 [(0, 0.104, 0.112, 2.3), (0.5, 0.098, 0.106, 2.2), (0.84, 0.072, 0.08, 2.1), (1, 0.034, 0.04, 2)], mat="hat", cap=0.5)
    tube("HatBand", (0, cy, z0 - 0.004), (0, cy, z0 + 0.022), 0.111, 0.109, mat="gold", seg=20)
    n, m = 36, 5
    TILT = 0.22

    def pt(i, s):
        ph = math.tau * i / n                          # (0 = in front, turning to its left)
        c3 = math.cos(3 * ph)
        far = 0.215 * (1 + 0.30 * c3)                  # (the corners far out)
        up = 0.118 * (0.5 - 0.5 * c3) ** 0.85          # (the sides turned up, the corners flat)
        r = 0.098 + (far - 0.098) * s
        z = z0 + up * s ** 1.5 + TILT * math.cos(ph) * (r - 0.098)       # (cocked back: the front point up off the eyes)
        return (math.sin(ph) * r, cy - math.cos(ph) * r, z)
    brim = A.skin("Brim", [[pt(i, k / m) for i in range(n)] for k in range(m + 1)], "hat", closed=True, thick=0.014)
    A.skin("BrimTrim", [[pt(i, s) for i in range(n)] for s in (0.92, 0.98, 1.03)], "gold", closed=True, thick=0.02)
    for sx in (1.0, -1.0):
        ph = math.radians(52 * sx)
        c3 = math.cos(3 * ph)
        far = 0.215 * (1 + 0.30 * c3)
        r = 0.098 + (far - 0.098) * 0.62
        at = (math.sin(ph) * r, cy - math.cos(ph) * r, z0 + 0.118 * (0.5 - 0.5 * c3) ** 0.85 * 0.62 ** 1.5 + TILT * math.cos(ph) * (r - 0.098))
        nrm = (math.sin(ph), -math.cos(ph), 0.45)
        _skull("HatSkull", at, nrm, brim, 0.03, up=(-math.sin(ph) * 0.45, math.cos(ph) * 0.45, 1.0))
        for a in (35, -35):       # the crossed bones behind it
            c, s_ = math.cos(math.radians(a)), math.sin(math.radians(a))
            bone_ = [(-0.05, -0.006), (0.05, -0.006), (0.05, 0.006), (-0.05, 0.006)]
            decal("HatBones", [(x * c - y * s_, x * s_ + y * c - 0.004) for (x, y) in bone_], at, nrm, brim, mat="gold",
                  up=(-math.sin(ph) * 0.45, math.cos(ph) * 0.45, 1.0), cuts=1, outline=0, offset=0.002, thick=0.004)


# The coat round the chest: (z, rx, ry, cy, how far round each side its front edge is - degrees from behind)
MANTLE = [(1.075, 0.186, 0.136, 0.004, 138), (1.20, 0.172, 0.124, 0.004, 138), (1.32, 0.202, 0.137, 0.004, 140), (1.46, 0.224, 0.146, 0.004, 144),
          (1.565, 0.218, 0.140, 0.006, 150), (1.615, 0.165, 0.118, 0.012, 152), (1.635, 0.118, 0.105, 0.03, 138), (1.675, 0.15, 0.13, 0.06, 112)]


def _mantle(z, table=None):
    table = table or MANTLE
    for k in range(len(table) - 1):
        a, b = table[k], table[k + 1]
        if z <= b[0] or k == len(table) - 2:
            t = (z - a[0]) / (b[0] - a[0])
            return [a[i] + (b[i] - a[i]) * t for i in range(1, 5)]


def _mantle_rings(zs, a_from=None, grow=0.0, cols=22, table=None):
    """Rings of the coat at the heights zs: all the way round the back, or (a_from = (side, degrees in from
    its front edge)) a lapel's strip. table: a coat's own shape (MANTLE's columns)."""
    rings = []
    for z in zs:
        rx, ry, cy, op = _mantle(z, table)
        if a_from is None:
            rings.append(A.arc((0, cy, z), rx + grow, ry + grow, -op, op, cols))
        else:
            sx, w = a_from
            rings.append(A.arc((0, cy, z), rx + grow, ry + grow, (op - w) * sx, (op + 1.5) * sx, 3))
    return rings


def coat():
    # ---- round the chest and the waist: open in front, the lapels turned back and studded, a standing collar
    bone("chest")
    # (a little proud of the waist's part, which it overlaps: a seam, nothing in one plane)
    A.skin("Coat", _mantle_rings([1.30, 1.38, 1.46, 1.52, 1.565, 1.615, 1.635, 1.655, 1.675], grow=0.004), "coat", closed=False, thick=0.016)
    for sx in (1.0, -1.0):
        A.skin("Lapel", _mantle_rings([1.30, 1.38, 1.46, 1.52, 1.565, 1.61], a_from=(sx, 13), grow=0.012), "coat2", closed=False, thick=0.014)
        for k in range(4):
            z = 1.33 + k * 0.075
            rx, ry, cy, op = _mantle(z)
            a = math.radians((op - 6) * sx)
            ball("LapelStud", ((rx + 0.02) * math.sin(a), cy + (ry + 0.02) * math.cos(a), z), 0.012, "gold", seg=6)
    # a yoke over the shoulders and the upper back, its edge in points, studded
    yoke = []
    for (z, g) in ((1.44, 0.016), (1.50, 0.018), (1.565, 0.018), (1.612, 0.016)):
        rx, ry, cy, op = _mantle(z)
        ring = A.arc((0, cy, z), rx + g, ry + g, -118, 118, 24)
        if z == 1.44:
            ring = [(x, y, zz + (0.045 if i % 4 == 2 else (0.02 if i % 2 else 0.0))) for i, (x, y, zz) in enumerate(ring)]
        yoke.append(ring)
    A.skin("Yoke", yoke, "coat2", closed=False, thick=0.012)
    for i in range(0, 25, 4):
        x, y, z = A.arc((0, 0.004, 1.47), 0.244, 0.166, -118, 118, 24)[i]
        ball("YokeStud", (x, y, z), 0.012, "gold", seg=6)
    bone("spine")
    A.skin("CoatWaist", _mantle_rings([1.075, 1.14, 1.20, 1.26, 1.32]), "coat", closed=False, thick=0.016)
    for sx in (1.0, -1.0):
        A.skin("LapelWaist", _mantle_rings([1.075, 1.14, 1.20, 1.26, 1.32], a_from=(sx, 13), grow=0.008), "coat2", closed=False, thick=0.014)
        for k in range(3):
            z = 1.105 + k * 0.075
            rx, ry, cy, op = _mantle(z)
            a = math.radians((op - 6) * sx)
            ball("LapelStud", ((rx + 0.016) * math.sin(a), cy + (ry + 0.016) * math.cos(a), z), 0.012, "gold", seg=6)
    # ---- hoses down the back, like tentacles
    bone("chest")
    for (x0, ln, out) in ((0.085, 0.50, 0.10), (-0.07, 0.40, 0.085), (0.01, 0.58, 0.075), (-0.15, 0.34, 0.06), (0.155, 0.28, 0.055)):
        sg = 1.0 if x0 >= 0 else -1.0
        A.cable("Cable", [(x0, 0.10, 1.585), (x0 * 1.2, 0.155 + out * 0.4, 1.60), (x0 * 1.45, 0.17 + out, 1.56 - ln * 0.3),
                          (x0 * 1.55 + 0.02 * sg, 0.19 + out * 0.8, 1.56 - ln * 0.7), (x0 * 1.35 + 0.05 * sg, 0.17 + out * 0.3, 1.56 - ln),
                          (x0 * 1.3 + 0.08 * sg, 0.20 + out * 0.3, 1.585 - ln)],
                0.024, 0.007, mat="cable", seg=7, steps=4)
    # ---- the belt: leather, a gold buckle, pouches, the skull hanging from it
    bone("pelvis")
    loft("BeltL", (0, 0.004, 1.048), (0, 0.004, 1.106), [(0, 0.206, 0.158, 2.6), (1, 0.204, 0.156, 2.6)], mat="leather", seg=24)
    box("BuckleP", (0.085, 0.02, 0.075), (0.01, -0.158, 1.077), mat="gold", bevel=0.01)
    box("BuckleIn", (0.045, 0.012, 0.038), (0.01, -0.168, 1.077), mat="leather", bevel=0.004)
    box("BuckleBar", (0.012, 0.014, 0.05), (0.01, -0.172, 1.077), mat="gold", bevel=0.0)
    for (px, w) in ((0.105, 0.062), (-0.165, 0.05)):
        a = math.atan2(px, 0.19)
        box("Pouch", (w, 0.04, 0.078), (px, -0.156 + abs(px) * 0.2, 1.062), mat="leather", bevel=0.01, r=rot(0, 0, -math.degrees(a) * 0.5))
        box("PouchFlap", (w + 0.006, 0.044, 0.03), (px, -0.158 + abs(px) * 0.2, 1.09), mat="coat2", bevel=0.006, r=rot(0, 0, -math.degrees(a) * 0.5))
        box("PouchClasp", (0.016, 0.012, 0.02), (px, -0.18 + abs(px) * 0.2, 1.074), mat="gold", bevel=0.0, r=rot(0, 0, -math.degrees(a) * 0.5))
    skull3d("BeltSkull", (-0.088, -0.182, 1.04), 0.04)
    box("BeltSkullChain", (0.014, 0.014, 0.05), (-0.088, -0.162, 1.095), mat="gold", bevel=0.0)
    box("BeltBack", (0.07, 0.02, 0.07), (0, 0.166, 1.077), mat="gold", bevel=0.008)
    # ---- the tails: long, flaring, their hems in tatters
    rag_b = [0.0, 0.13, 0.03, 0.17, 0.0, 0.09, 0.05, 0.16, 0.02, 0.12, 0.0, 0.18, 0.06, 0.02, 0.15, 0.0, 0.11, 0.04, 0.17, 0.0, 0.08]
    bone("coat.B")
    tb = A.drape("TailBack", -62, 62, (0, 0.004, 0.188, 0.140, 1.085), (0, 0.08, 0.40, 0.40, 0.36), cols=20, rows=8, thick=0.016,
                 pleat=0.022, waves=3.5, phase=math.pi, rag=rag_b, skip={(7, 3), (7, 9), (7, 15), (6, 9), (7, 10), (5, 4), (4, 16), (6, 17)})
    # the pirates' mark on it: the skull, its tentacles under it
    _skull("TailSkull", (0, 0.36, 0.90), (0, 1, 0.12), tb, 0.085, cuts=1)
    for k in range(6):
        a = math.radians(-62 + k * 24.8)
        ln = 0.20 - 0.03 * abs(k - 2.5)
        x0, x1 = math.sin(a) * 0.035, math.sin(a) * (0.07 + ln)
        y0, y1 = -0.085, -0.085 - math.cos(a) * ln - 0.03
        xm, ym = (x0 + x1) * 0.5 + math.sin(a) * 0.03, (y0 + y1) * 0.5
        decal("TailTentacle", [(x0 - 0.014, y0), (x0 + 0.014, y0), (xm + 0.012, ym), (x1 + 0.004, y1), (xm - 0.012, ym - 0.008)],
              (0, 0.36, 0.90), (0, 1, 0.12), tb, mat="gold", outline=0, cuts=1)
    for sx, sf in ((1.0, ".L"), (-1.0, ".R")):
        bone("coat" + sf)
        rag = rag_b[5:] if sx > 0 else rag_b[2:]
        A.drape("TailSide", 44 * sx, (134 * sx, 100 * sx), (0, 0.004, 0.188, 0.140, 1.085), (0, 0.04, 0.41, 0.30, 0.40), cols=14, rows=8, thick=0.016,
                pleat=0.02, waves=2.5, rag=rag, skip={(7, 4), (7, 10), (6, 10), (5, 6), (3, 9)}, grow=0.014)      # (over the back tail's edge, proud of it)


def rifle():
    """A heavy rifle: a fat barrel in its housing, two glowing cells along it, a flared muzzle, leather on the grip and stock."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    box("Grip", (0.036, 0.048, 0.10), at(-0.012, -0.02), mat="leather", r=rot(-14), bevel=0.008)
    box("Guard", (0.016, 0.085, 0.012), at(0.035, -0.022), mat="gun_o", bevel=0.0)
    box("Receiver", (0.07, 0.34, 0.105), at(0.06, 0.075), mat="gun", bevel=0.012)
    box("ReceiverTrim", (0.074, 0.30, 0.018), at(0.06, 0.128), mat="gun_o", bevel=0.004, outline=0.003)
    box("ReceiverPlate", (0.076, 0.12, 0.05), at(0.02, 0.07), mat="armor2", bevel=0.006)
    box("Stock", (0.052, 0.21, 0.09), at(-0.205, 0.06), mat="leather", taper=(1.0, 0.72), bevel=0.012)
    box("StockPlate", (0.056, 0.03, 0.115), at(-0.315, 0.05), mat="gun_o", bevel=0.006)
    tube("Housing", at(0.22, 0.075), at(0.56, 0.075), 0.05, 0.046, mat="gun", seg=14)
    for side in (1.0, -1.0):
        tube("Cell", at(0.27, 0.075, 0.05 * side), at(0.50, 0.075, 0.05 * side), 0.023, mat="glow", seg=10, outline=0)
        for f in (0.265, 0.385, 0.505):
            tube("CellBand", at(f - 0.012, 0.075, 0.05 * side), at(f + 0.012, 0.075, 0.05 * side), 0.027, mat="gun_o", seg=10)
    tube("ForeBand", at(0.545, 0.075), at(0.575, 0.075), 0.055, mat="gun_o", seg=14)
    box("ForeGrip", (0.042, 0.11, 0.05), at(0.27, 0.0), mat="leather", bevel=0.008)
    tube("Barrel", at(0.55, 0.075), at(0.74, 0.075), 0.03, mat="gun", seg=12)
    tube("Muzzle", at(0.70, 0.075), at(0.80, 0.075), 0.036, 0.05, mat="gun", seg=14)
    tube("MuzzleRim", at(0.785, 0.075), at(0.805, 0.075), 0.053, mat="gun_o", seg=14)
    tube("MuzzleGlow", at(0.80, 0.075), at(0.81, 0.075), 0.026, mat="glow", seg=10, outline=0)
    box("Mag", (0.045, 0.08, 0.11), at(0.10, -0.025), mat="gun", r=rot(8), bevel=0.008)
    tube("Scope", at(0.0, 0.158), at(0.17, 0.158), 0.022, mat="gun", seg=10)
    tube("ScopeFront", at(0.15, 0.158), at(0.2, 0.158), 0.028, mat="gun_o", seg=10)
    tube("ScopeLens", at(0.196, 0.158), at(0.204, 0.158), 0.02, mat="eye", seg=8, outline=0)


def build():
    materials()
    A.MARK = "skull"
    A.PAULDRON_MARK[0] = pauldron_mark
    mirror(A.legs)
    A.body()
    head()
    tricorn()
    mirror(A.arms)
    coat()
    rifle()
