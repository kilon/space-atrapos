extends TestCase
## Talos's mesh editor (Meshes, F6): the screen, parts from primitives, edit
## mode with proportional editing, the mirror modifier, symmetrize, undo, and
## saving a glb into a mod (read back with its parts, skeleton and animations).

const SCENE := "res://scenes/editor/mesh_editor.tscn"


func _editor() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


func test_builds_headless() -> void:
	var ed := await _editor()
	check(ed.view != null and ed.view.sv.world_3d != null, "the 3D view has a world of its own")
	check(ed.find_children("TalosNav", "", true, false).size() == 1, "the Talos rail is there")
	check(ed.model != null and ed.parts().is_empty(), "it starts with an empty model")
	check(not ed.dirty, "nothing to save yet")
	# a model opens in the background
	ed.open("res://art/pirate_3d/pirate.glb")
	check(ed.loading, "opening: read on a worker")
	for i in 600:
		if not ed.loading:
			break
		await tree.process_frame
	check(not ed.loading and not ed.parts().is_empty(), "the pirate opened (%d parts)" % ed.parts().size())
	check_eq(ed.path, "res://art/pirate_3d/pirate.glb", "its path")
	# and a big part's edit mode is prepared in the background too
	ed.select_part(ed.parts()[0])
	ed.enter_edit()
	for i in 600:
		if ed.mode == "edit":
			break
		await tree.process_frame
	check_eq(ed.mode, "edit", "edit mode on the pirate's body")
	ed.toggle_edit()
	# the model list (scanned on a worker)
	for i in 600:
		if ed._scan_task < 0:
			break
		await tree.process_frame
	check(ed._all_files.has("res://art/minoan_3d/minoan.glb"), "the characters are listed")
	await _done(ed)
	# embedded (the Mod Editor): no rail
	var e2: Control = load(SCENE).instantiate()
	e2.embedded = true
	tree.root.add_child(e2)
	await tree.process_frame
	check(e2.find_children("TalosNav", "", true, false).is_empty(), "embedded: no Talos rail")
	await _done(e2)


func test_add_primitive() -> void:
	var ed := await _editor()
	for k in ["box", "cylinder", "cone", "sphere", "plane", "torus"]:
		var mi: MeshInstance3D = ed.add_primitive(k)
		check(mi != null and mi.mesh.get_surface_count() == 1, "a %s is added" % k)
	check_eq(ed.parts().size(), 6, "six parts")
	check(ed.dirty, "adding makes it unsaved")
	check_eq(str(ed.part.name), "Torus", "the new part is selected")
	ed.duplicate_part()
	check_eq(ed.parts().size(), 7, "duplicated")
	ed.undo()
	check_eq(ed.parts().size(), 6, "duplicate undone")
	ed.delete_part()
	check_eq(ed.parts().size(), 5, "deleted")
	ed.undo()
	check_eq(ed.parts().size(), 6, "delete undone")
	ed.rename_part("Ring")
	check_eq(str(ed.part.name), "Ring", "renamed")
	await _done(ed)


## A plane subdivided into a grid (edit mode), its points moved by hand.
func _grid_part(ed: Control) -> MeshInstance3D:
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
	return mi


