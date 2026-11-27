extends VBoxContainer
## The Automaton's MAP > SOLAR SYSTEM: the solar map - the system you're in, in 3D (Map3DView):
## its star, planets and moons on their orbits, stations, jump gates,
## asteroid fields, bio-signatures, the ships your sensors see and you, over
## the system's plane (a polar grid, 10 km a ring). Drag to turn it, right /
## middle drag to pan, the wheel zooms; click something for its details
## (the panel beside it) and SET COURSE: it becomes your target - the
## Hyperion drive (J) takes you there, the HUD points the way. Double click:
## the view flies to it. The list under the panel names everything known
## here (click a line to pick it).
## Fog of war (Galaxy.fog): what your sensors have swept (Galaxy.SENSOR_RANGE
## round your ship, kept system by system - CosmosMapMirror reveals it as you
## fly) shows; the rest of the plane is a dark haze and what's in it is
## hidden until you get near (a system charted from its beacon: all of it).
## The star, you and your target always show; ships only within sensor range.
## TRADE (the button, or T): the best trade runs from this system's stations -
## to another station here, or to the gate toward one up to two jumps away.
## Works in the 3D game (the Cosmos scene: live positions) and anywhere else
## from the galaxy's data (the orbits worked out as Cosmos does).

var data: Node
var ship: Node2D
var world: Node                  # (the 3D game - Cosmos - when it says so; else the current scene)

var trade := false
var _view: SolarView
var _info: RichTextLabel
var _list: RichTextLabel
var _course: Button
var _look: Button
var _clear: Button
var _globe: Button
var _trade_btn: Button
var _list_sig := ""


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var title := UI.label("SOLAR MAP", 18, NeonTheme.HEAD)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_legend(MapIcons.ORANGE, "You / course"))
	top.add_child(_legend(MapIcons.CYAN, "Station / gate"))
	top.add_child(_legend(MapIcons.RED, "Hostile"))
	top.add_child(_legend(Color(0.5, 1.0, 0.75), "Neutral"))
	top.add_child(_legend(Color(0.85, 0.65, 0.4), "Asteroids"))
	_trade_btn = EditorIcons.dress(UI.button("TRADE", toggle_trade, 14), "buy", EditorIcons.tip("Trade routes", "T", "Green arrows for the best trade runs from this system's stations: to another station here, or out through a gate to a station up to two jumps away.\nEach shows the good to carry and the profit a unit."))
	_trade_btn.toggle_mode = true
	_trade_btn.focus_mode = FOCUS_NONE
	top.add_child(_trade_btn)
	var fit := EditorIcons.dress(UI.button("", func(): _view.fit(), 14), "fit_all", EditorIcons.tip("Whole system", "Home  ·  middle click", "Turns and zooms the map to show everything you know of this system."))
	fit.focus_mode = FOCUS_NONE
	top.add_child(fit)
	var ctr := EditorIcons.dress(UI.button("", func(): _view.centre_on_ship(), 14), "ship", EditorIcons.tip("Find your ship", "", "Flies the view to your ship."))
	ctr.focus_mode = FOCUS_NONE
	top.add_child(ctr)
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(row)
	_view = SolarView.new()
	_view.page = self
	_view.custom_minimum_size = Vector2(880, 590)
	_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_view.size_flags_vertical = SIZE_EXPAND_FILL
	_view.selected.connect(func(_k): _update_info())
	row.add_child(_view)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(370, 0)
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	col.add_child(UI.section("SELECTED"))
	_info = _rich(250)
	col.add_child(_info)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	_course = EditorIcons.dress(UI.button("Set course", plot, 15), "next", EditorIcons.tip("Set course", "Enter  ·  Space  ·  A",
		"Makes it your target: the HUD points the way and the Hyperion drive (J) takes you there."))
	_course.size_flags_horizontal = SIZE_EXPAND_FILL
	_look = EditorIcons.dress(UI.button("", func(): _view.look_at_selected(), 15), "eye", EditorIcons.tip("Look at it", "double click", "Flies the view to it."))
	_clear = EditorIcons.dress(UI.button("", clear_course, 15), "abandon", EditorIcons.tip("Clear course", "", "Drops your target: no course."))
	_globe = EditorIcons.dress(UI.button("", show_planet_map, 15), "planets", EditorIcons.tip("Planet map", "", "The world on its own map: a globe of what you've explored of it, its towns and their plans."))
	for b in [_course, _look, _globe, _clear]:
		b.focus_mode = FOCUS_NONE
		btns.add_child(b)
	col.add_child(btns)
	col.add_child(UI.section("KNOWN IN THIS SYSTEM"))
	_list = _rich(200)
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.meta_clicked.connect(func(m):
		_view.select(str(m))
		_view.look_at_selected())
	col.add_child(_list)


func _legend(c: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var dot := ColorRect.new()
	dot.color = c
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UI.label(text, 14, UI.TEXT_DIM))
	return h


