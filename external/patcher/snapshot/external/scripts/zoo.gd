extends Node2D
## The asset Library (main menu > Editor > Open the Library). It opens on the
## asset browser (AssetBrowser): every asset of the game sorted by who it
## belongs to - each empire, the Independents, the Sea Peoples, you, the
## monsters, the wildlife, the galaxy, the interface - in categories, with a
## preview and details. "View live" (or a room tab) opens a live room, where
## the assets stand side by side, alive:
##   CHARACTERS  on a planet's grassland: the Minoan androids (rifle, bow,
##               labrys) and the guard walking in all 8 directions, idling,
##               fighting drones and patrolling; the androids' attack views; the pilot (the android, walking
##               around and in its 8 views); the landed ship
##   SHIPS       every ship class, grouped by empire, at their in-game sizes
##   STATIONS    every space-station design, spinning, with who builds it
##   PLANETS     the sun, every planet look and the named planets
##   BUILDINGS   the Minoan tile styles (walls, floors, roofs, columns, decor)
##               and the scenery
##   EFFECTS     the laser arrows on a firing range, every effect sprite
##   MONSTERS    the creatures of the signal sites, alive and animated
## In a room: drag (any mouse button) or WASD / arrows to look around, the
## mouse wheel to zoom, Home to reset the view, Esc back to the browser; Esc in
## the browser (or "Back to Talos") leaves.

## The rooms' names on their tabs (short: eleven share the bar).
const ROOM_LABELS := ["People", "Ships", "Stations", "Planets", "Rocks", "Suns", "Nebulae", "Buildings", "Effects", "GUI", "Monsters"]
const ROOMS := ["CHARACTERS", "SHIPS", "STATIONS", "PLANETS", "ASTEROIDS", "SUNS", "NEBULAE", "BUILDINGS", "EFFECTS", "GUI", "MONSTERS"]
const EDITOR_SCENE := "res://editor.tscn"
const ACCENT := Color(0.4, 0.95, 0.75)
const PROPS := preload("res://scripts/surface_props.gd")
const PROP_KINDS := {"tree": Color(0.25, 0.55, 0.25), "palm": Color(0.3, 0.6, 0.25), "bush": Color(0.3, 0.5, 0.22),
	"tuft": Color(0.45, 0.65, 0.3), "flowers": Color(0.85, 0.4, 0.6), "rock": Color(0.5, 0.48, 0.45),
	"boulder": Color(0.45, 0.43, 0.4), "pebbles": Color(0.55, 0.52, 0.48), "crystal": Color(0.4, 0.75, 1.0),
	"shard": Color(0.7, 0.45, 1.0)}
## Per room: [camera start, zoom].
const VIEW := {"CHARACTERS": [Vector2(-150, -1450), 0.6], "SHIPS": [Vector2(1050, 560), 0.5],
	"STATIONS": [Vector2(1400, 520), 0.42], "PLANETS": [Vector2(1500, 450), 0.45], "ASTEROIDS": [Vector2(1300, 380), 0.5], "SUNS": [Vector2(1650, 0), 0.32], "NEBULAE": [Vector2(2400, 700), 0.25],
	"BUILDINGS": [Vector2(-850, -1000), 0.5], "EFFECTS": [Vector2(560, -100), 0.65], "GUI": [Vector2(380, 300), 1.0],
	"MONSTERS": [Vector2(4750, 0), 0.135]}

## The room the Library opens in (when it opens in a live room).
static var start_room := 0
## Opens in the browser (true) or the last live room.
static var start_browser := true
var browser: AssetBrowser
## Where the rooms put an asset: spot key (a ship class, a station design) -> position.
var _spots := {}

var room := 0
var world: Node2D                   # the current room's exhibits (y-sorted)
var labels: Node2D                  # name plates, above everything
var ground: Node2D                  # the room's floor (not y-sorted with the exhibits)
var cam: Camera2D
var _bg: CanvasLayer                # the current room's backdrop
var _bar: HBoxContainer
var _drag := false
var _drag_button := MOUSE_BUTTON_LEFT   # (the button that started it)
var _zoom := 1.0
var _t := 0.0
var _ui_layer: CanvasLayer
var _press_at := Vector2.ZERO        # where the left button went down (click vs drag)
## Procedural exhibits that can be selected and edited (planets, suns, nebulae):
## {kind, holder, spec, orig, pick_r, size}.
var _pickables: Array = []
var _sel := {}
var _panel: PropertyPanel
var _undo: Array = []                # [entry, key, old value, new value]
var _redo: Array = []
var _clip := {}                      # {kind, look} copied with Copy
var _sel_ring: Node2D


# --- Helpers used by the exhibits ------------------------------------------------------

## A pen for a wandering character: walkable inside its rectangle, straight paths.
class Pen extends Node:
	var rect := Rect2()

	func walkable_at(p: Vector2, _r := 0.0) -> bool:
		return rect.has_point(p)

	func find_path(_from: Vector2, to: Vector2) -> PackedVector2Array:
		return PackedVector2Array([to])


## A character (the guard; a pirate) walking on the spot toward one of the 8 directions.
class Walker extends Node2D:
	var dir := Vector2.RIGHT
	var rig := "gunner"
	var puppet: SheetPuppet

	func _ready() -> void:
		puppet = SheetPuppet.new()
		add_child(puppet)
		puppet.setup(rig)
		puppet.set_facing(dir)
		puppet.walk = 1.0

	func _process(delta: float) -> void:
		puppet.phase += 62.0 * delta / puppet.stride * TAU

	func _draw() -> void:
		SurfaceProps.shadow(self, 22, 8)


## The pilot walking round a loop (turning through every view).
class PilotWalk extends Node2D:
	var pilot: Node2D
	var _t := 0.0

	func _ready() -> void:
		pilot = PROPS.Pilot.new()
		add_child(pilot)

	func _process(delta: float) -> void:
		_t += delta
		pilot.moving = true
		pilot.position = Vector2(cos(_t * 0.6) * 150.0, sin(_t * 0.6) * 75.0)


