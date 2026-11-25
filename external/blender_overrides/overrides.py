"""Your own work on the characters, layered over the generated ones.

The generated characters are built by scripts (external/blender/automaton/:
build.py, kit.py, <skin>.py, moves.py) - rebuilt whenever they change, so
nothing made by hand in their .blend files lasts. Your work lives here instead,
one file a character: external/blender_overrides/<skin>/<skin>_overrides.blend.

In it:
  Reference  - a copy of the generated character: its rig ("Rig"), its parts
               ("gen:Head", "gen:Torso", "gen:Arm.L" ...) and every clip as an
               action ("gen:walk", "gen:swim" ...). Refreshed from the
               generated .blend whenever you like (refresh). Don't edit it: a
               refresh replaces it.
  Overrides  - your parts. A mesh named like a generated part ("Head")
               replaces it; any other name ("Head_Crest") is added. Parent it
               to "Rig" - skinned (an Armature modifier, vertex groups named
               after bones: "head") or on a bone (parent type Bone).
  Actions    - yours, with plain names: "walk" replaces the generated walk,
               a new name ("wave") adds a clip. (To start from a generated one:
               duplicate "gen:walk", rename it "walk".) Actions named "_..." are
               scratch - not exported.

The generated character's export (build.py export) merges all of it in: the
game gets one model either way, and nothing in the game needs to change.

  blender -b --python overrides.py -- <skin> init      # makes <skin>_overrides.blend (once)
  blender -b <skin>_overrides.blend --python ../overrides.py -- <skin> refresh   # the Reference brought up to date
  blender -b --python overrides.py -- <skin> check     # what the export would take, and any problems
(or, in Blender: the Text editor's "refresh_reference" / "export_to_game" scripts, Run Script.)
"""
import os
import re
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
GEN_DIR = os.path.join(os.path.dirname(HERE), "blender", "automaton")   # (every skin's generated .blend is there)
PROJECT = os.path.dirname(os.path.dirname(HERE))
GEN = "gen:"
REF = "Reference"
OVR = "Overrides"
SKIP_OBJECTS = ("KIT_", "SpriteCam")   # (the generated file's lights and camera: not part of the character)


def generated_blend(skin):
    return os.path.join(GEN_DIR, skin + ".blend")


def overrides_blend(skin):
    d = os.environ.get("SA_OVERRIDES_DIR", HERE)   # (a test's own copy, elsewhere)
    return os.path.join(d, skin, skin + "_overrides.blend")


def base(name):
    """A datablock's name without Blender's ".001" suffix."""
    return re.sub(r"\.\d{3}$", "", name)


def _coll(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


# --- In your file: the Reference -----------------------------------------------------

def refresh(skin):
    """The Reference brought up to date from the generated character: its rig's
    bones, its parts and its clips replaced - your Overrides (parented to "Rig")
    and your own actions untouched."""
    path = generated_blend(skin)
    if not os.path.exists(path):
        raise SystemExit("no generated character at %s - build it first (build.py %s model / actions)" % (path, skin))
    ref = _coll(REF)
    _coll(OVR)
    old_rig = bpy.data.objects.get("Rig")
    had_mats = {m.name: m for m in bpy.data.materials}
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if not n.startswith(SKIP_OBJECTS)]
        dst.actions = list(src.actions)
    new_objs = [o for o in dst.objects if o is not None]
    new_rig = next(o for o in new_objs if o.type == "ARMATURE")
    root = next((o for o in new_objs if o.type == "EMPTY" and base(o.name) == "Root"), None)
    # The rig: kept as the same object (your parts stay parented to it), its bones the new ones.
    if old_rig is None:
        rig = new_rig
        rig.name = "Rig"
    else:
        rig = old_rig
        old_data = rig.data
        rig.data = new_rig.data
        rig.data.name = "Rig"
        rig.matrix_world = new_rig.matrix_world.copy()
        bpy.data.objects.remove(new_rig)
        if old_data.users == 0:
            bpy.data.armatures.remove(old_data)
    if root is not None:
        old_root = bpy.data.objects.get("Root")
        if old_root is not None and old_root is not root:
            bpy.data.objects.remove(old_root)
        root.name = "Root"
    # The parts: the old reference ones out, the new ones in (named "gen:<part>").
    for o in list(ref.objects):
        if o not in (rig, root) and o.type == "MESH":
            bpy.data.objects.remove(o)
    for o in new_objs:
        if o is new_rig or o is root or o is rig:
            continue
        if o.type != "MESH":
            bpy.data.objects.remove(o)
            continue
        for c in list(o.users_collection):
            c.objects.unlink(o)
        ref.objects.link(o)
        o.name = GEN + base(o.name)
        o.parent = rig
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = rig
        o.hide_select = True   # (a reference: look, don't touch)
    for o in (rig, root):
        if o is not None:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            ref.objects.link(o)
    if root is not None:
        rig.parent = root
    # The clips: the old generated actions out, the new ones in as "gen:<clip>" (kept on save).
    for a in list(bpy.data.actions):
        if a.name.startswith(GEN) and a not in dst.actions:
            bpy.data.actions.remove(a)
    for a in dst.actions:
        if a is None:
            continue
        a.name = GEN + base(a.name)
        a.use_fake_user = True
    for a in bpy.data.actions:
        if not a.name.startswith(GEN):
            a.use_fake_user = True   # (yours too: an action no rig is playing is otherwise dropped on save)
    if rig.animation_data is None:
        rig.animation_data_create()
    if rig.animation_data.action is None or rig.animation_data.action.name not in bpy.data.actions:
        idle = bpy.data.actions.get(GEN + "idle")
        if idle:
            rig.animation_data.action = idle
    # The materials: the fresh ones take the old names (your parts using "AUT_Armor" get the new one).
    for m in list(bpy.data.materials):
        if m.name in had_mats:
            continue
        b = base(m.name)
        old = had_mats.get(b)
        if old is not None and b != m.name:
            old.user_remap(m)
            bpy.data.materials.remove(old)
            m.name = b
    _hide_overridden()
    for lib in list(bpy.data.libraries):
        if lib.users == 0:
            bpy.data.libraries.remove(lib)
    print("REFRESHED %s: %d parts, %d clips from %s" % (skin, len([o for o in ref.objects if o.type == "MESH"]),
                                                      len([a for a in bpy.data.actions if a.name.startswith(GEN)]), path))


