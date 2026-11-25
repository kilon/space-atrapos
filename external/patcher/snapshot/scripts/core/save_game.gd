extends Node
## Autoload "SaveGame": reads/writes the saves (JSON in user://saves/).
##
## SLOTS save slots (slot_1.json ...); each save keeps, besides the game, a
## `summary` (where you were - the system, and the planet if you were on one -
## your ship and credits) for the save / load slot lists. The old single save
## (user://savegame.json) moves into slot 1.
##
## Loading works by putting the saved data in `pending`, then (re)loading the
## game scene; the game applies `pending` in its _ready(). A save made on a
## planet carries `landed` ({planet, pos}): the space scene, loading it, goes
## straight back down there (main.gd), the pilot where you stood (`resume`).

const DIR := "user://saves/"
const SLOTS := 6
const LEGACY := "user://savegame.json"
const VERSION := 2
## Besides the numbered slots: the quicksave (F5 / F9: Keybinds "quicksave",
## "quickload") and the autosave (every Settings.autosave_minutes - not while
## you're under attack - and, Settings.autosave_events, on docking, arriving
## in a system, landing: autosave(why)). Settings > Game chooses.
const QUICK := 101
const AUTO := 102
## Talos opened from a game (F8, or the Esc menu): the game is saved here - a
## slot of its own, never in the lists - and loaded back when you leave Talos.
const TALOS := 103
## A live restart (LiveLink: a change that can't be hot reloaded): the game
## saved here and loaded back as the game comes up again.
const LIVE := 104
const EDITOR_SCENE := "res://scenes/editor/editor.tscn"
## (the time between periodic autosaves now: Settings.autosave_minutes)
static func autosave_every() -> float:
	return float(Settings.autosave_minutes) * 60.0
const GAME_SCENE := "res://scenes/world/cosmos.tscn"   # (the game: 3D)
var _auto_t := 300.0

## Save data waiting to be applied by the next game scene that loads.
var pending: Dictionary = {}

## While you're on a planet surface: the full space game state (as save data)
## to restore when you take off, and which planet you're on.
var space_state: Dictionary = {}
var landed_planet := ""
## The planet you just took off from (for the take-off animation in space).
var took_off_from := ""
## Where the ship was relative to the planet when it landed.
var orbit_offset := Vector2.ZERO
## True while switching between space and a planet (keeps the event log).
var travelling := false
## Loading a save made on a planet: where the pilot stood ({pos}) - the
## surface puts you there instead of beside your ship.
var resume: Dictionary = {}
## The slot last saved to or loaded from (the slot lists start on it).
var current_slot := 1
## True while Talos was opened from a game: leaving Talos goes back to it.
var talos_return := false


func _ready() -> void:
	_migrate()
	process_mode = Node.PROCESS_MODE_ALWAYS   # (F8 closes Talos over the paused game; autosaves still wait for an unpaused one)
	# Every save's header read ahead, off the main thread (_head).
	var paths := []
	for slot in all_slots():
		if FileAccess.file_exists(slot_path(slot)):
			paths.append([slot_path(slot), FileAccess.get_modified_time(slot_path(slot))])
	_tasks.append(WorkerThreadPool.add_task(func():
		for pm in paths:
			_read_head(pm[0], pm[1])))


## The worker tasks started here (each waited for: done ones as they're seen, all at exit).
var _tasks: Array = []

func _reap(all := false) -> void:
	for t in _tasks.duplicate():
		if all or WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_tasks.erase(t)


func _exit_tree() -> void:
	_reap(true)


func slot_path(slot: int) -> String:
	if slot == QUICK:
		return DIR + "quick.json"
	if slot == AUTO:
		return DIR + "auto.json"
	if slot == TALOS:
		return DIR + "talos_resume.json"
	if slot == LIVE:
		return DIR + "live_restart.json"
	return DIR + "slot_%d.json" % slot


## Every slot, the quicksave and autosave first.
func all_slots() -> Array:
	return [QUICK, AUTO] + range(1, SLOTS + 1)


