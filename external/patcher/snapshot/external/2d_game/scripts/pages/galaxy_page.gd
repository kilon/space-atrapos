extends HBoxContainer
## Ship Computer tab: the galaxy map. Star systems coloured by owner, gate
## lanes, empire territories, wars, system states and pirate activity.
## Click a system for details and to plot a route (your course is set to the
## first gate; after each jump the next gate is targeted); Shift + click adds
## a system to the end of the route (a waypoint). Right column:
## diplomacy (who is at war), your reputation and the galactic news feed.
## TRADE ROUTES (the button under the system info, or T): the map shows the
## best trade runs between systems (TradeRoutes.galaxy_routes - buy at one
## station, sell at a station up to two jumps away) as green arrows with their
## good and profit a unit, for every good or one; the right column lists them
## (click one to plot a route to where you buy).

var data: Node
var ship: Node2D

var _view: GalaxyView
var _info: RichTextLabel
var _diplo: RichTextLabel
var _news: RichTextLabel
var _plot: Button
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
	add_child(_view)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(UI.section("SYSTEM"))
	_info = _rich(150)
	col.add_child(_info)
	_plot = EditorIcons.dress(UI.button("", _plot_route, 15), "next", "", "Plot route")
	_plot.focus_mode = FOCUS_NONE
	col.add_child(_plot)
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
	_diplo = _rich(130)
	col.add_child(_diplo)
	var nh := UI.section("GALACTIC NEWS")
	col.add_child(nh)
	_news = _rich(170)
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
	if selected == "":
		selected = Galaxy.current_system
	_update_trade()
	_update_info()
	_update_diplo()
	var lines := []
	for n in Galaxy.news.slice(0, 25):
		var col: String = {"danger": "#ff7a6a", "good": "#7dffa0"}.get(n["kind"], "#c7d6ea")
		lines.append("[color=#6f8199]%s[/color]  [color=%s]%s[/color]" % [_clock(n["t"]), col, n["text"]])
	_news.text = "\n".join(lines) if not lines.is_empty() else "[color=#6f8199]No news yet.[/color]"
	_view.queue_redraw()
	_view._top_sig = ""   # (and its top: redrawn next frame)


func toggle_trade() -> void:
	trade = not trade
	refresh()


func _update_trade() -> void:
	_trade_btn.set_pressed_no_signal(trade)
	_trade_box.visible = trade
	for n in _plain_box:
		n.visible = not trade
	routes = TradeRoutes.galaxy_routes_spread(trade_item, 2, 10) if trade else []
	if not trade:
		return
	var lines := []
	for i in routes.size():
		var r: Dictionary = routes[i]
		lines.append("[url=%d][color=#7dffa0][b]+%d dr[/b][/color]  [color=#ffcf6a]%s[/color][/url]\n   %s (%s) › %s (%s)  ·  %d → %d dr  ·  %d jump%s" % [i, r["profit"],
			Items.display_name(r["item"]), TradeRoutes.station_name(r["from"]), TradeRoutes.system_name(r["from_sys"]),
			TradeRoutes.station_name(r["to"]), TradeRoutes.system_name(r["to_sys"]), r["buy"], r["sell"], r["jumps"], "" if r["jumps"] == 1 else "s"])
	_trade_text.text = "\n".join(lines) if not lines.is_empty() else "[color=#6f8199]No profitable runs you know of%s. Runs start at stations whose market you know - dock at them (or become Friendly with an empire: it shares all of its own) - and end at stations you've found.[/color]" % ("" if trade_item == "" else " for " + Items.display_name(trade_item))
	_trade_text.text += "\n\n[color=#6f8199]Click a run to plot a route to where you buy. Within one system, see the sector map's trade layer (M).[/color]"


## A run clicked in the list: plot a route to its start (or, there already, to its end).
func _on_route_clicked(meta) -> void:
	var i := int(str(meta))
	if i < 0 or i >= routes.size():
		return
	var r: Dictionary = routes[i]
	var to: String = r["from_sys"] if r["from_sys"] != Galaxy.current_system else r["to_sys"]
	selected = to
	Galaxy.route = Galaxy.find_route(Galaxy.current_system, to)
	if Galaxy.route.size() >= 2:
		if ship and ship.is_alive():
			ship.move_to(Galaxy.system(Galaxy.current_system)["gates"][Galaxy.route[1]])
		GameLog.post("Trade run: buy %s at %s, sell at %s (+%d dr a unit). Route plotted to %s." % [Items.display_name(r["item"]),
			TradeRoutes.station_name(r["from"]), TradeRoutes.station_name(r["to"]), r["profit"], TradeRoutes.system_name(to)], "mission")
	refresh()