## A sprite on show: gently swaying (ships), spinning (stations), pulsing
## (glows) or bobbing.
class Exhibit extends Node2D:
	var texture: Texture2D
	var mode := "sway"
	var size := 100.0                # longest side on screen, px
	var tint := Color.WHITE
	var additive := false
	var _t := 0.0

	func _ready() -> void:
		_t = randf() * 20.0
		if additive:
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			material = m

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var k := size / maxf(texture.get_width(), texture.get_height())
		var rot := 0.0
		var s := 1.0
		var off := Vector2.ZERO
		match mode:
			"sway": rot = sin(_t * 0.6) * 0.12
			"spin": rot = _t * 0.042
			"pulse": s = 1.0 + 0.08 * sin(_t * 3.0)
			"bob": off = Vector2(0, sin(_t * 1.4) * 6.0)
		draw_set_transform(off, rot, Vector2(k, k) * s)
		draw_texture(texture, -texture.get_size() / 2.0, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A target for the guard: a hovering drone, never destroyed.
class Drone extends Node2D:
	var _t := 0.0
	var _hit := 0.0

	func surface_hit(_d: float, _dtype := "") -> void:
		_hit = 1.0

	func _process(delta: float) -> void:
		_t += delta
		_hit = move_toward(_hit, 0.0, delta * 4.0)
		queue_redraw()

	func _draw() -> void:
		SurfaceProps.shadow(self, 20, 7)
		var c := Vector2(0, -46 + sin(_t * 2.0) * 5.0)
		draw_circle(c, 17, Color(0.25, 0.22, 0.3))
		draw_circle(c, 11, Color(1.0, 0.25, 0.2).lerp(Color.WHITE, _hit))
		draw_arc(c, 24, _t * 3.0, _t * 3.0 + 2.0, 12, Color(0.6, 0.6, 0.7), 3.0, true)
		draw_arc(c, 24, _t * 3.0 + PI, _t * 3.0 + PI + 2.0, 12, Color(0.6, 0.6, 0.7), 3.0, true)


# --- Scene ---------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("hot_buildings")   # (LiveLink: reskin_buildings when the tiles change)
	NeonTheme.set_empire("")
	Galaxy.active = false
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_build_ui()
	if start_browser:
		show_browser()
	else:
		show_room(start_room)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_ui_layer = layer
	# Talos's rail down the left: every tool, one click away.
	# (exactly where it is on the other Talos screens: TalosNav.AT)
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UI.panel_style(Color(ACCENT, 0.7)))
	frame.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	frame.offset_left = 12
	frame.offset_right = TalosNav.AT.x + TalosNav.WIDTH + 20
	frame.offset_top = 10
	frame.offset_bottom = -10
	layer.add_child(frame)
	var nav := TalosNav.rail("library", func(id): TalosNav.go(get_tree(), id))
	nav.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	nav.offset_left = TalosNav.AT.x
	nav.offset_right = TalosNav.AT.x + TalosNav.WIDTH
	nav.offset_top = TalosNav.AT.y
	nav.offset_bottom = -TalosNav.AT.y
	layer.add_child(nav)
	var left := int(frame.offset_right) + 10   # (past the rail's frame)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.panel_style(Color(ACCENT, 0.7)))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = left
	top.offset_right = -12
	top.offset_top = 10
	layer.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	# The title, with room on both sides.
	var title_box := MarginContainer.new()
	title_box.add_theme_constant_override("margin_left", 10)
	title_box.add_theme_constant_override("margin_right", 6)
	var zt := UI.label("LIBRARY", 24, ACCENT)
	zt.add_theme_font_override("font", NeonTheme.heavy_font())
	zt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title_box.add_child(zt)
	row.add_child(title_box)
	var bb := EditorIcons.dress(UI.button("", show_browser, 15), "fit_all", EditorIcons.tip("Asset browser", "Esc in a room",
		"Every asset, sorted by who it belongs to: the empires, the Independents, the Sea Peoples, you, monsters, wildlife,\nthe galaxy, the interface - with previews and details. The tabs on the right are the live rooms."))
	bb.toggle_mode = true
	bb.name = "BrowserButton"
	row.add_child(bb)
	_bar = UI.tab_bar(ROOMS, show_room, ACCENT)
	var info := [["characters", "The Minoan citizens on a planet's grassland: the androids (rifle, bow, labrys) and the guard walking in all 8 directions,\nidling, fighting and patrolling; the pilot (the android, in its 8 views)\nand your landed ship."],
		["ships", "Every ship class at its in-game size, grouped: your ship, independent, civilian, each empire's, the bosses."],
		["stations", "Every space-station design, spinning as in the game, with the empires that build it."],
		["planets", "The seven planet templates, the named planets and every planet of the galaxy\n(each one generated from the templates and different from all the others)."],
		["asteroid", "The two asteroid templates (contact binary, craggy rock), each ore type's rocks\nand a field of variants, each one generated from them and different from all the others."],
		["suns", "The six star templates (yellow sun, brown dwarf, white star, pulsar, magnetar, red giant)\nand every system's sun, each one generated from them and different from all the others."],
		["nebulae", "The four backdrop templates (supernova remnant, planetary nebula, emission nebula, spiral galaxy)\nand every system's nebulae, each one generated from them and different from all the others."],
		["buildings", "The Minoan building styles: every wall (both ways), floor, roof, column, roof piece and decor; the scenery."],
		["effects", "The laser arrows on a firing range (each with its impact burst) and every effect sprite, glowing."],
		["gui", "The interface itself: every kind of widget on a sample board. Its look (colours, panels,\ncorners, borders, glow) is edited in the property panel - live, on every window."],
		["enemy", "The creatures, alive: Skylla, the sea witch of the signal sites, the Minotaur - the main quest's\nlast boss - (both traced from their reference art) and the Void Leviathan."]]
	for i in _bar.get_child_count():
		var tb: Button = _bar.get_child(i)
		# Its icon and a short name (eleven rooms share the bar: the plain font,
		# tight padding).
		tb.text = ROOM_LABELS[i]
		tb.add_theme_font_override("font", ThemeDB.fallback_font)
		tb.add_theme_font_size_override("font_size", 14)
		tb.clip_text = false
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var sb := tb.get_theme_stylebox(st)
			if sb:
				sb = sb.duplicate()
				sb.content_margin_left = 7
				sb.content_margin_right = 7
				tb.add_theme_stylebox_override(st, sb)
		EditorIcons.dress_tab(tb, info[i][0], EditorIcons.tip(ROOMS[i].capitalize(), str((i + 1) % 10) if i < 10 else "", info[i][1]))
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bar)
	var rv := EditorIcons.dress(UI.button("", _reset_view, 16), "reload", EditorIcons.tip("Reset view", "Home", "Moves the camera back to the room's starting position and zoom.\nLook around with a drag, WASD or the arrows; zoom with the wheel or + / -."))
	row.add_child(rv)
	row.add_child(EditorIcons.docs_button(self, "zoo"))
	var hint := UI.label("Browser: pick an owner and a category, click a card, double-click (or View live) to see it alive  ·  rooms: 1-9, 0, drag / WASD to look, wheel to zoom, Home to reset, Esc back to the browser  ·  F1: documentation", 14, UI.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = left + 6
	hint.offset_top = -34
	layer.add_child(hint)
	browser = AssetBrowser.new()
	browser.name = "AssetBrowser"
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.offset_left = left
	browser.offset_right = -12
	browser.offset_top = 76
	browser.offset_bottom = -44
	browser.view_live.connect(view_live)
	layer.add_child(browser)
	layer.move_child(browser, 0)
	UI.scale_fonts(layer, "menu", 1.5)
	PinTips.install(self, "zoo")


## The asset browser (the rooms put away).
func show_browser() -> void:
	_deselect()
	_pickables = []
	start_browser = true
	for n in [world, labels, ground, _bg]:
		if n:
			n.queue_free()
	world = null
	labels = null
	ground = null
	_bg = null
	UI.select_tab(_bar, -1)
	var bb := _ui_layer.find_child("BrowserButton", true, false)
	if bb:
		bb.set_pressed_no_signal(true)
	browser.show()


## "View live": the room showing an asset, the view on it if the room knows where.
func view_live(room_name: String, spot := "") -> void:
	var i := ROOMS.find(room_name)
	if i < 0:
		return
	show_room(i)
	if spot != "" and _spots.has(spot):
		cam.position = _spots[spot]
		_zoom = 0.9
		cam.zoom = Vector2(_zoom, _zoom)


## Hot reload (LiveLink): the tiles or building styles changed - the room is
## built again (the Buildings room shows every style's pieces as they are now).
func reskin_buildings() -> int:
	if ROOMS[room] == "BUILDINGS":
		var keep := [cam.position, _zoom]
		show_room(room)
		cam.position = keep[0]
		_zoom = keep[1]
		cam.zoom = Vector2(_zoom, _zoom)
	return 1


func _leave() -> void:
	TalosNav.go(get_tree(), "menu")   # (Esc in the browser: as the rail's Exit)


func show_room(index: int) -> void:
	_deselect()
	_pickables = []
	_spots = {}
	room = index
	start_room = index
	start_browser = false
	if browser:
		browser.hide()
		var bb := _ui_layer.find_child("BrowserButton", true, false)
		if bb:
			bb.set_pressed_no_signal(false)
	UI.select_tab(_bar, index)
	for n in [world, labels, ground, _bg]:
		if n:
			n.queue_free()
	_bg = CanvasLayer.new()
	_bg.layer = -2
	add_child(_bg)
	ground = Node2D.new()
	ground.z_index = -10
	add_child(ground)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	labels = Node2D.new()
	labels.z_index = 60
	add_child(labels)
	match ROOMS[index]:
		"CHARACTERS": _room_characters()
		"SHIPS": _room_ships()
		"STATIONS": _room_stations()
		"PLANETS": _room_planets()
		"ASTEROIDS": _room_asteroids()
		"SUNS": _room_suns()
		"NEBULAE": _room_nebulae()
		"BUILDINGS": _room_buildings()
		"EFFECTS": _room_effects()
		"GUI": _room_gui()
		"MONSTERS": _room_monsters()
	_fit_plates()
	_reset_view()


func _reset_view() -> void:
	var v: Array = VIEW[ROOMS[room]]
	cam.position = v[0]
	_zoom = v[1]
	cam.zoom = Vector2(_zoom, _zoom)


## True while the mouse is over the Library's own interface (the property
## panel, the top bar...): its wheel, clicks and drags belong to that, not
## to the view underneath.
func _over_ui(pos: Vector2) -> bool:
	if _panel and _panel.visible and _panel.get_global_rect().has_point(pos):
		return true
	for c in _ui_layer.get_children():
		if c is Control and c.visible and c != _panel and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and (c as Control).get_global_rect().has_point(pos):
			return true
	return false


## A drag that began on the view follows the mouse wherever it goes - over
## the property panel, the top bar - until its button is let go: handled here,
## before the interface, which would otherwise take the motion and the release.
func _input(event: InputEvent) -> void:
	if not _drag:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & (1 << (_drag_button - 1)) == 0:
			_drag = false   # (let go somewhere the release never reached us)
			return
		cam.position -= mm.relative / _zoom
	elif event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		_drag = false


func _unhandled_input(event: InputEvent) -> void:
	if browser and browser.visible:
		# (the browser's own controls take the clicks, the wheel, the keys)
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_leave()
			elif event.keycode == KEY_F1:
				EditorDocs.open(self, "zoo", EditorDocs.FILE)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and _over_ui(mb.position):
			return   # (a scroll at the end of the panel's list, a click on its margin...)
		if UI.middle_click(self, mb):
			_reset_view()   # (a middle click: the zoom back; a middle drag pans)
			return
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			var before := get_global_mouse_position()
			_zoom = clampf(_zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 0.12, 3.0)
			cam.zoom = Vector2(_zoom, _zoom)
			cam.position += before - get_global_mouse_position()   # zoom about the mouse
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_drag = true
				_drag_button = mb.button_index
			# A left click (not a drag) selects a procedural exhibit.
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press_at = mb.position
				elif mb.position.distance_to(_press_at) < 6.0:
					pick(get_canvas_transform().affine_inverse() * mb.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc == KEY_HOME:
			_reset_view()
		elif event.ctrl_pressed and not _sel.is_empty() and kc in [KEY_Z, KEY_Y, KEY_C, KEY_V]:
			if kc == KEY_Z and not event.shift_pressed:
				undo()
			elif kc == KEY_Y or kc == KEY_Z:
				redo()
			elif kc == KEY_C:
				copy_look()
				_panel._copy()
			else:
				paste()
		elif kc == KEY_ESCAPE:
			if not _sel.is_empty():
				_deselect()
			else:
				show_browser()
		elif kc == KEY_F1:
			EditorDocs.open(self, "zoo", EditorDocs.FILE)
		elif kc >= KEY_1 and kc <= KEY_9 and kc - KEY_1 < ROOMS.size():
			show_room(kc - KEY_1)
		elif kc == KEY_0 and ROOMS.size() >= 10:
			show_room(9)
		elif kc in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom = clampf(_zoom * (1.2 if kc in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD] else 1.0 / 1.2), 0.12, 3.0)
			cam.zoom = Vector2(_zoom, _zoom)


func _process(delta: float) -> void:
	_t += delta
	if browser and browser.visible:
		return   # (no room to look around)
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return   # (typing a value in the property panel: no camera keys)
	var v := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	for k in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_physical_key_pressed(k[0]):
			v += k[1]
	if v != Vector2.ZERO:
		cam.position += v.normalized() * 900.0 * delta / _zoom


# --- Building blocks ---------------------------------------------------------------------

## A name plate centred under / over an exhibit.
func _plate(text: String, at: Vector2, size := 18, color := Color(0.92, 0.95, 1.0), width := 360.0) -> Label:
	# Readable at the room's starting zoom.
	var k := 0.75 / float(VIEW[ROOMS[room]][1])
	size = roundi(size * k)
	width *= k
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(width, 0)
	l.position = at - Vector2(width / 2.0, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(4, size / 3))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	labels.add_child(l)
	return l


## The text a plate draws (not its whole box): centred in its width.
static func plate_text_rect(l: Label) -> Rect2:
	var font: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var sz := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, l.size.x, fs, -1, brk)
	var lines := maxi(1, roundi(sz.y / font.get_height(fs)))
	sz.y += (lines - 1) * l.get_theme_constant("line_spacing")
	var pad := float(l.get_theme_constant("outline_size")) / 2.0
	return Rect2(l.position + Vector2((l.size.x - sz.x) / 2.0, 0), sz).grow(pad)


