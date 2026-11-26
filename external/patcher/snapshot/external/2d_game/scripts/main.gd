extends Node2D

const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

@export var enemy_count := 6
## Neutral (civilian) ships flying between stations.
@export var neutral_count := 5
@export var neutral_respawn_delay := 20.0
## Asteroid fields: centres, field radius, rocks per field, respawn delay.
@export var asteroid_fields: Array[Vector2] = [
	Vector2(-1600, -2000), Vector2(2800, -200), Vector2(500, 2900),
	Vector2(-4700, 1300), Vector2(3000, 4700)]
@export var asteroid_field_radius := 650.0
@export var asteroids_per_field := 8
@export var respawn_delay := 6.0
## Enemies spawn between these distances from the player.
@export var spawn_distance := Vector2(1300, 2600)

## Loot table: [item id, weight, amount]. Bigger enemies roll more often and
## have better odds for the rare entries (see _drop_loot).
const LOOT := [
	["scrap", 40, 1],
	["energy_cell", 25, 1],
	["missile", 14, 3],
	["alien_alloy", 10, 1],
	["repair_kit", 7, 1],
	["data_core", 3, 1],
]
## Chance that each loot roll actually drops an item.
const ITEM_DROP_CHANCE := 0.6
const LOOT_ROLLS_MAX := 10

var kills := 0
var _drag_moves := false  # true while the left button is held to steer
## A press shorter than this is a click ("fly to this point"); longer is
## steering ("fly toward the cursor until released").
const CLICK_MAX_MS := 250
var _press_time := 0
var _press_point := Vector2.ZERO
var _last_mouse_screen := Vector2.ZERO  # last mouse position (viewport coords)
var _dock_station: Node2D = null  # station close enough to dock at
var _dock_on_arrival: Node2D = null  # station clicked: dock when we get there

@onready var ship: Node2D = $Ship
@onready var marker: Node2D = $TargetMarker
@onready var enemies: Node2D = $Enemies
@onready var neutrals: Node2D = $Neutrals
@onready var asteroids: Node2D = $Asteroids
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: Control = $PauseLayer/PauseMenu
@onready var player_data: Node = $PlayerData
@onready var ship_menu: Control = $Panels/ShipMenu
@onready var station_menu: Control = $Panels/StationMenu
@onready var missions: Node = $Missions
@onready var quest: Node = $Quest
var scenario_host: Node

## New-game start: a spot where Amnissos (landable) sits in the middle of the
## screen. The planet layer scrolls at 1/4 speed and repeats every 2600 px,
## so such spots are ~10400 units apart; this one is near Kephala Outpost,
## where the main quest begins, and next to an asteroid field.
const START_POSITION := Vector2(3760, 4400)

## Sandbox: trader ships flown in this system (Galaxy record id -> ship).
var _trader_ships := {}
var _gate_prompted: Node2D = null
var _arrived_by_jump := false
var _system_label: Label
## Home-system planets in world space: [planet id, orbit radius, phase, size, moon of].
const HOME_ORBITS := [["akrotiri", 4300.0, 5.6, 520.0, ""], ["thalassa", 6400.0, 0.864, 760.0, ""], ["selene", 720.0, 1.0, 230.0, "thalassa"],
	["krystallos", 8400.0, 3.7, 560.0, ""], ["kronos", 9900.0, 5.2, 1500.0, ""]]
var level_editor: LevelEditor
## Saved start layout for new games (Level Editor > Save layout).
const SPACE_LAYOUT := "res://data/space.json"

## Per-planet surface state, e.g. {"thalassa": {"searched": [0, 2]}}.
var planet_state := {}
const SURFACE_SCENE := "res://scenes/planet_surface.tscn"


## Built a piece a frame when a scene change asks for it (UI.staging, set by
## UI.switch_scene: under its black fade or the loading veil) instead of in
## one long frame (a new game's first: 225 ms - everything made, processed
## and drawn for the first time at once; a jump: 45 ms): the world stays
## hidden and still (process off) while its pieces are made (_stage: the
## next frame), then its layers come into view one a frame (their first
## drawing spread out too), then it starts to run - build_settled() from
## then on. Built directly (tests, the editor's play): all at once, as before.
var _staged := false
var _settled := true
var _mode_was := Node.PROCESS_MODE_INHERIT


func build_settled() -> bool:
	return _settled


## A staged build's next piece: on to the next frame once this frame's share
## (STAGE_US) is used - several small pieces a frame, a big one alone (nothing
## when built at once).
const STAGE_US := 3000
var _stage_slice := 0

func _stage() -> void:
	if _staged and is_inside_tree() and Time.get_ticks_usec() - _stage_slice >= STAGE_US:
		await get_tree().process_frame
		_stage_slice = Time.get_ticks_usec()


# --- The system streamed in, piece by piece ------------------------------------
## A system's pieces - each planet and moon, station, gate, the nav beacon,
## each nebula, the far planets, every ship and monster, each field of rocks,
## the mining crew - are jobs in a queue, made nearest to your ship first, as
## many a frame as fit in PIECES_US, each fading in as it comes; the scene runs
## meanwhile (you fly from the start). One that needs another (a moon its
## planet, the miners their rocks) waits for it. Built directly (tests, the
## editor's play) a piece is made at once. Each one in is noted in the loading
## console.
const PIECES_US := 2500
var _stream_pieces := false
var _pieces: Array = []      # {key, what, at: Vector2, run: Callable, needs: Callable}
var _pieces_total := 0
var _pieces_done := 0


## A piece of the system: made now (built directly), or queued.
func _piece(key: String, what: String, at: Vector2, run: Callable, needs := Callable()) -> void:
	if not _stream_pieces:
		run.call()
		return
	_pieces.append({"key": key, "what": what, "at": at, "run": run, "needs": needs})
	_pieces_total += 1


## The pieces whose key starts with `prefix` made at once (the gate you come out of, say).
func _pieces_now(prefix: String) -> void:
	for p in _pieces.duplicate():
		if str(p["key"]).begins_with(prefix) and (not p["needs"].is_valid() or p["needs"].call()):
			_pieces.erase(p)
			_make_piece(p)


## Any piece whose key starts with `prefix` still to come.
func pieces_pending(prefix: String) -> bool:
	for p in _pieces:
		if str(p["key"]).begins_with(prefix):
			return true
	return false


## How far the system's streaming is: [pieces in, of all] (the loading console).
func stream_progress() -> Vector2i:
	return Vector2i(_pieces_done, _pieces_total)


## Each frame (once the scene runs): the nearest pieces made, within PIECES_US.
func _pump_pieces() -> void:
	if _staged or _pieces.is_empty() or not is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	var here: Vector2 = ship.global_position if is_instance_valid(ship) else Vector2.ZERO
	while not _pieces.is_empty() and Time.get_ticks_usec() - t0 < PIECES_US:
		var best := -1
		var best_d := INF
		for i in _pieces.size():
			var p: Dictionary = _pieces[i]
			if p["needs"].is_valid() and not p["needs"].call():
				continue
			var d: float = (p["at"] as Vector2).distance_squared_to(here)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		_make_piece(_pieces.pop_at(best))
	if _pieces.is_empty():
		AssetPool.note("%s system: all %d pieces in" % [Galaxy.SYSTEMS[Galaxy.current_system]["name"], _pieces_total])


var _made: Array = []

func _catch_made(n: Node) -> void:
	var p := n.get_parent()
	if n is CanvasItem and p != null and (p == self or p.get_parent() == self or (p.get_parent() and p.get_parent().get_parent() == self)):
		_made.append(n)


## One piece made; what it put in the world fades in.
func _make_piece(p: Dictionary) -> void:
	_made = []
	var fade := not _staged and is_inside_tree()
	if fade:
		get_tree().node_added.connect(_catch_made)
	p["run"].call()
	if fade:
		get_tree().node_added.disconnect(_catch_made)
		for n in _made:
			if is_instance_valid(n) and n.is_inside_tree() and (n as CanvasItem).visible and not _made.has(n.get_parent()):
				var c := n as CanvasItem
				var a := c.modulate.a
				c.modulate.a = 0.0
				# (the scene's tween, not the piece's: a piece that stops itself off
				# screen - a rock's VisibleOnScreenEnabler2D - would stop its own fade
				# at nothing and never be seen)
				create_tween().tween_property(c, "modulate:a", a, 0.4)
	_made = []
	_pieces_done += 1
	if p["what"] != "":
		AssetPool.note("%s: %s in" % [Galaxy.SYSTEMS[Galaxy.current_system]["name"], p["what"]])


var _held: Array = []

## (staged build) A piece just made in one of the world's layers: hidden till _stage_end.
func _hold_staged(n: Node) -> void:
	var p := n.get_parent()
	# (a piece in one of the world's layers, or one put straight in the scene -
	# a gate, the nav beacon, the star and its system, the far planets)
	if n is CanvasItem and p != null and (n as CanvasItem).visible \
			and ((p.get_parent() == self and p is CanvasItem) or (p == self and n is Node2D)):
		(n as CanvasItem).visible = false
		_held.append([n, n.process_mode])
		n.process_mode = Node.PROCESS_MODE_DISABLED   # (still till it's shown: the scene runs while they're revealed)


var _stage_t0 := 0
var _stage_frames := 0
## How long the last staged build took (ms, frames): the loading console reports it.
var stage_ms := 0.0


func _stage_begin() -> void:
	_stage_t0 = Time.get_ticks_usec()
	_stage_slice = _stage_t0
	_stage_frames = Engine.get_process_frames()
	_staged = true
	_settled = false
	_mode_was = process_mode
	process_mode = Node.PROCESS_MODE_DISABLED
	# (In view as it's built - the ship, the HUD and the stars at once, no
	# loading screen or black screen; the system's pieces - stations, planets,
	# rocks, ships - held back as they're made and shown a few a frame at the
	# end, their first drawing spread out: all at once was a 46 ms frame.)
	_held = []
	get_tree().node_added.connect(_hold_staged)


## The staged build's end: the world's layers shown one a frame, then it runs.
func _stage_end() -> void:
	if not _staged:
		return
	# (A layer's own children a few a frame too: stations, planets, rocks,
	# ships - each draws for the first time.)
	if get_tree().node_added.is_connected(_hold_staged):
		get_tree().node_added.disconnect(_hold_staged)
	var held := _held
	_held = []
	visible = true
	# The scene runs from here: you fly while the pieces come into view (each
	# still till it's shown).
	process_mode = _mode_was
	_staged = false
	stage_ms = (Time.get_ticks_usec() - _stage_t0) / 1000.0
	var frames := Engine.get_process_frames() - _stage_frames
	await get_tree().process_frame
	var per := 1 if held.size() <= 24 else ceili(held.size() / 24.0)
	var n := 0
	for k in held:
		if is_instance_valid(k[0]):
			k[0].process_mode = k[1]
			k[0].visible = true
		n += 1
		if n % per == 0:
			await get_tree().process_frame
	AssetPool.note("%s system: flying after %d ms (%d frames); %d pieces to stream in round you" % [Galaxy.SYSTEMS[Galaxy.current_system]["name"], roundi(stage_ms), frames, _pieces.size()])
	while not _pieces.is_empty() and is_inside_tree():
		await get_tree().process_frame
	if get_tree().process_frame.is_connected(_pump_pieces):
		get_tree().process_frame.disconnect(_pump_pieces)
	await ship_menu.prewarm()   # (the Ship Computer's window and its first pages, made now - not at the first Tab / M / G)
	await get_tree().process_frame
	_settled = true


