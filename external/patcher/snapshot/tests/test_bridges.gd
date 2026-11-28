extends TestCase
## The roads' bridges (CosmosRoads.Bridges - road_bridges.gd): wherever a road
## crosses water - Amnissos's straits, its rivers - a stone bridge with its deck
## over the water, ramps down to the banks, parapets, piers; stood and walked on
## (its floor, its walls), crossed by the caravans; the same each time.

const BR := preload("res://scripts/world/life/road_bridges.gd")

var _old_system := ""
static var _net := {}   # (Amnissos's network and ground: made once for these tests)


func setup() -> void:
	_old_system = Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""


func _amnissos_rec() -> Dictionary:
	for r in Cosmos.planet_records(Galaxy.HOME):
		if str(r.get("name", "")) == "Amnissos":
			return r
	return {}


## Amnissos as CosmosPlanet makes it (towns levelled, its water) and its roads: {sh, towns, roads}.
func _amnissos() -> Dictionary:
	if _net.is_empty():
		var rec := _amnissos_rec()
		var sh := PlanetShape.of(rec, false)
		var towns := CosmosTown.sites(sh, rec, Galaxy.owner_of(str(rec.get("system", Galaxy.HOME))))
		sh.set_flats(CosmosTown.flats_of(towns, sh.radius))
		sh.water = PlanetWater.make(sh)
		var t0 := Time.get_ticks_msec()
		var roads := CosmosRoads.network(sh, towns)
		_net = {"sh": sh, "towns": towns, "roads": roads, "ms": Time.get_ticks_msec() - t0}
	return _net


func _all_bridges(roads: Array) -> Array:
	var out: Array = []
	for k in roads.size():
		for br in roads[k].get("bridges", []):
			out.append([k, br])
	return out


func test_water_crossings_have_bridges() -> void:
	var w := _amnissos()
	var sh: PlanetShape = w["sh"]
	var roads: Array = w["roads"]
	var all := _all_bridges(roads)
	var total := 0.0
	var longest := 0.0
	var piers := 0
	for e in all:
		var br: Dictionary = e[1]
		var cum: PackedFloat32Array = roads[e[0]]["cum"]
		var L := cum[int(br["i1"])] - cum[int(br["i0"])]
		total += L
		longest = maxf(longest, L)
		piers += (br["piers"] as PackedFloat32Array).size()
	print("  (Amnissos: %d roads, %d bridges, %.0f m of them, the longest %.0f m, %d piers; network %d ms)" % [roads.size(), all.size(), total, longest, piers, int(w["ms"])])
	check(all.size() >= 1, "Amnissos's roads cross water on bridges (%d)" % all.size())
	# Every road point over water is on a bridge, its deck above the water.
	var wet := 0
	var bridged := 0
	for k in roads.size():
		var r: Dictionary = roads[k]
		var pts: PackedVector3Array = r["pts"]
		var dr: Vector2i = r["drawn"]
		for i in range(dr.x, dr.y + 1):
			var wl := BR.water_at(sh, pts[i])
			if wl > -INF and sh.height(pts[i]) < wl - 0.5:
				wet += 1
				var on := false
				for br in r.get("bridges", []):
					if i >= int(br["i0"]) and i <= int(br["i1"]):
						on = true
						var h: float = (br["h"] as PackedFloat32Array)[i - int(br["i0"])]
						if h < wl + 1.4:
							check(false, "a deck well over the water (%.1f m over it)" % (h - wl))
				if on:
					bridged += 1
	check_eq(bridged, wet, "every road point over water on a bridge (%d of %d)" % [bridged, wet])
	for e in all:
		var br: Dictionary = e[1]
		var h: PackedFloat32Array = br["h"]
		var g: PackedFloat32Array = br["g"]
		check(absf(h[0] - g[0]) < 0.6 and absf(h[h.size() - 1] - g[g.size() - 1]) < 0.6, "its ends on the banks (%.2f, %.2f m over the ground)" % [h[0] - g[0], h[h.size() - 1] - g[g.size() - 1]])
		var cum: PackedFloat32Array = roads[e[0]]["cum"]
		var worst := 0.0
		for q in range(1, h.size()):
			var run := cum[int(br["i0"]) + q] - cum[int(br["i0"]) + q - 1]
			if run > 0.5:
				worst = maxf(worst, absf(h[q] - h[q - 1]) / run)
		check(worst < 0.16, "gentle approaches (the steepest grade %.2f)" % worst)


