"""Imports source/dinosaur.glb (a spinosaurus on all fours, one textured mesh, no skeleton), gives it a
skeleton and two animations, and saves dinosaur.blend.

  blender -b --factory-startup --python external/blender/dinosaur/rig_dino.py [-- noshots]
Also renders stills of the animations into renders/ (walk.png, attack.png), unless "noshots".

The model as imported: 1 m long, facing -Y, feet on z = 0, its left at +X. It is kept at that size.

Skeleton (armature DINO_Rig, 31 bones; ".L" is the animal's left, +X):
  root > hips > spine > chest > neck.01 > neck.02 > head > jaw
         hips > tail.01 .. tail.06
         chest > upper_arm.L/R > forearm > hand            (the front legs)
         hips > thigh.L/R > shin > foot > toes             (the hind legs)
Skinning: Blender's automatic weights on the welded mesh, then repairs (bind()): points it left
out copy their neighbours, and the loose pieces inside the mouth (teeth, tongue) each follow the
head or the jaw as a whole.

Animations (actions on DINO_Rig, 25 frames a second, a key on every frame):
  DINO_Walk    frames 1-32, loops (frame 33 = frame 1): a four-legged walk in place - left hind,
               left front, right hind, right front, a quarter of the cycle apart; the ground
               passes under it at WALK_SPEED m/s
  DINO_Attack  frames 1-44: rears on its hind legs, cocks both front legs, slashes with the right
               then the left, drops back onto all fours (ends as it starts)
Poses are worked out, not hand-keyed: each foot and hand is given a place to be, and its leg is
solved to reach it (two-bone IK about the limb's own bend plane), then baked to plain rotations."""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
V = Vector
RIG, FPS = "DINO_Rig", 25
STRIDE, DUTY, WALK_FRAMES = 0.085, 0.66, 32
WALK_SPEED = STRIDE / (DUTY * WALK_FRAMES / FPS)


def Rx(d):
    return Matrix.Rotation(math.radians(d), 3, "X")        # + : nose down


def Ry(d):
    return Matrix.Rotation(math.radians(d), 3, "Y")        # roll


def Rz(d):
    return Matrix.Rotation(math.radians(d), 3, "Z")        # + : nose to its left


def R3(pitch_up=0.0, yaw=0.0, roll=0.0):
    return Rz(yaw) @ Rx(-pitch_up) @ Ry(roll)


# ---------------------------------------------------------------- the skeleton

SPINE = [("hips", (0, 0.02, 0.185), (0, -0.06, 0.180), "root"), ("spine", (0, -0.06, 0.180), (0, -0.14, 0.178), "hips"),
         ("chest", (0, -0.14, 0.178), (0, -0.225, 0.185), "spine"), ("neck.01", (0, -0.225, 0.185), (0, -0.28, 0.205), "chest"),
         ("neck.02", (0, -0.28, 0.205), (0, -0.335, 0.222), "neck.01"), ("head", (0, -0.335, 0.222), (0, -0.50, 0.240), "neck.02"),
         ("jaw", (0, -0.35, 0.205), (0, -0.455, 0.135), "head")]
TAIL = [(0, 0.02, 0.185), (0, 0.11, 0.190), (0, 0.20, 0.200), (0, 0.29, 0.213), (0, 0.38, 0.228), (0, 0.47, 0.240), (0, 0.455, 0.190)]
LEG = [("thigh", (0.055, -0.03, 0.185)), ("shin", (0.07, -0.04, 0.125)), ("foot", (0.08, 0.055, 0.075)), ("toes", (0.085, 0.045, 0.020)),
       (None, (0.11, -0.015, 0.008))]
ARM = [("upper_arm", (0.05, -0.215, 0.165)), ("forearm", (0.075, -0.165, 0.118)), ("hand", (0.075, -0.235, 0.060)), (None, (0.08, -0.228, 0.012))]


