extends TestCase
## The galaxy simulation: map, economy, traders, diplomacy, saving.

var _was_active := false


func setup() -> void:
	_was_active = Galaxy.active
	Galaxy.new_game(false)


func teardown() -> void:
	Galaxy.active = _was_active


func test_home_cluster_is_minoan() -> void:
	check_eq(Galaxy.owner_of(Galaxy.HOME), "minoa", "home system owner")
	var own := Galaxy.neighbors(Galaxy.HOME).filter(func(n): return Galaxy.owner_of(n) == "minoa")
	check(own.size() >= 2, "only %d Minoan neighbours" % own.size())


func test_map_connected() -> void:
	for a in Galaxy.SYSTEMS:
		for b in Galaxy.SYSTEMS:
			if a != b:
				check(not Galaxy.find_route(a, b).is_empty(), "no route %s -> %s" % [a, b])


func test_simulation_runs() -> void:
	Galaxy.active = true
	for i in 1200:   # 10 minutes of game time
		Galaxy._process(0.5)
	check(Galaxy.traders.size() > 0, "no traders")
	for id in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[id]
		check(EnemyTypes.has_type(r["type"]), "trader %s flies unknown class %s" % [id, r["type"]])
		check(r["role"] in ["trader", "miner", "explorer"], "trader %s has role %s" % [id, r["role"]])
	for sid in Galaxy.stations:
		for c in Galaxy.COMMODITIES:
			var p := Galaxy.price(sid, c)
			check(is_finite(p) and p > 0.0, "%s %s price %s" % [sid, c, p])


func test_save_round_trip() -> void:
	Galaxy.active = true
	for i in 200:
		Galaxy._process(0.5)
	var d := Galaxy.get_save_data()
	var text := JSON.stringify(d)
	Galaxy.new_game(false)
	Galaxy.load_save_data(JSON.parse_string(text))
	check_eq(JSON.stringify(Galaxy.get_save_data()), text, "save data after a round trip")


func test_old_save_migrates() -> void:
	var d := Galaxy.get_save_data()
	d["traders"] = {"t1": {"id": "t1", "type": "athens_05", "role": "cargo_hauler", "empire": "athens", "name": "Argo",
		"cargo": {}, "credits": 900, "capacity": 60, "system": Galaxy.HOME, "state": "docked",
		"station": Galaxy.system(Galaxy.HOME)["stations"][0], "wait": 5.0, "legs": [], "t": 0.0, "live": false, "dest": ""}}
	Galaxy.load_save_data(JSON.parse_string(JSON.stringify(d)))
	var r: Dictionary = Galaxy.traders["t1"]
	check(EnemyTypes.has_type(r["type"]), "retired class not replaced: " + str(r["type"]))
	check_eq(r["role"], "trader", "old role name migrated")


## Your trades leave a footprint on a station's price that fades; it bites
## harder where the good is scarce. Bounties scale with the pirate ship.
func test_player_market_footprint() -> void:
	var sid: String = Galaxy.systems[Galaxy.HOME]["stations"][0]
	var st: Dictionary = Galaxy.stations[sid]
	var c := "food"
	st["stock"][c] = 150.0
	st["impact"].clear()
	var d = load("res://scripts/player_data.gd").new()
	d.credits = 100000
	d.items = {}
	var p0 := Galaxy.price(sid, c)
	check_eq(Galaxy.player_buy(sid, c, 20, d), 20, "bought 20")
	var p_stock := Galaxy.price(sid, c) / exp(st["impact"][c])
	check(Galaxy.price(sid, c) > p_stock * 1.05, "buying pushes the price above what the stock alone gives")
	for i in 400:
		Galaxy._economy_tick()
	check(not st["impact"].has(c), "the footprint fades away")
	# Selling where it's scarce moves the price harder than where it's plentiful.
	st["impact"].clear()
	st["stock"][c] = 5.0
	Galaxy.player_sell(sid, c, 10, d)
	var scarce: float = -st["impact"][c]
	st["impact"].clear()
	st["stock"][c] = 200.0
	d.add_item(c, 10)
	Galaxy.player_sell(sid, c, 10, d)
	var plenty: float = -st["impact"][c]
	check(scarce > plenty * 1.5, "selling into scarcity floods it faster (%.3f vs %.3f)" % [scarce, plenty])
	# Saved and loaded.
	var save := Galaxy.get_save_data()
	Galaxy.load_save_data(JSON.parse_string(JSON.stringify(save)))
	check(absf(Galaxy.stations[sid]["impact"].get(c, 0.0) + plenty) < 0.001, "the footprint is saved")
	d.free()
	check(p0 > 0.0, "a price")
	check_eq(Galaxy.pirate_bounty(100.0, 0.0), 160, "a fighter's bounty")
	check(Galaxy.pirate_bounty(300.0, 0.0) > Galaxy.pirate_bounty(75.0, 0.0), "bigger ships pay more")


