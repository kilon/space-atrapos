extends TestCase
## The worlds turn on their axes (CosmosPlanet's day): each its own day of 16-24
## min, a little tilt; what stands on one is carried round with it (Cosmos._orbit_tick);
## the sun rises and sets; your spot, the parked ship and the animals stay where they
## stood; the save keeps your spot on the ground; the day-length setting changes the
## turn without the ground jumping.

var _old_system := ""
var _old_day := 1.0


func setup() -> void:
	_old_system = Galaxy.current_system
	_old_day = Settings.day_length
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""
	Settings.day_length = 1.0
	CosmosPlanet.reset_spin(1.0)


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""
	Settings.day_length = _old_day
	CosmosPlanet.reset_spin(_old_day)


func _cosmos(sid := "atrapos") -> Cosmos:
	Galaxy.current_system = sid
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


func _ground_index(c: Cosmos) -> int:
	for i in c.planets.size():
		if (c.planets[i] as CosmosPlanet).shape.sea == 1:
			return i
	return 0


func _on_foot(c: Cosmos) -> CosmosWalker:
	var i := _ground_index(c)
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	return c.walker


## `secs` of the galaxy's clock in the orbit steps' own pace (ORBIT_HZ): the worlds
## turned and moved on, what rides them carried; the walker (if `walk`) stepping too.
func _spin_for(c: Cosmos, secs: float, walk: CosmosWalker = null) -> void:
	var dt := 1.0 / Cosmos.ORBIT_HZ + 0.0001   # (a step each: never a hair short of one)
	for k in int(secs / dt):
		Galaxy.time += dt
		c._orbit_tick(dt)
		if walk:
			walk._process(dt)


func test_every_world_has_its_day() -> void:
	var c := await _cosmos()
	for p: CosmosPlanet in c.planets:
		check(p.day_len >= CosmosPlanet.DAY_MIN - 0.01 and p.day_len <= CosmosPlanet.DAY_MAX + 0.01, "%s: a day of 16-24 min (%.1f min)" % [p.name, p.day_len / 60.0])
		if p.get_node_or_null("Rings") == null:
			check(p.tilt <= CosmosPlanet.TILT_MAX + 0.001, "%s: tilted at most 20 degrees (%.1f)" % [p.name, rad_to_deg(p.tilt)])
			# (the longest day where towns stand - at LIVED_LAT, midsummer - at most 12 min)
			var share := acos(clampf(-tan(CosmosPlanet.LIVED_LAT) * tan(p.tilt), -1.0, 1.0)) / PI
			check(p.day_len * share <= CosmosPlanet.HALF_DAY_MAX + 1.0, "%s: its towns' longest day under 12 min (%.1f)" % [p.name, p.day_len * share / 60.0])
		for t in p.towns:
			check(absf((t["dir"] as Vector3).y) <= sin(CosmosPlanet.LIVED_LAT) + 0.001, "%s: its towns off the polar lands" % p.name)
	c.queue_free()
	await tree.process_frame


func test_a_world_turns() -> void:
	var c := await _cosmos()
	var pl: CosmosPlanet = c.planets[_ground_index(c)]
	var t0: float = Galaxy.time
	var b0 := pl.global_basis
	_spin_for(c, 60.0)
	var t1: float = Galaxy.time
	check(pl.global_basis.is_equal_approx(pl.spin_basis(t1)), "its basis is its turn at the galaxy's time")
	var want := TAU * (t1 - t0) * (1.0 / pl.day_len - 1.0 / pl.year_len)
	var got := (pl.global_basis * b0.inverse()).get_rotation_quaternion().get_angle()
	check(absf(got - want) < 0.002, "a minute: turned %.2f degrees (%.2f wanted)" % [rad_to_deg(got), rad_to_deg(want)])
	var axis := pl.dir_world(Vector3.UP)
	check((pl.global_basis * b0.inverse()) * axis == axis or ((pl.global_basis * b0.inverse()) * axis).distance_to(axis) < 0.001, "round its own axis (its local Y)")
	c.queue_free()
	await tree.process_frame


