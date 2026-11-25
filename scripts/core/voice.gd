extends Node
## Autoload "Voice": spoken dialogue. Every story line is recorded with
## Piper (neural text to speech, offline) by tools/voice_lines.py, one voice
## per character, as res://voices/lines/<key>.ogg - key: the first 16 hex
## digits of sha1("<speaker>|<the line without BBCode>"). Saying a line plays
## its own recording:
##
##   Voice.speak("Then the thread is in your hands.", "Kilon Alios")
##   Voice.stop()
##
## A line with no recording (edited since, or never recorded) is silent - run
## tools/voice_lines.py again (test_audio checks every quest line has one).
## The dialogue box speaks each line as it shows it. Plays on the "Voice"
## bus (Settings.voice_volume), also while the game is paused.

const DIR := "res://voices/lines/"
const BUS := "Voice"

var _player: AudioStreamPlayer
var speaking := ""                  # the key of the line being spoken ("" none)
static var _bb := RegEx.create_from_string("\\[[^\\]]*\\]")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.finished.connect(func(): speaking = "")
	add_child(_player)
	apply_volume()


## The Voice bus at Settings.voice_volume (0 = silent).
func apply_volume() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	var v: float = Settings.voice_volume
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


## The recording's key for a line (as tools/voice_lines.py names it).
static func key(text: String, speaker: String) -> String:
	var plain := _bb.sub(text, "", true).strip_edges()
	return ("%s|%s" % [speaker, plain]).sha1_text().substr(0, 16)


## The recording of a line (null if it has none).
static func recording(text: String, speaker: String) -> AudioStream:
	var path := DIR + key(text, speaker) + ".ogg"
	return load(path) if ResourceLoader.exists(path) else null


## Speaks a line (stopping whatever was being said); silent if it has no recording.
func speak(text: String, speaker: String) -> void:
	stop()
	var st := recording(text, speaker)
	if st == null:
		return
	speaking = key(text, speaker)
	_player.stream = st
	_player.play()


func stop() -> void:
	if _player and _player.playing:
		_player.stop()
	speaking = ""
