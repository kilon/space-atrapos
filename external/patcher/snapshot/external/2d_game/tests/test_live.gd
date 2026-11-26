extends TestCase
## Live updates (LiveLink): which changes hot reload can take and which need
## a restart where you were; the compile check run before a restart.


func test_what_needs_a_restart() -> void:
	expect_errors = ["Expected grouping expression", "live_probe.gd"]   # (the broken source, compiled on purpose)
	var known := {"Items": true, "Gear": true}
	check_eq(LiveLink.new_classes("class_name Items\nextends RefCounted\n", known), [], "a known class: no")
	check_eq(LiveLink.new_classes("class_name ShinyNew\nextends Node\n", known), ["ShinyNew"], "a new class_name: yes")
	check_eq(LiveLink.new_classes("extends Node\nvar class_name_x := 1\n", known), [], "no class_name line: no")
	# A loaded script that loses a variable (renamed / removed): yes; adds one: no.
	var path := "user://live_probe.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends Node\nvar keep := 1\nvar old_name := 2\n")
	f.close()
	var s: Script = load(path)
	check_eq(LiveLink.removed_members(s, "extends Node\nvar keep := 1\nvar new_name := 2\n", path), ["old_name"], "renamed: the old name is gone")
	check_eq(LiveLink.removed_members(s, "extends Node\nvar keep := 1\nvar old_name := 2\nvar more := 3\n", path), [], "only added: hot reload does")
	check_eq(LiveLink.removed_members(s, "extends Node\nvar keep := (\n", path), [], "broken code isn't a reason to restart")
	# Added variables: a restart only while objects of it live in the game
	# (they were made without them - what their _ready sets never gets set).
	check_eq(LiveLink.added_members(s, "extends Node\nvar keep := 1\nvar old_name := 2\nvar _tex: Texture2D\n", path), ["_tex"], "an added variable")
	check_eq(LiveLink.live_nodes_of(tree, s), 0, "none of it in the game: hot reload does")
	var n := Node.new()
	n.set_script(s)
	tree.root.add_child(n)
	check_eq(LiveLink.live_nodes_of(tree, s), 1, "one in the game: a restart")
	n.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A new picture means a restart (it's imported as the game starts again, and
## what looked for it found nothing); a changed one is imported and reloaded.
func test_pictures() -> void:
	var l: Node = load("res://scripts/live_link.gd").new()
	l._new_files["res://data/sprites/brand_new.png"] = true
	check(l._needs_restart(["res://data/sprites/brand_new.png"]).begins_with("a new picture"), "a new picture: restart")
	check_eq(l._needs_restart(["res://data/sprites/nav_beacon.png"]), "", "a changed one: no restart (imported and reloaded)")
	check("res://data/docs/shots" in l.watch_dirs and "jpg" in l.WATCH_EXT, "the docs' screenshots watched too")
	l.free()


## The check before a restart catches a script that doesn't compile.
func test_compile_check_catches_broken_code() -> void:
	expect_errors = ["live_broken.gd", "Expected parameter name"]   # (broken on purpose)
	var path := "user://live_broken.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("extends Node\nfunc x(:\n")
	f.close()
	var s: Script = load(path)
	check(s == null or not s.can_instantiate(), "a script with an error can't be used (what live_check looks for)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var ok: Script = load("res://scripts/rich_field.gd")
	check(ok != null and ok.can_instantiate(), "a good one can")
	check(FileAccess.file_exists("res://tools/live_check.gd"), "the checker is there")


## Live updates are on in a run from the project, off in the tests (headless)
## and in exports; the restart's resume slot is a save slot of its own.
func test_live_defaults() -> void:
	check(not LiveLink.auto_reload, "off headless (the tests)")
	check(not SaveGame.LIVE in SaveGame.all_slots(), "the live restart's save isn't in the lists")
	check(SaveGame.slot_path(SaveGame.LIVE).ends_with("live_restart.json"), "a file of its own")


## A class that names itself ("-> RichField") compiles on the side (the check
## before every hot reload) - it used to fail there and never reload.
func test_self_named_class_compiles_on_the_side() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/rich_field.gd")
	check(src.contains("-> RichField"), "rich_field.gd names itself")
	check(LiveLink.compiles(src, "res://scripts/rich_field.gd"), "and compiles on the side")
	check(not LiveLink.trial_source(src).contains("class_name"), "the copy without its class_name")
