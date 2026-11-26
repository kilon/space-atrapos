extends TestCase
## Slot inventories (Inventory): up to 100 of an item per slot; you carry 12
## slots on foot, a ship's hold has its class's slots (12 - 120); both toolbars
## have 9 slots you fill; at your ship on a planet you move stacks across
## (TransferPanel).

var _old_planet := ""

func setup() -> void:
	_old_planet = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old_planet


func test_stacks_and_slots() -> void:
	var inv := {}
	check_eq(Inventory.add(inv, "iron_ore", 250, 12), 250, "250 ore go in")
	check_eq(Inventory.slots_used(inv), 3, "in 3 slots (100 + 100 + 50)")
	check_eq(Inventory.stacks(inv), [["iron_ore", 100], ["iron_ore", 100], ["iron_ore", 50]], "drawn as three stacks")
	check_eq(Inventory.room_for(inv, "iron_ore", 3), 50, "a full set of slots still tops up its last stack")
	check_eq(Inventory.room_for(inv, "scrap", 3), 0, "but nothing new fits")
	check_eq(Inventory.add(inv, "scrap", 10, 3), 0, "so no scrap")
	check_eq(Inventory.add(inv, "scrap", 10, 4), 10, "a fourth slot: scrap")
	var other := {}
	check_eq(Inventory.move_stack(inv, other, "iron_ore", 12), 50, "moving a stack: the partial one first")
	check_eq(Inventory.move_stack(inv, other, "iron_ore", 12), 100, "then a full one")
	check_eq(int(inv["iron_ore"]), 100, "100 left")
	check_eq(Inventory.move_stack(inv, {"a": 0}, "nothing", 1), 0, "nothing to move")


func test_ship_holds_by_class() -> void:
	var pd: Node = preload("res://scripts/player_data.gd").new()
	pd.ship_class = "player"
	check_eq(Shipyard.cargo_capacity(pd), Shipyard.STARTER_HOLD, "the starter ship's hold (%d slots)" % Shipyard.STARTER_HOLD)
	for cls in Shipyard.CLASS_HOLD:
		var n: int = Shipyard.CLASS_HOLD[cls]
		check(n >= Inventory.PLAYER_SLOTS and n <= Inventory.SHIP_SLOTS, "%s: %d slots, between 12 and 120" % [cls, n])
	check_eq(Shipyard.CLASS_HOLD["freighter"], Inventory.SHIP_SLOTS, "the freighter has the most (120)")
	check(Shipyard.CLASS_HOLD["interceptor"] < Shipyard.CLASS_HOLD["frigate"], "small ships have far fewer slots")
	check_eq(pd.cargo_free(), (Shipyard.STARTER_HOLD - pd.START_ITEMS.size()) * Inventory.STACK, "room: empty slots' worth (the repair kits and energy drinks take one each)")
	pd.free()


func test_toolbars_and_carried_are_saved() -> void:
	var pd: Node = preload("res://scripts/player_data.gd").new()
	check_eq(pd.toolbar.size(), 9, "9 ship toolbar slots")
	check_eq(pd.toolbar_foot.size(), 9, "9 on foot")
	pd.toolbar[8] = "repair_kit"
	pd.toolbar[5] = ""
	pd.carried = {"medicine": 3}
	var back: Node = preload("res://scripts/player_data.gd").new()
	back.load_save_data(JSON.parse_string(JSON.stringify(pd.get_save_data())))
	check(back.toolbar[8] == "repair_kit" and back.toolbar[5] == "", "your toolbar layout is saved")
	check_eq(int(back.carried.get("medicine", 0)), 3, "and what you carry")
	# An older save: a pack and a 6-slot toolbar.
	var old: Node = preload("res://scripts/player_data.gd").new()
	old.load_save_data({"credits": 10, "items": {}, "pack": {"iron_ore": 5}, "toolbar": ["laser"]})
	check_eq(int(old.carried.get("iron_ore", 0)), 5, "an old pack: now carried")
	check_eq(old.toolbar.size(), 9, "toolbars always 9 slots")
	pd.free()
	back.free()
	old.free()


