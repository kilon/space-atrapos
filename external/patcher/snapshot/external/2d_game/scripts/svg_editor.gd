extends Control
## The SVG Editor (Editor > SVG Editor, F6): a vector drawing program in the
## spirit of Inkscape. Tools: select / transform (move, scale, rotate),
## nodes (edit paths: drag nodes and handles, add, delete, smooth / sharp),
## rectangle, ellipse, star / polygon, pen (Bezier), pencil (freehand), text
## and colour picker. Fill, stroke, opacity, z-order, align, flip, an objects
## list with hide / lock, undo / redo, copy / paste, grid and snapping.
## Files are real SVG (open, save) and the drawing exports to PNG at any
## scale. The document is SvgDoc; it is drawn by Godot's SVG rasteriser,
## so what you see is exactly what's exported.

const EDITOR_SCENE := "res://editor.tscn"
const ACCENT := Color(0.55, 0.92, 0.62)
const DIR := "res://art/svg/"
const HANDLE := 9.0
## [id, icon, name, key, help]
const TOOLS := [
	["select", "select", "Select and transform", "S", "Click a shape to select it (Shift adds), drag to move it; drag on empty space for a box selection.\nThe handles scale it (Ctrl / Shift: keep proportions); the round handle rotates it (Ctrl: 15° steps).\nDouble-click a shape to edit its nodes. Arrows nudge (Shift: 10 px)."],
	["node", "node", "Edit nodes", "N", "Edit a path's nodes: drag nodes or their handles (Shift adds to the selection; drag empty space\nfor a box). Double-click a segment to add a node; Delete removes nodes. Rectangles, ellipses,\nstars and text become paths when you edit their nodes."],
	["rect", "rect", "Rectangle", "R", "Drag to draw a rectangle (Ctrl: a square). Round its corners in the panel."],
	["ellipse", "ellipse", "Ellipse", "E", "Drag to draw an ellipse (Ctrl: a circle)."],
	["star", "star_tool", "Star and polygon", "*", "Drag from the centre to draw a star or polygon (Ctrl: snap the angle).\nSet the corners, the spoke ratio and star / polygon in the panel."],
	["pen", "pen", "Pen (Bezier)", "B", "Click to add sharp nodes, click-and-drag for smooth (curved) ones. Click the first node to close\nthe path; Enter, right-click or a double-click finishes it; Backspace removes the last node; Esc cancels."],
	["pencil", "pencil", "Pencil (freehand)", "P", "Drag to draw freehand: the line is smoothed into a curve. End near the start to close it."],
	["text", "text", "Text", "T", "Click to place text, then type it in the panel (size, bold). Click existing text to edit it."],
	["picker", "picker", "Colour picker", "D", "Click a shape to copy its fill onto the selection (Shift: its stroke too).\nWith nothing selected it sets the colour new shapes are drawn with."],
]

var doc := SvgDoc.new()
var file_path := ""
var dirty := false
var tool := "select"
var sel: Array = []               # selected shapes (references into doc.shapes)
var node_sel: Array = []          # selected nodes: [shape, sub index, node index]
var zoom := 1.0
var pan := Vector2(60, 40)
var show_grid := true
var snap := false
var grid := 10.0
## The style new shapes are drawn with (follows the last edited style).
var style := {"fill": Color(0.35, 0.6, 0.95), "stroke": Color(0.08, 0.1, 0.16), "stroke_width": 2.0, "opacity": 1.0}
var star_n := 5
var star_ratio := 0.45
var star_on := true

var _undo: Array = []
var _redo: Array = []
var _undo_key := ""
var _undo_time := 0
var _clip: Array = []

# Interaction.
var _drag := ""                   # move, scale, rotate, band, create, node, handle, pan, pencil, pen
var _press := Vector2.ZERO        # page point of the press
var _press_screen := Vector2.ZERO
var _orig: Array = []             # selected shapes' transforms (or node positions) at the press
var _bbox0 := Rect2()
var _handle := -1
var _handle_side := ""            # "i" / "o" for a node handle
var _creating: Dictionary = {}
var _pen: Dictionary = {}
var _pencil := PackedVector2Array()
var _mouse := Vector2.ZERO        # page coordinates
var _mouse_screen := Vector2.ZERO
var _hover: Dictionary = {}

# UI.
var _canvas: Control
var _tex: ImageTexture
var _checker: ImageTexture
var _render_dirty := true
var _panel: VBoxContainer
var _objects: Tree
var _listing := false        # (refreshing the list: ignore its selection signals)
var _status: Label
var _coords: Label
var _title: Label
var _tool_btns := {}
var _text_edit: LineEdit


func _ready() -> void:
	NeonTheme.set_empire("")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var ci := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for x in 16:
		for y in 16:
			ci.set_pixel(x, y, Color(0.86, 0.86, 0.88) if (x < 8) == (y < 8) else Color(0.97, 0.97, 0.98))
	_checker = ImageTexture.create_from_image(ci)
	_build()
	_new_doc(false)
	PinTips.install(self, "svg")
	# Opened from the command line with a file:  ... -- --svg=res://art/svg/x.svg
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--svg="):
			await get_tree().process_frame
			await get_tree().process_frame
			open_file(a.substr(6))


# --- Layout ----------------------------------------------------------------------------

