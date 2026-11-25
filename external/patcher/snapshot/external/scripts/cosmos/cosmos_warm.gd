class_name CosmosWarm
extends Node
## The 3D game's first-use work done at the title screen (as Warmup does for
## the 2D game), so the first flight into 3D space has no long frames: the
## noise texture made (on a worker), the shared unit spheres made, and one of
## every kind of 3D thing drawn - one a frame - in a small off-screen
## viewport set up as Cosmos's (the sky, a shadowed sun): the terrain, sea,
## atmosphere, clouds, gas giant, rings, star, glows, gate, engine, rocks and
## the plain materials of the hulls - their shaders compiled, their pipelines
## made (shadow passes too) - and the HUD's text sizes drawn once (the
## glyphs cached). Once a run; frees itself.

const PER_FRAME := 1
static var done := false

var _vp: SubViewport
var _queue: Array = []          # Callables, each adding one thing
var _wait := 3                  # frames to draw after the last one


func _ready() -> void:
	if done or DisplayServer.get_name() == "headless":
		queue_free()
		return
	done = true
	Cosmos.start_noise()
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
	_queue.append(_sky)
	for f in [_terrain, _water, _atmosphere, _clouds, _gas, _ring, _star, _glow, _gate, _engine, _rocks, _flora, _creature, _hulls, _walker, _pirate, _text]:
		_queue.append(f)


func _process(_delta: float) -> void:
	if _queue.is_empty():
		_wait -= 1
		if _wait <= 0:
			queue_free()
		return
	var noise := Cosmos.noise_ready()
	if noise == null:
		return   # (most of them sample it)
	for i in PER_FRAME:
		if _queue.is_empty():
			break
		(_queue.pop_front() as Callable).call()


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
	var sm := _shader("res://shaders/cosmos/sky.gdshader")
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
	var mi := _put(st.commit(), _shader("res://shaders/cosmos/terrain.gdshader"), Vector3.ZERO, true)
	mi.set_instance_shader_parameter("patch_centre", Vector3(0, 0, 1000))


func _water() -> void:
	_put(CosmosPlanet.unit_sphere(64, 32), _shader("res://shaders/cosmos/water.gdshader"), Vector3(-1, 0, 0))


func _atmosphere() -> void:
	_put(CosmosPlanet.unit_sphere(64, 32), _shader("res://shaders/cosmos/atmosphere.gdshader"), Vector3(1, 0, 0))


func _clouds() -> void:
	_put(CosmosPlanet.unit_sphere(128, 64), _shader("res://shaders/cosmos/clouds.gdshader"), Vector3(0, 1, 0))


func _gas() -> void:
	_put(CosmosPlanet.unit_sphere(128, 64), _shader("res://shaders/cosmos/gas_giant.gdshader"), Vector3(0, -1, 0))


func _ring() -> void:
	_put(QuadMesh.new(), _shader("res://shaders/cosmos/ring.gdshader"), Vector3(1, 1, 0))


func _star() -> void:
	_put(CosmosPlanet.unit_sphere(64, 32), _shader("res://shaders/cosmos/star.gdshader"), Vector3(-1, 1, 0))


func _glow() -> void:
	_put(QuadMesh.new(), _shader("res://shaders/cosmos/glow.gdshader"), Vector3(1, -1, 0))


func _gate() -> void:
	_put(QuadMesh.new(), _shader("res://shaders/cosmos/gate.gdshader"), Vector3(-1, -1, 0))


func _engine() -> void:
	var m := _shader("res://shaders/cosmos/engine.gdshader")
	_put(QuadMesh.new(), m, Vector3(0.5, 0.5, 0)).set_instance_shader_parameter("level", 1.0)
	var m2 := _shader("res://shaders/cosmos/engine.gdshader")
	m2.set_shader_parameter("glow", false)
	_put(CylinderMesh.new(), m2, Vector3(-0.5, 0.5, 0)).set_instance_shader_parameter("level", 1.0)


func _rocks() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = CosmosRocks._rock_mesh(1)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.3), Vector3(0.5, -0.5, 0)))
	mm.set_instance_custom_data(0, Color(0.3, 0.6, 0.2, 0.7))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shader("res://shaders/cosmos/rock.gdshader")
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
	mat.shader = load("res://shaders/cosmos/flora.gdshader")
	mmi.material_override = mat
	_vp.add_child(mmi)


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


func _creature() -> void:
	var m := _shader("res://shaders/cosmos/creature.gdshader")
	_put(CosmosPlanet.unit_sphere(64, 32), m, Vector3(0.3, -0.3, 0.5), true)


func _pirate() -> void:
	if not Stage3D.has_model("pirate"):
		return
	var model: Node3D = Stage3D._scene("pirate").instantiate()
	model.scale = Vector3.ONE * 0.5
	model.position = Vector3(0.6, -1, 0)
	_vp.add_child(model)
	CosmosModels.apply(model, "pirate")   # (the merged mesh made now, its shaders compiled)


func _text() -> void:
	var c := Control.new()
	c.size = Vector2(96, 96)
	c.draw.connect(func():
		for fs in CosmosHud.SIZES:
			c.draw_string_outline(ThemeDB.fallback_font, Vector2(0, 40), "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ .,:;-+()/%", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
			c.draw_string(ThemeDB.fallback_font, Vector2(0, 40), "0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ .,:;-+()/%", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	_vp.add_child(c)
