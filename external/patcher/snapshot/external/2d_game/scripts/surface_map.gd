class_name SurfaceMap
extends Control
## Planet surface: the map - the Field Computer's Map tab (M; `embedded`: built
## into that page, no window of its own), and the full-screen portal network
## map a teleport gate opens (open_gates). The whole terrain in the
## same isometric orientation as the view, with your ship,
## buildings and Minoan citizens. Wheel zoom, drag to pan, click to walk there.
## Pauses the game while open; Esc opens the Esc menu, Tab / M close it.
## Opened from a teleport gate (open_gates) it's the portal network's map:
## every gate, the network's links from the one you're at - click a gate to
## step through to it.

const VIEW_SCRIPT := preload("res://scripts/surface_minimap.gd")

var surface: Node
var _view: MapView
var card: PlanetCard                # the planet's card (bottom right of the map)
## Map layers (the LAYERS panel): routes, places, people, grid.
var layers := {"routes": true, "places": true, "people": true, "grid": true}
var _built := false
var gates_from := -1               # the portal network's map: the gate you're at (-1: the plain map)
var _title: Label
var _hint: Label
## A page of the Field Computer (field_menu.gd): no window, header or keys of
## its own - the Field Computer shows, hides and closes it.
var embedded := false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	if embedded:
		size_flags_horizontal = SIZE_EXPAND_FILL
		size_flags_vertical = SIZE_EXPAND_FILL
		return
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)


## (embedded: the Field Computer's page) Built the first time it's shown; the
## card brought up to date each time; the view fitted to the planet once.
var _fitted := false

func refresh() -> void:
	gates_from = -1
	if not _built:
		_build()
	else:
		_fill_card()
	if not _fitted:
		_fitted = true
		_view.reset.call_deferred()


func open() -> void:
	gates_from = -1
	_open()


## The portal network's map, from gate `from` (click a gate to go there).
func open_gates(from: int) -> void:
	gates_from = from
	_open()


func _open() -> void:
	if not _built:
		_build()
	else:
		_fill_card()
	var name_ := str(surface.pdata["name"]).to_upper()
	# (labels: absent on a map built before a hot reload - the header just keeps its words)
	if is_instance_valid(_title) and is_instance_valid(_hint):
		if gates_from >= 0:
			_title.text = "PORTAL NETWORK  ·  " + name_
			_hint.text = "Click a gate to step through to it  ·  wheel zoom  ·  drag pan  ·  M / Tab / Esc to close"
		else:
			_title.text = "SURFACE MAP  ·  " + name_
			_hint.text = "Wheel zoom  ·  drag pan  ·  click to walk  ·  M / Tab / Esc to close"
	show()   # (the game goes on - it closes by itself when you're hit: PlanetSurface)
	_view.reset.call_deferred()


func close() -> void:
	if embedded:
		if surface and surface.get("field_menu"):
			surface.field_menu.close()
		return
	hide()


func _build() -> void:
	_built = true
	var root: VBoxContainer
	if embedded:
		root = VBoxContainer.new()
		root.size_flags_horizontal = SIZE_EXPAND_FILL
		root.size_flags_vertical = SIZE_EXPAND_FILL
		root.add_theme_constant_override("separation", 10)
		add_child(root)
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	else:
		root = UI.modal(self, Color(NeonTheme.TEXT_DIM, 0.9), Vector2.ZERO, true)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_title = UI.label("SURFACE MAP  ·  " + str(surface.pdata["name"]).to_upper(), 28, NeonTheme.HEAD)
	header.add_child(_title)
	header.add_child(UI.spacer())
	_hint = UI.label("Wheel zoom  ·  drag pan  ·  click to walk  ·  M / Tab / Esc to close", 14, UI.TEXT_DIM)
	header.add_child(_hint)
	var reset := EditorIcons.dress(UI.button("", func(): _view.reset(), 15), "reload", EditorIcons.tip("Reset view", "", "Shows the whole planet again. Wheel: zoom · drag: pan · click: walk there."))
	reset.focus_mode = FOCUS_NONE
	header.add_child(reset)
	if embedded:
		_hint.text = "Wheel zoom  ·  drag pan  ·  click to walk there"
		_title.add_theme_font_size_override("font_size", 20)
	else:
		header.add_child(EditorIcons.docs_button(self, "surface-map", EditorDocs.GAME))
		header.add_child(EditorIcons.dress(UI.button("", close, 15), "close", EditorIcons.tip("Close the map", "M  ·  Tab  ·  Esc", "Closes the map (the game goes on while it's open - it closes by itself if you're attacked).")))
	root.add_child(header)
	# Left: the LAYERS panel; right: the map, with the planet card in its corner.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_layers_panel())
	_view = MapView.new()
	_view.owner_map = self
	_view.size_flags_vertical = SIZE_EXPAND_FILL
	_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(1000, 640)
	_view.mouse_filter = MOUSE_FILTER_STOP
	_view.clip_contents = true
	body.add_child(_view)
	_view.setup(surface)
	card = PlanetCard.new()
	_view.add_child(card)
	_fill_card()
	UI.scale_fonts(root, "menu", 1.5)


