extends TestCase
## The 3D game, stage 1 (Cosmos): a star system built in 3D from the galaxy's
## data, planets of procedural ground refined as you come closer (the same
## ground from orbit to the surface), the ship's flight, the cruise drive,
## collisions, the gates.

var _old_system := ""


func setup() -> void:
	_old_system = Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""


func _cosmos(sid := "atrapos") -> Cosmos:
	Galaxy.current_system = sid
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func test_system_built_from_the_galaxy() -> void:
	var c := await _cosmos()
	check(c.build_settled(), "the system builds and its planets' first patches come in")
	var sys: Dictionary = Galaxy.system("atrapos")
	check_eq(c.planets.size(), Cosmos.planet_records("atrapos").size(), "every planet and moon of the home system")
	check_eq(c.stations.size(), sys["stations"].size(), "every station")
	check_eq(c.gates.size(), sys["gates"].size(), "a gate for each jump lane")
	check(c.star != null and c.star.radius > 1000.0, "the star")
	var gas := 0
	for p: CosmosPlanet in c.planets:
		if p.shape.kind == "gas":
			gas += 1
		else:
			check(p.settled(), "%s: its six faces' first patches built" % p.name)
	check(gas >= 1, "the home system's gas giant is a gas giant (no ground)")
	check_lt(c.ship.global_position.length(), 1.0, "floating origin: the ship starts at the world's middle")
	check(c.clearance(c.ship.global_position) > 1500.0, "the ship starts clear of everything (%.0f m)" % c.clearance(c.ship.global_position))
	c.queue_free()
	await _frames(2)


func test_planet_ground_is_one_height_field() -> void:
	var rec := {"id": "t", "type": "ocean", "template": "ocean", "variant": 3, "size": 600.0, "seed": 1234}
	var a := PlanetShape.of(rec)
	var b := PlanetShape.of(rec)
	var d := Vector3(0.3, 0.8, -0.5).normalized()
	check_eq(a.height(d), b.height(d), "the same planet, the same ground (deterministic)")
	check(absf(a.radius - 2400.0) < 0.1, "a 2D size of 600 is a 2.4 km radius")
	var lo := INF
	var hi := -INF
	var wet := 0
	for i in 400:
		var v := Vector3(sin(i * 1.7), cos(i * 2.3), sin(i * 0.9 + 1.0)).normalized()
		var h := a.height(v)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if h < 0.0:
			wet += 1
	check(hi > a.amp * 0.3 and lo < -a.amp * 0.1, "hills and sea floors (%.0f .. %.0f m)" % [lo, hi])
	check(hi <= a.top(), "nothing above top() (%.0f <= %.0f)" % [hi, a.top()])
	check(wet > 80 and wet < 340, "an ocean world is part sea, part land (%d of 400 under the sea)" % wet)
	check_eq(a.surface(d), maxf(a.height(d), 0.0), "the surface is the sea where the ground is under it")
	var moon := PlanetShape.of({"id": "m", "type": "moon", "template": "barren", "variant": 2, "size": 200.0, "seed": 9})
	check_eq(moon.sea, 0, "a moon has no sea")
	var gas := PlanetShape.of({"id": "g", "type": "gas_giant", "template": "storm_giant", "variant": 1, "size": 1200.0, "seed": 5})
	check(gas.kind == "gas" and gas.height(d) == 0.0, "a gas giant has no ground")


func test_ground_gets_finer_closer() -> void:
	var c := await _cosmos()
	var idx := -1
	for i in c.planets.size():
		if (c.planets[i] as CosmosPlanet).shape.kind != "gas":
			idx = i
			break
	var pl: CosmosPlanet = c.planets[idx]
	c.warp_to(idx, 60000.0)
	for i in 30:
		await tree.process_frame
	var far := pl.deepest()
	c.warp_to(idx, 30.0)
	var t0 := Time.get_ticks_msec()
	while pl.deepest() < pl.max_level - 1 and Time.get_ticks_msec() - t0 < 30000:
		c.ship.velocity = Vector3.ZERO
		await tree.process_frame
	var near := pl.deepest()
	check(far <= 1, "from far away, a handful of coarse patches (level %d)" % far)
	check(near >= pl.max_level - 1, "on the ground, the finest patches (level %d of %d)" % [near, pl.max_level])
	var shown := pl.shown_patches()
	check(shown > 10 and shown < 400, "a sensible number of patches drawn (%d)" % shown)
	# Patch sizes: the finest a few tens of metres.
	check_lt(pl.radius * 2.0 / pow(2.0, pl.max_level), CosmosPlanet.MIN_PATCH_M * 1.01, "the finest patch is at most MIN_PATCH_M across")
	# Back up: the fine patches go.
	c.warp_to(idx, 60000.0)
	for i in 40:
		await tree.process_frame
	check(pl.deepest() <= 1, "flown away again, the fine patches merge back (level %d)" % pl.deepest())
	c.queue_free()
	await _frames(2)


func test_flight_cruise_and_ground() -> void:
	var c := await _cosmos()
	var s := c.ship
	s.drive = {"throttle": 1.0}
	var p0 := s.global_position + Vector3.ZERO
	var fwd := -s.global_basis.z
	for i in 60:
		s._process(1.0 / 30.0)
	check(s.speed() > 60.0 and s.speed() <= CosmosShip.MAX_SPEED + 0.1, "full throttle: up to its top speed (%.0f m/s)" % s.speed())
	check(s.velocity.normalized().dot(fwd) > 0.99, "flying where the nose points")
	s.drive = {"throttle": 1.0, "stick": Vector2(0.5, 0.0)}
	var b0 := s.global_basis
	for i in 20:
		s._process(1.0 / 30.0)
	check((-s.global_basis.z).dot(-b0.z) < 0.995, "the stick turns it")
	# Cruise: far from everything it's fast; close to a planet it slows and drops out.
	var idx := 0
	c.warp_to(idx, 50000.0)
	var pl: CosmosPlanet = c.planets[idx]
	s.look_at(pl.global_position, Vector3.UP)
	s.drive = {"throttle": 1.0, "stick": Vector2.ZERO}
	c.target = null
	s.toggle_cruise()
	var top := 0.0
	var dropped := false
	for i in 1500:
		s._process(1.0 / 30.0)
		c._shift_origin()
		top = maxf(top, s.speed())
		if s.cruise == 0 and i > 60:
			dropped = true
			break
	check(top > 5000.0, "cruising between planets: kilometres a second (%.0f m/s)" % top)
	check(dropped, "the cruise drive drops out near the planet")
	var alt := s.global_position.distance_to(pl.global_position) - pl.radius - pl.ground_at(s.global_position - pl.global_position)
	check(alt > 600.0 and alt < CosmosShip.HYPER_ARRIVE * 2.0, "out of cruise above the ground, not in it (%.0f m)" % alt)
	# Dive into the ground: it can't go under.
	c.warp_to(idx, 50.0)
	s.look_at(pl.global_position, Vector3.FORWARD)
	s.drive = {"throttle": 1.0, "boost": true}
	var lowest := INF
	for i in 120:
		s._process(1.0 / 30.0)
		c._shift_origin()
		var a := s.global_position.distance_to(pl.global_position) - pl.radius - pl.ground_at(s.global_position - pl.global_position)
		lowest = minf(lowest, a)
	check(lowest > -0.5, "the ground holds the ship up (lowest %.1f m)" % lowest)
	c.queue_free()
	await _frames(2)


func test_floating_origin() -> void:
	var c := await _cosmos()
	var s := c.ship
	var star0 := c.star.global_position - s.global_position
	s.global_position += Vector3(Cosmos.SHIFT_AT * 3.0, 0, 0)
	var star1 := c.star.global_position - s.global_position
	c._shift_origin()
	check_lt(s.global_position.length(), 1.0, "strayed far: the world moves back so the ship's at the middle again")
	check_lt((c.star.global_position - s.global_position).distance_to(star1), 0.5, "everything keeps its place relative to the ship")
	check(star0.distance_to(star1) > 1000.0, "(it had moved)")
	c.queue_free()
	await _frames(2)


func test_gate_jumps() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var g: CosmosGate = c.gates[0]
	# Beside the ring: crossing its plane outside it is no jump.
	c.ship.global_position = g.global_position + g.global_basis.z * 100.0 + g.global_basis.x * (CosmosGate.RADIUS + 200.0)
	c._check_gates()
	c.ship.global_position -= g.global_basis.z * 200.0
	c._check_gates()
	check_eq(c.jumped_to, "", "past the ring's edge: no jump")
	# Through the ring.
	c.ship.global_position = g.global_position + g.global_basis.z * 100.0
	c._check_gates()
	c.ship.global_position = g.global_position - g.global_basis.z * 100.0
	c._check_gates()
	check_eq(c.jumped_to, g.to, "through the ring: a jump to the system it leads to")
	check(Galaxy.systems.has(g.to), "a system of the galaxy")
	c.queue_free()
	await _frames(2)


func test_other_systems_build() -> void:
	var sid := "klotho"
	var c := await _cosmos(sid)
	check(c.build_settled(), "a generated system builds too")
	check_eq(c.planets.size(), Galaxy.system(sid)["planets"].size(), "all its planets and moons")
	var moons := 0
	for p: CosmosPlanet in c.planets:
		if str(p.rec.get("moon_of", "")) != "":
			moons += 1
			var parent: CosmosPlanet = null
			for q: CosmosPlanet in c.planets:
				if q.rec["id"] == p.rec["moon_of"]:
					parent = q
			check(parent != null and p.global_position.distance_to(parent.global_position) > parent.radius + p.radius, "%s orbits outside its planet" % p.name)
	for s: CosmosStation in c.stations:
		for p: CosmosPlanet in c.planets:
			check(s.global_position.distance_to(p.global_position) > p.radius + s.reach, "%s isn't inside %s" % [s.name, p.name])
	c.queue_free()
	await _frames(2)


func _ground_index(c: Cosmos) -> int:
	for i in c.planets.size():
		if (c.planets[i] as CosmosPlanet).shape.sea == 1:
			return i
	return 0


func test_landing_and_walking() -> void:
	var c := await _cosmos()
	var i := _ground_index(c)
	var pl: CosmosPlanet = c.planets[i]
	# Over the sea: no landing.
	var wet := Vector3.ZERO
	for k in 400:
		var u := Vector3(sin(k * 1.3), cos(k * 0.7), sin(k * 2.1 + 0.4)).normalized()
		if pl.shape.height(u) < -5.0:
			wet = u
			break
	c.warp_to(i, 40.0, 0.0, 0.0, wet)
	check(c.landing_check().contains("water"), "no landing on the sea (%s)" % c.landing_check())
	c.warp_to(i, 900.0, 0.0, 0.0, c.land_up(i))
	check(c.landing_check().contains("high"), "too high to land from 900 m")
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	check_eq(c.landing_check(), "", "low and slow over dry, gentle ground: it can land")
	check(c.land(), "L lands")
	for k in 200:
		c.ship._process(1.0 / 30.0)
	check_eq(c.ship.state, "landed", "settled on the ground")
	var local := c.ship.global_position - pl.global_position
	var over := local.length() - pl.radius - pl.shape.height(local.normalized())
	check(absf(over - CosmosShip.GEAR) < 0.5, "standing on its gear, on the ground (%.2f m)" % over)
	check(c.ship.global_basis.y.dot(local.normalized()) > 0.99, "level with the planet's up")
	# Up from the seat, in the cockpit; then down the ramp.
	c.get_out()
	var w := c.walker
	check(w != null and c.cam.walker == w and w.deck == c.ship.interior, "E: up from the seat, aboard - the camera on the walker")
	for k in 150:
		c.ship.interior._process(1.0 / 30.0)
	check(c.ship.interior.ramp_down, "landed: the tail's door up, the ramp out")
	# Walk aft and down the ramp - no jumps on the way.
	w.global_position = c.ship.interior.to_global(Vector3(0, CosmosShipInterior.FLOOR, 18.0))
	w.set_deck(c.ship.interior)
	w.heading = c.ship.global_basis.z
	w.drive = {"move": Vector2(0, 1)}
	var last := w.global_position
	var jump := 0.0
	for k in 120:
		w._process(1.0 / 30.0)
		c._ramp_crossing()
		jump = maxf(jump, w.global_position.distance_to(last))
		last = w.global_position
	w.drive = {}
	check(w.deck == null and w.planet == pl, "down the ramp: on the planet's ground")
	check(jump < 0.5, "walked out, no jump on the way (largest step %.2f m)" % jump)
	for k in 30:
		w._process(1.0 / 30.0)
	check(w.on_ground and absf(w.height_above_ground()) < 0.1, "standing on the ground (%.2f m)" % w.height_above_ground())
	var p0 := w.global_position
	w.drive = {"move": Vector2(0, 1), "run": true}
	for k in 90:
		w._process(1.0 / 30.0)
	var moved := w.global_position.distance_to(p0)
	check(moved > 12.0, "it runs (%.1f m in 3 s)" % moved)
	check(absf(w.height_above_ground()) < 0.6, "following the ground (%.2f m over it)" % w.height_above_ground())
	check(w.global_basis.y.dot(w.up()) > 0.99, "standing along the planet's up")
	w.drive = {"jump": true}
	w._process(1.0 / 30.0)
	w.drive = {}
	var top := 0.0
	for k in 30:
		w._process(1.0 / 30.0)
		top = maxf(top, w.height_above_ground())
	check(top > 0.8, "Space jumps (%.2f m)" % top)
	# Far from the ship: no boarding; near it: aboard.
	check(not c.board(), "not at the pilot's seat: no boarding")
	# Back up the ramp, forward to the seat.
	w.global_position = c.ship.interior.to_global(c.ship.interior.ramp_foot() + Vector3(0, 0.05, 0.3))
	w.heading = -c.ship.global_basis.z
	w.drive = {"move": Vector2(0, 1)}
	for k in 30:
		w._process(1.0 / 30.0)
		c._ramp_crossing()
	check(w.deck == c.ship.interior, "up the ramp: aboard")
	w.drive = {}
	check(c.embark() and c.walker == null, "at the seat: at the controls again")
	c.ship.take_off()
	for k in 60:
		c.ship._process(1.0 / 30.0)
	check_eq(c.ship.state, "fly", "taking off: flying again")
	local = c.ship.global_position - pl.global_position
	check(local.length() - pl.radius - pl.shape.height(local.normalized()) > 15.0, "lifted clear of the ground")
	c.queue_free()
	await _frames(2)


func test_boulders_on_the_ground() -> void:
	var c := await _cosmos()
	var i := _ground_index(c)
	var pl: CosmosPlanet = c.planets[i]
	c.warp_to(i, 6.0, 0.0, 0.0, c.land_up(i))
	var t0 := Time.get_ticks_msec()
	while pl.deepest() < pl.max_level and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
	var local := c.ship.global_position - pl.global_position
	var rocks := pl.rocks_near(local, 400.0)
	check(rocks.size() > 3, "boulders scattered round (%d within 400 m)" % rocks.size())
	var dry := true
	for r in rocks:
		if pl.shape.height((r[0] as Vector3).normalized()) < 0.0:
			dry = false
	check(dry, "none in the sea")
	# The same patch, the same boulders (seeded).
	var again := pl.rocks_near(local, 400.0)
	check_eq(again.size(), rocks.size(), "the same boulders on a second look")
	c.queue_free()
	await _frames(2)


func test_hyperion_drive_reaches_any_planet_in_a_minute() -> void:
	var c := await _cosmos()
	var s := c.ship
	# The farthest planet from where the ship starts.
	var far: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if far == null or p.global_position.distance_to(s.global_position) > far.global_position.distance_to(s.global_position):
			far = p
	var d0 := far.global_position.distance_to(s.global_position)
	c.target = far
	s.drive = {"throttle": 0.0, "stick": Vector2.ZERO}
	s.toggle_cruise()
	var t := 0.0
	var top := 0.0
	var slowed := false
	while t < 90.0 and (s.cruise != 0 or t < CosmosShip.CRUISE_CHARGE + 0.5):
		s._process(1.0 / 30.0)
		c._shift_origin()
		t += 1.0 / 30.0
		top = maxf(top, s.speed())
		if s.cruise == 2 and float(s.well[0]) < 0.5:
			slowed = true
	var left := c.surface_distance(far, s.global_position)
	check(t < 60.0, "the farthest planet (%.0f km away) in under a minute: %.1f s" % [d0 / 1000.0, t])
	check(left < CosmosShip.HYPER_ARRIVE * 1.5 and left > 200.0, "dropped out just short of it (%.0f m)" % left)
	check(top > 20000.0, "tens of km a second on the way (%.0f km/s)" % (top / 1000.0))
	check(slowed, "its gravity well slowed the drive on the way in")
	# A gravity well: deeper in, slower.
	var g1: float = c.gravity(far.global_position + Vector3.UP * far.radius * 1.2)[0]
	var g2: float = c.gravity(far.global_position + Vector3.UP * far.radius * 6.0)[0]
	var g3: float = c.gravity(far.global_position + Vector3.UP * far.radius * 30.0 + Vector3(far.radius * 30.0, 0, 0))[0]
	check(g1 < g2 and g2 < 1.0, "deeper in the well, slower (%.2f < %.2f)" % [g1, g2])
	check(g3 > g2, "out of it, free (%.2f)" % g3)
	c.queue_free()
	await _frames(2)


## Landed on the ocean world and out on foot (stage 3's tests start here).
func _on_foot(c: Cosmos) -> CosmosWalker:
	var i := _ground_index(c)
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	return c.walker


