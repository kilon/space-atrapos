extends TestCase
## The mesh editor's Fillet (Ctrl+B; mesh/mesh_bevel.gd, driven by mesh/mesh_ops.gd): a box's edges
## rounded into strips of quads - the counts of points and faces, the box still closed, its volume a
## little less, segments 1 a chamfer, the corners where filleted edges meet, one undo step.

const SCENE := "res://scenes/editor/mesh_editor.tscn"
const MeshBevel := preload("res://scripts/editor/mesh/mesh_bevel.gd")
const Shapes := preload("res://scripts/editor/mesh/shapes.gd")


func _box_editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	ed.add_primitive("box")
	ed.enter_edit(true)
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


## The shown edges of the box (12), or those with both ends at coordinate `axis` = `v`.
func _edges(em, axis := -1, v := 0.0) -> PackedInt32Array:
	var out := PackedInt32Array()
	for e in em.edge_count():
		if em.edge_inner[e]:
			continue
		if axis >= 0 and (absf(em.points[em.edges[e * 2]][axis] - v) > 1e-4 or absf(em.points[em.edges[e * 2 + 1]][axis] - v) > 1e-4):
			continue
		out.append(e)
	return out


## The edge from (x0, y0, z0) to (x1, y1, z1).
func _edge_at(em, a: Vector3, b: Vector3) -> int:
	var pa := -1
	var pb := -1
	for p in em.points.size():
		if em.points[p].distance_to(a) < 1e-4:
			pa = p
		elif em.points[p].distance_to(b) < 1e-4:
			pb = p
	return em.edge(pa, pb) if pa >= 0 and pb >= 0 else -1


func _closed(em) -> int:
	em.update_mesh()
	return Shapes.open_edges(em.mesh)


func _volume(em) -> float:
	em.update_mesh()
	return absf(Shapes.volume(em.mesh))


func test_one_edge() -> void:
	var ed := await _box_editor()
	var em = ed.em
	check_eq(em.points.size(), 8, "a box: eight points")
	check_eq(em.poly_count(), 6, "six faces")
	check_eq(_edges(em).size(), 12, "twelve edges")
	var v0 := _volume(em)
	var e := _edge_at(em, Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5))
	check(e >= 0, "the top right edge")
	var r: Dictionary = MeshBevel.fillet(em, PackedInt32Array([e]), 0.1, 4)
	check(r["ok"], "filleted: %s" % r["msg"])
	# each end: its corner gone, two points along the box's sides and three on the arc between
	check_eq(em.points.size(), 8 - 2 + 2 * 5, "sixteen points")
	check_eq((r["new_points"] as PackedInt32Array).size(), 10, "ten of them new")
	check_eq(em.poly_count(), 6 + 4, "four quads across the edge (the end faces get the arcs as corners)")
	check_eq(_closed(em), 0, "still closed")
	var v1 := _volume(em)
	check(v1 < v0 and v1 > v0 - 0.1 * 0.1 * 0.5, "the volume a little less (%f -> %f)" % [v0, v1])
	# the arc: every new point 0.1 from the edge's inner line (a circle's quarter)
	var c := Vector2(0.4, 0.4)
	for p in r["new_points"]:
		var q: Vector3 = em.points[p]
		if q.x > 0.4 + 1e-4 and q.y > 0.4 + 1e-4:
			check(absf(Vector2(q.x, q.y).distance_to(c) - 0.1) < 1e-4, "on the arc: %s" % q)
	await _done(ed)


func test_chamfer() -> void:
	var ed := await _box_editor()
	var em = ed.em
	var v0 := _volume(em)
	var e := _edge_at(em, Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5))
	var r: Dictionary = MeshBevel.fillet(em, PackedInt32Array([e]), 0.1, 1)
	check(r["ok"], "chamfered")
	check_eq(em.points.size(), 10, "the edge's two ends each made two")
	check_eq(em.poly_count(), 7, "one flat face across")
	check_eq(_closed(em), 0, "still closed")
	check(absf(_volume(em) - (v0 - 0.1 * 0.1 * 0.5)) < 1e-5, "a prism 0.1 x 0.1 / 2 cut off")
	await _done(ed)


