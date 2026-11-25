class_name CosmosTargetView
extends Control
## The target's window (top left, under the ship's gauge): what you've locked on
## (T) seen live - a camera of its own circling it in the same world, lit from
## its star's side - and its card under it: a ship's or a creature's shields and
## hull, speed, weapons; a planet's or a star's kind, size, orbit; a station's
## trade, pads, state. Rendered SHOW_HZ times a second, only while there's a
## target (the main view's frame rate first).

const W := 380.0
const VIEW_H := 210.0
const SHOW_HZ := 30.0
const FOV := 30.0
const FILL := 0.62              # (the target's share of the view's height)
const SPIN := 0.22              # rad/s round it

var cosmos: Node
var _box: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _font: Font
var _for: Node3D = null         # the target the camera's on
var _spin := 0.0
var _due := 0.0
var _card := {}
var _card_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.position = Vector2(0, 40)
	_box.size = Vector2(W, VIEW_H)
	add_child(_box)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(W), int(VIEW_H))
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.positional_shadow_atlas_size = 0   # (no lamps' shadows in it: the star's light only)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.audio_listener_enable_3d = false
	_box.add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_vp.add_child(_cam)
	_cam.current = true
	visible = false
	# (one frame now, under the loading veil: its buffers made, its first draw's cost not paid mid-flight)
	_cam.look_at_from_position(Vector3(0, 0, 50), Vector3.ZERO)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _tgt() -> Node3D:
	var raw: Variant = cosmos.target if cosmos else null
	if raw == null or not is_instance_valid(raw):
		return null
	if not cosmos.hud.visible or cosmos.docked or cosmos.dungeon != null or (cosmos.walker and cosmos.walker.get("deck") != null):
		return null   # (in a hangar, a cave, aboard: no window)
	return raw


func _process(delta: float) -> void:
	var t := _tgt()
	if t == null:
		if visible:
			visible = false
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_for = null
		return
	if t != _for:
		_for = t
		_spin = 0.0
		_due = 0.0
		_card_t = 0.0
	visible = true
	_place()
	_spin += delta * SPIN
	_due -= delta
	if _due <= 0.0:
		_due = 1.0 / SHOW_HZ
		_aim(t)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_card_t -= delta
	if _card_t <= 0.0:
		_card_t = 0.1
		_card = card(t)
		queue_redraw()


## Under the gauge (the 2D HUD's, top left), the guns' line above it.
func _place() -> void:
	var g: Control = cosmos.hud2d.gauge if cosmos.get("hud2d") and cosmos.hud2d.gauge else null
	var gr := g.get_global_rect() if g else Rect2(80, 60, 180, 180)
	position = Vector2(maxf(16.0, gr.position.x - 40.0), gr.end.y + 66.0)


## How big it is (m, from its middle): the camera stands back to fit it.
func _size_of(t: Node3D) -> float:
	if t is CosmosPlanet:
		return maxf(t.radius, t.atmo_radius) * 1.02
	if t is CosmosStar:
		return t.radius * 1.15
	if t is CosmosStation:
		return t.reach * 0.55
	if t is CosmosGate:
		return CosmosGate.RADIUS * 1.2
	if t is CosmosMonster:
		return t.length * 0.45
	if t is CosmosNpcShip:
		return t.reach * 0.55
	if t is CosmosShip:
		return t.reach * 0.5
	if t is CosmosTown:
		return float(t.site["r"]) * 1.1
	if t is CosmosLair:
		return 400.0
	if t.has_meta("rock_radius"):
		return float(t.get_meta("rock_radius")) * 1.2
	return 50.0


