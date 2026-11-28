class_name CosmosWarm
extends Node
## The 3D game's first-use work done at the title screen (as Warmup does for
## the 2D game), so the first flight into 3D space has no long frames: the
## noise texture made (on a worker), the shared unit spheres made, and one of
## every kind of 3D thing drawn - one a frame - in a small off-screen
## viewport set up as Cosmos's (the sky, a shadowed sun): the terrain, sea,
## atmosphere, clouds, gas giant, rings, star, glows, gate, engine, effects, rocks and
## the plain materials of the hulls - their shaders compiled, their pipelines
## made (shadow passes too) - and the HUD's text sizes drawn once (the
## glyphs cached). And the scripts and scenes a first game needs loaded on
## a thread meanwhile (PRELOAD: the player's data, the missions, the HUD) -
## else pressing New game stops for their loading. Once a run; frees itself.

const PER_FRAME := 1
## Loaded in the background at the title; kept (`_pre`), so the game's own load() finds them ready.
## First what a new game needs to show (the scene, the HUD, you, the start city's people -
## the game waits for these: loads_done), then the rest (asked for once those are in, not
## sharing the threads with them: in a browser, each model takes seconds).
const PRELOAD := ["res://scenes/world/cosmos.tscn", "res://scripts/sim/player_data.gd", "res://scripts/sim/missions.gd", "res://scenes/ui/hud.tscn"]
const FIRST_PEOPLE := ["player", "minoan", "guard", "kilon"]
const LATER := ["res://scenes/ui/ship_menu.tscn", "res://scenes/ui/station_menu.tscn"]
const LATER_PEOPLE := ["pirate", "athenian", "spartan", "mycenaean", "ionian", "cycladic"]
static var _later_asked := false
static var done := false
static var _pre := {}
## Every material drawn here, kept for the run: a standard material's shader (and
## the pipelines made for it) lives only while a material with its features does.
static var _kept: Array = []

var _vp: SubViewport
var _queue: Array = []          # Callables, each adding one thing
var _wait := 3                  # frames to draw after the last one


## (A browser) A few of the drawings, under the loading screen while the 3D scene builds
## (Cosmos._build): what's seen in the first seconds - you, the townspeople, the town, the
## plants, the creatures - else each first draw stopped the game a fifth of a second as it
## came into view (the shader compiled, the people's meshes merged). `drawn`: done.
static var drawn := false
var draw_only: Array = []


static func draw_in(parent: Node, which: Array) -> void:
	if drawn or DisplayServer.get_name() == "headless":
		drawn = true
		return
	var w := CosmosWarm.new()
	w.draw_only = which
	parent.add_child(w)


