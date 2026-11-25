class_name CosmosTutor
extends CanvasLayer
## The interactive tutorial (a new game's, on foot on Amnissos): a short list of
## things to learn by doing, shown one at a time in a small panel at the top
## right - never in the way: nothing stops, nothing pops up, each step done in
## whatever order you happen to do it (the panel shows the first not done yet),
## each paid for as you do it - its drachmas toward your first ship. First on
## foot (walking, the jet pack, the maps, the scanner, mining, building, selling ore,
## couriering a package, a ride with a local pilot, your first ship), then your
## ship (the controls, undocking, the Hyperion drive, docking, raiders, their
## bounties). Got a ship another way? Once you've flown, docked and fought, it
## ends and pays you everything it would have. F2 hides it (or shows it again).
## Its state is in the save (CosmosGame.extra "tutor"); old saves have none - no tutorial.

## [id, title, what to do, reward (dr), part]
const STEPS := [
	["walk", "Find your feet", "Walk about (W A S D, the mouse to look; Shift to run).", 40, 1],
	["jet", "The jet pack", "Jump (Space), then hold Space in the air: the jet pack lifts you.", 40, 1],
	["map", "The maps", "Open the Automaton (Tab): its MAP tab - the planet, the solar system and the galaxy; turn and zoom them.", 40, 1],
	["scan", "The scanner", "Z (or the scanner in hand - 4 - and a click): ore deposits and veins in the ground near you and the places round you are marked for a minute.", 50, 1],
	["mine", "Mine a deposit", "Walk to a deposit and fire at it (left button): the mining beam cuts its ore. Get 5 units.", 80, 1],
	["build", "Build", "The builder (5): the terrain digger (3) cuts building stone loose as it digs. With the builder in hand, a click lays a foundation where the preview shows green; then a wall on its edge (N: the pieces).", 60, 1],
	["sell", "Sell your ore", "The city's ore buyer, by its landing field, pays for raw ore (click them).", 80, 1],
	["package", "A courier's package", "The courier's office by the field gives you a package to carry to another world or a station.", 60, 1],
	["drop", "Set it down, pick it up", "H sets the package down; H (or a click on it) picks it up again.", 40, 1],
	["ride", "A ride off-world", "The local pilot flies you there for a fee: their ship comes down on the field - walk up its ramp; the passenger seat is beside his, and down the ramp again when it's landed.", 60, 1],
	["deliver", "Deliver it", "Hand the package over where it's going: the courier's office there, or a station's harbour officer.", 150, 1],
	["ship", "Your first ship", "Couriering and ore pay; a station's shipyard (its services hall) sells ships - the cheapest about 13,800 dr.", 1500, 1],
	["controls", "Take the controls", "Up your ship's ramp, forward to the cockpit, click the pilot's seat.", 100, 2],
	["undock", "Undock", "L (or Space) at the controls: up the lift and out.", 100, 2],
	["cruise", "The Hyperion drive", "J: the drive takes you across the system in moments; J again drops out.", 100, 2],
	["dock", "Dock", "Near a station, L asks for a pad: fly over it, line up with it, set down slowly.", 150, 2],
	["recall", "Call your ship", "On foot, B sends your landed ship up to wait in orbit - and B again calls it down to you, wherever you are.", 80, 2],
	["fight", "Raiders", "Destroy two pirate raiders: aim with the mouse, fire with the left button.", 300, 2],
	["bounty", "Bounties", "Hand your bounty vouchers in to a station's harbour officer.", 200, 2],
]

var cosmos: Cosmos
var _panel: PanelContainer
var _reward: Label
var _title: Label
var _text: Label
var _poll := 0.0
var _start := Vector3.INF        # (where you were last frame)
var _walked := 0.0
var _jetted := false


func _ready() -> void:
	layer = 4
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", NeonTheme.box(NeonTheme.HEAD))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -470
	_panel.offset_right = -24
	_panel.offset_top = 96
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", NeonTheme.CYAN)
	box.add_child(_title)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 16)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(420, 0)
	box.add_child(_text)
	_reward = Label.new()   # (what this step pays, and what you've earned of it all)
	_reward.add_theme_font_size_override("font_size", 17)
	_reward.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.custom_minimum_size = Vector2(420, 0)
	box.add_child(_reward)
	_show()


static func state() -> Dictionary:
	return CosmosGame.extra.get("tutor", {})


static func active() -> bool:
	var s := state()
	return not s.is_empty() and not bool(s.get("finished", false))


func _done() -> Dictionary:
	var s := state()
	if not s.has("done"):
		s["done"] = {}
	return s["done"]


func is_done(id: String) -> bool:
	return _done().has(id)


## The first step not done yet: [index, step] (or [-1, []]).
func current() -> Array:
	for i in STEPS.size():
		if not is_done(str(STEPS[i][0])):
			return [i, STEPS[i]]
	return [-1, []]