func test_standing_still_on_the_turning_ground() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var pl := w.planet
	check(pl != null, "on foot on a world")
	if pl == null:
		c.queue_free()
		return
	w.velocity = Vector3.ZERO
	w.drive = {}
	for k in 30:
		w._process(1.0 / 30.0)
	var l0 := pl.to_local(w.global_position)
	var f0 := pl.dir_local(w.facing)
	var s0 := pl.to_local(c.ship.global_position)
	var sb0 := pl.global_basis.inverse() * c.ship.global_basis
	# (an animal beside you, carried - its own wandering off for the test)
	var kinds: Array = c.fauna_of(pl)
	var cr: CosmosCreature = null
	if not kinds.is_empty():
		cr = CosmosCreature.new()
		cr.cosmos = c
		cr.setup(kinds[0], pl, 3)
		c.world.add_child(cr)
		var cu := (l0 + pl.dir_local(w.global_basis.x) * 8.0).normalized()
		cr.global_position = pl.to_global(cu * (pl.radius + maxf(pl.shape.height(cu), 0.0)))
		cr.set_process(false)
		c._rides[cr] = c._ride_of(cr)
	var cl0 := pl.to_local(cr.global_position) if cr else Vector3.ZERO
	var lat0 := rad_to_deg(asin(l0.normalized().y))
	var lon0 := rad_to_deg(atan2(l0.x, l0.z))
	var t0: float = Galaxy.time
	var b0 := pl.global_basis
	_spin_for(c, 60.0, w)
	var turned := rad_to_deg((pl.global_basis * b0.inverse()).get_rotation_quaternion().get_angle())
	check(turned > 10.0, "the world turned under the sun (%.1f degrees in a minute)" % turned)
	var l1 := pl.to_local(w.global_position)
	check(l1.distance_to(l0) < 0.3, "you stand on the same spot of its ground (%.2f m off)" % l1.distance_to(l0))
	check(w.on_ground, "on your feet, not falling")
	check(pl.dir_local(w.facing).dot(f0) > 0.995, "facing the same way along the ground")
	var lat1 := rad_to_deg(asin(l1.normalized().y))
	var lon1 := rad_to_deg(atan2(l1.x, l1.z))
	check(absf(lat1 - lat0) < 0.01 and absf(lon1 - lon0) < 0.01, "your latitude and longitude stay put (%.3f, %.3f)" % [lat1 - lat0, lon1 - lon0])
	var s1 := pl.to_local(c.ship.global_position)
	check(s1.distance_to(s0) < 0.05, "your parked ship where you left it (%.3f m)" % s1.distance_to(s0))
	check((pl.global_basis.inverse() * c.ship.global_basis).is_equal_approx(sb0) or ((pl.global_basis.inverse() * c.ship.global_basis).y.dot(sb0.y) > 0.9999), "level on its spot, as it was")
	if cr:
		var cl1 := pl.to_local(cr.global_position)
		check(cl1.distance_to(cl0) < 0.05, "an animal stood still where it stood (%.3f m)" % cl1.distance_to(cl0))
		cr.queue_free()
	c.queue_free()
	await tree.process_frame


