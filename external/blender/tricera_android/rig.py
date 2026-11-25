"""The triceratops android's skeleton and its animations (run by build_model.py after the parts are
built; the parts must exist under their build names).

Skeleton (armature TRI_Rig, a child of TRI_Root; the android faces -Y, its left is +X, ".L" / ".R"):
  root > hips > chest > neck > head > jaw, earring.L/R
                chest > shoulder.L/R > upper_arm > forearm > hand > fingers, thumb
                chest > cape_C.01-03 (middle of the back), cape_L.01-03, cape_R.01-03 (the wings)
         hips > thigh.L/R > shin > foot > toes
         hips > kilt.L/R (the front cloth's halves), tasset.L/R (hip plates), tassel.L/R
Every armour part is rigid: it is parented to one bone (attach()). Only the cape and the front cloth
bend: they are skinned (skin_cloth()) with weights worked out from where a point is on the cloth.

Animations (actions on TRI_Rig, 25 frames a second, a key on every frame):
  TRI_Walk    frames 1-32, loops (frame 33 = frame 1); in place - at this stride the ground passes
              under it at WALK_SPEED m/s
  TRI_Punch   frames 1-30: guard, wind up, a straight right, back to guard (ends as it starts)
  TRI_Die     frames 1-48: recoils, its knees give way, it kneels, falls on its face
Poses are written as a few numbers per body part (spec()) and solved to bone rotations (solve()):
the legs by two-bone IK in the plane they swing in, so planted feet stay planted; arms by the
direction each segment points in."""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

import kit
from kit import K, Q

RIG = "TRI_Rig"
FPS = 25
STRIDE = 0.50                 # how far a planted foot travels back under the body in a step (m)
STANCE = 0.56                 # the part of the walk cycle a foot is planted
WALK_FRAMES = 32
WALK_SPEED = STRIDE / (STANCE * WALK_FRAMES / FPS)


def X3(d):
    return Matrix.Rotation(math.radians(d), 3, "X")


def Y3(d):
    return Matrix.Rotation(math.radians(d), 3, "Y")


def Z3(d):
    return Matrix.Rotation(math.radians(d), 3, "Z")


def R3(pitch, yaw=0.0, roll=0.0):
    """Pitch forward (+), turn (+ = toward its left), lean (+ = its left side down)."""
    return Z3(yaw) @ X3(pitch) @ Y3(roll)


# ---------------------------------------------------------------- bones

def bone_table():
    """name -> (head, tail, parent)."""
    B = {
        "root": (Vector((0, 0, 0)), Vector((0, 0.25, 0)), None),
        "hips": (Q(0, 266, 430), Q(0, 266, 398), "root"),
        "chest": (Q(0, 274, 402), Q(0, 285, 270), "hips"),
        "neck": (Q(0, 290, 256), Q(0, 280, 210), "chest"),
        "head": (Q(0, 280, 210), Q(0, 275, 130), "neck"),
        "jaw": (Q(0, 262, 214), Q(0, 190, 232), "head"),
        "cape_C.01": (Q(0, 344, 290), Q(0, 358, 430), "chest"),
        "cape_C.02": (Q(0, 358, 430), Q(0, 373, 580), "cape_C.01"),
        "cape_C.03": (Q(0, 373, 580), Q(0, 388, 738), "cape_C.02"),
    }
    for sgn, s in ((1, "L"), (-1, "R")):
        def P(dx, sp, row, sgn=sgn):
            return Q(sgn * dx, sp, row)
        B.update({
            "earring." + s: (P(54, 298, 207), P(54, 298, 243), "head"),
            "shoulder." + s: (P(58, 290, 268), P(104, 290, 280), "chest"),
            "upper_arm." + s: (P(104, 290, 284), P(229, 290, 282), "shoulder." + s),
            "forearm." + s: (P(229, 290, 282), P(394, 290, 283), "upper_arm." + s),
            "hand." + s: (P(394, 290, 283), P(438, 290, 284), "forearm." + s),
            "fingers." + s: (P(438, 290, 283), P(486, 290, 297), "hand." + s),
            "thumb." + s: (P(402, 266, 297), P(430, 257, 330), "hand." + s),
            "thigh." + s: (P(70, 262, 456), P(82, 290, 669), "hips"),
            "shin." + s: (P(82, 290, 669), P(92, 285, 860), "thigh." + s),
            "foot." + s: (P(92, 285, 860), P(100, 228, 934), "shin." + s),
            "toes." + s: (P(100, 228, 934), P(112, 165, 975), "foot." + s),
            "kilt." + s: (P(35, 210, 428), P(40, 190, 640), "hips"),
            "tasset." + s: (P(84, 263, 440), P(100, 264, 548), "hips"),
            "tassel." + s: (P(52, 205, 428), P(52, 208, 577), "hips"),
            "cape_%s.01" % s: (P(160, 356, 300), P(190, 378, 420), "chest"),
            "cape_%s.02" % s: (P(190, 378, 420), P(228, 408, 540), "cape_%s.01" % s),
            "cape_%s.03" % s: (P(228, 408, 540), P(272, 441, 652), "cape_%s.02" % s),
        })
    return B


