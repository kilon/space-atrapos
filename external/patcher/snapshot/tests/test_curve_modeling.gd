extends TestCase
## The mesh editor's Curve modeling (scripts/editor/mesh/curve_tools.gd): the curves' shapes, the
## solids made of them (closed, facing out, the right volume), sketching by clicks on the
## construction plane, the tab and the right-click menu's tab, undo, keeping them with the model.

const SCENE := "res://scenes/editor/mesh_editor.tscn"
const CT := preload("res://scripts/editor/mesh/curve_tools.gd")
const Shapes := preload("res://scripts/editor/mesh/shapes.gd")


func _editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	await tree.process_frame
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


static func _rect(w: float, d: float, ccw := true) -> Dictionary:
	var k := PackedVector3Array([Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)])
	if not ccw:
		k.reverse()
	return {"kind": "line", "ctrl": k, "closed": true, "n": Vector3.UP}


static func _circle(c: Vector3, r: float, n := Vector3.UP) -> Dictionary:
	var start := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.BACK
	return {"kind": "circle", "ctrl": PackedVector3Array([c, c + start * r]), "closed": true, "n": n}


func test_curve_shapes() -> void:
	var circ := CT.sample(_circle(Vector3(1, 0, 0), 0.5))
	check(circ.size() == 64, "a circle: 64 vertices (%d)" % circ.size())
	var off := 0.0
	for q in circ:
		off = maxf(off, absf(q.distance_to(Vector3(1, 0, 0)) - 0.5))
		check(absf(q.y) < 1e-6, "in its plane")
	check(off < 1e-5, "all on its radius")
	# a spline goes through its points
	var k := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0.5), Vector3(2, 0, 0), Vector3(3, 0, 1)])
	var sp := CT.sample({"kind": "spline", "ctrl": k, "closed": false, "n": Vector3.UP})
	for q in k:
		var near := INF
		for s in sp:
			near = minf(near, s.distance_to(q))
		check(near < 1e-4, "the spline passes through %s" % q)
	# a three-point arc: through its middle point, ends where it should
	var a := CT.arc3(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
	check(a[0].distance_to(Vector3(-1, 0, 0)) < 1e-5 and a[a.size() - 1].distance_to(Vector3(1, 0, 0)) < 1e-5, "the arc from its start to its end")
	var through := INF
	for q in a:
		through = minf(through, q.distance_to(Vector3(0, 0, 1)))
		check(absf(q.length() - 1.0) < 1e-4, "on the circle")
	check(through < 0.05, "through the third vertex (%.3f)" % through)
	check(CT.circumcentre(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0) == Vector3.INF, "three in a row: no circle")
	# a rectangle's corners rounded: the arcs stay inside the corners
	var r := _rect(1.0, 1.0)
	r["radii"] = PackedFloat32Array([0.2, 0.2, 0.2, 0.2])
	var rs := CT.sample(r)
	check(rs.size() > 12, "rounded corners add vertices (%d)" % rs.size())
	for q in rs:
		check(q.x > -1e-5 and q.x < 1.0 + 1e-5 and q.z > -1e-5 and q.z < 1.0 + 1e-5, "inside the square")
	check(not Vector3(0, 0, 0) in rs, "the sharp corner's gone")


func test_offset_join_bridge() -> void:
	for ccw in [true, false]:
		var o := CT.offset(_rect(1.0, 1.0, ccw), 0.1)
		var k: PackedVector3Array = o["ctrl"]
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for q in k:
			lo = lo.min(q)
			hi = hi.max(q)
		check((hi - lo).distance_to(Vector3(1.2, 0, 1.2)) < 1e-4, "offset out by 0.1 each side, either winding (%s)" % (hi - lo))
	var c := CT.offset(_circle(Vector3.ZERO, 0.5), -0.1)
	check(absf((c["ctrl"][1] as Vector3).length() - 0.4) < 1e-5, "a circle offset in: radius 0.4")
	var l1 := {"kind": "line", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)]), "closed": false, "n": Vector3.UP}
	var l2 := {"kind": "line", "ctrl": PackedVector3Array([Vector3(2, 0, 1), Vector3(1, 0, 0)]), "closed": false, "n": Vector3.UP}
	var j := CT.join(l1, l2)
	check((j["ctrl"] as PackedVector3Array).size() == 3, "joined at the shared end: 3 vertices (%d)" % (j["ctrl"] as PackedVector3Array).size())
	check(str(j["kind"]) == "line", "two lines: a line")
	var br := CT.bridge(CT.sample(l1), PackedVector3Array([Vector3(2, 0, 0.5), Vector3(3, 0, 0.5)]))
	var bk: PackedVector3Array = br["ctrl"]
	check(bk[0].distance_to(Vector3(1, 0, 0)) < 1e-5 and bk[3].distance_to(Vector3(2, 0, 0.5)) < 1e-5, "the bridge joins the nearest ends")
	check((bk[1] - bk[0]).normalized().dot(Vector3.RIGHT) > 0.99, "leaving the first along its direction")


func _closed_solid(m: ArrayMesh, what: String, want_vol: float, tol: float) -> void:
	check(m != null, what + ": made")
	if m == null:
		return
	check(Shapes.open_edges(m) == 0, what + ": closed (%d open edges)" % Shapes.open_edges(m))
	var v := Shapes.volume(m)
	check(v > 0.0, what + ": facing out (volume %.4f)" % v)
	check(absf(v - want_vol) <= want_vol * tol, what + ": volume %.4f, about %.4f" % [v, want_vol])


func test_solids_from_curves() -> void:
	_closed_solid(CT.extrude_mesh([_rect(1.0, 0.5)], 0.2), "extruded rectangle", 0.1, 0.01)
	_closed_solid(CT.extrude_mesh([_rect(1.0, 0.5, false)], 0.2), "extruded rectangle (wound the other way)", 0.1, 0.01)
	_closed_solid(CT.extrude_mesh([_rect(1.0, 0.5)], -0.2), "extruded downward", 0.1, 0.01)
	var rr := _rect(1.0, 1.0)
	rr["radii"] = PackedFloat32Array([0.25, 0.25, 0.25, 0.25])
	_closed_solid(CT.extrude_mesh([rr], 0.1), "extruded rounded square", (1.0 - (4.0 - PI) * 0.0625) * 0.1, 0.02)
	_closed_solid(CT.extrude_mesh([_circle(Vector3.ZERO, 0.5)], 1.0), "extruded circle", PI * 0.25, 0.01)
	var open_m := CT.extrude_mesh([{"kind": "line", "ctrl": PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3(1, 0, 1)]), "closed": false, "n": Vector3.UP}], 0.5)
	check(open_m != null and Shapes.open_edges(open_m) > 0, "an open edge extrudes into a wall (open)")
	# revolve: a square profile (0.2 side, 1 from the axis) round Y - a torus of square section: 2 pi R A
	var prof := {"kind": "line", "ctrl": PackedVector3Array([Vector3(0.9, 0, 0), Vector3(1.1, 0, 0), Vector3(1.1, 0.2, 0), Vector3(0.9, 0.2, 0)]), "closed": true, "n": Vector3.BACK}
	_closed_solid(CT.revolve_mesh([prof], TAU, 48, [Vector3.ZERO, Vector3.UP, -1]), "revolved square", TAU * 1.0 * 0.04, 0.02)
	# loft: two circles, one above the other - a cylinder
	_closed_solid(CT.loft_mesh([_circle(Vector3.ZERO, 0.5), _circle(Vector3(0, 1, 0), 0.5)]), "lofted circles", PI * 0.25, 0.02)
	# the second circle wound the other way: still a clean cylinder
	var c2 := _circle(Vector3(0, 1, 0), 0.5)
	c2["n"] = Vector3.DOWN
	_closed_solid(CT.loft_mesh([_circle(Vector3.ZERO, 0.5), c2]), "lofted circles (one reversed)", PI * 0.25, 0.02)
	# pipe along a straight line: pi r^2 L (16 sides: a little less)
	var path := {"kind": "line", "ctrl": PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 2)]), "closed": false, "n": Vector3.UP}
	_closed_solid(CT.pipe_mesh([path], 0.1, 16), "pipe", PI * 0.01 * 2.0 * 0.974, 0.02)
	# pipe round a closed loop: a ring, no ends
	_closed_solid(CT.pipe_mesh([_circle(Vector3.ZERO, 1.0)], 0.1, 16), "pipe round a loop", TAU * 1.0 * PI * 0.01 * 0.974, 0.03)
	# sweep: a 0.2 square along a 2 m line
	var sq := {"kind": "line", "ctrl": PackedVector3Array([Vector3(-0.1, -0.1, 0), Vector3(0.1, -0.1, 0), Vector3(0.1, 0.1, 0), Vector3(-0.1, 0.1, 0)]), "closed": true, "n": Vector3.BACK}
	_closed_solid(CT.sweep_mesh(sq, path), "swept square", 0.04 * 2.0, 0.01)
	var f := CT.fill_mesh([_rect(1.0, 1.0)])
	check(f != null and f.surface_get_array_index_len(0) == 6, "fill: a square's two triangles")


func test_tabs_and_menu() -> void:
	var ed := await _editor()
	var tabs: TabContainer = ed._right_tabs
	check(tabs != null and tabs.get_tab_count() == 1 and not tabs.tabs_visible, "the side panel: one page, the mesh's and ECurves's together")
	var secs: Dictionary = ed.get_meta("side_secs", {})
	for t in ["OVERVIEW", "SOLID", "SKETCH", "EDGES", "MATERIAL"]:
		check(secs.has(t), "its section " + t)
	# only what's about the selection: nothing picked - the overview, sketching; a part - its sections
	ed.new_model(true)
	ed.select_part(null)
	ed.update_side_panel()
	check((secs["SKETCH"] as Control).visible and not (secs["SOLID"] as Control).visible and not (secs["MATERIAL"] as Control).visible and not (secs["EDGES"] as Control).visible, "nothing picked: no collection, material or edge sections")
	var bx: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(bx)
	ed.update_side_panel()
	check((secs["SOLID"] as Control).visible and (secs["MATERIAL"] as Control).visible and not (secs["BOOLEAN"] as Control).visible, "a collection: its sections (not the booleans - one collection)")
	check(not (secs["EDIT MESH"] as Control).visible, "object mode: no mesh editing")
	ed.select_part(null)
	check(ed.curve_tab_shown(), "object mode: ECurves's keys work")
	var m: PopupPanel = ed.menu(Vector2(200, 200))
	check(m.find_child("MenuTabs", true, false) == null, "the right-click menu: one page, no tabs")
	var cp: Control = m.find_child("Page", true, false)
	check(cp != null and cp.find_child("Menu_Line", true, false) != null, "nothing picked: its ECurves page has the sketch tools")
	check(cp.find_child("Menu_Extrude", true, false) == null, "... and nothing for edges (none picked)")
	# every button on both pages has a tooltip
	for b in m.find_children("Menu_*", "Button", true, false):
		check((b as Button).tooltip_text != "", "tooltip on " + str(b.name))
	m.hide()
	# a curve picked: what's done to curves - not the sketch tools
	ed.new_model(true)
	ed.curve_tools.add_curve(_rect(1.0, 1.0))
	ed.curve_tools.select(0)
	m = ed.menu(Vector2(200, 200))
	cp = m.find_child("Page", true, false)
	check(cp.find_child("Menu_Extrude", true, false) != null and cp.find_child("Menu_Move edges".validate_node_name(), true, false) != null, "an edge picked: Extrude, Move edges")
	check(cp.find_child("Menu_Line", true, false) == null, "... no sketch tools")
	check(cp.find_child("Menu_Loft", true, false) == null, "... nor what needs two edges")
	m.hide()
	# its points picked: the points' tools only
	ed.curve_tools.pick_point(0, 1)
	m = ed.menu(Vector2(200, 200))
	cp = m.find_child("Page", true, false)
	check(cp.find_child("Menu_Separate vertices".validate_node_name(), true, false) != null, "vertices picked: Separate vertices")
	check(cp.find_child("Menu_Extrude", true, false) == null and cp.find_child("Menu_Union edges".validate_node_name(), true, false) == null, "... not the edges' tools")
	m.hide()
	# the panel's buttons all have tooltips and icons
	var page: Control = tabs.get_child(0)
	for b in page.find_children("*", "Button", true, false):
		check((b as Button).tooltip_text != "", "panel tooltip on " + str(b.name) + " " + (b as Button).text)
	for n in ["m_cv_line", "m_cv_extrude", "m_cv_revolve", "m_cv_loft", "m_cv_pipe", "m_cv_plane"]:
		check(EditorIcons.get_icon(n) != null, "icon " + n)
	await _done(ed)


func test_sketch_by_clicks_and_extrude() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.view.size = Vector2(1000, 700)
	ed.view.sv.size = Vector2i(1000, 700)
	ed.view.set_view("top")
	ed.view.target = Vector3.ZERO
	ed.view.dist = 4.0
	ed.view.update_camera()
	await tree.process_frame
	ct.grid_step = 0.05
	ct.snap_points = false
	ct.begin("rect")
	check(ct.tool == "rect", "the rectangle tool's on")
	check(ed.curve_tab_shown(), "the ECurves tab shown with it")
	check(ct.click(ct._screen(Vector3(0.01, 0, -0.01))), "first corner clicked")
	check(ct.click(ct._screen(Vector3(0.49, 0, 0.31))), "the opposite corner")
	check(ct.curves.size() == 1, "a rectangle made (%d edges)" % ct.curves.size())
	if ct.curves.size() == 1:
		var k: PackedVector3Array = ct.curves[0]["ctrl"]
		check(k.size() == 4 and ct.curves[0]["closed"], "4 corners, closed")
		check(k[0].distance_to(Vector3(0, 0, 0)) < 1e-4 and k[2].distance_to(Vector3(0.5, 0, 0.3)) < 1e-4, "snapped to the grid (%s .. %s)" % [k[0], k[2]])
	check(ct.tool == "rect", "the tool stays on for the next one")
	# a line: three clicks, Enter
	ct.begin("line")
	for p in [Vector3(-1, 0, 0), Vector3(-1, 0, 1), Vector3(-0.5, 0, 1)]:
		ct.click(ct._screen(p))
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	check(ct.key(ev), "Enter ends the line")
	check(ct.curves.size() == 2 and (ct.curves[1]["ctrl"] as PackedVector3Array).size() == 3, "an open line of three vertices")
	# typed sizes: a circle of radius 0.25
	ct.begin("circle")
	ct.click(ct._screen(Vector3(1, 0, 1)))
	for ch in "0.25":
		var e2 := InputEventKey.new()
		e2.pressed = true
		e2.unicode = ch.unicode_at(0)
		ct.key(e2)
	ct.key(ev)
	check(ct.curves.size() == 3 and str(ct.curves[2]["kind"]) == "circle", "a circle from a typed radius")
	if ct.curves.size() == 3:
		var ck: PackedVector3Array = ct.curves[2]["ctrl"]
		check(absf(ck[0].distance_to(ck[1]) - 0.25) < 1e-5, "radius 0.25 (%.4f)" % ck[0].distance_to(ck[1]))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ct.key(esc)
	check(ct.tool == "", "Esc stops the tool")
	# undo takes the circle back, redo brings it
	ed.undo()
	check(ct.curves.size() == 2, "undo: the circle gone")
	ed.redo()
	check(ct.curves.size() == 3, "redo: back")
	# picking by clicking its line
	ct.select(-1)
	var at: Vector2 = ct._screen(Vector3(0.25, 0, 0))
	check(ct.pick(at) == 0, "a click on the rectangle's edge picks it")
	# extrude it into a solid part
	ct.select(0)
	var n0: int = ed.parts().size()
	var part: MeshInstance3D = ct.make_part("extrude", 0.2)
	check(part != null and ed.parts().size() == n0 + 1, "extruded: a new collection")
	if part:
		check(Shapes.open_edges(part.mesh) == 0, "closed solid")
		check(absf(Shapes.volume(part.mesh) - 0.5 * 0.3 * 0.2) < 0.001, "0.5 x 0.3 x 0.2 (%.4f)" % Shapes.volume(part.mesh))
	ed.undo()
	check(ed.parts().size() == n0, "undo removes the collection")
	# the interactive extrude: typed height, Enter
	ct.select(0)
	ct.begin_extrude()
	check(not ct.op.is_empty(), "extrude running")
	for ch in "0.4":
		var e3 := InputEventKey.new()
		e3.pressed = true
		e3.unicode = ch.unicode_at(0)
		ct.key(e3)
	ct.key(ev)
	check(ct.op.is_empty() and ed.parts().size() == n0 + 1, "typed 0.4 + Enter: made")
	if ed.parts().size() == n0 + 1:
		var p2: MeshInstance3D = ed.parts()[-1]
		check(absf(Shapes.volume(p2.mesh) - 0.5 * 0.3 * 0.4) < 0.001, "0.4 high (%.4f)" % Shapes.volume(p2.mesh))
	# fillet the rectangle's corners (kept on the curve), then offset it
	ct.select(0)
	ct.begin_fillet_corners()
	ct.op["value"] = 0.05
	ct._op_update()
	ct.confirm_op()
	check(ct.curves[0].has("radii") and is_equal_approx((ct.curves[0]["radii"] as PackedFloat32Array)[0], 0.05), "corners rounded, kept on the edge")
	ct.select(0)
	ct.begin_offset()
	ct.op["value"] = 0.1
	ct._op_update()
	ct.confirm_op()
	check(ct.curves.size() == 4, "offset: a new edge (%d)" % ct.curves.size())
	await _done(ed)


func test_keys_and_saving() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.show_right_tab(1)
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_L
	check(ct.key(k), "L in object mode: the line tool")
	check(ct.tool == "line", "line on")
	ct.stop()
	ed.mode = "edit"
	check(not ct.key(k), "in edit mode L is the mesh's own")
	ed.mode = "object"
	# kept beside the model, read back
	ct.curves = [_rect(1, 2), _circle(Vector3(0, 1, 0), 0.3, Vector3.BACK)]
	ct.curves[0]["radii"] = PackedFloat32Array([0.1, 0, 0, 0.1])
	var f := "user://test_curves/model.glb"
	DirAccess.make_dir_recursive_absolute("user://test_curves")
	ct.save_beside(f)
	check(FileAccess.file_exists(f + ".curves.json"), "saved beside the model")
	var back := CT.from_json(JSON.parse_string(FileAccess.get_file_as_string(f + ".curves.json"))["curves"])
	check(back.size() == 2 and str(back[1]["kind"]) == "circle", "read back: both edges")
	check(is_equal_approx((back[0]["radii"] as PackedFloat32Array)[0], 0.1), "with their corner radii")
	check((back[1]["n"] as Vector3).is_equal_approx(Vector3.BACK), "and their planes")
	ct.curves = []
	ct.save_beside(f)
	check(not FileAccess.file_exists(f + ".curves.json"), "no edges: the file's removed")
	await _done(ed)


func _vol(p: MeshInstance3D) -> float:
	return Shapes.volume(p.mesh)


func test_procedural_solids() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 0.5))
	ct.select(0)
	var part: MeshInstance3D = ct.make_part("extrude", 0.2)
	check(part != null and part.has_meta("curve_solid"), "the extrusion keeps its recipe")
	if part == null:
		await _done(ed)
		return
	check(absf(_vol(part) - 0.1) < 1e-3, "1 x 0.5 x 0.2 (%.4f)" % _vol(part))
	var mat: Material = part.mesh.surface_get_material(0)
	# the curve made wider: the solid follows
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	k[1].x = 2.0
	k[2].x = 2.0
	ct.curves[0]["ctrl"] = k
	ct._changed("Widen", before)
	check(absf(_vol(part) - 0.2) < 1e-3, "the edge widened to 2 m: the solid follows (%.4f)" % _vol(part))
	check(part.mesh.surface_get_material(0) == mat, "its material kept")
	check(Shapes.open_edges(part.mesh) == 0, "still closed")
	ed.undo()
	check(absf(_vol(part) - 0.1) < 1e-3, "undo: the edge and the solid back (%.4f)" % _vol(part))
	ed.redo()
	check(absf(_vol(part) - 0.2) < 1e-3, "redo: wide again")
	# corners filleted on the curve: the solid's corners round
	ct.select(0)
	ct.begin_fillet_corners()
	ct.op["value"] = 0.1
	ct._op_update()
	ct.confirm_op()
	check(_vol(part) < 0.2 - 1e-4 and _vol(part) > 0.19, "corners rounded on the edge: the solid's too (%.4f)" % _vol(part))
	# its settings: the height
	ed.select_part(part)
	ct.set_spec("value", 0.4)
	check(_vol(part) > 0.38, "height 0.4: made again (%.4f)" % _vol(part))
	check((ct._w("solid_box") as Control).visible, "the SOLID box shows for it")
	check(is_equal_approx((ct._w("solid_value") as SpinBox).value, 0.4), "showing its height")
	ed.undo()
	check(_vol(part) < 0.2, "undo: height 0.2 again (%.4f)" % _vol(part))
	ct.pick_part_curves()
	check(ct.sel == [0], "Pick its edges picks the rectangle")
	# a copy of the part (duplicate) follows the same curves: an instance
	ed.duplicate_part()
	var copy: MeshInstance3D = ed.part
	check(copy != part and copy.has_meta("curve_solid"), "a duplicate keeps the recipe")
	# a curve deleted: the solids stay as they were
	var v0 := _vol(part)
	ct.select(0)
	ct.delete_selected()
	check(is_equal_approx(_vol(part), v0), "its edge deleted: it stays as it is")
	ed.undo()
	# made a plain mesh: no longer follows
	ed.select_part(part)
	ct.unlink_part()
	check(not part.has_meta("curve_solid"), "plain mesh now")
	before = ct._state()
	k = ct.curves[0]["ctrl"]
	k[1].x = 3.0
	ct.curves[0]["ctrl"] = k
	ct._changed("Move", before)
	check(is_equal_approx(_vol(part), v0), "the edge changed: the plain mesh didn't")
	check(not is_equal_approx(_vol(copy), v0), "... but the linked copy did")
	ed.undo()
	ed.undo()
	check(part.has_meta("curve_solid"), "undo: linked again")
	# the recipe through JSON (as saved in the glb's extras): ids come back as floats - still found
	var spec: Dictionary = JSON.parse_string(JSON.stringify(part.get_meta("curve_solid")))
	check(ct.solid_of(spec) != null, "the recipe works after a round trip through JSON")
	await _done(ed)


func test_holes() -> void:
	var outer := _rect(1.0, 0.5)
	var hole := _circle(Vector3(0.5, 0, 0.25), 0.1)
	var rs := CT.regions([outer, hole])
	check(rs.size() == 1 and (rs[0]["holes"] as Array).size() == 1, "the circle is the rectangle's hole")
	_closed_solid(CT.extrude_mesh([outer, hole], 0.2), "a plate with a round hole", (0.5 - PI * 0.01) * 0.2, 0.01)
	_closed_solid(CT.extrude_mesh([hole, outer], -0.2), "the same, picked the other way, pushed down", (0.5 - PI * 0.01) * 0.2, 0.01)
	var two := _circle(Vector3(0.2, 0, 0.25), 0.05)
	var hole2 := _circle(Vector3(0.7, 0, 0.25), 0.08)
	_closed_solid(CT.extrude_mesh([outer, two, hole2], 0.1), "two holes", (0.5 - PI * (0.0025 + 0.0064)) * 0.1, 0.01)
	# an island in the hole: a solid of its own
	var island := _circle(Vector3(0.5, 0, 0.25), 0.04)
	_closed_solid(CT.extrude_mesh([outer, hole, island], 0.1), "a hole with an island", (0.5 - PI * 0.01 + PI * 0.0016) * 0.1, 0.01)
	var f := CT.fill_mesh([outer, hole])
	var area := 0.0
	var a := f.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for t in range(0, ix.size(), 3):
		area += (v[ix[t + 1]] - v[ix[t]]).cross(v[ix[t + 2]] - v[ix[t]]).length() * 0.5
	check(absf(area - (0.5 - PI * 0.01)) < 0.005, "fill with a hole: the ring's area (%.4f)" % area)


static func _area(cs: Array) -> float:
	# (outlines plus, holes minus: by winding about the first's normal)
	var n: Vector3 = cs[0]["n"]
	var a := 0.0
	for c in cs:
		a += CT._winding(CT.sample(c), n) * 0.5 * signf(1.0)
	return a


func test_moved_solid_takes_its_curves() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.view.size = Vector2(1000, 700)
	ed.view.sv.size = Vector2i(1000, 700)
	ed.new_model(true)
	ed.view.set_view("top")
	ed.view.target = Vector3.ZERO
	ed.view.dist = 4.0
	ed.view.update_camera()
	ct.add_curve(_rect(1.0, 0.5))
	ct.select(0)
	var part: MeshInstance3D = ct.make_part("extrude", 0.2)
	part.position = Vector3(0.5, 0.7, 0.0)   # (moved - as a drag of the part does)
	var own: Dictionary = ct.owner_xfs()
	check(own.has(int(ct.curves[0]["id"])) and (own[int(ct.curves[0]["id"])] as Transform3D).origin.is_equal_approx(Vector3(0.5, 0.7, 0)), "the edge is placed by its solid")
	# picked where it's drawn now (with the part), not where its points were
	ct.select(-1)
	check(ct.pick(ct._screen(Vector3(1.0, 0.7, 0.0))) == 0, "picked at its new place")
	ct.select(0)
	var h: Array = ct.pick_handle(ct._screen(Vector3(1.5, 0.7, 0.0)))
	check(h == [0, 1], "its corner handle where it's drawn (%s)" % [h])
	# a copy made from it lands where it shows
	ct.duplicate_selected()
	var dk: PackedVector3Array = ct.curves[1]["ctrl"]
	check(absf(dk[0].y - 0.7) < 1e-5, "a copy of a placed edge shows where it does (y %.2f)" % dk[0].y)
	# a new solid from the placed curve sits on it
	ct.select(0)
	var p2: MeshInstance3D = ct.make_part("pipe", 0.02)
	check(p2 != null and p2.position.is_equal_approx(Vector3(0.5, 0.7, 0.0)), "a new solid from it is placed with it")
	await _done(ed)


