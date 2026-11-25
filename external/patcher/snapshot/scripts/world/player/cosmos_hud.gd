class_name CosmosHud
extends Control
## The 3D game's flight display (Cosmos): markers on the planets, moons, the
## star, stations and gates (name and distance; the target boxed, an arrow at
## the edge when it's off screen), the stick reticle, and a panel - speed,
## throttle, the drive's state, the altitude over a planet, the target. H
## shows the controls. Redrawn at 60 Hz (UI.redraw_due).

## The theme's colours (NeonTheme: set when the HUD's made - the empire's palette).
var ACCENT := Color(0.45, 0.9, 1.0)
var DIM := Color(0.45, 0.9, 1.0, 0.55)
var WARN := Color(1.0, 0.7, 0.3)
const SIZES := [14, 15, 16, 17, 18, 20, 22, 26, 28, 30]   # (its text sizes, and the target window's: CosmosWarm draws them at the title)

var cosmos: Node
var ship: CosmosShip
var cam: Camera3D
var show_help := true
var _font: Font
var note := ""                  # a passing message (jumps, warnings)
var hit_flash := 0.0            # (you were hit: the screen's edge reddens)
var fade := 0.0                 # (docking: the screen to black and back)
var _note_t := 0.0
var draw_usec := 0              # (the compass's and the sights' last drawing took, µs - the tests time it)
var texts = null                # (the tests: an Array set here gathers every text drawn)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()   # (the game's theme: the HUD's own font)
	ACCENT = NeonTheme.CYAN
	DIM = Color(NeonTheme.TEXT_DIM, 0.9)
	WARN = Color(1.0, 0.42, 0.3)
	_layers()


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_mask_sync):
		RenderingServer.frame_pre_draw.connect(_mask_sync)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_mask_sync):
		RenderingServer.frame_pre_draw.disconnect(_mask_sync)


## Whether a body gets a marker (on screen, and on the compass bar).
func _marked(b: Node3D, tgt: Node3D) -> bool:
	if (cosmos.docked and not b is CosmosShip) or cosmos.dungeon != null:
		return false   # (in a hangar: no markers through its walls)
	if b is CosmosShip and cosmos.walker and cosmos.walker.get("deck") == ship.interior:
		return false   # (aboard: no marker on the ship round you)
	if b is CosmosNpcShip and b == cosmos.riding():
		return false   # (aboard another's ship: none on it either)
	if cosmos.walker and b != tgt and not (b is CosmosShip or b is CosmosTown) and b.global_position.distance_to(cam.global_position) > 5000.0:
		return false   # (on foot: what's near, your ship, the towns, your target)
	if b is CosmosTown and cam.global_position.distance_to(b.global_position) < float(b.site["r"]):
		return false   # (in it: no marker of its own in the middle of the street)
	return true


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
	if texts != null:
		texts.clear()   # (the last drawing's)
	_want_sights = false
	_want_compass = false
	_draw_all()
	_show_layer(_sights_layer, _want_sights)
	_show_layer(_sights_dyn, _want_sights)
	_show_layer(_compass_layer, _want_compass)


var _want_sights := false
var _cross_on := false           # (the sights' crosshair: locked on a hostile)
var _alt_on := false             # (ALT: near a world's ground)
var _cross_k := 0.0              # (how far each's unfolded: 0 folded away - 1 out; eased there in FOLD_TIME)
var _alt_k := 0.0
var _fold_at := 0                # (ticks, ms: the last step)
const FOLD_TIME := 0.28          # s
const ALT_SHOW := 15000.0        # m over the ground: ALT shown nearer than this ...
const ALT_HIDE := 18000.0        # ... and hidden again past this
var _want_compass := false


func _draw_all() -> void:
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
		if not _marked(b, tgt):
			continue
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
		if (b is CosmosNpcShip and b.hostile) or b is CosmosMonster:
			col = WARN if is_t else Color(WARN, 0.7)
		var r := 7.0
		draw_polyline(PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0), s + Vector2(0, -r)]), col, 2.0)
		if is_t:
			draw_rect(Rect2(s - Vector2(18, 18), Vector2(36, 36)), ACCENT, false, 2.0)
		var label: String = cosmos.label_of(b)
		_text(s + Vector2(12, -6), label, 17, col)
		_text(s + Vector2(12, 14), _dist(d - cosmos.radius_of(b)), 16, col)
	if not cosmos.dock_pad.is_empty() and not cosmos.docked and is_instance_valid(cosmos.dock_station):
		_draw_pad(vs, c)
	var t0 := Time.get_ticks_usec()
	var hd := compass_heading()
	if hd >= 0.0:
		_want_compass = true
		_draw_compass(vs, hd)
	draw_usec = Time.get_ticks_usec() - t0
	if cosmos.walker:
		_draw_scan(vs, c)
		_draw_foot(vs, c)
		return
	if ship.cruise == 2:
		_streaks(c, vs)
		if ship.well[1] != null and float(ship.well[0]) < 0.9:
			var g := "Gravity well: %s - %d%% speed" % [cosmos.label_of(ship.well[1]), roundi(float(ship.well[0]) * 100.0)]
			var gw := _font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			_text(Vector2(c.x - gw * 0.5, vs.y - 190.0), g, 18, WARN)
	# A targeted ship: where to aim to hit it (the lead), and its shields and hull.
	if (tgt is CosmosNpcShip or tgt is CosmosMonster) and is_instance_valid(tgt):
		var lead: Vector3 = cosmos.ship_aim()
		if not cam.is_position_behind(lead):
			var lp := cam.unproject_position(lead)
			draw_arc(lp, 12.0, 0, TAU, 20, WARN, 2.0)
			draw_line(lp - Vector2(16, 0), lp + Vector2(16, 0), WARN, 1.0)
	_want_sights = true
	# (the crosshair only locked on a hostile; ALT only near a world's ground - their fixed lines repainted when that changes)
	var cross: bool = is_instance_valid(tgt) and ((tgt is CosmosNpcShip and (tgt.hostile or tgt.kind == "pirate")) or tgt is CosmosMonster)
	var ng := nearest_ground()
	var near: bool = ng[0] != null and float(ng[1]) < (ALT_HIDE if _alt_on else ALT_SHOW)
	_cross_on = cross
	_alt_on = near
	_sights_dyn.queue_redraw()   # (its moving parts: on their layer, under the ship's mask)
	draw_usec += _sights_usec
	_draw_readout(tgt)
	_draw_mining(vs, c)
	_draw_prompt(vs, c)
	if note != "":
		var w := _font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(Vector2(c.x - w * 0.5, 150), note, 26, WARN)


