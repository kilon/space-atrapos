extends TestCase
## The mesh editor's material editor: the material library (the open model's materials, every
## character's, the game's looks, your own - data/materials.json or a mod's merge file), the
## Materials tab, the MATERIAL panel (a character's material: only colour, metal, roughness and
## glow), giving materials to surfaces and to selected faces, undo, saving into a mod.

const SCENE := "res://scenes/editor/mesh_editor.tscn"
const Lib := preload("res://scripts/editor/mesh/material_library.gd")


func _editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	return ed


func _done(ed: Control) -> void:
	ed.dirty = false
	ed.queue_free()
	await tree.process_frame


func teardown() -> void:
	EditTarget.mod_id = ""


func _surface_named(p: MeshInstance3D, nm: String) -> int:
	for i in p.mesh.get_surface_count():
		var m := p.mesh.surface_get_material(i)
		if m and m.resource_name == nm:
			return i
	return -1


## The library lists every character's named materials (who wears each), the game's looks, and
## - the pirate open - the pirate's own materials as "This model".
func test_library_lists_characters_and_the_model() -> void:
	var lib := Lib.new()
	lib.load_all()
	check(lib.has("char:PIR_Gold") and "pirate" in lib.entry("char:PIR_Gold")["users"], "the pirate's gold, worn by the pirate")
	check(lib.has("char:AUT_Armor") and lib.entry("char:AUT_Armor")["users"].size() >= 4, "the automaton armour, worn by several (%s)" % [lib.entry("char:AUT_Armor").get("users", [])])
	check(not lib.has("char:KIT_Ink"), "the outline ink left out")
	check_eq(lib.ids("preset").size(), MeshIO_presets(), "every preset look")
	check(lib.ids("character", "gold pirate").has("char:PIR_Gold"), "found by words (name and wearer)")
	var ed := await _editor()
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var names: Array = ed.mat_tools.lib.ids("model").map(func(id): return str(ed.mat_tools.lib.entry(id)["name"]))
	check("PIR_Gold" in names and "PIR_Coat" in names, "This model: the pirate's own materials (%d)" % names.size())
	check(ed.mat_tools.lib.ids("character").size() > names.size(), "and other characters' materials")
	check(ed.mat_tools.lib.entry(ed.mat_tools.lib.ids("model")[0])["kind"] == "character", "a character's are of the character kind")
	await _done(ed)


func MeshIO_presets() -> int:
	return load("res://scripts/editor/mesh/mesh_io.gd").PRESETS.size()