static func slot_name(slot: int) -> String:
	return {QUICK: "Quicksave", AUTO: "Autosave"}.get(slot, "Slot %d" % slot)


## The old single save becomes slot 1.
func _migrate() -> void:
	if FileAccess.file_exists(LEGACY) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.make_dir_recursive_absolute(DIR)
		DirAccess.rename_absolute(LEGACY, slot_path(1))


func has_save(slot := -1) -> bool:
	if slot > 0:
		return FileAccess.file_exists(slot_path(slot))
	for i in all_slots():
		if FileAccess.file_exists(slot_path(i)):
			return true
	return false


## The slot with the newest save (0: none).
func latest_slot() -> int:
	var best := 0
	var best_t := ""
	for i in all_slots():
		var t := saved_at(i)
		if t != "" and t > best_t:
			best = i
			best_t = t
	return best


func save_game(state: Dictionary, slot := -1) -> bool:
	if slot <= 0:
		slot = current_slot
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"summary": summarize(state),
		"state": state,
	}
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	if slot <= SLOTS:
		current_slot = slot
	return true


## Like save_game, written on a worker thread (an autosave: docking,
## arriving in a system - the JSON of the whole galaxy was ~13 ms of that
## frame). The state is copied first (the game goes on changing it); the file
## is written aside and moved into place whole.
func save_in_background(state: Dictionary, slot: int) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"summary": summarize(state),
		"state": state.duplicate(true),
	}
	var path := slot_path(slot)
	_reap()
	_tasks.append(WorkerThreadPool.add_task(func():
		var f := FileAccess.open(path + ".part", FileAccess.WRITE)
		if f == null:
			return
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		DirAccess.rename_absolute(path + ".part", path)))


## What the slot lists show of a save: {system, planet, ship, credits}.
static func summarize(state: Dictionary) -> Dictionary:
	var pl: Dictionary = state.get("player", {})
	var planet := ""
	if state.has("landed"):
		planet = str(Planets.get_planet(str(state["landed"].get("planet", ""))).get("name", ""))
	var cls := str(pl.get("ship_class", "player"))
	return {"system": str(Galaxy.system(Galaxy.current_system).get("name", "")), "planet": planet,
		"ship": str(Shipyard.stats(cls).get("name", "")), "credits": int(pl.get("credits", 0))}


## The whole save ({version, saved_at, summary, state}) of a slot (-1: the
## newest) or {} if missing / corrupt.
func read_save(slot := -1) -> Dictionary:
	if slot <= 0:
		slot = latest_slot()
	if slot <= 0 or not FileAccess.file_exists(slot_path(slot)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if parsed is Dictionary and parsed.has("state"):
		return parsed
	push_warning("Save file %d is corrupt, ignoring it." % slot)
	return {}


func saved_at(slot := -1) -> String:
	if slot <= 0:
		slot = latest_slot()
	return str(_head(slot).get("saved_at", ""))


## A slot's line for the lists: {saved_at, summary} or {} when empty.
func slot_info(slot: int) -> Dictionary:
	return _head(slot).duplicate()


## A save's header ({saved_at, summary}, {} if none): read once per version of
## the file (its modified time) and kept - the menus ask for every slot's each
## time one is built (a scene change); parsing whole saves then was ~20 ms.
## Read ahead on a worker thread at start-up (_ready).
var _heads := {}            # path -> [modified time, header]
var _heads_lock := Mutex.new()

func _head(slot: int) -> Dictionary:
	var p := slot_path(slot)
	if slot <= 0 or not FileAccess.file_exists(p):
		return {}
	var mt := FileAccess.get_modified_time(p)
	_heads_lock.lock()
	var known: Array = _heads.get(p, [])
	_heads_lock.unlock()
	if not known.is_empty() and int(known[0]) == mt:
		return known[1]
	return _read_head(p, mt)


func _read_head(p: String, mt: int) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	var h := {}
	if parsed is Dictionary and parsed.has("state"):
		h = {"saved_at": parsed.get("saved_at", ""), "summary": parsed.get("summary", {})}
	_heads_lock.lock()
	_heads[p] = [mt, h]
	_heads_lock.unlock()
	return h


func delete_slot(slot: int) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))


