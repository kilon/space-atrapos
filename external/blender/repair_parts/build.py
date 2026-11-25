# Repair Bay art (RepairArt): the components, bolts, sockets, clamps, gauges,
# tools, the table and the casing - modelled and rendered top-down here, then
# packed by pack.py into art/repair/. Run headless:
#   blender -b -P external/blender/repair_parts/build.py [-- name ...]
# Godot's (x, y) maps to Blender (x, -y): the picture's top is +Y.
import bpy, bmesh, math, os, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

# --- scene ------------------------------------------------------------------------------------

def reset():
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
    sc.cycles.samples = 128
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    # World: dim, brighter above - something for the metal to reflect.
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.01, 0.012, 0.016, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0.35, 0.36, 0.4, 1)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[1].default_value = 1.0
    outn = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], outn.inputs[0])
    # Lights: a big soft key from the upper left, a cool fill, a warm rim.
    def area(name, loc, size, power, col):
        d = bpy.data.lights.new(name, "AREA")
        d.size = size
        d.energy = power
        d.color = col
        o = bpy.data.objects.new(name, d)
        sc.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        return o
    area("key", (-4, 5, 8), 5, 1400, (1.0, 0.96, 0.9))
    area("fill", (6, -3, 5), 6, 380, (0.75, 0.85, 1.0))
    area("rim", (3, 6, 1.6), 2.5, 260, (1.0, 0.8, 0.6))
    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = (0, 0, 20)
    sc.camera = cam
    return sc

def shadow_catcher(size=12):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    p = bpy.context.object
    p.is_shadow_catcher = True
    p.data.materials.append(mat("catch", (0.5, 0.5, 0.5)))
    return p

def render(name, width_units, px_w, px_h=None, center=(0, 0)):
    sc = bpy.context.scene
    px_h = px_h or px_w
    sc.render.resolution_x = px_w
    sc.render.resolution_y = px_h
    sc.render.resolution_percentage = 100
    cam = sc.camera
    cam.data.ortho_scale = width_units if px_w >= px_h else width_units * px_h / px_w
    cam.location = (center[0], -center[1], 20)
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)

# --- materials -------------------------------------------------------------------------------

_mats = {}

def mat(name, col, metal=0.0, rough=0.5, emit=None, emit_k=0.0, coat=0.0, trans=0.0, noise=0.0, ior=1.45):
    key = name
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["IOR"].default_value = ior
    if coat:
        b.inputs["Coat Weight"].default_value = coat
    if trans:
        b.inputs["Transmission Weight"].default_value = trans
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_k
    _cols[name] = (col, metal, rough)
    if name == "hole":
        b.inputs["Specular IOR Level"].default_value = 0.0
    if not trans and name not in ("hole", "catch"):
        # Every hard edge rounded a little in the shading (it catches the light:
        # machined, not paper-cut), and the crevices darker (grime, contact shadows).
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.samples = 6
        bev.inputs["Radius"].default_value = 0.014
        nt.links.new(bev.outputs["Normal"], b.inputs["Normal"])
    if noise:
        # Scuffs: the roughness and colour vary a little (brushed, worn) - fine
        # grained, in the object's own units (not stretched over a big plate).
        tc = nt.nodes.new("ShaderNodeTexCoord")
        tex = nt.nodes.new("ShaderNodeTexNoise")
        nt.links.new(tc.outputs["Object"], tex.inputs["Vector"])
        tex.inputs["Scale"].default_value = 26.0
        tex.inputs["Detail"].default_value = 8.0
        mp = nt.nodes.new("ShaderNodeMapRange")
        mp.inputs[3].default_value = rough - noise
        mp.inputs[4].default_value = rough + noise
        nt.links.new(tex.outputs["Fac"], mp.inputs[0])
        nt.links.new(mp.outputs[0], b.inputs["Roughness"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["Factor"].default_value = 0.0
        nt.links.new(tex.outputs["Fac"], mix.inputs["Factor"])
        mix.inputs["A"].default_value = (col[0] * 0.8, col[1] * 0.8, col[2] * 0.8, 1)
        mix.inputs["B"].default_value = (*col, 1)
        nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    if not trans and not emit and name not in ("hole", "catch"):
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = 0.22
        ao.samples = 8
        src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].links else None
        if src is not None:
            nt.links.new(src, ao.inputs["Color"])
        else:
            ao.inputs["Color"].default_value = (*col, 1)
        dark = nt.nodes.new("ShaderNodeMix")
        dark.data_type = "RGBA"
        dark.blend_type = "MULTIPLY"
        dark.inputs["Factor"].default_value = 1.0
        ramp = nt.nodes.new("ShaderNodeMapRange")
        ramp.inputs[1].default_value = 0.35
        ramp.inputs[2].default_value = 0.95
        ramp.inputs[3].default_value = 0.28
        ramp.inputs[4].default_value = 1.0
        nt.links.new(ao.outputs["AO"], ramp.inputs[0])
        grey = nt.nodes.new("ShaderNodeCombineColor")
        for i in range(3):
            nt.links.new(ramp.outputs[0], grey.inputs[i])
        nt.links.new(ao.outputs["Color"], dark.inputs["A"])
        nt.links.new(grey.outputs[0], dark.inputs["B"])
        nt.links.new(dark.outputs["Result"], b.inputs["Base Color"])
    _mats[key] = m
    return m


_cols = {}

def charred(src):
    """A burnt-out version of material `src`: soot over what it was, rough,
    with ember veins still glowing in it."""
    name = src.name.split(".")[0]
    key = "char_" + name
    if key in _mats:
        return _mats[key]
    col, metal, rough = _cols.get(name, ((0.3, 0.3, 0.3), 0.5, 0.5))
    soot = (0.022, 0.018, 0.015)
    k = 0.86
    c = tuple(col[i] * (1 - k) + soot[i] * k for i in range(3))
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = metal * 0.35
    b.inputs["Roughness"].default_value = 0.82
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    n1.inputs["Scale"].default_value = 7.0
    n1.inputs["Detail"].default_value = 6.0
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(n1.outputs["Fac"], mix.inputs["Factor"])
    mix.inputs["A"].default_value = (*soot, 1)
    mix.inputs["B"].default_value = (min(1, c[0] * 1.9), min(1, c[1] * 1.7), min(1, c[2] * 1.6), 1)
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    # Ember veins: a thin band of a second noise glows.
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    n2.inputs["Scale"].default_value = 1.5
    n2.inputs["Detail"].default_value = 2.0
    n2.inputs["Distortion"].default_value = 0.9
    band = nt.nodes.new("ShaderNodeValToRGB")
    e = band.color_ramp.elements
    e[0].position = 0.489
    e[0].color = (0, 0, 0, 1)
    e[1].position = 0.5
    e[1].color = (1, 1, 1, 1)
    e2 = band.color_ramp.elements.new(0.511)
    e2.color = (0, 0, 0, 1)
    nt.links.new(n2.outputs["Fac"], band.inputs[0])
    b.inputs["Emission Color"].default_value = (1.0, 0.24, 0.03, 1)
    k2 = nt.nodes.new("ShaderNodeMath")
    k2.operation = "MULTIPLY"
    k2.inputs[1].default_value = 3.0
    nt.links.new(band.outputs[0], k2.inputs[0])
    nt.links.new(k2.outputs[0], b.inputs["Emission Strength"])
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.inputs["Radius"].default_value = 0.014
    nt.links.new(bev.outputs["Normal"], b.inputs["Normal"])
    _mats[key] = m
    return m


def wrecked(fn, bites, seed=1):
    """Builder `fn`'s part burnt out: charred all over, pieces bitten off its
    edge (`bites`: Godot (x, y, r)...), bits of it lying about."""
    def build(m):
        before = set(bpy.data.objects)
        fn(m)
        made = [o for o in bpy.data.objects if o not in before and o.type == "MESH" and not o.hide_render]
        cutters = []
        for (x, y, r) in bites:
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=(x, -y, 0.15))
            c = bpy.context.object
            c.scale = (1, 0.8, 2.5)
            c.rotation_euler = (0, 0, x * 3.1 + y)
            c.hide_render = True
            c.display_type = "WIRE"
            cutters.append(c)
        for o in made:
            for i, slot in enumerate(o.material_slots):
                if slot.material is not None:
                    o.material_slots[i].material = charred(slot.material)
            for c in cutters:
                bm_ = o.modifiers.new("bite", "BOOLEAN")
                bm_.operation = "DIFFERENCE"
                bm_.object = c
        import random
        rnd = random.Random(seed)
        soot = charred(m["steel_d"])
        for i in range(9):   # debris
            a = rnd.random() * math.tau
            d = rnd.uniform(0.75, 1.15)
            bpy.ops.mesh.primitive_cube_add(size=1, location=(math.cos(a) * d, math.sin(a) * d * 0.8, 0.03))
            o = bpy.context.object
            o.scale = (rnd.uniform(0.03, 0.09), rnd.uniform(0.02, 0.06), rnd.uniform(0.02, 0.04))
            o.rotation_euler = (rnd.random(), rnd.random(), rnd.random() * 3)
            o.data.materials.append(soot)
    return build

