extends TestCase
## Field-aligned quads for one face (scripts/editor/mesh/field_remesh.gd): watertight on the rim's samples,
## nothing turned over, nearly all quads, a good topology score (scripts/editor/mesh/topo_score.gd) - on a
## dome, a flat six-sided face with a hole, a curved band (coarse, long thin triangles), a messy face (folds,
## a flap) - and fast enough.

const FR := preload("res://scripts/editor/mesh/field_remesh.gd")
const TOPO := preload("res://tests/test_topology.gd")
const TS := "res://scripts/editor/mesh/topo_score.gd"


## A face's rim loops (the triangles' way round), each resampled about L apart - its sharp corners (a turn over
## `corner_deg`) and `keep` points kept as samples, the runs between them evenly divided. The longest loop
## first.
static func rim_loops(v: PackedVector3Array, t: PackedInt32Array, tris: Array, L: float, keep := {}, corner_deg := 50.0) -> Array:
	var dir := {}
	for ti in tris:
		for j in 3:
			dir[Vector2i(t[int(ti) * 3 + j], t[int(ti) * 3 + (j + 1) % 3])] = true
	var nxt := {}
	for k: Vector2i in dir:
		if not dir.has(Vector2i(k.y, k.x)):
			nxt[k.x] = k.y
	var out := []
	var lens := []
	while not nxt.is_empty():
		var st: int = nxt.keys()[0]
		var loop := [st]
		var cur: int = nxt[st]
		nxt.erase(st)
		while cur != st and nxt.has(cur):
			loop.append(cur)
			var nx: int = nxt[cur]
			nxt.erase(cur)
			cur = nx
		var n := loop.size()
		var corner := []
		for i in n:
			var a := v[loop[(i - 1 + n) % n]]
			var b := v[loop[i]]
			var c := v[loop[(i + 1) % n]]
			if keep.has(loop[i]) or (b - a).angle_to(c - b) > deg_to_rad(corner_deg):
				corner.append(i)
		var pts := PackedVector3Array()
		var total := 0.0
		for i in n:
			total += v[loop[i]].distance_to(v[loop[(i + 1) % n]])
		if corner.is_empty():
			var m := maxi(4, roundi(total / L))
			_resample(v, loop, 0, n, m, pts)
		else:
			for ci in corner.size():
				var a: int = corner[ci]
				var b: int = corner[(ci + 1) % corner.size()]
				var span := (b - a + n) % n
				if span == 0:
					span = n
				var ln := 0.0
				for k in span:
					ln += v[loop[(a + k) % n]].distance_to(v[loop[(a + k + 1) % n]])
				_resample(v, loop, a, span, maxi(1, roundi(ln / L)), pts)
		if pts.size() < 4:
			# (a tiny loop: four samples round it at least)
			pts = PackedVector3Array()
			_resample(v, loop, 0, n, 4, pts)
		out.append(pts)
		lens.append(total)
	# (the longest first)
	var order := range(out.size())
	order.sort_custom(func(x, y): return float(lens[x]) > float(lens[y]))
	return order.map(func(i): return out[i])


