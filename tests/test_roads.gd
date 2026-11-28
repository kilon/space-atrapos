extends TestCase
## Roads (CosmosRoads) between a world's towns - its cities and villages
## (CosmosTown.sites) - and their life (CosmosCaravans, CosmosTraveller): the
## network, the ways over the ground, the ribbons drawn on it, the towns'
## stocks that caravans carry, the travellers out near you, the raiders.

var _old_system := ""


func setup() -> void:
	_old_system = Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""


## The inhabited worlds of the first systems: [shape, rec, sites].
func _worlds(n := 10) -> Array:
	var out: Array = []
	for sid in Galaxy.systems.keys().slice(0, 8):
		for rec in Cosmos.planet_records(sid):
			var sh := PlanetShape.of(rec, false)
			if sh.kind != "rocky":
				continue
			var s := CosmosTown.sites(sh, rec, Galaxy.owner_of(sid), Vector3(1, 0, 0))
			if s.size() < 2:
				continue
			sh.set_flats(CosmosTown.flats_of(s, sh.radius))
			out.append([sh, rec, s])
			if out.size() >= n:
				return out
	return out


func test_worlds_have_cities_and_villages() -> void:
	var ws := _worlds(12)
	check(ws.size() >= 6, "inhabited worlds found (%d)" % ws.size())
	var most_cities := 0
	for w in ws:
		var sites: Array = w[2]
		var cities := sites.filter(func(s): return s["kind"] == "city").size()
		check(cities >= 1 and cities <= 3, "%s: 1-3 cities (%d)" % [w[1].get("name", "?"), cities])
		most_cities = maxi(most_cities, cities)
		check_eq(str(sites[0]["kind"]), "city", "the first still a city (its palace)")
		var names := {}
		for s in sites:
			names[s["name"]] = true
		check_eq(names.size(), sites.size(), "each town its own name")
		for i in sites.size():
			for j in range(i + 1, sites.size()):
				var ang := acos(clampf((sites[i]["dir"] as Vector3).dot(sites[j]["dir"]), -1.0, 1.0))
				check(ang * (w[0] as PlanetShape).radius > CosmosTown.MORE_APART - 1.0, "towns apart")
	check(most_cities >= 2, "some worlds with more than one city (%d)" % most_cities)
	# The sites a world had before stay where they were: the extra ones come after them.
	var sh: PlanetShape = ws[0][0]
	var again := CosmosTown.sites(sh, ws[0][1], str(ws[0][2][0]["empire"]), Vector3(1, 0, 0))
	check_eq(again.size(), (ws[0][2] as Array).size(), "the same sites each time")
	check((again[0]["dir"] as Vector3).is_equal_approx(ws[0][2][0]["dir"]), "in the same places")


func test_network_joins_towns_over_land() -> void:
	var roads_seen := 0
	for w in _worlds(6):
		var sh: PlanetShape = w[0]
		var sites: Array = w[2]
		var t0 := Time.get_ticks_msec()
		var net := CosmosRoads.network(sh, sites)
		check_lt(Time.get_ticks_msec() - t0, 6000.0, "a world's network made in seconds (on a worker)")
		check(net.size() <= sites.size() * 2, "a sparse network (%d roads, %d towns)" % [net.size(), sites.size()])
		for r in net:
			roads_seen += 1
			var pts: PackedVector3Array = r["pts"]
			var cum: PackedFloat32Array = r["cum"]
			check(pts.size() > 10, "a road of many points")
			check(absf(float(cum[cum.size() - 1]) - float(r["length"])) < 0.01, "its length")
			# Its ends in the two towns, on their levelled ground.
			var a: Vector3 = sites[r["a"]]["dir"]
			var b: Vector3 = sites[r["b"]]["dir"]
			check(pts[0].distance_to(a) * sh.radius < float(sites[r["a"]]["r"]) * 1.1, "starts in town a")
			check(pts[pts.size() - 1].distance_to(b) * sh.radius < float(sites[r["b"]]["r"]) * 1.1, "ends in town b")
			# A point every STEP m, none in the sea.
			var wet := 0
			var worst_gap := 0.0
			for i in pts.size():
				if i > 0:
					worst_gap = maxf(worst_gap, pts[i].distance_to(pts[i - 1]) * sh.radius)
				if sh.sea == 1 and sh.height(pts[i]) < 0.0:
					wet += 1
			check(worst_gap < CosmosRoads.STEP * 1.35, "a point every %.0f m (worst gap %.1f)" % [CosmosRoads.STEP, worst_gap])
			check(wet < pts.size() / 50 + 2 or (wet * CosmosRoads.STEP < CosmosTown.LONG_CAUSEWAY + 120.0 and float(r.get("wet", 0.0)) > 0.0),
				"over land, or a causeway's water at most (%d of %d points wet)" % [wet, pts.size()])
			# Along it: point() at its ends and between.
			check(CosmosRoads.point(r, 0.0).is_equal_approx(pts[0]), "point at 0: its start")
			check(CosmosRoads.point(r, float(r["length"]) + 50.0).is_equal_approx(pts[pts.size() - 1]), "past its end: its end")
			var mid := CosmosRoads.point(r, float(r["length"]) * 0.5)
			check(absf(mid.length() - 1.0) < 0.001, "a unit direction")
	check(roads_seen >= 4, "roads made (%d)" % roads_seen)


