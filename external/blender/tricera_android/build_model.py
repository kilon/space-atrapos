"""The triceratops android, modelled part by part after reference/reference.png (a model sheet: left
view and front view in a T-pose, 1980s anime style).

  blender -b --factory-startup --python external/blender/tricera_android/build_model.py [-- only head,torso]
Saves tricera_android.blend and renders/front.png, left.png (framed like the sheet's two views) and
three_quarter.png, back.png. tools/compare.py puts the renders beside the sheet. Then rig.py gives it
a skeleton and its animations (walk, punch, die); stills of them go to renders/anim/ and
tools/sheet.py tiles them into renders/anim_<name>.png.

Nothing of the sheet's picture is in the model: every part is a mesh shaped here (kit.py: lofted
bodies, swept tubes, cloth sheets, armour plates and panel lines laid on them), its sizes written in
the sheet's pixels as read off it by eye, and the painted patterns (spirals, waves, triskelions) are
drawn by code. The android faces -Y, feet on z = 0, 2.2 m to the top of the frill. All objects are in
the collection "TriceraAndroid", children of the empty TRI_Root, named <Part>_<Piece>[.L/.R]."""
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import kit  # noqa: E402
from kit import K, Q, X, Y, Z, M, lerp, zloft, xloft, yloft, tube, horn, ball, sheet, plate, ink_line, loft, ring  # noqa: E402

V = Vector
CREAM, GOLD, RED = "#edcb96", "#e0a02e", "#9a2123"


def rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


# ---------------------------------------------------------------- painted patterns

def tex_frill():
    """The frill's face as seen from the front: 4 texture pixels per sheet pixel, from 160 px left of
    the centre line and row 10. Cream with three red spirals and their tails."""
    S = 4
    c = kit.Canvas(320 * S, 220 * S, rgb(CREAM))

    def T(pts):
        return [((dx + 160) * S, (row - 10) * S) for dx, row in pts]
    red = rgb("#c8423a")
    left = kit.spiral(-82, 125, 4, 33, math.pi, 1.25) + [(-62, 96), (-48, 106), (-40, 120), (-37, 133)]
    for sgn in (1, -1):
        c.stroke(T(kit.smooth([V((sgn * dx, row)) for dx, row in left], 3)), 9.5 * S, red)
    sp = kit.spiral(0, 66, 3, 26, -math.pi / 2, 1.5)
    tail = [(-12, 93), (-24, 95), (-33, 99), (-39, 105)]
    c.stroke(T(kit.smooth([V(p) for p in sp + tail], 3)), 9.5 * S, red)
    c.stroke(T([(0, 28), (0, 40)]), 1.6 * S, rgb("#3a2a20"))
    return kit.image("TRI_frill", c.a)


def tex_kilt():
    """The front cloth (u across, v down from the belt): cream, a red band near the hem with a row of
    cream running spirals, a few fold lines."""
    W = H = 1024
    c = kit.Canvas(W, H, rgb(CREAM))
    y0, y1 = 0.800 * H, 0.945 * H
    c.rect(0, y0, W, y1, rgb("#c8423a"))
    n = 6
    uw, bh = W / n, y1 - y0
    for k in range(n):
        cx, cy = (k + 0.56) * uw, y0 + 0.47 * bh
        sp = kit.spiral(cx, cy, 0.07 * bh, 0.36 * bh, math.pi, -1.15)          # (out from the middle, ending low on the left)
        tail = [(cx - 0.36 * uw, y1 - 0.10 * bh), (cx - 0.60 * uw, y1 + 0.05 * bh)]
        c.stroke(kit.smooth([V(p) for p in sp + tail], 3), 0.15 * bh, rgb(CREAM))
    line = rgb("#4a3626")
    for u, v0, v1, lean in ((0.24, 0.06, 0.74, 0.03), (0.70, 0.18, 0.76, -0.02), (0.44, 0.22, 0.36, 0.05)):
        c.stroke([(u * W, v0 * H), ((u + lean) * W, v1 * H)], 3.0, line)
    return kit.image("TRI_kilt", c.a)


def triskelion(cx, cy, rx, ry, flip=1):
    """Three spirals joined at the centre (lists of points); rx, ry: its radii in the picture."""
    arms = []
    for k in range(3):
        a = math.radians(-90 + 120 * k)
        ox, oy = 0.52 * math.cos(a), 0.52 * math.sin(a)
        sp = kit.spiral(ox, oy, 0.46, 0.07, a + math.pi, flip * 1.3, n=70)
        arm = [(0.0, 0.0)] + sp
        arms.append([(cx + x * rx, cy + y * ry) for x, y in arm])
    return arms


def tex_cape(marks):
    """The cape (u around, v down): crimson, a gold band along the hem, a gold triskelion on each
    side panel. marks: (u, v, radius along u, radius along v, handedness) of each triskelion."""
    W, H = 2048, 1024
    c = kit.Canvas(W, H, rgb(RED))
    c.rect(0, 0.958 * H, W, H, rgb(GOLD))
    c.rect(0, 0.954 * H, W, 0.958 * H, rgb("#2a0a0a"))
    for u, v, ru, rv, flip in marks:
        for arm in triskelion(u * W, v * H, ru * W, rv * H, flip):
            c.stroke(kit.smooth([V(p) for p in arm], 2), 0.17 * (ru * W + rv * H) / 2, rgb(GOLD))
    return kit.image("TRI_cape", c.a)


def materials(cape_marks):
    t = kit.mat_toon
    M.update({
        "cream": t("TRI_Cream", CREAM, "#ac8e66"),
        "horn": t("TRI_Horn", "#f0d6a6", "#a4875f"),
        "navy": t("TRI_Navy", "#46587f", "#2a3350"),
        "steel": t("TRI_Steel", "#6f80a6", "#3d4a6c"),
        "gold": t("TRI_Gold", GOLD, "#b3761c", hi="#fad786"),
        "red": t("TRI_Red", RED, "#6a1417"),
        "tassel": t("TRI_Tassel", "#a32829", "#701a1c"),
        "lining": t("TRI_Lining", "#5a1214", "#3c0c0e"),
        "frill": t("TRI_Frill", CREAM, "#b79869", img=tex_frill()),
        "frill_back": t("TRI_FrillBack", "#8a3018", "#5e2010"),
        "kilt": t("TRI_Kilt", CREAM, "#ac8e66", img=tex_kilt()),
        "cape": t("TRI_Cape", RED, "#6a1417", img=tex_cape(cape_marks), tone=(-0.25, 0.9, 0.3), edge=0.16),
        "dark": kit.mat_flat("TRI_Dark", "#141a22"),
        "cyan": kit.mat_flat("TRI_Cyan", "#3ef1fc", 1.6),
        "white": kit.mat_flat("TRI_White", "#e8ffff", 1.5),
        "ink": kit.mat_flat("TRI_Ink", "#0a0706", 1.0, cull=True),
    })


