extends TestCase
## Parts bound to a character's skeleton: a part added beside a skinned body is skinned to
## it by itself (each vertex to its nearest bones), or rigidly to one bone; it stays where
## it's drawn; saved, the game merges it into the body (its look, its animation); added in
## the T-pose, it's saved back in the character's own pose.

const SCENE := "res://scenes/editor/mesh_editor.tscn"
const TPose := preload("res://scripts/editor/mesh/tpose.gd")
const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")


func _pirate() -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now("res://art/pirate_3d/pirate.glb"), "the pirate opens")
	return ed


func _done(ed: Control) -> void:
	ed.queue_free()
	await tree.process_frame


func _bind_index(ed: Control, bone: String) -> int:
	var bs: Array = ed.MeshBind.binds(ed._rig())
	for k in bs.size():
		if bs[k][1] == bone:
			return k
	return -1


## Where part `p`'s vertices are drawn (the skeleton's space): skinned by its bind matrices,
## or (T-posed) as they are.
func _drawn(ed: Control, p: MeshInstance3D) -> PackedVector3Array:
	var rig: Dictionary = ed._rig()
	var a := p.mesh.surface_get_arrays(0)
	if p.has_meta("tpose"):
		return a[Mesh.ARRAY_VERTEX]
	var baked: Array = TPose.bake(p.mesh, rig["mats"])
	return baked[0][1][Mesh.ARRAY_VERTEX]


func test_a_box_on_the_hand_binds_to_it() -> void:
	var ed := await _pirate()
	var body: MeshInstance3D = ed.parts()[0]
	var box: MeshInstance3D = ed.add_primitive("box")
	check(box.has_meta("bound_part") and box.skin == body.skin, "an added part is bound by itself")
	check(box.get_node_or_null(box.skeleton) == body.get_node(body.skeleton), "to the body's skeleton")
	ed.undo()
	check(box.get_parent() == null, "adding (and binding) is one undo step")
	ed.redo()
	# moved onto the left hand, bound again where it is
	var rig: Dictionary = ed._rig()
	var skel: Skeleton3D = rig["skel"]
	var hand := skel.find_bone("hand.L")
	var at: Vector3 = skel.global_transform * (rig["g"][hand] as Transform3D).origin
	ed.unbind_part(box)
	box.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.06), at)
	var want: PackedVector3Array = box.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var g0 := box.global_transform
	check(ed.bind_part(box), "bound again")
	var drawn := _drawn(ed, box)
	var worst := 0.0
	var sk_inv := skel.global_transform.affine_inverse()
	for i in want.size():
		worst = maxf(worst, drawn[i].distance_to(sk_inv * (g0 * want[i])))
	check(worst < 1e-3, "drawn where it was (%.5f m off)" % worst)
	var a := box.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var arm := 0.0
	var all := 0.0
	var on_arm := [_bind_index(ed, "hand.L"), _bind_index(ed, "fore.L"), _bind_index(ed, "fingers.L")]
	for i in bones.size():
		all += weights[i]
		if bones[i] in on_arm:
			arm += weights[i]
	check(arm / all > 0.7, "its weights mostly on the hand and forearm (%.0f%%)" % (arm / all * 100.0))
	# all on one bone
	var head := _bind_index(ed, "head")
	check(ed.bind_part(box, head), "bound to the head")
	a = box.mesh.surface_get_arrays(0)
	bones = a[Mesh.ARRAY_BONES]
	weights = a[Mesh.ARRAY_WEIGHTS]
	var rigid := true
	for i in range(0, bones.size(), 4):
		rigid = rigid and bones[i] == head and is_equal_approx(weights[i], 1.0)
	check(rigid, "bind to bone: every vertex all on it")
	check(ed._fill_parts() == null and ed._parts.get_root().get_child(ed._parts.get_root().get_child_count() - 1).get_text(0).contains("bound"), "the parts list says it's bound")
	await _done(ed)


