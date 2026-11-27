extends RefCounted
## A baked solid's edges as curves (Curve modeling's Bake): the finished mesh's sharp edges - where two
## faces meet at an angle, or a face ends - traced into curves, one from corner to corner (or a closed
## loop), each with as few points as keep its shape (a straight edge two, an arc three). The curves
## define the solid: move a point of one and the mesh's edge goes with it - every point of the mesh on
## that edge moves as the curve did there, the faces meeting at it follow.
##   var net := EdgeNet.trace(mesh)          -> {chains: [{pts, closed}...]}
##   var c := EdgeNet.chain_curve(pts, closed) -> a curve dict
##   EdgeNet.deform(base, chains, old_curves, new_curves) -> the mesh with its edges where the curves are
##   EdgeNet.faces(mesh, chains) -> its faces: flat ones and walls between two edges made again from
##     their edge curves each time (build), any other moved with its edges

const CT := preload("res://scripts/editor/mesh/curve_tools.gd")
const SHARP_DEG := 30.0   # (faces meeting at more than this: an edge)
const Q := 1e4   # (positions welded at a tenth of a millimetre)


static func key(p: Vector3) -> Vector3i:
	return Vector3i((p * Q).round())


## The mesh's sharp edges as chains of points: {chains: [{pts: PackedVector3Array, closed: bool}]}.
static func trace(m, sharp_deg := SHARP_DEG) -> Dictionary:   # (an ArrayMesh, or MeshData - its arrays, safe on a worker; `sharp_deg`: how sharp an edge must be)
	var pos := {}   # weld key -> position
	var tris := []   # [k0, k1, k2] keys
	for si in m.get_surface_count():
		var a: Array = m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			var ks := [key(vs[ix[t]]), key(vs[ix[t + 1]]), key(vs[ix[t + 2]])]
			if ks[0] == ks[1] or ks[1] == ks[2] or ks[0] == ks[2]:
				continue
			for j in 3:
				pos[ks[j]] = vs[ix[t + j]]
			tris.append(ks)
	# each edge's faces (their normals)
	var faces := {}   # "a|b" (sorted) -> [normals]
	var ends := {}    # "a|b" -> [a, b]
	for ks in tris:
		var nrm: Vector3 = (pos[ks[2]] - pos[ks[0]]).cross(pos[ks[1]] - pos[ks[0]])
		if nrm.length() < 1e-14:
			continue
		nrm = nrm.normalized()
		for j in 3:
			var a: Vector3i = ks[j]
			var b: Vector3i = ks[(j + 1) % 3]
			var e := _ekey(a, b)
			if not faces.has(e):
				faces[e] = []
				ends[e] = [a, b]
			(faces[e] as Array).append(nrm)
	var lim := cos(deg_to_rad(sharp_deg))
	var adj := {}   # key -> [neighbour keys along sharp edges]
	for e in faces:
		var ns: Array = faces[e]
		var sharp := ns.size() != 2 or (ns[0] as Vector3).dot(ns[1]) < lim
		if not sharp:
			continue
		var a: Vector3i = ends[e][0]
		var b: Vector3i = ends[e][1]
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		adj[a].append(b)
		adj[b].append(a)
	# loose ends pruned: a sharp run that dies out on a surface (one end touching no other edge - a crease
	# of a curved wall fading out, not an edge of the solid) taken away, again till none is left
	for round_ in 50:
		var cut := false
		for v in adj.keys():
			if not adj.has(v) or (adj[v] as Array).size() != 1:
				continue
			# (from the loose end along to the next junction)
			var prev: Vector3i = v
			var cur: Vector3i = adj[v][0]
			var run := [prev]
			while adj.has(cur) and (adj[cur] as Array).size() == 2 and not cur in run:
				run.append(cur)
				var nb2: Array = adj[cur]
				var nx: Vector3i = nb2[0] if nb2[1] == prev else nb2[1]
				prev = cur
				cur = nx
			run.append(cur)
			for i in run.size() - 1:
				var a: Vector3i = run[i]
				var b: Vector3i = run[i + 1]
				if adj.has(a):
					adj[a].erase(b)
					if (adj[a] as Array).is_empty():
						adj.erase(a)
				if adj.has(b):
					adj[b].erase(a)
					if (adj[b] as Array).is_empty():
						adj.erase(b)
			cut = true
		if not cut:
			break
	# at a junction (not two sharp edges) the edges that carry on from each other - running on nearly
	# straight, within 45° - are paired: one edge of the solid goes on through it (one curve, the junction
	# a point on it), the others end there
	var through := {}   # "node|from" -> the neighbour it carries on to
	var c45 := cos(deg_to_rad(80.0))   # (carrying on - not turning back: a kink a boolean left is a corner on one edge)
	for v in adj:
		var nb: Array = adj[v]
		if nb.size() == 2:
			continue
		var pairs := []
		for i in nb.size():
			for j in range(i + 1, nb.size()):
				var di: Vector3 = _away(v, nb[i], adj, pos)
				var dj: Vector3 = _away(v, nb[j], adj, pos)
				var straight := -di.dot(dj)   # (1: straight on)
				if straight > c45:
					pairs.append([straight, nb[i], nb[j]])
		pairs.sort_custom(func(a, b): return a[0] > b[0])
		var taken := {}
		for pr in pairs:
			if taken.has(pr[1]) or taken.has(pr[2]):
				continue
			taken[pr[1]] = true
			taken[pr[2]] = true
			through[str(v) + "|" + str(pr[1])] = pr[2]
			through[str(v) + "|" + str(pr[2])] = pr[1]
	# chains: from each junction edge that doesn't carry on, along to where it ends; what's left - loops
	var used := {}
	var chains := []
	for v in adj:
		if (adj[v] as Array).size() == 2:
			continue
		for w in adj[v]:
			if used.has(_ekey(v, w)) or through.has(str(v) + "|" + str(w)):
				continue
			chains.append({"pts": _walk(v, w, adj, used, pos, through), "closed": false})
	for v in adj:
		for w in adj[v]:
			if used.has(_ekey(v, w)):
				continue
			var pts := _walk(v, w, adj, used, pos, through)
			if pts.size() > 2 and key(pts[0]) == key(pts[pts.size() - 1]):
				pts.remove_at(pts.size() - 1)
			chains.append({"pts": pts, "closed": true})
	return {"chains": tidy_chains(chains.filter(func(c): return (c["pts"] as PackedVector3Array).size() >= 2))}


## The traced edges tidied: an open one with an end touching no other edge dropped (a crease dying out),
## again till none is; then two open edges meeting end to end where nothing else meets made one (the
## point between a corner of it if it turns there) - an edge of the solid one curve.
static func tidy_chains(chains: Array) -> Array:
	var out := chains.duplicate()
	for round_ in 30:
		var count := {}   # point key -> how many chains have it
		for c in out:
			var seen := {}
			for q in (c["pts"] as PackedVector3Array):
				var k := key(q)
				if not seen.has(k):
					seen[k] = true
					count[k] = int(count.get(k, 0)) + 1
		var keep := []
		var dropped := false
		for c in out:
			var pts: PackedVector3Array = c["pts"]
			if not bool(c["closed"]) and (int(count[key(pts[0])]) == 1 or int(count[key(pts[pts.size() - 1])]) == 1):
				dropped = true
				continue
			keep.append(c)
		out = keep
		if not dropped:
			break
	for round_ in 200:
		var count := {}
		var ends := {}   # point key -> [[chain index, at its start?]...]
		for i in out.size():
			var pts: PackedVector3Array = out[i]["pts"]
			var seen := {}
			for q in pts:
				var k := key(q)
				if not seen.has(k):
					seen[k] = true
					count[k] = int(count.get(k, 0)) + 1
			if not bool(out[i]["closed"]):
				for e in [[key(pts[0]), true], [key(pts[pts.size() - 1]), false]]:
					if not ends.has(e[0]):
						ends[e[0]] = []
					ends[e[0]].append([i, e[1]])
		var joined := false
		for k in ends:
			var es: Array = ends[k]
			if es.size() != 2 or int(count[k]) != 2 or int(es[0][0]) == int(es[1][0]):
				continue
			var a: PackedVector3Array = out[int(es[0][0])]["pts"]
			var b: PackedVector3Array = out[int(es[1][0])]["pts"]
			# (a running into the point, b running out of it)
			if bool(es[0][1]):
				a = a.duplicate()
				a.reverse()
			if not bool(es[1][1]):
				b = b.duplicate()
				b.reverse()
			var m := a.duplicate()
			for j in range(1, b.size()):
				m.append(b[j])
			var closed := m.size() > 3 and key(m[0]) == key(m[m.size() - 1])
			if closed:
				m.remove_at(m.size() - 1)
			var hi := maxi(int(es[0][0]), int(es[1][0]))
			var lo := mini(int(es[0][0]), int(es[1][0]))
			out.remove_at(hi)
			out[lo] = {"pts": m, "closed": closed}
			joined = true
			break
		if not joined:
			break
	return out


## The way a run of sharp edges leaves junction `v` through `w`: towards a point a few steps along it (a
## boolean's seam can kink at its first step).
static func _away(v: Vector3i, w: Vector3i, adj: Dictionary, pos: Dictionary) -> Vector3:
	var prev := v
	var cur := w
	var total := 0.0
	for i in 4:
		total += (pos[cur] as Vector3).distance_to(pos[prev])
		var nb: Array = adj.get(cur, [])
		if nb.size() != 2 or total > 0.03:
			break
		var nx: Vector3i = nb[0] if nb[1] == prev else nb[1]
		prev = cur
		cur = nx
	return ((pos[cur] as Vector3) - (pos[v] as Vector3)).normalized()


static func _ekey(a: Vector3i, b: Vector3i) -> String:
	return str(a) + "|" + str(b) if str(a) < str(b) else str(b) + "|" + str(a)


static func _walk(v: Vector3i, w: Vector3i, adj: Dictionary, used: Dictionary, pos: Dictionary, through := {}) -> PackedVector3Array:
	var pts := PackedVector3Array([pos[v]])
	var prev := v
	var cur := w
	used[_ekey(v, w)] = true
	while true:
		pts.append(pos[cur])
		var nb: Array = adj[cur]
		if cur == v:
			break   # (round to where it began)
		var nxt: Vector3i
		if nb.size() == 2:
			nxt = nb[0] if nb[1] == prev else nb[1]
		elif through.has(str(cur) + "|" + str(prev)):
			nxt = through[str(cur) + "|" + str(prev)]   # (a junction it carries on through)
		else:
			break   # (a corner)
		if used.has(_ekey(cur, nxt)):
			break
		used[_ekey(cur, nxt)] = true
		prev = cur
		cur = nxt
	return pts


## A chain of points as a curve with as few points as keep its shape: a straight edge - its two ends;
## an arc (its points on one circle) - three; a closed circle - a circle; else a lean path (corners
## kept sharp) or, not flat, a polyline through the points that matter.
static func chain_curve(pts: PackedVector3Array, closed: bool, must := {}) -> Dictionary:
	var inner_must := false
	for i in range(1, pts.size() - 1):
		if must.has(key(pts[i])):
			inner_must = true
	if closed and not must.is_empty():
		for q in pts:
			if must.has(key(q)):
				inner_must = true
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var size := maxf((hi - lo).length(), 1e-6)
	var tol := maxf(size * 2e-3, 2e-4)
	var n := _normal(pts, closed)
	var flat := n != Vector3.ZERO
	if flat:
		for q in pts:
			if absf((q - pts[0]).dot(n)) > tol:
				flat = false
				break
	if not closed:
		var a := pts[0]
		var b := pts[pts.size() - 1]
		var straight := true
		for q in pts:
			if Geometry3D.get_closest_point_to_segment(q, a, b).distance_to(q) > tol:
				straight = false
				break
		if straight and not inner_must:
			return {"kind": "line", "ctrl": PackedVector3Array([a, b]), "closed": false, "n": n if flat else _any_n(a, b)}
		var mid := pts[pts.size() / 2]
		var ctr := CT.circumcentre(a, mid, b)
		if ctr != Vector3.INF and flat and not inner_must:
			var r := ctr.distance_to(a)
			var round_ := true
			for q in pts:
				if absf(q.distance_to(ctr) - r) > tol:
					round_ = false
					break
			if round_:
				return {"kind": "arc", "ctrl": PackedVector3Array([a, mid, b]), "closed": false, "n": n}
		# (bending gently through its points: a path, smooth there - sharp only where it turns hard - with
		# as few points as keep the smooth path on the edge)
		var fp := fit_points(pts, false, must, maxf(size * 0.004, 5e-4))
		var ln: PackedVector3Array = fp["ctrl"]
		var sharp: PackedByteArray = fp["sharp"]
		var smooth_n := 0
		for i in range(1, ln.size() - 1):
			if sharp[i] == 0:
				smooth_n += 1
		if smooth_n > 0:
			return {"kind": "path", "ctrl": ln, "closed": false, "sharp": sharp, "n": n if flat else _any_n(a, b)}
		return {"kind": "line", "ctrl": ln, "closed": false, "n": n if flat else _any_n(a, b)}
	if inner_must:
		# (a loop other edges meet: a path through those points, smooth between)
		var fp2 := fit_points(pts, true, must, maxf(size * 0.004, 5e-4))
		return {"kind": "path", "ctrl": fp2["ctrl"], "closed": true, "sharp": fp2["sharp"], "n": n if n != Vector3.ZERO else Vector3.UP}
	if flat:
		var ctr := Vector3.ZERO
		for q in pts:
			ctr += q
		ctr /= pts.size()
		var r := 0.0
		for q in pts:
			r += q.distance_to(ctr)
		r /= pts.size()
		var round_ := pts.size() >= 8
		for q in pts:
			if absf(q.distance_to(ctr) - r) > tol:
				round_ = false
				break
		if round_:
			return {"kind": "circle", "ctrl": PackedVector3Array([ctr, pts[0]]), "closed": true, "n": n}
		var u := CT._any_perp(n)
		var v := n.cross(u)
		var f := PackedVector2Array()
		for q in pts:
			f.append(Vector2((q - pts[0]).dot(u), (q - pts[0]).dot(v)))
		var fit: Dictionary = CT.fit_path(CT._tidy(f))
		if not fit.is_empty():
			var k3 := PackedVector3Array()
			for q: Vector2 in fit["pts"]:
				k3.append(pts[0] + u * q.x + v * q.y)
			var e := {"kind": "path" if fit["curved"] else "line", "ctrl": k3, "closed": true, "n": n}
			if fit["curved"]:
				e["sharp"] = fit["sharp"]
			return e
	return {"kind": "line", "ctrl": _lean(pts, tol, true), "closed": true, "n": n if n != Vector3.ZERO else Vector3.UP}


## A chain's points for a smooth path: its ends, the points other edges meet (`must`) and its corners
## (where it turns over 30° in a step) - those sharp at corners - then, one at a time, the point the path
## through them strays furthest from, till none is `tol` off. {ctrl, sharp}.
static func fit_points(pts: PackedVector3Array, closed: bool, must: Dictionary, tol: float) -> Dictionary:
	var n := pts.size()
	var keep := PackedByteArray()
	keep.resize(n)
	var corner := PackedByteArray()
	corner.resize(n)
	if not closed:
		keep[0] = 1
		keep[n - 1] = 1
	for i in n:
		if must.has(key(pts[i])):
			keep[i] = 1
		var has_prev := closed or i > 0
		var has_next := closed or i < n - 1
		if has_prev and has_next:
			var d0 := (pts[i] - pts[(i - 1 + n) % n]).normalized()
			var d1 := (pts[(i + 1) % n] - pts[i]).normalized()
			if d0.angle_to(d1) > deg_to_rad(30.0):
				keep[i] = 1
				corner[i] = 1
	if closed:
		var cnt := 0
		for i in n:
			cnt += keep[i]
		if cnt < 3:
			keep[0] = 1
			keep[n / 3] = 1
			keep[2 * n / 3] = 1
	for it in n:
		var ctrl := PackedVector3Array()
		var sharp := PackedByteArray()
		var idx := []
		for i in n:
			if keep[i]:
				ctrl.append(pts[i])
				sharp.append(corner[i])
				idx.append(i)
		if (not closed and ctrl.size() >= n) or (closed and ctrl.size() >= n):
			return {"ctrl": ctrl, "sharp": sharp}
		var c := {"kind": "path", "ctrl": ctrl, "closed": closed, "sharp": sharp}
		var smp := CT.sample(c)
		if closed:
			smp.append(smp[0])
		var worst := -1.0
		var wi := -1
		for i in n:
			if keep[i]:
				continue
			var best := INF
			for m in range(1, smp.size()):
				best = minf(best, Geometry3D.get_closest_point_to_segment(pts[i], smp[m - 1], smp[m]).distance_squared_to(pts[i]))
			if best > worst:
				worst = best
				wi = i
		if wi < 0 or sqrt(worst) <= tol:
			return {"ctrl": ctrl, "sharp": sharp}
		keep[wi] = 1
	return {"ctrl": pts.duplicate(), "sharp": corner}


static func _normal(pts: PackedVector3Array, closed: bool) -> Vector3:
	var n := Vector3.ZERO
	var m := pts.size()
	for i in m:   # (Newell's)
		var a := pts[i]
		var b := pts[(i + 1) % m]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if n.length() > 1e-9:
		return n.normalized()
	if m >= 3:   # (a straight-ish open chain: any plane through it)
		for i in range(1, m - 1):
			var c := (pts[i] - pts[0]).cross(pts[m - 1] - pts[0])
			if c.length() > 1e-9:
				return c.normalized()
	return Vector3.ZERO


static func _any_n(a: Vector3, b: Vector3) -> Vector3:
	var d := (b - a).normalized()
	if d == Vector3.ZERO:
		return Vector3.UP
	return CT._any_perp(d)


## The points that matter (Douglas-Peucker within `tol`).
static func _lean(pts: PackedVector3Array, tol: float, closed: bool, must := {}) -> PackedVector3Array:
	if pts.size() <= 2:
		return pts.duplicate()
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	if closed:   # (a loop: split at its point furthest from the first)
		var best := -1.0
		var far := 0
		for i in pts.size():
			var d := pts[i].distance_to(pts[0])
			if d > best:
				best = d
				far = i
		keep[far] = 1
	for i in pts.size():
		if must.has(key(pts[i])):
			keep[i] = 1   # (a point other edges meet: kept - the curves stay joined there)
	var fixed := []
	for i in pts.size():
		if keep[i]:
			fixed.append(i)
	for j in fixed.size() - 1:
		_dp(pts, fixed[j], fixed[j + 1], tol, keep)
	var out := PackedVector3Array()
	for i in pts.size():
		if keep[i]:
			out.append(pts[i])
	return out


static func _dp(pts: PackedVector3Array, i0: int, i1: int, tol: float, keep: PackedByteArray) -> void:
	if i1 <= i0 + 1:
		return
	var best := -1.0
	var bi := -1
	for i in range(i0 + 1, i1):
		var d := Geometry3D.get_closest_point_to_segment(pts[i], pts[i0], pts[i1]).distance_to(pts[i])
		if d > best:
			best = d
			bi = i
	if best > tol:
		keep[bi] = 1
		_dp(pts, i0, bi, tol, keep)
		_dp(pts, bi, i1, tol, keep)


## Where each point of a chain sits along its curve: a fraction (0..1) along the curve's sampled line.
static func params(pts: PackedVector3Array, c: Dictionary) -> PackedFloat32Array:
	var s := CT.sample(c)
	if c.get("closed", false):
		s.append(s[0])
	var lens := PackedFloat32Array([0.0])
	for i in range(1, s.size()):
		lens.append(lens[i - 1] + s[i - 1].distance_to(s[i]))
	var total := maxf(lens[lens.size() - 1], 1e-9)
	var out := PackedFloat32Array()
	for q in pts:
		var best := INF
		var bt := 0.0
		for i in range(1, s.size()):
			var cp := Geometry3D.get_closest_point_to_segment(q, s[i - 1], s[i])
			var d := cp.distance_to(q)
			if d < best:
				best = d
				bt = (lens[i - 1] + s[i - 1].distance_to(cp)) / total
		out.append(bt)
	return out


## How a place along curve `c0` (a fraction of its length) carries over to `c1` - the same curve
## reshaped: span by span between its points, so pulling one stretch of a long edge out doesn't slide the
## points on its other stretches along it (past its corners). [[place on c0, place on c1]...] in order,
## or [] - the same fraction (a different number of points, a circle...).
static func span_map(c0: Dictionary, c1: Dictionary) -> Array:
	var k0: PackedVector3Array = c0.get("ctrl", PackedVector3Array())
	var k1: PackedVector3Array = c1.get("ctrl", PackedVector3Array())
	if str(c0["kind"]) != str(c1["kind"]) or not str(c0["kind"]) in ["path", "spline", "line"] or k0.size() != k1.size() or k0.size() < 3 or bool(c0.get("closed", false)) != bool(c1.get("closed", false)):
		return []
	var f0 := params(k0, c0)
	var f1 := params(k1, c1)
	var pairs := []
	for i in f0.size():
		pairs.append([f0[i], f1[i]])
	pairs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if float(pairs[0][0]) > 1e-6:
		pairs.push_front([0.0, 0.0])
	if float(pairs[pairs.size() - 1][0]) < 1.0 - 1e-6:
		pairs.append([1.0, 1.0])
	for i in range(1, pairs.size()):
		if float(pairs[i][1]) < float(pairs[i - 1][1]) - 1e-6:
			return []   # (its points not in the same order along it: as a whole)
	return pairs


## A place along a curve carried over by span_map's `m`.
static func map_t(m: Array, t: float) -> float:
	if m.is_empty():
		return t
	for i in range(1, m.size()):
		var a0 := float(m[i - 1][0])
		var b0 := float(m[i][0])
		if t <= b0 or i == m.size() - 1:
			var w := clampf((t - a0) / maxf(b0 - a0, 1e-9), 0.0, 1.0)
			return lerpf(float(m[i - 1][1]), float(m[i][1]), w)
	return t


## The point a fraction `t` along curve `c`'s sampled line.
static func at(c: Dictionary, t: float) -> Vector3:
	var s := CT.sample(c)
	if c.get("closed", false):
		s.append(s[0])
	if s.size() == 1:
		return s[0]
	var lens := PackedFloat32Array([0.0])
	for i in range(1, s.size()):
		lens.append(lens[i - 1] + s[i - 1].distance_to(s[i]))
	var d := clampf(t, 0.0, 1.0) * lens[lens.size() - 1]
	for i in range(1, s.size()):
		if lens[i] >= d:
			var w := (d - lens[i - 1]) / maxf(lens[i] - lens[i - 1], 1e-9)
			return s[i - 1].lerp(s[i], w)
	return s[s.size() - 1]


## Mesh `base` with its edges where the curves are now: each chain's points moved as their curve moved
## there (from `old` - the curve when the chain was traced - to `now`); a point on two edges (a corner)
## the bigger move. Shaded again.
static func deform(base: ArrayMesh, chains: Array, old: Dictionary, now: Dictionary, shade := true) -> ArrayMesh:
	var moves := {}   # weld key -> move
	var on_edge := {}   # every edge point (moved or not): held where its edge puts it
	for ch: Dictionary in chains:
		for q in (ch["pts"] as Array):
			on_edge[key(_v3(q))] = true
	for ch: Dictionary in chains:
		var id := int(ch["id"])
		if not old.has(id) or not now.has(id):
			continue
		var c0: Dictionary = old[id]
		var c1: Dictionary = now[id]
		if JSON.stringify(CT.to_json([c0])) == JSON.stringify(CT.to_json([c1])):
			continue
		var pts: Array = ch["pts"]
		var ts: Array = ch["t"]
		var round_ := str(c0["kind"]) == "circle" and str(c1["kind"]) == "circle"
		for i in pts.size():
			var p := _v3(pts[i])
			# (a round edge: each point by its angle round the centre - resized, moved or tilted, the
			# rim keeps its points where they were round it, not turned with the handle)
			var d := _round_move(p, c0, c1) if round_ else at(c1, float(ts[i])) - at(c0, float(ts[i]))
			var k := key(p)
			if not moves.has(k) or (moves[k] as Vector3).length() < d.length():
				moves[k] = d
	if moves.is_empty():
		return base
	_spread(base, moves, on_edge)
	var out := ArrayMesh.new()
	for si in base.get_surface_count():
		var a := base.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			var k := key(vs[i])
			if moves.has(k):
				vs[i] += moves[k]
		a[Mesh.ARRAY_VERTEX] = vs
		a[Mesh.ARRAY_NORMAL] = null
		a[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(si, base.surface_get_material(si))
	return CT.auto_smooth(out) if shade else out


static func _round_move(p: Vector3, c0: Dictionary, c1: Dictionary) -> Vector3:
	var k0: PackedVector3Array = c0["ctrl"]
	var k1: PackedVector3Array = c1["ctrl"]
	var n0: Vector3 = (c0.get("n", Vector3.UP) as Vector3).normalized()
	var n1: Vector3 = (c1.get("n", Vector3.UP) as Vector3).normalized()
	var r0 := maxf(k0[0].distance_to(k0[1]), 1e-9)
	var r1 := k1[0].distance_to(k1[1])
	var rel := p - k0[0]
	var off := n0 * rel.dot(n0)
	var flat := rel - off
	var turn := Basis.IDENTITY
	var ax := n0.cross(n1)
	if ax.length() > 1e-6:
		turn = Basis(ax.normalized(), n0.angle_to(n1))
	return k1[0] + turn * (flat * (r1 / r0) + off) - p


## The points of the mesh on no edge (a boolean leaves some partway up a wall, inside a face) moved
## too - each as its neighbours on the mesh move, blended out from the edges round it - so a face
## follows its edges smoothly instead of folding round the points left behind.
static func _spread(base: ArrayMesh, moves: Dictionary, on_edge: Dictionary) -> void:
	var nb := {}   # weld key -> neighbour keys
	for si in base.get_surface_count():
		var a := base.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			for j in 3:
				var p := key(vs[ix[t + j]])
				var q := key(vs[ix[t + (j + 1) % 3]])
				if p == q:
					continue
				if not nb.has(p):
					nb[p] = {}
				if not nb.has(q):
					nb[q] = {}
				nb[p][q] = true
				nb[q][p] = true
	var free := []
	for k in nb:
		if not on_edge.has(k):
			free.append(k)
	if free.is_empty():
		return
	for k in free:
		moves[k] = Vector3.ZERO
	for it in 80:   # (each free point the average of its neighbours' moves - the edges' held)
		var most := 0.0
		for k in free:
			var sum := Vector3.ZERO
			var cnt := 0
			for o in nb[k]:
				sum += moves.get(o, Vector3.ZERO)
				cnt += 1
			var nv: Vector3 = sum / maxf(cnt, 1)
			most = maxf(most, (nv - (moves[k] as Vector3)).length())
			moves[k] = nv
		if most < 1e-6:
			break


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array:
		return Vector3(v[0], v[1], v[2])
	return Vector3.ZERO


# --- faces: made again from their edges ---------------------------------------------------------

## The mesh's faces (its triangles in groups bounded by the edges) and the edges round each:
## [{type: flat | ruled | mesh, loops: [[[chain, reversed]...]...], n0, p0, rails?, tris?}].
## flat: its triangles all facing one way - made again by filling its edge loops; ruled: a band between
## two edges (four edges round it - two straight sides - or two closed loops) - made again as a strip
## between those two; mesh: anything else - its triangles moved with the edges.
static func faces(m, chains: Array) -> Array:
	var cedge := {}   # edge -> chain index
	var ends := []   # each chain's [start key, end key]
	for ci in chains.size():
		var pts: PackedVector3Array = _pv(chains[ci]["pts"])
		var closed := bool(chains[ci].get("closed", false))
		for j in pts.size() - 1:
			cedge[_ekey(key(pts[j]), key(pts[j + 1]))] = ci
		if closed:
			cedge[_ekey(key(pts[pts.size() - 1]), key(pts[0]))] = ci
		ends.append([key(pts[0]), key(pts[pts.size() - 1])])
	var tk := []   # each triangle: [keys, normal (area), centre, global index]
	var g := 0
	for si in m.get_surface_count():
		var a: Array = m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			var p0 := vs[ix[t]]
			var p1 := vs[ix[t + 1]]
			var p2 := vs[ix[t + 2]]
			tk.append([[key(p0), key(p1), key(p2)], (p2 - p0).cross(p1 - p0), (p0 + p1 + p2) / 3.0, g])
			g += 1
	var by_edge := {}
	for ti in tk.size():
		var ks: Array = tk[ti][0]
		for j in 3:
			var e := _ekey(ks[j], ks[(j + 1) % 3])
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(ti)
	var face_of := PackedInt32Array()
	face_of.resize(tk.size())
	face_of.fill(-1)
	var out := []
	for t0 in tk.size():
		if face_of[t0] >= 0 or (tk[t0][1] as Vector3).length() < 1e-14:
			continue
		var fi := out.size()
		var todo := [t0]
		face_of[t0] = fi
		var members := []
		var on := {}   # chains round it
		while not todo.is_empty():
			var t: int = todo.pop_back()
			members.append(t)
			var ks: Array = tk[t][0]
			for j in 3:
				var e := _ekey(ks[j], ks[(j + 1) % 3])
				if cedge.has(e):
					on[cedge[e]] = true
					continue
				for o in by_edge.get(e, []):
					if face_of[o] < 0 and (tk[o][1] as Vector3).length() >= 1e-14:
						face_of[o] = fi
						todo.append(o)
		var nsum := Vector3.ZERO
		for t in members:
			nsum += tk[t][1]
		var flat := nsum.length() > 1e-12
		if flat:
			var nn := nsum.normalized()
			for t in members:
				if (tk[t][1] as Vector3).normalized().dot(nn) < cos(deg_to_rad(3.0)):
					flat = false
					break
		var loops := _loops(on.keys(), ends, chains)
		var probe: Array = tk[members[0]]
		var f := {"loops": loops, "p0": _arr((probe[2] as Vector3)), "n0": _arr(((nsum if flat else probe[1]) as Vector3).normalized())}
		var tris := []
		for t in members:
			tris.append(tk[t][3])
		if flat and not loops.is_empty():
			f["type"] = "flat"
		elif loops.size() == 2 and loops[0].size() == 1 and loops[1].size() == 1:
			f["type"] = "ruled"
			f["rails"] = [loops[0][0], loops[1][0]]
		elif loops.size() == 2 and loops[0].size() <= 2 and loops[1].size() <= 2:
			f["type"] = "band"   # (a band between two loops of an edge or two each: a ring each)
		elif loops.size() == 1 and loops[0].size() == 4:
			# (the two opposite edges that aren't straight - else the longer pair - its rails)
			var lp: Array = loops[0]
			var straight := func(c: Array) -> bool: return _pv(chains[int(c[0])]["pts"]).size() == 2 or _is_straight(_pv(chains[int(c[0])]["pts"]))
			var pair_a := [lp[0], lp[2]]
			var pair_b := [lp[1], lp[3]]
			if straight.call(lp[1]) and straight.call(lp[3]) and not (straight.call(lp[0]) and straight.call(lp[2])):
				f["rails"] = pair_a
			elif straight.call(lp[0]) and straight.call(lp[2]) and not (straight.call(lp[1]) and straight.call(lp[3])):
				f["rails"] = pair_b
			else:
				f["rails"] = pair_a if _len(chains, lp[0]) + _len(chains, lp[2]) >= _len(chains, lp[1]) + _len(chains, lp[3]) else pair_b
			f["type"] = "ruled"
		else:
			f["type"] = "mesh"
			f["tris"] = tris
		out.append(f)
	return out


static func _is_straight(pts: PackedVector3Array) -> bool:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var tol := maxf(a.distance_to(b) * 2e-3, 1e-5)
	for q in pts:
		if Geometry3D.get_closest_point_to_segment(q, a, b).distance_to(q) > tol:
			return false
	return true


static func _len(chains: Array, c: Array) -> float:
	var pts := _pv(chains[int(c[0])]["pts"])
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## The chains round a face put in order into loops: [[chain, reversed]...] each (a closed chain: a loop
## of its own).
static func _loops(cis: Array, ends: Array, chains: Array) -> Array:
	var left := cis.duplicate()
	var loops := []
	for ci in cis:
		if bool(chains[ci].get("closed", false)):
			loops.append([[ci, false]])
			left.erase(ci)
	while not left.is_empty():
		var first: int = left.pop_front()
		var lp := [[first, false]]
		var start: Vector3i = ends[first][0]
		var cur: Vector3i = ends[first][1]
		var guard := 0
		while cur != start and guard < 1000:
			guard += 1
			var found := false
			for ci in left:
				if ends[ci][0] == cur:
					lp.append([ci, false])
					cur = ends[ci][1]
					left.erase(ci)
					found = true
					break
				if ends[ci][1] == cur:
					lp.append([ci, true])
					cur = ends[ci][0]
					left.erase(ci)
					found = true
					break
			if not found:
				break
		loops.append(lp)
	return loops


## The solid made again from its edges as they are now: flat faces filled from their edge loops, walls
## between two edges made as strips between them, any other face's triangles moved with the edges
## (`moved`: the base's arrays with its edges moved - deform's). One surface; shaded after.
static func build(fs: Array, chains: Array, now: Dictionary, moved: Array, mat: Material) -> ArrayMesh:
	var b := CT.Shapes.B.new()
	var curve_pts := func(c: Array) -> PackedVector3Array:
		var ch: Dictionary = chains[int(c[0])]
		var cv: Dictionary = now.get(int(ch["id"]), {})
		var s := CT.sample(cv) if not cv.is_empty() else _pv(ch["pts"])
		if bool(c[1]):
			s.reverse()
		return s
	for f: Dictionary in fs:
		var n0 := _v3(f["n0"])
		match str(f["type"]):
			"flat":
				var rings := []
				for lp in f["loops"]:
					var ring := PackedVector3Array()
					for c in lp:
						var s: PackedVector3Array = curve_pts.call(c)
						if lp.size() > 1 and s.size() > 1:
							s.remove_at(s.size() - 1)   # (its end: the next edge's start)
						ring.append_array(s)
					if ring.size() >= 3:
						rings.append(ring)
				if rings.is_empty():
					continue
				rings.sort_custom(func(x, y): return absf(CT._winding(x, n0)) > absf(CT._winding(y, n0)))
				var outer: PackedVector3Array = rings[0]
				if CT._winding(outer, n0) < 0.0:
					outer.reverse()
				var holes := []
				for i in range(1, rings.size()):
					var h: PackedVector3Array = rings[i]
					if CT._winding(h, n0) > 0.0:
						h.reverse()
					holes.append(h)
				var u := (outer[1] - outer[0]).normalized()
				CT.cap(b, CT.keyhole(outer, holes), n0, u if u != Vector3.ZERO else CT._any_perp(n0))
			"ruled":
				var ra: PackedVector3Array = curve_pts.call(f["rails"][0])
				var rb: PackedVector3Array = curve_pts.call(f["rails"][1])
				var closed := bool(chains[int(f["rails"][0][0])].get("closed", false))
				var m := maxi(ra.size(), rb.size())
				if closed:
					if ra.size() != m:
						ra = CT._resample_loop(ra, m)
					if rb.size() != m:
						rb = CT._resample_loop(rb, m)
					var nr := _normal(ra, true)
					rb = CT._matched(ra, rb, nr if nr != Vector3.ZERO else Vector3.UP)
				else:
					if ra[0].distance_to(rb[0]) + ra[ra.size() - 1].distance_to(rb[rb.size() - 1]) > ra[0].distance_to(rb[rb.size() - 1]) + ra[ra.size() - 1].distance_to(rb[0]):
						rb.reverse()
					if ra.size() != m:
						ra = _resample_open(ra, m)
					if rb.size() != m:
						rb = _resample_open(rb, m)
				var P := []
				for i in m:
					P.append(PackedVector3Array([ra[i], rb[i]]))
				if closed:
					P.append(P[0])
				# (which way it faces: as the face did - its normal near where it was)
				var p0 := _v3(f["p0"])
				var best := 0
				var bd := INF
				for i in m - 1:
					var d := ((ra[i] + rb[i]) * 0.5).distance_to(p0)
					if d < bd:
						bd = d
						best = i
				var tn := (ra[best + 1] - ra[best]).cross(rb[best] - ra[best])
				if tn.dot(n0) < 0.0:
					P.reverse()
				b.sheet(P, PackedInt32Array(), PackedInt32Array(), false)
			"band":
				var rings := []
				for lp in f["loops"]:
					var ring := PackedVector3Array()
					for c in lp:
						var s: PackedVector3Array = curve_pts.call(c)
						if lp.size() > 1 and s.size() > 1:
							s.remove_at(s.size() - 1)
						ring.append_array(s)
					rings.append(ring)
				if (rings[0] as PackedVector3Array).size() < 3 or (rings[1] as PackedVector3Array).size() < 3:
					continue
				var m := maxi(96, maxi(rings[0].size(), rings[1].size()))
				var ra: PackedVector3Array = CT._resample_loop(rings[0], m)
				var rb: PackedVector3Array = CT._resample_loop(rings[1], m)
				var nr := _normal(ra, true)
				rb = CT._matched(ra, rb, nr if nr != Vector3.ZERO else Vector3.UP)
				var P := []
				for i in m:
					P.append(PackedVector3Array([ra[i], rb[i]]))
				P.append(P[0])
				var p0 := _v3(f["p0"])
				var best := 0
				var bd := INF
				for i in m - 1:
					var d := ((ra[i] + rb[i]) * 0.5).distance_to(p0)
					if d < bd:
						bd = d
						best = i
				if (ra[best + 1] - ra[best]).cross(rb[best] - ra[best]).dot(n0) < 0.0:
					P.reverse()
				b.sheet(P, PackedInt32Array(), PackedInt32Array(), false)
			_:
				var want := {}
				for t in f.get("tris", []):
					want[int(t)] = true
				var g := 0
				for a in moved:
					var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
					var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
					for t in range(0, ix.size(), 3):
						if want.has(g):
							var i0 := b.add(vs[ix[t]], Vector3.UP, Vector2.ZERO)
							var i1 := b.add(vs[ix[t + 1]], Vector3.UP, Vector2.ZERO)
							var i2 := b.add(vs[ix[t + 2]], Vector3.UP, Vector2.ZERO)
							b.tri(i0, i2, i1)   # (the builder's way round, as the filled faces are - all turned out at the end)
						g += 1
	var m := CT._commit(b, true)
	if m == null:
		return null
	m.surface_set_material(0, mat)
	return CT.auto_smooth(m)


static func _resample_open(s: PackedVector3Array, m: int) -> PackedVector3Array:
	var lens := PackedFloat32Array([0.0])
	for i in range(1, s.size()):
		lens.append(lens[i - 1] + s[i - 1].distance_to(s[i]))
	var total := lens[lens.size() - 1]
	var out := PackedVector3Array()
	var k := 0
	for j in m:
		var d := total * j / maxf(m - 1, 1)
		while k < s.size() - 2 and lens[k + 1] < d:
			k += 1
		var w := (d - lens[k]) / maxf(lens[k + 1] - lens[k], 1e-9)
		out.append(s[k].lerp(s[k + 1], clampf(w, 0.0, 1.0)))
	return out


## The base's arrays with its edges moved (and its other points with them) - unshaded.
static func moved_arrays(base: ArrayMesh, chains: Array, old: Dictionary, now: Dictionary) -> Array:
	var m := deform(base, chains, old, now, false)
	var out := []
	for si in m.get_surface_count():
		out.append(m.surface_get_arrays(si))
	return out


static func _pv(v: Variant) -> PackedVector3Array:
	if v is PackedVector3Array:
		return v
	var out := PackedVector3Array()
	for q in v:
		out.append(_v3(q))
	return out


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# --- a clean, even mesh, moved smoothly with its edges ---------------------------------------------

## Mesh `m` remeshed into even triangles about `L` across - its edges (the chains' points, in order)
## kept exactly: long edges split (an edge's halves on it), then edges flipped and points eased toward
## their neighbours for well-shaped triangles (only inside faces, across nearly flat edges).
## {v: PackedVector3Array, t: PackedInt32Array, chains: [vertex indices along each chain]}.
static func remesh(m, chains: Array, L: float) -> Dictionary:
	var V := []
	var idx := {}
	var T := []
	for si in m.get_surface_count():
		var a: Array = m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			var tri := PackedInt32Array()
			for j in 3:
				var k := key(vs[ix[t + j]])
				if not idx.has(k):
					idx[k] = V.size()
					V.append(vs[ix[t + j]])
				tri.append(idx[k])
			if tri[0] != tri[1] and tri[1] != tri[2] and tri[0] != tri[2]:
				T.append(tri)
	# the edges: each chain's points as vertices (in order); its segments - feature edges
	var feat := {}   # "a,b" (sorted) -> chain index
	var cv := []   # each chain's vertices in order (grows as its segments split)
	for ci in chains.size():
		var pts: PackedVector3Array = _pv(chains[ci]["pts"])
		var vs := []
		for q in pts:
			vs.append(idx.get(key(q), -1))
		if bool(chains[ci].get("closed", false)) and vs.size() > 1:
			vs.append(vs[0])
		for j in vs.size() - 1:
			if vs[j] >= 0 and vs[j + 1] >= 0:
				feat[_pk(vs[j], vs[j + 1])] = ci
		cv.append(vs)
	var E := _edge_map(T)
	# split: the longest first, until none is over 4/3 L
	var hi := L * 4.0 / 3.0
	for pass_ in 12:   # (passes: every edge over the length split, the longest first)
		var long := []
		for e in E:
			var ab: PackedInt32Array = _unpk(e)
			var l: float = (V[ab[0]] as Vector3).distance_to(V[ab[1]])
			if l > hi:
				long.append([l, e])
		if long.is_empty():
			break
		long.sort_custom(func(x, y): return x[0] > y[0])
		for le in long:
			var e: String = le[1]
			if E.has(e):
				_split(e, V, T, E, feat, cv)
	# shape: flips (towards wider angles) and easing (points inside faces toward their neighbours)
	var fixed := {}
	for vs in cv:
		for v in vs:
			if v >= 0:
				fixed[v] = true
	for it in 4:
		_flips(V, T, E, feat)
		_ease(V, T, E, fixed)
	_flips(V, T, E, feat)
	var tv := PackedInt32Array()
	for tri in T:
		if tri != null:
			tv.append_array(tri)
	var pv := PackedVector3Array()
	for q in V:
		pv.append(q)
	return {"v": pv, "t": tv, "chains": cv}


static func _pk(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]


static func _unpk(e: String) -> PackedInt32Array:
	var p := e.split(",")
	return PackedInt32Array([int(p[0]), int(p[1])])


static func _edge_map(T: Array) -> Dictionary:
	var E := {}
	for ti in T.size():
		if T[ti] == null:
			continue
		var tri: PackedInt32Array = T[ti]
		for j in 3:
			var e := _pk(tri[j], tri[(j + 1) % 3])
			if not E.has(e):
				E[e] = []
			E[e].append(ti)
	return E


static func _set_tri(ti: int, tri: Variant, T: Array, E: Dictionary) -> void:
	if T[ti] != null:
		var old: PackedInt32Array = T[ti]
		for j in 3:
			var e := _pk(old[j], old[(j + 1) % 3])
			if E.has(e):
				(E[e] as Array).erase(ti)
				if (E[e] as Array).is_empty():
					E.erase(e)
	T[ti] = tri
	if tri != null:
		var nt: PackedInt32Array = tri
		for j in 3:
			var e := _pk(nt[j], nt[(j + 1) % 3])
			if not E.has(e):
				E[e] = []
			E[e].append(ti)


static func _split(e: String, V: Array, T: Array, E: Dictionary, feat: Dictionary, cv: Array) -> void:
	var ab := _unpk(e)
	var a := ab[0]
	var b := ab[1]
	var m := V.size()
	V.append(((V[a] as Vector3) + (V[b] as Vector3)) * 0.5)
	for ti in (E[e] as Array).duplicate():
		var tri: PackedInt32Array = T[ti]
		var k := 0
		while not ((tri[k] == a and tri[(k + 1) % 3] == b) or (tri[k] == b and tri[(k + 1) % 3] == a)):
			k += 1
		var p := tri[k]
		var q := tri[(k + 1) % 3]
		var r := tri[(k + 2) % 3]
		_set_tri(ti, PackedInt32Array([p, m, r]), T, E)
		T.append(null)
		_set_tri(T.size() - 1, PackedInt32Array([m, q, r]), T, E)
	if feat.has(e):
		var ci: int = feat[e]
		feat.erase(e)
		feat[_pk(a, m)] = ci
		feat[_pk(m, b)] = ci
		var vs: Array = cv[ci]
		for j in vs.size() - 1:
			if (vs[j] == a and vs[j + 1] == b) or (vs[j] == b and vs[j + 1] == a):
				vs.insert(j + 1, m)
				break


static func _tri_n(V: Array, tri: PackedInt32Array) -> Vector3:
	return ((V[tri[2]] as Vector3) - V[tri[0]]).cross((V[tri[1]] as Vector3) - V[tri[0]]).normalized()


static func _flips(V: Array, T: Array, E: Dictionary, feat: Dictionary) -> void:
	for e in E.keys():
		if feat.has(e) or not E.has(e) or (E[e] as Array).size() != 2:
			continue
		var ab := _unpk(e)
		var t1: int = E[e][0]
		var t2: int = E[e][1]
		var A: PackedInt32Array = T[t1]
		var B: PackedInt32Array = T[t2]
		if _tri_n(V, A).dot(_tri_n(V, B)) < cos(deg_to_rad(12.0)):
			continue   # (a bend: flipping would change the shape)
		# (A as a, b, c with a -> b its edge; B the other way, its far point d)
		var k := 0
		while not (A[k] in ab and A[(k + 1) % 3] in ab):
			k += 1
		var a := A[k]
		var b := A[(k + 1) % 3]
		var c := A[(k + 2) % 3]
		var d := -1
		for x in B:
			if x != a and x != b:
				d = x
		if d < 0 or E.has(_pk(c, d)):
			continue
		var pa: Vector3 = V[a]
		var pb: Vector3 = V[b]
		var pc: Vector3 = V[c]
		var pd: Vector3 = V[d]
		if (pa - pc).angle_to(pb - pc) + (pa - pd).angle_to(pb - pd) <= PI + 1e-6:
			continue   # (already the wider way)
		var n1 := (pd - pc).cross(pa - pc)
		var n2 := (pb - pc).cross(pd - pc)
		if n1.dot(_tri_n(V, A)) > 0.0 or n2.dot(_tri_n(V, A)) > 0.0:
			continue   # (it would fold)
		_set_tri(t1, PackedInt32Array([c, a, d]), T, E)
		_set_tri(t2, PackedInt32Array([d, b, c]), T, E)


static func _ease(V: Array, T: Array, E: Dictionary, fixed: Dictionary) -> void:
	var nb := {}
	var nrm := {}
	for tri in T:
		if tri == null:
			continue
		var n := _tri_n(V, tri)
		for j in 3:
			var v: int = tri[j]
			if not nb.has(v):
				nb[v] = {}
				nrm[v] = Vector3.ZERO
			nb[v][tri[(j + 1) % 3]] = true
			nb[v][tri[(j + 2) % 3]] = true
			nrm[v] += n
	for v in nb:
		if fixed.has(v):
			continue
		var c := Vector3.ZERO
		for o in nb[v]:
			c += V[o]
		c /= (nb[v] as Dictionary).size()
		var n: Vector3 = (nrm[v] as Vector3).normalized()
		var d := c - (V[v] as Vector3)
		V[v] = (V[v] as Vector3) + (d - n * d.dot(n)) * 0.5


## Each vertex's neighbours (for the smooth move).
static func neighbours(t: PackedInt32Array, nv: int) -> Array:
	var nb := []
	for i in nv:
		nb.append({})
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := t[i + j]
			nb[a][t[i + (j + 1) % 3]] = true
			nb[a][t[i + (j + 2) % 3]] = true
	var out := []
	for d in nb:
		out.append(PackedInt32Array((d as Dictionary).keys()))
	return out


## The edge points' moves (vertex -> move): each as its curve moved there, a corner the largest. Curves
## that didn't change move none of their points (nothing worked out for them); each changed curve sampled
## once (its line and lengths), its points' places looked up on that by halving.
static func edge_moves(fv: Array, chains: Array, old: Dictionary, now: Dictionary, v: PackedVector3Array) -> Dictionary:
	var moves := {}
	var maps := {}
	var polys := {}   # id -> [old line, old lengths, new line, new lengths] ({} - unchanged)
	for e in fv:
		var vi := int(e[0])
		var ch: Dictionary = chains[int(e[1])]
		var id := int(ch["id"])
		if not old.has(id) or not now.has(id):
			continue
		if not polys.has(id):
			var c0: Dictionary = old[id]
			var c1: Dictionary = now[id]
			if _same_curve(c0, c1):
				polys[id] = []
			else:
				var pa := _poly(c0)
				var pb := _poly(c1)
				polys[id] = [pa[0], pa[1], pb[0], pb[1]]
				maps[id] = span_map(c0, c1)
		var pl: Array = polys[id]
		var d := Vector3.ZERO
		if not pl.is_empty():
			var c0: Dictionary = old[id]
			var c1: Dictionary = now[id]
			if str(c0["kind"]) == "circle" and str(c1["kind"]) == "circle":
				d = _round_move(v[vi], c0, c1)
			else:
				var t := float(e[2])
				d = _at_poly(pl[2], pl[3], map_t(maps[id], t)) - _at_poly(pl[0], pl[1], t)
		if not moves.has(vi) or (moves[vi] as Vector3).length() < d.length():
			moves[vi] = d
	return moves


## Two curves the same shape (the same kind, points and settings).
static func _same_curve(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("kind", "")) != str(b.get("kind", "")) or bool(a.get("closed", false)) != bool(b.get("closed", false)):
		return false
	# (within a hair: a curve read back from text isn't moved for its last digits)
	for k in ["ctrl", "tin", "tout"]:
		var pa = a.get(k)
		var pb = b.get(k)
		if pa == null and pb == null:
			continue
		if pa == null or pb == null or (pa as PackedVector3Array).size() != (pb as PackedVector3Array).size():
			if k == "ctrl" or not (_all_zero(pa) and _all_zero(pb)):
				return false
			continue
		for i in (pa as PackedVector3Array).size():
			if (pa[i] as Vector3).distance_squared_to(pb[i]) > 1e-12:
				return false
	if Array(a.get("sharp", PackedByteArray())) != Array(b.get("sharp", PackedByteArray())):
		return false
	var ra = a.get("radii", PackedFloat32Array())
	var rb = b.get("radii", PackedFloat32Array())
	if (ra as PackedFloat32Array).size() != (rb as PackedFloat32Array).size():
		return false
	for i in (ra as PackedFloat32Array).size():
		if absf(float(ra[i]) - float(rb[i])) > 1e-6:
			return false
	return (a.get("n", Vector3.UP) as Vector3).distance_squared_to(b.get("n", Vector3.UP)) < 1e-12


static func _all_zero(v) -> bool:
	if v == null:
		return true
	for q in (v as PackedVector3Array):
		if q != Vector3.ZERO:
			return false
	return true


## Curve `c`'s sampled line (closed: back to its start) and the length along it at each point.
static func _poly(c: Dictionary) -> Array:
	var s := CT.sample(c)
	if c.get("closed", false) and s.size() > 0:
		s.append(s[0])
	var lens := PackedFloat32Array([0.0])
	for i in range(1, s.size()):
		lens.append(lens[i - 1] + s[i - 1].distance_to(s[i]))
	return [s, lens]


## The point a fraction `t` along a sampled line (`_poly`), found by halving.
static func _at_poly(s: PackedVector3Array, lens: PackedFloat32Array, t: float) -> Vector3:
	if s.size() == 1:
		return s[0]
	var d := clampf(t, 0.0, 1.0) * lens[lens.size() - 1]
	var lo := 1
	var hi := s.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if lens[mid] >= d:
			hi = mid
		else:
			lo = mid + 1
	var w := (d - lens[lo - 1]) / maxf(lens[lo] - lens[lo - 1], 1e-9)
	return s[lo - 1].lerp(s[lo], w)

## Every point's move: the edge points' as given, the others blended smoothly from them across the
## mesh (each the average of its neighbours', worked out from `start` - the last time's - till still).
static func smooth_moves(nv: int, nb: Array, fixed: Dictionary, start: PackedVector3Array, max_it := 400) -> PackedVector3Array:
	var d := start.duplicate() if start.size() == nv else PackedVector3Array()
	if d.size() != nv:
		d.resize(nv)
	for v in fixed:
		d[v] = fixed[v]
	for it in max_it:
		var most := 0.0
		for i in nv:
			if fixed.has(i):
				continue
			var n: PackedInt32Array = nb[i]
			if n.is_empty():
				continue
			var s := Vector3.ZERO
			for o in n:
				s += d[o]
			s /= n.size()
			most = maxf(most, s.distance_squared_to(d[i]))
			d[i] = s
		if most < 1e-12:
			break
	return d


## A baked mesh's points lying on its edges but not yet counted as theirs (a wall's rows up its side
## edge - the walls either side each with their own) welded into one and put in `fv` in their place along
## the edge, so moving that edge moves them. `old`: chain id -> its curve as the mesh was made.
## {fv, t} - the new edge points and the triangles with the welded points (null: nothing to do).
static func tie_edges(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array, old: Dictionary) -> Variant:
	var on := {}
	for e in fv:
		on[int(e[0])] = true
	var used := {}
	for i in t:
		used[i] = true
	var extra := {}   # chain index -> [[vertex, t]...]
	var weld := {}   # vertex -> the one it's welded to
	var at_key := {}   # weld key -> vertex
	for e in fv:
		at_key[key(v[int(e[0])])] = int(e[0])
	for ci in chains.size():
		var id := int(chains[ci]["id"])
		if not old.has(id):
			continue
		var c: Dictionary = old[id]
		var s := CT.sample(c)
		if c.get("closed", false):
			s.append(s[0])
		if s.size() < 2:
			continue
		var box := AABB(s[0], Vector3.ZERO)
		var total := 0.0
		for i in range(1, s.size()):
			box = box.expand(s[i])
			total += s[i - 1].distance_to(s[i])
		var tol := maxf(total * 1e-4, 1e-6)
		box = box.grow(tol)
		var pts := PackedVector3Array()
		var vis := []
		for vi in used:
			if on.has(vi) or weld.has(vi) or not box.has_point(v[vi]):
				continue
			var best := INF
			for i in range(1, s.size()):
				best = minf(best, Geometry3D.get_closest_point_to_segment(v[vi], s[i - 1], s[i]).distance_to(v[vi]))
				if best < tol:
					break
			if best < tol:
				var k := key(v[vi])
				if at_key.has(k):
					if int(at_key[k]) != vi:
						weld[vi] = at_key[k]
					continue
				at_key[k] = vi
				pts.append(v[vi])
				vis.append(vi)
		if vis.is_empty():
			continue
		var ts := params(pts, c)
		var lst := []
		for j in vis.size():
			lst.append([vis[j], ts[j]])
		extra[ci] = lst
	if extra.is_empty() and weld.is_empty():
		return null
	var nt := t.duplicate()
	for i in nt.size():
		if weld.has(nt[i]):
			nt[i] = weld[nt[i]]
	var by_chain := {}
	for e in fv:
		var ci := int(e[1])
		if not by_chain.has(ci):
			by_chain[ci] = []
		by_chain[ci].append([int(e[0]), float(e[2])])
	for ci in extra:
		var lst: Array = by_chain.get(ci, [])
		lst.append_array(extra[ci])
		var closed := bool(chains[ci].get("closed", false))
		var first: float = float(lst[0][1]) if closed and not lst.is_empty() else 0.0
		lst.sort_custom(func(a, b): return fposmod(float(a[1]) - first, 1.0) < fposmod(float(b[1]) - first, 1.0) if closed else float(a[1]) < float(b[1]))
		by_chain[ci] = lst
	var out := []
	for ci in chains.size():
		for e in by_chain.get(ci, []):
			out.append([e[0], ci, e[1]])
	return {"fv": out, "t": nt}


## The mesh's edges lying along the solid's edges: {_pk(a, b): true} for each mesh edge whose ends are both
## on one chain (fv) and whose middle is on that chain's curve (`old`: id -> the curve the mesh was made
## for) - not a chord across a cap between two points of one rim.
static func feature_edges(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array, old: Dictionary) -> Dictionary:
	var on := {}   # vertex -> [chain indices]
	for e in fv:
		var vi := int(e[0])
		if not on.has(vi):
			on[vi] = []
		on[vi].append(int(e[1]))
	var polys := {}
	var tols := {}
	var out := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := t[i + j]
			var b := t[i + (j + 1) % 3]
			if not on.has(a) or not on.has(b):
				continue
			var k := _pk(a, b)
			if out.has(k):
				continue
			var mid := (v[a] + v[b]) * 0.5
			for ci in on[a]:
				if not ci in on[b]:
					continue
				if not polys.has(ci):
					var id := int(chains[ci]["id"])
					var s := CT.sample(old[id]) if old.has(id) else PackedVector3Array()
					if not s.is_empty() and bool(chains[ci].get("closed", false)):
						s.append(s[0])
					var total := 0.0
					for m in range(1, s.size()):
						total += s[m - 1].distance_to(s[m])
					polys[ci] = s
					tols[ci] = maxf(total * 2e-3, 1e-5)
				var s: PackedVector3Array = polys[ci]
				if s.size() < 2:
					out[k] = true   # (no curve to check against: as before)
					break
				var best := INF
				for m in range(1, s.size()):
					best = minf(best, Geometry3D.get_closest_point_to_segment(mid, s[m - 1], s[m]).distance_to(mid))
				if best < float(tols[ci]):
					out[k] = true
					break
	# (and wherever faces meet at a real corner - over 45° - an edge, curve or not: a wall never runs
	# on into the top beside it)
	corner_edges(v, t, out)
	return out


## The mesh's edges where its faces meet at a real corner (over 80°) put into `out` ({_pk(a, b): true}).
static func corner_edges(v: PackedVector3Array, t: PackedInt32Array, out: Dictionary) -> void:
	var by_n := {}
	for i in range(0, t.size(), 3):
		var nrm := (v[t[i + 2]] - v[t[i]]).cross(v[t[i + 1]] - v[t[i]])
		for j in 3:
			var e := _pk(t[i + j], t[i + (j + 1) % 3])
			if not by_n.has(e):
				by_n[e] = []
			by_n[e].append(nrm)
	var c45 := cos(deg_to_rad(80.0))   # (carrying on - not turning back: a kink a boolean left is a corner on one edge)
	for e in by_n:
		var ns: Array = by_n[e]
		if ns.size() == 2 and (ns[0] as Vector3).length() > 1e-14 and (ns[1] as Vector3).length() > 1e-14 and (ns[0] as Vector3).normalized().dot((ns[1] as Vector3).normalized()) < c45:
			out[e] = true


## A baked mesh's flat faces rebuilt as quads: each flat face (between the solid's edges `feat`) laid out
## in columns across it - at every point of its edges and every `L` - each column from edge to edge (none
## across a hole), its points at rows the whole face shares (every L), neighbouring columns zipped row
## to row (quads; a triangle where an edge cuts across) - only those square to `up` (the solid's way up:
## its walls are rows of quads already); a column's end that falls between two edge
## points becomes a new point on that edge, and the wall beyond it is split there too (no cracks).
## `fv` gets the new edge points (each on its chain, its place between its neighbours').
## {v, t, fv} ({} - no flat face to rebuild).
static func quad_caps(v_in: PackedVector3Array, t: PackedInt32Array, fv: Array, feat: Dictionary, L: float, up := Vector3.ZERO, chains := []) -> Dictionary:
	var v := []
	for q in v_in:
		v.append(q)
	var nt := t.size() / 3
	var by_edge := {}
	for i in nt:
		for j in 3:
			var e := _pk(t[i * 3 + j], t[i * 3 + (j + 1) % 3])
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var face := PackedInt32Array()
	face.resize(nt)
	face.fill(-1)
	var groups := []
	for t0 in nt:
		if face[t0] >= 0:
			continue
		var g := [t0]
		face[t0] = groups.size()
		var k := 0
		while k < g.size():
			var ti: int = g[k]
			k += 1
			var tn_i := (v_in[t[ti * 3 + 2]] - v_in[t[ti * 3]]).cross(v_in[t[ti * 3 + 1]] - v_in[t[ti * 3]])
			for j in 3:
				var e := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
				for o in by_edge[e]:
					if face[o] >= 0:
						continue
					if feat.has(e):
						# (an edge of the solid's - unless the two sides lie flat in one plane: a sliver
						# along a gently curved edge, no real edge between them)
						var tn_o := (v_in[t[o * 3 + 2]] - v_in[t[o * 3]]).cross(v_in[t[o * 3 + 1]] - v_in[t[o * 3]])
						if tn_i.length() < 1e-14 or tn_o.length() < 1e-14 or tn_i.normalized().dot(tn_o.normalized()) < 0.9999:
							continue
					face[o] = groups.size()
					g.append(o)
		groups.append(g)
	var tris := []   # every triangle as [a, b, c] (null: gone)
	for i in nt:
		tris.append([t[i * 3], t[i * 3 + 1], t[i * 3 + 2]])
	# each chain's points in order along it (param, vertex), and each point's chains: {vertex: {ci: param}}
	var on_chain := {}
	var chain_pts := {}
	var chain_closed := {}
	for e in fv:
		var vi := int(e[0])
		var ci := int(e[1])
		if not on_chain.has(vi):
			on_chain[vi] = {}
		on_chain[vi][ci] = float(e[2])
		if not chain_pts.has(ci):
			chain_pts[ci] = []
		chain_pts[ci].append([float(e[2]), vi])
	for ci in chain_pts:
		(chain_pts[ci] as Array).sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		chain_closed[ci] = ci < chains.size() and bool(chains[ci].get("closed", false))
	var splits := {}   # edge key -> {t (0..1 from its smaller end): new vertex}
	var changed := false
	var new_tris := []
	for g: Array in groups:
		if g.size() < 2:
			continue
		# its rim: the edges only one of its triangles has (each the way its triangle runs)
		var cnt := {}
		for ti in g:
			var tr: Array = tris[ti]
			for j in 3:
				var e := _pk(int(tr[j]), int(tr[(j + 1) % 3]))
				cnt[e] = int(cnt.get(e, 0)) + 1
		var rim := []   # [a, b] pairs, a -> b
		for ti in g:
			var tr: Array = tris[ti]
			for j in 3:
				var a := int(tr[j])
				var b := int(tr[(j + 1) % 3])
				if int(cnt[_pk(a, b)]) == 1:
					rim.append([a, b])
		var n := Vector3.ZERO
		for ti in g:
			var tr: Array = tris[ti]
			n += ((v[tr[2]] as Vector3) - v[tr[0]]).cross((v[tr[1]] as Vector3) - v[tr[0]])
		if n.length() < 1e-12:
			continue
		var nn := n.normalized()
		if up != Vector3.ZERO and absf(nn.dot(up)) < 0.99:
			continue   # (a wall - already rows of quads)
		var flat := true
		for ti in g:
			var tr: Array = tris[ti]
			var tn: Vector3 = ((v[tr[2]] as Vector3) - v[tr[0]]).cross((v[tr[1]] as Vector3) - v[tr[0]])
			if tn.length() > 1e-14 and tn.normalized().dot(nn) < 0.9999:
				flat = false
				break
		if not flat:
			continue
		# (each rim edge along one of the solid's edges: every point that edge has between its ends
		# - the walls' - put in, so the cap meets them point for point)
		var full := []
		for e in rim:
			full.append_array(_along_chain(e[0], e[1], on_chain, chain_pts, chain_closed))
		rim = full
		if rim.size() < 3:
			continue
		var out := _cap_grid(v, rim, nn, L, splits)
		if out.is_empty():
			continue
		for ti in g:
			tris[ti] = null
		new_tris.append_array(out)
		changed = true
	if not changed:
		return {}
	# the triangles beyond a split edge (a wall's) split there too
	var vt := {}
	for i in tris.size():
		if tris[i] == null:
			continue
		for x in tris[i]:
			if not vt.has(x):
				vt[x] = []
			vt[x].append(i)
	for e in splits:
		var ab := _unpk(str(e))
		var pts: Dictionary = splits[e]
		var ks := pts.keys()
		ks.sort()
		for ti in vt.get(ab[0], []):
			var tr = tris[ti]
			if tr == null or not ab[1] in tr:
				continue
			var ia: int = (tr as Array).find(ab[0])
			var ib: int = (tr as Array).find(ab[1])
			var c: int = tr[3 - ia - ib]
			var x0: int = ab[0] if (ia + 1) % 3 == ib else ab[1]   # (its own way round: x0 -> x1)
			var x1: int = ab[1] if x0 == ab[0] else ab[0]
			var seq := [x0]
			var mids := []
			for kk in ks:
				mids.append(pts[kk])
			if x0 != ab[0]:
				mids.reverse()
			seq.append_array(mids)
			seq.append(x1)
			tris[ti] = null
			for m in seq.size() - 1:
				new_tris.append([seq[m], seq[m + 1], c])
	var ot := PackedInt32Array()
	for tr in tris:
		if tr != null:
			ot.append_array(PackedInt32Array(tr))
	for tr in new_tris:
		ot.append_array(PackedInt32Array(tr))
	# the new edge points: on their chain, between their edge's ends
	var on := {}
	for e in fv:
		if not on.has(int(e[0])):
			on[int(e[0])] = []
		on[int(e[0])].append([int(e[1]), float(e[2])])
	var nfv := fv.duplicate(true)
	for e in splits:
		var ab := _unpk(str(e))
		for ca in on.get(ab[0], []):
			for cb in on.get(ab[1], []):
				if int(ca[0]) != int(cb[0]):
					continue
				var ta := float(ca[1])
				var tb := float(cb[1])
				if absf(ta - tb) > 0.5:   # (across a closed chain's start)
					if ta < tb:
						ta += 1.0
					else:
						tb += 1.0
				var pts: Dictionary = splits[e]
				for kk in pts:
					nfv.append([int(pts[kk]), int(ca[0]), fposmod(lerpf(ta, tb, float(kk) / 1e6), 1.0 + 1e-9)])
	var pv := PackedVector3Array()
	for q in v:
		pv.append(q)
	return {"v": pv, "t": ot, "fv": nfv}


## Rim edge a -> b as the run of edge points between them along the chain they're both on ([[a, b]]
## if none): [[a, p1], [p1, p2], ... [pk, b]].
static func _along_chain(a: int, b: int, on_chain: Dictionary, chain_pts: Dictionary, chain_closed: Dictionary) -> Array:
	if not on_chain.has(a) or not on_chain.has(b):
		return [[a, b]]
	for ci in on_chain[a]:
		if not (on_chain[b] as Dictionary).has(ci):
			continue
		var ta: float = on_chain[a][ci]
		var tb: float = on_chain[b][ci]
		var lst: Array = chain_pts[ci]
		var mids := []
		var fwd := tb > ta
		var wrap := bool(chain_closed.get(ci, false)) and absf(tb - ta) > 0.5
		for e in lst:
			var tp := float(e[0])
			var vi := int(e[1])
			if vi == a or vi == b:
				continue
			var between := false
			if not wrap:
				between = (tp > minf(ta, tb) + 1e-7) and (tp < maxf(ta, tb) - 1e-7)
			else:
				between = tp > maxf(ta, tb) + 1e-7 or tp < minf(ta, tb) - 1e-7
			if between:
				mids.append([tp, vi])
		if mids.is_empty():
			return [[a, b]]
		# (in the order from a to b)
		if not wrap:
			mids.sort_custom(func(x, y): return float(x[0]) < float(y[0]) if fwd else float(x[0]) > float(y[0]))
		else:
			# (round the loop's start: from a's side on past 1 to 0 and on to b)
			mids.sort_custom(func(x, y): return fposmod(float(x[0]) - ta, 1.0) < fposmod(float(y[0]) - ta, 1.0) if tb < ta else fposmod(ta - float(x[0]), 1.0) < fposmod(ta - float(y[0]), 1.0))
		var seq := [a]
		for m in mids:
			seq.append(int(m[1]))
		seq.append(b)
		var out := []
		for k in seq.size() - 1:
			out.append([seq[k], seq[k + 1]])
		return out
	return [[a, b]]


## One flat face (its rim edges [a, b], facing `n`) as columns of quads - see quad_caps. New points go
## onto `v`; a column's end between two rim points: splits[edge][t] = its vertex. [] - couldn't.
static func _cap_grid(v: Array, rim: Array, n: Vector3, L: float, splits: Dictionary, snap_ends := false) -> Array:
	# across it along its longest straight rim edge, so a box's top is a plain grid
	var u := CT._any_perp(n)
	var bl := 0.0
	for e in rim:
		var d: Vector3 = (v[e[1]] as Vector3) - v[e[0]]
		d -= n * d.dot(n)
		if d.length() > bl:
			bl = d.length()
			u = d.normalized()
	var w := n.cross(u)
	var s_of := func(i: int) -> float: return (v[i] as Vector3).dot(u)
	var h_of := func(i: int) -> float: return (v[i] as Vector3).dot(w)
	# stations: the rim's points - where it turns back (across the columns) and its far ends always,
	# the others not closer than a third of L to a kept one (where the rim runs across, its points bunch
	# up: no paper-thin columns) - and every L between
	var nb_r := {}   # rim point -> its two neighbours along the rim
	for e in rim:
		for pr in [[e[0], e[1]], [e[1], e[0]]]:
			if not nb_r.has(pr[0]):
				nb_r[pr[0]] = []
			nb_r[pr[0]].append(pr[1])
	var must := []
	var rest := []
	var smin := INF
	var smax := -INF
	for x in nb_r:
		var sx: float = s_of.call(x)
		smin = minf(smin, sx)
		smax = maxf(smax, sx)
		var ns: Array = nb_r[x]
		var turn := ns.size() != 2
		if not turn:
			var d0: float = s_of.call(ns[0]) - sx
			var d1: float = s_of.call(ns[1]) - sx
			turn = d0 * d1 >= 0.0   # (both neighbours on one side: it turns back here)
		(must if turn else rest).append(sx)
	var ss := must.duplicate()
	rest.sort()
	for sx in rest:
		var near := false
		for k in ss:
			if absf(float(k) - float(sx)) < L / 3.0:
				near = true
				break
		if not near:
			ss.append(sx)
	var nst := maxi(1, ceili((smax - smin) / L))
	var stp := (smax - smin) / nst
	var fixed := ss.duplicate()
	for k in range(1, nst):
		var sx := smin + stp * k
		var near := false
		for f in fixed:
			if absf(float(f) - sx) < stp * 0.3:
				near = true
				break
		if not near:
			ss.append(sx)
	ss.sort()
	var st := []
	for sx in ss:
		if st.is_empty() or float(sx) - float(st[st.size() - 1]) > 1e-6:
			st.append(sx)
	# a crossing of the rim at station sx: its vertex (an existing point, or new on that edge)
	var cross_at := func(e: Array, sx: float) -> int:
		var sa: float = s_of.call(e[0])
		var sb: float = s_of.call(e[1])
		var tt := clampf((sx - sa) / (sb - sa), 0.0, 1.0) if absf(sb - sa) > 1e-12 else 0.0
		if tt < 1e-6:
			return e[0]
		if tt > 1.0 - 1e-6:
			return e[1]
		if snap_ends:
			# (onto the rim's own nearer point when it's close - the wall beyond untouched)
			var near_e: int = e[0] if tt < 0.5 else e[1]
			var at_p: Vector3 = (v[e[0]] as Vector3).lerp(v[e[1]], tt)
			if at_p.distance_to(v[near_e]) < L * 0.34:
				return near_e
		var key := _pk(e[0], e[1])
		var lo: int = mini(e[0], e[1])
		var tk := int(round((tt if lo == e[0] else 1.0 - tt) * 1e6))
		if not splits.has(key):
			splits[key] = {}
		if not (splits[key] as Dictionary).has(tk):
			v.append((v[e[0]] as Vector3).lerp(v[e[1]], tt))
			splits[key][tk] = v.size() - 1
		return splits[key][tk]
	var stations := []   # each: [segments on its left, on its right] - a segment: [low end, high end]
	for sx in st:
		var sides := []
		for dx in [-1e-5, 1e-5]:
			var xs: float = float(sx) + dx
			var hits := []
			for e in rim:
				var sa: float = s_of.call(e[0])
				var sb: float = s_of.call(e[1])
				if (sa <= xs and xs < sb) or (sb <= xs and xs < sa):
					var vi: int = cross_at.call(e, float(sx))
					hits.append([vi, (v[vi] as Vector3).dot(w)])
			hits.sort_custom(func(p, q): return float(p[1]) < float(q[1]))
			var segs := []
			for k in range(0, hits.size() - 1, 2):
				segs.append([hits[k][0], hits[k + 1][0]])   # (a single point too - where the face narrows to a corner: its wedge fans from it)
			sides.append(segs)
		stations.append(sides)
	# rows the whole face shares
	var hmin := INF
	for e in rim:
		for x in e:
			hmin = minf(hmin, h_of.call(x))
	var welded := {}
	var col := func(sg: Array) -> Array:   # [vertices low to high, their heights]
		var a: Vector3 = v[sg[0]]
		var b: Vector3 = v[sg[1]]
		var h0 := a.dot(w)
		var h1 := b.dot(w)
		var vs := PackedInt32Array([sg[0]])
		var hs := PackedFloat32Array([h0])
		var k0 := ceili((h0 - hmin) / L + 0.3)
		var hk := hmin + L * k0
		while hk < h1 - L * 0.3:
			var q := a.lerp(b, (hk - h0) / (h1 - h0))
			var qk := key(q)
			if not welded.has(qk):   # (two columns at one station - either side of a rim point - share it)
				v.append(q)
				welded[qk] = v.size() - 1
			vs.append(welded[qk])
			hs.append(hk)
			hk += L
		vs.append(sg[1])
		hs.append(h1)
		return [vs, hs]
	# the rim with every point on it (split points too), for the strips' ends between their columns
	var rdir := {}   # rim point -> the next one the way the face runs round it
	var rn := {}   # point -> [neighbours along the rim]
	for e in rim:
		var seq := [e[0]]
		var key2 := _pk(e[0], e[1])
		if splits.has(key2):
			var lo2: int = mini(e[0], e[1])
			var ks2: Array = (splits[key2] as Dictionary).keys()
			ks2.sort()
			var mids2 := []
			for kk in ks2:
				mids2.append(splits[key2][kk])
			if lo2 != e[0]:
				mids2.reverse()
			seq.append_array(mids2)
		seq.append(e[1])
		for m in seq.size() - 1:
			rdir[seq[m]] = seq[m + 1]
			for pr in [[seq[m], seq[m + 1]], [seq[m + 1], seq[m]]]:
				if not rn.has(pr[0]):
					rn[pr[0]] = []
				if not pr[1] in rn[pr[0]]:
					rn[pr[0]].append(pr[1])
	# the rim's points strictly between stations s0 and s1 on the way from point a to point b ([] - straight)
	var rim_between := func(a0: int, b0: int, s0: float, s1: float) -> Array:
		if a0 == b0:
			return []
		for first in rn.get(a0, []):
			var path := []
			var prev := a0
			var cur: int = first
			var ok := false
			for guard in 500:
				if cur == b0:
					ok = true
					break
				var sc: float = s_of.call(cur)
				if sc <= s0 + 1e-7 or sc >= s1 - 1e-7:
					break
				path.append(cur)
				var nx := -1
				for o in rn.get(cur, []):
					if o != prev:
						nx = o
						break
				if nx < 0:
					break
				prev = cur
				cur = nx
			if ok:
				return path
		return []
	var cols := {}   # segment (as string) -> its column - made once, shared by both sides
	var tris := []
	var rim_tris := []   # (the strips' ends along the rim: turned by the rim, not by their shape)
	for c in stations.size() - 1:
		for sa_ in stations[c][1]:
			for sb_ in stations[c + 1][0]:
				var ka := str(sa_)
				var kb := str(sb_)
				if not cols.has(ka):
					cols[ka] = col.call(sa_)
				if not cols.has(kb):
					cols[kb] = col.call(sb_)
				var A: PackedInt32Array = cols[ka][0]
				var Ah: PackedFloat32Array = cols[ka][1]
				var B: PackedInt32Array = cols[kb][0]
				var Bh: PackedFloat32Array = cols[kb][1]
				if minf(Ah[Ah.size() - 1], Bh[Bh.size() - 1]) - maxf(Ah[0], Bh[0]) < -1e-6:
					continue   # (not side by side: a hole or a notch between)
				# (its ends: the rim's points between the two columns' ends, if any - fanned from the column
				# end beside them; then zipped bottom to top)
				var s0: float = float(st[c])
				var s1: float = float(st[c + 1])
				for pair in [[A[0], B[0]], [A[A.size() - 1], B[B.size() - 1]]]:
					var mid: Array = rim_between.call(pair[0], pair[1], s0, s1)
					if mid.is_empty():
						continue
					var chain := [pair[0]]
					chain.append_array(mid)
					chain.append(pair[1])
					for m in range(1, chain.size() - 1):
						# (its way round from the rim edge it has - however thin, never inside out)
						if rdir.get(chain[m], -1) == chain[m + 1]:
							rim_tris.append([chain[0], chain[m], chain[m + 1]])
						else:
							rim_tris.append([chain[0], chain[m + 1], chain[m]])
				var ia := 0
				var ib := 0
				var ea := Ah.size() - 1
				var eb := Bh.size() - 1
				while ia < ea or ib < eb:
					if ia < ea and ib < eb and absf(Ah[ia + 1] - Bh[ib + 1]) < 1e-6:
						tris.append([A[ia], B[ib], B[ib + 1]])
						tris.append([A[ia], B[ib + 1], A[ia + 1]])
						ia += 1
						ib += 1
					elif ib < eb and (ia >= ea or Bh[ib + 1] < Ah[ia + 1]):
						tris.append([A[ia], B[ib], B[ib + 1]])
						ib += 1
					else:
						tris.append([A[ia], B[ib], A[ia + 1]])
						ia += 1
	var out := []
	for tr in tris:
		if tr[0] == tr[1] or tr[1] == tr[2] or tr[0] == tr[2]:
			continue
		var tn := _turn(v, tr, n)
		if absf(tn) < 1e-14:
			continue
		out.append(tr if tn > 0.0 else [tr[0], tr[2], tr[1]])
	for tr in rim_tris:
		if tr[0] != tr[1] and tr[1] != tr[2] and tr[0] != tr[2]:
			out.append(tr)
	return out


## (settling) Each four-sided face touching a reshaped edge (`moved_ci`: chain indices) made again as a
## grid for its shape now - a Coons patch between its four sides: its two longer sides the rails, a
## column wherever either rail has a point (the other rail given one there, on its curve), its rows from
## its two other sides; zipped side to side, quads where rows match. Its old inner points left unused;
## the faces beyond meet its new edge points once close_seams runs. Changes `v`, `t`, `fv`; true -
## something was rebuilt.
static func _rebuild_faces(v: Array, t: Array, fv: Array, chains: Array, now: Dictionary, feat: Dictionary, moved_ci: Dictionary, L: float) -> bool:
	var nt := t.size()
	var by_edge := {}
	for i in nt:
		for j in 3:
			var e := _pk(int(t[i][j]), int(t[i][(j + 1) % 3]))
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var on := {}   # vertex -> {chain index: place}
	for e in fv:
		if not on.has(int(e[0])):
			on[int(e[0])] = {}
		on[int(e[0])][int(e[1])] = float(e[2])
	var face := PackedInt32Array()
	face.resize(nt)
	face.fill(-1)
	var groups := []
	for t0 in nt:
		if face[t0] >= 0:
			continue
		var g := [t0]
		face[t0] = groups.size()
		var k := 0
		while k < g.size():
			var ti: int = g[k]
			k += 1
			for j in 3:
				var e := _pk(int(t[ti][j]), int(t[ti][(j + 1) % 3]))
				if feat.has(e):
					continue
				for o in by_edge[e]:
					if face[o] < 0:
						face[o] = groups.size()
						g.append(o)
		groups.append(g)
	var drop := {}
	var add := []
	var splits := []   # [a, b, share from a, new point] - points put on side a-b of a rebuilt face
	for g: Array in groups:
		# (touching a reshaped edge)
		var touches := false
		for ti in g:
			for x in t[ti]:
				if on.has(x):
					for ci in on[x]:
						if moved_ci.has(ci):
							touches = true
		if not touches or g.size() < 2:
			continue
		# its boundary: one loop
		var cnt := {}
		for ti in g:
			for j in 3:
				var e := _pk(int(t[ti][j]), int(t[ti][(j + 1) % 3]))
				cnt[e] = int(cnt.get(e, 0)) + 1
		var nxt := {}
		var bad := false
		for ti in g:
			for j in 3:
				var a := int(t[ti][j])
				var b := int(t[ti][(j + 1) % 3])
				if int(cnt[_pk(a, b)]) == 1:
					if nxt.has(a):
						bad = true
					nxt[a] = b
		if bad or nxt.size() < 4:
			continue
		var loop := []
		var st: int = nxt.keys()[0]
		var cur := st
		for guard in nxt.size() + 1:
			loop.append(cur)
			cur = nxt[cur]
			if cur == st:
				break
		if cur != st or loop.size() != nxt.size():
			continue   # (more than one loop - a hole: left as it is)
		# its corners: points on two curves or more, or where the boundary turns sharply
		var corners := []
		for i in loop.size():
			var x: int = loop[i]
			var is_c := on.has(x) and (on[x] as Dictionary).size() > 1
			if not is_c:
				var p0: Vector3 = v[loop[(i - 1 + loop.size()) % loop.size()]]
				var p1: Vector3 = v[x]
				var p2: Vector3 = v[loop[(i + 1) % loop.size()]]
				if (p1 - p0).length() > 1e-9 and (p2 - p1).length() > 1e-9 and (p1 - p0).normalized().dot((p2 - p1).normalized()) < 0.5:
					is_c = true
			if is_c:
				corners.append(i)
		if corners.size() != 4:
			continue
		var sides := []   # each: [vertices from its corner to the next]
		var slen := []
		for c in 4:
			var i0: int = corners[c]
			var i1: int = corners[(c + 1) % 4]
			var sd := []
			var i := i0
			while true:
				sd.append(loop[i])
				if i == i1:
					break
				i = (i + 1) % loop.size()
			sides.append(sd)
			var ln := 0.0
			for m in range(1, sd.size()):
				ln += (v[sd[m]] as Vector3).distance_to(v[sd[m - 1]])
			slen.append(ln)
		var k0 := 0 if float(slen[0]) + float(slen[2]) >= float(slen[1]) + float(slen[3]) else 1
		var A: Array = sides[k0]   # rail A: corner c0 -> c1
		var B: Array = (sides[k0 + 2] as Array).duplicate()
		B.reverse()   # rail B: c3 -> c2 (along A)
		var Lft: Array = (sides[(k0 + 3) % 4] as Array).duplicate()
		Lft.reverse()   # c0 -> c3
		var Rgt: Array = sides[k0 + 1]   # c1 -> c2
		if float(slen[k0]) < 1e-6 or float(slen[k0 + 2]) < 1e-6:
			continue
		# each rail's points by their share along it
		var frac := func(pts: Array) -> PackedFloat32Array:
			var out := PackedFloat32Array([0.0])
			var tot := 0.0
			for m in range(1, pts.size()):
				tot += (v[pts[m]] as Vector3).distance_to(v[pts[m - 1]])
				out.append(tot)
			for m in out.size():
				out[m] = out[m] / maxf(tot, 1e-12)
			return out
		var fa: PackedFloat32Array = frac.call(A)
		var fb: PackedFloat32Array = frac.call(B)
		var fl: PackedFloat32Array = frac.call(Lft)
		var fr: PackedFloat32Array = frac.call(Rgt)
		# the columns: every rail point's share (close ones as one), and every L along the longer rail
		var longer := maxf(float(slen[k0]), float(slen[k0 + 2]))
		# (every point either rail has: a column of its own - the faces beyond meet them; the other rail's
		# shares close to one of its own snapped onto it)
		var nmin := maxi(1, ceili(longer / L))
		var tol := minf(0.3 * L / maxf(longer, 1e-9), 0.3 / nmin)
		var shares := []
		for x in fa:
			shares.append(float(x))
		for x in fb:
			var near := false
			for y in fa:
				if absf(float(y) - float(x)) < tol:
					near = true   # (B's point paired with A's column there)
			if not near:
				shares.append(float(x))
		for m in range(1, nmin):
			var x := float(m) / nmin
			var near := false
			for y in shares:
				if absf(float(y) - x) < tol:
					near = true
					break
			if not near:
				shares.append(x)
		shares.sort()
		var F := []
		for x in shares:
			if F.is_empty() or float(x) - float(F[F.size() - 1]) > 1e-6:
				F.append(x)
		if float(F[0]) > 1e-6:
			F.push_front(0.0)
		if 1.0 - float(F[F.size() - 1]) > 1e-6:
			F.append(1.0)
		var used_r := {}
		# a rail's point at share f: its own when it has one there, else a new one on its curve
		var rail_pt := func(rail: Array, fr_: PackedFloat32Array, f: float) -> int:
			var bm := -1
			for m in rail.size():
				if absf(fr_[m] - f) <= 1e-6:
					return rail[m]
				if absf(fr_[m] - f) < tol and (bm < 0 or absf(fr_[m] - f) < absf(fr_[bm] - f)):
					bm = m
			if bm >= 0 and not used_r.has(rail[bm]):
				used_r[rail[bm]] = true
				return rail[bm]
			var m := 1
			while m < fr_.size() - 1 and fr_[m] < f:
				m += 1
			var a: int = rail[m - 1]
			var b: int = rail[m]
			var w := (f - fr_[m - 1]) / maxf(fr_[m] - fr_[m - 1], 1e-12)
			var q: Vector3 = (v[a] as Vector3).lerp(v[b], w)
			var put := []
			if on.has(a) and on.has(b):
				for ci in on[a]:
					if (on[b] as Dictionary).has(ci):
						var ta: float = on[a][ci]
						var tb: float = on[b][ci]
						if absf(ta - tb) > 0.5:
							if ta < tb:
								ta += 1.0
							else:
								tb += 1.0
						var tm := fposmod(lerpf(ta, tb, w), 1.0 + 1e-9)
						var id := int(chains[ci]["id"])
						if now.has(id):
							q = at(now[id], tm)
						put.append([ci, tm])
						break
			v.append(q)
			var nv := v.size() - 1
			on[nv] = {}
			for pf in put:
				fv.append([nv, pf[0], pf[1]])
				on[nv][pf[0]] = pf[1]
			splits.append([a, b, w, nv])   # (the face beyond split through it: no T-junction there)
			return nv
		var at_side := func(pts: Array, fs: PackedFloat32Array, f: float) -> Vector3:
			var m := 1
			while m < fs.size() - 1 and fs[m] < f:
				m += 1
			var w := (f - fs[m - 1]) / maxf(fs[m] - fs[m - 1], 1e-12)
			return (v[pts[m - 1]] as Vector3).lerp(v[pts[m]], clampf(w, 0.0, 1.0))
		var rows := maxi(1, ceili(maxf(float(slen[(k0 + 1) % 4]), float(slen[(k0 + 3) % 4])) / L))
		var P00: Vector3 = v[A[0]]
		var P10: Vector3 = v[A[A.size() - 1]]
		var P01: Vector3 = v[B[0]]
		var P11: Vector3 = v[B[B.size() - 1]]
		var cols := []   # [vertices from A to B, their shares]
		for ci in F.size():
			var f: float = F[ci]
			if ci == 0:
				cols.append([Lft.duplicate(), fl])
				continue
			if ci == F.size() - 1:
				cols.append([Rgt.duplicate(), fr])
				continue
			var a_i: int = rail_pt.call(A, fa, f)
			var b_i: int = rail_pt.call(B, fb, f)
			var vs := [a_i]
			var hs := PackedFloat32Array([0.0])
			for r in range(1, rows):
				var s := float(r) / rows
				var pa: Vector3 = v[a_i]
				var pb: Vector3 = v[b_i]
				var lp: Vector3 = at_side.call(Lft, fl, s)
				var rp: Vector3 = at_side.call(Rgt, fr, s)
				var q := pa * (1.0 - s) + pb * s + lp * (1.0 - f) + rp * f \
					- (P00 * (1.0 - f) * (1.0 - s) + P10 * f * (1.0 - s) + P01 * (1.0 - f) * s + P11 * f * s)
				v.append(q)
				vs.append(v.size() - 1)
				hs.append(s)
			vs.append(b_i)
			hs.append(1.0)
			cols.append([vs, hs])
		# zipped column to column
		var ref := Vector3.ZERO
		for ti in g:
			var tr: Array = t[ti]
			ref += ((v[tr[2]] as Vector3) - v[tr[0]]).cross((v[tr[1]] as Vector3) - v[tr[0]])
		var tris := []
		for ci in cols.size() - 1:
			var Av: Array = cols[ci][0]
			var Ah: PackedFloat32Array = cols[ci][1]
			var Bv: Array = cols[ci + 1][0]
			var Bh: PackedFloat32Array = cols[ci + 1][1]
			var ia := 0
			var ib := 0
			while ia < Av.size() - 1 or ib < Bv.size() - 1:
				if ia < Av.size() - 1 and ib < Bv.size() - 1 and absf(Ah[ia + 1] - Bh[ib + 1]) < 1e-4:
					tris.append([Av[ia], Bv[ib], Bv[ib + 1]])
					tris.append([Av[ia], Bv[ib + 1], Av[ia + 1]])
					ia += 1
					ib += 1
				elif ib < Bv.size() - 1 and (ia >= Av.size() - 1 or Bh[ib + 1] < Ah[ia + 1]):
					tris.append([Av[ia], Bv[ib], Bv[ib + 1]])
					ib += 1
				else:
					tris.append([Av[ia], Bv[ib], Av[ia + 1]])
					ia += 1
		var ok := true
		var outs := []
		for tr in tris:
			if tr[0] == tr[1] or tr[1] == tr[2] or tr[0] == tr[2]:
				continue
			var n: Vector3 = ((v[tr[2]] as Vector3) - v[tr[0]]).cross((v[tr[1]] as Vector3) - v[tr[0]])
			if n.length() < 1e-14:
				continue
			outs.append(tr if n.dot(ref) >= 0.0 else [tr[0], tr[2], tr[1]])
		if outs.is_empty() or not ok:
			continue
		# (the grid looked over: folded inside - two of its triangles meeting at more than 100 degrees, or one
		# facing against the face it replaces - and the face keeps its triangles; a thin piece's face can be
		# one no four-sided grid fits)
		var folded := false
		var nrm := []
		var by_e2 := {}
		for oi in outs.size():
			var tr2: Array = outs[oi]
			var n2: Vector3 = ((v[tr2[2]] as Vector3) - v[tr2[0]]).cross((v[tr2[1]] as Vector3) - v[tr2[0]])
			nrm.append(n2.normalized())
			if ref.length_squared() > 0.0 and n2.normalized().dot(ref.normalized()) < -0.2:
				folded = true
			for j in 3:
				var e2 := _pk(int(tr2[j]), int(tr2[(j + 1) % 3]))
				if not by_e2.has(e2):
					by_e2[e2] = []
				by_e2[e2].append(oi)
		if not folded:
			for e2 in by_e2:
				var ts2: Array = by_e2[e2]
				if ts2.size() == 2 and (nrm[ts2[0]] as Vector3).dot(nrm[ts2[1]]) < -0.17:
					folded = true
					break
		if folded:
			continue
		for ti in g:
			drop[ti] = true
		add.append_array(outs)
	if drop.is_empty() and splits.is_empty():
		return false
	var keep := []
	for ti in nt:
		if not drop.has(ti):
			keep.append(t[ti])
	t.clear()
	t.append_array(keep)
	t.append_array(add)
	_split_through(t, splits)
	return true


## Triangles `t` split through the points put on their sides (`splits`: [a, b, share from a, point]) - a
## triangle with a side a-b that has points on it made a fan through them; again till none has. The mesh
## stays joined where a rebuilt face added points along a side it shares (no T-junctions, no seams to close).
static func _split_through(t: Array, splits: Array) -> void:
	if splits.is_empty():
		return
	var on_edge := {}   # "lo|hi" -> [[share from lo, point]...] sorted
	for sp in splits:
		var a := int(sp[0])
		var b := int(sp[1])
		var w := float(sp[2])
		var k := _pk(a, b)
		if not on_edge.has(k):
			on_edge[k] = []
		on_edge[k].append([w if a < b else 1.0 - w, int(sp[3])])
	for k in on_edge.keys():
		(on_edge[k] as Array).sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	# (every stretch between two of a side's points knows the points between them: two faces rebuilt either
	# side of it each put their own points on it - each one's sides split through the other's)
	for k in on_edge.keys():
		var ab := _unpk(k)
		var row := [[0.0, ab[0]]] + (on_edge[k] as Array) + [[1.0, ab[1]]]
		for x in row.size():
			for y in range(x + 2, row.size()):
				var kk := _pk(int(row[x][1]), int(row[y][1]))
				if kk == k or on_edge.has(kk):
					continue
				var lo_first: bool = int(row[x][1]) < int(row[y][1])
				var inner := []
				for z in range(x + 1, y):
					var f := (float(row[z][0]) - float(row[x][0])) / maxf(float(row[y][0]) - float(row[x][0]), 1e-12)
					inner.append([f if lo_first else 1.0 - f, int(row[z][1])])
				inner.sort_custom(func(p1, p2): return float(p1[0]) < float(p2[0]))
				on_edge[kk] = inner
	var i := 0
	var guard := 0
	while i < t.size() and guard < 200000:
		guard += 1
		var tr: Array = t[i]
		var done := false
		for j in 3:
			var a := int(tr[j])
			var b := int(tr[(j + 1) % 3])
			var c := int(tr[(j + 2) % 3])
			var k := _pk(a, b)
			if not on_edge.has(k):
				continue
			var pts: Array = on_edge[k]
			var mids := []
			for e in pts:
				if int(e[1]) != a and int(e[1]) != b and int(e[1]) != c:
					mids.append(int(e[1]))
			if mids.is_empty():
				continue
			if a > b:
				mids.reverse()   # (from a to b)
			var chain := [a] + mids + [b]
			var fan := []
			for m in chain.size() - 1:
				fan.append([chain[m], chain[m + 1], c])
			t[i] = fan[0]
			for m in range(1, fan.size()):
				t.append(fan[m])
			done = true
			break
		if not done:
			i += 1


## (settling) The columns of the walls made straight again after an edit: each point of a reshaped edge
## (`moved`: chain ids) that ends a wall's column (one rising along `up`, however it leans) slides along its
## curve to the place nearest the column's other end (two columns - above and below: between them),
## kept in order between
## its edge's corners; the points up each column follow its ends (keeping how far they were off it - a
## side edge's bend). `pv` the points now, `fv` the edge points ([vertex, chain, place]), `bw` the move's
## set-up (its faces' columns). Changes `pv` and `fv`.
static func straighten_columns(pv: PackedVector3Array, fv: Array, chains: Array, now: Dictionary, moved: Dictionary, bw: Dictionary, up: Vector3, t := PackedInt32Array()) -> void:
	if up == Vector3.ZERO:
		return
	up = up.normalized()
	var on := {}   # vertex -> [fv indices]
	for k in fv.size():
		var vi := int(fv[k][0])
		if not on.has(vi):
			on[vi] = []
		on[vi].append(k)
	# each column's two ends (edge points), standing along `up`
	var partner := {}
	var cols_in := []   # [inner vertex, lo, hi, w_lo, w_hi]
	for f: Dictionary in bw.get("faces", []):
		var cols: Dictionary = f.get("cols", {})
		for vi in cols:
			if on.has(vi):
				continue
			var ce: Array = cols[vi]
			var ends: PackedInt32Array = ce[0]
			if ends.size() != 2:
				continue
			var lo := ends[0]
			var hi := ends[1]
			var d := pv[hi] - pv[lo]
			if d.length() < 1e-9 or absf(d.normalized().dot(up)) < 0.3:
				continue   # (a flat face's column, across it - not a wall's)
			cols_in.append([vi, lo, hi, float(ce[1][0]), float(ce[1][1])])
			for pr in [[lo, hi], [hi, lo]]:
				if not partner.has(pr[0]):
					partner[pr[0]] = {}
				partner[pr[0]][pr[1]] = true
	# (and a strip too short for points between its edges: its triangles' sides rising from one edge's
	# point straight to another edge's)
	var chains_of := {}
	for e in fv:
		if not chains_of.has(int(e[0])):
			chains_of[int(e[0])] = {}
		chains_of[int(e[0])][int(e[1])] = true
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := t[i + j]
			var b := t[i + (j + 1) % 3]
			if not chains_of.has(a) or not chains_of.has(b):
				continue
			var share := false
			for ci in chains_of[a]:
				if (chains_of[b] as Dictionary).has(ci):
					share = true
			if share:
				continue
			var d := pv[b] - pv[a]
			if d.length() < 1e-9 or absf(d.normalized().dot(up)) < 0.3:
				continue
			for pr in [[a, b], [b, a]]:
				if not partner.has(pr[0]):
					partner[pr[0]] = {}
				partner[pr[0]][pr[1]] = true
	var old := pv.duplicate()
	# per moved chain: its points in order; corners (on two chains or more) and ends anchored
	var by_chain := {}
	for k in fv.size():
		var ci := int(fv[k][1])
		if not by_chain.has(ci):
			by_chain[ci] = []
		by_chain[ci].append(k)
	for ci in by_chain:
		var id := int(chains[ci]["id"])
		if not moved.has(id) or not now.has(id):
			continue
		var c: Dictionary = now[id]
		var s := CT.sample(c)
		var closed := bool(chains[ci].get("closed", false))
		if closed:
			s.append(s[0])
		if s.size() < 2:
			continue
		# (the curve finely: places and points)
		var fine := PackedVector3Array()
		var ft := PackedFloat32Array()
		var lens := PackedFloat32Array([0.0])
		for i in range(1, s.size()):
			lens.append(lens[i - 1] + s[i - 1].distance_to(s[i]))
		var total := maxf(lens[lens.size() - 1], 1e-9)
		for i in range(1, s.size()):
			for k2 in 8:
				var w := float(k2) / 8.0
				fine.append(s[i - 1].lerp(s[i], w))
				ft.append((lens[i - 1] + (lens[i] - lens[i - 1]) * w) / total)
		fine.append(s[s.size() - 1])
		ft.append(1.0)
		var ks: Array = by_chain[ci]
		ks.sort_custom(func(a, b): return float(fv[a][2]) < float(fv[b][2]))
		var want := PackedFloat32Array()
		var anchor := PackedByteArray()
		for j in ks.size():
			var k: int = ks[j]
			var vi := int(fv[k][0])
			var t0 := float(fv[k][2])
			var is_anchor := (on[vi] as Array).size() > 1 or (not closed and (j == 0 or j == ks.size() - 1)) or not partner.has(vi)
			anchor.append(1 if is_anchor else 0)
			if is_anchor:
				want.append(t0)
				continue
			# straight across from its partners: the nearest place on its curve to them (a slanted wall's
			# columns run square across it, not plumb)
			var tgt := Vector3.ZERO
			var np := 0
			for o in partner[vi]:
				if on.has(o) and (on[o] as Array).size() > 1:
					continue   # (a corner: many columns end at it - not one to line up with)
				tgt += old[o]
				np += 1
			if np == 0:
				want.append(t0)
				anchor[anchor.size() - 1] = 1
				continue
			tgt /= np
			var best := t0
			var bd := INF
			for i in fine.size():
				var dd: float = fine[i].distance_squared_to(tgt)
				if dd < bd:
					bd = dd
					best = ft[i]
			want.append(best)
		# kept in order between the anchors (a small gap between neighbours)
		var gap := 0.002
		var j := 0
		while j < ks.size():
			if anchor[j] == 1:
				j += 1
				continue
			var a := j - 1
			var b := j
			while b < ks.size() and anchor[b] == 0:
				b += 1
			var lo_t := want[a] if a >= 0 else 0.0
			var hi_t := want[b] if b < ks.size() else 1.0
			if hi_t < lo_t:
				hi_t += 1.0   # (round a loop's start)
			var n_run := b - j
			# (never bunched: each at least half an even share from the next - forward, then back)
			var g2 := maxf(gap, 0.5 * (hi_t - lo_t) / float(n_run + 1))
			var prev := lo_t
			for m in range(j, b):
				var tw := want[m]
				if tw < lo_t - 1e-9 and hi_t > 1.0:
					tw += 1.0
				tw = maxf(tw, prev + g2)
				want[m] = tw
				prev = tw
			var nxt_t := hi_t
			for m in range(b - 1, j - 1, -1):
				want[m] = minf(want[m], nxt_t - g2)
				nxt_t = want[m]
			j = b
		for m in ks.size():
			if anchor[m] == 1:
				continue
			var k: int = ks[m]
			var tm := fposmod(want[m], 1.0 + 1e-9)
			fv[k][2] = tm
			pv[int(fv[k][0])] = at(c, tm)
	# the points up each column: on the line between its ends (where an end moved - straight again)
	for e in cols_in:
		var vi: int = e[0]
		var lo: int = e[1]
		var hi: int = e[2]
		if pv[lo] == old[lo] and pv[hi] == old[hi]:
			continue
		pv[vi] = pv[lo] * float(e[3]) + pv[hi] * float(e[4])


## (settling) Slivers cleared: points closer than `collapse` to a neighbour merged into it (an edge or
## corner point kept over an inner one, a curve's point only into one on the same curves - nothing
## turned over), then thin triangles lying flat beside a neighbour turned to their best (edge flips,
## never across the solid's edges - `feat` taken afresh after the merges). {t, fv}.
static func tidy_mesh(v: PackedVector3Array, t_in: PackedInt32Array, fv_in: Array, chains: Array, now: Dictionary, collapse: float, ci_moved := {}, fair_rounds := 0) -> Dictionary:
	var t := t_in.duplicate()
	var fv := fv_in.duplicate(true)
	var on := {}
	for e in fv:
		if not on.has(int(e[0])):
			on[int(e[0])] = {}
		on[int(e[0])][int(e[1])] = true
	var tri_n := func(tt: PackedInt32Array, i: int) -> Vector3:
		return (v[tt[i + 2]] - v[tt[i]]).cross(v[tt[i + 1]] - v[tt[i]])
	# 1. merges
	for round_ in 4:
		var vt := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				if not vt.has(t[i + j]):
					vt[t[i + j]] = []
				vt[t[i + j]].append(i)
		var gone := {}
		var into := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				var a := t[i + j]
				var b := t[i + (j + 1) % 3]
				if gone.has(a) or gone.has(b) or into.has(a) or into.has(b) or a == b:
					continue
				if v[a].distance_to(v[b]) >= collapse:
					continue
				# (which one stays)
				var keep := a
				var drop := b
				var ca: Dictionary = on.get(a, {})
				var cb: Dictionary = on.get(b, {})
				var sub_ab := true
				for ci in cb:
					if not ca.has(ci):
						sub_ab = false
				var sub_ba := true
				for ci in ca:
					if not cb.has(ci):
						sub_ba = false
				if sub_ab:
					keep = a
					drop = b
				elif sub_ba:
					keep = b
					drop = a
				else:
					continue
				# (the mesh kept whole: the only points both have as neighbours the far corners of the two
				# triangles on their edge - else merging them would pinch it, an edge with three triangles)
				var ok := true
				var nk := {}
				var nd := {}
				var opp := {}
				for ti in vt[keep]:
					for k in 3:
						nk[t[ti + k]] = true
				for ti in vt[drop]:
					var has_k := false
					for k in 3:
						nd[t[ti + k]] = true
						if t[ti + k] == keep:
							has_k = true
					if has_k:
						for k in 3:
							if t[ti + k] != keep and t[ti + k] != drop:
								opp[t[ti + k]] = true
				for x in nd:
					if x != keep and x != drop and nk.has(x) and not opp.has(x):
						ok = false
						break
				if not ok:
					continue
				# (nothing turned over: every triangle at `drop` not holding `keep` keeps its facing)
				for ti in vt[drop]:
					var tr := PackedInt32Array([t[ti], t[ti + 1], t[ti + 2]])
					if keep in tr:
						continue
					var n0: Vector3 = tri_n.call(t, ti)
					var tt := t.duplicate()
					for k in 3:
						if tt[ti + k] == drop:
							tt[ti + k] = keep
					var n1: Vector3 = tri_n.call(tt, ti)
					if n0.length() > 1e-14 and n1.dot(n0) <= 0.0:
						ok = false
						break
				if not ok:
					continue
				gone[drop] = true
				into[keep] = true
				for ti in vt[drop]:
					for k in 3:
						if t[ti + k] == drop:
							t[ti + k] = keep
		if gone.is_empty():
			break
		var nt := PackedInt32Array()
		for i in range(0, t.size(), 3):
			if t[i] != t[i + 1] and t[i + 1] != t[i + 2] and t[i] != t[i + 2]:
				nt.append_array(PackedInt32Array([t[i], t[i + 1], t[i + 2]]))
		t = nt
		var nfv := []
		for e in fv:
			if not gone.has(int(e[0])):
				nfv.append(e)
		fv = nfv
	# 2. flips of slivers (within a face: nearly flat together, not across the solid's edges - those
	# joining neighbouring points of one curve; a chord skipping a point is no edge of the solid)
	var feat := {}
	var by_c := {}
	for e in fv:
		var ci := int(e[1])
		if not by_c.has(ci):
			by_c[ci] = []
		by_c[ci].append([float(e[2]), int(e[0])])
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for i in lst.size() - 1:
			feat[_pk(int(lst[i][1]), int(lst[i + 1][1]))] = true
		if ci < chains.size() and bool(chains[ci].get("closed", false)) and lst.size() > 2:
			feat[_pk(int(lst[lst.size() - 1][1]), int(lst[0][1]))] = true
	var by_n := {}
	for i in range(0, t.size(), 3):
		var nn: Vector3 = tri_n.call(t, i)
		for j in 3:
			var k := _pk(t[i + j], t[i + (j + 1) % 3])
			if not by_n.has(k):
				by_n[k] = []
			by_n[k].append(nn)
	for k in by_n:
		var ns: Array = by_n[k]
		if ns.size() == 2 and (ns[0] as Vector3).length() > 1e-14 and (ns[1] as Vector3).length() > 1e-14 and (ns[0] as Vector3).normalized().dot((ns[1] as Vector3).normalized()) < 0.7:
			feat[k] = true
	var min_ang := func(p0: Vector3, p1: Vector3, p2: Vector3) -> float:
		return minf((p1 - p0).angle_to(p2 - p0), minf((p0 - p1).angle_to(p2 - p1), (p0 - p2).angle_to(p1 - p2)))
	for round_ in 6:
		var by_e := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				var k := _pk(t[i + j], t[i + (j + 1) % 3])
				if not by_e.has(k):
					by_e[k] = []
				by_e[k].append(i)
		var flipped := 0
		var touched := {}
		var made := {}
		for k in by_e:
			var ts: Array = by_e[k]
			if ts.size() != 2 or feat.has(k) or touched.has(ts[0]) or touched.has(ts[1]):
				continue
			var i0: int = ts[0]
			var i1: int = ts[1]
			var ab := _unpk(str(k))
			# (i0 as a -> b, its third c; i1's third d)
			var a := -1
			var b := -1
			var c := -1
			for j in 3:
				var x := t[i0 + j]
				var y := t[i0 + (j + 1) % 3]
				if (x == ab[0] and y == ab[1]) or (x == ab[1] and y == ab[0]):
					a = x
					b = y
					c = t[i0 + (j + 2) % 3]
			var d := -1
			for j in 3:
				if t[i1 + j] != a and t[i1 + j] != b:
					d = t[i1 + j]
			if c < 0 or d < 0 or c == d or by_e.has(_pk(c, d)) or made.has(_pk(c, d)):
				continue   # (c - d an edge already: turning onto it would give it three triangles)
			var n0: Vector3 = tri_n.call(t, i0)
			var n1: Vector3 = tri_n.call(t, i1)
			if n0.length() < 1e-14 or n1.length() < 1e-14 or n0.normalized().dot(n1.normalized()) < 0.9:
				continue
			var cur := minf(min_ang.call(v[a], v[b], v[c]), min_ang.call(v[b], v[a], v[d]))
			if cur > deg_to_rad(15.0):
				continue   # (no sliver here: a quad's two halves stay)
			var nw := minf(min_ang.call(v[a], v[d], v[c]), min_ang.call(v[d], v[b], v[c]))
			if nw <= cur * 1.2:
				continue
			# (the new pair c, a, d and c, d, b in i0's turn)
			var t0 := PackedInt32Array([a, d, c])
			var t1 := PackedInt32Array([d, b, c])
			var m0 := (v[t0[2]] - v[t0[0]]).cross(v[t0[1]] - v[t0[0]])
			var m1 := (v[t1[2]] - v[t1[0]]).cross(v[t1[1]] - v[t1[0]])
			if m0.dot(n0) <= 0.0 or m1.dot(n0) <= 0.0:
				continue
			for j in 3:
				t[i0 + j] = t0[j]
				t[i1 + j] = t1[j]
			touched[i0] = true
			made[_pk(c, d)] = true
			touched[i1] = true
			flipped += 1
		if flipped == 0:
			break
	# (lone triangles side by side made quads where turning their shared side does it)
	t = pair_quads(v, t, feat)
	# (points lying on the solid's edges but not counted as theirs - a column's end on a rim: held too)
	var held := _on_edges(v, t, fv, maxf(collapse * 0.25, 1e-4))
	# 3. the faces at reshaped edges faired: their inner points eased towards the middle of their
	# neighbours (each face shaped by its edges - no crease left where a bent edge pulled its first row)
	if fair_rounds > 0:
		var fx := held.duplicate()
		for e in fv:
			fx[int(e[0])] = true
		var nbr := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				var x := t[i + j]
				if not nbr.has(x):
					nbr[x] = {}
				nbr[x][t[i + (j + 1) % 3]] = true
				nbr[x][t[i + (j + 2) % 3]] = true
		var near_moved := {}
		for e in fv:
			if ci_moved.has(int(e[1])):
				near_moved[int(e[0])] = 0
		# (the points within a few rings of a reshaped edge)
		var ring := near_moved.keys()
		for r in 12:
			var nxt := []
			for x in ring:
				for o in nbr.get(x, {}):
					if not near_moved.has(o):
						near_moved[o] = r + 1
						nxt.append(o)
			ring = nxt
		var vtf := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				if not vtf.has(t[i + j]):
					vtf[t[i + j]] = []
				vtf[t[i + j]].append(i)
		# (each triangle's way out: as it faces - unless it's turned over against the triangles round its
		# corners: then theirs, so it's eased back; never one turned further round)
		var ring_n := {}
		for i in range(0, t.size(), 3):
			var nn := _tn(v, t, i)
			for j in 3:
				ring_n[t[i + j]] = (ring_n.get(t[i + j], Vector3.ZERO) as Vector3) + nn
		var ref_n := {}
		for i in range(0, t.size(), 3):
			var own := _tn(v, t, i).normalized()
			var rn: Vector3 = ((ring_n[t[i]] as Vector3) + ring_n[t[i + 1]] + ring_n[t[i + 2]]).normalized()
			ref_n[i] = own if own.dot(rn) > 0.0 else rn
		for it in fair_rounds:
			var vp := v.duplicate()   # (each round from the last one's points)
			for x in near_moved:
				if fx.has(x) or not nbr.has(x):
					continue
				var avg := Vector3.ZERO
				for o in nbr[x]:
					avg += vp[o]
				avg /= (nbr[x] as Dictionary).size()
				var was := v[x]
				var olds := []
				for i in vtf[x]:
					var n0 := _tn(v, t, i)
					olds.append(n0.normalized().dot(ref_n[i]) if n0.length() > 1e-14 else -1.0)
				v[x] = was.lerp(avg, 0.5)
				var k := 0
				for i in vtf[x]:
					var nn: Vector3 = _tn(v, t, i)
					if nn.length() < 1e-14 or nn.normalized().dot(ref_n[i]) < minf(0.85, float(olds[k])):
						v[x] = was   # (it would turn a triangle over - or further round from its way out: stays)
						break
					k += 1
	# 4. crumples smoothed: inner points where the triangles round them face very different ways (a face
	# pinched into a sharp corner) eased to the middle of their neighbours, a few rounds, never folding
	var fixed := held.duplicate()
	for e in fv:
		fixed[int(e[0])] = true
	var vt := {}
	var nb := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var x := t[i + j]
			if not vt.has(x):
				vt[x] = []
				nb[x] = {}
			vt[x].append(i)
			nb[x][t[i + (j + 1) % 3]] = true
			nb[x][t[i + (j + 2) % 3]] = true
	var c30 := cos(deg_to_rad(30.0))
	for round_ in 12:
		var moved_n := 0
		for x in vt:
			if fixed.has(x):
				continue
			var ns := []
			for i in vt[x]:
				var nn: Vector3 = _tn(v, t, i)
				if nn.length() > 1e-14:
					ns.append(nn.normalized())
			var crumpled := false
			for a in ns.size():
				for b in range(a + 1, ns.size()):
					if (ns[a] as Vector3).dot(ns[b]) < c30:
						crumpled = true
			if not crumpled:
				continue
			var avg := Vector3.ZERO
			for o in nb[x]:
				avg += v[o]
			avg /= (nb[x] as Dictionary).size()
			var was := v[x]
			var olds := []
			for i in vt[x]:
				olds.append(_tn(v, t, i))
			v[x] = was.lerp(avg, 0.7)
			var k := 0
			for i in vt[x]:
				if (_tn(v, t, i) as Vector3).dot(olds[k]) <= 0.0:
					v[x] = was
					break
				k += 1
			if v[x] != was:
				moved_n += 1
		if moved_n == 0:
			break
	return {"t": t, "fv": fv, "v": v}


## How many edges of triangles `t` ([[a, b, c]...]) have more than two triangles.
static func _crowded_edges(t: Array) -> int:
	var cnt := {}
	for tr in t:
		for j in 3:
			var k := _pk(int(tr[j]), int(tr[(j + 1) % 3]))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var n := 0
	for k in cnt:
		if int(cnt[k]) > 2:
			n += 1
	return n


## Triangle `i`'s (its first index in `t`) facing, as long as twice its area.
static func _tn(v: PackedVector3Array, t: PackedInt32Array, i: int) -> Vector3:
	return (v[t[i + 2]] - v[t[i]]).cross(v[t[i + 1]] - v[t[i]])


## The mesh's points (used by `t`) lying within `tol` of a segment between neighbouring points of one
## of the solid's edges (fv) - on an edge without being one of its points. {vertex: true}.
static func _on_edges(v: PackedVector3Array, t: PackedInt32Array, fv: Array, tol: float) -> Dictionary:
	var by_c := {}
	var isfv := {}
	for e in fv:
		isfv[int(e[0])] = true
		var ci := int(e[1])
		if not by_c.has(ci):
			by_c[ci] = []
		by_c[ci].append([float(e[2]), int(e[0])])
	var segs := []
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for i in lst.size() - 1:
			segs.append([v[int(lst[i][1])], v[int(lst[i + 1][1])]])
	var cell := 0.05
	var grid := {}
	for si in segs.size():
		var a: Vector3 = segs[si][0]
		var b: Vector3 = segs[si][1]
		var lo := Vector3i((a.min(b) / cell).floor())
		var hi := Vector3i((a.max(b) / cell).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var k := Vector3i(x, y, z)
					if not grid.has(k):
						grid[k] = []
					grid[k].append(si)
	var used := {}
	for i in t:
		used[i] = true
	var out := {}
	for x in used:
		if isfv.has(x):
			continue
		var k := Vector3i((v[x] / cell).floor())
		for si in grid.get(k, []):
			if Geometry3D.get_closest_point_to_segment(v[x], segs[si][0], segs[si][1]).distance_to(v[x]) < tol:
				out[x] = true
				break
	return out


## A baked solid's mesh settled after an edit (when the drag's let go) - the shape as it's now, made fine
## enough again, quads kept: where it bends more than `max_deg` between neighbouring quads, those quads
## split, each into four quads (each triangle into four), the new points on the curved surface (edge
## points on their curves), the triangles beyond the patch fanned to meet it - not below `min_len`.
## (Its points aren't moved: the smooth solve already spreads them evenly, each column straight.) `v` - the points
## where they are now, `t` the triangles, `fv` - [vertex, chain, place along it], `now`: chain id -> its
## curve now. {v, t, fv}.
static func settle(v_in: PackedVector3Array, t_in: PackedInt32Array, fv_in: Array, chains: Array, now: Dictionary, max_deg := 20.0, min_len := 0.01, moved := {}, L := 0.05) -> Dictionary:
	var v := []
	for q in v_in:
		v.append(q)
	var t := []
	for i in range(0, t_in.size(), 3):
		t.append([t_in[i], t_in[i + 1], t_in[i + 2]])
	var fv := fv_in.duplicate(true)
	# the faces at the edges reshaped: each made again as a grid for its shape now - kept only when the
	# mesh stays closed (else settled as it is)
	if not moved.is_empty():
		var mci := {}
		for ci in chains.size():
			if moved.has(int(chains[ci]["id"])):
				mci[ci] = true
		var v2 := v.duplicate()
		var t2 := t.duplicate(true)
		var fv2 := fv.duplicate(true)
		if _rebuild_faces(v2, t2, fv2, chains, now, _feat_now(v, t, fv, chains, now), mci, L):
			var vp2 := PackedVector3Array()
			for q in v2:
				vp2.append(q)
			var tp2 := PackedInt32Array()
			for tr in t2:
				tp2.append_array(PackedInt32Array(tr))
			var cs2 := close_seams(vp2, tp2, fv2)
			if not cs2.is_empty():
				tp2 = cs2["t"]
			if _open_edges(tp2) == 0:
				v = v2
				fv = cs2["fv"] if not cs2.is_empty() else fv2
				t = []
				for i in range(0, tp2.size(), 3):
					t.append([tp2[i], tp2[i + 1], tp2[i + 2]])
	# edges straying from their curves (a reshaped curve stretched its points apart): split through, a
	# loop cut across each - quads kept - till every edge segment lies within `fit` of its curve
	if not moved.is_empty():
		for level in 3:
			var seeds := _off_curve(v, t, fv, chains, now, moved, maxf(L * 0.04, 0.0015))
			if seeds.is_empty():
				break
			var keep := [v.duplicate(), t.duplicate(true), fv.duplicate(true)]
			var many0 := _crowded_edges(t)
			_split_bent(v, t, fv, chains, now, _feat_now(v, t, fv, chains, now), 180.0, 0.0, seeds)
			if _crowded_edges(t) > many0:
				# (a cut that left an edge with three triangles: undone - the mesh kept whole)
				v.assign(keep[0])
				t.assign(keep[1])
				fv.assign(keep[2])
				break
	# faces bending too much: split, quads into quads
	for level in (1 if max_deg < 179.0 else 0):
		var feat := _feat_now(v, t, fv, chains, now)
		var r := _split_bent(v, t, fv, chains, now, feat, max_deg, min_len)
		if not r:
			break
	# (edges two sides split differently: closed)
	var tp := PackedInt32Array()
	for tr in t:
		tp.append_array(PackedInt32Array(tr))
	var vp := PackedVector3Array()
	for q in v:
		vp.append(q)
	var cs := close_seams(vp, tp, fv)
	if not cs.is_empty():
		tp = cs["t"]
		fv = cs["fv"]
	# slivers cleared - near-coincident points merged, thin triangles turned (kept only if still closed)
	var cim := {}
	for ci in chains.size():
		if moved.has(int(chains[ci]["id"])):
			cim[ci] = true
	var td := tidy_mesh(vp.duplicate(), tp, fv, chains, now, L * 0.2, cim, 20)
	if _open_edges(td["t"]) == _open_edges(tp):
		tp = td["t"]
		fv = td["fv"]
		vp = td["v"]
	return {"v": vp, "t": tp, "fv": fv}


## The mesh's triangles all turned one way - outwards: from the triangle furthest out along X (facing
## +X), each neighbour turned to run their shared edge the other way round, across the whole closed
## mesh (each piece of it on its own). A copy of `t`.
static func orient(v: PackedVector3Array, t_in: PackedInt32Array) -> PackedInt32Array:
	var t := t_in.duplicate()
	var nt := t.size() / 3
	var by_edge := {}
	for i in nt:
		for j in 3:
			var e := _pk(t[i * 3 + j], t[i * 3 + (j + 1) % 3])
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var done := PackedByteArray()
	done.resize(nt)
	var order := range(nt)
	order.sort_custom(func(a, b): return (v[t[a * 3]] + v[t[a * 3 + 1]] + v[t[a * 3 + 2]]).x > (v[t[b * 3]] + v[t[b * 3 + 1]] + v[t[b * 3 + 2]]).x)
	for seed in order:
		if done[seed] == 1:
			continue
		# (the seed - furthest out of what's left: facing out along X)
		var sn := (v[t[seed * 3 + 2]] - v[t[seed * 3]]).cross(v[t[seed * 3 + 1]] - v[t[seed * 3]])
		if sn.x < 0.0:
			var x := t[seed * 3 + 1]
			t[seed * 3 + 1] = t[seed * 3 + 2]
			t[seed * 3 + 2] = x
		done[seed] = 1
		var todo := [seed]
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				var nbs: Array = by_edge[_pk(a, b)]
				if nbs.size() != 2:
					continue   # (an edge with more than two: left as it is)
				for o in nbs:
					if o == ti or done[o] == 1:
						continue
					# (o must run b -> a)
					var runs_ab := false
					for k in 3:
						if t[o * 3 + k] == a and t[o * 3 + (k + 1) % 3] == b:
							runs_ab = true
					if runs_ab:
						var x := t[o * 3 + 1]
						t[o * 3 + 1] = t[o * 3 + 2]
						t[o * 3 + 2] = x
					done[o] = 1
					todo.append(o)
	return t


## Each triangle's face (flooded between the solid's edges `feat`) - for drawing a mesh as it is.
static func face_of(v: PackedVector3Array, t: PackedInt32Array, feat: Dictionary) -> PackedInt32Array:
	var nt := t.size() / 3
	var by_edge := {}
	for i in nt:
		for j in 3:
			var e := _pk(t[i * 3 + j], t[i * 3 + (j + 1) % 3])
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var face := PackedInt32Array()
	face.resize(nt)
	face.fill(-1)
	var nf := 0
	for t0 in nt:
		if face[t0] >= 0:
			continue
		var todo := [t0]
		face[t0] = nf
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			for j in 3:
				var e := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
				if feat.has(e):
					continue
				for o in by_edge[e]:
					if face[o] < 0:
						face[o] = nf
						todo.append(o)
		nf += 1
	return face


## How many edges of triangles `t` have a triangle on one side only (0: closed).
static func _open_edges(t: PackedInt32Array) -> int:
	var cnt := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var e := _pk(t[i + j], t[i + (j + 1) % 3])
			cnt[e] = int(cnt.get(e, 0)) + 1
	var n := 0
	for e in cnt:
		if int(cnt[e]) == 1:
			n += 1
	return n


## (settle) The mesh's edges along a reshaped curve whose middle strays more than `fit` from it: {key: true}.
static func _off_curve(v: Array, t: Array, fv: Array, chains: Array, now: Dictionary, moved: Dictionary, fit: float) -> Dictionary:
	var by_chain := {}
	for e in fv:
		var ci := int(e[1])
		if ci >= chains.size() or not moved.has(int(chains[ci]["id"])):
			continue
		if not by_chain.has(ci):
			by_chain[ci] = []
		by_chain[ci].append([float(e[2]), int(e[0])])
	var has_edge := {}
	for tr in t:
		for j in 3:
			has_edge[_pk(int(tr[j]), int(tr[(j + 1) % 3]))] = true
	var out := {}
	for ci in by_chain:
		var c: Dictionary = now.get(int(chains[ci]["id"]), {})
		if c.is_empty():
			continue
		var lst: Array = by_chain[ci]
		lst.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		var closed := bool(chains[ci].get("closed", false))
		var n := lst.size()
		for i in (n if closed else n - 1):
			var a: Array = lst[i]
			var b: Array = lst[(i + 1) % n]
			var ta := float(a[0])
			var tb := float(b[0])
			if tb < ta:
				tb += 1.0
			var k := _pk(int(a[1]), int(b[1]))
			if not has_edge.has(k) or int(a[1]) == int(b[1]):
				continue
			var mid := ((v[a[1]] as Vector3) + (v[b[1]] as Vector3)) * 0.5
			var on := at(c, fposmod((ta + tb) * 0.5, 1.0 + 1e-9))
			if mid.distance_to(on) > fit:
				out[k] = true
	return out


## The solid's edges in the mesh as it is now (feature_edges against the curves now).
static func _feat_now(v: Array, t: Array, fv: Array, chains: Array, now: Dictionary) -> Dictionary:
	var vp := PackedVector3Array()
	for q in v:
		vp.append(q)
	var tp := PackedInt32Array()
	for tr in t:
		tp.append_array(PackedInt32Array(tr))
	var old := {}
	for ci in chains.size():
		var id := int(chains[ci]["id"])
		if now.has(id):
			old[id] = now[id]
	return feature_edges(vp, tp, fv, chains, old)


## (settle) Where neighbouring quads bend more than `max_deg` across the edge between them: a loop cut
## along each of the two strips of quads running beside that edge - every quad in a strip split in two
## (four where two cuts cross), the cut carried from quad to quad through the edges it splits, across
## the solid's edges too, till it closes or meets a triangle (that one fanned from the new point). New
## points on the curved surface, on the curve where an edge of the solid's is cut. Not where the quads
## are already shorter than `min_len`. Changes `v`, `t`, `fv`; true - something was cut.
static func _split_bent(v: Array, t: Array, fv: Array, chains: Array, now: Dictionary, feat: Dictionary, max_deg: float, min_len: float, seeds := {}) -> bool:
	var nt := t.size()
	var by_edge := {}
	for i in nt:
		for j in 3:
			var e := _pk(int(t[i][j]), int(t[i][(j + 1) % 3]))
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var tn := []
	for i in nt:
		var tr: Array = t[i]
		tn.append(((v[tr[2]] as Vector3) - v[tr[0]]).cross((v[tr[1]] as Vector3) - v[tr[0]]))
	# quads: two triangles sharing each one's longest edge, nearly flat together - corners in their turn
	var quads := []   # [c0, c1, c2, c3]
	var quad_of := {}   # triangle -> quad
	var longest := []
	for i in nt:
		var tr: Array = t[i]
		var lk := ""
		var ll := -1.0
		for j in 3:
			var l := (v[tr[j]] as Vector3).distance_to(v[tr[(j + 1) % 3]])
			if l > ll:
				ll = l
				lk = _pk(int(tr[j]), int(tr[(j + 1) % 3]))
		longest.append(lk)
	for i in nt:
		if quad_of.has(i):
			continue
		var ts: Array = by_edge[longest[i]]
		if ts.size() != 2:
			continue
		var o: int = ts[0] if ts[1] == i else ts[1]
		if quad_of.has(o) or longest[o] != longest[i]:
			continue
		var n1: Vector3 = tn[i]
		var n2: Vector3 = tn[o]
		if n1.length() < 1e-14 or n2.length() < 1e-14 or n1.normalized().dot(n2.normalized()) < 0.85:
			continue
		var tr: Array = t[i]
		# i runs a -> b on the diagonal, its third c; o's third d: the quad a, d, b, c
		var a2: int = -1
		var b2: int = -1
		for j in 3:
			var x: int = tr[j]
			var y: int = tr[(j + 1) % 3]
			if _pk(x, y) == longest[i]:
				a2 = x
				b2 = y
		var c := -1
		for x in tr:
			if x != a2 and x != b2:
				c = x
		var d := -1
		for x in t[o]:
			if x != a2 and x != b2:
				d = x
		quads.append([a2, d, b2, c])
		quad_of[i] = quads.size() - 1
		quad_of[o] = quads.size() - 1
	var qn := []   # each quad's facing
	for q in quads:
		qn.append(((v[q[2]] as Vector3) - v[q[0]]).cross((v[q[3]] as Vector3) - v[q[1]]))
	var qside := {}   # quad side (edge key) -> [quad indices]
	for qi in quads.size():
		var q: Array = quads[qi]
		for j in 4:
			var e := _pk(int(q[j]), int(q[(j + 1) % 4]))
			if not qside.has(e):
				qside[e] = []
			qside[e].append(qi)
	# the cuts: for each bent side between two quads, the strips beside it - each quad cut across the
	# pair of its sides that meet that side
	var cos_max := cos(deg_to_rad(max_deg))
	var cut := {}   # quad -> {0: across sides 0 and 2, 1: across sides 1 and 3}
	var todo := []
	# (seeded: the edges given split - the cut runs through each, across its quads)
	for e in seeds:
		for qi in qside.get(e, []):
			var q: Array = quads[qi]
			for k in 4:
				if _pk(int(q[k]), int(q[(k + 1) % 4])) == str(e):
					todo.append([qi, k % 2])
	for e in (qside if seeds.is_empty() else {}):
		var qs: Array = qside[e]
		if qs.size() != 2:
			continue
		var n1: Vector3 = qn[qs[0]]
		var n2: Vector3 = qn[qs[1]]
		if n1.length() < 1e-14 or n2.length() < 1e-14:
			continue
		var dd := n1.normalized().dot(n2.normalized())
		if dd >= cos_max or dd < -0.2:
			continue
		var ab := _unpk(str(e))
		if (v[ab[0]] as Vector3).distance_to(v[ab[1]]) < min_len * 2.0:
			continue
		for qi in qs:
			var q: Array = quads[qi]
			var j := 0
			for k in 4:
				if _pk(int(q[k]), int(q[(k + 1) % 4])) == str(e):
					j = k
			# (the side `e` is side j: the cut runs beside it, across sides j+1 and j+3)
			todo.append([qi, (j + 1) % 2])
	if todo.is_empty():
		return false
	var split_e := {}   # edge key -> true: gets a new point
	var guard := 0
	while not todo.is_empty() and guard < 20000:
		guard += 1
		var it: Array = todo.pop_back()
		var qi: int = it[0]
		var dirn: int = it[1]
		if not cut.has(qi):
			cut[qi] = {}
		if (cut[qi] as Dictionary).has(dirn):
			continue
		cut[qi][dirn] = true
		var q: Array = quads[qi]
		# its sides dirn and dirn+2 split - the cut goes on through each into the quad beyond
		for k in [dirn, dirn + 2]:
			var e := _pk(int(q[k]), int(q[(k + 1) % 4]))
			split_e[e] = true
			for o in qside.get(e, []):
				if o == qi:
					continue
				var oq: Array = quads[o]
				for kk in 4:
					if _pk(int(oq[kk]), int(oq[(kk + 1) % 4])) == e:
						todo.append([o, kk % 2])
	if seeds.is_empty() and quads.size() > 0 and cut.size() > quads.size() / 2:
		return false   # (bends all over: creases, not curvature - left as it is)
	if not seeds.is_empty():
		# (a seed edge with no quad on it - beside a triangle: split all the same, its triangles fanned)
		for e in seeds:
			split_e[e] = true
	# smooth normals at the points of the quads cut (for points on the curved surface)
	var vn := {}
	for qi in cut:
		for x in quads[qi]:
			vn[x] = (vn.get(x, Vector3.ZERO) as Vector3) + (qn[qi] as Vector3)
	var on_chain := {}
	for e in fv:
		if not on_chain.has(int(e[0])):
			on_chain[int(e[0])] = {}
		on_chain[int(e[0])][int(e[1])] = float(e[2])
	var mids := {}
	for ek in split_e:
		var ab := _unpk(str(ek))
		var a: int = ab[0]
		var b: int = ab[1]
		var pa: Vector3 = v[a]
		var pb: Vector3 = v[b]
		var q := (pa + pb) * 0.5
		var put := []
		var shared := false
		if on_chain.has(a) and on_chain.has(b):
			for ci in on_chain[a]:
				if (on_chain[b] as Dictionary).has(ci):
					shared = true
		if shared:
			for ci in on_chain[a]:
				if not (on_chain[b] as Dictionary).has(ci):
					continue
				var ta: float = on_chain[a][ci]
				var tb: float = on_chain[b][ci]
				if absf(ta - tb) > 0.5:
					if ta < tb:
						ta += 1.0
					else:
						tb += 1.0
				var tm := fposmod((ta + tb) * 0.5, 1.0 + 1e-9)
				var id := int(chains[ci]["id"])
				if now.has(id):
					q = at(now[id], tm)
				put.append([ci, tm])
				break
		elif not feat.has(ek) and not on_chain.has(a) and not on_chain.has(b):
			# (inside a face, away from its edges: on the curved surface - by an edge, straight)
			var na: Vector3 = vn.get(a, Vector3.ZERO)
			var nb2: Vector3 = vn.get(b, Vector3.ZERO)
			if na.length() > 1e-14 and nb2.length() > 1e-14:
				na = na.normalized()
				nb2 = nb2.normalized()
				var nm := na + nb2
				if nm.length() > 1e-9:
					q += nm.normalized() * ((pb - pa).dot(na - nb2) / 8.0)
		v.append(q)
		mids[ek] = v.size() - 1
		for pf in put:
			fv.append([v.size() - 1, pf[0], pf[1]])
	# the new triangles
	var out := []
	var done_t := {}
	for qi in quads.size():
		var q: Array = quads[qi]
		var m := []
		for k in 4:
			m.append(mids.get(_pk(int(q[k]), int(q[(k + 1) % 4])), -1))
		var nsplit := 0
		for x in m:
			if x >= 0:
				nsplit += 1
		if nsplit == 0:
			continue
		var quads_new := []
		if m[0] >= 0 and m[2] >= 0 and m[1] >= 0 and m[3] >= 0:
			v.append(((v[m[0]] as Vector3) + v[m[1]] + v[m[2]] + v[m[3]]) * 0.25)
			var ctr := v.size() - 1
			quads_new = [[q[0], m[0], ctr, m[3]], [m[0], q[1], m[1], ctr], [ctr, m[1], q[2], m[2]], [m[3], ctr, m[2], q[3]]]
		elif m[0] >= 0 and m[2] >= 0 and m[1] < 0 and m[3] < 0:
			quads_new = [[q[0], m[0], m[2], q[3]], [m[0], q[1], q[2], m[2]]]
		elif m[1] >= 0 and m[3] >= 0 and m[0] < 0 and m[2] < 0:
			quads_new = [[q[0], q[1], m[1], m[3]], [m[3], m[1], q[2], q[3]]]
		else:
			continue   # (an odd split: its triangles fanned below)
		for sq in quads_new:
			out.append([sq[0], sq[1], sq[2]])
			out.append([sq[0], sq[2], sq[3]])
		# (this quad's two triangles replaced)
		for ti in by_edge[_pk(int(q[0]), int(q[2]))]:
			done_t[ti] = true
	# every other triangle: as it was, or fanned from the new points on its sides
	var keep := []
	for ti in nt:
		if done_t.has(ti):
			continue
		var tr: Array = t[ti]
		var ring := []
		for j in 3:
			ring.append(tr[j])
			var ek := _pk(int(tr[j]), int(tr[(j + 1) % 3]))
			if mids.has(ek):
				ring.append(mids[ek])
		if ring.size() == 3:
			keep.append(tr)
			continue
		var start := 0
		for j in ring.size():
			if not ring[j] in tr:
				start = j
				break
		for k in range(1, ring.size() - 1):
			keep.append([ring[start], ring[(start + k) % ring.size()], ring[(start + k + 1) % ring.size()]])
	t.clear()
	t.append_array(keep)
	t.append_array(out)
	return true


## Mesh points `pv` (moved from `v0`) with any triangle turned over (against how it faced in `v0`)
## untangled: the inner points (not in `fixed`) round each such triangle eased towards the middle of
## their neighbours till they all face right again (or a few rounds have gone). Changes `pv` in place
## (returns it).
static func untangle(pv: PackedVector3Array, v0: PackedVector3Array, t: PackedInt32Array, nb: Array, fixed: Dictionary) -> PackedVector3Array:
	var vt := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			if not vt.has(t[i + j]):
				vt[t[i + j]] = []
			vt[t[i + j]].append(i)
	for round_ in 30:
		var bad := {}
		for i in range(0, t.size(), 3):
			var n0 := (v0[t[i + 2]] - v0[t[i]]).cross(v0[t[i + 1]] - v0[t[i]])
			var n1 := (pv[t[i + 2]] - pv[t[i]]).cross(pv[t[i + 1]] - pv[t[i]])
			if n0.length_squared() > 1e-20 and n1.dot(n0) <= 0.0:
				for j in 3:
					var vi := t[i + j]
					if not fixed.has(vi):
						bad[vi] = true
					for o in nb[vi]:
						if not fixed.has(o):
							bad[o] = true   # (and the ring round it - room to move)
		if bad.is_empty():
			break
		for it in 4:
			for vi in bad:
				var n: PackedInt32Array = nb[vi]
				if n.is_empty():
					continue
				var s := Vector3.ZERO
				for o in n:
					s += pv[o]
				pv[vi] = pv[vi].lerp(s / n.size(), 0.6 if round_ < 10 else 1.0)
	return pv


## (after untangle) Triangles still turned over - a rim point slid past its neighbours - fixed by turning
## the edge they share with a neighbour of the same face, when both then face right. {t, face} - the
## triangles to draw and each one's face (`t` itself when nothing's turned).
static func flip_fix(pv: PackedVector3Array, v0: PackedVector3Array, t: PackedInt32Array, face: PackedInt32Array) -> Dictionary:
	var bad := []
	var nt := t.size() / 3
	var n0s := []
	for i in nt:
		var n0 := (v0[t[i * 3 + 2]] - v0[t[i * 3]]).cross(v0[t[i * 3 + 1]] - v0[t[i * 3]])
		n0s.append(n0)
		var n1 := (pv[t[i * 3 + 2]] - pv[t[i * 3]]).cross(pv[t[i * 3 + 1]] - pv[t[i * 3]])
		if n0.length_squared() > 1e-20 and n1.dot(n0) <= 0.0:
			bad.append(i)
	if bad.is_empty():
		return {"t": t, "face": face}
	var out := t.duplicate()
	var by_edge := {}
	for i in nt:
		for j in 3:
			var e := _pk(out[i * 3 + j], out[i * 3 + (j + 1) % 3])
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i)
	var faces := face.duplicate()
	for i in bad:
		for j in 3:
			var a := out[i * 3 + j]
			var b := out[i * 3 + (j + 1) % 3]
			var c := out[i * 3 + (j + 2) % 3]
			var other := -1
			for o in by_edge.get(_pk(a, b), []):
				if o != i and (faces.is_empty() or faces[o] == faces[i]):
					other = o
			if other < 0:
				continue
			var d := -1
			for k in 3:
				var x := out[other * 3 + k]
				if x != a and x != b:
					d = x
			if d < 0:
				continue
			# (a -> b in i: the pair becomes c, a, d and c, d, b - the same turn)
			var nref: Vector3 = n0s[i]
			var t1 := [c, a, d]
			var t2 := [c, d, b]
			var ok := true
			for tr in [t1, t2]:
				var nn := (pv[tr[2]] - pv[tr[0]]).cross(pv[tr[1]] - pv[tr[0]])
				if nn.dot(nref) <= 0.0:
					ok = false
			if not ok:
				continue
			for k in 3:
				out[i * 3 + k] = t1[k]
				out[other * 3 + k] = t2[k]
			break
	return {"t": out, "face": faces}


## The mesh made whole where two sides of an edge have their points in different places (one side's
## point lying on the other's edge - a crack once it moves): each such edge's triangle split at those
## points; first any two points in one place made one (`fv` - the edge points - kept right). {t, fv},
## or {} - nothing to close.
static func close_seams(v: PackedVector3Array, t_in: PackedInt32Array, fv_in := []) -> Dictionary:
	var t := t_in.duplicate()
	var fv := fv_in.duplicate(true)
	var changed := false
	# (two points in one place - each side its own: one)
	var keep := {}
	var remap := {}
	for i in t.size():
		var k := key(v[t[i]])
		if not keep.has(k):
			keep[k] = t[i]
		elif keep[k] != t[i]:
			remap[t[i]] = keep[k]
	if not remap.is_empty():
		for i in t.size():
			if remap.has(t[i]):
				t[i] = remap[t[i]]
		var seen := {}
		var nfv := []
		for e in fv:
			var vi := int(e[0])
			if remap.has(vi):
				vi = remap[vi]
			var sk := "%d:%d" % [vi, int(e[1])]
			if seen.has(sk):
				continue
			seen[sk] = true
			nfv.append([vi, e[1], e[2]])
		fv = nfv
		# (no triangle left with a point twice)
		var nt0 := PackedInt32Array()
		for i in range(0, t.size(), 3):
			if t[i] != t[i + 1] and t[i + 1] != t[i + 2] and t[i] != t[i + 2]:
				nt0.append_array(PackedInt32Array([t[i], t[i + 1], t[i + 2]]))
		t = nt0
		changed = true
	var on_ch := {}   # point -> {chain: true}
	for e in fv:
		if not on_ch.has(int(e[0])):
			on_ch[int(e[0])] = {}
		on_ch[int(e[0])][int(e[1])] = true
	for round_ in 3:
		var cnt := {}
		for i in range(0, t.size(), 3):
			for j in 3:
				var e := _pk(t[i + j], t[i + (j + 1) % 3])
				cnt[e] = int(cnt.get(e, 0)) + 1
		var open_v := {}
		var open_e := []   # [a, b, triangle start] - each the way its triangle runs
		for i in range(0, t.size(), 3):
			for j in 3:
				var a := t[i + j]
				var b := t[i + (j + 1) % 3]
				if int(cnt[_pk(a, b)]) == 1:
					open_e.append([a, b, i])
					open_v[a] = true
					open_v[b] = true
		if open_e.is_empty():
			break
		var ov := open_v.keys()
		var cut := {}   # triangle start -> [a, b, [points on a-b, a to b]]
		for e in open_e:
			var a: int = e[0]
			var b: int = e[1]
			var pa := v[a]
			var ab := v[b] - pa
			var l2 := ab.length_squared()
			if l2 < 1e-16:
				continue
			var tight := maxf(sqrt(l2) * 1e-3, 1e-6)
			var loose := maxf(sqrt(l2) * 0.06, 1e-6)   # (on a curved edge a point bows off the other side's chord)
			var on := []
			for c in ov:
				if c == a or c == b:
					continue
				var tt := (v[c] - pa).dot(ab) / l2
				if tt <= 1e-4 or tt >= 1.0 - 1e-4:
					continue
				# (loosely only a point of the same curve as both ends - never a wall's point just under a rim)
				var same := false
				if on_ch.has(c) and on_ch.has(a) and on_ch.has(b):
					for ci in on_ch[c]:
						if (on_ch[a] as Dictionary).has(ci) and (on_ch[b] as Dictionary).has(ci):
							same = true
				if (pa + ab * tt).distance_to(v[c]) < (loose if same else tight):
					on.append([tt, c])
			if on.is_empty() or cut.has(e[2]):
				continue
			on.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			cut[e[2]] = [a, b, on.map(func(x): return x[1])]
		if cut.is_empty():
			break
		var nt := PackedInt32Array()
		for i in range(0, t.size(), 3):
			if not cut.has(i):
				nt.append_array(PackedInt32Array([t[i], t[i + 1], t[i + 2]]))
				continue
			var a: int = cut[i][0]
			var b: int = cut[i][1]
			var c := -1
			for j in 3:
				if t[i + j] != a and t[i + j] != b:
					c = t[i + j]
			var seq := [a]
			seq.append_array(cut[i][2])
			seq.append(b)
			for m in seq.size() - 1:
				nt.append_array(PackedInt32Array([seq[m], seq[m + 1], c]))
		t = nt
		changed = true
	return {"t": t, "fv": fv} if changed else {}


## Each edge of `tris` -> the triangles (indices) on it.
static func _tri_edges(tris: Array) -> Dictionary:
	var m := {}
	for i in tris.size():
		var tr: Array = tris[i]
		for j in 3:
			var e := _pk(int(tr[j]), int(tr[(j + 1) % 3]))
			if not m.has(e):
				m[e] = []
			m[e].append(i)
	return m


## Which way triangle `tr` faces along `n` (+: as the face's own; about 0: no area).
static func _turn(v: Array, tr: Array, n: Vector3) -> float:
	var a: Vector3 = v[tr[0]]
	var b: Vector3 = v[tr[1]]
	var c: Vector3 = v[tr[2]]
	return (c - a).cross(b - a).dot(n)


## The mesh's faces for the smooth move: [{inner: points inside it, rim: its edge points}] and, for each
## point inside, its face's edge points (the nearest 400) and how much each counts (1 / distance squared,
## adding up to 1) - a first guess at its move. Worked out once. {faces, w: {vertex: [[edge pt, weight]...]}}.
static func blend_weights(v: PackedVector3Array, t: PackedInt32Array, fixed: Dictionary, feat := {}, axis_given := Vector3.ZERO) -> Dictionary:
	return _blend(v, t, fixed, feat, axis_given)


## The mesh shaded by its faces: every point's normal the blend of its face's triangles round it (by
## their angle there) - smooth across a face however its triangles lean, sharp at the solid's edges.
## `face_of`: each triangle's face (blend_weights' "tri_face").
## Which corners meet at each point, once per mesh (for shaded): {start, corners} - point i's corners
## (triangle * 3 + j) at corners[start[i] .. start[i + 1]).
static func corner_topo(nv: int, t: PackedInt32Array) -> Dictionary:
	var cnt := PackedInt32Array()
	cnt.resize(nv + 1)
	for i in t.size():
		cnt[t[i] + 1] += 1
	for i in nv:
		cnt[i + 1] += cnt[i]
	var fill := cnt.duplicate()
	var corners := PackedInt32Array()
	corners.resize(t.size())
	for i in t.size():
		corners[fill[t[i]]] = i
		fill[t[i]] += 1
	return {"start": cnt, "corners": corners}


## shaded(), fast: one point per corner (no lookups by text), its normal the angle-weighted blend of the
## triangles round its point facing within `smooth_deg` of its own; `topo` from corner_topo.
## (`arrays_only`: its arrays, no mesh made - for a mesh made with levels of detail from them.)
static func shaded_fast(v: PackedVector3Array, t: PackedInt32Array, topo: Dictionary, mat: Material, smooth_deg := 40.0, arrays_only := false) -> Variant:
	var nt := t.size() / 3
	var tn := PackedVector3Array()
	tn.resize(nt)
	var ang := PackedFloat32Array()
	ang.resize(t.size())
	for ti in nt:
		var p0 := v[t[ti * 3]]
		var p1 := v[t[ti * 3 + 1]]
		var p2 := v[t[ti * 3 + 2]]
		var e01 := p1 - p0
		var e02 := p2 - p0
		var e12 := p2 - p1
		var n := e02.cross(e01)
		tn[ti] = n.normalized() if n.length_squared() > 1e-28 else Vector3.ZERO
		ang[ti * 3] = e01.angle_to(e02)
		ang[ti * 3 + 1] = (-e01).angle_to(e12)
		ang[ti * 3 + 2] = PI - ang[ti * 3] - ang[ti * 3 + 1]
	var start: PackedInt32Array = topo["start"]
	var corners: PackedInt32Array = topo["corners"]
	var cmin := cos(deg_to_rad(smooth_deg))
	var pv := PackedVector3Array()
	pv.resize(t.size())
	var nv := PackedVector3Array()
	nv.resize(t.size())
	var ix := PackedInt32Array()
	ix.resize(t.size())
	for c in t.size():
		var vi := t[c]
		var own: Vector3 = tn[c / 3]
		var n := Vector3.ZERO
		for k in range(start[vi], start[vi + 1]):
			var o := corners[k]
			var on: Vector3 = tn[o / 3]
			if own == Vector3.ZERO or on.dot(own) >= cmin:
				n += on * ang[o]
		pv[c] = v[vi]
		nv[c] = n.normalized() if n.length_squared() > 1e-24 else own
		ix[c] = c
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pv
	a[Mesh.ARRAY_NORMAL] = nv
	a[Mesh.ARRAY_INDEX] = ix
	if arrays_only:
		return a
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.surface_set_material(0, mat)
	return m


static func shaded(v: PackedVector3Array, t: PackedInt32Array, face_of: PackedInt32Array, mat: Material, smooth_deg := 40.0) -> ArrayMesh:
	# (each corner's normal: the triangles round its point that face within `smooth_deg` of its own,
	# each by its angle there - smooth across a curve, sharp at a real edge; `face_of` unused - kept
	# for its callers)
	var nt := t.size() / 3
	var tn := PackedVector3Array()
	tn.resize(nt)
	var ang := PackedFloat32Array()
	ang.resize(nt * 3)
	var vt := {}
	for ti in nt:
		var p0 := v[t[ti * 3]]
		var p1 := v[t[ti * 3 + 1]]
		var p2 := v[t[ti * 3 + 2]]
		var n := (p2 - p0).cross(p1 - p0)
		tn[ti] = n.normalized() if n.length() > 1e-14 else Vector3.ZERO
		var ps := [p0, p1, p2]
		for j in 3:
			var e1: Vector3 = ps[(j + 1) % 3] - ps[j]
			var e2: Vector3 = ps[(j + 2) % 3] - ps[j]
			ang[ti * 3 + j] = e1.angle_to(e2) if e1.length() > 1e-12 and e2.length() > 1e-12 else 0.0
			var vi := t[ti * 3 + j]
			if not vt.has(vi):
				vt[vi] = []
			vt[vi].append(ti * 3 + j)
	var cmin := cos(deg_to_rad(smooth_deg))
	var pv := PackedVector3Array()
	var nv := PackedVector3Array()
	var ix := PackedInt32Array()
	var slot := {}
	for ti in nt:
		for j in 3:
			var vi := t[ti * 3 + j]
			var own: Vector3 = tn[ti]
			var n := Vector3.ZERO
			for c in vt[vi]:
				var o: Vector3 = tn[c / 3]
				if own == Vector3.ZERO or o.dot(own) >= cmin:
					n += o * ang[c]
			n = n.normalized() if n.length() > 1e-12 else own
			var k := "%d:%s" % [vi, str(n.snapped(Vector3.ONE * 0.001))]
			if not slot.has(k):
				slot[k] = pv.size()
				pv.append(v[vi])
				nv.append(n)
			ix.append(slot[k])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pv
	a[Mesh.ARRAY_NORMAL] = nv
	a[Mesh.ARRAY_INDEX] = ix
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.surface_set_material(0, mat)
	return m


static func _blend(v: PackedVector3Array, t: PackedInt32Array, fixed: Dictionary, feat := {}, axis_given := Vector3.ZERO) -> Dictionary:
	var by_edge := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var e := _pk(t[i + j], t[i + (j + 1) % 3])
			if not by_edge.has(e):
				by_edge[e] = []
			by_edge[e].append(i / 3)
	var nt := t.size() / 3
	var face := PackedInt32Array()
	face.resize(nt)
	face.fill(-1)
	var nf := 0
	for t0 in nt:
		if face[t0] >= 0:
			continue
		var todo := [t0]
		face[t0] = nf
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				if feat.has(_pk(a, b)):
					continue   # (along an edge of the solid: another face beyond)
				for o in by_edge[_pk(a, b)]:
					if face[o] < 0:
						face[o] = nf
						todo.append(o)
		nf += 1
	var inner := []
	var rim := []
	for f in nf:
		inner.append({})
		rim.append({})
	for ti in nt:
		var f := face[ti]
		for j in 3:
			var vi := t[ti * 3 + j]
			(rim[f] if fixed.has(vi) else inner[f])[vi] = true
	# the solid's axis: the way its flat faces (most of their area) face - its walls stand along it
	var fn := []
	for f in nf:
		fn.append(Vector3.ZERO)
	for ti in nt:
		var a := v[t[ti * 3]]
		fn[face[ti]] += (v[t[ti * 3 + 2]] - a).cross(v[t[ti * 3 + 1]] - a)
	var axis := Vector3.ZERO
	for f in nf:
		var n: Vector3 = fn[f]
		if n.length() > 1e-9:
			var nn := n.normalized()
			if absf(nn.dot(axis.normalized() if axis != Vector3.ZERO else nn)) > 0.9 or axis == Vector3.ZERO:
				axis += nn * n.length() * signf(nn.dot(axis) if axis != Vector3.ZERO else 1.0)
	axis = axis.normalized() if axis != Vector3.ZERO else Vector3.UP
	if axis_given != Vector3.ZERO:
		axis = axis_given.normalized()
	# (how much each face faces along the axis: its triangles' |normal . axis|, by area)
	var along := []
	var area := []
	for f in nf:
		along.append(0.0)
		area.append(0.0)
	for ti in nt:
		var a := v[t[ti * 3]]
		var cr := (v[t[ti * 3 + 2]] - a).cross(v[t[ti * 3 + 1]] - a)
		var ar := cr.length()
		if ar > 1e-14:
			along[face[ti]] += absf(cr.normalized().dot(axis)) * ar
			area[face[ti]] += ar
	# (each edge point's neighbours along its edges: a point on a standing edge - a wall's side - has
	# them only straight below and above it)
	var enb := {}
	for k in feat:
		var ab := _unpk(str(k))
		for pr in [[ab[0], ab[1]], [ab[1], ab[0]]]:
			if not enb.has(pr[0]):
				enb[pr[0]] = []
			enb[pr[0]].append(pr[1])
	var faces := []
	var w := {}
	for f in nf:
		var ins: Array = (inner[f] as Dictionary).keys()
		var eds: Array = (rim[f] as Dictionary).keys()
		if ins.is_empty():
			continue
		# (a wall - standing along the axis: each point moves with the edge points straight below and
		# above it (its rails - the bottom and top edges), mixed by its height between them, plus how
		# its side edges bend off straight between their rails, blended in from the nearest side points;
		# a flat face: blended from all its edge points)
		var wall: bool = float(along[f]) / maxf(float(area[f]), 1e-14) < 0.35
		var fax := axis
		if not wall and (fn[f] as Vector3).length() > float(area[f]) * 0.998:
			# (a flat face - its quads in columns across it, along its longest straight edge: each point
			# moves as the edge points at its column's two ends do, like a wall's)
			var nf_: Vector3 = (fn[f] as Vector3).normalized()
			fax = _cap_columns(v, t, face, f, ins, eds, nf_)
			wall = true
		var fd := {"inner": PackedInt32Array(ins), "rim": PackedInt32Array(eds), "wall": wall, "cols": {}}
		var eds_p := PackedInt32Array(eds)   # (its edge points, and a weight each - filled per inner point)
		var ewt := PackedFloat64Array()
		ewt.resize(eds_p.size())
		faces.append(fd)
		var fcols: Dictionary = fd["cols"]   # (a wall's points and side points -> their column: [rails, weights])
		var rails := []
		var sides := {}   # side point -> its own column's weights (rails below / above)
		if wall:
			for e in eds:
				var side := enb.has(e) and (enb[e] as Array).size() >= 2
				if side:
					for o in enb[e]:
						var dd: Vector3 = v[o] - v[e]
						if dd.length() < 1e-12 or absf(dd.normalized().dot(fax)) < 0.9:
							side = false
							break
				if side:
					sides[e] = true
				else:
					rails.append(e)
			for e in sides.keys():
				var col := _column(v, e, rails, fax)
				if col.is_empty():
					sides.erase(e)
				else:
					sides[e] = col
					fcols[e] = col
		for vi in ins:
			if wall:
				var col := _column(v, vi, rails, fax)
				if not col.is_empty():
					fcols[vi] = col
					var acc := {}
					for k in 2:
						acc[col[0][k]] = float(col[1][k])
					if not sides.is_empty():
						# side residuals (a side point's move less what its rails would give it), by 1 / d^4 -
						# the total over every edge point first (plain numbers), then only the side points
						# that count for something (a millionth of it or more) looked up and added: a wall's
						# hundreds of side points each, every one added, was most of a second on a big solid
						var pvi := v[vi]
						var tot := 0.0
						for e in ewt.size():
							var d2 := pvi.distance_squared_to(v[eds_p[e]])
							var wt := 1.0 / maxf(d2 * d2, 1e-18)
							ewt[e] = wt
							tot += wt
						var sw := {}
						var cut := tot * 1e-6
						for e in ewt.size():
							if ewt[e] > cut and sides.has(eds_p[e]):
								sw[eds_p[e]] = ewt[e]
						for e in sw:
							var f_: float = sw[e] / tot
							acc[e] = float(acc.get(e, 0.0)) + f_
							var sc: Array = sides[e]
							for k in 2:
								acc[sc[0][k]] = float(acc.get(sc[0][k], 0.0)) - f_ * float(sc[1][k])
					var es := PackedInt32Array()
					var ws := PackedFloat32Array()
					for e in acc:
						if absf(float(acc[e])) > 1e-6:
							es.append(int(e))
							ws.append(float(acc[e]))
					w[vi] = [es, ws, true, faces.size() - 1]
					continue
			# (1 / distance to the 4th: the near edge counts most - those under a millionth of the whole
			# left out, the rest scaled to one; no sorting of hundreds of edge points a point)
			var pv2 := v[vi]
			var all_sum := 0.0
			for e in ewt.size():
				var d2 := pv2.distance_squared_to(v[eds_p[e]])
				var wt := 1.0 / maxf(d2 * d2, 1e-18)
				ewt[e] = wt
				all_sum += wt
			var ws := PackedFloat32Array()
			var es := PackedInt32Array()
			var sum := 0.0
			var cut2 := all_sum * 1e-6
			for e in ewt.size():
				if ewt[e] > cut2:
					es.append(eds_p[e])
					ws.append(ewt[e])
					sum += ewt[e]
			for k in ws.size():
				ws[k] /= sum
			w[vi] = [es, ws]
	return {"faces": faces, "w": w, "tri_face": face}


## The way a flat face's columns run (its quads' grid - quad_caps): of the two ways its inner edges run
## most, the one along which its inner points have edge points straight across both ways.
static func _cap_columns(v: PackedVector3Array, t: PackedInt32Array, face: PackedInt32Array, f: int, ins: Array, eds: Array, n: Vector3) -> Vector3:
	var inner := {}
	for vi in ins:
		inner[vi] = true
	var u0 := CT._any_perp(n)
	var w0 := n.cross(u0)
	var bins := PackedFloat32Array()
	bins.resize(180)
	for ti in face.size():
		if face[ti] != f:
			continue
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			if not inner.has(a) or not inner.has(b):
				continue
			var d := v[b] - v[a]
			var ang := fposmod(rad_to_deg(atan2(d.dot(w0), d.dot(u0))), 180.0)
			bins[int(ang) % 180] += 1.0
	var picks := []
	for k in 2:
		var bi := -1
		for i in 180:
			var taken := false
			for p in picks:
				var dd := absf(fposmod(float(i - int(p)) + 90.0, 180.0) - 90.0)
				if dd < 20.0:
					taken = true
			if not taken and (bi < 0 or bins[i] > bins[bi]):
				bi = i
		if bi >= 0 and bins[bi] > 0.0:
			picks.append(bi)
	var cands := []
	for p in picks:
		var a := deg_to_rad(float(p) + 0.5)
		cands.append((u0 * cos(a) + w0 * sin(a)).normalized())
	if cands.is_empty():
		cands = [w0, u0]
	var best: Vector3 = cands[0]
	var bs := INF
	for d: Vector3 in cands:
		var score := 0.0
		var step := maxi(1, ins.size() / 40)
		for ii in range(0, ins.size(), step):
			var p := v[ins[ii]]
			var lo := INF
			var hi := INF
			for e in eds:
				var q := v[e] - p
				var h := q.dot(d)
				var across := (q - d * h).length()
				if h < 0.0:
					lo = minf(lo, across)
				else:
					hi = minf(hi, across)
			score += lo + hi
		if score < bs:
			bs = score
			best = d
	return best


## A wall point's edge points straight below and above it (the nearest across, along the axis) and how
## much each counts by its height between them: [[below, above], [w, w]] ([] - none both ways).
static func _column(v: PackedVector3Array, vi: int, eds: Array, axis: Vector3) -> Array:
	var p := v[vi]
	var h := p.dot(axis)
	var best := [-1, -1]
	var bd := [INF, INF]
	for e in eds:
		var q := v[e]
		var dh := q.dot(axis) - h
		var across := (q - p - axis * dh).length()
		var side := 0 if dh < 0.0 else 1
		var score := across + absf(dh) * 0.05
		if score < bd[side]:
			bd[side] = score
			best[side] = e
	if best[0] < 0 or best[1] < 0:
		return []
	var h0 := v[best[0]].dot(axis)
	var h1 := v[best[1]].dot(axis)
	var f := clampf((h - h0) / maxf(h1 - h0, 1e-9), 0.0, 1.0)
	return [PackedInt32Array([best[0], best[1]]), PackedFloat32Array([1.0 - f, f])]


## The smooth solve's set-up (once a mesh): every face's inner points as unknowns, each coupled to its
## neighbours by the mesh's own shape (cotangent weights on the mesh as made - a fair spread however its
## triangles lie): a wall's or flat face's points solved for how far they are off their columns (zero
## at its rails, the side edges' bends at its sides), any other face's for their whole move.
static func cg_setup(v: PackedVector3Array, t: PackedInt32Array, bw: Dictionary) -> Dictionary:
	var wpair := {}   # "a,b" -> weight
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := t[i + j]
			var b := t[i + (j + 1) % 3]
			var c := t[i + (j + 2) % 3]
			var ea := v[a] - v[c]
			var eb := v[b] - v[c]
			var cr := ea.cross(eb).length()
			var cot := ea.dot(eb) / maxf(cr, 1e-12)
			var k := _pk(a, b)
			wpair[k] = float(wpair.get(k, 0.0)) + 0.5 * cot
	var mean := 0.0
	for k in wpair:
		mean += absf(float(wpair[k]))
	mean /= maxf(1.0, float(wpair.size()))
	var floor_w := mean * 0.05   # (never negative or nought: an obtuse corner still holds its neighbour)
	var unk := {}   # vertex -> unknown index
	var ulist := PackedInt32Array()
	var ucol := PackedByteArray()   # 1: a column face's (solved off its columns)
	var uface := []
	var w: Dictionary = bw["w"]
	for fi in (bw["faces"] as Array).size():
		var f: Dictionary = bw["faces"][fi]
		for vi in (f["inner"] as PackedInt32Array):
			if unk.has(vi) or not w.has(vi):
				continue
			var e: Array = w[vi]
			var col_face := int(e[3]) if e.size() > 3 else fi
			var is_col := e.size() > 2 and ((bw["faces"][col_face] as Dictionary).get("cols", {}) as Dictionary).has(vi)
			unk[vi] = ulist.size()
			ulist.append(vi)
			ucol.append(1 if is_col else 0)
			uface.append(col_face if is_col else fi)
	var nbr := {}   # vertex -> [neighbours]
	for k in wpair:
		var ab := _unpk(str(k))
		for pr in [[ab[0], ab[1]], [ab[1], ab[0]]]:
			if not nbr.has(pr[0]):
				nbr[pr[0]] = []
			nbr[pr[0]].append(pr[1])
	var rs := PackedInt32Array([0])
	var rc := PackedInt32Array()
	var rv := PackedFloat32Array()
	var fs := PackedInt32Array([0])
	var fidx := PackedInt32Array()
	var fwt := PackedFloat32Array()
	var fmode := PackedByteArray()   # 0: a rail (none off), 1: a side point (its bend), 2: its whole move
	var diag := PackedFloat32Array()
	for ui in ulist.size():
		var vi := ulist[ui]
		var f: Dictionary = bw["faces"][uface[ui]]
		var cols: Dictionary = f.get("cols", {})
		var dsum := 0.0
		for o in nbr.get(vi, []):
			var wt := maxf(float(wpair[_pk(vi, int(o))]), floor_w)
			dsum += wt
			if unk.has(o) and int(uface[unk[o]]) == int(uface[ui]):
				rc.append(unk[o])
				rv.append(wt)
			else:
				fidx.append(int(o))
				fwt.append(wt)
				if ucol[ui] == 1:
					fmode.append(1 if cols.has(o) else 0)
				else:
					fmode.append(2)
		rs.append(rc.size())
		fs.append(fidx.size())
		diag.append(dsum)
	# (each column point's straight place - from its column's two ends - read from flat arrays each solve,
	# not looked up by name: [end a, end b, weight a, weight b], -1: none)
	var colv := func(fi: int, vi: int) -> Array:
		var cm: Dictionary = (bw["faces"][fi] as Dictionary).get("cols", {})
		if not cm.has(vi):
			return [-1, -1, 0.0, 0.0]
		var ce: Array = cm[vi]
		var ends: PackedInt32Array = ce[0]
		var ws: PackedFloat32Array = ce[1]
		if ends.size() == 1:
			return [ends[0], ends[0], ws[0], 0.0]
		return [ends[0], ends[1], ws[0], ws[1]]
	var ub := PackedInt32Array()   # per unknown: a, b
	var ubw := PackedFloat32Array()
	for ui in ulist.size():
		var e: Array = colv.call(int(uface[ui]), ulist[ui]) if ucol[ui] == 1 else [-1, -1, 0.0, 0.0]
		ub.append_array(PackedInt32Array([e[0], e[1]]))
		ubw.append_array(PackedFloat32Array([e[2], e[3]]))
	var fb := PackedInt32Array()   # per fixed-neighbour entry: its column's a, b (mode 1)
	var fbw := PackedFloat32Array()
	for ui in ulist.size():
		for k in range(fs[ui], fs[ui + 1]):
			var e: Array = colv.call(int(uface[ui]), fidx[k]) if fmode[k] == 1 else [-1, -1, 0.0, 0.0]
			fb.append_array(PackedInt32Array([e[0], e[1]]))
			fbw.append_array(PackedFloat32Array([e[2], e[3]]))
	return {"u": ulist, "ucol": ucol, "uface": uface, "rs": rs, "rc": rc, "rv": rv, "fs": fs, "fi": fidx, "fw": fwt, "fm": fmode, "diag": diag,
		"ub": ub, "ubw": ubw, "fb": fb, "fbw": fbw}


## Every point's move, solved smooth (cg_setup's system, by conjugate gradients from `warm` - the last
## solve's offsets - for at most `iters` rounds or till it's still to `tol`): the edge points' moves as
## given (`fixed`), each wall's and flat face's points straight between their rails plus the side edges'
## bends spread over it, any other face's points spread from its edges. {d: the moves, r: the offsets}.
static func cg_moves(nv: int, cg: Dictionary, bw: Dictionary, fixed: Dictionary, warm: PackedVector3Array, iters := 40, tol := 1e-7, smooth_rounds := 6) -> Dictionary:
	var d := PackedVector3Array()
	d.resize(nv)
	for vi in fixed:
		d[vi] = fixed[vi]
	var u: PackedInt32Array = cg["u"]
	var m := u.size()
	var ucol: PackedByteArray = cg["ucol"]
	var w: Dictionary = bw["w"]
	var fs: PackedInt32Array = cg["fs"]
	var fi_: PackedInt32Array = cg["fi"]
	var fw: PackedFloat32Array = cg["fw"]
	var fm: PackedByteArray = cg["fm"]
	var ub: PackedInt32Array = cg["ub"]
	var ubw: PackedFloat32Array = cg["ubw"]
	var fb: PackedInt32Array = cg["fb"]
	var fbw: PackedFloat32Array = cg["fbw"]
	# each column point's straight place between its column's ends (moved as they are)
	var base := PackedVector3Array()
	base.resize(m)
	for ui in m:
		if ucol[ui] == 1 and ub[ui * 2] >= 0:
			base[ui] = d[ub[ui * 2]] * ubw[ui * 2] + d[ub[ui * 2 + 1]] * ubw[ui * 2 + 1]
	# the right-hand side: what the fixed neighbours hold each unknown to
	var bvec := PackedVector3Array()
	bvec.resize(m)
	for ui in m:
		var s := Vector3.ZERO
		for k in range(fs[ui], fs[ui + 1]):
			var mode := fm[k]
			if mode == 0:
				continue
			var o := fi_[k]
			if mode == 2:
				s += d[o] * fw[k]
			else:
				var vo := d[o]
				if fb[k * 2] >= 0:
					vo = d[fb[k * 2]] * fbw[k * 2] + d[fb[k * 2 + 1]] * fbw[k * 2 + 1]
				s += (d[o] - vo) * fw[k]
		bvec[ui] = s
	var rs: PackedInt32Array = cg["rs"]
	var rc: PackedInt32Array = cg["rc"]
	var rv: PackedFloat32Array = cg["rv"]
	var diag: PackedFloat32Array = cg["diag"]
	# a first guess: the last solve's (a drag goes on from where it was) - else the blend from the edges
	var x := PackedVector3Array()
	x.resize(m)
	if warm.size() == m:
		x = warm.duplicate()
	else:
		for ui in m:
			if ucol[ui] == 1:
				continue
			var e: Array = w[u[ui]]
			var es: PackedInt32Array = e[0]
			var ws: PackedFloat32Array = e[1]
			var q := Vector3.ZERO
			for k in es.size():
				q += d[es[k]] * ws[k]
			x[ui] = q
	# conjugate gradients (each unknown's weight its own pull: Jacobi-preconditioned)
	var r := PackedVector3Array()
	r.resize(m)
	var bnorm := 0.0
	for ui in m:
		var ax := x[ui] * diag[ui]
		for k in range(rs[ui], rs[ui + 1]):
			ax -= x[rc[k]] * rv[k]
		r[ui] = bvec[ui] - ax
		bnorm += bvec[ui].length_squared()
	var z := PackedVector3Array()
	z.resize(m)
	var p := PackedVector3Array()
	p.resize(m)
	var rz := 0.0
	for ui in m:
		z[ui] = r[ui] / diag[ui]
		p[ui] = z[ui]
		rz += r[ui].dot(z[ui])
	var ap := PackedVector3Array()
	ap.resize(m)
	var lim := tol * tol * maxf(bnorm, 1e-30)
	for it in iters:
		var rr := 0.0
		for ui in m:
			rr += r[ui].length_squared()
		if rr <= lim:
			break
		var pap := 0.0
		for ui in m:
			var q := p[ui] * diag[ui]
			for k in range(rs[ui], rs[ui + 1]):
				q -= p[rc[k]] * rv[k]
			ap[ui] = q
			pap += p[ui].dot(q)
		if absf(pap) < 1e-30:
			break
		var alpha := rz / pap
		var rz2 := 0.0
		for ui in m:
			x[ui] += p[ui] * alpha
			r[ui] -= ap[ui] * alpha
			z[ui] = r[ui] / diag[ui]
			rz2 += r[ui].dot(z[ui])
		var beta := rz2 / maxf(rz, 1e-30)
		rz = rz2
		for ui in m:
			p[ui] = z[ui] + p[ui] * beta
	for ui in m:
		d[u[ui]] = base[ui] + x[ui]
	# (a light smoothing over it all: where two runs of columns meet at a step - a wall's part above a
	# recess beside its full-height part - their moves blended, a smooth bend for a kink)
	var dn := d.duplicate()
	for it in smooth_rounds:
		for ui in m:
			var s := Vector3.ZERO
			var ws := 0.0
			for k in range(rs[ui], rs[ui + 1]):
				s += d[u[rc[k]]] * rv[k]
				ws += rv[k]
			for k in range(fs[ui], fs[ui + 1]):
				s += d[fi_[k]] * fw[k]
				ws += fw[k]
			if ws > 0.0:
				dn[u[ui]] = d[u[ui]].lerp(s / ws, 0.5)
		for ui in m:
			d[u[ui]] = dn[u[ui]]
	return {"d": d, "r": x}


# --- a quad mesh: walls as rows of quads between their edges ----------------------------------------

## Mesh `m` (a solid standing along one axis - extrusions and their booleans) rebuilt quad by quad: each
## wall (a face standing along the axis) as columns from its bottom edge straight up to its top edge -
## at its corners, and every `L` along it - joined by rows of quads (two triangles each); a step in it (a
## recess's side) two columns at one place; flat faces filled from their edge points; any other face its
## own triangles. Points on an edge shared by the faces either side. {v, t, chains: [vertex indices along
## each chain]} - as remesh gives ({} - it isn't such a solid).
static func quad_mesh(m, chains: Array, L: float) -> Dictionary:
	# the mesh welded
	var V := []
	var idx := {}
	var T := []
	for si in m.get_surface_count():
		var a: Array = m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
		for t in range(0, ix.size(), 3):
			var tri := PackedInt32Array()
			for j in 3:
				var k := key(vs[ix[t + j]])
				if not idx.has(k):
					idx[k] = V.size()
					V.append(vs[ix[t + j]])
				tri.append(idx[k])
			if tri[0] != tri[1] and tri[1] != tri[2] and tri[0] != tri[2]:
				T.append(tri)
	var feat := {}
	var cpts := []   # each chain's points (3D)
	var ends := []
	for ci in chains.size():
		var pts := _pv(chains[ci]["pts"])
		cpts.append(pts)
		ends.append([key(pts[0]), key(pts[pts.size() - 1])])
		var closed := bool(chains[ci].get("closed", false))
		for j in pts.size() - (0 if closed else 1):
			var a: int = idx.get(key(pts[j]), -1)
			var b: int = idx.get(key(pts[(j + 1) % pts.size()]), -1)
			if a >= 0 and b >= 0:
				feat[_pk(a, b)] = ci
	# faces: triangles joined across edges that aren't the solid's
	var E := _edge_map(T)
	var face := PackedInt32Array()
	face.resize(T.size())
	face.fill(-1)
	var fl := []   # each face: {tris, n (area-weighted normal), chains: {ci: true}}
	for t0 in T.size():
		if face[t0] >= 0:
			continue
		var fi := fl.size()
		var f := {"tris": [], "n": Vector3.ZERO, "chains": {}}
		var todo := [t0]
		face[t0] = fi
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			f["tris"].append(ti)
			var tri: PackedInt32Array = T[ti]
			f["n"] += ((V[tri[2]] as Vector3) - V[tri[0]]).cross((V[tri[1]] as Vector3) - V[tri[0]])
			for j in 3:
				var e := _pk(tri[j], tri[(j + 1) % 3])
				if feat.has(e):
					f["chains"][feat[e]] = true
					continue
				for o in E.get(e, []):
					if face[o] < 0:
						face[o] = fi
						todo.append(o)
		fl.append(f)
	# the axis: the way the biggest flat face faces
	var axis := Vector3.ZERO
	var best_a := 0.0
	for f in fl:
		var n: Vector3 = f["n"]
		if n.length() > best_a:
			var flat := true
			for ti in f["tris"]:
				var tri: PackedInt32Array = T[ti]
				var tn: Vector3 = ((V[tri[2]] as Vector3) - V[tri[0]]).cross((V[tri[1]] as Vector3) - V[tri[0]])
				if tn.length() > 1e-12 and tn.normalized().dot(n.normalized()) < 0.995:
					flat = false
					break
			if flat:
				best_a = n.length()
				axis = n.normalized()
	if axis == Vector3.ZERO:
		return {}
	var u := CT._any_perp(axis)
	var w := axis.cross(u)
	var to2 := func(p: Vector3) -> Vector2: return Vector2(p.dot(u), p.dot(w))
	# each chain's points (3D, keyed) - the walls add theirs
	var cps := []
	for ci in chains.size():
		var d := {}
		for q in cpts[ci]:
			d[key(q)] = q
		cps.append(d)
	# the walls and their footprints
	var walls := []
	for fi in fl.size():
		var f: Dictionary = fl[fi]
		var n: Vector3 = f["n"]
		if n.length() > 1e-9 and absf(n.normalized().dot(axis)) > 0.5:
			continue   # (not a wall)
		var fp := _footprint(f["chains"].keys(), cpts, chains, to2)
		if fp.is_empty():
			continue
		fp["face"] = fi
		# (its triangles laid flat - along it, up it: where columns are on it and where not - a hole, a notch)
		var tri2 := []
		var tot: float = fp["total"]
		for ti in f["tris"]:
			var tri: PackedInt32Array = T[ti]
			var t2 := PackedVector2Array()
			var ok := true
			for j in 3:
				var q: Vector3 = V[tri[j]]
				var st := _station_of(fp, to2.call(q))
				if st < 0.0:
					ok = false
					break
				t2.append(Vector2(st, q.dot(axis)))
			if not ok:
				continue
			if bool(fp["closed"]):
				var mn := minf(t2[0].x, minf(t2[1].x, t2[2].x))
				var mx := maxf(t2[0].x, maxf(t2[1].x, t2[2].x))
				if mx - mn > tot * 0.5:
					for j in 3:
						if t2[j].x < tot * 0.5:
							t2[j].x += tot
			tri2.append(t2)
		fp["tri2"] = tri2
		walls.append(fp)
	# columns: where every wall's columns are - each wall's own (corners, every L) and wherever another
	# face put a point on its edges - till they all agree
	for it in 5:
		var added := false
		for wl: Dictionary in walls:
			for s in _wall_stations(wl, cps, to2, L):
				for col in _columns_at(wl, s, cpts, to2, axis):
					for end in [col["lo"], col["hi"]]:
						var k := key(end[0])
						if not cps[int(end[1])].has(k):
							cps[int(end[1])][k] = end[0]
							added = true
		if not added:
			break
	# the vertices: every chain point (in order along its chain), then the walls' rows
	var OV := []
	var oidx := {}
	var add := func(p: Vector3) -> int:
		var k := key(p)
		if not oidx.has(k):
			oidx[k] = OV.size()
			OV.append(p)
		return oidx[k]
	var cv := []
	for ci in chains.size():
		var pts: Array = cps[ci].values()
		var poly: PackedVector3Array = cpts[ci]
		var closed := bool(chains[ci].get("closed", false))
		pts.sort_custom(func(a, b): return _along(poly, a, closed) < _along(poly, b, closed))
		var vis := []
		for q in pts:
			vis.append(add.call(q))
		if closed and not vis.is_empty():
			vis.append(vis[0])
		cv.append(vis)
	# rows at heights every wall shares (every L over the whole solid, and every column's ends): walls
	# meeting at an edge put their points on it in the same places
	var all_hs := []
	var g_min := INF
	var g_max := -INF
	for wl: Dictionary in walls:
		for st_ in _wall_stations(wl, cps, to2, L):
			for sg in _columns_at(wl, st_, cpts, to2, axis):
				for e in [sg["lo"][0], sg["hi"][0]]:
					var h := (e as Vector3).dot(axis)
					all_hs.append(h)
					g_min = minf(g_min, h)
					g_max = maxf(g_max, h)
	var g_levels := []
	if not all_hs.is_empty():
		var g_n := maxi(1, ceili((g_max - g_min) / L))
		var g_step := (g_max - g_min) / g_n
		for r in range(1, g_n):
			var h := g_min + g_step * r
			var near := false
			for e in all_hs:
				if absf(float(e) - h) < g_step * 0.35:
					near = true
					break
			if not near:
				g_levels.append(h)
		for e in all_hs:
			g_levels.append(e)
		g_levels.sort()
	var OT := PackedInt32Array()
	var done_faces := {}
	for wl: Dictionary in walls:
		var fi: int = wl["face"]
		var stations := []   # each: [its segments on the left, on the right] (the same where no step)
		var cols := []
		for st in _wall_stations(wl, cps, to2, L):
			var segs := _columns_at(wl, st, cpts, to2, axis)
			if segs.is_empty():
				continue
			var lft := []
			var rgt := []
			for sg in segs:
				cols.append(sg)
				if int(sg["side"]) <= 0:
					lft.append(sg)
				if int(sg["side"]) >= 0:
					rgt.append(sg)
			stations.append([lft, rgt])
		if stations.size() < 2:
			continue
		# (neighbouring columns meet row to row - quads - and where one column is taller (a step: a
		# recess's side) only the part they share is joined, so nothing runs from one's rows to the other's)
		var levels := g_levels
		var col_pts := func(col: Dictionary) -> Array:   # its vertices bottom to top, and their heights
			var lo: Vector3 = col["lo"][0]
			var hi: Vector3 = col["hi"][0]
			var h0 := lo.dot(axis)
			var h1 := hi.dot(axis)
			var cvs := PackedInt32Array([add.call(lo)])
			var hs := PackedFloat32Array([h0])
			for h in levels:
				if float(h) > h0 + 1e-5 and float(h) < h1 - 1e-5 and float(h) - hs[hs.size() - 1] > 1e-5:
					cvs.append(add.call(lo.lerp(hi, (float(h) - h0) / (h1 - h0))))
					hs.append(float(h))
			cvs.append(add.call(hi))
			hs.append(h1)
			return [cvs, hs]
		var n_st := stations.size()
		var tris := []
		for c in (n_st if bool(wl["closed"]) else n_st - 1):
			for ca in stations[c][1]:
				for cb in stations[(c + 1) % n_st][0]:
					var ga: Array = col_pts.call(ca)
					var gb: Array = col_pts.call(cb)
					var A: PackedInt32Array = ga[0]
					var Ah: PackedFloat32Array = ga[1]
					var B: PackedInt32Array = gb[0]
					var Bh: PackedFloat32Array = gb[1]
					var lo_h := maxf(Ah[0], Bh[0])
					var hi_h := minf(Ah[Ah.size() - 1], Bh[Bh.size() - 1])
					if hi_h - lo_h < 1e-5:
						continue
					var ia := 0
					var ib := 0
					while ia + 1 < Ah.size() and Ah[ia + 1] <= lo_h + 1e-5:
						ia += 1
					while ib + 1 < Bh.size() and Bh[ib + 1] <= lo_h + 1e-5:
						ib += 1
					var ea := ia
					var eb := ib
					while ea + 1 < Ah.size() and Ah[ea] < hi_h - 1e-5:
						ea += 1
					while eb + 1 < Bh.size() and Bh[eb] < hi_h - 1e-5:
						eb += 1
					# (zipped up: both on together where their rows match - a quad - else the lower one on)
					while ia < ea or ib < eb:
						if ia < ea and ib < eb and absf(Ah[ia + 1] - Bh[ib + 1]) < 1e-5:
							tris.append([A[ia], B[ib], B[ib + 1]])
							tris.append([A[ia], B[ib + 1], A[ia + 1]])
							ia += 1
							ib += 1
						elif ib < eb and (ia >= ea or Bh[ib + 1] < Ah[ia + 1]):
							tris.append([A[ia], B[ib], B[ib + 1]])
							ib += 1
						else:
							tris.append([A[ia], B[ib], A[ia + 1]])
							ia += 1
		# (which way round: as the face's own triangles face, near the first one that has an area)
		var flip := false
		for tr in tris:
			var qa: Vector3 = OV[tr[0]]
			var qn := ((OV[tr[2]] as Vector3) - qa).cross((OV[tr[1]] as Vector3) - qa)
			if qn.length() < 1e-12:
				continue
			var qc := (qa + (OV[tr[1]] as Vector3) + (OV[tr[2]] as Vector3)) / 3.0
			var bd := INF
			var ref := Vector3.ZERO
			for ti in fl[fi]["tris"]:
				var tri: PackedInt32Array = T[ti]
				var tc: Vector3 = ((V[tri[0]] as Vector3) + V[tri[1]] + V[tri[2]]) / 3.0
				if tc.distance_squared_to(qc) < bd:
					bd = tc.distance_squared_to(qc)
					ref = ((V[tri[2]] as Vector3) - V[tri[0]]).cross((V[tri[1]] as Vector3) - V[tri[0]])
			flip = qn.dot(ref) < 0.0
			break
		var wt := PackedInt32Array()
		for tr in tris:
			if tr[0] == tr[1] or tr[1] == tr[2] or tr[0] == tr[2]:
				continue
			var pa: Vector3 = OV[tr[0]]
			if ((OV[tr[2]] as Vector3) - pa).cross((OV[tr[1]] as Vector3) - pa).length() < 1e-12:
				continue   # (no area: along a step)
			if flip:
				wt.append_array(PackedInt32Array([tr[0], tr[2], tr[1]]))
			else:
				wt.append_array(PackedInt32Array([tr[0], tr[1], tr[2]]))
		# (a wall made right: its edges all along its footprint, its quads not lying over each other -
		# else it keeps its own triangles)
		var ok := true
		for ci in wl["rails"]:
			for q in (cpts[ci] as PackedVector3Array):
				if _station_of(wl, to2.call(q)) < 0.0:
					ok = false
					break
		if ok:
			var dire := {}
			for i in range(0, wt.size(), 3):
				for j in 3:
					var ek := str([key(OV[wt[i + j]]), key(OV[wt[i + (j + 1) % 3]])])
					if dire.has(ek):
						ok = false
						break
					dire[ek] = true
				if not ok:
					break
		if not ok:
			continue
		OT.append_array(wt)
		done_faces[fi] = true

	# flat faces: filled from their edge points; others: their own triangles
	var EM: GDScript = load("res://scripts/editor/mesh/edit_mesh.gd")
	for fi in fl.size():
		if done_faces.has(fi):
			continue
		var f: Dictionary = fl[fi]
		var n: Vector3 = f["n"]
		var flat := n.length() > 1e-9
		if flat:
			for ti in f["tris"]:
				var tri: PackedInt32Array = T[ti]
				var tn: Vector3 = ((V[tri[2]] as Vector3) - V[tri[0]]).cross((V[tri[1]] as Vector3) - V[tri[0]])
				if tn.length() > 1e-12 and tn.normalized().dot(n.normalized()) < 0.995:
					flat = false
					break
		var loops := _loops(f["chains"].keys(), ends, chains) if flat else []
		var rings := []
		for lp in loops:
			var ring := []
			for c in lp:
				var vis: Array = (cv[int(c[0])] as Array).duplicate()
				if bool(c[1]):
					vis.reverse()
				if lp.size() > 1 and vis.size() > 1:
					vis.pop_back()
				ring.append_array(vis)
			if bool(chains[int(lp[0][0])].get("closed", false)) and lp.size() == 1 and ring.size() > 1 and ring[0] == ring[ring.size() - 1]:
				ring.pop_back()
			if ring.size() >= 3:
				rings.append(ring)
		var filled := false
		if flat and not rings.is_empty():
			var nn := n.normalized()
			var fu := CT._any_perp(nn)
			var fw := nn.cross(fu)
			var r3 := []
			for ring in rings:
				var pts := PackedVector3Array()
				for vi in ring:
					pts.append(OV[vi])
				r3.append(pts)
			var order := range(r3.size())
			order.sort_custom(func(x, y): return absf(CT._winding(r3[x], nn)) > absf(CT._winding(r3[y], nn)))
			var outer: PackedVector3Array = r3[order[0]]
			if CT._winding(outer, nn) < 0.0:
				outer.reverse()
			var holes := []
			for oi in range(1, order.size()):
				var h: PackedVector3Array = r3[order[oi]]
				if CT._winding(h, nn) > 0.0:
					h.reverse()
				holes.append(h)
			var kh: PackedVector3Array = CT.keyhole(outer, holes)
			var flat2 := PackedVector2Array()
			for q in kh:
				flat2.append(Vector2(q.dot(fu), q.dot(fw)))
			var tris: PackedInt32Array = EM.ear_clip(flat2)
			if tris.size() >= 3:
				for k in range(0, tris.size(), 3):
					var ia: int = add.call(kh[tris[k]])
					var ib: int = add.call(kh[tris[k + 1]])
					var ic: int = add.call(kh[tris[k + 2]])
					var pa: Vector3 = OV[ia]
					if ((OV[ic] as Vector3) - pa).cross((OV[ib] as Vector3) - pa).dot(nn) < 0.0:
						OT.append_array(PackedInt32Array([ia, ic, ib]))
					else:
						OT.append_array(PackedInt32Array([ia, ib, ic]))
				filled = true
		if not filled:
			for ti in f["tris"]:
				var tri: PackedInt32Array = T[ti]
				OT.append_array(PackedInt32Array([add.call(V[tri[0]]), add.call(V[tri[1]]), add.call(V[tri[2]])]))
	var pv := PackedVector3Array()
	for q in OV:
		pv.append(q)
	return {"v": pv, "t": OT, "chains": cv, "axis": [axis.x, axis.y, axis.z]}


## Where point `p` is along chain polyline `poly` (its distance along it).
static func _along(poly: PackedVector3Array, p: Vector3, closed: bool) -> float:
	var best := INF
	var at_ := 0.0
	var run := 0.0
	var n := poly.size()
	for i in (n if closed else n - 1):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var c := Geometry3D.get_closest_point_to_segment(p, a, b)
		var d := c.distance_squared_to(p)
		if d < best - 1e-14:
			best = d
			at_ = run + a.distance_to(c)
		run += a.distance_to(b)
	return at_


## A wall's footprint - its edges seen along the axis: the nodes in order along it (2D keys and
## points), and its rails (the chains round it that run along it, not up it). {} - not one line.
static func _footprint(cis: Array, cpts: Array, chains: Array, to2: Callable) -> Dictionary:
	# (the rails - the edges running along the wall, not up it - seen along the axis; the footprint:
	# the longest one, carried on by any that goes on from its ends; the rest lie along it)
	var rails := []
	var lines := {}
	for ci in cis:
		var pts: PackedVector3Array = cpts[ci]
		var p2 := PackedVector2Array()
		for q in pts:
			var v2: Vector2 = to2.call(q)
			if p2.is_empty() or p2[p2.size() - 1].distance_to(v2) > 1e-6:
				p2.append(v2)
		var closed := bool(chains[ci].get("closed", false))
		if closed and p2.size() > 1:
			p2.append(p2[0])
		var extent := 0.0
		for k in p2.size() - 1:
			extent += p2[k].distance_to(p2[k + 1])
		if extent < 1e-4:
			continue   # (it runs up the wall: a side)
		rails.append(ci)
		lines[ci] = [p2, extent]
	if rails.is_empty():
		return {}
	var longest: int = rails[0]
	for ci in rails:
		if lines[ci][1] > lines[longest][1]:
			longest = ci
	var fp: PackedVector2Array = (lines[longest][0] as PackedVector2Array).duplicate()
	var used := {longest: true}
	var grew := true
	while grew:
		grew = false
		if fp.size() > 2 and fp[0].distance_to(fp[fp.size() - 1]) < 1e-5:
			break   # (round: closed)
		for ci in rails:
			if used.has(ci):
				continue
			var l: PackedVector2Array = lines[ci][0]
			var a := l[0]
			var b := l[l.size() - 1]
			var head := fp[0]
			var tail := fp[fp.size() - 1]
			# (only one that goes beyond: its middle and far end off the footprint so far - one lying
			# along it, a rail above or below, isn't a continuation)
			var mid_off := _off_line(fp, l[l.size() / 2])
			if not mid_off:
				continue
			var ext := PackedVector2Array()
			if a.distance_to(tail) < 1e-5:
				ext = l.slice(1)
				fp.append_array(ext)
			elif b.distance_to(tail) < 1e-5:
				var r := l.duplicate()
				r.reverse()
				fp.append_array(r.slice(1))
				ext = r
			elif b.distance_to(head) < 1e-5:
				var nf := l.slice(0, l.size() - 1)
				nf.append_array(fp)
				fp = nf
				ext = l
			elif a.distance_to(head) < 1e-5:
				var r := l.duplicate()
				r.reverse()
				var nf := r.slice(0, r.size() - 1)
				nf.append_array(fp)
				fp = nf
				ext = r
			if not ext.is_empty():
				used[ci] = true
				grew = true
	var closed := fp.size() > 2 and fp[0].distance_to(fp[fp.size() - 1]) < 1e-5
	if closed:
		fp.remove_at(fp.size() - 1)
	var s := PackedFloat32Array([0.0])
	for k in range(1, fp.size()):
		s.append(s[k - 1] + fp[k - 1].distance_to(fp[k]))
	var total := s[s.size() - 1] + (fp[fp.size() - 1].distance_to(fp[0]) if closed else 0.0)
	var rclosed := {}
	for ci in rails:
		rclosed[ci] = bool(chains[ci].get("closed", false))
	return {"nodes": fp, "s": s, "total": total, "closed": closed, "rails": rails, "rclosed": rclosed}


## Point `p` isn't on polyline `fp` (beyond a hair).
static func _off_line(fp: PackedVector2Array, p: Vector2) -> bool:
	for k in fp.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, fp[k], fp[k + 1]).distance_to(p) < 1e-5:
			return false
	return true


## The places along a wall where it has columns: its nodes (corners, and where its edges bend), every
## `L` between them, and wherever its edges have a point already (another face's).
static func _wall_stations(wl: Dictionary, cps: Array, to2: Callable, L: float) -> PackedFloat32Array:
	var nodes: PackedVector2Array = wl["nodes"]
	var s: PackedFloat32Array = wl["s"]
	var total: float = wl["total"]
	var st := []
	for x in s:
		st.append(x)
	var n := nodes.size()
	var segs := n if bool(wl["closed"]) else n - 1
	for i in segs:
		var a := s[i]
		var b := total if i == n - 1 else s[i + 1]
		var cnt := maxi(1, ceili((b - a) / L))
		for k in range(1, cnt):
			st.append(a + (b - a) * k / cnt)
	for ci in wl["rails"]:
		for q in (cps[ci] as Dictionary).values():
			var x := _station_of(wl, to2.call(q))
			if x >= 0.0:
				st.append(x)
	st.sort()
	var out := PackedFloat32Array()
	for x in st:
		if out.is_empty() or x - out[out.size() - 1] > 1e-5:
			out.append(x)
	if bool(wl["closed"]) and out.size() > 1 and total - out[out.size() - 1] < 1e-5:
		out.remove_at(out.size() - 1)
	return out


## Where 2D point `p` is along a wall's footprint (-1: not on it).
static func _station_of(wl: Dictionary, p: Vector2) -> float:
	var nodes: PackedVector2Array = wl["nodes"]
	var s: PackedFloat32Array = wl["s"]
	var n := nodes.size()
	var best := 1e-4
	var out := -1.0
	for i in (n if bool(wl["closed"]) else n - 1):
		var a := nodes[i]
		var b := nodes[(i + 1) % n]
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := c.distance_to(p)
		if d < best:
			best = d
			out = s[i] + a.distance_to(c)
	return out


## The 2D point at station `x` along a wall's footprint, and its segment.
static func _footprint_at(wl: Dictionary, x: float) -> Array:
	var nodes: PackedVector2Array = wl["nodes"]
	var s: PackedFloat32Array = wl["s"]
	var n := nodes.size()
	var total: float = wl["total"]
	for i in (n if bool(wl["closed"]) else n - 1):
		var a := s[i]
		var b := total if i == n - 1 else s[i + 1]
		if x <= b + 1e-7:
			var t := clampf((x - a) / maxf(b - a, 1e-9), 0.0, 1.0)
			return [nodes[i].lerp(nodes[(i + 1) % n], t), i]
	return [nodes[n - 1], n - 1]


## The wall's columns at station `x`: [{lo: [point, chain], hi: [point, chain]}] - one, or two where it
## steps (just before and just after: the edges either side of the station).
static func _columns_at(wl: Dictionary, x: float, cpts: Array, to2: Callable, axis: Vector3) -> Array:
	var total: float = wl["total"]
	var per_side := []
	for dx in [-1e-4, 1e-4]:
		var xs: float = x + dx
		if bool(wl["closed"]):
			xs = fposmod(xs, total)
		elif xs < 0.0 or xs > total:
			per_side.append([])
			continue
		var q: Vector2 = _footprint_at(wl, xs)[0]
		var q0: Vector2 = _footprint_at(wl, x)[0]
		var hits := []   # [point, chain, height] - every edge crossing this spot
		for ci in wl["rails"]:
			var pts: PackedVector3Array = cpts[ci]
			var rc := bool(wl["rclosed"].get(ci, false))
			for i in pts.size() - (0 if rc else 1):
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[(i + 1) % pts.size()]
				var a2: Vector2 = to2.call(a)
				var b2: Vector2 = to2.call(b)
				var c := Geometry2D.get_closest_point_to_segment(q, a2, b2)
				if c.distance_to(q) > 2e-4:
					continue
				var t := clampf((q0 - a2).dot(b2 - a2) / maxf((b2 - a2).length_squared(), 1e-18), 0.0, 1.0)
				var p := a.lerp(b, t)
				hits.append([p, ci, p.dot(axis)])
		hits.sort_custom(func(u, v): return float(u[2]) < float(v[2]))
		var uniq := []
		for hp in hits:
			if uniq.is_empty() or float(hp[2]) - float(uniq[uniq.size() - 1][2]) > 1e-6:
				uniq.append(hp)
		# (each stretch between two crossings that's on the face: a column - none across a hole or a notch)
		var segs := []
		var tri2: Array = wl.get("tri2", [])
		for k in uniq.size() - 1:
			var h0 := float(uniq[k][2])
			var h1 := float(uniq[k + 1][2])
			if tri2.is_empty() or _on_face2(tri2, xs, (h0 + h1) * 0.5, total, bool(wl["closed"])):
				segs.append({"lo": [uniq[k][0], uniq[k][1]], "hi": [uniq[k + 1][0], uniq[k + 1][1]]})
		if tri2.is_empty() and segs.size() > 1:
			segs = [{"lo": segs[0]["lo"], "hi": segs[segs.size() - 1]["hi"]}]
		per_side.append(segs)
	var same: bool = per_side[0].size() == per_side[1].size()
	if same:
		for k in per_side[0].size():
			if (per_side[0][k]["lo"][0] as Vector3).distance_to(per_side[1][k]["lo"][0]) > 1e-6 or (per_side[0][k]["hi"][0] as Vector3).distance_to(per_side[1][k]["hi"][0]) > 1e-6:
				same = false
				break
	var out := []
	if same:
		for sg in per_side[0]:
			sg["side"] = 0   # (no step here: one column)
			out.append(sg)
		return out
	for k in 2:
		for sg in per_side[k]:
			sg["side"] = -1 if k == 0 else 1
			out.append(sg)
	return out


## (s, h) - along a wall, up it - on its flattened triangles.
static func _on_face2(tri2: Array, s: float, h: float, total: float, closed: bool) -> bool:
	for t2: PackedVector2Array in tri2:
		for sx in ([s, s + total] if closed else [s]):
			if Geometry2D.point_is_inside_triangle(Vector2(sx, h), t2[0], t2[1], t2[2]):
				return true
	return false


# --- a baked solid's edges split and joined (its curves separated or merged: its mesh as it is) ------

## Chain `ci` of baked solid `spec` split into pieces, its mesh untouched: `pieces` [[curve id, from,
## to]...] - each piece's stretch of the old chain as places along it (to < from: round past its start,
## a closed chain). The first piece takes the chain's place, the rest are added. Each edge point on a
## piece is put on it at its place within the piece (a point where two pieces meet: on both). The
## spec's ids follow; its c0 is the caller's (the curves now).
static func split_chain(spec: Dictionary, ci: int, pieces: Array) -> void:
	var chains: Array = spec["chains"]
	var old: Dictionary = chains[ci]
	var closed := bool(old.get("closed", false))
	var fv: Array = spec["fv"]
	var out := []
	var on_old := []
	for e in fv:
		if int(e[1]) == ci:
			on_old.append(e)
		else:
			out.append(e)
	var cis := []
	for k in pieces.size():
		var nci := ci if k == 0 else chains.size()
		var ch := {"id": int(pieces[k][0]), "closed": false, "pts": [], "t": []}
		if k == 0:
			chains[ci] = ch
		else:
			chains.append(ch)
		cis.append(nci)
	var span := func(t: float, a: float, b: float) -> float:
		# (t's place within a..b, -1: outside it)
		var bb := b if b > a else b + 1.0
		var tt := t
		if closed and tt < a - 1e-6:
			tt += 1.0
		if tt < a - 1e-6 or tt > bb + 1e-6:
			return -1.0
		return clampf((tt - a) / maxf(bb - a, 1e-9), 0.0, 1.0)
	for k in pieces.size():
		var a := float(pieces[k][0 + 1])
		var b := float(pieces[k][2])
		for e in on_old:
			var w: float = span.call(float(e[2]), a, b)
			if w >= 0.0:
				out.append([int(e[0]), int(cis[k]), w])
		# (the traced points too, as the bake had them)
		var pts: Array = old.get("pts", [])
		var ts: Array = old.get("t", [])
		for m in mini(pts.size(), ts.size()):
			var w: float = span.call(float(ts[m]), a, b)
			if w >= 0.0:
				(chains[cis[k]]["pts"] as Array).append(pts[m])
				(chains[cis[k]]["t"] as Array).append(w)
	spec["fv"] = out
	var ids := []
	for ch in chains:
		ids.append(int(ch["id"]))
	spec["ids"] = ids


## Chains `ca` and `cb` of baked solid `spec` made one (`id`), its mesh untouched: `ca` run forwards
## (backwards when `ra`) then `cb` (backwards when `rb`) - where they meet one point; `la`, `lb`: their
## lengths (each one's share of the joined chain). `cb` taken out (the chains after it move up one).
## Both the same chain: closed (its ends one point).
static func merge_chains(spec: Dictionary, ca: int, cb: int, ra: bool, rb: bool, la: float, lb: float, id: int) -> void:
	var chains: Array = spec["chains"]
	var fv: Array = spec["fv"]
	if ca == cb:
		chains[ca]["closed"] = true
		chains[ca]["id"] = id
		var seen := {}
		var keep := []
		for e in fv:
			if int(e[1]) == ca:
				var tt := float(e[2])
				if tt > 1.0 - 1e-6:
					tt = 0.0
				if seen.has(int(e[0])):
					continue
				seen[int(e[0])] = true
				keep.append([int(e[0]), ca, tt])
			else:
				keep.append(e)
		spec["fv"] = keep
	else:
		var s := la / maxf(la + lb, 1e-9)
		var out := []
		var seen := {}
		for e in fv:
			var c := int(e[1])
			var tt := float(e[2])
			if c == ca:
				tt = (1.0 - tt if ra else tt) * s
			elif c == cb:
				tt = s + (1.0 - tt if rb else tt) * (1.0 - s)
			else:
				out.append([int(e[0]), c if c < cb else c - 1, tt])
				continue
			if seen.has(int(e[0])):
				continue   # (the point where they meet: once)
			seen[int(e[0])] = true
			out.append([int(e[0]), ca if ca < cb else ca - 1, tt])
		var A: Dictionary = chains[ca]
		var B: Dictionary = chains[cb]
		var pts := []
		var ts := []
		for pr in [[A, ra, 0.0, s], [B, rb, s, 1.0 - s]]:
			var P: Array = (pr[0] as Dictionary).get("pts", [])
			var T: Array = (pr[0] as Dictionary).get("t", [])
			for m in mini(P.size(), T.size()):
				pts.append(P[m])
				ts.append(float(pr[2]) + (1.0 - float(T[m]) if pr[1] else float(T[m])) * float(pr[3]))
		A["id"] = id
		A["pts"] = pts
		A["t"] = ts
		A["closed"] = false
		chains.remove_at(cb)
		spec["fv"] = out
	var ids := []
	for ch in chains:
		ids.append(int(ch["id"]))
	spec["ids"] = ids


## Lone triangles paired into quads: two neighbouring triangles neither of which is half of a quad (a
## quad: two triangles sharing each one's longest side, lying nearly flat together) that would make
## one if their shared side were turned to the quad's other diagonal - turned, when the quad they make
## is convex, flat enough and not across one of the solid's edges (`feat`: edge keys). A copy of `t`.
static func pair_quads(v: PackedVector3Array, t_in: PackedInt32Array, feat: Dictionary) -> PackedInt32Array:
	var t := t_in.duplicate()
	var nt := t.size() / 3
	for round_ in 4:
		var longest := PackedStringArray()
		longest.resize(nt)
		var by_e := {}
		for i in nt:
			var ll := -1.0
			for j in 3:
				var a := t[i * 3 + j]
				var b := t[i * 3 + (j + 1) % 3]
				var k := _pk(a, b)
				if not by_e.has(k):
					by_e[k] = []
				by_e[k].append(i)
				var l := v[a].distance_squared_to(v[b])
				if l > ll:
					ll = l
					longest[i] = k
		var paired := PackedByteArray()
		paired.resize(nt)
		for k in by_e:
			var ts: Array = by_e[k]
			if ts.size() == 2 and longest[ts[0]] == k and longest[ts[1]] == k:
				paired[ts[0]] = 1
				paired[ts[1]] = 1
		var turned := 0
		var made := {}
		for k in by_e:
			var ts: Array = by_e[k]
			if ts.size() != 2 or feat.has(k):
				continue
			var i0: int = ts[0]
			var i1: int = ts[1]
			if paired[i0] == 1 or paired[i1] == 1:
				continue
			var ab := _unpk(str(k))
			var a := -1
			var b := -1
			var c := -1
			for j in 3:
				var x := t[i0 * 3 + j]
				var y := t[i0 * 3 + (j + 1) % 3]
				if (x == ab[0] and y == ab[1]) or (x == ab[1] and y == ab[0]):
					a = x
					b = y
					c = t[i0 * 3 + (j + 2) % 3]
			var d := -1
			for j in 3:
				if t[i1 * 3 + j] != a and t[i1 * 3 + j] != b:
					d = t[i1 * 3 + j]
			if c < 0 or d < 0 or c == d or by_e.has(_pk(c, d)) or made.has(_pk(c, d)):
				continue
			var n0 := (v[c] - v[a]).cross(v[b] - v[a])
			var n1 := (v[d] - v[a]).cross(v[b] - v[a]) * -1.0
			if n0.length() < 1e-14 or n1.length() < 1e-14 or n0.normalized().dot(n1.normalized()) < 0.9:
				continue
			# (the other diagonal the longest side of both new triangles - and both facing as before)
			var cd := v[c].distance_squared_to(v[d])
			if cd <= v[c].distance_squared_to(v[a]) or cd <= v[a].distance_squared_to(v[d]) or cd <= v[c].distance_squared_to(v[b]) or cd <= v[b].distance_squared_to(v[d]):
				continue
			var t0 := PackedInt32Array([a, d, c])
			var t1 := PackedInt32Array([d, b, c])
			var m0 := (v[t0[2]] - v[t0[0]]).cross(v[t0[1]] - v[t0[0]])
			var m1 := (v[t1[2]] - v[t1[0]]).cross(v[t1[1]] - v[t1[0]])
			if m0.dot(n0) <= 0.0 or m1.dot(n0) <= 0.0:
				continue
			for j in 3:
				t[i0 * 3 + j] = t0[j]
				t[i1 * 3 + j] = t1[j]
			paired[i0] = 1
			paired[i1] = 1
			made[_pk(c, d)] = true   # (taken: no other turn onto it this round)
			turned += 1
		if turned == 0:
			break
	return t


## A mesh's triangles made even inside its faces, its shape kept: `rounds` of (1) flipping the diagonal of two
## triangles whose opposite corners together pass 180 degrees (never across an edge of the solid - both its
## ends edge points - and only when neither triangle turns over), and (2) sliding each point that isn't an edge
## point towards its neighbours' middle along the surface (not off it). Long thin triangles - a converted
## model's, made finer - become even ones; nothing folds. `fv` the edge points. {v, t}.
static func even_faces(v_in: PackedVector3Array, t_in: PackedInt32Array, fv: Array, rounds := 4, flips := true) -> Dictionary:
	var v := v_in.duplicate()
	var t := t_in.duplicate()
	var fixed := {}
	for e in fv:
		fixed[int(e[0])] = true
	# (the open border's points stay too)
	var cnt := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var k := _pk(t[i + j], t[i + (j + 1) % 3])
			cnt[k] = int(cnt.get(k, 0)) + 1
	for k in cnt:
		if int(cnt[k]) == 1:
			var ab := _unpk(k)
			fixed[ab[0]] = true
			fixed[ab[1]] = true
	for round_ in rounds:
		# (1) flips (not on a mesh of quads: a flip breaks two of them)
		for pass_ in (2 if flips else 0):
			var by_e := {}
			for i in range(0, t.size(), 3):
				for j in 3:
					var k := _pk(t[i + j], t[i + (j + 1) % 3])
					if not by_e.has(k):
						by_e[k] = []
					by_e[k].append(i)
			var flipped := 0
			var done := {}
			for k in by_e:
				var ts: Array = by_e[k]
				if ts.size() != 2 or done.has(ts[0]) or done.has(ts[1]):
					continue
				var ab := _unpk(k)
				var a := ab[0]
				var b := ab[1]
				if fixed.has(a) and fixed.has(b):
					continue   # (an edge of the solid, or its border: kept)
				var i0: int = ts[0]
				var i1: int = ts[1]
				var c := -1
				var d := -1
				for j in 3:
					if t[i0 + j] != a and t[i0 + j] != b:
						c = t[i0 + j]
					if t[i1 + j] != a and t[i1 + j] != b:
						d = t[i1 + j]
				if c < 0 or d < 0 or c == d:
					continue
				var ang_c := (v[a] - v[c]).angle_to(v[b] - v[c])
				var ang_d := (v[a] - v[d]).angle_to(v[b] - v[d])
				if ang_c + ang_d <= PI + 0.05:
					continue
				# the two triangles as they'd be: c d a and d c b, each turned as its old one was
				var n0 := (v[t[i0 + 1]] - v[t[i0]]).cross(v[t[i0 + 2]] - v[t[i0]])
				var n1 := (v[t[i1 + 1]] - v[t[i1]]).cross(v[t[i1 + 2]] - v[t[i1]])
				var x0 := PackedInt32Array([c, d, a])
				var x1 := PackedInt32Array([d, c, b])
				var m0 := (v[x0[1]] - v[x0[0]]).cross(v[x0[2]] - v[x0[0]])
				if m0.dot(n0 + n1) < 0.0:
					x0 = PackedInt32Array([c, a, d])
					x1 = PackedInt32Array([d, b, c])
					m0 = (v[x0[1]] - v[x0[0]]).cross(v[x0[2]] - v[x0[0]])
				var m1 := (v[x1[1]] - v[x1[0]]).cross(v[x1[2]] - v[x1[0]])
				var nn := (n0 + n1).normalized()
				if m0.length_squared() < 1e-24 or m1.length_squared() < 1e-24 or m0.normalized().dot(nn) < 0.5 or m1.normalized().dot(nn) < 0.5:
					continue
				for j in 3:
					t[i0 + j] = x0[j]
					t[i1 + j] = x1[j]
				done[i0] = true
				done[i1] = true
				flipped += 1
			if flipped == 0:
				break
		# (2) slides along the surface
		var nb := {}
		var vn := PackedVector3Array()
		vn.resize(v.size())
		for i in range(0, t.size(), 3):
			var n := (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]])
			for j in 3:
				vn[t[i + j]] += n
				var a := t[i + j]
				if not nb.has(a):
					nb[a] = {}
				nb[a][t[i + (j + 1) % 3]] = true
				nb[a][t[i + (j + 2) % 3]] = true
		var nv := v.duplicate()
		for a in nb:
			if fixed.has(a):
				continue
			var acc := Vector3.ZERO
			for o in nb[a]:
				acc += v[o]
			var target: Vector3 = acc / (nb[a] as Dictionary).size()
			var n := vn[a].normalized()
			var dv: Vector3 = target - v[a]
			dv -= n * dv.dot(n)   # (along the surface)
			nv[a] = v[a] + dv * 0.5
		v = nv
	return {"v": v, "t": t}



## A mesh made of quads (each two triangles sharing their longest side, lying nearly flat), its shape kept:
## its triangles paired into quads wherever two lie flat together across their longest side (not across an
## edge of the solid), then split as a subdivision surface's first step without its smoothing - a point at
## each side's middle and each face's middle: a quad four quads, a lone triangle three - every face a quad;
## again while a side's longer than `max_len` (up to `max_quads`). A new point at the middle of an edge's side
## (both its ends that edge's points) joins it. `closed`: each edge closed. [v, t, fv].
static func quadify(v_in: PackedVector3Array, t_in: PackedInt32Array, fv_in: Array, closed: Array, max_len: float, max_quads: int) -> Array:
	var v := v_in.duplicate()
	var fv := fv_in.duplicate(true)
	var faces := _pair_faces(v, t_in, fv)
	for level in 4:
		var longest := 0.0
		for f in faces:
			for j in (f as Array).size():
				longest = maxf(longest, v[f[j]].distance_to(v[f[(j + 1) % (f as Array).size()]]))
		var n_after := 0
		for f in faces:
			n_after += (f as Array).size()
		if level > 0 and (longest <= max_len or n_after > max_quads):
			break
		var on := {}
		for e in fv:
			if not on.has(int(e[0])):
				on[int(e[0])] = {}
			on[int(e[0])][int(e[1])] = float(e[2])
		var mid := {}
		var mid_of := func(a: int, b: int) -> int:
			var k := _pk(a, b)
			if mid.has(k):
				return mid[k]
			var m := v.size()
			v.append((v[a] + v[b]) * 0.5)
			mid[k] = m
			if on.has(a) and on.has(b):
				var best_c := -1
				var best_d := INF
				var best_t := 0.0
				for ci in on[a]:
					if not (on[b] as Dictionary).has(ci):
						continue
					var ta: float = on[a][ci]
					var tb: float = on[b][ci]
					var d := absf(ta - tb)
					var tm := (ta + tb) * 0.5
					if int(ci) < closed.size() and bool(closed[int(ci)]) and d > 0.5:
						d = 1.0 - d
						tm = fposmod(tm + 0.5, 1.0)
					if d < best_d:
						best_d = d
						best_c = int(ci)
						best_t = tm
				if best_c >= 0:
					fv.append([m, best_c, best_t])
			return m
		var nf := []
		for f: Array in faces:
			var c := Vector3.ZERO
			for x in f:
				c += v[x]
			v.append(c / f.size())
			var fc := v.size() - 1
			var n := f.size()
			for j in n:
				var a: int = f[j]
				var prev: int = mid_of.call(f[(j - 1 + n) % n], a)
				var nxt: int = mid_of.call(a, f[(j + 1) % n])
				nf.append([a, nxt, fc, prev])
		faces = nf
	return [v, _faces_to_tris(v, faces), fv]


## Triangles `t` as faces: two paired into a quad (sharing their longest side, lying nearly flat together,
## that side not one of the solid's edges), the rest left triangles. [[corners in order]...].
static func _pair_faces(v: PackedVector3Array, t: PackedInt32Array, fv: Array) -> Array:
	# (triangles side by side made quads - best first: across each side that isn't one of the solid's edges,
	# the two triangles there scored by how square the quad they'd make is (convex, nearly flat), and the
	# squarest pairs taken first, each triangle once)
	var nt := t.size() / 3
	# (the solid's edges as sides of the mesh: points next to each other along each one - a side between two
	# points of one edge that aren't neighbours along it, a corner quad's diagonal, isn't one of them)
	var edge_sides := {}
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in lst.size():
			var a0: int = lst[m][1]
			var b0: int = lst[(m + 1) % lst.size()][1]
			if a0 != b0:
				edge_sides[_pk(a0, b0)] = true
	var by_e := {}
	var nrm := []
	for i in nt:
		for j in 3:
			var k := _pk(t[i * 3 + j], t[i * 3 + (j + 1) % 3])
			if not by_e.has(k):
				by_e[k] = []
			by_e[k].append(i)
		var n := (v[t[i * 3 + 1]] - v[t[i * 3]]).cross(v[t[i * 3 + 2]] - v[t[i * 3]])
		nrm.append(n.normalized() if n.length_squared() > 1e-24 else Vector3.ZERO)
	var cands := []   # [score, i, partner, x, q, y, pp]
	for k in by_e:
		var tl: Array = by_e[k]
		if tl.size() != 2:
			continue
		var i: int = tl[0]
		var o: int = tl[1]
		if (nrm[i] as Vector3).dot(nrm[o]) < 0.85:
			pair_why["bent"] = int(pair_why.get("bent", 0)) + 1
			continue
		var ab := _unpk(k)
		var feature := edge_sides.has(k)   # (one of the solid's edges: not a quad's diagonal)
		if feature:
			pair_why["edge"] = int(pair_why.get("edge", 0)) + 1
			continue
		# (triangle i: x -> y shared, pp its third point; the partner's third point q: the quad x q y pp)
		var x := -1
		var y := -1
		var pp := -1
		for j in 3:
			var a := t[i * 3 + j]
			var b := t[i * 3 + (j + 1) % 3]
			if _pk(a, b) == k:
				x = a
				y = b
				pp = t[i * 3 + (j + 2) % 3]
		var q := -1
		for j in 3:
			var c := t[o * 3 + j]
			if c != x and c != y:
				q = c
		var quad := [x, q, y, pp]
		var worst := 0.0
		var convex := true
		var qn: Vector3 = (nrm[i] as Vector3) + (nrm[o] as Vector3)
		for m in 4:
			var p0: Vector3 = v[quad[(m + 3) % 4]]
			var p1: Vector3 = v[quad[m]]
			var p2: Vector3 = v[quad[(m + 1) % 4]]
			var d0 := p0 - p1
			var d1 := p2 - p1
			if d0.length_squared() < 1e-24 or d1.length_squared() < 1e-24:
				convex = false
				break
			worst = maxf(worst, absf(rad_to_deg(d0.angle_to(d1)) - 90.0))
			if d1.cross(d0).dot(qn) < 0.0:
				convex = false
		if not convex or worst > 80.0:
			pair_why["dented" if not convex else "skewed"] = int(pair_why.get("dented" if not convex else "skewed", 0)) + 1
			continue
		# (the side shared the longest of both triangles - how a quad's own diagonal looks: those first)
		var kl := v[ab[0]].distance_squared_to(v[ab[1]])
		var diag := true
		for tt in [i, o]:
			for j in 3:
				if v[t[tt * 3 + j]].distance_squared_to(v[t[tt * 3 + (j + 1) % 3]]) > kl * 1.0001:
					diag = false
		cands.append([worst - (1000.0 if diag else 0.0), i, o, x, q, y, pp])
	cands.sort_custom(func(p, r): return float(p[0]) < float(r[0]))
	var used := PackedByteArray()
	used.resize(nt)
	var faces := []
	for c in cands:
		if used[c[1]] == 1 or used[c[2]] == 1:
			continue
		used[c[1]] = 1
		used[c[2]] = 1
		faces.append([c[3], c[4], c[5], c[6]])
	for i in nt:
		if used[i] == 0:
			faces.append([t[i * 3], t[i * 3 + 1], t[i * 3 + 2]])
	return faces


## Faces (quads, triangles; corners in order) as triangles - a quad two, split along its longer diagonal (so
## it reads as one quad: two triangles sharing their longest side).
static func _faces_to_tris(v: PackedVector3Array, faces: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f: Array in faces:
		if f.size() == 3:
			out.append_array(PackedInt32Array([f[0], f[1], f[2]]))
		elif f.size() == 4:
			if v[f[0]].distance_squared_to(v[f[2]]) >= v[f[1]].distance_squared_to(v[f[3]]):
				out.append_array(PackedInt32Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
			else:
				out.append_array(PackedInt32Array([f[1], f[2], f[3], f[1], f[3], f[0]]))
	return out


## A solid's mesh made again as grids of quads that follow its edges - the rules for any topology made here:
## quads, laid out evenly, running along the edges. Each edge (between where edges meet) is sampled evenly
## once, so the faces either side share its points; each face (a region between edges, one boundary loop)
## is mapped onto a square - its boundary along the square's sides between four corners (its sharpest
## corners, opposite sides given the same number of points), its inside by a harmonic map - and a grid laid
## there is mapped back onto its surface. {v, t, fv} - or {} when a face can't be (a face with a hole,
## a corner count that won't balance, a grid that would fold): the mesh is left to other ways then.
## `L`: the quads' size.
static var grid_why := ""   # (why grid_faces made nothing - for the tests and messages)
static var grid_fail := -1   # (the face it stopped at)
static var grid_log := []
static var pair_why := {}
static var grid_keep_counts := true
static var kept_why := {}
static var field_fill_on := true   # (faces the templates can't do: a field-aligned fill - field_remesh.gd)
static var field_fill_all := false   # (experiment: every face field-filled)
static var fill_compare := true   # (each face: the fill tried too, the better kept)
static var fill_margin := 2.0
static var fill_skip_above := 101.0   # (a face's grid scoring this or more: no fill tried)   # (score points the fill must win by)
static var fill_won := 0
static var small_why := ""
static var progress := [0.0, ""]   # (the layout running: how far, 0..1, and what it's doing - read by the editor's bar)
static var _pbase := 0.0
static var _pspan := 1.0
static var prof := {}   # (debug: ms by stage - fill, score, grid)
static var fill_count := 0
static var fill_out_v := PackedVector3Array()
static var fill_out_t := PackedInt32Array()
static var fill_fixed := {}   # (faces filled on their own rim points: their edges' points kept)
static var fill_retry := []
static var fill_cache := {}   # (a face's fill by its triangles and rim samples - the rounds of grid_faces_best)
static var fill_log := []   # (debug: [triangles, filled?, why] a kept face)
static var crease_on := true   # (tuning switches)
static var uneven_limit := 10.0   # (a grid with a quad this many times the mean size: not used)
static var big_face := 0.0   # (a face of more quads than this cut in two, again till none is: 0 - off)
static var crease_min_len := 0.0   # (a crease line shorter than this many quads: a facet's nick)
static var crease_both := true   # (grid_any: laid out with short and with only long crease lines - the better kept)
static var crease_short := 4.0
static var crease_long := 8.0
static var crease_loop_min := 6.0   # (a closed crease line shorter than this many quads: dropped)
static var crease_deg := 35.0   # (a bend sharper than this, not an edge, gets a row of mesh along it)
static var fold_fallback_on := false   # (the plain average where cotangents fold: slightly worse on the player - off)
static var paths_on := true
static var ring_cut_on := false   # (cutting lopsided rings in two: worse on the player - off)
static var split_closed_on := false   # (cutting closed edgeless shapes in two: fewer slivers, but more non-manifold sides - to fix first)
static var no_chain_side := []   # (tuning: the last rim side on no edge)   # (tuning: why faces were kept as they were - counts)
static var dome_as_grid := false   # (tuning: a round dome as one grid of four corners on its rim, not rings)
static var phong_amount := 0.75   # (how far new points are pulled to the smooth surface - 0: flat facets; the rim needs the same before it helps: to do)
static var last_quality := ""   # (the last face's quads: mean aspect, slivers - for tuning)   # (each edge's count from its length alone - see the balancing)   # (why triangle pairs weren't made quads - for tuning)   # (each face: [face, how it was laid out, its corners, why another way failed] - for tuning)


## grid_faces, face by face: a face that can't be a grid kept as it was (its rim's points kept, so its
## neighbours' grids meet it with no gap) and the rest laid out again - tried till it works. {v, t, fv,
## kept (how many faces were kept)} or {} (none could be).
static func grid_faces_best(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array, L: float, fill := true, only := {}) -> Dictionary:
	var keep := {}
	fill_count = 0
	fill_log = []
	fill_cache = {}
	fill_won = 0
	for attempt in 400:
		var pt0 := Time.get_ticks_usec()
		_prog(0.05 + 0.2 * (1.0 - 1.0 / (1.0 + attempt * 0.3)), "laying grids")
		var r := grid_faces(v, t, fv, chains, L, keep, false, only)
		prof["grid_pass"] = float(prof.get("grid_pass", 0.0)) + (Time.get_ticks_usec() - pt0) / 1000.0
		prof["grid_passes"] = int(prof.get("grid_passes", 0)) + 1
		if not r.is_empty():
			r["kept"] = keep.size()
			if fill and (not keep.is_empty() or field_fill_all or fill_compare) and field_fill_on:
				# (the faces kept: laid out by the field-aligned fill, once the rest is settled - their rims sampled
				# like the others'; one the fill can't do that way filled on its own points next round)
				fill_fixed = {}
				var keep2 := keep.duplicate()
				for round in 60:
					fill_retry = []
					fill_count = 0
					var pt1 := Time.get_ticks_usec()
					var r2 := grid_faces(v, t, fv, chains, L, keep2, true, only)
					prof["fill_pass"] = float(prof.get("fill_pass", 0.0)) + (Time.get_ticks_usec() - pt1) / 1000.0
					prof["fill_passes"] = int(prof.get("fill_passes", 0)) + 1
					if r2.is_empty():
						# (a grid that fails with its neighbours' rims sampled: filled too)
						if grid_fail < 0 or keep2.has(grid_fail):
							break
						keep2[grid_fail] = true
						continue
					if fill_retry.is_empty():
						r2["kept"] = keep2.size()
						r2["filled"] = fill_count
						return r2
					for f in fill_retry:
						fill_fixed[f] = true
			return r
		if grid_fail < 0 or keep.has(grid_fail):
			return {}
		keep[grid_fail] = true
		kept_why[grid_why.get_slice("(", 0).left(40)] = int(kept_why.get(grid_why.get_slice("(", 0).left(40), 0)) + 1
	return {}


static func grid_faces(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array, L: float, keep := {}, fill_kept := false, only := {}) -> Dictionary:
	grid_fail = -1
	grid_log = []
	var nv0 := v.size()
	var on := {}   # vertex -> {chain: place}
	for e in fv:
		if not on.has(int(e[0])):
			on[int(e[0])] = {}
		on[int(e[0])][int(e[1])] = float(e[2])
	# each chain's points in order
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	var feat := {}
	var ch_list := {}
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var vs := []
		for x in lst:
			if vs.is_empty() or vs.back() != int(x[1]):
				vs.append(int(x[1]))
		var closed: bool = ci < chains.size() and bool(chains[ci].get("closed", false))
		if closed and vs.size() > 1 and vs[0] == vs.back():
			vs.pop_back()
		ch_list[ci] = [vs, closed]
		for m in vs.size() - 1:
			feat[_pk(vs[m], vs[m + 1])] = true
		if closed and vs.size() > 2:
			feat[_pk(vs.back(), vs[0])] = true
	# where chains meet (and open chains' ends): the segments' ends
	var junction := {}
	for vi in on:
		if (on[vi] as Dictionary).size() > 1:
			junction[vi] = true
	for ci in ch_list:
		if not ch_list[ci][1] and not (ch_list[ci][0] as Array).is_empty():
			junction[ch_list[ci][0][0]] = true
			junction[ch_list[ci][0].back()] = true
	# (an edge's own sharp bends too: points of the mesh exactly - the samples of a stretch run between them,
	# never cutting a corner)
	for ci in ch_list:
		var vs: Array = ch_list[ci][0]
		var closed: bool = ch_list[ci][1]
		var m := vs.size()
		if m < 3:
			continue
		for i in m:
			if not closed and (i == 0 or i == m - 1):
				continue
			var p0: Vector3 = v[vs[(i - 1 + m) % m]]
			var p1: Vector3 = v[vs[i]]
			var p2: Vector3 = v[vs[(i + 1) % m]]
			if (p1 - p0).length_squared() < 1e-24 or (p2 - p1).length_squared() < 1e-24:
				continue
			if (p1 - p0).angle_to(p2 - p1) > deg_to_rad(50.0):
				junction[vs[i]] = true
	# segments: runs of a chain between junctions - [verts, chain, closed loop]
	var segs := []
	var edge_seg := {}   # "a_b" -> [segment, forward (a then b along it)]
	for ci in ch_list:
		var vs: Array = ch_list[ci][0]
		var closed: bool = ch_list[ci][1]
		if vs.size() < 2:
			continue
		var starts := []
		for m in vs.size():
			if junction.has(vs[m]):
				starts.append(m)
		if closed and starts.is_empty():
			segs.append([vs.duplicate(), ci, true])
		else:
			if not closed:
				pass
			var n := vs.size()
			var ks := starts if closed else starts
			if ks.is_empty():
				ks = [0]
			for si in ks.size():
				var a: int = ks[si]
				var b: int = ks[(si + 1) % ks.size()] if (closed or si + 1 < ks.size()) else -1
				if b < 0:
					break
				var run := []
				var m := a
				while true:
					run.append(vs[m])
					if m == b and run.size() > 1:
						break
					m = (m + 1) % n if closed else m + 1
					if not closed and m >= n:
						break
				if run.size() >= 2:
					segs.append([run, ci, false])
	for si in segs.size():
		var run: Array = segs[si][0]
		var lim := run.size() if segs[si][2] else run.size() - 1
		for m in lim:
			var a: int = run[m]
			var b: int = run[(m + 1) % run.size()]
			edge_seg[str(a) + "_" + str(b)] = [si, true]
			edge_seg[str(b) + "_" + str(a)] = [si, false]
	# segment lengths and point counts (closed loops: a multiple of four)
	var seg_len := []
	var seg_n := []
	for s in segs:
		var run: Array = s[0]
		var ln := 0.0
		var lim := run.size() if s[2] else run.size() - 1
		for m in lim:
			ln += v[run[m]].distance_to(v[run[(m + 1) % run.size()]])
		seg_len.append(ln)
		var n := maxi(1, roundi(ln / L))
		if s[2]:
			n = maxi(4, int(ceil(n / 4.0)) * 4)
		seg_n.append(n)
	# faces and their boundary loops as runs of segments
	var face: PackedInt32Array = face_of(v, t, feat)
	var nf := 0
	for f in face:
		nf = maxi(nf, f + 1)
	var f_tris := []
	for f in nf:
		f_tris.append([])
	for ti in face.size():
		(f_tris[face[ti]] as Array).append(ti)
	# (only: the triangles to lay out - a face with none of them frozen: its triangles and its edges' points as
	# they are, never filled)
	var frozen := {}
	if not only.is_empty():
		for f in nf:
			var any := false
			for ti in f_tris[f]:
				if only.has(ti):
					any = true
					break
			if not any:
				frozen[f] = true
		keep = keep.duplicate()
		keep.merge(frozen)
	# (a face an edge runs into and stops in - a knife's cut ending inside it: the edge's sides inside the face,
	# triangles of the face on both sides. Its rim's one loop can't follow that edge - laid out, the edge would
	# be left floating, its points in no triangle: such a face kept as it was, the edge's points with it)
	var slit := {}
	for f in nf:
		var cnt := {}
		for ti in f_tris[f]:
			for j in 3:
				var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
				cnt[k] = int(cnt.get(k, 0)) + 1
		for k in cnt:
			if int(cnt[k]) == 2 and feat.has(k):
				slit[f] = true
				break
	if not slit.is_empty():
		keep = keep.duplicate()
		keep.merge(slit)
		frozen = frozen.duplicate()
		frozen.merge(slit)
	var f_loops := []   # each face: [[segment, forward]...] in loop order
	var f_loops2 := []   # (a ring-shaped face: its second loop's - else null)
	var kept_edges := []   # (the kept faces' rims: [a, b] - their segments keep their points)
	for f in nf:
		var cnt := {}
		for ti in f_tris[f]:
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				var k := _pk(a, b)
				cnt[k] = int(cnt.get(k, 0)) + 1
		if keep.has(f) or (fill_kept and field_fill_all):
			for ti in f_tris[f]:
				for j in 3:
					var a := t[ti * 3 + j]
					var b := t[ti * 3 + (j + 1) % 3]
					if int(cnt[_pk(a, b)]) == 1 and (not fill_kept or fill_fixed.has(f) or frozen.has(f)):
						kept_edges.append([a, b])
					elif slit.has(f) and feat.has(_pk(a, b)):
						kept_edges.append([a, b])   # (the edge inside it: its points as they are)
			f_loops.append([])
			f_loops2.append(null)
			continue
		var nxt := {}
		for ti in f_tris[f]:
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				if int(cnt[_pk(a, b)]) == 1:
					if nxt.has(a):
						grid_why = "a boundary touching itself"
						grid_fail = f
						return {}   # (a boundary touching itself)
					nxt[a] = b
		if nxt.is_empty():
			grid_why = "a closed face with no edges round it"
			grid_fail = f
			return {}   # (a closed face with no edges round it)
		# its boundary loops: one (a face), or two (a ring-shaped face - rows between them)
		var loops := []
		var left := nxt.duplicate()
		while not left.is_empty():
			var st: int = left.keys()[0]
			var loop := [st]
			var cur: int = left[st]
			left.erase(st)
			while cur != st and left.has(cur):
				loop.append(cur)
				var nx2: int = left[cur]
				left.erase(cur)
				cur = nx2
			if cur != st:
				grid_why = "a boundary that doesn't close"
				grid_fail = f
				return {}
			loops.append(loop)
		if loops.size() > 2:
			grid_why = "a face with more than one hole"
			grid_fail = f
			return {}
		var walked := []
		for loop in loops:
			var runs := _walk_loop(loop, junction, edge_seg, segs)
			if runs.is_empty():
				grid_fail = f
				return {}   # (grid_why says why)
			walked.append(runs)
		if walked.size() == 2:
			# (the longer loop first: the outer)
			var la := 0
			var lb := 0
			for r in walked[0]:
				la += (segs[r[0]][0] as Array).size()
			for r in walked[1]:
				lb += (segs[r[0]][0] as Array).size()
			if lb > la:
				walked.reverse()
		f_loops.append(walked[0])
		f_loops2.append(walked[1] if walked.size() == 2 else null)
	# (the kept faces' segments: their points as they are - their counts fixed)
	var fixed := {}
	for e in kept_edges:   # (the fill pass: only the faces filled on their own points - fill_fixed; the others' sampled like any)
		var es = edge_seg.get(str(e[0]) + "_" + str(e[1]))
		if es != null:
			fixed[int(es[0])] = true
	for si in fixed:
		var run: Array = segs[si][0]
		seg_n[si] = run.size() if segs[si][2] else run.size() - 1
	# balance: each face's loop count even, opposite sides equal at its sharp corners - segments' counts
	# raised where needed, a few rounds
	var turn_at := func(vi: int, prev: int, nxt2: int) -> float:
		var d0 := (v[vi] - v[prev]).normalized()
		var d1 := (v[nxt2] - v[vi]).normalized()
		return d0.angle_to(d1)
	# (each face's sharp corners - where its runs meet at a turn over 50 degrees: the four sharpest its grid's
	# corners, opposite sides given the same count - the shorter one's sparsest segment one more, rounds over)
	var f_corners := []   # each face: the run indices its four corners start (or [])
	var f_cc := []   # each face with 3, 5 or 6 corners: the run indices they start (or [])
	var f_ncand := []   # (each face: how many sharp corners it has)
	for f in nf:
		var runs: Array = f_loops[f]
		var cand := []
		if runs.size() >= 3 and f_loops2[f] == null:
			for ri in runs.size():
				var pr: Array = runs[(ri - 1 + runs.size()) % runs.size()]
				var cr: Array = runs[ri]
				var prun: Array = segs[pr[0]][0]
				var crun: Array = segs[cr[0]][0]
				var pv_prev: int = prun[prun.size() - 2] if pr[1] else prun[1]
				var here: int = crun[0] if cr[1] else crun.back()
				var nx: int = crun[1] if cr[1] else crun[crun.size() - 2]
				var ang: float = turn_at.call(here, pv_prev, nx)
				if ang > deg_to_rad(50.0):
					cand.append([ang, ri])
		f_ncand.append(cand.size())
		if cand.size() == 4:   # (exactly four corners: one grid; 3, 5 or 6 - that many grids round a pole; else rings)
			cand.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
			var four := [int(cand[0][1]), int(cand[1][1]), int(cand[2][1]), int(cand[3][1])]
			four.sort()
			f_corners.append(four)
			f_cc.append([])
		else:
			f_corners.append([])
			if cand.size() in [3, 5, 6]:
				var cc := cand.map(func(x): return int(x[1]))
				cc.sort()
				f_cc.append(cc)
			else:
				f_cc.append([])
	var n_first := seg_n.duplicate()
	# (counts kept true to each edge's length: a face whose sides don't balance gets a plan that takes them as
	# they are - a pole, a corner moved - not its neighbours' edges made denser to suit it; only rings, whose
	# two loops must match, are balanced)
	for round_i in 30:
		var changed := false
		var over := false
		for si in seg_n.size():
			if int(seg_n[si]) > int(n_first[si]) * 2 + 4:
				over = true
		if over:
			break   # (won't balance without growing: the faces left unbalanced get rings instead)
		for f in nf:
			if f_loops2[f] == null:
				continue
			# (a ring-shaped face: both its loops the same count - its rows run from one to the other)
			var ta := 0
			var tb := 0
			for r in f_loops[f]:
				ta += int(seg_n[r[0]])
			for r in f_loops2[f]:
				tb += int(seg_n[r[0]])
			if ta == tb:
				continue
			var low: Array = f_loops[f] if ta < tb else f_loops2[f]
			var pick := -1
			for r in low:
				if fixed.has(r[0]):
					continue
				if pick < 0 or float(seg_len[r[0]]) / seg_n[r[0]] > float(seg_len[pick]) / seg_n[pick]:
					pick = r[0]
			if pick >= 0:
				seg_n[pick] = int(seg_n[pick]) + absi(ta - tb)
				changed = true
		for f in nf:
			var four: Array = f_corners[f]
			if four.is_empty() or grid_keep_counts:
				continue
			var runs: Array = f_loops[f]
			var sides := []
			for k in 4:
				var a: int = four[k]
				var b: int = four[(k + 1) % 4]
				var ids := []
				var r := a
				while r != b:
					ids.append(runs[r][0])
					r = (r + 1) % runs.size()
				sides.append(ids)
			for pair in [[0, 2], [1, 3]]:
				var c0 := 0
				var c1 := 0
				for si in sides[pair[0]]:
					c0 += int(seg_n[si])
				for si in sides[pair[1]]:
					c1 += int(seg_n[si])
				if c0 == c1:
					continue
				var low: Array = sides[pair[0]] if c0 < c1 else sides[pair[1]]
				var pick := -1
				for si in low:
					if not segs[si][2] and not fixed.has(si) and (pick < 0 or float(seg_len[si]) / seg_n[si] > float(seg_len[pick]) / seg_n[pick]):
						pick = si
				if pick >= 0:
					seg_n[pick] = int(seg_n[pick]) + absi(c1 - c0)
					changed = true
		for f in nf:
			var cc: Array = f_cc[f]
			if cc.is_empty() or grid_keep_counts:
				continue
			# (an n-sided face: its sides' counts such that each spoke is a whole number, one or more - a
			# spoke too short: the sides either side of it longer)
			var runs: Array = f_loops[f]
			var sides := []
			var e := []
			for k in cc.size():
				var a: int = cc[k]
				var b: int = cc[(k + 1) % cc.size()]
				var ids := []
				var r := a
				while r != b:
					ids.append(runs[r][0])
					r = (r + 1) % runs.size()
				sides.append(ids)
				var c := 0
				for si in ids:
					c += int(seg_n[si])
				e.append(c)
			var sf := cc_spokes(e, true)
			if sf.is_empty():
				continue
			var nn := cc.size()
			var grow := {}
			for i in nn:
				if float(sf[i]) < 1.0 - 1e-6:
					grow[(i - 1 + nn) % nn] = true
					grow[(i + 1) % nn] = true
			if grow.is_empty() and not cc_spokes(e).is_empty():
				continue
			if grow.is_empty():
				# (whole numbers only - six sides: each group of every other side even in total; a side of each
				# odd group a step longer)
				if nn == 6:
					for g0 in 2:
						if (int(e[g0]) + int(e[g0 + 2]) + int(e[g0 + 4])) % 2 == 1:
							var best_side := g0
							for k2 in [g0, g0 + 2, g0 + 4]:
								if int(e[k2]) < int(e[best_side]):
									best_side = k2
							grow[best_side] = true
				if grow.is_empty():
					continue
			for side in grow:
				var pick := -1
				for si in sides[side]:
					if segs[si][2] or fixed.has(si):
						continue
					if pick < 0 or float(seg_len[si]) / seg_n[si] > float(seg_len[pick]) / seg_n[pick]:
						pick = si
				if pick >= 0:
					seg_n[pick] = int(seg_n[pick]) + 1
					changed = true
		if not changed:
			break
	for round_i in 12:
		var changed := false
		for f in nf:
			var total := 0
			var longest := -1
			for r in f_loops[f]:
				total += int(seg_n[r[0]])
				if not fixed.has(r[0]) and (longest < 0 or float(seg_len[r[0]]) / seg_n[r[0]] > float(seg_len[longest]) / seg_n[longest]):
					longest = r[0]
			if total % 2 == 1 and longest >= 0 and not segs[longest][2]:
				seg_n[longest] = int(seg_n[longest]) + 1
				changed = true
		if not changed:
			break
	# (every point's normal, all its triangles - the rim's samples follow the surface's curve with it)
	var vnrm := _face_normals(v, t, range(t.size() / 3)) if phong_amount > 0.0 else {}
	# samples: shared vertices along each segment (junctions shared too)
	var out_v := PackedVector3Array()
	var new_of := {}   # old junction vertex -> new vertex
	var seg_pts := []   # each segment: its samples' new vertex ids, in its own order (closed: no repeat)
	var rim_split := {}   # (the fill pass: Vector2i(old a, old b) -> [[u, new id, point]...] - the samples on that side)
	var rim_inner := {}   # (old points inside a resampled segment: not samples themselves)
	var fv_out := []
	var fv_seen := {}
	var add_fv := func(nid: int, ci: int, tp: float):
		var key := str(nid) + "_" + str(ci)
		if not fv_seen.has(key):
			fv_seen[key] = true
			fv_out.append([nid, ci, tp])
	for si in segs.size():
		var run: Array = segs[si][0]
		var ci: int = segs[si][1]
		var closed_seg: bool = segs[si][2]
		var n: int = seg_n[si]
		var pts := []
		if fixed.has(si):
			# (a kept face's segment: its own points)
			for vi in run:
				if not new_of.has(vi):
					new_of[vi] = out_v.size()
					out_v.append(v[vi])
					for cj in on.get(vi, {}):
						add_fv.call(new_of[vi], int(cj), float(on[vi][cj]))
				pts.append(new_of[vi])
			seg_pts.append(pts)
			continue
		var path := PackedVector3Array()
		var tps := PackedFloat32Array()
		var pn := PackedVector3Array()   # (its points' normals: the rim's samples bent round with the surface)
		for vi in run:
			path.append(v[vi])
			tps.append(float(on[vi][ci]))
			pn.append(vnrm.get(vi, Vector3.ZERO))
		if closed_seg:
			path.append(v[run[0]])
			pn.append(vnrm.get(run[0], Vector3.ZERO))
			tps.append(tps[0] + 1.0)
		var lens := PackedFloat32Array([0.0])
		for m in range(1, path.size()):
			lens.append(lens[m - 1] + path[m - 1].distance_to(path[m]))
		if fill_kept:
			for m in range(0 if closed_seg else 1, run.size() if closed_seg else run.size() - 1):
				rim_inner[run[m]] = true
		var total := maxf(lens[lens.size() - 1], 1e-12)
		var count := n if closed_seg else n + 1
		for k in count:
			if not closed_seg and (k == 0 or k == n):
				var jv: int = run[0] if k == 0 else run.back()
				if not new_of.has(jv):
					new_of[jv] = out_v.size()
					out_v.append(v[jv])
					for cj in on[jv]:
						add_fv.call(new_of[jv], int(cj), float(on[jv][cj]))
				pts.append(new_of[jv])
				continue
			var d := total * k / float(n)
			var m := 1
			while m < lens.size() - 1 and lens[m] < d:
				m += 1
			var u := clampf((d - lens[m - 1]) / maxf(lens[m] - lens[m - 1], 1e-12), 0.0, 1.0)
			var q := path[m - 1].lerp(path[m], u)
			if phong_amount > 0.0 and pn[m - 1] != Vector3.ZERO and pn[m] != Vector3.ZERO and pn[m - 1].dot(pn[m]) > cos(deg_to_rad(35.0)):
				# (between its two points: pulled to the curve their normals describe - a round edge round, not chords)
				var qa := q - (q - path[m - 1]).dot(pn[m - 1]) * pn[m - 1]
				var qb := q - (q - path[m]).dot(pn[m]) * pn[m]
				q = q.lerp(qa.lerp(qb, u), phong_amount)
			var tp := lerpf(tps[m - 1], tps[m], u)
			if tp >= 1.0:
				tp -= 1.0
			var nid := out_v.size()
			out_v.append(q)
			add_fv.call(nid, ci, tp)
			pts.append(nid)
			if fill_kept:
				var sk := Vector2i(run[m - 1], run[m % run.size()])
				if not rim_split.has(sk):
					rim_split[sk] = []
				rim_split[sk].append([u, nid, q])
		seg_pts.append(pts)
	# the faces' grids
	var out_t := PackedInt32Array()
	var order := []   # (the fill pass: the faces filled last - after every grid's made, so a grid that fails costs no fill)
	var later := []
	for f in nf:
		if fill_kept and (keep.has(f) or field_fill_all) and not frozen.has(f):
			later.append(f)
		else:
			order.append(f)
	var all_f := order + later
	var tri_total := 0
	for f in all_f:
		tri_total += (f_tris[f] as Array).size()
	var tri_done := 0
	for fi in all_f.size():
		var f: int = all_f[fi]
		if fill_kept:
			# (by triangles: the big faces are the slow ones)
			_prog(0.25 + 0.75 * float(tri_done) / maxf(1.0, tri_total), "laying its faces along their flow")
		tri_done += (f_tris[f] as Array).size()
		if keep.has(f) or (fill_kept and field_fill_all):
			# (a face the templates can't lay out: filled by a field-aligned layout on the points its rim kept
			# (field_remesh) - else its triangles as they were)
			var tried := fill_kept and not frozen.has(f)
			if tried and _fill_kept_face(v, t, f_tris[f], on, new_of, add_fv, out_v, out_t, L, {} if fill_fixed.has(f) else rim_split, {} if fill_fixed.has(f) else rim_inner):
				out_v = fill_out_v
				out_t.append_array(fill_out_t)
				continue
			if tried:
				out_v = fill_out_v   # (the rim points the failed fill kept - new_of points at them; a frozen face: none, and
				# fill_out_v still an earlier face's - never taken)
			if fill_kept and not fill_fixed.has(f) and not frozen.has(f):
				fill_retry.append(f)   # (its rim resampled but no fill: again on its own points - grid_faces_best)
			for ti in f_tris[f]:
				for j in 3:
					var vi := t[ti * 3 + j]
					if not new_of.has(vi):
						new_of[vi] = out_v.size()
						out_v.append(v[vi])
						for cj in on.get(vi, {}):
							add_fv.call(new_of[vi], int(cj), float(on[vi][cj]))
					out_t.append(new_of[vi])
			continue
		var bpts := _loop_pts(f_loops[f], seg_pts, segs)   # the loop's samples, in loop order (each once)
		if f_loops2[f] != null:
			# (a ring-shaped face: rows of quads from one loop to the other)
			var ring := _face_annulus(v, t, f_tris[f], bpts, _loop_pts(f_loops2[f], seg_pts, segs), out_v, L)
			grid_log.append([f, "annulus" if not ring.is_empty() else "annulus failed", bpts.size(), grid_why, "", last_quality, last_counts.duplicate()])
			if ring.is_empty():
				grid_fail = f
				return {}   # (grid_why says why)
			if fill_kept and fill_compare and _fill_wins(v, t, f_tris[f], on, new_of, add_fv, out_v, out_t, L, rim_split, rim_inner, ring, f, fv_out, fv_seen):
				out_v = fill_out_v
				out_t.append_array(fill_out_t)
				continue
			out_v = ring["v"]
			out_t.append_array(ring["t"])
			continue
		var N := bpts.size()
		if N < 4 or N % 2 == 1:
			grid_why = "an odd count round a face"
			grid_fail = f
			return {}
		# the corners: i0, i1, i0 + N/2, i1 + N/2 - as sharp as the boundary's corners allow
		var sharp := PackedFloat32Array()
		sharp.resize(N)
		for k in N:
			var d0 := (out_v[bpts[k]] - out_v[bpts[(k - 1 + N) % N]]).normalized()
			var d1 := (out_v[bpts[(k + 1) % N]] - out_v[bpts[k]]).normalized()
			sharp[k] = d0.angle_to(d1)   # (the samples' own turn - new points)
		var best := -INF
		var bc := [-1, 0]
		var h := N / 2
		var four: Array = f_corners[f]
		if not four.is_empty():
			# (its sharp corners, if their sides balanced: their samples' places in the loop)
			var at_run := []
			var k := 0
			for ri in f_loops[f].size():
				at_run.append(k)
				k += (seg_pts[f_loops[f][ri][0]] as Array).size() - (0 if segs[f_loops[f][ri][0]][2] else 1)
			var c := [at_run[four[0]], at_run[four[1]], at_run[four[2]], at_run[four[3]]]
			if c[1] - c[0] == c[3] - c[2] and c[2] - c[1] == N - c[3] + c[0] and c[1] - c[0] >= 1 and c[2] - c[1] >= 1:
				bc = [c[0], c[1] - c[0]]
		for i0 in 0:
			for a in range(mini(2, h - 1), maxi(h - 1, mini(2, h - 1) + 1)):
				var i1 := (i0 + a) % N
				var cs := [i0, i1, (i0 + h) % N, (i1 + h) % N]
				var sc := 0.0
				for c in cs:
					sc += sharp[c] * 4.0
				sc -= absf(float(a) / h - 0.5) * 0.5   # (square-ish)
				if sc > best:
					best = sc
					bc = [i0, a]
		var grid := {}
		# (the plan: its sharp corners, a virtual one or two added where the rim bends most when that makes
		# fewer poles or squarer quads - a 4-corner plan one grid, 3, 5 or 6 that many round one pole; a
		# round dome: rings)
		var per0 := 0.0
		for k2 in N:
			per0 += out_v[bpts[k2]].distance_to(out_v[bpts[(k2 + 1) % N]])
		var ar0 := 0.0
		for ti in f_tris[f]:
			ar0 += (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]]).length() * 0.5
		var bpos := PackedVector3Array()
		for k2 in N:
			bpos.append(out_v[bpts[k2]])
		var plan := _plan_corners(sharp, N, per0 * per0 / (4.0 * PI * maxf(ar0, 1e-12)), bpos)
		var plan_info := ""
		if plan.size() >= 3:
			var es := []
			var ls := []
			for pi in plan.size():
				var a0: int = plan[pi]
				var b0: int = plan[(pi + 1) % plan.size()]
				es.append((b0 - a0 + N) % N)
				var ln := 0.0
				var kk := a0
				while kk != b0:
					ln += out_v[bpts[kk]].distance_to(out_v[bpts[(kk + 1) % N]])
					kk = (kk + 1) % N
				ls.append(snappedf(ln / L, 0.1))
			plan_info = "counts %s, lengths/L %s, area/L2 %.0f" % [str(es), str(ls), ar0 / (L * L)]
		if plan.size() == 4:
			grid = _face_grid(v, t, f_tris[f], bpts, out_v, plan[0], plan[1] - plan[0], plan[2] - plan[1], L)
			grid_log.append([f, "plan grid" if not grid.is_empty() else "plan grid failed", 4, grid_why, plan_info, last_quality, last_counts.duplicate()])
		elif plan.size() >= 3:
			grid = _face_cc(v, t, f_tris[f], bpts, out_v, plan, L)
			grid_log.append([f, "plan cc" if not grid.is_empty() else "plan cc failed", plan.size(), grid_why, plan_info, last_quality, last_counts.duplicate()])
		var cc: Array = f_cc[f] if f < f_cc.size() and grid.is_empty() else []
		if not cc.is_empty():
			# (3, 5 or 6 corners: that many grids round one pole - the corners' places in the loop)
			var at_run := []
			var k := 0
			for ri in f_loops[f].size():
				at_run.append(k)
				k += (seg_pts[f_loops[f][ri][0]] as Array).size() - (0 if segs[f_loops[f][ri][0]][2] else 1)
			grid = _face_cc(v, t, f_tris[f], bpts, out_v, cc.map(func(x): return at_run[x]), L)
			grid_log.append([f, "cc" if not grid.is_empty() else "cc failed", cc.size(), grid_why])
		if grid.is_empty() and bc[0] >= 0 and plan.size() != 4:
			grid = _face_grid(v, t, f_tris[f], bpts, out_v, bc[0], bc[1], h - bc[1], L)
			grid_log.append([f, "grid" if not grid.is_empty() else "grid failed", 4, grid_why])
		if grid.is_empty():
			var per := 0.0
			for k2 in bpts.size():
				per += out_v[bpts[k2]].distance_to(out_v[bpts[(k2 + 1) % bpts.size()]])
			var ar := 0.0
			for ti in f_tris[f]:
				ar += (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]]).length() * 0.5
			grid_log.append([f, "rings", "%d corners, %d runs, %s, round %.1f" % [int(f_ncand[f]), (f_loops[f] as Array).size(), "ring" if f_loops2[f] != null else "disc", per * per / (4.0 * PI * maxf(ar, 1e-12))], grid_why])
		if grid.is_empty() and per0 * per0 / (4.0 * PI * maxf(ar0, 1e-12)) > 1.6 and plan.size() >= 3:
			# (rings only suit a round face - a long or many-cornered one whose plan failed is better kept as
			# it was than wound round a circle)
			grid_fail = f
			return {}
		if grid.is_empty():
			grid = _face_rings(v, t, f_tris[f], bpts, out_v, L)   # (not four balanced corners - or not an even grid: rings)
			if not grid.is_empty():
				grid_log.append([f, "rings made", 0, "", "", last_quality, last_counts.duplicate()])
		if grid.is_empty():
			grid_fail = f
			return {}   # (grid_why says why)
		if fill_kept and fill_compare and _fill_wins(v, t, f_tris[f], on, new_of, add_fv, out_v, out_t, L, rim_split, rim_inner, grid, f, fv_out, fv_seen):
			out_v = fill_out_v
			out_t.append_array(fill_out_t)
			continue
		out_v = grid["v"]   # (its inner points added - a packed array comes back, not changed in place)
		out_t.append_array(grid["t"])
	return {"v": out_v, "t": out_t, "fv": fv_out}


## (grid_faces, the fill pass) The field-aligned fill tried on a face the templates laid out (`grid`: {v, t}):
## true - it scores better by fill_margin (fill_out_v / fill_out_t hold it); else everything as it was.
static func _fill_wins(v: PackedVector3Array, t: PackedInt32Array, tris: Array, on: Dictionary, new_of: Dictionary, add_fv: Callable, out_v: PackedVector3Array, out_t: PackedInt32Array, L: float, rim_split: Dictionary, rim_inner: Dictionary, grid: Dictionary, f: int, fv_out: Array, fv_seen: Dictionary) -> bool:
	var gs := _local_score(grid["v"], grid["t"])
	if gs >= fill_skip_above:
		return false   # (a grid already that clean: kept, no fill tried)
	var had := new_of.duplicate()
	var fv_had := fv_out.size()
	if _fill_kept_face(v, t, tris, on, new_of, add_fv, out_v, out_t, L, rim_split, rim_inner):
		var fs := _local_score(fill_out_v, fill_out_t)
		grid_log.append([f, "fill vs grid", 0, "", "", "fill %.1f grid %.1f" % [fs, gs], [0, 0, 0]])
		if fs > gs + fill_margin:
			fill_won += 1
			return true
	if new_of.size() != had.size():
		new_of.clear()   # (rim points the fill added: gone with it)
		new_of.merge(had)
	for i in range(fv_had, fv_out.size()):
		fv_seen.erase(str(fv_out[i][0]) + "_" + str(fv_out[i][1]))   # (and their places on the edges - else they'd
	fv_out.resize(fv_had)   # name points the grid gives other ids, or none)
	return false


## (grid_faces) A face's layout scored on its own (topo_score: its rim samples count as edge points): triangles
## `tt` (vertex ids into vv).
static func _local_score(vv: PackedVector3Array, tt: PackedInt32Array) -> float:
	var loc := {}
	var lv := PackedVector3Array()
	var lt := PackedInt32Array()
	for x in tt:
		if not loc.has(x):
			loc[x] = lv.size()
			lv.append(vv[x])
		lt.append(loc[x])
	var fv := []
	# (the rim's points: edge points)
	var cnt := {}
	for i in range(0, lt.size(), 3):
		for j in 3:
			var a := lt[i + j]
			var b := lt[i + (j + 1) % 3]
			var k := Vector2i(mini(a, b), maxi(a, b))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var seen := {}
	for e in fv:
		seen[e[0]] = true
	for k: Vector2i in cnt:
		if int(cnt[k]) == 1:
			for x in [k.x, k.y]:
				if not seen.has(x):
					seen[x] = true
					fv.append([x, 0, 0.0])
	var TS: GDScript = load("res://scripts/editor/mesh/topo_score.gd")
	var pt0 := Time.get_ticks_usec()
	var sc := float(TS.score(lv, lt, fv, [{"id": 0, "closed": true}])["score"])
	prof["local_score"] = float(prof.get("local_score", 0.0)) + (Time.get_ticks_usec() - pt0) / 1000.0
	return sc


static func _rev(ps: Array, closed: bool) -> Array:
	var r := ps.duplicate()
	r.reverse()
	if closed:
		# (a loop the other way round, from the same first point)
		r.push_front(r.pop_back())
	return r


## (grid_faces) One face's grid: the face's triangles `tris` of v / t mapped onto a square (its boundary
## samples `bpts` - vertices of out_v - along its sides: na from bpts[i0], nb, na, nb), a grid of na x nb
## quads laid there and mapped back onto the face. {t, v: out_v with its inner points added} ({} - none).
static func _face_grid(v: PackedVector3Array, t: PackedInt32Array, tris: Array, bpts: Array, out_v: PackedVector3Array, i0: int, na: int, nb: int, L: float) -> Dictionary:
	var N := bpts.size()
	# (a face whose boundary is short for its size - a dome round a small rim - can't be one even grid: its
	# rows end on the boundary. Not made so: {})
	var area := 0.0
	for ti in tris:
		area += (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]]).length() * 0.5
	if float(na * nb) < 0.5 * area / (L * L) and mini(na, nb) > 3:   # (a strip: its width is its width)
		grid_why = "too coarse: %d x %d for %.0f" % [na, nb, area / (L * L)]
		return {}
	# the face's own vertices; its boundary loop (old vertices) by place along the samples
	var verts := {}
	for ti in tris:
		for j in 3:
			verts[t[ti * 3 + j]] = true
	var cnt := {}
	for ti in tris:
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			cnt[k] = int(cnt.get(k, 0)) + 1
	var bnd := {}
	var nbrs := {}
	for ti in tris:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			if int(cnt[_pk(a, b)]) == 1:
				bnd[a] = true
				bnd[b] = true
			if not nbrs.has(a):
				nbrs[a] = {}
			if not nbrs.has(b):
				nbrs[b] = {}
			nbrs[a][b] = true
			nbrs[b][a] = true
	# each sample's place on a rectangle shaped like the grid (na by nb - a unit square squeezes a long face
	# and its points miss it): side 0 along u from (0, 0), side 1 up v, ...
	var rx := float(na) / maxi(na, nb)
	var ry := float(nb) / maxi(na, nb)
	var sq := PackedVector2Array()
	sq.resize(N)
	for k in N:
		var r := (k - i0 + N) % N
		if r <= na:
			sq[k] = Vector2(float(r) / na * rx, 0.0)
		elif r <= na + nb:
			sq[k] = Vector2(rx, float(r - na) / nb * ry)
		elif r <= 2 * na + nb:
			sq[k] = Vector2((1.0 - float(r - na - nb) / na) * rx, ry)
		else:
			sq[k] = Vector2(0.0, (1.0 - float(r - 2 * na - nb) / nb) * ry)
	# the old rim's points placed along the new rim by how far along it they are
	var rp := _rim_places(v, t, tris, bpts, out_v)
	var uv := {}
	for vi in bnd:
		if rp.has(vi):
			var kk := int(rp[vi].x)
			uv[vi] = sq[kk].lerp(sq[(kk + 1) % N], rp[vi].y)
		else:
			var q := v[vi]
			var bestd := INF
			var place := Vector2.ZERO
			for k in N:
				var a := out_v[bpts[k]]
				var b := out_v[bpts[(k + 1) % N]]
				var ab := b - a
				var s := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-18), 0.0, 1.0)
				var d := (a + ab * s).distance_squared_to(q)
				if d < bestd:
					bestd = d
					place = sq[k].lerp(sq[(k + 1) % N], s)
			uv[vi] = place   # (a hole's rim: by nearness)
	# the inside: by cotangent weights (a plain average warps an uneven triangulation)
	_harmonic_cot(v, t, tris, bnd, uv)
	# the face's triangles in the square, bucketed for finding the one under a grid point
	var B := 24
	var buckets := {}
	for ti in tris:
		var a: Vector2 = uv[t[ti * 3]]
		var b: Vector2 = uv[t[ti * 3 + 1]]
		var c: Vector2 = uv[t[ti * 3 + 2]]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		for bx in range(clampi(int(lo.x * B), 0, B - 1), clampi(int(hi.x * B), 0, B - 1) + 1):
			for by in range(clampi(int(lo.y * B), 0, B - 1), clampi(int(hi.y * B), 0, B - 1) + 1):
				var key := bx * B + by
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(ti)
	var fnrm := _face_normals(v, t, tris)
	var surf := func(p: Vector2) -> Vector3:
		var key := clampi(int(p.x * B), 0, B - 1) * B + clampi(int(p.y * B), 0, B - 1)
		var best_ti := -1
		var best_w := Vector3.ZERO
		var best_out := INF
		for ti in buckets.get(key, []):
			var a: Vector2 = uv[t[ti * 3]]
			var b: Vector2 = uv[t[ti * 3 + 1]]
			var c: Vector2 = uv[t[ti * 3 + 2]]
			var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
			if absf(den) < 1e-20:
				continue
			var w0 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
			var w1 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
			var w2 := 1.0 - w0 - w1
			var outside := maxf(0.0, -minf(w0, minf(w1, w2)))
			if outside < best_out:
				best_out = outside
				best_ti = ti
				best_w = Vector3(w0, w1, w2)
		if best_ti < 0:
			return Vector3.INF
		var w := best_w.clamp(Vector3.ZERO, Vector3.ONE)
		w /= maxf(w.x + w.y + w.z, 1e-12)
		return _on_surface(v, t, best_ti, w, fnrm)   # (on the smooth surface, not its facets)
	# the grid's points: its border the samples, its inside mapped back
	var gid := func(i: int, j: int) -> int:
		if j == 0:
			return bpts[(i0 + i) % N]
		if i == na:
			return bpts[(i0 + na + j) % N]
		if j == nb:
			return bpts[(i0 + na + nb + (na - i)) % N]
		if i == 0:
			return bpts[(i0 + 2 * na + nb + (nb - j)) % N]
		return -1
	var inner_id := {}
	for i in range(1, na):
		for j in range(1, nb):
			var q: Vector3 = surf.call(Vector2(float(i) / na * rx, float(j) / nb * ry))
			if q == Vector3.INF:
				var ulo := Vector2(INF, INF)
				var uhi := -ulo
				for vi in uv:
					ulo = ulo.min(uv[vi])
					uhi = uhi.max(uv[vi])
				grid_why = "a grid point off the face (%d, %d of %d x %d; map %s..%s; %d tris, %d inner)" % [i, j, na, nb, str(ulo), str(uhi), tris.size(), uv.size() - bnd.size()]
				return {}
			inner_id[i * (nb + 1) + j] = out_v.size()
			out_v.append(q)
	var at := func(i: int, j: int) -> int:
		var g: int = gid.call(i, j)
		return g if g >= 0 else int(inner_id[i * (nb + 1) + j])
	# facing: as the face's own triangles do
	var fn := Vector3.ZERO
	for ti in tris:
		fn += (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]])
	var gn := Vector3.ZERO
	var quads := []
	for i in na:
		for j in nb:
			var q4 := [at.call(i, j), at.call(i + 1, j), at.call(i + 1, j + 1), at.call(i, j + 1)]
			quads.append(q4)
			gn += (out_v[q4[1]] - out_v[q4[0]]).cross(out_v[q4[2]] - out_v[q4[0]])
	var flip := gn.dot(fn) < 0.0
	# (even: no quad over four times the face's mean size - else it isn't an even layout)
	var mean := area / maxf(quads.size(), 1)
	for q4 in quads:
		var qa: float = ((out_v[q4[1]] - out_v[q4[0]]).cross(out_v[q4[2]] - out_v[q4[0]]).length() + (out_v[q4[2]] - out_v[q4[0]]).cross(out_v[q4[3]] - out_v[q4[0]]).length()) * 0.5
		if qa > mean * uneven_limit and mini(na, nb) > 2:   # (a strip a quad or two wide: uneven as its width is - still far better than rings)
			grid_why = "uneven: a quad %.1f x the mean, %d x %d grid, area %.3f, N %d" % [qa / mean, na, nb, area, N]
			return {}
	_note_quality(out_v, quads)
	var out := PackedInt32Array()
	for q4 in quads:
		var a: int = q4[0]
		var b: int = q4[1]
		var c: int = q4[2]
		var d: int = q4[3]
		if flip:
			var tmp := b
			b = d
			d = tmp
		# (split along a diagonal inside it, both triangles facing its way - the longer when both are)
		var qn := (out_v[c] - out_v[a]).cross(out_v[b] - out_v[d])
		var ac_ok := _tri_face(out_v, a, b, c).dot(qn) > 0.0 and _tri_face(out_v, a, c, d).dot(qn) > 0.0
		var bd_ok := _tri_face(out_v, a, b, d).dot(qn) > 0.0 and _tri_face(out_v, b, c, d).dot(qn) > 0.0
		var use_ac := out_v[a].distance_squared_to(out_v[c]) >= out_v[b].distance_squared_to(out_v[d])
		if use_ac and not ac_ok and bd_ok:
			use_ac = false
		elif not use_ac and not bd_ok and ac_ok:
			use_ac = true
		if use_ac:
			out.append_array(PackedInt32Array([a, b, c, a, c, d]))
		else:
			out.append_array(PackedInt32Array([a, b, d, b, c, d]))
	return {"t": out, "v": out_v}


## (grid_faces) A face that isn't one even grid - a dome round a small rim, a face of many corners: rings of
## quads following its boundary inwards (as many as its size needs), and a grid of quads filling the middle.
## The face mapped onto a disc (its boundary samples on the circle by length, its inside by a harmonic map,
## then evened out by area - a dome's far side isn't squeezed into the middle); the rings' points between the
## boundary's and the middle grid's edge. {t, v: out_v with its new points} ({} - none).
static func _face_rings(v: PackedVector3Array, t: PackedInt32Array, tris: Array, bpts: Array, out_v: PackedVector3Array, L: float) -> Dictionary:
	var N := bpts.size()
	if N < 4 or N % 2 == 1:
		grid_why = "rings: an odd count round a face"
		return {}
	var fl := _face_local(t, tris)
	var bnd: Dictionary = fl["bnd"]
	var nbrs: Dictionary = fl["nbrs"]
	# the boundary samples round the circle, by length
	var cum := PackedFloat64Array([0.0])
	for k in N:
		cum.append(cum[k] + out_v[bpts[k]].distance_to(out_v[bpts[(k + 1) % N]]))
	var per := maxf(cum[N], 1e-12)
	var ang := PackedFloat64Array()
	for k in N:
		ang.append(TAU * cum[k] / per)
	var uv := {}
	for vi in bnd:
		var q := v[vi]
		var bestd := INF
		var a := 0.0
		for k in N:
			var p0 := out_v[bpts[k]]
			var p1 := out_v[bpts[(k + 1) % N]]
			var ab := p1 - p0
			var s := clampf((q - p0).dot(ab) / maxf(ab.length_squared(), 1e-18), 0.0, 1.0)
			var d := (p0 + ab * s).distance_squared_to(q)
			if d < bestd:
				bestd = d
				a = ang[k] + (TAU * (cum[k + 1] - cum[k]) / per) * s
		uv[vi] = Vector2(cos(a), sin(a))
	_harmonic_cot(v, t, tris, bnd, uv)
	# evened out by area: each point's radius r made sqrt(the share of the face's area nearer the middle)
	var tr := []
	var area := 0.0
	for ti in tris:
		var a3 := (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]]).length() * 0.5
		var c2: Vector2 = ((uv[t[ti * 3]] as Vector2) + (uv[t[ti * 3 + 1]] as Vector2) + (uv[t[ti * 3 + 2]] as Vector2)) / 3.0
		tr.append([c2.length(), a3])
		area += a3
	tr.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var rs := PackedFloat64Array([0.0])
	var fs := PackedFloat64Array([0.0])
	var acc := 0.0
	for e in tr:
		acc += float(e[1])
		rs.append(float(e[0]))
		fs.append(acc / maxf(area, 1e-18))
	rs.append(1.0)
	fs.append(1.0)
	for vi in uv:
		var p: Vector2 = uv[vi]
		var r := p.length()
		if r < 1e-12:
			continue
		var j := rs.bsearch(r)
		j = clampi(j, 1, rs.size() - 1)
		var w := clampf((r - rs[j - 1]) / maxf(rs[j] - rs[j - 1], 1e-12), 0.0, 1.0)
		var f := lerpf(fs[j - 1], fs[j], w)
		uv[vi] = p / r * sqrt(clampf(f, 0.0, 1.0))
	var look := _uv_index(t, tris, uv, Vector2(-1.05, -1.05), Vector2(1.05, 1.05), 32)
	look["nrm"] = _face_normals(v, t, tris)
	# the layout: a middle grid m1 x m2 (its edge N points), R rings round it
	var m1 := int(ceil(N / 4.0))
	var m2 := N / 2 - m1
	if m2 < 1:
		grid_why = "rings: too few points round a face"
		return {}
	var sp3 := per / N   # (the boundary's spacing on the surface: the quads' size)
	var len3 := func(p0: Vector2, p1: Vector2, n: int) -> float:
		var tot := 0.0
		var last = null
		for i in n + 1:
			var h: Array = _uv_at(v, t, uv, look, p0.lerp(p1, float(i) / n))
			if h.is_empty():
				continue
			if last != null:
				tot += (h[0] as Vector3).distance_to(last)
			last = h[0]
		return tot
	# (the middle grid sized on the surface: its quads about the boundary's spacing across)
	var hw := 0.3
	var hh := 0.3 * m2 / float(m1)
	for it in 4:
		var w3: float = len3.call(Vector2(-hw, -hh), Vector2(hw, -hh), 12)
		var h3: float = len3.call(Vector2(-hw, -hh), Vector2(-hw, hh), 12)
		if w3 > 1e-9:
			hw *= clampf(m1 * sp3 / w3, 0.5, 2.0)
		if h3 > 1e-9:
			hh *= clampf(m2 * sp3 / h3, 0.5, 2.0)
		var dg := sqrt(hw * hw + hh * hh)
		if dg > 0.8:
			hw *= 0.8 / dg
			hh *= 0.8 / dg
	# its edge's points, round from a corner the same way as the boundary (counter-clockwise)
	var rect := PackedVector2Array()
	for i in m1:
		rect.append(Vector2(-hw + 2.0 * hw * i / m1, -hh))
	for i in m2:
		rect.append(Vector2(hw, -hh + 2.0 * hh * i / m2))
	for i in m1:
		rect.append(Vector2(hw - 2.0 * hw * i / m1, hh))
	for i in m2:
		rect.append(Vector2(-hw, hh - 2.0 * hh * i / m2))
	# the boundary sample each edge point faces (the best turn of one against the other)
	var best_o := 0
	var best_s := INF
	for o in N:
		var s := 0.0
		for k in N:
			var ra := atan2(rect[k].y, rect[k].x)
			var d := absf(wrapf(ang[(k + o) % N] - ra, -PI, PI))
			s += d
		if s < best_s:
			best_s = s
			best_o = o
	var rim2 := PackedVector2Array()
	var rim_id := []
	for k in N:
		var a := ang[(k + best_o) % N]
		rim2.append(Vector2(cos(a), sin(a)))
		rim_id.append(bpts[(k + best_o) % N])
	# the rings: as many as make their rows about the boundary's spacing deep; each spoke (a boundary sample
	# to its middle-edge point) cut at equal lengths on the surface - the rows even, not the map's
	var SS := 32
	var spokes := []   # each: [map places, lengths along it]
	var mean_len := 0.0
	for k in N:
		var ps := PackedVector2Array()
		var ls := PackedFloat64Array([0.0])
		var last = null
		for i in SS + 1:
			var pp := rim2[k].lerp(rect[k], float(i) / SS)
			var h: Array = _uv_at(v, t, uv, look, pp)
			ps.append(pp)
			if i > 0:
				ls.append(ls[i - 1] + ((h[0] as Vector3).distance_to(last) if not h.is_empty() and last != null else 0.0))
			if not h.is_empty():
				last = h[0]
		spokes.append([ps, ls])
		mean_len += ls[SS]
	mean_len /= N
	var R := maxi(0, roundi(mean_len / sp3) - 1)
	var nv := out_v
	var levels := [rim_id]
	var miss := false
	for j in range(1, R + 2):
		var lev := []
		for k in N:
			var ps: PackedVector2Array = spokes[k][0]
			var ls: PackedFloat64Array = spokes[k][1]
			var want_l := ls[SS] * float(j) / (R + 1)
			var i := clampi(ls.bsearch(want_l), 1, SS)
			var w := clampf((want_l - ls[i - 1]) / maxf(ls[i] - ls[i - 1], 1e-12), 0.0, 1.0)
			var p := ps[i - 1].lerp(ps[i], w) if j <= R else rect[k]
			var hit: Array = _uv_at(v, t, uv, look, p)
			if hit.is_empty():
				miss = true
				break
			lev.append(nv.size())
			nv.append(hit[0])
		if miss:
			break
		levels.append(lev)
	if miss:
		grid_why = "rings: a point off the face"
		return {}
	var edge: Array = levels.back()   # (the middle grid's edge: N points, from the corner (-hw, -hh))
	var gid := {}
	var g := func(i: int, j: int) -> int:
		if j == 0:
			return edge[i]
		if i == m1:
			return edge[m1 + j]
		if j == m2:
			return edge[m1 + m2 + (m1 - i)]
		if i == 0:
			return edge[2 * m1 + m2 + (m2 - j)] if j > 0 else edge[0]
		return int(gid[i * (m2 + 1) + j])
	for i in range(1, m1):
		for j in range(1, m2):
			var p := Vector2(-hw + 2.0 * hw * i / m1, -hh + 2.0 * hh * j / m2)
			var hit: Array = _uv_at(v, t, uv, look, p)
			if hit.is_empty():
				grid_why = "rings: a middle point off the face"
				return {}
			gid[i * (m2 + 1) + j] = nv.size()
			nv.append(hit[0])
	var quads := []
	for j in levels.size() - 1:
		var a: Array = levels[j]
		var b: Array = levels[j + 1]
		for k in N:
			quads.append([a[k], a[(k + 1) % N], b[(k + 1) % N], b[k]])
	for i in m1:
		for j in m2:
			quads.append([g.call(i, j), g.call(i + 1, j), g.call(i + 1, j + 1), g.call(i, j + 1)])
	return _quads_out(v, t, uv, look, nv, quads, tris)


## (grid_faces) The face's local make-up: its vertices' neighbours and which are on its boundary.
static func _face_local(t: PackedInt32Array, tris: Array) -> Dictionary:
	var cnt := {}
	for ti in tris:
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			cnt[k] = int(cnt.get(k, 0)) + 1
	var bnd := {}
	var nbrs := {}
	for ti in tris:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			if int(cnt[_pk(a, b)]) == 1:
				bnd[a] = true
				bnd[b] = true
			if not nbrs.has(a):
				nbrs[a] = {}
			if not nbrs.has(b):
				nbrs[b] = {}
			nbrs[a][b] = true
			nbrs[b][a] = true
	return {"bnd": bnd, "nbrs": nbrs}


## (grid_faces) The face's inner points placed each at its neighbours' middle - a harmonic map, `uv` holding
## the boundary's places (conjugate gradients, both axes).
static func _harmonic(nbrs: Dictionary, bnd: Dictionary, uv: Dictionary) -> void:
	var inner := []
	var idx := {}
	for vi in nbrs:
		if not bnd.has(vi):
			idx[vi] = inner.size()
			inner.append(vi)
	var n_in := inner.size()
	if n_in == 0:
		return
	for axis in 2:
		var bvec := PackedFloat64Array()
		bvec.resize(n_in)
		for i in n_in:
			var s := 0.0
			for o in nbrs[inner[i]]:
				if bnd.has(o):
					s += (uv[o] as Vector2)[axis]
			bvec[i] = s
		var x := PackedFloat64Array()
		x.resize(n_in)
		var apply := func(p: PackedFloat64Array) -> PackedFloat64Array:
			var o2 := PackedFloat64Array()
			o2.resize(n_in)
			for i in n_in:
				var nb2: Dictionary = nbrs[inner[i]]
				var s := float(nb2.size()) * p[i]
				for o in nb2:
					if idx.has(o):
						s -= p[idx[o]]
				o2[i] = s
			return o2
		var r := bvec.duplicate()
		var p := r.duplicate()
		var rr := 0.0
		for i in n_in:
			rr += r[i] * r[i]
		for it in 800:
			if rr < 1e-16:
				break
			var ap: PackedFloat64Array = apply.call(p)
			var pap := 0.0
			for i in n_in:
				pap += p[i] * ap[i]
			if absf(pap) < 1e-30:
				break
			var al := rr / pap
			var rr2 := 0.0
			for i in n_in:
				x[i] += al * p[i]
				r[i] -= al * ap[i]
				rr2 += r[i] * r[i]
			var be := rr2 / rr
			rr = rr2
			for i in n_in:
				p[i] = r[i] + be * p[i]
		for i in n_in:
			var cur: Vector2 = uv.get(inner[i], Vector2.ZERO)
			cur[axis] = x[i]
			uv[inner[i]] = cur


## (grid_faces) The face's triangles in its map, bucketed: {lo, hi, B, cells}.
static func _uv_index(t: PackedInt32Array, tris: Array, uv: Dictionary, lo: Vector2, hi: Vector2, B: int) -> Dictionary:
	var cells := {}
	var sz := hi - lo
	for ti in tris:
		var a: Vector2 = uv[t[ti * 3]]
		var b: Vector2 = uv[t[ti * 3 + 1]]
		var c: Vector2 = uv[t[ti * 3 + 2]]
		var l := (a.min(b).min(c) - lo) / sz
		var h := (a.max(b).max(c) - lo) / sz
		for bx in range(clampi(int(l.x * B), 0, B - 1), clampi(int(h.x * B), 0, B - 1) + 1):
			for by in range(clampi(int(l.y * B), 0, B - 1), clampi(int(h.y * B), 0, B - 1) + 1):
				var key := bx * B + by
				if not cells.has(key):
					cells[key] = []
				cells[key].append(ti)
	return {"lo": lo, "hi": hi, "B": B, "cells": cells}


## (grid_faces) The surface point at map place `p`: [point, triangle] ([] - off the face).
static func _uv_at(v: PackedVector3Array, t: PackedInt32Array, uv: Dictionary, look: Dictionary, p: Vector2) -> Array:
	var B: int = look["B"]
	var q := (p - (look["lo"] as Vector2)) / ((look["hi"] as Vector2) - (look["lo"] as Vector2))
	var key := clampi(int(q.x * B), 0, B - 1) * B + clampi(int(q.y * B), 0, B - 1)
	var best_ti := -1
	var best_w := Vector3.ZERO
	var best_out := INF
	for ti in (look["cells"] as Dictionary).get(key, []):
		var a: Vector2 = uv[t[ti * 3]]
		var b: Vector2 = uv[t[ti * 3 + 1]]
		var c: Vector2 = uv[t[ti * 3 + 2]]
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-20:
			continue
		var w0 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
		var w1 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
		var w2 := 1.0 - w0 - w1
		var outside := maxf(0.0, -minf(w0, minf(w1, w2)))
		if outside < best_out:
			best_out = outside
			best_ti = ti
			best_w = Vector3(w0, w1, w2)
	if best_ti < 0 or best_out > 0.05:
		return []
	var w := best_w.clamp(Vector3.ZERO, Vector3.ONE)
	w /= maxf(w.x + w.y + w.z, 1e-12)
	return [_on_surface(v, t, best_ti, w, look.get("nrm", {})), best_ti]


## A point of triangle `ti` (weights `w`) on the smooth surface its corners' normals describe (Phong
## tessellation: the flat point pulled to each corner's tangent plane, blended) - a finer grid laid over a
## coarse face isn't left on its flat facets, creased where they meet. `nrm`: {vertex: normal} ({} - flat).
static func _on_surface(v: PackedVector3Array, t: PackedInt32Array, ti: int, w: Vector3, nrm: Dictionary) -> Vector3:
	var a := t[ti * 3]
	var b := t[ti * 3 + 1]
	var c := t[ti * 3 + 2]
	var p := v[a] * w.x + v[b] * w.y + v[c] * w.z
	if nrm.is_empty() or not (nrm.has(a) and nrm.has(b) and nrm.has(c)):
		return p
	var na: Vector3 = nrm[a]
	var nb: Vector3 = nrm[b]
	var nc: Vector3 = nrm[c]
	var lim := cos(deg_to_rad(35.0))
	if na.dot(nb) < lim or nb.dot(nc) < lim or na.dot(nc) < lim:
		return p   # (a sharp bend inside the face, not one of its edges: left as it is - rounding it would bulge)
	var pa := p - (p - v[a]).dot(na) * na
	var pb := p - (p - v[b]).dot(nb) * nb
	var pc := p - (p - v[c]).dot(nc) * nc
	var ph := pa * w.x + pb * w.y + pc * w.z
	return p.lerp(ph, phong_amount)


## A face's vertex normals, its own triangles only (smooth across the face, its edges left sharp): each the
## triangles round it by their angle there. {vertex: normal}.
static func _face_normals(v: PackedVector3Array, t: PackedInt32Array, tris: Array) -> Dictionary:
	var out := {}
	for ti in tris:
		var ia := t[ti * 3]
		var ib := t[ti * 3 + 1]
		var ic := t[ti * 3 + 2]
		var n := (v[ic] - v[ia]).cross(v[ib] - v[ia])
		if n.length_squared() < 1e-30:
			continue
		n = n.normalized()
		var ids := [ia, ib, ic]
		for j in 3:
			var p0 := v[ids[j]]
			var e1 := v[ids[(j + 1) % 3]] - p0
			var e2 := v[ids[(j + 2) % 3]] - p0
			var ang := e1.angle_to(e2) if e1.length_squared() > 1e-30 and e2.length_squared() > 1e-30 else 0.0
			out[ids[j]] = (out.get(ids[j], Vector3.ZERO) as Vector3) + n * ang
	for k in out:
		out[k] = (out[k] as Vector3).normalized()
	return out


## (grid_faces) Quads [a, b, c, d] (round the same way in the map) as triangles facing as the surface under
## each does, each split along its longer diagonal; {} when many would turn over (a folded layout).
static func _quads_out(v: PackedVector3Array, t: PackedInt32Array, _uv: Dictionary, _look: Dictionary, nv: PackedVector3Array, quads: Array, tris: Array) -> Dictionary:
	# (which way round: the surface's own facing, by how most quads agree with the triangles nearest them)
	var fn := Vector3.ZERO
	var agree := 0
	var disagree := 0
	var cen := PackedVector3Array()
	for ti in tris:
		cen.append((v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0)
	var step := maxi(1, quads.size() / 200)
	for qi in range(0, quads.size(), step):
		var q4: Array = quads[qi]
		var qc := (nv[q4[0]] + nv[q4[1]] + nv[q4[2]] + nv[q4[3]]) / 4.0
		var qn := (nv[q4[2]] - nv[q4[0]]).cross(nv[q4[3]] - nv[q4[1]])
		var bi := 0
		var bd := INF
		for k in cen.size():
			var d := cen[k].distance_squared_to(qc)
			if d < bd:
				bd = d
				bi = k
		var ti: int = tris[bi]
		var tn := (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]])
		if qn.dot(tn) >= 0.0:
			agree += 1
		else:
			disagree += 1
	var flip := disagree > agree
	_note_quality(nv, quads)
	if mini(agree, disagree) * 10 > agree + disagree:
		grid_why = "a layout that folds (%d of %d quads turned over)" % [mini(agree, disagree), agree + disagree]
		return {}
	var out := PackedInt32Array()
	for q4 in quads:
		var a: int = q4[0]
		var b: int = q4[1]
		var c: int = q4[2]
		var d: int = q4[3]
		if flip:
			var tmp := b
			b = d
			d = tmp
		# (split along a diagonal inside the quad - both triangles facing its way; of two such, the longer:
		# a dented quad's longer diagonal runs outside it and turns one triangle over)
		var qn := (nv[c] - nv[a]).cross(nv[b] - nv[d])
		var ac_ok := _tri_face(nv, a, b, c).dot(qn) > 0.0 and _tri_face(nv, a, c, d).dot(qn) > 0.0
		var bd_ok := _tri_face(nv, a, b, d).dot(qn) > 0.0 and _tri_face(nv, b, c, d).dot(qn) > 0.0
		var use_ac := nv[a].distance_squared_to(nv[c]) >= nv[b].distance_squared_to(nv[d])
		if use_ac and not ac_ok and bd_ok:
			use_ac = false
		elif not use_ac and not bd_ok and ac_ok:
			use_ac = true
		if use_ac:
			out.append_array(PackedInt32Array([a, b, c, a, c, d]))
		else:
			out.append_array(PackedInt32Array([a, b, d, b, c, d]))
	return {"t": out, "v": nv}


## A triangle's facing (as the mesh draws it: Godot's front faces wind the other way round).
static func _tri_face(nv: PackedVector3Array, a: int, b: int, c: int) -> Vector3:
	return (nv[c] - nv[a]).cross(nv[b] - nv[a])



## (grid_faces) A boundary loop as runs of segments, from a junction (or one closed segment as it is):
## [[segment, forward]...] ([] - grid_why says why).
static func _walk_loop(loop: Array, junction: Dictionary, edge_seg: Dictionary, segs: Array) -> Array:
	var j0 := -1
	for m in loop.size():
		if junction.has(loop[m]):
			j0 = m
			break
	var runs := []
	if j0 < 0:
		var es = edge_seg.get(str(loop[0]) + "_" + str(loop[1]))
		if es == null or not segs[es[0]][2]:
			grid_why = "a loop not one closed edge"
			return []
		runs.append(es)
		return runs
	var m := 0
	while m < loop.size():
		var a: int = loop[(j0 + m) % loop.size()]
		var b: int = loop[(j0 + m + 1) % loop.size()]
		var es = edge_seg.get(str(a) + "_" + str(b))
		if es == null:
			grid_why = "a boundary edge on no chain"
			no_chain_side = [a, b, junction.has(a), junction.has(b)]
			return []
		runs.append(es)
		m += (segs[es[0]][0] as Array).size() - 1
	return runs


## (grid_faces) A loop's samples in its order, each once.
static func _loop_pts(runs: Array, seg_pts: Array, segs: Array) -> Array:
	var out := []
	for r in runs:
		var ps: Array = seg_pts[r[0]]
		var seq: Array = ps.duplicate() if r[1] else _rev(ps, segs[r[0]][2])
		if segs[r[0]][2]:
			out.append_array(seq)
		else:
			out.append_array(seq.slice(0, seq.size() - 1))
	return out


## (grid_faces) A ring-shaped face - between two loops of the same count: rows of quads running round it,
## each sample of one loop joined to its partner on the other (the pairing that doesn't twist), the rows
## at equal lengths along those joins on the surface. The face mapped onto a flat ring for that (loop A on
## the outer circle, B on the inner, a harmonic map between). {t, v} ({} - none).
static func _face_annulus(v: PackedVector3Array, t: PackedInt32Array, tris: Array, ba: Array, bb: Array, out_v: PackedVector3Array, L: float) -> Dictionary:
	var N := ba.size()
	if N < 3 or bb.size() != N:
		grid_why = "a ring-shaped face whose loops' counts differ (%d, %d)" % [N, bb.size()]
		return {}
	# the pairing: B's sample for A's k - an offset and a way round, the nearest overall
	var best := INF
	var bo := 0
	var bdir := 1
	for dir in [1, -1]:
		for o in N:
			var sd := 0.0
			for k in N:
				sd += out_v[ba[k]].distance_to(out_v[bb[(o + dir * k + N * 2) % N]])
			if sd < best:
				best = sd
				bo = o
				bdir = dir
	var bpair := []
	for k in N:
		bpair.append(bb[(bo + bdir * k + N * 2) % N])
	var fl := _face_local(t, tris)
	var bnd: Dictionary = fl["bnd"]
	var nbrs: Dictionary = fl["nbrs"]
	# A round the outer circle by length; B's partners at the same angles on the inner one
	var cum := PackedFloat64Array([0.0])
	for k in N:
		cum.append(cum[k] + out_v[ba[k]].distance_to(out_v[ba[(k + 1) % N]]))
	var per := maxf(cum[N], 1e-12)
	var rho := 0.45
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for k in N:
		var a := TAU * cum[k] / per
		pa.append(Vector2(cos(a), sin(a)))
		pb.append(Vector2(cos(a), sin(a)) * rho)
	# the face's own rims: each old loop on the new loop it lies along (as a whole - point by point, a
	# narrow band's points could land on the wrong one and fold the map), placed along it by length
	var uv := {}
	var cnt := {}
	for ti in tris:
		for j in 3:
			var k2 := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			cnt[k2] = int(cnt.get(k2, 0)) + 1
	var nxt := {}
	for ti in tris:
		for j in 3:
			var a2 := t[ti * 3 + j]
			var b2 := t[ti * 3 + (j + 1) % 3]
			if int(cnt[_pk(a2, b2)]) == 1:
				nxt[a2] = b2
	var left := nxt.duplicate()
	while not left.is_empty():
		var st: int = left.keys()[0]
		var loop := [st]
		var cur: int = left[st]
		left.erase(st)
		while cur != st and left.has(cur):
			loop.append(cur)
			var nx: int = left[cur]
			left.erase(cur)
			cur = nx
		# (which new loop: the nearer on average)
		var da := 0.0
		var db := 0.0
		for vi in loop:
			var ma := INF
			var mb := INF
			for k in N:
				ma = minf(ma, v[vi].distance_squared_to(out_v[ba[k]]))
				mb = minf(mb, v[vi].distance_squared_to(out_v[bpair[k]]))
			da += sqrt(ma)
			db += sqrt(mb)
		var on_a := da <= db
		var ids: Array = ba if on_a else bpair
		var pp: PackedVector2Array = pa if on_a else pb
		var lp := _loop_places(v, loop, ids, out_v)
		for vi in loop:
			if not lp.has(vi):
				continue
			var k := int(lp[vi].x)
			var u0 := pp[k]
			var u1 := pp[(k + 1) % N]
			# (along the arc, not across it)
			var a0 := atan2(u0.y, u0.x)
			var a1 := a0 + wrapf(atan2(u1.y, u1.x) - a0, -PI, PI)
			uv[vi] = Vector2(cos(lerpf(a0, a1, lp[vi].y)), sin(lerpf(a0, a1, lp[vi].y))) * u0.length()
	for vi in bnd:
		if not uv.has(vi):
			uv[vi] = Vector2.ZERO   # (shouldn't be: every rim point is on one of its two loops)
	_harmonic_cot(v, t, tris, bnd, uv)
	var look := _uv_index(t, tris, uv, Vector2(-1.05, -1.05), Vector2(1.05, 1.05), 32)
	# the joins: each sampled along on the surface; the rows at equal lengths along them
	var SS := 32
	var spokes := []
	var mean_len := 0.0
	for k in N:
		var ps := PackedVector2Array()
		var ls := PackedFloat64Array([0.0])
		var last = null
		for i in SS + 1:
			var pp := pa[k].lerp(pb[k], float(i) / SS)
			var h: Array = _uv_at(v, t, uv, look, pp)
			ps.append(pp)
			if i > 0:
				ls.append(ls[i - 1] + ((h[0] as Vector3).distance_to(last) if not h.is_empty() and last != null else 0.0))
			if not h.is_empty():
				last = h[0]
		spokes.append([ps, ls])
		mean_len += ls[SS]
	mean_len /= N
	var sp3 := per / N
	var R := maxi(0, roundi(mean_len / sp3) - 1)
	var nv := out_v
	var levels := [ba]
	for j in range(1, R + 1):
		var lev := []
		for k in N:
			var ps: PackedVector2Array = spokes[k][0]
			var ls: PackedFloat64Array = spokes[k][1]
			var want_l := ls[SS] * float(j) / (R + 1)
			var i := clampi(ls.bsearch(want_l), 1, SS)
			var w := clampf((want_l - ls[i - 1]) / maxf(ls[i] - ls[i - 1], 1e-12), 0.0, 1.0)
			var hit: Array = _uv_at(v, t, uv, look, ps[i - 1].lerp(ps[i], w))
			if hit.is_empty():
				grid_why = "a ring-shaped face: a point off it"
				return {}
			lev.append(nv.size())
			nv.append(hit[0])
		levels.append(lev)
	levels.append(bpair)
	var quads := []
	for j in levels.size() - 1:
		var a: Array = levels[j]
		var b: Array = levels[j + 1]
		for k in N:
			quads.append([a[k], a[(k + 1) % N], b[(k + 1) % N], b[k]])
	return _quads_out(v, t, uv, look, nv, quads, tris)


# --- grids for any solid: facing made one way, faces with holes cut into pieces -----------------------------

## A solid's mesh laid out again as grids of quads that follow its edges - any solid: its triangles turned
## to face one way, each face with more than one hole cut into two pieces (a line from its rim through each
## hole and out again - the cut's points let go of after, so no new edges), then every face a grid
## (grid_faces_best: one that still can't be kept as it was, with no gap). {v, t, fv, kept, cuts} or {}.
## full = false: the grid templates only (no field-aligned fill, one try at the crease lines) - quick (a tenth of
## a second for a few thousand triangles), for a layout made on the main thread; the full one on a worker.
## (the layout's progress) `f` of the way through the current run, doing `what` - never going back.
static func _prog(f: float, what := "") -> void:
	progress[0] = maxf(float(progress[0]), _pbase + _pspan * clampf(f, 0.0, 1.0))
	if what != "":
		progress[1] = what


## only: the triangles to lay out (their faces) - the other faces kept exactly as they are; empty: all.
static func grid_any(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array, L: float, full := true, only := {}) -> Dictionary:
	progress[0] = 0.0
	progress[1] = "starting"
	_pbase = 0.0
	_pspan = 1.0
	if not full or not crease_both or not crease_on:
		var r0 := _grid_any(v, t, fv, chains, L, crease_min_len, full, only)
		progress[0] = 1.0
		return r0
	# (the mesh's own sharp bends followed as lines - or not: on a clean shape they keep the shading crisp, on
	# a messy one they're noise cutting little faces - both laid out, the better kept)
	_pspan = 0.5
	var a := _grid_any(v, t, fv, chains, L, crease_short, true, only)
	_pbase = 0.5
	var b := _grid_any(v, t, fv, chains, L, crease_long, true, only)
	_pbase = 0.0
	_pspan = 1.0
	_prog(1.0, "choosing the cleaner")
	if a.is_empty() or b.is_empty():
		return b if a.is_empty() else a
	var TS: GDScript = load("res://scripts/editor/mesh/topo_score.gd")
	var sa := float(TS.score(a["v"], a["t"], a["fv"], chains)["score"])
	var sb := float(TS.score(b["v"], b["t"], b["fv"], chains)["score"])
	return a if sa >= sb else b


static func _grid_any(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array, L: float, min_len: float, full: bool, only := {}) -> Dictionary:
	_prog(0.0, "following its edges")
	var t2 := oriented(t)
	fv = chain_paths(v, t2, fv, chains) if paths_on else clean_edge_points(t2, fv, chains)   # (each edge's points in the order its path runs through the mesh)
	var creased := crease_chains(v, t2, fv, chains, L, min_len) if crease_on else {"fv": fv, "chains": chains}   # (sharp bends that aren't edges: rows of mesh along them)
	var halves := split_closed(v, t2, creased["fv"], creased["chains"]) if split_closed_on else creased   # (a closed shape with no edges: cut across its middle)
	var prep := cut_holes(v, t2, halves["fv"], halves["chains"])
	if big_face > 0.0:
		var sp := split_big(v, prep["t"], prep["fv"], prep["chains"], L)   # (a big face in pieces, each flattened with less distortion)
		prep["fv"] = sp["fv"]
		prep["chains"] = sp["chains"]   # (rim_chains - bare open borders as edges - made things worse: their open sides are mostly seams, to look at)
	_prog(0.05, "laying grids")
	var r := grid_faces_best(v, prep["t"], prep["fv"], prep["chains"], L, full, only)
	_prog(1.0)
	if r.is_empty():
		return {}
	var real := chains.size()
	r["fv"] = (r["fv"] as Array).filter(func(e): return int(e[1]) < real)   # (the cuts' points: plain points again)
	r["cuts"] = int(prep["cuts"])
	return r


## Triangles turned so neighbours agree (each side run opposite ways by the two triangles at it) - each
## piece of the mesh kept the way most of its triangles already faced.
static func oriented(t_in: PackedInt32Array) -> PackedInt32Array:
	var t := t_in.duplicate()
	var nt := t.size() / 3
	var by_e := {}
	for ti in nt:
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			if not by_e.has(k):
				by_e[k] = []
			(by_e[k] as Array).append(ti)
	var seen := PackedByteArray()
	seen.resize(nt)
	var flip := PackedByteArray()
	flip.resize(nt)
	var has_dir := func(ti: int, a: int, b: int) -> bool:
		for j in 3:
			if t[ti * 3 + j] == a and t[ti * 3 + (j + 1) % 3] == b:
				return true
		return false
	for t0 in nt:
		if seen[t0] == 1:
			continue
		var comp := []
		seen[t0] = 1
		var todo := [t0]
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			comp.append(ti)
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				if flip[ti] == 1:
					var tmp := a
					a = b
					b = tmp
				var nb: Array = by_e[_pk(a, b)]
				if nb.size() != 2:
					continue   # (an open side or one three faces meet at: not followed)
				var o: int = nb[0] if nb[1] == ti else nb[1]
				if seen[o] == 1:
					continue
				seen[o] = 1
				# (agreeing: the neighbour runs the side b -> a)
				flip[o] = 0 if has_dir.call(o, b, a) else 1
				todo.append(o)
		var flipped := 0
		for ti in comp:
			flipped += flip[ti]
		var undo := flipped * 2 > comp.size()   # (most of it faced the other way: that's its way)
		for ti in comp:
			if (flip[ti] == 1) != undo:
				var x := t[ti * 3 + 1]
				t[ti * 3 + 1] = t[ti * 3 + 2]
				t[ti * 3 + 2] = x
	return t


## Each face with more than one hole cut into two pieces: a line along its mesh from its rim to the nearest
## hole, from that hole's far side to the next, ... and from the last back to the rim - each a chain of its
## own (appended after `chains`, for grid_faces to cut there). {t, fv, chains, cuts}.
static func cut_holes(v: PackedVector3Array, t: PackedInt32Array, fv_in: Array, chains_in: Array) -> Dictionary:
	var fv := fv_in.duplicate(true)
	var chains := chains_in.duplicate(true)
	var cuts := 0
	# the faces as grid_faces sees them: split at the chains' sides
	var feat := {}
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in range(1, lst.size()):
			if int(lst[m - 1][1]) != int(lst[m][1]):
				feat[_pk(int(lst[m - 1][1]), int(lst[m][1]))] = true
		if ci < chains.size() and bool(chains[ci].get("closed", false)) and lst.size() > 2:
			feat[_pk(int(lst.back()[1]), int(lst[0][1]))] = true
	var face: PackedInt32Array = face_of(v, t, feat)
	var nf := 0
	for f in face:
		nf = maxi(nf, f + 1)
	var f_tris := []
	for f in nf:
		f_tris.append([])
	for ti in face.size():
		(f_tris[face[ti]] as Array).append(ti)
	for f in nf:
		var tris: Array = f_tris[f]
		var cnt := {}
		var adj := {}
		for ti in tris:
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				var k := _pk(a, b)
				cnt[k] = int(cnt.get(k, 0)) + 1
				if not adj.has(a):
					adj[a] = {}
				if not adj.has(b):
					adj[b] = {}
				adj[a][b] = true
				adj[b][a] = true
		# its rims: the boundary's pieces, each a loop
		var bnd := {}
		for k in cnt:
			if int(cnt[k]) == 1:
				var ab := _unpk(k)
				for x in ab:
					if not bnd.has(x):
						bnd[x] = []
				(bnd[ab[0]] as Array).append(ab[1])
				(bnd[ab[1]] as Array).append(ab[0])
		var comp_of := {}
		var comps := []   # [vertices, length]
		for s in bnd:
			if comp_of.has(s):
				continue
			var cv := []
			var ln := 0.0
			var st := [s]
			comp_of[s] = comps.size()
			while not st.is_empty():
				var x: int = st.pop_back()
				cv.append(x)
				for y in bnd[x]:
					ln += v[x].distance_to(v[y]) * 0.5
					if not comp_of.has(y):
						comp_of[y] = comps.size()
						st.append(y)
			comps.append([cv, ln])
		if comps.size() <= 1:
			continue   # (a face: grid_faces lays it out as it is)
		if comps.size() == 2 and not ring_cut_on:
			continue
		if comps.size() == 2:
			var l0: float = comps[0][1]
			var l1: float = comps[1][1]
			if maxf(l0, l1) < minf(l0, l1) * 1.4:
				continue   # (a ring with its two rims alike: rows from one to the other)
			# (a ring with one rim much longer: cut in two - each piece a patch whose poles take up the
			# difference; rows would have to squeeze)
		var outer := 0
		for ci in comps.size():
			if float(comps[ci][1]) > float(comps[outer][1]):
				outer = ci
		# the cut: rim -> nearest hole -> its far side -> next hole ... -> rim
		var used := {}
		var left := {}
		for ci in comps.size():
			if ci != outer:
				left[ci] = true
		var from: Array = comps[outer][0]
		var first_start := -1
		var path_ok := true
		var pieces := []
		while true:
			var targets := {}
			var to_rim := left.is_empty()
			if to_rim:
				for x in comps[outer][0]:
					if not used.has(x) and (first_start < 0 or v[x].distance_to(v[first_start]) > 1e-9):
						targets[x] = true
				# (back to the rim away from where the cut began: the face in two)
				if first_start >= 0:
					var far := {}
					var dd := []
					for x in targets:
						dd.append([v[x].distance_to(v[first_start]), x])
					dd.sort_custom(func(p, q): return p[0] > q[0])
					for i in maxi(1, dd.size() / 2):
						far[dd[i][1]] = true
					targets = far
			else:
				for ci in left:
					for x in comps[ci][0]:
						targets[x] = true
			var path := _shortest(v, adj, from, targets, used, bnd)
			if path.is_empty():
				path_ok = false
				break
			if first_start < 0:
				first_start = path[0]
			pieces.append(path)
			for x in path:
				used[x] = true
			if to_rim:
				break
			var hole: int = comp_of[path.back()]
			left.erase(hole)
			# (out of this hole from its far side: the points of its rim farthest from where the cut came in)
			var entry: int = path.back()
			var hv: Array = comps[hole][0]
			var dd := []
			for x in hv:
				dd.append([v[x].distance_to(v[entry]), x])
			dd.sort_custom(func(p, q): return p[0] > q[0])
			from = []
			for i in maxi(1, dd.size() / 3):
				from.append(dd[i][1])
		if not path_ok:
			continue   # (no way through: the face left to be kept as it is)
		for path in pieces:
			var ci := chains.size()
			chains.append({"id": -1000 - ci, "closed": false})
			var total := 0.0
			for i in range(1, path.size()):
				total += v[path[i - 1]].distance_to(v[path[i]])
			var acc := 0.0
			for i in path.size():
				if i > 0:
					acc += v[path[i - 1]].distance_to(v[path[i]])
				fv.append([int(path[i]), ci, acc / maxf(total, 1e-12)])
			cuts += 1
	return {"t": t, "fv": fv, "chains": chains, "cuts": cuts}


## The shortest way along the mesh's sides (`adj`) from any of `from` to any of `to` - not through `used`
## points nor rim points (`bnd`) other than its two ends. [points...] or [].
static func _shortest(v: PackedVector3Array, adj: Dictionary, from: Array, to: Dictionary, used: Dictionary, bnd: Dictionary) -> Array:
	var dist := {}
	var prev := {}
	var open := []   # [distance, point] - kept sorted cheaply (a binary heap would be quicker on huge faces)
	for s in from:
		if used.has(s) and not bnd.has(s):
			continue
		dist[s] = 0.0
		prev[s] = -1
		open.append([0.0, s])
	var src := {}
	for s in from:
		src[s] = true
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(open[i][0]) < float(open[bi][0]):
				bi = i
		var cur: Array = open[bi]
		open[bi] = open.back()
		open.pop_back()
		var x: int = cur[1]
		if float(cur[0]) > float(dist.get(x, INF)):
			continue
		if to.has(x) and not src.has(x):
			var path := [x]
			while int(prev[path.back()]) >= 0:
				path.append(prev[path.back()])
			path.reverse()
			return path
		for y in adj.get(x, {}):
			if used.has(y) and not to.has(y):
				continue
			if bnd.has(y) and not to.has(y):
				continue   # (along a rim: not a cut through the face)
			var nd: float = float(cur[0]) + v[x].distance_to(v[y])
			if nd < float(dist.get(y, INF)):
				dist[y] = nd
				prev[y] = x
				open.append([nd, y])
	return []


# --- an n-sided face: n grids round one pole --------------------------------------------------------------

## The spokes of an n-sided patch with side counts `e` (each side split where a spoke meets it: side i is
## s[i-1] edges from its first corner, then s[i+1] - so e[i] = s[i-1] + s[i+1]), or [] when there's no
## whole positive answer (Tarini, "Closed-form quadrangulation of n-sided patches"). n = 4: the middle of
## each side.
static func cc_spokes(e: Array, as_float := false) -> Array:
	var n := e.size()
	if n < 3:
		return []
	if n == 4 and not as_float:
		if int(e[0]) != int(e[2]) or int(e[1]) != int(e[3]) or int(e[0]) < 2 or int(e[1]) < 2:
			return []
		return [int(e[1]) / 2, int(e[0]) / 2, int(e[1]) - int(e[1]) / 2, int(e[0]) - int(e[0]) / 2]
	# (e[i] = s[i-1] + s[i+1]: solved exactly, n unknowns - n small)
	var m := []
	for i in n:
		var row := []
		row.resize(n + 1)
		row.fill(0.0)
		row[(i - 1 + n) % n] = 1.0
		row[(i + 1) % n] = 1.0
		row[n] = float(e[i])
		m.append(row)
	for c in n:
		var piv := -1
		var best := 1e-9
		for r in range(c, n):
			if absf(m[r][c]) > best:
				best = absf(m[r][c])
				piv = r
		if piv < 0:
			return []   # (n a multiple of 4 but 4: not solved here)
		var tmp = m[c]
		m[c] = m[piv]
		m[piv] = tmp
		for r in n:
			if r != c and absf(m[r][c]) > 0.0:
				var f: float = m[r][c] / m[c][c]
				for k in range(c, n + 1):
					m[r][k] -= f * m[c][k]
	var s := []
	for i in n:
		s.append(m[i][n] / m[i][i])
	if as_float:
		return s
	var si := []
	for x in s:
		if absf(float(x) - roundf(x)) > 1e-6 or roundf(x) < 1.0:
			return []
		si.append(int(roundf(x)))
	return si


## (grid_faces) An n-sided face (3 to 6 corners - `cut` their places in `bpts`, in order) laid out as n grids
## meeting at one pole in its middle: mapped flat onto a regular n-gon (its rim on the n-gon's sides, its
## inside by a harmonic map - a convex rim: no folds), the grids laid there and mapped back onto its surface.
## {t, v} or {} (grid_why says why).
static func _face_cc(v: PackedVector3Array, t: PackedInt32Array, tris: Array, bpts: Array, out_v: PackedVector3Array, cut: Array, L: float) -> Dictionary:
	var N := bpts.size()
	var n := cut.size()
	var e := []
	for i in n:
		e.append((int(cut[(i + 1) % n]) - int(cut[i]) + N) % N)
	var s := cc_spokes(e)
	if s.is_empty():
		grid_why = "cc: sides %s don't make %d grids" % [str(e), n]
		return {}
	var fl := _face_local(t, tris)
	var bnd: Dictionary = fl["bnd"]
	var nbrs: Dictionary = fl["nbrs"]
	# the flat n-gon: the face's own shape - its sides as long as they are, its corners as sharp (a regular
	# n-gon squashes a long thin face, and its grids come back as long thin quads); the rim's samples evenly
	# along its sides
	var C := _flat_polygon(v, t, tris, bpts, out_v, cut)
	var O := Vector2.ZERO   # (the pole: the polygon's middle)
	for q in C:
		O += q
	O /= maxf(C.size(), 1)
	var flat := PackedVector2Array()
	flat.resize(N)
	for i in n:
		for k in int(e[i]):
			flat[(int(cut[i]) + k) % N] = (C[i] as Vector2).lerp(C[(i + 1) % n], float(k) / int(e[i]))
	# the face's own rim points placed between the samples nearest them, the rest by the harmonic map
	var uv := {}
	var rp := _rim_places(v, t, tris, bpts, out_v)
	for vi in bnd:
		if rp.has(vi):
			var kk := int(rp[vi].x)
			uv[vi] = flat[kk].lerp(flat[(kk + 1) % N], rp[vi].y)
			continue
		var q := v[vi]
		var bestd := INF
		var place := Vector2.ZERO
		for k in N:
			var p0 := out_v[bpts[k]]
			var p1 := out_v[bpts[(k + 1) % N]]
			var ab := p1 - p0
			var u := clampf((q - p0).dot(ab) / maxf(ab.length_squared(), 1e-18), 0.0, 1.0)
			var d := (p0 + ab * u).distance_squared_to(q)
			if d < bestd:
				bestd = d
				place = flat[k].lerp(flat[(k + 1) % N], u)
		uv[vi] = place
	_harmonic_cot(v, t, tris, bnd, uv)
	var look := _uv_index(t, tris, uv, Vector2(-1.01, -1.01), Vector2(1.01, 1.01), 32)
	look["nrm"] = _face_normals(v, t, tris)   # (new points on the smooth surface, not its facets)
	var nv := out_v
	var made := {}   # point key -> vertex
	var at_flat := func(key: String, p: Vector2) -> int:
		if made.has(key):
			return made[key]
		var hit: Array = _uv_at(v, t, uv, look, p)
		if hit.is_empty():
			return -1
		made[key] = nv.size()
		nv.append(hit[0])
		return made[key]
	# each side's split point (where its spoke meets it), the middle
	var P := []
	for i in n:
		P.append((C[i] as Vector2).lerp(C[(i + 1) % n], float(s[(i - 1 + n) % n]) / int(e[i])))
	var quads := []
	for i in n:
		# the grid at corner i: a along side i (from the corner), b along side i-1 (back from the corner)
		var sa: int = s[(i - 1 + n) % n]
		var sb: int = s[i]
		var ip := (i - 1 + n) % n
		var c0: Vector2 = C[i]
		var p1: Vector2 = P[i]
		var p3: Vector2 = P[ip]
		var id := func(a: int, b: int) -> int:
			if b == 0:
				return bpts[(int(cut[i]) + a) % N]
			if a == 0:
				return bpts[(int(cut[i]) - b + N) % N]
			if a == sa and b == sb:
				return at_flat.call("o", O)
			if a == sa:
				return at_flat.call("s%d_%d" % [i, b], p1.lerp(O, float(b) / sb))
			if b == sb:
				return at_flat.call("s%d_%d" % [ip, a], p3.lerp(O, float(a) / sa))
			var u := float(a) / sa
			var w := float(b) / sb
			var pt := c0 * (1.0 - u) * (1.0 - w) + p1 * u * (1.0 - w) + O * u * w + p3 * (1.0 - u) * w
			return at_flat.call("r%d_%d_%d" % [i, a, b], pt)
		for a in sa:
			for b in sb:
				var q4 := [id.call(a, b), id.call(a + 1, b), id.call(a + 1, b + 1), id.call(a, b + 1)]
				if q4.has(-1):
					grid_why = "cc: a point off the face"
					return {}
				quads.append(q4)
	return _quads_out(v, t, uv, look, nv, quads, tris)


## (grid_faces) A face's inner points placed by cotangent weights - each pulled to its neighbours by how its
## triangles' angles lie, so a flat patch maps exactly flat and a curved one keeps its angles nearly (a plain
## average of neighbours warps an uneven triangulation). Weights kept positive (an obtuse triangle's would go
## negative and fold the map). `uv` holds the rim's places; solved by conjugate gradients, both axes.
static func _harmonic_cot(v: PackedVector3Array, t: PackedInt32Array, tris: Array, bnd: Dictionary, uv: Dictionary) -> void:
	var w := {}   # Vector2i(lo, hi) -> weight
	var total := 0.0
	for ti in tris:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			var c := t[ti * 3 + (j + 2) % 3]   # (the corner opposite side a-b)
			var e1 := v[a] - v[c]
			var e2 := v[b] - v[c]
			var cr := e1.cross(e2).length()
			var cot := e1.dot(e2) / maxf(cr, 1e-18)
			var k := Vector2i(mini(a, b), maxi(a, b))
			w[k] = float(w.get(k, 0.0)) + 0.5 * cot
			total += absf(0.5 * cot)
	var floor_w := maxf(total / maxf(w.size(), 1) * 0.02, 1e-9)
	var nb := {}   # vertex -> {neighbour: weight}
	for k in w:
		var ww := maxf(float(w[k]), floor_w)
		if not nb.has(k.x):
			nb[k.x] = {}
		if not nb.has(k.y):
			nb[k.y] = {}
		nb[k.x][k.y] = ww
		nb[k.y][k.x] = ww
	var inner := []
	var idx := {}
	for vi in nb:
		if not bnd.has(vi):
			idx[vi] = inner.size()
			inner.append(vi)
	var n_in := inner.size()
	if n_in == 0:
		return
	var diag := PackedFloat64Array()
	diag.resize(n_in)
	for i in n_in:
		var s := 0.0
		for o in nb[inner[i]]:
			s += float(nb[inner[i]][o])
		diag[i] = s
	for axis in 2:
		var bvec := PackedFloat64Array()
		bvec.resize(n_in)
		for i in n_in:
			var s := 0.0
			for o in nb[inner[i]]:
				if bnd.has(o):
					s += float(nb[inner[i]][o]) * (uv[o] as Vector2)[axis]
			bvec[i] = s
		var x := PackedFloat64Array()
		x.resize(n_in)
		for i in n_in:
			x[i] = bvec[i] / maxf(diag[i], 1e-18)   # (a first guess: its rim neighbours' pull)
		var apply := func(p: PackedFloat64Array) -> PackedFloat64Array:
			var o2 := PackedFloat64Array()
			o2.resize(n_in)
			for i in n_in:
				var row: Dictionary = nb[inner[i]]
				var s := diag[i] * p[i]
				for o in row:
					if idx.has(o):
						s -= float(row[o]) * p[idx[o]]
				o2[i] = s
			return o2
		var ax: PackedFloat64Array = apply.call(x)
		var r := PackedFloat64Array()
		r.resize(n_in)
		var rr := 0.0
		for i in n_in:
			r[i] = bvec[i] - ax[i]
			rr += r[i] * r[i]
		var p := r.duplicate()
		var tol := 1e-14 * maxf(rr, 1e-30)   # (relative: settled whatever the face's size)
		for it in maxi(1500, n_in * 4):   # (a long thin face settles slowly - as many steps as it takes)
			if rr < tol:
				break
			var ap: PackedFloat64Array = apply.call(p)
			var pap := 0.0
			for i in n_in:
				pap += p[i] * ap[i]
			if absf(pap) < 1e-30:
				break
			var al := rr / pap
			var rr2 := 0.0
			for i in n_in:
				x[i] += al * p[i]
				r[i] -= al * ap[i]
				rr2 += r[i] * r[i]
			var be := rr2 / rr
			rr = rr2
			for i in n_in:
				p[i] = r[i] + be * p[i]
		for i in n_in:
			var cur: Vector2 = uv.get(inner[i], Vector2.ZERO)
			cur[axis] = x[i]
			uv[inner[i]] = cur


## (grid_faces) A face's corners - places in its rim's samples (`turn`: each sample's turn), in order: its
## sharp corners (over 50 degrees; the six sharpest if more), and if it makes a better layout one or two more
## where the rim bends most - a 4-corner plan opposite sides equal (one grid), 3, 5 or 6 a whole answer for
## that many grids round one pole. Scored: a pole costs, a corner on a straight stretch costs, uneven grids
## cost. [] - a round dome with no corners to speak of: rings (`roundness`: its rim squared over 4 pi its area).
	# (folded anywhere - a triangle turned over in the map: the plain average instead, which can't fold
	# inside a convex rim - a little less true to the angles, but every point found where it belongs)
	var pos_n := 0
	var neg_n := 0
	for ti in tris:
		var pa: Vector2 = uv.get(t[ti * 3], Vector2.ZERO)
		var pb: Vector2 = uv.get(t[ti * 3 + 1], Vector2.ZERO)
		var pc: Vector2 = uv.get(t[ti * 3 + 2], Vector2.ZERO)
		var ar := (pb - pa).cross(pc - pa)
		if ar > 1e-14:
			pos_n += 1
		elif ar < -1e-14:
			neg_n += 1
	if mini(pos_n, neg_n) > 0 and fold_fallback_on:
		var nbrs := {}
		for ti in tris:
			for j in 3:
				var x := t[ti * 3 + j]
				var y := t[ti * 3 + (j + 1) % 3]
				if not nbrs.has(x):
					nbrs[x] = {}
				if not nbrs.has(y):
					nbrs[y] = {}
				nbrs[x][y] = true
				nbrs[y][x] = true
		_harmonic(nbrs, bnd, uv)


static func _plan_corners(turn: PackedFloat32Array, N: int, roundness: float, pos := PackedVector3Array()) -> Array:
	var sharp_min := deg_to_rad(50.0)
	var base := []
	for k in N:
		if turn[k] > sharp_min:
			base.append(k)
	if base.size() > 6:
		base.sort_custom(func(a, b): return turn[a] > turn[b])
		base = base.slice(0, 6)
	base.sort()
	if base.size() < 2 and roundness < 1.6 and not dome_as_grid:
		return []   # (a dome or a round cap: rings round a middle grid)
	var res := {"best": [], "sc": INF}   # (a lambda keeps its own copies of plain variables: kept in here)
	# (the rim's length up to each sample: a stretch's length in real units)
	var cum := PackedFloat64Array([0.0])
	for k in N:
		cum.append(cum[k] + (pos[k].distance_to(pos[(k + 1) % N]) if pos.size() == N else 1.0))
	var span := func(a: int, b: int) -> float:   # (from sample a on to sample b)
		if b >= a:
			return cum[b] - cum[a]
		return cum[N] - cum[a] + cum[b]
	var try_set := func(cs: Array, virt: Array) -> void:
		var n := cs.size()
		var dropped := 0.0
		for k in base:
			if not k in cs:
				dropped += clampf(turn[k] / (PI * 0.5), 0.0, 1.5) * 0.9   # (a sharp corner left bending a side)
		if n < 3 or n > 6:
			return
		var e := []
		for i in n:
			var g: int = (int(cs[(i + 1) % n]) - int(cs[i]) + N) % N
			if g < 1:
				return
			e.append(g)
		var sc := dropped
		var ln := []
		for i in n:
			ln.append(maxf(float(span.call(int(cs[i]), int(cs[(i + 1) % n]))), 1e-9))
		if n == 4:
			if int(e[0]) != int(e[2]) or int(e[1]) != int(e[3]):
				return
			# (square quads: the spacing along one way like the other; opposite sides alike - not a wedge)
			var da: float = (float(ln[0]) + float(ln[2])) * 0.5 / int(e[0])
			var db: float = (float(ln[1]) + float(ln[3])) * 0.5 / int(e[1])
			sc += absf(log(da / db)) * 1.5
			sc += (absf(log(float(ln[0]) / float(ln[2]))) + absf(log(float(ln[1]) / float(ln[3])))) * 0.3
		else:
			var sp := cc_spokes(e)
			if sp.is_empty():
				return
			sc += 1.0 if n != 6 else 1.4   # (a pole)
			# (each grid square: its two rim stretches spaced alike - a thin face's far-off middle makes long quads)
			var worst := 0.0
			var mean := 0.0
			for i in n:
				var sa: int = sp[(i - 1 + n) % n]
				var sb: int = sp[i]
				var split_a: int = (int(cs[i]) + sa) % N
				var split_b: int = (int(cs[i]) - sb + N) % N
				var la: float = maxf(float(span.call(int(cs[i]), split_a)), 1e-9)
				var lb: float = maxf(float(span.call(split_b, int(cs[i]))), 1e-9)
				var an: float = absf(log((la / sa) / (lb / sb)))
				worst = maxf(worst, an)
				mean += an / n
			sc += mean * 1.5 + worst * 0.5
		for k in virt:
			sc += (1.0 - clampf(turn[k] / (PI * 0.5), 0.0, 1.0)) * 0.8   # (a corner where the rim runs straight)
		if sc < float(res["sc"]):
			res["sc"] = sc
			res["best"] = cs.duplicate()
	try_set.call(base, [])
	var step := maxi(1, N / 48)
	var cand := []
	for k in range(0, N, step):
		if not k in base:
			cand.append(k)
	# (four corners, opposite ones half way round from each other - so opposite sides match: from each sharp
	# corner or pair of them, the rest worked out; the other sharp corners left on the sides)
	var h := N / 2
	if N % 2 == 0 and h >= 2:
		var anchors := []
		for x in base:
			anchors.append([x])
		for i in base.size():
			for j in range(i + 1, base.size()):
				anchors.append([base[i], base[j]])
		for an in anchors:
			var firsts := []
			if an.size() == 2:
				var d: int = (int(an[1]) - int(an[0]) + N) % N
				if d == h:
					for p in range(0, N, maxi(1, N / 64)):
						firsts.append([an[0], p])
				else:
					firsts.append([an[0], an[1]])
			else:
				for p in range(0, N, maxi(1, N / 64)):
					firsts.append([an[0], p])
			for fp in firsts:
				var c0: int = fp[0]
				var c1: int = fp[1]
				var cs := [c0, c1, (c0 + h) % N, (c1 + h) % N]
				var uniq := {}
				for x in cs:
					uniq[x] = true
				if uniq.size() != 4:
					continue
				cs.sort()
				var virt := cs.filter(func(x): return not x in base)
				try_set.call(cs, virt)
	if base.size() + 1 <= 6:
		for k in cand:
			var cs := base.duplicate()
			cs.append(k)
			cs.sort()
			try_set.call(cs, [k])
	if base.size() + 2 <= 6 and base.size() + 2 >= 3:
		var step2 := maxi(1, N / 28)
		var c2 := []
		for k in range(0, N, step2):
			if not k in base:
				c2.append(k)
		for i in c2.size():
			for j in range(i + 1, c2.size()):
				var cs := base.duplicate()
				cs.append(c2[i])
				cs.append(c2[j])
				cs.sort()
				try_set.call(cs, [c2[i], c2[j]])
	var best: Array = res["best"]
	if best.is_empty() and base.size() <= 2:
		# (a long face with no corners to speak of: four, opposite sides equal, at its sharpest turns)
		var bsc := -INF
		for i0 in range(0, h, step):
			for a in range(maxi(1, step), h, step):
				var cs := [i0, i0 + a, i0 + h, (i0 + h + a) % N]
				var sc := turn[cs[0]] + turn[cs[1]] + turn[cs[2]] + turn[cs[3]]
				if sc > bsc:
					bsc = sc
					cs.sort()
					best = cs
	return best


## (grid_faces) A face's corners laid flat with its real proportions: each side as long as its rim stretch,
## each corner as wide as on the surface (the turns scaled to make one whole turn - a curved face's don't),
## the small gap left at the end spread back along the sides; fitted inside the unit square. [Vector2...].
static func _flat_polygon(v: PackedVector3Array, t: PackedInt32Array, tris: Array, bpts: Array, out_v: PackedVector3Array, cut: Array) -> Array:
	var N := bpts.size()
	var n := cut.size()
	var fn := Vector3.ZERO
	for ti in tris:
		fn += (v[t[ti * 3 + 2]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 1]] - v[t[ti * 3]])
	fn = fn.normalized()
	var lens := []
	for i in n:
		var a: int = cut[i]
		var b: int = cut[(i + 1) % n]
		var ln := 0.0
		var k := a
		while k != b:
			ln += out_v[bpts[k]].distance_to(out_v[bpts[(k + 1) % N]])
			k = (k + 1) % N
		lens.append(maxf(ln, 1e-9))
	# each corner's turn (signed by the face's facing), from a couple of samples either side
	var turns := []
	var tsum := 0.0
	for i in n:
		var k: int = cut[i]
		var reach := mini(2, maxi(1, N / (4 * n)))
		var din := (out_v[bpts[k]] - out_v[bpts[(k - reach + N) % N]]).normalized()
		var dout := (out_v[bpts[(k + reach) % N]] - out_v[bpts[k]]).normalized()
		var tr := atan2(din.cross(dout).dot(fn), din.dot(dout))
		turns.append(tr)
		tsum += tr
	if absf(tsum) < 1e-6:
		tsum = TAU
	var scale := TAU / absf(tsum)
	var sgn := 1.0 if tsum > 0.0 else -1.0
	var P := [Vector2.ZERO]
	var ang := 0.0
	var total := 0.0
	for i in n:
		total += float(lens[i])
	for i in n - 1:
		P.append((P[i] as Vector2) + Vector2(cos(ang), sin(ang)) * float(lens[i]))
		ang += float(turns[(i + 1) % n]) * scale * sgn
	var end: Vector2 = (P[n - 1] as Vector2) + Vector2(cos(ang), sin(ang)) * float(lens[n - 1])
	var gap: Vector2 = end - (P[0] as Vector2)
	var acc := 0.0
	for i in range(1, n):
		acc += float(lens[i - 1])
		P[i] = (P[i] as Vector2) - gap * (acc / total)
	var lo: Vector2 = P[0]
	var hi: Vector2 = P[0]
	for q in P:
		lo = lo.min(q)
		hi = hi.max(q)
	var mid := (lo + hi) * 0.5
	var sz := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
	var out := []
	for q in P:
		out.append(((q as Vector2) - mid) / maxf(sz, 1e-12))
	return out



## (grid_faces) Where each of a face's own rim points falls along its new rim (`bpts`, samples of out_v):
## by how far along the rim it is - both rims walked from the same place the same way round, their lengths
## matched (a nearest-stretch guess goes wrong on a coarse face: its far ends got no points at all).
## {old rim vertex: Vector2(sample k, fraction on to k + 1)}; {} when its rim can't be followed.
static func _rim_places(v: PackedVector3Array, t: PackedInt32Array, tris: Array, bpts: Array, out_v: PackedVector3Array) -> Dictionary:
	var N := bpts.size()
	var cnt := {}
	for ti in tris:
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			cnt[k] = int(cnt.get(k, 0)) + 1
	var nxt := {}
	for ti in tris:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			if int(cnt[_pk(a, b)]) == 1:
				nxt[a] = b
	if nxt.is_empty():
		return {}
	# its outer rim: the longest loop
	var loops := []
	var left := nxt.duplicate()
	while not left.is_empty():
		var st: int = left.keys()[0]
		var loop := [st]
		var cur: int = left[st]
		left.erase(st)
		while cur != st and left.has(cur):
			loop.append(cur)
			var nx: int = left[cur]
			left.erase(cur)
			cur = nx
		loops.append(loop)
	var rim: Array = loops[0]
	var rim_len := 0.0
	for lp in loops:
		var ln := 0.0
		for i in lp.size():
			ln += v[lp[i]].distance_to(v[lp[(i + 1) % lp.size()]])
		if ln > rim_len:
			rim_len = ln
			rim = lp
	return _loop_places(v, rim, bpts, out_v)


## (grid_faces) Where each point of the old loop `rim` (in order) falls along the new loop `bpts` (samples of
## out_v): both walked from the same place the same way round, by length. {vertex: Vector2(k, fraction)}.
static func _loop_places(v: PackedVector3Array, rim_in: Array, bpts: Array, out_v: PackedVector3Array) -> Dictionary:
	var rim := rim_in.duplicate()
	var N := bpts.size()
	var M := rim.size()
	if M < 3 or N < 3:
		return {}
	# where the new rim starts on the old: the old rim's nearest point to sample 0 (stretch m, fraction u)
	var p0 := out_v[bpts[0]]
	var best := INF
	var m0 := 0
	var u0 := 0.0
	for m in M:
		var a := v[rim[m]]
		var b := v[rim[(m + 1) % M]]
		var ab := b - a
		var u := clampf((p0 - a).dot(ab) / maxf(ab.length_squared(), 1e-18), 0.0, 1.0)
		var d := (a + ab * u).distance_squared_to(p0)
		if d < best:
			best = d
			m0 = m
			u0 = u
	# which way round the samples run along it: where sample 1 lands - just ahead of the start, or behind
	var p1 := out_v[bpts[1 % N]]
	var best1 := INF
	var m1 := 0
	var u1 := 0.0
	for m in M:
		var a := v[rim[m]]
		var b := v[rim[(m + 1) % M]]
		var ab := b - a
		var u := clampf((p1 - a).dot(ab) / maxf(ab.length_squared(), 1e-18), 0.0, 1.0)
		var d := (a + ab * u).distance_squared_to(p1)
		if d < best1:
			best1 = d
			m1 = m
			u1 = u
	var pos0 := float(m0) + u0
	var pos1 := float(m1) + u1
	var fwd := fposmod(pos1 - pos0, float(M)) <= float(M) * 0.5
	if not fwd:
		rim.reverse()
		# (the same start, now on the reversed rim)
		m0 = (M - 1 - m0 - 1 + M) % M
		u0 = 1.0 - u0
	# old rim: each vertex's distance along from the start
	var start := v[rim[m0]].lerp(v[rim[(m0 + 1) % M]], u0)
	var along := {}
	var acc := start.distance_to(v[rim[(m0 + 1) % M]])
	var old_total := 0.0
	for i in M:
		old_total += v[rim[i]].distance_to(v[rim[(i + 1) % M]])
	for step in M:
		var vi: int = rim[(m0 + 1 + step) % M]
		along[vi] = acc
		acc += v[vi].distance_to(v[rim[(m0 + 2 + step) % M]])
	# new rim: each sample's distance along
	var cum := PackedFloat64Array([0.0])
	for k in N:
		cum.append(cum[k] + out_v[bpts[k]].distance_to(out_v[bpts[(k + 1) % N]]))
	var new_total := maxf(cum[N], 1e-18)
	var out := {}
	var k := 0
	var order := along.keys()
	order.sort_custom(func(x, y): return float(along[x]) < float(along[y]))
	for vi in order:
		var s := fposmod(float(along[vi]) / maxf(old_total, 1e-18), 1.0) * new_total
		while k < N - 1 and cum[k + 1] < s:
			k += 1
		var seg := maxf(cum[k + 1] - cum[k], 1e-18)
		out[vi] = Vector2(k, clampf((s - cum[k]) / seg, 0.0, 1.0))
	return out


## The mesh's open borders that none of its edges runs along, made edges for the layout (appended after
## `chains`; let go of after, like the cuts) - a face with such a rim can be laid out like any other. Each
## border a loop (closed) or, where an edge meets it, runs between those points. {fv, chains}.
static func rim_chains(v: PackedVector3Array, t: PackedInt32Array, fv_in: Array, chains_in: Array) -> Dictionary:
	var fv := fv_in.duplicate(true)
	var chains := chains_in.duplicate(true)
	var on := {}
	var by_c := {}
	for e in fv:
		on[int(e[0])] = true
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	var edge_side := {}
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in lst.size():
			var a0: int = lst[m][1]
			var b0: int = lst[(m + 1) % lst.size()][1]
			if a0 != b0:
				edge_side[_pk(a0, b0)] = true
	var cnt := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var k := _pk(t[i + j], t[i + (j + 1) % 3])
			cnt[k] = int(cnt.get(k, 0)) + 1
	var nxt := {}   # open sides no edge runs along, as the triangles run
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := t[i + j]
			var b := t[i + (j + 1) % 3]
			var k := _pk(a, b)
			if int(cnt[k]) == 1 and not edge_side.has(k):
				nxt[a] = b
	if nxt.is_empty():
		return {"fv": fv, "chains": chains}
	var prv := {}
	for a in nxt:
		prv[nxt[a]] = a
	var done := {}
	for s0 in nxt.keys():
		if done.has(s0):
			continue
		# (start where an edge meets the border, or anywhere on a loop with none)
		var st: int = s0
		var guard := 0
		while prv.has(st) and not on.has(st) and prv[st] != s0 and guard < 100000:
			st = prv[st]
			guard += 1
		var run := [st]
		var cur := st
		while nxt.has(cur) and not done.has(cur):
			done[cur] = true
			cur = nxt[cur]
			run.append(cur)
			if cur == st or on.has(cur):
				break
		var closed: bool = run.size() > 2 and run.back() == run[0]
		if closed:
			run.pop_back()
		if run.size() < 2:
			continue
		var ci := chains.size()
		chains.append({"id": -2000 - ci, "closed": closed})
		var total := 0.0
		for i in range(1, run.size()):
			total += v[run[i - 1]].distance_to(v[run[i]])
		if closed:
			total += v[run.back()].distance_to(v[run[0]])
		var acc := 0.0
		for i in run.size():
			if i > 0:
				acc += v[run[i - 1]].distance_to(v[run[i]])
			fv.append([int(run[i]), ci, acc / maxf(total, 1e-12)])
	return {"fv": fv, "chains": chains}


## (tuning) A layout's quads measured: last_quality / last_counts - how square, how many slivers.
static var last_counts := [0, 0]
static func _note_quality(nv: PackedVector3Array, quads: Array) -> void:
	var asp_sum := 0.0
	var slv := 0
	for q4 in quads:
		var ls := []
		for m in 4:
			ls.append(nv[q4[m]].distance_to(nv[q4[(m + 1) % 4]]))
		var asp: float = float(ls.max()) / maxf(float(ls.min()), 1e-12)
		asp_sum += asp
		var bad := asp > 3.0
		for m in 4:
			var d0 := nv[q4[(m + 3) % 4]] - nv[q4[m]]
			var d1 := nv[q4[(m + 1) % 4]] - nv[q4[m]]
			if d0.length_squared() > 1e-30 and d1.length_squared() > 1e-30 and rad_to_deg(d0.angle_to(d1)) < 30.0:
				bad = true
		if bad:
			slv += 1
	# (folded: a quad's two halves turned more than 30 degrees from each other, either way it's split)
	var folded := 0
	for q4 in quads:
		var n1 := (nv[q4[1]] - nv[q4[0]]).cross(nv[q4[2]] - nv[q4[0]])
		var n2 := (nv[q4[2]] - nv[q4[0]]).cross(nv[q4[3]] - nv[q4[0]])
		var n3 := (nv[q4[1]] - nv[q4[0]]).cross(nv[q4[3]] - nv[q4[0]])
		var n4 := (nv[q4[2]] - nv[q4[1]]).cross(nv[q4[3]] - nv[q4[1]])
		if n1.length_squared() > 1e-30 and n2.length_squared() > 1e-30 and n3.length_squared() > 1e-30 and n4.length_squared() > 1e-30:
			if minf(rad_to_deg(n1.angle_to(n2)), rad_to_deg(n3.angle_to(n4))) > 30.0:
				folded += 1
	last_quality = "aspect %.2f, slivers %d of %d, folded %d" % [asp_sum / maxf(quads.size(), 1), slv, quads.size(), folded]
	last_counts = [quads.size(), slv, folded]


## An edge's listed points cleaned up (for the layout): points no triangle uses dropped, and a point that
## breaks the edge's run - its neighbours along the edge are joined by a side of the mesh, it isn't - dropped
## (left over by edits: the run went round it). The rest as they were. [[vertex, chain, place]...].
static func clean_edge_points(t: PackedInt32Array, fv: Array, chains: Array) -> Array:
	var used := {}
	var side := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			used[t[i + j]] = true
			side[_pk(t[i + j], t[i + (j + 1) % 3])] = true
	var by_c := {}
	for e in fv:
		if not used.has(int(e[0])):
			continue
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append(e)
	var out := []
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[2]) < float(y[2]))
		var closed: bool = ci < chains.size() and bool(chains[ci].get("closed", false))
		var changed := false   # (dropping a run-breaking point broke more than it mended - unused points only, for now)
		var guard := 0
		while changed and guard < 50:
			changed = false
			guard += 1
			var n := lst.size()
			if n < 3:
				break
			for i in n:
				if not closed and (i == 0 or i == n - 1):
					continue
				var a: int = lst[(i - 1 + n) % n][0]
				var m: int = lst[i][0]
				var b: int = lst[(i + 1) % n][0]
				if a == m or m == b:
					continue
				if not side.has(_pk(a, m)) and side.has(_pk(a, b)):
					lst.remove_at(i)
					changed = true
					break
				if not side.has(_pk(m, b)) and side.has(_pk(a, b)):
					lst.remove_at(i)
					changed = true
					break
		out.append_array(lst)
	return out


## Each closed piece of the mesh with no edge on it (a blob, a capsule) cut across its middle - square to its
## longest way, through its centre - by a loop of the mesh's sides: a chain of its own (appended, let go of
## after), so it's two caps the layout can grid. {fv, chains}.
static func split_closed(v: PackedVector3Array, t: PackedInt32Array, fv_in: Array, chains_in: Array) -> Dictionary:
	var fv := fv_in.duplicate(true)
	var chains := chains_in.duplicate(true)
	var on := {}
	for e in fv:
		on[int(e[0])] = true
	var nt := t.size() / 3
	var by_e := {}
	for ti in nt:
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			if not by_e.has(k):
				by_e[k] = []
			(by_e[k] as Array).append(ti)
	var comp := PackedInt32Array()
	comp.resize(nt)
	comp.fill(-1)
	var nc := 0
	for t0 in nt:
		if comp[t0] >= 0:
			continue
		var members := [t0]
		comp[t0] = nc
		var todo := [t0]
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			for j in 3:
				for o in by_e[_pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])]:
					if comp[o] < 0:
						comp[o] = nc
						todo.append(o)
						members.append(o)
		nc += 1
		# (closed - every side two triangles - and no edge on it)
		var closed := true
		var bare := true
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var ctr := Vector3.ZERO
		for ti in members:
			for j in 3:
				var vi := t[ti * 3 + j]
				if on.has(vi):
					bare = false
				if (by_e[_pk(vi, t[ti * 3 + (j + 1) % 3])] as Array).size() != 2:
					closed = false
				lo = lo.min(v[vi])
				hi = hi.max(v[vi])
				ctr += v[vi]
		if not closed or not bare or members.size() < 8:
			continue
		ctr /= members.size() * 3
		var ext := hi - lo
		var axis := Vector3.RIGHT if ext.x >= ext.y and ext.x >= ext.z else (Vector3.UP if ext.y >= ext.z else Vector3.BACK)
		# the triangles on the far side of the middle; the loop between them and the rest
		var far := {}
		for ti in members:
			var c := (v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0
			if (c - ctr).dot(axis) >= 0.0:
				far[ti] = true
		var nxt := {}
		for ti in far:
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				var other: Array = (by_e[_pk(a, b)] as Array).filter(func(x): return x != ti)
				if not other.is_empty() and not far.has(other[0]):
					nxt[a] = b
		if nxt.size() < 3:
			continue
		var st: int = nxt.keys()[0]
		var loop := [st]
		var cur: int = nxt[st]
		var guard := 0
		while cur != st and nxt.has(cur) and guard < nxt.size() + 2:
			loop.append(cur)
			cur = nxt[cur]
			guard += 1
		if cur != st or loop.size() != nxt.size():
			continue   # (not one clean loop round it: left as it is)
		var ci := chains.size()
		chains.append({"id": -3000 - ci, "closed": true})
		var total := 0.0
		for i in loop.size():
			total += v[loop[i]].distance_to(v[loop[(i + 1) % loop.size()]])
		var acc := 0.0
		for i in loop.size():
			if i > 0:
				acc += v[loop[i - 1]].distance_to(v[loop[i]])
			fv.append([int(loop[i]), ci, acc / maxf(total, 1e-12)])
	return {"fv": fv, "chains": chains}


## The mesh's sharp bends that none of its edges runs along (sides where its surface turns over 35 degrees,
## in lines three sides long or more) made edges for the layout (appended, let go of after) - so rows of the
## new mesh lie exactly on them: a bend falling inside quads makes lumps and folds. {fv, chains}.
static func crease_chains(v: PackedVector3Array, t: PackedInt32Array, fv_in: Array, chains_in: Array, L := 0.0, min_len := -1.0) -> Dictionary:
	if min_len < 0.0:
		min_len = crease_min_len
	var fv := fv_in.duplicate(true)
	var chains := chains_in.duplicate(true)
	var edge_side := {}
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in lst.size():
			var a0: int = lst[m][1]
			var b0: int = lst[(m + 1) % lst.size()][1]
			if a0 != b0:
				edge_side[_pk(a0, b0)] = true
	var by_e := {}
	var nt := t.size() / 3
	var tn := []
	for ti in nt:
		var n := (v[t[ti * 3 + 2]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 1]] - v[t[ti * 3]])
		tn.append(n.normalized() if n.length_squared() > 1e-30 else Vector3.ZERO)
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			if not by_e.has(k):
				by_e[k] = []
			(by_e[k] as Array).append(ti)
	var lim := cos(deg_to_rad(crease_deg))
	var adj := {}   # crease graph: vertex -> [vertex...]
	for k in by_e:
		var tl: Array = by_e[k]
		if tl.size() != 2 or edge_side.has(k):
			continue
		var n0: Vector3 = tn[tl[0]]
		var n1: Vector3 = tn[tl[1]]
		if n0 == Vector3.ZERO or n1 == Vector3.ZERO or n0.dot(n1) > lim:
			continue
		var ab := _unpk(k)
		for x in [0, 1]:
			var a: int = ab[x]
			var b: int = ab[1 - x]
			if not adj.has(a):
				adj[a] = []
			(adj[a] as Array).append(b)
	if adj.is_empty():
		return {"fv": fv, "chains": chains}
	# lines: walked from their ends (or anywhere on a loop), breaking where three or more meet
	var used := {}
	var starts := adj.keys().filter(func(x): return (adj[x] as Array).size() != 2)
	starts.append_array(adj.keys())
	for st in starts:
		for nb in adj[st]:
			if used.has(_pk(st, nb)):
				continue
			var line := [st]
			var prev: int = st
			var cur: int = nb
			used[_pk(st, nb)] = true
			while true:
				line.append(cur)
				if (adj[cur] as Array).size() != 2 or cur == st:
					break
				var nx: int = adj[cur][0] if adj[cur][0] != prev else adj[cur][1]
				if used.has(_pk(cur, nx)):
					break
				used[_pk(cur, nx)] = true
				prev = cur
				cur = nx
			var closed: bool = line.size() > 3 and line.back() == line[0]
			if closed:
				line.pop_back()
			if line.size() < (3 if closed else 4):
				continue   # (a short nick: noise, not a bend to follow)
			var llen := 0.0
			for i in range(1, line.size()):
				llen += v[line[i - 1]].distance_to(v[line[i]])
			if closed:
				llen += v[line.back()].distance_to(v[line[0]])
				if llen < crease_loop_min * L:
					continue   # (a loop round a facet or two - a spike, not a fold: nothing lays its little face out)
			if llen < min_len * L:
				continue   # (shorter than three quads: a facet's nick, not a fold - it would cut slivers of faces)
			var ci := chains.size()
			chains.append({"id": -4000 - ci, "closed": closed})
			var total := 0.0
			for i in range(1, line.size()):
				total += v[line[i - 1]].distance_to(v[line[i]])
			if closed:
				total += v[line.back()].distance_to(v[line[0]])
			var acc := 0.0
			for i in line.size():
				if i > 0:
					acc += v[line[i - 1]].distance_to(v[line[i]])
				fv.append([int(line[i]), ci, acc / maxf(total, 1e-12)])
	return {"fv": fv, "chains": chains}


## Each edge's listed points put in the order its path really runs through the mesh: the sides of the mesh
## joining its points walked from one end (a closed one: from its first place), at a fork the way its places
## go on; its places along it worked out again by length; points the walk never reaches dropped (strays from
## old edits - in place order they made sides that aren't there, and the edge didn't cut the surface).
static func chain_paths(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array) -> Array:
	var side := {}   # side -> its triangles
	for i in range(0, t.size(), 3):
		for j in 3:
			var k := _pk(t[i + j], t[i + (j + 1) % 3])
			if not side.has(k):
				side[k] = []
			(side[k] as Array).append(i / 3)
	var bent := func(k: String) -> float:   # (how sharply the surface turns over a side; an open side: 180)
		var tl: Array = side[k]
		if tl.size() != 2:
			return 180.0
		var n0 := (v[t[tl[0] * 3 + 2]] - v[t[tl[0] * 3]]).cross(v[t[tl[0] * 3 + 1]] - v[t[tl[0] * 3]])
		var n1 := (v[t[tl[1] * 3 + 2]] - v[t[tl[1] * 3]]).cross(v[t[tl[1] * 3 + 1]] - v[t[tl[1] * 3]])
		if n0.length_squared() < 1e-30 or n1.length_squared() < 1e-30:
			return 0.0
		return rad_to_deg(n0.angle_to(n1))
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = {}
		by_c[int(e[1])][int(e[0])] = float(e[2])   # (vertex -> its place)
	var open_adj := {}   # (the mesh's open sides: vertex -> [vertex...])
	for k in side:
		if (side[k] as Array).size() == 1:
			var ab := _unpk(k)
			for x in [0, 1]:
				if not open_adj.has(ab[x]):
					open_adj[ab[x]] = []
				(open_adj[ab[x]] as Array).append(ab[1 - x])
	var out := []
	for ci in by_c:
		var place: Dictionary = by_c[ci]
		# (an open rim the edge runs along, through a point or two it never listed: those points taken in,
		# so the walk goes on round the rim)
		for x in place.keys():
			for y0 in open_adj.get(x, []):
				if place.has(y0):
					continue
				var run := [y0]
				var prev_v: int = x
				var cur_v: int = y0
				var reached := -1
				for step in 8:
					var nx := -1
					for z in open_adj.get(cur_v, []):
						if z != prev_v:
							nx = z
							break
					if nx < 0:
						break
					if place.has(nx):
						reached = nx
						break
					run.append(nx)
					prev_v = cur_v
					cur_v = nx
				if reached >= 0 and reached != x:
					for i in run.size():
						place[run[i]] = lerpf(float(place[x]), float(place[reached]), float(i + 1) / (run.size() + 1))
		var pts := place.keys()
		var closed: bool = ci < chains.size() and bool(chains[ci].get("closed", false))
		var adj := {}
		for a in pts:
			adj[a] = []
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				if side.has(_pk(pts[i], pts[j])):
					(adj[pts[i]] as Array).append(pts[j])
					(adj[pts[j]] as Array).append(pts[i])
		# the start: a closed edge's lowest place; an open one's end (one neighbour), the lowest place of them
		var start: int = pts[0]
		var best := INF
		for a in pts:
			var ends_here: bool = closed or (adj[a] as Array).size() <= 1
			if ends_here and float(place[a]) < best:
				best = float(place[a])
				start = a
		var walk := [start]
		var seen := {start: true}
		var cur := start
		while true:
			var nxt := -1
			var gap := INF
			# (at a fork: the way an edge really runs - along an open rim, else along a sharp bend - before its
			# places, which old edits can leave out of order)
			var open_ones := []
			var sharp_ones := []
			for b in adj[cur]:
				if seen.has(b):
					continue
				var bb: float = bent.call(_pk(cur, b))
				if bb >= 179.0:
					open_ones.append(b)
				elif bb > 45.0:
					sharp_ones.append(b)
			var allowed: Array = open_ones if not open_ones.is_empty() else (sharp_ones if not sharp_ones.is_empty() else adj[cur])
			for b in allowed:
				if seen.has(b):
					continue
				# (the next place on: a fork resolved by the places, wrapping round a closed edge)
				var d: float = float(place[b]) - float(place[cur])
				if closed and d < 0.0:
					d += 1.0
				if d < 0.0:
					d += 10.0   # (going back: only if nothing goes on)
				if d < gap:
					gap = d
					nxt = b
			if nxt < 0:
				break
			walk.append(nxt)
			seen[nxt] = true
			cur = nxt
		if walk.size() < 2:
			for a in pts:
				out.append([a, ci, float(place[a])])   # (no path through the mesh at all: as it was)
			continue
		var total := 0.0
		for i in range(1, walk.size()):
			total += v[walk[i - 1]].distance_to(v[walk[i]])
		if closed:
			total += v[walk.back()].distance_to(v[walk[0]])
		var acc := 0.0
		for i in walk.size():
			if i > 0:
				acc += v[walk[i - 1]].distance_to(v[walk[i]])
			out.append([int(walk[i]), ci, acc / maxf(total, 1e-12)])
	return out


## Faces bigger than big_face quads cut in two, again and again till none is: across each, the shortest path
## through it between two points of its rim roughly opposite each other - short for the rim it divides - a
## chain of its own (appended, let go of after). Flattened in one piece, a big curved face's grid comes back
## uneven; its pieces flatten with far less distortion. {fv, chains}.
static func split_big(v: PackedVector3Array, t: PackedInt32Array, fv_in: Array, chains_in: Array, L: float) -> Dictionary:
	var fv := fv_in.duplicate(true)
	var chains := chains_in.duplicate(true)
	for round_i in 40:
		var feat := {}
		var by_c := {}
		for e in fv:
			if not by_c.has(int(e[1])):
				by_c[int(e[1])] = []
			by_c[int(e[1])].append([float(e[2]), int(e[0])])
		for ci in by_c:
			var lst: Array = by_c[ci]
			lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			for m in range(1, lst.size()):
				if int(lst[m - 1][1]) != int(lst[m][1]):
					feat[_pk(int(lst[m - 1][1]), int(lst[m][1]))] = true
			if ci < chains.size() and bool(chains[ci].get("closed", false)) and lst.size() > 2:
				feat[_pk(int(lst.back()[1]), int(lst[0][1]))] = true
		var face: PackedInt32Array = face_of(v, t, feat)
		var nf := 0
		for f in face:
			nf = maxi(nf, f + 1)
		var f_tris := []
		var f_area := PackedFloat64Array()
		f_tris.resize(nf)
		f_area.resize(nf)
		for f in nf:
			f_tris[f] = []
		for ti in face.size():
			(f_tris[face[ti]] as Array).append(ti)
			f_area[face[ti]] += (v[t[ti * 3 + 1]] - v[t[ti * 3]]).cross(v[t[ti * 3 + 2]] - v[t[ti * 3]]).length() * 0.5
		var biggest := -1
		for f in nf:
			if f_area[f] / (L * L) > big_face and (biggest < 0 or f_area[f] > f_area[biggest]):
				biggest = f
		if biggest < 0:
			break
		var tris: Array = f_tris[biggest]
		var cnt := {}
		var adj := {}
		for ti in tris:
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				var k := _pk(a, b)
				cnt[k] = int(cnt.get(k, 0)) + 1
				if not adj.has(a):
					adj[a] = {}
				if not adj.has(b):
					adj[b] = {}
				adj[a][b] = true
				adj[b][a] = true
		var nxt := {}
		for ti in tris:
			for j in 3:
				var a := t[ti * 3 + j]
				var b := t[ti * 3 + (j + 1) % 3]
				if int(cnt[_pk(a, b)]) == 1:
					nxt[a] = b
		if nxt.is_empty():
			break
		# its outer rim, in order
		var bnd := {}
		for a in nxt:
			bnd[a] = [nxt[a]]
		var st: int = nxt.keys()[0]
		var rim := [st]
		var cur: int = nxt[st]
		var guard := 0
		while cur != st and nxt.has(cur) and guard < nxt.size() + 2:
			rim.append(cur)
			cur = nxt[cur]
			guard += 1
		var M := rim.size()
		if M < 8:
			break
		var cum := PackedFloat64Array([0.0])
		for i in M:
			cum.append(cum[i] + v[rim[i]].distance_to(v[rim[(i + 1) % M]]))
		var per := cum[M]
		# candidate cuts: from a dozen points round the rim to the points about half way round from each
		var best_path := []
		var best_sc := INF
		for c in 12:
			var i0 := (c * M) / 12
			var to := {}
			for j in M:
				var d := fposmod(cum[j] - cum[i0], per)
				if d > per * 0.35 and d < per * 0.65:
					to[rim[j]] = true
			var path := _shortest(v, adj, [rim[i0]], to, {}, bnd)
			if path.size() < 3:
				continue
			var plen := 0.0
			for q in range(1, path.size()):
				plen += v[path[q - 1]].distance_to(v[path[q]])
			var sc := plen / per
			if sc < best_sc:
				best_sc = sc
				best_path = path
		if best_path.is_empty():
			break
		var ci := chains.size()
		chains.append({"id": -5000 - ci, "closed": false})
		var total := 0.0
		for q in range(1, best_path.size()):
			total += v[best_path[q - 1]].distance_to(v[best_path[q]])
		var acc := 0.0
		for q in best_path.size():
			if q > 0:
				acc += v[best_path[q - 1]].distance_to(v[best_path[q]])
			fv.append([int(best_path[q]), ci, acc / maxf(total, 1e-12)])
	return {"fv": fv, "chains": chains}


## (grid_faces) A kept face filled by field_remesh.fill_face, its rim the points it already has (`new_of`: old
## vertex -> new; each rim point added if it isn't yet): the fill's quads split along an inside diagonal, its
## new points added (fill_out_v, fill_out_t - packed arrays come back, not changed in place). False - it couldn't.
static func _fill_kept_face(v: PackedVector3Array, t: PackedInt32Array, tris: Array, on: Dictionary, new_of: Dictionary, add_fv: Callable, out_v: PackedVector3Array, out_t: PackedInt32Array, L: float, rim_split := {}, rim_inner := {}) -> bool:
	fill_out_t = PackedInt32Array()
	# its rim's samples: the old points kept (junctions, open sides' points - new_of), the resampled edges' new ones
	var keep_pts := {}
	var scnt := {}
	for ti in tris:
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			scnt[k] = int(scnt.get(k, 0)) + 1
	for ti in tris:
		for j in 3:
			var x := t[ti * 3 + j]
			if int(scnt[_pk(x, t[ti * 3 + (j + 1) % 3])]) != 1:
				continue   # (rim points only)
			if not rim_inner.has(x) and not keep_pts.has(x):
				if not new_of.has(x):
					new_of[x] = out_v.size()
					out_v.append(v[x])
					for cj in on.get(x, {}):
						add_fv.call(new_of[x], int(cj), float(on[x][cj]))
				keep_pts[x] = new_of[x]
	# (the same face with the same rim samples filled before - an earlier round: that fill again)
	var slist := []
	var sig := PackedStringArray([str(tris.size()), str(tris[0]), str(tris.back())])
	for ti in tris:
		for j in 3:
			var x := t[ti * 3 + j]
			var y := t[ti * 3 + (j + 1) % 3]
			if keep_pts.has(x):
				slist.append(keep_pts[x])
			for sk in [Vector2i(x, y), Vector2i(y, x)]:
				for e in rim_split.get(sk, []):
					slist.append(int(e[1]))
	for id in slist:
		sig.append(str(out_v[id]))
	var key := "|".join(sig).hash()
	var FR: GDScript = load("res://scripts/editor/mesh/field_remesh.gd")
	var res: Dictionary
	var was_cached := fill_cache.has(key)
	if was_cached:
		var c: Dictionary = fill_cache[key]
		res = {"pts": c["pts"], "faces": []}
		for f in c["faces"]:
			res["faces"].append((f as Array).map(func(x): return -1 - int(slist[-1 - int(x)]) if int(x) < 0 else int(x)))
	else:
		var pt0 := Time.get_ticks_usec()
		res = FR.fill_face(v, t, tris, [], L, true, {"keep": keep_pts, "split": rim_split})
		prof["fill"] = float(prof.get("fill", 0.0)) + (Time.get_ticks_usec() - pt0) / 1000.0
		if not res.is_empty():
			var at := {}
			for i in slist.size():
				if not at.has(slist[i]):
					at[slist[i]] = i
			var faces := []
			for f in res["faces"]:
				faces.append((f as Array).map(func(x): return -1 - int(at[-1 - int(x)]) if int(x) < 0 else int(x)))
			fill_cache[key] = {"pts": res["pts"], "faces": faces}
	var nq := 0
	for f in res.get("faces", []):
		nq += 1 if (f as Array).size() == 4 else 0
	fill_log.append([tris.size(), not res.is_empty(), str(FR.get("why")), nq, res.get("faces", []).size() - nq, "cached" if was_cached else int(FR.get("stats").get("ms", 0))])
	if res.is_empty() and tris.size() <= 64:
		# (a small face the fill can't do: its rim's samples cut into triangles across it, flat)
		var st := _small_fill(v, t, tris, keep_pts, rim_split, out_v)
		fill_log.append(["small", small_why if st.is_empty() else "ok"])
		if not st.is_empty():
			fill_out_t = st
			fill_out_v = out_v
			fill_count += 1
			return true
	if res.is_empty():
		fill_out_v = out_v
		return false
	var base := out_v.size()
	for q in (res["pts"] as PackedVector3Array):
		out_v.append(q)
	var idx := func(x: int) -> int:
		return -1 - x if x < 0 else base + x
	for f in res["faces"]:
		var c := (f as Array).map(func(x): return idx.call(int(x)))
		if c.size() == 3:
			fill_out_t.append_array(PackedInt32Array(c))
		else:
			var a: int = c[0]
			var b: int = c[1]
			var cc: int = c[2]
			var d: int = c[3]
			var qn := (out_v[cc] - out_v[a]).cross(out_v[b] - out_v[d])
			var ac_ok := _tri_face(out_v, a, b, cc).dot(qn) > 0.0 and _tri_face(out_v, a, cc, d).dot(qn) > 0.0
			var bd_ok := _tri_face(out_v, a, b, d).dot(qn) > 0.0 and _tri_face(out_v, b, cc, d).dot(qn) > 0.0
			var use_ac := out_v[a].distance_squared_to(out_v[cc]) >= out_v[b].distance_squared_to(out_v[d])
			if use_ac and not ac_ok and bd_ok:
				use_ac = false
			elif not use_ac and not bd_ok and ac_ok:
				use_ac = true
			if use_ac:
				fill_out_t.append_array(PackedInt32Array([a, b, cc, a, cc, d]))
			else:
				fill_out_t.append_array(PackedInt32Array([a, b, d, b, cc, d]))
	fill_count += 1
	fill_out_v = out_v
	return true


## (_fill_kept_face) A small face's rim samples - its kept points and the samples on its sides, in order round
## it - cut into triangles (ear by ear, in the plane it faces), wound as its triangles are. Empty: it couldn't
## (more than one rim loop, a rim touching itself).
static func _small_fill(v: PackedVector3Array, t: PackedInt32Array, tris: Array, keep_pts: Dictionary, rim_split: Dictionary, out_v: PackedVector3Array) -> PackedInt32Array:
	var cnt := {}
	var n := Vector3.ZERO
	for ti in tris:
		n += _tri_face(v, t[ti * 3], t[ti * 3 + 1], t[ti * 3 + 2])
		for j in 3:
			var k := _pk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
			cnt[k] = int(cnt.get(k, 0)) + 1
	if n.length_squared() < 1e-30:
		small_why = "no normal"
		return PackedInt32Array()
	n = n.normalized()
	var nxt := {}
	for ti in tris:
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			if int(cnt[_pk(a, b)]) == 1:
				if nxt.has(a):
					small_why = "rim touches itself"
					return PackedInt32Array()
				nxt[a] = b
	if nxt.is_empty():
		small_why = "no rim"
		return PackedInt32Array()
	# its rim loops as sample ids
	var loops := []
	var left_s := nxt.duplicate()
	while not left_s.is_empty():
		var st: int = left_s.keys()[0]
		var lp := []
		var cur := st
		while true:
			if not left_s.has(cur):
				small_why = "rim breaks"
				return PackedInt32Array()
			var b2: int = left_s[cur]
			left_s.erase(cur)
			if keep_pts.has(cur):
				lp.append(int(keep_pts[cur]))
			var lst := []
			for e in rim_split.get(Vector2i(cur, b2), []):
				lst.append([float(e[0]), int(e[1])])
			for e in rim_split.get(Vector2i(b2, cur), []):
				lst.append([1.0 - float(e[0]), int(e[1])])
			lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			for e in lst:
				lp.append(int(e[1]))
			cur = b2
			if cur == st:
				break
		if lp.size() < 2:
			small_why = "a loop of too few samples"
			return PackedInt32Array()
		loops.append(lp)
	# ears, in the plane: e1, e2 with the face's normal
	var e1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := n.cross(e1)
	var p2 := {}
	for lp in loops:
		for id in lp:
			p2[id] = Vector2(out_v[id].dot(e1), out_v[id].dot(e2))
	# (holes bridged into the outer loop - the biggest - at their nearest points: one polygon)
	var areas := []
	for lp in loops:
		var ar := 0.0
		for k in lp.size():
			ar += (p2[lp[k]] as Vector2).cross(p2[lp[(k + 1) % lp.size()]])
		areas.append(absf(ar))
	var oi := 0
	for k in loops.size():
		if float(areas[k]) > float(areas[oi]):
			oi = k
	var poly: Array = loops[oi]
	for k in loops.size():
		if k == oi:
			continue
		var hole: Array = loops[k]
		var bi := 0
		var bj := 0
		var bd := INF
		for i2 in poly.size():
			for j2 in hole.size():
				var d := (p2[poly[i2]] as Vector2).distance_squared_to(p2[hole[j2]])
				if d < bd:
					bd = d
					bi = i2
					bj = j2
		var spliced := poly.slice(0, bi + 1)
		spliced.append_array(hole.slice(bj))
		spliced.append_array(hole.slice(0, bj + 1))
		spliced.append_array(poly.slice(bi))
		poly = spliced
	if poly.size() < 3:
		small_why = "too few samples"
		return PackedInt32Array()
	var area := 0.0
	for i in poly.size():
		var a: Vector2 = p2[poly[i]]
		var b: Vector2 = p2[poly[(i + 1) % poly.size()]]
		area += a.cross(b)
	var ccw := area > 0.0
	var left := poly.duplicate()
	var out := PackedInt32Array()
	var guard := 0
	while left.size() > 3 and guard < 4000:
		guard += 1
		var best := -1
		var best_q := -INF
		for i in left.size():
			var a: Vector2 = p2[left[(i - 1 + left.size()) % left.size()]]
			var b: Vector2 = p2[left[i]]
			var c: Vector2 = p2[left[(i + 1) % left.size()]]
			var cr := (b - a).cross(c - b)
			if (cr > 0.0) != ccw or absf(cr) < 1e-20:
				continue
			var inside := false
			for q in left:
				var pq: Vector2 = p2[q]
				if q == left[i] or q == left[(i - 1 + left.size()) % left.size()] or q == left[(i + 1) % left.size()]:
					continue
				var d1 := (b - a).cross(pq - a)
				var d2 := (c - b).cross(pq - b)
				var d3 := (a - c).cross(pq - c)
				if (d1 > 0.0) == ccw and (d2 > 0.0) == ccw and (d3 > 0.0) == ccw:
					inside = true
					break
			if inside:
				continue
			# (the roundest ear first)
			var la := a.distance_to(b)
			var lb := b.distance_to(c)
			var lc := c.distance_to(a)
			var q := absf(cr) / maxf(la * la + lb * lb + lc * lc, 1e-30)
			if q > best_q:
				best_q = q
				best = i
		if best < 0:
			small_why = "no ear"
			return PackedInt32Array()
		var ia: int = left[(best - 1 + left.size()) % left.size()]
		var ib: int = left[best]
		var ic: int = left[(best + 1) % left.size()]
		out.append_array(PackedInt32Array([ia, ib, ic]))
		left.remove_at(best)
	if left.size() == 3:
		out.append_array(PackedInt32Array([left[0], left[1], left[2]]))
	# (wound as the face's triangles: facing n)
	if out.size() >= 3 and _tri_face(out_v, out[0], out[1], out[2]).dot(n) < 0.0:
		for i in range(0, out.size(), 3):
			var x := out[i + 1]
			out[i + 1] = out[i + 2]
			out[i + 2] = x
	return out

