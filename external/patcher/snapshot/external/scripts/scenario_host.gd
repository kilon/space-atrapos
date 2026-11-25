extends Node
## The space scene's side of the quest scenarios (Scenarios): it ticks the
## rules, and does what they ask in the world - spawning ship groups and
## floating items, placing markers (beacons), playing dialogue, messages,
## rewards, the HUD's scenario objectives. Places are written as
##   player | station:<name> | planet:<id> | gate:<system> | point:<x>,<y> | marker:<name>

const BEACON := preload("res://scripts/quest_beacon.gd")

var main: Node
var _markers := {}            # scenario id -> {marker name: Node2D}
var _dialogue_queue: Array = []
var _objectives: VBoxContainer


func _ready() -> void:
	add_to_group("scenario_host")
	Scenarios.host = self
	for id in Scenarios.state:
		markers_changed(id)
	_respawn_here.call_deferred()


## A new system (or the game loaded): every scenario's ships still to be
## destroyed here come out - those left behind when you jumped away, and
## those ordered for a place in this system while you were elsewhere.
func _respawn_here() -> void:
	for id in Scenarios.state:
		if Scenarios.state[id].get("status") == "active":
			spawn_pending(id, true)
			drop_pending(id, true)


## A scenario's dropped items that belong in this system and aren't out yet.
func drop_pending(id: String, arrived := false) -> void:
	for r in Scenarios.state.get(id, {}).get("drops", []):
		if r["taken"] or (r["system"] != "" and (r["system"] != Galaxy.current_system or not arrived)):
			continue
		var at = place_position(id, str(r["place"]))
		if at == null:
			continue
		r["system"] = Galaxy.current_system
		var p := Pickup.spawn(get_tree(), at, str(r["item"]), 1)
		p.permanent = true
		p.velocity = Vector2.ZERO


## Spawns a scenario's ships that belong in this system and aren't out yet
## (`arrived`: the system was just entered - every one still alive here).
func spawn_pending(id: String, arrived := false) -> void:
	var spawns: Array = Scenarios.state.get(id, {}).get("spawns", [])
	for i in spawns.size():
		var r: Dictionary = spawns[i]
		if int(r["left"]) <= 0:
			continue
		if r["system"] != "" and (r["system"] != Galaxy.current_system or not arrived):
			continue   # (elsewhere; or here and already out)
		var at = place_position(id, str(r["place"]))
		if at == null:
			continue   # (not in this system: when you get there)
		r["system"] = Galaxy.current_system
		for k in int(r["left"]):
			var off := Vector2.from_angle(TAU * k / maxf(int(r["left"]), 1)) * (120.0 + 60.0 * (k % 2))
			var s: Node2D = main.spawn_ship(at + off, str(r["ship_type"]))
			s.quest_tag = "scenario:%s:%s:%d" % [id, r["group"], i]
			s.home = at


func _exit_tree() -> void:
	if Scenarios.host == self:
		Scenarios.host = null


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var dlg: Control = main.get_node_or_null("Panels/Dialogue")
	if dlg and dlg.is_open():
		return
	if not _dialogue_queue.is_empty() and dlg:
		dlg.play(_dialogue_queue.pop_front(), func(): pass)
		return
	Scenarios.tick(delta)


# --- What the rules can ask about -------------------------------------------------

func player_position() -> Variant:
	return main.ship.global_position if main and main.ship and main.ship.is_alive() else null


func item_count(item: String) -> int:
	if item == "credits":
		return credits()
	return main.player_data.count(item)


func credits() -> int:
	return int(main.player_data.credits)


## Where a place is in this system (null: not here).
func place_position(id: String, place: String) -> Variant:
	var kind := place.get_slice(":", 0)
	var arg := place.substr(kind.length() + 1)
	match kind:
		"player":
			return player_position()
		"station":
			for st in get_tree().get_nodes_in_group("stations"):
				if st.station_name == arg:
					return st.global_position + Vector2(380, 0)
		"planet":
			for b in get_tree().get_nodes_in_group("planet_bodies"):
				if b.planet_id == arg or b.title == arg:
					return b.global_position + Vector2(0, b.radius + 260.0)
		"gate":
			var gates: Dictionary = Galaxy.system(Galaxy.current_system).get("gates", {})
			if gates.has(arg):
				return gates[arg] - (gates[arg] as Vector2).normalized() * 400.0
		"point":
			var xy := arg.split(",")
			if xy.size() == 2:
				return Vector2(float(xy[0]), float(xy[1]))
		"marker":
			var m = Scenarios.state.get(id, {}).get("markers", {}).get(arg)
			if m != null and m[2] == Galaxy.current_system:
				return place_position(id, m[0])
	return null


# --- What the rules can do ---------------------------------------------------------

func objectives_changed() -> void:
	if _objectives == null:
		var hud: Node = main.hud
		var anchor: Control = hud.get("_quest_objective")
		if anchor == null:
			return
		_objectives = VBoxContainer.new()
		anchor.get_parent().add_child(_objectives)
		anchor.get_parent().move_child(_objectives, anchor.get_index() + 1)
	for c in _objectives.get_children():
		c.queue_free()
	for o in Scenarios.objectives():
		var t := UI.label(o[0].to_upper(), 13, UI.GOLD)
		_objectives.add_child(t)
		var l := UI.label(o[1], 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objectives.add_child(l)


func play_dialogue(lines: Array) -> void:
	if not lines.is_empty():
		_dialogue_queue.append(lines)


func message(text: String) -> void:
	main.hud.flash_message(text)
	GameLog.post(text, "quest")


func give_item(item: String, count: int) -> void:
	if item == "credits":
		add_credits(count)
	else:
		main.player_data.add_item(item, count)
		GameLog.loot(Items.display_name(item), count)


func take_item(item: String, count: int) -> void:
	main.player_data.remove_item(item, count)


func add_credits(amount: int) -> void:
	main.player_data.add_credits(amount)


## (older callers: the spawn records do it now - Scenarios "spawn")
func spawn(id: String, _group: String, _ship_type: String, _count: int, _place: String) -> void:
	spawn_pending(id)


## (older callers: the drop records do it now - Scenarios "drop_item")
func drop_item(id: String, _item: String, _place: String) -> void:
	drop_pending(id)


func markers_changed(id: String) -> void:
	for n in _markers.get(id, {}).values():
		if is_instance_valid(n):
			n.queue_free()
	_markers[id] = {}
	var ms: Dictionary = Scenarios.state.get(id, {}).get("markers", {})
	for name in ms:
		var m: Array = ms[name]
		if m[2] == "" and place_position(id, m[0]) != null:
			m[2] = Galaxy.current_system   # (a named place: it's in this system)
		if m[2] != Galaxy.current_system or m[1] == "none":
			continue
		var at = place_position(id, m[0])
		if at == null:
			continue
		var b := Node2D.new()
		b.set_script(BEACON)
		b.style = m[1]
		b.position = at
		main.add_child(b)
		_markers[id][name] = b


func unlock_lore(lore_id: String) -> void:
	var q: Node = main.quest
	if QuestData.LORE.has(lore_id) and not q.lore.has(lore_id):
		q.lore[lore_id] = true
		q.lore_unlocked.emit(lore_id)
		main.hud.flash_message("Encyclopedia: " + str(QuestData.LORE[lore_id]["title"]))
