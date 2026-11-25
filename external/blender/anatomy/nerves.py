# The nerves (layer 3): the brain, the spinal cord and its 31 pairs of nerves -
# the plexuses of the neck, arm, loin and hip and the nerves they send down
# the limbs - the cranial nerves of the face, the eyes, the sympathetic chains,
# with fine branches everywhere. See common.py.
import math, random
from mathutils import Vector
from common import V, Shape, Tubes, plain, twigs, hand_rays, foot_rays, foot_axis, ANKLE, _mats, _new, _set
import skeleton


def brain_mat():
    """The brain: folds (a cell pattern's ridges, warped) - pale pink on the gyri, dark in the sulci."""
    if "brain" in _mats:
        return _mats["brain"]
    m, nt, b = _new("brain")
    _set(b, rough=0.32, sss=0.3, coat=0.45)
    b.inputs["Subsurface Radius"].default_value = (0.02, 0.01, 0.008)
    b.inputs["Subsurface Scale"].default_value = 0.2
    N, L = nt.nodes.new, nt.links.new
    tc = N("ShaderNodeTexCoord")
    warp = N("ShaderNodeTexNoise")
    warp.inputs["Scale"].default_value = 42.0
    warp.inputs["Detail"].default_value = 2.0
    L(tc.outputs["Object"], warp.inputs["Vector"])
    mixv = N("ShaderNodeMixRGB")
    mixv.inputs[0].default_value = 0.11
    L(tc.outputs["Object"], mixv.inputs[1])
    L(warp.outputs["Color"], mixv.inputs[2])
    vor = N("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 62.0
    L(mixv.outputs[0], vor.inputs["Vector"])
    ramp = N("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = (0.30, 0.13, 0.12, 1)
    e[1].position = 0.16; e[1].color = (0.88, 0.66, 0.60, 1)
    e2 = ramp.color_ramp.elements.new(0.05); e2.color = (0.58, 0.34, 0.30, 1)
    L(vor.outputs["Distance"], ramp.inputs[0])
    L(ramp.outputs[0], b.inputs["Base Color"])
    hm = N("ShaderNodeMapRange")
    hm.inputs["From Max"].default_value = 0.14
    L(vor.outputs["Distance"], hm.inputs["Value"])
    bp = N("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 1.0
    bp.inputs["Distance"].default_value = 0.006
    L(hm.outputs[0], bp.inputs["Height"])
    L(bp.outputs["Normal"], b.inputs["Normal"])
    _mats["brain"] = m
    return m


def build():
    rng = random.Random(23)
    nmat = plain("nerve", (0.98, 0.80, 0.22), rough=0.34, sss=0.3, coat=0.35, bump=0.15, bump_scale=300.0, vary=0.18)
    cmat = plain("cord", (0.93, 0.84, 0.56), rough=0.3, sss=0.35, coat=0.4, bump=0.15, bump_scale=260.0, vary=0.12)
    N = Tubes("nerves", nmat, bevel_res=5)

    def run(pts, r0, r1, side=1, f=0.0, spacing=0.03, twig_len=0.045, depth=3, twig_r=0.0013):
        P = [V(side * p[0], p[1], (p[2] if len(p) > 2 else 0.0) + f) for p in pts]
        n = len(P)
        ps, rs = N.add(P, [r0 + (r1 - r0) * i / (n - 1.0) for i in range(n)], sub=6)
        if spacing <= 0:
            return ps
        acc = 0.0
        for i in range(1, len(ps)):
            seg = ps[i] - ps[i - 1]
            acc += seg.length
            if acc >= spacing:
                acc = 0.0
                t = Vector((seg.x, seg.z))
                if t.length < 1e-6:
                    continue
                t.normalize()
                a = rng.choice((-1, 1)) * rng.uniform(0.45, 1.1)
                nd = (t.x * math.cos(a) - t.y * math.sin(a), t.x * math.sin(a) + t.y * math.cos(a))
                twigs(N, rng, ps[i], nd, twig_len * rng.uniform(0.6, 1.3), min(rs[i] * 0.5, twig_r), depth)
        return ps

    # --- the brain ---
    br = Shape()
    for s in (-1, 1):
        br.ell(V(s * 0.033, 1.735, -0.010), (0.0325, 0.082, 0.050))          # hemisphere
        br.ell(V(s * 0.030, 1.722, 0.040), (0.0290, 0.040, 0.034))           # frontal lobe
        br.ell(V(s * 0.048, 1.698, 0.006), (0.0190, 0.040, 0.020))           # temporal lobe
    cut = Shape().box(V(0, 1.745, 0.0), (0.0012, 0.12, 0.05))                # the fissure between them
    br.finish("brain", brain_mat(), voxel=0.0016, smooth=3, cut=cut)
    cb = Shape()
    for s in (-1, 1):
        cb.ell(V(s * 0.026, 1.676, -0.050), (0.026, 0.026, 0.017))
    cb.finish("cerebellum", plain("cerebellum", (0.80, 0.56, 0.50), rough=0.35, sss=0.3, coat=0.4, bump=0.8, bump_scale=900.0, vary=0.3), voxel=0.0016, smooth=2)
    st = Shape()
    st.cap(V(0, 1.694, -0.014), V(0, 1.660, -0.020), 0.0130, 0.0115)        # pons
    st.cap(V(0, 1.660, -0.020), V(0, 1.622, -0.016), 0.0105, 0.0080)        # medulla
    st.finish("brainstem", cmat, voxel=0.0014, smooth=3)
    # The cord: its two swellings (for the arms, for the legs), ending at the loins in a tail of roots.
    cord = Tubes("cord", cmat, bevel_res=8)
    vs = skeleton.vertebrae()
    cz = [(0, 1.622, -0.016)] + [(0, z, f - 0.012) for (_, z, _, f, _) in vs[:20]]
    rad = []
    for (x, z, f) in cz:
        r = 0.0062
        r += 0.0020 * math.exp(-((z - 1.535) / 0.035) ** 2) + 0.0018 * math.exp(-((z - 1.215) / 0.035) ** 2)
        if z < 1.19:
            r *= max(0.25, (z - 1.14) / 0.05)
        rad.append(r)
    cord.add([V(*p) for p in cz], rad, sub=6)
    # --- the eyes and the cranial nerves ---
    eyes = Shape()
    iris = Shape()
    for s in (-1, 1):
        eyes.ell(V(s * 0.033, 1.703, 0.074), (0.0122, 0.0122, 0.0122), seg=32)
        iris.ell(V(s * 0.033, 1.703, 0.0855), (0.0058, 0.0028, 0.0058), seg=24)
        N.add([V(s * 0.033, 1.703, 0.062), V(s * 0.020, 1.702, 0.030), V(s * 0.004, 1.700, 0.006), V(-s * 0.012, 1.694, -0.012)], [0.0030, 0.0030, 0.0030, 0.0026], sub=6)   # optic nerve, crossing
        for (tz, ln, k) in ((1.722, 0.060, 7), (1.676, 0.050, 6), (1.628, 0.050, 6)):     # trigeminal: to the brow, the cheek, the jaw
            base = V(s * 0.040, 1.682, 0.010)
            mid = V(s * 0.044, tz, 0.060)
            N.add([base, (base + mid) * 0.5 + Vector((s * 0.006, 0, 0)), mid], [0.0024, 0.0020, 0.0016], sub=5)
            for j in range(k):
                a = (j / (k - 1.0) - 0.5) * 2.0 + (math.pi if s < 0 else 0.0) + (0.9 if tz > 1.70 else (-0.9 if tz < 1.65 else 0.0)) * (1 if s > 0 else -1)
                twigs(N, rng, mid + Vector((0, -0.02, 0)), (-s * abs(math.cos(a)) * 0.6 + 0.0, math.sin(a)), ln, 0.0012, 2)
        fb = V(s * 0.068, 1.660, 0.020)                                                 # facial nerve: a fan across the face from before the ear
        N.add([V(s * 0.030, 1.668, -0.016), V(s * 0.060, 1.662, 0.0), fb], [0.0020, 0.0020, 0.0018], sub=5)
        for j in range(6):
            a = -1.1 + j * 0.44
            end = V(s * (0.068 - 0.050 * math.cos(a * 0.6)), 1.660 + 0.062 * math.sin(a), 0.085)
            N.add([fb, (fb + end) * 0.5 + Vector((0, -0.03, 0)), end], [0.0015, 0.0012, 0.0007], sub=5)
            twigs(N, rng, end, (-s, math.sin(a) * 0.5), 0.022, 0.0008, 2)
        for j in range(6):                                                              # over the scalp
            a = 0.25 + j * 0.24
            twigs(N, rng, V(s * 0.050, 1.724, 0.050), (s * math.cos(a) * 0.5, math.sin(a)), 0.07, 0.0011, 2)
        run([(0.010, 1.664, -0.020), (0.030, 1.620, 0.006), (0.036, 1.540, 0.016), (0.030, 1.470, 0.012), (0.026, 1.400, 0.02), (0.020, 1.300, 0.03), (0.014, 1.240, 0.04)],
            0.0024, 0.0016, side=s, spacing=0.03, twig_len=0.035, depth=2)                # vagus
    eyes.finish("eyes", plain("sclera", (0.93, 0.90, 0.86), rough=0.12, sss=0.3, coat=0.8), raw=True)
    iris.finish("iris", plain("iris", (0.10, 0.28, 0.42), rough=0.2, coat=0.9), raw=True)

    # --- the spinal nerves ---
    gang = Shape()
    for s in (-1, 1):
        roots = {}
        for (name, z, rx, f, step) in vs:
            a = V(0, z + step * 0.2, f - 0.012)
            b = V(s * (rx + 0.012), z - step * 0.25, f - 0.020)
            N.add([a, (a + b) * 0.5 + Vector((0, 0, step * 0.1)), b], [0.0026, 0.0024, 0.0022], sub=4)
            gang.ell(b, (0.0040, 0.0034, 0.0034), seg=10)                                # the root's ganglion
            roots[name] = b
        # (eight cervical nerves to seven vertebrae: C8 leaves between C7 and T1)
        c8 = (roots["C7"] + roots["T1"]) * 0.5
        N.add([V(0, c8.z + 0.006, -c8.y - 0.008), c8], [0.0026, 0.0022], sub=3)
        gang.ell(c8, (0.0040, 0.0034, 0.0034), seg=10)
        roots["C8"] = c8
        # the tail of roots below the cord, out through the sacrum
        for k in range(5):
            z = 0.998 - k * 0.022
            b = V(s * (0.026 - k * 0.003), z, -0.022)
            N.add([V(s * 0.003, 1.150, -0.03), V(s * (0.006 + k * 0.002), 1.060, -0.022), b], [0.0016, 0.0016, 0.0020], sub=6)
            roots["S%d" % (k + 1)] = b
        # the sympathetic chain: a beaded cord down each side of the spine
        chain = [V(s * (rx + 0.020), z, f - 0.004) for (_, z, rx, f, _) in vs[2:]]
        N.add(chain, 0.0013, sub=3)
        for c in chain:
            gang.ell(c, (0.0030, 0.0026, 0.0042), seg=10)
        # cervical plexus: to the neck and shoulder, and the phrenic nerve down to the diaphragm
        for nm, (ex, ez, ef) in (("C2", (0.060, 1.640, 0.02)), ("C3", (0.070, 1.590, 0.04)), ("C3", (0.040, 1.560, 0.05)), ("C4", (0.110, 1.500, 0.05)), ("C4", (0.070, 1.470, 0.07))):
            r = roots[nm]
            ps = N.add([r, (r + V(s * ex, ez, ef)) * 0.5, V(s * ex, ez, ef)], [0.0018, 0.0015, 0.0009], sub=5)[0]
            twigs(N, rng, ps[-1], (s * 0.7, -0.4), 0.05, 0.0009, 2)
        r = roots["C4"]
        N.add([r, V(s * 0.040, 1.500, 0.01), V(s * 0.046, 1.420, 0.03), V(s * (0.058 if s > 0 else 0.044), 1.330, 0.04), V(s * 0.060, 1.262, 0.03)], [0.0018, 0.0017, 0.0016, 0.0015, 0.0013], sub=6)
        for a in (-2.6, -2.0, -1.4, -0.8):
            twigs(N, rng, V(s * 0.060, 1.262, 0.03), (s * math.cos(a) * (1 if s > 0 else -1) * (1 if a > -1.7 else -1), -0.3 + 0.2 * math.sin(a)), 0.05, 0.0010, 2)
        # brachial plexus: five roots braid into three cords behind the collarbone, then the arm's nerves
        ax = V(s * 0.150, 1.452, 0.0)
        for k, nm in enumerate(("C5", "C6", "C7", "C8", "T1")):
            r = roots[nm]
            m = V(s * 0.085, 1.495 - k * 0.010, 0.0)
            N.add([r, (r + m) * 0.5, m, ax + Vector((0, 0, (1 - k) * 0.004))], [0.0026, 0.0026, 0.0027, 0.0026], sub=6)
        run([(0.150, 1.452), (0.182, 1.420, 0.01), (0.205, 1.400, 0.03), (0.222, 1.360, 0.03)], 0.0022, 0.0010, side=s, spacing=0.02, twig_len=0.04, depth=2)        # axillary
        run([(0.150, 1.452), (0.186, 1.390, 0.01), (0.210, 1.300, 0.02), (0.232, 1.200, 0.03), (0.256, 1.100, 0.03), (0.286, 0.960, 0.02)], 0.0020, 0.0009, side=s, spacing=0.03, twig_len=0.04, depth=2)   # musculocutaneous
        med = run([(0.150, 1.452), (0.186, 1.380), (0.206, 1.290), (0.222, 1.200), (0.238, 1.150), (0.256, 1.040), (0.276, 0.940), (0.284, 0.900)], 0.0030, 0.0022, side=s, spacing=0.028, twig_len=0.04)   # median
        run([(0.150, 1.452), (0.178, 1.380, -0.01), (0.196, 1.290, -0.01), (0.206, 1.200, -0.015), (0.212, 1.168, -0.02), (0.232, 1.060, -0.005), (0.258, 0.950), (0.270, 0.900)], 0.0027, 0.0020, side=s, spacing=0.03, twig_len=0.04)   # ulnar
        run([(0.150, 1.452), (0.196, 1.400, -0.02), (0.232, 1.320, -0.03), (0.250, 1.240, -0.01), (0.260, 1.170, 0.005), (0.280, 1.060, 0.01), (0.298, 0.950, 0.005)], 0.0030, 0.0016, side=s, spacing=0.028, twig_len=0.05)   # radial
        rays = hand_rays(s)
        fwd = Vector((0, -0.006, 0))
        for k, (p, d, lens) in enumerate(rays):                                           # the fingers: a nerve down each side, a tuft at the tip
            tip = p + d * sum(lens)
            sv = Vector((d.z, 0, -d.x)) * 0.0046
            src = V(s * (0.284 if k < 4 else 0.270), 0.900, 0.006)
            for sg in (-1, 1):
                N.add([src, p + d * (lens[0] * 0.5) + sv * sg + fwd, tip - d * 0.004 + sv * sg * 0.7 + fwd], [0.0015, 0.0012, 0.0006], sub=4)
                for j in range(3):
                    t = 0.45 + j * 0.2
                    q = p + d * (sum(lens) * t) + sv * sg + fwd
                    N.add([q, q - sv * sg * 0.8 + d * 0.006], [0.0006, 0.0004], sub=2)
        # intercostal nerves: one along each rib
        for i in range(11):
            pts = skeleton.rib_path(i, s)
            N.add([roots["T%d" % (i + 1)]] + [p + Vector((0, -0.004, -0.010)) for p in pts[1:]], [0.0018] * (len(pts) - 1) + [0.0009], sub=8)
            if i >= 6:   # the lower ones run on across the belly
                e = pts[-1] + Vector((0, -0.004, -0.010))
                N.add([e, V(s * 0.070, e.z - 0.045, 0.085), V(s * 0.012, e.z - 0.070, 0.095)], [0.0010, 0.0009, 0.0006], sub=5)
        r = roots["T12"]
        N.add([r, V(s * 0.100, 1.120, 0.0), V(s * 0.120, 1.060, 0.06), V(s * 0.030, 0.980, 0.095)], [0.0016, 0.0014, 0.0011, 0.0007], sub=6)
        # lumbar plexus
        for nm, pts in (("L1", [(0.090, 1.090, 0.0), (0.125, 1.040, 0.05), (0.050, 0.950, 0.09), (0.020, 0.920, 0.09)]),
                        ("L2", [(0.110, 1.050, 0.02), (0.146, 0.960, 0.03), (0.152, 0.800, 0.03), (0.140, 0.620, 0.03)]),   # lateral cutaneous nerve of the thigh
                        ("L3", [(0.050, 1.020, 0.0), (0.056, 0.940, 0.01), (0.050, 0.840, 0.02), (0.052, 0.720, 0.02)])):  # obturator
            ps = [roots[nm]] + [V(s * x, z, f) for (x, z, f) in pts]
            ps2, rs2 = N.add(ps, [0.0020] + [0.0018 - 0.0002 * k for k in range(len(pts))], sub=6)
            for j in range(4, len(ps2), 5):
                twigs(N, rng, ps2[j], (s * rng.choice((-1, 1)) * 0.8, -0.5), 0.05, 0.0010, 2)
        fem = V(s * 0.094, 0.950, 0.02)                                                    # femoral nerve: L2-L4, fanning out on the thigh
        for nm in ("L2", "L3", "L4"):
            r = roots[nm]
            N.add([r, (r + fem) * 0.5 + Vector((s * 0.01, 0, 0)), fem], [0.0024, 0.0024, 0.0028], sub=6)
        for j in range(7):
            a = -math.pi / 2 + (j - 3) * 0.20
            ex = 0.094 + (j - 3) * 0.017
            ps = N.add([fem, V(s * (0.094 + (j - 3) * 0.008), 0.880, 0.05), V(s * ex, 0.760 - abs(j - 3) * 0.02, 0.06), V(s * (ex - 0.006), 0.620 - abs(j - 3) * 0.03, 0.05)],
                       [0.0019, 0.0016, 0.0012, 0.0007], sub=5)[0]
            twigs(N, rng, ps[len(ps) // 2], (s * (j - 3) * 0.3, -1), 0.05, 0.0009, 2)
        run([(0.094, 0.950, 0.02), (0.078, 0.800, 0.05), (0.056, 0.640, 0.05), (0.050, 0.500, 0.04), (0.054, 0.340, 0.035), (0.058, 0.180, 0.03), (0.060, 0.080, 0.03)],
            0.0018, 0.0009, side=s, spacing=0.03, twig_len=0.04, depth=2)                   # saphenous
        # sacral plexus: L4-S3 gather into the sciatic nerve - the body's biggest - down the back of the thigh
        sc = V(s * 0.070, 0.930, -0.04)
        for nm in ("L4", "L5", "S1", "S2", "S3"):
            r = roots[nm]
            N.add([r, (r + sc) * 0.5 + Vector((s * 0.006, 0, 0)), sc], [0.0026, 0.0027, 0.0030], sub=6)
        for nm, (ex, ez) in (("S3", (0.020, 0.900)), ("S4", (0.012, 0.890)), ("S5", (0.006, 0.880))):   # pudendal and the pelvic floor
            r = roots[nm]
            ps = N.add([r, V(s * ex * 1.6, ez + 0.03, -0.02), V(s * ex, ez, 0.02)], [0.0014, 0.0012, 0.0008], sub=5)[0]
            twigs(N, rng, ps[-1], (s * 0.5, -0.8), 0.03, 0.0008, 2)
        run([(0.070, 0.930, -0.04), (0.092, 0.860, -0.05), (0.098, 0.740, -0.04), (0.094, 0.620, -0.04), (0.090, 0.530, -0.03)], 0.0052, 0.0044, side=s, spacing=0.03, twig_len=0.06)   # sciatic
        run([(0.090, 0.530, -0.03), (0.086, 0.440, -0.03), (0.076, 0.320, -0.03), (0.068, 0.180, -0.02), (0.064, 0.080, -0.01)], 0.0036, 0.0020, side=s, spacing=0.028, twig_len=0.04)   # tibial
        run([(0.090, 0.530, -0.03), (0.112, 0.470, -0.02), (0.124, 0.430, 0.0), (0.112, 0.380, 0.02)], 0.0030, 0.0024, side=s, spacing=0)                                               # common peroneal, round the fibula's neck
        run([(0.112, 0.380, 0.02), (0.100, 0.300, 0.03), (0.092, 0.180, 0.03), (0.084, 0.080, 0.03)], 0.0022, 0.0014, side=s, spacing=0.028, twig_len=0.035, depth=2)                   # deep peroneal
        run([(0.112, 0.380, 0.02), (0.120, 0.300, 0.015), (0.112, 0.180, 0.02), (0.098, 0.085, 0.03)], 0.0020, 0.0012, side=s, spacing=0.028, twig_len=0.035, depth=2)                  # superficial peroneal
        run([(0.086, 0.440, -0.03), (0.112, 0.320, -0.03), (0.112, 0.180, -0.02), (0.106, 0.080, -0.01)], 0.0016, 0.0010, side=s, spacing=0.03, twig_len=0.03, depth=2)                 # sural
        up = Vector((0, -0.86, 0.5))
        ank = V(s * ANKLE[0], ANKLE[1], ANKLE[2])
        d0 = foot_axis(s)
        fo = ank + d0 * 0.02 + up * 0.03
        N.add([V(s * 0.084, 0.080, 0.03), fo], [0.0014, 0.0014], sub=3)                     # (on over the ankle)
        N.add([V(s * 0.098, 0.085, 0.03), fo + Vector((s * 0.008, 0, 0))], [0.0012, 0.0012], sub=3)
        for k, (p, d, lens) in enumerate(foot_rays(s)):
            tip = p + d * sum(lens)
            sv = Vector((d.z, 0, -d.x)).normalized() * (0.0048 if k == 0 else 0.003)
            for sg in (-1, 1):
                N.add([ank + d0 * 0.02 + up * 0.03, p + d * 0.02 + up * 0.016 + sv * sg, tip - d * 0.004 + up * 0.008 + sv * sg * 0.6], [0.0013, 0.0011, 0.0005], sub=4)
    # the solar plexus: a knot of ganglia before the aorta, radiating
    for j in range(16):
        a = j / 16.0 * math.tau
        twigs(N, rng, V(0.004, 1.236, 0.02), (math.cos(a), math.sin(a)), rng.uniform(0.035, 0.075), 0.0013, 2,
              keep=lambda x, z: (x / 0.11) ** 2 + ((z - 1.20) / 0.11) ** 2 < 1.0, f_jitter=0.02)
    gang.ell(V(0.014, 1.238, 0.02), (0.008, 0.005, 0.006)).ell(V(-0.008, 1.236, 0.02), (0.008, 0.005, 0.006))
    gang.finish("ganglia", cmat, raw=True)
    print("nerves:", N.n)