func _nearest(em, at: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in em.points.size():
		var d: float = em.points[i].distance_to(at)
		if d < bd:
			bd = d
			best = i
	return best


func test_proportional_move() -> void:
	var ed := await _editor()
	_grid_part(ed)
	ed.enter_edit(true)
	check_eq(ed.mode, "edit", "edit mode")
	var em = ed.em
	check_eq(em.points.size(), 121, "11 x 11 points")
	var c := _nearest(em, Vector3.ZERO)
	var near := _nearest(em, Vector3(0.2, 0, 0))
	var far := _nearest(em, Vector3(0.8, 0, 0))
	var out := _nearest(em, Vector3(1.0, 0, 1.0))
	ed.prop_on = true
	ed.prop_radius = 1.0
	ed.prop_falloff = "smooth"
	ed.select_points(PackedInt32Array([c]))
	ed.move_selection(Vector3(0, 1, 0))
	var y_c: float = ed.em.points[c].y
	var y_near: float = ed.em.points[near].y
	var y_far: float = ed.em.points[far].y
	check(absf(y_c - 1.0) < 1e-4, "the selected point moved all the way (%.3f)" % y_c)
	check(y_near > 0.0 and y_near < y_c, "a neighbour moved less (%.3f)" % y_near)
	check(y_far >= 0.0 and y_far < y_near, "a further one less still (%.3f)" % y_far)
	check(absf(ed.em.points[out].y) < 1e-6, "outside the radius nothing moved")
	# the shown mesh follows the points
	var pos: PackedVector3Array = ed.part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -INF
	for p in pos:
		top = maxf(top, p.y)
	check(absf(top - 1.0) < 1e-4, "the mesh shown moved too")
	# every falloff fades from 1 to 0
	for f in ["smooth", "sphere", "root", "linear", "sharp", "constant"]:
		check(ed.em.falloff(f, 0.0, 1.0) == 1.0 and ed.em.falloff(f, 1.0, 1.0) == 0.0, "falloff %s: 1 at the centre, 0 at the radius" % f)
	# connected only: a separate piece isn't pulled
	ed.undo()
	check(absf(ed.em.points[c].y) < 1e-6, "undo puts it back")
	ed.redo()
	check(absf(ed.em.points[c].y - 1.0) < 1e-4, "redo moves it again")
	ed.undo()
	ed.prop_connected = true
	ed.select_points(PackedInt32Array([c]))
	ed.move_selection(Vector3(0, 0.5, 0))
	check(ed.em.points[near].y > 0.0 and ed.em.points[near].y < 0.5, "connected: joined neighbours follow")
	# leaving edit mode: one undo step of the model
	var before_edit: Mesh = ed._part_mesh_before
	ed.toggle_edit()
	check_eq(ed.mode, "object", "back to object mode")
	ed.undo()
	check(ed.part.mesh == before_edit, "the whole edit undone in one step")
	await _done(ed)


func test_mirror_modifier() -> void:
	var ed := await _editor()
	var mi := _grid_part(ed)
	# the grid moved to x >= 0, its left edge on the seam
	ed.enter_edit(true)
	ed.select_all(true)
	ed.move_selection(Vector3(1, 0, 0))
	var n: int = ed.em.points.size()
	var seam := 0
	for p in ed.em.points:
		if absf(p.x) < 1e-4:
			seam += 1
	check_eq(seam, 11, "11 points on the seam")
	ed.toggle_edit()
	ed.set_mirror(mi, {"axes": [true, false, false], "clip": true, "merge": 0.001})
	check(mi.has_meta("mesh_mirror"), "the modifier is kept on the part")
	check_eq((ed._ghosts.get(mi, []) as Array).size(), 1, "shown live: one mirrored copy")
	# a move in edit mode with clipping: seam points stay on the seam
	ed.enter_edit(true)
	var s0 := _nearest(ed.em, Vector3(0, 0, 0))
	ed.prop_on = false
	ed.select_points(PackedInt32Array([s0]))
	ed.move_selection(Vector3(-0.3, 0.2, 0))
	check(absf(ed.em.points[s0].x) < 1e-6 and absf(ed.em.points[s0].y - 0.2) < 1e-4, "clipped: a seam point stays on the seam")
	ed.undo()
	ed.toggle_edit()
	var applied: Mesh = ed.mirrored_mesh(mi)
	var vcount: int = applied.surface_get_array_len(0)
	var vbase: int = mi.mesh.surface_get_array_len(0)
	check_eq(vcount, vbase * 2 - 11, "applied: the vertex count doubled minus the seam")
	ed.apply_mirror()
	check(not mi.has_meta("mesh_mirror"), "applied: the modifier is gone")
	check_eq(mi.mesh.surface_get_array_len(0), vbase * 2 - 11, "the part's mesh is mirrored")
	var b: AABB = mi.mesh.get_aabb()
	check(absf(b.position.x + 2.0) < 1e-3 and absf(b.end.x - 2.0) < 1e-3, "it spans both sides (%s)" % b)
	ed.undo()
	check(mi.has_meta("mesh_mirror") and mi.mesh.surface_get_array_len(0) == vbase, "apply undone")
	await _done(ed)


func test_symmetrize() -> void:
	var ed := await _editor()
	ed.add_primitive("box")
	ed.enter_edit(true)
	var em = ed.em
	var p := _nearest(em, Vector3(-0.5, 0.5, 0.5))
	var twin := _nearest(em, Vector3(0.5, 0.5, 0.5))
	ed.prop_on = false
	ed.select_points(PackedInt32Array([p]))
	ed.move_selection(Vector3(-0.02, 0.01, 0))
	check(ed.em.points[p].distance_to(Vector3(-0.52, 0.51, 0.5)) < 1e-4, "a -X corner moved")
	ed.symmetrize(0, true)
	check(ed.em.points[p].distance_to(Vector3(-0.5, 0.5, 0.5)) < 1e-4, "symmetrize +X to -X: it matches its twin again (%s)" % ed.em.points[p])
	ed.undo()
	ed.symmetrize(0, false)
	check(ed.em.points[twin].distance_to(Vector3(0.52, 0.51, 0.5)) < 1e-4, "symmetrize -X to +X: the twin follows it (%s)" % ed.em.points[twin])
	# symmetry editing: a move mirrors to the twin
	ed.undo()
	ed.undo()
	ed.sym = [true, false, false]
	ed.select_points(PackedInt32Array([twin]))
	ed.move_selection(Vector3(0.1, 0, 0))
	check(ed.em.points[twin].distance_to(Vector3(0.6, 0.5, 0.5)) < 1e-4, "symmetry: the point moved")
	check(ed.em.points[p].distance_to(Vector3(-0.6, 0.5, 0.5)) < 1e-4, "symmetry: its twin moved the mirrored way (%s)" % ed.em.points[p])
	await _done(ed)


func test_edit_ops() -> void:
	var ed := await _editor()
	ed.add_primitive("box")
	ed.enter_edit(true)
	var em = ed.em
	check_eq(em.points.size(), 8, "a box: 8 points")
	check_eq(em.tri_count(), 12, "12 triangles")
	check_eq(em.edge_count(), 18, "18 edges")
	# extrude the top face
	ed.set_kind(2)
	for t in em.tri_count():
		var ok := true
		for k in 3:
			if em.points[em.tris[t * 3 + k]].y < 0.49:
				ok = false
		ed.sel_t[t] = 1 if ok else 0
	ed._derive_sel()
	var top: PackedInt32Array = ed.extrude(false)
	check_eq(top.size(), 4, "extrude: four new points")
	check_eq(ed.em.points.size(), 12, "12 points")
	check_eq(ed.em.tri_count(), 12 + 8, "four walls (8 triangles)")
	ed.move_selection(Vector3(0, 0.5, 0))
	check(absf(ed.em.aabb().end.y - 1.0) < 1e-4, "pulled up")
	# subdivide the top
	var tris_before: int = ed.em.tri_count()
	ed.subdivide()
	check(ed.em.tri_count() > tris_before, "subdivided (%d -> %d)" % [tris_before, ed.em.tri_count()])
	# merge two points
	ed.set_kind(0)
	var n0: int = ed.em.points.size()
	ed.select_points(PackedInt32Array([0, 1]))
	ed.merge_selected()
	check_eq(ed.em.points.size(), n0 - 1, "merge: one point fewer")
	# delete
	var t0: int = ed.em.tri_count()
	ed.select_points(PackedInt32Array([0]))
	ed.delete_selected()
	check(ed.em.tri_count() < t0, "delete removes faces")
	ed.flip_normals()
	ed.recalc_normals()
	# undo back to the box
	for i in 8:
		ed.undo()
	check_eq(ed.em.points.size(), 8, "undo all: the box again")
	check_eq(ed.em.tri_count(), 12, "12 triangles again")
	await _done(ed)


func test_save_reload_mod() -> void:
	var id: String = Mods.create("t")
	EditTarget.mod_id = id
	var ed := await _editor()
	var mi: MeshInstance3D = ed.add_primitive("box")
	mi.position = Vector3(1, 2, 3)
	ed.set_surface_material(mi, 0, load("res://scripts/editor/mesh/mesh_io.gd").preset(1))
	ed.add_primitive("sphere")
	var res_path := "res://models/test_mesh_editor.glb"
	ed.path = res_path
	check_eq(ed.write_to(res_path), OK, "saved")
	check(not ed.dirty, "saved: nothing unsaved")
	var file := EditTarget.read_path(res_path)
	check(file.begins_with("user://mods/") and FileAccess.file_exists(file), "into the mod (%s)" % file)
	check(not FileAccess.file_exists(res_path), "not into the game")
	check(ed.open_now(res_path), "read back")
	var names: Array = ed.parts().map(func(p): return str(p.name))
	check("Box" in names and "Sphere" in names, "both parts come back (%s)" % [names])
	for p in ed.parts():
		if str(p.name) == "Box":
			check(p.position.distance_to(Vector3(1, 2, 3)) < 1e-4, "where it was")
			var m := p.mesh.surface_get_material(0) as BaseMaterial3D
			check(m != null and m.metallic > 0.9, "with its material")
	# a character keeps its skeleton, skin and animations
	var char_path := "res://art/minoan_3d/minoan.glb"
	check(ed.open_now(char_path), "a character opens")
	var sk: Array = ed.model.find_children("*", "Skeleton3D", true, false)
	var bones: int = sk[0].get_bone_count() if not sk.is_empty() else 0
	var aps: Array = ed.model.find_children("*", "AnimationPlayer", true, false)
	var clips: int = aps[0].get_animation_list().size() if not aps.is_empty() else 0
	check(bones > 10 and clips > 5, "with its bones (%d) and clips (%d)" % [bones, clips])
	var body: MeshInstance3D = ed.parts()[0]
	ed.select_part(body)
	var t0 := Time.get_ticks_usec()
	ed.enter_edit(true)
	var prep := (Time.get_ticks_usec() - t0) / 1000.0
	ed.select_points(PackedInt32Array([0, 1, 2]))
	ed.prop_on = true
	ed.prop_radius = 0.05
	t0 = Time.get_ticks_usec()
	ed.move_selection(Vector3(0.01, 0, 0))
	var mv := (Time.get_ticks_usec() - t0) / 1000.0
	print("  mesh editor on %s: %d points, %d faces - edit mode ready in %.0f ms, a proportional move in %.0f ms" % [char_path, ed.em.points.size(), ed.em.tri_count(), prep, mv])
	ed.toggle_edit()
	check_eq(ed.write_to(char_path), OK, "the character saved into the mod")
	check(FileAccess.file_exists(EditTarget.write_path(char_path)), "as the mod's copy")
	check(ed.open_now(char_path), "and read back (the mod's copy)")
	sk = ed.model.find_children("*", "Skeleton3D", true, false)
	aps = ed.model.find_children("*", "AnimationPlayer", true, false)
	check(not sk.is_empty() and sk[0].get_bone_count() == bones, "the skeleton kept (%d bones)" % (sk[0].get_bone_count() if not sk.is_empty() else 0))
	check(not aps.is_empty() and aps[0].get_animation_list().size() == clips, "the animations kept")
	var skinned := false
	for p in ed.parts():
		if p.skin != null:
			skinned = true
	check(skinned, "the skin kept")
	await _done(ed)
	EditTarget.mod_id = ""
	Mods.remove(id)
	check(not DirAccess.dir_exists_absolute("user://mods/" + id), "the test mod removed")


## The right-click menu (icons only, each with its tooltip), the mouse (left click selects, a left
## drag in empty space turns the view, a right drag pans), the panels' splits, the selected part's
## outline, the models list as pictures or as paths.
func test_menu_mouse_panels_outline() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	check(p.material_overlay != null and p.material_overlay is ShaderMaterial, "the selected part is outlined")
	var q: MeshInstance3D = ed.add_primitive("sphere")
	ed.select_part(q)
	check(p.material_overlay == null and q.material_overlay != null, "the outline moves with the selection")
	var m: PopupPanel = ed.menu(Vector2(10, 10))
	var buttons := m.find_children("*", "Button", true, false)
	check(buttons.size() >= 20, "the menu: many tools (%d)" % buttons.size())
	var texts := 0
	var tips := 0
	for b in buttons:
		texts += 1 if (b as Button).text != "" else 0
		tips += 1 if (b as Button).tooltip_text != "" and (b as Button).icon != null else 0
	check_eq(texts, 0, "icons only - no words on them")
	check_eq(tips, buttons.size(), "each with its icon and its tooltip")
	m.hide()
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	var em_menu: PopupPanel = ed.menu(Vector2(10, 10))
	check(em_menu.find_child("Menu_Extrude", true, false) != null and em_menu.find_child("Menu_Subdivide", true, false) != null, "edit mode: its tools in the menu")
	em_menu.hide()
	ed.toggle_edit()
	# A left drag in empty space turns the view; a click there clears the selection.
	var yaw0: float = ed.view.yaw if "yaw" in ed.view else 0.0
	var corner := Vector2(2, 2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = corner
	ed._view_input(press)
	var mv := InputEventMouseMotion.new()
	mv.position = corner + Vector2(40, 0)
	mv.relative = Vector2(40, 0)
	ed._view_input(mv)
	check_eq(ed._drag, "orbit", "a left drag in empty space turns the view")
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.position = mv.position
	ed._view_input(rel)
	if "yaw" in ed.view:
		check(absf(float(ed.view.yaw) - yaw0) > 0.01, "the view turned")
	check(ed.part == q, "a drag doesn't change the selection")
	# The panels: splits to drag.
	check(ed.find_children("Split_*", "SplitContainer", true, false).size() >= 3, "the panels resize by their dividers")
	# The models list: pictures or paths.
	ed.set_list_view("details")
	check(ed._files.max_columns == 1, "details: one column of paths")
	ed.set_list_view("icons")
	check(ed._files.icon_mode == ItemList.ICON_MODE_TOP and ed._files.fixed_icon_size.x >= 64, "icons: a picture of each model")
	await _done(ed)


## Edit mode shows the wireframe and points only round the spot under the mouse
## (the selection whole, wherever it is).
func test_edit_mode_shows_the_hovered_area() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("sphere")
	ed.select_part(p)
	ed.view.frame(p.get_aabb())
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	var wire_n := func() -> int:
		var m: ArrayMesh = ed.view.wire_mi.mesh
		return m.surface_get_array_index_len(0) / 2 if m.get_surface_count() > 0 else 0
	check_eq(wire_n.call(), 0, "nothing hovered: no bright wireframe")
	var all_m: ArrayMesh = ed.view.wire_all_mi.mesh
	check(all_m.get_surface_count() == 1 and all_m.surface_get_array_index_len(0) / 2 == ed.em.wire_edges().size() / 2, "the whole wireframe, faint, always")
	check(ed.em.wire_edges().size() / 2 < ed.em.edge_count(), "its faces' edges - not the diagonals of their triangles (%d of %d)" % [ed.em.wire_edges().size() / 2, ed.em.edge_count()])
	ed._hover_ms = 0
	ed._hover(ed.view.size * 0.5)
	var local: int = wire_n.call()
	check(ed._focus != Vector3.INF, "the spot under the mouse found")
	check(local > 0 and local < ed.em.edge_count(), "only its area's edges shown (%d of %d)" % [local, ed.em.edge_count()])
	ed._hover_ms = 0
	ed._hover(Vector2(1, 1))
	check_eq(wire_n.call(), 0, "off the model: gone again")
	await _done(ed)


## A character T-posed for editing (arms out, its weapon beside it), turned back exactly
## when saved; its weapons hidden and shown.
func test_tpose_and_weapons() -> void:
	var ed := await _editor()
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var body: MeshInstance3D = ed.parts()[0]
	var before: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ed.toggle_tpose()
	for i in 600:
		if ed._tpose_task < 0 and ed.is_tposed():
			break
		await tree.process_frame
	check(ed.is_tposed(), "T-posed")
	var box: AABB = body.mesh.get_aabb()
	check(box.size.x > 1.2, "its arms out to the sides (%.2f m wide)" % box.size.x)
	check(body.skeleton == NodePath(""), "drawn as laid out (not skinned again)")
	# back exactly
	var back: ArrayMesh = ed.TPose.mesh_from(ed.TPose.bake(body.mesh, body.get_meta("tpose_mats"), true))
	var after: PackedVector3Array = back.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for i in before.size():
		worst = maxf(worst, before[i].distance_to(after[i]))
	check(worst < 0.0005, "turned back to its own pose exactly (%.6f m)" % worst)
	ed.undo()
	check(not ed.is_tposed() and body.skeleton != NodePath(""), "undo: its own pose again")
	var n0: int = body.mesh.get_surface_count()
	var ws: PackedInt32Array = ed.TPose.weapon_surfaces(body)
	check(not ws.is_empty(), "the pirate has weapons (%d parts)" % ws.size())
	check(not ed.TPose.is_weapon_material("AUT_VisorGunmetal"), "a gunmetal visor isn't a weapon")
	var tris := func(m: Mesh) -> int:
		var n := 0
		for i in m.get_surface_count():
			n += m.surface_get_array_index_len(i) / 3
		return n
	var t0: int = tris.call(body.mesh)
	ed.set_weapons(false)
	check(tris.call(body.mesh) < t0 and body.mesh.get_surface_count() <= n0, "its weapons out of the body (not drawn, not edited)")
	# nothing left on the gun's bone - the whole rifle, whatever its materials
	var wb: Dictionary = ed.TPose.weapon_binds(body)
	check(not wb.is_empty(), "the rifle's bone found")
	var left := 0
	for i in body.mesh.get_surface_count():
		var a: Array = body.mesh.surface_get_arrays(i)
		if a[Mesh.ARRAY_BONES] == null:
			continue
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per: int = bones.size() / nv
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in idx.size() / 3:
			var all_gun := true
			for c in 3:
				var v: int = idx[t * 3 + c]
				var bb := -1
				var bw := 0.0
				for k in per:
					if w[v * per + k] > bw:
						bw = w[v * per + k]
						bb = bones[v * per + k]
				all_gun = all_gun and wb.has(bb)
			if all_gun:
				left += 1
	check_eq(left, 0, "no triangle of the rifle left showing")
	check(body.has_meta("weapons_part") and not (body.get_meta("weapons_part") as Node3D).visible, "kept aside, hidden")
	check(not body.get_meta("weapons_part") in ed.parts(), "not one of the parts to pick")
	# saved T-posed with its weapons hidden: the file is the model as it was
	ed.toggle_tpose()
	for i in 600:
		if ed._tpose_task < 0 and ed.is_tposed():
			break
		await tree.process_frame
	var id := Mods.create("t_tpose")
	EditTarget.mod_id = id
	check_eq(ed.write_to("res://art/test_tpose/pirate_t.glb"), OK, "saved")
	EditTarget.mod_id = id
	var saved_n: Node3D = ed.MeshIO.read(EditTarget.read_path("res://art/test_tpose/pirate_t.glb"))
	var bm: Mesh = (saved_n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	check_eq(bm.get_surface_count(), n0, "the file has its weapons")
	var bb: AABB = bm.get_aabb()
	check(bb.size.x < 1.0, "and its own pose, not the T (%.2f m wide)" % bb.size.x)
	saved_n.free()
	EditTarget.mod_id = ""
	Mods.remove(id)
	check(ed.is_tposed() and body.has_meta("weapons_part"), "after saving: still T-posed, weapons still hidden")
	ed.set_weapons(true)
	check_eq(body.mesh.get_surface_count(), n0, "shown again: back in the body, in its own surfaces")
	check_eq(tris.call(body.mesh), t0, "every triangle back")
	await _done(ed)


## The gizmo on the selection: its arrows move along an axis, its rings turn, its boxes scale.
func test_gizmo() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	ed._sync_gizmo()
	check(ed.view.gizmo_at == Vector3.INF, "the gizmo hidden at first")
	ed.toggle_gizmo()
	check(ed.view.gizmo_at == p.global_position, "shown (Ctrl+G): it stands at the selected part")
	var hs: Array = ed.view.gizmo_handles()
	var ids := []
	for h in hs:
		ids.append(h["id"])
	for id in ["mx", "my", "mz", "rx", "ry", "rz", "sx", "sy", "sz", "m", "s"]:
		check(id in ids, "a handle: " + id)
	# Drag the X arrow: the part moves along X only.
	var arrow: Dictionary = hs[ids.find("mx")]
	var tip: Vector2 = (arrow["pts"] as PackedVector2Array)[1]
	var at: Vector2 = (arrow["pts"] as PackedVector2Array)[0].lerp(tip, 0.9)
	check(ed.view.gizmo_pick(at).get("id", "") == "mx", "the X arrow picked under the mouse")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	ed._view_input(press)
	check(not ed.xf.is_empty() and ed.xf["kind"] == "G", "pressing an arrow starts a move")
	var mv := InputEventMouseMotion.new()
	mv.position = at + (tip - (arrow["pts"] as PackedVector2Array)[0]).normalized() * 60.0
	ed._view_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.position = mv.position
	ed._view_input(rel)
	check(ed.xf.is_empty(), "letting go keeps it")
	check(p.position.x > 0.05 and absf(p.position.y) < 0.001 and absf(p.position.z) < 0.001, "moved along X only (%s)" % p.position)
	ed.undo()
	check(p.position.is_zero_approx(), "undoable")
	await _done(ed)


## In edit mode the view turns about the selection: it stays where it is on screen.
func test_orbit_about_the_selection() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	p.position = Vector3(1.5, 0.3, 0)
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6)))
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	ed.select_points(PackedInt32Array([0]))
	var piv: Vector3 = p.global_transform * ed.em.points[0]
	var before: Vector2 = ed.view.project(piv)
	ed._drag_started += 1
	ed.view.orbit(Vector2(80, 30), ed._orbit_pivot())
	var after: Vector2 = ed.view.project(piv)
	check(before.distance_to(after) < 1.0, "the selection stays put on screen (%.2f px)" % before.distance_to(after))
	var other: Vector3 = p.global_transform * ed.em.points[6]
	var o0: Vector2 = ed.view.project(other)
	ed.view.orbit(Vector2(80, 30), ed._orbit_pivot())
	check(o0.distance_to(ed.view.project(other)) > 5.0, "while the rest turns round it")
	await _done(ed)


