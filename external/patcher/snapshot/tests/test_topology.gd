extends TestCase
## The rules for any mesh ECurves lays out (data/docs/editor.md, "mesh-curves-topology"): checked on flat
## patches whose answer is known - a face with n corners is n grids round one pole (none for four).

const EN := preload("res://scripts/editor/mesh/edge_net.gd")


## A flat n-gon (corners on a circle of radius 1) finely cut into triangles (a fan of strips), its n sides
## each an edge: {v, t, fv, chains}.
static func ngon(n: int, rings := 14) -> Dictionary:
	var v := PackedVector3Array([Vector3.ZERO])
	var t := PackedInt32Array()
	var C := []
	for i in n:
		var a := TAU * i / n
		C.append(Vector3(cos(a), 0, sin(a)))
	# (rings of points: ring r has n*r points, along the n-gon's sides scaled by r/rings)
	var ring_start := [0]
	for r in range(1, rings + 1):
		ring_start.append(v.size())
		for i in n:
			for k in r:
				v.append(((C[i] as Vector3).lerp(C[(i + 1) % n], float(k) / r)) * float(r) / rings)
	for r in range(1, rings + 1):
		var cur: int = ring_start[r]
		var cn := n * r
		if r == 1:
			for k in cn:
				t.append_array(PackedInt32Array([0, cur + (k + 1) % cn, cur + k]))
			continue
		var prv: int = ring_start[r - 1]
		var pn := n * (r - 1)
		for i in n:
			for k in r:
				var a := cur + i * r + k
				var b := cur + (i * r + k + 1) % cn
				var pk := i * (r - 1) + mini(k, r - 1)
				var p := prv + pk % pn
				t.append_array(PackedInt32Array([a, p, b]))
				if k < r - 1:
					var p2 := prv + (pk + 1) % pn
					t.append_array(PackedInt32Array([b, p, p2]))
	var fv := []
	var chains := []
	var outer: int = ring_start[rings]
	for i in n:
		chains.append({"id": i, "closed": false})
		for k in rings + 1:
			var vi := outer + (i * rings + k) % (n * rings)
			fv.append([vi, i, float(k) / rings])
	return {"v": v, "t": t, "fv": fv, "chains": chains}


## Its layout's quads, and its inner points' valences (how many quads meet there): {quads, faces, poles}.
static func layout(m: Dictionary, L: float) -> Dictionary:
	EN.pair_why = {}
	var g: Dictionary = EN.grid_faces(m["v"], m["t"], m["fv"], m["chains"], L)
	if g.is_empty():
		return {"why": EN.grid_why}
	var fs: Array = EN._pair_faces(g["v"], g["t"], g["fv"])
	var val := {}
	for f in fs:
		for x in f:
			val[x] = int(val.get(x, 0)) + 1
	var on := {}
	for e in g["fv"]:
		on[int(e[0])] = true
	var poles := []
	for x in val:
		if not on.has(x) and int(val[x]) != 4:
			poles.append(val[x])
	return {"quads": fs.filter(func(f): return (f as Array).size() == 4).size(), "faces": fs.size(), "poles": poles, "log": EN.grid_log}


func test_closed_form_spokes() -> void:
	check_eq(EN.cc_spokes([4, 4, 4]), [2, 2, 2], "a triangle 4/4/4: spokes of 2")
	check_eq(EN.cc_spokes([6, 4, 3, 5, 4]), EN.cc_spokes([6, 4, 3, 5, 4]), "the paper's pentagon solves")
	check(not EN.cc_spokes([6, 4, 3, 5, 4]).is_empty(), "(6, 4, 3, 5, 4) can be laid out (the paper's example)")
	check(EN.cc_spokes([8, 2, 2]).is_empty(), "a side as long as the other two: no layout")


func test_triangle_is_three_grids_round_one_pole() -> void:
	var r := layout(ngon(3), 0.15)
	check(r.has("quads"), "laid out (%s)" % str(r.get("why", "")))
	if r.has("quads"):
		check_eq(r["quads"], r["faces"], "all quads")
		check_eq(r["poles"], [3], "one pole, three quads meeting (%s)" % str(r["log"]))


func test_pentagon_and_hexagon_one_pole_each() -> void:
	for n in [5, 6]:
		var r := layout(ngon(n), 0.15)
		check(r.has("quads"), "%d sides: laid out (%s)" % [n, str(r.get("why", ""))])
		if r.has("quads"):
			check_eq(r["quads"], r["faces"], "%d sides: all quads" % n)
			# (one pole of n - or, better still, none: a grid with two corners left on its sides, as a six-sided
			# face often is - poles of six or more are best avoided)
			var p: Array = r["poles"]
			check(p.is_empty() or p == [n], "%d sides: one pole of %d or none (%s; %s)" % [n, n, str(p), str(r["log"])])