BONES = {}        # name -> dict(head, tail, parent, M: its rest orientation (3x3, armature axes))
ORDER = []        # bone names, parents first


def build_rig():
    table = bone_table()
    ad = bpy.data.armatures.new(RIG)
    arm = bpy.data.objects.new(RIG, ad)
    kit.coll().objects.link(arm)
    arm.parent = bpy.data.objects.get("TRI_Root")
    arm.show_in_front = True
    ad.display_type = "STICK"
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in table.items():
        eb = ad.edit_bones.new(name)
        eb.head, eb.tail = head, tail
    for name, (head, tail, parent) in table.items():
        if parent:
            ad.edit_bones[name].parent = ad.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    BONES.clear()
    ORDER.clear()
    for name, (head, tail, parent) in table.items():       # (the table lists parents first)
        b = ad.bones[name]
        BONES[name] = dict(head=b.head_local.copy(), tail=b.tail_local.copy(), parent=parent, M=b.matrix_local.to_3x3().normalized())
        ORDER.append(name)
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


# ---------------------------------------------------------------- parts on bones

RULES = [    # (name starts with, bone); the first that fits; a bone with a side takes the part's .L / .R
    ("Head_Jaw", "jaw"), ("Head_EarLink", "earring."), ("Head_EarBead", "earring."), ("Head_EarDrop", "earring."),
    ("Head_", "head"), ("Neck", "neck"),
    ("Torso_Pelvis", "hips"), ("Belt", "hips"), ("Bull_", "hips"), ("Torso_", "chest"), ("Sun_", "chest"), ("Cape_", "chest"),
    ("Shoulder_", "shoulder."),
    ("Arm_Shoulder", "upper_arm."), ("Arm_Upper", "upper_arm."), ("Arm_Elbow", "upper_arm."),
    ("Arm_Fore", "forearm."), ("Arm_Bracer", "forearm."), ("Arm_Wrist", "forearm."),
    ("Arm_Palm", "hand."), ("Arm_Thumb", "thumb."), ("Arm_Finger", "fingers."), ("Arm_Claw", "fingers."),
    ("Leg_Hip", "thigh."), ("Leg_Thigh", "thigh."), ("Leg_Knee", "thigh."),
    ("Leg_Shin", "shin."), ("Leg_Calf", "shin."), ("Leg_Cuff", "shin."), ("Leg_Ankle", "shin."),
    ("Foot_Instep", "foot."), ("Foot_Heel", "foot."), ("Foot_Sole", "foot."), ("Foot_Toe", "toes."), ("Foot_Claw", "toes."),
    ("Kilt_Tasset", "tasset."), ("Kilt_Cord", "tassel."), ("Kilt_Tassel", "tassel."),
]
SKINNED = ("Cape", "Kilt_Cloth")