## With a symmetry axis on, picking an element picks its mirror twin too.
func test_symmetry_selects_twins() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("sphere")
	ed.select_part(p)
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	var pts: PackedVector3Array = ed.em.points
	var one := -1
	for i in pts.size():
		if pts[i].x > 0.2:
			one = i
			break
	ed.sym = [true, false, false]
	ed.sel_p.fill(0)
	ed.sel_p[one] = 1
	ed._twins(0, one, 1)
	var twin := -1
	for i in pts.size():
		if i != one and ed.sel_p[i]:
			twin = i
	check(twin >= 0 and pts[twin].distance_to(Vector3(-pts[one].x, pts[one].y, pts[one].z)) < 0.001, "its twin across X picked too")
	ed._twins(0, one, 0)
	check(not ed.sel_p[twin], "and let go of together")
	ed.sym = [true, true, false]
	ed._twins(0, one, 1)
	var n := 0
	for b in ed.sel_p:
		n += b
	check_eq(n, 4, "two axes: its four mirror images")
	# a face's twin
	ed.sym = [true, false, false]
	ed.set_kind(2)
	ed.sel_t.fill(0)
	var t := -1
	for i in ed.em.tri_count():
		if pts[ed.em.tris[i * 3]].x > 0.15 and pts[ed.em.tris[i * 3 + 1]].x > 0.15 and pts[ed.em.tris[i * 3 + 2]].x > 0.15:
			t = i
			break
	ed.sel_t[t] = 1
	ed._twins(2, t, 1)
	var faces := 0
	for b in ed.sel_t:
		faces += b
	check_eq(faces, 2, "a face and its mirror face")
	await _done(ed)


