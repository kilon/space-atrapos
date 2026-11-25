class_name CosmosHud
extends Control
## The 3D game's flight display (Cosmos): markers on the planets, moons, the
## star, stations and gates (name and distance; the target boxed, an arrow at
## the edge when it's off screen), the stick reticle, and a panel - speed,
## throttle, the drive's state, the altitude over a planet, the target. H
## shows the controls. Redrawn at 60 Hz (UI.redraw_due).

const ACCENT := Color(0.45, 0.9, 1.0)
const DIM := Color(0.45, 0.9, 1.0, 0.55)
const WARN := Color(1.0, 0.7, 0.3)
const SIZES := [16, 17, 18, 22, 26, 30]   # (its text sizes: CosmosWarm draws them at the title)

var cosmos: Node
var ship: CosmosShip
var cam: Camera3D
var show_help := true
var _font: Font
var note := ""                  # a passing message (jumps, warnings)
var hit_flash := 0.0            # (you were hit: the screen's edge reddens)
var fade := 0.0                 # (docking: the screen to black and back)
var _note_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


## A message: the 2D HUD's (its place, its look) and a line in the event console.
func flash(text: String, secs := 3.5) -> void:
	if cosmos and cosmos.get("hud2d"):
		cosmos.hud2d.flash_message(text)
		GameLog.post(text, "info")
		return
	note = text
	_note_t = secs
	queue_redraw()


func _process(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta)
	if _note_t > 0.0:
		_note_t -= delta
		if _note_t <= 0.0:
			note = ""
	if UI.redraw_due(self):
		queue_redraw()