func test_plants_grow_on_the_ground() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var pl := w.planet
	var t0 := Time.get_ticks_msec()
	while (not pl.flora_ready or pl.deepest() < pl.max_level) and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
	for k in 40:
		await tree.process_frame
	check(pl.flora.size() >= 3, "the planet has its species of plants (%d)" % pl.flora.size())
	var kinds := {}
	for sp in pl.flora:
		kinds[sp["kind"]] = true
	check(kinds.has("tree") or kinds.has("spire"), "trees among them (%s)" % ", ".join(kinds.keys()))
	var plants := 0
	for mi in pl.get_children():
		for mm in mi.get_children():
			if mm is MultiMeshInstance3D and mm.material_override and (mm.material_override as ShaderMaterial).shader.resource_path.ends_with("flora.gdshader"):
				plants += (mm as MultiMeshInstance3D).multimesh.instance_count
	check(plants > 100, "the ground round you is planted (%d plants)" % plants)
	# The same design every time (seeded).
	var again := CosmosFlora.design(pl.shape, int(pl.rec["seed"]), str(pl.rec["type"]))
	check_eq(again.size(), pl.flora.size(), "the same species on a second look")
	c.queue_free()
	await _frames(2)


func test_animals_live_flee_hunt_and_die() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	for k in 10:
		c._life()
	check(c.creatures.size() >= 3, "animals appear round you (%d)" % c.creatures.size())
	var kinds := c.fauna_of(w.planet)
	check(kinds.size() >= 2, "the planet has its species (%s)" % ", ".join(kinds.map(func(k): return str(k["name"]))))
	var grazer: CosmosCreature = null
	var hunter: CosmosCreature = null
	for x: CosmosCreature in c.creatures:
		if x.kind["temper"] == "grazer" and grazer == null:
			grazer = x
		if x.kind["temper"] == "predator" and float(x.kind["run"]) >= 4.0 and hunter == null:
			hunter = x
	if hunter == null:   # (a fast one: the 2D game's snakes only strike close)
		var fast := kinds.filter(func(k): return k["temper"] == "predator")
		fast.sort_custom(func(a, b): return float(a["run"]) > float(b["run"]))
		for k in fast.slice(0, 1):
			if true:
				hunter = CosmosCreature.new()
				hunter.cosmos = c
				hunter.setup(k, w.planet, 5)
				c.world.add_child(hunter)
				c.creatures.append(hunter)
	var u := w.up()
	var side := w.heading.cross(u)
	if grazer:
		grazer.global_position = w.global_position + side * 6.0
		var d0 := grazer.global_position.distance_to(w.global_position)
		for k in 60:
			grazer._process(1.0 / 30.0)
		check(grazer.global_position.distance_to(w.global_position) > d0 + 3.0, "a grazer runs from you (%.0f m -> %.0f m)" % [d0, grazer.global_position.distance_to(w.global_position)])
	if hunter:
		hunter.global_position = w.global_position - side * 20.0
		var hp0 := w.hp
		for k in 240:
			hunter._process(1.0 / 30.0)
		check(w.hp < hp0, "a predator hunts you down and bites (%.0f -> %.0f)" % [hp0, w.hp])
		# Shoot it.
		var shots := 0
		while not hunter.dead and shots < 60:
			var muzzle := w.global_position + u * 1.3
			var to := hunter.global_position + hunter.up() * hunter.reach - muzzle
			var b := CosmosBolt.fire(c, muzzle, to, "player", CosmosWalker.BOLT_DAMAGE)
			for k in 20:
				if not is_instance_valid(b):
					break
				b._process(1.0 / 30.0)
			shots += 1
		check(hunter.dead, "bolts bring it down (%d shots)" % shots)
		check(c.kills >= 1, "counted")
	c.queue_free()
	await _frames(2)


func test_pirate_camps_fight_back() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var pl := w.planet
	var camps := c.camps_of(pl)
	check(camps.size() >= 3, "the planet has pirate camps (%d)" % camps.size())
	# Walk up to one.
	var cp: Vector3 = camps[0][0]
	var d := cp.normalized()
	var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var at := (cp + t * 30.0).normalized()
	w.global_position = pl.global_position + at * (pl.radius + w.floor_at(at * pl.radius) + 0.05)
	for k in 3:
		c._life()
	check(c.npcs.size() == 3, "its guards turn out (%d)" % c.npcs.size())
	check(camps[0][1] != null, "the camp itself: tent, crates, mast")
	var hp0 := w.hp
	for k in 300:
		for n in c.npcs:
			n._process(1.0 / 30.0)
		for b in c.world.get_children():
			if b is CosmosBolt:
				b._process(1.0 / 30.0)
	check(w.hp < hp0, "they shoot at you (%.0f -> %.0f)" % [hp0, w.hp])
	# Downed: back at the ship, whole.
	w.hurt(500.0)
	check(w.downed, "downed")
	c.walker_downed()
	await tree.create_timer(2.8).timeout
	check(not w.downed and w.hp == CosmosWalker.MAX_HP, "back on its feet, whole")
	check(w.global_position.distance_to(c.ship.interior.to_global(c.ship.interior.ramp_foot())) < 6.0, "by the foot of the ship's ramp")
	c.queue_free()
	await _frames(2)


func test_traffic_and_space_combat() -> void:
	var c := await _cosmos()
	c._life_rng.seed = 7   # (the same traffic every run)
	c._pirate_cd = 0.0
	# (one of the economy's traders here, docked at the station: flown as a ship)
	var r: Dictionary = Galaxy.spawn_trader(str(c.stations[0].record["id"]))
	People.crew_trader(str(r["id"]))
	r["system"] = c.system_id
	r["state"] = "docked"
	r["station"] = str(c.stations[0].record["id"])
	r["live"] = false
	r["wait"] = 60.0
	for k in 300:
		c._traffic()
		if c._flown.has(r["id"]):
			break
		await tree.process_frame
	var kinds := {}
	for x in c.npc_ships:
		kinds[x.kind] = true
	check(kinds.has("trader") and kinds.has("pirate"), "traffic about you: traders, and pirates coming (%s)" % ", ".join(kinds.keys()))
	var pirate: CosmosNpcShip = null
	for x in c.npc_ships:
		if x.kind == "pirate":
			pirate = x
	# The pirate closes in and fires on you.
	var hp0: float = c.ship.shield + c.ship.hull
	for k in 1800:
		pirate._process(1.0 / 30.0)
		for b in c.world.get_children():
			if b is CosmosBolt:
				b._process(1.0 / 30.0)
		if c.ship.shield + c.ship.hull < hp0:
			break
	check(c.ship.shield + c.ship.hull < hp0, "a pirate closes in and its lasers hit you")
	check(c.ship.hull == c.ship.max_hull or c.ship.shield < c.ship.max_shield, "the shields take it first")
	# Shoot it down: credits for the bounty.
	var cr0: int = int(c.sandbox.bounties().get("dr", 0))
	c.target = pirate
	var shots := 0
	while is_instance_valid(pirate) and not pirate.dead and shots < 200:
		var b := CosmosBolt.fire(c, c.ship.global_position, pirate.global_position - c.ship.global_position, "player", c.ship.laser_damage, true)
		for k in 80:
			if not is_instance_valid(b):
				break
			b._process(1.0 / 30.0)
		shots += 1
	check(not is_instance_valid(pirate) or pirate.dead, "lasers bring it down (%d shots, %.0f m)" % [shots, pirate.global_position.distance_to(c.ship.global_position) if is_instance_valid(pirate) else 0.0])
	check(int(c.sandbox.bounties().get("dr", 0)) > cr0, "a bounty voucher for it, to hand in at a station (%d -> %d dr)" % [cr0, int(c.sandbox.bounties().get("dr", 0))])
	CosmosGame.extra.erase("bounties")
	c.queue_free()
	await _frames(2)


func test_docking_hangar_and_terminals() -> void:
	var c := await _cosmos()
	c.dry_run = true
	check(c.station_near() != null, "starting beside a station")
	check(c.request_dock(true), "F: a pad granted (the docking computer flying)")
	check(not c.dock_pad.is_empty() and c.dock_pad["owner"] == c.ship, "the pad is yours")
	var dark_on_lift := 0
	for k in 900:
		c._docking(1.0 / 30.0)
		c.ship._process(1.0 / 30.0)
		if not c._dock.is_empty() and int(c._dock["phase"]) == 2 and c.hangar and not c.in_port():
			dark_on_lift += 1
		if c.docked and c._dock.is_empty():
			break
	check(c.docked and c.hangar != null, "set down on the pad, down its lift: in the port")
	check_eq(dark_on_lift, 0, "the port lit all the way down its lift")
	check_eq(c.ship.state, "landed", "the ship on the pad")
	check(c.hangar.get_parent() == c.dock_station, "the port is in the station (no other world)")
	var lp := c.hangar.to_local(c.ship.global_position)
	check(absf(lp.y - CosmosShip.GEAR) < 1.0 and absf(lp.x) < 5.0, "the ship down on the port's floor, on its lift (%s)" % lp)
	for k in 300:
		await tree.process_frame
		if c.hangar.built and c.hangar._spawned >= c.hangar._staff.size():
			break
	check(c.hangar.terminals.size() >= 5, "terminals in its rooms")
	c.disembark()
	var w := c.walker
	check(w != null and w.deck == c.hangar, "down the ramp onto the hangar's deck")
	for k in 30:
		w._process(1.0 / 30.0)
	check(absf(w.height_above_ground()) < 0.05, "standing on the deck")
	var cam0 := c.cam.global_position
	c.cam.global_position = c.hangar.to_global(c.hangar.to_local(w.global_position) + Vector3(0, CosmosHangar.HALL_H + 30.0, 0))
	check(c.in_port(), "you in the hall: lit, the camera however high up its shaft")
	c.cam.global_position = cam0
	w.drive = {"move": Vector2(0, 1), "run": true}
	for k in 600:
		w._process(1.0 / 30.0)
	var l := c.hangar.to_local(w.global_position)
	check(c.hangar.inside(l, 0.0).distance_to(Vector3(l.x, c.hangar.inside(l, 0.0).y, l.z)) < 0.05, "the walls hold it in")
	# Its people: talk to one, take work.
	var who: int = c.hangar.people.find(c.hangar.people.filter(func(q): return q["role"] == "officer")[0])
	w.global_position = c.hangar.to_global((c.hangar.people[who]["node"] as Node3D).position + Vector3(1.2, 0, 0))
	var talk := c.terminal_here()
	check(not talk.is_empty() and str(talk[1]) == "talk:port:%d" % who, "beside a harbour officer: talk (%s)" % [talk])
	c.talk_port(who)
	check(tree.paused, "talking: the game waits")
	c._port_work()
	c._talk_end()
	c._port_end()
	# A seat: sit down, stand up.
	var si := -1
	for k in c.hangar.seats.size():
		if not CosmosHangar._taken(c.hangar.seats[k]):
			si = k
			break
	check(si >= 0, "a free seat (%d seats)" % c.hangar.seats.size())
	var seat: Dictionary = c.hangar.seats[si]
	w.global_position = c.hangar.to_global((seat["at"] as Vector3) + (seat["face"] as Vector3) * 0.5)
	w.set_deck(c.hangar)
	var sit: Array = c.terminal_here()
	check(not sit.is_empty() and str(sit[1]).begins_with("sit:"), "beside a seat: sit down (%s)" % [sit])
	c.use_terminal(sit)
	for k in 5:
		w._process(1.0 / 30.0)
	check(not w.seat.is_empty() and seat["who"] == w and c.terminal_here()[1] == "stand", "sitting")
	c.use_terminal(["Stand up", "stand"])
	check(w.seat.is_empty() and seat["who"] == null, "up again")
	check(c.hangar.terminals.any(func(x): return x[0] == "Salvage" and int(x[1]) == 5), "a Salvage terminal (the Sell service)")
	# The market: real trade at this station.
	var t: Array = c.hangar.terminals.filter(func(x): return x[0] == "Market")[0]
	w.global_position = c.hangar.to_global(t[2])
	check(c.terminal_here() == t, "by the Market terminal")
	var sid := str(c.dock_station.record["id"])
	var good := ""
	for g in Galaxy.COMMODITIES:
		if Galaxy.stations[sid]["stock"].get(g, 0.0) > 5.0 and Galaxy.buy_price(sid, g) < 200:
			good = g
			break
	CosmosGame.data.add_credits(5000)
	var cr0: int = CosmosGame.data.credits
	c.use_terminal(t)
	await _frames(2)
	check(c._station_menu != null and c._station_menu.visible, "the terminal opens the Station Menu")
	check(not c._station_menu._bar.visible and c._station_menu.current == 1, "only the market: no tabs to the other services")
	Galaxy.player_buy(sid, good, 3, CosmosGame.data)
	check_eq(CosmosGame.data.count(good), 3, "bought 3 %s" % good)
	check(CosmosGame.data.credits < cr0, "paid for them")
	Galaxy.player_sell(sid, good, 3, CosmosGame.data)
	check_eq(CosmosGame.data.count(good), 0, "and sold them back")
	c._station_menu.close()
	# The ship's numbers from your fittings: a sturdier class, more hull.
	var h0: float = c.ship.max_hull
	var best := "player"
	for cls in ShipDesigns.ids():
		if float(Shipyard.stats(cls)["hull"]) > float(Shipyard.stats(best)["hull"]):
			best = cls
	CosmosGame.data.ship_class = best
	c.ship.apply_upgrades()
	check(best == "player" or c.ship.max_hull > h0, "a bigger hull class: more hull (%.0f -> %.0f, %s)" % [h0, c.ship.max_hull, best])
	check(not c.ship.guns.is_empty(), "the hardpoints' weapons are its guns (%d)" % c.ship.guns.size())
	CosmosGame.data.ship_class = "player"
	c.ship.apply_upgrades()
	# Aboard and out.
	check(c.embark(), "aboard again, at the controls")
	c.undock()
	for k in 600:
		c._docking(1.0 / 30.0)
		c.ship._process(1.0 / 30.0)
		if not c.docked and c._dock.is_empty():
			break
	check(not c.docked and c.ship.state == "fly", "undocked: up the lift, off the pad, flying")
	check(c.station_near() != null, "just over the station's pad")
	check(c.dock_pad.is_empty(), "the pad free again")
	c.queue_free()
	await _frames(2)


func test_manual_docking_on_a_pad() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var st := c.station_near()
	check(st != null and st.pads.size() >= 6, "a big station, its pads (%d)" % (st.pads.size() if st else 0))
	check(st.reach > 900.0, "~2 km and more across (%.0f m reach)" % st.reach)
	var big := 0
	for p in st.pads:
		if float(p["size"]) >= CosmosStation.PAD_LARGE:
			big += 1
	check(big >= 2, "pads for the big freighters (%d)" % big)
	check(c.request_dock(), "F: a pad")
	var xf := st.pad_transform(c.dock_pad)
	# Over the pad, level with it but turned across it: no touchdown - square on it, nose to its top, or not at all.
	c.ship.global_transform = Transform3D(Cosmos._level(-xf.basis.z, xf.basis.y), xf.origin + xf.basis.y * 30.0)
	c.ship.velocity = Vector3.ZERO
	c.ship.drive = {"throttle": 0.0, "lift": -0.25}
	for k in 300:
		c.ship._process(1.0 / 30.0)
		c._docking(1.0 / 30.0)
	check(c._dock.is_empty() and c.ship.state == "fly", "turned across the pad: no touchdown")
	# Square on it (a little off - within PAD_ALIGN): down on the thrusters.
	var nose := Cosmos.pad_nose(xf).rotated(xf.basis.y.normalized(), deg_to_rad(6.0))
	c.ship.global_transform = Transform3D(Cosmos._level(nose, xf.basis.y), xf.origin + xf.basis.y * 60.0)
	c.ship.velocity = Vector3.ZERO
	for k in 600:
		c.ship._process(1.0 / 30.0)
		c._docking(1.0 / 30.0)
		if c.docked:
			break
	check(c.docked, "set down by hand - down the lift into the hangar")
	check(Cosmos.pad_heading_off(xf, -c.ship.global_basis.z) < 0.5, "settled square: the nose to the pad's top (%.1f deg off)" % Cosmos.pad_heading_off(xf, -c.ship.global_basis.z))
	c.ship.drive = {}
	c.queue_free()
	await _frames(2)


func test_station_parts_are_solid() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var st := c.station_near()
	# Flown at the core: stopped at its side, not inside.
	c.ship.global_transform = Transform3D(Basis.looking_at(-st.global_basis.x, st.global_basis.y), st.to_global(Vector3(500, 0, 0)))
	c.ship.velocity = Vector3.ZERO
	c.ship.drive = {"throttle": 1.0}
	for k in 600:
		c.ship._process(1.0 / 30.0)
	var l := st.to_local(c.ship.global_position)
	check(Vector2(l.x, l.z).length() > 100.0, "the core holds it off (%.0f m from its axis)" % Vector2(l.x, l.z).length())
	check(st.push_out(st.global_position, 5.0) != Vector3.ZERO, "inside a part: pushed out")
	check(st.push_out(st.to_global(Vector3(0, 0, 5000)), 5.0) == Vector3.ZERO, "far off: clear")
	c.ship.drive = {}
	c.queue_free()
	await _frames(2)


