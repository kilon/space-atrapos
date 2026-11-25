extends TestCase
## Parts from bones: a character's bones given simple body parts - a loft along each bone,
## fitted to the body's vertices weighted to it, named after it and skinned all to it; made
## for one bone, a bone and the bones below it, or all; one undo step; right in the T-pose
## too (saved back in the character's own pose); saved, the game merges them into the body
## and they move with its animations.

const SCENE := "res://scenes/editor/mesh_editor.tscn"
const TPose := preload("res://scripts/editor/mesh/tpose.gd")
const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")


## (the automaton by default: the pirate may have an override for a moment while another test runs)
func _open(path := "res://art/player_3d/player.glb") -> Control:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.open_now(path), "the character opens")
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


## Part `p`'s vertices where they're drawn (the skeleton's space).
func _drawn(ed: Control, p: MeshInstance3D) -> PackedVector3Array:
	if p.has_meta("tpose"):
		return p.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return TPose.bake(p.mesh, ed._rig()["mats"])[0][1][Mesh.ARRAY_VERTEX]


## How far part `p` (drawn) is from its bone: [its centre's distance to the bone's segment
## (head to child's head), its farthest vertex from it].
func _off_bone(ed: Control, p: MeshInstance3D, bone: String, child: String) -> Array:
	var rig: Dictionary = ed._rig()
	var skel: Skeleton3D = rig["skel"]
	var a: Vector3 = (rig["g"][skel.find_bone(bone)] as Transform3D).origin
	var b: Vector3 = (rig["g"][skel.find_bone(child)] as Transform3D).origin
	var vs := _drawn(ed, p)
	var c := Vector3.ZERO
	var far := 0.0
	for v in vs:
		c += v
		far = maxf(far, v.distance_to(Geometry3D.get_closest_point_to_segment(v, a, b)))
	c /= vs.size()
	return [c.distance_to(Geometry3D.get_closest_point_to_segment(c, a, b)), far]


func _all_on(p: MeshInstance3D, bind: int) -> bool:
	var a := p.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	for i in range(0, bones.size(), 4):
		if bones[i] != bind or not is_equal_approx(weights[i], 1.0):
			return false
	return bones.size() > 0


func test_a_bone_and_its_children() -> void:
	var ed := await _open()
	var rig: Dictionary = ed._rig()
	var body: MeshInstance3D = rig["body"]
	var n0: int = ed.parts().size()
	var up := _bind_index(ed, "upper.L")
	check(up >= 0, "the automaton has an upper arm")
	var made: Array = ed.parts_from_bones("children", up)
	var names := made.map(func(p): return str(p.get_meta("bone_part")))
	check("upper.L" in names and "fore.L" in names and "hand.L" in names, "parts for the arm from the shoulder down (%s)" % ", ".join(names))
	check(not ("upper.R" in names or "head" in names), "and nothing else")
	check_eq(ed.parts().size(), n0 + made.size(), "added to the model")
	for p: MeshInstance3D in made:
		check(p.has_meta("bound_part") and p.skin == body.skin and p.get_node_or_null(p.skeleton) == rig["skel"], "%s is bound to the body's skeleton" % p.name)
		check(_all_on(p, _bind_index(ed, str(p.get_meta("bone_part")))), "%s is all on its bone" % p.name)
		check(str(p.name).begins_with(str(p.get_meta("bone_part")).validate_node_name()), "named after its bone (%s)" % p.name)
		check(p.mesh.surface_get_material(0) != null, "with a material")
	var upper: MeshInstance3D = made[names.find("upper.L")]
	var off := _off_bone(ed, upper, "upper.L", "fore.L")
	check(off[0] < 0.05, "the upper arm's part is along its bone (%.3f m off)" % off[0])
	check(off[1] > 0.02 and off[1] < 0.25, "about as thick as the arm (%.3f m out)" % off[1])
	ed.undo()
	check(made.all(func(p): return p.get_parent() == null), "one undo step takes them all")
	ed.redo()
	check(made.all(func(p): return p.get_parent() != null), "and redo brings them back")
	await _done(ed)


func test_one_bone_and_all_bones() -> void:
	var ed := await _open()
	var head := _bind_index(ed, "head")
	var one: Array = ed.parts_from_bones("bone", head)
	check(one.size() == 1 and str(one[0].get_meta("bone_part")) == "head", "one part, for the head")
	check(_all_on(one[0], head), "all on the head")
	ed.undo()
	var all: Array = ed.parts_from_bones("all")
	var bs: Array = ed.MeshBind.binds(ed._rig())
	var want := 0
	for b in bs:
		if int(b[0]) >= 0 and not (str(b[1]).to_lower() in TPose.WEAPON_BONES):
			want += 1
	check_eq(all.size(), want, "all bones: one part each (but the weapon's)")
	var seen := {}
	for p in all:
		seen[str(p.name)] = true
	check_eq(seen.size(), all.size(), "each its own name")
	ed.undo()
	check(all.all(func(p): return p.get_parent() == null), "one undo step")
	# no bone picked, no part selected: nothing (and it says why)
	check(ed.parts_from_bones("bone", -2).is_empty(), "no bone: no part")
	await _done(ed)