func _ready() -> void:
	if UI.staging:
		_stage_begin()
		_stream_pieces = true
		get_tree().process_frame.connect(_pump_pieces)
	RepairArt.warm()   # (the Repair Bay's pictures, loaded in the background)
	add_to_group("steering")   # (release_steering: a dialogue opening frees the mouse)
	# The Ship Computer and a station's window cover the screen: the space
	# behind them shown as a picture while they're open (MenuBackdrop).
	MenuBackdrop.watch(ship_menu, self)
	MenuBackdrop.watch(station_menu, self)
	# Sandbox galaxy: a new game starts a fresh one; loading a save restores
	# it (load_save_data); landing / jumping keeps the running simulation.
	var new_game := SaveGame.pending.is_empty() and not SaveGame.travelling
	if SaveGame.travelling and Galaxy.systems.is_empty():
		Galaxy.new_game(false)   # (taking off from a surface scene run on its own: no galaxy yet - one now)
	if new_game and Galaxy.prepared:
		Galaxy.prepared = false   # (made behind the loading screen: Galaxy.new_game_async)
	elif new_game:
		Galaxy.new_game()
	elif not SaveGame.travelling and not SaveGame.pending.has("galaxy"):
		Galaxy.new_game(false)   # an older save
	elif not SaveGame.travelling:
		Galaxy.load_save_data(SaveGame.pending["galaxy"])
	Galaxy.active = true
	var tips := PinTips.install(self, "space", EditorDocs.GAME)
	tips.f1_page = func() -> String:
		return "stations" if station_menu.visible else ("computer" if ship_menu.visible else "space")
	await _stage()
	await _build_system()
	await _stage()
	# (A fight's first explosion: its sounds and shaders ready beforehand.)
	Sfx.warm("space")
	(func(): Effects.warm(ship.global_position)).call_deferred()
	Galaxy.news_posted.connect(_on_news)
	Galaxy.trader_appeared.connect(_spawn_trader_ship)
	Galaxy.politics_changed.connect(_update_system_label)
	Fleets.fleet_arrived.connect(_on_fleet_arrived)
	Galaxy.station_destroyed.connect(_on_station_destroyed)
	ship.arrived.connect(marker.hide_marker)
	ship.waypoint_passed.connect(func(): marker.show_at(ship.target))   # (the marker moves on along the course)
	ship.destroyed.connect(_on_player_destroyed)
	ship.player_data = player_data
	hud.bind(ship, player_data)
	# Near death: the window fails like a broken monitor (DamageScreen).
	damage_screen = DamageScreen.new()
	damage_screen.health = func(): return ship.hull / maxf(1.0, ship.max_hull) if ship.is_alive() else 1.0
	add_child(damage_screen)
	hud.toolbar.slot_pressed.connect(activate_slot)
	for panel in [ship_menu, station_menu]:
		panel.data = player_data
		panel.ship = ship
	station_menu.missions = missions
	station_menu.quest = quest
	station_menu.undocked.connect(_on_undocked)
	ship.attacked.connect(close_menus_on_hit)
	level_editor = LevelEditor.new()
	level_editor.host = self
	$Panels.add_child(level_editor)
	hud.bind_missions(missions)
	await _stage()
	# Main quest: the Labyrinth ruin, the quest runner and its dialogue box.
	if Galaxy.current_system == Galaxy.HOME:
		var lab := Node2D.new()
		lab.set_script(preload("res://scripts/labyrinth.gd"))
		lab.position = QuestData.LABYRINTH
		add_child(lab)
	quest.main = self
	quest.dialogue = $Panels/Dialogue
	hud.bind_quest(quest)
	# The ship's scanner (right-click).
	scanner = ShipScanner.new()
	scanner.ship = ship
	scanner.minimap = hud.minimap
	scanner.main = self
	add_child(scanner)
	# The probe scanner (equipment; its probes on the system map: ProbeScanner).
	probes = ProbeScanner.new()
	probes.main = self
	probes.ship = ship
	add_child(probes)
	# Quest scenarios (rules made in Talos's Scenario Editor).
	scenario_host = preload("res://scripts/scenario_host.gd").new()
	scenario_host.name = "ScenarioHost"
	scenario_host.main = self
	add_child(scenario_host)
	await _stage()
	# "LAND" buttons over the planets in the background.
	var landing := preload("res://scripts/landing_ui.gd").new()
	landing.main = self
	hud.add_child(landing)
	# The planet card (bottom right): the planet under the mouse or close by.
	planet_card = PlanetCard.new()
	planet_card.main = self
	hud.add_child(planet_card)
	hud._apply_text_size()
	# Tech changes ship stats (also re-applied when a save loads).
	player_data.changed.connect(ship.apply_tech)
	# Pre-compile GPU pipelines so nothing hitches the first time it appears.
	var warmup := preload("res://scripts/warmup.gd").new()
	ship.add_child(warmup)
	await _stage()

	if not SaveGame.pending.is_empty():
		_arrived_by_jump = SaveGame.pending.get("jumped", false)
		# A save made on a planet: back down there once the game is loaded.
		var landed: Dictionary = SaveGame.pending.get("landed", {}) if not SaveGame.travelling else {}
		var raw: Dictionary = SaveGame.pending
		load_save_data(SaveGame.pending)
		SaveGame.pending = {}
		if not landed.is_empty() and Planets.get_planet(str(landed.get("planet", ""))).size() > 0 and get_tree().current_scene == self:
			var space := raw.duplicate()
			space.erase("landed")
			SaveGame.space_state = space   # (in orbit here when you take off)
			SaveGame.landed_planet = str(landed["planet"])
			SaveGame.resume = landed
			SaveGame.travelling = true
			get_tree().change_scene_to_file.call_deferred(SURFACE_SCENE)
			_settled = true
			return
		if SaveGame.travelling and not _arrived_by_jump:
			GameLog.post("Back in orbit.", "mission")
			if SaveGame.took_off_from != "":
				_take_off_animation(SaveGame.took_off_from)
				SaveGame.took_off_from = ""
	else:
		# New game: start in orbit in front of Amnissos (landable), near
		# Kephala Outpost. Quests are picked up at stations.
		ship.global_position = START_POSITION
		for o in HOME_ORBITS:
			if o[0] == "thalassa":   # (from its orbit: its piece may not be made yet)
				ship.global_position = _orbit_at(o[1], o[2], false, Vector2.ZERO) + Vector2(420, -520)
		$Ship/Camera2D.reset_smoothing()
		GameLog.post("You're in orbit above Amnissos - click LAND and talk to Kilon Alios by the landing pad: he has the main quest. Stations nearby offer missions (look for the yellow triangle).", "mission")
		var layout := DataFiles.read(SPACE_LAYOUT)
		await _stage()
		if not layout.is_empty():
			_spawn_layout(layout)  # designed in the level editor
			_populate_system(false, false, false)
		else:
			_populate_system(true, true, true)
		_spawn_mining_crew()
	await _stage()
	# (the traders under way here: at stations and gates - after them)
	_piece("traders", "the traders under way", ship.global_position + Vector2(5000, 0), _spawn_live_traders,
		func(): return not pieces_pending("station:") and not pieces_pending("gate:"))
	if SaveGame.travelling and Galaxy.route.size() >= 2 and Galaxy.route[0] == Galaxy.current_system:
		var gate: Vector2 = Galaxy.system(Galaxy.current_system)["gates"][Galaxy.route[1]]
		ship.move_to(gate)
		marker.show_at(gate)
		GameLog.post("Route: course set to the %s gate (%d jumps left)" % [Galaxy.SYSTEMS[Galaxy.route[1]]["name"], Galaxy.route.size() - 1], "mission")
	elif SaveGame.travelling and Galaxy.route.size() == 1:
		Galaxy.route = []
		GameLog.post("Route complete: you have arrived in %s." % Galaxy.SYSTEMS[Galaxy.current_system]["name"], "good")
	if SaveGame.travelling and _arrived_by_jump:
		_pieces_now("gate:")   # (the gates at once: you come out of one)
		var came := _nearest_gate()   # (you come out of the gate back to where you were)
		if came:
			came.flash()
		GameLog.post("Arrived in the %s system  ·  %s" % [Galaxy.SYSTEMS[Galaxy.current_system]["name"], Galaxy.empire_name(Galaxy.owner_of(Galaxy.current_system))], "mission")
	var arrived := SaveGame.travelling and _arrived_by_jump
	SaveGame.travelling = false
	if arrived:   # (a new system: autosaved once you're through)
		get_tree().create_timer(2.0).timeout.connect(SaveGame.autosave.bind("arrived in " + str(Galaxy.system(Galaxy.current_system).get("name", ""))))
	if new_game:
		Scenarios.new_game()
		Scenarios.event("entered", {"system": Galaxy.current_system})
	elif _arrived_by_jump:
		Scenarios.event("entered", {"system": Galaxy.current_system})
	scenario_host.objectives_changed()
	TalosNav._warm.call_deferred()   # (Talos's scenes loading in the background: F8 opens it at once)
	if AttractMode.active:   # (the title screen's attract mode: an autopilot plays)
		var a := AttractMode.new()
		a.host = self
		add_child(a)
	_stage_end()


# --- Enemies -----------------------------------------------------------------

## Spawns an AI ship. Its type (from `type_id`, the save data, or a random
## hostile class) decides whether it joins the enemies or the neutrals.
func spawn_ship(at: Vector2, type_id := "", data := {}, empire := "") -> Node2D:
	var s := ENEMY_SCENE.instantiate()
	s.position = at
	if not data.is_empty():
		s.load_save_data(data)
	if type_id != "":
		s.type_id = type_id
	elif not data.has("type"):
		s.type_id = _pick_enemy_type()
	if empire != "":
		s.empire = empire
	elif s.empire == "":
		# A ship flies for whoever its design belongs to: a civilian for its
		# design's empire (an unclaimed design: an independent); plain
		# hostiles are Sea Peoples raiders - a random one in a raider's design.
		var neutral_type: bool = EnemyTypes.get_type(s.type_id).get("faction", "enemy") == "neutral"
		if neutral_type:
			s.empire = ShipDesigns.owner_of(s.type_id)
			if s.empire == "" or s.empire == "pirates":
				s.empire = "independent"
		else:
			s.empire = "pirates"
			if type_id == "" and not data.has("type") and ShipDesigns.owner_of(s.type_id) not in ["pirates", ""]:
				var pirate := ShipDesigns.pick("pirates", [EnemyTypes.get_type(s.type_id).get("class", "fighter")])
				if pirate != "":
					s.type_id = pirate
	if s.empire != "pirates" and s.cargo.is_empty() and EnemyTypes.get_type(s.type_id).get("role", "") in ["trader", "miner"]:
		_random_cargo(s)
	s.died.connect(_on_ship_died)
	(enemies if s.empire == "pirates" else neutrals).add_child(s)
	return s


func spawn_enemy(at: Vector2, data := {}) -> Node2D:
	return spawn_ship(at, "", data)


func _random_cargo(s: Node2D) -> void:
	var goods: Array = Galaxy.COMMODITIES.slice(0, 11)
	for i in randi_range(1, 2):
		var c: String = goods.pick_random()
		s.cargo[c] = s.cargo.get(c, 0) + randi_range(5, 20)


## A passing civilian: mostly the system owner's, often an independent, now
## and then a visitor from another empire - in its own empire's design.
func spawn_neutral(at: Vector2) -> Node2D:
	var o := Galaxy.owner_of(Galaxy.current_system)
	if o == "pirates":
		o = Galaxy.HOME_EMPIRE
	var r := randf()
	var e: String = o if r < 0.65 else ("independent" if r < 0.9 else Galaxy.MAJOR.filter(func(m): return m != o).pick_random())
	var role: String = ["trader", "trader", "trader", "miner", "explorer"].pick_random()
	var id := ShipDesigns.pick(e, [role])
	if id == "":
		id = EnemyTypes.neutral_ids().pick_random()
		e = ""
	return spawn_ship(at, id, {}, e)


func spawn_asteroid(data: Dictionary) -> Node2D:
	var rock := Asteroid.new().setup(data)
	asteroids.add_child(rock)
	return rock


## A free spot inside an asteroid field (not overlapping other rocks).
func _asteroid_spot(field: Vector2) -> Vector2:
	var spot := field
	for attempt in 12:
		spot = field + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * asteroid_field_radius
		var clear := true
		for rock in asteroids.get_children():
			if rock.global_position.distance_to(spot) < 200.0:
				clear = false
				break
		if clear:
			break
	return spot


func _asteroid_at(point: Vector2) -> Node2D:
	for rock in asteroids.get_children():
		if rock.is_alive() and point.distance_to(rock.global_position) < rock.click_radius:
			return rock
	return null


## Somewhere just outside a random station (neutrals start/return there).
func _station_spawn_point() -> Vector2:
	var st: Node2D = get_tree().get_nodes_in_group("stations").pick_random()
	return st.global_position + Vector2.from_angle(randf() * TAU) * (st.radius + randf_range(200, 500))


## A random ship type that isn't already flying around, so every enemy on
## screen looks different (falls back to any type if all are in use).
func _pick_enemy_type() -> String:
	# Ship classes wanted by hunt missions turn up more often.
	var wanted: Array = missions.wanted_types()
	if not wanted.is_empty() and randf() < 0.5:
		return wanted.pick_random()
	var raiders: Array = EnemyTypes.ids().filter(func(id): return ShipDesigns.owner_of(id) == "pirates")
	var unused: Array = raiders.duplicate()
	for enemy in enemies.get_children():
		unused.erase(enemy.type_id)
	return (unused if not unused.is_empty() else raiders).pick_random()


func _random_spawn_point(min_dist := spawn_distance.x) -> Vector2:
	var dist := randf_range(min_dist, spawn_distance.y)
	# (In a signal site, the system's pirates turn up out in the system, round its beacon.)
	var around: Vector2 = site.return_point if site != null else ship.global_position
	return around + Vector2.from_angle(randf() * TAU) * dist


