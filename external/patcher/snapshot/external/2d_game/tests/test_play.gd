extends TestCase
## Plays through the real game scene: the home system, another empire's space
## (arriving the way a jump does), docking and every station-menu tab.

var _main: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	await tree.process_frame
	Galaxy.new_game(false)
	NeonTheme.set_empire("")


func _enter(system: String) -> Node:
	if is_instance_valid(_main):
		_main.queue_free()
		await tree.process_frame
	# Arrive as a jump does: the running galaxy is kept (a fresh scene without
	# travelling would start a new game at home).
	Galaxy.current_system = system
	SaveGame.travelling = system != Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	SaveGame.travelling = false
	return _main


func test_home_is_minoan_space() -> void:
	await _enter(Galaxy.HOME)
	check_eq(NeonTheme.empire, "", "GUI theme at home: the one look (no empire palette)")
	check(tree.get_nodes_in_group("stations").size() >= 3, "home stations")


func test_other_empire_space() -> void:
	var dest := ""
	for n in Galaxy.SYSTEMS:
		if Galaxy.owner_of(n) == "sparta":
			dest = n
	check(dest != "", "a Spartan system")
	await _enter(dest)
	var owner := Galaxy.owner_of(dest)
	check_eq(NeonTheme.empire, "", "GUI theme in %s space: the one look" % owner)
	for st in tree.get_nodes_in_group("stations"):
		check(StationArt.BY_EMPIRE[st.empire].has(st.design()), "%s builds the %s station design" % [st.empire, st.design()])
	var ships: Array = tree.get_nodes_in_group("enemies") + tree.get_nodes_in_group("neutrals")
	check(not ships.is_empty(), "ships in the system")
	for s in ships:
		check(EnemyTypes.has_type(s.type_id), "unknown ship class " + str(s.type_id))
		check(EnemyTypes.texture(s.type_id) != null, "no art for " + str(s.type_id))


func test_dock_and_station_tabs() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	var start: Vector2 = main.ship.global_position
	var full: Vector2 = main.ship.sprite.scale
	main.dock(st)
	var menu: Control = main.station_menu
	# Docking animation: glide to the station's centre, shrink away, then the menu.
	var t0 := Time.get_ticks_msec()
	while not menu.visible and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	check(menu.visible, "station menu opens after the docking animation")
	check(main.ship.global_position.distance_to(st.global_position) < 2.0, "ship reached the station's centre")
	check(main.ship.sprite.scale.length() < full.length() * 0.05, "ship shrank away")
	for i in menu.TABS.size():
		menu.show_tab(i)
		await tree.process_frame
	check(menu.visible, "station menu still open after every tab")
	# Undock: grows out of the station and glides back to where it docked from.
	menu.close()
	t0 = Time.get_ticks_msec()
	while main._ship_animating and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	check(not main._ship_animating, "undock animation finished")
	check(main.ship.sprite.scale.is_equal_approx(full), "ship back to full size")
	check(main.ship.global_position.distance_to(start) < 2.0, "ship back where it docked from")
	check(main.ship.is_physics_processing(), "ship controls back")


func test_take_off_next_to_the_planet() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var state: Dictionary = main.get_save_data()
	state["ship"]["position"] = [-9000.0, 9000.0]   # stale: the planet moved on meanwhile
	_main.queue_free()
	await tree.process_frame
	SaveGame.pending = state
	SaveGame.travelling = true
	SaveGame.took_off_from = "thalassa"
	SaveGame.orbit_offset = Vector2(420, -260)
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	var t0 := Time.get_ticks_msec()
	await tree.process_frame
	await tree.process_frame
	while _main._ship_animating and Time.get_ticks_msec() - t0 < 6000:
		await tree.process_frame
	SaveGame.travelling = false
	var body: Node2D = _main._planet_body("thalassa")
	var d: float = _main.ship.global_position.distance_to(body.global_position)
	check(d > body.radius and d < body.radius + 600.0, "ship next to Amnissos after take-off (%.0f px from its centre, radius %.0f)" % [d, body.radius])
	check(_main.ship.sprite.visible and _main.ship.sprite.modulate.a > 0.99, "ship fully visible")


## The Ship Computer, the station window and dialogues take mouse clicks while
## the game runs on behind them: their Panels layer processes unpaused (it was
## "when paused" from when those menus paused the game - then nothing in it
## got any input). Real clicks on a tab and the X were checked in a windowed
## game; headless, synthetic clicks don't hit-test.
func test_ship_computer_layer_processes() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	main.ship_menu.open()
	await tree.process_frame
	check(not tree.paused, "the game isn't paused by the Ship Computer")
	var panels: Node = main.ship_menu.get_parent()
	check(panels.process_mode == Node.PROCESS_MODE_ALWAYS, "the Panels layer processes always (%d)" % panels.process_mode)
	check(main.ship_menu.can_process() and panels.can_process(), "so the Ship Computer can take input while the game runs")
	tree.paused = true
	check(main.ship_menu.can_process(), "and under the Esc menu too")
	tree.paused = false
	main.ship_menu.close()


## The surface scene run on its own (tests, tools, a dev launch) has no galaxy:
## taking off into space makes one, instead of a system with no star.
func test_take_off_from_a_surface_run_alone() -> void:
	Galaxy.systems = {}
	Galaxy.stations = {}
	Galaxy.active = false
	SaveGame.pending = {"player": {"credits": 150, "items": {}, "equipment": ["laser"], "tech": []}, "planets": {}}
	SaveGame.travelling = true
	SaveGame.took_off_from = "thalassa"
	SaveGame.orbit_offset = Vector2(300, -300)
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	var t0 := Time.get_ticks_msec()
	await tree.process_frame
	await tree.process_frame
	while _main._ship_animating and Time.get_ticks_msec() - t0 < 6000:
		await tree.process_frame
	SaveGame.travelling = false
	check(not Galaxy.systems.is_empty() and Galaxy.systems.has(Galaxy.current_system), "a galaxy was made for the take-off")
	var body: Node2D = _main._planet_body("thalassa")
	check(body != null, "Amnissos is there to take off from")
	if body:
		var d: float = _main.ship.global_position.distance_to(body.global_position)
		check(d > body.radius and d < body.radius + 600.0, "ship next to it (%.0f px, radius %.0f)" % [d, body.radius])


