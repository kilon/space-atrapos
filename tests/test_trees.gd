extends TestCase
## The planets' plants (CosmosFlora): on the green worlds Greece's own - olive,
## cypress, pines, plane, oak, carob, fig, fir, palm, the maquis and phrygana,
## grasses and meadow flowers - several distinct tree designs a world, each with
## real branches and (up close) single leaves; a wide range of sizes; plants in
## groves, woods and meadows, each species near its own; deterministic and the
## same on a patch and on its finer patches.


func _shape(type: String) -> Array:
	for r in Cosmos.planet_records(Galaxy.HOME):
		if str(r.get("type", "")) == type:
			return [PlanetShape.of(r, false), int(r.get("seed", 1))]
	var r: Dictionary = Cosmos.planet_records(Galaxy.HOME)[0].duplicate()
	r["type"] = type
	return [PlanetShape.of(r, false), int(r.get("seed", 1))]


func _ocean() -> Array:
	var s := _shape("ocean")
	return [s[0], CosmosFlora.design(s[0], s[1], "ocean")]


static func _tris(arr: Array) -> int:
	return (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func test_greek_tree_designs() -> void:
	var o := _ocean()
	var fl: Array = o[1]
	var trees := {}
	for sp: Dictionary in fl:
		if sp["kind"] in ["tree", "spire"]:
			trees[sp["design"]] = sp
	check(trees.size() >= 6, "several tree designs on a green world (%s)" % ", ".join(trees.keys()))
	check(trees.has("olive") and trees.has("cypress"), "olive and cypress on every green world")
	var kinds := {}
	for sp: Dictionary in fl:
		kinds[sp["kind"]] = kinds.get(sp["kind"], 0) + 1
	check(int(kinds.get("grass", 0)) >= 3, "several kinds of grass (%d)" % int(kinds.get("grass", 0)))
	check(int(kinds.get("bush", 0)) >= 3, "maquis and phrygana shrubs (%d)" % int(kinds.get("bush", 0)))
	check(int(kinds.get("flower", 0)) >= 3, "meadow flowers (%d)" % int(kinds.get("flower", 0)))
	# Each tree its own design: different heights, widths, mesh sizes.
	var shapes := {}
	for d in trees:
		var sp: Dictionary = trees[d]
		var vs: PackedVector3Array = sp["arrays"][Mesh.ARRAY_VERTEX]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in vs:
			lo = lo.min(v)
			hi = hi.max(v)
		var sz := hi - lo
		shapes[Vector2i(roundi(sz.y), roundi(maxf(sz.x, sz.z)))] = d
		if d != "snag" and d != "palm":
			check(sp.has("near"), "%s: a near mesh (its branches and leaves)" % d)
			if sp.has("near"):
				check(_tris(sp["near"]) > _tris(sp["far"]) * 2, "%s: the near mesh finer than the far one (%d / %d)" % [d, _tris(sp["near"]), _tris(sp["far"])])
		check(_tris(sp["far"]) <= _tris(sp["arrays"]), "%s: the far mesh no finer than the middle one" % d)
		check(_tris(sp["arrays"]) < 6000, "%s: its crown mesh small enough to scatter (%d triangles)" % [d, _tris(sp["arrays"])])
		var cy: bool = d == "cypress"
		if cy:
			check(sz.y > maxf(sz.x, sz.z) * 4.0, "the cypress a tall narrow column (%s)" % str(sz))
	check(shapes.size() >= 5, "the designs differ in height and spread (%d distinct)" % shapes.size())
	# Its leaves: cards the shader cuts (UV2.x 3..6), and the trees drawn with the leaf shader.
	var cards := 0
	for u: Vector2 in (trees["olive"]["near"][Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		if u.x > 2.5:
			cards += 1
	check(cards > 200, "the olive's leaves up close (%d card corners)" % cards)
	check(bool(trees["olive"].get("cards", false)), "trees drawn with the leaf shader")


func test_meshes_well_formed() -> void:
	var fl: Array = _ocean()[1]
	for sp: Dictionary in fl:
		for key in ["arrays", "far", "near"]:
			if not sp.has(key):
				continue
			var a: Array = sp[key]
			var n := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var bad := 0
			for i in ix:
				if i < 0 or i >= n:
					bad += 1
			check(ix.size() % 3 == 0 and bad == 0, "%s %s: indexed triangles in range" % [sp["design"], key])
			check_eq((a[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size(), n, "%s %s: UV2 on every vertex" % [sp["design"], key])
			check_eq((a[Mesh.ARRAY_COLOR] as PackedColorArray).size(), n, "%s %s: a colour on every vertex" % [sp["design"], key])


func test_alien_worlds_keep_their_flora() -> void:
	for type in ["volcanic", "ice", "rocky", "moon"]:
		var s := _shape(type)
		var fl := CosmosFlora.design(s[0], s[1], type)
		var designs := {}
		for sp: Dictionary in fl:
			designs[sp["design"]] = true
		check(not designs.has("olive") and not designs.has("cypress"), "%s: no Greek trees (%s)" % [type, ", ".join(designs.keys())])
		check(designs.has("crystaltree") or designs.has("glowtree") or designs.has("fungustree"), "%s: an alien tree (%s)" % [type, ", ".join(designs.keys())])
	var again := CosmosFlora.design(_shape("ice")[0], 303, "ice")
	check_eq(again.size(), CosmosFlora.design(_shape("ice")[0], 303, "ice").size(), "the same species every time")


func test_sizes_from_saplings_to_giants() -> void:
	var fl: Array = _ocean()[1]
	var sp: Dictionary = fl[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var xs: Array = []
	for i in 4000:
		xs.append(CosmosFlora.size_of(sp, rng))
	xs.sort()
	var s: Vector2 = sp["size"]
	var lo: float = xs[0]
	var hi: float = xs[xs.size() - 1]
	check(hi / lo > 3.0, "saplings to old giants (%.2f .. %.2f)" % [lo, hi])
	check(lo < s.x * 0.65, "some saplings (%.2f)" % lo)
	check(hi > s.y * 1.05, "some giants (%.2f)" % hi)
	var mid := 0
	for x: float in xs:
		if x > lerpf(s.x, s.y, 0.25) and x < lerpf(s.x, s.y, 0.75):
			mid += 1
	check(mid > xs.size() / 2, "most middling (%d of %d)" % [mid, xs.size()])


func test_groves_meadows_and_territories() -> void:
	var o := _ocean()
	var shape: PlanetShape = o[0]
	var fl: Array = o[1]
	var tree: Dictionary = {}
	var grass: Dictionary = {}
	for sp: Dictionary in fl:
		if sp["design"] == "aleppo_pine" or sp["design"] == "oak" or (tree.is_empty() and sp["design"] == "olive"):
			tree = sp
		if sp["design"] == "turf":
			grass = sp
	# Along a line across the land: the trees thick in places and nearly absent in others.
	var d0 := Vector3(0.3, 0.8, 0.5).normalized()
	var ax := d0.cross(Vector3.RIGHT).normalized()
	var tc: Array = []
	var gc: Array = []
	for i in 400:
		var d := d0.rotated(ax, i * 8.0 / shape.radius)   # (every 8 m)
		tc.append(CosmosFlora.cluster(tree, d, shape.radius))
		gc.append(CosmosFlora.cluster(grass, d, shape.radius))
	var thick := tc.filter(func(x): return x > 0.5).size()
	var thin := tc.filter(func(x): return x < 0.1).size()
	check(thick > 20 and thin > 20, "woods and open land along 3 km (%d thick, %d thin of 400)" % [thick, thin])
	# Grass thicker where the trees are thin (meadows and clearings).
	var g_open := 0.0
	var g_wood := 0.0
	var n_open := 0
	var n_wood := 0
	for i in tc.size():
		if tc[i] < 0.1:
			g_open += gc[i]
			n_open += 1
		elif tc[i] > 0.5:
			g_wood += gc[i]
			n_wood += 1
	if n_open > 0 and n_wood > 0:
		check(g_open / n_open > g_wood / n_wood, "more grass in the open than in the woods (%.2f / %.2f)" % [g_open / n_open, g_wood / n_wood])
	# The turf on the green lowlands, not up the hills; the golden grass the other way.
	var golden: Dictionary = fl.filter(func(sp): return sp["design"] == "golden")[0]
	var low := shape.amp * 0.3
	var high := shape.amp * 1.2
	check(CosmosFlora.site(grass, shape, low, 0.05) > CosmosFlora.site(grass, shape, high, 0.05), "turf on the green lowlands")
	check(CosmosFlora.site(golden, shape, high, 0.05) > CosmosFlora.site(golden, shape, low, 0.05), "golden dry grass on the hills")
	check(CosmosFlora.site(tree, shape, low, 0.9) == 0.0, "no trees on a sheer slope")
	var reeds: Dictionary = fl.filter(func(sp): return sp["design"] == "reeds")[0]
	check(CosmosFlora.site(reeds, shape, 2.0, 0.05) > 0.0 and CosmosFlora.site(reeds, shape, high, 0.05) == 0.0, "reeds only by the shore")


func test_scatter_deterministic_and_coarse_matches_fine() -> void:
	var o := _ocean()
	var shape: PlanetShape = o[0]
	var fl: Array = o[1]
	var ax := PlanetShape.face_axes(2)
	var span := 34.0 / shape.radius
	var total := 0
	var found := false
	for k in 40:   # (a stretch of land with plants)
		var a0 := -0.6 + k * 0.03
		var b0 := 0.1 + k * 0.017
		var fine := {}
		var solids: Array = []
		for q in 4:
			var cell := {}
			CosmosFlora.scatter(fl, shape, shape.radius, 1000 + q + k * 10, ax[0], ax[1], ax[2], a0 + span * (q % 2), b0 + span * (q / 2), span, Vector3.ZERO, false, PackedFloat64Array(), cell, solids)
			for s in cell:
				fine[s] = fine.get(s, []) + cell[s]
		var n := 0
		for s in fine:
			n += (fine[s] as Array).size()
		if n < 50:
			continue
		found = true
		total = n
		# Again: the same.
		var again := {}
		CosmosFlora.scatter(fl, shape, shape.radius, 1000 + k * 10, ax[0], ax[1], ax[2], a0, b0, span, Vector3.ZERO, false, PackedFloat64Array(), again, [])
		var first := {}
		CosmosFlora.scatter(fl, shape, shape.radius, 1000 + k * 10, ax[0], ax[1], ax[2], a0, b0, span, Vector3.ZERO, false, PackedFloat64Array(), first, [])
		check_eq(str(again), str(first), "the same plants every time")
		# Coarse: only the solid ones, each where its fine cell has it.
		var coarse := {}
		CosmosFlora.scatter(fl, shape, shape.radius, 1000 + k * 10, ax[0], ax[1], ax[2], a0, b0, span, Vector3.ZERO, true, PackedFloat64Array(), coarse, [])
		for s in coarse:
			check(float(fl[s]["solid"]) > 0.0, "coarse: only the big plants (%s)" % fl[s]["design"])
			for t: Transform3D in coarse[s]:
				check((first[s] as Array).any(func(f): return (f as Transform3D).origin.is_equal_approx(t.origin)), "%s: where the finer patch has it" % fl[s]["design"])
		# Each plant its own turn and lean: no two bases the same.
		var ups := {}
		for s in first:
			for t: Transform3D in first[s]:
				ups[t.basis.x.snapped(Vector3.ONE * 0.001)] = true
		check(ups.size() > 10, "plants turned each their own way")
		break
	check(found, "a stretch of land with plants (%d)" % total)
