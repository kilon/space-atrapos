"""The automaton (you on foot), rebuilt from its reference sheets
(external/images/player_on_foot_idle.png / _aim.png): cream ceramic armour
over a dark slate frame - broad wedge pauldrons, a breastplate in two halves
round an orange light, flared greaves, heavy boots - red panels, orange
lights, a smooth helmet over a dark visor, a long cream-and-orange rifle.
Built from the kit's parts, each on one bone of the kit's rig.

The frame (legs / body / arms) is shared: the pirate, Kilon and the Minoan
androids wear it in their own colours (the same material keys). What only the
automaton has - its helmet, its marks, its rifle - is in head(), the "tri"
marks and rifle(). The makers skin / drape / cable (surfaces through rings of
points: cloth, hoods, hat brims, hoses) are here for every skin."""
import math

import bmesh
from mathutils import Vector

import kit
from kit import ball, bone, box, decal, loft, mirror, plate, rot, tube

KNEE_Z = kit.HIP_Z - kit.THIGH
AZ = kit.ANKLE_Z


def materials():
    kit.M.update({
        "armor": kit.mat_toon("AUT_Armor", "#f3e4c8", shade=0.60, hi=0.05, tint=(0.95, 0.88, 0.96)),
        "armor2": kit.mat_toon("AUT_Armor2", "#c9baa8", shade=0.62, tint=(0.93, 0.9, 1.0)),
        "joint": kit.mat_toon("AUT_Joint", "#34384a", shade=0.62),
        "grey": kit.mat_toon("AUT_Grey", "#646a7e", shade=0.66),
        "red": kit.mat_toon("AUT_Red", "#e0241c", shade=0.68, hi=0.06, tint=(0.95, 0.8, 0.9)),
        "red2": kit.mat_toon("AUT_Red2", "#9c1614", shade=0.7),
        "glow": kit.mat_glow("AUT_Glow", "#ff8a14", 1.5),
        "glow_y": kit.mat_glow("AUT_GlowY", "#ffd23a", 1.6),
        "gun": kit.mat_toon("AUT_Gun", "#454a5a", shade=0.62, hi=0.12),
        "gun_o": kit.mat_toon("AUT_GunOrange", "#f29418", shade=0.72),
        "visor": kit.mat_toon("AUT_VisorGunmetal", "#171a26", shade=0.6, hi=0.2),     # (the eyes' dark glass: polished - not "AUT_Gun...", the rifle's names)
        "ink": kit.mat_outline(),
    })


TRI = [(-1.0, 1.0), (1.0, 1.0), (0.0, -0.9)]
MARK = "tri"               # the pauldrons' mark: the automaton's red triangles, or a skin's own (PAULDRON_MARK)
PAULDRON_MARK = [None]


def _scale(pts, sx, sy=None):
    sy = sy if sy is not None else sx
    return [(x * sx, y * sy) for (x, y) in pts]


def dec(*a, **k):
    """A decal on a curved part: cut twice (16 triangles a triangle - the kit's 3 cuts make 64)."""
    k.setdefault("cuts", 2)
    return decal(*a, **k)


# ---------------------------------------------------------------- makers for every skin

def skin(name, rings, mat="armor", closed=True, caps=False, thick=0.0, smooth=True, split=0.0, skip=(), lining=None, inside=None):
    """A surface through rings of points (every ring the same count, in order).
    closed: each ring a loop (caps: its two ends filled) - else a sheet.
    thick: both its sides (cloth, a shell: the game draws front faces only);
    split: edges sharper than this (degrees) stay sharp; skip: (ring, column)
    quads left out (holes, tatters); lining: the material of its other side
    (with thick), the side facing the point `inside`."""
    bm = bmesh.new()
    rows = [[bm.verts.new(Vector(p)) for p in ring] for ring in rings]
    n = len(rows[0])
    for k in range(len(rows) - 1):
        for i in range(n if closed else n - 1):
            if (k, i) in skip:
                continue
            j = (i + 1) % n
            bm.faces.new((rows[k][i], rows[k][j], rows[k + 1][j], rows[k + 1][i]))
    if caps and closed:
        bm.faces.new(rows[0][::-1])
        bm.faces.new(rows[-1])
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    ob = kit.mesh_object(name, bm, [mat] + ([lining] if lining else []), smooth=smooth, outline=0.0)
    if inside is not None:                 # (its faces turned away from the inside)
        c = Vector(inside)
        if sum((p.center - c).dot(p.normal) * p.area for p in ob.data.polygons) < 0:
            ob.data.flip_normals()
    if thick > 0:
        s = ob.modifiers.new("Thick", "SOLIDIFY")
        s.thickness = thick
        s.offset = 0.0
        if lining:
            s.material_offset = 1
    if split > 0:
        e = ob.modifiers.new("Split", "EDGE_SPLIT")
        e.split_angle = math.radians(split)
    return ob


