# Shared by the anatomy layers (build.py): the scene (a front view of the body
# lying on the table, head to the LEFT of the picture), geometry helpers and
# materials.
#
# The body: 1.80 m tall, standing in Blender's world - Z up (feet at 0, the
# crown at 1.80), +X its LEFT side, its front facing -Y. The tables give
# points as (x, z, f): x across (+ = its left), z up, f forward of the
# mid-plane - V() turns them into world vectors. The camera looks at the front
# with the head to the picture's left: picture right = -Z, picture up = +X
# (the body's left side at the top).
# The feet fall forward and outward, as lying on a table (the toes to -Z).
# The picture: W x H px at PPM px per metre, z from Z_HI (its left edge) down.
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix

PPM = 2100.0
W, H = 4096, 1848
ZC = 0.845
Z_HI = ZC + W / PPM / 2.0
X_HI = H / PPM / 2.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)


def V(x, z, f=0.0):
    return Vector((x, -f, z))


def reset(samples=96):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
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
                pass
    except Exception:
        pass
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.20, 0.22, 0.26, 1)
    bg.inputs[1].default_value = 0.3

    def area(name, loc, size, power, col):
        d = bpy.data.lights.new(name, "AREA")
        d.size = size
        d.energy = power
        d.color = col
        o = bpy.data.objects.new(name, d)
        sc.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, ZC)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        return o
    # (picture up = +X, picture left = +Z, toward the viewer = -Y)
    area("key", (2.6, -3.6, ZC + 1.6), 3.0, 120, (1.0, 0.97, 0.92))      # upper left, in front
    area("fill", (-2.4, -3.0, ZC - 1.8), 4.0, 30, (0.78, 0.86, 1.0))    # lower right
    area("rim", (3.2, 0.6, ZC - 0.6), 2.0, 55, (1.0, 0.9, 0.8))         # grazing from above (the body's left)
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = W / PPM
    cam_d.clip_end = 30
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    rot = Matrix(((0, 1, 0), (0, 0, -1), (-1, 0, 0)))   # columns: picture right (-Z), up (+X), toward the viewer (-Y)
    cam.matrix_world = Matrix.Translation((0, -6, ZC)) @ rot.to_4x4()
    sc.camera = cam
    return sc


def render(name, scale=1.0):
    sc = bpy.context.scene
    sc.render.resolution_x = W
    sc.render.resolution_y = H
    sc.render.resolution_percentage = int(100 * scale)
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


# --- materials -----------------------------------------------------------------------------------

_mats = {}


def _new(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree, m.node_tree.nodes["Principled BSDF"]


def _set(b, **kw):
    names = {"col": "Base Color", "rough": "Roughness", "metal": "Metallic", "sss": "Subsurface Weight",
             "coat": "Coat Weight", "spec": "Specular IOR Level", "emit_k": "Emission Strength"}
    for k, v in kw.items():
        inp = b.inputs[names[k]]
        inp.default_value = (*v, 1) if k == "col" else v


def plain(name, col, rough=0.5, sss=0.0, coat=0.0, bump=0.0, bump_scale=300.0, vary=0.0, metal=0.0):
    """A plain material: a colour, a little variation, a fine bump."""
    if name in _mats:
        return _mats[name]
    m, nt, b = _new(name)
    _set(b, col=col, rough=rough, coat=coat, metal=metal)
    if sss:
        _set(b, sss=sss)
        b.inputs["Subsurface Radius"].default_value = (0.012, 0.006, 0.004)
        b.inputs["Subsurface Scale"].default_value = 0.4
    if bump or vary:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = bump_scale
        nz.inputs["Detail"].default_value = 6.0
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        if bump:
            bp = nt.nodes.new("ShaderNodeBump")
            bp.inputs["Strength"].default_value = bump
            bp.inputs["Distance"].default_value = 0.002
            nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
            nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
        if vary:
            nz2 = nt.nodes.new("ShaderNodeTexNoise")
            nz2.inputs["Scale"].default_value = bump_scale * 0.08
            nz2.inputs["Detail"].default_value = 5.0
            nt.links.new(tc.outputs["Object"], nz2.inputs["Vector"])
            mix = nt.nodes.new("ShaderNodeMixRGB")
            mix.blend_type = "MULTIPLY"
            ramp = nt.nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].position = 0.3
            ramp.color_ramp.elements[0].color = (1 - vary, 1 - vary, 1 - vary, 1)
            ramp.color_ramp.elements[1].position = 0.7
            ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
            nt.links.new(nz2.outputs["Fac"], ramp.inputs[0])
            mix.inputs[0].default_value = 1.0
            mix.inputs[1].default_value = (*col, 1)
            nt.links.new(ramp.outputs[0], mix.inputs[2])
            nt.links.new(mix.outputs[0], b.inputs["Base Color"])
    _mats[name] = m
    return m


