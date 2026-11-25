extends TestCase
## The toolbars (Inventory.toolbar_*, ToolbarUse, the HUD's Toolbar): the
## automaton's starts with its four tools (rifle, beam, digger, scanner), anything usable is dragged onto them - gear
## equipped or not, the automaton's tools, supplies, the ship's weapons,
## systems and fittings - slots swap, dragged off they empty, they're saved,
## and a slot pressed does what's on it.


func _data() -> Node:
	var pd: Node = load("res://scripts/sim/player_data.gd").new()
	return pd


func test_new_game_foot_toolbar_tools_old_saves_keep_theirs() -> void:
	var pd := _data()
	check_eq(pd.toolbar_foot.size(), Inventory.TOOLBAR_SLOTS, "nine slots on foot")
	check_eq(pd.toolbar_foot.slice(0, 6), ["tool:rifle", "tool:beam", "tool:digger", "tool:scanner", "tool:build", ""], "a new game: the automaton's tools on 1-5, in order")
	check(pd.toolbar.has("laser"), "the ship's toolbar: its weapons as before")
	# Filled, saved and loaded: kept.
	pd.toolbar_foot[2] = "tool:digger"
	pd.toolbar_foot[4] = "energy_drink"
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pd.get_save_data()))
	var pd2 := _data()
	pd2.load_save_data(saved)
	check_eq(pd2.toolbar_foot[2], "tool:digger", "saved: the digger's slot")
	check_eq(pd2.toolbar_foot[4], "energy_drink", "saved: the drinks' slot")
	# An older save's bar: kept, its "rifle" the rifle tool.
	saved["toolbar_foot"] = ["rifle", "medicine", "energy_cell", "", "", "", "", "", ""]
	pd2.load_save_data(saved)
	check_eq(pd2.toolbar_foot[0], Inventory.TOOL_RIFLE, "an older save's rifle: the rifle tool")
	check_eq(pd2.toolbar_foot[1], "medicine", "an older save keeps its bar")
	saved.erase("toolbar_foot")
	pd2.load_save_data(saved)
	check_eq(pd2.toolbar_foot[0], "tool:rifle", "no bar saved: a new game's")
	pd.free()
	pd2.free()