func _plates() -> Array:
	return labels.get_children().filter(func(l): return l is Label and l.visible and l.text.strip_edges() != "")


## Pairs of plates whose text overlaps ([label, label]).
func plate_overlaps() -> Array:
	var ls := _plates()
	var rects := ls.map(func(l): return plate_text_rect(l))
	var out := []
	for i in ls.size():
		for j in range(i + 1, ls.size()):
			if rects[i].intersects(rects[j]):
				out.append([ls[i], ls[j]])
	return out


## No plate's text over another's: plates side by side wrap narrower (to the
## room between them), then their text shrinks (down to half); plates still
## in each other's way (one above the other) - the lower one moves down.
func _fit_plates() -> void:
	for l in _plates():
		l.set_meta("fs0", l.get_theme_font_size("font_size"))
	for step in 400:
		var hits := plate_overlaps()
		if hits.is_empty():
			return
		var a: Label = hits[0][0]
		var b: Label = hits[0][1]
		var fa: int = a.get_theme_font_size("font_size")
		var fb: int = b.get_theme_font_size("font_size")
		var gap := 0.5 * maxf(fa, fb)
		var dx := absf((a.position.x + a.size.x / 2.0) - (b.position.x + b.size.x / 2.0))
		var room := dx - gap
		if room > 2.0 * maxf(fa, fb) and (a.size.x > room + 1.0 or b.size.x > room + 1.0):
			for l in [a, b]:
				if l.size.x > room:
					var c: float = l.position.x + l.size.x / 2.0
					l.size = Vector2(room, 0)
					l.position.x = c - room / 2.0
			continue
		var shrunk := false
		for l in [a, b]:
			var f: int = l.get_theme_font_size("font_size")
			if f > int(l.get_meta("fs0", f)) / 2 and room > 2.0 * f:
				l.add_theme_font_size_override("font_size", maxi(1, int(f * 0.9)))
				l.add_theme_constant_override("outline_size", maxi(2, int(f * 0.9) / 3))
				shrunk = true
		if shrunk:
			continue
		var top: Label = a if a.position.y <= b.position.y else b
		var low: Label = b if top == a else a
		var tr := plate_text_rect(top)
		var lr := plate_text_rect(low)
		low.position.y += tr.end.y - lr.position.y + gap * 0.3


func _heading(text: String, at: Vector2) -> void:
	_plate(text, at, 34, ACCENT, 1400.0)


## The starry dark of space behind a room.
func _space_backdrop() -> void:
	var dark := ColorRect.new()
	dark.color = Color(0.01, 0.01, 0.04)
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (dragging pans the view)
	_bg.add_child(dark)
	var stars: Node2D = preload("res://scripts/starfield.gd").new()
	_bg.add_child(stars)


## A patch of planet surface (Amnissos's grassland, with the game's ground
## shader and brick edges), n x n tiles, centred on `center`.
func _ground(center: Vector2, n: int) -> void:
	var sky := ColorRect.new()
	sky.color = Color(0.05, 0.07, 0.1)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (dragging pans the view)
	_bg.add_child(sky)
	var pdata: Dictionary = Planets.get_planet("thalassa")
	var types: Array = pdata["terrain"]
	var th: Array = pdata["thresholds"]
	var gi := 0
	for i in types.size():
		if types[i][3] == "grass":
			gi = i
	var lo: float = th[gi - 1] if gi > 0 else -1.0
	var hi: float = th[gi] if gi < th.size() else 1.0
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.12
	for i in n:
		for j in n:
			var h := lerpf(lo, hi, 0.45 + 0.4 * noise.get_noise_2d(i, j))
			var v := (h + 1.0) * 0.5
			img.set_pixel(i, j, Color(v, v, v))
	var g2w := Transform2D(Vector2(64, 32), Vector2(-64, 32), center - Vector2(0, 32.0 * n))
	var inv := g2w.affine_inverse()
	var colors := PackedColorArray()
	var kinds := PackedInt32Array()
	for t in types:
		colors.append(t[1])
		kinds.append(Planets.GROUND_KINDS.find(t[3]))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	mat.set_shader_parameter("height_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("grid_n", float(n))
	mat.set_shader_parameter("inv_x", inv.x)
	mat.set_shader_parameter("inv_y", inv.y)
	mat.set_shader_parameter("inv_o", inv.origin)
	mat.set_shader_parameter("count", types.size())
	mat.set_shader_parameter("colors", colors)
	mat.set_shader_parameter("kinds", kinds)
	mat.set_shader_parameter("thresholds", PackedFloat32Array(th))
	mat.set_shader_parameter("seed", float(int(pdata["seed"]) % 97))
	var e := 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([g2w * Vector2(-e, -e), g2w * Vector2(n - e, -e), g2w * Vector2(n - e, n - e), g2w * Vector2(-e, n - e)])
	poly.material = mat
	var edge := Node2D.new()
	edge.set_script(preload("res://scripts/surface_edge.gd"))
	edge.corners = [g2w * Vector2(-e, n - e), g2w * Vector2(n - e, n - e), g2w * Vector2(n - e, -e)]
	ground.add_child(edge)
	ground.add_child(poly)


# --- Rooms ----------------------------------------------------------------------------------

func _room_characters() -> void:
	_ground(Vector2(0, 1400), 150)
	var names := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]
	var y := -2050.0
	# The androids and the guard: walking toward each of the 8 directions.
	for who in [["android_rifle", "THE ANDROID WITH A LASER RIFLE"], ["android_bow", "THE ANDROID WITH A LASER BOW"],
			["android_axe", "THE ANDROID WITH A LABRYS"], ["gunner", "THE GUARD"]]:
		_heading("%s  (sprite sheets: 8 views)  ·  walking in 8 directions" % who[1], Vector2(0, y - 230))
		for i in 8:
			var w := Walker.new()
			w.rig = who[0]
			w.dir = Vector2.from_angle(i * PI / 4.0)
			w.position = Vector2(-700 + i * 200, y)
			world.add_child(w)
			_plate(names[i], w.position + Vector2(0, 14), 16, Color(0.92, 0.95, 1.0), 180.0)
		y += 400.0
	y += 60.0
	_heading("AT WORK", Vector2(0, y - 230))
	# The pilot and the landed ship.
	var pw := PilotWalk.new()
	pw.position = Vector2(-400, y)
	world.add_child(pw)
	_plate("The pilot", pw.position + Vector2(0, 14), 16)
	var lander: Node2D = PROPS.Lander.new()
	lander.position = Vector2(400, y + 10)
	world.add_child(lander)
	_plate("Your ship, landed", lander.position + Vector2(0, 60), 16)
	# The guard: idle at the ready, firing at a drone, patrolling.
	y += 380.0
	var gidle := Walker.new()
	gidle.rig = "gunner"
	gidle.position = Vector2(-1250, y)
	world.add_child(gidle)
	gidle.puppet.walk = 0.0
	gidle.set_process(false)
	_plate("Idle, rifle at the ready", gidle.position + Vector2(0, 14), 15, Color.WHITE, 240.0)
	var guard: Node2D = PROPS.citizen("gunner")
	guard.position = Vector2(-760, y)
	guard.home = guard.position
	guard.wander = 0.0
	world.add_child(guard)
	var drone := Drone.new()
	drone.position = Vector2(-330, y + 40)
	world.add_child(drone)
	guard.watch = drone
	_plate("Firing at a drone\n(shoulder, aim, bursts, recoil, cooling)", Vector2(-560, y + 80), 15, Color.WHITE, 360.0)
	var gpen := Pen.new()
	gpen.rect = Rect2(Vector2(100, y - 150), Vector2(900, 300))
	world.add_child(gpen)
	for k in 2:
		var patrol: Node2D = PROPS.citizen("gunner", 2 + k * 2)
		patrol.position = Vector2(350 + k * 400, y)
		patrol.home = patrol.position
		patrol.wander = 200.0
		patrol.surface = gpen
		world.add_child(patrol)
	_plate("Patrolling", Vector2(550, y + 170), 15)
	# The androids fighting: rifle bursts, single arrows, the labrys hand to hand.
	y += 420.0
	var kinds := [["android", "Rifle: bursts of bolts"], ["android_bow", "Bow: one arrow at a time"], ["android_axe", "Labrys: closes in and cleaves"]]
	for k in kinds.size():
		var a: Node2D = PROPS.citizen(kinds[k][0], k)
		a.position = Vector2(-1250 + k * 900, y)
		a.home = a.position
		a.wander = 0.0
		world.add_child(a)
		var d := Drone.new()
		d.position = a.position + Vector2(420 if k < 2 else 200, 40)
		world.add_child(d)
		a.watch = d
		_plate(kinds[k][1], a.position + Vector2(200, 100), 15, Color.WHITE, 320.0)
	var apen := Pen.new()
	apen.rect = Rect2(Vector2(-1300, y + 230), Vector2(2600, 300))
	world.add_child(apen)
	for k in 3:
		var patrol: Node2D = PROPS.citizen(kinds[k][0], 4 + k)
		patrol.position = Vector2(-800 + k * 800, y + 380)
		patrol.home = patrol.position
		patrol.wander = 250.0
		patrol.surface = apen
		world.add_child(patrol)
	_plate("Patrolling", Vector2(0, y + 550), 15)
	y += 420.0
	_room_pilot_views(y + 520.0)
	_room_guard_aiming(y + 1240.0)
	_room_android_poses(y + 1640.0)
	_room_pirate(y + 3380.0)
	# Scenery around the edges.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40:
		var p := Vector2(rng.randf_range(-1900, 1900), rng.randf_range(-2700, 5400))
		if absf(p.x) < 1700 and p.y > -2500 and p.y < 5200:
			continue   # keep the exhibits clear
		var pr: Node2D = PROPS.Prop.new()
		pr.kind = ["tree", "bush", "flowers", "tuft", "rock"][i % 5]
		pr.color = PROP_KINDS[pr.kind]
		pr.variant = i
		pr.position = p
		world.add_child(pr)


