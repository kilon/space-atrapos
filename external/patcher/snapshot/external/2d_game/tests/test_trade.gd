extends TestCase
## The commodity market and trade routes (TradeRoutes, MarketPage, the maps'
## trade layers) and the controls (Keybinds: bindings, saving, menu
## navigation).


func test_trade_routes() -> void:
	Galaxy.new_game(false)
	check(TradeRoutes.galaxy_routes("", 2, 10).is_empty(), "no market known yet: no routes")
	for sid in Galaxy.stations:
		Galaxy.visit_station(sid)   # (docked everywhere: every market known)
	TradeRoutes.invalidate()
	var t := TradeRoutes.table()
	check_eq(t.size(), Galaxy.stations.size(), "a price row for every station")
	var sid: String = Galaxy.stations.keys()[0]
	check(t[sid]["food"][0] >= t[sid]["food"][1], "a station asks at least what it pays")
	check(TradeRoutes.average("food") > 0, "a galactic average")
	var all := 0
	for cat in TradeRoutes.CATEGORIES:
		all += cat[1].size()
	check_eq(all, Galaxy.COMMODITIES.size(), "every good in one category")
	var runs := TradeRoutes.galaxy_routes("", 2, 10)
	check(not runs.is_empty(), "profitable runs across systems")
	var seen := {}
	for r in runs:
		check(r["from_sys"] != r["to_sys"], "galaxy runs leave the system")
		check(r["jumps"] >= 1 and r["jumps"] <= 2, "within two jumps")
		check_eq(r["profit"], r["sell"] - r["buy"], "profit = sell there - buy here")
		check(r["profit"] >= TradeRoutes.MIN_PROFIT, "worth the trip")
		check(TradeRoutes.open_to_player(r["to"]), "never to a system that shoots you")
		var key: String = r["from_sys"] + ">" + r["to_sys"]
		check(not seen.has(key), "one run per system pair")
		seen[key] = true
	for i in runs.size() - 1:
		check(runs[i]["profit"] >= runs[i + 1]["profit"], "best first")
	var food := TradeRoutes.galaxy_routes("food", 2, 10)
	for r in food:
		check_eq(r["item"], "food", "filtered to one good")
	var here := TradeRoutes.stations_of([Galaxy.HOME])
	for r in TradeRoutes.routes_from(here, 0, "", 6):
		check_eq(r["to_sys"], Galaxy.HOME, "zero jumps: inside the system")
	check(TradeRoutes.supply_bars(sid, "food") in [0, 1, 2, 3], "supply bars 0..3")


func test_market_page() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	main.player_data.add_credits(5000)
	main.station_menu.open(st)
	main.station_menu.show_tab(1)
	var page = main.station_menu.market_page()
	check(page != null, "the market page shows")
	MarketPage.selected = "food"
	MarketPage.qty = 3
	var before: int = main.player_data.count("food")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	check(main.station_menu.market_page().handle_key(key), "Enter buys")
	check_eq(main.player_data.count("food"), before + 3, "bought the quantity")
	key.keycode = KEY_S
	main.station_menu.market_page().handle_key(key)
	check_eq(MarketPage.selected, "water", "S: the next good")
	main.station_menu.close()
	main.queue_free()
	await tree.process_frame