def bone_mat(name="bone", col=(0.86, 0.80, 0.66)):
    """Bone: ivory, darker and yellower in the hollows (ambient occlusion), fine pores."""
    if name in _mats:
        return _mats[name]
    m, nt, b = _new(name)
    _set(b, rough=0.52, sss=0.12, coat=0.08)
    b.inputs["Subsurface Radius"].default_value = (0.01, 0.006, 0.004)
    b.inputs["Subsurface Scale"].default_value = 0.3
    tc = nt.nodes.new("ShaderNodeTexCoord")
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.03
    ao.samples = 8
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (col[0] * 0.42, col[1] * 0.33, col[2] * 0.22, 1)
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.elements[1].color = (*col, 1)
    nt.links.new(ao.outputs["AO"], ramp.inputs[0])
    # Mottling: big soft patches, and fine pores.
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 28.0
    nz.inputs["Detail"].default_value = 8.0
    nz.inputs["Roughness"].default_value = 0.65
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    r2 = nt.nodes.new("ShaderNodeValToRGB")
    r2.color_ramp.elements[0].position = 0.3
    r2.color_ramp.elements[0].color = (0.80, 0.74, 0.62, 1)
    r2.color_ramp.elements[1].position = 0.75
    r2.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(nz.outputs["Fac"], r2.inputs[0])
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    nt.links.new(ramp.outputs[0], mix.inputs[1])
    nt.links.new(r2.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], b.inputs["Base Color"])
    pores = nt.nodes.new("ShaderNodeTexNoise")
    pores.inputs["Scale"].default_value = 900.0
    pores.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], pores.inputs["Vector"])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.25
    bp.inputs["Distance"].default_value = 0.001
    nt.links.new(pores.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    _mats[name] = m
    return m


# --- geometry: primitives fused into one smooth mesh -----------------------------------------------

class Shape:
    """Primitives (ellipsoids, tapered capsules, paths of them) gathered into
    one mesh, then fused and smoothed (a voxel remesh) into something organic:
    a bone with its heads and condyles, a skull, a heart."""

    def __init__(self):
        self.bm = bmesh.new()

    def ell(self, c, r, rot=(0, 0, 0), seg=24):
        """An ellipsoid at world `c` (a Vector), radii `r` along its own x, y, z; turned `rot` (Euler, radians)."""
        m = Matrix.Translation(c) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ \
            Matrix.Rotation(rot[0], 4, "X") @ Matrix.Diagonal((r[0], r[1], r[2], 1.0))
        bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=seg // 2, radius=1.0, matrix=m)
        return self

    def cap(self, a, b, ra, rb=None, seg=16):
        """A capsule from `a` to `b` (Vectors), radius ra at a to rb at b."""
        rb = ra if rb is None else rb
        d = b - a
        ln = d.length
        if ln < 1e-6:
            return self.ell(a, (ra, ra, ra))
        q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        m = Matrix.Translation((a + b) / 2) @ q
        bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=ra, radius2=rb, depth=ln, matrix=m)
        self.ell(a, (ra, ra, ra), seg=seg)
        self.ell(b, (rb, rb, rb), seg=seg)
        return self

    def path(self, pts, radii, seg=14):
        """Capsules joined end to end through `pts` (smoothed), radius `radii` at each."""
        ps, rs = smooth_path(pts, radii, 4)
        for i in range(len(ps) - 1):
            self.cap(ps[i], ps[i + 1], rs[i], rs[i + 1], seg=seg)
        return self

    def box(self, c, half, rot=(0, 0, 0)):
        m = Matrix.Translation(c) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ \
            Matrix.Rotation(rot[0], 4, "X") @ Matrix.Diagonal((half[0] * 2, half[1] * 2, half[2] * 2, 1.0))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        return self

    def obj(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        return o

    def finish(self, name, mat, voxel=0.003, smooth=2, cut=None, raw=False):
        """The fused mesh: `cut` (another Shape) carved out of it first."""
        o = self.obj(name)
        if cut is not None:
            c = cut.obj(name + "_cut")
            # (each fused on its own first: a clean solid to carve with)
            for x in (o, c):
                r = x.modifiers.new("fuse", "REMESH")
                r.mode = "VOXEL"
                r.voxel_size = voxel
                apply_mods(x)
            bo = o.modifiers.new("cut", "BOOLEAN")
            bo.operation = "DIFFERENCE"
            bo.object = c
            bo.solver = "EXACT"
            apply_mods(o)
            bpy.data.objects.remove(c)
        if not raw:
            r = o.modifiers.new("fuse", "REMESH")
            r.mode = "VOXEL"
            r.voxel_size = voxel
            r.use_smooth_shade = True
            if smooth:
                s = o.modifiers.new("smooth", "SMOOTH")
                s.iterations = smooth
                s.factor = 0.6
            apply_mods(o)
        for p in o.data.polygons:
            p.use_smooth = True
            p.material_index = 0
        o.data.materials.clear()   # (a carve leaves an empty slot first)
        o.data.materials.append(mat)
        return o


def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def smooth_path(pts, radii, sub=6):
    """A Catmull-Rom curve through `pts` (Vectors), `sub` samples a span; the radii interpolated the same way."""
    if isinstance(radii, (int, float)):
        radii = [radii] * len(pts)
    if len(pts) < 3:
        return list(pts), list(radii)
    out, rs = [], []
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[min(i + 2, n - 1)]
        for k in range(sub):
            t = k / sub
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
            rs.append(radii[i] + (radii[i + 1] - radii[i]) * t)
    out.append(pts[-1])
    rs.append(radii[-1])
    return out, rs


def tube(name, pts, radii, mat, sub=6, bevel_res=5):
    """A round tube through `pts` (a smooth curve; radius at each point): vessels, nerves, ribs."""
    ps, rs = smooth_path(pts, radii, sub)
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = bevel_res
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(ps) - 1)
    for i, p in enumerate(ps):
        sp.points[i].co = (p.x, p.y, p.z, 1.0)
        sp.points[i].radius = rs[i]
    sp.use_smooth = True
    o = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