func test_traders_use_the_pads() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var st := c.station_near()
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	var t := CosmosNpcShip.new()
	t.setup("trader", c, 7, str(st.record.get("empire", "")))
	c.world.add_child(t)
	c.npc_ships.append(t)
	t.dest = st
	t.global_position = st.to_global(Vector3(0, 600, 2500))
	var sat := false
	for k in 9000:
		t._process(1.0 / 30.0)
		if t._pad_phase == 3:
			sat = true
			break
	check(sat, "a trader flew in and set down on a pad")
	if sat:
		var xf := st.pad_transform(t.pad)
		check((xf.affine_inverse() * t.global_position).y < t.reach, "on the pad's deck")
		check(st.free_pad(10.0).get("id") != t.pad["id"], "its pad not given to anyone else")
	c.queue_free()
	await _frames(2)


func test_saves_round_trip_with_the_2d_game() -> void:
	var c := await _cosmos()
	CosmosGame.data.add_credits(1234)
	CosmosGame.extra["contract"] = {"system": "atrapos", "need": 2, "done": 0, "reward": 100}
	var snap := CosmosGame.snapshot(c)
	for k in ["player", "galaxy", "ship", "cosmos3d"]:
		check(snap.has(k), "the save has its %s section" % k)
	var p: Array = snap["ship"]["position"]
	var sys := c.system_position()
	check(absf(float(p[0]) * PlanetShape.PX_TO_M - sys.x) < 1.0 and absf(float(p[1]) * PlanetShape.PX_TO_M - sys.z) < 1.0, "the ship where it is, in the 2D map's units")
	check_eq(int(snap["player"]["credits"]), CosmosGame.data.credits, "your credits")
	check(snap["cosmos3d"].has("contract"), "the 3D game's own things ride along")
	check(snap.has("missions") and snap.has("quest"), "missions and the quest saved too")
	# Written and read back.
	check(SaveGame.save_game(snap, CosmosGame.SLOT), "written to the Autosave slot")
	var back := SaveGame.read_save(CosmosGame.SLOT)
	check_eq(int(back["state"]["player"]["credits"]), CosmosGame.data.credits, "read back")
	c.queue_free()
	await _frames(2)


func test_towns_palaces_and_people() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var i := -1
	for k in c.planets.size():
		if not c.planets[k].towns.is_empty():
			i = k
			break
	check(i >= 0, "a world of the home system has towns")
	if i < 0:
		c.queue_free()
		return
	var pl: CosmosPlanet = c.planets[i]
	var s: Dictionary = pl.towns[0]
	check_eq(str(s["kind"]), "city", "the first a city (with its palace)")
	# Its ground level: the town's plane under its buildings, nothing growing there.
	var xf := CosmosTown.frame(s, pl.radius)
	var worst := 0.0
	for p in [Vector3(60, 0, 0), Vector3(-70, 0, 40), Vector3(0, 0, -80), Vector3(120, 0, 20)]:
		var g: Vector3 = xf * p
		worst = maxf(worst, absf(pl.radius + pl.shape.height(g.normalized()) - g.length()))
	check(worst < 0.3, "the ground levelled to the town's plane (worst %.2f m)" % worst)
	check(pl.shape.cleared((xf * Vector3(30, 0, 30)).normalized()), "no boulders or plants in it")
	# Built as you come near.
	var port_dir := (xf * Vector3(123, 0, 0)).normalized()
	c.warp_to(i, 30.0, 0.0, 0.0, port_dir)
	c._towns_tick()
	var t: CosmosTown = c._towns[pl][0]
	check(t != null, "the town built as you come near")
	for k in 600:
		if t.poll():
			break
		await tree.process_frame
	check(t.built and t._solids.size() > 100, "its buildings in, solid (%d blocks)" % t._solids.size())
	check(t.spots.size() > 10, "streets to walk (%d spots)" % t.spots.size())
	# Land on its field, walk out.
	check_eq(c.landing_check(), "", "its landing field takes the ship")
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var w := c.walker
	check(w != null and w.planet == pl, "on foot in the town")
	# Up the grand staircase onto the palace roof.
	w.global_position = t.to_global(Vector3(-6.5, 0.1, 5.0))
	w.heading = t.global_basis.z
	w.drive = {"move": Vector2(0, 1)}
	var top := 0.0
	for k in 150:
		w.heading = t.global_basis.z
		w._process(1.0 / 30.0)
		top = maxf(top, t.to_local(w.global_position).y)
	check(top > 3.2, "up the stairs onto the roof (%.1f m)" % top)
	# Walls hold you out: across the court into the west wing.
	w.global_position = t.to_global(Vector3(-5, 0.1, -20))
	w.velocity = Vector3.ZERO
	for k in 240:
		w.heading = -t.global_basis.x
		w._process(1.0 / 30.0)
	var l := t.to_local(w.global_position)
	check(l.x > -18.2, "stopped by the wing's wall (x %.1f)" % l.x)
	# In through a doorway: the west wing's, off the court, into its rooms (indoors).
	var dw: Array = []
	for dr in t.doors:
		if absf((dr[0] as Vector3).x + 18.0) < 0.5 and (dr[1] as Vector3).x > 0.5:
			dw = dr
	check(not dw.is_empty(), "the west wing's doorway onto the court")
	var door_z: float = (dw[0] as Vector3).z if not dw.is_empty() else -12.0
	w.global_position = t.to_global(Vector3(-15.0, 0.2, door_z))
	w.velocity = Vector3.ZERO
	for k in 150:
		w.heading = -t.global_basis.x
		w._process(1.0 / 30.0)
	var inl := t.to_local(w.global_position)
	check(inl.x < -18.6, "through the doorway into the palace's west wing (x %.1f)" % inl.x)
	check(t.indoors(inl), "indoors: under its roof")
	# Its people come out.
	w.drive = {}
	for k in 12:
		c._towns_tick()
	await _frames(3)
	var mine := c.citizens.filter(func(x): return x.town == t)
	check(mine.size() >= 5, "citizens out in the streets (%d)" % mine.size())
	var models := {}
	for x in mine:
		models[x.model_id] = true
	if str(t.site["empire"]) == "minoa":
		check(models.has("minoan") or models.has("guard"), "Minoan androids and guards (%s)" % ", ".join(models.keys()))
	var svc := mine.filter(func(x): return x.role in CosmosSandbox.ROLES)
	if str(t.site["kind"]) == "city":
		check(svc.size() == 3, "the ore buyer, the courier's office and the local pilot by the city's landing field (%d)" % svc.size())
		var vendor: Array = svc.filter(func(x): return x.role == "vendor")
		if vendor.size() == 1:
			w.global_position = vendor[0].global_position + vendor[0].global_basis.z * 2.0
			check_eq(c.terminal_here()[0], "Talk to the ore buyer", "E beside the ore buyer: talk")
			c.sandbox.talk(vendor[0])
			await _frames(2)
			check(c._dialogue.visible, "the ore buyer's greeting")
			c._dialogue.hide()
			c._talk_end()
	# An armed townsperson takes on a pirate who comes near.
	var guardian = mine.filter(func(x): return x.role == "guard" and x.weapon != "axe")
	if not guardian.is_empty():
		var g = guardian[0]
		var pir := CosmosNpc.new()
		pir.cosmos = c
		pir.setup(pl, g.global_position - pl.global_position, 9)
		c.world.add_child(pir)
		c.npcs.append(pir)
		pir.global_position = g.global_position + g.global_basis.x * 15.0
		var bolts0 := c.world.get_children().filter(func(x): return x is CosmosBolt).size()
		var fired := false
		for k in 120:
			g._process(1.0 / 30.0)
			if c.world.get_children().filter(func(x): return x is CosmosBolt).size() > bolts0:
				fired = true
				break
		check(fired, "a %s fires on a pirate near the town" % g.label)
	if not mine.is_empty():
		var x0: Array = mine.map(func(x): return x.global_position)
		for k in 300:
			for x in mine:
				x._process(1.0 / 30.0)
		var moved := 0
		for n in mine.size():
			if mine[n].global_position.distance_to(x0[n]) > 0.5:
				moved += 1
		check(moved > 0, "and walking about (%d of %d)" % [moved, mine.size()])
	c.queue_free()
	await _frames(2)


func test_space_monsters() -> void:
	# Every creature of the 2D game, built from the kit: a mesh, spheres to hit.
	for k in CosmosMonster.KINDS:
		var t0 := Time.get_ticks_usec()
		var out: Dictionary = CosmosMonster.Body.make(k, 400.0, Color(0.5, 1.0, 0.5), 3)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var m: ArrayMesh = out["mesh"]
		check(m.get_surface_count() == 1 and (out["spheres"] as Array).size() >= 4, "%s: one mesh, %d hit spheres (%.0f ms on a worker)" % [k, (out["spheres"] as Array).size(), ms])
	var c := await _cosmos()
	c.dry_run = true
	check(not c.lairs.is_empty(), "the system's monster signals: %d lairs" % c.lairs.size())
	if c.lairs.is_empty():
		c.queue_free()
		return
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	var lr: CosmosLair = c.lairs[0]
	check(c.label_of(lr).begins_with("Unknown bio-signature"), "on the HUD: %s" % c.label_of(lr))
	# Near it: its creature comes out.
	c.ship.global_position = lr.global_position + Vector3(2500, 0, 0)
	c.ship.look_at(lr.global_position, Vector3.UP)
	c.ship.control = false
	c._lairs_tick()
	var m: CosmosMonster = lr.monster
	check(m != null, "its creature out: %s" % (m.label if m else "none"))
	for k in 300:
		m.poll()
		if m.built:
			break
		await tree.process_frame
	check(m.built, "built (on a worker)")
	# It comes for you and its orbs hit.
	var hp0: float = c.ship.shield + c.ship.hull
	for k in 1800:
		m._process(1.0 / 30.0)
		for b in c.world.get_children():
			if b is CosmosBolt:
				b._process(1.0 / 30.0)
		if c.ship.shield + c.ship.hull < hp0:
			break
	check(c.ship.shield + c.ship.hull < hp0, "its orbs (or its bulk) hurt you")
	# Shoot it down: the bounty, the signal done.
	var cr0: int = CosmosGame.data.credits
	m.hull = 30.0
	m.shield = 0.0
	var shots := 0
	while is_instance_valid(m) and not m.dead and shots < 100:
		var b := CosmosBolt.fire(c, c.ship.global_position, m.to_global(m._spheres[0][0]) - c.ship.global_position, "player", 40.0, true)
		for k in 120:
			if not is_instance_valid(b):
				break
			b._process(1.0 / 30.0)
		shots += 1
	check(not is_instance_valid(m) or m.dead, "lasers bring it down (%d shots)" % shots)
	check(CosmosGame.data.credits > cr0, "its bounty paid")
	check(bool(lr.sig.get("done", false)) or not is_instance_valid(lr), "the signal done")
	c.queue_free()
	await _frames(2)


func test_the_2d_games_animals() -> void:
	var c := await _cosmos()
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if CosmosFauna.set_of(str(p.rec.get("type", "")), p.shape) == "fo":
			pl = p
			break
	check(pl != null, "a forest world in the home system")
	if pl == null:
		c.queue_free()
		return
	var kinds := c.fauna_of(pl)
	check(kinds.all(func(k): return CosmosFauna.SPECIES.has(str(k.get("id", "")))), "its animals the 2D game's: %s" % ", ".join(kinds.map(func(k): return k["name"])))
	check(kinds.any(func(k): return k["temper"] == "predator"), "a hunter among them")
	# Every species of every set builds; the flyers fly, the floaters float.
	var rng := RandomNumberGenerator.new()
	var up: Vector3 = c.land_up(c.planets.find(pl))
	var built := 0
	var flown := 0
	for id in CosmosFauna.SPECIES:
		var k := CosmosFauna.species(id, rng)
		var cr := CosmosCreature.new()
		cr.cosmos = c
		cr.setup(k, pl, 1)
		c.world.add_child(cr)
		cr.global_position = pl.global_position + up * (pl.radius + pl.shape.height(up))
		for i in 30:
			cr._process(1.0 / 30.0)
		built += 1
		if float(k.get("alt", 0.0)) > 0.0:
			var h := (cr.global_position - pl.global_position).length() - pl.radius - pl.shape.height((cr.global_position - pl.global_position).normalized())
			if h > 0.4:
				flown += 1
		cr.queue_free()
	check_eq(built, CosmosFauna.SPECIES.size(), "every species built (%d)" % built)
	var fliers := CosmosFauna.SPECIES.keys().filter(func(i): return float(CosmosFauna.species(i, rng).get("alt", 0.0)) > 0.0).size()
	check(flown == fliers, "the flyers and floaters off the ground (%d of %d)" % [flown, fliers])
	c.queue_free()
	await _frames(2)


func test_on_foot_ramp_gauge_map_trees_and_calling_the_ship() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var w := _on_foot(c)
	var pl := w.planet
	# The ramp slopes down from the door to the ground.
	var ramp: Node3D = c.ship.interior._ramp
	var out := ramp.global_basis * Vector3(0, 0, 1)
	check(out.dot(c.ship.global_basis.y) < -0.05, "the ramp points down to the ground (%.2f)" % out.dot(c.ship.global_basis.y))
	# On foot the gauge is the automaton's.
	await _frames(2)
	var g: HealthGauge = c.hud2d.gauge
	check(g.which == "automaton" and g.silhouette != ProcArt.get_tex("ship_player"), "the gauge shows the automaton on foot")
	# The Automaton's map: the planet's, on foot.
	c.open_computer(1)   # (the MAP tab)
	await _frames(2)
	var pm: Control = c._computer.maps().sub(0)
	check(pm != null and pm.visible, "Tab > MAP: the planet's map on foot")
	# Opened on you: the globe turned to your spot, the solar map on your world.
	var you_dir: Vector3 = pm._view.all["you"]["dir"]
	check(pm._view.view_dir().dot(you_dir) > 0.999, "the planet map opens turned to your spot (%.4f)" % pm._view.view_dir().dot(you_dir))
	pm._view.turn_to(-you_dir)
	pm._view.snap()
	c._computer.maps().show_sub(1)
	var sv: Node = c._computer.maps().sub(1)._view
	check(sv.you_key() == "planet:" + str(pl.rec["id"]) and sv.focus.distance_to(sv.objs[sv.you_key()]["pos"]) < 0.01, "the solar map opens on the world you're on")
	c._computer.maps().show_sub(0)
	check(pm._view.view_dir().dot(you_dir) > 0.999, "the planet map again: turned back to you")
	c.open_computer(2)   # (the old GALAXY tab: the MAP tab's Galaxy map)
	await _frames(2)
	check(c._computer.current == 1 and c._computer.maps().current == 2 and c._computer.maps().sub(2).visible, "G / tab 3: MAP > GALAXY")
	check(not pm.visible, "the planet's map hidden behind it")
	c._computer.close()
	# The view looks up into the sky.
	c.cam._pitch = -1.3
	c.cam._follow_walker(1.0 / 30.0)
	check((-c.cam.global_basis.z).dot(w.up()) > 0.6, "looking up at the sky (%.2f)" % (-c.cam.global_basis.z).dot(w.up()))
	c.cam._pitch = 0.25
	# The ship bumps into a tree (a solid plant) in its way.
	var local := c.ship.global_position - pl.global_position
	var u := local.normalized()
	var fw := -c.ship.global_basis.z
	fw = (fw - u * fw.dot(u)).normalized()
	c.board()
	c.embark()
	c.ship.take_off()
	for k in 60:
		c.ship._process(1.0 / 30.0)
	var tree_at := c.ship.global_position - pl.global_position + fw * 40.0
	var tu := tree_at.normalized()
	var base := tu * (pl.radius + pl.shape.height(tu))
	# (a tree planted on the patches under the ship, as the scatter makes them - on
	# every level of the quadtree round it: whichever is drawn now, it's in it)
	var tree := [base, 1.5, 30.0]
	var holders: Array = []
	var stack: Array = pl._roots.duplicate()
	while not stack.is_empty():
		var p = stack.pop_back()
		if p.centre.distance_to(base) <= p.size + 40.0:
			p.rocks.append(tree)
			holders.append(p)
			stack.append_array(p.kids)
	pl._near_cache.clear()
	var h0 := (c.ship.global_position - pl.global_position).dot(tu) - pl.radius
	c.ship.global_position = pl.global_position + tu * (pl.radius + pl.shape.height(tu) + 10.0) - fw * 20.0
	c.ship.velocity = fw * 40.0
	c.ship.drive = {"throttle": 0.2}
	for k in 90:
		c.ship._process(1.0 / 30.0)
	var past := (c.ship.global_position - pl.global_position - base).dot(fw)
	check(past < 2.0, "the tree stops the ship (%.1f m past it)" % past)
	for p in holders:
		p.rocks.erase(tree)
	c.ship.drive = {}
	# Land again, out; send the ship away, call it back.
	c.warp_to(c.planets.find(pl), 40.0, 0.0, 0.0, c.land_up(c.planets.find(pl)))
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	c.ship_call()
	for k in int(Cosmos.CALL_TIME * 30) + 5:
		c._ship_calling(1.0 / 30.0)
	check(c.ship_away and not c.ship.visible, "dismissed: the ship gone up into the sky")
	c.ship_call()
	for k in int(Cosmos.CALL_TIME * 30) + 5:
		c._ship_calling(1.0 / 30.0)
	check(not c.ship_away and c.ship.visible and c.ship.state == "landed", "recalled: it came down and landed")
	var d := c.ship.global_position.distance_to(c.walker.global_position)
	check(d < 200.0, "near you (%.0f m)" % d)
	c.queue_free()
	await _frames(2)


