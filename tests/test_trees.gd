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


# --- Levels of detail and reach (FloraLods) ------------------------------------------

func test_lod_chain_per_species() -> void:
	for type in ["ocean", "volcanic", "ice", "rocky"]:
		var s := _shape(type)
		var fl := CosmosFlora.design(s[0], s[1], type)
		var stands := 0
		for sp: Dictionary in fl:
			if not FloraLods.is_stand(sp):
				check(not sp.has("lods"), "%s: the grass and flowers keep their one mesh" % sp["design"])
				continue
			stands += 1
			var lods: Array = sp.get("lods", [])
			check(lods.size() >= (3 if type == "ocean" and sp["kind"] in ["tree", "spire"] else 1), "%s %s: a chain of meshes (%d)" % [type, sp["design"], lods.size()])
			# Contiguous bands from near (0) to low (3); fewer triangles each step down.
			var want := 0
			var last := 1 << 30
			var tris: Array = []
			for e: Array in lods:
				var n := _tris(e[0])
				tris.append(n)
				check_eq(int(e[1]), want, "%s %s: its levels contiguous" % [type, sp["design"]])
				check(n < last, "%s %s: fewer triangles each level down (%s)" % [type, sp["design"], str(tris)])
				last = n
				want = int(e[2]) + 1
				var a: float = (e[0][Mesh.ARRAY_COLOR] as PackedColorArray)[0].a
				var code := fmod(a * 128.0 - 0.5, 64.0)
				check(absf(code - (int(e[1]) * 8 + int(e[2]))) < 0.01, "%s %s: COLOR.a says its levels" % [type, sp["design"]])
			check_eq(want, FloraLods.IMP, "%s %s: down to the low mesh (the level before the impostor)" % [type, sp["design"]])
			check(int(tris[tris.size() - 1]) <= 140, "%s %s: the low mesh a handful of triangles (%d)" % [type, sp["design"], int(tris[tris.size() - 1])])
			check(float(sp["h"]) > 0.2 and float(sp["reach"]) >= FloraLods.BUSH_REACH, "%s %s: its size and reach" % [type, sp["design"]])
			if sp["kind"] in ["tree", "spire"]:
				check_eq(float(sp["reach"]), FloraLods.TREE_REACH, "%s %s: the trees seen to the horizon" % [type, sp["design"]])
		check(stands >= 3, "%s: trees and shrubs with levels (%d)" % [type, stands])
	check_eq(_tris(FloraLods.impostor_arrays()), 8, "the impostor: four cards, eight triangles")


func test_impostors_baked() -> void:
	var fl: Array = _ocean()[1]
	var atlas := FloraLods.bake(fl)
	var img: Image = atlas["image"]
	var grid: Vector2 = atlas["grid"]
	check(img != null and img.has_mipmaps(), "an atlas, mipmapped (far off: its smaller levels)")
	check_eq(img.get_width(), int(grid.x) * FloraLods.CELL, "its grid of cells")
	var seen := {}
	for sp: Dictionary in fl:
		if not FloraLods.is_stand(sp):
			continue
		check(sp.has("imp"), "%s: an impostor" % sp["design"])
		var iv: Vector4 = sp["imp"]
		seen[int(iv.x)] = true
		check(iv.y > 0.3 and iv.z > 0.3 and iv.w > 0.1 and iv.w < 0.95, "%s: its card sizes (%s)" % [sp["design"], str(iv)])
		for view in 2:   # (side and top: drawn - a good share of the cell covered - and in the plant's colours)
			var cell := int(iv.x) * 2 + view
			var ox := (cell % int(grid.x)) * FloraLods.CELL
			var oy := (cell / int(grid.x)) * FloraLods.CELL
			var cover := 0
			var col := Color(0, 0, 0, 0)
			for y in FloraLods.CELL:
				for x in FloraLods.CELL:
					var c := img.get_pixel(ox + x, oy + y)
					if c.a > 0.5:
						cover += 1
						col += c
			var share := cover / float(FloraLods.CELL * FloraLods.CELL)
			check(share > 0.05, "%s view %d: its shape drawn (%.0f%% covered)" % [sp["design"], view, share * 100.0])
			if cover > 0 and sp["kind"] == "tree" and sp["design"] != "snag":
				col /= cover
				check(col.g >= col.b, "%s view %d: leafy colours (%s)" % [sp["design"], view, str(col)])
	check(seen.size() >= 6, "each stand its own cell (%d)" % seen.size())


func test_lod_selection_by_screen_size() -> void:
	# The level a plant draws at: by its distance over its size - coarser further out, finer for bigger plants.
	check_eq(FloraLods.level_at(0.0), 0, "up close: every branch and leaf")
	check_eq(FloraLods.level_at(1000.0), FloraLods.IMP, "far off: the impostor")
	var last := -1
	for i in 200:
		var lv := FloraLods.level_at(i * 0.5)
		check(lv >= last, "never finer further out (%.1f: %d)" % [i * 0.5, lv])
		last = lv
	for k in range(1, FloraLods.LOD_K.size()):   # (continuous at each band's edge: no jump in the crossfade)
		var x: float = FloraLods.LOD_K[k]
		check(absf(FloraLods.lod_t(x - 0.001) - FloraLods.lod_t(x)) < 0.01, "the level continuous at %.0f" % x)
		check(is_equal_approx(FloraLods.lod_t(x), float(k)), "band %d starts at %.0f sizes" % [k, x])
	var small := 6.0
	var big := 15.0
	check(FloraLods.level_at(30.0 / big) < FloraLods.level_at(30.0 / small), "a big tree keeps its detail further than a small one")
	# The share of plants drawn falls with distance: all near, fewer far.
	check_eq(FloraLods.share(10.0), 1.0, "every plant near")
	check(FloraLods.share(1000.0) < FloraLods.share(300.0) and FloraLods.share(3000.0) > 0.0, "fewer further, still some at the horizon")


