class_name CosmosMammoth
extends RefCounted
## The mushroom mammoth (CosmosFauna "mykelephas", kind "model": "mammoth") - a
## towering, calm grazer with a fungus growing from its back; its own model and
## motion, not the generic heavy kit: one shared skinned mesh (one surface, one
## draw call, a lower LOD for far off; made on a worker like the fox's) over a
## 31-bone rig each mammoth builds for itself (Rig):
##  - a massive body (a high domed shoulder, the back sloping to the rump, a
##    heavy hanging belly), thick pillar legs on broad round feet with toenails,
##    a big head with a domed skull, small deep-set eyes in wrinkled lids, large
##    fan ears, a long trunk (six bones) ending in a finger, curved tusks out,
##    down and up, a short tail with a tuft of coarse hair;
##  - the fungus: a stout stalk rising from the spine with a ring on it, a
##    broad domed cap with a wavy rolled rim, gills under it, warts over it (c2),
##    and small mushrooms sprouting from the shoulders and back;
##  - the skin (mammoth.gdshader): thick, cracked into plates, folded at the
##    joints and ringed along the trunk (bumped in the shader from the rest
##    position - CUSTOM0), mottled, sparse coarse hair, mud and dust low on the
##    legs, a little light through the ears; the cap moist, warted, gilled.
##    COLOR: r - 0..0.2 fungus (amount), 0.4 a toenail, 0.6 a tusk, 0.8 an eye;
##    g - a fold's strength on skin, the fungus's part (0 stalk, 0.5 gills, 1 the
##    cap), along a tusk, an eye's depth; b - thin / pink (ears, the trunk's tip,
##    the lip); a - hair.
## Rig.step() moves it: the walk a lateral-sequence four-beat gait (each hind
## foot, then the fore on its side), an amble when it hurries (no moment off the
## ground), the feet planted (each leg reaches its foot by IK; the body rises
## over the stance legs and sinks between them, swaying from side to side), the
## head nodding, the ears fanning slowly, the trunk swinging with the stride and
## the cap jiggling on its stalk; standing, it grazes (the trunk feeling over
## the ground, curling a mouthful up to its mouth, the jaw chewing), fans its
## ears, rests a hind leg, throws dust over its back, looks round, swishes its
## tail; hurt, it trumpets. Unit space (y up from the ground, forward -z);
## CosmosCreature scales it by the species' size.

const SHADER := preload("res://shaders/world/mammoth.gdshader")

## The bones: [name, parent, rest position (unit space, global)].
const BONES := [
	["pelvis", -1, Vector3(0, 1.2, 0.5)],
	["chest", 0, Vector3(0, 1.25, -0.35)],
	["neck", 1, Vector3(0, 1.36, -0.66)],
	["head", 2, Vector3(0, 1.46, -0.92)],
	["jaw", 3, Vector3(0, 1.22, -1.0)],
	["ear_l", 3, Vector3(-0.22, 1.5, -0.86)],
	["ear_l2", 5, Vector3(-0.33, 1.42, -0.64)],
	["ear_r", 3, Vector3(0.22, 1.5, -0.86)],
	["ear_r2", 7, Vector3(0.33, 1.42, -0.64)],
	["trunk0", 3, Vector3(0, 1.3, -1.19)],
	["trunk1", 9, Vector3(0, 1.1, -1.27)],
	["trunk2", 10, Vector3(0, 0.9, -1.3)],
	["trunk3", 11, Vector3(0, 0.7, -1.31)],
	["trunk4", 12, Vector3(0, 0.51, -1.3)],
	["trunk5", 13, Vector3(0, 0.34, -1.28)],
	["tail0", 0, Vector3(0, 1.2, 1.02)],
	["tail1", 15, Vector3(0, 0.95, 1.08)],
	["cap", 0, Vector3(0, 1.42, 0.08)],
	["cap_top", 17, Vector3(0, 1.84, 0.08)],
	["fl_up", 1, Vector3(-0.29, 1.18, -0.45)],
	["fl_low", 19, Vector3(-0.3, 0.7, -0.4)],
	["fl_foot", 20, Vector3(-0.3, 0.19, -0.46)],
	["fr_up", 1, Vector3(0.29, 1.18, -0.45)],
	["fr_low", 22, Vector3(0.3, 0.7, -0.4)],
	["fr_foot", 23, Vector3(0.3, 0.19, -0.46)],
	["hl_up", 0, Vector3(-0.28, 1.12, 0.6)],
	["hl_low", 25, Vector3(-0.29, 0.62, 0.52)],
	["hl_foot", 26, Vector3(-0.29, 0.19, 0.64)],
	["hr_up", 0, Vector3(0.28, 1.12, 0.6)],
	["hr_low", 28, Vector3(0.29, 0.62, 0.52)],
	["hr_foot", 29, Vector3(0.29, 0.19, 0.64)],
]
enum { PELVIS, CHEST, NECK, HEAD, JAW, EAR_L, EAR_L2, EAR_R, EAR_R2,
	TRUNK0, TRUNK1, TRUNK2, TRUNK3, TRUNK4, TRUNK5, TAIL0, TAIL1, CAP, CAP_TOP,
	FL_UP, FL_LOW, FL_FOOT, FR_UP, FR_LOW, FR_FOOT, HL_UP, HL_LOW, HL_FOOT, HR_UP, HR_LOW, HR_FOOT }
## Where the ankles stand (unit space height) - the soles flat on the ground under them.
const ANKLE_Y := 0.19
## Its bulk for the camera and shots (unit space): the body, the head - [centre, radii].
const BULK := [[Vector3(0, 1.12, 0.1), Vector3(0.5, 0.48, 0.98)], [Vector3(0, 1.45, -0.98), Vector3(0.3, 0.32, 0.32)]]

static var _mesh: ArrayMesh
static var _skin: Skin
static var _task := -1
static var _built: Builder
## What the last build made (the tests read it).
static var made := {}


static func start() -> void:
	if _mesh != null or _task >= 0:
		return
	_built = Builder.new()
	_task = WorkerThreadPool.add_task(_built.run, false, "mammoth mesh")


static func is_ready() -> bool:
	return _mesh != null or (_task >= 0 and WorkerThreadPool.is_task_completed(_task))


static func mesh() -> ArrayMesh:
	if _mesh == null:
		start()
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var b := _built
		var m := ArrayMesh.new()
		var fmt := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays, [], b.lods, fmt)
		m.custom_aabb = AABB(Vector3(-1.6, -0.3, -2.4), Vector3(3.2, 2.9, 3.9))   # (the trunk raised, the ears spread)
		made = {"legs": b.legs, "toenails": b.nails, "tusks": b.tusks, "ears": b.ears, "eyes": b.eyes, "trunk_rings": b.trunk_rings,
			"cap_sides": b.cap_sides, "growths": b.growths, "tuft": b.tuft, "tris": b.body.idx.size() / 3, "verts": b.body.v.size(),
			"lods": b.lods.size(), "lod_tris": b.lod_tris, "build_ms": b.ms}
		_built = null
		_mesh = m
	return _mesh


