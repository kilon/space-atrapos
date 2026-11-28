class_name ArmsLayer
extends SkeletonModifier3D
## The automaton's upper body played over whatever its legs are doing (a child of
## its Skeleton3D, after the AnimationPlayer's pose): drawing the rifle from its
## holster on the hip, unfolding it (draw) and folding it back into the holster
## (holster), raising it to aim, a shot's recoil
## - the spine, chest, head, arms and the rifle from those clips, the legs and
## hips from the walk / run / stand below. And the aim: the chest (and the rifle
## with it, round the chest) pitched up or down to where the shot goes.
##
## `weight` 0: the clips below as they are; 1: this layer's pose. A new clip
## cross-fades from the last (`blend` s). CosmosWalker drives it.

const BONES := ["spine", "chest", "head", "pauldron.L", "pauldron.R", "upper.L", "fore.L", "hand.L", "fingers.L",
	"upper.R", "fore.R", "hand.R", "fingers.R", "gun"]
## And every bone of the rifle's folding pieces ("gun.*": automaton.py GUN_FOLD) and of the hip's compartment it's put
## away in ("holster.*": automaton.py POD - its lid opened and shut by draw and holster) the skeleton has.
const MORE := ["gun.", "holster."]
## The rifle's muzzle from its grip, in its bone's axes (its Y the barrel, Z its top): automaton.py rifle().
const MUZZLE := Vector3(0.0, 0.785, 0.08)

var weight := 0.0
var pitch := 0.0          # rad: the aim up (+) or down
var aim_k := 0.0          # how much of the pitch (0..1)

var _ap: AnimationPlayer
var _cur := ""
var _t := 0.0
var _prev := ""
var _pt := 0.0
var _mix := 1.0
var _mix_rate := 8.0
var _tracks := {}         # clip -> {bone index: [rotation track, position track]}
var _bones := {}          # (the skeleton's bones this layer poses: "list" - BONES and MORE's)


func setup(ap: AnimationPlayer) -> void:
	_ap = ap


func clip() -> String:
	return _cur


func time() -> float:
	return _t


## Plays `name` from `from` (a cross-fade of `blend` s from what it was playing).
func play(name: String, from := 0.0, blend := 0.12) -> void:
	if _ap == null or not _ap.has_animation(name):
		return
	_prev = _cur
	_pt = _t
	_cur = name
	_t = from
	_mix = 1.0 if _prev == "" or blend <= 0.0 else 0.0
	_mix_rate = 1.0 / maxf(blend, 0.001)


func step(dt: float, speed := 1.0) -> void:
	if _cur == "":
		return
	_t = minf(_t + dt * speed, length())
	_mix = minf(1.0, _mix + dt * _mix_rate)


func length() -> float:
	return _ap.get_animation(_cur).length if _ap and _cur != "" and _ap.has_animation(_cur) else 0.0


## Its cross-fade into the clip finished.
func blended() -> bool:
	return _mix >= 1.0


func done() -> bool:
	return _cur == "" or _t >= length() - 0.001


## The muzzle (global): the rifle's bone as posed now, MUZZLE along it.
func muzzle() -> Vector3:
	var sk := get_skeleton()
	if sk == null:
		return Vector3.ZERO
	if has_gun_pose:
		return sk.global_transform * (gun_pose * MUZZLE)
	var g := sk.find_bone("gun")
	if g < 0:
		return sk.global_position
	return sk.global_transform * (sk.get_bone_global_pose(g) * MUZZLE)


## The barrel's way (global), as the rifle's posed now.
func barrel() -> Vector3:
	var sk := get_skeleton()
	return (sk.global_basis * gun_pose.basis.y).normalized() if sk and has_gun_pose else Vector3.ZERO


var gun_pose := Transform3D()   # (the rifle's bone, skeleton space, as last posed - with this layer)
var has_gun_pose := false


func _tracks_of(name: String, sk: Skeleton3D) -> Dictionary:
	if _tracks.has(name):
		return _tracks[name]
	var out := {}
	var a := _ap.get_animation(name)
	for t in a.get_track_count():
		var bone := str(a.track_get_path(t)).get_slice(":", 1)
		if not (_poses(bone) or bone == "pelvis" or bone == "thigh.R"):
			continue
		var b := sk.find_bone(bone)
		if b < 0:
			continue
		if not out.has(b):
			out[b] = [-1, -1]
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			out[b][0] = t
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			out[b][1] = t
	_tracks[name] = out
	return out


static func _poses(bone: String) -> bool:
	if bone in BONES:
		return true
	for m in MORE:
		if bone.begins_with(m):
			return true
	return false


## The bones it poses, the skeleton's order (parents first).
func _names(sk: Skeleton3D) -> Array:
	if not _bones.has("list"):
		var out := []
		for b in sk.get_bone_count():
			if _poses(sk.get_bone_name(b)):
				out.append(sk.get_bone_name(b))
		_bones["list"] = out
	return _bones["list"]


## How much the clip has the rifle in the hip's compartment (0..1): its grip near the box's place on the clip's
## thigh - there it rides the legs' thigh (the walk's), not the clip's, so it stays in the box as it opens.
func _in_box(sk: Skeleton3D, clip_gun: Transform3D, clip_thigh: Transform3D) -> float:
	var hb := sk.find_bone("holster.R")
	if hb < 0:
		return 0.0
	var d := (clip_thigh.affine_inverse() * clip_gun).origin.distance_to(sk.get_bone_rest(hb).origin)
	return 1.0 - smoothstep(0.03, 0.16, d)


