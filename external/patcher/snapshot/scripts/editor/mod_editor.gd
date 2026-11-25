class_name ModEditor
extends Control
## The Mod Editor: makes mods - your changes to the game, any of it, kept apart from
## it (Mods lays them over the game as it starts). Standalone: the title screen's
## Mods > Mod Editor, or straight in with `-- --mod-editor` on the command line.
##
## FILES: the game's files (left) - copy one into the mod to change it (Override:
## the mod's copy replaces it), or start a merge patch for a JSON data file (a few
## entries changed, not the whole file: Mods merges it in); the mod's files (right)
## - edited in place: text, JSON, scripts, scenes, shaders with their colours and a
## check as you save; pictures shown and replaced from a file; models opened in the
## mesh editor. New files are added to the game (a new script, a new picture...).
## MESHES / ANIMATION / EFFECTS: Talos's mesh, animation and effects editors, saving into the mod
## (EditTarget.mod_id).
## The mod's own script (mod.json "main"): runs once the game's up - a Node added
## to the root, free to do anything a game script can.

const ACCENT := Color(0.55, 0.85, 1.0)
const MENU := "res://scenes/ui/main_menu.tscn"
const TEXT := ["gd", "json", "merge", "md", "txt", "cfg", "tscn", "tres", "gdshader", "gdshaderinc", "csv", "ini", "glsl"]
const IMAGES := ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]
const MODELS := ["glb", "gltf"]
const SOUNDS := ["ogg", "wav", "mp3"]
## The game's folders not shown (not part of the game, or Godot's own).
const HIDDEN := [".godot", "external", "tests", "tools", "addons", ".git", "build", "export"]
const TABS := ["FILES", "MESHES", "ANIMATION", "EFFECTS"]
## The tools the tabs after FILES embed (TalosNav ids), in TABS order.
const TOOL_TABS := ["mesh", "anim", "fx"]

## The mod to open on (the Mods screen's Edit sets it before switching here).
static var start_mod := ""

## The mod being made ("" - none yet).
var mod_id := ""
## The open file's text has unsaved changes.
var dirty := false
var current_tab := 0
var _open := ""                 # res:// path of the file open in the mod
var _picker: OptionButton
var _target: Label
var _status: Label
var _tab_bar: HBoxContainer
var _pages: Array = []          # tab -> its Control
var _game_tree: Tree
var _mod_tree: Tree
var _filter: LineEdit
var _view: VBoxContainer        # the open file's view
var _code: CodeEdit
var _file_title: Label
var _file_note: Label
var _tools := {}                # "mesh" / "anim" / "fx" -> the embedded editor
var _dialog: FileDialog
var _player: AudioStreamPlayer


func _ready() -> void:
	NeonTheme.set_empire("")
	Galaxy.active = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var sky := CanvasLayer.new()
	sky.layer = -1
	add_child(sky)
	var stars: Node2D = preload("res://scripts/ui/starfield.gd").new()
	stars.drift = Vector2(-12, 4)
	sky.add_child(stars)
	_build()
	PinTips.install(self, "mod-editor")   # (the editor screens' tooltips, as in Talos)
	var first := start_mod
	start_mod = ""
	if first == "" and not Mods.installed().is_empty():
		first = str(Mods.installed()[0]["id"])
	set_mod(first)


func _exit_tree() -> void:
	EditTarget.mod_id = ""


