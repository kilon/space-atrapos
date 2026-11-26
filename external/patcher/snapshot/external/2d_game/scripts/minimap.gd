extends Control
## Circular radar: player in the centre (north up), enemies as red dots.
## Enemies beyond the range are pinned to the rim. Wrecks you can salvage: grey
## diamonds (pinned to the rim too). Stations and planets out
## of range: arrows on the rim only after a system scan (ShipScanner,
## right-click in space), for ShipScanner.ARROW_TIME seconds (scan_until) -
## and so do the signal sources it located (diamonds when in range).

@export var world_radius := 2500.0
## Its frame: a ring (data/sprites/minimap_ring.png, cut from external/images/
## minimap_ring.png, keyed off its magenta - its band solid all round from 0.58 to
## 0.76 of its half-width) round the radar, the radar's edge at RING_HOLE - under the
## band, so there's no gap anywhere between them; and a glass sheen over the
## radar (data/sprites/minimap_glass.png).
const RING_HOLE := 0.6
const RING_FIT := 1.0
var _ring_tex: Texture2D
var _glass_tex: Texture2D


## The ring's size (px, square) round a radar of radius r.
static func ring_size(r: float) -> float:
	return 2.0 * r * RING_FIT / RING_HOLE

var ship: Node2D
var quest: Node
var scan_until := 0                 # Time.get_ticks_msec() the scan's arrows last until


## How strongly the scan's arrows show (0 none .. 1; fading the last 2 s).
func scan_alpha() -> float:
	var left := (scan_until - Time.get_ticks_msec()) / 1000.0
	return clampf(left / 2.0, 0.0, 1.0)
const QUEST_GOLD := Color(1.0, 0.82, 0.38)
## Wrecks you can salvage.
const WRECK_GREY := Color(0.62, 0.64, 0.68)


var _redraw_t := 0.0
const _DOT := [Vector2(2, 0), Vector2(1.41, 1.41), Vector2(0, 2), Vector2(-1.41, 1.41),
		Vector2(-2, 0), Vector2(-1.41, -1.41), Vector2(0, -2), Vector2(1.41, -1.41)]   # (an asteroid's dot: radius 2)

## 30 times a second is plenty for the radar (every frame cost 0.5 ms).
func _process(delta: float) -> void:
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 1.0 / 30.0
		queue_redraw()


## Main-quest objective: gold star in range, gold arrow on the rim otherwise.
func _draw_quest_target(c: Vector2, r: float) -> void:
	if quest == null:
		return
	var target: Variant = quest.target_position()
	if target == null:
		return
	var offset: Vector2 = target - ship.global_position
	var rel := offset / world_radius * r
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 200.0)
	if rel.length() <= r - 12.0:
		var p := c + rel
		var star := PackedVector2Array()
		for i in 8:
			star.append(p + Vector2.from_angle(i * TAU / 8.0 - PI / 2.0) * (8.0 if i % 2 == 0 else 3.5))
		draw_colored_polygon(star, Color(QUEST_GOLD, pulse))
	else:
		var dir := offset.normalized()
		var tip := c + dir * (r + 4.0)
		var base := c + dir * (r - 14.0)
		var side := dir.orthogonal() * 9.0
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(QUEST_GOLD, pulse))
		draw_string(ThemeDB.fallback_font, c + dir * (r - 32.0) + Vector2(-20, 4), "%.1fk" % (offset.length() / 1000.0),
				HORIZONTAL_ALIGNMENT_CENTER, 40, mini(Settings.fs("hud", 11), 22), QUEST_GOLD)


## Stations within range: diamonds in the station's colour.
func _draw_stations(c: Vector2, r: float) -> void:
	for station in get_tree().get_nodes_in_group("stations"):
		var rel: Vector2 = (station.global_position - ship.global_position) / world_radius * r
		if rel.length() > r - 10.0:
			continue
		var p := c + rel
		var s := 6.0
		var diamond := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
		draw_colored_polygon(diamond, station.accent)
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(1, 1, 1, 0.8), 1.0, true)


