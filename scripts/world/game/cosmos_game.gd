class_name CosmosGame
extends RefCounted
## The game behind the 3D game (stage 5): YOUR game - the same save as the 2D
## game's. "3D Space - Continue" loads the latest save (the galaxy, your
## credits, cargo and gear - PlayerData - and the system you're in); saving
## (docking, jumping, the Save terminal, the Esc menu) writes the game back
## in the same format, every section the 3D game doesn't touch carried over
## as it was - so the 2D game loads it too (your ship where you were, in its
## map units). The 3D game's own things - its ship's upgrades, a bounty
## contract, hull and shields - ride along in the save's "cosmos3d" section.
##   CosmosGame.begin(true)   # (the title: continue the latest save)

const SLOT := SaveGame.AUTO
static var state := {}            # the save as loaded (its other sections kept as they were)
static var data: Node             # PlayerData: credits, cargo, gear (in the tree, under the root)
static var missions: Node         # Missions (the 2D game's: offers, active ones) - under the root too
static var quest: CosmosQuest     # the main quest's stage
static var extra := {}            # the 3D game's own: {upgrades, contract, hull, shield}
static var from_save := false
static var started := false


## A game from a save's state (SaveGame.load_slot: the slot's "state").
static func begin_state(st: Dictionary) -> void:
	_fresh_data()
	CosmosPlanet.reset_spin(Settings.day_length)   # (the worlds' turn from the galaxy's clock: CosmosPlanet's day)
	state = st
	extra = st.get("cosmos3d", {}).duplicate(true)
	from_save = not st.is_empty()
	Cosmos._placed_from_save = false
	if st.has("galaxy"):
		Galaxy.load_save_data(st["galaxy"])
	if st.has("player"):
		data.load_save_data(st["player"])
	if st.has("missions"):
		missions.load_save_data(st["missions"])
	if st.has("quest"):
		quest.load_save_data(st["quest"])
	started = true


## A game for the 3D world: the latest save continued, or a new one.
static func begin(continue_save: bool) -> void:
	_fresh_data()
	CosmosPlanet.reset_spin(Settings.day_length)
	state = {}
	extra = {}
	from_save = false
	Cosmos._placed_from_save = false
	if continue_save:
		var parsed := SaveGame.read_save(-1)
		if not parsed.is_empty():
			state = parsed.get("state", {})
			if state.has("galaxy"):
				Galaxy.load_save_data(state["galaxy"])
			if state.has("player"):
				data.load_save_data(state["player"])
			if state.has("missions"):
				missions.load_save_data(state["missions"])
			if state.has("quest"):
				quest.load_save_data(state["quest"])
			extra = state.get("cosmos3d", {}).duplicate(true)
			from_save = true
	started = true


static func _fresh_data() -> void:
	for n in [data, missions, quest]:
		if n and is_instance_valid(n):
			n.queue_free()
	var root := (Engine.get_main_loop() as SceneTree).root
	data = load("res://scripts/sim/player_data.gd").new()
	data.name = "CosmosPlayerData"
	root.add_child.call_deferred(data)
	missions = load("res://scripts/sim/missions.gd").new()
	missions.name = "CosmosMissions"
	root.add_child.call_deferred(missions)
	quest = CosmosQuest.new()
	quest.name = "CosmosQuest"
	root.add_child.call_deferred(quest)


## A new game's start (from the title): on foot on Amnissos, by a city, with no
## ship yet - your rifle, mining beam and scanner; the tutorial with you.
static func start_on_foot() -> void:
	extra["no_ship"] = true
	extra["start"] = "Amnissos"
	extra["tutor"] = {"step": 0}
	if data:
		data.ship_value = 0
		data.ship_class = ""


## Your own ship? (Not yet, at the start: bought - or got another way - later.)
static func has_ship() -> bool:
	return not bool(extra.get("no_ship", false))


## Makes sure there's a game (a scene run on its own, a test).
static func ensure() -> void:
	if not started or data == null or not is_instance_valid(data):
		begin(false)


## The game as a save: the loaded state, brought up to date.
static func snapshot(c: Node) -> Dictionary:
	var st := state.duplicate(true)
	st["player"] = data.get_save_data()
	st["missions"] = missions.get_save_data()
	st["quest"] = quest.get_save_data()
	st["galaxy"] = Galaxy.get_save_data()
	var ship: Dictionary = st.get("ship", {})
	var p: Vector3 = c.system_position()
	ship["position"] = [p.x / PlanetShape.PX_TO_M, p.z / PlanetShape.PX_TO_M]
	ship["velocity"] = [0.0, 0.0]
	ship["has_target"] = false
	st["ship"] = ship
	# (on foot in a port your ship isn't in: where you are, to come back to there)
	extra.erase("foot_at")
	extra.erase("on_planet")
	if not c.ship_elsewhere:
		extra.erase("ship_at")   # (with you, or docked: no note of it left elsewhere)
	var h: Node = c.get("hangar")
	var w: Node = c.get("walker")
	# (on foot on a world, your ship not with you - or none yet: where you stand)
	if w and w.get("deck") == null and w.get("planet") and (c.ship_elsewhere or not has_ship()):
		var pl: Node3D = w.planet
		var lat: Vector3 = pl.to_local(w.global_position)   # (planet-local: the same ground under you whenever it's loaded - the world's turned since)
		extra["on_planet"] = {"planet": str(pl.rec.get("name", "")), "at": [lat.x, lat.y, lat.z]}
		var wp: Vector3 = w.global_position + c.origin
		ship["position"] = [wp.x / PlanetShape.PX_TO_M, wp.z / PlanetShape.PX_TO_M]
		st["ship"] = ship
	if w and h and is_instance_valid(h) and w.get("deck") == h and not c.ship_in_port(h):
		extra["foot_at"] = {"station": str(h.station.record.get("id", "")), "platform": int(h.platform)}
		if not c.ship_elsewhere and c.docked and c.dock_station:   # (your ship docked elsewhere in this system)
			extra["ship_at"] = {"system": c.system_id, "station": str(c.dock_station.record.get("id", "")), "pad": int(c.dock_pad.get("id", 0))}
		var sp: Vector3 = h.station.global_position + c.origin
		ship["position"] = [sp.x / PlanetShape.PX_TO_M, sp.z / PlanetShape.PX_TO_M]
		st["ship"] = ship
	extra["hull"] = c.ship.hull
	extra["shield"] = c.ship.shield
	st["cosmos3d"] = extra.duplicate(true)
	return st


static func save(c: Node) -> bool:
	if c.has_method("can_save") and not c.can_save():
		return false   # (aboard a moving ship: not now)
	var st := snapshot(c)
	var ok := SaveGame.save_game(st, SLOT)
	if ok:
		state = st
	return ok