## The pirate raider (planet surfaces' hostiles): its 8 views, walking.
func _room_pirate(y: float) -> void:
	_heading("PIRATE RAIDER  ·  8 views  ·  shoots you and the citizens", Vector2(-200, y - 300))
	var names := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]
	for i in 8:
		var w := Walker.new()
		w.rig = "pirate"
		w.dir = Vector2.from_angle(i * PI / 4.0)
		w.position = Vector2(-700 + i * 200, y)
		world.add_child(w)
		_plate(names[i], w.position + Vector2(0, 14), 15, Color(0.92, 0.95, 1.0), 180.0)
	# Four moments of its attack (12 frames: raising the rifle, then firing),
	# and one firing at a drone.
	var y2 := y + 330.0
	for k in 4:
		var w := Walker.new()
		w.rig = "pirate"
		w.dir = Vector2(0, 1)
		w.position = Vector2(-700 + k * 170, y2)
		world.add_child(w)
		w.puppet.walk = 0.0
		w.puppet.raise_amt = k / 3.0
		w.set_process(false)
		_plate(["Rifle down (idle)", "Raising", "At the hip", "Aimed (firing)"][k], w.position + Vector2(0, 14), 15, Color.WHITE, 170.0)
	var p: Node2D = PROPS.citizen("pirate", 1)
	p.position = Vector2(100, y2)
	p.home = p.position
	p.wander = 0.0
	world.add_child(p)
	var drone := Drone.new()
	drone.position = Vector2(500, y2 + 30)
	world.add_child(drone)
	p.watch = drone
	_plate("Raising the rifle and firing at a drone", Vector2(300, y2 + 80), 15, Color.WHITE, 360.0)


## The guard's aiming pose: its 8 views.
func _room_guard_aiming(y: float) -> void:
	_heading("THE GUARD  ·  aiming, 8 views", Vector2(-200, y - 300))
	var names := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]
	for i in 8:
		var w := Walker.new()
		w.rig = "gunner"
		w.dir = Vector2.from_angle(i * PI / 4.0)
		w.position = Vector2(-700 + i * 200, y)
		world.add_child(w)
		w.puppet.walk = 0.0
		w.puppet.raise_amt = 1.0
		w.set_process(false)
		_plate(names[i], w.position + Vector2(0, 14), 15, Color(0.92, 0.95, 1.0), 180.0)


## The androids' attack pictures in their 8 views: the rifle aimed, the bow
## drawn, the labrys wound up and striking.
func _room_android_poses(y: float) -> void:
	var names := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]
	var rows := [["android_rifle", 1.0, "THE ANDROID  ·  rifle aimed"], ["android_bow", 1.0, "THE ANDROID  ·  bow drawn"],
		["android_axe", 0.5, "THE ANDROID  ·  labrys wound up"], ["android_axe", 1.0, "THE ANDROID  ·  labrys striking"]]
	for r in rows.size():
		var ry: float = y + r * 400.0
		_heading("%s, 8 views" % rows[r][2], Vector2(-200, ry - 230))
		for i in 8:
			var w := Walker.new()
			w.rig = rows[r][0]
			w.dir = Vector2.from_angle(i * PI / 4.0)
			w.position = Vector2(-700 + i * 200, ry)
			world.add_child(w)
			w.puppet.walk = 0.0
			w.puppet.raise_amt = rows[r][1]
			w.set_process(false)
			_plate(names[i], w.position + Vector2(0, 14), 15, Color(0.92, 0.95, 1.0), 180.0)


## You on foot: the 8 relaxed views and the 8 aiming ones.
func _room_pilot_views(y: float) -> void:
	_heading("YOU ON FOOT  ·  8 views, relaxed and firing", Vector2(-200, y - 300))
	var names := ["East", "South-east", "South", "South-west", "West", "North-west", "North", "North-east"]
	for row in 2:
		for i in 8:
			var p: Node2D = PROPS.Pilot.new()
			p.heading = Vector2.from_angle(i * PI / 4.0)
			p.position = Vector2(-700 + i * 200, y + row * 300)
			world.add_child(p)
			if row == 1:
				p.set_process(false)
				p.puppet.raise_amt = 1.0   # the aiming pose (in the game: only while you fire)
			_plate(names[i], p.position + Vector2(0, 14), 15, Color(0.92, 0.95, 1.0), 180.0)


func _room_ships() -> void:
	_space_backdrop()
	var groups := {}
	var t := EnemyTypes.types()
	for id in t:
		var d: Dictionary = t[id]
		# By who flies it (ShipDesigns.owner_of): each empire, the
		# Independents, the Sea Peoples; the bosses apart.
		var g := "Bosses" if d.get("unique", false) else _empire_name(ShipDesigns.owner_of(id) if ShipDesigns.owner_of(id) != "" else "independent")
		if not groups.has(g):
			groups[g] = []
		groups[g].append(id)
	var y := 0.0
	_heading("SHIPS  ·  every class at its in-game size", Vector2(1100, y - 260))
	# The player's own ship first.
	var order := ["Player"] + groups.keys()
	groups["Player"] = ["player"]
	for g in order:
		var ids: Array = groups[g]
		ids.sort()
		_plate(g.to_upper() + "  (%d)" % ids.size(), Vector2(1100, y - 170), 24, ACCENT, 1200.0)
		var x := 0.0
		var row_h := 0.0
		var col := 0
		for id in ids:
			var d: Dictionary = t.get(id, {})
			var tex: Texture2D = ProcArt.get_tex("ship_player") if id == "player" else EnemyTypes.texture(id)
			var length: float = d.get("length", EnemyTypes.MIN_LENGTH)
			var ex := Exhibit.new()
			ex.texture = tex
			ex.size = length
			ex.tint = d.get("tint", Color.WHITE)
			ex.position = Vector2(x + length / 2.0, y)
			world.add_child(ex)
			_spots[id] = ex.position
			_plate(str(d.get("name", "Your ship" if id == "player" else id)).replace("-class ", "-class\n"), ex.position + Vector2(0, length / 2.0 + 18), 13, Color.WHITE, maxf(170.0, length * 0.7))
			x += maxf(280.0, length + 80.0)
			row_h = maxf(row_h, length)
			col += 1
			if col == 8:
				col = 0
				x = 0.0
				y += row_h + 140.0
				row_h = 0.0
		y += row_h + 300.0


func _empire_name(e: String) -> String:
	return str(Galaxy.empire_name(e))


