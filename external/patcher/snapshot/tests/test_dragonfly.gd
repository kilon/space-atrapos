extends TestCase
## The dragonfly's own model (CosmosDragonfly): one shared mesh made on a worker -
## its body and four wings in two surfaces - six legs, a ten-segment abdomen; a
## dragonfly creature shows it with its own materials, beats its wings fore and
## hind out of phase, hovers and darts; the other flyers keep the generic build.


func _creature(id: String) -> CosmosCreature:
	var k := CosmosFauna.species(id, RandomNumberGenerator.new())
	var cr := CosmosCreature.new()
	cr.setup(k, null, 7)
	tree.root.add_child(cr)
	return cr


func test_mesh_anatomy_and_surfaces() -> void:
	CosmosDragonfly.start()
	var m := CosmosDragonfly.mesh()
	check(m != null, "the mesh made")
	check_eq(m.get_surface_count(), 2, "two surfaces: the body and the wings")
	check_eq(int(CosmosDragonfly.made.get("wings", 0)), 4, "four wings")
	check_eq(int(CosmosDragonfly.made.get("legs", 0)), 6, "six legs")
	check_eq(int(CosmosDragonfly.made.get("segments", 0)), 10, "a ten-segment abdomen")
	check_lt(float(CosmosDragonfly.made.get("build_ms", 0.0)), 200.0, "built quickly (on a worker)")
	# The wings: each vertex says its side and pair (fore / hind) - four of them.
	var w: Array = m.surface_get_arrays(1)
	var kinds := {}
	for u: Vector2 in (w[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		kinds[u] = true
	check_eq(kinds.size(), 4, "the wings' vertices: left / right, fore / hind")
	# The abdomen: its segments numbered along it (UV.y), 0 to 9.
	var b: Array = m.surface_get_arrays(0)
	var segs := {}
	for u: Vector2 in (b[Mesh.ARRAY_TEX_UV] as PackedVector2Array):
		if u.y >= 0.0:
			segs[int(u.y)] = true
	check_eq(segs.size(), 10, "the abdomen's segments in its UVs")
	check(m == CosmosDragonfly.mesh(), "the same mesh for every dragonfly")


func test_creature_uses_it_and_flies() -> void:
	var a := _creature("dragonfly")
	var b := _creature("dragonfly")
	for i in 60:
		if a._fly.mesh != null and b._fly.mesh != null:
			break
		a._process(0.016)
		b._process(0.016)
		await tree.process_frame
	check(a._fly != null and a._fly.mesh == CosmosDragonfly.mesh(), "the dragonfly shows its own model")
	check(a._fly.mesh == b._fly.mesh, "shared between dragonflies")
	check(a._wings.is_empty() and a._legs.is_empty(), "none of the generic flyer's parts")
	var meshes := a.find_children("*", "MeshInstance3D", true, false)
	check_eq(meshes.size(), 1, "one mesh instance (two draw calls)")
	check(a._fly.get_surface_override_material(0) != b._fly.get_surface_override_material(0), "each its own materials (the hit flash)")
	check((a._fly.get_surface_override_material(1) as ShaderMaterial).shader == CosmosDragonfly.WING_SHADER, "the wings' glassy shader")
	# The beat: the wing phase advancing, faster darting.
	a._alt = 1.2
	var p0 := a._beat
	a._darting = false
	a._fly_motion(0.01, Vector3.ZERO, Vector3.UP)
	var hover_step := wrapf(a._beat - p0, 0.0, TAU)
	p0 = a._beat
	a._darting = true
	a._fly_motion(0.01, Vector3(0, 0, -5), Vector3.UP)
	var dart_step := wrapf(a._beat - p0, 0.0, TAU)
	check(hover_step > 0.0 and dart_step > hover_step, "the wings beat, faster darting (%.3f, %.3f)" % [hover_step, dart_step])
	check(is_equal_approx(float((a._wmat as ShaderMaterial).get_shader_parameter("phase")), a._beat), "the beat reaches the wings' shader")
	# Hover and dart: still for a while, then a burst far faster than its wander pace.
	var seen := {}
	for i in 400:
		var sp := a._fly_speed(0.02, Vector3.FORWARD, float(a.kind["walk"]))
		seen[snappedf(sp, 0.01)] = true
	var fast := seen.keys().filter(func(x): return x > float(a.kind["walk"]) * 2.0)
	var slow := seen.keys().filter(func(x): return x < float(a.kind["walk"]) * 0.5)
	check(not fast.is_empty() and not slow.is_empty(), "hovers and darts")
	# Hit: the flash on its body's material.
	a.hurt(1.0, Vector3.ZERO)
	a.planet = null
	check(a._hurt > 0.0, "hit")
	a.queue_free()
	b.queue_free()
	await tree.process_frame


func test_other_flyers_unchanged() -> void:
	for id in ["moth", "firefly", "frostray", "emberqueen"]:
		var c := _creature(id)
		check(c._fly == null, "%s: not the dragonfly's model" % id)
		check_eq(c._wings.size(), 2, "%s: the generic flyer's two wings" % id)
		c.queue_free()
	await tree.process_frame
