extends TestCase
## Dying loses one thing you carry (LostItems); a kill of yours has a 10 %
## chance to win a lost thing back, with "ITEM REGAINED" on screen.

func test_dying_loses_one_thing() -> void:
	var p := {"items": {"repair_kit": 2, "phaistos_fragment": 1}, "equipment": ["laser", "plasma_cannon"]}
	var seen := {}
	for roll in [0.0, 0.5, 0.99]:
		var q: Dictionary = p.duplicate(true)
		var name := LostItems.lose_one(q, roll)
		check(name != "", "something is lost (roll %.2f)" % roll)
		check_eq(q["lost"].size(), 1, "and remembered")
		check(q["items"].has("phaistos_fragment"), "never a story item")
		check("laser" in q["equipment"], "never the basic laser")
		seen[name] = true
	check(seen.has("Repair Kit x2") and seen.has("Plasma Cannon"), "an inventory stack or a piece of toolbar equipment (%s)" % [seen.keys()])
	var empty := {"items": {}, "equipment": ["laser"]}
	check_eq(LostItems.lose_one(empty, 0.3), "", "nothing to lose: nothing lost")


func test_a_kill_may_win_it_back() -> void:
	var p := {"items": {"repair_kit": 2}, "equipment": ["laser"]}
	LostItems.lose_one(p, 0.0)
	check(not p["items"].has("repair_kit"), "lost")
	check_eq(LostItems.regain(p, 0.5), "", "90 %: not this time")
	check_eq(LostItems.regain(p, 0.12), "", "(just over the 10 %)")
	check_eq(LostItems.regain(p, 0.05), "Repair Kit x2", "10 %: regained")
	check_eq(int(p["items"]["repair_kit"]), 2, "all of it back")
	check(p["lost"].is_empty(), "and off the lost list")
	check_eq(LostItems.regain(p, 0.0), "", "nothing left to regain")
	# Equipment comes back too.
	var q := {"items": {}, "equipment": ["laser", "afterburner"]}
	LostItems.lose_one(q, 0.0)
	check_eq(LostItems.regain(q, 0.01), "Afterburner", "a piece of equipment regained")
	check("afterburner" in q["equipment"], "back on the toolbar")


func test_player_data_keeps_the_lost_list() -> void:
	var pd: Node = preload("res://scripts/player_data.gd").new()
	tree.root.add_child(pd)
	pd.add_equipment("missile_launcher")
	var wid := "wpn:missile_launcher:0"
	check(pd.has_equipment("missile_launcher") and wid in pd.weapons, "a Missile Launcher XS on a free XS hardpoint")
	var d: Dictionary = pd.get_save_data()
	d["equipment"] = Array(d["equipment"])
	d["weapons"] = Array(d["weapons"])
	LostItems.lose_one(d, 0.99)   # (the missile launcher: sorted after the repair kits)
	pd.load_save_data(JSON.parse_string(JSON.stringify(d)))   # (as saved and loaded)
	check(not pd.has_equipment("missile_launcher"), "lost with the ship")
	check(pd.has_equipment("laser"), "never the small Pulse Cannon")
	check_eq(pd.lost.size(), 1, "the lost list saved and loaded")
	check_eq(pd.regain_lost(0.5), "", "most kills bring nothing back")
	check_eq(pd.regain_lost(0.0), "Missile Launcher XS", "a lucky kill")
	check(pd.count(wid) == 1 and pd.lost.is_empty(), "regained, into the hold")
	pd.free()


## However many times you die, every thing lost stays recoverable - kept in
## the save file - until a kill wins it back.
func test_every_loss_stays_recoverable_in_the_save() -> void:
	var p := {"credits": 150, "items": {"repair_kit": 2, "missile": 5, "medicine": 1},
		"equipment": ["laser", "afterburner", "plasma_cannon"], "tech": []}
	var names := []
	for death in 5:
		names.append(LostItems.lose_one(p, 0.3))
	check_eq(p["lost"].size(), 5, "five deaths, five things on the lost list (%s)" % [names])
	check(not names.has(""), "each death lost something")
	# Saved to disk and loaded back (the real save file).
	SaveGame.save_game({"player": p})
	var back: Dictionary = SaveGame.read_save()["state"]["player"]
	check_eq(back.get("lost", []).size(), 5, "the lost list is in the save file")
	var pd: Node = preload("res://scripts/player_data.gd").new()
	pd.load_save_data(back)
	check_eq(pd.lost.size(), 5, "and loads into the game")
	var won := []
	for k in 5:
		won.append(pd.regain_lost(0.0))
	check(not won.has(""), "every one of them can still be won back (%s)" % [won])
	check(pd.lost.is_empty(), "nothing left to recover")
	check(pd.count("repair_kit") == 2 and pd.count("missile") == 5 and pd.has_equipment("afterburner") and pd.has_equipment("plasma_cannon"),
		"all back, whole stacks")
	pd.free()


func test_regained_popup() -> void:
	var p := RegainPopup.show_item(tree, "Repair Kit x2")
	await tree.process_frame
	check(p.is_inside_tree() and p._box != null, "the pop-up shows")
	var texts := p.find_children("*", "Label", true, false).map(func(l): return l.text)
	check("ITEM REGAINED" in texts, "headed ITEM REGAINED")
	check(texts.any(func(t): return t.contains("Repair Kit x2")), "with the item's name")
	var q := RegainPopup.show_item(tree, "Afterburner")
	await tree.process_frame
	check(not is_instance_valid(p) or p.is_queued_for_deletion(), "one at a time")
	q.queue_free()


func test_knocked_out_on_a_planet_loses_one() -> void:
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.set_process(false)
	s.state["player"]["carried"] = {"medicine": 3}
	s.state["player"]["equipment"] = ["laser"]
	s.state["player"]["lost"] = []   # (a slow build: pirates may have knocked you out already)
	s.knocked_out()
	check(not s.carried().has("medicine"), "knocked out: the medicine you carried is gone")
	check_eq(s.state["player"]["lost"].size(), 1, "on the lost list")
	s.queue_free()
	await tree.process_frame