## Saved into a mod and read back: the game merges the bound box into the body (its look,
## its bones): the merged mesh has its vertices, and they move with their bone.
func test_saved_and_merged_in_the_game() -> void:
	var ed := await _pirate()
	var box: MeshInstance3D = ed.add_primitive("box")
	ed.bind_part(box, _bind_index(ed, "head"))
	var id: String = Mods.create("t_bind")
	EditTarget.mod_id = id
	check_eq(ed.write_to("res://art/test_bind/pirate_b.glb"), OK, "saved")
	var n: Node3D = MeshIO.read(EditTarget.read_path("res://art/test_bind/pirate_b.glb"))
	await _done(ed)
	tree.root.add_child(n)
	var body: MeshInstance3D = n.find_child("Body", true, false)
	var others := n.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m != body)
	check(others.size() == 1 and (others[0] as MeshInstance3D).skin != null, "the box read back, skinned")
	var nv0 := 0
	for i in body.mesh.get_surface_count():
		nv0 += body.mesh.surface_get_array_len(i)
	CosmosModels._meshes.erase("pirate")
	CosmosModels.apply(n, "pirate")
	var m: ArrayMesh = body.mesh
	check(m.get_surface_count() == 1 and m.surface_get_array_len(0) > 0, "merged")
	check(not (others[0] as MeshInstance3D).visible, "the box is drawn as part of the body")
	var merged_n := m.surface_get_array_len(0)
	CosmosModels._meshes.erase("pirate")
	var plain: Node3D = MeshIO.read("res://art/pirate_3d/pirate.glb")
	tree.root.add_child(plain)
	CosmosModels.apply(plain, "pirate")
	var plain_n: int = (plain.find_child("Body", true, false) as MeshInstance3D).mesh.surface_get_array_len(0)
	check_eq(merged_n - plain_n, others[0].mesh.surface_get_array_len(0), "the merged mesh has the box's vertices too (%d -> %d)" % [plain_n, merged_n])
	# the head turned: the box's vertices move with it
	var sk := body.get_node(body.skeleton) as Skeleton3D
	var hb := sk.find_bone("head")
	var g := []
	for i in sk.get_bone_count():
		g.append(sk.get_bone_global_pose(i))
	var g2 := g.duplicate()
	for i in sk.get_bone_count():
		var b := i
		while b >= 0 and b != hb:
			b = sk.get_bone_parent(b)
		if b == hb:
			g2[i] = Transform3D(Basis(Vector3.UP, 0.8), Vector3.ZERO) * (g[i] as Transform3D)
	var a0: Array = TPose.bake(m, TPose.matrices(body, sk, g))
	var a1: Array = TPose.bake(m, TPose.matrices(body, sk, g2))
	var v0: PackedVector3Array = a0[0][1][Mesh.ARRAY_VERTEX]
	var v1: PackedVector3Array = a1[0][1][Mesh.ARRAY_VERTEX]
	var moved := 0
	for i in range(plain_n, merged_n):
		if v0[i].distance_to(v1[i]) > 0.01:
			moved += 1
	check_eq(moved, merged_n - plain_n, "with the head turned, every box vertex moves")
	CosmosModels._meshes.erase("pirate")
	n.queue_free()
	plain.queue_free()
	EditTarget.mod_id = ""
	Mods.remove(id)


## Added in the T-pose: bound with the body's T-pose, saved back in its own pose.
func test_added_in_the_tpose_saved_in_its_own_pose() -> void:
	var ed := await _pirate()
	ed.toggle_tpose()
	for i in 600:
		if ed._tpose_task < 0 and ed.is_tposed():
			break
		await tree.process_frame
	check(ed.is_tposed(), "T-posed")
	var rig: Dictionary = ed._rig()
	var skel: Skeleton3D = rig["skel"]
	var hand := skel.find_bone("hand.L")
	var at: Vector3 = skel.global_transform * (rig["g"][hand] as Transform3D).origin
	var box: MeshInstance3D = ed.add_primitive("box")
	ed.unbind_part(box)
	box.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.06), at)
	check(ed.bind_part(box), "bound in the T-pose")
	check(box.has_meta("tpose") and box.get_meta("tpose_mats") == rig["body"].get_meta("tpose_mats"), "with the body's T-pose")
	var tpose_v: PackedVector3Array = box.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var id: String = Mods.create("t_bind_t")
	EditTarget.mod_id = id
	check_eq(ed.write_to("res://art/test_bind/pirate_t.glb"), OK, "saved")
	var n: Node3D = MeshIO.read(EditTarget.read_path("res://art/test_bind/pirate_t.glb"))
	var body: MeshInstance3D = n.find_child("Body", true, false)
	var saved: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m != body)[0]
	var own: PackedVector3Array = saved.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var back: PackedVector3Array = TPose.bake(saved.mesh, rig["body"].get_meta("tpose_mats"))[0][1][Mesh.ARRAY_VERTEX]
	var far := 0.0
	var worst := 0.0
	for i in own.size():
		far = maxf(far, own[i].distance_to(tpose_v[i]))
		worst = maxf(worst, back[i].distance_to(tpose_v[i]))
	check(far > 0.05, "saved in the character's own pose, not the T (%.2f m away)" % far)
	check(worst < 1e-3, "which the T-pose turns back into where it was (%.5f m)" % worst)
	n.free()
	EditTarget.mod_id = ""
	Mods.remove(id)
	await _done(ed)
