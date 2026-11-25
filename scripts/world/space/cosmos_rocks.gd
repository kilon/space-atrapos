class_name CosmosRocks
extends Node3D
## An asteroid field in the 3D game (Cosmos): a few hundred rocks in a loose
## flattened cloud - three lumpy rock meshes (spheres pushed about by noise),
## drawn as multimeshes (one draw each), tumbling in their shader by a clock
## set from here (`clock`), so the script knows each rock's turn: where a
## point on its surface is now (`surface_at` - the veins CosmosMining cuts).
## `rocks` keeps every rock's place and size (the ship bumps into them).
## Each rock is a mix of minerals with its ore in veins (Mining.generate, by
## the field's kind and the rock's size), made when first asked for
## (`state`); mined, a rock is carved: the first cut gives it a finer mesh
## of its own (built on a worker) and each vein worked becomes a pit that
## deepens and widens as its ore comes out, fractures and hacking at the bulk
## rock blast craters (`carve`); mined out it's gone - for good (kept in the
## save, craters and all: CosmosGame.extra "mined").

const COUNT := 320
const SPREAD := 2600.0
const SHADER := preload("res://shaders/world/rock.gdshader")
const KINDS := ["iron", "iron", "titanium", "platinum"]
const TONES := {"iron": Color(0.42, 0.36, 0.31), "titanium": Color(0.46, 0.46, 0.47), "platinum": Color(0.5, 0.47, 0.4)}
const ORE_PER_M := 12.0          # ore units a metre of radius

var rocks: Array = []           # [local position, radius] (the radius shrinks as it's mined; 0: gone)
var kind := "iron"
var key := ""                   # (the save's: system and field)
var clock := 0.0                # s: the tumble's clock (the shader's)
var _inst: Array = []           # per rock: [mesh kind, instance, axis, speed, basis (unscaled), first radius]
var _mms: Array = []            # the multimeshes
var _shape: Array = []          # per mesh kind: [FastNoiseLite, scale]
var _mat: ShaderMaterial
var _state := {}                # rock -> {comp, veins, ore_total, ore_left, scanned}
var _carved := {}               # rock -> {craters: [[centre (unit), radius, depth]], mm, mmi, task, arrays, dirty, t}
var _seeds: Array = []          # per mesh kind: its noise seed (the fine meshes')
const FINE := Vector2i(48, 24)  # a carved rock's mesh: segments, rings
const REBUILD := 0.15           # s: a carved rock's mesh rebuilt at most this often
const CRATERS := 48             # the most a rock keeps (the smallest merged away)