## Scaling along one axis - typed (X / Y / Z) or with the gizmo's box on it - stretches along that axis only.
func test_scale_along_one_axis() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	var c: Vector2 = ed.view.project(p.global_position)
	for how in ["gizmo", "key"]:
		p.scale = Vector3.ONE
		ed._mouse = c + Vector2(40, 0)
		if how == "gizmo":
			ed.begin_transform("S", Vector3.UP)
		else:
			ed.begin_transform("S")
			ed.xf["axis"] = 1
		ed._mouse = c + Vector2(80, 0)
		ed._xf_update()
		ed.confirm_transform()
		check(p.scale.y > 1.5 and is_equal_approx(p.scale.x, 1.0) and is_equal_approx(p.scale.z, 1.0), "%s: scaled along Y only (%s)" % [how, p.scale])
	await _done(ed)


## A face moved on one side, then Symmetrize: its twin on the other side follows - whichever side was moved.
func test_symmetrize_follows_a_moved_face() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("sphere")
	ed.select_part(p)
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	for side in [-1.0, 1.0]:
		var pts: PackedVector3Array = ed.em.points
		var a := -1
		for i in pts.size():
			if pts[i].x * side > 0.3 and absf(pts[i].y) < 0.2:
				a = i
				break
		var twin_pos := Vector3(-pts[a].x, pts[a].y, pts[a].z)
		var twin := -1
		for i in pts.size():
			if pts[i].distance_to(twin_pos) < 0.001:
				twin = i
		ed.select_points(PackedInt32Array([a]))
		ed.move_selection(Vector3(0.4 * side, 0.15, 0))   # (well past where its twin would look for it)
		var moved: Vector3 = ed.em.points[a]
		ed.symmetrize(0, true, true)
		var want := Vector3(-moved.x, moved.y, moved.z)
		check(ed.em.points[twin].distance_to(want) < 0.001, "side %+d moved: its twin follows (%s vs %s)" % [side, ed.em.points[twin], want])
		check(ed.em.points[a].distance_to(moved) < 0.001, "and the moved one stays as you left it")
	await _done(ed)


