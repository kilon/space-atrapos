class_name CosmosUnderwater
extends Node3D
## Under the sea of a water world (PlanetShape.sea == 1: its surface at the
## planet's radius, its floor PlanetShape.height below it) in the 3D game:
## the look while the camera is under the surface - one full-screen pass
## (underwater.gdshader: the water's absorption and glow, darker deeper; the
## caustics; light shafts; the surface seen from below, Snell's window; a
## slight wobble) and drifting specks round the camera (underwater_snow) -
## and the life round the diver: kelp forests, sea-grass meadows, corals
## (branching, domes, fans), sponges, urchins and boulders on the floor
## (designed from the planet's seed and palette, underwater_flora.gdshader:
## swaying in the current), schools of fish, rays, an eel or sea serpent and
## a bloom of jellyfish (underwater_life.gdshader: moved in the vertex
## shader; the script steers each group).
##
## The floor's things are scattered by CELL cells round the eye, each from
## its own seed (the same cell, the same plants), built on a worker - all the
## cells of a kind in one MultiMesh (a draw a kind) - streamed in and out as
## you swim (RANGE). Only on sea worlds, only under the water (none on dry
## land); kept ready while you're near the surface (ABOVE), drawn only once
## the camera's under it (the sea's surface is opaque from above).
##
## Cosmos adds one (it watches `cosmos.cam`, `cosmos.planets`, `cosmos.walker`):
##   underwater = CosmosUnderwater.new(); underwater.cosmos = self; add_child(underwater)

const FX := preload("res://shaders/world/underwater.gdshader")          # (pass 1: the absorption, the caustics - multiplied)
const GLOW := preload("res://shaders/world/underwater_glow.gdshader")   # (pass 2: the water's light, shafts, the surface - added)
const SNOW := preload("res://shaders/world/underwater_snow.gdshader")
const PLANTS := preload("res://shaders/world/underwater_flora.gdshader")
const LIFE := preload("res://shaders/world/underwater_life.gdshader")
const ROCK := preload("res://shaders/world/rock.gdshader")

const CELL := 24.0              # m: a scatter cell
const RANGE := 60.0             # m: the floor's things this far round the eye (the water's murk hides the edge)
const ABOVE := 12.0             # m: the eye this high over a sea (or lower - a swimmer's camera): its life streamed in, ready
const LEAVE := 400.0            # m: further above it, all of it let go
const REPLAN := 8.0             # m the eye moves before the area's cells are worked out again
const CHECK_S := 0.25           # s between looks round (which sea, the area)
const SNOW_N := 600
const SNOW_BOX := 14.0
const SCHOOLS := 4
const JELLIES := 9

var cosmos: Node
var planet: CosmosPlanet = null    # the sea world the eye's at (null: none near)
var under := false                 # the camera under its surface now
var eye_depth := 0.0               # m under it (the camera)
var design: Dictionary = {}        # the planet's sea life (design())
var cells := {}                    # Vector3i -> its built cell (cell())
var shown_cells: Array = []        # the cells drawn now
var counts := {}                   # kind -> instances drawn now

var _fx: MeshInstance3D            # (pass 1)
var _fx_mat: ShaderMaterial
var _glow: MeshInstance3D          # (pass 2)
var _glow_mat: ShaderMaterial
var _snow: MultiMeshInstance3D
var _snow_mat: ShaderMaterial
var _root: Node3D                  # (on the planet: everything of its sea)
var _mmis: Array = []              # a MultiMesh a plant kind
var _rock_mmi: MultiMeshInstance3D
var _plant_mat: ShaderMaterial
var _design_task := -1
var _design_out := {}
var _meshes: Array = []            # (built a frame at a time, from the design's arrays)
var _mesh_todo: Array = []
var _area_task := -1
var _area_out := {}
var _apply: Array = []             # (the area's buffers, set a kind a frame)
var _planned_at := Vector3(INF, INF, INF)
var _anchor := Vector3.ZERO        # (the caustics' plane: its origin and axes, planet-local)
var _axis_u := Vector3.RIGHT
var _axis_v := Vector3.BACK
var _check_t := 0.0
var _rocks: Array = []             # [planet-local position, radius, height] - the walker's bumps
var _swimmers: Array = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _shells_hid := {}              # (the air's shells hidden under the sea: put back on surfacing)


## A group of the sea's animals: a school, a ray, an eel, a bloom of jellies.
class Swimmer:
	var kind := ""
	var node: GeometryInstance3D
	var mat: ShaderMaterial
	var pos := Vector3.ZERO      # planet-local
	var vel := Vector3.ZERO
	var goal := Vector3.ZERO
	var cruise := 1.0            # m/s
	var turn := 1.0
	var lo := 1.0                # m over the floor, at least...
	var hi := 4.0                # ...at most (and under the surface)
	var flee := 0.0              # m: it bolts from you closer than this
	var scale := 1.0
	var floor_h := 0.0
	var floor_t := 0.0
	var goal_t := 0.0
	var placed := false
	var scared := false
	var far_t := 0.0


func _ready() -> void:
	_rng.seed = 4242
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.custom_aabb = AABB(Vector3.ONE * -1e7, Vector3.ONE * 2e7)   # (never culled: it covers the screen)
	_fx_mat = fx_material(FX)
	_fx = _screen_quad(q, _fx_mat, "UnderwaterLook")
	_glow_mat = fx_material(GLOW)
	_glow = _screen_quad(q, _glow_mat, "UnderwaterGlow")
	_snow_mat = snow_material()
	_snow = MultiMeshInstance3D.new()
	_snow.name = "UnderwaterSpecks"
	_snow.multimesh = snow_multimesh(SNOW_N)
	_snow.material_override = _snow_mat
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow.visible = false
	add_child(_snow)


func _screen_quad(q: Mesh, mat: Material, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


static func fx_material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = 100 if shader == FX else 101   # (after the transparent things: the air's shells it covers)
	m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	return m


static func snow_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SNOW
	m.render_priority = 110
	m.set_shader_parameter("box", SNOW_BOX)
	return m


static func snow_multimesh(n: int) -> MultiMesh:
	var q := QuadMesh.new()
	q.custom_aabb = AABB(Vector3.ONE * -1e7, Vector3.ONE * 2e7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in n:
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), pow(rng.randf(), 3.0)))
	mm.custom_aabb = q.custom_aabb
	return mm


func _process(delta: float) -> void:
	_t += delta
	var cam: Camera3D = cosmos.get("cam") if cosmos else null
	if cam == null or not is_instance_valid(cam):
		_set_under(false)
		return
	var eye := cam.global_position
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_S
		_look_round(eye)
	_collect()
	if planet == null:
		_set_under(false)
		return
	var local := eye - planet.global_position
	var r := local.length()
	eye_depth = planet.radius - r
	_set_under(eye_depth > (0.0 if under else 0.06) and _in_open_water(local))   # (a little hysteresis: no flicker at the waterline)
	if under:
		_update_look(local)
		_swim(delta, local)


## Whether the camera's out in the sea (not in a ship, a hangar, a dungeon or the ground).
func _in_open_water(local: Vector3) -> bool:
	if cosmos.get("dungeon") != null or cosmos.get("docked") == true:
		return false
	var w: Node = cosmos.get("walker")
	if w != null and is_instance_valid(w) and w.get("deck") != null:
		return false
	return local.length() > planet.radius + planet.shape.height(local.normalized()) - 1.0


func _set_under(on: bool) -> void:
	if on == under and _fx.visible == on:
		return
	under = on
	_fx.visible = on
	_glow.visible = on
	_snow.visible = on
	if _root:
		_root.visible = on   # (from above the sea's opaque: nothing of it drawn)
	_shells(not on)
	_near_sight(on)


## Under the sea the camera sees no further than the water lets it (at 150 m
## the clearest light is down to 0.2%): its far plane brought in to FAR_UNDER,
## the world beyond (the land, its plants, towns, the sky's bodies) not drawn
## at all - put back on surfacing.
const FAR_UNDER := 250.0
var _far_was := 0.0