func _on_ship_died(s: Node2D) -> void:
	var by_player: bool = is_instance_valid(s.last_attacker) and s.last_attacker == ship
	# Wrecks always drop loot - even from fights between other ships.
	# Shields count toward how tough (and rewarding) the ship was.
	_drop_loot(s.global_position, s.max_hull + s.max_shields * 0.5)
	# What's left of it: a wreck to salvage (not of creatures).
	if not s.is_creature() and not s.body.has_node("Monster"):
		Wreck.spawn(self, s.global_position, s.body.texture, s.body.global_scale, s.body.global_rotation,
			{"kind": "ship", "title": s.display_name, "empire": s.empire, "toughness": s.max_hull + s.max_shields * 0.5, "electro": s.electro, "weapons": s.loadout})
	# Whatever was in its hold spills out (pirates drop what they stole).
	for c in s.cargo:
		var n: int = int(s.cargo[c] * randf_range(0.5, 0.9))
		if n > 0:
			Pickup.spawn(get_tree(), s.global_position + Vector2.from_angle(randf() * TAU) * 40.0, c, n)
	if s.record_id != "":
		_trader_ships.erase(s.record_id)
		Galaxy.trader_destroyed(s.record_id)
	if s.fleet_id != "":
		Fleets.ship_lost(s.fleet_id)
	if by_player:
		if s.empire == "pirates":
			# Bounty from the system's owner (bigger during Pirate Raids).
			var owner := Galaxy.owner_of(Galaxy.current_system)
			if owner != "pirates":
				var bounty := Galaxy.pirate_bounty(s.max_hull, s.max_shields)
				if Galaxy.state_of(Galaxy.current_system) == "pirate_raids":
					bounty = roundi(bounty * 1.6)
				bounty = roundi(bounty * Galaxy.bounty_bonus(owner))
				player_data.add_credits(bounty)
				GameLog.post("Bounty: +%d dr from the %s" % [bounty, Galaxy.empire_name(owner)], "good")
			Galaxy.change_reputation(owner, 2.0)
		elif s.empire != "":
			# Their ship destroyed: they think less of you (a ship at a time -
			# it takes several to make an enemy); their war enemies a little
			# more; and a civilian shot down in someone's space is lawlessness
			# its owner frowns on (unless they're at war with the victim).
			Galaxy.change_reputation(s.empire, Galaxy.REP_KILL, "you destroyed one of their ships")
			for e in Galaxy.MAJOR:
				if Galaxy.at_war(e, s.empire):
					Galaxy.change_reputation(e, 2.0)
			var here := Galaxy.owner_of(Galaxy.current_system)
			if here != s.empire and here != "pirates" and not Galaxy.at_war(here, s.empire) and s.role != "patrol":
				Galaxy.change_reputation(here, Galaxy.REP_LAWLESS, "a civilian destroyed in their space")
	_log_death(s, by_player)
	if by_player:
		Scenarios.event("killed", {"ship_type": s.type_id})
	if str(s.quest_tag).begins_with("scenario:"):
		var tag: PackedStringArray = str(s.quest_tag).split(":")
		Scenarios.group_ship_lost(tag[1], tag[2], int(tag[3]) if tag.size() > 3 else -1)
	if by_player and s.empire != "pirates" and s.empire != "":
		missions.on_enemy_killed(s.type_id, s.empire, s.fleet_id)   # (an empire's warship: defence missions count it)
	if s.role == "patrol" and s.quest_tag == "":
		if s.fleet_id == "":   # (a fleet's losses aren't replaced here: Fleets)
			_schedule_patrol(s.empire)
		return
	if s.is_neutral():
		if by_player:
			hud.flash_message("Civilian %s destroyed" % s.display_name)
		_schedule_neutral_respawn()
		return
	# Only the player's own kills count (neutrals fight enemies too).
	if by_player:
		kills += 1
		missions.on_enemy_killed(s.type_id, s.empire, s.fleet_id)
		_regain_check()
	if s.quest_tag == "":  # story ships don't come back
		_schedule_respawn()


## A kill of yours: a chance to win back something you lost (LostItems).
func _regain_check() -> void:
	var got: String = player_data.regain_lost()
	if got != "":
		RegainPopup.show_item(get_tree(), got)
		GameLog.post("Item regained: %s." % got, "mission")


## Event log line for a destroyed ship (others' kills only if nearby).
func _log_death(s: Node2D, by_player: bool) -> void:
	if by_player:
		if s.is_neutral():
			GameLog.post("You destroyed the civilian %s" % s.display_name, "danger")
		else:
			GameLog.post("You destroyed %s" % s.display_name, "good")
	elif s.global_position.distance_to(ship.global_position) < 3000.0:
		var killer: String = s.last_attacker.display_name if is_instance_valid(s.last_attacker) and "display_name" in s.last_attacker else "unknown fire"
		GameLog.post("%s destroyed by %s" % [s.display_name, killer], "info")


func _schedule_neutral_respawn() -> void:
	await get_tree().create_timer(neutral_respawn_delay, false).timeout
	if is_inside_tree():
		spawn_neutral(_station_spawn_point())


## Credits always drop; items are a chance per roll. Tougher ships (more
## hull) get more rolls and better odds for rare loot.
const GEAR_DROP_CHANCE := 0.12

func _drop_loot(at: Vector2, enemy_hull: float) -> void:
	var credits: int = int((enemy_hull * 0.4 + randi_range(5, 20)) * (1.0 + player_data.mod("loot_mult")))
	Pickup.spawn(get_tree(), at, "credits", credits)
	# Now and then a piece of gear (Gear: for your ship or your automaton) -
	# the tougher the ship, the likelier, and the better.
	var level := clampf(enemy_hull / 900.0, 0.0, 1.0)
	if randf() < GEAR_DROP_CHANCE + level * 0.25:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		Pickup.spawn(get_tree(), at + Vector2(randf_range(-30, 30), randf_range(-30, 30)), Gear.roll(rng, "", level), 1)

	var rolls := 1 + mini(int(enemy_hull / 70.0), LOOT_ROLLS_MAX)   # (a huge creature doesn't fill your hold)
	for i in rolls:
		if randf() > ITEM_DROP_CHANCE:
			continue
		var total := 0.0
		var weights := []
		for entry in LOOT:
			var w: float = entry[1]
			if entry[0] in ["alien_alloy", "data_core"]:
				w *= 1.0 + enemy_hull / 100.0  # rare loot from big ships
			weights.append(w)
			total += w
		var pick := randf() * total
		for j in LOOT.size():
			pick -= weights[j]
			if pick <= 0.0:
				Pickup.spawn(get_tree(), at, LOOT[j][0], LOOT[j][2])
				break


func _schedule_respawn() -> void:
	# process_always = false, so the timer pauses with the game.
	await get_tree().create_timer(respawn_delay, false).timeout
	if is_inside_tree() and enemies.get_child_count() < _pirate_count():
		spawn_enemy(_random_spawn_point())


