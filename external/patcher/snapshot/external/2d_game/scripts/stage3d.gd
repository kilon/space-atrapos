class_name Stage3D
extends Node
## The 3D stage: where the game's 3D characters are drawn, live, for its 2D
## world (the first step of the game turning 3D: the automaton on foot is its
## actual model - art/player_3d/player.glb, exported from Blender by
## external/blender/automaton/build.py "export" - not pictures of it).
##
## One SubViewport (a world of its own, transparent) holds a row of up to SLOTS
## cells, CELL px each; a character claims a cell (claim) and gets its model
## there - one skinned mesh, the kit's cel shading remade as shaders
## (shaders/toon_part, flat_part: the colours from model.json), its ink outline
## the mesh's inverted hull - seen by one orthographic camera from the game's
## angle (ELEVATION above the horizon), lit by one light fixed to the camera. A
## Sprite2D in the 2D world shows the cell (region(): SheetPuppet's model mode),
## standing on ANCHOR. The stage redraws HZ times a second, when it has
## characters: each is asked to pose itself (its `pose` callable) just before.
## Models are loaded and their shaders compiled on the loading screen (warm);
## freed cells keep their model for the next one.

const CELL := Vector2i(512, 640)
const SLOTS := 4
const PX_PER_M := 135.0
const ANCHOR := Vector2(256.0, 480.0)       # where a character stands in its cell (px)
const ELEVATION := 22.0                     # the camera above the horizon (degrees: the sprites' too)
const HZ := 60.0
const TOON := preload("res://shaders/toon_part.gdshader")   # (the old cel look: kept for reference)
const FLAT := preload("res://shaders/flat_part.gdshader")
## The game's look since 2026-11-21: photoreal (physically based parts, no ink outline).
const PBR := preload("res://shaders/pbr_part.gdshader")
const HIDDEN := preload("res://shaders/hidden_part.gdshader")

static var _it: Stage3D
static var _scenes := {}                    # id -> PackedScene
static var _infos := {}                     # id -> model.json
static var _mats := {}                      # id -> [Material per surface]

var viewport: SubViewport
var _cam: Camera3D
var _slots: Array = []                      # per cell: {} (free) or {id, root, model, skeleton, anim, pose}
var _pool := {}                             # id -> [model instances not in use]
var _t := 0.0


static func model_dir(id: String) -> String:
	return "res://art/%s_3d/" % id


static func has_model(id: String) -> bool:
	return _infos.has(id) or (FileAccess.file_exists(model_dir(id) + "model.json") and ResourceLoader.exists(model_dir(id) + id + ".glb"))


## A model's facts (model.json): fps, clips {n, loop, gun, marks, air (m a frame), points (m)}, materials.
static func info(id: String) -> Dictionary:
	if not _infos.has(id):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(model_dir(id) + "model.json"))
		var d: Dictionary = parsed if parsed is Dictionary else {"clips": {}, "materials": {}}
		d["fps"] = float(d.get("fps", 30))
		d["stand_m"] = float(d.get("stand_m", 1.89))
		_infos[id] = d
	return _infos[id]


## The stage (made the first time, under the root: it outlives the scenes).
static func stage(tree: SceneTree) -> Stage3D:
	if _it == null or not is_instance_valid(_it):
		_it = Stage3D.new()
		_it.name = "Stage3D"
		tree.root.add_child.call_deferred(_it)      # (deferred: the root may be busy building a scene)
	return _it


func _init() -> void:
	for i in SLOTS:
		_slots.append({})
	viewport = SubViewport.new()
	viewport.size = Vector2i(CELL.x, CELL.y)      # (as wide as the cells in use: _fit)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)    # (a soft sky fill: the photoreal look's shadows aren't black)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var el := deg_to_rad(ELEVATION)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CELL.y / PX_PER_M
	_cam.near = 0.5
	_cam.far = 60.0
	viewport.add_child(_cam)
	_fit()
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = false
	sun.light_energy = 1.6
	viewport.add_child(sun)
	# (as the kit's key light: from the upper left, a little toward the camera)
	sun.look_at_from_position(Vector3(-3.4, 3.2, 2.4), Vector3.ZERO, Vector3.UP)


