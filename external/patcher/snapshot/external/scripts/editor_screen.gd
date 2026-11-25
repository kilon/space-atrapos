extends Control
## Talos, the editor (main menu > Talos): the host of all its tools, over the
## title screen's starfield. The data editor (DevMode: quest dialogue,
## chapters, lore, citizens, sprites) is here from the start; the other tools
## (Scenarios, Library, SVG, Patcher - their own scenes) are built the first
## time you open one and then kept: switching (the rail, TalosNav) only
## shows one and hides the rest - nothing is rebuilt, nothing is lost, so
## switching never asks about unsaved changes. Leaving Talos (Exit, or Esc in
## the data editor) does, tool by tool (exit()).

const MENU_SCENE := "res://main_menu.tscn"
## Where a screen not showing waits (x, px): far off to the side.
const PARKED := 100000.0

var editor: DevMode
## The tools built so far: id -> their scene's root.
var tools := {}
## The tool showing ("" - the data editor).
var current := ""
var _sky: CanvasLayer
var _dim: ColorRect
## Opened over a running game (SaveGame.open_talos): in a CanvasLayer of
## its own above the game; leaving closes it (TalosNav.leave).
var overlay := false


func _ready() -> void:
	add_to_group("talos_host")
	NeonTheme.set_empire("")
	Galaxy.active = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# (the host itself takes no mouse: over the Library - a world, not a Control -
	# a full-screen STOP here swallowed every press and drag meant for its view)
	mouse_filter = MOUSE_FILTER_IGNORE
	_sky = CanvasLayer.new()
	_sky.layer = -1
	add_child(_sky)
	if overlay:   # (over a game: an opaque ground under every tool - the Library's world too - so nothing of the game shows through)
		var ground_layer := CanvasLayer.new()
		ground_layer.layer = -3
		add_child(ground_layer)
		var ground := ColorRect.new()
		ground.color = Color(0.01, 0.0, 0.03)
		ground.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		ground.mouse_filter = MOUSE_FILTER_IGNORE
		ground_layer.add_child(ground)
	var stars: Node2D = preload("res://scripts/starfield.gd").new()
	stars.drift = Vector2(-12, 4)
	_sky.add_child(stars)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.06, 0.55)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_dim)
	# The data editor a piece a frame (all in this frame: a 35-40 ms frame as
	# Talos opened over the game): itself, its frame, then its page. A tool
	# asked for meanwhile (the rail, Exit) waits for it (_wanted). Headless
	# (tests): all at once.
	if not await _next_piece():
		return
	editor = DevMode.new()
	add_child(editor)
	# Dialogue previews play in a dialogue box of their own.
	var box: Control = preload("res://scripts/dialogue.gd").new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS   # (it pauses the tree while it plays)
	add_child(box)
	editor.dialogue = box
	editor.closed.connect(func(): TalosNav.leave(get_tree()))
	editor.zoo_requested.connect(show_tool.bind("library"))
	editor.scenario_requested.connect(show_tool.bind("scenarios"))
	editor.svg_requested.connect(show_tool.bind("svg"))
	editor.patcher_requested.connect(show_tool.bind("patcher"))
	if not await _next_piece():
		return
	editor._build()
	if not await _next_piece():
		return
	editor.open()
	PinTips.install(editor, "data-editor")
	_editor_ready = true
	if _wanted != "":
		show_tool(_wanted)
		_wanted = ""


## On to the next frame (not headless); false if Talos closed meanwhile.
func _next_piece() -> bool:
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
	return is_inside_tree()


## The data editor's made (_ready: a piece a frame); a tool asked for before that.
var _editor_ready := false
var _wanted := ""


