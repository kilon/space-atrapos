"""The pirate NPC's sprites, rendered from the Tripo models.

Sources (external/blender/pirate/source/): pirate.glb (rigged by Tripo with a
Mixamo skeleton, T-pose, facing -Y, 0.96 m tall) and gun.glb (muzzle at -X).
The scene: external/blender/pirate.blend.

  setup()          import both (if not in the scene yet), put the gun in the
                   LEFT hand: the gun hangs under the empty "GunCtrl" (its
                   origin = the grip, local -Y = the muzzle, +Z = the top);
                   IK on both forearms - the left hand to the grip, the right
                   hand to "HandR_Goal" (blended from its rest onto the fore-grip).
  POSES            the four key poses of the attack (from the reference frames
                   external/images/npc_pirate_frame_*): rifle hanging at the
                   side, across the body, at the hip, aimed.
  apply_pose(f)    an attack frame (ATTACK: idle, raise1..raise10, aim - 12
                   frames interpolated through the four key POSES, eased).
  apply_walk(k)    frame k of the in-place walk cycle (WALK_N = 28 frames, the
                   rifle hanging in the left hand).
  keyframe_all()   both as actions: PirateAttack (assigned) and PirateWalk, 25 fps.
  render_all(dir)  8 directions x FRAMES (12 attack + 28 walk) ->
                   dir/<frame>_<dir>.png, from the game's view (orthographic,
                   30 degrees above).

Run inside Blender (MCP execute, or blender -b pirate_rig.blend --python ...).
The PNGs are cropped / scaled into art/pirate/ by tools/sprites_from_renders.py.
"""
import json
import math
import os

import bpy
from mathutils import Matrix, Vector

HERE = "/home/kilon/MEGA/Dimitris/godot/space-atrapos/external/blender/pirate/"
SRC = HERE + "source/"
P = "mixamorig:"
GUN_LEN = 0.5                       # the rifle's length (m) - the pirate is 0.96 m
GRIP = Vector((0.25, 0.0, 0.12))    # on gun.glb: the pistol grip (under the hand)
FORE = Vector((-0.02, 0.0, 0.15))   # ... and under the barrel, for the other hand
DIRS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]


def _norm(v):
    return Vector(v).normalized()


def _frame(pos, fwd, up):
    """A matrix with origin pos, local -Y along fwd (the muzzle), +Z ~ up."""
    y = -_norm(fwd)
    z = _norm(up)
    x = y.cross(z).normalized()
    z = x.cross(y).normalized()
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(pos)
    return m


# Per pose: the grip (world, character facing -Y, left = +X), the muzzle
# direction, the gun's top, whether the right hand holds the gun, and the free
# right arm's rotation (idle). Spine twist / lean in radians.
POSES = {
    "idle":   dict(grip=(0.205, -0.02, 0.5), fwd=(0.05, -0.3, -1.0), up=(0.0, -1.0, 0.3), right=0.0,
                   twist=0.0, lean=0.0),
    # (twist / clav found by a search so both hands reach: the arms are short)
    "raise1": dict(grip=(0.07, -0.10, 0.52), fwd=(-0.65, -0.55, -0.45), up=(0.0, 0.0, 1.0), right=1.0,
                   twist=0.55, clav=0.4, lean=0.05),
    "raise2": dict(grip=(0.05, -0.13, 0.55), fwd=(-0.2, -1.0, -0.22), up=(0.0, 0.0, 1.0), right=1.0,
                   twist=0.55, clav=0.4, lean=0.08),
    "aim":    dict(grip=(0.06, -0.16, 0.63), fwd=(-0.08, -1.0, 0.0), up=(0.0, 0.0, 1.0), right=1.0,
                   twist=0.55, clav=0.4, lean=0.1),
}


def _obj(name):
    return bpy.data.objects.get(name)


def _empty(name, parent, size=0.03):
    e = _obj(name)
    if e is None:
        e = bpy.data.objects.new(name, None)
        bpy.data.collections["Pirate"].objects.link(e)
    e.empty_display_size = size
    e.parent = parent
    e.matrix_parent_inverse = Matrix.Identity(4)
    return e


def pirate_mesh():
    return [o for o in bpy.data.collections["Pirate"].objects if o.type == "MESH" and o.name.startswith("tripo")][0]


