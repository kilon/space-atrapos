class_name AttractMode
extends Node
## Attract mode: left alone on the title screen for IDLE seconds, the game
## plays itself - a fresh game where an autopilot flies your ship round the
## system: to the planets (circling them, sometimes landing and walking about
## the village), past the stations, mining asteroids, fighting pirates that
## come near, scanning, and through the jump gates to other systems. "PLEASE
## INSERT DRACHMA" blinks slowly in big gold letters near the bottom (clear of
## the HUD), and the whole window looks like an old CRT (CrtFilter, if
## Settings.crt_attract - the default). Any key, click or real mouse
## movement goes back to the menu.
##
## AttractMode.active (static) lasts across the scene changes (jumps, landing);
## main.gd / planet_surface.gd add a controller (AttractMode.new()) while it's
## on. Nothing is saved; your ship can't be destroyed meanwhile.

const IDLE := 30.0
const MENU := "res://main_menu.tscn"
const GAME := "res://main.tscn"
const TASK_TIME := 22.0             # any task gives up after this long
const SURFACE_TIME := 35.0          # walking about a planet, then take off
const MOVE_TOLERANCE := 6.0         # mouse movement (px) that counts as "the user is back"

static var active := false
static var _ready_at := 0

var host: Node                      # main.gd (space) or planet_surface.gd
var task := ""
var _task_t := 0.0
var _goal: Node2D
var _orbit_a := 0.0
var _visits := 0
var _moved := 0.0
var _walk_t := 0.0
var _label: Control
var _t := 0.0


## Starts it from the title screen: a fresh game, driven.
static func start(tree: SceneTree) -> void:
	active = true
	_ready_at = Time.get_ticks_msec() + 1200   # (ignore input as the scene changes)
	var sg := tree.root.get_node_or_null("SaveGame")
	if sg:
		sg.pending = {}
		sg.travelling = false
	tree.change_scene_to_file(GAME)


## Back to the title screen.
static func stop(tree: SceneTree) -> void:
	if not active:
		return
	active = false
	tree.paused = false
	var sg := tree.root.get_node_or_null("SaveGame")
	if sg:
		sg.pending = {}
		sg.travelling = false
		sg.landed_planet = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.change_scene_to_file(MENU)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_banner()
	if host.get("ship") != null:   # space
		var ship: Node2D = host.ship
		ship.invulnerable = true
		host.set("_zoom", 0.75)
		if host.get("hud") and host.hud.get("hint"):
			host.hud.hint.visible = false


func _build_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_label = Banner.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom centre, above the toolbar (and clear of the event log on the left).
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -440
	_label.offset_right = 440
	_label.offset_top = -265
	_label.offset_bottom = -132
	layer.add_child(_label)


## The user is back: any key, click or real mouse movement.
func _input(event: InputEvent) -> void:
	if Time.get_ticks_msec() < _ready_at:
		return
	var back := false
	if event is InputEventKey and event.pressed:
		back = true
	elif event is InputEventMouseButton and event.pressed:
		back = true
	elif event is InputEventJoypadButton and event.pressed:
		back = true
	elif event is InputEventMouseMotion:
		_moved += event.relative.length()
		back = _moved > MOVE_TOLERANCE
	if back:
		get_viewport().set_input_as_handled()
		AttractMode.stop(get_tree())


func _process(delta: float) -> void:
	_t += delta
	_moved = maxf(0.0, _moved - delta * 20.0)   # (tiny jitters fade away)
	# A slow blink: fading in and out over two and a half seconds.
	_label.modulate.a = 0.15 + 0.85 * pow(0.5 + 0.5 * sin(_t * TAU / 2.5), 1.5)
	if get_tree().paused:
		_unpause()
	if host.get("ship") != null:
		_drive_space(delta)
	elif host.get("pilot") != null:
		_drive_surface(delta)


## A dialogue or panel popping up mid-demo: close it.
func _unpause() -> void:
	for n in get_tree().get_nodes_in_group("dialogue_boxes"):
		if n.visible and n.has_method("_finish"):
			n._finish()
	var d = host.get("quest")
	if d and d.get("dialogue") and d.dialogue.visible:
		d.dialogue._finish()
	get_tree().paused = false