## The ship's readout beside its gauge (the 2D HUD's, top left): the drive
## (flight, boost, Hyperion's state), the throttle, heat; latitude and longitude
## over a planet, the guns and their ammo. (The heading, the speed and the
## altitude are the sights' - the compass bar, VEL and ALT.)
func _draw_readout(tgt: Node3D) -> void:
	var g: Control = cosmos.hud2d.gauge if cosmos.get("hud2d") and cosmos.hud2d.gauge else null
	var gr := g.get_global_rect() if g else Rect2(80, 60, 180, 180)
	var c := gr.get_center()
	var r := gr.size.x * 0.5 + 6.0
	var col := WARN if ship.cruise > 0 else ACCENT
	var x := c.x + r + 30.0
	var y := gr.position.y + 6.0
	var mode := "BOOST" if ship.boosting else "FLIGHT"
	if ship.cruise == 2:
		mode = "HYPERION ON"
	elif ship.cruise == 1:
		mode = ("HYPERION %d" % ceili(CosmosShip.CRUISE_CHARGE - ship.cruise_t)) if ship.cruise_t < CosmosShip.CRUISE_CHARGE else "HYPERION: ALIGN"
	_text(Vector2(x, y + 22), mode + ("  -  well %d%%" % roundi(float(ship.well[0]) * 100.0) if ship.cruise == 2 and float(ship.well[0]) < 0.95 else ""), 20, col)
	var ty := y + 34.0
	draw_rect(Rect2(x, ty, 200, 6), Color(ACCENT, 0.15))
	draw_rect(Rect2(x + 40, ty, 160 * maxf(ship.throttle, 0.0), 6), ACCENT)
	if ship.throttle < 0.0:
		draw_rect(Rect2(x + 40 - 40 * -ship.throttle / CosmosShip.REVERSE, ty, 40 * -ship.throttle / CosmosShip.REVERSE, 6), WARN)
	draw_line(Vector2(x + 40, ty - 4), Vector2(x + 40, ty + 10), Color(ACCENT, 0.8), 2.0)   # (zero)
	_text(Vector2(x + 210, ty + 10), "%+d%%" % roundi(ship.throttle * 100.0) if ship.throttle != 0.0 else "0%", 16, WARN if ship.throttle < 0.0 else ACCENT)
	var line := ty + 32.0
	var pl: CosmosPlanet = cosmos.nearest_planet(ship.global_position)
	if pl and ship.global_position.distance_to(pl.global_position) < pl.radius * 3.0:
		var u := (ship.global_position - pl.global_position).normalized()
		var lat := rad_to_deg(asin(clampf(u.y, -1.0, 1.0)))
		var lon := rad_to_deg(atan2(u.x, u.z))
		_text(Vector2(x, line), "%.2f° %s   %.2f° %s" % [absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"], 17, ACCENT)
		line += 22.0
	if ship.heat > 0.01:
		var hcol := Color(1.0, 0.75 - ship.heat * 0.5, 0.2)
		_text(Vector2(x, line), "HEAT %d%%" % roundi(ship.heat * 100.0), 17, hcol)
		draw_rect(Rect2(x + 90, line - 10, 110, 8), Color(hcol, 0.2))
		draw_rect(Rect2(x + 90, line - 10, 110 * ship.heat, 8), hcol)
		line += 22.0
	# Guns and ammo.
	var kinds := {}
	for gn in ship.guns:
		kinds[gn["name"]] = int(kinds.get(gn["name"], 0)) + 1
	var parts := []
	for n in kinds:
		parts.append("%s%s" % [n, (" x%d" % kinds[n]) if kinds[n] > 1 else ""])
	var missiles: int = CosmosGame.data.count("missile") if CosmosGame.data else 0
	_text(Vector2(gr.position.x - 40, gr.end.y + 52), ", ".join(parts) + ("   Missiles: %d" % missiles if missiles > 0 or ship.guns.any(func(gg): return gg["ammo"] != "") else ""), 16, ACCENT)
	# (the target: its own window under this - CosmosTargetView)


## The jet pack's charge (on foot, while it's not full or firing): a bar under the
## sights - its level; at the top level, the height and the speed instead.
func _draw_jet(vs: Vector2, c: Vector2, w: Node3D) -> void:
	if not w is CosmosWalker or w.deck != null:
		return
	var lv: int = w.jet_level
	var top := lv >= CosmosWalker.JET.size() - 1
	var full: float = CosmosWalker.JET[lv][0]
	if not w.jetting and (top or w.jet_fuel >= full - 0.01) and (w.on_ground or w.swimming or w.diving):   # (afloat or under the sea: no jet to show)
		return
	var at := Vector2(c.x - 110, vs.y - 290)   # (over the box of where you are: clear of you)
	var col := Color(0.45, 0.75, 1.0)
	if top:
		var alt: float = w.height_above_ground()
		_text(at, "JET  %s up  %s" % [_dist(alt), _speed(w.velocity.length())], 17, col)
		return
	var k := clampf(w.jet_fuel / full, 0.0, 1.0)
	_text(at + Vector2(0, -6), "JET L%d" % lv, 15, col)
	draw_rect(Rect2(at + Vector2(60, -16), Vector2(160, 8)), Color(col, 0.2))
	draw_rect(Rect2(at + Vector2(60, -16), Vector2(160 * k, 8)), col if k > 0.2 else WARN)


## Mining (CosmosMining): the targeted rock's veins marked on it as it turns
## (the one being cut ringed), and over the toolbar the readout - the scan,
## what the rock holds, the vein's heat on its bar with the cutting band in
## green, the resonance, what you've cut from it.
func _draw_mining(vs: Vector2, c: Vector2) -> void:
	var m: CosmosMining = cosmos.get("mining")
	if m == null or not is_instance_valid(m.proxy) or m.field == null or m.rock < 0:
		return
	var st := m.rock_state()
	var title := m.proxy.name
	var y := vs.y - 330.0
	var x := c.x - 260.0
	if st["scanned"]:
		for k in st["veins"].size():
			var v: Dictionary = st["veins"][k]
			if int(v["units"]) <= 0:
				continue
			var p: Vector3 = m.field.vein_at(m.rock, v)
			if cam.is_position_behind(p):
				continue
			var s := cam.unproject_position(p)
			var col := Mining.mineral_color(str(v["mineral"]))
			var r := 6.0
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0)]), col)
			if k == m.vein:
				draw_arc(s, 13.0, 0, TAU, 24, ACCENT, 2.0)
	draw_rect(Rect2(x - 12, y - 26, 544, 118), Color(0, 0, 0, 0.45))
	if not st["scanned"]:
		var k := clampf(m.scan_t / CosmosMining.SCAN_TIME, 0.0, 1.0)
		_text(Vector2(x, y), "%s  -  %s" % [title, ("scanning %d%%" % roundi(k * 100.0)) if k > 0.0 else "not scanned: come within 3 km"], 18, ACCENT)
		draw_rect(Rect2(x, y + 12, 520, 6), Color(ACCENT, 0.15))
		draw_rect(Rect2(x, y + 12, 520 * k, 6), ACCENT)
		_text(Vector2(x, y + 44), "Fire at it: rubble only until it's scanned", 16, DIM)
		return
	_text(Vector2(x, y), "%s  -  %s" % [title, m.comp_text()], 16, ACCENT)
	if m.vein >= 0 and m.vein < st["veins"].size():
		var v: Dictionary = st["veins"][m.vein]
		var heat := float(v["heat"])
		var name: String = Items.ITEMS.get(v["mineral"], {}).get("name", v["mineral"])
		_text(Vector2(x, y + 26), "Vein: %s  -  %d left" % [name, int(v["units"])], 17, Mining.mineral_color(str(v["mineral"])))
		var bx := Rect2(x, y + 36, 520, 12)
		draw_rect(bx, Color(ACCENT, 0.12))
		draw_rect(Rect2(bx.position.x + bx.size.x * Mining.BAND.x, bx.position.y, bx.size.x * (Mining.BAND.y - Mining.BAND.x), bx.size.y), Color(0.3, 0.9, 0.4, 0.35))
		var hc := Color(0.3, 0.9, 0.4) if Mining.in_band(heat) else (WARN if heat > Mining.BAND.y else ACCENT)
		draw_rect(Rect2(bx.position, Vector2(bx.size.x * clampf(heat, 0.0, 1.0), bx.size.y)), hc)
		_text(Vector2(x + 380, y + 26), "resonance x%.1f" % float(v["res"]), 16, Color(0.3, 0.9, 0.4) if float(v["res"]) > 1.05 else DIM)
	else:
		_text(Vector2(x, y + 26), "Aim at a vein and fire to cut it", 16, DIM)
	var parts: Array = []
	for mn in m.cut:
		parts.append("%s %d" % [Items.ITEMS.get(mn, {}).get("name", mn.capitalize()), int(m.cut[mn])])
	_text(Vector2(x, y + 74), ("Cut: " + ", ".join(parts)) if not parts.is_empty() else "Keep the heat in the green: resonance builds, the vein cuts faster", 16, DIM)


## Your pad: its marker (an arrow at the edge when off the screen), and over
## it the height, the drift off its middle and the speed to set down.
func _draw_pad(vs: Vector2, c: Vector2) -> void:
	var st: CosmosStation = cosmos.dock_station
	var xf := st.pad_transform(cosmos.dock_pad)
	var p := xf.origin
	var id := int(cosmos.dock_pad["id"])
	if cam.is_position_behind(p):
		_edge_arrow(c, -(cam.unproject_position(p) - c), vs)
	else:
		var s := cam.unproject_position(p)
		if Rect2(Vector2.ZERO, vs).grow(-20).has_point(s):
			draw_rect(Rect2(s - Vector2(14, 14), Vector2(28, 28)), ACCENT, false, 2.0)
			draw_line(s + Vector2(-20, 0), s + Vector2(-8, 0), ACCENT, 2.0)
			draw_line(s + Vector2(8, 0), s + Vector2(20, 0), ACCENT, 2.0)
			_text(s + Vector2(18, -8), "Pad %d" % id, 17, ACCENT)
			_text(s + Vector2(18, 12), _dist(cam.global_position.distance_to(p)), 16, ACCENT)
		else:
			_edge_arrow(c, s - c, vs)
	if cosmos.walker:
		return
	var l := xf.affine_inverse() * ship.global_position
	if l.y < -2.0 or l.y > LAND_NEAR or Vector2(l.x, l.z).length() > LAND_NEAR:
		return
	_draw_landing(vs, xf, l, id)


## Within this of your pad (m) the landing display shows.
const LAND_NEAR := 600.0
const LAND_RANGES := [30.0, 60.0, 120.0, 250.0, 600.0]


