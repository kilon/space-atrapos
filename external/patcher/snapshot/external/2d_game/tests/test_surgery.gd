extends TestCase
## The automaton on the operating table (Surgery, AnatomyArt, Parts' anatomy):
## its body in four layers - muscles, veins, nerves, skeleton - each
## component a structure of one layer at its place; the scanner finding the
## faults of the layer shown (the deeper ones with a Mk II); the muscles
## worked on directly, the rest through an incision; each fault mended with
## its surgeon's tool - sutures, the bone fuser, a clamp and sealant, the
## splicer under a nerve block, the tuner, a graft with the forceps - by mouse.

var _main: Node
var _bay: RepairBay
var _s: Surgery


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}


func _rng(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = n
	return r


func test_the_body_is_anatomy_in_four_layers() -> void:
	check_eq(Parts.LAYERS, ["muscles", "veins", "nerves", "skeleton"], "the four layers, outermost first")
	var seen := {}
	var by_kind := {"servo": ["muscles", "veins"], "conduit": ["veins"], "circuit": ["nerves"], "plate": ["skeleton"]}
	for pid in Parts.BODIES["automaton"]["parts"]:
		var layers := {}
		for c in Parts.comps("automaton", pid):
			check(c.size() == 7 and str(c[2]) in Parts.LAYERS, "%s: %s has a layer, a place, a direction and a width" % [pid, c[1]])
			check(str(c[2]) in by_kind[c[0]], "%s is a %s: in the %s layer" % [c[1], c[0], c[2]])
			var p := AnatomyArt.px(float(c[3]), float(c[4]))
			check(Rect2(Vector2.ZERO, AnatomyArt.SIZE).grow(-60.0).has_point(p), "%s lies on the body's picture (%s)" % [c[1], p])
			layers[c[2]] = true
			seen[c[2]] = true
		check(layers.size() >= 3, "%s reaches through the layers (%s)" % [pid, layers.keys()])
	check_eq(seen.size(), 4, "every layer has structures")
	# The head is at the picture's left, the body's left side at its top.
	check(AnatomyArt.px(0.0, 1.70).x < AnatomyArt.px(0.0, 0.10).x and AnatomyArt.px(0.2, 1.0).y < AnatomyArt.px(-0.2, 1.0).y, "lying head-left, its left side up")
	for l in Parts.LAYERS:
		check(ResourceLoader.exists(AnatomyArt.path(l)), "the %s picture is there" % l)
	# A fault's name and tool follow its layer.
	var c := {}
	var crack_bone := Parts.add_fault(c, "automaton", "arms", "crack", 4, _rng(1))
	var crack_muscle := Parts.add_fault(c, "automaton", "arms", "crack", 0, _rng(2))
	var arr := Parts.add_fault(c, "automaton", "core", "drift", 0, _rng(3))
	check_eq(Parts.fault_info("automaton", "arms", crack_bone)["tool"], "fuser", "a fracture: the bone fuser")
	check_eq(Parts.fault_info("automaton", "arms", crack_bone)["name"], "Fracture", "... by its name")
	check_eq(Parts.fault_info("automaton", "arms", crack_muscle)["tool"], "suture", "a torn muscle: sutures")
	check_eq(Parts.fault_info("automaton", "core", arr)["name"], "Arrhythmia", "the heart out of rhythm")
	check_eq(Parts.fault_info("ship", "engines", {"kind": "crack", "comp": 1})["tool"], "welder", "the ship's are as they were")
	# The scanner: muscles and veins built in, the deeper layers with a Mk II.
	check_eq(Parts.scan_layers({}), ["muscles", "veins"], "the built-in scanner's layers")
	check_eq(Parts.scan_layers({"scanner_mk2": 1}).size(), 4, "a Mk II reads them all")
	# An older save: a fault its component can't have now moves to one that can (or goes).
	var old := {"automaton": {"optics": {"faults": [{"id": 1, "kind": "drift", "comp": 0, "sev": 0.5}], "off": false},
		"core": {"faults": [{"id": 2, "kind": "burn", "comp": 1, "sev": 0.5}], "off": false}}, "next": 3}
	var back := Parts.load_condition(old)
	var of: Array = back["automaton"]["optics"]["faults"]
	check(of.size() == 1 and Parts.comps("automaton", "optics")[int(of[0]["comp"])][0] == "servo", "a spasm moved onto a muscle")
	check(back["automaton"]["core"]["faults"].is_empty(), "nothing in the heart's part can burn: it's gone")


# --- the operating table, by mouse ---------------------------------------------------------------

func _btn(at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	_s._gui_input(e)


func _move(to: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = to - _s._mouse
	e.position = to
	_s._gui_input(e)


func _step(s: float, dt := 0.05) -> void:
	for i in ceili(s / dt):
		_s._process(dt)


func _click(at: Vector2) -> void:
	_move(at)
	_btn(at, true)
	_btn(at, false)


## The button held, drawn steadily through the middle of each piece (a cut, a fracture).
func _trace(bits: Array) -> void:
	var first: Vector2 = ((bits[0][0] as Vector2) + (bits[0][1] as Vector2)) * 0.5
	_move(first)
	_btn(first, true)
	for b in bits:
		var m: Vector2 = ((b[0] as Vector2) + (b[1] as Vector2)) * 0.5
		_move(_s._mouse.lerp(m, 0.5))
		_s._speed = 200.0
		_s._process(0.03)
		_move(m)
		_s._speed = 200.0
		_s._process(0.03)
	_btn(_s._mouse, false)


func _scan_at(f: Dictionary) -> void:
	_bay.set_tool("scanner")
	_move(_s.anchor(f))
	_step(0.7)


func _open_bay(part: String) -> void:
	Galaxy.new_game(false)
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 10:
		await tree.process_frame
	_main.ship_menu.open(_main.ship_menu.REPAIR_TAB)
	for i in 3:
		await tree.process_frame
	_bay = _main.ship_menu._pages[_main.ship_menu.REPAIR_TAB]
	_s = _bay._surgery
	_bay._pick_body("automaton")
	_bay.pick_part(part)
	await tree.process_frame
	_s.opened()
	_s._view = _s._view_to


func test_an_operation_on_the_arm() -> void:
	await _open_bay("arms")
	var pd: Node = _main.player_data
	var c: Dictionary = pd.condition
	check(_s.visible and not _bay._table.visible, "the automaton: the anatomy on the table")
	check_eq(_bay._tool_btns.size(), RepairBay.SURGERY_TOOLS.size(), "a surgeon's tools")
	check(_s.size.x > 600 and _s.size.y > 400, "the table has room (%s)" % str(_s.size))
	for i in _s.comps().size():
		check(Rect2(Vector2.ZERO, _s.size).grow(-20.0).has_point(_s.site(i)), "%s is in view" % _s.comps()[i][1])
	var tear := Parts.add_fault(c, "automaton", "arms", "crack", 0, _rng(4))     # right biceps
	var spasm := Parts.add_fault(c, "automaton", "arms", "drift", 1, _rng(5))    # left forearm flexors
	var nerve := Parts.add_fault(c, "automaton", "arms", "burn", 2, _rng(6))     # right median nerve
	var bleed := Parts.add_fault(c, "automaton", "arms", "leak", 3, _rng(7))     # right brachial artery
	var bone := Parts.add_fault(c, "automaton", "arms", "crack", 4, _rng(8))     # left upper arm bone
	var by := func(x: Dictionary) -> Dictionary: return _bay.fault(int(x["id"]))
	var has := func(x: Dictionary) -> bool: return not _bay.fault(int(x["id"])).is_empty()
	var total := func() -> int: return Parts.fault_count(c, "automaton")
	check_eq(total.call(), 5, "five faults")
	# The scanner finds the faults of the layer shown.
	_bay.set_layer("veins")
	_scan_at(by.call(tear))
	check(not by.call(tear)["found"], "a torn muscle doesn't show in the veins layer")
	_bay.set_layer("muscles")
	_scan_at(by.call(tear))
	_scan_at(by.call(spasm))
	check(by.call(tear)["found"] and by.call(spasm)["found"], "the muscles layer: the tear and the spasm found")
	_bay.set_layer("veins")
	_scan_at(by.call(bleed))
	check(by.call(bleed)["found"], "the veins layer: the bleed")
	_bay.set_layer("skeleton")
	_scan_at(by.call(bone))
	check(not by.call(bone)["found"], "the skeleton is too deep for the built-in scanner")
	pd.add_item("scanner_mk2", 1)
	_scan_at(by.call(bone))
	_bay.set_layer("nerves")
	_scan_at(by.call(nerve))
	check(by.call(bone)["found"] and by.call(nerve)["found"], "with a Mk II: the fracture and the burnt nerve")
	# The muscle is the surface: sutured directly, a stitch at each mark.
	_bay.set_layer("muscles")
	_bay.set_tool("suture")
	var marks := _s.stitch_pts(by.call(tear))
	for i in marks.size() - 1:
		_click(marks[i])
	check(has.call(tear), "one stitch short: still torn")
	_click(marks[-1])
	check(not has.call(tear), "sutured: the tear is mended")
	# The spasm: the tuner's wave onto the reference, and held.
	_bay.set_tool("tuner")
	var st: Dictionary = _s.fstate(by.call(spasm))
	var panel := _s.cal_panel(by.call(spasm))
	_move(panel[1])
	_btn(panel[1], true)
	check(str(_s._drag.get("kind", "")) == "dial", "a dial in hand")
	_btn(panel[1], false)
	st["f"] = st["f0"]
	st["p"] = st["p0"]
	_step(1.3)
	check(not has.call(spasm), "tuned and held: the spasm is gone")
	# The bone lies under the muscle: no fusing until it's cut down to.
	_bay.set_layer("skeleton")
	_bay.set_tool("fuser")
	check(not _s.reachable(by.call(bone)), "the fracture is under the muscle")
	_trace(_s.crack_bits(by.call(bone)))
	check(has.call(bone), "the fuser does nothing through the muscle")
	_bay.op()["heat"] = 0.0
	_bay.set_tool("scalpel")
	_trace(_s.cut_bits(4))
	check(_s.is_open(4) and _s.reachable(by.call(bone)), "an incision along the line: the bone is reached")
	_bay.set_tool("fuser")
	_trace(_s.crack_bits(by.call(bone)))
	check(not has.call(bone), "traced with the fuser: the fracture knit")
	check(float(_bay.op()["heat"]) > 0.0, "the fuser heats the site")
	# The incision closed with sutures.
	_bay.set_tool("suture")
	for p in _s.close_pts(4):
		_click(p)
	check(not _s.is_open(4), "stitched shut")
	# The nerve: cut down to it; live, it shocks - numb the arm first.
	_bay.set_layer("nerves")
	_bay.set_tool("scalpel")
	_trace(_s.cut_bits(2))
	check(_s.is_open(2), "an incision over the nerve")
	_bay.set_tool("splicer")
	var g: Dictionary = _s.burn_geo(by.call(nerve))
	_bay.op()["shock"] = 0.0
	_btn(g["l"][0], true)
	_btn(g["l"][0], false)
	check(float(_bay.op()["shock"]) > 0.0 and has.call(nerve), "splicing a live nerve: a shock, and nothing joined")
	check_eq(total.call(), 2, "... and no new fault from it")
	_bay._toggle_power()
	check(not _bay.powered(), "the nerve block: the arm numbed")
	for j in 3:
		var to: int = g["order"].find(j)
		_move(g["l"][j])
		_btn(g["l"][j], true)
		_move(g["r"][to])
		_btn(g["r"][to], false)
	check(not has.call(nerve), "each fibre to its own colour: the nerve spliced")
	_bay._toggle_power()
	check(_bay.powered(), "the block lifted")
	# The bleed: clamped upstream, the pressure stays down; sealed.
	_bay.set_layer("veins")
	_bay.set_tool("scalpel")
	_trace(_s.cut_bits(3))
	_bay.set_tool("clamp")
	_click(_s.clamp_at(by.call(bleed)))
	check(float(_s.fstate(by.call(bleed))["clamp"]) > 0.0, "the vessel clamped")
	var hi := 0.0
	for i in 40:
		_s._process(0.05)
		hi = maxf(hi, _s.pressure(by.call(bleed)))
	check(hi < 0.42, "clamped: the pressure stays low (%.2f)" % hi)
	_bay.set_tool("sealant")
	var lp := _s.leak_pos(by.call(bleed))
	_move(lp)
	_btn(lp, true)
	for i in 80:
		if not has.call(bleed):
			break
		_s._process(0.05)
	_btn(lp, false)
	check(not has.call(bleed), "sealed while it held")
	check_eq(total.call(), 0, "the arm is whole again - and nothing new went wrong on the table")
	# Leaving the part closes what's still open.
	check(_s.is_open(3), "(an incision still open)")
	_bay.pick_part("legs")
	_bay.pick_part("arms")
	check(not _s.is_open(3), "leaving the part closed it up")


func test_a_graft() -> void:
	await _open_bay("legs")
	var pd: Node = _main.player_data
	var c: Dictionary = pd.condition
	var dead := Parts.add_fault(c, "automaton", "legs", "wreck", 0, _rng(9))   # right thigh muscle
	var walk: float = Parts.mod(c, "automaton", "speed_mult")
	check(walk < 0.0, "a destroyed thigh muscle: slower")
	_s._view_pid = ""
	_s.opened()
	_s._view = _s._view_to
	var f: Dictionary = _bay.fault(int(dead["id"]))
	check(f["found"], "a destroyed muscle is plain to see")
	_bay.set_tool("forceps")
	var st: Dictionary = _s.fstate(f)
	for j in 2:
		_click(_s.tie_pos(f, j))
	check_eq(str(st["stage"]), "lift", "both ties undone")
	var at := _s.site(0)
	_move(at)
	_btn(at, true)
	_move(at + Vector2(0, -_s.piece(0).x * 3.0))
	_btn(_s._mouse, false)
	check_eq(str(st["stage"]), "empty", "lifted out")
	_click(at)
	check(_s._held_spare < 0, "no spare: nothing to graft")
	pd.add_item("spare_servo", 1)
	_click(at)
	check(_s._held_spare >= 0, "a spare in the forceps")
	_click(at)
	check_eq(str(st["stage"]), "empty", "turned the wrong way: it won't take")
	for i in 4:
		if _s._held_spare == _s.notch(f):
			break
		_btn(at, true, MOUSE_BUTTON_RIGHT)
	_click(at)
	check_eq(str(st["stage"]), "seat", "turned the way the tissue runs: grafted")
	check_eq(pd.count("spare_servo"), 0, "the spare is used")
	for j in 2:
		_click(_s.tie_pos(f, j))
	check(_bay.fault(int(dead["id"])).is_empty() and Parts.mod(c, "automaton", "speed_mult") == 0.0, "tied in: the leg works again")