func _build() -> void:
	var root := UI.modal(self, ACCENT, Vector2.ZERO, true)
	var h: Array = TalosNav.header("MOD EDITOR", "", ACCENT)
	var header: HBoxContainer = h[0]
	_target = h[1]
	_picker = OptionButton.new()
	_picker.name = "ModPicker"
	_picker.custom_minimum_size.x = 260
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.tooltip_text = "The mod you're making."
	_picker.item_selected.connect(func(i): _guard(func(): set_mod(str(_picker.get_item_metadata(i))), func(): _sync_picker()))
	header.add_child(_picker)
	header.add_child(_btn("New mod", "new", "Ctrl+N", "Starts a new, empty mod.", _new_mod_dialog))
	header.add_child(_btn("Properties", "rename", "", "The mod's name, version, author, description and its own script.", _properties))
	header.add_child(_btn("Check", "accept", "", "Checks every file of the mod: JSON that parses, scripts that compile, scenes and resources that load.", validate))
	header.add_child(_btn("Test in game", "play", "F5", "Turns this mod on and restarts the game with it.", _test))
	if not OS.has_feature("web"):
		header.add_child(_btn("Export", "export", "", "Saves the mod as a zip to share (Mods > Install takes it).", _export))
	header.add_child(EditorIcons.docs_button(self, "mods"))
	header.add_child(_btn("Back", "back", "Esc", "Back to the title screen.", leave))
	root.add_child(header)
	_tab_bar = UI.tab_bar(TABS, show_tab, ACCENT, false, [
		EditorIcons.tip("Files", "", "The game's files and your mod's: override one of the game's, add new ones, edit text, replace pictures,\nmodels and sounds."),
		EditorIcons.tip("Meshes", "", "The mesh editor, saving into this mod: the game's models and your own."),
		EditorIcons.tip("Animation", "", "The animation editor, saving into this mod: the characters' clips."),
		EditorIcons.tip("Effects", "", "The effects editor, saving into this mod: the game's particle effects.")])
	root.add_child(_tab_bar)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stack)
	var files := _build_files()
	_add_page(stack, files)
	for i in TOOL_TABS.size():
		var holder := VBoxContainer.new()
		holder.name = ["Meshes", "Animation", "Effects"][i]
		_add_page(stack, holder)
	_status = UI.label("", 14, UI.TEXT_DIM)
	_status.name = "Status"
	_status.clip_text = true
	root.add_child(_status)
	show_tab(0)


func _add_page(stack: Control, page: Control) -> void:
	page.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stack.add_child(page)
	_pages.append(page)


func _build_files() -> Control:
	var split := HSplitContainer.new()
	split.name = "Files"
	# The game's files.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 380
	split.add_child(left)
	left.add_child(UI.section("THE GAME"))
	_filter = LineEdit.new()
	_filter.placeholder_text = "Find a file..."
	_filter.tooltip_text = "Shows only the game's files whose path has these words."
	_filter.text_changed.connect(func(_t): _fill_game())
	left.add_child(_filter)
	_game_tree = Tree.new()
	_game_tree.name = "GameFiles"
	_game_tree.hide_root = true
	_game_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game_tree.tooltip_text = EditorIcons.tip("The game's files", "Enter", "Every file of the game, by folder. Double-click one (or Override) to copy it into your mod,\nwhere your copy replaces the game's.")
	_game_tree.item_activated.connect(func(): override(_selected(_game_tree)))
	_game_tree.item_collapsed.connect(_on_collapse)
	left.add_child(_game_tree)
	var gb := HBoxContainer.new()
	gb.add_child(_btn("Override", "duplicate", "Enter", "Copies the game's file into the mod: change the copy, it replaces the game's.", func(): override(_selected(_game_tree))))
	gb.add_child(_btn("Merge patch", "add", "", "For a JSON data file: a patch merged into it (only what you put in it changes - key by key).", func(): merge_patch(_selected(_game_tree))))
	left.add_child(gb)
	# The mod's files.
	var right_split := HSplitContainer.new()
	split.add_child(right_split)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 340
	right_split.add_child(mid)
	mid.add_child(UI.section("THE MOD"))
	_mod_tree = Tree.new()
	_mod_tree.name = "ModFiles"
	_mod_tree.hide_root = true
	_mod_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mod_tree.tooltip_text = EditorIcons.tip("The mod's files", "", "Your mod's files, laid out like the game's: each replaces the game's file at that path (or adds a new one).\nClick one to open it on the right.")
	_mod_tree.item_selected.connect(func():
		var p := _selected(_mod_tree)
		if p != "" and p != _open:
			_guard(func(): open_file(p), func(): _select_open()))
	mid.add_child(_mod_tree)
	var mb := HBoxContainer.new()
	mb.add_child(_btn("New file", "new", "", "Adds a new file to the game (a script, data, a scene...) at a path you choose.", _new_file_dialog))
	mb.add_child(_btn("Main script", "gui", "", "The mod's own script: runs once the game's up and can change anything (made if it hasn't one).", main_script))
	mb.add_child(_btn("Remove", "delete", "Delete", "Removes the file from the mod (the game's own, if any, is back).", func(): _remove(_selected(_mod_tree))))
	mid.add_child(mb)
	# The open file.
	_view = VBoxContainer.new()
	_view.name = "FileView"
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(_view)
	return split


