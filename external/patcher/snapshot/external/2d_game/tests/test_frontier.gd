extends TestCase
## Fuel (the tank, jumps, refuelling, the Star Energizer), the Electro
## (ChainLightning), wrecks and salvage (Wreck), combined invasions and
## distress calls (Fleets), the war missions, the rings' local spaces, the
## ship's areas (the equipment screens) - and the Patcher opening on its
## infographic, the Library's categories as icons.

var _main: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false


func teardown() -> void:
	Accuracy.sure = false
	if is_instance_valid(_main):
		_main.queue_free()
	await tree.process_frame
	tree.paused = false
	Galaxy.new_game(false)


func _game() -> Node:
	if is_instance_valid(_main):
		_main.queue_free()
		await tree.process_frame
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	_main.ship.invulnerable = true
	return _main


# --- Fuel ---------------------------------------------------------------------------------

func test_fuel() -> void:
	var main: Node = await _game()
	var d: Node = main.player_data
	check_eq(d.fuel_max(), Shipyard.STARTER_FUEL, "the starter ship's tank")
	check_eq(d.fuel_level(), d.fuel_max(), "full at the start")
	# A jump burns FUEL_JUMP; too little and the gate won't take you.
	var dest: String = Galaxy.neighbors(Galaxy.HOME)[0]
	d.fuel = 5.0
	main.jump_to(dest)
	check_eq(Galaxy.current_system, Galaxy.HOME, "not enough fuel: no jump")
	d.fuel = 50.0
	check(d.use_fuel(Shipyard.FUEL_JUMP), "a jump's fuel burnt")
	check(is_equal_approx(d.fuel_level(), 40.0), "40 left")
	# An empty tank: a third of your speed.
	d.fuel = 0.0
	main.ship.move_to(main.ship.global_position + Vector2(5000, 0))
	for i in 90:
		await tree.process_frame
	check(main.ship.velocity.length() <= main.ship.max_speed * main.ship.FUEL_EMPTY_SPEED + 5.0, "empty: emergency thrusters only (%.0f)" % main.ship.velocity.length())
	main.ship.stop()
	# A Fuel Tank module makes the tank bigger.
	d.modules.append({"id": "fuel_tank", "rating": 0})
	check(d.fuel_max() > Shipyard.STARTER_FUEL, "a Fuel Tank adds to it")
	d.modules.clear()
	# Fuel in the hold, pumped in at a station (the Repair tab's helper).
	d.fuel = 10.0
	d.add_item("fuel", 3)
	var sm: Node = main.station_menu
	sm.data = d
	sm._pump_fuel(3)
	check(is_equal_approx(d.fuel_level(), 40.0), "3 units of fuel pumped in: +30 (%.1f)" % d.fuel_level())
	check_eq(d.count("fuel"), 0, "out of the hold")
	# The station's price for a unit of tank: its fuel price over FUEL_UNITS_PER_CARGO.
	var sid: String = Galaxy.system(Galaxy.HOME)["stations"][0]
	check(Shipyard.fuel_unit_price(sid) > 0.0, "fuel has a price at a station")


func test_star_energizer() -> void:
	var main: Node = await _game()
	var d: Node = main.player_data
	var ship: Node2D = main.ship
	d.add_equipment("star_energizer")
	check("star_energizer" in d.toolbar, "on the toolbar")
	d.fuel = 20.0
	ship.global_position = Vector2(ship.energizer_reach() + 3000.0, 0)
	ship.use_system("star_energizer")
	check(not ship.energizing, "too far from the star: off")
	ship.global_position = Vector2(ship.energizer_reach() - 200.0, 0)
	ship.cooldowns.clear()
	ship.use_system("star_energizer")
	check(ship.energizing, "near the star: on")
	await tree.create_timer(0.5).timeout
	check(d.fuel_level() > 20.5, "the tank fills (%.1f)" % d.fuel_level())


# --- The Electro --------------------------------------------------------------------------

