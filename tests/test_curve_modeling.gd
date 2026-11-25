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
	check(circ.size() == 64, "a circle: 64 points (%d)" % circ.size())
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
	check(through < 0.05, "through the third point (%.3f)" % through)
	check(CT.circumcentre(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0) == Vector3.INF, "three in a row: no circle")
	# a rectangle's corners rounded: the arcs stay inside the corners
	var r := _rect(1.0, 1.0)
	r["radii"] = PackedFloat32Array([0.2, 0.2, 0.2, 0.2])
	var rs := CT.sample(r)
	check(rs.size() > 12, "rounded corners add points (%d)" % rs.size())
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
	check((j["ctrl"] as PackedVector3Array).size() == 3, "joined at the shared end: 3 points (%d)" % (j["ctrl"] as PackedVector3Array).size())
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
	check(open_m != null and Shapes.open_edges(open_m) > 0, "an open curve extrudes into a wall (open)")
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
	check(tabs != null and tabs.get_tab_count() == 2, "the right panel has two tabs")
	check(tabs.get_tab_title(1) == "Curve modeling", "the second: Curve modeling (%s)" % tabs.get_tab_title(1))
	ed.show_right_tab(1)
	check(ed.curve_tab_shown(), "shown on asking")
	var m: PopupPanel = ed.menu(Vector2(200, 200))
	var mt: TabBar = m.find_child("MenuTabs", true, false)
	check(mt != null and mt.tab_count == 2, "the right-click menu has two tabs")
	var cp: Control = m.find_child("CurvePage", true, false)
	check(cp != null and cp.find_child("Menu_Extrude", true, false) != null, "its Curve modeling page has Extrude")
	check(cp.find_child("Menu_Line", true, false) != null, "... and the sketch tools")
	# every button on both pages has a tooltip
	for b in m.find_children("Menu_*", "Button", true, false):
		check((b as Button).tooltip_text != "", "tooltip on " + str(b.name))
	mt.current_tab = 0
	check(not cp.visible, "switching tabs shows the other page")
	m.hide()
	# the panel's buttons all have tooltips and icons
	var page: Control = tabs.get_child(1)
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
	check(ed.curve_tab_shown(), "the Curve modeling tab shown with it")
	check(ct.click(ct._screen(Vector3(0.01, 0, -0.01))), "first corner clicked")
	check(ct.click(ct._screen(Vector3(0.49, 0, 0.31))), "the opposite corner")
	check(ct.curves.size() == 1, "a rectangle made (%d curves)" % ct.curves.size())
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
	check(ct.curves.size() == 2 and (ct.curves[1]["ctrl"] as PackedVector3Array).size() == 3, "an open line of three points")
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
	check(part != null and ed.parts().size() == n0 + 1, "extruded: a new part")
	if part:
		check(Shapes.open_edges(part.mesh) == 0, "closed solid")
		check(absf(Shapes.volume(part.mesh) - 0.5 * 0.3 * 0.2) < 0.001, "0.5 x 0.3 x 0.2 (%.4f)" % Shapes.volume(part.mesh))
	ed.undo()
	check(ed.parts().size() == n0, "undo removes the part")
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
	check(ct.curves[0].has("radii") and is_equal_approx((ct.curves[0]["radii"] as PackedFloat32Array)[0], 0.05), "corners rounded, kept on the curve")
	ct.select(0)
	ct.begin_offset()
	ct.op["value"] = 0.1
	ct._op_update()
	ct.confirm_op()
	check(ct.curves.size() == 4, "offset: a new curve (%d)" % ct.curves.size())
	await _done(ed)