def bone_table():
    B = {"root": (V((0, 0, 0)), V((0, 0.1, 0)), None)}
    for name, h, t, parent in SPINE:
        B[name] = (V(h), V(t), parent)
    for i in range(6):
        B["tail.%02d" % (i + 1)] = (V(TAIL[i]), V(TAIL[i + 1]), "hips" if i == 0 else "tail.%02d" % i)
    for sgn, s in ((1, "L"), (-1, "R")):
        for chain, top in ((LEG, "hips"), (ARM, "chest")):
            parent = top
            for (name, h), (_, t) in zip(chain, chain[1:]):
                B["%s.%s" % (name, s)] = (V((sgn * h[0], h[1], h[2])), V((sgn * t[0], t[1], t[2])), parent)
                parent = "%s.%s" % (name, s)
    return B


BONES, ORDER = {}, []


def build_rig():
    table = bone_table()
    ad = bpy.data.armatures.new(RIG)
    arm = bpy.data.objects.new(RIG, ad)
    bpy.context.scene.collection.objects.link(arm)
    arm.show_in_front = True
    ad.display_type = "STICK"
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in table.items():
        eb = ad.edit_bones.new(name)
        eb.head, eb.tail = h, t
    for name, (h, t, parent) in table.items():
        if parent:
            ad.edit_bones[name].parent = ad.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    ad.bones["root"].use_deform = False
    for name, (h, t, parent) in table.items():
        b = ad.bones[name]
        BONES[name] = dict(head=b.head_local.copy(), tail=b.tail_local.copy(), parent=parent, M=b.matrix_local.to_3x3().normalized())
        ORDER.append(name)
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


# ---------------------------------------------------------------- the mesh and its weights

def import_model():
    bpy.ops.import_scene.gltf(filepath=os.path.join(HERE, "source", "dinosaur.glb"))
    ob = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    world = ob.matrix_world.copy()
    for o in list(bpy.context.scene.objects):
        if o is not ob:
            bpy.data.objects.remove(o, do_unlink=True)
    ob.parent = None
    ob.matrix_world = world
    ob.name = ob.data.name = "Dinosaur"
    bm = bmesh.new()                       # (the file splits the surface along its texture seams: weld it)
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def islands(me):
    """The mesh's connected pieces: a piece number for every point."""
    n = len(me.vertices)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    return np.array([find(i) for i in range(n)])


RADIUS = {"hips": 0.075, "spine": 0.075, "chest": 0.07, "neck.01": 0.05, "neck.02": 0.045, "head": 0.04, "jaw": 0.035,
          "tail.01": 0.06, "tail.02": 0.045, "tail.03": 0.035, "tail.04": 0.028, "tail.05": 0.022, "tail.06": 0.02,
          "thigh": 0.042, "shin": 0.028, "foot": 0.022, "toes": 0.02, "upper_arm": 0.032, "forearm": 0.024, "hand": 0.02}