func _ready() -> void:
	if (done and draw_only.is_empty()) or DisplayServer.get_name() == "headless":
		queue_free()
		return
	done = true
	_ask(_first())
	if not OS.has_feature("web"):
		_ask(_later())   # (the desktop: all at once, as ever - it takes them in its stride)
	Cosmos.start_noise()
	CosmosDragonfly.start()   # (its shared mesh on a worker now: ready when _creature draws it)
	CosmosAeromanta.start()
	CosmosFox.start()
	CosmosMammoth.start()
	if not OS.has_feature("web"):   # (in a browser: started by the game, when it needs them - not sharing the threads with the first loads)
		CosmosShip.start_hull()                 # (your ship's hull and rooms: made on workers now)
		CosmosShipInterior.start_dress()
	for k in [[64, 32], [384, 192], [128, 64]]:
		CosmosPlanet.unit_sphere(k[0], k[1]).get_rid()   # (made now, not in a build)
	_vp = SubViewport.new()
	_vp.size = Vector2i(96, 96)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var cam := Camera3D.new()
	cam.near = 0.25
	cam.far = 600000.0
	_vp.add_child(cam)
	cam.position = Vector3(0, 0, 6)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.rotation = Vector3(-0.8, 0.5, 0)
	_vp.add_child(light)
	# (a point light and a spot too, as the game has - stations' floodlights, the ship's lamps,
	# the walker's: everything's pipelines made for a scene lit that way)
	var omni := OmniLight3D.new()
	omni.position = Vector3(0, 1.5, 2)
	omni.omni_range = 8.0
	omni.shadow_enabled = false
	_vp.add_child(omni)
	var spot := SpotLight3D.new()
	spot.position = Vector3(1.5, 0, 4)
	spot.spot_range = 10.0
	spot.shadow_enabled = false
	_vp.add_child(spot)
	if not draw_only.is_empty():
		for f in draw_only:
			_queue.append(Callable(self, f))
		return
	if OS.has_feature("web"):
		# (In a browser each shader's compile stops the page for up to a second: drawn here, the
		# title froze for ~15 s and Start game seemed dead. There a few are drawn under the
		# loading screen (draw_in) and the rest as they're first seen; the loads above still run.)
		_queue.append(_text)
		return
	_queue.append(_sky)
	for f in [_terrain, _water, _atmosphere, _clouds, _weather, _gas, _ring, _star, _glow, _gate, _engine, _fx, _fx_smoke, _fx_debris, _rocks, _deposit, _minoan, _flora, _creature, _veins, _underwater, _hulls, _walker, _pirate, _citizen, _town, _roads, _loot, _builds, _maps, _text]:
		_queue.append(f)


func _process(_delta: float) -> void:
	tick_loads()   # (the background loads: taken as they finish, the later ones asked for after the first)
	if _queue.is_empty():
		_wait -= 1
		if _wait <= 0 and _preloads_in():
			for n in _vp.find_children("*", "GeometryInstance3D", true, false):
				var mat: Material = (n as GeometryInstance3D).material_override
				if mat != null and not _kept.has(mat):
					_kept.append(mat)
			# (the labels themselves kept, hidden, for the run: their material is their own)
			var keep := Node3D.new()
			keep.name = "CosmosWarmKept"
			keep.visible = false
			get_tree().root.add_child.call_deferred(keep)
			for n in _vp.get_children():
				if n.has_meta("keep"):
					_vp.remove_child(n)
					keep.add_child(n)
			if not draw_only.is_empty():
				drawn = true
			queue_free()
		return
	var noise := Cosmos.noise_ready()
	if noise == null:
		return   # (most of them sample it)
	for i in PER_FRAME:
		if _queue.is_empty():
			break
		(_queue.pop_front() as Callable).call()


## The background loads all taken (or failed: not waited for).
## What's loaded in the background: PRELOAD, and the people's models (a town's, a
## hangar's crew - each a few MB: not loaded the moment you dock).
static func _preloads() -> Array:
	return _first() + _later()


## (A browser) Scripts and the scenes made of them, loaded on the main thread a thing a
## frame under the loading screen (load_direct) - not on a thread: there a script's load
## waits on the main thread step by step, and the HUD's (with all it uses) took ~30 s.
const DIRECT := ["res://scripts/sim/player_data.gd", "res://scripts/sim/missions.gd", "res://scenes/ui/hud.tscn", "res://scenes/ui/ship_menu.tscn", "res://scenes/ui/station_menu.tscn"]


## (A browser) The next of DIRECT loaded now (a frame's work); false once all are in.
static func load_direct() -> bool:
	for path in DIRECT:
		if not _pre.has(path):
			_pre[path] = load(path)
			return true
	return false


static func _first() -> Array:
	var out: Array = PRELOAD.duplicate()
	if OS.has_feature("web"):
		out = out.filter(func(p): return not p in DIRECT)
	for id in FIRST_PEOPLE:
		out.append("res://art/%s_3d/%s.glb" % [id, id])
	return out


static func _later() -> Array:
	var out: Array = LATER.duplicate() if not OS.has_feature("web") else []
	for id in LATER_PEOPLE:
		out.append("res://art/%s_3d/%s.glb" % [id, id])
	return out


