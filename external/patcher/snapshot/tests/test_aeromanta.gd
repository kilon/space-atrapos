extends TestCase
## The aeromanta's own model (CosmosAeromanta): one shared mesh made on a worker,
## one surface - the disc that is its wings, cephalic and pelvic fins, a dorsal
## fin, eyes, the whip tail; an aeromanta creature shows it, never stops (it
## cruises), alternates strokes and glides, banks into turns with its tail
## trailing; the other flyers keep the generic build.


func _creature(id: String) -> CosmosCreature:
	var k := CosmosFauna.species(id, RandomNumberGenerator.new())
	var cr := CosmosCreature.new()
	cr.setup(k, null, 3)
	tree.root.add_child(cr)
	return cr


func test_mesh_anatomy() -> void:
	CosmosAeromanta.start()
	var m := CosmosAeromanta.mesh()
	check_eq(m.get_surface_count(), 1, "one surface")
	var made := CosmosAeromanta.made
	check(int(made.get("stations", 0)) >= 30, "the disc lofted across its span (%d stations)" % int(made.get("stations", 0)))
	check_eq(int(made.get("eyes", 0)), 2, "two eyes")
	check_eq(int(made.get("fins", 0)), 5, "cephalic fins, pelvic fins, a dorsal fin")
	check(int(made.get("tail_rings", 0)) >= 20, "a long tail")
	check_lt(float(made.get("build_ms", 0.0)), 200.0, "built quickly (on a worker)")
	var arr: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var box := AABB(v[0], Vector3.ZERO)
	var tail_tip := 0.0
	for i in v.size():
		box = box.expand(v[i])
		if uv2[i].x > 0.0:
			tail_tip = maxf(tail_tip, uv2[i].x)
	check(box.size.x > 2.5 and box.size.x > box.size.y * 8.0, "a broad, flat disc (%s)" % str(box.size))
	check(box.size.z > box.size.x * 0.9, "the tail longer than the disc is wide")
	check(tail_tip > 0.95, "the tail's vertices know how far along it they are")
	check(m == CosmosAeromanta.mesh(), "the same mesh for every aeromanta")


func test_creature_uses_it_and_swims_the_air() -> void:
	var a := _creature("aeromanta")
	var b := _creature("aeromanta")
	for i in 60:
		if a._ray.mesh != null and b._ray.mesh != null:
			break
		a._process(0.016)
		b._process(0.016)
		await tree.process_frame
	check(a._ray.mesh == CosmosAeromanta.mesh() and a._ray.mesh == b._ray.mesh, "its own model, shared")
	check(a._wings.is_empty(), "none of the generic flyer's parts")
	check_eq(a.find_children("*", "MeshInstance3D", true, false).size(), 1, "one mesh instance (one draw call)")
	check(a._ray.material_override != b._ray.material_override, "each its own material (the flash, the waves)")
	# Strokes and glides: the waves deepen and ease off.
	var lo := 9.0
	var hi := 0.0
	var f := Vector3(0, 0, -3)
	for i in 1500:
		a._ray_motion(0.02, f, Vector3.UP)
		lo = minf(lo, a._wave)
		hi = maxf(hi, a._wave)
	check(hi > 0.5 and lo < 0.3, "strokes and glides (waves %.2f .. %.2f)" % [lo, hi])
	check(is_equal_approx(float(a._mat.get_shader_parameter("phase")), a._beat), "the beat reaches the shader")
	# A turn: it banks into it, its tail trailing the other way.
	a.facing = Vector3.FORWARD
	a._last_flat = Vector3(0, 0, -3)
	for i in 120:
		a._ray_motion(0.016, Vector3(0, 0, -3).rotated(Vector3.UP, (i + 1) * 0.02), Vector3.UP)
	var roll := absf(a._body.rotation.z)
	check(roll > 0.05, "banking into a turn (roll %.2f)" % roll)
	check(absf(a._bend) > 0.01 and signf(a._bend) != signf(a._body.rotation.z), "the tail trailing the turn")
	a.queue_free()
	b.queue_free()
	await tree.process_frame


func test_other_flyers_unchanged() -> void:
	for id in ["frostray", "emberqueen", "moth"]:
		var c := _creature(id)
		check(c._ray == null and c._fly == null, "%s: the generic flyer" % id)
		check_eq(c._wings.size(), 2, "%s: its two wings" % id)
		c.queue_free()
	await tree.process_frame
