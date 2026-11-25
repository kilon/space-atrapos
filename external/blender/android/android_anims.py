"""The Minoan android's animations (build_android.py builds the model and rig)
and its sprite renders - all at 25 fps, the game's sprite rate.

Clips (each a set of actions, one per animated object, with a fake user;
AndroidIdle assigned; switch clips with use_clip(name) or in the Action editor):
  Idle  50 frames (2 s)  breathing, a slow weight shift, glances; rifle at the ready
  Walk  28 frames        one full cycle in place (two steps: 64 px in 1.1 s in the game)
  Aim   10 frames        shouldering the rifle (spine turns, head follows the barrel)
  Fire   6 frames        a shot: muzzle flash, recoil, settling back on aim

Animated: AndroidRig (hips, spine, neck, head), FootIK.L / .R (the legs are IK
to them), RifleCtrl (the hands are IK to the rifle), MuzzleFlash.

  render_all(out_dir)   every clip frame from 8 directions (the game's camera:
                        orthographic, 30 degrees above) -> out_dir/<clip><n>_<dir>.png
                        + meta.json (where the character stands); then
                        tools/sprites_from_renders.py makes the game's sprites.
Run: blender -b android.blend --python-expr "import android_anims as a; a.render_all('renders')"
(with this folder on sys.path), or exec in the open Blender.
"""
import json  # noqa
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

LIFT = 0.13
FPS = 25
DIRS = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
CLIPS = {"Idle": 50, "Walk": 28, "Aim": 10, "Fire": 6}
HIP_X, ANKLE_Z = 0.13, 0.15

CARRY = dict(grip=(-0.12, -0.24, 1.12 + LIFT), fwd=(0.55, -0.75, -0.35), up=(0.3, 0.1, 1.0))
AIM = dict(grip=(-0.07, -0.24, 1.5), fwd=(0.0, -1.0, 0.02), up=(0.0, 0.0, 1.0))
AIM_TWIST = -0.42     # spine yaw when aiming (the left shoulder comes forward)


def _obj(n):
    return bpy.data.objects.get(n)


def _rig():
    return _obj("AndroidRig")


# ---------------------------------------------------------------- posing

def rifle_at(grip, fwd, up=(0, 0, 1)):
    y = -Vector(fwd).normalized()
    z = Vector(up).normalized()
    x = y.cross(z).normalized()
    z = x.cross(y).normalized()
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(grip)
    _obj("RifleCtrl").matrix_world = _obj("AndroidRoot").matrix_world @ m
    bpy.context.view_layer.update()


def _lerp_pose(a, b, t):
    return {k: tuple(Vector(a[k]).lerp(Vector(b[k]), t)) for k in a}


def reset():
    rig = _rig()
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
    for s, sx in (("L", 1), ("R", -1)):
        _obj("FootIK." + s).location = (HIP_X * sx, 0, ANKLE_Z)
    fl = _obj("MuzzleFlash")
    if fl:
        fl.scale = (0.001, 0.001, 0.001)
    bpy.context.view_layer.update()


def body(drop=0.02, sway=0.0, twist=0.0, lean=0.0, head_yaw=0.0, head_pitch=0.0, breathe=0.0):
    """The upper body: hips lowered by drop (knees bent a little), swayed /
    twisted; the spine leans; the head looks."""
    pb = _rig().pose.bones
    pb["hips"].location = (0, -drop, 0)              # (bone Y = up)
    pb["hips"].rotation_euler = (0, sway, 0)          # (about the bone's own axis: a yaw)
    pb["spine"].rotation_euler = (lean + breathe, twist, 0)
    pb["neck"].rotation_euler = (-0.5 * lean, -0.4 * twist, 0)
    pb["head"].rotation_euler = (head_pitch, 0, head_yaw)   # (the head bone points forward: Z is its yaw)
    bpy.context.view_layer.update()


def pose_idle(k, n=CLIPS["Idle"]):
    reset()
    t = 2 * math.pi * k / n
    body(drop=0.02 + 0.004 * math.sin(t), sway=0.03 * math.sin(t), breathe=0.012 * math.sin(2 * t),
         head_yaw=0.12 * math.sin(t + 0.6), head_pitch=0.03 * math.sin(2 * t))
    c = dict(CARRY)
    c["grip"] = tuple(Vector(c["grip"]) + Vector((0, 0, 0.006 * math.sin(2 * t))))
    rifle_at(**c)


