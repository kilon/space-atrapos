"""The spaceship of reference/reference.png, modelled part by part.

  blender -b --factory-startup --python external/blender/spaceship/build_ship.py [-- draft]
Saves spaceship.blend and renders/view.png: the ship from the reference picture's camera (worked out
by tools/camera.py from the picture's two lift fans, camera.json). tools/compare.py puts the render
beside the picture. "draft" renders quicker and rougher.

The ship's frame: x forward, y to port, z up, metres, the origin midway between the lift fans, level
with their rims. Its sizes were read off the picture with that camera (tools/camera.py at / rectify).
Everything is in the collection "Spaceship", children of the empty SHIP_Root; port-side parts are
named *.P and have a starboard twin *.S. Nothing of the picture is in the model."""
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shipkit as kit  # noqa: E402
from shipkit import M, box, prism, skin, lathe, cyl, mesh, greebles, decal  # noqa: E402

V = Vector
FAN_Y, FAN_R = 7.84, 2.6


# ---------------------------------------------------------------- painted marks

def tex_emblem(n=1024):
    """The hull's emblem: a ring round three spirals joined at the middle (white = paint)."""
    m = np.zeros((n, n), np.float32)
    c = n / 2
    ring = [(c + 0.445 * n * math.cos(a), c + 0.445 * n * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 200)]
    kit.stroke_mask(n, n, ring, 0.075 * n, m)
    for k in range(3):
        a = math.radians(-90 + 120 * k)
        ox, oy = c + 0.215 * n * math.cos(a), c + 0.215 * n * math.sin(a)
        sp = kit.spiral(ox, oy, 0.185 * n, 0.03 * n, a + math.pi + 0.4, 1.45, 90)
        kit.stroke_mask(n, n, [(c, c)] + sp, 0.062 * n, m)
    return kit.image("SHIP_emblem", m)


def tex_waves(w=2048, h=360):
    """The wing's leading-edge mark: a band of paint along the bottom rising into curling waves."""
    m = np.zeros((h, w), np.float32)
    m[int(h * 0.62):, :int(w * 0.84)] = 1.0
    m[:, :int(w * 0.05)] = 1.0
    n = 4
    x0, x1 = 0.10 * w, 0.80 * w
    for k in range(n):
        cx = x0 + (x1 - x0) * (k + 0.55) / n
        cy = h * 0.40
        sp = kit.spiral(cx, cy, 0.06 * h, 0.33 * h, math.pi, -1.2, 80)       # (out from the middle, ending low on the left)
        tail = [(cx - 0.62 * h, h * 0.70), (cx - 1.1 * h, h * 0.80)]
        kit.stroke_mask(w, h, sp + tail, 0.20 * h, m)
    return kit.image("SHIP_waves", m)


def materials():
    a = kit.mat_armour
    M.update({
        "white": a("SHIP_White", "#c4bcb2"),
        "red": a("SHIP_Red", "#9c1018", dark="#2a1012", tint=0.22),
        "grey": a("SHIP_Grey", "#8a857f", rough=0.5),
        "hull": a("SHIP_Hull", "#4a4744", rough=0.45, metal=0.5, tint=0.25),
        "dark": a("SHIP_Dark", "#25272c", panel=(1.6, 2.2, 2.2), metal=0.8, rough=0.48, chips=0.4, tint=0.4),
        "black": kit.mat_metal("SHIP_Black", "#101114", rough=0.55, metal=0.6),
        "gold": kit.mat_metal("SHIP_Gold", "#e2a038", rough=0.2),
        "yellow": a("SHIP_Yellow", "#d2972c", metal=0.4, rough=0.38, tint=0.2),
        "steel": kit.mat_metal("SHIP_Steel", "#7b7f8a", rough=0.32),
        "glass": kit.mat_glass("SHIP_Glass"),
        "lamp": kit.mat_glow("SHIP_Lamp", "#ff5a08", 4.0),
        "cabin": kit.mat_glow("SHIP_CabinLamp", "#ff6a10", 3.0),
        "nozzle": kit.mat_glow("SHIP_Nozzle", "#4f9cff", 8.0),
        "emblem": kit.mat_decal("SHIP_EmblemPaint", tex_emblem(), "#9c1018"),
        "waves": kit.mat_decal("SHIP_WavePaint", tex_waves(), "#9c1018"),
    })