func _near_sight(on: bool) -> void:
	var cam: Camera3D = cosmos.get("cam") if cosmos else null
	if cam == null or not is_instance_valid(cam):
		_far_was = 0.0
		return
	if on and _far_was == 0.0:
		_far_was = cam.far
		cam.far = FAR_UNDER
	elif not on and _far_was > 0.0:
		cam.far = _far_was
		_far_was = 0.0


## The planet's air shells (its atmosphere, its clouds): hidden under the sea -
## the passes cover them whole (their per-pixel work saved) - put back as they were.
func _shells(show: bool) -> void:
	if planet == null or not is_instance_valid(planet):
		_shells_hid = {}
		return
	for n in ["Atmosphere", "Clouds", "CloudsLow", "CloudsHigh"]:
		var sh := planet.get_node_or_null(n) as Node3D
		if sh == null:
			continue
		if not show and sh.visible:
			_shells_hid[n] = true
			sh.visible = false
		elif show and _shells_hid.has(n):
			sh.visible = true
	if show:
		_shells_hid = {}


## Which sea the eye's at; the area round it, worked out again when it's moved.
func _look_round(eye: Vector3) -> void:
	var best: CosmosPlanet = null
	var planets: Array = cosmos.get("planets") if cosmos.get("planets") != null else []
	for p: CosmosPlanet in planets:
		if not is_instance_valid(p) or p.shape == null or p.shape.sea != 1 or p.shape.kind == "gas":
			continue
		var r := (eye - p.global_position).length()
		if r < p.radius + LEAVE and r > p.radius - p.shape.amp * 3.0:
			best = p
			break
	if best != planet:
		_drop()
		planet = best
		if planet:
			_begin(planet)
	if planet == null or not design.has("plants") or _area_task != -1 or not _mesh_todo.is_empty() or not _apply.is_empty():
		return
	var local := eye - planet.global_position
	var r := local.length()
	if r > planet.radius + ABOVE:
		return
	var g := local.normalized() * planet.radius
	if g.distance_to(_planned_at) < REPLAN:
		return
	if r > planet.radius and planet.shape.height(local.normalized()) > 3.0:
		return   # (over dry land: no sea below to stream)
	_plan(g)


func _begin(pl: CosmosPlanet) -> void:
	_root = Node3D.new()
	_root.name = "Undersea"
	_root.visible = under
	pl.add_child(_root)
	var shape := pl.shape
	var seed := int(pl.rec.get("seed", 1))
	_design_out = {}
	_design_task = WorkerThreadPool.add_task(func(): _design_out = design_of(shape, seed), true, "undersea design")


## (Main) The worker's results taken in: the design, then its meshes (one a
## frame), then the area's cells (their buffers set a kind a frame).
func _collect() -> void:
	if _design_task != -1 and WorkerThreadPool.is_task_completed(_design_task):
		WorkerThreadPool.wait_for_task_completion(_design_task)
		_design_task = -1
		design = _design_out
		_design_out = {}
		_mesh_todo = []
		for sp: Dictionary in design["plants"]:
			_mesh_todo.append(sp["arrays"])
		for f: Dictionary in design["fish"]:
			_mesh_todo.append(f["arrays"])
		for k in ["ray", "eel", "jelly"]:
			_mesh_todo.append(design[k]["arrays"])
		_meshes = []
		return
	if not _mesh_todo.is_empty():
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _mesh_todo.pop_front())
		_meshes.append(m)
		if _mesh_todo.is_empty():
			_make_nodes()
		return
	if _area_task != -1 and WorkerThreadPool.is_task_completed(_area_task):
		WorkerThreadPool.wait_for_task_completion(_area_task)
		_area_task = -1
		var out := _area_out
		_area_out = {}
		for k in out["fresh"]:
			cells[k] = out["fresh"][k]
		var keep := {}
		for k in out["keys"]:
			keep[k] = true
		# (the cells left behind kept a while - swim back and they're there - then let go)
		for k in cells.keys():
			if not keep.has(k) and ((Vector3(k) + Vector3.ONE * 0.5) * CELL).distance_to(_planned_at) > RANGE * 2.5:
				cells.erase(k)
		shown_cells = out["keys"]
		_rocks = out["rocks"]
		for i in (out["bufs"] as Array).size():
			_apply.append([i, out["bufs"][i]])
		_apply.append([-1, out["rock_buf"]])
		return
	if not _apply.is_empty():
		var a: Array = _apply.pop_front()
		var buf: PackedFloat32Array = a[1]
		var mmi: MultiMeshInstance3D = _rock_mmi if int(a[0]) < 0 else _mmis[int(a[0])]
		var w := 16 if int(a[0]) < 0 else 12
		var mm := mmi.multimesh
		mm.instance_count = buf.size() / w
		if buf.size() > 0:
			mm.buffer = buf
		counts["rock" if int(a[0]) < 0 else str(design["plants"][int(a[0])]["kind"])] = buf.size() / w


func _make_nodes() -> void:
	var noise := Cosmos.noise_ready()
	_plant_mat = ShaderMaterial.new()
	_plant_mat.shader = PLANTS
	var plants: Array = design["plants"]
	for i in plants.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[i]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Sea_" + str(plants[i]["kind"])
		mmi.multimesh = mm
		mmi.material_override = _plant_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mmi)
		_mmis.append(mmi)
	var rmat := ShaderMaterial.new()
	rmat.shader = ROCK
	rmat.set_shader_parameter("noise_tex", noise)
	rmat.set_shader_parameter("tone", design["rock_tone"])
	var rm := MultiMesh.new()
	rm.transform_format = MultiMesh.TRANSFORM_3D
	rm.use_custom_data = true
	rm.mesh = rock_mesh()
	_rock_mmi = MultiMeshInstance3D.new()
	_rock_mmi.name = "Sea_rocks"
	_rock_mmi.multimesh = rm
	_rock_mmi.material_override = rmat
	_rock_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_rock_mmi)
	# The animals.
	var np := plants.size()
	var fish: Array = design["fish"]
	for i in SCHOOLS:
		var f: Dictionary = fish[i % fish.size()]
		var sw := Swimmer.new()
		sw.kind = "school"
		sw.mat = life_material(0, f["size"], f["spread"])
		sw.node = _group(_meshes[np + i % fish.size()], int(f["n"]), 900 + i, sw.mat)
		sw.cruise = _rng.randf_range(1.1, 1.8)
		sw.turn = 1.4
		sw.lo = 1.0 + f["spread"] * 0.4
		sw.hi = 6.0
		sw.flee = 5.0 + f["spread"]
		_swimmers.append(sw)
	var nf := np + fish.size()
	for i in 2:
		var sw := Swimmer.new()
		sw.kind = "ray"
		sw.mat = life_material(1, 1.0, 0.0)
		sw.node = _single(_meshes[nf], sw.mat)
		sw.cruise = _rng.randf_range(0.9, 1.4)
		sw.turn = 0.5
		sw.lo = 0.7
		sw.hi = 3.0
		sw.flee = 4.0
		sw.scale = _rng.randf_range(1.1, 2.0) * float(design["ray"]["size"])
		_swimmers.append(sw)
	var eel := Swimmer.new()
	eel.kind = "eel"
	eel.mat = life_material(2, 1.0, 0.0)
	eel.node = _single(_meshes[nf + 1], eel.mat)
	eel.cruise = 0.8
	eel.turn = 1.1
	eel.lo = 0.3
	eel.hi = 1.4
	eel.scale = float(design["eel"]["size"])
	_swimmers.append(eel)
	var jl := Swimmer.new()
	jl.kind = "jelly"
	jl.mat = life_material(3, float(design["jelly"]["size"]), 7.0)
	jl.mat.set_shader_parameter("glow", float(design["jelly"]["glow"]))
	jl.node = _group(_meshes[nf + 2], JELLIES, 1700, jl.mat)
	jl.cruise = 0.15
	jl.turn = 0.3
	jl.lo = 3.0
	jl.hi = 10.0
	_swimmers.append(jl)
	for sw: Swimmer in _swimmers:
		sw.node.visible = false


