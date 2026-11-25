extends VBoxContainer
## Ship Computer tab: the sector map. Stations, planets (where to fly to
## reach them), asteroid fields, ships, the quest objective and your course.
## Wheel to zoom, drag to pan, click to set a course (the ship flies there),
## Shift + click to add a waypoint to it (the course runs through them in order),
## Shift + drag a waypoint (or the course's end) to move it.
## Fog of war (Galaxy.fog): only what your sensors have swept shows; the rest
## of the system is dark until you fly there. Signal sources a scan located
## show (above the fog) and can be clicked to fly to.
## PROBES (the button, or a right-click on empty space in flight): the probe
## scanner's panel beside the map (ProbeScanner) - launch probes where the map
## is looking, drag them about, the wheel over one sets its reach, ANALYZE;
## its findings show on the map (a circle where a signature might be; exact once
## located) and in the panel's list.
## TRADE ROUTES (the button, or T): green arrows for the best trade runs from
## this system's stations - to another station here, or (to the gate on the
## way) to a station up to two jumps away - with the good and the profit a unit.

var data: Node
var ship: Node2D

var _view: MapView
var _info: Label
var trade := false
var _trade_btn: Button
var _probe_btn: Button
var _probe_panel: ProbePanel


## The probe scanner (main's ProbeScanner), or null (not in space).
func probes() -> ProbeScanner:
	var m := get_tree().current_scene if is_inside_tree() else null
	return m.get("probes") if m and m.get("probes") is ProbeScanner else null


## The PROBES panel shown (or hidden).
func show_probes(on: bool) -> void:
	_probe_panel.visible = on
	_probe_btn.set_pressed_no_signal(on)
	_view.probing = on
	if on:
		_probe_panel.rebuild()
	_view.queue_redraw()


func toggle_trade() -> void:
	trade = not trade
	_trade_btn.set_pressed_no_signal(trade)
	_view.routes = []
	_view._trade_t = 0.0
	_view.queue_redraw()


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	# (the help wraps to the room the legend and buttons leave it)
	_info = UI.note("Wheel: zoom  ·  drag: pan  ·  click: set a course  ·  Shift + click: add a waypoint  ·  Shift + drag a waypoint: move it", 14, 300)
	_info.size_flags_horizontal = SIZE_EXPAND_FILL
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_info)
	top.add_child(_legend(MapIcons.ORANGE, "Objective / landable"))
	top.add_child(_legend(MapIcons.CYAN, "Station / planet / gate"))
	top.add_child(_legend(MapIcons.RED, "Hostile"))
	top.add_child(_legend(Color(0.5, 1.0, 0.75), "Neutral"))
	top.add_child(_legend(Color(0.85, 0.65, 0.4), "Asteroid"))
	_trade_btn = EditorIcons.dress(UI.button("TRADE", toggle_trade, 14), "buy", EditorIcons.tip("Trade routes", "T", "Green arrows for the best trade runs from this system's stations: to another station here, or out through a gate to a station up to two jumps away.\nEach shows the good to carry and the profit a unit."))
	_trade_btn.toggle_mode = true
	_trade_btn.focus_mode = FOCUS_NONE
	top.add_child(_trade_btn)
	_probe_btn = EditorIcons.dress(UI.button("PROBES", func(): show_probes(not _probe_panel.visible), 14), "scan", EditorIcons.tip("Probe scanner", "right-click in flight",
		"Scan probes: launch them across the system, drag them into place - one at a time, or all together by the handle above them -\nset their reach (the wheel over one) and analyze.\nEvery signature they read gets a strength: tight probes round it pin it down - at 100% it's located.\nNeeds a Probe Scanner (outfitters, SYSTEMS)."))
	_probe_btn.toggle_mode = true
	_probe_btn.focus_mode = FOCUS_NONE
	top.add_child(_probe_btn)
	var fit := EditorIcons.dress(UI.button("", func(): _view.fit(), 14), "fit_all", EditorIcons.tip("Whole sector", "", "Zooms the map out to show the whole sector: every station, planet and jump gate.\nWheel: zoom · drag: pan."))
	fit.focus_mode = FOCUS_NONE
	top.add_child(fit)
	var ctr := EditorIcons.dress(UI.button("", func(): _view.centre_on_ship(), 14), "ship", EditorIcons.tip("Centre on your ship", "", "Moves the map to your ship's position (keeping the zoom)."))
	ctr.focus_mode = FOCUS_NONE
	top.add_child(ctr)
	add_child(top)
	_view = MapView.new()
	_view.page = self
	_view.custom_minimum_size = Vector2(1240, 590)
	_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_view.size_flags_vertical = SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(row)
	row.add_child(_view)
	_probe_panel = ProbePanel.new()
	_probe_panel.page = self
	_probe_panel.custom_minimum_size = Vector2(330, 0)
	_probe_panel.visible = false
	row.add_child(_probe_panel)


func _legend(c: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var dot := ColorRect.new()
	dot.color = c
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UI.label(text, 13, UI.TEXT_DIM))
	return h


func refresh() -> void:
	_view.ship = ship
	_view.rebuild()


## The current system's planets (they orbit the star; positions are live).
static func planet_targets(tree: SceneTree, _from: Vector2) -> Array:
	var out := []
	for b in tree.get_nodes_in_group("planet_bodies"):
		var look: Dictionary = b.spec
		out.append({"id": b.planet_id, "name": b.title, "pos": b.global_position, "landable": b.landable,
			"radius": b.radius, "orbit": b.orbit, "center": b.parent_body.global_position if b.parent_body else Vector2.ZERO,
			"color": look.get("color_light", Color(0.65, 0.75, 0.85)), "color2": look.get("color_dark", Color(0.25, 0.3, 0.4)),
			"moon": b.parent_body != null, "rings": float(b.spec.get("rings", 0.0)) > 0.0})
	return out


