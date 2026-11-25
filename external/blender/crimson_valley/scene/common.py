"""Shared Blender helpers of the Crimson Valley scene (import bpy; Blender 5.2).

The scene is built from PARTS. A part is a module scene/part_<name>.py with

    def build(col):      # create the part's objects, link them into the collection `col`
    def finalize(scene): # optional: runs in the assembled scene, after every part is in (cross-part wiring)

`build_part.py` runs one part in an empty scene and saves parts/<name>.blend; `assemble.py` appends every
built part into crimson_valley.blend. Parts never reference another part's datablocks: what they share
goes through files (analysis/, meshes/) - so they can be built and tested alone, in any order.

World units are metres: X right, Y into the picture, Z up; the river is z = 0; the camera stands at
(0, 0, 20) looking along +Y (see tools/cvlib.py, analysis/camera.json). Datablocks are named "CV_...".
"""
import fcntl
import importlib
import math
import os
import sys
import time

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, HERE)
import cvlib  # noqa: E402

ANALYSIS = os.path.join(ROOT, "analysis")
MESHES = os.path.join(ROOT, "meshes")
PARTS = os.path.join(ROOT, "parts")
RENDERS = os.path.join(ROOT, "renders")
REFERENCE = cvlib.REFERENCE
FINAL_BLEND = os.path.join(ROOT, "crimson_valley.blend")
W, H = cvlib.W, cvlib.H
WORLD_NAME = "CV_World"
COMPOSITOR_NAME = "CV_Compositing"
CAMERA_NAME = "CV_Camera"
GPU_LOCK = os.path.join(os.path.expanduser("~"), ".cache", "crimson_valley_tools", "gpu.lock")

# The order parts are assembled in (missing ones are skipped). World and compositor come from the
# parts named here.
PART_ORDER = ["sky", "planet", "moons", "clouds", "far", "terrain", "rocks", "water", "vegetation",
              "city", "waterfalls", "mist", "lighting", "grade"]
WORLD_PART = "sky"
COMPOSITOR_PART = "grade"


# --------------------------------------------------------------------------------------------- scene
def cam_model():
    return cvlib.load_camera()


