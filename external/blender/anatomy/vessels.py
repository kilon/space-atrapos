# The vessels (layer 2): the heart, the arteries (red) and the veins (blue) -
# the great vessels, the trees through the head, the limbs and the lungs, the
# kidneys - with fine branches everywhere. See common.py.
import math, random
from mathutils import Vector
from common import V, Shape, Tubes, plain, inside_body, twigs, hand_rays, foot_rays, foot_axis, ANKLE, _mats, _new, _set
import skeleton


def vessel_mat(name, col):
    if name in _mats:
        return _mats[name]
    return plain(name, col, rough=0.28, sss=0.25, coat=0.5, bump=0.12, bump_scale=260.0, vary=0.22)


def heart_mat():
    """The heart: dark red muscle, yellow fat along its grooves and round its base."""
    if "heart" in _mats:
        return _mats["heart"]
    m, nt, b = _new("heart")
    _set(b, rough=0.3, sss=0.2, coat=0.5)
    b.inputs["Subsurface Radius"].default_value = (0.02, 0.008, 0.005)
    b.inputs["Subsurface Scale"].default_value = 0.2
    N, L = nt.nodes.new, nt.links.new
    tc = N("ShaderNodeTexCoord")
    nz = N("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 38.0
    nz.inputs["Detail"].default_value = 6.0
    L(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = N("ShaderNodeValToRGB")
    e = ramp.color_ramp.elements
    e[0].position = 0.40; e[0].color = (0.30, 0.035, 0.03, 1)
    e[1].position = 0.62; e[1].color = (0.52, 0.09, 0.06, 1)
    e2 = ramp.color_ramp.elements.new(0.70); e2.color = (0.80, 0.62, 0.30, 1)
    e3 = ramp.color_ramp.elements.new(0.78); e3.color = (0.88, 0.74, 0.40, 1)
    L(nz.outputs["Fac"], ramp.inputs[0])
    L(ramp.outputs[0], b.inputs["Base Color"])
    fine = N("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 420.0
    L(tc.outputs["Object"], fine.inputs["Vector"])
    bp = N("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.3
    bp.inputs["Distance"].default_value = 0.0015
    L(fine.outputs["Fac"], bp.inputs["Height"])
    L(bp.outputs["Normal"], b.inputs["Normal"])
    _mats["heart"] = m
    return m


def in_lung(x, z):
    s = 1 if x > 0 else -1
    ax = abs(x)
    if ((ax - 0.086) / 0.062) ** 2 + ((z - 1.335) / 0.120) ** 2 >= 1.0:
        return False
    if ax < 0.022:
        return False
    # (the heart's bed: more of it out of the left lung)
    hx, hr = (0.026, 0.050) if s > 0 else (-0.012, 0.036)
    if ((x - hx) / hr) ** 2 + ((z - 1.332) / 0.058) ** 2 < 1.0:
        return False
    return True


def lung_tree(tubes, rng, p, d, length, radius, depth):
    """A bronchial-like tree of vessels filling a lung: each branch forks in two."""
    q = Vector((p.x + d[0] * length, p.y + rng.uniform(-0.012, 0.012), p.z + d[1] * length))
    if not in_lung(q.x, q.z):
        q = Vector((p.x + d[0] * length * 0.5, p.y, p.z + d[1] * length * 0.5))
        if not in_lung(q.x, q.z):
            return
    mid = (p + q) * 0.5 + Vector((rng.uniform(-1, 1), 0, rng.uniform(-1, 1))) * length * 0.08
    tubes.add([p, mid, q], [radius, radius * 0.9, radius * 0.78], sub=3)
    if depth <= 0:
        return
    for sign in (-1, 1):
        a = sign * rng.uniform(0.35, 0.80)
        nd = (d[0] * math.cos(a) - d[1] * math.sin(a), d[0] * math.sin(a) + d[1] * math.cos(a))
        lung_tree(tubes, rng, q, nd, length * rng.uniform(0.70, 0.86), radius * 0.76, depth - 1)


def build():
    rng = random.Random(11)
    art = Tubes("arteries", vessel_mat("artery", (0.62, 0.025, 0.02)), bevel_res=5)
    ven = Tubes("veins", vessel_mat("vein", (0.06, 0.16, 0.52)), bevel_res=5)

    def run(tubes, pts, r0, r1, side=1, f=0.0, spacing=0.035, twig_len=0.05, depth=3, twig_r=0.0018):
        """A vessel through `pts` ((x, z) or (x, z, f)) tapering r0 -> r1, with side branches every `spacing`."""
        P = [V(side * p[0], p[1], (p[2] if len(p) > 2 else 0.0) + f) for p in pts]
        n = len(P)
        radii = [r0 + (r1 - r0) * i / (n - 1.0) for i in range(n)]
        ps, rs = tubes.add(P, radii, sub=6)
        if spacing <= 0:
            return ps
        acc = 0.0
        for i in range(1, len(ps)):
            seg = ps[i] - ps[i - 1]
            acc += seg.length
            if acc >= spacing * 0.7:
                acc = 0.0
                t = Vector((seg.x, seg.z))
                if t.length < 1e-6:
                    continue
                t.normalize()
                a = rng.choice((-1, 1)) * rng.uniform(0.6, 1.3)
                nd = (t.x * math.cos(a) - t.y * math.sin(a), t.x * math.sin(a) + t.y * math.cos(a))
                twigs(tubes, rng, ps[i], nd, twig_len * rng.uniform(0.6, 1.3), min(rs[i] * 0.55, twig_r), depth)
        return ps

    # --- the heart ---
    hs = Shape()
    hs.ell(V(0.024, 1.334, 0.048), (0.044, 0.040, 0.060), rot=(0, 0.50, 0))       # left ventricle, the apex down and to its left
    hs.ell(V(-0.004, 1.336, 0.066), (0.036, 0.026, 0.050), rot=(0, 0.50, 0))      # right ventricle
    hs.ell(V(-0.032, 1.378, 0.044), (0.024, 0.026, 0.030))                        # right atrium
    hs.ell(V(0.046, 1.388, 0.040), (0.014, 0.014, 0.017))                         # left auricle
    hs.ell(V(0.008, 1.384, 0.040), (0.036, 0.026, 0.020))                         # its base
    hs.finish("heart", heart_mat(), voxel=0.0022, smooth=10)
    cor_a = Tubes("coronary_a", vessel_mat("artery", (0.62, 0.025, 0.02)), bevel_res=4)
    cor_v = Tubes("coronary_v", vessel_mat("vein", (0.06, 0.16, 0.52)), bevel_res=4)
    in_heart = lambda x, z: ((x - 0.016) / 0.052) ** 2 + ((z - 1.338) / 0.062) ** 2 < 1.0
    def on_heart(tubes, pts, r0, r1, n_twigs=5):
        P = [V(p[0], p[1], p[2]) for p in pts]
        ps, rs = tubes.add(P, [r0 + (r1 - r0) * i / (len(P) - 1.0) for i in range(len(P))], sub=6)
        for k in range(n_twigs):
            i = rng.randint(2, len(ps) - 2)
            a = rng.choice((-1, 1)) * rng.uniform(0.7, 1.4)
            t = ps[i] - ps[i - 1]
            t = Vector((t.x, t.z)).normalized()
            nd = (t.x * math.cos(a) - t.y * math.sin(a), t.x * math.sin(a) + t.y * math.cos(a))
            twigs(tubes, rng, ps[i] + Vector((0, -0.002, 0)), nd, rng.uniform(0.02, 0.04), rs[i] * 0.6, 1, keep=in_heart, f_jitter=0.0)
    on_heart(cor_a, [(0.018, 1.386, 0.074), (0.024, 1.350, 0.092), (0.036, 1.315, 0.090), (0.052, 1.288, 0.072)], 0.0030, 0.0014, 7)   # anterior descending
    on_heart(cor_a, [(-0.002, 1.388, 0.066), (-0.028, 1.366, 0.078), (-0.036, 1.336, 0.080), (-0.022, 1.306, 0.082)], 0.0028, 0.0014, 6)   # right coronary
    on_heart(cor_a, [(0.020, 1.386, 0.070), (0.048, 1.372, 0.066), (0.062, 1.340, 0.058)], 0.0024, 0.0012, 4)                           # circumflex
    on_heart(cor_v, [(0.026, 1.384, 0.074), (0.032, 1.348, 0.090), (0.044, 1.314, 0.086), (0.056, 1.292, 0.070)], 0.0030, 0.0015, 5)     # great cardiac vein
    on_heart(cor_v, [(-0.018, 1.374, 0.076), (-0.020, 1.340, 0.086), (-0.010, 1.308, 0.086)], 0.0022, 0.0012, 4)

    # --- the great vessels ---
    run(art, [(0.000, 1.384, 0.046), (-0.010, 1.418, 0.044), (0.004, 1.442, 0.026), (0.026, 1.432, -0.006), (0.022, 1.390, -0.030),
              (0.014, 1.300, -0.034), (0.010, 1.180, -0.026), (0.006, 1.066, -0.016)], 0.0140, 0.0088, spacing=0)                       # the aorta
    run(ven, [(0.006, 1.384, 0.066), (0.016, 1.408, 0.056), (0.022, 1.418, 0.036)], 0.0125, 0.0115, spacing=0)                         # pulmonary trunk
    run(ven, [(0.022, 1.418, 0.036), (0.046, 1.408, 0.020), (0.060, 1.398, 0.010)], 0.0100, 0.0085, spacing=0)                         # ... to the left lung
    run(ven, [(0.022, 1.418, 0.036), (-0.012, 1.404, 0.006), (-0.050, 1.392, 0.004)], 0.0100, 0.0085, spacing=0)                       # ... to the right
    for s in (-1, 1):
        run(art, [(s * 0.060, 1.372, 0.0), (s * 0.034, 1.374, -0.006), (0.012, 1.376, -0.010)], 0.0058, 0.0070, spacing=0)             # pulmonary veins
        run(art, [(s * 0.064, 1.342, 0.0), (s * 0.036, 1.356, -0.006), (0.012, 1.366, -0.010)], 0.0052, 0.0064, spacing=0)
    run(ven, [(-0.032, 1.388, 0.040), (-0.032, 1.415, 0.034), (-0.032, 1.440, 0.030)], 0.0118, 0.0105, spacing=0)                      # superior vena cava
    run(ven, [(-0.032, 1.440, 0.030), (-0.038, 1.456, 0.030), (-0.046, 1.472, 0.030)], 0.0090, 0.0082, spacing=0)                      # brachiocephalic veins
    run(ven, [(-0.032, 1.440, 0.030), (0.006, 1.452, 0.050), (0.046, 1.472, 0.034)], 0.0088, 0.0080, spacing=0)
    run(ven, [(-0.026, 1.352, 0.006), (-0.024, 1.290, -0.008), (-0.022, 1.180, -0.012), (-0.018, 1.068, -0.008)], 0.0125, 0.0105, spacing=0)   # inferior vena cava
    run(art, [(-0.002, 1.442, 0.030), (-0.016, 1.458, 0.028), (-0.030, 1.472, 0.024)], 0.0085, 0.0075, spacing=0)                      # brachiocephalic trunk
    # --- head and neck ---
    for s in (-1, 1):
        c0 = (-0.030, 1.472, 0.024) if s < 0 else (0.012, 1.444, 0.026)
        run(art, [c0, (s * 0.030, 1.520, 0.020), (s * 0.032, 1.566, 0.018), (s * 0.034, 1.604, 0.016)], 0.0060, 0.0050, spacing=0.03, twig_len=0.03)   # common carotid
        run(art, [(s * 0.034, 1.604, 0.016), (s * 0.030, 1.640, 0.006), (s * 0.026, 1.672, -0.004), (s * 0.016, 1.700, -0.01)], 0.0040, 0.0026, f=-0.01, spacing=0.02, twig_len=0.05, depth=3)   # internal carotid
        run(art, [(s * 0.034, 1.604, 0.016), (s * 0.048, 1.622, 0.03), (s * 0.058, 1.648, 0.03), (s * 0.068, 1.690, 0.02), (s * 0.064, 1.740, 0.03), (s * 0.048, 1.776, 0.03)],
            0.0036, 0.0014, spacing=0.016, twig_len=0.055, depth=3)                                                                     # external carotid, superficial temporal
        run(art, [(s * 0.046, 1.618, 0.05), (s * 0.040, 1.632, 0.07), (s * 0.026, 1.646, 0.085), (s * 0.016, 1.676, 0.09), (s * 0.014, 1.706, 0.085)],
            0.0024, 0.0010, spacing=0.012, twig_len=0.035, depth=2)                                                                     # facial artery
        run(art, [(s * 0.050, 1.626, 0.04), (s * 0.036, 1.612, 0.07), (s * 0.014, 1.604, 0.085)], 0.0018, 0.0009, spacing=0.012, twig_len=0.02, depth=1)   # to the chin
        run(ven, [(s * 0.046, 1.472, 0.032), (s * 0.044, 1.520, 0.034), (s * 0.045, 1.570, 0.030), (s * 0.050, 1.622, 0.022)], 0.0078, 0.0058, spacing=0.035, twig_len=0.03)   # internal jugular
        run(ven, [(s * 0.050, 1.622, 0.022), (s * 0.060, 1.660, 0.03), (s * 0.072, 1.704, 0.02), (s * 0.060, 1.756, 0.03)], 0.0034, 0.0014, f=0.01, spacing=0.016, twig_len=0.05, depth=3)
        run(ven, [(s * 0.062, 1.632, 0.030), (s * 0.066, 1.570, 0.030), (s * 0.070, 1.500, 0.036), (s * 0.075, 1.474, 0.036)], 0.0034, 0.0040, f=0.012, spacing=0.03, twig_len=0.03, depth=1)   # external jugular
        run(ven, [(s * 0.050, 1.622, 0.05), (s * 0.044, 1.640, 0.075), (s * 0.030, 1.660, 0.088), (s * 0.022, 1.690, 0.09), (s * 0.012, 1.730, 0.08)],
            0.0026, 0.0010, spacing=0.014, twig_len=0.03, depth=2)                                                                      # facial vein
        # --- shoulder and arm ---
        a0 = (-0.030, 1.472, 0.024) if s < 0 else (0.020, 1.442, 0.010)
        run(art, [a0, (s * 0.070, 1.482, 0.03), (s * 0.125, 1.474, 0.025), (s * 0.172, 1.446, 0.01)], 0.0066, 0.0058, spacing=0.03, twig_len=0.05)     # subclavian
        run(art, [(s * 0.172, 1.446, 0.01), (s * 0.198, 1.350, 0.01), (s * 0.214, 1.250, 0.01), (s * 0.232, 1.166, 0.012)], 0.0056, 0.0044, spacing=0.028, twig_len=0.06)   # brachial
        ra = run(art, [(s * 0.232, 1.166, 0.012), (s * 0.256, 1.090, 0.014), (s * 0.276, 1.000, 0.012), (s * 0.294, 0.928, 0.010), (s * 0.300, 0.900, 0.010)], 0.0034, 0.0024, spacing=0.03, twig_len=0.04)   # radial
        ul = run(art, [(s * 0.232, 1.166, 0.012), (s * 0.236, 1.090, 0.008), (s * 0.252, 1.000, 0.008), (s * 0.270, 0.930, 0.008), (s * 0.274, 0.898, 0.010)], 0.0034, 0.0024, spacing=0.03, twig_len=0.04)   # ulnar
        run(art, [(s * 0.300, 0.900, 0.010), (s * 0.296, 0.878, 0.012), (s * 0.284, 0.868, 0.012), (s * 0.274, 0.880, 0.010), (s * 0.274, 0.898, 0.010)], 0.0022, 0.0020, spacing=0)   # palmar arch
        run(ven, [(s * 0.046, 1.472, 0.034), (s * 0.090, 1.470, 0.036), (s * 0.130, 1.464, 0.03), (s * 0.176, 1.438, 0.016)], 0.0074, 0.0062, f=0.008, spacing=0.035, twig_len=0.04)   # subclavian vein
        run(ven, [(s * 0.176, 1.438, 0.016), (s * 0.192, 1.340, 0.018), (s * 0.206, 1.240, 0.018), (s * 0.220, 1.160, 0.02), (s * 0.240, 1.060, 0.02), (s * 0.262, 0.950, 0.016)],
            0.0054, 0.0026, f=0.01, spacing=0.03, twig_len=0.05)                                                                        # basilic
        run(ven, [(s * 0.150, 1.462, 0.03), (s * 0.196, 1.420, 0.05), (s * 0.228, 1.330, 0.04), (s * 0.246, 1.240, 0.035), (s * 0.258, 1.170, 0.03), (s * 0.282, 1.060, 0.028), (s * 0.300, 0.940, 0.016)],
            0.0044, 0.0026, f=0.012, spacing=0.03, twig_len=0.05)                                                                       # cephalic
        run(ven, [(s * 0.254, 1.196, 0.036), (s * 0.238, 1.166, 0.036), (s * 0.222, 1.146, 0.032)], 0.0030, 0.0028, f=0.012, spacing=0)   # median cubital
        run(ven, [(s * 0.238, 1.150, 0.03), (s * 0.252, 1.060, 0.03), (s * 0.270, 0.980, 0.02), (s * 0.282, 0.925, 0.016)], 0.0026, 0.0020, f=0.012, spacing=0.03, twig_len=0.03, depth=1)   # median antebrachial
        for k, (p, d, lens) in enumerate(hand_rays(s)):
            tip = p + d * sum(lens)
            side_v = Vector((d.z, 0, -d.x)) * 0.0042
            fwd = Vector((0, -0.006, 0))
            for sg, tubes in ((-1, art), (1, ven)):
                a = p + d * (lens[0] * (0.2 if k == 0 else 0.55)) + side_v * sg + fwd
                tubes.add([a, (a + tip + side_v * sg) * 0.5 + fwd, tip + side_v * sg * 0.6 + fwd - d * 0.004], [0.0015, 0.0012, 0.0006], sub=4)
            tubes = art
            tubes.add([tip - d * 0.012 - side_v + fwd, tip - d * 0.003 + fwd, tip - d * 0.012 + side_v + fwd], [0.0007, 0.0006, 0.0007], sub=4)   # the fingertip's loop
        # --- trunk ---
        for i in range(1, 11):
            pts = skeleton.rib_path(i, s)
            art.add([p + Vector((0, -0.003, -0.0075)) for p in pts], [0.0019] * (len(pts) - 1) + [0.0010], sub=8)   # intercostals: an artery and a vein under each rib
            ven.add([p + Vector((0, -0.003, -0.0125)) for p in pts], [0.0021] * (len(pts) - 1) + [0.0011], sub=8)
        run(art, [(s * 0.028, 1.468, 0.07), (s * 0.026, 1.380, 0.085), (s * 0.030, 1.290, 0.085), (s * 0.036, 1.180, 0.09), (s * 0.040, 1.100, 0.09)], 0.0024, 0.0014, spacing=0.03, twig_len=0.035, depth=1)   # internal thoracic, epigastric
        run(ven, [(s * 0.034, 1.468, 0.07), (s * 0.032, 1.380, 0.085), (s * 0.036, 1.290, 0.085), (s * 0.042, 1.180, 0.09)], 0.0024, 0.0014, spacing=0.035, twig_len=0.03, depth=1)
        run(art, [(s * 0.076, 0.962, 0.05), (s * 0.056, 1.030, 0.085), (s * 0.044, 1.100, 0.09)], 0.0022, 0.0014, spacing=0.025, twig_len=0.03, depth=1)   # inferior epigastric
        run(ven, [(s * 0.090, 0.930, 0.05), (s * 0.120, 1.000, 0.08), (s * 0.135, 1.080, 0.08), (s * 0.140, 1.180, 0.08)], 0.0020, 0.0012, f=0.01, spacing=0.03, twig_len=0.04, depth=2)   # the flank's surface veins
        # kidneys
        kz = 1.186 if s > 0 else 1.172
        run(art, [(0.010, kz + 0.008, -0.024), (s * 0.036, kz + 0.006, -0.026), (s * 0.058, kz, -0.028)], 0.0042, 0.0036, spacing=0)
        run(ven, [(-0.022, kz - 0.004, -0.010), (s * 0.034, kz - 0.006, -0.016), (s * 0.058, kz - 0.008, -0.022)], 0.0050, 0.0040, spacing=0)
        for k in range(5):
            a = -0.9 + k * 0.45
            twigs(art, rng, V(s * 0.060, kz, -0.022), (s * math.cos(a), math.sin(a)), 0.032, 0.0020, 2,
                  keep=lambda x, z, s=s, kz=kz: ((abs(x) - 0.078) / 0.030) ** 2 + ((z - kz) / 0.052) ** 2 < 1.0)
        # --- pelvis and leg ---
        run(art, [(0.006, 1.066, -0.016), (s * 0.040, 1.010, 0.0), (s * 0.072, 0.960, 0.02), (s * 0.088, 0.932, 0.036)], 0.0082, 0.0072, spacing=0.03, twig_len=0.04)   # iliac
        run(art, [(s * 0.040, 1.010, 0.0), (s * 0.046, 0.970, -0.02), (s * 0.036, 0.930, -0.02)], 0.0048, 0.0030, spacing=0.012, twig_len=0.045, depth=3)               # internal iliac
        run(art, [(s * 0.088, 0.932, 0.036), (s * 0.082, 0.820, 0.045), (s * 0.074, 0.680, 0.03), (s * 0.080, 0.540, -0.01), (s * 0.090, 0.456, -0.02)], 0.0074, 0.0054, spacing=0.028, twig_len=0.07)   # femoral, popliteal
        run(art, [(s * 0.090, 0.890, 0.03), (s * 0.110, 0.800, 0.02), (s * 0.122, 0.700, 0.01), (s * 0.120, 0.600, 0.0)], 0.0046, 0.0024, spacing=0.022, twig_len=0.07, depth=3)                        # deep femoral
        run(art, [(s * 0.090, 0.456, -0.02), (s * 0.098, 0.400, 0.01), (s * 0.098, 0.280, 0.02), (s * 0.088, 0.150, 0.02), (s * 0.082, 0.070, 0.03)], 0.0040, 0.0026, spacing=0.028, twig_len=0.04)   # anterior tibial
        run(art, [(s * 0.090, 0.456, -0.02), (s * 0.078, 0.380, -0.02), (s * 0.068, 0.240, -0.02), (s * 0.062, 0.090, -0.01)], 0.0040, 0.0024, f=-0.004, spacing=0.03, twig_len=0.04)                 # posterior tibial
        run(art, [(s * 0.094, 0.420, -0.02), (s * 0.108, 0.320, -0.02), (s * 0.110, 0.180, -0.02)], 0.0028, 0.0016, f=-0.004, spacing=0.03, twig_len=0.03)                                                # peroneal
        run(ven, [(-0.018, 1.068, -0.008), (s * 0.044, 1.000, 0.006), (s * 0.070, 0.955, 0.024), (s * 0.080, 0.930, 0.038)], 0.0090, 0.0078, f=0.006, spacing=0.035, twig_len=0.04)   # iliac vein
        run(ven, [(s * 0.080, 0.930, 0.038), (s * 0.072, 0.820, 0.045), (s * 0.066, 0.680, 0.03), (s * 0.074, 0.540, -0.01), (s * 0.086, 0.450, -0.02)], 0.0078, 0.0054, f=0.006, spacing=0.03, twig_len=0.06)   # femoral vein
        run(ven, [(s * 0.076, 0.905, 0.05), (s * 0.050, 0.780, 0.06), (s * 0.038, 0.640, 0.05), (s * 0.040, 0.500, 0.04), (s * 0.050, 0.340, 0.03), (s * 0.056, 0.180, 0.03), (s * 0.058, 0.080, 0.03)],
            0.0040, 0.0026, f=0.012, spacing=0.028, twig_len=0.06)                                                                       # great saphenous
        run(ven, [(s * 0.086, 0.450, -0.02), (s * 0.092, 0.340, 0.015), (s * 0.090, 0.200, 0.02), (s * 0.084, 0.090, 0.025)], 0.0040, 0.0026, f=0.006, spacing=0.03, twig_len=0.04)   # tibial veins
        run(ven, [(s * 0.112, 0.420, -0.01), (s * 0.118, 0.300, -0.01), (s * 0.108, 0.150, 0.0), (s * 0.104, 0.080, 0.01)], 0.0030, 0.0020, f=0.008, spacing=0.03, twig_len=0.04)     # small saphenous
        # the foot: the artery over its top, the arch, a pair to each toe; the veins' arch
        d0 = foot_axis(s)
        up = Vector((0, -0.86, 0.5))
        ank = V(s * ANKLE[0], ANKLE[1], ANKLE[2])
        rays = foot_rays(s)
        art.add([V(s * 0.082, 0.070, 0.03), ank + d0 * 0.02 + up * 0.03, ank + d0 * 0.07 + up * 0.03, rays[0][0] + rays[0][1] * 0.02 + up * 0.018], [0.0026, 0.0024, 0.0020, 0.0016], sub=5)
        art.add([r[0] + r[1] * 0.03 + up * 0.015 for r in rays], 0.0015, sub=5)
        ven.add([V(s * 0.058, 0.080, 0.03)] + [r[0] + r[1] * 0.016 + up * 0.019 for r in rays] + [V(s * 0.104, 0.080, 0.01)], 0.0019, sub=5)
        for k, (p, d, lens) in enumerate(rays):
            tip = p + d * sum(lens)
            sv = Vector((d.z, 0, -d.x)).normalized() * (0.005 if k == 0 else 0.0032)
            art.add([p + d * 0.03 + up * 0.015 - sv, tip - d * 0.004 + up * 0.008 - sv * 0.5], [0.0012, 0.0006], sub=3)
            ven.add([p + d * 0.016 + up * 0.019 + sv, tip - d * 0.006 + up * 0.009 + sv * 0.5], [0.0013, 0.0006], sub=3)
    # --- the gut's vessels: the trunks off the aorta, fanning out ---
    for (z, n, ln, spread) in ((1.238, 7, 0.060, 2.6), (1.205, 11, 0.085, 2.2), (1.125, 6, 0.060, 1.8)):
        for k in range(n):
            a = -math.pi / 2 + (k / (n - 1.0) - 0.5) * spread
            twigs(art, rng, V(0.008, z, 0.0), (math.cos(a), math.sin(a)), ln * rng.uniform(0.8, 1.2), 0.0026, 3,
                  keep=lambda x, z2: (x / 0.105) ** 2 + ((z2 - 1.14) / 0.125) ** 2 < 1.0, f_jitter=0.03)
            twigs(ven, rng, V(-0.016, z - 0.012, 0.012), (math.cos(a + 0.2), math.sin(a + 0.2)), ln * rng.uniform(0.8, 1.2), 0.0028, 3,
                  keep=lambda x, z2: (x / 0.105) ** 2 + ((z2 - 1.14) / 0.125) ** 2 < 1.0, f_jitter=0.03)
    # --- the lungs: two trees each ---
    for s in (-1, 1):
        for tubes, (hx, hz), seed in ((ven, (0.066, 1.402), 3), (art, (0.070, 1.384), 5)):
            r2 = random.Random(seed + (10 if s > 0 else 0))
            for a in (-1.45, -0.95, -0.45, 0.10, 0.60, 1.10):
                lung_tree(tubes, r2, V(s * hx, hz, 0.0), (s * math.cos(a), math.sin(a)), 0.036, 0.0046, 7)
    # --- the kidneys ---
    ks = Shape()
    for s in (-1, 1):
        kz = 1.186 if s > 0 else 1.172
        ks.ell(V(s * 0.080, kz, -0.034), (0.026, 0.020, 0.050))
        ks.ell(V(s * 0.072, kz + 0.028, -0.034), (0.022, 0.018, 0.026))
        ks.ell(V(s * 0.072, kz - 0.028, -0.034), (0.022, 0.018, 0.026))
    ks.finish("kidneys", plain("kidney", (0.36, 0.09, 0.06), rough=0.3, sss=0.25, coat=0.5, bump=0.2, bump_scale=200.0, vary=0.2), voxel=0.002, smooth=4)
    print("vessels:", art.n, "arteries,", ven.n, "veins")
