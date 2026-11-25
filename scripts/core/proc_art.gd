extends Node
## Autoload "ProcArt": the game's sprite textures. All art is raster: PNGs
## cut out of the reference sheets in external/images/ by tools/extract_sprites.py
## (data/sprites/<key>.png). Godot imports them; at start-up they're loaded on
## background threads while the loading screen shows its progress, then the
## Minoan building textures are assembled from the tile pieces.
##
## Keys: "ship_<class id>", "ship_player", "station_<design>", "npc_...",
## "tile_...", "fx_...".

signal baked
## Emitted when art was reloaded.
signal art_changed
signal progress_changed(value: float, label: String)

const SPRITES := "res://data/sprites/"

var progress := 0.0
var stage := ""
var ready_done := false
## The main scenes the loading screen loaded, kept loaded for the whole game
## (else they're dropped with the loading screen, and the first landing loads
## the planet surface's scene again: a 0.4 s freeze as you click Land).
var scenes := {}
var scenes_done := true   # (false only while load_scenes is at work)

## The game's scenes still to load after the title screen opened (load_scenes):
## one after another in the background (parallel loads of scenes sharing
## dependencies can race).
var _scene_queue: Array = []


## The title screen opens as soon as its own scene is in (the loading screen);
## the sprites (_load_all, already going) and these scenes come in behind it.
func load_scenes(paths: Array) -> void:
	_scene_queue = paths.filter(func(p): return not scenes.has(p))
	scenes_done = _scene_queue.is_empty()
	while not _scene_queue.is_empty():
		var p: String = _scene_queue[0]
		ResourceLoader.load_threaded_request(p, "", false)
		while true:
			var st := ResourceLoader.load_threaded_get_status(p)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				scenes[p] = ResourceLoader.load_threaded_get(p)
				break
			if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("Background load failed, loading normally: " + p)
				scenes[p] = load(p)
				break
			await get_tree().process_frame
		_scene_queue.pop_front()
	scenes_done = true


## Everything the game needs in (the sprites and the scenes): starting a game,
## attract mode and Talos wait for it.
func all_ready() -> bool:
	return ready_done and scenes_done


## Waits until all_ready(); `on_progress` (0..1, stage text) is called each frame meanwhile.
func wait_ready(on_progress := Callable()) -> void:
	while not all_ready():
		if on_progress.is_valid():
			on_progress.call(overall(), stage if not ready_done else "Loading scenes")
		await get_tree().process_frame


## How far the background loading is (0..1): the sprites most of it.
func overall() -> float:
	var art := 1.0 if ready_done else progress
	return art * 0.9 + (1.0 if scenes_done else 0.0) * 0.1
var _tex := {}
var _images := {}
var _loading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # (loading on while the game's paused: menus, the veil)
	EditorIcons.warm()   # (every GUI icon painted ahead, on worker threads)
	_load_all()


## Quitting: the memory pool emptied while what it points at still exists
## (its entries - static, holding calls bound to this - outlived it at exit:
## the game crashed as it closed, a double free).
func _exit_tree() -> void:
	AssetPool.reset()
	# (the builds kept for the whole run - the empires' ship designs, your hull and its rooms, the noise,
	# the planets' maps - collected: a task left in the pool at exit was freed after its script went,
	# and the game crashed as it closed)
	EmpireHulls.finish()
	CosmosShip.finish_tasks()
	CosmosShipInterior.finish_tasks()
	Cosmos.finish_tasks()
	PlanetMapPage.finish_tasks()


## Every sprite loaded at start-up: [key, path, label].
func bake_jobs() -> Array:
	var out := []
	# (ResourceLoader's listing: in an exported game the folder holds the
	# imported pictures, not the PNGs - DirAccess found next to none there)
	for f in ResourceLoader.list_directory(SPRITES):
		if f.ends_with(".png"):
			var key := f.get_basename()
			out.append([key, SPRITES + f, _label(key)])
	return out


static func _label(key: String) -> String:
	if key.begins_with("ship_"):
		return "Ships: " + key.trim_prefix("ship_").trim_prefix("traced_").replace("_", " ").capitalize()
	if key.begins_with("station_"):
		return "Stations: " + key.trim_prefix("station_").replace("_", " ").capitalize()
	if key.begins_with("monster_"):
		return "Creatures: " + key.trim_prefix("monster_").replace("_", " ")
	if key.begins_with("npc_"):
		return "Citizens: " + key.trim_prefix("npc_minoan_").replace("_", " ")
	return "Buildings: " + key.trim_prefix("tile_").replace("_", " ")


## Sprites being loaded at once (IN_FLIGHT), and the main thread's time a frame for taking
## them in (making each one's texture): loading all 1000+ at once froze a
## browser tab for seconds at a time.
var IN_FLIGHT := 3 if OS.has_feature("web") else 8   # (a browser froze with more at once; a desktop takes them in its stride)
const TAKE_BUDGET_US := 3000