class MapView extends Control:
	const GOLD := Color(1.0, 0.82, 0.38)
	var page: Node
	var ship: Node2D
	var center := Vector2.ZERO
	var scale_ := 0.05            # screen px per world unit
	var _bounds := Rect2()
	var _planets := []
	var _hover := {}

	var routes: Array = []      # the trade runs shown (page.trade)
	var probing := false        # the PROBES panel open: probes can be dragged, the wheel sizes them
	var picked_id := ""         # the signature picked in the panel's list (drawn out)
	var _probe_drag := -1
	var _trade_t := 0.0

	## The game goes on while the map is open: you, the ships and your course move on it.
	func _process(_delta: float) -> void:
		# (30 pictures a second of the moving system - a map; the heavy redraw
		# frames at 60 were one in eight of 700 a second)
		if UI.redraw_due(self, 30.0):
			queue_redraw()
		if is_visible_in_tree():
			_overlay_due()
		if _trading() and is_visible_in_tree():
			_trade_t -= _delta
			if _trade_t <= 0.0:
				_trade_t = 2.0   # (prices move every economy tick)
				var here := TradeRoutes.stations_of([Galaxy.current_system])
				routes = TradeRoutes.routes_from(here, 0, "", 6) + TradeRoutes.routes_from(here, 2, "", 5, true)

	func _trading() -> bool:
		return is_instance_valid(page) and page.trade

	## The trade runs: station to station, or station to the gate toward the
	## system where it sells.
	func _draw_trade(font: Font, fs: int) -> void:
		if routes.is_empty():
			return
		var where := {}
		for st in get_tree().get_nodes_in_group("stations"):
			where[st.station_id] = st.global_position
		var gates := {}
		for g in get_tree().get_nodes_in_group("gates"):
			gates[g.target] = g.global_position
		var top := 1.0
		for r in routes:
			top = maxf(top, r["profit"])
		var t := Time.get_ticks_msec() / 1000.0
		var n := 0
		var taken := []
		for r in routes:
			if not where.has(r["from"]) or not _seen(where[r["from"]]):
				continue   # (from stations you've charted; where it sells may be out in the dark)
			var a := to_screen(where[r["from"]])
			var b: Vector2
			var tag := TradeRoutes.tag_text(r)
			if r["to_sys"] == Galaxy.current_system:
				if not where.has(r["to"]):
					continue
				b = to_screen(where[r["to"]])
			else:
				var path := Galaxy.find_route(Galaxy.current_system, r["to_sys"])
				if path.size() < 2 or not gates.has(path[1]):
					continue
				b = to_screen(gates[path[1]])
				tag += " › " + TradeRoutes.system_name(r["to_sys"]).to_upper()
			var d := (b - a).normalized()
			var off := d.orthogonal() * ((n % 3) - 1) * 8.0
			n += 1
			var pts := PackedVector2Array([a + d * 22.0 + off, b - d * 24.0 + off])
			if pts[0].distance_to(pts[1]) < 30.0:
				continue
			TradeRoutes.draw_run(self, pts, r["profit"] / top, t)
			TradeRoutes.draw_tag(self, pts[0].lerp(pts[1], 0.3 + 0.12 * (n % 3)), tag, fs, taken)
	var _press := Vector2.ZERO
	var _dragging := false
	var _pressed := false
	var _fitted := false

	func _init() -> void:
		clip_contents = true
		mouse_filter = MOUSE_FILTER_STOP
		_overlay = ProbeOverlay.new()
		_overlay.view = self
		_overlay.mouse_filter = MOUSE_FILTER_IGNORE
		_overlay.set_anchors_preset(PRESET_FULL_RECT)
		add_child(_overlay)

	## The probes and their findings on their own layer, redrawn only when they
	## (or the view) change - not with the moving system 60 times a second:
	## dozens of signatures' circles and names were 3 ms a redraw.
	var _overlay: ProbeOverlay
	var _overlay_sig := ""

	func _overlay_due() -> void:
		var ps: ProbeScanner = page.probes() if is_instance_valid(page) else null
		if ps == null:
			return
		var sig := "%s|%s|%d|%d|%s|%s|%s" % [center, scale_, ps.probes.size(), ps.results.size(), picked_id, probing, _group_drag]
		for p in ps.probes:
			sig += "|%s,%s" % [p["at"], p["r"]]
		var anim := ps.analyzing >= 0.0
		if sig != _overlay_sig or (anim and UI.redraw_due(_overlay, 30.0)):
			_overlay_sig = sig
			_overlay.repaint()

	func rebuild() -> void:
		if ship == null:
			return
		_planets = MapPage_targets()
		var b := Rect2(ship.global_position, Vector2.ZERO)
		for st in get_tree().get_nodes_in_group("stations"):
			if _seen(st.global_position):
				b = b.expand(st.global_position)
		for r in get_tree().get_nodes_in_group("asteroids"):
			if _seen(r.global_position):
				b = b.expand(r.global_position)
		for p in _planets:
			if _seen(p["pos"]):
				b = b.expand(p["pos"])
		for g in get_tree().get_nodes_in_group("gates"):
			if _seen(g.global_position):
				b = b.expand(g.global_position)
		var q := _quest()
		if q and q.target_position() != null:
			b = b.expand(q.target_position())
		_bounds = b.grow(1200)
		if not _fitted:
			_fitted = true
			fit.call_deferred()
		queue_redraw()

	## Explored (out of the fog).
	func _seen(p: Vector2) -> bool:
		return Galaxy.explored_at(p)

	func MapPage_targets() -> Array:
		return page.planet_targets(get_tree(), ship.global_position)

	func _quest() -> Node:
		return get_tree().get_first_node_in_group("quest")

	func fit() -> void:
		if size.x < 10 or _bounds.size.x <= 0:
			return
		center = _bounds.get_center()
		scale_ = minf(size.x / _bounds.size.x, size.y / _bounds.size.y) * 0.95
		queue_redraw()

	func centre_on_ship() -> void:
		if ship:
			center = ship.global_position
			scale_ = maxf(scale_, 0.12)
			queue_redraw()

	func to_screen(w: Vector2) -> Vector2:
		return size / 2.0 + (w - center) * scale_

	func to_world(s: Vector2) -> Vector2:
		return center + (s - size / 2.0) / scale_

	# --- Input -----------------------------------------------------------------------

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			var pi := _probe_at(mb.position) if probing else -1
			var on_group := probing and _group_handle_at(mb.position)
			if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and on_group:
				# (the wheel over the group's handle: the formation spread out / drawn in round its middle)
				_spread_group(1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and pi >= 0 and mb.shift_pressed:
				page.probes().step_all(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)   # (Shift: every probe's reach)
				queue_redraw()
			elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and (on_group or (pi >= 0 and mb.shift_pressed)):
				_group_drag = true   # (the handle, or Shift + a probe: the whole group moves)
				_group_last = to_world(mb.position)
			elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _group_drag:
				_group_drag = false
				page.probes().changed.emit()
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and pi >= 0:
				# (the wheel over a probe: its reach a step bigger / smaller)
				var pr: Dictionary = page.probes().probes[pi]
				pr["r"] = ProbeScanner.step(float(pr["r"]), 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
				page.probes().changed.emit()
				queue_redraw()
			elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and pi >= 0:
				_probe_drag = pi   # (drag a probe to move it)
			elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _probe_drag >= 0:
				_probe_drag = -1
				page.probes().changed.emit()
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var w := to_world(mb.position)
				scale_ = clampf(scale_ * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.005, 1.0)
				center = w - (mb.position - size / 2.0) / scale_
				queue_redraw()
			elif UI.middle_click(self, mb):
				fit()   # (the middle button: the whole map again)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.shift_pressed and _course_point_at(mb.position) >= 0:
					_wp_drag = _course_point_at(mb.position)   # (Shift + drag a course point: move it)
					_wp_moved = false
				elif mb.pressed:
					_pressed = true
					_dragging = false
					_press = mb.position
				elif _wp_drag >= 0:
					if _wp_moved:
						_drop_course_point(mb.position)
					_wp_drag = -1
				else:
					if _pressed and not _dragging:
						_set_course(mb.position, mb.shift_pressed)
					_pressed = false
					_dragging = false
			accept_event()
		elif ev is InputEventMouseMotion:
			var mm := ev as InputEventMouseMotion
			if _group_drag and page.probes():
				var w := to_world(mm.position)
				var d := w - _group_last
				_group_last = w
				for pr in page.probes().probes:
					pr["pos"] = (pr["pos"] as Vector2) + d
					pr["at"] = pr["pos"]   # (already out there: moved, not relaunched)
				queue_redraw()
				accept_event()
				return
			if _probe_drag >= 0 and page.probes() and _probe_drag < page.probes().probes.size():
				var pr: Dictionary = page.probes().probes[_probe_drag]
				pr["pos"] = to_world(mm.position)
				pr["at"] = pr["pos"]   # (it's already out there: moved, not relaunched)
				queue_redraw()
				accept_event()
				return
			if _wp_drag >= 0:
				_wp_moved = true
				ship.set_course_point(_wp_drag, to_world(mm.position))
				queue_redraw()
				accept_event()
				return
			# Shift over a course point, the probes' group handle, Shift over a probe: the move cursor (they can be dragged).
			var movable := (mm.shift_pressed and _course_point_at(mm.position) >= 0) or (probing and (_group_handle_at(mm.position) or (mm.shift_pressed and _probe_at(mm.position) >= 0)))
			mouse_default_cursor_shape = CURSOR_MOVE if movable else CURSOR_ARROW
			if _pressed and (_dragging or mm.position.distance_to(_press) > 5.0):
				_dragging = true
				center -= mm.relative / scale_
			_hover = _pick(mm.position)
			queue_redraw()
			accept_event()

	var _wp_drag := -1      # the course point being dragged (Shift + drag), -1: none
	var _group_drag := false   # the probes moved as a group (their handle, or Shift + drag a probe)
	var _group_last := Vector2.ZERO

	## The probes' middle (world), the group handle's place.
	func _group_centre() -> Vector2:
		var ps: ProbeScanner = page.probes()
		var c := Vector2.ZERO
		if ps == null:
			return c
		for pr in ps.probes:
			c += pr["at"] as Vector2
		return c / maxf(1.0, ps.probes.size())

	## The group handle's place (screen): above the topmost probe, in line with
	## their middle (clear of every probe's marker - the pattern has one in the middle).
	func _group_handle_pos() -> Vector2:
		var ps: ProbeScanner = page.probes()
		var top := INF
		for pr in ps.probes:
			top = minf(top, to_screen(pr["at"]).y)
		return Vector2(to_screen(_group_centre()).x, top - 34.0)

	## Over the group handle (shown with two probes or more)?
	func _group_handle_at(at: Vector2) -> bool:
		if not is_instance_valid(page) or page.probes() == null or page.probes().probes.size() < 2:
			return false
		return _group_handle_pos().distance_to(at) < 13.0

	## The formation spread out (k > 1) or drawn in round its middle.
	func _spread_group(k: float) -> void:
		var ps: ProbeScanner = page.probes()
		if ps == null:
			return
		var c := _group_centre()
		for pr in ps.probes:
			pr["pos"] = c + ((pr["pos"] as Vector2) - c) * k
			pr["at"] = pr["pos"]
		ps.changed.emit()
		queue_redraw()

	## The probe under `at` (its marker, or its reach's rim), -1: none.
	func _probe_at(at: Vector2) -> int:
		if not is_instance_valid(page):
			return -1
		var ps: ProbeScanner = page.probes()
		if ps == null:
			return -1
		for i in range(ps.probes.size() - 1, -1, -1):
			var c := to_screen(ps.probes[i]["at"])
			var rr: float = float(ps.probes[i]["r"]) * scale_
			var d := c.distance_to(at)
			if d < 14.0 or absf(d - rr) < 8.0:
				return i
		return -1

	## The probes (their reach, where they are) and what they've found.
	func _draw_probes(font: Font, fs: int, ci: CanvasItem) -> void:
		if not is_instance_valid(page):
			return
		var ps: ProbeScanner = page.probes()
		if ps == null:
			return
		var t := Time.get_ticks_msec() / 1000.0
		for r in ps.results:
			var col: Color = ProbeScanner.KINDS[r["kind"]][2]
			var st := float(r["strength"])
			var lbl := "%s  %d%%" % [ProbeScanner.label(r), roundi(st * 100.0)]
			if st >= 1.0:
				var c := to_screen(r["node"].global_position if is_instance_valid(r.get("node")) else r["pos"])
				ci.draw_arc(c, 11.0, 0, TAU, 20, col, 2.5, true)
				ci.draw_arc(c, 16.0 + 3.0 * sin(t * 4.0), 0, TAU, 24, Color(col, 0.5), 1.5, true)
				ci.draw_string_outline(font, c + Vector2(-140, -18), lbl, HORIZONTAL_ALIGNMENT_CENTER, 280, fs, 4, Color(0, 0, 0, 0.85))
				ci.draw_string(font, c + Vector2(-140, -18), lbl, HORIZONTAL_ALIGNMENT_CENTER, 280, fs, col.lightened(0.3))
			else:
				# (where it might be: fainter the weaker - a sweep's dozens of faint ones
				# don't bury the map; the one picked in the list stands out)
				var c := to_screen(r["est"])
				var rr := maxf(10.0, float(r["unc"]) * scale_)
				var picked: bool = r["id"] == picked_id
				var k := 1.0 if picked else clampf(st * 1.3, 0.15, 1.0)
				if picked or st >= 0.5:
					ci.draw_circle(c, rr, Color(col, 0.07 * k))
				ci.draw_arc(c, rr, 0, TAU, 48, Color(col, 0.55 * k), 2.5 if picked else 1.2, true)
				ci.draw_circle(c, 3.0, Color(col, k))
				if st >= 0.25 or picked:
					ci.draw_string_outline(font, c + Vector2(-140, -minf(rr, 60.0) - 6), lbl, HORIZONTAL_ALIGNMENT_CENTER, 280, fs, 4, Color(0, 0, 0, 0.85))
					ci.draw_string(font, c + Vector2(-140, -minf(rr, 60.0) - 6), lbl, HORIZONTAL_ALIGNMENT_CENTER, 280, fs, Color(col.lightened(0.2), maxf(k, 0.6)))
		if not probing:
			return
		var scanning := ps.analyzing >= 0.0
		for i in ps.probes.size():
			var p: Dictionary = ps.probes[i]
			var c := to_screen(p["at"])
			var rr: float = float(p["r"]) * scale_
			var col := Color(0.4, 0.85, 1.0)
			ci.draw_circle(c, rr, Color(col, 0.06))
			ci.draw_arc(c, rr, 0, TAU, 96, Color(col, 0.75 if i == _probe_drag else 0.45), 2.0, true)
			if scanning:   # (a sweep round each while the analysis runs)
				var a := t * 3.0 + i
				ci.draw_line(c, c + Vector2.from_angle(a) * rr, Color(col, 0.5), 2.0, true)
				ci.draw_arc(c, rr, a - 0.6, a, 16, Color(col, 0.35), rr * 0.1 if rr < 60.0 else 6.0, false)
			ci.draw_circle(c, 7.0, Color(0, 0, 0, 0.7))
			ci.draw_circle(c, 5.0, col)
			ci.draw_string(font, c + Vector2(9, -8), "%d  %.0fk" % [i + 1, float(p["r"]) / 1000.0], HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(Settings.MIN_FONT, fs - 2), col)
		# The group handle: a diamond with four arrows above the probes, lines to each
		# while it's dragged (drag it: they all move; the wheel over it: spread / draw in).
		if ps.probes.size() >= 2:
			var g := _group_handle_pos()
			var hcol := Color(1.0, 0.82, 0.4)
			if _group_drag:
				for p in ps.probes:
					ci.draw_line(g, to_screen(p["at"]), Color(hcol, 0.35), 1.5, true)
			var d := 9.0
			ci.draw_colored_polygon(PackedVector2Array([g + Vector2(0, -d), g + Vector2(d, 0), g + Vector2(0, d), g + Vector2(-d, 0)]), Color(0, 0, 0, 0.75))
			ci.draw_polyline(PackedVector2Array([g + Vector2(0, -d), g + Vector2(d, 0), g + Vector2(0, d), g + Vector2(-d, 0), g + Vector2(0, -d)]), hcol, 2.0, true)
			for k in 4:
				var dir := Vector2.from_angle(k * PI * 0.5)
				var tip := g + dir * (d + 8.0)
				ci.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 5.0 + dir.orthogonal() * 4.0, tip - dir * 5.0 - dir.orthogonal() * 4.0]), hcol)
	var _wp_moved := false

	## The course point (0: the target, then the waypoints) drawn under `at`, or -1.
	func _course_point_at(at: Vector2) -> int:
		if ship == null or not ship.has_target:
			return -1
		var pts: Array[Vector2] = ship.course()
		for i in range(pts.size() - 1, -1, -1):
			if to_screen(pts[i]).distance_to(at) < 14.0:
				return i
		return -1

	## A dragged course point let go: onto a station / planet / gate under the
	## cursor it snaps to it.
	func _drop_course_point(at: Vector2) -> void:
		var h := _pick(at)
		var p := to_world(at)
		if not h.is_empty():
			p = h["pos"]
		ship.set_course_point(_wp_drag, p)
		GameLog.post("Waypoint %d moved%s." % [_wp_drag + 1, (" to " + h["name"]) if not h.is_empty() else ""], "info")
		queue_redraw()

	func _set_course(at: Vector2, add := false) -> void:
		if ship == null or not ship.is_alive():
			return
		var target := to_world(at)
		var h := _pick(at)
		if not h.is_empty():
			target = h["pos"]
		var named: String = (" " + h["name"]) if not h.is_empty() else ""
		if add and ship.has_target:
			var from: Vector2 = ship.course()[-1]
			ship.add_waypoint(target)
			GameLog.post("Waypoint %d added%s (%.1fk on)." % [ship.course().size(), named, from.distance_to(target) / 1000.0], "info")
		else:
			ship.move_to(target)
			GameLog.post("Course set%s (%.1fk)." % [(" for" + named) if named != "" else "", ship.global_position.distance_to(target) / 1000.0], "info")
		queue_redraw()   # (the map stays open: the course shows on it, the ship flies it)

	## The named thing under the cursor: {name, pos, detail}.
	func _pick(at: Vector2) -> Dictionary:
		var best := {}
		var best_d := 16.0
		var cands := []
		for st in get_tree().get_nodes_in_group("stations"):
			var pres := Galaxy.presence_label(Galaxy.station_presence(st.station_id))
			cands.append({"name": st.station_name, "pos": st.global_position, "detail": "%s station%s (you: %s) - dock to trade, repair and take missions" % [
				Galaxy.EMPIRES.get(st.empire, {}).get("short", "?"), (", " + pres) if pres != "" else "", Galaxy.standing(st.empire)]})
		for p in _planets:
			cands.append({"name": p["name"], "pos": p["pos"], "detail": "Planet - %s" % ("fly here to land" if p["landable"] else "not landable")})
		for g in get_tree().get_nodes_in_group("gates"):
			cands.append({"name": "Gate to " + g.target_name, "pos": g.global_position,
				"detail": "Jump gate - %s space" % Galaxy.empire_name(Galaxy.owner_of(g.target))})
		var star := get_tree().get_first_node_in_group("star")
		if star:
			cands.append({"name": star.star_name + " (star)", "pos": star.global_position, "detail": Galaxy.STARS[Galaxy.system(Galaxy.current_system)["star"]]["name"]})
		for b in get_tree().get_nodes_in_group("signal_beacons"):
			if b.active() and ShipScanner.signal_visible(get_tree(), b.global_position, ship.global_position):
				cands.append({"name": "Objective", "pos": b.global_position, "detail": "Signal source: %s - fly there and ENTER" % b.title()})
		var ms := get_tree().get_first_node_in_group("missions")
		if ms:
			for mk in ms.markers():
				cands.append({"name": "Objective", "pos": mk["pos"], "detail": mk["name"] + " - fly here to scan it"})
		var q := _quest()
		if q and q.target_position() != null:
			cands.append({"name": "Objective", "pos": q.target_position(), "detail": q.objective_text()})
		for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("neutrals"):
			var nm: String = e.display_name if e.display_name != "" else EnemyTypes.get_type(e.type_id).get("name", "Ship")
			cands.append({"name": nm, "pos": e.global_position, "detail": "Neutral" if e.is_neutral() and not e.is_hostile_to_player() else "Hostile"})
		for c in cands:
			if c["name"] != "Objective" and not _seen(c["pos"]):
				continue
			var d := to_screen(c["pos"]).distance_to(at)
			if d < best_d:
				best_d = d
				best = c
		return best

	# --- Drawing -----------------------------------------------------------------------

	## The fog over the unexplored parts (and dark beyond its edges).
	func _draw_fog() -> void:
		var f: FogOfWar = Galaxy.fog()
		var r := Rect2(to_screen(f.origin), Vector2(f.cols, f.rows) * f.cell * scale_)
		draw_texture_rect(f.texture(), r, false)
		var dark := Color(0, 0, 0, f.shade)
		# Beyond the fog's edges (as bands round it, clipped to the view).
		var top := clampf(r.position.y, 0.0, size.y)
		var bottom := clampf(r.end.y, 0.0, size.y)
		var left := clampf(r.position.x, 0.0, size.x)
		var right := clampf(r.end.x, 0.0, size.x)
		for band in [Rect2(0, 0, size.x, top), Rect2(0, bottom, size.x, size.y - bottom),
				Rect2(0, top, left, bottom - top), Rect2(right, top, size.x - right, bottom - top)]:
			if band.size.x > 0.0 and band.size.y > 0.0:
				draw_rect(band, dark)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := Settings.fs("menu", 13)
		draw_rect(Rect2(Vector2.ZERO, size), NeonTheme.BG)
		font = NeonTheme.heavy_font()
		fs = Settings.fs("menu", 15)
		if ship == null:
			return
		# Grid every 1000 units (labelled in k).
		var step := 1000.0 if scale_ > 0.02 else 5000.0
		var w0 := to_world(Vector2.ZERO)
		var w1 := to_world(size)
		var x := floorf(w0.x / step) * step
		while x <= w1.x:
			draw_line(Vector2(to_screen(Vector2(x, 0)).x, 0), Vector2(to_screen(Vector2(x, 0)).x, size.y), Color(NeonTheme.CYAN, 0.07 if x != 0.0 else 0.18))
			x += step
		var y := floorf(w0.y / step) * step
		while y <= w1.y:
			draw_line(Vector2(0, to_screen(Vector2(0, y)).y), Vector2(size.x, to_screen(Vector2(0, y)).y), Color(NeonTheme.CYAN, 0.07 if y != 0.0 else 0.18))
			y += step
		# Star, orbits and gates.
		var star := get_tree().get_first_node_in_group("star")
		if star:
			var sc := to_screen(star.global_position)
			draw_circle(sc, clampf(star.radius * scale_ * 2.5, 14.0, 90.0), Color(star.color, 0.12))
			draw_circle(sc, clampf(star.radius * scale_, 7.0, 40.0), Color(star.color, 0.55))
			MapIcons.badge(self, sc, 18.0, Color(1.0, 0.8, 0.35), "star")
		for p in _planets:
			if _seen(p["pos"]):
				draw_arc(to_screen(p["center"]), p["orbit"] * scale_, 0, TAU, 96, Color(NeonTheme.HEAD, 0.2), 1.0, true)
		for g in get_tree().get_nodes_in_group("gates"):
			if not _seen(g.global_position):
				continue
			var gc := to_screen(g.global_position)
			MapIcons.badge(self, gc, 15.0, MapIcons.CYAN, "gate")
			var gl: String = "GATE › " + g.target_name.to_upper()
			draw_string_outline(font, gc + Vector2(-110, 28), gl, HORIZONTAL_ALIGNMENT_CENTER, 220, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, gc + Vector2(-110, 28), gl, HORIZONTAL_ALIGNMENT_CENTER, 220, fs, NeonTheme.HEAD)
		# The navigation beacon by the star (once seen): scan it in space (right-click) to chart the system.
		for nb in get_tree().get_nodes_in_group("nav_beacons"):
			if not _seen(nb.global_position):
				continue
			var nc := to_screen(nb.global_position)
			var ncol: Color = Color(0.45, 1.0, 0.7) if nb.charted() else MapIcons.ORANGE
			MapIcons.badge(self, nc, 13.0, ncol, "signal")
			var nl := "NAV BEACON" + ("  ·  CHARTED" if nb.charted() else "")
			# (its name on the side away from the star, clear of the star's badge)
			var left: bool = star != null and nb.global_position.x < star.global_position.x
			var lp := nc + Vector2(-20.0 - 260.0 if left else 20.0, fs * 0.35)
			var al := HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
			draw_string_outline(font, lp, nl, al, 260, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, lp, nl, al, 260, fs, ncol)
		# Asteroids.
		for r in get_tree().get_nodes_in_group("asteroids"):
			if not _seen(r.global_position):
				continue
			draw_circle(to_screen(r.global_position), maxf(1.5, 30.0 * scale_), Color(0.85, 0.65, 0.4, 0.7))
		# Planets: shaded disc, name, "LAND" tag.
		for p in _planets:
			if not _seen(p["pos"]):
				continue
			var c := to_screen(p["pos"])
			var rr := clampf(float(p["radius"]) * scale_, 7.0, 60.0)
			# The planet itself (small, shaded), ringed by its map badge.
			draw_circle(c, rr, p["color2"])
			draw_circle(c + Vector2(-rr, -rr) * 0.22, rr * 0.75, Color(p["color"], 0.85))
			var kind := "moon" if p["moon"] else ("ringed" if p["rings"] else "planet")
			var bcol: Color = MapIcons.ORANGE if p["landable"] else MapIcons.CYAN
			draw_arc(c, rr + 6.0, 0, TAU, 40, Color(bcol, 0.9), 2.0, true)
			draw_arc(c, rr + 10.0, 0, TAU, 40, Color(bcol, 0.25), 4.0, true)
			MapIcons.badge(self, c + Vector2(rr + 14.0, -rr - 6.0), 10.0, bcol, kind)
			# Moons: named only zoomed in far enough to see them apart from their
			# planet (hovering one names it anyway), and without the LAND tag.
			if p["moon"] and float(p["orbit"]) * scale_ < 46.0:
				continue
			var label: String = p["name"].to_upper() + ("  ·  LAND" if p["landable"] and not p["moon"] else "")
			draw_string_outline(font, c + Vector2(-120, rr + fs + 12), label, HORIZONTAL_ALIGNMENT_CENTER, 240, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-120, rr + fs + 12), label, HORIZONTAL_ALIGNMENT_CENTER, 240, fs, Color(1.0, 0.78, 0.5) if p["landable"] else NeonTheme.HEAD)
		# Stations.
		for st in get_tree().get_nodes_in_group("stations"):
			if not _seen(st.global_position):
				continue
			var c := to_screen(st.global_position)
			# Not the system owner's (an independent port, an ally's outpost,
			# a forward base): in its own empire's colour, with what it is.
			var guest: bool = st.empire != Galaxy.owner_of(Galaxy.current_system)
			var scol: Color = Galaxy.empire_color(st.empire).lightened(0.2) if guest else NeonTheme.HEAD
			MapIcons.badge(self, c, 15.0, Galaxy.empire_color(st.empire) if guest else MapIcons.CYAN, "station")
			var sl: String = st.station_name.to_upper()
			if guest:
				sl += "  ·  " + Galaxy.presence_label(Galaxy.station_presence(st.station_id)).to_upper()
			draw_string_outline(font, c + Vector2(-160, -24), sl, HORIZONTAL_ALIGNMENT_CENTER, 320, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-160, -24), sl, HORIZONTAL_ALIGNMENT_CENTER, 320, fs, scol)
		# Ships.
		for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("neutrals"):
			if e.global_position.distance_to(ship.global_position) > Galaxy.SENSOR_RANGE:
				continue   # (ships: only those your sensors see now)
			var col := MapIcons.RED
			if e.is_neutral():
				col = MapIcons.ORANGE if e.is_hostile_to_player() else Color(0.5, 1.0, 0.75)
			var ep := to_screen(e.global_position)
			var ev: Vector2 = e.velocity.normalized() if e.velocity.length() > 5.0 else Vector2.UP
			draw_colored_polygon(PackedVector2Array([ep + ev * 6.0, ep + ev.orthogonal() * 4.0 - ev * 4.0, ep - ev.orthogonal() * 4.0 - ev * 4.0]), col)
		_draw_fog()
		if _trading():
			_draw_trade(font, Settings.fs("menu", 13))
		# Located signal sources (on top of the fog).
		for b in get_tree().get_nodes_in_group("signal_beacons"):
			if not b.active():
				continue   # (not located yet: the probes find them)
			var c := to_screen(b.global_position)
			var col: Color = b.color()
			MapIcons.badge(self, c, 15.0, col, "signal", 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0))
			draw_string_outline(font, c + Vector2(-140, 32), b.title(), HORIZONTAL_ALIGNMENT_CENTER, 280, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-140, 32), b.title(), HORIZONTAL_ALIGNMENT_CENTER, 280, fs, col.lightened(0.3))
		# Survey missions' points (on top of the fog: they're where the dark is).
		var ms := get_tree().get_first_node_in_group("missions")
		if ms:
			for mk in ms.markers():
				var c := to_screen(mk["pos"])
				MapIcons.badge(self, c, 14.0, MapIcons.CYAN, "mountain")
				draw_string_outline(font, c + Vector2(-140, 30), mk["name"], HORIZONTAL_ALIGNMENT_CENTER, 280, fs, 4, Color(0, 0, 0, 0.8))
				draw_string(font, c + Vector2(-140, 30), mk["name"], HORIZONTAL_ALIGNMENT_CENTER, 280, fs, NeonTheme.HEAD)
		# Quest objective.
		var q := _quest()
		if q and q.target_position() != null:
			var c := to_screen(q.target_position())
			MapIcons.badge(self, c, 16.0, MapIcons.ORANGE, "quest", 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0))
			var t: String = q.objective_text()
			draw_string_outline(font, c + Vector2(-160, 30), t, HORIZONTAL_ALIGNMENT_CENTER, 320, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-160, 30), t, HORIZONTAL_ALIGNMENT_CENTER, 320, fs, GOLD)
		# Course and ship.
		var sp := to_screen(ship.global_position)
		if ship.has_target:
			# The course: through every waypoint, numbered (Shift + click adds them).
			var pts: Array[Vector2] = ship.course()
			var prev := sp
			for i in pts.size():
				var tp := to_screen(pts[i])
				MapIcons.route(self, prev, tp, MapIcons.ORANGE, 0.0, i > 0, 2.0)
				draw_arc(tp, 7, 0, TAU, 16, MapIcons.ORANGE, 2.0, true)
				if pts.size() > 1:
					draw_circle(tp, 10.0, Color(0, 0, 0, 0.75))
					draw_arc(tp, 10.0, 0, TAU, 20, MapIcons.ORANGE, 2.0, true)
					draw_string(font, tp + Vector2(-10, fs * 0.35), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, maxi(Settings.MIN_FONT, fs - 2), MapIcons.ORANGE)
				prev = tp
		var pts := PackedVector2Array([Vector2(0, -11), Vector2(7.5, 8), Vector2(-7.5, 8)])
		for i in pts.size():
			pts[i] = sp + pts[i].rotated(ship.rotation)
		draw_circle(sp, 18, Color(MapIcons.ORANGE, 0.18))
		draw_arc(sp, 16, 0, TAU, 32, MapIcons.ORANGE, 2.0, true)
		draw_colored_polygon(pts, Color(1.0, 0.7, 0.35))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.7), 1.0, true)
		# Scale bar.
		var units := 1000.0 if scale_ > 0.02 else 5000.0
		var bl := units * scale_
		var b0 := Vector2(16, size.y - 18)
		draw_line(b0, b0 + Vector2(bl, 0), Color(1, 1, 1, 0.7), 2.0)
		draw_string(font, b0 + Vector2(bl + 8, 5), "%dk" % int(units / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.7))
		# Hover info.
		if not _hover.is_empty():
			var mp := get_local_mouse_position()
			var dist := ship.global_position.distance_to(_hover["pos"]) / 1000.0
			var txt: String = "%s  (%.1fk)" % [_hover["name"], dist]
			var det: String = _hover["detail"]
			var wbox := maxf(font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2).x, font.get_string_size(det, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 20
			var box := Rect2(mp + Vector2(16, 12), Vector2(wbox, fs * 2 + 22))
			box.position.x = minf(box.position.x, size.x - box.size.x - 4)
			box.position.y = minf(box.position.y, size.y - box.size.y - 4)
			draw_rect(box, Color(NeonTheme.BG, 0.95))
			draw_rect(box, Color(NeonTheme.HEAD, 0.7), false, 1.0)
			draw_string(font, box.position + Vector2(10, fs + 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2, Color.WHITE)
			draw_string(font, box.position + Vector2(10, fs * 2 + 14), det, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT_DIM)



## The probe scanner's panel beside the map: launch, reach, analyze, recall,
## and what was found (each: its strength; a click shows it on the map, a
## located one can be flown to).
class ProbePanel extends VBoxContainer:
	var page: Node
	var _status: Label
	var _bar: ProgressBar
	var _list: VBoxContainer
	var _reach := 8000.0
	var _t := 0.0
	var _bound := false

	func _ready() -> void:
		add_theme_constant_override("separation", 6)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var ps: ProbeScanner = page.probes()
		if ps and not _bound:
			_bound = true
			ps.changed.connect(func(): if is_visible_in_tree(): rebuild())
		if ps and ps.analyzing >= 0.0 and _bar:
			_bar.value = ps.analyzing / ProbeScanner.ANALYZE_TIME

	func rebuild() -> void:
		for c in get_children():
			c.queue_free()
		_bar = null
		var ps: ProbeScanner = page.probes()
		add_child(UI.section("PROBE SCANNER"))
		if ps == null or not ps.fitted():
			add_child(UI.note("No probe scanner fitted. Outfitters sell them (SYSTEMS): scan probes that find anomalies, ships, planets and structures anywhere in the system.", 14, 320))
			return
		add_child(UI.note("Launch the probes where the map is looking; drag one to move it, the wheel over one changes its reach. Move them all together: drag the gold handle above them (or Shift + drag any probe); the wheel over the handle spreads them out or draws them in, Shift + wheel over a probe changes every reach. Tight probes round a signature raise its strength - at 100% it's located.", 13, 320))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.button("-", func():
			_reach = ProbeScanner.step(_reach, -1)
			ps.step_all(-1), 15))
		var rl := UI.label("reach %.0fk" % (_reach / 1000.0), 15, Color.WHITE)
		rl.custom_minimum_size = Vector2(110, 0)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(rl)
		row.add_child(UI.button("+", func():
			_reach = ProbeScanner.step(_reach, 1)
			ps.step_all(1), 15))
		add_child(row)
		var launch := UI.button("Launch %d probes here" % ProbeScanner.MAX_PROBES, func():
			ps.launch_pattern(page._view.center, _reach), 15)
		launch.tooltip_text = "Probes fly out to where the map is centred, in a ring of the reach shown, one in the middle."
		add_child(launch)
		var go := UI.button("ANALYZE" if ps.analyzing < 0.0 else "Analyzing...", ps.analyze, 16)
		go.disabled = ps.probes.is_empty() or ps.analyzing >= 0.0
		go.tooltip_text = "Reads every signature within the probes' reach (%.1f s once they're in place)." % ProbeScanner.ANALYZE_TIME
		add_child(go)
		if ps.analyzing >= 0.0:
			_bar = ProgressBar.new()
			_bar.max_value = 1.0
			_bar.show_percentage = false
			_bar.custom_minimum_size = Vector2(0, 10)
			add_child(_bar)
		var rc := UI.button("Recall probes", ps.recall, 14)
		rc.disabled = ps.probes.is_empty()
		add_child(rc)
		add_child(UI.section("SIGNATURES  ·  %d" % ps.results.size()))
		var scroll := ScrollContainer.new()
		scroll.name = "Signatures"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		_list = VBoxContainer.new()
		_list.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.add_child(_list)
		add_child(scroll)
		if ps.results.is_empty():
			_list.add_child(UI.label("None yet - launch probes and analyze.", 14, UI.TEXT_DIM))
		for ri in mini(ps.results.size(), LIST_MAX):
			var r: Dictionary = ps.results[ri]
			var st := float(r["strength"])
			var col: Color = ProbeScanner.KINDS[r["kind"]][2]
			var b := UI.button("%3d%%   %s" % [roundi(st * 100.0), ProbeScanner.label(r)], _pick.bind(r), 14)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_color_override("font_color", col if st < 1.0 else col.lightened(0.35))
			b.tooltip_text = ("Located: click to set a course to it." if st >= 1.0 else "Click: the map centres on where it might be. Draw probes tighter round it to pin it down.")
			_list.add_child(b)
		if ps.results.size() > LIST_MAX:
			_list.add_child(UI.label("... and %d fainter ones (on the map)" % (ps.results.size() - LIST_MAX), 13, UI.TEXT_DIM))

	const LIST_MAX := 14   # (the strongest; the rest on the map)

	func _pick(r: Dictionary) -> void:
		var v = page._view
		if float(r["strength"]) >= 1.0 and page.ship and page.ship.is_alive():
			var to: Vector2 = r["node"].global_position if is_instance_valid(r.get("node")) else r["pos"]
			page.ship.move_to(to)
			GameLog.post("Course set for %s (%.1fk)." % [r["name"], page.ship.global_position.distance_to(to) / 1000.0], "info")
		v.center = r["est"] if float(r["strength"]) < 1.0 else r["pos"]
		v.picked_id = r["id"]
		v._fitted = true   # (keep this view: not refitted)
		v.queue_redraw()



class ProbeOverlay extends Control:
	## (Painted off screen - a SubViewport - when it changes, shown as one
	## picture: the dozens of circles and names were a thousand draw calls a frame.)
	var view: Control
	var _vp: SubViewport
	var _paint: Painter

	class Painter extends Control:
		var view: Control
		func _draw() -> void:
			if view and view.ship:
				view._draw_probes(NeonTheme.heavy_font(), Settings.fs("menu", 15), self)

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.transparent_bg = true
		_vp.disable_3d = true
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_vp)
		_paint = Painter.new()
		_paint.view = view
		_vp.add_child(_paint)
		resized.connect(_fit)
		_fit()

	func _fit() -> void:
		_vp.size = Vector2i(maxi(8, int(size.x)), maxi(8, int(size.y)))
		_paint.size = size
		repaint()

	func repaint() -> void:
		if _paint:
			_paint.queue_redraw()
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			queue_redraw()

	func _draw() -> void:
		if _vp:
			draw_texture(_vp.get_texture(), Vector2.ZERO)