func test_keybinds() -> void:
	Keybinds.reset()
	var e := InputEventKey.new()
	e.keycode = KEY_E
	e.pressed = true
	check(Keybinds.pressed(e, "dock"), "E docks by default")
	Keybinds.set_bind("dock", 0, "k:K")
	check(not Keybinds.pressed(e, "dock"), "rebound: E no more")
	e.keycode = KEY_K
	check(Keybinds.pressed(e, "dock"), "K now")
	Keybinds.load_binds()
	check_eq(Keybinds.binds["dock"][0], "k:K", "saved and loaded")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	pad.pressed = true
	check(Keybinds.pressed(pad, "dock"), "pad Y docks")
	pad.button_index = JOY_BUTTON_A
	check(pad.is_action_pressed("ui_accept"), "pad A presses focused buttons (ui_accept)")
	check(Keybinds.clashes("attack", "k:F").is_empty(), "no clash by default")
	Keybinds.set_bind("hail", 0, "k:K")
	check("hail" in Keybinds.clashes("dock", "k:K"), "a clash is found")
	# A trigger counts once per pull.
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_TRIGGER_RIGHT
	m.axis_value = 0.9
	check(Keybinds.pressed(m, "attack"), "RT pulled: attack")
	check(not Keybinds.pressed(m, "attack"), "held: not again")
	m.axis_value = 0.0
	Keybinds._input(m)
	m.axis_value = 0.9
	check(Keybinds.pressed(m, "attack"), "released and pulled: again")
	Keybinds.reset()
	check_eq(Keybinds.binds["dock"], Keybinds.defaults("dock"), "reset")
	check_eq(Keybinds.spec_text("p:10"), "RB", "pad names")
	check_eq(Keybinds.spec_of(e), "k:K", "a key's slot string")
	# Keys with modifiers: Shift+D undocks; plain D doesn't (and Shift+D isn't D).
	var sd := InputEventKey.new()
	sd.keycode = KEY_D
	sd.shift_pressed = true
	sd.pressed = true
	check(Keybinds.pressed(sd, "undock"), "Shift+D undocks")
	check(not Keybinds.pressed(sd, "menu_right"), "Shift+D isn't D")
	check(Keybinds.pressed_loose(sd, "menu_right"), "but loosely it is (the market's step of 10)")
	sd.shift_pressed = false
	check(not Keybinds.pressed(sd, "undock"), "plain D doesn't undock")
	sd.shift_pressed = true
	check_eq(Keybinds.spec_of(sd), "k:Shift+D", "a key with a modifier, as a slot string")
	var q := InputEventKey.new()
	q.keycode = KEY_E
	q.pressed = true
	check(Keybinds.pressed(q, "menu_tab_next"), "E: next tab")


func test_menu_nav() -> void:
	var menu := VBoxContainer.new()
	menu.size = Vector2(300, 300)
	tree.root.add_child(menu)
	var a := Button.new()
	a.text = "a"
	var b := Button.new()
	b.text = "b"
	menu.add_child(a)
	menu.add_child(b)
	Keybinds.register_menu(menu)
	await tree.process_frame
	check(Keybinds.active_menu() == menu, "the open menu")
	var s := InputEventKey.new()
	s.keycode = KEY_S
	s.pressed = true
	Keybinds._unhandled_input(s)
	check(a.has_focus(), "the first press focuses the first button")
	Keybinds._unhandled_input(s)
	check(b.has_focus(), "S moves down")
	var w := s.duplicate()
	w.keycode = KEY_W
	Keybinds._unhandled_input(w)
	check(a.has_focus(), "W moves up")
	menu.queue_free()
	await tree.process_frame


func test_waypoints() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var ship: Node2D = main.ship
	var p0: Vector2 = ship.global_position
	ship.move_to(p0 + Vector2(400, 0))
	ship.add_waypoint(p0 + Vector2(400, 400))
	ship.add_waypoint(p0 + Vector2(0, 400))
	check_eq(ship.course().size(), 3, "a course of three points")
	var d: Dictionary = ship.get_save_data()
	ship.waypoints.clear()
	ship.load_save_data(d)
	check_eq(ship.waypoints.size(), 2, "waypoints saved and loaded")
	var passed := [0]
	ship.waypoint_passed.connect(func(): passed[0] += 1)
	for i in 900:
		await tree.physics_frame
		if not ship.has_target:
			break
	check_eq(passed[0], 2, "passed both waypoints")
	check(not ship.has_target and ship.global_position.distance_to(p0 + Vector2(0, 400)) < 200.0, "stopped at the last")
	ship.move_to(p0)
	ship.add_waypoint(p0 + Vector2(10, 10))
	ship.move_to(p0 + Vector2(50, 0))
	check(ship.waypoints.is_empty(), "a plain click replaces the course")
	# The galaxy map: Shift + click extends the route.
	Galaxy.route = []
	var gp = load("res://scripts/pages/galaxy_page.gd").new()
	gp.ship = ship
	tree.root.add_child(gp)
	await tree.process_frame
	gp.add_to_route("klotho")
	check_eq(Galaxy.route, [Galaxy.current_system, "klotho"], "first leg")
	gp.add_to_route("erebos")
	check_eq(Galaxy.route[-1], "erebos", "extended")
	check_eq(Galaxy.route[1], "klotho", "through the waypoint")
	Galaxy.route = []
	gp.queue_free()
	main.queue_free()
	await tree.process_frame