func test_caves_and_dungeons() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var w := _on_foot(c)
	var pl := w.planet
	var sites := c.dungeons_of(pl)
	check(sites.size() == 4, "a rocky world's caves and dungeons (%d)" % sites.size())
	var site: Dictionary = {}
	for e in sites:
		if e[0]["kind"] == "dungeon":
			site = e[0]
	check(not site.is_empty(), "a dungeon among them")
	# At its mouth: E goes in.
	var u: Vector3 = site["dir"]
	w.global_position = pl.global_position + u * (pl.radius + pl.shape.height(u) + 0.1)
	var term: Array = c.terminal_here()
	check(term.size() == 2 and term[1] == "enter_dungeon", "at its mouth: %s" % (term[0] if term.size() else "nothing"))
	c.enter_dungeon(site)
	for k in 300:
		if c.dungeon and c.dungeon.built and w.deck == c.dungeon:
			break
		await tree.process_frame
	var d: CosmosDungeon = c.dungeon
	check(d != null and w.deck == d, "down in it: walking its floor")
	if d == null:
		c.queue_free()
		return
	var dead := c.npcs.filter(func(x): return x.get("dungeon") == d)
	check(dead.any(func(x): return x.role == "skeleton"), "skeleton warriors in its rooms")
	check(dead.any(func(x): return x.label == "Demon lord"), "the demon lord by its chest")
	for k in 30:
		w._process(1.0 / 30.0)
	check(absf(d.to_local(w.global_position).y) < 0.2, "standing on its floor")
	# Its walls hold: walking west into the first room's wall.
	w.drive = {"move": Vector2(0, 1)}
	for k in 200:
		w.heading = -d.global_basis.x
		w._process(1.0 / 30.0)
	var room0: Rect2 = d.rooms[0][0]
	check(d.to_local(w.global_position).x > room0.position.x - 0.1, "its walls hold you in")
	w.drive = {}
	# A skeleton comes for you.
	var sk = dead.filter(func(x): return x.role == "skeleton")[0]
	sk.global_position = w.global_position + d.global_basis.x * 6.0
	w.set_deck(d)
	var hp0 := w.hp
	for k in 150:
		sk._process(1.0 / 30.0)
	check(w.hp < hp0, "a skeleton warrior's sword finds you (%.0f -> %.0f)" % [hp0, w.hp])
	w.hp = CosmosWalker.MAX_HP
	# The walls stop your bolts (the sights).
	c.cam.global_position = w.global_position + d.global_basis.y * 1.6
	c.cam.look_at(c.cam.global_position - d.global_basis.x * 10.0, d.global_basis.y)
	check(c.aim()[2] < 30.0, "the sights stop at its walls (%.1f m)" % c.aim()[2])
	# The chest.
	w.global_position = d.to_global(d.chest_at + Vector3(0, 0.0, 1.5))
	w.set_deck(d)
	check(c.terminal_here() == ["Open the chest", "chest"], "by its chest")
	var cr0: int = CosmosGame.data.credits
	c.open_dungeon_chest()
	check(CosmosGame.data.credits > cr0, "the chest's drachmas")
	check(c._chest_key(pl, site) in CosmosGame.extra.get("looted", []), "its chest stays looted (in the save)")
	check(c.terminal_here().is_empty(), "an open chest offers nothing")
	# Back up its stairs.
	w.global_position = d.to_global(d.exit_at)
	w.set_deck(d)
	check(c.terminal_here() == ["Climb out", "leave_dungeon"], "by the stairs: climb out")
	c.leave_dungeon()
	check(c.dungeon == null and w.deck == null and w.planet == pl, "out again on the surface")
	check(not c.npcs.any(func(x): return is_instance_valid(x) and x.get("dungeon") != null), "its dead stay below")
	c.queue_free()
	await _frames(2)

## Small moons, ice sheets: on every rocky world, wherever you come down over
## dry ground, the ship finds somewhere to set down within 150 m (L).
func test_land_on_any_world() -> void:
	for sid in ["atrapos", "klotho"]:
		var c := await _cosmos(sid)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for pl: CosmosPlanet in c.planets:
			if pl.shape.kind != "rocky":
				continue
			var n := 0
			var stuck := 0
			for k in 30:
				var u := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
				var f := u.cross(Vector3.UP).normalized()
				var why := c._spot_why(pl, u, f)
				if why.begins_with("water") or why.begins_with("lava"):
					continue
				n += 1
				if why == "":
					continue
				var found := false
				for ring in [15.0, 30.0, 50.0, 75.0, 110.0, 150.0]:
					for j in 12:
						var d: Vector3 = (u * pl.radius + f.rotated(u, TAU * j / 12.0) * ring).normalized()
						if c._spot_why(pl, d, f) == "" or c._spot_why(pl, d, -f) == "":
							found = true
							break
					if found:
						break
				stuck += 0 if found else 1
			check(stuck == 0, "%s (%s, %.0f m): somewhere to land near %d of %d spots" % [pl.rec.get("name", ""), pl.rec.get("type", ""), pl.radius, n - stuck, n])
		c.queue_free()
		await _frames(2)


## Mining (CosmosMining): an asteroid under the sights becomes the target,
## it's scanned near, the beam cuts the vein nearest the sights (heat in the
## band builds resonance, too hot fractures it), fragments in the hold, the
## rock shrinks; gone when mined out - and kept so in the save.
func test_mining_an_asteroid() -> void:
	var c := await _cosmos("klotho")
	c.dry_run = true
	check(not c.fields.is_empty(), "Klotho has asteroid fields")
	var f: CosmosRocks = c.fields[0]
	var i := 0
	for k in f.rocks.size():
		if f.rocks[k][1] > f.rocks[i][1]:
			i = k
	var at: Vector3 = f.to_global(f.rocks[i][0])
	var r: float = f.rocks[i][1]
	c.ship.global_position = at + Vector3(0, 0, r + 300.0)
	c.ship.look_at(at, Vector3.UP)
	c.cam.global_position = c.ship.global_position + Vector3(0, 0, 30)
	c.cam.look_at(at, Vector3.UP)
	c.cam.set_process(false)
	var m: CosmosMining = c.mining
	c.pick_target()
	check(m.proxy != null and c.target == m.proxy and m.rock == i, "T on an asteroid: it's the target (%s)" % c.label_of(c.target) if c.target else "none")
	var st := m.rock_state()
	check(not st["scanned"], "not scanned at first")
	for k in 30:
		m.step(0.1, false)
	check(st["scanned"], "scanned once near it for %.0f s" % CosmosMining.SCAN_TIME)
	check(m.comp_text() != "", "its minerals known: %s" % m.comp_text())
	# Aim at a vein (the nearest the sights is cut).
	var cr0: int = CosmosGame.data.held_items().size()
	var units0 := 0
	for v in st["veins"]:
		units0 += int(v["units"])
	var held_frags := func() -> int:
		var n := 0
		for id in CosmosGame.data.held_items():
			if Mining.is_frag(id):
				n += CosmosGame.data.count(id)
		return n
	var before: int = held_frags.call()
	var hot := 0.0
	var mined_any := false
	for k in 60:   # (in pulses: fire while below the band's middle, let it cool above)
		var v_now: int = m.vein
		var heat: float = st["veins"][v_now]["heat"] if v_now >= 0 else 0.0
		var fire: bool = heat < (Mining.BAND.x + Mining.BAND.y) * 0.5
		m.cool(0.1)
		var on := m.step(0.1, fire)
		mined_any = mined_any or on
		hot = maxf(hot, heat)
	check(mined_any, "the beam cuts (the guns hold their fire)")
	check(held_frags.call() > before, "fragments in the hold (%d)" % (held_frags.call() - before))
	check(hot > Mining.BAND.x, "the vein heated into the band (%.2f)" % hot)
	check(f.rocks[i][1] < r, "the rock shrinks as it's mined (%.1f -> %.1f m)" % [r, f.rocks[i][1]])
	check(CosmosGame.extra.get("mined", {}).get(f.key, {}).has(str(i)), "what's cut is kept in the save")
	# Carved: the vein's pit, the rock's own mesh (built on a worker), the vein's mark at its bottom.
	check(f._carved.has(i) and not (f._carved[i]["craters"] as Array).is_empty(), "the rock carved: a pit where the vein was cut")
	for k in 120:
		f._carve_step(i, 0.05)
		if f._carved[i].has("mm") and int(f._carved[i]["task"]) == -1 and not f._carved[i]["dirty"]:
			break
		await tree.process_frame
	check(f._carved[i].has("mm"), "its carved mesh made and shown")
	var pv: Dictionary = st["veins"][m.vein]
	var dv := CosmosRocks.vein_dir(pv)
	var bottom := f.to_unit(i, f.to_local(f.vein_at(i, pv)))
	check(bottom.length() < f.unit_surface(i, dv).length() - 0.02, "the vein's mark at the bottom of its pit (%.2f < %.2f)" % [bottom.length(), f.unit_surface(i, dv).length()])
	check(CosmosGame.extra["mined"][f.key][str(i)].has("craters"), "the craters kept in the save")
	# Too hot: held on, the vein fractures.
	var vv: Dictionary = st["veins"][m.vein]
	vv["heat"] = 0.99
	m.step(0.2, true)
	check(m.last == "fracture", "held on too long, the vein fractures (%s)" % m.last)
	# Mined out: gone.
	for v in st["veins"]:
		v["units"] = 0
	st["ore_left"] = 0
	f.mined(i)
	check(f.rocks[i][1] == 0.0, "mined out: gone")
	m.step(0.1, false)
	check(m.proxy == null, "and no longer the target")
	c.queue_free()


func test_mining_deposits_on_foot() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var w := _on_foot(c)
	var t0 := Time.get_ticks_msec()
	while (c.deposits == null or c.deposits.deps.is_empty()) and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	var dp: CosmosDeposits = c.deposits
	check(dp != null and dp.planet == w.planet, "on foot: the planet's deposits round you")
	check(not dp.deps.is_empty(), "deposits on the ground near you (%d)" % dp.deps.size())
	var minerals := {}
	for k in dp.deps:
		minerals[dp.deps[k]["mineral"]] = true
		check(CosmosDeposits.MIX.get(str(w.planet.rec.get("type", "")), CosmosDeposits.MIX[""]).has(dp.deps[k]["mineral"]), "a mineral of this kind of world")
	check(minerals.size() >= 1, "minerals: %s" % ", ".join(minerals.keys()))
	# The same ones every visit (seeded).
	var keys: Array = dp.deps.keys()
	keys.sort()
	var again := CosmosDeposits._find(w.planet.shape, w.planet.radius, int(w.planet.shape.look.get("seed", 0.0) * 1000.0), CosmosDeposits.MIX.get(str(w.planet.rec.get("type", "")), CosmosDeposits.MIX[""]), w.global_position - w.planet.global_position, {})
	check(again.size() >= keys.size() - 2, "found again in the same places (%d / %d)" % [again.size(), keys.size()])
	# Stand by one, sights on it, fire: the beam cuts it.
	var dep: Dictionary = dp.deps[keys[0]]
	var sp := dp._sphere(dep)
	var u: Vector3 = dep["up"]
	var side := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	w.global_position = (sp[0] as Vector3) + side * (float(sp[1]) + 6.0) - u * float(sp[1]) * 0.3
	c.cam.set_process(false)
	c.cam.global_position = w.global_position + u * 1.6 + side * 2.0
	c.cam.look_at(sp[0], u)
	var mineral: String = dep["mineral"]
	var had: int = CosmosGame.data.count(mineral)
	var u0: int = dep["units"]
	var cut := false
	for k in 60:
		cut = dp.step(0.1, true) or cut
	check(cut and dp.focus == dep, "fire on a deposit: the mining beam cuts it (not the rifle)")
	check(int(dep["units"]) < u0, "it gives up its ore (%d -> %d)" % [u0, int(dep["units"])])
	check(CosmosGame.data.count(mineral) > had, "the %s in your pack (+%d)" % [mineral, CosmosGame.data.count(mineral) - had])
	check(dp.heat > 0.3 or dp.overheated, "the beam heats (%.2f)" % dp.heat)
	check(CosmosGame.extra["dug"][dp._pid()].has(dep["key"]), "what's dug kept in the save")
	# Held on: it overheats, and stops till it's cooled.
	for k in 100:
		dp.step(0.1, true)
		if dp.overheated:
			break
	check(dp.overheated, "held on, the beam overheats")
	var left: int = dep["units"]
	dp.step(0.1, true)
	check(int(dep["units"]) == left, "overheated: no cutting till it cools")
	for k in 60:
		dp.step(0.1, false)
	check(not dp.overheated and dp.heat == 0.0, "let go: it cools")
	# Mined out: gone, and for good.
	dep["units"] = 1
	for k in 10:
		dp.step(0.1, true)
	check(not dp.deps.has(dep["key"]), "mined out: the deposit's gone")
	check(float(CosmosGame.extra["dug"][dp._pid()][dep["key"]]) == 0.0, "gone for good (the save)")
	c.queue_free()
	await _frames(2)


func test_digging_the_ground() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var w := _on_foot(c)
	var pl := w.planet
	var t0 := Time.get_ticks_msec()
	while (c.deposits == null or pl.deepest() < pl.max_level) and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	var dp: CosmosDeposits = c.deposits
	dp.deps.clear()   # (nothing but the ground under the sights)
	dp.toggle_digger()
	check(dp.digger, "V: the terrain digger out")
	# Sights on the ground 2.5 m ahead, steeply down: it bores down.
	var u := w.up()
	var f: Vector3 = w.heading
	var spot: Vector3 = w.global_position + f * 2.5
	var d := (spot - pl.global_position).normalized()
	if pl.shape.cleared(d):
		w.global_position += f.cross(u) * 120.0
		spot = w.global_position + f * 2.5
		d = (spot - pl.global_position).normalized()
	var h0 := pl.shape.height(d)
	var ground := d * (pl.radius + h0)
	c.cam.set_process(false)
	c.cam.global_position = w.global_position + u * 1.7
	c.cam.look_at(pl.global_position + ground, u)
	check(pl.shape.density(ground - d * 1.0) < 0.0, "a metre under the ground: solid")
	var n0 := pl.shape.dig_n
	for k in 20:
		check(dp.step(0.15, true), "firing with the digger: no rifle shot")
	check(pl.shape.dig_n - n0 >= 10, "the ground carved (%d carves)" % (pl.shape.dig_n - n0))
	check(pl.shape.density(ground - d * 1.0) > 0.0, "carved: air where the ground was solid")
	var deep := 0.0
	for k in range(n0, pl.shape.dig_n):
		deep = maxf(deep, h0 - (pl.shape._centre(k).length() - pl.radius) + CosmosDeposits.DIG_R)
	check(deep > 4.0, "bored down along the beam: %.1f m deep" % deep)
	# A real voxel shape: a tunnel's possible - air under solid ground.
	var side := f.cross(u).normalized()
	var under := (ground + side * 40.0)
	var d2 := under.normalized()
	var g2 := d2 * (pl.radius + pl.shape.height(d2))
	pl.shape.dig(d2, 2.0, pl.shape.height(d2) - 4.0)   # (a hollow 4 m under the ground: its roof 2 m thick)
	check(pl.shape.density(g2 - d2 * 4.0) > 0.0 and pl.shape.density(g2 - d2 * 0.8) < 0.0, "a cave under solid ground (no heightfield can)")
	# Drawn: the voxels' chunks meshed round the carves, the heightfield not drawn inside them.
	t0 = Time.get_ticks_msec()
	while (pl.voxels == null or pl.voxels.building()) and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
	check(pl.voxels != null and not pl.voxels.chunks.is_empty(), "voxel chunks made (%d)" % (pl.voxels.chunks.size() if pl.voxels else 0))
	var tris := 0
	if pl.voxels:
		for k in pl.voxels.chunks:
			var mi: MeshInstance3D = pl.voxels.chunks[k]["mi"]
			if mi:
				tris += mi.mesh.surface_get_array_index_len(0) / 3
	check(tris > 100, "the carved ground meshed (%d triangles)" % tris)
	check(int(pl.material.get_shader_parameter("cut_n")) > 0, "the terrain shader told the carves (%d)" % int(pl.material.get_shader_parameter("cut_n")))
	# Walk in: the floor's down in the hole.
	var lw := ground + d * 1.0
	var fl := w.floor_at(lw)
	check(fl < h0 - 1.0, "the walker's floor is down in the hole (%.1f under the ground)" % (h0 - fl))
	# Down in it, the lamp comes on (the sun can't reach); up out of it, off - by day.
	w.global_position = pl.global_position + lw.normalized() * (pl.radius + fl + 0.05)
	w._lamp_t = 0.0
	w._lamp_step(1.0)
	check(w.lamp_on and w.lamp.visible, "down in the hole: the lamp on")
	var wall := []   # (the carve's wall rough: its edge at different distances round it)
	var cm := pl.shape._centre(n0)
	for a in 12:
		var dirn := (d.cross(Vector3.UP).normalized()).rotated(d, a * TAU / 12.0)
		var t := 0.0
		while t < 5.0 and pl.shape.density(cm + dirn * t) > 0.0:
			t += 0.05
		wall.append(t)
	check(wall.max() - wall.min() > 0.15, "its walls rough, not a ball's (%.2f - %.2f m)" % [wall.min(), wall.max()])
	# Kept: the save's list; a fresh shape from it carves the same.
	var saved: Array = CosmosGame.extra["digs"][str(pl.rec["id"])]
	check(saved.size() == pl.shape.dig_n, "every carve in the save (%d)" % saved.size())
	var again := PlanetShape.of(pl.rec)
	for e in saved:
		again.add_dig(Vector3(e[0], e[1], e[2]).normalized(), float(e[3]), float(e[4]))
	var probe := ground - d * 1.5
	check(absf(again.density(probe) - pl.shape.density(probe)) < 0.05, "carved the same again from the save")
	dp.toggle_digger()
	check(not dp.digger, "V again: the rifle")
	c.queue_free()
	await _frames(2)


