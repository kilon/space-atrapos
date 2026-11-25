extends Control
## Mods (the title screen's Mods): every mod installed (user://mods/), each turned
## on or off, the turned-on ones in their order (a later one wins where two change
## the same file); install one from a zip, share one as a zip, delete one, open
## one in the Mod Editor. Mods load as the game starts: a change asks for a restart.

const ACCENT := Color(0.55, 0.85, 1.0)
const EDITOR_SCENE := "res://scenes/editor/mod_editor.tscn"

signal closed

var _list: VBoxContainer
var _note: Label
var _restart: Button
var _dialog: FileDialog


## The screen over `parent` (the title screen), on a layer of its own.
static func open_over(parent: Node) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.name = "ModsScreen"
	parent.add_child(layer)
	var s: Control = load("res://scripts/ui/mods_screen.gd").new()
	s.closed.connect(layer.queue_free)
	layer.add_child(s)
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var root := UI.modal(self, ACCENT, Vector2(1180, 760))
	var h: Array = TalosNav.header("MODS", "your changes to the game - any of it - laid over it as it starts", ACCENT)
	var header: HBoxContainer = h[0]
	header.add_child(_btn("Mod Editor", "mod", "Make a new mod or change one: any of the game's files, its meshes and animations.", func(): open_editor("")))
	if not OS.has_feature("web"):
		header.add_child(_btn("Install", "open", "Installs a mod from a zip file (one shared with Export).", _install))
		header.add_child(_btn("Folder", "docs", "Opens the mods' folder - a mod is a folder in it (mod.json, files/).", func():
			OS.shell_open(ProjectSettings.globalize_path(Mods.DIR))))
	var back := _btn("Back", "back", "Back to the menu (Esc).", close)
	back.name = "BackButton"
	header.add_child(back)
	root.add_child(header)
	var bar := HBoxContainer.new()
	_note = UI.label("", 14, UI.TEXT_DIM)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_note)
	_restart = UI.button("Restart to apply", Mods.restart, 16)
	_restart.name = "RestartButton"
	_restart.tooltip_text = "Mods load as the game starts: restarts it with the mods turned on now."
	bar.add_child(_restart)
	root.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1100, 560)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "ModList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	refresh()


func close() -> void:
	closed.emit()
	if get_parent() is CanvasLayer:
		return
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## The list again (after any change).
func refresh() -> void:
	UI.clear(_list)
	var mods := Mods.installed()
	var lines := PackedStringArray()
	if Mods.safe_mode:
		lines.append("Started without mods: the last start with them didn't reach the title screen.")
	for e in Mods.errors:
		lines.append(e)
	if mods.is_empty():
		lines.append("No mods yet. Make one in the Mod Editor, or install one from a zip.")
	elif Mods.active.is_empty():
		lines.append("Running without mods.")
	else:
		var names := PackedStringArray()
		for m in Mods.active:
			names.append(str(m["name"]))
		lines.append("Running with: " + ", ".join(names) + ".")
	_note.text = "\n".join(lines)
	_restart.visible = Mods.needs_restart()
	var on := Mods.enabled()
	for m in mods:
		_list.add_child(_row(m, on))


func _row(m: Dictionary, on: PackedStringArray) -> Control:
	var id := str(m["id"])
	var panel := PanelContainer.new()
	panel.name = "Mod_" + id
	panel.add_theme_stylebox_override("panel", UI.panel_style(ACCENT if m["enabled"] else UI.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var check := CheckBox.new()
	check.name = "On"
	check.button_pressed = m["enabled"]
	check.tooltip_text = "Turned on: loaded as the game starts (Restart to apply)."
	check.toggled.connect(func(v): Mods.set_enabled(id, v); refresh())
	row.add_child(check)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var title := "%s  %s" % [m["name"], m["version"]]
	if str(m["author"]) != "":
		title += "  ·  by " + str(m["author"])
	if m["enabled"]:
		title = "%d. %s" % [on.find(id) + 1, title]
	col.add_child(UI.label(title, 18, NeonTheme.HEAD))
	if str(m["description"]) != "":
		var d := UI.label(str(m["description"]), 14, UI.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
	var files := Mods.mod_files(id)
	var facts := PackedStringArray(["%d file%s" % [files.size(), "" if files.size() == 1 else "s"]])
	if str(m["main"]) != "":
		facts.append("runs a script of its own (it can do anything a game script can)")
	if m.has("broken"):
		facts.append("broken: " + str(m["broken"]))
	var shared := 0
	for p in files:
		var t: Array = Mods.touched.get(p.trim_suffix(".merge"), [])
		if t.size() > 1:
			shared += 1
	if shared > 0:
		facts.append("%d file%s also changed by another mod (the later one wins)" % [shared, "" if shared == 1 else "s"])
	col.add_child(UI.label("  ·  ".join(facts), 13, UI.TEXT_DIM))
	if m["enabled"]:
		row.add_child(_btn("", "up", "Earlier in the load order.", func(): Mods.move(id, -1); refresh()))
		row.add_child(_btn("", "down", "Later in the load order (wins over the ones before it).", func(): Mods.move(id, 1); refresh()))
	row.add_child(_btn("Edit", "tool", "Opens this mod in the Mod Editor.", func(): open_editor(id)))
	if not OS.has_feature("web"):
		row.add_child(_btn("Export", "export", "Saves this mod as a zip, to share (Install takes it).", func(): _export(id)))
	row.add_child(_btn("Delete", "delete", "Deletes this mod and its files.", func():
		UI.confirm(self, "DELETE MOD", "Delete \"%s\" and all its files? This can't be undone." % m["name"], func(): Mods.remove(id); refresh(), "Delete", "Keep")))
	return panel


func _btn(text: String, icon: String, help: String, cb: Callable) -> Button:
	var b := UI.button(text, cb, 15)
	b.focus_mode = Control.FOCUS_NONE
	EditorIcons.dress(b, icon, EditorIcons.tip(text if text != "" else help.get_slice(" (", 0), "", help))
	if text != "":
		b.text = text
	return b


## The Mod Editor on mod `id` ("" - its own list: pick or make one).
func open_editor(id: String) -> void:
	var s: GDScript = load("res://scripts/editor/mod_editor.gd")
	s.set("start_mod", id)
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _file_dialog(mode: FileDialog.FileMode, title: String, cb: Callable) -> void:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.zip ; Mod (zip)"])
	_dialog.title = title
	_dialog.use_native_dialog = true
	add_child(_dialog)
	_dialog.file_selected.connect(cb)
	_dialog.popup_centered(Vector2i(900, 600))


func _install() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Install a mod", func(path: String):
		var id := Mods.install_zip(path)
		refresh()
		if id != "":
			_note.text = "Installed \"%s\" - turn it on, then restart." % Mods.info(id).get("name", id))


func _export(id: String) -> void:
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export the mod as a zip", func(path: String):
		if not path.ends_with(".zip"):
			path += ".zip"
		_note.text = ("Saved " + path) if Mods.export_zip(id, path) else ("Couldn't write " + path))