func test_drag_waypoint() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var ship: Node2D = main.ship
	var p0: Vector2 = ship.global_position
	ship.move_to(p0 + Vector2(800, 0))
	ship.add_waypoint(p0 + Vector2(800, 800))
	var view = load("res://scripts/pages/map_page.gd").MapView.new()
	view.page = load("res://scripts/pages/map_page.gd").new()
	view.ship = ship
	view.size = Vector2(1000, 600)
	view.center = p0
	view.scale_ = 0.2
	tree.root.add_child(view)
	await tree.process_frame
	var at: Vector2 = view.to_screen(p0 + Vector2(800, 800))
	check_eq(view._course_point_at(at), 1, "the waypoint under the cursor")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.shift_pressed = true
	press.position = at
	view._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = at + Vector2(50, -20)
	move.shift_pressed = true
	view._gui_input(move)
	var up := press.duplicate()
	up.pressed = false
	up.position = move.position
	view._gui_input(up)
	check(ship.waypoints[0].distance_to(view.to_world(at + Vector2(50, -20))) < 1.0, "dragged to the new place")
	check_eq(ship.waypoints.size(), 1, "moved, not added")
	view.page.free()
	view.queue_free()
	main.queue_free()
	await tree.process_frame


func test_station_names() -> void:
	Galaxy.new_game(false)
	var seen := {}
	for sid in Galaxy.stations:
		var st: Dictionary = Galaxy.stations[sid]
		check(not seen.has(st["name"]), "no two stations share a name (%s)" % st["name"])
		seen[st["name"]] = true
		var sys: Dictionary = Galaxy.SYSTEMS[st["system"]]
		var i := int(sid.get_slice(":", 1))
		if st["system"] == Galaxy.HOME or sys["owner"] == "pirates" or Galaxy.station_owner(sid) != sys["owner"]:
			continue   # (guests - independents, outposts - have names of their own: test_reputation)
		if i == 0:
			check(st["name"].begins_with(sys["name"]), "the first station bears the system's name (%s)" % st["name"])
		else:
			check(st["name"].get_slice(" ", 0) in Galaxy.STATION_ROOTS[sys["owner"]], "the others an empire's hero, person, landmark or city (%s)" % st["name"])


## Selling all cargo with a full hold of every kind of good and loot: one
## rebuild of the page, not one per good (dozens of rebuilds in one click,
## from inside the button's own signal, overflowed Godot's message queue and
## crashed the game).
func test_sell_all_cargo_with_a_big_hold() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	for i in 5:
		await tree.process_frame
	var data: Node = main.player_data
	var kinds := 0
	for id in Items.ITEMS:
		if Items.info(id)["kind"] == "cargo":
			data.items[id] = 3
			kinds += 1
	data.changed.emit()
	check(kinds > 100, "a hold of %d kinds of cargo" % kinds)
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	var sm: Node = main.station_menu
	sm.open(st)
	sm.show_tab(sm.TABS.find("SELL"))
	await tree.process_frame
	var builds := [0]
	sm._content.child_entered_tree.connect(func(_n): builds[0] += 1)
	var before: int = data.credits
	sm._sell_all_cargo()
	await tree.process_frame
	await tree.process_frame
	var left: Array = data.held_items().filter(func(id): return Items.info(id)["kind"] == "cargo")
	check(left.is_empty(), "all of it sold (%d kinds left)" % left.size())
	check(data.credits > before, "for drachmas (%d -> %d)" % [before, data.credits])
	check(builds[0] < 10, "the page rebuilt once (%d nodes added to it), not once per good" % builds[0])
	sm.close()
	main.queue_free()
	await tree.process_frame