## Setting down on a pad: in the view, the pad's square outlined and the
## point under the ship dropped onto its deck; beside it the landing display
## - the scope (the pad from above, the ship in the middle nose up: steer the
## square onto it, the line your drift), the height tape with the climb or
## sink rate, the level bubble (inside its ring: level enough), the thrust
## (signed: backward and down are negative) and what still stops a touchdown.
func _draw_landing(vs: Vector2, xf: Transform3D, l: Vector3, id: int) -> void:
	var half := float(cosmos.dock_pad["size"]) * 0.5
	var pu := xf.basis.y.normalized()
	var v := ship.velocity
	var vl := xf.basis.inverse() * v
	var h := maxf(l.y - CosmosShip.GEAR, 0.0)
	var over := absf(l.x) <= half and absf(l.z) <= half
	var lvl := ship.global_basis.y.dot(pu) >= 0.85
	var slow := v.length() <= Cosmos.PAD_SPEED
	var off_deg := Cosmos.pad_heading_off(xf, -ship.global_basis.z)
	var square := off_deg <= Cosmos.PAD_ALIGN
	var good := Color(0.45, 1.0, 0.55)
	# In the view: the pad's edges, and the ship's drop line onto the deck.
	var pts := PackedVector2Array()
	for k in 5:
		var q: Vector3 = xf * (Vector3([-1, 1, 1, -1][k % 4], 0.0, [-1, -1, 1, 1][k % 4]) * half)
		if cam.is_position_behind(q):
			pts.clear()
			break
		pts.append(cam.unproject_position(q))
	if pts.size() == 5:
		draw_polyline(pts, Color(good if over else ACCENT, 0.9), 2.0)
		# (its top edge - toward the station: where the nose goes - bold, a chevron past it, the axis down the middle)
		draw_line(pts[0], pts[3], Color(good if square else WARN, 0.95), 5.0)
		var axis: Array = []
		for q in [Vector3(half * 0.9, 0, 0), Vector3(-half * 0.9, 0, 0), Vector3(-half - 10.0, 0, -8.0), Vector3(-half - 18.0, 0, 0), Vector3(-half - 10.0, 0, 8.0)]:
			var wq: Vector3 = xf * q
			if cam.is_position_behind(wq):
				axis.clear()
				break
			axis.append(cam.unproject_position(wq))
		if axis.size() == 5:
			var n := 14
			for k in n:
				if k % 2 == 0:
					draw_line((axis[0] as Vector2).lerp(axis[1], float(k) / n), (axis[0] as Vector2).lerp(axis[1], float(k + 1) / n), Color(ACCENT, 0.7), 2.0)
			draw_polyline(PackedVector2Array([axis[2], axis[3], axis[4]]), Color(good if square else WARN, 0.95), 3.0)
	var foot: Vector3 = xf * Vector3(l.x, 0.0, l.z)
	if not cam.is_position_behind(foot) and not cam.is_position_behind(ship.global_position):
		var f2 := cam.unproject_position(foot)
		var s2 := cam.unproject_position(ship.global_position)
		var n := int(f2.distance_to(s2) / 12.0)
		for k in n:
			if k % 2 == 0:
				draw_line(s2.lerp(f2, float(k) / n), s2.lerp(f2, float(k + 1) / n), Color(good if over else WARN, 0.8), 2.0)
		draw_arc(f2, 9.0, 0, TAU, 20, good if over else WARN, 2.0)
	# The panel.
	var w := 340.0
	var x0 := vs.x - w - 40.0
	var y0 := vs.y * 0.5 - 250.0
	draw_rect(Rect2(x0, y0, w, 470.0), Color(0.02, 0.05, 0.09, 0.86))
	draw_rect(Rect2(x0, y0, w, 470.0), Color(ACCENT, 0.35), false, 1.5)
	_text(Vector2(x0 + 16, y0 + 30), "PAD %d" % id, 22, ACCENT)
	var can := over and lvl and slow and square and h < 6.0
	var st := "TOUCHDOWN" if can else ("OVER THE PAD" if over else "OFF THE PAD")
	var sw := _font.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_text(Vector2(x0 + w - 16 - sw, y0 + 28), st, 18, good if over else WARN)
	# The scope: the deck from above, the ship's nose up.
	var sc := Vector2(x0 + 128, y0 + 168)
	var sr := 104.0
	var fl := xf.basis.inverse() * -ship.global_basis.z
	var fh := Vector2(fl.x, fl.z)
	fh = fh.normalized() if fh.length() > 0.05 else Vector2(0, -1)
	var rh := Vector2(-fh.y, fh.x)
	var dist := Vector2(l.x, l.z).length()
	var rng: float = LAND_RANGES[-1]
	for r in LAND_RANGES:
		if r >= maxf(dist + half, half * 1.8):
			rng = r
			break
	var k := sr / rng
	var to_scope := func(p: Vector2) -> Vector2:   # (a deck point, from the ship: to the scope)
		return sc + Vector2(p.dot(rh), -p.dot(fh)) * k
	draw_arc(sc, sr, 0, TAU, 48, Color(ACCENT, 0.5), 1.5)
	draw_arc(sc, sr * 0.5, 0, TAU, 36, Color(ACCENT, 0.18), 1.0)
	draw_line(sc - Vector2(sr, 0), sc + Vector2(sr, 0), Color(ACCENT, 0.15), 1.0)
	draw_line(sc - Vector2(0, sr), sc + Vector2(0, sr), Color(ACCENT, 0.15), 1.0)
	_text(Vector2(x0 + 16, y0 + 62), "range %s" % _dist(rng), 16, DIM)
	var me := Vector2(l.x, l.z)
	var sq := PackedVector2Array()
	for q in 5:
		var cp := Vector2([-1, 1, 1, -1][q % 4], [-1, -1, 1, 1][q % 4]) * half
		var p: Vector2 = to_scope.call(cp - me)
		sq.append(sc + (p - sc).limit_length(sr))
	draw_polyline(sq, good if over else ACCENT, 2.5)
	# (the pad's top edge, bold - the nose goes there - a chevron past it, its axis)
	var top_a: Vector2 = to_scope.call(Vector2(-half, -half) - me)
	var top_b: Vector2 = to_scope.call(Vector2(-half, half) - me)
	draw_line(sc + (top_a - sc).limit_length(sr), sc + (top_b - sc).limit_length(sr), good if square else WARN, 5.0)
	var ax0: Vector2 = to_scope.call(Vector2(half, 0) - me)
	var ax1: Vector2 = to_scope.call(Vector2(-half - rng * 0.12, 0) - me)
	draw_line(sc + (ax0 - sc).limit_length(sr), sc + (ax1 - sc).limit_length(sr), Color(ACCENT, 0.45), 1.5)
	var chev_tip: Vector2 = to_scope.call(Vector2(-half - rng * 0.12, 0) - me)
	if chev_tip.distance_to(sc) < sr:
		var dn := (chev_tip - (to_scope.call(Vector2(-half, 0) - me) as Vector2)).normalized()
		var nn2 := Vector2(-dn.y, dn.x)
		draw_polyline(PackedVector2Array([chev_tip - dn * 10.0 + nn2 * 8.0, chev_tip, chev_tip - dn * 10.0 - nn2 * 8.0]), good if square else WARN, 3.0)
	var mid: Vector2 = to_scope.call(-me)
	if mid.distance_to(sc) <= sr:
		draw_line(mid - Vector2(6, 0), mid + Vector2(6, 0), good if over else ACCENT, 2.0)
		draw_line(mid - Vector2(0, 6), mid + Vector2(0, 6), good if over else ACCENT, 2.0)
	else:
		var dd := (mid - sc).normalized()
		var tip := sc + dd * (sr + 4.0)
		var nn := Vector2(-dd.y, dd.x)
		draw_colored_polygon(PackedVector2Array([tip + dd * 12.0, tip + nn * 8.0, tip - nn * 8.0]), ACCENT)
	# The drift (the ship's sideways and ahead motion over the deck: 2 s of it).
	var drift := Vector2(vl.x, vl.z)
	var dp: Vector2 = sc + (to_scope.call(drift * 2.0) - sc).limit_length(sr)
	if drift.length() > 0.3:
		draw_line(sc, dp, WARN if drift.length() > Cosmos.PAD_SPEED else ACCENT, 2.0)
		draw_arc(dp, 4.0, 0, TAU, 12, WARN if drift.length() > Cosmos.PAD_SPEED else ACCENT, 2.0)
	draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -11), sc + Vector2(8, 8), sc + Vector2(0, 4), sc + Vector2(-8, 8)]), Color(1, 1, 1, 0.95))
	_text(Vector2(x0 + 16, y0 + 300), "off %s" % _dist(dist), 18, good if over else ACCENT)
	_text(Vector2(x0 + 16, y0 + 324), "HEADING %s%d°" % ["" if square else "off ", roundi(off_deg)], 18, good if square else WARN)
	# The height tape: the gear over the deck, and the climb / sink rate.
	var tx := x0 + w - 70.0
	var ty := y0 + 64.0
	var th := 208.0
	var hr := 25.0
	for r in [25.0, 60.0, 150.0, 400.0, 600.0]:
		hr = r
		if r >= h * 1.15:
			break
	draw_rect(Rect2(tx, ty, 14, th), Color(ACCENT, 0.12))
	for q in 5:
		draw_line(Vector2(tx - 5, ty + th * q / 4.0), Vector2(tx, ty + th * q / 4.0), Color(ACCENT, 0.5), 1.0)
	var hy := ty + th * (1.0 - clampf(h / hr, 0.0, 1.0))
	draw_rect(Rect2(tx, hy, 14, ty + th - hy), Color(good if h < 6.0 else ACCENT, 0.55))
	draw_colored_polygon(PackedVector2Array([Vector2(tx - 2, hy), Vector2(tx - 12, hy - 6), Vector2(tx - 12, hy + 6)]), ACCENT)
	_text(Vector2(tx - 12, ty - 10), _dist(hr), 16, DIM)
	var vy := vl.y
	var vcol := WARN if absf(vy) > Cosmos.PAD_SPEED else ACCENT
	_text(Vector2(tx - 30, ty + th + 26), _dist(h), 18, ACCENT)
	_text(Vector2(tx - 30, ty + th + 48), "%+.1f m/s" % vy, 16, vcol)
	# The level bubble: inside the ring, level enough to set down.
	var bc := Vector2(x0 + 52, y0 + 372)
	var br := 34.0
	var ul := ship.global_basis.inverse() * pu
	var tol := sqrt(1.0 - 0.85 * 0.85)   # (the tilt that's still level enough)
	draw_arc(bc, br, 0, TAU, 32, Color(ACCENT, 0.45), 1.5)
	draw_arc(bc, br * 0.62, 0, TAU, 28, Color(good if lvl else WARN, 0.8), 1.5)
	var bub := Vector2(ul.x, ul.z) / tol * br * 0.62
	draw_circle(bc + bub.limit_length(br), 6.0, good if lvl else WARN)
	var tilt := rad_to_deg(acos(clampf(ship.global_basis.y.dot(pu), -1.0, 1.0)))
	_text(Vector2(bc.x + br + 14, bc.y - 8), "LEVEL %d°" % roundi(tilt), 18, good if lvl else WARN)
	_text(Vector2(bc.x + br + 14, bc.y + 16), "SPEED %s" % _speed(v.length()), 18, good if slow else WARN)
	# The thrust: the throttle (negative: backward), the thrusters.
	var thr := "THR %+d%%" % roundi(ship.throttle * 100.0) if absf(ship.throttle) > 0.004 else "THR 0%"
	var lift := "LIFT %+d%%" % roundi(ship.lift * 100.0) if absf(ship.lift) > 0.004 else "LIFT 0%"
	var side := "SIDE %+d%%" % roundi(ship.strafe * 100.0) if absf(ship.strafe) > 0.004 else "SIDE 0%"
	_text(Vector2(x0 + 16, y0 + 434), "%s   %s   %s" % [thr, lift, side], 17, ACCENT)
	var why := ""
	if not over:
		why = "Over the square first"
	elif not lvl:
		why = "Level the ship"
	elif not square:
		why = "Turn: the nose to the pad's top"
	elif not slow:
		why = "Slower than %d m/s" % int(Cosmos.PAD_SPEED)
	elif h >= 6.0:
		why = "Down: %s" % Keybinds.keys_text("down")
	else:
		why = "Touching down"
	_text(Vector2(x0 + 16, y0 + 460), why, 17, good if why == "Touching down" else (ACCENT if why.begins_with("Down") else WARN))