def M():
    return {
        "steel": mat("steel", (0.62, 0.64, 0.68), 1.0, 0.32, noise=0.12),
        "steel_d": mat("steel_d", (0.2, 0.21, 0.24), 1.0, 0.42, noise=0.1),
        "gun": mat("gun", (0.09, 0.095, 0.11), 0.85, 0.5, noise=0.1),
        "brass": mat("brass", (0.92, 0.66, 0.3), 1.0, 0.28, noise=0.08),
        "gold": mat("gold", (1.0, 0.78, 0.36), 1.0, 0.22),
        "copper": mat("copper", (0.95, 0.5, 0.32), 1.0, 0.3),
        "pcb": mat("pcb", (0.03, 0.22, 0.12), 0.0, 0.35, coat=0.6),
        "trace": mat("trace", (0.55, 0.8, 0.35), 0.4, 0.3, coat=0.6),
        "chip": mat("chip", (0.03, 0.03, 0.035), 0.0, 0.45),
        "cap": mat("cap", (0.08, 0.15, 0.45), 0.0, 0.3, coat=0.4),
        "res": mat("res", (0.75, 0.65, 0.48), 0.0, 0.5),
        "rubber": mat("rubber", (0.05, 0.05, 0.055), 0.0, 0.7),
        "glass": mat("glass", (0.75, 0.92, 1.0), 0.0, 0.02, trans=1.0),
        "sensor": mat("sensor", (0.02, 0.05, 0.12), 0.0, 0.2, emit=(0.15, 0.45, 1.0), emit_k=1.2),
        "cellglow": mat("cellglow", (0.9, 0.5, 0.1), 0.0, 0.3, emit=(1.0, 0.55, 0.12), emit_k=0.9),
        "led_g": mat("led_g", (0.05, 0.3, 0.1), 0.0, 0.25, emit=(0.1, 1.0, 0.3), emit_k=0.25, coat=0.5),
        "led_a": mat("led_a", (0.35, 0.2, 0.03), 0.0, 0.25, emit=(1.0, 0.6, 0.1), emit_k=0.25, coat=0.5),
        "face": mat("face", (0.018, 0.02, 0.024), 0.0, 0.55),
        "well": mat("well", (0.035, 0.038, 0.044), 0.5, 0.6, noise=0.1),
        "paint": mat("paint", (0.42, 0.44, 0.46), 0.6, 0.48, noise=0.15),
        "hazard": mat("hazard", (0.95, 0.55, 0.12), 0.0, 0.5, noise=0.1),
        "red": mat("red", (0.6, 0.06, 0.04), 0.0, 0.4, coat=0.5),
        "blue": mat("blue", (0.12, 0.35, 0.55), 0.3, 0.35, coat=0.5),
        "hole": mat("hole", (0.01, 0.01, 0.012), 0.0, 0.9),
        "print": mat("print", (0.035, 0.06, 0.07), 0.0, 0.7),
        "print_h": mat("print_h", (0.07, 0.13, 0.15), 0.0, 0.7),
        "table": mat("table", (0.05, 0.053, 0.06), 0.7, 0.55, noise=0.15),
        "mat": mat("mat", (0.012, 0.016, 0.018), 0.0, 0.85, noise=0.08),
        "lid": mat("lid", (0.36, 0.38, 0.42), 0.85, 0.48, noise=0.12),
    }