class Tubes:
    """Many tubes of one material in one curve object (a vascular tree, the nerves): cheap to build and render."""

    def __init__(self, name, mat, bevel_res=4):
        self.cu = bpy.data.curves.new(name, "CURVE")
        self.cu.dimensions = "3D"
        self.cu.bevel_depth = 1.0
        self.cu.bevel_resolution = bevel_res
        self.cu.use_fill_caps = True
        self.o = bpy.data.objects.new(name, self.cu)
        bpy.context.scene.collection.objects.link(self.o)
        self.o.data.materials.append(mat)
        self.n = 0

    def add(self, pts, radii, sub=5):
        ps, rs = smooth_path(pts, radii, sub)
        sp = self.cu.splines.new("POLY")
        sp.points.add(len(ps) - 1)
        for i, p in enumerate(ps):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = max(rs[i], 0.0002)
        sp.use_smooth = True
        self.n += 1
        return ps, rs


# --- the body's outline (for keeping small branches inside it) --------------------------------------

# Capsules in the front plane: (x0, z0, x1, z1, radius) - one side (+x); mirrored for the other.
_BODY = [
    (0.0, 1.70, 0.0, 1.66, 0.078), (0.0, 1.62, 0.0, 1.60, 0.062),              # head, jaw
    (0.0, 1.57, 0.0, 1.50, 0.05),                                                # neck
    (0.0, 1.42, 0.0, 1.22, 0.155), (0.07, 1.44, 0.12, 1.44, 0.07),              # chest, shoulder slope
    (0.0, 1.18, 0.0, 1.02, 0.14), (0.0, 0.98, 0.0, 0.94, 0.16),                 # abdomen, hips
    (0.195, 1.43, 0.235, 1.18, 0.05), (0.235, 1.17, 0.283, 0.93, 0.04),         # upper arm, forearm
    (0.285, 0.91, 0.30, 0.80, 0.042), (0.30, 0.80, 0.31, 0.73, 0.035),          # hand, fingers
    (0.10, 0.92, 0.088, 0.52, 0.082), (0.085, 0.47, 0.078, 0.12, 0.052),        # thigh, shin
    (0.080, 0.05, 0.115, -0.09, 0.042),                                          # foot
]