## A road out of a town leaves by a gate - where one of its streets meets its
## edge (TownStreets) - with no gap and no overlap, and goes on in along that
## street. Every world with towns has two cities or more, joined by roads; every
## city is on a main road (or, on an island no causeway reaches, a track to a
## village); no road crosses more water than a causeway.
func test_roads_join_streets_and_cities() -> void:
	var lone := 0
	var cw := 0
	for w in _worlds(10):
		var sh: PlanetShape = w[0]
		var sites: Array = w[2]
		var nm: String = str(w[1].get("id", "?"))
		var net := CosmosRoads.network(sh, sites)
		var cities: Array = range(sites.size()).filter(func(i): return sites[i]["kind"] == "city")
		check(cities.size() >= 2, "%s: two cities or more (%d)" % [nm, cities.size()])
		var adj := {}
		for r in net:
			var dr: Vector2i = r["drawn"]
			var pts: PackedVector3Array = r["pts"]
			for e in [[int(r["a"]), dr.x, 0], [int(r["b"]), dr.y, pts.size() - 1]]:
				var st: Dictionary = sites[e[0]]
				var inv := CosmosTown.frame(st, sh.radius).affine_inverse()
				var q: Vector3 = inv * (pts[e[1]] * (sh.radius + float(st["h"])))
				var best := INF
				for g in TownStreets.gates(str(st["kind"]), str(st["empire"])):
					best = minf(best, Vector2(q.x - (g["at"] as Vector3).x, q.z - (g["at"] as Vector3).z).length())
				check(best < 0.5, "%s: its road meets a street's end at a gate (%.2f m off)" % [nm, best])
				var inner: Vector3 = inv * (pts[e[2]] * (sh.radius + float(st["h"])))
				check(TownStreets.on_street(str(st["kind"]), str(st["empire"]), inner, 0.5), "%s: and goes on in along the street" % nm)
			check(float(r.get("wet", 0.0)) <= CosmosTown.LONG_CAUSEWAY + 60.0, "%s: no more water than a causeway (%.0f m)" % [nm, float(r.get("wet", 0.0))])
			if float(r.get("wet", 0.0)) > 1.0:
				cw += 1
			check_eq(bool(r["main"]), sites[r["a"]]["kind"] == "city" and sites[r["b"]]["kind"] == "city", "%s: city to city a main road" % nm)
			adj[int(r["a"])] = adj.get(int(r["a"]), []) + [int(r["b"])]
			adj[int(r["b"])] = adj.get(int(r["b"]), []) + [int(r["a"])]
		# The first city joined to another by road.
		var seen := {cities[0]: true}
		var todo: Array = [cities[0]]
		while not todo.is_empty():
			var i: int = todo.pop_back()
			for j in adj.get(i, []):
				if not seen.has(j):
					seen[j] = true
					todo.append(j)
		check(cities.slice(1).any(func(ci): return seen.has(ci)), "%s: two of its cities joined by road" % nm)
		for ci in cities:
			if not net.any(func(r): return r["main"] and (int(r["a"]) == ci or int(r["b"]) == ci)):
				lone += 1
				check(adj.has(ci), "%s: a city with no main road has a track at least" % nm)
	print("  (cities not on a main road: %d; roads over a causeway: %d)" % [lone, cw])


