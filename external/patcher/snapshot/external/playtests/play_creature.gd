extends SceneTree
## Playtest by hand: a new game, dropped straight into a monster signal of the
## given creature - you fly it; the test ends when you close the game.
##   godot --path . --resolution 1920x1080 -s external/playtests/play_creature.gd -- <skylla|cerberus|cetus|echidna|hydra|chimera|charybdis> [--window-at=0,1020]
## (--window-at: where the window goes - Settings keeps it there instead of centring it)
func _init():
	var args := OS.get_cmdline_user_args()
	var want: String = args[0] if args.size() > 0 and not args[0].begins_with("--") else "hydra"
	await process_frame
	var art = root.get_node("ProcArt")
	while not art.ready_done: await process_frame
	var G = root.get_node("Galaxy")
	G.new_game(false)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 60: await process_frame
	var SS = load("res://scripts/signal_site.gd")
	var sg: Dictionary = G.signals_in()[0].duplicate()
	var n := 0
	while true:
		sg["id"] = "play:%d" % n
		if SS.CREATURES[absi(hash(sg["id"])) % SS.CREATURES.size()][0] == want: break
		n += 1
	sg["kind"] = "monster"; sg["located"] = true; sg["done"] = false
	G.signals_in().append(sg)
	main.refresh_beacons()
	var b = main._beacons[sg["id"]]
	main.ship.global_position = b.global_position
	main.enter_site(b)
	print("PLAYTEST: in the %s's signal - close the game to end" % want)