func _clock(t: float) -> String:
	return "%02d:%02d" % [int(t / 60.0), int(t) % 60]


func select(id: String) -> void:
	selected = id
	refresh()


func _update_info() -> void:
	var sys: Dictionary = Galaxy.system(selected)
	if sys.is_empty():
		return
	var owner: String = sys["owner"]
	var col: String = Galaxy.empire_color(owner).to_html(false)
	var path := Galaxy.find_route(Galaxy.current_system, selected)
	var t := "[b][font_size=20]%s[/font_size][/b]   [color=#%s]%s[/color]\n" % [sys["name"].to_upper(), col, Galaxy.empire_name(owner)]
	var n_moons: int = 1 if selected == Galaxy.HOME else sys["planets"].filter(func(pl): return pl["moon_of"] != "").size()
	var n_planets: int = (Planets.PLANETS.size() - 1) if selected == Galaxy.HOME else sys["planets"].size() - n_moons
	t += "The star %s (%s)  ·  %d planet%s%s  ·  %d stations\n" % [sys["name"], Galaxy.STARS[sys["star"]]["name"].to_lower(), n_planets,
		"" if n_planets == 1 else "s", ("  ·  %d moon%s" % [n_moons, "" if n_moons == 1 else "s"]) if n_moons > 0 else "", sys["stations"].size()]
	var st: String = Galaxy.state_of(selected)
	if st != "none":
		t += "State: [color=#ffcf6a]%s[/color] - %s\n" % [Galaxy.STATES[st]["name"], Galaxy.STATES[st]["desc"]]
	var danger: float = sys["pirates"]
	t += "Pirate activity: %s\n" % ["low", "moderate", "high", "extreme"][clampi(int(danger * 3.99), 0, 3)]
	var econs := []
	for sid in sys["stations"]:
		var e := Galaxy.station_owner(sid)
		var pres := Galaxy.presence_label(Galaxy.station_presence(sid))
		econs.append("%s (%s%s)" % [Galaxy.stations[sid]["name"], Galaxy.ECONOMIES[Galaxy.stations[sid]["economy"]]["name"].to_lower(),
			(", [color=#%s]%s[/color]" % [Galaxy.empire_color(e).to_html(false), pres if e == "independent" else "%s %s" % [Galaxy.EMPIRES[e]["short"], pres]]) if pres != "" else ""])
	t += "Stations: " + ", ".join(econs) + "\n"
	if selected == Galaxy.current_system:
		t += "[color=#7dd8ff]You are here.[/color]"
	elif path.is_empty():
		t += "[color=#ff7a6a]No route.[/color]"
	else:
		t += "Route: %s  (%d jumps)" % [" › ".join(path.map(func(p): return Galaxy.SYSTEMS[p]["name"])), path.size() - 1]
	_info.text = t
	_plot.disabled = selected == Galaxy.current_system or path.is_empty()
	var clearing: bool = not Galaxy.route.is_empty() and Galaxy.route[-1] == selected
	_plot.icon = EditorIcons.get_icon("abandon" if clearing else "next")
	_plot.text = "Clear" if clearing else "Plot route"
	_plot.tooltip_text = EditorIcons.tip("Clear route" if clearing else "Plot route to %s" % sys["name"], "",
		"Removes the route to %s: the HUD stops pointing the way." % sys["name"] if clearing else
		"Plans the shortest way through the jump gates to %s. The HUD then points you to each gate in turn.\nUnavailable for the system you're in, or when no gates lead there." % sys["name"])


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


## Shift + click: the route goes on from where it ends now (or from here)
## to this system - a waypoint; plain Plot route replaces it.
func add_to_route(id: String) -> void:
	var start: String = Galaxy.route[-1] if not Galaxy.route.is_empty() else Galaxy.current_system
	selected = id
	if start == id:
		refresh()
		return
	var leg := Galaxy.find_route(start, id)
	if leg.is_empty():
		GameLog.post("No route from %s to %s." % [Galaxy.SYSTEMS[start]["name"], Galaxy.SYSTEMS[id]["name"]], "danger")
		refresh()
		return
	var was_empty := Galaxy.route.is_empty()
	if was_empty:
		Galaxy.route = leg
	else:
		Galaxy.route = Galaxy.route + leg.slice(1)
	if was_empty and Galaxy.route.size() >= 2 and ship and ship.is_alive():
		ship.move_to(Galaxy.system(Galaxy.current_system)["gates"][Galaxy.route[1]])
	GameLog.post("Waypoint: %s added to the route (%d jumps in all)." % [Galaxy.SYSTEMS[id]["name"], Galaxy.route.size() - 1], "mission")
	refresh()


