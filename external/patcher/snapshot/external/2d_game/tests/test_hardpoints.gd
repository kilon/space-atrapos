extends TestCase
## Sized weapons and hardpoints (Hardpoints): a class's hardpoints (XS to XXL,
## up to 24 on a dreadnought), weapons as items in sizes that fit a hardpoint
## their size or bigger, all of them firing together (a kind switched off on
## the toolbar holds fire), older saves' weapons fitted, NPC ships' loadouts
## at their old damage a second, capital ships leading big fleets.

var _main: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}


func test_sizes_and_layouts() -> void:
	check_eq(Hardpoints.LAYOUT["dreadnought"].size(), 24, "a dreadnought: 24 hardpoints")
	check(Hardpoints.LAYOUT["dreadnought"].max() == 5 and Hardpoints.LAYOUT["interceptor"].max() == 0, "XXL on a dreadnought, XS on an interceptor")
	for cls in Hardpoints.LAYOUT:
		var lay: Array = Hardpoints.LAYOUT[cls]
		check(lay.size() <= 24, "%s: no more than 24" % cls)
		var sorted := lay.duplicate()
		sorted.sort()
		sorted.reverse()
		check(sorted == lay, "%s: biggest first" % cls)
		if cls != "player":
			check_eq(int(Shipyard.CLASS_SLOTS[cls][0]), lay.size(), "%s: the shipyard counts the same hardpoints" % cls)
	var s := Hardpoints.stats("wpn:plasma_cannon:1")
	var l := Hardpoints.stats("wpn:plasma_cannon:3")
	check(is_equal_approx(float(s["damage"]), float(Items.WEAPONS["plasma_cannon"]["damage"])), "size S: the catalogue's numbers")
	check(float(l["damage"]) > float(s["damage"]) * 2.5 and float(l["range"]) > float(s["range"]) and float(l["interval"]) > float(s["interval"]),
		"size L: much harder, further, a little slower")
	check(Hardpoints.price("wpn:plasma_cannon:3") > Hardpoints.price("wpn:plasma_cannon:1") * 5, "and dearer")
	check(Hardpoints.fits("wpn:laser:2", 3) and Hardpoints.fits("wpn:laser:2", 2) and not Hardpoints.fits("wpn:laser:2", 1), "fits its size or bigger")
	check(Hardpoints.parse("wpn:nothing:2").is_empty() and Hardpoints.parse("laser").is_empty(), "only real weapon items")
	check(Items.exists("wpn:beam:4") and Items.display_name("wpn:beam:4") == "Beam Emitter XL", "an item like any other")
	for k in Hardpoints.KINDS:
		check(Hardpoints.MADE_IN.has(k) and Shipyard.HARDPOINT_GEAR.has(k), "%s comes in sizes" % k)


func test_fitting_and_saves() -> void:
	var pd: Node = preload("res://scripts/player_data.gd").new()
	tree.root.add_child(pd)
	check_eq(pd.weapons, ["wpn:laser:1", "", ""], "the Atrapos starts with a Pulse Cannon S")
	check(pd.has_equipment("laser"), "the laser counts as fitted")
	pd.add_item("wpn:plasma_cannon:0", 1)
	check(Hardpoints.fit(pd, "wpn:plasma_cannon:0"), "an XS plasma cannon onto an XS hardpoint")
	check(not Hardpoints.fit(pd, "wpn:laser:2"), "an M one fits none of them")
	check(Hardpoints.unfit(pd, 1) and pd.count("wpn:plasma_cannon:0") == 1 and pd.weapons[1] == "", "taken out into the hold")
	# A bigger ship: what fits goes on, biggest first.
	pd.weapons = ["wpn:laser:1", "wpn:plasma_cannon:0", "wpn:missile_launcher:0"]
	var old: Array = pd.weapons.duplicate()
	pd.ship_class = ShipDesigns.pick("athens", ["frigate"])
	Hardpoints.refit(pd, old)
	check_eq(pd.weapons.size(), 10, "a frigate's ten hardpoints")
	check_eq(pd.weapons.filter(func(w): return w != "").size(), 3, "all three weapons moved over")
	# An older save: weapon kinds owned ("equipment"), fitted at their best size.
	var saved: Dictionary = pd.get_save_data()
	saved.erase("weapons")
	saved["ship_class"] = "player"
	saved["equipment"] = ["laser", "plasma_cannon", "afterburner"]
	pd.load_save_data(JSON.parse_string(JSON.stringify(saved)))
	check(pd.has_equipment("laser") and pd.has_equipment("plasma_cannon"), "an older save's weapons are fitted (%s)" % str(pd.weapons))
	check(pd.has_equipment("afterburner") and not pd.equipment.has("plasma_cannon"), "systems stay equipment, weapons don't")
	var again: Dictionary = JSON.parse_string(JSON.stringify(pd.get_save_data()))
	pd.load_save_data(again)
	check(pd.has_equipment("plasma_cannon"), "and saved as weapons from then on")
	pd.free()