func _draw() -> void:
	if cosmos == null or ship == null or cam == null:
		return
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))
		if fade >= 0.99:
			return
	var vs := size
	var c := vs * 0.5
	# Markers.
	var raw: Variant = cosmos.target
	var tgt: Node3D = raw if is_instance_valid(raw) else null
	for b: Node3D in cosmos.bodies():
		if cosmos.docked and not b is CosmosShip:
			continue   # (in a hangar: no markers through its walls)
		if b is CosmosShip and cosmos.walker and cosmos.walker.get("deck") == ship.interior:
			continue   # (aboard: no marker on the ship round you)
		var p := b.global_position
		var d := cam.global_position.distance_to(p)
		var is_t := b == tgt
		if cam.is_position_behind(p):
			if is_t:
				_edge_arrow(c, -(cam.unproject_position(p) - c), vs)
			continue
		var s := cam.unproject_position(p)
		if not Rect2(Vector2.ZERO, vs).grow(-20).has_point(s):
			if is_t:
				_edge_arrow(c, s - c, vs)
			continue
		var col := ACCENT if is_t else DIM
		if b is CosmosNpcShip and b.hostile:
			col = WARN if is_t else Color(WARN, 0.7)
		var r := 7.0
		draw_polyline(PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0), s + Vector2(0, -r)]), col, 2.0)
		if is_t:
			draw_rect(Rect2(s - Vector2(18, 18), Vector2(36, 36)), ACCENT, false, 2.0)
		var label: String = cosmos.label_of(b)
		_text(s + Vector2(12, -6), label, 17, col)
		_text(s + Vector2(12, 14), _dist(d - cosmos.radius_of(b)), 16, col)
	if cosmos.walker:
		_draw_foot(vs, c)
		return
	if ship.cruise == 2:
		_streaks(c, vs)
		if ship.well[1] != null and float(ship.well[0]) < 0.9:
			var g := "Gravity well: %s - %d%% speed" % [cosmos.label_of(ship.well[1]), roundi(float(ship.well[0]) * 100.0)]
			var gw := _font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			_text(Vector2(c.x - gw * 0.5, vs.y - 190.0), g, 18, WARN)
	# A targeted ship: where to aim to hit it (the lead), and its shields and hull.
	if tgt is CosmosNpcShip and is_instance_valid(tgt):
		var lead: Vector3 = cosmos.ship_aim()
		if not cam.is_position_behind(lead):
			var lp := cam.unproject_position(lead)
			draw_arc(lp, 12.0, 0, TAU, 20, WARN, 2.0)
			draw_line(lp - Vector2(16, 0), lp + Vector2(16, 0), WARN, 1.0)
	# The stick.
	draw_arc(c, 6.0, 0, TAU, 20, ACCENT, 1.5)
	draw_arc(c, 160.0, 0, TAU, 64, Color(ACCENT, 0.12), 1.5)
	var sp := c + ship.stick * 160.0
	if ship.stick.length() > CosmosShip.DEADZONE:
		draw_line(c, sp, Color(ACCENT, 0.4), 1.5)
	draw_arc(sp, 10.0, 0, TAU, 20, ACCENT, 2.0)
	# Panel.
	var y := vs.y - 300.0   # (above the 2D HUD's toolbar)
	var x := c.x - 260.0
	draw_rect(Rect2(x - 16, y - 16, 552, 140), Color(0.02, 0.05, 0.09, 0.62))
	var spd := ship.speed()
	_text(Vector2(x, y + 22), _speed(spd), 30, ACCENT)
	var mode := "BOOST" if ship.boosting else "FLIGHT"
	if ship.cruise == 2:
		mode = "HYPERION"
	elif ship.cruise == 1:
		mode = "HYPERION CHARGING %d" % ceili(CosmosShip.CRUISE_CHARGE - ship.cruise_t) if ship.cruise_t < CosmosShip.CRUISE_CHARGE else "ALIGN WITH THE TARGET"
	_text(Vector2(x + 260, y + 22), mode, 22, WARN if ship.cruise == 1 else ACCENT)
	# Throttle bar.
	var bw := 520.0
	draw_rect(Rect2(x, y + 40, bw, 14), Color(ACCENT, 0.15))
	var z := bw * 0.2
	draw_rect(Rect2(x + z, y + 40, (bw - z) * maxf(ship.throttle, 0.0), 14), ACCENT)
	if ship.throttle < 0.0:
		var w := z * -ship.throttle / 0.25
		draw_rect(Rect2(x + z - w, y + 40, w, 14), WARN)
	_text(Vector2(x, y + 76), cosmos.where_text(), 18, ACCENT)
	if ship.heat > 0.01:
		var hcol := Color(1.0, 0.75 - ship.heat * 0.5, 0.2)
		draw_rect(Rect2(x + 400, y + 6, 120, 10), Color(hcol, 0.2))
		draw_rect(Rect2(x + 400, y + 6, 120 * ship.heat, 10), hcol)
		_text(Vector2(x + 400, y + 2), "HEAT %d%%" % roundi(ship.heat * 100.0), 16, hcol)
	if tgt:
		var d: float = cam.global_position.distance_to(tgt.global_position) - cosmos.radius_of(tgt)
		var eta := " - %s" % _time(d / spd) if spd > 5.0 else ""
		_text(Vector2(x, y + 102), "Target: %s  %s%s" % [cosmos.label_of(tgt), _dist(d), eta], 18, WARN if tgt is CosmosNpcShip and tgt.hostile else ACCENT)
		if tgt is CosmosNpcShip:
			var ts: CosmosNpcShip = tgt
			draw_rect(Rect2(x + 330, y + 92, 90, 6), Color(0.35, 0.75, 1.0))
			draw_rect(Rect2(x + 330, y + 92, 90 * ts.shield / ts.max_shield, 6), Color(0.6, 0.9, 1.0))
			draw_rect(Rect2(x + 430, y + 92, 90, 6), Color(1.0, 0.65, 0.3, 0.3))
			draw_rect(Rect2(x + 430, y + 92, 90 * ts.hull / ts.max_hull, 6), Color(1.0, 0.65, 0.3))

	if note != "":
		var w := _font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(Vector2(c.x - w * 0.5, 150), note, 26, WARN)