## What you can do here (land, dock, take off...): one line above the toolbar.
func _draw_prompt(vs: Vector2, c: Vector2) -> void:
	var hint := ""
	if ship.state == "docking" or cosmos.is_docking():
		hint = "Docking..."
	elif ship.state == "landed" and cosmos.docked:
		hint = "%s: up from the seat    L / Space: undock" % Keybinds.keys_text("stand_up")
	elif ship.state == "landed":
		hint = "%s: up from the seat    L / Space: take off" % Keybinds.keys_text("stand_up")
	elif not cosmos.dock_pad.is_empty() and not cosmos.docked:
		hint = "Set down on pad %d    %s: cancel" % [int(cosmos.dock_pad["id"]), Keybinds.keys_text("land")]
	elif cosmos.station_near() != null:
		hint = "%s: ask %s for a pad" % [Keybinds.keys_text("land"), cosmos.label_of(cosmos.station_near())]
	elif cosmos.planet_below(ship.global_position, 400.0) != null:
		var why: String = cosmos.landing_check()
		hint = "L: land" if why == "" else "Landing: " + why
	if hint == "":
		return
	var hw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_text(Vector2(c.x - hw * 0.5, vs.y - 150.0), hint, 22, ACCENT if hint.contains(": ") and not hint.begins_with("Landing") else WARN)


## On foot: the planet, the way back to the ship, the controls.
var _foot_at := 0
var _foot_term: Array = []


func _draw_foot(vs: Vector2, c: Vector2) -> void:
	var w: Node3D = cosmos.walker
	# (what a click does here, looked up ten times a second: the hand at the crosshair and its word - no
	# panel of where you are and tips: those are the tutorial's)
	var now := Time.get_ticks_msec()
	if now - _foot_at > 100:
		_foot_at = now
		_foot_term = cosmos.terminal_here()
	var d := w.global_position.distance_to(ship.global_position)
	var term: Array = _foot_term
	var inside: bool = ship.interior != null and w.get("deck") == ship.interior
	var act := str(term[0]) if not term.is_empty() else ("Take the controls" if inside and ship.interior.at_seat(ship.interior.to_local(w.global_position)) else "")
	if act != "":
		_grab_hand(vs * 0.5)   # (the left click does something here: the hand at the crosshair)
		var tx := c + Vector2(28, 40)
		if act.begins_with("Locked"):   # (a padlock before it)
			var lk := tx + Vector2(0, -12)
			draw_arc(lk + Vector2(7, -2), 5.0, PI, TAU, 10, WARN, 2.0)
			draw_rect(Rect2(lk + Vector2(0, -2), Vector2(14, 11)), WARN)
			tx.x += 22
		_text(tx, act, 18, WARN if act.begins_with("Locked") else ACCENT)
	# (off the ground and away from it: where it is)
	if not cosmos.ship_away and w.get("deck") == null and not w.on_ground and d > 80.0:
		var sp: Vector3 = ship.global_position
		if cam.is_position_behind(sp):
			_edge_arrow(c, -(cam.unproject_position(sp) - c), vs)
		else:
			var s2 := cam.unproject_position(sp)
			if Rect2(Vector2.ZERO, vs).grow(-20).has_point(s2):
				draw_colored_polygon(PackedVector2Array([s2 + Vector2(0, -11), s2 + Vector2(11, 0), s2 + Vector2(0, 11), s2 + Vector2(-11, 0)]), Color(ACCENT, 0.25))
				draw_polyline(PackedVector2Array([s2 + Vector2(0, -11), s2 + Vector2(11, 0), s2 + Vector2(0, 11), s2 + Vector2(-11, 0), s2 + Vector2(0, -11)]), ACCENT, 2.0)
				_text(s2 + Vector2(16, -6), "Your ship", 17, ACCENT)
				_text(s2 + Vector2(16, 14), _dist(d), 16, ACCENT)
			else:
				_edge_arrow(c, s2 - c, vs)
	_draw_dig(vs, c)
	_draw_build(vs, c)
	_draw_jet(vs, c, w)
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


## On foot: the deposit under the sights (its mineral, what's left), the
## mining beam's heat on its bar, what you've dug.
func _draw_dig(vs: Vector2, c: Vector2) -> void:
	var dep: CosmosDeposits = cosmos.deposits
	if dep and dep.digger:
		draw_arc(c, 15.0, -0.6, 0.6, 8, ACCENT, 2.0)   # (the digger's sights: brackets)
		draw_arc(c, 15.0, PI - 0.6, PI + 0.6, 8, ACCENT, 2.0)
		_text(c + Vector2(-60, -30), "TERRAIN DIGGER", 16, ACCENT)
	if dep == null or (dep.focus.is_empty() and dep.heat <= 0.0):
		return
	var x := c.x + 40.0
	var y := c.y + 40.0
	if not dep.focus.is_empty():
		_text(Vector2(x, y), dep.focus_text(), 18, ACCENT)
	var col := WARN if dep.overheated or dep.heat > 0.8 else ACCENT
	draw_rect(Rect2(x, y + 10, 220, 8), Color(col, 0.2))
	draw_rect(Rect2(x, y + 10, 220 * dep.heat, 8), col)
	_text(Vector2(x, y + 40), "OVERHEATED - cooling" if dep.overheated else "Beam heat %d%%" % roundi(dep.heat * 100.0), 16, col)
	if not dep.got.is_empty():
		var parts := []
		for m in dep.got:
			parts.append("%s %d" % [CosmosDeposits._name(m), int(dep.got[m])])
		_text(Vector2(x, y + 62), "Dug: " + ", ".join(parts.slice(0, 3)), 16, DIM)


