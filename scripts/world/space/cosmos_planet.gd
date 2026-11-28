class_name CosmosPlanet
extends Node3D
## A planet (or moon) of the 3D game: real ground all the way down. Its
## surface is a cube's six faces bent onto the sphere, each a quadtree of
## terrain patches (PATCH x PATCH quads of PlanetShape.height): far away a
## handful of coarse patches, coming closer they split into finer ones - down
## to a metre between vertices underfoot - so the planet you see from orbit
## IS the ground you land on, nothing swapped. Patches are built on worker
## threads (a few at a time, their meshes made on the main thread within a
## budget), patches beyond the horizon aren't drawn, and children replace
## their parent only once all four are built (no holes; skirts hide the
## seams between levels). Gas giants are a sphere of cloud bands (no ground).
## Around it: its sea (water, an ice sheet or lava), clouds and an
## atmosphere shell (scattering worked out per pixel against the depth
## buffer: the halo from space, the sky and the haze on the ground).

const PATCH := 24               # quads a patch side
const SPLIT := 2.2              # split a patch closer than this many of its sizes
const KEEP := 1.2               # (hysteresis: merge only beyond SPLIT x KEEP)
const MIN_PATCH_M := 34.0       # the finest patch (m across): ~1.4 m a quad
const MAX_TASKS := 10           # patches building at once (all planets share this)
const ROCKS_A_PATCH := 4        # boulders on a finest patch (up to; a few patches a field of them)
const VISIT_BUDGET_US := 300    # main-thread time a frame visiting the quadtree (a planet)
const MESH_BUDGET_US := 1500    # main-thread time a frame turning built patches into meshes (all planets)
const MESH_BUDGET_SLOW_US := 350   # (on foot, slow: less a frame, over more frames)
const VISIT_BUDGET_SLOW_US := 200
static var visit_budget_us := VISIT_BUDGET_US
const TERRAIN := preload("res://shaders/world/terrain.gdshader")
const WATER := preload("res://shaders/world/water.gdshader")
const ATMO := preload("res://shaders/world/atmosphere.gdshader")
const CLOUDS := preload("res://shaders/world/clouds.gdshader")
const GAS := preload("res://shaders/world/gas_giant.gdshader")
const RING := preload("res://shaders/world/ring.gdshader")

static var tasks := 0           # building now, all planets
static var deadline_us := 0     # (meshes made until then: Cosmos sets it each frame)

var rec := {}
var shape: PlanetShape
var radius := 1000.0
var max_level := 6
var sun_dir := Vector3.UP       # (to the star, world - set by Cosmos)
var material: ShaderMaterial
## The web's renderer (Compatibility): its terrain without instance uniforms (terrain.gdshader).
static var COMPAT := RenderingServer.get_current_rendering_method() == "gl_compatibility"
var atmo_radius := 0.0
var _roots: Array = []
var _busy: Array = []           # patches whose builds are running
var _sea_mi: MeshInstance3D
var _sea_low: Mesh
var _sea_high: Mesh
var _cam_local := Vector3(1e9, 0, 0)
var _horizon := PI
var deepest_hint := 0
var _stack: Array = []          # the visit under way: patches still to visit (a slice a frame)
var _sight_cos := PackedFloat32Array()
var _cam_dir := Vector3.RIGHT
var patches_made := 0
var _rock_mat: ShaderMaterial
var flora: Array = []           # the species (CosmosFlora.design), built on a worker at setup
var flora_ready := false
var _flora_task := -1
var _cave_task := -1
var caves_ready := false        # (its caves carved in: PlanetShape.caves)
static var _caves_frame := -1
var _flora_meshes: Array = []   # (the grass's and flowers' meshes - null for the trees and shrubs: _flora_lods)
var _flora_mk := -1             # (the species whose meshes are made next)
var _flora_mat: ShaderMaterial
var _leaf_mat: ShaderMaterial
## The trees and shrubs to the horizon (FloraLods): each patch from level
## _stand_top down carries its plants (its parent's on it and its own), built on
## a worker once its ground is in and its parent's plants are known; each
## species' chain of meshes (_flora_lods: [mesh, lo, hi]), the impostors drawn
## from one atlas (_imp_tex).
var _flora_lods: Array = []
var _imp_atlas := {}
var _imp_tex: ImageTexture
var _stand_top := 0
var _stand_wait: Array = []     # patches whose plants are to be (re)built
var _stand_busy: Array = []     # ...being built
var _leaving := false           # (leaving the tree: the queued plant tasks end at once)
var _stop := [false]            # (...and the impostors' baking)
static var _rock_mesh: Mesh


static func rock_mesh() -> Mesh:
	if _rock_mesh == null:
		_rock_mesh = CosmosRocks._rock_mesh(77)[0]
	return _rock_mesh


class Patch:
	var face := 0
	var level := 0
	var a0 := 0.0
	var b0 := 0.0
	var span := 2.0
	var centre := Vector3.ZERO  # planet-local, on the ground
	var dir := Vector3.UP
	var size := 1.0             # metres across
	var mi: MeshInstance3D
	var task := -1
	var arrays: Array = []
	var kids: Array = []
	var ready := false
	var shown := false          # (its mesh drawn now)
	var sub := false            # (something under it drawn now)
	var rock_xf: Array = []     # boulders on it (transforms, relative to its centre) - while building
	var flora_xf := {}          # species index -> its plants' transforms - while building
	var rock_buf := PackedFloat32Array()   # ...then as MultiMesh buffers
	var rock_n := 0
	var flora_buf := {}
	var rocks: Array = []       # [planet-local position, radius] (collisions)
	var rocks_new: Array = []   # (while building: the next rocks - swapped in when it's in)
	var digs := PackedFloat64Array()   # (the digs near it, a snapshot for its build)
	var again := false          # (dug again while building: built once more)
	var parent: Patch
	var dead := false           # (merged away: its parent's drawn again)
	var hs := PackedFloat32Array()   # its ground's heights (its grid, PATCH + 3 a side - its plants stand on it)
	var stands = null           # its trees and shrubs: FloraLods records (its parent's on it and its own) - made once, kept
	var stand_task := -1
	var stand_again := false
	var stand_res: Array = []   # (the worker's: [stands if new, buffers, solids])
	var fl: Node3D              # (its impostors drawn: shown with it)
	var stand_bufs := {}        # (its plants as MultiMesh buffers: FloraLods.build - the near field's source)
	var stand_ok := false       # (its plants built: its parent's give way to it only then)
	var rock_only: Array = []   # (its boulders - rocks: these and its trees' trunks)
	var stand_solids: Array = []


var towns: Array = []           # CosmosTown.sites: where its towns stand