## The reference console's LAYERS panel: a check box per map layer.
func _layers_panel() -> Control:
	var panel := PanelContainer.new()
	var st := UI.panel_style(NeonTheme.CYAN)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_vertical = SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(230, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var head := UI.label("LAYERS", 24, NeonTheme.TEXT)
	box.add_child(head)
	for l in [["routes", "Routes", "Orange routes from your ship to the settlements, dotted ones between them."],
			["places", "Places", "The settlements, your ship and the buildings."],
			["people", "People", "Citizens (gold) and pirates (red warnings)."],
			["grid", "Grid", "The map grid and its frame."]]:
		var cb := CheckBox.new()
		cb.text = l[1]
		cb.button_pressed = layers[l[0]]
		cb.tooltip_text = l[2]
		cb.focus_mode = FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 18)
		var key: String = l[0]
		cb.toggled.connect(func(on): layers[key] = on; _view.queue_redraw())
		box.add_child(cb)
	return panel


func _fill_card() -> void:
	var pd: Dictionary = surface.pdata
	var settlements: int = _view.settlements().size()
	var pirates := 0
	for a in surface.npcs:
		if a.get("species") == "pirate":
			pirates += 1
	var explored: float = surface.fog.explored_share() if surface.fog else 1.0
	var kinds := []
	for t in pd.get("terrain", []):
		if t[2]:
			kinds.append(t[0])
	var rows := [["SYSTEM", Galaxy.systems.get(Galaxy.current_system, {}).get("name", "-")],
		["TERRAIN", " / ".join(kinds.slice(0, 2))],
		["SETTLEMENTS", str(settlements)],
		["EXPLORED", "%d%%" % roundi(explored * 100.0)],
		["THREAT", PlanetCard.threat_word(pirates / 12.0)]]
	card.show_planet(str(pd.get("name", "")), "Surface map", Planets.spec(surface.planet_id), rows, str(pd.get("desc", "")))


func _input(event: InputEvent) -> void:
	if embedded or not visible or UI.esc_menu_open():
		return   # (embedded: the Field Computer's keys)
	if Keybinds.pressed(event, "sector_map") or Keybinds.pressed(event, "computer") or event.is_action_pressed("ui_cancel"):
		close()   # (M / Tab, Esc or pad B)
	else:
		return
	get_viewport().set_input_as_handled()