## Stations out of range: arrows on the rim pointing at them, with distance.
func _draw_station_arrows(c: Vector2, r: float) -> void:
	var font := ThemeDB.fallback_font
	for station in get_tree().get_nodes_in_group("stations"):
		var offset: Vector2 = station.global_position - ship.global_position
		var sa := scan_alpha()
		if offset.length() / world_radius * r <= r - 10.0 or sa <= 0.0:
			continue   # (in range, or no scan running: no arrow)
		var dir := offset.normalized()
		var tip := c + dir * (r - 3.0)
		var base := c + dir * (r - 15.0)
		var side := dir.orthogonal() * 7.0
		var arrow := PackedVector2Array([tip, base + side, base - side])
		draw_colored_polygon(arrow, Color(station.accent, sa))
		draw_polyline(arrow + PackedVector2Array([tip]), Color(0, 0, 0, 0.6), 1.0, true)
		# Distance in thousands of units, just inside the arrow.
		var label := "%.1fk" % (offset.length() / 1000.0)
		var label_pos := c + dir * (r - 30.0) + Vector2(-20, 4)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 40, mini(Settings.fs("hud", 10), 20),
				Color(station.accent, 0.9 * sa))


## Jump gates (ring in the destination owner's colour; arrow on the rim when
## out of range) and the system's star.
func _draw_gates_and_star(c: Vector2, r: float) -> void:
	var star := get_tree().get_first_node_in_group("star")
	if star:
		var rel: Vector2 = (star.global_position - ship.global_position) / world_radius * r
		if rel.length() < r - 8.0:
			draw_circle(c + rel, 7.0, Color(star.color, 0.35))
			draw_circle(c + rel, 4.0, star.color)
	_draw_planets(c, r, star)
	_draw_nav_beacon(c, r)
	for g in get_tree().get_nodes_in_group("gates"):
		var off: Vector2 = g.global_position - ship.global_position
		var rel := off / world_radius * r
		if rel.length() < r - 10.0:
			draw_arc(c + rel, 6.0, 0, TAU, 16, g.accent, 2.0, true)
		elif Galaxy.explored_at(g.global_position):
			var dir := off.normalized()
			var p := c + dir * (r - 7.0)
			draw_arc(p, 5.0, 0, TAU, 12, Color(g.accent, 0.85), 2.0, true)


## The navigation beacon (once its spot is seen): a small hexagon, amber
## until it's charted the system, then green; out of range, a mark on the rim.
func _draw_nav_beacon(c: Vector2, r: float) -> void:
	for b in get_tree().get_nodes_in_group("nav_beacons"):
		if not Galaxy.explored_at(b.global_position):
			continue
		var col: Color = Color(0.45, 1.0, 0.7) if b.charted() else Color(1.0, 0.75, 0.3)
		var off: Vector2 = b.global_position - ship.global_position
		var rel := off / world_radius * r
		var p := c + rel
		var s := 7.0
		if rel.length() > r - 10.0:
			p = c + off.normalized() * (r - 8.0)
			s = 5.5
		var hexa := PackedVector2Array()
		for i in 6:
			hexa.append(p + Vector2.from_angle(i * TAU / 6.0 + PI / 6.0) * s)
		draw_colored_polygon(hexa, Color(0.05, 0.05, 0.05, 0.85))
		hexa.append(hexa[0])   # (the outline closed - the fill takes the 6 corners only)
		draw_polyline(hexa, col, 2.0, true)
		draw_circle(p, s * 0.38, col)