func test_drag_every_kind_onto_the_toolbars() -> void:
	var foot: Array = Inventory.FOOT_TOOLBAR.duplicate()
	var rifle := str(Gear.DEFAULT_LOADOUT["weapon"])
	var plate := Gear.item_id("bronze_plating", 1)
	# On foot: a tool, equipped gear (from the loadout), gear in the hold, a drink, medicine, food, a skill.
	check(Inventory.toolbar_drop(foot, 0, {"src": "tool", "id": "tool:scanner"}, true), "a tool")
	check(Inventory.toolbar_drop(foot, 1, {"src": "loadout", "slot": "weapon", "id": rifle}, true), "equipped gear: the rifle")
	check(Inventory.toolbar_drop(foot, 2, {"src": "hold", "id": plate}, true), "gear not equipped")
	check(Inventory.toolbar_drop(foot, 3, {"src": "carried", "id": "energy_drink"}, true), "a consumable")
	check(Inventory.toolbar_drop(foot, 4, {"src": "hold", "id": "medicine"}, true), "medicine")
	check(Inventory.toolbar_drop(foot, 5, {"src": "hold", "id": "food"}, true), "food")
	check(Inventory.toolbar_drop(foot, 6, {"src": "skill", "id": "skill:pygmachia"}, true), "a skill")
	check_eq(Inventory.toolbar_kind("tool:scanner", true), "tool", "kind: tool")
	check_eq(Inventory.toolbar_kind(plate, true), "gear", "kind: gear")
	check_eq(Inventory.toolbar_kind("energy_drink", true), "consumable", "kind: consumable")
	# What does nothing there: refused.
	check(not Inventory.toolbar_drop(foot, 7, {"src": "hold", "id": "iron_ore"}, true), "ore: not on a toolbar")
	check(not Inventory.toolbar_drop(foot, 7, {"src": "gear", "id": "laser"}, true), "a ship's weapon: not on foot")
	check(not Inventory.toolbar_drop(foot, 7, {"src": "hold", "id": Gear.item_id(Shipyard.MODULES.keys()[0], 0)}, true), "ship gear: not on foot")
	check_eq(foot[7], "", "slot 8 still empty")
	# Swap two slots; one slot a thing (dropped again: it moves).
	check(Inventory.toolbar_drop(foot, 8, {"src": "toolbar", "which": "foot", "index": 0, "id": "tool:scanner"}, true), "a slot onto another")
	check(foot[8] == "tool:scanner" and foot[0] == "", "they swap (onto an empty one: it moves)")
	Inventory.toolbar_drop(foot, 0, {"src": "carried", "id": "energy_drink"}, true)
	check(foot[0] == "energy_drink" and not foot.slice(1).has("energy_drink"), "the same thing again: it moves, not copied")
	# Dragged off: emptied.
	Inventory.toolbar_clear(foot, 8)
	check_eq(foot[8], "", "dragged off the bar: emptied")
	# In the ship: weapon kinds, systems, a weapon and ship gear from the hold, fuel - not a drink.
	var bar: Array = ["", "", "", "", "", "", "", "", ""]
	var wpn := Hardpoints.item_id("plasma_cannon", 1)
	var mod := Gear.item_id(Shipyard.MODULES.keys()[0], 0)
	check(Inventory.toolbar_drop(bar, 0, {"src": "gear", "id": "laser"}, false), "a weapon kind")
	check(Inventory.toolbar_drop(bar, 1, {"src": "gear", "id": "shield_booster"}, false), "a system")
	check(Inventory.toolbar_drop(bar, 2, {"src": "hold", "id": wpn}, false), "a weapon in the hold")
	check(Inventory.toolbar_drop(bar, 3, {"src": "hold", "id": mod}, false), "ship gear in the hold")
	check(Inventory.toolbar_drop(bar, 4, {"src": "hold", "id": "fuel"}, false), "fuel")
	check(not Inventory.toolbar_drop(bar, 5, {"src": "hold", "id": "energy_drink"}, false), "a drink: not in the ship")
	check(not Inventory.toolbar_drop(bar, 5, {"src": "tool", "id": "tool:digger"}, false), "the digger: not in the ship")
	# From the other bar: what it can hold, copied over.
	check(Inventory.toolbar_drop(foot, 7, {"src": "toolbar", "which": "ship", "index": 4, "id": "fuel"}, true) == Inventory.foot_usable("fuel"), "from the ship's bar: what it can hold there")
	check(not Inventory.toolbar_accepts({"src": "toolbar", "which": "ship", "index": 2, "id": wpn}, true), "a ship weapon from the ship's bar: not on foot")


func test_counts_and_equipped() -> void:
	var pd := _data()
	var plate := Gear.item_id("bronze_plating", 2)
	pd.items["medicine"] = 3
	pd.carried["medicine"] = 2
	pd.items["fuel"] = 4
	pd.items[plate] = 1
	check_eq(Inventory.toolbar_count(pd, "medicine", true), 5, "on foot: carried + the hold")
	check_eq(Inventory.toolbar_count(pd, "fuel", false), 4, "in the ship: the hold")
	check_eq(Inventory.toolbar_count(pd, plate, true), 1, "gear not equipped: how many")
	check_eq(Inventory.toolbar_count(pd, "tool:digger", true), -1, "a tool: no count")
	check(Inventory.toolbar_equipped(pd, str(Gear.DEFAULT_LOADOUT["weapon"]), true), "the loadout's rifle: equipped")
	check(not Inventory.toolbar_equipped(pd, plate, true), "the plating: not yet")
	pd.free()