func test_curve_booleans() -> void:
	var a := _rect(1.0, 1.0)
	var b := {"kind": "line", "ctrl": PackedVector3Array([Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5), Vector3(1.5, 0, 1.5), Vector3(0.5, 0, 1.5)]), "closed": true, "n": Vector3.UP}
	var u: Array = CT.curve_bool([a, b], "union")
	check(u.size() == 1, "two overlapping squares: one outline (%d)" % u.size())
	if u.size() == 1:
		check(absf(absf(CT._winding(CT.sample(u[0]), Vector3.UP)) * 0.5 - 1.75) < 1e-3, "its area 1.75 (%.3f)" % (absf(CT._winding(CT.sample(u[0]), Vector3.UP)) * 0.5))
		check((u[0]["ctrl"] as PackedVector3Array).size() == 8, "an L-ish outline: 8 corners (%d)" % (u[0]["ctrl"] as PackedVector3Array).size())
	var i: Array = CT.curve_bool([a, b], "intersect")
	check(i.size() == 1 and absf(absf(CT._winding(CT.sample(i[0]), Vector3.UP)) * 0.5 - 0.25) < 1e-3, "intersect: the 0.5 x 0.5 they share")
	var d: Array = CT.curve_bool([a, b], "subtract")
	check(d.size() == 1 and absf(absf(CT._winding(CT.sample(d[0]), Vector3.UP)) * 0.5 - 0.75) < 1e-3, "subtract: 0.75 left")
	# a circle inside the square: subtract makes a hole - extruded, a holed plate
	var hole := _circle(Vector3(0.5, 0, 0.5), 0.2)
	var cut: Array = CT.curve_bool([a, hole], "subtract")
	check(cut.size() == 2, "the square minus a circle inside it: outline + hole (%d)" % cut.size())
	_closed_solid(CT.extrude_mesh(cut, 0.1), "the cut edges extruded", (1.0 - PI * 0.04) * 0.1, 0.01)
	# not on one plane: nothing
	var up := _rect(1.0, 1.0)
	var k: PackedVector3Array = up["ctrl"]
	for j in k.size():
		k[j].y = 0.5
	var lifted: Array = CT.curve_bool([a, up], "union")
	check(lifted.size() == 1 and absf((lifted[0]["ctrl"] as PackedVector3Array)[0].y) < 1e-5, "a parallel plane above: brought down onto the first's plane")
	# in the editor: the picked curves replaced by the result, one undo step
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(a)
	ct.add_curve(hole)
	ct.select(0)
	ct.select(1, true)
	ct.curve_boolean("subtract")
	check(ct.curves.size() == 2 and ct.sel.size() == 2, "replaced by the outline and its hole")
	var part: MeshInstance3D = ct.make_part("extrude", 0.1)
	check(part != null and absf(Shapes.volume(part.mesh) - (1.0 - PI * 0.04) * 0.1) < 0.002, "extruded: the holed plate")
	ed.undo()
	ed.undo()
	check(ct.curves.size() == 2 and str(ct.curves[1]["kind"]) == "circle", "undo: the square and the circle back")
	await _done(ed)


func test_live_boolean() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var a: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))
	ct.select(1)
	var b: MeshInstance3D = ct.make_part("extrude", 0.4)
	b.position = Vector3(0, -0.1, 0)   # (through A: taller than it, from below)
	b.mesh = CT.extrude_mesh([ct.curves[1]], 0.6)
	b.set_meta("curve_solid", {"kind": "extrude", "ids": [int(ct.curves[1]["id"])], "value": 0.6, "segs": 32, "axis": -1})
	ed.shape_tools.keep_b = false
	check(ed.shape_tools.boolean("difference", a, b, true), "the boolean ran")
	var spec: Dictionary = a.get_meta("curve_solid", {})
	check(str(spec.get("kind", "")) == "bool", "the result keeps a live recipe")
	var v0 := Shapes.volume(a.mesh)
	check(absf(v0 - (1.0 - PI * 0.04) * 0.4) < 0.01, "a 1 x 1 x 0.4 block with a round hole (%.4f)" % v0)
	# the hole's circle made bigger: the result follows
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[1]["ctrl"]
	k[1] = Vector3(0.8, 0, 0.5)
	ct.curves[1]["ctrl"] = k
	ct._changed("Bigger hole", before)
	var v1 := Shapes.volume(a.mesh)
	check(absf(v1 - (1.0 - PI * 0.09) * 0.4) < 0.01, "the hole's edge widened: the hole is wider (%.4f)" % v1)
	# A's curve changed: follows too
	before = ct._state()
	k = ct.curves[0]["ctrl"]
	k[1].x = 2.0
	k[2].x = 2.0
	ct.curves[0]["ctrl"] = k
	ct._changed("Wider block", before)
	check(Shapes.volume(a.mesh) > v1 + 0.3, "the block's edge widened: the result too (%.4f)" % Shapes.volume(a.mesh))
	check(ct.owner_xfs().has(int(ct.curves[1]["id"])), "B's edges still placed (through the recipe)")
	ed.undo()
	ed.undo()
	ed.undo()
	check(str(a.get_meta("curve_solid", {}).get("kind", "")) == "extrude", "undo the boolean: A is its extrusion again")
	await _done(ed)


func test_curve_boolean_results_are_lean() -> void:
	var sq := _rect(1.0, 1.0)
	# a circle biting into the square's side
	var bite := _circle(Vector3(1.0, 0, 0.5), 0.3)
	var r: Array = CT.curve_bool([sq, bite], "subtract")
	check(r.size() == 1, "one outline")
	if r.size() == 1:
		var k: PackedVector3Array = r[0]["ctrl"]
		check(str(r[0]["kind"]) == "path", "a path: straight sides and an arc (%s)" % r[0]["kind"])
		check(k.size() <= 12, "few vertices: %d (the boolean gave ~40)" % k.size())
		var want := 1.0 - PI * 0.09 * 0.5
		var got := absf(CT._winding(CT.sample(r[0]), Vector3.UP)) * 0.5
		check(absf(got - want) < want * 0.01, "its shape kept: area %.4f, want %.4f" % [got, want])
		var corners := 0
		for b in (r[0]["sharp"] as PackedByteArray):
			corners += b
		check(corners == 6, "6 corners: the square's 4 and where the arc meets it (%d)" % corners)
		_closed_solid(CT.extrude_mesh(r, 0.1), "the bitten square extruded", want * 0.1, 0.015)
	# a circle inside: the hole is that circle itself
	var r2: Array = CT.curve_bool([sq, _circle(Vector3(0.5, 0, 0.5), 0.2)], "subtract")
	check(r2.size() == 2, "outline + hole")
	if r2.size() == 2:
		var kinds := [str(r2[0]["kind"]), str(r2[1]["kind"])]
		check("circle" in kinds and "line" in kinds, "the square stays a 4-corner line, the hole a circle (%s)" % [kinds])
		for c in r2:
			if str(c["kind"]) == "line":
				check((c["ctrl"] as PackedVector3Array).size() == 4, "4 corners")
	# two circles unioned: a smooth path with two corners where they meet
	var u: Array = CT.curve_bool([_circle(Vector3.ZERO, 0.5), _circle(Vector3(0.6, 0, 0), 0.5)], "union")
	check(u.size() == 1 and (u[0]["ctrl"] as PackedVector3Array).size() <= 14, "two circles: one lean path (%d vertices)" % ((u[0]["ctrl"] as PackedVector3Array).size() if u.size() == 1 else -1))
	if u.size() == 1:
		var d := 0.6
		var lens := 2.0 * 0.25 * acos(d / 1.0) - 0.5 * d * sqrt(1.0 - d * d)   # (the overlap of two r 0.5 circles d apart)
		var want := 2.0 * PI * 0.25 - lens
		var got := absf(CT._winding(CT.sample(u[0]), Vector3.UP)) * 0.5
		check(absf(got - want) < want * 0.01, "the union's area %.4f, want %.4f" % [got, want])
	# kept with the model: the path's corners too
	var back := CT.from_json(JSON.parse_string(JSON.stringify(CT.to_json(r))))
	check(back.size() == 1 and (back[0]["sharp"] as PackedByteArray) == (r[0]["sharp"] as PackedByteArray), "a path's corners saved and read back")


func test_simplify_curve() -> void:
	# a dense outline (as the old curve booleans left them): a square with a round bite, 40-odd points
	var sq := _rect(1.0, 1.0)
	var r: Array = CT.curve_bool([sq, _circle(Vector3(1.0, 0, 0.5), 0.3)], "subtract")
	var full := {"kind": "line", "ctrl": CT.sample(r[0]), "closed": true, "n": Vector3.UP}
	check((full["ctrl"] as PackedVector3Array).size() > 30, "a dense line to start (%d vertices)" % (full["ctrl"] as PackedVector3Array).size())
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(full)
	ct.select(0)
	var part: MeshInstance3D = ct.make_part("extrude", 0.1)
	var v0 := Shapes.volume(part.mesh)
	var id0: int = ct.curves[0]["id"]
	ct.select(0)
	ct.simplify_selected()
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(k.size() <= 12, "simplified to %d vertices" % k.size())
	check(int(ct.curves[0]["id"]) == id0, "the same edge (its id kept)")
	check(absf(Shapes.volume(part.mesh) - v0) < v0 * 0.015, "its solid follows, its shape kept (%.4f vs %.4f)" % [Shapes.volume(part.mesh), v0])
	ed.undo()
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() > 30, "undo: dense again")
	await _done(ed)


## The farthest a curve's drawn points stray from the nearest of the given circles ([centre, r]...).
static func _off_circles(c: Dictionary, circles: Array) -> float:
	var worst := 0.0
	for q in CT.sample(c):
		var d := INF
		for ci in circles:
			d = minf(d, absf(q.distance_to(ci[0]) - float(ci[1])))
		worst = maxf(worst, d)
	return worst


func test_curve_boolean_keeps_true_arcs() -> void:
	# (the user's case: a small circle minus a big one overlapping it - a short arc of the big one bites in)
	var big := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(-1.7, 0, -0.35), Vector3(-0.8, 0, -0.85)]), "closed": true, "n": Vector3.UP}
	var small := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(-0.45, 0, -0.45), Vector3(-0.05, 0, -0.75)]), "closed": true, "n": Vector3.UP}
	var circles := [[Vector3(-1.7, 0, -0.35), Vector3(-1.7, 0, -0.35).distance_to(Vector3(-0.8, 0, -0.85))], [Vector3(-0.45, 0, -0.45), 0.5]]
	for op in ["subtract", "intersect", "union"]:
		var r: Array = CT.curve_bool([small, big], op)
		check(r.size() == 1, "%s: one edge" % op)
		if r.size() != 1:
			continue
		var off := _off_circles(r[0], circles)
		check(off < 0.002, "%s: on the true circles (%.4f m off at worst)" % [op, off])
		check((r[0]["ctrl"] as PackedVector3Array).size() <= 14, "%s: lean (%d vertices)" % [op, (r[0]["ctrl"] as PackedVector3Array).size()])
	# a point of a path's arc moved off its circle: the run is a smooth spline instead, through its points
	var r2: Array = CT.curve_bool([small, big], "subtract")
	var c: Dictionary = r2[0].duplicate(true)
	var k: PackedVector3Array = c["ctrl"]
	var j := 0
	while (c["sharp"] as PackedByteArray)[j] == 1:
		j += 1
	k[j] += Vector3(0.05, 0, 0.05)
	c["ctrl"] = k
	var s := CT.sample(c)
	var near := INF
	for i in s.size():
		var p := Geometry3D.get_closest_point_to_segment(k[j], s[i], s[(i + 1) % s.size()])
		near = minf(near, p.distance_to(k[j]))
	check(near < 1e-3, "a moved vertex: the edge still passes through it (%.5f)" % near)


func test_small_intersections_stay_lean() -> void:
	# a small lens where a big circle and a small one overlap: two arcs, two corners
	var big := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(-1.7, 0, -0.35), Vector3(-0.8, 0, -0.85)]), "closed": true, "n": Vector3.UP}
	var small := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(-0.45, 0, -0.45), Vector3(-0.05, 0, -0.75)]), "closed": true, "n": Vector3.UP}
	for order in [[small, big], [big, small]]:
		var r: Array = CT.curve_bool(order, "intersect")
		check(r.size() == 1, "one lens")
		if r.size() == 1:
			var k: PackedVector3Array = r[0]["ctrl"]
			check(k.size() == 4, "the lens: 2 corners + an arc's middle each (%d vertices)" % k.size())
			var circles := [[Vector3(-1.7, 0, -0.35), Vector3(-1.7, 0, -0.35).distance_to(Vector3(-0.8, 0, -0.85))], [Vector3(-0.45, 0, -0.45), 0.5]]
			check(_off_circles(r[0], circles) < 0.002, "on the true circles")
	# a tiny square cut by a big circle: straight sides stay straight, the arc an arc
	var sq := _rect(0.2, 0.2)
	var c := _circle(Vector3(0.2, 0, 0.2), 0.12)
	var r2: Array = CT.curve_bool([sq, c], "intersect")
	check(r2.size() == 1 and (r2[0]["ctrl"] as PackedVector3Array).size() <= 5, "a quarter disc: corner, two sides, an arc (%d vertices)" % ((r2[0]["ctrl"] as PackedVector3Array).size() if r2.size() == 1 else -1))


func _key(ct, code: int, uni := 0) -> bool:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.unicode = uni
	return ct.key(e)


func _type(ct, text: String) -> void:
	for ch in text:
		_key(ct, KEY_NONE, ch.unicode_at(0))


func test_curves_move_turn_scale_in_3d() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 0.5))
	ct.select(0)
	var part: MeshInstance3D = ct.make_part("extrude", 0.2)
	ct.select(0)
	# G, Y, 0.5, Enter: up half a metre - off its plane, into 3D; its solid follows
	check(_key(ct, KEY_G), "G with an edge picked: move it")
	check(str(ct.op.get("kind", "")) == "move", "moving")
	_key(ct, KEY_Y)
	_type(ct, "0.5")
	_key(ct, KEY_ENTER)
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(absf(k[0].y - 0.5) < 1e-5 and absf(k[2].y - 0.5) < 1e-5, "lifted 0.5 m on Y (%s)" % k[0])
	check(absf(part.mesh.get_aabb().position.y - 0.5) < 1e-4, "its solid follows (%.3f)" % part.mesh.get_aabb().position.y)
	# R, X, 90: stood up on edge - its plane turned too
	_key(ct, KEY_R)
	_key(ct, KEY_X)
	_type(ct, "90")
	_key(ct, KEY_ENTER)
	var n: Vector3 = ct.curves[0]["n"]
	check(absf(n.y) < 1e-4 and absf(absf(n.z) - 1.0) < 1e-4, "turned 90° about X: facing along Z now (%s)" % n)
	check(absf(Shapes.volume(part.mesh) - 0.1) < 1e-3, "the solid turned with it, the same size (%.4f)" % Shapes.volume(part.mesh))
	check(Shapes.open_edges(part.mesh) == 0, "and closed")
	# S, 2: twice the size about its middle
	_key(ct, KEY_S)
	_type(ct, "2")
	_key(ct, KEY_ENTER)
	check(absf(Shapes.volume(part.mesh) - 0.4) < 2e-3, "scaled x2: the outline 4x the area (%.4f)" % Shapes.volume(part.mesh))
	# undo: back step by step
	ed.undo()
	ed.undo()
	ed.undo()
	k = ct.curves[0]["ctrl"]
	check(absf(k[0].y) < 1e-5 and (ct.curves[0]["n"] as Vector3).is_equal_approx(Vector3.UP), "undo x3: back on the ground")
	check(absf(Shapes.volume(part.mesh) - 0.1) < 1e-3, "the solid too")
	# Esc cancels; X while moving is an axis, not Delete
	_key(ct, KEY_G)
	_key(ct, KEY_X)
	check(ct.curves.size() == 1 and int(ct.op.get("axis", -1)) == 0, "X while moving: the X axis (nothing deleted)")
	_key(ct, KEY_ESCAPE)
	check(ct.op.is_empty() and absf((ct.curves[0]["ctrl"] as PackedVector3Array)[0].y) < 1e-5, "Esc: nothing moved")
	await _done(ed)



func test_curve_booleans_across_planes() -> void:
	var sq := _rect(1.0, 1.0)
	# a circle lifted 0.3 m above the square (a parallel plane): cut out as the same circle, on the square's plane
	var lifted := _circle(Vector3(0.5, 0.3, 0.5), 0.2)
	var r: Array = CT.curve_bool([sq, lifted], "subtract")
	check(r.size() == 2, "outline + hole (%d)" % r.size())
	var hole := {}
	for c in r:
		if str(c["kind"]) == "circle":
			hole = c
	check(not hole.is_empty(), "the hole is still a circle")
	if not hole.is_empty():
		check(absf((hole["ctrl"] as PackedVector3Array)[0].y) < 1e-6 and absf((hole["ctrl"] as PackedVector3Array)[1].y) < 1e-6, "brought down onto the square's plane")
	_closed_solid(CT.extrude_mesh(r, 0.1), "extruded with its hole", (1.0 - PI * 0.04) * 0.1, 0.01)
	# a circle tilted 60° (standing at an angle): projected - seen square-on from the square, an ellipse
	var tilt := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(60.0))
	var tilted := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(0.5, 0.2, 0.5), Vector3(0.7, 0.2, 0.5)]), "closed": true, "n": tilt}
	var r2: Array = CT.curve_bool([sq, tilted], "subtract")
	check(r2.size() == 2, "outline + a projected hole (%d)" % r2.size())
	var area := 0.0
	for c in r2:
		for q in CT.sample(c):
			check(absf(q.y) < 1e-5, "on the square's plane")
			break
		area += CT._winding(CT.sample(c), Vector3.UP) * 0.5 * (1.0 if CT._winding(CT.sample(c), Vector3.UP) > 0 else 1.0)
	var holes_area := 0.0
	for c in r2:
		var w := absf(CT._winding(CT.sample(c), Vector3.UP)) * 0.5
		if w < 0.5:
			holes_area += w
	var want := PI * 0.04 * cos(deg_to_rad(60.0))
	check(absf(holes_area - want) < want * 0.02, "the hole is the circle as seen from above: an ellipse of area %.4f (want %.4f)" % [holes_area, want])
	# standing exactly edge-on: left out (nothing to cut)
	var edge := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(0.5, 0.2, 0.5), Vector3(0.7, 0.2, 0.5)]), "closed": true, "n": Vector3.BACK}
	check(not CT.projectable(edge, Vector3.UP), "edge-on: can't be projected")
	check(CT.curve_bool([sq, edge], "subtract").is_empty(), "nothing to do with only an edge-on one")
	var r3: Array = CT.curve_bool([sq, edge, _circle(Vector3(0.5, 0, 0.5), 0.1)], "subtract")
	check(r3.size() == 2, "the edge-on one left out, the rest done (%d)" % r3.size())


func test_panel_buttons_enable_and_run() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.add_curve(_circle(Vector3(1.0, 0, 0.5), 0.3))
	ct.select(0)
	var union: Button = ct._panel_btns["op_Union edges"][0]
	check(union.disabled, "one edge picked: Union off")
	ct.select(1, true)
	for n in ["Union edges", "Subtract edges", "Intersect edges", "Join edges", "Bridge edge", "Loft", "Sweep"]:
		check(not (ct._panel_btns["op_" + n][0] as Button).disabled, n + " on with two picked")
	union.pressed.emit()
	check(ct.curves.size() == 1 and str(ct.curves[0]["kind"]) == "path", "pressing Union ran it: one outline")
	# the panel's connections are methods (they survive a hot reload), not lambdas
	for k in ct._panel_btns:
		var e = ct._panel_btns[k]
		if not (e is Button or e is Array):
			continue   # (the SOLID box's controls, kept there too)
		var b: Button = e if e is Button else e[0]
		for c in b.pressed.get_connections():
			check(not (c["callable"] as Callable).is_custom() or (c["callable"] as Callable).get_object() == ct, "%s: pressed goes to a method of the edge tools" % k)
	await _done(ed)


func test_negative_extrusions() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block (positive), then a circle on its top
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(0.5, 0.4, 0.5), 0.2))
	ct.select(1)
	# extruding down: positive by default - a new solid, nothing cut
	ct.begin_extrude()
	ct.op["value"] = -0.2
	ct._op_update()
	check(not ct.op.get("neg", false), "positive by default")
	ct.confirm_op()
	check(ed.parts().size() == 2 and absf(Shapes.volume(block.mesh) - 0.4) < 1e-3, "positive: a solid of its own, the block whole")
	ed.undo()
	check(ed.parts().size() == 1, "undo: gone")
	# N: negative - cut from the block it's in, live
	ct.select(1)
	ct.begin_extrude()
	ct.op["value"] = -0.2
	_key(ct, KEY_N)
	check(ct.op.get("neg", false) and ct.op.get("target") == block, "N: negative, cutting the block")
	ct.confirm_op()
	check(ed.parts().size() == 1, "the cutter's collection went into the cut")
	var want := 0.4 - PI * 0.04 * 0.2
	check(absf(Shapes.volume(block.mesh) - want) < 0.005, "a 0.2 deep round pocket (%.4f, want %.4f)" % [Shapes.volume(block.mesh), want])
	check(str(block.get_meta("curve_solid", {}).get("kind", "")) == "bool", "live: the block keeps the cut as a recipe")
	# the pocket's curve made bigger: the cut follows
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[1]["ctrl"]
	k[1] = Vector3(0.8, 0.4, 0.5)
	ct.curves[1]["ctrl"] = k
	ct._changed("Bigger", before)
	want = 0.4 - PI * 0.09 * 0.2
	check(absf(Shapes.volume(block.mesh) - want) < 0.006, "the circle widened: the pocket too (%.4f, want %.4f)" % [Shapes.volume(block.mesh), want])
	# made positive again: the cutter its own part, the block whole
	ed.select_part(block)
	ct.make_positive()
	check(ed.parts().size() == 2 and absf(Shapes.volume(block.mesh) - 0.4) < 1e-3, "positive again: the block whole, the cutter a collection")
	var cutter: MeshInstance3D = ed.parts()[1]
	check(cutter.has_meta("curve_solid") and absf(Shapes.volume(cutter.mesh) - PI * 0.09 * 0.2) < 0.005, "the cutter: the 0.3-radius disc, still following its edge")
	# and negative again, from the SOLID box's button
	ed.select_part(cutter)
	ct.make_negative()
	check(ed.parts().size() == 1 and Shapes.volume(block.mesh) < 0.4 - 0.05, "Negative: cut from the block again")
	ed.undo()
	check(ed.parts().size() == 2, "undo: positive")
	await _done(ed)


func test_curves_redrawn_when_their_solid_moves() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var part: MeshInstance3D = ct.make_part("extrude", 0.2)
	await tree.process_frame
	await tree.process_frame
	var drawn := [0]
	var count := func(): drawn[0] += 1
	ct.layer.draw.connect(count)
	part.position += Vector3(0, 0.5, 0)   # (moved as G / the gizmo / a drag do)
	await tree.process_frame
	await tree.process_frame
	check(drawn[0] > 0, "the edges' layer redrawn as their solid moved (%d)" % drawn[0])
	ct.layer.draw.disconnect(count)
	await _done(ed)


func test_recipe_tree_editable_any_time() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(0.5, 0.4, 0.5), 0.2))
	ct.select(1)
	var cyl: MeshInstance3D = ct.make_part("extrude", -0.2)
	ct.cut_from(cyl, block)
	ed.select_part(block)
	ct._refresh_panel()
	var recipe: VBoxContainer = ct._w("recipe")
	check(recipe != null and (ct._w("solid_box") as Control).visible, "the recipe shows for the cut block")
	var spins := recipe.find_children("*", "SpinBox", true, false)
	var roles := recipe.find_children("*", "OptionButton", true, false)
	check(spins.size() == 2 and roles.size() == 1, "two extrusions' heights and one role (%d, %d)" % [spins.size(), roles.size()])
	# the block's own height, inside the cut: 0.4 -> 0.6 (still cut 0.2 deep from its old top: now a hole
	# further down... the pocket stays where its curve is)
	var v0 := Shapes.volume(block.mesh)
	(spins[0] as SpinBox).value = 0.6
	check(absf(Shapes.volume(block.mesh) - (v0 + 0.2)) < 0.01, "the block's height changed inside its recipe (%.4f)" % Shapes.volume(block.mesh))
	# the cutter's depth: 0.2 -> 0.4
	(spins[1] as SpinBox).value = -0.4
	check(absf(Shapes.volume(block.mesh) - (0.6 - PI * 0.04 * 0.4)) < 0.01, "the cut's depth changed (%.4f)" % Shapes.volume(block.mesh))
	# the role: Cut -> Join -> Common
	(roles[0] as OptionButton).select(0)
	(roles[0] as OptionButton).item_selected.emit(0)
	check(str(block.get_meta("curve_solid")["op"]) == "union", "role: Join")
	(roles[0] as OptionButton).item_selected.emit(2)
	check(str(block.get_meta("curve_solid")["op"]) == "intersection" and absf(Shapes.volume(block.mesh) - PI * 0.04 * 0.4) < 0.01, "role: Common - only the shared cylinder (%.4f)" % Shapes.volume(block.mesh))
	(roles[0] as OptionButton).item_selected.emit(1)
	# the block back to 0.4 high; Both ways on the 0.4 cutter: centred on the block's top, half of it inside
	(spins[0] as SpinBox).value = 0.4
	var boths := recipe.find_children("*", "CheckBox", true, false)
	(boths[1] as CheckBox).button_pressed = true
	check(bool(ct.node_at(block.get_meta("curve_solid"), ["b"]).get("both", false)), "Both ways set on the cutter")
	check(absf(Shapes.volume(block.mesh) - (0.4 - PI * 0.04 * 0.2)) < 0.01, "both ways: only half the cut goes into the block (%.4f)" % Shapes.volume(block.mesh))
	# undo each (height, depth, 3 roles, height, both ways), all the way back to the cut as made
	for i in 7:
		ed.undo()
	check(absf(Shapes.volume(block.mesh) - (0.4 - PI * 0.04 * 0.2)) < 0.01, "undo x5: the cut as it was made (%.4f)" % Shapes.volume(block.mesh))
	# separate: the cutter its own part again
	ct.separate_node([])
	check(ed.parts().size() == 2 and str(block.get_meta("curve_solid")["kind"]) == "extrude", "separated: the block plain, the cutter a collection")
	await _done(ed)