func test_roads_keep_off_the_landing_fields() -> void:
	var worlds := _worlds(6)
	var checked := 0
	var bad := 0
	for w in worlds:
		var sh: PlanetShape = w[0]
		var towns: Array = w[2]
		var net := CosmosRoads.network(sh, towns)
		var fields := CosmosRoads.fields_of(sh, towns)
		for r in net:
			var pts: PackedVector3Array = r["pts"]
			var dr: Vector2i = r.get("drawn", Vector2i(0, pts.size() - 1))
			for i in range(dr.x, dr.y + 1):
				checked += 1
				if CosmosRoads.in_field(fields, pts[i] * sh.radius):
					bad += 1
	check(checked > 100, "roads looked at (%d points)" % checked)
	check(bad == 0, "no road over a landing field or its pads (%d of %d points)" % [bad, checked])


func test_path_goes_round_the_sea() -> void:
	# An ocean world: a way between two points of land with sea between them goes round it, or there's none.
	var rec := {"id": "road_t", "type": "ocean", "template": "ocean", "variant": 3, "size": 600.0, "seed": 4321}
	var sh := PlanetShape.of(rec, false)
	var land: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	while land.size() < 40:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		if sh.height(d) > 6.0:
			land.append(d)
	var tried := 0
	for i in 20:
		var a: Vector3 = land[i]
		var b: Vector3 = land[i + 20]
		if a.distance_to(b) * sh.radius > 4000.0:
			continue
		tried += 1
		var p := CosmosRoads.path(sh, a, b)
		for d in p:
			if sh.height(d) < 1.2 and not d.is_equal_approx(a) and not d.is_equal_approx(b):
				check(false, "a path cell in the sea (%.1f m)" % sh.height(d))
				return
	check(tried > 0, "pairs tried")


func test_road_piece_lies_on_the_ground() -> void:
	var w: Array = _worlds(1)[0]
	var sh: PlanetShape = w[0]
	var net := CosmosRoads.network(sh, w[2])
	check(not net.is_empty(), "a road")
	if net.is_empty():
		return
	var pts: PackedVector3Array = net[0]["pts"]
	var res := CosmosRoads.piece_mesh(sh, pts, 0, mini(CosmosRoads.CHUNK_PTS + 1, pts.size()), 0.0, Vector2(CosmosRoads.PAVED, -1.0), float(net[0]["length"]))
	check(res.size() == 2, "its mesh's arrays and its centre")
	var arr: Array = res[0]
	var c: Vector3 = res[1]
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var rows := (mini(CosmosRoads.CHUNK_PTS + 1, pts.size()) - 1) * CosmosRoads.SUB + 1
	check_eq(v.size(), rows * 6, "six columns a row, %d rows a point" % CosmosRoads.SUB)
	var worst := 0.0
	for p in v:
		var g := p + c
		var d := g.normalized()
		worst = maxf(worst, absf(g.length() - sh.radius - maxf(sh.surface(d), 0.0)))
	check_lt(worst, 0.2, "draped on the ground (worst %.2f m)" % worst)
	check(col[0].r > 0.9, "paved out of a city")
	var up := (v[0] + c).normalized()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := (v[idx[1]] - v[idx[0]]).cross(v[idx[2]] - v[idx[0]])
	check(n.dot(up) < 0.0, "wound to face up (clockwise front faces)")
	check(CosmosRoads.warm_mesh().get_surface_count() == 1, "a warm-up piece")