def gun_mesh():
    return [o for o in bpy.data.collections["Gun"].objects if o.type == "MESH"][0]


def _import(name):
    coll = bpy.data.collections.get(name.capitalize())
    if coll and coll.objects:
        return
    coll = coll or bpy.data.collections.new(name.capitalize())
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SRC + name + ".glb")
    for o in [o for o in bpy.data.objects if o not in before]:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)


def setup():
    _import("pirate")
    _import("gun")
    ico = _obj("Icosphere")              # (the bones' display shape)
    if ico:
        ico.hide_render = ico.hide_viewport = True
    arm = _obj("Armature")
    root = _obj("Node_0")
    # The gun: scaled, turned so the muzzle is local -Y, the grip at GunCtrl.
    ctrl = _empty("GunCtrl", root, 0.06)
    g = gun_mesh()
    k = GUN_LEN / g.dimensions.x if g.parent is None else g.get("pir_k", 1.0)
    g["pir_k"] = k
    rot = Matrix.Rotation(math.pi / 2, 4, "Z")             # -X (muzzle) -> -Y
    g.parent = ctrl
    g.matrix_parent_inverse = Matrix.Identity(4)
    g.matrix_basis = Matrix.Translation(-(rot @ (GRIP * k))) @ rot @ Matrix.Scale(k, 4)
    # IK targets on the gun, poles behind / outside the elbows.
    tl = _empty("IK_HandL", ctrl)
    tl.location = (0, 0, 0)
    tr = _empty("IK_HandR", ctrl)
    tr.location = rot @ ((FORE - GRIP) * k)
    # The right hand's IK goal: blended between its rest at the side and the
    # fore-grip (IK_HandR, on the gun) - so it travels smoothly onto the gun.
    goal = _empty("HandR_Goal", root)
    old = _obj("Rest_R")                   # (before: a second IK switched on and off)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    pl = _empty("Pole_L", root)
    pl.location = (0.45, 0.35, 0.55)
    prr = _empty("Pole_R", root)
    prr.location = (-0.45, 0.35, 0.55)
    for side, tgt, pole in (("Left", tl, pl), ("Right", goal, prr)):
        pb = arm.pose.bones[P + side + "ForeArm"]
        c = pb.constraints.get("IK") or pb.constraints.new("IK")
        c.target = tgt
        c.pole_target = pole
        c.pole_angle = math.radians(-90 if side == "Left" else -90)
        c.chain_count = 2
        c.use_tail = True
        c.influence = 1.0
    pb = arm.pose.bones[P + "RightForeArm"]
    if pb.constraints.get("IK_rest"):
        pb.constraints.remove(pb.constraints["IK_rest"])
    for a in ("PirateWalkHand",):
        if bpy.data.actions.get(a):
            bpy.data.actions.remove(bpy.data.actions[a])
    # (brighter and more saturated than the raw textures - the user found 0.85 / 1.1 too dark)
    grade(pirate_mesh().data.materials[0], sat=1.45, val=1.1, contrast=0.06, hue=0.515)
    grade(gun_mesh().data.materials[0], sat=1.35, val=1.05, contrast=0.08)
    stage()
    return {"gun_scale": round(k, 3)}


# The attack: ATTACK_N frames from idle to aim (idle, raise1 .. raise<N-2>, aim),
# the key poses above at 0, 1/3, 2/3 and 1 of the way, eased in and out;
# in between everything is interpolated - the grip, the rifle's direction, the
# right hand travelling from the side onto the fore-grip, the twist.
# The game plays them over RAISE_TIME (0.45 s): 12 frames ~ 25 fps.
ATTACK_N = 12
_KEYS = ("idle", "raise1", "raise2", "aim")
ATTACK = tuple(["idle"] + ["raise%d" % k for k in range(1, ATTACK_N - 1)] + ["aim"])


def attack_params(t):
    """The pose t of the way (0 idle .. 1 aimed) through the attack."""
    t = t * t * (3.0 - 2.0 * t)                      # (ease in and out)
    x = t * (len(_KEYS) - 1)
    i = min(int(x), len(_KEYS) - 2)
    u = x - i
    a, b = POSES[_KEYS[i]], POSES[_KEYS[i + 1]]
    out = {}
    for key in ("grip", "fwd", "up"):
        va, vb = Vector(a[key]), Vector(b[key])
        if key != "grip":
            va, vb = va.normalized(), vb.normalized()
        out[key] = va.lerp(vb, u)
    for key in ("right", "twist", "lean", "clav"):
        out[key] = a.get(key, 0.0) * (1 - u) + b.get(key, 0.0) * u
    return out


