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
const MESH_BUDGET_US := 1500    # main-thread time a frame turning built patches into meshes (all planets)
const TERRAIN := preload("res://shaders/cosmos/terrain.gdshader")
const WATER := preload("res://shaders/cosmos/water.gdshader")
const ATMO := preload("res://shaders/cosmos/atmosphere.gdshader")
const CLOUDS := preload("res://shaders/cosmos/clouds.gdshader")
const GAS := preload("res://shaders/cosmos/gas_giant.gdshader")
const RING := preload("res://shaders/cosmos/ring.gdshader")

static var tasks := 0           # building now, all planets
static var deadline_us := 0     # (meshes made until then: Cosmos sets it each frame)

var rec := {}
var shape: PlanetShape
var radius := 1000.0
var max_level := 6
var sun_dir := Vector3.UP       # (to the star, world - set by Cosmos)
var material: ShaderMaterial
var atmo_radius := 0.0
var _roots: Array = []
var _busy: Array = []           # patches whose builds are running
var _sea_mi: MeshInstance3D
var _sea_low: Mesh
var _sea_high: Mesh
var _cam_local := Vector3(1e9, 0, 0)
var _horizon := PI
var deepest_hint := 0
var _cam_dir := Vector3.RIGHT
var patches_made := 0
var _rock_mat: ShaderMaterial
var flora: Array = []           # the species (CosmosFlora.design), built on a worker at setup
var flora_ready := false
var _flora_task := -1
var _flora_meshes: Array = []
var _flora_mat: ShaderMaterial
static var _rock_mesh: Mesh


static func rock_mesh() -> Mesh:
	if _rock_mesh == null:
		_rock_mesh = CosmosRocks._rock_mesh(77)
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


func setup(record: Dictionary, noise: Texture3D) -> void:
	rec = record
	name = str(rec.get("name", "Planet")).replace(" ", "_")
	shape = PlanetShape.of(rec)
	radius = shape.radius
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
		if float(L.get("rings", 0.0)) > 0.0:
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
	material.set_shader_parameter("amp", shape.amp)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("sea", shape.sea)
	material.set_shader_parameter("noise_tex", noise)
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = preload("res://shaders/cosmos/rock.gdshader")
	_rock_mat.set_shader_parameter("noise_tex", noise)
	var lh: Color = L.get("land_high", Color(0.4, 0.38, 0.35))
	_rock_mat.set_shader_parameter("tone", lh.lerp(Color(0.42, 0.4, 0.38), 0.4))
	_flora_mat = ShaderMaterial.new()
	_flora_mat.shader = preload("res://shaders/cosmos/flora.gdshader")
	var fseed := int(rec.get("seed", 1))
	var ftype := str(rec.get("type", "rocky"))
	_flora_task = WorkerThreadPool.add_task(func(): flora = CosmosFlora.design(shape, fseed, ftype), true, "planet flora")
	for f in 6:
		var p := Patch.new()
		p.face = f
		p.a0 = -1.0
		p.b0 = -1.0
		p.span = 2.0
		_place(p)
		_roots.append(p)
		_start(p)
	if shape.sea > 0:
		_add_sea(L, noise)
	if float(L.get("clouds", 0.0)) > 0.05 and atmo_k > 0.3:
		_add_clouds(L, noise)
	atmo_radius = radius + maxf(shape.top() * 2.5, radius * 0.06)
	_add_atmosphere(atmo_col, atmo_k)


## Built enough to be seen: every face's first patch is in.
func settled() -> bool:
	for p: Patch in _roots:
		if not p.ready:
			return false
	return true


func _place(p: Patch) -> void:
	var ax := PlanetShape.face_axes(p.face)
	p.dir = PlanetShape.face_dir(ax[0], ax[1], ax[2], p.a0 + p.span * 0.5, p.b0 + p.span * 0.5)
	p.centre = p.dir * (radius + shape.surface(p.dir))
	p.size = radius * p.span * 0.9


func _start(p: Patch) -> void:
	tasks += 1
	_busy.append(p)
	p.task = WorkerThreadPool.add_task(_build.bind(p, p.face, p.a0, p.b0, p.span, p.centre), true, "planet patch")


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
	var V := PATCH + 1
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
			uvs[j * V + i] = Vector2(hs[k], 0.0)
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
		var d := PlanetShape.face_dir(n, u, v, a0 + rng.randf() * span, b0 + rng.randf() * span)
		var size := pow(rng.randf(), 4.0) * 2.4 + 0.15
		var e := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var sy := rng.randf_range(0.5, 0.9)
		var sz := rng.randf_range(0.8, 1.2)
		if coarse and size < 1.0:
			continue
		var h := shape.height(d)
		if shape.sea > 0 and h < 0.4:
			continue
		var at := d * (radius + h - size * 0.3)
		p.rock_xf.append(Transform3D(Basis.from_euler(e).scaled(Vector3(size, size * sy, size * sz)), at - centre))
		p.rocks.append([at, size * 0.8, size * 0.7])
	if not flora_ready:
		return
	var step := 1.2 / radius
	for k in flora.size():
		var sp: Dictionary = flora[k]
		var dens: float = sp["density"]
		var patchy := rng.randf()
		var m := int(dens * area * (0.3 + patchy * 1.4) + rng.randf())
		for i in m:
			var d := PlanetShape.face_dir(n, u, v, a0 + rng.randf() * span, b0 + rng.randf() * span)
			var sc: float = rng.randf_range(sp["size"].x, sp["size"].y)
			var turn := rng.randf() * TAU
			if coarse and float(sp["solid"]) <= 0.0:
				continue
			var h := shape.height(d)
			var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var slope := absf(shape.height((d + t * step).normalized()) - h) / 1.2
			if not CosmosFlora.grows(sp, shape, h, slope):
				continue
			var x := t.rotated(d, turn)
			var b := Basis(x, d, x.cross(d)).scaled(Vector3.ONE * sc)
			var at := d * (radius + h - 0.08 * sc)
			p.flora_xf[k] = p.flora_xf.get(k, []) + [Transform3D(b, at - centre)]
			if float(sp["solid"]) > 0.0:
				p.rocks.append([at, float(sp["solid"]) * sc, 6.0 * sc])