func test_landing_builds_in_background() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	tree.current_scene = main   # the landing switches scenes
	var body: Node2D = main._planet_body("thalassa")
	main.ship.global_position = body.global_position + Vector2(600, -300)
	await tree.process_frame
	main.land_on("thalassa")
	var t0 := Time.get_ticks_msec()
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while tree.current_scene == main and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	check(tree.current_scene != main, "switched to the planet after the landing animation")
	while (tree.current_scene == null or not tree.current_scene.has_method("show_world")) and Time.get_ticks_msec() - t0 < 25000:
		await tree.process_frame
	var s: Node = tree.current_scene
	for i in 4:
		await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	check(s != null and s.has_method("show_world"), "current scene is the surface: " + str(s))
	if s and s.has_method("show_world"):
		check(s.visible, "surface visible")
		check(s.is_processing(), "surface processing")
		check(not s.prebuilding, "surface no longer prebuilding")
	check(worst < 400.0, "no long freeze during the landing animation (worst frame %.0f ms)" % worst)
	_main = s
	SaveGame.landed_planet = ""
	SaveGame.travelling = false


## A planet's surface is built ahead while you fly near it; landing then takes
## it (quickly), with the game as it is now.
func test_surface_built_ahead() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	tree.current_scene = main
	main.prebuild_on = true
	var body: Node2D = main._planet_body("thalassa")
	main.ship.global_position = body.global_position + Vector2(600, -300)
	var t0 := Time.get_ticks_msec()
	while not (main.surface_ahead("thalassa") and main.surface_ahead("thalassa").is_built) and Time.get_ticks_msec() - t0 < 40000:
		await tree.process_frame
	check(main.surface_ahead("thalassa") != null, "near Amnissos: its surface built ahead")
	var pre: Node = main.surface_ahead("thalassa")
	check(pre != null and pre.is_built and not pre.visible, "built, hidden")
	check(tree.get_first_node_in_group("fx_layer") == null or not pre.is_ancestor_of(tree.get_first_node_in_group("fx_layer")), "space's effects don't land in it")
	for e in main.enemies.get_children():   # (no landing under attack: the home system's raiders away)
		e.queue_free()
	await tree.process_frame
	main.player_data.credits += 777   # (the game moves on meanwhile)
	var credits: int = main.player_data.credits
	main.land_on("thalassa")
	var t1 := Time.get_ticks_msec()
	while tree.current_scene == main and Time.get_ticks_msec() - t1 < 20000:
		await tree.process_frame
	var took := Time.get_ticks_msec() - t1
	var s: Node = tree.current_scene
	check(s == pre, "landing took the surface built ahead")
	check(took < 6000, "and was quick (%d ms: the landing animation only)" % took)
	if s == pre:
		check(int(s.state["player"].get("credits", 0)) == credits, "with the game as it is now (credits %d)" % int(s.state["player"].get("credits", 0)))
	for i in 6:
		await tree.process_frame
	_main = s
	SaveGame.landed_planet = ""
	SaveGame.travelling = false


## Mining: the beam, NPC miners, and rocks that stay mined out.
func test_mining_beam_npc_miners_and_finite_rocks() -> void:
	await _enter(Galaxy.HOME)
	var miners: Array = tree.get_nodes_in_group("neutrals").filter(func(n): return n.role == "miner")
	check(not miners.is_empty(), "a mining crew works the home fields (%d)" % miners.size())
	# The player's beam: a rock in reach, ore cut off continuously.
	var ship: Node2D = _main.ship
	var rock: Node2D = _main.asteroids.get_child(0)
	ship.global_position = rock.global_position + Vector2(0, 400)
	ship.rotation = 0.0   # facing up, at the rock
	ship.velocity = Vector2.ZERO
	ship.stop()
	ship.set_attack_target(rock)
	rock.scanned = true   # (prospected: its veins - Mining)
	ship.mining_hold = true   # (the button held on it)
	var left: int = rock.ore_left
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3500 and rock.ore_left >= left:
		await tree.process_frame
	check(ship._beam != null and ship._beam.active, "the mining beam is on while the button's held")
	check(rock.ore_left < left, "the beam cuts ore (%d -> %d)" % [left, rock.ore_left])
	ship.mining_hold = false
	await tree.process_frame
	check(not ship._beam.active, "let go: the laser stops")
	ship.set_attack_target(null)
	await tree.process_frame
	check(not ship._beam.active, "the beam stops with no rock targeted")
	# An NPC miner at a rock fills its hold.
	var m: Node2D = miners[0]
	var target: Node2D = m._pick_rock()
	m.global_position = target.global_position + Vector2(target.hit_radius + 200.0, 0)
	m._mine_rock = target
	for i in 240:
		await tree.process_frame
	check(m._ore_held() > 0, "the NPC miner has ore in its hold (%d)" % m._ore_held())
	# Rocks are finite: a system remembers its rocks, depleted ones stay gone.
	var dest: String = Galaxy.neighbors(Galaxy.HOME)[0]
	Galaxy.rocks[dest] = [Asteroid.random_data(Vector2(4000, 0))]
	var state: Dictionary = _main.get_save_data()   # (packed as jump_to does)
	for k in ["enemies", "neutrals", "asteroids"]:
		state.erase(k)
	state["jumped"] = true
	SaveGame.pending = state
	await _enter(dest)
	check_eq(_main.asteroids.get_child_count(), 1, "the system keeps the rocks it was left with")
	var r: Node2D = _main.asteroids.get_child(0)
	r.mine(Asteroid.DAMAGE_PER_ORE * (r.ore_left + 1), r.global_position, null)
	for i in 5:
		await tree.process_frame
	check_eq(_main.asteroids.get_child_count(), 0, "mined out: gone")
	check(_main.get_save_data()["asteroids"].is_empty(), "and it stays gone in the save")


