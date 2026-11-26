class_name TalosNav
extends RefCounted
## Talos's navigation rail: one column down the left of every Talos screen
## listing every tool by icon and name - the data editor's pages (Dialogue,
## Chapters, Lore, Citizens, Sprites), then the 3D tools (Effects, Meshes, Animation) and,
## at the foot, the way out to the title screen. (The patch notes are the title
## screen's own: Patch Notes; the Mod Editor - Talos's tools on a mod - too.) The tool
## you're in is lit. Click another and you're there - no going back to a hub
## first (each screen asks about unsaved changes before it lets you go).
##   var root := TalosNav.wrap(UI.modal(...), "mesh", func(id): _guard(func(): TalosNav.open(get_tree(), id)))
##   (the screen's own header and body then go in `root`)

const EDITOR := "res://scenes/editor/editor.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
## The rail's size, the same on every screen: it never moves or resizes
## (fixed font, text clipped, never scaled by the text-size setting).
const WIDTH := 92
const ITEM_H := 64
## Where it sits on screen (the full-screen frames' inside corner; the
## Library places its own rail there too).
const AT := Vector2(44, 44)

## [id, name, icon, keys, what it is]; "" separates the groups.
const TOOLS := [
	["mesh", "ECurves", "mesh", "F6", "The ECurves editor: the game's models and your own as ECurve objects - collections of solids\nmade of faces, edges and vertices; primitives, materials, variants. Saves into the game (or, in the\nMod Editor, into your mod)."],
	["anim", "Animation", "anim", "F7", "The animation editor: a character's clips on a timeline - pose its bones, key them,\nmake new clips. Saves into the game (or, in the Mod Editor, into your mod)."],
	"",
	["fx", "Effects", "effects", "F4", "The effects editor: the game's particle effects (explosions, dust, sparks, impacts) - their emitters,\ncolours over life, sizes, speeds - played as you change them. Saves into the game (or your mod)."],
	"",
	["dialogue", "Dialogue", "dialogue", "Ctrl+1", "Each stage of the main quest: its objective, rewards and the dialogue\nthat plays when it starts. Preview the dialogue in the game's own box."],
	["chapters", "Chapters", "ui_journal", "Ctrl+2", "The titles of the main quest's chapters, as shown in the Automaton."],
	["lore", "Lore", "lore", "Ctrl+3", "The lore entries the player unlocks during the quest (titles and BBCode text)."],
	["citizens", "Citizens", "chat", "Ctrl+4", "What Minoan citizens say when you click them: the Minoan words\nand their translation (shown in the event log)."],
	["sprites", "Sprites", "sprites", "Ctrl+5", "Every sprite of the game by group (hover one for its key and file).\nReload them after re-cutting the reference sheets."],
]
## The data editor's pages, in TOOLS order (DevMode.TABS).
const PAGES := ["dialogue", "chapters", "lore", "citizens", "sprites"]
const SCENES := {"fx": "res://scenes/editor/fx_editor.tscn", "mesh": "res://scenes/editor/mesh_editor.tscn", "anim": "res://scenes/editor/anim_editor.tscn", "menu": MENU}
## The tools with scenes of their own (the host builds each the first time it's opened).
const TOOL_IDS := ["fx", "mesh", "anim"]

## The data editor's page to open on (set when another tool sends you to one).
static var page := 0
## The tool Talos opens on (the mesh editor; a data page when another screen sends you to one).
static var start := "mesh"


## The rail, `current` lit; clicking a tool calls go(id) ("menu": the title screen).
## `keys`: the rail also answers the tools' shortcuts (Ctrl+1-5, F4, F6, F7)
## - not for the data editor, which has its own.
static func rail(current: String, go: Callable, keys := true) -> VBoxContainer:
	_warm()
	var box := VBoxContainer.new()
	box.name = "TalosNav"
	if keys:
		var k := Keys.new()
		k.go = go
		k.current = current
		box.add_child(k)
	box.custom_minimum_size.x = WIDTH
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.set_meta("fixed_font", true)   # (UI.scale_fonts leaves it alone)
	box.add_theme_constant_override("separation", 4)
	for t in TOOLS:
		if t is String:
			var sep := HSeparator.new()
			sep.add_theme_constant_override("separation", 10)
			box.add_child(sep)
			continue
		box.add_child(_item(t[0], t[1], t[2], EditorIcons.tip(t[1], t[3], t[4]), go))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(gap)
	if SaveGame.talos_return:   # (opened from a game: leaving goes back to it)
		box.add_child(_item("menu", "Back", "exit", EditorIcons.tip("Back to the game", "Esc", "Back to your game, where you left it. Each tool asks about unsaved changes first;\nwhat you changed here applies to it.")
			, go))
	else:
		box.add_child(_item("menu", "Exit", "exit", EditorIcons.tip("Exit Talos", "Esc", "Back to the title screen. Each tool asks about unsaved changes first;\nedits already made apply to games started from here on.")
			, go))
	select(box, current)
	return box