func test_electro_chains_and_stuns() -> void:
	var main: Node = await _game()
	var p: Vector2 = main.ship.global_position + Vector2(600, 0)
	var foes := []
	for i in 4:
		foes.append(main.spawn_enemy(p + Vector2(i * 150, 0)))
	for f in foes:
		f.max_hull = 5000.0
		f.hull = 5000.0
		f.shields = 0.0
	var w: Dictionary = Items.WEAPONS["electro"].duplicate()
	w["stun"] = 1.0
	var hit := ChainLightning.strike(tree, main.ship, foes[0], 40.0, w)
	check_eq(hit.size(), 4, "it leapt from ship to ship (up to chain + 1)")
	check(foes.all(func(f): return f.hull < 5000.0), "every one hurt")
	check(foes[0].hull < foes[3].hull, "each hit weaker than the last")
	check(foes.all(func(f): return f._stun_t > 0.0), "stunned (a sure stun here)")
	# A stunned ship drifts and holds its fire.
	var v0: Vector2 = foes[0].velocity
	await tree.process_frame
	check(foes[0].velocity.length() <= v0.length() + 1.0, "a stunned ship drifts")
	# The player's ship can be stunned too - less with electric resistance.
	main.ship.stun(1.5)
	check(main.ship._stun_t > 0.0, "you can be stunned")
	# It leaps only to foes: from you, not onto neutrals minding their business.
	var friend: Node2D = main.spawn_ship(foes[0].global_position + Vector2(0, 120), EnemyTypes.neutral_ids()[0], {}, "minoa")
	check(not ChainLightning._foe_of(main.ship, friend), "not onto a friendly neutral")
	# NPCs can carry one (saved).
	foes[1].electro = true
	var sd: Dictionary = foes[1].get_save_data()
	check(sd.get("electro", false), "an NPC's Electro is saved")


# --- Wrecks and salvage -------------------------------------------------------------------

func test_wrecks_and_salvage() -> void:
	var main: Node = await _game()
	var d: Node = main.player_data
	var e: Node2D = main.spawn_enemy(main.ship.global_position + Vector2(700, 0))
	e.electro = true
	e.take_damage(99999.0, e.global_position, main.ship)
	for i in 5:
		await tree.process_frame
	var wrecks: Array = tree.get_nodes_in_group("wrecks")
	check(not wrecks.is_empty(), "a destroyed ship leaves a wreck")
	var w: Wreck = wrecks[-1]
	check(w.electro, "it remembers the ship's Electro")
	# Without a Salvage Rig: nothing.
	main._start_salvage(w)
	check(main._salvage == null, "no rig: no salvage")
	d.add_equipment("salvage_rig")
	main._start_salvage(w)
	check(main._salvage == w, "with a rig: salvaging it")
	main.ship.global_position = w.global_position + Vector2(w.radius + 100.0, 0)
	main.ship.stop()
	main.ship.velocity = Vector2.ZERO
	var t0 := Time.get_ticks_msec()
	while not w.salvaged and Time.get_ticks_msec() - t0 < 9000:   # (Wreck.SALVAGE_TIME_SHIP: 4 s)
		await tree.process_frame
	check(w.salvaged, "cut apart")
	check(tree.get_nodes_in_group("pickups").any(func(pk): return pk.item_id == "scrap" and pk.global_position.distance_to(w.global_position) < w.radius * 2.0 + 200.0),
		"salvage drifts out (scrap beside the wreck)")
	check(tree.get_nodes_in_group("pickups").any(func(pk): return str(pk.item_id).begins_with("spare_") and pk.global_position.distance_to(w.global_position) < w.radius * 2.0 + 200.0),
		"spare parts for the Repair Bay among it")
	var rng := RandomNumberGenerator.new()
	for i in 20:
		var n := 0
		for dr in Wreck.spare_drops(rng, 3):
			check(Items.ITEMS.has(dr[0]), "a real item (%s)" % dr[0])
			n += int(dr[1])
		check_eq(n, 3, "spare_drops gives as many as asked")
	# A wreck's Electro (an Electro S): fitted to a free hardpoint that takes it (or sold for parts).
	var ez := Hardpoints.item_id("electro", Hardpoints.BASE)
	Hardpoints.fitted(d)[0] = ""   # (the S hardpoint free)
	var w2 := Wreck.spawn(main, Vector2(1000, 1000), ProcArt.get_tex("ship_player"), Vector2.ONE, 0.0, {"kind": "ship", "electro": true})
	var said := w2._salvage_electro(d)
	check(d.has_equipment("electro") and said.contains("Electro"), "salvaged an Electro and fitted it")
	# Another, with no hardpoint free that takes it: it's yours all the same - in the hold.
	var in_hold: int = d.count(ez)
	var w3 := Wreck.spawn(main, Vector2(1200, 1000), ProcArt.get_tex("ship_player"), Vector2.ONE, 0.0, {"kind": "ship", "electro": true})
	said = w3._salvage_electro(d)
	check(d.count(ez) == in_hold + 1 and said.contains("hold"), "a second Electro goes into the hold, not sold (%s)" % said)
	# And a third, with one in the hold too.
	said = w3._salvage_electro(d)
	check(d.count(ez) == in_hold + 2, "and a third, beside the one in the hold")
	# A ship's own weapons: a salvaged wreck may give one up.
	var got := false
	for i in 40:
		var w4 := Wreck.spawn(main, Vector2(1400 + i * 10, 1000), ProcArt.get_tex("ship_player"), Vector2.ONE, 0.0, {"kind": "ship", "weapons": ["wpn:plasma_cannon:2"]})
		if w4.salvage(d).contains("Plasma Cannon M"):
			got = true
			break
	check(got, "a wreck gives up one of its weapons now and then")
	# A destroyed station leaves one too.
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	var n0 := tree.get_nodes_in_group("wrecks").size()
	st.blow_up()
	await tree.process_frame
	check(tree.get_nodes_in_group("wrecks").any(func(x): return x.kind == "station"), "a station's wreck")
	check(tree.get_nodes_in_group("wrecks").size() >= n0, "kept")


