class_name CosmosWaters
extends Node3D
## A sea world's waters in the 3D game, on its planet (CosmosPlanet adds one): its
## lakes' and rivers' surfaces (PlanetWater - built on a worker, a mesh a frame: each
## river a ribbon along it at its water's level, sloping down with it - its u metres down
## it, v across, its colour the current's speed, its rapids, its depth, a fade at its ends;
## each lake its basin's water, flat at its level, out to under its lip), the sea's near
## grid (round the camera: its vertices moved by the waves - water_waves.gdshaderinc), the
## waves' clock, and the sound of the river nearest you (a calm one's murmur, a rapids'
## roar). All drawn with water_surface.gdshader (`body`: 1 the near grid, 2 a lake, 3 a river).

const SHADER := preload("res://shaders/world/water_surface.gdshader")
const NEAR_R := 420.0            # m: the near grid's reach
const NEAR_SHOW := 600.0         # m over the sea: the near grid drawn below this
const RIVER_SEEN := 2600.0       # m: a river's surface drawn within this
const LAKE_SEEN := 6000.0
const SOUND_REACH := 70.0        # m: a river heard within this
const MESH_BUDGET_US := 1200

static var clock := 0.0          # (s: the waves' - the shader's and the swimmers' the same)
static var _clock_frame := -1
static var wave_amp := 0.3       # m (the sea's biggest wave)

var planet: CosmosPlanet
var sea_mat: ShaderMaterial       # (the far sphere's: CosmosPlanet's)
var near_mat: ShaderMaterial
var lake_mat: ShaderMaterial
var river_mat: ShaderMaterial
var near_mi: MeshInstance3D
var meshes: Array = []            # MeshInstance3D a river or a lake (built)
var built := false
var _task := -1
var _out := {}
var _todo: Array = []
var _snd: AudioStreamPlayer3D
var _snd_key := ""
var _snd_t := 0.0


func _ready() -> void:
	name = "Waters"
	if DisplayServer.get_name() != "headless":
		Sfx.warm("water")   # (the rivers' sounds loaded ahead, in the background)
	var L: Dictionary = planet.shape.look
	sea_mat = planet._sea_mi.material_override as ShaderMaterial if planet._sea_mi else null
	near_mat = material(L, 1)
	lake_mat = material(L, 2)
	river_mat = material(L, 3)
	if sea_mat and sea_mat.shader == SHADER:
		near_mi = MeshInstance3D.new()
		near_mi.name = "SeaNear"
		near_mi.mesh = near_mesh()
		near_mi.material_override = near_mat
		near_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		near_mi.visible = false
		add_child(near_mi)
	var w := planet.shape.water
	if w and (not w.rivers.is_empty() or not w.lakes.is_empty()):
		var shape := planet.shape
		var out := {}
		_out = out
		var stop := _stop
		_task = WorkerThreadPool.add_task(func(): out["r"] = build(shape, stop), true, "planet waters")
	else:
		built = true


## Its lakes' and rivers' surfaces built again (on a worker - the old ones kept till then):
## the rivers changed (fords - PlanetWater.ford).
func rebuild() -> void:
	if planet.shape.water == null:
		return
	if _task != -1:
		_again = true   # (one under way: once more after it)
		return
	var shape := planet.shape
	var out := {}
	_out = out
	_replace = true
	var stop := _stop
	_task = WorkerThreadPool.add_task(func(): out["r"] = build(shape, stop), true, "planet waters")


var _replace := false
var _again := false