## A boulder of the sea floor: a lumpy ball, fewer faces than the land's (many, in the murk).
static var _rock: Mesh


static func rock_mesh() -> Mesh:
	if _rock == null:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 12
		s.rings = 7
		var arr := s.get_mesh_arrays()
		var n := FastNoiseLite.new()
		n.seed = 31
		n.frequency = 0.9
		n.fractal_octaves = 3
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			verts[i] = v * (1.0 + 0.35 * n.get_noise_3dv(v * 1.3)) * Vector3(1.0, 0.8, 0.92)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = null
		arr[Mesh.ARRAY_TANGENT] = null
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_normals()
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		_rock = m
	return _rock


static func life_material(kind: int, size: float, spread: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LIFE
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("spread", spread)
	return m


## A school (or a bloom): `n` of a mesh, each its slot and rhythm (custom data).
func _group(mesh: Mesh, n: int, seed: int, mat: ShaderMaterial) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in n:
		var s := Vector3(rng.randf(), rng.randf(), rng.randf())
		mm.set_instance_transform(i, Transform3D.IDENTITY)   # (the shader places each: its slot)
		mm.set_instance_custom_data(i, Color(s.x, s.y, s.z, rng.randf()))
	mm.custom_aabb = AABB(Vector3.ONE * -16.0, Vector3.ONE * 32.0)   # (the slots' wander: within this)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)
	return mmi


func _single(mesh: Mesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2.0
	_root.add_child(mi)
	return mi


## The cells round planet-local ground point `g` to have, the missing ones built (worker).
func _plan(g: Vector3) -> void:
	_planned_at = g
	var up := g.normalized()
	if _anchor == Vector3.ZERO or _anchor.normalized().dot(up) < 0.9995:
		_anchor = g   # (the caustics' plane: moved rarely - its pattern jumps then, unseen in the shimmer)
		_axis_u = up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		_axis_v = up.cross(_axis_u)
	var keys := cells_round(planet.radius, g, RANGE)
	var todo: Array = keys.filter(func(k): return not cells.has(k))
	var shape := planet.shape
	var dz := design
	var have := cells
	_area_out = {}
	_area_task = WorkerThreadPool.add_task(func(): _area_out = _build_area(shape, dz, keys, todo, have, g), true, "undersea cells")


## (Worker) The missing cells built, then every kind's instances of all the cells joined.
static func _build_area(shape: PlanetShape, dz: Dictionary, keys: Array, todo: Array, have: Dictionary, g: Vector3) -> Dictionary:
	var fresh := {}
	for k in todo:
		fresh[k] = cell(shape, dz, k)
	var n: int = (dz["plants"] as Array).size()
	var all: Array = []
	var off: Array = []   # (each cell's middle's distance from the eye's ground)
	for k in keys:
		all.append(fresh[k] if fresh.has(k) else have[k])
		off.append(((Vector3(k) + Vector3.ONE * 0.5) * CELL).distance_to(g))
	var bufs: Array = []
	for i in n:
		var near: float = dz["plants"][i]["near"]   # (the small kinds only nearer: unseen further in the murk)
		var b := PackedFloat32Array()
		for j in all.size():
			if off[j] <= near:
				b.append_array(all[j]["bufs"][i])
		bufs.append(b)
	var rock_buf := PackedFloat32Array()
	var rocks: Array = []
	for c: Dictionary in all:
		rock_buf.append_array(c["rock_buf"])
		rocks.append_array(c["rocks"])
	return {"fresh": fresh, "keys": keys, "bufs": bufs, "rock_buf": rock_buf, "rocks": rocks}


## The scatter cells (CELL cubes, planet-local) within `reach` of ground point
## `g` that the sea's shell passes through - each owns the things whose spot
## (a point in its cube) is near the radius: every spot in exactly one cell.
static func cells_round(radius: float, g: Vector3, reach: float) -> Array:
	var c0 := Vector3i((g / CELL).floor())
	var n := ceili(reach / CELL)
	var out: Array = []
	for x in range(-n, n + 1):
		for y in range(-n, n + 1):
			for z in range(-n, n + 1):
				var k := c0 + Vector3i(x, y, z)
				var mid := (Vector3(k) + Vector3.ONE * 0.5) * CELL
				if mid.distance_to(g) > reach + CELL * 0.87 or absf(mid.length() - radius) > CELL * 1.37:
					continue
				out.append(k)
	return out


## (Worker) One cell's things: for each kind a few clusters (meadows,
## forests, reefs - thicker where the kind's patch noise says), each spot
## put down on the floor if the water there is as deep as the kind likes.
## Deterministic: its own seed, the same draws whatever's kept.
static func cell(shape: PlanetShape, dz: Dictionary, key: Vector3i) -> Dictionary:
	var R := shape.radius
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(dz["seed"]), key.x, key.y, key.z])
	var lo := Vector3(key) * CELL
	var mid := lo + Vector3.ONE * CELL * 0.5
	var noise: FastNoiseLite = dz["noise"]
	var plants: Array = dz["plants"]
	var bufs: Array = []
	var rocks: Array = []
	var area := CELL * CELL
	for i in plants.size():
		var sp: Dictionary = plants[i]
		var patch := smoothstep(-0.3, 0.35, noise.get_noise_3dv(mid + Vector3(i * 1777.0, i * 913.0, 0.0))) * 2.0
		var want := float(sp["dens"]) * area * lerpf(1.0 - float(sp["patchy"]), patch, float(sp["patchy"]))
		var count := int(want + rng.randf())
		var per: int = sp["per"]
		var xs: Array = []
		var left := count
		while left > 0:
			var c3 := lo + Vector3(rng.randf(), rng.randf(), rng.randf()) * CELL
			var m := mini(left, per + rng.randi_range(-per / 3, per / 3))
			left -= maxi(m, 1)
			var in_band := absf(c3.length() - R) < CELL * 0.5
			for j in m:
				var off := Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * float(sp["spread"])
				var sc := rng.randf_range(sp["size"].x, sp["size"].y)
				var turn := rng.randf() * TAU
				if not in_band:
					continue
				var d := (c3 + off).normalized()
				var h := shape.height(d)
				var depth := -h
				if depth < float(sp["min"]) or depth > float(sp["max"]):
					continue
				var tall: float = sp["h"]
				if tall * sc > depth * 0.85:
					sc = depth * 0.85 / tall   # (kelp to below the surface)
					if sc < float(sp["size"].x) * 0.45:
						continue
				var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized().rotated(d, turn)
				var b := Basis(t, d, t.cross(d)).scaled(Vector3.ONE * sc)
				var at := d * (R + h - 0.06 * sc)
				xs.append(Transform3D(b, at))
				if float(sp["solid"]) > 0.0:
					rocks.append([at, float(sp["solid"]) * sc, tall * sc])
		bufs.append(CosmosPlanet._buffer(xs, false))
	# Boulders: scattered, and now and then a field of them.
	var rx: Array = []
	var nr := int(float(dz["rocks"]) * area * (1.0 if rng.randf() < 0.8 else 4.0) + rng.randf())
	for i in nr:
		var x3 := lo + Vector3(rng.randf(), rng.randf(), rng.randf()) * CELL
		var size := pow(rng.randf(), 3.0) * 2.6 + 0.25
		var e := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var sy := rng.randf_range(0.45, 0.85)
		if absf(x3.length() - R) >= CELL * 0.5:
			continue
		var d := x3.normalized()
		var h := shape.height(d)
		if h > -0.3:
			continue   # (only under the water)
		var at := d * (R + h - size * 0.3)
		rx.append(Transform3D(Basis.from_euler(e).scaled(Vector3(size, size * sy, size)), at))
		rocks.append([at, size * 0.8, size * 0.7])
	return {"bufs": bufs, "rock_buf": CosmosPlanet._buffer(rx, true), "rocks": rocks}


