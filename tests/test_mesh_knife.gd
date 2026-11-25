extends TestCase
## The mesh editor's faces (n-gons over the triangles) and its knife (K): a box reads as
## six quads; a cut splits the faces it crosses into two each (new points on the edges
## it crosses, their UVs and normals mixed from the edge's ends), follows the surface
## over an edge onto the next face, mirrors with symmetry, cuts right through (Shift+K),
## and is one undo step.

const SCENE := "res://scenes/editor/mesh_editor.tscn"


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


## The faces whose every corner has coordinate `axis` = `v` (a side of the box).
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


func _point_at(em, at: Vector3) -> int:
	for p in em.points.size():
		if em.points[p].distance_to(at) < 1e-4:
			return p
	return -1


func test_a_box_is_six_quads() -> void:
	var ed := await _box_editor()
	var em = ed.em
	check_eq(em.tri_count(), 12, "12 triangles underneath")
	check_eq(em.poly_count(), 6, "six faces")
	check_eq(em.edge_count(), 18, "18 edges, the diagonals counted")
	check_eq(em.wire_edges().size() / 2, 12, "12 edges shown - not the diagonals")
	for t in em.tri_count():
		check_eq(em.poly_loop(t).size(), 4, "each face a quad")
	# face mode: a click on one triangle selects its whole quad
	ed.view.frame(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	ed.set_kind(2)
	var top: Vector2 = ed.view.project(ed.part.global_transform * Vector3(0.1, 0.5, 0.2))
	ed.click_select(top, false)
	var n := 0
	for b in ed.sel_t:
		n += b
	check_eq(n, 2, "face mode: a click selects the whole quad (both its triangles)")
	# extruded, the quad is still one face on top, with a quad for each wall
	ed.extrude(false)
	check_eq(ed.em.poly_count(), 10, "extruded: its four walls are quads (6 + 4 faces)")
	await _done(ed)


func test_a_cut_across_a_face() -> void:
	var ed := await _box_editor()
	var em = ed.em
	var before: Dictionary = em.snapshot()
	var n0: int = em.points.size()
	ed.begin_knife()
	check(not ed.knife.is_empty(), "K: the knife is on")
	check(ed.knife_add_local(Vector3(0.25, 0.5, -0.5), Vector3.DOWN), "a point on the top's back edge")
	check(ed.knife_add_local(Vector3(0.25, 0.5, 0.5), Vector3.DOWN), "a point on its front edge")
	check(ed.knife_confirm(), "cut")
	em = ed.em
	check(ed.knife.is_empty(), "the knife is off after the cut")
	check_eq(_faces_on(em, 1, 0.5).size(), 2, "the top: two faces")
	check_eq(em.poly_count(), 7, "seven faces in all")
	check_eq(em.points.size(), n0 + 2, "two new points - on the two edges it crosses (none in the middle)")
	var a := _point_at(em, Vector3(0.25, 0.5, -0.5))
	var b := _point_at(em, Vector3(0.25, 0.5, 0.5))
	check(a >= 0 and b >= 0, "the new points where the cut crosses the edges")
	var e: int = em.edge(a, b)
	check(e >= 0 and not em.edge_inner[e], "a shown edge between them")
	check(e >= 0 and ed.sel_e[e] == 1, "the new edge is selected")
	# the front and back faces get the new points as corners: n-gons
	for z in [-0.5, 0.5]:
		var fs: Array = _faces_on(em, 2, z)
		check(fs.size() == 1 and em.poly_loop(fs[0]).size() == 5, "the face beside it (z %.1f): a 5-gon" % z)
	# the new points' vertices: UVs and normals from the edges' ends (one each side of the box's hard edges)
	var s = em.surfs[0]
	var verts := 0
	var top_ok := true
	for k in range(em.pv_start[a], em.pv_start[a + 1]):
		var v: int = em.pv[k] & em.VMASK
		verts += 1
		check(s.uv.size() == s.count(), "UVs for every vertex")
		if absf(s.nrm[v].y - 1.0) < 1e-3:
			top_ok = top_ok and s.uv[v].is_finite()
		check(absf(s.nrm[v].length() - 1.0) < 1e-3, "a unit normal")
	check_eq(verts, 2, "a vertex on each side of the hard edge (top and back)")
	var normals := {}
	for k in range(em.pv_start[a], em.pv_start[a + 1]):
		var v: int = em.pv[k] & em.VMASK
		normals[s.nrm[v].round()] = true
	check(normals.has(Vector3.UP) and normals.has(Vector3.BACK * -1.0), "the top's normal and the back's: hard edges stay hard (%s)" % [normals.keys()])
	# the shown mesh has it
	check_eq(ed.part.mesh.surface_get_array_index_len(0) / 3, em.tri_count(), "the mesh shown is the cut one")
	# one undo step back exactly
	ed.undo()
	check_eq(ed.em.points, before["points"], "undo: the points as they were")
	check_eq(ed.em.tris, before["derived"][0], "undo: the triangles as they were")
	check_eq(ed.em.poly_count(), 6, "undo: six quads")
	ed.redo()
	check_eq(ed.em.poly_count(), 7, "redo: cut again")
	await _done(ed)


func test_a_cut_over_an_edge() -> void:
	var ed := await _box_editor()
	ed.begin_knife()
	var dir := Vector3(0, -1, -1).normalized()   # (seen from above and in front)
	check(ed.knife_add_local(Vector3(0, 0.5, -0.5), dir), "a point on the top's back edge")
	check(ed.knife_add_local(Vector3(0, -0.5, 0.5), dir), "a point on the front's bottom edge")
	check(ed.knife_confirm(), "cut")
	var em = ed.em
	check(_point_at(em, Vector3(0, 0.5, 0.5)) >= 0, "a new point where it crosses the edge between top and front")
	check_eq(_faces_on(em, 1, 0.5).size(), 2, "the top split")
	check_eq(_faces_on(em, 2, 0.5).size(), 2, "the front split")
	check_eq(em.poly_count(), 8, "eight faces")
	# the derived arrays patched where it cut are what working them out again gives
	var es := {}
	for e in em.edge_count():
		es["%d-%d:%d" % [em.edges[e * 2], em.edges[e * 2 + 1], em.edge_inner[e]]] = true
	var adj := []
	for p in em.points.size():
		var l := Array(em.adj.slice(em.adj_start[p], em.adj_start[p + 1]))
		l.sort()
		adj.append(l)
	em.derive()
	var es2 := {}
	for e in em.edge_count():
		es2["%d-%d:%d" % [em.edges[e * 2], em.edges[e * 2 + 1], em.edge_inner[e]]] = true
	var adj2 := []
	for p in em.points.size():
		var l := Array(em.adj.slice(em.adj_start[p], em.adj_start[p + 1]))
		l.sort()
		adj2.append(l)
	check(es == es2, "patched edges = edges derived again")
	check(adj == adj2, "patched neighbours = neighbours derived again")
	check_eq(em.poly_count(), 8, "and the same faces")
	await _done(ed)


func test_symmetry_and_cut_through() -> void:
	var ed := await _box_editor()
	ed.sym = [true, false, false]
	ed.begin_knife()
	ed.knife_add_local(Vector3(0.25, 0.5, -0.5), Vector3.DOWN)
	ed.knife_add_local(Vector3(0.25, 0.5, 0.5), Vector3.DOWN)
	check(ed.knife_confirm(), "cut on +X")
	var em = ed.em
	check(_point_at(em, Vector3(-0.25, 0.5, -0.5)) >= 0 and _point_at(em, Vector3(-0.25, 0.5, 0.5)) >= 0, "mirrored on -X")
	check_eq(_faces_on(em, 1, 0.5).size(), 3, "the top in three")
	ed.undo()
	ed.sym = [false, false, false]
	# Shift+K: right through, front and back - a ring round the box
	ed.begin_knife(true)
	ed.knife_add_local(Vector3(0, 1.0, 1.0), Vector3.FORWARD)
	ed.knife_add_local(Vector3(0, -1.0, 1.0), Vector3.FORWARD)
	check(ed.knife_confirm(), "cut through")
	em = ed.em
	check_eq(em.poly_count(), 10, "top, front, bottom and back each in two")
	for at in [Vector3(0, 0.5, 0.5), Vector3(0, -0.5, 0.5), Vector3(0, 0.5, -0.5), Vector3(0, -0.5, -0.5)]:
		check(_point_at(em, at) >= 0, "a point on the box's edge at %s" % at)
	await _done(ed)


## A character's body (70,000 triangles): a cut over a few of them is quick - only the faces
## it crosses are made again.
func test_a_cut_on_a_character_is_quick() -> void:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	ed.select_part(ed.parts()[0])
	ed.enter_edit(true)
	var em = ed.em
	# two spots a few triangles apart, seen along the surface's normal there
	var ta: int = em.tri_count() / 2
	var tb: int = ta
	for i in 6:
		var e: int = em.tri_edges[tb * 3]
		tb = em.edge_tris[e * 2] if em.edge_tris[e * 2] != tb else em.edge_tris[e * 2 + 1]
	var mid := func(t: int) -> Vector3:
		return (em.points[em.tris[t * 3]] + em.points[em.tris[t * 3 + 1]] + em.points[em.tris[t * 3 + 2]]) / 3.0
	var n: Vector3 = (em.points[em.tris[ta * 3 + 1]] - em.points[em.tris[ta * 3]]).cross(em.points[em.tris[ta * 3 + 2]] - em.points[em.tris[ta * 3]]).normalized()
	var t0: int = em.tri_count()
	ed.begin_knife()
	check(ed.knife_add_local(mid.call(ta), -n, false) and ed.knife_add_local(mid.call(tb), -n, false), "two points on the body")
	var us := Time.get_ticks_usec()
	var ok: bool = ed.knife_confirm()
	var ms := (Time.get_ticks_usec() - us) / 1000.0
	print("    knife on the pirate (%d triangles): %.1f ms" % [t0, ms])
	check(ok and ed.em.tri_count() > t0, "cut (%d -> %d triangles)" % [t0, ed.em.tri_count()])
	check(ms < 400.0, "quick: %.1f ms" % ms)
	ed.undo()
	check_eq(ed.em.tri_count(), t0, "undone")
	await _done(ed)


## Auto select (4): a click picks a point when it's on one, else an edge, else the face;
## Shift+click mixes them, and a move takes all their points.
func test_auto_select() -> void:
	var ed := await _box_editor()
	ed.view.frame(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))
	ed.set_kind(3)
	var g: Transform3D = ed.part.global_transform
	var scr := func(p: Vector3) -> Vector2: return ed.view.project(g * p)
	var em = ed.em
	var top_mid: Vector2 = scr.call(Vector3(0, 0.5, 0))
	# near a corner: the point
	var corner := Vector3(0.5, 0.5, 0.5)
	var c2: Vector2 = scr.call(corner)
	ed.click_select(c2 + (top_mid - c2).normalized() * 3.0, false)
	var cp := _point_at(em, corner)
	check(ed.sel_pa[cp] == 1 and not ed.sel_e.has(1) and not ed.sel_t.has(1), "near a corner: the point picked")
	# the middle of an edge: the edge
	var e2: Vector2 = scr.call(Vector3(0, 0.5, 0.5))
	ed.click_select(e2 + (top_mid - e2).normalized() * 2.0, false)
	var e: int = em.edge(_point_at(em, Vector3(0.5, 0.5, 0.5)), _point_at(em, Vector3(-0.5, 0.5, 0.5)))
	check(ed.sel_e[e] == 1 and not ed.sel_pa.has(1) and not ed.sel_t.has(1), "on an edge: the edge picked")
	# the middle of a face: the whole face
	ed.click_select(top_mid, false)
	var n := 0
	for b in ed.sel_t:
		n += b
	check(n == 2 and not ed.sel_e.has(1), "inside a face: the face (both its triangles)")
	# mixed: the top face, the bottom front edge, a bottom back corner - all moved together
	ed.click_select(scr.call(Vector3(0, -0.5, 0.5)) + Vector2(0, -2), true)
	var bc := Vector3(-0.5, -0.5, -0.5)
	var vis: Vector2 = ed.view.project(g * bc)
	ed.sel_pa[_point_at(em, bc)] = 1   # (behind the box from here: picked as a click would)
	ed._derive_sel()
	var sel: PackedInt32Array = ed.selected_points()
	check_eq(sel.size(), 4 + 2 + 1, "the face's 4 points, the edge's 2 and the point: 7 (%s)" % vis)
	var before: PackedVector3Array = ed.em.points.duplicate()
	ed.move_selection(Vector3(0, 0.25, 0))
	var moved := 0
	for p in before.size():
		if ed.em.points[p].distance_to(before[p]) > 0.2:
			moved += 1
	check_eq(moved, 7, "all their points moved")
	ed.undo()
	# a box round the whole box: every point, edge and face
	ed.box_select(Rect2(Vector2.ZERO, ed.view.size), false)
	check(not ed.sel_pa.has(0) and ed.sel_t.count(1) == 12 and ed.sel_e.count(1) == 12, "a box: points, the shown edges and the faces inside it")
	await _done(ed)