def arc(c, rx, ry, a0, a1, n, z=None):
    """n + 1 points on an ellipse round c (x, y, z): the angles a0..a1 (degrees: 0 = behind, 90 = its left, 180 = in front)."""
    out = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        out.append((c[0] + rx * math.sin(a), c[1] + ry * math.cos(a), c[2] if z is None else z))
    return out


def drape_rings(a0, a1, top, hem, cols=10, rows=6, pleat=0.0, waves=3.0, phase=0.0, flare=1.3, rag=None, t0=0.0, t1=1.0, grow=0.0):
    """The rings of a hanging cloth panel (drape): rows + 1 of cols + 1 points, from the top (or t0) to the hem (or t1)."""
    rings = []
    a0 = a0 if isinstance(a0, tuple) else (a0, a0)        # (an end of the arc: the same all the way down, or (top, hem))
    a1 = a1 if isinstance(a1, tuple) else (a1, a1)
    for k in range(rows + 1):
        t = t0 + (t1 - t0) * k / rows
        f = t ** flare
        cx, cy, rx, ry = (top[i] + (hem[i] - top[i]) * f for i in range(4))
        z = top[4] + (hem[4] - top[4]) * t
        b0 = a0[0] + (a0[1] - a0[0]) * t
        b1 = a1[0] + (a1[1] - a1[0]) * t
        row = []
        for i in range(cols + 1):
            u = i / cols
            a = math.radians(b0 + (b1 - b0) * u)
            w = 1.0 + (pleat * t * math.cos(waves * math.tau * u + phase) + grow) / max(rx, ry)
            zz = z
            if rag and k >= rows - 1 and t1 >= 1.0:
                zz -= rag[i % len(rag)] * (1.0 if k == rows else 0.3)
            row.append((cx + rx * w * math.sin(a), cy + ry * w * math.cos(a), zz))
        rings.append(row)
    return rings


def drape(name, a0, a1, top, hem, mat="coat", cols=10, rows=6, thick=0.014, pleat=0.0, waves=3.0, phase=0.0, flare=1.3,
          rag=None, skip=(), split=0.0, lining=None, t0=0.0, t1=1.0, grow=0.0):
    """A hanging cloth panel: the arc a0..a1 (degrees round the body: 0 = behind,
    90 = its left, 180 = in front; an end may be (at the top, at the hem)) of
    the ellipse top = (cx, cy, rx, ry, z), widening to hem = (cx, cy, rx, ry, z).
    pleat: its folds (m at the hem, `waves` of them); rag: the hem's tatters -
    how much longer each column hangs (m); t0..t1: only that part of its length
    (a band on it, `grow` proud of it); lining: its inner side's material."""
    rings = drape_rings(a0, a1, top, hem, cols, rows, pleat, waves, phase, flare, rag, t0, t1, grow)
    return skin(name, rings, mat, closed=False, thick=thick, split=split, skip=skip, lining=lining,
                inside=(top[0], top[1], (top[4] + hem[4]) * 0.5) if lining else None)


def _spline(pts, steps):
    """Points along the smooth curve through pts (Catmull-Rom)."""
    p = [Vector(q) for q in pts]
    p = [p[0] * 2 - p[1]] + p + [p[-1] * 2 - p[-2]]
    out = []
    for k in range(1, len(p) - 2):
        for s in range(steps):
            t = s / steps
            out.append(0.5 * ((2 * p[k]) + (-p[k - 1] + p[k + 1]) * t + (2 * p[k - 1] - 5 * p[k] + 4 * p[k + 1] - p[k + 2]) * t * t
                              + (-p[k - 1] + 3 * p[k] - 3 * p[k + 1] + p[k + 2]) * t * t * t))
    out.append(p[-2])
    return out


def cable(name, pts, r0, r1=None, mat="joint", seg=8, steps=4, flat=1.0, hint=(0.3, 0.2, 1.0)):
    """A hose along the smooth curve through pts, r0 thick at its start, r1 at
    its end (flat: its section's other half-size, a ribbon's or a strap's)."""
    r1 = r0 if r1 is None else r1
    path = _spline(pts, steps)
    rings = []
    side = None
    for k, c in enumerate(path):
        d = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
        if side is None:
            side = d.cross(Vector(hint))
            if side.length < 1e-4:
                side = d.orthogonal()
        side = (side - d * side.dot(d)).normalized()
        up = d.cross(side)
        r = r0 + (r1 - r0) * k / (len(path) - 1)
        rings.append([tuple(c + side * (math.cos(math.tau * i / seg) * r) + up * (math.sin(math.tau * i / seg) * r * flat)) for i in range(seg)])
    return skin(name, rings, mat, closed=True, caps=True)


# ---------------------------------------------------------------- the frame