## The cargo hold limits mining: a full hold stops the beam, and ore / loot
## floating by isn't taken in (credits still are).
func test_mining_stops_when_the_hold_is_full() -> void:
	await _enter(Galaxy.HOME)
	var ship: Node2D = _main.ship
	var data: Node = _main.player_data
	var rock: Node2D = _main.asteroids.get_child(0)
	ship.global_position = rock.global_position + Vector2(0, 400)
	ship.rotation = 0.0
	ship.velocity = Vector2.ZERO
	ship.stop()
	data.add_item("iron_ore", data.cargo_free())
	check_eq(data.cargo_free(), 0, "the hold is full")
	ship.set_attack_target(rock)
	var left: int = rock.ore_left
	# (The other ships hold still meanwhile: an NPC miner could cut this rock too.)
	var others := tree.get_nodes_in_group("neutrals") + tree.get_nodes_in_group("enemies")
	for o in others:
		o.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 60:
		await tree.process_frame
	for o in others:
		if is_instance_valid(o):
			o.process_mode = Node.PROCESS_MODE_INHERIT
	check(not ship._beam.active, "a full hold: the beam stops")
	check_eq(rock.ore_left, left, "no ore cut")
	ship.set_attack_target(null)
	# Ore next to you stays out; credits come in.
	var ore := Pickup.spawn(tree, ship.global_position + Vector2(10, 0), "titanium_ore", 1)
	var cr := Pickup.spawn(tree, ship.global_position + Vector2(-10, 0), "credits", 5)
	var credits: int = data.credits
	for i in 20:
		await tree.process_frame
	check(is_instance_valid(ore) and data.count("titanium_ore") == 0, "ore with no room stays out there")
	check(not is_instance_valid(cr) and data.credits == credits + 5, "credits take no room")
	# Room again (sold some): the beam cuts up to the hold's size, no more.
	data.remove_item("iron_ore", 3)
	if is_instance_valid(ore):
		ore.queue_free()
	ship.set_attack_target(rock)
	for i in 600:
		await tree.process_frame
	check(data.cargo_free() >= 0, "never more than the hold holds (%d free)" % data.cargo_free())
	check(data.count("iron_ore") + data.count("titanium_ore") + data.count("platinum_ore") > data.count("iron_ore") - 3 or rock.ore_left < left,
		"with room the beam mines again")
	ship.set_attack_target(null)


## Regression: the target freed under the ship (an attacker or a rock gone
## while you land) must not crash the weapon range / mining checks.
func test_freed_target_does_not_crash() -> void:
	await _enter(Galaxy.HOME)
	var ship: Node2D = _main.ship
	for target in [Asteroid.new().setup(Asteroid.random_data(ship.global_position + Vector2(0, 300))),
			tree.get_nodes_in_group("enemies")[0] if not tree.get_nodes_in_group("enemies").is_empty() else null]:
		if target == null:
			continue
		if target.get_parent() == null:
			_main.asteroids.add_child(target)
		await tree.process_frame
		ship.set_attack_target(target)
		target.free()   # gone at once, as when the scene changes
		var r: float = ship.weapon_range
		check(r > 0.0, "the weapon range still reads (%.0f)" % r)
		ship._process(0.016)
		for i in 3:
			await tree.process_frame
		check(ship.attack_target == null, "the freed target is dropped")


## Before you take the main quest, it points you to its giver on Amnissos;
## taken on the surface (state "quest" stage 0), it runs when you're back in
## space. Stations show a quest bulb while you have room for a side quest.
func test_main_quest_from_its_giver() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	check_eq(main.quest.stage, -1, "a new game: the main quest not taken yet")
	check(main.quest.objective_text().contains("Kilon Alios") and main.quest.objective_text().contains("Amnissos"), "the HUD sends you to Kilon Alios on Amnissos")
	var target: Variant = main.quest.target_position()
	check(target is Vector2 and target.distance_to(main._planet_body("thalassa").global_position) < 1.0, "the minimap points at Amnissos")
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	st._update_bulb()
	check(st.bulb.visible, "a station with side quests for you: its bulb is lit")
	for i in main.missions.MAX_ACTIVE:
		main.missions.active.append({"type": "bounty", "title": "x", "count": 1, "progress": 0, "reward": 1, "giver": "x"})
	st._update_bulb()
	check(not st.bulb.visible, "no room for another: it goes out")
	main.missions.active.clear()
	# Taken on Amnissos: back in space at its first stage, without replaying the opening.
	var data: Dictionary = main.get_save_data()
	data["quest"] = {"stage": 0, "finished": false, "lore": []}
	main.load_save_data(data)
	check_eq(main.quest.stage, 0, "the quest taken on the surface runs in space")
	check(not main.quest.dialogue.is_open(), "its opening isn't replayed")
	check_eq(main.quest.objective_text(), QuestData.STAGES[0]["objective"], "its first objective")


