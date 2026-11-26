extends TestCase
## What damage looks and feels like: afflictions (Parts.afflictions) under
## the health bars (AfflictionBar) - the frozen self-repair always first, a
## damaged part each - more the worse the body's hurt (Parts.by_health), gone
## when repaired; the near-death screen (DamageScreen); sparks (FaultSparks);
## accuracy (Accuracy): every shot can miss, and a miss flies past.

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


func test_afflictions() -> void:
	var c := {}
	check(Parts.afflictions(c, "ship").is_empty(), "sound: no afflictions")
	check(not Parts.regen_frozen(c, "ship"), "self-repair working")
	Parts.add_fault(c, "ship", "engines", "crack", 1, _rng(1))
	var a := Parts.afflictions(c, "ship")
	check(a.size() == 2 and a[0]["id"] == "regen", "the first: the self-repair frozen (%s)" % str(a.map(func(x): return x["id"])))
	check(a[1]["part"] == "engines" and str(a[1]["desc"]).contains("speed"), "then the damaged part, with what it does")
	check(Parts.regen_frozen(c, "ship"), "frozen while anything is damaged")
	# The worse it's hurt, the more.
	var c2 := {}
	check(Parts.by_health(c2, "ship", 0.9).is_empty(), "at 90%: none needed")
	Parts.by_health(c2, "ship", 0.5, "kinetic", _rng(2))
	check_eq(Parts.fault_count(c2, "ship"), 2, "at 50%: two faults")
	Parts.by_health(c2, "ship", 0.1, "kinetic", _rng(3))
	check(Parts.fault_count(c2, "ship") >= 5, "near death: five or more")
	check(Parts.afflictions(c2, "ship").size() >= 3, "and as many afflictions as damaged parts")
	# Repaired: gone.
	Parts.clear_all(c2, "ship")
	check(Parts.afflictions(c2, "ship").is_empty() and not Parts.regen_frozen(c2, "ship"), "repaired: they go, the self-repair works again")
	# The screen and the glass.
	check_eq(DamageScreen.level(1.0), 0.0, "healthy: a clear screen")
	check(DamageScreen.level(0.25) > 0.0 and DamageScreen.level(0.05) > 0.8, "near death: the screen fails")


func test_in_play() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	var ship: Node2D = _main.ship
	var pd: Node = _main.player_data
	check(_main.hud.gauge != null and _main.hud.gauge.icons().is_empty(), "the gauge: no afflictions round it")
	for i in 5:
		ship.shields = 0.0
		ship.take_damage(ship.max_hull * 0.15, ship.global_position + Vector2(0, 200))
	_main.hud.gauge.refresh()
	check(Parts.fault_count(pd.condition, "ship") >= 3, "a battering leaves faults (%d)" % Parts.fault_count(pd.condition, "ship"))
	check(_main.hud.gauge.icons().size() >= 2, "their icons round the gauge")
	var first: Control = _main.hud.gauge.icons()[0]
	check(first.tooltip_text.contains(Parts.REGEN_NAME), "the first icon: the frozen self-repair (tooltip)")
	# Frozen: the hull doesn't mend.
	var h: float = ship.hull
	ship._since_hit = 99.0
	ship._process(1.0)
	check(is_equal_approx(ship.hull, h), "no self-repair while damaged")
	Parts.clear_all(pd.condition, "ship")
	ship.apply_tech()
	ship._since_hit = 99.0
	ship._process(1.0)
	check(ship.hull > h, "repaired: the hull mends itself again")
	check(ship._sparks != null, "the ship crackles when hurt (FaultSparks)")
	check(_main.damage_screen != null, "and the screen fails near death (DamageScreen)")



## Shields recharging and the hull mending themselves burn fuel; out of fuel, neither does.
func test_regen_costs_fuel() -> void:
	Galaxy.current_system = Galaxy.HOME
	if not is_instance_valid(_main):
		_main = load("res://main.tscn").instantiate()
		tree.root.add_child(_main)
		for i in 40:
			await tree.process_frame
	var ship: Node2D = _main.ship
	var pd: Node = _main.player_data
	Parts.clear_all(pd.condition, "ship")
	ship.apply_tech()
	pd.fuel = pd.fuel_max()
	# The shields: 10 points back cost 10 x FUEL_PER_SHIELD.
	ship.shields = ship.max_shields - 10.0
	ship._since_hit = 99.0
	var f0: float = pd.fuel_level()
	ship._process(10.0 / ship.shield_regen)
	check(is_equal_approx(ship.shields, ship.max_shields), "the shields recharged")
	check(absf((f0 - pd.fuel_level()) - 10.0 * Shipyard.FUEL_PER_SHIELD) < 0.01, "for fuel: %.3f (10 points)" % (f0 - pd.fuel_level()))
	# The hull: what it mends costs FUEL_PER_HULL a point.
	ship.hull = ship.max_hull - 50.0
	var h0: float = ship.hull
	f0 = pd.fuel_level()
	ship._since_hit = 99.0
	ship._process(2.0)
	var mended: float = ship.hull - h0
	check(mended > 0.0, "the hull mends itself (%.1f)" % mended)
	check(absf((f0 - pd.fuel_level()) - mended * Shipyard.FUEL_PER_HULL) < 0.01, "for fuel: %.3f" % (f0 - pd.fuel_level()))
	# Out of fuel: neither comes back.
	pd.fuel = 0.0
	ship.shields = 0.0
	var h1: float = ship.hull
	ship._since_hit = 99.0
	ship._process(2.0)
	check(ship.shields == 0.0 and is_equal_approx(ship.hull, h1), "out of fuel: no recharge, no mending")
	# A little fuel: as much as it pays for.
	pd.fuel = 0.1
	ship._process(1.0)
	check(ship.shields > 0.0 and ship.shields <= 0.1 / Shipyard.FUEL_PER_SHIELD + 0.01 and pd.fuel_level() < 0.001, "a little fuel: what it pays for (%.1f shields)" % ship.shields)