## On foot: the planet, the way back to the ship, the controls.
func _draw_foot(vs: Vector2, c: Vector2) -> void:
	var w: Node3D = cosmos.walker
	var y := vs.y - 250.0
	var x := c.x - 260.0
	draw_rect(Rect2(x - 16, y - 16, 552, 110), Color(0.02, 0.05, 0.09, 0.62))
	_text(Vector2(x, y + 14), cosmos.where_text(), 20, ACCENT)
	var d := w.global_position.distance_to(ship.global_position)
	var term: Array = cosmos.terminal_here()
	var inside: bool = ship.interior != null and w.get("deck") == ship.interior
	if not term.is_empty():
		_text(Vector2(x, y + 44), "E: %s" % term[0], 20, ACCENT)
	elif inside and ship.interior.at_seat(ship.interior.to_local(w.global_position)):
		_text(Vector2(x, y + 44), "E: take the controls", 20, ACCENT)
	elif inside:
		_text(Vector2(x, y + 44), "The pilot's seat: forward, in the cockpit" + ("  -  the ramp: aft, in the hold" if ship.interior.ramp_down else ""), 18, DIM)
	elif d < 60.0:
		_text(Vector2(x, y + 44), "Board up the ramp, under the ship's tail", 18, ACCENT)
	else:
		_text(Vector2(x, y + 44), "Your ship: %s" % _dist(d), 20, DIM)
	# The sights, and what they're on.
	draw_arc(c, 9.0, 0, TAU, 24, ACCENT, 1.5)
	draw_line(c + Vector2(-18, 0), c + Vector2(-11, 0), ACCENT, 1.5)
	draw_line(c + Vector2(11, 0), c + Vector2(18, 0), ACCENT, 1.5)
	var a: Array = cosmos.aim()
	if a[0] != null:
		var t: Node3D = a[0]
		var name: String = CosmosFauna.label(t.kind) if t is CosmosCreature else str(t.get("label"))
		var hostile: bool = (t is CosmosNpc) or (t is CosmosCreature and t.kind["temper"] == "predator")
		_text(c + Vector2(26, -14), name, 18, WARN if hostile else ACCENT)
		var f := float(t.get("hp")) / maxf(float(t.get("max_hp")), 1.0)
		draw_rect(Rect2(c + Vector2(26, -6), Vector2(120, 6)), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(c + Vector2(26, -6), Vector2(120 * f, 6)), WARN if hostile else ACCENT)
		_text(c + Vector2(26, 18), _dist(float(a[2])), 15, DIM)
	if hit_flash > 0.0:
		var k := hit_flash * 0.5
		for i in 6:
			var m := 30.0 + i * 22.0
			draw_rect(Rect2(Vector2.ZERO, vs).grow(-m), Color(1, 0.1, 0.05, k * (1.0 - i / 6.0) * 0.35), false, 22.0)
	if note != "":
		var nw := _font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(Vector2(c.x - nw * 0.5, 150), note, 26, WARN)


## The Hyperion drive at speed: streaks of light rushing out from the middle.
func _streaks(c: Vector2, vs: Vector2) -> void:
	var k := clampf(log(maxf(ship.speed(), 1.0)) / log(CosmosShip.CRUISE_MAX), 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	var r := vs.length() * 0.5
	for i in 90:
		var a := fmod(i * 2.39996, TAU)
		var ph := fmod(t * (0.6 + 1.6 * k) + i * 0.137, 1.0)
		var d := Vector2.from_angle(a)
		var r0 := r * (0.12 + ph * ph)
		var len := r * (0.04 + 0.22 * k) * ph
		draw_line(c + d * r0, c + d * (r0 + len), Color(0.7, 0.9, 1.0, 0.35 * k * ph), 1.5)


func _edge_arrow(c: Vector2, dir: Vector2, vs: Vector2) -> void:
	if dir.length() < 1.0:
		return
	var d := dir.normalized()
	var r := minf(vs.x, vs.y) * 0.42
	var p := c + d * r
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([p + d * 16.0, p - d * 8.0 + n * 10.0, p - d * 8.0 - n * 10.0]), ACCENT)


func _text(at: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _dist(m: float) -> String:
	m = maxf(m, 0.0)
	if m < 1000.0:
		return "%d m" % roundi(m)
	if m < 100000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d km" % roundi(m / 1000.0)


static func _speed(v: float) -> String:
	if v < 1000.0:
		return "%d m/s" % roundi(v)
	return "%.1f km/s" % (v / 1000.0)


static func _time(s: float) -> String:
	if s < 60.0:
		return "%ds" % roundi(s)
	if s < 3600.0:
		return "%dm %02ds" % [int(s / 60.0), int(s) % 60]
	return "%dh" % int(s / 3600.0)
