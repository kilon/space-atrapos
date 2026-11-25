# The muscles (layer 1): the superficial muscles of the front of the body,
# each a bundle of fibres swept along its path from origin to insertion (its
# tendons pale at the ends), laid on the body's surface (surf()), over a dark
# underlayer (the deep tissue seen between them). See common.py.
import bpy, bmesh, math, random
from mathutils import Vector
from common import V, Shape, plain, smooth_path, _mats, _new, _set, hand_rays, foot_rays, foot_axis, ANKLE

# The body under the muscles: ("ell", (x, z, f), (rx, rf, rz)) / ("cap", (x, z, f), (x, z, f), ra, rb) - for the
# left side and the middle; mirrored. Muscles lie on its front (surf()).
DEEP_MID = [
    ("ell", (0, 1.705, -0.005), (0.072, 0.088, 0.088)), ("ell", (0, 1.660, 0.040), (0.052, 0.050, 0.062)),
    ("ell", (0, 1.612, 0.036), (0.045, 0.042, 0.036)), ("cap", (0, 1.600, -0.012), (0, 1.490, -0.006), 0.046, 0.056),
    ("ell", (0, 1.360, -0.010), (0.158, 0.105, 0.135)), ("ell", (0, 1.170, 0.000), (0.136, 0.092, 0.125)),
    ("ell", (0, 1.000, -0.005), (0.156, 0.098, 0.105)),
]
DEEP_SIDE = [
    ("ell", (0.165, 1.435, -0.005), (0.056, 0.058, 0.052)),
    ("cap", (0.196, 1.420, 0.0), (0.235, 1.190, 0.0), 0.043, 0.035),
    ("cap", (0.236, 1.170, 0.0), (0.283, 0.930, 0.0), 0.036, 0.021),
    ("ell", (0.292, 0.868, 0.0), (0.036, 0.011, 0.048)),
    ("cap", (0.104, 0.930, 0.0), (0.089, 0.530, 0.0), 0.080, 0.052),
    ("ell", (0.090, 0.500, 0.005), (0.048, 0.045, 0.045)),
    ("cap", (0.087, 0.460, 0.0), (0.078, 0.110, 0.0), 0.050, 0.030),
    ("cap", (0.080, 0.050, 0.012), (0.106, -0.062, 0.078), 0.031, 0.036),
]


def _prims():
    out = list(DEEP_MID)
    for s in (1, -1):
        for p in DEEP_SIDE:
            if p[0] == "ell":
                out.append(("ell", (s * p[1][0], p[1][1], p[1][2]), p[2]))
            else:
                out.append(("cap", (s * p[1][0], p[1][1], p[1][2]), (s * p[2][0], p[2][1], p[2][2]), p[3], p[4]))
    return out


PRIMS = _prims()


def surf(x, z):
    """How far forward the body's front surface is at (x, z) - None off the body."""
    best = None
    for p in PRIMS:
        if p[0] == "ell":
            (cx, cz, cf), (rx, rf, rz) = p[1], p[2]
            d = ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2
            if d < 1.0:
                f = cf + rf * math.sqrt(1.0 - d)
                best = f if best is None else max(best, f)
        else:
            (ax, az, af), (bx, bz, bf), ra, rb = p[1], p[2], p[3], p[4]
            dx, dz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            r = ra + (rb - ra) * t
            d2 = (x - (ax + dx * t)) ** 2 + (z - (az + dz * t)) ** 2
            if d2 < r * r:
                f = af + (bf - af) * t + math.sqrt(r * r - d2)
                best = f if best is None else max(best, f)
    return best