# --- shapes ----------------------------------------------------------------------------------

def G(x, y):
    """Godot -> Blender plane."""
    return (x, -y)

def box(cx, cy, z0, w, h, d, m, bevel=0.0, rot=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(cx, -cy, z0 + d / 2))
    o = bpy.context.object
    o.scale = (w, h, d)
    o.rotation_euler = (0, 0, -rot)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        bv = o.modifiers.new("b", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        bv.limit_method = "ANGLE"
    o.data.materials.append(m)
    smooth(o)
    return o

def cyl(cx, cy, z0, r, d, m, bevel=0.0, verts=48, axis="Z"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d)
    o = bpy.context.object
    if axis == "X":
        o.rotation_euler = (0, math.pi / 2, 0)
        o.location = (cx, -cy, z0)
    elif axis == "Y":
        o.rotation_euler = (math.pi / 2, 0, 0)
        o.location = (cx, -cy, z0)
    else:
        o.location = (cx, -cy, z0 + d / 2)
    if bevel:
        bv = o.modifiers.new("b", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        bv.limit_method = "ANGLE"
    o.data.materials.append(m)
    smooth(o)
    return o

def prism(pts, z0, d, m, bevel=0.0):
    """An extruded polygon (Godot points)."""
    me = bpy.data.meshes.new("p")
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], -p[1], z0)) for p in pts]
    f = bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=[f])
    if f.normal.z < 0:
        f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, d))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("p", me)
    bpy.context.scene.collection.objects.link(o)
    if bevel:
        bv = o.modifiers.new("b", "BEVEL")
        bv.width = bevel
        bv.segments = 3
        bv.limit_method = "ANGLE"
    o.data.materials.append(m)
    smooth(o)
    return o

def sphere(cx, cy, z0, r, m, sz=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(cx, -cy, z0), segments=32, ring_count=16)
    o = bpy.context.object
    o.scale = (1, 1, sz)
    o.data.materials.append(m)
    smooth(o)
    return o

def torus(cx, cy, z0, R, r, m):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=(cx, -cy, z0), major_segments=48, minor_segments=12)
    o = bpy.context.object
    o.data.materials.append(m)
    smooth(o)
    return o

def cut(target, cutter):
    b = target.modifiers.new("cut", "BOOLEAN")
    b.operation = "DIFFERENCE"
    b.object = cutter
    cutter.hide_render = True
    cutter.display_type = "WIRE"

def smooth(o):
    """Smooth by angle (kept as the last modifier: after bevels and cuts)."""
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))

def hexagon(cx, cy, r, turn=0.0):
    return [(cx + math.cos(turn + i * math.tau / 6) * r, cy + math.sin(turn + i * math.tau / 6) * r) for i in range(6)]

def ngon(cx, cy, r, n, turn=0.0):
    return [(cx + math.cos(turn + i * math.tau / n) * r, cy + math.sin(turn + i * math.tau / n) * r) for i in range(n)]

# --- the pieces (half size s = 1: the component's footprint as RepairArt draws it) ----------

def circuit(m):
    prism([(-1, -0.72), (1, -0.72), (1, 0.72), (-1, 0.72)], 0, 0.08, m["pcb"], 0.02)
    # Edge connector: gold fingers along the left edge.
    for i in range(7):
        box(-0.93, -0.5 + i * 0.167, 0.08, 0.1, 0.09, 0.01, m["gold"])
    # Traces with 45-degree bends, vias at their ends.
    paths = [[(-0.86, -0.5), (-0.6, -0.5), (-0.5, -0.6), (0.3, -0.6), (0.4, -0.5), (0.86, -0.5)],
             [(-0.86, -0.33), (-0.55, -0.33), (-0.55, -0.15)],
             [(-0.86, 0.17), (-0.6, 0.17), (-0.6, 0.0)],
             [(-0.86, 0.5), (-0.4, 0.5), (-0.3, 0.6), (0.5, 0.6), (0.6, 0.5), (0.86, 0.5)],
             [(0.55, -0.2), (0.75, -0.2), (0.85, -0.3)],
             [(0.55, 0.2), (0.75, 0.2), (0.85, 0.3)],
             [(-0.86, 0.33), (-0.65, 0.33), (-0.55, 0.43), (-0.2, 0.43)],
             [(0.2, 0.43), (0.62, 0.43), (0.7, 0.35)]]
    for path in paths:
        for a, b in zip(path, path[1:]):
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            ln = math.dist(a, b)
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            box(mid[0], mid[1], 0.08, ln + 0.035, 0.035, 0.012, m["trace"], rot=ang)
        for p in (path[0], path[-1]):
            cyl(p[0], p[1], 0.08, 0.035, 0.016, m["gold"], verts=16)
    # The chip, its legs.
    box(0, 0, 0.08, 0.9, 0.64, 0.12, m["chip"], 0.02)
    sphere(-0.33, -0.2, 0.2, 0.04, m["steel_d"], 0.2)
    for i in range(5):
        x = -0.4 + i * 0.2
        for side in (-1, 1):
            box(x, side * 0.38, 0.08, 0.06, 0.12, 0.05, m["steel"], 0.01)
    # Capacitors, resistors, a crystal.
    for (x, y) in [(0.7, -0.05), (0.7, 0.1), (-0.72, -0.05)]:
        cyl(x, y, 0.08, 0.07, 0.24, m["cap"], 0.01, 24)
        cyl(x, y, 0.32, 0.06, 0.01, m["steel"], 0, 24)
    for (x, y) in [(-0.1, -0.5), (0.12, -0.5), (0.0, 0.52)]:
        box(x, y, 0.08, 0.14, 0.06, 0.05, m["res"], 0.015)
    box(0.42, -0.44, 0.08, 0.16, 0.08, 0.06, m["steel"], 0.03)
    # Two status LEDs (unlit here: the game lights them - RepairArt.LEDS).
    for (x, y, mm) in [(0.62, -0.36, "led_g"), (0.76, -0.36, "led_a")]:
        box(x, y, 0.08, 0.09, 0.07, 0.02, m["steel"], 0.005)
        sphere(x, y, 0.1, 0.035, m[mm], 0.8)