## Queue a slot's save (-1: the newest) to be applied when the game scene
## loads. False if there is nothing valid to load.
func queue_load(slot := -1) -> bool:
	if slot <= 0:
		slot = latest_slot()
	var data := read_save(slot)
	if data.is_empty():
		return false
	pending = data["state"]
	if slot <= SLOTS:
		current_slot = slot
	return true


# --- Quicksave, quickload, autosave ---------------------------------------------------------

## The running game, if it can be saved now (`busy_ok`: even paused - docked).
func _game(busy_ok := false) -> Node:
	var tree := get_tree()
	var scene := tree.current_scene if tree else null
	if scene == null or not scene.has_method("get_save_data") or travelling:
		return null
	if scene.has_method("can_save") and not scene.can_save():
		return null
	if scene.has_method("build_settled") and not scene.build_settled():
		return null   # (still being built, a piece a frame: not a game to save yet)
	if tree.paused and not busy_ok:
		return null
	return scene


func quicksave() -> bool:
	var g := _game(true)
	if g == null:
		toast("Can't save now")
		return false
	if save_game(g.get_save_data(), QUICK):
		GameLog.post("Quicksaved (F9 to load it).", "good")
		toast("QUICKSAVED")
		return true
	return false


func quickload() -> bool:
	if not has_save(QUICK):
		toast("No quicksave yet")
		return false
	return load_slot(QUICK)


## Loads a slot's save (-1: the newest) into the game, under the loading
## screen (LoadVeil) until it's ready to play - back down on the planet if
## it was made there. False if there is nothing valid to load.
func load_slot(slot := -1) -> bool:
	if get_tree().root.has_node("LoadVeil"):
		return true   # (already loading)
	if slot <= 0:
		slot = latest_slot()
	if not queue_load(slot):
		return false
	travelling = false
	Cosmos.arrive_from = ""
	LoadVeil.change_to(GAME_SCENE, {QUICK: "Loading quicksave", AUTO: "Loading autosave", TALOS: "Back to the game", LIVE: "Back to the game - updated"}.get(slot, "Loading slot %d" % slot),
		func(_progress):
			CosmosGame.begin_state(pending)
			pending = {}, "Loading your save")
	return true


## Opens Talos over the running game (F8, or the Esc menu): the game stays
## as it is underneath - paused, nothing unloaded - and leaving Talos (Back,
## Esc, F8) puts you straight back in it (close_talos). Talos draws above
## the game: it and every layer it makes are lifted by TALOS_LAYER. False
## (and a word on screen) when there's no game to open it over just now.
const TALOS_LAYER := 400
var _talos_state := {}
## The frame Talos over the game closed (the Esc menu under it skips the key
## that closed it - else that same Esc would close the menu too).
var talos_closed_frame := -1

func open_talos() -> bool:
	if talos_overlay() != null:
		return true
	var g := _game(true)
	if g == null:
		toast("Can't open Talos now")
		return false
	var tree := get_tree()
	_talos_state = {"paused": tree.paused, "galaxy": Galaxy.active, "empire": NeonTheme.empire,
		"camera": get_viewport().get_camera_2d()}
	var layer := CanvasLayer.new()
	layer.name = "TalosOverlay"
	layer.layer = TALOS_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS   # (Talos runs; the game under it is paused)
	if not tree.node_added.is_connected(_lift_layer):
		tree.node_added.connect(_lift_layer)
	tree.paused = true
	talos_return = true
	var host: Node = TalosNav.scene(EDITOR_SCENE).instantiate()   # (loaded in the background since the game began: TalosNav._warm)
	host.set("overlay", true)
	layer.add_child(host)
	tree.root.add_child(layer)
	return true


