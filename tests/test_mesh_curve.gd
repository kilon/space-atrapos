extends TestCase
## The mesh editor's curve deform (V), flatten (Shift+Alt+F) - transforms of edit mode, one undo
## step each, proportional editing applying - and its reference images (kept per model).

const SCENE := "res://scenes/editor/mesh_editor.tscn"


func _editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


## A subdivided plane in edit mode, everything selected.
func _grid(ed: Control, cuts := 2) -> void:
	var p: MeshInstance3D = ed.add_primitive("plane")
	ed.select_part(p)
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	for i in cuts:
		ed.select_all(true)
		ed.subdivide()
	ed.select_all(true)
	ed._derive_sel()


static func _same(a: PackedVector3Array, b: PackedVector3Array, eps := 1e-5) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > eps:
			return false
	return true


func test_curve_maths() -> void:
	var DT: GDScript = load("res://scripts/editor/mesh/deform_tools.gd")
	var pts := PackedVector3Array()
	for i in 5:
		pts.append(Vector3(i * 0.25, 0.1, 0.0))   # (a row along X, a little above the line through it)
	var ids := PackedInt32Array([0, 1, 2, 3, 4])
	var line: Dictionary = DT.curve_line(pts, ids)
	check(not line.is_empty(), "a line laid along the row")
	check((line["crv_dir"] as Vector3).abs().is_equal_approx(Vector3.RIGHT), "along its longest extent (X)")
	check(is_equal_approx(line["crv_len"], 1.0), "from one end to the other (%.3f)" % line["crv_len"])
	var cp: PackedVector3Array = line["crv_p"]
	for p in pts:
		check(DT.curve_carry(p, line["crv_a0"], line["crv_dir"], line["crv_len"], cp).distance_to(p) < 1e-5, "straight: the points stay")
	var a0: Vector3 = line["crv_a0"]
	var bent := PackedVector3Array([cp[0], cp[1] + Vector3(0, 0.4, 0), cp[2] + Vector3(0, 0.4, 0), cp[3]])
	var mid: Vector3 = DT.curve_carry(pts[2], a0, line["crv_dir"], line["crv_len"], bent)
	check(absf(mid.y - (0.1 + 0.3)) < 1e-4, "the middle carried up by 3/4 of the handles' rise (%.4f)" % mid.y)
	check(DT.curve_line(PackedVector3Array([Vector3.ONE, Vector3.ONE]), PackedInt32Array([0, 1])).is_empty(), "points at one place: no line")
	# best-fit plane: points spread on a tilted plane
	var tilted := PackedVector3Array()
	var n0 := Vector3(0.3, 1.0, -0.2).normalized()
	var u := n0.cross(Vector3.RIGHT).normalized()
	var v := n0.cross(u)
	for i in 6:
		for j in 4:
			tilted.append(Vector3(2, 1, 0) + u * (i * 0.3) + v * (j * 0.2))
	var all := PackedInt32Array()
	for i in tilted.size():
		all.append(i)
	var n: Vector3 = DT.fit_normal(tilted, all)
	check(absf(n.dot(n0)) > 0.9999, "the best-fit plane's normal found (%.5f)" % absf(n.dot(n0)))