## The camera: round the target (its own up for a ship), from the side its
## star lights - a planet seen part day, part night.
func _aim(t: Node3D) -> void:
	var at := t.global_position
	var s := _size_of(t)
	var dist := s / tan(deg_to_rad(FOV * 0.5 * FILL))
	var sun := Vector3.UP
	if cosmos.star and t != cosmos.star:
		sun = (cosmos.star.global_position - at).normalized()
	var up := Vector3.UP
	var dir: Vector3
	if t is CosmosStar:
		dir = Vector3(sin(_spin), 0.7, cos(_spin)).normalized()   # (from above the planets' plane: nothing between)
	elif t is CosmosTown:
		up = (at - t.planet.global_position).normalized()   # (a town from above, its planet's sky behind)
		var side := up.cross(sun)
		if side.length() < 0.01:
			side = up.cross(Vector3.RIGHT)
		dir = (up + side.normalized() * 0.9).normalized().rotated(up, _spin)
	elif t is CosmosGate:
		dir = t.global_basis.orthonormalized() * Vector3(sin(_spin) * 0.6, 0.25, 1.0).normalized()   # (through its ring, a little aside)
	elif t is CosmosPlanet or t is CosmosLair:
		dir = sun.rotated(Vector3.UP, 0.75 + sin(_spin) * 0.35)
		dir = (dir + Vector3.UP * 0.25).normalized()
	else:
		var b := t.global_basis.orthonormalized()
		up = b.y
		var orb := b * Vector3(sin(_spin + 0.8), 0.32, cos(_spin + 0.8)).normalized()
		dir = (orb + sun * 0.45).normalized()
	if absf(dir.dot(up)) > 0.98:
		up = dir.cross(Vector3.RIGHT).normalized()
	var from := at + dir * dist
	_cam.near = clampf((dist - s * 1.6) * 0.5, 0.05, 1000.0)
	_cam.far = dist + s * 4.0 + 2000.0
	_cam.look_at_from_position(from, at, up)


# --- The card ---------------------------------------------------------------