# ---------------------------------------------------------------- head

FR_T0 = 0.20                      # where the frill starts (inside the skull), as a fraction of its radius
FR_RX, FR_RZ = 141.0, 120.0       # the frill face's radii in the front view (px), about (0, row 150)


def frill_max_angle(t):
    return math.radians(100 + 12 * ((t - 0.7) / 0.3) ** 2)


def frill_pt(th, t, back=0.0):
    """The frill's face: th = the angle from straight up (radians, + to the android's left), t = 0 at
    its centre .. 1 at the edge. It is a dish swept back, more at the sides than at the top."""
    g = max((t - FR_T0) / (1 - FR_T0), 0.0) ** 1.15
    sweep = 50 + 62 * min(abs(math.sin(th)), 1.0) ** 1.3 if abs(th) < math.pi / 2 else 112
    return Q(t * FR_RX * math.sin(th), 287 + sweep * g + back, 150 - t * FR_RZ * math.cos(th))


def frill_normal(th, t):
    e = 1e-3
    du = frill_pt(th + e, t) - frill_pt(th - e, t)
    dv = frill_pt(th, t + e) - frill_pt(th, t - e)
    n = du.cross(dv).normalized()
    return n if n.y < 0 else -n


def head():
    # --- the skull: wide at the cheeks, a narrow snout, a hooked beak
    yloft("Head_Skull", [
        (299, 150, 200, 26, 0.1), (294, 141, 205, 34, 0.15), (285, 137, 209, 40, 0.2), (268, 139, 213, 41, 0.25), (256, 144, 215, 38, 0.3),
        (245, 149, 217, 34, 0.35), (235, 155, 218, 27.5, 0.4), (225, 161, 220, 22.5, 0.45), (212, 169, 222, 19.5, 0.5),
        (198, 180, 225, 17.5, 0.55), (186, 186, 230, 15, 0.6), (176, 192, 235, 12, 0.65), (169, 199, 239, 8.5, 0.7), (165, 212, 242, 5, 0.7),
        (164.5, 228, 244, 2.2, 0.7)], "cream", n=2.7, m=32, sub=1)
    yloft("Head_Jaw", [(262, 209, 226, 27), (245, 214, 229, 22), (226, 218, 231, 16), (208, 221, 233, 11.5), (194, 225, 236, 7.5),
                       (186, 229, 238, 3)], "cream", n=2.6, m=24, sub=1)
    sk = kit.Caster(["Head_Skull", "Head_Jaw"])
    # eyes: a dark socket and a slanted cyan eye on the slope between cheek and snout
    for sgn, s in ((-1, "R"), (1, "L")):
        inner, outer = Q(sgn * 13, 221, 183), Q(sgn * 35, 248, 166)
        c = (inner + outer) / 2
        along = (outer - inner).normalized()
        nrm = V((sgn * 0.50, -0.83, 0.24))
        nrm = (nrm - along * nrm.dot(along)).normalized()
        tube("Head_Socket." + s, [c - nrm * 0.010, c + nrm * 0.006], 10 * K, 18 * K, mat="dark", m=20, n=1.8, up=along, ink=0)
        tube("Head_Eye." + s, [c - nrm * 0.004, c + nrm * 0.008], 5.8 * K, 12.5 * K, mat="cyan", m=20, n=1.5, up=along, ink=0)
    # brow ridge over each eye (a plate from the side), cheek plate behind the eye
    plate("Head_Brow.L", [(214, 168), (232, 160), (256, 158), (264, 150), (286, 150), (290, 168), (268, 171), (250, 165), (232, 164)],
          "S", sk, "cream", thick=0.007, lift=0.001, grid=4, bevel=0.002, mirror=True)
    plate("Head_Cheek.L", [(246, 191), (262, 186), (284, 190), (288, 205), (262, 213), (244, 208)],
          "S", sk, "cream", thick=0.006, lift=0.001, grid=4, bevel=0.002, mirror=True)
    for i, pts in enumerate(([(170, 235), (186, 226), (210, 222), (240, 219), (262, 213)],          # the mouth
                             [(238, 190), (232, 204), (236, 217)],   # sutures
                             [(178, 200), (186, 204)], [(172, 212), (180, 207), (192, 208)])):
        ink_line("Head_Line%d.L" % i, pts, "S", sk, mirror=True)
    # nostril
    plate("Head_Nostril.L", [(180, 201), (188, 198), (190, 203), (183, 207)], "S", sk, "dark", thick=0.0015, lift=0.0006,
          grid=2, rnd=1, bevel=0, ink=0, mirror=True)
    # --- horns
    horn("Head_NoseHorn", Q(0, 184, 189), Q(0, 141, 152), V((0, 6 * K, -3 * K)), 12.5 * K, 16 * K, "horn", m=16, up=V((0, 1, 0.6)))
    for sgn, s in ((-1, "R"), (1, "L")):
        p0, p1 = Q(sgn * 27, 276, 148), Q(sgn * 52, 146, 66)
        horn("Head_BrowHorn." + s, p0, p1, V((sgn * 3 * K, 0, -9 * K)), 14 * K, 14.5 * K, "horn", steps=18, m=18, power=0.9, up=Z)
        d = (p1 - p0).normalized()
        c = p0 + d * (11 * K)
        tube("Head_BrowHornRing." + s, _circle(c, d, 13.5 * K, 14 * K, X), 5 * K, 7 * K, mat="gold", m=8, n=3.0, closed=True,
             up=lambda p, c=c, d=d: d)
    tube("Head_Crown", [Q(-17, 268, 136), Q(-8, 266, 131), Q(8, 266, 131), Q(17, 268, 136)], 4 * K, 6 * K, mat="gold", m=8, n=3.0, sub=3, up=Y)
    # --- the frill
    def fn(u, v):
        t = lerp(FR_T0, 1.0, v)
        return frill_pt(lerp(-1, 1, u) * frill_max_angle(t), t)

    def uvfn(u, v):
        p = fn(u, v)
        return ((p.x / K + 160) / 320.0, 1.0 - ((kit.GY - p.z / K) - 10) / 220.0)
    sheet("Head_Frill", fn, 96, 22, "frill", thick=7 * K, uvfn=uvfn, back="frill_back", bevel=0.003)
    ths = [lerp(-1, 1, i / 96) * frill_max_angle(1.0) for i in range(97)]
    tube("Head_FrillRim", [frill_pt(th, 1.02, back=3) for th in ths], 4.2 * K, 6 * K, mat="gold", m=10, n=3.2,
         up=[frill_normal(th, 1.0) for th in ths])
    for sgn, s in ((-1, "R"), (1, "L")):
        low = [frill_pt(sgn * frill_max_angle(t), t, back=2) + V((0, 0, -2 * K)) for t in (0.40 + 0.04 * i for i in range(16))]
        tube("Head_FrillLowRim." + s, low, 4.5 * K, 8 * K, mat="gold", m=8, n=3.0,
             up=lambda p, sgn=sgn: frill_normal(sgn * 1.8, 0.8))
        # the rolled underside: a red strip that turns back and down from the lower edge
        def under(u, v, sgn=sgn):
            t = lerp(0.40, 1.0, u)
            p = frill_pt(sgn * frill_max_angle(t), t, back=4)
            return p + V((sgn * -4 * K * v, 30 * K * v, -(22 * v - 9 * v * v) * K * (0.4 + 0.6 * u)))
        sheet("Head_FrillUnder." + s, under, 14, 4, "frill_back", thick=4 * K)
    for i in range(11):
        th = math.radians(-110 + 22 * i)
        base = frill_pt(th, 1.045, back=2)
        out = (frill_pt(th, 1.06) - frill_pt(th, 0.98)).normalized()
        nrm = frill_normal(th, 1.0)
        tipd = (out * 0.8 + nrm * 0.6).normalized()
        horn("Head_FrillStud%02d" % i, base - tipd * (3 * K), base + tipd * (13 * K), V((0, 0, 0)), 11.5 * K, 11.5 * K, "gold",
             steps=1, m=4, power=1.0, up=nrm, flat=True)
    # --- ears, earrings
    for sgn, s in ((-1, "R"), (1, "L")):
        tube("Head_Ear." + s, [Q(sgn * 34, 298, 192), Q(sgn * 54, 298, 192)], 17 * K, mat="gold", m=28, up=Z, bevel=0.004)
        tube("Head_EarRing." + s, _circle(Q(sgn * 55, 298, 192), X, 11.5 * K, 11.5 * K, Z), 2.6 * K, mat="gold", m=6, closed=True)
        ball("Head_EarGem." + s, Q(sgn * 55, 298, 192), 5 * K, 7.5 * K, 7.5 * K, "cyan", ink=0.5)
        tube("Head_EarLink." + s, [Q(sgn * 54, 298, 207), Q(sgn * 54, 298, 214)], 2.4 * K, mat="gold", m=8, up=X)
        ball("Head_EarBead." + s, Q(sgn * 54, 298, 215), 3.6 * K, mat="gold", m=10, rows=6, ink=0.6)
        _drop("Head_EarDrop." + s, Q(sgn * 54, 298, 230), 5.6 * K, 13.5 * K)
    # --- neck
    tube("Neck", [Q(0, 276, 198), Q(0, 284, 215), Q(0, 291, 235), Q(0, 296, 258)], lambda t: (27 + 2.5 * math.cos(t * 6 * math.pi)) * K,
         lambda t: (27 + 2.5 * math.cos(t * 6 * math.pi)) * K, mat="navy", m=24, sub=6, up=Y)