def mirrored_to(o):
    """A left part ("Arm.L") with an X Mirror modifier: the right one it makes too ("Arm.R"), else ""."""
    name = base(o.name)
    if not name.endswith(".L"):
        return ""
    for m in o.modifiers:
        if m.type == "MIRROR" and m.use_axis[0] and m.show_render:
            return name[:-2] + ".R"
    return ""


def _hide_overridden():
    """A generated part your Overrides replace: hidden in the Reference (so you see yours in its place) -
    a mirrored left part's right one too."""
    mine = {base(o.name) for o in _coll(OVR).all_objects if o.type == "MESH"}
    mine |= {mirrored_to(o) for o in _coll(OVR).all_objects if o.type == "MESH"} - {""}
    for o in _coll(REF).objects:
        if o.name.startswith(GEN):
            hide = o.name[len(GEN):] in mine
            o.hide_viewport = hide
            o.hide_render = hide


def init(skin):
    """A new overrides file for `skin`: the Reference, an empty Overrides
    collection - and, to start from, a copy of the generated head as your "Head"
    (the same as the generated one until you change it: delete it to go back)."""
    path = overrides_blend(skin)
    if os.path.exists(path):
        raise SystemExit("%s exists already - refresh it instead" % path)
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.context.scene.name = skin + " overrides"
    refresh(skin)
    rig = bpy.data.objects["Rig"]
    gen_head = bpy.data.objects.get(GEN + "Head")
    if gen_head is not None:
        head = gen_head.copy()
        head.data = gen_head.data.copy()
        head.name = "Head"
        head.data.name = "Head"
        head.hide_select = False
        head.hide_viewport = False
        head.hide_render = False
        for m in list(head.modifiers):
            if m.type != "ARMATURE":
                head.modifiers.remove(m)   # (the generated ink shell: not wanted)
        if "ink" in head.vertex_groups:
            head.vertex_groups.remove(head.vertex_groups["ink"])
        ink = head.data.materials.find("KIT_Ink")
        if ink >= 0:
            head.data.materials.pop(index=ink)
        _coll(OVR).objects.link(head)
        head.parent = rig
    _hide_overridden()
    _scripts(skin)
    # A plain light and a view onto the head, for a start.
    bpy.context.scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else bpy.context.scene.render.engine
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.rotation_euler = (0.8, 0.2, 0.6)
    bpy.context.scene.collection.objects.link(sun)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, relative_remap=True)
    print("MADE", path)