## A step done (once): its reward paid, the panel on to the next.
func complete(id: String) -> void:
	if not active() or is_done(id):
		return
	for st in STEPS:
		if st[0] == id:
			_done()[id] = true
			CosmosGame.data.add_credits(int(st[3]))
			if cosmos and cosmos.hud:
				cosmos.hud.flash("Tutorial: %s - done (+%d dr)" % [st[1], int(st[3])], 3.5)
	_check_end()
	_show()


func on_event(e: String) -> void:
	if not active():
		return
	var s := state()
	match e:
		"scanned": complete("scan")
		"ore_sold": complete("sell")
		"package_taken": complete("package")
		"box_down":
			s["box_down"] = true
		"box_up":
			if s.get("box_down", false):
				complete("drop")
		"ride_hired", "ride_boarded": complete("ride")
		"package_delivered": complete("deliver")
		"ship_bought":
			_note_other_way()
			complete("ship")
		"at_controls": complete("controls")
		"undocked": complete("undock")
		"docked":
			if is_done("undock"):
				complete("dock")
		"pirate_killed":
			s["kills"] = int(s.get("kills", 0)) + 1
			if int(s["kills"]) >= 2:
				complete("fight")
		"bounty_claimed": complete("bounty")
		"map_opened": complete("map")
		"ship_called": complete("recall")
		"built":
			s["built"] = int(s.get("built", 0)) + 1
			if int(s["built"]) >= 2:
				complete("build")


## Polled twice a second: what's seen rather than told - walking, the jet pack,
## ore in your pack, the drive, a ship got some other way.
func _process(delta: float) -> void:
	if not active():
		if _panel.visible:
			_panel.visible = false
		return
	var w: Node3D = cosmos.walker if cosmos else null
	if w:   # (every frame: the way walked - not a jump of the world's origin - and a moment's jet)
		if _start != Vector3.INF:
			var step := w.global_position.distance_to(_start)
			if step < 5.0:
				_walked += step
		_start = w.global_position
		if w.get("jetting"):
			_jetted = true
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	if _walked > 20.0:
		complete("walk")
	if _jetted:
		complete("jet")
	var comp: Node = cosmos.get("_computer") if cosmos else null
	if comp and is_instance_valid(comp) and comp.visible and int(comp.get("current")) in [1, 2]:
		complete("map")   # (the Automaton open on its MAP tab)
	var ore := 0
	for id in Mining.MINERALS:
		ore += CosmosGame.data.count(id)
	if ore >= 5:
		complete("mine")
	if cosmos and cosmos.ship and cosmos.walker == null and cosmos.ship.cruise == 2:
		complete("cruise")
	if CosmosGame.has_ship() and not is_done("ship"):
		_note_other_way()
		complete("ship")   # (a ship got another way: the rest of the first part skipped - its rewards paid at the end)
	_show()


## It ends once you've done its last step - or have a ship and have flown, docked
## and fought: every reward not yet paid then paid at once.
func _check_end() -> void:
	var s := state()
	if bool(s.get("finished", false)):
		return
	var all: bool = int(current()[0]) == -1
	var learned := bool(s.get("other_way", false)) and is_done("undock") and is_done("dock") and is_done("fight")
	if not (all or learned):
		return
	var owed := 0
	var paid: Dictionary = s.get("paid", {})
	for st in STEPS:
		if not is_done(str(st[0])):
			owed += int(st[3])
			_done()[st[0]] = true
	s["finished"] = true
	if owed > 0:
		CosmosGame.data.add_credits(owed)
	if cosmos and cosmos.hud:
		cosmos.hud.flash("Tutorial complete%s - the sector's yours to explore" % ((" (+%d dr for the steps you went your own way on)" % owed) if owed > 0 else ""), 6.0)


## Your first ship got before the first part's done (bought early, or another way):
## then flying, docking and fighting are all it still asks before it ends.
func _note_other_way() -> void:
	for st in STEPS:
		if int(st[4]) == 1 and st[0] != "ship" and not is_done(str(st[0])):
			state()["other_way"] = true
			return


func toggle() -> void:
	var s := state()
	s["hidden"] = not bool(s.get("hidden", false))
	_show()


func _show() -> void:
	if _panel == null:
		return
	var s := state()
	var c := current()
	_panel.visible = active() and not bool(s.get("hidden", false)) and int(c[0]) >= 0
	if not _panel.visible:
		return
	var st: Array = c[1]
	var part := "on foot" if int(st[4]) == 1 else "your ship"
	_title.text = "Tutorial  ·  %d / %d  ·  %s" % [int(c[0]) + 1, STEPS.size(), st[1]]
	var extra := ""
	if st[0] == "ship":
		extra = "  (%s / 13,800 dr)" % UI.money(int(CosmosGame.data.credits))
	elif st[0] == "fight":
		extra = "  (%d / 2)" % int(s.get("kills", 0))
	_text.text = "%s%s" % [st[2], extra]
	var earned := 0
	var total := 0
	for x in STEPS:
		total += int(x[3])
		if is_done(str(x[0])):
			earned += int(x[3])
	_reward.text = "Reward: %s dr   ·   earned %s of %s dr   ·   %s" % [UI.money(int(st[3])), UI.money(earned), UI.money(total), part]