func _btn(name: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button(name, cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	EditorIcons.dress(b, icon, EditorIcons.tip(name, keys, help))
	b.text = name
	return b


func show_tab(i: int) -> void:
	current_tab = i
	UI.select_tab(_tab_bar, i)
	for k in _pages.size():
		_pages[k].visible = k == i
	if i > 0:
		var id: String = TOOL_TABS[i - 1]
		if not _tools.has(id):
			var path: String = TalosNav.SCENES[id]
			if not ResourceLoader.exists(path):
				_pages[i].add_child(UI.label("Not available in this build.", 16, UI.TEXT_DIM))
				_tools[id] = null
				return
			var t: Node = load(path).instantiate()
			t.set("embedded", true)
			_tools[id] = t
			_pages[i].add_child(t)
			if t is Control:
				t.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if _tools[id] and _tools[id].has_method("talos_shown"):
			_tools[id].talos_shown()


## The embedded tool `id` ("mesh" / "anim" / "fx"), built if needed.
func tool(id: String) -> Node:
	show_tab(TOOL_TABS.find(id) + 1)
	return _tools.get(id)


# --- The mod --------------------------------------------------------------------

func set_mod(id: String) -> void:
	mod_id = id
	EditTarget.mod_id = id
	_open = ""
	dirty = false
	_sync_picker()
	_fill_game()
	_fill_mod()
	_show_none()
	_target.text = ("saving into " + EditTarget.label()) if id != "" else "no mod yet - New mod to start one"
	for t in _tools.values():
		if t and t.has_method("target_changed"):
			t.target_changed()


func _sync_picker() -> void:
	_picker.clear()
	var i := 0
	for m in Mods.installed():
		_picker.add_item(str(m["name"]))
		_picker.set_item_metadata(i, m["id"])
		if m["id"] == mod_id:
			_picker.select(i)
		i += 1
	if i == 0:
		_picker.add_item("(no mods)")
		_picker.set_item_metadata(0, "")


func new_mod(name: String) -> String:
	var id := Mods.create(name)
	set_mod(id)
	_say("Made \"%s\" (user://mods/%s/). Override the game's files, add new ones, or edit meshes and animations." % [name, id])
	return id


func _new_mod_dialog() -> void:
	_ask_text("NEW MOD", "Its name:", "My mod", func(t: String):
		if t.strip_edges() != "":
			_guard(func(): new_mod(t.strip_edges())))


func _properties() -> void:
	if mod_id == "":
		return
	var m := Mods.info(mod_id)
	var box := VBoxContainer.new()
	var fields := {}
	for k in ["name", "version", "author", "description", "main"]:
		var row := HBoxContainer.new()
		var l := UI.label(k.capitalize() if k != "main" else "Main script", 15)
		l.custom_minimum_size.x = 140
		row.add_child(l)
		var e := LineEdit.new()
		e.text = str(m.get(k, ""))
		e.custom_minimum_size.x = 460
		e.placeholder_text = "res://mods/%s/main.gd (runs once the game's up)" % mod_id if k == "main" else ""
		row.add_child(e)
		fields[k] = e
		box.add_child(row)
	_panel_dialog("MOD PROPERTIES", box, func():
		for k in fields:
			m[k] = fields[k].text.strip_edges()
		Mods.save_info(m)
		_sync_picker()
		_target.text = "saving into " + EditTarget.label())


# --- The game's files ---------------------------------------------------------------

func _fill_game() -> void:
	_game_tree.clear()
	var root := _game_tree.create_item()
	var words := _filter.text.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		_add_dir(root, "res://", true)
		return
	# (searching: every match, as a flat list of paths)
	var all := PackedStringArray()
	_walk_game("res://", all, 4000)
	for p in all:
		var ok := true
		for w in words:
			if not p.to_lower().contains(w):
				ok = false
				break
		if ok:
			var it := _game_tree.create_item(root)
			it.set_text(0, p.trim_prefix("res://"))
			it.set_metadata(0, p)
			_mark(it, p)


## A folder's entries under `parent` (folders lazily: filled when opened).
func _add_dir(parent: TreeItem, dir: String, open: bool) -> void:
	for sub in _dirs(dir):
		var it := _game_tree.create_item(parent)
		it.set_text(0, sub + "/")
		it.set_metadata(0, dir + sub + "/")
		it.set_icon(0, EditorIcons.get_icon("open"))
		it.set_icon_max_width(0, 16)
		_game_tree.create_item(it).set_text(0, "...")   # (filled when opened)
		it.collapsed = true
	for f in _files(dir):
		var it := _game_tree.create_item(parent)
		it.set_text(0, f)
		it.set_metadata(0, dir + f)
		_mark(it, dir + f)
	if parent:
		parent.collapsed = not open


func _on_collapse(it: TreeItem) -> void:
	if it.collapsed or it.get_child_count() != 1 or it.get_first_child().get_text(0) != "...":
		return
	it.get_first_child().free()
	_add_dir(it, str(it.get_metadata(0)), true)


func _mark(it: TreeItem, p: String) -> void:
	if EditTarget.overridden(p):
		it.set_custom_color(0, ACCENT)
		it.set_tooltip_text(0, p + "\nThe mod replaces it.")
	elif EditTarget.overridden(p + ".merge"):
		it.set_custom_color(0, ACCENT.lerp(Color.WHITE, 0.4))
		it.set_tooltip_text(0, p + "\nThe mod merges a patch into it.")
	else:
		it.set_tooltip_text(0, p)


func _dirs(dir: String) -> PackedStringArray:
	var d := DirAccess.open(dir)
	var out := PackedStringArray()
	if d == null:
		return out
	for s in d.get_directories():
		if s.begins_with(".") or (dir == "res://" and s in HIDDEN):
			continue
		out.append(s)
	out.sort()
	return out


## A folder's files as the game knows them (an exported game's imports and
## remaps under their own names; Godot's own files left out).
func _files(dir: String) -> PackedStringArray:
	var d := DirAccess.open(dir)
	var out := PackedStringArray()
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".remap"):
			f = f.get_basename()
		if f.ends_with(".uid") or f.begins_with(".") or f.ends_with(".gdc") or f in out:
			continue
		if dir == "res://" and f != "icon.png":
			continue   # (the project's own files: its settings, its notes - not the game's)
		out.append(f)
	out.sort()
	return out


func _walk_game(dir: String, out: PackedStringArray, cap: int) -> void:
	for f in _files(dir):
		if out.size() >= cap:
			return
		out.append(dir + f)
	for s in _dirs(dir):
		_walk_game(dir + s + "/", out, cap)


func _selected(tree: Tree) -> String:
	var it := tree.get_selected()
	return str(it.get_metadata(0)) if it and it.get_metadata(0) != null else ""


## The game's file `p` copied into the mod (opened there); "" (or a folder) - nothing.
func override(p: String) -> bool:
	if mod_id == "" or p == "" or p.ends_with("/"):
		return false
	if EditTarget.overridden(p):
		open_file(p)
		return true
	var bytes := game_bytes(p)
	if bytes.is_empty() and p.get_extension() in ["gd"]:
		_say("This build has no source for %s (its scripts are compiled): write the mod's version from scratch." % p)
	var to := EditTarget.write_path(p)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f == null:
		_say("Can't write " + to)
		return false
	f.store_buffer(bytes)
	f.close()
	_fill_mod()
	_refresh_marks()
	open_file(p)
	_say("%s copied into the mod - change it here; the mod's copy replaces the game's." % p)
	return true


## A game file's bytes as the mod's copy starts: the file itself when the game has it as
## it is (a project run; text in an export); else made from what the game loads (a
## picture's image as PNG, a model as GLB).
func game_bytes(p: String) -> PackedByteArray:
	var ext := p.get_extension().to_lower()
	var raw := FileAccess.get_file_as_bytes(p)
	if not raw.is_empty():
		return raw
	if ext in IMAGES and ResourceLoader.exists(p):
		var t = load(p)
		if t is Texture2D and (t as Texture2D).get_image():
			return (t as Texture2D).get_image().save_png_to_buffer()
	if ext in MODELS and ResourceLoader.exists(p):
		var ps = load(p)
		if ps is PackedScene:
			var n: Node = ps.instantiate()
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_scene(n, st) == OK:
				var buf := doc.generate_buffer(st)
				n.free()
				return buf
			n.free()
	if ext == "gd" and ResourceLoader.exists(p):
		var s = load(p)
		if s is GDScript and (s as GDScript).source_code != "":
			return (s as GDScript).source_code.to_utf8_buffer()
	return PackedByteArray()


## A merge patch for the game's JSON file `p`: an empty object to fill with what changes.
func merge_patch(p: String) -> bool:
	if mod_id == "" or p.get_extension() != "json":
		_say("A merge patch is for a JSON data file: pick one in the game's files.")
		return false
	var mp := p + ".merge"
	if not EditTarget.overridden(mp):
		var f := FileAccess.open(EditTarget.write_path(mp), FileAccess.WRITE)
		f.store_string("{\n\t\n}\n")
		f.close()
		_fill_mod()
		_refresh_marks()
	open_file(mp)
	_say("Put in it only what changes (as in %s): objects merge key by key, anything else replaces." % p.get_file())
	return true


func _refresh_marks() -> void:
	var it := _game_tree.get_root()
	while it:
		if it.get_metadata(0) != null and not str(it.get_metadata(0)).ends_with("/"):
			_mark(it, str(it.get_metadata(0)))
		it = it.get_next_in_tree()


# --- The mod's files ------------------------------------------------------------------

func _fill_mod() -> void:
	_mod_tree.clear()
	var root := _mod_tree.create_item()
	if mod_id == "":
		return
	var folders := {}
	for p in Mods.mod_files(mod_id):
		var rel := p.trim_prefix("res://")
		var parent := root
		var acc := ""
		for part in rel.get_base_dir().split("/", false):
			acc += part + "/"
			if not folders.has(acc):
				var f := _mod_tree.create_item(parent)
				f.set_text(0, part + "/")
				f.set_selectable(0, false)
				folders[acc] = f
			parent = folders[acc]
		var it := _mod_tree.create_item(parent)
		it.set_text(0, rel.get_file())
		it.set_metadata(0, p)
		var kind := "merged into the game's" if p.ends_with(".merge") else ("replaces the game's" if _game_has(p) else "new")
		it.set_tooltip_text(0, "%s\n%s" % [p, kind])
		it.set_custom_color(0, ACCENT if kind.begins_with("replaces") else (Color(0.6, 1.0, 0.7) if kind == "new" else ACCENT.lerp(Color.WHITE, 0.4)))
	_select_open()


## The game has a file `p` (the mod's would replace it).
func _game_has(p: String) -> bool:
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)