# --- Fleets: combined invasions, distress calls ---------------------------------------------

func test_combined_invasion_and_distress() -> void:
	Galaxy.current_system = "atrapos"
	Galaxy._set_relation("sparta", "minoa", -90.0)
	for f in Fleets.fleets.values().duplicate():
		if f["mission"] == "invade":
			Fleets.fleets.erase(f["id"])
	Fleets._launch_invasion("sparta", "kyros", "delos")
	var inv: Array = Fleets.fleets.values().filter(func(f): return f.get("event", "") != "")
	check(inv.size() >= 2 and inv.size() <= 3, "an invasion of 2-3 fleets (%d)" % inv.size())
	check(inv.all(func(f): return f["waiting"] and f["stage"] == "kyros" and f["target"] == "delos"), "gathering at the staging system")
	# They set out together once all are there.
	for i in 40:
		Fleets._clock += Fleets.TICK
		Fleets._move()
		if inv.all(func(f): return not f.get("waiting", true)):
			break
	check(inv.all(func(f): return not f["waiting"]), "set out")
	check(inv.all(func(f): return f["route"] == ["delos"] or f["system"] == "delos"), "together, for the target")
	# A distress call brings the victim's (and allies') idle defenders.
	var victim := "minoa"
	var sys_id := "delos"
	var answered: Array = Fleets.distress(sys_id, victim, "sparta")
	check(not answered.is_empty(), "a distress call answered")
	check(answered.size() <= Fleets.DISTRESS_ANSWER, "by at most %d fleets" % Fleets.DISTRESS_ANSWER)
	check(answered.all(func(f): return f["empire"] == victim or Galaxy.allied(f["empire"], victim)), "the owner's or its allies'")
	check(answered.all(func(f): return f["answering"] == sys_id and not f["route"].is_empty()), "on their way")
	check(Fleets.distress(sys_id, victim, "sparta").is_empty(), "not again at once")


# --- A fleet in the system: formation, one target, all turn on an attacker ------------------

func test_fleet_formation_and_counterattack() -> void:
	var main: Node = await _game()
	var emp: String = Galaxy.owner_of(Galaxy.current_system)
	if emp == "" or emp == "pirates":
		emp = "minoa"
	var f := {"id": "f_test", "empire": emp, "mission": "defend", "size": 6, "system": Galaxy.current_system, "route": [], "t": 0.0}
	Fleets.fleets[f["id"]] = f
	main.ship.global_position = Vector2(-60000, -60000)   # (out of the way)
	main._spawn_fleet(f, false)
	await tree.process_frame
	var ships: Array = main.neutrals.get_children().filter(func(n): return n.get("fleet_id") == "f_test")
	check_eq(ships.size(), 6, "the fleet's ships")
	var lead: Node2D = ships[0].fleet_mates()[0]
	check(ships.all(func(s): return s.fleet_mates().size() == 6 and s.fleet_mates()[0] == lead), "one leader for all")
	# They form up: each wingman at its place in the wedge behind the leader.
	var t0 := Time.get_ticks_msec()
	var formed := false
	while Time.get_ticks_msec() - t0 < 30000 and not formed:
		await tree.process_frame
		formed = ships.all(func(s): return s == lead or s.global_position.distance_to(lead.global_position + s._wing_offset().rotated(lead.velocity.angle() + PI / 2.0 if lead.velocity.length_squared() > 400.0 else lead.body.rotation)) < 140.0)
	check(formed, "in formation behind the leader")
	var behind := ships.filter(func(s): return s != lead and (s.global_position - lead.global_position).dot(lead.velocity) < 0.0).size()
	check(behind >= 4, "the wedge trails the leader (%d of 5 behind it)" % behind)
	# You fire on a wingman: the whole fleet turns on you. (Out in open space,
	# well away from any station's safe zone, where nobody fights.)
	var far := Vector2(40000, 40000) - lead.global_position
	for sh in ships:
		sh.global_position += far
	main.ship.global_position = lead.global_position + Vector2(700, 0)
	var hit: Node2D = ships[ships.size() - 1]
	hit.take_damage(1.0, main.ship.global_position, main.ship)
	check(ships.all(func(s): return s._target == main.ship and s.is_hostile_to_player()), "attack one, they all counter-attack")
	# They fight from an arc round you, the leader in the middle - not in a heap.
	t0 = Time.get_ticks_msec()
	var near := []
	while Time.get_ticks_msec() - t0 < 20000 and (near.size() < 5 or Time.get_ticks_msec() - t0 < 3000):
		await tree.process_frame
		near = ships.filter(func(s): return is_instance_valid(s) and s.global_position.distance_to(main.ship.global_position) < s.preferred_distance + 260.0)
	check(near.size() >= 5, "at their firing distance round you (%d)" % near.size())
	# (Spread: they swing round their slots, two can cross for a moment - the
	# widest closest gap over a second and a half.)
	var min_gap := 0.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500 and min_gap <= 60.0:
		await tree.process_frame
		var gap := INF
		for a in ships:
			for b in ships:
				if a != b and is_instance_valid(a) and is_instance_valid(b):
					gap = minf(gap, a.global_position.distance_to(b.global_position))
		min_gap = maxf(min_gap, gap)
	check(min_gap > 60.0, "spread along the arc (closest two %.0f apart)" % min_gap)
	Fleets.fleets.erase("f_test")