func _build() -> void:
	var root := TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "svg", func(id): TalosNav.go(get_tree(), id, _guard))
	var hn := TalosNav.header("SVG", "", ACCENT)
	var header: HBoxContainer = hn[0]
	_title = hn[1]
	header.add_child(_btn("New", "new", "Ctrl+N", "Starts a new, empty drawing (asks about unsaved changes).", func(): _guard(func(): _new_doc(true))))
	header.add_child(_btn("Open", "open", "Ctrl+O", "Opens an SVG file (shapes, paths, text, groups and their styles are read;\ngradients become grey).", func(): _guard(_open_dialog)))
	header.add_child(_btn("Save", "save", "Ctrl+S", "Saves the drawing as an SVG file (asks for a name the first time).", _save))
	header.add_child(_btn("Save as", "duplicate", "Ctrl+Shift+S", "Saves the drawing under a new name.", _save_as))
	header.add_child(_btn("Export PNG", "export", "Ctrl+E", "Exports the page, the whole drawing or the selection as a PNG image,\nat any scale, with a transparent or a coloured background.", _export_dialog))
	header.add_child(_btn("Undo", "undo", "Ctrl+Z", "Undoes the last change.", undo))
	header.add_child(_btn("Redo", "redo", "Ctrl+Y / Ctrl+Shift+Z", "Redoes what was undone.", redo))
	header.add_child(_btn("Zoom to page", "fit_all", "5", "Fits the whole page in the view (1: 100%; the wheel zooms at the mouse;\nmiddle drag or Space + drag pans).", zoom_fit))
	var g := _btn("Grid", "grid", "#", "Shows or hides the grid.", func(): show_grid = not show_grid; _canvas.queue_redraw())
	header.add_child(g)
	var sn := _btn("Snap to grid", "snap", "%", "Snaps drawing, moving and node editing to the grid.", func(): snap = not snap; _set_status(); _canvas.queue_redraw())
	header.add_child(sn)
	header.add_child(EditorIcons.docs_button(self, "svg"))
	root.add_child(header)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	# Tools.
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	body.add_child(tools)
	for t in TOOLS:
		var b := _btn(t[2], t[1], t[3], t[4], set_tool.bind(t[0]))
		b.toggle_mode = true
		_tool_btns[t[0]] = b
		tools.add_child(b)
	# Canvas.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.focus_mode = Control.FOCUS_CLICK
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(func(): _render_dirty = true)
	mid.add_child(_canvas)
	var bar := HBoxContainer.new()
	mid.add_child(bar)
	_status = UI.label("", 13, UI.TEXT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bar.add_child(_status)
	_coords = UI.label("", 13, UI.TEXT_DIM)
	bar.add_child(_coords)
	# Right: properties and objects.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 5)
	scroll.add_child(_panel)
	right.add_child(UI.label("OBJECTS  (top first)", 14, ACCENT))
	_objects = Tree.new()
	_objects.custom_minimum_size = Vector2(0, 220)
	_objects.size_flags_vertical = Control.SIZE_EXPAND_FILL   # (shares the column's height with the properties)
	_objects.size_flags_stretch_ratio = 0.7
	_objects.hide_root = true
	_objects.select_mode = Tree.SELECT_MULTI
	_objects.multi_selected.connect(func(_it, _c, _s):
		if not _listing:
			_select_from_list.call_deferred())
	_objects.button_clicked.connect(_on_object_button)
	_objects.tooltip_text = EditorIcons.tip("Objects", "", "Every shape, top first. Click to select (Ctrl / Shift: several).\nThe eye hides or shows a shape (hidden ones aren't exported); the padlock locks it\n(locked shapes can't be clicked on the canvas). Shift+click either: every selected object.")
	right.add_child(_objects)
	var ob := HBoxContainer.new()
	right.add_child(ob)
	ob.add_child(_small("Hide", "Hides or shows the selected objects (hidden ones aren't exported).", _toggle_hidden))
	ob.add_child(_small("Lock", "Locks or unlocks the selected objects (locked ones can't be clicked on the canvas).", _toggle_locked))
	ob.add_child(_small("Up", "Raises the selection one step (Page Up).", func(): arrange(1)))
	ob.add_child(_small("Down", "Lowers the selection one step (Page Down).", func(): arrange(-1)))


func _btn(name: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	return EditorIcons.dress(b, icon, EditorIcons.tip(name, keys, help))


func _small(text: String, help: String, cb: Callable) -> Button:
	var b := UI.button(text, cb, 13)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = help
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


# --- Document, files ---------------------------------------------------------------------

func _new_doc(push := true) -> void:
	if push:
		_push_undo("new")
	doc = SvgDoc.new()
	file_path = ""
	dirty = false
	sel = []
	node_sel = []
	_undo = [] if not push else _undo
	call_deferred("zoom_fit")
	_changed(true)
	dirty = false
	_update_title()


func _update_title() -> void:
	_title.text = "  %s%s  ·  %d x %d px" % [file_path.get_file() if file_path != "" else "untitled.svg", " *" if dirty else "", doc.width, doc.height]


func _guard(then: Callable) -> void:
	if dirty:
		UI.unsaved(self, "The drawing", _save, Callable(), then)
	else:
		then.call()


func _file_dialog(mode: FileDialog.FileMode, filter: String, cb: Callable, file_name := "") -> void:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([filter])
	fd.current_dir = ProjectSettings.globalize_path(DIR) if file_path == "" else file_path.get_base_dir()
	if file_name != "":
		fd.current_file = file_name
	fd.use_native_dialog = false
	fd.file_selected.connect(func(p): cb.call(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(1000, 640))


func _open_dialog() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.svg ; SVG drawings", open_file)


func open_file(p: String) -> bool:
	var text := FileAccess.get_file_as_string(p)
	var d := SvgDoc.new()
	if text == "" or not d.load_svg(text):
		_set_status("Couldn't read " + p.get_file())
		return false
	doc = d
	file_path = p
	sel = []
	node_sel = []
	_undo = []
	_redo = []
	_changed(true)
	dirty = false
	_update_title()
	zoom_fit()
	_set_status("Opened %s: %d objects." % [p.get_file(), doc.shapes.size()])
	return true


func _save() -> void:
	if file_path == "":
		_save_as()
	else:
		save_file(file_path)


func _save_as() -> void:
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.svg ; SVG drawings", save_file, file_path.get_file() if file_path != "" else "drawing.svg")


func save_file(p: String) -> bool:
	if not p.ends_with(".svg"):
		p += ".svg"
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		_set_status("Couldn't write " + p)
		return false
	f.store_string(doc.to_svg(false))
	f.close()
	file_path = p
	dirty = false
	_update_title()
	_set_status("Saved " + p.get_file())
	return true


## Export PNG: area (page, drawing, selection), scale, background.
func _export_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Export PNG"
	dlg.ok_button_text = "Export..."
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	dlg.add_child(v)
	var area := OptionButton.new()
	for a in ["The page", "The whole drawing", "The selection"]:
		area.add_item(a)
	area.selected = 0
	v.add_child(_row("Area", area))
	var sc := SpinBox.new()
	sc.min_value = 0.05
	sc.max_value = 16.0
	sc.step = 0.05
	sc.value = 1.0
	sc.suffix = "x"
	v.add_child(_row("Scale", sc))
	var px := UI.label("", 14, UI.TEXT_DIM)
	v.add_child(px)
	var transparent := CheckBox.new()
	transparent.text = "Transparent background"
	transparent.button_pressed = doc.background == null
	v.add_child(transparent)
	var upd := func(_x = null):
		var r := export_area(area.selected)
		px.text = "%d x %d pixels" % [roundi(r.size.x * sc.value), roundi(r.size.y * sc.value)]
	area.item_selected.connect(upd)
	sc.value_changed.connect(upd)
	upd.call()
	dlg.confirmed.connect(func():
		var a: int = area.selected
		var s: float = sc.value
		var bg: bool = not transparent.button_pressed
		var name := (file_path.get_file().get_basename() if file_path != "" else "drawing") + ".png"
		_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.png ; PNG images", func(p): export_png(p, s, a, bg), name)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## The page area an export covers: 0 page, 1 the drawing, 2 the selection.
func export_area(which: int) -> Rect2:
	if which == 1 or (which == 2 and not sel.is_empty()):
		var r := _bounds_of(doc.shapes.filter(func(s): return not s["hidden"]) if which == 1 else sel)
		if r.size.x > 0.0 and r.size.y > 0.0:
			return r.grow(2.0)
	return Rect2(0, 0, doc.width, doc.height)


func export_png(p: String, scale := 1.0, which := 0, background := true) -> bool:
	if not p.ends_with(".png"):
		p += ".png"
	var r := export_area(which)
	var img := doc.render(scale, r, background)
	if img == null or img.save_png(p) != OK:
		_set_status("Couldn't export " + p)
		return false
	_set_status("Exported %s (%d x %d px)" % [p.get_file(), img.get_width(), img.get_height()])
	return true


func _back() -> void:
	TalosNav.go(get_tree(), "menu", _guard)   # (Esc: as the rail's Exit)


## Asks about unsaved changes (save / discard / stay), then `then` (Talos's exit).
func guard(then: Callable) -> void:
	_guard(then)


# --- Undo --------------------------------------------------------------------------------

## Remembers the document before a change. Changes with the same `key`
## less than a second apart (a slider being dragged) are one step.
func _push_undo(key := "") -> void:
	var now := Time.get_ticks_msec()
	if key != "" and key == _undo_key and now - _undo_time < 1000:
		_undo_time = now
		return
	_undo_key = key
	_undo_time = now
	_undo.append(_snapshot())
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()


func _snapshot() -> Dictionary:
	return {"shapes": doc.shapes.duplicate(true), "w": doc.width, "h": doc.height, "bg": doc.background,
		"sel": sel.map(func(s): return _index(s))}


func _restore(s: Dictionary) -> void:
	doc.shapes = s["shapes"].duplicate(true)
	doc.width = s["w"]
	doc.height = s["h"]
	doc.background = s["bg"]
	sel = []
	for i in s["sel"]:
		if i >= 0 and i < doc.shapes.size():
			sel.append(doc.shapes[i])
	node_sel = []
	_pen = {}
	_creating = {}
	_undo_key = ""
	_changed(true)


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())


## Something changed: redraw; `structure` also refreshes the panel and list.
func _changed(structure := false) -> void:
	dirty = true
	_render_dirty = true
	if _canvas:
		_canvas.queue_redraw()
	if structure:
		_refresh_objects()
		_rebuild_panel()
	if _title:
		_update_title()


func _index(sh: Dictionary) -> int:
	for i in doc.shapes.size():
		if is_same(doc.shapes[i], sh):
			return i
	return -1


func _is_sel(sh: Dictionary) -> bool:
	for s in sel:
		if is_same(s, sh):
			return true
	return false


# --- View ------------------------------------------------------------------------------

func _to_page(screen: Vector2) -> Vector2:
	return (screen - pan) / zoom


func _to_screen(page: Vector2) -> Vector2:
	return page * zoom + pan


func zoom_fit() -> void:
	if _canvas == null or _canvas.size.x < 10:
		return
	zoom = minf((_canvas.size.x - 60) / doc.width, (_canvas.size.y - 60) / doc.height)
	pan = (_canvas.size - Vector2(doc.width, doc.height) * zoom) / 2.0
	_render_dirty = true
	_canvas.queue_redraw()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := _to_page(screen)
	zoom = clampf(zoom * factor, 0.02, 64.0)
	pan = screen - before * zoom
	_render_dirty = true
	_canvas.queue_redraw()


func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2(grid, grid)) if snap else p


func _process(_delta: float) -> void:
	if _render_dirty and _canvas and _canvas.size.x > 2 and _canvas.size.y > 2:
		_render_dirty = false
		var view := Rect2(_to_page(Vector2.ZERO), _canvas.size / zoom)
		var img := Image.new()
		if img.load_svg_from_string(doc.to_svg(true, view, _canvas.size, false), 1.0) == OK:
			if _tex and Vector2i(_tex.get_size()) == img.get_size():
				_tex.update(img)
			else:
				_tex = ImageTexture.create_from_image(img)
		_canvas.queue_redraw()


func _draw_canvas() -> void:
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.12, 0.13, 0.16))
	var page := Rect2(_to_screen(Vector2.ZERO), Vector2(doc.width, doc.height) * zoom)
	c.draw_rect(Rect2(page.position + Vector2(5, 5), page.size).grow(1), Color(0, 0, 0, 0.4))
	if doc.background != null:
		c.draw_rect(page, doc.background)
	else:
		c.draw_texture_rect(_checker, page, true)
	if show_grid and grid * zoom >= 6.0:
		var vis := page.intersection(Rect2(Vector2.ZERO, c.size))
		var col := Color(0.3, 0.45, 0.8, 0.18)
		var x0 := ceilf(_to_page(vis.position).x / grid) * grid
		var x := x0
		while _to_screen(Vector2(x, 0)).x < vis.end.x:
			var sx := _to_screen(Vector2(x, 0)).x
			c.draw_line(Vector2(sx, vis.position.y), Vector2(sx, vis.end.y), col)
			x += grid
		var y := ceilf(_to_page(vis.position).y / grid) * grid
		while _to_screen(Vector2(0, y)).y < vis.end.y:
			var sy := _to_screen(Vector2(0, y)).y
			c.draw_line(Vector2(vis.position.x, sy), Vector2(vis.end.x, sy), col)
			y += grid
	if _tex:
		c.draw_texture(_tex, Vector2.ZERO)
	c.draw_rect(page, Color(0.45, 0.5, 0.62), false, 1.0)
	# Hover outline.
	if not _hover.is_empty() and not _is_sel(_hover) and _drag == "":
		_outline(_hover, Color(0.4, 0.8, 1.0, 0.8))
	# Selection.
	for s in sel:
		if tool == "node" or sel.size() > 1:
			_outline(s, Color(0.3, 0.7, 1.0, 0.55))
	if tool == "select" and not sel.is_empty():
		var r := _sel_screen_rect()
		_dashed_rect(r, Color(0.1, 0.1, 0.12), Color(1, 1, 1))
		for i in 8:
			var h := _handle_pos(r, i)
			c.draw_rect(Rect2(h - Vector2.ONE * HANDLE / 2.0, Vector2.ONE * HANDLE), Color(0.95, 0.97, 1.0))
			c.draw_rect(Rect2(h - Vector2.ONE * HANDLE / 2.0, Vector2.ONE * HANDLE), Color(0.1, 0.2, 0.4), false, 1.0)
		var rh := _handle_pos(r, 8)
		c.draw_line(Vector2(r.get_center().x, r.position.y), rh, Color(1, 1, 1, 0.6))
		c.draw_circle(rh, 5.5, Color(1.0, 0.8, 0.3))
		c.draw_arc(rh, 5.5, 0, TAU, 16, Color(0.2, 0.15, 0.05), 1.0)
	if tool == "node":
		_draw_nodes()
	if _drag == "band":
		var r := Rect2(_press_screen, Vector2.ZERO).expand(_mouse_screen)
		c.draw_rect(r, Color(0.4, 0.7, 1.0, 0.12))
		_dashed_rect(r, Color(0.2, 0.5, 1.0), Color(1, 1, 1))
	if _drag == "pencil" and _pencil.size() > 1:
		var pts := PackedVector2Array()
		for p in _pencil:
			pts.append(_to_screen(p))
		c.draw_polyline(pts, Color(1.0, 0.3, 0.3), 1.5, true)
	if tool == "pen" and not _pen.is_empty():
		var ns: Array = _pen["subs"][0]["nodes"]
		var last: Dictionary = ns[-1]
		if _drag == "":
			var pts := PackedVector2Array([_to_screen(last["p"])])
			var tmp := PackedVector2Array([last["p"]])
			SvgDoc.flatten_seg(last["p"], last["o"], _mouse, _mouse, tmp)
			for p in tmp:
				pts.append(_to_screen(p))
			c.draw_polyline(pts, Color(1.0, 0.35, 0.3), 1.5, true)
		for k in ns.size():
			var p := _to_screen(ns[k]["p"])
			c.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.6, 0.2) if k == 0 else Color.WHITE)
		if not (last["o"] as Vector2).is_equal_approx(last["p"]):
			for h in [last["i"], last["o"]]:
				c.draw_line(_to_screen(last["p"]), _to_screen(h), Color(0.5, 0.8, 1.0))
				c.draw_circle(_to_screen(h), 3.5, Color(0.5, 0.8, 1.0))