func setup(record: Dictionary, noise: Texture3D) -> void:
	rec = record
	name = str(rec.get("name", "Planet")).replace(" ", "_")
	shape = PlanetShape.of(rec, false)
	radius = shape.radius

	# (the ground dug before: the save's list, the shape's own from now on)
	var all_digs: Dictionary = CosmosGame.extra.get("digs", {})
	var pid := str(rec.get("id", name))
	var saved: Array = all_digs.get(pid, [])
	for e in saved:
		shape.add_dig(Vector3(e[0], e[1], e[2]).normalized(), float(e[3]), float(e[4]))
	shape.saved = saved
	all_digs[pid] = saved
	CosmosGame.extra["digs"] = all_digs
	max_level = clampi(ceili(log(2.0 * radius / MIN_PATCH_M) / log(2.0)), 3, 12)
	var L: Dictionary = shape.look
	var atmo_col: Color = L.get("atmosphere", Color(0.5, 0.7, 1.0))
	var atmo_k := float(L.get("atmo_strength", 0.5))
	if shape.kind == "gas":
		var m := ShaderMaterial.new()
		m.shader = GAS
		for k in ["gas_a", "gas_b", "gas_c", "gas_d", "band_count", "band_turb", "storm", "storm_pos", "storm_size", "storm_color", "seed"]:
			if L.has(k):
				m.set_shader_parameter(k, L[k])
		m.set_shader_parameter("noise_tex", noise)
		material = m
		_ball(radius, 128, 64, m, "Body")
		var ringed := float(L.get("rings", 0.0)) > 0.0
		_spin_setup(Vector3(float(L.get("incline", 0.3)) * 0.6, 0.0, float(L.get("tilt", 0.2))) if ringed else Vector3.INF)   # (a ringed giant turns round its rings' axis)
		if ringed:
			_add_rings(L)
		atmo_radius = radius * 1.04
		_add_atmosphere(atmo_col, atmo_k * 0.7)
		return
	material = ShaderMaterial.new()
	material.shader = TERRAIN
	for k in ["land_low", "land_mid", "land_high", "land_peak", "biome", "biome_color", "ice_cover", "ice_color",
			"lava", "lava_color", "lava_hot", "water_shallow", "water_deep"]:
		if L.has(k):
			material.set_shader_parameter(k, L[k])
	# (its ground close up: Greece's on the green worlds - terra rossa, limestone, dry grass; a touch of it elsewhere)
	material.set_shader_parameter("greek", {"ocean": 1.0, "ice": 0.25, "volcanic": 0.3, "moon": 0.4}.get(str(rec.get("type", "")), 0.5))
	material.set_shader_parameter("amp", shape.amp)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("sea", shape.sea)
	material.set_shader_parameter("noise_tex", noise)
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = preload("res://shaders/world/rock.gdshader")
	_rock_mat.set_shader_parameter("noise_tex", noise)
	var lh: Color = L.get("land_high", Color(0.4, 0.38, 0.35))
	_rock_mat.set_shader_parameter("tone", lh.lerp(Color(0.42, 0.4, 0.38), 0.4))
	# The towns (CosmosTown): where they stand, their ground levelled - before any ground is built.
	_spin_setup()
	towns = CosmosTown.sites(shape, rec, Galaxy.owner_of(str(rec.get("system", Galaxy.current_system))))
	_morning_start()
	shape.set_flats(CosmosTown.flats_of(towns, radius))
	# (a sea world's lakes and rivers: PlanetWater, made on a worker - its towns known: kept off them - the
	# ground built once they're in, then its caves: _water_in)
	water_ready = not (shape.kind == "rocky" and shape.sea == 1)
	if not water_ready:
		var wk := _water_key()
		if _water_cache.has(wk):
			shape.water = _water_cache[wk]
			water_ready = true
		else:
			var sh := shape
			var out := {}
			_water_out = out
			var stop := _stop
			_water_task = WorkerThreadPool.add_task(func():
				if not stop[0]:   # (its world gone before it began: a wait on it runs it here - nothing to do)
					out["w"] = PlanetWater.make(sh, stop), true, "planet water")
	if shape.kind == "rocky" and water_ready:   # (its caves and dungeons: made on a worker - its towns known: kept clear of them - carved in when done, _caves_in)
		_caves_start()
	_flora_mat = ShaderMaterial.new()
	_flora_mat.shader = preload("res://shaders/world/flora.gdshader")
	_leaf_mat = ShaderMaterial.new()   # (the trees: their leaf cards cut into leaves - CosmosFlora)
	_leaf_mat.shader = preload("res://shaders/world/leaf_flora.gdshader")
	var fseed := int(rec.get("seed", 1))
	var ftype := str(rec.get("type", "rocky"))
	_flora_task = WorkerThreadPool.add_task(_design_flora.bind(fseed, ftype), true, "planet flora")
	# (the coarsest level carrying trees: its plants reach as far as the furthest trees)
	_stand_top = 0
	for lv in range(max_level, -1, -1):
		if FloraLods.LEVEL_REACH * _level_size(lv) >= FloraLods.TREE_REACH:
			_stand_top = lv
			break
	for f in 6:
		var p := Patch.new()
		p.face = f
		p.a0 = -1.0
		p.b0 = -1.0
		p.span = 2.0
		_place(p)
		_roots.append(p)
		if water_ready:
			_start(p)
	if shape.sea > 0:
		_add_sea(L, noise)
	if water_ready:
		_waters_add()
	atmo_radius = radius + maxf(shape.top() * 2.5, radius * 0.06)
	var has_air := shape.kind == "rocky" and atmo_k > 0.3
	if has_air or float(L.get("clouds", 0.0)) > 0.05 and atmo_k > 0.3:
		_add_clouds(L, noise)
	weather = PlanetWeather.of(rec, shape, has_air)
	_add_atmosphere(atmo_col, atmo_k)


## Built enough to be seen: every face's first patch is in.
func settled() -> bool:
	if not water_ready:
		_water_in()
		if not water_ready:
			return false
	if not caves_ready:
		_caves_in()
		if not caves_ready:
			return false
	for p: Patch in _roots:
		if not p.ready:
			return false
	return true


## (Worker) Its species (CosmosFlora) and their impostors' atlas (FloraLods).
func _design_flora(fseed: int, ftype: String) -> void:
	if _stop[0]:
		return   # (its world gone before this began: a wait on a task not started runs it on the waiting thread - nothing to do)
	var fl := CosmosFlora.design(shape, fseed, ftype, _stop)
	if _stop[0]:
		return
	_imp_atlas = FloraLods.bake(fl, _stop)
	flora = fl


## A level's patches' size (m).
func _level_size(lv: int) -> float:
	return radius * (2.0 / pow(2.0, lv)) * 0.9


func _place(p: Patch) -> void:
	var ax := PlanetShape.face_axes(p.face)
	p.dir = PlanetShape.face_dir(ax[0], ax[1], ax[2], p.a0 + p.span * 0.5, p.b0 + p.span * 0.5)
	p.centre = p.dir * (radius + shape.surface(p.dir))
	p.size = radius * p.span * 0.9


func _start(p: Patch) -> void:
	tasks += 1
	_busy.append(p)
	p.digs = shape.digs_near(p.centre, p.size * 0.8, true) if p.level >= max_level - DIG_LEVELS and shape.dig_n > 0 else PackedFloat64Array()   # (those that open its face)
	p.task = WorkerThreadPool.add_task(_build.bind(p, p.face, p.a0, p.b0, p.span, p.centre), true, "planet patch")


## Its lakes and rivers (PlanetWater): made once a run a world (the same ground, the same water).
static var _water_cache := {}
var water_ready := true          # (its lakes and rivers in - false while a sea world's are being made)
var waters: CosmosWaters         # (its lakes' and rivers' surfaces, their sounds)
var _water_task := -1
var _water_out := {}


func _water_key() -> String:
	return "%s:%d:%d" % [str(rec.get("id", name)), int(rec.get("seed", 0)), towns.size()]


## (Main) Its lakes and rivers in: the ground built from now on with them, its caves made.
func _water_in() -> void:
	if water_ready or _water_task == -1 or not WorkerThreadPool.is_task_completed(_water_task):
		return
	WorkerThreadPool.wait_for_task_completion(_water_task)
	_water_task = -1
	var w: PlanetWater = _water_out.get("w")
	_water_out = {}
	if w != null and w.stats.has("rivers"):   # (made whole - not given up)
		shape.water = w
		if _water_cache.size() >= 8:
			_water_cache.erase(_water_cache.keys()[0])
		_water_cache[_water_key()] = w
	water_ready = true
	for p: Patch in _roots:
		if p.task == -1 and not p.ready:
			_start(p)
	_caves_start()
	_waters_add()


func _caves_start() -> void:
	if _cave_task == -1 and not caves_ready and shape.kind == "rocky":
		var sh := shape
		_cave_task = WorkerThreadPool.add_task(func(): sh.make_caves(), true, "planet caves")


## Its lakes' and rivers' surfaces (CosmosWaters: built on a worker, near you).
func _waters_add() -> void:
	if waters == null and shape.kind == "rocky" and shape.sea == 1:
		waters = CosmosWaters.new()
		waters.planet = self
		add_child(waters)


## The caves made (a worker): carved in - the ground where they open built again
## (its plants and boulders out of the way), the shader's cuts and the voxels
## round you told.
func _caves_in() -> void:
	if _cave_task == -1 or not WorkerThreadPool.is_task_completed(_cave_task):
		if _cave_task == -1 and shape.kind != "rocky":
			caves_ready = true
		return
	if Engine.get_process_frames() == _caves_frame:
		return   # (another world's caves carved in this frame: one a frame)
	_caves_frame = Engine.get_process_frames()
	WorkerThreadPool.wait_for_task_completion(_cave_task)
	_cave_task = -1
	shape.merge_caves()
	caves_ready = true
	if voxels == null:
		voxels = CosmosVoxels.new()
		voxels.planet = self
		add_child(voxels)
	for c in shape.caves:
		_rebuild_near(c["mouth"], 12.0)
	_cuts_at = Vector3(INF, INF, INF)   # (the shader's cuts and the voxels made again at the next visit)
	voxels._at = Vector3(INF, INF, INF)


## The finest levels that know of the carves near them (their plants and
## boulders go; the terrain shader leaves the carves undrawn).
const DIG_LEVELS := 2
const CUTS := 128               # the carves the terrain shader knows (the nearest)
var voxels: CosmosVoxels        # the ground where it's carved (made at the first carve)
var _cuts: Array = []           # [distance, middle, radius] - the shader's
var _cuts_at := Vector3(INF, INF, INF)
var _cuts_wait: Array = []      # [middle, radius, msec] - carves whose dug ground is still being built (CosmosVoxels)


## A carve at `local` (planet-local), `r` wide: the patches there built again
## (on workers - each swapped in when done; a build under way runs once more
## after), the voxels' chunks there meshed again, the shader told.
func redig(local: Vector3, r: float) -> void:
	if voxels == null:
		voxels = CosmosVoxels.new()
		voxels.planet = self
		add_child(voxels)
	voxels.carve(local, r)
	_cuts_wait.append([local, r, Time.get_ticks_msec()])   # (the shader told once the dug ground's there: not before - the sky through the hole meanwhile)
	_rebuild_near(local, r)


