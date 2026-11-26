extends TestCase
## Quest scenarios (plain-sentence rules): the engine, a whole scenario played
## in the real game scene, and the Scenario Editor.

var _main: Node
var _saved: Array = []


func setup() -> void:
	Scenarios.reload()
	_saved = Scenarios.all().duplicate(true)
	Scenarios.state = {}
	Galaxy.new_game(false)
	SaveGame.travelling = false
	SaveGame.pending = {}


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	await tree.process_frame
	tree.paused = false   # (a story dialogue may still have been open)
	# Leave the scenarios as they were on disk (tests edit them in memory).
	Scenarios.all().clear()
	Scenarios.all().append_array(_saved)
	Scenarios.state = {}
	Scenarios.host = null
	Galaxy.new_game(false)


## A host that records what the rules ask for.
class FakeHost extends Node:
	var calls: Array = []
	var items := {}
	var money := 0

	func item_count(i: String) -> int: return int(items.get(i, 0))
	func credits() -> int: return money
	func player_position() -> Variant: return Vector2.ZERO
	func place_position(_id: String, _p: String) -> Variant: return Vector2(100, 0)
	func objectives_changed() -> void: calls.append("objectives")
	func play_dialogue(l: Array) -> void: calls.append(["dialogue", l.size()])
	func message(t: String) -> void: calls.append(["message", t])
	func give_item(i: String, n: int) -> void: items[i] = int(items.get(i, 0)) + n
	func take_item(i: String, n: int) -> void: items[i] = int(items.get(i, 0)) - n
	func add_credits(n: int) -> void: money += n
	func spawn(_id: String, g: String, t: String, n: int, p: String) -> void: calls.append(["spawn", g, t, n, p])
	func drop_item(_id: String, i: String, _p: String) -> void: calls.append(["drop", i])
	func markers_changed(_id: String) -> void: calls.append("markers")
	func unlock_lore(l: String) -> void: calls.append(["lore", l])


func test_engine_rules_steps_conditions() -> void:
	var host := FakeHost.new()
	tree.root.add_child(host)
	Scenarios.host = host
	var sc := Scenarios.blank("t1", "Test")
	sc["steps"] = ["Not started", "A", "B", "Finished"]
	sc["rules"] = [
		{"when": {"event": "start", "args": {}}, "if": [], "then": [{"action": "set_step", "args": {"step": "A"}}], "once": true},
		{"when": {"event": "docked", "args": {"station": "Kephala Outpost"}}, "if": [{"cond": "step_is", "args": {"step": "A"}},
			{"cond": "has_item", "args": {"count": 2, "item": "iron_ore"}}],
			"then": [{"action": "take_item", "args": {"count": 2, "item": "iron_ore"}}, {"action": "credits", "args": {"amount": 300}},
				{"action": "add_var", "args": {"var": "visits", "value": 1}}, {"action": "set_step", "args": {"step": "B"}}], "once": true},
		{"when": {"event": "step", "args": {"step": "B"}}, "if": [], "then": [{"action": "timer", "args": {"timer": "t", "seconds": 1}},
			{"action": "spawn", "args": {"count": 2, "ship_type": "traced_pirate_reaver", "group": "g", "place": "player"}}], "once": true},
		{"when": {"event": "group_gone", "args": {"group": "g"}}, "if": [{"cond": "var", "args": {"var": "visits", "op": "=", "value": 1}}],
			"then": [{"action": "objective", "args": {"text": "Wait"}}], "once": true},
		{"when": {"event": "timer", "args": {"timer": "t"}}, "if": [{"cond": "step_is", "args": {"step": "B"}}],
			"then": [{"action": "finish", "args": {}}], "once": true},
	]
	Scenarios.all().append(sc)
	Scenarios.start("t1")
	check(Scenarios.state["t1"]["step"] == "A", "'the scenario starts' moves to step A")
	Scenarios.event("docked", {"station": "Kephala Outpost"})
	check(Scenarios.state["t1"]["step"] == "A", "a failing condition (not enough ore) blocks the rule")
	host.items["iron_ore"] = 3
	Scenarios.event("docked", {"station": "Other"})
	check(Scenarios.state["t1"]["step"] == "A", "an event for another station doesn't match")
	Scenarios.event("docked", {"station": "Kephala Outpost"})
	check(Scenarios.state["t1"]["step"] == "B" and host.items["iron_ore"] == 1 and host.money == 300, "the rule ran its actions in order")
	check(host.calls.has(["spawn", "g", "traced_pirate_reaver", 2, "player"]), "reaching step B spawned the group")
	Scenarios.group_ship_lost("t1", "g")
	check(Scenarios.state["t1"]["objective"] == "", "one ship left: the group isn't gone yet")
	Scenarios.group_ship_lost("t1", "g")
	check(Scenarios.state["t1"]["objective"] == "Wait", "the whole group gone fires its rule (counter condition true)")
	Scenarios.tick(0.6)
	check(Scenarios.state["t1"]["status"] == "active", "the timer is still running")
	Scenarios.tick(0.6)
	check(Scenarios.state["t1"]["status"] == "finished" and Scenarios.state["t1"]["step"] == "Finished", "the timer ran out: finished")
	var probs := Scenarios.check(sc).filter(func(p): return not str(p).begins_with("Note:"))
	check(probs.is_empty(), "the checker finds no problems in it (only notes): %s" % str(probs))
	var saved := Scenarios.get_save_data()
	Scenarios.state = {}
	Scenarios.load_save_data(saved)
	check(Scenarios.state["t1"]["status"] == "finished", "the state saves and loads")
	host.queue_free()