def _circle(c, axis, ru, rv, ref, n=28):
    """n points of an ellipse around c, in the plane across `axis`."""
    axis = axis.normalized()
    u = (ref - axis * ref.dot(axis)).normalized()
    v = axis.cross(u)
    return [c + u * (ru * math.cos(2 * math.pi * i / n)) + v * (rv * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _drop(name, c, r, h, mat="cyan"):
    """A tear drop: pointed above, round below."""
    rings = []
    for i in range(1, 12):
        f = i / 12
        w = math.sin(math.pi * f) ** (0.8 if f > 0.5 else 1.5)
        rings.append(ring(c + Z * (h * (1 - 2 * f)), X, Y, r * w, r * w, 2.0, 14))
    return loft(name, rings, mat, ink=0.6)


# ---------------------------------------------------------------- torso

def torso():
    zloft("Torso_Core", [
        (246, -30, 30, 268, 322), (262, -56, 56, 242, 334), (300, -64, 64, 220, 338), (335, -60, 60, 222, 334),
        (352, -58, 58, 226, 330), (375, -53, 53, 229, 324), (398, -48, 48, 232, 318), (412, -48, 48, 232, 318)], "navy", n=2.8, m=36)
    zloft("Torso_Pelvis", [(404, -50, 50, 230, 318), (413, -83, 83, 213, 319), (440, -84, 84, 214, 317), (462, -68, 68, 230, 308)],
          "navy", n=2.3, m=36)
    zloft("Torso_Chest", [
        (257, -58, 58, 240, 332), (263, -68, 68, 226, 337), (275, -76, 76, 214, 340), (300, -82, 82, 207, 342),
        (322, -93, 93, 207, 340), (340, -89, 89, 211, 336), (349, -62, 62, 220, 330)], "cream", n=3.3, m=40, bevel=0.004)
    tc = kit.Caster(["Torso_Chest", "Torso_Core"])
    # the two cream strips of the abdomen, the navy core between them
    plate("Torso_Abs.R", [(-53, 349), (-29, 347), (-21, 380), (-22, 404), (-40, 404), (-51, 374)], "F", tc, "cream",
          thick=0.011, lift=0.0, grid=4, bevel=0.003, mirror=True)
    ac = kit.Caster(["Torso_Chest", "Torso_Core", "Torso_Abs.R", "Torso_Abs.L"])
    for i, pts in enumerate(([(-62, 264), (-48, 276), (-40, 296)], [(-81, 300), (-58, 308), (-44, 322), (-40, 340)],
                             [(-93, 322), (-70, 318), (-58, 308)], [(-89, 340), (-62, 336), (-44, 322)],
                             [(-51, 374), (-36, 372), (-24, 380)], [(-12, 366), (-10, 402)], [(-20, 386), (20, 386)])):
        ink_line("Torso_Line%d.R" % i, pts, "F", ac, mirror=(i < 6))
    for i, pts in enumerate(([(322, 352), (322, 403)], [(250, 376), (320, 374)], [(236, 262), (252, 300), (246, 344)],
                             [(252, 300), (300, 296), (334, 306)], [(214, 330), (246, 344), (300, 340)])):
        ink_line("Torso_SideLine%d.L" % i, pts, "S", ac, mirror=True)
    # collar
    loop = []
    for i in range(40):
        a = 2 * math.pi * i / 40
        ca = math.cos(a)
        loop.append(Q(36 * math.sin(a), 293 - 32 * ca, 249 + 8 * ca + 9 * max(ca, 0) ** 5))
    tube("Torso_Collar", loop, 5 * K, 11 * K, mat="gold", m=10, n=3.5, closed=True, up=Z)
    # the sun on the chest: a gold disc, a cyan core, eight cyan rays lying on the chest
    (c0,), d = tc.drop("F", [(0, 305)])
    f = V((0, -1, 0))
    tube("Sun_Disc", [c0 + f * 0.001, c0 + f * 0.013], 37 * K, mat="gold", m=40, up=Z, bevel=0.003)
    tube("Sun_Ring", _circle(c0 + f * 0.014, Y, 26 * K, 26 * K, Z, 36), 3.2 * K, mat="gold", m=6, closed=True)
    ball("Sun_Core", c0 + f * 0.013, 22.5 * K, 9 * K, 22.5 * K, "cyan", m=32, rows=12, ink=0.6)
    for i in range(8):
        a = math.radians(45 * i)
        dr = V((math.sin(a), 0, math.cos(a)))
        length = 57 if i % 2 == 0 else 50
        base = c0 + f * 0.012 + dr * (27 * K)
        try:
            (tip,), _ = tc.drop("F", [(dr.x * length, 305 - dr.z * length)], maxdev=0.05)
            tip = tip + f * 0.005
        except RuntimeError:
            tip = c0 + f * 0.004 + dr * (length * K)
        tip.y = max(tip.y, c0.y - 0.004) if abs(dr.x) < 0.1 else tip.y
        horn("Sun_Ray%d" % i, base, tip, V((0, 0, 0)), 6 * K, 3.5 * K, "cyan", steps=1, m=4, power=1.0, up=f, flat=True, ink=0.6)
    plate("Sun_Tail", [(-33, 330), (33, 330), (27, 351), (0, 367), (-27, 351)], "F", ac, "gold", thick=0.008, lift=0.001, grid=4)
    # belt
    loop = ring(Q(0, 266, 414), X, Y, 88 * K, 57 * K, 2.3, 56)
    for p in loop:                                   # (it sits lower in front)
        p.z += (p.y - Q(0, 266, 0).y) / (57 * K) * 8 * K
    tube("Belt", loop, 5 * K, 11.5 * K, mat="gold", m=12, n=4.5, closed=True, up=Z)
    # the bull's head buckle
    zloft("Bull_Head", [(409, -20, 20, 188, 212), (415, -29, 29, 179, 214), (430, -31, 31, 167, 214), (446, -26, 26, 163, 208),
                        (462, -18, 18, 164, 200), (476, -14, 14, 166, 195), (486, -15, 15, 169, 194), (492, -10, 10, 174, 191)],
          "gold", n=2.7, m=28, sub=1)
    bc = kit.Caster(["Bull_Head"])
    for sgn, s in ((-1, "R"), (1, "L")):
        horn("Bull_Horn." + s, Q(sgn * 22, 194, 418), Q(sgn * 33, 194, 391), V((sgn * 13 * K, 0, -8 * K)), 6.5 * K, 6.5 * K, "gold", m=10, up=Y)
        horn("Bull_Ear." + s, Q(sgn * 27, 199, 434), Q(sgn * 44, 201, 431), V((0, 0, -3 * K)), 5.5 * K, 3.5 * K, "gold", steps=6, m=8, up=Y)
    plate("Bull_Eye.R", [(-19, 437), (-11, 440), (-10, 444), (-18, 442)], "F", bc, "white", thick=0.0015, lift=0.0005, grid=2, bevel=0, ink=0, mirror=True)
    plate("Bull_Nostril.R", [(-10, 477), (-5, 476), (-4, 481), (-9, 482)], "F", bc, "dark", thick=0.0015, lift=0.0005, grid=2, bevel=0, ink=0, mirror=True)
    for i, pts in enumerate(([(-26, 431), (-12, 436), (-8, 446)], [(-8, 446), (-9, 462), (-12, 472)], [(-14, 472), (0, 469), (14, 472)])):
        ink_line("Bull_Line%d.R" % i, pts, "F", bc, mirror=(i < 2), r=0.0018)


def pauldron_fn(x0, x1, ry=50.0, rz=56.0, down=0.0):
    """A shoulder shell: a vault over the arm (u: from the neck end to the pointed outer end,
    v: from its front edge over the top to its back edge)."""
    def fn(u, v):
        top = 228 - 20 * u + 39 * u * u + down
        Rz = rz * (1 - 0.45 * u)
        spread = math.radians(113 - 45 * u) * math.sqrt(max(1 - u ** 6, 0.0)) + math.radians(3)
        phi = lerp(-1, 1, v) * spread
        return Q(lerp(x0, x1, u), 290 + ry * (1 - 0.30 * u) * math.sin(phi), top + Rz - Rz * math.cos(phi))
    return fn


def shoulders():
    sheet("Shoulder_Pad.R", pauldron_fn(-99, -187), 16, 28, "cream", thick=5 * K, bevel=0.003, flip=True, mirror=True)
    sheet("Shoulder_PadLow.R", pauldron_fn(-104, -184, 46, 50, down=13), 14, 24, "cream", thick=5 * K, bevel=0.003, flip=True, mirror=True)

    def strap(u, v):
        phi = lerp(-1, 1, v) * math.radians(113)
        return Q(lerp(-84, -99, u) - 7 * math.sin(abs(phi)) ** 2, 290 + 52.5 * math.sin(phi), 226 + 59 - 59 * math.cos(phi))
    sheet("Shoulder_Strap.R", strap, 3, 28, "gold", thick=5 * K, bevel=0.002, flip=True, mirror=True)
    ball("Shoulder_Joint.R", Q(-104, 290, 284), 28 * K, 30 * K, 27 * K, "navy", mirror=True)
    ball("Shoulder_Stud.R", Q(-86, 239, 297), 3.5 * K, mat="gold", m=10, rows=6, ink=0.5, mirror=True)
    pc = kit.Caster(["Shoulder_Pad.R"])
    ink_line("Shoulder_Crack.R", [(-118, 226), (-126, 238), (-142, 240), (-152, 250)], "F", pc, mirror=True)
    ink_line("Shoulder_Crack2.R", [(-152, 250), (-160, 262)], "F", pc, mirror=True)


# ---------------------------------------------------------------- arms

def arms():
    def st(rows):      # (dx, top, bottom, depth factor) -> rings around the arm's axis (s = 290)
        return [(dx, a, b, 290 - (b - a) / 2 * f, 290 + (b - a) / 2 * f) for dx, a, b, f in rows]
    xloft("Arm_Shoulder.R", st([(-98, 266, 302, 1.0), (-130, 262, 304, 1.0), (-158, 264, 302, 1.0)]), "navy", m=20, mirror=True)
    xloft("Arm_Upper.R", st([(-150, 266, 299, 1.0), (-156, 259, 303, 1.0), (-180, 257, 304, 1.0), (-203, 258, 304, 1.0), (-211, 263, 300, 1.0)]),
          "cream", n=2.9, m=28, bevel=0.003, mirror=True)
    xloft("Arm_Elbow.R", st([(-205, 266, 298, 1.0), (-212, 259, 305, 1.0), (-229, 256, 308, 1.0), (-245, 259, 305, 1.0), (-252, 266, 298, 1.0)]),
          "navy", m=24, mirror=True)
    xloft("Arm_Fore.R", st([(-245, 266, 298, 0.95), (-251, 252, 309, 0.95), (-268, 244, 314, 0.92), (-290, 246, 315, 0.9), (-315, 255, 309, 0.9),
                            (-336, 262, 301, 0.92), (-340, 266, 298, 0.92)]), "cream", n=2.9, m=28, bevel=0.003, mirror=True)
    xloft("Arm_Bracer.R", st([(-337, 262, 302, 1.0), (-340, 258, 305, 1.0), (-389, 258, 305, 1.0), (-392, 262, 302, 1.0)]),
          "gold", n=5.0, m=32, bevel=0.003, mirror=True)
    ball("Arm_BracerGem.R", Q(-364, 290, 259), 15 * K, 10 * K, 4.5 * K, "cyan", ink=0.6, mirror=True)
    xloft("Arm_Wrist.R", st([(-390, 268, 298, 0.8), (-402, 268, 298, 0.8)]), "navy", m=16, mirror=True)
    xloft("Arm_Palm.R", [(-398, 270, 297, 268, 312), (-404, 266, 300, 266, 314), (-428, 267, 299, 266, 314), (-441, 271, 296, 269, 311)],
          "cream", n=3.2, m=24, bevel=0.003, mirror=True)
    for i, s in enumerate((271, 284, 297, 309)):
        fan = (s - 290) * 0.35
        tube("Arm_Finger%d.R" % i, [Q(-436, s, 281), Q(-460, s + fan * 0.4, 285)], 7.8 * K, 7.5 * K, mat="cream", m=10, bevel=0.002, mirror=True)
        horn("Arm_Claw%d.R" % i, Q(-456, s + fan * 0.4, 285), Q(-487 + abs(s - 290) * 0.25, s + fan, 298), V((0, 0, 3 * K)), 7.2 * K, 7.2 * K,
             "navy", steps=10, m=10, power=0.6, up=Y, mirror=True)
    tube("Arm_Thumb.R", [Q(-400, 266, 296), Q(-416, 260, 313)], 9.5 * K, 9 * K, mat="cream", m=10, bevel=0.002, mirror=True)
    horn("Arm_ThumbClaw.R", Q(-413, 261, 310), Q(-431, 256, 331), V((-4 * K, 0, 0)), 8 * K, 8 * K, "navy", steps=10, m=10, power=0.6, up=Y, mirror=True)
    ac = kit.Caster(["Arm_Upper.R", "Arm_Fore.R", "Arm_Elbow.R", "Arm_Palm.R", "Arm_Bracer.R"])
    for i, pts in enumerate(([(-152, 270), (-180, 268), (-208, 272)], [(-250, 262), (-272, 266), (-300, 262), (-338, 270)],
                             [(-262, 296), (-285, 300), (-292, 312)], [(-285, 300), (-338, 290)],
                             [(-221, 258), (-221, 306)], [(-237, 258), (-237, 306)], [(-207, 281), (-250, 281)],
                             [(-338, 290), (-360, 296), (-392, 290)], [(-352, 262), (-348, 294)], [(-378, 262), (-382, 294)],
                             [(-408, 270), (-424, 280), (-440, 280)])):
        ink_line("Arm_Line%d.R" % i, pts, "F", ac, mirror=True, r=0.0017)


# ---------------------------------------------------------------- legs

def Lz(st):
    """Leg measures are read off the leg at the left of the front view (dx < 0); the leg is built
    on the android's left (dx > 0), where the left view sees it, and mirrored."""
    return [(s[0], -s[2], -s[1]) + tuple(s[3:]) for s in st]


def neg(pts):
    return [(-x, y) for x, y in pts]


def legs():
    ball("Leg_Hip.L", Q(70, 262, 456), 22 * K, 26 * K, 24 * K, "navy", mirror=True)
    zloft("Leg_ThighCore.L", Lz([(440, -82, -52, 238, 286), (480, -92, -52, 238, 290), (540, -100, -54, 242, 292),
                                 (600, -98, -60, 250, 292), (655, -96, -64, 256, 288)]), "navy", n=2.6, m=24, mirror=True)
    zloft("Leg_Thigh.L", Lz([(442, -80, -50, 236, 282), (460, -86, -49, 235, 284), (500, -96, -50, 236, 285), (540, -103, -52, 239, 284),
                             (580, -100, -62, 243, 274), (612, -94, -68, 248, 264), (646, -88, -72, 252, 258)]), "cream", n=3.0, m=32,
          bevel=0.004, mirror=True)
    tube("Leg_KneePivot.L", [Q(52, 290, 669), Q(113, 290, 669)], 18.5 * K, mat="navy", m=28, up=Z, bevel=0.004, mirror=True)
    tube("Leg_KneePivotCap.L", [Q(49, 290, 669), Q(116, 290, 669)], 10 * K, mat="steel", m=20, up=Z, bevel=0.003, mirror=True)
    zloft("Leg_KneeCap.L", Lz([(639, -92, -68, 230, 243), (648, -104, -60, 226, 249), (668, -113, -50, 225, 260), (690, -110, -53, 227, 263),
                               (712, -102, -62, 235, 262), (729, -96, -70, 248, 259)]), "cream", n=3.2, m=32, bevel=0.004, mirror=True)
    zloft("Leg_Shin.L", Lz([(693, -112, -56, 279, 325), (703, -117, -52, 272, 330), (718, -120, -52, 264, 332), (736, -121, -54, 258, 331),
                            (756, -117, -58, 257, 319), (775, -111, -61, 260, 306), (800, -108, -67, 261, 302), (821, -106, -70, 259, 302)]),
          "cream", n=3.0, m=32, bevel=0.004, mirror=True)
    zloft("Leg_Calf.L", Lz([(772, -104, -70, 294, 324), (790, -103, -71, 298, 328), (808, -103, -71, 298, 327), (823, -102, -72, 298, 321)]),
          "navy", m=20, mirror=True)
    zloft("Leg_Cuff.L", Lz([(817, -110, -67, 257, 321), (824, -121, -59, 251, 325), (838, -130, -53, 249, 331), (848, -129, -54, 251, 332),
                            (860, -123, -59, 257, 322), (873, -115, -65, 268, 306)]), "cream", n=3.4, m=32, bevel=0.004, mirror=True)
    tube("Leg_Ankle.L", [Q(91, 284, 846), Q(93, 285, 880), Q(94, 285, 916)], 16.5 * K, 15 * K, mat="navy", m=18, up=X, mirror=True)
    tube("Leg_AnklePivot.L", [Q(64, 322, 856), Q(120, 322, 856)], 11.5 * K, mat="navy", m=20, up=Z, bevel=0.003, mirror=True)
    # the foot: a wedge from the ankle down to the toes, three toes with claws, the heel block
    zloft("Foot_Instep.L", Lz([(858, -112, -77, 248, 263), (866, -115, -75, 243, 274), (880, -119, -72, 235, 286), (898, -127, -66, 224, 292),
                               (916, -140, -58, 209, 297), (930, -148, -55, 201, 294), (938, -146, -57, 203, 286)]), "cream", n=2.9, m=32,
          bevel=0.003, mirror=True)
    for i, (bx, tx, s_tip, row_tip) in enumerate(((-148, -170, 188, 975), (-116, -127, 141, 979), (-72, -65, 158, 982))):
        mx = lerp(bx, tx, 0.45)
        s_mid = lerp(228, s_tip, 0.42)
        tube("Foot_Toe%d.L" % i, [Q(-bx, 228, 933), Q(-mx, s_mid, 949)], 12.5 * K, 12.5 * K, mat="cream", m=14, n=2.6, bevel=0.003, mirror=True)
        ball("Foot_ToeJoint%d.L" % i, Q(-lerp(bx, mx, 0.4), lerp(228, s_mid, 0.4), 946), 10.5 * K, 12 * K, 9 * K, "navy", m=12, rows=6, mirror=True)
        horn("Foot_Claw%d.L" % i, Q(-mx, s_mid + 2, 950), Q(-tx, s_tip, row_tip), V((0, 0, 13 * K)), 12 * K, 13 * K, "gold",
             steps=12, m=14, power=0.5, up=Z, mirror=True)
    zloft("Foot_Heel.L", Lz([(909, -106, -80, 290, 308), (915, -110, -76, 286, 312), (938, -111, -75, 284, 315), (951, -109, -77, 285, 310),
                             (958, -105, -81, 289, 303)]), "cream", n=3.3, m=24, bevel=0.004, mirror=True)
    zloft("Foot_Sole.L", Lz([(950, -102, -82, 264, 300), (956, -104, -80, 260, 302), (976, -104, -80, 260, 302)]), "navy", n=3.0, m=20,
          bevel=0.003, mirror=True)
    parts = ["Leg_Thigh.L", "Leg_KneeCap.L", "Leg_Shin.L", "Leg_Cuff.L", "Foot_Instep.L", "Foot_Heel.L"]
    lc = kit.Caster(parts)
    plate("Leg_CuffNotch.L", neg([(-107, 840), (-100, 832), (-84, 832), (-77, 840), (-76, 875), (-108, 875)]), "F", lc, "navy",
          thick=0.003, lift=0.0008, grid=3, bevel=0, mirror=True)
    for i, pts in enumerate(([(-80, 640), (-83, 686), (-84, 727)], [(-113, 669), (-88, 686), (-50, 674)],                 # knee cap
                             [(-119, 716), (-105, 738), (-100, 760), (-98, 812)], [(-76, 742), (-78, 780), (-80, 812)],     # shin
                             [(-110, 826), (-100, 822), (-82, 822), (-70, 827)],
                             [(-118, 884), (-124, 905), (-132, 926)], [(-92, 884), (-92, 905), (-93, 928)])):
        ink_line("Leg_Line%d.L" % i, neg(pts), "F", lc, mirror=True)
    for i, pts in enumerate(([(228, 702), (250, 683), (260, 671)], [(250, 683), (253, 710), (255, 732)],                    # knee cap
                             [(283, 700), (298, 742), (305, 772)], [(262, 800), (288, 790), (302, 782)],                    # shin
                             [(262, 840), (290, 827), (320, 836)], [(264, 868), (266, 894), (242, 924)],
                             [(288, 932), (312, 928)])):
        ink_line("Leg_SideLine%d.L" % i, pts, "S", lc, mirror=True)
    ball("Leg_ShinRivet.L", Q(121, 284, 727), 2.6 * K, mat="dark", m=8, rows=4, ink=0, mirror=True)


# ---------------------------------------------------------------- kilt

def kilt():
    def fn(u, v):
        w = lerp(52, 77, v ** 0.6)
        a = 2 * u - 1
        return Q(a * w, lerp(210, 186, v) + lerp(14, 42, v) * abs(a) ** 2.2 + 2.2 * v * math.sin(u * 5 * math.pi),
                 lerp(425, 641, v) + 3 * (1 - a * a) * v)
    sheet("Kilt_Cloth", fn, 36, 30, "kilt", thick=3.5 * K, flip=True)
    # the hip plates: a shell round the front and outside of each hip, flaring out toward its lower edge
    low = kit.interp([548, 548, 548, 546, 544, 550, 558, 561, 527])

    def tasset(u, v):
        a = math.radians(lerp(-122, 76, u))
        row = lerp(440, low(u), v)
        t = (row - 440) / 105.0
        ca, sa = math.cos(a), math.sin(a)
        e = 2.0 / 3.0
        return Q(lerp(64, 86, t) + lerp(20, 40, t) * math.copysign(abs(ca) ** e, ca),
                 lerp(263, 266, t) + lerp(33, 27, t) * math.copysign(abs(sa) ** e, sa), row)
    sheet("Kilt_Tasset.L", tasset, 48, 14, "cream", thick=0.012, bevel=0.003, flip=True, mirror=True)
    tcast = kit.Caster(["Kilt_Tasset.L"])
    for i, pts in enumerate(([(-102, 462), (-95, 478), (-98, 500), (-106, 520)], [(-64, 470), (-70, 500), (-62, 546)])):
        ink_line("Kilt_TassetLine%d.L" % i, neg(pts), "F", tcast, mirror=True)
    for i, pts in enumerate(([(238, 512), (256, 534), (270, 548)], [(270, 548), (279, 500), (280, 462)])):
        ink_line("Kilt_TassetSideLine%d.L" % i, pts, "S", tcast, mirror=True)
    # tassels
    tube("Kilt_Cord.R", [Q(-52, 204, 428), Q(-52, 207, 470), Q(-52, 208, 503)], 2.4 * K, mat="tassel", m=8, sub=3, mirror=True)
    ball("Kilt_TasselKnot.R", Q(-52, 208, 508), 8 * K, 8 * K, 7 * K, "tassel", m=14, rows=8, mirror=True)
    rings = []
    for row, r in ((513, 6.5), (520, 8.5), (545, 10.5), (572, 12), (577, 11)):
        pts = []
        for k in range(20):
            a = 2 * math.pi * k / 20
            rr = r * (1.0 if k % 2 else 0.86) * K
            pts.append(Q(-52, 208, row) + X * (rr * math.cos(a)) + Y * (rr * math.sin(a)))
        rings.append(pts)
    loft("Kilt_Tassel.R", rings, "tassel", sharp=25, mirror=True)


# ---------------------------------------------------------------- cape

# The cape's shape: lines hanging from the shoulders to the hem, (dx, s, row) at the top and at the
# hem; the cloth is a smooth surface through them (and their mirror images). A: the front edge,
# M: the middle of the side panel, B: the outer corner (a wing swept out and back), D, E: folds of
# the back, C: the middle of the back.
CAPE = [
    ((-122, 318, 272), (-150, 277, 648)),      # A
    ((-140, 334, 268), (-226, 352, 716)),      # M
    ((-152, 352, 268), (-272, 441, 652)),      # B
    ((-112, 350, 258), (-170, 396, 746)),      # D
    ((-60, 344, 252), (-102, 380, 768)),       # E
    ((0, 340, 250), (0, 388, 738)),            # C
]
CAPE_SUB = 12


def cape_lines():
    lines = CAPE + [((-a[0], a[1], a[2]), (-b[0], b[1], b[2])) for a, b in reversed(CAPE[:-1])]
    return lines


def cape_fn(u, v):
    lines = cape_lines()
    row_pts = []
    for top, hem in lines:
        f = v ** 0.9
        dx = lerp(top[0], hem[0], f)
        s = lerp(top[1], hem[1], f) + 6 * math.sin(math.pi * v) * (1 if abs(top[0]) > 100 else 0.3)
        row = lerp(top[2], hem[2], v)
        row_pts.append(V((dx, s, row)))
    n = len(row_pts) - 1
    x = min(u * n, n - 1e-9)
    i = int(x)
    t = x - i
    p1, p2 = row_pts[i], row_pts[i + 1]
    p0 = row_pts[i - 1] if i > 0 else p1 + (p1 - p2)
    p3 = row_pts[i + 2] if i + 2 <= n else p2 + (p2 - p1)
    p = 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3)
    # folds all round, deeper toward the hem, and the hem rising and falling with them
    wave = math.sin(u * 2 * math.pi * 11.5)
    out = V((p.x, p.y - 300.0))
    out = out / max(out.length, 1e-6)
    amp = 10.0 * v ** 1.3
    return Q(p.x + out.x * amp * wave, p.y + out.y * amp * wave, p.z + 7.0 * v ** 3 * wave)


def cape_marks(u0=0.13, v0=0.735, r=47.0):
    """Where the triskelions go on the cape's picture, sized to be r pixels across on the cloth."""
    e = 0.004
    du = (cape_fn(u0 + e, v0) - cape_fn(u0 - e, v0)).length / (2 * e)
    dv = (cape_fn(u0, v0 + e) - cape_fn(u0, v0 - e)).length / (2 * e)
    ru, rv = r * K / du, r * K / dv
    return [(u0, v0, ru, rv, 1), (1 - u0, v0, ru, rv, -1)]


def cape():
    sheet("Cape", cape_fn, 200, 44, "cape", thick=0.006, back="lining", sharp=60)
    # clasp at the back of the neck, brooches on the shoulders
    tube("Cape_Clasp", [Q(-44, 318, 246), Q(-30, 338, 243), Q(0, 346, 242), Q(30, 338, 243), Q(44, 318, 246)], 5 * K, 7 * K, mat="gold",
         m=8, n=3.0, sub=4, up=Z)
    for sgn, s in ((-1, "R"), (1, "L")):
        c = Q(sgn * 152, 362, 330)
        nrm = V((sgn * 0.93, 0.34, 0.12)).normalized()
        tube("Cape_Brooch." + s, [c - nrm * 0.004, c + nrm * 0.012], 13 * K, 30 * K, mat="gold", m=28, up=Z, bevel=0.003)
        tube("Cape_BroochGem." + s, [c + nrm * 0.010, c + nrm * 0.017], 7 * K, 20 * K, mat="cyan", m=20, up=Z, bevel=0.004, ink=0.5)


# ---------------------------------------------------------------- stage, renders

def stage():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = True          # (the renders are put on the sheet's purple by tools/compare.py)
    w = bpy.data.worlds.new("TRI_World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (*kit.lin("#a603ee"), 1)
    sc.world = w
    root = bpy.data.objects.new("TRI_Root", None)
    root.empty_display_size = 0.3
    kit.coll().objects.link(root)
    for ob in kit.coll().objects:
        if ob is not root:
            ob.parent = root
    zc = (kit.GY - 512.0) * K
    cams = (("TRI_CamFront", (0, -8, zc), (math.pi / 2, 0, 0), 1000, 1024 * K),
            ("TRI_CamLeft", (8, (290 - kit.SX) * K, zc), (math.pi / 2, 0, math.pi / 2), 520, 1024 * K),
            ("TRI_CamBack", (0, 8, zc), (math.pi / 2, 0, math.pi), 1000, 1024 * K),
            ("TRI_CamThreeQuarter", (5.2, -6.0, zc + 1.6), None, 1000, 1024 * K * 1.12),
            ("TRI_CamAnim", (5.6, -5.2, zc + 1.9), None, 640, 4.3))
    for name, loc, rot, wpx, scale in cams:
        cd = bpy.data.cameras.new(name)
        cd.type = "ORTHO"
        cd.ortho_scale = scale
        cam = bpy.data.objects.new(name, cd)
        cam.location = loc
        if rot is None:
            tgt = V((0, -0.75, zc - 0.25)) if name == "TRI_CamAnim" else V((0, 0.1, zc - 0.05))
            cam.rotation_euler = (tgt - V(loc)).to_track_quat("-Z", "Y").to_euler()
        else:
            cam.rotation_euler = rot
        cam["res"] = (wpx, 512 if name == "TRI_CamAnim" else 1024)
        kit.coll().objects.link(cam)
        cam.parent = root
    sc.camera = bpy.data.objects["TRI_CamFront"]


def renders(names=("front", "left", "three_quarter", "back")):
    sc = bpy.context.scene
    cams = {"front": "TRI_CamFront", "left": "TRI_CamLeft", "back": "TRI_CamBack", "three_quarter": "TRI_CamThreeQuarter"}
    for name in names:
        ob = bpy.data.objects[cams[name]]
        sc.camera = ob
        sc.render.resolution_x, sc.render.resolution_y = ob["res"]
        sc.render.filepath = os.path.join(HERE, "renders", name + ".png")
        bpy.ops.render.render(write_still=True)
    sc.camera = bpy.data.objects["TRI_CamFront"]
    sc.render.resolution_x, sc.render.resolution_y = bpy.data.objects["TRI_CamFront"]["res"]


def animation_frames(arm):
    """Stills of each animation (renders/anim/<action>_<frame>.png; tools/sheet.py tiles them)."""
    import rig
    sc = bpy.context.scene
    cam = bpy.data.objects["TRI_CamAnim"]
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = cam["res"]
    shots = {"TRI_Walk": range(1, 33, 4), "TRI_Punch": (1, 4, 7, 9, 11, 13, 18, 24), "TRI_Die": (1, 5, 10, 14, 18, 21, 24, 26, 29, 31, 34, 48)}
    for name, frames in shots.items():
        rig.use_action(arm, name)
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(HERE, "renders", "anim", "%s_%02d.png" % (name, f))
            bpy.ops.render.render(write_still=True)
    rig.use_action(arm, "TRI_Walk")
    sc.camera = bpy.data.objects["TRI_CamFront"]
    sc.render.resolution_x, sc.render.resolution_y = bpy.data.objects["TRI_CamFront"]["res"]


PARTS = {"head": head, "torso": torso, "shoulders": shoulders, "arms": arms, "legs": legs, "kilt": kilt, "cape": cape}


def build(only=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials(cape_marks())
    for name, fn in PARTS.items():
        if only is None or name in only:
            fn()
    stage()


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = args[args.index("only") + 1].split(",") if "only" in args else None
    build(only)
    if only is None:
        import rig
        arm = rig.rig_and_animate()
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "tricera_android.blend"))
        arm.data.pose_position = "REST"            # (the views that are compared with the sheet: the T-pose)
        renders()
        arm.data.pose_position = "POSE"
        if "noanim" not in args:
            animation_frames(arm)
    else:
        out = args[args.index("out") + 1] if "out" in args else os.path.join(HERE, "renders")
        sc = bpy.context.scene
        for name, cam in (("front", "TRI_CamFront"), ("left", "TRI_CamLeft"), ("three_quarter", "TRI_CamThreeQuarter")):
            ob = bpy.data.objects[cam]
            sc.camera = ob
            sc.render.resolution_x, sc.render.resolution_y = ob["res"]
            sc.render.filepath = os.path.join(out, "part_" + name + ".png")
            bpy.ops.render.render(write_still=True)