func _outline(sh: Dictionary, col: Color) -> void:
	for pl in SvgDoc.polylines(sh, 1.5 / zoom):
		var pts := PackedVector2Array()
		for p in pl[0]:
			pts.append(_to_screen(p))
		if pl[1] and pts.size() > 1:
			pts.append(pts[0])
		if pts.size() > 1:
			_canvas.draw_polyline(pts, col, 1.2, true)


func _dashed_rect(r: Rect2, a: Color, b: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for k in 4:
		_canvas.draw_line(pts[k], pts[k + 1], a, 1.0)
		_canvas.draw_dashed_line(pts[k], pts[k + 1], b, 1.0, 4.0)


func _draw_nodes() -> void:
	for sh in sel:
		if sh["type"] != "path":
			continue
		var xf: Transform2D = sh["xf"]
		var subs: Array = sh["subs"]
		for si in subs.size():
			var ns: Array = subs[si]["nodes"]
			for ni in ns.size():
				var n: Dictionary = ns[ni]
				var p := _to_screen(xf * n["p"])
				var on := _node_selected(sh, si, ni)
				if on:
					for h in ["i", "o"]:
						if not (n[h] as Vector2).is_equal_approx(n["p"]):
							var hp := _to_screen(xf * n[h])
							_canvas.draw_line(p, hp, Color(0.5, 0.8, 1.0, 0.9))
							_canvas.draw_circle(hp, 4.0, Color(0.5, 0.8, 1.0))
				var r := Rect2(p - Vector2(4.5, 4.5), Vector2(9, 9))
				var col := Color(1.0, 0.45, 0.25) if on else Color(0.95, 0.97, 1.0)
				if n.get("s", false):
					_canvas.draw_circle(p, 5.0, col)
					_canvas.draw_arc(p, 5.0, 0, TAU, 12, Color(0.1, 0.15, 0.3), 1.0)
				else:
					_canvas.draw_rect(r, col)
					_canvas.draw_rect(r, Color(0.1, 0.15, 0.3), false, 1.0)


# --- Selection geometry ---------------------------------------------------------------------

func _bounds_of(list: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for s in list:
		var b := SvgDoc.bounds(s)
		if b.size == Vector2.ZERO and b.position == Vector2.ZERO:
			continue
		r = b if first else r.merge(b)
		first = false
	return r


func _sel_screen_rect() -> Rect2:
	var b := _bounds_of(sel)
	return Rect2(_to_screen(b.position), b.size * zoom).grow(4.0)


## Handle positions: 0..7 round the box from the top-left; 8 = rotate.
func _handle_pos(r: Rect2, i: int) -> Vector2:
	var c := r.get_center()
	match i:
		0: return r.position
		1: return Vector2(c.x, r.position.y)
		2: return Vector2(r.end.x, r.position.y)
		3: return Vector2(r.end.x, c.y)
		4: return r.end
		5: return Vector2(c.x, r.end.y)
		6: return Vector2(r.position.x, r.end.y)
		7: return Vector2(r.position.x, c.y)
	return Vector2(c.x, r.position.y - 26.0)


func shape_at(p: Vector2) -> Dictionary:
	for k in range(doc.shapes.size() - 1, -1, -1):
		var sh: Dictionary = doc.shapes[k]
		if not sh["locked"] and SvgDoc.hit(sh, p, 4.0 / zoom):
			return sh
	return {}


func _node_selected(sh: Dictionary, si: int, ni: int) -> bool:
	for e in node_sel:
		if is_same(e[0], sh) and e[1] == si and e[2] == ni:
			return true
	return false


# --- Input ----------------------------------------------------------------------------

func set_tool(id: String) -> void:
	if tool == "pen" and id != "pen":
		_finish_pen()
	tool = id
	for t in _tool_btns:
		_tool_btns[t].button_pressed = t == id
	if id == "node":
		for s in sel:
			if s["type"] != "path":
				_to_path(s)
	node_sel = []
	_rebuild_panel()
	_set_status()
	_canvas.queue_redraw()


func _set_status(text := "") -> void:
	if text == "":
		for t in TOOLS:
			if t[0] == tool:
				text = t[2] + ": " + t[4].replace("\n", " ")
	_status.text = text + ("   [snap on]" if snap else "")


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse_screen = mm.position
		_mouse = _to_page(mm.position)
		_coords.text = "x %.1f   y %.1f   ·   %d%%" % [_mouse.x, _mouse.y, roundi(zoom * 100.0)]
		if _drag == "pan":
			pan += mm.relative
			_render_dirty = true
		elif _drag != "":
			on_motion(_mouse, mm.shift_pressed, mm.ctrl_pressed)
		elif tool in ["select", "node", "picker"]:
			var h := shape_at(_mouse)
			if not is_same(h, _hover):
				_hover = h
		_canvas.queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse_screen = mb.position
		_mouse = _to_page(mb.position)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE)):
			_drag = "pan" if mb.pressed else ""
			if UI.middle_click(self, mb):
				zoom_fit()   # (a middle click: the whole page again; a middle drag pans)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if tool == "pen" and not _pen.is_empty():
				_finish_pen()
			elif _drag == "":
				context_menu(_mouse, mb.global_position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_canvas.grab_focus()
			if mb.pressed:
				on_press(_mouse, mb.shift_pressed, mb.ctrl_pressed, mb.double_click)
			else:
				on_release(_mouse, mb.shift_pressed, mb.ctrl_pressed)
		_canvas.queue_redraw()


## A left press at page point p (the tools' logic; tests call it directly).
func on_press(p: Vector2, shift := false, ctrl := false, double := false) -> void:
	_press = p
	_press_screen = _to_screen(p)
	_mouse = p
	_mouse_screen = _press_screen
	match tool:
		"select":
			if double:
				var d := shape_at(p)
				if not d.is_empty():
					sel = [d]
					set_tool("node")
				return
			if not sel.is_empty():
				var r := _sel_screen_rect()
				for i in 9:
					if _handle_pos(r, i).distance_to(_press_screen) <= HANDLE:
						_begin_transform("rotate" if i == 8 else "scale", i)
						return
			var hit := shape_at(p)
			if hit.is_empty():
				if not shift:
					_select([])
				_drag = "band"
				return
			if shift:
				if _is_sel(hit):
					_select(sel.filter(func(s): return not is_same(s, hit)))
					return
				_select(sel + [hit])
			elif not _is_sel(hit):
				_select([hit])
			_begin_transform("move", -1)
		"node":
			if double:
				_insert_node_at(p)
				return
			# Handles of selected nodes first, then nodes.
			for e in node_sel:
				var n: Dictionary = e[0]["subs"][e[1]]["nodes"][e[2]]
				for h in ["i", "o"]:
					if not (n[h] as Vector2).is_equal_approx(n["p"]) and _to_screen(e[0]["xf"] * n[h]).distance_to(_press_screen) <= 7.0:
						_push_undo()
						node_sel = [e]
						_handle_side = h
						_drag = "handle"
						return
			for sh in sel:
				if sh["type"] != "path":
					continue
				var subs: Array = sh["subs"]
				for si in subs.size():
					for ni in subs[si]["nodes"].size():
						if _to_screen(sh["xf"] * subs[si]["nodes"][ni]["p"]).distance_to(_press_screen) <= 7.0:
							if shift:
								if not _node_selected(sh, si, ni):
									node_sel.append([sh, si, ni])
							elif not _node_selected(sh, si, ni):
								node_sel = [[sh, si, ni]]
							_push_undo()
							_orig = node_sel.map(func(e): return (e[0]["subs"][e[1]]["nodes"][e[2]] as Dictionary).duplicate())
							_drag = "node"
							_rebuild_panel()
							return
			var hit := shape_at(p)
			if not hit.is_empty() and not _is_sel(hit):
				if hit["type"] != "path":
					_to_path(hit)
				_select([hit])
				return
			if not shift:
				node_sel = []
			_drag = "band"
		"rect", "ellipse", "star":
			_push_undo()
			var sh := SvgDoc.new_shape(tool)
			_apply_style(sh)
			if tool == "star":
				sh.merge({"n": star_n, "star": star_on}, true)
			doc.shapes.append(sh)
			_creating = sh
			_drag = "create"
			on_motion(p, shift, ctrl)
		"pen":
			var q := _snap(p)
			if double:
				_finish_pen()
				return
			if _pen.is_empty():
				_push_undo()
				var sh := SvgDoc.new_shape("path")
				_apply_style(sh)
				sh["fill"] = null
				sh["subs"] = [{"closed": false, "nodes": [SvgDoc.node(q)]}]
				doc.shapes.append(sh)
				_pen = sh
				_select([sh])
			else:
				var ns: Array = _pen["subs"][0]["nodes"]
				if ns.size() >= 2 and _to_screen(ns[0]["p"]).distance_to(_press_screen) <= 8.0:
					_pen["subs"][0]["closed"] = true
					if style["fill"] != null:
						_pen["fill"] = style["fill"]
					_finish_pen()
					return
				ns.append(SvgDoc.node(q))
			_drag = "pen"
			_changed()
		"pencil":
			_pencil = PackedVector2Array([p])
			_drag = "pencil"
		"text":
			var hit := shape_at(p)
			if not hit.is_empty() and hit["type"] == "text":
				_select([hit])
			else:
				_push_undo()
				var sh := SvgDoc.new_shape("text")
				sh["fill"] = style["fill"] if style["fill"] != null else Color.BLACK
				sh.merge({"x": _snap(p).x, "y": _snap(p).y}, true)
				doc.shapes.append(sh)
				_select([sh])
				_changed(true)
			if _text_edit:
				_text_edit.grab_focus()
				_text_edit.select_all()
		"picker":
			var hit := shape_at(p)
			if hit.is_empty():
				return
			if sel.is_empty() or (sel.size() == 1 and is_same(sel[0], hit)):
				style["fill"] = hit["fill"]
				if shift:
					style["stroke"] = hit["stroke"]
					style["stroke_width"] = hit["stroke_width"]
				_set_status("New shapes will use the picked colour.")
			else:
				_push_undo()
				for s in sel:
					s["fill"] = hit["fill"]
					if shift:
						s["stroke"] = hit["stroke"]
						s["stroke_width"] = hit["stroke_width"]
				_changed(true)


func on_motion(p: Vector2, shift := false, ctrl := false) -> void:
	_mouse = p
	_mouse_screen = _to_screen(p)
	match _drag:
		"move":
			var d := p - _press
			if snap:
				d = _snap(_bbox0.position + d) - _bbox0.position
			if ctrl:
				d = Vector2(d.x, 0) if absf(d.x) > absf(d.y) else Vector2(0, d.y)
			for k in sel.size():
				sel[k]["xf"] = Transform2D(0.0, d) * _orig[k]
			_changed()
		"scale":
			var b := _bbox0
			var anchor := b.get_center() * 2.0 - _handle_page(b, _handle)
			var h0 := _handle_page(b, _handle)
			var q := _snap(p)
			var sx := 1.0
			var sy := 1.0
			if _handle in [0, 2, 3, 4, 6, 7] and absf(h0.x - anchor.x) > 1e-6:
				sx = (q.x - anchor.x) / (h0.x - anchor.x)
			if _handle in [0, 1, 2, 4, 5, 6] and absf(h0.y - anchor.y) > 1e-6:
				sy = (q.y - anchor.y) / (h0.y - anchor.y)
			if ctrl or shift:
				var s: float = sx if (absf(sx) > absf(sy) and _handle not in [1, 5]) or _handle in [3, 7] else sy
				sx = s
				sy = s
			sx = sx if absf(sx) > 0.001 else 0.001
			sy = sy if absf(sy) > 0.001 else 0.001
			var t := Transform2D(0.0, anchor) * Transform2D(Vector2(sx, 0), Vector2(0, sy), Vector2.ZERO) * Transform2D(0.0, -anchor)
			for k in sel.size():
				sel[k]["xf"] = t * _orig[k]
			_changed()
		"rotate":
			var c := _bbox0.get_center()
			var a := (p - c).angle() - (_press - c).angle()
			if ctrl:
				a = snappedf(a, deg_to_rad(15.0))
			var t := Transform2D(0.0, c) * Transform2D(a, Vector2.ZERO) * Transform2D(0.0, -c)
			for k in sel.size():
				sel[k]["xf"] = t * _orig[k]
			_set_status("Rotate: %.1f°" % rad_to_deg(a))
			_changed()
		"create":
			_shape_from_drag(_creating, _snap(_press), _snap(p), ctrl)
			_changed()
		"node":
			for k in node_sel.size():
				var e: Array = node_sel[k]
				var inv: Transform2D = (e[0]["xf"] as Transform2D).affine_inverse()
				var o: Dictionary = _orig[k]
				var d: Vector2 = inv * _snap(p) - inv * _snap(_press)
				var n: Dictionary = e[0]["subs"][e[1]]["nodes"][e[2]]
				n["p"] = o["p"] + d
				n["i"] = o["i"] + d
				n["o"] = o["o"] + d
			_changed()
		"handle":
			var e: Array = node_sel[0]
			var n: Dictionary = e[0]["subs"][e[1]]["nodes"][e[2]]
			var local: Vector2 = (e[0]["xf"] as Transform2D).affine_inverse() * _snap(p)
			n[_handle_side] = local
			if n.get("s", false) and not shift:   # smooth: the other handle stays opposite
				var other := "o" if _handle_side == "i" else "i"
				var len: float = (n[other] as Vector2).distance_to(n["p"])
				var dir: Vector2 = (n["p"] - local).normalized()
				n[other] = n["p"] + dir * len
			_changed()
		"pen":
			var ns: Array = _pen["subs"][0]["nodes"]
			var n: Dictionary = ns[-1]
			if _to_screen(p).distance_to(_to_screen(n["p"])) > 3.0:
				var q := _snap(p)
				n["o"] = q
				n["i"] = n["p"] * 2.0 - q
				n["s"] = true
				_changed()
		"pencil":
			if _pencil.is_empty() or _to_screen(_pencil[-1]).distance_to(_to_screen(p)) > 2.0:
				_pencil.append(p)


func on_release(p: Vector2, shift := false, _ctrl := false) -> void:
	match _drag:
		"band":
			var r := Rect2(_press, Vector2.ZERO).expand(p)
			if tool == "node":
				if not shift:
					node_sel = []
				for sh in sel:
					if sh["type"] != "path":
						continue
					var subs: Array = sh["subs"]
					for si in subs.size():
						for ni in subs[si]["nodes"].size():
							if r.has_point(sh["xf"] * subs[si]["nodes"][ni]["p"]) and not _node_selected(sh, si, ni):
								node_sel.append([sh, si, ni])
				_rebuild_panel()
			elif r.size.length() * zoom > 3.0:
				var picked := doc.shapes.filter(func(s): return not s["locked"] and not s["hidden"] and r.encloses(SvgDoc.bounds(s)))
				_select((sel + picked) if shift else picked)
		"create":
			var b := SvgDoc.bounds(_creating)
			if b.size.length() * zoom < 3.0:
				doc.shapes.erase(_creating)
				_undo.pop_back()
			else:
				_select([_creating])
			_creating = {}
			_changed(true)
		"pencil":
			_finish_pencil()
		"move", "scale", "rotate", "node", "handle":
			_changed(true)
	_drag = "" if _drag != "pan" else _drag
	_set_status()


func _begin_transform(kind: String, handle: int) -> void:
	_push_undo()
	_drag = kind
	_handle = handle
	_bbox0 = _bounds_of(sel)
	_orig = sel.map(func(s): return s["xf"])


func _handle_page(b: Rect2, i: int) -> Vector2:
	return _handle_pos(b, i) if i < 8 else b.get_center()


func _shape_from_drag(sh: Dictionary, a: Vector2, b: Vector2, ctrl: bool) -> void:
	var d := b - a
	if sh["type"] == "star":
		var ang := d.angle()
		if ctrl:
			ang = snappedf(ang, deg_to_rad(15.0))
		sh.merge({"cx": a.x, "cy": a.y, "r1": d.length(), "r2": d.length() * star_ratio, "angle": ang}, true)
		return
	if ctrl:
		var m := maxf(absf(d.x), absf(d.y))
		d = Vector2(signf(d.x) if d.x != 0.0 else 1.0, signf(d.y) if d.y != 0.0 else 1.0) * m
	var r := Rect2(a, Vector2.ZERO).expand(a + d)
	if sh["type"] == "rect":
		sh.merge({"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}, true)
	else:
		sh.merge({"cx": r.get_center().x, "cy": r.get_center().y, "rx": r.size.x / 2.0, "ry": r.size.y / 2.0}, true)


func _apply_style(sh: Dictionary) -> void:
	for k in style:
		sh[k] = style[k]


func _finish_pen() -> void:
	if _pen.is_empty():
		return
	var ns: Array = _pen["subs"][0]["nodes"]
	# (A double-click adds the same point twice.)
	while ns.size() >= 2 and (ns[-1]["p"] as Vector2).distance_to(ns[-2]["p"]) * zoom < 2.0:
		ns.pop_back()
	if ns.size() < 2:
		doc.shapes.erase(_pen)
		sel = []
	else:
		sel = [_pen]
	_pen = {}
	_drag = ""
	_changed(true)


func _finish_pencil() -> void:
	var pts := _simplify(_pencil, 1.6 / zoom)
	_pencil = PackedVector2Array()
	if pts.size() < 2:
		return
	_push_undo()
	var closed := pts.size() > 3 and _to_screen(pts[0]).distance_to(_to_screen(pts[-1])) < 10.0
	if closed:
		pts.remove_at(pts.size() - 1)
	var ns := []
	var n := pts.size()
	for k in n:
		var prev: Vector2 = pts[(k - 1 + n) % n] if (closed or k > 0) else pts[k]
		var next: Vector2 = pts[(k + 1) % n] if (closed or k < n - 1) else pts[k]
		var t := (next - prev) / 6.0
		ns.append(SvgDoc.node(pts[k], pts[k] - t, pts[k] + t, true))
	var sh := SvgDoc.new_shape("path")
	_apply_style(sh)
	if not closed:
		sh["fill"] = null
	sh["subs"] = [{"closed": closed, "nodes": ns}]
	doc.shapes.append(sh)
	_select([sh])
	_changed(true)


## Ramer-Douglas-Peucker simplification.
static func _simplify(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep := []
	keep.resize(pts.size())
	keep.fill(false)
	keep[0] = true
	keep[-1] = true
	var stack := [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var best := -1.0
		var bi := -1
		for k in range(seg[0] + 1, seg[1]):
			var d := Geometry2D.get_closest_point_to_segment(pts[k], pts[seg[0]], pts[seg[1]]).distance_to(pts[k])
			if d > best:
				best = d
				bi = k
		if best > eps:
			keep[bi] = true
			stack.append([seg[0], bi])
			stack.append([bi, seg[1]])
	var out := PackedVector2Array()
	for k in pts.size():
		if keep[k]:
			out.append(pts[k])
	return out


## Turns a rectangle, ellipse, star or text into an editable path.
func _to_path(sh: Dictionary) -> void:
	if sh["type"] == "path":
		return
	_push_undo()
	var subs: Array = SvgDoc.to_subs(sh).duplicate(true)
	for k in ["x", "y", "w", "h", "r", "cx", "cy", "rx", "ry", "r1", "r2", "n", "star", "angle", "text", "size", "bold"]:
		sh.erase(k)
	sh["type"] = "path"
	sh["subs"] = subs
	_changed(true)


## The point of a selected path's outline nearest p, if within 8 px:
## [shape, sub index, segment index, t] (else []).
func _segment_at(p: Vector2) -> Array:
	var best := INF
	var hit := []
	for sh in sel:
		if sh["type"] != "path":
			continue
		var xf: Transform2D = sh["xf"]
		var subs: Array = sh["subs"]
		for si in subs.size():
			var ns: Array = subs[si]["nodes"]
			var count: int = ns.size() if subs[si]["closed"] else ns.size() - 1
			for k in count:
				var a: Dictionary = ns[k]
				var b: Dictionary = ns[(k + 1) % ns.size()]
				for s in 41:
					var t := s / 40.0
					var q: Vector2 = xf * _bez(a["p"], a["o"], b["i"], b["p"], t)
					var d := q.distance_to(p)
					if d < best:
						best = d
						hit = [sh, si, k, t]
	return [] if hit.is_empty() or best * zoom > 8.0 else hit


func _insert_node_at(p: Vector2) -> void:
	var hit := _segment_at(p)
	if hit.is_empty():
		return
	_push_undo()
	var ns: Array = hit[0]["subs"][hit[1]]["nodes"]
	var k: int = hit[2]
	var t: float = hit[3]
	var a: Dictionary = ns[k]
	var b: Dictionary = ns[(k + 1) % ns.size()]
	var p0: Vector2 = a["p"]
	var c0: Vector2 = a["o"]
	var c1: Vector2 = b["i"]
	var p1: Vector2 = b["p"]
	var e0 := p0.lerp(c0, t)
	var e1 := c0.lerp(c1, t)
	var e2 := c1.lerp(p1, t)
	var f0 := e0.lerp(e1, t)
	var f1 := e1.lerp(e2, t)
	var m := f0.lerp(f1, t)
	var straight := c0.is_equal_approx(p0) and c1.is_equal_approx(p1)
	if not straight:
		a["o"] = e0
		b["i"] = e2
	ns.insert(k + 1, SvgDoc.node(m, m if straight else f0, m if straight else f1, not straight))
	node_sel = [[hit[0], hit[1], k + 1]]
	_changed(true)


static func _bez(p0: Vector2, c0: Vector2, c1: Vector2, p1: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * u * u * u + c0 * 3.0 * u * u * t + c1 * 3.0 * u * t * t + p1 * t * t * t


func delete_nodes() -> void:
	if node_sel.is_empty():
		return
	_push_undo()
	var by_sub := {}
	for e in node_sel:
		var key := [_index(e[0]), e[1]]
		if not by_sub.has(key):
			by_sub[key] = [e[0], []]
		by_sub[key][1].append(e[2])
	for key in by_sub:
		var sh: Dictionary = by_sub[key][0]
		var ns: Array = sh["subs"][key[1]]["nodes"]
		var idx: Array = by_sub[key][1]
		idx.sort()
		idx.reverse()
		for i in idx:
			ns.remove_at(i)
	for sh in sel.duplicate():
		if sh["type"] == "path":
			sh["subs"] = sh["subs"].filter(func(s): return s["nodes"].size() >= 2)
			if sh["subs"].is_empty():
				doc.shapes.erase(sh)
				sel.erase(sh)
	node_sel = []
	_changed(true)


## Node types: smooth (handles in line), sharp (no handles, straight joins).
func set_nodes_smooth(smooth: bool) -> void:
	if node_sel.is_empty():
		return
	_push_undo()
	for e in node_sel:
		var sub: Dictionary = e[0]["subs"][e[1]]
		var ns: Array = sub["nodes"]
		var n: Dictionary = ns[e[2]]
		if not smooth:
			n["i"] = n["p"]
			n["o"] = n["p"]
			n["s"] = false
			continue
		var count := ns.size()
		var prev: Vector2 = ns[(e[2] - 1 + count) % count]["p"] if (sub["closed"] or e[2] > 0) else n["p"]
		var next: Vector2 = ns[(e[2] + 1) % count]["p"] if (sub["closed"] or e[2] < count - 1) else n["p"]
		var dir := (next - prev).normalized()
		n["i"] = n["p"] - dir * (n["p"] as Vector2).distance_to(prev) / 3.0
		n["o"] = n["p"] + dir * (n["p"] as Vector2).distance_to(next) / 3.0
		n["s"] = true
	_changed(true)


func toggle_closed() -> void:
	var done := {}
	_push_undo()
	for e in (node_sel if not node_sel.is_empty() else sel.map(func(s): return [s, 0, 0])):
		var sh: Dictionary = e[0]
		if sh["type"] != "path" or sh["subs"].is_empty() or done.has([_index(sh), e[1]]):
			continue
		done[[_index(sh), e[1]]] = true
		sh["subs"][e[1]]["closed"] = not sh["subs"][e[1]]["closed"]
	_changed(true)


# --- Selection, arranging ---------------------------------------------------------------------

func _select(list: Array) -> void:
	sel = []
	for s in list:
		if not _is_sel(s):
			sel.append(s)
	node_sel = []
	_refresh_objects()
	_rebuild_panel()
	_canvas.queue_redraw()


func select_all() -> void:
	_select(doc.shapes.filter(func(s): return not s["locked"] and not s["hidden"]))


func delete_selection() -> void:
	if tool == "node" and not node_sel.is_empty():
		delete_nodes()
		return
	if sel.is_empty():
		return
	_push_undo()
	for s in sel:
		doc.shapes.erase(s)
	sel = []
	_changed(true)


func duplicate_selection() -> void:
	if sel.is_empty():
		return
	_push_undo()
	var copies := []
	for s in sel:
		var c: Dictionary = s.duplicate(true)
		doc.shapes.insert(_index(s) + 1 + copies.size(), c)
		copies.append(c)
	_select(copies)
	_changed(true)


func copy() -> void:
	_clip = sel.map(func(s): return s.duplicate(true))
	DisplayServer.clipboard_set(SvgDoc.new().to_svg() if sel.is_empty() else "\n".join(sel.map(func(s): return SvgDoc.shape_svg(s, false))))


func paste() -> void:
	if _clip.is_empty():
		return
	_push_undo()
	var copies := []
	for s in _clip:
		var c: Dictionary = s.duplicate(true)
		c["xf"] = Transform2D(0.0, Vector2(10, 10)) * c["xf"]
		doc.shapes.append(c)
		copies.append(c)
	_clip = copies.map(func(s): return s.duplicate(true))
	_select(copies)
	_changed(true)


## dir: +1 raise one step, -1 lower, +2 to the top, -2 to the bottom.
func arrange(dir: int) -> void:
	if sel.is_empty():
		return
	_push_undo()
	var order := sel.duplicate()
	order.sort_custom(func(a, b): return _index(a) > _index(b) if dir > 0 else _index(a) < _index(b))
	for s in order:
		var i := _index(s)
		doc.shapes.remove_at(i)
		var to: int
		match dir:
			1: to = mini(i + 1, doc.shapes.size())
			-1: to = maxi(i - 1, 0)
			2: to = doc.shapes.size()
			_: to = 0
		doc.shapes.insert(to, s)
	_changed(true)


## Applies a page-space transform about the selection's centre.
func transform_selection(t: Transform2D) -> void:
	if sel.is_empty():
		return
	_push_undo()
	var c := _bounds_of(sel).get_center()
	var full := Transform2D(0.0, c) * t * Transform2D(0.0, -c)
	for s in sel:
		s["xf"] = full * s["xf"]
	_changed(true)


## Aligns the selection's shapes: edge in left, hcenter, right, top, vcenter,
## bottom; to the selection's box (or the page with one shape selected).
func align(edge: String) -> void:
	if sel.is_empty():
		return
	_push_undo()
	var ref := _bounds_of(sel) if sel.size() > 1 else Rect2(0, 0, doc.width, doc.height)
	for s in sel:
		var b := SvgDoc.bounds(s)
		var d := Vector2.ZERO
		match edge:
			"left": d.x = ref.position.x - b.position.x
			"hcenter": d.x = ref.get_center().x - b.get_center().x
			"right": d.x = ref.end.x - b.end.x
			"top": d.y = ref.position.y - b.position.y
			"vcenter": d.y = ref.get_center().y - b.get_center().y
			"bottom": d.y = ref.end.y - b.end.y
		s["xf"] = Transform2D(0.0, d) * s["xf"]
	_changed(true)


func _toggle_hidden() -> void:
	if sel.is_empty():
		return
	_push_undo()
	var h: bool = not sel[0]["hidden"]
	for s in sel:
		s["hidden"] = h
	_changed(true)


func _toggle_locked() -> void:
	if sel.is_empty():
		return
	_push_undo()
	var l: bool = not sel[0]["locked"]
	for s in sel:
		s["locked"] = l
	_changed(true)


func _refresh_objects() -> void:
	if _objects == null:
		return
	_listing = true
	_objects.clear()
	var root := _objects.create_item()
	for k in range(doc.shapes.size() - 1, -1, -1):
		var s: Dictionary = doc.shapes[k]
		var t: String = s["type"]
		var name: String = s["name"] if s["name"] != "" else ("%s \"%s\"" % [t.capitalize(), str(s["text"]).left(18)] if t == "text" else t.capitalize())
		var it := _objects.create_item(root)
		it.set_text(0, name)
		it.set_metadata(0, k)
		var col = s["fill"] if s["fill"] != null else s["stroke"]
		it.set_icon(0, EditorIcons.get_icon({"rect": "rect", "ellipse": "ellipse", "star": "star_tool", "text": "text"}.get(t, "pen")))
		if col != null:
			it.set_icon_modulate(0, Color(col, 1.0))
		if s["hidden"]:
			it.set_custom_color(0, Color(0.55, 0.58, 0.65))
		it.add_button(0, EditorIcons.get_icon("eye_off" if s["hidden"] else "eye"), 0, false,
			("Show it" if s["hidden"] else "Hide it") + " (Shift: every selected object)")
		it.add_button(0, EditorIcons.get_icon("lock" if s["locked"] else "unlock"), 1, false,
			("Unlock it" if s["locked"] else "Lock it - it can't be clicked on the canvas") + " (Shift: every selected object)")
		if _is_sel(s):
			it.select(0)
	_listing = false


## The eye (id 0) and padlock (id 1) on an object's row.
func _on_object_button(it: TreeItem, _col: int, id: int, _mb: int) -> void:
	var k: int = it.get_metadata(0)
	if k < 0 or k >= doc.shapes.size():
		return
	var sh: Dictionary = doc.shapes[k]
	var key := "hidden" if id == 0 else "locked"
	var value: bool = not sh[key]
	var targets: Array = sel if Input.is_key_pressed(KEY_SHIFT) and _is_sel(sh) else [sh]
	_push_undo()
	for s in targets:
		s[key] = value
		if key == "hidden" and value and is_same(_hover, s):
			_hover = {}
	_changed(true)


func _select_from_list() -> void:
	var picked := []
	var it := _objects.get_next_selected(null)
	while it:
		var k: int = it.get_metadata(0)
		if k >= 0 and k < doc.shapes.size():
			picked.append(doc.shapes[k])
		it = _objects.get_next_selected(it)
	sel = picked
	node_sel = []
	_rebuild_panel()
	_canvas.queue_redraw()


# --- Right-click menu ------------------------------------------------------------------

## The node under a screen point on a selected path: [shape, sub, node] or [].
func _node_at(screen: Vector2) -> Array:
	for sh in sel:
		if sh["type"] != "path":
			continue
		var subs: Array = sh["subs"]
		for si in subs.size():
			for ni in subs[si]["nodes"].size():
				if _to_screen(sh["xf"] * subs[si]["nodes"][ni]["p"]).distance_to(screen) <= 7.0:
					return [sh, si, ni]
	return []


## Builds the menu for what's under the page point p: nodes and segments
## (Nodes tool), shapes, or the empty canvas. Returns its entries (tests).
func context_menu(p: Vector2, at: Vector2, show := true) -> Array:
	var items := []
	var C := KEY_MASK_CTRL
	var S := KEY_MASK_SHIFT
	if tool == "node" and not sel.is_empty():
		var n := _node_at(_to_screen(p))
		if not n.is_empty() and not _node_selected(n[0], n[1], n[2]):
			node_sel = [n]
			_rebuild_panel()
		var seg := _segment_at(p) if n.is_empty() else []
		items.append("#NODES  (%d selected)" % node_sel.size())
		if not seg.is_empty():
			items.append(["Add a node here", func(): _insert_node_at(p), 0, false])
		var some := not node_sel.is_empty()
		items.append(["Make smooth", func(): set_nodes_smooth(true), 0, not some])
		items.append(["Make sharp (corner)", func(): set_nodes_smooth(false), 0, not some])
		items.append(["Delete nodes", delete_nodes, KEY_DELETE, not some])
		items.append(["Break the path here", break_at_node, 0, not some])
		items.append(["Close / open the path", toggle_closed, 0, false])
		items.append("-")
		items.append(["Select all nodes", select_all_nodes, C | KEY_A, false])
		items.append(["Back to the Select tool", set_tool.bind("select"), KEY_S, false])
	else:
		var hit := shape_at(p)
		if not hit.is_empty() and not _is_sel(hit):
			_select([hit])
		elif hit.is_empty() and not _bounds_of(sel).grow(4.0 / zoom).has_point(p):
			_select([])
		if not sel.is_empty():
			var one: bool = sel.size() == 1
			items.append("#" + (str(sel[0]["name"] if sel[0]["name"] != "" else sel[0]["type"]).to_upper() if one else "%d OBJECTS" % sel.size()))
			items.append(["Cut", cut, C | KEY_X, false])
			items.append(["Copy", copy, C | KEY_C, false])
			items.append(["Paste", paste, C | KEY_V, _clip.is_empty()])
			items.append(["Duplicate", duplicate_selection, C | KEY_D, false])
			items.append(["Delete", delete_selection, KEY_DELETE, false])
			items.append("-")
			items.append(["Edit nodes", set_tool.bind("node"), KEY_N, false])
			items.append(["Object to path", func():
				for s in sel:
					_to_path(s), C | S | KEY_C, sel.all(func(s): return s["type"] == "path")])
			items.append("-")
			items.append(["Raise to top", func(): arrange(2), KEY_HOME, false])
			items.append(["Raise", func(): arrange(1), KEY_PAGEUP, false])
			items.append(["Lower", func(): arrange(-1), KEY_PAGEDOWN, false])
			items.append(["Lower to bottom", func(): arrange(-2), KEY_END, false])
			items.append("-")
			items.append(["Flip horizontally", func(): transform_selection(Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO)), KEY_H, false])
			items.append(["Flip vertically", func(): transform_selection(Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2.ZERO)), KEY_V, false])
			items.append(["Rotate 90° clockwise", func(): transform_selection(Transform2D(PI / 2.0, Vector2.ZERO)), 0, false])
			items.append(["Rotate 90° anticlockwise", func(): transform_selection(Transform2D(-PI / 2.0, Vector2.ZERO)), 0, false])
			items.append("-")
			items.append(["Hide", _toggle_hidden, 0, false])
			items.append(["Unlock" if sel[0]["locked"] else "Lock", _toggle_locked, 0, false])
		else:
			items.append("#CANVAS")
			items.append(["Paste", paste, C | KEY_V, _clip.is_empty()])
			items.append(["Select all", select_all, C | KEY_A, doc.shapes.is_empty()])
			items.append("-")
			items.append(["Zoom to the page", zoom_fit, KEY_5, false])
			items.append(["Zoom 100%", func(): _zoom_at(_canvas.size / 2.0, 1.0 / zoom), KEY_1, false])
			items.append([("Hide" if show_grid else "Show") + " the grid", func(): show_grid = not show_grid; _canvas.queue_redraw(), 0, false])
			items.append([("Stop snapping" if snap else "Snap") + " to the grid", func(): snap = not snap; _set_status(), 0, false])
			items.append("-")
			items.append(["Export PNG...", _export_dialog, C | KEY_E, false])
	if show:
		_popup(items, at)
	return items


func _popup(items: Array, at: Vector2) -> void:
	var m := PopupMenu.new()
	m.theme = NeonTheme.build()
	m.add_theme_font_size_override("font_size", Settings.fs("menu", 15))
	m.add_theme_color_override("font_separator_color", ACCENT)
	var calls := {}
	for e in items:
		if e is String:
			if e.begins_with("#"):
				m.add_separator(e.substr(1))
			else:
				m.add_separator()
			continue
		var id := calls.size()
		m.add_item(e[0], id)
		var idx := m.item_count - 1
		if int(e[2]) != 0:
			m.set_item_accelerator(idx, e[2])
		m.set_item_disabled(idx, e[3])
		calls[id] = e[1]
	m.id_pressed.connect(func(id): (calls[id] as Callable).call())
	m.popup_hide.connect(m.queue_free)
	add_child(m)
	m.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func cut() -> void:
	copy()
	delete_selection()


func select_all_nodes() -> void:
	node_sel = []
	for sh in sel:
		if sh["type"] == "path":
			for si in sh["subs"].size():
				for ni in sh["subs"][si]["nodes"].size():
					node_sel.append([sh, si, ni])
	_rebuild_panel()
	_canvas.queue_redraw()


## Breaks the path at the (first) selected node: a closed path opens there;
## an open one splits in two (the node is doubled, one copy in each part).
func break_at_node() -> void:
	if node_sel.is_empty():
		return
	var e: Array = node_sel[0]
	var sh: Dictionary = e[0]
	var sub: Dictionary = sh["subs"][e[1]]
	var ns: Array = sub["nodes"]
	var k: int = e[2]
	_push_undo()
	if sub["closed"]:
		var opened: Array = ns.slice(k) + ns.slice(0, k)
		var tail: Dictionary = (opened[0] as Dictionary).duplicate()
		opened[0]["i"] = opened[0]["p"]
		tail["o"] = tail["p"]
		opened.append(tail)
		sub["nodes"] = opened
		sub["closed"] = false
	elif k > 0 and k < ns.size() - 1:
		var first: Array = ns.slice(0, k + 1)
		var second: Array = ns.slice(k)
		second[0] = (second[0] as Dictionary).duplicate()
		first[-1]["o"] = first[-1]["p"]
		second[0]["i"] = second[0]["p"]
		sub["nodes"] = first
		sh["subs"].insert(e[1] + 1, {"closed": false, "nodes": second})
	node_sel = []
	_changed(true)


# --- Properties panel --------------------------------------------------------------------

func _row(label: String, c: Control, help := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UI.label(label, 14, UI.TEXT_DIM)
	l.custom_minimum_size = Vector2(118, 0)
	l.tooltip_text = help
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if help != "":
		c.tooltip_text = help
	h.add_child(c)
	return h


func _spin(lo: float, hi: float, step: float, value: float, cb: Callable, suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.value = value
	s.suffix = suffix
	s.value_changed.connect(cb)
	return s


func _color(c: Variant, cb: Callable) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.color = c if c != null else Color.BLACK
	b.edit_alpha = true
	b.custom_minimum_size = Vector2(60, 28)
	b.color_changed.connect(cb)
	return b


## Sets a property on every selected shape (and the drawing style).
func set_prop(key: String, value: Variant) -> void:
	if key in style:
		style[key] = value
	if sel.is_empty():
		return
	_push_undo("prop:" + key)
	for s in sel:
		if s.has(key) or key in style:
			s[key] = value
	_changed()
	if key in ["name", "text", "hidden", "locked", "fill", "stroke"]:
		_refresh_objects()


func _rebuild_panel() -> void:
	if _panel == null:
		return
	UI.clear(_panel)
	_text_edit = null
	var one: Dictionary = sel[0] if sel.size() == 1 else {}
	var src: Dictionary = sel[0] if not sel.is_empty() else style
	_panel.add_child(UI.label(("%d OBJECTS" % sel.size()) if sel.size() > 1 else (str(one["type"]).to_upper() if not one.is_empty() else "NEW SHAPES"), 16, ACCENT))
	if sel.is_empty():
		_panel.add_child(UI.label("The style new shapes are drawn with:", 13, UI.TEXT_DIM))
	# Fill and stroke.
	var fill_on := CheckBox.new()
	fill_on.button_pressed = src["fill"] != null
	var fill_c := _color(src["fill"], func(c): set_prop("fill", c))
	fill_on.toggled.connect(func(on): set_prop("fill", fill_c.color if on else null))
	var fr := HBoxContainer.new()
	fr.add_child(fill_on)
	fill_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.add_child(fill_c)
	_panel.add_child(_row("Fill", fr, "The inside colour (with transparency). Untick for no fill."))
	var st_on := CheckBox.new()
	st_on.button_pressed = src["stroke"] != null
	var st_c := _color(src["stroke"], func(c): set_prop("stroke", c))
	st_on.toggled.connect(func(on): set_prop("stroke", st_c.color if on else null))
	var sr := HBoxContainer.new()
	sr.add_child(st_on)
	st_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(st_c)
	_panel.add_child(_row("Stroke", sr, "The outline colour. Untick for no outline."))
	_panel.add_child(_row("Stroke width", _spin(0.0, 200.0, 0.5, float(src["stroke_width"]), func(v): set_prop("stroke_width", v), " px"), "Thickness of the outline."))
	var op := HSlider.new()
	op.min_value = 0.0
	op.max_value = 1.0
	op.step = 0.01
	op.value = float(src["opacity"])
	op.value_changed.connect(func(v): set_prop("opacity", v))
	_panel.add_child(_row("Opacity", op, "How opaque the whole shape is."))
	# Shape-specific.
	var star_src: Dictionary = one if not one.is_empty() and one["type"] == "star" else {}
	if not one.is_empty():
		var nm := LineEdit.new()
		nm.text = one["name"]
		nm.placeholder_text = "(no name)"
		nm.text_changed.connect(func(t): set_prop("name", t))
		_panel.add_child(_row("Name / id", nm, "The object's id in the SVG file and its name in the Objects list."))
		match one["type"]:
			"rect":
				_panel.add_child(_row("Corner radius", _spin(0.0, 1000.0, 0.5, float(one["r"]), func(v): set_prop("r", v), " px"), "Rounds the corners."))
			"text":
				_text_edit = LineEdit.new()
				_text_edit.text = one["text"]
				_text_edit.text_changed.connect(func(t): set_prop("text", t))
				_panel.add_child(_row("Text", _text_edit, "The words. (Drawn as outlines of the game's font.)"))
				_panel.add_child(_row("Font size", _spin(1.0, 1000.0, 1.0, float(one["size"]), func(v): set_prop("size", v), " px"), "Height of the letters."))
				var bold := CheckBox.new()
				bold.button_pressed = one["bold"]
				bold.toggled.connect(func(on): set_prop("bold", on))
				_panel.add_child(_row("Bold", bold, "Heavier letters."))
	if tool == "star" or not star_src.is_empty():
		_panel.add_child(UI.label("STAR / POLYGON", 14, ACCENT))
		var n_src: int = int(star_src["n"]) if not star_src.is_empty() else star_n
		_panel.add_child(_row("Corners", _spin(3, 64, 1, n_src, func(v): star_n = int(v); set_prop("n", int(v))), "How many points (or sides)."))
		var ratio: float = float(star_src["r2"]) / maxf(float(star_src["r1"]), 0.001) if not star_src.is_empty() else star_ratio
		_panel.add_child(_row("Spoke ratio", _spin(0.01, 1.0, 0.01, ratio, func(v):
			star_ratio = v
			for s in sel:
				if s["type"] == "star":
					_push_undo("prop:ratio")
					s["r2"] = float(s["r1"]) * v
			_changed()), "Inner radius against the outer one (stars only)."))
		var is_star := CheckBox.new()
		is_star.button_pressed = star_src["star"] if not star_src.is_empty() else star_on
		is_star.text = "Star (off: polygon)"
		is_star.toggled.connect(func(on): star_on = on; set_prop("star", on))
		_panel.add_child(is_star)
	# Position and size of the selection.
	if not sel.is_empty():
		_panel.add_child(UI.label("POSITION AND SIZE", 14, ACCENT))
		var b := _bounds_of(sel)
		var g := GridContainer.new()
		g.columns = 4
		for f in [["X", b.position.x], ["Y", b.position.y], ["W", b.size.x], ["H", b.size.y]]:
			g.add_child(UI.label(f[0], 14, UI.TEXT_DIM))
			var key: String = f[0]
			var sp := _spin(-100000.0, 100000.0, 0.1, f[1], func(v): _set_geometry(key, v))
			sp.custom_minimum_size = Vector2(110, 0)
			g.add_child(sp)
		_panel.add_child(g)
		var tr := HFlowContainer.new()
		tr.add_child(_small("⟲ 90°", "Rotates the selection 90° anticlockwise.", func(): transform_selection(Transform2D(-PI / 2.0, Vector2.ZERO))))
		tr.add_child(_small("⟳ 90°", "Rotates the selection 90° clockwise.", func(): transform_selection(Transform2D(PI / 2.0, Vector2.ZERO))))
		tr.add_child(_small("Flip ↔", "Flips the selection horizontally (H).", func(): transform_selection(Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO))))
		tr.add_child(_small("Flip ↕", "Flips the selection vertically (V).", func(): transform_selection(Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2.ZERO))))
		_panel.add_child(tr)
		_panel.add_child(UI.label("ALIGN  (to the page, or to each other)", 14, ACCENT))
		var al := HFlowContainer.new()
		for a in [["⇤", "left", "Left edges"], ["↔", "hcenter", "Centres, horizontally"], ["⇥", "right", "Right edges"],
				["⤒", "top", "Top edges"], ["↕", "vcenter", "Centres, vertically"], ["⤓", "bottom", "Bottom edges"]]:
			al.add_child(_small(a[0], "Aligns the %s (of the selection; a single shape to the page)." % a[2].to_lower(), align.bind(a[1])))
		_panel.add_child(al)
		_panel.add_child(UI.label("ARRANGE", 14, ACCENT))
		var ar := HFlowContainer.new()
		ar.add_child(_small("To top", "Raises the selection to the top (Home).", func(): arrange(2)))
		ar.add_child(_small("Raise", "One step up (Page Up).", func(): arrange(1)))
		ar.add_child(_small("Lower", "One step down (Page Down).", func(): arrange(-1)))
		ar.add_child(_small("To bottom", "Lowers the selection to the bottom (End).", func(): arrange(-2)))
		ar.add_child(_small("Duplicate", "Copies the selection in place (Ctrl+D).", duplicate_selection))
		ar.add_child(_small("Delete", "Deletes the selection (Delete).", delete_selection))
		ar.add_child(_small("To path", "Turns rectangles, ellipses, stars and text into editable paths (Ctrl+Shift+C).", func():
			for s in sel:
				_to_path(s)))
		_panel.add_child(ar)
	if tool == "node":
		_panel.add_child(UI.label("NODES  (%d selected)" % node_sel.size(), 14, ACCENT))
		var nr := HFlowContainer.new()
		nr.add_child(_small("Smooth", "Makes the selected nodes smooth: their handles line up.", func(): set_nodes_smooth(true)))
		nr.add_child(_small("Sharp", "Makes the selected nodes sharp corners with straight segments.", func(): set_nodes_smooth(false)))
		nr.add_child(_small("Delete", "Deletes the selected nodes (Delete).", delete_nodes))
		nr.add_child(_small("Close / open", "Closes the selected nodes' path (or opens it).", toggle_closed))
		_panel.add_child(nr)
		_panel.add_child(UI.label("Double-click a segment to add a node.", 13, UI.TEXT_DIM))
	# The document.
	_panel.add_child(UI.label("DOCUMENT", 14, ACCENT))
	_panel.add_child(_row("Page width", _spin(1.0, 20000.0, 1.0, doc.width, func(v): _push_undo("doc:w"); doc.width = v; _changed(); _update_title(), " px")))
	_panel.add_child(_row("Page height", _spin(1.0, 20000.0, 1.0, doc.height, func(v): _push_undo("doc:h"); doc.height = v; _changed(); _update_title(), " px")))
	var bg_on := CheckBox.new()
	bg_on.button_pressed = doc.background != null
	var bg_c := _color(doc.background if doc.background != null else Color.WHITE, func(c): _push_undo("doc:bg"); doc.background = c; _changed())
	bg_on.toggled.connect(func(on): _push_undo(); doc.background = bg_c.color if on else null; _changed())
	var bgr := HBoxContainer.new()
	bgr.add_child(bg_on)
	bg_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgr.add_child(bg_c)
	_panel.add_child(_row("Background", bgr, "The page colour (saved in the file and used by exports). Untick: transparent."))
	_panel.add_child(_row("Grid size", _spin(1.0, 500.0, 1.0, grid, func(v): grid = v; _canvas.queue_redraw(), " px"), "Spacing of the grid and of snapping."))


func _set_geometry(key: String, v: float) -> void:
	if sel.is_empty():
		return
	var b := _bounds_of(sel)
	_push_undo("geo:" + key)
	var t := Transform2D.IDENTITY
	match key:
		"X": t = Transform2D(0.0, Vector2(v - b.position.x, 0))
		"Y": t = Transform2D(0.0, Vector2(0, v - b.position.y))
		"W":
			if b.size.x > 0.0001 and v > 0.0:
				t = Transform2D(0.0, b.position) * Transform2D(Vector2(v / b.size.x, 0), Vector2(0, 1), Vector2.ZERO) * Transform2D(0.0, -b.position)
		"H":
			if b.size.y > 0.0001 and v > 0.0:
				t = Transform2D(0.0, b.position) * Transform2D(Vector2(1, 0), Vector2(0, v / b.size.y), Vector2.ZERO) * Transform2D(0.0, -b.position)
	for s in sel:
		s["xf"] = t * s["xf"]
	_changed()


# --- Keys ------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var act := Callable()
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if ctrl:
		match k.keycode:
			KEY_Z: act = redo if k.shift_pressed else undo
			KEY_Y: act = redo
			KEY_S: act = _save_as if k.shift_pressed else _save
			KEY_O: act = func(): _guard(_open_dialog)
			KEY_N: act = func(): _guard(func(): _new_doc(true))
			KEY_E: act = _export_dialog
			KEY_A: act = select_all_nodes if tool == "node" else select_all
			KEY_X: act = cut
			KEY_D: act = duplicate_selection
			KEY_C:
				if k.shift_pressed:
					act = func():
						for s in sel:
							_to_path(s)
				else:
					act = copy
			KEY_V: act = paste
	elif not k.echo or k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		match k.keycode:
			KEY_S: act = set_tool.bind("select")
			KEY_N: act = set_tool.bind("node")
			KEY_R: act = set_tool.bind("rect")
			KEY_E: act = set_tool.bind("ellipse")
			KEY_ASTERISK, KEY_KP_MULTIPLY: act = set_tool.bind("star")
			KEY_B: act = set_tool.bind("pen")
			KEY_P: act = set_tool.bind("pencil")
			KEY_T: act = set_tool.bind("text")
			KEY_D: act = set_tool.bind("picker")
			KEY_H: act = func(): transform_selection(Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO))
			KEY_V: act = func(): transform_selection(Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2.ZERO))
			KEY_DELETE, KEY_BACKSPACE:
				if tool == "pen" and not _pen.is_empty():
					act = func():
						var ns: Array = _pen["subs"][0]["nodes"]
						ns.pop_back()
						if ns.is_empty():
							doc.shapes.erase(_pen)
							_pen = {}
						_changed(true)
				else:
					act = delete_selection
			KEY_ENTER, KEY_KP_ENTER: act = _finish_pen
			KEY_PAGEUP: act = func(): arrange(1)
			KEY_PAGEDOWN: act = func(): arrange(-1)
			KEY_HOME: act = func(): arrange(2)
			KEY_END: act = func(): arrange(-2)
			KEY_1: act = func(): _zoom_at(_canvas.size / 2.0, 1.0 / zoom)
			KEY_5: act = zoom_fit
			KEY_NUMBERSIGN: act = func(): show_grid = not show_grid; _canvas.queue_redraw()
			KEY_PERCENT: act = func(): snap = not snap; _set_status()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: act = func(): _zoom_at(_canvas.size / 2.0, 1.25)
			KEY_MINUS, KEY_KP_SUBTRACT: act = func(): _zoom_at(_canvas.size / 2.0, 0.8)
			KEY_F1: act = func(): EditorDocs.open(self, "svg", EditorDocs.FILE)
			KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
				var step := 10.0 if k.shift_pressed else 1.0
				var d: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[k.keycode] * step
				act = func():
					if sel.is_empty():
						return
					_push_undo("nudge")
					for s in sel:
						s["xf"] = Transform2D(0.0, d) * s["xf"]
					_changed()
			KEY_ESCAPE:
				if tool == "pen" and not _pen.is_empty():
					act = _finish_pen
				elif not sel.is_empty():
					act = func(): _select([])
				else:
					act = _back
	if act.is_valid():
		get_viewport().set_input_as_handled()
		act.call()
