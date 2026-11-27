extends TestCase
## The topology scorer (scripts/editor/mesh/topo_score.gd): a regular grid of quads scores near 100, the same
## grid with its triangles flipped and its points jittered clearly lower, a fan of triangles low.

const TS := "res://scripts/editor/mesh/topo_score.gd"


## A flat n x n grid of quads (each two triangles split along a diagonal), its rim four edges of the solid.
## [v, t, fv, chains]
func _grid(n: int) -> Array:
	var v := PackedVector3Array()
	for z in n + 1:
		for x in n + 1:
			v.append(Vector3(x, 0, z) * 0.1)
	var t := PackedInt32Array()
	for z in n:
		for x in n:
			var a := z * (n + 1) + x
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			t.append_array(PackedInt32Array([a, c, d, a, d, b]))
	var fv := []
	for i in n + 1:
		var p := float(i) / n
		fv.append([i, 0, p])                           # (z = 0)
		fv.append([n * (n + 1) + i, 1, p])             # (z = n)
		fv.append([i * (n + 1), 2, p])                 # (x = 0)
		fv.append([i * (n + 1) + n, 3, p])             # (x = n)
	var chains := [{"id": 1, "closed": false}, {"id": 2, "closed": false}, {"id": 3, "closed": false}, {"id": 4, "closed": false}]
	return [v, t, fv, chains]


## Flips `count` random inner sides (where the two triangles still face up after) and moves the inner points
## up to `jit` of a cell's width.
func _spoil(g: Array, count: int, jit: float, seed_n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var v: PackedVector3Array = (g[0] as PackedVector3Array).duplicate()
	var t: PackedInt32Array = (g[1] as PackedInt32Array).duplicate()
	var on := {}
	for e in g[2]:
		on[int(e[0])] = true
	for i in v.size():
		if not on.has(i):
			v[i] += Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * jit * 0.1
	var nt := t.size() / 3
	var flips := 0
	for attempt in count * 20:
		if flips >= count:
			break
		var i := rng.randi_range(0, nt - 1)
		var j := rng.randi_range(0, 2)
		var a := t[i * 3 + j]
		var b := t[i * 3 + (j + 1) % 3]
		var c := t[i * 3 + (j + 2) % 3]
		for o in nt:
			if o == i:
				continue
			for k in 3:
				if t[o * 3 + k] == b and t[o * 3 + (k + 1) % 3] == a:
					var d := t[o * 3 + (k + 2) % 3]
					# (a b c + b a d -> c a d + d b c)
					var n1 := (v[a] - v[c]).cross(v[d] - v[c])
					var n2 := (v[b] - v[d]).cross(v[c] - v[d])
					var up := (v[b] - v[a]).cross(v[c] - v[a])
					if n1.dot(up) > 0 and n2.dot(up) > 0:
						t[i * 3] = c
						t[i * 3 + 1] = a
						t[i * 3 + 2] = d
						t[o * 3] = d
						t[o * 3 + 1] = b
						t[o * 3 + 2] = c
						flips += 1
	return [v, t, g[2], g[3]]


func test_perfect_grid_near_100() -> void:
	var S: GDScript = load(TS)
	var g := _grid(10)
	var r: Dictionary = S.score(g[0], g[1], g[2], g[3])
	check_eq(r["quads"], 100, "100 quads")
	check(is_equal_approx(r["quad_ratio"], 1.0), "all quads (%s)" % r["quad_ratio"])
	check_eq(r["poles"], 0, "no poles")
	check_eq(r["interior"], 81, "81 inner points")
	check(r["angle_dev"] < 0.01 and r["slivers"] == 0, "square corners, no slivers")
	check_eq(r["shade_bad"], 0, "flat: no creases")
	check_eq(r["open_sides"], 40, "the rim open")
	check_eq(r["nonmanifold"], 0, "manifold")
	check(r["score"] > 99.0, "scores near 100 (%.1f)" % r["score"])


func test_spoiled_grid_lower() -> void:
	var S: GDScript = load(TS)
	var g := _grid(10)
	var best: float = S.score(g[0], g[1], g[2], g[3])["score"]
	var bad := _spoil(g, 40, 0.35, 7)
	var r: Dictionary = S.score(bad[0], bad[1], bad[2], bad[3])
	check(r["quad_ratio"] < 0.9, "flips leave triangles (%.2f)" % r["quad_ratio"])
	check(r["poles"] > 0, "and poles (%d)" % r["poles"])
	check(r["score"] < best - 15.0, "scores clearly lower: %.1f vs %.1f" % [r["score"], best])
	var jit := _spoil(g, 0, 0.35, 3)
	var rj: Dictionary = S.score(jit[0], jit[1], jit[2], jit[3])
	check(rj["angle_dev"] > 5.0 and rj["area_cv"] > 0.1, "jitter alone: crooked, uneven quads (%.1f deg, cv %.2f)" % [rj["angle_dev"], rj["area_cv"]])
	check(rj["score"] < best - 5.0, "jitter alone scores lower: %.1f" % rj["score"])


func test_fan_low() -> void:
	var S: GDScript = load(TS)
	var v := PackedVector3Array([Vector3.ZERO])
	var t := PackedInt32Array()
	var fv := []
	var n := 24
	for i in n:
		var a := TAU * i / n
		v.append(Vector3(cos(a), 0, sin(a)))
		fv.append([i + 1, 0, float(i) / n])
	for i in n:
		t.append_array(PackedInt32Array([0, 1 + (i + 1) % n, 1 + i]))
	var r: Dictionary = S.score(v, t, fv, [{"id": 1, "closed": true}])
	check_eq(r["poles"], 1, "the hub a pole")
	check(r["score"] < 40.0, "a fan scores low (%.1f)" % r["score"])


func test_fast() -> void:
	var S: GDScript = load(TS)
	var g := _grid(70)   # (9800 triangles)
	var t0 := Time.get_ticks_usec()
	var r: Dictionary = S.score(g[0], g[1], g[2], g[3])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check_eq(r["triangles"], 9800, "9800 triangles")
	check_lt(ms, 1000.0, "scored in under a second (ms)")
