class_name LoadVeil
extends CanvasLayer
## A scene change to the game (a new game, a save loaded, back from Talos) -
## with NO loading screen: nothing is shown over the game (its screen is made
## but hidden, and lets clicks through), the space scene comes into view as
## it's built, pictures not loaded yet stand in as placeholders (ProcArt.sprite)
## and a new game's economy warms up while you play (Galaxy.new_game_async).
## It still follows the load (what it's waiting for, the bar's value - tests).
## A save made in space: the galaxy and the system are rebuilt (one long
## frame); one made on a planet: then the surface is built too (the bar
## follows its build_progress). It fades out once the game scene is ready
## (SaveGame.travelling back to false; a surface built) - or after TIMEOUT
## seconds, whatever happened.
##   LoadVeil.change_to("res://main.tscn", "Loading slot 2")

const TIMEOUT := 30.0
const FADE := 0.3
## Of the bar: the space scene; the rest, a planet's surface if there's one.
const SPACE_SHARE := 0.3

var _bar: ProgressBar
var _stage: Label
var _root: Control
var _t := 0.0
var _shown := 0.0
var _ready_frames := 0
var _closing := false
## The scene to wait for (tests); else the current scene.
var watch: Node = null
## The scene showing when the load began (it may be a game too: loading
## from its menu) - only a new one counts.
var _from: Node = null
var _changed := false


## Shows the veil, lets it draw, then changes to `path` under it. `prepare`:
## work done first, under the veil, across frames (a coroutine taking a
## progress Callable(share) - a new game's galaxy: Galaxy.new_game_async),
## with its own `stage` line.
static func change_to(path: String, title := "Loading", prepare := Callable(), stage := "") -> LoadVeil:
	var tree := Engine.get_main_loop() as SceneTree
	var v := LoadVeil.new()
	v.name = "LoadVeil"
	tree.root.add_child(v)
	v._build(title)
	v._prepare = prepare
	if stage != "":
		v._stage.text = stage
	v._go.call_deferred(path)
	return v


var _prepare := Callable()
var _prep_share := -1.0   # the preparation's progress (-1: none)
var _art_wait := false   # (nothing waits for the art now: kept for the time-out check)
var _art_part := 0.0


func _build(title: String) -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # (no clicks through while loading)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(NeonTheme.BG, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	_root.add_child(box)
	var head := Label.new()
	head.text = title.to_upper()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", NeonTheme.CYAN)
	box.add_child(head)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(620, 22)
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var back := NeonBox.new()
	back.bg_color = Color(NeonTheme.BG, 0.9)
	back.border_color = NeonTheme.HEAD
	var fill := NeonBox.new()
	fill.bg_color = NeonTheme.CYAN
	fill.border_color = NeonTheme.PINK
	fill.light = 0.5
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	_stage = Label.new()
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_font_size_override("font_size", 22)
	_stage.add_theme_color_override("font_color", Color(NeonTheme.HEAD, 0.85))
	_stage.text = "Restoring the galaxy"
	box.add_child(_stage)
	# (No loading screen: the game shows as it's made.)
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _go(path: String) -> void:
	# Two frames so the veil is on screen before the long frame of the load.
	await get_tree().process_frame
	await get_tree().process_frame
	# (The game's art isn't waited for: it keeps loading in the background,
	# placeholders standing in for pictures not in yet - ProcArt.sprite.)
	if _prepare.is_valid():
		_prep_share = 0.0
		await _prepare.call(func(share: float): _prep_share = _art_part + share * (1.0 - _art_part))
		_prep_share = 1.0
		_t = 0.0   # (the time-out counts from here)
	get_tree().paused = false
	_from = get_tree().current_scene
	_changed = true
	await UI.switch_scene(path)


func _process(delta: float) -> void:
	if _closing:
		return
	_t += delta
	var s := watch if watch != null else get_tree().current_scene
	var target := 0.05 if _prep_share < 0.0 else _prep_share * SPACE_SHARE
	var done := false
	if (watch != null or (_changed and s != _from)) and s != null and s.has_method("get_save_data"):
		var surface := s.get("is_built") != null
		if surface:
			target = SPACE_SHARE + (1.0 - SPACE_SHARE) * float(s.get("build_progress"))
			var p := str(SaveGame.landed_planet)
			_stage.text = "Landing on " + str(Planets.get_planet(p).get("name", p)) if p != "" else "Landing"
			done = s.get("is_built") == true and not SaveGame.travelling and (not s.has_method("world_settled") or s.world_settled())
		else:
			target = SPACE_SHARE
			done = not SaveGame.travelling and (not s.has_method("build_settled") or s.build_settled())
	_shown = move_toward(_shown, target, delta * 2.0)
	if done:
		_ready_frames += 1
		_shown = 1.0
	_bar.value = _shown
	if _ready_frames >= 3 or (_t > TIMEOUT and not _art_wait):   # (a few frames for the first picture)
		_close()


func _close() -> void:
	_closing = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE)
	tw.tween_callback(queue_free)
