extends TestCase
## The towns' landing pads (CosmosLandingField): a city's pads, the ships that come
## down on them and lift off on their schedule, their pilots down the ramp into the
## town and back, a ride asked of one (stations, systems, their prices, the fee
## taken) flown end to end - to a station, through a gate - and a save mid-stay.

var _old_system := ""
var LF: GDScript


func setup() -> void:
	_old_system = Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""
	LF = load("res://scripts/world/life/cosmos_landing_field.gd")


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""
	LF.test_busy = -1.0
	CosmosGame.extra.erase("pads_taken")


func _cosmos() -> Cosmos:
	Galaxy.current_system = "atrapos"
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## The first world with a city: [planet index, its site].
func _city(c: Cosmos) -> Array:
	for k in c.planets.size():
		for s in c.planets[k].towns:
			if str(s["kind"]) == "city":
				return [k, s]
	return []


## On foot by the city's landing field, its town built: the town.
func _at_field(c: Cosmos, k: int, site: Dictionary) -> CosmosTown:
	var pl: CosmosPlanet = c.planets[k]
	var xf := CosmosTown.frame(site, pl.radius)
	c.warp_to(k, 30.0, 0.0, 0.0, pl.dir_world((xf * Vector3(123, 0, 0)).normalized()))
	c._towns_tick()
	var t: CosmosTown = null
	for x in c._towns[pl]:
		if x != null and x.site == site:
			t = x
	for i in 600:
		if t.poll():
			break
		await tree.process_frame
	c.land()
	for i in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	for i in 6:
		c._towns_tick()
	return t


## The galaxy's clock set (the worlds moved to it).
func _clock(c: Cosmos, time: float) -> void:
	Galaxy.time = time
	c._orbit_tick(1.0 / 60.0)


