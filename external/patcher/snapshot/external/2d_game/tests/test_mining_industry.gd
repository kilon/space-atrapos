extends TestCase
## Mining by hand (Mining, Asteroid veins): prospecting shows a rock's
## composition and veins; cutting a vein in its heat band gives fragments,
## overheating fractures it; an unscanned rock gives rubble. The ship's
## industry (Industry): the refinery turns fragments into minerals, the
## fabricator makes things, Upgrade Kits fit upgrades. The probe scanner (ProbeScanner).

var _main: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}


func _game() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 30:
		await tree.process_frame
	_main.ship.invulnerable = true


func test_veins() -> void:
	var g := Mining.generate("platinum", 90.0, 1200, 42)
	check(g["veins"].size() >= 2 and g["veins"].size() <= 5, "a few veins (%d)" % g["veins"].size())
	var sum := 0.0
	for m in g["comp"]:
		sum += float(g["comp"][m])
	check(absf(sum - 1.0) < 0.01 and g["comp"].size() >= 4, "a composition of several minerals")
	check_eq(g["veins"][0]["mineral"], "platinum_ore", "the first vein its main mineral")
	check_eq(Mining.generate("platinum", 90.0, 1200, 42)["veins"][1]["a"], g["veins"][1]["a"], "the same rock, the same veins")
	check(Mining.cut_rate(0.1) == 0.0 and Mining.cut_rate(0.7) == 1.0 and Mining.cut_rate(0.9) < 1.0, "cold: nothing; the band: full; too hot: less")
	check(Mining.valid("frag:iron_ore") and Items.exists("frag:gold_ore") and not Mining.valid("frag:nothing"), "fragments are items")
	check(int(Items.info("frag:platinum_ore")["value"]) < int(Items.info("platinum_ore")["value"]), "worth less than refined")


func test_cutting() -> void:
	await _game()
	var ship: Node2D = _main.ship
	var rock: Asteroid = null
	for r in _main.asteroids.get_children():
		if r.kind != "ice":
			rock = r
			break
	ship.global_position = rock.global_position + Vector2(0, 300)
	ship.rotation = 0.0
	ship.stop()
	ship.set_attack_target(rock)
	# Unscanned: rubble only.
	ship.mining_hold = true
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await tree.process_frame
	check(ship.mining_last == "bulk", "unscanned: hacking at the bulk")
	# Prospected: the veins.
	rock.scanned = true
	ship.mining_vein = 0
	var v: Dictionary = rock.veins[0]
	var units: int = v["units"]
	# Held on and on: it overheats and fractures.
	var fractured := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000 and not fractured:
		await tree.process_frame
		fractured = fractured or ship.mining_last == "fracture"
	check(fractured, "held on too long: the vein fractures")
	check(int(v["units"]) < units, "and loses ore (%d -> %d)" % [units, int(v["units"])])
	ship.mining_hold = false
	# The autopilot keeps it in the band: fragments, resonance.
	ship.mining_auto = true
	units = int(v["units"])
	var max_res := 1.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
		max_res = maxf(max_res, float(v["res"]))
	check(int(v["units"]) < units, "kept in the band: it cuts (%d -> %d)" % [units, int(v["units"])])
	check(max_res > 1.2, "and resonance builds (x%.2f)" % max_res)
	ship.mining_auto = false
	var saved := rock.get_save_data()
	var copy := Asteroid.new().setup(saved)
	check_eq(int(copy.veins[0]["units"]), int(v["units"]), "the veins' ore saved")
	copy.free()


