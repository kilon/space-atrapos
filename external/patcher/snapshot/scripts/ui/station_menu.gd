extends Control
## Station facilities, shown while docked (game paused). Tabs:
## Workshop (component upgrades, fuel; shields recharge free on docking), Buy
## (ammo, equipment), Sell (cargo market) and Missions (job board + active jobs).

const SUPPLIES := [["missile", 5], ["energy_drink", 3]]  # [item id, amount per purchase]
const OUTFITTING := ["plasma_cannon", "missile_launcher", "afterburner", "shield_booster"]
const TABS := ["WORKSHOP", "MARKET", "OUTFITTING", "SHIPYARD", "DESIGNER", "SELL", "REPUTATION", "MAIN QUESTS", "MISSIONS"]
## The services by their own names - each its own panel, opened at its terminal in the port (`single`).
const SERVICES := ["Workshop", "Market", "Outfitting", "Shipyard", "Designer", "Salvage", "Reputation", "Main quests", "Missions"]
## One service at a time - a terminal's (the 3D game's port: CosmosHangar.TERMINALS): no tabs to
## the others, no keys to switch; Esc / Close steps away from the terminal, docked still.
var single := true

var data: Node
var ship: Node2D
var missions: Node
var quest: Node
var station: Node2D

var current := 0
var _subtitle: Label
var _dockmaster: Portrait
var _title: Label
var _credits: Label
var _bar: HBoxContainer
var _content: VBoxContainer
var _panel_style: StyleBox
var _built := false


func _ready() -> void:
	hide()
	set_anchors_preset(PRESET_FULL_RECT)
	Keybinds.register_menu(self)   # (WASD / D-pad move the focus; Q / E or LB / RB switch tabs)


func cycle_tab(d: int) -> void:
	if single:
		return
	show_tab(wrapi(current + d, 0, TABS.size()))


func open(st: Node2D) -> void:
	if not _built:
		_build()
	station = st
	show()
	ship.invulnerable = true   # (docked: a safe zone - the game goes on round you)
	ship.recharge_shields()  # free service on docking
	_title.text = st.station_name.to_upper()
	_dockmaster.setup(st.station_name + "-dockmaster", st.empire)
	_dockmaster.tooltip_text = "%s, dockmaster" % _dockmaster.person_name
	var rec: Dictionary = Galaxy.stations.get(st.station_id, {})
	if not rec.is_empty():
		var pres := Galaxy.presence_label(Galaxy.station_presence(st.station_id))
		var hp := Galaxy.station_health(st.station_id)
		_subtitle.text = "%s  ·  %s%s  ·  your standing: %s  ·  condition %d%%%s  ·  docked" % [Galaxy.ECONOMIES[rec["economy"]]["name"], Galaxy.empire_name(st.empire),
			(" (" + pres + ")") if pres != "" else "", Galaxy.standing(st.empire), int(hp), "  ·  BURNING" if hp < Galaxy.DAMAGED else ""]
	# The station's empire shows in the bracket corners; the rest is the theme's.
	_title.add_theme_color_override("font_color", NeonTheme.HEAD)
	_panel_style.set("accent", st.accent)
	show_tab(0)


## Emitted when you undock (the menu closes).
signal undocked(station: Node2D)


func close() -> void:
	var was_open := visible
	if visible and station and not single:
		GameLog.post("Undocked from %s" % station.station_name, "mission")
	hide()
	if was_open and is_instance_valid(ship):
		ship.invulnerable = false
	if was_open and station:
		undocked.emit(station)


func show_tab(index: int) -> void:
	current = index
	UI.select_tab(_bar, index)
	_bar.visible = not single
	if single and station:
		_title.text = "%s  ·  %s" % [station.station_name.to_upper(), SERVICES[index].to_upper()]
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return  # the Esc menu on top handles input
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var mp := market_page() if current == 1 else null
	if Keybinds.pressed(event, "undock"):
		close()   # (first: Shift+D isn't the market's D)
	elif mp and mp.handle_key(event):
		pass
	elif event.is_action_pressed("ui_cancel"):
		close()   # (Esc leaves the menu - undocks, as the Undock button)
	elif key and event.keycode >= KEY_1 and event.keycode <= KEY_9 and not single:
		show_tab(event.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()


func _build() -> void:
	_built = true
	var root := UI.modal(self, NeonTheme.HEAD, Vector2.ZERO, true)
	_panel_style = root.get_parent().get_parent().get_theme_stylebox("panel")

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	_dockmaster = Portrait.new()
	_dockmaster.custom_minimum_size = Vector2(84, 100)
	header.add_child(_dockmaster)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	_title = UI.label("STATION", 30)
	titles.add_child(_title)
	_subtitle = UI.label("Docked  ·  shields recharged  ·  safe zone", 14, UI.TEXT_DIM)
	titles.add_child(_subtitle)
	header.add_child(titles)
	header.add_child(UI.spacer())
	_credits = UI.label("", 22, UI.GOLD)
	header.add_child(_credits)
	root.add_child(header)

	_bar = UI.tab_bar(TABS, show_tab)
	var tab_info := [["repair", "Upgrade your ship's and your automaton's parts, and refuel (shields recharge for free when you dock)."],
		["buy", "Buy and sell trade goods. Prices follow each station's supply: buy where goods are made, sell where they're needed."],
		["rating", "Fit weapons, utility systems and modules (ratings E to A), and buy missiles."],
		["ship", "Buy a new ship class; your current ship is traded in."],
		["paint", "Repaint your ship: hue, saturation, brightness and a tint, or a ready-made skin."],
		["sell", "Sell cargo and loot at this station's prices."],
		["pledge", "Who runs this station, and your reputation with every empire and the independents: what it does for you and how it moves."],
		["quest", "The main story campaign, The Thread of Ariadne."],
		["accept", "Missions offered here (greyed out: the empire doesn't trust you enough yet), and your active ones (turn them in or abandon them)."]]
	for i in _bar.get_child_count():
		EditorIcons.dress_tab(_bar.get_child(i), tab_info[i][0], EditorIcons.tip(TABS[i].capitalize(), str(i + 1), tab_info[i][1]))
	root.add_child(_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	# (sideways too: at a big text size a page may be wider than the window -
	# it scrolls rather than pushing the window past the screen's edge)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true   # (keys / pad moving the focus scroll the page)
	root.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 18)   # clear of the scrollbar
	scroll.add_child(pad)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	pad.add_child(_content)

	var footer := HBoxContainer.new()
	var keys := UI.label("", 14, UI.TEXT_DIM)
	_keys_hint = keys
	_update_keys_hint()
	Keybinds.changed.connect(_update_keys_hint)   # (rebound in Settings: the hint follows)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (big text: wraps, never wider than the window)
	keys.size_flags_horizontal = SIZE_EXPAND_FILL
	keys.custom_minimum_size.x = 200
	footer.add_child(keys)
	footer.add_child(EditorIcons.docs_button(self, "stations", EditorDocs.GAME))
	if single:
		footer.add_child(EditorIcons.dress(UI.button("Close", close, 18), "undock", EditorIcons.tip("Close", "Esc", "Steps away from the terminal - you're still docked.")))
	else:
		footer.add_child(EditorIcons.dress(UI.button("Undock", close, 18), "undock", EditorIcons.tip("Undock", Keybinds.keys_text("undock") + " / Esc", "Leaves the station and returns to space, next to it.\nYour purchases, upgrades and accepted quests are kept; the station's safe zone protects you for a moment.")))
	root.add_child(footer)

	data.changed.connect(_refresh_soon)   # (once at the end of the frame, however many changes)
	missions.changed.connect(_refresh_soon)
	Settings.text_scale_changed.connect(refresh)


var _keys_hint: Label

func _update_keys_hint() -> void:
	if single:
		_keys_hint.text = "WASD / arrows / D-pad move  ·  Esc to step away  ·  F1 pilot's guide  ·  hover any icon for help (keep hovering to pin it)"
		return
	_keys_hint.text = "1-9 or %s / %s switch tabs  ·  WASD / arrows / D-pad move  ·  %s to undock  ·  F1 pilot's guide  ·  hover any icon for help (keep hovering to pin it)" % [
		Keybinds.keys_text("menu_tab_prev").get_slice(" /", 0), Keybinds.keys_text("menu_tab_next").get_slice(" /", 0), Keybinds.keys_text("undock").get_slice(" /", 0)]


## Asks for one refresh at the end of the frame. Selling all cargo changes the
## hold once per good: a whole rebuild of the page each time (dozens, in one
## click, from inside the clicked button's own signal) overflowed Godot's
## message queue and crashed the game - now it's one rebuild.
var _refresh_queued := false

func _refresh_soon() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func():
		_refresh_queued = false
		refresh()).call_deferred()


func refresh() -> void:
	if not visible:
		return
	_credits.text = "%s drachmas" % UI.money(data.credits)
	UI.clear(_content)
	match current:
		0: _page_workshop()
		1:
			_page_market()
			# (the market's keys pick goods: a focused button would take the arrows / Enter)
			var f := get_viewport().gui_get_focus_owner()
			if f and is_ancestor_of(f):
				f.release_focus()
		2: _page_buy()
		3: _page_shipyard()
		4: _page_designer()
		5: _page_sell()
		6: _page_empire()
		7: _page_main_quests()
		8: _page_missions()
	UI.scale_fonts(self, "menu")
	UI.scale_fonts(_bar, "menu", 1.5)
	UI.scale_fonts(_title.get_parent().get_parent(), "menu", 1.5)  # header row