func test_keys_and_saving() -> void:
	var ed := await _editor()
	var ct = ed.curve_tools
	ed.show_right_tab(1)
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_L
	check(ct.key(k), "L in the Curve modeling tab: the line tool")
	check(ct.tool == "line", "line on")
	ct.stop()
	ed.show_right_tab(0)
	check(not ct.key(k), "in the Mesh tab L is the mesh's own")
	# kept beside the model, read back
	ct.curves = [_rect(1, 2), _circle(Vector3(0, 1, 0), 0.3, Vector3.BACK)]
	ct.curves[0]["radii"] = PackedFloat32Array([0.1, 0, 0, 0.1])
	var f := "user://test_curves/model.glb"
	DirAccess.make_dir_recursive_absolute("user://test_curves")
	ct.save_beside(f)
	check(FileAccess.file_exists(f + ".curves.json"), "saved beside the model")
	var back := CT.from_json(JSON.parse_string(FileAccess.get_file_as_string(f + ".curves.json"))["curves"])
	check(back.size() == 2 and str(back[1]["kind"]) == "circle", "read back: both curves")
	check(is_equal_approx((back[0]["radii"] as PackedFloat32Array)[0], 0.1), "with their corner radii")
	check((back[1]["n"] as Vector3).is_equal_approx(Vector3.BACK), "and their planes")
	ct.curves = []
	ct.save_beside(f)
	check(not FileAccess.file_exists(f + ".curves.json"), "no curves: the file's removed")
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
	check(absf(_vol(part) - 0.2) < 1e-3, "the curve widened to 2 m: the solid follows (%.4f)" % _vol(part))
	check(part.mesh.surface_get_material(0) == mat, "its material kept")
	check(Shapes.open_edges(part.mesh) == 0, "still closed")
	ed.undo()
	check(absf(_vol(part) - 0.1) < 1e-3, "undo: the curve and the solid back (%.4f)" % _vol(part))
	ed.redo()
	check(absf(_vol(part) - 0.2) < 1e-3, "redo: wide again")
	# corners filleted on the curve: the solid's corners round
	ct.select(0)
	ct.begin_fillet_corners()
	ct.op["value"] = 0.1
	ct._op_update()
	ct.confirm_op()
	check(_vol(part) < 0.2 - 1e-4 and _vol(part) > 0.19, "corners rounded on the curve: the solid's too (%.4f)" % _vol(part))
	# its settings: the height
	ed.select_part(part)
	ct.set_spec("value", 0.4)
	check(_vol(part) > 0.38, "height 0.4: made again (%.4f)" % _vol(part))
	check((ct._w("solid_box") as Control).visible, "the SOLID box shows for it")
	check(is_equal_approx((ct._w("solid_value") as SpinBox).value, 0.4), "showing its height")
	ed.undo()
	check(_vol(part) < 0.2, "undo: height 0.2 again (%.4f)" % _vol(part))
	ct.pick_part_curves()
	check(ct.sel == [0], "Pick its curves picks the rectangle")
	# a copy of the part (duplicate) follows the same curves: an instance
	ed.duplicate_part()
	var copy: MeshInstance3D = ed.part
	check(copy != part and copy.has_meta("curve_solid"), "a duplicate keeps the recipe")
	# a curve deleted: the solids stay as they were
	var v0 := _vol(part)
	ct.select(0)
	ct.delete_selected()
	check(is_equal_approx(_vol(part), v0), "its curve deleted: it stays as it is")
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
	check(is_equal_approx(_vol(part), v0), "the curve changed: the plain mesh didn't")
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
	check(own.has(int(ct.curves[0]["id"])) and (own[int(ct.curves[0]["id"])] as Transform3D).origin.is_equal_approx(Vector3(0.5, 0.7, 0)), "the curve is placed by its solid")
	# picked where it's drawn now (with the part), not where its points were
	ct.select(-1)
	check(ct.pick(ct._screen(Vector3(1.0, 0.7, 0.0))) == 0, "picked at its new place")
	ct.select(0)
	var h: Array = ct.pick_handle(ct._screen(Vector3(1.5, 0.7, 0.0)))
	check(h == [0, 1], "its corner handle where it's drawn (%s)" % [h])
	# a copy made from it lands where it shows
	ct.duplicate_selected()
	var dk: PackedVector3Array = ct.curves[1]["ctrl"]
	check(absf(dk[0].y - 0.7) < 1e-5, "a copy of a placed curve shows where it does (y %.2f)" % dk[0].y)
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
	_closed_solid(CT.extrude_mesh(cut, 0.1), "the cut curves extruded", (1.0 - PI * 0.04) * 0.1, 0.01)
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
	check(absf(v1 - (1.0 - PI * 0.09) * 0.4) < 0.01, "the hole's curve widened: the hole is wider (%.4f)" % v1)
	# A's curve changed: follows too
	before = ct._state()
	k = ct.curves[0]["ctrl"]
	k[1].x = 2.0
	k[2].x = 2.0
	ct.curves[0]["ctrl"] = k
	ct._changed("Wider block", before)
	check(Shapes.volume(a.mesh) > v1 + 0.3, "the block's curve widened: the result too (%.4f)" % Shapes.volume(a.mesh))
	check(ct.owner_xfs().has(int(ct.curves[1]["id"])), "B's curves still placed (through the recipe)")
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
		check(k.size() <= 12, "few points: %d (the boolean gave ~40)" % k.size())
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
	check(u.size() == 1 and (u[0]["ctrl"] as PackedVector3Array).size() <= 14, "two circles: one lean path (%d points)" % ((u[0]["ctrl"] as PackedVector3Array).size() if u.size() == 1 else -1))
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
	check((full["ctrl"] as PackedVector3Array).size() > 30, "a dense line to start (%d points)" % (full["ctrl"] as PackedVector3Array).size())
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
	check(k.size() <= 12, "simplified to %d points" % k.size())
	check(int(ct.curves[0]["id"]) == id0, "the same curve (its id kept)")
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
		check(r.size() == 1, "%s: one curve" % op)
		if r.size() != 1:
			continue
		var off := _off_circles(r[0], circles)
		check(off < 0.002, "%s: on the true circles (%.4f m off at worst)" % [op, off])
		check((r[0]["ctrl"] as PackedVector3Array).size() <= 14, "%s: lean (%d points)" % [op, (r[0]["ctrl"] as PackedVector3Array).size()])
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
	check(near < 1e-3, "a moved point: the curve still passes through it (%.5f)" % near)