## The builder in hand (CosmosBuilds): its piece (its picture, tier, style),
## what it costs or why it won't go there - in the other modes the piece aimed at
## and what taking it down, upgrading or painting it does - and its keys.
func _draw_build(vs: Vector2, c: Vector2) -> void:
	var b: CosmosBuilds = cosmos.get("builds")
	if b == null or not b.tool_out():
		return
	var mode := CosmosBuilds.mode
	var box := Rect2(c.x - 330.0, vs.y - 214.0, 660.0, 92.0)
	draw_rect(box, Color(0, 0, 0, 0.5))
	draw_rect(box, Color(ACCENT, 0.55), false, 1.5)
	var shown: String = CosmosBuilds.piece if mode == "place" or b.aim_pc.is_empty() else str(b.aim_pc["t"])
	BuildKit.draw_icon(self, shown, Rect2(box.position + Vector2(8, 8), Vector2(72, 72)), ACCENT)
	var x := box.position.x + 92.0
	var title := ""
	var line := ""
	var col := ACCENT
	if mode == "place":
		title = "%s  ·  %s" % [BuildKit.title(CosmosBuilds.piece, CosmosBuilds.tier), BuildKit.STYLE_NAMES.get(CosmosBuilds.style, "")]
		var cost := BuildKit.cost(CosmosBuilds.piece, CosmosBuilds.tier)
		var have := []
		for k in cost:
			have.append("%d" % CosmosBuilds.have(k))
		line = "Free building" if BuildKit.free_build else "Costs %s  (you have %s)" % [BuildKit.cost_text(cost), " / ".join(have)]
		if not b.aim_ok:
			line = b.aim_why
			col = WARN
	else:
		title = str(CosmosBuilds.MODE_NAMES[mode]).to_upper()
		if not b.aim_pc.is_empty():
			title += "  ·  " + BuildKit.title(str(b.aim_pc["t"]), int(b.aim_pc.get("m", 1)))
			title += "  ·  %d%% sound" % roundi(100.0 * BuildKit.hp_now(b.aim_pc) / maxf(1.0, BuildKit.hp_of(str(b.aim_pc["t"]), int(b.aim_pc.get("m", 1)))))
		if not b.aim_ok:
			line = b.aim_why
			col = WARN
		else:
			match mode:
				"remove":
					line = "Back: %s" % (BuildKit.cost_text(b.aim_cost) if not b.aim_cost.is_empty() else "nothing")
					if b.aim_falls > 0:
						line += "  -  %d more fall with it" % b.aim_falls
						col = WARN
				"upgrade":
					line = "To %s: %s" % [BuildKit.tier_name(int(b.aim_pc.get("m", 1)) + 1), BuildKit.cost_text(b.aim_cost)]
				"paint":
					line = "Paint it %s" % BuildKit.PAINT_NAMES[CosmosBuilds.paint].to_lower()
	_text(Vector2(x, box.position.y + 26.0), title, 19, ACCENT)
	_text(Vector2(x, box.position.y + 52.0), line, 17, col)
	_text(Vector2(x, box.position.y + 78.0), "N pieces  ·  K turn  ·  O %s  ·  P snap %s  ·  drag: a run" % [
		str(CosmosBuilds.MODE_NAMES[CosmosBuilds.MODES[(CosmosBuilds.MODES.find(mode) + 1) % CosmosBuilds.MODES.size()]]).to_lower(),
		"on" if CosmosBuilds.snap_on else "off"], 15, DIM)


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
	if texts != null:
		texts.append(s)
	_ci.draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
	_ci.draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


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



## The scanner's finds (CosmosSandbox.scan): its pulse going out, then each find
## marked for a minute - deposits gold, towns, caves and dungeons, foes and camps red.
func _draw_scan(vs: Vector2, c: Vector2) -> void:
	var sb: CosmosSandbox = cosmos.sandbox
	if sb == null:
		return
	if sb.scan_pulse > 0.0:
		var k := 1.0 - sb.scan_pulse
		draw_arc(c, k * vs.x * 0.7, 0, TAU, 72, Color(ACCENT, sb.scan_pulse * 0.55), 3.0)
	var area := Rect2(Vector2.ZERO, vs).grow(-20)
	for m in sb.scan_marks:
		var pl: Node3D = m[1]
		if not is_instance_valid(pl):
			continue
		var p: Vector3 = pl.global_position + (m[0] as Vector3)
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		if not area.has_point(s):
			continue
		var col: Color = {"ore": Color(1.0, 0.82, 0.35), "town": ACCENT, "cave": Color(0.72, 0.78, 0.95), "foe": WARN}.get(m[3], DIM)
		var r := 6.0
		draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), col, false, 2.0)
		_text(s + Vector2(10, -6), str(m[2]), 16, col)
		_text(s + Vector2(10, 12), _dist(cam.global_position.distance_to(p)), 15, Color(col, 0.8))



## The grab hand: a palm and four fingers and a thumb, at the crosshair - the left click takes, talks, sits, uses.
func _grab_hand(c: Vector2) -> void:
	var col := ACCENT
	var palm := Rect2(c + Vector2(-9, -2), Vector2(18, 16))
	draw_rect(palm, Color(col, 0.25), true)
	draw_rect(palm, col, false, 2.0)
	for k in 4:
		var x := c.x - 8.0 + k * 5.4
		draw_line(Vector2(x, c.y - 2), Vector2(x, c.y - 13 + absf(k - 1.5) * 2.0), col, 3.0)
	draw_line(c + Vector2(-9, 6), c + Vector2(-16, -1), col, 3.0)


# --- The compass bar and the ship's sights ----------------------------------------------------
#
# The heading (compass_heading / heading_at): degrees clockwise from north, 0-360, of where you
# face projected on the local level:
#  - near a world (within 6 of its radii; on foot always): "up" is away from its centre, north its
#    pole - the world's +Y axis (worlds don't spin; latitude is measured the same way) - laid on the
#    ground's level; east = north x up (so walking east, the longitude grows).
#  - out in space: the system's plane - up is the system's +Y (its plane is XZ, as the maps draw it),
#    north is -Z, east +X.
# Facing: on foot the camera's (where you look), in the ship its nose. No compass inside things -
# ship and station interiors, hangars, the labyrinths below a world - nor docked.
#
# Their fixed lines (the band, the rings, ladders, housings, boxes) are drawn once into two layers of
# their own (redrawn only when the screen's size changes); each redraw draws only what moves.

const SIGHTS_R := 0.15         # (the sights' ring: its radius, a share of the screen's height)
const COMPASS_R := 0.3         # (the compass bar's scale: the same share)
const COMPASS_TOP := 22.0
const MASK_LAYER := 1 << 18    # (render layer 19: the ship's meshes, for the mask)
var _sights_layer: Control     # (the sights' fixed lines)
var _sights_dyn: Control       # (their moving parts, redrawn with the HUD)
var _compass_layer: Control
var _ci: CanvasItem = self     # (what _text draws on: the HUD, or a layer being painted)
var _sights_usec := 0
var _mask_vp: SubViewport      # (the ship alone, drawn to a mask the sights are cut by)
var _mask_cam: Camera3D
var _mask_mat: ShaderMaterial
var _mask_tagged_at := -100000
var _last_hd := 0.0


## A layer of fixed lines: `paint` draws them onto it (called when it's redrawn - its size changed).
class Layer extends Control:
	var paint: Callable
	func _init(p: Callable) -> void:
		paint = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
	func _draw() -> void:
		paint.call(self)


func _layers() -> void:
	_sights_layer = Layer.new(_paint_sights)
	_sights_dyn = Layer.new(_paint_sights_dyn)
	_compass_layer = Layer.new(_paint_compass)
	for l: Control in [_sights_layer, _sights_dyn, _compass_layer]:
		add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.show_behind_parent = true   # (under the markers and texts the HUD draws)
	# The ship over the sights: it's drawn alone (its meshes on MASK_LAYER, a camera that sees only
	# them, at half the screen's size) and where it covers the screen the sights aren't drawn.
	_mask_vp = SubViewport.new()
	_mask_vp.transparent_bg = true
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask_vp.positional_shadow_atlas_size = 0
	_mask_vp.msaa_3d = Viewport.MSAA_DISABLED
	_mask_vp.size = Vector2i(64, 64)
	_mask_cam = Camera3D.new()
	_mask_cam.cull_mask = MASK_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	_mask_cam.environment = env
	_mask_vp.add_child(_mask_cam)
	add_child(_mask_vp)
	_mask_mat = mask_material()
	_mask_mat.set_shader_parameter("ship_mask", _mask_vp.get_texture())
	_sights_layer.material = _mask_mat
	_sights_dyn.material = _mask_mat


## The sights' material: cut where the ship's mask covers the screen (a new one each call).
static func mask_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/hud_ship_mask.gdshader")
	return m


