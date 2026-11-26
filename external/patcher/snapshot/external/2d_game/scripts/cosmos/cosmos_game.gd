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


## A game for the 3D world: the latest save continued, or a new one.
static func begin(continue_save: bool) -> void:
	_fresh_data()
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
	data = load("res://scripts/player_data.gd").new()
	data.name = "CosmosPlayerData"
	root.add_child.call_deferred(data)
	missions = load("res://scripts/missions.gd").new()
	missions.name = "CosmosMissions"
	root.add_child.call_deferred(missions)
	quest = CosmosQuest.new()
	quest.name = "CosmosQuest"
	root.add_child.call_deferred(quest)


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
	extra["hull"] = c.ship.hull
	extra["shield"] = c.ship.shield
	st["cosmos3d"] = extra.duplicate(true)
	return st


static func save(c: Node) -> bool:
	var st := snapshot(c)
	var ok := SaveGame.save_game(st, SLOT)
	if ok:
		state = st
	return ok