static func _ask(paths: Array) -> void:
	for path in paths:
		if ResourceLoader.exists(path) and not _pre.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


## The loads under way taken as they finish, the later ones asked for once the first are
## in (the title, and the game a few times a second - CosmosWarm's node goes with the title).
## True when all are in.
static func tick_loads() -> bool:
	var first := true
	for path in _first():
		if not _take(path):
			first = false
	if not first:
		return false
	if not _later_asked:
		_later_asked = true
		_ask(_later())
	var all := true
	for path in _later():
		if not _take(path):
			all = false
	return all


## (One path) Loaded (now kept in _pre) - or not being loaded at all.
static func _take(path: String) -> bool:
	if _pre.has(path) or not ResourceLoader.exists(path):
		return true
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		ResourceLoader.THREAD_LOAD_LOADED:
			_pre[path] = ResourceLoader.load_threaded_get(path)
	return true


## (Cosmos._build waits on it, a frame at a time) The background loads all in: a load()
## of one still loading stops the frame till it's done - in a browser, a second or more.
static func loads_done() -> bool:
	tick_loads()
	for path in _first():
		if not _take(path):
			return false
	return true


func _preloads_in() -> bool:
	return tick_loads()


func _put(mesh: Mesh, mat: Material, at := Vector3.ZERO, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(mi)
	return mi


func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	return m


func _sky() -> void:
	var sm := _shader("res://shaders/world/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true      # (as Cosmos: the bloom's shaders compiled here)
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)


func _terrain() -> void:
	# (a patch's mesh as the planets make them: vertices, normals, UVs, an index)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-1, -1, 0), Vector3(1, 1, 0), Vector3(1, -1, 0)]:
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(v)
	st.index()
	var mi := _put(st.commit(), _shader("res://shaders/world/terrain.gdshader"), Vector3.ZERO, true)
	mi.set_instance_shader_parameter("patch_info", Vector4(0, 0, 1000, 0))


func _water() -> void:
	_put(CosmosPlanet.unit_sphere(64, 32), _shader("res://shaders/world/water.gdshader"), Vector3(-1, 0, 0))
	# (a sea world's water - CosmosWaters: the far sphere, the near grid, a lake's, a river's - each its mesh's own layout)
	var L := {}
	_put(CosmosPlanet.unit_sphere(64, 32), CosmosWaters.sea_material(L, 1.0), Vector3(-1, 0.5, 0))
	_put(CosmosWaters.near_mesh(), CosmosWaters.material(L, 1), Vector3(-1, -0.5, 0))
	var wm := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr.duplicate())   # (a lake's)
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2.RIGHT])
	var rm := ArrayMesh.new()
	rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)   # (a river's)
	_put(wm, CosmosWaters.material(L, 2), Vector3(-1.5, 0, 0))
	_put(rm, CosmosWaters.material(L, 3), Vector3(-1.5, 0.5, 0))


func _atmosphere() -> void:
	_put(CosmosPlanet.unit_sphere(64, 32), _shader("res://shaders/world/atmosphere.gdshader"), Vector3(1, 0, 0))


func _clouds() -> void:
	_put(CosmosPlanet.unit_sphere(128, 64), _shader("res://shaders/world/clouds.gdshader"), Vector3(0, 1, 0))


func _weather() -> void:   # (the rain, the snow, the ash, a bolt of lightning: their particles' and looks' shaders)
	for k in CosmosWeatherFx.KINDS:
		var gp := CosmosWeatherFx.make_particles(k)
		gp.amount = 8
		gp.position = Vector3(0, 0, 2)
		gp.emitting = true
		_vp.add_child(gp)
	_put(QuadMesh.new(), CosmosWeatherFx.bolt_mat(), Vector3(0.5, 0.5, 0))


