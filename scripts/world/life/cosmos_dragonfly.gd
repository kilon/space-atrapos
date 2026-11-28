class_name CosmosDragonfly
extends RefCounted
## The dragonfly (CosmosFauna "dragonfly", kind "model": "dragonfly") - its own
## model, not the generic flyer: a true Anisoptera at the species' size, in one
## shared mesh of two surfaces (one draw call each, every dragonfly the same mesh):
##  - the body: a head that is mostly two wrap-around compound eyes (their facets
##    drawn by the shader from UV2), a face, short antennae; a robust slanted
##    thorax; six thin jointed legs folded forward under it; a long abdomen of ten
##    tapering segments (UV.x: how far along it - its flex; UV.y: segment + place
##    in it - the joints and spots); the claspers at its tip. COLOR: r eye, g dark
##    chitin, b thorax. Metallic and iridescent (dragonfly.gdshader).
##  - the wings: four long narrow ones, the hind pair broader at the base, glassy,
##    veined, a dark stigma near each tip (dragonfly_wing.gdshader); UV: (along
##    the span, across the chord), UV2: (side, 0 fore / 1 hind) - the shader beats
##    them round their hinges, fore and hind out of phase.
## Built on a worker (start() when the species is designed; mesh() waits for it).
## Unit space: CosmosCreature scales it by the species' size; forward is -z.

const BODY_SHADER := preload("res://shaders/world/dragonfly.gdshader")
const WING_SHADER := preload("res://shaders/world/dragonfly_wing.gdshader")
const WING_LEN := 0.9
const FORE_HINGE := Vector3(0.028, 0.112, -0.44)
const HIND_HINGE := Vector3(0.028, 0.106, -0.335)
const ABDOMEN := [0.045, 0.092, 0.122, 0.12, 0.118, 0.116, 0.112, 0.1, 0.08, 0.06]   # (the ten segments' lengths)
const ABD_START := -0.275
const ABD_END := 0.8

static var _mesh: ArrayMesh
static var _task := -1
static var _built: Builder
## What the last build made (the tests read it): {"legs", "wings", "segments", "build_ms"}.
static var made := {}


## Begin making the mesh on a worker (nothing if made or under way).
static func start() -> void:
	if _mesh != null or _task >= 0:
		return
	_built = Builder.new()
	_task = WorkerThreadPool.add_task(_built.run, false, "dragonfly mesh")


## The mesh made (or its task finished: mesh() then costs only the upload).
static func is_ready() -> bool:
	return _mesh != null or (_task >= 0 and WorkerThreadPool.is_task_completed(_task))


static func mesh() -> ArrayMesh:
	if _mesh == null:
		start()
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _built.body.arrays())
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _built.wings.arrays())
		m.custom_aabb = AABB(Vector3(-1.0, -0.4, -0.9), Vector3(2.0, 1.2, 1.9))   # (the beating wings inside)
		made = {"legs": _built.legs, "wings": _built.wing_n, "segments": _built.segments, "build_ms": _built.ms}
		_built = null
		_mesh = m
	return _mesh


## Its two materials, one dragonfly's own (its hit flash, its wings' beat): [body, wings].
static func materials(c1: Color, c2: Color) -> Array:
	var b := ShaderMaterial.new()
	b.shader = BODY_SHADER
	b.set_shader_parameter("c1", c1)
	b.set_shader_parameter("c2", c2)
	b.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	var w := ShaderMaterial.new()
	w.shader = WING_SHADER
	w.set_shader_parameter("tint", c2)
	w.set_shader_parameter("stigma", c1.darkened(0.6))
	w.set_shader_parameter("fore_hinge", FORE_HINGE)
	w.set_shader_parameter("hind_hinge", HIND_HINGE)
	return [b, w]


## One surface's vertices; normals smoothed from its faces at the end.
class Part:
	var v := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var flat_n := PackedVector3Array()   # (given normals: the wings)

	func add(p: Vector3, c: Color, a: Vector2, b: Vector2) -> int:
		v.append(p)
		col.append(c)
		uv.append(a)
		uv2.append(b)
		return v.size() - 1

	## (given counter-clockwise seen from outside; stored clockwise - Godot's front faces)
	func tri(a: int, b: int, c: int) -> void:
		idx.append_array([a, c, b])

	func arrays() -> Array:
		var n := flat_n
		if n.size() != v.size():
			n = PackedVector3Array()
			n.resize(v.size())
			for i in range(0, idx.size(), 3):
				var a := idx[i]
				var b := idx[i + 1]
				var c := idx[i + 2]
				var f := (v[c] - v[a]).cross(v[b] - v[a])   # (area-weighted, outward)
				n[a] += f
				n[b] += f
				n[c] += f
			for i in n.size():
				n[i] = n[i].normalized() if n[i].length_squared() > 1e-20 else Vector3.UP
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