# ---------------------------------------------------------------- fuselage

# stations: x, the top deck's height and half width, the shoulder (y, z), the side's lower edge (y, z),
# the chine (y, z), the bottom's half width and height
FUS = [
    (20.5, -0.55, 0.30, 0.50, -0.80, 0.50, -1.00, 0.40, -1.40, 0.20, -1.50),
    (18.7, 0.20, 0.90, 1.50, -0.50, 1.55, -0.90, 1.25, -2.00, 0.70, -2.30),
    (16.0, 0.75, 1.30, 2.00, -0.10, 2.10, -0.60, 1.90, -2.60, 1.10, -3.00),
    (13.4, 1.25, 1.40, 2.20, 0.45, 2.35, -0.10, 2.50, -2.90, 1.50, -3.50),
    (12.0, 2.45, 0.90, 2.10, 1.45, 2.30, 1.05, 2.90, -1.80, 1.70, -3.70),
    (9.0, 2.25, 1.20, 2.80, 1.05, 3.00, 0.70, 3.20, -1.70, 1.85, -3.85),
    (5.5, 2.00, 1.50, 3.40, 0.70, 3.60, 0.40, 3.30, -1.70, 1.90, -3.90),
    (-6.0, 1.60, 1.40, 3.20, 0.50, 3.40, 0.20, 3.10, -1.60, 1.80, -3.60),
    (-12.0, 1.30, 1.20, 2.60, 0.40, 2.80, 0.10, 2.50, -1.40, 1.40, -3.00),
    (-16.5, 0.90, 0.90, 1.80, 0.20, 2.00, -0.10, 1.70, -1.20, 0.90, -2.30),
]
SEGS = [-16.5, -14.5, -12.5, -10.5, -8.5, -6.5, -4.5, -2.5, -0.5, 1.5, 3.5, 5.5, 7.5, 9.5, 12.0, 13.4, 14.8, 16.3, 17.6, 18.7, 19.7, 20.5]


def fus(x):
    """The fuselage's half section at x: (y, z) from the top's middle round the port side to the bottom's middle."""
    for a, b in zip(FUS, FUS[1:]):
        if b[0] <= x <= a[0]:
            t = (x - a[0]) / (b[0] - a[0])
            s = [p + (q - p) * t for p, q in zip(a, b)]
            return [(0.0, s[1]), (s[2], s[1]), (s[3], s[4]), (s[5], s[6]), (s[7], s[8]), (s[9], s[10]), (0.0, s[10])]
    raise ValueError(x)


def fus_pt(x, k, t=0.0, side=1):
    """A point on facet k of the fuselage at x (t = 0 at the facet's upper edge .. 1 at its lower)."""
    p = fus(x)
    return V((x, side * (p[k][0] + (p[k + 1][0] - p[k][0]) * t), p[k][1] + (p[k + 1][1] - p[k][1]) * t))


def plate_paint(x, k):
    """What covers facet k of the fuselage about x: a list of (from, to, paint) down the facet
    (0 = its upper edge, 1 = its lower); nothing where the machinery shows."""
    if x > 19.7:
        return [(0, 1, "red")]
    if k == 0:
        return [] if 12.0 < x < 18.7 else [(0, 1, "white")]          # (the cockpit)
    if k == 1:
        return [(0, 1, "red" if 1.5 < x < 3.5 else "white")]
    if k == 2:
        return [(0, 1, "white")]
    if k == 3:                                                           # the side: a trench of machinery amidships
        if x > 13.4:
            return [(0, 0.6, "white"), (0.6, 1, "red")]
        if x > 9.5:
            return [(0, 0.72, "red")]
        return []
    return [(0, 1, "hull")]