func test_industry() -> void:
	await _game()
	var pd: Node = _main.player_data
	var rng := RandomNumberGenerator.new()
	pd.add_item("frag:copper_ore", 6)
	check(not Industry.order(pd, "refine", "frag:copper_ore", 3), "no refinery: nothing")
	pd.add_equipment("refinery")
	pd.add_equipment("fabricator")
	check(Industry.order(pd, "refine", "frag:copper_ore", 6), "refining ordered")
	check_eq(pd.count("frag:copper_ore"), 0, "the fragments taken")
	for i in 40:
		Industry.tick(pd, 0.5, rng)
	check_eq(pd.count("copper_ore"), 6, "six copper ore refined")
	pd.add_item("tin_ore", 2)
	check_eq(Industry.can_make(pd.items, "bronze_ingots"), 2, "enough for two bronze ingots")
	check(Industry.order(pd, "fab", "bronze_ingots", 2), "made")
	Industry.cancel(pd, 0)
	check(pd.count("copper_ore") == 6 and pd.count("tin_ore") == 2, "cancelled: given back")
	Industry.order(pd, "fab", "bronze_ingots", 2)
	for i in 40:
		Industry.tick(pd, 0.5, rng)
	check_eq(pd.count("bronze_ingots"), 2, "two bronze ingots made")
	check(int(Items.info("bronze_ingots").get("value", 0)) > 0, "the markets buy them")
	for id in Industry.RECIPES:
		var r: Array = Industry.RECIPES[id]
		check(Items.exists(r[2][0]), "%s makes a real item (%s)" % [id, r[2][0]])
		for k in r[3]:
			check(Items.exists(k), "%s takes a real item (%s)" % [id, k])
	# A kit fits an upgrade.
	pd.add_item("upkit_1", 1)
	check(Industry.fit_kit(pd, "upkit_1", "ship", "engines:speed_mult"), "a Mk I kit fitted")
	check_eq(Upgrades.level(pd.upgrades, "ship", "engines:speed_mult"), 1, "speed: level 1")
	pd.add_item("upkit_3", 1)
	check(not Industry.fit_kit(pd, "upkit_3", "ship", "engines:speed_mult"), "a Mk III doesn't fit a level 1 stat")


func test_probes() -> void:
	await _game()
	var ps: ProbeScanner = _main.probes
	check(not ps.fitted(), "no probe scanner at first")
	_main.player_data.add_equipment("probe_scanner")
	check(ps.fitted(), "bought: fitted")
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	var wide := ps.strength_of(st.global_position + Vector2(9000, 0), "anomaly")
	ps.probes = [{"pos": st.global_position + Vector2(6000, 0), "r": 16000.0, "at": st.global_position}]
	var one_wide := ps.strength_of(st.global_position, "anomaly")
	ps.probes = [{"pos": st.global_position + Vector2(300, 0), "r": 1000.0, "at": st.global_position}]
	var one_tight := ps.strength_of(st.global_position, "anomaly")
	check(one_tight > one_wide, "tight probes read stronger (%.2f > %.2f)" % [one_tight, one_wide])
	check(ps.strength_of(st.global_position, "body") > one_tight, "a planet is easier than an anomaly")
	check_eq(wide, 0.0, "nothing read without probes")
	ps.launch_pattern(st.global_position, 2000.0)
	for p in ps.probes:
		p["at"] = p["pos"]
	ps.analyze()
	ps._process(ProbeScanner.ANALYZE_TIME + 0.1)
	var r: Array = ps.results.filter(func(x): return x["node"] == st)
	check(r.size() == 1 and float(r[0]["strength"]) >= 1.0, "the station: located")
	check_eq(ProbeScanner.label(r[0]), st.station_name, "named")
	check(ps.signatures().any(func(x): return x["kind"] in ["hostile", "neutral"]), "ships show as signatures")