func test_curve_box_properties_live() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_circle(Vector3.ZERO, 0.2))
	ct.select(0)
	var part: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.select(0)
	check((ct._w("cv_box") as Control).visible and (ct._w("cv_radius_row") as Control).visible, "a picked circle: its radius shown")
	check(absf((ct._w("cv_radius") as SpinBox).value - 0.2) < 1e-5, "0.2")
	(ct._w("cv_radius") as SpinBox).value = 0.3
	check(absf(Shapes.volume(part.mesh) - PI * 0.09 * 0.5) < 0.005, "radius 0.3 typed: the cylinder follows (%.4f)" % Shapes.volume(part.mesh))
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(1)
	check((ct._w("cv_corner_row") as Control).visible and not (ct._w("cv_radius_row") as Control).visible, "a rectangle: its corner radius, no circle radius")
	(ct._w("cv_corner") as SpinBox).value = 0.1
	check(is_equal_approx((ct.curves[1]["radii"] as PackedFloat32Array)[2], 0.1), "corners rounded 0.1")
	(ct._w("cv_closed") as CheckBox).button_pressed = false
	check(not ct.curves[1]["closed"], "opened")
	(ct._w("cv_name") as LineEdit).text_submitted.emit("Base")
	check(str(ct.curves[1]["name"]) == "Base", "renamed")
	ed.undo()
	ed.undo()
	ed.undo()
	ed.undo()
	ed.undo()
	check(absf(Shapes.volume(part.mesh) - PI * 0.04 * 0.5) < 0.005, "undo all the way: the cylinder's radius 0.2 again")
	await _done(ed)


func test_roles_for_every_solid_and_curve() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# one extrusion of two overlapping circles (as the user made): each curve gets a role
	ct.add_curve(_circle(Vector3.ZERO, 0.5))
	ct.add_curve(_circle(Vector3(0.6, 0, 0), 0.4))
	ct.select(0)
	ct.select(1, true)
	var p: MeshInstance3D = ct.make_part("extrude", 0.2)
	ed.select_part(p)
	ct._refresh_panel()
	var recipe: VBoxContainer = ct._w("recipe")
	var obs := recipe.find_children("*", "OptionButton", true, false)
	check(obs.size() == 2, "both circles listed with a role (%d)" % obs.size())
	var role_row: Control = ct._w("role_row")
	check(role_row.visible, "the solid's own role shown")
	# circle 2: Cut - circle 1 with a bite, one clean closed solid
	(obs[1] as OptionButton).item_selected.emit(1)
	var r1 := 0.5
	var r2 := 0.4
	var d := 0.6
	# (the lens of two circles r1, r2, d apart)
	var a1 := acos((d * d + r1 * r1 - r2 * r2) / (2 * d * r1))
	var a2 := acos((d * d + r2 * r2 - r1 * r1) / (2 * d * r2))
	var lens := r1 * r1 * (a1 - sin(2 * a1) / 2) + r2 * r2 * (a2 - sin(2 * a2) / 2)
	var want := (PI * r1 * r1 - lens) * 0.2
	check(Shapes.open_edges(p.mesh) == 0, "closed")
	check(absf(Shapes.volume(p.mesh) - want) < want * 0.02, "circle 1 minus circle 2, extruded (%.4f, want %.4f)" % [Shapes.volume(p.mesh), want])
	# both Add: joined into one outline (no overlap inside)
	(obs[1] as OptionButton).item_selected.emit(0)
	want = (PI * (r1 * r1 + r2 * r2) - lens) * 0.2
	check(absf(Shapes.volume(p.mesh) - want) < want * 0.02, "both added: one joined solid (%.4f, want %.4f)" % [Shapes.volume(p.mesh), want])
	ed.undo()
	ed.undo()
	check(not ct.node_at(p.get_meta("curve_solid"), []).has("roles"), "undo: no roles again")
	# a solid's own role: a small cylinder inside a block - Cut the solid it's in
	ct.add_curve(_rect(2.0, 2.0))
	ct.curves[2]["ctrl"] = PackedVector3Array([Vector3(-1, -0.5, -1), Vector3(1, -0.5, -1), Vector3(1, -0.5, 1), Vector3(-1, -0.5, 1)])
	ct.select(2)
	var block: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(p)
	ct.set_solid_role(1)
	check(ed.parts().size() == 1 and str(block.get_meta("curve_solid")["kind"]) == "bool", "Cut the solid it's in: the block cut, live")
	check(str(block.get_meta("curve_solid")["op"]) == "difference", "as a cut")
	await _done(ed)


func test_ghosts_of_cut_solids() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(0.5, 0.4, 0.5), 0.2))
	ct.select(1)
	var cyl: MeshInstance3D = ct.make_part("extrude", -0.2)
	ct.cut_from(cyl, block)
	ct.update_ghosts()
	var gs: Array = ct.get_meta("ghost_nodes", [])
	check(gs.size() == 1, "the cutter shows as a ghost (%d)" % gs.size())
	if gs.size() == 1:
		var g: MeshInstance3D = gs[0]
		check(g.get_parent() == ed.view.world and not ed.model.is_ancestor_of(g), "in the view, not the model (never saved)")
		check((g.material_override as StandardMaterial3D).albedo_color.r > 0.9, "red: a cut")
		check(absf(Shapes.volume(g.mesh) - PI * 0.04 * 0.2) < 0.005, "the cutter's shape")
	# the role changed to Join: green
	ed.select_part(block)
	ct.set_node([], "op", "union")
	ct.update_ghosts()
	gs = ct.get_meta("ghost_nodes", [])
	check(gs.size() == 1 and (gs[0].material_override as StandardMaterial3D).albedo_color.g > 0.9, "joined: green")
	# off with the Ghosts box; separated: none
	ct._set_ghosts(false)
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "Ghosts off: none")
	ct._set_ghosts(true)
	ct.separate_node([])
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "separated: no ghost (the cutter's a collection again)")
	await _done(ed)


func test_ghosts_of_cut_curves() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_circle(Vector3.ZERO, 0.5))
	ct.add_curve(_circle(Vector3(0.6, 0, 0), 0.4))
	ct.select(0)
	ct.select(1, true)
	var p: MeshInstance3D = ct.make_part("extrude", 0.2)
	ed.select_part(p)
	ct._curve_role(1, [], str(int(ct.curves[1]["id"])))
	ct.update_ghosts()
	var gs: Array = ct.get_meta("ghost_nodes", [])
	check(gs.size() == 1, "the cut circle shows as a ghost (%d)" % gs.size())
	if gs.size() == 1:
		check(absf(Shapes.volume(gs[0].mesh) - PI * 0.16 * 0.2) < 0.005, "the whole cut circle, extruded as the step is (%.4f)" % Shapes.volume(gs[0].mesh))
	await _done(ed)


func test_cut_curve_own_height() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))
	ct.select(0)
	ct.select(1, true)
	var p: MeshInstance3D = ct.make_part("extrude", 0.4)
	ed.select_part(p)
	var cid := str(int(ct.curves[1]["id"]))
	ct._curve_role(1, [], cid)
	check(absf(Shapes.volume(p.mesh) - (1.0 - PI * 0.04) * 0.4) < 0.005, "the circle cut right through (the step's height)")
	ct._refresh_panel()
	var spins := (ct._w("recipe") as Node).find_children("*", "SpinBox", true, false)
	check(spins.size() == 3, "the step's height + each edge's own (%d)" % spins.size())
	# the circle's own height: from the top down 0.1 - a pocket: its plane at y 0, so both ways off and
	# height 0.1 cuts the bottom 0.1 only
	ct._curve_value(0.1, [], cid)
	var want := 0.4 - PI * 0.04 * 0.1
	check(absf(Shapes.volume(p.mesh) - want) < 0.005, "own height 0.1: a 0.1 deep pocket (%.4f, want %.4f)" % [Shapes.volume(p.mesh), want])
	check(Shapes.open_edges(p.mesh) == 0, "closed")
	ct.update_ghosts()
	var gs: Array = ct.get_meta("ghost_nodes", [])
	check(gs.size() == 1 and absf(Shapes.volume(gs[0].mesh) - PI * 0.04 * 0.1) < 0.003, "its ghost has its own height")
	# the rectangle's own height too (an added curve): 0.6 - the block taller, the pocket the same
	ct._curve_value(0.6, [], str(int(ct.curves[0]["id"])))
	want = 0.6 - PI * 0.04 * 0.1
	check(absf(Shapes.volume(p.mesh) - want) < 0.006, "the block's own height 0.6 (%.4f, want %.4f)" % [Shapes.volume(p.mesh), want])
	ed.undo()
	ed.undo()
	check(absf(Shapes.volume(p.mesh) - (1.0 - PI * 0.04) * 0.4) < 0.005, "undo: through again")
	await _done(ed)


func test_added_curve_own_height_still_cut() -> void:
	# (the user's case: two overlapping circles, the second cuts; the first given a lower height of its
	# own - it must still be cut)
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_circle(Vector3.ZERO, 0.5))
	ct.add_curve(_circle(Vector3(0.6, 0, 0), 0.4))
	ct.select(0)
	ct.select(1, true)
	var p: MeshInstance3D = ct.make_part("extrude", 0.6)
	ed.select_part(p)
	var a := str(int(ct.curves[0]["id"]))
	var b := str(int(ct.curves[1]["id"]))
	ct._curve_role(1, [], b)
	ct._curve_value(0.3, [], a)
	var r1 := 0.5
	var r2 := 0.4
	var d := 0.6
	var a1 := acos((d * d + r1 * r1 - r2 * r2) / (2 * d * r1))
	var a2 := acos((d * d + r2 * r2 - r1 * r1) / (2 * d * r2))
	var lens := r1 * r1 * (a1 - sin(2 * a1) / 2) + r2 * r2 * (a2 - sin(2 * a2) / 2)
	var want := (PI * r1 * r1 - lens) * 0.3
	check(absf(Shapes.volume(p.mesh) - want) < want * 0.03, "the lower added circle still cut by the other (%.4f, want %.4f)" % [Shapes.volume(p.mesh), want])
	check(Shapes.open_edges(p.mesh) == 0, "closed")
	await _done(ed)


func _tree_items(t: Tree) -> Array:
	var out := []
	var stack := [t.get_root()]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		if it == null:
			continue
		out.append(it)
		for c in it.get_children():
			stack.append(c)
	return out


func test_overview_tree() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))
	ct.add_curve(_circle(Vector3(2, 0, 0), 0.3))   # (in no solid)
	ct.select(0)
	ct.select(1, true)
	var solid: MeshInstance3D = ct.make_part("extrude", 0.3)
	ed.add_primitive("box")
	ct._refresh_panel()
	var t: Tree = ct._w("tree")
	check(t != null, "the overview is there")
	var texts := []
	for it in _tree_items(t):
		texts.append(it.get_text(0))
		var m0 = it.get_metadata(0)
		check(not (m0 is Dictionary and m0.has("curve") and m0.has("of")), "a solid's edges folded away at first (%s)" % it.get_text(0))
	# opened: its edges listed
	for it in _tree_items(t):
		var m1 = it.get_metadata(0)
		if m1 is Dictionary and m1.get("part") == solid:
			it.collapsed = false
	ct._fill_tree()
	texts = []
	for it in _tree_items(t):
		texts.append(it.get_text(0))
	check(str(solid.name) in texts and "Box" in texts, "solids and meshes listed (%s)" % [texts])
	check("Edge 3" in texts or "Circle 3" in texts, "the edge in no solid listed")
	# select a solid's curve and the loose curve from the tree: both picked
	t.deselect_all()
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("curve") and int(m["curve"]) in [1, 2]:
			it.select(0)
	ct._tree_apply()
	check(ct.sel.size() == 2 and 1 in ct.sel and 2 in ct.sel, "two edges picked from the overview (%s)" % [ct.sel])
	# select the solid and the box together
	t.deselect_all()
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("part"):
			it.select(0)
	ct._tree_apply()
	check(ed.selected_parts().size() == 2, "both collections selected from the overview")
	# hide a curve with the eye: not drawn, not picked
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("curve") and int(m["curve"]) == 2:
			ct._tree_button(it, 1, 0, MOUSE_BUTTON_LEFT)
			break
	check(ct.curves[2].get("hidden", false), "the eye hid the edge")
	ed.undo()
	check(not ct.curves[2].get("hidden", false), "undo: shown")
	await _done(ed)


func test_cut_solids_shade_smoothly() -> void:
	# a cylinder cut by another: its round walls smooth (neighbouring wall normals close), its rim crisp
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_circle(Vector3.ZERO, 0.5))
	ct.select(0)
	var a: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.add_curve(_circle(Vector3(0.6, -0.1, 0), 0.4))
	ct.select(1)
	var b: MeshInstance3D = ct.make_part("extrude", 0.7)
	ct.cut_from(b, a)
	var arr := a.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var wall_ok := 0
	var wall := 0
	var cap_ok := 0
	var cap := 0
	for i in v.size():
		var p := v[i]
		var on_outer := absf(Vector2(p.x, p.z).length() - 0.5) < 1e-3
		if on_outer and absf(n[i].y) < 0.5:
			wall += 1
			# smooth: the normal points straight out from the axis (not a facet's)
			if n[i].dot(Vector3(p.x, 0, p.z).normalized()) > 0.995:
				wall_ok += 1
		if absf(p.y - 0.5) < 1e-4 and n[i].y > 0.5:
			cap += 1
			if n[i].dot(Vector3.UP) > 0.9999:
				cap_ok += 1
	check(wall > 0 and wall_ok >= wall * 0.95, "the round wall shades smoothly (%d of %d - the few off are at the cut's crease)" % [wall_ok, wall])
	check(cap > 0 and cap_ok == cap, "the top stays flat, its rim crisp (%d of %d)" % [cap_ok, cap])
	await _done(ed)


func test_add_tools_to_a_solid() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	# a circle on the ground, picked, added as a cut: through the whole block (both ways, its height)
	ct.add_curve(_circle(Vector3(0.3, 0, 0.5), 0.15))
	ed.select_part(block)
	ct.select(1)
	ct.add_tool_curves("difference")
	var spec: Dictionary = block.get_meta("curve_solid")
	check(str(spec["kind"]) == "bool" and str(spec["op"]) == "difference", "a cut step added")
	var want := 0.4 - PI * 0.0225 * 0.2   # (both ways from y 0: half of 0.4 inside)
	check(absf(Shapes.volume(block.mesh) - want) < 0.005, "cut (%.4f, want %.4f)" % [Shapes.volume(block.mesh), want])
	# another curve added as a join on top of that
	ct.add_curve(_circle(Vector3(0.75, 0.4, 0.5), 0.1))
	ct.select(2)
	ed.select_part(block)
	ct.add_tool_curves("union")
	spec = block.get_meta("curve_solid")
	check(str(spec["op"]) == "union" and str(spec["a"]["kind"]) == "bool", "a join on top of the cut: nested steps")
	check(Shapes.volume(block.mesh) > want + 0.005, "joined: more volume (%.4f)" % Shapes.volume(block.mesh))
	# the new tool's height is in the recipe, editable
	ct.set_node(["a", "b"], "value", 0.8)
	check(absf(float(ct.node_at(block.get_meta("curve_solid"), ["a", "b"])["value"]) - 0.8) < 1e-6, "the cut's height editable in the recipe")
	for i in 4:   # (the height, the join, the second circle, the cut)
		ed.undo()
	check(str(block.get_meta("curve_solid")["kind"]) == "extrude", "undo x4: the plain block again")
	# another solid added to it
	ct.add_curve(_circle(Vector3(0.5, 0.2, 0.5), 0.2))
	ct.select(ct.curves.size() - 1)
	var cyl: MeshInstance3D = ct.make_part("extrude", 0.5)
	ed.select_part(block)
	ed.select_part(cyl, true)
	ed.select_part(block, true)
	ed.select_part(block)
	ed.select_part(cyl, true)
	# (the solid being added to: selected last makes it the part - select block, then add cyl, then make block current)
	ed.part = block
	ct.add_tool_solid("difference")
	check(ed.parts().size() == 1 and str(block.get_meta("curve_solid")["kind"]) == "bool", "the other solid added as a cut")
	await _done(ed)


func test_hiding_in_overview_hides_ghosts() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(0.3, 0, 0.5), 0.15))
	ed.select_part(block)
	ct.select(1)
	ct.add_tool_curves("difference")
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).size() == 1, "the cut's ghost shows")
	var v0 := Shapes.volume(block.mesh)
	# its curve hidden in the overview: the ghost goes too - the cut stays
	ct._unfolded()[block.get_instance_id()] = true   # (the solid opened: its steps and edges listed)
	ct._refresh_panel()
	var t: Tree = ct._w("tree")
	var curve_item: TreeItem = null
	var step_item: TreeItem = null
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("curve") and int(m["curve"]) == 1:
			curve_item = it
		if m is Dictionary and m.has("step"):
			step_item = it
	check(step_item != null and step_item.get_text(0).begins_with("Cut"), "the cut is a step row in the overview")
	ct._tree_button(curve_item, 1, 0, MOUSE_BUTTON_LEFT)
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "its edge hidden: its ghost hidden")
	check(is_equal_approx(Shapes.volume(block.mesh), v0), "the cut itself stays")
	ed.undo()
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).size() == 1, "undo: shown again")
	# the step's own eye: only its ghost
	ct._refresh_panel()
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("step"):
			step_item = it
	ct._tree_button(step_item, 1, 0, MOUSE_BUTTON_LEFT)
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "the step's eye: its ghost hidden")
	check(not ct.curves[1].get("hidden", false), "its edge still shown")
	# the solid hidden: its ghosts too (the step's ghost shown again first - the tree rebuilt: found anew)
	ct._refresh_panel()
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("step"):
			step_item = it
	ct._tree_button(step_item, 1, 0, MOUSE_BUTTON_LEFT)
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).size() == 1, "its eye again: the ghost back")
	block.visible = false
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "the solid hidden: its ghosts hidden")
	await _done(ed)


func _menu_pick(ct, pm: PopupMenu, text: String) -> bool:
	# (an item by its text - in the menu or a submenu)
	for i in pm.item_count:
		if pm.get_item_text(i) == text:
			ct._menu_act(pm.get_item_id(i))
			return true
		var sub := pm.get_item_submenu_node(i)
		if sub:
			for j in sub.item_count:
				if sub.get_item_text(j) == text:
					ct._menu_act(sub.get_item_id(j))
					return true
	return false


func test_overview_menu() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	block.name = "Block"
	ct.add_curve(_circle(Vector3(0.5, 0.2, 0.5), 0.2))
	ct.select(1)
	var cyl: MeshInstance3D = ct.make_part("extrude", 0.4)
	cyl.name = "Cyl"
	# a solid's menu: Attach to > Cut from Block
	var pm: PopupMenu = ct.tree_menu({"part": cyl})
	check(_menu_pick(ct, pm, "Cut from Block"), "Attach to › Cut from Block")
	check(ed.parts().size() == 1 and str(block.get_meta("curve_solid")["op"]) == "difference", "Cyl attached to Block as a cut")
	# the step's menu: Role: Join, then Detach
	pm = ct.tree_menu({"step": ["b"], "of": block})
	check(_menu_pick(ct, pm, "Role: Join"), "Role: Join")
	check(str(block.get_meta("curve_solid")["op"]) == "union", "the step joins now")
	pm = ct.tree_menu({"step": ["b"], "of": block})
	check(_menu_pick(ct, pm, "Detach (a solid of its own)"), "Detach")
	check(ed.parts().size() == 2 and str(block.get_meta("curve_solid")["kind"]) == "extrude", "detached: two solids again")
	# a curve's menu: Attach to › Common with Block, then Detach from Block (the step goes)
	ct.add_curve(_circle(Vector3(0.2, 0, 0.2), 0.1))
	pm = ct.tree_menu({"curve": 2})
	check(_menu_pick(ct, pm, "Cut from Block"), "a loose edge: Attach to › Cut from Block")
	check(str(block.get_meta("curve_solid")["kind"]) == "bool", "the edge a cut step of Block")
	pm = ct.tree_menu({"curve": 2, "of": block, "leaf": ["b"]})
	check(_menu_pick(ct, pm, "Detach from Block"), "Detach from Block")
	check(str(block.get_meta("curve_solid")["kind"]) == "extrude", "its step gone with it")
	# delete a curve, delete a solid
	pm = ct.tree_menu({"curve": 2})
	_menu_pick(ct, pm, "Delete")
	check(ct.curves.size() == 2, "the edge deleted")
	pm = ct.tree_menu({"part": block})
	_menu_pick(ct, pm, "Delete")
	check(not block.is_inside_tree(), "the solid deleted")
	ed.undo()
	check(block.is_inside_tree(), "undo: back")
	await _done(ed)


## Types `text` into tree `t`'s open row editor (its own LineEdit) and presses Enter.
func _type_in(t: Tree, text: String) -> bool:
	var todo: Array = [t]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		if n is LineEdit and n.is_visible_in_tree():
			(n as LineEdit).text = text
			(n as LineEdit).text_submitted.emit(text)
			return true
		todo.append_array(n.get_children(true))
	return false


func test_parts_group_solids() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var a: MeshInstance3D = ct.make_part("extrude", 0.2)
	ct.add_curve(_circle(Vector3(2, 0, 0), 0.3))
	ct.select(1)
	var b: MeshInstance3D = ct.make_part("extrude", 0.4)
	# a part (group) of both
	var g: Node3D = ct.make_group([a, b])
	check(g != null and ct.is_group(g) and ct.group_parts(g).size() == 2, "a collection made of the two solids")
	check(ct.group_of(a) == g and ed.parts().size() == 2, "they're in it - still collections of the model")
	# the Mesh tab's list: the part a row, its solids under it
	var root: TreeItem = ed._parts.get_root()
	var top := root.get_children()
	check(top.size() == 1 and top[0].get_metadata(0) == g and top[0].get_child_count() == 2, "the Mesh tab lists the collection with its solids under it")
	# selecting the part's row selects its solids
	ed._parts.deselect_all()
	top[0].select(0)
	ed._sync_tree_selection()
	check(ed.selected_parts().size() == 2, "the collection's row selects both solids")
	# the curve overview: the part at the top, its solids under it
	ct._refresh_panel()
	var t: Tree = ct._w("tree")
	var first: TreeItem = t.get_root().get_child(0)
	check(first.get_metadata(0) is Dictionary and first.get_metadata(0).has("group") and first.get_child_count() == 2, "the overview: the collection first, its solids under it")
	# a new solid made with a solid of the part selected goes into the part
	ed.select_part(a)
	ct.add_curve(_circle(Vector3(0, 0, 2), 0.2))
	ct.select(2)
	var c: MeshInstance3D = ct.make_part("extrude", 0.3)
	check(ct.group_of(c) == g, "a new solid joins the selected solid's collection")
	# moving the part moves its solids - and their curves with them
	g.position += Vector3(0, 1, 0)
	var own: Dictionary = ct.owner_xfs()
	check(absf((own[int(ct.curves[0]["id"])] as Transform3D).origin.y - 1.0) < 1e-5, "the collection moved: its solids' edges with it")
	# G with the part's row selected: the part moves as one (its node), undone in one step
	ed._parts.deselect_all()
	ed._fill_parts()
	ed._parts.get_root().get_child(0).select(0)
	ed._sync_tree_selection()
	check(ed.xf_nodes() == [g], "all its solids selected: the transform moves the collection itself")
	var gy := g.global_position.y
	ed.begin_transform("G")
	ed._set_xfs(ed.xf, Transform3D(Basis(), Vector3(0, 0.5, 0)))
	ed.confirm_transform()
	check(absf(g.global_position.y - gy - 0.5) < 1e-5 and absf(a.position.y) < 1e-5, "moved the collection, its solids kept in it")
	ed.undo()
	check(absf(g.global_position.y - gy) < 1e-5, "undone in one step")
	# two loose-ish solids: one of the part only - it alone moves
	ed.select_part(a)
	check(ed.xf_nodes() == [a], "one solid of the collection selected: just it")
	# Rename: the menu's item opens the part's row for typing (its plain name); typed - renamed, one undo step
	ed._fill_parts()
	check(_menu_pick(ct, ct.parts_menu(g), "Rename"), "the collection's menu has Rename")
	var row: TreeItem = ed._parts.get_selected()
	check(row != null and row.get_metadata(0) == g and row.get_text(0) == str(g.name), "its row opened for typing, holding its name")
	check(_type_in(ed._parts, "Hull"), "typed into the row")
	check(str(g.name) == "Hull", "renamed")
	ed.undo()
	check(str(g.name) != "Hull", "the rename undone")
	ed.redo()
	# F2 in the overview: the selected solid's row (its plain name), typed there
	ct._refresh_panel()
	ed.select_part(a)
	ct.start_rename({"part": a})
	var orow: TreeItem = (ct._w("tree") as Tree).get_selected()
	check(orow != null and orow.get_metadata(0).get("part") == a and orow.get_text(0) == str(a.name), "the overview's row opened for typing")
	check(_type_in(ct._w("tree"), "Plate"), "typed into the overview's row")
	check(str(a.name) == "Plate", "a solid renamed in the overview")
	# menus: move out, ungroup, undo
	var pm: PopupMenu = ct.parts_menu(c)
	check(_menu_pick(ct, pm, "(no collection - the top)"), "Move to › out of the collection")
	check(ct.group_of(c) == null, "out")
	pm = ct.parts_menu(g)
	check(_menu_pick(ct, pm, "Ungroup"), "Ungroup")
	check(ct.groups().is_empty() and ed.parts().size() == 3, "the collection gone, its solids kept")
	ed.undo()
	check(ct.groups().size() == 1 and ct.group_parts(ct.groups()[0]).size() == 2, "undo: the collection back")
	# kept in the glb: its extras say it's a part
	check(bool(g.get_meta("extras", {}).get("atrapos_group", false)), "marked for the glb")
	await _done(ed)


func test_parts_saved_in_the_glb() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var a: MeshInstance3D = ct.make_part("extrude", 0.2)
	var g: Node3D = ct.make_group([a])
	g.name = "Hull"
	var MeshIO: GDScript = load("res://scripts/editor/mesh/mesh_io.gd")
	a.set_meta("extras", {"atrapos_curves": a.get_meta("curve_solid")})
	DirAccess.make_dir_recursive_absolute("user://test_parts")
	check(MeshIO.write(ed.model, "user://test_parts/m.glb") == OK, "written")
	var back: Node = MeshIO.read("user://test_parts/m.glb")
	check(back != null, "read back")
	if back:
		var found: Array = back.find_children("Hull", "Node3D", true, false)
		check(found.size() == 1 and ct.is_group(found[0]), "the collection comes back as a collection")
		if found.size() == 1:
			var ms: Array = found[0].find_children("*", "MeshInstance3D", true, false)
			check(ms.size() == 1, "with its solid in it")
			if ms.size() == 1:
				var ex = ms[0].get_meta("extras", {})
				check(ex is Dictionary and ex.has("atrapos_curves"), "the solid's recipe too")
		back.free()
	await _done(ed)