## The picture as wide as the cells in use (1 for the automaton alone: a quarter
## of the pixels), the camera over the middle of them, looking down at
## ELEVATION; a cell's ground point (the model's origin) lands on ANCHOR.
func _fit() -> void:
	var n := 1
	for i in SLOTS:
		if not (_slots[i] as Dictionary).is_empty() if i < _slots.size() else false:
			n = i + 1
	if viewport.size.x != CELL.x * n:
		viewport.size = Vector2i(CELL.x * n, CELL.y)
	var el := deg_to_rad(ELEVATION)
	var cell_m := CELL.x / PX_PER_M
	var up_m := (CELL.y * 0.5 - (CELL.y - ANCHOR.y)) / PX_PER_M      # (the origin below the picture's middle: m on screen)
	var look := Vector3(cell_m * (n - 1) * 0.5, up_m / cos(el), 0.0)
	_cam.look_at_from_position(look + Vector3(0.0, sin(el), cos(el)) * 20.0, look, Vector3.UP)


## A model's materials: the kit's, remade (shared by every instance).
static func materials(id: String, mesh: Mesh) -> Array:
	if not _mats.has(id):
		var table: Dictionary = info(id).get("materials", {})
		var out := []
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			var m: Dictionary = table.get(nm, {})
			var sm := ShaderMaterial.new()
			var c: Array = m.get("color", [0.8, 0.8, 0.8])
			var look := surface_look(nm, str(m.get("kind", "toon")))
			if look["hidden"]:
				sm.shader = HIDDEN
			else:
				sm.shader = PBR
				sm.set_shader_parameter("albedo", Color(c[0], c[1], c[2]))
				sm.set_shader_parameter("metallic", look["metal"])
				sm.set_shader_parameter("roughness", look["rough"])
				var k := float(m.get("strength", 1.0)) * float(look["emit"])
				sm.set_shader_parameter("emission", Vector3(_lin(c[0]), _lin(c[1]), _lin(c[2])) * k)
			out.append(sm)
		_mats[id] = out
	return _mats[id]


## How a part's surface takes the light, by its material's name (the kit's
## names: AUT_Armor, PIR_Leather, KIT_Ink...) and kind: {metal, rough, emit, hidden}.
static func surface_look(nm: String, kind: String) -> Dictionary:
	var n := nm.to_lower()
	if kind == "ink" or n.contains("ink"):
		return {"metal": 0.0, "rough": 1.0, "emit": 0.0, "hidden": true}
	if kind == "glow" or n.contains("glow") or n.contains("eye"):
		return {"metal": 0.0, "rough": 0.3, "emit": 3.0, "hidden": false}
	for k in ["gold", "bronze", "gun"]:
		if n.contains(k):
			return {"metal": 0.9, "rough": 0.28, "emit": 0.0, "hidden": false}
	if n.contains("armor") or n.contains("armour"):
		return {"metal": 0.55, "rough": 0.32, "emit": 0.0, "hidden": false}   # (painted metal plates)
	if n.contains("grey") or n.contains("red"):
		return {"metal": 0.45, "rough": 0.38, "emit": 0.0, "hidden": false}
	if n.contains("joint") or n.contains("cable"):
		return {"metal": 0.2, "rough": 0.6, "emit": 0.0, "hidden": false}     # (rubber, braided cable)
	if n.contains("leather") or n.contains("coat") or n.contains("hat"):
		return {"metal": 0.0, "rough": 0.75, "emit": 0.0, "hidden": false}    # (leather, cloth)
	return {"metal": 0.4, "rough": 0.45, "emit": 0.0, "hidden": false}


static func _lin(x: float) -> float:
	return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)


static func _scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		_scenes[id] = load(model_dir(id) + id + ".glb")
	return _scenes[id]