## Each frame the sights show, just before it's drawn: the mask's camera where the game's is, the
## ship's meshes on the mask's layer (looked over every two seconds: its parts come and go).
func _mask_sync() -> void:
	if _mask_vp == null:
		return
	var on := _want_sights and visible and is_instance_valid(cam) and is_instance_valid(ship)
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _mask_vp.render_target_update_mode != mode:
		_mask_vp.render_target_update_mode = mode
	if not on:
		return
	var want := Vector2i(maxi(int(size.x * 0.5), 2), maxi(int(size.y * 0.5), 2))
	if _mask_vp.size != want:
		_mask_vp.size = want
	_mask_cam.global_transform = cam.global_transform
	_mask_cam.fov = cam.fov
	_mask_cam.near = cam.near
	_mask_cam.far = cam.far
	_mask_cam.keep_aspect = cam.keep_aspect
	_mask_cam.h_offset = cam.h_offset
	_mask_cam.v_offset = cam.v_offset
	var now := Time.get_ticks_msec()
	if now - _mask_tagged_at > 2000:
		_mask_tagged_at = now
		_tag_mask(ship)


static func _tag_mask(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers |= MASK_LAYER
	for k in n.get_children():
		if not k is CosmosShipInterior:   # (its insides: not seen from out here)
			_tag_mask(k)


func _show_layer(l: Control, on: bool) -> void:
	if l and l.visible != on:
		l.set_deferred("visible", on)


## The compass's frame at `pos`: [up, north, east] (see above).
func compass_frame(pos: Vector3) -> Array:
	var up := Vector3.UP
	var north := Vector3.FORWARD
	var pl: CosmosPlanet = cosmos.nearest_planet(pos) if cosmos else null
	if pl and pos.distance_to(pl.global_position) < pl.radius * 6.0:
		up = (pos - pl.global_position).normalized()
		north = Vector3.UP
		if absf(up.y) > 0.999:
			north = Vector3.FORWARD   # (right over a pole: every way is south / north)
	north = (north - up * north.dot(up)).normalized()
	return [up, north, north.cross(up)]


## The bearing of `dir` in a compass frame (degrees, 0 north, 90 east), or -1 straight up or down.
static func bearing(frame: Array, dir: Vector3) -> float:
	var up: Vector3 = frame[0]
	var f := dir - up * dir.dot(up)
	if f.length_squared() < 1e-4 * dir.length_squared():
		return -1.0
	return fposmod(rad_to_deg(atan2(f.dot(frame[2]), f.dot(frame[1]))), 360.0)


## The heading at `pos` facing `fwd` (degrees, 0 north, 90 east), in the frame above.
func heading_at(pos: Vector3, fwd: Vector3) -> float:
	var b := bearing(compass_frame(pos), fwd.normalized())
	if b >= 0.0:
		_last_hd = b   # (straight up or down: the last heading)
	return _last_hd


## Where the compass stands: you on foot, else the ship.
func _compass_at() -> Vector3:
	return cosmos.walker.global_position if cosmos.walker else ship.global_position


## The compass's heading now, or -1 when it doesn't show (inside a ship, a hangar, below ground, docked).
func compass_heading() -> float:
	if cosmos == null or cam == null or cosmos.docked or cosmos.dungeon != null:
		return -1.0
	if cosmos.walker:
		if cosmos.walker.get("deck") != null:
			return -1.0
		return heading_at(cosmos.walker.global_position, -cam.global_basis.z)
	return heading_at(ship.global_position, -ship.global_basis.z)


## The nearest world's surface: [planet, metres to its ground (to its sphere when far off)].
func nearest_ground() -> Array:
	var best: CosmosPlanet = null
	var bd := INF
	for pl: CosmosPlanet in cosmos.planets:
		var d := pl.global_position.distance_to(ship.global_position) - pl.radius
		if d < bd:
			bd = d
			best = pl
	if best and bd < best.radius * 0.6:
		bd -= best.ground_at(ship.global_position - best.global_position)
	return [best, bd]


## A stroke with its glow: two wider, fainter ones under it.
static func _glow_arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float) -> void:
	ci.draw_arc(c, r, a0, a1, n, Color(col, col.a * 0.1), w + 9.0)
	ci.draw_arc(c, r, a0, a1, n, Color(col, col.a * 0.25), w + 4.0)
	ci.draw_arc(c, r, a0, a1, n, col, w)


static func _glow_line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, Color(col, col.a * 0.12), w + 6.0)
	ci.draw_line(a, b, col, w)


## A text centred on `at` (its baseline); `bare`: no dark outline (on the glass, half the cost).
func _text_c(at: Vector2, s: String, fs: int, col: Color, bare := false) -> void:
	var p := at - Vector2(_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 0)
	if not bare:
		_text(p, s, fs, col)
		return
	if texts != null:
		texts.append(s)
	_ci.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The compass bar's shape for a screen size: [R, half width, depth, the arch's radius, its centre].
static func _compass_geo(vs: Vector2) -> Array:
	var R := vs.y * COMPASS_R
	var rc := R * 10.0
	return [R, R * 1.08, R * 0.2, rc, Vector2(vs.x * 0.5, COMPASS_TOP + rc)]


## The compass bar's fixed lines: an arched band of glass, its edges, the ends' hooks turned up,
## the notch, the heading's box on the lower edge.
func _paint_compass(l: Control) -> void:
	var g := _compass_geo(l.size)
	var R: float = g[0]
	var th: float = g[2]
	var rc: float = g[3]
	var o: Vector2 = g[4]
	var span := asin(float(g[1]) / rc)
	var a0 := -PI * 0.5 - span
	var a1 := -PI * 0.5 + span
	var rb := rc - th
	l.draw_arc(o, rc - th * 0.5, a0, a1, 32, Color(0.05, 0.02, 0.0, 0.55), th)   # (the glass)
	l.draw_arc(o, rc - th * 0.5, a0, a1, 32, Color(ACCENT, 0.07), th)
	l.draw_arc(o, rc, a0, a1, 32, Color(ACCENT, 0.45), 1.5)
	_glow_arc(l, o, rb, a0, a1, 32, ACCENT, 2.0)
	for sgn: float in [-1.0, 1.0]:
		var e := o + Vector2.from_angle(-PI * 0.5 + span * sgn) * rb
		var p1 := e + Vector2(sgn * R * 0.05, R * 0.02)
		var p2 := p1 + Vector2(sgn * R * 0.04, -R * 0.025)
		var p3 := p2 + Vector2(0, -R * 0.09)
		l.draw_polyline(PackedVector2Array([e, p1, p2, p3]), Color(ACCENT, 0.18), 8.0)
		l.draw_polyline(PackedVector2Array([e, p1, p2, p3]), ACCENT, 2.0)
	var box := _compass_box(l.size)
	var n0 := Vector2(o.x, COMPASS_TOP + th * 0.62)
	_glow_line(l, n0, Vector2(o.x, box.position.y), ACCENT, 1.5)
	l.draw_colored_polygon(PackedVector2Array([n0 + Vector2(-5, 6), n0 + Vector2(5, 6), n0]), ACCENT)
	l.draw_rect(box.grow(3.0), Color(ACCENT, 0.12))
	l.draw_rect(box, Color(0.06, 0.02, 0.0, 0.85))
	l.draw_rect(box, ACCENT, false, 2.0)


static func _compass_box(vs: Vector2) -> Rect2:
	var R := vs.y * COMPASS_R
	var bw := R * 0.26
	var bh := R * 0.1
	return Rect2(vs.x * 0.5 - bw * 0.5, COMPASS_TOP + R * 0.2 - bh * 0.3, bw, bh)


## The compass bar's moving parts: the headings scrolling on it (letters every 45°, ticks every
## 5°, 135° either side), the heading in its box.
func _draw_compass(vs: Vector2, hd: float) -> void:
	var g := _compass_geo(vs)
	var half: float = g[1]
	var th: float = g[2]
	var rc: float = g[3]
	var o: Vector2 = g[4]
	var rb := rc - th
	var ppd := half * 0.94 / 135.0
	var ticks := PackedVector2Array()
	var k := ceili((hd - 135.0) / 5.0) * 5
	while k <= hd + 135.0:
		var dx := (k - hd) * ppd
		var dir := Vector2.from_angle(-PI * 0.5 + dx / rc)
		var m := posmod(k, 360)
		var len := th * (0.32 if m % 45 == 0 else (0.2 if m % 15 == 0 else 0.11))
		ticks.append(o + dir * (rb + 2.0))
		ticks.append(o + dir * (rb + 2.0 + len))
		if m % 45 == 0:
			var lbl: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][m / 45]
			var fade := clampf(1.6 - absf(dx) / half * 1.6, 0.0, 1.0)
			_text_c(o + dir * (rb + th * 0.38), lbl, 20, Color(WARN if m == 0 else ACCENT, fade), true)
		k += 5
	draw_multiline(ticks, Color(ACCENT, 0.8), 1.0)
	_compass_marks(o, rb, th, half, ppd, rc, hd)
	var box := _compass_box(vs)
	_text_c(Vector2(o.x, box.position.y + box.size.y * 0.5 + 8.0), "%03d°" % (roundi(hd) % 360), 22, Color(1.0, 0.85, 0.6), true)


