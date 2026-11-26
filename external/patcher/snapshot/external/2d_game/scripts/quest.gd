extends Node
## Main quest runner ("The Thread of Ariadne"). Stage definitions, story and
## lore live in QuestData; this node tracks progress, creates each stage's
## world objects (beacons, relic, quest enemies), reacts to game events and
## plays the dialogue.

signal changed
signal lore_unlocked(id: String)

const BEACON := preload("res://scripts/quest_beacon.gd")

var stage := -1
var finished := false
var lore := {}   # unlocked lore ids

var main: Node        # the game scene (spawning, player data, ship)
var dialogue: Control
var _world: Array = []      # nodes created for the current stage
var _targets: Array = []    # quest ships still alive (kill stages)


func _ready() -> void:
	add_to_group("quest")


func current() -> Dictionary:
	if stage < 0 or stage >= QuestData.STAGES.size():
		return {}
	return QuestData.STAGES[stage]


func chapter_title() -> String:
	var s := current()
	return QuestData.CHAPTERS[s["chapter"]] if not s.is_empty() else ""


# --- Flow ----------------------------------------------------------------------

func start() -> void:
	_enter_stage(0, true)


func _enter_stage(index: int, play_dialogue: bool) -> void:
	_clear_world()
	stage = index
	Themes.chapter = index   # (look presets can depend on the story's chapter)
	_setup_world()
	changed.emit()
	if play_dialogue and not current().is_empty():
		var s := current()
		if index == 0 or QuestData.STAGES[index - 1]["chapter"] != s["chapter"]:
			GameLog.post(QuestData.CHAPTERS[s["chapter"]], "quest")
		if s["type"] != "end":
			GameLog.post("New objective: " + s["objective"], "quest")
	if play_dialogue:
		main.hud.hint.hide()  # the controls hint would show through the dialogue box
		dialogue.play(current().get("dialogue", []), _after_stage_dialogue)
	elif current().get("type", "") == "end":
		finished = true


func _after_stage_dialogue() -> void:
	if current().get("type", "") == "end" and not finished:
		finished = true
		_grant(current())
		main.hud.flash_message("The Thread of Ariadne - main quest complete!")
		GameLog.post("Main quest complete: The Thread of Ariadne", "quest")
		changed.emit()


func _complete_stage() -> void:
	var s := current()
	GameLog.post("Objective complete: " + s["objective"], "good")
	_grant(s)
	_enter_stage(stage + 1, true)


func _grant(s: Dictionary) -> void:
	var data: Node = main.player_data
	var reward: Dictionary = s.get("reward", {})
	var parts := []
	if reward.has("credits"):
		data.add_credits(reward["credits"])
		parts.append("+%d dr" % reward["credits"])
	if reward.has("data_core"):
		data.add_item("data_core", reward["data_core"])
		parts.append("+%d Data Core" % reward["data_core"])
	for id in reward.get("items", {}):
		data.add_item(id, int(reward["items"][id]))
		parts.append("+%d %s" % [int(reward["items"][id]), Items.display_name(id)])
	if reward.has("equipment") and not data.has_equipment(reward["equipment"]):
		data.add_equipment(reward["equipment"])
		parts.append(Items.EQUIPMENT[reward["equipment"]]["name"] + " installed")
	for id in s.get("lore", []):
		if not lore.has(id):
			lore[id] = true
			lore_unlocked.emit(id)
			parts.append("Encyclopedia: " + QuestData.LORE[id]["title"])
	if not parts.is_empty():
		main.hud.flash_message("Objective complete   " + "   ".join(parts))


# --- World objects for the current stage ---------------------------------------

func _setup_world() -> void:
	var s := current()
	_update_labyrinth()
	if Galaxy.current_system != Galaxy.HOME:
		return   # the story happens in the Atrapos system
	match s.get("type", ""):
		"reach":
			if s.has("beacon"):
				var b := Node2D.new()
				b.set_script(BEACON)
				b.style = s["beacon"]
				b.position = s["pos"]
				_add_world(b)
		"kill":
			for entry in s["spawn"]:
				var ship: Node2D = main.spawn_ship(s["pos"] + entry[1], entry[0])
				ship.quest_tag = "main"
				ship.home = s["pos"]
				ship.died.connect(_on_target_died)
				_targets.append(ship)
				_world.append(ship)
			# The relic is already visible while its guards are alive.
			if s.has("relic") and main.player_data.count(s["relic"]) == 0:
				var relic := Pickup.spawn(get_tree(), s["pos"], s["relic"], 1)
				relic.permanent = true
				relic.collectible = false
				relic.velocity = Vector2.ZERO
				_world.append(relic)
		"pickup":
			if main.player_data.count(s["item"]) == 0:
				var relic := Pickup.spawn(get_tree(), s["pos"], s["item"], 1)
				relic.permanent = true
				relic.velocity = Vector2.ZERO
				_world.append(relic)