## Dug ground and dug veins kept: saved to a file's JSON, loaded, the system built again
## (as after leaving the world, or loading the game) - the same carves, the vein as dug.
func test_excavations_kept_through_save_and_return() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if p.shape.kind == "rocky" and p.shape.sea <= 0.0:
			pl = p
			break
	if pl == null:
		pl = c.planets[0]
	var d := Vector3(0.3, 0.8, 0.5).normalized()
	var top := pl.shape.height(d) - 1.0
	var n0 := pl.shape.dig_n
	var k := pl.shape.dig(d, 2.0, top)
	check(k >= 0 and pl.shape.dig_n == n0 + 1, "a carve")
	var pid := str(pl.rec["id"])
	CosmosGame.extra["veins"] = {pid: {"0,0,0": 0.25}}
	var st: Dictionary = JSON.parse_string(JSON.stringify(CosmosGame.snapshot(c)))
	c.queue_free()
	await _frames(2)
	CosmosGame.begin_state(st)   # (loaded: a new game state from the file's)
	var c2 := await _cosmos()
	var pl2: CosmosPlanet = null
	for p: CosmosPlanet in c2.planets:
		if str(p.rec["id"]) == pid:
			pl2 = p
	check(pl2 != null and pl2.shape.dig_n == n0 + 1, "the world's carves all there again (%d)" % (pl2.shape.dig_n if pl2 else -1))
	if pl2:
		var probe := d * (pl2.radius + top)
		check(pl2.shape.density(probe) > 0.0, "the hole still a hole")
	check(float(CosmosGame.extra.get("veins", {}).get(pid, {}).get("0,0,0", 1.0)) == 0.25, "the dug vein still as dug")
	c2.queue_free()
	await _frames(2)