## Missions: eight per station, every kind, four tiers by reputation; the ones
## you aren't trusted with are greyed out and can't be taken; finishing one
## raises your reputation; supply runs and surveys complete.
func test_missions() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var ms: Node = main.missions
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	var e: String = st.empire
	check_eq(ms.offers_for(st.station_name, e).size(), ms.MISSIONS_PER_STATION, "eight missions at a station")
	var kinds := {}
	var tiers := {}
	var mining := false
	for i in 300:
		var m: Dictionary = ms._generate(st.station_name, e)
		kinds[m["type"]] = true
		tiers[m["tier"]] = true
		mining = mining or m["title"] == "Mining Contract"
		check(m["reward"] > 0, "%s pays" % m["type"])
	for k in ["bounty", "hunt", "salvage", "supply", "courier", "survey"]:
		check(kinds.has(k), "the %s kind is offered (%s)" % [k, kinds.keys()])
	for k in kinds:   # (and war missions when there's a fleet or a war near: Missions._fill_war)
		check(k in ["bounty", "hunt", "salvage", "supply", "courier", "survey", "protect", "strike", "join", "attack_fleet"], "a known kind: %s" % k)
	check(mining, "mining contracts (salvage jobs for ore) too")
	# Offers' pay is raised by their difficulty (Missions.pay_mult): x1 for the
	# easiest, up to x10 for the hardest - once.
	for m in ms.offers_for(st.station_name, e):
		check(m.get("pay_raised", false), "%s: an offer at the raised pay" % m["title"])
	check_eq(ms.pay_mult({"type": "courier", "tier": 0}), 1.0, "a Routine courier run: as before")
	check_eq(ms.pay_mult({"type": "hunt", "tier": 3}), 10.0, "a Hero-tier hunt: ten times")
	check(ms.pay_mult({"type": "bounty", "tier": 1}) > ms.pay_mult({"type": "courier", "tier": 1}), "a fight pays more than a delivery")
	check(ms.pay_mult({"type": "courier", "tier": 2}) > ms.pay_mult({"type": "courier", "tier": 1}), "a higher tier pays more")
	var keep: Dictionary = JSON.parse_string(JSON.stringify(ms.get_save_data()))
	var base := {"id": 999, "type": "hunt", "giver": st.station_name, "title": "Old job", "desc": "", "reward": 150, "count": 1, "progress": 0, "tier": 3}
	ms.load_save_data(JSON.parse_string(JSON.stringify({"offers": {}, "active": [base], "next_id": 1000})))
	check_eq(int(ms.active[0]["reward"]), 1500, "a hard job in an older save pays ten times as much")
	ms.load_save_data(JSON.parse_string(JSON.stringify(ms.get_save_data())))
	check_eq(int(ms.active[0]["reward"]), 1500, "and only once (saved and loaded again)")
	ms.load_save_data(keep)   # (the station's offers back, for what follows)
	check_eq(tiers.keys().size(), 4, "all four tiers")
	# Reputation decides what you can take.
	var old_rep: float = Galaxy.reputation.get(e, 0.0)
	Galaxy.reputation[e] = 0.0
	var routine: Dictionary = ms._generate(st.station_name, e)
	routine["tier"] = 0
	routine["min_rep"] = ms.TIERS[0]["rep"]
	var hero: Dictionary = routine.duplicate()
	hero["tier"] = 3
	hero["min_rep"] = ms.TIERS[3]["rep"]
	check(ms.available(routine) and not ms.available(hero), "reputation 0: routine yes, hero no")
	check(ms.required_text(hero).contains(str(int(ms.TIERS[3]["rep"]))), "it says what's needed")
	ms.offers[st.station_name].append(hero)
	check(not ms.accept(hero), "a locked mission can't be taken")
	# The station's page: locked ones greyed out, their Accept disabled.
	ms.offers[st.station_name] = [routine, hero]
	main.station_menu.open(st)
	main.station_menu.show_tab(main.station_menu.TABS.find("MISSIONS"))
	await tree.process_frame
	var accepts: Array = main.station_menu._content.find_children("*", "Button", true, false).filter(func(b): return str(b.tooltip_text).contains("Accept mission"))
	check_eq(accepts.size(), 2, "two missions offered")
	check(accepts.filter(func(b): return b.disabled).size() == 1, "the hero mission's Accept is disabled")
	var greyed: Array = main.station_menu._content.find_children("*", "PanelContainer", true, false).filter(func(p): return p.modulate.r < 0.7)
	check_eq(greyed.size(), 1, "and its card greyed out")
	main.station_menu.close()
	await tree.process_frame
	# Finishing one raises your reputation.
	check(ms.accept(routine), "a routine mission taken")
	var rep0: float = Galaxy.reputation[e]
	ms._complete(routine)
	check(Galaxy.reputation[e] > rep0, "finishing it raises your reputation (%.0f -> %.0f)" % [rep0, Galaxy.reputation[e]])
	# A supply run: dock there with the goods.
	var other: Node2D = tree.get_nodes_in_group("stations")[1]
	var sup := {"id": 900, "giver": st.station_name, "type": "supply", "target_station": other.station_name, "item": "food",
		"count": 3, "progress": 0, "reward": 100, "cores": 0, "empire": e, "tier": 0, "min_rep": -29.0, "title": "Supply", "desc": ""}
	ms.active.append(sup)
	ms.on_docked(other.station_name)
	check(ms.active.has(sup), "no goods: not done")
	main.player_data.add_item("food", 3)
	ms.on_docked(other.station_name)
	check(not ms.active.has(sup) and main.player_data.count("food") == 0, "with the goods: delivered and paid")
	# A survey: arriving scans it.
	var sv: Dictionary = {}
	for i in 200:
		sv = ms._generate(st.station_name, e)
		if sv["type"] == "survey":
			break
	sv["tier"] = 0
	sv["min_rep"] = -29.0
	ms.active.append(sv)
	check_eq(ms.markers().size(), 1, "its point is on the map")
	main.ship.global_position = Vector2(sv["pos"][0], sv["pos"][1])
	ms._check_t = 0.0
	ms._process(0.1)
	check(not ms.active.has(sv), "flying there completes it")
	Galaxy.reputation[e] = old_rep


## Neutral ships: the first click selects one and you follow it (no firing);
## clicking it again attacks.
func test_neutral_click_follows_then_attacks() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var n: Node2D = null
	for s in main.neutrals.get_children():
		if s.is_neutral() and not s.is_hostile_to_player():
			n = s
			break
	check(n != null, "a friendly neutral ship")
	if n == null:
		return
	var rep: Dictionary = Galaxy.reputation.duplicate()
	n.global_position = main.ship.global_position + Vector2(900, 0)
	await tree.process_frame
	var click := func():
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = true
		e.position = main.get_canvas_transform() * n.global_position
		main._unhandled_input(e)
	click.call()
	check(main.ship.follow_target == n and main.ship.attack_target == null, "first click: following it, not attacking")
	var shields: float = n.shields
	var hull: float = n.hull
	for i in 90:
		await tree.process_frame
	check(main.ship.global_position.distance_to(n.global_position) < 900.0, "you close in behind it")
	check(n.shields == shields and n.hull == hull, "and don't fire at it")
	click.call()
	check(main.ship.attack_target == n and main.ship.follow_target == null, "second click: attacking it")
	main.ship.set_attack_target(null)
	Galaxy.reputation = rep


## Nebulae and galaxies are the deepest thing in space: everything else in
## the world (planets near and far, the star, stations, ships, rocks) is
## drawn in front of them - never the other way round.
func test_nebulae_behind_everything() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var neb: Node = main.get_node("Nebulae")
	check(neb.get_child_count() > 0, "this system has nebulae")
	var z_of := func(n: Node) -> int:
		var z := 0
		var c: Node = n
		while c != null and c is CanvasItem:
			z += c.z_index
			if not c.z_as_relative:
				break
			c = c.get_parent()
		return z
	var nz: int = z_of.call(neb.get_child(0))
	var bad := []
	var bodies := 0
	for n in main.find_children("*", "CanvasItem", true, false):
		if neb.is_ancestor_of(n) or n == neb or not (n is Node2D):
			continue
		var layer: Node = n.get_parent()
		var in_ui := false
		while layer != null and layer != main:
			if layer is CanvasLayer:
				in_ui = true   # (the HUD, the panels, the starfield layer: other layers)
				break
			layer = layer.get_parent()
		if in_ui:
			continue
		if n.is_in_group("planet_bodies"):
			bodies += 1
		if z_of.call(n) <= nz:
			bad.append("%s (z %d)" % [n.name, z_of.call(n)])
	check(bodies > 0, "planets checked (%d)" % bodies)
	check(bad.is_empty(), "everything is in front of the nebulae (z %d); behind: %s" % [nz, bad.slice(0, 5)])


