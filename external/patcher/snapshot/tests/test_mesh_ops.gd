extends TestCase
## The mesh editor's edit-mode tools in mesh/mesh_ops.gd: Duplicate (Shift+D), Merge by distance
## (Alt+M) and Auto merge, Inset (I), Loop cut (Ctrl+R) and Select loop / ring (Alt+click) - each
## one undo step, on a box (six quads) and a 10 x 10 grid of quads.

const SCENE := "res://scenes/editor/mesh_editor.tscn"


func _box_editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	ed.add_primitive("box")
	ed.enter_edit(true)
	return ed


## A 2 m plane in a 10 x 10 grid of quads, in edit mode.
func _grid_editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	var mi: MeshInstance3D = ed.add_primitive("plane")
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	pm.subdivide_width = 9
	pm.subdivide_depth = 9
	var a := pm.get_mesh_arrays()
	a[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mi.mesh = m
	ed.select_part(mi)
	ed.enter_edit(true)
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


func _point_at(em, at: Vector3) -> int:
	for p in em.points.size():
		if em.points[p].distance_to(at) < 1e-4:
			return p
	return -1


## The faces whose every corner has coordinate `axis` = `v`.
func _faces_on(em, axis: int, v: float) -> Array:
	var out := {}
	for t in em.tri_count():
		var ok := true
		for k in 3:
			if absf(em.points[em.tris[t * 3 + k]][axis] - v) > 1e-4:
				ok = false
		if ok:
			out[em.tri_face[t]] = t
	return out.values()


func _count(flags: PackedByteArray) -> int:
	var n := 0
	for b in flags:
		n += b
	return n


func test_duplicate() -> void:
	var ed := await _box_editor()
	var n0: int = ed.em.points.size()
	check_eq(ed.em.poly_count(), 6, "a box: six faces")
	# points alone (no whole face): nothing copied
	ed.set_kind(0)
	ed.select_points(PackedInt32Array([0]))
	ed.mesh_ops.duplicate_selection()
	check_eq(ed.em.points.size(), n0, "one point selected: nothing to copy")
	check(ed.xf.is_empty(), "and no move")
	# the top face
	ed.set_kind(2)
	ed.select_all(false)
	ed._set_poly(_faces_on(ed.em, 1, 0.5)[0], 1)
	ed._derive_sel()
	ed.mesh_ops.duplicate_selection()
	check_eq(ed.em.points.size(), n0 + 4, "the top face copied: four new points")
	check_eq(ed.em.poly_count(), 7, "and one new face")
	check_eq(ed.xf.get("kind", ""), "G", "the copy is being moved")
	var sel: PackedInt32Array = ed.selected_points()
	check_eq(sel.size(), 4, "the copy is selected")
	for p in sel:
		check(p >= n0, "only the copy's points (%d)" % p)
	ed.xf = {}
	ed.move_selection(Vector3(0, 0.3, 0))
	check(_point_at(ed.em, Vector3(0.5, 0.8, 0.5)) >= 0, "moved up, off the box")
	check(_point_at(ed.em, Vector3(0.5, 0.5, 0.5)) >= 0, "the box's own corner where it was")
	check_eq(_faces_on(ed.em, 1, 0.8).size(), 1, "the copy's face up there")
	ed.undo()
	ed.undo()
	check_eq(ed.em.points.size(), n0, "undo (the move, the copy): as it was")
	check_eq(ed.em.poly_count(), 6, "six faces again")
	await _done(ed)


func test_merge_by_distance() -> void:
	var ed := await _box_editor()
	var n0: int = ed.em.points.size()
	ed.set_kind(2)
	ed.select_all(true)
	ed.mesh_ops.duplicate_selection()
	ed.confirm_transform()   # (the copy kept where it was made: on the box)
	check_eq(ed.em.points.size(), n0 * 2, "the whole box doubled")
	ed.select_all(false)
	ed.mesh_ops.merge_dist = 0.001
	var gone: int = ed.mesh_ops.merge_by_distance()
	check_eq(gone, n0, "nothing selected: all points - each corner's two made one")
	check_eq(ed.em.points.size(), n0, "back to eight points")
	check_eq(ed.em.poly_count(), 6, "the copied faces welded onto the box's: kept once (six faces)")
	check_eq(ed.em.tri_count(), 12, "twelve triangles, none doubled")
	check_eq(ed.mesh_ops.merge_by_distance(), 0, "again: nothing closer")
	ed.undo()
	check_eq(ed.em.points.size(), n0 * 2, "undo: one step")
	# only the selected points: two corners' pairs
	ed.set_kind(0)
	var ids := PackedInt32Array()
	for at in [Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]:
		for p in ed.em.points.size():
			if ed.em.points[p].distance_to(at) < 1e-4:
				ids.append(p)
	check_eq(ids.size(), 4, "two corners, each twice")
	ed.select_points(ids)
	check_eq(ed.mesh_ops.merge_by_distance(), 2, "selected: only theirs merged")
	check_eq(ed.em.points.size(), n0 * 2 - 2, "two fewer")
	# the threshold: points further apart stay
	ed.select_all(false)
	check_eq(ed.mesh_ops.merge_by_distance(0.0), 0, "a zero distance merges nothing")
	await _done(ed)


func test_auto_merge() -> void:
	var ed := await _box_editor()
	var n0: int = ed.em.points.size()
	ed.mesh_ops.set_auto_merge(true)
	ed.set_kind(0)
	var p := _point_at(ed.em, Vector3(0.5, 0.5, 0.5))
	ed.select_points(PackedInt32Array([p]))
	ed.move_selection(Vector3(0, 0, -0.99995))   # (within 0.0001 of the corner behind it)
	check_eq(ed.em.points.size(), n0 - 1, "moved onto another corner: welded to it")
	check(_point_at(ed.em, Vector3(0.5, 0.5, -0.5)) >= 0, "the corner it landed on stayed where it was")
	var left := 0
	for q in ed.em.points.size():
		if ed.em.points[q].distance_to(Vector3(0.5, 0.5, -0.49995)) < 1e-6:
			left += 1
	check_eq(left, 0, "the moved one is gone")
	check_eq(ed.selected_points().size(), 1, "the merged point selected")
	ed.undo()
	check_eq(ed.em.points.size(), n0, "one undo: the move and the weld")
	check(_point_at(ed.em, Vector3(0.5, 0.5, 0.5)) >= 0, "the corner back")
	ed.mesh_ops.set_auto_merge(false)
	ed.select_points(PackedInt32Array([_point_at(ed.em, Vector3(0.5, 0.5, 0.5))]))
	ed.move_selection(Vector3(0, 0, -0.99995))
	check_eq(ed.em.points.size(), n0, "off: nothing welded")
	await _done(ed)


func test_inset() -> void:
	var ed := await _box_editor()
	var n0: int = ed.em.points.size()
	ed.set_kind(2)
	ed._set_poly(_faces_on(ed.em, 1, 0.5)[0], 1)
	ed._derive_sel()
	ed.mesh_ops.begin_inset()
	check_eq(ed.xf.get("kind", ""), "INS", "I: the inset runs")
	for kc in [KEY_0, KEY_PERIOD, KEY_1]:
		var k := InputEventKey.new()
		k.keycode = kc
		k.pressed = true
		check(ed.mesh_ops.key(k), "a digit typed is taken")
	check(absf(ed.mesh_ops.inset_amount() - 0.1) < 1e-6, "typed 0.1")
	ed.confirm_transform()
	var em = ed.em
	check_eq(em.points.size(), n0 + 4, "four new points")
	check_eq(em.poly_count(), 10, "the top: a face inside and four round it (6 + 4)")
	for at in [Vector3(0.4, 0.5, 0.4), Vector3(-0.4, 0.5, 0.4), Vector3(0.4, 0.5, -0.4), Vector3(-0.4, 0.5, -0.4)]:
		check(_point_at(em, at) >= 0, "an inner corner 0.1 in: %s" % at)
	check_eq(_faces_on(em, 1, 0.5).size(), 5, "five faces on top")
	for t in _faces_on(em, 1, 0.5):
		check_eq(em.poly_loop(t).size(), 4, "each a quad")
	check_eq(_count(ed.sel_t), 2, "the inner face selected")
	ed.undo()
	check_eq(ed.em.points.size(), n0, "one undo: as it was")
	check_eq(ed.em.poly_count(), 6, "six faces")
	# cancelled: nothing changes, the selection as it was
	ed.set_kind(2)
	ed.select_all(false)
	ed._set_poly(_faces_on(ed.em, 1, 0.5)[0], 1)
	ed._derive_sel()
	ed.mesh_ops.begin_inset()
	ed._cancel_xf()
	check_eq(ed.em.points.size(), n0, "cancelled: no new points")
	check_eq(ed.sel_t.size(), ed.em.tri_count(), "the selection fits the mesh")
	check_eq(_count(ed.sel_t), 2, "the face still selected")
	# a whole box has no border: nothing
	ed.select_all(true)
	ed.mesh_ops.begin_inset()
	check(ed.xf.is_empty(), "a closed region: no inset")
	check_eq(ed.em.points.size(), n0, "nothing changed")
	await _done(ed)


func test_loop_cut() -> void:
	var ed := await _box_editor()
	var n0: int = ed.em.points.size()
	var a := _point_at(ed.em, Vector3(-0.5, 0.5, 0.5))
	var b := _point_at(ed.em, Vector3(0.5, 0.5, 0.5))
	var r: Dictionary = ed.mesh_ops.ring(ed.em, a, b)
	check(r["closed"], "the ring across a box's edge goes round")
	check_eq((r["sides"] as Array).size(), 4, "crossing four edges")
	check_eq((r["quads"] as PackedInt32Array).size(), 4, "through four quads")
	check(ed.mesh_ops.cut_loop(a, b), "cut")
	check_eq(ed.xf.get("kind", ""), "SLIDE", "then it slides")
	ed.xf["fixed"] = 0.25
	ed._xf_update()
	ed.confirm_transform()
	var em = ed.em
	check_eq(em.points.size(), n0 + 4, "four new points")
	check_eq(em.poly_count(), 10, "four faces split in two (6 + 4)")
	check(_point_at(em, Vector3(-0.25, 0.5, 0.5)) >= 0, "a quarter of the way along the edge")
	check(_point_at(em, Vector3(-0.25, -0.5, -0.5)) >= 0, "and round the other side the same way")
	check_eq(_count(ed.sel_e), 4, "the new loop's edges selected")
	ed.undo()
	check_eq(ed.em.points.size(), n0, "one undo: as it was")
	check_eq(ed.em.poly_count(), 6, "six faces")
	# right-click / Esc while sliding: kept, in the middle
	check(ed.mesh_ops.cut_loop(a, b), "cut again")
	ed._cancel_xf()
	check_eq(ed.em.points.size(), n0 + 4, "cancelled slide: the loop kept")
	check(_point_at(ed.em, Vector3(0.0, 0.5, 0.5)) >= 0, "in the middle")
	ed.undo()
	check_eq(ed.em.points.size(), n0, "and one undo step")
	# Ctrl+R: the ring shown while pointing, a click cuts
	ed.mesh_ops.begin_loopcut()
	check(ed.mesh_ops.cutting, "Ctrl+R: waiting for a click")
	ed.mesh_ops.cancel_loopcut()
	check(not ed.mesh_ops.cutting and not ed.view.knife_on, "stopped: nothing shown")
	await _done(ed)


func test_loop_cut_on_a_grid_stops_at_the_border() -> void:
	var ed := await _grid_editor()
	var em = ed.em
	var n0: int = em.points.size()
	var f0: int = em.poly_count()
	check_eq(f0, 100, "a 10 x 10 grid of quads")
	var a := _point_at(em, Vector3(0, 0, 0))
	var b := _point_at(em, Vector3(0, 0, 0.2))
	var r: Dictionary = ed.mesh_ops.ring(em, a, b)
	check(not r["closed"], "open: it stops at the grid's borders")
	check_eq((r["quads"] as PackedInt32Array).size(), 10, "across ten quads")
	check(ed.mesh_ops.cut_loop(a, b, false), "cut (no slide)")
	check_eq(ed.em.points.size(), n0 + 11, "eleven new points")
	check_eq(ed.em.poly_count(), f0 + 10, "ten more faces")
	ed.undo()
	check_eq(ed.em.points.size(), n0, "undone")
	# with the mouse: Ctrl+R, point at the edge (the ring shown), click, slide, click
	ed.view.frame(AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))
	ed.view.set_view("top")
	ed._em_tm = null
	ed.mesh_ops.begin_loopcut()
	var at: Vector2 = ed.view.project(ed.part.global_transform * Vector3(0.0, 0, 0.1))
	var mv := InputEventMouseMotion.new()
	mv.position = at
	ed._view_input(mv)
	check(ed.view.knife_on and ed.view.knife_pts.size() == 11, "pointing at the edge: the new loop shown (%d points)" % ed.view.knife_pts.size())
	var click := func(pressed: bool) -> void:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = at
		ed._view_input(mb)
	click.call(true)
	click.call(false)
	check_eq(ed.xf.get("kind", ""), "SLIDE", "a click cuts, then it slides")
	check(not ed.view.knife_on, "the preview gone")
	click.call(true)
	click.call(false)
	check(ed.xf.is_empty(), "a second click keeps it")
	check_eq(ed.em.points.size(), n0 + 11, "the loop is there")
	check_eq(ed.em.poly_count(), f0 + 10, "its faces too")
	await _done(ed)


