extends HBoxContainer
## The Automaton's MAP > GALAXY: the galaxy map - New Hellas in 3D (Map3DView): its
## 120 star systems through the whole volume, over the galactic plane (stems
## drop from each to it), gate lanes, the empires' territories as glowing
## clouds round their systems, war fronts, the system states, your route.
## Drag to turn it, right / middle drag to pan, the wheel zooms; click a
## system for its details (the panel beside it), PLOT ROUTE plans the way
## there through the gates you know - your course is set to the first gate
## and, after each jump, the next (CosmosMapMirror) - and Shift + click (or
## ADD WAYPOINT) adds it to the end of the route.
## Fog of war: only the systems you've been in show (Galaxy.been - Knossos
## always), the lanes between them, and faint stubs where a lane leads off to
## one you haven't (its gate names it: an uncharted "?" you can plot a route
## to). Right column: diplomacy (who is at war), your reputation and the
## galactic news feed. TRADE ROUTES (the button, or T): the best trade runs
## between systems (TradeRoutes.galaxy_routes - buy at one station, sell at a
## station up to two jumps away) as green arrows with their good and profit a
## unit; the right column lists them (click one to plot a route to where you
## buy).

var data: Node
var ship: Node2D

var _view: GalaxyView
var _info: RichTextLabel
var _diplo: RichTextLabel
var _news: RichTextLabel
var _plot: Button
var _way: Button
var _look: Button
var selected := ""
var trade := false              # the trade layer on
var trade_item := ""            # "" = every good
var routes: Array = []          # the runs shown (TradeRoutes.galaxy_routes)
var _trade_btn: Button
var _goods: OptionButton
var _trade_box: Control
var _trade_text: RichTextLabel
var _plain_box: Array = []      # diplomacy & news (hidden while trading)


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_view = GalaxyView.new()
	_view.page = self
	_view.custom_minimum_size = Vector2(780, 590)
	_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_view.selected.connect(func(k): select(k))
	add_child(_view)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(UI.section("SYSTEM"))
	_info = _rich(190)
	col.add_child(_info)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	_plot = EditorIcons.dress(UI.button("", _plot_route, 15), "next", "", "Plot route")
	_plot.size_flags_horizontal = SIZE_EXPAND_FILL
	_way = EditorIcons.dress(UI.button("", func(): add_to_route(selected), 15), "add", EditorIcons.tip("Add waypoint", "Shift + click",
		"Adds this system to the end of your route: the route goes on from where it ends now - round several systems in one trip."))
	_look = EditorIcons.dress(UI.button("", func(): _view.look_at_system(selected), 15), "eye", EditorIcons.tip("Look at it", "double click", "Flies the view to it."))
	var fit := EditorIcons.dress(UI.button("", func(): _view.fit(), 15), "fit_all", EditorIcons.tip("Whole galaxy", "Home  ·  middle click", "Turns and zooms the map to show every system you know."))
	for b in [_plot, _way, _look, fit]:
		b.focus_mode = FOCUS_NONE
		btns.add_child(b)
	col.add_child(btns)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	_trade_btn = EditorIcons.dress(UI.button("TRADE ROUTES", toggle_trade, 15), "buy",
		EditorIcons.tip("Trade routes", "T", "Shows the best trade runs between systems: where to buy a good and where, up to two jumps on, to sell it - green arrows with the profit a unit.\nPrices change as traders (and you) move goods: the routes follow."))
	_trade_btn.toggle_mode = true
	_trade_btn.focus_mode = FOCUS_NONE
	_trade_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	tr.add_child(_trade_btn)
	_goods = OptionButton.new()
	_goods.focus_mode = FOCUS_NONE
	_goods.add_item("All goods")
	for c in Galaxy.COMMODITIES:
		_goods.add_item(Items.display_name(c))
	_goods.tooltip_text = "Show the runs for one good, or the best of every good."
	_goods.item_selected.connect(func(i): trade_item = "" if i == 0 else Galaxy.COMMODITIES[i - 1]; refresh())
	tr.add_child(_goods)
	col.add_child(tr)
	_trade_box = VBoxContainer.new()
	_trade_box.size_flags_vertical = SIZE_EXPAND_FILL
	_trade_box.visible = false
	_trade_box.add_child(UI.section("BEST TRADE RUNS  ·  PROFIT A UNIT"))
	_trade_text = _rich(300)
	_trade_text.size_flags_vertical = SIZE_EXPAND_FILL
	_trade_text.meta_clicked.connect(_on_route_clicked)
	_trade_box.add_child(_trade_text)
	col.add_child(_trade_box)
	var dh := UI.section("DIPLOMACY  ·  YOUR STANDING")
	col.add_child(dh)
	_diplo = _rich(120)
	col.add_child(_diplo)
	var nh := UI.section("GALACTIC NEWS")
	col.add_child(nh)
	_news = _rich(140)
	_news.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_news)
	_plain_box = [dh, _diplo, nh, _news]