def _scripts(skin):
    """Two scripts in the file's Text editor: refresh the Reference; export to the game."""
    refresh_src = '''# Run Script (Alt+P): the Reference brought up to date from the generated %(skin)s.
import bpy, sys, os
d = bpy.path.abspath("//..")
sys.path.insert(0, d)
import importlib, overrides
importlib.reload(overrides)
overrides.refresh("%(skin)s")
''' % {"skin": skin}
    export_src = '''# Run Script (Alt+P): this file saved, then the game's %(skin)s exported with your
# overrides merged in (build.py export) and Godot's import run. Watch the console.
import bpy, subprocess, os, sys
bpy.ops.wm.save_mainfile()
here = bpy.path.abspath("//")
gen = os.path.normpath(os.path.join(here, "..", "..", "blender", "automaton"))
project = os.path.normpath(os.path.join(here, "..", "..", ".."))
r = subprocess.run([bpy.app.binary_path, "-b", os.path.join(gen, "%(skin)s.blend"), "--python",
                    os.path.join(gen, "build.py"), "--", "%(skin)s", "export"], capture_output=True, text=True)
out = r.stdout + r.stderr
print("\\n".join(l for l in out.splitlines() if l.startswith(("EXPORTED", "OVERRIDE", "Error", "Traceback"))) or out[-3000:])
try:
    subprocess.run(["godot", "--headless", "--path", project, "--import"], capture_output=True, timeout=600)
    print("Godot import done: restart the game (or its window) to see it.")
except Exception as e:
    print("Godot import not run (%%s): open the project in Godot, or run godot --headless --import" %% e)
''' % {"skin": skin}
    for name, src in (("refresh_reference", refresh_src), ("export_to_game", export_src)):
        t = bpy.data.texts.get(name) or bpy.data.texts.new(name)
        t.from_string(src)


# --- In the export: your work merged in -----------------------------------------------

def apply(skin, arm, coll, log=print):
    """Called by build.py's export on the generated character (`arm`: its rig,
    `coll`: its collection): your Overrides' parts and actions brought in -
    a part with a generated part's name replacing it, others added; an action
    with a clip's name replacing it, others added. Returns
    {"parts": {name: "replaced" | "added"}, "clips": {name: "replaced" | "added"}, "problems": [...]}."""
    out = {"parts": {}, "clips": {}, "problems": []}
    path = overrides_blend(skin)
    if not os.path.exists(path):
        return out
    bones = {b.name for b in arm.data.bones}
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.collections = [OVR] if OVR in src.collections else []
        dst.actions = [n for n in src.actions if not n.startswith((GEN, "_"))]
    mine = []
    if dst.collections and dst.collections[0] is not None:
        oc = dst.collections[0]
        mine = [o for o in oc.all_objects if o.type == "MESH" and not o.hide_render]
    gen_parts = {o.name: o for o in coll.objects if o.type == "MESH" and o.parent == arm}
    gen_low = {n: min((o.matrix_world @ v.co).z for v in o.data.vertices) for n, o in gen_parts.items() if len(o.data.vertices)}
    for o in mine:
        name = base(o.name)
        twin = mirrored_to(o)   # (a left part mirrored: the generated right one goes too - the mirror makes it)
        # On the generated rig: parented to it, skinned to it - as yours were to the Reference's "Rig".
        mw = o.matrix_world.copy()
        o.parent = arm
        o.matrix_world = mw
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = arm
        if o.parent_type == "BONE" and o.parent_bone not in bones:
            out["problems"].append("%s: on bone %r - the rig has no such bone" % (name, o.parent_bone))
        groups = [g.name for g in o.vertex_groups if g.name != "ink"]
        if o.parent_type != "BONE":
            if not groups:
                out["problems"].append("%s: no vertex groups - skin it to bones (e.g. a group \"head\" with every vertex)" % name)
            unknown = [g for g in groups if g not in bones]
            if unknown:
                out["problems"].append("%s: vertex groups %s aren't bones of the rig" % (name, unknown))
            if groups:
                n = _weigh_strays(o)
                if n:
                    out.setdefault("notes", []).append("%s: %d vertices were on no bone (added geometry not assigned to a vertex group) - "
                                                       "given the bones of the nearest weighted vertex; assign them in Blender to choose" % (name, n))
        # Its materials: the generated ones where the names match (the game knows those: their look, their recolouring).
        for i, slot in enumerate(o.material_slots):
            mat = slot.material
            if mat is None:
                continue
            known = bpy.data.materials.get(base(mat.name))
            if known is not None and known is not mat and known.library is None and base(mat.name) == known.name:
                o.material_slots[i].material = known
            elif not base(mat.name).startswith(("AUT_", "KIT_", "MIN_", "PIR_", "KIL_")):
                out["problems"].append("%s: material %r is new to the game - it'll get a plain look (name it after a known one, "
                                       "or ask for it to be taught)" % (name, mat.name))
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        baked = _bake_modifiers(o)   # (in the scene now: its modifiers evaluated)
        if baked:
            out.setdefault("notes", []).append("%s: its %s modifier%s applied for the game (the Armature kept)" % (
                name, ", ".join(baked), "s" if len(baked) > 1 else ""))
        if name in gen_parts:
            g = gen_parts.pop(name)
            low = min((o.matrix_world @ v.co).z for v in o.data.vertices) if len(o.data.vertices) else 0.0
            if name in gen_low and low > gen_low[name] + 0.03:
                out["problems"].append("%s: its lowest point is %.0f mm above the generated one's - a gap at the join?" % (
                    name, (low - gen_low[name]) * 1000.0))
            bpy.data.objects.remove(g)
            out["parts"][name] = "replaced"
        else:
            out["parts"][name] = "added"
        if twin and twin in gen_parts:
            bpy.data.objects.remove(gen_parts.pop(twin))
            out["parts"][twin] = "mirrored from %s" % name
        o.name = name
    # Anything else the parts dragged in (the Reference's rig, its root): not wanted.
    for o in list(bpy.data.objects):
        if o is not arm and o not in mine and not o.users_scene:
            bpy.data.objects.remove(o)
    if dst.collections and dst.collections[0] is not None:
        bpy.data.collections.remove(dst.collections[0])
    for a in dst.actions:
        if a is None:
            continue
        name = base(a.name)
        old = bpy.data.actions.get(name)
        if old is not None and old is not a:
            bpy.data.actions.remove(old)
            out["clips"][name] = "replaced"
        else:
            out["clips"][name] = "added"
        a.name = name
    for p in out["problems"]:
        log("OVERRIDE PROBLEM: " + p)
    for p in out.get("notes", []):
        log("OVERRIDE NOTE: " + p)
    for k, v in out["parts"].items():
        log("OVERRIDE part %s: %s" % (k, v))
    for k, v in out["clips"].items():
        log("OVERRIDE clip %s: %s" % (k, v))
    return out