## The sights' fixed lines: the glass band and the rings -
## the outer one bright in places, the thin ones, the dotted one - the tick ladders inside the ring
## left and right, the target box's corners round the diamond in its circle; VEL's housing, its
## value box and label.
func _paint_sights(l: Control) -> void:
	var vs := l.size
	var c := vs * 0.5
	var R := vs.y * SIGHTS_R
	var faint := Color(ACCENT, 0.35)
	var line := Color(ACCENT, 0.7)
	l.draw_arc(c, R * 1.025, 0, TAU, 72, Color(ACCENT, 0.06), R * 0.05)
	l.draw_arc(c, R * 1.05, 0, TAU, 72, faint, 1.0)
	l.draw_arc(c, R, 0, TAU, 72, Color(ACCENT, 0.45), 1.5)
	for seg: Vector2 in [Vector2(-80, -18), Vector2(28, 84), Vector2(96, 152), Vector2(-162, -112)]:
		_glow_arc(l, c, R, deg_to_rad(seg.x), deg_to_rad(seg.y), 16, ACCENT, 3.0)
	l.draw_arc(c, R * 0.9, 0, TAU, 64, faint, 1.0)
	l.draw_arc(c, R * 0.7, 0, TAU, 64, Color(ACCENT, 0.2), 1.0)
	l.draw_arc(c, R * 0.4, 0, TAU, 48, Color(ACCENT, 0.55), 1.0)
	l.draw_arc(c, R * 0.29, 0, TAU, 48, Color(ACCENT, 0.55), 1.0)
	var ladders := PackedVector2Array()
	for side: float in [-1.0, 1.0]:
		var i := 0
		for deg in range(-36, 30, 2):
			var a := deg_to_rad(float(deg))
			var dir := Vector2(cos(a) * side, sin(a))
			ladders.append(c + dir * R * (0.8 if i % 5 == 0 else 0.84))
			ladders.append(c + dir * R * 0.93)
			i += 1
	l.draw_multiline(ladders, line, 1.0)
	var dots := PackedVector2Array()
	for k in 120:
		var a := k * TAU / 120.0
		dots.append(c + Vector2.from_angle(a) * R * 0.78)
		dots.append(c + Vector2.from_angle(a + 0.012) * R * 0.78)
	l.draw_multiline(dots, Color(ACCENT, 0.5), 1.0)
	for sgn: float in [-1.0, 1.0]:
		var p := c + Vector2(0, R * 0.29 * sgn)
		l.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0), p + Vector2(0, 4), p + Vector2(-4, 0)]), ACCENT)
	l.draw_arc(c, R * 0.065, 0, TAU, 24, ACCENT, 1.5)
	var dm := R * 0.032
	l.draw_polyline(PackedVector2Array([c + Vector2(0, -dm), c + Vector2(dm, 0), c + Vector2(0, dm), c + Vector2(-dm, 0), c + Vector2(0, -dm)]), ACCENT, 2.0)
	var bx := R * 0.17
	var arm := R * 0.05
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := c + q * bx
		l.draw_polyline(PackedVector2Array([p - Vector2(q.x * arm, 0), p, p - Vector2(0, q.y * arm)]), Color(ACCENT, 0.8), 1.5)
	_paint_gauge(l, c, R, -1.0)   # (VEL; the crosshair and ALT come and go - drawn folding in and out, _draw_folding)


## A gauge's fixed lines (side -1 left, VEL; 1 right, ALT): its glass housing between two rails,
## the bar's empty track, the value's box pointed outward on the crosshair's line, the label.
func _paint_gauge(l: Control, c: Vector2, R: float, side: float) -> void:
	var g := _gauge_geo(c, R, side)
	var lo: float = minf(g[0], g[1])
	var hi: float = maxf(g[0], g[1])
	var ext := deg_to_rad(5.0)
	l.draw_arc(c, R * 1.13, lo - ext, hi + ext, 20, Color(ACCENT, 0.07), R * 0.17)
	l.draw_arc(c, R * 1.215, lo - ext, hi + ext, 20, Color(ACCENT, 0.55), 1.5)
	l.draw_arc(c, R * 1.045, lo - ext, hi + ext, 20, Color(ACCENT, 0.3), 1.0)
	for h: float in [lo - ext, hi + ext]:
		var d := Vector2.from_angle(h)
		l.draw_line(c + d * R * 1.045, c + d * R * 1.215, Color(ACCENT, 0.55), 1.5)
	l.draw_arc(c, R * 1.13, lo, hi, 20, Color(ACCENT, 0.15), R * 0.055)
	var pts: PackedVector2Array = g[2]
	l.draw_colored_polygon(pts, Color(0.06, 0.02, 0.0, 0.45))
	l.draw_colored_polygon(pts, Color(ACCENT, 0.1))
	l.draw_polyline(pts, Color(ACCENT, 0.8), 1.5)
	var lbl := "VEL" if side < 0.0 else "ALT"
	var foot: Vector2 = g[4]
	var fs := 14
	l.draw_string_outline(_font, foot + Vector2(-_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 14), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
	l.draw_string(_font, foot + Vector2(-_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 14), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ACCENT)


## A gauge's shape: [the bar's foot angle, its top angle, the value box's outline, the box's
## middle, the label's place]. The bar runs from 26° below the level to 27° above, at 1.13 R.
static func _gauge_geo(c: Vector2, R: float, side: float) -> Array:
	var base := PI if side < 0.0 else 0.0
	var dirf := -1.0 if side < 0.0 else 1.0
	var a_lo := base + deg_to_rad(26.0) * dirf
	var a_hi := base - deg_to_rad(27.0) * dirf
	var bh := maxf(R * 0.17, 24.0)
	var x_in := c.x + side * R * 1.23
	var x_out := x_in + side * maxf(R * 0.7, 100.0)
	var y0 := c.y - 1.0
	var pts := PackedVector2Array([Vector2(x_in, y0), Vector2(x_out - side * bh * 0.5, y0), Vector2(x_out, y0 + bh * 0.5), Vector2(x_out - side * bh * 0.5, y0 + bh), Vector2(x_in, y0 + bh), Vector2(x_in, y0)])
	var mid := Vector2((x_in + x_out) * 0.5 - side * bh * 0.15, y0 + bh * 0.5)
	var foot := c + Vector2.from_angle(base + deg_to_rad(36.0) * dirf) * R * 1.22
	return [a_lo, a_hi, pts, mid, foot]


## The sights' moving parts: how far (the target, else the ground the nose points at), the stick,
## VEL - the speed (log scale to the drive's top) - and ALT - the height over the nearest world (how
## far it is when far off; log scale to 100,000 km), its name under the label.
func _paint_sights_dyn(l: Control) -> void:
	if cosmos == null or ship == null or cam == null:
		return
	var t0 := Time.get_ticks_usec()
	var raw: Variant = cosmos.target
	_ci = l
	_draw_sights(l, l.size, l.size * 0.5, raw if is_instance_valid(raw) else null)
	_ci = self
	_sights_usec = Time.get_ticks_usec() - t0


func _draw_sights(l: Control, vs: Vector2, c: Vector2, tgt: Node3D) -> void:
	var R := vs.y * SIGHTS_R
	var far := -1.0
	if tgt:
		far = cam.global_position.distance_to(tgt.global_position) - cosmos.radius_of(tgt)
	else:
		var fwd := -ship.global_basis.z
		var pl: CosmosPlanet = cosmos.nearest_planet(ship.global_position)
		if pl:
			var to := pl.global_position - ship.global_position
			var along := to.dot(fwd)
			var miss := to.length_squared() - along * along
			if along > 0.0 and miss < pl.radius * pl.radius:
				far = along - sqrt(pl.radius * pl.radius - miss)
	if far >= 0.0:
		_text(c + Vector2(R * 0.08, R * 0.2 + 12.0), _dist(far), 16, ACCENT)
	var sp := c + ship.stick * R * 0.9
	if ship.stick.length() > CosmosShip.DEADZONE:
		l.draw_line(c, sp, Color(ACCENT, 0.4), 1.5)
		l.draw_arc(sp, 7.0, 0, TAU, 16, ACCENT, 2.0)
	var spd := ship.speed()
	var kv := clampf(log(1.0 + spd) / log(1.0 + CosmosShip.CRUISE_MAX), 0.0, 1.0)
	_gauge_fill(l, c, R, -1.0, kv, _speed(spd), "", WARN if ship.cruise > 0 else ACCENT)
	_draw_folding(l, c, R)


## The sights' parts that come and go, folding out and in (FOLD_TIME, eased): the crosshair -
## its four lines growing out of the middle (locked on a hostile) - and ALT - its housing opening
## up and down off the crosshair's level, a panel unfolding (near a world's ground).
func _draw_folding(l: Control, c: Vector2, R: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _fold_at) / 1000.0, 0.0, 0.1)
	_fold_at = now
	_cross_k = move_toward(_cross_k, 1.0 if _cross_on else 0.0, dt / FOLD_TIME)
	_alt_k = move_toward(_alt_k, 1.0 if _alt_on else 0.0, dt / FOLD_TIME)
	if _cross_k > 0.0:
		var e := ease(_cross_k, -2.4)
		var line := Color(ACCENT, 0.7 * minf(1.0, _cross_k * 2.0))
		var gap := R * 0.09
		_glow_line(l, Vector2(c.x, c.y - gap), Vector2(c.x, c.y - gap - (R * 1.3 - gap) * e), line, 1.0)
		_glow_line(l, Vector2(c.x, c.y + gap), Vector2(c.x, c.y + gap + (R * 1.3 - gap) * e), line, 1.0)
		_glow_line(l, Vector2(c.x - gap, c.y), Vector2(c.x - gap - (R * 1.02 - gap) * e, c.y), line, 1.0)
		_glow_line(l, Vector2(c.x + gap, c.y), Vector2(c.x + gap + (R * 1.02 - gap) * e, c.y), line, 1.0)
	if _alt_k > 0.0:
		var e := ease(_alt_k, -2.4)
		l.draw_set_transform(Vector2(0.0, c.y * (1.0 - e)), 0.0, Vector2(1.0, maxf(e, 0.02)))   # (squeezed onto the level, opening out)
		_paint_gauge(l, c, R, 1.0)
		if _alt_k > 0.6:
			var ng := nearest_ground()
			var alt := maxf(float(ng[1]), 0.0)
			var ka := clampf(log(1.0 + alt) / log(1.0 + ALT_HIDE), 0.0, 1.0)   # (log scale over the range it's shown in)
			_gauge_fill(l, c, R, 1.0, ka * e, _dist(alt) if ng[0] else "-", str(ng[0].rec.get("name", "")) if ng[0] else "", ACCENT)
		l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A gauge's moving parts: the bar filled from its foot, the value in its box, the world's name.