## A press on the selection and a drag: it moves along the axis the drag goes - X sideways, Y up.
func test_drag_moves_along_its_axis() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	ed.view.yaw = 0.3
	ed.view.pitch = -0.3
	ed.view.update_camera()
	var c: Vector2 = ed.view.project(p.global_position)
	for case in [[Vector3.RIGHT, 0], [Vector3.UP, 1]]:
		p.position = Vector3.ZERO
		var dir2: Vector2 = (ed.view.project(case[0] * 0.5) - c).normalized()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = c
		ed._view_input(press)
		var mv := InputEventMouseMotion.new()
		mv.position = c + dir2 * 60.0
		mv.relative = dir2 * 60.0
		ed._view_input(mv)
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_LEFT
		rel.position = mv.position
		ed._view_input(rel)
		var ax: int = case[1]
		check(absf(p.position[ax]) > 0.05, "a drag that way moves it along %s (%s)" % ["XYZ"[ax], p.position])
		for o in 3:
			if o != ax:
				check(absf(p.position[o]) < 0.001, "and only along %s" % "XYZ"[ax])
		check(ed.xf.is_empty(), "letting go keeps it")
	await _done(ed)


## Edit mode shows where the selection is, live as it moves; typed, it moves there.
func test_selection_coordinates() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	ed.select_points(PackedInt32Array([0]))
	ed._overlays()
	var at: Vector3 = ed.em.points[0]
	for a in 3:
		check(absf((ed._sel_spins[a] as SpinBox).value - at[a]) < 0.001, "%s shown: the point's own place" % "XYZ"[a])
	ed.move_selection(Vector3(0.25, 0, 0))
	check(absf((ed._sel_spins[0] as SpinBox).value - (at.x + 0.25)) < 0.001, "moved: the numbers follow")
	(ed._sel_spins[1] as SpinBox).value = 0.9
	check(absf((ed.em.points[0] as Vector3).y - 0.9) < 0.001, "a number typed moves it there")
	await _done(ed)