func test_the_sun_rises_and_sets() -> void:
	var c := await _cosmos()
	var pl: CosmosPlanet = c.planets[_ground_index(c)]
	var sid: String = c.system_id
	var id := str(pl.rec.get("id", ""))
	var spot := Vector3.UP
	for t in pl.towns:
		if str(t.get("kind", "")) == "city":
			spot = t["dir"]
			break
	var t0: float = Galaxy.time
	var crossings: Array = []
	var prev := 0.0
	var step := 5.0
	var up_t := 0.0
	var n := int(pl.day_len * 2.2 / step)
	for k in n + 1:
		var t := t0 + k * step
		var e := spot.dot(pl.sun_local_at(t, Cosmos.planet_places(sid, t)[id]))
		if e > 0.0:
			up_t += step
		if k > 0 and signf(e) != signf(prev):
			crossings.append(t)
		prev = e
	check(crossings.size() >= 4, "the sun rises and sets over two days (%d crossings)" % crossings.size())
	if crossings.size() >= 3:
		var full := float(crossings[2]) - float(crossings[0])
		check(absf(full - pl.day_len) < pl.day_len * 0.03, "a day and a night: its day length (%.1f min, %.1f wanted)" % [full / 60.0, pl.day_len / 60.0])
		var a := float(crossings[1]) - float(crossings[0])
		var b := float(crossings[2]) - float(crossings[1])
		check(a <= CosmosPlanet.HALF_DAY_MAX + step * 2.0 and b <= CosmosPlanet.HALF_DAY_MAX + step * 2.0, "at its city day and night each at most 12 min (%.1f, %.1f min)" % [a / 60.0, b / 60.0])
	# (a new game: its first city has the morning sun)
	var e0 := spot.dot(pl.sun_local_at(0.0, Cosmos.planet_places(sid, 0.0)[id]))
	var e1 := spot.dot(pl.sun_local_at(30.0, Cosmos.planet_places(sid, 30.0)[id]))
	check(e0 > 0.2 and e1 > e0, "a new game's city: the morning sun (%.2f, rising: %.2f)" % [e0, e1])
	c.queue_free()
	await tree.process_frame


func test_the_save_keeps_your_spot() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var pl := w.planet
	_spin_for(c, 20.0, w)
	c.ship_elsewhere = true   # (on foot, your ship not with you: the save keeps where you stand)
	c.get_save_data()
	var on: Dictionary = CosmosGame.extra.get("on_planet", {})
	check(not on.is_empty(), "the save notes where you stand")
	var l0 := pl.to_local(w.global_position)
	var at: Array = on.get("at", [0, 0, 0])
	check(Vector3(float(at[0]), float(at[1]), float(at[2])).distance_to(l0) < 0.01, "planet-local")
	_spin_for(c, 200.0)   # (time goes by: the world turns)
	await c._set_down_on_world(str(on["planet"]), at)
	var l1 := pl.to_local(w.global_position)
	check(Vector3(l1.x, 0, l1.z).normalized().dot(Vector3(l0.x, 0, l0.z).normalized()) > 0.99999 and l1.distance_to(l0) < 0.5, "loaded: back on the same ground (%.2f m)" % l1.distance_to(l0))
	c.ship_elsewhere = false
	CosmosGame.extra.erase("on_planet")
	c.queue_free()
	await tree.process_frame


func test_the_day_length_setting() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var pl := w.planet
	_spin_for(c, 2.0, w)
	var b0 := pl.global_basis
	var l0 := pl.to_local(w.global_position)
	Settings.day_length = 2.0
	c._orbit_tick(0.0)   # (the rate changed: a step at once - from where it was)
	check(pl.global_basis.is_equal_approx(b0) or (pl.global_basis * b0.inverse()).get_rotation_quaternion().get_angle() < 0.0005, "set otherwise: the world doesn't jump")
	check(pl.to_local(w.global_position).distance_to(l0) < 0.05, "nor does the ground under you")
	var t0: float = Galaxy.time
	_spin_for(c, 60.0, w)
	var want := TAU * (Galaxy.time - t0) * (1.0 / (pl.day_len * 2.0) - 1.0 / pl.year_len)
	var got := (pl.global_basis * b0.inverse()).get_rotation_quaternion().get_angle()
	check(absf(got - want) < 0.002, "twice as long: half the turn (%.2f, %.2f wanted)" % [rad_to_deg(got), rad_to_deg(want)])
	Settings.day_length = 0.0
	_spin_for(c, 1.0, w)
	var b1 := pl.global_basis
	_spin_for(c, 60.0, w)
	check((pl.global_basis * b1.inverse()).get_rotation_quaternion().get_angle() < 0.0001, "no turning: it stays as it is")
	check(pl.to_local(w.global_position).distance_to(l0) < 0.5, "and you on your spot all along (%.2f m)" % pl.to_local(w.global_position).distance_to(l0))
	Settings.day_length = 1.0
	c.queue_free()
	await tree.process_frame