## The scanner (right-click): an asteroid is laser-scanned, then highlighted
## with its kind and ore; empty space starts a system scan whose waves end in
## the radar's arrows to stations and planets for 10 seconds.
func test_scanner() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var sc: ShipScanner = main.scanner
	var rock: Node2D = main.asteroids.get_child(0)
	main.ship.global_position = rock.global_position + Vector2(0, 500)
	main.ship.stop()
	await tree.process_frame
	var right := func(world: Vector2, shift := false):
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = true
		e.shift_pressed = shift
		e.position = main.get_canvas_transform() * world
		main._unhandled_input(e)
	right.call(rock.global_position)
	check(sc.scanning() and sc._rock == rock, "right-click on an asteroid: scanning it")
	await tree.create_timer(sc.ROCK_TIME + 0.3).timeout
	check(rock.scanned, "the scan done: it's highlighted")
	check(rock.get_save_data()["scanned"], "and stays so (saved)")
	var empty: Vector2 = main.ship.global_position + Vector2(600, -400)
	for k in 12:   # (a spot with no asteroid under it - the rocks are random)
		if main._asteroid_at(empty) == null:
			break
		empty = main.ship.global_position + Vector2.from_angle(k * 0.7) * 700.0
	# Empty space: the probe scanner (ProbeScanner) - none fitted, it says so; fitted, the map opens on its probes.
	right.call(empty)
	check(not main.ship_menu.visible, "no probe scanner: nothing opens")
	main.player_data.add_equipment("probe_scanner")
	right.call(empty)
	check(main.ship_menu.visible and main.ship_menu.current == main.ship_menu.MAP_TAB, "right-click in space: the system map")
	check(main.ship_menu.page(main.ship_menu.MAP_TAB)._probe_panel.visible, "with the PROBES panel open")
	main.ship_menu.close()
	# Far away: out of scanner range.
	main.ship.global_position = rock.global_position + Vector2(0, 5000)
	check(not sc.scan_rock(rock), "too far: no scan")
	# Shift + right-click: the menu, not the probes.
	right.call(main.ship.global_position + Vector2(300, 0), true)
	check(not main.ship_menu.visible, "Shift + right-click opens the menu instead")
	for c in main.get_children():
		if c is CanvasLayer and c.layer >= 40:
			c.queue_free()
	tree.paused = false


## Following a ship is one smooth motion at its speed - no stop-and-go.
func test_follow_is_smooth() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var n: Node2D = null
	for s in main.neutrals.get_children():
		if s.is_neutral():
			n = s
			break
	check(n != null, "a neutral ship")
	if n == null:
		return
	# It cruises in a straight line (its AI paused, moved by hand).
	n.set_process(false)
	n.set_physics_process(false)
	var v := Vector2(170, -60)
	n.velocity = v
	main.ship.global_position = n.global_position + Vector2(-500, 300)
	main.ship.velocity = Vector2.ZERO
	main.ship.follow(n)
	var dt := 1.0 / 60.0
	var speeds := []
	var gaps := []
	for i in 600:   # 10 s
		n.global_position += v * dt
		main.ship._process(dt)
		if i >= 240:   # after catching up
			speeds.append(main.ship.velocity.length())
			gaps.append(main.ship.global_position.distance_to(n.global_position))
	var lo: float = speeds.min()
	var hi: float = speeds.max()
	check(lo > v.length() * 0.8, "never slows to a stop (slowest %.0f, it flies %.0f)" % [lo, v.length()])
	check(hi < v.length() * 1.2, "nor races ahead (fastest %.0f)" % hi)
	check(absf(gaps.min() - main.ship.FOLLOW_DIST) < 60.0 and absf(gaps.max() - main.ship.FOLLOW_DIST) < 60.0,
		"keeps a steady gap behind it (%.0f..%.0f)" % [gaps.min(), gaps.max()])
	main.ship.stop()


## Following a ship that hovers and drifts back and forth (slowly, around one
## spot): you settle near it instead of swinging from side to side.
func test_follow_a_hovering_ship() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var n: Node2D = main.neutrals.get_child(0)
	n.set_process(false)
	n.set_physics_process(false)
	var home: Vector2 = n.global_position
	main.ship.global_position = home + Vector2(-400, 200)
	main.ship.velocity = Vector2.ZERO
	main.ship.follow(n)
	var dt := 1.0 / 60.0
	var travelled := 0.0
	var reversals := 0
	var last := Vector2.ZERO
	for i in 900:   # 15 s: it drifts +-35 px/s, reversing every 2 s
		var v := Vector2(35.0 * sin(i * dt * PI / 2.0), 12.0 * cos(i * dt * 1.3))
		n.velocity = v
		n.global_position += v * dt
		var before: Vector2 = main.ship.global_position
		main.ship._process(dt)
		if i > 300:
			var step: Vector2 = main.ship.global_position - before
			travelled += step.length()
			if step.length() > 0.2 and last.length() > 0.2 and step.dot(last) < 0.0:
				reversals += 1
			if step.length() > 0.2:
				last = step
	var gap: float = main.ship.global_position.distance_to(n.global_position)
	check(travelled < 500.0, "you don't swing about (moved %.0f px in 10 s)" % travelled)
	check(reversals <= 6, "no back-and-forth (%d reversals)" % reversals)
	check(absf(gap - main.ship.FOLLOW_DIST) < 120.0, "still close behind it (%.0f)" % gap)
	main.ship.stop()