## (Each frame, by the voxels) The carves waiting for their dug ground: each
## sent to the shader (the ground there undrawn) once the voxel chunks round it
## are built - the old ground drawn till the new one's in.
func cuts_settle() -> void:
	if _cuts_wait.is_empty():
		return
	var sent := false
	for i in range(_cuts_wait.size() - 1, -1, -1):
		var w: Array = _cuts_wait[i]
		if voxels.ready_at(w[0], w[1]) or Time.get_ticks_msec() - int(w[2]) > 2000:
			_cuts_wait.remove_at(i)
			_cuts.append([0.0, w[0], w[1]])
			sent = true
	if sent:
		if _cuts.size() > CUTS:
			_cuts.sort_custom(func(a, b): return a[1].distance_to(_cam_local) < b[1].distance_to(_cam_local))
			_cuts.resize(CUTS)
		_send_cuts()


## The finest patches within `r` of planet-local `local` built again (their
## boulders and plants: ground built over - CosmosStructure - or dug); the
## coarser ones' trees and shrubs placed again.
func _rebuild_near(local: Vector3, r: float) -> void:
	var stack := _roots.duplicate()
	while not stack.is_empty():
		var p: Patch = stack.pop_back()
		if p.centre.distance_to(local) > p.size * 0.8 + r + 4.0:
			continue
		stack.append_array(p.kids)
		if p.level < max_level - DIG_LEVELS or not p.ready:
			if p.stand_ok:   # (the coarser ones' trees: placed again, their ground as it was)
				_want_stands(p)
			continue
		if p.task != -1:
			p.again = true
		else:
			_start(p)


## (Worker) The patch's vertices (relative to its centre), normals, heights.
func _build(p: Patch, face: int, a0: float, b0: float, span: float, centre: Vector3) -> void:
	var ax := PlanetShape.face_axes(face)
	var n: Vector3 = ax[0]
	var u: Vector3 = ax[1]
	var v: Vector3 = ax[2]
	var G := PATCH + 3          # samples a side: the patch's vertices and a border (normals)
	var step := span / PATCH
	var pts := PackedVector3Array()
	pts.resize(G * G)
	var hs := PackedFloat32Array()
	hs.resize(G * G)
	for j in G:
		for i in G:
			var d := PlanetShape.face_dir(n, u, v, a0 + (i - 1) * step, b0 + (j - 1) * step)
			var h := shape.height(d)
			hs[j * G + i] = h
			pts[j * G + i] = d * (radius + h)
	p.hs = hs
	var V := PATCH + 1
	var wt: PlanetWater = shape.water if p.level >= max_level - 4 else null
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(V * V)
	norms.resize(V * V)
	uvs.resize(V * V)
	for j in V:
		for i in V:
			var k := (j + 1) * G + (i + 1)
			var du := pts[k + 1] - pts[k - 1]
			var dv := pts[k + G] - pts[k - G]
			var nr := du.cross(dv).normalized()
			if nr.dot(pts[k]) < 0.0:
				nr = -nr
			verts[j * V + i] = pts[k] - centre
			norms[j * V + i] = nr
			uvs[j * V + i] = Vector2(hs[k], -wt.wet(pts[k].normalized()) if wt else 0.0)   # (y: how wet - a lake's, a river's banks; < 0, the carved ground's chunks say 1)
	for j in PATCH:
		for i in PATCH:
			var a := j * V + i
			idx.append_array([a, a + V + 1, a + 1, a, a + V, a + V + 1])
	# Skirts: the rim's vertices again, dropped toward the centre - hides
	# the cracks where a finer patch meets a coarser one.
	var drop := 1.0 - (span * radius * 0.02 + 2.0) / radius
	var rim := []
	for i in V:
		rim.append(i)
	for j in range(1, V):
		rim.append(j * V + PATCH)
	for i in range(PATCH - 1, -1, -1):
		rim.append(PATCH * V + i)
	for j in range(PATCH - 1, 0, -1):
		rim.append(j * V)
	var base := verts.size()
	for r in rim:
		verts.append((verts[r] + centre) * drop - centre)
		norms.append(norms[r])
		uvs.append(uvs[r] - Vector2(span * radius * 0.02, 0.0))
	for q in rim.size():
		var a: int = rim[q]
		var b: int = rim[(q + 1) % rim.size()]
		var sa := base + q
		var sb := base + (q + 1) % rim.size()
		idx.append_array([a, sa, b, b, sa, sb, a, b, sa, b, sb, sa])   # (both sides)
	_scatter(p, n, u, v, a0, b0, span, centre)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	p.arrays = arr


## (Worker) What stands on the ground of the finest patches: boulders and
## the planet's plants (CosmosFlora). Placed a finest cell at a time, each
## cell from its own seed - so a patch one level coarser (which shows only
## the big boulders and the trees) has them exactly where its children will:
## nothing jumps when the ground refines. None in the sea, plants by their
## species' heights and slopes.
func _scatter(p: Patch, n: Vector3, u: Vector3, v: Vector3, a0: float, b0: float, span: float, centre: Vector3) -> void:
	if p.level < max_level - 1:
		return
	if p.level == max_level:
		_scatter_cell(p, n, u, v, a0, b0, span, centre, false)
	else:
		var h := span * 0.5
		for q in 4:
			_scatter_cell(p, n, u, v, a0 + h * (q % 2), b0 + h * (q / 2), h, centre, true)
	# (as MultiMesh buffers, made here: the main thread sets each in one call)
	p.rock_buf = _buffer(p.rock_xf, true)
	p.rock_n = p.rock_xf.size()
	p.rock_xf = []
	for k in p.flora_xf:
		p.flora_buf[k] = _buffer(p.flora_xf[k], false)
	p.flora_xf = {}


## Transforms as a MultiMesh buffer (TRANSFORM_3D: 12 floats each, row-major;
## + 4 of custom data, all 0.5 - the rocks' "no tumbling").
static func _buffer(xs: Array, custom: bool) -> PackedFloat32Array:
	var w := 16 if custom else 12
	var b := PackedFloat32Array()
	b.resize(xs.size() * w)
	var i := 0
	for t: Transform3D in xs:
		var bs := t.basis
		b[i] = bs.x.x; b[i + 1] = bs.y.x; b[i + 2] = bs.z.x; b[i + 3] = t.origin.x
		b[i + 4] = bs.x.y; b[i + 5] = bs.y.y; b[i + 6] = bs.z.y; b[i + 7] = t.origin.y
		b[i + 8] = bs.x.z; b[i + 9] = bs.y.z; b[i + 10] = bs.z.z; b[i + 11] = t.origin.z
		if custom:
			b[i + 12] = 0.5; b[i + 13] = 0.5; b[i + 14] = 0.5; b[i + 15] = 0.5
		i += w
	return b


func _scatter_cell(p: Patch, n: Vector3, u: Vector3, v: Vector3, a0: float, b0: float, span: float, centre: Vector3, coarse: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(shape.look.get("seed", 0.0) * 100.0), p.face, snappedf(a0, 1e-6), snappedf(b0, 1e-6)])
	var area := pow(span * radius * 0.9 / 22.0, 2.0)   # (densities are per 22 x 22 m)
	var count := int((rng.randi_range(0, ROCKS_A_PATCH) if rng.randf() < 0.85 else rng.randi_range(8, ROCKS_A_PATCH * 4)) * area)
	for i in count:
		var ua := a0 + rng.randf() * span
		var vb := b0 + rng.randf() * span
		var d := PlanetShape.face_dir(n, u, v, ua, vb)
		var size := pow(rng.randf(), 4.0) * 2.4 + 0.15
		var e := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var sy := rng.randf_range(0.5, 0.9)
		var sz := rng.randf_range(0.8, 1.2)
		if coarse and size < 1.0:
			continue
		var h := shape.height(d)
		if shape.sea > 0 and h < 0.4 or shape.cleared(d) or shape.dug_here(d, p.digs) or shape.bare(d):
			continue
		var at := d * (radius + h - size * 0.3)
		p.rock_xf.append(Transform3D(Basis.from_euler(e).scaled(Vector3(size, size * sy, size * sz)), at - centre))
		p.rocks_new.append([at, size * 0.8, size * 0.7])
	if not flora_ready:
		return
	# (the plants - groves and meadows, sizes, each species its own seed: CosmosFlora.scatter)
	CosmosFlora.scatter(flora, shape, radius, rng.seed, n, u, v, a0, b0, span, centre, coarse, p.digs, p.flora_xf, p.rocks_new, false)


## (The plants designed) The finest patches built before - bare - built again with their plants.
func _replant() -> void:
	var stack := _roots.duplicate()
	while not stack.is_empty():
		var p: Patch = stack.pop_back()
		stack.append_array(p.kids)
		if p.level < max_level - 1:
			if p.ready:
				_want_stands(p)   # (its trees: the finer ones' with their ground, built again below)
			continue
		if p.task != -1:
			p.again = true
		elif p.ready:
			_start(p)


