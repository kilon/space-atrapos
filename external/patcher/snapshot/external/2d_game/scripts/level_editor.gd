class_name LevelEditor
extends Control
## Level editor overlay (right-click menu > Level Editor). Works on any
## "host" scene that provides:
##   editor_title() -> String
##   editor_tools() -> Array of {id, label, options?: Array, brush?: bool,
##                               drag?: bool, rect?: bool}
##   editor_apply(tool_id, option, brush, world, phase, start_world)
##       phase: "press", "drag" or "release"
##   editor_rect_polygon(a, b) -> PackedVector2Array   (for rect tools)
##   editor_save() -> String, editor_revert() -> String
##   editor_camera() -> Camera2D
## The game pauses while editing; the camera pans (WASD / arrows / middle
## drag) and zooms (wheel) freely.

const ACCENT := Color(0.4, 1.0, 0.6)
const PAN_SPEED := 900.0

var host: Node
var _tools: Array = []
var _tool := 0
var _opt := 0
var _brush := 1
var _panel: PanelContainer
var _tool_buttons: Array = []
var _options: OptionButton
var _brush_row: HBoxContainer
var _status: Label
var _drag_start: Variant = null
var _panning := false
var _cam: Camera2D
var _cam_saved := {}
var _paused_by_me := false
var _built := false
## Changes since the layout was last saved.
var dirty := false
var _brush_slider: HSlider


func _ready() -> void:
	hide()
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	process_mode = PROCESS_MODE_ALWAYS


func open() -> void:
	if not _built:
		_build()
	_paused_by_me = not get_tree().paused
	get_tree().paused = true
	_cam = host.editor_camera()
	_cam_saved = {"mode": _cam.process_mode, "smooth": _cam.position_smoothing_enabled, "zoom": _cam.zoom, "offset": _cam.offset}
	_cam.process_mode = PROCESS_MODE_ALWAYS
	_cam.position_smoothing_enabled = false
	show()
	_select_tool(_tool)
	GameLog.post("[Dev] Level editor opened", "info")


## Leaves the editor, asking first about unsaved layout changes.
func close() -> void:
	if dirty and visible:
		UI.unsaved(self, "This map's layout", _save, func(): dirty = false, _close_now)
		return
	_close_now()


## (Exit without saving keeps the edits on this map until you leave it.)
func _close_now() -> void:
	hide()
	_drag_start = null
	if _cam:
		_cam.offset = _cam_saved["offset"]
		_cam.zoom = _cam_saved["zoom"]
		_cam.position_smoothing_enabled = _cam_saved["smooth"]
		_cam.process_mode = _cam_saved["mode"]
	if _paused_by_me:
		get_tree().paused = false