## A bone's pose in the layer's clip (cross-faded from the last): [rotation or null, position or null].
func _sample(b: int, cur: Dictionary, a: Animation, prev: Dictionary, pa: Animation) -> Array:
	var q = null
	var p = null
	if cur.has(b):
		var tr: Array = cur[b]
		if tr[0] >= 0:
			q = a.rotation_track_interpolate(tr[0], _t)
			if pa and prev.has(b) and prev[b][0] >= 0:
				q = (pa.rotation_track_interpolate(prev[b][0], _pt) as Quaternion).slerp(q, _mix)
		if tr[1] >= 0:
			p = a.position_track_interpolate(tr[1], _t)
			if pa and prev.has(b) and prev[b][1] >= 0:
				p = (pa.position_track_interpolate(prev[b][1], _pt) as Vector3).lerp(p, _mix)
	return [q, p]


func _process_modification_with_delta(_delta: float) -> void:
	_pose_now()


func _process_modification() -> void:
	_pose_now()


func _pose_now() -> void:
	var sk := get_skeleton()
	if sk == null or _ap == null:
		return
	if weight > 0.001 and _cur != "":
		var cur := _tracks_of(_cur, sk)
		var a := _ap.get_animation(_cur)
		var prev := _tracks_of(_prev, sk) if _mix < 1.0 and _prev != "" and _ap.has_animation(_prev) else {}
		var pa: Animation = _ap.get_animation(_prev) if not prev.is_empty() else null
		var pelvis := sk.find_bone("pelvis")
		var spine := sk.find_bone("spine")
		# (the legs' pelvis - its walk's bob and sway - against the clip's: the upper body put where the
		# clip has it, carried by the pelvis's move; the rifle - a root bone - carried the same)
		var actual := sk.get_bone_pose(pelvis)
		var ps := _sample(pelvis, cur, a, prev, pa)
		var clip_pelvis := Transform3D(Basis(ps[0] if ps[0] != null else actual.basis.get_rotation_quaternion()), ps[1] if ps[1] != null else actual.origin)
		var shift := actual.origin - clip_pelvis.origin
		var thigh := sk.find_bone("thigh.R")
		for name in _names(sk):
			var b := sk.find_bone(name)
			if b < 0 or not cur.has(b):
				continue
			var s := _sample(b, cur, a, prev, pa)
			if name == "gun" and s[0] != null and s[1] != null and thigh >= 0 and cur.has(thigh):
				# (in or by its box: carried by the legs' thigh the way the clip's thigh carries it)
				var ts := _sample(thigh, cur, a, prev, pa)
				var clip_thigh := clip_pelvis * Transform3D(Basis(ts[0] if ts[0] != null else sk.get_bone_pose_rotation(thigh)),
						ts[1] if ts[1] != null else sk.get_bone_pose_position(thigh))
				var clip_gun := Transform3D(Basis(s[0]), s[1])
				var k := _in_box(sk, clip_gun, clip_thigh)
				var want_g := Transform3D(Basis(s[0]), s[1] + shift)
				if k > 0.001:
					want_g = want_g.interpolate_with(sk.get_bone_global_pose(thigh) * (clip_thigh.affine_inverse() * clip_gun), k)
				sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(want_g.basis.get_rotation_quaternion(), weight))
				sk.set_bone_pose_position(b, sk.get_bone_pose_position(b).lerp(want_g.origin, weight))
				continue
			if b == spine:
				var local := Transform3D(Basis(s[0] if s[0] != null else sk.get_bone_pose_rotation(b)), s[1] if s[1] != null else sk.get_bone_pose_position(b))
				var want := Transform3D(clip_pelvis.basis, clip_pelvis.origin + shift) * local
				var l2 := actual.affine_inverse() * want
				sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(l2.basis.get_rotation_quaternion(), weight))
				sk.set_bone_pose_position(b, sk.get_bone_pose_position(b).lerp(l2.origin, weight))
				continue
			if s[0] != null:
				sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b).slerp(s[0], weight))
			if s[1] != null:
				var pos: Vector3 = s[1] + (shift if name == "gun" else Vector3.ZERO)
				sk.set_bone_pose_position(b, sk.get_bone_pose_position(b).lerp(pos, weight))
	if aim_k > 0.001 and absf(pitch) > 0.001:
		_pitch_chest(sk, pitch * aim_k)
	var gb := sk.find_bone("gun")
	if gb >= 0:
		gun_pose = sk.get_bone_global_pose(gb)   # (as posed - the skeleton's own pose drops the modifiers' after the frame)
		has_gun_pose = true


## The chest turned up / down round its own middle (the arms with it), and the rifle -
## its own root bone - turned the same, round the same point.
func _pitch_chest(sk: Skeleton3D, p: float) -> void:
	var chest := sk.find_bone("chest")
	var spine := sk.find_bone("spine")
	var gun := sk.find_bone("gun")
	if chest < 0 or spine < 0:
		return
	var parent := sk.get_bone_global_pose(spine)
	var g := parent * sk.get_bone_pose(chest)
	var r := Basis(Vector3(1, 0, 0), -p)   # (the model faces +z: about +x, -p tips the front up)
	var g2 := Transform3D(r * g.basis, g.origin)
	var local := parent.affine_inverse() * g2
	sk.set_bone_pose_rotation(chest, local.basis.get_rotation_quaternion())
	if gun >= 0:
		var gg := sk.get_bone_pose(gun)   # (a root bone: its pose is its place in the skeleton)
		var o := g.origin + r * (gg.origin - g.origin)
		sk.set_bone_pose_rotation(gun, (r * gg.basis).get_rotation_quaternion())
		sk.set_bone_pose_position(gun, o)