## Its trees and shrubs to be built (again): its ground's in (or dug, or the plants
## just designed). Above _stand_top: none.
func _want_stands(p: Patch) -> void:
	if flora.is_empty() and flora_ready:
		return
	if p.level < _stand_top:
		if p.stands == null:
			p.stands = {}
		return
	if not _stand_wait.has(p):
		_stand_wait.append(p)


## (Each frame) The patches' plants: built on workers - each once its parent's are
## known (its share of them handed down) - and drawn once built, within the frame's
## budget: per species a MultiMesh a level of detail its plants can need there (the
## rest culled by their visibility ranges), the impostors of all in one.
func _stands_collect() -> void:
	if not flora_ready:
		return
	var i := 0
	while i < _stand_wait.size():
		var p: Patch = _stand_wait[i]
		if p.dead:
			_stand_wait.remove_at(i)
			continue
		var par := p.parent
		if par != null and par.level >= _stand_top and par.stands == null:
			i += 1   # (its parent's plants first)
			continue
		_stand_wait.remove_at(i)
		if p.stand_task != -1:
			p.stand_again = true
			continue
		var inh: Dictionary = par.stands if par != null and par.level >= _stand_top else {}
		var lv := p.level
		var hi := INF if lv == _stand_top else FloraLods.LEVEL_REACH * _level_size(lv)
		var lo := 0.0 if lv == max_level else FloraLods.LEVEL_REACH * _level_size(lv + 1)
		p.stand_task = WorkerThreadPool.add_task(_stand_build.bind(p, inh, p.stands, lo, hi, p.hs, p.digs, shape._bare_list), true, "planet plants")
		_stand_busy.append(p)
	i = 0
	while i < _stand_busy.size():
		var p: Patch = _stand_busy[i]
		if not WorkerThreadPool.is_task_completed(p.stand_task):
			i += 1
			continue
		if Time.get_ticks_usec() > deadline_us:
			break
		WorkerThreadPool.wait_for_task_completion(p.stand_task)
		p.stand_task = -1
		_stand_busy.remove_at(i)
		var res := p.stand_res
		p.stand_res = []
		if p.dead or res.is_empty():
			continue
		if res[0] != null:
			p.stands = res[0]
		p.stand_solids = res[2]
		p.rocks = p.rock_only + p.stand_solids
		_stands_draw(p, res[1])
		if p.stand_again:
			p.stand_again = false
			_want_stands(p)


## (Worker) A patch's plants: its own made (the first time) and its parent's on it
## added; then set on its ground as MultiMesh buffers (FloraLods).
func _stand_build(p: Patch, inh: Dictionary, have, lo: float, hi: float, hs: PackedFloat32Array, digs: PackedFloat64Array, bare: Array) -> void:
	if _leaving:
		return   # (the planet going: the tasks still queued end at once - its exit waits for them)
	var all: Dictionary
	var fresh = null
	if have == null:
		var ax := PlanetShape.face_axes(p.face)
		var sd := hash([int(shape.look.get("seed", 0.0) * 100.0), p.face, snappedf(p.a0, 1e-6), snappedf(p.b0, 1e-6), p.level, 5])
		var mine := FloraLods.own(flora, shape, radius, sd, ax[0], ax[1], ax[2], p.a0, p.b0, p.span, lo, hi)
		all = FloraLods.inherit(inh, p.a0, p.b0, p.span, mine)
		fresh = all
	else:
		all = have
	var solids: Array = []
	var res := FloraLods.build(flora, shape, radius, all, p.a0, p.b0, p.span, p.centre, hs, PATCH, p.level >= max_level - 1, digs, solids, bare)
	p.stand_res = [fresh, res, solids]


## Patch `p`'s plants: kept as buffers (the near field draws them up close) and
## its impostors drawn - all species in one MultiMesh, culled where none can be one.
func _stands_draw(p: Patch, res: Dictionary) -> void:
	p.stand_bufs = res
	p.stand_ok = true
	if p.shown:
		_nf_dirty = true
	if p.fl:
		p.fl.queue_free()
		p.fl = null
	if not res.has("imp"):
		return
	var e: Array = res["imp"]
	var s := _level_size(p.level)
	# (where its plants can be from the camera while it's drawn: from where it splits - nearer
	# while its children build - to where its parent merges back)
	var win := Vector2(0.0 if p.level == max_level else s * 1.3, INF if p.level == _stand_top else s * 7.5)
	var band := FloraLods.band_m(FloraLods.IMP, FloraLods.IMP, float(e[2]), float(e[3]))
	band.y = minf(band.y, float(e[4]))
	if band.x >= band.y or band.y < win.x or band.x > win.y:
		return
	var box: AABB = e[5]
	var r := 0.0
	for c in 8:
		r = maxf(r, box.get_endpoint(c).length())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = FloraLods.impostor_mesh()
	mm.instance_count = e[1]
	mm.buffer = e[0]
	mm.custom_aabb = box
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _leaf_mat
	mmi.visibility_range_begin = maxf(band.x - r, 0.0)
	mmi.visibility_range_end = band.y + r
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = p.centre
	mmi.visible = p.shown
	add_child(mmi)
	p.fl = mmi


# --- The near field: the plants' finer levels round the camera ---------------------

## The trees' and shrubs' meshes finer than the impostor - every species' near, mid,
## far and low - drawn round the camera: per species and level one MultiMesh of the
## plants that level can draw now (their distance over their size near its band, a
## margin for the camera's movement until the next), gathered on a worker from the
## patches drawn whenever the camera's moved NF_STEP (the near and mid levels' 4 m,
## the far and low ones' 24 m - each tier gathered on its own) or the patches changed - a few
## hundred MultiMeshes in all (each group in NF_SECTORS by bearing - those out of
## sight culled), whatever the patches. Each plant's level is the shader's
## pick, the same as the gathering's: nothing pops when the field's gathered again.
const NF_STEP := [4.0, 24.0]    # m: gathered again after the camera's moved this far - the near and mid levels, the far and low ones
const NF_CAST_M := 50.0         # m: the plants casting shadows (near and mid levels: solid ones)
const NF_SECTORS := 8           # (each group split by its bearing from the camera: the ones behind it culled)
var _nf: Node3D
var _nf_mmi := {}               # group key -> MultiMeshInstance3D
var _nf_groups: Array = []      # [key, species, mesh, lo x, hi x, cast, near only, far only, tier]
var _nf_task := -1
var _nf_res := {}
var _nf_apply := {}             # (gathered, being handed to the MultiMeshes: key -> [buffer, AABB, hash])
var _nf_i := 0
var _nf_busy := false
var _nf_at: Array = [Vector3(INF, INF, INF), Vector3(INF, INF, INF)]   # (each tier's camera when last gathered)
var _nf_t: Array = [0, 0]
var _nf_dirty := false
var _nf_dirt: Array = [false, false]
var _nf_tiers: Array = [false, false]   # (the tiers the gathering under way is of)
var _nf_hash := {}              # key -> its buffer's hash (unchanged: not sent again)


## The groups (made once the meshes are): per species, per level of its chain - the
## mid level split at NF_CAST_M (the nearer half casts shadows).
func _nf_setup() -> void:
	_nf_groups.clear()
	for k in _flora_lods.size():
		var solid := float(flora[k]["solid"]) > 0.0
		for lm: Array in _flora_lods[k]:
			var lo: int = lm[1]
			var hi: int = lm[2]
			var bx := FloraLods.band_x(lo, hi)
			var lx: float = bx.x
			var hx: float = bx.y
			var tier := 0 if lo < FloraLods.IMP - 2 else 1   # (near and mid levels / far and low)
			if solid and lo < FloraLods.IMP - 2 and hi < FloraLods.IMP - 2:
				_nf_groups.append([_nf_groups.size(), k, lm[0], lx, hx, true, true, false, tier])
				_nf_groups.append([_nf_groups.size(), k, lm[0], lx, hx, false, false, true, tier])
			else:
				_nf_groups.append([_nf_groups.size(), k, lm[0], lx, hx, false, false, false, tier])