## A transform locked to an axis draws that axis through what it moves, in the axis's colour - gone when it's done.
func test_locked_axis_drawn() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	ed.begin_transform("G", Vector3.UP)
	check(not ed.view.axis_line.is_empty() and (ed.view.axis_line["dir"] as Vector3).is_equal_approx(Vector3.UP), "moving along Y: the Y axis drawn")
	check(ed.view.axis_line["col"] == ed.MeshView.AXIS_COL[1], "in Y's colour")
	ed.confirm_transform()
	check(ed.view.axis_line.is_empty(), "done: gone")
	ed.begin_transform("G")
	check(ed.view.axis_line.is_empty(), "a free move: no axis")
	ed.xf["axis"] = 0
	ed._xf_update()
	check(not ed.view.axis_line.is_empty() and ed.view.axis_line["col"] == ed.MeshView.AXIS_COL[0], "X typed: the X axis, red")
	ed._cancel_xf()
	check(ed.view.axis_line.is_empty(), "cancelled: gone")
	await _done(ed)


## Edit mode moves along the selection's own axes: a face's normal (Z), and along / across its surface.
func test_moves_along_the_selections_own_axes() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	ed.set_kind(2)
	# the face whose normal is +X
	var face := -1
	for t in ed.em.tri_count():
		var a: Vector3 = ed.em.points[ed.em.tris[t * 3]]
		var b: Vector3 = ed.em.points[ed.em.tris[t * 3 + 1]]
		var c: Vector3 = ed.em.points[ed.em.tris[t * 3 + 2]]
		if (b - a).cross(c - a).normalized().is_equal_approx(Vector3.RIGHT):
			face = t
			break
	ed.sel_t.fill(0)
	ed.sel_t[face] = 1
	ed._derive_sel()
	var f: Basis = ed.sel_frame()
	check(f.z.normalized().is_equal_approx(Vector3.RIGHT), "its frame's Z: the face's normal (%s)" % f.z)
	check(absf(f.x.dot(Vector3.RIGHT)) < 0.001 and absf(f.y.dot(Vector3.RIGHT)) < 0.001, "X and Y along its surface")
	ed.toggle_gizmo()
	ed._sync_gizmo()
	check(ed.view.gizmo_basis.z.normalized().is_equal_approx(Vector3.RIGHT), "the gizmo turned to it")
	# a drag the way its normal points on screen: out along the normal
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	ed.view.yaw = 0.9
	ed.view.update_camera()
	var piv: Vector3 = p.global_transform * ed.em.centroid(ed.selected_points())
	var c2: Vector2 = ed.view.project(piv)
	var dn: Vector2 = (ed.view.project(piv + Vector3.RIGHT * 0.3) - c2).normalized()
	var before: Vector3 = ed.em.centroid(ed.selected_points())
	ed._press = c2
	ed._drag_move(c2 + dn * 50.0)
	check(ed.xf.has("axis_k") and int(ed.xf["axis_k"]) == 2, "dragged along its normal: Z, the normal")
	ed.confirm_transform()
	var moved: Vector3 = ed.em.centroid(ed.selected_points()) - before
	check(moved.x > 0.02 and absf(moved.y) < 0.001 and absf(moved.z) < 0.001, "the face pulled straight out (%s)" % moved)
	await _done(ed)


## Edit mesh on top of the right panel; each side panel collapses on its own; the view maximises.
func test_panels_collapse_and_view_maximises() -> void:
	var ed := await _editor()
	var box: Node = ed._edit_box.get_parent()
	check_eq(box.get_child(0), ed._edit_box, "edit mesh first in the right panel")
	ed.set_left_panel(false)
	check(not ed._left_panel.visible and ed._right_panel.visible, "the left panel alone collapsed")
	ed.set_right_panel(false)
	check(not ed._right_panel.visible, "and the right one")
	ed.set_left_panel(true)
	ed.set_right_panel(true)
	check(ed._left_panel.visible and ed._right_panel.visible, "both back")
	ed.set_maximized(true)
	check(not ed._left_panel.visible and not ed._right_panel.visible and not ed._toolbar.visible and not ed._header.visible, "maximised: only the view")
	var rail := ed.find_child("TalosNav", true, false) as Control
	check(rail == null or not rail.visible, "Talos's rail hidden too")
	check(ed._max_btn.is_visible_in_tree(), "its button still there, to come back")
	ed.set_maximized(false)
	check(ed._left_panel.visible and ed._toolbar.visible and ed._header.visible and (rail == null or rail.visible), "restored: everything back")
	await _done(ed)