func _projectiles_from(ship: Node2D) -> int:
	return tree.get_nodes_in_group("fx_layer")[0].get_children().filter(func(p): return p is Projectile and p.shooter == ship).size() \
		if not tree.get_nodes_in_group("fx_layer").is_empty() else 0


func test_all_weapons_fire_together() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	var ship: Node2D = _main.ship
	ship.invulnerable = true
	var pd: Node = _main.player_data
	pd.weapons = ["wpn:laser:1", "wpn:plasma_cannon:0", "wpn:laser:0"]
	var e: Node2D = _main.spawn_enemy(ship.global_position + Vector2(0, -300))
	e.max_hull = 1e9
	e.hull = 1e9
	await tree.process_frame
	ship.set_attack_target(e)
	var styles := {}
	var mounts := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await tree.process_frame
		for p in tree.get_nodes_in_group("fx_layer")[0].get_children():
			if p is Projectile and p.shooter == ship:
				styles[p.style] = true
	check(styles.has("laser") and styles.has("plasma"), "the lasers and the plasma cannon all fire (%s)" % str(styles.keys()))
	check(ship.mount(0) != ship.mount(1), "each from its own hardpoint")
	# The plasma cannons switched off: they hold fire.
	ship.select_weapon("plasma_cannon")
	check(not ship.weapon_on("plasma_cannon"), "switched off on the toolbar")
	await tree.process_frame
	var plasma := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await tree.process_frame
		for p in tree.get_nodes_in_group("fx_layer")[0].get_children():
			if p is Projectile and p.shooter == ship and p.style == "plasma" and p.get_meta("seen", false) == false:
				p.set_meta("seen", true)
				if Time.get_ticks_msec() - t0 > 200:
					plasma = true
	check(not plasma, "no plasma while it's off")
	ship.select_weapon("plasma_cannon")
	check(ship.weapon_on("plasma_cannon"), "and back on")


func test_npc_loadouts_and_capitals() -> void:
	# A loadout fills the class's hardpoints (a civilian half of them), sizes in range.
	var dread := ShipDesigns.pick("sparta", ["dreadnought"])
	check(dread != "" and EnemyTypes.get_type(dread).get("capital", false), "Sparta has a dreadnought (%s)" % dread)
	var lo := Hardpoints.loadout(dread, "patrol", 7)
	check_eq(lo.size(), 24, "a dreadnought's 24 guns")
	for i in lo.size():
		check(Hardpoints.size_of(lo[i]) <= int(Hardpoints.LAYOUT["dreadnought"][i]), "each fits its hardpoint")
	check_eq(Hardpoints.loadout(ShipDesigns.pick("athens", ["freighter"]), "trader", 3).size(), 1, "a freighter trader: half its two")
	check(Shipyard.stats(dread)["price"] > Shipyard.stats(ShipDesigns.pick("sparta", ["frigate"]))["price"] * 2, "a dreadnought costs a fortune")
	check(Shipyard.for_sale("sparta").has(dread), "and the Spartan yards sell one")
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	_main.ship.invulnerable = true
	var e: Node2D = null
	for attempt in 20:   # (a warship may draw an Electro or a Bouncer instead of a loadout - Enemy ELECTRO_CHANCE: another)
		e = _main.spawn_ship(_main.ship.global_position + Vector2(2000, 0), dread, {}, "sparta")
		if not (e.electro or e.bouncer):
			break
		e.queue_free()
	await tree.process_frame
	check_eq(e.loadout.size(), 24, "a spawned dreadnought carries its loadout")
	# Its damage a second: its type's, spread over its batteries.
	var t := EnemyTypes.get_type(dread)
	var want := float(t["damage"]) * float(t["shots"]) / float(t["fire_interval"])
	var dps := 0.0
	for b in e._batteries:
		dps += float(b["dmg"]) * int(b["n"]) / float(b["iv"])
	check(absf(dps - want) < want * 0.02, "its damage a second as designed (%.0f / %.0f)" % [dps, want])
	var shots := 0
	for b in e._batteries:
		shots += int(b["n"])
	check(shots <= e._batteries.size() * int(e.MAX_VOLLEY), "a few bolts a volley, not 24 at once")
	# Saved with it.
	var back: Dictionary = JSON.parse_string(JSON.stringify(e.get_save_data()))
	check_eq(Array(back["loadout"]).size(), 24, "its loadout is saved")
	# A full fleet flies under a dreadnought.
	check(EnemyTypes.get_type(ShipDesigns.flagship("sparta", 12)).get("class", "") == "dreadnought", "12 ships: a dreadnought flagship")
	check(EnemyTypes.get_type(ShipDesigns.flagship("sparta", 7)).get("class", "") == "cruiser", "7: a cruiser")
	check_eq(ShipDesigns.flagship("sparta", 4), "", "4: none")