def conduit(m):
    tube = cyl(0, 0, 0.32, 0.28, 2.0, m["steel"], 0.02, 48, "X")
    for i in range(9):
        x = -0.85 + i * 0.212
        if abs(x) < 0.3:
            continue
        torus(x, 0, 0.32, 0.28, 0.03, m["steel_d"]).rotation_euler = (0, math.pi / 2, 0)
    for x in (-0.75, 0.75):
        c = cyl(x, 0, 0.32, 0.42, 0.2, m["brass"], 0.02, 48, "X")
        for k in (-1, 1):
            cyl(x, k * 0.34, 0.62, 0.05, 0.06, m["steel_d"], 0.01, 6)
    # The valve: a housing, its wheel.
    box(0, 0, 0.05, 0.5, 0.62, 0.52, m["steel_d"], 0.06)
    torus(0, 0, 0.62, 0.22, 0.035, m["brass"])
    for k in range(3):
        a = k * math.tau / 3
        box(math.cos(a) * 0.11, math.sin(a) * 0.11, 0.6, 0.22, 0.04, 0.04, m["brass"], 0.01, rot=a)
    cyl(0, 0, 0.58, 0.06, 0.08, m["steel"], 0.01, 24)

def servo(m):
    pts = []
    n = 12
    for i in range(n):
        a = i * math.tau / n
        for da, r in ((-0.11, 0.76), (-0.06, 0.95), (0.06, 0.95), (0.11, 0.76)):
            pts.append((math.cos(a + da) * r, math.sin(a + da) * r))
    gear = prism(pts, 0, 0.22, m["steel_d"], 0.02)
    disc = cyl(0, 0, 0.18, 0.66, 0.08, m["steel"], 0.02, 64)
    for k in range(5):
        a = k * math.tau / 5 + 0.3
        h = cyl(math.cos(a) * 0.45, math.sin(a) * 0.45, 0.0, 0.12, 0.6, m["hole"], 0, 32)
        cut(disc, h)
        cut(gear, h)
    cyl(0, 0, 0.2, 0.28, 0.16, m["brass"], 0.03, 48)
    box(0, -0.12, 0.33, 0.06, 0.24, 0.05, m["gun"], 0.01)   # (its pointer, as RepairArt drew it)
    for k in range(6):
        a = k * math.tau / 6
        cyl(math.cos(a) * 0.2, math.sin(a) * 0.2, 0.36, 0.025, 0.01, m["steel_d"], 0, 6)

def plate(m):
    pts = [(-1, -0.6), (0.8, -0.75), (1, 0.6), (-0.85, 0.72)]
    prism(pts, 0, 0.1, m["paint"], 0.04)
    inner = [(x * 0.78, y * 0.7) for (x, y) in pts]
    prism(inner, 0.1, 0.04, m["steel"], 0.02)
    # A hazard stripe across a corner.
    prism([(0.45, -0.67), (0.62, -0.69), (0.98, 0.45), (0.95, 0.55), (0.85, 0.57)], 0.1, 0.012, m["hazard"])
    for p in [(-0.75, -0.42), (0.6, -0.55), (0.78, 0.42), (-0.62, 0.52)]:
        sphere(p[0], p[1], 0.1, 0.085, m["steel_d"], 0.5)
    for k in range(4):
        box(-0.2 + k * 0.14, 0.0, 0.14, 0.05, 0.5, 0.012, m["steel_d"], 0.005)

def lens(m):
    housing = cyl(0, 0, 0, 0.95, 0.26, m["steel_d"], 0.03, 64)
    for k in range(36):   # knurled rim
        a = k * math.tau / 36
        box(math.cos(a) * 0.93, math.sin(a) * 0.93, 0.03, 0.05, 0.08, 0.2, m["steel"], 0.01, rot=a)
    torus(0, 0, 0.27, 0.68, 0.07, m["brass"])
    cyl(0, 0, 0.2, 0.6, 0.06, m["sensor"], 0, 64)
    sphere(0, 0, 0.24, 0.6, m["glass"], 0.38)
    for k in range(4):
        a = k * math.tau / 4 + 0.785
        cyl(math.cos(a) * 0.82, math.sin(a) * 0.82, 0.26, 0.04, 0.03, m["brass"], 0.005, 12)