func test_bake_solid() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block 1 x 1 x 0.4 with a pocket in it (a circle cutting 0.2 deep from the bottom)...
	ct.add_curve(_rect(1.0, 1.0))
	ct.add_curve(_circle(Vector3(0.3, 0, 0.3), 0.15))
	ct.select(0)
	ct.select(1, true)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	var spec: Dictionary = block.get_meta("curve_solid")
	spec["roles"] = {str(int(ct.curves[1]["id"])): "cut", str(int(ct.curves[0]["id"])): "add"}
	spec["per"] = {str(int(ct.curves[1]["id"])): {"value": 0.2}}
	ed.select_part(block)
	ct.set_recipe(spec, "pocket")
	# ...a cylinder cut right through it, and a cutter far away (not touching it)
	ct.add_curve(_circle(Vector3(0.7, 0, 0.7), 0.1))
	ct.select(2)
	var cyl: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.cut_from(cyl, block)
	ct.add_curve(_circle(Vector3(5, 0, 5), 0.1))
	ct.select(3)
	var far: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.cut_from(far, block)
	var v0 := Shapes.volume(block.mesh)
	var n_parts: int = ed.parts().size()
	ed.select_part(block)
	# the right-click menus have it: the view's (Curve modeling tab), the overview's, the Mesh tab's list
	var in_view := false
	for g in ct.menu_groups():
		for it in g:
			if str(it[1]) == "Bake solid" and bool(it[5]):
				in_view = true
	check(in_view, "the view's right-click menu: Bake solid")
	var lm: PopupMenu = ct.parts_menu(block)
	var in_list := false
	for i in lm.item_count:
		if lm.get_item_text(i).begins_with("Bake") and not lm.is_item_disabled(i):
			in_list = true
	check(in_list, "the Mesh tab's list menu: Bake")
	check(ct.bake_solid(block), "baked")
	var baked: Dictionary = block.get_meta("curve_solid")
	check(str(baked.get("kind")) == "edges", "one solid, its curves its edges (%s)" % baked.get("kind"))
	check(str(block.name).begins_with("Baked"), "named a baked solid (%s)" % block.name)
	check(ed.parts().size() == n_parts, "the tool solids were steps - no collections left behind")
	check(absf(Shapes.volume(block.mesh) - v0) < 0.002, "the same solid (%.4f vs %.4f)" % [Shapes.volume(block.mesh), v0])
	# its edges: the block's 12 straight ones, the hole's rim top and bottom, the pocket's mouth and floor
	var kinds := {}
	for id in baked["ids"]:
		var c: Dictionary = ct.curve_by_id(int(id))
		kinds[c["kind"]] = int(kinds.get(c["kind"], 0)) + 1
	check(int(kinds.get("line", 0)) == 12 and int(kinds.get("circle", 0)) == 4 and kinds.size() == 2, "12 straight edges, 4 round ones (%s)" % [kinds])
	check(ct.curves.size() == 16, "only its edges - the old edges gone (%d)" % ct.curves.size())
	for id in baked["ids"]:
		check((ct.curve_by_id(int(id))["ctrl"] as PackedVector3Array).size() <= 2, "each edge a few vertices")
	ed.select_part(block)
	ct._refresh_panel()
	check(not (ct._w("solid_value_row") as Control).visible, "no extrusion settings: only its edges shape it")
	ct.update_ghosts()
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "no ghosts: one solid")
	# a corner of the top raised 0.2: the edges meeting there go with it, the mesh's corner rises, the
	# bottom stays
	var corner := Vector3(1, 0.4, 1)
	var moved := 0
	for id in baked["ids"]:
		var ci: int = ct._curve_index(int(id))
		var k: PackedVector3Array = ct.curves[ci]["ctrl"]
		for m in k.size():
			if k[m].distance_to(corner) < 1e-4 and moved == 0:
				k[m] = corner + Vector3(0, 0.2, 0)
				ct.curves[ci]["ctrl"] = k
				ct._move_corner(ci, corner, corner + Vector3(0, 0.2, 0))
				moved += 1
	check(moved == 1, "a top corner found on an edge")
	var at_corner := 0
	for id in baked["ids"]:
		for q in (ct.curve_by_id(int(id))["ctrl"] as PackedVector3Array):
			if q.distance_to(corner + Vector3(0, 0.2, 0)) < 1e-4:
				at_corner += 1
	check(at_corner == 3, "the three edges at that corner all moved with it (%d)" % at_corner)
	ct.refresh_solids()
	var top := -INF
	var bottom := INF
	for vtx in (block.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		top = maxf(top, (vtx as Vector3).y)
		bottom = minf(bottom, (vtx as Vector3).y)
	check(absf(top - 0.6) < 1e-3 and absf(bottom) < 1e-3, "the mesh's corner rose to 0.6, the bottom stayed (%.3f, %.3f)" % [top, bottom])
	check(Shapes.volume(block.mesh) > v0 + 0.01, "more solid under the raised corner")
	# undo: the solid and its curves as before the bake
	ed.undo()
	ed.undo()
	check(str(block.get_meta("curve_solid").get("kind")) == "bool", "undone: its recipe back")
	await _done(ed)


func test_bake_stacked_into_one() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a slab, and a smaller one stacked on it (only touching), joined to it
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var low: MeshInstance3D = ct.make_part("extrude", 0.2)
	var top := _circle(Vector3(0.5, 0.2, 0.5), 0.3)
	ct.add_curve(top)
	ct.select(1)
	var high: MeshInstance3D = ct.make_part("extrude", 0.3)
	ct.cut_from(high, low)
	ed.select_part(low)
	ct.set_node([], "op", "union")
	var v0 := Shapes.volume(low.mesh)
	check(ct.bake_solid(low), "baked")
	var spec: Dictionary = low.get_meta("curve_solid")
	check(str(spec.get("kind")) == "edges", "one solid, its curves its edges")
	check(absf(Shapes.volume(low.mesh) - v0) < 0.003, "the same solid (%.4f vs %.4f)" % [Shapes.volume(low.mesh), v0])
	await _done(ed)


func test_preview_in_game() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	ct.make_part("extrude", 0.4)
	# no game under Talos: nothing to preview in (the button off)
	check(ed.preview_in_game() == null, "no game: no preview")
	var pb: Button = ed._toolbar.get_node_or_null("PreviewInGame")
	check(pb != null, "the toolbar's Preview in game")
	# a stand-in game: a world, a camera, Talos's overlay over it
	var world := Node3D.new()
	ed.get_tree().root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = Vector3(10, 0, 0)
	cam.look_at(Vector3(10, 0, -10))
	var overlay := CanvasLayer.new()
	overlay.name = "TalosOverlay"
	ed.get_tree().root.add_child(overlay)
	var sky := CanvasLayer.new()   # (Talos's own layers - its starfield, its ground - inside the overlay)
	overlay.add_child(sky)
	var P: GDScript = load("res://scripts/editor/mesh/model_preview.gd")
	var p: Node = P.new()
	ed.get_tree().root.add_child(p)
	p._begin(ed, world, cam)
	var copy: Node3D = p.copy
	check(copy != null and copy.get_parent() == world and copy != ed.model, "a copy of the model set in the game world")
	check(ed.model.get_parent() != world and ed.parts().size() == 1, "the editor's model as it was")
	var to := copy.global_position - cam.global_position
	check(to.dot(-cam.global_basis.z) > 1.5 and absf(to.y) < 1.0, "in front of the camera (%s)" % to)
	check(not overlay.visible and overlay.process_mode == Node.PROCESS_MODE_DISABLED and not ed.get_tree().paused, "Talos hidden, the game running")
	check(not sky.visible, "its own layers hidden too (they'd cover the game)")
	var shown := copy.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.material_overlay != null)
	check(shown.is_empty(), "no selection outline on the copy")
	# F8 / Esc: back - the copy gone, Talos back
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	p._input(esc)
	await ed.get_tree().process_frame
	check(not is_instance_valid(copy) and not is_instance_valid(p), "the preview over: the copy gone")
	check(overlay.visible and overlay.process_mode != Node.PROCESS_MODE_DISABLED, "Talos back")
	check(sky.visible, "its layers back")
	ed.get_tree().paused = false
	overlay.queue_free()
	world.queue_free()
	await _done(ed)


func test_bake_takes_in_touching_solids() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block, a separate positive solid overlapping it (not a tool of it), and one far away
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var block: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(1.0, 0, 0.5), 0.3))
	ct.select(1)
	var knob: MeshInstance3D = ct.make_part("extrude", 0.6)
	ct.add_curve(_circle(Vector3(6, 0, 6), 0.3))
	ct.select(2)
	var far: MeshInstance3D = ct.make_part("extrude", 0.6)
	var v0 := Shapes.volume(block.mesh)
	var vk := Shapes.volume(knob.mesh)
	var overlap := 0.4 * PI * 0.09 * 0.5   # (half the knob's circle inside the block, 0.4 high)
	ed.select_part(block)
	check(ct.can_bake(block), "a plain solid with others around: Bake offered")
	check(ct.bake_solid(block), "baked")
	check(not knob.is_inside_tree() and far.is_inside_tree(), "the touching solid baked in (gone as a collection); the far one kept")
	check(ed.parts().size() == 2, "the baked solid and the far one")
	check(absf(Shapes.volume(block.mesh) - (v0 + vk - overlap)) < 0.01, "their union (%.4f vs %.4f)" % [Shapes.volume(block.mesh), v0 + vk - overlap])
	var spec: Dictionary = block.get_meta("curve_solid")
	check(str(spec.get("kind")) == "edges", "one baked solid: the block and the knob joined, its curves its edges")
	ed.undo()
	check(knob.is_inside_tree() and ed.parts().size() == 3, "undone: the knob a solid of its own again")
	await _done(ed)


func test_point_drag_free_and_baked_follows() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	ct.snap_grid = false
	# a point dragged along Y (the axis key while dragging): lifted off the plane - free in any axis
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	ct._drag = {"handle": [0, 2], "before": ct._state(), "x": Transform3D(), "own": {}, "moved": false,
		"press": ed.view.project(ed.model.global_transform * k[2]), "start": k[2], "axis": Vector3.UP}
	var up: Vector3 = ed.model.global_transform * (k[2] + Vector3(0, 0.3, 0))
	ct._drag_to(ed.view.project(up), false)
	ct._drag = {}
	var q: Vector3 = ct.curves[0]["ctrl"][2]
	check(absf(q.y - 0.3) < 0.02 and absf(q.x - 1.0) < 0.02, "the vertex went up along Y (%s)" % q)
	# a baked solid of it follows: its corner lifted 0.3 with the point
	var spec := {"kind": "baked", "ids": [int(ct.curves[0]["id"])], "value": 0.2, "segs": 30, "axis": -1}
	var m: ArrayMesh = ct.solid_of(spec)
	var hi := -INF
	for vtx in m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if (vtx as Vector3).distance_to(Vector3(1, (vtx as Vector3).y, 1)) < 1e-3:
			hi = maxf(hi, (vtx as Vector3).y)
	check(absf(hi - (q.y + 0.2)) < 0.02, "the baked solid's corner rose with the vertex (top %.3f)" % hi)
	await _done(ed)


func test_edges_matched_however_drawn() -> void:
	# a piece's top edge drawn from another corner and the other way round: its walls still run straight up
	var bot := _rect(1.0, 1.0)
	var top := _rect(1.0, 1.0)
	var k: PackedVector3Array = top["ctrl"]
	var r := PackedVector3Array()
	for i in [2, 1, 0, 3]:
		r.append(k[i] + Vector3(0, 0.5, 0))
	top["ctrl"] = r
	var m: ArrayMesh = CT.loft_piece([[bot, top]])
	check(m != null and absf(Shapes.volume(m) - 0.5) < 1e-3, "a straight block, not twisted (%.4f)" % (Shapes.volume(m) if m else -1.0))


func test_baked_mesh_follows_its_edges_smoothly() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a cylinder r 0.5, 1 high, baked: its faces - top, bottom (flat), its wall (a strip between the rims)
	ct.add_curve(_circle(Vector3.ZERO, 0.5))
	ct.select(0)
	var cyl: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(cyl)
	check(ct.bake_solid(cyl), "baked")
	var spec: Dictionary = cyl.get_meta("curve_solid")
	check(spec.has("mesh") and (spec["mesh"]["t"] as Array).size() / 3 > 200, "an even mesh of its own (%d triangles)" % ((spec["mesh"]["t"] as Array).size() / 3))
	# the top rim widened to r 0.75: the wall made again between the rims - a cone's frustum, smooth
	var top := {}
	for id in spec["ids"]:
		var c: Dictionary = ct.curve_by_id(int(id))
		if str(c["kind"]) == "circle" and (c["ctrl"][0] as Vector3).y > 0.5:
			top = c
	check(not top.is_empty(), "the top rim")
	var k: PackedVector3Array = top["ctrl"]
	k[1] = k[0] + (k[1] - k[0]) * 1.5
	top["ctrl"] = k
	ct.refresh_solids()
	var want := PI * 1.0 / 3.0 * (0.25 + 0.5 * 0.75 + 0.5625)
	check(absf(Shapes.volume(cyl.mesh) - want) < want * 0.04, "a frustum's volume (%.4f vs %.4f)" % [Shapes.volume(cyl.mesh), want])
	# smooth: neighbouring faces on the wall meet nearly flat (no folds)
	var a := (cyl.mesh as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var fn := {}
	for i in range(0, ix.size(), 3):
		var nn := (vs[ix[i + 2]] - vs[ix[i]]).cross(vs[ix[i + 1]] - vs[ix[i]]).normalized()
		for j in 3:
			var p0 := Vector3i((vs[ix[i + j]] * 1e4).round())
			var p1 := Vector3i((vs[ix[i + (j + 1) % 3]] * 1e4).round())
			var ek := str([p0, p1]) if str(p0) < str(p1) else str([p1, p0])
			if not fn.has(ek):
				fn[ek] = []
			fn[ek].append(nn)
	var folds := 0
	for ek in fn:
		var f: Array = fn[ek]
		if f.size() == 2:
			var d := rad_to_deg((f[0] as Vector3).angle_to(f[1]))
			if d > 25.0 and d < 60.0:
				folds += 1
	check(folds == 0, "no folds - every edge inside a face nearly flat (%d)" % folds)
	await _done(ed)


func test_curves_hidden_behind_solids() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))   # (under the block's top: on its bottom face)
	ed.view.set_view("top")
	ed.view.frame(AABB(Vector3(-0.5, -0.5, -0.5), Vector3(2, 2, 2)))
	await tree.process_frame
	ct._begin_occ(false)
	var mx: Transform3D = ct._mx()
	check(ct._hidden(mx * Vector3(0.7, 0, 0.5)), "an edge under the block's top is hidden from above")
	check(not ct._hidden(mx * Vector3(0.5, 0.4, 0.0)), "the top's own edge isn't hidden by the face it bounds")
	check(not ct._hidden(mx * Vector3(1.5, 0, 0.5)), "a vertex beside the block shows")
	ct._end_occ()
	# picking skips the hidden curve: a click over it picks nothing of it
	var i: int = ct.pick(ed.view.project(mx * Vector3(0.7, 0, 0.5)))
	check(i != 1, "the hidden circle isn't picked (%d)" % i)
	await _done(ed)


func test_double_click_inserts_point() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.add_curve(_circle(Vector3(3, 0, 0.5), 0.5))
	ed.view.set_view("top")
	ed.view.frame(AABB(Vector3(-0.5, -0.5, -0.5), Vector3(4.5, 1, 2)))
	await tree.process_frame
	var mx: Transform3D = ct._mx()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.position = ed.view.project(mx * Vector3(0.5, 0, 0))
	check(ct.view_input(ev), "the double-click was the edge tools'")
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(k.size() == 5 and k[1].distance_to(Vector3(0.5, 0, 0)) < 0.02, "a vertex put in between the first two (%s)" % k)
	ed.undo()
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() == 4, "undone")
	# a circle: a path through points on it, the same shape, the new point where clicked
	var before: PackedVector3Array = CT.sample(ct.curves[1])
	var on := Vector3(3, 0, 0.5) + Vector3(0.5, 0, 0).rotated(Vector3.UP, 1.0)
	check(ct.insert_point(ed.view.project(mx * on)), "a vertex put into the circle")
	var c: Dictionary = ct.curves[1]
	check(str(c["kind"]) == "path" and (c["ctrl"] as PackedVector3Array).size() == 9, "the circle as a path of 9 vertices (%s %d)" % [c["kind"], (c["ctrl"] as PackedVector3Array).size()])
	var worst := 0.0
	for q in CT.sample(c):
		worst = maxf(worst, absf(q.distance_to(Vector3(3, 0, 0.5)) - 0.5))
	check(worst < 0.003, "still the same circle (off by %.4f)" % worst)
	check(CT.sample(c)[0].distance_to(before[0]) < 1e-3, "starting where it did")
	await _done(ed)


func test_baked_side_edge_shapes_its_walls() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block 1 x 1 x 1, baked; a point put in the middle of one of its standing corner edges and pulled out
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	var spec: Dictionary = blk.get_meta("curve_solid")
	var side := -1
	for i in ct.curves.size():
		var k: PackedVector3Array = ct.curves[i]["ctrl"]
		if k.size() == 2 and absf(k[0].x - k[1].x) < 1e-4 and absf(k[0].z - k[1].z) < 1e-4 and k[0].distance_to(Vector3(1, k[0].y, 1)) < 1e-4:
			side = i
	check(side >= 0, "its corner edge at (1, 1) standing up")
	if side < 0:
		await _done(ed)
		return
	var c: Dictionary = ct.curves[side]
	var k: PackedVector3Array = c["ctrl"]
	k.insert(1, Vector3(1.3, 0.5, 1.3))   # (pulled out 0.3 each way at half height)
	c["ctrl"] = k
	ct.refresh_solids()
	# the mesh's points at half height near that corner went out with it; the walls bent smoothly
	var vs: PackedVector3Array = (blk.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var far := 0.0
	var mid_wall := 0.0
	for q in vs:
		if absf(q.y - 0.5) < 0.06:
			far = maxf(far, q.x + q.z)
			if absf(q.z - 0.5) < 0.06:
				mid_wall = maxf(mid_wall, q.x)   # (the x = 1 wall halfway along: bent part way)
	check(far > 2.5, "the corner went out with its edge (x + z %.3f, want 2.6)" % far)
	check(mid_wall > 1.03 and mid_wall < 1.2, "the wall beside it followed part way (x %.3f)" % mid_wall)
	check((spec.get("fv", []) as Array).size() > 0 and spec.get("tied", false), "its side rows made its edge's vertices")
	await _done(ed)


func test_point_smooth_or_sharp_menu() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	ed.view.set_view("top")
	ed.view.frame(AABB(Vector3(-0.5, -0.5, -0.5), Vector3(2, 1, 2)))
	await tree.process_frame
	var at: Vector2 = ct._screen(Vector3(1, 0, 0))
	var items: Array = ct.point_items(at)
	check(items.size() == 3 and str(items[2][1]) == "Manual vertex" and bool(items[2][5]) and str(items[0][1]) == "Smooth vertex" and bool(items[0][5]) and not bool(items[1][5]), "a line's corner: Smooth and Manual on offer, Sharp not (%s)" % [items.map(func(x): return [x[1], x[5]])])
	var groups: Array = ct.menu_groups(at)
	check(str(groups[0][0][1]) == "Smooth vertex", "first in the right-click menu")
	(items[0][4] as Callable).call()
	var c: Dictionary = ct.curves[0]
	check(str(c["kind"]) == "path" and (c["sharp"] as PackedByteArray) == PackedByteArray([1, 0, 1, 1]), "a path now, that vertex smooth (%s %s)" % [c["kind"], c.get("sharp")])
	var s := CT.sample(c)
	var bent := false
	for q in s:
		if q.x > 1.02:
			bent = true   # (the side round the smooth point bulges past the old corner's line)
	check(bent and s.size() > 8, "curved through it (%d vertices)" % s.size())
	(ct.point_items(at)[1][4] as Callable).call()
	check((ct.curves[0]["sharp"] as PackedByteArray)[1] == 1, "sharp again")
	check(CT.sample(ct.curves[0]).size() == 4, "straight sides again")
	ed.undo()
	ed.undo()
	check(str(ct.curves[0]["kind"]) == "line", "undone to the line")
	check(ct.point_items(Vector2(-500, -500)).is_empty(), "nothing away from a vertex")
	await _done(ed)


func test_double_click_dissolves_point() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	ed.view.set_view("top")
	ed.view.frame(AABB(Vector3(-0.5, -0.5, -0.5), Vector3(2, 1, 2)))
	await tree.process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.position = ct._screen(Vector3(1, 0, 0))
	check(ct.view_input(ev), "the double-click on the vertex was the edge tools'")
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(k.size() == 3 and not Vector3(1, 0, 0) in k, "that corner gone - a triangle (%s)" % k)
	ev.position = ct._screen(Vector3(1, 0, 1))
	ct.view_input(ev)
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() == 3, "a closed edge keeps three vertices")
	ct._drag = {}
	ed.undo()
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() == 4, "undone (%s, %s)" % [ct.curves[0]["ctrl"], ed._undo.map(func(e): return e.get("name") if e is Dictionary else str(e))])
	# an arc's middle point: a straight line between its ends
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(3, 0, 0), Vector3(3.5, 0, 0.5), Vector3(4, 0, 0)]), "closed": false, "n": Vector3.UP})
	check(ct.dissolve_point(1, 1) and str(ct.curves[1]["kind"]) == "line", "the arc made a line")
	await _done(ed)


func test_baked_recess_side_edge_stays_in_its_walls() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block 1 x 1 x 1 with a recess cut in its x = 1 side, from the bottom to half way up
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(0.8, 0, 0.3), Vector3(1.2, 0, 0.3), Vector3(1.2, 0, 0.7), Vector3(0.8, 0, 0.7)]), "closed": true, "n": Vector3.UP})
	ct.select(1)
	var cut: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.cut_from(cut, blk)
	ed.select_part(blk)
	var v_before := Shapes.volume(blk.mesh)
	check(ct.bake_solid(blk), "baked")
	check(absf(Shapes.volume(blk.mesh) - v_before) < 1e-3, "the same solid - the recess kept (%.4f vs %.4f)" % [Shapes.volume(blk.mesh), v_before])
	var spec: Dictionary = blk.get_meta("curve_solid")
	# the recess's side edge on the block's face: x = 1, z = 0.3, from y 0 to 0.5
	var side := -1
	for i in ct.curves.size():
		var k: PackedVector3Array = ct.curves[i]["ctrl"]
		if k.size() == 2 and k[0].distance_to(Vector3(1, k[0].y, 0.3)) < 1e-3 and k[1].distance_to(Vector3(1, k[1].y, 0.3)) < 1e-3 and absf(k[0].y - k[1].y) > 0.4:
			side = i
	check(side >= 0, "the recess's side edge")
	if side < 0:
		await _done(ed)
		return
	var a := (blk.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var k: PackedVector3Array = ct.curves[side]["ctrl"]
	ct.curves[side]["ctrl"] = PackedVector3Array([k[0], Vector3(1.1, 0.25, 0.3), k[1]])   # (a point put in its middle, pulled out - its own way round kept)
	ct.refresh_solids()
	var b := (blk.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	# above the recess (y > 0.55) nothing moved; the edge's middle went out with it
	var worst := 0.0
	var out := 0.0
	for q in b:
		if q.y > 0.55:
			var near := INF
			for p in a:
				near = minf(near, p.distance_to(q))
			worst = maxf(worst, near)
		if absf(q.y - 0.25) < 0.04 and absf(q.z - 0.3) < 0.02:
			out = maxf(out, q.x)
	check(worst < 5e-3, "the wall above the recess stays put - a few mm at most, the bend fading past its corner (moved %.4f)" % worst)
	var ci := -1
	for j in spec["chains"].size():
		if int(spec["chains"][j]["id"]) == int(ct.curves[side]["id"]):
			ci = j
	var n_on := 0
	for e in spec.get("fv", []):
		if int(e[1]) == ci:
			n_on += 1
	check(out > 1.08, "the edge's middle went out (x %.3f; %d vertices on it)" % [out, n_on])
	# closed all over: every edge of its mesh has a face either side (no cracks between walls)
	var tt: Array = spec["mesh"]["t"]
	var ecount := {}
	for ti in range(0, tt.size(), 3):
		for j in 3:
			var x: int = tt[ti + j]
			var y: int = tt[ti + (j + 1) % 3]
			var ek := "%d,%d" % [mini(x, y), maxi(x, y)]
			ecount[ek] = int(ecount.get(ek, 0)) + 1
	var open_n := 0
	for ek in ecount:
		if int(ecount[ek]) == 1:
			open_n += 1
	check(open_n == 0, "its mesh closed - no open edges (%d)" % open_n)
	await _done(ed)


func test_point_drag_smart_axis() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	ct.snap_grid = false
	ed.view.yaw = deg_to_rad(-30.0)
	ed.view.pitch = deg_to_rad(-25.0)
	ed.view.frame(AABB(Vector3(-0.5, -0.5, -0.5), Vector3(2, 1, 2)))
	await tree.process_frame
	var mx: Transform3D = ed.model.global_transform
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	var press: Vector2 = ed.view.project(mx * k[2]) + Vector2(4, 3)   # (pressed a little off the point)
	ct._drag = {"handle": [0, 2], "before": ct._state(), "x": Transform3D(), "own": {}, "press": press, "start": k[2], "moved": false}
	# a couple of pixels: nothing moves (no jump to under the mouse)
	ct._drag_to(press + Vector2(2, 1), false)
	check((ct.curves[0]["ctrl"][2] as Vector3).is_equal_approx(Vector3(1, 0, 1)), "still for the first pixels")
	# dragged straight up the screen: along Y, and only Y
	var up_dir: Vector2 = ct._axis_on_screen(k[2], 1).normalized()
	ct._drag_to(press + up_dir * 80.0, false)
	var q: Vector3 = ct.curves[0]["ctrl"][2]
	check(ct._drag.get("axis") == Vector3.UP, "Y picked from the drag's direction (%s)" % [ct._drag.get("axis")])
	check(absf(q.x - 1.0) < 1e-5 and absf(q.z - 1.0) < 1e-5 and q.y > 0.05, "moved along Y only (%s)" % q)
	# X while dragging: along X now, from where it started
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.pressed = true
	ct.key(ev)
	ct._drag_to(press + ct._axis_on_screen(k[2], 0).normalized() * 60.0, false)
	q = ct.curves[0]["ctrl"][2]
	check(absf(q.y) < 1e-5 and absf(q.z - 1.0) < 1e-5 and q.x > 1.05, "then along X only (%s)" % q)
	# smooth - no snapping, even with the grid on; Ctrl: whole grid steps from where it started
	ct.snap_grid = true
	ct._drag_to(press + ct._axis_on_screen(k[2], 0).normalized() * 61.0, false)
	q = ct.curves[0]["ctrl"][2]
	var steps: float = (q.x - 1.0) / ct.grid_step
	check(absf(steps - roundf(steps)) > 1e-3, "smooth, not on a grid step (%.4f)" % q.x)
	ct._drag_to(press + ct._axis_on_screen(k[2], 0).normalized() * 61.0, true)
	q = ct.curves[0]["ctrl"][2]
	steps = (q.x - 1.0) / ct.grid_step
	check(absf(steps - roundf(steps)) < 1e-4, "Ctrl: grid steps from the start (%.4f)" % q.x)
	ct._drag = {}
	await _done(ed)


func test_point_drag_guides() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(2, 0.3, 0), Vector3(2, 0.3, 1)]), "closed": false, "n": Vector3.UP})
	ct.add_curve(_rect(0.5, 0.5))
	ct.curves[2]["ctrl"] = PackedVector3Array([Vector3(3, 0, 0), Vector3(3.5, 0, 0), Vector3(3.5, 0, 0.5), Vector3(3, 0, 0.5)])
	ct.select(2)
	ct.make_part("extrude", 0.5)   # (a block: its top a flat face at y 0.5)
	ct.select(0)
	ed.view.yaw = deg_to_rad(-30.0)
	ed.view.pitch = deg_to_rad(-20.0)
	ed.view.frame(AABB(Vector3(-0.5, -0.5, -0.5), Vector3(4.5, 1.5, 2)))
	await tree.process_frame
	var mx: Transform3D = ed.model.global_transform
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	var press: Vector2 = ed.view.project(mx * k[2])
	ct._drag = {"handle": [0, 2], "before": ct._state(), "x": Transform3D(), "own": {}, "press": press, "start": k[2], "moved": false, "axis": Vector3.UP}
	# near the other line's height (0.3): snapped onto it, its guide shown
	ct._drag_to(ed.view.project(mx * Vector3(1, 0.297, 1)), false)
	var q: Vector3 = ct.curves[0]["ctrl"][2]
	check(absf(q.y - 0.3) < 1e-6, "snapped to the other vertex's height (%.4f)" % q.y)
	var gs: Array = ct._drag.get("guides", [])
	check(gs.size() == 1 and str(gs[0]["kind"]) == "point", "a guide from that vertex (%s)" % [gs.map(func(g): return g["kind"])])
	# well away from any level: smooth, no guide
	ct._drag_to(ed.view.project(mx * Vector3(1, 0.4, 1)), false)
	q = ct.curves[0]["ctrl"][2]
	check(absf(q.y - 0.4) < 0.01, "free between (%.4f)" % q.y)
	check((ct._drag.get("guides", []) as Array).is_empty(), "no guide there")
	# near the block's top (y 0.5): level with that flat face
	ct._drag_to(ed.view.project(mx * Vector3(1, 0.497, 1)), false)
	q = ct.curves[0]["ctrl"][2]
	check(absf(q.y - 0.5) < 1e-6, "level with the flat face (%.4f)" % q.y)
	gs = ct._drag.get("guides", [])
	check(gs.size() == 1 and str(gs[0]["kind"]) == "face", "a face guide")
	# Guides off: smooth there too
	ct.set_meta("guides_off", true)
	ct._drag_to(ed.view.project(mx * Vector3(1, 0.497, 1)), false)
	q = ct.curves[0]["ctrl"][2]
	check(absf(q.y - 0.5) > 1e-4, "guides off: not snapped (%.4f)" % q.y)
	ct.remove_meta("guides_off")
	ct._drag = {}
	await _done(ed)


