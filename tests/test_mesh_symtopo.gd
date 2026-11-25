extends TestCase
## Symmetrize topology (Ctrl+Shift+M): one side rebuilt as the mirror of the other - cut at
## the plane, the other side deleted, the kept side mirrored and welded at the seam; a
## character's copy weighted to the twin bones; one undo step.

const SCENE := "res://scenes/editor/mesh_editor.tscn"


func _editor(kind: String) -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	ed.add_primitive(kind)
	ed.enter_edit(true)
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


## Points with no mirror twin across `axis`, and edges not between exactly two triangles.
func _lone_and_open(em, axis: int) -> Array:
	var m: PackedInt32Array = em.mirror_map(axis, 1e-4)
	var lone := 0
	for i in em.points.size():
		if m[i] < 0 and em.adj_start[i + 1] > em.adj_start[i]:
			lone += 1
	var open := 0
	for e in em.edge_count():
		if em.edge_tn[e] != 2:
			open += 1
	return [lone, open]


func test_a_box_across_the_plane() -> void:
	var ed := await _editor("box")
	ed.select_all(true)
	ed.move_selection(Vector3(0.2, 0, 0))
	var before: Dictionary = ed.em.snapshot()
	ed.symmetrize_topology(0, true)
	var em = ed.em
	var b: AABB = em.aabb()
	check(absf(b.position.x + 0.7) < 1e-4 and absf(b.end.x - 0.7) < 1e-4, "both sides as the + side was (%s)" % b)
	var lo: Array = _lone_and_open(em, 0)
	check_eq(lo[0], 0, "every point has its mirror twin")
	check_eq(lo[1], 0, "closed: every edge between two triangles")
	check_eq(em.points.size(), 12, "12 points: 8 corners, 4 on the seam")
	check_eq(em.poly_count(), 10, "10 faces: the +X side, and four faces cut in two")
	var sel := 0
	for p in em.points.size():
		if ed.sel_p[p]:
			sel += 1
			check(em.points[p].x < 0.0, "a new point selected (on -X)")
	check_eq(sel, 4, "the new half's points selected")
	ed.undo()
	check_eq(ed.em.points, before["points"], "undo: the points exactly")
	check_eq(ed.em.tris, before["derived"][0], "undo: the triangles exactly")
	await _done(ed)


func test_cuts_on_one_side_mirrored() -> void:
	var ed := await _editor("sphere")
	var em = ed.em
	# a knife cut on +X only
	var q := -1
	for t in em.tri_count():
		var lp: PackedInt32Array = em.poly_loop(t)
		if lp.size() == 4 and em.points[lp[0]].x > 0.25 and absf(em.points[lp[0]].y) < 0.3:
			q = t
			break
	var lp: PackedInt32Array = em.poly_loop(q)
	var a: Vector3 = (em.points[lp[0]] + em.points[lp[1]]) * 0.5
	var b: Vector3 = (em.points[lp[2]] + em.points[lp[3]]) * 0.5
	var n: Vector3 = -((a + b) * 0.5).normalized()
	ed.begin_knife()
	ed.knife_add_local(a, n)
	ed.knife_add_local(b, n)
	check(ed.knife_confirm(), "cut on +X")
	var cuts := []
	for p in range(ed.em.points.size() - 2, ed.em.points.size()):
		cuts.append(ed.em.points[p])
	check(_lone_and_open(ed.em, 0)[0] > 0, "before: the cut's points have no twins")
	ed.symmetrize_topology(0, true, true)   # (the side changed found by itself)
	em = ed.em
	for c: Vector3 in cuts:
		var want := Vector3(-c.x, c.y, c.z)
		var found := false
		for p in em.points.size():
			if em.points[p].distance_to(want) < 1e-4:
				found = true
		check(found, "the cut's point %s mirrored on -X" % c)
	var lo: Array = _lone_and_open(em, 0)
	check_eq(lo[0], 0, "every point has its twin")
	check_eq(lo[1], 0, "still closed")
	await _done(ed)


## A character: the copied side's vertices weighted to the twin bones (upper.L -> upper.R).
func test_a_character_follows_its_twin_bones() -> void:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	ed.select_part(ed.parts()[0])
	ed.enter_edit(true)
	var tw: PackedInt32Array = ed._bones_twin()
	check(not tw.is_empty(), "its bones paired")
	check_eq(ed.twin_bone_name("upper.L"), "upper.R", "upper.L's twin")
	check_eq(ed.twin_bone_name("Hand_Left"), "Hand_Right", "Left -> Right")
	check_eq(ed.twin_bone_name("spine"), "spine", "a bone in the middle: itself")
	var sk: Skin = ed.part.skin
	var skel := ed.part.get_node(ed.part.skeleton) as Skeleton3D
	var bind_of := func(bone: String) -> int:
		for i in sk.get_bind_count():
			if skel.get_bone_name(sk.get_bind_bone(i)) == bone or str(sk.get_bind_name(i)) == bone:
				return i
		return -1
	var bl: int = bind_of.call("upper.L")
	var br: int = bind_of.call("upper.R")
	check(bl >= 0 and br >= 0 and tw[bl] == br and tw[br] == bl, "upper.L and upper.R twins (%d, %d)" % [bl, br])
	# a vertex mostly on upper.L: its side kept
	var em = ed.em
	var best_v := -1
	var best_s := -1
	var best_w := 0.5
	for si in em.surfs.size():
		var s = em.surfs[si]
		for v in s.count():
			for k in s.nb:
				if s.bones[v * s.nb + k] == bl and s.weights[v * s.nb + k] > best_w:
					best_w = s.weights[v * s.nb + k]
					best_v = v
					best_s = si
	check(best_v >= 0, "a vertex mostly on upper.L")
	var at: Vector3 = em.surfs[best_s].pos[best_v]
	var t0 := Time.get_ticks_usec()
	ed.symmetrize_topology(0, at.x > 0.0)
	print("    symmetrize topology on the pirate: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	em = ed.em
	var want := Vector3(-at.x, at.y, at.z)
	var twin_ok := false
	var s2 = em.surfs[best_s]
	for v in s2.count():
		if s2.pos[v].distance_to(want) < 1e-4:
			var top := -1
			var tw2 := 0.0
			for k in s2.nb:
				if s2.weights[v * s2.nb + k] > tw2:
					tw2 = s2.weights[v * s2.nb + k]
					top = s2.bones[v * s2.nb + k]
			if top == br:
				twin_ok = true
	check(twin_ok, "its mirror image mostly on upper.R")
	ed.undo()
	await _done(ed)