def inside_body(x, z, shrink=0.0):
    x = abs(x)
    for (x0, z0, x1, z1, r) in _BODY:
        dx, dz = x1 - x0, z1 - z0
        ln2 = dx * dx + dz * dz
        t = 0.0 if ln2 == 0 else max(0.0, min(1.0, ((x - x0) * dx + (z - z0) * dz) / ln2))
        px, pz = x0 + dx * t, z0 + dz * t
        if (x - px) ** 2 + (z - pz) ** 2 <= (r - shrink) ** 2:
            return True
    return False


def twigs(tubes, rng, start, direction, length, radius, depth, spread=0.9, keep=None, f_jitter=0.01):
    """A branch from `start` (a Vector) heading `direction` in the front plane
    (x, z), wandering, with side branches - each shorter and thinner - to
    `depth` levels. Stays inside the body (or `keep(x, z)`)."""
    keep = keep or inside_body
    n = max(3, int(length / 0.012))
    pts = [start.copy()]
    d = Vector((direction[0], direction[1])).normalized()
    p = start.copy()
    for i in range(n):
        ang = rng.uniform(-0.35, 0.35)
        d = Vector((d.x * math.cos(ang) - d.y * math.sin(ang), d.x * math.sin(ang) + d.y * math.cos(ang)))
        step = length / n
        q = Vector((p.x + d.x * step, p.y + rng.uniform(-f_jitter, f_jitter) * 0.3, p.z + d.y * step))
        if not keep(q.x, q.z):
            break
        p = q
        pts.append(p.copy())
    if len(pts) < 2:
        return
    radii = [radius * (1.0 - 0.75 * i / (len(pts) - 1)) for i in range(len(pts))]
    tubes.add(pts, radii, sub=3)
    if depth <= 0:
        return
    k = rng.randint(1, 3)
    for j in range(k):
        i = rng.randint(1, len(pts) - 1)
        t0 = pts[i] - pts[i - 1]
        base = Vector((t0.x, t0.z)).normalized() if t0.length > 0 else d
        ang = rng.choice((-1, 1)) * rng.uniform(0.5, spread + 0.4)
        nd = (base.x * math.cos(ang) - base.y * math.sin(ang), base.x * math.sin(ang) + base.y * math.cos(ang))
        twigs(tubes, rng, pts[i], nd, length * rng.uniform(0.45, 0.7), radii[i] * 0.72, depth - 1, spread, keep, f_jitter)


# --- hands and feet (the same rays in every layer) -----------------------------------------------------

FINGERS = [(0.058, 0.040, 0.024, 0.019), (0.056, 0.044, 0.029, 0.020), (0.052, 0.041, 0.027, 0.020), (0.048, 0.033, 0.020, 0.018)]
WRIST = (0.284, 0.912)
ANKLE = (0.080, 0.050, 0.012)


def hand_rays(s):
    """The thumb, then index .. little finger: (base, direction, segment lengths) - palm forward, the thumb outside."""
    wx, wz = s * WRIST[0], WRIST[1]
    out = [(V(wx + s * 0.019, wz - 0.010, 0.006), Vector((s * math.sin(0.72), -0.25, -math.cos(0.72))).normalized(), (0.040, 0.030, 0.024))]
    for k in range(4):
        ang = 0.10 + (1.5 - k) * 0.075
        out.append((V(wx + s * (1.5 - k) * 0.0098, wz - 0.026, 0.004), Vector((s * math.sin(ang), 0, -math.cos(ang))), FINGERS[k]))
    return out


def foot_axis(s):
    return Vector((s * 0.198, -0.497, -0.845)).normalized()


def foot_rays(s):
    """Big toe .. little toe: (base of its metatarsal, direction, segment lengths)."""
    a = V(s * ANKLE[0], ANKLE[1], ANKLE[2])
    d0 = foot_axis(s)
    out = []
    for k in range(5):
        turn = 0.20 + (k - 2) * 0.07
        d = Vector((s * math.sin(turn), -0.50, -0.85)).normalized()
        base = a + d0 * (0.082 - k * 0.004) + Vector((s * (k - 1.6) * 0.0125, 0.004 * k, 0))
        out.append((base, d, (0.052, 0.027, 0.021) if k == 0 else (0.058 - k * 0.003, 0.021, 0.012, 0.010)))
    return out