## The minimap drawing, zoomable and pannable, with labels and hover info.
class MapView extends "res://scripts/surface_minimap.gd":
	var owner_map: Node
	var zoom := 1.0
	var pan := Vector2.ZERO
	var _pressed := false
	var _dragging := false
	var _press := Vector2.ZERO
	var _hover := {}

	func setup(s: Node) -> void:
		super(s)
		whole = true

	func reset() -> void:
		zoom = 1.0
		pan = Vector2.ZERO
		queue_redraw()

	func _grid_xform() -> Transform2D:
		# The base fits the diamond to the control's width; keep it inside the height too.
		var base := super()
		var n: float = surface.N
		var h := n * (size.x / (2.0 * n))      # diamond height at full width
		var fit := minf(1.0, size.y * 0.96 / maxf(h, 1.0))
		var c := size / 2.0
		return Transform2D(0.0, Vector2(fit * zoom, fit * zoom), 0.0, c + pan - c * fit * zoom) * base

	func to_world(screen: Vector2) -> Vector2:
		var grid := _grid_xform().affine_inverse() * screen - Vector2(0.5, 0.5)
		return _world_to_grid.affine_inverse() * grid

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var f := 1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
				var nz := clampf(zoom * f, 0.6, 60.0)
				# Keep the point under the cursor fixed.
				var c := size / 2.0
				pan = (mb.position - c) - (mb.position - c - pan) * (nz / zoom)
				zoom = nz
			elif UI.middle_click(self, mb):
				reset()   # (the middle button: the whole planet again)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true
					_dragging = false
					_press = mb.position
				else:
					if _pressed and not _dragging:
						_walk(mb.position)
					_pressed = false
			accept_event()
		elif ev is InputEventMouseMotion:
			var mm := ev as InputEventMouseMotion
			if _pressed and (_dragging or mm.position.distance_to(_press) > 5.0):
				_dragging = true
				pan += mm.relative
			_hover = _pick(mm.position)
			accept_event()

	func _walk(at: Vector2) -> void:
		if owner_map and owner_map.gates_from >= 0:   # the portal network: travel
			var gi := gate_at(at)
			if gi >= 0 and gi != owner_map.gates_from:
				owner_map.close()
				surface.teleport_to(gi)
			return
		var h := _pick(at)
		var world: Vector2 = to_world(at)
		if h.has("pos"):
			world = h["pos"]
		elif h.has("thing"):
			world = h["thing"].global_position + Vector2(0, 30)
		surface._walk_to(world)   # (the map stays open: the route shows on it as you walk)
		queue_redraw()

	## The gate whose marker is under `at` (map px), or -1.
	func gate_at(at: Vector2) -> int:
		var best := -1
		var best_d := 22.0
		var gs: Array = surface.get("gates") if surface.get("gates") != null else []
		for i in gs.size():
			if not gate_known(i):
				continue
			var d := gate_pos(i).distance_to(at)
			if d < best_d:
				best_d = d
				best = i
		return best

	## A gate shows on the maps (and can be travelled to) once its ground is
	## cleared of the fog of war - or it's the one you're at.
	func gate_known(i: int) -> bool:
		if owner_map != null and owner_map.gates_from == i:
			return true
		return surface.fog == null or surface.fog.explored(Vector2(surface.gates[i]["cell"]) + Vector2(0.5, 0.5))

	func gate_pos(i: int) -> Vector2:
		return _grid_xform() * (Vector2(surface.gates[i]["cell"]) + Vector2(0.5, 0.5))

	## Things with a name near the cursor.
	func _pick(at: Vector2) -> Dictionary:
		if owner_map and owner_map.gates_from >= 0:
			var gi := gate_at(at)
			if gi < 0:
				return {}
			var here: bool = gi == owner_map.gates_from
			return {"name": surface.gates[gi]["name"] + ("  (you are here)" if here else ""), "gate": gi, "here": here}
		var best := {}
		var best_d := 14.0
		for st in settlements():
			var sp: Vector2 = _grid_xform() * (st["c"] + Vector2(0.5, 0.5))
			if sp.distance_to(at) < 18.0 and (surface.fog == null or surface.fog.explored(st["c"] + Vector2(0.5, 0.5))):
				best = {"pos": _world_to_grid.affine_inverse() * st["c"], "name": "Settlement · %d buildings" % st["n"]}
				best_d = 0.0
		var things: Array = [surface.lander] + surface.npcs
		for t in things:
			if not surface.explored_at(t.global_position):
				continue
			var d := _to_map(t.global_position).distance_to(at)
			if d < best_d:
				best_d = d
				best = {"thing": t, "name": _name_of(t)}
		return best

	func _name_of(t: Node) -> String:
		if t == surface.lander:
			return "Your ship"
		if t in surface.npcs:
			return t.title.get_slice("  -", 0)
		var title: String = t.get("title") if t.get("title") != null else ""
		return title.get_slice("  -  ", 0)

	## Building groups: one settlement each (grid centre, buildings in it).
	func settlements() -> Array:
		var out := []
		for r in surface.building_rects():
			var c := Vector2(r.get_center())
			var found := false
			for st in out:
				if st["c"].distance_to(c) < 40.0:
					st["c"] = (st["c"] * st["n"] + c) / (st["n"] + 1)
					st["n"] += 1
					found = true
					break
			if not found:
				out.append({"c": c, "n": 1})
		return out

	func _layer(k: String) -> bool:
		if owner_map != null and owner_map.gates_from >= 0 and k in ["routes", "people"]:
			return false   # (the portal network's map: the gates' links instead)
		return owner_map == null or owner_map.layers.get(k, true)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), NeonTheme.BG)
		var g := _grid_xform()
		var n: float = surface.N
		var c := g * Vector2(n / 2.0, n / 2.0)
		var half := (g * Vector2(n, 0)).distance_to(g * Vector2(0, n)) * 0.5
		if _layer("grid"):   # the console's frame: grid lines and an oval ring round the map
			var gc := Color(NeonTheme.HEAD, 0.07)
			var step := 48.0
			var x := fposmod(c.x, step)
			while x < size.x:
				draw_line(Vector2(x, 0), Vector2(x, size.y), gc, 1.0)
				x += step
			var y := fposmod(c.y, step)
			while y < size.y:
				draw_line(Vector2(0, y), Vector2(size.x, y), gc, 1.0)
				y += step
		whole_markers = false
		super()
		if _layer("grid"):
			MapIcons._ellipse(self, c, Vector2(half * 1.08, half * 0.6), Color(NeonTheme.HEAD, 0.35), 1.5)
			MapIcons._ellipse(self, c, Vector2(half * 1.12, half * 0.63), Color(NeonTheme.HEAD, 0.12), 1.0)
		var font := NeonTheme.heavy_font()
		var fs := Settings.fs("menu", 15)
		var label := func(p: Vector2, t: String, col: Color):
			draw_string_outline(font, p + Vector2(-110, 30), t, HORIZONTAL_ALIGNMENT_CENTER, 220, fs, 5, Color(0, 0, 0, 0.9))
			draw_string(font, p + Vector2(-110, 30), t, HORIZONTAL_ALIGNMENT_CENTER, 220, fs, col)
		var lp := _to_map(surface.lander.global_position)
		var sts := settlements().filter(func(st): return surface.fog == null or surface.fog.explored(st["c"] + Vector2(0.5, 0.5)))
		var big := 0
		for i in sts.size():
			if sts[i]["n"] > sts[big]["n"]:
				big = i
		if _layer("routes"):   # orange routes from your ship, dotted cyan ones between settlements
			for i in sts.size():
				var p: Vector2 = g * (sts[i]["c"] + Vector2(0.5, 0.5))
				MapIcons.route(self, lp, p, MapIcons.ORANGE, 30.0 * (1 if i % 2 == 0 else -1), false, 2.5)
			for i in sts.size() - 1:
				MapIcons.route(self, g * (sts[i]["c"] + Vector2(0.5, 0.5)), g * (sts[i + 1]["c"] + Vector2(0.5, 0.5)), MapIcons.CYAN, 20.0, true, 2.5)
		if _layer("people"):
			for a in surface.npcs:
				if not surface.explored_at(a.global_position):
					continue
				var at := _to_map(a.global_position)
				if a.get("species") == "pirate":
					MapIcons.badge(self, at, 9.0, MapIcons.RED, "warning")
				else:
					draw_circle(at, 2.5, Color(1.0, 0.8, 0.35))
		if _layer("places"):
			for i in sts.size():
				var p: Vector2 = g * (sts[i]["c"] + Vector2(0.5, 0.5))
				MapIcons.badge(self, p, 17.0 if i == big else 14.0, MapIcons.CYAN, "temple" if i == big else "city")
				if i == big and p.distance_to(lp) > 60.0:
					label.call(p, "PALACE", NeonTheme.HEAD)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
			MapIcons.badge(self, lp, 19.0, MapIcons.ORANGE, "ship", pulse)
			label.call(lp + Vector2(0, -62), "YOUR SHIP", Color(1.0, 0.75, 0.4))
		_draw_gates(label)
		var pp := _to_map(surface.pilot.global_position)
		MapIcons.badge(self, pp, 11.0, Color.WHITE, "you")
		# Walking route.
		if surface.pilot.moving and not surface.pilot.path.is_empty():
			var pts := PackedVector2Array([pp])
			for w in surface.pilot.path:
				pts.append(_to_map(w))
			draw_polyline(pts, Color(1, 1, 1, 0.7), 2.0, true)
		_compass(Vector2(size.x - 70, 70))
		_scale_bar(Vector2(28, size.y - 40))
		_draw_hover()

	## The teleport gates: in the portal network's map all of them, linked to
	## the one you're at (brightest) and named; on the plain map, the ones
	## you've seen (with the places).
	func _draw_gates(label: Callable) -> void:
		var gs: Array = surface.get("gates") if surface.get("gates") != null else []
		var network: bool = owner_map != null and owner_map.gates_from >= 0
		if gs.is_empty() or (not network and not _layer("places")):
			return
		var t := Time.get_ticks_msec() / 1000.0
		var col := NeonTheme.HEAD
		if network:
			var from: Vector2 = gate_pos(owner_map.gates_from)
			for i in gs.size():
				if i != owner_map.gates_from and gate_known(i):
					MapIcons.route(self, from, gate_pos(i), col, 16.0, true, 2.0)
		for i in gs.size():
			var p: Vector2 = gate_pos(i)
			if not gate_known(i):
				continue   # (still under the fog of war)
			var here: bool = network and i == owner_map.gates_from
			var hover: bool = network and _hover.get("gate", -1) == i
			var r := 13.0 if here or hover else 10.0
			draw_circle(p, r + 6.0 + 2.0 * sin(t * 3.0 + i), Color(col, 0.18))
			draw_arc(p, r, 0, TAU, 28, Color(col.lightened(0.3), 0.95), 2.5, true)
			portal_icon(self, p, r * 0.6)
			if network or hover:
				label.call(p + Vector2(0, -6), gs[i]["name"].to_upper() + ("  ·  HERE" if here else ""),
					Color(1.0, 0.85, 0.45) if here else NeonTheme.TEXT)

	## A compass rose (north = the top of the map).
	func _compass(at: Vector2) -> void:
		var col := NeonTheme.TEXT
		draw_arc(at, 34, 0, TAU, 40, Color(NeonTheme.HEAD, 0.4), 1.0, true)
		for k in 4:
			var d := Vector2.from_angle(-PI / 2 + k * PI / 2)
			var sd := d.orthogonal()
			var ln := 30.0 if k == 0 else 22.0
			draw_colored_polygon(PackedVector2Array([at + d * ln, at + sd * 5, at - sd * 5]), col if k == 0 else Color(col, 0.6))
		draw_string(NeonTheme.heavy_font(), at + Vector2(-6, -38), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)

	## The scale bar: map distance in metres (a tile is about 2 m).
	func _scale_bar(at: Vector2) -> void:
		var g := _grid_xform()
		var px_per_tile: float = (g * Vector2(1, 0)).distance_to(g * Vector2(0, 0))
		var marks := [0, 50, 100, 250]
		var col := Color(NeonTheme.TEXT, 0.9)
		var font := NeonTheme.heavy_font()
		var last: float = marks[-1] / 2.0 * px_per_tile
		draw_line(at, at + Vector2(last, 0), col, 2.0)
		for m in marks:
			var x: float = m / 2.0 * px_per_tile
			draw_line(at + Vector2(x, -6), at + Vector2(x, 6), col, 2.0)
			draw_string(font, at + Vector2(x - 12, -12), str(m) + (" m" if m == marks[-1] else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

	## What's under the cursor: a small panel ("... · click to walk there").
	func _draw_hover() -> void:
		var font := ThemeDB.fallback_font
		var fs := Settings.fs("menu", 13)
		if not _hover.is_empty():
			var mp := get_local_mouse_position()
			var t: String = _hover["name"] + ("" if _hover.get("here", false) else ("   ·   click to step through" if _hover.has("gate") else "   ·   click to walk there"))
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1).x + 20
			var box := Rect2(mp + Vector2(16, 12), Vector2(w, fs + 18))
			box.position.x = minf(box.position.x, size.x - box.size.x - 4)
			draw_rect(box, Color(NeonTheme.BG, 0.95))
			draw_rect(box, Color(NeonTheme.HEAD, 0.7), false, 1.0)
			draw_string(font, box.position + Vector2(10, fs + 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1, Color.WHITE)