## Every empire builds its own: a station (pads, solid parts, one baked mesh),
## ships small and big, a town, a hangar in its look - crewed by its own people.
func test_every_empire_builds_its_own() -> void:
	var c := await _cosmos()
	c.dry_run = true
	# The game's own stations (laid out and finished in two loading steps): their bodies come in.
	var t9 := Time.get_ticks_msec()
	while c.stations.any(func(s): return s.get_node_or_null("Body") == null) and Time.get_ticks_msec() - t9 < 10000:
		await tree.process_frame
	for s0: CosmosStation in c.stations:
		var b0 := s0.get_node_or_null("Body") as MeshInstance3D
		check(b0 != null and b0.mesh != null and b0.mesh.get_surface_count() == 1, "%s: its body baked and shown" % s0.name)
	var ids := {}
	for emp in ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades", "pirates"]:
		# Its station.
		var st := CosmosStation.new()
		st.setup({"id": "test:" + emp, "name": "Test " + emp, "empire": emp, "economy": "trade", "health": 100.0})
		c.world.add_child(st)
		st.global_position = c.ship.global_position + Vector3(0, 20000, 0)
		check(st.pads.size() == 8, "%s: its station has 8 pads (%d)" % [emp, st.pads.size()])
		check(st._solids.size() > 60, "%s: its parts are solid (%d)" % [emp, st._solids.size()])
		check(st.reach > 900.0 and st.reach < 1500.0, "%s: its reach (%.0f m)" % [emp, st.reach])
		check(st.push_out(st.to_global(Vector3(0, -30, 0)), 5.0) != Vector3.ZERO, "%s: its middle is solid" % emp)
		check(st.push_out(st.to_global(Vector3(0, 0, 5000)), 5.0) == Vector3.ZERO, "%s: far off it, clear" % emp)
		var big: Dictionary = st.free_pad(CosmosShip.HULL_R * 2.6)
		check(not big.is_empty(), "%s: a pad that takes your ship" % emp)
		var t0 := Time.get_ticks_msec()
		while st._bake_task >= 0 and Time.get_ticks_msec() - t0 < 10000:
			await tree.process_frame
		var body := st.get_node_or_null("Body") as MeshInstance3D
		check(body != null and body.mesh.get_surface_count() == 1, "%s: its parts baked into one mesh" % emp)
		# Its ships.
		for is_big in [false, true]:
			for v in EmpireHulls.VARIANTS:
				var out := EmpireHulls.build(emp, is_big, v)
				var n := (out[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				check(n > 250 and n < 6000, "%s: a ship design of %d triangles (big %s, kind %d)" % [emp, n, is_big, v])
				check(EmpireHulls.engines(emp, is_big, v).size() >= 2, "%s: its engines" % emp)
		var holder := Node3D.new()
		c.world.add_child(holder)
		var nz := CosmosHull.build(holder, RandomNumberGenerator.new(), "patrol", emp)
		check(nz.size() >= 2 and holder.get_child_count() > 0, "%s: a patrol's hull built, its nozzles" % emp)
		holder.queue_free()
		# Its town (the Sea Peoples have none).
		if emp != "pirates":
			var made := CosmosTown._make("city", 5, emp)
			check((made["meshes"] as Array).all(func(m): return (m as ArrayMesh).get_surface_count() == 1) and (made["solids"] as Array).size() > 200, "%s: its city, a mesh a block, its walls solid" % emp)
		# Its hangar and crew.
		var h := CosmosHangar.new()
		h.setup(st, 1)
		st.add_child(h)
		var t1 := Time.get_ticks_msec()
		while (not h.built or h._spawned < h._staff.size()) and Time.get_ticks_msec() - t1 < 10000:
			await tree.process_frame
		check(h.get_node_or_null("Bay") != null, "%s: its port dressed" % emp)
		var kinds := {}
		for r in h.rooms:
			kinds[r["kind"]] = true
		check(kinds.has("services") and kinds.has("bar") and kinds.has("lounge") and kinds.has("offices"), "%s: its rooms (%s)" % [emp, kinds.keys()])
		check(h.rooms.filter(func(r): return r["kind"] == "services").size() == 1, "%s: one services hall (its terminals)" % emp)
		for q in h.people:   # (the floor itself: its people - visitors at the terminals - aside)
			(q["node"] as Node3D).visible = false
		for t in h.terminals:
			var at: Vector3 = t[2]
			check(h.inside(at, 0.3).distance_to(at) < 0.05, "%s: the %s terminal can be walked up to" % [emp, t[0]])
		# Its people's ways: from the hall to a terminal round everything, never through it.
		var from := Vector3(h.xi + 6.0, 0, 0)
		var way: Array = h._way(from, h.terminals[0][2])
		var through := 0
		var prev := from
		for q in way:
			var seg: Vector3 = (q as Vector3) - prev
			for k in int(seg.length() / 0.5):
				var pt: Vector3 = prev + seg * (k * 0.5 / seg.length())
				for b in h._blocks:
					if pt.x > b[0] + 0.1 and pt.x < b[2] - 0.1 and pt.z > b[1] + 0.1 and pt.z < b[3] - 0.1:
						through += 1
			prev = q
		check(way.size() >= 2 and through == 0, "%s: a way from the hall to a terminal, round its things (%d points, %d through)" % [emp, way.size(), through])
		check(h._crew.size() == CosmosHangar.CREW, "%s: its crew (%d)" % [emp, h._crew.size()])
		var armed := 0
		for cr in h._crew:
			var id := str((cr[0] as Node).get_meta("model"))
			ids[id] = true
			var want: String = CosmosNpc.PEOPLE[emp]
			check(id == want or (emp == "minoa" and id == "guard"), "%s: its crew are its own people (%s)" % [emp, id])
			if cr[4]:
				armed += 1
		check(armed == (0 if emp == "pirates" else 2), "%s: two of them on guard, armed (%d)" % [emp, armed])
		for k in 5:
			h._process(0.2)   # (they go about: no missing clips)
		h.queue_free()
		st.queue_free()
		await _frames(1)
	for id in ["minoan", "athenian", "spartan", "mycenaean", "ionian", "cycladic", "pirate"]:
		check(ids.has(id), "the %s among the crews" % id)
	# An independent station: people from everywhere.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for k in 40:
		seen[CosmosNpc.people_id("independent", rng)] = true
	check(seen.size() >= 4, "the independents' crews come from every empire (%d kinds)" % seen.size())
	EmpireHulls.finish()
	c.queue_free()
	await _frames(2)


## The jump: up and down again, upright (the jump and fall clips - not the
## old somersault). The jet pack: Space held after it burns its charge - a
## climb higher than the jump, the jet clip; at the top level it climbs out of
## the air, hovers when Space is let go (F / Ctrl brings it down).
func test_jump_and_jet_pack() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var i := 1
	for k in c.planets.size():
		if str(c.planets[k].rec.get("type", "")) == "ocean":
			i = k
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	c.ship.drive = {}
	check(c.land(), "landed")
	var t0 := Time.get_ticks_msec()
	while c.ship.state != "landed" and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	c.disembark()
	var w: CosmosWalker = c.walker
	w.global_position += w.heading * 15.0
	for k in 10:
		await tree.process_frame
	var data = CosmosGame.data
	if not data.upgrades.get("automaton") is Dictionary:
		data.upgrades["automaton"] = {}
	data.upgrades["automaton"]["legs:jet_pack"] = 0
	w._read_jet()
	w.jet_fuel = CosmosWalker.JET[0][0]
	# A tap: a jump, no jet.
	for k in 90:   # (settled on the ground)
		if w.on_ground:
			break
		w._process(1.0 / 30.0)
	check(w.on_ground, "standing (%.2f m up)" % w.height_above_ground())
	var top := 0.0
	var clips := {}
	w.drive = {"jump": true}
	for k in 4:
		w._process(1.0 / 30.0)
	w.drive = {}
	for k in 60:
		w._process(1.0 / 30.0)
		top = maxf(top, w.height_above_ground())
		clips[w._clip] = true
	check(top > 1.0 and top < 2.2, "a jump: up %.1f m" % top)
	check(clips.has("jump") and clips.has("fall") and not clips.has("leap") and not clips.has("jet"), "the jump and fall clips, no flip (%s)" % str(clips.keys()))
	check(w.on_ground, "down again")
	# Held: the jet pack's burn.
	for k in 20:
		w._process(1.0 / 30.0)
	top = 0.0
	clips = {}
	w.drive = {"jump": true}
	for k in 90:
		w._process(1.0 / 30.0)
		top = maxf(top, w.height_above_ground())
		clips[w._clip] = true
	w.drive = {}
	check(clips.has("jet") and top > 4.0, "held: the jet pack climbs higher (%.1f m)" % top)
	check(w.jet_fuel <= 0.01, "its charge burnt")
	for k in 150:
		w._process(1.0 / 30.0)
	check(w.on_ground and w.jet_fuel > CosmosWalker.JET[0][0] * 0.9, "down, the charge back")
	# The top level: out of the air, hovering.
	data.upgrades["automaton"]["legs:jet_pack"] = 5
	w._read_jet()
	check(w.jet_level == 5, "the upgrade read: level %d" % w.jet_level)
	w.drive = {"jump": true}
	for k in 300:
		w._process(1.0 / 30.0)
	var alt := w.height_above_ground()
	check(alt > w.planet.atmo_radius - w.planet.radius, "level 5: out of the air (%.0f m up)" % alt)
	w.drive = {}
	for k in 120:
		w._process(1.0 / 30.0)
	var vert := w.velocity.dot(w.up())
	check(w.jetting and absf(vert) < 2.0, "Space let go: it hovers (%.1f m/s)" % vert)
	data.upgrades["automaton"]["legs:jet_pack"] = 0
	c.queue_free()
	await _frames(2)



## The stations' law (fines, murder: their guns on you) and war at them (an
## invasion fleet's ships besieging a station, its guns answering, the hail).
func test_station_law_and_siege() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var law: CosmosLaw = c.law
	check(law != null, "the law's there")
	var st: CosmosStation = c.station_near()
	check(st != null and st.turrets.size() == 8, "the station's guns (%d)" % (st.turrets.size() if st else 0))
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	# Firing on a trader: a fine.
	var t := CosmosNpcShip.new()
	t.setup("trader", c, 5, str(st.record.get("empire", "")))
	c.world.add_child(t)
	t.global_position = st.global_position + Vector3(0, 0, st.reach + 800.0)
	c.npc_ships.append(t)
	CosmosGame.data.credits = 1000
	law.player_hit(t)
	check_eq(int(CosmosGame.data.credits), 1000 - CosmosLaw.FINE_ASSAULT, "fined for firing on a trader")
	CosmosGame.data.credits = 0
	law._fined_at.clear()
	law.player_hit(t)
	check_eq(law.debt(), CosmosLaw.FINE_ASSAULT, "unpaid: owed")
	check(law.refuses(st) != "", "no pad while you owe")
	CosmosGame.data.credits = 5000
	check_eq(law.refuses(st), "", "the fine paid, a pad again")
	check_eq(int(CosmosGame.data.credits), 5000 - CosmosLaw.FINE_ASSAULT, "the fine taken")
	# Destroying it: wanted - the station's guns on you.
	t.hurt(99999.0, t.global_position)
	check(law.wanted(), "murder: wanted in this system")
	check(law.refuses(st) != "", "no pad for a murderer")
	c.ship.global_position = st.global_position + (st.turrets[0].global_position - st.global_position).normalized() * (st.reach + 900.0) + st.global_basis.y * 300.0
	c.ship.velocity = Vector3.ZERO
	var h0: float = c.ship.hull + c.ship.shield
	for k in 240:
		await tree.process_frame
	check(c.ship.hull + c.ship.shield < h0 - 50.0, "the station's guns hit you hard (%.0f -> %.0f)" % [h0, c.ship.hull + c.ship.shield])
	law.ship_lost()
	check(not law.wanted() and law.debt() == 0, "your ship lost: the law's done with you")
	c.ship.hull = c.ship.max_hull
	c.ship.shield = c.ship.max_shield
	# A siege: an empire at war with the station's owner, its fleet here.
	var sid := str(st.record["id"])
	var owner := Galaxy.station_owner(sid)
	var foe := "sparta" if owner != "sparta" else "athens"
	Galaxy._set_relation(foe, owner, -80.0)
	var f: Dictionary = Fleets._new_fleet(foe, "invade", c.system_id, 6, [])
	check(Fleets.besieged(sid), "besieged")
	var hp0 := Galaxy.station_health(sid)
	law._hailed[sid] = true   # (its hail later)
	for k in 30:
		law._sieges()
		await tree.process_frame
	var inv: Array = c.npc_ships.filter(func(x): return is_instance_valid(x) and x.kind == "invader")
	check(inv.size() >= 1 and inv.size() <= CosmosLaw.INVADERS, "its warships out (%d)" % inv.size())
	for x in inv:   # (in close)
		x.global_position = st.global_position + (x.global_position - st.global_position).normalized() * (st.reach + 600.0)
	for k in 600:
		await tree.process_frame
	check(Galaxy.station_health(sid) < hp0, "they hit the station (%.1f -> %.1f)" % [hp0, Galaxy.station_health(sid)])
	var size0: int = f["size"]
	var one: CosmosNpcShip = c.npc_ships.filter(func(x): return is_instance_valid(x) and x.kind == "invader")[0]
	one.set_meta("by_player", true)
	one.hurt(99999.0, one.global_position)
	check(not Fleets.fleets.has(f["id"]) or int(f["size"]) < size0, "one lost: its fleet smaller")
	# The hail: its jobs offered.
	law._hailed.clear()
	c.ship.global_position = st.global_position + Vector3(0, 0, st.reach + 3000.0)
	law._hails()
	check(tree.paused, "the station hails you")
	c._talk_end()
	Fleets.fleets.erase(f["id"])
	Galaxy._set_relation(foe, owner, 0.0)
	c.queue_free()


## A fall from high up hurts (a jump doesn't); flying free far up, B brings
## the ship to you and you're aboard.
func test_fall_and_space_pickup() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var i := 1
	for k in c.planets.size():
		if str(c.planets[k].rec.get("type", "")) == "ocean":
			i = k
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	c.ship.drive = {}
	check(c.land(), "landed")
	var t0 := Time.get_ticks_msec()
	while c.ship.state != "landed" and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	c.disembark()
	var w: CosmosWalker = c.walker
	w.global_position += w.heading * 15.0
	for k in 60:
		w._process(1.0 / 30.0)
	var u := w.up()
	# From 3 m: nothing. From 30 m: hurt.
	w.global_position += u * 3.0
	w.on_ground = false
	for k in 90:
		w._process(1.0 / 30.0)
	check(is_equal_approx(w.hp, CosmosWalker.MAX_HP), "a drop of 3 m: unhurt (%.0f)" % w.hp)
	w.global_position += u * 30.0
	w.on_ground = false
	for k in 150:
		w._process(1.0 / 30.0)
	check(w.hp < CosmosWalker.MAX_HP - 30.0 and w.on_ground, "a fall of 30 m: hurt (%.0f)" % w.hp)
	w.hp = CosmosWalker.MAX_HP
	# Flying free at the top level, high up: B - the ship comes, you're aboard.
	var data = CosmosGame.data
	if not data.upgrades.get("automaton") is Dictionary:
		data.upgrades["automaton"] = {}
	data.upgrades["automaton"]["legs:jet_pack"] = CosmosWalker.JET.size() - 1
	w._read_jet()
	w.drive = {"jump": true}
	for k in 4:
		w._process(1.0 / 30.0)
	for k in 240:
		w._process(1.0 / 30.0)
		if w.height_above_ground() > 400.0:
			break
	w.drive = {}
	check(w._flying and w.height_above_ground() > Cosmos.PICK_ALT, "flying free, %.0f m up" % w.height_above_ground())
	c.ship_call()
	check(not c._call.is_empty() and c._call["kind"] == "pick", "the ship called to you")
	for k in int(Cosmos.CALL_TIME * 30.0) + 10:
		w._process(1.0 / 30.0) if c.walker else null
		c._ship_calling(1.0 / 30.0)
		if c.walker == null:
			break
	check(c.walker == null and c.ship.state == "fly", "aboard, at the controls, flying")
	data.upgrades["automaton"]["legs:jet_pack"] = 0
	c.queue_free()


## Insides follow their outsides: every port inside its own module under its
## platform - no other part of the station through its hall or rooms, its lift
## shafts clear, open space outside its windows; your ship's rooms inside its hull.
func test_interiors_inside_their_shells() -> void:
	for emp in ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades", "pirates", ""]:
		var st := CosmosStation.new()
		st.setup({"id": "shell:" + emp, "name": "Shell " + emp, "empire": emp, "economy": "trade", "health": 100.0})
		tree.root.add_child(st)
		st._collect_solids()
		var hall := 0
		var shaft := 0
		var view := 0
		for i in st.platforms.size():
			var pf: Dictionary = st.platforms[i]
			var xf := st.port_transform(i)
			var H: float = float(pf["pd"]) * 0.5
			var W: float = float(pf["pw"]) * 0.5
			var x1 := H + CosmosStation.PORT_ROOMS
			var x := -H + CosmosStation.PORT_INSET + 2.0
			while x < x1 - 2.0:
				var z := -W + 3.0
				while z < W - 3.0:
					for y in [2.0, 16.0, 31.0]:
						if st.push_out(st.to_global(xf * Vector3(x, y, z)), 0.5) != Vector3.ZERO:
							hall += 1
					z += 9.0
				x += 9.0
			var z2 := -W + 4.0
			while z2 < W - 4.0:
				for d in [6.0, 40.0]:
					if st.push_out(st.to_global(xf * Vector3(x1 + 2.0 + d, 3.0, z2)), 0.5) != Vector3.ZERO:
						view += 1
				z2 += 10.0
		for p in st.pads:
			var b := Basis(Vector3.UP, float(p["yaw"]))
			var hs: float = float(p["size"]) * 0.5 - 4.0
			for y in range(-45, -3, 6):   # (below the lift's deck at the top)
				for q in [Vector3(-hs, y, -hs), Vector3(hs, y, hs), Vector3(0, y, 0)]:
					if st.push_out(st.to_global((p["at"] as Vector3) + b * q), 0.5) != Vector3.ZERO:
						shaft += 1
		check(hall == 0, "%s: nothing of the station inside its ports' halls and rooms (%d)" % [emp, hall])
		check(shaft == 0, "%s: its lifts' shafts clear (%d)" % [emp, shaft])
		check(view == 0, "%s: open space outside its ports' windows (%d)" % [emp, view])
		st.free()
	# Your ship: each room's corners inside the hull's section there (its plates' thickness spared).
	var sec := func(z: float) -> Array:
		var hh: Array = MinoanShip.HULL
		for k in hh.size() - 1:
			if z >= float(hh[k][0]) and z <= float(hh[k + 1][0]):
				var t := (z - float(hh[k][0])) / (float(hh[k + 1][0]) - float(hh[k][0]))
				var out := []
				for c in 5:
					out.append(lerpf(float(hh[k][c]), float(hh[k + 1][c]), t))
				return out
		return []
	for r in CosmosShipInterior.ROOMS:
		for z in [float(r[2]) + 0.01, (float(r[2]) + float(r[3])) * 0.5, float(r[3]) - 0.01]:
			var s: Array = sec.call(z)
			var hw: float = float(s[1]) - 0.3
			var top: float = float(s[2]) - 0.3
			var bot: float = float(s[3]) + 0.3
			var ch: float = float(s[4])
			var ok := true
			for y in [CosmosShipInterior.FLOOR - 0.2, float(r[4]) + 0.2]:
				var ax: float = float(r[1])
				if ax > hw or y > top or y < bot or ax - (hw - ch) + y - (top - ch) > ch or ax - (hw - ch) + (bot + ch) - y > ch:
					ok = false
			check(ok, "your ship's %s inside its hull at z %.1f" % [r[0], z])



## The traders are the economy's: each ship here its record (its route, its
## people), parked down a lift while docked; off on its next run it flies its
## leg - through the gate, its record on in the next system.
func test_traders_are_the_economys() -> void:
	var c := await _cosmos()
	c.dry_run = true
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	var st: CosmosStation = c.stations[0]
	var r: Dictionary = Galaxy.spawn_trader(str(st.record["id"]))
	People.crew_trader(str(r["id"]))
	r["system"] = c.system_id
	r["state"] = "docked"
	r["station"] = str(st.record["id"])
	r["live"] = false
	r["wait"] = 40.0
	for k in 300:
		c._sync_traders()
		if c._flown.has(r["id"]):
			break
		await tree.process_frame
	check(c._flown.has(r["id"]), "the economy's trader docked here: flown as a ship")
	var s: CosmosNpcShip = c._flown.get(r["id"])
	if s == null:
		c.queue_free()
		return
	check(s._pad_phase == 3 and s._down > 50.0, "down its pad's lift, in the port")
	check(r.has("pad") and r["live"], "its record knows its pad, flown")
	var crew: Array = People.crew_of(str(r["id"]))
	check(crew.size() >= 2 and People.where(People.person(crew[0])) == "st:" + str(st.record["id"]), "its captain and crew ashore at the station (%d)" % crew.size())
	check(People.person(crew[0])["job"] == "captain", "its captain first")
	# Its time up: up the lift and off on its next run.
	s._pad_t = s._pad_stay - 0.05
	for k in 600:
		s._process(1.0 / 30.0)
		if s._pad_phase == 0:
			break
	check(r["state"] == "travel" and not (r["legs"] as Array).is_empty(), "its next run planned (%s)" % r["state"])
	check(People.where(People.person(crew[0])) == "ship:" + str(r["id"]), "its people aboard")
	var end := c.leg_end(str(r["id"]))
	check(end != null and s.dest == end, "it flies its leg (to %s)" % (end.name if end else "?"))
	if end is CosmosGate:
		var next_sys := str(r["legs"][1]["system"])
		s.global_position = end.global_position + Vector3(0, 0, 200)
		s._process(1.0 / 30.0)
		check(not c._flown.has(r["id"]) and str(r["system"]) == next_sys and not r["live"], "through the gate: its record on in %s" % next_sys)
	c.queue_free()
	await _frames(2)


## The port's people are the sector's (People): its staff on shift, its
## households off duty, the captain and crew of a ship down on one of its lifts -
## who go back aboard when their ship's time is nearly up.
func test_port_people_are_the_sectors() -> void:
	var c := await _cosmos()
	c.dry_run = true
	People.populate()
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	var st: CosmosStation = c.station_near()
	var sid := str(st.record["id"])
	# A ship of the economy at this station, down on a lift of the platform you'll dock at.
	var r: Dictionary = Galaxy.spawn_trader(sid)
	People.crew_trader(str(r["id"]))
	r["system"] = c.system_id
	r["state"] = "docked"
	r["station"] = sid
	r["live"] = false
	r["wait"] = 200.0
	check(c.request_dock(true), "a pad")
	var plat := int(c.dock_pad.get("platform", 0))
	var other: Dictionary = {}
	for pd in st.pads:
		if int(pd.get("platform", -1)) == plat and pd != c.dock_pad and (pd["owner"] == null or not is_instance_valid(pd["owner"])):
			other = pd
	for k in 300:
		c._sync_traders()
		if c._flown.has(r["id"]):
			break
		await tree.process_frame
	var s: CosmosNpcShip = c._flown.get(r["id"])
	if s and not other.is_empty() and s.pad != other:   # (onto this platform's other lift)
		s._leave_pad()
		s.park(st, other)
	r["wait"] = 200.0
	for k in 900:
		c._docking(1.0 / 30.0)
		c.ship._process(1.0 / 30.0)
		if c.docked and c._dock.is_empty():
			break
	var h: CosmosHangar = c.hangar
	for k in 600:
		await tree.process_frame
		if h.built and h._spawned >= h._staff.size() and h.people.size() > 4:
			break
	var ids: Array = h.people.map(func(q): return str(q.get("pid", "")))
	check(ids.all(func(i): return i != "" and not People.person(i).is_empty()), "every one of its people a person of the sector (%d)" % ids.size())
	var staff: Array = h.people.filter(func(q): return not q.get("leaving", false) and q["role"] in ["bartender", "officer", "guard", "dock", "carrier"])   # (at work - off duty, they're in the bar or the lounge)
	check(staff.all(func(q): return str(People.person(str(q["pid"]))["at"]) == sid and People.on_shift(People.person(str(q["pid"])))), "its staff this station's, on shift (%d)" % staff.size())
	var crew: Array = People.crew_of(str(r["id"]))
	var ashore: Array = []
	for k in 600:   # (the port looks about it every couple of seconds: they come off their ship)
		ashore = h.people.filter(func(q): return str(q.get("tid", "")) == str(r["id"]))
		if ashore.size() >= crew.size():
			break
		await tree.process_frame
	check(not other.is_empty() and ashore.size() == crew.size(), "the ship's captain and crew ashore (%d of %d; ship %s, pad %s, wait %.0f, here %s)" % [ashore.size(), crew.size(), s != null, r.get("pad", "-"), float(r.get("wait", 0)), h._ship_here(str(r["id"]))])
	var life: Array = People.story(str(crew[0]))
	check(not life.is_empty() and str(life[0]).contains(str(r["name"])), "its captain tells you of their ship (%s)" % [life])
	# Its time nearly up: they go back aboard.
	r["wait"] = 10.0
	if s:
		s._pad_stay = s._pad_t + 10.0
	for k in 1800:
		await tree.process_frame
		if h.people.filter(func(q): return str(q.get("tid", "")) == str(r["id"])).is_empty():
			break
	check(h.people.filter(func(q): return str(q.get("tid", "")) == str(r["id"])).is_empty(), "back aboard before it leaves")
	c.queue_free()
	await _frames(2)


## Every empire's traders can be walked into: rooms fitted inside the hull from the
## stern ramp's door forward (hold, quarters, bridge), standing room in each, the ramp
## down to the pad's deck, the walls keeping you in.
func test_trader_interiors_fit_their_hulls() -> void:
	for emp in ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades"]:
		for sd in [3, 11]:
			var s := CosmosNpcShip.new()
			tree.root.add_child(s)
			s.setup("trader", null, sd, emp)
			s._make_gear()
			var inn := s.make_interior()
			var t0 := Time.get_ticks_msec()
			while not inn.built and Time.get_ticks_msec() - t0 < 10000:
				await tree.process_frame
			var tag := "%s %s" % [emp, s.hull_kind]
			check(inn.ok, "%s: rooms fitted in its hull" % tag)
			if inn.ok:
				var hb: AABB = s._hull_box()
				check(inn.rooms.size() == 3, "%s: a hold, quarters and a bridge (%d rooms)" % [tag, inn.rooms.size()])
				var span: float = float(inn.rooms[-1][2]) - inn.z_fore
				check(span > hb.size.z * 0.45, "%s: its rooms run most of its length (%.0f of %.0f m)" % [tag, span, hb.size.z])
				var low := INF
				for i in inn.hws.size():
					check(float(inn.hws[i]) <= CosmosNpcInterior.MAX_HW + 0.01 and float(inn.hws[i]) * 2.0 < hb.size.x, "%s: slice %d no wider than the hull" % [tag, i])
					low = minf(low, float(inn.ceils[i]) - inn.sill)
				check(low >= 2.1, "%s: standing room everywhere (%.1f m at the lowest)" % [tag, low])
				s._ramp_k = 1.0   # (its ramp down, as in port)
				check(absf(inn.foot.y + s.rest_height()) < 0.05, "%s: the ramp's foot on the pad's deck" % tag)
				var far := inn.confine(Vector3(40.0, inn.sill, (inn.z_fore + inn.z_aft) * 0.5), 0.45)
				check(absf(far.x) < float(inn.hws[inn._slice(far.z)]), "%s: the walls keep you in" % tag)
				s._ramp_k = 0.0
				check(inn.confine(Vector3(0, inn.sill, inn.foot.z), 0.45).z < inn.z_aft, "%s: its ramp up, the door shut behind you" % tag)
				s._ramp_k = 1.0
				check(is_equal_approx(inn.floor_y(Vector3(0, 0, inn.foot.z)), inn.foot.y + inn.ramp_lift) and inn.ramp_lift < 0.4 and is_equal_approx(inn.floor_y(Vector3(0, 0, inn.z_aft - 1.0)), inn.sill), "%s: the ramp from the deck up to its floor" % tag)
			s.free()


## Your ship left where you left it (riding a trader on through a gate): in another
## system it isn't here at all; a save in a port keeps where it is and where you are;
## recalled, it comes - from the other system, a while - down this port's lift.
func test_ship_left_behind_and_recalled() -> void:
	CosmosGame.ensure()
	var sid: String = str(Galaxy.systems["klotho"]["stations"][0])
	CosmosGame.extra["ship_at"] = {"system": "atrapos", "station": "atrapos:3", "pad": 4}
	CosmosGame.extra["foot_at"] = {"station": sid, "platform": 0}
	var c := await _cosmos("klotho")
	check(c.ship_elsewhere and not c.ship.visible, "your ship in another system: not here")
	check(c.walker != null and c.hangar != null and c.walker.deck == c.hangar and str(c.port_station().record.get("id", "")) == sid, "on foot in the port you were in")
	check(c.ship_note().contains(str(Galaxy.stations["atrapos:3"]["name"])), "the panel says where your ship is (%s)" % c.ship_note())
	var snap := CosmosGame.snapshot(c)
	check(str(snap["cosmos3d"].get("ship_at", {}).get("system", "")) == "atrapos" and str(snap["cosmos3d"].get("foot_at", {}).get("station", "")) == sid,
		"a save keeps where your ship is and where you are")
	c.dry_run = true
	for p in c.hangar.station.pads:
		if int(p.get("platform", -1)) == 0:
			p["owner"] = null
	c.ship_call()
	check(not c._recall.is_empty() and float(c._recall.get("t", 0.0)) > 60.0, "recalled from another system: on its way a while (%.0f s)" % float(c._recall.get("t", 0.0)))
	c._recall["t"] = 0.1
	var t0 := Time.get_ticks_msec()
	while not (c.docked and c._dock.is_empty()) and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	check(not c.ship_elsewhere and c.ship.visible and c.ship_in_port(c.hangar), "your ship's come down this port's lift")
	check(not CosmosGame.extra.has("ship_at"), "no note of it left elsewhere")
	CosmosGame.extra.erase("ship_at")
	CosmosGame.extra.erase("foot_at")
	c.queue_free()
	await tree.process_frame


## Veins in the ground: found round you, shown by the scanner as ghosts, dug for their ore (more than a deposit's), what's left saved.
## The tool in hand (the toolbar's lit slot): picked on the toolbar - the rifle, its beam, the digger,
## the scanner (its pulse then on the left button, once a press; nothing fired).
func test_tool_in_hand_and_the_scanners_click() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var t0 := Time.get_ticks_msec()
	while c.deposits == null and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	var d: Node = CosmosGame.data
	ToolbarUse.use(c, d, "tool:beam", true)
	check_eq(ToolbarUse.held(c), "tool:beam", "the beam in hand")
	ToolbarUse.use(c, d, "tool:digger", true)
	check_eq(ToolbarUse.held(c), "tool:digger", "the digger out")
	ToolbarUse.use(c, d, "tool:scanner", true)
	check_eq(ToolbarUse.held(c), "tool:scanner", "the scanner in hand (the digger put away)")
	check(not c.deposits.digger, "the digger away")
	check_eq(c.sandbox.scan_pulse, 0.0, "picking it sends no pulse")
	w.drive = {"fire": true}
	w._process(1.0 / 60.0)
	check(c.sandbox.scan_pulse > 0.0, "the left button: its pulse")
	c.sandbox.scan_pulse = 0.0
	w._process(1.0 / 60.0)
	check_eq(c.sandbox.scan_pulse, 0.0, "held down: one pulse a press")
	w.drive = {}
	ToolbarUse.use(c, d, "tool:digger", true)
	ToolbarUse.use(c, d, "tool:digger", true)
	check_eq(ToolbarUse.held(c), "tool:rifle", "the digger put away: the rifle back in hand")
	c.queue_free()
	await _frames(2)


## A right click frees the mouse and another captures it again; a right drag (the camera) doesn't.
func test_right_click_frees_and_captures_the_mouse() -> void:
	var c := await _cosmos()
	c.set_free_mouse(false)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	var up := press.duplicate() as InputEventMouseButton
	up.pressed = false
	check(c._toggle_click(press) and c._toggle_click(up), "the right button: the free mouse's")
	check(c.free_mouse, "a right click: the mouse free")
	c._toggle_click(press)
	c._toggle_click(up)
	check(not c.free_mouse, "again: captured")
	c._toggle_click(press)
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(40, 0)
	c._input(mv)
	c._toggle_click(up)
	check(not c.free_mouse, "a right drag (turning the camera): no change")
	check(not InputMap.has_action("action_menu"), "no actions menu")
	for id in ["InventoryButton", "PlanetMapButton", "SolarMapButton", "GalaxyMapButton", "TutorialButton"]:
		check(c.hud2d.get_node_or_null(id) != null, "the HUD's %s" % id)
	var mk := InputEventKey.new()
	mk.keycode = KEY_M
	mk.physical_keycode = KEY_M
	mk.pressed = true
	c._unhandled_input(mk)
	check(c._computer != null and c._computer.visible and int(c._computer.current) == int(load("res://scripts/ui/ship_menu.gd").MAP_TAB), "M (the Automaton shut): the maps")
	c._computer.close()
	c.open_map(2)
	check(c._computer.visible and int(c._computer.current) == int(load("res://scripts/ui/ship_menu.gd").MAP_TAB), "the galaxy map's icon: the MAP tab")
	c._computer.close()
	c.queue_free()
	await _frames(2)


## The ship's shots meet where the reticle's middle is: on the sights' line, at what's on it.
func test_shots_meet_in_the_reticles_middle() -> void:
	var c := await _cosmos()
	await _frames(2)
	var fwd := -c.cam.global_basis.z
	var far := c.ship_aim()
	check(absf((far - c.cam.global_position).normalized().dot(fwd) - 1.0) < 0.0001, "on the sights' line")
	var s := CosmosNpcShip.new()
	s.setup("trader", c, 3, "minoa", "trader")
	c.world.add_child(s)
	c.npc_ships.append(s)
	s.global_position = c.cam.global_position + fwd * 600.0
	var at := c.ship_aim()
	var d := at.distance_to(c.cam.global_position)
	check(d < 600.0 and d > 600.0 - c.radius_of(s) - 1.0, "a ship 600 m along it: the shots meet at it (%.0f m)" % d)
	check(absf((at - c.cam.global_position).normalized().dot(fwd) - 1.0) < 0.0001, "still the reticle's middle")
	c.queue_free()
	await _frames(2)


func test_veins_scanned_and_dug() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var t0 := Time.get_ticks_msec()
	while c.veins.veins.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	check(c.veins.veins.size() > 0, "veins in the ground round you (%d)" % c.veins.veins.size())
	if c.veins.veins.is_empty():
		c.queue_free()
		await _frames(2)
		return
	var v: Dictionary = c.veins.veins.values()[0]
	check(int(v["units"]) >= 40, "a vein is rich (%d units)" % int(v["units"]))
	var top: Vector3 = v["pts"][0]
	var pl: CosmosPlanet = c.veins.planet
	var down: float = pl.radius + pl.shape.height(top.normalized()) - top.length()
	check(down > 2.0 and down < 12.0, "buried a few metres down (%.1f m)" % down)
	w.global_position = pl.global_position + top.normalized() * (pl.radius + pl.shape.height(top.normalized()))
	var marks: Array = c.veins.reveal(w.global_position)
	check(marks.size() >= 1 and c.veins.ghosts() >= 1, "the scanner shows it as a ghost (%d)" % marks.size())
	var tm: ShaderMaterial = pl.material
	check(int(tm.get_shader_parameter("vein_n")) >= 1 and float(tm.get_shader_parameter("ghost_k")) == 0.0, "the ground knows it (its dug walls' ore), no glow over the ground (%d veins)" % int(tm.get_shader_parameter("vein_n")))
	var holo: MeshInstance3D = c.veins._holo
	check(holo != null and holo.get_parent() == pl, "a hologram of it on its world")
	if holo:
		check(holo.mesh.get_surface_count() == 2 and holo.mesh.surface_get_primitive_type(1) == Mesh.PRIMITIVE_LINES, "its skin and its wireframe cage")
		var aabb := holo.mesh.get_aabb()
		check(aabb.has_point(top) or aabb.grow(1.0).has_point(top), "shaped along the vein itself")
		var t0us := Time.get_ticks_usec()
		CosmosVeins.holo_mesh([{"pts": v["pts"], "r": float(v["r"]), "col": Color.ORANGE}])
		var us := Time.get_ticks_usec() - t0us
		check(us < 4000, "made in a moment (%d us a vein)" % us)
	var over := 0   # (no meshes drawn over everything: the automaton, the plants, the HUD in front of it)
	for n in c.veins.find_children("*", "GeometryInstance3D", true, false):
		var m: Material = (n as GeometryInstance3D).material_override
		if m is BaseMaterial3D and (m as BaseMaterial3D).no_depth_test:
			over += 1
	check(over == 0 and c.veins.get_child_count() == 0, "no ghost meshes drawn over the rest (%d)" % over)
	c.veins.ghost_until = Time.get_ticks_msec() / 1000.0 + 1.0
	await _frames(3)
	var hk := float((CosmosVeins.holo_mats()[0] as ShaderMaterial).get_shader_parameter("k"))
	check(hk < 0.5, "the hologram fading out at its end (%.2f)" % hk)
	var before: int = CosmosGame.data.count(str(v["mineral"]))
	var left := int(v["units"])
	check(c.veins.dig(top + top.normalized() * 2.0, 2.5) > 0, "a carve into it yields ore")
	var n0 := int((CosmosVeins.holo_mats()[0] as ShaderMaterial).get_shader_parameter("cut_n"))
	var cn := func() -> int: return int(pl.material.get_shader_parameter("cut_n")) if pl.material.get_shader_parameter("cut_n") != null else 0
	var tn0: int = cn.call()
	pl.redig(top, 2.0)
	check(cn.call() == tn0 or not pl.voxels.building(), "the ground not undrawn there before its dug ground is built (no sky through the hole)")
	for i in 240:
		if not pl._cuts_wait.is_empty():
			await _frames(1)
	check(pl._cuts_wait.is_empty() and cn.call() > tn0, "then the shader told (the dug ground drawn in its place)")
	var hm: ShaderMaterial = CosmosVeins.holo_mats()[1]
	var hc: PackedVector4Array = hm.get_shader_parameter("cuts")
	var got := false
	for i in int(hm.get_shader_parameter("cut_n")):
		got = got or Vector3(hc[i].x, hc[i].y, hc[i].z).is_equal_approx(top)
	check(got and int(hm.get_shader_parameter("cut_n")) > n0, "dug: the hologram knows the carve (its dug part gone from it)")
	check(CosmosGame.data.count(str(v["mineral"])) > before and int(v["units"]) < left, "into the pack, out of the vein")
	check(float(CosmosGame.extra["veins"][c.veins._pid()][v["key"]]) < 1.0, "what's left of it is in the save")
	var sent: PackedVector4Array = tm.get_shader_parameter("vein_col")
	var at := -1
	for i in int(tm.get_shader_parameter("vein_n")):
		var p0: Vector4 = (tm.get_shader_parameter("vein_pts") as PackedVector4Array)[int((tm.get_shader_parameter("vein_span") as PackedVector4Array)[i].x)]
		if Vector3(p0.x, p0.y, p0.z).is_equal_approx(top):
			at = i
	check(at >= 0 and sent[at].w < 1.0, "the dug ground knows the vein (its ore in the walls; what's left %.2f)" % (sent[at].w if at >= 0 else -1.0))
	check_eq(c.veins.dig(top.normalized() * (pl.radius + 500.0), 2.5), 0, "a carve nowhere near it: nothing")
	CosmosGame.extra.erase("veins")
	c.queue_free()
	await _frames(2)


## Swimming at the surface, diving under (down), coming back up (Space) - the clips to match.
func test_swimming_and_diving() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var pl := w.planet
	var d0 := (w.global_position - pl.global_position).normalized()
	var rng := RandomNumberGenerator.new()
	var wet := Vector3.ZERO
	for i in 6000:
		var u := (d0 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
		if pl.shape.height(u) < -5.0:
			wet = u
			break
	check(wet != Vector3.ZERO, "deep water on the ocean world")
	if wet == Vector3.ZERO:
		c.queue_free()
		await _frames(2)
		return
	w.global_position = pl.global_position + wet * (pl.radius + 1.0)
	w.velocity = Vector3.ZERO
	w.drive = {"move": Vector2.ZERO}
	for k in 60:
		w._process(1.0 / 30.0)
	var depth := pl.radius - (w.global_position - pl.global_position).length()
	check(w.swimming and not w.diving, "afloat in deep water")
	check(absf(depth - CosmosWalker.SWIM_DEPTH) < 0.2, "at swimming depth (%.2f m)" % depth)
	w.drive = {"move": Vector2.ZERO, "dive": true}
	for k in 60:
		w._process(1.0 / 30.0)
	depth = pl.radius - (w.global_position - pl.global_position).length()
	check(w.diving and depth > CosmosWalker.SWIM_DEPTH + 1.5, "diving under (%.2f m)" % depth)
	w._process(1.0 / 30.0)
	w.drive = {"move": Vector2.ZERO, "jump": true}
	for k in 150:
		w._process(1.0 / 30.0)
		if not w.diving:
			break
	w.drive = {"move": Vector2.ZERO}
	for k in 90:
		w._process(1.0 / 30.0)
	depth = pl.radius - (w.global_position - pl.global_position).length()
	check(not w.diving and w.swimming and depth < CosmosWalker.SWIM_DEPTH + 0.3, "back up and afloat (%.2f m)" % depth)
	if w._anim:   # (the strokes go on as long as you swim: every clip model.json marks a loop loops - not once and frozen)
		for k in ["swim", "swim_idle", "dive", "dive_idle", "carry", "carry_idle"]:
			if w._anim.has_animation(k):
				check_eq(w._anim.get_animation(k).loop_mode, Animation.LOOP_LINEAR, "the %s clip loops" % k)
	w.drive = {}
	c.queue_free()
	await _frames(2)


## The worlds go round their star on the galaxy's clock (moons round their
## worlds), stations in a world's orbit band co-orbit it, and whatever's near
## a moving world is carried with it - you on its ground stay where you stand;
## the maps' places are the game's.
func test_worlds_orbit_and_carry_you() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	await _frames(3)
	var pl: CosmosPlanet = w.planet
	var pid := str(pl.rec["id"])
	var local0 := w.global_position - pl.global_position
	var sys0 := pl.global_position + c.origin
	var moons := {}
	for m: CosmosPlanet in c.planets:
		var parent := str(m.rec.get("moon_of", ""))
		if parent != "":
			for p: CosmosPlanet in c.planets:
				if str(p.rec["id"]) == parent:
					moons[m] = [p, m.global_position.distance_to(p.global_position)]
	var near := {}
	var where0 := Cosmos.planet_places(c.system_id, Galaxy.time)
	var anchors: Dictionary = Cosmos._orbits_of(c.system_id)["anchors"]
	for s in c.stations:
		var an: Array = anchors.get("station:" + str(s.record.get("id", "")), [""])
		for p: CosmosPlanet in c.planets:
			if str(p.rec["id"]) == str(an[0]):
				near[s] = [p, s.global_position.distance_to(p.global_position)]
	c._towns_tick()
	var towns0 := {}
	for k in c._towns:
		for t in c._towns[k]:
			if t != null:
				towns0[t] = t.global_position - t.planet.global_position
	var t0: float = Galaxy.time
	Galaxy.time = t0 + 60.0
	c._orbit_tick(1.0 / 60.0)
	for t in towns0:
		check(t.get_parent() == t.planet, "%s: on its world (its child)" % t.name)
		check((t.global_position - t.planet.global_position).distance_to(towns0[t]) < 0.01, "%s: where it stood on its world" % t.name)
	var sys1 := pl.global_position + c.origin
	var r: Dictionary = pl.rec
	var speed: float = TAU * float(r["orbit"]) * PlanetShape.PX_TO_M / Cosmos.orbit_period(r)
	var moon_too := str(r.get("moon_of", "")) != ""
	check(sys1.distance_to(sys0) > speed * 60.0 * 0.6 or moon_too, "the world moved on its orbit (%.0f m in a minute)" % sys1.distance_to(sys0))
	var where := Cosmos.planet_places(c.system_id, Galaxy.time)
	check(sys1.distance_to(where[pid]) < 0.5, "where its orbit says (%.2f m off)" % sys1.distance_to(where[pid]))
	check((w.global_position - pl.global_position).distance_to(local0) < 0.01, "you're carried with it: where you stood on its ground")
	for m in moons:
		var d: float = m.global_position.distance_to(moons[m][0].global_position)
		check(absf(d - float(moons[m][1])) < 0.05 * float(moons[m][1]), "a moon keeps round its world (%.0f -> %.0f m)" % [moons[m][1], d])
	var places := Cosmos.system_places(c.system_id, Galaxy.time)
	for s in c.stations:
		var key := "station:" + str(s.record.get("id", ""))
		check((s.global_position + c.origin).distance_to(places[key]) < 1.0, "%s: the map's place is the game's" % key)
		if near.has(s):
			var d: float = s.global_position.distance_to(near[s][0].global_position)
			check(absf(d - float(near[s][1])) < 300.0, "a station co-orbits its world (%.0f -> %.0f m)" % [near[s][1], d])
		for p: CosmosPlanet in c.planets:
			check(s.global_position.distance_to(p.global_position) > p.radius * 1.2, "%s clear of %s" % [key, p.rec["name"]])
	# On the side of a world facing its moon (within the moon's reach): you ride the world, not the moon.
	for m in moons:
		var world: CosmosPlanet = moons[m][0]
		var toward: Vector3 = (m.global_position - world.global_position).normalized()
		var at_d := toward
		w.global_position = world.global_position + at_d * (world.radius + world.shape.height(at_d) + 0.05)
		w.planet = world
		var wi := -1
		for i in c._bodies.size():
			if c._bodies[i][0] == world:
				wi = i
		check_eq(c._ride_of(w), wi, "under %s, on %s's ground: you ride %s" % [m.rec["name"], world.rec["name"], world.rec["name"]])
		c._rides[w] = c._ride_of(w)
		var l0 := w.global_position - world.global_position
		Galaxy.time += 30.0
		c._orbit_tick(1.0 / 60.0)
		check((w.global_position - world.global_position).distance_to(l0) < 0.01, "and stay where you stood as both move")
		break
	# Between orbit steps (30 a second): where things are to the clock, for the solar map (place_now).
	Galaxy.time += 0.02
	var wn: Dictionary = c.places_now()
	check(c.place_now(pl, wn).distance_to(wn[pid]) < 0.01, "a world's place to the clock between steps")
	if c._rides.get(w, -1) >= 0:
		var body: Node3D = c._bodies[c._rides[w]][0]
		var moved: Vector3 = c.place_now(body, wn) - (body.global_position + c.origin)
		check(moved.length() > 0.01 and (c.place_now(w, wn) - (w.global_position + c.origin)).distance_to(moved) < 0.01, "you carried with your world between steps")
	# The solar map: the world you're on shown without exploring it.
	Galaxy.planets_known.erase(pid)
	c._mirror._sweep()
	check(Galaxy.knows_planet(pid), "the world you're on: known on the solar map")
	Galaxy.time = t0
	c.queue_free()
	await _frames(2)


## A hired ride: the town's local pilot walks to his ship on the field once it's down,
## up its ramp and along its deck to the pilot's seat, and sits there - a child of its
## insides, flown with it; it lifts off only with you aboard and him seated; the
## passenger seat beside his still yours; the town's field gets a new pilot once it's gone.
func test_hired_ride_pilot_boards_and_flies() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var i := -1
	for k in c.planets.size():
		if not c.planets[k].towns.is_empty() and str(c.planets[k].towns[0]["kind"]) == "city":
			i = k
			break
	check(i >= 0, "a world with a city")
	if i < 0:
		c.queue_free()
		return
	var pl: CosmosPlanet = c.planets[i]
	var xf := CosmosTown.frame(pl.towns[0], pl.radius)
	c.warp_to(i, 30.0, 0.0, 0.0, (xf * Vector3(123, 0, 0)).normalized())
	c._towns_tick()
	var t: CosmosTown = c._towns[pl][0]
	for k in 600:
		if t.poll():
			break
		await tree.process_frame
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var w := c.walker
	for k in 12:
		c._towns_tick()
	await _frames(3)
	var pilots := c.citizens.filter(func(x): return x.town == t and x.role == "pilot")
	check_eq(pilots.size(), 1, "the city's local pilot by its field")
	if pilots.is_empty():
		c.queue_free()
		return
	var x: CosmosNpc = pilots[0]
	var st: CosmosStation = c.stations[0]
	c.sandbox._hire(x, {"kind": "station", "id": str(st.record.get("id", "")), "label": c.label_of(st)}, 0)
	c._dialogue.hide()
	c._talk_end()
	var s: CosmosNpcShip = c.sandbox._ride
	check(s != null and s.hire.get("pilot") == x, "hired: his ship on its way, him its pilot")
	var dt := 1.0 / 30.0
	for k in 900:
		s._process(dt)
		if s.hire_state() == "wait" and s._ramp_k > 0.99:
			break
	s._process(dt)
	check(s.hire_open(), "down on the field, its ramp down")
	check(x.ride == s, "its pilot off to it")
	var inn := s.interior
	var t0 := Time.get_ticks_msec()
	while inn and not inn.built and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	check(inn != null and inn.ok and inn.pilot_pos != Vector3.INF, "its insides made, a pilot's seat at its consoles")
	if inn == null or not inn.ok:
		c.queue_free()
		return
	# Its ramp solid from the ground: its sides where it's high, a step up where it's low.
	var top := inn.floor_y(Vector3(0, 0, inn.z_aft)) - inn.foot.y
	var hi := Vector3(0.3, inn.foot.y, lerpf(inn.foot.z, inn.z_aft, 1.5 / top))   # (where it's 1.5 m over the ground: too high a step, too low to walk under)
	check(absf(inn.floor_y(hi) - inn.foot.y - 1.5) < 0.2, "the ramp 1.5 m up there (%.2f m)" % (inn.floor_y(hi) - inn.foot.y))
	w.global_position = inn.to_global(hi)
	c.walker_bumps(w)
	var after := inn.to_local(w.global_position)
	check(absf(after.x) >= inn.ramp_hw, "walked into its high end from the ground: kept out by its side (x %.2f)" % after.x)
	check(not c._steps_aboard(inn, s), "not stepped up onto it there")
	var lo := Vector3(0.2, inn.foot.y, inn.foot.z - 0.9)
	w.global_position = inn.to_global(lo)
	w.velocity = Vector3.ZERO
	check(c._steps_aboard(inn, s), "stepped onto its low end, from the side or standing")
	w.global_position = inn.to_global(Vector3(0, inn.foot.y, inn.foot.z + 3.0))
	c.walker_bumps(w)
	check(inn.to_local(w.global_position).distance_to(Vector3(0, inn.foot.y, inn.foot.z + 3.0)) < 0.01, "clear of it behind its foot: not pushed")
	# Aboard before he is: the passenger seat yours, the townsfolk on the field under the hull never in the way.
	w.global_position = inn.to_global(inn.seat_pos + Vector3(0, 0, 0.9))
	w.set_deck(inn)
	var by := c.citizens.filter(func(y): return y.role in CosmosSandbox.ROLES and y != x)
	var by_at := Vector3.ZERO
	if not by.is_empty():
		by_at = by[0].global_position
		by[0].global_position = w.global_position - s.global_basis.y * 1.5
	var tm0 := c.terminal_here()
	check(tm0.size() == 2 and tm0[1] == "npc_sit", "the passenger seat to sit in before its pilot's aboard, someone just under the hull (%s)" % str(tm0))
	if not by.is_empty():
		by[0].global_position = by_at
	# You aboard first: it waits for him.
	w.global_position = inn.to_global(Vector3(0, inn.sill, inn.z_aft - 3.0))
	w.velocity = Vector3.ZERO
	w.set_deck(inn)
	var early := false
	var boarded_at := -1
	var dupes := 0
	var ramp_seen := false
	var max_step := 0.0
	var last := x.global_position
	for k in 3000:
		s._process(dt)
		x._process(dt)
		if x.global_position.distance_to(last) > max_step and s.hire_state() == "wait":
			max_step = x.global_position.distance_to(last)
		last = x.global_position
		if x.get_parent() == inn:
			if boarded_at < 0:
				boarded_at = k
				for n in 3:
					c._towns_tick()
				dupes = c.citizens.filter(func(y): return y.town == t and y.role == "pilot").size()
			if inn.on_ramp(x.position):
				ramp_seen = true
		if s.hire_state() == "climb":
			early = not x.seated()
			break
	check_eq(s.hire_state(), "climb", "off once he's seated")
	check(not early, "not before its pilot sat down (crew %d, boarded at step %d, %.1f m from the seat, aboard %.1f s)" % [x._crew, boarded_at, x.global_position.distance_to(inn.to_global(inn.pilot_pos)), float(s.hire.get("aboard_t", 0.0))])
	check(boarded_at > 0, "he walked over to it and aboard (step %d)" % boarded_at)
	check(ramp_seen, "up its ramp")
	check(max_step < CosmosNpc.CREW_RUN * 0.15 + 0.05, "walking, never a jump (%.2f m at most a step)" % max_step)
	check(not x in c.citizens, "aboard: no longer one of the town's people")
	check_eq(dupes, 0, "no second pilot by the field while his ship waits there")
	check(x.get_parent() == inn and x.position.distance_to(inn.pilot_pos) < 0.02 and inn.pilot_seat.get("who") == x, "in the pilot's seat, in its insides' space")
	check_eq(x._clip, "sit", "sitting")
	c._towns_tick()
	check_eq(c.citizens.filter(func(y): return y.town == t and y.role == "pilot").size(), 1, "his ship lifting off: a new pilot by the field")
	var z0 := s.global_position
	for k in 600:
		s._process(dt)
		x._process(dt)
		if s.hire_state() == "out":
			break
	check(s.global_position.distance_to(z0) > 1000.0, "climbed off the field (%.0f m)" % s.global_position.distance_to(z0))
	check(is_instance_valid(x) and x.get_parent() == inn and x.global_position.distance_to(inn.to_global(inn.pilot_pos)) < 0.02, "still in his seat, flown with it")
	# The passenger seat beside him: yours (his never).
	w.global_position = inn.to_global(inn.seat_pos + Vector3(0, 0, 0.9))
	w.set_deck(inn)
	var tm := c.terminal_here()
	check(tm.size() == 2 and tm[1] == "npc_sit", "the passenger seat to sit in (%s)" % str(tm))
	if tm.size() == 2:
		c.use_terminal(tm)
	check(w.seat == inn.seat and inn.seat.get("who") == w and inn.pilot_seat.get("who") == x, "in the passenger seat, him in the pilot's")
	c.use_terminal(["", "npc_stand"])
	check(w.seat.is_empty(), "up from it again")
	c.queue_free()
	await _frames(2)


## A ship you stay aboard never vanishes with you: bound for a world, it comes down
## on its town's field (ramp down, you walk off); a world with no town - on to a station.
func test_ridden_trader_lands_not_vanishes() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var town_pl: CosmosPlanet = null
	var bare_pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if town_pl == null and not p.towns.is_empty():
			town_pl = p
		if bare_pl == null and p.towns.is_empty() and p.shape.kind != "gas":
			bare_pl = p
	check(town_pl != null, "a world with a town")
	c.warp_to(c.planets.find(town_pl), 30.0, 0.0, 0.0, (CosmosTown.frame(town_pl.towns[0], town_pl.radius) * Vector3(123, 0, 0)).normalized())
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var w := c.walker
	var s := CosmosNpcShip.new()
	s.setup("trader", c, 7, "minoa", "trader")
	c.world.add_child(s)
	c.npc_ships.append(s)
	s.global_position = town_pl.global_position + Vector3(0, town_pl.radius + 30000.0, 0)
	s._make_gear()
	var inn: CosmosNpcInterior = s.make_interior()
	var t0 := Time.get_ticks_msec()
	while inn and not inn.built and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	check(inn != null and inn.ok, "its insides made")
	if inn == null or not inn.ok:
		c.queue_free()
		return
	w.global_position = inn.to_global(inn.seat_pos)
	w.set_deck(inn)
	w.sit(inn.seat, inn.seat_pos)
	check(c.riding() == s, "aboard it")
	if bare_pl:   # (bound for a townless world: on to a station instead)
		s.dest = bare_pl
		c.trader_arrived(s)
		check(is_instance_valid(s) and not s.is_queued_for_deletion(), "not gone with you aboard")
		check(s.dest is CosmosStation, "on to a station (%s)" % str(s.dest))
	s.dest = town_pl
	var dt := 1.0 / 30.0
	var landed := false
	for k in 20000:
		s._process(dt)
		if not is_instance_valid(s) or s.is_queued_for_deletion():
			break
		if s.hire_state() == "landed":
			landed = true
			break
	check(is_instance_valid(s) and not s.is_queued_for_deletion(), "never gone with you aboard")
	check(landed, "down on %s's town field (%s)" % [town_pl.rec.get("name", ""), s.hire_state() if is_instance_valid(s) else "freed"])
	if landed:
		for k in 120:
			s._process(dt)
		check(s.hire_open(), "its ramp down to walk off")
		check_eq(s.hire["pl"], town_pl, "on that world")
	# A deck freed under you: set down, not stuck on nothing.
	s.queue_free()
	await _frames(2)
	c._npc_boarding()
	check(w.deck == null and w.seat.is_empty(), "off a ship gone under you")
	c.queue_free()
	await _frames(2)


## The compass bar (top centre) and the ship's sights: the heading - north 0°, east 90° - on foot (the
## camera's way, on the world's level, north to its pole) and flying (the nose; out in space the
## system's plane, north -Z); VEL and ALT in the sights, the old readout's compass, speed and "Nearest"
## line gone; cheap to draw.
func test_compass_bar_and_sights() -> void:
	var c := await _cosmos()
	var hud: CosmosHud = c.hud
	# Flying, out in space: the system's frame.
	c.warp_to(0, 60000.0)
	var s := c.ship
	s.global_basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	check(absf(hud.compass_heading()) < 0.5, "flying north (-Z): 0° (%.1f)" % hud.compass_heading())
	s.global_basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	check(absf(hud.compass_heading() - 90.0) < 0.5, "flying east (+X): 90° (%.1f)" % hud.compass_heading())
	s.global_basis = Basis.looking_at(Vector3.LEFT + Vector3.UP * 0.5, Vector3.UP)
	check(absf(hud.compass_heading() - 270.0) < 0.5, "climbing west: 270° (%.1f)" % hud.compass_heading())
	# The compass bar's marks: what's known, at its bearing - the target's flagged.
	if not c.stations.is_empty():
		var st: Node3D = c.stations[0]
		c.target = st
		var marks: Array = hud.compass_marks()
		var want := CosmosHud.bearing(hud.compass_frame(s.global_position), st.global_position - s.global_position)
		var found := marks.filter(func(m): return m[3])
		check(found.size() == 1 and found[0][1] == "station" and absf(float(found[0][0]) - want) < 0.01, "the targeted station on the compass bar at its bearing (%.1f°)" % want)
		check(marks.size() <= CosmosHud.COMPASS_MARKS and marks.any(func(m): return m[1] == "planet") and marks.any(func(m): return m[1] == "star"), "the star and the worlds too, %d marks at most" % CosmosHud.COMPASS_MARKS)
		check(marks.all(func(m): return CompassIcons.KINDS.has(m[1]) and m[5] == CompassIcons.cell(CompassIcons.index(m[1]))), "each mark its own kind's icon (%s)" % ", ".join(marks.map(func(m): return m[1])))
		var kinds := {}
		for m in marks:
			kinds[m[1]] = true
		check(kinds.size() >= 4, "icons of several kinds: %s" % ", ".join(kinds.keys()))
		c.target = null
	# What the ship's HUD draws: the sights' VEL and ALT, the compass's letters; not the old ring's.
	hud.texts = []
	hud.queue_redraw()
	await _frames(2)
	var texts: Array = hud.texts
	check(hud._sights_layer.visible and hud._compass_layer.visible, "the sights' and the compass bar's fixed lines showing")
	check(texts.has("W") and texts.has("NW") and texts.has("270°"), "the compass bar's letters and heading (%s)" % ", ".join(texts.slice(0, 12)))
	check(texts.count(CosmosHud._speed(s.speed())) == 1, "the speed once: in VEL")
	check(not texts.any(func(t): return str(t).begins_with("Nearest") or str(t).begins_with("Altitude")), "no 'Nearest' / 'Altitude' line (ALT has it)")
	var ng: Array = hud.nearest_ground()
	check(hud._alt_on == (ng[0] != null and float(ng[1]) < CosmosHud.ALT_SHOW), "ALT only near a world's ground (%.0f m: %s)" % [float(ng[1]), hud._alt_on])
	check(not hud._cross_on, "no crosshair without a hostile locked")
	var pz := CosmosNpcShip.new()
	pz.setup("trader", c, 5, "minoa", "trader")
	pz.hostile = true   # (fired on: hostile)
	c.world.add_child(pz)
	pz.global_position = s.global_position - s.global_basis.z * 900.0
	c.target = pz
	hud.queue_redraw()
	await _frames(2)
	check(hud._cross_on, "a hostile locked: the crosshair")
	var tf := Time.get_ticks_msec()
	while hud._cross_k < 1.0 and Time.get_ticks_msec() - tf < 2000:
		hud.queue_redraw()
		await _frames(1)
	check(hud._cross_k >= 1.0 and Time.get_ticks_msec() - tf < 1000, "unfolded in a moment (%d ms)" % (Time.get_ticks_msec() - tf))
	c.target = null
	pz.queue_free()
	hud.queue_redraw()
	await _frames(2)
	check(not hud._cross_on, "unlocked: gone again")
	var us: Array = []
	for i in 8:
		hud.queue_redraw()
		await _frames(1)
		us.append(hud.draw_usec)
	us.sort()
	print("  compass + sights: %d µs (median of 8)" % us[4])
	check(us[4] < 500, "the compass and the sights draw quickly (%d µs)" % us[4])
	hud.texts = null
	# On foot: the camera's way on the world's level, north to its pole.
	var w := _on_foot(c)
	var pl := w.planet
	var up := (w.global_position - pl.global_position).normalized()
	var north := (Vector3.UP - up * up.y).normalized()
	var east := north.cross(up)
	c.cam.global_basis = Basis.looking_at(north, up)
	check(absf(hud.compass_heading()) < 0.5 or absf(hud.compass_heading() - 360.0) < 0.5, "on foot facing the pole: 0° (%.1f)" % hud.compass_heading())
	c.cam.global_basis = Basis.looking_at(east, up)
	check(absf(hud.compass_heading() - 90.0) < 0.5, "on foot facing east: 90° (%.1f)" % hud.compass_heading())
	var lon0 := atan2(up.x, up.z)
	var up2 := (w.global_position + east * 50.0 - pl.global_position).normalized()
	check(atan2(up2.x, up2.z) > lon0, "east is the way the longitude grows")
	var ship_mark: Array = (hud.compass_marks() as Array).filter(func(m): return m[1] == "ship")
	var sb := CosmosHud.bearing(hud.compass_frame(w.global_position), c.ship.global_position - w.global_position)
	check(ship_mark.size() >= 1 and ship_mark.any(func(m): return absf(float(m[0]) - sb) < 0.01), "on foot: your ship on the compass bar at its bearing (%.1f°)" % sb)
	hud.texts = []
	hud.queue_redraw()
	await _frames(2)
	check((hud.texts as Array).has("E") and hud._compass_layer.visible and not hud._sights_layer.visible, "on foot: the compass bar, not the ship's sights")
	hud.texts = null
	# Aboard (a deck under you): no compass.
	w.set_deck(c.ship.interior)
	check(hud.compass_heading() < 0.0, "inside the ship: no compass")
	c.queue_free()
	await _frames(2)


## The rifle: slung on the back, drawn off it when you shoot (the shots wait for it),
## raised and aimed - its barrel along the shot, from its own muzzle - lowered, then
## slung back; the upper body over the legs' clips (ArmsLayer).
func test_rifle_drawn_aimed_slung() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	check(w.arms != null, "the automaton's arms layer (draw, holster, aim)")
	if w.arms == null:
		c.queue_free()
		return
	check_eq(w.gun_state, "slung", "the rifle starts on the back")
	await _frames(3)
	check(w.arms.has_gun_pose and w.arms.gun_pose.origin.z < -0.2, "slung: behind the back, outside the jet pack (%.2f m behind)" % -w.arms.gun_pose.origin.z)
	w.drive = {"move": Vector2.ZERO, "fire": true}
	var states := []
	var shots_before_aim := 0
	var bolts0 := get_nodes_in_group_count(c)
	for i in 120:
		await tree.process_frame
		if states.is_empty() or states[-1] != w.gun_state:
			states.append(w.gun_state)
		if w.gun_state == "drawing" and get_nodes_in_group_count(c) > bolts0:
			shots_before_aim += 1
	check(states.has("drawing") and states.has("aiming"), "drawn, then aimed (%s)" % str(states))
	check_eq(shots_before_aim, 0, "no shot while it's being drawn")
	var shot := ((c.aim()[1] as Vector3) - w.muzzle()).normalized()
	var off := rad_to_deg(w.arms.barrel().angle_to(shot))
	check(off < 15.0, "aimed: the barrel along the shot (%.1f deg off)" % off)
	check(w.muzzle().distance_to(w.global_position) < 2.0, "the shot leaves from the rifle's muzzle")
	w.drive = {}
	w._gun_t = 0.05
	var t0 := Time.get_ticks_msec()
	var seen := []
	while w.gun_state != "slung" and Time.get_ticks_msec() - t0 < 6000:
		await tree.process_frame
		if seen.is_empty() or seen[-1] != w.gun_state:
			seen.append(w.gun_state)
	check(seen.has("holstering") and w.gun_state == "slung", "slung back after (%s)" % str(seen))
	c.queue_free()
	await _frames(2)


func get_nodes_in_group_count(c: Node) -> int:
	return c.find_children("*", "CosmosBolt", true, false).size()


## The landing field's corner posts (dark, red-topped) are solid - you walk round them, not through.
func test_field_posts_are_solid() -> void:
	var T: GDScript = load("res://scripts/world/life/cosmos_town.gd")
	var out: Dictionary = T._make("city", 7, "minoa")
	var port: Vector3 = out["port"]
	var found := 0
	for k in 4:
		var c := port + Vector3(32.0 * (1 if k % 2 else -1), 1.0, 32.0 * (1 if k < 2 else -1))
		for s in out["solids"]:
			if s is AABB and (s as AABB).grow(0.01).has_point(c):
				found += 1
				break
	check_eq(found, 4, "all four corner posts solid")