## What it says of `t`: {title, sub, col, bars: [[label, value, max, colour]], rows: [[key, value]]}.
func card(t: Node3D) -> Dictionary:
	var acc := NeonTheme.CYAN
	var warn := Color(1.0, 0.42, 0.3)
	var d: float = cosmos.cam.global_position.distance_to(t.global_position) - cosmos.radius_of(t) if cosmos.cam else 0.0
	var c := {"title": cosmos.label_of(t), "sub": CosmosHud._dist(d), "col": acc, "bars": [], "rows": []}
	var spd: float = cosmos.ship.speed() if cosmos.ship and cosmos.walker == null else 0.0
	if spd > 5.0:
		c["sub"] += "  -  %s away" % CosmosHud._time(d / spd)
	var rows: Array = c["rows"]
	var shield := Color(0.6, 0.9, 1.0)
	var hull := Color(1.0, 0.65, 0.3)
	if t is CosmosNpcShip:
		var empire := Galaxy.empire_name(t.faction) if t.kind != "pirate" else "Pirates"
		c["col"] = warn if t.hostile else acc
		c["bars"] = [["SHIELDS", t.shield, t.max_shield, shield], ["HULL", t.hull, t.max_hull, hull]]
		rows.append(["Class", "%s - %d m" % [str(t.hull_kind).capitalize(), roundi(t.reach * 2.0)]])
		rows.append(["Flag", empire])
		rows.append(["Stance", ("Fleeing" if t.kind == "trader" else "Hostile") if t.hostile else "Neutral"])
		rows.append(["Speed", "%s  (top %s)" % [CosmosHud._speed(t.velocity.length()), CosmosHud._speed(t.speed_max)]])
		rows.append(["Weapons", "Unarmed" if t.kind == "trader" else "Laser cannon - %d dmg, %.1f/s" % [roundi(CosmosNpcShip.LASER_DAMAGE), 1.0 / CosmosNpcShip.LASER_EVERY]])
		var r: Dictionary = Galaxy.traders.get(str(t.rec_id), {}) if t.rec_id != "" else {}
		if not r.is_empty():   # (one of the economy's ships: its name, its captain and crew, its route)
			var crew: Array = People.crew_of(str(r["id"]))
			rows.append(["Ship", "The %s" % r["name"]])
			if not crew.is_empty():
				rows.append(["Captain", "%s  (+%d crew)" % [People.full_name(People.person(crew[0])), crew.size() - 1]])
			var dest: Dictionary = Galaxy.stations.get(str(r.get("dest", "")), {})
			if r["state"] == "docked":
				rows.append(["Docked", str(Galaxy.stations.get(str(r["station"]), {}).get("name", "?"))])
			elif not dest.is_empty():
				rows.append(["Bound for", "%s (%s)" % [dest["name"], Galaxy.system(str(dest["system"])).get("name", "?")]])
		elif t.kind == "trader" and is_instance_valid(t.dest):
			rows.append(["Bound for", cosmos.label_of(t.dest)])
	elif t is CosmosMonster:
		c["col"] = warn
		c["bars"] = [["SHIELDS", t.shield, t.max_shield, shield], ["HIDE", t.hull, t.max_hull, hull]] if t.max_shield > 0.0 else [["HIDE", t.hull, t.max_hull, hull]]
		rows.append(["Kind", "Space creature - %d m long" % roundi(t.length)])
		rows.append(["Threat", "Level x%.1f" % t.mult])
		rows.append(["Speed", CosmosHud._speed(t.velocity.length())])
		rows.append(["Attacks", "Orbs %d dmg, ram %d" % [roundi(t.damage), roundi(t.damage * 3.0)]])
	elif t is CosmosShip:
		c["bars"] = [["SHIELDS", t.shield, t.max_shield, shield], ["HULL", t.hull, t.max_hull, hull]]
		rows.append(["State", {"landed": "Landed", "fly": "In flight"}.get(t.state, str(t.state).capitalize())])
		var names: Array = []
		for g in t.guns:
			names.append(g["name"])
		rows.append(["Weapons", ", ".join(names) if not names.is_empty() else "None"])
	elif t is CosmosPlanet:
		var type := str(t.rec.get("type", ""))
		var info: Dictionary = Planets.TYPES.get(type, {})
		rows.append(["Type", str(info.get("label", type.capitalize())).capitalize()])
		rows.append(["Radius", "%s  (%s across)" % [CosmosHud._dist(t.radius), CosmosHud._dist(t.radius * 2.0)]])
		var moon_of := str(t.rec.get("moon_of", ""))
		var orbit := float(t.rec.get("orbit", 0.0))
		if orbit > 0.0:
			var period := (240.0 if moon_of != "" else 900.0 * pow(orbit / 3000.0, 1.5)) * Cosmos.ORBIT_SLOWDOWN
			var round_what := "the star"
			if moon_of != "":
				var parent: Dictionary = Galaxy.planet_record(moon_of)
				round_what = str(parent.get("name", Planets.PLANETS.get(moon_of, {}).get("name", "its planet")))
			rows.append(["Orbit", "%s round %s" % [CosmosHud._dist(orbit * PlanetShape.PX_TO_M), round_what]])
			rows.append(["Year", CosmosHud._time(period)])
		var moons := 0
		for p in cosmos.planets:
			if str(p.rec.get("moon_of", "")) == str(t.rec.get("id", "-")):
				moons += 1
		if moon_of == "":
			rows.append(["Moons", str(moons) if moons > 0 else "None"])
		var sh: PlanetShape = t.shape
		if sh.kind == "gas":
			rows.append(["Surface", "None - clouds all the way down"])
		else:
			rows.append(["Surface", ["Dry ground", "Seas", "Ice sheets", "Lava seas"][clampi(sh.sea, 0, 3)] + ", relief %s" % CosmosHud._dist(sh.amp * 3.0)])
		rows.append(["Air", "Atmosphere" if t.atmo_radius > t.radius else "None"])
		if not t.towns.is_empty():
			rows.append(["Towns", str(t.towns.size())])
	elif t is CosmosStar:
		var sys: Dictionary = Galaxy.system(cosmos.system_id)
		var kind: Dictionary = Galaxy.STARS.get(str(sys.get("star", "yellow")), Galaxy.STARS["yellow"])
		rows.append(["Type", str(kind["name"])])
		rows.append(["Radius", "%s  (%s across)" % [CosmosHud._dist(t.radius), CosmosHud._dist(t.radius * 2.0)]])
		rows.append(["Planets", str(cosmos.planets.filter(func(p): return str(p.rec.get("moon_of", "")) == "").size())])
		rows.append(["Heat", "Burns shields within %s" % CosmosHud._dist(t.radius * (Cosmos.HEAT_FROM - 1.0))])
		rows.append(["Rule", Galaxy.empire_name(str(sys.get("owner", "")))])
	elif t is CosmosStation:
		var r: Dictionary = t.record
		var econ: Dictionary = Galaxy.ECONOMIES.get(str(r.get("economy", "")), {})
		c["bars"] = [["STATE", float(r.get("health", 100.0)), 100.0, hull]]
		rows.append(["Kind", str(econ.get("name", "Station"))])
		rows.append(["Flag", Galaxy.empire_name(str(r.get("empire", "")))])
		rows.append(["Sells", _goods(econ.get("produce", {}))])
		rows.append(["Buys", _goods(econ.get("consume", {}))])
		var free := 0
		for p in t.pads:
			if p.get("owner") == null or not is_instance_valid(p.get("owner")):
				free += 1
		rows.append(["Pads", "%d of %d free" % [free, t.pads.size()]])
	elif t is CosmosGate:
		var sys: Dictionary = Galaxy.system(t.to)
		rows.append(["Leads to", "%s system" % str(sys.get("name", t.to))])
		rows.append(["Rule", Galaxy.empire_name(str(sys.get("owner", "")))])
		rows.append(["Star", str(Galaxy.STARS.get(str(sys.get("star", "yellow")), {}).get("name", ""))])
		rows.append(["Ring", "%s across" % CosmosHud._dist(CosmosGate.RADIUS * 2.0)])
	elif t is CosmosTown:
		rows.append(["Kind", "City" if str(t.site["kind"]) == "city" else "Village"])
		if is_instance_valid(t.planet):
			rows.append(["On", cosmos.label_of(t.planet)])
		rows.append(["Size", "%s across" % CosmosHud._dist(float(t.site["r"]) * 2.0)])
	elif t is CosmosLair:
		c["col"] = warn
		rows.append(["Signal", str(SignalSites.level_info(t.sig).get("name", ""))])
		rows.append(["Reading", "A living thing - large"])
	elif t.has_meta("rock_radius"):
		var st: Dictionary = cosmos.mining.rock_state() if cosmos.mining else {}
		rows.append(["Kind", "Asteroid - %s" % (cosmos.mining.field.kind.capitalize() if cosmos.mining and cosmos.mining.field else "rock")])
		rows.append(["Radius", CosmosHud._dist(float(t.get_meta("rock_radius")))])
		if not st.is_empty():
			rows.append(["Holds", cosmos.mining.comp_text() if st["scanned"] else "Not scanned"])
			c["bars"] = [["ORE", float(st["ore_left"]), float(maxi(int(st["ore_total"]), 1)), hull]]
	return c