## Boulders and corals within `reach` of planet-local `local` (the walker's
## bumps): [planet-local position, radius, height] each.
func rocks_near(local: Vector3, reach: float) -> Array:
	var out: Array = []
	for r in _rocks:
		if (r[0] as Vector3).distance_to(local) < reach + float(r[1]):
			out.append(r)
	return out


## Metres under the sea's surface of world point `p` on planet `pl` (< 0: above it; no sea: -INF).
static func depth_of(pl: CosmosPlanet, p: Vector3) -> float:
	if pl == null or pl.shape.sea != 1:
		return -INF
	return pl.radius - (p - pl.global_position).length()


# --- The look -----------------------------------------------------------------------------

func _update_look(local: Vector3) -> void:
	var up := local.normalized()
	var L := planet.shape.look
	var sun := planet.sun_dir.normalized()
	var ca := sun.dot(up)
	var lw := up
	if ca > 0.0:   # (the sun's light bent down into the water: Snell, 1.333)
		var sw := sqrt(maxf(1.0 - ca * ca, 0.0)) / 1.333
		var tdir := sun - up * ca
		if tdir.length() > 1e-4:
			lw = (up * sqrt(1.0 - sw * sw) + tdir.normalized() * sw).normalized()
	var energy := 1.0
	var lt: Node = cosmos.get("light")
	if lt is DirectionalLight3D:
		energy = (lt as DirectionalLight3D).light_energy
	for m: ShaderMaterial in [_fx_mat, _glow_mat]:
		m.set_shader_parameter("eye_rel", local)
		m.set_shader_parameter("up", up)
		m.set_shader_parameter("radius", planet.radius)
		m.set_shader_parameter("eye_depth", eye_depth)
		m.set_shader_parameter("light_dir", lw)
		m.set_shader_parameter("sun_dir", sun)
		m.set_shader_parameter("light", energy)
		m.set_shader_parameter("anchor", _anchor)
		m.set_shader_parameter("axis_u", _axis_u)
		m.set_shader_parameter("axis_v", _axis_v)
		if not m.has_meta("tinted"):
			m.set_meta("tinted", true)
			m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
			m.set_shader_parameter("water", water_colour(L))
			m.set_shader_parameter("sky", (L.get("atmosphere", Color(0.5, 0.75, 1.0)) as Color).lightened(0.25))
	var day := energy * smoothstep(-0.05, 0.15, ca)
	var wc: Color = water_colour(L)
	var k := Vector3(exp(-0.16 * eye_depth), exp(-0.045 * eye_depth), exp(-0.032 * eye_depth)) * (0.25 + 0.9 * day)
	_snow_mat.set_shader_parameter("tint", Color(0.5 + wc.r * k.x * 2.0, 0.5 + wc.g * k.y * 1.2, 0.5 + wc.b * k.z, 0.5) * (0.35 + 0.65 * day))
	if _plant_mat and int(_t * 2.0) != int((_t - get_process_delta_time()) * 2.0):
		# (the current: slowly turning along the floor)
		var a := _t * 0.03
		_plant_mat.set_shader_parameter("current", (_axis_u * cos(a) + _axis_v * sin(a)) * 0.8)
		# (the water's own light all round, as deep as you are: the plants' and animals' shade lit by it)
		var fill := Color(wc.r * k.x, wc.g * k.y, wc.b * k.z) * 1.6
		_plant_mat.set_shader_parameter("fill", fill)
		for sw: Swimmer in _swimmers:
			sw.mat.set_shader_parameter("fill", fill)


## The sea's own colour (what its water scatters): its shallows', a little greener.
static func water_colour(L: Dictionary) -> Color:
	var s: Color = L.get("water_shallow", Color(0.12, 0.5, 0.6))
	return s.lerp(Color(0.06, 0.42, 0.42), 0.35) * 0.75


# --- The animals ---------------------------------------------------------------------------

func _swim(delta: float, eye: Vector3) -> void:
	for sw: Swimmer in _swimmers:
		var dt := delta
		if sw.placed and sw.pos.distance_to(eye) > 45.0:
			sw.far_t += delta   # (far in the murk: steered less often)
			if sw.far_t < 0.1:
				continue
			dt = sw.far_t
		sw.far_t = 0.0
		_step(sw, dt, eye)


func _step(sw: Swimmer, dt: float, eye: Vector3) -> void:
	var shape := planet.shape
	var R := planet.radius
	if not sw.placed or sw.pos.distance_to(eye) > RANGE * 0.9:
		if not _place(sw, eye):
			sw.node.visible = false
			return
		sw.node.visible = true
	var away := sw.pos - eye
	var scared := sw.flee > 0.0 and away.length() < sw.flee
	if scared != sw.scared:
		sw.scared = scared
		sw.mat.set_shader_parameter("pace", 2.2 if scared else 1.0)
	sw.goal_t -= dt
	if sw.goal_t <= 0.0 or sw.pos.distance_to(sw.goal) < 2.0 or (scared and away.normalized().dot((sw.goal - sw.pos).normalized()) < 0.3):
		sw.goal = _goal_for(sw, eye, scared)
		sw.goal_t = _rng.randf_range(6.0, 12.0)
	sw.floor_t -= dt
	if sw.floor_t <= 0.0:
		sw.floor_t = 0.3
		sw.floor_h = shape.height(sw.pos.normalized())
	var r := sw.pos.length()
	var up := sw.pos / r
	var want := (sw.goal - sw.pos).normalized() * sw.cruise * (2.6 if scared else 1.0)
	var alt := r - (R + sw.floor_h)
	if alt < sw.lo:
		want += up * (sw.lo - alt) * 1.5
	if r > R - 1.0:
		want -= up * (r - (R - 1.0) + 0.3) * 2.0
	sw.vel = sw.vel.lerp(want, minf(dt * sw.turn, 1.0))
	sw.pos += sw.vel * dt
	var fwd := sw.vel - up * sw.vel.dot(up) * 0.6   # (it pitches a little, not much)
	if fwd.length() < 0.02:
		fwd = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP)
	var bs := Basis.looking_at(fwd.normalized(), up)
	sw.node.transform = Transform3D(bs.scaled(Vector3.ONE * sw.scale), sw.pos)


## Somewhere for it to go: round you, at its depth over the floor (away from
## you, scared); where it is if all round's dry.
func _goal_for(sw: Swimmer, eye: Vector3, scared: bool) -> Vector3:
	var R := planet.radius
	for tries in 5:
		var base := eye
		var u := eye.normalized()
		var t := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _rng.randf() * TAU)
		var p := base + t * _rng.randf_range(8.0, 32.0)
		if scared:
			var a := sw.pos - eye
			a -= u * a.dot(u)
			p = sw.pos + (a.normalized() if a.length() > 0.01 else t) * 18.0 + t * 4.0
		var d := p.normalized()
		var h := planet.shape.height(d)
		if -h < sw.lo + 1.5:
			continue   # (too shallow - or land)
		var top := minf(R - 1.2, R + h + sw.hi)
		var r := minf(R + h + _rng.randf_range(sw.lo, sw.hi), top)
		return d * r
	return sw.pos


## Put it somewhere in the murk round you (none: false - no sea round here).
func _place(sw: Swimmer, eye: Vector3) -> bool:
	var R := planet.radius
	var u := eye.normalized()
	for tries in 6:
		var t := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _rng.randf() * TAU)
		var d := (eye + t * _rng.randf_range(26.0, 44.0)).normalized()
		var h := planet.shape.height(d)
		if -h < sw.lo + 2.0:
			continue
		sw.pos = d * minf(R + h + _rng.randf_range(sw.lo, sw.hi), R - 1.2)
		sw.vel = t.rotated(d, _rng.randf_range(-1.5, 1.5)) * sw.cruise
		sw.goal = sw.pos + sw.vel * 5.0
		sw.goal_t = 0.0
		sw.floor_h = h
		sw.placed = true
		return true
	sw.placed = false
	return false