func _select_open() -> void:
	var it := _mod_tree.get_root()
	while it:
		if str(it.get_metadata(0)) == _open and _open != "":
			it.select(0)
			return
		it = it.get_next_in_tree()


func _remove(p: String) -> void:
	if p == "":
		return
	UI.confirm(self, "REMOVE FILE", "Remove %s from the mod?" % p, func():
		DirAccess.remove_absolute(EditTarget.write_path(p))
		if p == _open:
			_open = ""
			dirty = false
			_show_none()
		_fill_mod()
		_refresh_marks(), "Remove", "Keep")


func _new_file_dialog() -> void:
	if mod_id == "":
		return
	_ask_text("NEW FILE", "Its path in the game:", "res://data/my_data.json", func(t: String): new_file(t))


## A new, empty file in the mod at res:// path `p` (a script starts as a Node script).
func new_file(p: String) -> bool:
	p = p.strip_edges()
	if not p.begins_with("res://"):
		p = "res://" + p.trim_prefix("/")
	if mod_id == "" or p.contains("..") or p.get_file() == "":
		return false
	if not EditTarget.overridden(p):
		var f := FileAccess.open(EditTarget.write_path(p), FileAccess.WRITE)
		if f == null:
			return false
		match p.get_extension():
			"gd": f.store_string("extends Node\n\n\nfunc _ready() -> void:\n\tpass\n")
			"json": f.store_string("{\n}\n")
			"gdshader": f.store_string("shader_type spatial;\n\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n")
		f.close()
	_fill_mod()
	_refresh_marks()
	open_file(p)
	return true