def _bake_modifiers(o):
    """Your part's modifiers other than the Armature (a Mirror, a Subdivision, a Bevel...)
    applied into its mesh for the game (the glTF export leaves modifiers live: a mirrored
    half would come out half) - its vertex groups kept, so it's still skinned; the Armature
    modifier stays. Done on the export's own copy, never your file. The modifiers' types."""
    others = [m for m in o.modifiers if m.type != "ARMATURE"]
    if not others or o.type != "MESH":
        return []
    arms = [m for m in o.modifiers if m.type == "ARMATURE"]
    was = [m.show_viewport for m in arms]
    for m in arms:
        m.show_viewport = False   # (the mesh at rest: the armature deforms it in the game)
    for m in others:
        m.show_viewport = True
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    new = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    for m, w in zip(arms, was):
        m.show_viewport = w
    types = [m.type.capitalize() for m in others]
    for m in others:
        o.modifiers.remove(m)
    old = o.data
    o.data = new
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return types


def _weigh_strays(o):
    """A skinned part's vertices on no bone (geometry added in Edit Mode isn't put in a
    vertex group by itself - the armature then never moves it): each given the bone
    weights of the nearest vertex that has some. How many there were."""
    from mathutils import kdtree
    me = o.data
    real = {g.index for g in o.vertex_groups if g.name != "ink"}
    weighted = [v for v in me.vertices if any(g.group in real and g.weight > 0.0 for g in v.groups)]
    strays = [v for v in me.vertices if not any(g.group in real and g.weight > 0.0 for g in v.groups)]
    if not strays or not weighted:
        return 0
    kd = kdtree.KDTree(len(weighted))
    for i, v in enumerate(weighted):
        kd.insert(v.co, i)
    kd.balance()
    for v in strays:
        _, i, _ = kd.find(v.co)
        for g in weighted[i].groups:
            if g.group in real and g.weight > 0.0:
                o.vertex_groups[g.group].add([v.index], g.weight, "REPLACE")
    return len(strays)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) < 2:
        print(__doc__)
        return
    skin, cmd = argv[0], argv[1]
    if cmd == "init":
        init(skin)
    elif cmd == "refresh":
        refresh(skin)
        bpy.ops.wm.save_mainfile()
    elif cmd == "check":
        bpy.ops.wm.open_mainfile(filepath=generated_blend(skin))
        arm = bpy.data.objects["Rig"]
        coll = arm.users_collection[0]
        r = apply(skin, arm, coll)
        print("CHECK %s: parts %s, clips %s, %d problem(s)" % (skin, r["parts"], r["clips"], len(r["problems"])))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