# --- War missions ---------------------------------------------------------------------------

func test_war_missions() -> void:
	Galaxy.current_system = "atrapos"
	Galaxy._set_relation("sparta", "minoa", -90.0)
	Fleets._launch_invasion("sparta", "kyros", "delos")
	var ms: Node = load("res://scripts/missions.gd").new()
	tree.root.add_child(ms)
	var pd: Node = load("res://scripts/player_data.gd").new()
	pd.add_to_group("player_data")
	tree.root.add_child(pd)
	var kinds := {}
	for i in 200:
		var m := {"id": i, "giver": "x", "progress": 0, "count": 1, "cores": 0, "empire": "minoa", "tier": 0, "min_rep": -49.0}
		if ms._fill_war(m, "minoa", 1.0):
			kinds[m["type"]] = true
			check(m["reward"] > 0 and m["title"] != "" and m["desc"] != "", "%s: a real job" % m["type"])
	for k in ["protect", "join", "attack_fleet", "strike"]:
		check(kinds.has(k), "%s missions offered (%s)" % [k, kinds.keys()])
	# An attack_fleet mission counts that fleet's ships only.
	var f: Dictionary = Fleets.fleets.values().filter(func(x): return x["empire"] == "sparta")[0]
	var m2 := {"id": 900, "giver": "x", "progress": 0, "count": 2, "cores": 0, "empire": "minoa", "tier": 0, "type": "attack_fleet",
		"fleet": f["id"], "target_empire": "sparta", "title": "Raid", "reward": 100}
	ms.active.append(m2)
	ms.on_enemy_killed("x", "sparta", "not_it")
	check_eq(m2["progress"], 0, "another fleet's ship doesn't count")
	ms.on_enemy_killed("x", "sparta", f["id"])
	check_eq(m2["progress"], 1, "its ship counts")
	# A strike mission counts your hits on its station.
	var sid: String = Galaxy.system("delos")["stations"][0]
	var m3 := {"id": 901, "giver": "x", "progress": 0, "count": 10, "cores": 0, "empire": "sparta", "tier": 0, "type": "strike",
		"station_id": sid, "target_station": "y", "system": "delos", "title": "Strike", "reward": 100}
	ms.active.append(m3)
	ms.on_station_hit(sid, 4.0)
	check(is_equal_approx(float(m3["progress"]), 4.0), "4% off it")
	ms.on_station_hit(sid, 7.0)
	check(not m3 in ms.active, "done at 10%")
	ms.queue_free()
	pd.queue_free()


# --- Rings: local spaces ----------------------------------------------------------------------

