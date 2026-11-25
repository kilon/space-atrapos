extends TestCase
## Gear (Gear): equipment for your ship and your automaton, quality E to A -
## items like any other ("gear:<kind>:<quality>"); the automaton's loadout;
## ship gear fitted from the hold; damage types and resistances; where it
## comes from (outfitters, drops, encounters).

const PROPS := preload("res://scripts/surface_props.gd")
var _old_planet := ""


func setup() -> void:
	_old_planet = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old_planet


func test_catalogue_and_items() -> void:
	for kind in Gear.FOOT.keys() + Shipyard.MODULES.keys():
		for q in Gear.QUALITY.size():
			var id := Gear.item_id(kind, q)
			check_eq(Gear.parse(id), [kind, q], "%s round-trips" % id)
			check(Items.exists(id) and Items.info(id)["kind"] == "gear", "%s is an item" % id)
			check(Items.display_name(id).ends_with(Gear.QUALITY[q]), "%s: named with its quality" % id)
			check(Gear.describe(id) != "", "%s: says what it does" % id)
		check(Gear.price(Gear.item_id(kind, 4)) > Gear.price(Gear.item_id(kind, 0)), "%s: A costs more than E" % kind)
	var e: Dictionary = Gear.effects("gear:bronze_plating:0")
	var a: Dictionary = Gear.effects("gear:bronze_plating:4")
	check(a["max_hp"] > e["max_hp"], "quality scales effects")
	check(Gear.weapon_stats("gear:rail_rifle:4")["damage"] > Gear.weapon_stats("gear:rail_rifle:0")["damage"], "and weapon damage")
	check(Gear.parse("gear:nonsense:2").is_empty() and not Items.exists("gear:nonsense:2"), "unknown gear isn't an item")
	# It stacks and takes slots like any item.
	var inv := {}
	Inventory.add(inv, "gear:scope:2", 3, 12)
	check_eq(Inventory.slots_used(inv), 1, "gear stacks in a slot")


func test_loadout_equip() -> void:
	var player := {}
	var lo := Gear.loadout(player)
	check_eq(lo["weapon"], "gear:laser_rifle:0", "a new automaton has the standard rifle")
	var inv := {"gear:bronze_plating:1": 1, "gear:plasma_rifle:2": 1, "gear:scope:0": 2, "gear:servo_core:0": 1}
	check(not Gear.equip(lo, inv, 12, "gear:bronze_plating:1", "core"), "armour doesn't go in the core slot")
	check(Gear.equip(lo, inv, 12, "gear:bronze_plating:1", "armour"), "it goes in the armour slot")
	check(not inv.has("gear:bronze_plating:1") and lo["armour"] == "gear:bronze_plating:1", "out of the inventory, into the loadout")
	check(Gear.equip(lo, inv, 12, "gear:plasma_rifle:2", "weapon"), "a new weapon")
	check_eq(int(inv.get("gear:laser_rifle:0", 0)), 1, "the old rifle back in the inventory")
	check_eq(Gear.slot_for(lo, "gear:scope:0"), "mod1", "a mod: the first free mod slot")
	Gear.equip(lo, inv, 12, "gear:scope:0", "mod1")
	check_eq(Gear.slot_for(lo, "gear:scope:0"), "mod2", "then the second")
	check(Gear.unequip(lo, inv, 12, "armour") and not lo.has("armour") and int(inv["gear:bronze_plating:1"]) == 1, "taken off: back into the inventory")
	check(Gear.unequip(lo, inv, 12, "weapon") and lo["weapon"] == "gear:laser_rifle:0", "the weapon slot falls back on the standard rifle")
	check(not Gear.unequip(lo, inv, 12, "weapon"), "which stays")
	# No room for what comes off: nothing changes.
	var full := {}
	for k in 12:
		full["scrap_%d" % k] = 1
	full.clear()
	for k in 12:
		Inventory.add(full, "gear:scope:%d" % mini(k, 4), 100, 12)
	var lo2 := {"weapon": "gear:laser_rifle:0", "armour": "gear:bronze_plating:0"}
	check(not Gear.unequip(lo2, full, 12, "armour"), "no room in the inventory: it stays on")


