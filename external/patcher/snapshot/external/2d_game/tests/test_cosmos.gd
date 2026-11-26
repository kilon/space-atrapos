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
		if x.kind["temper"] == "predator" and hunter == null:
			hunter = x
	if hunter == null:
		for k in kinds:
			if k["temper"] == "predator":
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
	c._traffic()
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
	var cr0: int = CosmosGame.data.credits
	c.target = pirate
	var shots := 0
	while is_instance_valid(pirate) and not pirate.dead and shots < 200:
		var b := CosmosBolt.fire(c, c.ship.global_position, pirate.global_position - c.ship.global_position, "player", c.ship.laser_damage, true)
		for k in 40:
			if not is_instance_valid(b):
				break
			b._process(1.0 / 30.0)
		shots += 1
	check(not is_instance_valid(pirate) or pirate.dead, "lasers bring it down (%d shots)" % shots)
	check(CosmosGame.data.credits > cr0, "its bounty paid (%d -> %d dr)" % [cr0, CosmosGame.data.credits])
	c.queue_free()
	await _frames(2)


func test_docking_hangar_and_terminals() -> void:
	var c := await _cosmos()
	c.dry_run = true
	check(c.station_near() != null, "starting beside a station")
	check(c.request_dock(), "F: docking granted")
	for k in 300:
		c._docking(1.0 / 30.0)
		if c.docked and c._dock.is_empty():
			break
	check(c.docked and c.hangar != null, "flown in: docked, in the hangar")
	check_eq(c.ship.state, "landed", "the ship on the pad")
	check(c.hangar.terminals.size() >= 5, "terminals along the back wall")
	c.disembark()
	var w := c.walker
	check(w != null and w.deck == c.hangar, "down the ramp onto the hangar's deck")
	for k in 30:
		w._process(1.0 / 30.0)
	check(absf(w.height_above_ground()) < 0.05, "standing on the deck")
	w.drive = {"move": Vector2(0, 1), "run": true}
	for k in 600:
		w._process(1.0 / 30.0)
	var l := c.hangar.to_local(w.global_position)
	check(absf(l.x) <= CosmosHangar.BOUNDS.x and absf(l.z) <= CosmosHangar.BOUNDS.z, "the walls hold it in")
	# The market: real trade at this station.
	var t: Array = c.hangar.terminals[1]
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
	for k in 120:
		c._docking(1.0 / 30.0)
	check(not c.docked and c.ship.state == "fly", "undocked: out of the bay, flying")
	check(c.station_near() != null, "just outside the station")
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
