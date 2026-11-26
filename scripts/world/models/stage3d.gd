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
## A model's looping clips set to loop (model.json's "loop"), each a whole cycle long
## (n / fps: its last frame blending back into its first - the imported clips end ON
## their last frame, and the loop jumped from it to the first: up to 20 degrees a step
## in the run); and `extra` clips looping too.
static func loop_clips(anim: AnimationPlayer, id: String, extra: Array = []) -> void:
	if anim == null:
		return
	smooth_clips(anim, id)
	var d := info(id)
	var clips: Dictionary = d.get("clips", {})
	var own := custom_clips(id)            # (clips from files keep their own loop and length)
	for name in clips:
		if anim.has_animation(name) and not own.has(name) and bool(clips[name].get("loop", false)):
			var a := anim.get_animation(name)
			a.loop_mode = Animation.LOOP_LINEAR
			a.length = float(clips[name]["n"]) / float(d["fps"])
	for c in extra:
		if anim.has_animation(c) and not own.has(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR


## Glitches taken out of a model's clips (once a model - its clips are shared): a
## bone that flips away for one to four frames and straight back (the pose solver
## picking the other solution for an elbow, a shoulder piece - up to 180 degrees in a
## frame and back) has those frames blended across from the frames either side. Real
## fast moves - a punch, a kick, going on the way they went - are left as they are.
## Returns the frames mended.
static var _smoothed := {}


static func smooth_clips(anim: AnimationPlayer, id: String) -> int:
	if anim == null:
		return 0
	var fixed := 0
	if not _smoothed.has(id):
		_smoothed[id] = true
		var clips: Dictionary = info(id).get("clips", {})
		var own := custom_clips(id)
		for name in anim.get_animation_list():
			var a := anim.get_animation(name)
			if own.has(name):
				continue   # (a clip from a file: as its maker keyed it)
			fixed += smooth_animation(a)
			fixed += ease_steps(a, deg_to_rad(60.0 if bool(clips.get(name, {}).get("loop", false)) else 100.0))
	use_clips(anim, id)
	return fixed


## Clips from files (the animation editor's - Talos > Animation): every
## art/<id>_3d/clips/<name>.tres - the game's, a mod's (mounted over res://), and
## the mod Talos is saving into (EditTarget) - replaces the model's clip of that
## name or adds one, in the model's library (shared by every instance of it: the
## walker, NPCs, the hangar's crews, the ArmsLayer reading draw / holster / aim by
## name). The folder is listed once per id and the clips loaded then (none: an
## empty dictionary, one lookup a model after that). The model's own clips are
## kept aside (_orig), put back when a file's gone (forget_clips).
static var _clip_files := {}               # id -> {name: path}
static var _custom := {}                   # id -> {name: Animation}
static var _orig := {}                     # id -> {name: the model's own Animation, replaced}
static var _libs := {}                     # id -> the AnimationLibrary the clips went into


static func clips_dir(id: String) -> String:
	return model_dir(id) + "clips/"


## The clip files for `id`: {name: path} (listed once; forget_clips lists again).
static func clip_files(id: String) -> Dictionary:
	if not _clip_files.has(id):
		var out := {}
		_list_clips(clips_dir(id), out)
		# (the mod being made in the Mod Editor: not mounted till the game restarts.
		# EditTarget loaded, not named: scripts run with -s compile this before the autoloads exist)
		var target: GDScript = load("res://scripts/editor/edit_target.gd") if ResourceLoader.exists("res://scripts/editor/edit_target.gd") else null
		if target != null and target.is_mod():
			_list_clips(target.root() + clips_dir(id).trim_prefix("res://"), out)
		_clip_files[id] = out
	return _clip_files[id]


static func _list_clips(dir: String, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".remap")   # (an exported game's converted resources)
		if f.ends_with(".tres") or f.ends_with(".res"):
			out[f.get_basename()] = dir + f


## The clips from files for `id`, loaded: {name: Animation}.
static func custom_clips(id: String) -> Dictionary:
	if not _custom.has(id):
		var out := {}
		var files := clip_files(id)
		for name in files:
			var a = ResourceLoader.load(files[name], "Animation", ResourceLoader.CACHE_MODE_IGNORE)
			if a is Animation:
				out[name] = a
		_custom[id] = out
	return _custom[id]


## The clips from files put into `anim`'s library (in place of the model's own).
static func use_clips(anim: AnimationPlayer, id: String) -> void:
	if anim == null:
		return
	var own := custom_clips(id)
	if own.is_empty():
		return
	var lib := anim.get_animation_library(&"")
	if lib == null:
		return
	_libs[id] = lib
	if not _orig.has(id):
		_orig[id] = {}
	for name in own:
		var a: Animation = own[name]
		if lib.has_animation(name):
			var cur := lib.get_animation(name)
			if cur == a:
				continue
			if not _orig[id].has(name):
				_orig[id][name] = cur
			lib.remove_animation(name)
		lib.add_animation(name, a)


## The model's own clip `name` (not a file's), or null.
static func base_clip(anim: AnimationPlayer, id: String, name: String) -> Animation:
	if _orig.get(id, {}).has(name):
		return _orig[id][name]
	if anim != null and anim.has_animation(name) and not custom_clips(id).has(name):
		return anim.get_animation(name)
	return null


## The clip files for `id` read again next time (after the editor saves): the
## model's own clips put back meanwhile, the files' added again by use_clips.
static func forget_clips(id: String) -> void:
	var lib: AnimationLibrary = _libs.get(id)
	if lib != null:
		for name in _custom.get(id, {}):
			if lib.has_animation(name):
				lib.remove_animation(name)
		for name in _orig.get(id, {}):
			lib.add_animation(name, _orig[id][name])
	_orig.erase(id)
	_libs.erase(id)
	_clip_files.erase(id)
	_custom.erase(id)


static func smooth_animation(a: Animation) -> int:
	var fixed := 0
	const JUMP := deg_to_rad(40.0)
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var n := a.track_get_key_count(t)
		var k := 1
		while k < n - 1:
			var q0: Quaternion = a.track_get_key_value(t, k - 1)
			var q1: Quaternion = a.track_get_key_value(t, k)
			if q0.angle_to(q1) < JUMP:
				k += 1
				continue
			# (a jump away: does it come straight back within 4 frames, to near where it left?)
			var back := -1
			for e in range(k + 1, mini(k + 5, n)):
				var qe: Quaternion = a.track_get_key_value(t, e)
				var qp: Quaternion = a.track_get_key_value(t, e - 1)
				if qp.angle_to(qe) >= JUMP and q0.angle_to(qe) < q0.angle_to(q1) * 0.5:
					back = e
					break
			if back < 0:
				k += 1
				continue
			var qb: Quaternion = a.track_get_key_value(t, back)
			for j in range(k, back):
				a.track_set_key_value(t, j, q0.slerp(qb, float(j - k + 1) / float(back - k + 1)))
				fixed += 1
			k = back + 1
	return fixed


## A step far bigger than the motion round it (`over` and 2.5 times the frames' usual
## step there - a pose jumping to the next in one frame: a shoulder piece flipping as
## the dive starts, the leap's arms) spread over the frames either side: those frames
## eased (each drawn toward its neighbours' middle, a few times), the window's ends
## kept. Returns the steps eased.
static func ease_steps(a: Animation, over: float) -> int:
	var eased := 0
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var n := a.track_get_key_count(t)
		if n < 7:
			continue
		var q: Array = []
		for k in n:
			q.append(a.track_get_key_value(t, k))
		var steps: Array = [0.0]
		for k in range(1, n):
			steps.append((q[k - 1] as Quaternion).angle_to(q[k]))
		var touched := false
		for k in range(1, n):
			if float(steps[k]) < over:
				continue
			var around: Array = []
			for j in range(maxi(1, k - 4), mini(n, k + 5)):
				if absi(j - k) > 1:
					around.append(float(steps[j]))
			around.sort()
			var usual: float = around[around.size() / 2] if not around.is_empty() else 0.0
			if float(steps[k]) < 2.5 * maxf(usual, deg_to_rad(4.0)):
				continue
			var lo := maxi(0, k - 3)
			var hi := mini(n - 1, k + 2)
			for it in 6:
				for j in range(lo + 1, hi):
					var mid: Quaternion = (q[j - 1] as Quaternion).slerp(q[j + 1], 0.5)
					q[j] = (q[j] as Quaternion).slerp(mid, 0.7)
			touched = true
			eased += 1
		if touched:
			for k in n:
				a.track_set_key_value(t, k, q[k])
	return eased


static func info(id: String) -> Dictionary:
	if not _infos.has(id):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(preload("res://scripts/world/models/model_override.gd").read(model_dir(id) + id + ".glb", "model.json")))
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
	for k in ["bone", "hide", "wing", "skin", "crest", "cloth"]:
		if n.contains(k):
			return {"metal": 0.0, "rough": 0.7, "emit": 0.0, "hidden": false}   # (bone, hide, cloth: matte)
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
		# (the mesh editor's override of it, if there is one: art/overrides/)
		_scenes[id] = preload("res://scripts/world/models/model_override.gd").scene(model_dir(id) + id + ".glb")
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
	var own := custom_clips(id)
	for name in d["clips"]:
		if anim.has_animation(name) and not own.has(name):
			var a := anim.get_animation(name)
			var n := int(d["clips"][name]["n"])
			if bool(d["clips"][name].get("loop", false)):
				a.loop_mode = Animation.LOOP_LINEAR
				a.length = n / fps
			else:
				a.loop_mode = Animation.LOOP_NONE
				a.length = maxf(a.length, (n - 1) / fps)
	use_clips(anim, id)
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
		var MO := preload("res://scripts/world/models/model_override.gd")
		if MO.has(path):
			# (an override - an ECurve object stored from the mesh editor: read from its own file, and its
			# solids merged for the game, on a worker - a character of ninety solids was a 170 ms frame)
			info(id)
			var got := [null, null]
			var tk := WorkerThreadPool.add_task(func():
				got[0] = MO.build(path)
				got[1] = CosmosModels.premerge(got[0], id), false, "Stage3D: a model's override")
			while not WorkerThreadPool.is_task_completed(tk):
				await tree.process_frame
			WorkerThreadPool.wait_for_task_completion(tk)
			MO.remember(path, got[0])
			if not _scenes.has(id):
				_scenes[id] = got[0]
			CosmosModels.keep(id, got[1])
			continue
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