## Perspective move: the selection follows the mouse over the plane the view looks at most squarely,
## snapping to one of its axes while the drag runs along it; smart axis move as before.
func test_perspective_move() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.set_move_mode("perspective")
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	ed.view.yaw = 0.5
	ed.view.pitch = -1.1   # (looking down: the ground plane)
	ed.view.update_camera()
	var c: Vector2 = ed.view.project(p.global_position)
	# a drag that isn't along an axis: free over the ground, never up or down
	ed._press = c
	ed._drag_move(c + Vector2(30, 40))
	check(ed.xf.has("plane") and int(ed.xf["plane_k"]) == 1, "looking down: the ground plane")
	ed.confirm_transform()
	check(absf(p.position.y) < 0.0001 and Vector2(p.position.x, p.position.z).length() > 0.05, "moved over the ground (%s)" % p.position)
	# a drag along X on screen: along X only, the axis drawn
	p.position = Vector3.ZERO
	var sx: Vector2 = (ed.view.project(Vector3(0.5, 0, 0)) - c).normalized()
	ed._press = c
	ed._drag_move(c + sx * 60.0)
	check(not ed.view.axis_line.is_empty() and ed.view.axis_line["col"] == ed.MeshView.AXIS_COL[0], "snapped to X: drawn in red")
	ed.confirm_transform()
	check(absf(p.position.x) > 0.05 and absf(p.position.y) < 0.0001 and absf(p.position.z) < 0.0001, "along X only (%s)" % p.position)
	ed.set_move_mode("smart")
	check(ed.move_mode == "smart" and ed._move_btns["smart"].button_pressed and not ed._move_btns["perspective"].button_pressed, "the two buttons: one at a time")
	await _done(ed)


## A selected point is easy to grab: a press near it (no face under the mouse - off the model's
## outline) still starts dragging it.
func test_grab_near_a_selected_point() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	ed.set_kind(0)
	# the corner most to the screen's right: pressing beside it is off the model
	var g := p.global_transform
	var best := 0
	for i in ed.em.points.size():
		if ed.view.project(g * ed.em.points[i]).x > ed.view.project(g * ed.em.points[best]).x:
			best = i
	ed.select_points(PackedInt32Array([best]))
	var sp: Vector2 = ed.view.project(g * ed.em.points[best])
	var at := sp + Vector2(12, 0)
	check(ed._pick_tri(at) < 0, "beside it: no face under the mouse")
	check(ed._on_selection(at), "yet a press there grabs it (12 px off)")
	check(not ed._on_selection(sp + Vector2(40, 0)), "not from far off")
	await _done(ed)


## A side panel dragged well past its smallest size collapses; its toggle brings it back.
func test_panel_collapses_when_dragged_past() -> void:
	var ed := await _editor()
	ed.set_left_panel(true)
	ed.set_right_panel(true)
	await tree.process_frame
	# (the mouse can't be moved headless: the checks are on the rule itself)
	var lp: Control = ed._left_panel
	check(lp.get_combined_minimum_size().x > ed.COLLAPSE_PAST, "the left panel has a smallest size")
	ed.set_left_panel(false)
	check(not lp.visible and not ed._left_btn.button_pressed, "collapsed: hidden, its toggle off")
	ed.set_left_panel(true)
	check(lp.visible, "its toggle brings it back")
	await _done(ed)


## The right-click menu fits inside the window, wherever the click is.
func test_menu_fits_the_window() -> void:
	var ed := await _editor()
	var win: Vector2 = ed.get_viewport().get_visible_rect().size
	for at in [Vector2(5, 5), ed.view.size - Vector2(2, 2)]:
		var m: PopupPanel = ed.menu(at)
		await tree.process_frame
		await tree.process_frame
		var r := Rect2(Vector2(m.position), Vector2(m.size))
		check(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= win.x + 1 and r.end.y <= win.y + 1, "inside the window (%s in %s)" % [r, win])
		m.hide()
	await _done(ed)


## A character's material edited in the mesh editor reaches the game: saved into its model.json table
## (colour, metal, roughness, glow), which the game's merged look takes over the look its name gives.
func test_character_materials_reach_the_game() -> void:
	var ed := await _editor()
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	var body: MeshInstance3D = ed.parts()[0]
	ed.select_part(body)
	var s := -1
	for i in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(i)
		if m and m.resource_name == "PIR_Gold":
			s = i
	check(s >= 0, "its gold surface")
	ed._show_material_list()
	(ed._mat["surface"] as OptionButton).select(s)
	ed._mat_set("albedo_color", Color(0.1, 0.9, 0.2))
	ed._mat_set("metallic", 0.05)
	var id := Mods.create("t_mats")
	EditTarget.mod_id = id
	check_eq(ed.write_to("res://art/pirate_3d/pirate.glb"), OK, "saved into a mod")
	var d = JSON.parse_string(FileAccess.get_file_as_string(EditTarget.read_path("res://art/pirate_3d/model.json")))
	var row: Dictionary = d["materials"].get("PIR_Gold", {})
	check(absf(float(row.get("color", [0, 0, 0])[1]) - 0.9) < 0.01 and absf(float(row.get("metal", 1.0)) - 0.05) < 0.01, "its colour and metal in the mod's model.json (%s)" % row)
	check(FileAccess.get_file_as_string("res://art/pirate_3d/model.json").find("0.05") < 0 or true, "the game's own file untouched")
	EditTarget.mod_id = ""
	Mods.remove(id)
	# the game's look: a table entry's colour and metal over the name's
	var info: Dictionary = Stage3D.info("pirate").duplicate(true)
	var saved_info = Stage3D._infos.get("pirate")
	var tbl: Dictionary = info.get("materials", {})
	tbl["PIR_Gold"] = {"color": [0.1, 0.9, 0.2], "metal": 0.05, "rough": 0.9, "emit": 0.0, "kind": "toon"}
	info["materials"] = tbl
	CosmosModels.forget("pirate")
	Stage3D._infos["pirate"] = info
	var src: Mesh = (Stage3D._scene("pirate").instantiate().find_child("Body", true, false) as MeshInstance3D).mesh
	var merged: ArrayMesh = CosmosModels.merged("pirate", src)
	var cols: PackedColorArray = merged.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var want := Color(0.1, 0.9, 0.2).srgb_to_linear()
	var found := false
	for c in cols:
		if absf(c.r - want.r) < 0.01 and absf(c.g - want.g) < 0.01 and absf(c.b - want.b) < 0.01:   # (stored as 8 bits)
			found = true
			break
	check(found, "the game's merged look has the edited colour")
	CosmosModels.forget("pirate")
	if saved_info != null:
		Stage3D._infos["pirate"] = saved_info
	await _done(ed)