func test_ring_local_space() -> void:
	var main: Node = await _game()
	var beacon: Node2D = null
	for b in tree.get_nodes_in_group("signal_beacons"):
		if b.sig.get("kind", "") == "ring":
			beacon = b
	check(beacon != null, "a ringed planet (Dikte) has a ring beacon")
	if beacon == null:
		return
	check(beacon.active(), "always there")
	check(not "ring" in SignalSites.signal_kinds(), "rings aren't signal sources")
	var rocks0: int = tree.get_nodes_in_group("asteroids").size()
	main.enter_site(beacon)
	for i in 10:
		await tree.process_frame
	var site: Node = main.site
	check(site != null and site.kind == "ring", "in the ring's local space")
	var ice: Array = tree.get_nodes_in_group("asteroids").filter(func(r): return r.kind == "ice")
	check(ice.size() >= 60, "ice asteroids beyond counting (%d)" % ice.size())
	check(site._miners.size() > 0, "miners at work")
	# Collisions: driven into a rock at speed, the ship is pushed out, bounced and hurt.
	var rock: Node2D = ice[0]
	main.ship.invulnerable = false
	main.ship.shields = 0.0
	var hull0: float = main.ship.hull
	main.ship.global_position = rock.global_position + Vector2(rock.hit_radius + 10.0, 0)
	main.ship.velocity = Vector2(-400, 0)
	site._ring_collisions()
	check(main.ship.global_position.distance_to(rock.global_position) >= rock.hit_radius + site.PLAYER_RADIUS - 0.5, "pushed out of the ice")
	check(main.ship.velocity.x > 0.0, "bounced back (%.0f)" % main.ship.velocity.x)
	check(main.ship.hull < hull0, "a hard hit hurts (%.1f -> %.1f)" % [hull0, main.ship.hull])
	main.ship.invulnerable = true
	# Not saved with the system.
	var sd: Dictionary = main.get_save_data()
	check(sd["asteroids"].all(func(a): return a["kind"] != "ice"), "a ring's rocks aren't saved with the system")
	# Raiders come; defending the miners earns their empire's thanks.
	site._raid_t = 0.0
	await tree.process_frame
	check(not site._pirates.is_empty(), "raiders came")
	var e: String = site._miner_empire
	var rep0: float = Galaxy.reputation.get(e, 0.0)
	var p: Node2D = site._pirates[0]
	p.take_damage(99999.0, p.global_position, main.ship)
	for i in 3:
		await tree.process_frame
	check(Galaxy.reputation.get(e, 0.0) > rep0, "defending the miners: +reputation with the %s" % e)
	site.leave()
	for i in 3:
		await tree.process_frame
	check_eq(tree.get_nodes_in_group("asteroids").filter(func(r): return r.kind == "ice" and not r.is_queued_for_deletion()).size(), 0, "left: its rocks gone")
	check(tree.get_nodes_in_group("asteroids").size() <= rocks0 + 1, "the system's own rocks kept")


# --- The equipment screens: areas ---------------------------------------------------------------

func test_ship_areas() -> void:
	var main: Node = await _game()
	var d: Node = main.player_data
	for a in Shipyard.AREAS:
		check(Shipyard.area_capacity(d, a) >= 1, "the %s takes something" % a)
	for id in Shipyard.MODULES:
		check(Shipyard.AREA_OF.has(id), "%s has an area" % id)
	for id in Shipyard.HARDPOINT_GEAR + Shipyard.UTILITY_GEAR:
		check(Shipyard.AREA_OF.has(id), "%s has an area" % id)
	check_eq(Shipyard.area_of("gear:focusing_lens:2"), "nose", "a weapon modifier in the nose")
	check_eq(Shipyard.area_of("electro"), "wings", "weapons on the wings")
	# Filling an area: no room for more there.
	var bay := Shipyard.area_capacity(d, "bay")
	for i in bay:
		d.modules.append({"id": "cargo_rack", "rating": 0})
	check_eq(Shipyard.free_for(d, "fuel_tank"), 0, "the bay full: no Fuel Tank")
	check(Shipyard.free_for(d, "gear:focusing_lens:0") > 0, "the nose still free")
	# The dolls build (the Ship Computer's inventory).
	var doll := load("res://scripts/pages/inventory_page.gd").ship_doll(d, main.ship, func(_e, _i): pass, func(_id): pass) as EquipDoll
	check_eq(doll.groups.size(), Shipyard.AREAS.size(), "the ship's doll: a group per area")
	doll.free()
	var lp := LoadoutPanel.new()
	tree.root.add_child(lp)
	lp.setup(d.loadout, d.items, 16, "hold", Callable())
	check_eq(lp._doll.groups.size(), Gear.LOADOUT.size(), "the automaton's doll: a group per slot")
	lp.queue_free()