func _hull_ready(sl: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	while not CosmosHull.ready(str(sl["hull"]), str(sl["empire"])) and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame


func test_cities_have_pads() -> void:
	var cities := 0
	var c := await _cosmos()
	for pl: CosmosPlanet in c.planets:
		for s in pl.towns:
			var pads: Array = LF.pads_of(s)
			var lay := CosmosTown.layout(str(s["kind"]))
			var port: Vector3 = lay["port"]
			if str(s["kind"]) == "city":
				cities += 1
				check(pads.size() >= 3 and pads.size() <= 6, "%s: a city's 3-6 pads (%d)" % [s["name"], pads.size()])
				check(pads.filter(func(p): return p["big"]).size() >= 2, "%s: big pads for the shuttles" % s["name"])
			else:
				check(pads.size() <= 1, "%s: a village's 0-1 pads (%d)" % [s["name"], pads.size()])
			for i in pads.size():
				var a: Dictionary = pads[i]
				var ra := Rect2(Vector2(a["at"].x, a["at"].z) - a["size"] * 0.5, a["size"])
				var far := Vector2(absf(ra.position.x) + ra.size.x, maxf(absf(ra.position.y), absf(ra.end.y))).length()
				check(far < float(s["r"]), "%s pad %d on its levelled ground (%.0f of %.0f m)" % [s["name"], a["id"], far, s["r"]])
				check(ra.position.x > float(lay["half"]), "%s pad %d out of the town's square" % [s["name"], a["id"]])
				var field := Rect2(Vector2(port.x - 34.0, -35.6 - 0.5), Vector2(70.0, 72.2))
				check(not ra.intersects(field), "%s pad %d clear of the field's stone, its lamps and its middle (a ride's landing)" % [s["name"], a["id"]])
				if a["big"]:
					var sh := CosmosHull.size_of("shuttle", str(s["empire"])) * 22.0
					check(ra.size.x >= sh + 3.0, "a shuttle's length on it (%.0f of %.0f m)" % [ra.size.x, sh])
				for j in range(i + 1, pads.size()):
					var b: Dictionary = pads[j]
					var rb := Rect2(Vector2(b["at"].x, b["at"].z) - b["size"] * 0.5, b["size"])
					check(not ra.grow(0.5).intersects(rb), "pads %d and %d apart" % [a["id"], b["id"]])
	check(cities >= 1, "a city in the home system")
	var e := _city(c)
	var t: CosmosTown = await _at_field(c, e[0], e[1])
	var lf = LF.of(c)
	for i in 200:
		lf._meshes()
		if t.has_node("LandingField"):
			break
		await tree.process_frame
	check(t.has_node("LandingField"), "its pads' meshes put in the town")
	var node := t.get_node_or_null("LandingField")
	if node:
		check(node.get_node("Pads").mesh.get_surface_count() == 1 and node.get_node("Lamps").mesh.get_surface_count() == 1, "one mesh of pads, one of lamps")
	var p: Dictionary = LF.pads_of(t.site)[0]
	var on: Vector3 = p["at"] + Vector3(2.0, 0.0, 1.0)
	check(absf(t.floor_top(Vector3(on.x, 0.05, on.z)) - LF.DECK) < 0.01, "a pad's deck walked on (%.2f m)" % t.floor_top(Vector3(on.x, 0.05, on.z)))
	var tw = LF.tower_of(t.site)
	check(tw != null, "the field's control tower")
	if tw != null:
		var pushed := t.push((tw as Vector3) + Vector3(1.9, 0.1, 0.0), 0.4)
		check(pushed.length() > 0.2, "the tower solid (pushed %.2f m)" % pushed.length())
	TownLamps.test_night = 1.0
	t.set_lit(1.0)
	lf._meshes()
	if node:
		check(float(node.get_meta("lit", 0.0)) > 0.99, "its lamps lit by night")
	TownLamps.test_night = -1.0
	c.queue_free()
	await _frames(2)


## A ship comes down on its pad (from the sky, slowing, onto it), its pilot walks
## down the ramp into the town and back up it when its time's up; it lifts off and
## is gone - the pad free again. None comes down on a pad your ship is on.
func test_ship_lands_pilot_ashore_and_back_takes_off() -> void:
	var c := await _cosmos()
	LF.test_busy = 1.0
	var e := _city(c)
	var pl: CosmosPlanet = c.planets[e[0]]
	var site: Dictionary = e[1]
	var p: Dictionary = LF.pads_of(site)[0]
	var key: String = LF.key_of(pl, site, p)
	var sl: Dictionary = LF.next_busy(key, p, Galaxy.time + 5.0, str(site["empire"]))
	check(not sl.is_empty(), "its next round")
	_clock(c, float(sl["arrive"]) - 1.0)
	var t: CosmosTown = await _at_field(c, e[0], site)
	await _hull_ready(sl)
	var lf = LF.of(c)
	Galaxy.time = float(sl["arrive"]) + 0.5
	lf.tick()
	check(lf.live.has(key), "a ship on its way to the pad")
	if not lf.live.has(key):
		c.queue_free()
		return
	var r: Dictionary = lf.live[key]
	var s: CosmosNpcShip = r["ship"]
	var deck: Transform3D = t.global_transform * LF.pad_frame(p)
	var rest: Vector3 = deck.origin + deck.basis.y * s.rest_height()
	check(s.global_position.distance_to(rest) > 800.0, "coming in from the sky (%.0f m off)" % s.global_position.distance_to(rest))
	check(c.npc_ships.has(s), "one of the system's ships")
	var dt := 1.0 / 30.0
	var lowest := INF
	var steps := 0
	while r["state"] == "in" and steps < 2000:
		Galaxy.time += dt
		s._process(dt)
		steps += 1
		lowest = minf(lowest, (s.global_position - rest).dot(deck.basis.y))
	check_eq(r["state"], "down", "down on the pad")
	check(s.global_position.distance_to(rest) < 0.05 and s.global_basis.y.dot(deck.basis.y) > 0.999, "on its deck, level (%.2f m)" % s.global_position.distance_to(rest))
	check(lowest > -0.05, "never through it (%.2f m)" % lowest)
	check(s._gear_k > 0.99, "on its legs")
	lf.tick()
	check_eq(c.npc_ships.filter(func(y): return is_instance_valid(y) and str(y.get_meta("field_key", "")) == key).size(), 1, "no second ship on it")
	# Its pilot: down the ramp into the town.
	var x: CosmosNpc = null
	var on_ramp := false
	var max_step := 0.0
	var last := Vector3.INF
	var ashore_at := -1
	for k in 4000:
		Galaxy.time += dt
		s._process(dt)
		if k % 8 == 0:
			lf.tick()
		x = r["pilot"] if is_instance_valid(r["pilot"]) else null
		if x == null:
			continue
		x._process(dt)
		var l := s.to_local(x.global_position)
		if x._off == 1 and l.y < -0.3 and l.y > -s.rest_height() + 0.2:
			on_ramp = true
		if last != Vector3.INF:
			max_step = maxf(max_step, x.global_position.distance_to(last))
		last = x.global_position
		if x._off == 2 and ashore_at < 0:
			ashore_at = k
		if ashore_at > 0 and k > ashore_at + 200 and t.to_local(x.global_position).distance_to(x.stay_at) < 1.0:
			break
	check(x != null, "its pilot out")
	if x == null:
		c.queue_free()
		return
	check(on_ramp, "down its ramp")
	check(max_step < CosmosNpc.CREW_RUN * 0.15 + 0.1, "walking, never a jump (%.2f m a step at most)" % max_step)
	check(ashore_at > 0, "off it, into the town")
	check(x in c.citizens and x.role == "captain", "one of the town's people a while")
	var far_from := s.global_position.distance_to(x.global_position)
	check(far_from > 15.0, "away from his ship into the town (%.0f m)" % far_from)
	check(str(x.get_meta("who", "")) == str(sl["pilot"]) and x.label.begins_with(str(sl["pilot"])), "a named pilot (%s)" % x.label)
	var pr := c.sandbox.prompt_for(x)
	check(str(pr[0]).begins_with("Talk to " + str(sl["pilot"])), "talked to by his name (%s)" % str(pr[0]))
	# His time up: back to it, up its ramp, aboard; it lifts off and is gone.
	Galaxy.time = float(sl["leave"]) + 0.1
	lf.tick()
	check_eq(r["state"], "call", "its time up: its pilot called back")
	var up_ramp := false
	for k in 9000:
		Galaxy.time += dt
		s._process(dt)
		if is_instance_valid(x):
			x._process(dt)
			if x._off == 4:
				up_ramp = true
		if r["state"] == "up":
			break
	check(up_ramp, "back up its ramp (off %d, %.0f m from its foot, after %.0f s)" % [x._off if is_instance_valid(x) else -1, t.to_local(x.global_position).distance_to(x._ramp_foot()) if is_instance_valid(x) else -1.0, float(r["t"])])
	check_eq(r["state"], "up", "lifting off with him aboard")
	check(not is_instance_valid(x) or x.is_queued_for_deletion(), "him gone in with it")
	var climbed := 0.0
	for k in 1200:
		Galaxy.time += dt
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			break
		s._process(dt)
		climbed = maxf(climbed, (s.global_position - rest).dot(deck.basis.y))
	check(climbed > 800.0, "up and away (%.0f m)" % climbed)
	check(not lf.live.has(key) and (not is_instance_valid(s) or s.is_queued_for_deletion()), "gone: the pad free")
	check(not c.npc_ships.has(s), "out of the system's ships")
	# Your ship on a pad: none comes down on it.
	var sl2: Dictionary = LF.next_busy(key, p, Galaxy.time + 1.0, str(site["empire"]))
	c.ship.global_position = t.to_global(p["at"] + Vector3(0, 3.0, 0))
	c.ship.visible = true
	Galaxy.time = float(sl2["arrive"]) + 0.5
	lf.tick()
	check(not lf.live.has(key), "none coming down on your ship")
	check_eq(int(CosmosGame.extra.get("pads_taken", {}).get(key, -1)), int(sl2["c"]), "that round gone elsewhere")
	c.queue_free()
	await _frames(2)


## A ship down, its pilot ashore: [cosmos, town, record, pilot, slot] (or [] with a failed check).
func _pilot_ashore(c: Cosmos, mid := 30.0) -> Array:
	LF.test_busy = 1.0
	var e := _city(c)
	var pl: CosmosPlanet = c.planets[e[0]]
	var site: Dictionary = e[1]
	var pads: Array = LF.pads_of(site)
	var p: Dictionary = pads[0]
	var key: String = LF.key_of(pl, site, p)
	var sl: Dictionary = {}
	var s0 := Galaxy.time
	for k in 6:   # (a shuttle's round: its pilot takes passengers)
		sl = LF.next_busy(key, p, s0, str(site["empire"]))
		if sl["kind"] != "courier":
			break
		s0 = float(sl["gone"]) + 1.0
	_clock(c, float(sl["land"]) + mid)
	var t: CosmosTown = await _at_field(c, e[0], site)
	await _hull_ready(sl)
	var lf = LF.of(c)
	Galaxy.time = float(sl["land"]) + mid
	lf.tick()
	check(lf.live.has(key), "a ship down on the pad mid-stay")
	if not lf.live.has(key):
		return []
	var r: Dictionary = lf.live[key]
	for k in 20:
		lf.tick()
		if is_instance_valid(r["pilot"]):
			break
	var x: CosmosNpc = r["pilot"] if is_instance_valid(r["pilot"]) else null
	check(x != null and x._off == 2, "its pilot ashore")
	if x == null:
		return []
	return [t, r, x, sl, key]


## Asked for a ride: the system's stations and the systems through its gates, each its
## price (the jumps dearer), the fee taken; flown to a station end to end.
func test_ride_from_a_pad_to_a_station() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var a := await _pilot_ashore(c)
	if a.is_empty():
		c.queue_free()
		return
	var t: CosmosTown = a[0]
	var r: Dictionary = a[1]
	var x: CosmosNpc = a[2]
	var s: CosmosNpcShip = r["ship"]
	var offers: Array = c.sandbox.ride_offers(t)
	var st_n := offers.filter(func(o): return o[2]["kind"] == "station").size()
	var sys := offers.filter(func(o): return o[2]["kind"] == "system")
	check_eq(st_n, mini(c.stations.size(), 6), "every station of the system offered")
	check(sys.size() >= 1, "and systems through the gates (%d)" % sys.size())
	var most := 0
	for o in offers:
		if o[2]["kind"] != "system":
			most = maxi(most, int(o[1]))
	for o in sys:
		check(int(o[1]) > most, "a jump dearer than any ride in the system (%s: %d dr)" % [o[0], o[1]])
		check(Galaxy.systems.has(str(o[2]["sys"])) and c._gate_to(str(o[2]["via"])) != null, "through one of this system's gates")
	CosmosGame.data.add_credits(2000)
	var cr0: int = CosmosGame.data.credits
	var o: Array = offers.filter(func(o): return o[2]["kind"] == "station")[0]
	check(c.sandbox.hire_captain(x, o[2], int(o[1])), "hired")
	c._dialogue.hide()
	c._talk_end()
	check_eq(CosmosGame.data.credits, cr0 - int(o[1]), "the fee taken (%d dr)" % int(o[1]))
	check(s.traffic == null and s.hire_state() == "wait" and s.hire.get("pilot") == x, "his ship a hired ride, waiting on its pad")
	var inn: CosmosNpcInterior = s.make_interior()
	var t0 := Time.get_ticks_msec()
	while not inn.built and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	check(inn.ok, "its insides made")
	if not inn.ok:
		c.queue_free()
		return
	var w := c.walker
	w.global_position = inn.to_global(Vector3(0, inn.sill, inn.z_aft - 3.0))
	w.velocity = Vector3.ZERO
	w.set_deck(inn)
	var dt := 1.0 / 30.0
	var walked_back := false
	for k in 12000:
		s._process(dt)
		x._process(dt)
		if x._off == 3:
			walked_back = true
		if s.hire_state() == "climb":
			break
	check(walked_back, "he walked back through the town to it")
	check_eq(s.hire_state(), "climb", "off once you're aboard and he's in his seat")
	check(x.seated() and x.get_parent() == inn, "in its pilot's seat (off %d, crew %d, aboard %.1f s, %.1f m from the ramp's foot)" % [x._off, x._crew, float(s.hire.get("aboard_t", 0.0)), x.global_position.distance_to(s.to_global(inn.foot))])
	var lf = LF.of(c)
	for k in 3000:
		s._process(dt)
		if s.hire.is_empty():
			break
	lf.tick()
	check(s.hire.is_empty() and s.dest is CosmosStation, "across the system: in to the station (%s)" % str(s.dest))
	check(s.dest == c._station_by_id(str(o[2]["id"])), "the one you paid for")
	check(c.riding() == s, "you still aboard")
	check(not lf.live.has(a[4]), "its pad free again")
	check_eq(int(CosmosGame.extra.get("pads_taken", {}).get(a[4], -1)), int(a[3]["c"]), "no other ship on it this round")
	c.queue_free()
	await _frames(2)


## A ride through a gate: flown to it, through it - the next system, on foot at its station; your ship left where it was.
func test_ride_from_a_pad_to_another_system() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var a := await _pilot_ashore(c)
	if a.is_empty():
		c.queue_free()
		return
	var t: CosmosTown = a[0]
	var r: Dictionary = a[1]
	var x: CosmosNpc = a[2]
	var s: CosmosNpcShip = r["ship"]
	var sys: Array = c.sandbox.ride_offers(t).filter(func(o): return o[2]["kind"] == "system")
	check(not sys.is_empty(), "a system to fly to")
	if sys.is_empty():
		c.queue_free()
		return
	CosmosGame.data.add_credits(2000)
	var o: Array = sys[0]
	check(c.sandbox.hire_captain(x, o[2], int(o[1])), "hired for %s" % o[0])
	c._dialogue.hide()
	c._talk_end()
	var inn: CosmosNpcInterior = s.make_interior()
	var t0 := Time.get_ticks_msec()
	while not inn.built and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	var w := c.walker
	w.global_position = inn.to_global(Vector3(0, inn.sill, inn.z_aft - 3.0))
	w.velocity = Vector3.ZERO
	w.set_deck(inn)
	var dt := 1.0 / 30.0
	var gate: Node3D = s.hire["to"]["gate"]
	var nearest := INF
	for k in 20000:
		s._process(dt)
		x._process(dt)
		if is_instance_valid(gate):
			nearest = minf(nearest, s.global_position.distance_to(gate.global_position))
		if c.jumped_to != "":
			break
	check_eq(c.jumped_to, str(o[2]["sys"]), "through the gate to %s" % o[0])
	check(nearest < 300.0, "flown to the gate (%.0f m)" % nearest)
	check(CosmosGame.extra.has("foot_at"), "to be set down on foot at its station")
	check(CosmosGame.extra.has("ship_at") and str(CosmosGame.extra["ship_at"]["system"]) == "atrapos", "your ship left behind here")
	CosmosGame.extra.erase("foot_at")
	CosmosGame.extra.erase("ship_at")
	c.queue_free()
	await _frames(2)


## Saved with a ship on its pad, its pilot ashore: loaded, the same ship there, the same pilot in the town.
func test_save_round_trips_mid_stay() -> void:
	var c := await _cosmos()
	var a := await _pilot_ashore(c, 40.0)
	if a.is_empty():
		c.queue_free()
		return
	var key: String = a[4]
	var who := str(a[3]["pilot"])
	var hull := str(a[1]["ship"].hull_kind)
	var snap := CosmosGame.snapshot(c)
	c.queue_free()
	await _frames(2)
	CosmosGame.begin_state(snap)
	var c2 := await _cosmos()
	var e := _city(c2)
	_clock(c2, float(snap["galaxy"]["time"]))
	var t: CosmosTown = await _at_field(c2, e[0], e[1])
	var lf = LF.of(c2)
	Galaxy.time = float(snap["galaxy"]["time"])
	var x: CosmosNpc = null
	for k in 20:
		lf.tick()
		if lf.live.has(key) and is_instance_valid(lf.live[key]["pilot"]):
			x = lf.live[key]["pilot"]
			break
	check(lf.live.has(key), "the ship on its pad again")
	if lf.live.has(key):
		check_eq(lf.live[key]["state"], "down", "down on it")
		check_eq(str(lf.live[key]["ship"].hull_kind), hull, "the same ship")
	check(x != null and str(x.get_meta("who", "")) == who, "its pilot (%s)" % who)
	if x:
		check(x._off == 2 and t.to_local(x.global_position).distance_to(x.stay_at) < 0.5, "ashore, where he spends his time")
	c2.queue_free()
	await _frames(2)