func test_curve_deform() -> void:
	var ed := await _editor()
	await _grid(ed)
	ed.deform.set_snap(false)   # (a whole grid: bent as an area, offsets kept)
	var before: PackedVector3Array = ed.em.points.duplicate()
	var steps: int = ed._eundo.size()
	ed.deform.begin_curve()
	check_eq(ed.xf.get("kind", ""), "CRV", "curve deform started")
	check(_same(ed.em.points, before), "laid straight: nothing moved yet")
	check_eq(ed.view.curve_pts.size(), 4, "the curve drawn: two ends, two handles")
	var cp: PackedVector3Array = ed.xf["crv_p"]
	var dir: Vector3 = ed.xf["crv_dir"]
	var up := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	var bent := PackedVector3Array([cp[0], cp[1] + up * 0.4, cp[2] + up * 0.4, cp[3]])
	ed.deform.set_curve(bent)
	# the point nearest the line's middle rises 3/4 of the handles' rise
	var a0: Vector3 = ed.xf["crv_a0"]
	var ln: float = ed.xf["crv_len"]
	var mid := a0 + dir * (ln * 0.5)
	var best := -1
	for i in before.size():
		if best < 0 or before[i].distance_to(mid) < before[best].distance_to(mid):
			best = i
	var rise: float = ((ed.em.points[best] as Vector3) - before[best]).dot(up)
	check(absf(rise - 0.3) < 0.02, "the middle bent with the curve (%.3f of 0.3)" % rise)
	ed.confirm_transform()
	check(ed.xf.is_empty(), "kept")
	check_eq(ed._eundo.size(), steps + 1, "one undo step")
	for i in 3:
		await tree.process_frame
	check(ed.view.curve_pts.is_empty(), "the curve gone from the view")
	ed.undo()
	check(_same(ed.em.points, before), "undo: as it was")
	# cancelled: as it was
	ed.select_all(true)
	ed._derive_sel()
	ed.deform.begin_curve()
	ed.deform.set_curve(bent)
	ed._cancel_xf()
	check(_same(ed.em.points, before), "cancelled: as it was")
	# proportional editing: a point outside the selection pulled part of the way
	ed.select_points(PackedInt32Array([best]))
	var nb := -1
	for i in before.size():
		if i != best and (nb < 0 or before[i].distance_to(before[best]) < before[nb].distance_to(before[best])):
			nb = i
	ed.select_points(PackedInt32Array([best, nb]))
	ed.prop_on = true
	ed.prop_radius = 2.0
	ed.deform.begin_curve()
	var c2: PackedVector3Array = ed.xf["crv_p"]
	var d2: Vector3 = ed.xf["crv_dir"]
	var off := d2.cross(Vector3.UP).normalized() if absf(d2.y) < 0.9 else Vector3.RIGHT
	ed.deform.set_curve(PackedVector3Array([c2[0] + off * 0.2, c2[1] + off * 0.2, c2[2] + off * 0.2, c2[3] + off * 0.2]))
	var moved_out := 0
	for i in before.size():
		if i != best and i != nb and (ed.em.points[i] as Vector3).distance_to(before[i]) > 1e-4:
			moved_out += 1
	check(moved_out > 0, "proportional: neighbours pulled along (%d)" % moved_out)
	ed.confirm_transform()
	ed.prop_on = false
	await _done(ed)


## Snapped (the default): a row of points ends exactly on the curve, spaced along it by length as
## along the line; the toggle turns it off at once.
func test_curve_snaps_points_onto_it() -> void:
	var ed := await _editor()
	await _grid(ed)
	var DT: GDScript = load("res://scripts/editor/mesh/deform_tools.gd")
	check(ed.deform.snaps(), "snapping on by default")
	# a row: the points on one line of the grid (z = its middle row), a little bumped off it
	var em = ed.em
	var row := PackedInt32Array()
	for i in em.points.size():
		if absf(em.points[i].z) < 1e-4:
			row.append(i)
	check(row.size() >= 3, "a row of points (%d)" % row.size())
	for k in row.size():
		em.points[row[k]] += Vector3(0, 0.05 * (k % 2), 0)
	ed.select_points(row)
	ed.deform.begin_curve()
	var cp: PackedVector3Array = ed.xf["crv_p"]
	var dir: Vector3 = ed.xf["crv_dir"]
	var up := Vector3.UP
	var bent := PackedVector3Array([cp[0], cp[1] + up * 0.6, cp[2] - up * 0.4, cp[3] + up * 0.2])
	ed.deform.set_curve(bent)
	var table: PackedFloat32Array = DT.arc_table(bent, 512)
	var worst := 0.0
	for i in row:
		var p: Vector3 = ed.em.points[i]
		var best := INF
		for j in 513:
			best = minf(best, p.distance_to(DT.bez(bent, float(j) / 512.0)))
		worst = maxf(worst, best)
	check(worst < 0.01, "every selected point on the curve (worst %.4f m off)" % worst)
	# spaced by length: the ends on the curve's ends
	var ends := [INF, INF]
	for i in row:
		ends[0] = minf(ends[0], (ed.em.points[i] as Vector3).distance_to(bent[0]))
		ends[1] = minf(ends[1], (ed.em.points[i] as Vector3).distance_to(bent[3]))
	check(ends[0] < 1e-4 and ends[1] < 1e-4, "the end points on the curve's ends")
	ed.deform.set_snap(false)
	var off := 0.0
	for i in row:
		var p: Vector3 = ed.em.points[i]
		var best := INF
		for j in 513:
			best = minf(best, p.distance_to(DT.bez(bent, float(j) / 512.0)))
		off = maxf(off, best)
	check(off > 0.01, "snapping off: the bumped points keep their offsets (%.3f)" % off)
	ed.deform.set_snap(true)
	ed.confirm_transform()
	await _done(ed)