func _gas() -> void:
	_put(CosmosPlanet.unit_sphere(128, 64), _shader("res://shaders/world/gas_giant.gdshader"), Vector3(0, -1, 0))


func _ring() -> void:
	_put(QuadMesh.new(), _shader("res://shaders/world/ring.gdshader"), Vector3(1, 1, 0))


func _star() -> void:
	_put(CosmosPlanet.unit_sphere(64, 32), _shader("res://shaders/world/star.gdshader"), Vector3(-1, 1, 0))


func _glow() -> void:
	_put(QuadMesh.new(), _shader("res://shaders/world/glow.gdshader"), Vector3(1, -1, 0))


func _gate() -> void:
	_put(QuadMesh.new(), _shader("res://shaders/world/gate.gdshader"), Vector3(-1, -1, 0))


func _engine() -> void:
	var m := _shader("res://shaders/world/engine.gdshader")
	_put(QuadMesh.new(), m, Vector3(0.5, 0.5, 0)).set_instance_shader_parameter("level", 1.0)
	var m2 := _shader("res://shaders/world/engine.gdshader")
	m2.set_shader_parameter("glow", false)
	_put(CylinderMesh.new(), m2, Vector3(-0.5, 0.5, 0)).set_instance_shader_parameter("level", 1.0)


## The particle effects' materials (Fx: data/effects.json), as their emitters draw them
## (a shader a frame).
func _fx() -> void:
	Fx.warm_into(_vp, "add")


func _fx_smoke() -> void:
	Fx.warm_into(_vp, "smoke")


func _fx_debris() -> void:
	Fx.warm_into(_vp, "debris")


func _rocks() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = CosmosRocks._rock_mesh(1)[0]
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.3), Vector3(0.5, -0.5, 0)))
	mm.set_instance_custom_data(0, Color(0.3, 0.6, 0.2, 0.7))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shader("res://shaders/world/rock.gdshader")
	_vp.add_child(mmi)


func _deposit() -> void:
	var ms := CosmosDeposits.meshes()
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = ms[k]
		mi.material_override = CosmosDeposits._mat
		CosmosDeposits._mat.set_shader_parameter("noise_tex", Cosmos.noise_ready())
		_vp.add_child(mi)
		mi.position = Vector3(-0.6 + k * 1.2, -0.3, 0)
		mi.scale = Vector3.ONE * 0.4


