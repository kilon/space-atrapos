extends SceneTree
## Screenshots of one patch's steps in the Patcher (and its code review tab).
##   godot --path . --resolution 1600x900 --position 0,30 -s external/playtests/patcher_shots.gd -- <patch id> <out_dir> [review files...] --window-at=0,30
func _init():
	var args := OS.get_cmdline_user_args()
	var want: String = args[0]
	var out: String = args[1]
	await process_frame
	var art = root.get_node("ProcArt")
	while not art.ready_done: await process_frame
	var p = load("res://scenes/editor/patcher.tscn").instantiate()
	root.add_child(p)
	for i in 30: await process_frame
	var idx := -1
	for i in p.patches.size():
		if str(p.patches[i].get("id", "")) == want and not p.is_version(i): idx = i
	if idx < 0:
		print("no patch ", want); quit(); return
	p.show_patch(idx)
	p._tabs.current_tab = 0   # (the infographic: it may open on the code review)
	var n: int = p.patches[idx]["steps"].size()
	for s in n:
		p.go_step(s, true)
		var t := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t < 3200: await process_frame
		root.get_viewport().get_texture().get_image().save_png("%s/step_%02d.png" % [out, s + 1])
	print("SHOTS ", n)
	# The code review: the files named after the out dir (-- <id> <out> [file...]).
	var want_files: Array = Array(args.slice(2)).filter(func(a): return not a.begins_with("--"))
	if not want_files.is_empty():
		p._tabs.current_tab = 1
		for f in want_files:
			for r in p._rows.size():
				var k: int = p._rows[r]
				var path := str(p.patches[idx]["review"]["files"][k]["path"]) if k >= 0 else ""
				if path == f:
					p.show_file(r)
					var t := Time.get_ticks_msec()
					while Time.get_ticks_msec() - t < 1500: await process_frame
					root.get_viewport().get_texture().get_image().save_png("%s/review_%s.png" % [out, f.get_file().get_basename()])
		print("REVIEW SHOTS")
	quit()