## The curve starts fitted through the points: an arc of points - nothing moves till it's changed,
## the curve passing through them; a tiny change moves them only a little; Reset puts them back.
func test_curve_starts_through_the_points() -> void:
	var ed := await _editor()
	await _grid(ed)
	var DT: GDScript = load("res://scripts/editor/mesh/deform_tools.gd")
	var em = ed.em
	var row := PackedInt32Array()
	for i in em.points.size():
		if absf(em.points[i].z) < 1e-4:
			row.append(i)
	for i in row:   # (the row bent into an arc first)
		var x: float = em.points[i].x
		em.points[i] = Vector3(x, 0.6 * (1.0 - x * x), 0.0)
	var before: PackedVector3Array = em.points.duplicate()
	ed.select_points(row)
	ed.deform.begin_curve()
	check(_same(ed.em.points, before), "begun: no point moved")
	var cp: PackedVector3Array = ed.xf["crv_p"]
	var worst := 0.0
	for i in row:
		worst = maxf(worst, (before[i] as Vector3).distance_to(DT.bez(cp, DT.nearest_t(cp, before[i]))))
	check(worst < 0.005, "the curve passes through the arc's points (worst %.4f m)" % worst)
	ed.deform.set_curve(cp)
	check(_same(ed.em.points, before), "set to itself: still nothing moved")
	var nudged := cp.duplicate()
	nudged[1] += Vector3(0, 0.001, 0)
	ed.deform.set_curve(nudged)
	var most := 0.0
	for i in row:
		most = maxf(most, (ed.em.points[i] as Vector3).distance_to(before[i]))
	check(most < 0.01, "a tiny change: the points move only a little (%.4f m)" % most)
	ed.deform.reset_curve()
	check(_same(ed.em.points, before), "Reset: back where they were")
	ed._cancel_xf()
	await _done(ed)