func setup(seed: int, noise: Texture3D, save_key := "") -> void:
	name = "Asteroids"
	key = save_key
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	kind = KINDS[rng.randi() % KINDS.size()]
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise_tex", noise)
	_mat.set_shader_parameter("tone", TONES[kind].lerp(Color(0.5, 0.42, 0.36), rng.randf() * 0.3))
	var kinds := 3
	var per: Array = []
	for k in kinds:
		per.append([])
	for i in COUNT:
		var r := pow(rng.randf(), 2.2) * 70.0 + 4.0
		var p := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 0.25), rng.randfn(0.0, 1.0)) * SPREAD * 0.5
		rocks.append([p, r])
		var axis := Vector3(rng.randf(), rng.randf(), rng.randf())
		var w := rng.randf()
		var euler := Vector3(rng.randf(), rng.randf(), rng.randf())
		_inst.append([i % kinds, per[i % kinds].size(), axis, w, Basis.from_euler(euler * TAU), r])
		per[i % kinds].append(i)
	for k in kinds:
		var ms := rng.randi()
		_seeds.append(ms)
		var made := _rock_mesh(ms)
		_shape.append([made[1], made[2]])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = made[0]
		mm.instance_count = per[k].size()
		for j in per[k].size():
			var i: int = per[k][j]
			var e: Array = _inst[i]
			mm.set_instance_transform(j, Transform3D((e[4] as Basis).scaled(Vector3.ONE * float(rocks[i][1])), rocks[i][0]))
			mm.set_instance_custom_data(j, Color(e[2].x, e[2].y, e[2].z, e[3]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat
		add_child(mmi)
		_mms.append(mm)
	# Rocks mined before (the save): their size, or gone.
	var mined: Dictionary = CosmosGame.extra.get("mined", {}).get(key, {}) if key != "" else {}
	for s in mined:
		var i := int(s)
		if i >= 0 and i < rocks.size():
			var cr: Array = mined[s].get("craters", [])
			if not cr.is_empty() and float(mined[s].get("left", 1.0)) > 0.0:
				_carved[i] = {"craters": cr.map(func(c): return [Vector3(c[0], c[1], c[2]), float(c[3]), float(c[4])]), "task": -1, "dirty": true, "t": 0.0}
			_size(i, float(mined[s].get("left", 1.0)))


func _process(delta: float) -> void:
	clock = fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	_mat.set_shader_parameter("clock", clock)
	for i in _carved:
		_carve_step(i, delta)


func _exit_tree() -> void:
	for i in _carved:
		if int(_carved[i]["task"]) != -1:
			WorkerThreadPool.wait_for_task_completion(_carved[i]["task"])
			_carved[i]["task"] = -1


## A lumpy unit rock: a sphere's vertices pushed in and out by noise -
## [mesh, its noise, its scale] (the surface's radius: _radius()).
static func _rock_mesh(seed: int) -> Array:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 20
	s.rings = 10
	var arr := s.get_mesh_arrays()
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.9
	n.fractal_octaves = 3
	var sc := Vector3(1.0, 0.75 + 0.2 * (seed % 3) / 2.0, 0.9)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var d := verts[i].normalized()
		verts[i] = d * (1.0 + n.get_noise_3dv(d * 1.3) * 0.45) * sc
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return [st.commit(), n, sc]


# --- Where things are on a rock (its tumble) ---------------------------------------------

## Rock `i`'s turn now: the shader's rotation (about its axis, by the clock).
func _turn(i: int) -> Basis:
	var e: Array = _inst[i]
	var k: Vector3 = ((e[2] as Vector3) * 2.0 - Vector3.ONE + Vector3(0.001, 0.001, 0.001)).normalized()
	return Basis(k, clock * (float(e[3]) - 0.5) * 0.6)


## The point of rock `i`'s surface in its mesh's direction `d` (unit), in the field's space.
func surface_at(i: int, d: Vector3) -> Vector3:
	var e: Array = _inst[i]
	var sh: Array = _shape[e[0]]
	var p: Vector3 = d * (1.0 + (sh[0] as FastNoiseLite).get_noise_3dv(d * 1.3) * 0.45) * (sh[1] as Vector3)
	if _carved.has(i):
		p = _dent(p, _carved[i]["craters"], null)
	return rocks[i][0] + (e[4] as Basis).scaled(Vector3.ONE * _shown_r(i)) * (_turn(i) * p)


## A point of the field (local) on rock `i`, in its unit mesh's space (unturned).
func to_unit(i: int, p: Vector3) -> Vector3:
	var e: Array = _inst[i]
	var b := (e[4] as Basis).scaled(Vector3.ONE * maxf(_shown_r(i), 0.0001))
	return _turn(i).inverse() * (b.inverse() * (p - rocks[i][0]))


## The unit mesh's surface point in the direction `d` (uncarved).
func unit_surface(i: int, d: Vector3) -> Vector3:
	var sh: Array = _shape[_inst[i][0]]
	return d * (1.0 + (sh[0] as FastNoiseLite).get_noise_3dv(d * 1.3) * 0.45) * (sh[1] as Vector3)


## A vein's place on rock `i` (its angle round and its height: Mining's a / d).
func vein_at(i: int, v: Dictionary) -> Vector3:
	return to_global(surface_at(i, vein_dir(v)))


## A vein's direction on its rock (unit space).
static func vein_dir(v: Dictionary) -> Vector3:
	var a := float(v["a"])
	return Vector3(cos(a), (float(v["d"]) - 0.53) * 1.6, sin(a)).normalized()


# --- Carving ------------------------------------------------------------------------------

## Rock `i`'s radius as drawn (a carved rock barely shrinks: its pits show what's gone).
func _shown_r(i: int) -> float:
	var r: float = rocks[i][1]
	if r <= 0.0 or not _carved.has(i):
		return r
	var r0: float = _inst[i][5]
	var left := clampf((r / r0 - 0.45) / 0.55, 0.0, 1.0)
	return r0 * (0.82 + 0.18 * left)


## A point `p` (unit space) pushed in by the craters: each a bowl round its
## centre, `depth` deep at the middle, rough (`rough`: a noise, or null).
static func _dent(p: Vector3, craters: Array, rough: FastNoiseLite) -> Vector3:
	for c in craters:
		var cc: Vector3 = c[0]
		var R: float = c[1]
		var d2 := p.distance_squared_to(cc)
		if d2 >= R * R:
			continue
		var f := 1.0 - d2 / (R * R)
		var k := f * f * (3.0 - 2.0 * f)   # (a bowl, its rim smooth)
		var dep: float = c[2]
		if rough:
			dep *= 0.8 + 0.4 * (rough.get_noise_3dv(p * 7.0) * 0.5 + 0.5)
		p -= cc.normalized() * dep * k
	return p


## Carve rock `i`: a crater at `at` (unit space, on its surface) `radius`
## wide, `depth` deep (unit); `key` >= 0 names a crater that grows (a vein's
## pit: the same key again replaces it), -1 a new one (or merged into one close by).
func carve(i: int, at: Vector3, radius: float, depth: float, key := -1) -> void:
	if not _carved.has(i):
		_carved[i] = {"craters": [], "task": -1, "dirty": true, "t": REBUILD}
	var cs: Array = _carved[i]["craters"]
	var done := false
	if key >= 0:
		for c in cs:
			if c.size() > 3 and int(c[3]) == key:
				c[0] = at
				c[1] = maxf(float(c[1]), radius)
				c[2] = maxf(float(c[2]), depth)
				done = true
				break
	else:
		for c in cs:
			if c.size() <= 3 and (c[0] as Vector3).distance_to(at) < float(c[1]) * 0.35:
				c[1] = maxf(float(c[1]), radius)
				c[2] = minf(float(c[2]) + depth * 0.5, 0.7)
				done = true
				break
	if not done:
		cs.append([at, radius, depth] + ([key] if key >= 0 else []))
		if cs.size() > CRATERS:
			var least := 0
			for k in cs.size():
				if float(cs[k][1]) * float(cs[k][2]) < float(cs[least][1]) * float(cs[least][2]) and cs[k].size() <= 3:
					least = k
			cs.remove_at(least)
	_carved[i]["dirty"] = true


## A carved rock's mesh: rebuilt on a worker when its craters change (at most
## every REBUILD s), swapped in when done; drawn as a multimesh of one (its
## tumble: the same shader, the same custom data).
func _carve_step(i: int, delta: float) -> void:
	var c: Dictionary = _carved[i]
	c["t"] = float(c["t"]) + delta
	if int(c["task"]) != -1:
		if not WorkerThreadPool.is_task_completed(c["task"]):
			return
		WorkerThreadPool.wait_for_task_completion(c["task"])
		c["task"] = -1
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c["out"][0])
		c.erase("out")
		if not c.has("mm"):
			var e: Array = _inst[i]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = m
			mm.instance_count = 1
			mm.set_instance_custom_data(0, Color(e[2].x, e[2].y, e[2].z, e[3]))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _mat
			add_child(mmi)
			c["mm"] = mm
			c["mmi"] = mmi
			_size(i, _left(i))
		else:
			(c["mm"] as MultiMesh).mesh = m
	if c["dirty"] and int(c["task"]) == -1 and float(c["t"]) >= REBUILD:
		c["dirty"] = false
		c["t"] = 0.0
		var craters: Array = (c["craters"] as Array).duplicate(true)
		var sd: int = _seeds[_inst[i][0]]
		var sc: Vector3 = _shape[_inst[i][0]][1]
		var out := []   # (the worker's result: only it touches this till it's done)
		c["out"] = out
		c["task"] = WorkerThreadPool.add_task(func(): out.append(_fine_arrays(sd, sc, craters)), true, "carved rock")


## (Worker) A carved rock's mesh arrays: the fine sphere pushed out by the
## rock's noise (as _rock_mesh), in by its craters; normals from its faces.
static func _fine_arrays(seed: int, sc: Vector3, craters: Array) -> Array:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.9
	n.fractal_octaves = 3
	var rough := FastNoiseLite.new()
	rough.seed = seed + 1
	rough.frequency = 1.0
	var segs := FINE.x
	var rings := FINE.y
	var verts := PackedVector3Array()
	for r in rings + 1:
		var th := PI * r / rings
		for g in segs + 1:
			var ph := TAU * g / segs
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p := d * (1.0 + n.get_noise_3dv(d * 1.3) * 0.45) * sc
			verts.append(_dent(p, craters, rough))
	var idx := PackedInt32Array()
	for r in rings:
		for g in segs:
			var a := r * (segs + 1) + g
			var b := a + segs + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var fn := (verts[idx[t + 2]] - verts[idx[t]]).cross(verts[idx[t + 1]] - verts[idx[t]])
		for q in 3:
			norms[idx[t + q]] += fn
	# (the seam: its two columns share their normals; the poles one)
	for r in rings + 1:
		var a := r * (segs + 1)
		var s2 := norms[a] + norms[a + segs]
		norms[a] = s2
		norms[a + segs] = s2
	for k in norms.size():
		norms[k] = norms[k].normalized() if norms[k].length_squared() > 0.0 else verts[k].normalized()
	for r in [0, rings]:
		var s3 := Vector3.ZERO
		for g in segs + 1:
			s3 += norms[r * (segs + 1) + g]
		for g in segs + 1:
			norms[r * (segs + 1) + g] = s3.normalized()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _left(i: int) -> float:
	var r: float = rocks[i][1]
	return 0.0 if r <= 0.0 else clampf((r / float(_inst[i][5]) - 0.45) / 0.55, 0.0, 1.0)


# --- Its ore ------------------------------------------------------------------------------

## Rock `i`'s ore and veins (made the first time; what's been cut, from the save).
func state(i: int) -> Dictionary:
	if _state.has(i):
		return _state[i]
	var r0: float = _inst[i][5]
	var total := int(r0 * ORE_PER_M)
	var g := Mining.generate(kind, r0, total, hash(key) + i)
	var st := {"comp": g["comp"], "veins": g["veins"], "ore_total": total, "ore_left": total, "scanned": false, "dmg": 0.0}
	var saved: Dictionary = CosmosGame.extra.get("mined", {}).get(key, {}).get(str(i), {})
	if not saved.is_empty():
		st["scanned"] = bool(saved.get("scanned", false))
		var left: Array = saved.get("veins", [])
		for k in mini(left.size(), st["veins"].size()):
			st["veins"][k]["units"] = int(left[k])
		st["ore_left"] = int(saved.get("ore", total))
	_state[i] = st
	return st


## Rock `i` after mining: its size by the ore left, kept in the save; gone when mined out.
func mined(i: int) -> void:
	var st := state(i)
	var left := float(st["ore_left"]) / maxf(1.0, float(st["ore_total"]))
	if st["ore_left"] <= 0 or (st["scanned"] and st["veins"].all(func(v): return int(v["units"]) <= 0)):
		left = 0.0
		st["ore_left"] = 0
	_size(i, left)
	if key == "":
		return
	var all: Dictionary = CosmosGame.extra.get("mined", {})
	var mine: Dictionary = all.get(key, {})
	mine[str(i)] = {"left": left, "ore": int(st["ore_left"]), "scanned": st["scanned"], "veins": st["veins"].map(func(v): return int(v["units"]))}
	if _carved.has(i) and left > 0.0:
		mine[str(i)]["craters"] = (_carved[i]["craters"] as Array).map(func(c): return [snappedf(c[0].x, 0.001), snappedf(c[0].y, 0.001), snappedf(c[0].z, 0.001), snappedf(c[1], 0.001), snappedf(c[2], 0.001)])
	all[key] = mine
	CosmosGame.extra["mined"] = all


func _size(i: int, left: float) -> void:
	var e: Array = _inst[i]
	var r: float = 0.0 if left <= 0.0 else float(e[5]) * (0.45 + 0.55 * left)
	rocks[i][1] = r
	var gone := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), rocks[i][0])
	var b: Basis = (e[4] as Basis).scaled(Vector3.ONE * maxf(_shown_r(i), 0.0001))
	var c: Dictionary = _carved.get(i, {})
	if c.has("mm"):
		# (carved: its own mesh shows, the shared one's instance hidden)
		(_mms[e[0]] as MultiMesh).set_instance_transform(e[1], gone)
		(c["mm"] as MultiMesh).set_instance_transform(0, Transform3D(b, rocks[i][0]) if r > 0.0 else gone)
		if r <= 0.0:
			if int(c["task"]) != -1:
				WorkerThreadPool.wait_for_task_completion(c["task"])
			(c["mmi"] as Node).queue_free()
			_carved.erase(i)
		return
	if r <= 0.0:
		_carved.erase(i)
	(_mms[e[0]] as MultiMesh).set_instance_transform(e[1], Transform3D(b, rocks[i][0]) if r > 0.0 else gone)


## The rock a line from `o` along `dir` meets first within `reach` (global): [rock, distance] or [].
func ray(o: Vector3, dir: Vector3, reach: float) -> Array:
	var lo := to_local(o)
	var ld := (global_basis.inverse() * dir).normalized()
	var best := -1
	var bt := reach
	for i in rocks.size():
		var r: float = rocks[i][1] * 0.85
		if r <= 0.0:
			continue
		var oc: Vector3 = lo - rocks[i][0]
		var b := oc.dot(ld)
		var c := oc.dot(oc) - r * r
		var disc := b * b - c
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < bt:
			bt = t
			best = i
	return [] if best < 0 else [best, bt]