## The mod's own script (mod.json "main"), made if it hasn't one, and opened.
func main_script() -> void:
	if mod_id == "":
		return
	var m := Mods.info(mod_id)
	var p := str(m.get("main", ""))
	if p == "":
		p = "res://mods/%s/main.gd" % mod_id
		m["main"] = p
		Mods.save_info(m)
	if not EditTarget.overridden(p):
		var f := FileAccess.open(EditTarget.write_path(p), FileAccess.WRITE)
		f.store_string(MAIN_TEMPLATE % m["name"])
		f.close()
		_fill_mod()
	open_file(p)


const MAIN_TEMPLATE := """extends Node
## %s: the mod's own script. It runs once the game's up (a Node added to the root, after
## every autoload), and can change anything a game script can - the autoloads (Galaxy,
## PlayerData, Settings, Keybinds...), any class's static data, scenes as they come in.


func _ready() -> void:
	# (for example: every new scene, as it's made)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(_node: Node) -> void:
	pass
"""


# --- The open file -----------------------------------------------------------------

func _show_none() -> void:
	UI.clear(_view)
	_code = null
	var l := UI.label("Pick a file of the mod (right), or copy one of the game's into it (Override).", 15, UI.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_view.add_child(l)


## Opens the mod's file `p` (res:// path) in the view: text in the code editor,
## a picture shown, a model or a sound with what can be done with it.
func open_file(p: String) -> void:
	_open = p
	dirty = false
	UI.clear(_view)
	_code = null
	var ext := p.get_extension().to_lower()
	var src := EditTarget.read_path(p)
	var h := HBoxContainer.new()
	_file_title = UI.label(p, 16, NeonTheme.HEAD)
	_file_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_title.clip_text = true
	h.add_child(_file_title)
	_view.add_child(h)
	_file_note = UI.label("", 13, UI.TEXT_DIM)
	_file_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_view.add_child(_file_note)
	if ext in TEXT:
		h.add_child(_btn("Save", "save", "Ctrl+S", "Saves the file into the mod (checked first).", save_file))
		h.add_child(_btn("Revert", "undo", "", "Back to the file as last saved.", func(): open_file(p)))
		_code = _code_edit(ext)
		_code.text = FileAccess.get_file_as_string(src)
		_code.clear_undo_history()
		_code.text_changed.connect(func(): dirty = true)
		_view.add_child(_code)
		_file_note.text = check_text(p, _code.text)
	elif ext in IMAGES:
		var img := Image.new()
		var err := img.load_svg_from_string(FileAccess.get_file_as_string(src)) if ext == "svg" else img.load(src)
		if err == OK:
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if img.get_width() <= 128 else CanvasItem.TEXTURE_FILTER_LINEAR
			_view.add_child(tr)
			_file_note.text = "%d x %d px" % [img.get_width(), img.get_height()]
		h.add_child(_btn("Replace", "open", "", "Replaces the picture with an image file of yours.", func(): _replace_from_disk(p)))
	elif ext in MODELS:
		_file_note.text = "A 3D model: edit it in the mesh editor (it saves back here)."
		h.add_child(_btn("Mesh editor", "mesh", "", "Opens it in the mesh editor.", func(): open_in_mesh_editor(p)))
		h.add_child(_btn("Replace", "open", "", "Replaces the model with a .glb / .gltf file of yours.", func(): _replace_from_disk(p)))
	elif ext in SOUNDS:
		_file_note.text = "A sound."
		h.add_child(_btn("Play", "play", "", "Plays it.", func(): _play(src, ext)))
		h.add_child(_btn("Replace", "open", "", "Replaces the sound with a file of yours.", func(): _replace_from_disk(p)))
	else:
		_file_note.text = "%d bytes." % FileAccess.get_file_as_bytes(src).size()
		h.add_child(_btn("Replace", "open", "", "Replaces it with a file of yours.", func(): _replace_from_disk(p)))
	_select_open()


func open_in_mesh_editor(p: String) -> void:
	var t := tool("mesh")
	if t and t.has_method("open_file"):
		t.open_file(p)


func _code_edit(ext: String) -> CodeEdit:
	var c := CodeEdit.new()
	c.name = "Code"
	c.tooltip_text = EditorIcons.tip("The file's text", "Ctrl+S", "Edit it here; Save checks it (JSON, scripts) and writes it into the mod. Ctrl+Z undoes.")
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.gutters_draw_line_numbers = true
	c.auto_brace_completion_enabled = true
	c.highlight_current_line = true
	c.minimap_draw = true
	c.add_theme_font_size_override("font_size", 15)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
	c.add_theme_font_override("font", mono)
	var hl := CodeHighlighter.new()
	hl.number_color = Color(0.7, 0.9, 1.0)
	hl.symbol_color = Color(0.85, 0.8, 0.7)
	hl.function_color = Color(0.55, 0.85, 1.0)
	hl.member_variable_color = Color(0.9, 0.85, 0.75)
	hl.add_color_region("\"", "\"", Color(1.0, 0.8, 0.5))
	if ext in ["gd", "cfg", "tscn", "tres", "ini"]:
		hl.add_color_region("#", "", Color(0.5, 0.6, 0.55), true)
	if ext in ["gdshader", "gdshaderinc", "glsl"]:
		hl.add_color_region("//", "", Color(0.5, 0.6, 0.55), true)
	var kw := []
	match ext:
		"gd": kw = ["func", "var", "const", "if", "elif", "else", "for", "while", "match", "return", "extends", "class_name", "class",
			"static", "signal", "await", "in", "not", "and", "or", "pass", "break", "continue", "true", "false", "null", "self", "enum", "preload", "load", "super"]
		"gdshader", "gdshaderinc", "glsl": kw = ["shader_type", "render_mode", "uniform", "varying", "void", "float", "vec2", "vec3", "vec4", "int", "bool",
			"mat3", "mat4", "sampler2D", "if", "else", "for", "return", "const", "instance"]
		"json", "merge": kw = ["true", "false", "null"]
	for k in kw:
		hl.add_keyword_color(k, Color(1.0, 0.6, 0.3))
	c.syntax_highlighter = hl
	return c


## What's wrong with `text` as file `p` ("" - fine): JSON that doesn't parse, a script
## that doesn't compile.
func check_text(p: String, text: String) -> String:
	var ext := p.get_extension()
	if ext in ["json", "merge"]:
		var j := JSON.new()
		if j.parse(text) != OK:
			return "JSON error, line %d: %s" % [j.get_error_line(), j.get_error_message()]
		if ext == "merge" and not j.data is Dictionary:
			return "A merge patch must be a JSON object { ... }."
	elif ext == "gd":
		var s := GDScript.new()
		s.source_code = text
		if s.reload() != OK:
			return "The script doesn't compile - see the output (or Check) for the line."
	return ""


func save_file() -> bool:
	if _code == null or _open == "":
		return false
	var why := check_text(_open, _code.text)
	var f := FileAccess.open(EditTarget.write_path(_open), FileAccess.WRITE)
	if f == null:
		_say("Can't write " + _open)
		return false
	f.store_string(_code.text)
	f.close()
	dirty = false
	_file_note.text = why
	_say(("Saved %s - " % _open.get_file()) + (why if why != "" else "it applies when the game starts with the mod (Test in game)."))
	return true


func _replace_from_disk(p: String) -> void:
	if OS.has_feature("web"):
		_say("Not in a browser: copy the file into the mod's folder instead.")
		return
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*." + p.get_extension()]), "Replace " + p.get_file(), func(path: String):
		var to := EditTarget.write_path(p)
		var err := DirAccess.copy_absolute(path, to)
		_say(("Replaced " + p) if err == OK else ("Couldn't copy: " + error_string(err)))
		open_file(p))