func test_select_loop_and_ring() -> void:
	var ed := await _grid_editor()
	var em = ed.em
	var a := _point_at(em, Vector3(0, 0, 0))
	var b := _point_at(em, Vector3(0.2, 0, 0))
	var e: int = em.edge(a, b)
	check(e >= 0, "an edge in the middle")
	var loop: PackedInt32Array = ed.mesh_ops.edge_loop(em, e)
	check_eq(loop.size(), 10, "its loop: straight across the grid, ten edges")
	for x in loop:
		check(absf(em.points[em.edges[x * 2]].z) < 1e-4 and absf(em.points[em.edges[x * 2 + 1]].z) < 1e-4, "all on the line z = 0")
	var ring: PackedInt32Array = ed.mesh_ops.edge_ring(em, e)
	check_eq(ring.size(), 11, "its ring: the eleven edges across the quads beside it")
	# the buttons: from the selected edge
	ed.set_kind(1)
	ed.select_all(false)
	var se: PackedByteArray = ed.sel_e
	se[e] = 1
	ed.sel_e = se
	ed._derive_sel()
	check_eq(ed.mesh_ops.select_loops(), 10, "Select loop: the loop selected")
	check_eq(_count(ed.sel_e), 10, "ten edges")
	ed.select_all(false)
	se = ed.sel_e
	se[e] = 1
	ed.sel_e = se
	ed._derive_sel()
	check_eq(ed.mesh_ops.select_rings(), 11, "Select ring")
	# Alt+click: at the edge on screen
	ed.view.frame(AABB(Vector3(-1, -0.1, -1), Vector3(2, 0.2, 2)))
	ed.view.set_view("top")
	ed._em_tm = null
	var at: Vector2 = ed.view.project(ed.part.global_transform * Vector3(0.1, 0, 0.0))
	ed.select_all(false)
	var alt := func(pressed: bool) -> void:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.alt_pressed = true
		mb.pressed = pressed
		mb.position = at
		ed._view_input(mb)
	alt.call(true)
	alt.call(false)
	check_eq(_count(ed.sel_e), 10, "Alt+click on the edge: its loop")
	check_eq(ed._drag, "", "and the view isn't left turning")
	ed.set_kind(2)
	ed.select_all(false)
	ed.mesh_ops.select_loop_at(at)
	var faces := {}
	for t in ed.em.tri_count():
		if ed.sel_t[t]:
			faces[ed.em.tri_face[t]] = true
	check_eq(faces.size(), 10, "face mode: the ring of quads across it")
	await _done(ed)


func test_menu_and_panel_have_them() -> void:
	var ed := await _box_editor()
	for title in ["Duplicate selection", "Inset", "Loop cut", "Select loop", "Select ring", "Merge by distance"]:
		var b: Button = ed.find_child("Op_" + title.validate_node_name(), true, false)
		check(b != null and b.tooltip_text.begins_with(title), "the EDIT MESH row has %s, with its tooltip" % title)
		check(EditorIcons.get_icon(ed.mesh_ops.items().filter(func(i): return i[1] == title)[0][0]) != null, "%s has an icon" % title)
	check(ed.find_child("MergeDistance", true, false) != null, "the merge distance is in the panel")
	var m: PopupPanel = ed.menu(Vector2(100, 100))
	check(m.find_child("Menu_Inset", true, false) != null, "the right-click menu has Inset")
	check(m.find_child("Menu_Loop cut".validate_node_name(), true, false) != null, "and Loop cut")
	m.hide()
	await _done(ed)