func test_checker_finds_problems() -> void:
	var sc := Scenarios.blank("t2", "Broken")
	sc["rules"] = [{"when": {"event": "step", "args": {"step": "Nowhere"}}, "if": [], "then": [], "once": true},
		{"when": {"event": "group_gone", "args": {"group": "ghosts"}}, "if": [], "then": [{"action": "set_step", "args": {"step": "Missing"}}], "once": true}]
	var probs := " | ".join(Scenarios.check(sc))
	check(probs.contains("does nothing"), "a rule without actions is reported")
	check(probs.contains("'Nowhere'"), "a step that doesn't exist is reported")
	check(probs.contains("'ghosts'"), "a group nothing spawns is reported")
	check(probs.contains("'Missing'"), "moving to a missing step is reported")


func test_missing_freighter_plays_through() -> void:
	var ex := Scenarios.find("missing_freighter")
	check(not ex.is_empty(), "the example scenario ships with the game")
	Scenarios.test_request = {"id": "missing_freighter", "step": ""}
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 30:
		await tree.process_frame
	check(Scenarios.state.get("missing_freighter", {}).get("status") == "active", "Test starts the scenario in a new game")
	var credits_before: int = _main.player_data.credits
	Scenarios.event("docked", {"station": "Kephala Outpost"})
	check(Scenarios.state["missing_freighter"]["step"] == "Search", "docking at Kephala Outpost starts the search")
	check(_main.player_data.credits == credits_before + 500, "the advance was paid")
	# Arriving in Klotho (simulated): the wreck's marker appears.
	Scenarios.event("entered", {"system": "klotho"})
	var at = _main.scenario_host.place_position("missing_freighter", "marker:wreck")
	check(at != null, "the wreck's marker is placed")
	# Fly to it: the ambush.
	_main.ship.global_position = at
	for i in 10:
		await tree.process_frame
	if _main.get_node("Panels/Dialogue").is_open():
		_main.get_node("Panels/Dialogue")._finish()
	for i in 5:
		await tree.process_frame
	check(Scenarios.state["missing_freighter"]["step"] == "Fight", "coming near the wreck springs the ambush")
	var raiders: Array = tree.get_nodes_in_group("enemies").filter(func(e): return str(e.quest_tag).begins_with("scenario:missing_freighter:ambush"))
	check(raiders.size() == 3, "three raiders spawned as group 'ambush' (%d)" % raiders.size())
	for r in raiders:
		r.take_damage(1e6, r.global_position, _main.ship)
	for i in 5:
		await tree.process_frame
	check(Scenarios.state["missing_freighter"]["step"] == "Return", "destroying the group moves on")
	check(_main.player_data.count("data_core") >= 1, "the black box was given")
	Scenarios.event("docked", {"station": "Kephala Outpost"})
	check(Scenarios.state["missing_freighter"]["status"] == "finished", "handing it in finishes the scenario")
	check(Galaxy.reputation.get("minoa", 0.0) >= 10.0, "reputation was raised")


func test_scenario_editor() -> void:
	var ed: Control = load("res://scenario_editor.tscn").instantiate()
	tree.root.add_child(ed)
	for i in 3:
		await tree.process_frame
	check(ed._list.item_count == Scenarios.all().size(), "the editor lists every scenario")
	var idx := -1
	for i in Scenarios.all().size():
		if Scenarios.all()[i]["id"] == "missing_freighter":
			idx = i
	ed._select(idx)
	for i in 8:   # (the cards come one a frame)
		await tree.process_frame
	var cards: Array = ed._rules_box.get_children().filter(func(c): return c is PanelContainer)
	check(cards.size() == 5, "one card per rule (%d)" % cards.size())
	# A new rule for a step: it starts with 'the quest step is <step>'.
	ed._step_filter = "Fight"
	ed._rebuild()
	await tree.process_frame
	var rules: Array = ed._sc["rules"]
	rules.append(Scenarios.blank_rule("Fight"))
	check(rules[-1]["if"][0]["args"]["step"] == "Fight", "a new rule for a step tests that step")
	# Renaming a step renames it in every rule.
	ed._rename_step("Fight", "Battle")
	check(ed._sc["steps"].has("Battle") and not ed._sc["steps"].has("Fight"), "the step is renamed")
	var uses := 0
	for r in rules:
		for c in r["if"]:
			if c["args"].get("step") == "Battle":
				uses += 1
	check(uses >= 2, "every rule now tests 'Battle'")
	ed._check()
	check(ed._problems.text.contains("does nothing"), "the problems list shows the empty new rule")
	ed.queue_free()
	await tree.process_frame