def fuselage():
    rings = []
    for x in [s[0] for s in FUS]:
        h = fus(x)
        if x < 12.5:                                    # the trench is cut well into the side
            h[3], h[4] = (h[3][0] - 0.55, h[3][1]), (h[4][0] - 0.45, h[4][1])
        c = (h[0][1] + h[-1][1]) / 2
        full = h + [(-y, z) for y, z in reversed(h[1:-1])]
        rings.append([V((x, y * 0.96, c + (z - c) * 0.96)) for y, z in full])
    skin("Fuselage_Core", rings, "dark")
    groups = {}
    for xa, xb in zip(SEGS, SEGS[1:]):
        for k in range(6):
            for t0, t1, paint in plate_paint((xa + xb) / 2, k):
                q = [fus_pt(xa, k, t0), fus_pt(xb, k, t0), fus_pt(xb, k, t1), fus_pt(xa, k, t1)]
                groups.setdefault(paint, []).append(kit.quad_plate(q, 0.16 if k < 3 else 0.10, 0.035))
    for paint, parts in groups.items():
        vs, fs = kit.merge(parts)
        mesh("Fuselage_Plates_%s.P" % paint, vs, fs, paint, bevel=0.025, mirror=True)
    # the machinery in the side trench, with lamps
    for i, (xa, xb) in enumerate(zip(SEGS, SEGS[1:])):
        if not plate_paint((xa + xb) / 2, 3) and xa >= -8.5:
            o = fus_pt(xa, 3, 0.05) - V((0, 0.5, 0))
            greebles("Fuselage_Trench%02d.P" % i, o, fus_pt(xb, 3, 0.05) - V((0, 0.5, 0)) - o, fus_pt(xa, 3, 0.95) - V((0, 0.45, 0)) - o, 22, 100 + i,
                     size=(0.18, 0.8), height=(0.08, 0.5), lamps=2 if i % 2 == 0 else 0, mirror=True, n=(0, 1, 0.05))
    # lamp strips low on the side, a pod with lamps under the shoulder
    for i, (x0, x1, k, t) in enumerate(((3.8, 5.6, 4, 0.12), (-1.0, 0.6, 4, 0.12), (10.6, 12.4, 4, 0.2), (15.0, 16.6, 4, 0.2), (7.4, 8.6, 4, 0.5))):
        a, b = fus_pt(x0, k, t), fus_pt(x1, k, t)
        out, up = V((0, 0.16, -0.05)), V((0, 0.03, 0.11))
        mesh("Fuselage_LampStrip%d.P" % i, [a - up, b - up, b + up, a + up, a - up + out, b - up + out, b + up + out, a + up + out],
             [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "lamp", mirror=True)
    box("Fuselage_SidePod.P", (12.2, 2.3, -1.9), (13.9, 3.1, -0.7), "grey", bevel=0.07, mirror=True)
    box("Fuselage_SidePodLamp.P", (13.8, 2.55, -1.6), (13.97, 2.95, -1.0), "lamp", bevel=0.0, mirror=True)
    box("Fuselage_GoldPanel.P", (7.9, 2.7, -0.5), (9.3, 2.82, 0.2), "yellow", bevel=0.04, mirror=True)
    # the nose's intake
    box("Nose_Intake", (20.25, -0.3, -1.3), (20.62, 0.3, -0.75), "black", bevel=0.03)
    # decks stepping up along the spine, blocks on the shoulders
    box("Deck_Low", (-5.5, -1.75, 1.55), (3.6, 1.75, 2.38), "white", bevel=0.05)
    box("Deck_High", (-3.6, -1.1, 2.38), (1.6, 1.1, 2.72), "grey", bevel=0.05)
    greebles("Deck_Machinery", (-5.2, -1.0, 2.38), (1.5, 0, 0), (0, 2.0, 0), 12, 7, size=(0.2, 0.7), height=(0.06, 0.3))
    greebles("Deck_MachineryFore", (1.7, -1.0, 2.38), (1.7, 0, 0), (0, 2.0, 0), 10, 8, size=(0.2, 0.6), height=(0.05, 0.25))
    for i, (x0, x1) in enumerate(((-5.4, -3.2), (-2.6, 0.2), (0.9, 3.4), (4.0, 5.6), (9.8, 11.6))):          # hatches and machinery beside the decks
        greebles("Deck_Side%d.P" % i, (x0, 1.45, fus(x0)[0][1] + 0.16), (x1 - x0, 0, 0), (0, 0.6, -0.24), 8, 60 + i, size=(0.2, 0.6), height=(0.05, 0.2),
                 mirror=True, n=(0, 0.4, 1))
    box("Shoulder_Block.P", (3.7, 2.0, 0.75), (5.3, 3.75, 1.75), "white", bevel=0.08, mirror=True)
    for i in range(4):                                   # its louvres
        box("Shoulder_Louvre%d.P" % i, (3.95 + i * 0.32, 3.72, 0.95), (4.1 + i * 0.32, 3.8, 1.55), "black", bevel=0.0, mirror=True)
    box("Shoulder_LampBox.P", (2.0, 3.45, -0.15), (3.1, 4.5, 0.75), "white", bevel=0.07, mirror=True)
    for i in range(5):
        box("Shoulder_Lamp%d.P" % i, (2.2, 4.48, 0.0 + i * 0.13), (2.9, 4.54, 0.08 + i * 0.13), "lamp", bevel=0.0, mirror=True)
    # the emblem on each shoulder
    e0, e1 = 6.4, 9.2
    decal("Emblem.S", [fus_pt(e0, 1, 0.95, -1), fus_pt(e1, 1, 0.95, -1), fus_pt(e1, 1, 0.05, -1), fus_pt(e0, 1, 0.05, -1)], "emblem", lift=0.185)
    decal("Emblem.P", [fus_pt(e1, 1, 0.95, 1), fus_pt(e0, 1, 0.95, 1), fus_pt(e0, 1, 0.05, 1), fus_pt(e1, 1, 0.05, 1)], "emblem", lift=0.185)


def cockpit():
    st = [(13.45, 1.30, 1.22, 2.08, 0.72), (14.8, 1.32, 1.02, 1.98, 0.76), (16.3, 1.25, 0.72, 1.58, 0.66), (17.6, 1.05, 0.44, 1.06, 0.46),
          (18.7, 0.78, 0.2, 0.46, 0.2)]
    rings = [[V((x, -bh, bz)), V((x, -th, tz)), V((x, th, tz)), V((x, bh, bz)), V((x, bh * 0.9, bz - 0.35)), V((x, -bh * 0.9, bz - 0.35))]
             for x, bh, bz, tz, th in st]
    skin("Cockpit_Glass", rings, "glass")
    bars = []
    for r in rings:                                   # hoops
        for a, b in zip(r[:3], r[1:4]):
            bars.append((a, b))
    for j in range(4):                                # rails
        for r0, r1 in zip(rings, rings[1:]):
            bars.append((r0[j], r1[j]))
    for i, (a, b) in enumerate(bars):
        cyl("Cockpit_Frame%02d" % i, a, b, 0.055, mat="gold", seg=8)
    box("Cockpit_Floor", (13.5, -1.15, 0.2), (18.3, 1.15, 0.5), "black", bevel=0.0)
    rng = random.Random(3)
    for i in range(9):
        x, y = rng.uniform(13.8, 17.6), rng.uniform(-0.9, 0.9)
        s = rng.uniform(0.08, 0.2)
        box("Cockpit_Lamp%d" % i, (x, y, 0.5), (x + s * 2, y + s, 0.5 + rng.uniform(0.1, 0.5)), "cabin", bevel=0.0)
    box("Cockpit_Seat.P", (15.0, 0.25, 0.5), (15.7, 0.85, 1.35), "black", bevel=0.05, mirror=True)
    # the gold frame block behind the canopy, the gold lip at its front
    box("Cockpit_Block", (11.9, -1.75, 0.6), (13.5, 1.75, 2.35), "yellow", bevel=0.07)
    box("Cockpit_BlockInset.P", (12.1, 1.68, 0.8), (13.3, 1.8, 2.1), "dark", bevel=0.02, mirror=True)
    greebles("Cockpit_BlockMachinery.P", (12.15, 1.8, 0.85), (1.1, 0, 0), (0, 0, 1.2), 12, 21, size=(0.12, 0.4), height=(0.03, 0.12), mirror=True, n=(0, 1, 0))
    box("Cockpit_BlockTop", (11.95, -1.2, 2.35), (13.3, 1.2, 2.5), "white", bevel=0.04)
    prism("Cockpit_Lip", [(18.55, -0.85), (19.15, -0.6), (19.15, 0.6), (18.55, 0.85)], 0.0, 0.3, "z", "gold", bevel=0.04)


# ---------------------------------------------------------------- wings, lift fans

# the port wing seen from above (x, y): its top face, its widest outline (the leading edge's nose), its underside
WING_TOP = [(4.9, 3.3), (4.6, 8.0), (0.3, 15.1), (-0.9, 15.1), (-5.5, 7.0), (-7.6, 3.3)]
WING = [(5.25, 3.3), (4.95, 8.0), (0.75, 15.35), (-0.9, 15.6), (-5.6, 7.2), (-7.7, 3.3)]
WING_BOT = [(5.0, 3.3), (4.7, 8.0), (0.5, 15.1), (-0.8, 15.3), (-5.4, 7.2), (-7.5, 3.3)]
Z_TOP, Z_MID, Z_LIP, Z_BOT = -0.30, -1.85, -2.10, -2.45


def wings():
    rings = [[V((x, y, Z_TOP)) for x, y in WING_TOP], [V((x, y, Z_MID)) for x, y in WING], [V((x, y, Z_LIP)) for x, y in WING],
             [V((x, y, Z_BOT)) for x, y in WING_BOT]]
    w = skin("Wing.P", rings, "white", bevel=0.03)
    kit.cut_hole(w, (0.0, FAN_Y), FAN_R + 0.42, -3, 2)
    kit.mirror_obj(w)
    # the red band along the trailing edge
    prism("Wing_Band.P", [(-0.9, 15.1), (-5.5, 7.0), (-4.4, 6.9), (0.0, 14.5)], Z_TOP - 0.02, Z_TOP + 0.05, "z", "red", bevel=0.015, mirror=True)
    prism("Wing_BandRoot.P", [(-5.5, 7.0), (-7.6, 3.3), (-6.5, 3.3), (-4.4, 6.9)], Z_TOP - 0.02, Z_TOP + 0.05, "z", "red", bevel=0.015, mirror=True)
    # raised plates on the wing's top, outboard and aft of the fan
    prism("Wing_PlateOuter.P", [(2.2, 11.4), (0.4, 14.6), (-0.6, 14.4), (-2.6, 11.0), (-0.4, 11.0)], Z_TOP, Z_TOP + 0.16, "z", "white", bevel=0.04, mirror=True)
    prism("Wing_PlateAft.P", [(-3.3, 5.0), (-3.4, 9.2), (-4.6, 7.0), (-5.8, 4.6)], Z_TOP, Z_TOP + 0.14, "z", "white", bevel=0.04, mirror=True)
    # the wing root: blocks between the hull and the fan, machinery in the gaps
    box("Wing_RootFore.P", (2.9, 4.6, -1.6), (4.8, 6.3, 0.15), "white", bevel=0.1, mirror=True)
    box("Wing_RootMid.P", (-2.4, 3.3, -0.6), (1.9, 4.9, 0.15), "grey", bevel=0.08, mirror=True)
    box("Wing_RootAft.P", (-6.8, 3.3, -0.6), (-2.9, 4.9, 0.3), "white", bevel=0.08, mirror=True)
    greebles("Wing_RootMachinery.P", (-2.3, 3.4, 0.15), (4.1, 0, 0), (0, 1.4, 0), 24, 31, size=(0.2, 0.8), height=(0.05, 0.3), lamps=2, mirror=True)
    # along the leading edge's face: a dark slot and lamps
    A, B = V((4.95, 8.0, 0)), V((0.75, 15.35, 0))
    f = V((0.87, 0.5, 0)) * 0.03
    for i, (t0, t1, paint) in enumerate(((0.05, 0.70, "black"), (0.76, 0.86, "lamp"), (0.90, 0.97, "lamp"))):
        a, b = A.lerp(B, t0) + f, A.lerp(B, t1) + f
        mesh("Wing_Slot%d.P" % i, [a + V((0, 0, Z_LIP + 0.02)), b + V((0, 0, Z_LIP + 0.02)), b + V((0, 0, Z_MID - 0.03)), a + V((0, 0, Z_MID - 0.03))],
             [(0, 1, 2, 3)], paint, mirror=True, recalc=False)
    # the wave mark on the leading edge's slope
    for side, tag in ((-1, "S"), (1, "P")):
        A0, B0 = V((4.95, side * 8.0, Z_MID)), V((0.75, side * 15.35, Z_MID))
        A1, B1 = V((4.6, side * 8.0, Z_TOP)), V((0.3, side * 15.1, Z_TOP))
        q = [B0, A0, A1, B1] if side < 0 else [A0, B0, B1, A1]
        q = [q[0].lerp(q[3], 0.02), q[1].lerp(q[2], 0.02), q[1].lerp(q[2], 0.98), q[0].lerp(q[3], 0.98)]
        decal("Wing_Waves." + tag, q, "waves", lift=0.04)


def fans():
    c = (0.0, FAN_Y, 0.0)
    lathe("Fan_Ring.P", [(2.25, -0.55), (2.33, -0.06), (2.46, 0.0), (2.62, 0.0), (2.74, -0.09), (2.97, -0.42), (3.02, -0.62), (2.25, -0.62)],
          c, "z", 72, "gold", loop=True, mirror=True)
    lathe("Fan_Skirt.P", [(3.02, -0.62), (3.06, -1.3), (2.2, -1.3), (2.2, -0.62)], c, "z", 48, "steel", loop=True, mirror=True)
    lathe("Fan_Bowl.P", [(0.02, -0.8), (2.26, -0.8), (2.26, -0.5)], c, "z", 48, "black", mirror=True)
    for i, (r, t) in enumerate(((1.45, 0.045), (1.0, 0.04), (1.9, 0.03))):
        lathe("Fan_Hoop%d.P" % i, [(r - t, -0.62), (r + t, -0.62), (r + t, -0.72), (r - t, -0.72)], c, "z", 48, "steel", loop=True, mirror=True)
    parts = []
    for k in range(30):                                # the stator vanes between the bowl's wall and the middle hoop
        a = 2 * math.pi * k / 30
        d, s = V((math.cos(a), math.sin(a), 0)), V((-math.sin(a), math.cos(a), 0))
        p0, p1 = V(c) + d * 1.5, V(c) + d * 2.24
        vs = [p0 - s * 0.02 + V((0, 0, -0.78)), p1 - s * 0.03 + V((0, 0, -0.78)), p1 + s * 0.10 + V((0, 0, -0.42)), p0 + s * 0.07 + V((0, 0, -0.56))]
        parts.append((vs + [p + s * 0.025 for p in vs], [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]))
    for k in range(12):                                # spokes to the hub
        a = 2 * math.pi * (k + 0.5) / 12
        d, s = V((math.cos(a), math.sin(a), 0)), V((-math.sin(a), math.cos(a), 0))
        p0, p1 = V(c) + d * 0.5, V(c) + d * 1.45
        vs = [p0 - s * 0.03 + V((0, 0, -0.74)), p1 - s * 0.03 + V((0, 0, -0.74)), p1 + s * 0.03 + V((0, 0, -0.74)), p0 + s * 0.03 + V((0, 0, -0.74))]
        parts.append((vs + [p + V((0, 0, 0.07)) for p in vs], [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]))
    vs, fs = kit.merge(parts)
    mesh("Fan_Vanes.P", vs, fs, "steel", mirror=True)
    lathe("Fan_Hub.P", [(0.01, -0.04), (0.2, -0.04), (0.3, -0.1), (0.4, -0.16), (0.47, -0.42), (0.62, -0.5), (0.62, -0.78), (0.01, -0.78)],
          c, "z", 32, "gold", mirror=True)
    lathe("Fan_HubEye.P", [(0.01, -0.02), (0.18, -0.02), (0.18, -0.06), (0.01, -0.06)], c, "z", 20, "black", mirror=True)


# ---------------------------------------------------------------- engines, tail

def banded(name, outline, cuts, paints, **kw):
    """A housing with bands of paint across it: the outline (y, z) cut into lengths along x."""
    for i, (x0, x1, paint) in enumerate(zip(cuts, cuts[1:], paints)):
        prism("%s%d.P" % (name, i), outline, x0 + 0.02, x1 - 0.02, "x", paint, bevel=0.05, mirror=True, **kw)


def engine(name, y, z, r, x0, x1, flame):
    """A drive: its dark barrel from x0 back to the nozzle at x1, a glowing throat, the flame."""
    o = (0.0, y, z)
    lathe(name + "_Barrel.P", [(r * 0.98, x0), (r, x0 - 0.5), (r * 1.06, x0 - 0.6), (r * 1.06, x0 - 1.0), (r * 0.92, x0 - 1.1),
                               (r * 0.95, x1 + 0.5), (r * 0.86, x1), (r * 0.72, x1), (r * 0.66, x1 + 0.9), (0.02, x1 + 0.9)],
          o, "x", 40, "dark", mirror=True)
    lathe(name + "_Throat.P", [(0.02, x1 + 0.88), (r * 0.64, x1 + 0.88)], o, "x", 32, "nozzle", mirror=True)
    for k in range(10):                                 # ribs round the barrel
        a = 2 * math.pi * k / 10
        d = V((0, math.cos(a), math.sin(a)))
        s = V((0, -math.sin(a), math.cos(a)))
        p = V((x0 - 1.2, y, z)) + d * (r * 0.93)
        q = V((x1 + 0.45, y, z)) + d * (r * 0.95)
        vs = [p - s * 0.09, q - s * 0.09, q + s * 0.09, p + s * 0.09]
        mesh("%s_Rib%d.P" % (name, k), vs + [v + d * 0.1 for v in vs], [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
             "black", mirror=True)
    f = lathe(name + "_Flame.P", [(r * 0.66, x1 + 0.3), (r * 0.72, x1 - 0.4), (r * 0.5, x1 - flame * 0.5), (0.03, x1 - flame)], o, "x", 32,
              "flame_" + name, mirror=True)
    for ob in (f, bpy.data.objects[kit._twin(f.name)]):
        ob.visible_shadow = False


def engines():
    banded("Engine_UpperHousing", [(2.3, 1.15), (4.9, 1.15), (6.1, 0.25), (6.1, -1.9), (2.3, -1.9)],
           [-17.0, -16.2, -15.0, -13.4, -10.8, -8.6], ["white", "red", "white", "red", "white"])
    M["flame_Engine_Upper"] = kit.mat_flame("SHIP_FlameUpper", -19.2, -23.2)
    engine("Engine_Upper", 4.2, -0.75, 1.25, -17.0, -19.3, 3.9)
    banded("Engine_LowerHousing", [(5.0, -2.0), (7.4, -2.0), (7.9, -2.6), (7.9, -4.2), (7.3, -4.75), (5.0, -4.75)],
           [-15.6, -14.6, -12.4, -11.2, -8.8], ["red", "white", "red", "white"])
    M["flame_Engine_Lower"] = kit.mat_flame("SHIP_FlameLower", -17.5, -21.6)
    engine("Engine_Lower", 6.4, -3.35, 1.45, -15.6, -17.6, 4.0)
    box("Engine_Pylon.P", (-15.0, 5.0, -2.15), (-9.2, 6.1, -1.85), "dark", bevel=0.04, mirror=True)
    box("Engine_Fairing.P", (-8.7, 2.6, -1.7), (-6.4, 6.0, 0.6), "grey", bevel=0.1, mirror=True)
    greebles("Engine_Machinery.P", (-16.8, 2.4, 1.15), (8.0, 0, 0), (0, 2.4, 0), 26, 41, size=(0.2, 0.9), height=(0.05, 0.28), mirror=True)
    # the stern between the housings
    box("Stern_Block", (-16.6, -2.25, -1.6), (-8.0, 2.25, 0.95), "dark", bevel=0.08)
    greebles("Stern_Machinery", (-16.4, -2.2, 0.95), (8.2, 0, 0), (0, 4.4, 0), 60, 51, size=(0.2, 1.0), height=(0.06, 0.5), lamps=4)
    box("Stern_GoldBox", (-8.4, -2.5, 1.2), (-6.2, -0.7, 2.05), "yellow", bevel=0.07)
    box("Stern_Plate.S", (-12.6, -2.4, 0.95), (-8.8, -0.5, 1.5), "grey", bevel=0.06)
    box("Stern_Plate.P", (-12.6, 0.5, 0.95), (-8.8, 2.4, 1.5), "grey", bevel=0.06)


def tail():
    prism("Fin", [(-6.8, 1.45), (-11.8, 3.0), (-13.2, 3.0), (-18.3, 2.35), (-18.3, 1.95), (-14.5, 1.9), (-13.2, 1.2), (-10.5, 1.2)],
          -0.17, 0.17, "y", "white", bevel=0.03)
    prism("Fin_Paint", [(-9.6, 2.32), (-11.8, 3.0), (-13.2, 3.0), (-18.3, 2.35), (-18.3, 1.95), (-14.5, 1.9)], -0.2, 0.2, "y", "red", bevel=0.02)
    prism("Fin_Root", [(-6.4, 1.4), (-8.2, 1.95), (-12.0, 1.7), (-13.6, 1.2)], -0.4, 0.4, "y", "grey", bevel=0.05)
    box("Fin_Bar", (-18.75, -0.95, 2.02), (-16.9, 0.95, 2.28), "red", bevel=0.05)
    cyl("Mast_Aft", (-8.7, 0.0, 1.4), (-8.7, 0.0, 3.3), 0.07, mat="gold", seg=10)
    cyl("Mast_AftTip", (-8.7, 0.0, 3.3), (-8.7, 0.0, 3.8), 0.035, mat="gold", seg=8)
    cyl("Mast_AftCollar", (-8.7, 0.0, 2.2), (-8.7, 0.0, 2.45), 0.13, mat="gold", seg=10)
    cyl("Mast_Wing", (-1.6, 11.3, -0.3), (-1.6, 11.3, 1.5), 0.07, mat="gold", seg=10)
    cyl("Mast_WingTip", (-1.6, 11.3, 1.5), (-1.6, 11.3, 2.05), 0.035, mat="gold", seg=8)
    cyl("Mast_WingCollar", (-1.6, 11.3, 0.5), (-1.6, 11.3, 0.75), 0.13, mat="gold", seg=10)


# ---------------------------------------------------------------- stage

def stage(draft):
    sc = bpy.context.scene
    root = bpy.data.objects.new("SHIP_Root", None)
    root.empty_display_size = 2.0
    kit.coll().objects.link(root)
    for ob in kit.coll().objects:
        if ob is not root:
            ob.parent = root
    with open(os.path.join(HERE, "camera.json")) as fh:
        cam = json.load(fh)
    cd = bpy.data.cameras.new("SHIP_RefCamera")
    cd.lens, cd.sensor_width, cd.sensor_fit = cam["lens"], 36.0, "HORIZONTAL"
    cd.clip_end = 500
    ob = bpy.data.objects.new("SHIP_RefCamera", cd)
    fw, up = V(cam["forward"]), V(cam["up"])
    right = fw.cross(up).normalized()
    ob.matrix_world = Matrix.Translation(V(cam["location"])) @ Matrix((right, up, -fw)).transposed().to_4x4()
    kit.coll().objects.link(ob)
    sc.camera = ob
    sc.render.resolution_x, sc.render.resolution_y = cam["size"]
    sc.render.film_transparent = True
    # light: a warm key from high on the camera's right, a cool fill from the left, an orange glow from below
    def lamp(name, kind, loc, energy, color, size=0.0, at=(0, 0, 0)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy, ld.color = energy, color
        if kind == "SUN":
            ld.angle = math.radians(6)
        elif size:
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        lo.rotation_euler = (V(at) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        kit.coll().objects.link(lo)
    lamp("SHIP_Key", "SUN", (30, -22, 34), 2.3, (1.0, 0.96, 0.9))
    lamp("SHIP_Fill", "SUN", (-10, -40, 8), 0.3, (0.75, 0.85, 1.0))
    lamp("SHIP_Glow", "AREA", (4, -6, -14), 1800, (1.0, 0.42, 0.1), size=26, at=(4, -1, 0))
    w = bpy.data.worlds.new("SHIP_World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.035, 0.05, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = w
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24 if draft else 160
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                for d in prefs.devices:
                    d.use = True
                sc.cycles.device = "GPU"
                break
            except Exception:
                continue
    except Exception as ex:
        print("rendering on the CPU:", ex)
    for vt in ("Standard",):
        try:
            sc.view_settings.view_transform = vt
            break
        except Exception:
            continue


def build(draft=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials()
    fuselage()
    cockpit()
    wings()
    fans()
    engines()
    tail()
    stage(draft)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build("draft" in args)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "spaceship.blend"))
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(HERE, "renders", "view.png")
    bpy.ops.render.render(write_still=True)