DUTY = 0.6
STEP = 0.40          # m, a foot's travel front to back
LIFT_H = 0.11        # m, a foot's lift in the swing


def _gait(u):
    """[forward 1..-1, lift 0..1] of a foot at cycle position u (0 = heel strike)."""
    u %= 1.0
    if u < DUTY:
        return 1.0 - 2.0 * u / DUTY, 0.0
    g = (u - DUTY) / (1.0 - DUTY)
    e = 0.5 - 0.5 * math.cos(math.pi * g)
    return -1.0 + 2.0 * e, math.sin(math.pi * g)


def pose_walk(k, n=CLIPS["Walk"]):
    reset()
    u = k / n
    for s, sx, off in (("L", 1, 0.0), ("R", -1, 0.5)):
        fwd, lift = _gait(u + off)
        _obj("FootIK." + s).location = (HIP_X * sx, -fwd * STEP / 2, ANKLE_Z + lift * LIFT_H)
    t = 2 * math.pi * u
    # Hips: lowest just after each heel strike, highest mid-stance; the pelvis
    # turns with the legs, the chest against it.
    body(drop=0.06 + 0.025 * math.cos(2 * t), sway=0.12 * math.sin(t), twist=-0.1 * math.sin(t),
         lean=0.05, head_yaw=0.04 * math.sin(t))
    c = dict(CARRY)
    c["grip"] = tuple(Vector(c["grip"]) + Vector((0.01 * math.sin(t), 0, 0.012 * math.cos(2 * t))))
    rifle_at(**c)


def pose_aim(k, n=CLIPS["Aim"]):
    reset()
    t = k / (n - 1)
    e = t * t * (3 - 2 * t)
    body(drop=0.03, twist=AIM_TWIST * e, lean=0.04 * e, head_yaw=-AIM_TWIST * 0.6 * e, head_pitch=0.08 * e)
    rifle_at(**_lerp_pose(CARRY, AIM, e))


def pose_fire(k, n=CLIPS["Fire"]):
    reset()
    kick = [1.0, 0.75, 0.45, 0.22, 0.08, 0.0][min(k, 5)]
    body(drop=0.03, twist=AIM_TWIST, lean=0.04 - 0.03 * kick, head_yaw=-AIM_TWIST * 0.6, head_pitch=0.08)
    a = dict(AIM)
    a["grip"] = tuple(Vector(a["grip"]) + Vector((0, 0.05 * kick, 0.015 * kick)))
    a["fwd"] = tuple(Vector(a["fwd"]) + Vector((0, 0, 0.12 * kick)))
    rifle_at(**a)
    fl = _obj("MuzzleFlash")
    if fl:
        s = [1.0, 0.6, 0.001, 0.001, 0.001, 0.001][min(k, 5)]
        fl.scale = (s, s, s)


POSERS = {"Idle": pose_idle, "Walk": pose_walk, "Aim": pose_aim, "Fire": pose_fire}


# ---------------------------------------------------------------- the muzzle flash

def make_flash():
    """A glowing star at the muzzle (on the rifle), shown only when firing."""
    if _obj("MuzzleFlash"):
        return
    import bmesh
    bm = bmesh.new()
    pts = []
    for i in range(16):
        r = 0.16 if i % 2 == 0 else 0.05
        a = 2 * math.pi * i / 16
        pts.append(bm.verts.new((r * math.cos(a), 0, r * math.sin(a))))
    c = bm.verts.new((0, 0, 0))
    for i in range(16):
        bm.faces.new((c, pts[i], pts[(i + 1) % 16]))
    # (and one along the barrel, seen from the side)
    a1 = bm.verts.new((0, -0.3, 0))
    a2 = bm.verts.new((0.05, -0.02, 0))
    a3 = bm.verts.new((-0.05, -0.02, 0))
    a4 = bm.verts.new((0, -0.02, 0.05))
    a5 = bm.verts.new((0, -0.02, -0.05))
    bm.faces.new((a1, a2, a4))
    bm.faces.new((a1, a4, a3))
    bm.faces.new((a1, a3, a5))
    bm.faces.new((a1, a5, a2))
    me = bpy.data.meshes.new("MuzzleFlash")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bpy.data.materials["AND_Eye"])
    ob = bpy.data.objects.new("MuzzleFlash", me)
    bpy.data.collections["Android"].objects.link(ob)
    ob.parent = _obj("RifleCtrl")
    ob.location = (0, -0.63, 0.07)
    ob.scale = (0.001, 0.001, 0.001)