## Everything of the sea let go (left it, or another one).
func _drop() -> void:
	_shells(true)
	_near_sight(false)
	if _design_task != -1:
		WorkerThreadPool.wait_for_task_completion(_design_task)
		_design_task = -1
	if _area_task != -1:
		WorkerThreadPool.wait_for_task_completion(_area_task)
		_area_task = -1
	if _root and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_mmis = []
	_rock_mmi = null
	_swimmers = []
	_meshes = []
	_mesh_todo = []
	_apply = []
	cells = {}
	shown_cells = []
	counts = {}
	_rocks = []
	design = {}
	_planned_at = Vector3(INF, INF, INF)
	_anchor = Vector3.ZERO
	planet = null


func _exit_tree() -> void:
	_drop()


# --- The design: the planet's sea life ---------------------------------------------------

## (Worker) A sea world's undersea life, from its seed and palette: the
## plants' kinds (mesh arrays, how thick, how deep, how big, how clustered),
## the fish (three kinds), a ray, an eel, a jellyfish.
static func design_of(shape: PlanetShape, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 53 + 17
	var L := shape.look
	var leaf: Color = L.get("land_mid", Color(0.3, 0.45, 0.25))
	if L.has("flora"):
		leaf = leaf.lerp(L["flora"], float(L.get("flora_k", 0.0)) * 0.6)
	var sand: Color = L.get("land_low", Color(0.7, 0.65, 0.5))
	var noise := FastNoiseLite.new()
	noise.seed = seed + 5
	noise.frequency = 1.0 / 70.0
	noise.fractal_octaves = 2
	var kelp_c := Color(0.42, 0.34, 0.12).lerp(leaf, 0.2)
	var grass_c := Color(0.22, 0.42, 0.18).lerp(leaf, 0.4)
	var plants: Array = []
	# [kind, arrays, per m^2, patchy 0..1, per cluster, spread m, min depth, max depth, size, height, solid]
	plants.append(_kind("kelp", _kelp(rng, kelp_c, 9.0), 0.015, 0.9, 14, 4.5, 4.0, 60.0, Vector2(0.6, 1.3), 9.0, 0.0))
	plants.append(_kind("seagrass", _seagrass(rng, grass_c), 0.09, 0.85, 30, 3.5, 0.5, 11.0, Vector2(0.7, 1.4), 1.0, 0.0, 44.0))
	plants.append(_kind("coral_branch", _coral_branch(rng, _vivid(rng)), 0.012, 0.95, 7, 2.5, 1.2, 18.0, Vector2(0.6, 1.5), 1.1, 0.4, 48.0))
	plants.append(_kind("coral_dome", _coral_dome(rng, _vivid(rng)), 0.008, 0.95, 5, 3.0, 1.0, 20.0, Vector2(0.5, 1.6), 0.6, 0.7, 48.0))
	plants.append(_kind("coral_fan", _coral_fan(rng, _vivid(rng)), 0.007, 0.9, 5, 3.0, 2.5, 26.0, Vector2(0.7, 1.4), 1.3, 0.0, 48.0))
	plants.append(_kind("sponge", _sponge(rng, _vivid(rng).lerp(Color(0.85, 0.6, 0.2), 0.4)), 0.007, 0.8, 4, 3.0, 3.0, 60.0, Vector2(0.6, 1.4), 0.9, 0.25, 56.0))
	plants.append(_kind("urchin", _urchin(rng, Color(0.12, 0.06, 0.12).lerp(_vivid(rng), 0.25)), 0.02, 0.7, 8, 2.0, 0.8, 40.0, Vector2(0.7, 1.3), 0.25, 0.0, 40.0))
	var fish: Array = []
	for i in 3:
		var hue := rng.randf()
		var back := Color.from_hsv(hue, rng.randf_range(0.3, 0.7), rng.randf_range(0.25, 0.5))
		var belly := Color(0.85, 0.88, 0.9).lerp(Color.from_hsv(hue, 0.3, 0.9), 0.3)
		var stripe := Color.from_hsv(fmod(hue + rng.randf_range(0.1, 0.5), 1.0), 0.8, 0.95)
		if i == 0:   # (one silver shoal fish, small and many)
			back = Color(0.2, 0.3, 0.38)
			belly = Color(0.88, 0.9, 0.92)
		var deep := rng.randf_range(1.0, 1.4) if i == 0 else rng.randf_range(1.5, 2.6)
		fish.append({"arrays": _fish(rng, back, belly, stripe, deep, i != 0), "size": rng.randf_range(0.16, 0.24) if i == 0 else rng.randf_range(0.25, 0.45),
			"n": 46 if i == 0 else rng.randi_range(14, 24), "spread": 3.5 if i == 0 else 2.2})
	var ray_c := Color.from_hsv(rng.randf_range(0.05, 0.6), rng.randf_range(0.2, 0.5), rng.randf_range(0.18, 0.32))
	var eel_c := Color.from_hsv(rng.randf_range(0.1, 0.4), rng.randf_range(0.4, 0.7), rng.randf_range(0.25, 0.45))
	var jelly_c := Color.from_hsv(rng.randf_range(0.45, 0.95), rng.randf_range(0.4, 0.8), 1.0)
	return {"seed": seed, "noise": noise, "plants": plants, "fish": fish,
		"rocks": 0.009, "rock_tone": sand.lerp(Color(0.32, 0.36, 0.3), 0.6).darkened(0.25),
		"ray": {"arrays": _ray(rng, ray_c), "size": 1.0},
		"eel": {"arrays": _eel(rng, eel_c, Color(0.75, 0.7, 0.45).lerp(eel_c, 0.3)), "size": rng.randf_range(3.5, 6.0)},
		"jelly": {"arrays": _jelly(rng, jelly_c), "size": rng.randf_range(0.28, 0.42), "glow": rng.randf_range(0.8, 1.6)}}


static func _kind(kind: String, arrays: Array, dens: float, patchy: float, per: int, spread: float, mn: float, mx: float, size: Vector2, h: float, solid: float, near := RANGE + CELL) -> Dictionary:
	return {"kind": kind, "arrays": arrays, "dens": dens, "patchy": patchy, "per": per, "spread": spread, "min": mn, "max": mx, "size": size, "h": h, "solid": solid, "near": near}


static func _vivid(rng: RandomNumberGenerator) -> Color:
	var hues := [0.0, 0.03, 0.08, 0.13, 0.55, 0.8, 0.88, 0.95]   # (reefs' reds, oranges, yellows, blues, purples, pinks)
	return Color.from_hsv(fmod(hues[rng.randi() % hues.size()] + rng.randf_range(-0.02, 0.02) + 1.0, 1.0), rng.randf_range(0.5, 0.85), rng.randf_range(0.6, 0.95))


# --- Meshes ------------------------------------------------------------------------------------

## A mesh being made: vertex colours; UV.x how supple (plants) or which part
## (animals), UV.y the height up the thing (0..1 of `h`), UV2.x `h`.
class Kit:
	var st := SurfaceTool.new()
	var flex := 0.0
	var h := 1.0

	func _init(height := 1.0) -> void:
		h = height
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func v(p: Vector3, c: Color) -> void:
		st.set_color(c)
		st.set_uv(Vector2(flex, p.y / h))
		st.set_uv2(Vector2(h, 0.0))
		st.add_vertex(p)

	## One triangle, its front facing `out` (Godot's: clockwise).
	func tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		if (c - a).cross(b - a).dot(out) >= 0.0:
			v(a, ca); v(b, cb); v(c, cc)
		else:
			v(a, ca); v(c, cc); v(b, cb)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, ca: Color, cb: Color) -> void:
		tri(a, b, c, out, ca, cb, cb)
		tri(a, c, d, out, ca, cb, ca)

	## A tapered tube from `a` to `b` (radii ra, rb), n sides; open ends.
	func tube(a: Vector3, b: Vector3, ra: float, rb: float, n: int, ca: Color, cb: Color) -> void:
		var ax := (b - a).normalized()
		var p := ax.cross(Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.FORWARD).normalized()
		var q := ax.cross(p)
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var d0 := p * cos(a0) + q * sin(a0)
			var d1 := p * cos(a1) + q * sin(a1)
			var out := (d0 + d1).normalized()
			tri(a + d0 * ra, b + d0 * rb, b + d1 * rb, out, ca, cb, cb)
			tri(a + d0 * ra, b + d1 * rb, a + d1 * ra, out, ca, cb, ca)

	## A ribbon (a blade, a fin) along `pts`, `w` wide at each, across `side`.
	func ribbon(pts: Array, w: Array, side: Vector3, ca: Color, cb: Color) -> void:
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var out := side.cross(b - a).normalized()
			var t0 := float(i) / (pts.size() - 1)
			var t1 := float(i + 1) / (pts.size() - 1)
			var c0 := ca.lerp(cb, t0)
			var c1 := ca.lerp(cb, t1)
			var wa: float = w[i]
			var wb: float = w[i + 1]
			tri(a - side * wa, a + side * wa, b + side * wb, out, c0, c0, c1)
			tri(a - side * wa, b + side * wb, b - side * wb, out, c0, c1, c1)

	## A lumpy ball, centre `c`, radii `r`; `shade` darkens it to its foot; `grooves` (a brain coral's).
	func lump(rng: RandomNumberGenerator, c: Vector3, r: Vector3, col: Color, seg := 6, grooves := 0.0, half := false) -> void:
		var bumps := [rng.randf() * TAU, rng.randf() * TAU, rng.randf_range(0.06, 0.18)]
		var rows := seg if not half else seg / 2 + 1
		var pts: Array = []
		var cols: Array = []
		for j in rows + 1:
			var row: Array = []
			var crow: Array = []
			var th := PI * j / seg
			for i in seg * 2:
				var ph := TAU * i / (seg * 2)
				var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
				var k: float = 1.0 + bumps[2] * sin(ph * 3.0 + bumps[0]) * sin(th * 2.0 + bumps[1])
				row.append(c + d * r * k)
				var shade := 0.72 + 0.32 * (1.0 - float(j) / seg)
				if grooves > 0.0:
					shade *= 1.0 - grooves * (0.5 + 0.5 * sin(th * 17.0 + sin(ph * 5.0) * 2.0) * sin(ph * 11.0 + th * 3.0))
				crow.append(col * Color(shade, shade, shade))
			pts.append(row)
			cols.append(crow)
		for j in rows:
			for i in seg * 2:
				var i2 := (i + 1) % (seg * 2)
				var out: Vector3 = (pts[j][i] + pts[j + 1][i2]) * 0.5 - c
				tri(pts[j][i], pts[j][i2], pts[j + 1][i2], out, cols[j][i], cols[j][i2], cols[j + 1][i2])
				tri(pts[j][i], pts[j + 1][i2], pts[j + 1][i], out, cols[j][i], cols[j + 1][i2], cols[j + 1][i])

	func done(smooth := false) -> Array:
		if smooth:
			st.index()
		st.generate_normals()
		return st.commit_to_arrays()


