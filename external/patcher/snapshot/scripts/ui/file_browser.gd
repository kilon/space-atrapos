extends Control
## A full file browser for saving (and opening) files, laid out the way a 3D suite's is: places down the
## left (the game's folders, home, recent folders), a toolbar (back, forward, parent, refresh, new folder,
## the folder's path - typed in to go there -, a search, list or thumbnails), the folder's files (folders
## first; sorted by name, date or size - click a column's title), and at the foot the file name with -/+
## (its number down/up), Cancel and the action button. A name that's already there shows red: saving
## overwrites it. Enter saves (or opens the folder typed), Esc cancels, Backspace (in the list) goes up,
## double-click opens a folder or picks a file.
##   FileBrowser.open(owner, {title, action ("Save As"), dir, file, filters (["glb", "gltf"]), thumb
##   (Callable(path) -> Texture2D or null), done (Callable(path)), cancel (Callable())})
## `path` handed to `done`: res:// when it's in the game's folder, else the absolute path.

const RECENT_FILE := "user://file_browser.json"
const RECENT_MAX := 10

var title := "Save As"
var action := "Save As"
var filters: Array = ["glb", "gltf"]
var thumb := Callable()
var done := Callable()
var cancel := Callable()

var dir := "res://"
var _back: Array = []
var _fwd: Array = []
var _sort := 0   # (0 name, 1 date, 2 size)
var _desc := false
var _thumbs_mode := false
var _only_filtered := true
var _entries: Array = []   # [{name, dir: bool, time, size}] of the folder shown

var _path_le: LineEdit
var _search_le: LineEdit
var _name_le: LineEdit
var _tree: Tree
var _grid: ItemList
var _places: ItemList
var _recent: ItemList
var _status: Label
var _act_btn: Button
var _new_box: Control
var _name_style_ok: StyleBox
var _name_style_bad: StyleBoxFlat


## A browser over `owner`'s screen (its own layer); the browser node (freed when it closes).
static func open(owner: Node, opts: Dictionary) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 60
	owner.add_child(layer)
	var fb: Control = load("res://scripts/ui/file_browser.gd").new()
	fb.title = str(opts.get("title", "Save As"))
	fb.action = str(opts.get("action", "Save As"))
	fb.filters = opts.get("filters", ["glb", "gltf"])
	fb.thumb = opts.get("thumb", Callable())
	fb.done = opts.get("done", Callable())
	fb.cancel = opts.get("cancel", Callable())
	fb.set_anchors_preset(Control.PRESET_FULL_RECT)
	fb.name = "FileBrowser"
	layer.add_child(fb)
	fb._build()
	var d := str(opts.get("dir", "res://"))
	fb._go(d if DirAccess.dir_exists_absolute(d) else "res://", false)
	fb._name_le.text = str(opts.get("file", ""))
	fb._name_changed(fb._name_le.text)
	fb._name_le.grab_focus.call_deferred()
	fb._name_le.select_all.call_deferred()
	return fb