func test_stands_handed_down_the_patches() -> void:
	var o := _ocean()
	var shape: PlanetShape = o[0]
	var fl: Array = o[1]
	var ax := PlanetShape.face_axes(2)
	var R := shape.radius
	# A coarse patch (level 4) over land, its four children, their own and inherited plants.
	var span := 2.0 / 16.0
	var a0 := -1.0
	var b0 := -1.0
	var size := R * span * 0.9
	var hi := FloraLods.LEVEL_REACH * size
	var mine := {}
	for t in 64:   # (a patch over land with trees)
		a0 = -1.0 + (t % 8) * span * 2.0
		b0 = -1.0 + (t / 8) * span * 2.0
		mine = FloraLods.own(fl, shape, R, 11, ax[0], ax[1], ax[2], a0, b0, span, hi * 0.5, hi)
		var cnt := 0
		for k in mine:
			cnt += (mine[k] as PackedFloat32Array).size() / FloraLods.REC
		if cnt > 40:
			break
	var again := FloraLods.own(fl, shape, R, 11, ax[0], ax[1], ax[2], a0, b0, span, hi * 0.5, hi)
	check_eq(str(mine), str(again), "the same plants every time")
	var n := 0
	for k in mine:
		var rec: PackedFloat32Array = mine[k]
		check(FloraLods.is_stand(fl[k]), "%s: only trees and shrubs carried far" % fl[k]["design"])
		for i in range(0, rec.size(), FloraLods.REC):
			n += 1
			var reach := rec[i + 14]
			check(reach >= hi * 0.5 - 0.01 and reach <= hi + 0.01 or reach <= 70.0, "reach within the patch's band (%.0f)" % reach)
	check(n > 20, "a coarse patch carries plants far out (%d)" % n)
	var all := FloraLods.inherit({}, a0, b0, span, mine)
	var handed := 0
	for q in 4:
		var h := span * 0.5
		var ka := a0 + h * (q % 2)
		var kb := b0 + h * (q / 2)
		var kid_own := FloraLods.own(fl, shape, R, 20 + q, ax[0], ax[1], ax[2], ka, kb, h, hi * 0.25, hi * 0.5)
		var kid := FloraLods.inherit(all, ka, kb, h, kid_own)
		for k in all:   # (every parent plant on this quarter is the child's too)
			var src: PackedFloat32Array = all[k]
			var got: PackedFloat32Array = kid.get(k, PackedFloat32Array())
			for i in range(0, src.size(), FloraLods.REC):
				if src[i] >= ka and src[i] < ka + h and src[i + 1] >= kb and src[i + 1] < kb + h:
					handed += 1
					var found := false
					for j in range(0, got.size(), FloraLods.REC):
						if got[j] == src[i] and got[j + 1] == src[i + 1]:
							found = true
							break
					check(found, "the parent's plant handed down to its child")
	check_eq(handed, n, "each parent plant handed to exactly one child")
	# Built on the ground: a buffer per species, custom data (size, reach), the far ones' impostors.
	FloraLods.bake(fl)   # (their impostors: sp["imp"])
	var solids: Array = []
	var res := FloraLods.build(fl, shape, R, all, a0, b0, span, Vector3.ZERO, PackedFloat32Array(), 24, true, PackedFloat64Array(), solids)
	check(res.has("imp"), "the impostors of all the species in one buffer")
	for k in res:
		var e: Array = res[k]
		var buf: PackedFloat32Array = e[0]
		check_eq(buf.size(), int(e[1]) * 16, "16 floats a plant (transform and custom data)")
		if k is int:
			var at := Vector3(buf[3], buf[7], buf[11])
			var gh := shape.height(at.normalized())
			check(absf(at.length() - (R + gh)) < 3.0, "%s: on the ground (%.1f m off)" % [fl[k]["design"], at.length() - R - gh])
			check(buf[12] > 0.1 and buf[13] >= hi * 0.5 - 0.01 or buf[13] <= 70.0, "%s: its size and reach as custom data" % fl[k]["design"])


func test_leaf_cards_thin_out_one_by_one() -> void:
	# The near level's cards ranked at random; the thinned level holds only those
	# ranked under KEEP - what the near mesh has become at its end, card by card.
	var fl: Array = _ocean()[1]
	for sp: Dictionary in fl:
		if sp["design"] != "olive":
			continue
		var lods: Array = sp["lods"]
		var near: Array = lods[0][0]
		var thin: Array = lods[1][0]
		check_eq(int(lods[0][1]), 0, "the full near level first")
		check(_tris(thin) < _tris(near), "the thinned level lighter (%d < %d)" % [_tris(thin), _tris(near)])
		var ranks := {}
		var uv2: PackedVector2Array = near[Mesh.ARRAY_TEX_UV2]
		for u in uv2:
			if u.x > 2.5 and u.x < 6.5:
				ranks[FloraLods.rank_of(u.y)] = true
		check(ranks.size() > 20, "the cards ranked apart (%d ranks)" % ranks.size())
		var tuv: PackedVector2Array = thin[Mesh.ARRAY_TEX_UV2]
		var ix: PackedInt32Array = thin[Mesh.ARRAY_INDEX]
		var bad := 0
		for i in ix:
			if tuv[i].x > 2.5 and tuv[i].x < 6.5 and FloraLods.rank_of(tuv[i].y) >= FloraLods.KEEP:
				bad += 1
		check_eq(bad, 0, "the thinned level keeps only the cards ranked under KEEP")