func _minoan() -> void:
	# The empires' look (EmpireKit): the hulls', the insides', a station's - on a mesh of its own
	# kind (the Mesher's: colours and UVs in its vertices) - the windows, the hologram, the pads' shutters.
	var m := EmpireKit.Mesher.new()
	m.boxat(Vector3.ONE * 0.5, Vector3.ZERO, EmpireKit.MAIN)
	m.disc(Vector3(0, 0.26, 0), Vector3.UP, Vector3.FORWARD, 0.2, EmpireKit.ROUNDEL, 8)
	m.panel(Vector3(0, 0, 0.26), Vector3(0.2, 0, 0), Vector3(0, -0.2, 0), EmpireKit.FRIEZE, Vector3(0, 0, 1), 0.1)
	var mesh := m.commit()
	_put(mesh, EmpireKit.mat("hull"), Vector3(-0.6, 0.4, 0), true)
	_put(mesh, EmpireKit.cut_mat(EmpireKit.mat("hull")), Vector3(-0.3, 0.4, 0.3), true)   # (a trader's hull with its doorway: CosmosNpcInterior)
	_put(mesh, EmpireKit.mat("inside"), Vector3(0.6, 0.4, 0))
	_put(mesh, EmpireKit.mat("station"), Vector3(0, 0.4, -0.5), true)
	_put(mesh, EmpireKit.glass(), Vector3(-0.6, -0.4, 0))
	_put(BoxMesh.new(), EmpireKit.zone_mat(EmpireKit.STEEL), Vector3(0.6, -0.4, 0))
	_put(SphereMesh.new(), EmpireKit.holo(), Vector3(0, 0, 0.5))
	for mat in [EmpireKit.zone_mat(EmpireKit.IRON, "station"), CosmosStation._mat(Color(1, 0.6, 0.25), 0.0, 0.5, Color(1, 0.6, 0.25) * 3.0), EmpireKit.mat("inside")]:
		var mm := MultiMesh.new()   # (the shutters: instances of a box; the hold's crates: of the Mesher's)
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new() if mat != EmpireKit.mat("inside") else mesh
		mm.instance_count = 2
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.2), Vector3(-0.3, -0.8, 0)))
		mm.set_instance_transform(1, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.2), Vector3(0.3, -0.8, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		_vp.add_child(mmi)


func _flora() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var m := ArrayMesh.new()
	var rng := RandomNumberGenerator.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CosmosFlora._crystal(rng, Color.CYAN))
	mm.mesh = m
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.4), Vector3(-0.5, -0.5, 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world/flora.gdshader")
	mmi.material_override = mat
	_vp.add_child(mmi)
	# (the trees' own shader - their leaf cards cut into leaves - and their vertex layout: UV2)
	var lm := ArrayMesh.new()
	lm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CosmosFlora.warm_arrays())
	var lmi := MeshInstance3D.new()
	lmi.mesh = lm
	var lmat := ShaderMaterial.new()
	lmat.shader = load("res://shaders/world/leaf_flora.gdshader")
	lmi.material_override = lmat
	lmi.scale = Vector3.ONE * 0.4
	lmi.position = Vector3(0.5, -0.5, 0.5)
	_vp.add_child(lmi)
	# (the trees' and shrubs' levels of detail: a MultiMesh with custom data - each plant's size and
	# reach - and the impostor's cards, from its atlas: FloraLods)
	var im := MultiMesh.new()
	im.transform_format = MultiMesh.TRANSFORM_3D
	im.use_custom_data = true
	im.mesh = FloraLods.impostor_mesh()
	im.instance_count = 1
	im.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.4), Vector3(0.5, -0.5, -0.5)))
	im.set_instance_custom_data(0, Color(0.01, 1000.0, 0.6, 0.0))
	var imi := MultiMeshInstance3D.new()
	imi.multimesh = im
	imi.material_override = lmat
	_vp.add_child(imi)


func _veins() -> void:
	# (a scanned vein's hologram: its skin and its wire cage - triangles and lines)
	var mi := MeshInstance3D.new()
	mi.mesh = CosmosVeins.holo_mesh([{"pts": [Vector3(-1, 0, 0), Vector3(0, 0.3, 0), Vector3(1, 0, 0)], "r": 0.3, "col": Color(1, 0.6, 0.2, 1.0)}])
	var mats := CosmosVeins.holo_mats()
	mi.set_surface_override_material(0, mats[0])
	mi.set_surface_override_material(1, mats[1])
	_vp.add_child(mi)


func _underwater() -> void:
	# (under a sea: the full-screen look, its specks, the plants' and animals' shaders)
	CosmosUnderwater.warm(_vp)


func _hulls() -> void:
	# The stations' and ships' plain materials: lit, metal, glowing, shadowed.
	_put(BoxMesh.new(), CosmosStation._mat(Color(0.6, 0.6, 0.65), 0.55, 0.45), Vector3(-0.5, -0.5, 0), true)
	_put(BoxMesh.new(), CosmosStation._mat(Color(1, 0.8, 0.5), 0.0, 0.5, Color(1, 0.8, 0.5) * 3.0), Vector3(0, 0.5, 0), true)
	_put(TorusMesh.new(), CosmosStation._mat(Color(0.5, 0.5, 0.55), 0.7, 0.4), Vector3(0, -0.5, 0), true)