func _play(src: String, ext: String) -> void:
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(_player)
	match ext:
		"ogg": _player.stream = AudioStreamOggVorbis.load_from_file(src)
		"wav": _player.stream = AudioStreamWAV.load_from_file(src)
		"mp3":
			var m := AudioStreamMP3.new()
			m.data = FileAccess.get_file_as_bytes(src)
			_player.stream = m
	_player.play()


# --- The whole mod --------------------------------------------------------------------

## Checks every file of the mod: the problems found (also shown).
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	if mod_id == "":
		return out
	if dirty:
		save_file()
	var m := Mods.info(mod_id)
	if str(m.get("main", "")) != "" and not EditTarget.overridden(str(m["main"])) and not ResourceLoader.exists(str(m["main"])):
		out.append("Its main script %s isn't there." % m["main"])
	for p in Mods.mod_files(mod_id):
		var src := EditTarget.read_path(p)
		var ext := p.get_extension()
		if ext in ["json", "merge", "gd"]:
			var why := check_text(p, FileAccess.get_file_as_string(src))
			if why != "":
				out.append("%s: %s" % [p.trim_prefix("res://"), why])
		elif ext in ["tscn", "tres"]:
			if ResourceLoader.load(src, "", ResourceLoader.CACHE_MODE_IGNORE) == null:
				out.append("%s: doesn't load" % p.trim_prefix("res://"))
		elif ext in IMAGES and ext != "svg":
			if Image.load_from_file(src) == null:
				out.append("%s: not a picture Godot reads" % p.trim_prefix("res://"))
		if ext == "merge" and not FileAccess.file_exists(p.trim_suffix(".merge")):
			out.append("%s: the game has no %s to merge into" % [p.trim_prefix("res://"), p.trim_suffix(".merge").get_file()])
	_say("Checked %d files: %s" % [Mods.mod_files(mod_id).size(), "all fine." if out.is_empty() else "; ".join(out)])
	return out