def bind(ob, arm):
    """Skins the mesh. (Blender's automatic weights give up on this mesh - it is many loose shells -
    so:) every point goes to the bone it is nearest to, measured in that bone's own thickness
    (RADIUS), then the weights are blurred along the surface so the joints bend softly."""
    me = ob.data
    n = len(me.vertices)
    names = [b for b in ORDER if b != "root"]
    co = np.array([tuple(v.co) for v in me.vertices])
    D = np.empty((n, len(names)))
    for j, name in enumerate(names):
        h, t = np.array(BONES[name]["head"]), np.array(BONES[name]["tail"])
        ab = t - h
        f = np.clip(((co - h) @ ab) / (ab @ ab), 0.0, 1.0)
        D[:, j] = np.linalg.norm(co - (h + f[:, None] * ab), axis=1) / RADIUS[name.split(".")[0] if name[-2:] in (".L", ".R") else name]
    W = np.zeros((n, len(names)))
    W[np.arange(n), D.argmin(axis=1)] = 1.0
    e = np.array([tuple(ed.vertices) for ed in me.edges])
    deg = np.zeros(n)
    np.add.at(deg, e[:, 0], 1.0)
    np.add.at(deg, e[:, 1], 1.0)
    for _ in range(6):
        acc = np.zeros_like(W)
        np.add.at(acc, e[:, 0], W[e[:, 1]])
        np.add.at(acc, e[:, 1], W[e[:, 0]])
        W = 0.5 * W + 0.5 * acc / np.maximum(deg, 1.0)[:, None]
    for name in names:
        ob.vertex_groups.new(name=name)
    ob.parent = arm
    ob.modifiers.new("Armature", "ARMATURE").object = arm
    bad = np.zeros(n, bool)
    # loose pieces inside the mouth (teeth, tongue): each follows the head or the jaw as a whole
    isl = islands(me)
    ids, counts = np.unique(isl, return_counts=True)
    main = ids[np.argmax(counts)]
    hj = [names.index("head"), names.index("jaw")]
    moved = 0
    for i in ids:
        if i == main:
            continue
        k = isl == i
        c = co[k].mean(axis=0)
        if c[1] < -0.33:
            mouth_z = 0.205 + (c[1] + 0.35) * (0.185 - 0.205) / (-0.47 + 0.35)
            W[k] = 0.0
            W[np.nonzero(k)[0], hj[1 if c[2] < mouth_z else 0]] = 1.0
        else:                                # any other loose piece: wholly on its strongest bone
            j = W[k].sum(axis=0).argmax()
            W[k] = 0.0
            W[np.nonzero(k)[0], j] = 1.0
        moved += 1
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    for gi, g in enumerate(ob.vertex_groups):
        g.remove(list(range(n)))
        idx = np.nonzero(W[:, gi] > 0.003)[0]
        for j in idx:
            g.add([int(j)], float(W[j, gi]), "REPLACE")
    print("bound: %d points, %d left out by the automatic weights, %d loose pieces set on one bone" % (n, int(bad.sum()), moved))


# ---------------------------------------------------------------- poses

def rest(name):
    return BONES[name]["head"]


def ik(root, target, l1, l2, bend):
    """Two-bone IK: the middle joint, given the root joint, the target for the end joint, the two
    lengths and the direction the middle joint bends toward."""
    d = target - root
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.999)
    dn = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    e = bend - dn * bend.dot(dn)
    e = e.normalized() if e.length > 1e-6 else V((0, 0, 1))
    return root + dn * a + e * h, root + dn * dist


def frame(direction, axis):
    x = direction.normalized()
    z = (axis - x * axis.dot(x)).normalized()
    return Matrix((x, z.cross(x), z)).transposed()


def limb_solve(Rw, s, upper, lower, root, target, body):
    """Sets the world rotations of a limb's two long bones so its end joint reaches the target."""
    u, lo = BONES[upper + s], BONES[lower + s]
    j0, j1, j2 = u["head"], lo["head"], lo["tail"]
    bend_rest = (j1 - j0) - (j2 - j0).normalized() * (j1 - j0).dot((j2 - j0).normalized())
    mid, end = ik(root, target, (j1 - j0).length, (j2 - j1).length, body @ bend_rest)
    ax_rest, ax_new = (j2 - j0).cross(bend_rest), (end - root).cross(mid - root)
    Rw[upper + s] = frame(mid - root, ax_new) @ frame(j1 - j0, ax_rest).transposed()
    Rw[lower + s] = frame(end - mid, ax_new) @ frame(j2 - j1, ax_rest).transposed()


def neutral():
    """A pose: everything at rest. hips: loc (offset, m) and rot (pitch up, yaw, roll, degrees);
    spine, chest, neck, head: (pitch up, yaw, roll) on their parent; jaw: degrees more open; tail:
    (pitch up, yaw) of each of its six bones; feet L, R: where the ball of the foot is (offset from
    rest), the foot's pitch (+ = heel up) and the toes' curl; hands L, R: where the wrist is (offset
    from rest, in the chest's frame when "chest", else in the world) and the hand's pitch."""
    return dict(hips=dict(loc=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)), spine=(0.0, 0.0, 0.0), chest=(0.0, 0.0, 0.0), neck=(0.0, 0.0, 0.0),
                head=(0.0, 0.0, 0.0), jaw=0.0, tail=[(0.0, 0.0)] * 6,
                feet=dict(L=dict(at=(0.0, 0.0, 0.0), pitch=0.0, toes=0.0), R=dict(at=(0.0, 0.0, 0.0), pitch=0.0, toes=0.0)),
                hands=dict(L=dict(at=(0.0, 0.0, 0.0), pitch=0.0, space="world"), R=dict(at=(0.0, 0.0, 0.0), pitch=0.0, space="world")))


