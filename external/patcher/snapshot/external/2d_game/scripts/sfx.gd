extends Node
## Autoload "Sfx": sound effects. Sounds live in res://sounds/<group>/ as
## takes <name>_1.ogg, <name>_2.ogg ... (tools/sfx_pirate.py makes the
## pirate's); a sound is called by "<group>/<name>" and each time one of its
## takes plays, at a slightly random pitch, so repeats don't sound the same.
##
##   Sfx.play_at("pirate/shot", where, parent)   # in the world: fades with distance from the camera
##   Sfx.play("pirate/loot_take")                # flat (for you: picking things up, the UI)
##   Sfx.play_world("space/boom_big", global_pos) # at a global point, in the FX layer / scene
##   var hum := Sfx.loop_at("space/station_hum", station)   # a looping sound on a node (yours to stop)
##
## Everything goes through the "SFX" bus, whose volume is Settings.sfx_volume.
## A sound can't stack up endlessly: at most MAX_EACH of one sound play at
## once (a band of pirates firing), MAX_ALL in all.

const DIR := "res://sounds/"
const BUS := "SFX"
const MAX_EACH := 6
const MAX_ALL := 40
const MAX_TAKES := 12
## How far a sound in the world carries (px), and how fast it fades.
const RANGE := 1500.0
const FALLOFF := 1.6

var _takes := {}                    # "group/name" -> [AudioStream, ...]
var _playing := {}                  # "group/name" -> [players]
var _count := 0


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	apply_volume()
	set_process(false)


var _warm_queue: Array = []         # sounds still to load ahead (warm)


## Loads every sound in `folder` ("space") ahead - one a frame, in the
## background: the first explosion of a fight doesn't also read its sound
## from disk (a few ms in that frame).
## (once a run per folder: listing it was ~5 ms of each space scene's first
## frame; every take requested from a background loader - _process collects
## them as they're done, takes() takes one ready-made)
static var _listed := {}
func warm(folder: String) -> void:
	if _listed.has(folder):
		return
	_listed[folder] = true
	for f in ResourceLoader.list_directory(DIR + folder):
		if f.get_extension() != "ogg":
			continue
		var key := folder + "/" + f.get_basename().rsplit("_", true, 1)[0]
		if not _takes.has(key) and not _warm_queue.has(key):
			_warm_queue.append(key)
			_request_queue.append(key)
	set_process(not _warm_queue.is_empty())


var _request_queue: Array = []   # keys whose takes are still to be asked for (a few a frame)

func _process(_delta: float) -> void:
	for i in 3:
		if _request_queue.is_empty():
			break
		var rk: String = _request_queue.pop_front()
		for k in range(1, MAX_TAKES + 1):
			var path := "%s%s_%d.ogg" % [DIR, rk, k]
			if not ResourceLoader.exists(path):
				break
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(path)
	if _warm_queue.is_empty():
		set_process(false)
		return
	var key: String = _warm_queue[0]
	if _takes.has(key):
		_warm_queue.pop_front()
		return
	var path := "%s%s_1.ogg" % [DIR, key]
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return   # (still loading: next frame)
	takes(_warm_queue.pop_front())


## The SFX bus at Settings.sfx_volume (0 = silent, 1 = full).
func apply_volume() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	var v: float = Settings.sfx_volume
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


## Every take of a sound (loaded once).
func takes(key: String) -> Array:
	if not _takes.has(key):
		var found := []
		for k in range(1, MAX_TAKES + 1):
			var path := "%s%s_%d.ogg" % [DIR, key, k]
			if not ResourceLoader.exists(path):
				break
			var bg := ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
			found.append(ResourceLoader.load_threaded_get(path) if bg else load(path))
		_takes[key] = found
	return _takes[key]


func _free_slot(key: String) -> bool:
	var live: Array = _playing.get(key, []).filter(func(p): return is_instance_valid(p))
	_playing[key] = live
	return live.size() < MAX_EACH and _count < MAX_ALL


func _track(key: String, p: Node) -> void:
	_playing[key].append(p)
	_count += 1
	p.tree_exited.connect(func(): _count -= 1)


## Plays a sound in the world at `at` (in `parent`'s coordinates): it fades
## with distance from the camera. volume_db shifts it (quieter footsteps);
## pitch: how much the pitch may wander (0.06 = +-6 %). Null if it didn't play.
func play_at(key: String, at: Vector2, parent: Node, volume_db := 0.0, pitch := 0.06) -> AudioStreamPlayer2D:
	var list := takes(key)
	if list.is_empty() or parent == null or not parent.is_inside_tree() or not _free_slot(key):
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = list.pick_random()
	p.position = at
	p.bus = BUS
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch, pitch)
	p.max_distance = RANGE
	p.attenuation = FALLOFF
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	_track(key, p)
	p.play()
	return p


## Plays a sound at a global position: in the FX layer (group "fx_layer") or
## else the current scene.
func play_world(key: String, global_at: Vector2, volume_db := 0.0, pitch := 0.06) -> AudioStreamPlayer2D:
	var tree := get_tree()
	var layer: Node = tree.get_first_node_in_group("fx_layer")
	if layer == null:
		layer = tree.current_scene
	if not layer is Node2D:
		return null
	return play_at(key, (layer as Node2D).to_local(global_at), layer, volume_db, pitch)


## A looping sound on `node` (its first take, looping), playing: it moves with
## the node and goes when it does. Not counted against the caps; the caller
## turns it up / down / stops it. Null if the sound doesn't exist.
func loop_at(key: String, node: Node, volume_db := 0.0, max_distance := RANGE) -> AudioStreamPlayer2D:
	var list := takes(key)
	if list.is_empty() or node == null:
		return null
	var st: AudioStream = list[0]
	if st is AudioStreamOggVorbis:
		st.loop = true
	var p := AudioStreamPlayer2D.new()
	p.stream = st
	p.bus = BUS
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.attenuation = FALLOFF
	node.add_child(p)
	if p.is_inside_tree():
		p.play()
	else:
		p.ready.connect(p.play)
	return p


## Plays a sound flat - not in the world (yours: loot you pick up, the UI).
func play(key: String, volume_db := 0.0, pitch := 0.04) -> AudioStreamPlayer:
	var list := takes(key)
	if list.is_empty() or not _free_slot(key):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = list.pick_random()
	p.bus = BUS
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch, pitch)
	p.finished.connect(p.queue_free)
	add_child(p)
	_track(key, p)
	p.play()
	return p