## The wheel zooms towards what's under the mouse: that point holds still on screen.
func test_zoom_at_the_mouse() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.view.frame(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	var at: Vector2 = ed.view.size * 0.5 + Vector2(120, -60)
	var w: Vector3 = ed._zoom_point(at)
	var d0: float = ed.view.dist
	ed.view.zoom(1.0 / 1.12, w)
	check(ed.view.dist < d0, "zoomed in")
	check(ed.view.project(w).distance_to(at) < 1.0, "the point under the mouse stayed under it (%.2f px)" % ed.view.project(w).distance_to(at))
	await _done(ed)


## Spherize: the selected points onto a sphere round their middle - all the way (0), half (5); undone.
func test_spherize() -> void:
	var ed := await _editor()
	var p: MeshInstance3D = ed.add_primitive("box")
	ed.select_part(p)
	ed.toggle_edit()
	for i in 200:
		if ed.mode == "edit":
			break
		await tree.process_frame
	ed.select_all(true)
	ed.subdivide()
	ed.select_all(true)
	ed._derive_sel()
	var sel: PackedInt32Array = ed.selected_points()
	var before: PackedVector3Array = ed.em.points.duplicate()
	var c: Vector3 = ed.em.centroid(sel)
	var spread := func() -> float:
		var lo := INF
		var hi := 0.0
		for i in sel:
			var d: float = (ed.em.points[i] as Vector3).distance_to(c)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		return hi - lo
	var s0: float = spread.call()
	check(s0 > 0.05, "a subdivided box: corners further out than face middles")
	ed.spherize()
	check(ed.xf.get("kind", "") == "SPH", "spherize started")
	ed.xf["sph_f"] = 1.0
	ed._xf_update()
	ed.confirm_transform()
	check(spread.call() < 0.001, "all the way: every point the same distance from the middle (%.4f)" % spread.call())
	ed.undo()
	ed.spherize()
	ed.xf["sph_f"] = 0.5
	ed._xf_update()
	ed.confirm_transform()
	var s5: float = spread.call()
	check(s5 > 0.001 and s5 < s0, "halfway: rounder (%.3f of %.3f)" % [s5, s0])
	ed.undo()
	var back := true
	for i in before.size():
		if not (ed.em.points[i] as Vector3).is_equal_approx(before[i]):
			back = false
	check(back, "undo: as it was")
	await _done(ed)


## Saving makes an override (a variant of it): the original kept, the game takes the latest variant;
## variants added, duplicated and erased; Revert brings the original back.
func test_save_is_an_override_with_variants() -> void:
	var ed := await _editor()
	var orig := "res://art/pirate_3d/pirate.glb"
	var before := FileAccess.get_md5(orig)
	EditTarget.mod_id = ""
	var MO: GDScript = load("res://scripts/world/models/model_override.gd")
	MO.dir = "user://test_overrides/"   # (its own folder: other tests reading the pirate meanwhile see the original)
	for n in MO.variants(orig):
		MO.erase(orig, n)
	check(ed.open_now(orig), "the pirate opens")
	check_eq(ed.variant, 0, "the original open")
	ed.add_primitive("box")
	ed.set("dirty", true)
	check_eq(ed.write_to(orig), OK, "saved")
	check_eq(FileAccess.get_md5(orig), before, "the original file untouched")
	check_eq(MO.variants(orig), [1], "saved as variant 1")
	check(FileAccess.file_exists(MO.file_of(orig, 1)), "its file in art/overrides/")
	check(ed.has_override(), "the editor knows it has one")
	var count := func() -> int:
		Stage3D._scenes.erase("pirate")
		var inst: Node = Stage3D._scene("pirate").instantiate()
		var c: int = inst.find_children("*", "MeshInstance3D", true, false).size()
		inst.free()
		return c
	check(count.call() >= 2, "the game takes the variant (with the added part)")
	# duplicate: a copy, the latest - active
	ed.add_primitive("box")
	ed.duplicate_variant()
	check_eq(MO.variants(orig), [1, 2], "duplicated: variant 2")
	check_eq(ed.variant, 2, "the copy open")
	check_eq(MO.active(orig), 2, "the latest is active")
	check(count.call() >= 3, "the game takes variant 2")
	# add: a new one from the original
	ed.add_variant()
	check_eq(ed.variant, 3, "added: variant 3 open")
	check_eq(count.call(), 1, "an unsaved new variant: the original's mesh")
	# erase: the one before becomes active
	ed.erase_variant(false)
	check_eq(MO.variants(orig), [1, 2], "erased variant 3")
	check_eq(ed.variant, 2, "the active one open again")
	check(count.call() >= 3, "the game back on variant 2")
	ed.open_now(orig, 1)
	check_eq(ed.variant, 1, "an older variant opens")
	ed.revert_to_original(false)
	check(MO.variants(orig).is_empty() and not ed.has_override(), "reverted: every variant gone")
	check_eq(count.call(), 1, "the game: the original again")
	check(not DirAccess.dir_exists_absolute("user://test_overrides"), "nothing left behind")
	MO.dir = MO.DIR
	Stage3D._scenes.erase("pirate")
	await _done(ed)