## A plane subdivided into four quads round a middle point.
func _quads_editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	ed.add_primitive("plane")
	ed.enter_edit(true)
	ed.set_kind(2)
	ed.select_all(true)
	ed.subdivide()
	return ed


## Dissolve (Ctrl+X): a point, an edge or faces taken out and the faces round them made one.
func test_dissolve() -> void:
	var ed := await _quads_editor()
	var em = ed.em
	check_eq(em.poly_count(), 4, "a plane subdivided: four quads")
	var mid := _point_at(em, Vector3.ZERO)
	check(mid >= 0, "a point in the middle")
	var before: Dictionary = em.snapshot()
	# the middle point: one face, no point inside it
	ed.set_kind(0)
	ed.select_points(PackedInt32Array([mid]))
	ed.dissolve_selected()
	em = ed.em
	check_eq(em.poly_count(), 1, "the middle point dissolved: one face")
	check_eq(em.adj_start[mid + 1] - em.adj_start[mid], 0, "the point has no edges left")
	check(not em.poly_loop(0).has(mid) and em.poly_loop(0).size() == 8, "its outline: the 8 points round it (%d)" % em.poly_loop(0).size())
	# undo: exactly as it was
	ed.undo()
	check_eq(ed.em.points, before["points"], "undo: the points")
	check_eq(ed.em.tris, before["derived"][0], "undo: the triangles")
	check_eq(ed.em.poly_count(), 4, "undo: four quads")
	# the four faces: one, the middle point gone
	ed.set_kind(2)
	ed.select_all(true)
	ed.dissolve_selected()
	em = ed.em
	check_eq(em.poly_count(), 1, "four faces dissolved: one")
	check_eq(em.tri_count(), 6, "filled again from its 8-point outline (6 triangles)")
	var es := {}
	for e in em.edge_count():
		es["%d-%d:%d" % [em.edges[e * 2], em.edges[e * 2 + 1], em.edge_inner[e]]] = true
	var tri_set := {}
	for t in em.tri_count():
		var k := [em.tris[t * 3], em.tris[t * 3 + 1], em.tris[t * 3 + 2]]
		k.sort()
		tri_set[str(k)] = true
	em.derive()
	var es2 := {}
	for e in em.edge_count():
		es2["%d-%d:%d" % [em.edges[e * 2], em.edges[e * 2 + 1], em.edge_inner[e]]] = true
	var tri_set2 := {}
	for t in em.tri_count():
		var k := [em.tris[t * 3], em.tris[t * 3 + 1], em.tris[t * 3 + 2]]
		k.sort()
		tri_set2[str(k)] = true
	check(es == es2 and tri_set == tri_set2, "patched = derived again (edges, triangles)")
	check_eq(em.poly_count(), 1, "and one face")
	ed.toggle_edit()
	check_eq(ed.part.mesh.surface_get_array_len(0), 8, "back in object mode: the dissolved point's vertex dropped from the mesh")
	await _done(ed)
	# a box's top and front: one n-gon of six corners
	ed = await _box_editor()
	em = ed.em
	ed.set_kind(1)
	ed.sel_e.fill(0)
	ed.sel_e[em.edge(_point_at(em, Vector3(0.5, 0.5, 0.5)), _point_at(em, Vector3(-0.5, 0.5, 0.5)))] = 1
	ed.dissolve_selected()
	em = ed.em
	check_eq(em.poly_count(), 5, "the shared edge dissolved: five faces")
	var big := -1
	for t in em.tri_count():
		if em.poly_loop(t).size() == 6:
			big = t
	check(big >= 0, "one of six corners (top and front)")
	check_eq(em.tri_count(), 12, "the triangles as they were")
	ed.undo()
	# symmetry: the twin edge on -X too
	ed.sym = [true, false, false]
	ed.sel_e.fill(0)
	ed.sel_e[em.edge(_point_at(ed.em, Vector3(0.5, 0.5, 0.5)), _point_at(ed.em, Vector3(0.5, 0.5, -0.5)))] = 1
	ed.dissolve_selected()
	check_eq(ed.em.poly_count(), 4, "with symmetry X: the top joined to both sides (6 - 2 faces)")
	await _done(ed)


