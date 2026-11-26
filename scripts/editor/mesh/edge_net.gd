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
static func trace(m: ArrayMesh) -> Dictionary:
	var pos := {}   # weld key -> position
	var tris := []   # [k0, k1, k2] keys
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
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
	var lim := cos(deg_to_rad(SHARP_DEG))
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
	# chains: from each corner (not two sharp edges) along to the next; what's left - closed loops
	var used := {}
	var chains := []
	for v in adj:
		if (adj[v] as Array).size() == 2:
			continue
		for w in adj[v]:
			if used.has(_ekey(v, w)):
				continue
			chains.append({"pts": _walk(v, w, adj, used, pos), "closed": false})
	for v in adj:
		for w in adj[v]:
			if used.has(_ekey(v, w)):
				continue
			var pts := _walk(v, w, adj, used, pos)
			if pts.size() > 2 and key(pts[0]) == key(pts[pts.size() - 1]):
				pts.remove_at(pts.size() - 1)
			chains.append({"pts": pts, "closed": true})
	return {"chains": chains.filter(func(c): return (c["pts"] as PackedVector3Array).size() >= 2)}


static func _ekey(a: Vector3i, b: Vector3i) -> String:
	return str(a) + "|" + str(b) if str(a) < str(b) else str(b) + "|" + str(a)


static func _walk(v: Vector3i, w: Vector3i, adj: Dictionary, used: Dictionary, pos: Dictionary) -> PackedVector3Array:
	var pts := PackedVector3Array([pos[v]])
	var prev := v
	var cur := w
	used[_ekey(v, w)] = true
	while true:
		pts.append(pos[cur])
		var nb: Array = adj[cur]
		if nb.size() != 2 or cur == v:
			break   # (a corner - or round to where it began)
		var nxt: Vector3i = nb[0] if nb[1] == prev else nb[1]
		if used.has(_ekey(cur, nxt)):
			break
		used[_ekey(cur, nxt)] = true
		prev = cur
		cur = nxt
	return pts


## A chain of points as a curve with as few points as keep its shape: a straight edge - its two ends;
## an arc (its points on one circle) - three; a closed circle - a circle; else a lean path (corners
## kept sharp) or, not flat, a polyline through the points that matter.
static func chain_curve(pts: PackedVector3Array, closed: bool) -> Dictionary:
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
		if straight:
			return {"kind": "line", "ctrl": PackedVector3Array([a, b]), "closed": false, "n": n if flat else _any_n(a, b)}
		var mid := pts[pts.size() / 2]
		var ctr := CT.circumcentre(a, mid, b)
		if ctr != Vector3.INF and flat:
			var r := ctr.distance_to(a)
			var round_ := true
			for q in pts:
				if absf(q.distance_to(ctr) - r) > tol:
					round_ = false
					break
			if round_:
				return {"kind": "arc", "ctrl": PackedVector3Array([a, mid, b]), "closed": false, "n": n}
		return {"kind": "line", "ctrl": _lean(pts, tol, false), "closed": false, "n": n if flat else _any_n(a, b)}
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
static func _lean(pts: PackedVector3Array, tol: float, closed: bool) -> PackedVector3Array:
	if pts.size() <= 2:
		return pts.duplicate()
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var far := 0
	if closed:   # (a loop: split at its point furthest from the first)
		var best := -1.0
		for i in pts.size():
			var d := pts[i].distance_to(pts[0])
			if d > best:
				best = d
				far = i
		keep[far] = 1
		_dp(pts, 0, far, tol, keep)
		_dp(pts, far, pts.size() - 1, tol, keep)
	else:
		_dp(pts, 0, pts.size() - 1, tol, keep)
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
static func faces(m: ArrayMesh, chains: Array) -> Array:
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
		var a := m.surface_get_arrays(si)
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
static func remesh(m: ArrayMesh, chains: Array, L: float) -> Dictionary:
	var V := []
	var idx := {}
	var T := []
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
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