## The economy doesn't starve: after 20 minutes few station stocks are empty,
## the production chains mostly run, and every inhabited system's second
## station makes staples.
func test_economy_stays_supplied() -> void:
	for id in Galaxy.systems:
		var sys: Dictionary = Galaxy.systems[id]
		if id != Galaxy.HOME and sys["owner"] != "pirates":
			check(Galaxy.stations[sys["stations"][1]]["economy"] in ["agricultural", "mining", "refinery"], "%s has a staples station" % id)
	Galaxy.active = true
	for i in 2400:
		Galaxy._process(0.5)
	var empty := 0
	var n := 0
	var effs := []
	for sid in Galaxy.stations:
		for c in Galaxy.stations[sid]["stock"]:   # (the goods it deals in)
			n += 1
			if Galaxy.stations[sid]["stock"][c] < 1.0:
				empty += 1
		effs.append(Galaxy.stations[sid].get("efficiency", 1.0))
	effs.sort()
	check(empty < n * 0.15, "few empty stocks (%d of %d)" % [empty, n])
	check(effs[effs.size() / 2] >= 0.5, "the median station runs at least half speed (%.2f)" % effs[effs.size() / 2])


## Names: each system is one of its empire's most famous cities or places, and
## its star has the same name; planets are named after lesser places of the
## same empire - every one different, never a system's (or star's) name.
func test_system_star_and_planet_names() -> void:
	Galaxy.new_game(false)
	var sys_names := {}
	for id in Galaxy.SYSTEMS:
		var n: String = Galaxy.SYSTEMS[id]["name"]
		check(not sys_names.has(n), "one system called %s" % n)
		sys_names[n] = true
		check_eq(Galaxy.systems[id]["name"], n, "%s: its star and system share the name" % id)
	check_eq(Galaxy.SYSTEMS["atrapos"]["name"], "Knossos", "home: Knossos")
	var planet_names := {}
	for id in Galaxy.systems:
		var sys: Dictionary = Galaxy.systems[id]
		for p in sys["planets"]:
			var n: String = p["name"]
			if p["moon_of"] != "":   # moons: their planet's name and a numeral
				check(n.begins_with(Galaxy.planet_record(p["moon_of"])["name"] + " "), "%s: the moon %s is named after its planet" % [id, n])
				continue
			check(not sys_names.has(n), "%s: the planet %s isn't a system's name" % [id, n])
			check(not planet_names.has(n), "one planet called %s" % n)
			planet_names[n] = true
			var base: String = n
			for g in [" Beta", " Gamma", " Delta", " Epsilon", " Zeta", " Eta"]:
				base = base.trim_suffix(g)   # (an empire's names used up: again with a Greek letter)
			check(base in Galaxy.PLANET_NAMES[sys["owner"]], "%s: %s is a place of its empire (%s)" % [id, n, sys["owner"]])
	for pid in Planets.PLANETS:   # the home system's named planets
		var n: String = Planets.PLANETS[pid]["name"]
		check(not sys_names.has(n) and not planet_names.has(n), "the home planet %s has a name of its own" % n)


## Generated systems: 1 to 12 planets of the four landable types, some with
## moons; every one landable (its type's surface, its own name and seed);
## the gates beyond the outermost orbit.
func test_generated_planets() -> void:
	var counts := {}
	var types := {}
	var moons := 0
	var seeds := {}
	for id in Galaxy.systems:
		if id == Galaxy.HOME:
			continue
		var sys: Dictionary = Galaxy.systems[id]
		var main_planets: Array = sys["planets"].filter(func(p): return p["moon_of"] == "")
		check(main_planets.size() >= 1 and main_planets.size() <= Galaxy.MAX_PLANETS, "%s: %d planets" % [id, main_planets.size()])
		counts[main_planets.size()] = true
		var outer := 0.0
		for p in sys["planets"]:
			var pd := Planets.get_planet(p["id"])
			check(not pd.is_empty() and pd["landable"], "%s: %s can be landed on" % [id, p["id"]])
			check_eq(pd["name"], p["name"], "%s: its surface carries its name" % p["id"])
			check(not seeds.has(pd["seed"]), "%s: a seed of its own" % p["id"])
			seeds[pd["seed"]] = true
			if p["moon_of"] == "":
				check(p["type"] in ["ocean", "ice", "volcanic", "gas_giant"], "%s: one of the four types (%s)" % [p["id"], p["type"]])
				check_eq(pd["tiles"], Planets.PLANETS[Planets.TYPES[p["type"]]["base"]]["tiles"], "%s: its type's surface" % p["id"])
				types[p["type"]] = true
				outer = maxf(outer, p["orbit"] + p["size"] / 2.0)
			else:
				moons += 1
				check_eq(p["type"], "moon", "%s: a moon" % p["id"])
				check(Galaxy.planet_record(p["moon_of"]).get("system", "") == id, "%s orbits a planet of its system" % p["id"])
		for g in sys["gates"]:
			check((sys["gates"][g] as Vector2).length() > outer, "%s: the gate to %s is beyond the planets" % [id, g])
	check_eq(types.size(), 4, "all four types appear")
	check(moons > 0, "some planets have moons")
	check(counts.size() >= 4, "systems differ in size (%s)" % [counts.keys()])
	check(Planets.get_planet("no_such_planet").is_empty(), "unknown ids: no planet")
	check_eq(Planets.get_planet("thalassa")["name"], "Amnissos", "the named planets are still themselves")