## Faces selected: the curve goes through their middles and carries them whole (no snapping -
## each keeps its shape), the middles following the curve.
func test_curve_carries_faces() -> void:
	var ed := await _editor()
	await _grid(ed)
	var DT: GDScript = load("res://scripts/editor/mesh/deform_tools.gd")
	var em = ed.em
	ed.set_kind(2)
	# a strip of faces: those whose middle is near z = the first row's
	ed.select_all(false)
	var zs := {}
	for t in em.tri_count():
		var c := Vector3.ZERO
		for p in em.poly_loop(t):
			c += em.points[p]
		c /= em.poly_loop(t).size()
		zs[snappedf(c.z, 0.001)] = true
	var z0: float = zs.keys().min()
	var strip := 0
	for t in em.tri_count():
		var c := Vector3.ZERO
		for p in em.poly_loop(t):
			c += em.points[p]
		c /= em.poly_loop(t).size()
		if absf(c.z - z0) < 1e-3:
			ed._set_poly(t, 1)
			strip += 1
	ed._derive_sel()
	check(strip >= 3, "a strip of faces picked")
	var before: PackedVector3Array = em.points.duplicate()
	ed.deform.begin_curve()
	check(ed.xf.get("crv_faces", false), "faces: the curve carries the faces")
	check(_same(ed.em.points, before), "begun: nothing moved")
	var cp: PackedVector3Array = ed.xf["crv_p"]
	var bent := PackedVector3Array([cp[0], cp[1] + Vector3.UP * 0.5, cp[2] + Vector3.UP * 0.5, cp[3]])
	ed.deform.set_curve(bent)
	var centres: PackedVector3Array = DT.face_centres(ed.em, ed.sel_t)
	var worst := 0.0
	for c in centres:
		worst = maxf(worst, c.distance_to(DT.bez(bent, DT.nearest_t(bent, c))))
	check(worst < 0.06, "the faces' middles on the curve - within a chord's sag of its bend (worst %.3f m, faces 0.5 m)" % worst)
	var moved := 0
	for i in ed.selected_points():
		if (ed.em.points[i] as Vector3).distance_to(before[i]) > 0.01:
			moved += 1
	check(moved > 0, "the faces moved with it")
	# kept whole: no face squashed onto the curve (each corner still apart from its face's middle)
	var flat := 0
	for t in em.tri_count():
		if ed.sel_t[t]:
			var a: Vector3 = ed.em.points[ed.em.tris[t * 3]]
			var b: Vector3 = ed.em.points[ed.em.tris[t * 3 + 1]]
			var c2: Vector3 = ed.em.points[ed.em.tris[t * 3 + 2]]
			if (b - a).cross(c2 - a).length() < 1e-4:
				flat += 1
	check_eq(flat, 0, "no face squashed flat")
	ed.confirm_transform()
	await _done(ed)


## The curve's handle dragged with the mouse in the view (a press on it, a move, a release).
func test_curve_dragged_in_the_view() -> void:
	var ed := await _editor()
	await _grid(ed)
	ed.view.set_view("front")
	ed.frame_all()
	await tree.process_frame
	var before: PackedVector3Array = ed.em.points.duplicate()
	ed.deform.begin_curve()
	var g: Transform3D = ed.part.global_transform
	var cp: PackedVector3Array = ed.xf["crv_p"]
	var at: Vector2 = ed.view.project(g * cp[1])
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	ed._view_input(mb)
	check_eq(int(ed.xf.get("crv_drag", -1)), 1, "a press on a handle takes it")
	var mm := InputEventMouseMotion.new()
	mm.position = at + Vector2(0, -60)
	ed._view_input(mm)
	mb = mb.duplicate()
	mb.pressed = false
	mb.position = mm.position
	ed._view_input(mb)
	check_eq(ed.xf.get("kind", ""), "CRV", "still curving after the drag (Enter keeps)")
	check(not _same(ed.em.points, before), "the points followed the handle")
	check(not (ed.xf["crv_p"] as PackedVector3Array)[1].is_equal_approx(cp[1]), "the handle moved")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	ed._unhandled_key_input(ev)
	check(ed.xf.is_empty(), "Enter: kept")
	await _done(ed)