func _add_world(node: Node2D) -> void:
	main.add_child(node)
	_world.append(node)


func _clear_world() -> void:
	for n in _world:
		if is_instance_valid(n):
			n.queue_free()
	_world.clear()
	_targets.clear()


func _update_labyrinth() -> void:
	var lab := get_tree().get_first_node_in_group("labyrinth")
	if lab:
		# Sealed until the stage that opens it (after Talos falls).
		var open_at := QuestData.STAGES.size()
		for i in QuestData.STAGES.size():
			if QuestData.STAGES[i].get("unseal", false):
				open_at = i
				break
		lab.sealed = stage < open_at and not finished


# --- Events --------------------------------------------------------------------

func _process(_delta: float) -> void:
	var s := current()
	if s.is_empty() or dialogue.is_open():
		return
	var ship: Node2D = main.ship
	if not ship.is_alive() or Galaxy.current_system != Galaxy.HOME:
		return
	match s["type"]:
		"reach":
			if ship.global_position.distance_to(s["pos"]) < s["radius"]:
				_complete_stage()
		"pickup":
			if main.player_data.count(s["item"]) > 0:
				_complete_stage()


func _on_target_died(ship: Node2D) -> void:
	_targets.erase(ship)
	changed.emit()
	if _targets.is_empty() and current().get("type", "") == "kill":
		_complete_stage.call_deferred()


## Called by the game when the player docks (before the station menu shows).
func on_docked(station_name: String) -> void:
	var s := current()
	if s.get("station", "") != station_name:
		return
	match s["type"]:
		"dock":
			_complete_stage()
		"deliver":
			var data: Node = main.player_data
			var items: Dictionary = s["items"]
			for id in items:
				if data.count(id) < items[id]:
					main.hud.flash_message("Still needed for the main quest: " + _needs_text(items))
					return
			for id in items:
				data.remove_item(id, items[id])
			_complete_stage()


# --- Info for the HUD, minimap and quest log -----------------------------------

## World position the player should head for, or null.
func target_position() -> Variant:
	var s := current()
	if finished or (s.is_empty() and stage >= 0):
		return null
	# Away from home: point at the gate that leads back toward Knossos.
	if Galaxy.current_system != Galaxy.HOME:
		var path := Galaxy.find_route(Galaxy.current_system, Galaxy.HOME)
		if path.size() >= 2:
			return Galaxy.system(Galaxy.current_system)["gates"][path[1]]
		return null
	if stage < 0:   # not taken yet: the planet where its giver waits
		var body: Node2D = main._planet_body(str(QuestData.GIVER["planet"])) if main and main.has_method("_planet_body") else null
		return body.global_position if body else null
	match s["type"]:
		"dock", "deliver":
			for st in get_tree().get_nodes_in_group("stations"):
				if st.station_name == s["station"]:
					return st.global_position
		"kill":
			for t in _targets:
				if is_instance_valid(t) and t.is_alive():
					return t.global_position
			return s["pos"]
		"reach", "pickup":
			return s["pos"]
	return null


func objective_text() -> String:
	var s := current()
	if stage < 0 and not finished:
		var g: Dictionary = QuestData.GIVER
		return "Land on %s and talk to %s by the landing pad" % [Planets.get_planet(str(g["planet"]))["name"], g["name"]]
	if s.is_empty():
		return ""
	if finished:
		return "Main quest complete - the archive awaits"
	var text: String = s["objective"]
	match s["type"]:
		"deliver":
			text += "  (" + _needs_text(s["items"], true) + ")"
		"kill":
			text += "  (%d left)" % _targets.size()
	if Galaxy.current_system != Galaxy.HOME:
		text = "Return to the Atrapos system  ·  " + text
	return text


func _needs_text(items: Dictionary, with_progress := false) -> String:
	var parts := []
	for id in items:
		if with_progress:
			parts.append("%s %d/%d" % [Items.display_name(id), mini(main.player_data.count(id), items[id]), items[id]])
		else:
			parts.append("%d %s" % [items[id], Items.display_name(id)])
	return ", ".join(parts)


## All dialogue heard so far, for the journal.
func journal() -> Array:
	var out := []
	for i in mini(stage + 1, QuestData.STAGES.size()):
		out.append([i, QuestData.STAGES[i]])
	return out


# --- Saving --------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"stage": stage, "finished": finished, "lore": lore.keys()}


func load_save_data(data: Dictionary) -> void:
	lore = {}
	for id in data.get("lore", []):
		lore[id] = true
	finished = data.get("finished", false)
	# Rebuild the stage's world (beacons, enemies at full strength, relic)
	# without replaying its dialogue.
	_enter_stage(int(data.get("stage", 0)), false)
	finished = data.get("finished", false)
	_update_labyrinth()
	changed.emit()
