extends SceneTree
## A new game, straight onto a planet's surface (no menus) - for measuring and
## live coding (add --live).
##   godot --path . --resolution 1600x900 -s external/playtests/play_surface.gd -- [planet] [--live=PORT] [--window-at=X,Y]
func _init():
	var args := OS.get_cmdline_user_args()
	var pid: String = args[0] if args.size() > 0 and not args[0].begins_with("--") else "thalassa"
	await process_frame
	var art = root.get_node("ProcArt")
	while not art.ready_done: await process_frame
	root.get_node("Galaxy").new_game(false)
	root.get_node("SaveGame").landed_planet = pid
	var s = load("res://scenes/planet_surface.tscn").instantiate()
	root.add_child(s)
	while not s.is_built: await process_frame
	print("PLAYSURFACE: on %s - close the game to end" % pid)