func test_baked_flat_face_follows_without_folding() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block 1 x 1 x 0.4 with a round notch cut in its side; baked; the notch's top arc pushed well out
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.add_curve(_circle(Vector3(1.0, 0, 0.5), 0.3))
	ct.select(1)
	var cut: MeshInstance3D = ct.make_part("extrude", 0.4)
	ct.cut_from(cut, blk)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	var spec: Dictionary = blk.get_meta("curve_solid")
	var top := -1
	for i in ct.curves.size():
		var c: Dictionary = ct.curves[i]
		if str(c["kind"]) == "arc" and absf((c["ctrl"][0] as Vector3).y - 0.4) < 1e-3:
			top = i
	check(top >= 0, "the notch's top arc")
	if top < 0:
		await _done(ed)
		return
	# the top face has points inside it now (not just its edges')
	var tv: Array = spec["mesh"]["v"]
	var inner := 0
	for j in range(0, tv.size(), 3):
		if absf(tv[j + 1] - 0.4) < 1e-4 and tv[j] > 0.1 and tv[j] < 0.6 and tv[j + 2] > 0.2 and tv[j + 2] < 0.8:
			inner += 1
	check(inner > 5, "vertices inside the top face (%d)" % inner)
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[top]["ctrl"]
	k[1] = Vector3(0.55, 0.4, 0.5)   # (the arc's middle pushed 0.15 into the block)
	ct.curves[top]["ctrl"] = k
	ct.refresh_solids()
	ct._changed("Move edge vertex", before)   # (let go: settled, folds untangled)
	# no triangle of the top face turned over
	var a := (blk.mesh as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var flipped := 0
	var on_top := 0
	var area_all := 0.0
	var area_bad := 0.0
	for i in range(0, ix.size(), 3):
		var p0 := vs[ix[i]]
		var p1 := vs[ix[i + 1]]
		var p2 := vs[ix[i + 2]]
		if absf(p0.y - 0.4) < 1e-3 and absf(p1.y - 0.4) < 1e-3 and absf(p2.y - 0.4) < 1e-3:
			on_top += 1
			var cr := (p2 - p0).cross(p1 - p0)
			area_all += cr.length() * 0.5
			if cr.y < -1e-9:
				flipped += 1
				area_bad += cr.length() * 0.5
	# (an edge pushed this far: at most a few specks - slivers along the rim where it curves in)
	check(on_top > 10 and area_bad < area_all * 0.015, "the top face faces up - turned over: %d of %d, %.3f%% of it" % [flipped, on_top, area_bad / maxf(area_all, 1e-9) * 100.0])
	# quads: most of it in pairs of triangles making squares-ish quads (its columns and rows)
	check(on_top < 1200, "a lean grid, not a fan of slivers (%d)" % on_top)
	await _done(ed)


func test_edit_settles_baked_mesh_and_wireframe() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a cylinder baked; its top rim widened as one edit (the way a drag ends): the mesh settles
	ct.add_curve(_circle(Vector3.ZERO, 0.5))
	ct.select(0)
	var cyl: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(cyl)
	check(ct.bake_solid(cyl), "baked")
	var spec0: Dictionary = (cyl.get_meta("curve_solid") as Dictionary).duplicate(true)
	var n0: int = (spec0["mesh"]["t"] as Array).size() / 3
	var top := -1
	for i in ct.curves.size():
		if str(ct.curves[i]["kind"]) == "circle" and (ct.curves[i]["ctrl"][0] as Vector3).y > 0.5:
			top = i
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[top]["ctrl"]
	k[1] = k[0] + (k[1] - k[0]) * 2.0   # (a cone's flare: the wall bends a lot - finer there)
	ct.curves[top]["ctrl"] = k
	ct.refresh_solids()
	ct._changed("Move edge vertex", before)
	var spec: Dictionary = cyl.get_meta("curve_solid")
	var n1: int = (spec["mesh"]["t"] as Array).size() / 3
	check(JSON.stringify(spec["c0"][str(int(ct.curves[top]["id"]))]) == JSON.stringify(ct.to_json([ct.curves[top]])[0]), "settled: its edges now its start")
	# closed, and the same shape (a frustum r 0.5 -> 1.0, 1 high)
	var tt: Array = spec["mesh"]["t"]
	var ecount := {}
	for ti in range(0, tt.size(), 3):
		for j in 3:
			var x: int = tt[ti + j]
			var y: int = tt[ti + (j + 1) % 3]
			var ek := "%d,%d" % [mini(x, y), maxi(x, y)]
			ecount[ek] = int(ecount.get(ek, 0)) + 1
	var open_n := 0
	for ek in ecount:
		if int(ecount[ek]) == 1:
			open_n += 1
	check(open_n == 0, "closed after settling (%d open)" % open_n)
	var want := PI / 3.0 * (0.25 + 0.5 + 1.0)
	check(absf(Shapes.volume(cyl.mesh) - want) < want * 0.05, "the frustum's volume (%.4f vs %.4f)" % [Shapes.volume(cyl.mesh), want])
	check(n1 >= n0, "as fine or finer (%d -> %d triangles)" % [n0, n1])
	# every triangle facing out (the wall away from the axis, the caps up and down): none inside out
	var am := (cyl.mesh as ArrayMesh).surface_get_arrays(0)
	var mvs: PackedVector3Array = am[Mesh.ARRAY_VERTEX]
	var mix: PackedInt32Array = am[Mesh.ARRAY_INDEX]
	var a_all := 0.0
	var a_in := 0.0
	for i in range(0, mix.size(), 3):
		var q0 := mvs[mix[i]]
		var q1 := mvs[mix[i + 1]]
		var q2 := mvs[mix[i + 2]]
		var nn := (q2 - q0).cross(q1 - q0)
		var cen := (q0 + q1 + q2) / 3.0
		var out := Vector3(cen.x, 0, cen.z)
		if absf(cen.y - 1.0) < 1e-3:
			out = Vector3.UP
		elif absf(cen.y) < 1e-3:
			out = Vector3.DOWN
		a_all += nn.length()
		if nn.dot(out) < 0.0:
			a_in += nn.length()
	check(a_in < a_all * 0.005, "facing out (inside out: %.3f%%)" % (a_in / maxf(a_all, 1e-9) * 100.0))
	# quads: most triangles paired across their longest side into a quad (lying nearly flat together)
	var st: Array = spec["mesh"]["t"]
	var smv: Array = spec["mesh"]["v"]
	var sv := PackedVector3Array()
	for i in range(0, smv.size(), 3):
		sv.append(Vector3(smv[i], smv[i + 1], smv[i + 2]))
	var e_t := {}
	var t_long := []
	var t_n := []
	for i in range(0, st.size(), 3):
		var tr := [int(st[i]), int(st[i + 1]), int(st[i + 2])]
		t_n.append((sv[tr[2]] - sv[tr[0]]).cross(sv[tr[1]] - sv[tr[0]]).normalized())
		var lk := ""
		var ll := -1.0
		for j in 3:
			var ek := "%d,%d" % [mini(tr[j], tr[(j + 1) % 3]), maxi(tr[j], tr[(j + 1) % 3])]
			if not e_t.has(ek):
				e_t[ek] = []
			e_t[ek].append(i / 3)
			var l := sv[tr[j]].distance_to(sv[tr[(j + 1) % 3]])
			if l > ll:
				ll = l
				lk = ek
		t_long.append(lk)
	var in_quads := 0
	for ek in e_t:
		var ts: Array = e_t[ek]
		if ts.size() == 2 and t_long[ts[0]] == ek and t_long[ts[1]] == ek and (t_n[ts[0]] as Vector3).dot(t_n[ts[1]]) > 0.85:
			in_quads += 2
	check(in_quads >= (st.size() / 3) * 0.8, "quads: %d of %d triangles in quads" % [in_quads, st.size() / 3])
	# undo: the mesh as it was
	ed.undo()
	var back: Dictionary = cyl.get_meta("curve_solid")
	check((back["mesh"]["t"] as Array).size() / 3 == n0, "undo: the mesh as it was")
	# the wireframe: on, drawn over the part, its quads' diagonals left out
	ed.toggle_wire()
	ed.update_wire()
	var wm: MeshInstance3D = ed.get_meta("wire_mi")
	var lines: int = (wm.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 2 if (wm.mesh as ArrayMesh).get_surface_count() > 0 else 0
	var tris: int = (cyl.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	check(wm.visible and lines > 0 and lines < tris * 1.4, "a wireframe of quads (%d lines for %d triangles)" % [lines, tris])
	ed.toggle_wire()
	check(not wm.visible, "off again")
	await _done(ed)


func test_settle_rebuilds_stretched_walls() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.5)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	# a top corner pulled 0.6 out (on every edge that has it): the two walls at it stretched at the top
	var before: Array = ct._state()
	var hit := 0
	for i in ct.curves.size():
		var k: PackedVector3Array = ct.curves[i]["ctrl"]
		var ch := false
		for j in k.size():
			if k[j].distance_to(Vector3(1, 0.5, 1)) < 1e-3:
				k[j] = Vector3(1.6, 0.5, 1.6)
				ch = true
		if ch:
			ct.curves[i]["ctrl"] = k
			hit += 1
	check(hit >= 2, "the corner on its edges (%d)" % hit)
	ct.refresh_solids()
	ct._changed("Move edge vertex", before)
	var spec: Dictionary = blk.get_meta("curve_solid")
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	check(EN._open_edges(PackedInt32Array(spec["mesh"]["t"])) == 0, "closed after settling")
	# the stretched wall's columns: none much longer than the wall is tall (no fanning)
	var mv: Array = spec["mesh"]["v"]
	var t: Array = spec["mesh"]["t"]
	var worst := 0.0
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := int(t[i + j])
			var b := int(t[i + (j + 1) % 3])
			var pa := Vector3(mv[a * 3], mv[a * 3 + 1], mv[a * 3 + 2])
			var pb := Vector3(mv[b * 3], mv[b * 3 + 1], mv[b * 3 + 2])
			if absf(pa.y - pb.y) > 0.4:   # (bottom to top)
				worst = maxf(worst, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	check(worst < 0.75, "columns run across the walls, not fanned (longest lean %.3f)" % worst)
	await _done(ed)


func test_cut_into_baked_solid_follows_its_curve() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.5)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	# a new circle extruded and cut from the baked solid: a live boolean, its baked side kept
	var ci: int = ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))
	ct.select(ct.curves.size() - 1)
	var cyl: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.cut_from(cyl, blk)
	var spec: Dictionary = blk.get_meta("curve_solid")
	check(str(spec.get("kind", "")) == "bool" and str(spec["a"].get("kind", "")) == "edges", "a live cut in the baked solid (%s)" % spec.get("kind"))
	var v0 := Shapes.volume(blk.mesh)
	# the circle moved: the hole moves with it - and grown: the solid loses more
	var c: Dictionary = ct.curves[ct.curves.size() - 1]
	var k: PackedVector3Array = c["ctrl"]
	k[1] = k[0] + (k[1] - k[0]) * 1.5
	c["ctrl"] = k
	ct.refresh_solids()
	var v1 := Shapes.volume(blk.mesh)
	check(v1 < v0 - 0.02, "the cut grew with its circle (%.4f -> %.4f)" % [v0, v1])
	await _done(ed)


func test_view_turns_round_the_selection() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.add_curve(_circle(Vector3(3, 0, 0), 0.2))
	var mx: Transform3D = ed.model.global_transform
	# a solid selected (no curve): round its middle
	ct.select(-1)
	ed.select_part(blk)
	ed._drag_started += 1
	var pv: Vector3 = ed._orbit_pivot()
	check(pv.distance_to(blk.global_transform * blk.mesh.get_aabb().get_center()) < 1e-3, "a solid: round its middle (%s)" % pv)
	# a curve picked: round the curve (smaller than the solid)
	ct.select(1)
	ed._drag_started += 1
	pv = ed._orbit_pivot()
	check(pv.distance_to(mx * Vector3(3, 0, 0)) < 1e-3, "an edge: round its middle (%s)" % pv)
	# a point of it pressed: round that point
	ct.set_meta("last_handle", [1, 1])
	ed._drag_started += 1
	pv = ed._orbit_pivot()
	check(pv.distance_to(mx * Vector3(3.2, 0, 0)) < 1e-3, "a vertex: round it (%s)" % pv)
	await _done(ed)


func test_bake_makes_lean_joined_curves() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block, baked; a round cut through its corner; baked again (creases of curved walls, junctions)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.5)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	ct.add_curve(_circle(Vector3(1.0, 0, 1.0), 0.3))
	ct.select(ct.curves.size() - 1)
	var cyl: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.cut_from(cyl, blk)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked again")
	var spec: Dictionary = blk.get_meta("curve_solid")
	var cs := []
	for id in spec["ids"]:
		cs.append(ct.curve_by_id(int(id)))
	var samples := []
	for c in cs:
		samples.append(CT.sample(c))
	var loose := 0
	var pairs := 0
	for i in cs.size():
		if cs[i].get("closed", false):
			continue
		var s: PackedVector3Array = samples[i]
		for q in [s[0], s[s.size() - 1]]:
			var ends := 0
			var through := 0
			for j in cs.size():
				if j == i:
					continue
				var k: PackedVector3Array = cs[j]["ctrl"]
				var hit := false
				for p in k:
					if p.distance_to(q) < 1e-4:
						hit = true
				if hit and not cs[j].get("closed", false) and (k[0].distance_to(q) < 1e-4 or k[k.size() - 1].distance_to(q) < 1e-4):
					ends += 1
				elif hit:
					through += 1
			if ends == 0 and through == 0:
				loose += 1
			elif ends == 1 and through == 0:
				pairs += 1
	check(loose == 0, "every edge's ends meet other edges (%d loose)" % loose)
	check(pairs == 0, "no two edges that are one edge (%d ends meeting only one other)" % pairs)
	var most := 0
	for c in cs:
		most = maxi(most, (c["ctrl"] as PackedVector3Array).size())
	check(cs.size() <= 24 and most <= 16, "lean: %d edges, the most vertices on one %d" % [cs.size(), most])
	await _done(ed)


func test_far_pull_keeps_edge_points_in_their_spans() -> void:
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	# an edge of three stretches (a rim, down a side, along the bottom - one curve, corners sharp); its
	# middle stretch pulled far out: the points on the other stretches stay where they were (they
	# don't slide along it past its corners), the ones on the pulled stretch go with it
	var k0 := PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var c0 := {"kind": "path", "ctrl": k0, "sharp": PackedByteArray([0, 1, 1, 0]), "closed": false}
	var k1 := k0.duplicate()
	k1[1] = Vector3(1, 1, 3)
	k1[2] = Vector3(1, 0, 3)
	var c1 := {"kind": "path", "ctrl": k1, "sharp": PackedByteArray([0, 1, 1, 0]), "closed": false}
	var v := PackedVector3Array([EN.at(c0, 1.0 / 6.0), EN.at(c0, 0.5), EN.at(c0, 5.0 / 6.0)])
	var fv := [[0, 0, 1.0 / 6.0], [1, 0, 0.5], [2, 0, 5.0 / 6.0]]
	var chains := [{"id": 7}]
	var mv: Dictionary = EN.edge_moves(fv, chains, {7: c0}, {7: c1}, v)
	# (the first and last stretches turned about their fixed ends - their points' moves well under the pull)
	var p0: Vector3 = v[0] + mv[0]
	var p2: Vector3 = v[2] + mv[2]
	check(p0.distance_to(Vector3(0, 1, 0).lerp(Vector3(1, 1, 3), 0.5)) < 1e-3, "the rim's vertex halfway along its stretch (%s)" % p0)
	check(p2.distance_to(Vector3(1, 0, 3).lerp(Vector3(2, 0, 0), 0.5)) < 1e-3, "the bottom's vertex halfway along its stretch (%s)" % p2)
	check((v[1] + mv[1]).distance_to(Vector3(1, 0.5, 3)) < 1e-3, "the side's vertex halfway down it (%s)" % (v[1] + mv[1]))
	# a different number of points: as a whole (no map)
	var c2 := c1.duplicate()
	c2["ctrl"] = PackedVector3Array([k1[0], k1[1], k1[3]])
	check((EN.span_map(c0, c2) as Array).is_empty(), "vertices added or taken: the plain fraction")
	# merges and turns in tidying never pinch the mesh (an edge with three triangles) or fold a face:
	# a strip of quads with one point pulled across its neighbours, tidied with fairing
	var sv := PackedVector3Array()
	for j in 3:
		for i in 6:
			sv.append(Vector3(i * 0.2, 0, j * 0.2))
	var st := PackedInt32Array()
	for j in 2:
		for i in 5:
			var a := j * 6 + i
			st.append_array(PackedInt32Array([a, a + 6, a + 1, a + 1, a + 6, a + 7]))
	sv[8] = Vector3(0.75, 0, 0.21)   # (an inner point pushed past its neighbour)
	var sfv := []
	for i in 6:
		sfv.append([i, 0, i / 5.0])
		sfv.append([12 + i, 1, i / 5.0])
	var td: Dictionary = EN.tidy_mesh(sv, st, sfv, [{"id": 1}, {"id": 2}], {}, 0.02, {0: true}, 20)
	check(EN._crowded_edges(_tri_rows(td["t"])) == 0, "no edge with three triangles")
	var tv: PackedVector3Array = td["v"]
	var tt: PackedInt32Array = td["t"]
	var down := 0
	for i in range(0, tt.size(), 3):
		if (tv[tt[i + 2]] - tv[tt[i]]).cross(tv[tt[i + 1]] - tv[tt[i]]).y > 0.0:
			down += 1   # (they face -y, the way the strip was made)
	check(down == 0, "every triangle facing the same way (%d turned over)" % down)


func _tri_rows(t: PackedInt32Array) -> Array:
	var out := []
	for i in range(0, t.size(), 3):
		out.append([t[i], t[i + 1], t[i + 2]])
	return out


func _block_with_side_point(ed: Control) -> Array:
	# a block 1 x 1 x 1 baked; its standing corner edge at (1, 1) given a point halfway up (on it)
	var ct = ed.curve_tools
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	var side := -1
	for i in ct.curves.size():
		var k: PackedVector3Array = ct.curves[i]["ctrl"]
		if k.size() == 2 and absf(k[0].x - k[1].x) < 1e-4 and absf(k[0].z - k[1].z) < 1e-4 and k[0].distance_to(Vector3(1, k[0].y, 1)) < 1e-4:
			side = i
	if side < 0:
		return [blk, -1]
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[side]["ctrl"]
	k.insert(1, (k[0] + k[1]) * 0.5)
	ct.curves[side]["ctrl"] = k
	ct._changed("Insert edge vertex", before)
	ct._rebase_holding([int(ct.curves[side]["id"])])
	return [blk, side]


static func _mesh_pts(p: MeshInstance3D) -> PackedVector3Array:
	var spec: Dictionary = p.get_meta("curve_solid")
	var mv: Array = spec["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, mv.size(), 3):
		v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
	return v


func test_points_pick_separate_merge() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var r := _block_with_side_point(ed)
	var blk: MeshInstance3D = r[0]
	var side: int = r[1]
	check(side >= 0, "its standing corner edge")
	if side < 0:
		await _done(ed)
		return
	# picking: a click picks one point, Shift adds - the picked ones shown and listed
	ct.select(side)
	ct.pick_point(side, 1)
	check(ct.picked_points() == [[side, 1]], "one vertex picked")
	ct.pick_point(side, 0, true)
	check(ct.picked_points().size() == 2, "Shift: two")
	ct.pick_point(side, 0, true)
	check(ct.picked_points() == [[side, 1]], "Shift again: left out")
	# separate at the middle point: two curves, the mesh as it was, the solid's edge split with them
	var n0: int = ct.curves.size()
	var spec0: Dictionary = (blk.get_meta("curve_solid") as Dictionary).duplicate(true)
	var v0 := _mesh_pts(blk)
	check(ct.separate_points(), "separated")
	check(ct.curves.size() == n0 + 1, "one more edge (%d -> %d)" % [n0, ct.curves.size()])
	var spec1: Dictionary = blk.get_meta("curve_solid")
	check((spec1["chains"] as Array).size() == (spec0["chains"] as Array).size() + 1, "the solid's edge split too")
	check(_mesh_pts(blk) == v0, "its mesh as it was")
	var top := -1
	var bot := -1
	for i in ct.curves.size():
		var k: PackedVector3Array = ct.curves[i]["ctrl"]
		if k.size() == 2 and k[0].distance_to(Vector3(1, 0.5, 1)) < 1e-4:
			top = i
		if k.size() == 2 and k[1].distance_to(Vector3(1, 0.5, 1)) < 1e-4:
			bot = i
	check(top >= 0 and bot >= 0, "the two pieces meet halfway up")
	if top < 0 or bot < 0:
		await _done(ed)
		return
	# each piece still shapes the solid: their shared point pulled out, the mesh follows
	var before: Array = ct._state()
	var kt: PackedVector3Array = ct.curves[top]["ctrl"]
	var was := kt[0]
	kt[0] = Vector3(1.3, 0.5, 1.3)
	ct.curves[top]["ctrl"] = kt
	ct._move_corner(top, was, kt[0])
	ct._changed("Move edge vertex", before)
	var far := 0.0
	for q in _mesh_pts(blk):
		if absf(q.y - 0.5) < 0.06:
			far = maxf(far, q.x + q.z)
	check(far > 2.5, "pulled out with its edges (x + z %.3f)" % far)
	ed.undo()
	# merge: the two pieces' meeting ends picked - one curve again, the mesh as it is
	ct.select(-1)
	for i in ct.curves.size():
		var k: PackedVector3Array = ct.curves[i]["ctrl"]
		if k.size() == 2 and k[0].distance_to(Vector3(1, 0.5, 1)) < 1e-4:
			top = i
		if k.size() == 2 and k[1].distance_to(Vector3(1, 0.5, 1)) < 1e-4:
			bot = i
	var v1 := _mesh_pts(blk)
	ct.pick_point(bot, 1)
	ct.pick_point(top, 0, true)
	check(ct.merge_points(), "merged")
	check(ct.curves.size() == n0, "one edge again (%d)" % ct.curves.size())
	var spec2: Dictionary = blk.get_meta("curve_solid")
	check((spec2["chains"] as Array).size() == (spec0["chains"] as Array).size(), "the solid's edges joined too")
	check(_mesh_pts(blk) == v1, "its mesh as it was")
	var ids := {}
	for e in spec2["fv"]:
		check(int(e[1]) < (spec2["chains"] as Array).size(), "every edge vertex on a chain that's there")
		ids[int(e[1])] = true
	await _done(ed)


func test_points_extrude_connect_delete_and_move() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)]), "closed": false})
	ct.select(0)
	# extrude its end: a new point follows the mouse till a click keeps it
	ct.pick_point(0, 2)
	check(ct.extrude_points(), "extruding")
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() == 4 and ct._drag.has("grab"), "a new end vertex, following the mouse")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(300, 300)
	check(ct.view_input(click), "a click keeps it")
	check(ct._drag.is_empty(), "done")
	# two points picked and moved together (the others stay)
	ct.select(0)
	ct.pick_point(0, 0)
	ct.pick_point(0, 1, true)
	ct.begin_xf("move")
	ct.op["delta"] = Vector3(0, 0.5, 0)
	ct._op_update()
	ct.confirm_op()
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(k[0].distance_to(Vector3(0, 0.5, 0)) < 1e-4 and k[1].distance_to(Vector3(1, 0.5, 0)) < 1e-4 and k[2].distance_to(Vector3(2, 0, 0)) < 1e-4, "the two picked moved, the rest stayed (%s)" % k)
	# connect two points: a line between them
	ct.select(0)
	ct.pick_point(0, 0)
	ct.pick_point(0, 2, true)
	var n: int = ct.curves.size()
	check(ct.connect_points() and ct.curves.size() == n + 1, "connected: a new line")
	# delete a point
	ct.select(0)
	ct.pick_point(0, 1)
	var m: int = (ct.curves[0]["ctrl"] as PackedVector3Array).size()
	check(ct.delete_points() and (ct.curves[0]["ctrl"] as PackedVector3Array).size() == m - 1, "a vertex taken out")
	# subdivide between two neighbours: a point between, the shape kept
	ct.select(0)
	ct.pick_point(0, 0)
	ct.pick_point(0, 1, true)
	m = (ct.curves[0]["ctrl"] as PackedVector3Array).size()
	check(ct.subdivide_points() and (ct.curves[0]["ctrl"] as PackedVector3Array).size() == m + 1, "a vertex put between")
	await _done(ed)


