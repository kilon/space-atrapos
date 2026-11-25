extends TestCase
## Mods: your changes to the game, any of it, laid over it as it starts - a mod's data,
## scripts and pictures replace the game's (a real start of the game with one turned
## on); merge patches; the Mods screen and the Mod Editor; installing and sharing a mod
## as a zip. And Patch Notes off Talos, on the title screen.


func _cleanup(ids: Array) -> void:
	for id in ids:
		Mods.remove(id)
	EditTarget.mod_id = ""


func test_merge_is_deep() -> void:
	var a := {"a": 1, "b": {"c": 2, "d": [1, 2]}, "e": "x"}
	var m: Dictionary = Mods.merge(a, {"b": {"c": 5, "f": true}, "e": [3]})
	check_eq(m["a"], 1, "untouched keys kept")
	check_eq(m["b"]["c"], 5, "a nested key replaced")
	check_eq(m["b"]["d"], [1, 2], "its sibling kept")
	check_eq(m["b"]["f"], true, "a new nested key added")
	check_eq(m["e"], [3], "a non-object replaced whole")
	check_eq(a["b"]["c"], 2, "the base itself not changed")


func test_mods_list_order_and_zip() -> void:
	var a := Mods.create("Test Mod A")
	var b := Mods.create("Test Mod B")
	check(a != b and DirAccess.dir_exists_absolute(Mods.files_dir(a)), "a mod is a folder with files/")
	check_eq(str(Mods.info(a)["name"]), "Test Mod A", "its mod.json")
	Mods.set_enabled(b, true)
	Mods.set_enabled(a, true)
	check_eq(Array(Mods.enabled()), [b, a], "turned on in order")
	Mods.move(a, -1)
	check_eq(Array(Mods.enabled()), [a, b], "moved earlier")
	check_eq(str(Mods.installed()[0]["id"]), a, "the list in load order")
	check(Mods.needs_restart(), "a change of mods asks for a restart")
	var f := FileAccess.open(Mods.files_dir(a) + "data/x.json", FileAccess.WRITE) if DirAccess.make_dir_recursive_absolute(Mods.files_dir(a) + "data") == OK else null
	f.store_string("{\"k\": 1}")
	f.close()
	check_eq(Array(Mods.mod_files(a)), ["res://data/x.json"], "its files as game paths")
	var zip := "user://test_mod_a.zip"
	check(Mods.export_zip(a, zip), "shared as a zip")
	Mods.remove(a)
	check(not DirAccess.dir_exists_absolute(Mods.DIR + a), "deleted")
	var back := Mods.install_zip(zip)
	check_eq(back, a, "installed from the zip under its id")
	check_eq(FileAccess.get_file_as_string(Mods.files_dir(a) + "data/x.json"), "{\"k\": 1}", "its files back")
	DirAccess.remove_absolute(zip)
	_cleanup([a, b])
	check(Mods.enabled().is_empty(), "turned off as they're deleted")


## A real start of the game with a mod on: its data file, its merge patch, a new
## script, a replaced picture and its own script all in effect.
func test_a_mod_changes_the_game() -> void:
	var id := Mods.create("Test Mod Live")
	var root := Mods.files_dir(id)
	for d in ["data", "scripts/mod_test", "data/sprites", "mods/" + id]:
		DirAccess.make_dir_recursive_absolute(root + d)
	var w := func(rel: String, text: String):
		var f := FileAccess.open(root + rel, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	w.call("data/themes.json.merge", "{\"modded_by_test\": {\"x\": 7}}")
	w.call("scripts/mod_test/thing.gd", "extends RefCounted\nfunc hi() -> int:\n\treturn 42\n")
	w.call("mods/%s/main.gd" % id, "extends Node\nfunc _ready() -> void:\n\tprint(\"MODMAIN ran\")\n")
	var pic := ""
	for f in DirAccess.get_files_at("res://data/sprites"):
		if f.ends_with(".png"):
			pic = f
			break
	Image.create(7, 5, false, Image.FORMAT_RGBA8).save_png(root + "data/sprites/" + pic)
	var m := Mods.info(id)
	m["main"] = "res://mods/%s/main.gd" % id
	Mods.save_info(m)
	Mods.set_enabled(id, true)
	var probe := "user://mod_probe.gd"
	var f := FileAccess.open(probe, FileAccess.WRITE)
	f.store_string("""extends SceneTree
func _initialize() -> void:
	await process_frame
	await process_frame
	var t = JSON.parse_string(FileAccess.get_file_as_string("res://data/themes.json"))
	print("MODJSON ", t.get("modded_by_test", {}).get("x", -1), " ", t.size() > 1)
	print("MODSCRIPT ", load("res://scripts/mod_test/thing.gd").new().hi())
	var tex = load("res://data/sprites/%s")
	print("MODPIC ", tex.get_width(), "x", tex.get_height())
	print("MODACTIVE ", root.get_node("Mods").active.size())
	quit()
""" % pic)
	f.close()
	var out := []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", ProjectSettings.globalize_path(probe)]
	OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(out)
	if not text.contains("MODJSON 7"):
		print(text.right(3000))
	check(text.contains("MODJSON 7"), "a merge patch merged into the game's data (the rest kept)")
	check(text.contains("MODSCRIPT 42"), "a new script of the mod's loads")
	check(text.contains("MODPIC 7x5"), "a picture of the mod's replaces the game's")
	check(text.contains("MODACTIVE 1"), "the mod running")
	check(text.contains("MODMAIN ran"), "its own script ran")
	DirAccess.remove_absolute(probe)
	# A start that never reaches the title screen: the next one runs without mods.
	check(FileAccess.file_exists(Mods.BOOTING), "a start with mods leaves its mark till the title screen")
	out.clear()
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "2"], out, true)
	DirAccess.remove_absolute(Mods.BOOTING)
	_cleanup([id])