func test_transfer_at_the_ship() -> void:
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.set_process(false)
	var pl: Dictionary = s.state["player"]
	pl["carried"] = {}
	pl["items"] = {"repair_kit": 2}
	check_eq(s._give("iron_ore", 150), 0, "you pick up 150 ore")
	check_eq(int(s.carried()["iron_ore"]), 150, "you carry it (2 slots)")
	check_eq(int(pl["items"].get("iron_ore", 0)), 0, "not the ship")
	# Full: 12 slots.
	s._give("scrap", Inventory.PLAYER_SLOTS * Inventory.STACK)
	check_eq(Inventory.slots_used(s.carried()), Inventory.PLAYER_SLOTS, "your 12 slots fill")
	check(s._give("medicine", 1) == 1, "nothing more fits")
	# At the ship: move stacks across.
	s.board_ship()
	await tree.process_frame
	var t: TransferPanel = null
	for c in s.get_children():
		if c is TransferPanel:
			t = c
	check(t != null and tree.paused, "clicking your ship: the transfer screen (the game waits)")
	if t:
		t._to_you("repair_kit")
		check_eq(int(s.carried().get("repair_kit", 0)), 0, "your slots are full: nothing comes from the ship")
		t._to_ship("iron_ore")
		check_eq(int(pl["items"].get("iron_ore", 0)), 50, "a stack into the hold (the partial one: a slot freed)")
		t._to_you("repair_kit")
		check_eq(int(s.carried().get("repair_kit", 0)), 2, "now you can take the repair kits")
		t.close()
		check(not tree.paused, "closed: the game goes on")
	s.queue_free()
	await tree.process_frame


## Drag and drop: inventory slots keep where you put things (a layout, saved);
## toolbar slots swap; something usable dragged onto a toolbar slot goes there.
func test_drag_and_drop() -> void:
	var inv := {"iron_ore": 150, "scrap": 5}
	var lay := []
	var s := Inventory.slots(inv, lay, 12)
	check_eq(s.slice(0, 4), [["iron_ore", 100], ["iron_ore", 50], ["scrap", 5], []], "laid out in name order at first")
	Inventory.swap(lay, 2, 7)   # (scrap dragged to slot 8)
	s = Inventory.slots(inv, lay, 12)
	check(s[2].is_empty() and s[7] == ["scrap", 5], "dragged: the scrap stays in slot 8")
	inv["medicine"] = 3
	s = Inventory.slots(inv, lay, 12)
	check_eq(s[2], ["medicine", 3], "something new goes to the first empty slot")
	Inventory.swap(lay, 0, 7)
	s = Inventory.slots(inv, lay, 12)
	check(s[0] == ["scrap", 5] and s[7][0] == "iron_ore", "two slots swap")
	inv.erase("scrap")
	s = Inventory.slots(inv, lay, 12)
	check(s[0].is_empty(), "gone: its slot empties")
	# Into a given slot of another inventory.
	var other := {}
	var olay := []
	Inventory.slots(other, olay, 12)
	Inventory.move_stack_into(inv, other, "medicine", 12, olay, 5)
	check_eq(Inventory.slots(other, olay, 12)[5], ["medicine", 3], "dropped across: into that slot")
	# Toolbars.
	var bar: Array = Inventory.SHIP_TOOLBAR.duplicate()
	check(Inventory.toolbar_drop(bar, 7, {"src": "toolbar", "which": "ship", "index": 0, "id": "laser"}, false), "a toolbar slot dragged onto another")
	check(bar[7] == "laser" and bar[0] == "", "they swap (the laser to 8, the empty slot to 1)")
	check(Inventory.toolbar_drop(bar, 0, {"src": "hold", "id": "repair_kit"}, false), "repair kits dragged from the hold")
	check(bar[0] == "repair_kit" and not bar.slice(1).has("repair_kit"), "go to that slot (and leave their old one)")
	check(not Inventory.toolbar_accepts({"src": "hold", "id": "iron_ore"}, false), "ore can't go on the toolbar")
	check(not Inventory.toolbar_accepts({"src": "toolbar", "which": "foot", "index": 0, "id": "rifle"}, false), "nor the foot toolbar's slots")
	var foot: Array = Inventory.FOOT_TOOLBAR.duplicate()
	check(Inventory.toolbar_drop(foot, 8, {"src": "gear", "id": "rifle"}, true) and foot[8] == "rifle" and foot[0] == "", "on foot: the rifle dragged to 9")
	# A slot's drag carries its payload; a drop calls its handler.
	var slot := ItemSlot.make("scrap", 5)
	slot.payload = {"src": "hold", "index": 3, "id": "scrap"}
	var got := []
	slot.on_drop = func(d): got.append(d)
	slot.accepts = func(d): return d.get("src") == "hold"
	tree.root.add_child(slot)
	check(slot._can_drop_data(Vector2.ZERO, {"src": "hold", "index": 1, "id": "x"}), "a slot takes what it accepts")
	check(not slot._can_drop_data(Vector2.ZERO, {"src": "toolbar"}), "and not what it doesn't")
	slot._drop_data(Vector2.ZERO, {"src": "hold", "index": 1, "id": "x"})
	check_eq(got.size(), 1, "dropped")
	slot.queue_free()