## Extrude face: a baked block's top face pulled up 0.5 m - the block taller, still closed (no holes), walls
## of quads, the top's edges copied up and a side edge up each corner; pushed in it's shorter; one undo.
func test_extrude_face() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	for i in 60:
		if not ct.has_meta("join_job"):
			break
		await tree.process_frame
	var spec: Dictionary = blk.get_meta("curve_solid")
	var fs: Dictionary = ct._faces_of(spec)
	var v: PackedVector3Array = fs["v"]
	var t: PackedInt32Array = fs["t"]
	var top_f := -1
	for ti in t.size() / 3:
		if v[t[ti * 3]].y > 0.999 and v[t[ti * 3 + 1]].y > 0.999 and v[t[ti * 3 + 2]].y > 0.999:
			top_f = (fs["face"] as PackedInt32Array)[ti]
			break
	var ids: Array = ct._face_ids(spec, fs, top_f)
	ct.set_meta("patch", {"part": blk.get_instance_id(), "ids": ids, "seed": Vector3(0.5, 1, 0.5)})
	var n_ids: int = (spec["ids"] as Array).size()
	ct.begin_face_extrude()
	check(ct.op.get("kind", "") == "face_extrude", "the operation starts")
	check(((ct.op["n_local"] as Vector3) - Vector3.UP).length() < 1e-3, "along the face's normal (up)")
	ct.op["value"] = 0.5
	ct._op_update()
	ct.confirm_op()
	var s1: Dictionary = blk.get_meta("curve_solid")
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	var t1 := PackedInt32Array(s1["mesh"]["t"])
	check_eq(EN._open_edges(t1), 0, "still closed - no holes")
	var mv: Array = s1["mesh"]["v"]
	var top := -INF
	for i in range(1, mv.size(), 3):
		top = maxf(top, float(mv[i]))
	check(absf(top - 1.5) < 1e-4, "the top now at 1.5 m (%.3f)" % top)
	var added: int = (s1["ids"] as Array).size() - n_ids
	check(added >= 5, "its edges copied up and a side edge at each corner (%d new)" % added)
	await tree.process_frame
	ct.refresh_solids()
	check(Shapes.volume(blk.mesh) > 1.4, "the block 1.5 m tall (volume %.3f)" % Shapes.volume(blk.mesh))
	var v2 := PackedVector3Array()
	for i in range(0, mv.size(), 3):
		v2.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
	var faces: Array = EN._pair_faces(v2, t1, s1["fv"])
	var quads := faces.filter(func(f): return (f as Array).size() == 4).size()
	check(quads >= faces.size() * 0.8, "quads (%d of %d)" % [quads, faces.size()])
	ed.undo()
	check_eq(((blk.get_meta("curve_solid") as Dictionary)["ids"] as Array).size(), n_ids, "undo: as it was")
	await _done(ed)


## The knife snaps (Blender's way): a click near a vertex of the solid's edges lands on it, near an edge on
## it; Ctrl: free.
func test_knife_snaps_to_vertices_and_edges() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	for i in 60:
		if not ct.has_meta("join_job"):
			break
		await tree.process_frame
	ed.view.frame(blk.global_transform * blk.get_aabb())
	await tree.process_frame
	# (a top corner in sight)
	var cam: Vector3 = ed.view.cam.global_position
	var corner := Vector3.ZERO
	var best := INF
	for q in [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1)]:
		var w: Vector3 = blk.global_transform * q
		if w.distance_to(cam) < best:
			best = w.distance_to(cam)
			corner = w
	var sc: Vector2 = ed.view.cam.unproject_position(corner)
	ct.begin_knife()
	var sn: Dictionary = ct._knife_snap(sc + Vector2(5, 4), null)
	check(not sn.is_empty() and str(sn["kind"]) == "vertex" and (sn["world"] as Vector3).distance_to(corner) < 1e-3, "near a corner: snapped onto it (%s)" % str(sn.get("kind", "none")))
	# an edge: between that corner and the next one along the top
	var other: Vector3 = blk.global_transform * Vector3(0.5, 1, 0.5)
	var mid := corner.lerp(corner + Vector3((other - corner).x * 2.0, 0, 0), 0.5)
	var sm: Vector2 = ed.view.cam.unproject_position(mid)
	var se: Dictionary = ct._knife_snap(sm + Vector2(0, 6), null)
	check(not se.is_empty() and str(se["kind"]) == "edge" and absf((se["world"] as Vector3).y - corner.y) < 1e-3, "near an edge: snapped onto it (%s)" % str(se.get("kind", "none")))
	# a click there places the knife's point exactly on the vertex
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = sc + Vector2(5, 4)
	ct._knife_input(mb)
	var kn: Dictionary = ct.get_meta("knife")
	check((kn["clicks"] as Array).size() == 1 and (blk.global_transform * (kn["clicks"][0]["pos"] as Vector3)).distance_to(corner) < 1e-3, "the click: on the vertex")
	mb.ctrl_pressed = true
	ct._knife_input(mb)
	check((blk.global_transform * (kn["clicks"][1]["pos"] as Vector3)).distance_to(corner) > 1e-3, "Ctrl: where the mouse is, not snapped")
	ct.knife_stop()
	await _done(ed)


## Remesh: a baked solid laid out again by the topology rules, in the background - still closed, mostly
## quads, its edges as they were; one undo step.
func test_remesh_solid() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	for i in 60:
		if not ct.has_meta("join_job"):
			break
		await tree.process_frame
	var s0: Dictionary = blk.get_meta("curve_solid")
	var ids0: Array = (s0["ids"] as Array).duplicate()
	ct.remesh_solid(blk)
	var t_end := Time.get_ticks_msec() + 60000
	var bar_seen := false
	while ct.has_meta("remesh_job") and Time.get_ticks_msec() < t_end:
		await tree.process_frame
		if ct.has_meta("remesh_bar") and is_instance_valid(ct.get_meta("remesh_bar")):
			var bx: Control = ct.get_meta("remesh_bar")
			bar_seen = bar_seen or (bx.get_parent() == ed.view and bx.position.x < ed.view.size.x * 0.5 and bx.position.y > ed.view.size.y * 0.5)
	check(bar_seen, "a progress bar in the view's lower left corner while it works")
	check(not ct.has_meta("remesh_bar"), "the bar gone when it's done")
	var s1: Dictionary = blk.get_meta("curve_solid")
	check(s1 != s0 and s1["mesh"]["t"] != s0["mesh"]["t"], "laid out again")
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	check_eq(EN._open_edges(PackedInt32Array(s1["mesh"]["t"])), 0, "still closed")
	check_eq(s1["ids"], ids0, "its edges as they were")
	var mv: Array = s1["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, mv.size(), 3):
		v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
	var fs: Array = EN._pair_faces(v, PackedInt32Array(s1["mesh"]["t"]), s1["fv"])
	var q := fs.filter(func(f): return (f as Array).size() == 4).size()
	check(q >= fs.size() * 0.9, "mostly quads (%d of %d)" % [q, fs.size()])
	ed.undo()
	check((blk.get_meta("curve_solid") as Dictionary)["mesh"]["t"] == s0["mesh"]["t"], "undo: as it was")
	await _done(ed)


## Remesh in the right-click menu whatever's picked on a solid: a face of it, the whole solid, or nothing.
func test_remesh_in_every_solid_menu() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	var has_remesh := func() -> bool:
		for g in ct.menu_groups():
			for it in g:
				if str(it[1]) == "Remesh" and bool(it[5]):
					return true
		return false
	ct.sel = []
	check(has_remesh.call(), "the solid selected: Remesh")
	var spec: Dictionary = blk.get_meta("curve_solid")
	var fs: Dictionary = ct._faces_of(spec)
	ct.set_meta("patch", {"part": blk.get_instance_id(), "ids": ct._face_ids(spec, fs, 0), "seed": Vector3(0.5, 1, 0.5)})
	check(not ct.picked_patch().is_empty() and has_remesh.call(), "a face picked: Remesh too")
	ct.remove_meta("patch")
	ct.set_meta("solid", blk.get_instance_id())
	check(ct.picked_solid() != null and has_remesh.call(), "the whole solid picked: Remesh too")
	await _done(ed)


## A bake lays its solid out quickly (grids), then fully in the background (the field-aligned fill where it's
## cleaner) - its own undo step; the solid stays closed.
func test_bake_lays_out_in_background() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# (a revolved sphere with a smaller one cut out of its side - the even-mesh path, laid out as grids)
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(0.69, 0.68, 0), Vector3(0, 1.36, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("revolve", 360.0)
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0.5, 1.0, 0), Vector3(0, 1.5, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(1)
	var small: MeshInstance3D = ct.make_part("revolve", 360.0)
	small.position = Vector3(0.6, 0, 0)
	check(ct.cut_from(small, blk), "cut")
	ed.select_part(blk)
	var t0 := Time.get_ticks_msec()
	check(ct.bake_solid(blk), "baked")
	check(Time.get_ticks_msec() - t0 < 3000, "the bake itself quick (%d ms)" % (Time.get_ticks_msec() - t0))
	check(ct.has_meta("remesh_after") or ct.has_meta("remesh_job"), "the full layout queued")
	var t_end := Time.get_ticks_msec() + 60000
	while (ct.has_meta("remesh_after") or ct.has_meta("remesh_job") or ct.has_meta("join_job")) and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	check(not ct.has_meta("remesh_job") and not ct.has_meta("remesh_after"), "laid out within a minute")
	var s1: Dictionary = blk.get_meta("curve_solid")
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	check_eq(EN._open_edges(PackedInt32Array(s1["mesh"]["t"])), 0, "still closed")
	await _done(ed)


func test_patch_pick_move_and_resolution() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	# its top face as a patch (as a click on it picks it)
	var spec: Dictionary = blk.get_meta("curve_solid")
	var fs: Dictionary = ct._faces_of(spec)
	var v: PackedVector3Array = fs["v"]
	var t: PackedInt32Array = fs["t"]
	var top_f := -1
	for ti in t.size() / 3:
		if v[t[ti * 3]].y > 0.999 and v[t[ti * 3 + 1]].y > 0.999 and v[t[ti * 3 + 2]].y > 0.999:
			top_f = (fs["face"] as PackedInt32Array)[ti]
			break
	var ids: Array = ct._face_ids(spec, fs, top_f)
	check(ids.size() >= 1, "the top face's edges (%d)" % ids.size())
	ct.set_meta("patch", {"part": blk.get_instance_id(), "ids": ids, "seed": Vector3(0.5, 1, 0.5)})
	var pa: Dictionary = ct.picked_patch()
	check(not pa.is_empty() and (pa["tris"] as PackedInt32Array).size() > 0, "picked: its triangles")
	# finer: more triangles, still closed; coarser: as it was
	var n0: int = (spec["mesh"]["t"] as Array).size()
	check(ct.patch_finer(), "finer")
	var s1: Dictionary = blk.get_meta("curve_solid")
	var n1: int = (s1["mesh"]["t"] as Array).size()
	check(n1 > n0, "finer: more triangles (%d -> %d)" % [n0 / 3, n1 / 3])
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	check(EN._open_edges(PackedInt32Array(s1["mesh"]["t"])) == 0, "still closed")
	check(ct.patch_level() == 1, "level 1")
	check(ct.patch_coarser(), "coarser")
	check(((blk.get_meta("curve_solid") as Dictionary)["mesh"]["t"] as Array).size() == n0, "as it was")
	# moved as a whole: G on the patch moves its edges' points (the walls follow)
	ct.begin_xf("move")
	check(ct.op.has("points"), "moving its vertices")
	ct.op["delta"] = Vector3(0, 0.25, 0)
	ct._op_update()
	ct.confirm_op()
	ct._settle_finish()   # (settled on a worker: taken)
	var hi := -INF
	for q in _mesh_pts(blk):
		hi = maxf(hi, q.y)
	check(absf(hi - 1.25) < 0.01, "the top went up with it (%.3f)" % hi)
	await _done(ed)


## An edit let go: it settles, no remesh (the user's call - a vertex move only moves); one undo step, the
## solid closed, the edit's shape kept.
func test_settle_does_not_remesh() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	var t_end := Time.get_ticks_msec() + 60000
	while (ct.has_meta("remesh_after") or ct.has_meta("remesh_job") or ct.has_meta("join_job")) and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	var spec: Dictionary = blk.get_meta("curve_solid")
	var fs: Dictionary = ct._faces_of(spec)
	var v: PackedVector3Array = fs["v"]
	var t: PackedInt32Array = fs["t"]
	var top_f := -1
	for ti in t.size() / 3:
		if v[t[ti * 3]].y > 0.999 and v[t[ti * 3 + 1]].y > 0.999 and v[t[ti * 3 + 2]].y > 0.999:
			top_f = (fs["face"] as PackedInt32Array)[ti]
			break
	ct.set_meta("patch", {"part": blk.get_instance_id(), "ids": ct._face_ids(spec, fs, top_f), "seed": Vector3(0.5, 1, 0.5)})
	ct.begin_xf("move")
	ct.op["delta"] = Vector3(0, 0.25, 0)
	ct._op_update()
	ct.confirm_op()
	ct._settle_finish()
	var steps: int = ed._eundo.size() if ed.mode == "edit" else ed._undo.size()
	check(not ct.has_meta("remesh_after") and not ct.has_meta("remesh_job"), "no remesh after the edit")
	t_end = Time.get_ticks_msec() + 60000
	while (ct.has_meta("remesh_after") or ct.has_meta("remesh_job")) and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	check_eq(ed._eundo.size() if ed.mode == "edit" else ed._undo.size(), steps, "no undo step of its own")
	var s1: Dictionary = blk.get_meta("curve_solid")
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	check_eq(EN._open_edges(PackedInt32Array(s1["mesh"]["t"])), 0, "still closed")
	var hi := -INF
	for q in _mesh_pts(blk):
		hi = maxf(hi, q.y)
	check(absf(hi - 1.25) < 0.01, "the edit kept (top %.3f)" % hi)
	await _done(ed)


func test_menu_icons_fold_and_no_twins() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ed.show_right_tab(1)
	var m: PopupPanel = ed.menu(Vector2(200, 200))
	await tree.process_frame
	check(ed.find_child("MenuFoldIn", true, false) != null, "it unrolls as it opens")
	var cp: Control = m.find_child("Page", true, false)
	check(cp.find_children("Group_*", "", true, false).is_empty(), "every tool its own icon - no groups")
	var circ: Button = cp.find_child("Menu_Circle", true, false)
	check(circ != null and circ.get_parent() is HFlowContainer, "the circle tool its own icon in the row")
	if circ:
		circ.pressed.emit()
		check(ct.tool == "circle", "pressed: runs")
		ct.stop()
	m.hide()
	await tree.process_frame
	# what the menu has isn't on the bars and panels too
	check(not ed._kind_btns[0].visible, "the vertex-select button: only in the menu")
	check(not (ct._panel_btns["tool_line"] as Button).visible, "the sketch tools: only in the menu")
	check(not (ct._panel_btns["op_Extrude"][0] as Button).visible, "the solid tools: only in the menu")
	await _done(ed)


func test_click_again_picks_bigger() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var r := _block_with_side_point(ed)
	var side: int = r[1]
	check(side >= 0, "a baked block's side edge")
	if side < 0:
		await _done(ed)
		return
	ct.select(side)
	ed.view.set_view("front")
	ed.view.frame(AABB(Vector3(-0.2, -0.2, -0.2), Vector3(1.6, 1.4, 1.6)))
	await tree.process_frame
	var at: Vector2 = ct._screen(Vector3(1, 0.5, 1))
	var click := func():
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = at
			ct.view_input(e)
	# a click on its point: only the point picked
	click.call()
	check(ct.picked_points() == [[side, 1]] and ct.picked_patch().is_empty(), "the vertex (%s)" % [ct.picked_points()])
	# again: the curve (the point let go)
	click.call()
	check(ct.picked_points().is_empty() and ct.sel == [side], "then its edge")
	# again: a patch it bounds
	click.call()
	var pa: Dictionary = ct.picked_patch()
	check(not pa.is_empty() and int(ct.curves[side]["id"]) in (pa["ids"] as Array), "then a face beside it")
	# again: the whole solid
	click.call()
	check(ct.picked_solid() == r[0] and ct.picked_patch().is_empty(), "then the whole solid")
	check(ct.sel.is_empty() and ct.picked_points().is_empty(), "the solid alone: none of its edges or vertices picked")
	check(ct.pick(at) == -1 and ct.pick_handle(at).is_empty(), "... nor shown (nothing to click there)")
	# chosen in the parts list or clicked in object mode: the same - the solid alone
	ct.select(-1)
	ct.select(side)
	ct.solid_chosen(r[0])
	check(ct.picked_solid() == r[0] and ct.sel.is_empty(), "chosen as a collection: the solid alone")
	# a face clicked: its patch; again: the solid; again: the patch
	var face_at: Vector2 = ct._screen(Vector3(0.5, 0.5, 1))
	ct.select(-1)
	check(ct.pick_patch(face_at) and not ct.picked_patch().is_empty(), "a face: its face")
	check(ct.pick_patch(face_at) and ct.picked_solid() == r[0], "the face again: the whole solid")
	ct.begin_xf("move")
	check(ct.op.has("points") and (ct.op["points"] as Array).size() > 8, "G moves all its vertices")
	ct.cancel_op()
	check(ct.pick_patch(face_at) and not ct.picked_patch().is_empty() and ct.picked_solid() == null, "again: the face")
	await _done(ed)


func test_press_drag_moves_click_picks() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 1.0)
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	ed.show_right_tab(1)
	ct.select(-1)
	ed.view.set_view("front")
	ed.view.frame(AABB(Vector3(-0.2, -0.2, -0.2), Vector3(1.6, 1.4, 1.6)))
	await tree.process_frame
	var at: Vector2 = ct._screen(Vector3(0.5, 0.5, 1))
	var ev := func(kind: String, pos: Vector2):
		var e: InputEvent
		if kind == "move":
			e = InputEventMouseMotion.new()
			(e as InputEventMouseMotion).position = pos
		else:
			e = InputEventMouseButton.new()
			(e as InputEventMouseButton).button_index = MOUSE_BUTTON_LEFT
			(e as InputEventMouseButton).pressed = kind == "down"
			(e as InputEventMouseButton).position = pos
		return ct.view_input(e)
	# a press and a drag up on the front face, nothing picked: its patch picked and moved up with it
	var v0 := _mesh_pts(blk)
	check(ev.call("down", at), "the press is the edge tools'")
	check(ct.picked_patch().is_empty(), "nothing picked on the press itself")
	for k in 6:
		ev.call("move", at + Vector2(0, -10.0 * (k + 1)))
	ev.call("up", at + Vector2(0, -60))
	check(ct.has_meta("settling"), "let go: settling on a worker")
	for k in 200:
		if not ct.has_meta("settling"):
			break
		await tree.process_frame   # (taken when it's done, a frame at a time)
	check(not ct.has_meta("settling"), "settled")
	var pa: Dictionary = ct.picked_patch()
	check(not pa.is_empty(), "the face pressed: its face picked")
	var hi := -INF
	for q in _mesh_pts(blk):
		if q.z > 0.99:
			hi = maxf(hi, q.y)
	check(hi > 1.05, "... and dragged up (its top %.3f)" % hi)
	ed.undo()
	check(_mesh_pts(blk) == v0, "one undo: back")
	# a click (no drag) on it: the pick grows - the whole solid - and nothing moves
	var v1 := _mesh_pts(blk)
	ct.set_meta("patch", {})
	ct.pick_patch(at)
	ev.call("down", at)
	ev.call("up", at)
	check(ct.picked_solid() == blk, "a click on the picked face: the whole solid")
	check(_mesh_pts(blk) == v1, "nothing moved")
	await _done(ed)


func test_merge_curves_by_shared_points() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# three lines: a and b meet end to end (0.5 mm apart), c starts there too (0.5 mm off) but turns sharply;
	# d far away
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)]), "closed": false})
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(1.0005, 0, 0), Vector3(2, 0, 0.1)]), "closed": false})
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(1, 0, 0.0005), Vector3(0.9, 0, 1)]), "closed": false})
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(5, 0, 0), Vector3(6, 0, 0)]), "closed": false})
	for i in 4:
		ct.select(i, i > 0)
	ct.set_merge_dist(0.0001)
	check(ct.merge_curves_selected() == 0 and ct.curves.size() == 4, "ends 0.5 mm apart, a 0.1 mm merge distance: nothing joined")
	ct.set_merge_dist(0.001)
	check(ct.merge_curves_selected() == 1, "within 1 mm: one join")
	check(ct.curves.size() == 3, "three edges now (%d)" % ct.curves.size())
	var long_one := -1
	for i in ct.curves.size():
		if (ct.curves[i]["ctrl"] as PackedVector3Array).size() == 3:
			long_one = i
	check(long_one >= 0, "the straight pair made one - the sharp turn left apart")
	if long_one >= 0:
		var k: PackedVector3Array = ct.curves[long_one]["ctrl"]
		check(k[0].distance_to(Vector3(0, 0, 0)) < 1e-4 and k[2].distance_to(Vector3(2, 0, 0.1)) < 1e-4, "from one's start to the other's end (%s)" % k)
	ed.undo()
	check(ct.curves.size() == 4, "one undo: apart again")
	# a baked block's edges split, then merged back: one curve each again, its mesh as it was
	ed.new_model(true)
	var r := _block_with_side_point(ed)
	var blk: MeshInstance3D = r[0]
	var side: int = r[1]
	if side < 0:
		check(false, "a side edge")
		await _done(ed)
		return
	var n0: int = ct.curves.size()
	ct.select(side)
	ct.pick_point(side, 1)
	ct.separate_points()
	var v0 := _mesh_pts(blk)
	ct.select(-1)
	ct.solid_chosen(blk)
	check(ct.merge_curves_selected() >= 1, "the solid's edges merged")
	check(_mesh_pts(blk) == v0, "its mesh as it was")
	check(ct.curves.size() < n0 + 1, "the split edge one edge again (%d edges, was %d)" % [ct.curves.size(), n0])
	await _done(ed)


func test_curve_primitives() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var want := {"box": 1.0, "cylinder": PI * 0.25, "prism": 1.5 * sqrt(3.0) * 0.25, "cone": PI * 0.25 / 3.0, "sphere": PI / 6.0,
		"torus": 2.0 * PI * PI * 0.35 * 0.0225}
	for k in want:
		var p: MeshInstance3D = ct.add_curve_primitive(k)
		check(p != null and p.has_meta("curve_solid"), "%s: a solid from edges" % k)
		if p == null:
			continue
		var vol := Shapes.volume(p.mesh)
		check(absf(vol - float(want[k])) < float(want[k]) * 0.06, "%s: its volume %.4f (want %.4f)" % [k, vol, want[k]])
		var box: AABB = p.mesh.get_aabb()
		check(box.position.y > -0.01 and box.position.y < 0.01, "%s: on the ground (%.3f)" % [k, box.position.y])
	# the menu offers them with nothing picked
	ct.select(-1)
	var names := []
	for g in ct.menu_groups():
		for it in g:
			names.append(str(it[1]))
	check("Add sphere" in names and "Add box" in names, "the menu: Add edge box, sphere...")
	# reshaped: the solid follows its curve
	var cyl: MeshInstance3D = ed.parts()[1]
	var ci: int = ct._curve_index(int((cyl.get_meta("curve_solid") as Dictionary)["ids"][0]))
	var before: Array = ct._state()
	var k: PackedVector3Array = ct.curves[ci]["ctrl"]
	k[1] = Vector3(1.0, 0, 0)
	ct.curves[ci]["ctrl"] = k
	ct._changed("Move edge vertex", before)
	check(cyl.mesh.get_aabb().size.x > 1.9, "the cylinder grew with its circle (%.2f)" % cyl.mesh.get_aabb().size.x)
	await _done(ed)