# ---------------------------------------------------------------- actions

ANIMATED = ("AndroidRig", "RifleCtrl", "FootIK.L", "FootIK.R", "MuzzleFlash")


def _linear(act):
    curves = list(getattr(act, "fcurves", []) or [])
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves += list(bag.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def bake(clip):
    """Keyframes clip frames 1..n into actions Android<clip>[<object>]."""
    n = CLIPS[clip]
    for name in ANIMATED:
        ob = _obj(name)
        ad = ob.animation_data or ob.animation_data_create()
        ad.action = None
        old = bpy.data.actions.get(_act_name(clip, name))
        if old:
            bpy.data.actions.remove(old)
    rig = _rig()
    for k in range(n):
        f = k + 1
        POSERS[clip](k, n)
        for b in ("hips", "spine", "neck", "head"):
            rig.pose.bones[b].keyframe_insert("location", frame=f)
            rig.pose.bones[b].keyframe_insert("rotation_euler", frame=f)
        rc = _obj("RifleCtrl")
        rc.keyframe_insert("location", frame=f)
        rc.keyframe_insert("rotation_euler", frame=f)
        for s in ("L", "R"):
            _obj("FootIK." + s).keyframe_insert("location", frame=f)
        _obj("MuzzleFlash").keyframe_insert("scale", frame=f)
    for name in ANIMATED:
        ob = _obj(name)
        act = ob.animation_data.action
        act.name = _act_name(clip, name)
        act.use_fake_user = True
        _linear(act)
        ob.animation_data.action = None


def _act_name(clip, obname):
    return "Android%s" % clip if obname == "AndroidRig" else "Android%s[%s]" % (clip, obname)


def use_clip(clip):
    """Assigns a clip's actions and sets the scene's frame range to it."""
    for name in ANIMATED:
        ob = _obj(name)
        ob.animation_data.action = bpy.data.actions.get(_act_name(clip, name))
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, CLIPS[clip]
    sc.render.fps = FPS
    sc.frame_set(1)


def setup_all():
    make_flash()
    _obj("RifleCtrl").rotation_mode = "XYZ"
    for clip in CLIPS:
        bake(clip)
    use_clip("Idle")
    # Timeline markers name the clips' frame ranges when they're laid end to end
    # in the NLA - here simply the loop length.
    sc = bpy.context.scene
    sc.timeline_markers.clear()
    sc.timeline_markers.new("Idle loop (2 s at 25 fps)", frame=1)


# ---------------------------------------------------------------- sprites

def facing_angle(d):
    """AndroidRoot's Z rotation for facing screen direction d (e = right,
    s = toward the camera): the model faces -Y at 0."""
    return math.pi / 2 - DIRS.index(d) * math.pi / 4


def render_all(out_dir, clips=tuple(CLIPS), dirs=DIRS):
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    root = _obj("AndroidRoot")
    files = []
    for clip in clips:
        use_clip(clip)
        for k in range(CLIPS[clip]):
            sc.frame_set(k + 1)
            for d in dirs:
                root.rotation_euler = (0, 0, facing_angle(d))
                bpy.context.view_layer.update()
                sc.render.filepath = os.path.join(out_dir, "%s%d_%s.png" % (clip.lower(), k + 1, d))
                bpy.ops.render.render(write_still=True)
                files.append(sc.render.filepath)
    root.rotation_euler = (0, 0, 0)
    from bpy_extras.object_utils import world_to_camera_view
    uv = world_to_camera_view(sc, sc.camera, root.matrix_world.translation)
    W = sc.render.resolution_x * sc.render.resolution_percentage // 100
    H = sc.render.resolution_y * sc.render.resolution_percentage // 100
    with open(os.path.join(out_dir, "meta.json"), "w") as fh:
        json.dump({"ground": [round(uv.x * W, 2), round((1.0 - uv.y) * H, 2)], "size": [W, H], "fps": FPS}, fh)
    use_clip("Idle")
    return files