func test_mod_editor() -> void:
	var ed: Control = load("res://scenes/editor/mod_editor.tscn").instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	var id: String = ed.new_mod("Test Editor Mod")
	check_eq(EditTarget.mod_id, id, "the tools save into the mod being made")
	check(EditTarget.write_path("res://data/a.json").begins_with(Mods.files_dir(id)), "laid out like the game")
	check(ed.override("res://data/themes.json"), "the game's file copied into the mod")
	check(EditTarget.overridden("res://data/themes.json"), "the mod has its copy")
	check_eq(FileAccess.get_file_as_string(EditTarget.read_path("res://data/themes.json")), FileAccess.get_file_as_string("res://data/themes.json"), "a true copy")
	check(ed._code != null and ed._code.text.length() > 10, "opened as text")
	ed._code.text = "{ broken"
	check(ed.check_text("res://data/themes.json", ed._code.text).begins_with("JSON error"), "bad JSON caught")
	check(ed.merge_patch("res://data/galaxy.json"), "a merge patch started")
	check(ed.new_file("res://scripts/mod_new.gd"), "a new file")
	ed.main_script()
	check(str(Mods.info(id)["main"]) != "" and EditTarget.overridden(str(Mods.info(id)["main"])), "its own script made")
	check_eq(ed.check_text("x.gd", "extends Node\nfunc f(:\n"), "The script doesn't compile - see the output (or Check) for the line.", "a script that doesn't compile caught")
	expect_errors.append("Parse Error")
	ed.dirty = false
	var probs: PackedStringArray = ed.validate()
	check(probs.is_empty(), "a fresh mod checks clean (%s)" % ", ".join(probs))
	check(ed.get_node_or_null("%ModPicker") != null or ed.find_child("ModPicker", true, false) != null, "the mod picker")
	ed.queue_free()
	await tree.process_frame
	check_eq(EditTarget.mod_id, "", "leaving it, the tools save into the game again")
	_cleanup([id])


func test_mods_screen_and_patch_notes() -> void:
	var id := Mods.create("Test Screen Mod")
	var host := Control.new()
	tree.root.add_child(host)
	var s: Control = load("res://scripts/ui/mods_screen.gd").open_over(host)
	await tree.process_frame
	check(s.find_child("Mod_" + id, true, false) != null, "each mod a row")
	s.close()
	await tree.process_frame
	check(host.get_child_count() == 0, "Back closes it")
	var notes: Control = load("res://scripts/editor/patcher.gd").open_over(host)
	await tree.process_frame
	check(notes.find_child("BackButton", true, false) != null, "Patch Notes: a Back button")
	check(notes.find_child("TalosNav", true, false) == null, "not in Talos (no rail)")
	notes._back()
	await tree.process_frame
	check(host.get_child_count() == 0, "Back closes Patch Notes")
	host.queue_free()
	var ids := []
	for t in TalosNav.TOOLS:
		if t is Array:
			ids.append(t[0])
	check(not "svg" in ids and not "patcher" in ids, "Talos: no SVG editor, no Versions")
	check("mesh" in ids and "anim" in ids, "Talos: the mesh and animation editors")
	check(not ResourceLoader.exists("res://scripts/editor/svg_editor.gd"), "the SVG editor gone")
	_cleanup([id])