## The AI ship (hostile or neutral) under `point`, if any.
func _enemy_at(point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in enemies.get_children() + neutrals.get_children():
		var d := point.distance_to(enemy.global_position)
		if d < enemy.click_radius and d < best_dist and enemy.is_alive():
			best = enemy
			best_dist = d
	return best


# --- Toolbar, panels, docking --------------------------------------------------

## Toolbar slot (hotkeys 1-9): switch a weapon kind on / off or trigger a system - whatever
## you put there (PlayerData.toolbar).
func activate_slot(index: int) -> void:
	if not ship.is_alive():
		return
	var slot: Dictionary = hud.toolbar.slot_at(index)
	if slot.is_empty():
		return
	if slot["type"] == "weapon":
		ship.select_weapon(slot["id"])
	else:
		ship.use_system(slot["id"])


## The next / previous firing mode (gamepad LB / RB): every fitted weapon
## kind on, then each kind on its own.
func _cycle_weapon(d: int) -> void:
	var kinds := []
	for id in ship.weapons():
		if id != "" and not Hardpoints.kind(id) in kinds:
			kinds.append(Hardpoints.kind(id))
	if kinds.size() < 2:
		return
	var modes := [""] + kinds   # ("": all on)
	var on := kinds.filter(func(k): return ship.weapon_on(k))
	var at := 0 if on.size() == kinds.size() else (modes.find(on[0]) if on.size() == 1 else 0)
	var m: String = modes[wrapi(at + d, 0, modes.size())]
	player_data.weapons_off = {}
	for k in kinds:
		if m != "" and k != m:
			player_data.weapons_off[k] = true
	ship.message.emit("All weapons on" if m == "" else "%s only" % Items.WEAPONS[m]["name"])
	player_data.changed.emit()


## Attack the nearest hostile ship (F / gamepad RT) - or, none near, the
## nearest neutral you're already following.
func _attack_nearest() -> void:
	var best: Node2D = null
	var best_d := 2400.0
	for e in enemies.get_children() + neutrals.get_children():
		if not e.is_alive() or e.untouchable or (e.is_neutral() and not e.is_hostile_to_player()):
			continue
		var d: float = e.global_position.distance_to(ship.global_position)
		if d < best_d:
			best = e
			best_d = d
	if best:
		ship.set_attack_target(best, true)
		marker.hide_marker()
	else:
		hud.flash_message("No enemy in range")


## Gamepad flight: the left stick steers - the ship flies toward a point
## ahead in the stick's direction; let go and it stops (like releasing the
## mouse after steering). Not while a menu is open or the game is paused.
var _pad_steering := false

func _pad_flight() -> void:
	var v := Keybinds.stick_vector()
	if v != Vector2.ZERO and not get_tree().paused and not menu_open() and ship.is_alive() and not _ship_animating:
		_pad_steering = true
		ship.move_to(ship.global_position + v * 900.0)
	elif _pad_steering:
		_pad_steering = false
		if ship.is_alive() and not ship.chasing:
			ship.stop()


## Camera zoom in space (mouse wheel): target value, eased toward.
var _zoom := 1.0


var _fog_t := 0.0
var damage_screen: DamageScreen
var scanner: ShipScanner
var probes: ProbeScanner

const _ENEMY := preload("res://scripts/enemy.gd")

func _process(_delta: float) -> void:
	_prebuild_tick(_delta)
	_pad_flight()
	_update_salvage(_delta)
	_update_beacon_scan(_delta)
	_ENEMY.view_rect = (get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()).grow(600.0)
	_fog_t -= _delta
	if _fog_t <= 0.0 and ship.is_alive():
		_fog_t = 0.25
		Galaxy.reveal(ship.global_position)   # (fog of war: the system map shows what you've swept)
		for st in get_tree().get_nodes_in_group("stations"):   # (stations in sensor range: seen - trade routes to them)
			if st.station_id != "" and not Galaxy.seen.has(st.station_id) and st.global_position.distance_to(ship.global_position) < Galaxy.SENSOR_RANGE:
				Galaxy.see_station(st.station_id)
		_discover_t -= 1
		if _discover_t <= 0:
			_discover_t = 2   # (every half second)
			Discovery.scan(self)   # (the Encyclopedia: what's come near)
	var cam: Camera2D = $Ship/Camera2D
	if not is_equal_approx(cam.zoom.x, _zoom):
		var z := lerpf(cam.zoom.x, _zoom, minf(1.0, _delta * 12.0))
		cam.zoom = Vector2(z, z)
	_dock_station = null
	if ship.is_alive():
		for st in get_tree().get_nodes_in_group("stations"):
			if ship.global_position.distance_to(st.global_position) < st.dock_radius:
				_dock_station = st
				break
	hud.show_dock_prompt(_dock_station)
	_check_gates()
	_update_steering()
	# Arrived at a station we clicked on: dock.
	if _dock_on_arrival and _dock_station == _dock_on_arrival:
		dock(_dock_station)
	# Arrived at a signal's beacon we asked to enter: drop in.
	if is_instance_valid(_site_on_arrival) and site == null and ship.is_alive():
		if not ship.has_target or ship.target.distance_to(_site_on_arrival.global_position) > 10.0:
			_site_on_arrival = null   # (you flew somewhere else)
		elif ship.global_position.distance_to(_site_on_arrival.global_position) < SignalBeacon.ENTER_RANGE * 0.5:
			enter_site(_site_on_arrival)


# --- Signal sources (SignalSites) ------------------------------------------------------

## The signal site you're in (null: out in the system).
var site: SignalSite
var planet_card: PlanetCard
var _beacons := {}                  # signal id -> SignalBeacon
var _site_on_arrival: SignalBeacon


## A beacon for every signal source of this system (shown once located).
func refresh_beacons() -> void:
	for sg in Galaxy.signals_in():
		if not _beacons.has(sg["id"]) or not is_instance_valid(_beacons[sg["id"]]):
			var b := SignalBeacon.new()
			b.sig = sg
			add_child(b)
			_beacons[sg["id"]] = b


## The ENTER button: drop in if you're near enough, else fly there first.
func request_site(b: SignalBeacon) -> void:
	if site != null or not b.active() or not ship.is_alive():
		return
	if ship.global_position.distance_to(b.global_position) < SignalBeacon.ENTER_RANGE:
		enter_site(b)
	else:
		_move_ship(b.global_position)
		_site_on_arrival = b
		hud.flash_message("Flying to the %s - you'll drop in when you arrive" % b.title())


func enter_site(b: SignalBeacon) -> void:
	_site_on_arrival = null
	if site != null:
		return
	marker.hide_marker()
	scanner.paths = []                 # (the scan's paths and arrows belong to the system outside)
	hud.minimap.scan_until = 0
	site = SignalSite.new()
	site.main = self
	site.sig = b.sig
	site.return_point = b.global_position + Vector2(0, 260)
	add_child(site)
	site.start()


var _discover_t := 0

func dock(st: Node2D) -> void:
	_dock_on_arrival = null
	if _ship_animating:   # (still undocking, landing...: dock once it's done)
		_dock_queued = st
		return
	_dock_queued = null
	if st.empire != "" and Galaxy.is_hostile_to_player(st.empire):
		hud.flash_message("%s refuses docking: the %s considers you an enemy" % [st.station_name, Galaxy.empire_name(st.empire)])
		return
	ship.has_target = false
	ship.chasing = false
	ship.velocity = Vector2.ZERO
	marker.hide_marker()
	_set_steering(false)
	# The outfitter shows every weapon and system: known from here on (Encyclopedia).
	Discovery.mark(get_tree(), "station:" + str(st.station_name))
	for id in Items.EQUIPMENT:
		Discovery.mark(get_tree(), "gear:" + str(id))
	hud.show_dock_prompt(null)
	# Glide into the station's centre and shrink away, then the menu opens.
	_dock_return = ship.global_position
	_ship_anim_begin()
	Sfx.play("space/dock")
	DockAnim.into(ship, ship.sprite, st.global_position, func():
		GameLog.post("Docked at %s" % st.station_name, "mission")
		missions.on_docked(st.station_name)
		Galaxy.visit_station(st.station_id)   # (its market: known now - trade routes from it)
		SaveGame.autosave.call_deferred("docked at " + str(st.station_name))
		Scenarios.event("docked", {"station": st.station_name})
		_open_panel(station_menu, st)
		quest.on_docked(st.station_name))  # may start story dialogue over the menu


## Undocking: the ship grows out of the station and glides back out.
func _on_undocked(st: Node2D) -> void:
	if not is_instance_valid(st):
		_ship_anim_end()
		return
	Sfx.play("space/undock")
	DockAnim.out_of(ship, ship.sprite, st.global_position, _dock_return, _ship_sprite_scale, _ship_anim_end)


var _ship_animating := false
var _dock_queued: Node2D = null   # a dock asked for while the ship was animating
var _ship_sprite_scale := Vector2.ONE
var _dock_return := Vector2.ZERO


## The player's ship hands control to a dock / land animation.
func _ship_anim_begin() -> void:
	_ship_animating = true
	_ship_sprite_scale = ship.sprite.scale
	ship.stop()
	ship.thrust = 0.0
	ship.set_physics_process(false)
	ship._shield_fx.visible = false


func _ship_anim_end() -> void:
	ship.sprite.scale = _ship_sprite_scale
	ship.sprite.visible = true
	ship._shield_fx.visible = true
	ship.set_physics_process(true)
	_ship_animating = false
	if is_instance_valid(_dock_queued) and ship.is_alive():   # a dock asked for during the animation
		var st := _dock_queued
		_dock_queued = null
		dock.call_deferred(st)


# --- Wrecks and salvage (Wreck) --------------------------------------------------------------

var _salvage: Wreck = null      # the wreck being salvaged (or flown to)
var _salvage_beam: MiningBeam


func _nav_beacon_at(point: Vector2) -> NavBeacon:
	for b in get_tree().get_nodes_in_group("nav_beacons"):
		if point.distance_to(b.global_position) < NavBeacon.CLICK_RADIUS:
			return b
	return null


## Right-clicked the navigation beacon: the ship scans it - NavBeacon.SCAN_TIME
## seconds, within NavBeacon.SCAN_RANGE (fly out of it, or die, and the scan
## is lost); the beacon shows the scan (its progress, a sweep, a beam from the
## ship) and, done, makes the system's navigation report (chart_with_beacon).
## Scanned already this visit: its report shown again at once.
var _beacon_scan: NavBeacon
var _beacon_scan_t := 0.0


func scan_beacon(b: NavBeacon) -> void:
	if b.charted() and Galaxy.reports.has(b.sys_id) and int(Galaxy.report_issued.get(b.sys_id, -1)) == Galaxy.jumps:
		NavReportPanel.open(hud, Galaxy.reports[b.sys_id], false)
		return
	if _beacon_scan == b:
		hud.flash_message("Scanning the nav beacon... %d%%" % int(b.scan * 100.0))
		return
	if ship.global_position.distance_to(b.global_position) > NavBeacon.SCAN_RANGE:
		hud.flash_message("Out of scanner range - get within %.1fk of the nav beacon" % (NavBeacon.SCAN_RANGE / 1000.0))
		return
	_beacon_scan = b
	_beacon_scan_t = 0.0
	b.scan = 0.0
	b.scanner = ship
	Sfx.play_world("space/scan_laser", b.global_position, -2.0, 0.03)
	hud.flash_message("Scanning the nav beacon - stay within %.1fk for %d seconds" % [NavBeacon.SCAN_RANGE / 1000.0, int(NavBeacon.SCAN_TIME)])


func _update_beacon_scan(delta: float) -> void:
	var b := _beacon_scan
	if b == null:
		return
	if not is_instance_valid(b):
		_beacon_scan = null
		return
	if not ship.is_alive() or ship.global_position.distance_to(b.global_position) > NavBeacon.SCAN_RANGE * 1.1:
		b.scan = -1.0
		b.scanner = null
		_beacon_scan = null
		hud.flash_message("Nav beacon scan lost - you went out of range" if ship.is_alive() else "Nav beacon scan lost")
		return
	_beacon_scan_t += delta
	b.scan = minf(_beacon_scan_t / NavBeacon.SCAN_TIME, 1.0)
	if b.scan >= 1.0:
		b.scan = -1.0
		b.scanner = null
		_beacon_scan = null
		chart_with_beacon(b)


## Scanned the system's navigation beacon: its navigation report (NavReports)
## made from what's in the system now - shown (NavReportPanel) and, once a
## visit, a copy put in your hold to sell in other systems. The fog stays (the
## report lists the system; your sensors still have to find things on the map).
func chart_with_beacon(b: NavBeacon) -> void:
	var tree := get_tree()
	var r := NavReports.make(tree, b.sys_id)
	var new_copy := Galaxy.chart_system(b.sys_id, r)
	b.pulse()
	Sfx.play("space/scan_done", -2.0)
	for p in tree.get_nodes_in_group("planet_bodies"):
		if str(p.planet_id) != "":
			Discovery.mark(tree, "planet:" + str(p.planet_id))
	for st in tree.get_nodes_in_group("stations"):
		Discovery.mark(tree, "station:" + str(st.station_name))
	if new_copy:
		player_data.add_item(NavReports.id_for(b.sys_id), 1)
	NavReportPanel.open(hud, r, new_copy)
	var text := "%s navigation report: %s%s" % [r["name"], NavReports.summary(r),
		" - a copy in your hold (sell it in another system)" if new_copy else ""]
	hud.flash_message("%s navigation report%s" % [r["name"], " - a copy in your hold" if new_copy else ""])
	GameLog.post(text, "mission")


func _wreck_at(point: Vector2) -> Wreck:
	for w in get_tree().get_nodes_in_group("wrecks"):
		if not w.salvaged and point.distance_to(w.global_position) < w.radius + 20.0:
			return w
	return null


## Clicked a wreck: with a Salvage Rig, fly up and cut it apart.
func _start_salvage(w: Wreck) -> void:
	if not player_data.has_equipment("salvage_rig"):
		hud.flash_message("The wreck of a %s - fit a Salvage Rig (Outfitting) to salvage it" % w.title)
		return
	_salvage = w
	w.progress = 0.0
	marker.hide_marker()
	ship.set_attack_target(null)
	var off := (ship.global_position - w.global_position).normalized() * (w.radius + Wreck.SALVAGE_REACH * 0.6)
	_move_ship(w.global_position + off)
	hud.flash_message("Salvaging the wreck of a %s - hold close" % w.title)


func _update_salvage(delta: float) -> void:
	var on := false
	if _salvage != null and (not is_instance_valid(_salvage) or _salvage.salvaged or not ship.is_alive()):
		_salvage = null
	if _salvage != null:
		var d: float = ship.global_position.distance_to(_salvage.global_position)
		if d < _salvage.radius + Wreck.SALVAGE_REACH and ship.velocity.length() < 140.0:
			on = true
			_salvage.progress += delta * (1.0 + float(player_data.mod("salvage_speed")))
			if _salvage_beam == null:
				_salvage_beam = MiningBeam.new()
				_salvage_beam.color = Color(1.0, 0.7, 0.25)
				add_child(_salvage_beam)
			_salvage_beam.aim(ship.global_position, _salvage.global_position)
			if _salvage.progress >= _salvage.salvage_time():
				var extra: String = _salvage.salvage(player_data)
				GameLog.post("Salvaged the wreck of a %s%s." % [_salvage.title, (": " + extra) if extra != "" else ""], "loot")
				hud.flash_message("Salvaged - tractor the parts in")
				Sfx.play("space/pickup")
				_salvage = null
	if not on and _salvage_beam:
		_salvage_beam.off()


func _station_at(point: Vector2) -> Node2D:
	for st in get_tree().get_nodes_in_group("stations"):
		if point.distance_to(st.global_position) < st.radius + 30.0:
			return st
	return null


## Clicked a station: dock now if close, otherwise fly there first.
func _go_to_station(st: Node2D) -> void:
	if _dock_station == st:
		dock(st)
		return
	_dock_on_arrival = st
	var approach: Vector2 = st.global_position + st.global_position.direction_to(ship.global_position) * (st.radius + 80.0)
	ship.move_to(approach)
	marker.show_at(approach)
	hud.hint.visible = false
	hud.flash_message("Flying to %s to dock" % st.station_name)


## A full-window menu is open (the Ship Computer, a station's window). The
## game goes on behind them - only the Esc menu pauses.
func menu_open() -> bool:
	return ship_menu.visible or station_menu.visible


## You were hit: the Ship Computer closes, so you see the fight (a docked ship
## can't be hit: stations are safe zones).
func close_menus_on_hit() -> void:
	if ship_menu.visible and not UI.esc_menu_open():
		ship_menu.close()
		hud.flash_message("Under attack!")


## Right-click on empty space: the probe scanner - the system map with its
## PROBES panel open (if one's fitted).
func open_probes() -> void:
	if not probes.fitted():
		hud.flash_message("No probe scanner fitted - buy one at a station's outfitter (SYSTEMS)")
		return
	_open_panel(ship_menu, ship_menu.MAP_TAB)
	var mp = ship_menu.page(ship_menu.MAP_TAB)
	if mp.has_method("show_probes"):
		mp.show_probes(true)


func _open_panel(panel: Control, arg: Variant = null) -> void:
	_set_steering(false)
	hud.hint.visible = false
	hud.show_dock_prompt(null)
	if arg == null:
		panel.open()
	else:
		panel.open(arg)


func _on_player_destroyed() -> void:
	marker.hide_marker()
	_set_steering(false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	await get_tree().create_timer(1.5, false).timeout
	hud.show_game_over(kills)


# --- Input -------------------------------------------------------------------

# Tab is handled in _input so GUI focus navigation can't swallow it.
func _input(event: InputEvent) -> void:
	var which := ""
	for id in ["computer", "sector_map", "galaxy_map"]:
		if Keybinds.pressed(event, id):
			which = id
	if which != "" and not get_tree().paused and not menu_open() and ship.is_alive():
		if which == "sector_map":
			_open_panel(ship_menu, ship_menu.MAP_TAB)   # sector map
		elif which == "galaxy_map":
			_open_panel(ship_menu, ship_menu.GALAXY_TAB)   # galaxy map
		else:
			_open_panel(ship_menu)
		get_viewport().set_input_as_handled()


# _unhandled_input only receives clicks that no UI control consumed,
# i.e. clicks on empty space (or on enemies).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or Keybinds.pressed(event, "pause"):
		_set_steering(false)
		hud.hint.visible = false
		pause_menu.open()
		get_viewport().set_input_as_handled()
		return

	# Mouse wheel: zoom in / out; the middle button: back to the normal zoom.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
		_zoom = clampf(_zoom * step, 0.6, 1.6)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and UI.middle_click(self, event):
		_zoom = 1.0
		get_viewport().set_input_as_handled()
		return

	if not ship.is_alive() or menu_open():
		return   # (a full-window menu open: its keys are its own)

	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var slot := Keybinds.slot_pressed(event)
		if slot >= 0:
			activate_slot(slot)
		elif Keybinds.pressed(event, "inventory"):
			_open_panel(ship_menu, ship_menu.INVENTORY_TAB)
		elif Keybinds.pressed(event, "event_log"):
			hud.toggle_event_log()
		elif Keybinds.pressed(event, "hail"):
			var c := _hail_candidate()
			if c:
				hail(c)
			else:
				hud.flash_message("No ship in comms range")
		elif Keybinds.pressed(event, "dock"):
			if _dock_station:
				dock(_dock_station)
		elif Keybinds.pressed(event, "attack"):
			_attack_nearest()
		elif Keybinds.pressed(event, "slot_prev"):
			_cycle_weapon(-1)
		elif Keybinds.pressed(event, "slot_next"):
			_cycle_weapon(1)
		else:
			return
		get_viewport().set_input_as_handled()
		return

	# World position of the event itself (not a separately polled mouse position).
	var point := get_global_mouse_position()
	if event is InputEventMouse:
		_last_mouse_screen = event.position
		point = get_canvas_transform().affine_inverse() * event.position

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var enemy := _enemy_at(point)
				var rock := _asteroid_at(point) if enemy == null else null
				var station := _station_at(point) if enemy == null and rock == null else null
				var wreck := _wreck_at(point) if enemy == null and rock == null and station == null else null
				_dock_on_arrival = null
				_salvage = null
				if wreck:
					_start_salvage(wreck)
				elif enemy:
					var friendly: bool = enemy.is_neutral() and not enemy.is_hostile_to_player()
					if friendly and ship.follow_target != enemy and ship.attack_target != enemy:
						# A neutral ship: the first click selects it and you follow it;
						# clicking it again attacks.
						ship.follow(enemy)
						hud.flash_message("Following the %s - click it again to attack" % enemy.display_name)
					else:
						# Attack; flies into weapon range first if needed.
						if friendly and ship.attack_target != enemy:
							hud.flash_message("Attacking a neutral %s - it will fight back" % enemy.display_name)
						ship.set_attack_target(enemy, true)
					marker.hide_marker()
				elif rock:
					# Mine it: fly into range; hold the button to fire the laser
					# (Mining) - pressed near a vein, that vein's the one cut.
					if ship.attack_target != rock:
						ship.set_attack_target(rock, true)
						ship.mining_vein = -1
					if rock.scanned:
						var vi: int = rock.vein_near(point)
						if vi >= 0 and rock.vein_pos(vi).distance_to(point) < rock.hit_radius * 0.6:
							ship.mining_vein = vi
					ship.mining_hold = true
					marker.hide_marker()
				elif station:
					_go_to_station(station)
				else:
					_press_time = Time.get_ticks_msec()
					_press_point = point
					_set_steering(true)
					_move_ship(point)
			elif ship.mining_hold:
				ship.mining_hold = false   # (let go: the laser stops, the vein cools)
			elif _drag_moves:
				_set_steering(false)
				if Time.get_ticks_msec() - _press_time < CLICK_MAX_MS:
					# Quick click: fly to the clicked point and mark it.
					_move_ship(_press_point)
					marker.show_at(_press_point)
				else:
					# Released after steering: stop.
					ship.stop()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if event.shift_pressed:
				_context_menu(event.position)   # (Shift + right-click: the menu)
			elif ship.is_alive():
				# The scanner: the navigation beacon (charts the system), an asteroid
				# (or a signal site's anomaly node), or the whole system.
				var nav := _nav_beacon_at(point) if site == null else null
				var rock: Node2D = _asteroid_at(point) if nav == null else null
				if rock == null and site != null:
					rock = site.scan_point_at(point)
				if nav:
					scan_beacon(nav)
				elif rock:
					scanner.scan_rock(rock)
				else:
					open_probes()

	elif event is InputEventMouseMotion:
		if not _drag_moves:
			# Crosshair over enemies, pointing hand over stations.
			var shape := Input.CURSOR_ARROW
			if _enemy_at(point) or _asteroid_at(point):
				shape = Input.CURSOR_CROSS
			elif _station_at(point) or _wreck_at(point) or _nav_beacon_at(point):
				shape = Input.CURSOR_POINTING_HAND
			Input.set_default_cursor_shape(shape)


## While the left button is held, keep flying toward the cursor's direction
## (relative to the ship). The target is pushed far ahead every frame, so
## the ship never arrives and never slows down until the button is released.
func _update_steering() -> void:
	if _drag_moves and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_steering(false)   # (the release went somewhere else - a panel: never keep the cursor hidden)
	if not _drag_moves or not ship.is_alive():
		return
	var cursor := get_canvas_transform().affine_inverse() * _last_mouse_screen
	var to_cursor := cursor - ship.global_position
	if to_cursor.length() < 30.0:
		return  # cursor on top of the ship: keep the current heading
	ship.move_to(ship.global_position + to_cursor.normalized() * 5000.0)


## Ends steering (the cursor back): a dialogue opening over the game calls it
## (group "steering").
func release_steering() -> void:
	if _drag_moves:
		_set_steering(false)
		ship.stop()


## While the left button is held to steer, nothing follows the mouse: the
## system cursor is hidden and the target marker is only shown on release.
func _set_steering(on: bool) -> void:
	_drag_moves = on
	if on:
		marker.hide_marker()
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		# Fallback for setups where the hidden mode is ignored (e.g. the game
		# embedded in the editor): an invisible cursor image.
		Input.set_custom_mouse_cursor(_blank_cursor(), Input.CURSOR_ARROW)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


static var _blank: ImageTexture

static func _blank_cursor() -> ImageTexture:
	if _blank == null:
		_blank = ImageTexture.create_from_image(Image.create_empty(16, 16, false, Image.FORMAT_RGBA8))
	return _blank


func _notification(what: int) -> void:
	# Never leave the cursor hidden if the window loses focus mid-drag,
	# or when leaving the game scene.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		_set_steering(false)


func _move_ship(point: Vector2) -> void:
	ship.move_to(point)
	hud.hint.visible = false


# --- Saving ------------------------------------------------------------------

# --- Star systems (sandbox) -------------------------------------------------------

## Builds the current system: its star, orbiting planets, stations, gates
## and asteroid fields (Atrapos keeps its hand-made stations and planets).
func _build_system() -> void:
	var sys: Dictionary = Galaxy.system(Galaxy.current_system)
	# The GUI takes on the colours of the empire whose space this is.
	NeonTheme.set_empire(Galaxy.owner_of(Galaxy.current_system))
	# A GUI look preset for here (Themes "gui"), or the plain palette.
	var gui_look := Themes.pick("gui", Themes.context(), hash(Galaxy.current_system))
	if not gui_look.is_empty():
		GuiLook.apply_all(gui_look)
	elif not NeonTheme.custom.is_empty():
		NeonTheme.apply_look({})
	var home: bool = Galaxy.current_system == Galaxy.HOME
	var root := Node2D.new()
	root.name = "SolarSystem"
	root.z_index = -16
	add_child(root)
	move_child(root, $Stations.get_index())
	var star_def: Dictionary = Galaxy.STARS[sys["star"]]
	var sspec := Galaxy.star_spec(Galaxy.current_system)
	sspec.merge(Themes.pick("star", Themes.context(), hash(Galaxy.current_system), str(sspec.get("template", ""))), true)
	root.add_child(Star.new().setup(star_def["color"], star_def["radius"], sys["name"], sspec))
	var orbits := OrbitRings.new()
	root.add_child(orbits)
	# Planets (pieces, nearest first - a moon after its planet).
	var bodies := {}
	var home_at := {}   # (where each is now, roughly: the order they come in)
	if home:
		for o in HOME_ORBITS:
			var pd: Dictionary = Planets.PLANETS[o[0]]
			var hspec := Planets.spec(o[0])
			hspec.merge(Themes.pick("planet", Themes.context(o[0]), hash(o[0]), str(hspec.get("template", ""))), true)
			var at := _orbit_at(o[1], o[2], o[4] != "", home_at.get(o[4], Vector2.ZERO))
			home_at[o[0]] = at
			_piece("planet:" + o[0], "the planet " + str(pd["name"]), at, _add_body.bind(root, orbits, bodies,
				o[0], pd["name"], pd["desc"], pd["landable"], hspec, o[3], o[1], o[2], o[4]),
				(func(): return bodies.has(o[4])) if o[4] != "" else Callable())
	else:
		# Its planets and moons (Galaxy._generate_planets) - every one landable.
		for pl in sys["planets"]:
			var spec := PlanetGen.generate(pl["template"], pl["variant"])
			spec.merge(Themes.pick("planet", Themes.context(pl["id"]), int(pl["variant"]), pl["template"]), true)
			var pd := Planets.get_planet(pl["id"])
			var label: String = Planets.TYPES[pl["type"]]["label"]
			var desc: String = pd["desc"] if pl["moon_of"] != "" else "A %s of the %s system. %s" % [label, sys["name"], pd["desc"]]
			var moon: String = pl["moon_of"]
			var at := _orbit_at(pl["orbit"], pl["phase"], moon != "", home_at.get(moon, Vector2.ZERO))
			home_at[pl["id"]] = at
			_piece("planet:" + str(pl["id"]), ("the moon " if moon != "" else "the planet ") + str(pl["name"]), at,
				_add_body.bind(root, orbits, bodies, pl["id"], pl["name"], desc, true, spec, pl["size"], pl["orbit"], pl["phase"], moon),
				(func(): return bodies.has(moon)) if moon != "" else Callable())
	await _stage()
	# Stations: Atrapos keeps the scene's; other systems get generated ones.
	if home:
		for st in $Stations.get_children():
			var rec := Galaxy.station_by_name(Galaxy.HOME, st.station_name)
			st.station_id = rec.get("id", "")
			st.empire = Galaxy.station_owner(st.station_id)
			st.accent = Galaxy.empire_color(st.empire)   # (its owner's colour, not the scene's own)
	else:
		for st in $Stations.get_children():
			st.free()
		for sid in sys["stations"]:
			var rec: Dictionary = Galaxy.stations[sid]
			_piece("station:" + sid, "the station " + str(rec["name"]), rec["pos"], _add_station.bind(sid))
		asteroid_fields.assign(sys["fields"])
	await _stage()
	# Jump gates to the neighbouring systems.
	for n in sys["gates"]:
		_piece("gate:" + n, "the gate to " + str(Galaxy.SYSTEMS[n]["name"]), sys["gates"][n], func():
			var g := JumpGate.new()
			g.target = n
			g.target_name = Galaxy.SYSTEMS[n]["name"]
			g.accent = Galaxy.empire_color(Galaxy.owner_of(n))
			g.position = sys["gates"][n]
			add_child(g))
	# The navigation beacon by the star: click it to chart the system.
	var nav_at := NavBeacon.place(Galaxy.current_system, star_def["radius"])
	_piece("nav", "the navigation beacon", nav_at, func():
		var nav := NavBeacon.new()
		nav.sys_id = Galaxy.current_system
		nav.position = nav_at
		add_child(nav))
	await _stage()
	# Nebulae and galaxies far behind: each system has its own (NebulaGen).
	# They're the deepest thing in space: the Nebulae layer is at NEBULA_Z,
	# below everything else (planets add their own z to their parent's, so
	# keep every other layer well above it - test_play checks).
	# (The layer doesn't repeat: a nebula is wider than any tile it could
	# repeat in, and as the layer wrapped round, parts of it snapped in and out.)
	for n in NebulaGen.for_system(Galaxy.current_system, Galaxy.SYSTEMS.keys().find(Galaxy.current_system)):
		var spec: Dictionary = n[0]
		spec.merge(Themes.pick("nebula", Themes.context(), int(spec.get("variant", 0)), str(spec.get("template", ""))), true)
		spec["intensity"] = float(spec["intensity"]) * 0.6   # a backdrop: keep it behind the action
		# (far behind, on a slow layer: as near as anything - they come early)
		_piece("nebula:" + str(n[1]), "a nebula far behind", ship.global_position, func():
			var neb := NebulaGen.make(spec, n[2])
			neb.position = n[1] - neb.size / 2.0
			# (drawn into a picture 4 times a second - its slow drift - not by its shader every frame)
			$Nebulae.add_child(ShaderCache.wrap(neb, 4.0, 1024.0, CanvasItemMaterial.BLEND_MODE_ADD)))
	await _stage()
	# Distant planets far behind (other worlds of the galaxy).
	var far := Parallax2D.new()
	far.scroll_scale = Vector2(0.08, 0.08)
	far.repeat_size = Vector2(4200, 4200)
	far.repeat_times = 2
	far.z_index = -18
	add_child(far)
	move_child(far, root.get_index())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Galaxy.current_system)
	for i in 4:
		# (variants 1000+: unique to this system and never used by an orbiting planet)
		var tpl: String = PlanetGen.TEMPLATES.keys()[rng.randi() % PlanetGen.TEMPLATES.size()]
		var variant := 1000 + Galaxy.SYSTEMS.keys().find(Galaxy.current_system) * 10 + i
		var fsize := rng.randf_range(50, 110)
		var fpos := Vector2(rng.randf_range(-2000, 2000), rng.randf_range(-2000, 2000))
		_piece("far:%d" % i, "a distant world", ship.global_position, func():
			var planet := Planets.make_planet(PlanetGen.generate(tpl, variant), fsize, PlanetGen.DISK, true)
			planet.position = fpos
			planet.modulate = Color(0.7, 0.7, 0.78)
			far.add_child(planet))
	await _stage()
	# HUD: which system you're in and who owns it.
	_system_label = UI.label("", 18)
	_system_label.add_theme_font_override("font", NeonTheme.heavy_font())
	_system_label.add_theme_constant_override("outline_size", 6)
	_system_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_system_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_system_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_system_label.position = Vector2(-300, 14)
	_system_label.size = Vector2(600, 30)
	hud.add_child(_system_label)
	_update_system_label()
	refresh_beacons()


func _update_system_label() -> void:
	if _system_label == null:
		return
	var owner := Galaxy.owner_of(Galaxy.current_system)
	_system_label.text = "%s SYSTEM  ·  %s" % [Galaxy.SYSTEMS[Galaxy.current_system]["name"].to_upper(), Galaxy.empire_name(owner).to_upper()]
	_system_label.add_theme_color_override("font_color", Galaxy.empire_color(owner).lightened(0.25))


func _make_body(pid: String, title: String, desc: String, landable: bool, spec: Dictionary, size: float, orbit: float,
		phase: float) -> OrbitBody:
	var b := OrbitBody.new()
	b.planet_id = pid
	b.title = title
	b.desc = desc
	b.landable = landable
	b.radius = size / 2.0
	b.orbit = orbit
	b.phase = phase
	b.spec = spec
	var rect := Planets.make_planet(spec, size, PlanetGen.DISK, true)
	rect.position = -rect.size / 2.0
	b.add_child(rect)
	b.planet = rect
	return b


## Where a saved ship or rock was (its piece's place in the queue).
func _saved_at(d: Dictionary) -> Vector2:
	var p = d.get("position", d.get("pos", null))
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


## Where a planet (or a moon round `parent_at`) is now - OrbitBody's motion.
func _orbit_at(orbit: float, phase: float, moon: bool, parent_at: Vector2) -> Vector2:
	var period: float = (240.0 if moon else 900.0 * pow(orbit / 3000.0, 1.5)) * OrbitBody.ORBIT_SLOWDOWN
	return (parent_at if moon else Vector2.ZERO) + Vector2.from_angle(phase + Galaxy.time * TAU / period) * orbit


## A planet or moon piece: its body in the system, on the orbit rings, and a
## ringed planet's beacon (its local space: SignalSite "ring").
func _add_body(root: Node2D, orbits: OrbitRings, bodies: Dictionary, pid: String, title: String, desc: String,
		landable: bool, spec: Dictionary, size: float, orbit: float, phase: float, parent: String) -> void:
	var b := _make_body(pid, title, desc, landable, spec, size, orbit, phase)
	if parent != "":
		b.parent_body = bodies[parent]
	bodies[pid] = b
	root.add_child(b)
	b._process(0.0)   # (in place at once - not at the centre for a frame)
	orbits.bodies.append(b)
	if float(b.spec.get("rings", 0.0)) > 0.2 and b.parent_body == null:
		var rb := SignalBeacon.new()
		rb.sig = {"id": "ring:" + b.planet_id, "kind": "ring", "planet": b.title, "located": true, "done": false,
			"seed": hash(b.planet_id), "level": "moderate",
			"pos": [b.radius * float(b.spec.get("ring_outer", 2.2)) * 0.85, 0.0]}
		b.add_child(rb)


## A station piece (systems other than Atrapos: the scene's own are there already).
func _add_station(sid: String) -> void:
	var rec: Dictionary = Galaxy.stations[sid]
	var st: Node2D = preload("res://scenes/station.tscn").instantiate()
	st.position = rec["pos"]
	st.station_name = rec["name"]
	st.station_id = sid
	st.empire = Galaxy.station_owner(sid)   # (not always the system's owner: independents, outposts, forward bases)
	st.accent = Galaxy.empire_color(st.empire)
	st.radius = 150.0 + float(hash(sid) % 60)
	$Stations.add_child(st)


func _pirate_count() -> int:
	var sys: Dictionary = Galaxy.system(Galaxy.current_system)
	if Galaxy.current_system == Galaxy.HOME:
		return enemy_count
	return roundi(1.0 + Galaxy.pirate_level(Galaxy.current_system) * 8.0)


## Fills a freshly entered system: pirates, empire patrols (and raiders of
## empires at war with the owner), a few local civilians, asteroids.
func _populate_system(ships: bool, civilians: bool, rocks: bool) -> void:
	var owner := Galaxy.owner_of(Galaxy.current_system)
	if ships:
		for i in _pirate_count():
			# Sea Peoples raiders: their own hawk-and-cat designs, plus captured classics.
			var at := _system_spot()
			_piece("ship", "a pirate raider", at, spawn_ship.bind(at, _warship_type("pirates") if randf() < 0.6 else "", {}, "pirates"))
		if owner != "pirates":
			for i in 2:   # (the system's own militia)
				var at := _system_spot()
				_piece("ship", "a militia patrol", at, spawn_ship.bind(at, _warship_type(owner), {}, owner))
		# The war fleets here (Fleets): defenders and invaders, real ships (after the stations they besiege).
		for f in Fleets.in_system(Galaxy.current_system):
			_piece("fleet", "a war fleet of " + Galaxy.empire_name(str(f.get("empire", ""))), ship.global_position + Vector2(4000, 0),
				_spawn_fleet.bind(f, false), func(): return not pieces_pending("station:") and not pieces_pending("gate:"))
	if civilians:
		for i in (2 if Galaxy.current_system == Galaxy.HOME else 1):
			var civ_owner := owner if owner != "pirates" else Galaxy.HOME_EMPIRE
			var civ := ShipDesigns.pick(civ_owner, ["explorer"])
			var cls: String = civ if civ != "" else EnemyTypes.neutral_ids().pick_random()
			# (by a station: after the stations)
			_piece("ship", "a traveller", ship.global_position + Vector2(3000, 0), func(): spawn_ship(_station_spawn_point(), cls, {}, civ_owner),
				func(): return not pieces_pending("station:"))
	if rocks:
		for field in asteroid_fields:
			_piece("rocks", "an asteroid field", field, func():
				for i in asteroids_per_field:
					spawn_asteroid(Asteroid.random_data(_asteroid_spot(field))))



## A mining crew for the system's fields: one miner per field (up to three),
## while there are rocks left to mine. They cut ore and sell it at stations.
func _spawn_mining_crew() -> void:
	if _stream_pieces and pieces_pending("rocks"):   # (streaming in: once the rocks are)
		_piece("miners", "the mining crew", asteroid_fields[0] if not asteroid_fields.is_empty() else ship.global_position,
			_spawn_mining_crew, func(): return not pieces_pending("rocks"))
		return
	if not asteroids.get_children().any(func(a): return a.is_alive()):
		return
	var owner := Galaxy.owner_of(Galaxy.current_system)
	var crew_owner := owner if owner != "pirates" else Galaxy.HOME_EMPIRE
	for i in mini(asteroid_fields.size(), 3):
		var miner := ShipDesigns.pick(crew_owner, ["miner"])
		if miner != "":
			var field: Vector2 = asteroid_fields[i]
			spawn_ship(field + Vector2.from_angle(randf() * TAU) * (asteroid_field_radius + 300.0), miner, {}, crew_owner)


## A fleet's ships in this system (as many as it has, less those already
## here): arriving ones at a gate, the others about the system; an invasion's
## ships each given a station to besiege (the most damaged of the empires it's
## at war with).
func _spawn_fleet(f: Dictionary, arriving: bool) -> void:
	var live := 0
	for n in neutrals.get_children():
		if n.get("fleet_id") == f["id"] and n.is_alive():
			live += 1
	var gates := get_tree().get_nodes_in_group("gates")
	var at: Vector2 = _system_spot()
	if arriving and not gates.is_empty():
		at = gates.pick_random().global_position
	var target: Node2D = null
	if f["mission"] == "invade":
		var best_h := INF
		for st in get_tree().get_nodes_in_group("stations"):
			if st.station_id != "" and Galaxy.at_war(f["empire"], st.empire) and st.health() < best_h:
				best_h = st.health()
				target = st
		if target and not arriving:
			at = target.global_position + Vector2.from_angle(randf() * TAU) * (target.radius + 900.0)
	for i in maxi(0, int(f["size"]) - live):
		# (a big fleet flies under a capital ship: the first one in, its leader)
		var t := _warship_type(f["empire"])
		if i == 0 and live == 0 and ShipDesigns.flagship(f["empire"], int(f["size"])) != "":
			t = ShipDesigns.flagship(f["empire"], int(f["size"]))
		var s := spawn_ship(at + Vector2.from_angle(randf() * TAU) * randf_range(80.0, 420.0), t, {}, f["empire"])
		s.fleet_id = f["id"]
		s.siege_target = target


func _on_fleet_arrived(f: Dictionary) -> void:
	if ship and f["system"] == Galaxy.current_system:
		_spawn_fleet(f, true)


## A station destroyed (by a siege here or away): its node blows up.
func _on_station_destroyed(station_id: String) -> void:
	for st in get_tree().get_nodes_in_group("stations"):
		if st.station_id == station_id:
			st.blow_up()


## A warship class of the empire's own design.
func _warship_type(empire: String) -> String:
	var t := ShipDesigns.warship(empire)
	return t if t != "" else EnemyTypes.ids().pick_random()


## A random point in the system (not too close to the star).
func _system_spot() -> Vector2:
	return Vector2.from_angle(randf() * TAU) * randf_range(2500.0, 9500.0)


func _schedule_patrol(empire: String) -> void:
	await get_tree().create_timer(45.0, false).timeout
	var owner := Galaxy.owner_of(Galaxy.current_system)
	if is_inside_tree() and empire != "" and (empire == owner or Galaxy.at_war(empire, owner)):
		var gates := get_tree().get_nodes_in_group("gates")
		var at: Vector2 = gates.pick_random().global_position if not gates.is_empty() else _system_spot()
		spawn_ship(at + Vector2.from_angle(randf() * TAU) * 400.0, _warship_type(empire), {}, empire)


# --- Traders ---------------------------------------------------------------------------

func _spawn_live_traders() -> void:
	for r in Galaxy.traders_in(Galaxy.current_system):
		_spawn_trader_ship(r)


## Flies a Galaxy trader record as a real ship in this system.
func _spawn_trader_ship(r: Dictionary) -> void:
	if r["system"] != Galaxy.current_system or r["legs"].is_empty():
		return
	if _trader_ships.has(r["id"]) and is_instance_valid(_trader_ships[r["id"]]):
		return
	var s := ENEMY_SCENE.instantiate()
	s.type_id = r["type"]
	s.empire = r["empire"]
	s.cargo = r["cargo"]          # shared: hijacks and deaths update the record
	s.credits = r["credits"]
	s.record_id = r["id"]
	s.position = Galaxy.leg_position(r)
	s.home = s.position
	s.leg_target = Galaxy.leg_target(r)
	s.has_leg = true
	s._pending_rotation = (s.leg_target - s.position).angle() + PI / 2.0
	s.died.connect(_on_ship_died)
	s.leg_reached.connect(_on_trader_leg_reached)
	neutrals.add_child(s)
	s.display_name = "%s  '%s'" % [s.display_name, r["name"]]
	r["live"] = true
	_trader_ships[r["id"]] = s
	if r["t"] < 0.02:
		Effects.spark(s.global_position, Galaxy.empire_color(r["empire"]))


## A trader reached a station (docks: glides in and shrinks away) or a gate
## (jumps out with a flash).
func _on_trader_leg_reached(s: Node2D) -> void:
	var r: Dictionary = Galaxy.traders.get(s.record_id, {})
	_trader_ships.erase(s.record_id)
	if not r.is_empty():
		r["live"] = false
		r["t"] = 1.0
		Galaxy.leg_done(s.record_id)
	var st := _nearest_station(s.global_position, 2.6)
	if st == null:
		Effects.spark(s.global_position, Galaxy.empire_color(s.empire))
		s.queue_free()
		return
	# Out of play while it docks: no AI, no targeting.
	s.set_process(false)
	s.set_physics_process(false)
	for g in s.get_groups():
		s.remove_from_group(g)
	DockAnim.into(s, s, st.global_position, s.queue_free, s.body)


## The station whose centre is within `reach` x its radius of a point, if any.
func _nearest_station(p: Vector2, reach: float) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for st in get_tree().get_nodes_in_group("stations"):
		var d: float = p.distance_to(st.global_position)
		if d < st.radius * reach and d < best_d:
			best = st
			best_d = d
	return best


func _exit_tree() -> void:
	_drop_prebuild()
	# (left mid-landing - quitting to the menu: the half-built surface goes too)
	if is_instance_valid(_landing_surface) and _landing_surface.get("prebuilding") == true and get_tree().current_scene != _landing_surface:
		_landing_surface.queue_free()
	for id in _trader_ships:
		var s = _trader_ships[id]
		if is_instance_valid(s):
			Galaxy.release_live(id, s.global_position)
	_trader_ships.clear()


func _on_news(text: String, kind: String) -> void:
	GameLog.post(text, {"news": "info", "danger": "danger", "good": "good"}.get(kind, "info"))


# --- Comms -------------------------------------------------------------------------------

## The ship to hail: your target, else the nearest ship within 1800.
func _hail_candidate() -> Node2D:
	if is_instance_valid(ship.attack_target) and ship.attack_target.has_method("faction_group"):
		return ship.attack_target
	var best: Node2D = null
	var best_d := 1800.0
	for n in enemies.get_children() + neutrals.get_children():
		var d: float = n.global_position.distance_to(ship.global_position)
		if n.is_alive() and not n.untouchable and d < best_d:
			best = n
			best_d = d
	return best


## Open a channel to another ship: what they say depends on who they are.
func hail(s: Node2D) -> void:
	if not is_instance_valid(s) or not s.is_alive():
		return
	_set_steering(false)
	var seed_ := "%s-%d" % [s.type_id, s.get_instance_id()]
	var e: String = s.empire
	var t: Dictionary = EnemyTypes.get_type(s.type_id)
	var role_line := "%s of the %s" % ["Captain" if s.role != "pirate" else "Raid leader", s.display_name]
	var text := ""
	var options := []
	match s.role:
		"pirate":
			var tribute := clampi(player_data.credits / 4, 50, 600)
			text = ["Nice ship, %s. It'd look better as scrap - unless you pay." % _player_title(), "The Sea Peoples take what the sea gives. Today, the sea gives you to us.", "Cut your engines and open your hold. Or don't. We enjoy both."].pick_random()
			options = [["Pay tribute: %d dr (they leave you alone)" % tribute, func():
				if player_data.spend(tribute):
					s.surrender()   # (raiders keep their word... for now)
					GameLog.post("Paid %d dr tribute to %s" % [tribute, s.display_name], "info")
				else:
					hud.flash_message("Not enough drachmas")], ["\"Come and take it.\"", null]]
		"trader", "miner":
			var hold := "an empty hold"
			if not s.cargo.is_empty():
				hold = ", ".join(s.cargo.keys().map(func(c): return "%d %s" % [s.cargo[c], Items.display_name(c)]))
			var dest := ""
			var r: Dictionary = Galaxy.traders.get(s.record_id, {})
			if not r.is_empty() and Galaxy.stations.has(r.get("dest", "")):
				dest = " bound for %s" % Galaxy.stations[r["dest"]]["name"]
			text = "Merchant %s here. We're carrying %s%s. Watch out for Sea Peoples on the lanes - they hit us twice this month." % [s.display_name, hold, dest]
			options = [["Ask for a trade tip", func(): _trade_tip(s)], ["Safe travels.", null]]
		"patrol":
			if s.is_hostile_to_player():
				text = "You are an enemy of the %s. Power down and prepare to be boarded." % Galaxy.empire_name(e)
			else:
				var wars := []
				for o in Galaxy.MAJOR:
					if o != e and Galaxy.at_war(e, o):
						wars.append(Galaxy.EMPIRES[o]["name"])
				text = "%s patrol. %s Keep your weapons cold in our space." % [Galaxy.EMPIRES[e]["short"],
					("We are at war with the %s." % " and the ".join(wars)) if not wars.is_empty() else "The border is quiet - for now."]
			options = [["Report pirate activity", func(): _patrol_report(s)], ["Understood.", null]]
		_:
			text = ["Out here charting the drift. The old maps lie, you know.", "Have you seen the palace on Amnissos? Minoan, they say - bull horns and all.", "Long way from home, both of us. Fair winds, pilot."].pick_random()
	Comms.open(self, seed_, e, role_line, text, options)


func _player_title() -> String:
	return "independent"   # (you answer to no empire: your standing with each is your reputation)


func _trade_tip(s: Node2D) -> void:
	var sys: Dictionary = Galaxy.system(Galaxy.current_system)
	var best := ["", "", "", 0]
	for a in sys["stations"]:
		for b in sys["stations"]:
			if a == b:
				continue
			for c in Galaxy.stations[a]["stock"]:
				if Galaxy.stations[a]["stock"][c] < 10.0 or not Galaxy.stations[b]["stock"].has(c):
					continue
				var gain := Galaxy.sell_price(b, c) - Galaxy.buy_price(a, c)
				if gain > best[3]:
					best = [c, a, b, gain]
	var text := "Nothing worth hauling round here right now."
	if best[0] != "":
		text = "Buy %s at %s, sell at %s - about %d dr profit a unit. You didn't hear it from me." % [Items.display_name(best[0]), Galaxy.stations[best[1]]["name"], Galaxy.stations[best[2]]["name"], best[3]]
	Comms.open(self, "%s-%d" % [s.type_id, s.get_instance_id()], s.empire, "Captain of the %s" % s.display_name, text, [])


func _patrol_report(s: Node2D) -> void:
	var n := enemies.get_child_count()
	Comms.open(self, "%s-%d" % [s.type_id, s.get_instance_id()], s.empire, "Captain of the %s" % s.display_name,
		"We count %d Sea Peoples raiders in this system. Bring us their hulls and the %s pays bounties." % [n, Galaxy.empire_name(Galaxy.owner_of(Galaxy.current_system))], [])


# --- Gates -------------------------------------------------------------------------------

func _check_gates() -> void:
	if not ship.is_alive() or get_tree().paused or SaveGame.travelling or AttractMode.active:
		return
	var near: Node2D = null
	for g in get_tree().get_nodes_in_group("gates"):
		if ship.global_position.distance_to(g.global_position) < JumpGate.USE_RADIUS:
			near = g
	if near == null:
		_gate_prompted = null
		return
	if near == _gate_prompted:
		return
	_gate_prompted = near
	_set_steering(false)
	ship.stop()
	var dest: String = near.target
	var owner := Galaxy.owner_of(dest)
	var text := "Gate to the %s system (%s)." % [Galaxy.SYSTEMS[dest]["name"], Galaxy.empire_name(owner)]
	if Galaxy.is_hostile_to_player(owner) and owner != "pirates":
		text += "\nWarning: the %s considers you an enemy." % Galaxy.empire_name(owner)
	elif owner == "pirates":
		text += "\nWarning: Sea Peoples space - expect raiders."
	UI.confirm(self, "Jump to %s?" % Galaxy.SYSTEMS[dest]["name"], text, func(): jump_to(dest), "Jump", "Stay")


## Jump through a gate: the next system is built from the Galaxy data and
## you arrive at its gate back to here.
## After your ship is destroyed: back in a new ship at the nearest station
## of this system - everything you've done kept (the main quest, missions,
## reputation, the galaxy...), minus your cargo and RESPAWN_FEE of your
## credits (the insurance). Reloads the space scene like a jump does.
const RESPAWN_FEE := 0.1

func respawn() -> void:
	if SaveGame.travelling:
		return
	SaveGame.pending = respawn_state()
	SaveGame.travelling = true
	get_tree().paused = false
	UI.fade_change_scene("res://main.tscn")


## The game as it goes on after a respawn (see respawn).
func respawn_state() -> Dictionary:
	var state := get_save_data()
	state.erase("enemies")   # (the system's pirates turn up afresh)
	var st := _nearest_station(ship.global_position, INF)
	var at: Vector2 = (st.global_position + Vector2(0, st.radius + 160.0)) if st else Vector2(0, 2600)
	state["ship"] = {"position": [at.x, at.y], "rotation": 0.0, "velocity": [0.0, 0.0], "has_target": false}   # (no hull / shields: a full new ship)
	var pd: Dictionary = state["player"]
	var lost := 0
	for id in pd["items"].keys():
		if Items.is_cargo(id):
			lost += int(pd["items"][id])
			pd["items"].erase(id)
	var fee := int(int(pd["credits"]) * RESPAWN_FEE)
	pd["credits"] = int(pd["credits"]) - fee
	var gone := LostItems.lose_one(pd)   # (and one thing you carried - kills may win it back)
	state["jumped"] = false
	GameLog.post("A new ship at %s. Insurance: %d drachmas%s. Your story, missions and standing are as they were." %
		[st.station_name if st else "the system", fee, (", %d units of cargo lost" % lost) if lost > 0 else ""], "mission")
	if gone != "":
		GameLog.post("Lost in the wreck: %s. Destroying enemies may recover it." % gone, "warning")
	return state


func jump_to(dest: String) -> void:
	if not ship.is_alive() or SaveGame.travelling:
		return
	var from := Galaxy.current_system
	if not dest in Galaxy.neighbors(from):
		return   # gates only connect neighbouring systems
	# A jump burns fuel (Shipyard.FUEL_JUMP): not enough, no jump.
	if not player_data.use_fuel(Shipyard.FUEL_JUMP * maxf(0.3, 1.0 - player_data.mod("fuel_efficiency"))):   # (efficient engines: Upgrades)
		hud.flash_message("Not enough fuel to jump (%d needed, %d in the tank)" % [Shipyard.FUEL_JUMP, floori(player_data.fuel_level())])
		GameLog.post("The gate needs %d fuel to jump - refuel at a station, pump in fuel from your hold, or use a Star Energizer near the sun." % Shipyard.FUEL_JUMP, "danger")
		return
	_set_steering(false)
	ship.stop()
	if not Galaxy.route.is_empty() and Galaxy.route[0] == from:
		Galaxy.route.pop_front()
	Galaxy.current_system = dest
	Galaxy.jumps += 1   # (a beacon gives another report once you've left and come back: NavReports)
	var state := get_save_data()
	Galaxy.rocks[from] = state["asteroids"]   # this system keeps its rocks (depleted ones stay gone; not a ring's)
	for k in ["enemies", "neutrals", "asteroids"]:
		state.erase(k)
	var gate: Vector2 = Galaxy.system(dest)["gates"][from]
	var arrive := gate - gate.normalized() * 520.0
	state["ship"]["position"] = [arrive.x, arrive.y]
	state["ship"]["has_target"] = false
	state["ship"]["velocity"] = [0.0, 0.0]
	state["jumped"] = true
	SaveGame.pending = state
	SaveGame.travelling = true
	GameLog.post("Jumping to %s..." % Galaxy.SYSTEMS[dest]["name"], "mission")
	Sfx.play("space/jump")
	var through := _nearest_gate()
	if through:
		through.flash()
	else:
		Effects.explosion(ship.global_position, 1.2)
	UI.fade_change_scene("res://main.tscn")


## The jump gate nearest your ship (null: none in the system).
func _nearest_gate() -> JumpGate:
	var best: JumpGate = null
	for g in get_tree().get_nodes_in_group("gates"):
		if g is JumpGate and (best == null or ship.global_position.distance_squared_to(g.global_position) < ship.global_position.distance_squared_to(best.global_position)):
			best = g
	return best


func _context_menu(at: Vector2) -> void:
	_set_steering(false)
	var items := []
	if ship.attack_target != null and is_instance_valid(ship.attack_target):
		items.append(["Stop attacking", func(): ship.set_attack_target(null)])
	var contact := _hail_candidate()
	if contact:
		items.append(["Hail %s  (H)" % contact.display_name, func(): hail(contact)])
	items.append(["Sector map  (M)", func(): _open_panel(ship_menu, ship_menu.MAP_TAB)])
	items.append(["Galaxy map  (G)", func(): _open_panel(ship_menu, ship_menu.GALAXY_TAB)])
	items.append(["Level Editor...", func(): level_editor.open()])
	UI.context_menu(self, at, items)


func _spawn_layout(layout: Dictionary) -> void:
	for e in layout.get("enemies", []):
		spawn_ship(Vector2(e[1], e[2]), e[0])
	for n in layout.get("neutrals", []):
		spawn_ship(Vector2(n[1], n[2]), n[0])
	for a in layout.get("asteroids", []):
		spawn_asteroid(a)


func editor_title() -> String:
	return "LEVEL EDITOR  ·  Space"


func editor_tools() -> Array:
	return [
		{"id": "enemy", "label": "Place enemy ship", "options": EnemyTypes.ids(), "help": "Click to place a hostile ship of the chosen class."},
		{"id": "neutral", "label": "Place neutral ship", "options": EnemyTypes.neutral_ids(), "help": "Click to place a civilian ship."},
		{"id": "asteroid", "label": "Place asteroid", "options": ["iron", "titanium", "platinum"], "help": "Click to place an asteroid of the chosen ore."},
		{"id": "erase", "label": "Erase", "help": "Click a ship or asteroid to remove it (story ships can't be erased)."},
	]


func editor_apply(tool: String, opt: int, _brush: int, world: Vector2, phase: String, _start: Vector2) -> void:
	if phase != "press":
		return
	match tool:
		"enemy":
			spawn_ship(world, EnemyTypes.ids()[opt])
		"neutral":
			spawn_ship(world, EnemyTypes.neutral_ids()[opt])
		"asteroid":
			var d := Asteroid.random_data(world)
			d["kind"] = ["iron", "titanium", "platinum"][opt]
			spawn_asteroid(d)
		"erase":
			var best: Node2D = null
			var best_d := 90.0
			for n in enemies.get_children() + neutrals.get_children() + asteroids.get_children():
				if n.get("quest_tag") != null and n.quest_tag != "":
					continue
				var d: float = n.global_position.distance_to(world)
				if d < best_d:
					best = n
					best_d = d
			if best:
				best.free()


func editor_rect_polygon(_a: Vector2, _b: Vector2) -> PackedVector2Array:
	return PackedVector2Array()


## Saves the current enemies, neutral ships and asteroids as the layout new
## games start with.
func editor_save() -> String:
	var data := {"_help": "Start layout for new games, made in the Level Editor (Shift + right-click > Level Editor). Ships are [type, x, y]. Delete this file (or use 'Revert to generated') for random placement.",
		"enemies": [], "neutrals": [], "asteroids": []}
	for e in enemies.get_children():
		if e.quest_tag == "":
			data["enemies"].append([e.type_id, roundi(e.global_position.x), roundi(e.global_position.y)])
	for n in neutrals.get_children():
		data["neutrals"].append([n.type_id, roundi(n.global_position.x), roundi(n.global_position.y)])
	for a in asteroids.get_children():
		data["asteroids"].append(a.get_save_data())
	return DataFiles.write(SPACE_LAYOUT, data)


func editor_revert() -> String:
	for p in [SPACE_LAYOUT, DataFiles.user_path(SPACE_LAYOUT)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return "Start layout deleted - new games use random placement again."


func editor_camera() -> Camera2D:
	return $Ship/Camera2D


# --- Planets ------------------------------------------------------------------

## Land on a planet: snapshot the whole space game (like a save) and switch
## to its surface. Taking off restores the snapshot.
## LAND button: ask first.
func request_land(planet_id: String) -> void:
	if not ship.is_alive() or get_tree().paused or SaveGame.travelling:
		return
	var p: Dictionary = Planets.get_planet(planet_id)
	UI.confirm(self, "Land on %s?" % p["name"], p["desc"], func(): land_on(planet_id), "Land", "Stay in orbit")


func land_on(planet_id: String) -> void:
	if not ship.is_alive() or get_tree().paused or SaveGame.travelling:
		return  # (already on the way down: ignore repeat clicks)
	for e in enemies.get_children():
		if e.is_alive() and e._target == ship and e.global_position.distance_to(ship.global_position) < 1300.0:
			hud.flash_message("Can't land while under attack!")
			GameLog.post("Landing aborted: %s is attacking you" % e.display_name, "danger")
			return
	_set_steering(false)
	ship.stop()
	SaveGame.space_state = get_save_data()   # (back in orbit here after take-off)
	SaveGame.landed_planet = planet_id
	SaveGame.travelling = true
	Scenarios.event("landed", {"planet": planet_id})
	GameLog.post("Landing on %s..." % Planets.get_planet(planet_id)["name"], "mission")
	# Glide to the planet's centre and shrink away, then down to the surface.
	var body := _planet_body(planet_id)
	if body == null:
		UI.fade_change_scene(SURFACE_SCENE)
		return
	# Where you were relative to the planet: it keeps orbiting while you're down.
	SaveGame.orbit_offset = ship.global_position - body.global_position
	_ship_anim_begin()
	Sfx.play("space/land")
	# The surface: built ahead while you flew near the planet (_prebuild) -
	# then it takes the game as it is now - or built now, hidden in the
	# background (heavy parts on worker threads) while the ship lands; the
	# animation lasts until it's ready.
	var surface: Node
	var ahead := surface_ahead(planet_id)
	if ahead:
		surface = ahead
		_surfaces.erase(planet_id)
		AssetPool.forget("surface:" + planet_id)
		if _prebuilt == ahead:
			_prebuilt = null
			_prebuilt_id = ""
		if not surface.is_inside_tree():
			get_tree().root.add_child(surface)   # (parked: back in, under the root - as it was built)
		surface.adopt_state(SaveGame.space_state)
	else:
		surface = load(SURFACE_SCENE).instantiate()
		surface.prebuilding = true
		# (under the root, beside this scene - not in it: becoming the scene then
		# needs no move; moving it took its 5000+ nodes out of the tree and back
		# in, a 230 ms frame)
		get_tree().root.add_child(surface)
	_landing_surface = surface
	_land_animation(body, surface)


var _landing_surface: Node = null


## Every landable planet's surface built ahead, hidden, from the moment you're
## in a system - one at a time, the nearest not built yet first - and kept:
## landing on any of them takes the animation only. Each built one is in the
## memory pool (AssetPool "surface:<id>": used more while you're near it),
## unloaded only if the pool runs out of room, the least used first. They go
## with this scene (a jump, a landing: the others taken apart a few ms a frame).
const PREBUILD_R := 4000.0
## (its size in memory, measured 2026-11-20: five surfaces 199 MB of memory and
## 14 MB of textures - its arrays, ~2400 nodes, tile layers, ground pictures, map)
const SURFACE_BYTES := 44 * 1048576
## How many a browser keeps built ahead (a tab has far less memory: the nearest few).
const WEB_SURFACES := 3
var _surfaces := {}          # planet id -> its surface (built, or being built)
var _prebuilt: Node = null   # the one being built now (the loading console)
var _prebuilt_id := ""
var _prebuild_t := 1.5   # (not in the system's first moments)
## (off in headless runs - the tests, but the one that checks it)
var prebuild_on := DisplayServer.get_name() != "headless"


## A surface built (or being built) ahead for `pid` - null if none.
func surface_ahead(pid: String) -> Node:
	var s: Node = _surfaces.get(pid)
	return s if is_instance_valid(s) else null


func _prebuild_tick(delta: float) -> void:
	_prebuild_t -= delta
	if _prebuild_t > 0.0:
		return
	_prebuild_t = 0.5
	if not prebuild_on or SaveGame.travelling or is_instance_valid(_landing_surface) or not ship.is_alive():
		return
	# The nearest planet's surface used: it stays longest in the pool.
	var near: Node2D = null
	var near_d := INF
	var next: Node2D = null
	var next_d := INF
	for b in get_tree().get_nodes_in_group("planet_bodies"):
		if b.landable and b.planet_id != "":
			var d: float = b.global_position.distance_to(ship.global_position)
			if d < near_d:
				near_d = d
				near = b
			if surface_ahead(b.planet_id) == null and d < next_d:
				next_d = d
				next = b
	# (the pool's usual need: this system's surfaces too - its room twice that)
	var landable := get_tree().get_nodes_in_group("planet_bodies").filter(func(b): return b.landable and b.planet_id != "").size()
	if OS.has_feature("web"):
		landable = mini(landable, WEB_SURFACES)
		if _surfaces.size() >= WEB_SURFACES:
			next = null   # (a browser: the nearest few only)
	AssetPool.set_need_part("surfaces", landable * SURFACE_BYTES)
	if near and near_d < PREBUILD_R:
		AssetPool.touch("surface:" + near.planet_id)
	if is_instance_valid(_prebuilt):
		if not _prebuilt.is_built:
			return   # (one at a time)
		var pid := _prebuilt_id
		_prebuilt = null
		_prebuilt_id = ""
		AssetPool.add("surface:" + pid, SURFACE_BYTES, _drop_surface.bind(pid), Callable(), false,
			"Surface of " + str(Planets.get_planet(pid).get("name", pid)))
	# A built one whose streaming has settled waits out of the tree (parked): in
	# it, its ~2400 hidden, stopped nodes still cost the frame (~11%, measured);
	# out of it, nothing. One a tick (~11 ms); put back as you land (~9 ms).
	for pid in _surfaces:
		var sf: Node = _surfaces[pid]
		if is_instance_valid(sf) and sf != _prebuilt and sf.is_built and sf.is_inside_tree() and sf.streaming_idle():
			sf.get_parent().remove_child(sf)
			break
	if next != null:
		_prebuild(next.planet_id)


func _prebuild(pid: String) -> void:
	var surface: Node = load(SURFACE_SCENE).instantiate()
	surface.prebuilding = true
	surface.background = true
	surface.planet_override = pid
	surface.state_override = get_save_data()
	get_tree().root.add_child(surface)
	_surfaces[pid] = surface
	_prebuilt = surface
	_prebuilt_id = pid
	AssetPool.note("Building the surface of %s ahead (%d of %d)" % [str(Planets.get_planet(pid).get("name", pid)), _surfaces.size(),
		get_tree().get_nodes_in_group("planet_bodies").filter(func(b): return b.landable and b.planet_id != "").size()])


## A surface built ahead let go (the pool ran out of room, or this scene goes).
func _drop_surface(pid: String) -> void:
	var s: Node = _surfaces.get(pid)
	_surfaces.erase(pid)
	AssetPool.forget("surface:" + pid)
	if s == _prebuilt:
		_prebuilt = null
		_prebuilt_id = ""
	if is_instance_valid(s):
		if not s.is_inside_tree():
			s.queue_free()   # (parked out of the tree: freed without the tree's notifications)
		elif s.is_built:
			s.discard = true   # (its ground streaming stops at once: nothing made into what's being taken apart)
			UI.dismantle(s)   # (a few ms a frame)
		else:
			s.discard = true   # (still being built: it finishes, quietly, then takes itself apart - freed at once was a 340 ms frame)


func _drop_prebuild() -> void:
	for pid in _surfaces.keys():
		_drop_surface(pid)


## Turn and glide to the planet's centre, then shrink - slowing down while
## the surface is still being built, finishing once it is - then switch.
func _land_animation(body: Node2D, surface: Node) -> void:
	var from := ship.global_position
	var face := (body.global_position - from).angle() + PI / 2.0
	var tw := create_tween()
	tw.tween_property(ship, "rotation", ship.rotation + wrapf(face - ship.rotation, -PI, PI), 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(u: float): ship.global_position = from.lerp(body.global_position, u), 0.0, 1.0,
		DockAnim.glide_time(from.distance_to(body.global_position))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	var base: Vector2 = ship.sprite.scale
	var p := 0.0
	var t := 0.0
	while true:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		ship.global_position = body.global_position   # (the planet moves on its orbit)
		var built: bool = is_instance_valid(surface) and surface.is_built
		# While building: ease towards 92% shrunk, ever slower; once built: finish.
		var target := 1.0 if built else 0.92 * (1.0 - exp(-t / DockAnim.SHRINK_TIME))
		p = move_toward(p, target, dt / (0.5 if built else DockAnim.SHRINK_TIME * 0.6))
		var e := p * p * (3.0 - 2.0 * p)
		ship.sprite.scale = base * lerpf(1.0, 0.01, e)
		if built and p >= 1.0:
			break
	ship.sprite.visible = false
	UI.fade_change_scene_to_node(surface)


func _planet_body(planet_id: String) -> Node2D:
	for b in get_tree().get_nodes_in_group("planet_bodies"):
		if b.planet_id == planet_id:
			return b
	return null


## Back from a planet: the ship rises out of it to its orbit position.
func _take_off_animation(planet_id: String) -> void:
	await get_tree().process_frame   # planets placed on their orbits first
	var body := _planet_body(planet_id)
	if body == null or not ship.is_alive():
		return
	# Put it (and the planet it orbits) on its orbit now: its own _process may
	# not have run yet, and it would still be at the star.
	if body.parent_body:
		body.parent_body._process(0.0)
	body._process(0.0)
	# Back next to the planet you left, on the side you landed from (it has
	# moved on along its orbit meanwhile) - just outside its disc.
	var off: Vector2 = SaveGame.orbit_offset
	if off.length() < 1.0:
		off = Vector2(1, -1)
	var r: float = body.radius
	off = off.normalized() * clampf(off.length(), r + 220.0, r + 520.0)
	var orbit: Vector2 = body.global_position + off
	SaveGame.orbit_offset = Vector2.ZERO
	ship.global_position = orbit
	$Ship/Camera2D.reset_smoothing()
	_ship_anim_begin()
	Sfx.play("space/take_off")
	DockAnim.out_of(ship, ship.sprite, body.global_position, orbit, _ship_sprite_scale, _ship_anim_end)


func can_save() -> bool:
	return ship.is_alive() and not AttractMode.active


## Under attack (no autosave now): an enemy close by going for you.
func in_combat() -> bool:
	for e in enemies.get_children():
		if e.is_alive() and e._target == ship and e.global_position.distance_to(ship.global_position) < 1600.0:
			return true
	return false


## Everything needed to restore this game later (stored as JSON).
func get_save_data() -> Dictionary:
	var enemy_data := []
	for enemy in enemies.get_children():
		if enemy.is_alive() and enemy.quest_tag == "" and not _in_site_space(enemy) and not enemy.has_meta("pursuit") and enemy.leader == null:  # the quest re-creates its own
			enemy_data.append(enemy.get_save_data())
	var neutral_data := []
	for n in neutrals.get_children():
		if n.is_alive() and n.record_id == "" and not _in_site_space(n):   # traders live in the Galaxy simulation
			neutral_data.append(n.get_save_data())
	var asteroid_data := []
	for rock in asteroids.get_children():
		if rock.is_alive() and not _in_site_space(rock):   # (a ring's rocks belong to its local space)
			asteroid_data.append(rock.get_save_data())
	var ship_data: Dictionary = ship.get_save_data()
	if site != null:   # (saved in a signal site: you'll be back beside its beacon)
		ship_data["position"] = [site.return_point.x, site.return_point.y]
		ship_data["has_target"] = false
	return {
		"asteroids": asteroid_data,
		"neutrals": neutral_data,
		"ship": ship_data,
		"player": player_data.get_save_data(),
		"missions": missions.get_save_data(),
		"quest": quest.get_save_data(),
		"scenarios": Scenarios.get_save_data(),
		"planets": planet_state,
		"kills": kills,
		"enemies": enemy_data,
		"galaxy": Galaxy.get_save_data(),
	}


## Out in a signal site's pocket of space (its ships aren't saved: the site
## starts afresh when you come back).
static func _in_site_space(n: Node2D) -> bool:
	return n.global_position.distance_to(SignalSite.ORIGIN) < SignalSite.BOUNDS * 2.0


func load_save_data(data: Dictionary) -> void:
	# Player data first: it applies tech (max hull/shields), then the ship
	# restores its exact saved hull/shields on top.
	if data.has("player"):
		player_data.load_save_data(data["player"])
	if data.has("missions"):
		missions.load_save_data(data["missions"])
	ship.load_save_data(data.get("ship", {}))
	kills = int(data.get("kills", 0))

	# Arriving in a new system (jump) the lists are missing: populate it.
	# (each ship, monster and rock a piece of the system: nearest first)
	for e in data.get("enemies", []):
		_piece("ship", "", _saved_at(e), spawn_enemy.bind(Vector2.ZERO, e))
	for n in data.get("neutrals", []):
		_piece("ship", "", _saved_at(n), spawn_ship.bind(Vector2.ZERO, "", n))
	# Asteroids: the save's, else this system's as we left them, else fresh fields.
	var rocks: Array = data.get("asteroids", Galaxy.rocks.get(Galaxy.current_system, []))
	var rocks_known: bool = data.has("asteroids") or Galaxy.rocks.has(Galaxy.current_system)
	for a in rocks:
		_piece("rocks", "", _saved_at(a), spawn_asteroid.bind(a))
	_populate_system(not data.has("enemies"), not data.has("neutrals"), not rocks_known)
	if not data.has("neutrals"):   # (arriving by jump: the system's own civilians, miners too)
		_spawn_mining_crew()
	if data.has("enemies"):
		for i in maxi(0, _pirate_count() - data["enemies"].size()):
			_schedule_respawn()

	planet_state = data.get("planets", {})
	# (Scenario state lives on across landing and jumping; a loaded save sets it.)
	if not SaveGame.travelling:
		Scenarios.load_save_data(data.get("scenarios", {}))
		for id in Scenarios.state:
			scenario_host.markers_changed(id)
	if data.has("quest"):
		quest.load_save_data(data["quest"])  # (not started yet: stays that way)

	if ship.has_target:
		marker.show_at(ship.target)
	hud.hint.visible = false
	# Snap the camera to the ship instead of gliding there from the origin.
	$Ship/Camera2D.reset_smoothing()