## (Each LOD visit) Gather the near field again if the camera's moved or the patches changed.
func _nf_check(cam: Vector3) -> void:
	if not flora_ready or _flora_lods.is_empty() or _nf_task != -1 or _nf_busy:
		return
	if _nf_dirty:
		_nf_dirty = false
		_nf_dirt = [true, true]
	var now := Time.get_ticks_msec()
	var due: Array = [false, false]
	var margin: Array = [0.0, 0.0]
	for t in 2:
		var moved: float = cam.distance_to(_nf_at[t])
		# (the far tier's gathering is the bulk: for the patches changing, at most every 0.4 s)
		due[t] = moved >= float(NF_STEP[t]) or bool(_nf_dirt[t]) and (t == 0 or now - int(_nf_t[t]) > 400)
		if not due[t]:
			continue
		var speed: float = moved / maxf((now - int(_nf_t[t])) / 1000.0, 0.05) if (_nf_at[t] as Vector3).x < INF else 0.0
		margin[t] = clampf(float(NF_STEP[t]) + speed * 0.35, float(NF_STEP[t]), 250.0)   # (fast: a wider margin - it moves further before the next)
		_nf_t[t] = now
		_nf_at[t] = cam
		_nf_dirt[t] = false
	if not due[0] and not due[1]:
		return
	if _nf_groups.is_empty():
		_nf_setup()
	var reach := 0.0
	for g: Array in _nf_groups:
		if due[g[8]]:
			reach = maxf(reach, float(g[4]) * float(flora[g[1]]["h"]) * 1.7 + float(margin[g[8]]))
	# (the patches drawn round it: their plants' buffers)
	var snap: Array = []
	var stack := _roots.duplicate()
	while not stack.is_empty():
		var q: Patch = stack.pop_back()
		if q.centre.distance_to(cam) > reach + q.size:
			continue
		if q.shown:
			if not q.stand_bufs.is_empty():
				snap.append([q.centre, q.stand_bufs])
		else:
			stack.append_array(q.kids)
	_nf_tiers = due
	_nf_task = WorkerThreadPool.add_task(_nf_build.bind(snap, cam, margin, due), true, "planet plants near")


## (Worker) Each group's plants: those whose distance over size is within its band
## (and the margin), planet-local (a float's precision there: under a millimetre) -
## [buffer, AABB] each.
func _nf_build(snap: Array, cam: Vector3, margins: Array, due: Array) -> void:
	if _leaving:
		return
	var by_k := {}
	for g: Array in _nf_groups:
		if not due[g[8]]:
			continue
		var l: Array = by_k.get(g[1], [])
		l.append(g)
		by_k[g[1]] = l
	var out := {}
	var co := cam
	var up := cam.normalized()
	var e1 := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := up.cross(e1)
	for e: Array in snap:
		var off: Vector3 = e[0]
		var bufs: Dictionary = e[1]
		for k in bufs:
			if not k is int or not by_k.has(k):
				continue
			var gs: Array = by_k[k]
			var margin := 0.0
			for g: Array in gs:
				margin = maxf(margin, float(margins[g[8]]))
			var buf: PackedFloat32Array = bufs[k][0]
			for i in range(0, buf.size(), 16):
				var px := buf[i + 3] + off.x
				var py := buf[i + 7] + off.y
				var pz := buf[i + 11] + off.z
				var d := Vector3(px, py, pz).distance_to(co)
				var reach := buf[i + 13]
				if d - margin > reach:
					continue
				var size := buf[i + 12]
				var rel := Vector3(px, py, pz) - co
				var sec := int(floor((atan2(rel.dot(e2), rel.dot(e1)) + PI) / TAU * NF_SECTORS)) % NF_SECTORS
				for g: Array in gs:
					var gm: float = margins[g[8]]
					if (d + gm) / size < float(g[3]) or (d - gm) / size > float(g[4]):
						continue
					if bool(g[6]) and d > NF_CAST_M or bool(g[7]) and d <= NF_CAST_M:
						continue   # (the near ones cast shadows, the rest not: each in one of the two)
					var key: int = int(g[0]) * NF_SECTORS + sec
					var acc: Array = out.get(key, [])   # [buffer, offset, instance] triples (an Array: appended in place)
					if acc.is_empty():
						out[key] = acc
					acc.append_array([buf, Vector3(px, py, pz), i])
	var res := {}
	for key in out:   # (each one's buffer, and bounds: its plants' places, their sizes round them)
		var acc: Array = out[key]
		var ob := PackedFloat32Array()
		ob.resize(acc.size() / 3 * 16)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var big := 0.0
		var w := 0
		for j in range(0, acc.size(), 3):
			var src: PackedFloat32Array = acc[j]
			var o: Vector3 = acc[j + 1]
			var i: int = acc[j + 2]
			for q in 16:
				ob[w + q] = src[i + q]
			ob[w + 3] = o.x
			ob[w + 7] = o.y
			ob[w + 11] = o.z
			w += 16
			lo = lo.min(o)
			hi = hi.max(o)
			big = maxf(big, src[i + 12])
		res[key] = [ob, AABB(lo - Vector3.ONE * big * 1.3, hi - lo + Vector3.ONE * big * 2.6), hash(ob)]
	_nf_res = res