func _walker() -> void:
	# The automaton on foot (its cel shaders, skinned, in this lighting).
	if not Stage3D.has_model("player"):
		return
	var model: Node3D = Stage3D._scene("player").instantiate()
	model.scale = Vector3.ONE * 0.5
	_vp.add_child(model)
	CosmosModels.apply(model, "player")   # (the merged mesh made now, its shaders compiled)
	Stage3D.smooth_clips(model.find_child("AnimationPlayer", true, false), "player")
	# (its landing dust, its jet's heat haze; a port's glass, seen from both sides)
	_put(CosmosWalker.puff_mesh(), CosmosWalker.shimmer_mat(), Vector3(0.3, 0.2, 0.4))
	_put(QuadMesh.new(), CosmosHangar._glass_mat(), Vector3(0.0, -0.2, 0.4))
	_put(CylinderMesh.new(), CosmosWalker._flame_mat(), Vector3(0.0, 0.3, 0.4))   # (the boots' jet thrusters: their flames)
	_put(CosmosWalker.shield_mesh(), CosmosWalker.shield_mat(), Vector3(0.3, 0.3, 0.4))   # (the automaton's shield: its bubble on a hit)
	_put(BoxMesh.new(), LiveEditor.box_material(), Vector3(0.0, -0.5, 0.4))   # (the Live Editor's lines: what's picked)
	_put(BoxMesh.new(), SelectOutline.material(), Vector3(-0.6, -0.5, 0.4))   # (the outline round what's picked)
	var ct: GDScript = load("res://scripts/world/live/tabs/collision_tab.gd")
	for through in [false, true]:   # (the Collision tab's lines: solids, seen through walls or not)
		_put(BoxMesh.new(), ct._material(through), Vector3(0.6, -0.5, 0.4))


func _creature() -> void:
	var m := _shader("res://shaders/world/creature.gdshader")
	_put(CosmosPlanet.unit_sphere(64, 32), m, Vector3(0.3, -0.3, 0.5), true)
	# The dragonfly's own model (CosmosDragonfly): its body and glassy wings (two shaders), the shared mesh made now.
	var dm := CosmosDragonfly.materials(Color(0.2, 0.45, 0.7), Color(0.6, 0.85, 0.9))
	var df := _put(CosmosDragonfly.mesh(), null, Vector3(-0.3, -0.3, 0.5), true)
	df.set_surface_override_material(0, dm[0])
	df.set_surface_override_material(1, dm[1])
	# The aeromanta's own model (CosmosAeromanta): its skin and wave shader, the shared mesh made now.
	_put(CosmosAeromanta.mesh(), CosmosAeromanta.material(Color(0.2, 0.35, 0.6), Color(0.85, 0.9, 1.0)), Vector3(0.0, -0.4, 0.6), true)
	# The red fox's own model (CosmosFox): its fur shader on a skinned mesh, the shared mesh made now.
	var fox_sk := CosmosFox.skeleton()
	fox_sk.position = Vector3(-0.6, -0.6, 0.5)
	fox_sk.scale = Vector3.ONE * 0.5
	_vp.add_child(fox_sk)
	var fox := MeshInstance3D.new()
	fox.mesh = CosmosFox.mesh()
	fox.skin = CosmosFox.skin()
	fox.material_override = CosmosFox.material(Color(0.85, 0.42, 0.15), Color(0.95, 0.92, 0.88))
	fox_sk.add_child(fox)
	fox.skeleton = NodePath("..")
	# The mushroom mammoth's own model (CosmosMammoth): its skin-and-fungus shader on a skinned mesh, the shared mesh made now.
	var mam_sk := CosmosMammoth.skeleton()
	mam_sk.position = Vector3(0.6, -0.6, 0.4)
	mam_sk.scale = Vector3.ONE * 0.3
	_vp.add_child(mam_sk)
	var mam := MeshInstance3D.new()
	mam.mesh = CosmosMammoth.mesh()
	mam.skin = CosmosMammoth.skin()
	mam.material_override = CosmosMammoth.material(Color(0.45, 0.4, 0.38), Color(0.75, 0.2, 0.15))
	mam_sk.add_child(mam)
	mam.skeleton = NodePath("..")