static func _item(id: String, name: String, icon: String, tip: String, go: Callable) -> Button:
	var b := Button.new()
	b.name = "Nav_" + id
	b.text = name
	b.icon = EditorIcons.get_icon(icon)
	IconAnim.attach(b, icon)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(WIDTH, ITEM_H)
	b.clip_text = true   # (a long name can't widen the rail)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 13)
	b.tooltip_text = tip
	b.set_meta("talos_nav", id)
	b.pressed.connect(func():
		select(b.get_parent(), str(b.get_parent().get_meta("current", "")))   # (lit only when you get there)
		go.call(id))
	return b


## The tools' scenes, loaded in the background once Talos is open, so the
## first visit to each doesn't wait for its scripts and scene to load
## (~0.4-1 s the first time; then they're ready).
static func _warm() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for path in [EDITOR] + SCENES.values():
		if path != MENU and not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


## Lights `current`'s button.
static func select(box: Node, current: String) -> void:
	box.set_meta("current", current)
	for b in box.get_children():
		if b is Button:
			b.set_pressed_no_signal(b.get_meta("talos_nav", "") == current)


## The rail beside a screen's content: `root` (a full-screen modal's box)
## gets the rail and a column for the screen, which is returned.
static func wrap(root: VBoxContainer, current: String, go: Callable, keys := true) -> VBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)
	row.add_child(rail(current, go, keys))
	var sep := VSeparator.new()
	row.add_child(sep)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	return col


## The Talos host (editor_screen.gd: every tool kept, switched by showing
## one), or null when a tool runs as a scene of its own (tests).
static func host(tree: SceneTree) -> Node:
	var s := tree.current_scene
	if s != null and s.has_method("show_tool"):
		return s
	return tree.get_first_node_in_group("talos_host")   # (Talos over a game)


## The rail's click from a tool: in the host, straight there (the tool stays
## as it is, so nothing to ask); on its own, `guard` first (it asks about
## unsaved changes, then calls what it's given), then the tool's scene.
static func go(tree: SceneTree, id: String, guard := Callable()) -> void:
	var h := host(tree)
	if h:
		h.show_tool(id)
	elif guard.is_valid():
		guard.call(func(): open(tree, id))
	else:
		open(tree, id)


## A tool's scene: the one loaded in the background (_warm) if it's there.
static func scene(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var r := ResourceLoader.load_threaded_get(path)
		if r is PackedScene:
			return r
	return load(path)


## Leaves Talos: back to the game it was opened from (SaveGame.open_talos),
## else to the title screen.
static func leave(tree: SceneTree) -> void:
	if SaveGame.close_talos():
		return   # (Talos was over the game: the game, as it was)
	if SaveGame.talos_return and SaveGame.return_from_talos():
		return
	tree.change_scene_to_file(MENU)


## Goes to tool `id` (a data-editor page, a tool, or "menu").
static func open(tree: SceneTree, id: String) -> void:
	var h := host(tree)
	if h:
		h.show_tool(id)   # ("menu": the host's exit - it asks about unsaved changes, then leave())
		return
	if id == "menu":
		leave(tree)
		return
	if id in PAGES:
		page = PAGES.find(id)
		start = id
		tree.change_scene_to_file(EDITOR)
	elif SCENES.has(id):
		tree.change_scene_to_file(SCENES[id])


## A screen's header: its name (and a line under it, `note`, for status
## messages) on the left; the screen's own buttons go after the spacer.
## Returns [header, note label].
static func header(title: String, note: String, accent: Color) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var t := UI.label(title, 24, accent)
	t.name = "TalosTitle"
	h.add_child(t)
	var n := UI.label(note, 14, UI.TEXT_DIM)
	n.name = "TalosNote"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(n)
	return [h, n]


## The tools' shortcuts, wherever you are in Talos (before the tool's own keys:
## Ctrl+digit isn't a room or a zoom here).
class Keys extends Node:
	var go: Callable
	var current := ""

	func _input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo or not is_visible_in_tree_safe():
			return
		var id := ""
		if k.ctrl_pressed and k.keycode >= KEY_1 and k.keycode < KEY_1 + PAGES.size():
			id = PAGES[k.keycode - KEY_1]
		elif not k.ctrl_pressed:
			id = {KEY_F4: "fx", KEY_F6: "mesh", KEY_F7: "anim"}.get(k.keycode, "")
		if id == "" or id == current:
			return
		get_viewport().set_input_as_handled()
		go.call(id)

	func is_visible_in_tree_safe() -> bool:
		var p := get_parent() as Control
		return p != null and p.is_visible_in_tree()