def legs(sx, sf):
    hx = kit.HIP_X * sx
    # ---- thigh: a full plate, widest below the hip, a long panel down its outside
    bone("thigh" + sf)
    ball("Hip", (hx, 0, kit.HIP_Z), 0.082, "joint")
    loft("ThighCore", (hx, 0.005, kit.HIP_Z - 0.03), (hx, 0.0, KNEE_Z + 0.02),
         [(0, 0.070, 0.074), (1, 0.048, 0.052)], mat="joint", seg=14)
    th = loft("ThighArmor", (hx + 0.020 * sx, -0.006, kit.HIP_Z - 0.03), (hx + 0.004 * sx, -0.004, KNEE_Z + 0.095),
              [(0, 0.058, 0.068, 3.4), (0.14, 0.078, 0.088, 4.2), (0.36, 0.083, 0.094, 4.2, 0, 0.004), (0.72, 0.070, 0.080, 3.8),
               (1, 0.055, 0.064, 3.2)], cap=0.7)
    plate("ThighPlate", [(0, 0.115), (0.04, 0.085), (0.032, -0.07), (0, -0.10), (-0.032, -0.07), (-0.04, 0.085)],
          (hx + 0.022 * sx, -0.092, 0.80), (0.12 * sx, -1, 0.05), thick=0.02, mat="armor", bevel=0.007)
    tube("HipDisc", (hx + 0.085 * sx, 0.0, kit.HIP_Z - 0.035), (hx + 0.112 * sx, 0.0, kit.HIP_Z - 0.035), 0.05, 0.044, mat="armor2", seg=14)
    tube("HipDiscIn", (hx + 0.108 * sx, 0.0, kit.HIP_Z - 0.035), (hx + 0.118 * sx, 0.0, kit.HIP_Z - 0.035), 0.024, mat="joint", seg=10)
    tube("ThighBand", (hx, -0.004, KNEE_Z + 0.105), (hx, -0.004, KNEE_Z + 0.062), 0.059, 0.054, mat="grey", seg=14)
    side = [(0, 0.125), (0.036, 0.085), (0.03, -0.09), (0, -0.125), (-0.03, -0.09), (-0.036, 0.085)]
    dec("ThighSide", _scale(side, 1.22, 1.12), (hx + 0.09 * sx, -0.02, 0.765), (sx, -0.35, 0), th, mat="joint", outline=0, offset=0.002,
        thick=0.004)
    dec("ThighRed", side, (hx + 0.09 * sx, -0.02, 0.765), (sx, -0.35, 0), th, offset=0.006)
    dec("ThighSlot", [(-0.012, 0.04), (0.012, 0.04), (0.009, -0.04), (-0.009, -0.04)],
        (hx - 0.02 * sx, -0.085, 0.655), (-0.2 * sx, -1, 0), th, mat="joint", outline=0, cuts=1)
    dec("ThighGlow", [(-0.005, 0.022), (0.005, 0.022), (0.005, -0.022), (-0.005, -0.022)],
        (hx - 0.02 * sx, -0.085, 0.645), (-0.2 * sx, -1, 0), th, mat="glow", offset=0.009, outline=0, cuts=1)
    # ---- shin: the knee's cap, a greave swelling at the calf and flaring at the ankle
    bone("shin" + sf)
    ball("Knee", (hx, 0.0, KNEE_Z), 0.058, "joint")
    box("KneeCap", (0.088, 0.05, 0.125), (hx, -0.062, KNEE_Z + 0.006), taper=((0.72, 1.0), (0.6, 0.7)), r=rot(8), bevel=0.014)
    box("KneeLight", (0.014, 0.012, 0.022), (hx, -0.089, KNEE_Z - 0.012), mat="glow", r=rot(8), bevel=0.0)
    tube("KneeBolt", (hx - 0.064, 0, KNEE_Z), (hx + 0.064, 0, KNEE_Z), 0.026, mat="grey")
    loft("ShinCore", (hx, 0.004, KNEE_Z - 0.03), (hx, 0.004, AZ + 0.02), [(0, 0.05, 0.055), (1, 0.04, 0.045)], mat="joint", seg=14)
    sh = loft("Greave", (hx, -0.004, KNEE_Z - 0.075), (hx, 0.002, AZ + 0.04),
              [(0, 0.048, 0.056, 3), (0.16, 0.066, 0.080, 3.2, 0, -0.012), (0.42, 0.070, 0.086, 3.2, 0, -0.016),
               (0.78, 0.055, 0.064, 3, 0, -0.004), (1, 0.064, 0.074, 3.5)], cap=0.6)
    loft("AnkleCuff", (hx, 0.002, AZ + 0.085), (hx, 0.002, AZ + 0.03), [(0, 0.062, 0.071, 3.4), (1, 0.071, 0.082, 3.6)], mat="armor2", seg=16)
    plate("ShinPlate", [(0, 0.11), (0.032, 0.07), (0.024, -0.09), (0, -0.115), (-0.024, -0.09), (-0.032, 0.07)],
          (hx, -0.081, 0.345), (0, -1, 0.06), thick=0.022, mat="armor", bevel=0.007)
    dec("ShinStrip", [(-0.006, 0.07), (0.006, 0.07), (0.006, -0.07), (-0.006, -0.07)],
        (hx + 0.06 * sx, -0.01, 0.33), (sx, -0.25, 0), sh, mat="glow", outline=0.002, cuts=1)
    dec("ShinRed", [(0, 0.09), (0.036, 0.01), (0.0, -0.085), (-0.036, 0.01)],
        (hx + 0.046 * sx, -0.06, 0.31), (0.75 * sx, -1, 0), sh)
    box("ShinLight", (0.01, 0.01, 0.028), (hx, -0.097, 0.33), mat="glow", bevel=0.0)
    dec("CalfDark", [(-0.03, 0.11), (0.03, 0.11), (0.022, -0.11), (-0.022, -0.11)],
        (hx, 0.08, 0.34), (0, 1, 0), sh, mat="joint", offset=0.002, thick=0.004)
    dec("CalfGlow", [(-0.011, 0.085), (0.011, 0.085), (0.011, -0.085), (-0.011, -0.085)],
        (hx, 0.08, 0.34), (0, 1, 0), sh, mat="glow", outline=0.003, offset=0.006, cuts=1)
    # ---- foot: a heavy boot in plates
    bone("foot" + sf)
    ball("Ankle", (hx, 0.0, AZ), 0.05, "joint")
    box("Sole", (0.118, 0.305, 0.034), (hx, -0.072, 0.017), mat="joint", taper=(0.94, 0.97), bevel=0.008)
    box("Heel", (0.106, 0.11, 0.10), (hx, 0.042, 0.08), taper=(0.85, 0.75))
    box("Boot", (0.114, 0.16, 0.095), (hx, -0.068, 0.078), taper=(0.82, 0.82), shear=(0, 0.028))
    box("Toe", (0.112, 0.115, 0.062), (hx, -0.172, 0.064), taper=(0.8, 0.55), shear=(0, 0.026))
    box("ToeRed", (0.074, 0.05, 0.03), (hx, -0.146, 0.116), mat="red", r=rot(-22), bevel=0.006, outline=0.004)
    box("AnkleGuard", (0.10, 0.03, 0.10), (hx, -0.062, AZ + 0.05), taper=(0.7, 1.0), r=rot(14))
    box("BootSide", (0.012, 0.10, 0.03), (hx + 0.056 * sx, 0.01, 0.062), mat="red", bevel=0.004, r=rot(-12))
    box("HeelDark", (0.06, 0.012, 0.05), (hx, 0.094, 0.085), mat="joint", bevel=0.004)