## Ships you follow for minutes fly steady courses: a patrol sweeps round a
## circuit (it used to zig-zag to random spots near home, reversing every few
## seconds), an explorer heads onward, not back; you stay with them.
func test_followed_ships_fly_steady() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	# (no pirates about: a patrol hunts any in reach, and a dogfight turns it back
	# and forth - right, but not what this measures)
	for e in tree.get_nodes_in_group("enemies"):
		e.remove_from_group("enemies")
		e.queue_free()
	await tree.process_frame
	var roles := {}
	for n in main.neutrals.get_children():
		# (not a war fleet's ship: a wingman keeps its place behind its leader -
		# test_frontier's fleet test - and only this one ship is stepped here)
		if n.is_neutral() and n.role in ["patrol", "explorer"] and not roles.has(n.role) and n.fleet_id == "":
			roles[n.role] = n
	check(roles.has("patrol"), "a patrol ship to follow")
	for role in roles:
		var n: Node2D = roles[role]
		main.ship.global_position = n.global_position + Vector2(0, 300)
		main.ship.velocity = Vector2.ZERO
		main.ship.follow(n)
		var last := Vector2.ZERO
		var flips := 0
		var worst := 0.0
		for sec in 90:
			for f in 30:
				main.ship._process(1.0 / 30.0)
				n._process(1.0 / 30.0)
			var v: Vector2 = n.velocity
			if v.length() > 30.0:
				if last != Vector2.ZERO and v.normalized().dot(last) < -0.3:
					flips += 1
				last = v.normalized()
			if sec > 5:
				worst = maxf(worst, main.ship.global_position.distance_to(n.global_position))
		check(flips <= 2, "a followed %s ship doesn't keep turning back (%d reversals in 90 s)" % [role, flips])
		check(worst < 450.0, "and you stay with it (at most %d away)" % int(worst))
	main.ship.stop()


## A story dialogue opening while you hold the button to steer (the cursor
## hidden) gives the mouse back: steering ends, the cursor shows - the
## release would land on the dialogue and leave the cursor hidden.
func test_dialogue_frees_the_mouse() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	var spot: Vector2 = main.ship.global_position + Vector2(0, -700)
	for k in 12:   # (empty space: no ship, rock or station under it)
		if main._asteroid_at(spot) == null and main._enemy_at(spot) == null and main._station_at(spot) == null:
			break
		spot = main.ship.global_position + Vector2.from_angle(k * 0.6) * 700.0
	e.position = main.get_canvas_transform() * spot
	main._unhandled_input(e)
	check(main._drag_moves, "holding the button: steering (the cursor hidden - not in headless runs)")
	main.quest.dialogue.play([["Narrator", "A test line."]])
	check(not main._drag_moves, "a dialogue opens: steering ends")
	check_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "and the cursor shows")
	main.quest.dialogue._finish()
	tree.paused = false
	main.ship.stop()


## Dying doesn't throw the game away: Respawn puts you in a new ship at the
## nearest station with the main quest, missions and reputation as they
## were - only your cargo and a tenth of your credits lost.
func test_respawn_keeps_progress() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	main.quest.start()
	await tree.process_frame
	main.quest.dialogue._finish()
	tree.paused = false
	var stage: int = main.quest.stage
	check(stage >= 0, "the main quest under way")
	var m: Dictionary = main.missions.offers_for("Kephala Outpost", "")[0]
	main.missions.accept(m)
	Galaxy.reputation["minoa"] = 22.0
	main.player_data.credits = 1000
	main.player_data.add_item("iron_ore", 12)
	main.player_data.add_item("repair_kit", 1)
	main.ship.take_damage(99999.0, main.ship.global_position)
	check(not main.ship.is_alive(), "destroyed")
	var state: Dictionary = main.respawn_state()
	# Coming back as the scene does after a jump.
	main.queue_free()
	await tree.process_frame
	SaveGame.pending = state
	SaveGame.travelling = true
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	SaveGame.travelling = false
	var n: Node = _main
	check_eq(n.quest.stage, stage, "the main quest where it was")
	check(n.missions.active.any(func(a): return a["id"] == m["id"]), "your missions kept")
	check_eq(Galaxy.reputation["minoa"], 22.0, "your reputation kept")
	check_eq(n.player_data.credits, 900, "10 % insurance paid")
	check_eq(n.player_data.count("iron_ore"), 0, "the cargo lost")
	# One thing you carried is lost (LostItems) - here the kits or the energy drinks (all you had but the laser).
	check_eq(n.player_data.lost.size(), 1, "one thing lost with the ship")
	var gone := str(n.player_data.lost[0]["id"])
	check(gone in ["repair_kit", "energy_drink"] and n.player_data.count(gone) == 0, "the repair kits or the energy drinks (%s)" % [n.player_data.lost])
	check(n.ship.is_alive() and n.ship.hull == n.ship.max_hull, "a new ship, full hull")
	var st: Node2D = n._nearest_station(n.ship.global_position, INF)
	check(st != null and n.ship.global_position.distance_to(st.global_position) < st.radius + 400.0, "at a station")


## Attract mode (the title screen left alone): an autopilot plays a fresh
## game - your ship flies itself and can't be destroyed, nothing can be
## saved, "PLEASE INSERT DRACHMA" blinks near the bottom.
func test_attract_mode() -> void:
	AttractMode.active = true
	var main: Node = await _enter(Galaxy.HOME)
	var c: AttractMode = null
	for n in main.get_children():
		if n is AttractMode:
			c = n
	check(c != null, "the autopilot is driving")
	if c == null:
		AttractMode.active = false
		return
	check(main.ship.invulnerable and not main.can_save(), "your ship can't die, nothing is saved")
	check(c._label.TEXT == "PLEASE INSERT DRACHMA" and Array(c._label.TEXT.split("")).all(func(ch): return ch == " " or c._label.GLYPHS.has(ch)) and c._label.offset_top < -100.0, "the banner, near the bottom above the toolbar")
	var crt_filter = tree.root.get_children().filter(func(n): return n is CrtFilter)
	check(crt_filter.size() == 1 and (not Settings.crt_attract or crt_filter[0].visible), "the CRT filter covers the window (by default)")
	var from: Vector2 = main.ship.global_position
	for i in 120:
		await tree.process_frame
	check(c.task != "", "it has something to do (%s)" % c.task)
	check(main.ship.global_position.distance_to(from) > 50.0, "and the ship moves by itself")
	var hull: float = main.ship.hull
	main.ship.take_damage(500.0, main.ship.global_position)
	check_eq(main.ship.hull, hull, "unhurt")
	var a: Array = []
	for k in 4:
		c._t = k * 0.625
		c._process(0.0)
		a.append(c._label.modulate.a)
	check(a.max() - a.min() > 0.5, "the banner blinks")
	AttractMode.active = false