func _rich(h: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	r.custom_minimum_size = Vector2(0, h)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	return r


func refresh() -> void:
	if selected == "" or not Galaxy.is_known(selected):
		selected = Galaxy.current_system
	_view.rebuild()
	_view.selected_key = selected
	_update_trade()
	_update_info()
	_update_diplo()
	var lines := []
	for n in Galaxy.news.slice(0, 25):
		var col: String = {"danger": "#ff7a6a", "good": "#7dffa0"}.get(n["kind"], "#c7d6ea")
		lines.append("[color=#6f8199]%s[/color]  [color=%s]%s[/color]" % [_clock(n["t"]), col, n["text"]])
	_news.text = "\n".join(lines) if not lines.is_empty() else "[color=#6f8199]No news yet.[/color]"


## Opened (MapsPage.show_sub): centred on the system you're in, at once (the
## zoom you left it at; the first time, a few systems round it).
func focus_you(_keep := false) -> void:
	if not Galaxy.SYSTEMS.has(Galaxy.current_system):
		return
	var d := 1300.0 if not _view._fitted else _view._dist_t
	_view._fitted = true
	_view.snap_to(_view.at(Galaxy.current_system), d)
	_view.snap()


func toggle_trade() -> void:
	trade = not trade
	refresh()


func _update_trade() -> void:
	_trade_btn.set_pressed_no_signal(trade)
	_trade_box.visible = trade
	for n in _plain_box:
		n.visible = not trade
	routes = TradeRoutes.galaxy_routes_spread(trade_item, 2, 10) if trade else []
	_view.mark_dirty()
	if not trade:
		return
	var lines := []
	for i in routes.size():
		var r: Dictionary = routes[i]
		lines.append("[url=%d][color=#7dffa0][b]+%d dr[/b][/color]  [color=#ffcf6a]%s[/color][/url]\n   %s (%s) › %s (%s)  ·  %d → %d dr  ·  %d jump%s" % [i, r["profit"],
			Items.display_name(r["item"]), TradeRoutes.station_name(r["from"]), TradeRoutes.system_name(r["from_sys"]),
			TradeRoutes.station_name(r["to"]), TradeRoutes.system_name(r["to_sys"]), r["buy"], r["sell"], r["jumps"], "" if r["jumps"] == 1 else "s"])
	_trade_text.text = "\n".join(lines) if not lines.is_empty() else "[color=#6f8199]No profitable runs you know of%s. Runs start at stations whose market you know - dock at them (or become Friendly with an empire: it shares all of its own) - and end at stations you've found.[/color]" % ("" if trade_item == "" else " for " + Items.display_name(trade_item))


## A run clicked in the list: plot a route to its start (or, there already, to its end).
func _on_route_clicked(meta) -> void:
	var i := int(str(meta))
	if i < 0 or i >= routes.size():
		return
	var r: Dictionary = routes[i]
	var to: String = r["from_sys"] if r["from_sys"] != Galaxy.current_system else r["to_sys"]
	selected = to
	_set_route(_route_to(Galaxy.current_system, to))
	if Galaxy.route.size() >= 2:
		GameLog.post("Trade run: buy %s at %s, sell at %s (+%d dr a unit). Route plotted to %s." % [Items.display_name(r["item"]),
			TradeRoutes.station_name(r["from"]), TradeRoutes.station_name(r["to"]), r["profit"], TradeRoutes.system_name(to)], "mission")
	refresh()


func _clock(t: float) -> String:
	return "%02d:%02d" % [int(t / 60.0), int(t) % 60]


func select(id: String) -> void:
	if id == "" or not Galaxy.is_known(id):
		return
	selected = id
	_view.selected_key = id
	_view.mark_dirty()
	_update_info()


## The way from a to b: through the systems you've been in (find_known_route),
## else - a system you can't reach that way - none.
func _route_to(a: String, b: String) -> Array:
	return Galaxy.find_known_route(a, b)


## The route set (and, in the 3D game, your course to its first gate).
func _set_route(r: Array) -> void:
	Galaxy.route = r if r.size() >= 2 else []
	aim_at_gate()
	_view.mark_dirty()


## In the 3D game: your target the gate toward the route's next system.
func aim_at_gate() -> void:
	var c := get_tree().current_scene if is_inside_tree() else null
	if c == null or not c.has_method("bodies") or Galaxy.route.size() < 2:
		return
	for g in c.get("gates"):
		if is_instance_valid(g) and str(g.to) == Galaxy.route[1]:
			c.target = g
			return


func _update_info() -> void:
	var sys: Dictionary = Galaxy.system(selected)
	if sys.is_empty():
		return
	var been := Galaxy.has_been(selected)
	var owner: String = sys["owner"]
	var col: String = Galaxy.empire_color(owner).to_html(false)
	var dim := UI.TEXT_DIM.to_html(false)
	var path := _route_to(Galaxy.current_system, selected)
	var t := "[b][font_size=20]%s[/font_size][/b]   [color=#%s]%s[/color]\n" % [str(sys["name"]).to_upper(), col, Galaxy.empire_name(owner)]
	var lines: Array = []
	if been:
		var n_moons: int = 1 if selected == Galaxy.HOME else sys["planets"].filter(func(pl): return pl["moon_of"] != "").size()
		var n_planets: int = (Planets.PLANETS.size() - 1) if selected == Galaxy.HOME else sys["planets"].size() - n_moons
		lines.append(["Star", "%s (%s)" % [sys["name"], Galaxy.STARS[sys["star"]]["name"].to_lower()]])
		lines.append(["Worlds", "%d planet%s%s" % [n_planets, "" if n_planets == 1 else "s", ("  ·  %d moon%s" % [n_moons, "" if n_moons == 1 else "s"]) if n_moons > 0 else ""]])
		var st: String = Galaxy.state_of(selected)
		if st != "none":
			lines.append(["State", "[color=#ffcf6a]%s[/color] - %s" % [Galaxy.STATES[st]["name"], Galaxy.STATES[st]["desc"]]])
		lines.append(["Pirate activity", ["low", "moderate", "high", "extreme"][clampi(int(float(sys["pirates"]) * 3.99), 0, 3)]])
		var known := []
		for sid in sys["stations"]:
			if not Galaxy.knows_station(sid) and selected != Galaxy.current_system:
				continue
			var e := Galaxy.station_owner(sid)
			var pres := Galaxy.presence_label(Galaxy.station_presence(sid))
			known.append("%s (%s%s)" % [Galaxy.stations[sid]["name"], Galaxy.ECONOMIES[Galaxy.stations[sid]["economy"]]["name"].to_lower(),
				(", [color=#%s]%s[/color]" % [Galaxy.empire_color(e).to_html(false), pres if e == "independent" else "%s %s" % [Galaxy.EMPIRES[e]["short"], pres]]) if pres != "" else ""])
		lines.append(["Stations", "%d%s" % [sys["stations"].size(), (" - known: " + ", ".join(known)) if not known.is_empty() else ""]])
		lines.append(["Visited", "you are here" if selected == Galaxy.current_system else "yes"])
	else:
		var from := ""
		for n in Galaxy.neighbors(selected):
			if Galaxy.has_been(n):
				from = Galaxy.SYSTEMS[n]["name"]
				break
		lines.append(["Uncharted", "you haven't been there - a gate from %s leads to it" % from])
	lines.append(["Your standing", "%s (%+d)" % [Galaxy.standing(owner), int(Galaxy.reputation.get(owner, 0.0))]])
	var wars: Array = Galaxy.MAJOR.filter(func(e): return e != owner and Galaxy.at_war(owner, e)).map(func(e): return Galaxy.EMPIRES[e]["short"])
	if owner in Galaxy.MAJOR:
		lines.append(["At war with", ", ".join(wars) if not wars.is_empty() else "no one"])
	var ly := (Galaxy.SYSTEMS[Galaxy.current_system]["pos3"] as Vector3).distance_to(Galaxy.SYSTEMS[selected]["pos3"]) * 0.1
	if selected != Galaxy.current_system:
		lines.append(["Distance", ("%d jump%s" % [path.size() - 1, "" if path.size() == 2 else "s"] if not path.is_empty() else "[color=#ff7a6a]no route you know[/color]") + "  ·  %.1f light-years" % ly])
		if not path.is_empty():
			lines.append(["Route", " › ".join(path.map(func(p): return Galaxy.SYSTEMS[p]["name"]))])
	for l in lines:
		t += "[color=#%s]%s:[/color] %s\n" % [dim, l[0], l[1]]
	if Galaxy.route.size() >= 2:
		t += "[color=#ffb060]Your route: %s (%d jumps)[/color]" % [" › ".join(Galaxy.route.map(func(p): return Galaxy.SYSTEMS[p]["name"])), Galaxy.route.size() - 1]
	_info.text = t
	_plot.disabled = selected == Galaxy.current_system or path.is_empty()
	var clearing: bool = not Galaxy.route.is_empty() and Galaxy.route[-1] == selected
	if clearing:
		_plot.disabled = false
	_plot.icon = EditorIcons.get_icon("abandon" if clearing else "next")
	_plot.text = "Clear route" if clearing else "Plot route"
	_plot.tooltip_text = EditorIcons.tip("Clear route" if clearing else "Plot route to %s" % sys["name"], "Enter  ·  Space  ·  A",
		"Removes the route to %s: the HUD stops pointing the way." % sys["name"] if clearing else
		"Plans the shortest way through the jump gates you know to %s. Your course is set to the first gate, and after each jump to the next.\nUnavailable for the system you're in, or when no gates you know lead there." % sys["name"])
	_way.disabled = selected == Galaxy.current_system or path.is_empty() or (not Galaxy.route.is_empty() and Galaxy.route[-1] == selected)
	_look.disabled = false


func _update_diplo() -> void:
	var t := ""
	var m: Array = Galaxy.MAJOR
	for i in m.size():
		for j in range(i + 1, m.size()):
			var a: String = m[i]
			var b: String = m[j]
			var war: bool = Galaxy.at_war(a, b)
			var rel := Galaxy.relation(a, b)
			var mood := "[color=#ff6a5a]AT WAR[/color]" if war else ("[color=#7dffa0]allied[/color]" if rel > 40 else ("peace" if rel > -10 else "[color=#ffcf6a]tense[/color]"))
			t += "%s – %s: %s\n" % [Galaxy.EMPIRES[a]["short"], Galaxy.EMPIRES[b]["short"], mood]
	t += "Everyone – Sea Peoples: [color=#ff6a5a]AT WAR[/color]\n"
	t += "Independents: neutral with everyone, at war with no one\n"
	for e in m + ["independent"]:
		var rep: float = Galaxy.reputation.get(e, 0.0)
		t += "You – [color=#%s]%s[/color]: %+d (%s)\n" % [Galaxy.empire_color(e).to_html(false), Galaxy.EMPIRES[e]["short"], int(rep), Galaxy.standing(e)]
	_diplo.text = t


## Shift + click / ADD WAYPOINT: the route goes on from where it ends now (or
## from here) to this system - a waypoint; plain Plot route replaces it.
func add_to_route(id: String) -> void:
	if id == "":
		return
	var start: String = Galaxy.route[-1] if not Galaxy.route.is_empty() else Galaxy.current_system
	selected = id
	if start == id:
		refresh()
		return
	var leg := _route_to(start, id)
	if leg.is_empty():
		GameLog.post("No route you know from %s to %s." % [Galaxy.SYSTEMS[start]["name"], Galaxy.SYSTEMS[id]["name"]], "danger")
		refresh()
		return
	var was_empty := Galaxy.route.is_empty()
	_set_route(leg if was_empty else Galaxy.route + leg.slice(1))
	GameLog.post("Waypoint: %s added to the route (%d jumps in all)." % [Galaxy.SYSTEMS[id]["name"], Galaxy.route.size() - 1], "mission")
	refresh()


func _plot_route() -> void:
	if not Galaxy.route.is_empty() and Galaxy.route[-1] == selected:
		_set_route([])
		GameLog.post("Route cleared", "info")
	else:
		_set_route(_route_to(Galaxy.current_system, selected))
		if Galaxy.route.size() >= 2:
			GameLog.post("Route plotted to %s: %d jumps. Course set to the %s gate." % [Galaxy.SYSTEMS[selected]["name"], Galaxy.route.size() - 1, Galaxy.SYSTEMS[Galaxy.route[1]]["name"]], "mission")
	refresh()


## The galaxy in 3D: a map unit a unit, round the galaxy's middle.
class GalaxyView extends Map3DView:
	var page: Node
	var centre := Vector3.ZERO     # (the galaxy's middle: the plane's centre)
	var shown: Array = []          # systems shown (been there)
	var stubs: Array = []          # uncharted systems a lane from them leads to
	var _glow: MultiMeshInstance3D # the systems' stars
	var _rings: MultiMeshInstance3D # their owners' rings, the crises' turning arcs, your system's pulse
	var _lab := {}                 # id -> [its name, its colour] (the overlay's)
	var _land: MultiMeshInstance3D # the territories (soft clouds in their owners' colours)
	var _lanes: MeshInstance3D
	var _route: MeshInstance3D
	var _plane: MeshInstance3D
	var _sky: MeshInstance3D
	var _sig := ""
	var _route_sig := ""
	var _fitted := false
	var _t := 0.0
	var _check_t := 0.0

	func _init() -> void:
		super()
		min_dist = 40.0
		max_dist = 9000.0
		anim_hz = 30.0
		overlay_hz = 4.0
		for id in Galaxy.SYSTEMS:
			centre += Galaxy.SYSTEMS[id]["pos3"]
		centre /= maxf(1.0, Galaxy.SYSTEMS.size())
		centre.y = 0.0
		_plane = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * 2.0
		_plane.mesh = pm
		var mat := MapKit.plane_material()
		mat.set_shader_parameter("ring_step", 200.0)
		mat.set_shader_parameter("extent", 1900.0)
		mat.set_shader_parameter("spokes", 16.0)
		mat.set_shader_parameter("strength", 0.38)
		_plane.material_override = mat
		_plane.scale = Vector3(1900.0, 1.0, 1900.0)
		world.add_child(_plane)
		_sky = MeshInstance3D.new()
		_sky.mesh = _starfield()
		_sky.material_override = MapKit.points_material(2.0)
		world.add_child(_sky)
		_land = MapKit.glows(Galaxy.SYSTEMS.size())
		world.add_child(_land)
		_lanes = MeshInstance3D.new()
		_lanes.material_override = MapKit.line_material()
		world.add_child(_lanes)
		_route = MeshInstance3D.new()
		_route.material_override = MapKit.line_material()
		world.add_child(_route)
		_glow = MapKit.glows(Galaxy.SYSTEMS.size())
		world.add_child(_glow)
		_rings = MapKit.glows(Galaxy.SYSTEMS.size() * 2 + 1)
		world.add_child(_rings)

	## Where a system is on the map.
	func at(id: String) -> Vector3:
		return (Galaxy.SYSTEMS[id]["pos3"] as Vector3) - centre

	## The far stars round it all (still: they turn with the view).
	func _starfield() -> ArrayMesh:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var pts := PackedVector3Array()
		var cols := PackedColorArray()
		var sizes := PackedFloat32Array()
		for i in 1400:
			var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			pts.append(d * rng.randf_range(14000.0, 22000.0))
			var warm := rng.randf()
			cols.append(Color(Color(0.75, 0.82, 1.0).lerp(Color(1.0, 0.85, 0.7), warm), rng.randf_range(0.15, 0.6)))
			sizes.append(rng.randf_range(0.5, 1.3))
		# (and a faint band of them along the galactic plane)
		for i in 900:
			var a := rng.randf() * TAU
			var r := rng.randf_range(14000.0, 22000.0)
			pts.append(Vector3(cos(a) * r, rng.randfn() * 1200.0, sin(a) * r))
			cols.append(Color(0.9, 0.85, 0.8, rng.randf_range(0.1, 0.35)))
			sizes.append(rng.randf_range(0.4, 1.0))
		return MapKit.points(pts, cols, sizes)

	## What's shown, from what you know (made again when that changes).
	func rebuild() -> void:
		shown = Galaxy.SYSTEMS.keys().filter(func(id): return Galaxy.has_been(id))
		stubs = Galaxy.SYSTEMS.keys().filter(func(id): return not Galaxy.has_been(id) and Galaxy.is_known(id))
		marks = {}
		for id in shown:
			marks[id] = {"pos": at(id), "r": 16.0}
		for id in stubs:
			marks[id] = {"pos": at(id), "r": 12.0}
		var owners := str(shown.map(func(id): return Galaxy.owner_of(id) + Galaxy.state_of(id)))
		var wars := str(Galaxy.war.keys())
		var sig := str(shown) + owners + wars + Galaxy.current_system
		if sig != _sig:
			_sig = sig
			_build_still()
		_build_route()
		if not _fitted and size.x > 10.0:
			_fitted = true
			snap_to(at(Galaxy.current_system), 1300.0)
		mark_dirty()

	func _war(a: String, b: String) -> bool:
		var oa := Galaxy.owner_of(a)
		var ob := Galaxy.owner_of(b)
		return oa != ob and Galaxy.at_war(oa, ob)

	## The stars, the territories, the lanes (with their stubs), the stems.
	func _build_still() -> void:
		var n := 0
		var land := 0
		var rings := 0
		_lab = {}
		for id in Galaxy.SYSTEMS:
			if not marks.has(id):
				continue
			var been := Galaxy.has_been(id)
			var star: Dictionary = Galaxy.STARS[Galaxy.SYSTEMS[id]["star"]]
			var oc := Galaxy.empire_color(Galaxy.owner_of(id))
			var p := at(id)
			_lab[id] = [str(Galaxy.SYSTEMS[id]["name"]).to_upper(), oc.lightened(0.45)]
			if been:
				MapKit.set_glow(_glow, n, p, 14.0, Color(star["color"], 0.9), 15.0, 0.75)
				MapKit.set_glow(_land, land, p, 260.0, Color(oc, 0.09), 0.0, 0.0)
				land += 1
				MapKit.set_ring(_rings, rings, p, 21.0, Color(oc, 0.8))
				rings += 1
				if Galaxy.state_of(id) != "none":
					MapKit.set_ring(_rings, rings, p, 31.0, Color(MapIcons.ORANGE, 0.9), MapKit.TURNING, 2.0)
					rings += 1
				if id == Galaxy.current_system:
					MapKit.set_ring(_rings, rings, p, 52.0, Color(MapIcons.ORANGE, 1.0), MapKit.PULSE, 2.5)
					rings += 1
			else:
				MapKit.set_glow(_glow, n, p, 6.0, Color(0.7, 0.75, 0.85, 0.35), 7.0, 0.0)
				MapKit.set_ring(_rings, rings, p, 17.0, Color(NeonTheme.HEAD, 0.35), MapKit.RING, 1.2)
				rings += 1
			n += 1
		_glow.multimesh.visible_instance_count = n
		_land.multimesh.visible_instance_count = land
		_rings.multimesh.visible_instance_count = rings
		var L := MapKit.Lines.new()
		for l in Galaxy.LINKS:
			var a: String = l[0]
			var b: String = l[1]
			var ba := Galaxy.has_been(a)
			var bb := Galaxy.has_been(b)
			if not ba and not bb:
				continue
			var pa := at(a)
			var pb := at(b)
			if ba and bb:
				if _war(a, b):
					L.seg(pa, pb, Color(1.0, 0.3, 0.25, 0.85), 2.4, maxf(3.0, pa.distance_to(pb) / 18.0), 0.6)
				else:
					L.seg(pa, pb, Color(Galaxy.empire_color(Galaxy.owner_of(a)).lerp(NeonTheme.HEAD, 0.4), 0.6), 1.6, 0.0, 0.0,
						Color(Galaxy.empire_color(Galaxy.owner_of(b)).lerp(NeonTheme.HEAD, 0.4), 0.6))
			else:
				# A stub: from the system you know toward the one you don't, fading out.
				var from := pa if ba else pb
				var to := pb if ba else pa
				var mid := from.lerp(to, 0.7)
				L.seg(from, mid, Color(NeonTheme.HEAD, 0.45), 1.4, 0.0, 0.0, Color(NeonTheme.HEAD, 0.0))
		# Stems down to the galactic plane, and a ring where each stands over it.
		for id in shown:
			var p := at(id)
			var foot := Vector3(p.x, 0.0, p.z)
			var oc := Galaxy.empire_color(Galaxy.owner_of(id))
			L.seg(p, foot, Color(oc, 0.3), 1.0, 0.0, 0.0, Color(oc, 0.05))
			L.circle(foot, 9.0, Color(oc, 0.3), 1.0, 20)
		L.into(_lanes)

	## Your route: an orange line flowing along it.
	func _build_route() -> void:
		var sig := str(Galaxy.route)
		if sig == _route_sig:
			return
		_route_sig = sig
		var L := MapKit.Lines.new()
		var r: Array = Galaxy.route
		for i in r.size() - 1:
			var a := at(r[i])
			var b := at(r[i + 1])
			L.seg(a, b, Color(MapIcons.ORANGE, 0.95), 3.5, maxf(3.0, a.distance_to(b) / 14.0), 1.2)
		L.into(_route)

	func tick() -> void:
		_t += 1.0 / anim_hz
		_check_t -= 1.0 / anim_hz
		if _check_t <= 0.0:
			_check_t = 0.5   # (who owns what, the wars, the route: looked at twice a second)
			rebuild()
		if is_instance_valid(page) and page.trade:
			# (the search goes on ~1 ms a frame; the routes shown are the last it finished)
			var now: Array = TradeRoutes.galaxy_routes_spread(page.trade_item, 2, 10)
			if not is_same(now, page.routes):
				page._update_trade()

	func fit(now := false) -> void:
		var pts: Array = []
		for id in marks:
			pts.append(marks[id]["pos"])
		if pts.size() < 3:
			pts.append_array([at(Galaxy.current_system) + Vector3(-500, 0, -500), at(Galaxy.current_system) + Vector3(500, 0, 500)])
		fit_points(pts, now)

	func look_at_system(id: String) -> void:
		if marks.has(id):
			fly_to(at(id), minf(_dist_t, 700.0))

	func clicked(key: String, add: bool) -> void:
		if key == "" or not is_instance_valid(page):
			return
		if add:
			page.add_to_route(key)
		else:
			select(key)

	func accept() -> void:
		if is_instance_valid(page) and page.selected != "":
			page._plot_route()

	func cycle_order() -> Array:
		var here := at(Galaxy.current_system)
		var keys: Array = marks.keys()
		keys.sort_custom(func(a, b): return here.distance_squared_to(marks[a]["pos"]) < here.distance_squared_to(marks[b]["pos"]))
		return keys

	# --- The overlay -------------------------------------------------------------------

	func draw_overlay() -> void:
		var font := NeonTheme.heavy_font()
		var fs := Settings.fs("menu", 14)
		var small := maxi(Settings.MIN_FONT, fs - 2)
		var taken: Array = []
		var r: Array = Galaxy.route
		# Names: the selection, here, the route first; then the nearest to the camera.
		var cp := cam.global_position
		var order: Array = []
		for id in _lab:
			if at_screen(id) != null:
				order.append([-_rank(id, r), cp.distance_squared_to(marks[id]["pos"]), id])
		order.sort()
		for e in order:
			var id: String = e[2]
			var p: Vector2 = at_screen(id)
			var hi: bool = id == selected_key or id == hover_key
			if Galaxy.has_been(id):
				tag(p + Vector2(0, 30), _lab[id][0], fs if hi or id == Galaxy.current_system else small, Color.WHITE if hi else _lab[id][1], taken, font)
			else:
				draw_string(font, p + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(NeonTheme.HEAD, 0.75 if hi else 0.5))
				if hi or r.has(id):
					tag(p + Vector2(0, 26), "UNCHARTED", small, Color(NeonTheme.HEAD, 0.8), taken, font)
			if id == selected_key:
				for i in 4:
					var a := TAU * i / 4.0 + PI / 4.0
					draw_arc(p, 26.0, a - 0.35, a + 0.35, 6, Color(1, 1, 1, 0.9), 2.0, true)
		if is_instance_valid(page) and page.trade:
			_draw_trade(small)
		# The galaxy's name, top right; the legend, top left.
		var tfs := Settings.fs("menu", 22)
		draw_string(font, Vector2(0, tfs + 6), "NEW HELLAS", HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14, tfs, NeonTheme.HEAD)
		draw_string(font, Vector2(0, tfs + 10 + fs), "%d of %d star systems charted" % [Galaxy.been.size(), Galaxy.SYSTEMS.size()], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14, small, UI.TEXT_DIM)
		var y := float(fs) + 4.0
		for e in Galaxy.EMPIRES:
			draw_circle(Vector2(18, y - fs * 0.32), 5.0, Galaxy.empire_color(e))
			draw_string(font, Vector2(30, y), Galaxy.empire_name(e), HORIZONTAL_ALIGNMENT_LEFT, -1, small, NeonTheme.TEXT)
			y += small + 5.0

	func _rank(id: String, r: Array) -> int:
		if id == selected_key:
			return 4
		if id == Galaxy.current_system:
			return 3
		if r.has(id):
			return 2
		return 1 if Galaxy.has_been(id) else 0

	## The trade runs: along the gate lanes from where you buy to where you
	## sell, side by side where they share a lane, the best brightest.
	func _draw_trade(fs: int) -> void:
		var rs: Array = page.routes
		if rs.is_empty():
			return
		var top: float = rs[0]["profit"]
		var lanes := {}
		var taken := []
		var t := Time.get_ticks_msec() / 1000.0
		for r in rs:
			var path := Galaxy.find_route(r["from_sys"], r["to_sys"])
			if path.size() < 2 or not path.all(func(id): return at_screen(id) != null):
				continue   # (runs through systems you know, on the screen)
			var pts := PackedVector2Array()
			for i in path.size():
				var p: Vector2 = at_screen(path[i])
				var off := Vector2.ZERO
				if i < path.size() - 1:
					var key: String = path[i] + "|" + path[i + 1] if path[i] < path[i + 1] else path[i + 1] + "|" + path[i]
					var n: int = lanes.get(key, 0)
					lanes[key] = n + 1
					var dir: Vector2 = ((at_screen(path[i + 1]) as Vector2) - p).normalized()
					off = dir.orthogonal() * (n * 9.0 - 4.0)
				pts.append(p + off)
			pts[0] += (pts[1] - pts[0]).normalized() * 14.0
			pts[-1] -= (pts[-1] - pts[-2]).normalized() * 16.0
			TradeRoutes.draw_run(self, pts, r["profit"] / maxf(1.0, top), t)
			TradeRoutes.draw_tag(self, pts[0].lerp(pts[1], 0.5), TradeRoutes.tag_text(r), fs, taken)