def solve(sp):
    """A pose -> each bone's world rotation (from rest) and the hips' offset."""
    Rw = {"root": Matrix.Identity(3)}
    off = V(sp["hips"]["loc"])
    Rw["hips"] = R3(*sp["hips"]["rot"])
    Rw["spine"] = Rw["hips"] @ R3(*sp["spine"])
    Rw["chest"] = Rw["spine"] @ R3(*sp["chest"])
    Rw["neck.01"] = Rw["chest"] @ R3(*sp["neck"])
    Rw["neck.02"] = Rw["neck.01"] @ R3(*sp["neck"])
    Rw["head"] = Rw["neck.02"] @ R3(*sp["head"])
    Rw["jaw"] = Rw["head"] @ Rx(sp["jaw"])
    R = Rw["hips"]
    for i, (p, y) in enumerate(sp["tail"]):
        R = R @ R3(p, y)
        Rw["tail.%02d" % (i + 1)] = R
    p_hips = rest("hips") + off
    p_spine = p_hips + Rw["hips"] @ (rest("spine") - rest("hips"))
    p_chest = p_spine + Rw["spine"] @ (rest("chest") - rest("spine"))
    for s in "LR":
        ft = sp["feet"][s]
        foot, toes = BONES["foot." + s], BONES["toes." + s]
        Rf = Rx(ft["pitch"])
        ankle = foot["tail"] + V(ft["at"]) - Rf @ (foot["tail"] - foot["head"])
        limb_solve(Rw, "." + s, "thigh", "shin", p_hips + Rw["hips"] @ (rest("thigh." + s) - rest("hips")), ankle, Rw["hips"])
        Rw["foot." + s], Rw["toes." + s] = Rf, Rx(ft["toes"])
        hd = sp["hands"][s]
        shoulder = p_chest + Rw["chest"] @ (rest("upper_arm." + s) - rest("chest"))
        rel = rest("hand." + s) - rest("upper_arm." + s)
        wrist = shoulder + Rw["chest"] @ (rel + V(hd["at"])) if hd["space"] == "chest" else rest("hand." + s) + V(hd["at"])
        limb_solve(Rw, "." + s, "upper_arm", "forearm", shoulder, wrist, Rw["chest"])
        Rw["hand." + s] = (Rw["chest"] if hd["space"] == "chest" else Matrix.Identity(3)) @ Rx(hd["pitch"])
    return Rw, off


def key_pose(arm, f, sp, last):
    Rw, off = solve(sp)
    for name in ORDER:
        b = BONES[name]
        Rp = Rw[b["parent"]] if b["parent"] else Matrix.Identity(3)
        q = (b["M"].transposed() @ Rp.transposed() @ Rw[name] @ b["M"]).to_quaternion()
        if name in last and last[name].dot(q) < 0:
            q.negate()
        last[name] = q
        pb = arm.pose.bones[name]
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=f)
        if name == "hips":
            pb.location = b["M"].transposed() @ off
            pb.keyframe_insert("location", frame=f)


def mixp(a, b, t):
    if isinstance(a, dict):
        return {k: mixp(a[k], b[k], t) for k in a}
    if isinstance(a, (tuple, list)):
        return type(a)(mixp(x, y, t) for x, y in zip(a, b))
    if isinstance(a, str):
        return b
    return a + (b - a) * t