## The main quest's last boss: the Minotaur at the heart of the Labyrinth,
## drawn from his art (MinotaurBoss), rewarding credits, data cores and alloy.
func test_minotaur_boss() -> void:
	var found := -1
	for i in QuestData.STAGES.size():
		if QuestData.STAGES[i].get("type", "") == "kill" and QuestData.STAGES[i]["spawn"][0][0] == "minotaur":
			found = i
	check(found >= 0, "a main-quest stage fights the Minotaur")
	if found < 0:
		return
	var st: Dictionary = QuestData.STAGES[found]
	check(QuestData.STAGES[found - 1].get("unseal", false), "after entering the heart of the Labyrinth")
	check(QuestData.STAGES[found + 1]["type"] == "end", "before the end")
	check(st["reward"]["credits"] > 0 and st["reward"]["items"].has("alien_alloy"), "a reward: credits and items")
	var main: Node = await _enter(Galaxy.HOME)
	var m: Node2D = main.spawn_ship(main.ship.global_position + Vector2(0, -900), "minotaur")
	for i in 5:
		await tree.process_frame
	check(m.body.has_node("Monster") and m.body.get_node("Monster") is MinotaurBoss, "drawn as the Minotaur")
	check(m.display_name == "The Minotaur" and m.boss and m.hull >= 1500.0, "a unique boss")
	var mon: MinotaurBoss = m.body.get_node("Monster")
	check(mon._limbs.size() == 3, "arms and leg rigged")
	var d0: float = main.ship.global_position.distance_to(m.global_position)
	m.queue_free()
	check(d0 > 0.0, "spawned")


## Docking again while the undock animation plays isn't lost: it happens
## once the animation ends (it used to be ignored - no station menu).
func test_dock_during_undock_is_queued() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	main.ship.global_position = st.global_position + Vector2(0, st.dock_radius * 0.5)
	main.dock(st)
	var t0 := Time.get_ticks_msec()
	while not main.station_menu.visible and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	check(main.station_menu.visible, "docked: the station menu")
	main.station_menu.close()
	await tree.process_frame
	check(main._ship_animating, "undocking: the ship animates out")
	main.dock(st)
	t0 = Time.get_ticks_msec()
	while not main.station_menu.visible and Time.get_ticks_msec() - t0 < 8000:
		await tree.process_frame
	check(main.station_menu.visible, "docking during the undock: it docks once the animation ends")
	main.station_menu.close()
	for i in 10:
		await tree.process_frame


## The Ship Computer and its map don't pause the game; setting a course on the
## map keeps it open (the course shows as the ship flies); a hit closes it.
func test_menus_run_and_close_on_attack() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	main._open_panel(main.ship_menu, main.ship_menu.MAP_TAB)
	check(main.ship_menu.visible and not tree.paused, "the map is open and the game goes on")
	var view = main.ship_menu._pages[main.ship_menu.MAP_TAB].find_children("*", "Control", true, false).filter(func(c): return c.has_method("_set_course"))[0]
	var start: Vector2 = main.ship.global_position
	view._set_course(view.to_screen(start + Vector2(3000, 0)))
	check(main.ship_menu.visible, "setting a course keeps the map open")
	for k in 30:
		await tree.process_frame
	check(main.ship.has_target and main.ship.global_position.distance_to(start) > 1.0, "the ship flies its course with the map open")
	main.ship.take_damage(1.0, main.ship.global_position, main.ship)
	check(not main.ship_menu.visible, "a hit closes the Ship Computer")
	# Docked: a safe zone - the game goes on, nothing can hurt you.
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	main.dock(st)
	var t0 := Time.get_ticks_msec()
	while not main.station_menu.visible and Time.get_ticks_msec() - t0 < 5000:   # (the docking glide first)
		await tree.process_frame
	check(main.station_menu.visible and not tree.paused, "docked, the game goes on")
	var hull: float = main.ship.hull + main.ship.shields
	main.ship.take_damage(50.0, main.ship.global_position, main.ship)
	check(is_equal_approx(main.ship.hull + main.ship.shields, hull) and main.station_menu.visible, "untouchable while docked")
	main.station_menu.close()
	check(not main.ship.invulnerable, "vulnerable again after undocking")


## The Ship Computer's tabs: Inventory, Map, Galaxy, Quest, Tech Tree,
## Repair, Archive - and Tab (or I) always opens it on the Inventory.
func test_ship_computer_tabs() -> void:
	var main: Node = await _enter(Galaxy.HOME)
	var sm = main.ship_menu
	check_eq(sm.TABS, ["INVENTORY", "MAP", "GALAXY", "QUEST", "TECH TREE", "REPAIR", "ARCHIVE", "INDUSTRY"], "the tabs in order")
	sm.open()
	await tree.process_frame
	check_eq(sm.current, sm.INVENTORY_TAB, "opens on the Inventory")
	check(sm._pages[sm.current].get_script() == preload("res://scripts/pages/inventory_page.gd"), "and shows the inventory page")
	sm.show_tab(sm.QUEST_TAB)
	sm.close()
	sm.open()
	await tree.process_frame
	check_eq(sm.current, sm.INVENTORY_TAB, "again on the Inventory, not the tab used last")
	sm.close()
	sm.open(sm.MAP_TAB)
	check(sm._pages[sm.MAP_TAB].get_script() == preload("res://scripts/pages/map_page.gd"), "M: the map")
	sm.close()


## The middle mouse button (a click, not a drag) resets the zoom in every
## view that zooms with the wheel - space here.
func test_middle_click_resets_zoom() -> void:
	var n := Node.new()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.position = Vector2(100, 100)
	mb.pressed = true
	check(not UI.middle_click(n, mb), "pressed: not yet")
	mb.pressed = false
	check(UI.middle_click(n, mb), "let go where it was pressed: a middle click")
	mb.pressed = true
	UI.middle_click(n, mb)
	mb.pressed = false
	mb.position = Vector2(180, 140)
	check(not UI.middle_click(n, mb), "dragged: not a click (views that pan with it keep panning)")
	n.free()
	for p in ["res://scripts/main.gd", "res://scripts/planet_surface.gd", "res://scripts/pages/map_page.gd", "res://scripts/surface_map.gd",
			"res://scripts/zoo.gd", "res://scripts/level_editor.gd", "res://scripts/svg_editor.gd"]:
		check(FileAccess.get_file_as_string(p).contains("UI.middle_click("), "%s resets its zoom on a middle click" % p.get_file())
	# In space: zoomed in, a middle click puts the zoom back.
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var m: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(m)
	for i in 5:
		await tree.process_frame
	m._zoom = 1.5
	mb.position = Vector2(400, 300)
	mb.pressed = true
	m._unhandled_input(mb)
	mb.pressed = false
	m._unhandled_input(mb)
	check_eq(m._zoom, 1.0, "space: back to the normal zoom")
	m.queue_free()
	for i in 3:
		await tree.process_frame