## Kelp: two or three stipes from a holdfast up to ~`tall` m, long wrinkled
## blades on short stalks all the way up, drooping - supple all through.
static func _kelp(rng: RandomNumberGenerator, col: Color, tall: float) -> Array:
	var k := Kit.new(tall)
	k.lump(rng, Vector3(0, 0.05, 0), Vector3(0.24, 0.14, 0.24), col.darkened(0.5), 4)
	k.flex = 1.0
	for s in rng.randi_range(2, 3):
		var hs := tall * rng.randf_range(0.7, 1.0)
		var a := rng.randf() * TAU
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.14)
		var segs := 6
		var pts: Array = []
		for i in segs + 1:
			var y := hs * i / segs
			pts.append(lean * y + Vector3(sin(i * 0.9 + a) * 0.12, y, cos(i * 0.7 + a) * 0.12) + Vector3(cos(a), 0, sin(a)) * 0.1)
		var stem := col.darkened(0.4)
		for i in segs:
			k.tube(pts[i], pts[i + 1], 0.035, 0.03, 3, stem, stem)
		var blades := int(hs / 0.55)
		for i in blades:
			var f := (i + 0.7) / blades
			var seg := mini(int(f * segs), segs - 1)
			var base: Vector3 = (pts[seg] as Vector3).lerp(pts[seg + 1], f * segs - seg)
			var ang := a + i * 2.39996
			var out := Vector3(cos(ang), 0.0, sin(ang))
			var len := rng.randf_range(0.7, 1.15) * lerpf(0.8, 1.2, f)
			var dir := (out * 0.8 + Vector3(0, rng.randf_range(0.25, 0.7), 0)).normalized()
			var side := dir.cross(Vector3.UP).normalized().rotated(dir, rng.randf_range(-0.5, 0.5))
			var bl: Array = []
			var ws: Array = []
			for j in 5:
				var g := j / 4.0
				bl.append(base + dir * len * g + Vector3(0, -0.3 * g * g * len, 0) + side * sin(g * 9.0 + ang) * 0.03)
				ws.append(lerpf(0.02, 0.11, sin(minf(g * 1.4, 1.0) * PI * 0.5)) * (1.0 - g * 0.55) if j < 4 else 0.012)
			var c0 := col.lerp(Color(0.62, 0.48, 0.14), rng.randf_range(0.0, 0.35))
			k.ribbon(bl, ws, side, c0.darkened(0.25), c0.lightened(0.08))
	return k.done(true)


## Sea grass: a tuft of long supple blades.
static func _seagrass(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(1.0)
	k.flex = 1.0
	for i in rng.randi_range(9, 15):
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var base := dir * rng.randf_range(0.0, 0.2)
		var h := rng.randf_range(0.45, 1.0)
		var lean := rng.randf_range(0.05, 0.3)
		var side := Vector3(-sin(a), 0, cos(a))
		var pts: Array = []
		for j in 4:
			var f := j / 3.0
			pts.append(base + dir * lean * f * f + Vector3(0, h * f, 0))
		var c := col.lightened(rng.randf_range(-0.12, 0.1))
		k.ribbon(pts, [0.022, 0.02, 0.016, 0.004], side, c.darkened(0.35), c.lightened(0.1))
	return k.done(true)


## A branching coral (staghorn): stone, a few stems forking up and out, paler tips.
static func _coral_branch(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(1.1)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf() * 0.8
		var dir := (Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.45)).normalized()
		_branch(k, rng, Vector3(cos(a), 0, sin(a)) * 0.05, dir, rng.randf_range(0.28, 0.38), 0.06, 2, col)
	k.lump(rng, Vector3(0, 0.02, 0), Vector3(0.18, 0.08, 0.18), col.darkened(0.35), 4)
	return k.done(true)


static func _branch(k: Kit, rng: RandomNumberGenerator, at: Vector3, dir: Vector3, len: float, r: float, depth: int, col: Color) -> void:
	var end := at + dir * len
	var tip := col.lightened(0.35) if depth == 0 else col
	k.tube(at, end, r, r * 0.75, 4, col.darkened(0.1 * depth), tip)
	if depth == 0:
		k.tube(end, end + dir * r * 1.4, r * 0.75, 0.0, 4, tip, tip.lightened(0.15))   # (a blunt tip)
		return
	for i in 2:
		var side := dir.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		var nd := (dir.rotated(side, rng.randf_range(0.35, 0.7)) + Vector3.UP * 0.3).normalized()
		_branch(k, rng, end, nd, len * rng.randf_range(0.7, 0.9), r * 0.75, depth - 1, col)


## Boulder corals: a cluster of squat lumpy heads, grooved.
static func _coral_dome(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(0.6)
	k.lump(rng, Vector3(0, 0.1, 0), Vector3(0.5, 0.42, 0.46), col, 7, 0.4, true)
	for i in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.18, 0.3)
		k.lump(rng, Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.45, 0.6) + Vector3(0, 0.04, 0), Vector3(r, r * 0.8, r), col.lerp(Color.from_hsv(col.h + 0.08, col.s, col.v), 0.5), 5, 0.35, true)
	return k.done(true)


