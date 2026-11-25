extends TestCase
## The Automaton (Tab): its tabs - Inventory, Map, Archive (no repair bay, no tech
## tree, no industry: refining and making are the ship's own devices, each its
## own window - DeviceMenu); the Inventory page - your inventory, your toolbar
## and the automaton's equipment (no cargo hold, no ship equipment); one
## inventory (an older save's on-foot pack merged in); no research in saves.


func _data() -> Node:
	return load("res://scripts/sim/player_data.gd").new()


func test_tabs_without_tech_or_industry() -> void:
	var M: GDScript = load("res://scripts/ui/ship_menu.gd")
	var tabs: Array = M.TABS
	check(not tabs.has("TECH TREE") and not tabs.has("INDUSTRY"), "no tech tree, no industry tab (%s)" % ", ".join(tabs))
	var shown: Array = M.SHOWN.map(func(i): return tabs[i])
	check_eq(shown, ["INVENTORY", "MAP", "ARCHIVE"], "the tabs you see, 1-3")
	check(not tabs.has("REPAIR"), "no repair bay")
	check(not FileAccess.file_exists("res://scripts/sim/tech.gd") and not FileAccess.file_exists("res://scripts/ui/pages/tech_page.gd"), "the tech tree's gone")


func test_inventory_page_is_yours() -> void:
	var pd := _data()
	pd.add_item("iron_ore", 30)
	pd.add_item("medicine", 2)
	var page: Control = load("res://scripts/ui/pages/inventory_page.gd").new()
	page.data = pd
	tree.root.add_child(page)
	page.refresh()
	var sections: Array = page.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(sections.has("INVENTORY") and sections.has("TOOLBAR"), "INVENTORY and TOOLBAR sections")
	for gone in ["CARGO HOLD", "SHIP  ·  EQUIPMENT", "WEAPONS & SYSTEMS", "YOU CARRY ON FOOT"]:
		check(not sections.has(gone), "no %s" % gone)
	check(page.find_children("*", "EquipDoll", true, false).size() >= 1, "the automaton's equipment screen")
	var slots := page.find_children("*", "", true, false).filter(func(n): return n.get("payload") is Dictionary and n.payload.get("src") == "toolbar")
	check_eq(slots.size(), Inventory.TOOLBAR_SLOTS, "one toolbar: the automaton's nine slots")
	check(slots.all(func(n): return n.payload["which"] == "foot"), "the on-foot toolbar only")
	var held := page.find_children("*", "", true, false).filter(func(n): return n.get("payload") is Dictionary and n.payload.get("src") == "hold")
	check(held.size() >= 2, "your things in the inventory (%d stacks)" % held.size())
	page.queue_free()
	pd.free()


func test_one_inventory_and_no_research_in_saves() -> void:
	var pd := _data()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pd.get_save_data()))
	check(not saved.has("tech"), "no research saved")
	saved["carried"] = {"medicine": 3, "energy_drink": 2}
	saved["tech"] = ["hull_1"]
	var items: Dictionary = saved.get("items", {})
	var before := int(items.get("medicine", 0))
	var pd2 := _data()
	pd2.load_save_data(saved)
	check_eq(pd2.count("medicine"), before + 3, "an older save's pack merged into the inventory")
	check(pd2.carried.is_empty(), "no separate pack")
	check(not "tech" in pd2, "no research kept")
	pd.free()
	pd2.free()


func test_the_ships_devices() -> void:
	var I: GDScript = load("res://scripts/world/player/cosmos_ship_interior.gd")
	var names: Array = I.TERMINALS.map(func(t): return t[0])
	check(not names.has("Tech"), "no Tech terminal aboard")
	for t in I.TERMINALS:
		if t[0] in ["Refinery", "Fabricator"]:
			check(t[1] is String, "%s: a device of its own (%s)" % [t[0], str(t[1])])
	var pd := _data()
	var dm := DeviceMenu.new()
	dm.data = pd
	tree.root.add_child(dm)
	dm.open("refinery")
	check(dm.visible and dm._page.only == [0], "the refinery: its refining only")
	dm.open("fabricator")
	check(dm._page.only == [1, 2], "the fabricator: its recipes and kits")
	check(dm._title.text == "FABRICATOR", "its own window's title")
	dm.queue_free()
	await tree.process_frame
	pd.free()


## The repair system's gone: no repair bay, no repair at stations, no kits,
## spare parts or scanners - an older save's are dropped (and its parts' faults).
func test_no_repair_and_older_saves_load() -> void:
	for f in ["res://scripts/ui/repair_bay.gd", "res://scripts/ui/surgery.gd", "res://scripts/sim/repair_service.gd"]:
		check(not FileAccess.file_exists(f), "gone: " + f.get_file())
	var I: GDScript = load("res://scripts/world/player/cosmos_ship_interior.gd")
	check(not I.TERMINALS.any(func(t): return "Repair" in str(t[0])), "no Repair Bay terminal aboard")
	var S: GDScript = load("res://scripts/ui/station_menu.gd")
	check(not S.TABS.has("REPAIR") and S.TABS[0] == "WORKSHOP", "the station's workshop (upgrades, fuel), no repair")
	for id in ["repair_kit", "spare_servo", "scanner_mk2", "scanner_mk3"]:
		check(not Items.ITEMS.has(id), "no item " + id)
	check(not Shipyard.MODULES.has("nanite_repair"), "no Nanite Repair module")
	var pd := _data()
	check(not pd.items.has("repair_kit"), "a new game: no repair kits")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pd.get_save_data()))
	check(not saved.has("condition"), "no parts' condition saved")
	saved["items"] = {"repair_kit": 3, "spare_cell": 1, "scanner_mk2": 1, "medicine": 2, Gear.item_id("nanite_repair", 1): 1}
	saved["toolbar"] = ["laser", "", "", "", "", "repair_kit", "", "", ""]
	saved["toolbar_foot"] = ["tool:rifle", "repair_kit", "", "", "", "", "", "", ""]
	saved["modules"] = [{"id": "nanite_repair", "rating": 2}]
	saved["condition"] = {"ship": {"engines": {"faults": [{"id": 1, "kind": "crack", "comp": 0, "sev": 0.5}], "off": false}}, "next": 2}
	saved["upgrades"] = {"ship": {"reactor:hull_regen": 3, "engines:speed_mult": 1}}
	saved["industry"] = {"queue": [{"kind": "fab", "id": "repair_kit", "n": 2}, {"kind": "fab", "id": "missile", "n": 1}]}
	var pd2 := _data()
	pd2.load_save_data(saved)
	check_eq(pd2.items.keys(), ["medicine"], "the repair items dropped, the rest kept")
	check(not pd2.toolbar.has("repair_kit") and not pd2.toolbar_foot.has("repair_kit"), "off the toolbars")
	check(pd2.modules.is_empty(), "the Nanite Repair module dropped")
	check(not "condition" in pd2, "no condition kept")
	check_eq(pd2.upgrades["ship"].keys(), ["engines:speed_mult"], "the hull self-repair upgrade dropped")
	check_eq(pd2.industry["queue"].map(func(j): return j["id"]), ["missile"], "a repair kit's fabrication dropped")
	check(pd2.mod("speed_mult") > 0.0, "upgrades still count")
	pd.free()
	pd2.free()
