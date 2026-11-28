class_name CosmosFox
extends RefCounted
## The red fox (CosmosFauna "fox", kind "model": "fox") - its own model and
## motion, not the generic canine: one shared skinned mesh (one surface, one
## draw call; made on a worker like the dragonfly's) over a 26-bone rig each fox
## builds for itself (Rig):
##  - a lean body (deep chest, tucked waist), a neck with a white throat, the
##    head: a narrow skull, a long pointed muzzle (its lower half and the chin
##    white), a black nose, whiskers, amber eyes with slit pupils, big upright
##    triangular ears with black backs; slender legs in black stockings on small
##    paws; a big bushy tail with a white tip;
##  - the coat (fox.gdshader): soft wrapped light, fur strands along each part
##    (UV: round, along), a rim of light, the colours from COLOR (r white,
##    g black, b eye; a: an eye's depth to its pupil, 0.5 the glossy nose).
## Rig.step() moves it: a 4-beat walk, the trot (diagonal pairs - its main gait),
## a gallop when it flees, chosen and blended by speed; standing about it looks
## round, flicks its ears, sways its tail, sniffs the ground, sits, and now and
## then leaps in its high mousing pounce. Unit space (y up from the ground,
## forward -z); CosmosCreature scales it by the species' size.

const SHADER := preload("res://shaders/world/fox.gdshader")

## The bones: [name, parent, rest position (unit space, global)].
const BONES := [
	["pelvis", -1, Vector3(0, 0.76, 0.3)],
	["chest", 0, Vector3(0, 0.76, -0.3)],
	["neck", 1, Vector3(0, 0.82, -0.5)],
	["head", 2, Vector3(0, 1.0, -0.72)],
	["ear_l", 3, Vector3(-0.07, 1.1, -0.78)],
	["ear_r", 3, Vector3(0.07, 1.1, -0.78)],
	["tail0", 0, Vector3(0, 0.8, 0.62)],
	["tail1", 6, Vector3(0, 0.72, 0.84)],
	["tail2", 7, Vector3(0, 0.58, 1.04)],
	["tail3", 8, Vector3(0, 0.44, 1.18)],
	["fl_up", 1, Vector3(-0.1, 0.72, -0.4)],
	["fl_low", 10, Vector3(-0.1, 0.42, -0.36)],
	["fl_wrist", 11, Vector3(-0.1, 0.1, -0.38)],
	["fl_paw", 12, Vector3(-0.1, 0.035, -0.39)],
	["fr_up", 1, Vector3(0.1, 0.72, -0.4)],
	["fr_low", 14, Vector3(0.1, 0.42, -0.36)],
	["fr_wrist", 15, Vector3(0.1, 0.1, -0.38)],
	["fr_paw", 16, Vector3(0.1, 0.035, -0.39)],
	["hl_hip", 0, Vector3(-0.11, 0.75, 0.42)],
	["hl_stifle", 18, Vector3(-0.11, 0.44, 0.28)],
	["hl_hock", 19, Vector3(-0.11, 0.22, 0.48)],
	["hl_paw", 20, Vector3(-0.11, 0.04, 0.45)],
	["hr_hip", 0, Vector3(0.11, 0.75, 0.42)],
	["hr_stifle", 22, Vector3(0.11, 0.44, 0.28)],
	["hr_hock", 23, Vector3(0.11, 0.22, 0.48)],
	["hr_paw", 24, Vector3(0.11, 0.04, 0.45)],
]
enum { PELVIS, CHEST, NECK, HEAD, EAR_L, EAR_R, TAIL0, TAIL1, TAIL2, TAIL3,
	FL_UP, FL_LOW, FL_WRIST, FL_PAW, FR_UP, FR_LOW, FR_WRIST, FR_PAW,
	HL_HIP, HL_STIFLE, HL_HOCK, HL_PAW, HR_HIP, HR_STIFLE, HR_HOCK, HR_PAW }

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
	_task = WorkerThreadPool.add_task(_built.run, false, "fox mesh")


static func is_ready() -> bool:
	return _mesh != null or (_task >= 0 and WorkerThreadPool.is_task_completed(_task))