## A new material made, edited, given to a box's surface (the surface shows it); edited again -
## both boxes that have it change; undo takes the edits and the giving back.
func test_new_material_edited_and_assigned() -> void:
	var mid: String = Mods.create("t_mat")
	EditTarget.mod_id = mid
	var ed := await _editor()
	var mt = ed.mat_tools
	var a: MeshInstance3D = ed.add_primitive("box")
	var b: MeshInstance3D = ed.add_primitive("box")
	var old_mat: Material = a.mesh.surface_get_material(0)
	var id: String = mt.new_material()
	check(mt.lib.entry(id)["group"] == "mine" and mt.lib.entry(id)["kind"] == "standard", "a new material of mine (a full one: not a character)")
	check_eq(mt.picked, id, "picked: in the MATERIAL panel")
	mt.set_value("color", [0.1, 0.8, 0.3, 1.0])
	mt.assign(id, a, 0)
	var m := a.mesh.surface_get_material(0) as BaseMaterial3D
	check(m != null and m.albedo_color.is_equal_approx(Color(0.1, 0.8, 0.3)), "the box's surface shows it (%s)" % [m.albedo_color if m else null])
	mt.assign(id, b, 0)
	check(b.mesh.surface_get_material(0) == m, "the second box shares the one material")
	mt.pick(id)
	mt.set_value("metal", 0.9)
	mt.set_value("metal", 0.95)   # (a slider dragged: one step)
	check(absf(m.metallic - 0.95) < 1e-4 and absf(float(mt.lib.values(id)["metal"]) - 0.95) < 1e-4, "an edit: the surfaces and the library entry")
	check(m.metallic == (b.mesh.surface_get_material(0) as BaseMaterial3D).metallic, "both boxes changed")
	# the full kind's settings: textures, transparency, UV scale, cull
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	mt.set_texture_image("albedo", img)
	check(m.albedo_texture != null, "an albedo picture on the surfaces")
	check(str(mt.lib.entry(id)["textures"].get("albedo", "")).begins_with("res://art/materials/"), "kept as art/materials/<name>_albedo.png")
	mt.set_value("alpha", true)
	mt.set_value("uv", [2.0, 3.0])
	mt.set_value("cull", "none")
	check(m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and m.uv1_scale.is_equal_approx(Vector3(2, 3, 1)) and m.cull_mode == BaseMaterial3D.CULL_DISABLED, "transparency, UV scale, cull mode")
	for i in 4:
		ed.undo()   # cull, uv, alpha, texture
	check(m.albedo_texture == null and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.cull_mode == BaseMaterial3D.CULL_BACK, "undone: the texture and the rest")
	ed.undo()
	check(absf(m.metallic - 0.0) < 1e-4, "undo: the metal back as one step (%.2f)" % m.metallic)
	ed.undo()
	check(b.mesh.surface_get_material(0) != m, "undo: the second box's material back")
	ed.redo()
	check(b.mesh.surface_get_material(0) == m, "redo: given again")
	ed.undo()
	ed.undo()
	check(a.mesh.surface_get_material(0) == old_mat, "undo: the first box's own material back")
	await _done(ed)
	EditTarget.mod_id = ""
	Mods.remove(mid)


## A character's material shows only colour, metal, roughness and glow (what the game keeps of
## it); a full material shows its textures, transparency, UV scale and cull mode too. Edited in
## the pirate, it applies to every surface using it and is marked to go into model.json.
func test_character_material_shows_only_what_the_game_keeps() -> void:
	var ed := await _editor()
	var mt = ed.mat_tools
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var body: MeshInstance3D = ed.parts()[0]
	ed.select_part(body)
	var s := _surface_named(body, "PIR_Gold")
	check(s >= 0, "its gold surface")
	(ed._mat["surface"] as OptionButton).select(s)
	ed._show_material()
	check_eq(mt.lib.entry(mt.picked)["name"], "PIR_Gold", "the surface's material shows")
	check_eq(mt.shown_settings(), ["color", "metal", "rough", "emit"], "only colour, metal, roughness, glow")
	check((mt._ctl["metal"] as Control).tooltip_text.contains("model.json"), "the tooltip says why")
	mt.set_value("rough", 0.12)
	var m := body.mesh.surface_get_material(s) as BaseMaterial3D
	check(absf(m.roughness - 0.12) < 1e-4 and m.has_meta("mesh_editor_own"), "edited in place, marked for model.json")
	# the built-in looks can't be changed (duplicate one); a full material shows everything
	mt.pick("preset:Bronze")
	check(not mt.lib.is_editable("preset:Bronze") and (mt._ctl["metal"] as Range).editable == false, "a preset is read-only")
	check(mt.shown_settings().has("tex_albedo") and mt.shown_settings().has("cull") and mt.shown_settings().has("uv"), "a full material: textures, UV scale, cull (%s)" % [mt.shown_settings()])
	ed.undo()
	check(absf(m.roughness - 0.12) > 1e-3, "undo")
	await _done(ed)