func test_small_intersections_stay_lean() -> void:
	# a small lens where a big circle and a small one overlap: two arcs, two corners
	var big := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(-1.7, 0, -0.35), Vector3(-0.8, 0, -0.85)]), "closed": true, "n": Vector3.UP}
	var small := {"kind": "circle", "ctrl": PackedVector3Array([Vector3(-0.45, 0, -0.45), Vector3(-0.05, 0, -0.75)]), "closed": true, "n": Vector3.UP}
	for order in [[small, big], [big, small]]:
		var r: Array = CT.curve_bool(order, "intersect")
		check(r.size() == 1, "one lens")
		if r.size() == 1:
			var k: PackedVector3Array = r[0]["ctrl"]
			check(k.size() == 4, "the lens: 2 corners + an arc's middle each (%d points)" % k.size())
			var circles := [[Vector3(-1.7, 0, -0.35), Vector3(-1.7, 0, -0.35).distance_to(Vector3(-0.8, 0, -0.85))], [Vector3(-0.45, 0, -0.45), 0.5]]
			check(_off_circles(r[0], circles) < 0.002, "on the true circles")
	# a tiny square cut by a big circle: straight sides stay straight, the arc an arc
	var sq := _rect(0.2, 0.2)
	var c := _circle(Vector3(0.2, 0, 0.2), 0.12)
	var r2: Array = CT.curve_bool([sq, c], "intersect")
	check(r2.size() == 1 and (r2[0]["ctrl"] as PackedVector3Array).size() <= 5, "a quarter disc: corner, two sides, an arc (%d points)" % ((r2[0]["ctrl"] as PackedVector3Array).size() if r2.size() == 1 else -1))


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
	check(_key(ct, KEY_G), "G with a curve picked: move it")
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
	var union: Button = ct._panel_btns["op_Union curves"][0]
	check(union.disabled, "one curve picked: Union off")
	ct.select(1, true)
	for n in ["Union curves", "Subtract curves", "Intersect curves", "Join curves", "Bridge curve", "Loft", "Sweep"]:
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
			check(not (c["callable"] as Callable).is_custom() or (c["callable"] as Callable).get_object() == ct, "%s: pressed goes to a method of the curve tools" % k)
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
	check(ed.parts().size() == 1, "the cutter's part went into the cut")
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
	check(ed.parts().size() == 2 and absf(Shapes.volume(block.mesh) - 0.4) < 1e-3, "positive again: the block whole, the cutter a part")
	var cutter: MeshInstance3D = ed.parts()[1]
	check(cutter.has_meta("curve_solid") and absf(Shapes.volume(cutter.mesh) - PI * 0.09 * 0.2) < 0.005, "the cutter: the 0.3-radius disc, still following its curve")
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
	check(drawn[0] > 0, "the curves' layer redrawn as their solid moved (%d)" % drawn[0])
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
	check(ed.parts().size() == 2 and str(block.get_meta("curve_solid")["kind"]) == "extrude", "separated: the block plain, the cutter a part")
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
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "separated: no ghost (the cutter's a part again)")
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
	check(spins.size() == 3, "the step's height + each curve's own (%d)" % spins.size())
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
	check(str(solid.name) in texts and "Box" in texts, "solids and meshes listed (%s)" % [texts])
	check("Curve 3" in texts or "Circle 3" in texts, "the curve in no solid listed")
	# select a solid's curve and the loose curve from the tree: both picked
	t.deselect_all()
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("curve") and int(m["curve"]) in [1, 2]:
			it.select(0)
	ct._tree_apply()
	check(ct.sel.size() == 2 and 1 in ct.sel and 2 in ct.sel, "two curves picked from the overview (%s)" % [ct.sel])
	# select the solid and the box together
	t.deselect_all()
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("part"):
			it.select(0)
	ct._tree_apply()
	check(ed.selected_parts().size() == 2, "both parts selected from the overview")
	# hide a curve with the eye: not drawn, not picked
	for it in _tree_items(t):
		var m = it.get_metadata(0)
		if m is Dictionary and m.has("curve") and int(m["curve"]) == 2:
			ct._tree_button(it, 1, 0, MOUSE_BUTTON_LEFT)
			break
	check(ct.curves[2].get("hidden", false), "the eye hid the curve")
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
	check((ct.get_meta("ghost_nodes", []) as Array).is_empty(), "its curve hidden: its ghost hidden")
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
	check(not ct.curves[1].get("hidden", false), "its curve still shown")
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
	check(_menu_pick(ct, pm, "Cut from Block"), "a loose curve: Attach to › Cut from Block")
	check(str(block.get_meta("curve_solid")["kind"]) == "bool", "the curve a cut step of Block")
	pm = ct.tree_menu({"curve": 2, "of": block, "leaf": ["b"]})
	check(_menu_pick(ct, pm, "Detach from Block"), "Detach from Block")
	check(str(block.get_meta("curve_solid")["kind"]) == "extrude", "its step gone with it")
	# delete a curve, delete a solid
	pm = ct.tree_menu({"curve": 2})
	_menu_pick(ct, pm, "Delete")
	check(ct.curves.size() == 2, "the curve deleted")
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
	check(g != null and ct.is_group(g) and ct.group_parts(g).size() == 2, "a part made of the two solids")
	check(ct.group_of(a) == g and ed.parts().size() == 2, "they're in it - still parts of the model")
	# the Mesh tab's list: the part a row, its solids under it
	var root: TreeItem = ed._parts.get_root()
	var top := root.get_children()
	check(top.size() == 1 and top[0].get_metadata(0) == g and top[0].get_child_count() == 2, "the Mesh tab lists the part with its solids under it")
	# selecting the part's row selects its solids
	ed._parts.deselect_all()
	top[0].select(0)
	ed._sync_tree_selection()
	check(ed.selected_parts().size() == 2, "the part's row selects both solids")
	# the curve overview: the part at the top, its solids under it
	ct._refresh_panel()
	var t: Tree = ct._w("tree")
	var first: TreeItem = t.get_root().get_child(0)
	check(first.get_metadata(0) is Dictionary and first.get_metadata(0).has("group") and first.get_child_count() == 2, "the overview: the part first, its solids under it")
	# a new solid made with a solid of the part selected goes into the part
	ed.select_part(a)
	ct.add_curve(_circle(Vector3(0, 0, 2), 0.2))
	ct.select(2)
	var c: MeshInstance3D = ct.make_part("extrude", 0.3)
	check(ct.group_of(c) == g, "a new solid joins the selected solid's part")
	# moving the part moves its solids - and their curves with them
	g.position += Vector3(0, 1, 0)
	var own: Dictionary = ct.owner_xfs()
	check(absf((own[int(ct.curves[0]["id"])] as Transform3D).origin.y - 1.0) < 1e-5, "the part moved: its solids' curves with it")
	# G with the part's row selected: the part moves as one (its node), undone in one step
	ed._parts.deselect_all()
	ed._fill_parts()
	ed._parts.get_root().get_child(0).select(0)
	ed._sync_tree_selection()
	check(ed.xf_nodes() == [g], "all its solids selected: the transform moves the part itself")
	var gy := g.global_position.y
	ed.begin_transform("G")
	ed._set_xfs(ed.xf, Transform3D(Basis(), Vector3(0, 0.5, 0)))
	ed.confirm_transform()
	check(absf(g.global_position.y - gy - 0.5) < 1e-5 and absf(a.position.y) < 1e-5, "moved the part, its solids kept in it")
	ed.undo()
	check(absf(g.global_position.y - gy) < 1e-5, "undone in one step")
	# two loose-ish solids: one of the part only - it alone moves
	ed.select_part(a)
	check(ed.xf_nodes() == [a], "one solid of the part selected: just it")
	# Rename: the menu's item opens the part's row for typing (its plain name); typed - renamed, one undo step
	ed._fill_parts()
	check(_menu_pick(ct, ct.parts_menu(g), "Rename"), "the part's menu has Rename")
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
	check(_menu_pick(ct, pm, "(no part - the top)"), "Move to › out of the part")
	check(ct.group_of(c) == null, "out")
	pm = ct.parts_menu(g)
	check(_menu_pick(ct, pm, "Ungroup"), "Ungroup")
	check(ct.groups().is_empty() and ed.parts().size() == 3, "the part gone, its solids kept")
	ed.undo()
	check(ct.groups().size() == 1 and ct.group_parts(ct.groups()[0]).size() == 2, "undo: the part back")
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
		check(found.size() == 1 and ct.is_group(found[0]), "the part comes back as a part")
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
	check(ed.parts().size() == n_parts, "the tool solids were steps - no parts left behind")
	check(absf(Shapes.volume(block.mesh) - v0) < 0.002, "the same solid (%.4f vs %.4f)" % [Shapes.volume(block.mesh), v0])
	# its edges: the block's 12 straight ones, the hole's rim top and bottom, the pocket's mouth and floor
	var kinds := {}
	for id in baked["ids"]:
		var c: Dictionary = ct.curve_by_id(int(id))
		kinds[c["kind"]] = int(kinds.get(c["kind"], 0)) + 1
	check(int(kinds.get("line", 0)) == 12 and int(kinds.get("circle", 0)) == 4 and kinds.size() == 2, "12 straight edges, 4 round ones (%s)" % [kinds])
	check(ct.curves.size() == 16, "only its edges - the old curves gone (%d)" % ct.curves.size())
	for id in baked["ids"]:
		check((ct.curve_by_id(int(id))["ctrl"] as PackedVector3Array).size() <= 2, "each edge a few points")
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
	check(not knob.is_inside_tree() and far.is_inside_tree(), "the touching solid baked in (gone as a part); the far one kept")
	check(ed.parts().size() == 2, "the baked solid and the far one")
	check(absf(Shapes.volume(block.mesh) - (v0 + vk - overlap)) < 0.01, "their union (%.4f vs %.4f)" % [Shapes.volume(block.mesh), v0 + vk - overlap])
	var spec: Dictionary = block.get_meta("curve_solid")
	check(str(spec.get("kind")) == "edges", "one baked solid: the block and the knob joined, its edges its curves")
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
	check(absf(q.y - 0.3) < 0.02 and absf(q.x - 1.0) < 0.02, "the point went up along Y (%s)" % q)
	# a baked solid of it follows: its corner lifted 0.3 with the point
	var spec := {"kind": "baked", "ids": [int(ct.curves[0]["id"])], "value": 0.2, "segs": 30, "axis": -1}
	var m: ArrayMesh = ct.solid_of(spec)
	var hi := -INF
	for vtx in m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if (vtx as Vector3).distance_to(Vector3(1, (vtx as Vector3).y, 1)) < 1e-3:
			hi = maxf(hi, (vtx as Vector3).y)
	check(absf(hi - (q.y + 0.2)) < 0.02, "the baked solid's corner rose with the point (top %.3f)" % hi)
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
	check(ct._hidden(mx * Vector3(0.7, 0, 0.5)), "a curve under the block's top is hidden from above")
	check(not ct._hidden(mx * Vector3(0.5, 0.4, 0.0)), "the top's own edge isn't hidden by the face it bounds")
	check(not ct._hidden(mx * Vector3(1.5, 0, 0.5)), "a point beside the block shows")
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
	check(ct.view_input(ev), "the double-click was the curve tools'")
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(k.size() == 5 and k[1].distance_to(Vector3(0.5, 0, 0)) < 0.02, "a point put in between the first two (%s)" % k)
	ed.undo()
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() == 4, "undone")
	# a circle: a path through points on it, the same shape, the new point where clicked
	var before: PackedVector3Array = CT.sample(ct.curves[1])
	var on := Vector3(3, 0, 0.5) + Vector3(0.5, 0, 0).rotated(Vector3.UP, 1.0)
	check(ct.insert_point(ed.view.project(mx * on)), "a point put into the circle")
	var c: Dictionary = ct.curves[1]
	check(str(c["kind"]) == "path" and (c["ctrl"] as PackedVector3Array).size() == 9, "the circle as a path of 9 points (%s %d)" % [c["kind"], (c["ctrl"] as PackedVector3Array).size()])
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
	check((spec.get("fv", []) as Array).size() > 0 and spec.get("tied", false), "its side rows made its edge's points")
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
	check(items.size() == 2 and str(items[0][1]) == "Smooth point" and bool(items[0][5]) and not bool(items[1][5]), "a line's corner: Smooth on offer, Sharp not (%s)" % [items.map(func(x): return [x[1], x[5]])])
	var groups: Array = ct.menu_groups(at)
	check(str(groups[0][0][1]) == "Smooth point", "first in the right-click menu")
	(items[0][4] as Callable).call()
	var c: Dictionary = ct.curves[0]
	check(str(c["kind"]) == "path" and (c["sharp"] as PackedByteArray) == PackedByteArray([1, 0, 1, 1]), "a path now, that point smooth (%s %s)" % [c["kind"], c.get("sharp")])
	var s := CT.sample(c)
	var bent := false
	for q in s:
		if q.x > 1.02:
			bent = true   # (the side round the smooth point bulges past the old corner's line)
	check(bent and s.size() > 8, "curved through it (%d points)" % s.size())
	(ct.point_items(at)[1][4] as Callable).call()
	check((ct.curves[0]["sharp"] as PackedByteArray)[1] == 1, "sharp again")
	check(CT.sample(ct.curves[0]).size() == 4, "straight sides again")
	ed.undo()
	ed.undo()
	check(str(ct.curves[0]["kind"]) == "line", "undone to the line")
	check(ct.point_items(Vector2(-500, -500)).is_empty(), "nothing away from a point")
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
	check(ct.view_input(ev), "the double-click on the point was the curve tools'")
	var k: PackedVector3Array = ct.curves[0]["ctrl"]
	check(k.size() == 3 and not Vector3(1, 0, 0) in k, "that corner gone - a triangle (%s)" % k)
	ev.position = ct._screen(Vector3(1, 0, 1))
	ct.view_input(ev)
	check((ct.curves[0]["ctrl"] as PackedVector3Array).size() == 3, "a closed curve keeps three points")
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
	check(out > 1.08, "the edge's middle went out (x %.3f; %d points on it)" % [out, n_on])
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
	check(absf(q.y - 0.3) < 1e-6, "snapped to the other point's height (%.4f)" % q.y)
	var gs: Array = ct._drag.get("guides", [])
	check(gs.size() == 1 and str(gs[0]["kind"]) == "point", "a guide from that point (%s)" % [gs.map(func(g): return g["kind"])])
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
	check(inner > 5, "points inside the top face (%d)" % inner)
	var k: PackedVector3Array = ct.curves[top]["ctrl"]
	k[1] = Vector3(0.55, 0.4, 0.5)   # (the arc's middle pushed 0.15 into the block)
	ct.curves[top]["ctrl"] = k
	ct.refresh_solids()
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
	check(on_top > 10 and area_bad < area_all * 0.01, "the top face faces up - turned over: %d of %d, %.3f%% of it" % [flipped, on_top, area_bad / maxf(area_all, 1e-9) * 100.0])
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
	ct._changed("Move curve point", before)
	var spec: Dictionary = cyl.get_meta("curve_solid")
	var n1: int = (spec["mesh"]["t"] as Array).size() / 3
	check(JSON.stringify(spec["c0"][str(int(ct.curves[top]["id"]))]) == JSON.stringify(ct.to_json([ct.curves[top]])[0]), "settled: its curves now its start")
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