def body():
    # ---- pelvis: the dark hips, a wedge in front, plates at the sides and behind
    bone("pelvis")
    loft("Hips", (0, 0.005, 0.90), (0, 0.005, 1.085), [(0, 0.10, 0.085, 3), (0.5, 0.160, 0.105, 3), (1, 0.125, 0.092, 3)], mat="joint")
    box("Cod", (0.115, 0.07, 0.18), (0, -0.088, 0.972), taper=((0.38, 0.8), (1.0, 1.0)), r=rot(-10), bevel=0.014)
    box("CodRed", (0.03, 0.02, 0.07), (0, -0.126, 0.985), mat="joint", r=rot(-10), bevel=0.004, outline=0.003)
    loft("Belt", (0, 0.004, 1.052), (0, 0.004, 1.102), [(0, 0.148, 0.108, 3.6), (1, 0.146, 0.107, 3.6)], mat="armor2", seg=24)
    box("Buckle", (0.075, 0.03, 0.06), (0, -0.106, 1.078), mat="grey", bevel=0.01)
    box("BuckleIn", (0.04, 0.012, 0.03), (0, -0.122, 1.078), mat="joint", bevel=0.004)
    for sx in (1.0, -1.0):
        box("HipPlate", (0.05, 0.16, 0.16), (0.158 * sx, 0.0, 0.998), taper=((0.7, 0.7), (1.0, 1.0)), r=rot(0, 10 * sx), bevel=0.016)
        box("HipRed", (0.012, 0.06, 0.075), (0.186 * sx, 0.0, 1.008), mat="red", r=rot(0, 10 * sx), bevel=0.004, outline=0.003)
        box("FrontTasset", (0.075, 0.03, 0.115), (0.092 * sx, -0.094, 1.0), taper=((0.6, 1.0), (1.0, 1.0)), r=rot(-8, 0, -14 * sx), bevel=0.01)
        box("Rear", (0.105, 0.05, 0.14), (0.062 * sx, 0.09, 0.975), taper=((0.6, 0.8), (1.0, 1.0)), r=rot(12, 0, 8 * sx), bevel=0.016)
    # ---- spine: the dark waist, its plates
    bone("spine")
    loft("Waist", (0, 0.0, 1.07), (0, 0.0, 1.30), [(0, 0.115, 0.086, 3), (0.5, 0.105, 0.08, 3), (1, 0.135, 0.10, 3)], mat="joint")
    for k in range(2):
        box("Abs", (0.125 + k * 0.03, 0.032, 0.062), (0, -0.074 - k * 0.008, 1.14 + k * 0.076), mat="armor2", bevel=0.012,
            taper=((0.78, 1.0), (1.0, 1.0)))
    for sx in (1.0, -1.0):
        box("Flank", (0.035, 0.11, 0.12), (0.112 * sx, 0.0, 1.19), mat="grey", taper=(0.9, 0.8), r=rot(0, -6 * sx))
        box("Loin", (0.06, 0.03, 0.10), (0.05 * sx, 0.082, 1.19), mat="armor2", bevel=0.01, r=rot(4))
    # ---- chest: a dark frame carrying the breastplate's two halves, the blades behind
    bone("chest")
    loft("ChestFrame", (0, 0.0, 1.27), (0, 0.0, 1.585),
         [(0, 0.138, 0.100, 3.2), (0.35, 0.180, 0.112, 3.2, 0, 0.002), (0.75, 0.190, 0.112, 3.2), (1, 0.14, 0.095, 3)],
         mat="joint", cap=0.5)
    box("Collar", (0.20, 0.17, 0.06), (0, 0.01, 1.585), mat="joint", taper=(0.7, 0.75))
    for sx in (1.0, -1.0):
        # (a loft built upward has its x = +X: dx as given)
        pec = loft("Pec", (0.094 * sx, -0.050, 1.318), (0.108 * sx, -0.026, 1.578),
                   [(0, 0.058, 0.050, 3.4), (0.22, 0.086, 0.076, 3.6), (0.62, 0.098, 0.084, 3.6), (0.9, 0.092, 0.07, 3.4),
                    (1, 0.08, 0.055, 3.2)], cap=0.5)
        dec("PecRed", _scale(TRI, 0.022, 0.02), (0.15 * sx, -0.125, 1.515), (0.25 * sx, -1, 0.1), pec, cuts=1)
        dec("PecSlot", [(-0.03, 0.007), (0.03, 0.007), (0.03, -0.007), (-0.03, -0.007)], (0.115 * sx, -0.125, 1.43), (0.1 * sx, -1, 0), pec,
            mat="joint", outline=0, cuts=1)
        box("Rib", (0.095, 0.04, 0.05), (0.118 * sx, -0.088, 1.31), mat="armor2", r=rot(0, 0, -16 * sx), bevel=0.012,
            taper=((0.8, 1.0), (1.0, 1.0)))
        box("SidePlate", (0.04, 0.15, 0.15), (0.186 * sx, 0.0, 1.41), taper=((0.8, 0.8), (1.0, 1.0)), bevel=0.014)
        # shoulder blades, the plates from the neck to the shoulders
        loft("Blade", (0.094 * sx, 0.048, 1.33), (0.108 * sx, 0.036, 1.575),
             [(0, 0.058, 0.05, 3.4), (0.3, 0.088, 0.072, 3.6), (0.75, 0.096, 0.076, 3.6), (1, 0.08, 0.055, 3.2)], cap=0.5)
        box("Trap", (0.12, 0.14, 0.05), (0.118 * sx, 0.0, 1.586), taper=(0.7, 0.8), r=rot(0, 16 * sx), bevel=0.016)
    # the light in the middle of the chest
    tube("ChestRing", (0, -0.10, 1.40), (0, -0.147, 1.40), 0.046, 0.042, mat="joint", seg=20)
    tube("ChestLight", (0, -0.135, 1.40), (0, -0.154, 1.40), 0.031, mat="glow", seg=18, outline=0)
    tube("ChestCore", (0, -0.145, 1.40), (0, -0.160, 1.40), 0.015, mat="glow_y", seg=12, outline=0)
    box("Gorget", (0.085, 0.04, 0.045), (0, -0.094, 1.562), bevel=0.01, taper=((0.5, 1.0), (1.0, 0.8)), r=rot(14))
    box("Sternum", (0.03, 0.03, 0.10), (0, -0.112, 1.49), mat="armor2", bevel=0.008, taper=((0.6, 1.0), (1.0, 1.0)))
    # the spine's lights down the back
    box("BackSpine", (0.07, 0.05, 0.33), (0, 0.10, 1.42), mat="joint", bevel=0.01)
    for k in range(4):
        w = 0.05 - k * 0.006
        box("BackGlow", (w, 0.02, 0.045), (0, 0.125, 1.535 - k * 0.068), mat="glow", bevel=0.004, outline=0.0025)