func _plot_route() -> void:
	if not Galaxy.route.is_empty() and Galaxy.route[-1] == selected:
		Galaxy.route = []
		GameLog.post("Route cleared", "info")
	else:
		Galaxy.route = Galaxy.find_route(Galaxy.current_system, selected)
		if Galaxy.route.size() >= 2:
			var gate: Vector2 = Galaxy.system(Galaxy.current_system)["gates"][Galaxy.route[1]]
			if ship and ship.is_alive():
				ship.move_to(gate)
			GameLog.post("Route plotted to %s: %d jumps. Course set to the %s gate." % [Galaxy.SYSTEMS[selected]["name"], Galaxy.route.size() - 1, Galaxy.SYSTEMS[Galaxy.route[1]]["name"]], "mission")
	refresh()


class GalaxyView extends Control:
	var page: Node
	var _hover := ""
	var _t := 0.0
	var _back: Control            # the still part (console grid, stars, territories), behind
	var _back_sig := ""           # what it was drawn for
	var _top: Control             # the systems' badges and names, the route, the legend, on top
	var _top_sig := ""
	var _xf_cache := Transform2D()
	var _xf_size := Vector2(-1, -1)
	## The still layers are drawn into two off-screen pictures (SubViewports,
	## rendered once each time what they show changes) and the view draws those
	## two textures: a galaxy of 58 systems is ~1,100 vector draw calls (badges,
	## names, lanes) - every frame, they cost more than the rest of the game.
	var _svp_back: SubViewport
	var _svp_top: SubViewport

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true
		_svp_back = _layer(false)
		_back = _svp_back.get_child(0)
		_back.draw.connect(_draw_back)
		_svp_top = _layer(true)
		_top = _svp_top.get_child(0)
		_top.draw.connect(_draw_top)

	func _layer(transparent: bool) -> SubViewport:
		var v := SubViewport.new()
		v.transparent_bg = transparent
		v.disable_3d = true
		v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		v.size = Vector2i(8, 8)
		var c := Control.new()
		c.mouse_filter = MOUSE_FILTER_IGNORE
		v.add_child(c)
		add_child(v)
		return v

	## Redraws a still layer's picture (at the view's size).
	func _refresh_layer(v: SubViewport) -> void:
		var sz := Vector2i(maxi(8, int(size.x)), maxi(8, int(size.y)))
		if v.size != sz:
			v.size = sz
		var c: Control = v.get_child(0)
		c.size = Vector2(sz)
		c.queue_redraw()
		v.render_target_update_mode = SubViewport.UPDATE_ONCE

	## (Redrawn every frame for the pulses; the still back only when its size or
	## the territories change - all of it every frame was half the frame.)
	var _owners_t := 0.0
	var _owners_sig := ""

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return   # (another tab: nothing to draw)
		_t += delta
		if UI.redraw_due(self):   # (60 pictures a second - every frame at 600 FPS was ten times that)
			queue_redraw()
		if page.trade and is_visible_in_tree():
			# (every frame: the search goes on ~1 ms a frame, and the routes
			# shown are the last it finished - prices move every 2 s)
			var now: Array = TradeRoutes.galaxy_routes_spread(page.trade_item, 2, 10)
			if not is_same(now, page.routes):
				page._update_trade()   # (a search finished: the list beside the map too)
		# (who owns what: looked at twice a second, not every frame - a string
		# of 58 owners made each frame)
		_owners_t -= delta
		if _owners_t <= 0.0 or _owners_sig == "":
			_owners_t = 0.5
			_owners_sig = str(Galaxy.SYSTEMS.keys().map(func(id): return Galaxy.owner_of(id)))
		var sig := str(size) + _owners_sig
		if sig != _back_sig:
			_back_sig = sig
			_refresh_layer(_svp_back)
		var top := sig + str([_hover, page.selected, Galaxy.route, Settings.fs("menu", 15), page.trade])
		if top != _top_sig:
			_top_sig = top
			_refresh_layer(_svp_top)

	## Fits every system (plus a margin for names) into the page.
	func _xf() -> Transform2D:
		if size == _xf_size:
			return _xf_cache
		_xf_size = size
		_xf_cache = _fit()
		return _xf_cache

	func _fit() -> Transform2D:
		var box := Rect2(Galaxy.SYSTEMS.values()[0]["pos"], Vector2.ZERO)
		for id in Galaxy.SYSTEMS:
			box = box.expand(Galaxy.SYSTEMS[id]["pos"])
		box = box.grow(80.0)
		var k := minf(size.x / box.size.x, size.y / box.size.y)
		return Transform2D(0.0, Vector2(k, k), 0.0, (size - box.size * k) / 2.0 - box.position * k)

	func _pos(id: String) -> Vector2:
		return _xf() * Galaxy.SYSTEMS[id]["pos"]

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion:
			_hover = _pick(ev.position)
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var id := _pick(ev.position)
			if id != "" and ev.shift_pressed:
				page.add_to_route(id)
			elif id != "":
				page.select(id)
			accept_event()

	func _pick(at: Vector2) -> String:
		for id in Galaxy.SYSTEMS:
			if _pos(id).distance_to(at) < 22.0:
				return id
		return ""

	## The still back: the console grid, faint stars, the territories.
	func _draw_back() -> void:
		var ci := _back
		ci.draw_rect(Rect2(Vector2.ZERO, size), NeonTheme.BG)
		var gc := Color(NeonTheme.HEAD, 0.06)   # the console grid
		for gx in range(0, int(size.x), 48):
			ci.draw_line(Vector2(gx, 0), Vector2(gx, size.y), gc, 1.0)
		for gy in range(0, int(size.y), 48):
			ci.draw_line(Vector2(0, gy), Vector2(size.x, gy), gc, 1.0)
		# Faint background stars and the territories (soft discs in the owner's
		# colour): one texture (ExhaustTrail.disc), so they batch into a draw
		# call or two instead of one each (a galaxy of 58 systems: hundreds).
		var disc := ExhaustTrail.disc()
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 220:
			var r := rng.randf_range(0.5, 1.4)
			var at := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			ci.draw_texture_rect(disc, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, rng.randf_range(0.1, 0.45)))
		var k_ := _xf().get_scale().x
		for id in Galaxy.SYSTEMS:
			var c := Galaxy.empire_color(Galaxy.owner_of(id))
			for k in 4:
				var r := (70.0 - k * 14.0) * clampf(k_ * 1.6, 0.5, 1.0)
				ci.draw_texture_rect(disc, Rect2(_pos(id) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c, 0.035))
		# Gate lanes at peace, dotted - every dash of every lane in one draw
		# call (the war fronts pulse: drawn every frame).
		var dashes := PackedVector2Array()
		for l in Galaxy.LINKS:
			if _war(l):
				continue
			var a := _pos(l[0])
			var b := _pos(l[1])
			var n := maxi(2, int(a.distance_to(b) / 9.0))
			for i in range(0, n, 2):
				dashes.append(a.lerp(b, float(i) / n))
				dashes.append(a.lerp(b, float(i + 1) / n))
		if not dashes.is_empty():
			ci.draw_multiline(dashes, Color(NeonTheme.HEAD, 0.47), 1.5)

	## Every frame: the war fronts' pulse, the system states' turning arcs, your
	## system's pulse (between the still back and the top).
	func _draw() -> void:
		draw_texture(_svp_back.get_texture(), Vector2.ZERO)   # (the still back: its picture)
		for l in Galaxy.LINKS:
			if _war(l):
				MapIcons.route(self, _pos(l[0]), _pos(l[1]), Color(1.0, 0.3, 0.25, 0.55 + 0.25 * sin(_t * 3.0)), 0.0, true, 3.0)
		for id in Galaxy.SYSTEMS:
			var p := _pos(id)
			if Galaxy.state_of(id) != "none":
				draw_arc(p, 21.0, _t, _t + 4.5, 24, Color(MapIcons.ORANGE, 0.85), 2.0, true)
			if id == Galaxy.current_system:
				var pulse := 25.0 + 3.0 * sin(_t * 4.0)
				draw_arc(p, pulse, 0, TAU, 40, MapIcons.ORANGE, 2.5, true)
				draw_arc(p, pulse + 5.0, 0, TAU, 40, Color(MapIcons.ORANGE, 0.3), 4.0, true)
		if page.trade:
			_draw_trade()
		draw_texture(_svp_top.get_texture(), Vector2.ZERO)   # (the badges, names, route, legend: their picture, on top)

	## The trade runs: along the gate lanes from where you buy to where you
	## sell, side by side where they share a lane, the best brightest.
	func _draw_trade() -> void:
		var rs: Array = page.routes
		if rs.is_empty():
			return
		var top: float = rs[0]["profit"]
		var lanes := {}   # lane key -> runs drawn on it so far (to set them side by side)
		var fs := Settings.fs("menu", 13)
		var taken := []
		for id in Galaxy.SYSTEMS:   # (the systems' names: tags keep clear of them)
			taken.append(Rect2(_pos(id) + Vector2(-60, 26), Vector2(120, 20)))
		for r in rs:
			var path := Galaxy.find_route(r["from_sys"], r["to_sys"])
			if path.size() < 2:
				continue
			var pts := PackedVector2Array()
			for i in path.size():
				var p := _pos(path[i])
				var off := Vector2.ZERO
				if i < path.size() - 1:
					var key: String = path[i] + "|" + path[i + 1] if path[i] < path[i + 1] else path[i + 1] + "|" + path[i]
					var n: int = lanes.get(key, 0)
					lanes[key] = n + 1
					var dir := (_pos(path[i + 1]) - p).normalized()
					off = dir.orthogonal() * (n * 9.0 - 4.0)
				pts.append(p + off)
			# Start and end clear of the system badges.
			pts[0] += (pts[1] - pts[0]).normalized() * 22.0
			pts[-1] -= (pts[-1] - pts[-2]).normalized() * 24.0
			TradeRoutes.draw_run(self, pts, r["profit"] / maxf(1.0, top), _t)
			TradeRoutes.draw_tag(self, pts[0].lerp(pts[1], 0.5), TradeRoutes.tag_text(r), fs, taken)

	func _war(l: Array) -> bool:
		return Galaxy.at_war(Galaxy.owner_of(l[0]), Galaxy.owner_of(l[1])) and Galaxy.owner_of(l[0]) != Galaxy.owner_of(l[1])

	## The top (redrawn when what it shows changes): the planned route, the
	## systems' badges and names, the legend.
	func _draw_top() -> void:
		var ci := _top
		var font := NeonTheme.heavy_font()
		var fs := Settings.fs("menu", 15)
		var r: Array = Galaxy.route
		for i in r.size() - 1:
			MapIcons.route(ci, _pos(r[i]), _pos(r[i + 1]), MapIcons.ORANGE, 0.0, false, 3.0)
		for id in Galaxy.SYSTEMS:
			var p := _pos(id)
			var star: Dictionary = Galaxy.STARS[Galaxy.SYSTEMS[id]["star"]]
			var oc := Galaxy.empire_color(Galaxy.owner_of(id))
			# A circled star in the console's style; the ring in the owner's colour.
			MapIcons.badge(ci, p, 15.0, oc.lerp(MapIcons.CYAN, 0.25), "star")
			ci.draw_circle(p, 3.5, star["color"])
			if id == page.selected:
				ci.draw_arc(p, 33.0, 0, TAU, 32, Color(1, 1, 1, 0.8), 1.5, true)
			var label: String = Galaxy.SYSTEMS[id]["name"].to_upper()
			ci.draw_string_outline(font, p + Vector2(-80, 40), label, HORIZONTAL_ALIGNMENT_CENTER, 160, fs, 4, Color(0, 0, 0, 0.9))
			ci.draw_string(font, p + Vector2(-80, 40), label, HORIZONTAL_ALIGNMENT_CENTER, 160, fs, oc.lightened(0.45) if id != _hover else Color.WHITE)
		# The galaxy's name, top right.
		var tfs := Settings.fs("menu", 22)
		ci.draw_string(NeonTheme.heavy_font(), Vector2(0, tfs + 6), "NEW HELLAS", HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14, tfs, NeonTheme.HEAD)
		ci.draw_string(font, Vector2(0, tfs + 10 + fs), "%d star systems" % Galaxy.systems.size(), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14, fs, UI.TEXT_DIM)
		# Legend (a row per empire, spaced by the text size).
		var y := float(fs) + 4.0
		for e in Galaxy.EMPIRES:
			ci.draw_circle(Vector2(18, y - fs * 0.32), 5.0, Galaxy.empire_color(e))
			ci.draw_string(font, Vector2(30, y), Galaxy.empire_name(e), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NeonTheme.TEXT)
			y += fs + 4.0
		ci.draw_string(font, Vector2(14, size.y - 12), "orange ring: you  ·  orange arc: system state  ·  red lane: war front  ·  Shift + click: add to the route" + ("  ·  green: trade run (good, profit a unit)" if page.trade else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(Settings.MIN_FONT, fs - 1), NeonTheme.HEAD)