## Dissolving a point on a character's body is quick (only the faces round it are made again).
func test_dissolve_on_a_character_is_quick() -> void:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	ed.select_part(ed.parts()[0])
	ed.enter_edit(true)
	var em = ed.em
	var t0: int = em.tri_count()
	var p: int = em.tris[(t0 / 2) * 3]
	ed.set_kind(0)
	ed.select_points(PackedInt32Array([p]))
	var us := Time.get_ticks_usec()
	ed.dissolve_selected()
	var ms := (Time.get_ticks_usec() - us) / 1000.0
	print("    dissolve on the pirate (%d triangles): %.1f ms" % [t0, ms])
	check(ed.em.tri_count() < t0, "dissolved (%d -> %d triangles)" % [t0, ed.em.tri_count()])
	check(ms < 400.0, "quick: %.1f ms" % ms)
	ed.undo()
	check_eq(ed.em.tri_count(), t0, "undone")
	await _done(ed)


## "" if the edit mesh's faces are sound: every face one outline, and the derived arrays as
## they are equal to those worked out again (else what's wrong).
func _sound(em) -> String:
	for t in em.tri_count():
		if em.poly_loop(t).size() < 3:
			return "triangle %d's face has no outline" % t
	var key := func() -> Array:
		var es := {}
		for e in em.edge_count():
			es["%d-%d:%d" % [em.edges[e * 2], em.edges[e * 2 + 1], em.edge_inner[e]]] = true
		var ts := {}
		for t in em.tri_count():
			var k := [em.tris[t * 3], em.tris[t * 3 + 1], em.tris[t * 3 + 2]]
			k.sort()
			ts[str(k)] = true
		var adj := {}
		for p in em.points.size():
			var l := Array(em.adj.slice(em.adj_start[p], em.adj_start[p + 1]))
			l.sort()
			if not l.is_empty():
				adj[p] = l
		return [es, ts, adj, em.poly_count()]
	var a: Array = key.call()
	em.derive()
	var b: Array = key.call()
	for i in 4:
		if a[i] != b[i]:
			return ["edges", "triangles", "neighbours", "face count (%s vs %s)" % [a[3], b[3]]][i] + " differ from those derived again"
	return ""