## Planets within range: small discs in the planet's colours, lit from the
## star's side, with a ring for ringed worlds; landable ones get a thin halo.
func _draw_planets(c: Vector2, r: float, star: Node) -> void:
	for b in get_tree().get_nodes_in_group("planet_bodies"):
		var rel: Vector2 = (b.global_position - ship.global_position) / world_radius * r
		var s: float = clampf(b.radius / 45.0, 6.0, 10.0) if b.parent_body == null else 4.0
		var far := rel.length() > r - s - 2.0
		if far:   # out of range: after a system scan, an arrow on the rim pointing at it
			if b.parent_body != null or scan_alpha() <= 0.0:
				continue
			var dir := rel.normalized()
			var tip := c + dir * (r - 3.0)
			var base := c + dir * (r - 15.0)
			var col: Color = b.spec.get("color_light", Color(0.65, 0.75, 0.85))
			draw_colored_polygon(PackedVector2Array([tip, base + dir.orthogonal() * 6.0, base - dir.orthogonal() * 6.0]), Color(col, scan_alpha()))
			s = 4.0
			rel = dir * (r - 22.0)
		var p := c + rel
		var spec: Dictionary = b.spec
		var light: Color = spec.get("color_light", Color(0.65, 0.75, 0.85))
		var dark: Color = spec.get("color_dark", Color(0.25, 0.3, 0.4))
		var to_sun := Vector2(-0.6, -0.6)
		if star:
			to_sun = (star.global_position - b.global_position).normalized()
		var ringed := float(spec.get("rings", 0.0)) > 0.0
		if ringed:   # back half of the ring
			_ring(p, s, Color(light.lightened(0.2), 0.8), PI, TAU)
		draw_circle(p, s, dark)
		draw_circle(p + to_sun * s * 0.3, s * 0.72, light)
		draw_circle(p + to_sun * s * 0.5, s * 0.3, light.lightened(0.35))
		if ringed:   # front half
			_ring(p, s, Color(light.lightened(0.2), 0.9), 0.0, PI)
		if b.landable and not far:
			draw_arc(p, s + 2.5, 0, TAU, 20, Color(NeonTheme.HEAD, 0.6), 1.0, true)