def cell(m):
    box(0, 0, 0, 1.1, 1.8, 0.5, m["steel_d"], 0.12)
    win = box(0, 0, 0.42, 0.78, 1.36, 0.12, m["cellglow"], 0.03)
    box(0, 0, 0.5, 0.82, 1.42, 0.035, m["glass"], 0.015)
    for i in range(3):
        box(0, -0.35 + i * 0.35, 0.5, 0.9, 0.06, 0.06, m["steel"], 0.015)
    box(0, -0.95, 0.15, 0.4, 0.16, 0.3, m["brass"], 0.03)
    for x in (-0.48, 0.48):
        box(x, 0, 0.05, 0.08, 1.5, 0.48, m["steel"], 0.02)

def bolt(m, out=False):
    if out:
        ring = cyl(0, 0, 0, 1.15, 0.12, m["steel"], 0.03, 48)
        h = cyl(0, 0, -0.5, 0.72, 1.2, m["hole"], 0, 48)
        cut(ring, h)
        cyl(0, 0, -0.3, 0.74, 0.3, m["hole"], 0, 48)
        for k in range(3):   # thread, catching the light
            torus(0, 0, -0.02 - k * 0.07, 0.72, 0.025, m["steel_d"])
        return
    cyl(0, 0, 0, 1.25, 0.1, m["steel"], 0.02, 48)   # washer
    head = prism(hexagon(0, 0, 1.0), 0.1, 0.42, m["steel"], 0.08)
    slot = box(0, 0, 0.4, 1.4, 0.2, 0.3, m["hole"])
    cut(head, slot)

def socket(m):
    """The well a component sits in."""
    cyl(0, 0, -0.02, 1.32, 0.04, m["well"], 0.02, 64)
    torus(0, 0, 0.02, 1.3, 0.035, m["steel"])
    for k in range(8):
        a = k * math.tau / 8 + 0.2
        cyl(math.cos(a) * 1.18, math.sin(a) * 1.18, 0.02, 0.035, 0.02, m["steel"], 0, 12)

def empty_socket(m):
    plate_ = box(0, 0, 0, 2.2, 2.2, 0.14, m["steel_d"], 0.04)
    h = box(0, 0, -0.1, 1.9, 1.9, 0.4, m["hole"])
    cut(plate_, h)
    box(0, 0, -0.2, 1.9, 1.9, 0.05, m["face"])
    for (x, y) in [(-0.7, -0.7), (0.7, -0.7), (0.7, 0.7), (-0.7, 0.7)]:
        box(x, y, -0.15, 0.2, 0.2, 0.06, m["brass"], 0.02)
    for i in range(4):   # contacts
        box(-0.3 + i * 0.2, 0, -0.15, 0.08, 0.5, 0.03, m["gold"])

def clamp(m, shut=True):
    box(0, 0.35, 0, 0.9, 0.7, 0.25, m["steel_d"], 0.05)
    cyl(0, 0.3, 0.25, 0.14, 0.08, m["steel"], 0.02, 24, )
    if shut:
        box(0, -0.15, 0.25, 0.32, 1.25, 0.14, m["steel"], 0.05)
        box(0, -0.72, 0.39, 0.4, 0.22, 0.06, m["red"], 0.03)
    else:
        box(0.28, -0.1, 0.25, 0.32, 1.1, 0.14, m["steel"], 0.05, rot=-0.5)
        box(0.52, -0.55, 0.39, 0.4, 0.22, 0.06, m["red"], 0.03, rot=-0.5)

def gauge(m):
    cyl(0, 0, 0, 1.0, 0.18, m["steel"], 0.06, 64)
    cyl(0, 0, 0.1, 0.86, 0.1, m["face"], 0, 64)
    for k in range(13):   # ticks
        a = math.pi * 0.75 + math.pi * 1.5 * k / 12
        box(math.cos(a) * 0.74, math.sin(a) * 0.74, 0.2, 0.14 if k % 3 == 0 else 0.08, 0.025, 0.005, m["steel"], rot=a)

def knob(m):
    k = cyl(0, 0, 0, 1.0, 0.4, m["gun"], 0.05, 64)
    for i in range(24):
        a = i * math.tau / 24
        box(math.cos(a) * 0.98, math.sin(a) * 0.98, 0.02, 0.07, 0.12, 0.34, m["steel_d"], 0.01, rot=a)
    cyl(0, 0, 0.4, 0.62, 0.04, m["steel"], 0.02, 48)

def _along(t0, t1, r, m, z=0.3, verts=32):
    """A cylinder from Godot point t0 to t1 (a tool's segment)."""
    a = Vector((t0[0], -t0[1], z))
    b = Vector((t1[0], -t1[1], z))
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r * TK, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    o.data.materials.append(m)
    smooth(o)
    return o

def _cone(t0, t1, r0, r1, m, z=0.3):
    a = Vector((t0[0], -t0[1], z))
    b = Vector((t1[0], -t1[1], z))
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=r1 * TK, radius2=r0 * TK, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    o.data.materials.append(m)
    smooth(o)
    return o

D = 0.7071
TK = 1.6   # (the tools' thickness: read at a glance under the mouse)
def P(t):   # a point t along the tool's diagonal (tip at 0, handle down-right)
    return (t * D, t * D)

def welder(m):
    _cone(P(0.0), P(0.16), 0.025, 0.06, m["copper"])
    _along(P(0.16), P(0.42), 0.05, m["steel"])
    _along(P(0.42), P(0.5), 0.08, m["brass"])
    _along(P(0.5), P(1.1), 0.1, m["rubber"])
    for k in range(5):
        t = 0.58 + k * 0.1
        _along(P(t), P(t + 0.03), 0.108, m["red"])
    _along(P(1.1), P(1.2), 0.07, m["steel_d"])