## A quad subdivided on a curved primitive: four quads round its middle, the faces beside it
## n-gons, the pole / cap triangles as they were - every face sound.
func test_subdivide_a_quad_on_round_shapes() -> void:
	for kind in ["sphere", "cylinder"]:
		var ed: Control = load(SCENE).instantiate()
		tree.root.add_child(ed)
		await tree.process_frame
		ed.add_primitive(kind)
		ed.enter_edit(true)
		ed.set_kind(2)
		check_eq(_sound(ed.em), "", "%s: sound as read" % kind)
		var quads := []
		for t in ed.em.tri_count():
			if ed.em.poly_tris(t).size() == 2 and ed.em.poly_loop(t).size() == 4 and t == ed.em.poly_tris(t)[0]:
				quads.append(t)
		for t in [quads[0], quads[quads.size() / 2], quads[quads.size() - 1]]:
			var em = ed.em
			var f0: int = em.poly_count()
			var lp: PackedInt32Array = em.poly_loop(t)
			ed.sel_t.fill(0)
			for u in em.poly_tris(t):
				ed.sel_t[u] = 1
			ed._derive_sel()
			ed.subdivide()
			em = ed.em
			check_eq(em.poly_count(), f0 + 3, "%s quad %d: one face became four" % [kind, t])
			var c := -1
			for d in [[0, 2], [1, 3]]:
				var want: Vector3 = (em.points[lp[d[0]]] + em.points[lp[d[1]]]) * 0.5
				for p in range(em.points.size() - 5, em.points.size()):
					if em.points[p].distance_to(want) < 1e-5:
						c = p
			var round_c := {}
			for u in em.tris_around(c):
				round_c[em.tri_face[u]] = em.poly_loop(u).size()
			check(round_c.size() == 4 and round_c.values().all(func(n): return n == 4), "%s quad %d: four quads round its middle (%s)" % [kind, t, round_c])
			check_eq(_sound(em), "", "%s quad %d: sound after" % [kind, t])
			ed.undo()
		await _done(ed)