## A sea fan (gorgonian): a flat lace of thin branches in one plane, swaying a little.
static func _coral_fan(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(1.3)
	k.flex = 0.3
	_fan(k, rng, Vector3.ZERO, Vector3.UP, 0.32, 0.028, 5, col)
	return k.done(true)


static func _fan(k: Kit, rng: RandomNumberGenerator, at: Vector3, dir: Vector3, len: float, r: float, depth: int, col: Color) -> void:
	var end := at + dir * len
	k.tube(at, end, r, r * 0.8, 3, col.darkened(0.2), col.lightened(0.08 * (5 - depth)))
	if depth == 0:
		return
	for s: float in [-1.0, 1.0]:
		var nd := dir.rotated(Vector3.BACK, s * rng.randf_range(0.3, 0.75)).normalized()
		nd = (nd + Vector3.UP * 0.2).normalized()
		_fan(k, rng, end, nd, len * rng.randf_range(0.65, 0.85), r * 0.8, depth - 1, col)


## Barrel and tube sponges: a cluster of open tubes, bulging, a lip at the
## rim (their insides darker - the shader's back faces).
static func _sponge(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(0.9)
	for i in rng.randi_range(3, 5):
		var at := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.35, 0.85)
		var r := rng.randf_range(0.08, 0.15)
		var tilt := Vector3(at.x, 0, at.z) * 0.5
		var c := col.lerp(Color.from_hsv(fmod(col.h + 0.06, 1.0), col.s, col.v), rng.randf()).lightened(rng.randf_range(-0.1, 0.12))
		var mid := at + (Vector3(0, h, 0) + tilt) * 0.45
		var top := at + Vector3(0, h, 0) + tilt
		k.tube(at, mid, r * 0.75, r * 1.2, 7, c.darkened(0.35), c)
		k.tube(mid, top, r * 1.2, r * 1.0, 7, c, c.lightened(0.1))
		k.tube(top, top + (top - mid).normalized() * 0.03, r * 1.0, r * 1.12, 7, c.lightened(0.1), c.lightened(0.2))
	return k.done(true)


## A sea urchin: a dark ball of spines.
static func _urchin(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(0.25)
	k.lump(rng, Vector3(0, 0.1, 0), Vector3(0.12, 0.09, 0.12), col, 5)
	for i in 18:
		var y := 1.0 - (i + 0.5) / 18.0 * 1.3
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		var a := i * 2.39996
		var d := Vector3(cos(a) * rr, y, sin(a) * rr).normalized()
		if d.y < -0.3:
			continue
		var base := Vector3(0, 0.1, 0) + d * 0.09
		k.tube(base, base + d * rng.randf_range(0.12, 0.2), 0.012, 0.0, 3, col, col.lightened(0.25))
	return k.done(true)


## A fish, a metre long (scaled): a lofted body, nose to -z, darker back,
## pale belly, a stripe along its flank, a forked tail, fins, eyes.
static func _fish(rng: RandomNumberGenerator, back: Color, belly: Color, stripe: Color, deep: float, striped: bool) -> Array:
	var k := Kit.new(1.0)
	k.flex = 1.0   # (the body: silvery)
	var zs := [-0.5, -0.45, -0.36, -0.22, -0.05, 0.12, 0.25, 0.33]
	var rs := [0.0, 0.04, 0.07, 0.085, 0.082, 0.062, 0.035, 0.016]
	var n := 8
	var rings: Array = []
	var cols: Array = []
	for j in zs.size():
		var row: Array = []
		var crow: Array = []
		for i in n:
			var a := TAU * i / n
			var s := sin(a)
			row.append(Vector3(cos(a) * rs[j], s * rs[j] * deep, zs[j]))
			var c: Color = belly.lerp(back, smoothstep(-0.3, 0.5, s))
			if striped and absf(s) < 0.28 and j > 1 and j < 6:
				c = c.lerp(stripe, 0.75)
			crow.append(c)
		rings.append(row)
		cols.append(crow)
	for j in zs.size() - 1:
		for i in n:
			var i2 := (i + 1) % n
			var out: Vector3 = (rings[j][i] + rings[j + 1][i2]) * 0.5 - Vector3(0, 0, (zs[j] + zs[j + 1]) * 0.5)
			k.tri(rings[j][i], rings[j][i2], rings[j + 1][i2], out, cols[j][i], cols[j][i2], cols[j + 1][i2])
			k.tri(rings[j][i], rings[j + 1][i2], rings[j + 1][i], out, cols[j][i], cols[j + 1][i2], cols[j + 1][i])
	k.flex = 0.0   # (fins)
	var fin := back.darkened(0.15)
	var tailc := fin.lerp(stripe, 0.4 if striped else 0.1)
	var t0 := Vector3(0, 0, 0.31)
	k.tri(t0, Vector3(0, 0.16 * deep, 0.52), Vector3(0, 0.02, 0.44), Vector3.RIGHT, fin, tailc, tailc)
	k.tri(t0, Vector3(0, -0.16 * deep, 0.52), Vector3(0, -0.02, 0.44), Vector3.RIGHT, fin, tailc, tailc)
	var ry := 0.085 * deep
	k.tri(Vector3(0, ry * 0.95, -0.16), Vector3(0, ry + 0.08 * deep, -0.02), Vector3(0, ry * 0.8, 0.12), Vector3.RIGHT, fin, tailc, fin)
	k.tri(Vector3(0, -ry * 0.9, 0.02), Vector3(0, -ry - 0.04 * deep, 0.12), Vector3(0, -ry * 0.6, 0.18), Vector3.RIGHT, fin, fin, fin)
	for s: float in [-1.0, 1.0]:
		k.tri(Vector3(s * 0.07, -0.02, -0.2), Vector3(s * 0.16, -0.06, -0.08), Vector3(s * 0.07, -0.04, -0.1), Vector3.UP, fin, tailc, fin)
		k.lump(rng, Vector3(s * 0.042, 0.022 * deep, -0.4), Vector3.ONE * 0.016, Color(0.02, 0.02, 0.03), 3)
	return k.done(true)


## A ray: a broad flat diamond of wings (span x -1..1, swept back), a pale
## belly, spots on its back, a long thin tail, its eyes on top.
static func _ray(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(1.0)
	var nu := 16
	var ns := 6
	var belly := Color(0.85, 0.84, 0.8)
	var spots := rng.randf() < 0.7
	for side: float in [1.0, -1.0]:   # (top, bottom)
		var grid: Array = []
		var cg: Array = []
		for i in nu + 1:
			var u := -1.0 + 2.0 * i / nu
			var au := absf(u)
			var chord := 1.15 * pow(1.0 - au, 0.75) + 0.04
			var lead := -0.5 + 0.42 * au
			var row: Array = []
			var crow: Array = []
			for j in ns + 1:
				var s := float(j) / ns
				var th := 0.1 * pow(1.0 - au, 1.5) * sin(PI * s)
				var p := Vector3(u, side * th * (1.0 if side > 0 else 0.55), lead + chord * s)
				row.append(p)
				var c := col
				if side < 0:
					c = belly
				elif spots and fmod(absf(sin(u * 37.0 + s * 19.0) * 43758.5), 1.0) > 0.78:
					c = col.lightened(0.45)
				crow.append(c)
			grid.append(row)
			cg.append(crow)
		var out := Vector3.UP * side
		for i in nu:
			for j in ns:
				k.tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], out, cg[i][j], cg[i + 1][j], cg[i + 1][j + 1])
				k.tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1], out, cg[i][j], cg[i + 1][j + 1], cg[i][j + 1])
	k.tube(Vector3(0, 0, 0.6), Vector3(0, 0.0, 1.9), 0.03, 0.004, 4, col, col.darkened(0.3))
	for s: float in [-1.0, 1.0]:
		k.lump(rng, Vector3(s * 0.12, 0.07, -0.32), Vector3.ONE * 0.025, Color(0.03, 0.03, 0.03), 3)
		k.tri(Vector3(s * 0.08, 0.0, -0.46), Vector3(s * 0.16, -0.01, -0.62), Vector3(s * 0.2, 0.0, -0.42), Vector3.UP, col, col.darkened(0.2), col)
	return k.done(true)