# --- Reputation (the station's owner, your standing with everyone) -------------------------------------------------------------

func _page_empire() -> void:
	var e: String = station.empire
	var sid: String = station.station_id
	var col := Galaxy.empire_color(e)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	var liaison := Portrait.new().setup(station.station_name + "-liaison", e)
	liaison.custom_minimum_size = Vector2(120, 144)
	top_row.add_child(liaison)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = SIZE_EXPAND_FILL
	tcol.add_child(UI.label(Galaxy.empire_name(e).to_upper(), 24, col.lightened(0.2)))
	var presence := Galaxy.presence_label(Galaxy.station_presence(sid))
	tcol.add_child(UI.label("%s, liaison (%s)  ·  this station: %s" % [liaison.person_name, liaison.species_name(),
		("an " + presence) if presence.begins_with("a") or presence.begins_with("i") else (("a " + presence) if presence != "" else "a %s station" % Galaxy.EMPIRES.get(e, {}).get("short", "local"))], 14, UI.TEXT_DIM))
	var d := UI.label(Galaxy.EMPIRES.get(e, {}).get("desc", ""), 14, UI.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tcol.add_child(d)
	top_row.add_child(tcol)
	_content.add_child(top_row)
	var sys: Dictionary = Galaxy.system(Galaxy.current_system)
	var o: String = sys["owner"]
	var ctl := UI.label("%s holds %s  ·  control %d%%%s" % [Galaxy.empire_name(o), sys["name"], int(sys.get("control", 60.0)),
		("  ·  under attack by: " + ", ".join(Galaxy.guests_in(Galaxy.current_system).filter(func(g): return Galaxy.station_presence(g) == "forward").map(func(g): return Galaxy.EMPIRES[Galaxy.station_owner(g)]["short"]))) if Galaxy.guests_in(Galaxy.current_system).any(func(g): return Galaxy.station_presence(g) == "forward") else ""], 15)
	_content.add_child(ctl)
	# Your standing with everyone.
	_content.add_child(UI.section("YOUR REPUTATION"))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	for who in Galaxy.MAJOR + ["independent"]:
		var v: float = Galaxy.reputation.get(who, 0.0)
		var tier := Galaxy.standing(who)
		var name := UI.label(Galaxy.empire_name(who), 16, Galaxy.empire_color(who).lightened(0.25))
		name.custom_minimum_size.x = 230
		g.add_child(name)
		g.add_child(_rep_bar(v))
		var tl := UI.label("%s  %+d" % [tier, roundi(v)], 16, _tier_color(tier))
		tl.custom_minimum_size.x = 150
		g.add_child(tl)
		var px: Array = Galaxy.REP_PRICES.get(tier, [1.0, 1.0])
		var eff := []
		if tier == "Hostile":
			eff.append("warships attack, docking refused")
		if px[0] != 1.0:
			eff.append("prices %+d%%" % roundi((px[0] - 1.0) * 100))
		if Galaxy.REP_BOUNTY.has(tier):
			eff.append("bounties +%d%%" % roundi((Galaxy.REP_BOUNTY[tier] - 1.0) * 100))
		g.add_child(UI.label("  ·  ".join(eff), 14, UI.TEXT_DIM))
		if who == e:
			name.text = "› " + name.text
	_content.add_child(g)
	var how := UI.label("Reputation rises slowly when you work and trade with them: missions at their stations, buying and selling there (every 10,000 dr traded: +1), and hunting the Sea Peoples in their space. It falls when you attack their ships - a little for the first shot at one, more for each one destroyed (shooting down a civilian in someone's space annoys its owner too) - and a bad name fades back toward Neutral over time. Tiers: Hostile (below -50), Unfriendly, Neutral (-15 to 15), Cordial, Friendly (40), Allied (70). Better standing opens the better missions (Trusted, Honoured) and better prices.", 14, UI.TEXT_DIM)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(how)


## A -100..100 bar, centred, red to the left and green to the right.
func _rep_bar(v: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(260, 16)
	c.size_flags_vertical = SIZE_SHRINK_CENTER
	c.draw.connect(func():
		var w := c.size.x
		var h := c.size.y
		c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))
		var mid := w / 2.0
		var x := mid + w / 2.0 * clampf(v / 100.0, -1.0, 1.0)
		c.draw_rect(Rect2(minf(mid, x), 2, absf(x - mid), h - 4), Color(0.4, 1.0, 0.5) if v >= 0.0 else Color(1.0, 0.4, 0.3))
		for t in Galaxy.REP_TIERS:
			var tx: float = mid + w / 2.0 * float(t[1]) / 100.0
			c.draw_line(Vector2(tx, 0), Vector2(tx, h), Color(1, 1, 1, 0.25), 1.0)
		c.draw_line(Vector2(mid, -2), Vector2(mid, h + 2), Color(1, 1, 1, 0.7), 1.0)
		c.draw_rect(Rect2(0, 0, w, h), Color(NeonTheme.CYAN, 0.5), false, 1.0))
	return c


static func _tier_color(tier: String) -> Color:
	return {"Hostile": Color(1.0, 0.35, 0.3), "Unfriendly": Color(1.0, 0.6, 0.35), "Neutral": Color(0.85, 0.85, 0.85),
		"Cordial": Color(0.7, 1.0, 0.7), "Friendly": Color(0.45, 1.0, 0.55), "Allied": Color(0.35, 1.0, 0.85)}.get(tier, Color.WHITE)


# --- Market ----------------------------------------------------------------------

func _page_market() -> void:
	var sid: String = station.station_id
	if not Galaxy.stations.has(sid):
		_content.add_child(UI.label("This station has no market.", 16, UI.TEXT_DIM))
		return
	var rec: Dictionary = Galaxy.stations[sid]
	var econ: Dictionary = Galaxy.ECONOMIES[rec["economy"]]
	var head := HBoxContainer.new()
	head.add_child(UI.section("COMMODITIES MARKET  ·  %s" % econ["name"].to_upper()))
	head.add_child(UI.spacer())
	var st_state: String = Galaxy.state_of(rec["system"])
	if st_state != "none":
		var sl := UI.label("%s  " % Galaxy.STATES[st_state]["name"].to_upper(), 14, UI.GOLD)
		sl.tooltip_text = Galaxy.STATES[st_state]["desc"]
		sl.mouse_filter = MOUSE_FILTER_STOP
		head.add_child(sl)
	var eff: float = rec.get("efficiency", 1.0)
	if eff < 0.7:
		var inputs := ", ".join(Galaxy.INPUTS.get(rec["economy"], []).map(func(c): return Items.display_name(c)))
		head.add_child(UI.label("Production %d%%: short of %s  " % [roundi(eff * 100), inputs], 14, Color(1.0, 0.6, 0.45)))
	head.add_child(UI.label("W/S select  ·  A/D quantity  ·  Enter buy  ·  Backspace sell", 13, UI.TEXT_DIM))
	_content.add_child(head)
	var page := MarketPage.new()
	page.setup(self)
	_content.add_child(page)


## The market page while it shows (null otherwise).
func market_page() -> Node:
	for c in _content.get_children():
		if c is MarketPage and not c.is_queued_for_deletion():
			return c
	return null


# --- Workshop --------------------------------------------------------------------

## The WORKSHOP tab: component UPGRADES (Upgrades) and FUEL.
const WORKSHOP_PAGES := ["UPGRADES", "FUEL"]
var _workshop_page := 0
var _up_body := "ship"
var _up_part := ""


func _page_workshop() -> void:
	_content.add_child(_sub_tabs(WORKSHOP_PAGES, _workshop_page, func(i):
		_workshop_page = i
		refresh()))
	match _workshop_page:
		0:
			_page_upgrades()
		1:
			_page_fuel()


