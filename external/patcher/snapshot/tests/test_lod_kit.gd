extends TestCase
## The shared levels of detail (LodKit): every kind of 3D asset's mesh given a
## chain of simpler versions of itself - fewer triangles each level, the coarsest
## a small share of the full mesh, the same every time - swapped in off the main
## thread (the renderer then picks a level by its error on screen).


func _sphere() -> Array:
	var s := SphereMesh.new()
	s.radial_segments = 48
	s.rings = 24
	return s.get_mesh_arrays()


func _wait_chains() -> void:
	var t0 := Time.get_ticks_msec()
	while LodKit.pending() > 0 and Time.get_ticks_msec() - t0 < 20000:
		OS.delay_msec(5)
		LodKit.pump()


static func _levels(m: Mesh) -> Array:
	var out: Array = []
	for s in m.get_surface_count():
		var d: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), s)
		out.append((d.get("lods", []) as Array).size())
	return out


func test_chain_falls_and_is_deterministic() -> void:
	var arr := _sphere()
	var full := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var a := LodKit.lods(arr)
	check(a.size() >= 3, "a chain of several levels (%d)" % a.size())
	var keys := a.keys()
	keys.sort()
	var last := full
	for k in keys:   # (the larger its error, the fewer its triangles: the renderer goes down them further out)
		var n := (a[k] as PackedInt32Array).size() / 3
		check(n < last, "fewer triangles each level (%d after %d)" % [n, last])
		last = n
	check(LodKit.coarsest(a, full) < full * 0.3, "the coarsest a small share of the full (%d of %d)" % [LodKit.coarsest(a, full), full])
	check_eq(str(LodKit.lods(arr)), str(a), "the same chain every time")


func test_later_swaps_the_chain_in() -> void:
	var arr := _sphere()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	m.surface_set_material(0, mat)
	LodKit.later(m, [arr])
	LodKit.later(m, [arr])   # (once a mesh)
	_wait_chains()
	check(int(_levels(m)[0]) >= 3, "the mesh has its levels (%s)" % str(_levels(m)))
	check(m.surface_get_material(0) == mat, "its material kept")


func test_each_asset_kind_has_a_chain() -> void:
	var kinds := {}
	kinds["fox"] = CosmosFox.mesh()
	kinds["dragonfly"] = CosmosDragonfly.mesh()
	kinds["aeromanta"] = CosmosAeromanta.mesh()
	kinds["rock"] = CosmosRocks._rock_mesh(77)[0]
	kinds["deposit"] = CosmosDeposits.meshes()[0]
	_wait_chains()
	for k in kinds:
		var lv := _levels(kinds[k])
		check(int(lv[0]) >= 2, "%s: levels of detail (%s)" % [k, str(lv)])