def solder(m):
    _cone(P(0.0), P(0.12), 0.01, 0.025, m["steel"])
    _along(P(0.12), P(0.5), 0.025, m["steel"])
    _along(P(0.5), P(0.56), 0.05, m["steel_d"])
    _along(P(0.56), P(1.1), 0.075, m["blue"])
    for k in range(6):
        t = 0.62 + k * 0.07
        _along(P(t), P(t + 0.025), 0.08, m["rubber"])

def sealant(m):
    _cone(P(0.0), P(0.3), 0.02, 0.05, m["steel"])
    _along(P(0.3), P(0.38), 0.07, m["steel_d"])
    _along(P(0.38), P(1.05), 0.16, m["blue"])
    _along(P(0.5), P(0.53), 0.165, m["steel"])
    _along(P(0.9), P(0.93), 0.165, m["steel"])
    _along(P(1.05), P(1.12), 0.1, m["steel_d"])

def forceps(m):
    for side in (-1, 1):
        n = (side * D * 0.12, -side * D * 0.12)
        a = (0.03 * side * D, -0.03 * side * D)
        tip = (P(0.0)[0] + a[0], P(0.0)[1] + a[1])
        mid = (P(0.6)[0] + n[0], P(0.6)[1] + n[1])
        end = (P(1.1)[0] + n[0] * 0.3, P(1.1)[1] + n[1] * 0.3)
        _along(tip, mid, 0.022, m["steel"])
        _along(mid, end, 0.03, m["steel"])
        _along((P(0.62)[0] + n[0], P(0.62)[1] + n[1]), (P(0.85)[0] + n[0] * 0.7, P(0.85)[1] + n[1] * 0.7), 0.036, m["rubber"])
    _along(P(1.08), P(1.16), 0.05, m["steel_d"])

# --- surgical instruments (the automaton's operating table: Surgery) ---------------------------

def Q(t, n):
    """A point t along a tool's diagonal, n off to its side."""
    return (t * D + n * D, t * D - n * D)

def scalpel(m):
    prism([Q(0.0, 0.0), Q(0.10, 0.045), Q(0.36, 0.05), Q(0.42, 0.012), Q(0.40, -0.028), Q(0.10, -0.022)], 0.27, 0.035, m["steel"], 0.008)
    _along(P(0.40), P(0.50), 0.022, m["steel_d"])
    _along(P(0.50), P(1.16), 0.034, m["steel"])
    for k in range(7):
        t = 0.60 + k * 0.06
        _along(P(t), P(t + 0.02), 0.038, m["steel_d"])

def _rings(m, t=1.08, spread=0.11, R=0.085):
    for side in (-1, 1):
        c = Q(t, side * spread)
        torus(c[0], c[1], 0.3, R * TK * 0.62, 0.016 * TK, m["steel"])

def needle(m):
    # A needle holder, a curved needle in its jaws, the thread trailing.
    for side in (-1, 1):
        _along(Q(0.02, side * 0.012), Q(0.30, side * 0.02), 0.017, m["steel"])
        _along(Q(0.36, -side * 0.02), Q(1.00, -side * 0.10), 0.02, m["steel"])
    _along(P(0.30), P(0.37), 0.034, m["steel_d"])
    _rings(m)
    cx, cy = Q(0.04, 0.0)
    pts = [(cx + 0.105 * math.cos(a), cy + 0.105 * math.sin(a)) for a in [math.radians(200 + k * 26) for k in range(8)]]
    for k in range(len(pts) - 1):
        _along(pts[k], pts[k + 1], 0.0085, m["steel"], z=0.34, verts=12)
    th = [pts[-1], (pts[-1][0] + 0.10, pts[-1][1] - 0.05), (pts[-1][0] + 0.24, pts[-1][1] - 0.02), (pts[-1][0] + 0.36, pts[-1][1] - 0.10)]
    for k in range(len(th) - 1):
        _along(th[k], th[k + 1], 0.0045, m["blue"], z=0.3, verts=8)

def fuser(m):
    _cone(P(0.0), P(0.10), 0.012, 0.04, m["sensor"])
    _along(P(0.10), P(0.16), 0.05, m["brass"])
    _along(P(0.16), P(0.46), 0.042, m["steel"])
    for k in range(4):
        t = 0.2 + k * 0.06
        _along(P(t), P(t + 0.02), 0.06, m["steel_d"])
    _along(P(0.46), P(1.08), 0.085, m["gun"])
    _along(P(0.56), P(0.74), 0.09, m["hazard"])
    _along(P(1.08), P(1.18), 0.06, m["steel_d"])

def hemostat(m):
    for side in (-1, 1):
        _along(Q(0.0, side * 0.008), Q(0.42, side * 0.016), 0.014, m["steel"])
        _along(Q(0.48, -side * 0.016), Q(1.00, -side * 0.10), 0.019, m["steel"])
    for k in range(6):
        _along(Q(0.05 + k * 0.05, -0.02), Q(0.05 + k * 0.05, 0.02), 0.005, m["steel_d"], z=0.31, verts=8)
    _along(P(0.42), P(0.49), 0.032, m["steel_d"])
    _along(Q(0.92, -0.05), Q(0.92, 0.05), 0.012, m["steel_d"])
    _rings(m)

def vclamp(m):
    # A small vessel clamp, as it sits across a vessel: two jaws, the spring's loop behind them.
    for side in (-1, 1):
        box(-0.12, side * 0.085, 0.02, 0.95, 0.10, 0.12, m["steel"], 0.03)
        box(-0.36, side * 0.085, 0.14, 0.34, 0.11, 0.02, m["steel_d"], 0.005)
    torus(0.50, 0.0, 0.08, 0.20, 0.055, m["brass"])
    box(0.30, 0.0, 0.02, 0.22, 0.34, 0.12, m["steel_d"], 0.03)