## Each edit on a sphere leaves its faces sound (the derived arrays as derive() makes them).
func test_edits_keep_faces_sound() -> void:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	ed.add_primitive("sphere")
	ed.enter_edit(true)
	var em = ed.em
	var q := -1
	for t in em.tri_count():
		if em.poly_loop(t).size() == 4 and em.points[em.tris[t * 3]].x > 0.2:
			q = t
			break
	var steps := {
		"extrude": func():
			ed.set_kind(2); ed.sel_t.fill(0)
			for u in ed.em.poly_tris(q): ed.sel_t[u] = 1
			ed._derive_sel(); ed.extrude(false),
		"delete": func():
			ed.set_kind(2); ed.sel_t.fill(0)
			for u in ed.em.poly_tris(q): ed.sel_t[u] = 1
			ed._derive_sel(); ed.delete_selected(),
		"merge": func():
			ed.set_kind(0); ed.select_points(PackedInt32Array([ed.em.tris[q * 3], ed.em.tris[q * 3 + 1]])); ed.merge_selected(),
		"knife": func():
			var lp: PackedInt32Array = ed.em.poly_loop(q)
			var a: Vector3 = (ed.em.points[lp[0]] + ed.em.points[lp[1]]) * 0.5
			var b: Vector3 = (ed.em.points[lp[2]] + ed.em.points[lp[3]]) * 0.5
			var n: Vector3 = -((a + b) * 0.5).normalized()
			ed.begin_knife(); ed.knife_add_local(a, n); ed.knife_add_local(b, n); ed.knife_confirm(),
		"dissolve": func():
			ed.set_kind(0); ed.select_points(PackedInt32Array([ed.em.tris[q * 3]])); ed.dissolve_selected(),
	}
	for name in steps:
		var t0: int = ed.em.tri_count()
		(steps[name] as Callable).call()
		check(ed.em.tri_count() != t0, "%s: the mesh changed" % name)
		check_eq(_sound(ed.em), "", "%s: sound" % name)
		ed.undo()
		check_eq(ed.em.tri_count(), t0, "%s undone" % name)
	await _done(ed)
