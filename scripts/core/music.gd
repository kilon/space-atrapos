extends Node
## Autoload "Music": the background music. Three looping tracks in res://music/
## (made by tools/music_gen.py, each a seamless 2-minute loop):
##   menu     "Atrapos"        - the main menu and Talos (the editor)
##   space    "Deep Drift"     - flying in space
##   surface  "Minoan Shores"  - on a planet's surface (and the Library)
## The track follows the scene by itself (TRACK_FOR: scene file -> track);
## a change crossfades over FADE seconds. play("space") / stop() by hand too.
## It plays on the "Music" bus, whose volume is Settings.music_volume; it keeps
## playing while the game is paused (the menu over the game).

const DIR := "res://music/"
const BUS := "Music"
const FADE := 2.5
const TRACK_FOR := {
	"res://scenes/ui/main_menu.tscn": "menu",
	"res://scenes/editor/editor.tscn": "menu",
	"res://scenario_editor.tscn": "menu",
	"res://scenes/editor/mesh_editor.tscn": "menu",
	"res://scenes/editor/anim_editor.tscn": "menu",
	"res://scenes/editor/mod_editor.tscn": "menu",
	"res://scenes/editor/patcher.tscn": "menu",
	"res://main.tscn": "space",
	"res://scenes/planet_surface.tscn": "surface",
	"res://zoo.tscn": "surface",
}
const TITLES := {"menu": "Atrapos", "space": "Deep Drift", "surface": "Minoan Shores"}

var current := ""                   # the track playing ("" none)
var auto := true                    # follow the scene
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _scene: Node
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Every track loading in the background now: a scene change takes its
	# track ready-made (loading one then was ~7 ms of that frame).
	if DisplayServer.get_name() != "headless":
		for t in TRACK_FOR.values():
			var path := "%s%s.ogg" % [DIR, t]
			if ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(path)
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = -80.0
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)
	apply_volume()


## The Music bus at Settings.music_volume (0 = silent).
func apply_volume() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	var v: float = Settings.music_volume
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


## The track for a scene file ("" if none).
func track_for(scene_path: String) -> String:
	return TRACK_FOR.get(scene_path, "")


func stream(track: String) -> AudioStream:
	var path := "%s%s.ogg" % [DIR, track]
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = (ResourceLoader.load_threaded_get(path) if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE else load(path)) as AudioStream
	if s is AudioStreamOggVorbis:
		s.loop = true
	return s


## Crossfades to `track` (no change if it's already playing).
func play(track: String, fade := FADE) -> void:
	if track == current:
		return
	var s := stream(track) if track != "" else null
	if track != "" and s == null:
		return
	current = track
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if s:
		new.stream = s
		new.volume_db = -60.0
		new.play()
		_tween.tween_property(new, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if old.playing:
		_tween.tween_property(old, "volume_db", -60.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_tween.chain().tween_callback(old.stop)


func stop(fade := FADE) -> void:
	play("", fade)


func _process(_delta: float) -> void:
	if not auto:
		return
	var sc := get_tree().current_scene
	if sc == _scene or sc == null:
		return
	_scene = sc
	var t := track_for(sc.scene_file_path)
	if t != "":
		play(t)