## A flattened ring arc round a planet icon.
func _ring(p: Vector2, s: float, col: Color, from: float, to: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := lerpf(from, to, i / 12.0)
		pts.append(p + Vector2(cos(a) * s * 1.9, sin(a) * s * 0.55).rotated(-0.35))
	draw_polyline(pts, col, 1.5, true)


## Located signal sources: a pulsing diamond in their colour when in range,
## an arrow on the rim (while a scan's arrows last) when not.
func _draw_signals(c: Vector2, r: float) -> void:
	var sa := scan_alpha()
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)
	for b in get_tree().get_nodes_in_group("signal_beacons"):
		if not b.active():
			continue
		if not ShipScanner.signal_visible(get_tree(), b.global_position, ship.global_position):
			continue   # (out of range: not on the radar either)
		var col: Color = b.color()
		var rel: Vector2 = (b.global_position - ship.global_position) / world_radius * r
		if rel.length() < r - 8.0:
			var p := c + rel
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), Color(col, pulse))
		elif sa > 0.0:
			var dir := rel.normalized()
			var tip := c + dir * (r - 3.0)
			var base := c + dir * (r - 15.0)
			draw_colored_polygon(PackedVector2Array([tip, base + dir.orthogonal() * 6.0, base - dir.orthogonal() * 6.0]), Color(col, sa))
			var q := c + dir * (r - 24.0)
			draw_colored_polygon(PackedVector2Array([q + Vector2(0, -4), q + Vector2(4, 0), q + Vector2(0, 4), q + Vector2(-4, 0)]), Color(col, sa * pulse))


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	if _ring_tex == null:
		_ring_tex = ProcArt.sprite("minimap_ring")
		_glass_tex = ProcArt.sprite("minimap_glass")

	draw_circle(c, r, Color(NeonTheme.BG, 0.92))
	draw_arc(c, r * 0.5, 0, TAU, 48, Color(NeonTheme.HEAD, 0.15), 1.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(NeonTheme.HEAD, 0.12))
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(NeonTheme.HEAD, 0.12))
	draw_arc(c, r - 1.0, 0, TAU, 64, Color(NeonTheme.HEAD, 0.7), 2.0, true)

	if ship == null:
		_draw_frame(c, r)
		return

	_draw_stations(c, r)
	_draw_gates_and_star(c, r)
	_draw_signals(c, r)

	# Asteroids: small grey dots (within range only) - all in one batch of
	# little octagons (a ring of hundreds, a draw_circle each, was ~1 ms a redraw).
	var me: Vector2 = ship.global_position
	var k := r / world_radius
	var lim := (r - 4.0) * (r - 4.0)
	var dots := PackedVector2Array()
	var dot_idx := PackedInt32Array()
	for rock in get_tree().get_nodes_in_group("asteroids"):
		var rel: Vector2 = ((rock as Node2D).global_position - me) * k
		if rel.length_squared() < lim:
			var b := dots.size()
			var p := c + rel
			dots.append(p)
			for o in _DOT:
				dots.append(p + o)
			for t in 8:
				dot_idx.append_array([b, b + 1 + t, b + 1 + (t + 1) % 8])
	if not dots.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), dot_idx, dots, PackedColorArray([Color(0.65, 0.62, 0.58, 0.7)]))

	# Wrecks waiting to be salvaged: grey diamonds (a station's bigger), on
	# the rim when out of range - the dots are ships, the small grey dots rocks.
	for w in get_tree().get_nodes_in_group("wrecks"):
		if w.salvaged:
			continue
		var wrel: Vector2 = (w.global_position - ship.global_position) / world_radius * r
		var w_rim := wrel.length() > r - 6.0
		if w_rim:
			wrel = wrel.normalized() * (r - 6.0)
		var wp := c + wrel
		var ws := (3.0 if w_rim else (6.0 if w.kind == "station" else 4.5))
		var dia := PackedVector2Array([wp + Vector2(0, -ws), wp + Vector2(ws, 0), wp + Vector2(0, ws), wp + Vector2(-ws, 0)])
		draw_colored_polygon(dia, Color(WRECK_GREY, 0.45 if w_rim else 0.85))
		draw_polyline(dia + PackedVector2Array([dia[0]]), Color(0.08, 0.08, 0.1, 0.8), 1.0, true)

	# Ships: hostile red, neutral green (orange once provoked).
	for enemy in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("neutrals"):
		var rel: Vector2 = (enemy.global_position - ship.global_position) / world_radius * r
		var on_rim := rel.length() > r - 6.0
		if on_rim:
			rel = rel.normalized() * (r - 6.0)
		var p := c + rel
		var col := Color(1.0, 0.3, 0.25)
		if enemy.is_neutral():
			col = Color(1.0, 0.6, 0.2) if enemy.is_hostile_to_player() else Color(0.4, 1.0, 0.5)
		draw_circle(p, 2.5 if on_rim else 4.0, Color(col, 0.55 if on_rim else 1.0))
		if enemy.targeted:
			draw_arc(p, 7.0, 0, TAU, 16, Color(1.0, 0.5, 0.4), 1.5, true)

	# Weapon range ring.
	var wr: float = ship.weapon_range / world_radius * r
	draw_arc(c, wr, 0, TAU, 40, Color(NeonTheme.HEAD, 0.25), 1.0, true)

	_draw_station_arrows(c, r)
	_draw_quest_target(c, r)

	# Player arrow.
	if ship.is_alive():
		var pts := PackedVector2Array([Vector2(0, -8), Vector2(5.5, 6), Vector2(-5.5, 6)])
		for i in pts.size():
			pts[i] = c + pts[i].rotated(ship.rotation)
		draw_colored_polygon(pts, NeonTheme.HEAD)
	_draw_frame(c, r)


## The glass over the radar and the ring round it.
func _draw_frame(c: Vector2, r: float) -> void:
	if _glass_tex:
		draw_texture_rect(_glass_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	if _ring_tex:
		var s := ring_size(r)
		draw_texture_rect(_ring_tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false)
