# The skeleton (layer 4): skull, spine, ribcage, shoulder girdle, arms and
# hands, pelvis, legs and feet. See common.py for the coordinates.
import math
from mathutils import Vector
from common import V, Shape, tube, Tubes, bone_mat, plain, hand_rays, foot_rays, foot_axis, ANKLE

# The spine: (name, z of the body's centre, half width, how far forward) - C1..C7, T1..T12, L1..L5.
def vertebrae():
    out = []
    for i in range(7):
        out.append(("C%d" % (i + 1), 1.598 - i * 0.0155, 0.0105 + i * 0.0007, 0.012 - abs(i - 3) * 0.003, 0.0155))
    for i in range(12):
        out.append(("T%d" % (i + 1), 1.485 - i * 0.0255, 0.0150 + i * 0.0005, -0.030 - math.sin(i / 11.0 * math.pi) * 0.022, 0.0255))
    for i in range(5):
        out.append(("L%d" % (i + 1), 1.176 - i * 0.0325, 0.0215 + i * 0.001, -0.022 + math.sin(i / 4.0 * math.pi) * 0.02, 0.0325))
    return out

# Ribs 1..12: half width, how far the front end drops, the front end's x and forward.
RIBS = [(0.058, 0.035, 0.030, 0.070), (0.090, 0.050, 0.035, 0.085), (0.112, 0.060, 0.045, 0.095), (0.127, 0.068, 0.055, 0.100),
        (0.138, 0.076, 0.068, 0.100), (0.146, 0.084, 0.082, 0.098), (0.150, 0.090, 0.098, 0.094), (0.151, 0.090, 0.112, 0.088),
        (0.148, 0.085, 0.122, 0.080), (0.141, 0.075, 0.128, 0.070), (0.128, 0.060, 0.125, 0.030), (0.100, 0.040, 0.100, -0.010)]
# Where the cartilages of ribs 2..7 meet the sternum (z).
STERNAL = [1.452, 1.428, 1.398, 1.368, 1.342, 1.318, 1.298]


def rib_end(i, s):
    w, drop, xf, ff = RIBS[i]
    z = 1.485 - i * 0.0255
    return V(s * xf, z - drop, ff)


def rib_path(i, s):
    w, drop, xf, ff = RIBS[i]
    z = 1.485 - i * 0.0255
    pts = [V(s * 0.022, z, -0.045), V(s * w * 0.62, z + 0.004, -0.078), V(s * w * 0.95, z - drop * 0.25, -0.045),
           V(s * w, z - drop * 0.5, 0.01)]
    if i < 10:
        pts += [V(s * (w * 0.55 + xf * 0.45), z - drop * 0.82, (0.06 + ff) * 0.5 + 0.01), V(s * xf, z - drop, ff)]
    elif i == 10:
        pts += [V(s * xf, z - drop, ff)]
    return pts


