extends TestCase
## The mushroom mammoth's own model (CosmosMammoth): one shared skinned mesh
## made on a worker (one surface, its LODs) over a rig each mammoth builds; a
## towering calm grazer; its walk a lateral-sequence four-beat gait with the
## feet planted (IK), an amble when it hurries with never all feet off the
## ground; standing about it grazes (the trunk to the ground and up to its
## mouth), fans its ears, rests a leg, throws dust; hurt, it trumpets and
## strides off - or, hurt badly, charges. (In the world: test_cosmos.test_mammoths_calm_and_solid.)


func _creature(id: String) -> CosmosCreature:
	var k := CosmosFauna.species(id, RandomNumberGenerator.new())
	var cr := CosmosCreature.new()
	cr.setup(k, null, 5)
	tree.root.add_child(cr)
	return cr


func _mammoth() -> CosmosCreature:
	var a := _creature("mykelephas")
	for i in 60:
		if a._fox.mesh != null:
			break
		a._process(0.016)
		await tree.process_frame
	return a


func test_mesh_and_rig() -> void:
	CosmosMammoth.start()
	var m := CosmosMammoth.mesh()
	check_eq(m.get_surface_count(), 1, "one surface")
	var made := CosmosMammoth.made
	check_eq(int(made.get("legs", 0)), 4, "four legs")
	check(int(made.get("toenails", 0)) >= 12, "toenails on its feet")
	check_eq(int(made.get("tusks", 0)), 2, "two tusks")
	check_eq(int(made.get("ears", 0)), 2, "two ears")
	check_eq(int(made.get("eyes", 0)), 2, "two eyes")
	check(int(made.get("trunk_rings", 0)) >= 16, "a long ringed trunk")
	check(int(made.get("growths", 0)) >= 3, "small mushrooms on its back")
	check(int(made.get("tuft", 0)) >= 5, "a tuft on its tail")
	check_lt(int(made.get("tris", 0)), 7000, "few triangles (%d)" % int(made.get("tris", 0)))
	check(int(made.get("lods", 0)) >= 1 and int(made.get("lod_tris", 0)) < int(made.get("tris", 0)) / 2, "a lighter LOD for far off (%d)" % int(made.get("lod_tris", 0)))
	check_lt(float(made.get("build_ms", 0.0)), 400.0, "built quickly (on a worker)")
	var arr: Array = m.surface_get_arrays(0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var used := {}
	for b in bones:
		used[b] = true
	check_eq(used.size(), CosmosMammoth.BONES.size(), "every bone moves some of it")
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var fungus := 0
	var ivory := 0
	for c in cols:
		fungus += 1 if c.r > 0.15 and c.r < 0.3 else 0
		ivory += 1 if c.r > 0.5 and c.r < 0.7 else 0
	check(fungus > cols.size() / 20 and ivory > 0, "the fungus and the tusks (%d / %d of %d)" % [fungus, ivory, cols.size()])
	check((arr[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).size() == cols.size() * 3, "each vertex's rest place for the skin's detail")
	var sk := CosmosMammoth.skeleton()
	check_eq(sk.get_bone_count(), CosmosMammoth.BONES.size(), "the rig's bones")
	sk.free()


func test_towering_and_calm() -> void:
	var k := CosmosFauna.species("mykelephas", RandomNumberGenerator.new())
	check(float(k["size"]) * 1.8 > 13.0, "towering: %.0f m high" % (float(k["size"]) * 1.8))
	check_eq(str(k["temper"]), "calm", "calm: it doesn't run from you")
	check_eq(float(CosmosCreature.SIGHT["calm"]), 0.0, "it lets you come")
	var a := await _mammoth()
	check(a._fox.mesh == CosmosMammoth.mesh(), "its own model")
	check(a._fox.skin == CosmosMammoth.skin(), "skinned to its rig")
	check(a._legs.is_empty(), "none of the generic heavy kit's parts")
	check_eq(a.find_children("*", "MeshInstance3D", true, false).size(), 1, "one mesh instance (one draw call)")
	check(a.is_in_group("cam_solid"), "the camera stops short of it")
	check(a.reach > 8.0, "its bulk for shots and bites (%.1f m)" % a.reach)
	# The camera's ray through it: stopped at its flank.
	var size := float(a.kind["size"])
	var o := a.global_position + Vector3(-20.0, 1.1 * size, 0.0)
	var hit := a.cam_hit(o, Vector3.RIGHT, 40.0)
	check(hit > 20.0 - 0.6 * size and hit < 20.0 - 0.3 * size, "a ray stops at its side (%.1f m)" % hit)
	# Hurt: it calls, and strides off; hurt badly, it charges.
	a.hurt(10.0, a.global_position + Vector3(5, 0, 0))
	check(a.state == "flee" and a._rig.trumpet >= 0.0, "hurt: it trumpets and turns away (%s)" % a.state)
	a.hurt(a.max_hp * 0.6, a.global_position + Vector3(5, 0, 0))
	check_eq(a.state, "hunt", "hurt badly: it charges")
	a.queue_free()
	await tree.process_frame


func _lifted(rig: CosmosMammoth.Rig, up: int) -> bool:
	return (rig.feet[up] as Vector3).y > CosmosMammoth.ANKLE_Y + 0.01


func test_walk_lateral_sequence_feet_planted() -> void:
	var a := await _mammoth()
	var rig: CosmosMammoth.Rig = a._rig
	var size := float(a.kind["size"])
	var v := float(a.kind["walk"])
	for i in 600:
		rig.step(1.0 / 60.0, v, size, false, false)
	check(rig.gait.x > 0.9, "walking at its pace (%s)" % str(rig.gait))
	# Which foot lifts after which: hind, then the fore on its side.
	var order := []
	var was := {}
	var slide := 0.0
	var n := 0
	for up in [CosmosMammoth.FL_UP, CosmosMammoth.FR_UP, CosmosMammoth.HL_UP, CosmosMammoth.HR_UP]:
		was[up] = _lifted(rig, up)
	for i in 60 * 12:
		var before := {}
		for up in was:
			before[up] = rig.feet[up]
		rig.step(1.0 / 60.0, v, size, false, false)
		for up in was:
			var now := _lifted(rig, up)
			if now and not was[up]:
				order.append(up)
			if not now and not was[up]:   # (planted: moving back under it as fast as it walks on)
				slide += absf(((rig.feet[up] as Vector3).z - (before[up] as Vector3).z) * 60.0 - v / size)
				n += 1
			was[up] = now
		# The legs reach their feet (IK): the ankle where it's meant to be.
	for up in was:
		var at := rig.sk.get_bone_global_pose(up + 2).origin
		check_lt(at.distance_to(rig.feet[up]), 0.02, "leg %d reaches its foot" % up)
	var seq := []
	for i in range(order.size() - 3):
		seq.append(order.slice(i, i + 4))
	var lateral := [CosmosMammoth.HL_UP, CosmosMammoth.FL_UP, CosmosMammoth.HR_UP, CosmosMammoth.FR_UP]
	var ok := false
	for s in seq:
		for r in 4:
			var rot := lateral.slice(r) + lateral.slice(0, r)
			ok = ok or s == rot
	check(ok, "a lateral sequence: hind, fore on that side, the other hind, its fore (%s)" % str(order.slice(0, 8)))
	check(n > 100 and slide / n < 0.08, "planted feet don't slide (%.3f units/s, %d)" % [slide / maxf(n, 1), n])
	a.queue_free()
	await tree.process_frame


func test_amble_never_off_the_ground() -> void:
	var a := await _mammoth()
	var rig: CosmosMammoth.Rig = a._rig
	var size := float(a.kind["size"])
	for i in 400:
		rig.step(1.0 / 60.0, float(a.kind["run"]), size, false, true)
	check(rig.gait.y > 0.8, "ambling when it hurries (%s)" % str(rig.gait))
	var least := 4
	for i in 300:
		rig.step(1.0 / 60.0, float(a.kind["run"]), size, false, true)
		var down := 0
		for up in rig.feet:
			down += 0 if _lifted(rig, up) else 1
		least = mini(least, down)
	check(least >= 2, "never all off the ground - at least %d feet down" % least)
	a.queue_free()
	await tree.process_frame


func test_idle_grazing_and_acts() -> void:
	var a := await _mammoth()
	var rig: CosmosMammoth.Rig = a._rig
	var size := float(a.kind["size"])
	var seen := {}
	var low := 9.0
	var high := -9.0
	for i in 60 * 150:
		rig.step(1.0 / 60.0, 0.0, size, true, false)
		seen[rig.act] = true
		if i % 6 == 0:
			var tip := rig.sk.get_bone_global_pose(CosmosMammoth.TRUNK5).origin
			low = minf(low, tip.y)
			high = maxf(high, tip.y)
	for act in ["graze", "look", "fan", "rest", "dust"]:
		check(seen.has(act), "standing about it does %s" % act)
	check(low < 0.3, "grazing: the trunk down to the ground (%.2f)" % low)
	check(high > 1.0, "the trunk curled up - to its mouth, over its back (%.2f)" % high)
	a.queue_free()
	await tree.process_frame