## A model made ready: its materials, its animations set for being posed by hand
## (looping clips a whole cycle long, wrapping round).
func _make(id: String) -> Dictionary:
	var model: Node3D = _scene(id).instantiate()
	var mesh: MeshInstance3D = model.find_child("Body", true, false)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var mats := materials(id, mesh.mesh)
	for i in mats.size():
		mesh.set_surface_override_material(i, mats[i])
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 4.0           # (posed far from its rest box: a leap, a fall)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var d: Dictionary = info(id)
	var fps: float = d["fps"]
	for name in d["clips"]:
		if anim.has_animation(name):
			var a := anim.get_animation(name)
			var n := int(d["clips"][name]["n"])
			if bool(d["clips"][name].get("loop", false)):
				a.loop_mode = Animation.LOOP_LINEAR
				a.length = n / fps
			else:
				a.loop_mode = Animation.LOOP_NONE
				a.length = maxf(a.length, (n - 1) / fps)
	return {"id": id, "model": model, "skeleton": sk, "anim": anim, "gun": sk.find_bone("gun")}


## A cell for a character: {slot, model, skeleton, anim, gun} - {} when the
## stage is full. `pose` (dt) is called before each redraw.
func claim(id: String, pose: Callable) -> Dictionary:
	var slot := -1
	for i in SLOTS:
		if (_slots[i] as Dictionary).is_empty():
			slot = i
			break
	if slot < 0:
		return {}
	var c: Dictionary
	var free: Array = _pool.get(id, [])
	if not free.is_empty():
		c = free.pop_back()
	else:
		c = _make(id)
	c["slot"] = slot
	c["pose"] = pose
	var model: Node3D = c["model"]
	model.position = Vector3(slot * CELL.x / PX_PER_M, 0.0, 0.0)
	if model.get_parent() == null:
		viewport.add_child(model)
	model.visible = true
	_slots[slot] = c
	_fit()
	_t = 1.0                                # (drawn at once)
	return c


func release(slot: int) -> void:
	if slot < 0 or slot >= SLOTS or (_slots[slot] as Dictionary).is_empty():
		return
	var c: Dictionary = _slots[slot]
	_slots[slot] = {}
	c["pose"] = Callable()
	(c["model"] as Node3D).visible = false
	if not _pool.has(c["id"]):
		_pool[c["id"]] = []
	_pool[c["id"]].append(c)
	_fit()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE   # (its picture cleared)


func in_use() -> int:
	return _slots.filter(func(s): return not (s as Dictionary).is_empty()).size()


## A cell of the stage's picture.
func region(slot: int) -> Rect2:
	return Rect2(slot * CELL.x, 0, CELL.x, CELL.y)


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0 / HZ:
		return
	var dt := minf(_t, 0.1)
	_t = 0.0
	var any := false
	for c in _slots:
		var pose: Callable = (c as Dictionary).get("pose", Callable())
		if pose.is_valid():
			pose.call(dt)
			any = true
	if any:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Every 3D character's model loaded, made and drawn once, unseen - on the
## loading screen, never in play (awaitable).
static func warm(tree: SceneTree) -> void:
	for dir in DirAccess.get_directories_at("res://art"):
		if not dir.ends_with("_3d"):
			continue
		var id := dir.trim_suffix("_3d")
		if not has_model(id) or _scenes.has(id):
			continue
		var path := model_dir(id) + id + ".glb"
		if DisplayServer.get_name() == "headless":
			_scenes[id] = load(path)
		else:
			ResourceLoader.load_threaded_request(path)
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await tree.process_frame
			_scenes[id] = ResourceLoader.load_threaded_get(path)
		info(id)
		await tree.process_frame
		var st := stage(tree)
		while not st.is_inside_tree():
			await tree.process_frame
		var c := st.claim(id, func(_dt): pass)       # (made, and its shaders compiled as it's drawn)
		if c.is_empty():
			continue
		for i in 4:
			st.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await tree.process_frame
		st.release(int(c["slot"]))