func test_picked_patch_shaded_in_3d() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var r := _block_with_side_point(ed)
	var blk: MeshInstance3D = r[0]
	ct.solid_chosen(blk)
	ct._sync_pick_overlay()
	var mi: MeshInstance3D = ct.get_meta("pick_mi") if ct.has_meta("pick_mi") else null
	check(mi != null and mi.visible and mi.mesh == blk.mesh, "the solid picked: shaded in the 3D view (its own mesh, a skin over it)")
	check(not (mi in ed.parts()), "not one of the model's collections")
	check((mi.material_override as BaseMaterial3D).no_depth_test == false, "hidden where the solid hides it")
	var spec: Dictionary = blk.get_meta("curve_solid")
	var fs: Dictionary = ct._faces_of(spec)
	ct.set_meta("solid", 0)
	ct.set_meta("patch", {"part": blk.get_instance_id(), "ids": ct._face_ids(spec, fs, 0), "seed": Vector3.INF})
	ct._sync_pick_overlay()
	check(mi.visible and mi.mesh != blk.mesh and mi.mesh.get_surface_count() == 1, "a face: a mesh of its own triangles")
	ct.select(-1)
	ct._sync_pick_overlay()
	check(not mi.visible, "nothing picked: gone")
	await _done(ed)


func test_click_away_drops_the_solids_shading() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var r := _block_with_side_point(ed)
	ct.solid_chosen(r[0])
	var mi: MeshInstance3D = ct.get_meta("pick_mi")
	check(mi.visible, "the solid picked: shaded")
	# a click on nothing (far off in a corner of the sky)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(3, 3)
	ct.view_input(e)
	check(ct.picked_solid() == null, "let go")
	check(not mi.visible, "its shading gone with it")
	await _done(ed)


func test_ecurve_objects() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a plain mesh solid (a box part) made an ECurve solid in the background: its edges traced
	var bx: MeshInstance3D = ed.add_primitive("box")
	check(not bx.has_meta("curve_solid"), "a plain mesh to start with")
	ct.convert_parts([bx])
	for k in 600:
		if bx.has_meta("curve_solid") or bx.has_meta("ecurve_failed"):
			break
		await tree.process_frame
	check(bx.has_meta("curve_solid"), "made an ECurve solid (%s)" % bx.get_meta("ecurve_failed", ""))
	if bx.has_meta("curve_solid"):
		var spec: Dictionary = bx.get_meta("curve_solid")
		check(str(spec["kind"]) == "edges" and (spec["ids"] as Array).size() >= 6, "its edges: curves (%d)" % (spec["ids"] as Array).size())
		var v := Shapes.volume(bx.mesh)
		check(absf(v - 1.0) < 0.05, "the same shape (volume %.3f)" % v)
		check(bx.mesh.get_surface_count() == 1, "one surface")
	# associated with bones: kept with its recipe (bound as it's saved)
	# (no character here: the association needs a rig - checked by the menu's state elsewhere)
	# the Primitives tab: the ECurve primitives; the variants browser under the models
	ed.set_left_tab("shapes")
	var pl: ItemList = (ed.get_meta("prims") as Node).find_child("Primitives", true, false)
	check(pl.item_count == ct.CURVE_PRIMS.size(), "the primitives browser")
	var n0: int = ed.parts().size()
	pl.item_activated.emit(0)
	check(ed.parts().size() == n0 + 1, "double-click: added")
	check(ed._can_drop_shape(Vector2.ZERO, {"ecurve_prim": "sphere"}) and ed._can_drop_shape(Vector2.ZERO, {"ecurve_model": "res://models/test_curve_modeling.glb"}), "the view takes a dragged primitive or object")
	ed.fill_variant_browser("res://art/pirate_3d/pirate.glb")
	var vb: ItemList = ed.get_meta("variant_browser")
	check(vb.item_count >= 1 and vb.get_item_text(0).contains("original"), "the variants: the original first")
	# an ECurve object dropped in: added in a collection of its own
	var g: Node3D = ed.add_model_into("res://models/test_curve_modeling.glb", Vector3(2, 0, 0), true)
	check(g != null and ct.is_group(g) and g.get_child_count() >= 1, "dropped in: a collection of its solids")
	check(g.position.distance_to(Vector3(2, 0, 0)) < 1e-4, "where it was dropped")
	# no mesh editing: Tab does nothing, the menu has no edit mode
	var tab := InputEventKey.new()
	tab.pressed = true
	tab.keycode = KEY_TAB
	ed._unhandled_key_input(tab)
	check(ed.mode == "object", "Tab: no edit mode")
	var m: PopupPanel = ed.menu(Vector2(5, 5))
	check(m.find_child("Menu_Edit mode".validate_node_name(), true, false) == null, "the menu: no edit mode")
	m.hide()
	await _done(ed)


## An object dragged over the view: a marker where it'll land (on the surface under the pointer), its
## bounds once read; dropped: added there at once from that read; the drag over: the marker gone.
func test_drop_marker_shows_where() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	var box: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0, 0.5, 0))
	ed.view.frame(box.global_transform * box.get_aabb())
	await tree.process_frame
	var at: Vector2 = ed.view.project(box.global_transform * box.get_aabb().get_center())
	var data := {"ecurve_model": "res://models/test_curve_modeling.glb"}
	check(ed._can_drop_shape(at, data), "the view takes it")
	var mk: Node3D = ed.get_meta("drop_marker")
	var ring: MeshInstance3D = mk.get_node("Ring")
	var hit: Array = ed.shape_tools.drop_hit(at)
	check(mk.visible and ring.global_position.distance_to(hit[0]) < 1e-4, "the marker where it'll land")
	check((hit[0] as Vector3).distance_to(ed.shape_tools.drop_point(at)) < 1e-6, "the same point the drop uses")
	check(box.get_aabb().grow(0.01).has_point(box.global_transform.affine_inverse() * (hit[0] as Vector3)), "on the solid under the pointer")
	check((ring.global_basis.y.normalized()).dot(hit[1]) > 0.99, "lying on its surface")
	var bx: MeshInstance3D = mk.get_node("Bounds")
	for i in 200:
		ed._can_drop_shape(at, data)
		if bx.visible:
			break
		await tree.process_frame
	check(bx.visible and bx.mesh != null, "its bounds shown once read")
	var n0: int = ed.parts().size()
	ed._drop_shape(at, data)
	check(ed.parts().size() > n0 and not ed.has_meta("drop_job"), "dropped: added at once (read while dragged)")
	check(not mk.visible, "the drag over: the marker gone")
	# a primitive: the ring only
	ed._can_drop_shape(at, {"ecurve_prim": "sphere"})
	check(mk.visible and not bx.visible, "a primitive: the ring, no bounds")
	await tree.process_frame
	check(not mk.visible, "not dragging: hidden")
	await _done(ed)


## An open tube between two heights, quads round it (outward), in material `mat`.
func _tube(y0: float, y1: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	var rows := 5
	for r in rows:
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var ya := lerpf(y0, y1, float(r) / rows)
			var yb := lerpf(y0, y1, float(r + 1) / rows)
			var p00 := Vector3(cos(a0) * 0.3, ya, sin(a0) * 0.3)
			var p10 := Vector3(cos(a1) * 0.3, ya, sin(a1) * 0.3)
			var p01 := Vector3(cos(a0) * 0.3, yb, sin(a0) * 0.3)
			var p11 := Vector3(cos(a1) * 0.3, yb, sin(a1) * 0.3)
			for q in [p00, p01, p11, p00, p11, p10]:
				st.set_normal(Vector3(q.x, 0, q.z).normalized())
				st.add_vertex(q)
	st.index()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


## Two solids meeting along an edge (two halves of a tube, each its own material): converted, they're
## joined by themselves - one solid, the shared edge once, welded with no gap, quads kept, both materials;
## Auto join finds nothing more; undo puts the two back.
func test_auto_join_after_converting() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color.GRAY
	var parts := []
	for half in [[0.0, 0.4, red, "Low"], [0.4, 0.8, grey, "High"]]:
		var mi := MeshInstance3D.new()
		mi.name = half[3]
		mi.mesh = _tube(half[0], half[1], half[2])
		ed.model.add_child(mi)
		parts.append(mi)
	ed._fill_parts()
	ct.convert_parts(parts)
	for k in 1200:
		if not ct._converting() and not ct.has_meta("join_after") and not ct.has_meta("join_job") and ed.parts().size() == 1:
			break
		await tree.process_frame
	check_eq(ed.parts().size(), 1, "the two halves joined into one solid")
	if ed.parts().size() != 1:
		await _done(ed)
		return
	var p: MeshInstance3D = ed.parts()[0]
	var sp: Dictionary = p.get_meta("curve_solid")
	check(str(sp["kind"]) == "edges" and int(sp.get("joined", 0)) == 2, "an ECurve solid made of both")
	check_eq((sp["ids"] as Array).size(), 3, "three edges: the bottom, the top, the shared one once")
	# no gap: the only open sides are the tube's two ends
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var t := PackedInt32Array(sp["mesh"]["t"])
	var mv: Array = sp["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, mv.size(), 3):
		v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
	var AJ: GDScript = load("res://scripts/editor/mesh/auto_join.gd")
	var open: Dictionary = AJ.open_sides(Array(t))
	var at_seam := 0
	for k in open:
		if absf(v[k.x].y - 0.4) < 0.05 or absf(v[k.y].y - 0.4) < 0.05:
			at_seam += 1
	check(open.size() > 0 and at_seam == 0, "open only at its two ends - nothing open at the seam (%d of %d)" % [at_seam, open.size()])
	# quads kept
	var fs: Array = EN._pair_faces(v, t, sp["fv"])
	var quads := fs.filter(func(f): return (f as Array).size() == 4).size()
	check(quads >= fs.size() * 0.9, "quads (%d of %d faces)" % [quads, fs.size()])
	# both materials: a surface each, each in its own half
	for i in 10:
		await tree.process_frame
	check_eq(p.mesh.get_surface_count(), 2, "a surface a material")
	if p.mesh.get_surface_count() == 2:
		var ys := []
		for si in 2:
			var sv: PackedVector3Array = p.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var sum := 0.0
			for q in sv:
				sum += q.y
			ys.append([p.mesh.surface_get_material(si), sum / maxf(sv.size(), 1)])
		var low = ys[0] if float(ys[0][1]) < float(ys[1][1]) else ys[1]
		var high = ys[1] if low == ys[0] else ys[0]
		check(low[0] == red and high[0] == grey, "each half its own material still")
		# no shading seam: the normals either side of the weld the same
		var worst := 0.0
		var na: Array = p.mesh.surface_get_arrays(0)
		var nb: Array = p.mesh.surface_get_arrays(1)
		for i in (na[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var q: Vector3 = na[Mesh.ARRAY_VERTEX][i]
			if absf(q.y - 0.4) > 1e-4:
				continue
			for j in (nb[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				if (nb[Mesh.ARRAY_VERTEX][j] as Vector3).distance_to(q) < 1e-5:
					worst = maxf(worst, rad_to_deg((na[Mesh.ARRAY_NORMAL][i] as Vector3).angle_to(nb[Mesh.ARRAY_NORMAL][j])))
		check(worst < 1.0, "smooth across the weld (normals differ %.2f deg)" % worst)
	check(not ct.auto_join([], true), "nothing more to join (one solid)")
	# undo: the two again
	ed.undo()
	check_eq(ed.parts().size(), 2, "undo: the two solids back")
	ed.redo()
	check_eq(ed.parts().size(), 1, "redo: one again")
	await _done(ed)


## Merge by distance: two vertices of one edge within the merge distance - one dissolved; two edges'
## ends within it - moved together, so they meet; vertices farther apart left alone; one undo step.
func test_merge_by_distance() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var a: Dictionary = ct._fresh({"kind": "line", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1.0004, 0, 0), Vector3(2, 0, 0)]), "closed": false, "n": Vector3.UP})
	var b: Dictionary = ct._fresh({"kind": "line", "ctrl": PackedVector3Array([Vector3(2.0006, 0, 0.0002), Vector3(3, 0, 1)]), "closed": false, "n": Vector3.UP})
	ct.curves = [a, b]
	ct.set_merge_dist(0.001)
	var n: int = ct.merge_by_distance()
	check_eq(n, 2, "two merged: one dissolved, one pair welded")
	var ka: PackedVector3Array = ct.curves[0]["ctrl"]
	var kb: PackedVector3Array = ct.curves[1]["ctrl"]
	check_eq(ka.size(), 3, "the close pair on one edge: one point now")
	check(ka[ka.size() - 1].distance_to(kb[0]) < 1e-6, "the two edges' ends in one place")
	check(ka[0] == Vector3.ZERO and kb[1] == Vector3(3, 0, 1), "points farther apart left where they were")
	check_eq(ct.merge_by_distance(), 0, "nothing left to merge")
	ed.undo()
	check_eq((ct.curves[0]["ctrl"] as PackedVector3Array).size(), 4, "undo: as it was")
	await _done(ed)


func test_ecurve_solid_bones() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var p: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0, 1.2, 0))
	ed.select_part(p)
	check(p.has_meta("curve_solid") and str((p.get_meta("curve_solid") as Dictionary).get("bone", "")) == "auto", "added to a character: associated with its bones at once, still an ECurve solid")
	var sp0: Dictionary = (p.get_meta("curve_solid") as Dictionary).duplicate()
	sp0.erase("bone")
	p.set_meta("curve_solid", sp0)
	check(ed.bind_part(p), "bound")
	check(str((p.get_meta("curve_solid") as Dictionary).get("bone", "")) == "auto", "an ECurve solid: associated with its nearest bones, kept with its recipe")
	check(p.skin == null and p.has_meta("curve_solid"), "its mesh still its own (edits stay free)")
	ed.undo()
	check(not (p.get_meta("curve_solid") as Dictionary).has("bone"), "undo: not associated")
	ed.redo()
	# as it's saved: bound for the write, then back
	var boned: Array = ed._apply_bone_links()
	check(boned.size() == 1 and p.skin != null, "saving: bound to the bones (skinned)")
	for b in boned:
		ed._set_bind_state(b[0], b[1])
	check(p.skin == null and p.has_meta("curve_solid"), "and back as it was")
	await _done(ed)


func test_ecurve_mirror_solid() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var p: MeshInstance3D = ct.add_curve_primitive("box", Vector3(1, 0, 0))
	p.name = "Fore L Armor"
	ed.select_part(p)
	var n0: int = ed.parts().size()
	var c0: int = ct.curves.size()
	check(not ct._mirror_targets().is_empty(), "a solid selected: Mirror solid offered")
	ct.mirror_solids(0)
	check(ed.parts().size() == n0 + 1, "a mirrored copy added (%d solids)" % ed.parts().size())
	var d: MeshInstance3D = null
	for q in ed.parts():
		if q != p:
			d = q
	check(d != null and str(d.name) == "Fore R Armor", "named for the other side (%s)" % (d.name if d else "none"))
	check(d != null and absf(d.global_transform.origin.x + p.global_transform.origin.x) < 1e-4, "on the other side of X")
	check(d != null and d.global_transform.basis.determinant() < 0.0, "mirrored, not just moved")
	check(ct.curves.size() == c0 * 2, "its own edges (%d -> %d)" % [c0, ct.curves.size()])
	var a_ids: Array = ct.spec_ids(p.get_meta("curve_solid"))
	var b_ids: Array = ct.spec_ids(d.get_meta("curve_solid")) if d else []
	var shared := a_ids.filter(func(x): return x in b_ids)
	check(shared.is_empty() and not b_ids.is_empty(), "no edge shared between them")
	check(CT._side_swap("upper_arm.L") == "upper_arm.R" and CT._side_swap("Left Hand") == "Right Hand" and CT._side_swap("Lamp") == "Lamp", "sides swapped in names, not inside words")
	ed.undo()
	check(ed.parts().size() == n0 and ct.curves.size() == c0, "undo: gone, its edges too")
	await _done(ed)


func test_ecurve_symmetry_drag() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(0.5, 0, 0), Vector3(0.5, 1, 0)]), "closed": false, "n": Vector3.BACK})
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(-0.5, 1, 0)]), "closed": false, "n": Vector3.BACK})
	ct.add_curve({"kind": "line", "ctrl": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 0.5, 1)]), "closed": false, "n": Vector3.UP})
	ed.sym[0] = true
	var tw: Array = ct._find_twins([[0, 0], [2, 0]])
	check(tw.size() == 2, "each dragged vertex's twin found (%d)" % tw.size())
	check(tw.size() == 2 and int(tw[0][0]) == 1 and int(tw[0][1]) == 0 and not tw[0][4], "the mirror image's vertex on the other edge")
	check(tw.size() == 2 and bool(tw[1][4]), "a vertex on the plane: its own twin")
	ct._drag = {"handle": [0, 0], "multi": [[2, 0]]}
	var k0: PackedVector3Array = ct.curves[0]["ctrl"]
	k0[0] = Vector3(0.7, 0.1, 0.2)
	ct.curves[0]["ctrl"] = k0
	var k2: PackedVector3Array = ct.curves[2]["ctrl"]
	k2[0] = Vector3(0.3, 0.6, 0)
	ct.curves[2]["ctrl"] = k2
	ct._move_twins(tw)
	var m: Vector3 = (ct.curves[1]["ctrl"] as PackedVector3Array)[0]
	check(m.distance_to(Vector3(-0.7, 0.1, 0.2)) < 1e-5, "the twin follows, mirrored (%s)" % m)
	var on: Vector3 = (ct.curves[2]["ctrl"] as PackedVector3Array)[0]
	check(absf(on.x) < 1e-6 and absf(on.y - 0.6) < 1e-5, "the vertex on the plane stays on it (%s)" % on)
	ct._drag = {}
	ed.sym[0] = false
	check(ct.sym_items().size() == 6, "the symmetry tools in the menu: X / Y / Z, mirror across each")
	await _done(ed)


func test_ecurve_weapons_and_tpose() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var sk: Skeleton3D = ed.model.find_children("*", "Skeleton3D", true, false)[0]
	var arm := ""
	for b in sk.get_bone_count():
		if ed.TPose._is_arm(sk.get_bone_name(b)) and sk.get_bone_name(b).to_lower().contains("upper"):
			arm = sk.get_bone_name(b)
			break
	check(arm != "", "an arm bone (%s)" % arm)
	var sleeve: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0.4, 1.4, 0))
	var sp: Dictionary = (sleeve.get_meta("curve_solid") as Dictionary).duplicate()
	sp["bone_name"] = arm
	sleeve.set_meta("curve_solid", sp)
	var gun: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0.6, 1.0, 0))
	var gp: Dictionary = (gun.get_meta("curve_solid") as Dictionary).duplicate()
	gp["bone_name"] = "Gun"
	gun.set_meta("curve_solid", gp)
	check(ed._whole_weapon(gun) and not ed._whole_weapon(sleeve), "a solid moving with the gun's bone is a weapon")
	ed.set_weapons(false)
	check(not gun.visible and gun.has_meta("weapon_hidden") and sleeve.visible, "weapons hidden: the gun solid hidden whole")
	ed.set_weapons(true)
	check(gun.visible and not gun.has_meta("weapon_hidden"), "and shown again")
	var xf0 := sleeve.transform
	ed.toggle_tpose()
	check(sleeve.has_meta("tpose_xf") and not sleeve.transform.is_equal_approx(xf0), "T-pose: the solid turned by its arm bone")
	check(ed.is_tposed(), "T-posed")
	for i in 600:
		if ed._tpose_task < 0:
			break
		await tree.process_frame
	ed.toggle_tpose()
	for i in 600:
		if ed._tpose_task < 0:
			break
		await tree.process_frame
	check(not sleeve.has_meta("tpose_xf") and sleeve.transform.is_equal_approx(xf0), "back in its own pose, exactly")
	await _done(ed)



## Solids that name their bones but no rig in the model (a collection brought in from a file saved without
## one): T-pose borrows the game characters' rig - never into the model - and puts them back exactly.
func test_tpose_without_a_rig_in_the_model() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var sleeve: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0.4, 1.4, 0))
	var sp: Dictionary = (sleeve.get_meta("curve_solid") as Dictionary).duplicate()
	sp["bone_name"] = "upper.L"
	sleeve.set_meta("curve_solid", sp)
	check(ed.model.find_children("*", "Skeleton3D", true, false).is_empty(), "no rig in the model")
	var xf0 := sleeve.transform
	ed.toggle_tpose()
	check(sleeve.has_meta("tpose_xf") and not sleeve.transform.is_equal_approx(xf0), "T-pose: the solid turned by its arm bone")
	check(ed.model.find_children("*", "Skeleton3D", true, false).is_empty(), "the borrowed rig not put in the model")
	ed.toggle_tpose()
	check(not sleeve.has_meta("tpose_xf") and sleeve.transform.is_equal_approx(xf0), "back in its own pose, exactly")
	await _done(ed)

func _mouse_btn(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


func test_manual_vertex() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve({"kind": "spline", "ctrl": PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)]), "closed": false, "n": Vector3.BACK})
	var s0: PackedVector3Array = CT.sample(ct.curves[0])
	var items: Array = ct.point_items(ct._screen((ct.curves[0]["ctrl"] as PackedVector3Array)[1]))
	check(items.any(func(it): return str(it[0]) == "m_cv_pt_manual" and bool(it[5])), "the vertex's menu: Manual vertex")
	ct.set_point_manual(0, 1)
	var c: Dictionary = ct.curves[0]
	check(str(c["kind"]) == "path" and int((c["sharp"] as PackedByteArray)[1]) == 2 and (c["tin"] as PackedVector3Array).size() == 3, "a manual vertex: its mode and its two tangents")
	check(CT.point_mode(c, 1) == 2 and CT.point_mode(c, 0) != 2, "its mode: manual (the others as they were)")
	var s1: PackedVector3Array = CT.sample(c)
	var dev := 0.0
	for q in s1:
		var dmin := INF
		for r in s0:
			dmin = minf(dmin, q.distance_to(r))
		dev = maxf(dev, dmin)
	check(dev < 0.12, "made manual: the edge keeps its shape, about (%.3f)" % dev)
	# each side on its own: the leaving tangent bent - the arriving half untouched
	var before_in := CT._path_span(c["ctrl"], c["sharp"], false, c["tin"], c["tout"], 0, 16)
	var c2: Dictionary = c.duplicate(true)
	var to: PackedVector3Array = c2["tout"]
	to[1] = Vector3(0, -3, 0)
	c2["tout"] = to
	var after_in := CT._path_span(c2["ctrl"], c2["sharp"], false, c2["tin"], c2["tout"], 0, 16)
	var after_out := CT._path_span(c2["ctrl"], c2["sharp"], false, c2["tin"], c2["tout"], 1, 16)
	check(before_in == after_in, "the arriving side as it was")
	check(after_out[4].y < 0.6, "the leaving side bends where it was dragged (%s)" % after_out[4])
	# dragged in the view: the part of the edge beside it pressed, moved - the tangent follows, one undo step
	var sp := CT._path_span(c["ctrl"], c["sharp"], false, c["tin"], c["tout"], 1, 16)
	var at: Vector2 = ct._screen(sp[3])
	var tg: Array = ct.pick_tangent(at)
	check(tg.size() == 4 and int(tg[0]) == 0 and int(tg[1]) == 1 and bool(tg[2]), "pressing beside the vertex: its leaving side (%s)" % [tg.slice(0, 3)])
	var t_was: Vector3 = (ct.curves[0]["tout"] as PackedVector3Array)[1]
	ct.view_input(_mouse_btn(at, true))
	check(ct._drag.has("tangent"), "a tangent drag started")
	var mv := InputEventMouseMotion.new()
	mv.position = at + Vector2(0, 40)
	ct.view_input(mv)
	ct.layer.queue_redraw()   # (the green glow drawn while it's dragged - no errors)
	await tree.process_frame
	ct.view_input(_mouse_btn(at + Vector2(0, 40), false))
	var t_now: Vector3 = (ct.curves[0]["tout"] as PackedVector3Array)[1]
	check(not t_now.is_equal_approx(t_was), "dragged: the edge's bend into the vertex changed")
	check((ct.curves[0]["tin"] as PackedVector3Array)[1].is_equal_approx((c["tin"] as PackedVector3Array)[1]), "the other side untouched")
	ed.undo()
	check((ct.curves[0]["tout"] as PackedVector3Array)[1].is_equal_approx(t_was), "undo: back")
	# kept when saved
	var back: Array = CT.from_json(CT.to_json(ct.curves))
	check(back[0].has("tin") and (back[0]["tout"] as PackedVector3Array)[1].is_equal_approx(t_was), "saved and read back with its tangents")
	# a converted solid's edge: a manual vertex shapes the solid too
	var bx: MeshInstance3D = ed.add_primitive("box")
	ct.convert_parts([bx])
	for k in 600:
		if bx.has_meta("curve_solid") or bx.has_meta("ecurve_failed"):
			break
		await tree.process_frame
	if bx.has_meta("curve_solid"):
		var id0 := int((bx.get_meta("curve_solid")["ids"] as Array)[0])
		var ci: int = ct._curve_index(id0)
		var n: int = (ct.curves[ci]["ctrl"] as PackedVector3Array).size()
		ct.set_point_manual(ci, mini(1, n - 1))
		check(CT.point_mode(ct.curves[ci], mini(1, n - 1)) == 2, "a solid's edge can have a manual vertex")
		ct.refresh_solids()
		check(bx.mesh != null and bx.mesh.get_surface_count() == 1, "its solid still made")
	await _done(ed)


func test_ecurve_object_not_stored_twice() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var p: MeshInstance3D = ct.add_curve_primitive("box")
	check(p.has_meta("curve_solid"), "an ECurve solid already")
	ct.convert_parts([p], {"kind": "drop", "path": "res://art/player_3d/player.glb", "group": p.get_parent()})
	check((ct.get_meta("convert_batches", []) as Array).is_empty(), "nothing to convert: nothing stored again (no new variant)")
	check(not ct._converting(), "and nothing queued")
	await _done(ed)


func test_saved_character_keeps_bone_names() -> void:
	var MeshIO: GDScript = load("res://scripts/editor/mesh/mesh_io.gd")
	var root: Node = MeshIO.read("res://art/player_3d/player.glb")
	var out := "user://bone_names_kept.glb"
	check(MeshIO.write(root, out) == OK, "written")
	root.free()
	var back: Node = MeshIO.read(out)
	var sk: Skeleton3D = back.find_children("*", "Skeleton3D", true, false)[0] if back else null
	check(sk != null and sk.find_bone("upper.L") >= 0 and sk.find_bone("hand.R") >= 0, "its bones' names as they were (the game finds \"hand.R\" by name), not upper_L")
	if back:
		back.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))