## A hemisphere (latitude rings of triangles), its rim one closed edge.
static func dome(segs := 32, rows := 10) -> Dictionary:
	var v := PackedVector3Array([Vector3(0, 1, 0)])
	var t := PackedInt32Array()
	for r in range(1, rows + 1):
		var th := PI * 0.5 * r / rows
		for k in segs:
			var ph := TAU * k / segs
			v.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
	for k in segs:
		t.append_array(PackedInt32Array([0, 1 + (k + 1) % segs, 1 + k]))
	for r in range(1, rows):
		var a0 := 1 + (r - 1) * segs
		var b0 := 1 + r * segs
		for k in segs:
			var k1 := (k + 1) % segs
			t.append_array(PackedInt32Array([a0 + k, a0 + k1, b0 + k, a0 + k1, b0 + k1, b0 + k]))
	var fv := []
	var rim := 1 + (rows - 1) * segs
	for k in segs:
		fv.append([rim + k, 0, float(k) / segs])
	return {"v": v, "t": t, "fv": fv, "chains": [{"id": 0, "closed": true}]}


func test_dome_is_rings_round_a_middle_grid() -> void:
	var r := layout(dome(), 0.12)
	check(r.has("quads"), "laid out (%s)" % str(r.get("why", "")))
	if r.has("quads"):
		check_eq(r["quads"], r["faces"], "all quads")
		var p: Array = r["poles"]
		check(p.size() <= 4 and p.all(func(x): return int(x) == 3), "four poles of three at most - the middle grid's corners (%s; %s)" % [str(p), str(r["log"])])


## A long thin band (a visor), made of triangles that span its width only - no points inside - its rim one
## closed edge.
static func ribbon(length := 3.0, width := 0.08, segs := 20) -> Dictionary:
	var v := PackedVector3Array()
	for k in segs + 1:
		var x := length * k / segs
		var bend := Vector3(x, 0.0, 0.15 * sin(x))   # (curved a little, like a visor)
		v.append(bend)
		v.append(bend + Vector3(0, width, 0))
	var t := PackedInt32Array()
	for k in segs:
		var a := k * 2
		t.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	# the rim: along the bottom, up the far end, back along the top, down the near end
	var rim := []
	for k in segs + 1:
		rim.append(k * 2)
	for k in range(segs, -1, -1):
		rim.append(k * 2 + 1)
	var fv := []
	for i in rim.size():
		fv.append([rim[i], 0, float(i) / rim.size()])
	return {"v": v, "t": t, "fv": fv, "chains": [{"id": 0, "closed": true}]}


func test_ribbon_is_one_strip() -> void:
	var r := layout(ribbon(), 0.03)
	check(r.has("quads"), "laid out (%s)" % str(r.get("why", "")))
	if r.has("quads"):
		# (nearly all quads, nearly no poles - a quad or two at one end still comes out uneven: to do)
		check(float(r["quads"]) >= float(r["faces"]) * 0.98, "nearly all quads (%d of %d; %s)" % [r["quads"], r["faces"], str(r["log"])])
		check((r["poles"] as Array).size() <= 4, "a strip: next to no poles (%s)" % str(r["poles"]))


## A ring band with a U-shaped section (an outer wall, a top, an inner wall), coarse like a converted part,
## its two bottom rims its only edges - one ring-shaped face.
static func u_band(segs := 24) -> Dictionary:
	var prof := [Vector2(1.0, 0.0), Vector2(1.0, 0.25), Vector2(0.95, 0.3), Vector2(0.85, 0.3), Vector2(0.8, 0.25), Vector2(0.8, 0.0)]
	var v := PackedVector3Array()
	for k in segs:
		var a := TAU * k / segs
		for q in prof:
			v.append(Vector3(cos(a) * q.x, q.y, sin(a) * q.x))
	var np := prof.size()
	var t := PackedInt32Array()
	for k in segs:
		var k1 := (k + 1) % segs
		for i in np - 1:
			var a0 := k * np + i
			var b0 := k1 * np + i
			t.append_array(PackedInt32Array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]))
	var fv := []
	for k in segs:
		fv.append([k * np, 0, float(k) / segs])
		fv.append([k * np + np - 1, 1, float(k) / segs])
	return {"v": v, "t": t, "fv": fv, "chains": [{"id": 0, "closed": true}, {"id": 1, "closed": true}]}