## The run of `span` sides from loop[a], cut into m pieces: its points from the start (not the end).
static func _resample(v: PackedVector3Array, loop: Array, a: int, span: int, m: int, pts: PackedVector3Array) -> void:
	var n := loop.size()
	var cum := [0.0]
	for k in span:
		cum.append(float(cum[k]) + v[loop[(a + k) % n]].distance_to(v[loop[(a + k + 1) % n]]))
	var total: float = cum[span]
	var j := 0
	for s in m:
		var d := total * s / m
		while j < span - 1 and float(cum[j + 1]) < d:
			j += 1
		var seg := float(cum[j + 1]) - float(cum[j])
		var u := clampf((d - float(cum[j])) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
		pts.append(v[loop[(a + j) % n]].lerp(v[loop[(a + j + 1) % n]], u))


## A fill as a mesh, its quads split along the diagonal that keeps both halves facing its way (as
## edge_net._quads_out does), its rim samples the solid's edges (a closed chain a loop): {v, t, fv, chains}.
static func as_mesh(res: Dictionary, loops: Array) -> Dictionary:
	var v := PackedVector3Array()
	var starts := []
	for l in loops:
		starts.append(v.size())
		v.append_array(l)
	var ns := v.size()
	v.append_array(res["pts"])
	var ix := func(x: int) -> int:
		return -1 - x if x < 0 else ns + x
	var t := PackedInt32Array()
	for f in res["faces"]:
		var c: Array = (f as Array).map(func(x): return ix.call(int(x)))
		if c.size() == 3:
			t.append_array(PackedInt32Array(c))
			continue
		var a: int = c[0]
		var b: int = c[1]
		var cc: int = c[2]
		var d: int = c[3]
		var qn := (v[cc] - v[a]).cross(v[d] - v[b])
		var f1 := func(x: int, y: int, z: int) -> float:
			return (v[y] - v[x]).cross(v[z] - v[x]).dot(qn)
		var ac_ok: bool = f1.call(a, b, cc) > 0.0 and f1.call(a, cc, d) > 0.0
		var bd_ok: bool = f1.call(a, b, d) > 0.0 and f1.call(b, cc, d) > 0.0
		var use_ac := v[a].distance_squared_to(v[cc]) >= v[b].distance_squared_to(v[d])
		if use_ac and not ac_ok and bd_ok:
			use_ac = false
		elif not use_ac and not bd_ok and ac_ok:
			use_ac = true
		if use_ac:
			t.append_array(PackedInt32Array([a, b, cc, a, cc, d]))
		else:
			t.append_array(PackedInt32Array([a, b, d, b, cc, d]))
	var fv := []
	var chains := []
	for li in loops.size():
		var n: int = (loops[li] as PackedVector3Array).size()
		chains.append({"id": li, "closed": true})
		for k in n:
			fv.append([int(starts[li]) + k, li, float(k) / n])
	return {"v": v, "t": t, "fv": fv, "chains": chains}


## The face's own triangles as a mesh, its rim loops the edges: {v, t, fv, chains}.
static func face_mesh(v: PackedVector3Array, t: PackedInt32Array, tris: Array) -> Dictionary:
	var loc := {}
	var lv := PackedVector3Array()
	var lt := PackedInt32Array()
	for ti in tris:
		for j in 3:
			var x := t[int(ti) * 3 + j]
			if not loc.has(x):
				loc[x] = lv.size()
				lv.append(v[x])
			lt.append(loc[x])
	var dir := {}
	for i in range(0, lt.size(), 3):
		for j in 3:
			dir[Vector2i(lt[i + j], lt[i + (j + 1) % 3])] = true
	var nxt := {}
	for k: Vector2i in dir:
		if not dir.has(Vector2i(k.y, k.x)):
			nxt[k.x] = k.y
	var fv := []
	var chains := []
	while not nxt.is_empty():
		var st: int = nxt.keys()[0]
		var loop := [st]
		var cur: int = nxt[st]
		nxt.erase(st)
		while cur != st and nxt.has(cur):
			loop.append(cur)
			var nx: int = nxt[cur]
			nxt.erase(cur)
			cur = nx
		var ci := chains.size()
		chains.append({"id": ci, "closed": true})
		for k in loop.size():
			fv.append([loop[k], ci, float(k) / loop.size()])
	return {"v": lv, "t": lt, "fv": fv, "chains": chains}


## Fills a face and measures it: {res, why, ms, bad (validate's answer), score (topo_score's dict), quads, tris}.
static func run(v: PackedVector3Array, t: PackedInt32Array, tris: Array, L: float, loops := []) -> Dictionary:
	if loops.is_empty():
		loops = rim_loops(v, t, tris, L)
	var t0 := Time.get_ticks_usec()
	var res: Dictionary = FR.fill_face(v, t, tris, loops, L)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var out := {"res": res, "why": FR.why, "ms": ms, "stats": FR.stats.duplicate(), "loops": loops}
	if res.is_empty():
		out["bad"] = "nothing (%s)" % FR.why
		return out
	out["bad"] = FR.validate(v, t, tris, loops, res)
	var q := 0
	for f in res["faces"]:
		if (f as Array).size() == 4:
			q += 1
	out["quads"] = q
	out["tris"] = (res["faces"] as Array).size() - q
	var mm := as_mesh(res, loops)
	out["score"] = load(TS).score(mm["v"], mm["t"], mm["fv"], mm["chains"])
	return out


static func summary(r: Dictionary) -> String:
	if not r.has("score"):
		return "failed: %s" % str(r.get("bad", ""))
	var s: Dictionary = r["score"]
	return "score %.1f, quads %d, tris %d, quad_ratio %.3f, poles %d/%d, slivers %d, angle_dev %.1f, area_cv %.2f, %.0f ms" % [s["score"], r["quads"], r["tris"], s["quad_ratio"], s["poles"], s["interior"], s["slivers"], s["angle_dev"], s["area_cv"], r["ms"]]


## A flat six-sided face (radius 1) with a round hole (radius 0.35, off centre), in rows of triangles from
## the hole out to the rim.
static func hex_with_hole(segs := 48, rows := 12) -> Dictionary:
	var v := PackedVector3Array()
	var c0 := Vector3(0.12, 0, -0.05)
	for r in rows + 1:
		var f := float(r) / rows
		for k in segs:
			var a := TAU * k / segs
			var inner := c0 + Vector3(cos(a), 0, sin(a)) * 0.35
			# (the hexagon's rim along the same ray from the centre)
			var sec := fposmod(a, TAU / 6.0) - TAU / 12.0
			var rr := cos(TAU / 12.0) / cos(sec)
			var outer := Vector3(cos(a), 0, sin(a)) * rr
			v.append(inner.lerp(outer, f))
	var t := PackedInt32Array()
	for r in rows:
		for k in segs:
			var k1 := (k + 1) % segs
			var a := r * segs + k
			var b := r * segs + k1
			var cc := (r + 1) * segs + k
			var d := (r + 1) * segs + k1
			t.append_array(PackedInt32Array([a, cc, b, b, cc, d]))
	return {"v": v, "t": t}


static func all_tris(t: PackedInt32Array) -> Array:
	return range(t.size() / 3)


func _report(name: String, r: Dictionary) -> void:
	print("  field_remesh %s: %s" % [name, summary(r)])


func _check_fill(name: String, r: Dictionary, min_score: float) -> void:
	_report(name, r)
	check(r["bad"] == "", "%s: watertight, nothing turned over (%s)" % [name, r["bad"]])
	if not r.has("score"):
		return
	var s: Dictionary = r["score"]
	check(float(s["quad_ratio"]) >= 0.9, "%s: quads at least 9 in 10 (%.3f)" % [name, s["quad_ratio"]])
	check(int(s["nonmanifold"]) == 0, "%s: manifold" % name)
	check(int(s["misoriented"]) == 0, "%s: wound one way" % name)
	check(float(s["score"]) >= min_score, "%s: score %.1f at least %.0f" % [name, s["score"], min_score])


func test_dome() -> void:
	var m := TOPO.dome(32, 10)
	_check_fill("dome", run(m["v"], m["t"], all_tris(m["t"]), 0.12), 80.0)


func test_hexagon_with_a_hole() -> void:
	var m := hex_with_hole()
	_check_fill("hexagon with a hole", run(m["v"], m["t"], all_tris(m["t"]), 0.1), 72.0)


func test_curved_band() -> void:
	# (a coarse U-section ring: long thin triangles across its width, two rims)
	var m := TOPO.u_band(24)
	_check_fill("curved band", run(m["v"], m["t"], all_tris(m["t"]), 0.06), 78.0)


func test_messy_face() -> void:
	# (a dome whose inner points are shaken till triangles fold over, with a flap - one triangle there twice,
	# both ways round - as a converted mesh can have: still filled, watertight, mostly quads)
	var m := TOPO.dome(32, 10)
	var v: PackedVector3Array = m["v"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(1, 1 + 8 * 32):
		v[i] += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * 0.06
	var t: PackedInt32Array = m["t"]
	t.append_array(PackedInt32Array([t[30], t[31], t[32], t[30], t[32], t[31]]))
	var r := run(v, t, all_tris(t), 0.12, rim_loops(v, m["t"], all_tris(m["t"]), 0.12))
	_report("messy face", r)
	check(r["bad"] == "", "watertight, nothing turned over (%s)" % r["bad"])
	if r.has("score"):
		check(float(r["score"]["quad_ratio"]) >= 0.85, "mostly quads (%.3f)" % r["score"]["quad_ratio"])


func test_rim_given_the_other_way_round() -> void:
	var m := TOPO.dome(32, 10)
	var loops := rim_loops(m["v"], m["t"], all_tris(m["t"]), 0.12)
	var back := PackedVector3Array(loops[0])
	back.reverse()
	var r := run(m["v"], m["t"], all_tris(m["t"]), 0.12, [back])
	_report("rim reversed", r)
	check(r["bad"] == "", "watertight, nothing turned over (%s)" % r["bad"])


func test_rim_samples_kept_exactly() -> void:
	var m := TOPO.dome(32, 10)
	var r := run(m["v"], m["t"], all_tris(m["t"]), 0.12)
	check(r["bad"] == "", "filled (%s)" % r["bad"])
	if r["res"].is_empty():
		return
	# (each rim sample a corner of some face, and no new point on the rim's line)
	var loops: Array = r["loops"]
	var rim: PackedVector3Array = loops[0]
	var pts: PackedVector3Array = r["res"]["pts"]
	var near := 0
	for p in pts:
		if absf(p.y) < 1e-4:
			near += 1
	check_eq(near, 0, "no inner point on the rim")
	check(rim.size() > 0, "the rim sampled")


func test_speed_on_a_4000_triangle_face() -> void:
	var m := TOPO.dome(64, 32)
	var nt: int = m["t"].size() / 3
	check(nt >= 4000, "a big face (%d triangles)" % nt)
	var r := run(m["v"], m["t"], all_tris(m["t"]), 0.1)
	_report("4000 triangles", r)
	check(r["bad"] == "", "filled (%s)" % r["bad"])
	check(float(r["ms"]) < 5000.0, "under 5 s (%.0f ms; %s)" % [r["ms"], str(r["stats"])])