func test_collection_picked_and_moved_whole() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var a: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0, 0, 0))
	var b: MeshInstance3D = ct.add_curve_primitive("box", Vector3(2, 0, 0))
	var g: Node3D = ct.make_group([a, b])
	check(g != null, "a collection of two solids")
	ed.view.set_view("front")
	ed.view.frame(AABB(Vector3(-1, -1, -1), Vector3(4, 2, 2)))
	await tree.process_frame
	# its row in the overview: the collection picked whole
	ct.pick_group(g)
	check(ct.picked_group() == g and ed.selected_parts().size() == 2, "the collection picked: both its solids selected")
	# dragged in the view by one of its solids: the whole collection moves - its solids' own places untouched
	var a0 := a.transform
	var b0 := b.transform
	var ga0 := a.global_position
	var at: Vector2 = ed.view.project(a.global_position + Vector3(0, 0, 0.5))
	ct.view_input(_mouse_btn(at, true))
	check(ct._drag.has("coll"), "pressing on its solid: a collection drag")
	var mv := InputEventMouseMotion.new()
	mv.position = at + Vector2(60, 0)
	ct.view_input(mv)
	ct.view_input(_mouse_btn(at + Vector2(60, 0), false))
	check(a.global_position.x > ga0.x + 0.1, "the collection moved (%.2f -> %.2f)" % [ga0.x, a.global_position.x])
	check(a.transform == a0 and b.transform == b0, "as one: its solids kept their places in it")
	check(absf((b.global_position - a.global_position).x - 2.0) < 1e-4, "still the same distance apart")
	ed.undo()
	check(a.global_position.distance_to(ga0) < 1e-4, "undo: back where it was")
	await _done(ed)


func test_overview_renames_on_double_click_only() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var a: MeshInstance3D = ct.add_curve_primitive("box")
	ct._refresh_panel()
	var t: Tree = ct._w("tree")
	var row: TreeItem = null
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.get("part") == a:
			row = it
	check(row != null and not row.is_editable(0), "a row isn't opened for typing by a click")
	check(row != null and row.get_icon(0) != null, "a solid's row has its icon")
	ed.select_part(a)
	t.set_selected(row, 0)
	t.item_activated.emit()
	check(_type_in(t, "Plate"), "a double-click opens its name for typing")
	check(str(a.name) == "Plate", "renamed so")
	await _done(ed)


func test_pan_follows_the_mouse_at_any_zoom() -> void:
	var ed := await _editor()
	ed.new_model(true)
	var v = ed.view
	for d in [0.08, 4.0, 60.0]:
		v.target = Vector3.ZERO
		v.dist = d
		v.update_camera()
		await tree.process_frame
		var p := Vector3(0, 0, 0)
		var s0: Vector2 = v.project(p)
		v.pan(Vector2(50, -30), v.depth_at(p))
		var s1: Vector2 = v.project(p)
		check((s1 - s0).distance_to(Vector2(50, -30)) < 1.0, "zoomed to %.2f m: what's grabbed moves with the mouse, 1:1 (%s)" % [d, s1 - s0])
	await _done(ed)


func test_not_selectable() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var a: MeshInstance3D = ct.add_curve_primitive("box", Vector3(0, 0, 0))
	var b: MeshInstance3D = ct.add_curve_primitive("box", Vector3(2, 0, 0))
	ed.select_part(a)
	ct.set_selectable(a, false)
	check(ct.locked(a) and not ct.locked(b), "the solid made not selectable")
	ed.select_part(b)
	check(a in ed.selected_parts() and b in ed.selected_parts(), "it can't be let go: picking another keeps it")
	ed.select_part(null)
	check(a in ed.selected_parts(), "nor by clicking nothing")
	ct.set_selectable(a, true)
	ed.select_part(null)
	check(ed.selected_parts().is_empty(), "selectable again: let go")
	ct.set_selectable(a, false)
	ed.select_part(a)
	check(not a in ed.selected_parts(), "nor picked")
	var ida := int((a.get_meta("curve_solid") as Dictionary)["ids"][0])
	var sel0: Array = ct.sel.duplicate()
	ct.select(ct._curve_index(ida))
	check(ct.sel == sel0, "nor any of its edges picked or let go (%s -> %s)" % [sel0, ct.sel])
	ed.undo()
	check(not ct.locked(a), "undo: selectable")
	# a collection's arrow: everything in it
	ct.set_selectable(a, true)
	var g: Node3D = ct.make_group([a, b])
	ct.set_selectable(g, false)
	check(ct.locked(a) and ct.locked(b), "a collection not selectable: its contents neither")
	ct._refresh_panel()
	var btns := 0
	for it in _tree_items(ct._w("tree")):
		if it.get_metadata(0) is Dictionary and (it.get_metadata(0) as Dictionary).has("part"):
			btns = it.get_button_count(1)
	check(btns == 2, "each solid's row: the eye and the arrow")
	var off_icon: Texture2D = EditorIcons.get_icon("m_cv_ol_sel_off")
	var all_off := true
	for it in _tree_items(ct._w("tree")):
		var m3 = it.get_metadata(0)
		if m3 is Dictionary and (m3 as Dictionary).has("part") and it.get_button(1, 1) != off_icon:
			all_off = false
	check(all_off, "the collection's arrow off: each of its solids' arrows shows off too")
	await _done(ed)


func test_knife_cuts_a_new_edge() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var bx: MeshInstance3D = ed.add_primitive("box")
	ct.convert_parts([bx])
	for k in 600:
		if bx.has_meta("curve_solid") or bx.has_meta("ecurve_failed"):
			break
		await tree.process_frame
	check(bx.has_meta("curve_solid"), "a box made of edges")
	if not bx.has_meta("curve_solid"):
		await _done(ed)
		return
	var spec0: Dictionary = bx.get_meta("curve_solid")
	var ids0: int = (spec0["ids"] as Array).size()
	var nv0: int = (spec0["mesh"]["v"] as Array).size() / 3
	var b := bx.get_aabb()
	var z := b.end.z
	var y := b.get_center().y
	var eye := Vector3(0, y, z + 3.0)
	var c0: int = ct.curves.size()
	var before: Array = ct._state()
	var res: Dictionary = ct.knife_apply_to(bx, [{"pos": Vector3(b.position.x, y, z), "eye": eye}, {"pos": Vector3(b.end.x, y, z), "eye": eye}])
	check(not res.has("error"), "cut across the front face from side to side (%s)" % res.get("error", ""))
	ct._changed("Knife", before)
	var spec1: Dictionary = bx.get_meta("curve_solid")
	check((spec1["ids"] as Array).size() == ids0 + 1 and ct.curves.size() == c0 + 1, "a new edge of the solid (%d -> %d)" % [ids0, (spec1["ids"] as Array).size()])
	var v := Shapes.volume(bx.mesh)
	check(absf(v - 1.0) < 0.05, "the solid's shape kept (volume %.3f)" % v)
	var cut_id := int(res.get("id", -1))
	var on_cut := (spec1["fv"] as Array).filter(func(e): return int(e[1]) == (spec1["chains"] as Array).size() - 1)
	check(on_cut.size() >= 2, "the cut's vertices belong to the new edge (%d)" % on_cut.size())
	check(ct.curve_by_id(cut_id).size() > 0, "its curve there to reshape")
	ed.undo()
	check(((bx.get_meta("curve_solid") as Dictionary)["ids"] as Array).size() == ids0, "undo: no cut")
	# off the mesh's lines: the faces really cut
	var y2 := b.position.y + b.size.y * 0.37
	var res2: Dictionary = ct.knife_apply_to(bx, [{"pos": Vector3(b.position.x, y2, z), "eye": Vector3(0, y2, z + 3.0)}, {"pos": Vector3(b.end.x, y2, z), "eye": Vector3(0, y2, z + 3.0)}])
	check(not res2.has("error") and ((bx.get_meta("curve_solid") as Dictionary)["mesh"]["v"] as Array).size() / 3 > nv0, "a cut across faces: new vertices along it (%s)" % res2.get("error", ""))
	check(absf(Shapes.volume(bx.mesh) - 1.0) < 0.05, "the shape kept")
	# the tool: K starts it, Esc stops it
	var kk := InputEventKey.new()
	kk.keycode = KEY_K
	kk.pressed = true
	check(ct.key(kk) and ct.has_meta("knife"), "K: the knife")
	kk.keycode = KEY_ESCAPE
	check(ct.key(kk) and not ct.has_meta("knife"), "Esc: stopped")
	await _done(ed)


## After a knife cut the faces either side of it are laid out again (only those): quads, closed, the shape
## and the new edge kept.
func test_knife_faces_laid_out_again() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var bx: MeshInstance3D = ed.add_primitive("box")
	ct.convert_parts([bx])
	for k in 600:
		if bx.has_meta("curve_solid") or bx.has_meta("ecurve_failed"):
			break
		await tree.process_frame
	if not bx.has_meta("curve_solid"):
		check(false, "a box made of edges")
		await _done(ed)
		return
	var b := bx.get_aabb()
	var z := b.end.z
	var y2 := b.position.y + b.size.y * 0.37
	var eye := Vector3(0, y2, z + 3.0)
	var res: Dictionary = ct.knife_apply_to(bx, [{"pos": Vector3(b.position.x, y2, z), "eye": eye}, {"pos": Vector3(b.end.x, y2, z), "eye": eye}])
	check(not res.has("error") and not (res.get("chains", []) as Array).is_empty(), "cut (%s)" % res.get("error", ""))
	var s0: Dictionary = (bx.get_meta("curve_solid") as Dictionary).duplicate(true)
	ct.remesh_solid(bx, "Lay out (the knife's faces)", res.get("chains", []))
	var t_end := Time.get_ticks_msec() + 60000
	while ct.has_meta("remesh_job") and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	var s1: Dictionary = bx.get_meta("curve_solid")
	check(s1["mesh"]["t"] != s0["mesh"]["t"], "the faces along the cut laid out again")
	var EN = load("res://scripts/editor/mesh/edge_net.gd")
	check_eq(EN._open_edges(PackedInt32Array(s1["mesh"]["t"])), 0, "still closed")
	check(absf(Shapes.volume(bx.mesh) - 1.0) < 0.05, "the shape kept (volume %.3f)" % Shapes.volume(bx.mesh))
	var last := (s1["chains"] as Array).size() - 1
	check((s1["fv"] as Array).filter(func(e): return int(e[1]) == last).size() >= 2, "the cut still an edge of it")
	var mv: Array = s1["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, mv.size(), 3):
		v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
	var fs: Array = EN._pair_faces(v, PackedInt32Array(s1["mesh"]["t"]), s1["fv"])
	var q := fs.filter(func(f): return (f as Array).size() == 4).size()
	check(q >= fs.size() * 0.85, "quads (%d of %d)" % [q, fs.size()])
	await _done(ed)


func test_vertex_modes_for_picked_vertices() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve({"kind": "spline", "ctrl": PackedVector3Array([Vector3(-1, 0, 0), Vector3(-0.3, 1, 0), Vector3(0.3, 1, 0), Vector3(1, 0, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(0)
	ct.pick_point(0, 1)
	ct.pick_point(0, 2, true)
	check(ct.picked_points().size() == 2, "two vertices picked")
	var labels := []
	for g in ct.menu_groups():
		for it in g:
			labels.append(str(it[1]))
	check(labels.count("Smooth vertex") == 1 and labels.count("Sharp vertex") == 1 and labels.count("Manual vertex") == 1, "the menu: Smooth / Sharp / Manual vertex, once each (%s)" % [labels])
	ct.set_points_mode(1)
	check(CT.point_mode(ct.curves[0], 1) == 1 and CT.point_mode(ct.curves[0], 2) == 1, "both made sharp at once")
	ed.undo()
	check(str(ct.curves[0]["kind"]) == "spline", "one undo step: back")
	await _done(ed)


func test_right_click_cancels_a_drag() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve({"kind": "spline", "ctrl": PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(0)
	ed.view.set_view("front")
	ed.view.frame(AABB(Vector3(-1.5, -0.5, -0.5), Vector3(3, 2, 1)))
	await tree.process_frame
	var was: Vector3 = (ct.curves[0]["ctrl"] as PackedVector3Array)[1]
	var at: Vector2 = ct._screen(was)
	var undo0: int = ed._undo.size()
	ct.view_input(_mouse_btn(at, true))
	var mv := InputEventMouseMotion.new()
	mv.position = at + Vector2(60, 30)
	ct.view_input(mv)
	check(not (ct.curves[0]["ctrl"] as PackedVector3Array)[1].is_equal_approx(was), "dragging: the vertex moves")
	var rc := _mouse_btn(at + Vector2(60, 30), true)
	rc.button_index = MOUSE_BUTTON_RIGHT
	check(ct.view_input(rc), "a right-click while dragging is taken")
	check((ct.curves[0]["ctrl"] as PackedVector3Array)[1].is_equal_approx(was), "and the drag called off: the vertex back where it was")
	ct.view_input(_mouse_btn(at + Vector2(60, 30), false))
	check((ct.curves[0]["ctrl"] as PackedVector3Array)[1].is_equal_approx(was) and ed._undo.size() == undo0, "letting go after: nothing moves, no undo step")
	await _done(ed)


func test_cut_picked_from_its_ghost() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.5)
	# a tall cylinder cut out of the block: it stands out of the block's top - its ghost there
	ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))
	ct.select(ct.curves.size() - 1)
	var cyl: MeshInstance3D = ct.make_part("extrude", 1.5)
	check(ct.cut_from(cyl, blk), "cut")
	ct.select(-1)
	ed.select_part(null)
	ct.update_ghosts()
	ed.frame_all()
	await tree.process_frame
	var top: Vector3 = blk.global_transform * Vector3(0.5, 1.3, 0.5)
	var at: Vector2 = ed.view.project(top)
	var gh: Dictionary = ct._ghost_hit(at)
	check(not gh.is_empty() and gh["part"] == blk, "the cut's ghost found under the mouse")
	# pressed there: the cut step picked - its solid selected, the circle picked
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.position = at
	ct.view_input(b)
	check(ed.part == blk, "its solid selected")
	check(ct.sel.size() == 1 and int(ct.curves[ct.sel[0]].get("id", -1)) == int(ct.spec_ids(blk.get_meta("curve_solid")["b"])[0]), "the cut's edge picked (%s)" % [ct.sel])
	check(ct.has_meta("step_pick"), "its ghost shown picked")
	# dragged: the cut moves whole - its place in the recipe, its edge's shape kept
	var k0: PackedVector3Array = (ct.curves[ct.sel[0]]["ctrl"] as PackedVector3Array).duplicate()
	var xf0: Array = (blk.get_meta("curve_solid")["b_xf"] as Array).duplicate()
	var v0 := Shapes.volume(blk.mesh)
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = at + Vector2(8 + i * 6, 0)
		ct.view_input(m)
	b.pressed = false
	b.position = at + Vector2(44, 0)
	ct.view_input(b)
	check(ct.curves[ct.sel[0]]["ctrl"] == k0, "the cut's edge kept its shape")
	check(blk.get_meta("curve_solid")["b_xf"] != xf0, "the cut moved")
	ed.undo()
	check(blk.get_meta("curve_solid")["b_xf"] == xf0, "undone: back where it was (%.4f vs %.4f)" % [Shapes.volume(blk.mesh), v0])
	# the overview lists the step even with the solid folded
	ct._unfolded().erase(blk.get_instance_id())
	ct._refresh_panel()
	var found := false
	var it: TreeItem = (ct._w("tree") as Tree).get_root()
	while it:
		if it.get_text(0).begins_with("Cut:"):
			found = true
		it = it.get_next_in_tree()
	check(found, "the cut's row in the overview, the solid folded")
	await _done(ed)


func test_revolve_near_axis_is_closed_and_cuts() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a half circle whose ends sit a hair off the axis (left so by a drag): revolved, it's still a closed solid
	var arc := {"kind": "arc", "ctrl": PackedVector3Array([Vector3(0.0002, -0.5, 0), Vector3(0.5, 0, 0), Vector3(0.0002, 0.5, 0)]), "closed": false, "n": Vector3.BACK}
	var m: ArrayMesh = ct.revolve_mesh([arc], TAU, 32, [Vector3.ZERO, Vector3.UP, -1])
	var MB: GDScript = load("res://scripts/editor/mesh/mesh_bool.gd")
	var big := BoxMesh.new()
	big.size = Vector3(2, 2, 2)
	var box := ArrayMesh.new()
	box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, big.get_mesh_arrays())
	var r: Dictionary = MB.run(box, m, Transform3D(), "difference")
	check(str(r.get("error", "")) == "", "cut from a box: a solid (%s)" % r.get("error", ""))
	await _done(ed)


func test_lines_follow_a_moved_step() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.5)
	ct.add_curve(_circle(Vector3(0.5, 0, 0.5), 0.2))
	ct.select(ct.curves.size() - 1)
	var cyl: MeshInstance3D = ct.make_part("extrude", 1.5)
	ct.cut_from(cyl, blk)
	ct.select(-1)
	await tree.process_frame
	await tree.process_frame
	var mi: MeshInstance3D = ct.get_meta("lines_mi")
	var sig0 = mi.get_meta("sig", 0)
	var spec: Dictionary = blk.get_meta("curve_solid").duplicate(true)
	spec["b_xf"] = ct.xf_arr(Transform3D(Basis.IDENTITY, Vector3(0.1, 0, 0)) * ct.xf_of(spec["b_xf"]))
	blk.set_meta("curve_solid", spec)
	ct.layer.queue_redraw()
	await tree.process_frame
	await tree.process_frame
	check(mi.get_meta("sig", 0) != sig0, "the cut's edge lines drawn where it went")
	await _done(ed)


func test_simplify_keeps_a_curved_rim() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	# a rim round a curved solid: a closed line of 48 points, not flat (a saddle), its plane's normal wrong
	var k := PackedVector3Array()
	for i in 48:
		var a := TAU * i / 48.0
		k.append(Vector3(cos(a), 0.3 * sin(2.0 * a), sin(a)))
	var c := {"kind": "line", "ctrl": k, "closed": true, "n": Vector3.UP}
	var e: Dictionary = ct.simplified(c)
	check(not e.is_empty() and (e["ctrl"] as PackedVector3Array).size() < 24, "made lean (%d vertices)" % (e["ctrl"] as PackedVector3Array).size() if not e.is_empty() else 0)
	var s: PackedVector3Array = ct.sample(e)
	s.append(s[0])
	var worst := 0.0
	for q in k:
		var best := INF
		for j in range(1, s.size()):
			best = minf(best, Geometry3D.get_closest_point_to_segment(q, s[j - 1], s[j]).distance_to(q))
		worst = maxf(worst, best)
	check(worst < 0.02, "its shape kept - not flattened (%.4f off at most)" % worst)
	await _done(ed)


func test_baked_cut_sphere_has_few_slivers() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	ed.new_model(true)
	# a revolved sphere, a smaller revolved sphere cut out of its side, baked into one solid
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(0.69, 0.68, 0), Vector3(0, 1.36, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(0)
	var big: MeshInstance3D = ct.make_part("revolve", 360.0)
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0.5, 1.0, 0), Vector3(0, 1.5, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(1)
	var small: MeshInstance3D = ct.make_part("revolve", 360.0)
	small.position = Vector3(0.6, 0, 0)
	check(ct.cut_from(small, big), "cut")
	ed.select_part(big)
	check(ct.bake_solid(big), "baked")
	var sp: Dictionary = big.get_meta("curve_solid")
	var flat: Array = sp["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, flat.size(), 3):
		v.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	var t := PackedInt32Array(sp["mesh"]["t"])
	var thin := 0
	for i in range(0, t.size(), 3):
		if ct._min_angle(v[t[i]], v[t[i + 1]], v[t[i + 2]]) < 15.0:
			thin += 1
	check(thin * 10 < t.size() / 3, "few slivers - halves of quads over 4 to 1: %d of %d triangles" % [thin, t.size() / 3])
	check(EN._open_edges(t) == 0, "still closed")
	check(t.size() / 3 < 12000, "not too dense (%d triangles)" % (t.size() / 3))
	await _done(ed)



## (bakes' topology) The baked solid's quads: [faces, lone triangles, open edges, dense].
func _quad_stats(blk: MeshInstance3D) -> Array:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var sp: Dictionary = blk.get_meta("curve_solid")
	var flat: Array = sp["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, flat.size(), 3):
		v.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	var t := PackedInt32Array(sp["mesh"]["t"])
	var faces: Array = EN._pair_faces(v, t, sp["fv"])
	var lone := 0
	for f in faces:
		if (f as Array).size() == 3:
			lone += 1
	return [faces.size(), lone, EN._open_edges(t), int(sp.get("dense", 0))]


func test_bake_lays_quads_along_the_edges() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a block with a tilted block cut into its corner (faces of many corners: rings round a middle grid)
	ct.add_curve(_rect(1.0, 1.0))
	ct.select(0)
	var blk: MeshInstance3D = ct.make_part("extrude", 0.6)
	ct.add_curve(_rect(0.5, 0.5))
	ct.select(1)
	var cut: MeshInstance3D = ct.make_part("extrude", 0.5)
	cut.position = Vector3(0.75, 0.35, 0.75)
	cut.rotation = Vector3(0.3, 0.5, 0.2)
	check(ct.cut_from(cut, blk), "cut")
	ed.select_part(blk)
	check(ct.bake_solid(blk), "baked")
	var st := _quad_stats(blk)
	check(st[3] == 3 and st[2] == 0, "made as grids of quads, closed (dense %d, open %d - %s)" % [st[3], st[2], load("res://scripts/editor/mesh/edge_net.gd").grid_why])
	check(st[1] * 100 < st[0] * 15, "quads: %d of %d faces are triangles" % [st[1], st[0]])
	await _done(ed)


func test_baked_dome_rings_follow_its_rim() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a revolved sphere with a smaller one cut out of its side: the dome round the cut's rim made rings
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(0.69, 0.68, 0), Vector3(0, 1.36, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(0)
	var big: MeshInstance3D = ct.make_part("revolve", 360.0)
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0.5, 1.0, 0), Vector3(0, 1.5, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(1)
	var small: MeshInstance3D = ct.make_part("revolve", 360.0)
	small.position = Vector3(0.6, 0, 0)
	check(ct.cut_from(small, big), "cut")
	ed.select_part(big)
	check(ct.bake_solid(big), "baked")
	var st := _quad_stats(big)
	check(st[3] == 3 and st[2] == 0, "made as grids of quads, closed (dense %d, open %d - %s)" % [st[3], st[2], load("res://scripts/editor/mesh/edge_net.gd").grid_why])
	check(st[1] * 100 < st[0] * 15, "quads: %d of %d faces are triangles" % [st[1], st[0]])
	await _done(ed)


func test_baked_tunnel_rows_run_between_its_rims() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	# a sphere with a tunnel bored through it: the outer surface between two rims, the tunnel's wall too -
	# ring-shaped faces, their rows running from one rim to the other
	ct.add_curve({"kind": "arc", "ctrl": PackedVector3Array([Vector3(0, 0, 0), Vector3(0.69, 0.68, 0), Vector3(0, 1.36, 0)]), "closed": false, "n": Vector3.BACK})
	ct.select(0)
	var big: MeshInstance3D = ct.make_part("revolve", 360.0)
	ct.add_curve(_circle(Vector3(0, 0, 0), 0.25, Vector3.BACK))
	ct.select(1)
	var bore: MeshInstance3D = ct.make_part("extrude", 3.0)
	bore.position = Vector3(0.0, 0.68, -1.5)
	check(ct.cut_from(bore, big), "bored")
	ed.select_part(big)
	check(ct.bake_solid(big), "baked")
	var st := _quad_stats(big)
	check(st[3] == 3 and st[2] == 0, "made as grids of quads, closed (dense %d, open %d - %s)" % [st[3], st[2], load("res://scripts/editor/mesh/edge_net.gd").grid_why])
	check(st[1] * 100 < st[0] * 15, "quads: %d of %d faces are triangles" % [st[1], st[0]])
	await _done(ed)


## A knife cut that stops inside a face (not across it from side to side) stays an edge of the mesh after
## the faces are laid out again - its points in triangles, joined by the mesh's own sides; a whole Remesh too.
func test_knife_cut_ending_inside_a_face_stays_in_the_mesh() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.new_model(true)
	var bx: MeshInstance3D = ed.add_primitive("box")
	ct.convert_parts([bx])
	for k in 600:
		if bx.has_meta("curve_solid") or bx.has_meta("ecurve_failed"):
			break
		await tree.process_frame
	if not bx.has_meta("curve_solid"):
		check(false, "a box made of edges")
		await _done(ed)
		return
	var b := bx.get_aabb()
	var z := b.end.z
	var y2 := b.position.y + b.size.y * 0.37
	var eye := Vector3(0, y2, z + 3.0)
	var res: Dictionary = ct.knife_apply_to(bx, [{"pos": Vector3(b.position.x, y2, z), "eye": eye}, {"pos": Vector3(b.position.x + b.size.x * 0.55, y2 + b.size.y * 0.2, z), "eye": eye}])
	check(not res.has("error") and not (res.get("chains", []) as Array).is_empty(), "cut (%s)" % res.get("error", ""))
	var cut_ci := ((bx.get_meta("curve_solid") as Dictionary)["chains"] as Array).size() - 1
	var on_mesh := func(label: String) -> void:
		var s: Dictionary = bx.get_meta("curve_solid")
		var t: Array = s["mesh"]["t"]
		var used := {}
		var sides := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				used[int(t[i + j])] = true
				var a := int(t[i + j])
				var c := int(t[i + (j + 1) % 3])
				sides[Vector2i(mini(a, c), maxi(a, c))] = true
		var pts := (s["fv"] as Array).filter(func(e): return int(e[1]) == cut_ci)
		pts.sort_custom(func(x, y): return float(x[2]) < float(y[2]))
		check(pts.size() >= 2, "%s: the cut still an edge (%d points)" % [label, pts.size()])
		var loose := pts.filter(func(e): return not used.has(int(e[0]))).size()
		check_eq(loose, 0, "%s: every point of the cut in the mesh" % label)
		var gaps := 0
		for i in pts.size() - 1:
			var a := int(pts[i][0])
			var c := int(pts[i + 1][0])
			gaps += 0 if sides.has(Vector2i(mini(a, c), maxi(a, c))) else 1
		check_eq(gaps, 0, "%s: the cut's points joined by the mesh's sides" % label)
	on_mesh.call("cut")
	ct.remesh_solid(bx, "Lay out (the knife's faces)", res.get("chains", []))
	var t_end := Time.get_ticks_msec() + 60000
	while ct.has_meta("remesh_job") and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	on_mesh.call("its faces laid out")
	ct.remesh_solid(bx)
	t_end = Time.get_ticks_msec() + 60000
	while ct.has_meta("remesh_job") and Time.get_ticks_msec() < t_end:
		await tree.process_frame
	on_mesh.call("remeshed")
	await _done(ed)
