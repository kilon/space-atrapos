extends SceneTree
## A new game, straight into the home system's space (no menus) - for
## measuring and live coding (add --live).
##   godot --path . --resolution 1600x900 -s external/playtests/play_space.gd -- [--live=PORT] [--window-at=X,Y]
func _init():
	await process_frame
	var art = root.get_node("ProcArt")
	while not art.ready_done: await process_frame
	root.get_node("Galaxy").new_game(false)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	print("PLAYSPACE: in space - close the game to end")