## The edge points' moves (vertex -> move): each as its curve moved there, a corner the largest.
static func edge_moves(fv: Array, chains: Array, old: Dictionary, now: Dictionary, v: PackedVector3Array) -> Dictionary:
	var moves := {}
	for e in fv:
		var vi := int(e[0])
		var ch: Dictionary = chains[int(e[1])]
		var id := int(ch["id"])
		if not old.has(id) or not now.has(id):
			continue
		var c0: Dictionary = old[id]
		var c1: Dictionary = now[id]
		var d: Vector3
		if str(c0["kind"]) == "circle" and str(c1["kind"]) == "circle":
			d = _round_move(v[vi], c0, c1)
		else:
			d = at(c1, float(e[2])) - at(c0, float(e[2]))
		if not moves.has(vi) or (moves[vi] as Vector3).length() < d.length():
			moves[vi] = d
	return moves


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
	var by_n := {}
	for i in range(0, t.size(), 3):
		var nrm := (v[t[i + 2]] - v[t[i]]).cross(v[t[i + 1]] - v[t[i]])
		for j in 3:
			var e := _pk(t[i + j], t[i + (j + 1) % 3])
			if not by_n.has(e):
				by_n[e] = []
			by_n[e].append(nrm)
	var c45 := cos(deg_to_rad(45.0))
	for e in by_n:
		var ns: Array = by_n[e]
		if ns.size() == 2 and (ns[0] as Vector3).length() > 1e-14 and (ns[1] as Vector3).length() > 1e-14 and (ns[0] as Vector3).normalized().dot((ns[1] as Vector3).normalized()) < c45:
			out[e] = true
	return out


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
		var n := Vector3.ZERO
		for ti in g:
			var tr: Array = tris[ti]
			n += ((v[tr[2]] as Vector3) - v[tr[0]]).cross((v[tr[1]] as Vector3) - v[tr[0]])
		if n.length() < 1e-12 or g.size() < 2:
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
		for ti in g:
			drop[ti] = true
		add.append_array(outs)
	if drop.is_empty():
		return false
	var keep := []
	for ti in nt:
		if not drop.has(ti):
			keep.append(t[ti])
	t.clear()
	t.append_array(keep)
	t.append_array(add)
	return true


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
			var prev := lo_t
			var n_run := b - j
			for m in range(j, b):
				var tw := want[m]
				if tw < lo_t - 1e-9 and hi_t > 1.0:
					tw += 1.0
				var room_hi := hi_t - gap * float(b - m)
				tw = clampf(tw, prev + gap, maxf(prev + gap, room_hi))
				want[m] = tw
				prev = tw
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
static func _split_bent(v: Array, t: Array, fv: Array, chains: Array, now: Dictionary, feat: Dictionary, max_deg: float, min_len: float) -> bool:
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
	for e in qside:
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
	if quads.size() > 0 and cut.size() > quads.size() / 2:
		return false   # (bends all over: creases, not curvature - left as it is)
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
						# side residuals (a side point's move less what its rails would give it), by 1 / d^4
						var tot := 0.0
						var sw := {}
						for e in eds:
							var wt := 1.0 / maxf(pow(v[vi].distance_squared_to(v[e]), 2.0), 1e-18)
							tot += wt
							if sides.has(e):
								sw[e] = wt
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
			var near := []
			for e in eds:
				near.append([v[vi].distance_squared_to(v[e]), e])
			if near.size() > 400:
				near.sort_custom(func(x, y): return x[0] < y[0])
				near.resize(400)
			var ws := PackedFloat32Array()
			var es := PackedInt32Array()
			var sum := 0.0
			for nv in near:
				var wt := 1.0 / maxf(float(nv[0]) * float(nv[0]), 1e-18)   # (1 / distance to the 4th: the near edge counts most)
				es.append(int(nv[1]))
				ws.append(wt)
				sum += wt
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
	return {"u": ulist, "ucol": ucol, "uface": uface, "rs": rs, "rc": rc, "rv": rv, "fs": fs, "fi": fidx, "fw": fwt, "fm": fmode, "diag": diag}


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
	# each column face's points' straight-between-rails place (and its side points')
	var vert := {}
	var faces: Array = bw["faces"]
	var vert_of := func(fi: int, vi: int) -> Vector3:
		var key2 := "%d:%d" % [fi, vi]
		if vert.has(key2):
			return vert[key2]
		var cmap: Dictionary = (faces[fi] as Dictionary).get("cols", {})
		if not cmap.has(vi):
			return d[vi]   # (not one of this face's columns: as it is)
		var ce: Array = cmap[vi]
		var q := Vector3.ZERO
		for k in (ce[0] as PackedInt32Array).size():
			q += d[ce[0][k]] * float(ce[1][k])
		vert[key2] = q
		return q
	var base := PackedVector3Array()
	base.resize(m)
	for ui in m:
		if ucol[ui] == 1:
			base[ui] = vert_of.call(int(cg["uface"][ui]), u[ui])
	# the right-hand side: what the fixed neighbours hold each unknown to
	var bvec := PackedVector3Array()
	bvec.resize(m)
	var fs: PackedInt32Array = cg["fs"]
	var fi_: PackedInt32Array = cg["fi"]
	var fw: PackedFloat32Array = cg["fw"]
	var fm: PackedByteArray = cg["fm"]
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
				s += (d[o] - vert_of.call(int(cg["uface"][ui]), o)) * fw[k]
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
static func quad_mesh(m: ArrayMesh, chains: Array, L: float) -> Dictionary:
	# the mesh welded
	var V := []
	var idx := {}
	var T := []
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
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