var _queue: Array = []       # keys still to load, in order
var _urgent: Array = []      # keys asked for (get_tex) before they're in: first
var _flight := {}            # key -> path, loading now
var _ph := {}                # key -> the placeholder handed out for it (ImageTexture), real picture to come
var _sizes := {}             # key -> Vector2i (data/sprites/sizes.json: tools/sprite_sizes.py)
var _meta := {}              # key -> sizes.json's row (size, colours, opaque box: PlaceholderArt)
## Every placeholder drawn (the real pictures load only after: _load_all).
var placeholders_done := false


var _labels := {}
var _total := 1.0


## Every frame (for the whole game - pictures asked for later come in too):
## a few sprites loading at once, the asked-for ones first; the ones done taken
## in within the time budget.
## In a browser: loaded on the main thread, a few a frame within this budget
## (the threaded loader there handed each texture back to the main thread in
## stalls of 1-2 s, and took the worker threads a planet's making needs).
const WEB_BUDGET_US := 8000
const WEB_GAME_BUDGET_US := 1500   # (in the 3D game: the pictures asked for)
var _web := OS.has_feature("web")


## What was built from placeholder images (the ground's pieces and atlases, the
## buildings' walls, floors and roofs) made again from the real pictures as
## they come in: checked a few times a second while pictures arrive.
const REFRESH_EVERY := 0.3
var _refresh_at := 0.0
var _refreshed_serial := 0

func _refresh_built() -> void:
	_refreshed_serial = real_serial
	pass


func _process(_delta: float) -> void:
	if real_serial != _refreshed_serial and Time.get_ticks_msec() / 1000.0 >= _refresh_at:
		_refresh_at = Time.get_ticks_msec() / 1000.0 + REFRESH_EVERY
		_refresh_built()
	if not placeholders_done or (_queue.is_empty() and _urgent.is_empty() and _flight.is_empty()):
		return   # (the placeholders all first)
	if _web:
		var t0 := Time.get_ticks_usec()
		# (In the 3D game only the pictures asked for (urgent) - their placeholders shown a frame or
		# two meanwhile; the rest wait for the title: there each load is the main thread's
		# (decoded here), and 8 ms of them a frame held the game at ~40 FPS for ~20 s.)
		var cs := get_tree().current_scene
		var in_game := cs != null and cs.has_method("build_settled")
		if in_game and _urgent.is_empty():
			return
		var budget := WEB_GAME_BUDGET_US if in_game else WEB_BUDGET_US
		while (not _urgent.is_empty() or (not _queue.is_empty() and not in_game)) and Time.get_ticks_usec() - t0 < budget:
			var key: String = _urgent.pop_front() if not _urgent.is_empty() else _queue.pop_front()
			if _tex.has(key) and not _ph.has(key):
				continue
			_queue.erase(key)
			_take(key, load(path_of(key)))
			stage = _labels.get(key, key)
		if _loading:
			var left := _queue.size() + _urgent.size()
			progress = 0.9 * (_total - left) / _total
			progress_changed.emit(progress, stage)
		return
	while _flight.size() < IN_FLIGHT and (not _urgent.is_empty() or not _queue.is_empty()):
		var key: String = _urgent.pop_front() if not _urgent.is_empty() else _queue.pop_front()
		if _flight.has(key) or (_tex.has(key) and not _ph.has(key)):
			continue
		_queue.erase(key)
		_flight[key] = path_of(key)
		ResourceLoader.load_threaded_request(_flight[key], "Texture2D", false)
	var t0 := Time.get_ticks_usec()
	for key in _flight.keys():
		if Time.get_ticks_usec() - t0 > TAKE_BUDGET_US:
			break
		var st := ResourceLoader.load_threaded_get_status(_flight[key])
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_take(key, ResourceLoader.load_threaded_get(_flight[key]))
			_flight.erase(key)
			stage = _labels.get(key, key)
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("Sprite failed to load: " + str(_flight[key]))
			_flight.erase(key)
	if _loading:
		var left := _queue.size() + _urgent.size() + _flight.size()
		progress = 0.9 * (_total - left) / _total
		progress_changed.emit(progress, stage)