func test_flatten() -> void:
	var ed := await _editor()
	await _grid(ed)
	# a bump in the middle of the grid
	var c0: Vector3 = ed.em.centroid(ed.selected_points())
	var mid := 0
	for i in ed.em.points.size():
		if (ed.em.points[i] as Vector3).distance_to(c0) < (ed.em.points[mid] as Vector3).distance_to(c0):
			mid = i
	ed.select_points(PackedInt32Array([mid]))
	ed.move_selection(Vector3(0, 0.3, 0))
	ed.select_all(true)
	ed._derive_sel()
	var bumped: PackedVector3Array = ed.em.points.duplicate()
	var steps: int = ed._eundo.size()
	ed.deform.begin_flatten()
	check_eq(ed.xf.get("kind", ""), "FLT", "flatten started")
	var n: Vector3 = ed.xf["flt_fit"]
	check(absf(n.y) > 0.95, "a flat grid: its best-fit plane level (%.3f)" % n.y)
	ed.xf["flt_f"] = 1.0
	ed._xf_update()
	ed.confirm_transform()
	check_eq(ed._eundo.size(), steps + 1, "one undo step")
	var c: Vector3 = ed.xf.get("flt_c", ed.em.centroid(ed.selected_points()))
	var worst := 0.0
	for i in ed.selected_points():
		worst = maxf(worst, absf(((ed.em.points[i] as Vector3) - c).dot(n)))
	check(worst < 1e-4, "all the way: every point on the plane (%.5f)" % worst)
	ed.undo()
	check(_same(ed.em.points, bumped), "undo: the bump back")
	# an axis plane (X typed), halfway
	ed.deform.begin_flatten()
	ed.deform.set_plane(0)
	ed.xf["flt_f"] = 0.5
	ed._xf_update()
	var cx: float = (ed.xf["flt_c"] as Vector3).x
	var ok := true
	for i in ed.selected_points():
		var want := lerpf(bumped[i].x, cx, 0.5)
		if absf((ed.em.points[i] as Vector3).x - want) > 1e-4:
			ok = false
	check(ok, "the X plane, halfway: each point halfway to the middle's X")
	ed._cancel_xf()
	check(_same(ed.em.points, bumped), "cancelled: as it was")
	await _done(ed)


func test_reference_images() -> void:
	var ed := await _editor()
	var file := ProjectSettings.globalize_path("user://test_ref_image.png")
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9))
	img.save_png(file)
	var ri = ed.ref_images
	ri.model_opened("res://test/ref_model.glb")
	check(ri.images.is_empty(), "a model with no reference images")
	var i: int = ri.add_file(file)
	for k in 200:
		if not ri.busy():
			break
		await tree.process_frame
	var q: MeshInstance3D = ri.quad_of(i)
	check(q != null and q.visible, "its quad in the view")
	if q == null:
		await _done(ed)
		return
	check(q.is_inside_tree() and ed.view.sv.is_ancestor_of(q), "in the view's own world")
	check(absf(q.transform.basis.x.length() - 2.0 * 2.0) < 1e-3, "as wide as the picture's shape (2:1 at 2 m high)")
	var m: ShaderMaterial = q.material_override
	check(m.get_shader_parameter("far") == true and not "depth_test_disabled" in m.shader.code, "behind: at the far plane, depth tested")
	ri.set_value(i, "layer", "front")
	check(m.get_shader_parameter("far") == false and "depth_test_disabled" in m.shader.code, "over: no depth test")
	check(m.render_priority < 0, "drawn before the edit overlays")
	ri.set_value(i, "view", "side")
	check(q.transform.basis.z.normalized().is_equal_approx(Vector3.RIGHT), "the side's: facing +X, as the side view looks")
	ri.set_value(i, "opacity", 0.25)
	check(is_equal_approx(m.get_shader_parameter("opacity"), 0.25), "its opacity")
	ri.set_value(i, "shown", false)
	check(not q.visible, "hidden")
	ri._save_now()
	# opened again: back as it was
	ri.model_opened("res://test/other.glb")
	check(ri.images.is_empty(), "another model: none")
	ri.model_opened("res://test/ref_model.glb")
	check_eq(ri.images.size(), 1, "the model again: its image back")
	if ri.images.size() == 1:
		var e: Dictionary = ri.images[0]
		check(e["view"] == "side" and e["layer"] == "front" and not e["shown"] and is_equal_approx(e["opacity"], 0.25), "with its settings")
	ri.remove(0)
	ri._save_now()
	check(not ri._read_all().has("res://test/ref_model.glb"), "removed: forgotten")
	DirAccess.remove_absolute(file)
	await _done(ed)