## Gear on the automaton comes off the ways it goes on: a click on its slot,
## or dragged back onto the items (and right-click).
func test_loadout_takes_off_by_click_and_drag() -> void:
	var lo := {"weapon": Gear.DEFAULT_LOADOUT["weapon"], "passive2": "gear:reinforced_frame:1"}
	var inv := {"scrap": 2}
	var lp := LoadoutPanel.new()
	tree.root.add_child(lp)
	lp.setup(lo, inv, 12, "carried", Callable())
	await tree.process_frame
	var slot: ItemSlot = null
	for sl in lp.find_children("*", "ItemSlot", true, false):
		if sl.item_id == "gear:reinforced_frame:1":
			slot = sl
	check(slot != null, "the equipped frame shows in its slot")
	Settings.set_text_scale("menu", 1.3)
	lp.refresh()
	slot = null
	for sl in lp.find_children("*", "ItemSlot", true, false):
		if sl.item_id == "gear:reinforced_frame:1":
			slot = sl
	var kids := lp.get_child_count()
	var tall := lp.get_combined_minimum_size().y
	var heading_size := (lp.get_child(0) as Label).get_theme_font_size("font_size")
	slot.clicked.emit(slot.item_id)
	check_eq((lp.get_child(0) as Label).get_theme_font_size("font_size"), heading_size, "rebuilt at the player's text size (130%), not back at 100%")
	Settings.set_text_scale("menu", 1.0)
	check_eq(lp.get_child_count(), kids, "rebuilt in place: the old screen gone at once (no frame with both - the page jumping)")
	check(absf(lp.get_combined_minimum_size().y - tall) < 1.0, "the same height right after a change")
	check(not lo.has("passive2") and int(inv.get("gear:reinforced_frame:1", 0)) == 1, "a click on the slot takes it off into the items")
	check(lp.take_from_grid("gear:reinforced_frame:1", "passive2"), "back on")
	await tree.process_frame
	var d := {"src": "loadout", "slot": "passive2", "id": "gear:reinforced_frame:1"}
	check(lp.is_mine(d), "the items take it dragged off the automaton")
	check(lp.take_off("passive2") and not lo.has("passive2"), "dropped on the items: off")
	check(not lp.take_off("weapon"), "the standard rifle stays (the weapon slot is never empty)")
	# The pages' grids take the drop.
	for page in ["res://scripts/pages/field_inventory_page.gd", "res://scripts/pages/inventory_page.gd"]:
		check("_loadout.is_mine(d)" in FileAccess.get_file_as_string(page), page.get_file() + ": its grid takes gear dragged off")
	lp.queue_free()


# --- The Patcher and the Library ---------------------------------------------------------------

func test_patcher_opens_on_the_infographic() -> void:
	var p: Control = load("res://scripts/patcher.gd").new()
	tree.root.add_child(p)
	await tree.process_frame
	for i in p.patches.size():
		if not p.patches[i].get("steps", []).is_empty() and not p.patches[i].get("review", {}).is_empty():
			p._tabs.current_tab = 1
			p.show_patch(i)
			check_eq(p._tabs.current_tab, 0, "a patch opens on its infographic")
			break
	p.queue_free()


## The Library's categories: each its icon and its name (labels beside icons everywhere).
func test_library_categories_have_icon_and_name() -> void:
	var b := AssetBrowser.new()
	tree.root.add_child(b)
	await tree.process_frame
	var root: TreeItem = b._tree.get_root()
	var n := 0
	for o in root.get_children():
		for c in o.get_children():
			n += 1
			check(c.get_text(0) != "" and c.get_icon(0) != null and c.get_tooltip_text(0).begins_with(c.get_text(0)), "a category: its icon and name (%s)" % c.get_tooltip_text(0))
	check(n > 10, "categories (%d)" % n)
	b.queue_free()


# --- Bouncer Plasma ---------------------------------------------------------------------------

