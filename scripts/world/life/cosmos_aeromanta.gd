class_name CosmosAeromanta
extends RefCounted
## The aeromanta (CosmosFauna "aeromanta", kind "model": "aeromanta") - a manta
## ray of the sky, its own model, not the generic flyer: one shared mesh of one
## surface (one draw call), made on a worker like the dragonfly's:
##  - the disc: a broad diamond that IS the wings - a closed loft across the span,
##    each station an airfoil (blunt rounded leading edge, thick over the body,
##    thinning to the falcate tips; the back domed, the belly flatter), its
##    leading edges curved and swept back, its trailing edge concave;
##  - the cephalic fins (two scrolled lobes forward of the wide mouth), eyes at the
##    head's sides, a small dorsal fin, the pelvic fins either side of the tail's
##    root, the long thin whip tail (UV2.x: how far along it, 0 off it).
## COLOR: g the eyes, b the cephalic and pelvic fins. The skin, its gill slits, the
## mouth, the back's pale shoulder marks and the belly's spots are the shader's
## (aeromanta.gdshader), which also moves it: waves travelling from the body out
## to the tips (`phase`, `wave`), the tail rippling and trailing a turn (`bend`).
## Unit space: CosmosCreature scales it by the species' size; forward is -z.

const SHADER := preload("res://shaders/world/aeromanta.gdshader")
const SPAN := 1.45          # (half the wingspan)
const TAIL := 1.9           # (the whip tail's length)

static var _mesh: ArrayMesh
static var _task := -1
static var _built: Builder
## What the last build made (the tests read it).
static var made := {}


static func start() -> void:
	if _mesh != null or _task >= 0:
		return
	_built = Builder.new()
	_task = WorkerThreadPool.add_task(_built.run, false, "aeromanta mesh")


static func is_ready() -> bool:
	return _mesh != null or (_task >= 0 and WorkerThreadPool.is_task_completed(_task))


static func mesh() -> ArrayMesh:
	if _mesh == null:
		start()
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _built.body.arrays())
		m.custom_aabb = AABB(Vector3(-SPAN - 0.2, -0.6, -1.0), Vector3(SPAN * 2.0 + 0.4, 1.2, TAIL + 1.8))   # (the waves and the tail inside)
		made = {"stations": _built.stations, "tail_rings": _built.tail_rings, "fins": _built.fins, "eyes": _built.eyes, "build_ms": _built.ms}
		_built = null
		_mesh = m
	return _mesh