## The skin binding the mesh to a rig (shared).
static func skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		for i in BONES.size():
			_skin.add_bind(i, Transform3D(Basis(), -(BONES[i][2] as Vector3)))
	return _skin


static func material(c1: Color, c2: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("c1", c1)
	m.set_shader_parameter("c2", c2)
	m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	return m


## A mammoth's skeleton (its bones at rest).
static func skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	for i in BONES.size():
		var b: Array = BONES[i]
		sk.add_bone(b[0])
		var p: int = b[1]
		var at: Vector3 = b[2]
		if p >= 0:
			sk.set_bone_parent(i, p)
			at -= BONES[p][2] as Vector3
		sk.set_bone_rest(i, Transform3D(Basis(), at))
	sk.reset_bone_poses()
	return sk


static func rig(sk: Skeleton3D, seed: int) -> Rig:
	return Rig.new(sk, seed)


## A point `at` (local to the creature, metres) against its bulk: how far along
## the ray o + dir * s (s up to `limit`) it enters the body or the head, or INF.
## `size`: metres a unit.
static func ray_hit(o: Vector3, dir: Vector3, limit: float, size: float) -> float:
	var best := INF
	for e: Array in BULK:
		var c: Vector3 = (e[0] as Vector3) * size
		var r: Vector3 = (e[1] as Vector3) * size
		var lo := (o - c) / r
		var ld := dir / r
		var a := ld.dot(ld)
		var bq := lo.dot(ld)
		var cq := lo.dot(lo) - 1.0
		var disc := bq * bq - a * cq
		if disc < 0.0:
			continue
		var s := (-bq - sqrt(disc)) / a
		if cq < 0.0:
			s = 0.0   # (starting inside)
		if s >= 0.0 and s < limit:
			best = minf(best, s)
	return best


## The mesh's vertices with their bones and weights, and each one's rest place (CUSTOM0: the skin's detail).
class MamPart extends CosmosFox.FoxPart:
	var rest := PackedFloat32Array()
	var seams := PackedInt32Array()   # (pairs: a ring's first and last vertex - one normal)

	func arrays() -> Array:
		var n := PackedVector3Array()
		n.resize(v.size())
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			var f := (v[c] - v[a]).cross(v[b] - v[a])
			n[a] += f
			n[b] += f
			n[c] += f
		for k in range(0, seams.size(), 2):
			var s := n[seams[k]] + n[seams[k + 1]]
			n[seams[k]] = s
			n[seams[k + 1]] = s
		for i in n.size():
			n[i] = n[i].normalized() if n[i].length_squared() > 1e-20 else Vector3.UP
		flat_n = n
		var arr := super()
		arr[Mesh.ARRAY_CUSTOM0] = rest
		return arr


class Builder:
	var body := MamPart.new()
	var arrays: Array
	var lods := {}
	var lod_tris := 0
	var legs := 0
	var nails := 0
	var tusks := 0
	var ears := 0
	var eyes := 0
	var trunk_rings := 0
	var cap_sides := 0
	var growths := 0
	var tuft := 0
	var ms := 0.0

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		_torso()
		_head()
		_trunk()
		_tusks()
		_ears()
		_legs()
		_tail()
		_fungus()
		arrays = body.arrays()
		_lod()
		ms = (Time.get_ticks_usec() - t0) / 1000.0

	## A simpler mesh for far off - the shared chain (LodKit: meshoptimizer, the
	## seams and the weights kept), its levels keyed by their error, as Godot picks them.
	func _lod() -> void:
		lods = LodKit.lods(arrays, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		lod_tris = LodKit.coarsest(lods, body.idx.size() / 3)

	func _vert(q: Vector3, c: Color, uv: Vector2, sk: Vector3) -> int:
		var i := body.add(q, c, uv, Vector2.ZERO)
		var w := clampf(sk.z, 0.0, 1.0)
		if int(sk.x) == int(sk.y):
			w = 0.0
		body.bones.append_array([int(sk.x), int(sk.y), 0, 0])
		body.weights.append_array([1.0 - w, w, 0.0, 0.0])
		body.rest.append_array([q.x, q.y, q.z])
		return i

	## Rings of `sides` vertices: ring i = [centre, ex, ey up, ey down, superellipse
	## exponent, bones Vector3(a, b, weight of b)] - a vertex at angle t:
	## centre + ex f(cos t) + ey f(sin t), the frame (ex, ey, the way on) right-handed;
	## `col` its colour (ring, outward, place, along 0..1); `skf` (optional) a bone
	## pair per vertex (ring, place) in place of the ring's; `warp` (optional) moves it (ring, place, angle).
	func sweep(rings: Array, col: Callable, sides: int, close_a := true, close_b := true, skf := Callable(), warp := Callable()) -> void:
		var n := rings.size()
		var base := body.v.size()
		var total := 0.0
		for i in range(1, n):
			total += ((rings[i][0] as Vector3) - (rings[i - 1][0] as Vector3)).length()
		var along := 0.0
		for i in n:
			var r: Array = rings[i]
			var c: Vector3 = r[0]
			if i > 0:
				along += (c - (rings[i - 1][0] as Vector3)).length()
			var ex: Vector3 = r[1]
			var eyu: Vector3 = r[2]
			var eyd: Vector3 = r[3]
			var e := 2.0 / float(r[4])
			for j in sides + 1:
				var a := TAU * j / sides
				var ca := cos(a)
				var sa := sin(a)
				var q: Vector3 = c + ex * signf(ca) * pow(absf(ca), e) + (eyu if sa >= 0.0 else eyd) * signf(sa) * pow(absf(sa), e)
				if warp.is_valid():
					q = warp.call(i, q, a)
				var dir := (q - c).normalized()
				var sk: Vector3 = skf.call(i, q) if skf.is_valid() else r[5]
				_vert(q, col.call(i, dir, q, along / maxf(total, 1e-5)), Vector2(float(j) / sides, along), sk)
			body.seams.append_array([base + i * (sides + 1), base + i * (sides + 1) + sides])
		for i in n - 1:
			for j in sides:
				var a := base + i * (sides + 1) + j
				var b := a + sides + 1
				body.tri(a, a + 1, b)
				body.tri(a + 1, b + 1, b)
		for e in [0, n - 1]:
			if (e == 0 and not close_a) or (e == n - 1 and not close_b):
				continue
			var ring: int = base + e * (sides + 1)
			var c := _vert(rings[e][0], body.col[ring], Vector2(0.5, along if e > 0 else 0.0), skf.call(e, rings[e][0]) if skf.is_valid() else rings[e][5])
			for j in sides:
				if e == 0:
					body.tri(c, ring + j + 1, ring + j)
				else:
					body.tri(c, ring + j, ring + j + 1)

	## A tube through `pts` (radii `rad`: x across, y the other way), its rings
	## bound to `sk` - the frames carried along it.
	func tube(pts: Array, rad: Array, sk: Array, col: Callable, sides: int, close_a := true, close_b := true, skf := Callable()) -> void:
		var n := pts.size()
		var t0: Vector3 = ((pts[1] as Vector3) - (pts[0] as Vector3)).normalized()
		var up := Vector3.UP if absf(t0.y) < 0.9 else Vector3.BACK
		var rings := []
		for i in n:
			var t: Vector3
			if i == 0:
				t = t0
			elif i == n - 1:
				t = ((pts[i] as Vector3) - (pts[i - 1] as Vector3)).normalized()
			else:
				t = ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)).normalized()
			up = (up - t * up.dot(t)).normalized()
			var side := up.cross(t).normalized()
			var r: Vector2 = rad[i]
			rings.append([pts[i], side * r.x, up * r.y, up * r.y, 2.0, sk[i]])
		sweep(rings, col, sides, close_a, close_b, skf)

	## An ellipsoid round `at` along `axis`, bound to one bone.
	func blob(at: Vector3, r: Vector3, axis: Vector3, bone: int, col: Callable, rings: int, sides: int) -> void:
		axis = axis.normalized()
		var pts := []
		var rad := []
		var sk := []
		var ra := absf(axis.dot(r))
		var other := Vector2(r.x, r.y) if absf(axis.z) > 0.5 else (Vector2(r.z, r.y) if absf(axis.x) > 0.5 else Vector2(r.x, r.z))
		for i in rings + 1:
			var th := PI * i / rings
			pts.append(at - axis * cos(th) * ra)
			rad.append(other * maxf(sin(th), 0.0))
			sk.append(Vector3(bone, bone, 0))
		tube(pts, rad, sk, col, sides)

	## Catmull-Rom through `keys` (floats or Vector3s) at f (0..1).
	static func spline(keys: Array, f: float) -> Variant:
		var n := keys.size() - 1
		var x := clampf(f, 0.0, 1.0) * n
		var i := mini(int(x), n - 1)
		var t := x - i
		var p0: Variant = keys[maxi(i - 1, 0)]
		var p1: Variant = keys[i]
		var p2: Variant = keys[i + 1]
		var p3: Variant = keys[mini(i + 2, n)]
		var t2 := t * t
		var t3 := t2 * t
		return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

	static func skin(fold := 0.0, pink := 0.0, hair := 0.0) -> Color:
		return Color(0.0, fold, pink, hair)

	# The body: chest to rump - the dome over the shoulders, the back sloping to
	# a rounded rump, the belly hanging low between the legs.
	const TZ := [-0.82, -0.72, -0.6, -0.45, -0.25, 0.0, 0.25, 0.5, 0.68, 0.8, 0.9, 0.98, 1.05, 1.1]
	const TTOP := [1.36, 1.48, 1.55, 1.58, 1.56, 1.5, 1.46, 1.44, 1.42, 1.39, 1.34, 1.27, 1.18, 1.09]
	const TBOT := [1.06, 0.96, 0.86, 0.79, 0.73, 0.69, 0.7, 0.74, 0.78, 0.8, 0.84, 0.9, 0.96, 1.02]
	const TW := [0.16, 0.3, 0.38, 0.43, 0.46, 0.47, 0.46, 0.44, 0.41, 0.38, 0.33, 0.26, 0.17, 0.06]

	## The body's top surface at (x, z) (unit space) - where things grow from it.
	static func torso_top(x: float, z: float) -> float:
		var f := inverse_lerp(-0.82, 1.1, z)
		var top: float = spline(TTOP, f)
		var bot: float = spline(TBOT, f)
		var w: float = spline(TW, f)
		var cy := (top + bot) * 0.5
		var h := (top - bot) * 0.5
		var c := clampf(absf(x) / w, 0.0, 1.0)
		return cy + h * pow(maxf(1.0 - pow(c, 2.25), 0.0), 1.0 / 2.25)

	func _torso() -> void:
		var rings := []
		var n := 20
		for i in n + 1:
			var f := float(i) / n
			var z: float = spline(TZ, f)
			var top: float = spline(TTOP, f)
			var bot: float = spline(TBOT, f)
			var w: float = spline(TW, f)
			var cy := (top + bot) * 0.5
			var h := (top - bot) * 0.5
			# (the frame: across, up - along +z, right-handed)
			rings.append([Vector3(0, cy, z), Vector3(w, 0, 0), Vector3(0, h, 0), Vector3(0, h * 1.02, 0), 2.25,
				Vector3(PELVIS, CHEST, smoothstep(0.35, -0.35, z))])
		var col := func(_i: int, dir: Vector3, q: Vector3, _f: float) -> Color:
			var belly := smoothstep(-0.3, -0.8, dir.y)   # (folds where the belly hangs, round the legs' tops)
			var hump := smoothstep(0.4, 0.9, dir.y) * smoothstep(0.2, -0.5, q.z)
			return skin(0.15 + belly * 0.35, 0.0, 0.25 + hump * 0.6)
		sweep(rings, col, 22)

	func _head() -> void:
		# The neck: short and thick, folded.
		var neck := func(_i: int, dir: Vector3, _q: Vector3, _f: float) -> Color:
			return skin(0.7 + smoothstep(0.0, -0.6, dir.y) * 0.3, 0.0, smoothstep(0.3, 0.9, dir.y) * 0.5)
		tube([Vector3(0, 1.22, -0.55), Vector3(0, 1.3, -0.66), Vector3(0, 1.37, -0.77), Vector3(0, 1.43, -0.87)],
			[Vector2(0.36, 0.36), Vector2(0.33, 0.34), Vector2(0.29, 0.31), Vector2(0.25, 0.27)],
			[Vector3(CHEST, NECK, 0.3), Vector3(CHEST, NECK, 0.8), Vector3(NECK, HEAD, 0.3), Vector3(NECK, HEAD, 0.8)], neck, 20, false, false)
		# The skull: domed high, the brow over the trunk's root, heavy cheeks.
		var hz := [-0.74, -0.82, -0.92, -1.02, -1.1, -1.16, -1.21]
		var hcy := [1.45, 1.48, 1.49, 1.47, 1.42, 1.36, 1.31]
		var htop := [0.22, 0.27, 0.285, 0.26, 0.21, 0.155, 0.11]
		var hbot := [0.24, 0.29, 0.31, 0.3, 0.26, 0.19, 0.13]
		var hw := [0.23, 0.28, 0.295, 0.28, 0.24, 0.185, 0.13]
		var rings := []
		var n := 9
		for i in n + 1:
			var f := float(i) / n
			# (along -z: across -x, right-handed)
			rings.append([Vector3(0, float(spline(hcy, f)), float(spline(hz, f))), Vector3(-float(spline(hw, f)), 0, 0), Vector3(0, float(spline(htop, f)), 0),
				Vector3(0, float(spline(hbot, f)), 0), 2.2, Vector3(HEAD, HEAD, 0)])
		var col := func(_i: int, dir: Vector3, q: Vector3, _f: float) -> Color:
			var temple := smoothstep(0.75, 0.95, absf(dir.x)) * smoothstep(-1.12, -0.98, q.z)
			return skin(0.35 + temple * 0.5, 0.0, smoothstep(0.5, 0.95, dir.y) * 0.8)
		sweep(rings, col, 22)
		# The lower lip, pink and moist, on the jaw.
		var lip := func(_i: int, dir: Vector3, _q: Vector3, _f: float) -> Color:
			return skin(0.5, smoothstep(0.2, -0.4, dir.y) * 0.4 + 0.25)
		blob(Vector3(0, 1.15, -1.1), Vector3(0.1, 0.065, 0.09), Vector3.BACK, JAW, lip, 5, 10)
		# Small eyes, deep in wrinkled lids, looking out and forward.
		for s in [-1.0, 1.0]:
			var axis := Vector3(s, 0.05, -0.55).normalized()
			var lid := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
				return skin(1.0)
			blob(Vector3(s * 0.225, 1.46, -1.07), Vector3(0.05, 0.042, 0.05), axis, HEAD, lid, 4, 10)
			var eye := func(i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
				return Color(0.8, float(i) / 4.0, 0, 0)
			blob(Vector3(s * 0.225, 1.46, -1.07) + axis * 0.03, Vector3(0.024, 0.02, 0.024), axis, HEAD, eye, 4, 8)
			eyes += 1

	## The trunk: from the brow to the ground, tapering, ringed, a finger at its tip.
	func _trunk() -> void:
		var chain: Array = [Vector3(0, 1.36, -1.15)]
		for b in range(TRUNK0, TRUNK5 + 1):
			chain.append(BONES[b][2])
		chain.append(Vector3(0, 0.17, -1.26))
		var pts := []
		var rad := []
		var sk := []
		var n := 20
		for i in n + 1:
			var f := float(i) / n
			pts.append(spline(chain, f) as Vector3)
			var r := lerpf(0.16, 0.05, pow(f, 0.8)) + 0.012 * smoothstep(0.85, 1.0, f)
			rad.append(Vector2(r, r * 0.88))
			var x := f * (chain.size() - 1) - 1.0   # (along the bones: 0 at trunk0 .. 6 the tip)
			var b0 := clampi(int(floor(x)), 0, 5)
			var k := clampf(x - b0, 0.0, 1.0)
			if x < 0.0:
				sk.append(Vector3(HEAD, TRUNK0, smoothstep(-1.0, 0.0, x)))
			else:
				sk.append(Vector3(TRUNK0 + b0, TRUNK0 + mini(b0 + 1, 5), smoothstep(0.3, 1.0, k) if b0 < 5 else 0.0))
			trunk_rings += 1
		var col := func(_i: int, dir: Vector3, _q: Vector3, f: float) -> Color:
			return skin(0.9 - f * 0.2, smoothstep(0.9, 1.0, f) * 0.8, smoothstep(0.2, 0.8, dir.z) * 0.3 * (1.0 - f))
		tube(pts, rad, sk, col, 12)
		var tip := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return skin(0.6, 0.7)
		blob(Vector3(0, 0.15, -1.3), Vector3(0.03, 0.05, 0.03), Vector3(0, -0.6, -0.8), TRUNK5, tip, 4, 8)

	## Curved tusks: out, down and forward, then up and in; ivory, sheathed at the root.
	func _tusks() -> void:
		for s in [-1.0, 1.0]:
			var keys := [Vector3(s * 0.12, 1.25, -1.1), Vector3(s * 0.16, 1.1, -1.22), Vector3(s * 0.2, 0.99, -1.35), Vector3(s * 0.23, 0.94, -1.5),
				Vector3(s * 0.215, 0.98, -1.64), Vector3(s * 0.15, 1.07, -1.74), Vector3(s * 0.08, 1.17, -1.78)]
			var pts := []
			var rad := []
			var sk := []
			var n := 12
			for i in n + 1:
				var f := float(i) / n
				pts.append(spline(keys, f) as Vector3)
				var r := lerpf(0.058, 0.004, pow(f, 1.3))
				rad.append(Vector2(r, r))
				sk.append(Vector3(HEAD, HEAD, 0))
			var ivory := func(_i: int, _d: Vector3, _q: Vector3, f: float) -> Color:
				return Color(0.6, f, 0, 0)
			tube(pts, rad, sk, ivory, 10)
			var sheath := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
				return skin(0.9)
			blob(Vector3(s * 0.135, 1.2, -1.14), Vector3(0.075, 0.07, 0.075), Vector3(s * 0.3, -0.6, -0.7), HEAD, sheath, 4, 10)
			tusks += 1

	## Big fan ears lying back along the neck: thin, veined, light through them.
	func _ears() -> void:
		var ey := [1.72, 1.66, 1.56, 1.44, 1.32, 1.2, 1.1, 1.02, 0.98]
		var ew := [0.05, 0.25, 0.39, 0.45, 0.46, 0.41, 0.31, 0.17, 0.04]
		for s in [-1.0, 1.0]:
			var e1 := EAR_L if s < 0 else EAR_R
			var e2 := EAR_L2 if s < 0 else EAR_R2
			var back := Vector3(s * 0.62, 0, 1).normalized()
			var out := Vector3(s, 0, -0.62).normalized()
			var rings := []
			var n := 10
			for i in n + 1:
				var f := float(i) / n
				var y: float = spline(ey, f)
				var w: float = maxf(float(spline(ew, f)), 0.01)
				var root := Vector3(s * (0.215 + (1.66 - y) * 0.05), y, -0.88 + maxf(1.3 - y, 0.0) * 0.25)
				# (down the ear: across = back, the other way = out; right-handed with -y)
				var ex := back * (w * 0.5)
				var eyv: Vector3 = out * 0.02 * s * -1.0
				rings.append([root + back * (w * 0.5), ex, eyv, eyv, 2.0, Vector3(e1, e1, 0)])
			var skf := func(_i: int, q: Vector3) -> Vector3:
				var d := (q - Vector3(s * 0.22, q.y, -0.88)).dot(back)
				if d < 0.1:
					return Vector3(HEAD, e1, smoothstep(0.0, 0.1, d))
				return Vector3(e1, e2, smoothstep(0.1, 0.42, d))
			var warp := func(i: int, q: Vector3, _a: float) -> Vector3:
				var d := (q - Vector3(s * 0.22, q.y, -0.88)).dot(back)
				return q + back * (sin(i * 1.9 + d * 7.0) * 0.012 * d) + out * (d * d * 0.25)   # (a ragged edge, the ear cupped)
			var col := func(_i: int, dir: Vector3, _q: Vector3, _f: float) -> Color:
				var inner := smoothstep(0.2, -0.5, dir.dot(out))
				return skin(0.55, 0.6 + inner * 0.4)
			sweep(rings, col, 12, true, true, skf, warp)
			ears += 1

	## Pillar legs: the arm and forearm, the thigh and shin, round feet with nails.
	func _legs() -> void:
		for s in [-1.0, 1.0]:
			for front in [true, false]:
				var up: int = (FL_UP if s < 0 else FR_UP) if front else (HL_UP if s < 0 else HR_UP)
				var low := up + 1
				var foot := up + 2
				var par := CHEST if front else PELVIS
				var j0: Vector3 = BONES[up][2]
				var j1: Vector3 = BONES[low][2]
				var j2: Vector3 = BONES[foot][2]
				var fz := j2.z - 0.005
				var pts := [Vector3(s * 0.2, 1.34, j0.z), j0 + Vector3(-s * 0.02, 0.06, 0), j0.lerp(j1, 0.5), j1, j1.lerp(j2, 0.45), j1.lerp(j2, 0.85), j2,
					Vector3(j2.x, 0.1, fz), Vector3(j2.x, 0.035, fz), Vector3(j2.x, 0.0, fz)]
				var k := 1.0 if front else 1.06
				var rad := [Vector2(0.15, 0.24) * k, Vector2(0.19, 0.235) * k, Vector2(0.18, 0.19) * k, Vector2(0.155, 0.16) * k, Vector2(0.138, 0.14) * k,
					Vector2(0.13, 0.132) * k, Vector2(0.136, 0.14) * k, Vector2(0.155, 0.165) * k, Vector2(0.168, 0.18) * k, Vector2(0.163, 0.175) * k]
				if not front:
					for i in rad.size():
						rad[i] = Vector2(rad[i].x * 0.94, rad[i].y * (1.0 if i < 6 else 1.06))
				var sk := [Vector3(par, up, 0.6), Vector3(up, up, 0), Vector3(up, up, 0), Vector3(up, low, 0.5), Vector3(low, low, 0), Vector3(low, low, 0),
					Vector3(low, foot, 0.5), Vector3(foot, foot, 0), Vector3(foot, foot, 0), Vector3(foot, foot, 0)]
				var col := func(i: int, _d: Vector3, q: Vector3, _f: float) -> Color:
					var joint := 1.0 - smoothstep(0.0, 0.14, minf(absf(q.y - j1.y), absf(q.y - j2.y) + 0.03))
					return skin(0.4 + joint * 0.6 if i < 8 else 0.9, 0.0, 0.1)
				tube(pts, rad, sk, col, 14, false, true)
				legs += 1
				# Toenails round the front of the foot.
				var count := 4 if front else 3
				var fr: float = (rad[8] as Vector2).x
				for nn in count:
					var a := lerpf(-0.95, 0.95, float(nn) / (count - 1))
					var dir := Vector3(sin(a), 0, -cos(a))
					var at := Vector3(j2.x, 0.04, fz) + dir * (fr * 0.95)
					var nail := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
						return Color(0.4, 0, 0, 0)
					blob(at, Vector3(0.042, 0.036, 0.042), dir, foot, nail, 3, 5)
					nails += 1

	## A short tail on the rump with a tuft of coarse dark hair.
	func _tail() -> void:
		var pts := [Vector3(0, 1.22, 1.0), Vector3(0, 1.1, 1.06), Vector3(0, 0.97, 1.09), Vector3(0, 0.84, 1.1), Vector3(0, 0.72, 1.105)]
		var rad := [Vector2(0.05, 0.05), Vector2(0.04, 0.04), Vector2(0.032, 0.032), Vector2(0.026, 0.026), Vector2(0.02, 0.02)]
		var sk := [Vector3(PELVIS, TAIL0, 0.6), Vector3(TAIL0, TAIL0, 0), Vector3(TAIL0, TAIL1, 0.6), Vector3(TAIL1, TAIL1, 0), Vector3(TAIL1, TAIL1, 0)]
		var col := func(_i: int, _d: Vector3, _q: Vector3, f: float) -> Color:
			return skin(0.6, 0.0, f)
		tube(pts, rad, sk, col, 8)
		var hair := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return skin(0.0, 0.0, 1.0)
		for i in 7:
			var a := TAU * i / 7.0
			var o := Vector3(cos(a), 0, sin(a)) * 0.016
			var b := Vector3(0, 0.74, 1.105) + o
			var e := b + Vector3(cos(a) * 0.035, -0.17 - (i % 3) * 0.02, sin(a) * 0.035)
			tube([b, b.lerp(e, 0.5) + o * 0.5, e], [Vector2(0.012, 0.012), Vector2(0.009, 0.009), Vector2(0.002, 0.002)],
				[Vector3(TAIL1, TAIL1, 0), Vector3(TAIL1, TAIL1, 0), Vector3(TAIL1, TAIL1, 0)], hair, 4)
			tuft += 1

	## The fungus on its back: the stalk from the spine, its ring, the broad
	## warted cap with a rolled rim and gills; small mushrooms on the shoulders.
	func _fungus() -> void:
		var stalk := func(i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return Color(0.2 * clampf(float(i) / 1.5, 0.0, 1.0), 0.0, 0.0, 0.0)
		var sz := 0.08
		var sy := torso_top(0.0, sz)
		tube([Vector3(0, sy - 0.06, sz), Vector3(0, sy + 0.02, sz), Vector3(0, sy + 0.12, sz), Vector3(0, 1.62, sz), Vector3(0, 1.72, sz), Vector3(0, 1.8, sz)],
			[Vector2(0.24, 0.26), Vector2(0.19, 0.2), Vector2(0.155, 0.16), Vector2(0.135, 0.135), Vector2(0.13, 0.13), Vector2(0.15, 0.15)],
			[Vector3(PELVIS, CHEST, 0.33), Vector3(PELVIS, CAP, 0.5), Vector3(CAP, CAP, 0), Vector3(CAP, CAP, 0), Vector3(CAP, CAP_TOP, 0.5), Vector3(CAP, CAP_TOP, 0.9)],
			stalk, 16, false, false)
		var skirt := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return Color(0.2, 0.1, 0.0, 0.0)
		tube([Vector3(0, 1.7, sz), Vector3(0, 1.68, sz), Vector3(0, 1.63, sz)], [Vector2(0.133, 0.133), Vector2(0.165, 0.165), Vector2(0.175, 0.175)],
			[Vector3(CAP, CAP, 0), Vector3(CAP, CAP, 0), Vector3(CAP, CAP, 0)], skirt, 16, false, false)
		# The cap: from its crown over the rim and in under it to the stalk.
		var prof := [Vector2(0.06, 2.098), Vector2(0.17, 2.085), Vector2(0.33, 2.04), Vector2(0.47, 1.96), Vector2(0.57, 1.87), Vector2(0.63, 1.79),
			Vector2(0.65, 1.745), Vector2(0.63, 1.715), Vector2(0.56, 1.715), Vector2(0.42, 1.74), Vector2(0.27, 1.77), Vector2(0.14, 1.79)]
		var rings := []
		for i in prof.size():
			var p: Vector2 = prof[i]
			# (round the stalk: ex x, ey z - (x, z, the way on) right-handed down the outside)
			rings.append([Vector3(0, p.y, sz), Vector3(p.x, 0, 0), Vector3(0, 0, p.x), Vector3(0, 0, p.x), 2.0, Vector3(CAP_TOP, CAP_TOP, 0)])
		var warp := func(i: int, q: Vector3, a: float) -> Vector3:
			var r := Vector2(q.x, q.z - sz)
			var k := r.length() / 0.65
			var wav := 1.0 + (0.045 * sin(3.0 * a + 1.0) + 0.025 * sin(7.0 * a + 2.0) + 0.012 * sin(13.0 * a)) * k * k
			return Vector3(r.x * wav, q.y + 0.03 * cos(a + 0.4) * k - (0.02 * sin(5.0 * a) * k * k if i >= 5 else 0.0), sz + r.y * wav)
		var cap := func(i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return Color(0.2, 1.0 if i <= 6 else 0.5, 0.0, 0.0)
		sweep(rings, cap, 26, true, false, Callable(), warp)
		cap_sides = 26
		# Small mushrooms sprouting from the shoulders and the back.
		var spots := [Vector2(-0.24, -0.48), Vector2(0.27, -0.36), Vector2(-0.18, 0.52), Vector2(0.3, 0.3)]
		for gi in spots.size():
			var g: Vector2 = spots[gi]
			var gy := torso_top(g.x, g.y) - 0.01
			var bone := CHEST if g.y < 0.0 else PELVIS
			var hgt := 0.08 + 0.03 * (gi % 2)
			var lean := Vector3(g.x * 0.25, 1.0, 0).normalized()
			var b := Vector3(g.x, gy, g.y)
			var top := b + lean * hgt
			tube([b, b.lerp(top, 0.5), top], [Vector2(0.028, 0.028), Vector2(0.02, 0.02), Vector2(0.018, 0.018)],
				[Vector3(bone, bone, 0), Vector3(bone, bone, 0), Vector3(bone, bone, 0)], stalk, 6, false, false)
			var cr := 0.055 + 0.015 * (gi % 3)
			var gp := [Vector2(0.0, 0.045), Vector2(cr * 0.6, 0.035), Vector2(cr, 0.0), Vector2(cr * 0.8, -0.012), Vector2(0.02, -0.004)]
			var grings := []
			for p: Vector2 in gp:
				grings.append([top + Vector3(0, p.y, 0), Vector3(p.x, 0, 0), Vector3(0, 0, p.x), Vector3(0, 0, p.x), 2.0, Vector3(bone, bone, 0)])
			var gcol := func(i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
				return Color(0.2, 1.0 if i <= 2 else 0.5, 0.0, 0.0)
			sweep(grings, gcol, 10, false, false)
			growths += 1


## One mammoth's rig and its motion.
class Rig:
	var sk: Skeleton3D
	var phase := 0.0
	var t := 0.0
	var gait := Vector3(1, 0, 0)   # (walk, amble)
	var moving := 0.0
	var stride := 0.6
	var rng := RandomNumberGenerator.new()
	var act := "stand"             # (standing about: stand, graze, look, fan, rest, dust)
	var act_t := 0.0
	var look := 0.0
	var look_to := 0.0
	var graze := 0.0
	var graze_t := 0.0
	var fan := 0.1
	var ear_ph := 0.0
	var rest_w := 0.0
	var rest_side := 1.0
	var dust := 0.0
	var dust_t := 0.0
	var trumpet := -1.0            # (its call's time, -1 when not calling)
	var alarm_w := 0.0
	var tail_t := 0.0
	var tail_flick := 0.0
	var cap_a := Vector2.ZERO
	var cap_v := Vector2.ZERO
	var jig := 0.0
	var jig_v := 0.0
	var lift_h := 0.0
	var lift_f := 0.0
	var last_lift := 0.0
	var feet := {}                 # (each foot's ankle now, unit space - the tests read them)
	var _owed := 0.0               # (time not yet posed: a giant's slow motion posed at most 60 times a second)
	const POSE_DT := 1.0 / 60.0

	func _init(s: Skeleton3D, seed: int) -> void:
		sk = s
		rng.seed = seed
		act_t = rng.randf_range(1.0, 4.0)
		phase = rng.randf()
		graze_t = rng.randf() * 5.0
		ear_ph = rng.randf() * TAU

	## (it never leaps)
	func leap_speed() -> float:
		return -1.0

	func leap_height() -> float:
		return 0.0

	## Its call when hurt: the trunk up, the ears spread, the head raised.
	func call_out() -> void:
		trumpet = 0.0

	## One frame: `v` its speed (m/s), `size` its scale (m a unit), `idle` standing about, `alarm` upset (fleeing, charging).
	func step(delta: float, v: float, size: float, idle: bool, alarm: bool) -> void:
		_owed += delta
		if _owed < POSE_DT and not feet.is_empty():
			return
		delta = minf(_owed, 0.2)
		_owed = 0.0
		t += delta
		var vu := v / maxf(size, 0.05)
		var k := 1.0 - exp(-delta * 3.0)
		var amb := smoothstep(0.4, 0.55, vu)
		gait = gait.lerp(Vector3(1.0 - amb, amb, 0.0), k)
		moving = lerpf(moving, clampf(vu / 0.08, 0.0, 1.0), 1.0 - exp(-delta * 2.0))
		stride = lerpf(stride, clampf(0.4 + vu * 1.0, 0.45, 1.2), k)
		phase = fmod(phase + delta * vu / stride, 1.0)
		# Standing about: its acts.
		if idle and vu < 0.04:
			act_t -= delta
			if act_t <= 0.0:
				var r := rng.randf()
				act = "graze" if r < 0.45 else ("look" if r < 0.58 else ("fan" if r < 0.73 else ("rest" if r < 0.86 else ("dust" if r < 0.95 else "stand"))))
				act_t = rng.randf_range(7.0, 14.0) if act == "graze" else rng.randf_range(3.5, 7.0)
				look_to = rng.randf_range(-0.7, 0.7)
				rest_side = -1.0 if rng.randf() < 0.5 else 1.0
				if act == "dust":
					dust_t = 0.0
					act_t = 3.2
		elif not idle:
			act = "walk"
		if act == "look" and rng.randf() < delta * 0.5:
			look_to = rng.randf_range(-0.7, 0.7)
		alarm_w = lerpf(alarm_w, 1.0 if alarm else 0.0, k)
		var slow_walk := (1.0 - smoothstep(0.1, 0.2, vu)) * smoothstep(0.02, 0.06, vu)   # (ambling along, feeling the ground)
		graze = lerpf(graze, (1.0 if act == "graze" else slow_walk * 0.6) * (1.0 - alarm_w), 1.0 - exp(-delta * 1.5))
		graze_t += delta
		look = lerpf(look, look_to if act == "look" else 0.0, 1.0 - exp(-delta * 1.5))
		rest_w = lerpf(rest_w, 1.0 if act == "rest" else 0.0, 1.0 - exp(-delta * 1.8))
		dust_t += delta
		dust = lerpf(dust, 1.0 if act == "dust" and dust_t < 2.4 else 0.0, 1.0 - exp(-delta * (2.0 if act == "dust" and dust_t < 2.4 else 6.0)))
		if trumpet >= 0.0:
			trumpet += delta
			if trumpet > 3.0:
				trumpet = -1.0
		# The ears: fanning slowly (more when it's fanning itself), spread when upset.
		var fan_to := 1.0 if act == "fan" else (0.35 if idle else 0.2)
		fan = lerpf(fan, fan_to, 1.0 - exp(-delta * 1.0))
		ear_ph += delta * TAU * (0.55 if act == "fan" else 0.3)
		# The tail: swishing, now and then a flick.
		tail_t -= delta
		if tail_t <= 0.0:
			tail_t = rng.randf_range(2.0, 6.0)
			tail_flick = rng.randf_range(-1.0, 1.0)
		tail_flick = lerpf(tail_flick, 0.0, 1.0 - exp(-delta * 2.5))
		_pose(delta)

	func _q(x: float, y := 0.0, z := 0.0) -> Quaternion:
		return Quaternion.from_euler(Vector3(x, y, z))

	func _rot(b: int, x: float, y := 0.0, z := 0.0) -> void:
		sk.set_bone_pose_rotation(b, _q(x, y, z))

	## A leg's foot at its cycle point `p`: [ankle offset (y lift, z), the foot's pitch, in stance].
	func _foot(p: float, front: bool) -> Array:
		var duty := lerpf(0.68, 0.52, gait.y)
		var half := stride * duty * 0.5 * moving
		if p < duty:
			return [Vector2(0.0, lerpf(-half, half, p / duty)), 0.0, true]
		var q := (p - duty) / (1.0 - duty)
		var lift := sin(PI * q) * lerpf(0.09, 0.13, gait.y) * moving
		var z := lerpf(half, -half, q * q * (3.0 - 2.0 * q))
		var pitch: float
		if front:   # (the wrist folding back: the sole turned to the rear, then flat again to land)
			pitch = -sin(PI * minf(q * 1.5, 1.0)) * 0.9 * moving
		else:
			pitch = (-sin(PI * minf(q * 1.8, 1.0)) * 0.45 + smoothstep(0.6, 0.9, q) * (1.0 - smoothstep(0.9, 1.0, q)) * 0.15) * moving
		return [Vector2(lift, z), pitch, false]

	## Two-bone IK: the leg from bone `up` reaching its ankle to `target` (skeleton
	## space), the knee or elbow bent toward `pole`, the foot turned to `pitch`.
	func _ik(up: int, parent_g: Transform3D, target: Vector3, pole: Vector3, pitch: float) -> void:
		var a_rest: Vector3 = BONES[up][2]
		var b_rest: Vector3 = BONES[up + 1][2]
		var c_rest: Vector3 = BONES[up + 2][2]
		var par_rest: Vector3 = BONES[BONES[up][1]][2]
		var a := parent_g * (a_rest - par_rest)
		var l1 := (b_rest - a_rest).length()
		var l2 := (c_rest - b_rest).length()
		var to := target - a
		var d := clampf(to.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.9995)
		var u := to.normalized()
		var w := (pole - u * pole.dot(u)).normalized()
		var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var b := a + (u * ca + w * sqrt(1.0 - ca * ca)) * l1
		var c := a + u * d
		var r1 := Quaternion((b_rest - a_rest).normalized(), (b - a).normalized())
		var r2 := Quaternion((c_rest - b_rest).normalized(), (c - b).normalized())
		var pq := parent_g.basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(up, pq.inverse() * r1)
		sk.set_bone_pose_rotation(up + 1, r1.inverse() * r2)
		sk.set_bone_pose_rotation(up + 2, r2.inverse() * _q(pitch))
		feet[up] = c

	## How high a hip can stand over a foot `dz` before or behind it (unit space; 0 at rest).
	func _reach(up: int, dz: float, lift: float) -> float:
		var a: Vector3 = BONES[up][2]
		var l := (((BONES[up + 1][2] as Vector3) - a).length() + ((BONES[up + 2][2] as Vector3) - (BONES[up + 1][2] as Vector3)).length()) * 0.985
		var rest_h := a.y - ANKLE_Y
		var dzr := dz + ((BONES[up + 2][2] as Vector3).z - a.z)
		return sqrt(maxf(l * l - dzr * dzr, 0.0)) - rest_h + lift

	func _pose(delta: float) -> void:
		var cyc := phase * TAU
		var lat := lerpf(0.25, 0.2, gait.y)   # (each fore foot this far behind its hind in the cycle)
		var offs := [[FL_UP, 1.0 - lat, true], [FR_UP, 0.5 - lat, true], [HL_UP, 0.0, false], [HR_UP, 0.5, false]]
		var fl := {}
		var hmin := 0.05
		var fmin := 0.05
		for l in offs:
			var up: int = l[0]
			var f: Array = _foot(fmod(phase + float(l[1]) + 1.0, 1.0), l[2])
			if up == (HL_UP if rest_side < 0.0 else HR_UP):   # (a hind leg rested: the foot drawn back onto its toe)
				f[0] = (f[0] as Vector2) + Vector2(0.05, 0.12) * rest_w
				f[1] = float(f[1]) - 0.45 * rest_w
			fl[up] = f
			var off: Vector2 = f[0]
			if f[2] or off.x < 0.02:
				var r := _reach(up, off.y, off.x)
				if l[2]:
					fmin = minf(fmin, r)
				else:
					hmin = minf(hmin, r)
		# The body: riding over its stance legs (rising and sinking), swaying side to side.
		var bob_h := minf(hmin, 0.0)
		var bob_f := minf(fmin, 0.0)
		var kk := 1.0 - exp(-delta * 10.0)
		# (eased - but never higher than its stance legs reach: down at once)
		lift_h = minf(lerpf(lift_h, bob_h - rest_w * 0.02 - graze * 0.015, kk), bob_h)
		lift_f = minf(lerpf(lift_f, bob_f - graze * 0.04, kk), bob_f)
		var breathe := sin(t * 1.1) * 0.004
		var roll := sin(cyc + 0.4) * 0.03 * moving + rest_w * rest_side * 0.025
		var shift := sin(cyc + 0.4) * 0.025 * moving + rest_w * rest_side * -0.02
		var yaw := sin(cyc) * 0.025 * moving
		var span := 0.95   # (pelvis to the shoulders)
		var pitch := asin(clampf((lift_f - lift_h) / span, -0.5, 0.5))
		var ppos: Vector3 = (BONES[PELVIS][2] as Vector3) + Vector3(shift, lift_h + breathe * 0.5, 0)
		var prot := _q(pitch, yaw, roll)
		sk.set_bone_pose_position(PELVIS, ppos)
		sk.set_bone_pose_rotation(PELVIS, prot)
		var crot := _q(breathe - pitch * 0.1, -yaw * 1.4, -roll * 0.5)
		sk.set_bone_pose_rotation(CHEST, crot)
		var pg := Transform3D(Basis(prot), ppos)
		var cg := pg * Transform3D(Basis(crot), (BONES[CHEST][2] as Vector3) - (BONES[PELVIS][2] as Vector3))
		# The legs: each foot planted, the knee or elbow bent its way.
		for l in offs:
			var up: int = l[0]
			var f: Array = fl[up]
			var off: Vector2 = f[0]
			var rest: Vector3 = BONES[up + 2][2]
			var target := Vector3(rest.x, ANKLE_Y + off.x, rest.z + off.y)
			_ik(up, cg if l[2] else pg, target, Vector3(0, 0, 1) if l[2] else Vector3(0, 0, -1), f[1])
		# Neck and head: nodding with the fore feet, lowered to graze, raised when upset.
		var tr := 0.0
		if trumpet >= 0.0:
			tr = smoothstep(0.0, 0.4, trumpet) * (1.0 - smoothstep(2.2, 3.0, trumpet))
		var nod := sin(cyc * 2.0 - 0.8) * 0.035 * moving
		var neck_x := nod - graze * 0.24 + alarm_w * 0.1 + tr * 0.22 + dust * 0.08 - pitch * 0.7
		_rot(NECK, neck_x, look * 0.35 + sin(cyc) * 0.03 * moving, -roll * 0.4)
		_rot(HEAD, -graze * 0.08 + tr * 0.12, look * 0.25)
		# Chewing after each mouthful.
		var gc := fmod(graze_t / 5.0, 1.0)
		var chew := graze * (smoothstep(0.72, 0.78, gc) + (1.0 - smoothstep(0.12, 0.2, gc))) * clampf(1.0 - (smoothstep(0.2, 0.25, gc) - smoothstep(0.7, 0.72, gc)), 0.0, 1.0)
		_rot(JAW, maxf(sin(t * 7.0), 0.0) * 0.12 * chew + tr * -0.2)
		# The ears: a slow fan (a wave rolling out to the edge), spread wide when upset.
		var spread := maxf(alarm_w, tr)
		var fanning := fan * (0.5 - 0.5 * cos(ear_ph)) * (1.0 - spread)
		var flap := sin(cyc * 2.0) * 0.05 * moving
		for s in [-1.0, 1.0]:
			var e1 := EAR_L if s < 0 else EAR_R
			var o := 0.06 + fanning * 0.85 + spread * 1.0 + flap
			var o2 := fanning * 0.35 + sin(ear_ph - 1.3) * 0.12 * fan * (1.0 - spread) + spread * 0.2
			_rot(e1, -spread * 0.15, s * o, s * spread * -0.1)
			_rot(e1 + 1, 0.0, s * o2, 0.0)
		# The trunk: swinging with its stride; grazing, feeling over the ground and
		# curling a mouthful up to its mouth; thrown up over its back for dust; raised to call.
		var reach_w := graze * smoothstep(0.0, 0.12, gc) * (1.0 - smoothstep(0.5, 0.6, gc))
		var mouth_w := graze * smoothstep(0.55, 0.65, gc) * (1.0 - smoothstep(0.78, 0.92, gc))
		var sweep_s := sin(graze_t * 1.1) * 0.6
		var reach_x := [0.06, 0.08, 0.12, 0.22, 0.42, 0.7]
		var mouth_x := [-0.12, -0.4, -0.62, -0.7, -0.6, -0.45]
		var dust_x := [0.45, 0.62, 0.72, 0.72, 0.62, 0.5]
		var call_x := [0.4, 0.5, 0.5, 0.4, 0.3, 0.2]
		var up_x := [0.12, 0.15, 0.15, 0.12, 0.1, 0.08]
		for i in 6:
			var x := sin(cyc * 2.0 - 0.6 - i * 0.5) * 0.05 * moving + sin(t * 0.5 - i * 0.4) * 0.03
			x += reach_x[i] * reach_w + mouth_x[i] * mouth_w + dust_x[i] * dust + call_x[i] * tr + up_x[i] * alarm_w * (1.0 - tr)
			x -= neck_x * (0.35 if i == 0 else 0.0)   # (hanging, not swung by the head)
			var z := sin(cyc - 0.5 - i * 0.45) * 0.07 * moving + sin(t * 0.37 - i * 0.5) * 0.04 * (1.0 - moving)
			z += sweep_s * 0.06 * reach_w * (1.0 if i > 2 else 0.4)
			var curl := sin(t * 1.7 + i) * 0.04 * reach_w
			_rot(TRUNK0 + i, x + curl, z * 0.3, z)
		# The tail: swishing at the flies, swinging with the stride; up when upset.
		var sw := sin(t * 1.4) * 0.22 * (1.0 - moving * 0.5) + sin(cyc) * 0.12 * moving + tail_flick * 0.5
		_rot(TAIL0, -alarm_w * 0.9 - pitch * 0.5, 0.0, sw)
		_rot(TAIL1, -alarm_w * 0.3, 0.0, sin(t * 1.4 - 0.8) * 0.18 + tail_flick * 0.4)
		# The cap: on its stalk, lagging the body's sway and bounce - a heavy, soft jiggle.
		var dl := (lift_h - last_lift) / maxf(delta, 1e-4)
		last_lift = lift_h
		var cap_to := Vector2(-pitch * 0.8 - clampf(dl, -1.0, 1.0) * 0.06, -roll * 1.6)
		var dt := minf(delta, 0.05)
		for _n in ceili(delta / maxf(dt, 1e-4)):
			cap_v += ((cap_to - cap_a) * 45.0 - cap_v * 4.0) * dt
			cap_a += cap_v * dt
			jig_v += ((-clampf(dl, -1.0, 1.0) * 0.08 - jig) * 70.0 - jig_v * 5.0) * dt
			jig += jig_v * dt
		cap_a = cap_a.clamp(Vector2(-0.25, -0.25), Vector2(0.25, 0.25))
		jig = clampf(jig, -0.06, 0.06)
		_rot(CAP, cap_a.x * 0.6, 0.0, cap_a.y * 0.6)
		_rot(CAP_TOP, cap_a.x * 0.4 + sin(t * 0.7) * 0.01, 0.0, cap_a.y * 0.4)
		sk.set_bone_pose_scale(CAP_TOP, Vector3(1.0 + jig * 0.5, 1.0 - jig, 1.0 + jig * 0.5))