func test_the_same_each_time() -> void:
	var w := _amnissos()
	var roads2 := CosmosRoads.network(w["sh"], w["towns"])
	var a := _all_bridges(w["roads"])
	var b := _all_bridges(roads2)
	check_eq(a.size(), b.size(), "the same bridges")
	for i in mini(a.size(), b.size()):
		check_eq(int(a[i][1]["i0"]), int(b[i][1]["i0"]), "in the same places")
		check_eq((a[i][1]["h"] as PackedFloat32Array), (b[i][1]["h"] as PackedFloat32Array), "the same decks")
		check_eq((a[i][1]["piers"] as PackedFloat32Array), (b[i][1]["piers"] as PackedFloat32Array), "the same piers")


func test_deck_floor_walls_and_mesh() -> void:
	var w := _amnissos()
	var sh: PlanetShape = w["sh"]
	var roads: Array = w["roads"]
	var R := sh.radius
	var hsh := BR.index(roads, R)
	var all := _all_bridges(roads)
	if all.is_empty():
		check(false, "a bridge to test")
		return
	# The longest one.
	var pick: Array = all[0]
	for e in all:
		if int(e[1]["i1"]) - int(e[1]["i0"]) > int(pick[1]["i1"]) - int(pick[1]["i0"]):
			pick = e
	var k: int = pick[0]
	var br: Dictionary = pick[1]
	var road: Dictionary = roads[k]
	var pts: PackedVector3Array = road["pts"]
	var mid := (int(br["i0"]) + int(br["i1"])) / 2
	var d := pts[mid]
	var top: float = (br["h"] as PackedFloat32Array)[mid - int(br["i0"])]
	var wl := BR.water_at(sh, d)
	var on := d * (R + top + 0.3)
	var pr := BR.probe(roads, hsh, R, on)
	check(not pr.is_empty(), "found by the hash")
	check(absf(BR.floor_at(pr, top + 0.3) - top) < 0.05, "its floor: the deck (%.2f, the deck %.2f)" % [BR.floor_at(pr, top + 0.3), top])
	# Under it, swimming: no floor there (the water's), and free under an arch or by a pier's side out.
	var low := d * (R + wl - 1.2)
	check_eq(BR.floor_at(BR.probe(roads, hsh, R, low), wl - 1.2), -INF, "under the deck: not its floor")
	# Its parapets: walking at its edge, held in.
	var side := pts[mid].cross(pts[mid + 1] - pts[mid - 1]).normalized()
	var W: float = br["half"]
	var edge := (d * R + side * (W - 0.1)).normalized() * (R + top)
	var pe := BR.probe(roads, hsh, R, edge)
	var mv := BR.push(pe, top, 0.4)
	check(mv.dot(side) < -0.2, "the parapet holds you in (pushed %.2f m)" % mv.dot(side))
	check(BR.solid(pe, top + 0.5, 0.0) == false, "the deck's air not solid")
	var in_wall := (d * R + side * (W + 0.2)).normalized() * (R + top)
	check(BR.solid(BR.probe(roads, hsh, R, in_wall), top + 0.5, 0.0), "the parapet solid (the camera, bolts)")
	check(BR.solid(BR.probe(roads, hsh, R, on), top - 0.4, 0.0), "the deck's slab solid")
	# Off the side: nothing.
	var off := (d * R + side * (W + 8.0)).normalized() * (R + top)
	check(BR.probe(roads, hsh, R, off).is_empty() or BR.floor_at(BR.probe(roads, hsh, R, off), top) == -INF, "off its side: no deck")
	# Its mesh: a piece's arrays, under a budget.
	var t0 := Time.get_ticks_usec()
	var i0 := maxi(int(br["i0"]) - 10, 0)
	var i1 := mini(i0 + CosmosRoads.CHUNK_PTS + 1, pts.size())
	var centre := pts[(i0 + i1) / 2] * (R + maxf(sh.surface(pts[(i0 + i1) / 2]), 0.0))
	var res := BR.piece(sh, road, i0, i1, centre)
	var us := Time.get_ticks_usec() - t0
	check(not res.is_empty(), "a piece's bridge mesh")
	if not res.is_empty():
		var tris := (res[0][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("  (a bridge piece: %d triangles, %d LOD levels, made in %.1f ms)" % [tris, (res[1] as Dictionary).size(), us / 1000.0])
		check(tris > 200 and tris < 30000, "a sensible size (%d triangles)" % tris)


func _cosmos() -> Cosmos:
	Galaxy.current_system = Galaxy.HOME
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


## On Amnissos on foot, its roads and their bridges made: [cosmos, planet, roads] (or [] - checked).
func _on_amnissos() -> Array:
	var c := await _cosmos()
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if str(p.rec.get("name", "")) == "Amnissos":
			pl = p
	if not check(pl != null, "Amnissos is built"):
		c.queue_free()
		return []
	c.warp_to(c.planets.find(pl), 40.0, 0.0, 0.0, c.land_up(c.planets.find(pl)))
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var cr := CosmosRoads.of(c)
	var t0 := Time.get_ticks_msec()
	while (cr.roads_of(pl).is_empty() or not CosmosRoads._decks.has(CosmosRoads._pid(pl))) and Time.get_ticks_msec() - t0 < 40000:
		await tree.process_frame
	var roads := cr.roads_of(pl)
	if not check(not roads.is_empty() and CosmosRoads._decks.has(CosmosRoads._pid(pl)), "its roads and bridges made"):
		c.queue_free()
		return []
	return [c, pl, roads]


## A bridge to walk: the longest under ~450 m (or the shortest): [road index, bridge].
func _longest(roads: Array) -> Array:
	var pick: Array = []
	for e in _all_bridges(roads):
		var n := int(e[1]["i1"]) - int(e[1]["i0"])
		var pn := int(pick[1]["i1"]) - int(pick[1]["i0"]) if not pick.is_empty() else 0
		if pick.is_empty() or (n < 150 and (n > pn or pn >= 150)) or (pn >= 150 and n < pn):
			pick = e
	return pick


func test_walked_across_and_crossed_by_caravans() -> void:
	var got := await _on_amnissos()
	if got.is_empty():
		return
	var c: Cosmos = got[0]
	var pl: CosmosPlanet = got[1]
	var roads: Array = got[2]
	var pick := _longest(roads)
	if not check(not pick.is_empty(), "a bridge on Amnissos"):
		c.queue_free()
		return
	var road: Dictionary = roads[pick[0]]
	var br: Dictionary = pick[1]
	var pts: PackedVector3Array = road["pts"]
	var cum: PackedFloat32Array = road["cum"]
	var R := pl.radius
	var w := c.walker
	var i0 := int(br["i0"])
	var i1 := int(br["i1"])
	var wl := float(br["wl"])
	# From the bank, along the deck to the far bank (the camera kept along the road).
	w.global_position = pl.to_global(pts[i0] * (R + float((br["h"] as PackedFloat32Array)[0]) + 0.05))
	w.velocity = Vector3.ZERO
	w.drive = {"move": Vector2(0, 1)}
	var worst := 0.0
	var swam := false
	var over_water := 0
	var lowest_over_water := INF
	var far := 0.0
	var ii := i0
	for k in int((cum[i1] - cum[i0] + 30.0) / 2.5 * 30.0):
		var lp := pl.to_local(w.global_position)
		var bi := ii
		for q in range(maxi(ii - 3, 0), mini(ii + 8, pts.size())):   # (where along it: the nearest point near the last)
			if pts[q].distance_to(lp.normalized()) < pts[bi].distance_to(lp.normalized()):
				bi = q
		ii = bi
		var s := cum[ii]
		var ahead := CosmosRoads.point(road, s + 6.0) * R - lp
		w.heading = pl.dir_world((ahead - lp.normalized() * ahead.dot(lp.normalized())).normalized())
		w._process(1.0 / 30.0)
		c.walker_bumps(w)
		lp = pl.to_local(w.global_position)
		var pr := CosmosRoads.deck_probe(pl, lp)
		if not pr.is_empty() and s > cum[i0] + 3.0 and s < cum[i1] - 3.0:
			worst = maxf(worst, absf(lp.length() - R - float(pr[3])))
			if pl.shape.height(lp.normalized()) < wl - 0.5:
				over_water += 1
				lowest_over_water = minf(lowest_over_water, lp.length() - R - wl)
		swam = swam or w.swimming
		far = maxf(far, s)
		if s > cum[i1] + 5.0:
			break
	w.drive = {}
	check(far > cum[i1], "walked across, bank to bank (%.0f of %.0f m)" % [far - cum[i0], cum[i1] - cum[i0]])
	check(not swam, "never in the water")
	check(over_water > 10, "over the water (%d steps)" % over_water)
	check(worst < 0.25, "on its deck all the way (at most %.2f m off it)" % worst)
	check(lowest_over_water > 1.4, "well over the water (%.1f m at the lowest)" % lowest_over_water)
	# Its middle: the road's pace there too; the parapet holds you on it.
	var mid := (i0 + i1) / 2
	var top: float = (br["h"] as PackedFloat32Array)[mid - i0]
	w.global_position = pl.to_global(pts[mid] * (R + top + 0.02))
	w.velocity = Vector3.ZERO
	check(CosmosRoads.on_way(pl, pts[mid] * (R + top)), "on the road there (its pace)")
	var side := pts[mid].cross(pts[mid + 1] - pts[mid - 1]).normalized()
	w.heading = pl.dir_world(side)
	w.drive = {"move": Vector2(0, 1)}
	for k in 90:
		w._process(1.0 / 30.0)
		c.walker_bumps(w)
	w.drive = {}
	var lp := pl.to_local(w.global_position)
	var x := (lp - pts[mid] * lp.length()).dot(side)
	check(x < float(br["half"]), "the parapet held you on the deck (%.2f m out, the parapet at %.2f)" % [x, float(br["half"])])
	check(lp.length() - R > top - 0.3, "still on it (%.1f m up, the deck %.1f)" % [lp.length() - R, top])
	# A caravan's way across: on the deck, not in the water.
	var g := {"road": pick[0], "dir": 1}
	var lowest := INF
	var s := cum[i0] + 2.0
	while s < cum[i1] - 2.0:
		var at := CosmosCaravans.where(pl, roads, g, s, 1.0)
		var dk := CosmosRoads.deck_along(road, s)
		lowest = minf(lowest, at.length() - R - dk)
		s += 3.0
	check(lowest > -0.05, "a caravan's way: on its deck (%.2f m)" % lowest)
	# A traveller (a caravan's people) walked across: kept on the deck.
	var tr := CosmosTraveller.new()
	tr.cosmos = c
	tr.traveller(pl, "trader", "minoa", 7)
	c.world.add_child(tr)
	tr.global_position = pl.to_global(pts[mid] * (R + top))
	var worst_t := 0.0
	for k in 120:
		var tl := pl.to_local(tr.global_position)
		var near := CosmosRoads.nearest([road], tl.normalized(), R)
		tr.goal = pl.to_global(CosmosRoads.point(road, float(near[1]) + 8.0) * R)
		tr._process(1.0 / 30.0)
		tl = pl.to_local(tr.global_position)
		var dk := CosmosRoads.deck_along(road, float(CosmosRoads.nearest([road], tl.normalized(), R)[1]))
		if dk > -INF:
			worst_t = maxf(worst_t, absf(tl.length() - R - dk))
	check(worst_t < 0.6, "a traveller walks on the deck (at most %.2f m off it)" % worst_t)
	tr.queue_free()
	# The camera kept out of its stone: from over the deck down through it, stopped at its top.
	var pivot := pl.to_global(pts[mid] * (R + top + 1.6))
	var below := pl.to_global(pts[mid] * (R + top - 3.0))
	var got_cam: Vector3 = c.camera_clear(pivot, below)
	check(pl.to_local(got_cam).length() - R > top - 0.05, "the camera stops at the deck (%.2f m over it)" % (pl.to_local(got_cam).length() - R - top))
	# A bolt into it: stopped.
	check(CosmosRoads.deck_solid(pl, pts[mid] * (R + top - 0.4)), "its slab solid to bolts")
	# No landing on it.
	check(CosmosRoads.bridge_near(pl, pts[mid] * R, 14.0), "the ship won't set down on a bridge")
	check(c._spot_why(pl, pl.dir_world(pts[mid]), pl.dir_world(side)) != "", "a spot on it refused (%s)" % c._spot_why(pl, pl.dir_world(pts[mid]), pl.dir_world(side)))
	c.queue_free()
	await tree.process_frame