## Edit mode: a material given to some faces of a box splits them into a surface of their own;
## undo puts the one surface back.
func test_assign_to_selected_faces() -> void:
	var ed := await _editor()
	var mt = ed.mat_tools
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.enter_edit(true)
	check_eq(ed.mode, "edit", "edit mode")
	var n0: int = p.mesh.get_surface_count()
	var one := PackedByteArray()
	one.resize(ed.em.tri_count())
	one[0] = 1
	ed.sel_t = ed.em.grow_to_polys(one)   # (one face of the box: its two triangles)
	ed._derive_sel()
	mt.assign_selected("preset:Gold")
	check_eq(p.mesh.get_surface_count(), n0 + 1, "the faces split into a surface of their own")
	var gold := 0
	for i in p.mesh.get_surface_count():
		var m := p.mesh.surface_get_material(i)
		if m and m.resource_name == "Gold":
			gold += p.mesh.surface_get_array_index_len(i) / 3 if p.mesh is ArrayMesh else 0
	check(gold >= 1 and gold < 12, "some triangles gold (%d of 12)" % gold)
	check_eq(ed.em.tri_count(), 12, "nothing lost")
	ed.undo()
	check_eq(p.mesh.get_surface_count(), n0, "undo: one surface again")
	ed.select_all(true)
	mt.assign_selected("preset:Steel")
	check_eq(p.mesh.get_surface_count(), n0, "all the faces: the surface's material changed, no split")
	check_eq(p.mesh.surface_get_material(0).resource_name, "Steel", "steel")
	ed.toggle_edit()
	await _done(ed)


## Dropping a material onto the view gives it to the surface under the drop point.
func test_drop_on_a_surface() -> void:
	var ed := await _editor()
	var mt = ed.mat_tools
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.frame_all()
	await tree.process_frame
	var data := {"mesh_material": "preset:Navy"}
	check(ed._can_drop_shape(Vector2.ZERO, data), "a material can be dropped on the view")
	var at: Vector2 = ed.view.size * 0.5
	var hit: Array = mt.surface_at(at)
	if hit.is_empty():
		check(true, "(no view size headless: the surface under the point not tested)")
	else:
		ed._drop_shape(at, data)
		check_eq(p.mesh.surface_get_material(int(hit[1])).resource_name, "Navy", "the surface under it has it")
	await _done(ed)


## Your materials saved into a mod (its data/materials.json.merge, the picture into its art/materials/),
## read back; renamed; a built-in look removed in the mod only; the game's own file untouched.
func test_library_saves_into_a_mod() -> void:
	var game_text := FileAccess.get_file_as_string(Lib.FILE)
	var mid: String = Mods.create("t_matlib")
	EditTarget.mod_id = mid
	var ed := await _editor()
	var mt = ed.mat_tools
	mt.pick("preset:Gold")
	var id: String = mt.duplicate_material()
	check(id != "" and mt.lib.entry(id)["name"] == "Gold copy", "a duplicate of a preset (%s)" % id)
	mt.set_value("rough", 0.77)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 1))
	mt.set_texture_image("normal", img)
	mt.rename_material(id, "Shiny gold")
	check_eq(mt.save_library(), OK, "saved")
	var merge := EditTarget.root() + "data/materials.json.merge"
	check(FileAccess.file_exists(merge), "into the mod's merge file")
	var tex_file := EditTarget.read_path(str(mt.lib.entry(id)["textures"]["normal"]))
	check(tex_file.begins_with("user://mods/") and FileAccess.file_exists(tex_file), "the picture into the mod (%s)" % tex_file)
	check_eq(FileAccess.get_file_as_string(Lib.FILE), game_text, "the game's file untouched")
	var lib2 := Lib.new()
	lib2.load_all()
	check(lib2.has(id) and lib2.entry(id)["name"] == "Shiny gold" and absf(float(lib2.values(id)["rough"]) - 0.77) < 1e-4, "read back: its name and settings")
	check(lib2.textures(id).has("normal"), "and its normal map")
	# a built-in look removed in the mod
	mt.pick("preset:Stone")
	mt.browser.select_id("")
	mt.delete_material(true)
	check(not mt.lib.has("preset:Stone"), "removed")
	var lib3 := Lib.new()
	lib3.load_all()
	check(not lib3.has("preset:Stone") and lib3.has(id), "removed in the mod (yours kept)")
	EditTarget.mod_id = ""
	var lib4 := Lib.new()
	lib4.load_all()
	check(lib4.has("preset:Stone") and not lib4.has(id), "the game's library as it was")
	await _done(ed)
	Mods.remove(mid)