## (Each frame) The gathered field in: each group's MultiMesh given its plants - as
## many as the frame's budget allows, the rest the next frames (a group's buffer
## swapped whole: a plant in two groups for a frame at most).
func _nf_collect() -> void:
	if _nf_task != -1 and WorkerThreadPool.is_task_completed(_nf_task):
		WorkerThreadPool.wait_for_task_completion(_nf_task)
		_nf_task = -1
		_nf_apply = _nf_res
		_nf_res = {}
		_nf_i = 0
		_nf_busy = true
	if not _nf_busy:
		return
	if _nf == null:
		_nf = Node3D.new()
		_nf.name = "PlantsNear"
		add_child(_nf)
	var total := _nf_groups.size() * NF_SECTORS
	while _nf_i < total:
		if Time.get_ticks_usec() > deadline_us and _nf_i > 0:
			return
		var key := _nf_i
		_nf_i += 1
		var g: Array = _nf_groups[key / NF_SECTORS]
		if not _nf_tiers[g[8]]:
			continue   # (not gathered this time: as it was)
		var e: Array = _nf_apply.get(key, [])
		var mmi: MultiMeshInstance3D = _nf_mmi.get(key)
		if e.is_empty():
			if mmi:
				mmi.visible = false
			_nf_hash.erase(key)
			continue
		if mmi and mmi.visible and int(_nf_hash.get(key, 0)) == int(e[2]):
			continue   # (the same plants: nothing sent)
		_nf_hash[key] = e[2]
		var buf: PackedFloat32Array = e[0]
		if mmi == null:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = g[2]
			mmi = MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _leaf_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(g[5]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_nf.add_child(mmi)
			_nf_mmi[key] = mmi
		var m := mmi.multimesh
		if m.instance_count != buf.size() / 16:
			m.instance_count = buf.size() / 16
		m.buffer = buf
		m.custom_aabb = e[1]
		mmi.visible = true
	_nf_busy = false
	_nf_apply = {}


## Called by Cosmos a few times a second: the camera's planet-local position.
func update_lod(cam_local: Vector3) -> void:
	if shape.kind == "gas":
		return
	if shape.dig_n > 0 and cam_local.distance_to(_cuts_at) > 30.0:
		_cuts_at = cam_local   # (the carves nearest you, for the shader)
		_cuts = shape.cuts_near(cam_local, 600.0, CUTS, true)   # (those that open the ground's face: the rest are under it)
		if not _cuts_wait.is_empty():   # (not the ones still waiting for their dug ground)
			_cuts = _cuts.filter(func(c): return _cuts_wait.all(func(w): return (w[0] as Vector3).distance_to(c[1]) > 0.01))
		_send_cuts()
		if voxels == null:
			voxels = CosmosVoxels.new()
			voxels.planet = self
			add_child(voxels)
	if voxels:
		voxels.update(cam_local)
	_collect()
	if _stack.is_empty():
		_begin_visit(cam_local)
	# (the visit, a slice a frame: a whole one is ~1.5 ms of script near the
	# ground - in one frame it was the slow twentieth at 600 FPS)
	var until := Time.get_ticks_usec() + visit_budget_us
	while not _stack.is_empty() and Time.get_ticks_usec() < until:
		_visit(_stack.pop_back())
	_nf_check(cam_local)


func _send_cuts() -> void:
	var v := PackedVector4Array()
	for c in _cuts:
		var m: Vector3 = c[1]
		v.append(Vector4(m.x, m.y, m.z, float(c[2]) + PlanetShape.CRUMBLE + 0.05))   # (as far as its roughest: the voxels draw the ground to past that)
	v.resize(CUTS)
	material.set_shader_parameter("cuts", v)
	material.set_shader_parameter("cut_n", _cuts.size())
	for m: ShaderMaterial in CosmosVeins.holo_mats():   # (the scanned veins' hologram: the parts dug out grey, as you dig)
		m.set_shader_parameter("cuts", v)
		m.set_shader_parameter("cut_n", _cuts.size())


## A visit under way (its slices still to come)?
func visiting() -> bool:
	return not _stack.is_empty()


func _begin_visit(cam_local: Vector3) -> void:
	_cam_local = cam_local
	# (the horizon, once a visit: patches beyond it aren't drawn - a level's
	# patches past the cosine of it, plus their own size)
	var h := cam_local.length()
	var top := radius + shape.top()
	h = maxf(h, radius + 1.0)
	_horizon = acos(clampf(radius / h, -1.0, 1.0)) + acos(clampf(radius / top, -1.0, 1.0))
	_cam_dir = cam_local.normalized()
	_sight_cos.resize(max_level + 2)
	for lv in max_level + 2:
		var size := radius * (2.0 / pow(2.0, lv)) * 0.9
		_sight_cos[lv] = cos(minf(_horizon + size / radius * 0.8, PI))
	deepest_hint = 0
	for p: Patch in _roots:
		if not p.kids.is_empty():
			deepest_hint = 2   # (split somewhere: visited until it's merged back)
	_stack.append_array(_roots)
	if _sea_mi:
		var near := cam_local.length() - radius < radius * 0.6
		var want := _sea_high if near else _sea_low
		if _sea_mi.mesh != want:
			_sea_mi.mesh = want


## Only turns finished patches into meshes (the frames between LOD visits).
func collect_only() -> void:
	if shape.kind != "gas":
		_collect()


func _collect() -> void:
	_water_in()
	_caves_in()
	if _flora_task != -1 and WorkerThreadPool.is_task_completed(_flora_task):
		WorkerThreadPool.wait_for_task_completion(_flora_task)
		_flora_task = -1
		_flora_mk = 0 if not flora.is_empty() else -1
		flora_ready = flora.is_empty()
		if _imp_atlas.has("image"):   # (the impostors' atlas: FloraLods.bake)
			_imp_tex = ImageTexture.create_from_image(_imp_atlas["image"])
			_leaf_mat.set_shader_parameter("impostors", _imp_tex)
			_leaf_mat.set_shader_parameter("imp_grid", _imp_atlas["grid"])
			_imp_atlas = {}
	if _flora_mk >= 0 and flora[_flora_mk].has("lods"):   # (a tree's or shrub's chain of meshes, one species a frame: FloraLods)
		var lods: Array = []
		for e: Array in flora[_flora_mk]["lods"]:
			var lm := ArrayMesh.new()
			lm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e[0])
			lods.append([lm, e[1], e[2]])
		_flora_lods.append(lods)
		_flora_meshes.append(null)
		_flora_mk += 1
		if _flora_mk >= flora.size():
			_flora_mk = -1
			flora_ready = true
			_replant()
	elif _flora_mk >= 0:   # (a grass's or flower's mesh)
		var sp: Dictionary = flora[_flora_mk]
		_flora_lods.append([])
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sp["arrays"])
		_flora_meshes.append(m)
		_flora_mk += 1
		if _flora_mk >= flora.size():
			_flora_mk = -1
			flora_ready = true
			_replant()
	var i := 0
	while i < _busy.size():
		var p: Patch = _busy[i]
		if not WorkerThreadPool.is_task_completed(p.task):
			i += 1
			continue
		if Time.get_ticks_usec() > deadline_us:
			break
		WorkerThreadPool.wait_for_task_completion(p.task)
		p.task = -1
		tasks -= 1
		_busy.remove_at(i)
		if p.arrays.is_empty():
			continue
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p.arrays)
		p.arrays = []
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = material
		mi.position = p.centre
		mi.visible = p.shown and p.mi != null   # (built again - dug: in place of the old one)
		if p.mi:
			p.mi.queue_free()
		p.rock_only = p.rocks_new
		p.rocks = p.rock_only + p.stand_solids if not p.stand_solids.is_empty() else p.rock_only
		p.rocks_new = []
		if not COMPAT:   # (the web's renderer: none - see terrain.gdshader)
			mi.set_instance_shader_parameter("patch_info", Vector4(p.centre.x, p.centre.y, p.centre.z, 0.0 if p.digs.is_empty() else 1.0))   # (its centre; 1: carves near - not drawn inside them)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if p.level >= max_level - 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		p.mi = mi
		p.ready = true
		patches_made += 1
		if p.rock_n > 0:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = rock_mesh()
			mm.instance_count = p.rock_n
			mm.buffer = p.rock_buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _rock_mat
			mmi.visibility_range_end = 260.0 if p.level < max_level else 140.0   # (the big ones further)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if p.level < max_level else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(mmi)
		p.rock_buf = PackedFloat32Array()
		for k in p.flora_buf:
			var buf: PackedFloat32Array = p.flora_buf[k]
			if buf.is_empty():
				continue
			var fm := MultiMesh.new()
			fm.transform_format = MultiMesh.TRANSFORM_3D
			fm.mesh = _flora_meshes[k]   # (the grass and flowers: the finest patches')
			fm.instance_count = buf.size() / 12
			fm.buffer = buf
			var fmi := MultiMeshInstance3D.new()
			fmi.multimesh = fm
			fmi.material_override = _leaf_mat if flora[k].get("cards", false) else _flora_mat
			var solid: bool = float(flora[k]["solid"]) > 0.0
			fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if solid and p.level >= max_level else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # (shadows: the near trees')
			# (draw distances: the small plants only near - their patches' draw calls go)
			fmi.visibility_range_end = float(flora[k].get("range", 0.0))   # (each species' own: CosmosFlora - grass and flowers fade out before it)
			mi.add_child(fmi)
		p.flora_buf = {}
		if p.again:
			p.again = false
			_start(p)
		else:
			_want_stands(p)
	_stands_collect()
	_nf_collect()


func _visit(p: Patch) -> void:
	var d := _cam_local.distance_to(p.centre)
	var limit := p.size * SPLIT * (KEEP if not p.kids.is_empty() else 1.0)
	if p.level < max_level and d < limit:
		if p.kids.is_empty() and tasks < MAX_TASKS:
			_split(p)
		if not p.kids.is_empty() and _kids_ready(p):
			_show(p, false)
			p.sub = true
			_stack.append_array(p.kids)   # (visited in this visit's later slices)
			return
	elif not p.kids.is_empty() and not _subtree_busy(p):
		_drop_kids(p)
	if p.mi:
		_show(p, _in_sight(p))
	if p.sub:
		p.sub = false
		for k: Patch in p.kids:
			_hide(k)


func _show(p: Patch, on: bool) -> void:
	if p.shown != on and p.mi:
		p.shown = on
		p.mi.visible = on
		if p.fl:
			p.fl.visible = on
		if not p.stand_bufs.is_empty():
			_nf_dirty = true


func _split(p: Patch) -> void:
	var h := p.span * 0.5
	for q in 4:
		var k := Patch.new()
		k.face = p.face
		k.level = p.level + 1
		k.span = h
		k.a0 = p.a0 + h * (q % 2)
		k.b0 = p.b0 + h * (q / 2)
		k.parent = p
		_place(k)
		p.kids.append(k)
		_start(k)


func _kids_ready(p: Patch) -> bool:
	for k: Patch in p.kids:
		if not k.ready or p.stand_ok and not k.stand_ok:   # (their plants too, once its own are: the trees never blink out)
			return false
	return true


func _subtree_busy(p: Patch) -> bool:
	for k: Patch in p.kids:
		if k.task != -1 or k.stand_task != -1 or _subtree_busy(k):
			return true
	return false


func _drop_kids(p: Patch) -> void:
	for k: Patch in p.kids:
		_drop_kids(k)
		k.dead = true
		if k.mi:
			k.mi.queue_free()
		if k.fl:
			k.fl.queue_free()
			k.fl = null
	p.kids.clear()


func _hide(p: Patch) -> void:
	_show(p, false)
	if p.sub:
		p.sub = false
		for k: Patch in p.kids:
			_hide(k)


## Not hidden behind the planet's own horizon (from the camera).
func _in_sight(p: Patch) -> bool:
	return _cam_dir.dot(p.dir) > float(_sight_cos[mini(p.level, _sight_cos.size() - 1)])


## Leaf patches on screen (tests, the HUD's debug line).
func shown_patches() -> int:
	var n := 0
	for c in get_children():
		if c is MeshInstance3D and c.visible and c.material_override == material:
			n += 1
	return n


## The finest level shown now.
func deepest() -> int:
	var best := 0
	var stack := _roots.duplicate()
	while not stack.is_empty():
		var p: Patch = stack.pop_back()
		if p.mi and p.mi.visible:
			best = maxi(best, p.level)
		stack.append_array(p.kids)
	return best


const NEAR_FRESH_MS := 250
const NEAR_MARGIN := 6.0
var _near_cache := {}


## Boulders within `reach` of planet-local `local` on the patches drawn now:
## [planet-local position, radius] each.
func rocks_near(local: Vector3, reach: float, key := "") -> Array:
	# (a caller asking every frame - `key` - gets its last answer while it's
	# fresh and it's moved little: found with a margin, so it still holds all)
	if key != "":
		var c: Array = _near_cache.get(key, [])
		# (not dropped when any patch is made - while walking that's nearly every frame; new
		# boulders come into the answer within NEAR_FRESH_MS)
		if not c.is_empty() and Time.get_ticks_msec() - int(c[0]) < NEAR_FRESH_MS \
				and (c[1] as Vector3).distance_to(local) + reach <= float(c[2]):
			return c[3]
		var found := rocks_near(local, reach + NEAR_MARGIN)
		_near_cache[key] = [Time.get_ticks_msec(), local, reach + NEAR_MARGIN, found, patches_made]
		return found
	var out: Array = []
	var stack := _roots.duplicate()
	while not stack.is_empty():
		var p: Patch = stack.pop_back()
		if p.centre.distance_to(local) > p.size + reach:
			continue
		if p.kids.is_empty() or not _kids_ready(p):
			for r in p.rocks:
				if (r[0] as Vector3).distance_to(local) < reach + r[1]:
					out.append(r)
		else:
			stack.append_array(p.kids)
	return out