func test_caravans_carry_goods_and_meet_raiders() -> void:
	Galaxy.current_system = Galaxy.HOME
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	var cv := CosmosCaravans.attach(c)
	check(cv == CosmosCaravans.attach(c), "one a Cosmos")
	check(c.get_node_or_null("Roads") != null and c.get_node_or_null("Loot") != null, "its roads and loot with it")
	# A world with roads: near it, they're made.
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if p.towns.size() >= 2 and not CosmosRoads.network(p.shape, p.towns).is_empty():
			pl = p
			break
	check(pl != null, "a world of the home system with roads")
	if pl == null:
		c.queue_free()
		return
	var i := c.planets.find(pl)
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	var roads := CosmosRoads.of(c)
	t0 = Time.get_ticks_msec()
	while roads.roads_of(pl).is_empty() and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
	var rl: Array = roads.roads_of(pl)
	check(not rl.is_empty(), "its roads made as you came near (%d)" % rl.size())
	await tree.process_frame
	var w := CosmosCaravans.world_of(pl)
	check(not w.is_empty() and (w["groups"] as Array).size() >= rl.size(), "travellers on its roads (%d)" % (w["groups"] as Array).size() if not w.is_empty() else -1)
	if w.is_empty():
		c.queue_free()
		return
	# Logistics: a caravan arriving unloads into its town's stock and loads for the next.
	var g: Dictionary = cv._new_group(w, pl, rl, 0, 1, float(rl[0]["length"]) - 1.0, "caravan")
	var dest := CosmosCaravans._dest(g, rl)
	var load := {}
	for m in g["members"]:
		for k in m["goods"]:
			load[k] = int(load.get(k, 0)) + int(m["goods"][k])
	var st: Dictionary = w["stock"][dest]
	var before := {}
	for k in load:
		before[k] = float(st.get(k, 0.0))
	cv._simulate(w, pl, rl, 2.0)
	check(not load.is_empty(), "a caravan sets out loaded (%s)" % str(load))
	for k in load:
		if not k in w["makes"][dest]:   # (what the town makes itself it may load again at once)
			check(float(st.get(k, 0.0)) > float(before[k]) + int(load[k]) - 0.5, "its %s into the town's stock (%.0f -> %.0f)" % [k, before[k], float(st.get(k, 0.0))])
	check(float(g["halt"]) > 0.0 and CosmosCaravans._from(g, rl) == dest, "a rest in the town, then off along another road from it")
	# Robbed out of your sight: its remains in the road.
	var loot := CosmosLoot.of(c)
	var n0 := loot.drops.size()
	var lost := false
	for k in 30:
		var g2: Dictionary = cv._new_group(w, pl, rl, 0, 1, 50.0, "pilgrims")
		cv._far_raid(g2, pl, CosmosCaravans.where(pl, rl, g2, 50.0), RandomNumberGenerator.new())
		if g2.get("gone", false):
			lost = true
			break
	check(lost and loot.drops.size() > n0, "a raid lost leaves the group's remains to loot")
	# Near you: its people out on the road, walking it; raiders fall on them.
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	check(c.walker != null, "on foot")
	if c.walker == null:
		c.queue_free()
		return
	var road: Dictionary = rl[0]
	var s := float(road["length"]) * 0.5
	var g3: Dictionary = cv._new_group(w, pl, rl, 0, 1, s, "caravan")
	g3["raided"] = true   # (no ambush of its own while it's watched: one's set off below)
	var here := CosmosCaravans.where(pl, rl, g3, s - 30.0, 6.0)
	c.walker.global_position = pl.to_global(here)
	c._shift_origin(true)
	for k in 40:
		await tree.process_frame
	check(g3["out"], "the group out near you")
	var people: Array = c.npcs.filter(func(x): return x is CosmosTraveller and is_instance_valid(x) and x.group == g3)
	check(people.size() >= 2, "its people in the world (%d)" % people.size())
	check(c.creatures.any(func(x): return is_instance_valid(x) and x.has_meta("caravan")), "its pack donkey too")
	check(people.all(func(x): return x.friendly), "friendly")
	var s0 := float(g3["s"])
	for k in 120:
		await tree.process_frame
	check(float(g3["s"]) > s0, "walking its road (%.1f -> %.1f)" % [s0, float(g3["s"])])
	# Town guards leave them be.
	var guard := CosmosNpc.new()
	guard.cosmos = c
	guard.set_process(false)
	c.world.add_child(guard)   # (in the world: where it stands - the pirates and beasts round it measured from there)
	check(not people.has(guard._nearest_foe(500.0)) or guard._nearest_foe(500.0) == null, "not a town guard's foe")
	guard.free()
	g3["ambush"] = 0.05
	for k in 60:
		await tree.process_frame
	check((g3["raiders"] as Array).size() >= 2, "raiders fall on it (%d)" % (g3["raiders"] as Array).size())
	check(g3["seen"].has("raid"), "the event log notes it")
	for r in g3["raiders"]:
		if is_instance_valid(r):
			check(not r.friendly, "a raider's hostile")
			r.hurt(1000.0, r.global_position)
	for k in 10:
		await tree.process_frame
	check(loot.drops.any(func(e): return str(e["title"]) == "raider"), "a dead raider's loot")
	# Away from it: back into numbers.
	c.walker.global_position = pl.to_global(CosmosCaravans.where(pl, rl, g3, s + 900.0))
	c._shift_origin(true)
	for k in 5:
		await tree.process_frame
	check(not g3["out"], "put away when you're far")
	check(not c.npcs.any(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion() and x is CosmosTraveller and x.group == g3), "its people gone")
	c.queue_free()
	await tree.process_frame
	await tree.process_frame