func _gauge_fill(l: Control, c: Vector2, R: float, side: float, k: float, value: String, sub: String, col: Color) -> void:
	var g := _gauge_geo(c, R, side)
	if k > 0.004:
		var a_lo: float = g[0]
		var a_k: float = a_lo + (float(g[1]) - a_lo) * k
		_glow_arc(l, c, R * 1.13, minf(a_lo, a_k), maxf(a_lo, a_k), 12, col, R * 0.055)
	_text_c(g[3] + Vector2(0, 6.0), value, 18, col, true)
	if sub != "":
		_text_c(g[4] + Vector2(0, 30), sub, 14, DIM)


const COMPASS_MARKS := 40   # (at most, on the bar)
const ORE_GOLD := Color(1.0, 0.82, 0.35)
var _icons: Texture2D           # (CompassIcons' atlas, made with the HUD)


## What's known round you, on the compass bar at its bearing, each its own icon (CompassIcons): the
## markers' things - the star, worlds, moons, gas giants, stations, gates, traders, pirates, monsters,
## lairs, your ship from outside it, towns - and on foot the scanner's finds (ore and veins gold,
## caves, dungeons, camps, creatures) and the package's destination; hostile in red, the target
## ringed, its distance under the bar - past the bar's end, an arrow there.
## Each: [bearing, kind, colour, the target?, metres, its cell in the atlas, its drawn colour].
func compass_marks() -> Array:
	var raw: Variant = cosmos.target
	var tgt: Node3D = raw if is_instance_valid(raw) else null
	var at := _compass_at()
	var fr := compass_frame(at)
	var out := []
	for b: Node3D in cosmos.bodies():
		if out.size() >= COMPASS_MARKS:
			break
		if not _marked(b, tgt):
			continue
		var brg := bearing(fr, b.global_position - at)
		if brg < 0.0:
			continue
		var col := ACCENT
		if (b is CosmosNpcShip and b.hostile) or b is CosmosMonster:
			col = WARN
		out.append([brg, _kind_of(b), col, b == tgt, at.distance_to(b.global_position) - cosmos.radius_of(b)])
	var sb: CosmosSandbox = cosmos.sandbox
	if sb and cosmos.walker:
		for m in sb.scan_marks:
			if out.size() >= COMPASS_MARKS:
				break
			var pl: Node3D = m[1]
			if not is_instance_valid(pl):
				continue
			var p: Vector3 = pl.global_position + (m[0] as Vector3)
			var brg := bearing(fr, p - at)
			if brg < 0.0:
				continue
			var name := str(m[2])
			var kind := "rock"
			var col: Color = DIM
			match str(m[3]):
				"ore":
					kind = "vein" if name.ends_with("m down") else "ore"
					col = ORE_GOLD
				"town":
					kind = "city" if name.ends_with("(city)") else "village"
					col = ACCENT
				"cave":
					kind = "dungeon" if name.ends_with("(dungeon)") else "cave"
					col = Color(0.72, 0.78, 0.95)
				"foe":
					kind = "camp" if name == "Pirate camp" else ("lair" if name == "Bio-signature" else "creature")
					col = WARN
			out.append([brg, kind, col, false, at.distance_to(p)])
	var dest: Variant = package_dest()
	if dest != null and out.size() < COMPASS_MARKS:
		var brg := bearing(fr, (dest as Vector3) - at)
		if brg >= 0.0:
			out.append([brg, "package", ACCENT, false, at.distance_to(dest)])
	for mk: Array in out:   # (its cell and colour: made once, drawn each time)
		mk.append(CompassIcons.cell(CompassIcons.index(mk[1])))
		mk.append(mk[2] if mk[3] else Color(mk[2], 0.8))
	return out


## The icon a body gets on the compass bar.
func _kind_of(b: Node3D) -> String:
	if b is CosmosStar:
		return "star"
	if b is CosmosPlanet:
		if (b as CosmosPlanet).shape.kind == "gas":
			return "gas"
		return "moon" if str(b.rec.get("moon_of", "")) != "" else "planet"
	if b is CosmosStation:
		return "station"
	if b is CosmosGate:
		return "gate"
	if b is CosmosShip:
		return "ship"
	if b is CosmosNpcShip:
		return "pirate" if b.hostile else "trader"
	if b is CosmosMonster:
		return "monster"
	if b is CosmosLair:
		return "lair"
	if b is CosmosTown:
		return "city" if str(b.site.get("kind", "")) == "city" else "village"
	return "rock"


## Where the package you carry goes (a town on another world, a station), or null.
func package_dest() -> Variant:
	var p: Dictionary = CosmosGame.extra.get("package", {}) if CosmosGame.extra is Dictionary else {}
	if p.is_empty():
		return null
	var d: Dictionary = p.get("dest", {})
	if str(d.get("kind", "")) == "station":
		for st: CosmosStation in cosmos.stations:
			if str(st.record.get("id", "")) == str(d.get("id", "")):
				return st.global_position
		return null
	for pl: CosmosPlanet in cosmos.planets:
		if str(pl.rec.get("name", "")) == str(d.get("planet", "")):
			for t in pl.towns:
				if str(t["name"]) == str(d.get("town", "")):
					return pl.global_position + (t["dir"] as Vector3) * (pl.radius + float(t["h"]))
			return pl.global_position
	return null


var _marks: Array = []
var _marks_at := -100000
var _marks_tgt: Variant = null


func _compass_marks(o: Vector2, rb: float, th: float, half: float, ppd: float, rc: float, hd: float) -> void:
	# (the bearings change only as you move: looked up ten times a second, or the target changed)
	var now := Time.get_ticks_msec()
	if now - _marks_at > 100 or not is_same(_marks_tgt, cosmos.target):
		_marks_at = now
		_marks_tgt = cosmos.target
		_marks = compass_marks()
	if _icons == null:
		_icons = CompassIcons.make(self)
	var r := rb + th * 0.78
	var lim := half * 0.94
	var cs := float(CompassIcons.CELL)
	for mk: Array in _marks:
		var dx := wrapf(float(mk[0]) - hd, -180.0, 180.0) * ppd
		var col: Color = mk[6]
		if absf(dx) > lim:
			if not mk[3]:
				continue
			# (the target past the bar's end: an arrow there)
			var e := o + Vector2.from_angle(-PI * 0.5 + signf(dx) * lim / rc) * r
			var sx := signf(dx)
			draw_colored_polygon(PackedVector2Array([e + Vector2(sx * 7, 0), e + Vector2(-sx * 3, -6), e + Vector2(-sx * 3, 6)]), col)
			continue
		var p := o + Vector2.from_angle(-PI * 0.5 + dx / rc) * r
		if mk[3]:
			draw_arc(p, cs * 0.6, 0, TAU, 16, col, 1.5)
			if absf(dx) > half * 0.16:   # (its distance under the bar, clear of the heading's box)
				_text_c(o + Vector2.from_angle(-PI * 0.5 + dx / rc) * (rb - 18.0), _dist(float(mk[4])), 14, col)
		draw_texture_rect_region(_icons, Rect2(p - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), mk[5], col)
