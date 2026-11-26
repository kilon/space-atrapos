extends TestCase
## A station's repair service (RepairService): an evaluation listing the
## damage with prices at least MARKUP x the manual cost; a repair over time (up
## to a minute); undocking refunds what's not done. Component upgrades (Upgrades).

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


func _game() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 30:
		await tree.process_frame
	_main.ship.invulnerable = true


func test_evaluation_and_repair() -> void:
	await _game()
	var pd: Node = _main.player_data
	var ship: Node2D = _main.ship
	ship.hull = ship.max_hull * 0.4
	Parts.add_fault(pd.condition, "ship", "engines", "wreck", 4, _rng(1))
	Parts.add_fault(pd.condition, "ship", "sensors", "crack", 1, _rng(2))
	Parts.add_fault(pd.condition, "automaton", "legs", "crack", 0, _rng(3))
	var ev := RepairService.evaluate(pd, ship)
	check_eq(ev.size(), 4, "the hull and three faults (%s)" % str(ev.map(func(x): return x["name"])))
	check(ev[0]["kind"] == "hull", "the hull first")
	for it in ev:
		check(float(it["price"]) >= float(it["manual"]) * RepairService.MARKUP - 0.01, "%s: at least %dx the manual cost (%d vs %.0f)" % [it["name"], int(RepairService.MARKUP), int(it["price"]), float(it["manual"])])
	check(Parts.part(pd.condition, "ship", "engines")["faults"][0]["found"], "hidden faults traced")
	check(RepairService.job_time(ev) <= RepairService.MAX_TIME, "it takes a minute at most")
	pd.credits = 100000
	var job := RepairService.start(pd, ev)
	check(not job.is_empty() and pd.credits == 100000 - RepairService.total(ev), "paid up front")
	RepairService.tick(job, 1.0, pd, ship)
	check(not RepairService.finished(job), "a second in: not done")
	var t := 1.0
	while not RepairService.finished(job) and t < 70.0:
		RepairService.tick(job, 1.0, pd, ship)
		t += 1.0
	check(RepairService.finished(job) and t <= RepairService.MAX_TIME + 1.0, "done within a minute (%.0f s)" % t)
	check(is_equal_approx(ship.hull, ship.max_hull) and Parts.fault_count(pd.condition, "ship") == 0 and Parts.fault_count(pd.condition, "automaton") == 0, "everything repaired")
	# Undocking mid-job: the rest paid back.
	Parts.add_fault(pd.condition, "ship", "engines", "crack", 1, _rng(5))
	Parts.add_fault(pd.condition, "ship", "shields", "crack", 1, _rng(6))
	var ev2 := RepairService.evaluate(pd, ship)
	var before: int = pd.credits
	var job2 := RepairService.start(pd, ev2)
	RepairService.tick(job2, float(job2["items"][0]["time"]) + 0.01, pd, ship)
	var back := RepairService.cancel(job2, pd)
	check(back == int(ev2[1]["price"]) and pd.credits == before - int(ev2[0]["price"]), "undocked mid-job: the unfinished one paid back")


func test_upgrades() -> void:
	await _game()
	var pd: Node = _main.player_data
	var ship: Node2D = _main.ship
	var n := Upgrades.list("ship").size() + Upgrades.list("automaton").size()
	check(n >= 40, "dozens of stats to upgrade (%d)" % n)
	var keys := {}
	for w in ["ship", "automaton"]:
		for st in Upgrades.list(w):
			keys[st["key"]] = true
	check(keys.size() >= 30 and keys.has("accuracy") and keys.has("evasion") and keys.has("crit_chance"), "accuracy, evasion, critical hits among %d kinds" % keys.size())
	var hull: float = ship.max_hull
	check(Upgrades.price("ship", "plating:max_hull", 1) > Upgrades.price("ship", "plating:max_hull", 0), "dearer each level")
	for i in 3:
		Upgrades.raise(pd.upgrades, "ship", "plating:max_hull")
	ship.apply_tech()
	check(is_equal_approx(ship.max_hull, hull + 45.0), "three levels of hull strength: +45 (%.0f)" % ship.max_hull)
	Upgrades.raise(pd.upgrades, "ship", "sensors:accuracy")
	ship.apply_tech()
	check(ship.accuracy() > Accuracy.BASE_SHIP, "accuracy upgraded")
	Parts.add_fault(pd.condition, "ship", "plating", "wreck", 0, _rng(7))
	ship.apply_tech()
	check(ship.max_hull < hull + 45.0, "a damaged part: its upgrades give less")
	for i in 10:
		Upgrades.raise(pd.upgrades, "ship", "plating:max_hull")
	check_eq(Upgrades.level(pd.upgrades, "ship", "plating:max_hull"), Upgrades.MAX_LEVEL, "at most %d levels" % Upgrades.MAX_LEVEL)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pd.get_save_data()))
	pd.load_save_data(saved)
	check_eq(Upgrades.level(pd.upgrades, "ship", "plating:max_hull"), Upgrades.MAX_LEVEL, "saved and loaded")
