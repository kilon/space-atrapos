extends TestCase
## Damage to parts and the Repair Bay (Parts, RepairBay): hits leave faults
## that weaken what the part does and are saved; on the operating table each
## kind is found with its scan mode and fixed with its tool, by mouse - the
## bolts undone in a good order, the crack welded, the cable soldered (the
## power cut first: live, it shocks), the leak sealed at low pressure, the
## component calibrated, a wreck replaced by a spare turned the right way.

var _main: Node


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}


func _rng(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = n
	return r


func test_hits_leave_faults_that_weaken_parts() -> void:
	var c := {}
	var rng := _rng(3)
	var made := 0
	for i in 200:
		if not Parts.hit(c, "ship", 200.0, 800.0, "kinetic", Vector2(0, 1), rng).is_empty():
			made += 1
	check(made > 0, "big hits leave faults (%d)" % made)
	var b := Parts.body(c, "ship")
	var rear: int = b["engines"]["faults"].size() + b["fuel"]["faults"].size()
	var front: int = b["sensors"]["faults"].size()
	check(rear > front, "hits from behind reach the engines and fuel lines, not the sensors (%d / %d)" % [rear, front])
	check(Parts.fault_count(c, "ship") <= Parts.BODIES["ship"]["parts"].size() * Parts.MAX_FAULTS, "a part holds at most MAX_FAULTS")
	check(Parts.mod(c, "ship", "speed_mult") < 0.0, "damaged engines: less speed (%.2f)" % Parts.mod(c, "ship", "speed_mult"))
	var small := 0
	var c2 := {}
	for i in 200:
		if not Parts.hit(c2, "ship", 2.0, 800.0, "kinetic", Vector2.ZERO, rng).is_empty():
			small += 1
	check(small < 10, "grazes rarely leave one (%d of 200)" % small)
	# A fault's kind follows the damage: lasers burn wiring, heat leaks.
	var c3 := {}
	var kinds := {}
	for i in 300:
		var f := Parts.hit(c3, "ship", 300.0, 800.0, "energy", Vector2.ZERO, rng)
		if not f.is_empty():
			kinds[f["kind"]] = int(kinds.get(f["kind"], 0)) + 1
	check(kinds.has("burn"), "energy weapons burn wiring (%s)" % str(kinds))
	# Saved and loaded (JSON numbers as floats) the same.
	var back := Parts.load_condition(JSON.parse_string(JSON.stringify(c)))
	check_eq(Parts.fault_count(back, "ship"), Parts.fault_count(c, "ship"), "the faults survive a save")
	check(is_equal_approx(Parts.mod(back, "ship", "speed_mult"), Parts.mod(c, "ship", "speed_mult")), "and weaken the same")
	# Cut the power: the part does nothing.
	var c4 := {}
	Parts.part(c4, "ship", "engines")["off"] = true
	check(is_equal_approx(Parts.mod(c4, "ship", "speed_mult"), -0.45), "an engine switched off: all its speed gone")
	check(Parts.service_cost(c, "ship") > 0 and Parts.clear_all(c, "ship") > 0 and Parts.fault_count(c, "ship") == 0, "a station's technicians fix everything, for a price")


func test_the_ship_and_automaton_feel_their_damage() -> void:
	Galaxy.new_game(false)
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 10:
		await tree.process_frame
	var pd: Node = _main.player_data
	var ship: Node2D = _main.ship
	var speed: float = ship.max_speed
	var shields: float = ship.max_shields
	Parts.add_fault(pd.condition, "ship", "engines", "wreck", 0, _rng(1))
	Parts.add_fault(pd.condition, "ship", "shields", "wreck", 0, _rng(1))
	ship.apply_tech()
	check(ship.max_speed < speed * 0.9, "wrecked engine parts: slower (%.0f < %.0f)" % [ship.max_speed, speed])
	check(ship.max_shields < shields, "a wrecked emitter part: weaker shields")
	check(pd.get_save_data()["condition"]["ship"]["engines"]["faults"].size() == 1, "the condition is saved with the player")
	# Hits through to the hull leave faults (and say so).
	var before := Parts.fault_count(pd.condition, "ship")
	for i in 60:
		ship.hull = ship.max_hull
		ship.shields = 0.0
		ship.take_damage(ship.max_hull * 0.2, ship.global_position + Vector2(0, 300).rotated(ship.rotation))
	check(Parts.fault_count(pd.condition, "ship") > before, "heavy hits on the hull damage parts")
	# The automaton: its legs slow it, its frame lets more through.
	var pilot := SurfaceProps.Pilot.new()
	var player := {"condition": {}}
	pilot.apply_gear(player)
	var walk := pilot.speed
	Parts.add_fault(player["condition"], "automaton", "legs", "wreck", 0, _rng(2))
	Parts.add_fault(player["condition"], "automaton", "frame", "wreck", 0, _rng(2))
	pilot.apply_gear(player)
	check(pilot.speed < walk, "damaged leg servos: slower walking (%.0f < %.0f)" % [pilot.speed, walk])
	pilot.hp = 100.0
	pilot.shield = 0.0   # (the hit reaches the frame)
	pilot.surface_hit(10.0)
	check(pilot.hp < 90.0, "a damaged frame: more damage taken (%.1f)" % (100.0 - pilot.hp))
	pilot.free()


# --- The operating table, by mouse --------------------------------------------------

var _bay: RepairBay
var _t: RepairBay.Table


func _btn(at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	_t._gui_input(e)


func _move(to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = to - _t._mouse
	e.position = to
	_t._gui_input(e)


func _step(s: float, dt := 0.05) -> void:
	var n := ceili(s / dt)
	for i in n:
		_t._process(dt)


func _hold_at(at: Vector2, s: float) -> void:
	_move(at)
	_btn(at, true)
	_step(s)
	_btn(at, false)


func _open_bay() -> void:
	Galaxy.new_game(false)
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 10:
		await tree.process_frame
	_main.ship_menu.open(_main.ship_menu.REPAIR_TAB)
	for i in 3:
		await tree.process_frame
	_bay = _main.ship_menu._pages[_main.ship_menu.REPAIR_TAB]
	_t = _bay._table


func test_surgery_on_the_engines() -> void:
	await _open_bay()
	var pd: Node = _main.player_data
	var c: Dictionary = pd.condition
	var cs := Parts.comps("ship", "engines")   # injector, liner, vector, ignition, chamber
	Parts.add_fault(c, "ship", "engines", "crack", 1, _rng(4))
	Parts.add_fault(c, "ship", "engines", "leak", 0, _rng(5))
	Parts.add_fault(c, "ship", "engines", "burn", 3, _rng(6))
	Parts.add_fault(c, "ship", "engines", "drift", 2, _rng(7))
	Parts.add_fault(c, "ship", "engines", "wreck", 4, _rng(8))
	pd.add_item("spare_cell", 1)
	_bay.pick_part("engines")
	await tree.process_frame
	check(_t.size.x > 600 and _t.size.y > 400, "the table has room (%s)" % str(_t.size))
	var speed: float = _main.ship.max_speed
	# The scanner can't see through the casing (no Deep Scanner).
	_bay.set_tool("scanner")
	_bay.set_scan("structure")
	_hold_at(_t.anchor(_bay.faults()[0]), 1.0)
	check(not _bay.faults()[0]["found"], "the closed casing blocks the scan")
	# Undo the bolts (a click near each, whatever tool), opposite ones in turn: no strain.
	for i in [0, 3, 1, 4, 2, 5]:
		_hold_at(_t.bolt_pos(i) + Vector2(20, 14), 0.1)   # (near it, not on it: a generous reach)
	check(_bay.op()["open"], "all six bolts out: the casing comes off")
	check(_bay.faults().size() == 5, "no complication from a good order")
	var wreck: Dictionary = _bay.faults().filter(func(f): return f["kind"] == "wreck")[0]
	check(wreck["found"], "a wreck is plain to see once it's open")
	_step(0.6)   # (the casing lifts away)
	# Scan: each kind in its mode.
	_bay.set_tool("scanner")
	for mode in ["structure", "thermal"]:
		_bay.set_scan(mode)
		for f in _bay.faults():
			if Parts.FAULTS[f["kind"]]["scan"] == mode:
				_move(_t.anchor(f))
				_step(0.6)
	var by := {}
	for f in _bay.faults():
		by[f["kind"]] = f
	check(by["crack"]["found"] and by["leak"]["found"], "structure finds the crack, thermal the leak")
	check(not by["burn"]["found"] and not by["drift"]["found"], "the field and resonance modes need a Mk II scanner")
	pd.add_item("scanner_mk2", 1)
	_bay._fill()
	for mode in ["field", "resonance"]:
		_bay.set_scan(mode)
		for f in _bay.faults():
			if Parts.FAULTS[f["kind"]]["scan"] == mode:
				_move(_t.anchor(f))
				_step(0.6)
	check(by["burn"]["found"] and by["drift"]["found"], "with the Mk II: the burnt cable and the misalignment")
	# Weld the crack: slowly along it.
	_bay.set_tool("welder")
	var bits: Array = _t.crack_bits(by["crack"])
	_move(bits[0][0])
	_btn(bits[0][0], true)
	for b in bits:
		var m: Vector2 = (b[0] + b[1]) * 0.5
		_move(_t._mouse.lerp(m, 0.5))
		_t._speed = 200.0
		_t._process(0.03)
		_move(m)
		_t._speed = 200.0
		_t._process(0.03)
	_btn(_t._mouse, false)
	check(by["crack"]["id"] not in _bay.faults().map(func(f): return f["id"]), "the crack welded shut")
	# Solder: live first - a shock.
	_bay.set_tool("solder")
	var g: Dictionary = _t.burn_geo(by["burn"])
	var heat := float(_bay.op()["heat"])
	var before := _bay.faults().size()
	_btn(g["l"][0], true)
	_btn(g["l"][0], false)
	check(float(_bay.op()["heat"]) > heat, "soldering a live cable: a shock")
	check(_bay.faults().size() == before, "a shock hurts, but never adds a fault (faults come only from hits)")
	_bay._toggle_power()
	check(not _bay.powered(), "the breaker cut")
	var burn_id: int = by["burn"]["id"]
	for bf in _bay.faults().filter(func(f): return f["kind"] == "burn"):
		var gg: Dictionary = _t.burn_geo(bf)
		for k in 3:
			var j: int = gg["order"].find(k)
			_move(gg["l"][k])
			_btn(gg["l"][k], true)
			_move(gg["r"][j])
			_btn(gg["r"][j], false)
	check(burn_id not in _bay.faults().map(func(f): return f["id"]), "each strand to its own colour: the cable mended")
	_bay._toggle_power()
	# Seal the leak: only while the pressure's low.
	_bay.set_tool("sealant")
	var lp: Vector2 = _t.leak_pos(by["leak"])
	_move(lp)
	var leak_id: int = by["leak"]["id"]
	for i in 600:
		var low: bool = _t.pressure(by["leak"]) < 0.42
		if low and not _t._down:
			_btn(lp, true)
		elif not low and _t._down:
			_btn(lp, false)
		_t._process(0.05)
		if leak_id not in _bay.faults().map(func(f): return f["id"]):
			break
	_btn(lp, false)
	check(leak_id not in _bay.faults().map(func(f): return f["id"]), "sealed, a little at each low")
	# Calibrate: the dials onto the reference.
	_bay.set_tool("calibrator")
	var st: Dictionary = _t.fstate(by["drift"])
	var panel: Array = _t.cal_panel(by["drift"])
	for k in 2:
		var dial: Vector2 = panel[k + 1]
		var need: float = (float(st["f0"]) - float(st["f"])) / 0.008 if k == 0 else angle_difference(float(st["p"]), float(st["p0"])) / 0.02
		_move(dial)
		_btn(dial, true)
		var e := InputEventMouseMotion.new()
		e.position = dial
		e.relative = Vector2(0, -need)
		_t._gui_input(e)
		_btn(dial, false)
	var drift_id: int = by["drift"]["id"]
	_step(1.3)
	check(drift_id not in _bay.faults().map(func(f): return f["id"]), "frequency and phase on the reference: aligned")
	# The wreck: clamps, out, a spare turned to the notch, clamps.
	_bay.set_tool("forceps")
	var cp: Vector2 = _t.comp_pos(4)
	_btn(_t.clamp_pos(wreck, 0), true)
	_btn(_t.clamp_pos(wreck, 1), true)
	_btn(cp, true)
	_move(cp + Vector2(0, _t.comp_size() * 3.0))
	_btn(_t._mouse, false)
	check_eq(str(_t.fstate(wreck)["stage"]), "empty", "pulled out")
	_btn(cp, true)
	check(_t._held_spare >= 0, "a spare in the forceps")
	if _t._held_spare != _t.notch(wreck):
		_btn(cp, true)
		check(str(_t.fstate(wreck)["stage"]) == "empty", "turned wrong, it won't seat")
	for i in 4:
		if _t._held_spare == _t.notch(wreck):
			break
		_btn(cp, true, MOUSE_BUTTON_RIGHT)
	_btn(cp, true)
	check_eq(str(_t.fstate(wreck)["stage"]), "seat", "turned to the notch, it seats")
	check_eq(pd.count("spare_cell"), 0, "the spare used")
	_btn(_t.clamp_pos(wreck, 0), true)
	_btn(_t.clamp_pos(wreck, 1), true)
	check(_bay.faults().is_empty(), "every fault fixed")
	check(_main.ship.max_speed > speed, "the engines back to full speed (%.0f > %.0f)" % [_main.ship.max_speed, speed])
	# Close up: a click on each empty hole.
	for i in 6:
		_hold_at(_t.bolt_pos(i), 0.1)
	check(not _bay.op()["open"], "the bolts back in: closed")


func test_careless_surgery_has_consequences() -> void:
	await _open_bay()
	var c: Dictionary = _main.player_data.condition
	_bay.pick_part("reactor")
	await tree.process_frame
	# Neighbouring bolts one after another: the casing warps and the bolts seize -
	# never a new fault (faults come only from hits to the hull or the body).
	var faults_of := func(): return Parts.part(c, "ship", "reactor")["faults"].size()
	var n0: int = faults_of.call()
	for i in [0, 1, 2]:
		_hold_at(_t.bolt_pos(i), 0.6)
	check(faults_of.call() == n0, "undoing neighbours warped the casing, but no new fault")
	check(int(_bay.op()["seized"]) > 0, "the warped casing seized the bolts")
	var left: int = _bay.op()["bolts"].count(true)
	_hold_at(_t.bolt_pos(3), 0.1)
	check(_bay.op()["bolts"].count(true) == left, "a seized bolt doesn't come out at the first turn")
	for k in 6:
		for i in [3, 4, 5]:
			if _bay.op()["bolts"][i]:
				_hold_at(_t.bolt_pos(i), 0.6)
	check(_bay.op()["open"], "kept turning: the casing came off")
	# Too long with the welder in one place: overheated - the welder cuts out, no new fault.
	var n: int = faults_of.call()
	_bay.set_tool("welder")
	var at: Vector2 = _t.comp_pos(0)
	_move(at)
	_btn(at, true)
	_step(4.0)
	var said: String = _t._flash_text
	_btn(at, false)
	check(said.begins_with("Overheated"), "welding in one place too long: overheated (%s)" % said)
	check(faults_of.call() == n, "an overheat costs work, but no new fault")
	# The automaton's core can't be switched off (it's you).
	_bay._pick_body("automaton")
	_bay.pick_part("core")
	_bay._toggle_power()
	check(_bay.powered(), "the automaton's power core stays on")
