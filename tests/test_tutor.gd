extends TestCase
## The interactive tutorial (CosmosTutor) and the sandbox start: its steps done in
## any order and paid for, shown one at a time; docking counts only after undocking;
## following it to the end; ending early - all its rewards paid - when your first
## ship came another way and you've flown, docked and fought; old saves without one.

var _extra := {}


func setup() -> void:
	CosmosGame.ensure()
	_extra = CosmosGame.extra.duplicate(true)


func teardown() -> void:
	CosmosGame.extra = _extra


func _fresh() -> CosmosTutor:
	CosmosGame.extra = {}
	CosmosGame.start_on_foot()
	var t := CosmosTutor.new()
	tree.root.add_child(t)
	return t


func _total() -> int:
	var n := 0
	for st in CosmosTutor.STEPS:
		n += int(st[3])
	return n


func test_a_new_game_starts_on_foot_with_the_tutorial() -> void:
	CosmosGame.extra = {}
	CosmosGame.start_on_foot()
	check(not CosmosGame.has_ship(), "no ship at the start")
	check(str(CosmosGame.extra.get("start", "")) == "Amnissos", "on foot on Amnissos")
	check(CosmosTutor.active(), "the tutorial on")
	check(int(CosmosGame.data.ship_value) == 0 and str(CosmosGame.data.ship_class) == "", "nothing to trade in at a shipyard")
	CosmosGame.extra = {}
	check(not CosmosTutor.active(), "an old save (no tutorial in it): none")


func test_steps_paid_shown_one_at_a_time() -> void:
	var t := _fresh()
	var cr0: int = CosmosGame.data.credits
	check_eq(str(t.current()[1][0]), "walk", "the first step first")
	t.complete("scan")   # (done out of order)
	check(t.is_done("scan") and CosmosGame.data.credits == cr0 + 50, "a step done whenever: paid (%d)" % (CosmosGame.data.credits - cr0))
	check_eq(str(t.current()[1][0]), "walk", "the panel still shows the first not done")
	t.complete("scan")
	check(CosmosGame.data.credits == cr0 + 50, "paid once")
	t.on_event("docked")
	check(not t.is_done("dock"), "docking counts only after undocking (your bought ship's lift doesn't)")
	t.on_event("undocked")
	t.on_event("docked")
	check(t.is_done("undock") and t.is_done("dock"), "undocked, then docked")
	t.on_event("pirate_killed")
	check(not t.is_done("fight"), "one raider: not yet")
	t.on_event("pirate_killed")
	check(t.is_done("fight"), "two raiders: done")
	t.on_event("box_up")
	check(not t.is_done("drop"), "picking up needs setting down first")
	t.on_event("box_down")
	t.on_event("box_up")
	check(t.is_done("drop"), "set down, picked up")
	t.free()


func test_followed_to_the_end() -> void:
	var t := _fresh()
	var cr0: int = CosmosGame.data.credits
	for st in CosmosTutor.STEPS:
		if st[0] == "ship":
			CosmosGame.extra.erase("no_ship")
			t.on_event("ship_bought")
		else:
			check(CosmosTutor.active(), "still on before %s" % st[0])
			t.complete(str(st[0]))
	check(not CosmosTutor.active() and bool(CosmosTutor.state().get("finished", false)), "finished at its last step")
	check(not bool(CosmosTutor.state().get("other_way", false)), "followed: not 'another way'")
	check(CosmosGame.data.credits == cr0 + _total(), "every step paid once (%d of %d)" % [CosmosGame.data.credits - cr0, _total()])
	t.free()


func test_ship_another_way_ends_it_with_every_reward() -> void:
	var t := _fresh()
	var cr0: int = CosmosGame.data.credits
	t.complete("walk")
	CosmosGame.extra.erase("no_ship")   # (a ship come by another way, the first part not done)
	t._process(1.0)
	check(t.is_done("ship") and bool(CosmosTutor.state().get("other_way", false)), "a ship got another way: noted")
	check(CosmosTutor.active(), "still on: flying, docking and fighting to learn")
	t.on_event("undocked")
	t.on_event("docked")
	check(CosmosTutor.active(), "not yet: raiders to fight")
	t.on_event("pirate_killed")
	t.on_event("pirate_killed")
	check(not CosmosTutor.active(), "flown, docked, fought: it ends")
	check(CosmosGame.data.credits == cr0 + _total(), "with every reward it would have paid (%d of %d)" % [CosmosGame.data.credits - cr0, _total()])
	t.free()


func test_the_sandbox_pay() -> void:
	check(CosmosSandbox.ore_price("iron_ore") > int(Items.info("iron_ore").get("value", 0)), "the ore buyer pays more than its market value")
	var first_ship := int(Shipyard.stats("player")["price"])
	var tutor := _total()
	check(tutor < first_ship, "the tutorial alone doesn't buy a ship (%d of %d)" % [tutor, first_ship])
	var per := 280 + 60 + 30   # (a delivery's pay, middling)
	var n := ceili(float(first_ship - tutor) / per)
	check(n >= 20 and n <= 40, "a few dozen deliveries and the tutorial: a first ship (%d deliveries)" % n)