func _load_all() -> void:
	_loading = true
	var f := FileAccess.get_file_as_string(SPRITES + "sizes.json")
	var d = JSON.parse_string(f) if f != "" else null
	var need := 0
	if d is Dictionary:
		for k in d:
			_sizes[k] = Vector2i(int(d[k][0]), int(d[k][1]))
			_meta[k] = d[k]
			need += _sizes[k].x * _sizes[k].y * 4
	# The memory pool's room: twice what's usually loaded (every sprite).
	AssetPool.set_need(need)
	var jobs := bake_jobs()
	var labels := {}
	for j in jobs:
		labels[j[0]] = j[2]
		if not _tex.has(j[0]) or _ph.has(j[0]):
			_queue.append(j[0])
	_labels = labels
	_total = maxf(1.0, jobs.size())
	# First every sprite's procedural placeholder (PlaceholderArt: a simple shape
	# in its colours - microseconds each, a few ms a frame), all of them; only
	# then the real pictures, each replacing its placeholder in place.
	if DisplayServer.get_name() != "headless":
		var t0 := Time.get_ticks_msec()
		var slice := Time.get_ticks_usec()
		var made := 0
		for j in jobs:
			if not _tex.has(j[0]) and _meta.has(j[0]):
				_placeholder(j[0])
				made += 1
			if Time.get_ticks_usec() - slice > PH_BUDGET_US:
				stage = "procedural placeholders: " + str(j[2])
				progress_changed.emit(progress, stage)
				await get_tree().process_frame
				slice = Time.get_ticks_usec()
		AssetPool.add("placeholders", made * PlaceholderArt.RES * PlaceholderArt.RES * 4, Callable(), Callable(), true,
			"Procedural placeholders (%d)" % made)
		AssetPool.note("%d procedural placeholders drawn in %d ms - now the real pictures" % [made, Time.get_ticks_msec() - t0])
	placeholders_done = true
	set_process(true)
	while not _queue.is_empty() or not _urgent.is_empty() or not _flight.is_empty():
		await get_tree().process_frame
	stage = "Characters: 3D models"
	progress_changed.emit(progress, stage)
	await Stage3D.warm(get_tree())           # (loaded, made, their shaders compiled - unseen)
	progress = 1.0
	stage = "Ready"
	_loading = false
	ready_done = true
	baked.emit()


## A sprite's texture - always the real picture (one not in yet is loaded now,
## and fills in a placeholder handed out for it): for anything that reads its
## pixels or bakes it into something (atlases, tile caches). Drawing it as it
## is: sprite().
func get_tex(key: String) -> Texture2D:
	if _tex.has(key) and not _ph.has(key):
		AssetPool.touch(key)
		return _tex[key]
	var p := path_of(key)
	if p == "" or not ResourceLoader.exists(p):
		return null
	var real: Texture2D = load(p)
	_take(key, real)
	return _tex.get(key)


## Sprites whose keys start with any of `prefixes` loaded next (a planet
## about to be landed on: its tiles and creatures).
func prefetch(prefixes: Array) -> void:
	# (in the order of `prefixes`: the first ones first)
	for p in prefixes:
		var first: Array = []
		for k in _queue:
			if str(k).begins_with(p):
				first.append(k)
		for k in first:
			_queue.erase(k)
			if not k in _urgent:
				_urgent.append(k)
		if not _loading:   # (the pool unloaded some: back they come)
			for k in _labels:
				if str(k).begins_with(p) and not _tex.has(k) and not k in _urgent and not _flight.has(k):
					_urgent.append(k)


## Waits (frames go on) until every sprite whose key starts with one of
## `prefixes` is in - loaded first (prefetch): for what must have the real
## pictures (a planet's surface baking its tiles) without loading them on the
## spot (a browser froze seconds for a dozen).
func ensure(prefixes: Array) -> void:
	prefetch(prefixes)
	while true:
		var pending := false
		for k in _urgent + _flight.keys() + _ph.keys():
			for p in prefixes:
				if str(k).begins_with(p):
					pending = true
					break
			if pending:
				break
		if not pending:
			return
		await get_tree().process_frame


## Any sprite starting with one of `prefixes` still to load (not waiting for it).
func pending(prefixes: Array) -> bool:
	if _queue.is_empty() and _urgent.is_empty() and _flight.is_empty():
		return false
	for k in _queue + _urgent + _flight.keys():
		for p in prefixes:
			if str(k).begins_with(p):
				return true
	return false


## How many sprites are in, of how many (the loading bar).
func counts() -> Vector2i:
	return Vector2i(int(_total) - (_queue.size() + _urgent.size() + _flight.size()), int(_total))


## A sprite to draw. One not loaded yet comes as a placeholder of its size
## (a soft, faint shape) and is loaded next; its picture replaces the
## placeholder in place when it's in (the same texture: whatever holds it shows
## the real thing from then on) - the game never waits for a picture.
func sprite(key: String) -> Texture2D:
	if _tex.has(key):
		if _ph.has(key):
			if not key in _urgent and not _flight.has(key):
				_urgent.append(key)
		else:
			AssetPool.touch(key)
		return _tex[key]
	if DisplayServer.get_name() == "headless" or not _meta.has(key) or not ResourceLoader.exists(path_of(key)):
		return get_tex(key)
	var ph := _placeholder(key)
	_urgent.append(key)
	return ph