## Talos's own layers (its backdrops at -1 / -2, the Library's interface,
## the guide...) lifted above the game's, in the same order.
func _lift_layer(n: Node) -> void:
	var o := talos_overlay()
	if o != null and n is CanvasLayer and n != o and o.is_ancestor_of(n) and not n.has_meta("talos_lifted"):
		n.set_meta("talos_lifted", true)
		# (after its _ready: some set their layer there - the pinned tooltips)
		(func(): if is_instance_valid(n): n.layer += TALOS_LAYER).call_deferred()


## The open Talos (over the game), or null.
func talos_overlay() -> CanvasLayer:
	return get_tree().root.get_node_or_null("TalosOverlay") as CanvasLayer


## Closes Talos opened over the game: the game as it was - its camera, its
## look, the galaxy running, paused only if it was. False if none is open.
func close_talos() -> bool:
	var o := talos_overlay()
	if o == null:
		return false
	var tree := get_tree()
	o.name = "TalosClosing"
	o.queue_free()
	if tree.node_added.is_connected(_lift_layer):
		tree.node_added.disconnect(_lift_layer)
	talos_return = false
	talos_closed_frame = Engine.get_process_frames()
	Galaxy.active = bool(_talos_state.get("galaxy", Galaxy.active))
	NeonTheme.set_empire(str(_talos_state.get("empire", "")))
	var cam: Camera2D = _talos_state.get("camera") as Camera2D
	if is_instance_valid(cam) and cam.is_inside_tree():
		cam.make_current()
	tree.paused = bool(_talos_state.get("paused", false))
	_talos_state = {}
	return true


## (Older: Talos opened from a game by saving it first - kept so a save made
## that way still loads back.)
func return_from_talos() -> bool:
	talos_return = false
	return has_save(TALOS) and load_slot(TALOS)


## Saves the game into the autosave (`why` for the log). Not while you're
## under attack (the scene's in_combat()), nor mid-landing or jump.
func autosave(why := "") -> bool:
	if why != "" and not Settings.autosave_events:
		return false   # (event autosaves switched off)
	var g := _game(true)
	if g == null or (g.has_method("in_combat") and g.in_combat()):
		return false
	_auto_t = autosave_every()
	save_in_background(g.get_save_data(), AUTO)
	GameLog.post("Autosaved%s." % ((" (" + why + ")") if why != "" else ""), "info")
	return true


func _process(delta: float) -> void:
	if Settings.autosave_minutes <= 0:
		return   # (periodic autosaves off)
	_auto_t = minf(_auto_t, autosave_every())   # (a shorter interval chosen: applies at once)
	_auto_t -= delta
	if _auto_t <= 0.0:
		_auto_t = 20.0   # (couldn't save now: again in a moment)
		if _game() != null:
			autosave()


func _unhandled_input(ev: InputEvent) -> void:
	if Keybinds.pressed(ev, "quicksave") and talos_overlay() == null:
		if _game(true) != null:
			quicksave()
			get_viewport().set_input_as_handled()
	elif Keybinds.pressed(ev, "talos"):
		if talos_overlay() != null:
			get_viewport().set_input_as_handled()
			TalosNav.leave(get_tree())   # (F8 again: back to the game - the tools ask about unsaved edits first)
		elif _game(true) != null:
			get_viewport().set_input_as_handled()
			open_talos()
	elif Keybinds.pressed(ev, "live_edit") and talos_overlay() == null and LiveEditor.current == null:
		var g := _game(true)
		if g != null and g.get("world") is Node3D:
			get_viewport().set_input_as_handled()
			LiveEditor.toggle(g)   # (closed by its own F10)
	elif Keybinds.pressed(ev, "quickload") and talos_overlay() == null:   # (not from under Talos)
		if has_save(QUICK) and get_tree().current_scene and get_tree().current_scene.has_method("get_save_data"):
			get_viewport().set_input_as_handled()
			quickload()


## A word on screen for a moment (QUICKSAVED...).
func toast(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_font_override("font", NeonTheme.heavy_font())
	l.add_theme_color_override("font_color", NeonTheme.HEAD)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.position.y = 120
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(l)
	get_tree().root.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(layer.queue_free)