func test_bouncer_plasma() -> void:
	var main: Node = await _game()
	Accuracy.sure = true   # (the bounces measured, not the aim: teardown turns it off)
	main.ship.global_position = Vector2(50000, -50000)   # (empty space: no passing ship for the ball to bounce off to)
	var p: Vector2 = main.ship.global_position + Vector2(500, 0)
	var foes := []
	for i in 3:
		var e: Node2D = main.spawn_enemy(p + Vector2(i * 160, (i % 2) * 120))
		e.max_hull = 5000.0
		e.hull = 5000.0
		e.max_shields = 0.0   # (no shields recharging between hits: every hit on the hull)
		e.shields = 0.0
		e.max_speed = 0.0
		foes.append(e)
	var w: Dictionary = Items.WEAPONS["bouncer"]
	PlasmaBouncer.fire(tree, main.ship, foes[0], 20.0, w)
	var web: Node2D = null
	var t0 := Time.get_ticks_msec()
	while web == null and Time.get_ticks_msec() - t0 < 6000:
		await tree.process_frame
		for f in foes:
			if is_instance_valid(f.web):
				web = f.web
	check(foes.all(func(f): return f.hull < 5000.0), "it bounced: every one hit")
	check(foes.any(func(f): return f.hull <= 5000.0 - 40.0), "some hit more than once (6 bounces between 3): %s" % [foes.map(func(f): return f.hull)])
	check(web != null, "then webbed them together")
	if web == null:
		return
	check(foes.all(func(f): return f.web == web), "all three in the web")
	# Slowed, and held within its reach of the others.
	var f0: Node2D = foes[0]
	f0.max_speed = 400.0
	var v: Vector2 = web.constrain(f0, Vector2(400, 0))
	check(v.length() <= 400.0 * w["web_slow"] + 1.0, "slowed (%.0f)" % v.length())
	f0.global_position = web.centre(f0) + Vector2(web.reach + 500.0, 0)
	web.constrain(f0, Vector2(400, 0))
	check(f0.global_position.distance_to(web.centre(f0)) <= web.reach + 1.0, "pulled back within the web's reach of the others")
	check(Shipyard.area_of("bouncer") == "wings" and "bouncer" in Shipyard.HARDPOINT_GEAR, "a wing weapon, sold at Outfitting")


func test_enemy_bouncer_webs_you() -> void:
	var main: Node = await _game()
	var ship: Node2D = main.ship
	var e: Node2D = main.spawn_enemy(ship.global_position + Vector2(400, 0))
	e.max_speed = 0.0
	var mate: Node2D = main.spawn_enemy(ship.global_position + Vector2(400, 150))
	mate.max_speed = 0.0
	PlasmaBouncer.fire(tree, e, ship, 10.0, Items.WEAPONS["bouncer"])
	var t0 := Time.get_ticks_msec()
	while not is_instance_valid(ship.web) and Time.get_ticks_msec() - t0 < 5000:
		await tree.process_frame
	check(is_instance_valid(ship.web), "an enemy's plasma webs you")
	if not is_instance_valid(ship.web):
		return
	check(e in ship.web.members, "tied to the ship that fired it")
	check(mate in ship.web.members, "and its wingman nearby")
	var v: Vector2 = ship.web.constrain(ship, Vector2(ship.max_speed, 0))
	check(v.length() <= ship.max_speed * Items.WEAPONS["bouncer"]["web_slow"] + 1.0, "you're slowed")
	ship.global_position = ship.web.centre(ship) + Vector2(ship.web.reach + 800.0, 0)
	ship.web.constrain(ship, Vector2(300, 0))
	check(ship.global_position.distance_to(ship.web.centre(ship)) <= ship.web.reach + 1.0, "and can't fly away from them")
	var sd: Dictionary = e.get_save_data()
	check(sd.has("bouncer"), "an NPC's Bouncer is saved")


# --- Beam Emitter; the Pulse Cannon's even split --------------------------------------------------

func test_beam_drains_shields() -> void:
	# The split: a beam takes twice its damage off shields, a third off a hull;
	# the Pulse Cannon (and most hits) the same off either.
	check(Gear.split("beam", 100.0, 30.0).is_equal_approx(Vector2(60.0, 0.0)), "a beam on shields: x2 (%s)" % Gear.split("beam", 100.0, 30.0))
	check(Gear.split("beam", 0.0, 30.0).is_equal_approx(Vector2(0.0, 10.5)), "a beam on a hull: x0.35 (%s)" % Gear.split("beam", 0.0, 30.0))
	check(Gear.split("beam", 10.0, 30.0).is_equal_approx(Vector2(10.0, 25.0 * 0.35)), "through the last of the shields")
	check(Gear.split("energy", 100.0, 30.0).is_equal_approx(Vector2(30.0, 0.0)) and Gear.split("energy", 0.0, 30.0).is_equal_approx(Vector2(0.0, 30.0)), "a pulse: the same on shields and hull")
	# Fired: the beam strips a pirate's shields fast.
	var main: Node = await _game()
	var ship: Node2D = main.ship
	main.player_data.add_equipment("beam")
	check(Shipyard.area_of("beam") == "wings" and "beam" in Shipyard.HARDPOINT_GEAR, "a wing weapon, sold at Outfitting")
	var e: Node2D = main.spawn_enemy(ship.global_position + Vector2(0, -300))
	e.max_speed = 0.0
	e.max_shields = 200.0
	e.shields = 200.0
	e.max_hull = 1000.0
	e.hull = 1000.0
	ship.select_weapon("beam")
	Accuracy.sure = true   # (the drain measured, not the aim: no tick missing)
	ship.set_attack_target(e)
	await tree.create_timer(1.0).timeout
	Accuracy.sure = false
	check(e.shields < 200.0 - Items.WEAPONS["beam"]["damage"] * 1.2, "shields drained fast (%.0f left)" % e.shields)
	check(is_equal_approx(e.hull, 1000.0) or e.shields <= 0.0, "the hull untouched while shields last")