def bone_for(ob):
    name = ob.name
    side = "L" if ".L" in name else "R" if ".R" in name else ""
    if name.startswith("Arm_Line") or name.startswith("Leg_Line") or name.startswith("Leg_SideLine"):
        # a panel line: the bone of the part it is drawn on, by where it is
        c = sum((v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
        if name.startswith("Arm_"):
            x = abs(c.x) / K
            return ("upper_arm." if x < 229 else "forearm." if x < 396 else "hand.") + side
        row = kit.GY - c.z / K
        return ("thigh." if row < 700 else "shin." if row < 868 else "foot.") + side
    for prefix, bone in RULES:
        if name.startswith(prefix):
            return bone + side if bone.endswith(".") else bone
    return None


def attach(arm):
    """Parents every rigid part to its bone (the part stays where it is)."""
    left = []
    for ob in list(kit.coll().objects):
        if ob.type != "MESH" or ob.name in SKINNED:
            continue
        bone = bone_for(ob)
        if bone is None or bone not in BONES:
            left.append(ob.name)
            continue
        b = BONES[bone]
        ob.parent = arm
        ob.parent_type = "BONE"
        ob.parent_bone = bone
        rest = arm.data.bones[bone].matrix_local @ Matrix.Translation((0, (b["tail"] - b["head"]).length, 0))
        ob.matrix_parent_inverse = rest.inverted()
    if left:
        print("parts without a bone:", left)


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def skin_cloth(arm):
    """Weights of the cape and the front cloth, from each point's place on the cloth (its texture
    coordinates: u across, 1 - v down)."""
    def uv_of(me):
        uv = [None] * len(me.vertices)
        data = me.uv_layers[0].data
        for lp in me.loops:
            uv[lp.vertex_index] = data[lp.index].uv
        return uv

    def bind(ob, weights):
        ink = [(m.thickness, m.offset, m.use_flip_normals, m.use_rim, m.material_offset) for m in ob.modifiers if m.type == "SOLIDIFY"]
        ob.modifiers.clear()
        groups = {}
        for i, w in enumerate(weights):
            tot = sum(w.values())
            for name, x in w.items():
                if x > 1e-4:
                    g = groups.get(name) or groups.setdefault(name, ob.vertex_groups.new(name=name))
                    g.add([i], x / tot, "REPLACE")
        md = ob.modifiers.new("Armature", "ARMATURE")
        md.object = arm
        for th, off, flip, rim, mo in ink:                      # (the outline goes on after the bending)
            s = ob.modifiers.new("Ink", "SOLIDIFY")
            s.thickness, s.offset, s.use_flip_normals, s.use_rim, s.material_offset = th, off, flip, rim, mo
        ob.parent = arm
        ob.parent_type = "OBJECT"

    cape = bpy.data.objects["Cape"]
    w = []
    for uv in uv_of(cape.data):
        u, v = uv[0], 1.0 - uv[1]
        i = u * 10.0                                     # the cape's lines: 0 A, 1 M, 2 B (right wing) ... 5 C ... 8 B, 10 A
        side = {"R": max(0.0, 1 - abs(i - 1.5) / 3.6), "C": max(0.0, 1 - abs(i - 5.0) / 3.6), "L": max(0.0, 1 - abs(i - 8.5) / 3.6)}
        down = {0: 1 - _smooth(0.06, 0.34, v), 1: _smooth(0.06, 0.34, v) * (1 - _smooth(0.34, 0.64, v)),
                2: _smooth(0.34, 0.64, v) * (1 - _smooth(0.64, 0.94, v)), 3: _smooth(0.64, 0.94, v)}
        d = {"chest": down[0]}
        for s, ws in side.items():
            for k in (1, 2, 3):
                d["cape_%s.%02d" % (s, k)] = ws * down[k]
        w.append(d)
    bind(cape, w)
    cloth = bpy.data.objects["Kilt_Cloth"]
    w = []
    for uv in uv_of(cloth.data):
        u, v = uv[0], 1.0 - uv[1]
        top = 1 - _smooth(0.03, 0.22, v)
        left = _smooth(0.2, 0.8, u)
        w.append({"hips": top, "kilt.L": (1 - top) * left, "kilt.R": (1 - top) * (1 - left)})
    bind(cloth, w)


# ---------------------------------------------------------------- poses

def mir(v):
    return (-v[0], v[1], v[2])


ARM_REST = dict(up=(0.34, 0.0, -0.94), fo=(0.22, -0.30, -0.93), space="chest", curl=25.0)      # the left arm, hanging


def spec(**kw):
    """A pose. hips: loc (x, y, z offsets, m) and rot (pitch, yaw, roll, degrees); chest, neck, head:
    (pitch, yaw, roll) on their parent; jaw: degrees open; legs L, R: ("ik", ankle y, lift, foot pitch)
    - the ankle put at y (forward is negative) and `lift` above standing height - or ("fk", thigh,
    shin, foot): their pitch in the world; arms L, R: up / fo = the directions the upper arm and
    forearm point (space "chest": turning with the chest, or "world"), curl = the fingers; pads: how
    far the shoulder pads drop; cape C, L, R: each chain's three bends; sway: tassels and earrings."""
    s = dict(hips=dict(loc=(0.0, 0.0, -0.03), rot=(0.0, 0.0, 0.0)), chest=(0.0, 0.0, 0.0), neck=(0.0, 0.0, 0.0), head=(0.0, 0.0, 0.0),
             jaw=0.0, legs=dict(L=("ik", 0.052, 0.0, 0.0), R=("ik", 0.052, 0.0, 0.0)),
             arms=dict(L=dict(ARM_REST), R=dict(ARM_REST, up=mir(ARM_REST["up"]), fo=mir(ARM_REST["fo"]))),
             pads=18.0, cape=dict(C=(0.0, 0.0, 0.0), L=(0.0, 0.0, 0.0), R=(0.0, 0.0, 0.0)), sway=0.0, toes=dict(L=0.0, R=0.0))
    for k, v in kw.items():
        if isinstance(v, dict) and isinstance(s.get(k), dict):
            for kk, vv in v.items():
                s[k][kk] = dict(s[k][kk], **vv) if isinstance(vv, dict) and isinstance(s[k].get(kk), dict) else vv
        else:
            s[k] = v
    return s


def _ang(v):
    """The pitch of a direction in the plane a leg swings in (0 = straight down, + = backward)."""
    return math.degrees(math.atan2(v.y, -v.z))


def _leg_lengths(s):
    th, sh = BONES["thigh." + s], BONES["shin." + s]
    a, b = th["tail"] - th["head"], sh["tail"] - sh["head"]
    return math.hypot(a.y, a.z), math.hypot(b.y, b.z), _ang(a), _ang(b)


def leg_fk(s, sp, Rh):
    """The world pitches (thigh, shin, foot) of leg s in pose sp."""
    leg = sp["legs"][s]
    if leg[0] == "fk":
        return leg[1], leg[2], leg[3]
    L1, L2, a1, a2 = _leg_lengths(s)
    h = BONES["hips"]["head"]
    hip = h + Vector(sp["hips"]["loc"]) + Rh @ (BONES["thigh." + s]["head"] - h)
    ay, az = leg[1], BONES["foot." + s]["head"].z + leg[2]
    dy, dz = ay - hip.y, az - hip.z
    d = min(math.hypot(dy, dz), (L1 + L2) * 0.9995)
    base = math.atan2(dy, -dz)
    alpha = math.acos(min(max((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1.0), 1.0))
    th = base - alpha                                   # (the knee bends forward)
    ky, kz = hip.y + L1 * math.sin(th), hip.z - L1 * math.cos(th)
    sh = math.atan2(ay - ky, -(az - kz))
    return math.degrees(th) - a1, math.degrees(sh) - a2, leg[3]


def solve(sp):
    """A pose -> each bone's rotation in the world (relative to its rest) and the hips' offset."""
    Rw = {"root": Matrix.Identity(3)}
    Rh = R3(*sp["hips"]["rot"])
    Rw["hips"] = Rh
    Rc = Rh @ R3(*sp["chest"])
    Rw["chest"] = Rc
    Rw["neck"] = Rc @ R3(*sp["neck"])
    Rw["head"] = Rw["neck"] @ R3(*sp["head"])
    Rw["jaw"] = Rw["head"] @ X3(sp["jaw"])
    lying = _smooth(35.0, 75.0, abs(sp["hips"]["rot"][0]))
    for sgn, s in ((1, "L"), (-1, "R")):
        Rw["earring." + s] = Matrix.Identity(3).lerp(Rw["head"], lying) @ X3(sp["sway"] * 1.5)
        Rw["shoulder." + s] = Rc @ Y3(sgn * sp["pads"])
        arm = sp["arms"][s]
        Ra = Rc if arm.get("space", "chest") == "chest" else Matrix.Identity(3)
        for bone, key in (("upper_arm.", "up"), ("forearm.", "fo")):
            b = BONES[bone + s]
            rest = (b["tail"] - b["head"]).normalized()
            Rw[bone + s] = rest.rotation_difference((Ra @ Vector(arm[key])).normalized()).to_matrix()
        Rw["hand." + s] = Rw["forearm." + s]
        Rw["fingers." + s] = Rw["hand." + s] @ Y3(sgn * arm.get("curl", 0.0))
        Rw["thumb." + s] = Rw["hand." + s] @ Y3(sgn * arm.get("curl", 0.0) * 0.35)
        th, sh, ft = leg_fk(s, sp, Rh)
        Rw["thigh." + s], Rw["shin." + s], Rw["foot." + s] = X3(th), X3(sh), X3(ft)
        Rw["toes." + s] = X3(ft + sp["toes"][s])
        rel = th - sp["hips"]["rot"][0]                  # the thigh's swing on the hips (forward is negative)
        Rw["kilt." + s] = Rh @ X3(0.85 * min(rel, 0.0))
        Rw["tasset." + s] = Rh @ X3(0.6 * rel)
        Rw["tassel." + s] = Matrix.Identity(3).lerp(Rh, lying) @ X3(sp["sway"] + 0.3 * min(rel, 0.0))
    for s in "CLR":
        R = Rc
        for k, a in enumerate(sp["cape"][s]):
            R = R @ X3(a)
            Rw["cape_%s.%02d" % (s, k + 1)] = R
    return Rw, Vector(sp["hips"]["loc"])


def key_pose(arm, frame, sp, last):
    Rw, loc = solve(sp)
    for name in ORDER:
        b = BONES[name]
        Rp = Rw[b["parent"]] if b["parent"] else Matrix.Identity(3)
        R = Rw.setdefault(name, Rp)
        q = (b["M"].transposed() @ Rp.transposed() @ R @ b["M"]).to_quaternion()
        if name in last and last[name].dot(q) < 0:
            q.negate()
        last[name] = q
        pb = arm.pose.bones[name]
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if name == "hips":
            pb.location = b["M"].transposed() @ loc
            pb.keyframe_insert("location", frame=frame)


# ---------------------------------------------------------------- blending between key poses

def _mix(a, b, t):
    if isinstance(a, dict):
        return {k: _mix(a[k], b[k], t) if k in b else a[k] for k in a}
    if isinstance(a, (tuple, list)):
        return tuple(_mix(x, y, t) for x, y in zip(a, b))
    if isinstance(a, str):
        return b if t >= 0.5 else a
    return a + (b - a) * t


def _settled(sp):
    """The pose with its arms' directions said in the chest's frame and unit long (so two poses blend)."""
    sp = _mix(sp, sp, 0.0)
    Rc = R3(*sp["hips"]["rot"]) @ R3(*sp["chest"])
    for s in "LR":
        arm = dict(sp["arms"][s])
        for key in ("up", "fo"):
            v = Vector(arm[key]).normalized()
            arm[key] = tuple(Rc.transposed() @ v) if arm.get("space") == "world" else tuple(v)
        arm["space"] = "chest"
        sp["arms"][s] = arm
    return sp


def blend(a, b, t):
    """Between two key poses. A leg planted by IK in both stays solved by IK (the foot does not
    slide); otherwise its angles are blended."""
    a, b = _settled(a), _settled(b)
    for s in "LR":
        if a["legs"][s][0] != b["legs"][s][0]:
            for p in (a, b):
                if p["legs"][s][0] == "ik":
                    p["legs"][s] = ("fk",) + leg_fk(s, p, R3(*p["hips"]["rot"]))
    out = _mix(a, b, t)
    for s in "LR":
        out["legs"][s] = (a["legs"][s][0],) + tuple(out["legs"][s][1:])
    return out


EASE = {"smooth": lambda t: t * t * (3 - 2 * t), "in": lambda t: t ** 2.4, "out": lambda t: 1 - (1 - t) ** 2.4, "linear": lambda t: t}


def key_sequence(arm, keys):
    """keys: (frame, pose, how it arrives: "smooth", "in" (speeding up), "out" (slowing), "linear")."""
    last = {}
    for (f0, a, _), (f1, b, ease) in zip(keys, keys[1:]):
        for f in range(f0, f1):
            key_pose(arm, f, blend(a, b, EASE[ease]((f - f0) / (f1 - f0))), last)
    key_pose(arm, keys[-1][0], _settled(keys[-1][1]), last)


# ---------------------------------------------------------------- the animations

def new_action(arm, name):
    arm.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    try:                                          # (actions keep their curves per "slot": one for the rig)
        arm.animation_data.action_slot = act.slots.new(id_type="OBJECT", name=RIG)
    except Exception:
        pass
    return act


def walk_pose(p):
    """The walk at phase p (0..1; the left foot lands at 0, the right at 0.5)."""
    c, s = math.cos(2 * math.pi * p), math.sin(2 * math.pi * p)

    def foot(ph):
        ph %= 1.0
        front, back = 0.03 - STRIDE / 2, 0.03 + STRIDE / 2
        if ph < STANCE:                                   # planted: carried back under the body
            t = ph / STANCE
            roll = 12.0 * _smooth(0.78, 1.0, t)            # (the heel starts to lift before the toe leaves)
            return ("ik", front + (back - front) * t, 0.045 * _smooth(0.78, 1.0, t), roll)
        t = (ph - STANCE) / (1 - STANCE)                  # swinging forward
        e = t * t * (3 - 2 * t)
        lift = 0.045 * (1 - t) ** 2 + 0.13 * math.sin(math.pi * t) ** 1.2
        pitch = 12.0 + 22.0 * math.sin(math.pi * min(t / 0.6, 1.0)) if t < 0.6 else 12.0 * (1 - _smooth(0.6, 1.0, t)) - 9.0 * math.sin(math.pi * (t - 0.6) / 0.4)
        return ("ik", back + (front - back) * e, lift, pitch)

    def arm(sgn, swing):                                  # swing > 0: back
        up = X3(swing) @ Vector((sgn * 0.34, 0.0, -0.94))
        fo = X3(swing - 16.0 - 0.5 * max(-swing, 0.0)) @ Vector((sgn * 0.24, 0.0, -0.97))
        return dict(up=tuple(up), fo=tuple(fo), space="chest", curl=40.0)
    lag = math.sin(2 * math.pi * p - 0.9)
    lag2 = math.sin(4 * math.pi * p - 1.2)
    return spec(hips=dict(loc=(0.020 * s, 0.0, -0.058 - 0.014 * math.cos(4 * math.pi * p)), rot=(3.0, -6.0 * c, 2.2 * s)),
                chest=(4.0, 10.0 * c, -3.0 * s), neck=(-2.0, -2.5 * c, 0.0), head=(-3.0 + 1.5 * math.cos(4 * math.pi * p), -1.5 * c, 0.8 * s),
                legs=dict(L=foot(p), R=foot(p + 0.5)),
                arms=dict(L=arm(1, 17.0 * c), R=arm(-1, -17.0 * c)),
                cape=dict(C=(3.0 + 2.0 * lag2, 2.0 + 2.5 * lag2, 2.0 + 3.0 * lag2), L=(2.0 + 3.5 * lag, 1.5 + 3.0 * lag, 3.0 * lag),
                          R=(2.0 - 3.5 * lag, 1.5 - 3.0 * lag, -3.0 * lag)),
                sway=5.0 * lag2)


def make_walk(arm):
    new_action(arm, "TRI_Walk")
    last = {}
    for f in range(1, WALK_FRAMES + 2):
        key_pose(arm, f, walk_pose((f - 1) / WALK_FRAMES), last)


def make_punch(arm):
    new_action(arm, "TRI_Punch")
    legs = dict(L=("ik", -0.17, 0.0, 0.0), R=("ik", 0.25, 0.0, 0.0))                 # the left foot leads
    guard = spec(hips=dict(loc=(0.0, 0.01, -0.09), rot=(4.0, -18.0, 0.0)), chest=(8.0, -8.0, 0.0), neck=(-3.0, 12.0, 0.0), head=(-4.0, 13.0, 0.0),
                 legs=legs, pads=8.0,
                 arms=dict(L=dict(up=(0.30, -0.50, -0.81), fo=(-0.25, -0.55, 0.80), curl=100.0),
                           R=dict(up=(-0.36, 0.06, -0.93), fo=(0.20, -0.60, 0.77), curl=100.0)),
                 cape=dict(C=(2.0, 1.0, 0.0), L=(1.0, 0.0, 0.0), R=(1.0, 0.0, 0.0)))
    windup = spec(hips=dict(loc=(0.0, 0.06, -0.10), rot=(2.0, -27.0, 0.0)), chest=(5.0, -22.0, 0.0), neck=(-2.0, 22.0, 0.0), head=(-3.0, 24.0, 0.0),
                  legs=legs, pads=8.0, jaw=6.0,
                  arms=dict(L=dict(up=(0.25, -0.66, -0.71), fo=(-0.20, -0.62, 0.76), curl=100.0),
                            R=dict(up=(-0.46, 0.62, -0.64), fo=(0.04, -0.80, 0.60), curl=110.0)),
                  cape=dict(C=(-3.0, -3.0, -3.0), L=(-4.0, -3.0, -2.0), R=(4.0, 3.0, 2.0)))
    strike = spec(hips=dict(loc=(0.0, -0.13, -0.11), rot=(7.0, 9.0, 0.0)), chest=(12.0, 30.0, 0.0), neck=(-6.0, -18.0, 0.0), head=(-6.0, -19.0, 0.0),
                  legs=dict(L=("ik", -0.17, 0.0, 0.0), R=("ik", 0.25, 0.055, 24.0)), pads=4.0, jaw=16.0,
                  arms=dict(L=dict(up=(0.36, 0.34, -0.87), fo=(-0.15, -0.46, 0.87), curl=100.0),
                            R=dict(up=(0.10, -0.99, 0.07), fo=(0.07, -1.0, 0.03), space="world", curl=110.0)),
                  cape=dict(C=(9.0, 8.0, 8.0), L=(10.0, 8.0, 6.0), R=(5.0, 5.0, 5.0)), sway=-14.0)
    hold = _mix(strike, spec(), 0.0)
    hold["hips"] = dict(loc=(0.0, -0.12, -0.11), rot=(7.0, 11.0, 0.0))
    hold["cape"] = dict(C=(-2.0, -3.0, -4.0), L=(-3.0, -4.0, -4.0), R=(-2.0, -3.0, -3.0))
    hold["sway"] = 8.0
    key_sequence(arm, [(1, guard, "smooth"), (7, windup, "out"), (11, strike, "in"), (15, hold, "out"), (30, guard, "smooth")])


def make_die(arm):
    new_action(arm, "TRI_Die")
    stand = spec()
    recoil = spec(hips=dict(loc=(0.0, 0.06, -0.04), rot=(-7.0, 4.0, 0.0)), chest=(-14.0, 6.0, 0.0), neck=(-8.0, 0.0, 0.0), head=(-14.0, -6.0, 4.0),
                  jaw=24.0, pads=4.0,
                  arms=dict(L=dict(up=(0.76, 0.10, -0.64), fo=(0.80, -0.32, -0.50), curl=5.0),
                            R=dict(up=(-0.70, 0.30, -0.65), fo=(-0.78, -0.20, -0.60), curl=5.0)),
                  cape=dict(C=(-6.0, -6.0, -6.0), L=(-7.0, -6.0, -5.0), R=(-7.0, -6.0, -5.0)), sway=-16.0)
    limp_l = dict(up=(0.24, -0.10, -0.97), fo=(0.14, -0.24, -0.96), curl=35.0)
    limp = dict(L=limp_l, R=dict(limp_l, up=mir(limp_l["up"]), fo=mir(limp_l["fo"])))
    buckle = spec(hips=dict(loc=(0.0, -0.02, -0.30), rot=(10.0, 2.0, 0.0)), chest=(18.0, 0.0, 0.0), neck=(10.0, 0.0, 0.0), head=(14.0, 0.0, 6.0),
                  jaw=14.0, arms=limp, cape=dict(C=(8.0, 8.0, 8.0), L=(8.0, 7.0, 6.0), R=(8.0, 7.0, 6.0)), sway=10.0)
    down = dict(L=("ik", 0.19, -0.195, 122.0), R=("ik", 0.19, -0.195, 122.0))        # the ankles laid on the ground behind: the knees land
    kneel = spec(hips=dict(loc=(0.0, -0.04, -0.682), rot=(15.0, 0.0, 0.0)), chest=(20.0, 0.0, 0.0), neck=(12.0, 0.0, 0.0), head=(18.0, 0.0, 8.0),
                 jaw=10.0, legs=down, arms=limp, cape=dict(C=(-4.0, 6.0, 8.0), L=(-3.0, 5.0, 7.0), R=(-3.0, 5.0, 7.0)), sway=-6.0)
    over = spec(hips=dict(loc=(0.0, -0.53, -0.70), rot=(55.0, 0.0, 0.0)), chest=(12.0, 0.0, 0.0), neck=(0.0, 0.0, 0.0), head=(4.0, 0.0, 10.0),
                jaw=10.0, legs=down, pads=6.0,
                arms=dict(L=dict(up=(0.50, -0.50, -0.70), fo=(0.30, -0.80, -0.50), curl=20.0),
                          R=dict(up=(-0.55, -0.35, -0.75), fo=(-0.40, -0.70, -0.60), curl=20.0)),
                cape=dict(C=(10.0, 8.0, 6.0), L=(10.0, 8.0, 6.0), R=(10.0, 8.0, 6.0)), sway=0.0)
    arms_flat = dict(L=dict(up=(0.74, -0.62, -0.12), fo=(0.34, -0.93, -0.06), space="world", curl=30.0),
                     R=dict(up=(-0.86, 0.34, -0.14), fo=(-0.58, 0.80, -0.04), space="world", curl=30.0))
    prone = spec(hips=dict(loc=(0.0, -0.79, -1.036), rot=(90.0, 0.0, 0.0)), chest=(6.0, 0.0, 0.0), neck=(-22.0, 0.0, 0.0), head=(-38.0, 8.0, 16.0),
                 jaw=16.0, legs=down, pads=0.0, arms=arms_flat,
                 cape=dict(C=(-12.0, -4.0, -2.0), L=(-16.0, -5.0, -2.0), R=(-16.0, -5.0, -2.0)))
    bounce = _mix(prone, prone, 0.0)
    bounce["hips"] = dict(loc=(0.0, -0.80, -1.005), rot=(88.0, 0.0, 0.0))
    bounce["head"], bounce["jaw"] = (-30.0, 8.0, 12.0), 8.0
    bounce["cape"] = dict(C=(-4.0, 2.0, 3.0), L=(-8.0, 1.0, 3.0), R=(-8.0, 1.0, 3.0))
    rest = _mix(prone, prone, 0.0)
    rest["jaw"], rest["head"] = 20.0, (-40.0, 8.0, 18.0)
    key_sequence(arm, [(1, stand, "smooth"), (5, recoil, "out"), (14, buckle, "smooth"), (21, kneel, "in"), (26, over, "linear"),
                       (31, prone, "in"), (34, bounce, "out"), (38, prone, "smooth"), (48, rest, "smooth")])


ACTIONS = {"TRI_Walk": (1, WALK_FRAMES), "TRI_Punch": (1, 30), "TRI_Die": (1, 48)}


def use_action(arm, name):
    """Makes an action the rig's current one and sets the scene's frames to it."""
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    try:
        arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = ACTIONS[name]
    sc.frame_set(sc.frame_start)


def rig_and_animate():
    sc = bpy.context.scene
    sc.render.fps = FPS
    arm = build_rig()
    attach(arm)
    skin_cloth(arm)
    make_walk(arm)
    make_punch(arm)
    make_die(arm)
    arm["animations"] = "TRI_Walk 1-32 (loops, %.2f m/s), TRI_Punch 1-30, TRI_Die 1-48; %d frames a second" % (WALK_SPEED, FPS)
    use_action(arm, "TRI_Walk")
    return arm