static func mesh() -> ArrayMesh:
	if _mesh == null:
		start()
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var m := ArrayMesh.new()
		var body: Array = _built.body.arrays()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body)
		LodKit.later(m, [body])   # (its levels of detail - LodKit)
		m.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.8), Vector3(2.4, 3.2, 3.8))   # (leaping, sitting, its tail streaming)
		made = {"legs": _built.legs, "ears": _built.ears, "eyes": _built.eyes, "whiskers": _built.whiskers, "tail_rings": _built.tail_rings, "build_ms": _built.ms}
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


## A fox's skeleton (its bones at rest).
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


## A fox's Rig on its skeleton (CosmosCreature makes one through this - as it does a mammoth's).
static func rig(sk: Skeleton3D, seed: int) -> Rig:
	return Rig.new(sk, seed)


## The mesh's vertices with their bones and weights.
class FoxPart extends CosmosDragonfly.Part:
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()

	func arrays() -> Array:
		var arr := super()
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		return arr


class Builder:
	var body := FoxPart.new()
	var legs := 0
	var ears := 0
	var eyes := 0
	var whiskers := 0
	var tail_rings := 0
	var ms := 0.0

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		_torso()
		_neck_head()
		_legs()
		_tail()
		ms = (Time.get_ticks_usec() - t0) / 1000.0

	func _vert(q: Vector3, c: Color, uv: Vector2, sk: Vector3) -> int:
		var i := body.add(q, c, uv, Vector2.ZERO)
		var w := clampf(sk.z, 0.0, 1.0)
		if int(sk.x) == int(sk.y):
			w = 0.0
		body.bones.append_array([int(sk.x), int(sk.y), 0, 0])
		body.weights.append_array([1.0 - w, w, 0.0, 0.0])
		return i

	## A tube through `pts` (ellipse radii `rad`: x across, y up), its rings
	## bound to bones `sk` (Vector3(bone a, bone b, weight of b)), each vertex's
	## colour from `col` (ring, outward direction, position, along 0..1).
	func loft(pts: Array, rad: Array, sk: Array, col: Callable, sides: int, close_start := true, close_end := true) -> void:
		var n := pts.size()
		var base := body.v.size()
		var t0: Vector3 = (pts[1] - pts[0]).normalized()
		var up := Vector3.UP if absf(t0.y) < 0.9 else Vector3.BACK
		up = (up - t0 * up.dot(t0)).normalized()
		var total := 0.0
		for i in range(1, n):
			total += (pts[i] - pts[i - 1]).length()
		var along := 0.0
		for i in n:
			var t: Vector3
			if i == 0:
				t = t0
			elif i == n - 1:
				t = (pts[i] - pts[i - 1]).normalized()
			else:
				t = (pts[i + 1] - pts[i - 1]).normalized()
			up = (up - t * up.dot(t)).normalized()
			var side := up.cross(t).normalized()
			if i > 0:
				along += (pts[i] - pts[i - 1]).length()
			var r: Vector2 = rad[i]
			for j in sides + 1:
				var a := TAU * j / sides
				var dir := side * cos(a) + up * sin(a)
				var q: Vector3 = pts[i] + side * cos(a) * r.x + up * sin(a) * r.y
				_vert(q, col.call(i, dir, q, along / maxf(total, 1e-5)), Vector2(float(j) / sides, along), sk[i])
		for i in n - 1:
			for j in sides:
				var a := base + i * (sides + 1) + j
				var b := a + sides + 1
				body.tri(a, a + 1, b)
				body.tri(a + 1, b + 1, b)
		for e in [0, n - 1]:
			if (e == 0 and not close_start) or (e == n - 1 and not close_end):
				continue
			var r2: Vector2 = rad[e]
			if r2.length() < 1e-5:
				continue
			var ring: int = base + e * (sides + 1)
			var c := _vert(pts[e], body.col[ring], Vector2(0.5, along if e > 0 else 0.0), sk[e])
			for j in sides:
				if e == 0:
					body.tri(c, ring + j + 1, ring + j)
				else:
					body.tri(c, ring + j, ring + j + 1)

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
		loft(pts, rad, sk, col, sides)

	static func coat(white := 0.0, black := 0.0) -> Color:
		return Color(white, black, 0.0, 1.0)

	func _torso() -> void:
		# From the rump to the chest: deep chest, tucked waist; the belly and chest white.
		var zs := [0.7, 0.62, 0.48, 0.3, 0.1, -0.1, -0.3, -0.45, -0.56, -0.62]
		var ys := [0.76, 0.76, 0.76, 0.75, 0.75, 0.75, 0.72, 0.72, 0.75, 0.78]
		var rs := [Vector2(0.03, 0.03), Vector2(0.11, 0.11), Vector2(0.15, 0.15), Vector2(0.15, 0.16), Vector2(0.125, 0.13),
			Vector2(0.135, 0.17), Vector2(0.15, 0.21), Vector2(0.14, 0.2), Vector2(0.11, 0.15), Vector2(0.05, 0.07)]
		var pts := []
		var sk := []
		for i in zs.size():
			pts.append(Vector3(0, ys[i], zs[i]))
			sk.append(Vector3(PELVIS, CHEST, smoothstep(0.35, -0.35, zs[i])))
		var col := func(_i: int, dir: Vector3, q: Vector3, _f: float) -> Color:
			var belly := smoothstep(-0.35, -0.75, dir.y)
			var chest := smoothstep(-0.35, -0.6, q.z) * smoothstep(0.0, -0.5, dir.y)
			return coat(maxf(belly * 0.85, chest))
		loft(pts, rs, sk, col, 26)

	func _neck_head() -> void:
		# The neck: chest to head, its throat white.
		var npts := [Vector3(0, 0.79, -0.5), Vector3(0, 0.86, -0.6), Vector3(0, 0.94, -0.68), Vector3(0, 1.0, -0.75)]
		var nr := [Vector2(0.11, 0.14), Vector2(0.1, 0.125), Vector2(0.09, 0.105), Vector2(0.08, 0.085)]
		var nsk := [Vector3(CHEST, NECK, 0.3), Vector3(CHEST, NECK, 0.9), Vector3(NECK, HEAD, 0.4), Vector3(NECK, HEAD, 1.0)]
		var throat := func(_i: int, dir: Vector3, _q: Vector3, _f: float) -> Color:
			return coat(smoothstep(-0.1, -0.5, dir.y))
		loft(npts, nr, nsk, throat, 20)
		var head := func(_i: int, dir: Vector3, q: Vector3, _f: float) -> Color:   # (the cheeks and chin white)
			return coat(smoothstep(0.0, -0.5, dir.y) * smoothstep(-0.8, -0.86, q.z))
		# The skull, and cheek ruffs either side.
		blob(Vector3(0, 1.04, -0.8), Vector3(0.1, 0.088, 0.105), Vector3.BACK, HEAD, head, 10, 16)
		for side in [-1.0, 1.0]:
			var ruff := func(_i: int, dir: Vector3, _q: Vector3, _f: float) -> Color:
				return coat(smoothstep(0.1, -0.4, dir.y))
			blob(Vector3(side * 0.07, 0.99, -0.79), Vector3(0.06, 0.055, 0.07), Vector3.BACK, HEAD, ruff, 6, 10)
		# The muzzle: long, narrow, pointed; the lower jaw white.
		var mpts := [Vector3(0, 1.025, -0.85), Vector3(0, 1.008, -0.92), Vector3(0, 0.995, -0.98), Vector3(0, 0.985, -1.03), Vector3(0, 0.98, -1.065)]
		var mr := [Vector2(0.07, 0.066), Vector2(0.054, 0.05), Vector2(0.04, 0.038), Vector2(0.028, 0.028), Vector2(0.017, 0.019)]
		var msk := [Vector3(HEAD, HEAD, 0), Vector3(HEAD, HEAD, 0), Vector3(HEAD, HEAD, 0), Vector3(HEAD, HEAD, 0), Vector3(HEAD, HEAD, 0)]
		var muzzle := func(_i: int, dir: Vector3, _q: Vector3, f: float) -> Color:
			return coat(smoothstep(0.05, -0.35, dir.y), smoothstep(0.85, 1.0, f) * smoothstep(-0.2, 0.3, dir.y) * 0.6)
		loft(mpts, mr, msk, muzzle, 14)
		# The black nose, glossy.
		var nose := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return Color(0, 1, 0, 0.5)
		blob(Vector3(0, 0.985, -1.07), Vector3(0.021, 0.017, 0.016), Vector3.BACK, HEAD, nose, 5, 10)
		# Amber eyes looking forward and out (COLOR.a: how far toward the pupil).
		for side in [-1.0, 1.0]:
			var eye := func(i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
				return Color(0, 0, 1, float(i) / 6.0)
			blob(Vector3(side * 0.047, 1.062, -0.875), Vector3(0.016, 0.014, 0.016), Vector3(side * 0.5, 0.05, -1.0), HEAD, eye, 6, 12)
			eyes += 1
		# Whiskers: three a side, fine and pale.
		var pale := func(_i: int, _d: Vector3, _q: Vector3, _f: float) -> Color:
			return coat(0.9)
		for side in [-1.0, 1.0]:
			for w in 3:
				var a := Vector3(side * 0.03, 0.99 - w * 0.008, -0.99 + w * 0.01)
				var b := a + Vector3(side * 0.1, 0.01 - w * 0.02, 0.05)
				loft([a, a.lerp(b, 0.5), b], [Vector2(0.0022, 0.0022), Vector2(0.0015, 0.0015), Vector2(0.0004, 0.0004)],
					[Vector3(HEAD, HEAD, 0), Vector3(HEAD, HEAD, 0), Vector3(HEAD, HEAD, 0)], pale, 4)
				whiskers += 1
		# Big upright ears: thin triangles, black backs and tips, pale insides.
		for side in [-1.0, 1.0]:
			var bone := EAR_L if side < 0 else EAR_R
			var b0 := Vector3(side * 0.07, 1.08, -0.78)
			var tip := Vector3(side * 0.115, 1.25, -0.765)
			var ear := func(_i: int, dir: Vector3, _q: Vector3, f: float) -> Color:
				var back := smoothstep(-0.1, 0.3, dir.z)
				return coat(smoothstep(0.0, -0.4, dir.z) * 0.8 * (1.0 - f), maxf(back * 0.85, smoothstep(0.7, 0.85, f)))
			loft([b0, b0.lerp(tip, 0.35), b0.lerp(tip, 0.7), tip], [Vector2(0.068, 0.018), Vector2(0.055, 0.015), Vector2(0.032, 0.01), Vector2(0.002, 0.002)],
				[Vector3(bone, bone, 0), Vector3(bone, bone, 0), Vector3(bone, bone, 0), Vector3(bone, bone, 0)], ear, 10)
			ears += 1

	## Slender legs: the fronts with upper arm, forearm, wrist and paw; the hinds
	## with a muscled thigh, shin, hock and paw - black stockings below.
	func _legs() -> void:
		var stock := func(_i: int, dir: Vector3, q: Vector3, _f: float) -> Color:
			return coat(0.0, smoothstep(0.4, 0.28, q.y))
		for side in [-1.0, 1.0]:
			var o := 0 if side < 0 else 4
			var b: Array = []
			for k in 4:
				b.append(BONES[FL_UP + o + k][2])
			var top := Vector3(side * 0.065, 0.8, -0.43)
			var toe := Vector3(side * 0.1, 0.018, -0.47)
			loft([top, b[0], b[0].lerp(b[1], 0.5), b[1], b[1].lerp(b[2], 0.5), b[2], b[3], toe],
				[Vector2(0.055, 0.075), Vector2(0.058, 0.07), Vector2(0.045, 0.05), Vector2(0.036, 0.04), Vector2(0.028, 0.03), Vector2(0.022, 0.024), Vector2(0.026, 0.02), Vector2(0.018, 0.012)],
				[Vector3(CHEST, FL_UP + o, 0.6), Vector3(FL_UP + o, FL_UP + o, 0), Vector3(FL_UP + o, FL_UP + o, 0), Vector3(FL_UP + o, FL_LOW + o, 0.5),
				Vector3(FL_LOW + o, FL_LOW + o, 0), Vector3(FL_LOW + o, FL_WRIST + o, 0.5), Vector3(FL_WRIST + o, FL_PAW + o, 0.6), Vector3(FL_PAW + o, FL_PAW + o, 0)],
				stock, 12)
			legs += 1
			var h: Array = []
			for k in 4:
				h.append(BONES[HL_HIP + o + k][2])
			var htop := Vector3(side * 0.05, 0.82, 0.44)
			var htoe := Vector3(side * 0.11, 0.018, 0.38)
			loft([htop, h[0], h[0].lerp(h[1], 0.5), h[1], h[1].lerp(h[2], 0.5), h[2], h[3], htoe],
				[Vector2(0.07, 0.09), Vector2(0.08, 0.105), Vector2(0.06, 0.08), Vector2(0.04, 0.045), Vector2(0.03, 0.035), Vector2(0.024, 0.026), Vector2(0.024, 0.02), Vector2(0.018, 0.012)],
				[Vector3(PELVIS, HL_HIP + o, 0.6), Vector3(HL_HIP + o, HL_HIP + o, 0), Vector3(HL_HIP + o, HL_HIP + o, 0), Vector3(HL_HIP + o, HL_STIFLE + o, 0.5),
				Vector3(HL_STIFLE + o, HL_STIFLE + o, 0), Vector3(HL_STIFLE + o, HL_HOCK + o, 0.5), Vector3(HL_HOCK + o, HL_PAW + o, 0.6), Vector3(HL_PAW + o, HL_PAW + o, 0)],
				stock, 12)
			legs += 1

	## The brush: big and bushy, held low at rest, a white tip.
	func _tail() -> void:
		var pts := []
		var rad := []
		var sk := []
		var chain := [BONES[TAIL0][2], BONES[TAIL1][2], BONES[TAIL2][2], BONES[TAIL3][2], Vector3(0, 0.34, 1.3)]
		var n := 16
		for i in n + 1:
			var f := float(i) / n
			var seg := mini(int(f * 4.0), 3)
			var k := f * 4.0 - seg
			var p: Vector3 = (chain[seg] as Vector3).lerp(chain[seg + 1], k)
			pts.append(p)
			var r := 0.045 + 0.1 * sin(PI * pow(f, 0.6)) + 0.02 * f
			if f > 0.92:
				r *= (1.0 - f) / 0.08 * 0.8 + 0.2
			rad.append(Vector2(r, r * 0.95))
			var b0 := TAIL0 + seg
			var b1 := mini(b0 + 1, TAIL3)
			sk.append(Vector3(b0, b1, smoothstep(0.5, 1.0, k)))
			tail_rings += 1
		var col := func(_i: int, dir: Vector3, _q: Vector3, f: float) -> Color:
			return coat(maxf(smoothstep(0.8, 0.86, f), smoothstep(-0.4, -0.9, dir.y) * 0.4 * (1.0 - f)), smoothstep(0.2, 0.6, dir.y) * 0.25 * (1.0 - f))
		loft(pts, rad, sk, col, 18)


## One fox's rig and its motion.
class Rig:
	var sk: Skeleton3D
	var phase := 0.0
	var t := 0.0
	var act := "stand"            # (standing about: stand, look, sniff, sit, pounce)
	var act_t := 0.0
	var look := 0.0
	var look_to := 0.0
	var ear_t := 1.0
	var ear_flick := Vector2.ZERO
	var crouch := 0.0
	var pounce := -1.0           # (its leap's time, -1 when not leaping)
	var gait := Vector3(1, 0, 0) # (walk, trot, gallop weights)
	var rng := RandomNumberGenerator.new()
	var sit := 0.0
	var sniff := 0.0
	var tail_up := 0.0

	func _init(s: Skeleton3D, seed: int) -> void:
		sk = s
		rng.seed = seed
		act_t = rng.randf_range(1.0, 3.0)
		phase = rng.randf()

	## How fast it moves while leaping (m/s; -1: not leaping).
	func leap_speed() -> float:
		return 2.2 if pounce >= 0.35 and pounce < 1.15 else (0.0 if pounce >= 0.0 else -1.0)

	## The leap's height (unit space) - its body raised by CosmosCreature.
	func leap_height() -> float:
		if pounce < 0.35 or pounce > 1.15:
			return 0.0
		var f := (pounce - 0.35) / 0.8
		return sin(PI * f) * 0.85

	## One frame: `v` its speed (m/s), `size` its scale (m a unit), `idle` standing about, `alarm` fleeing.
	func step(delta: float, v: float, size: float, idle: bool, alarm: bool) -> void:
		t += delta
		# The gait by speed: walk under ~1 m/s, trot to ~3.5, gallop above.
		var vu := v / maxf(size, 0.05)   # (in units a second)
		var want := Vector3(1.0 - smoothstep(1.2, 1.9, vu), 0.0, smoothstep(4.0, 5.5, vu))
		want.y = maxf(0.0, 1.0 - want.x - want.z)
		gait = gait.lerp(want, 1.0 - exp(-delta * 4.0))
		var stride := gait.x * 0.55 + gait.y * 0.95 + gait.z * 1.7
		phase = fmod(phase + delta * maxf(vu / stride, 0.0), 1.0)
		var moving := clampf(vu / 0.5, 0.0, 1.0)
		# Standing about: its acts.
		if idle and v < 0.2 and pounce < 0.0:
			act_t -= delta
			if act_t <= 0.0:
				var r := rng.randf()
				act = "look" if r < 0.35 else ("sniff" if r < 0.6 else ("sit" if r < 0.8 else ("pounce" if r < 0.93 else "stand")))
				act_t = rng.randf_range(2.0, 5.0)
				look_to = rng.randf_range(-0.8, 0.8)
				if act == "pounce":
					pounce = 0.0
		elif not idle:
			act = "stand"
		if pounce >= 0.0:
			pounce += delta
			if pounce > 1.7:
				pounce = -1.0
				act = "sniff"
				act_t = 1.5
		if act == "look" and rng.randf() < delta * 0.8:
			look_to = rng.randf_range(-0.8, 0.8)
		var k := 1.0 - exp(-delta * 4.0)
		look = lerpf(look, look_to if act == "look" else 0.0, 1.0 - exp(-delta * 3.0))
		sit = lerpf(sit, 1.0 if act == "sit" and idle else 0.0, 1.0 - exp(-delta * 3.0))
		sniff = lerpf(sniff, 1.0 if act == "sniff" or (vu < 1.3 and v > 0.1 and not alarm) else 0.0, k)
		tail_up = lerpf(tail_up, gait.z * moving, k)
		# Ear flicks.
		ear_t -= delta
		if ear_t <= 0.0:
			ear_t = rng.randf_range(1.5, 5.0)
			ear_flick = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.5
		ear_flick = ear_flick.lerp(Vector2.ZERO, 1.0 - exp(-delta * 8.0))
		_pose(moving, alarm)

	func _rot(b: int, x: float, y := 0.0, z := 0.0) -> void:
		sk.set_bone_pose_rotation(b, Quaternion.from_euler(Vector3(x, y, z)))

	## A leg's swing at its cycle point `p` (0..1): [upper, lower, wrist, paw] angles.
	func _leg(p: float, front: bool) -> Array:
		var duty := gait.x * 0.62 + gait.y * 0.5 + gait.z * 0.38
		var amp := gait.x * 0.32 + gait.y * 0.45 + gait.z * 0.75
		var lift := gait.x * 0.7 + gait.y * 1.0 + gait.z * 1.3
		var a: float
		var flex := 0.0
		if p < duty:
			a = lerpf(amp, -amp, p / duty)
		else:
			var q := (p - duty) / (1.0 - duty)
			a = lerpf(-amp, amp, smoothstep(0.0, 1.0, q))
			flex = sin(PI * q) * lift
		if front:
			return [a, -flex * 0.9, -flex * 0.5, -flex * 0.6 + (0.25 * amp if p > duty * 0.8 and p < duty else 0.0)]
		return [a * 0.9, flex * 0.7, -flex * 0.9, flex * 0.5]

	func _pose(moving: float, alarm: bool) -> void:
		# Leg phases: walk (lateral sequence), trot (diagonal pairs), gallop (rotary).
		var offs := {
			"fl": gait.x * 0.25 + gait.y * 0.0 + gait.z * 0.45,
			"fr": gait.x * 0.75 + gait.y * 0.5 + gait.z * 0.55,
			"hl": gait.x * 0.0 + gait.y * 0.5 + gait.z * 0.0,
			"hr": gait.x * 0.5 + gait.y * 0.0 + gait.z * 0.1}
		var legs := [["fl", FL_UP, true], ["fr", FR_UP, true], ["hl", HL_HIP, false], ["hr", HR_HIP, false]]
		var pitch := 0.0
		var lift := 0.0
		var spine := 0.0
		var cyc := phase * TAU
		# The body: a trot's light bounce, a gallop's rocking and spine flexing.
		lift += absf(sin(cyc * 2.0)) * 0.025 * gait.y * moving
		lift += sin(cyc) * 0.05 * gait.z * moving
		pitch += sin(cyc + 0.6) * 0.12 * gait.z * moving
		spine = sin(cyc + 1.2) * 0.22 * gait.z * moving
		# Sitting: the rump down, the front up, the hind legs folded under.
		lift -= sit * 0.33
		pitch += sit * 0.55
		# The pounce: crouch, the leap (nose up, then diving), the landing.
		var pf := pounce
		var leap_pose := 0.0
		if pf >= 0.0:
			if pf < 0.35:
				lift -= sin(pf / 0.35 * PI * 0.5) * 0.15
				pitch += -0.08
			elif pf < 1.15:
				var f := (pf - 0.35) / 0.8
				pitch += lerpf(0.55, -0.9, smoothstep(0.1, 0.9, f))
				leap_pose = 1.0
			else:
				var f2 := (pf - 1.15) / 0.55
				pitch += lerpf(-0.5, 0.0, f2)
				lift -= (1.0 - f2) * 0.1
		sk.set_bone_pose_position(PELVIS, (BONES[PELVIS][2] as Vector3) + Vector3(0, lift, 0))
		_rot(PELVIS, pitch)
		_rot(CHEST, spine - sit * 0.25)
		# Legs.
		for l in legs:
			var b: int = l[1]
			var front: bool = l[2]
			var p := fmod(phase + float(offs[l[0]]), 1.0)
			var ang: Array = _leg(p, front)
			for j in 4:
				ang[j] = float(ang[j]) * moving
			if front:
				ang[0] = float(ang[0]) - pitch * (1.0 - leap_pose) - sit * 0.05
				if leap_pose > 0.0:
					ang = [0.9, -0.4, -0.3, -0.3]   # (reaching forward into the dive)
				_rot(b, ang[0])
				_rot(b + 1, ang[1])
				_rot(b + 2, ang[2])
				_rot(b + 3, ang[3])
			else:
				var a0 := float(ang[0]) - pitch * (1.0 - leap_pose)
				var a1 := float(ang[1]) + sit * 1.6
				var a2 := float(ang[2]) - sit * 1.9
				var a3 := float(ang[3]) + sit * 0.3
				if leap_pose > 0.0:
					a0 = -0.9
					a1 = 0.2
					a2 = 0.3
					a3 = 0.3
				_rot(b, a0 + sit * 0.35)
				_rot(b + 1, a1)
				_rot(b + 2, a2)
				_rot(b + 3, a3)
		# Neck and head: level against the body's pitch, looking round, sniffing low.
		var bob := sin(cyc * 2.0) * 0.05 * gait.y * moving
		var level := 1.0 - leap_pose * 0.8   # (in the dive its head goes down with it)
		_rot(NECK, -sniff * 1.35 - pitch * 0.5 * level + sit * 0.1 + bob + gait.z * moving * -0.15, look * 0.6)
		_rot(HEAD, sniff * 0.45 - pitch * 0.4 * level, look * 0.5)
		# Ears: pricked, flicking; laid back when it flees.
		var back := -0.6 if alarm else 0.0
		_rot(EAR_L, back + ear_flick.x, 0.0, ear_flick.y * 0.6)
		_rot(EAR_R, back - ear_flick.y * 0.6, 0.0, -ear_flick.x * 0.6)
		# The tail: hanging low and swaying at rest, streaming out behind when running.
		var sway := sin(t * 1.3) * 0.12 * (1.0 - moving * 0.6) + sin(cyc) * 0.1 * moving
		var up := -0.35 * tail_up - 0.15 * gait.y * moving - sit * -0.2
		_rot(TAIL0, up - 0.1 + pitch * -0.3, sway)
		_rot(TAIL1, up * 0.8 + sin(t * 1.3 - 0.6) * 0.03, sway * 1.2)
		_rot(TAIL2, up * 0.6, sway * 1.3 + sin(t * 1.3 - 1.2) * 0.05)
		_rot(TAIL3, up * 0.4 + sit * 0.2, sway * 1.4)