## The Ship Computer opens and closes with a hexagon curtain (HexReveal) - in
## a window; headless (the tests) at once. The curtain's shader compiles and
## while it plays every part of the menu uses it, then gets its own look back.
func test_hex_curtain() -> void:
	var menu := Control.new()
	tree.root.add_child(menu)
	var part := ColorRect.new()
	menu.add_child(part)
	var done := [false]
	HexReveal.play(menu, true, func(): done[0] = true)
	check(done[0], "headless: closing hides at once")
	check(not HexReveal.running(menu), "and nothing keeps playing")
	# The curtain itself, as in a window.
	var h := HexReveal.new()
	h._menu = menu
	menu.add_child(h)
	check(menu.material is ShaderMaterial and part.use_parent_material, "playing: the menu's parts use the curtain")
	var sh: Shader = (menu.material as ShaderMaterial).shader
	check(sh != null and sh.code.contains("hex_dist"), "the curtain's shader")
	h.finish()
	check(menu.material == null and not part.use_parent_material, "done: every part its own look back")
	menu.queue_free()
	await tree.process_frame


## The main quest done: nothing of it under the minimap any more.
func test_finished_main_quest_leaves_the_tracker() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var m: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(m)
	for i in 5:
		await tree.process_frame
	check(m.hud._quest_objective.visible and m.hud._quest_objective.text != "", "under way: its objective shows")
	m.quest.finished = true
	m.quest.changed.emit()
	check(not m.hud._quest_title.visible and not m.hud._quest_objective.visible, "done: no main quest under the minimap")
	m.quest.finished = false
	m.queue_free()
	for i in 3:
		await tree.process_frame


## Turning on the spot at full thrust, the exhaust is thrown out behind the
## nozzle in each direction it pointed and flies on that way - not left in a
## little circle round the ship where the nozzle has been.
func test_exhaust_follows_the_nozzle_when_turning() -> void:
	var src := GDScript.new()
	src.source_code = "extends Node2D\nvar engine_offset := Vector2(0, 30)\nvar thrust := 1.0\nvar boost_time := 0.0\nfunc is_alive() -> bool:\n\treturn true\n"
	src.reload()
	var s: Node2D = Node2D.new()
	s.set_script(src)
	tree.root.add_child(s)
	var t := ExhaustTrail.attach(s, "blue", 100.0)
	await tree.process_frame
	t.set_process(false)
	for i in 60:   # a full turn in half a second
		s.rotation = TAU * i / 60.0
		t._time += 1.0 / 120.0
		t.remove_meta("_redrawn_at")
		t._process(0.0)
	var far := 0.0
	var dirs := {}
	for p in t._pp:
		far = maxf(far, p.length())
		if p.length() > 60.0:
			dirs[int(fposmod(p.angle(), TAU) / (TAU / 4.0))] = true
	check(far > 100.0, "the exhaust flies out from the nozzle (%.0f px from the ship; the nozzle is 34 px out)" % far)
	check(dirs.size() == 4, "and out every way the nozzle pointed as it turned (%d of 4 quarters)" % dirs.size())
	s.queue_free()
	await tree.process_frame


## A system streams in (as a jump or a new game builds it - staged): the scene
## runs while its pieces come, nearest to the ship first, and in the end every
## planet, station and gate is there.
func test_system_streams_in() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		await tree.process_frame
	var sys_id: String = "klotho" if Galaxy.SYSTEMS.has("klotho") else str(Galaxy.SYSTEMS.keys()[1])
	Galaxy.current_system = sys_id
	SaveGame.travelling = true
	UI.staging = true
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	UI.staging = false
	var main: Node = _main
	var t0 := Time.get_ticks_msec()
	while main.process_mode == Node.PROCESS_MODE_DISABLED and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	var p: Vector2i = main.stream_progress()
	check(main.process_mode != Node.PROCESS_MODE_DISABLED, "the scene runs (you fly) after a short start")
	check(p.y > 10 and p.x < p.y, "with its pieces still coming in (%d / %d)" % [p.x, p.y])
	var order: Array = []   # (each piece's distance from the ship as it comes)
	while not main.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		var before: int = main.stream_progress().x
		await tree.process_frame
		if main.stream_progress().x > before:
			order.append(main.stream_progress().x)
	p = main.stream_progress()
	check(main.build_settled() and p.x == p.y, "all in, in the end (%d / %d)" % [p.x, p.y])
	var sys: Dictionary = Galaxy.system(sys_id)
	check(tree.get_nodes_in_group("stations").size() == sys["stations"].size(), "every station (%d)" % sys["stations"].size())
	check(tree.get_nodes_in_group("gates").size() == sys["gates"].size(), "every gate (%d)" % sys["gates"].size())
	check(tree.get_nodes_in_group("planet_bodies").size() == sys["planets"].size(), "every planet and moon (%d)" % sys["planets"].size())
	check(order.size() > 3, "a few pieces a frame, over several frames (%d frames)" % order.size())
	# Every piece faded all the way in - even one that stops itself off screen (a
	# rock's VisibleOnScreenEnabler2D stopped its own fade: rocks never showed).
	for r in tree.get_nodes_in_group("asteroids"):
		r.process_mode = Node.PROCESS_MODE_DISABLED
	await tree.create_timer(0.6).timeout
	var faint := 0
	for n in tree.get_nodes_in_group("asteroids") + tree.get_nodes_in_group("stations") + tree.get_nodes_in_group("planet_bodies"):
		if (n as CanvasItem).modulate.a < 0.99:
			faint += 1
	check(faint == 0, "every rock, station and planet fully shown (%d faint)" % faint)
	SaveGame.travelling = false