def head():
    """The automaton's helmet: a smooth dome running down into the mask - two
    slanted lights in dark glass under the brow, a ridge down the nose, a narrow
    chin - red rings at the ears, the triangle on the brow."""
    bone("head")
    tube("Neck", (0, 0.012, 1.57), (0, 0.006, 1.68), 0.05, 0.048, mat="joint")
    loft("Skull", (0, 0.02, 1.645), (0, 0.022, 1.80), [(0, 0.054, 0.070, 2.6), (0.5, 0.076, 0.092, 2.6), (1, 0.08, 0.094, 2.6)], mat="joint", cap=0.4)
    # the dome: tipped back a little, so its rim is a brow in front and comes down the nape behind
    dome = loft("Dome", (0, 0.024, 1.768), (0, 0.05, 1.905),
                [(0, 0.090, 0.110, 2.4), (0.22, 0.094, 0.115, 2.3), (0.5, 0.088, 0.108, 2.2), (0.72, 0.074, 0.092, 2.1),
                 (0.88, 0.052, 0.066, 2.0), (1, 0.022, 0.03, 2)], cap=0.5, seg=24)
    loft("Nape", (0, 0.055, 1.662), (0, 0.045, 1.772), [(0, 0.056, 0.060, 2.6), (0.6, 0.082, 0.082, 2.5), (1, 0.09, 0.09, 2.4)], cap=0.3)
    # the mask: from the brow to a narrow chin; the eyes' dark glass in it, their lights slanted
    face = loft("Face", (0, -0.058, 1.640), (0, -0.05, 1.80),
                [(0, 0.020, 0.022, 3.4), (0.2, 0.034, 0.034, 3.4), (0.45, 0.056, 0.044, 3.4), (0.72, 0.074, 0.048, 3.2), (1, 0.078, 0.046, 3.0)],
                cap=0.3, seg=24)
    for sx in (1.0, -1.0):
        # (a decal facing forward has its x to the character's right: -sx puts the high corner outside)
        so = [(-0.031, -0.020), (-0.030, -0.002), (0.026, 0.022), (0.038, 0.014), (0.034, -0.004), (0.004, -0.018)]
        ey = [(-0.021, -0.011), (-0.019, -0.004), (0.02, 0.012), (0.027, 0.007), (0.006, -0.008)]
        dec("EyeSocket", [(-x * sx, y) for (x, y) in so][::-int(sx)], (0.04 * sx, -0.105, 1.764), (0.3 * sx, -1, 0.0), face,
            mat="visor", offset=0.001, outline=0, thick=0.004)
        dec("Eye", [(-x * sx, y) for (x, y) in ey][::-int(sx)], (0.04 * sx, -0.105, 1.764), (0.3 * sx, -1, 0.0), face,
            mat="glow", offset=0.004, outline=0, thick=0.004, cuts=1)
        box("MouthSlit", (0.02, 0.008, 0.008), (0.024 * sx, -0.096, 1.692), mat="joint", bevel=0.0, r=rot(0, 20 * sx, -12 * sx))
        box("CheekLine", (0.006, 0.03, 0.05), (0.064 * sx, -0.082, 1.715), mat="joint", bevel=0.0, r=rot(0, -22 * sx, 28 * sx))
        # the ears: red rings on a dark seat
        tube("EarSeat", (0.07 * sx, 0.03, 1.757), (0.094 * sx, 0.03, 1.757), 0.054, 0.05, mat="joint", seg=16)
        tube("Ear", (0.086 * sx, 0.03, 1.757), (0.106 * sx, 0.03, 1.757), 0.041, mat="red", seg=16)
        tube("EarCap", (0.10 * sx, 0.03, 1.757), (0.114 * sx, 0.03, 1.757), 0.025, mat="joint", seg=14)
        tube("EarDot", (0.11 * sx, 0.03, 1.757), (0.12 * sx, 0.03, 1.757), 0.011, mat="glow", seg=8, outline=0)
    box("Nose", (0.022, 0.02, 0.12), (0, -0.098, 1.73), bevel=0.006, taper=((0.7, 1.0), (1.0, 1.0)), r=rot(-3))
    box("Chin", (0.026, 0.012, 0.03), (0, -0.086, 1.66), mat="joint", bevel=0.004)
    box("Brow", (0.15, 0.022, 0.016), (0, -0.092, 1.800), bevel=0.006, taper=(0.86, 1.0), r=rot(12))
    # the triangle on the forehead
    dec("BrowTri", _scale(TRI, 0.027, 0.025), (0, -0.072, 1.852), (0, -1, 0.5), dome, mat="red", up=(0, 0.5, 1))
    dec("BrowTriIn", _scale(TRI, 0.013, 0.012), (0, -0.072, 1.856), (0, -1, 0.5), dome, mat="armor", up=(0, 0.5, 1), offset=0.009, outline=0,
        cuts=1)