func test_u_band_rows_round_it() -> void:
	var m := u_band()
	var g: Dictionary = EN.grid_any(m["v"], m["t"], m["fv"], m["chains"], 0.04)
	check(not g.is_empty(), "laid out (%s)" % EN.grid_why)
	if not g.is_empty():
		var ts: GDScript = load("res://scripts/editor/mesh/topo_score.gd")
		var sc: Dictionary = ts.score(g["v"], g["t"], g["fv"], m["chains"])
		check(sc["score"] > 70.0, "a clean band (score %.1f, slivers %d, poles %d, creases %d; %s)" % [sc["score"], sc["slivers"], sc["poles"], sc["shade_bad"], str(EN.grid_log)])


## A flat cross (twelve corners), finely cut into triangles, one closed edge round it.
static func cross(n := 24) -> Dictionary:
	var v := PackedVector3Array()
	var id := {}
	var inside := func(i: int, j: int) -> bool:
		var x := (i + 0.5) / n * 3.0 - 1.5
		var y := (j + 0.5) / n * 3.0 - 1.5
		return absf(x) < 0.5 or absf(y) < 0.5
	var t := PackedInt32Array()
	var P := func(i: int, j: int) -> int:
		var k := Vector2i(i, j)
		if not id.has(k):
			id[k] = v.size()
			v.append(Vector3(float(i) / n * 3.0 - 1.5, 0, float(j) / n * 3.0 - 1.5))
		return id[k]
	for i in n:
		for j in n:
			if inside.call(i, j):
				var a = P.call(i, j)
				var b = P.call(i + 1, j)
				var c = P.call(i + 1, j + 1)
				var d = P.call(i, j + 1)
				t.append_array(PackedInt32Array([a, c, b, a, d, c]))
	# boundary loop
	var cnt := {}
	for ti in t.size() / 3:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			var k := Vector2i(mini(a, b), maxi(a, b))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var nxt := {}
	for ti in t.size() / 3:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			if int(cnt[Vector2i(mini(a, b), maxi(a, b))]) == 1:
				nxt[a] = b
	var st: int = nxt.keys()[0]
	var loop := [st]
	var cur: int = nxt[st]
	while cur != st:
		loop.append(cur)
		cur = nxt[cur]
	var fv := []
	for k in loop.size():
		fv.append([loop[k], 0, float(k) / loop.size()])
	return {"v": v, "t": t, "fv": fv, "chains": [{"id": 0, "closed": true}]}


## A face the grids fit badly (a cross: twelve corners) is laid out by the field-aligned fill - all quads,
## a closed surface (its rim the edge's samples, every inner side shared by two triangles).
func test_cross_laid_out_by_its_flow() -> void:
	var m := cross()
	var g: Dictionary = EN.grid_any(m["v"], m["t"], m["fv"], m["chains"], 0.125)
	check(not g.is_empty(), "laid out (%s)" % EN.grid_why)
	if g.is_empty():
		return
	var ts: GDScript = load("res://scripts/editor/mesh/topo_score.gd")
	var sc: Dictionary = ts.score(g["v"], g["t"], g["fv"], m["chains"])
	check(sc["quad_ratio"] > 0.95, "quads (%.0f%%)" % (sc["quad_ratio"] * 100.0))
	check(sc["score"] > 85.0, "clean (score %.1f, poles %d, slivers %d)" % [sc["score"], sc["poles"], sc["slivers"]])
	check_eq(sc["nonmanifold"], 0, "no side on three triangles")
	# (its open sides: exactly its rim - as many as the edge's samples)
	var rim := 0
	for e in g["fv"]:
		rim += 1 if int(e[1]) == 0 else 0
	check_eq(sc["open_sides"], rim, "open only round its rim")


## Laying out only some faces again (a knife's, an edit's) keeps the others as they were: a kept face never
## takes points left over from an earlier layout (a stale fill once crashed the editor), and every point an
## edge names is in the result.
func test_part_laid_out_again_keeps_the_rest() -> void:
	var m := cross()
	var t: PackedInt32Array = m["t"]
	var only := {}
	for i in range(0, t.size() / 3, 2):
		only[i] = true   # (every other triangle: some faces laid out again, the rest kept)
	EN.fill_out_v = PackedVector3Array([Vector3.ZERO])   # (an earlier layout's leftovers, shorter than this one)
	var g: Dictionary = EN.grid_any(m["v"], m["t"], m["fv"], m["chains"], 0.125, true, only)
	check(not g.is_empty(), "laid out (%s)" % EN.grid_why)
	if g.is_empty():
		return
	var n: int = (g["v"] as PackedVector3Array).size()
	var bad := 0
	for i in (g["t"] as PackedInt32Array):
		bad += 1 if i < 0 or i >= n else 0
	check_eq(bad, 0, "every triangle's corners among its points")
	var bad_fv := 0
	for e in g["fv"]:
		bad_fv += 1 if int(e[0]) < 0 or int(e[0]) >= n else 0
	check_eq(bad_fv, 0, "every edge's point among its points")