func test_all_edges() -> void:
	var ed := await _box_editor()
	var em = ed.em
	var v0 := _volume(em)
	var r: Dictionary = MeshBevel.fillet(em, _edges(em), 0.1, 4)
	check(r["ok"], "every edge filleted")
	check_eq(r["edges"], 12, "twelve edges")
	# each corner: three points in from it, three arcs of three, a fan's middle
	check_eq(em.points.size(), 8 * (3 + 9 + 1), "104 points")
	check_eq(em.poly_count(), 6 + 12 * 4 + 8 * 12, "six faces, 48 quads, a fan of 12 at each corner")
	check_eq(_closed(em), 0, "still closed")
	var v1 := _volume(em)
	# (less taken off than a chamfer as wide would: 12 prisms 0.1 x 0.1 / 2 x 0.8 and the corners)
	check(v1 < v0 and v1 > v0 - 0.035, "the volume a little less (%f -> %f)" % [v0, v1])
	# the corner fan's middle: about on the ball rounding the corner (0.1 round (0.4, 0.4, 0.4))
	var far := 0.0
	for p in em.points.size():
		var q: Vector3 = em.points[p]
		far = maxf(far, q.length())
	check(far < Vector3(0.4, 0.4, 0.4).length() + 0.1 + 1e-3, "nothing out past the rounded corners (%f)" % far)
	# chamfered all round: still closed, each corner a triangle
	var ed2 := await _box_editor()
	var r2: Dictionary = MeshBevel.fillet(ed2.em, _edges(ed2.em), 0.1, 1)
	check(r2["ok"], "chamfered all round")
	check_eq(ed2.em.points.size(), 24, "three points at each corner")
	check_eq(ed2.em.poly_count(), 6 + 12 + 8, "a face an edge, a triangle a corner")
	check_eq(_closed(ed2.em), 0, "still closed")
	await _done(ed2)
	await _done(ed)


func test_corners() -> void:
	# two edges meeting at a corner (the third not): their arcs welded into a mitre
	var ed := await _box_editor()
	var em = ed.em
	var es := PackedInt32Array([_edge_at(em, Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5)), _edge_at(em, Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5))])
	var r: Dictionary = MeshBevel.fillet(em, es, 0.1, 3)
	check(r["ok"], "two edges")
	check_eq(_closed(em), 0, "closed")
	check_eq(em.poly_count(), 6 + 2 * 3, "two strips of three, nothing more at the shared corner")
	# a ring of four round the top: each corner two arcs, welded
	var ed2 := await _box_editor()
	var r2: Dictionary = MeshBevel.fillet(ed2.em, _edges(ed2.em, 1, 0.5), 0.1, 4)
	check(r2["ok"], "the top's four edges")
	check_eq(_closed(ed2.em), 0, "closed")
	check_eq(ed2.em.poly_count(), 6 + 16, "four strips of four")
	# three at one corner, segments 3
	var ed3 := await _box_editor()
	var c := Vector3(0.5, 0.5, 0.5)
	var es3 := PackedInt32Array([_edge_at(ed3.em, Vector3(-0.5, 0.5, 0.5), c), _edge_at(ed3.em, Vector3(0.5, -0.5, 0.5), c), _edge_at(ed3.em, Vector3(0.5, 0.5, -0.5), c)])
	var r3: Dictionary = MeshBevel.fillet(ed3.em, es3, 0.15, 3)
	check(r3["ok"], "three at a corner")
	check_eq(_closed(ed3.em), 0, "closed")
	# nothing to fillet
	var ed4 := await _box_editor()
	var r4: Dictionary = MeshBevel.fillet(ed4.em, PackedInt32Array(), 0.1, 4)
	check(not r4["ok"], "no edges: nothing done")
	check_eq(ed4.em.points.size(), 8, "the box as it was")
	for x in [ed, ed2, ed3, ed4]:
		await _done(x)


