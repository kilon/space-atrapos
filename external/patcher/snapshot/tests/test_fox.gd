extends TestCase
## The red fox's own model (CosmosFox): one shared skinned mesh made on a
## worker (one surface) over a rig each fox builds; a fox creature shows it,
## its gait chosen by speed (walk, trot, gallop - the legs in their pairs),
## standing about it sits, sniffs and leaps in its mousing pounce; the other
## canines keep the generic build.


func _creature(id: String) -> CosmosCreature:
	var k := CosmosFauna.species(id, RandomNumberGenerator.new())
	var cr := CosmosCreature.new()
	cr.setup(k, null, 5)
	tree.root.add_child(cr)
	return cr


func _fox() -> CosmosCreature:
	var a := _creature("fox")
	for i in 60:
		if a._fox.mesh != null:
			break
		a._process(0.016)
		await tree.process_frame
	return a


func test_mesh_and_rig() -> void:
	CosmosFox.start()
	var m := CosmosFox.mesh()
	check_eq(m.get_surface_count(), 1, "one surface")
	var made := CosmosFox.made
	check_eq(int(made.get("legs", 0)), 4, "four legs")
	check_eq(int(made.get("ears", 0)), 2, "two ears")
	check_eq(int(made.get("eyes", 0)), 2, "two eyes")
	check(int(made.get("whiskers", 0)) >= 4, "whiskers")
	check(int(made.get("tail_rings", 0)) >= 12, "a bushy tail")
	check_lt(float(made.get("build_ms", 0.0)), 300.0, "built quickly (on a worker)")
	var arr: Array = m.surface_get_arrays(0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var used := {}
	for b in bones:
		used[b] = true
	check_eq(used.size(), CosmosFox.BONES.size(), "every bone moves some of it")
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var white := 0
	var black := 0
	for c in cols:
		white += 1 if c.r > 0.5 else 0
		black += 1 if c.g > 0.5 else 0
	check(white > cols.size() / 20 and black > cols.size() / 20, "white chest and belly, black stockings (%d / %d of %d)" % [white, black, cols.size()])
	var sk := CosmosFox.skeleton()
	check_eq(sk.get_bone_count(), CosmosFox.BONES.size(), "the rig's bones")
	sk.free()


func test_creature_uses_it() -> void:
	var a := await _fox()
	var b := await _fox()
	check(a._fox.mesh == CosmosFox.mesh() and a._fox.mesh == b._fox.mesh, "its own model, shared")
	check(a._fox.skin == CosmosFox.skin(), "skinned to its rig")
	check(a._legs.is_empty(), "none of the generic canine's parts")
	check_eq(a.find_children("*", "MeshInstance3D", true, false).size(), 1, "one mesh instance (one draw call)")
	check(a._fox.material_override != b._fox.material_override, "each its own material (the flash)")
	a.queue_free()
	b.queue_free()
	await tree.process_frame


## The angle a bone is turned by about x.
func _ang(sk: Skeleton3D, b: int) -> float:
	return sk.get_bone_pose_rotation(b).get_euler().x


func test_gaits_by_speed() -> void:
	var a := await _fox()
	var rig: CosmosFox.Rig = a._rig
	var size := float(a.kind["size"]) * float(a.kind["scale"])
	# Trot: the diagonal pairs move together (left fore with right hind).
	for i in 200:
		rig.step(1.0 / 60.0, 1.8, size, false, false)
	check(rig.gait.y > 0.8, "trotting at its wander pace (%s)" % str(rig.gait))
	var same := 0
	var opposite := 0
	for i in 60:
		rig.step(1.0 / 60.0, 1.8, size, false, false)
		var fl := _ang(rig.sk, CosmosFox.FL_UP)
		var hr := _ang(rig.sk, CosmosFox.HR_HIP)
		var fr := _ang(rig.sk, CosmosFox.FR_UP)
		same += 1 if signf(fl) == signf(hr) else 0
		opposite += 1 if signf(fl) != signf(fr) else 0
	check(same > 40 and opposite > 40, "diagonal pairs (%d, %d of 60)" % [same, opposite])
	# Gallop when fleeing fast; a walk when slow.
	for i in 200:
		rig.step(1.0 / 60.0, 6.0, size, false, true)
	check(rig.gait.z > 0.8, "galloping when it flees (%s)" % str(rig.gait))
	for i in 200:
		rig.step(1.0 / 60.0, 0.6, size, false, false)
	check(rig.gait.x > 0.8, "walking slowly (%s)" % str(rig.gait))
	a.queue_free()
	await tree.process_frame


func test_idle_acts_and_pounce() -> void:
	var a := await _fox()
	var rig: CosmosFox.Rig = a._rig
	var size := float(a.kind["size"]) * float(a.kind["scale"])
	var seen := {}
	var top := 0.0
	var leapt := false
	for i in 60 * 120:
		rig.step(1.0 / 60.0, 0.0, size, true, false)
		seen[rig.act] = true
		top = maxf(top, rig.leap_height())
		leapt = leapt or rig.leap_speed() > 0.0
	for act in ["look", "sniff", "sit", "pounce"]:
		check(seen.has(act), "standing about it does %s" % act)
	check(top > 0.5 and leapt, "the pounce a high leap forward (%.2f)" % top)
	# Sitting lowers its rump.
	rig.act = "sit"
	rig.act_t = 10.0
	rig.pounce = -1.0
	for i in 120:
		rig.step(1.0 / 60.0, 0.0, size, true, false)
	check(rig.sk.get_bone_pose_position(CosmosFox.PELVIS).y < (CosmosFox.BONES[0][2] as Vector3).y - 0.2, "sitting: its rump down")
	a.queue_free()
	await tree.process_frame


func test_other_canines_unchanged() -> void:
	for id in ["wolf", "frostwolf", "pyrohound"]:
		var c := _creature(id)
		check(c._fox == null and c._rig == null, "%s: the generic canine" % id)
		check_eq(c._legs.size(), 4, "%s: its four legs" % id)
		c.queue_free()
	await tree.process_frame