class Builder:
	var body := Part.new()
	var wings := Part.new()
	var legs := 0
	var wing_n := 0
	var segments := 0
	var ms := 0.0

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		_head()
		_thorax()
		_abdomen()
		_legs()
		for side in [-1.0, 1.0]:
			_wing(side, 0.0)
			_wing(side, 1.0)
		ms = (Time.get_ticks_usec() - t0) / 1000.0

	## A tube through `pts` (ellipse radii `rad`: x across, y up), `sides` round,
	## its ends closed; per ring a colour, a UV and the UV2 its facets need
	## (`facet` > 0: UV2 = (round, along) / facet).
	func loft(pts: Array, rad: Array, cols: Array, uvs: Array, sides: int, facet := 0.0) -> void:
		var p := body
		var n := pts.size()
		var base := p.v.size()
		var t0: Vector3 = (pts[1] - pts[0]).normalized()
		var up := Vector3.UP if absf(t0.y) < 0.9 else Vector3.BACK
		up = (up - t0 * up.dot(t0)).normalized()
		var along := 0.0
		for i in n:
			var t: Vector3
			if i == 0:
				t = t0
			elif i == n - 1:
				t = (pts[i] - pts[i - 1]).normalized()
			else:
				t = (pts[i + 1] - pts[i - 1]).normalized()
			up = (up - t * up.dot(t)).normalized()   # (carried along: no twist)
			var side := up.cross(t).normalized()
			if i > 0:
				along += (pts[i] - pts[i - 1]).length()
			var r: Vector2 = rad[i]
			for j in sides + 1:
				var a := TAU * j / sides
				var q: Vector3 = pts[i] + side * cos(a) * r.x + up * sin(a) * r.y
				var f := Vector2.ZERO
				if facet > 0.0:
					f = Vector2(float(j) / sides * TAU * (r.x + r.y) * 0.5, along) / facet
				p.add(q, cols[i], uvs[i], f)
		for i in n - 1:
			for j in sides:
				var a := base + i * (sides + 1) + j
				var b := a + sides + 1
				p.tri(a, a + 1, b)
				p.tri(a + 1, b + 1, b)
		# (the ends: fans - a ring of radius 0 needs none)
		for e in [0, n - 1]:
			var r2: Vector2 = rad[e]
			if r2.length() < 1e-5:
				continue
			var c := p.add(pts[e], cols[e], uvs[e], Vector2.ZERO)
			var ring: int = base + e * (sides + 1)
			for j in sides:
				if e == 0:
					p.tri(c, ring + j + 1, ring + j)
				else:
					p.tri(c, ring + j, ring + j + 1)

	## An ellipsoid (radii r) round `at`, its poles along `axis`.
	func blob(at: Vector3, r: Vector3, axis: Vector3, col: Color, rings: int, sides: int, facet := 0.0, uv := Vector2(0, -1)) -> void:
		var pts := []
		var rad := []
		var cols := []
		var uvs := []
		axis = axis.normalized()
		var ra := absf(axis.dot(r))
		var other := Vector2(r.x, r.y) if absf(axis.z) > 0.5 else (Vector2(r.z, r.y) if absf(axis.x) > 0.5 else Vector2(r.x, r.z))
		for i in rings + 1:
			var th := PI * i / rings
			pts.append(at - axis * cos(th) * ra)
			rad.append(other * maxf(sin(th), 0.0))
			cols.append(col)
			uvs.append(uv)
		loft(pts, rad, cols, uvs, sides, facet)

	func _head() -> void:
		var eye := Color(1, 0, 0)
		var dark := Color(0, 1, 0)
		var plain := Color(0, 0, 0)
		# The two compound eyes - one dome over most of the head, the seam where they
		# meet on top drawn by the shader (the dome's pole hidden in it).
		blob(Vector3(0, 0.026, -0.664), Vector3(0.094, 0.074, 0.07), Vector3.UP, eye, 18, 32, 0.0085)
		blob(Vector3(0, -0.012, -0.716), Vector3(0.05, 0.042, 0.034), Vector3.BACK, plain, 8, 14)     # (the face: frons and clypeus)
		blob(Vector3(0, -0.05, -0.705), Vector3(0.034, 0.026, 0.026), Vector3.BACK, dark, 5, 12)      # (the mouthparts)
		blob(Vector3(0, 0.012, -0.624), Vector3(0.06, 0.058, 0.034), Vector3.BACK, dark, 6, 14)       # (the back of the head)
		blob(Vector3(0, 0.03, -0.73), Vector3(0.016, 0.012, 0.012), Vector3.UP, plain, 4, 8)          # (the vertex, between the eyes)
		# Short antennae, bristles forward from the face.
		for side in [-1.0, 1.0]:
			var a := Vector3(side * 0.012, 0.022, -0.74)
			loft([a, a + Vector3(side * 0.005, 0.008, -0.012), a + Vector3(side * 0.012, 0.02, -0.03)],
				[Vector2(0.003, 0.003), Vector2(0.0018, 0.0018), Vector2(0.0005, 0.0005)], [dark, dark, dark],
				[Vector2(0, -1), Vector2(0, -1), Vector2(0, -1)], 5)

	func _thorax() -> void:
		var th := Color(0, 0, 1)
		# The neck (prothorax) and the synthorax - slanted: the legs forward under it, the wings back on top.
		blob(Vector3(0, 0.0, -0.59), Vector3(0.042, 0.042, 0.035), Vector3.BACK, Color(0, 0.6, 0.6), 6, 14)
		var pts := []
		var rad := []
		var cols := []
		var uvs := []
		var n := 12
		for i in n + 1:
			var f := float(i) / n
			var z := lerpf(-0.575, -0.255, f)
			var y := lerpf(-0.02, 0.025, f) + sin(f * PI) * 0.012
			var bulge := sin(PI * (0.06 + 0.86 * pow(f, 0.85)))
			var w := 0.02 + 0.058 * pow(bulge, 0.6)
			var h := 0.025 + 0.078 * pow(bulge, 0.55)
			pts.append(Vector3(0, y, z))
			rad.append(Vector2(w, h))
			cols.append(th)
			uvs.append(Vector2(0, -1))
		loft(pts, rad, cols, uvs, 20)
		# (the wing bases: small humps)
		for hinge in [FORE_HINGE, HIND_HINGE]:
			for side in [-1.0, 1.0]:
				blob(Vector3(side * hinge.x, hinge.y - 0.008, hinge.z), Vector3(0.018, 0.012, 0.03), Vector3.BACK, Color(0, 0.7, 0.5), 4, 8)

	func _abdomen() -> void:
		var total := 0.0
		for l in ABDOMEN:
			total += l
		var pts := []
		var rad := []
		var cols := []
		var uvs := []
		var at := 0.0
		# radius per segment (S1-2 swollen, S3 the waist, S7-8 a little wider, then tapering)
		var R := [0.04, 0.042, 0.03, 0.026, 0.026, 0.026, 0.028, 0.03, 0.028, 0.024]
		for s in ABDOMEN.size():
			var len: float = ABDOMEN[s] / total
			var r0: float = R[s]
			var r1: float = R[mini(s + 1, R.size() - 1)] if s < R.size() - 1 else r0 * 0.8
			for k in [0.0, 0.08, 0.3, 0.7, 0.93]:
				var f: float = (at + len * k)
				var z := lerpf(ABD_START, ABD_END, f)
				var r := lerpf(r0, r1, k * k) * (0.86 if k == 0.0 else (0.97 if k == 0.08 else 1.0))
				var y := 0.012 - sin(f * PI) * 0.018 + f * f * 0.01
				pts.append(Vector3(0, y, z))
				rad.append(Vector2(r, r * 1.12))
				cols.append(Color(0, 0, 0))
				uvs.append(Vector2(f, s + k))
			at += len
			segments += 1
		var tip := Vector3(0, 0.012 - 0 + 0.01, ABD_END)
		pts.append(tip)
		rad.append(Vector2(0.012, 0.012))
		cols.append(Color(0, 0, 0))
		uvs.append(Vector2(1.0, 9.99))
		loft(pts, rad, cols, uvs, 12)
		# The claspers: two upper cerci and the lower epiproct.
		var dark := Color(0, 0.85, 0)
		for side in [-1.0, 1.0]:
			var a := tip + Vector3(side * 0.012, 0.006, -0.012)
			loft([a, a + Vector3(side * 0.008, 0.002, 0.035), a + Vector3(side * 0.004, -0.006, 0.065)],
				[Vector2(0.008, 0.007), Vector2(0.006, 0.005), Vector2(0.0008, 0.0008)], [dark, dark, dark],
				[Vector2(1, -1), Vector2(1, -1), Vector2(1, -1)], 6)
		var e := tip + Vector3(0, -0.01, -0.008)
		loft([e, e + Vector3(0, -0.006, 0.03), e + Vector3(0, 0.004, 0.05)],
			[Vector2(0.008, 0.005), Vector2(0.005, 0.004), Vector2(0.0008, 0.0008)], [dark, dark, dark],
			[Vector2(1, -1), Vector2(1, -1), Vector2(1, -1)], 6)

	## Six legs folded forward under the thorax (a basket, as in flight): coxa,
	## femur, tibia, tarsus with its claw - the hind ones longest.
	func _legs() -> void:
		var dark := Color(0, 1, 0)
		var ns := Vector2(0, -1)
		for pair in 3:
			var z := -0.535 + pair * 0.06
			var g := 1.0 + pair * 0.22
			for side in [-1.0, 1.0]:
				var hip := Vector3(side * 0.024, -0.055 + pair * 0.006, z)
				var knee := hip + Vector3(side * 0.05, -0.035, -0.06 - pair * 0.012) * g
				var ankle := knee + Vector3(side * 0.006, -0.05, 0.055 + pair * 0.01) * g
				var toe := ankle + Vector3(0, -0.004, -0.032) * g
				var claw := toe + Vector3(0, 0.006, -0.008)
				loft([hip, hip.lerp(knee, 0.12), hip.lerp(knee, 0.5), knee.lerp(hip, 0.04), knee],
					[Vector2(0.012, 0.012), Vector2(0.009, 0.009), Vector2(0.008, 0.0085), Vector2(0.0075, 0.0075), Vector2(0.006, 0.006)],
					[dark, dark, dark, dark, dark], [ns, ns, ns, ns, ns], 6)
				loft([knee, knee.lerp(ankle, 0.5), ankle],
					[Vector2(0.006, 0.006), Vector2(0.005, 0.005), Vector2(0.004, 0.004)], [dark, dark, dark], [ns, ns, ns], 6)
				loft([ankle, ankle.lerp(toe, 0.5), toe, claw],
					[Vector2(0.0038, 0.0038), Vector2(0.003, 0.003), Vector2(0.0025, 0.0025), Vector2(0.0005, 0.0005)],
					[dark, dark, dark, dark], [ns, ns, ns, ns], 5)
				legs += 1
				# (the spines along the tibia: a few short bristles)
				for b in 3:
					var at := knee.lerp(ankle, 0.25 + b * 0.25)
					loft([at, at + Vector3(side * 0.004, 0.002, -0.012) * g], [Vector2(0.0018, 0.0018), Vector2(0.0003, 0.0003)],
						[dark, dark], [ns, ns], 4)

	## The wing's chord at `s` (0 root .. 1 tip): long and narrow, the hind one
	## broader at its base (its anal field).
	static func chord(s: float, hind: float) -> Vector2:
		var root := 0.32 + 0.68 * smoothstep(0.0, 0.16, s)
		var tip := pow(maxf(1.0 - pow(s, 5.0), 0.0), 0.5)
		var c := (0.155 + 0.03 * hind) * root * tip * (1.0 - 0.12 * s)
		var lead := c * 0.22
		var trail := c * 0.78
		if hind > 0.5:
			trail += 0.1 * (1.0 - smoothstep(0.04, 0.42, s)) * smoothstep(0.0, 0.05, s)
		return Vector2(lead, maxf(trail, 0.002))

	func _wing(side: float, hind: float) -> void:
		var p := wings
		wing_n += 1
		var hinge := HIND_HINGE if hind > 0.5 else FORE_HINGE
		var h := Vector3(side * hinge.x, hinge.y, hinge.z)
		var ns := 28
		var nc := 7
		var base := p.v.size()
		var span := WING_LEN * (0.96 if hind > 0.5 else 1.0)
		for i in ns + 1:
			var s := float(i) / ns
			s = 1.0 - pow(1.0 - s, 1.25)   # (finer toward the tip's curve)
			var c := chord(s, hind)
			var sweep := s * s * 0.03 + (0.025 * s if hind > 0.5 else 0.0)   # (the tips swept back a little)
			for j in nc + 1:
				var f := float(j) / nc
				var z := h.z + sweep + lerpf(-c.x, c.y, f)
				var y := h.y + sin(f * PI) * 0.006 * (1.0 - s) - s * 0.008   # (a little camber, a little droop)
				p.add(Vector3(h.x + side * (0.004 + s * span), y, z), Color(1, 1, 1), Vector2(s, f), Vector2(side, hind))
				p.flat_n.append(Vector3.UP)
		for i in ns:
			for j in nc:
				var a := base + i * (nc + 1) + j
				var b := a + nc + 1
				if side > 0.0:   # (facing up)
					p.tri(a, a + 1, b)
					p.tri(a + 1, b + 1, b)
				else:
					p.tri(a, b, a + 1)
					p.tri(a + 1, b, b + 1)