## The probes moved as a group on the map: Shift + drag a probe, or drag the handle
## above them; the wheel over the handle spreads them; Shift + wheel: every reach.
func test_probes_move_as_a_group() -> void:
	await _game()
	var ps: ProbeScanner = _main.probes
	_main.player_data.add_equipment("probe_scanner")
	tree.current_scene = _main   # (the map finds the probe scanner on the scene)
	var cm = _main.ship_menu
	_main._open_panel(cm, cm.MAP_TAB)
	await tree.process_frame
	var mp = cm.page(cm.MAP_TAB)
	mp.show_probes(true)
	var view = mp._view
	view.size = Vector2(1200, 800)
	var c: Vector2 = _main.ship.global_position + Vector2(3000, 0)
	ps.launch_pattern(c, 2000.0)
	for p in ps.probes:
		p["at"] = p["pos"]
	view.center = c
	view.scale_ = 0.05
	var before: Array = ps.probes.map(func(p): return p["pos"])
	var press := func(at: Vector2, down: bool, shift := false, button := MOUSE_BUTTON_LEFT):
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.shift_pressed = shift
		e.position = at
		view._gui_input(e)
	var move := func(at: Vector2, shift := false):
		var e := InputEventMouseMotion.new()
		e.position = at
		e.shift_pressed = shift
		view._gui_input(e)
	# Shift + drag the second probe: all of them move the same way.
	var p1: Vector2 = view.to_screen(ps.probes[1]["at"])
	press.call(p1, true, true)
	move.call(p1 + Vector2(100, 40), true)
	press.call(p1 + Vector2(100, 40), false, true)
	var d: Vector2 = Vector2(100, 40) / view.scale_
	var all_moved := true
	for i in ps.probes.size():
		if ((ps.probes[i]["pos"] as Vector2) - (before[i] as Vector2) - d).length() > 1.0:
			all_moved = false
	check(all_moved, "Shift + drag a probe: the whole group moved by %s" % d)
	# The handle in their middle: drag it, they all follow.
	var mid: Vector2 = view._group_handle_pos()
	check(view._group_handle_at(mid) and view._probe_at(mid) < 0, "a handle above the probes, clear of them")
	var at0: Vector2 = ps.probes[0]["pos"]
	press.call(mid, true)
	move.call(mid + Vector2(-50, 0))
	press.call(mid + Vector2(-50, 0), false)
	check((((ps.probes[0]["pos"] as Vector2) - at0) - Vector2(-50, 0) / view.scale_).length() < 1.0, "dragging the handle moves them all")
	# A plain drag of one probe still moves just that one.
	var lone: Vector2 = ps.probes[0]["pos"]   # (the middle one: its marker clear of the others' rims)
	var other: Vector2 = ps.probes[3]["pos"]
	var p2: Vector2 = view.to_screen(ps.probes[0]["at"])
	press.call(p2, true)
	move.call(p2 + Vector2(0, 60))
	press.call(p2 + Vector2(0, 60), false)
	check(((ps.probes[0]["pos"] as Vector2) - lone).length() > 1.0 and ((ps.probes[3]["pos"] as Vector2) - other).length() < 1.0, "a plain drag moves only that probe")
	# The wheel over the handle: spread out round the middle.
	var g: Vector2 = view._group_centre()
	var spread0: float = (ps.probes[1]["pos"] as Vector2).distance_to(g)
	press.call(view._group_handle_pos(), true, false, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx((ps.probes[1]["pos"] as Vector2).distance_to(g), spread0 * 1.25), "the wheel over the handle spreads them (x1.25)")
	# Shift + wheel over a probe: every probe's reach a step.
	var r0: Array = ps.probes.map(func(p): return p["r"])
	press.call(view.to_screen(ps.probes[0]["at"]), true, true, MOUSE_BUTTON_WHEEL_UP)
	var all_up := true
	for i in ps.probes.size():
		if float(ps.probes[i]["r"]) <= float(r0[i]):
			all_up = false
	check(all_up, "Shift + wheel over a probe: every reach a step up")


## The mining readout shows while you mine - not for as long as a rock is your target.
func test_mining_panel_only_while_mining() -> void:
	await _game()
	var ship: Node2D = _main.ship
	var panel: Control = _main.hud.mining_panel
	var rock: Asteroid = _main.asteroids.get_child(0)
	ship.global_position = rock.global_position + Vector2(0, 300)
	ship.stop()
	ship.set_attack_target(rock)
	ship.mining_hold = false
	ship.mining_at = -1000.0
	for i in 5:
		await tree.process_frame
	check(not panel.visible, "a rock targeted, the laser not on it: no panel")
	ship.mining_hold = true
	for i in 5:
		await tree.process_frame
	check(panel.visible, "holding the button on it: the panel")
	ship.mining_hold = false
	ship.mining_at = Time.get_ticks_msec() / 1000.0
	for i in 3:
		await tree.process_frame
	check(panel.visible, "let go: it stays a moment")
	ship.mining_at = Time.get_ticks_msec() / 1000.0 - MiningPanel.LINGER - 0.1
	for i in 3:
		await tree.process_frame
	check(not panel.visible, "a few seconds later: gone, though the rock is still the target")
	ship.mining_hold = true
	ship.global_position = rock.global_position + Vector2(0, MiningPanel.REACH + 200.0)
	for i in 3:
		await tree.process_frame
	check(not panel.visible, "flown off: gone")