func _build() -> void:
	var box := UI.modal(self, NeonTheme.HEAD, Vector2(1120, 700))
	var head := HBoxContainer.new()
	head.add_child(UI.label(title, 24, NeonTheme.HEAD))
	box.add_child(head)
	# the toolbar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	box.add_child(bar)
	bar.add_child(_tool("back", "Back", "Alt+Left", "The folder shown before.", _go_back))
	bar.add_child(_tool("forward", "Forward", "Alt+Right", "The folder gone back from.", _go_fwd))
	bar.add_child(_tool("up", "Parent folder", "Backspace", "The folder this one is in.", _go_up))
	bar.add_child(_tool("reload", "Refresh", "", "The folder read again.", func(): _go(dir, false)))
	bar.add_child(_tool("add", "New folder", "", "A new folder in this one (you name it).", _new_folder))
	_path_le = LineEdit.new()
	_path_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_le.add_theme_font_size_override("font_size", 15)
	_path_le.tooltip_text = EditorIcons.tip("Folder", "Enter", "The folder shown - type a path and press Enter to go there.")
	_path_le.text_submitted.connect(func(t: String):
		var p := t.strip_edges()
		if DirAccess.dir_exists_absolute(p):
			_go(p)
		else:
			_say("No folder %s." % p, true))
	bar.add_child(_path_le)
	_search_le = LineEdit.new()
	_search_le.placeholder_text = "Search"
	_search_le.custom_minimum_size.x = 190
	_search_le.add_theme_font_size_override("font_size", 15)
	_search_le.clear_button_enabled = true
	_search_le.tooltip_text = EditorIcons.tip("Search", "", "Only the files and folders whose names have these letters.")
	_search_le.text_changed.connect(func(_t): _fill())
	bar.add_child(_search_le)
	var flt := _tool("mesh", "Only %s files" % ", ".join(filters.map(func(e): return "." + str(e))), "", "Show only the files that can be saved here (on), or every file (off).", Callable())
	flt.toggle_mode = true
	flt.button_pressed = true
	flt.toggled.connect(func(on: bool): _only_filtered = on; _fill())
	bar.add_child(flt)
	var tm := _tool("m_icons", "Thumbnails", "", "The files as pictures (on) or as a list with their dates and sizes (off).", Callable())
	tm.toggle_mode = true
	tm.toggled.connect(func(on: bool): _thumbs_mode = on; _fill())
	bar.add_child(tm)
	# places | files
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 210
	box.add_child(split)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 200
	side.add_theme_constant_override("separation", 6)
	split.add_child(side)
	side.add_child(UI.section("Places"))
	_places = ItemList.new()
	_places.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_places.add_theme_font_size_override("font_size", 15)
	side.add_child(_places)
	for pl in _place_list():
		var i := _places.add_item(pl[0], EditorIcons.get_icon("open"))
		_places.set_item_metadata(i, pl[1])
		_places.set_item_tooltip(i, pl[1])
	_places.item_selected.connect(func(i: int): _go(str(_places.get_item_metadata(i))))
	side.add_child(UI.section("Recent"))
	_recent = ItemList.new()
	_recent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recent.add_theme_font_size_override("font_size", 15)
	side.add_child(_recent)
	for d in _recent_dirs():
		var i := _recent.add_item(_short(d), EditorIcons.get_icon("open"))
		_recent.set_item_metadata(i, d)
		_recent.set_item_tooltip(i, d)
	_recent.item_selected.connect(func(i: int): _go(str(_recent.get_item_metadata(i))))
	var files := VBoxContainer.new()
	files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(files)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.add_theme_font_size_override("font_size", 15)
	_tree.add_theme_font_size_override("title_button_font_size", 15)
	_tree.set_column_title(0, "Name")
	_tree.set_column_title(1, "Date modified")
	_tree.set_column_title(2, "Size")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(1, 190)
	_tree.set_column_custom_minimum_width(2, 110)
	_tree.column_title_clicked.connect(func(col: int, _mb: int):
		_desc = (not _desc) if col == _sort else false
		_sort = col
		_fill())
	_tree.item_selected.connect(func():
		var it := _tree.get_selected()
		if it:
			_pick(it.get_metadata(0), false))
	_tree.item_activated.connect(func():
		var it := _tree.get_selected()
		if it:
			_pick(it.get_metadata(0), true))
	_tree.gui_input.connect(_list_key)
	files.add_child(_tree)
	_grid = ItemList.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.max_columns = 0
	_grid.icon_mode = ItemList.ICON_MODE_TOP
	_grid.fixed_icon_size = Vector2i(112, 112)
	_grid.fixed_column_width = 140
	_grid.same_column_width = true
	_grid.add_theme_font_size_override("font_size", 14)
	_grid.visible = false
	_grid.item_selected.connect(func(i: int): _pick(_grid.get_item_metadata(i), false))
	_grid.item_activated.connect(func(i: int): _pick(_grid.get_item_metadata(i), true))
	_grid.gui_input.connect(_list_key)
	files.add_child(_grid)
	# the new folder's name (shown by New folder)
	_new_box = HBoxContainer.new()
	_new_box.visible = false
	(_new_box as HBoxContainer).add_theme_constant_override("separation", 8)
	files.add_child(_new_box)
	_new_box.add_child(UI.label("New folder:", 15, UI.TEXT_DIM))
	var nf := LineEdit.new()
	nf.name = "NewName"
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nf.add_theme_font_size_override("font_size", 15)
	nf.text_submitted.connect(func(_t): _make_folder())
	_new_box.add_child(nf)
	_new_box.add_child(UI.button("Create", _make_folder, 15))
	_new_box.add_child(UI.button("Cancel", func(): _new_box.visible = false, 15))
	# the file's name, and the buttons
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	box.add_child(foot)
	_name_le = LineEdit.new()
	_name_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_le.add_theme_font_size_override("font_size", 16)
	_name_le.placeholder_text = "File name"
	_name_le.tooltip_text = EditorIcons.tip("File name", "Enter", "The name to save under, in the folder shown (red: a file of that name is there - saving\noverwrites it).")
	_name_le.text_changed.connect(_name_changed)
	_name_le.text_submitted.connect(func(_t): _confirm())
	foot.add_child(_name_le)
	_name_style_ok = _name_le.get_theme_stylebox("normal")
	_name_style_bad = StyleBoxFlat.new()
	_name_style_bad.bg_color = Color(0.45, 0.06, 0.04, 0.9)
	_name_style_bad.border_color = Color(1.0, 0.35, 0.25)
	_name_style_bad.set_border_width_all(1)
	_name_style_bad.set_corner_radius_all(3)
	_name_style_bad.content_margin_left = 8
	_name_style_bad.content_margin_right = 8
	foot.add_child(_tool("remove", "Decrease the number", "Ctrl+Minus", "The number at the end of the name one less.", func(): _bump(-1)))
	foot.add_child(_tool("add", "Increase the number", "Ctrl+Plus", "The number at the end of the name one more (a 1 added if it has none).", func(): _bump(1)))
	foot.add_child(UI.button("Cancel", _cancel, 16))
	_act_btn = UI.button(action, _confirm, 16)
	_act_btn.name = "Action"
	foot.add_child(_act_btn)
	_status = UI.label("", 14, UI.TEXT_DIM)
	box.add_child(_status)