## Landing on a generated planet and on a moon: their type's surface, under
## their own name, with their type's environment.
func test_land_on_generated_planets() -> void:
	var old := SaveGame.landed_planet
	var picks := {}
	for id in Galaxy.planets:
		var rec: Dictionary = Galaxy.planets[id]
		if not picks.has(rec["type"]):
			picks[rec["type"]] = id
	for type in ["ice", "moon"]:
		var pid: String = picks[type]
		check_eq(Planets.environment(pid)["speed"], 0.8 if type in ["ice", "moon"] else 1.0, "%s (%s): its type's environment" % [pid, type])
		SaveGame.landed_planet = pid
		var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
		tree.root.add_child(s)
		while not s.is_built:
			await tree.process_frame
		s.set_process(false)
		check_eq(s.pdata["name"], Galaxy.planets[pid]["name"], "%s: its own name" % pid)
		check_eq(s.pdata["tiles"], Planets.PLANETS[Planets.TYPES[type]["base"]]["tiles"], "%s: its type's tiles" % pid)
		check(s.walkable_at(s.pilot.position), "%s: you stand on solid ground" % pid)
		s.queue_free()
		await tree.process_frame
	SaveGame.landed_planet = old


## The grown galaxy: every empire holds 6 to 12 systems, all reachable, no
## two systems on top of each other, no gate lanes crossing.
func test_grown_galaxy() -> void:
	var by := {}
	for id in Galaxy.SYSTEMS:
		var o: String = Galaxy.SYSTEMS[id]["owner"]
		by[o] = by.get(o, 0) + 1
	for e in Galaxy.MAJOR:
		check(by.get(e, 0) >= 6 and by.get(e, 0) <= 12, "%s holds 6 to 12 systems (%d)" % [e, by.get(e, 0)])
	for id in Galaxy.BASE_SYSTEMS:
		check(Galaxy.SYSTEMS.has(id), "the story's system %s is still there" % id)
	var seen := {Galaxy.HOME: true}
	var q := [Galaxy.HOME]
	while not q.is_empty():
		var c = q.pop_front()
		for n in Galaxy.neighbors(c):
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	check_eq(seen.size(), Galaxy.SYSTEMS.size(), "every system reachable from home")
	var ids: Array = Galaxy.SYSTEMS.keys()
	var names := {}
	for i in ids.size():
		check(not names.has(Galaxy.SYSTEMS[ids[i]]["name"]), "one system called %s" % Galaxy.SYSTEMS[ids[i]]["name"])
		names[Galaxy.SYSTEMS[ids[i]]["name"]] = true
		for j in range(i + 1, ids.size()):
			check(Galaxy.SYSTEMS[ids[i]]["pos"].distance_to(Galaxy.SYSTEMS[ids[j]]["pos"]) >= 99.0, "%s and %s apart" % [ids[i], ids[j]])
	var crossing := 0
	for a in Galaxy.LINKS.size():
		for b in range(a + 1, Galaxy.LINKS.size()):
			var l1: Array = Galaxy.LINKS[a]
			var l2: Array = Galaxy.LINKS[b]
			if l1[0] in l2 or l1[1] in l2:
				continue
			if Geometry2D.segment_intersects_segment(Galaxy.SYSTEMS[l1[0]]["pos"], Galaxy.SYSTEMS[l1[1]]["pos"], Galaxy.SYSTEMS[l2[0]]["pos"], Galaxy.SYSTEMS[l2[1]]["pos"]) != null:
				crossing += 1
	check(crossing <= 2, "gate lanes don't cross (the grown ones never; %d crossings, the hand-made map's own)" % crossing)


## The Cycladic Isles: a major power with its own ships, stations and systems.
func test_cycladic_isles() -> void:
	check("cyclades" in Galaxy.MAJOR, "a major power")
	check(Galaxy.SYSTEMS.has("keros") and Galaxy.SYSTEMS["keros"]["owner"] == "cyclades", "Keros is theirs")
	check_eq(StationArt.BY_EMPIRE["cyclades"].size(), 12, "twelve station designs")
	for role in ["fighter", "interceptor", "gunship", "frigate", "trader", "miner", "explorer"]:
		var id := ShipDesigns.pick("cyclades", [role])
		check(id != "" and ShipDesigns.owner_of(id) == "cyclades", "a Cycladic %s (%s)" % [role, id])
		check(ProcArt.has_sprite("ship_" + id), "%s has a sprite" % id)
	var stations := Galaxy.stations.keys().filter(func(s): return Galaxy.station_owner(s) == "cyclades")
	check(stations.size() >= 8, "Cycladic stations (%d)" % stations.size())