def reset_scene():
    """An empty file with the scene's camera and render settings."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "Crimson Valley"
    scene.unit_settings.system = "METRIC"
    make_camera(scene)
    setup_render(scene)
    return scene


def make_camera(scene):
    cm = cam_model()
    cam = bpy.data.cameras.new(CAMERA_NAME)
    cam.lens = cm.lens_mm
    cam.sensor_width = cm.sensor_width
    cam.sensor_fit = "HORIZONTAL"
    cam.clip_start = 0.5
    cam.clip_end = 200000.0
    ob = bpy.data.objects.new(CAMERA_NAME, cam)
    ob.location = tuple(cm.pos)
    ob.rotation_euler = (math.pi / 2 - cm.pitch, 0.0, 0.0)
    scene.collection.objects.link(ob)
    scene.camera = ob
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.resolution_percentage = 100
    # The reference behind the camera view, to compare in the viewport (not rendered).
    try:
        img = bpy.data.images.load(REFERENCE, check_existing=True)
        img.name = "CV_Reference"
        cam.show_background_images = True
        bg = cam.background_images.new()
        bg.image = img
        bg.alpha = 0.5
        bg.display_depth = "FRONT"
        bg.show_background_image = False       # off by default: toggle in Camera > Background Images
    except Exception as ex:                     # the picture is a convenience, never a blocker
        print("reference background not set:", ex)
    return ob


def enable_gpu():
    """Cycles on the GPU (OptiX), from a factory-settings session."""
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        found = False
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
            found = found or d.use
        return found
    except Exception as ex:
        print("GPU not enabled:", ex)
        return False


def setup_render(scene, engine="CYCLES", samples=96, scale=100):
    r = scene.render
    r.engine = engine
    r.resolution_x, r.resolution_y, r.resolution_percentage = W, H, scale
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.film_transparent = False
    if engine == "CYCLES":
        c = scene.cycles
        c.device = "GPU" if enable_gpu() else "CPU"
        c.samples = samples
        c.use_adaptive_sampling = True
        c.adaptive_threshold = 0.02
        c.use_denoising = True
        try:
            c.denoiser = "OPTIX" if c.device == "GPU" else "OPENIMAGEDENOISE"
        except Exception:
            pass
        c.max_bounces = 6
        c.diffuse_bounces = 3
        c.glossy_bounces = 4
        c.transmission_bounces = 6
        c.transparent_max_bounces = 16
        c.volume_bounces = 1
        c.caustics_reflective = False
        c.caustics_refractive = False
    # "Standard": what a material emits or reflects is what the picture shows (the reference is an
    # ordinary sRGB picture, so its colours can be matched directly: linear = srgb_to_linear(pixel)).
    set_view(scene, "Standard", "None")


def set_view(scene, transform, look=None, exposure=None, gamma=None):
    """View transform / look by name; unknown names are reported and left as they were."""
    vs = scene.view_settings
    try:
        vs.view_transform = transform
    except Exception as ex:
        print("view transform", transform, "not set:", ex)
    if look is not None:
        for name in (look, look.replace("AgX - ", ""), "None"):
            try:
                vs.look = name
                break
            except Exception:
                continue
    if exposure is not None:
        vs.exposure = exposure
    if gamma is not None:
        vs.gamma = gamma


def render(scene, path, scale=None, samples=None):
    """Render the camera view to `path` (PNG). One render at a time across processes (a file lock),
    so parallel builds share the GPU without running out of memory."""
    if scale is not None:
        scene.render.resolution_percentage = scale
    if samples is not None and scene.render.engine == "CYCLES":
        scene.cycles.samples = samples
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    os.makedirs(os.path.dirname(GPU_LOCK), exist_ok=True)
    t0 = time.time()
    with open(GPU_LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        t1 = time.time()
        bpy.ops.render.render(write_still=True)
        fcntl.flock(lock, fcntl.LOCK_UN)
    print(f"RENDERED {path} in {time.time() - t1:.1f} s (waited {t1 - t0:.1f} s for the GPU)")


# --------------------------------------------------------------------------------------------- parts
def part_module(name):
    return importlib.import_module("part_" + name)


def part_path(name):
    return os.path.join(PARTS, name + ".blend")


def new_collection(scene, name):
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    return col


def append_part(scene, name):
    """Bring a built part into the scene: its collection, and (for the world / compositor parts)
    the world and the compositing node group. Returns the collection or None."""
    path = part_path(name)
    if not os.path.exists(path):
        return None
    want_world = name == WORLD_PART
    want_comp = name == COMPOSITOR_PART
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.collections = [c for c in src.collections if c == name]
        if want_world and WORLD_NAME in src.worlds:
            dst.worlds = [WORLD_NAME]
        if want_comp and COMPOSITOR_NAME in src.node_groups:
            dst.node_groups = [COMPOSITOR_NAME]
    col = dst.collections[0] if dst.collections else None
    if col is not None:
        scene.collection.children.link(col)
    if want_world and dst.worlds:
        scene.world = dst.worlds[0]
    if want_comp and dst.node_groups:
        try:
            scene.compositing_node_group = dst.node_groups[0]
        except Exception as ex:
            print("compositor not set:", ex)
    return col


def preview_world(scene, color=(0.35, 0.42, 0.55), strength=0.6):
    """A plain sky colour for looking at a part alone."""
    w = bpy.data.worlds.new("CV_PreviewWorld")
    nt = node_tree(w)
    bg = nt.nodes.get("Background") or nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (*color, 1.0)
    bg.inputs["Strength"].default_value = strength
    out = nt.nodes.get("World Output") or nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    scene.world = w
    return w


def preview_sun(scene, azimuth_deg=200.0, elevation_deg=14.0, strength=4.0, color=(1.0, 0.72, 0.5)):
    """A low warm sun for looking at a part alone. Azimuth: the direction the light comes FROM,
    degrees clockwise from +Y seen from above (0 = from ahead of the camera, 90 = from the right,
    180 = from behind the camera, 270 = from the left)."""
    light = bpy.data.lights.new("CV_PreviewSun", "SUN")
    light.energy = strength
    light.color = color
    light.angle = math.radians(2.0)
    ob = bpy.data.objects.new("CV_PreviewSun", light)
    scene.collection.objects.link(ob)
    aim_sun(ob, azimuth_deg, elevation_deg)
    return ob


def aim_sun(ob, azimuth_deg, elevation_deg):
    """Point a sun lamp so its light comes from the given azimuth / elevation (see preview_sun)."""
    az, el = math.radians(azimuth_deg), math.radians(elevation_deg)
    # direction the light travels (from the sun towards the scene)
    d = (-math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), -math.sin(el))
    import mathutils
    ob.rotation_euler = mathutils.Vector(d).to_track_quat("-Z", "Y").to_euler()


# ----------------------------------------------------------------------------------------- datablocks
def node_tree(idblock):
    """The node tree of a material / world, with nodes switched on (Blender 5: always on)."""
    try:
        if not idblock.node_tree:
            idblock.use_nodes = True
    except Exception:
        pass
    return idblock.node_tree


def new_material(name):
    """A fresh material with an empty node tree: returns (material, nodes, links)."""
    mat = bpy.data.materials.new(name)
    nt = node_tree(mat)
    nt.nodes.clear()
    return mat, nt.nodes, nt.links


def mesh_object(name, verts, faces, col, smooth=True, attributes=None, uvs=None, flat_faces=None):
    """A mesh object from numpy arrays. verts (N, 3) float; faces (M, 3) or (M, 4) int, or a list of
    index lists. flat_faces: bool (M,) faces to leave flat-shaded. attributes: {name: (N,) or (N, k) float array} stored per vertex (FLOAT / FLOAT_VECTOR /
    FLOAT_COLOR for k = 4). uvs: (N, 2) per-vertex UVs written to a UV map "UVMap"."""
    verts = np.asarray(verts, dtype=np.float32)
    me = bpy.data.meshes.new(name)
    if isinstance(faces, np.ndarray) and faces.ndim == 2:
        k = faces.shape[1]
        me.vertices.add(len(verts))
        me.vertices.foreach_set("co", verts.ravel())
        me.loops.add(faces.size)
        me.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
        me.polygons.add(len(faces))
        me.polygons.foreach_set("loop_start", np.arange(0, faces.size, k, dtype=np.int32))
        me.polygons.foreach_set("loop_total", np.full(len(faces), k, dtype=np.int32))
        me.update(calc_edges=True)
    else:
        me.from_pydata([tuple(map(float, v)) for v in verts], [], [list(map(int, f)) for f in faces])
        me.update()
    if smooth and len(me.polygons):
        sm = np.ones(len(me.polygons), dtype=bool)
        if flat_faces is not None:               # these faces stay flat: normals split along their edges
            sm &= ~np.asarray(flat_faces, dtype=bool)
        me.polygons.foreach_set("use_smooth", sm)
    for an, arr in (attributes or {}).items():
        arr = np.asarray(arr, dtype=np.float32)
        if arr.ndim == 1:
            at = me.attributes.new(an, "FLOAT", "POINT")
            at.data.foreach_set("value", arr)
        elif arr.shape[1] == 3:
            at = me.attributes.new(an, "FLOAT_VECTOR", "POINT")
            at.data.foreach_set("vector", arr.ravel())
        elif arr.shape[1] == 4:
            at = me.attributes.new(an, "FLOAT_COLOR", "POINT")
            at.data.foreach_set("color", arr.ravel())
        elif arr.shape[1] == 2:
            at = me.attributes.new(an, "FLOAT2", "POINT")
            at.data.foreach_set("vector", arr.ravel())
    if uvs is not None:
        uv = me.uv_layers.new(name="UVMap")
        li = np.empty(len(me.loops), dtype=np.int32)
        me.loops.foreach_get("vertex_index", li)
        uv.data.foreach_set("uv", np.asarray(uvs, dtype=np.float32)[li].ravel())
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def load_npz_mesh(path):
    """A mesh saved by the tools: dict with 'verts', 'faces' and any per-vertex attributes."""
    z = np.load(path)
    return {k: z[k] for k in z.files}


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    print("SAVED", path, f"{os.path.getsize(path) / 1e6:.1f} MB")


def srgb_to_linear(c):
    """sRGB 0..1 (or 0..255 ints, or "#rrggbb") -> scene-linear RGB tuple, for node colours."""
    if isinstance(c, str):
        c = [int(c.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    c = [float(x) for x in c[:3]]
    if max(c) > 1.0:
        c = [x / 255.0 for x in c]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def rgba(c, a=1.0):
    """Node colour (r, g, b, a) in scene-linear from an sRGB colour (see srgb_to_linear)."""
    return (*srgb_to_linear(c), a)


def args_after_dashes():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