func test_interactive_and_undo() -> void:
	var ed := await _box_editor()
	var em = ed.em
	var e := _edge_at(em, Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5))
	ed.set_kind(1)
	ed.mesh_ops._select_edges(PackedInt32Array([e]), false)
	ed.mesh_ops.begin_fillet()
	check_eq(ed.xf.get("kind", ""), "FIL", "Ctrl+B: the fillet runs")
	for kc in [KEY_0, KEY_PERIOD, KEY_1]:
		var k := InputEventKey.new()
		k.keycode = kc
		k.pressed = true
		check(ed.mesh_ops.key(k), "a digit typed is taken")
	check(absf(ed.mesh_ops.fillet_width() - 0.1) < 1e-6, "typed 0.1")
	var minus := InputEventKey.new()
	minus.keycode = KEY_MINUS
	minus.pressed = true
	for i in 2:
		ed.mesh_ops.key(minus)
	check_eq(int(ed.xf["segments"]), 2, "two fewer segments (4 -> 2)")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	check(ed.mesh_ops.view_input(wheel), "the wheel is taken")
	check_eq(int(ed.xf["segments"]), 3, "the wheel: one more")
	ed.confirm_transform()
	em = ed.em
	check_eq(em.points.size(), 8 - 2 + 2 * 4, "three segments: two points along the sides and two on the arc, each end")
	check_eq(em.poly_count(), 6 + 3, "three quads")
	check_eq(_closed(em), 0, "closed")
	ed.undo()
	check_eq(ed.em.points.size(), 8, "one undo: the box again")
	check_eq(ed.em.poly_count(), 6, "six faces")
	check_eq(_closed(ed.em), 0, "closed")
	# cancelled: nothing changes
	ed.set_kind(1)
	ed.mesh_ops._select_edges(PackedInt32Array([_edge_at(ed.em, Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5))]), false)
	ed.mesh_ops.begin_fillet()
	ed._cancel_xf()
	check_eq(ed.em.points.size(), 8, "cancelled: as it was")
	# face mode: the selected face's border filleted
	ed.set_kind(2)
	ed.select_all(false)
	for t in ed.em.tri_count():
		var top := true
		for k in 3:
			top = top and absf(ed.em.points[ed.em.tris[t * 3 + k]].y - 0.5) < 1e-4
		if top:
			ed._set_poly(t, 1)
	ed._derive_sel()
	ed.mesh_ops.begin_fillet()
	check_eq(ed.xf.get("kind", ""), "FIL", "face mode: the fillet runs")
	ed.confirm_transform()
	check_eq(ed.em.poly_count(), 6 + 12, "the top's four edges, three segments each (as many as the last fillet)")
	check_eq(_closed(ed.em), 0, "closed")
	ed.undo()
	check_eq(ed.em.poly_count(), 6, "undone")
	await _done(ed)


func test_cylinder_and_sphere() -> void:
	# a cylinder's top rim (its cap an n-gon, its side smooth), every edge of a sphere and a torus: closed
	for kind in ["cylinder", "sphere", "torus"]:
		var ed: Control = load(SCENE).instantiate()
		tree.root.add_child(ed)
		await tree.process_frame
		ed.add_primitive(kind)
		ed.enter_edit(true)
		var em = ed.em
		var open0 := _closed(em)
		var top := -INF
		for p in em.points:
			top = maxf(top, p.y)
		var es := _edges(em, 1, top) if kind == "cylinder" else _edges(em)
		var r: Dictionary = MeshBevel.fillet(em, es, 0.02, 3)   # (on the sphere: held narrower near the poles)
		check(r["ok"], "%s: filleted (%s)" % [kind, r["msg"]])
		check_eq(_closed(em), open0, "%s: as closed as it was" % kind)
		await _done(ed)