def sm(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def new_action(arm, name):
    arm.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    try:
        arm.animation_data.action_slot = act.slots.new(id_type="OBJECT", name=RIG)
    except Exception:
        pass
    return act


# ---------------------------------------------------------------- the animations

def step(ph, lift, y0):
    """A foot through the cycle at phase ph: planted and carried back for DUTY of it, then lifted and
    swung forward. Returns (its offset along y from the middle of its step, its height, how far
    through the swing it is or -1)."""
    ph %= 1.0
    if ph < DUTY:
        return y0 - STRIDE / 2 + STRIDE * ph / DUTY, 0.0, -1.0
    t = (ph - DUTY) / (1 - DUTY)
    e = t * t * (3 - 2 * t)
    return y0 + STRIDE / 2 - STRIDE * e, lift * math.sin(math.pi * t) ** 1.3, t


def walk_pose(p):
    sp = neutral()
    w = 2 * math.pi * p
    sp["hips"] = dict(loc=(0.006 * math.sin(w + 0.6), 0.0, -0.006 - 0.004 * math.cos(2 * w)), rot=(0.0, 5.0 * math.cos(w), 2.0 * math.sin(w)))
    sp["spine"] = (0.0, -3.5 * math.cos(w), 0.0)
    sp["chest"] = (0.0, -6.0 * math.cos(w - 0.5), -2.0 * math.sin(w))
    sp["neck"] = (0.8 * math.cos(2 * w), 2.0 * math.cos(w - 0.5), 0.0)
    sp["head"] = (-1.0 * math.cos(2 * w - 0.6), 2.5 * math.cos(w - 0.5), 0.0)
    sp["jaw"] = -14.0
    sp["tail"] = [(0.3 * math.cos(2 * w - 0.5 * i), (3.5 + 1.2 * i) * math.sin(w - 0.7 - 0.55 * i)) for i in range(6)]
    for s, ph in (("L", 0.0), ("R", 0.5)):
        y, z, t = step(p - ph, 0.035, -0.015)
        roll = 28.0 * sm(0.80, 1.0, (p - ph) % 1.0 / DUTY) if t < 0 else 28.0 * (1 - sm(0.0, 0.5, t)) - 14.0 * math.sin(math.pi * sm(0.5, 1.0, t))
        sp["feet"][s] = dict(at=(0.0, y, z), pitch=-roll, toes=18.0 * math.sin(math.pi * t) if t >= 0 else 0.0)
    for s, ph in (("L", 0.25), ("R", 0.75)):
        y, z, t = step(p - ph, 0.035, 0.0)
        pitch = -22.0 * sm(0.80, 1.0, (p - ph) % 1.0 / DUTY) if t < 0 else -22.0 * (1 - sm(0.0, 0.4, t)) + 16.0 * math.sin(math.pi * sm(0.4, 1.0, t))
        sp["hands"][s] = dict(at=(0.0, y, z - 0.008), pitch=pitch, space="world")
    return sp


def make_walk(arm):
    new_action(arm, "DINO_Walk")
    last = {}
    for f in range(1, WALK_FRAMES + 2):
        key_pose(arm, f, walk_pose((f - 1) / WALK_FRAMES), last)


def make_attack(arm):
    new_action(arm, "DINO_Attack")

    def pose(lift, lunge, pitch, chest, neck, head, jaw, L, R, yaw=0.0, tail=0.0):
        sp = neutral()
        sp["hips"] = dict(loc=(0.0, -lunge, lift), rot=(pitch, yaw * 0.4, 0.0))
        sp["spine"], sp["chest"] = (chest * 0.5, yaw * 0.6, 0.0), (chest * 0.5, yaw, 0.0)
        sp["neck"], sp["head"], sp["jaw"] = (neck, -yaw * 0.5, 0.0), (head, -yaw * 0.4, 0.0), jaw
        sp["tail"] = [((-pitch * 0.5 if i < 2 else 0.0) + tail * (0.5 + 0.3 * i), -yaw * 0.5) for i in range(6)]      # (the tail stays near level as the body rears)
        sp["hands"] = dict(L=dict(at=L[0], pitch=L[1], space="chest"), R=dict(at=R[0], pitch=R[1], space="chest"))
        return sp
    down = ((0.0, 0.0, 0.0), 0.0)
    cocked = ((0.03, -0.03, 0.09), -50.0)             # the hand drawn up beside the chest, claws forward
    high = ((0.03, -0.07, 0.11), -65.0)               # the hand raised ahead of the shoulder
    struck = ((-0.035, -0.115, 0.035), 30.0)          # the hand thrown forward and down, across the middle
    keys = [
        (1, pose(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -14.0, down, down), "smooth"),
        (6, pose(-0.012, 0.01, -3.0, -4.0, -4.0, 4.0, -18.0, down, down), "smooth"),                              # a crouch before it rears
        (13, pose(0.012, -0.012, 24.0, 10.0, -8.0, -12.0, 14.0, high, cocked, yaw=-8.0, tail=1.5), "out"),        # reared, both hands up
        (17, pose(0.004, 0.022, 15.0, 2.0, -3.0, -4.0, 20.0, cocked, struck, yaw=14.0, tail=-1.0), "in"),         # the right hand slashes
        (20, pose(0.006, 0.016, 17.0, 4.0, -4.0, -6.0, 12.0, high, struck, yaw=8.0), "out"),
        (24, pose(0.002, 0.03, 13.0, 0.0, -2.0, -2.0, 22.0, struck, cocked, yaw=-14.0, tail=-1.0), "in"),         # the left hand slashes
        (28, pose(0.004, 0.022, 14.0, 2.0, -3.0, -4.0, 10.0, struck, cocked, yaw=-9.0), "out"),
        (36, pose(-0.008, 0.004, -2.0, -3.0, -3.0, 3.0, -8.0, down, down, tail=1.0), "in"),                       # lands, sinking on its legs
        (44, pose(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -14.0, down, down), "smooth"),
    ]
    ease = {"smooth": lambda t: t * t * (3 - 2 * t), "in": lambda t: t ** 2.2, "out": lambda t: 1 - (1 - t) ** 2.2}
    last = {}
    for (f0, a, _), (f1, b, e) in zip(keys, keys[1:]):
        for f in range(f0, f1):
            key_pose(arm, f, mixp(a, b, ease[e]((f - f0) / (f1 - f0))), last)
    key_pose(arm, keys[-1][0], keys[-1][1], last)


ACTIONS = {"DINO_Walk": (1, WALK_FRAMES), "DINO_Attack": (1, 44)}


def use_action(arm, name):
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    try:
        arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = ACTIONS[name]
    sc.frame_set(sc.frame_start)


# ---------------------------------------------------------------- stage, stills

def stage():
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("DINO_World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.57, 0.6, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.world = w
    ld = bpy.data.lights.new("DINO_Sun", "SUN")
    ld.energy = 3.0
    sun = bpy.data.objects.new("DINO_Sun", ld)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-40))
    sc.collection.objects.link(sun)
    cd = bpy.data.cameras.new("DINO_Cam")
    cd.type, cd.ortho_scale = "ORTHO", 1.2
    cam = bpy.data.objects.new("DINO_Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 600, 340
    return cam


def stills(arm, cam):
    sc = bpy.context.scene
    views = {"side": V((-1.0, -0.25, 0.12)), "front": V((-0.55, -1.0, 0.35))}
    shots = {"DINO_Walk": ("side", range(1, 33, 4)), "DINO_Attack": ("front", (1, 6, 10, 13, 15, 17, 20, 22, 24, 28, 36, 44))}
    arm.hide_render = True
    for name, (view, frames) in shots.items():
        d = views[view].normalized()
        cam.location = V((0, -0.02, 0.17)) + d * 3
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        use_action(arm, name)
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(HERE, "renders", "frames", "%s_%02d.png" % (name, f))
            bpy.ops.render.render(write_still=True)
    use_action(arm, "DINO_Walk")


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ob = import_model()
    arm = build_rig()
    bind(ob, arm)
    make_walk(arm)
    make_attack(arm)
    arm["animations"] = "DINO_Walk 1-32 (loops, %.2f m/s), DINO_Attack 1-44; %d frames a second" % (WALK_SPEED, FPS)
    cam = stage()
    use_action(arm, "DINO_Walk")
    return arm, cam


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    arm, cam = build()
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "dinosaur.blend"))
    if "noshots" not in args:
        stills(arm, cam)