func _pirate() -> void:
	if not Stage3D.has_model("pirate"):
		return
	var model: Node3D = Stage3D._scene("pirate").instantiate()
	model.scale = Vector3.ONE * 0.5
	model.position = Vector3(0.6, -1, 0)
	_vp.add_child(model)
	CosmosModels.apply(model, "pirate")   # (the merged mesh made now, its shaders compiled)
	Stage3D.smooth_clips(model.find_child("AnimationPlayer", true, false), "pirate")   # (its clips' glitches mended now, not when one first appears)


func _citizen() -> void:
	# A town's citizen: the automaton recoloured (its own material).
	if not Stage3D.has_model("player"):
		return
	var model: Node3D = Stage3D._scene("player").instantiate()
	model.position = Vector3(1.0, -1.0, 0)
	_vp.add_child(model)
	CosmosModels.apply(model, "player", [Color(0.9, 0.8, 0.6, 0.85), Color(0.6, 0.1, 0.07), Color(1, 0.6, 0.2, 0.8)])
	# The towns' people: the Minoan android with each weapon, the guard, Kilon Alios.
	for v in [["minoan", ["MIN_Bow", "MIN_Axe"]], ["minoan", ["MIN_Rifle", "MIN_Axe"]], ["minoan", ["MIN_Rifle", "MIN_Bow"]], ["guard", []], ["kilon", []], ["skeleton", []], ["demon", []]]:
		if Stage3D.has_model(v[0]):
			var m2: Node3D = Stage3D._scene(v[0]).instantiate()
			m2.position = Vector3(-1.0, -1.0, 0)
			_vp.add_child(m2)
			CosmosModels.apply(m2, v[0], [], v[1])
			Stage3D.smooth_clips(m2.find_child("AnimationPlayer", true, false), v[0])


func _town() -> void:
	# The towns' buildings (one shader: their palette as parameters).
	_put(BoxMesh.new(), CosmosTown.material("minoa"), Vector3(-1.5, 0, 0), true).set_instance_shader_parameter("lamp_lit", 1.0)
	# Their lamps' glows on the ground by night (TownLamps: added on, unshaded).
	_put(QuadMesh.new(), TownLamps.pool_material(), Vector3(1.5, 0, 0)).set_instance_shader_parameter("lamp_lit", 1.0)


func _builds() -> void:
	# The building kit (BuildKit): its own copy of the building shader (paints, the
	# flames' glow, bronze trim) and the builder's translucent previews.
	_put(BoxMesh.new(), BuildKit.material("minoa"), Vector3(-1.5, 0, 0), true)
	for k in ["ok", "bad", "pick"]:
		_put(BoxMesh.new(), BuildKit.ghost_material(k), Vector3(1.5, 0, 0))