func test_automaton_stats() -> void:
	var p: Node2D = PROPS.Pilot.new()
	var player := {"loadout": {"weapon": "gear:rail_rifle:0", "mod1": "gear:amplifier:4", "armour": "gear:ceramic_carapace:4",
		"core": "gear:servo_core:0", "passive1": "gear:reinforced_frame:2"}}
	p.apply_gear(player)
	var w := Gear.weapon_stats("gear:rail_rifle:0")
	check(is_equal_approx(p.damage, w["damage"] * (1.0 + 0.07 * 2.5)), "damage: the rifle's, plus the amplifier (%.1f)" % p.damage)
	check(p.damage_type == "kinetic" and is_equal_approx(p.reach, w["range"]), "the rail rifle: kinetic, its reach")
	check(is_equal_approx(p.max_hp, 100.0 + 10.0 * 2.5 + 9.0 * 1.65), "health: base, armour, frame (%.1f)" % p.max_hp)
	check(p.speed > p.SPEED, "the servo core: faster")
	check(is_equal_approx(p.resists["energy"], 0.06 * 2.5), "energy resistance from the carapace")
	p.hp = 100.0
	p.shield = 0.0   # (the hits reach the automaton itself)
	p.surface_hit(20.0, "energy")
	check(is_equal_approx(p.hp, 100.0 - 20.0 * (1.0 - 0.15)), "an energy hit takes its share off (%.1f left)" % p.hp)
	p.hp = 100.0
	p.shield = 0.0
	p.surface_hit(20.0, "cold")
	check(is_equal_approx(p.hp, 80.0), "cold: no resistance, the full hit")
	# Heat / cold resistance offsets the planet's environment.
	var bare: Node2D = PROPS.Pilot.new()
	bare.apply_gear({}, Planets.environment("akrotiri"))
	check(is_equal_approx(bare.regen_mult, 0.5), "Akrotiri bare: half healing")
	var lined: Node2D = PROPS.Pilot.new()
	lined.apply_gear({"loadout": {"weapon": "gear:laser_rifle:0", "passive1": "gear:heat_sink:4", "armour": "gear:insulated_shell:4"}}, Planets.environment("akrotiri"))
	check(lined.regen_mult > 0.6, "heat resistance: healing less hindered (%.2f)" % lined.regen_mult)
	var cold: Node2D = PROPS.Pilot.new()
	cold.apply_gear({"loadout": {"weapon": "gear:laser_rifle:0", "passive1": "gear:thermal_lining:4"}}, Planets.environment("krystallos"))
	check(cold.speed > cold.SPEED * 0.8, "cold resistance: the ice slows you less (%.0f)" % cold.speed)
	for n in [p, bare, lined, cold]:
		n.free()


func test_surface_equips_and_drops() -> void:
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	var pl: Dictionary = s.state["player"]
	var inv: Dictionary = s.carried()
	inv["gear:bronze_plating:4"] = 1
	var hp0: float = s.pilot.max_hp
	check(Gear.equip(Gear.loadout(pl), inv, Inventory.PLAYER_SLOTS, "gear:bronze_plating:4", "armour"), "equipped on the planet")
	s.refresh_gear()
	check(s.pilot.max_hp > hp0, "your health follows at once (%.0f -> %.0f)" % [hp0, s.pilot.max_hp])
	# Gear from containers and pirates (their odds), and the loot rolls.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var q_low := 0.0
	var q_high := 0.0
	for k in 400:
		var a := Gear.roll(rng, "foot", 0.0)
		var b := Gear.roll(rng, "ship", 1.0)
		check(Gear.side(a) == "foot" and Gear.side(b) == "ship", "rolls give the side asked for")
		q_low += Gear.quality(a)
		q_high += Gear.quality(b)
	check(q_high > q_low * 2.0, "tougher sources, better quality (avg %.2f vs %.2f)" % [q_high / 400.0, q_low / 400.0])
	check(s.CONTAINER_GEAR_CHANCE["vault"] > s.CONTAINER_GEAR_CHANCE["chest"], "vaults hold gear most often")
	s.queue_free()
	await tree.process_frame


func test_ship_gear_and_resistance() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	for i in 30:
		await tree.process_frame
	var data: Node = main.player_data
	var ship: Node2D = main.ship
	data.modules.clear()
	data.items["gear:heat_shield:4"] = 1
	check(Gear.fit(data, "gear:heat_shield:4"), "ship gear fits from the hold")
	data.changed.emit()
	check(data.count("gear:heat_shield:4") == 0 and data.modules[-1]["id"] == "heat_shield", "out of the hold, onto the ship")
	check(is_equal_approx(ship.resistance("heat"), 0.07 * 2.5), "heat resistance %.3f" % ship.resistance("heat"))
	ship.shields = 0.0
	ship.hull = 100.0
	data.condition.clear()
	ship.take_damage(40.0, ship.global_position, null, "heat")
	check(is_equal_approx(ship.hull, 100.0 - 40.0 * (1.0 - 0.175)), "a heat hit takes its share off (hull %.1f)" % ship.hull)
	ship.hull = 100.0
	data.condition.clear()   # (the heat hit may have damaged a part - plating that lets more through)
	ship.take_damage(40.0, ship.global_position, null, "kinetic")
	check(is_equal_approx(ship.hull, 60.0), "kinetic: the full hit")
	check(Gear.unfit(data, data.modules.size() - 1) and data.count("gear:heat_shield:4") == 1, "taken out: back into the hold")
	# Saved: the loadout and gear in the hold.
	data.loadout["armour"] = "gear:blast_harness:3"
	var back: Node = preload("res://scripts/player_data.gd").new()
	back.load_save_data(JSON.parse_string(JSON.stringify(data.get_save_data())))
	check_eq(back.loadout.get("armour", ""), "gear:blast_harness:3", "the loadout is saved")
	check_eq(back.count("gear:heat_shield:4"), 1, "and gear in the hold")
	back.free()
	main.queue_free()
	await tree.process_frame
	Galaxy.new_game(false)