func test_accuracy() -> void:
	var target := Node2D.new()
	target.position = Vector2(400, 0)
	tree.root.add_child(target)
	var close := Accuracy.chance(0.9, Vector2.ZERO, target, 1000.0)
	target.position = Vector2(950, 0)
	var far := Accuracy.chance(0.9, Vector2.ZERO, target, 1000.0)
	check(close > far, "further: harder to hit (%.2f / %.2f)" % [close, far])
	check(close <= Accuracy.MAX_HIT, "never certain")
	var d := Accuracy.miss_dir(Vector2.ZERO, Vector2(500, 0), 40.0)
	var off := absf(d.angle()) * 500.0
	check(off > 40.0, "a miss is aimed past the target's edge (%.0f px off)" % off)
	target.free()
	# Ships miss: a projectile marked to fly past its target.
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 30:
		await tree.process_frame
	var ship: Node2D = _main.ship
	ship.invulnerable = true
	check(ship.accuracy() > 0.5 and ship.accuracy() < 1.0, "your ship's accuracy (%.2f)" % ship.accuracy())
	Parts.add_fault(_main.player_data.condition, "ship", "sensors", "wreck", 0, _rng(4))
	ship.apply_tech()
	check(ship.accuracy() < Accuracy.BASE_SHIP, "damaged sensors: worse aim")
	var e: Node2D = _main.spawn_enemy(ship.global_position + Vector2(0, -400))
	e.max_hull = 1e9
	e.hull = 1e9
	await tree.process_frame
	ship.set_attack_target(e)
	var missed := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await tree.process_frame
		for p in tree.get_nodes_in_group("fx_layer")[0].get_children():
			if p is Projectile and p.shooter == ship and p.ignore == e and not p.has_meta("n"):
				p.set_meta("n", true)
				missed += 1
	check(missed > 0, "some of your shots miss - and fly past it (%d)" % missed)


func test_on_foot() -> void:
	var old: String = SaveGame.landed_planet
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	var pilot = s.pilot
	check(s.gauge != null and s.damage_screen != null, "on foot: the health gauge and the damage screen")
	# The automaton's shield takes a hit first, then comes back once you're out of the fight.
	pilot.hp = pilot.max_hp
	pilot.shield = pilot.max_shield
	pilot.surface_hit(pilot.max_shield * 0.5, "kinetic")
	check(is_equal_approx(pilot.hp, pilot.max_hp) and pilot.shield < pilot.max_shield, "the shield soaks a hit (health untouched)")
	pilot.surface_hit(pilot.max_shield, "kinetic")
	check(pilot.shield == 0.0 and pilot.hp < pilot.max_hp, "a bigger one breaks through to your health")
	pilot._since_hit = 99.0
	pilot._process(1.0)
	check(pilot.shield > 0.0, "out of the fight: the shield recharges")
	pilot.hp = pilot.max_hp
	pilot.shield = 0.0
	pilot.max_shield = 0.0   # (the battering below reaches the parts)
	for i in 6:
		pilot.surface_hit(pilot.max_hp * 0.13, "kinetic")
	var cond: Dictionary = s.state["player"]["condition"]
	check(Parts.fault_count(cond, "automaton") >= 2, "a battering damages the automaton's parts (%d)" % Parts.fault_count(cond, "automaton"))
	s.gauge.refresh()
	check(s.gauge.icons().size() >= 2, "their icons round the health gauge")
	var hp: float = pilot.hp
	pilot._since_hit = 99.0
	pilot._process(1.0)
	check(is_equal_approx(pilot.hp, hp), "no healing while damaged")
	check(pilot.accuracy > 0.5 and pilot.accuracy < 1.0, "the automaton's accuracy (%.2f)" % pilot.accuracy)
	s.queue_free()
	SaveGame.landed_planet = old
	await tree.process_frame