func _test() -> void:
	if mod_id == "":
		return
	if dirty:
		save_file()
	var problems := validate()
	var go := func():
		Mods.set_enabled(mod_id, true)
		Mods.restart()
	if problems.is_empty():
		go.call()
	else:
		UI.confirm(self, "TEST IN GAME", "The check found problems:\n%s\nStart the game with the mod anyway?" % "\n".join(problems), go, "Start", "Stay")


func _export() -> void:
	if mod_id == "":
		return
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.zip ; Mod (zip)"]), "Export the mod", func(path: String):
		if not path.ends_with(".zip"):
			path += ".zip"
		_say(("Saved " + path) if Mods.export_zip(mod_id, path) else ("Couldn't write " + path)))


func leave() -> void:
	_guard(func():
		EditTarget.mod_id = ""
		get_tree().change_scene_to_file(MENU))


## `then` once the open file's saved or its changes dropped (asked when there are any);
## `stay` if you stay.
func _guard(then: Callable, stay := Callable()) -> void:
	var embedded_dirty := false
	for t in _tools.values():
		if t and t.get("dirty") == true:
			embedded_dirty = true
	if not dirty and not embedded_dirty:
		then.call()
		return
	if dirty:
		UI.unsaved(self, _open.get_file(), func(): save_file(); then.call(), func(): dirty = false; then.call(), func():
			if stay.is_valid():
				stay.call())
		return
	for t in _tools.values():
		if t and t.get("dirty") == true and t.has_method("guard"):
			show_tab(TOOL_TABS.find(_tools.find_key(t)) + 1)
			t.guard(func(): _guard(then, stay))
			return
	then.call()