func _tool(icon: String, name: String, keys: String, body: String, fn: Callable) -> Button:
	var b := Button.new()
	b.icon = EditorIcons.get_icon(icon)
	b.expand_icon = false
	b.custom_minimum_size = Vector2(36, 34)
	b.tooltip_text = EditorIcons.tip(name, keys, body)
	b.focus_mode = Control.FOCUS_NONE
	if fn.is_valid():
		b.pressed.connect(fn)
	return b


## [label, folder] of the places down the side.
func _place_list() -> Array:
	var out := [["Game", "res://"]]
	for d in [["Models", "models"], ["Art", "art"], ["Overrides", "art/overrides"]]:
		if DirAccess.dir_exists_absolute("res://" + d[1]):
			out.append([d[0], "res://" + d[1]])
	var home := OS.get_environment("HOME") if OS.get_environment("HOME") != "" else OS.get_environment("USERPROFILE")
	if home != "":
		out.append(["Home", home])
	for k in [OS.SYSTEM_DIR_DESKTOP, OS.SYSTEM_DIR_DOCUMENTS, OS.SYSTEM_DIR_DOWNLOADS]:
		var p := OS.get_system_dir(k)
		if p != "" and DirAccess.dir_exists_absolute(p):
			out.append([p.get_file(), p])
	return out


static func _recent_dirs() -> Array:
	if not FileAccess.file_exists(RECENT_FILE):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(RECENT_FILE))
	return (d as Array).filter(func(x): return DirAccess.dir_exists_absolute(str(x))) if d is Array else []


static func _remember(d: String) -> void:
	var r := _recent_dirs()
	r.erase(d)
	r.push_front(d)
	r.resize(mini(r.size(), RECENT_MAX))
	var f := FileAccess.open(RECENT_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r))


static func _short(d: String) -> String:
	return d if d.length() < 28 else "..." + d.right(25)


## Shows folder `d` (`push`: the one left goes on the Back list).
func _go(d: String, push := true) -> void:
	d = _norm(d)
	if push and d != dir:
		_back.append(dir)
		_fwd.clear()
	dir = d
	_path_le.text = dir
	_new_box.visible = false
	_read()
	_fill()
	_name_changed(_name_le.text)