def arms(sx, sf):
    """An arm: its pauldron, the upper arm, the forearm, the hand."""
    pauldron(sx, sf)
    upper_arm(sx, sf)
    forearm(sx, sf)
    hand(sx, sf)


def pauldron(sx, sf):
    S = kit.SHOULDER
    x = S.x * sx
    # ---- the pauldron: a broad shell, flaring down and out, a rim under it - its inner side clear of the chest's
    # top and side plates (kit.fit_pauldron keeps it clear as the arm moves)
    bone("pauldron" + sf)
    pd = loft("Pauldron", (x + 0.037 * sx, 0, S.z + 0.088), (x + 0.089 * sx, 0, S.z - 0.115),
              [(0, 0.036, 0.066, 4.0), (0.16, 0.070, 0.098, 4.6), (0.6, 0.078, 0.106, 4.6), (0.9, 0.068, 0.096, 4.2), (1, 0.054, 0.082, 3.8)],
              cap=0.45, seg=24)
    loft("PauldronRim", (x + 0.077 * sx, 0, S.z - 0.072), (x + 0.089 * sx, 0, S.z - 0.122),
         [(0, 0.079, 0.107, 4.0), (1, 0.072, 0.101, 3.8)], mat="armor2", seg=24)
    if MARK == "tri":
        dec("PauldronRed", _scale(TRI, 0.05, 0.048), (x + 0.15 * sx, 0.0, S.z - 0.036), (sx, -0.08, 0.1), pd)
        dec("PauldronIn", _scale(TRI, 0.023, 0.022), (x + 0.15 * sx, 0.0, S.z - 0.032), (sx, -0.08, 0.1), pd, mat="red2", offset=0.009, outline=0,
            cuts=1)
        dec("PauldronTop", [(-0.088, 0.04), (0.088, 0.04), (0.078, -0.032), (-0.078, -0.032)],
            (x + 0.12 * sx, -0.005, S.z + 0.058), (sx, -0.1, 0.9), pd, up=(-sx, 0, 1.1), offset=0.003)
    else:
        PAULDRON_MARK[0](pd, x, sx, S)