def splicer(m):
    _cone(P(0.0), P(0.12), 0.006, 0.018, m["gold"])
    _along(P(0.12), P(0.46), 0.016, m["steel"])
    _along(P(0.46), P(0.52), 0.045, m["steel_d"])
    _along(P(0.52), P(1.08), 0.07, m["lid"])
    _along(P(0.60), P(0.66), 0.074, m["hazard"])
    _along(P(0.90), P(0.96), 0.074, m["hazard"])
    _along(P(1.08), P(1.16), 0.045, m["steel_d"])

def tuner(m):
    c = P(0.05)
    cyl(c[0], c[1], 0.26, 0.085 * TK * 0.7, 0.04, m["brass"], 0.01, 32)
    _along(P(0.08), P(0.42), 0.02, m["steel"])
    for k in range(5):
        t = 0.16 + k * 0.045
        _along(P(t), P(t + 0.018), 0.034, m["copper"])
    _along(P(0.42), P(1.10), 0.09, m["gun"])
    g = P(0.62)
    box(g[0], g[1], 0.3 + 0.09 * TK - 0.02, 0.2, 0.12, 0.03, m["led_g"], 0.01, rot=math.pi / 4)
    _along(P(1.10), P(1.18), 0.06, m["steel_d"])

def retractor(m):
    # A self-holding rake, seen from above: its prongs (up) hook the wound's edge.
    box(0, 0.42, 0.02, 0.26, 0.55, 0.10, m["steel"], 0.04)
    box(0, 0.10, 0.02, 0.86, 0.14, 0.12, m["steel"], 0.04)
    for k in (-1, 0, 1):
        box(k * 0.32, -0.16, 0.02, 0.12, 0.46, 0.12, m["steel"], 0.04)
        sphere(k * 0.32, -0.40, 0.07, 0.085, m["steel_d"])
    box(0, 0.62, 0.12, 0.30, 0.10, 0.03, m["steel_d"], 0.01)

def table(m, w=3.333, h=2.0):
    box(0, 0, -0.1, w, h, 0.1, m["table"], 0.02)
    mat_ = box(0, 0, 0.0, w - 0.18, h - 0.18, 0.02, m["mat"], 0.01)
    # Machined drain slots along the edges, small screws in the corners.
    for k in range(18):
        x = -w / 2 + 0.3 + k * (w - 0.6) / 17
        for y in (-h / 2 + 0.045, h / 2 - 0.045):
            box(x, y, -0.02, 0.09, 0.025, 0.03, m["hole"])
    for (x, y) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
        cyl(x * (w / 2 - 0.045), y * (h / 2 - 0.045), 0.0, 0.025, 0.012, m["steel"], 0, 12)
        # Corner brackets holding the mat down.
        prism([(x * (w / 2 - 0.1), y * (h / 2 - 0.1)), (x * (w / 2 - 0.34), y * (h / 2 - 0.1)), (x * (w / 2 - 0.1), y * (h / 2 - 0.34))],
            0.02, 0.012, m["steel_d"], 0.004)
        cyl(x * (w / 2 - 0.16), y * (h / 2 - 0.16), 0.03, 0.018, 0.008, m["steel"], 0, 6)
    # The mat's printed grid (every 0.2; a heavier line every 1.0) and ruler ticks along its edges.
    gx = int((w - 0.3) / 0.2 / 2)
    gy = int((h - 0.3) / 0.2 / 2)
    for i in range(-gx, gx + 1):
        heavy = i % 5 == 0
        box(i * 0.2, 0, 0.02, 0.006 if heavy else 0.003, h - 0.3, 0.0015, m["print_h" if heavy else "print"])
        for y in (-h / 2 + 0.13, h / 2 - 0.13):
            box(i * 0.2, y, 0.02, 0.005, 0.05 if heavy else 0.025, 0.002, m["print_h"])
    for j in range(-gy, gy + 1):
        heavy = j % 5 == 0
        box(0, j * 0.2, 0.02, w - 0.3, 0.006 if heavy else 0.003, 0.0015, m["print_h" if heavy else "print"])
    # The power feed: a socket block on the left edge (the first cable starts here).
    box(-w / 2 + 0.07, 0, 0.0, 0.16, 0.3, 0.07, m["steel_d"], 0.02)
    box(-w / 2 + 0.07, 0, 0.07, 0.1, 0.2, 0.02, m["brass"], 0.008)
    for y in (-0.11, 0.11):
        cyl(-w / 2 + 0.07, y, 0.07, 0.016, 0.03, m["steel"], 0, 6)

