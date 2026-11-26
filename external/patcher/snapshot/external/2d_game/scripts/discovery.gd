class_name Discovery
## What you've discovered, for the Encyclopedia: the entries it lists stay
## "? ? ?" until you've met the thing - a ship class that came near, a station
## you came up to, an asteroid kind you got close to, a planet or a nebula you
## flew by, weapons and systems seen at a station's outfitter or fitted, items
## you've held. Keys: "ship:<type id>", "station:<name>", "asteroid:<kind>",
## "planet:<id>", "nebula", "gear:<id>", "item:<id>".
## Kept in PlayerData.discovered (saved); on a planet, in the surface's
## state["player"] (the same data, as a dictionary).

const SHIP_RANGE := 1800.0       # a ship this near (about a screen) is seen
const ROCK_RANGE := 800.0
const PLANET_RANGE := 700.0      # beyond the planet's disc
const NEBULA_RANGE := 2200.0


## The discovered set: PlayerData's in space; on a planet, the surface state's
## player dictionary (saved as a list of keys - made a dictionary in place).
static func _known_set(tree: SceneTree) -> Dictionary:
	var pd: Node = tree.get_first_node_in_group("player_data") if tree else null
	if pd != null:
		return pd.discovered
	var player: Dictionary = {}
	var scene: Node = tree.current_scene if tree else null
	var st: Variant = scene.get("state") if scene else null
	if st is Dictionary and st.has("player"):
		player = st["player"]
	elif SaveGame.space_state is Dictionary and SaveGame.space_state.has("player"):
		player = SaveGame.space_state["player"]
	var d: Variant = player.get("discovered")
	if not (d is Dictionary):
		var made := {}
		for k in (d if d is Array else []):
			made[str(k)] = true
		player["discovered"] = made
	return player["discovered"]


static func known(tree: SceneTree, key: String) -> bool:
	return _known_set(tree).get(key, false)


## True if it was new.
static func mark(tree: SceneTree, key: String) -> bool:
	var d := _known_set(tree)
	if d.get(key, false):
		return false
	d[key] = true
	return true


## (Main, now and then) What's near the ship now.
static func scan(main: Node) -> void:
	var tree := main.get_tree()
	var ship: Node2D = main.ship
	if ship == null or not ship.is_alive():
		return
	var at: Vector2 = ship.global_position
	for g in ["enemies", "neutrals"]:
		for e in tree.get_nodes_in_group(g):
			if e.is_alive() and at.distance_to(e.global_position) < SHIP_RANGE:
				mark(tree, "ship:" + str(e.type_id))
	for st in tree.get_nodes_in_group("stations"):
		if at.distance_to(st.global_position) < st.dock_radius * 2.5:
			mark(tree, "station:" + str(st.station_name))
	for a in tree.get_nodes_in_group("asteroids"):
		if at.distance_to(a.global_position) < ROCK_RANGE:
			mark(tree, "asteroid:" + str(a.kind))
	for b in tree.get_nodes_in_group("planet_bodies"):
		if str(b.planet_id) != "" and at.distance_to(b.global_position) < b.radius + PLANET_RANGE:
			mark(tree, "planet:" + str(b.planet_id))
	var nebs: Node = main.get_node_or_null("Nebulae")
	if nebs:
		for n in nebs.get_children():
			if n is Node2D and at.distance_to(n.global_position) < NEBULA_RANGE:
				mark(tree, "nebula")