func _room_stations() -> void:
	_space_backdrop()
	_heading("SPACE STATIONS  ·  every design, spinning as in the game, by who builds it", Vector2(1400, -420))
	# A row (or two) per owner.
	var y := 0.0
	for e in StationArt.BY_EMPIRE:
		_plate(_empire_name(e).to_upper() + "  (%d)" % StationArt.BY_EMPIRE[e].size(), Vector2(1400, y - 300), 24, ACCENT, 1200.0)
		var i := 0
		for dsg in StationArt.BY_EMPIRE[e]:
			var ex := Exhibit.new()
			ex.texture = ProcArt.station_texture(dsg)
			ex.mode = "spin"
			ex.size = 440.0
			ex.position = Vector2((i % 6) * 560.0, y + (i / 6) * 640.0)
			world.add_child(ex)
			_spots[dsg] = ex.position
			_plate(StationArt.DESIGNS[dsg]["name"], ex.position + Vector2(0, 245), 17, Color.WHITE, 480.0)
			i += 1
		y += ceilf(i / 6.0) * 640.0 + 160.0


func _room_planets() -> void:
	_space_backdrop()
	_heading("PLANETS  ·  the seven templates, the named worlds, every planet of the galaxy", Vector2(1800, -520))
	var i := 0
	for t in PlanetGen.TEMPLATES:
		_planet_exhibit(PlanetGen.generate(t, 0), Vector2(i * 560.0, 0.0), "Template: " + PlanetGen.TEMPLATES[t]["name"])
		i += 1
	var y := 800.0
	_plate("NAMED PLANETS", Vector2(1800, y - 230), 26, ACCENT, 1000.0)
	i = 0
	for id in Planets.PLANETS:
		var p: Dictionary = Planets.PLANETS[id]
		_planet_exhibit(Planets.spec(id), Vector2(i * 560.0, y), "%s\n%s" % [p.get("name", id), p.get("desc", "")])
		i += 1
	# Every planet of the galaxy: the templates mixed and recoloured, no two alike.
	if Galaxy.systems.is_empty():
		Galaxy.new_game(false, true)   # (the map only: Talos lists its places, never runs it)
		Galaxy.active = false
	y += 820.0
	_plate("EVERY PLANET OF THE GALAXY  ·  generated from the templates, each one different", Vector2(1800, y - 230), 26, ACCENT, 1600.0)
	i = 0
	for sid in Galaxy.SYSTEMS:
		for pl in Galaxy.systems[sid]["planets"]:
			var spec := PlanetGen.generate(pl["template"], pl["variant"])
			_planet_exhibit(spec, Vector2((i % 8) * 560.0, y + (i / 8) * 640.0), "%s\n%s" % [pl["name"], PlanetGen.describe(spec)])
			i += 1


func _room_asteroids() -> void:
	_space_backdrop()
	_heading("ASTEROIDS  ·  the two templates, each ore's rocks, a field of variants", Vector2(1300, -560))
	var i := 0
	for t in AsteroidGen.TEMPLATES:
		var spec := AsteroidGen.generate(t, 0)
		_asteroid_exhibit(spec, Vector2(700.0 + i * 1000.0, -150.0), 260.0, "Template: " + spec["name"])
		i += 1
	var y := 650.0
	_plate("EACH ORE  ·  iron (rust), titanium (cyan veins), platinum (gold veins)", Vector2(1300, y - 260), 26, ACCENT, 1600.0)
	i = 0
	for ore in Asteroid.KINDS:
		for s in [0, 1]:
			var spec := AsteroidGen.for_rock(ore, 3 * i + 7 * s + (0 if s == 0 else 1), false)
			_asteroid_exhibit(spec, Vector2((i * 2 + s) * 440.0 + 200.0, y), 130.0,
				"%s\n%s" % [Asteroid.KINDS[ore]["name"], AsteroidGen.describe(spec)] if s == 0 else AsteroidGen.describe(spec))
		i += 1
	y += 620.0
	_plate("A FIELD OF VARIANTS  ·  generated from the templates, each one different", Vector2(1300, y - 200), 26, ACCENT, 1600.0)
	for n in 24:
		var t: String = AsteroidGen.TEMPLATES.keys()[n % 2]
		var spec := AsteroidGen.generate(t, n + 1)
		_asteroid_exhibit(spec, Vector2((n % 8) * 470.0 - 340.0, y + (n / 8) * 440.0), 120.0, AsteroidGen.describe(spec))


func _asteroid_exhibit(spec: Dictionary, at: Vector2, r: float, text: String) -> void:
	_exhibit("asteroid", spec, at, r, r * 0.9)
	_plate(text, at + Vector2(0, r * 1.05 + 20.0), 16, Color.WHITE, maxf(r * 2.4, 300.0))


func _room_suns() -> void:
	_space_backdrop()
	_heading("SUNS  ·  the six star templates, every system's sun", Vector2(1650, -1450))
	var i := 0
	for t in StarGen.TEMPLATES:
		var spec := StarGen.generate(t, 0)
		_star_exhibit(spec, Vector2(i * 1100.0 - 1100.0, -650.0), "Template: " + spec["name"])
		i += 1
	_plate("EVERY SYSTEM'S SUN  ·  generated from the templates, each one different", Vector2(1650, 300), 30, ACCENT, 2000.0)
	i = 0
	for id in Galaxy.SYSTEMS:
		var st: Dictionary = Galaxy.STARS[Galaxy.SYSTEMS[id]["star"]]
		var spec := Galaxy.star_spec(id)
		_star_exhibit(spec, Vector2((i % 6) * 1100.0 - 1100.0, 1050.0 + (i / 6) * 1150.0),
			"%s  ·  %s\n%s" % [Galaxy.SYSTEMS[id]["name"], st["name"], StarGen.describe(spec)])
		i += 1


func _room_nebulae() -> void:
	_space_backdrop()
	_heading("NEBULAE  ·  the four templates, every system's backdrop", Vector2(2400, -1500))
	var i := 0
	for t in NebulaGen.TEMPLATES:
		var spec := NebulaGen.generate(t, 0)
		_nebula_exhibit(spec, Vector2(i * 1700.0, -400.0), 1500.0, "Template: " + spec["name"])
		i += 1
	_plate("EVERY SYSTEM'S NEBULAE  ·  generated from the templates, each one different", Vector2(2400, 900), 40, ACCENT, 3000.0)
	i = 0
	for id in Galaxy.SYSTEMS:
		var k := 0
		for n in NebulaGen.for_system(id, Galaxy.SYSTEMS.keys().find(id)):
			_nebula_exhibit(n[0], Vector2((i % 6) * 1000.0, 1900.0 + (i / 6) * 1150.0), 900.0,
				"%s %d\n%s" % [Galaxy.SYSTEMS[id]["name"], k + 1, NebulaGen.describe(n[0])])
			i += 1
			k += 1


func _nebula_exhibit(spec: Dictionary, at: Vector2, size: float, text: String) -> void:
	_exhibit("nebula", spec, at, size, size * 0.42)
	_plate(text, at + Vector2(0, size * 0.5 + 10.0), 18, Color.WHITE, size * 0.28)


## One star; neutron stars are drawn smaller so their loops fit.
func _star_exhibit(spec: Dictionary, at: Vector2, text: String) -> void:
	var r := 110.0 if spec["template"] in StarGen.NEUTRON else 300.0
	_exhibit("star", spec, at, r, r * 1.15)
	_plate(text, at + Vector2(0, 420), 18, Color.WHITE, 600.0)


## One planet, 300 px across (smaller when it has rings, so they fit).
func _planet_exhibit(spec: Dictionary, at: Vector2, text: String) -> void:
	_exhibit("planet", spec, at, 300.0, 160.0)
	_plate(text, at + Vector2(0, 175), 16, Color.WHITE, 300.0)


# --- Procedural exhibits: selection and the property panel -----------------------------

## The generator script of an exhibit kind (PROPERTIES, STRUCTURAL, apply, generate).
static func generator(kind: String) -> GDScript:
	match kind:
		"planet": return PlanetGen
		"star": return StarGen
		"asteroid": return AsteroidGen
		"building": return BuildingLook
		"gui": return GuiLook
	return NebulaGen


## The Themes kind of an exhibit kind.
static func theme_kind(kind: String) -> String:
	return kind


## Places a selectable procedural exhibit: its node is rebuilt from `spec`.
func _exhibit(kind: String, spec: Dictionary, at: Vector2, size: float, pick_r: float) -> Dictionary:
	var holder := Node2D.new()
	holder.position = at
	world.add_child(holder)
	var e := {"kind": kind, "holder": holder, "spec": spec, "orig": spec.duplicate(true), "pick_r": pick_r, "size": size}
	_build_visual(e)
	_pickables.append(e)
	return e