func _build() -> void:
	_built = true
	_tools = host.editor_tools()
	_panel = PanelContainer.new()
	var style := UI.panel_style(ACCENT)
	style.bg_color = Color(0.03, 0.06, 0.08, 0.93)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(16, 140)
	_panel.custom_minimum_size = Vector2(330, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	v.add_child(UI.label(host.editor_title(), 18, ACCENT))
	v.add_child(UI.section("TOOLS", ACCENT))
	var group := ButtonGroup.new()
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for i in _tools.size():
		var b := Button.new()
		b.text = _tools[i]["label"]
		var tid: String = _tools[i].get("id", "")
		var how := ""
		if _tools[i].get("rect", false):
			how = "\nDrag a rectangle on the map."
		elif _tools[i].get("drag", false):
			how = "\nClick, or hold and drag to keep using it."
		if _tools[i].has("options"):
			how += "\nPick the kind in the list below the tools."
		var more: String = {
			"terrain": "Paints the ground kind chosen in the list (water and crevasses can't be walked on).\nThe brush size ([ / ]) sets how many tiles around the cursor are painted.",
			"building": "Drag a rectangle (at least 3 x 3 tiles) to raise a Minoan building of the chosen style:\npalace, warehouse or temple. Its walls, doors, floors, roof and decor come from the tile sheets.",
			"wall": "Each click cycles the wall under the cursor: plain, window, door. Doors are sliding doors\nthat open as people come near.",
			"column": "Adds a Minoan column on a floor tile inside a building (columns block walking).",
			"npc": "Places a Minoan citizen of the chosen kind where you click: a guard with a laser rifle, or an android\nwith a laser rifle, a laser bow or a labrys (the double axe). They stroll around that spot and shoot anything hostile.",
			"prop": "Places scenery of the chosen kind (trees, palms, bushes, rocks, crystals...) - hold and drag to scatter it.",
			"erase": "Removes what you click (citizens, scenery, columns, buildings) - hold and drag to erase as you go.\nStory ships in space can't be erased.",
			"enemy": "Places a hostile ship of the chosen class where you click.",
			"neutral": "Places a civilian ship (trader, miner, explorer) of the chosen class where you click.",
			"asteroid": "Places an asteroid of the chosen ore where you click.",
		}.get(tid, "")
		how = ("\n" + more if more != "" else "") + how + "\nSave the layout (Ctrl+S) to keep your changes."
		EditorIcons.dress(b, {"terrain": "terrain", "building": "building", "wall": "wall", "column": "column", "npc": "npc",
			"prop": "prop", "erase": "erase", "enemy": "enemy", "neutral": "neutral", "asteroid": "asteroid"}.get(tid, "tool"),
			EditorIcons.tip(_tools[i]["label"], str(i + 1) if i < 9 else "", str(_tools[i].get("help", "")) + how))
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_select_tool.bind(i))
		grid.add_child(b)
		_tool_buttons.append(b)
	_options = OptionButton.new()
	_options.focus_mode = FOCUS_NONE
	_options.add_theme_font_size_override("font_size", 15)
	_options.tooltip_text = EditorIcons.tip("Kind", "", "What the selected tool places or paints.")
	_options.item_selected.connect(func(i): _opt = i)
	v.add_child(_options)
	_brush_row = HBoxContainer.new()
	_brush_row.add_child(UI.label("Brush size", 14, UI.TEXT_DIM))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 4
	slider.step = 1
	slider.value = _brush
	slider.custom_minimum_size = Vector2(140, 24)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.focus_mode = FOCUS_NONE
	var val := UI.label(str(_brush), 14)
	slider.tooltip_text = EditorIcons.tip("Brush size", "[  /  ]", "How many tiles around the cursor the terrain brush paints (0 = one tile).")
	slider.value_changed.connect(func(x): _brush = int(x); val.text = str(_brush))
	_brush_slider = slider
	_brush_row.add_child(slider)
	_brush_row.add_child(val)
	v.add_child(_brush_row)
	v.add_child(UI.section("LAYOUT", ACCENT))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 4)
	v.add_child(lrow)
	lrow.add_child(EditorIcons.dress(UI.button("Save layout", _save, 15), "save",
		EditorIcons.tip("Save layout", "Ctrl+S", "Writes this map (terrain, buildings, citizens, scenery or ships) to its layout file in data/.\nIt's used every time from then on instead of the generated one.")))
	lrow.add_child(EditorIcons.dress(UI.button("Revert to generated", func(): dirty = false; _status.text = host.editor_revert(), 15), "reload",
		EditorIcons.tip("Revert to generated", "", "Deletes the saved layout: the map is generated again (as in a new game) next time it's loaded.")))
	lrow.add_child(EditorIcons.docs_button(self, "level-editor"))
	lrow.add_child(EditorIcons.dress(UI.button("Exit level editor", close, 15), "exit",
		EditorIcons.tip("Exit the level editor", "F10 / Esc", "Back to the game (unsaved edits stay until you leave this map).")))
	_status = UI.label("", 13, UI.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 300
	v.add_child(_status)
	v.add_child(UI.label("Left click: use tool  ·  1-9: pick tool  ·  Wheel: zoom\nWASD / arrows / middle-drag: pan  ·  [ ]: brush\nCtrl+S: save  ·  F1: docs  ·  F10 / Esc: exit  ·  Right-click: editor menu", 13, UI.TEXT_DIM))
	UI.scale_fonts(_panel, "menu", 1.3)
	PinTips.install(self, "level-editor")


func _select_tool(i: int) -> void:
	_tool = i
	(_tool_buttons[i] as Button).set_pressed_no_signal(true)
	var t: Dictionary = _tools[i]
	_options.clear()
	for o in t.get("options", []):
		_options.add_item(str(o))
	_options.visible = _options.item_count > 0
	_opt = 0
	if _options.visible:
		_options.select(0)
	_brush_row.visible = t.get("brush", false)
	_status.text = t.get("help", "")


func _save() -> void:
	var path: String = host.editor_save()
	dirty = path == "" and dirty
	_status.text = ("Saved to " + path) if path != "" else "Save failed."
	GameLog.post("[Dev] Layout saved", "info")


func _world(screen: Vector2) -> Vector2:
	return host.get_viewport().get_canvas_transform().affine_inverse() * screen


func _apply(world: Vector2, phase: String) -> void:
	dirty = true
	var t: Dictionary = _tools[_tool]
	var start: Vector2 = _drag_start if _drag_start != null else world
	host.editor_apply(t["id"], _opt, _brush, world, phase, start)


func _input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()   # (Esc leaves the editor, as F10)
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		var done := true
		if k.keycode >= KEY_1 and k.keycode <= KEY_9 and k.keycode - KEY_1 < _tools.size() and not k.ctrl_pressed:
			_select_tool(k.keycode - KEY_1)
		elif k.ctrl_pressed and k.keycode == KEY_S:
			_save()
		elif k.keycode == KEY_F10:
			get_viewport().set_input_as_handled()
			close()
			return
		elif k.keycode == KEY_F1:
			EditorDocs.open(self, "level-editor", EditorDocs.FILE)
		elif k.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT] and _brush_slider:
			_brush_slider.value += -1 if k.keycode == KEY_BRACKETLEFT else 1
		else:
			done = false
		if done:
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventMouse:
		return
	if _panel.get_global_rect().has_point(event.position) and _drag_start == null and not _panning:
		return  # the tool panel handles it
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var z := _cam.zoom.x * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
					z = clampf(z, 0.25, 3.0)
					_cam.zoom = Vector2(z, z)
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				if UI.middle_click(self, event):
					_cam.zoom = Vector2.ONE   # (a middle click: the zoom back; a middle drag pans)
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					UI.context_menu(self, event.position, [["Save layout  (Ctrl+S)", _save], ["Exit level editor  (F10)", close]])
			MOUSE_BUTTON_LEFT:
				var w := _world(event.position)
				if event.pressed:
					_drag_start = w
					_apply(w, "press")
				elif _drag_start != null:
					_apply(w, "release")
					_drag_start = null
	elif event is InputEventMouseMotion:
		if _panning:
			_cam.offset -= event.relative / _cam.zoom
		elif _drag_start != null and _tools[_tool].get("drag", false):
			_apply(_world(event.position), "drag")
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): d.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): d.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): d.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): d.y += 1
	if d != Vector2.ZERO:
		_cam.offset += d.normalized() * PAN_SPEED * delta / _cam.zoom.x
	queue_redraw()


## Tool cursor: brush circle or the rectangle being dragged.
func _draw() -> void:
	if _tools.is_empty():
		return
	var t: Dictionary = _tools[_tool]
	var mouse := get_local_mouse_position()
	var xf := host.get_viewport().get_canvas_transform()
	if t.get("rect", false) and _drag_start != null:
		var poly: PackedVector2Array = host.editor_rect_polygon(_drag_start, _world(mouse))
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(xf * p)
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(ACCENT, 0.18))
			pts.append(pts[0])
			draw_polyline(pts, ACCENT, 2.0, true)
	elif t.get("brush", false):
		var r := (40.0 + _brush * 90.0) * _cam.zoom.x
		draw_arc(mouse, r, 0, TAU, 48, Color(ACCENT, 0.8), 2.0, true)
	else:
		draw_arc(mouse, 10.0, 0, TAU, 24, ACCENT, 2.0, true)
		draw_line(mouse - Vector2(16, 0), mouse + Vector2(16, 0), Color(ACCENT, 0.6), 1.0)
		draw_line(mouse - Vector2(0, 16), mouse + Vector2(0, 16), Color(ACCENT, 0.6), 1.0)