func _go_back() -> void:
	if _back.is_empty():
		return
	_fwd.append(dir)
	_go(_back.pop_back(), false)


func _go_fwd() -> void:
	if _fwd.is_empty():
		return
	_back.append(dir)
	_go(_fwd.pop_back(), false)


func _go_up() -> void:
	if dir == "res://" or dir == "/" or dir.ends_with(":/"):
		return
	var up := dir.trim_suffix("/").get_base_dir()
	if up == "res:":
		up = "res://"
	_go(up if up != "" else "/")


## A path in one form: res:// inside the game's folder, else absolute; no trailing slash (but a root).
static func _norm(d: String) -> String:
	var loc := ProjectSettings.localize_path(d)
	if loc.begins_with("res://"):
		d = loc
	if d.length() > 1 and d.ends_with("/") and d != "res://" and not d.ends_with(":/"):
		d = d.trim_suffix("/")
	return d


func _read() -> void:
	_entries = []
	var da := DirAccess.open(dir)
	if da == null:
		_say("Can't read %s." % dir, true)
		return
	da.include_hidden = false
	for d in da.get_directories():
		if d.begins_with(".") or (dir == "res://" and d == ".godot"):
			continue
		_entries.append({"name": d, "dir": true, "time": FileAccess.get_modified_time(dir.path_join(d)), "size": -1})
	for f in da.get_files():
		if f.begins_with(".") or f.get_extension() in ["import", "uid"]:
			continue
		var full := dir.path_join(f)
		var fa := FileAccess.open(full, FileAccess.READ)
		_entries.append({"name": f, "dir": false, "time": FileAccess.get_modified_time(full), "size": fa.get_length() if fa else 0})
	_say("")


## The folder's entries as they're filtered and sorted, into the list or the thumbnails.
func _fill() -> void:
	var q := _search_le.text.strip_edges().to_lower()
	var show := _entries.filter(func(e):
		if q != "" and not str(e["name"]).to_lower().contains(q):
			return false
		return bool(e["dir"]) or not _only_filtered or filters.is_empty() or str(e["name"]).get_extension().to_lower() in filters)
	var key: String = ["name", "time", "size"][_sort]
	show.sort_custom(func(a, b):
		if bool(a["dir"]) != bool(b["dir"]):
			return bool(a["dir"])
		var x = str(a["name"]).to_lower() if key == "name" else a[key]
		var y = str(b["name"]).to_lower() if key == "name" else b[key]
		if x == y:
			return str(a["name"]) < str(b["name"])
		return (x > y) if _desc else (x < y))
	_tree.visible = not _thumbs_mode
	_grid.visible = _thumbs_mode
	for c in 3:
		_tree.set_column_title(c, ["Name", "Date modified", "Size"][c] + ((" v" if _desc else " ^") if c == _sort else ""))
	if _thumbs_mode:
		_grid.clear()
		for e in show:
			var full := dir.path_join(str(e["name"]))
			var tex: Texture2D = null
			if not bool(e["dir"]) and thumb.is_valid():
				tex = thumb.call(full)
			var i := _grid.add_item(str(e["name"]), tex if tex else EditorIcons.get_icon("open" if bool(e["dir"]) else "mesh"))
			_grid.set_item_metadata(i, e)
			_grid.set_item_tooltip(i, full)
		return
	_tree.clear()
	var root := _tree.create_item()
	for e in show:
		var it := _tree.create_item(root)
		it.set_text(0, str(e["name"]))
		it.set_icon(0, EditorIcons.get_icon("open" if bool(e["dir"]) else "mesh"))
		it.set_icon_max_width(0, 20)
		it.set_text(1, Time.get_datetime_string_from_unix_time(int(e["time"]), true) if int(e["time"]) > 0 else "")
		it.set_text(2, "" if bool(e["dir"]) else _size_text(int(e["size"])))
		it.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		it.set_metadata(0, e)
		it.set_tooltip_text(0, dir.path_join(str(e["name"])))
		if not bool(e["dir"]) and str(e["name"]) == _with_ext(_name_le.text.strip_edges()):
			it.select(0)