## Shows tool `id` (a data-editor page, a tool, or "menu": leave Talos).
func show_tool(id: String) -> void:
	if not _editor_ready:
		_wanted = id   # (shown once the editor's made)
		return
	if id == "menu":
		exit()
		return
	if id in TalosNav.PAGES:
		_activate("")
		editor.show_tab(TalosNav.PAGES.find(id))
		return
	if not TalosNav.SCENES.has(id):
		return
	if not tools.has(id):
		var n: Node = TalosNav.scene(TalosNav.SCENES[id]).instantiate()
		tools[id] = n
		add_child(n)
	_activate(id)


func _activate(id: String) -> void:
	current = id
	for t in tools:
		if t != id:
			_set_on(tools[t], false)
	if id != "":
		_set_on(tools[id], true)
	_set_on(editor, id == "")
	# The Library is a world of its own (its camera, its backdrops).
	var world := id != "" and tools[id] is Node2D
	_sky.visible = not world
	_dim.visible = not world
	if overlay and get_parent() is CanvasLayer:
		# (over a game: Talos's layer follows the camera only for the Library's
		# world; the screens stay put whatever the game's camera did)
		(get_parent() as CanvasLayer).follow_viewport_enabled = world
	if not world:
		get_viewport().canvas_transform = Transform2D.IDENTITY


## A tool on (shown, running, answering input) or off (hidden and still).
func _set_on(n: Node, on: bool) -> void:
	if n.has_meta("talos_off") != on:
		return   # (already so: hiding twice would forget what was showing)
	if on:
		n.remove_meta("talos_off")
	else:
		n.set_meta("talos_off", true)
	if not on:
		if not n.has_meta("talos_mode"):
			n.set_meta("talos_mode", n.process_mode)
		n.process_mode = Node.PROCESS_MODE_DISABLED
	elif n.has_meta("talos_mode"):
		n.process_mode = n.get_meta("talos_mode")
		n.remove_meta("talos_mode")
	if n is Control:
		# (parked off to the side rather than hidden: showing a hidden screen
		# lays out all of it again - ~25 ms for the Scenario Editor - moving
		# it back, ~1 ms; off screen it isn't drawn and can't be clicked)
		n.position.x = 0.0 if on else PARKED
		if on:
			n.remove_meta("talos_parked")
		else:
			n.set_meta("talos_parked", true)
		if not on and n.get_viewport().gui_get_focus_owner() and n.is_ancestor_of(n.get_viewport().gui_get_focus_owner()):
			n.get_viewport().gui_release_focus()
	elif n is CanvasItem:
		n.visible = on
	for cl in n.get_children():   # (a tool's layers - its UI, backdrops, tooltips, dialogs - are its own children)
		if not cl is CanvasLayer:
			continue
		if on:
			cl.visible = cl.get_meta("talos_was_visible", true)
		else:
			cl.set_meta("talos_was_visible", cl.visible)
			cl.visible = false
	if on and n.has_method("talos_shown"):
		n.talos_shown()   # (work it put off while it wasn't showing)
	var cam: Camera2D = n.get("cam") if n.get("cam") is Camera2D else null
	if cam:
		cam.enabled = on
		if on:
			cam.make_current()


## Leaves Talos for the title screen (or the game it was opened from: F8 / the
## Esc menu - SaveGame.open_talos): every tool with unsaved changes is
## shown in turn and asks first (save, discard or stay).
func exit() -> void:
	if not _editor_ready:
		_wanted = "menu"
		return
	var order: Array = [editor]
	for t in ["scenarios", "svg", "patcher", "library"]:
		if tools.has(t):
			order.append(tools[t])
	_exit_from(order, 0)


func _exit_from(order: Array, i: int) -> void:
	if i >= order.size():
		TalosNav.leave(get_tree())   # (the title screen - or the game Talos was opened from)
		return
	var n: Node = order[i]
	var next := _exit_from.bind(order, i + 1)
	if n.get("dirty") == true and n.has_method("guard"):   # (the Library and Versions have none)
		show_tool(TalosNav.PAGES[TalosNav.page] if n == editor else tools.find_key(n))
		n.guard(next)
	else:
		next.call()