def muscle_mat():
    """Muscle: fine fibres along its length (dark to bright red, by the mesh's
    UV: u along, v across), pale glistening tendon where the "tend" vertex
    colour says so; wet."""
    if "muscle" in _mats:
        return _mats["muscle"]
    m, nt, b = _new("muscle")
    _set(b, rough=0.36, sss=0.18, coat=0.35)
    b.inputs["Subsurface Radius"].default_value = (0.02, 0.006, 0.004)
    b.inputs["Subsurface Scale"].default_value = 0.25
    b.inputs["Coat Roughness"].default_value = 0.15
    N = nt.nodes.new
    L = nt.links.new
    uv = N("ShaderNodeUVMap")
    sep = N("ShaderNodeSeparateXYZ")
    L(uv.outputs["UV"], sep.inputs[0])
    info = N("ShaderNodeObjectInfo")
    att = N("ShaderNodeVertexColor")
    att.layer_name = "tend"
    sepc = N("ShaderNodeSeparateColor")
    L(att.outputs["Color"], sepc.inputs[0])   # R: tendon, G: this bundle's shade, B: its fibre count
    # Fibres: noise stretched along the length (it varies fast across, slowly along).
    def fibres(scale_v, scale_u, detail):
        comb = N("ShaderNodeCombineXYZ")
        mu = N("ShaderNodeMath"); mu.operation = "MULTIPLY"; mu.inputs[1].default_value = scale_u
        mv = N("ShaderNodeMath"); mv.operation = "MULTIPLY"; mv.inputs[1].default_value = scale_v
        L(sep.outputs["X"], mu.inputs[0])
        L(sep.outputs["Y"], mv.inputs[0])
        L(mu.outputs[0], comb.inputs["X"])
        L(mv.outputs[0], comb.inputs["Y"])
        L(sepc.outputs["Green"], comb.inputs["Z"])
        nz = N("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = detail
        nz.inputs["Roughness"].default_value = 0.6
        L(comb.outputs[0], nz.inputs["Vector"])
        return nz
    coarse = fibres(34.0, 1.6, 3.0)
    fine = fibres(150.0, 3.0, 2.0)
    mixf = N("ShaderNodeMath"); mixf.operation = "ADD"
    half = N("ShaderNodeMath"); half.operation = "MULTIPLY"; half.inputs[1].default_value = 0.45
    L(fine.outputs["Fac"], half.inputs[0])
    L(coarse.outputs["Fac"], mixf.inputs[0])
    L(half.outputs[0], mixf.inputs[1])
    red = N("ShaderNodeValToRGB")
    e = red.color_ramp.elements
    e[0].position = 0.42; e[0].color = (0.18, 0.012, 0.010, 1)
    e[1].position = 0.92; e[1].color = (0.80, 0.16, 0.10, 1)
    e2 = red.color_ramp.elements.new(0.68); e2.color = (0.52, 0.045, 0.035, 1)
    L(mixf.outputs[0], red.inputs[0])
    pale = N("ShaderNodeValToRGB")
    pe = pale.color_ramp.elements
    pe[0].position = 0.40; pe[0].color = (0.62, 0.55, 0.46, 1)
    pe[1].position = 0.90; pe[1].color = (0.97, 0.94, 0.86, 1)
    L(mixf.outputs[0], pale.inputs[0])
    # Each bundle a little lighter or darker than its neighbours.
    shade = N("ShaderNodeMapRange")
    shade.inputs["To Min"].default_value = 0.78
    shade.inputs["To Max"].default_value = 1.12
    L(sepc.outputs["Green"], shade.inputs["Value"])
    tint = N("ShaderNodeMixRGB"); tint.blend_type = "MULTIPLY"; tint.inputs[0].default_value = 1.0
    L(red.outputs[0], tint.inputs[1])
    L(shade.outputs[0], tint.inputs[2])
    mix = N("ShaderNodeMixRGB")
    L(sepc.outputs["Red"], mix.inputs[0])
    L(tint.outputs[0], mix.inputs[1])
    L(pale.outputs[0], mix.inputs[2])
    L(mix.outputs[0], b.inputs["Base Color"])
    rr = N("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = 0.40
    rr.inputs["To Max"].default_value = 0.24
    L(sepc.outputs["Red"], rr.inputs["Value"])
    L(rr.outputs[0], b.inputs["Roughness"])
    bp = N("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.55
    bp.inputs["Distance"].default_value = 0.0016
    L(mixf.outputs[0], bp.inputs["Height"])
    L(bp.outputs["Normal"], b.inputs["Normal"])
    _mats["muscle"] = m
    return m


class Flesh:
    """Every muscle bundle of the layer in one mesh."""

    def __init__(self, seed=7):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.color.new("tend")
        self.rng = random.Random(seed)

    def bundle(self, pts, widths, thick=0.008, tend=(0.10, 0.10), lift=0.0, side=1, world=False, ring=12, sub=7, shade=None, blunt=(False, False)):
        """A bundle through `pts` ((x, z) on the body's surface, or (x, z, extra lift); with `world`, Vectors):
        half-width `widths` (one, or one a point) across, half-thickness `thick` deep; `tend`: the share of
        its length that is tendon at each end (1, 1: all of it - a ligament, a sheet of fascia); `blunt`: that
        end stays its full width (a sheet's edge at its origin) instead of closing to a point."""
        if isinstance(widths, (int, float)):
            widths = [widths] * len(pts)
        if isinstance(thick, (int, float)):
            thick = [thick] * len(pts)
        P = []
        for i, p in enumerate(pts):
            if world:
                P.append(Vector((p.x * side, p.y, p.z)))
                continue
            x, z = p[0] * side, p[1]
            f = surf(x, z)
            f = 0.0 if f is None else f
            P.append(V(x, z, f + lift + (p[2] if len(p) > 2 else 0.0) + thick[i] * 0.55))
        ps, ws = smooth_path(P, widths, sub)
        _, ts = smooth_path(P, thick, sub)
        n = len(ps)
        toward = Vector((0, -1, 0))
        shade = self.rng.random() if shade is None else shade
        rings = []
        for i in range(n):
            T = (ps[min(i + 1, n - 1)] - ps[max(i - 1, 0)]).normalized()
            Nv = (toward - T * toward.dot(T))
            Nv = Nv.normalized() if Nv.length > 1e-6 else Vector((1, 0, 0))
            B = T.cross(Nv).normalized()
            u = i / (n - 1.0)
            # (the ends close to a point: a rounded tip, not a cut)
            k = min(1.0, math.sin(min(u, 1.0 - u) * math.pi / 0.16)) if min(u, 1.0 - u) < 0.08 else 1.0
            k = max(k, 0.12)
            if (u < 0.5 and blunt[0]) or (u >= 0.5 and blunt[1]):
                k = max(k, 0.85)
            vs = []
            for j in range(ring):
                a = j / ring * math.tau
                vs.append(self.bm.verts.new(ps[i] + B * (ws[i] * k * math.cos(a)) + Nv * (ts[i] * k * math.sin(a))))
            rings.append(vs)
        a0, a1 = tend
        def tn(u):
            if a0 >= 1.0:
                return 1.0
            t = 0.0
            if a0 > 0:
                t = max(t, 1.0 - _ss(a0 * 0.6, a0 * 1.25, u))
            if a1 > 0:
                t = max(t, _ss(1.0 - a1 * 1.25, 1.0 - a1 * 0.6, u))
            return t
        for i in range(n - 1):
            for j in range(ring):
                j2 = (j + 1) % ring
                f = self.bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
                f.smooth = True
                us = (i / (n - 1.0), i / (n - 1.0), (i + 1) / (n - 1.0), (i + 1) / (n - 1.0))
                vv = (j / ring, (j + 1) / ring, (j + 1) / ring, j / ring)
                for l, uu, v2 in zip(f.loops, us, vv):
                    # v doubled back on itself (0..1..0 round the bundle): no seam in the fibres
                    l[self.uv].uv = (uu * (ps[0] - ps[-1]).length * 12.0, abs(v2 * 2.0 - 1.0) * ws[n // 2] * 60.0)
                    l[self.col] = (tn(uu), shade, 0.0, 1.0)
        for vs in (rings[0], rings[-1]):
            try:
                f = self.bm.faces.new(vs)
                f.smooth = True
                for l in f.loops:
                    l[self.uv].uv = (0.0, 0.0)
                    l[self.col] = (tn(0.0 if vs is rings[0] else 1.0), shade, 0.0, 1.0)
            except ValueError:
                pass

    def fan(self, a0, a1, b0, b1, n, widths, thick=0.008, tend=(0.08, 0.12), bow=0.0, lift=0.0, side=1, blunt=(False, False)):
        """n bundles from the line a0..a1 to the line b0..b1 (a fan when b0 == b1), each bowed `bow` sideways at its middle."""
        for i in range(n):
            t = (i + 0.5) / n
            a = (a0[0] + (a1[0] - a0[0]) * t, a0[1] + (a1[1] - a0[1]) * t)
            b = (b0[0] + (b1[0] - b0[0]) * t, b0[1] + (b1[1] - b0[1]) * t)
            mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
            if bow:
                dx, dz = b[0] - a[0], b[1] - a[1]
                ln = math.hypot(dx, dz) or 1.0
                mid = (mid[0] - dz / ln * bow, mid[1] + dx / ln * bow)
            self.bundle([a, mid, b], widths, thick, tend, lift, side, blunt=blunt)

    def ring(self, c, rx, rz, width, thick=0.003, lift=0.0, side=1, n=14):
        """A sphincter: fibres round an opening (the eye, the mouth)."""
        pts = [(c[0] + rx * math.cos(i / n * math.tau), c[1] + rz * math.sin(i / n * math.tau)) for i in range(n + 2)]
        self.bundle(pts, width, thick, (0.0, 0.0), lift, side, sub=4)

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        o.data.materials.append(muscle_mat())
        return o


def _ss(a, b, x):
    if b <= a:
        return 1.0 if x >= a else 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def build():
    # --- the deep layer ---
    deep = plain("deep", (0.20, 0.035, 0.03), rough=0.5, sss=0.1, coat=0.2, bump=0.3, bump_scale=120.0, vary=0.35)
    sh = Shape()
    for p in PRIMS:
        if p[0] == "ell":
            (cx, cz, cf), (rx, rf, rz) = p[1], p[2]
            sh.ell(V(cx, cz, cf), (rx, rf, rz), seg=32)
        else:
            sh.cap(V(*p[1]), V(*p[2]), p[3], p[4], seg=24)
    sh.finish("deep", deep, voxel=0.004, smooth=4)
    pale = plain("sheath", (0.78, 0.62, 0.54), rough=0.35, sss=0.3, coat=0.3, bump=0.2, bump_scale=400.0, vary=0.15)
    cart = plain("cartilage_m", (0.66, 0.44, 0.38), rough=0.4, sss=0.4, coat=0.25, bump=0.15, vary=0.2)
    F = Flesh()
    fwd = Vector((0, -1, 0))
    # Fingers and toes under their tendons.
    dg = Shape()
    for s in (-1, 1):
        for k, (p, d, lens) in enumerate(hand_rays(s)):
            tip = p + d * sum(lens)
            knuckle = p + d * lens[0]
            dg.cap((knuckle if k else p + d * 0.03) - d * 0.008, tip, 0.0092 if k == 0 else 0.0082, 0.0072 if k == 0 else 0.0064, seg=12)
            F.bundle([p + d * 0.004 + fwd * 0.008, knuckle + fwd * 0.0085, tip - d * 0.006 + fwd * 0.0062], [0.0034, 0.0030, 0.0022], 0.0022, (1, 1), world=True)
        d0 = foot_axis(s)
        up = Vector((0, -0.86, 0.5))   # (off the top of the foot, toward the viewer)
        ank = V(s * ANKLE[0], ANKLE[1], ANKLE[2])
        for k, (p, d, lens) in enumerate(foot_rays(s)):
            tip = p + d * sum(lens)
            dg.cap(p + d * lens[0] * 0.9, tip, 0.0105 if k == 0 else 0.0072, 0.0092 if k == 0 else 0.006, seg=12)
            F.bundle([ank + d0 * 0.012 + up * 0.034 + Vector((s * (k - 2) * 0.004, 0, 0)), p + d * lens[0] * 0.55 + up * 0.030, tip - d * 0.004 + up * 0.008],
                     [0.0030, 0.0028, 0.0022], 0.002, (1, 1), world=True)
        # The short muscles on top of the foot, and between its bones.
        F.bundle([ank + d0 * 0.022 + up * 0.031 + Vector((s * 0.012, 0, 0)), ank + d0 * 0.060 + up * 0.034 + Vector((s * 0.006, 0, 0)),
                  ank + d0 * 0.098 + up * 0.030], [0.006, 0.011, 0.006], 0.004, (0.05, 0.3), world=True)
        rays = foot_rays(s)
        for k in range(4):
            a = (rays[k][0] + rays[k + 1][0]) * 0.5
            dd = (rays[k][1] + rays[k + 1][1]).normalized()
            F.bundle([a + up * 0.016, a + dd * 0.024 + up * 0.019, a + dd * 0.048 + up * 0.016], [0.002, 0.0042, 0.002], 0.003, (0.1, 0.2), world=True)
    dg.finish("digits", pale, voxel=0.0015, smooth=2)

    # --- the head ---
    eyes = Shape()
    iris = Shape()
    pup = Shape()
    nose = Shape()
    for s in (-1, 1):
        f0 = surf(s * 0.033, 1.703)
        eyes.ell(V(s * 0.033, 1.703, f0 - 0.004), (0.0125, 0.0125, 0.0125), seg=32)
        iris.ell(V(s * 0.033, 1.703, f0 + 0.0062), (0.0060, 0.0030, 0.0060), seg=24)
        pup.ell(V(s * 0.033, 1.703, f0 + 0.0082), (0.0026, 0.0016, 0.0026), seg=16)
        nose.ell(V(s * 0.0105, 1.6625, 0.106), (0.0075, 0.009, 0.0065))                  # the nostril's wing
        nose.ell(V(s * 0.0785, 1.690, 0.0), (0.0062, 0.012, 0.0270))                     # the ear
        nose.ell(V(s * 0.0825, 1.676, -0.004), (0.0035, 0.008, 0.0105))
    nose.cap(V(0, 1.690, 0.100), V(0, 1.668, 0.120), 0.0058, 0.0080)
    nose.ell(V(0, 1.663, 0.122), (0.0100, 0.010, 0.0085))
    nose.ell(V(0, 1.548, 0.042), (0.0115, 0.010, 0.0125))                                # larynx
    for k in range(5):
        nose.ell(V(0, 1.527 - k * 0.0085, 0.040 - k * 0.001), (0.0088, 0.008, 0.0030))   # the windpipe's rings
    eyes.finish("eyes", plain("sclera", (0.93, 0.90, 0.86), rough=0.12, sss=0.3, coat=0.8), raw=True)
    iris.finish("iris", plain("iris", (0.10, 0.28, 0.42), rough=0.2, coat=0.9), raw=True)
    pup.finish("pupil", plain("pupil", (0.005, 0.005, 0.005), rough=0.1, coat=1.0), raw=True)
    nose.finish("cartilage", cart, voxel=0.0014, smooth=3)

    F.bundle([(0, 1.468), (0, 1.380), (0, 1.290)], [0.013, 0.010, 0.006], 0.0025, (1, 1), lift=-0.002)       # over the sternum
    F.bundle([(0, 1.272), (0, 1.100), (0, 0.925)], [0.078, 0.082, 0.050], 0.002, (1, 1), lift=-0.004, blunt=(True, True), ring=16)   # the sheath over the belly
    F.bundle([(0, 1.268), (0, 1.100), (0, 0.920)], [0.0055, 0.0065, 0.0045], 0.0028, (1, 1), lift=0.005)     # linea alba
    F.ring((0, 1.617), 0.027, 0.0125, 0.0075, lift=0.002)                                     # orbicularis oris
    F.ring((0, 1.617), 0.015, 0.0050, 0.0050, lift=0.004)
    for s in (-1, 1):
        B = lambda *a, **k: F.bundle(*a, side=s, **k)
        FAN = lambda *a, **k: F.fan(*a, side=s, **k)
        # head
        B([(0.016, 1.722), (0.018, 1.752), (0.019, 1.786)], 0.0155, 0.003, (0.0, 0.30), blunt=(True, False))    # frontalis, into the scalp's aponeurosis
        B([(0.046, 1.722), (0.049, 1.750), (0.046, 1.782)], 0.0150, 0.003, (0.0, 0.30), blunt=(True, False))
        FAN((0.060, 1.752), (0.074, 1.700), (0.066, 1.668), (0.068, 1.668), 5, [0.007, 0.011, 0.004], 0.004, (0.0, 0.3), blunt=(True, False))   # temporalis
        F.ring((0.033, 1.703), 0.0215, 0.0185, 0.0085, side=s, lift=0.001)                    # orbicularis oculi
        F.ring((0.033, 1.703), 0.0135, 0.0105, 0.0040, side=s, lift=0.003)
        B([(0.007, 1.694), (0.015, 1.668)], 0.0050, 0.002, (0.2, 0.0))                        # nasalis
        B([(0.021, 1.686), (0.019, 1.660), (0.015, 1.634)], 0.0055, 0.0025, (0.1, 0.05))      # levator labii
        B([(0.045, 1.679), (0.032, 1.652), (0.021, 1.630)], 0.0042, 0.0025, (0.1, 0.05))      # zygomaticus minor
        B([(0.059, 1.673), (0.042, 1.645), (0.027, 1.621)], 0.0058, 0.003, (0.1, 0.05))       # zygomaticus major
        B([(0.058, 1.668), (0.057, 1.635), (0.053, 1.602)], [0.013, 0.0175, 0.012], 0.008, (0.25, 0.05), blunt=(True, True))   # masseter
        B([(0.050, 1.636), (0.038, 1.626), (0.027, 1.619)], 0.0100, 0.003, (0.0, 0.0), lift=-0.003)        # buccinator
        B([(0.060, 1.640), (0.044, 1.628), (0.028, 1.618)], 0.0040, 0.002, (0.0, 0.0))        # risorius
        B([(0.026, 1.613), (0.029, 1.598), (0.028, 1.584)], 0.0070, 0.003, (0.0, 0.1))        # depressor anguli oris
        B([(0.015, 1.607), (0.014, 1.596), (0.013, 1.587)], 0.0060, 0.003, (0.0, 0.1))        # depressor labii
        B([(0.007, 1.601), (0.006, 1.590), (0.006, 1.581)], 0.0062, 0.003, (0.0, 0.1))        # mentalis
        # neck
        B([(0.068, 1.636), (0.052, 1.565), (0.034, 1.510), (0.019, 1.476)], [0.008, 0.013, 0.011, 0.006], 0.008, (0.08, 0.12), lift=0.004)   # sternomastoid
        B([(0.066, 1.630), (0.056, 1.560), (0.048, 1.510), (0.046, 1.482)], [0.006, 0.009, 0.009, 0.007], 0.005, (0.08, 0.08))
        B([(0.008, 1.566), (0.010, 1.520), (0.011, 1.480)], 0.0058, 0.003, (0.05, 0.05), lift=0.004)     # sternohyoid
        B([(0.013, 1.560), (0.032, 1.522), (0.062, 1.498)], 0.0038, 0.0025, (0.05, 0.05))     # omohyoid
        B([(0.040, 1.585), (0.058, 1.530), (0.075, 1.492)], 0.0085, 0.004, (0.0, 0.0), lift=-0.004)      # scalenes
        FAN((0.034, 1.610), (0.050, 1.558), (0.120, 1.492), (0.188, 1.486), 5, [0.010, 0.016, 0.012], 0.006, (0.0, 0.1), lift=-0.002, blunt=(True, True))   # trapezius
        # the collarbone, under the skin
        B([(0.024, 1.466), (0.075, 1.473), (0.130, 1.480), (0.182, 1.485)], 0.0062, 0.005, (1, 1), lift=0.003)
        # chest and shoulder: pectoralis major (clavicular, sternal, abdominal parts), then the deltoid over its tendon
        FAN((0.028, 1.464), (0.108, 1.476), (0.198, 1.402), (0.202, 1.388), 5, [0.011, 0.016, 0.007], 0.011, (0.03, 0.10), bow=0.006, blunt=(True, False))
        FAN((0.014, 1.456), (0.014, 1.300), (0.200, 1.396), (0.204, 1.372), 10, [0.012, 0.0165, 0.007], 0.012, (0.04, 0.10), bow=-0.012, blunt=(True, False))
        B([(0.028, 1.286), (0.110, 1.300), (0.198, 1.366)], [0.012, 0.015, 0.007], 0.010, (0.12, 0.10), blunt=(True, False))
        FAN((0.108, 1.486), (0.198, 1.482), (0.219, 1.320), (0.227, 1.308), 8, [0.010, 0.0170, 0.006], 0.011, (0.03, 0.14), bow=-0.016, lift=0.004, blunt=(True, False))
        for i in range(5):                                                                    # serratus anterior
            B([(0.158, 1.338 - i * 0.031), (0.137, 1.322 - i * 0.032), (0.112, 1.304 - i * 0.034)], [0.008, 0.0105, 0.005], 0.004, (0.0, 0.07), lift=-0.002, blunt=(True, False))
        B([(0.170, 1.370), (0.168, 1.270), (0.158, 1.180), (0.140, 1.090)], 0.0150, 0.006, (0.0, 0.1), lift=-0.006)   # latissimus dorsi
        # abdomen: the obliques run down and in to the sheath; rectus abdominis in its four bellies
        for i in range(12):
            t = i / 11.0
            B([(0.152 - t * 0.004, 1.305 - t * 0.215), (0.120 - t * 0.008, 1.266 - t * 0.222), (0.078, 1.220 - t * 0.228)],
              [0.0125, 0.0150, 0.0100], 0.005, (0.0, 0.20), lift=-0.001, blunt=(True, False))
        B([(0.150, 1.085), (0.142, 1.058), (0.132, 1.036)], 0.0150, 0.005, (0.0, 0.2), blunt=(True, True))
        segs = [1.268, 1.212, 1.156, 1.094, 0.935]
        for i in range(4):
            z0, z1 = segs[i] - 0.0032, segs[i + 1] + 0.0032
            wd = [0.0300, 0.0315, 0.0300] if i < 3 else [0.0305, 0.0250, 0.0110]
            B([(0.0385, z0), (0.0385 - (0.005 if i == 3 else 0), (z0 + z1) * 0.5), (0.0385 - (0.018 if i == 3 else 0), z1)], wd, 0.0105, (0.035, 0.035),
              lift=0.001, blunt=(True, i < 3), ring=16)
        B([(0.129, 1.030), (0.075, 0.966), (0.016, 0.916)], 0.0032, 0.0028, (1, 1), lift=0.004)   # inguinal ligament
        # arm
        B([(0.180, 1.440), (0.190, 1.390), (0.203, 1.330)], 0.0080, 0.006, (0.1, 0.1), lift=-0.006)           # coracobrachialis
        B([(0.185, 1.385), (0.200, 1.290), (0.213, 1.195)], 0.0105, 0.008, (0.0, 0.2), lift=-0.010)           # triceps (medial)
        B([(0.234, 1.400), (0.250, 1.300), (0.262, 1.205)], 0.0120, 0.008, (0.0, 0.2), lift=-0.012)           # triceps (lateral)
        B([(0.222, 1.270), (0.232, 1.215), (0.238, 1.160)], [0.018, 0.024, 0.012], 0.008, (0.0, 0.15), lift=-0.006)   # brachialis
        B([(0.186, 1.442), (0.203, 1.330), (0.222, 1.225), (0.240, 1.146)], [0.004, 0.0155, 0.0140, 0.0035], 0.014, (0.14, 0.16))   # biceps: short head
        B([(0.202, 1.436), (0.214, 1.330), (0.233, 1.220), (0.244, 1.142)], [0.004, 0.0170, 0.0150, 0.0035], 0.016, (0.14, 0.16))   # ... long head
        B([(0.240, 1.160), (0.228, 1.140), (0.215, 1.125)], 0.0060, 0.002, (1, 1), lift=0.004)                # its aponeurosis
        B([(0.262, 1.205), (0.285, 1.100), (0.302, 0.955)], [0.006, 0.0095, 0.003], 0.007, (0.05, 0.42), lift=-0.006)   # extensor carpi radialis
        B([(0.250, 1.232), (0.266, 1.130), (0.290, 0.995), (0.298, 0.932)], [0.005, 0.0155, 0.0100, 0.003], 0.011, (0.05, 0.30))   # brachioradialis
        B([(0.225, 1.125), (0.248, 1.040), (0.268, 0.970), (0.278, 0.930)], [0.010, 0.014, 0.011, 0.007], 0.006, (0.0, 0.40), lift=-0.004)   # flexor digitorum
        B([(0.214, 1.182), (0.238, 1.130), (0.262, 1.082)], [0.006, 0.0105, 0.005], 0.007, (0.10, 0.12))        # pronator teres
        B([(0.216, 1.176), (0.250, 1.060), (0.270, 0.985), (0.285, 0.930)], [0.004, 0.0115, 0.0060, 0.0026], 0.008, (0.08, 0.45))   # flexor carpi radialis
        B([(0.212, 1.173), (0.242, 1.060), (0.264, 0.985), (0.279, 0.925)], [0.003, 0.0075, 0.0030, 0.0022], 0.006, (0.08, 0.55), lift=0.002)   # palmaris longus
        B([(0.207, 1.171), (0.231, 1.050), (0.252, 0.980), (0.267, 0.930)], [0.004, 0.0125, 0.0080, 0.0035], 0.008, (0.08, 0.40))   # flexor carpi ulnaris
        B([(0.262, 0.917), (0.283, 0.920), (0.303, 0.923)], 0.0085, 0.003, (1, 1), lift=0.004, blunt=(True, True))   # flexor retinaculum
        B([(0.290, 0.908), (0.303, 0.888), (0.314, 0.868)], [0.008, 0.0135, 0.006], 0.008, (0.1, 0.1), lift=0.002)   # thenar
        B([(0.272, 0.902), (0.274, 0.875), (0.277, 0.850)], [0.006, 0.0090, 0.005], 0.006, (0.1, 0.1), lift=0.002)   # hypothenar
        for k in range(4):                                                                    # palmar aponeurosis
            B([(0.283, 0.908), (0.284 + (1.5 - k) * 0.008, 0.880), (0.2855 + (1.5 - k) * 0.013, 0.846)], [0.0030, 0.0042, 0.0036], 0.002, (1, 1), lift=0.003)
        # thigh
        B([(0.090, 1.005), (0.096, 0.965), (0.102, 0.925)], 0.0160, 0.006, (0.0, 0.2), lift=-0.006)            # iliopsoas
        B([(0.038, 0.932), (0.064, 0.905), (0.090, 0.880)], 0.0120, 0.006, (0.05, 0.1), lift=-0.006)           # pectineus
        B([(0.020, 0.882), (0.040, 0.720), (0.056, 0.560)], 0.0170, 0.008, (0.0, 0.1), lift=-0.012)            # adductor magnus
        FAN((0.018, 0.918), (0.022, 0.905), (0.060, 0.800), (0.082, 0.700), 3, [0.005, 0.012, 0.009], 0.008, (0.12, 0.1), lift=-0.004)   # adductor longus
        B([(0.014, 0.902), (0.034, 0.700), (0.048, 0.540), (0.054, 0.468)], [0.005, 0.0085, 0.0060, 0.003], 0.006, (0.05, 0.25), lift=-0.004)   # gracilis
        B([(0.152, 0.890), (0.150, 0.720), (0.128, 0.570), (0.110, 0.526)], [0.011, 0.0250, 0.0210, 0.007], 0.014, (0.05, 0.14), lift=-0.004)   # vastus lateralis
        B([(0.086, 0.760), (0.070, 0.620), (0.068, 0.548), (0.079, 0.516)], [0.007, 0.0190, 0.0235, 0.008], 0.014, (0.05, 0.10), lift=-0.002)   # vastus medialis
        B([(0.122, 1.002), (0.119, 0.850), (0.106, 0.680), (0.093, 0.565)], [0.005, 0.0235, 0.0215, 0.007], 0.016, (0.10, 0.17))               # rectus femoris
        B([(0.132, 1.032), (0.142, 0.990), (0.151, 0.950)], [0.007, 0.0135, 0.008], 0.008, (0.05, 0.2))          # tensor fasciae latae
        B([(0.152, 0.955), (0.153, 0.750), (0.138, 0.560), (0.124, 0.470)], [0.009, 0.0115, 0.0100, 0.006], 0.003, (1, 1), lift=-0.002)   # iliotibial band
        B([(0.128, 1.030), (0.108, 0.905), (0.066, 0.710), (0.046, 0.540), (0.057, 0.458)], [0.006, 0.0105, 0.0105, 0.0090, 0.004], 0.006, (0.03, 0.10), lift=0.006)   # sartorius
        B([(0.092, 0.566), (0.091, 0.540), (0.090, 0.522)], [0.010, 0.0150, 0.0160], 0.005, (1, 1), lift=0.004)   # quadriceps tendon
        B([(0.090, 0.486), (0.090, 0.460), (0.090, 0.434)], [0.012, 0.0100, 0.008], 0.004, (1, 1), lift=0.004)   # patellar ligament
        # lower leg
        B([(0.125, 0.452), (0.138, 0.365), (0.129, 0.262)], [0.006, 0.0120, 0.005], 0.008, (0.0, 0.25), lift=-0.014)   # gastrocnemius (lateral)
        B([(0.055, 0.462), (0.045, 0.365), (0.054, 0.245)], [0.007, 0.0195, 0.005], 0.010, (0.0, 0.28), lift=-0.010)   # gastrocnemius (medial)
        B([(0.060, 0.305), (0.060, 0.230), (0.063, 0.160)], [0.006, 0.0100, 0.004], 0.006, (0.0, 0.3), lift=-0.010)    # soleus
        B([(0.083, 0.432), (0.079, 0.300), (0.076, 0.120)], [0.010, 0.0090, 0.007], 0.004, (1, 1), lift=-0.002)       # the shin (bone under the skin)
        B([(0.128, 0.432), (0.133, 0.300), (0.119, 0.145), (0.104, 0.080)], [0.004, 0.0105, 0.0060, 0.003], 0.007, (0.05, 0.45), lift=-0.008)   # peroneus longus
        B([(0.118, 0.432), (0.121, 0.300), (0.106, 0.145), (0.092, 0.082)], [0.004, 0.0105, 0.0060, 0.003], 0.008, (0.05, 0.42), lift=-0.003)   # extensor digitorum longus
        B([(0.105, 0.442), (0.105, 0.320), (0.091, 0.165), (0.072, 0.082)], [0.005, 0.0155, 0.0080, 0.003], 0.011, (0.05, 0.36))               # tibialis anterior
        B([(0.058, 0.104), (0.082, 0.098), (0.106, 0.090)], 0.0055, 0.003, (1, 1), lift=0.004, blunt=(True, True))    # extensor retinaculum
        B([(0.060, 0.078), (0.082, 0.070), (0.103, 0.064)], 0.0048, 0.003, (1, 1), lift=0.004, blunt=(True, True))
    F.finish("muscles")
    # The kneecaps (their own smooth shape, under the tendon's sheen).
    kn = Shape()
    for s in (-1, 1):
        f0 = surf(s * 0.090, 0.503)
        kn.ell(V(s * 0.090, 0.503, f0 + 0.002), (0.0185, 0.008, 0.0200))
    kn.finish("kneecaps", plain("ligament", (0.84, 0.78, 0.68), rough=0.3, sss=0.3, coat=0.4, bump=0.2, bump_scale=500.0, vary=0.12), voxel=0.0015, smooth=2)