## Component upgrades: a body's parts (tabs), each part's stats with their
## level, what they give and the next level's price.
func _page_upgrades() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	for w in ["ship", "automaton"]:
		var b := UI.button(Parts.BODIES[w]["name"].to_upper(), func():
			_up_body = w
			_up_part = ""
			refresh(), 15)
		b.toggle_mode = true
		b.button_pressed = w == _up_body
		b.tooltip_text = "Upgrades for your ship's parts: hull, engines, systems." if w == "ship" else "Upgrades for your automaton's parts: its body, limbs and systems."
		b.custom_minimum_size = Vector2(160, 36)
		top.add_child(b)
	top.add_child(UI.note("Every part carries stats you can raise, %d levels each. Upgrade Kits made by your ship's fabricator fit them too." % Upgrades.MAX_LEVEL, 14, 900))
	_content.add_child(top)
	var parts: Array = Upgrades.STATS[_up_body].keys()
	if not _up_part in parts:
		_up_part = parts[0]
	_content.add_child(_sub_tabs(parts.map(func(p): return Parts.info(_up_body, p)["name"]), parts.find(_up_part), func(i):
		_up_part = parts[i]
		refresh()))
	_content.add_child(UI.label(Parts.info(_up_body, _up_part)["name"], 16, UI.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for st in Upgrades.list(_up_body):
		if st["part"] != _up_part:
			continue
		var lvl := Upgrades.level(data.upgrades, _up_body, st["id"])
		var price := Upgrades.price(_up_body, st["id"], lvl)
		var card := PanelContainer.new()
		UI.light_panel(card)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		card.add_child(v)
		var h := HBoxContainer.new()
		var nm := UI.label(st["name"], 17, Color.WHITE)
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(UI.label("level %d / %d" % [lvl, Upgrades.MAX_LEVEL], 15, UI.GOLD if lvl > 0 else UI.TEXT_DIM))
		v.add_child(h)
		var pips := HBoxContainer.new()
		for k in Upgrades.MAX_LEVEL:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(34, 8)
			pip.color = NeonTheme.HEAD if k < lvl else Color(1, 1, 1, 0.12)
			pips.add_child(pip)
		v.add_child(pips)
		v.add_child(UI.label("now %s  ·  next level %s" % [Upgrades.words(st, float(st["per"]) * lvl), Upgrades.words(st, float(st["per"]) * (lvl + 1))] if lvl < Upgrades.MAX_LEVEL else "now %s  ·  at its best" % Upgrades.words(st, float(st["per"]) * lvl), 14, UI.TEXT_DIM))
		var b := EditorIcons.action(UI.button("", _buy_upgrade.bind(_up_body, st["id"], price), 15), "rating", "%d" % price,
			EditorIcons.tip("Upgrade %s" % str(st["name"]).to_lower(), "", "Level %d: %s for %d drachmas." % [lvl + 1, Upgrades.words(st, float(st["per"]) * (lvl + 1)), price]))
		b.text = "Upgrade  ·  %d dr" % price if lvl < Upgrades.MAX_LEVEL else "At its best"
		b.disabled = lvl >= Upgrades.MAX_LEVEL or data.credits < price
		v.add_child(b)
		grid.add_child(card)


func _buy_upgrade(which: String, id: String, price: int) -> void:
	if price <= 0 or not data.spend(price):
		return
	if Upgrades.raise(data.upgrades, which, id):
		var st := Upgrades.find(which, id)
		GameLog.post("Upgraded: %s's %s to level %d (%d dr)" % [Parts.info(which, st["part"])["name"], str(st["name"]).to_lower(), Upgrades.level(data.upgrades, which, id), price], "good")
		Sfx.play("space/repair", -4.0)
		ship.apply_tech()
		data.changed.emit()
	refresh()


## Fuel: fill the tank here (at this station's fuel price), or pump in the
## fuel you carry in the hold.
func _page_fuel() -> void:
	_content.add_child(UI.section("FUEL"))
	var f: float = data.fuel_level()
	var m: float = data.fuel_max()
	var unit := Shipyard.fuel_unit_price(station.station_id)
	_content.add_child(UI.label("Tank  %d / %d   ·   a jump through a gate burns %d, flying a trickle   ·   here %.1f dr a unit" % [
		floori(f), roundi(m), Shipyard.FUEL_JUMP, unit], 17, UI.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var need := m - f
	var units := minf(need, floorf(data.credits / unit))
	var cost := ceili(units * unit)
	var b := EditorIcons.action(UI.button("", _refuel.bind(units, cost), 18), "buy", "%d" % cost,
		EditorIcons.tip("Refuel" if units >= need - 0.5 else "Refuel %d of %d" % [roundi(units), roundi(need)], "", "Fills the tank: %d units for %d drachmas." % [roundi(units), cost]))
	b.text = "Refuel  (%d dr)" % cost if need >= 0.5 else "Tank full"
	b.disabled = need < 0.5 or units < 0.5
	b.custom_minimum_size = Vector2(300, 50)
	row.add_child(b)
	var held: int = data.count("fuel")
	var pump := mini(held, ceili(need / Shipyard.FUEL_UNITS_PER_CARGO))
	var pb := EditorIcons.action(UI.button("", _pump_fuel.bind(pump), 18), "cargo", "%d" % pump,
		EditorIcons.tip("Pump from the hold", "", "Each unit of fuel in your hold fills %d of the tank. You carry %d." % [Shipyard.FUEL_UNITS_PER_CARGO, held]))
	pb.text = "Pump %d fuel from the hold" % pump if pump > 0 else "No fuel in the hold"
	pb.disabled = pump <= 0
	pb.custom_minimum_size = Vector2(300, 50)
	row.add_child(pb)
	_content.add_child(row)


func _refuel(units: float, cost: int) -> void:
	if units > 0.0 and data.spend(cost):
		data.add_fuel(units)
		GameLog.post("Refuelled: %d units for %d dr" % [roundi(units), cost], "info")
		Sfx.play("space/repair")
		refresh()


func _pump_fuel(n: int) -> void:
	if n > 0 and data.remove_item("fuel", n):
		data.add_fuel(n * Shipyard.FUEL_UNITS_PER_CARGO)
		GameLog.post("Pumped %d fuel from the hold into the tank" % n, "info")
		refresh()


# --- Buy ---------------------------------------------------------------------------

## The outfitter's categories (a tab each: nothing to scroll).
const OUTFIT_TABS := ["YOUR SHIP", "WEAPONS", "SYSTEMS", "SHIP MODULES", "AUTOMATON GEAR", "SUPPLIES"]
var _outfit_tab := 0
var _outfit_sel := ""          # the selected card (its spec's key)
var _outfit_specs := {}        # key -> spec (see _outfit_spec)
var _outfit_cards := {}        # key -> its card
var _outfit_detail: VBoxContainer


func _page_buy() -> void:
	# The ship's numbers and the quality selector; a tab per category; the
	# category's cards (click one) beside the selection's detail: its picture,
	# what it is, and what it would change - before and after.
	var cls := Shipyard.stats(data.ship_class)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var info := UI.label("%s  ·  hull %d  ·  shields %d  ·  speed %d  ·  cargo %d slots  ·  fuel %d\n%s" % [
		cls["name"].to_upper(), ship.max_hull, ship.max_shields, ship.max_speed, Shipyard.cargo_capacity(data), roundi(data.fuel_max()),
		"  ·  ".join(Shipyard.AREAS.map(func(a): return "%s %d/%d" % [Shipyard.AREA_NAMES[a], Shipyard.area_fittings(data, a).size(), Shipyard.area_capacity(data, a)]))], 14, UI.TEXT_DIM)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (wraps beside the quality buttons, not widening the page)
	info.custom_minimum_size.x = 360
	head.add_child(info)
	if _outfit_tab == 1:   # (weapons come in sizes: the hardpoints say which fit)
		var lay := Hardpoints.layout(data.ship_class)
		if _wsize < 0:
			_wsize = mini(int(lay.max()), 2)
		var hp_text := Hardpoints.summary(lay)
		var hl := UI.label("SIZE", 14, NeonTheme.HEAD)
		hl.tooltip_text = "Your hardpoints: %s.\nA weapon fits a hardpoint its size or bigger." % hp_text
		head.add_child(hl)
		for z in Hardpoints.SIZES.size():
			var zb := UI.button(Hardpoints.SIZES[z], _set_wsize.bind(z), 13)
			zb.toggle_mode = true
			zb.button_pressed = z == _wsize
			zb.custom_minimum_size = Vector2(54, 34)
			zb.tooltip_text = "Show the weapons in size %s (%s). Your hardpoints: %s." % [Hardpoints.SIZES[z], Hardpoints.SIZE_NAMES[z].to_lower(), hp_text]
			head.add_child(zb)
	if _outfit_tab in [3, 4]:   # (modules and automaton gear come in qualities)
		head.add_child(UI.label("QUALITY", 14, NeonTheme.HEAD))
		for q in Gear.QUALITY.size():
			var qb := UI.button("%s  %s" % [Gear.QUALITY[q], Gear.QUALITY_NAMES[q]], _set_quality.bind(q), 13)
			qb.toggle_mode = true
			qb.button_pressed = q == _quality
			qb.custom_minimum_size = Vector2(118, 34)
			qb.tooltip_text = "Show the gear at %s quality (E is the cheapest and weakest, A the best)." % Gear.QUALITY_NAMES[q]
			head.add_child(qb)
	_content.add_child(head)
	_content.add_child(_sub_tabs(OUTFIT_TABS, _outfit_tab, func(i):
		_outfit_tab = i
		_outfit_sel = ""
		refresh()))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	_content.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_child(grid)
	body.add_child(list)
	var panel := UI.light_panel(PanelContainer.new())
	panel.custom_minimum_size.x = 460
	body.add_child(panel)
	_outfit_detail = VBoxContainer.new()
	_outfit_detail.add_theme_constant_override("separation", 6)
	panel.add_child(_outfit_detail)

	_outfit_specs = {}
	_outfit_cards = {}
	var specs := _outfit_specs_for(_outfit_tab)
	for sp in specs:
		_outfit_specs[sp["key"]] = sp
		var card := _outfit_card(sp)
		_outfit_cards[sp["key"]] = card
		grid.add_child(card)
	if specs.is_empty():
		list.add_child(UI.label({0: "Nothing fitted yet, and no ship gear in your hold. Buy modules in SHIP MODULES."}.get(_outfit_tab, "Nothing here."), 14, UI.TEXT_DIM))
	if not _outfit_specs.has(_outfit_sel):
		_outfit_sel = specs[0]["key"] if not specs.is_empty() else ""
	_show_outfit_detail()


## The cards of a category, as specs: {key, icon, title, sub, desc, price,
## actions: [{icon, text, call, disabled, tip}], rows (before / after,
## OutfitCompare), facts ([label, value, format]), what (the rows' subject)}.
func _outfit_specs_for(tab: int) -> Array:
	var out := []
	var base: Dictionary = ship._base if ship else {}
	match tab:
		0:   # your ship: fitted modules (to the hold / sold back), ship gear in the hold (fit)
			for i in data.modules.size():
				var m: Dictionary = data.modules[i]
				var gid := Gear.item_id(m["id"], int(m["rating"]))
				var refund := roundi(Shipyard.module_price(m["id"], m["rating"]) * 0.8)
				var area: String = Shipyard.AREA_NAMES[Shipyard.area_of(m["id"])].to_lower()
				out.append({"key": "fitted:%d" % i, "icon": gid, "title": Shipyard.module_name(m), "sub": "fitted  ·  " + area,
					"desc": "%s\n%s" % [Shipyard.MODULES[m["id"]]["desc"], Gear.describe(gid)], "price": refund, "what": "Taking it out",
					"rows": OutfitCompare.ship_rows(data, base, "", 0, i),
					"actions": [{"icon": "cargo", "text": "To hold", "call": _unfit_module.bind(i), "tip": "Into your hold (it's gear: refit it any time).",
							"disabled": Inventory.room_for(data.items, gid, Shipyard.cargo_capacity(data)) < 1},
						{"icon": "remove", "text": "+%d" % refund, "call": _remove_module.bind(i, refund), "disabled": false,
							"tip": "Sold back for %d drachmas (80%%), freeing its place in the %s." % [refund, area]}]})
			for id in data.held_items().filter(func(x): return Gear.side(x) == "ship"):
				var area: String = Shipyard.AREA_NAMES[Shipyard.area_of(id)].to_lower()
				out.append({"key": "held:" + id, "icon": id, "title": "%s  ×%d" % [Gear.title(id), data.count(id)], "sub": "in your hold  ·  " + area,
					"desc": Gear.describe(id), "price": -1, "what": "Fitting it", "rows": OutfitCompare.ship_rows(data, base, id),
					"actions": [{"icon": "rating", "text": "Fit", "call": _fit_gear.bind(id), "disabled": Shipyard.free_for(data, id) <= 0,
						"tip": "Goes in the %s (%d free there)." % [area, Shipyard.free_for(data, id)]}]})
		1:   # weapons: fitted (by kind and size), in the hold, and for sale at the chosen size
			var ws := Hardpoints.fitted(data)
			var lay := Hardpoints.layout(data.ship_class)
			var groups := {}
			for i in ws.size():
				if ws[i] != "":
					groups.get_or_add(ws[i], []).append(i)
			for id in groups:
				var slots: Array = groups[id]
				var refund := roundi(Hardpoints.price(id) * 0.8)
				var last: int = slots[-1]
				out.append({"key": "fw:" + id, "icon": id, "title": "%s  ×%d" % [Hardpoints.title(id), slots.size()], "sub": "fitted",
					"desc": Hardpoints.info(id)["desc"], "price": refund, "what": "Taking one out",
					"rows": OutfitCompare.ship_rows(data, base, "", 0, -1, last), "facts": OutfitCompare.weapon_facts(data, id),
					"actions": [{"icon": "cargo", "text": "To hold", "call": _unfit_weapon.bind(last), "tip": "One into your hold (refit it any time).",
							"disabled": Inventory.room_for(data.items, id, Shipyard.cargo_capacity(data)) < 1},
						{"icon": "remove", "text": "+%d" % refund, "call": _sell_weapon.bind(last, refund), "disabled": false,
							"tip": "One sold back for %d drachmas (80%%), freeing its hardpoint (%s)." % [refund, Hardpoints.SIZES[lay[last]]]}]})
			for id in data.held_items().filter(func(x): return Hardpoints.is_weapon(x)):
				var slot := Hardpoints.free_slot_for(data, id)
				out.append({"key": "hw:" + id, "icon": id, "title": "%s  ×%d" % [Hardpoints.title(id), data.count(id)], "sub": "in your hold",
					"desc": Hardpoints.info(id)["desc"], "price": -1, "what": "Fitting it", "rows": OutfitCompare.ship_rows(data, base, id),
					"facts": OutfitCompare.weapon_facts(data, id),
					"actions": [{"icon": "rating", "text": "Fit", "call": _fit_weapon.bind(id), "disabled": slot < 0,
						"tip": ("Goes on a free %s hardpoint." % Hardpoints.SIZES[lay[slot]]) if slot >= 0 else "No free hardpoint of size %s or bigger." % Hardpoints.SIZES[Hardpoints.size_of(id)]}]})
			for k in Hardpoints.KINDS:
				if not _wsize in Hardpoints.sizes(k):
					continue
				var id := Hardpoints.item_id(k, _wsize)
				var price := Hardpoints.price(id)
				var slot := Hardpoints.free_slot_for(data, id)
				var room := Inventory.room_for(data.items, id, Shipyard.cargo_capacity(data)) >= 1
				out.append({"key": "buy:" + id, "icon": id, "title": Hardpoints.title(id), "sub": "free hardpoint" if slot >= 0 else "into the hold",
					"desc": Hardpoints.info(id)["desc"], "price": price, "what": "Fitting it",
					"rows": OutfitCompare.ship_rows(data, base, id) if slot >= 0 else [], "facts": OutfitCompare.weapon_facts(data, id),
					"actions": [{"icon": "buy", "text": "%d" % price, "call": _buy_weapon.bind(id, price),
						"disabled": data.credits < price or (slot < 0 and not room),
						"tip": "Costs %d drachmas; %s" % [price, ("goes on a free %s hardpoint." % Hardpoints.SIZES[lay[slot]]) if slot >= 0 else "no free hardpoint takes it: into your hold."]}]})
		2:   # systems (utility mounts) - one of each
			for id in Shipyard.UTILITY_GEAR:
				var eq: Dictionary = Items.EQUIPMENT[id]
				var area: String = Shipyard.AREA_NAMES[Shipyard.area_of(id)].to_lower()
				var have: bool = data.has_equipment(id)
				var refund := roundi(eq["price"] * 0.8)
				var act: Dictionary
				if have:
					act = {"icon": "remove", "text": "+%d" % refund, "call": _remove_gear.bind(id, refund), "disabled": false,
						"tip": "Sold back for %d drachmas (80%%), freeing its place in the %s." % [refund, area]}
				else:
					act = {"icon": "buy", "text": "%d" % eq["price"], "call": _buy_equipment.bind(id, eq["price"]),
						"disabled": data.credits < eq["price"] or Shipyard.free_for(data, id) <= 0,
						"tip": "Costs %d drachmas; goes in the %s (%d free there)." % [eq["price"], area, Shipyard.free_for(data, id)]}
				out.append({"key": "eq:" + id, "icon": id, "title": eq["name"], "sub": "fitted" if have else area, "desc": eq["desc"],
					"price": eq["price"], "what": "Fitted" if have else "Fitting it",
					"rows": [] if have else OutfitCompare.ship_rows(data, base, id),
					"facts": OutfitCompare.system_facts(id), "actions": [act]})
		3:   # ship modules at the chosen quality (fitted at once if there's room, else into the hold)
			for id in Shipyard.MODULES:
				var md: Dictionary = Shipyard.MODULES[id]
				var price := Shipyard.module_price(id, _quality)
				var gid := Gear.item_id(id, _quality)
				var area: String = Shipyard.AREA_NAMES[Shipyard.area_of(id)].to_lower()
				out.append({"key": "mod:" + id, "icon": gid, "title": md["name"], "sub": area, "desc": "%s\n%s" % [md["desc"], Gear.describe(gid)],
					"price": price, "what": "Fitting it", "rows": OutfitCompare.ship_rows(data, base, id, _quality),
					"actions": [{"icon": "rating", "text": "%d" % price, "call": _buy_module.bind(id, _quality, price),
						"disabled": data.credits < price or (Shipyard.free_for(data, id) <= 0 and Inventory.room_for(data.items, gid, Shipyard.cargo_capacity(data)) < 1),
						"tip": "%s for %d drachmas.\nGoes in the %s - or, no room there, into your hold." % [Gear.QUALITY_NAMES[_quality], price, area]}]})
		4:   # automaton gear at the chosen quality (into the hold)
			for kind in Gear.FOOT:
				var gd: Dictionary = Gear.FOOT[kind]
				var gid := Gear.item_id(kind, _quality)
				var gprice := Gear.price(gid)
				var where: String = Gear.AREA_OF_SLOT.get({"weapon": "weapon", "mod": "mod1", "armour": "armour", "core": "core", "passive": "passive1"}.get(gd["slot"], "weapon"), "")
				out.append({"key": "foot:" + kind, "icon": gid, "title": gd["name"], "sub": where.to_lower(), "desc": "%s\n%s" % [gd["desc"], Gear.describe(gid)],
					"price": gprice, "what": "Equipping it (on your automaton)", "rows": OutfitCompare.foot_rows(data.loadout, gid),
					"actions": [{"icon": "rating", "text": "%d" % gprice, "call": _buy_gear.bind(gid, gprice),
						"disabled": data.credits < gprice or Inventory.room_for(data.items, gid, Shipyard.cargo_capacity(data)) < 1,
						"tip": "%s for %d drachmas.\nInto your hold: equip it from the inventory." % [Gear.QUALITY_NAMES[_quality], gprice]}]})
		5:   # supplies
			for entry in SUPPLIES:
				var sid: String = entry[0]
				var amount: int = entry[1]
				var sprice: int = Items.ITEMS[sid]["price"] * amount
				var stitle := Items.display_name(sid) + ("  ×%d" % amount if amount > 1 else "")
				out.append({"key": "sup:" + sid, "icon": sid, "title": stitle, "sub": "you have %d" % data.count(sid), "desc": Items.ITEMS[sid]["desc"],
					"price": sprice, "what": "Buying them", "rows": [["You have", float(data.count(sid)), float(data.count(sid) + amount), "%.0f", true]],
					"actions": [{"icon": "buy", "text": "%d" % sprice, "call": _buy_item.bind(sid, amount, sprice), "disabled": data.credits < sprice,
						"tip": "Costs %d drachmas. Supplies don't use cargo space." % sprice}]})
	return out


## A spec's buttons (made fresh: one set on the card, one in the detail).
func _outfit_buttons(sp: Dictionary, font := 12) -> Array:
	var out := []
	for a in sp.get("actions", []):
		var b := EditorIcons.action(UI.button("", a["call"], font), a["icon"], a["text"], EditorIcons.tip(sp["title"], "", "%s\n%s" % [sp["desc"], a["tip"]]))
		b.disabled = a["disabled"]
		out.append(b)
	return out


## A card of the outfitter's list: click it to see it in the detail.
func _outfit_card(sp: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.size_flags_horizontal = SIZE_EXPAND_FILL   # (the cards share the row: names whole)
	card.add_theme_stylebox_override("panel", _outfit_card_style(sp["key"] == _outfit_sel))
	card.add_child(_card(sp["icon"], sp["title"], sp["sub"], sp["desc"], _outfit_buttons(sp)))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select_outfit(sp["key"]))
	return card


func _select_outfit(key: String) -> void:
	if key == _outfit_sel:
		return
	if _outfit_cards.has(_outfit_sel) and is_instance_valid(_outfit_cards[_outfit_sel]):
		_outfit_cards[_outfit_sel].add_theme_stylebox_override("panel", _outfit_card_style(false))
	_outfit_sel = key
	if _outfit_cards.has(key):
		_outfit_cards[key].add_theme_stylebox_override("panel", _outfit_card_style(true))
	_show_outfit_detail()


static var _card_styles := {}

static func _outfit_card_style(selected: bool) -> StyleBoxFlat:
	if not _card_styles.has(selected):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(NeonTheme.CYAN, 0.16) if selected else Color(0, 0, 0, 0)
		sb.border_color = Color(NeonTheme.CYAN, 0.9) if selected else Color(0, 0, 0, 0)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		_card_styles[selected] = sb
	return _card_styles[selected]


## The selection's detail: its picture, name, description, price and buttons,
## and what it would change - each stat before and after.
func _show_outfit_detail() -> void:
	if _outfit_detail == null:
		return
	UI.clear(_outfit_detail)
	var sp: Dictionary = _outfit_specs.get(_outfit_sel, {})
	if sp.is_empty():
		_outfit_detail.add_child(UI.label("Pick something on the left to see it here.", 14, UI.TEXT_DIM))
		UI.scale_fonts(_outfit_detail, "menu")
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var pic := ItemPortrait.new()
	pic.custom_minimum_size = Vector2(170, 170)
	pic.show_item(sp["icon"])
	top.add_child(pic)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	var t := UI.label(sp["title"], 18, NeonTheme.HEAD)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(t)
	words.add_child(UI.label(sp["sub"], 13, UI.TEXT_DIM))
	if int(sp.get("price", -1)) >= 0:
		words.add_child(UI.label("%s drachmas" % UI.money(sp["price"]), 15, UI.GOLD))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	for b in _outfit_buttons(sp, 14):
		b.custom_minimum_size = Vector2(110, 34)
		btns.add_child(b)
	words.add_child(btns)
	top.add_child(words)
	_outfit_detail.add_child(top)
	var d := UI.label(sp["desc"], 13, UI.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outfit_detail.add_child(d)
	var facts: Array = sp.get("facts", [])
	if not facts.is_empty():
		_outfit_detail.add_child(UI.section("ITS STATS"))
		var fg := GridContainer.new()
		fg.columns = 4
		fg.add_theme_constant_override("h_separation", 14)
		for f in facts:
			fg.add_child(UI.label(f[0], 13, UI.TEXT_DIM))
			fg.add_child(UI.label(f[2] % f[1], 13))
		_outfit_detail.add_child(fg)
	var rows: Array = sp.get("rows", [])
	_outfit_detail.add_child(UI.section(("%s: BEFORE  →  AFTER" % sp.get("what", "")).to_upper()))
	if rows.is_empty():
		_outfit_detail.add_child(UI.label("Already yours." if sp.get("what", "") == "Fitted" else "No change to your stats.", 13, UI.TEXT_DIM))
	else:
		var g := GridContainer.new()
		g.columns = 5
		g.add_theme_constant_override("h_separation", 12)
		g.add_theme_constant_override("v_separation", 1)
		for r in rows:
			var better: bool = (r[2] > r[1]) == bool(r[4])
			var col := Color(0.45, 0.95, 0.5) if better else Color(1.0, 0.45, 0.4)
			var delta: float = r[2] - r[1]
			g.add_child(UI.label(r[0], 13, UI.TEXT_DIM))
			g.add_child(UI.label(r[3] % r[1], 13))
			g.add_child(UI.label("→", 13, UI.TEXT_DIM))
			g.add_child(UI.label(r[3] % r[2], 14, col))
			g.add_child(UI.label(("+" if delta > 0 else "-") + (r[3] % absf(delta)), 13, col))
		_outfit_detail.add_child(g)
	UI.scale_fonts(_outfit_detail, "menu")


## A row of small tabs inside a page (the outfitter's categories, the
## shipyard's classes): `on_select(i)`.
func _sub_tabs(names: Array, current_i: int, on_select: Callable, rows := 1) -> Container:
	var box := VBoxContainer.new()   # (`rows` rows of tabs, sharing them out)
	box.add_theme_constant_override("separation", 4)
	var bar: HBoxContainer
	var per_row := ceili(names.size() / float(rows))
	var group := ButtonGroup.new()
	for i in names.size():
		if i % per_row == 0:
			bar = HBoxContainer.new()
			bar.add_theme_constant_override("separation", 6)
			box.add_child(bar)
		var b := UI.button(str(names[i]), on_select.bind(i), 14)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = i == current_i
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		# (they share the row: at big text a long name ends in "..." - its
		# tooltip has it whole - rather than pushing the page wider)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = str(names[i])
		# (the chosen one: dark text on its lit face)
		b.add_theme_color_override("font_pressed_color", NeonTheme.INK)
		b.add_theme_color_override("font_hover_pressed_color", NeonTheme.INK)
		b.add_theme_color_override("icon_pressed_color", NeonTheme.INK)
		bar.add_child(b)
	return box


## A compact card: the item's icon, its name and a line, its buttons; the
## whole description in the tooltip.
func _card(icon_id: String, title: String, sub: String, desc: String, buttons: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(246, 40)
	row.size_flags_horizontal = SIZE_EXPAND_FILL   # (wider with room: the name shows whole)
	row.tooltip_text = "%s\n%s" % [title, desc]
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := ItemSlot.make(icon_id, 0, 40.0)
	icon.tooltip_text = row.tooltip_text
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.custom_minimum_size.x = 120
	var t := UI.label(title, 13)
	t.clip_text = true
	t.tooltip_text = row.tooltip_text
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(t)
	var st := UI.label(sub, 12, UI.TEXT_DIM)
	st.clip_text = true
	text.add_child(st)
	row.add_child(text)
	for b in buttons:
		b.custom_minimum_size = Vector2(70, 30)
		UI.light_button(b)   # (a page of these: the light style - far fewer draw calls)
		row.add_child(b)
	return row


func _buy_module(id: String, rating: int, price: int) -> void:
	if Shipyard.free_for(data, id) > 0 and data.spend(price):
		data.modules.append({"id": id, "rating": rating})
		GameLog.post("Fitted %s (%d dr)" % [Shipyard.module_name({"id": id, "rating": rating}), price], "good")
		data.changed.emit()
	elif Inventory.room_for(data.items, Gear.item_id(id, rating), Shipyard.cargo_capacity(data)) >= 1 and data.spend(price):
		Inventory.add(data.items, Gear.item_id(id, rating), 1, Shipyard.cargo_capacity(data))
		GameLog.post("Bought %s (%d dr) - no free %s slot: it's in your hold" % [Shipyard.module_name({"id": id, "rating": rating}), price, Shipyard.MODULES[id]["slot"]], "good")
		data.changed.emit()


var _quality := 0   # the outfitter's quality shown (Gear.QUALITY)
var _wsize := -1    # the weapon size shown (Hardpoints.SIZES; -1: picked for the ship)

func _set_wsize(z: int) -> void:
	_wsize = z
	refresh()


## A weapon bought: on a free hardpoint that takes it, else into the hold.
func _buy_weapon(id: String, price: int) -> void:
	var slot := Hardpoints.free_slot_for(data, id)
	if slot < 0 and Inventory.room_for(data.items, id, Shipyard.cargo_capacity(data)) < 1:
		return
	if not data.spend(price):
		return
	if slot >= 0:
		Hardpoints.fit(data, id, slot, false)
		GameLog.post("Fitted %s (%d dr)" % [Hardpoints.title(id), price], "good")
	else:
		Inventory.add(data.items, id, 1, Shipyard.cargo_capacity(data))
		GameLog.post("Bought %s (%d dr) - no free hardpoint takes it: it's in your hold" % [Hardpoints.title(id), price], "good")
		data.changed.emit()


func _fit_weapon(id: String) -> void:
	if Hardpoints.fit(data, id):
		GameLog.post("Fitted %s" % Hardpoints.title(id), "good")


func _unfit_weapon(slot: int) -> void:
	var id: String = Hardpoints.fitted(data)[slot]
	if Hardpoints.unfit(data, slot):
		GameLog.post("%s taken out into your hold" % Hardpoints.title(id), "info")


func _sell_weapon(slot: int, refund: int) -> void:
	var ws := Hardpoints.fitted(data)
	var id: String = ws[slot]
	if id == "":
		return
	ws[slot] = ""
	data.add_credits(refund)
	GameLog.post("Sold %s (+%d dr)" % [Hardpoints.title(id), refund], "info")
	data.changed.emit()

func _set_quality(q: int) -> void:
	_quality = q
	refresh()


## Gear bought into the hold (an automaton's, or ship gear with no slot free).
func _buy_gear(id: String, price: int) -> void:
	if Inventory.room_for(data.items, id, Shipyard.cargo_capacity(data)) >= 1 and data.spend(price):
		Inventory.add(data.items, id, 1, Shipyard.cargo_capacity(data))
		GameLog.post("Bought %s (%d dr) - it's in your hold" % [Gear.title(id), price], "good")
		data.changed.emit()


func _fit_gear(id: String) -> void:
	if Gear.fit(data, id):
		GameLog.post("Fitted %s" % Gear.title(id), "good")
		data.changed.emit()


func _unfit_module(i: int) -> void:
	var m: Dictionary = data.modules[i]
	if Gear.unfit(data, i):
		GameLog.post("%s taken out into your hold" % Shipyard.module_name(m), "info")
		data.changed.emit()


func _remove_module(i: int, refund: int) -> void:
	var m: Dictionary = data.modules[i]
	data.modules.remove_at(i)
	data.add_credits(refund)
	GameLog.post("Sold %s (+%d dr)" % [Shipyard.module_name(m), refund], "info")


func _remove_gear(id: String, refund: int) -> void:
	data.equipment.erase(id)
	data.add_credits(refund)
	GameLog.post("Removed %s (+%d dr)" % [Items.EQUIPMENT[id]["name"], refund], "info")


# --- Ship designer (paint shop) --------------------------------------------------------

var _design := {}
var _preview: DesignPreview
var _cost_label: Label
var _apply_btn: Button
var _design_keep := false
var _sliders := {}


func _page_designer() -> void:
	if _design_keep:
		_design_keep = false   # refreshed after picking a skin: keep the edits
	else:
		_design = ShipParts.normalized(data.ship_look)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_content.add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	_preview = DesignPreview.new()
	_preview.texture = ship.sprite.texture
	_preview.custom_minimum_size = Vector2(360, 380)
	left.add_child(_preview)
	left.add_child(UI.label("Live preview  ·  %s" % Shipyard.stats(data.ship_class)["name"], 13, UI.TEXT_DIM))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	col.add_child(UI.section("CUSTOM PAINT  ·  %d dr per paint job" % ShipParts.PAINT_JOB))
	_sliders.clear()
	for f in [["hue", "Hue", -0.5, 0.5, "Turns every colour of the hull round the colour wheel (the middle: as built)."],
			["sat", "Saturation", 0.0, 1.6, "How strong the colours are: 0 grey, 1 as built."],
			["bright", "Brightness", 0.4, 1.5, "How light or dark the hull is: 1 as built."],
			["tint_amt", "Tint strength", 0.0, 0.8, "How much of the tint colour (below) is laid over the hull: 0 none."]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var l := UI.label(f[1], 15)
		l.custom_minimum_size = Vector2(140, 0)
		line.add_child(l)
		var sl := HSlider.new()
		sl.min_value = f[2]
		sl.max_value = f[3]
		sl.step = 0.01
		sl.value = float(_design[f[0]])
		sl.size_flags_horizontal = SIZE_EXPAND_FILL
		sl.focus_mode = FOCUS_NONE
		sl.tooltip_text = "%s\n%s\nThe preview shows it at once; a paint job costs %d dr." % [f[1], f[4], ShipParts.PAINT_JOB]
		var key: String = f[0]
		sl.value_changed.connect(func(v):
			_design[key] = v
			_design.erase("skin")
			_design_changed())
		line.add_child(sl)
		_sliders[key] = sl
		col.add_child(line)
	var tline := HBoxContainer.new()
	tline.add_child(UI.label("Tint colour", 15))
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(120, 32)
	cp.color = Color(_design["tint"])
	cp.tooltip_text = "Tint colour\nThe colour laid over the hull (as much as Tint strength says). Click to pick it."
	cp.color_changed.connect(func(c):
		_design["tint"] = c.to_html()
		_design.erase("skin")
		_design_changed())
	tline.add_child(cp)
	col.add_child(tline)
	col.add_child(UI.section("READY-MADE SKINS  (✓ owned)"))
	var skins := GridContainer.new()
	skins.columns = 4
	skins.add_theme_constant_override("h_separation", 6)
	skins.add_theme_constant_override("v_separation", 6)
	for id in ShipParts.SKINS:
		var sk: Dictionary = ShipParts.SKINS[id]
		var owned: bool = data.owned_parts.has(id)
		var b := UI.button("✓" if owned else "%d" % sk["price"], func():
			_design = ShipParts.skin_look(id)
			_design_keep = true
			refresh(), 13)
		b.focus_mode = FOCUS_NONE
		# The skin's colour as a swatch.
		var tint: Color = sk["tint"]
		b.icon = Icons.paint(22, 22, [{"pts": Icons.arc(Vector2(11, 11), 9.0, 0, TAU, 20), "fill": tint, "stroke": tint.lightened(0.5), "width": 1.5}])
		b.tooltip_text = EditorIcons.tip("Skin: %s" % sk["name"], "", "Shows this ready-made paint job in the preview (press Apply to paint your ship).\n%s" % (
			"You own it: applying it is free." if owned else "Costs %d drachmas the first time you apply it; after that it's yours to re-apply for free." % sk["price"]))
		skins.add_child(b)
	col.add_child(skins)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_cost_label = UI.label("", 17, UI.GOLD)
	foot.add_child(_cost_label)
	foot.add_child(UI.spacer())
	foot.add_child(EditorIcons.dress(UI.button("", func():
		data.ship_look = {}
		data.changed.emit()
		GameLog.post("Ship restored to its factory paint", "info")
		refresh(), 15), "reload", EditorIcons.tip("Factory paint", "", "Restores your ship's original colours, for free. Skins you bought stay yours.")))
	_apply_btn = EditorIcons.dress(UI.button("", _apply_design, 17), "apply", EditorIcons.tip("Apply paint", "", "Paints your ship as shown in the preview. Adjusting the sliders costs a little; ready-made skins\nare bought once and then free to re-apply. The cost is shown on the left."))
	foot.add_child(_apply_btn)
	col.add_child(foot)
	_design_changed()


func _design_changed() -> void:
	var c := ShipParts.cost(data.ship_look, _design, data.owned_parts)
	_cost_label.text = "Changes cost: %d dr" % c if c > 0 else "No cost"
	_apply_btn.disabled = data.credits < c
	_preview.material = ShipParts.material(_design)


func _apply_design() -> void:
	# (copy first: paying emits data.changed, which refreshes this page)
	var design := _design.duplicate(true)
	var c := ShipParts.cost(data.ship_look, design, data.owned_parts)
	if c > 0 and not data.spend(c):
		return
	var sk: String = design.get("skin", "")
	if sk != "" and not data.owned_parts.has(sk):
		data.owned_parts.append(sk)
	data.ship_look = design
	GameLog.post("Ship repainted%s" % ((" (%d dr)" % c) if c > 0 else ""), "good")
	data.changed.emit()
	refresh()


## Live preview: your ship's sprite with the paint job, turning slowly.
class DesignPreview extends Control:
	var texture: Texture2D
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var ts := texture.get_size()
		var k := minf(size.x * 0.9 / ts.x, size.y * 0.9 / ts.y)
		draw_set_transform(size / 2.0, sin(_t * 0.6) * 0.08, Vector2(k, k))
		draw_texture(texture, -ts / 2.0)
		draw_set_transform(Vector2.ZERO)


# --- Shipyard ------------------------------------------------------------------------

## The shipyard's classes (a tab each), smallest first.
const SHIP_CLASSES := ["interceptor", "fighter", "courier", "explorer", "gunship", "freighter", "frigate", "cruiser", "battleship", "dreadnought"]
const SHIP_CLASS_NAMES := {"interceptor": "INTERCEPTORS", "fighter": "FIGHTERS", "courier": "COURIERS", "explorer": "EXPLORERS",
	"gunship": "GUNSHIPS", "freighter": "FREIGHTERS", "frigate": "FRIGATES", "cruiser": "CRUISERS", "battleship": "BATTLESHIPS", "dreadnought": "DREADNOUGHTS"}
var _yard_tab := -1   # (-1: your ship's class, the first time)


func _page_shipyard() -> void:
	var e: String = station.empire
	var cur := Shipyard.stats(data.ship_class)
	var trade_in := Shipyard.trade_in(data)
	# The ships by class: a tab for each class this yard sells.
	var by_class := {}
	for id in Shipyard.for_sale(e):
		var cls: String = "fighter" if id == "player" else str(EnemyTypes.get_type(id).get("class", "fighter"))
		by_class.get_or_add(cls, []).append(id)
	var classes: Array = SHIP_CLASSES.filter(func(c): return by_class.has(c))
	if _yard_tab < 0 or _yard_tab >= classes.size():
		var mine: String = "fighter" if data.ship_class in ["", "player"] else str(EnemyTypes.get_type(data.ship_class).get("class", "fighter"))
		_yard_tab = maxi(0, classes.find(mine))
	_content.add_child(UI.section("SHIPYARD  ·  %s DESIGNS" % Galaxy.EMPIRES.get(e, {"short": "local"})["short"].to_upper()))
	if not CosmosGame.has_ship():
		_content.add_child(UI.note("You have no ship yet: buy one and it's yours - it comes down this port's lift onto a pad.", 14, 400))
	else:
		_content.add_child(UI.note("You fly the %s (hull %d, shields %d, speed %d). Trade-in value: %s dr (80%% of what it cost you). Fitted modules move to the new ship if they fit (the rest are sold at 80%%); weapons go on its hardpoints that take them, the rest into your hold." % [
			cur["name"], cur["hull"], cur["shields"], cur["speed"], UI.money(trade_in)], 14, 400))
	var names := classes.map(func(c): return "%s  %d" % [SHIP_CLASS_NAMES[c], by_class[c].size()])
	_content.add_child(_sub_tabs(names, _yard_tab, func(i):
		_yard_tab = i
		refresh(), 2 if names.size() > 8 else 1))   # (ten classes: two rows, the wide type fits)
	if classes.is_empty():
		return
	var ids: Array = by_class[classes[_yard_tab]]
	ids.sort_custom(func(a, b): return Shipyard.stats(a)["price"] < Shipyard.stats(b)["price"])
	# A class's ships as cards, three to a row, cheapest first.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for id in ids:
		var st := Shipyard.stats(id)
		var panel := UI.light_panel(PanelContainer.new())
		panel.custom_minimum_size = Vector2(400, 0)
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		var fuel := roundi(Shipyard.CLASS_FUEL.get(EnemyTypes.get_type(id).get("class", ""), Shipyard.STARTER_FUEL)) if id != "player" else roundi(Shipyard.STARTER_FUEL)
		panel.tooltip_text = "%s\nHull %d  ·  Shields %d  ·  Speed %d  ·  Cargo %d slots  ·  Fuel %d\nHardpoints %d  ·  Internal %d  ·  Utility %d  ·  Price %s dr" % [
			st["name"], st["hull"], st["shields"], st["speed"], st["cargo"], fuel, st["hardpoints"], st["internal"], st["utility"], UI.money(st["price"])]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(row)
		var pic := TextureRect.new()
		pic.texture = ProcArt.sprite("ship_player") if id == "player" else EnemyTypes.texture(id)
		pic.custom_minimum_size = Vector2(84, 84)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(pic)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 1)
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		var nm := UI.label(st["name"] + ("  (yours)" if id == data.ship_class and CosmosGame.has_ship() else ""), 14)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size.x = 150
		info.add_child(nm)
		# Each stat with how it compares with your ship's (green: better).
		var stats := HFlowContainer.new()
		stats.add_theme_constant_override("h_separation", 10)
		for k in [["hull", "hull"], ["shields", "shields"], ["speed", "speed"], ["cargo", "hold"]]:
			var v: float = float(st[k[0]])
			var dv: float = v - float(cur[k[0]])
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 3)
			cell.add_child(UI.label("%s %d" % [k[1], v], 12, UI.TEXT_DIM))
			if absf(dv) >= 1.0 and id != data.ship_class:
				cell.add_child(UI.label("%+d" % dv, 12, Color(0.45, 0.95, 0.5) if dv > 0 else Color(1.0, 0.45, 0.4)))
			stats.add_child(cell)
		info.add_child(stats)
		info.add_child(UI.label("hardpoints %s  ·  modules %d + %d  ·  fuel %d" % [Hardpoints.summary(Hardpoints.layout(id)), st["internal"], st["utility"], fuel], 12, UI.TEXT_DIM))
		var low := HBoxContainer.new()
		low.add_theme_constant_override("separation", 6)
		var pl := UI.label("%s dr" % UI.money(st["price"]), 14, UI.GOLD)
		pl.size_flags_horizontal = SIZE_EXPAND_FILL
		low.add_child(pl)
		var cost: int = st["price"] - trade_in
		var b := EditorIcons.action(UI.button("", _buy_ship.bind(id, cost), 12), "buy", UI.money(cost), EditorIcons.tip("Buy the %s" % st["name"], "", "Price %s drachmas; your current ship is traded in, so you pay %s (a negative amount is paid to you).\nYou keep your cargo; modules and equipment with no room on the new ship are sold back." % [UI.money(st["price"]), UI.money(cost)]))
		b.disabled = id == data.ship_class or data.credits < cost
		b.custom_minimum_size = Vector2(110, 28)
		UI.light_button(b)
		low.add_child(b)
		info.add_child(low)
		row.add_child(info)
		grid.add_child(panel)


func _buy_ship(id: String, cost: int) -> void:
	if cost > 0 and not data.spend(cost):
		return
	if cost < 0:
		data.add_credits(-cost)
	var old := Shipyard.stats(data.ship_class)
	var old_weapons: Array = data.weapons.duplicate()
	data.ship_class = id
	var st := Shipyard.stats(id)
	data.ship_value = int(st["price"])
	# Move what fits; sell the rest at 80%.
	# What fits each area of the new ship stays (equipment first, then
	# modules in order); the rest is sold back at 80%.
	var refund := Hardpoints.refit(data, old_weapons)   # (the weapons onto its hardpoints; what doesn't fit to the hold)
	var used := {}
	for g in Shipyard.UTILITY_GEAR:
		if data.has_equipment(g):
			var ga := Shipyard.area_of(g)
			if int(used.get(ga, 0)) < Shipyard.area_capacity(data, ga):
				used[ga] = int(used.get(ga, 0)) + 1
			else:
				data.equipment.erase(g)
				refund += roundi(Items.EQUIPMENT[g]["price"] * 0.8)
	var kept := []
	for m in data.modules:
		var ma := Shipyard.area_of(m["id"])
		if int(used.get(ma, 0)) < Shipyard.area_capacity(data, ma):
			kept.append(m)
			used[ma] = int(used.get(ma, 0)) + 1
		else:
			refund += roundi(Shipyard.module_price(m["id"], m["rating"]) * 0.8)
	data.modules = kept
	if refund > 0:
		data.add_credits(refund)
	GameLog.post("New ship: %s (traded in your %s%s)" % [st["name"], old["name"], (", modules sold for %d dr" % refund) if refund > 0 else ""], "good")
	data.changed.emit()
	ship.hull = ship.max_hull   # (a new ship: its hull whole)
	ship.recharge_shields()


func _buy_item(id: String, amount: int, price: int) -> void:
	if data.spend(price):
		GameLog.post("Bought %d %s for %d dr" % [amount, Items.display_name(id), price], "info")
		data.add_item(id, amount)


func _buy_equipment(id: String, price: int) -> void:
	if data.spend(price):
		GameLog.post("Installed %s (%d dr)" % [Items.EQUIPMENT[id]["name"], price], "good")
		data.add_equipment(id)


# --- Sell --------------------------------------------------------------------------

func _page_sell() -> void:
	# Compact cards, four to a row (the page never scrolls); "Sell all" on top.
	var total := 0
	var sellable := []
	for id in data.held_items():
		var it: Dictionary = Items.info(id)
		if it["kind"] == "quest":
			continue  # story items can't be sold
		sellable.append(id)
		if it["kind"] == "cargo":
			total += _sell_value(id) * data.count(id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var sec := UI.section("CARGO MARKET  ·  this station's prices")
	sec.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(sec)
	var all := EditorIcons.action(UI.button("", _sell_all_cargo, 16), "sellall", "+%d" % total, EditorIcons.tip("Sell all cargo", "", "Sells every trade good and piece of loot in your hold for %d drachmas in total.\nKeeps your missiles, gear and story items." % total))
	all.disabled = total == 0
	all.custom_minimum_size = Vector2(300, 40)
	head.add_child(all)
	_content.add_child(head)
	if sellable.is_empty():
		_content.add_child(UI.label("Cargo hold is empty. Destroy enemies to collect loot.", 16, UI.TEXT_DIM))
		return
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	for id in sellable:
		var it: Dictionary = Items.info(id)
		var n: int = data.count(id)
		var each := _sell_value(id)
		var one := EditorIcons.action(UI.button("", _sell_item.bind(id, 1), 12), "sell", "1", EditorIcons.tip("Sell 1 %s" % it["name"], "", "Sells one for %d drachmas at this station's price." % each))
		var every := EditorIcons.action(UI.button("", _sell_item.bind(id, n), 12), "sellall", str(n), EditorIcons.tip("Sell all %s" % it["name"], "", "Sells all %d for %d drachmas." % [n, each * n]))
		var sub := "%d dr each  ·  %d total" % [each, each * n]
		if NavReports.is_report(id):   # (worth more the further from its system; nothing in it)
			var j := NavReports.jumps(NavReports.system_of(id), _here_system())
			sub = ("%d dr  ·  %d %s from %s" % [each, j, "jump" if j == 1 else "jumps", NavReports.name_of(NavReports.system_of(id))]) if each > 0 else "Worthless here: its own system"
			for bt in [one, every]:
				bt.disabled = each <= 0
		var card := _card(id, "%s  ×%d" % [it["name"], n], sub, it.get("desc", ""), [one, every])
		for bt in [one, every]:
			bt.custom_minimum_size = Vector2(56, 34)
		grid.add_child(card)


## This station's system.
func _here_system() -> String:
	return str(Galaxy.stations.get(station.station_id, {}).get("system", Galaxy.current_system))


## What this station pays for one unit (live market price for trade goods; a
## navigation report by how far its system is from here).
func _sell_value(id: String) -> int:
	if NavReports.is_report(id):
		return NavReports.price(NavReports.system_of(id), _here_system())
	if Galaxy.stations.has(station.station_id) and id in Galaxy.COMMODITIES:
		return Galaxy.sell_price(station.station_id, id)
	return Items.info(id)["value"]


func _sell_item(id: String, n: int) -> void:
	if Galaxy.stations.has(station.station_id) and id in Galaxy.COMMODITIES:
		var earned := Galaxy.player_sell(station.station_id, id, n, data)
		if earned > 0:
			GameLog.post("Sold %d %s for %d dr" % [n, Items.display_name(id), earned], "loot")
		return
	var each := _sell_value(id)
	if NavReports.is_report(id) and each <= 0:
		return   # (worthless in its own system)
	if data.remove_item(id, n):
		GameLog.post("Sold %d %s for %d dr" % [n, Items.display_name(id), each * n], "loot")
		data.add_credits(each * n)


func _sell_all_cargo() -> void:
	for id in data.held_items():
		if Items.info(id)["kind"] == "cargo":
			_sell_item(id, data.count(id))


# --- Missions ----------------------------------------------------------------------

func _page_missions() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	_content.add_child(cols)

	var avail := VBoxContainer.new()
	avail.size_flags_horizontal = SIZE_EXPAND_FILL   # (the offers take the room the active list doesn't need)
	avail.add_theme_constant_override("separation", 10)
	cols.add_child(avail)
	avail.add_child(UI.section("MISSIONS AT %s" % station.station_name.to_upper()))
	var e: String = station.empire
	if e != "":
		avail.add_child(UI.label("Your reputation with the %s: %d  ·  better missions need more" % [Galaxy.empire_name(e), int(Galaxy.reputation.get(e, 0.0))], 14, UI.TEXT_DIM))
	if station.health() < Galaxy.DAMAGED:
		var crisis := UI.label("THE STATION IS BURNING (%d%%): only repair and defence jobs until it's mended. Repairs raise your standing with the %s." % [int(station.health()), Galaxy.empire_name(e)], 15, Color(1.0, 0.55, 0.3))
		crisis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		avail.add_child(crisis)
	var full: bool = missions.active.size() >= missions.MAX_ACTIVE
	# The ones you can take first, then the ones you aren't trusted with yet (greyed out).
	var list: Array = missions.offers_for(station.station_name, e).duplicate()
	list.sort_custom(func(a, b): return int(missions.available(a)) * 10 - int(a.get("tier", 0)) > int(missions.available(b)) * 10 - int(b.get("tier", 0)))
	# Two columns of offers: the page never scrolls.
	var offer_grid := GridContainer.new()
	offer_grid.columns = 2
	offer_grid.add_theme_constant_override("h_separation", 12)
	offer_grid.add_theme_constant_override("v_separation", 4)
	avail.add_child(offer_grid)
	for m in list:
		var ok: bool = missions.available(m)
		var b := EditorIcons.dress(UI.button("", _accept.bind(m), 15), "accept", EditorIcons.tip("Accept mission", "",
			("Takes this mission (up to %d at a time). Its goal and progress appear under ACTIVE MISSIONS\nand at the top right of the screen; finishing it pays the reward and raises your reputation with the %s." % [missions.MAX_ACTIVE, Galaxy.empire_name(e)]) if ok
			else ("Not available: " + missions.required_text(m) + ".\nFinish missions for them (or fight their enemies) to earn their trust.")))
		b.disabled = full or not ok
		var card := _mission_card(m, [b], "" if ok else missions.required_text(m), not ok)
		card.custom_minimum_size.x = 420
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		offer_grid.add_child(card)
	if full:
		avail.add_child(UI.label("You already have %d active missions." % missions.MAX_ACTIVE, 14, Color(1, 0.6, 0.5)))

	var act := VBoxContainer.new()
	act.custom_minimum_size = Vector2(380, 0)
	act.add_theme_constant_override("separation", 10)
	cols.add_child(act)
	act.add_child(UI.section("ACTIVE MISSIONS  (%d / %d)" % [missions.active.size(), missions.MAX_ACTIVE]))
	if missions.active.is_empty():
		act.add_child(UI.label("No active missions.", 15, UI.TEXT_DIM))
	for m in missions.active:
		var buttons := []
		if missions.can_turn_in(m, station.station_name):
			buttons.append(EditorIcons.dress(UI.button("", _turn_in.bind(m), 15), "turnin", EditorIcons.tip("Turn in", "", "Completes the mission here and collects its reward (delivered items are taken from your cargo).")))
		buttons.append(EditorIcons.dress(UI.button("", _abandon.bind(m), 15), "abandon", EditorIcons.tip("Abandon", "", "Gives up this mission: it's removed from your list and frees a slot. No penalty, no reward.")))
		act.add_child(_mission_card(m, buttons, missions.progress_text(m)))


# --- Main quests ---------------------------------------------------------------------

func _page_main_quests() -> void:
	var gold := Color(1.0, 0.82, 0.38)
	_content.add_child(UI.section("MAIN QUESTS", gold))
	var card := {"title": "The Thread of Ariadne",
		"desc": "For three nights a strange spiral signal has repeated across the sector, and Kephala Outpost is asking independent pilots for help. A story of Bronze Age Crete: the Minoans, Linear A, the Minotaur, Daedalus, Talos and the Labyrinth of Knossos.",
		"reward_text": "story campaign in 7 chapters  ·  drachmas, Data Cores, equipment and history entries"}
	if quest.stage < 0:
		# Kilon Alios gives it, in person (QuestData.GIVER, planet_surface.gd).
		var g: Dictionary = QuestData.GIVER
		_content.add_child(_mission_card(card, [], "Offered by %s: land on %s and talk to him by the landing pad." % [g["name"], Planets.get_planet(str(g["planet"]))["name"]]))
	elif quest.finished:
		_content.add_child(_mission_card(card, [], "Completed - the archive awaits."))
	else:
		_content.add_child(_mission_card(card, [], "%s  -  %s" % [quest.chapter_title(), quest.objective_text()]))
		_content.add_child(UI.label("In progress. Press Tab and open the QUEST tab for the full journal.", 14, UI.TEXT_DIM))


# --- Shared cards ---------------------------------------------------------------------

func _mission_card(m: Dictionary, buttons: Array, progress: String, locked := false) -> Control:
	var panel := PanelContainer.new()
	if locked:   # greyed out: the empire doesn't trust you with it yet
		panel.modulate = Color(0.55, 0.55, 0.6, 0.75)
	var style := UI.panel_style(Color(0.3, 0.5, 0.7, 0.6))
	style.bg_color = NeonTheme.BG_LIGHT
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	# The contact offering the job.
	var giver := Portrait.new().setup(str(m.get("title", "")) + str(m.get("giver", "")), station.empire if station else "athens")
	giver.custom_minimum_size = Vector2(52, 62)
	giver.size_flags_vertical = SIZE_SHRINK_BEGIN   # (its own size, at the top - not stretched down a tall card)
	giver.tooltip_text = "%s (%s)" % [giver.person_name, giver.species_name()]
	row.add_child(giver)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	var tier: int = int(m.get("tier", -1))
	var tname: String = ("  ·  " + missions.TIERS[tier]["name"].to_upper()) if tier >= 0 and m.has("empire") else ""
	var title := UI.label(m["title"] + tname, 17, [Color.WHITE, NeonTheme.INFO, Color(0.75, 0.6, 1.0), UI.GOLD][maxi(tier, 0)] if tname != "" else Color.WHITE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title)
	text.custom_minimum_size.x = 240
	if locked:   # (not yours to take yet: what it needs, the rest in the tooltip - a compact card)
		panel.tooltip_text = str(m["desc"])
	else:
		var desc := UI.label(m["desc"], 13, UI.TEXT_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# (two lines at most - the whole of it in the card's tooltip: a station
		# with long offers at large text made the page scroll)
		desc.max_lines_visible = 2
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		panel.tooltip_text = str(m["desc"])
		text.add_child(desc)
	if progress != "":
		var pl := UI.label(progress, 14, Color(1.0, 0.55, 0.45) if locked else NeonTheme.HEAD)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(pl)
	# The reward, and the card's buttons beside it (not a column of their own:
	# the text gets the card's width).
	var reward: String = m["reward_text"] if m.has("reward_text") else missions.reward_text(m)
	# (a flow: in a narrow card - the active list, two buttons - the buttons
	# drop under the reward instead of squeezing it to a letter a line)
	var foot := HFlowContainer.new()
	foot.add_theme_constant_override("h_separation", 8)
	foot.add_theme_constant_override("v_separation", 4)
	var rl := UI.label("Reward: " + reward, 14, UI.GOLD)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.size_flags_horizontal = SIZE_EXPAND_FILL
	rl.custom_minimum_size.x = minf(rl.get_theme_font("font").get_string_size(rl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4.0, 200.0)
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(rl)
	for b in buttons:
		b.custom_minimum_size = Vector2(100, 32)
		b.size_flags_vertical = SIZE_SHRINK_END
		foot.add_child(b)
	text.add_child(foot)
	row.add_child(text)
	return panel


func _accept(m: Dictionary) -> void:
	missions.accept(m)


func _turn_in(m: Dictionary) -> void:
	missions.turn_in(m)


func _abandon(m: Dictionary) -> void:
	missions.abandon(m)


# --- Shared ------------------------------------------------------------------------

func _item_row(id: String, n: int, title: String, subtitle: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := ItemSlot.make(id, n, 48.0)
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(UI.label(title, 16))
	var sub := UI.label(subtitle, 13, UI.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sub)
	row.add_child(text)
	return row
