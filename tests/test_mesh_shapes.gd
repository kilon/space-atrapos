extends TestCase
## The mesh editor's shape library (120 parametric shapes, editable, new ones saved into
## a mod), its browser, and the boolean operations between parts (union, difference,
## intersection, slice - undoable).

const SCENE := "res://scenes/editor/mesh_editor.tscn"


func _editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


func _vol(m: Mesh) -> float:
	return load("res://scripts/editor/mesh/shapes.gd").volume(m)


## Every shape of the library is made: not empty, with normals, UVs and tangents - and the
## solid ones closed, their skin facing out.
func test_all_shapes_generate() -> void:
	var Shapes: GDScript = load("res://scripts/editor/mesh/shapes.gd")
	var lib = load("res://scripts/editor/mesh/shape_library.gd").new()
	lib.load_all()
	var built := 0
	var cats := {}
	var slowest := ""
	var slow_ms := 0.0
	var t_all := Time.get_ticks_usec()
	for id in lib.shapes:
		var e: Dictionary = lib.shapes[id]
		if not e.get("builtin", false):
			continue
		built += 1
		cats[e["cat"]] = int(cats.get(e["cat"], 0)) + 1
		var t0 := Time.get_ticks_usec()
		var m: Mesh = lib.mesh_of(e)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > slow_ms:
			slow_ms = ms
			slowest = id
		if m == null or m.get_surface_count() == 0:
			check(false, "%s is made" % id)
			continue
		var a := m.surface_get_arrays(0)
		var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var ok: bool = nv > 0 and a[Mesh.ARRAY_NORMAL] != null and (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == nv \
			and a[Mesh.ARRAY_TEX_UV] != null and (a[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == nv and a[Mesh.ARRAY_TANGENT] != null
		check(ok, "%s: vertices, normals, UVs, tangents (%d vertices)" % [id, nv])
		if Shapes.GENS[e["gen"]]["solid"]:
			var open: int = Shapes.open_edges(m)
			check(open == 0, "%s is closed (%d open edges)" % [id, open])
			check(Shapes.volume(m) > 0.0, "%s faces out (volume %.4f)" % [id, Shapes.volume(m)])
	check_eq(built, 120, "120 shapes built in")
	check(cats.size() >= 6, "in %d categories (%s)" % [cats.size(), cats])
	print("  120 shapes made in %.0f ms (one thread); the slowest %s: %.1f ms" % [(Time.get_ticks_usec() - t_all) / 1000.0, slowest, slow_ms])


## Two boxes a metre across, half overlapping: the union holds 1.5 m3, the difference and the
## intersection 0.5; undo puts both back; slice makes two parts; an open mesh is refused.
func test_booleans() -> void:
	var ed := await _editor()
	var results := {"union": 1.5, "difference": 0.5, "intersection": 0.5}
	for op in results:
		var a: MeshInstance3D = ed.add_primitive("box")
		var b: MeshInstance3D = ed.add_primitive("box")
		b.position = Vector3(0.5, 0, 0)
		ed.select_part(a)
		ed.select_part(b, true)
		check_eq(ed.selected_parts(), [a, b], "%s: two parts selected (Ctrl+click)" % op)
		check_eq(ed.shape_tools.bool_pair(), [a, b], "A first, B the other")
		var n0: int = ed.parts().size()
		check(ed.boolean(op, null, null, true), op + " done")
		check(absf(_vol(a.mesh) - results[op]) < 1e-3, "%s: %.3f m3 (%.3f)" % [op, _vol(a.mesh), results[op]])
		check_eq(ed.parts().size(), n0 - 1, op + ": B is gone")
		check_eq(load("res://scripts/editor/mesh/shapes.gd").open_edges(a.mesh), 0, op + ": the result is closed")
		var box: AABB = a.mesh.get_aabb()
		if op == "union":
			check(absf(box.size.x - 1.5) < 1e-3, "the union spans 1.5 m")
		ed.undo()
		check(absf(_vol(a.mesh) - 1.0) < 1e-3 and ed.parts().size() == n0, op + " undone: both boxes back")
		ed.redo()
		check(absf(_vol(a.mesh) - results[op]) < 1e-3, op + " redone")
		ed.delete_part()
	# slice: two parts, B kept (hidden)
	var a: MeshInstance3D = ed.add_primitive("box")
	var b: MeshInstance3D = ed.add_primitive("sphere")
	b.position = Vector3(0.5, 0, 0)
	ed.shape_tools.keep_b = true
	var n1: int = ed.parts().size()
	check(ed.boolean("slice", a, b, true), "slice done")
	check_eq(ed.parts().size(), n1 + 1, "slice: a new part (the inside piece)")
	check(not b.visible and b.is_inside_tree(), "B kept, hidden")
	var inside: MeshInstance3D = ed.parts()[ed.parts().find(a) + 1]
	check(absf(_vol(a.mesh) + _vol(inside.mesh) - 1.0) < 2e-3, "the two pieces make the box (%.3f + %.3f)" % [_vol(a.mesh), _vol(inside.mesh)])
	ed.undo()
	check(b.visible and ed.parts().size() == n1, "slice undone")
	ed.shape_tools.keep_b = false
	# an open mesh (a plane) can't take part
	var pl: MeshInstance3D = ed.add_primitive("plane")
	var before: Mesh = a.mesh
	ed.boolean("union", a, pl, true)
	check(a.mesh == before, "a plane: refused")
	check(ed._note.text.contains("isn't closed"), "and why (%s)" % ed._note.text.get_slice("    ·", 0))
	# the menu: the part selected and the part right-clicked (no clicks here: set as menu() would)
	ed.select_part(a)
	ed._menu_prev = a
	ed.part = b
	check_eq(ed.shape_tools.bool_pair(), [a, b], "the selected part and the one under the mouse")
	ed.select_part(a)
	ed._menu_prev = a
	ed.part = b   # (right-clicked on b with a selected)
	var m: PopupPanel = ed.menu(Vector2(5, 5))
	check(m.find_child("Menu_Union", true, false) != null and m.find_child("Menu_Slice", true, false) != null, "the menu's Boolean group")
	m.hide()
	# on a worker: two ~2,000-triangle parts
	for p in ed.parts():
		ed.select_part(p)
		ed.delete_part()
	var s1: MeshInstance3D = ed.add_primitive("box")
	s1.mesh = load("res://scripts/editor/mesh/shapes.gd").make("superellipsoid", {"res": 13})
	var s2: MeshInstance3D = ed.add_primitive("sphere")
	s2.mesh = load("res://scripts/editor/mesh/shapes.gd").make("sphere", {"segs": 46, "rings": 23})
	s2.position = Vector3(0.4, 0.1, 0)
	ed.select_part(s1)
	ed.select_part(s2, true)
	var t0 := Time.get_ticks_usec()
	check(ed.boolean("difference"), "started on a worker")
	check(ed.shape_tools.busy, "working")
	var frames := 0
	for i in 600:
		if not ed.shape_tools.busy:
			break
		frames += 1
		await tree.process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(not ed.shape_tools.busy and ed.parts().size() == 1, "done (%d frames)" % frames)
	print("  boolean difference of 2,028 + 2,024 triangles: %.0f ms on a worker (%d frames)" % [ms, frames])
	await _done(ed)


## A shape added as a part keeps its recipe: a parameter changed makes it again (undoable);
## edited by hand, it's a plain mesh. The recipe survives a save (the glb's extras).
func test_shape_parameters() -> void:
	var id: String = Mods.create("t")
	EditTarget.mod_id = id
	var ed := await _editor()
	var g: MeshInstance3D = ed.add_shape_now("gear")
	check(g != null and g.has_meta("mesh_shape"), "a gear added, with its recipe")
	check_eq(ed.part, g, "and selected")
	check_eq(ed.shape_tools.panel.mode, "part", "the SHAPE panel shows its parameters")
	check(ed.shape_tools.panel.find_child("Param_teeth", true, false) != null, "a field for each (teeth)")
	var t12: int = g.mesh.surface_get_array_index_len(0)
	ed.shape_tools.panel.set_param("teeth", 20)
	var t20: int = g.mesh.surface_get_array_index_len(0)
	check(t20 > t12, "20 teeth: made again (%d > %d indices)" % [t20, t12])
	check_eq(int(g.get_meta("mesh_shape")["params"]["teeth"]), 20, "the recipe changed")
	ed.undo()
	check_eq(g.mesh.surface_get_array_index_len(0), t12, "undone: 12 teeth again")
	ed.redo()
	check_eq(g.mesh.surface_get_array_index_len(0), t20, "redone")
	# saved and opened again: the recipe back
	var res_path := "res://models/test_mesh_shapes.glb"
	check_eq(ed.write_to(res_path), OK, "saved into the mod")
	check(ed.open_now(res_path), "read back")
	var g2: MeshInstance3D = ed.parts()[0]
	check(g2.has_meta("mesh_shape") and int(g2.get_meta("mesh_shape")["params"]["teeth"]) == 20, "its recipe kept (the glb's extras)")
	# edited by hand: a plain mesh
	ed.select_part(g2)
	ed.enter_edit(true)
	ed.select_points(PackedInt32Array([0]))
	ed.move_selection(Vector3(0, 0.1, 0))
	ed.toggle_edit()
	check(not g2.has_meta("mesh_shape"), "its vertices edited: no recipe any more")
	ed.undo()
	check(g2.has_meta("mesh_shape"), "undone: the recipe back")
	await _done(ed)
	EditTarget.mod_id = ""
	Mods.remove(id)


## New shapes - a recipe, and a part's own mesh - saved into a mod and loaded back; one removed.
func test_new_shapes_into_a_mod() -> void:
	var id: String = Mods.create("t")
	EditTarget.mod_id = id
	var ed := await _editor()
	var tools = ed.shape_tools
	var g: MeshInstance3D = ed.add_shape_now("gear")
	tools.set_part_param(g, "teeth", 30.0)
	var sid: String = tools.save_new("Test gear", "Mine")
	check(sid != "", "a recipe kept (%s)" % sid)
	var p: MeshInstance3D = ed.add_primitive("cone")
	ed.select_part(p)
	var mid: String = tools.save_new("Test cone mesh", "Mine")
	check(mid != "" and tools.lib.entry(mid)["gen"] == "mesh", "a part's own mesh kept as a shape")
	var merge := EditTarget.root() + "data/shapes.json.merge"
	check(FileAccess.file_exists(merge), "into the mod (%s)" % merge)
	check(FileAccess.file_exists(EditTarget.write_path("res://art/shapes/%s.res" % mid)), "its mesh beside it")
	var text := FileAccess.get_file_as_string("res://data/shapes.json")
	check(not text.contains("Test gear"), "not into the game's file")
	var lib2 = load("res://scripts/editor/mesh/shape_library.gd").new()
	lib2.load_all()
	check(lib2.shapes.has(sid) and int(lib2.entry(sid)["params"]["teeth"]) == 30, "loads back with its parameters")
	check(lib2.shapes.has(mid) and lib2.mesh_of(lib2.entry(mid)) != null, "the mesh shape loads back")
	check_eq(lib2.ids("Mine").size(), 2, "both in Mine")
	check_eq(lib2.ids().size(), 122, "beside the 120")
	# the browser shows them; one removed
	tools.browser.set_cat("Mine")
	check_eq(tools.browser.list.item_count, 2, "the browser's Mine tab")
	tools.pick(mid)
	tools.delete_picked()
	var lib3 = load("res://scripts/editor/mesh/shape_library.gd").new()
	lib3.load_all()
	check(not lib3.shapes.has(mid) and lib3.shapes.has(sid), "removed (the other kept)")
	# a built-in removed in the mod only (asked first: confirmed here)
	tools.pick("cube")
	tools.delete_picked(true)
	var lib4 = load("res://scripts/editor/mesh/shape_library.gd").new()
	lib4.load_all()
	check(not lib4.shapes.has("cube"), "a built-in shape removed in the mod")
	EditTarget.mod_id = ""
	var lib5 = load("res://scripts/editor/mesh/shape_library.gd").new()
	lib5.load_all()
	check(lib5.shapes.has("cube") and not lib5.shapes.has(sid), "the game's library untouched")
	await _done(ed)
	Mods.remove(id)
	check(not DirAccess.dir_exists_absolute("user://mods/" + id), "the test mod removed")


## The browser: a grid of the shapes with categories as tabs and a search; a double-click (or a
## drop into the view) adds the shape, made on a worker.
func test_browser() -> void:
	var ed := await _editor()
	ed.set_left_tab("shapes")
	var br = ed.shape_tools.browser
	check((ed.get_meta("prims") as Control).visible and not ed._models_box.visible, "the Primitives tab")
	var pl: ItemList = (ed.get_meta("prims") as Node).find_child("Primitives", true, false)
	check(pl != null and pl.item_count == 6, "the ECurve primitives (%d)" % (pl.item_count if pl else -1))
	br.set_cat("")
	check_eq(br.list.item_count, 120, "all 120 shapes")
	check(br.list.get_item_tooltip(0) != "", "each with a tooltip")
	br.set_cat("Mechanical")
	check(br.list.item_count >= 15 and br.list.item_count < 120, "a category (%d)" % br.list.item_count)
	br.set_cat("")
	br.search.text = "column"
	br.refill()
	check(br.list.item_count >= 4, "found by name (%d columns)" % br.list.item_count)
	br.search.text = ""
	br.refill()
	# picked: its parameters, a preview
	br.list.select(0)
	br.list.item_selected.emit(0)
	check_eq(ed.shape_tools.panel.mode, "library", "picked: the SHAPE panel shows it")
	# double-click: added (on a worker)
	var n0: int = ed.parts().size()
	br.list.item_activated.emit(0)
	for i in 120:
		if ed.parts().size() > n0:
			break
		await tree.process_frame
	check_eq(ed.parts().size(), n0 + 1, "double-click adds it")
	# dropped into the view: on the ground under the mouse
	check(ed._can_drop_shape(Vector2.ZERO, {"mesh_shape": "cone"}), "the view takes a dragged shape")
	var at: Vector3 = ed.shape_tools.drop_point(ed.view.size * 0.5)
	check(at != Vector3.INF, "dropped somewhere (%s)" % at)
	ed._drop_shape(ed.view.size * 0.5, {"mesh_shape": "cone"})
	for i in 120:
		if ed.parts().size() > n0 + 1:
			break
		await tree.process_frame
	check_eq(ed.parts().size(), n0 + 2, "the drop adds it")
	ed.set_left_tab("models")
	check(ed._models_box.visible and not br.visible, "back to the models")
	await _done(ed)