func _goods(m: Dictionary) -> String:
	var ks: Array = m.keys()
	ks.sort_custom(func(a, b): return m[a] > m[b])
	var out: Array = []
	for k in ks.slice(0, 3):
		out.append(str(Items.ITEMS.get(k, {}).get("name", str(k).capitalize())))
	return ", ".join(out) if not out.is_empty() else "-"


func _draw() -> void:
	if _card.is_empty():
		return
	var col: Color = _card["col"]
	var rows: Array = _card["rows"]
	var bars: Array = _card["bars"]
	var h := 40.0 + VIEW_H + 12.0 + bars.size() * 20.0 + rows.size() * 22.0 + 6.0
	draw_style_box(NeonTheme.box(Color(col, 0.8), Color(NeonTheme.BG, 0.72), 2, 6), Rect2(-8, -6, W + 16, h + 6))
	_text(Vector2(0, 18), str(_card["title"]), 20, col)
	_text(Vector2(0, 34), str(_card["sub"]), 15, Color(NeonTheme.TEXT_DIM, 0.95))
	draw_rect(Rect2(-1, 39, W + 2, VIEW_H + 2), Color(col, 0.5), false, 1.0)
	# (corner ticks on the view: a sight)
	var vr := Rect2(0, 40, W, VIEW_H)
	var k := 14.0
	for cn in [vr.position, Vector2(vr.end.x, vr.position.y), vr.end, Vector2(vr.position.x, vr.end.y)]:
		var sx := 1.0 if cn.x < vr.get_center().x else -1.0
		var sy := 1.0 if cn.y < vr.get_center().y else -1.0
		draw_line(cn, cn + Vector2(k * sx, 0), col, 2.0)
		draw_line(cn, cn + Vector2(0, k * sy), col, 2.0)
	var y := 40.0 + VIEW_H + 16.0
	for b in bars:
		var bc: Color = b[3]
		var frac := clampf(float(b[1]) / maxf(float(b[2]), 0.001), 0.0, 1.0)
		_text(Vector2(0, y + 5), str(b[0]), 14, Color(NeonTheme.TEXT_DIM, 0.95))
		draw_rect(Rect2(80, y - 4, W - 150, 8), Color(bc, 0.25))
		draw_rect(Rect2(80, y - 4, (W - 150) * frac, 8), bc)
		_text(Vector2(W - 62, y + 5), "%d/%d" % [roundi(float(b[1])), roundi(float(b[2]))], 14, bc)
		y += 20.0
	y += 4.0
	for r in rows:
		_text(Vector2(0, y + 6), str(r[0]), 16, Color(NeonTheme.TEXT_DIM, 0.95))
		_text(Vector2(92, y + 6), str(r[1]), 16, NeonTheme.TEXT)
		y += 22.0


func _text(at: Vector2, s: String, fs: int, c: Color) -> void:
	var w := W - at.x
	draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, w, fs, 4, Color(0, 0, 0, 0.7))
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, w, fs, c)