def apply_pose(name):
    """One of the attack frames (ATTACK), or one of the key POSES."""
    if name in ATTACK:
        apply_params(attack_params(ATTACK.index(name) / (ATTACK_N - 1)))
    else:
        apply_params(POSES[name])


def apply_params(p, rest=None):
    """Poses the rig: the rifle (grip / fwd / up), the right hand `right` of the
    way from its rest (`rest`, default REST_R) onto the fore-grip, the spine
    twist / lean, the right collarbone and the neck."""
    arm = _obj("Armature")
    ctrl = _obj("GunCtrl")
    root = _obj("Node_0")
    # The armature is rotated -90 deg (Z) under Node_0 - GunCtrl lives in
    # Node_0's space, which is the world when Node_0 isn't turned.
    ctrl.matrix_basis = _frame(p["grip"], p["fwd"], p["up"])
    bpy.context.view_layer.update()
    fore = root.matrix_world.inverted() @ _obj("IK_HandR").matrix_world.translation
    _obj("HandR_Goal").location = Vector(rest or REST_R).lerp(fore, p["right"])
    sp = arm.pose.bones[P + "Spine1"]
    sp.rotation_mode = "XYZ"
    sp.rotation_euler = (p["lean"], p["twist"], 0.0)
    # The right collarbone brought forward, to reach the fore-grip.
    cl = arm.pose.bones[P + "RightShoulder"]
    cl.rotation_mode = "XYZ"
    cl.rotation_euler = (0.0, 0.0, -p.get("clav", 0.0))
    # The head turned back along the barrel.
    nk = arm.pose.bones[P + "Neck"]
    nk.rotation_mode = "XYZ"
    nk.rotation_euler = (0.0, -p["twist"] * 0.7, 0.0)
    # (no walk: legs straight, hips level, the free hand at rest)
    for b in LEG_BONES:
        pb = arm.pose.bones[P + b]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
    arm.pose.bones[P + "Hips"].location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ walking
# An in-place walk cycle of WALK_N frames (walk1..walkN), the rifle hanging in
# the left hand as in idle. One cycle = two steps = the game's STRIDE (64 px,
# about 0.52 m for this 1 m tall figure on screen): the thighs swing +-WALK_SWING,
# the knee bends in the swing, the foot stays about level, the hips dip on the
# contacts, the free right arm swings against the legs, the rifle sways.
# Axes (found by probing the rig): thigh / knee / foot all turn on local Z -
# thigh -Z = forward, knee +Z = bend, foot +Z = toes down; hips local +Y = up.
WALK_N = 28                # one cycle = 1.1 s in the game (64 px at 58 px/s): ~25 fps
WALK_SWING = 0.32          # rad, the thighs (about 18 deg)
WALK_KNEE = 0.55           # rad, the knee in the swing
WALK_BOB = 0.012           # m, the hips' rise and fall
LEG_BONES = ("LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot")
REST_R = (-0.2, 0.0, 0.47)


def apply_walk(k):
    """Frame k (0..WALK_N-1) of the walk cycle."""
    w = 2 * math.pi * k / WALK_N
    # The rifle sways a little, against the left leg; the right arm swings
    # against the right leg (forward with the left leg).
    p = dict(POSES["idle"])
    p["grip"] = Vector(p["grip"]) + Vector((0.0, 0.03 * math.sin(w), WALK_BOB * math.cos(2 * w)))
    p["fwd"] = Vector(p["fwd"]) + Vector((0.0, -0.12 * math.sin(w), 0.0))
    rx, ry, rz = REST_R
    apply_params(p, rest=(rx, ry - 0.07 * math.sin(w), rz + 0.015 * (1 - math.cos(2 * w))))
    arm = _obj("Armature")
    for side, ph in (("Left", 0.0), ("Right", math.pi)):
        fwd = WALK_SWING * math.sin(w + ph)                      # the thigh forward (+) / back (-)
        swing = math.cos(w + ph)                                 # > 0: the leg is swinging forward
        # bent in the swing, most just after the foot passes under the body; soft in stance
        knee = WALK_KNEE * max(0.0, math.cos(w + ph - 0.45)) ** 1.5 + 0.08
        # level with the ground (undoing thigh and knee); toes down as the foot leaves the ground
        foot = 0.85 * (fwd - knee) + 0.3 * max(0.0, -math.sin(w + ph)) * max(0.0, swing)
        arm.pose.bones[P + side + "UpLeg"].rotation_euler = (0.0, 0.0, -fwd)
        arm.pose.bones[P + side + "Leg"].rotation_euler = (0.0, 0.0, knee)
        arm.pose.bones[P + side + "Foot"].rotation_euler = (0.0, 0.0, foot)
    arm.pose.bones[P + "Hips"].location = (0.0, WALK_BOB * math.cos(2 * w), 0.0)
    bpy.context.view_layer.update()


