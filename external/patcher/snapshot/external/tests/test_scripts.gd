extends TestCase
## Every script in the project compiles.


func test_all_scripts_compile() -> void:
	var n := 0
	for dir in ["res://scripts", "res://scripts/pages", "res://tests"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var s: Variant = load(dir + "/" + f)
			check(s is GDScript, "%s/%s does not load" % [dir, f])
			n += 1
	check(n > 50, "found only %d scripts" % n)


func test_scenes_load() -> void:
	for p in ["res://main.tscn", "res://main_menu.tscn"]:
		check(load(p) is PackedScene, p + " does not load")
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".tscn"):
			check(load("res://scenes/" + f) is PackedScene, f + " does not load")


func test_loading_bakes_everything() -> void:
	var keys := ProcArt.bake_jobs().map(func(j): return j[0])
	for id in EnemyTypes.all_ids():
		check(ProcArt.ship_texture(id) != null, "no sprite for ship " + id)
	for d in StationArt.ids():
		check(keys.has("station_" + d), "loading doesn't load station " + d)
	check_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://main_menu.tscn", "start scene: the title, straight away (the art loads behind it)")


func test_threaded_bake_complete() -> void:
	var t0 := Time.get_ticks_msec()
	while not ProcArt.ready_done and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
	check(ProcArt.ready_done, "the startup bake finished")
	for j in ProcArt.bake_jobs():
		var tex: Texture2D = ProcArt.get_tex(j[0])
		check(tex != null and tex.get_width() > 8, "no texture for " + str(j[0]))
	check(ProcArt.ship_texture("asterion") != null, "boss art (a traced hull)")