def lid(m, w=3.333, h=2.0):
    body = box(0, 0, 0, w, h, 0.16, m["lid"], 0.05)
    # A raised inner panel, vents in two corners, ribs.
    box(0, 0, 0.16, w - 1.5, h - 0.75, 0.03, m["lid"], 0.02)
    for k in range(6):
        v = box(-w / 2 + 0.3 + k * 0.07, 0, 0.1, 0.03, 0.5, 0.2, m["hole"])
        cut(body, v)
        v2 = box(w / 2 - 0.3 - k * 0.07, 0, 0.1, 0.03, 0.5, 0.2, m["hole"])
        cut(body, v2)
    for y in (-0.55, 0.55):
        box(0, y, 0.19, w - 1.4, 0.03, 0.012, m["steel_d"], 0.005)
    pw, ph = (w - 1.5) / 2, (h - 0.75) / 2   # the raised panel's half size
    for i in range(13):   # rivets round the panel
        x = -pw + 0.06 + i * (2 * pw - 0.12) / 12
        for y in (-ph + 0.05, ph - 0.05):
            sphere(x, y, 0.19, 0.016, m["steel"], 0.5)
    for (x, y) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:   # corner gussets (clear of the bolts at the very corners)
        cx, cy = x * (w / 2 - 0.3), y * (h / 2 - 0.22)
        prism([(cx, cy - y * 0.1), (cx + x * 0.16, cy - y * 0.1), (cx + x * 0.16, cy + y * 0.02), (cx + x * 0.06, cy + y * 0.1), (cx, cy + y * 0.1)],
            0.16, 0.02, m["steel_d"], 0.006)
        sphere(cx + x * 0.05, cy, 0.18, 0.014, m["steel"], 0.5)
        sphere(cx + x * 0.11, cy - y * 0.05, 0.18, 0.014, m["steel"], 0.5)
    # A data plate (brass, lines of stamped text) and a hazard strip along the panel's foot.
    box(-pw + 0.36, ph - 0.2, 0.19, 0.5, 0.18, 0.008, m["brass"], 0.004)
    for k in range(4):
        box(-pw + 0.36 - (0.06 if k == 3 else 0.0), ph - 0.26 + k * 0.04, 0.198, 0.4 - (0.12 if k == 3 else 0.0), 0.012, 0.002, m["gun"])
    for i in range(14):
        x0 = pw - 1.0 + i * 0.065
        prism([(x0, ph - 0.12), (x0 + 0.035, ph - 0.12), (x0 + 0.065, ph - 0.19), (x0 + 0.03, ph - 0.19)], 0.19, 0.004, m["hazard" if i % 2 == 0 else "gun"])

# --- the list ---------------------------------------------------------------------------------
# name: (builder, view width in units, pixels w, pixels h, centre (Godot), shadow catcher)

R = 1.3   # (a component's picture spans 2.6 x its half size: room for the shadow)
C = 448   # a component's picture, px
JOBS = {
    "circuit": (circuit, 2 * R, C, None, (0, 0), True),
    "conduit": (conduit, 2 * R, C, None, (0, 0), True),
    "servo": (servo, 2 * R, C, None, (0, 0), True),
    "plate": (plate, 2 * R, C, None, (0, 0), True),
    "lens": (lens, 2 * R, C, None, (0, 0), True),
    "cell": (cell, 2 * R, C, None, (0, 0), True),
    "circuit_wreck": (wrecked(circuit, [(0.95, 0.6, 0.34), (-0.2, -0.75, 0.22), (0.1, 0.05, 0.2)], 1), 2 * R, C, None, (0, 0), True),
    "conduit_wreck": (wrecked(conduit, [(0.35, 0.0, 0.3), (-0.95, -0.2, 0.2)], 2), 2 * R, C, None, (0, 0), True),
    "servo_wreck": (wrecked(servo, [(0.8, 0.5, 0.33), (-0.7, -0.6, 0.26), (-0.9, 0.3, 0.18)], 3), 2 * R, C, None, (0, 0), True),
    "plate_wreck": (wrecked(plate, [(0.9, -0.6, 0.36), (-0.3, 0.7, 0.24), (0.0, 0.0, 0.16)], 4), 2 * R, C, None, (0, 0), True),
    "lens_wreck": (wrecked(lens, [(0.6, 0.6, 0.34), (-0.15, -0.1, 0.3)], 5), 2 * R, C, None, (0, 0), True),
    "cell_wreck": (wrecked(cell, [(0.45, -0.6, 0.3), (-0.5, 0.7, 0.24), (0.1, 0.2, 0.2)], 6), 2 * R, C, None, (0, 0), True),
    "bolt": (lambda m: bolt(m), 2.8, 112, None, (0, 0), True),
    "bolt_hole": (lambda m: bolt(m, True), 2.8, 112, None, (0, 0), False),
    "socket": (socket, 2.8, 384, None, (0, 0), False),
    "empty_socket": (empty_socket, 2.4, 384, None, (0, 0), False),
    "clamp_shut": (lambda m: clamp(m, True), 1.6, 80, 128, (0, 0), True),
    "clamp_open": (lambda m: clamp(m, False), 1.6, 80, 128, (0, 0), True),
    "gauge": (gauge, 2.2, 128, None, (0, 0), True),
    "knob": (knob, 2.2, 112, None, (0, 0), True),
    "welder": (welder, 1.5, 128, None, (0.5, 0.5), True),
    "solder": (solder, 1.5, 128, None, (0.5, 0.5), True),
    "sealant": (sealant, 1.5, 128, None, (0.5, 0.5), True),
    "forceps": (forceps, 1.5, 128, None, (0.5, 0.5), True),
    "scalpel": (scalpel, 1.5, 128, None, (0.5, 0.5), True),
    "needle": (needle, 1.5, 128, None, (0.5, 0.5), True),
    "fuser": (fuser, 1.5, 128, None, (0.5, 0.5), True),
    "hemostat": (hemostat, 1.5, 128, None, (0.5, 0.5), True),
    "vclamp": (vclamp, 1.7, 112, 72, (0, 0), True),
    "splicer": (splicer, 1.5, 128, None, (0.5, 0.5), True),
    "tuner": (tuner, 1.5, 128, None, (0.5, 0.5), True),
    "retractor": (retractor, 1.4, 96, 112, (0, 0.1), True),
    "table": (table, 3.333, 1200, 720, (0, 0), False),
    "lid": (lid, 3.6, 1296, 777, (0, 0), True),
}

for name, (fn, wu, pw, ph, ctr, catch) in JOBS.items():
    if ONLY and name not in ONLY:
        continue
    reset()
    _mats.clear()
    _cols.clear()
    m = M()
    if catch:
        shadow_catcher()
    fn(m)
    render(name, wu, pw, ph, ctr)