## The ground (or sea) under planet-local point `local`: metres above the radius.
func ground_at(local: Vector3) -> float:
	return shape.surface(local.normalized())


func _add_sea(L: Dictionary, noise: Texture3D) -> void:
	if shape.sea == 1:   # (water: seen into, its waves, the sky in it - CosmosWaters' too)
		_sea_low = unit_sphere(64, 32)
		_sea_high = unit_sphere(384, 192)
		_sea_mi = _ball(radius, 64, 32, CosmosWaters.sea_material(L, radius), "Sea")
		return
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("kind", shape.sea)
	m.set_shader_parameter("shallow", L.get("water_shallow", Color(0.15, 0.45, 0.65)))
	m.set_shader_parameter("deep", L.get("water_deep", Color(0.05, 0.1, 0.35)))
	m.set_shader_parameter("ice", L.get("ice_color", Color(0.85, 0.92, 1.0)))
	m.set_shader_parameter("lava", L.get("lava_color", Color(1.0, 0.4, 0.05)))
	m.set_shader_parameter("lava_hot", L.get("lava_hot", Color(1.0, 0.9, 0.4)))
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("radius", radius)
	_sea_low = unit_sphere(64, 32)
	_sea_high = unit_sphere(384, 192)
	_sea_mi = _ball(radius, 64, 32, m, "Sea")


## Its cloud layers: [name, height (x its highest ground, + m), scale, speed, stretch,
## edge softness, opacity, its share of the world's cover, how much the weather
## thickens it, how dark a storm makes it] - low and heavy (the weather's own),
## heaped mid, thin high streaks racing.
const CLOUD_LAYERS := [
	["CloudsLow", 0.85, 25.0, 1.3, 1.0, Vector3(0.6, 1.0, 0.6), 0.2, 0.88, 0.45, 1.25, 0.8],
	["Clouds", 1.3, 40.0, 1.0, 0.65, Vector3(0.55, 1.0, 0.55), 0.14, 0.92, 1.0, 0.75, 0.5],
	["CloudsHigh", 2.0, 120.0, 0.75, 2.6, Vector3(0.2, 1.0, 1.0), 0.3, 0.5, 0.55, 0.25, 0.15],
]
var weather: PlanetWeather       # (its weather: local, moving - PlanetWeather; weather_tick)
var _cloud_mats: Array = []      # (its cloud layers' materials, low to high)


func _add_clouds(L: Dictionary, noise: Texture3D) -> void:
	var base := float(L.get("clouds", 0.4))
	var span := atmo_radius - radius
	for ly in CLOUD_LAYERS:
		var m := ShaderMaterial.new()
		m.shader = CLOUDS
		m.render_priority = 1 + _cloud_mats.size()
		m.set_shader_parameter("cover", base * float(ly[8]))
		m.set_shader_parameter("scale", float(L.get("cloud_scale", 2.2)) * float(ly[3]))
		m.set_shader_parameter("tint", L.get("cloud_color", Color.WHITE))
		m.set_shader_parameter("seed", float(L.get("seed", 0.0)) + _cloud_mats.size() * 37.0)
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("speed", float(ly[4]))
		m.set_shader_parameter("stretch", ly[5])
		m.set_shader_parameter("soft", float(ly[6]))
		m.set_shader_parameter("opacity", float(ly[7]))
		m.set_shader_parameter("weather_k", float(ly[9]))
		m.set_shader_parameter("storm_dark", float(ly[10]))
		var h := minf(shape.top() * float(ly[1]) + float(ly[2]), span * 0.92)
		_ball(radius + h, 128, 64, m, str(ly[0]))
		_cloud_mats.append(m)


## The weather now (the galaxy's clock `t`): its cells to the clouds and the ground; the
## layers drawn in the right order for where you are (under them: the low one last).
func weather_tick(t: float, eye_local: Vector3) -> void:
	if weather == null or weather.cells.is_empty():
		return
	var sc: Array = weather.shader_cells(t, sun_local)   # (its cells in its own frame)
	for m: ShaderMaterial in _cloud_mats:
		m.set_shader_parameter("cell_a", sc[0])
		m.set_shader_parameter("cell_b", sc[1])
	if material:
		material.set_shader_parameter("cell_a", sc[0])
		material.set_shader_parameter("cell_b", sc[1])
	var n := _cloud_mats.size()
	var r := eye_local.length()
	for i in n:   # (the nearest layer drawn last: from under them the low one, from over them the high one)
		var hi := (get_node_or_null(str(CLOUD_LAYERS[i][0])) as Node3D)
		var under := hi != null and r < hi.scale.x
		(_cloud_mats[i] as ShaderMaterial).render_priority = 1 + (n - 1 - i if under else i)


func _add_atmosphere(col: Color, k: float) -> void:
	var m := ShaderMaterial.new()
	m.shader = ATMO
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("strength", k)
	m.set_shader_parameter("r_planet", radius)
	m.set_shader_parameter("r_atmo", atmo_radius)
	var mi := _ball(atmo_radius, 64, 32, m, "Atmosphere")
	mi.extra_cull_margin = atmo_radius   # (never culled while you might be inside it)


func _add_rings(L: Dictionary) -> void:
	var inner := float(L.get("ring_inner", 1.4)) * radius
	var outer := float(L.get("ring_outer", 2.2)) * radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 160
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := [Vector3(cos(a0) * inner, 0, sin(a0) * inner), Vector3(cos(a0) * outer, 0, sin(a0) * outer),
			Vector3(cos(a1) * outer, 0, sin(a1) * outer), Vector3(cos(a1) * inner, 0, sin(a1) * inner)]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for t in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[t])
			st.set_normal(Vector3.UP)
			st.add_vertex(p[t])
	var m := ShaderMaterial.new()
	m.shader = RING
	m.set_shader_parameter("ring_a", L.get("ring_a", Color(0.8, 0.7, 0.6)))
	m.set_shader_parameter("ring_b", L.get("ring_b", Color(0.5, 0.45, 0.4)))
	m.set_shader_parameter("density", float(L.get("rings", 1.0)))
	m.set_shader_parameter("seed", float(L.get("seed", 0.0)))
	m.set_shader_parameter("r_planet", radius)
	var mi := MeshInstance3D.new()
	mi.name = "Rings"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)   # (in its equator's plane: tilted with its axis - tilt_basis - turning round it, unchanged)


## A unit sphere of `radial` x `rings` segments - one of each kind for every
## planet (seas, clouds, atmospheres, gas giants: scaled to their radius),
## made once a run (CosmosWarm makes them at the title screen).
static var _spheres := {}


static func unit_sphere(radial: int, rings: int) -> SphereMesh:
	var k := Vector2i(radial, rings)
	if not _spheres.has(k):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = radial
		s.rings = rings
		_spheres[k] = s
	return _spheres[k]