## Called by Cosmos a few times a second: the camera's planet-local position.
func update_lod(cam_local: Vector3) -> void:
	if shape.kind == "gas":
		return
	_cam_local = cam_local
	_collect()
	# (the horizon, once a visit: patches beyond it aren't drawn)
	var h := cam_local.length()
	var top := radius + shape.top()
	h = maxf(h, radius + 1.0)
	_horizon = acos(clampf(radius / h, -1.0, 1.0)) + acos(clampf(radius / top, -1.0, 1.0))
	_cam_dir = cam_local.normalized()
	deepest_hint = 0
	for p: Patch in _roots:
		_visit(p)
		if not p.kids.is_empty():
			deepest_hint = 2   # (split somewhere: visited until it's merged back)
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
	if _flora_task != -1 and WorkerThreadPool.is_task_completed(_flora_task):
		WorkerThreadPool.wait_for_task_completion(_flora_task)
		_flora_task = -1
		for sp: Dictionary in flora:
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sp["arrays"])
			_flora_meshes.append(m)
		flora_ready = true
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
		mi.visible = false
		mi.set_instance_shader_parameter("patch_centre", p.centre)
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
			fm.mesh = _flora_meshes[k]
			fm.instance_count = buf.size() / 12
			fm.buffer = buf
			var fmi := MultiMeshInstance3D.new()
			fmi.multimesh = fm
			fmi.material_override = _flora_mat
			var solid: bool = float(flora[k]["solid"]) > 0.0
			fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if solid else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# (draw distances: the small plants only near - their patches' draw calls go)
			fmi.visibility_range_end = {"grass": 42.0, "flower": 38.0, "bush": 80.0, "fungus": 100.0}.get(str(flora[k]["kind"]), 0.0)
			if solid and p.level == max_level:
				fmi.visibility_range_end = 0.0
			mi.add_child(fmi)
		p.flora_buf = {}


func _visit(p: Patch) -> void:
	var d := _cam_local.distance_to(p.centre)
	var limit := p.size * SPLIT * (KEEP if not p.kids.is_empty() else 1.0)
	if p.level < max_level and d < limit:
		if p.kids.is_empty() and tasks < MAX_TASKS:
			_split(p)
		if not p.kids.is_empty() and _kids_ready(p):
			_show(p, false)
			p.sub = true
			for k: Patch in p.kids:
				_visit(k)
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


func _split(p: Patch) -> void:
	var h := p.span * 0.5
	for q in 4:
		var k := Patch.new()
		k.face = p.face
		k.level = p.level + 1
		k.span = h
		k.a0 = p.a0 + h * (q % 2)
		k.b0 = p.b0 + h * (q / 2)
		_place(k)
		p.kids.append(k)
		_start(k)


func _kids_ready(p: Patch) -> bool:
	for k: Patch in p.kids:
		if not k.ready:
			return false
	return true


func _subtree_busy(p: Patch) -> bool:
	for k: Patch in p.kids:
		if k.task != -1 or _subtree_busy(k):
			return true
	return false


func _drop_kids(p: Patch) -> void:
	for k: Patch in p.kids:
		_drop_kids(k)
		if k.mi:
			k.mi.queue_free()
	p.kids.clear()


func _hide(p: Patch) -> void:
	_show(p, false)
	if p.sub:
		p.sub = false
		for k: Patch in p.kids:
			_hide(k)


## Not hidden behind the planet's own horizon (from the camera).
func _in_sight(p: Patch) -> bool:
	return acos(clampf(_cam_dir.dot(p.dir), -1.0, 1.0)) < _horizon + p.size / radius * 0.8


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


## Boulders within `reach` of planet-local `local` on the patches drawn now:
## [planet-local position, radius] each.
func rocks_near(local: Vector3, reach: float) -> Array:
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


func _add_clouds(L: Dictionary, noise: Texture3D) -> void:
	var m := ShaderMaterial.new()
	m.shader = CLOUDS
	m.render_priority = 1
	m.set_shader_parameter("cover", float(L.get("clouds", 0.5)))
	m.set_shader_parameter("scale", float(L.get("cloud_scale", 2.2)))
	m.set_shader_parameter("tint", L.get("cloud_color", Color.WHITE))
	m.set_shader_parameter("seed", float(L.get("seed", 0.0)))
	m.set_shader_parameter("noise_tex", noise)
	_ball(radius + shape.top() * 1.3 + 40.0, 128, 64, m, "Clouds")


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
	mi.rotation = Vector3(float(L.get("incline", 0.3)) * 0.6, 0.0, float(L.get("tilt", 0.2)))
	add_child(mi)


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


func set_sun(dir: Vector3) -> void:
	sun_dir = dir
	for c in get_children():
		if c is GeometryInstance3D and c.material_override is ShaderMaterial:
			(c.material_override as ShaderMaterial).set_shader_parameter("sun_dir", dir)
	if material:
		material.set_shader_parameter("sun_dir", dir)


func _exit_tree() -> void:
	if _flora_task != -1:
		WorkerThreadPool.wait_for_task_completion(_flora_task)
		_flora_task = -1
	for p: Patch in _busy:
		if p.task != -1:
			WorkerThreadPool.wait_for_task_completion(p.task)
			p.task = -1
			tasks -= 1
	_busy.clear()