## (for the unsaved-changes question)
func guard(next: Callable) -> void:
	_guard(next)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed and k.keycode == KEY_S and current_tab == 0:
		save_file()
	elif k.ctrl_pressed and k.keycode == KEY_N:
		_new_mod_dialog()
	elif k.keycode == KEY_F5:
		_test()
	elif k.keycode == KEY_F1:
		EditorDocs.open(self, "mods", EditorDocs.FILE)
	elif k.keycode == KEY_ESCAPE and current_tab == 0:
		leave()
	else:
		return
	get_viewport().set_input_as_handled()


func _say(t: String) -> void:
	_status.text = t


# --- Small dialogs ----------------------------------------------------------------------

func _ask_text(title: String, prompt: String, initial: String, cb: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_child(UI.label(prompt, 15))
	var e := LineEdit.new()
	e.name = "Input"
	e.text = initial
	e.custom_minimum_size.x = 520
	box.add_child(e)
	var d := _panel_dialog(title, box, func(): cb.call(e.text))
	e.text_submitted.connect(func(_t): d.get_ok_button().pressed.emit())
	e.call_deferred("grab_focus")
	e.call_deferred("select_all")


func _panel_dialog(title: String, content: Control, on_ok: Callable) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = title
	d.add_child(content)
	d.confirmed.connect(on_ok)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


func _file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray, title: String, cb: Callable) -> void:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = filters
	_dialog.title = title
	_dialog.use_native_dialog = true
	add_child(_dialog)
	_dialog.file_selected.connect(cb)
	_dialog.popup_centered(Vector2i(900, 600))
