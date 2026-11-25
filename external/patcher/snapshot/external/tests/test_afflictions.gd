extends TestCase
## Afflictions (Affliction, Parts): a ship's damaged parts acting up beyond
## weaker numbers - thrusters jerking it off course, the fire control losing
## the target and firing wild, the sensors scattering shots - for your ship
## and for others, whose hull hits damage their own parts too.

var _main: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}


func _rng(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = n
	return r


func test_the_helpers() -> void:
	var st := Affliction.new_state()
	check(Affliction.jitter_push(st, 0.0, 0.1, 400.0) == Vector2.ZERO, "sound thrusters: no kick")
	var kicks := 0.0
	for i in 20:
		kicks = maxf(kicks, Affliction.jitter_push(st, 0.3, 0.1, 400.0).length())
	check(kicks > 30.0, "thrusters a third gone: kicks you feel (%.0f)" % kicks)
	var started := 0
	var wild_t := 0.0
	for i in 600:   # (a minute at 0.1 s)
		var m := Affliction.misfire(st, 1.0, 0.1)
		if m == 1:
			started += 1
		if m != 0:
			wild_t += 0.1
	check(started >= 3 and wild_t < 50.0, "wrecked fire control: spells of wild fire, not all the time (%d, %.0f s)" % [started, wild_t])
	var st2 := Affliction.new_state()
	var wild_sound := 0
	for i in 600:
		wild_sound += 1 if Affliction.misfire(st2, 0.0, 0.1) != 0 else 0
	check(wild_sound == 0, "sound fire control: never wild")
	var off := 0.0
	for i in 50:
		off = maxf(off, absf(Affliction.scattered(Vector2.RIGHT, 0.5).angle()))
	check(off > 0.05 and off <= Affliction.SCATTER, "damaged sensors: shots scatter (%.2f rad)" % off)
	check(Affliction.scattered(Vector2.RIGHT, 0.0) == Vector2.RIGHT, "sound sensors: true aim")
	# The parts carry them.
	var c := {}
	Parts.add_fault(c, "ship", "thrusters", "wreck", 0, _rng(1))
	Parts.add_fault(c, "ship", "weapons", "wreck", 0, _rng(1))
	Parts.add_fault(c, "ship", "sensors", "wreck", 0, _rng(1))
	var fx := Parts.effects(c, "ship")
	check(fx.get("jitter", 0.0) > 0.0 and fx.get("misfire", 0.0) > 0.0 and fx.get("scatter", 0.0) > 0.0,
			"thrusters, weapon mounts and sensors damaged: jitter, misfire, scatter (%s)" % str(fx))


func test_your_ship_acts_up() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	var ship: Node2D = _main.ship
	ship.invulnerable = true
	ship.stop()
	ship.velocity = Vector2.ZERO
	var pd: Node = _main.player_data
	# Sound: it sits still.
	var at: Vector2 = ship.global_position
	for i in 30:
		await tree.process_frame
	check(ship.global_position.distance_to(at) < 2.0, "sound thrusters: it holds still")
	Parts.add_fault(pd.condition, "ship", "thrusters", "wreck", 0, _rng(3))
	Parts.add_fault(pd.condition, "ship", "thrusters", "drift", 1, _rng(4))
	ship.apply_tech()
	check(ship._jitter > 0.0, "damaged thrusters: it jitters (%.2f)" % ship._jitter)
	at = ship.global_position
	var rot: float = ship.rotation
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await tree.process_frame
	check(ship.global_position.distance_to(at) > 5.0 or absf(ship.rotation - rot) > 0.02, "it drifts and wobbles off its place (%.0f px)" % ship.global_position.distance_to(at))
	# Fire control: wild shots.
	Parts.add_fault(pd.condition, "ship", "weapons", "wreck", 1, _rng(5))
	ship.apply_tech()
	check(ship._misfire > 0.0, "damaged weapon mounts: misfire (%.2f)" % ship._misfire)


func test_other_ships_parts_are_hit_too() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	_main.ship.invulnerable = true
	var e: Node2D = _main.spawn_enemy(_main.ship.global_position + Vector2(900, 0))
	await tree.process_frame
	var speed: float = e.max_speed
	var shields: float = e.max_shields
	# Heavy hits through to the hull (shields down) damage its parts.
	for i in 80:
		e.hull = e.max_hull
		e.shields = 0.0
		e.take_damage(e.max_hull * 0.2, e.global_position + Vector2(0, 200), _main.ship, "kinetic")
		if Parts.fault_count(e.condition, "ship") >= 4:
			break
	check(Parts.fault_count(e.condition, "ship") > 0, "hull hits damage an enemy's parts (%d)" % Parts.fault_count(e.condition, "ship"))
	# Its stats follow its parts.
	var c := {}
	Parts.add_fault(c, "ship", "engines", "wreck", 0, _rng(6))
	Parts.add_fault(c, "ship", "shields", "wreck", 0, _rng(7))
	Parts.add_fault(c, "ship", "thrusters", "wreck", 0, _rng(8))
	var e2: Node2D = _main.spawn_enemy(_main.ship.global_position + Vector2(-900, 0))
	await tree.process_frame
	speed = e2.max_speed
	shields = e2.max_shields
	e2.condition = c
	e2._apply_parts()
	check(e2.max_speed < speed * 0.9, "wrecked engines: it's slower (%.0f < %.0f)" % [e2.max_speed, speed])
	check(shields <= 0.0 or e2.max_shields < shields, "a wrecked emitter: weaker shields")
	check(e2._fx.has("jitter"), "wrecked thrusters: it jerks off course")
	# Saved with it.
	var sd: Dictionary = e2.get_save_data()
	var back := Parts.load_condition(JSON.parse_string(JSON.stringify(sd["condition"])))
	check_eq(Parts.fault_count(back, "ship"), 3, "its damage is saved")