## A sprite's procedural placeholder (PlaceholderArt), standing in for it at its size.
const PH_BUDGET_US := 4000
func _placeholder(key: String) -> ImageTexture:
	var ph := ImageTexture.create_from_image(PlaceholderArt.make(key, _meta[key]))
	ph.set_size_override(_sizes[key])
	_ph[key] = ph
	_tex[key] = ph
	return ph


## Is its real picture in (not a placeholder)?
func is_in(key: String) -> bool:
	return _tex.has(key) and not _ph.has(key)


## Counts the real pictures arriving: whatever was built from placeholder
## images (the ground's tiles, the buildings' walls and floors) is redone when
## this moves on and its pictures are in (TerrainTiles / MinoanTiles.refresh).
var real_serial := 0
var _ph_img := {}            # key -> its placeholder Image at the picture's full size


## A sprite as an Image, never waited for: the real one if it's in, else a
## procedural placeholder at the picture's exact size (PlaceholderArt - the
## same layout once the real one replaces it), the real one asked for first.
## Headless (tests, tools): always the real one. -> [Image, is_placeholder].
func image_now(key: String) -> Array:
	if is_in(key) or DisplayServer.get_name() == "headless" or not _meta.has(key):
		return [get_image(key), false]
	if not _ph_img.has(key):
		var img := PlaceholderArt.make(key, _meta[key])
		var size: Vector2i = _sizes[key]
		img.resize(maxi(1, size.x), maxi(1, size.y), Image.INTERPOLATE_NEAREST)
		_ph_img[key] = img
	if not key in _urgent and not _flight.has(key):
		_urgent.append(key)
	return [_ph_img[key], true]


## The real picture in: a placeholder handed out for it takes it on (its RID stays).
func _take(key: String, tex: Texture2D) -> void:
	if tex == null:
		return
	real_serial += 1
	_ph_img.erase(key)
	if _ph.has(key):
		var img := tex.get_image()
		if img:
			(_ph[key] as ImageTexture).set_image(img)
		_ph.erase(key)
	else:
		_tex[key] = tex
	AssetPool.add(key, tex.get_width() * tex.get_height() * 4, _unload.bind(key), _held.bind(key), false, _labels.get(key, key))


## The pool unloads it (it ran out of room): asked for again, it comes back
## (a placeholder meanwhile).
func _unload(key: String) -> void:
	_tex.erase(key)


## Something besides ProcArt holds it (a sprite on screen, an atlas): it stays.
func _held(key: String) -> bool:
	var t: RefCounted = _tex.get(key)
	return t != null and t.get_reference_count() > 2   # (the dictionary's and this one's)


## The PNG behind a key.
func path_of(key: String) -> String:
	return SPRITES + key + ".png"


func has_sprite(key: String) -> bool:
	return ResourceLoader.exists(path_of(key))


## A sprite as an Image (for building textures from tile pieces).
func get_image(key: String) -> Image:
	if not _images.has(key):
		var t: Texture2D = get_tex(key)
		# Headless (tests, tools) has no GPU copy to read back: use the PNG.
		var img: Image = t.get_image() if t and DisplayServer.get_name() != "headless" else null
		if img == null and has_sprite(key):
			# No GPU copy to read back (headless runs): the PNG itself.
			img = Image.load_from_file(ProjectSettings.globalize_path(path_of(key)))
		if img:
			img.decompress()
			AssetPool.add("image:" + key, img.get_data_size(), func(): _images.erase(key), _image_held.bind(key), false, "Picture data: " + key)
		_images[key] = img
	AssetPool.touch("image:" + key)
	return _images[key]


func _image_held(key: String) -> bool:
	var i: RefCounted = _images.get(key)
	return i != null and i.get_reference_count() > 2


## A ship class's sprite (bosses fly a traced hull).
func ship_texture(id: String) -> Texture2D:
	var t := EnemyTypes.get_type(id)
	if t.has("art") and EnemyTypes.has_type(id):
		return sprite("ship_" + str(t["art"]))
	return sprite("ship_" + id)


func station_texture(design: String) -> Texture2D:
	return sprite("station_" + design)


## Pixel position of a sprite's anchor (its centre).
func origin(key: String) -> Vector2:
	var t := get_tex(key)
	return t.get_size() / 2.0 if t else Vector2.ZERO


## Re-reads every sprite (after tools/extract_sprites.py ran).
func rebake() -> void:
	if _loading:
		return
	for k in _tex:
		AssetPool.forget(k)
	for k in _images:
		AssetPool.forget("image:" + k)
	_tex.clear()
	_images.clear()
	ready_done = false
	await _load_all()
	art_changed.emit()