def build():
    bone = bone_mat()
    cart = plain("cartilage", (0.74, 0.77, 0.74), rough=0.42, sss=0.35, coat=0.12, bump=0.15, vary=0.12)
    tooth = plain("tooth", (0.95, 0.93, 0.86), rough=0.15, sss=0.2, coat=0.6)

    # --- skull ---
    sk = Shape()
    sk.ell(V(0, 1.722, -0.014), (0.076, 0.095, 0.084))
    sk.ell(V(0, 1.722, 0.042), (0.066, 0.052, 0.064))
    sk.ell(V(0, 1.660, 0.058), (0.044, 0.040, 0.040))
    sk.ell(V(0, 1.634, 0.066), (0.034, 0.030, 0.016))
    sk.cap(V(0, 1.708, 0.090), V(0, 1.686, 0.104), 0.0085, 0.006)
    for s in (-1, 1):
        sk.cap(V(s * 0.052, 1.724, 0.078), V(s * 0.012, 1.722, 0.090), 0.0085)          # brow ridge
        sk.ell(V(s * 0.053, 1.670, 0.058), (0.021, 0.020, 0.017))                        # cheekbone
        sk.cap(V(s * 0.060, 1.670, 0.045), V(s * 0.073, 1.674, -0.012), 0.0062)          # zygomatic arch
        sk.ell(V(s * 0.064, 1.652, -0.022), (0.011, 0.016, 0.016))                       # mastoid
        sk.cap(V(s * 0.050, 1.700, 0.070), V(s * 0.050, 1.676, 0.066), 0.007)            # the orbit's outer rim
    cut = Shape()
    for s in (-1, 1):
        cut.ell(V(s * 0.033, 1.701, 0.088), (0.0205, 0.034, 0.0175), rot=(0, s * 0.18, 0))   # orbits
        cut.ell(V(s * 0.0062, 1.661, 0.100), (0.0085, 0.030, 0.0085))                         # the nasal aperture's base
        cut.ell(V(s * 0.068, 1.690, 0.030), (0.008, 0.030, 0.022))                            # temporal fossa
    cut.ell(V(0, 1.671, 0.100), (0.0085, 0.030, 0.0175))
    sk.finish("skull", bone, voxel=0.0016, smooth=3, cut=cut)
    # The septum and the thin bones inside the nose and orbits (dark hollows with a little structure).
    inner = Shape()
    inner.box(V(0, 1.668, 0.062), (0.0012, 0.02, 0.018))
    for s in (-1, 1):
        inner.ell(V(s * 0.033, 1.701, 0.045), (0.022, 0.012, 0.019))
    inner.finish("skull_in", plain("bone_dark", (0.30, 0.22, 0.15), rough=0.8), raw=True)

    # --- mandible ---
    mj = Shape()
    for s in (-1, 1):
        mj.path([V(s * 0.060, 1.664, 0.0), V(s * 0.056, 1.630, 0.006), V(s * 0.052, 1.600, 0.012)], [0.008, 0.0085, 0.0105])
        mj.path([V(s * 0.052, 1.598, 0.012), V(s * 0.040, 1.586, 0.045), V(s * 0.020, 1.581, 0.070), V(0, 1.580, 0.078)],
                [0.0115, 0.0125, 0.013, 0.014])
        mj.path([V(s * 0.049, 1.608, 0.022), V(s * 0.034, 1.598, 0.055), V(s * 0.016, 1.596, 0.074), V(0, 1.595, 0.080)],
                [0.009, 0.0095, 0.0095, 0.0095])
        mj.ell(V(s * 0.055, 1.630, 0.006), (0.0075, 0.012, 0.030))
        mj.cap(V(s * 0.050, 1.606, 0.016), V(s * 0.047, 1.642, 0.030), 0.006, 0.004)   # coronoid process
    mj.ell(V(0, 1.580, 0.079), (0.020, 0.012, 0.015))
    mj.finish("mandible", bone, voxel=0.0016, smooth=3)

    # --- teeth ---
    th = Shape()
    for row, z, k in ((0, 1.6235, 1.0), (1, 1.6085, 0.92)):
        for i in range(-7, 8):
            a = i / 7.0 * 1.25
            x = 0.031 * k * math.sin(a)
            f = 0.050 + 0.034 * k * math.cos(a)
            big = abs(i) >= 4
            th.ell(V(x, z, f), (0.0036 if not big else 0.0042, 0.0038, 0.0068 if abs(i) != 3 else 0.0076), seg=12)
    th.finish("teeth", tooth, raw=True)

    # --- spine ---
    sp = Shape()
    discs = Shape()
    vs = vertebrae()
    for k, (name, z, rx, f, step) in enumerate(vs):
        sp.ell(V(0, z, f), (rx, rx * 0.82, step * 0.40))
        ext = 0.012 if name[0] == "C" else (0.024 - k * 0.0004 if name[0] == "T" else 0.030)
        for s in (-1, 1):
            sp.cap(V(s * rx * 0.75, z, f - 0.014), V(s * (rx + ext), z + 0.003, f - 0.026), 0.0048, 0.0036)
            sp.ell(V(s * rx * 0.85, z - step * 0.1, f - 0.018), (0.006, 0.007, step * 0.3))   # articular processes
        sp.cap(V(0, z, f - 0.02), V(0, z - step * 0.5, f - 0.05), 0.005, 0.004)              # spinous process
        if k + 1 < len(vs):
            discs.ell(V(0, z - step * 0.5, (f + vs[k + 1][3]) * 0.5), (rx * 0.97, rx * 0.8, step * 0.105))
    discs.ell(V(0, 1.030, -0.012), (0.0255, 0.021, 0.0035))
    sp.finish("spine", bone, voxel=0.0018, smooth=2)
    discs.finish("discs", cart, raw=True)

    # --- ribcage ---
    ribs = Tubes("ribs", bone, bevel_res=6)
    cartt = Tubes("costal", cart, bevel_res=6)
    for s in (-1, 1):
        for i in range(12):
            pts = rib_path(i, s)
            n = len(pts)
            ribs.add(pts, [0.0050 + 0.0016 * math.sin(k / (n - 1) * math.pi) for k in range(n)], sub=10)
        # Costal cartilages: 1..7 to the sternum, 8..10 each to the one above (the costal margin).
        for i in range(7):
            e = rib_end(i, s)
            sx = V(s * (0.022 if i == 0 else 0.017), STERNAL[i], 0.086 if i == 0 else 0.092)
            mid = (e + sx) * 0.5 + Vector((0, 0, -0.012 * max(0, i - 3)))
            cartt.add([e, mid, sx], [0.0058, 0.0056, 0.0062], sub=8)
        join = [V(s * 0.060, 1.262, 0.094), V(s * 0.086, 1.232, 0.088), V(s * 0.106, 1.204, 0.078)]
        for k, i in enumerate((7, 8, 9)):
            e = rib_end(i, s)
            cartt.add([e, (e + join[k]) * 0.5 + Vector((0, 0, -0.006)), join[k]], [0.0054, 0.005, 0.0048], sub=8)
        cartt.add([V(s * 0.017, 1.298, 0.092), V(s * 0.036, 1.276, 0.094)] + join, [0.006, 0.0056, 0.0052, 0.005, 0.0046], sub=8)

    st = Shape()
    st.ell(V(0, 1.452, 0.084), (0.030, 0.0095, 0.026))
    st.ell(V(0, 1.366, 0.093), (0.0195, 0.0088, 0.072))
    st.cap(V(0, 1.294, 0.092), V(0, 1.268, 0.086), 0.0072, 0.003)
    for s in (-1, 1):
        st.ell(V(s * 0.026, 1.466, 0.080), (0.008, 0.008, 0.009))   # the clavicular notches' lips
    notch = Shape().ell(V(0, 1.482, 0.084), (0.015, 0.02, 0.012))
    st.finish("sternum", bone, voxel=0.0018, smooth=3, cut=notch)

    for s in (-1, 1):
        n = "L" if s > 0 else "R"
        # --- shoulder girdle ---
        tube("clavicle" + n, [V(s * 0.024, 1.464, 0.078), V(s * 0.072, 1.471, 0.086), V(s * 0.130, 1.479, 0.046), V(s * 0.180, 1.483, 0.002)],
             [0.0088, 0.0068, 0.0070, 0.0090], bone, sub=10, bevel_res=8)
        sc = Shape()
        for k in range(9):   # the blade: a fan of struts from its neck, fused into a plate
            t = k / 8.0
            sc.cap(V(s * 0.165, 1.435, -0.045), V(s * (0.098 + 0.03 * t), 1.455 - 0.135 * t, -0.090), 0.0065, 0.0045)
        sc.cap(V(s * 0.105, 1.452, -0.088), V(s * 0.192, 1.480, -0.012), 0.0075, 0.0095)     # its spine out to the acromion
        sc.cap(V(s * 0.166, 1.456, -0.005), V(s * 0.156, 1.444, 0.036), 0.0075, 0.006)       # coracoid process
        sc.ell(V(s * 0.171, 1.440, -0.022), (0.011, 0.016, 0.021))                           # glenoid
        sc.finish("scapula" + n, bone, voxel=0.002, smooth=3)
        # --- arm ---
        ar = Shape()
        ar.ell(V(s * 0.189, 1.442, -0.012), (0.0235, 0.0235, 0.0235))
        ar.ell(V(s * 0.206, 1.431, 0.0), (0.0135, 0.014, 0.0165))
        ar.path([V(s * 0.201, 1.420, 0.0), V(s * 0.212, 1.320, 0.0), V(s * 0.226, 1.225, 0.0), V(s * 0.234, 1.188, 0.004)],
                [0.0140, 0.0112, 0.0108, 0.0135])
        ar.ell(V(s * 0.208, 1.179, 0.0), (0.0125, 0.010, 0.0125))                            # medial epicondyle
        ar.ell(V(s * 0.258, 1.179, 0.0), (0.0100, 0.010, 0.0115))                            # lateral epicondyle
        ar.cap(V(s * 0.219, 1.166, 0.004), V(s * 0.250, 1.166, 0.004), 0.0108)               # trochlea and capitulum
        ar.finish("humerus" + n, bone, voxel=0.002, smooth=3)
        fa = Shape()
        fa.path([V(s * 0.222, 1.176, -0.010), V(s * 0.228, 1.142, 0.0), V(s * 0.250, 1.020, 0.0), V(s * 0.268, 0.928, 0.0)],
                [0.0110, 0.0090, 0.0068, 0.0058])
        fa.ell(V(s * 0.268, 0.924, 0.0), (0.0082, 0.008, 0.008))
        fa.finish("ulna" + n, bone, voxel=0.0016, smooth=3)
        fr = Shape()
        fr.path([V(s * 0.248, 1.156, 0.004), V(s * 0.252, 1.134, 0.004), V(s * 0.276, 1.030, 0.004), V(s * 0.296, 0.928, 0.004)],
                [0.0092, 0.0064, 0.0076, 0.0112])
        fr.finish("radius" + n, bone, voxel=0.0016, smooth=3)
        # --- hand: carpals, metacarpals, phalanges (palm forward: the thumb on the outside) ---
        hd = Shape()
        wx, wz = s * 0.284, 0.912
        for r in range(2):
            for c in range(4):
                hd.ell(V(wx + s * (c - 1.5) * 0.0105, wz - 0.004 - r * 0.0135, 0.004), (0.0062, 0.006, 0.0066), seg=12)
        for k, (p, d, lens) in enumerate(hand_rays(s)):
            for j, ln in enumerate(lens):
                q = p + d * ln
                r0 = (0.0058 if k == 0 else 0.0052) - j * 0.0005
                hd.path([p, (p + q) * 0.5, q], [r0, r0 * 0.72, r0 * 0.98], seg=10)
                p = q
        hd.finish("hand" + n, bone, voxel=0.0011, smooth=2)
        # --- leg ---
        fe = Shape()
        fe.ell(V(s * 0.095, 0.936, 0.010), (0.0235, 0.0235, 0.0235))
        fe.cap(V(s * 0.106, 0.931, 0.008), V(s * 0.146, 0.906, 0.0), 0.0135, 0.0150)
        fe.ell(V(s * 0.159, 0.906, -0.005), (0.0165, 0.018, 0.0245))
        fe.ell(V(s * 0.128, 0.866, -0.012), (0.010, 0.011, 0.012))
        fe.path([V(s * 0.150, 0.886, 0.0), V(s * 0.135, 0.750, 0.012), V(s * 0.112, 0.600, 0.012), V(s * 0.093, 0.525, 0.0)],
                [0.0165, 0.0142, 0.0145, 0.0185])
        fe.ell(V(s * 0.068, 0.493, 0.0), (0.0200, 0.026, 0.0225))
        fe.ell(V(s * 0.112, 0.493, 0.0), (0.0200, 0.026, 0.0225))
        fe.ell(V(s * 0.090, 0.507, 0.010), (0.0220, 0.018, 0.0200))
        notch2 = Shape().ell(V(s * 0.090, 0.476, 0.0), (0.008, 0.04, 0.016))
        fe.finish("femur" + n, bone, voxel=0.0022, smooth=3, cut=notch2)
        Shape().ell(V(s * 0.090, 0.503, 0.046), (0.0205, 0.0095, 0.0220)).ell(V(s * 0.090, 0.488, 0.044), (0.012, 0.008, 0.012)) \
            .finish("patella" + n, bone, voxel=0.0018, smooth=2)
        ti = Shape()
        ti.ell(V(s * 0.088, 0.458, 0.0), (0.0380, 0.026, 0.0160))
        ti.ell(V(s * 0.090, 0.430, 0.022), (0.0120, 0.010, 0.0160))
        ti.path([V(s * 0.088, 0.442, 0.004), V(s * 0.084, 0.300, 0.010), V(s * 0.079, 0.140, 0.006), V(s * 0.078, 0.082, 0.004)],
                [0.0170, 0.0125, 0.0108, 0.0150])
        ti.ell(V(s * 0.060, 0.066, 0.004), (0.0105, 0.012, 0.0140))
        ti.finish("tibia" + n, bone, voxel=0.002, smooth=3)
        fi = Shape()
        fi.ell(V(s * 0.124, 0.440, -0.012), (0.0100, 0.010, 0.0120))
        fi.path([V(s * 0.124, 0.430, -0.012), V(s * 0.119, 0.280, -0.010), V(s * 0.105, 0.105, -0.008)], [0.0064, 0.0054, 0.0060])
        fi.ell(V(s * 0.102, 0.064, -0.006), (0.0105, 0.012, 0.0160))
        fi.finish("fibula" + n, bone, voxel=0.0016, smooth=3)
        # --- foot (relaxed: the toes forward and down, turned out a little) ---
        ft = Shape()
        ank = V(s * ANKLE[0], ANKLE[1], ANKLE[2])
        d0 = foot_axis(s)
        ft.ell(ank, (0.0200, 0.024, 0.0170))                                                 # talus
        ft.ell(ank - d0 * 0.045 + Vector((0, 0.012, -0.012)), (0.0170, 0.024, 0.0220))       # heel
        ft.ell(ank + d0 * 0.036 + Vector((-s * 0.008, 0, 0)), (0.0135, 0.012, 0.0125))       # navicular
        ft.ell(ank + d0 * 0.046 + Vector((s * 0.018, 0.004, 0)), (0.0125, 0.013, 0.0140))    # cuboid
        for c in range(3):
            ft.ell(ank + d0 * 0.064 + Vector((s * (c - 1.3) * 0.012, 0, 0)), (0.0062, 0.008, 0.0090), seg=12)
        for k, (p, d, lens) in enumerate(foot_rays(s)):
            for j, ln in enumerate(lens):
                q = p + d * ln
                r0 = (0.0078 if k == 0 else 0.0050) - j * 0.0005
                ft.path([p, (p + q) * 0.5, q], [r0, r0 * 0.72, r0], seg=10)
                p = q
        ft.finish("foot" + n, bone, voxel=0.0013, smooth=2)

    # --- pelvis and sacrum ---
    pv = Shape()
    pv.ell(V(0, 0.988, -0.034), (0.050, 0.022, 0.036))
    pv.ell(V(0, 0.938, -0.040), (0.028, 0.016, 0.030))
    pv.cap(V(0, 0.908, -0.034), V(0, 0.884, -0.022), 0.0085, 0.004)
    holes = Shape()
    for s in (-1, 1):
        crest = [V(s * 0.128, 1.026, 0.050), V(s * 0.137, 1.060, 0.020), V(s * 0.120, 1.086, -0.020), V(s * 0.082, 1.084, -0.060),
                 V(s * 0.046, 1.046, -0.086)]
        pv.path(crest, [0.0095, 0.0090, 0.0090, 0.0090, 0.0095])
        from common import smooth_path
        cs, _ = smooth_path(crest, 0.009, 5)
        for k, c in enumerate(cs):   # the wing: struts from the crest down to the brim, fused into a plate
            t = k / (len(cs) - 1.0)
            pv.cap(c, V(s * (0.108 - 0.068 * t), 0.966 + 0.030 * t, 0.020 - 0.062 * t), 0.0062, 0.0085, seg=10)
        pv.cap(V(s * 0.128, 1.026, 0.050), V(s * 0.112, 0.972, 0.036), 0.0092, 0.0105)       # ASIS down to the socket
        pv.ell(V(s * 0.096, 0.936, 0.008), (0.030, 0.026, 0.030))                            # acetabulum
        pv.cap(V(s * 0.086, 0.948, 0.030), V(s * 0.013, 0.916, 0.066), 0.0095, 0.0088)       # superior pubic ramus
        pv.ell(V(s * 0.013, 0.905, 0.066), (0.0112, 0.010, 0.0165))                          # pubic body
        pv.path([V(s * 0.013, 0.893, 0.060), V(s * 0.040, 0.864, 0.030), V(s * 0.062, 0.860, -0.010), V(s * 0.086, 0.900, -0.010)],
                [0.0078, 0.0080, 0.0135, 0.0100])                                           # ischiopubic ramus, the tuberosity
        pv.cap(V(s * 0.046, 1.046, -0.086), V(s * 0.040, 0.990, -0.040), 0.010)              # sacroiliac joint
        for k in range(4):
            holes.ell(V(s * (0.024 - k * 0.003), 1.004 - k * 0.022, -0.02), (0.0048, 0.04, 0.0048))   # sacral foramina
        holes.ell(V(s * 0.097, 0.934, 0.036), (0.0215, 0.020, 0.0215))                       # the hip socket
    pv.finish("pelvis", bone, voxel=0.0024, smooth=3, cut=holes)
    Shape().ell(V(0, 0.905, 0.066), (0.0035, 0.009, 0.015)).finish("symphysis", cart, raw=True)