# --- In space ------------------------------------------------------------------------------

func _drive_space(delta: float) -> void:
	var ship: Node2D = host.ship
	if not ship.is_alive() or host.get("site") != null:
		return
	_task_t += delta
	# Pirates close by: fight them.
	if task != "fight":
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.is_alive() and e.global_position.distance_to(ship.global_position) < 900.0:
				_begin("fight", e)
				ship.set_attack_target(e, true)
				break
	if task == "" or _task_t > TASK_TIME:
		_next_task()
	match task:
		"fight":
			if not is_instance_valid(_goal) or not _goal.is_alive():
				_next_task()
		"planet", "station":
			if not is_instance_valid(_goal):
				_next_task()
				return
			var c: Vector2 = _goal.global_position
			var r: float = float(_goal.get("radius")) * 1.6 + 260.0 if _goal.get("radius") != null else 500.0
			if ship.global_position.distance_to(c) > r + 400.0:
				ship.move_to(c + (ship.global_position - c).normalized() * r)
			else:   # circle it
				_orbit_a += delta * 0.35
				ship.move_to(c + Vector2.from_angle(_orbit_a) * r)
				if task == "planet" and _task_t > 9.0 and _goal.get("landable") and _visits % 3 == 1:
					task = "landing"
					host.land_on(_goal.planet_id)
		"mine":
			if not is_instance_valid(_goal) or not _goal.is_alive():
				_next_task()
		"gate":
			if not is_instance_valid(_goal):
				_next_task()
				return
			ship.move_to(_goal.global_position)
			if ship.global_position.distance_to(_goal.global_position) < 700.0:
				task = "jumping"
				host.jump_to(_goal.target)


func _begin(t: String, goal: Node2D) -> void:
	task = t
	_goal = goal
	_task_t = 0.0


## The next thing to do: mostly planets and stations, now and then a rock,
## a scan, or a gate to the next system.
func _next_task() -> void:
	var ship: Node2D = host.ship
	ship.set_attack_target(null)
	_visits += 1
	var roll := _visits % 7
	var pick: Node2D = null
	if roll == 6:
		pick = _random_in("gates")
		if pick:
			_begin("gate", pick)
			return
	if roll == 3:
		pick = _nearest_in("asteroids", ship.global_position)
		if pick:
			_begin("mine", pick)
			ship.set_attack_target(pick, true)
			pick.scanned = true
			ship.mining_auto = true   # (the autopilot keeps the laser's heat in the band: Mining)
			return
	if roll in [2, 5]:
		pick = _random_in("stations")
		if pick:
			_begin("station", pick)
			return
	var planets := get_tree().get_nodes_in_group("planet_bodies").filter(func(b): return b.parent_body == null)
	if not planets.is_empty():
		_begin("planet", planets.pick_random())
		_orbit_a = (ship.global_position - _goal.global_position).angle()
		return
	_begin("station", _random_in("stations"))


func _random_in(group: String) -> Node2D:
	var all := get_tree().get_nodes_in_group(group)
	return all.pick_random() if not all.is_empty() else null


func _nearest_in(group: String, p: Vector2) -> Node2D:
	var best: Node2D = null
	for n in get_tree().get_nodes_in_group(group):
		if best == null or p.distance_to(n.global_position) < p.distance_to(best.global_position):
			best = n
	return best


# --- On a planet ---------------------------------------------------------------------------

func _drive_surface(delta: float) -> void:
	var pilot: Node2D = host.pilot
	if pilot == null or not host.has_method("_walk_to"):
		return
	_task_t += delta
	if _task_t > SURFACE_TIME:
		_task_t = -INF
		host.take_off()
		return
	_walk_t -= delta
	if _walk_t <= 0.0 or (not pilot.moving and _walk_t < 4.0):
		_walk_t = randf_range(5.0, 8.0)
		for k in 12:   # somewhere open, a little way off
			var p: Vector2 = pilot.position + Vector2.from_angle(randf() * TAU) * randf_range(300.0, 700.0)
			if host.walkable_at(p):
				host._walk_to(p)
				break


