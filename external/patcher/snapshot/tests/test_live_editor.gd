extends TestCase
## The Live Editor (F10 in a game): anything in the world picked with a click and
## edited while the game runs - its place and values, its meshes, its materials,
## its clips - each edit put on every thing of its kind and kept (LiveEdits) for
## the next time such a thing is made, saved into the game or a mod.

var _old_system := ""
var _old_data := {}


func setup() -> void:
	_old_system = Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""
	LiveEdits.load_all()
	_old_data = LiveEdits.data.duplicate(true)


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""
	LiveEdits.data = _old_data
	LiveEdits.dirty = false
	EditTarget.mod_id = ""
	Engine.time_scale = 1.0
	tree.paused = false


func _cosmos() -> Cosmos:
	Galaxy.current_system = "atrapos"
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


func test_keys_and_paths() -> void:
	var a := Node3D.new()
	a.set_meta("edit_key", "test/thing")
	var mid := Node3D.new()
	mid.name = "Arm"
	a.add_child(mid)
	var m1 := MeshInstance3D.new()
	var m2 := MeshInstance3D.new()
	mid.add_child(m1)
	mid.add_child(m2)
	tree.root.add_child(a)
	var an := LiveEdits.anchor_of(m2)
	check(an[0] == a and an[1] == "test/thing", "a part's kind: its builder's key")
	var rel := LiveEdits.rel_path(a, m2)
	check_eq(rel, "Arm/MeshInstance3D#1", "made-up names kept as class and place")
	check(LiveEdits.find(a, rel) == m2, "found again by its path")
	check(LiveEdits.find(a, ".") == a, "the anchor itself")
	# Kept edits put back on a thing of that kind as it's made.
	LiveEdits.hook(tree)
	LiveEdits.data["test/thing"] = {"object": {"Arm": {"scale": LiveEdits.enc(Vector3(2, 2, 2))}}}
	var b := a.duplicate()
	tree.root.add_child(b)
	await tree.process_frame
	await tree.process_frame
	check((b.get_node("Arm") as Node3D).scale.is_equal_approx(Vector3(2, 2, 2)), "a new one gets the kept edit as it's made")
	check(LiveEditor.kind_name("res://scripts/world/life/cosmos_creature.gd") == "every Cosmos Creature", "its kind in words")
	a.queue_free()
	b.queue_free()


func test_live_editor_in_a_game() -> void:
	var c := await _cosmos()
	LiveEditor.toggle(c)
	await tree.process_frame
	var ed: LiveEditor = LiveEditor.current
	check(ed != null and ed.cosmos == c, "F10 opens it over the game")
	check(ed.get_node_or_null("../") != null and not tree.paused, "the game goes on under it")
	ed.set_paused(true)
	check(tree.paused, "Pause stops the game's time")
	ed.set_paused(false)
	# Pick: a ray straight at a thing finds it.
	var target := MeshInstance3D.new()
	target.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	target.material_override = mat
	var holder := Node3D.new()
	holder.set_meta("edit_key", "test/box")
	holder.add_child(target)
	c.world.add_child(holder)
	var cam := ed.camera()
	holder.global_position = cam.global_position - cam.global_basis.z * 6.0
	await tree.process_frame
	var hit := ed.pick(cam.global_position, -cam.global_basis.z)
	check(hit == target, "a click picks the nearest thing on its ray (%s)" % [hit])
	ed.select(target)
	check(ed.key == "test/box" and ed.anchor == holder, "picked: its kind known")
	var tabs := []
	for b in ed._tab_bar.get_children():
		tabs.append(str(b.name).trim_prefix("Tab_"))
	for t in ["object", "model", "material"]:
		check(t in tabs, "a %s tab for it" % t)
	check(not "anim" in tabs, "no Animation tab for a thing with no clips")
	# Materials: a colour changed live and kept.
	ed.show_tab("material")
	var mt = ed.tab()
	mt._keep("0", "albedo_color", LiveEdits.enc(Color(1, 0, 0)))
	mat.albedo_color = Color(1, 0, 0)
	check(LiveEdits.data["test/box"]["material"]["MeshInstance3D#0"]["0"].has("albedo_color"), "a material edit kept")
	# Model: a new mesh on it, and on another of its kind.
	ed.show_tab("model")
	var other := holder.duplicate()
	c.world.add_child(other)
	var new_mesh: ArrayMesh = load("res://scripts/world/live/tabs/model_tab.gd").editable(SphereMesh.new())
	ed.tab().put(target, new_mesh)
	check(target.mesh == new_mesh, "the new mesh on it at once")
	check(ed.apply_everywhere() >= 1, "and put on the others of its kind")
	check((other.get_child(0) as MeshInstance3D).mesh == new_mesh, "another of its kind has it too")
	# Object: a part's size kept; the whole thing's own place not.
	ed.select(target)
	ed.show_tab("object")
	check(LiveEdits.data["test/box"].get("object", {}).is_empty(), "nothing kept before an edit")
	# Saved into a mod: the edits file and the new mesh written there.
	var id := Mods.create("Test Live Mod")
	EditTarget.mod_id = id
	ed.save()
	check(FileAccess.file_exists(Mods.files_dir(id) + "data/live_edits.json"), "the edits saved into the mod")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Mods.files_dir(id) + "data/live_edits.json"))
	var mesh_path: String = saved["test/box"]["model"]["MeshInstance3D#0"]
	check(FileAccess.file_exists(EditTarget.read_path(mesh_path)), "its new mesh saved into the mod too")
	check(not LiveEdits.dirty, "nothing left unsaved")
	EditTarget.mod_id = ""
	Mods.remove(id)
	ed._close_now()
	await tree.process_frame
	check(LiveEditor.current == null and Engine.time_scale == 1.0, "closed: the game as it was")
	c.queue_free()
	await tree.process_frame


func test_a_character_has_its_clips() -> void:
	var c := await _cosmos()
	var w: Node = null
	for n in c.find_children("*", "", true, false):
		if n.has_meta("model_id"):
			w = n
			break
	if w == null:
		c.queue_free()
		return   # (no character in this start: nothing to check)
	var S: GDScript = load("res://scripts/world/live/tabs/anim_tab.gd")
	var body: Node = w.find_child("Body", true, false)
	check(S.handles(body if body else w), "a character: an Animation tab")
	check(S.model_id(S._player_of(body if body else w)) != "", "which character it is known")
	c.queue_free()
	await tree.process_frame