## (Re)builds an exhibit's node from its spec.
func _build_visual(e: Dictionary) -> void:
	if e["kind"] == "gui":
		(e["node"] as Node).set_meta("look", (e["spec"] as Dictionary).duplicate())
		GuiLook.apply_all(e["spec"])
		return
	if e["kind"] == "building":
		var skin: Node = e.get("node")
		if skin == null:
			skin = BuildingLook.skin(e["spec"])
			add_child(skin)
			e["node"] = skin
			for cat in e["items"]:
				BuildingLook.dress(e["items"][cat], skin, cat)
		else:
			skin.set_meta("look", (e["spec"] as Dictionary).duplicate())
			BuildingLook._push(skin)
		return
	var holder: Node2D = e["holder"]
	for c in holder.get_children():
		c.queue_free()
	var spec: Dictionary = e["spec"]
	var node: Control
	match e["kind"]:
		"planet":
			var k := 1.0
			if float(spec.get("rings", 0.0)) > 0.0:
				k = float(spec.get("ring_outer", 2.2)) / 1.25
			node = Planets.make_planet(spec, e["size"], PlanetGen.DISK / k)
			node.position = -node.size / 2.0
		"star":
			node = StarGen.make(spec, e["size"])
		"asteroid":
			# (each rock through its own little view, redrawn in turns: RockView)
			node = AsteroidGen.make(spec, e["size"])
			holder.add_child(RockView.wrap(node))
			e["node"] = node
			return
		_:
			node = NebulaGen.make(spec, e["size"])
			node.position = -node.size / 2.0
	holder.add_child(node)
	e["node"] = node


## A Library rock, drawn into a small view of its own and shown from there:
## the rock shader (ray-marched, lit, noise on noise) on 34 big rocks at once
## took the room's GPU to 4.3 ms a frame. The rocks only turn slowly (a few
## thousandths of a radian between redraws), so each is redrawn REFRESH times
## a second, a few each frame in turn (~0.4 ms each): the same to the eye,
## the room ~1.8 ms a frame. Live edits reach the rock's material as before.
class RockView extends Node2D:
	static var _all: Array = []
	static var _next := 0
	static var _frame := -1
	static var _due := 0.0
	const REFRESH := 20.0
	var _vp: SubViewport

	static func wrap(rock: Control) -> RockView:
		var v := RockView.new()
		var full := rock.size
		var res := Vector2i((full * 0.6).clamp(Vector2(96, 96), Vector2(640, 640)))
		v._vp = SubViewport.new()
		v._vp.size = res
		v._vp.transparent_bg = true
		v._vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		rock.position = Vector2.ZERO
		rock.size = Vector2(res)
		v._vp.add_child(rock)
		v.add_child(v._vp)
		var spr := Sprite2D.new()
		spr.texture = v._vp.get_texture()
		spr.scale = full / Vector2(res)
		v.add_child(spr)
		return v

	func _enter_tree() -> void:
		_all.append(self)

	func _exit_tree() -> void:
		_all.erase(self)

	func _process(d: float) -> void:
		# (the first rock to run each frame asks the next few to redraw)
		if _frame == Engine.get_process_frames():
			return
		_frame = Engine.get_process_frames()
		var n := _all.size()
		_due += n * REFRESH * minf(d, 0.1)
		var count := int(_due)
		_due -= count
		for i in mini(count, n):
			_next = (_next + 1) % maxi(1, n)
			var r: RockView = _all[_next]
			if is_instance_valid(r) and r._vp:
				r._vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## The GUI room: a board with every kind of widget, styled by the game's
## theme; its look (GuiLook) is edited live in the property panel.
var _gui_on_entry := {}