def upper_arm(sx, sf):
    S = kit.SHOULDER
    x = S.x * sx
    ez = S.z - kit.UPPER
    bone("upper" + sf)
    ball("Shoulder", (x, 0, S.z), 0.066, "joint")
    loft("UpperCore", (x, 0, S.z - 0.03), (x, 0, ez + 0.02), [(0, 0.046, 0.05), (1, 0.038, 0.042)], mat="joint", seg=14)
    up = loft("UpperArmor", (x + 0.016 * sx, 0, S.z - 0.115), (x + 0.01 * sx, 0, ez + 0.07),
              [(0, 0.046, 0.052, 3), (0.4, 0.055, 0.062, 3.2), (1, 0.042, 0.047, 3)], cap=0.5)
    dec("UpperRed", [(-0.018, 0.04), (0.018, 0.04), (0.012, -0.04), (-0.012, -0.04)],
        (x + 0.07 * sx, 0.0, S.z - 0.2), (sx, -0.15, 0), up, cuts=1)


def forearm(sx, sf):
    """A guard swelling below the elbow."""
    S = kit.SHOULDER
    x = S.x * sx
    ez = S.z - kit.UPPER
    wz = ez - kit.FORE
    bone("fore" + sf)
    ball("Elbow", (x, 0.0, ez), 0.05, "joint")
    tube("ElbowBolt", (x - 0.054, 0, ez), (x + 0.054, 0, ez), 0.022, mat="grey")
    fa = loft("Gauntlet", (x, -0.004, ez - 0.05), (x, -0.004, wz + 0.022),
              [(0, 0.044, 0.049, 3), (0.22, 0.062, 0.068, 3.2, -0.008 * sx), (0.55, 0.060, 0.064, 3.2, -0.006 * sx), (0.85, 0.049, 0.053, 3),
               (1, 0.045, 0.049, 3)], cap=0.5)
    loft("ForeCore", (x, 0, ez - 0.02), (x, 0, wz), [(0, 0.04, 0.044), (1, 0.034, 0.038)], mat="joint", seg=14)
    tube("Cuff", (x, -0.004, wz + 0.045), (x, -0.004, wz + 0.016), 0.05, 0.047, mat="armor2", seg=14)
    dec("ForeStrip", [(-0.005, 0.05), (0.005, 0.05), (0.005, -0.05), (-0.005, -0.05)],
        (x + 0.02 * sx, -0.06, ez - 0.14), (0.3 * sx, -1, 0), fa, mat="glow", outline=0.002, cuts=1)
    dec("ForeRed", [(0, 0.075), (0.024, 0.045), (0.018, -0.05), (0, -0.07), (-0.018, -0.05), (-0.024, 0.045)],
        (x + 0.07 * sx, -0.004, ez - 0.135), (sx, -0.2, 0), fa)
    dec("ForeDark", [(-0.022, 0.07), (0.022, 0.07), (0.016, -0.05), (-0.016, -0.05)],
        (x - 0.07 * sx, -0.004, ez - 0.15), (-sx, -0.2, 0), fa, mat="joint", outline=0, cuts=1)


def hand(sx, sf):
    S = kit.SHOULDER
    x = S.x * sx
    wz = S.z - kit.UPPER - kit.FORE
    bone("hand" + sf)
    tube("Wrist", (x, 0, wz + 0.02), (x, 0, wz - 0.012), 0.038, mat="joint")
    box("Palm", (0.04, 0.085, 0.064), (x, -0.004, wz - 0.03), mat="joint", bevel=0.01)
    box("HandBack", (0.018, 0.078, 0.058), (x + 0.024 * sx, -0.004, wz - 0.028), bevel=0.006)
    box("Thumb", (0.03, 0.028, 0.05), (x - 0.005 * sx, -0.052, wz - 0.04), mat="grey", bevel=0.008, r=rot(20))
    bone("fingers" + sf)
    for k in range(4):
        box("Finger", (0.032, 0.0185, 0.056 - 0.006 * abs(k - 1.2)), (x, -0.036 + k * 0.0212, wz - 0.084), mat="grey", bevel=0.005)
    box("Knuckles", (0.02, 0.08, 0.022), (x + 0.02 * sx, -0.004, wz - 0.066), bevel=0.006)