## Its own material (its hit flash, its waves).
static func material(c1: Color, c2: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("c1", c1)
	m.set_shader_parameter("c2", c2)
	m.set_shader_parameter("span", SPAN)
	m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	return m


## The disc's leading and trailing edges at `a` (0 the middle .. 1 the tip), z.
static func edges(a: float) -> Vector2:
	var lead := -0.56 + 0.86 * pow(a, 1.55) - 0.07 * sin(PI * pow(a, 0.7))
	var trail := lerpf(0.5, 0.3, a) - 0.2 * sin(PI * pow(a, 0.75)) * (1.0 - 0.2 * a)
	if a < 0.1:   # (the wide mouth: the head's front squared off)
		lead = lerpf(-0.53, lead, smoothstep(0.0, 0.1, a))
	return Vector2(lead, maxf(trail, lead + 0.004))


## The disc's half thickness at `a`: the body's dome in the middle, the wings thin.
static func thick(a: float) -> float:
	return 0.022 * (1.0 - a) * (1.0 - a * 0.6) + 0.12 * exp(-pow(a / 0.2, 2.0))


class Builder extends CosmosDragonfly.Builder:
	var stations := 0
	var tail_rings := 0
	var fins := 0
	var eyes := 0

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		_disc()
		_head()
		_fins()
		_tail()
		ms = (Time.get_ticks_usec() - t0) / 1000.0

	## The disc: rings across the span (x), each a closed airfoil in y-z.
	func _disc() -> void:
		var p := body
		var n := 48
		var sides := 32
		var base := p.v.size()
		var plain := Color(0, 0, 0)
		for i in n + 1:
			var u := float(i) / n * 2.0 - 1.0
			u = signf(u) * pow(absf(u), 1.35)   # (stations crowded at the body)
			var a := absf(u)
			var e := CosmosAeromanta.edges(a)
			var h := CosmosAeromanta.thick(a)
			var droop := -0.05 * a * a   # (the wings' tips a little down at rest)
			for j in sides + 1:
				var th := TAU * j / sides
				var c := (1.0 - cos(th)) * 0.5
				var z := lerpf(e.x, e.y, c)
				var s := sin(th)
				var prof := (1.0 - 0.55 * c) * (1.0 + 0.4 * (1.0 - c) * exp(-pow(a / 0.12, 2.0)))   # (thickest forward; the head's front rounded)
				var y := s * h * prof * (1.0 if s > 0.0 else 0.5) + droop
				p.add(Vector3(u * CosmosAeromanta.SPAN, y, z), plain, Vector2(u, c), Vector2.ZERO)
			stations += 1
		for i in n:
			for j in sides:
				var a := base + i * (sides + 1) + j
				var b := a + sides + 1
				p.tri(a, a + 1, b)
				p.tri(a + 1, b + 1, b)

	func _head() -> void:
		var eye := Color(0, 1, 0)
		# Eyes at the head's sides, just behind the cephalic fins.
		for side in [-1.0, 1.0]:
			blob(Vector3(side * 0.2, 0.028, -0.53), Vector3(0.028, 0.026, 0.032), Vector3.BACK, eye, 8, 12, 0.0, Vector2(0, 0))
			eyes += 1

	func _fins() -> void:
		var fin := Color(0, 0, 1)
		var z0 := Vector2(0, 0)
		for side in [-1.0, 1.0]:
			# The cephalic fins: flat lobes forward of the mouth, scrolled inward.
			var b := Vector3(side * 0.13, 0.0, -0.5)
			loft([b, b + Vector3(side * 0.012, -0.004, -0.06), b + Vector3(side * 0.004, -0.012, -0.13), b + Vector3(-side * 0.012, -0.02, -0.19), b + Vector3(-side * 0.022, -0.022, -0.215)],
				[Vector2(0.014, 0.04), Vector2(0.012, 0.042), Vector2(0.01, 0.036), Vector2(0.008, 0.024), Vector2(0.002, 0.004)],
				[fin, fin, fin, fin, fin], [z0, z0, z0, z0, z0], 10)
			# The pelvic fins: small flaps either side of the tail's root.
			var q := Vector3(side * 0.06, -0.025, 0.36)
			loft([q, q + Vector3(side * 0.03, -0.004, 0.06), q + Vector3(side * 0.035, -0.006, 0.13)],
				[Vector2(0.035, 0.012), Vector2(0.03, 0.009), Vector2(0.004, 0.002)], [fin, fin, fin], [z0, z0, z0], 8)
			fins += 2
		# A small dorsal fin on the back, before the tail.
		var d := Vector3(0, 0.05, 0.4)
		loft([d, d + Vector3(0, 0.035, 0.035), d + Vector3(0, 0.05, 0.08)],
			[Vector2(0.006, 0.03), Vector2(0.004, 0.018), Vector2(0.001, 0.002)], [fin, fin, fin], [z0, z0, z0], 8)
		fins += 1

	## The whip tail: long and thin, UV2.x along it (the shader ripples it).
	func _tail() -> void:
		var pts := []
		var rad := []
		var cols := []
		var uvs := []
		var n := 28
		var start := Vector3(0, 0.0, 0.3)
		for i in n + 1:
			var t := float(i) / n
			pts.append(start + Vector3(0, 0.03 * t, t * CosmosAeromanta.TAIL))
			var r := lerpf(0.04, 0.003, pow(t, 0.55))
			rad.append(Vector2(r, r * 0.9))
			cols.append(Color(0, 0, 0))
			uvs.append(Vector2(0, 0))
			tail_rings += 1
		# (the loft writes UV2 only for facets: set the tail's along-ness after)
		var from := body.v.size()
		loft(pts, rad, cols, uvs, 8)
		for i in range(from, body.v.size()):
			var t := clampf((body.v[i].z - start.z) / CosmosAeromanta.TAIL, 0.0, 1.0)
			body.uv2[i] = Vector2(maxf(t, 0.002), 0.0)