static func _size_text(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	if n < 1024 * 1024:
		return "%.1f KB" % (n / 1024.0)
	return "%.1f MB" % (n / 1048576.0)


## An entry clicked (`open`: double-clicked): a folder entered (double-click), a file's name taken (and
## saved under, double-click).
func _pick(e: Dictionary, open: bool) -> void:
	if bool(e["dir"]):
		if open:
			_go(dir.path_join(str(e["name"])))
		return
	_name_le.text = str(e["name"])
	_name_changed(_name_le.text)
	if open:
		_confirm()


func _list_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_BACKSPACE:
		_go_up()
		get_viewport().set_input_as_handled()


func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	var k := ev as InputEventKey
	if k.keycode == KEY_ESCAPE:
		_cancel()
	elif k.alt_pressed and k.keycode == KEY_LEFT:
		_go_back()
	elif k.alt_pressed and k.keycode == KEY_RIGHT:
		_go_fwd()
	elif k.ctrl_pressed and k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		_bump(-1)
	elif k.ctrl_pressed and k.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]:
		_bump(1)
	else:
		return
	get_viewport().set_input_as_handled()


## The name with the first filter's extension if it has none of them.
func _with_ext(n: String) -> String:
	if n == "" or filters.is_empty() or n.get_extension().to_lower() in filters:
		return n
	return n + "." + str(filters[0])


## The name's number at its end one up or down ("chair" + -> "chair1", "chair_009" + -> "chair_010").
func _bump(by: int) -> void:
	var n := _name_le.text.strip_edges()
	var ext := n.get_extension() if n.get_extension().to_lower() in filters else ""
	var base := n.get_basename() if ext != "" else n
	var re := RegEx.create_from_string("^(.*?)(\\d+)$")
	var m := re.search(base)
	if m:
		var digits := m.get_string(2)
		var v := maxi(0, int(digits) + by)
		base = m.get_string(1) + str(v).pad_zeros(digits.length())
	elif by > 0:
		base += "1"
	_name_le.text = base + ("." + ext if ext != "" else "")
	_name_le.caret_column = _name_le.text.length()
	_name_changed(_name_le.text)


func _name_changed(t: String) -> void:
	var n := _with_ext(t.strip_edges())
	var there := n != "" and FileAccess.file_exists(dir.path_join(n))
	_name_le.add_theme_stylebox_override("normal", _name_style_bad if there else _name_style_ok)
	_name_le.add_theme_stylebox_override("focus", _name_style_bad if there else _name_le.get_theme_stylebox("focus", "LineEdit"))
	_act_btn.disabled = n == "" or n.contains("/") or n.contains("\\")
	_say("%s is there - %s overwrites it." % [n, action] if there else "")


func _confirm() -> void:
	var n := _with_ext(_name_le.text.strip_edges())
	if n == "" or n.contains("/") or n.contains("\\"):
		_say("Give it a name.", true)
		return
	if dir.begins_with("res://.godot") or dir.begins_with("res://.git"):
		_say("Not there: that folder is the engine's.", true)
		return
	var full := _norm(dir).path_join(n)
	_remember(_norm(dir))
	var fn := done
	_close()
	if fn.is_valid():
		fn.call(full)


func _cancel() -> void:
	var fn := cancel
	_close()
	if fn.is_valid():
		fn.call()


func _close() -> void:
	set_process_input(false)
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()


func _new_folder() -> void:
	_new_box.visible = true
	var le: LineEdit = _new_box.get_node("NewName")
	le.text = "New Folder"
	le.grab_focus()
	le.select_all()


func _make_folder() -> void:
	var le: LineEdit = _new_box.get_node("NewName")
	var n := le.text.strip_edges()
	if n == "" or n.contains("/"):
		_say("Give the folder a name.", true)
		return
	var full := dir.path_join(n)
	if DirAccess.dir_exists_absolute(full):
		_say("%s is there already." % n, true)
		return
	var err := DirAccess.make_dir_recursive_absolute(full)
	if err != OK:
		_say("Couldn't make %s (%s)." % [n, error_string(err)], true)
		return
	_new_box.visible = false
	_go(full)


func _say(t: String, bad := false) -> void:
	if _status == null:
		return
	_status.text = t
	_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if bad or t.contains("overwrites") else UI.TEXT_DIM)