FRAMES = ATTACK + tuple("walk%d" % (k + 1) for k in range(WALK_N))


def pose_frame(name):
    if name.startswith("walk"):
        apply_walk(int(name[4:]) - 1)
    else:
        apply_pose(name)


def grade(mat, sat, val, contrast, hue=0.5):
    """A colour grade between the base-colour texture and the shader: the Tripo
    textures are paler than the art (more saturation and contrast, darker)."""
    nt = mat.node_tree
    bsdf = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
    hsv = nt.nodes.get("SPR_GradeHSV")
    if hsv is None:
        src = bsdf.inputs["Base Color"].links[0].from_socket
        hsv = nt.nodes.new("ShaderNodeHueSaturation")
        hsv.name = "SPR_GradeHSV"
        bc = nt.nodes.new("ShaderNodeBrightContrast")
        bc.name = "SPR_GradeBC"
        nt.links.new(src, hsv.inputs["Color"])
        nt.links.new(hsv.outputs["Color"], bc.inputs["Color"])
        nt.links.new(bc.outputs["Color"], bsdf.inputs["Base Color"])
    hsv.inputs["Hue"].default_value = hue
    hsv.inputs["Saturation"].default_value = sat
    hsv.inputs["Value"].default_value = val
    nt.nodes["SPR_GradeBC"].inputs["Contrast"].default_value = contrast


def stage():
    sc = bpy.context.scene
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.25, 0.22, 0.26, 1.0)   # (a light ambient lifts the shadows)
        bg.inputs["Strength"].default_value = 1.0
    coll = bpy.data.collections["Pirate"]

    def light(name, loc, energy, color, size):
        ld = bpy.data.lights.get(name) or bpy.data.lights.new(name, "AREA")
        ld.energy, ld.color, ld.size = energy, color, size
        ob = _obj(name) or bpy.data.objects.new(name, ld)
        if ob.name not in coll.objects:
            coll.objects.link(ob)
        ob.location = loc
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = (Vector((0, 0, 0.5)) - Vector(loc)).to_track_quat("-Z", "Y")
    # Fixed to the camera (the character turns, the light doesn't - as in the game).
    light("SPR_Key", (-1.6, -2.2, 2.6), 170, (1.0, 0.88, 0.75), 1.5)
    light("SPR_Rim", (1.5, 1.8, 2.0), 200, (1.0, 0.45, 0.35), 1.2)
    light("SPR_Fill", (2.0, -1.6, 1.0), 90, (0.75, 0.65, 1.0), 2.0)
    dl = _obj("Light")
    if dl:
        dl.hide_render = True
    cd = bpy.data.cameras.get("SpriteCam") or bpy.data.cameras.new("SpriteCam")
    cd.type = "ORTHO"
    cd.ortho_scale = 1.45
    cam = _obj("SpriteCam") or bpy.data.objects.new("SpriteCam", cd)
    if cam.name not in coll.objects:
        for c in list(cam.users_collection):
            c.objects.unlink(cam)
        coll.objects.link(cam)
    tgt = Vector((0, 0, 0.5))
    el = math.radians(30)
    cam.location = tgt + Vector((0, -math.cos(el), math.sin(el))) * 6
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = (tgt - cam.location).to_track_quat("-Z", "Y")
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 1000
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"