def rifle():
    """On the gun bone: its head = the grip, its Y = the muzzle (world -Y at rest), Z = top."""
    bone("gun")
    g = Vector((0, -0.4, 1.2))

    def at(fwd, up, side=0.0):
        return (g.x + side, g.y - fwd, g.z + up)
    box("Grip", (0.034, 0.045, 0.10), at(-0.012, -0.02), mat="gun", r=rot(-14), bevel=0.008)
    box("Guard", (0.016, 0.085, 0.012), at(0.035, -0.022), mat="gun", bevel=0.0)
    box("Lower", (0.056, 0.30, 0.05), at(0.06, 0.04), mat="gun", bevel=0.01)
    box("Receiver", (0.066, 0.38, 0.07), at(0.07, 0.088), mat="armor", bevel=0.012)
    box("ReceiverStripe", (0.07, 0.24, 0.02), at(0.09, 0.07), mat="gun_o", bevel=0.004, outline=0.003)
    box("Port", (0.07, 0.07, 0.022), at(0.03, 0.10), mat="gun", bevel=0.004)
    box("Rail", (0.03, 0.34, 0.016), at(0.09, 0.128), mat="gun", bevel=0.004)
    box("Mag", (0.04, 0.075, 0.13), at(0.11, -0.035), mat="gun", r=rot(10), bevel=0.008)
    box("MagBase", (0.046, 0.08, 0.02), at(0.122, -0.098), mat="gun_o", r=rot(10), bevel=0.004)
    box("Stock", (0.046, 0.22, 0.075), at(-0.215, 0.062), mat="gun", taper=(1.0, 0.8), bevel=0.012)
    box("Cheek", (0.05, 0.14, 0.03), at(-0.20, 0.105), mat="armor", bevel=0.008)
    box("StockPad", (0.052, 0.035, 0.12), at(-0.335, 0.048), mat="armor", bevel=0.008)
    box("Fore", (0.062, 0.27, 0.08), at(0.385, 0.072), mat="armor", bevel=0.012, taper=((1.0, 1.0), (0.8, 1.0)))
    box("ForeStripe", (0.066, 0.20, 0.02), at(0.385, 0.05), mat="gun_o", bevel=0.004, outline=0.003)
    for k in range(3):
        box("Vent", (0.066, 0.03, 0.012), at(0.32 + k * 0.06, 0.09), mat="gun", bevel=0.0)
    box("ForeGrip", (0.04, 0.11, 0.05), at(0.27, 0.012), mat="gun", bevel=0.008)
    tube("Barrel", at(0.50, 0.075), at(0.72, 0.075), 0.022, mat="gun", seg=12)
    tube("Shroud", at(0.50, 0.075), at(0.60, 0.075), 0.032, 0.028, mat="grey", seg=12)
    tube("Muzzle", at(0.68, 0.075), at(0.78, 0.075), 0.034, mat="gun", seg=12)
    tube("MuzzleBand", at(0.70, 0.075), at(0.72, 0.075), 0.037, mat="gun_o", seg=12)
    tube("MuzzleGlow", at(0.775, 0.075), at(0.785, 0.075), 0.016, mat="glow", seg=10, outline=0)
    tube("Barrel2", at(0.50, 0.046), at(0.64, 0.046), 0.013, mat="gun", seg=10)
    # the scope
    tube("Scope", at(-0.03, 0.172), at(0.22, 0.172), 0.029, mat="gun", seg=14)
    tube("ScopeBack", at(-0.06, 0.172), at(-0.02, 0.172), 0.034, mat="gun", seg=14)
    tube("ScopeFront", at(0.20, 0.172), at(0.28, 0.172), 0.038, mat="armor", seg=14)
    tube("ScopeLens", at(0.275, 0.172), at(0.285, 0.172), 0.028, mat="glow", seg=12, outline=0)
    tube("ScopeRing", at(0.05, 0.172), at(0.085, 0.172), 0.034, mat="gun_o", seg=14, outline=0.004)
    box("ScopeMount", (0.03, 0.05, 0.03), at(0.02, 0.14), mat="gun", bevel=0.006)
    box("ScopeMount", (0.03, 0.05, 0.03), at(0.16, 0.14), mat="gun", bevel=0.006)


def build():
    materials()
    mirror(legs)
    body()
    head()
    mirror(arms)
    rifle()


# Where the hands hold the rifle (the gun bone's axes: x side, y muzzle, z top), for the wrists.
GUN_HAND_R = (0.0, -0.075, -0.03)
GUN_HAND_L = (0.0, 0.255, -0.035)