func _room_gui() -> void:
	_space_backdrop()
	_heading("THE INTERFACE  ·  every widget, in the game's theme  ·  edit its look on the right", Vector2(380, -120))
	var board := PanelContainer.new()
	board.position = Vector2(-120, -40)
	board.custom_minimum_size = Vector2(1000, 0)
	world.add_child(board)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	board.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var tabs := TabBar.new()
	for t in ["Market", "Outfitting", "Shipyard", "Missions"]:
		tabs.add_tab(t)
	v.add_child(tabs)
	var title := Label.new()
	title.text = "Kephala Outpost  ·  docking bay 3"
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)
	var dim := Label.new()
	dim.text = "Dim text: hints, captions and placeholders."
	dim.add_theme_color_override("font_color", NeonTheme.TEXT_DIM)
	v.add_child(dim)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for t in ["Buy", "Sell", "Repair"]:
		var b := Button.new()
		b.text = t
		row.add_child(b)
	var tog := Button.new()
	tog.text = "Toggled"
	tog.toggle_mode = true
	tog.button_pressed = true
	row.add_child(tog)
	var dis := Button.new()
	dis.text = "Disabled"
	dis.disabled = true
	row.add_child(dis)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	v.add_child(row2)
	var cb := CheckBox.new()
	cb.text = "Check box"
	cb.button_pressed = true
	row2.add_child(cb)
	var cs := CheckButton.new()
	cs.text = "Switch"
	cs.button_pressed = true
	row2.add_child(cs)
	var ob := OptionButton.new()
	for t in ["Option A", "Option B", "Option C"]:
		ob.add_item(t)
	row2.add_child(ob)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 16)
	v.add_child(row3)
	var le := LineEdit.new()
	le.placeholder_text = "Type here..."
	le.custom_minimum_size = Vector2(260, 0)
	row3.add_child(le)
	var sb := SpinBox.new()
	sb.value = 42
	row3.add_child(sb)
	var sl := HSlider.new()
	sl.value = 60
	sl.custom_minimum_size = Vector2(260, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row3.add_child(sl)
	var pb := ProgressBar.new()
	pb.value = 70
	pb.custom_minimum_size = Vector2(0, 22)
	v.add_child(pb)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = "[b]Rich text[/b] - mission briefings and the encyclopedia: [color=#ffd060]gold[/color] highlights, [i]italics[/i]."
	v.add_child(rt)
	var tip := PanelContainer.new()
	tip.theme_type_variation = "TooltipPanel"
	var tl := Label.new()
	tl.text = "  A tooltip: what a button does, and its shortcut [Ctrl+S]  "
	tl.theme_type_variation = "TooltipLabel"
	tip.add_child(tl)
	v.add_child(tip)
	# The board is one selectable exhibit: the whole GUI's look.
	var holder := Node2D.new()
	holder.position = Vector2(380, 300)
	world.add_child(holder)
	var skin := Node.new()
	holder.add_child(skin)
	_gui_on_entry = NeonTheme.custom.duplicate()
	var spec := GuiLook.generate("neon", 0)
	if not NeonTheme.custom.is_empty():
		spec.merge(NeonTheme.custom, true)
	skin.set_meta("look", spec.duplicate())
	var e := {"kind": "gui", "holder": holder, "node": skin, "spec": spec, "orig": spec.duplicate(true),
		"rect": Rect2(Vector2(-160, -80), Vector2(1080, 760)), "pick_r": 0.0, "size": 0.0, "title": "Interface (GUI)"}
	_pickables.append(e)
	select.call_deferred(e)


func _exit_tree() -> void:
	# The Library's GUI edits are a preview: leaving restores the look you
	# came in with (save a preset to keep one).
	if NeonTheme.custom != _gui_on_entry:
		NeonTheme.apply_look(_gui_on_entry)


## Selects the procedural exhibit under `world_pos` (none: deselects).
func pick(world_pos: Vector2) -> void:
	var best := {}
	var best_d := INF
	for e in _pickables:
		if not is_instance_valid(e["holder"]):
			continue
		var d: float
		if e.has("rect"):
			if not (e["rect"] as Rect2).has_point(world_pos):
				continue
			d = 1e6   # (an area: anything closer wins)
		else:
			d = ((e["holder"] as Node2D).global_position + e.get("pick_off", Vector2.ZERO)).distance_to(world_pos)
			if d >= float(e["pick_r"]):
				continue
		if d < best_d:
			best = e
			best_d = d
	if best.is_empty():
		_deselect()
	else:
		select(best)


func select(e: Dictionary) -> void:
	_sel = e
	if _panel == null:
		_panel = PropertyPanel.new()
		_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_panel.offset_left = -470
		_panel.offset_right = -12
		_panel.offset_top = 86
		_panel.offset_bottom = -48
		_ui_layer.add_child(_panel)
		_panel.changed.connect(_on_prop_changed)
		_panel.template_changed.connect(func(t): _regenerate(t, int(_sel["spec"].get("variant", 0))))
		_panel.variant_changed.connect(func(v): _regenerate(str(_sel["spec"].get("template", "")), v))
		_panel.randomize_requested.connect(func(): _regenerate(str(_sel["spec"].get("template", "")), randi_range(1, 99999)))
		_panel.reset_requested.connect(func():
			_sel["spec"] = (_sel["orig"] as Dictionary).duplicate(true)
			_build_visual(_sel)
			_show_panel())
		_panel.closed.connect(_deselect)
		_panel.undo_requested.connect(undo)
		_panel.redo_requested.connect(redo)
		_panel.paste_requested.connect(paste)
		_panel.apply_all_requested.connect(apply_to_all)
		_panel.preset_load.connect(_load_preset)
		_panel.preset_save.connect(_save_preset)
		_panel.preset_delete.connect(func(n):
			Themes.delete_preset(theme_kind(_sel["kind"]), n)
			_refresh_presets()
			_panel.notify("Deleted the preset '%s'." % n))
	_panel.visible = true
	if _sel_ring == null or not is_instance_valid(_sel_ring):
		_sel_ring = SelRing.new()
		labels.add_child(_sel_ring)
	_sel_ring.position = (e["holder"] as Node2D).global_position + e.get("pick_off", Vector2.ZERO)
	_sel_ring.r = float(e["pick_r"])
	_sel_ring.rect = e.get("rect", Rect2())
	_sel_ring.follow = e["holder"]
	_sel_ring.offset = e.get("pick_off", Vector2.ZERO)
	if e["kind"] == "building" and e.get("node") == null:
		_build_visual(e)
	_show_panel()


func _show_panel() -> void:
	var g := generator(_sel["kind"])
	var spec: Dictionary = _sel["spec"]
	var ids: Array = g.TEMPLATES.keys()
	var names := ids.map(func(t): return g.TEMPLATES[t]["name"])
	var sub: String = g.describe(spec) + "\nLeft-click another exhibit to edit it; drag to look around."
	var title: String = _sel.get("title", str(spec.get("name", "Asset")))
	_panel.edit(title, sub, ids, names, str(spec.get("template", "")), int(spec.get("variant", 0)),
		g.PROPERTIES, _prop_value, "mode" if _sel["kind"] in ["planet", "nebula"] else "")
	_refresh_presets()
	_panel.set_rules(_sel.get("rules", {}), _rule_options(_sel["kind"]))


func _refresh_presets() -> void:
	var names := Themes.presets(theme_kind(_sel["kind"])).map(func(p): return p["name"])
	_panel.set_presets(names, _sel.get("preset", ""))


## The choices for the list rules (ids and names).
func _rule_options(kind: String) -> Dictionary:
	var g := generator(kind)
	var o := {}
	o["systems"] = Galaxy.SYSTEMS.keys().map(func(id): return [id, Galaxy.SYSTEMS[id]["name"]])
	o["owners"] = Galaxy.EMPIRES.keys().map(func(id): return [id, Galaxy.EMPIRES[id]["name"]])
	o["planets"] = Planets.PLANETS.keys().map(func(id): return [id, Planets.PLANETS[id]["name"]])
	o["states"] = Galaxy.STATES.keys().map(func(id): return [id, str(Galaxy.STATES[id].get("name", id))])
	o["templates"] = g.TEMPLATES.keys().map(func(id): return [id, str(g.TEMPLATES[id]["name"])])
	o["friends"] = Galaxy.MAJOR.map(func(id): return [id, Galaxy.EMPIRES[id]["name"]])
	return o


func _load_preset(name: String) -> void:
	var pr := Themes.find(theme_kind(_sel["kind"]), name)
	if pr.is_empty():
		return
	var look := Themes.look_of(pr)
	_set_look(_sel, look)
	_sel["preset"] = name
	_sel["rules"] = Themes.rules_of(pr)
	_show_panel()
	_panel.notify("Loaded the preset '%s'." % name)


func _save_preset(name: String, rules: Dictionary) -> void:
	var path := Themes.save_preset(theme_kind(_sel["kind"]), name, _sel["spec"], rules)
	_sel["preset"] = name
	_sel["rules"] = rules
	_refresh_presets()
	_panel.notify(("Saved the preset '%s' (%s)." % [name, path]) if path != "" else "Could not save the preset.")


## Replaces an exhibit's whole look (undoable as one step).
func _set_look(e: Dictionary, look: Dictionary) -> void:
	var before: Dictionary = (e["spec"] as Dictionary).duplicate(true)
	var spec: Dictionary = (e["spec"] as Dictionary).duplicate(true)
	spec.merge(look, true)
	e["spec"] = spec
	_build_visual(e)
	_undo.append([e, "*", before, spec.duplicate(true)])
	_redo.clear()


func undo() -> void:
	_step(_undo, _redo, 2)


func redo() -> void:
	_step(_redo, _undo, 3)


func _step(from: Array, to: Array, which: int) -> void:
	if from.is_empty():
		return
	var u: Array = from.pop_back()
	to.append(u)
	var e: Dictionary = u[0]
	var g := generator(e["kind"])
	if u[1] == "*":
		e["spec"] = (u[which] as Dictionary).duplicate(true)
		_build_visual(e)
	else:
		e["spec"][u[1]] = u[which]
		if u[1] in g.STRUCTURAL:
			_build_visual(e)
		else:
			g.apply(e["node"], u[1], u[which])
	if e == _sel:
		if u[1] == "*" or u[1] == "mode":
			_show_panel()
		else:
			_panel.show_value(u[1], u[which])


## Copy keeps the look for Paste (any exhibit of the same kind).
func copy_look() -> void:
	if not _sel.is_empty():
		_clip = {"kind": _sel["kind"], "look": (_sel["spec"] as Dictionary).duplicate(true)}


func paste() -> void:
	if _sel.is_empty():
		return
	var look := {}
	if _clip.get("kind") == _sel["kind"]:
		look = _clip["look"]
	else:
		var v = str_to_var(DisplayServer.clipboard_get())
		if v is Dictionary:
			look = v
	if look.is_empty():
		_panel.notify("Nothing to paste: Copy a %s's properties first." % _sel["kind"])
		return
	_set_look(_sel, look)
	_show_panel()
	_panel.notify("Pasted %d properties." % look.size())


## Gives every exhibit of the selected kind in this room the selected look.
func apply_to_all() -> void:
	if _sel.is_empty():
		return
	var n := 0
	for e in _pickables:
		if e != _sel and e["kind"] == _sel["kind"] and is_instance_valid(e["holder"]):
			_set_look(e, _sel["spec"])
			n += 1
	_panel.notify("Applied this look to %d more %s exhibits (undo takes them back one by one)." % [n, _sel["kind"]])


## A property's current value: the spec's, or the shader's default.
func _prop_value(key: String) -> Variant:
	if key == "":
		return null
	var spec: Dictionary = _sel["spec"]
	if spec.has(key):
		return spec[key]
	if _sel["kind"] in ["building", "gui"]:
		return generator(_sel["kind"]).base_value(key)
	var node = _sel.get("node")
	var mat: ShaderMaterial = null
	if node:
		mat = node.get_meta("planet_mat", null) if _sel["kind"] == "planet" else node.material
	if mat and mat.get_shader_parameter(key) != null:
		return mat.get_shader_parameter(key)
	var g := generator(_sel["kind"])
	return RenderingServer.shader_get_parameter_default((g.SHADER as Shader).get_rid(), key)


func _on_prop_changed(key: String, value: Variant) -> void:
	if _sel.is_empty():
		return
	var g := generator(_sel["kind"])
	var old = _sel["spec"].get(key, _prop_value(key))
	if not _undo.is_empty() and _undo[-1][0] == _sel and _undo[-1][1] == key:
		_undo[-1][3] = value   # (a slider drag is one step)
	else:
		_undo.append([_sel, key, old, value])
	_redo.clear()
	_sel["spec"][key] = value
	if key in g.STRUCTURAL:
		_build_visual(_sel)
	else:
		g.apply(_sel["node"], key, value)
	if key == "mode":
		_panel.rebuild()   # (other properties apply now)


## Regenerates the selected exhibit from a template and variant.
func _regenerate(template: String, variant: int) -> void:
	if _sel.is_empty():
		return
	var g := generator(_sel["kind"])
	_sel["spec"] = g.generate(template, variant)
	_build_visual(_sel)
	_show_panel()


func _deselect() -> void:
	_sel = {}
	if _panel:
		_panel.visible = false
	if _sel_ring and is_instance_valid(_sel_ring):
		_sel_ring.queue_free()
	_sel_ring = null


## A slowly turning dashed ring around the selected exhibit.
class SelRing extends Node2D:
	var r := 100.0
	var rect := Rect2()
	var follow: Node2D
	var offset := Vector2.ZERO
	var _a := 0.0

	func _process(delta: float) -> void:
		_a += delta * 0.6
		if follow and is_instance_valid(follow) and rect.size == Vector2.ZERO:
			global_position = follow.global_position + offset
		queue_redraw()

	func _draw() -> void:
		if rect.size != Vector2.ZERO:
			var rr := Rect2(rect.position - global_position, rect.size)
			var c := Color(0.4, 0.95, 0.75, 0.6 + 0.3 * sin(_a * 4.0))
			draw_rect(rr, c, false, 6.0)
			return
		var w := maxf(r * 0.012, 3.0)
		for k in 16:
			var a0 := _a + k * TAU / 16.0
			draw_arc(Vector2.ZERO, r, a0, a0 + TAU / 32.0, 6, Color(0.4, 0.95, 0.75, 0.95), w, true)


func _room_buildings() -> void:
	_ground(Vector2(0, 300), 110)
	var y := -1450.0
	for st in MinoanTiles.STYLES:
		var d: Dictionary = MinoanTiles.STYLES[st]
		_heading("MINOAN %s  ·  walls (both ways), floors, roofs, columns, roof pieces, decor  ·  click to theme" % st.to_upper(), Vector2(0, y - 250))
		var items := {"walls": [], "floors": [], "roofs": [], "decor": []}
		var y0 := y
		# Walls: every design facing each way, then a door.
		var x := -1800.0
		for orient in ["x", "y"]:
			var walls: Array = []
			for v in d["plain"].size():
				walls.append(["plain", v])
			for v in d["window"].size():
				walls.append(["window", v])
			walls.append(["door", 0])
			for wv in walls:
				var s := Sprite2D.new()
				s.texture = MinoanTiles.wall(orient, wv[0], wv[1], st)
				s.centered = false
				s.scale = Vector2.ONE / MinoanTiles.RES
				s.position = Vector2(x, y - SurfaceTiles.WALL_H - 32)
				world.add_child(s)
				items["walls"].append(s)
				x += 74.0
			x += 60.0
		# Floors and roofs.
		y += 170.0
		x = -1800.0
		for kind in ["floor", "mosaic", "roof"]:
			for piece in d[kind]:
				var s := Sprite2D.new()
				s.texture = MinoanTiles.diamond(piece)
				s.position = Vector2(x + 64, y)
				world.add_child(s)
				items["roofs" if kind == "roof" else "floors"].append(s)
				_plate(str(piece).replace("_", " "), s.position + Vector2(0, 34), 13, UI.TEXT_DIM, 120.0)
				x += 150.0
		# Standing pieces.
		y += 260.0
		x = -1800.0
		var pieces: Array = [d["column"], d["antenna"], d["dome"], d["horns"]] + d["caps"] + d["decor"] + d["entrance"]
		var seen := {}
		for piece in pieces:
			if seen.has(piece):
				continue
			seen[piece] = true
			var s := MinoanTiles.sprite(piece, Vector2(x, y), SurfaceTiles.WALL_H + 16.0 if piece == d["column"] else 0.0)
			world.add_child(s)
			items["decor"].append(s)
			_plate(str(piece).replace("_", " "), Vector2(x, y + 8), 13, UI.TEXT_DIM, 120.0)
			x += 150.0
		# The whole style is one selectable exhibit (BuildingLook).
		var area := Rect2(Vector2(-1900, y0 - 330), Vector2(4300, y - y0 + 420))
		var anchor := Node2D.new()
		anchor.position = area.get_center()
		world.add_child(anchor)
		var spec := BuildingLook.generate("minoan", 0)
		_pickables.append({"kind": "building", "holder": anchor, "rect": area, "items": items, "spec": spec,
			"orig": spec.duplicate(true), "pick_r": 0.0, "size": 0.0, "title": "Buildings: Minoan " + st})
		y += 420.0
	# The extra sheet's pieces no style uses (yet): ground, water, platforms, stairs.
	var used := {}
	for st in MinoanTiles.STYLES:
		var d: Dictionary = MinoanTiles.STYLES[st]
		for k in ["plain", "window", "floor", "mosaic", "roof", "caps", "decor", "entrance"]:
			for piece in d[k]:
				used[piece] = true
	var spare: Array = MinoanTiles.names().filter(func(n): return n.begins_with("xt_") and not n.begins_with("xt_wallx_") \
		and not used.has(n) and not used.has(n.replace("wally_", "")))
	spare.sort()
	if not spare.is_empty():
		_heading("MORE MINOAN PIECES  ·  ground, water, platforms, stairs - not in a building style yet", Vector2(0, y - 250))
		var x := -1800.0
		for piece in spare:
			var s := MinoanTiles.sprite(piece, Vector2(x, y))
			world.add_child(s)
			_plate(str(piece).trim_prefix("xt_").replace("_", " "), Vector2(x, y + 8), 13, UI.TEXT_DIM, 120.0)
			x += 150.0
		y += 420.0
	# Scenery.
	y -= 200.0
	var i := 0
	_heading("SCENERY", Vector2(0, y - 120))
	for kind in PROP_KINDS:
		var pr: Node2D = PROPS.Prop.new()
		pr.kind = kind
		pr.color = PROP_KINDS[kind]
		pr.variant = i * 13
		pr.s = 1.6
		pr.position = Vector2(-1350 + i * 300.0, y + 60)
		world.add_child(pr)
		_plate(kind.capitalize(), pr.position + Vector2(0, 30), 15)
		i += 1


## The creatures, alive: Skylla (SeaWitch), Cerberus, Cetus, Echidna, the Hydra,
## the Chimera, Charybdis and the Minotaur (MinotaurBoss), in demo mode - winding up now and then without a
## target - and the Void Leviathan.
func _room_monsters() -> void:
	_space_backdrop()
	_heading("MONSTERS  ·  the creatures of the signal sites and the main quest, alive", Vector2(4750, -620))
	var witch := SeaWitch.new()
	witch.length = float(EnemyTypes.MONSTERS["skylla"]["length"])
	witch.demo = true
	witch.position = Vector2(0, 0)
	world.add_child(witch)
	_plate("SKYLLA  ·  the sea witch\ntraced from the reference art: tentacles writhe, hair drifts,\narms reach and claw; charging, her eyes blaze and energy gathers at her mouth",
		Vector2(0, 360), 17, Color.WHITE, 640.0)
	var lev := SpaceMonster.new()
	lev.length = float(EnemyTypes.MONSTERS["void_leviathan"]["length"])
	lev.position = Vector2(1000, 0)
	world.add_child(lev)
	_plate("VOID LEVIATHAN\nthe first creature (old saves)", Vector2(1000, 360), 17, Color.WHITE, 480.0)
	var cer := CerberusBeast.new()
	cer.length = float(EnemyTypes.MONSTERS["cerberus"]["length"])
	cer.demo = true
	cer.position = Vector2(3200, 0)
	world.add_child(cer)
	_plate("CERBERUS  ·  monster signals\nthe three-headed hound, traced from the reference art: heads snap,\nlegs paw, tail lashes; winding up, his jaws glow - fire from all three",
		Vector2(3200, 420), 17, Color.WHITE, 700.0)
	var cet := CetusBeast.new()
	cet.length = float(EnemyTypes.MONSTERS["cetus"]["length"])
	cet.demo = true
	cet.position = Vector2(4400, 0)
	cet.rotation = -PI / 2.0   # (swimming to the left, as drawn)
	world.add_child(cet)
	_plate("CETUS  ·  monster signals\nthe sea monster of Andromeda, traced from its top view: it bends as it swims,\nfins beating, tail sweeping; it dives and breaches - the side view leaping out",
		Vector2(4400, 420), 17, Color.WHITE, 760.0)
	var ech := EchidnaBeast.new()
	ech.length = float(EnemyTypes.MONSTERS["echidna"]["length"])
	ech.demo = true
	ech.position = Vector2(5600, 0)
	world.add_child(ech)
	_plate("ECHIDNA  ·  monster signals\nthe mother of monsters, traced from her top view: arms reach and claw, tail sways;\nshe rears up (the front view) to loose her brood of serpents, and spits venom",
		Vector2(5600, 460), 17, Color.WHITE, 760.0)
	var hyd := HydraBeast.new()
	hyd.length = float(EnemyTypes.MONSTERS["hydra"]["length"])
	hyd.demo = true
	hyd.position = Vector2(6900, 0)
	world.add_child(hyd)
	_plate("THE HYDRA  ·  monster signals\nthe many-headed serpent of Lerna, traced from its top view: eight heads weaving,\neach firing from its own jaws; cut one off and it grows back; it bites, and rears up to breathe poison",
		Vector2(6900, 420), 17, Color.WHITE, 820.0)
	var chi := ChimeraBeast.new()
	chi.length = float(EnemyTypes.MONSTERS["chimera"]["length"])
	chi.demo = true
	chi.position = Vector2(8200, 0)
	world.add_child(chi)
	_plate("THE CHIMERA  ·  monster signals\nlion, goat and serpent in one, traced from its top view: the lion snarls, the goat tosses its horns,\nthe serpent sways; fire, embers and venom - a sweeping breath, a charge, a rampage (the front view)",
		Vector2(8200, 420), 17, Color.WHITE, 860.0)
	var cha := CharybdisBeast.new()
	cha.length = float(EnemyTypes.MONSTERS["charybdis"]["length"])
	cha.demo = true
	cha.position = Vector2(9500, 0)
	world.add_child(cha)
	_plate("CHARYBDIS  ·  monster signals\nthe whirlpool that swallows the sea, traced whole: it turns, its vortex spinning inside the teeth,\ntentacles writhing; it drags you toward its maw, and spews the sea back out",
		Vector2(9500, 460), 17, Color.WHITE, 860.0)
	var mino := MinotaurBoss.new()
	mino.length = float(EnemyTypes.MONSTERS["minotaur"]["length"])
	mino.demo = true
	mino.position = Vector2(2000, 0)
	world.add_child(mino)
	_plate("THE MINOTAUR  ·  main-quest boss\nthe true Asterion, guardian of the Labyrinth: traced from the reference art;\nhis cape ripples, arms rake, leg kicks; winding up, eyes and crest blaze - and he charges",
		Vector2(2000, 420), 17, Color.WHITE, 700.0)


func _room_effects() -> void:
	_space_backdrop()
	_heading("EFFECTS  ·  every effect sprite", Vector2(600, -520))
	# Every effect sprite, glowing.
	var i := 0
	var fx := []
	for f in DirAccess.get_files_at("res://data/sprites"):
		if f.begins_with("fx_") and f.ends_with(".png"):
			fx.append(f.get_basename())
	fx.sort()
	for key in fx:
		var ex := Exhibit.new()
		ex.texture = ProcArt.get_tex(key)
		ex.additive = true
		ex.mode = "pulse"
		ex.size = 150.0
		ex.position = Vector2(-200 + (i % 8) * 230.0, -300 + (i / 8) * 260.0)
		world.add_child(ex)
		_plate(key.trim_prefix("fx_").replace("_", " "), ex.position + Vector2(0, 92), 15, Color.WHITE, 220.0)
		i += 1