## The water's material for `body` (1 the sea's near grid, 2 a lake, 3 a river) on a world of look `L`.
static func material(L: Dictionary, body: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = -1   # (before the air's shells: they draw over it)
	m.set_shader_parameter("body", body)
	m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	var deep: Color = L.get("water_deep", Color(0.03, 0.12, 0.3))
	var shallow: Color = L.get("water_shallow", Color(0.12, 0.5, 0.6))
	var air: Color = L.get("atmosphere", Color(0.5, 0.75, 1.0))
	m.set_shader_parameter("sky_top", air.lerp(Color(0.25, 0.45, 0.9), 0.3))
	m.set_shader_parameter("sky_low", air.lerp(Color(0.92, 0.94, 0.96), 0.6))
	match body:
		2:   # (a lake: darker, peaty, a little green; the view in shorter)
			m.set_shader_parameter("deep", deep.lerp(Color(0.02, 0.06, 0.05), 0.55))
			m.set_shader_parameter("shallow", shallow.lerp(Color(0.18, 0.32, 0.22), 0.5))
			m.set_shader_parameter("absorb", Vector3(0.45, 0.16, 0.2))
			m.set_shader_parameter("murk", 0.12)
		3:   # (a river: clear green-brown, stirred)
			m.set_shader_parameter("deep", deep.lerp(Color(0.04, 0.09, 0.06), 0.6))
			m.set_shader_parameter("shallow", shallow.lerp(Color(0.3, 0.42, 0.3), 0.5))
			m.set_shader_parameter("absorb", Vector3(0.4, 0.13, 0.16))
			m.set_shader_parameter("murk", 0.09)
		_:
			m.set_shader_parameter("deep", deep)
			m.set_shader_parameter("shallow", shallow)
	return m


## The sea's far sphere's material (CosmosPlanet._add_sea: a sea of water).
static func sea_material(L: Dictionary, radius: float) -> ShaderMaterial:
	var m := material(L, 0)
	m.set_shader_parameter("obj_scale", radius)
	m.set_shader_parameter("radius", radius)
	return m


## The near grid: rings round its middle, finer near it (x, z in m; the shader puts it on the sphere).
static var _near_mesh: ArrayMesh


static func near_mesh() -> ArrayMesh:
	if _near_mesh:
		return _near_mesh
	var seg := 96
	var rings := 44
	var verts := PackedVector3Array([Vector3.ZERO])
	var idx := PackedInt32Array()
	var r0 := 0.7
	var g := pow(NEAR_R / r0, 1.0 / (rings - 1))
	for j in rings:
		var r := r0 * pow(g, j)
		for i in seg:
			var a := TAU * (i + 0.5 * (j % 2)) / seg
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in seg:
		idx.append_array([0, 1 + (i + 1) % seg, 1 + i])
	for j in rings - 1:
		var a0 := 1 + j * seg
		var b0 := 1 + (j + 1) * seg
		for i in seg:
			var i1 := (i + 1) % seg
			idx.append_array([a0 + i, a0 + i1, b0 + i, a0 + i1, b0 + i1, b0 + i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3.ONE * -1e5, Vector3.ONE * 2e5)
	_near_mesh = m
	return m


## (Worker) The lakes' and rivers' surfaces of `shape`: [kind, arrays, middle (planet-local)] each.
## `stop` [true]: its world gone - given up where it is (a wait on it never long).
static func build(shape: PlanetShape, stop: Array = [false]) -> Array:
	var w := shape.water
	var out: Array = []
	var R := shape.radius
	for ri in w.rivers.size():
		if stop[0]:
			return []
		var rv: Dictionary = w.rivers[ri]
		var first := int(rv["first"])
		var n := int(rv["count"])
		var run: Array = []
		for i in range(first, first + n):
			var d := w.pts[i] / R
			var wet := w.lake_at(d) < 0 and not (w.lvl[i] < 0.05 and shape.height(d) < -0.2)
			if wet:
				run.append(i)
			elif not run.is_empty():
				if run.size() >= 3:
					out.append(["river", _ribbon(w, run, first, first + n - 1), w.pts[run[run.size() / 2]]])
				run = []
		if run.size() >= 3:
			out.append(["river", _ribbon(w, run, first, first + n - 1), w.pts[run[run.size() / 2]]])
	for li in w.lakes.size():
		if stop[0]:
			return []
		out.append(["lake", _lake(w, li, stop), (w.lakes[li]["dir"] as Vector3) * R])
	return out


## A river's ribbon over its points `run` (a stretch of one river: `lo` .. `hi` its whole).
static func _ribbon(w: PlanetWater, run: Array, lo: int, hi: int) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var X := [-1.08, -0.55, 0.0, 0.55, 1.08]
	var n := run.size()
	for q in n:
		var i: int = run[q]
		var a: int = run[maxi(q - 1, 0)]
		var b: int = run[mini(q + 1, n - 1)]
		var p := w.pts[i]
		var u := p.normalized()
		var fw := (w.pts[b] - w.pts[a])
		fw = (fw - u * fw.dot(u)).normalized()
		var side := fw.cross(u)
		# (a fade where it runs into the sea, a lake or the river it joins, and out of a lake - not at a spring)
		var fade := clampf(float(n - 1 - q) / 3.0, 0.0, 1.0)
		if run[0] > lo:
			fade = minf(fade, clampf(float(q) / 3.0, 0.0, 1.0))
		var col := Color(w.spd[i] / 5.0, smoothstep(PlanetWater.RAPID_SPEED - 0.4, PlanetWater.RAPID_SPEED + 0.6, w.spd[i]), w.dep[i] / 4.0, fade)
		for x: float in X:
			var v := (p + side * w.hw[i] * x).normalized() * (w.radius + w.lvl[i] + 0.03)
			verts.append(v)
			norms.append(u)
			uvs.append(Vector2(w.along[i], x))
			cols.append(col)
	var C := X.size()
	for q in n - 1:
		for k in C - 1:
			var a := q * C + k
			idx.append_array([a, a + 1, a + C, a + 1, a + C + 1, a + C])
	_wind(verts, idx)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## A lake's water: a grid on its plane round its middle, kept where it's the lake's (its
## field over its shore's line, out to under its lip), at its level.
static func _lake(w: PlanetWater, li: int, stop: Array = [false]) -> Array:
	var L: Dictionary = w.lakes[li]
	var c: Vector3 = L["dir"]
	var reach := float(L["reach"])
	var lv := float(L["level"])
	var R := w.radius
	var t1 := c.cross(Vector3.UP if absf(c.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := c.cross(t1)
	var n := clampi(int(reach * 2.0 / 4.5), 8, 170)
	var sp := reach * 2.0 / n
	var G := n + 1
	var m := PackedFloat32Array()
	m.resize(G * G)
	var dirs := PackedVector3Array()
	dirs.resize(G * G)
	for j in G:
		if stop[0]:
			break
		for i in G:
			var d := (c * R + t1 * (-reach + i * sp) + t2 * (-reach + j * sp)).normalized()
			dirs[j * G + i] = d
			m[j * G + i] = w.lake_mask(d, li)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var at := {}
	for j in n:
		for i in n:
			var k := j * G + i
			if m[k] < 0.33 or m[k + 1] < 0.33 or m[k + G] < 0.33 or m[k + G + 1] < 0.33:
				continue
			var q := []
			for kk in [k, k + 1, k + G, k + G + 1]:
				if not at.has(kk):
					at[kk] = verts.size()
					verts.append(dirs[kk] * (R + lv + 0.02))
					norms.append(dirs[kk])
					cols.append(Color(0.0, 0.0, 0.5, 1.0))
				q.append(at[kk])
			idx.append_array([q[0], q[1], q[2], q[1], q[3], q[2]])
	_wind(verts, idx)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Its triangles wound to face up (out from the planet: Godot's front faces are clockwise).
static func _wind(verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	if idx.size() < 3:
		return
	var a := verts[idx[0]]
	var nrm := (verts[idx[1]] - a).cross(verts[idx[2]] - a)
	if nrm.dot(a) > 0.0:
		for t in range(0, idx.size(), 3):
			var x := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = x


func _process(delta: float) -> void:
	if Engine.get_process_frames() != _clock_frame:
		_clock_frame = Engine.get_process_frames()
		clock = fmod(clock + delta, 3600.0)
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_todo = _out.get("r", [])
		_out = {}
		if _replace:   # (the new ones in place of the old)
			_replace = false
			for mi in meshes:
				mi.queue_free()
			meshes.clear()
		if _again:
			_again = false
			_todo = []
			rebuild()
	if not _todo.is_empty():
		var until := Time.get_ticks_usec() + MESH_BUDGET_US
		while not _todo.is_empty() and Time.get_ticks_usec() < until:
			_make(_todo.pop_back())
		if _todo.is_empty():
			built = true
	var cam := get_viewport().get_camera_3d()
	var sun := planet.sun_dir
	for m: ShaderMaterial in [sea_mat, near_mat, lake_mat, river_mat]:
		if m == null:
			continue
		m.set_shader_parameter("ww_t", clock)
		m.set_shader_parameter("sun_dir", sun)
		m.set_shader_parameter("ww_amp", wave_amp)
		m.set_shader_parameter("radius", planet.radius)
	if cam == null:
		return
	var local := planet.to_local(cam.global_position)
	_near_grid(local)
	_snd_t -= delta
	if _snd_t <= 0.0:
		_snd_t = 0.25
		_sound(local)
		_fords(local)


## Its roads made (CosmosRoads): fords where they cross its rivers (PlanetWater.ford, on a
## worker) - then the rivers' surfaces and the ground near you there made again.
func _fords(local: Vector3) -> void:
	var w := planet.shape.water
	if w == null or w.pts.is_empty():
		return
	if _ford_task != -1:
		if not WorkerThreadPool.is_task_completed(_ford_task):
			return
		WorkerThreadPool.wait_for_task_completion(_ford_task)
		_ford_task = -1
		for p in w.fords:
			if p.distance_to(local) < 2500.0:
				planet._rebuild_near(p, 30.0)
		rebuild()
		return
	if _forded:
		return
	var roads: Array = CosmosRoads._cache.get(CosmosRoads._pid(planet), [])
	if roads.is_empty():
		return
	_forded = true
	if not w.fords.is_empty():
		return   # (this world's water's been through it: kept from the last visit)
	var stop := _stop
	_ford_task = WorkerThreadPool.add_task(func():
		if not stop[0]:
			w.ford(roads, stop), true, "planet fords")


var _ford_task := -1
var _forded := false


func _make(e: Array) -> void:
	var arr: Array = e[1]
	if (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = ("River" if e[0] == "river" else "Lake") + str(meshes.size())
	mi.mesh = m
	mi.material_override = river_mat if e[0] == "river" else lake_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = RIVER_SEEN if e[0] == "river" else LAKE_SEEN
	mi.visibility_range_end_margin = 200.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(mi)
	meshes.append(mi)


## The near grid under the camera (planet-local `local`) - drawn low over the sea, the far
## sphere leaving it its middle.
func _near_grid(local: Vector3) -> void:
	if near_mi == null or sea_mat == null:
		return
	var alt := local.length() - planet.radius
	var on := alt < NEAR_SHOW and alt > -40.0 and planet._sea_mi.visible
	near_mi.visible = on
	if not on:
		sea_mat.set_shader_parameter("near_r", 0.0)
		return
	var u := local.normalized()
	var c := u * planet.radius
	var t1 := u.cross(Vector3.UP if absf(u.y) < 0.95 else Vector3.RIGHT).normalized()
	var t2 := u.cross(t1)
	for m: ShaderMaterial in [near_mat, sea_mat]:
		m.set_shader_parameter("near_c", c)
		m.set_shader_parameter("near_t1", t1)
		m.set_shader_parameter("near_t2", t2)
		m.set_shader_parameter("near_r", NEAR_R)


## The planet-local height (m above the radius) of the sea's waves at `p` now - as the
## shader's (water_waves.gdshaderinc: its long waves' heights, not their sideways swing).
static func wave_height(p: Vector3, t := INF) -> float:
	if t == INF:
		t = clock
	var up := p.normalized()
	var h := 0.0
	for i in WL.size():
		var D := (WIND * cos(WANG[i]) + SIDE * sin(WANG[i])).normalized()
		var mm := (D - up * D.dot(up)).length()
		var k: float = TAU / WL[i]
		h += wave_amp * float(WA[i]) * mm * sin(k * p.dot(D) - sqrt(9.81 * k) * t + float(WPH[i]))
	return h


const WIND := Vector3(0.8, 0.12, 0.58)
const SIDE := Vector3(-0.58, 0.0, 0.8)
const WL := [31.0, 19.0, 12.0, 7.4, 4.6]
const WA := [1.0, 0.6, 0.38, 0.22, 0.12]
const WANG := [0.0, 0.55, -0.45, 1.15, -0.9]
const WPH := [0.0, 1.7, 4.1, 2.6, 5.3]


## The river nearest you heard from where it runs: a murmur, louder where it's fast; a roar in its rapids.
func _sound(local: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := planet.shape.water
	var want := ""
	var at := Vector3.ZERO
	var loud := -60.0
	if w and not w.pts.is_empty() and local.length() - planet.radius < SOUND_REACH + 60.0:
		var i := w.nearest_point(local.normalized() * planet.radius, SOUND_REACH + w.BANK_MAX)
		if i >= 0:
			var d := local.distance_to(w.pts[i].normalized() * (planet.radius + w.lvl[i]))
			var fast := smoothstep(1.2, 3.2, w.spd[i])
			want = "water/rapids" if fast > 0.5 else "water/river"
			at = w.pts[i].normalized() * (planet.radius + w.lvl[i] + 0.3)
			loud = lerpf(-14.0, -4.0, fast) - 8.0 * clampf(d / SOUND_REACH, 0.0, 1.0)
	if want != _snd_key and _snd:
		_snd.queue_free()
		_snd = null
	_snd_key = want
	if want == "":
		return
	if _snd == null:
		var takes: Array = Sfx.takes(want)
		if takes.is_empty():
			return
		var st: AudioStream = takes[0]
		if st is AudioStreamOggVorbis:
			st = st.duplicate()
			st.loop = true
		_snd = AudioStreamPlayer3D.new()
		_snd.stream = st
		_snd.bus = Sfx.BUS
		_snd.unit_size = 12.0
		_snd.max_distance = SOUND_REACH * 1.6
		_snd.volume_db = loud
		add_child(_snd)
		_snd.position = at
		_snd.play()
	_snd.position = _snd.position.lerp(at, 0.5)
	_snd.volume_db = loud


var _stop := [false]            # (its workers' jobs: set leaving - they give up)


func _enter_tree() -> void:
	_stop[0] = false


func _exit_tree() -> void:
	_stop[0] = true
	if _ford_task != -1:
		WorkerThreadPool.wait_for_task_completion(_ford_task)
		_ford_task = -1
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