## Made in the T-pose: along the T-posed bones, saved back in the character's own pose - where
## the same part made out of the T-pose is.
func test_in_the_tpose() -> void:
	var ed := await _open()
	var fore := _bind_index(ed, "fore.L")
	var plain: MeshInstance3D = ed.parts_from_bones("bone", fore)[0]
	var plain_v := _drawn(ed, plain)
	ed.undo()
	ed.toggle_tpose()
	for i in 600:
		if ed._tpose_task < 0 and ed.is_tposed():
			break
		await tree.process_frame
	check(ed.is_tposed(), "T-posed")
	var rig: Dictionary = ed._rig()
	var p: MeshInstance3D = ed.parts_from_bones("bone", fore)[0]
	check(p.has_meta("tpose") and p.get_meta("tpose_mats") == rig["body"].get_meta("tpose_mats"), "with the body's T-pose")
	var off := _off_bone(ed, p, "fore.L", "hand.L")
	check(off[0] < 0.05, "along the T-posed forearm (%.3f m off)" % off[0])
	var id: String = Mods.create("t_bone_parts")
	EditTarget.mod_id = id
	check_eq(ed.write_to("res://art/test_bone_parts/player_t.glb"), OK, "saved")
	var n: Node3D = MeshIO.read(EditTarget.read_path("res://art/test_bone_parts/player_t.glb"))
	var saved: MeshInstance3D = n.find_child(str(p.name), true, false)
	check(saved != null and saved.skin != null, "read back, skinned")
	if saved:
		var c0 := Vector3.ZERO
		for v in plain_v:
			c0 += v
		c0 /= plain_v.size()
		# (drawn at rest by its own bind: where the same part made out of the T-pose is)
		var rest := TPose.bake(saved.mesh, _rest_mats(n))[0][1][Mesh.ARRAY_VERTEX] as PackedVector3Array
		var c1 := Vector3.ZERO
		for v in rest:
			c1 += v
		c1 /= rest.size()
		check(c1.distance_to(c0) < 0.03, "saved in the character's own pose: where it'd be made out of the T (%.3f m)" % c1.distance_to(c0))
	n.free()
	EditTarget.mod_id = ""
	Mods.remove(id)
	await _done(ed)


## The skin binds' matrices of a read-back model in its rest pose.
func _rest_mats(n: Node3D) -> Array:
	var body: MeshInstance3D = n.find_child("Body", true, false)
	var sk := body.get_node(body.skeleton) as Skeleton3D
	var g := []
	for i in sk.get_bone_count():
		g.append(sk.get_bone_global_rest(i))
	return TPose.matrices(body, sk, g)


## Saved into a mod and read back: the game merges the parts into the body, and an animation
## moves them.
func test_saved_merged_and_animated() -> void:
	var ed := await _open()
	var made: Array = ed.parts_from_bones("children", _bind_index(ed, "fore.L"))
	var want_names := made.map(func(p): return str(p.name))
	var id: String = Mods.create("t_bone_parts2")
	EditTarget.mod_id = id
	check_eq(ed.write_to("res://art/test_bone_parts/player_b.glb"), OK, "saved")
	var n: Node3D = MeshIO.read(EditTarget.read_path("res://art/test_bone_parts/player_b.glb"))
	await _done(ed)
	tree.root.add_child(n)
	var body: MeshInstance3D = n.find_child("Body", true, false)
	var others := n.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m != body and m.skin != null)
	check_eq(others.size(), want_names.size(), "the parts read back, skinned")
	check(others.all(func(o): return str(o.name) in want_names), "with their names (%s)" % ", ".join(others.map(func(o): return str(o.name))))
	var nv := 0
	for o: MeshInstance3D in others:
		nv += o.mesh.surface_get_array_len(0)
	CosmosModels._meshes.erase("player")
	CosmosModels.apply(n, "player")
	var m: ArrayMesh = body.mesh
	var merged_n := m.surface_get_array_len(0)
	check(others.all(func(o): return not o.visible), "drawn as part of the body")
	CosmosModels._meshes.erase("player")
	var plain: Node3D = MeshIO.read("res://art/player_3d/player.glb")
	tree.root.add_child(plain)
	CosmosModels.apply(plain, "player")
	var plain_n: int = (plain.find_child("Body", true, false) as MeshInstance3D).mesh.surface_get_array_len(0)
	check_eq(merged_n - plain_n, nv, "the merged mesh has the parts' vertices (%d -> %d)" % [plain_n, merged_n])
	# an animation played: the parts' vertices move with the arm
	var sk := body.get_node(body.skeleton) as Skeleton3D
	var g0 := []
	for i in sk.get_bone_count():
		g0.append(sk.get_bone_global_rest(i))
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0] if not n.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	check(ap != null, "the model has its animations")
	if ap:
		var clip := "walk" if ap.has_animation("walk") else str(ap.get_animation_list()[0])
		ap.play(clip)
		ap.seek(0.4, true)
		var g1 := []
		for i in sk.get_bone_count():
			g1.append(sk.get_bone_global_pose(i))
		var v0: PackedVector3Array = TPose.bake(m, TPose.matrices(body, sk, g0))[0][1][Mesh.ARRAY_VERTEX]
		var v1: PackedVector3Array = TPose.bake(m, TPose.matrices(body, sk, g1))[0][1][Mesh.ARRAY_VERTEX]
		var moved := 0
		for i in range(plain_n, merged_n):
			if v0[i].distance_to(v1[i]) > 0.005:
				moved += 1
		check(moved > (merged_n - plain_n) * 0.9, "playing %s, the parts move with the arm (%d of %d vertices)" % [clip, moved, merged_n - plain_n])
	CosmosModels._meshes.erase("player")
	n.queue_free()
	plain.queue_free()
	EditTarget.mod_id = ""
	Mods.remove(id)