## "PLEASE INSERT DRACHMA" the 80s arcade way - blocky letters on an 8 x 8 pixel
## grid like an "INSERT COIN" - but styled as ancient Greek: Λ for A, Σ for E,
## Δ for D, a squared S and C, between two bands of meander (Greek key). Drawn
## pixel by pixel; the rows shade from pale gold down to orange, with a hard shadow.
class Banner extends Control:
	const TEXT := "PLEASE INSERT DRACHMA"
	const PX := 5.0                 # screen pixels per letter pixel
	const BAND_PX := 3.0            # ... per meander pixel
	const GAP := 14.0
	const ROWS := [Color(1.0, 0.96, 0.62), Color(1.0, 0.9, 0.42), Color(1.0, 0.82, 0.25),
			Color(1.0, 0.74, 0.16), Color(0.98, 0.64, 0.1), Color(0.93, 0.52, 0.06), Color(0.86, 0.42, 0.04)]
	const SHADOW := Color(0.3, 0.1, 0.0)
	const GLYPHS := {
		"A": ["...#...", "..###..", ".##.##.", ".##.##.", "##...##", "##...##", "##...##"],
		"C": [".######", "##.....", "##.....", "##.....", "##.....", "##.....", ".######"],
		"D": ["...#...", "..###..", ".##.##.", ".##.##.", "##...##", "##...##", "#######"],
		"E": ["#######", "##.....", ".##....", "..##...", ".##....", "##.....", "#######"],
		"H": ["##...##", "##...##", "##...##", "#######", "##...##", "##...##", "##...##"],
		"I": [".#####.", "..##...", "..##...", "..##...", "..##...", "..##...", ".#####."],
		"L": ["##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "#######"],
		"M": ["##...##", "###.###", "#######", "##.#.##", "##...##", "##...##", "##...##"],
		"N": ["##...##", "###..##", "####.##", "##.####", "##..###", "##...##", "##...##"],
		"P": ["#######", "##...##", "##...##", "#######", "##.....", "##.....", "##....."],
		"R": ["#######", "##...##", "##...##", "#######", "##.##..", "##..##.", "##...##"],
		"S": ["#######", "##.....", "##.....", "#######", ".....##", ".....##", "#######"],
		"T": ["#######", "..###..", "..###..", "..###..", "..###..", "..###..", "..###.."],
	}
	# One turn of the meander, repeated along the band.
	const KEY := ["######", ".....#", ".###.#", ".#...#", ".#####", "......"]

	func _draw() -> void:
		var text_w := (TEXT.length() * 8 - 1) * PX
		var units := int(floor(text_w / (6.0 * BAND_PX)))
		var band_w := units * 6 * BAND_PX
		var band_h := 6 * BAND_PX
		var x0 := (size.x - text_w) * 0.5
		var y := 0.0
		for pass_i in 2:   # the shadow, then the letters
			var off := Vector2(PX, PX) if pass_i == 0 else Vector2.ZERO
			_band(Vector2((size.x - band_w) * 0.5, y) + off, units, pass_i == 0, false)
			var ty := y + band_h + GAP
			for i in TEXT.length():
				var g: Array = GLYPHS.get(TEXT[i], [])
				for r in g.size():
					var c: Color = SHADOW if pass_i == 0 else ROWS[r]
					for k in 7:
						if g[r][k] == "#":
							draw_rect(Rect2(Vector2(x0 + (i * 8 + k) * PX, ty + r * PX) + off, Vector2(PX, PX)), c)
			_band(Vector2((size.x - band_w) * 0.5, ty + 7 * PX + GAP) + off, units, pass_i == 0, true)

	func _band(at: Vector2, units: int, shadow: bool, flip: bool) -> void:
		var c := SHADOW if shadow else Color(0.95, 0.7, 0.2)
		for u in units:
			for r in 6:
				var row: String = KEY[5 - r if flip else r]
				for k in 6:
					if row[k] == "#":
						draw_rect(Rect2(at + Vector2((u * 6 + k) * BAND_PX, r * BAND_PX), Vector2(BAND_PX, BAND_PX)), c)