func _rich(h: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.custom_minimum_size = Vector2(0, h)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	return r


func refresh() -> void:
	_view.rebuild()
	_update_info()


## Opened (MapsPage.show_sub): centred on where you are.
func focus_you(_keep := false) -> void:
	_view.focus_you()
	_update_info()


func toggle_trade() -> void:
	trade = not trade
	_trade_btn.set_pressed_no_signal(trade)
	_view.routes = []
	_view.trade_t = 0.0
	_view.mark_dirty()


## The 3D game (Cosmos) when that's where the map is open, else null.
func cosmos() -> Node:
	var c: Node = world if is_instance_valid(world) else (get_tree().current_scene if is_inside_tree() else null)
	return c if c != null and c.has_method("bodies") and c.get("built") == true else null


## The selected world on the planet map (MAP > PLANET).
func show_planet_map() -> void:
	var o: Dictionary = _view.objs.get(_view.selected_key, {})
	if o.get("kind", "") != "planet" or not is_instance_valid(o.get("node")):
		return
	var p := get_parent()
	while p != null and not p.has_method("show_planet"):
		p = p.get_parent()
	if p:
		p.show_planet(o["node"])


## The selection made your target (SET COURSE, Enter).
func plot() -> void:
	var o: Dictionary = _view.objs.get(_view.selected_key, {})
	var c := cosmos()
	if o.is_empty() or c == null or not is_instance_valid(o.get("node")) or o["kind"] == "you":
		return
	c.target = o["node"]
	GameLog.post("Course set for %s (%s)." % [o["name"], SolarView.km(_view.dist_to(o))], "info")
	_view.mark_dirty()
	_update_info()


func clear_course() -> void:
	var c := cosmos()
	if c and c.target != null:
		c.target = null
		GameLog.post("Course cleared.", "info")
	_view.mark_dirty()
	_update_info()


## The selection's details, and the list of what's known here.
func _update_info() -> void:
	var o: Dictionary = _view.objs.get(_view.selected_key, {})
	var c := cosmos()
	var tgt: Node = c.target if c else null
	_clear.disabled = tgt == null
	if o.is_empty():
		var txt := "[color=#%s]Nothing selected.[/color]" % UI.TEXT_DIM.to_html(false)
		if txt != _info.text:
			_info.text = txt
		_course.disabled = true
		_look.disabled = true
		_globe.disabled = true
	else:
		var txt: String = _view.describe(o)
		if txt != _info.text:
			_info.text = txt
		var is_target: bool = tgt != null and is_instance_valid(o.get("node")) and o["node"] == tgt
		_course.disabled = c == null or not is_instance_valid(o.get("node")) or o["kind"] in ["you", "marker"] or is_target
		_course.text = "On course" if is_target else "Set course"
		_look.disabled = false
		_globe.disabled = o["kind"] != "planet" or not is_instance_valid(o.get("node"))
	var sig := str(_view.order)
	if sig != _list_sig:
		_list_sig = sig
		var lines := []
		for k in _view.order:
			var q: Dictionary = _view.objs[k]
			lines.append("[url=%s][color=#%s]%s[/color][/url]  [color=#%s]%s[/color]" % [k, (q["color"] as Color).lightened(0.3).to_html(false), q["name"],
				UI.TEXT_DIM.to_html(false), SolarView.km(_view.dist_to(q))])
		_list.text = "\n".join(lines)


## The solar map's view: the system in 3D, a kilometre a unit.
class SolarView extends Map3DView:
	const KM := 1000.0
	const ASTEROID := Color(0.85, 0.65, 0.4)
	const NEUTRAL := Color(0.5, 1.0, 0.75)
	var page: Node
	## What's shown: key -> {kind, name, pos (km), color, node (the 3D game's), r (km), ...}.
	var objs := {}
	var order: Array = []          # (the keys, nearest you first - the list, cycling)
	var routes: Array = []         # the trade runs shown
	var trade_t := 0.0
	var _bodies := {}              # key -> MeshInstance3D (a world, its moons' orbits under it)
	var _orbits: MeshInstance3D    # the planets' orbits (still)
	var _orbit_sig := ""
	var _lines: MeshInstance3D     # your course (made again each frame: one segment)
	var _stems: MultiMeshInstance3D # what's over the plane: a stem down to it and a circle at its foot - one line mesh each, moved
	var _sensor: MeshInstance3D    # your sensors' reach (a circle, moved and sized)
	var _glow: MultiMeshInstance3D # the star's light
	var _rings: MultiMeshInstance3D # the markers' rings (drawn by the GPU: the overlay only adds glyphs and names)
	var _plane: MeshInstance3D
	var _fields := {}              # key -> MeshInstance3D (its rocks, points)
	var _system := ""
	var _looks := {}               # planet id -> its look (away from the 3D game: made once)
	var _fitted := false
	var _t := 0.0
	var _rebuild_t := 0.0

	func _init() -> void:
		super()
		min_dist = 0.5
		max_dist = 3000.0
		# (what moves - the worlds on their orbits, you, the ships - placed
		# again each frame the screen shows: fluid, not a step four times a second)
		anim_hz = frame_hz()
		overlay_hz = 1000.0   # (the overlay with every picture)
		_plane = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * 2.0
		_plane.mesh = pm
		_plane.material_override = MapKit.plane_material()
		_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_plane)
		_orbits = MeshInstance3D.new()
		_orbits.material_override = MapKit.line_material()
		world.add_child(_orbits)
		_lines = MeshInstance3D.new()
		_lines.material_override = MapKit.line_material()
		world.add_child(_lines)
		# (the stems and their feet, your sensors' ring: line meshes made once and
		# placed by their transforms each frame - building them anew each frame
		# was 1.5 ms)
		var stem := MapKit.Lines.new()
		stem.seg(Vector3.ZERO, Vector3.DOWN, Color.WHITE, 1.2, 0.0, 0.0, Color(1, 1, 1, 0.21))
		var foot := MapKit.Lines.new()
		foot.circle(Vector3.ZERO, 1.0, Color.WHITE, 1.2, 16)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = stem.mesh()
		_stems = MultiMeshInstance3D.new()
		_stems.multimesh = mm
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.mesh = foot.mesh()
		var feet := MultiMeshInstance3D.new()
		feet.multimesh = mm2
		for x: GeometryInstance3D in [_stems, feet]:
			x.material_override = MapKit.line_material()
			x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			x.extra_cull_margin = 16384.0   # (widened in the shader)
			world.add_child(x)
		_stems.set_meta("feet", feet)
		var ring := MapKit.Lines.new()
		ring.circle(Vector3.ZERO, 1.0, Color(MapIcons.ORANGE, 0.25), 1.2, 96)
		_sensor = ring.into(null)
		world.add_child(_sensor)
		_glow = MapKit.glows(1)
		world.add_child(_glow)
		_rings = MapKit.glows(64)
		world.add_child(_rings)

	func cosmos() -> Node:
		return page.cosmos() if is_instance_valid(page) else null

	static func km(d: float) -> String:
		if d < 10.0:
			return "%.1f km" % d
		return "%s km" % _thousands(int(round(d)))

	static func _thousands(n: int) -> String:
		var s := str(n)
		var out := ""
		while s.length() > 3:
			out = "," + s.right(3) + out
			s = s.left(s.length() - 3)
		return s + out

	func you() -> Vector3:
		return objs.get("you", {}).get("pos", Vector3.ZERO)

	func dist_to(o: Dictionary) -> float:
		return you().distance_to(o["pos"])

	# --- What's there ------------------------------------------------------------

	## Gathers what's known (the 3D game's nodes, or the galaxy's data) and
	## sets the 3D parts to match.
	func rebuild() -> void:
		var sid := Galaxy.current_system
		if sid != _system:
			_system = sid
			_fitted = false
			_looks = {}
			for k in _bodies:
				(_bodies[k] as Node).queue_free()
			_bodies = {}
			for k in _fields:
				(_fields[k] as Node).queue_free()
			_fields = {}
			_orbit_sig = ""
		var c := cosmos()
		objs = {}
		if c:
			_gather_live(c)
		else:
			_gather_data(sid)
		var here := you()
		order = objs.keys().filter(func(k): return k != "you")
		order.sort_custom(func(a, b): return here.distance_squared_to(objs[a]["pos"]) < here.distance_squared_to(objs[b]["pos"]))
		order.push_front("you")
		marks = {}
		for k in objs:
			marks[k] = {"pos": objs[k]["pos"], "r": 16.0}
		if selected_key != "" and not objs.has(selected_key):
			selected_key = ""
		_sync_3d()
		if not _fitted and size.x > 10.0:
			_fitted = true
			fit(true)
		mark_dirty()

	## Known (out of the fog), at a place in the system (km)?
	func _seen_at(p: Vector3) -> bool:
		return Galaxy.charted.has(Galaxy.current_system) or Galaxy.explored_at(Vector2(p.x, p.z) * KM / PlanetShape.PX_TO_M)

	func _put(key: String, d: Dictionary) -> void:
		objs[key] = d

	func _gather_live(c: Node) -> void:
		var o: Vector3 = c.origin
		var tgt: Node = c.target
		var sys: Dictionary = Galaxy.system(Galaxy.current_system)
		var me: Node3D = c.walker if c.walker else c.ship   # (on foot: you, not your ship)
		if me:
			_put("you", {"kind": "you", "name": "You" if c.walker else "Your ship", "pos": (me.global_position + o) / KM, "node": me, "color": MapIcons.ORANGE})
		var here: Node = c.life_planet() if c.has_method("life_planet") else null
		var at := you()
		if c.star:
			_put("star", {"kind": "star", "name": str(sys.get("name", "Star")), "pos": (c.star.global_position + o) / KM, "node": c.star,
				"r": c.star.radius / KM, "color": c.star.color})
		for p in c.planets:
			var pos: Vector3 = (p.global_position + o) / KM
			var rec: Dictionary = p.rec
			if not (p == here or p == tgt or Galaxy.knows_planet(str(rec.get("id", p.name))) or _seen_at(pos)):
				continue   # (the world you're on, or near, always - and any you've seen: it's known wherever its orbit's taken it)
			_put("planet:" + str(rec.get("id", p.name)), {"kind": "planet", "name": str(rec.get("name", "?")), "pos": pos, "node": p, "rec": rec,
				"r": p.radius / KM, "look": p.shape.look, "towns": p.towns.size(), "color": _planet_col(p.shape.look)})
		for s in c.stations:
			var pos: Vector3 = (s.global_position + o) / KM
			var sid := str(s.record.get("id", ""))
			if not (_seen_at(pos) or Galaxy.knows_station(sid) or s == tgt):
				continue
			var e := str(s.record.get("empire", Galaxy.owner_of(Galaxy.current_system)))
			_put("station:" + sid, {"kind": "station", "name": str(s.record.get("name", "Station")), "pos": pos, "node": s, "rec": s.record,
				"empire": e, "color": _station_col(e)})
		for g in c.gates:
			var pos: Vector3 = (g.global_position + o) / KM
			if not (_seen_at(pos) or Galaxy.has_been(g.to) or g == tgt):
				continue
			_put("gate:" + str(g.to), {"kind": "gate", "name": "Gate to %s" % Galaxy.system(g.to).get("name", g.to), "pos": pos, "node": g,
				"to": str(g.to), "color": MapIcons.CYAN})
		for i in c.fields.size():
			var f: Node3D = c.fields[i]
			var pos: Vector3 = (f.global_position + o) / KM
			if not _seen_at(pos):
				continue
			_put("field:%d" % i, {"kind": "field", "name": "Asteroid field", "pos": pos, "node": f, "ore": str(f.get("kind")),
				"rocks": (f.get("rocks") as Array).filter(func(r): return float(r[1]) > 0.0).size(), "color": ASTEROID})
		var sensor := Galaxy.SENSOR_RANGE * PlanetShape.PX_TO_M / KM
		for lr in c.lairs:
			if not is_instance_valid(lr) or is_instance_valid(lr.monster):
				continue
			var pos: Vector3 = (lr.global_position + o) / KM
			if not (_seen_at(pos) or pos.distance_to(at) < sensor or lr == tgt):
				continue
			_put("lair:%d" % lr.get_instance_id(), {"kind": "lair", "name": lr.title(), "pos": pos, "node": lr, "color": MapIcons.RED})
		for x in c.npc_ships:
			if not is_instance_valid(x) or x.dead:
				continue
			var pos: Vector3 = (x.global_position + o) / KM
			if pos.distance_to(at) > sensor and x != tgt:
				continue   # (ships: only those your sensors see now)
			var col := MapIcons.RED if x.hostile or x.kind == "pirate" else NEUTRAL
			_put("ship:%d" % x.get_instance_id(), {"kind": "ship", "name": x.label if x.label != "" else x.kind.capitalize(), "pos": pos, "node": x,
				"color": col, "hostile": x.hostile or x.kind == "pirate"})
		for m in c.monsters:
			if is_instance_valid(m) and not m.dead:
				var pos: Vector3 = (m.global_position + o) / KM
				if pos.distance_to(at) < sensor or m == tgt:
					_put("monster:%d" % m.get_instance_id(), {"kind": "monster", "name": str(m.label), "pos": pos, "node": m, "color": MapIcons.RED, "hostile": true})
		_gather_markers()

	## Away from the 3D game (Talos, a test): the galaxy's records, the orbits
	## worked out as Cosmos does (Cosmos._orbit_pos, _map3).
	func _gather_data(sid: String) -> void:
		var sys: Dictionary = Galaxy.system(sid)
		if sys.is_empty():
			return
		var t: Dictionary = Galaxy.STARS.get(str(sys.get("star", "yellow")), Galaxy.STARS["yellow"])
		_put("star", {"kind": "star", "name": str(sys.get("name", "Star")), "pos": Vector3.ZERO, "r": float(t["radius"]) * 9.0 / KM,
			"color": t["color"]})
		var C: GDScript = load("res://scripts/world/space/cosmos.gd")
		var recs: Array = C.planet_records(sid)
		var places: Dictionary = C.system_places(sid, Galaxy.time)   # (as the game puts them: the same orbits, the same clock)
		for r in recs:
			var pos: Vector3 = places.get("planet:" + str(r["id"]), Vector3.ZERO) / KM
			if not (_seen_at(pos) or Galaxy.knows_planet(str(r["id"]))):
				continue
			var look: Dictionary = _looks.get(str(r["id"]), {})
			if look.is_empty():
				look = PlanetGen.generate(str(r.get("template", "barren")), int(r.get("variant", 0)))
				_looks[str(r["id"])] = look
			_put("planet:" + str(r["id"]), {"kind": "planet", "name": str(r.get("name", "?")), "pos": pos, "rec": r,
				"r": float(r.get("size", 500.0)) * PlanetShape.SIZE_TO_R / KM, "look": look, "color": _planet_col(look)})
		for stid in sys.get("stations", []):
			var st: Dictionary = Galaxy.stations.get(stid, {})
			if st.is_empty():
				continue
			var pos: Vector3 = places.get("station:" + str(stid), _map3(st["pos"], hash(stid))) / KM
			if not (_seen_at(pos) or Galaxy.knows_station(str(stid))):
				continue
			var e := str(st.get("empire", sys["owner"]))
			_put("station:" + str(stid), {"kind": "station", "name": str(st["name"]), "pos": pos, "rec": st, "empire": e, "color": _station_col(e)})
		var gd: Dictionary = sys.get("gates", {})
		for to in gd:
			var pos := _map3(gd[to], hash(str(to))) / KM
			if _seen_at(pos) or Galaxy.has_been(str(to)):
				_put("gate:" + str(to), {"kind": "gate", "name": "Gate to %s" % Galaxy.system(to).get("name", to), "pos": pos, "to": str(to), "color": MapIcons.CYAN})
		var i := 0
		for f in sys.get("fields", []):
			var pos: Vector3 = places.get("field:%d" % i, _map3(f, i * 31)) / KM
			if _seen_at(pos):
				_put("field:%d" % i, {"kind": "field", "name": "Asteroid field", "pos": pos, "ore": "", "rocks": 0, "color": ASTEROID})
			i += 1
		_put("you", {"kind": "you", "name": "Your ship", "pos": objs.get("station:%s:0" % sid, {}).get("pos", Vector3(20, 0, 20)), "color": MapIcons.ORANGE})
		_gather_markers()

	## Survey missions' points here (always shown: they're where the dark is).
	func _gather_markers() -> void:
		var ms := get_tree().get_first_node_in_group("missions") if is_inside_tree() else null
		if ms == null or not ms.has_method("markers"):
			return
		var n := 0
		for mk in ms.markers():
			var p: Vector2 = mk["pos"]
			_put("marker:%d" % n, {"kind": "marker", "name": str(mk["name"]), "pos": Vector3(p.x, 0.0, p.y) * PlanetShape.PX_TO_M / KM, "color": MapIcons.ORANGE})
			n += 1

	static func _map3(p: Vector2, seed: int) -> Vector3:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		return Vector3(p.x, 0.0, p.y) * PlanetShape.PX_TO_M + Vector3(0, rng.randf_range(-2500.0, 2500.0), 0)

	## A planet's place now (m), as Cosmos puts it (Cosmos.orbit_pos_at: the one orbit code).
	static func orbit_pos(r: Dictionary, where: Dictionary) -> Vector3:
		return (load("res://scripts/world/space/cosmos.gd") as GDScript).orbit_pos_at(r, where, Galaxy.time)

	## A point of a planet's orbit (m, round what it circles) at angle `a`.
	static func _orbit_at(r: Dictionary, a: float) -> Vector3:
		return (load("res://scripts/world/space/cosmos.gd") as GDScript).orbit_point(r, a)

	static func _planet_col(look: Dictionary) -> Color:
		return (look.get("color_light", Color(0.65, 0.75, 0.85)) as Color).lerp(Color(1.0, 0.85, 0.6), 0.25)

	func _station_col(e: String) -> Color:
		return MapIcons.CYAN if e == Galaxy.owner_of(Galaxy.current_system) else Galaxy.empire_color(e)

	# --- The 3D parts ---------------------------------------------------------------

	func _sync_3d() -> void:
		var star: Dictionary = objs.get("star", {})
		var sun: Vector3 = star.get("pos", Vector3.ZERO)
		# The worlds and the star: a sphere each (made once, moved after).
		var keep := {}
		for k in objs:
			var o: Dictionary = objs[k]
			if not o["kind"] in ["planet", "star"]:
				continue
			keep[k] = true
			var mi: MeshInstance3D = _bodies.get(k)
			if mi == null:
				mi = MeshInstance3D.new()
				mi.mesh = MapKit.sphere()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var look: Dictionary = o.get("look", {})
				if o["kind"] == "star" and Galaxy.SYSTEMS.has(Galaxy.current_system):
					look = Galaxy.star_spec(Galaxy.current_system)
				mi.material_override = MapKit.body_material(look, o["kind"] == "star")
				world.add_child(mi)
				_bodies[k] = mi
				if o["kind"] == "planet":
					_moon_orbits(mi, o)
			mi.position = o["pos"]
			(mi.material_override as ShaderMaterial).set_shader_parameter("sun_pos", sun)
		for k in _bodies.keys():
			if not keep.has(k):
				(_bodies[k] as Node).queue_free()
				_bodies.erase(k)
		# The star's light.
		_glow.visible = not star.is_empty()
		if not star.is_empty():
			MapKit.set_glow(_glow, 0, sun, float(star["r"]) * 14.0, Color(star["color"], 0.55), 70.0, 0.4)
		# The asteroid fields: their rocks as points (made once).
		for k in objs:
			if objs[k]["kind"] == "field" and not _fields.has(k):
				var mi := MeshInstance3D.new()
				mi.mesh = _rock_cloud(hash(k + Galaxy.current_system))
				mi.material_override = MapKit.points_material(2.5)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				world.add_child(mi)
				_fields[k] = mi
			if _fields.has(k):
				(_fields[k] as Node3D).position = objs[k]["pos"]
		# The planets' orbits: one mesh, made again when the known worlds change.
		var sig := str(objs.keys().filter(func(k): return objs[k]["kind"] == "planet"))
		if sig != _orbit_sig:
			_orbit_sig = sig
			var L := MapKit.Lines.new()
			for k in objs:
				var o: Dictionary = objs[k]
				if o["kind"] != "planet" or str(o["rec"].get("moon_of", "")) != "":
					continue
				var pts := PackedVector3Array()
				for i in 160:
					pts.append(sun + _orbit_at(o["rec"], TAU * i / 160.0) / KM)
				L.poly(pts, Color(o["color"], 0.6), 1.8, true)   # (in the world's own colour: told apart from the grid's rings)
			_orbits.mesh = L.mesh()
		# The plane and its fog (the system's reach: past the furthest gate).
		var reach := 120.0
		for k in objs:
			reach = maxf(reach, Vector2(objs[k]["pos"].x, objs[k]["pos"].z).length() * 1.12)
		for g in Galaxy.system(Galaxy.current_system).get("gates", {}).values():
			reach = maxf(reach, (g as Vector2).length() * PlanetShape.PX_TO_M / KM * 1.12)
		_plane.scale = Vector3(reach, 1.0, reach)
		var pmat := _plane.material_override as ShaderMaterial
		pmat.set_shader_parameter("extent", reach)
		pmat.set_shader_parameter("ring_step", 10.0 if reach < 400.0 else 50.0)
		var f: FogOfWar = Galaxy.fog()
		pmat.set_shader_parameter("has_fog", 0.0 if Galaxy.charted.has(Galaxy.current_system) else 1.0)
		pmat.set_shader_parameter("fog_tex", f.texture())
		pmat.set_shader_parameter("fog_origin", f.origin * PlanetShape.PX_TO_M / KM)
		pmat.set_shader_parameter("fog_size", Vector2(f.cols, f.rows) * f.cell * PlanetShape.PX_TO_M / KM)
		_place_3d()

	## Where what moves is now: each frame the map shows (tick), between the
	## gatherings (rebuild, four times a second) - the 3D game's nodes to the
	## galaxy's clock (Cosmos.place_now: smooth between its orbit steps), or
	## the orbits worked out away from it.
	func _follow() -> void:
		var c := cosmos()
		if c and c.has_method("place_now"):
			var where: Dictionary = c.places_now()
			for k in objs:
				var o: Dictionary = objs[k]
				var n: Variant = o.get("node")
				if is_instance_valid(n) and n is Node3D:
					o["pos"] = c.place_now(n, where) / KM
		elif c == null and _system != "":
			var places: Dictionary = (load("res://scripts/world/space/cosmos.gd") as GDScript).system_places(_system, Galaxy.time)
			for k in places:
				if objs.has(k):
					objs[k]["pos"] = places[k] / KM
		else:
			return
		for k in marks:
			if objs.has(k):
				marks[k]["pos"] = objs[k]["pos"]
		_place_3d()

	## The 3D parts of what moves where it is (the worlds, the fields, the
	## rings, the stems and your course).
	func _place_3d() -> void:
		for k in _bodies:
			var o: Dictionary = objs.get(k, {})
			if not o.is_empty():
				(_bodies[k] as Node3D).position = o["pos"]
		for k in _fields:
			var o: Dictionary = objs.get(k, {})
			if not o.is_empty():
				(_fields[k] as Node3D).position = o["pos"]
		_set_rings()
		_sizes()
		_moving_lines()

	## A ring round every marker (a world's outside its sphere: _sizes).
	func _set_rings() -> void:
		var n := objs.size()
		if _rings.multimesh.instance_count < n:
			_rings.multimesh.instance_count = n + 32
		var i := 0
		for k in objs:
			var o: Dictionary = objs[k]
			var col: Color = o["color"]
			match o["kind"]:
				"station", "gate":
					MapKit.set_ring(_rings, i, o["pos"], 25.0, Color(col, 0.95), MapKit.RING, 2.0)
				"field":
					MapKit.set_ring(_rings, i, o["pos"], 20.0, Color(col, 0.8), MapKit.RING, 1.6)
				"lair":
					MapKit.set_ring(_rings, i, o["pos"], 28.0, Color(col, 1.0), MapKit.PULSE, 2.0)
				"marker":
					MapKit.set_ring(_rings, i, o["pos"], 24.0, Color(MapIcons.CYAN, 0.9), MapKit.RING, 2.0)
				"planet":
					MapKit.set_ring(_rings, i, o["pos"], 22.0, Color(col, 0.45), MapKit.RING, 1.4)
				"you":
					MapKit.set_ring(_rings, i, o["pos"], 34.0, Color(MapIcons.ORANGE, 1.0), MapKit.PULSE, 2.0)
				_:
					continue
			o["ring"] = i
			i += 1
		_rings.multimesh.visible_instance_count = i

	## A moon's orbit drawn round its planet (under its sphere: it moves with it).
	func _moon_orbits(mi: MeshInstance3D, o: Dictionary) -> void:
		var pid := str(o["rec"].get("id", ""))
		var col: Color = o["color"]
		var L := MapKit.Lines.new()
		var C: GDScript = load("res://scripts/world/space/cosmos.gd")
		for r in C.planet_records(Galaxy.current_system):
			if str(r.get("moon_of", "")) != pid:
				continue
			var pts := PackedVector3Array()
			for i in 64:
				pts.append(_orbit_at(r, TAU * i / 64.0) / KM)
			L.poly(pts, Color(col, 0.5), 1.4, true)
		if not L.is_empty():
			var lm := L.into(null)
			lm.name = "MoonOrbits"
			world.add_child(lm)
			mi.set_meta("moon_orbits", lm)
			mi.tree_exiting.connect(lm.queue_free)

	func _rock_cloud(seed: int) -> ArrayMesh:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var pts := PackedVector3Array()
		var cols := PackedColorArray()
		var sizes := PackedFloat32Array()
		var spread := 2600.0 / KM
		for i in 160:
			var d := Vector3(rng.randfn(), rng.randfn() * 0.35, rng.randfn()) * spread * 0.45
			pts.append(d)
			cols.append(Color(ASTEROID.darkened(rng.randf() * 0.4), rng.randf_range(0.5, 0.9)))
			sizes.append(rng.randf_range(0.6, 1.4))
		return MapKit.points(pts, cols, sizes)

	## The worlds kept at least a few pixels across at any zoom (their true
	## size when you're close).
	func _sizes() -> void:
		var px := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / maxf(size.y, 1.0)
		for k in _bodies:
			var o: Dictionary = objs.get(k, {})
			if o.is_empty():
				continue
			var mi: MeshInstance3D = _bodies[k]
			var d := maxf(cam.global_position.distance_to(mi.position), 0.001)
			var moon: bool = o["kind"] == "planet" and str(o["rec"].get("moon_of", "")) != ""
			var least := (14.0 if o["kind"] == "star" else (5.0 if moon else 9.0)) * px * d
			mi.scale = Vector3.ONE * maxf(float(o["r"]), least)
			if o.has("ring"):   # (its ring just outside it)
				MapKit.set_ring(_rings, int(o["ring"]), o["pos"], 22.0, Color(o["color"], 0.45), MapKit.RING, 1.4, mi.scale.x * 2.0 + 10.0 * px * d)
			if mi.has_meta("moon_orbits"):
				(mi.get_meta("moon_orbits") as Node3D).position = mi.position

	## Stems from each thing down to the plane (where it stands over it), your
	## course, your sensors' reach.
	func _moving_lines() -> void:
		var mm := _stems.multimesh
		var fm: MultiMesh = (_stems.get_meta("feet") as MultiMeshInstance3D).multimesh
		if mm.instance_count < objs.size():
			mm.instance_count = objs.size() + 32
			fm.instance_count = objs.size() + 32
		var ns := 0
		var nf := 0
		var fr := maxf(dist * 0.006, 0.05)
		for k in objs:
			var o: Dictionary = objs[k]
			if o["kind"] in ["star", "marker"]:
				continue
			var p: Vector3 = o["pos"]
			var col: Color = o["color"]
			if absf(p.y) > 0.05:
				mm.set_instance_transform(ns, Transform3D(Basis.from_scale(Vector3(1.0, p.y, 1.0)), p))
				mm.set_instance_color(ns, Color(col, 0.38))
				ns += 1
			fm.set_instance_transform(nf, Transform3D(Basis.from_scale(Vector3(fr, 1.0, fr)), Vector3(p.x, 0.0, p.z)))
			fm.set_instance_color(nf, Color(col, 0.35))
			nf += 1
		mm.visible_instance_count = ns
		fm.visible_instance_count = nf
		var c := cosmos()
		var at := you()
		var L := MapKit.Lines.new()
		if c and c.target != null:
			for k in objs:
				if objs[k].get("node") == c.target:
					L.seg(at, objs[k]["pos"], Color(MapIcons.ORANGE, 0.9), 2.5, maxf(4.0, at.distance_to(objs[k]["pos"]) / maxf(dist * 0.03, 0.01)), 1.5)
		if L.is_empty():
			_lines.visible = false
		else:
			_lines.visible = true
			L.into(_lines)
		_sensor.visible = objs.has("you")
		if _sensor.visible:
			var sensor := Galaxy.SENSOR_RANGE * PlanetShape.PX_TO_M / KM
			_sensor.transform = Transform3D(Basis.from_scale(Vector3(sensor, 1.0, sensor)), Vector3(at.x, 0.0, at.z))

	func _view_changed() -> void:
		_sizes()
		_moving_lines()   # (the feet's circles sized to the zoom)

	func tick() -> void:
		_t += 1.0 / anim_hz
		_rebuild_t -= 1.0 / anim_hz
		if _rebuild_t <= 0.0:
			_rebuild_t = 0.25   # (what's where, four times a second - the system goes on)
			rebuild()
			if is_instance_valid(page):
				page._update_info()
		_follow()   # (gathered from the nodes as they stand: placed to this moment too)
		if is_instance_valid(page) and page.trade:
			trade_t -= 1.0 / anim_hz
			if trade_t <= 0.0:
				trade_t = 2.0   # (prices move every economy tick)
				var here := TradeRoutes.stations_of([Galaxy.current_system])
				routes = TradeRoutes.routes_from(here, 0, "", 6) + TradeRoutes.routes_from(here, 2, "", 5, true)

	func fit(now := false) -> void:
		var pts: Array = []
		for k in objs:
			pts.append(objs[k]["pos"])
		if pts.size() < 3:
			pts.append_array([Vector3(-60, 0, -60), Vector3(60, 0, 60)])
		fit_points(pts, now)

	## Where you are: on a world (on foot or landed), that world; else you.
	func you_key() -> String:
		var c := cosmos()
		if c:
			var pl: Node = c.walker.planet if c.walker and c.walker.get("planet") else (c.planet_below(c.ship.global_position, 3000.0) if c.ship and c.has_method("planet_below") else null)
			for k in objs:
				if objs[k]["kind"] == "planet" and objs[k].get("node") == pl and pl != null:
					return k
		return "you" if objs.has("you") else ""

	## The view centred on you at once (the map opened: MapsPage.show_sub) -
	## the first time in a system at the whole system's zoom, after that at
	## the zoom you left it.
	func focus_you() -> void:
		rebuild()
		if not _fitted:
			_fitted = true
			fit(true)
		var k := you_key()
		if k != "":
			_focus_t = objs[k]["pos"]
			snap()

	func centre_on_ship() -> void:
		if objs.has("you"):
			fly_to(objs["you"]["pos"], minf(_dist_t, 60.0))

	func look_at_selected() -> void:
		var o: Dictionary = objs.get(selected_key, {})
		if o.is_empty():
			return
		var r := float(o.get("r", 0.0))
		fly_to(o["pos"], clampf(maxf(r * 8.0, 6.0), 2.0, _dist_t))

	func accept() -> void:
		if is_instance_valid(page):
			page.plot()

	func cycle_order() -> Array:
		return order

	func clicked(key: String, _add: bool) -> void:
		select(key)

	# --- The overlay -------------------------------------------------------------------

	func draw_overlay() -> void:
		var font := NeonTheme.heavy_font()
		var fs := Settings.fs("menu", 14)
		var small := maxi(Settings.MIN_FONT, fs - 2)
		var taken: Array = []
		var c := cosmos()
		var tgt: Node = c.target if c else null
		# Selected and course first: their names win the room.
		var keys: Array = []
		for k in order:
			if at_screen(k) != null:
				keys.append([-_rank(k, tgt), k])
		keys.sort()
		for e in keys:
			var k: String = e[1]
			var o: Dictionary = objs[k]
			var p: Vector2 = at_screen(k)
			var col: Color = o["color"]
			var hi: bool = k == selected_key or k == hover_key
			match o["kind"]:
				"star":
					tag(p + Vector2(0, -26), str(o["name"]).to_upper(), fs, Color(1.0, 0.85, 0.55), taken, font)
				"planet":
					var moon := str(o["rec"].get("moon_of", "")) != ""
					if not moon or hi or _close(o):
						tag(p + Vector2(0, _screen_r(k, 4.0) + 10.0 + fs), str(o["name"]).to_upper(), small if moon else fs, col, taken, font)
				"station":
					MapIcons.glyph(self, p, 7.5, col.lightened(0.25), "station")
					tag(p + Vector2(0, -18), str(o["name"]).to_upper(), small, col.lightened(0.3), taken, font)
				"gate":
					MapIcons.glyph(self, p, 7.5, col.lightened(0.25), "gate")
					var on_route: bool = Galaxy.route.size() >= 2 and Galaxy.route[1] == o["to"]
					tag(p + Vector2(0, 26), ("GATE › %s" % Galaxy.system(o["to"]).get("name", "?")).to_upper(), small,
						MapIcons.ORANGE if on_route else NeonTheme.HEAD, taken, font)
				"field":
					MapIcons.glyph(self, p, 6.0, col.lightened(0.25), "asteroid")
					if hi:
						tag(p + Vector2(0, 24), "ASTEROIDS", small, col, taken, font)
				"lair":
					MapIcons.glyph(self, p, 7.5, col.lightened(0.25), "signal")
					tag(p + Vector2(0, 26), str(o["name"]), small, col.lightened(0.3), taken, font)
				"marker":
					MapIcons.glyph(self, p, 7.5, MapIcons.CYAN, "mountain")
					tag(p + Vector2(0, 26), str(o["name"]), small, NeonTheme.HEAD, taken, font)
				"ship", "monster":
					var v: Vector2 = _screen_dir(o)
					draw_colored_polygon(PackedVector2Array([p + v * 7.0, p + v.orthogonal() * 4.5 - v * 4.5, p - v.orthogonal() * 4.5 - v * 4.5]), col)
					if hi or o.get("node") == tgt:
						tag(p + Vector2(0, -12), str(o["name"]), small, col, taken, font)
				"you":
					var v: Vector2 = _screen_dir(o)
					var tri := PackedVector2Array([p + v * 9.0, p + v.orthogonal() * 6.0 - v * 6.0, p - v.orthogonal() * 6.0 - v * 6.0])
					draw_colored_polygon(tri, Color(1.0, 0.7, 0.35))
					tag(p + Vector2(0, 30), "YOU", small, MapIcons.ORANGE, taken, font)
			if o.get("node") != null and o.get("node") == tgt:
				_brackets(p, 21.0, MapIcons.ORANGE)
				tag(p + Vector2(0, -30), "COURSE  ·  " + SolarView.km(dist_to(o)), small, MapIcons.ORANGE, taken, font)
			if k == selected_key:
				_brackets(p, 17.0, Color(1, 1, 1, 0.9))
		if is_instance_valid(page) and page.trade:
			_draw_trade(small)
		# Scale: the grid's rings.
		var ring := 10.0 if _plane.scale.x < 400.0 else 50.0
		draw_string(font, Vector2(14, size.y - 14), "GRID  %d KM A RING  ·  VIEW %s ACROSS" % [int(ring), SolarView.km(2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) * size.x / maxf(size.y, 1.0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(NeonTheme.HEAD, 0.8))

	func _rank(k: String, tgt: Node) -> int:
		if k == selected_key:
			return 5
		if objs[k].get("node") != null and objs[k].get("node") == tgt:
			return 4
		if k == "you":
			return 3
		return {"star": 2, "station": 2, "gate": 2, "planet": 1}.get(objs[k]["kind"], 0)

	## A world's radius on the screen (px), at least `least`.
	func _screen_r(k: String, least: float) -> float:
		var mi: MeshInstance3D = _bodies.get(k)
		if mi == null:
			return least
		var d := maxf(cam.global_position.distance_to(mi.position), 0.001)
		var px := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / maxf(size.y, 1.0)
		return maxf(mi.scale.x / (px * d), least)

	func _close(o: Dictionary) -> bool:
		return cam.global_position.distance_to(o["pos"]) < 60.0

	## Which way it's heading, on the screen.
	func _screen_dir(o: Dictionary) -> Vector2:
		var n: Node3D = o.get("node")
		var v := Vector3.ZERO
		if is_instance_valid(n):
			var vel: Variant = n.get("velocity")
			v = vel if vel is Vector3 and (vel as Vector3).length() > 1.0 else -n.global_basis.z
		if v == Vector3.ZERO:
			return Vector2.UP
		var a: Variant = project(o["pos"])
		var b: Variant = project(o["pos"] + v.normalized() * dist * 0.05)
		if a == null or b == null or (b - a).length() < 0.5:
			return Vector2.UP
		return (b - a).normalized()

	func _brackets(p: Vector2, r: float, col: Color) -> void:
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			draw_arc(p, r, a - 0.35, a + 0.35, 6, col, 2.0, true)

	## The trade runs: station to station, or station to the gate on the way.
	func _draw_trade(fs: int) -> void:
		if routes.is_empty():
			return
		var top := 1.0
		for r in routes:
			top = maxf(top, r["profit"])
		var t := Time.get_ticks_msec() / 1000.0
		var n := 0
		var taken := []
		for r in routes:
			var a: Variant = at_screen("station:" + str(r["from"]))
			if a == null:
				continue   # (from stations you know; where it sells may be out in the dark)
			var b: Variant
			var tag_t := TradeRoutes.tag_text(r)
			if r["to_sys"] == Galaxy.current_system:
				b = at_screen("station:" + str(r["to"]))
			else:
				var path := Galaxy.find_route(Galaxy.current_system, r["to_sys"])
				b = at_screen("gate:" + str(path[1])) if path.size() >= 2 else null
				tag_t += " › " + TradeRoutes.system_name(r["to_sys"]).to_upper()
			if b == null:
				continue
			var d: Vector2 = ((b as Vector2) - (a as Vector2)).normalized()
			var off := d.orthogonal() * ((n % 3) - 1) * 8.0
			n += 1
			var pts := PackedVector2Array([a + d * 20.0 + off, b - d * 22.0 + off])
			if pts[0].distance_to(pts[1]) < 30.0:
				continue
			TradeRoutes.draw_run(self, pts, r["profit"] / top, t)
			TradeRoutes.draw_tag(self, pts[0].lerp(pts[1], 0.3 + 0.12 * (n % 3)), tag_t, fs, taken)

	# --- The details -------------------------------------------------------------------

	## The panel's text for `o` (BBCode).
	func describe(o: Dictionary) -> String:
		var dim := UI.TEXT_DIM.to_html(false)
		var col := (o["color"] as Color).lightened(0.25).to_html(false)
		var t := "[b][font_size=20]%s[/font_size][/b]\n" % str(o["name"]).to_upper()
		var lines: Array = []
		var sys: Dictionary = Galaxy.system(Galaxy.current_system)
		match o["kind"]:
			"star":
				var st: Dictionary = Galaxy.STARS.get(str(sys.get("star", "yellow")), {})
				t += "[color=#%s]%s[/color]\n" % [col, st.get("name", "Star")]
				lines.append(["Radius", km(float(o["r"]))])
				var owner := str(sys.get("owner", ""))
				lines.append(["System of", "[color=#%s]%s[/color]" % [Galaxy.empire_color(owner).to_html(false), Galaxy.empire_name(owner)]])
				lines.append(["Pirate activity", ["low", "moderate", "high", "extreme"][clampi(int(float(sys.get("pirates", 0.0)) * 3.99), 0, 3)]])
				var stt := Galaxy.state_of(Galaxy.current_system)
				if stt != "none":
					lines.append(["State", "[color=#ffcf6a]%s[/color]" % Galaxy.STATES[stt]["name"]])
				var known := objs.keys().filter(func(k): return objs[k]["kind"] == "planet").size()
				var all: int = (load("res://scripts/world/space/cosmos.gd") as GDScript).planet_records(Galaxy.current_system).size()
				lines.append(["Worlds charted", "%d of %d" % [known, all] if not Galaxy.charted.has(Galaxy.current_system) else str(all)])
			"planet":
				var rec: Dictionary = o["rec"]
				var moon_of := str(rec.get("moon_of", ""))
				var type := str(rec.get("type", "moon"))
				var kind: String = {"ocean": "Ocean world", "volcanic": "Volcanic world", "ice": "Ice world", "gas_giant": "Gas giant", "moon": "Moon"}.get(type, type.capitalize())
				if moon_of != "":
					kind = "Moon of " + _name_of("planet:" + moon_of, moon_of)
				t += "[color=#%s]%s[/color]\n" % [col, kind]
				lines.append(["Radius", km(float(o["r"]))])
				lines.append(["Orbit", km(float(rec.get("orbit", 0.0)) * PlanetShape.PX_TO_M / KM) + (" from its world" if moon_of != "" else " from the star")])
				var moons: Array = []
				var C: GDScript = load("res://scripts/world/space/cosmos.gd")
				for r in C.planet_records(Galaxy.current_system):
					if str(r.get("moon_of", "")) == str(rec.get("id", "")):
						moons.append(str(r.get("name", "")))
				if not moons.is_empty():
					lines.append(["Moons", ", ".join(moons)])
				lines.append(["Landing", "[color=#7dffa0]you can land[/color]" if type != "gas_giant" else "no ground to land on"])
				if int(o.get("towns", 0)) > 0:
					lines.append(["Towns", str(o["towns"])])
			"station":
				var rec: Dictionary = o["rec"]
				var e := str(o["empire"])
				var sid := str(rec.get("id", ""))
				var pres := Galaxy.presence_label(Galaxy.station_presence(sid))
				t += "[color=#%s]%s station%s[/color]\n" % [Galaxy.empire_color(e).to_html(false), Galaxy.EMPIRES.get(e, {}).get("short", "?"), (" · " + pres) if pres != "" else ""]
				lines.append(["Economy", Galaxy.ECONOMIES.get(str(rec.get("economy", "")), {}).get("name", "?")])
				lines.append(["Your standing", Galaxy.standing(e)])
				lines.append(["Condition", "%d%%" % int(Galaxy.station_health(sid))])
				lines.append(["Market", "known (docked)" if Galaxy.visited.has(sid) else ("shared with you" if Galaxy.shares_market(sid) else "not yet known - dock to see it")])
			"gate":
				var to := str(o["to"])
				var owner := Galaxy.owner_of(to)
				t += "[color=#%s]Jump gate[/color]\n" % col
				lines.append(["Leads to", "%s ([color=#%s]%s[/color])" % [Galaxy.system(to).get("name", to), Galaxy.empire_color(owner).to_html(false), Galaxy.empire_name(owner)]])
				lines.append(["Been there", "yes" if Galaxy.has_been(to) else "no - uncharted"])
				var i := Galaxy.route.find(to)
				if i == 1:
					lines.append(["Route", "[color=#ffb060]the next gate of your route (%d jumps to %s)[/color]" % [Galaxy.route.size() - 1, Galaxy.system(Galaxy.route[-1]).get("name", "?")]])
			"field":
				t += "[color=#%s]Asteroid field[/color]\n" % col
				if str(o.get("ore", "")) != "":
					lines.append(["Ore", str(o["ore"]).capitalize()])
				if int(o.get("rocks", 0)) > 0:
					lines.append(["Rocks", str(o["rocks"])])
			"lair":
				t += "[color=#%s]Signal source[/color]\n" % col
			"marker":
				t += "[color=#%s]Survey point (mission)[/color]\n" % col
			"ship", "monster":
				var n: Node = o.get("node")
				t += "[color=#%s]%s[/color]\n" % [col, "Hostile" if o.get("hostile", false) else "Neutral"]
				if is_instance_valid(n):
					if n.get("kind") is String:
						lines.append(["Kind", str(n.get("kind")).capitalize()])
					var fac: Variant = n.get("faction")
					if fac is String and fac != "":
						lines.append(["Flag", Galaxy.empire_name(fac)])
					if n.get("max_hull") != null:
						lines.append(["Hull", "%d%%" % int(100.0 * float(n.get("hull")) / maxf(float(n.get("max_hull")), 1.0))])
					var vel: Variant = n.get("velocity")
					if vel is Vector3:
						lines.append(["Speed", "%d m/s" % int((vel as Vector3).length())])
			"you":
				var n: Node = o.get("node")
				t += "[color=#%s]%s[/color]\n" % [col, Galaxy.system(Galaxy.current_system).get("name", "")]
				if is_instance_valid(n):
					lines.append(["Hull", "%d / %d" % [int(n.get("hull")), int(n.get("max_hull"))]])
					lines.append(["Shields", "%d / %d" % [int(n.get("shield")), int(n.get("max_shield"))]])
					lines.append(["Speed", "%d m/s" % int((n.get("velocity") as Vector3).length())])
				lines.append(["From the star", km(Vector3(o["pos"]).distance_to(objs.get("star", {}).get("pos", Vector3.ZERO)))])
				var c := cosmos()
				if c and c.target != null:
					lines.append(["Course", str(c.label_of(c.target))])
		if o["kind"] != "you":
			lines.append(["Distance", km(dist_to(o))])
			lines.append(["Height", ("%+.1f km" % float(o["pos"].y)) + " over the plane"])
		for l in lines:
			t += "[color=#%s]%s:[/color] %s\n" % [dim, l[0], l[1]]
		return t

	func _name_of(key: String, fallback: String) -> String:
		if objs.has(key):
			return str(objs[key]["name"])
		var C: GDScript = load("res://scripts/world/space/cosmos.gd")
		for r in C.planet_records(Galaxy.current_system):
			if str(r.get("id", "")) == fallback:
				return str(r.get("name", fallback))
		return fallback