## An eel (or a sea serpent, the big ones): a long body, a metre (scaled),
## head at -z, mottled, a fin ribbon down its back.
static func _eel(rng: RandomNumberGenerator, col: Color, belly: Color) -> Array:
	var k := Kit.new(1.0)
	var n := 28
	var sides := 7
	var rings: Array = []
	var cols: Array = []
	for j in n + 1:
		var f := float(j) / n
		var z := -0.5 + f
		var r := 0.032 * (0.75 + 0.25 * sin(minf(f * 6.0, PI * 0.5))) * (1.0 - pow(f, 2.2) * 0.9)
		if f < 0.04:
			r *= f / 0.04 * 0.7 + 0.3
		var row: Array = []
		var crow: Array = []
		for i in sides:
			var a := TAU * i / sides
			row.append(Vector3(cos(a) * r, sin(a) * r * 1.15, z))
			var c: Color = belly.lerp(col, smoothstep(-0.4, 0.3, sin(a)))
			if fmod(absf(sin(f * 91.0 + a * 3.0) * 43758.5), 1.0) > 0.8:
				c = c.darkened(0.35)
			crow.append(c)
		rings.append(row)
		cols.append(crow)
	for j in n:
		for i in sides:
			var i2 := (i + 1) % sides
			var out: Vector3 = (rings[j][i] + rings[j + 1][i2]) * 0.5 - Vector3(0, 0, -0.5 + (j + 0.5) / n)
			k.tri(rings[j][i], rings[j][i2], rings[j + 1][i2], out, cols[j][i], cols[j][i2], cols[j + 1][i2])
			k.tri(rings[j][i], rings[j + 1][i2], rings[j + 1][i], out, cols[j][i], cols[j + 1][i2], cols[j + 1][i])
	var fin: Array = []
	var ws: Array = []
	for j in range(4, n + 1, 3):
		var f := float(j) / n
		fin.append(Vector3(0, 0.03 * (1.0 - f * 0.8) + 0.006, -0.5 + f))
		ws.append(0.0)
	# (the fin: a ribbon standing up - its "width" upward)
	for j in fin.size() - 1:
		var a: Vector3 = fin[j]
		var b: Vector3 = fin[j + 1]
		var hgt := 0.014
		k.quad(a, a + Vector3(0, hgt, 0), b + Vector3(0, hgt, 0), b, Vector3.RIGHT, col.darkened(0.2), col.lightened(0.1))
	for s: float in [-1.0, 1.0]:
		k.lump(rng, Vector3(s * 0.02, 0.016, -0.475), Vector3.ONE * 0.007, Color(0.85, 0.75, 0.2), 3)
	return k.done(true)


## A jellyfish (unit, scaled): a domed bell open beneath (UV.x 0), trailing
## tentacles and frilled arms (UV.x 1); its glow is the shader's.
static func _jelly(rng: RandomNumberGenerator, col: Color) -> Array:
	var k := Kit.new(1.0)
	var sides := 14
	var rows := 5
	var pts: Array = []
	for j in rows + 1:
		var th := (PI * 0.5) * j / rows
		var row: Array = []
		for i in sides:
			var a := TAU * i / sides
			var r := sin(th) * (1.0 + 0.06 * sin(a * 7.0) * float(j) / rows)
			row.append(Vector3(cos(a) * r, cos(th) * 0.75 - 0.1 * pow(float(j) / rows, 3.0), sin(a) * r))
		pts.append(row)
	for j in rows:
		for i in sides:
			var i2 := (i + 1) % sides
			var out: Vector3 = (pts[j][i] + pts[j + 1][i2]) * 0.5
			var c0 := col.lightened(0.3 * (1.0 - float(j) / rows))
			var c1 := col.lightened(0.3 * (1.0 - float(j + 1) / rows))
			k.tri(pts[j][i], pts[j][i2], pts[j + 1][i2], out, c0, c0, c1)
			k.tri(pts[j][i], pts[j + 1][i2], pts[j + 1][i], out, c0, c1, c1)
	k.flex = 1.0
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0
		var top := Vector3(cos(a) * 0.92, -0.08, sin(a) * 0.92)
		var len := rng.randf_range(1.6, 2.8)
		var pts2: Array = []
		for j in 6:
			pts2.append(top + Vector3(0, -len * j / 5.0, 0) - Vector3(cos(a), 0, sin(a)) * 0.15 * j / 5.0)
		k.ribbon(pts2, [0.025, 0.02, 0.016, 0.012, 0.008, 0.002], Vector3(-sin(a), 0, cos(a)), col, col.darkened(0.3))
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var pts3: Array = []
		var ws: Array = []
		for j in 6:
			var f := j / 5.0
			pts3.append(Vector3(cos(a) * 0.12, -0.05 - 1.1 * f, sin(a) * 0.12) + Vector3(sin(f * 9.0 + a) * 0.06, 0, cos(f * 7.0 + a) * 0.06))
			ws.append(0.09 * (1.0 - f * 0.6))
		k.ribbon(pts3, ws, Vector3(-sin(a), 0, cos(a)), col.lightened(0.25), col)
	return k.done()


# --- First use: drawn at the title (CosmosWarm) -------------------------------------------

## One of each of the sea's materials and meshes kinds, in CosmosWarm's viewport.
static func warm(vp: Node) -> void:
	var rng := RandomNumberGenerator.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	for sh in [FX, GLOW]:
		var fx := MeshInstance3D.new()
		fx.mesh = q
		fx.material_override = fx_material(sh)
		vp.add_child(fx)
	var sn := MultiMeshInstance3D.new()
	sn.multimesh = snow_multimesh(4)
	sn.material_override = snow_material()
	vp.add_child(sn)
	var pm := ShaderMaterial.new()
	pm.shader = PLANTS
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _seagrass(rng, Color.SEA_GREEN))
	mm.mesh = m
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.4), Vector3(0.4, -0.5, 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = pm
	vp.add_child(mmi)
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_custom_data = true
	var fmesh := ArrayMesh.new()
	fmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _fish(rng, Color.SLATE_GRAY, Color.WHITE, Color.GOLD, 1.5, true))
	fm.mesh = fmesh
	fm.instance_count = 1
	fm.set_instance_transform(0, Transform3D.IDENTITY)
	fm.set_instance_custom_data(0, Color(0.5, 0.5, 0.5, 0.3))
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fm
	fmi.material_override = life_material(0, 0.4, 0.2)
	fmi.position = Vector3(-0.4, 0.3, 0.5)
	vp.add_child(fmi)
	for kind in [1, 2]:   # (a ray, an eel: the same shader, as plain meshes)
		var mi := MeshInstance3D.new()
		mi.mesh = fmesh
		mi.material_override = life_material(kind, 1.0, 0.0)
		mi.position = Vector3(-0.4 + kind * 0.3, -0.3, 0.5)
		mi.scale = Vector3.ONE * 0.4
		vp.add_child(mi)