## A sphere instance of radius `r` (a shared unit sphere, scaled).
func _ball(r: float, radial: int, rings: int, mat: Material, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = unit_sphere(radial, rings)
	mi.scale = Vector3.ONE * r
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Towards the star (world, `dir`): the shaders lit from it - in the world's frame,
## but the clouds' (they light their own unit sphere: its frame, spin_sun).
func set_sun(dir: Vector3) -> void:
	sun_dir = dir
	for c in get_children():
		if c is GeometryInstance3D and c.material_override is ShaderMaterial and not _cloud_mats.has(c.material_override):
			(c.material_override as ShaderMaterial).set_shader_parameter("sun_dir", dir)
	if material:
		material.set_shader_parameter("sun_dir", dir)
	spin_sun()


## The sun in its own frame (it's turned since): sun_local, and its clouds lit from it -
## each of Cosmos._orbit_tick's steps.
func spin_sun() -> void:
	sun_local = dir_local(sun_dir)
	for m: ShaderMaterial in _cloud_mats:
		m.set_shader_parameter("sun_dir", sun_local)


# --- Its turning: a day and a night ---------------------------------------------------
## Every world turns on its own axis - tilted a little (up to TILT_MAX, fixed among
## the stars: its seasons over its year) - so the sun rises and sets. Its node's
## basis IS its turn: Cosmos._orbit_tick sets it (ORBIT_HZ) and carries round with it
## what stands on it; its children (the ground, the sea, the clouds, its towns...)
## turn with it. "Planet-local" is its own frame: to_local / to_global for points,
## dir_local / dir_world for directions. Its solar day (noon to noon) 16-24 min
## from its seed - day and night each at most 12 min where its towns stand (within
## LIVED_LAT of its equator: CosmosTown.sites - the tilt's longest day there kept to
## 12 min, its day shortened to fit) - times Settings.day_length; a pure function of
## its seed and the galaxy's clock (spin_clock: continuous when the setting changes).
const DAY_MIN := 960.0           # s: the shortest solar day
const DAY_MAX := 1440.0          # s: the longest
const HALF_DAY_MAX := 720.0      # s: the longest day (or night) where its towns are
const TILT_MAX := 0.349          # (20 degrees)
const LIVED_LAT := 1.047         # (60 degrees: its towns within it)
var day_len := 1200.0            # s: its solar day (the setting's 1x)
var year_len := 0.0              # s: its year - a moon: its world's (the solar day's the turn less the year's)
var spin_phase := 0.0
var tilt := 0.0
var tilt_basis := Basis.IDENTITY # (its axis: its local Y, tilted)
var spin_now := 0.0              # (the turn its basis shows now: Cosmos._orbit_tick)
var sun_local := Vector3.UP      # (to the star, in its own frame - spin_sun)


## Its turn from its record (and, a ringed giant, its rings' tilt - the axis theirs):
## {day, tilt, tilt_basis, phase}.
static func spin_of(r: Dictionary, ring_euler := Vector3.INF) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(r.get("seed", 1)) + ":" + str(r.get("id", "")) + ":spin")
	var day := rng.randf_range(DAY_MIN, DAY_MAX)
	var eps := TILT_MAX * pow(rng.randf(), 1.3)
	var az := rng.randf() * TAU
	var phase := rng.randf() * TAU
	var tb := Basis.IDENTITY
	if ring_euler != Vector3.INF:
		tb = Basis.from_euler(ring_euler)
		eps = (tb * Vector3.UP).angle_to(Vector3.UP)
	elif eps > 0.0001:
		var pole := Vector3(sin(eps) * cos(az), cos(eps), sin(eps) * sin(az))
		tb = Basis(Vector3.UP.cross(pole).normalized(), eps)
	# (at LIVED_LAT, midsummer: the day's share of the turn - the hour angle of sunset)
	var share := acos(clampf(-tan(LIVED_LAT) * tan(eps), -1.0, 1.0)) / PI
	if ring_euler == Vector3.INF:
		day = minf(day, HALF_DAY_MAX / maxf(share, 0.5))
	return {"day": day, "tilt": eps, "tilt_basis": tb, "phase": phase}


## (Set up in setup: its turn, its year.)
func _spin_setup(ring_euler := Vector3.INF) -> void:
	var s := spin_of(rec, ring_euler)
	day_len = s["day"]
	tilt = s["tilt"]
	tilt_basis = s["tilt_basis"]
	spin_phase = s["phase"]
	var top := rec
	var parent := str(rec.get("moon_of", ""))
	if parent != "":
		top = Cosmos._orbits_of(str(rec.get("system", Galaxy.current_system)))["by_id"].get(parent, rec)
	year_len = Cosmos.orbit_period(top) if top.has("orbit") else 0.0


## A world with towns: its turn at the clock's start such that its first city has the
## morning sun then (a new game begins there, galaxy time 0) - its seed's all the same.
func _morning_start() -> void:
	if towns.is_empty():
		return
	var site: Dictionary = towns[0]
	for s in towns:
		if str(s.get("kind", "")) == "city":
			site = s
			break
	spin_phase = morning_turn(site["dir"], 0.0, spin_phase)   # (the clock's start: its turn there is its phase)


## The turn (radians) that puts planet-local `d` in the mid-morning sun at galaxy
## time `t` (the sun rising, a little over halfway up) - `none` if it has no sun.
func morning_turn(d: Vector3, t: float, none := 0.0) -> float:
	var at: Vector3 = Cosmos.planet_places(str(rec.get("system", Galaxy.current_system)), t).get(str(rec.get("id", "")), Vector3.ZERO)
	if at == Vector3.ZERO:
		return none
	var u := tilt_basis.inverse() * (-at).normalized()
	var best := none
	var best_k := INF
	var top := 0.0
	for k in 360:
		top = maxf(top, (Basis(Vector3.UP, -deg_to_rad(k)) * u).dot(d))
	for k in 360:
		var e := (Basis(Vector3.UP, -deg_to_rad(k)) * u).dot(d)
		var e1 := (Basis(Vector3.UP, -deg_to_rad(k + 1)) * u).dot(d)
		if e1 > e and absf(e - top * 0.55) < best_k:
			best_k = absf(e - top * 0.55)
			best = deg_to_rad(k)
	return best


## How far it's turned at galaxy time `t` (radians).
func spin_angle(t: float) -> float:
	var c := spin_clock(t)
	return spin_phase + TAU * (c.x / day_len - (c.y / year_len if year_len > 0.0 else 0.0))   # (the year's share taken off: it turns the same way as it goes round its star - its days a little longer than its turn)


## Its basis at galaxy time `t`: its axis tilted, turned round it.
func spin_basis(t: float) -> Basis:
	return basis_at(spin_angle(t))


## Its basis turned `a` (radians) round its axis.
func basis_at(a: float) -> Basis:
	return tilt_basis * Basis(Vector3.UP, a)   # (seen from its north - its local +Y - turning anticlockwise: the sun rises in the east, sets in the west)


## A direction (or an offset from its centre) in the world's frame, in its own - and back.
func dir_local(v: Vector3) -> Vector3:
	return global_basis.inverse() * v


func dir_world(v: Vector3) -> Vector3:
	return global_basis * v


## The direction to its star in its own frame at galaxy time `t` (m round the star: `where`
## its place then - Cosmos.planet_places) - for what looks ahead (the HUD's sunrise, the shots).
func sun_local_at(t: float, where: Vector3) -> Vector3:
	return spin_basis(t).inverse() * (-where).normalized()


## The spin's clock: [day clock, year clock] (s) at galaxy time `t` - the galaxy's own
## times the setting's rate (Settings.day_length: 2 - days twice as long; 0 - no turning).
## Its rate changed: carried on from where it was (the worlds don't jump); a game
## loaded: from the galaxy's time (reset_spin).
static var _clk := [0.0, 0.0, 0.0]   # (from: galaxy time, day clock, year clock)
static var _clk_rate := Vector2(1.0, 1.0)


static func spin_clock(t: float) -> Vector2:
	var dt := t - float(_clk[0])
	return Vector2(float(_clk[1]) + dt * _clk_rate.x, float(_clk[2]) + dt * _clk_rate.y)


static func _rate_of(mult: float) -> Vector2:
	return Vector2.ZERO if mult <= 0.0 else Vector2(1.0 / mult, 1.0)


## The setting's rate from now (galaxy time `t`) - kept continuous; true if it changed.
static func spin_rate(mult: float, t: float) -> bool:
	var r := _rate_of(mult)
	if r == _clk_rate:
		return false
	var c := spin_clock(t)
	_clk = [t, c.x, c.y]
	_clk_rate = r
	return true


## A game begun or loaded: the clock the galaxy's own times the setting's rate.
static func reset_spin(mult: float) -> void:
	_clk = [0.0, 0.0, 0.0]
	_clk_rate = _rate_of(mult)


func _enter_tree() -> void:
	_leaving = false
	_stop[0] = false
	if COMPAT and not RenderingServer.frame_pre_draw.is_connected(_pre_draw):
		RenderingServer.frame_pre_draw.connect(_pre_draw)


## (The web's renderer) The terrain's planet transform, just before each frame is drawn
## (after everything's moved): there the shader has no instance uniforms for its patches'
## centres (each instance takes 16 of 4096 slots) - it works them out from this.
func _pre_draw() -> void:
	if material and is_inside_tree():
		material.set_shader_parameter("planet_inv", Projection(global_transform.affine_inverse()))


func _exit_tree() -> void:
	_leaving = true
	_stop[0] = true
	if RenderingServer.frame_pre_draw.is_connected(_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	if _flora_task != -1:
		WorkerThreadPool.wait_for_task_completion(_flora_task)
		_flora_task = -1
	if _cave_task != -1:
		WorkerThreadPool.wait_for_task_completion(_cave_task)
		_cave_task = -1
	if _water_task != -1:
		WorkerThreadPool.wait_for_task_completion(_water_task)
		_water_task = -1
	for p: Patch in _busy:
		if p.task != -1:
			WorkerThreadPool.wait_for_task_completion(p.task)
			p.task = -1
			tasks -= 1
	_busy.clear()
	for p: Patch in _stand_busy:
		if p.stand_task != -1:
			WorkerThreadPool.wait_for_task_completion(p.stand_task)
			p.stand_task = -1
	_stand_busy.clear()
	if _nf_task != -1:
		WorkerThreadPool.wait_for_task_completion(_nf_task)
		_nf_task = -1