# --- The cloak -------------------------------------------------------------------------------

func test_cloak() -> void:
	var main: Node = await _game()
	var ship: Node2D = main.ship
	main.player_data.add_equipment("cloak")
	check("cloak" in main.player_data.toolbar, "on the toolbar")
	var e: Node2D = main.spawn_enemy(ship.global_position + Vector2(0, -400))
	e.max_speed = 0.0
	ship.shields = 80.0
	ship.use_system("cloak")
	check(ship.cloaked, "cloaked")
	check(ship.shields == 0.0, "shields down while cloaked")
	check(ship.sprite.material is ShaderMaterial and ship.sprite.material.shader.resource_path.ends_with("cloak.gdshader"), "the cloak's shimmer on the hull")
	check(not e._valid_target(ship), "no enemy can see you")
	await tree.create_timer(0.3).timeout
	check(ship.shields == 0.0, "still down")
	# Firing breaks it.
	ship.set_attack_target(e)
	var t0 := Time.get_ticks_msec()
	while ship.cloaked and Time.get_ticks_msec() - t0 < 3000:
		await tree.process_frame
	check(not ship.cloaked, "firing ends the cloak")
	check(e._valid_target(ship), "seen again")
	await tree.create_timer(ship.CLOAK_SWEEP + 0.2).timeout
	check(not (ship.sprite.material is ShaderMaterial and ship.sprite.material.shader.resource_path.ends_with("cloak.gdshader")), "the paint back once it's off")
	ship.set_attack_target(null)
	await tree.create_timer(1.0).timeout
	check(ship.shields > 10.0 and ship.shields < 80.0, "shields coming back (%.0f after 1 s)" % ship.shields)
	await tree.create_timer(1.3).timeout
	check(ship.shields >= 79.0, "back to where they were in 2 s (%.0f)" % ship.shields)


# --- The Projection Array ---------------------------------------------------------------------

func test_projection_array() -> void:
	var main: Node = await _game()
	var ship: Node2D = main.ship
	main.player_data.add_equipment("projection_array")
	check("projection_array" in main.player_data.toolbar, "on the toolbar")
	var foes := []
	for i in 8:
		var e: Node2D = main.spawn_enemy(ship.global_position + Vector2.from_angle(i * TAU / 8.0) * 600.0)
		e.max_speed = 0.0
		e._target = ship
		e.process_mode = Node.PROCESS_MODE_DISABLED   # (frozen: their shots would end the illusions early)
		foes.append(e)
	ship.use_system("projection_array")
	await tree.process_frame
	var decoys: Array = tree.get_nodes_in_group("player_decoys")
	check_eq(decoys.size(), 2, "two illusions")
	check(decoys.all(func(d): return d.global_position.distance_to(ship.global_position) < 400.0), "flying beside you")
	check(foes.any(func(e): return e._target in decoys), "some enemies now attack an illusion")
	# A new attacker takes its pick too (once).
	var late: Node2D = main.spawn_enemy(ship.global_position + Vector2(0, 700))
	late.process_mode = Node.PROCESS_MODE_DISABLED
	var picks := {}
	for i in 20:
		late._decoy_pa = null
		picks[late._decoyed(ship)] = true
	check(picks.size() >= 2, "a new attacker picks among you and them")
	# Hit, an illusion is gone.
	var d0: Node2D = decoys[0]
	d0.take_damage(5.0, d0.global_position, foes[0])
	check(not d0.is_alive() and not d0.is_in_group("player_decoys"), "hit: gone")
	# The shuffle: your ship and an illusion trade places.
	var pa: Node = tree.get_first_node_in_group("projection_arrays")
	var before: Vector2 = ship.global_position
	var other: Node2D = decoys[1]
	var at: Vector2 = other.global_position
	pa._shuffle()
	check(ship.global_position.is_equal_approx(at), "you took the illusion's place")
	check(other.global_position.is_equal_approx(before), "and it took yours")
	# Over after its time.
	if is_instance_valid(pa):
		pa._t = ProjectionArray.LIFE
	await tree.process_frame
	await tree.process_frame
	check(tree.get_nodes_in_group("player_decoys").is_empty(), "gone after %d s" % ProjectionArray.LIFE)