func test_pressing_a_slot_uses_it() -> void:
	var pd := _data()
	var plate := Gear.item_id("bronze_plating", 2)
	var carbine := Gear.item_id("pulse_carbine", 0)
	pd.carried[plate] = 1
	pd.items[carbine] = 1
	# Gear not equipped: pressed, equipped (from what you carry, or the hold).
	ToolbarUse.use(null, pd, plate, true)
	check_eq(str(pd.loadout.get("armour", "")), plate, "the plating equipped")
	check(not pd.carried.has(plate), "out of what you carry")
	ToolbarUse.use(null, pd, carbine, true)
	check_eq(str(pd.loadout.get("weapon", "")), carbine, "the carbine in the weapon slot")
	check_eq(int(pd.items.get(Gear.DEFAULT_LOADOUT["weapon"], 0)), 1, "the old rifle back in the hold")
	check(Inventory.toolbar_equipped(pd, carbine, true), "the slot lit: equipped")
	# A drink: stamina back, one used.
	pd.stamina = 10.0
	pd.carried["energy_drink"] = 2
	ToolbarUse.use(null, pd, "energy_drink", true)
	check(pd.stamina > 60.0 and int(pd.carried["energy_drink"]) == 1, "an energy drink: stamina back, one used")
	pd.stamina = Stamina.MAX
	ToolbarUse.use(null, pd, "energy_drink", true)
	check_eq(int(pd.carried["energy_drink"]), 1, "full: none wasted")
	# A weapon kind: switched off and on.
	ToolbarUse.use(null, pd, "laser", false)
	check(pd.weapons_off.has("laser"), "the pulse cannons off")
	ToolbarUse.use(null, pd, "laser", false)
	check(not pd.weapons_off.has("laser"), "and on again")
	# A weapon in the hold: fitted.
	var wpn := Hardpoints.item_id("plasma_cannon", 0)
	pd.items[wpn] = 1
	ToolbarUse.use(null, pd, wpn, false)
	check(Hardpoints.has_kind(pd, "plasma_cannon") and pd.count(wpn) == 0, "a weapon from the hold fitted to a hardpoint")
	# Fuel: a unit pumped.
	pd.fuel = 1.0
	pd.items["fuel"] = 2
	ToolbarUse.use(null, pd, "fuel", false)
	check(pd.fuel > 1.0 and pd.count("fuel") == 1, "fuel pumped into the tank")
	pd.free()


func test_hud_toolbar_on_foot() -> void:
	var old_system := Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""
	Galaxy.current_system = "atrapos"
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	c.dry_run = true
	var bar: Control = c.hud2d.toolbar
	var data: Node = CosmosGame.data
	await tree.process_frame
	check(not bar.foot and bar.bar() == data.toolbar, "in the ship: the ship's bar")
	# On foot.
	var gi := -1
	for i in c.planets.size():
		if c.planets[i].shape.kind != "gas":
			gi = i
			break
	c.warp_to(gi, 40.0, 0.0, 0.0, c.land_up(gi))
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	t0 = Time.get_ticks_msec()
	while not bar.foot and Time.get_ticks_msec() - t0 < 3000:
		await tree.process_frame
	check(bar.foot and bar.bar() == data.toolbar_foot, "on foot: the automaton's bar")
	t0 = Time.get_ticks_msec()
	while c.deposits == null and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame
	data.toolbar_foot[0] = "tool:digger"
	data.toolbar_foot[1] = Inventory.TOOL_RIFLE
	data.toolbar_foot[2] = "medicine"
	check_eq(str(bar.slot_at(0).get("type", "")), "tool", "slot 1: a tool")
	check(c.deposits != null, "the deposits (the digger) on the ground")
	if c.deposits:
		c.deposits.digger = false
		bar.press(0)
		check(c.deposits.digger, "pressed: the terrain digger out")
		bar.press(1)
		check(not c.deposits.digger, "the rifle's slot: the rifle back")
	data.items["medicine"] = 2
	c.walker.hp = 30.0
	bar.press(2)
	check(c.walker.hp > 60.0 and data.count("medicine") == 1, "medicine on foot: the automaton healed")
	c.queue_free()
	await tree.process_frame
	Galaxy.current_system = old_system