func _maps() -> void:
	# The Automaton's 3D maps (MapKit): a world and a star (one shader), lines,
	# glows, the reference plane (with a fog texture), the planet map's globe and points.
	var L := MapKit.Lines.new()
	L.seg(Vector3(-1, 0, 0), Vector3(1, 0, 0), Color.WHITE, 2.0, 3.0, 1.0)
	_vp.add_child(L.into(null))
	_put(MapKit.sphere(), MapKit.body_material({"color_light": Color.WHITE}), Vector3(-1.5, 0, 0))
	_put(MapKit.sphere(), MapKit.body_material({}, true), Vector3(1.5, 0, 0))
	var g := MapKit.glows(1)
	MapKit.set_glow(g, 0, Vector3.ZERO, 1.0, Color.WHITE)
	_vp.add_child(g)
	var pm := PlaneMesh.new()
	var mat := MapKit.plane_material()
	mat.set_shader_parameter("has_fog", 1.0)
	var img := Image.create(4, 4, false, Image.FORMAT_LA8)
	mat.set_shader_parameter("fog_tex", ImageTexture.create_from_image(img))
	_put(pm, mat)
	var fimg := Image.create(4, 4, false, Image.FORMAT_L8)
	var gm := MapKit.globe_material(ImageTexture.create_from_image(fimg))
	var garr := []   # (the globe's own vertex format: positions, normals, colours, UVs, indices)
	garr.resize(Mesh.ARRAY_MAX)
	garr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(0, 2, 0)])
	garr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	garr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	garr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	garr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1])
	var ball := ArrayMesh.new()
	ball.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, garr)
	gm.set_shader_parameter("sea_kind", 1.0)
	_put(ball, gm)
	var pts := MeshInstance3D.new()
	pts.mesh = MapKit.points(PackedVector3Array([Vector3.ZERO]), PackedColorArray([Color.WHITE]), PackedFloat32Array([1.0]))
	pts.material_override = MapKit.points_material()
	_vp.add_child(pts)


func _text() -> void:
	# The flight HUD's text: its own font (the game's theme's), every size it draws at, outlined
	# and plain - the glyphs made now, not in the game's first frame. A pad's number too (a Label3D).
	var c := Control.new()
	c.size = Vector2(96, 96)
	c.draw.connect(func():
		var f := c.get_theme_default_font()
		var chars := "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ .,:;-+()/%'!?<>=°x·"
		for font in ([f, ThemeDB.fallback_font] if f != ThemeDB.fallback_font else [f]):
			for fs in CosmosHud.SIZES:
				c.draw_string_outline(font, Vector2(0, 40), chars, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
				c.draw_string(font, Vector2(0, 40), chars, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	_vp.add_child(c)
	# The flight sights' cut (CosmosHud: the ship over them) - its canvas shader on lines, arcs,
	# polygons and text; and the ship's mask drawn as it is (alone, on a clear, see-through ground).
	var m := Control.new()
	m.size = Vector2(96, 96)
	m.material = CosmosHud.mask_material()
	m.draw.connect(func():
		m.draw_arc(Vector2(40, 40), 20.0, 0, TAU, 16, Color.WHITE, 3.0)
		m.draw_line(Vector2(0, 0), Vector2(90, 90), Color.WHITE, 1.0)
		m.draw_multiline(PackedVector2Array([Vector2(0, 5), Vector2(9, 5)]), Color.WHITE, 1.0)
		m.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(9, 0), Vector2(5, 9)]), Color.WHITE)
		m.draw_string(m.get_theme_default_font(), Vector2(0, 60), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE))
	_vp.add_child(m)
	var mvp := SubViewport.new()
	mvp.size = Vector2i(48, 48)
	mvp.transparent_bg = true
	mvp.positional_shadow_atlas_size = 0
	mvp.world_3d = _vp.find_world_3d()
	mvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var mcam := Camera3D.new()
	mcam.environment = Environment.new()
	mcam.environment.background_mode = Environment.BG_CLEAR_COLOR
	mcam.position = Vector3(0, 0, 6)
	mvp.add_child(mcam)
	add_child(mvp)
	for billboard in [false, true]:   # (a pad's number; a terminal's name, turned to you)
		var l := Label3D.new()
		l.text = "0123456789"
		l.font_size = 64
		l.pixel_size = 0.01
		l.position = Vector3(0, -0.9, 0)
		if billboard:
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.set_meta("keep", true)
		_vp.add_child(l)


## The roads between the towns (CosmosRoads: their ribbons' shader).
func _roads() -> void:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/world/road.gdshader")
	_put(CosmosRoads.warm_mesh(), m, Vector3(0, -1, 0))


## The loot of the dead (CosmosLoot: the pouch).
func _loot() -> void:
	_put(CosmosLoot.mesh(), CosmosLoot.material(), Vector3(0.8, -0.6, 0))