def _bake(names, count, pose_fn, bones, legs=False):
    """Keyframes frames 1..count (pose_fn(k) poses frame k) into new actions
    names = {object name: action name}; the actions assigned before stay."""
    arm, ctrl, goal = _obj("Armature"), _obj("GunCtrl"), _obj("HandR_Goal")
    obs = (arm, ctrl, goal)
    keep = {}
    for ob in obs:
        ad = ob.animation_data or ob.animation_data_create()
        old = bpy.data.actions.get(names[ob.name])
        keep[ob.name] = None if ad.action == old else ad.action     # (replaced: not kept)
        ad.action = None
        if old:
            bpy.data.actions.remove(old)
    for k in range(count):
        f = k + 1
        pose_fn(k)
        for b in bones:
            arm.pose.bones[P + b].keyframe_insert("rotation_euler", frame=f)
        if legs:
            arm.pose.bones[P + "Hips"].keyframe_insert("location", frame=f)
        ctrl.keyframe_insert("location", frame=f)
        ctrl.keyframe_insert("rotation_euler", frame=f)
        goal.keyframe_insert("location", frame=f)
    acts = {}
    for ob in obs:
        act = ob.animation_data.action
        act.name = names[ob.name]
        act.use_fake_user = True
        _linear(act)
        acts[ob.name] = act
        ob.animation_data.action = keep[ob.name]
    return acts


def keyframe_all():
    """The attack (ATTACK_N frames) as PirateAttack / -Gun / -Hand, assigned;
    the walk (WALK_N frames) as PirateWalk / -Gun / -Hand (switch to them in
    the Action editor). 25 fps, as the game plays them."""
    names = {"Armature": "PirateAttack", "GunCtrl": "PirateAttackGun", "HandR_Goal": "PirateAttackHand"}
    acts = _bake(names, ATTACK_N, lambda k: apply_pose(ATTACK[k]), ("Spine1", "RightShoulder", "Neck"))
    _bake({"Armature": "PirateWalk", "GunCtrl": "PirateWalkGun", "HandR_Goal": "PirateWalkHand"},
          WALK_N, apply_walk, LEG_BONES, legs=True)
    for name, act in acts.items():
        _obj(name).animation_data.action = act
    for c in ("IK", "IK_rest"):        # (the old switched-IK keys)
        pb = _obj("Armature").pose.bones[P + "RightForeArm"]
        if pb.constraints.get(c):
            pb.constraints[c].influence = 1.0
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, ATTACK_N
    sc.render.fps = 25
    sc.frame_set(1)


def _linear(act):
    """Straight from frame to frame (every frame is a rendered pose)."""
    curves = list(getattr(act, "fcurves", []) or [])
    for layer in getattr(act, "layers", []):          # (layered actions, Blender 4.4+)
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves += list(bag.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def facing_angle(d):
    """Node_0's Z rotation for facing screen direction d (e = right, s = toward
    the camera): the model faces -Y at 0."""
    theta = DIRS.index(d) * math.pi / 4          # screen angle, y down
    return math.pi / 2 - theta


def render_all(out_dir, poses=FRAMES, dirs=DIRS):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    root = _obj("Node_0")
    keep = {}
    for ob in (_obj("Armature"), _obj("GunCtrl"), _obj("HandR_Goal")):
        if ob.animation_data:                      # (poses are set directly)
            keep[ob] = ob.animation_data.action
            ob.animation_data.action = None
    files = []
    for name in poses:
        pose_frame(name)
        for d in dirs:
            root.rotation_mode = "XYZ"
            root.rotation_euler = (0, 0, facing_angle(d))
            bpy.context.view_layer.update()
            sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (name, d))
            bpy.ops.render.render(write_still=True)
            files.append(sc.render.filepath)
    root.rotation_euler = (0, 0, 0)
    # Where the character stands (the root, on the ground) in every picture: it
    # turns about it, so it's the same point in all of them - the sprites'
    # anchor (tools/sprites_from_renders.py -> art/<id>/<id>_anchors.json).
    from bpy_extras.object_utils import world_to_camera_view
    uv = world_to_camera_view(sc, sc.camera, root.matrix_world.translation)
    W = sc.render.resolution_x * sc.render.resolution_percentage // 100
    H = sc.render.resolution_y * sc.render.resolution_percentage // 100
    with open(os.path.join(out_dir, "meta.json"), "w") as fh:
        json.dump({"ground": [round(uv.x * W, 2), round((1.0 - uv.y) * H, 2)], "size": [W, H]}, fh)
    apply_pose("idle")
    for ob, act in keep.items():
        ob.animation_data.action = act
    return files