## The Materials tab builds headless; every control there and in the MATERIAL panel has a tooltip.
func test_tab_builds_with_tooltips() -> void:
	var ed := await _editor()
	ed.add_primitive("box")
	ed.set_left_tab("materials")
	await tree.process_frame
	await tree.process_frame
	var br = ed.mat_tools.browser
	check(br.visible and not ed._models_box.visible and not ed.shape_tools.browser.visible, "the Materials tab shows")
	check(br.list.item_count > 50, "its balls (%d)" % br.list.item_count)
	br.set_group("preset")
	check_eq(br.list.item_count, MeshIO_presets(), "a group's")
	br.set_group("")
	br.search.text = "pir_gold"
	br.refill()
	check(br.list.item_count >= 1, "found by search")
	br.search.text = ""
	br.refill()
	var TT: GDScript = load("res://tests/test_tooltips.gd")
	var out := {}
	TT.scan(ed, out)
	ed.mat_tools.pick("preset:Gold")
	await tree.process_frame
	TT.scan(ed, out)
	TT.seen.clear()
	check(out.is_empty(), "every control has a tooltip (%s)" % [out])
	ed.set_left_tab("models")
	await _done(ed)


## The MATERIAL panel follows what's picked: edit mode - the selected faces' surface; object mode - the
## surface clicked on.
func test_panel_follows_the_selection() -> void:
	var ed: Control = load("res://scenes/editor/mesh_editor.tscn").instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var body: MeshInstance3D = ed.parts()[0]
	ed.select_part(body)
	ed.enter_edit(true)
	for i in 300:
		if ed.mode == "edit":
			break
		await tree.process_frame
	var em = ed.em
	var gold := -1
	for i in body.mesh.get_surface_count():
		var m: Material = body.mesh.surface_get_material(i)
		if m and m.resource_name == "PIR_Gold":
			gold = i
	check(gold >= 0, "the gold surface")
	(ed._mat["surface"] as OptionButton).select(0)
	ed.set_kind(2)
	ed.sel_t.fill(0)
	for t in em.tri_count():
		if em.tri_surf[t] == gold:
			ed.sel_t[t] = 1
			break
	ed._derive_sel()
	await tree.process_frame
	check_eq(ed._surface_index(), gold, "a gold face selected: the panel shows the gold")
	# object mode: the surface under the click
	ed.toggle_edit()
	for i in 100:
		if ed.mode == "object":
			break
		await tree.process_frame
	check_eq(ed._surface_of_face(body, 0), 0, "a part's first triangle: its first surface")
	ed.queue_free()
	await tree.process_frame


## Select island by material: from a face, every joined face of the same material - none of another.
func test_select_island_by_material() -> void:
	var ed: Control = load("res://scenes/editor/mesh_editor.tscn").instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var body: MeshInstance3D = ed.parts()[0]
	ed.select_part(body)
	ed.enter_edit(true)
	for i in 300:
		if ed.mode == "edit":
			break
		await tree.process_frame
	var em = ed.em
	var gold := -1
	for i in body.mesh.get_surface_count():
		var m: Material = body.mesh.surface_get_material(i)
		if m and m.resource_name == "PIR_Gold":
			gold = i
	var seed := -1
	for t in em.tri_count():
		if em.tri_surf[t] == gold:
			seed = t
			break
	ed.set_kind(2)
	ed.sel_t.fill(0)
	ed.sel_t[seed] = 1
	var n: int = ed.select_material_island()
	check(n > 1, "the island grew from one face (%d)" % n)
	var other := 0
	var picked := 0
	for t in em.tri_count():
		if ed.sel_t[t]:
			picked += 1
			if body.mesh.surface_get_material(em.tri_surf[t]) != body.mesh.surface_get_material(gold):
				other += 1
	check_eq(other, 0, "no face of another material picked")
	check(picked >= n, "they're the selection")
	ed.queue_free()
	await tree.process_frame
