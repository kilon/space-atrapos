extends RefCounted
## AUTO JOIN (ECurves): solids that meet along one edge - an edge of each in nearly the same place, nearly
## the same shape, both open there (a seam: the surface stops at it on both sides) - made one solid. Of
## each such pair of edges one is kept; the two meshes are welded along it with no gap: each side given the
## points the other has on the seam by cutting a row of quads through its quads (a loop cut - quads stay
## quads), then the points made one. Their materials kept (the joined solid's triangles each keep the
## material of the solid they came from - `regions`), their bone weights kept (their sources joined too,
## by the caller), and only solids with the same bone association are joined.
## Pure functions on arrays: run on a worker.

const CT := preload("res://scripts/editor/mesh/curve_tools.gd")
const EN := preload("res://scripts/editor/mesh/edge_net.gd")
const N_CMP := 48   # (points each edge is compared by)


## An edge's points evenly along it (by length), `n` of them (a closed one: not repeating its first).
static func even_points(c: Dictionary, xf: Transform3D, n := N_CMP) -> PackedVector3Array:
	var s := CT.sample(c)
	var closed := bool(c.get("closed", false))
	if closed and s.size() > 0:
		s.append(s[0])
	for i in s.size():
		s[i] = xf * s[i]
	var lens := PackedFloat32Array([0.0])
	for i in range(1, s.size()):
		lens.append(lens[i - 1] + s[i - 1].distance_to(s[i]))
	var total := lens[lens.size() - 1] if lens.size() > 0 else 0.0
	var out := PackedVector3Array()
	if s.size() < 2 or total <= 0.0:
		return out
	var k := 0
	var cnt := n if closed else n
	for j in cnt:
		var at := total * (float(j) / float(n if closed else n - 1))
		while k < lens.size() - 2 and lens[k + 1] < at:
			k += 1
		var seg := lens[k + 1] - lens[k]
		var f := 0.0 if seg <= 0.0 else clampf((at - lens[k]) / seg, 0.0, 1.0)
		out.append(s[k].lerp(s[k + 1], f))
	return out


static func _length(p: PackedVector3Array, closed: bool) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	if closed and p.size() > 1:
		l += p[p.size() - 1].distance_to(p[0])
	return l


## The farthest any point of `a` is from the line through `b`'s points.
static func _far(a: PackedVector3Array, b: PackedVector3Array, closed: bool) -> float:
	var worst := 0.0
	var nb := b.size()
	for q in a:
		var best := INF
		var lim := nb if closed else nb - 1
		for i in lim:
			var cp := Geometry3D.get_closest_point_to_segment(q, b[i], b[(i + 1) % nb])
			best = minf(best, cp.distance_squared_to(q))
		worst = maxf(worst, best)
	return sqrt(worst)


## The open sides of a mesh's triangles (a side with one triangle only): {"a_b" (a < b): true}.
static func open_sides(t: Array) -> Dictionary:
	var cnt := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := int(t[i + j])
			var b := int(t[i + (j + 1) % 3])
			var k := Vector2i(mini(a, b), maxi(a, b))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var out := {}
	for k in cnt:
		if int(cnt[k]) == 1:
			out[k] = true
	return out


## Whether chain `ci` of a solid (its points from `fv`) runs along the mesh's open border all the way.
static func chain_open(fv: Array, ci: int, open: Dictionary, closed: bool, used := {}) -> bool:
	var lst := []
	for e in fv:
		if int(e[1]) == ci and (used.is_empty() or used.has(int(e[0]))):
			lst.append([float(e[2]), int(e[0])])
	if lst.size() < 2:
		return false
	lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var vs := []
	for x in lst:
		if vs.is_empty() or vs.back() != int(x[1]):
			vs.append(int(x[1]))
	if closed and vs.size() > 2 and vs[0] != vs.back():
		vs.append(vs[0])
	for i in range(1, vs.size()):
		var a: int = vs[i - 1]
		var b: int = vs[i]
		if not open.has(Vector2i(mini(a, b), maxi(a, b))):
			return false
	return true


## The pairs of edges that make solids meet. `solids`: [{group (only solids of one group join), xf (its
## part's place in the model), spec (its recipe - an "edges" one), curves: {id: curve}}...]. `tol`: how far
## apart two edges may be (at least - each pair allows 3% of its shorter edge's length too). [[solid a,
## curve id a, solid b, curve id b, how far apart]...], nearest first, each edge in one pair at most.
static func find_pairs(solids: Array, tol := 0.001) -> Array:
	var edges := []   # [solid, id, points, closed, length, box]
	for si in solids.size():
		var s: Dictionary = solids[si]
		var spec: Dictionary = s["spec"]
		var chains: Array = spec.get("chains", [])
		var fv: Array = spec.get("fv", [])
		var open := open_sides(spec.get("mesh", {}).get("t", []))
		if open.is_empty():
			continue   # (closed all round: nowhere to meet another along a seam)
		var used := {}
		for x in spec.get("mesh", {}).get("t", []):
			used[int(x)] = true   # (an edge's points no triangle uses - left over: not part of it)
		for ci in chains.size():
			var id := int(chains[ci]["id"])
			var c: Dictionary = (s["curves"] as Dictionary).get(id, {})
			if c.is_empty():
				continue
			var closed := bool(c.get("closed", false))
			if not chain_open(fv, ci, open, closed, used):
				continue
			var pts := even_points(c, s["xf"])
			if pts.size() < 2:
				continue
			var box := AABB(pts[0], Vector3.ZERO)
			for q in pts:
				box = box.expand(q)
			edges.append([si, id, pts, closed, _length(pts, closed), box])
	var found := []
	for i in edges.size():
		var a: Array = edges[i]
		for j in range(i + 1, edges.size()):
			var b: Array = edges[j]
			if int(a[0]) == int(b[0]) or bool(a[3]) != bool(b[3]):
				continue
			if str(solids[a[0]].get("group", "")) != str(solids[b[0]].get("group", "")):
				continue
			var la: float = a[4]
			var lb: float = b[4]
			var tl := maxf(tol, 0.03 * minf(la, lb))
			if absf(la - lb) > 0.12 * maxf(la, lb) + tl:
				continue
			if not (a[5] as AABB).grow(tl).intersects((b[5] as AABB).grow(tl)):
				continue
			var d := maxf(_far(a[2], b[2], bool(b[3])), _far(b[2], a[2], bool(a[3])))
			if d <= tl:
				found.append([int(a[0]), int(a[1]), int(b[0]), int(b[1]), d])
	found.sort_custom(func(x, y): return float(x[4]) < float(y[4]))
	var used := {}
	var out := []
	for f in found:
		var ka := Vector2i(int(f[0]), int(f[1]))
		var kb := Vector2i(int(f[2]), int(f[3]))
		if used.has(ka) or used.has(kb):
			continue
		used[ka] = true
		used[kb] = true
		out.append(f)
	return out


# --- the join ----------------------------------------------------------------------------------------

## Solids joined into one along their paired edges. `parts`: [{v: PackedVector3Array, t: PackedInt32Array,
## fv, chains, c0 (all in the joined solid's space - the first's), mat: its material's number}...];
## `pairs`: [[part a, chain a, part b, chain b]...] (chains by their index in their part; a's edge kept).
## {v, t, fv, chains, c0, ids, tmat (each triangle's material), anchors: [[a point inside, material]...],
## seams (the kept edges between two materials, by id)} - or {error}.
static func join(parts: Array, pairs: Array) -> Dictionary:
	var st := {"v": [], "faces": [], "fmat": [], "fsrc": [], "fv": [], "nrm": [], "on": {}}
	var chains := []
	var c0 := {}
	var c_off := []
	for P: Dictionary in parts:
		var nv0: int = (st["v"] as Array).size()
		var nc0 := chains.size()
		c_off.append(nc0)
		var pv: PackedVector3Array = P["v"]
		for q in pv:
			(st["v"] as Array).append(q)
		for e in P["fv"]:
			(st["fv"] as Array).append([int(e[0]) + nv0, int(e[1]) + nc0, float(e[2])])
		for ch in P["chains"]:
			chains.append((ch as Dictionary).duplicate())
		for k in (P["c0"] as Dictionary):
			c0[k] = P["c0"][k]
		for f in EN._pair_faces(pv, P["t"], P["fv"]):
			(st["faces"] as Array).append((f as Array).map(func(x): return int(x) + nv0))
			(st["fmat"] as Array).append(int(P["mat"]))
			(st["fsrc"] as Array).append(c_off.size() - 1)
	_normals(st)
	_index(st)
	var dropped := {}
	var seams := []
	for pr in pairs:
		var ka: int = c_off[int(pr[0])] + int(pr[1])
		var kb: int = c_off[int(pr[2])] + int(pr[3])
		var cs := CT.from_json([c0.get(str(int(chains[ka]["id"])), {})])
		if cs.is_empty():
			return {"error": "an edge without its curve"}
		var err := _weld(st, ka, kb, cs[0], bool(chains[ka].get("closed", false)))
		if err != "":
			return {"error": err}
		dropped[kb] = true
		if int(parts[int(pr[0])]["mat"]) != int(parts[int(pr[2])]["mat"]):
			seams.append(int(chains[ka]["id"]))
	# the edges dropped gone, the points no face uses gone, the faces as triangles
	var cmap := {}
	var out_chains := []
	var ids := []
	for ci in chains.size():
		if dropped.has(ci):
			c0.erase(str(int(chains[ci]["id"])))
			continue
		cmap[ci] = out_chains.size()
		out_chains.append(chains[ci])
		ids.append(int(chains[ci]["id"]))
	var v_all: Array = st["v"]
	var used := PackedInt32Array()
	used.resize(v_all.size())
	used.fill(-1)
	var v := PackedVector3Array()
	for f in st["faces"]:
		for x in f:
			if used[int(x)] < 0:
				used[int(x)] = v.size()
				v.append(v_all[int(x)])
	var fv := []
	var seen := {}
	for e in st["fv"]:
		if not cmap.has(int(e[1])) or used[int(e[0])] < 0:
			continue
		var k := Vector2i(used[int(e[0])], int(cmap[int(e[1])]))
		if seen.has(k):
			continue
		seen[k] = true
		fv.append([k.x, k.y, float(e[2])])
	var t0 := PackedInt32Array()
	var tm0 := PackedInt32Array()
	var ts0 := PackedInt32Array()
	var faces: Array = st["faces"]
	for fi in faces.size():
		var f: Array = (faces[fi] as Array).map(func(x): return used[int(x)])
		var m: int = st["fmat"][fi]
		var sr: int = st["fsrc"][fi]
		if f.size() == 3:
			t0.append_array(PackedInt32Array(f))
			tm0.append(m)
			ts0.append(sr)
		elif f.size() == 4:
			if v[f[0]].distance_squared_to(v[f[2]]) >= v[f[1]].distance_squared_to(v[f[3]]):
				t0.append_array(PackedInt32Array([f[0], f[1], f[2], f[0], f[2], f[3]]))
			else:
				t0.append_array(PackedInt32Array([f[1], f[2], f[3], f[1], f[3], f[0]]))
			tm0.append_array(PackedInt32Array([m, m]))
			ts0.append_array(PackedInt32Array([sr, sr]))
	# (where two of the solids had a triangle in one place - touching face to face, a cap each: that inner
	# double wall gone, as a union would; the same way round: kept once. Each solid's own as it was.)
	var by_set := {}
	for ti in ts0.size():
		var key := [t0[ti * 3], t0[ti * 3 + 1], t0[ti * 3 + 2]]
		key.sort()
		if not by_set.has(key):
			by_set[key] = []
		(by_set[key] as Array).append(ti)
	var gone_t := {}
	for key in by_set:
		var l: Array = by_set[key]
		for x in l.size():
			for y in range(x + 1, l.size()):
				var ta: int = l[x]
				var tb: int = l[y]
				if ts0[ta] == ts0[tb] or gone_t.has(ta) or gone_t.has(tb):
					continue
				var tri_a := [t0[ta * 3], t0[ta * 3 + 1], t0[ta * 3 + 2]]
				var tri_b := [t0[tb * 3], t0[tb * 3 + 1], t0[tb * 3 + 2]]
				gone_t[tb] = true
				if not _same_way(tri_a, tri_b):
					gone_t[ta] = true
	var t := PackedInt32Array()
	var tmat := PackedInt32Array()
	for ti in ts0.size():
		if gone_t.has(ti):
			continue
		t.append_array(PackedInt32Array([t0[ti * 3], t0[ti * 3 + 1], t0[ti * 3 + 2]]))
		tmat.append(tm0[ti])
	if not gone_t.is_empty():
		# (points only the dropped walls used: gone too)
		var u2 := PackedInt32Array()
		u2.resize(v.size())
		u2.fill(-1)
		var v2 := PackedVector3Array()
		for i in t.size():
			if u2[t[i]] < 0:
				u2[t[i]] = v2.size()
				v2.append(v[t[i]])
			t[i] = u2[t[i]]
		v = v2
		fv = fv.filter(func(e): return u2[int(e[0])] >= 0).map(func(e): return [u2[int(e[0])], int(e[1]), float(e[2])])
	return {"v": v, "t": t, "fv": fv, "chains": out_chains, "c0": c0, "ids": ids, "tmat": tmat, "seams": seams,
		"anchors": anchors(v, t, tmat)}


## Whether two faces with the same corners go round them the same way.
static func _same_way(a: Array, b: Array) -> bool:
	var i: int = b.find(a[0])
	return i >= 0 and int(b[(i + 1) % b.size()]) == int(a[1])


## Each vertex's normal (the faces round it, by their area) - new points between two get theirs blended.
static func _normals(st: Dictionary) -> void:
	var v: Array = st["v"]
	var n := []
	n.resize(v.size())
	n.fill(Vector3.ZERO)
	for f in st["faces"]:
		var fn := Vector3.ZERO
		for j in (f as Array).size():
			var a: Vector3 = v[f[j]]
			var b: Vector3 = v[f[(j + 1) % f.size()]]
			fn += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		for x in f:
			n[int(x)] += fn
	for i in n.size():
		n[i] = (n[i] as Vector3).normalized() if (n[i] as Vector3).length_squared() > 1e-30 else Vector3.ZERO
	st["nrm"] = n


## The faces by their sides ({Vector2i(lo, hi): [faces]}), and each point's edges ({vertex: {chain: place}}).
static func _index(st: Dictionary) -> void:
	var em := {}
	var faces: Array = st["faces"]
	for fi in faces.size():
		_add_sides(em, faces[fi], fi)
	st["emap"] = em
	var vf := {}
	for f in faces:
		for x in f:
			vf[int(x)] = true
	st["vfaces"] = vf
	var on := {}
	for e in st["fv"]:
		if not on.has(int(e[0])):
			on[int(e[0])] = {}
		on[int(e[0])][int(e[1])] = float(e[2])
	st["on"] = on


static func _add_sides(em: Dictionary, f: Array, fi: int) -> void:
	for j in f.size():
		var k := _sk(int(f[j]), int(f[(j + 1) % f.size()]))
		if not em.has(k):
			em[k] = []
		(em[k] as Array).append(fi)


static func _drop_sides(em: Dictionary, f: Array, fi: int) -> void:
	for j in f.size():
		var k := _sk(int(f[j]), int(f[(j + 1) % f.size()]))
		if em.has(k):
			(em[k] as Array).erase(fi)
			if (em[k] as Array).is_empty():
				em.erase(k)


static func _sk(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


## Chain `k`'s points in order along it: [[place, vertex]...] (each vertex once).
static func _chain_list(st: Dictionary, k: int) -> Array:
	var lst := []
	var seen := {}
	var vf: Dictionary = st["vfaces"]
	for e in st["fv"]:
		if int(e[1]) == k and not seen.has(int(e[0])) and vf.has(int(e[0])):   # (a point no face uses: not on it)
			seen[int(e[0])] = true
			lst.append([float(e[2]), int(e[0])])
	lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	return lst


## How far apart two places along an edge are (a closed one: round the shorter way).
static func _pd(a: float, b: float, closed: bool) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d) if closed else d


## Edge `kb` welded onto edge `ka` (curve `c` - its shape, where the places along it are measured): each side
## given the points the other has (a loop cut through its quads at each), then each point of kb made the
## point of ka in its place. "" or why it couldn't be.
static func _weld(st: Dictionary, ka: int, kb: int, c: Dictionary, closed: bool) -> String:
	var v: Array = st["v"]
	# (one point added at a time, both sides read again after each - a cut can come round through the
	# quads and out on the seam again, adding a point there too)
	var mt := {}
	for round in 2000:
		var la := _chain_list(st, ka)
		var lb0 := _chain_list(st, kb)
		if la.size() < 2 or lb0.size() < 2:
			return "an edge with too few points"
		var bp := PackedVector3Array()
		for x in lb0:
			bp.append(v[int(x[1])])
		var tb := EN.params(bp, c)
		var lb := []
		for i in lb0.size():
			lb.append([tb[i], int(lb0[i][1])])
		lb.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		mt = _match(la, lb, closed)
		var a_matched := {}
		for vb in mt:
			a_matched[int(mt[vb])] = true
		var done := true
		for j in lb.size():
			if mt.has(int(lb[j][1])):
				continue
			# (a b point with no a point: put on a's side - a cut through its quads there)
			if _insert(st, la, float(lb[j][0]), v[int(lb[j][1])], closed, ka) < 0:
				return "a seam point couldn't be put on the other side"
			done = false
			break
		if not done:
			continue
		for i in la.size():
			if a_matched.has(int(la[i][1])):
				continue
			# (an a point with no b point: put on b's side)
			if _insert(st, lb, float(la[i][0]), v[int(la[i][1])], closed, kb) < 0:
				return "a seam point couldn't be put on the other side"
			done = false
			break
		if done:
			break
		if round == 1999:
			return "a seam that wouldn't match up"
	# the b points made the a points
	var faces: Array = st["faces"]
	for fi in faces.size():
		var f: Array = faces[fi]
		var ch := false
		for j in f.size():
			if mt.has(int(f[j])) and int(mt[int(f[j])]) != int(f[j]):
				f[j] = mt[int(f[j])]
				ch = true
		if ch:
			faces[fi] = f
	for e in st["fv"]:
		if mt.has(int(e[0])):
			e[0] = mt[int(e[0])]
	st["fv"] = (st["fv"] as Array).filter(func(e): return int(e[1]) != kb)
	_index(st)
	return ""


## Each b point (of list `lb` - [[place, vertex]...] in order) matched to the a point at its place, when it's
## nearer than 40% of the spacing either side (each a point to one b point at most). {b vertex: a vertex}.
static func _match(la: Array, lb: Array, closed: bool) -> Dictionary:
	var gap := func(l: Array, i: int) -> float:
		var g := INF
		var n := l.size()
		for o in [-1, 1]:
			var j: int = i + o
			if closed:
				j = (j + n) % n
			elif j < 0 or j >= n:
				continue
			if j != i:
				g = minf(g, _pd(float(l[i][0]), float(l[j][0]), closed))
		return g if g < INF else 1.0
	var best_b := {}   # a index -> [distance, b index]
	for j in lb.size():
		var pb: float = lb[j][0]
		var bi := -1
		var bd := INF
		for i in la.size():
			var d := _pd(pb, float(la[i][0]), closed)
			if d < bd:
				bd = d
				bi = i
		if bi >= 0 and (int(lb[j][1]) == int(la[bi][1]) or bd < 0.4 * minf(gap.call(la, bi), gap.call(lb, j))):
			if not best_b.has(bi) or float(best_b[bi][0]) > bd:
				best_b[bi] = [bd, j]
	var out := {}
	for i in best_b:
		out[int(lb[int(best_b[i][1])][1])] = int(la[int(i)][1])
	return out


## A point put on the open border along a seam's list `l` (its points in order along the edge, [[place,
## vertex]...]) at place `pt`, position `pos`: the border's side there cut, a row of quads cut through
## from it (a loop cut) - the list kept in order; on edge `k` (>= 0: its place recorded). The new point.
static func _insert(st: Dictionary, l: Array, pt: float, pos: Vector3, closed: bool, k: int) -> int:
	var n := l.size()
	var lo := -1
	for i in n - 1:
		if float(l[i][0]) <= pt and pt <= float(l[i + 1][0]):
			lo = i
			break
	if lo < 0:
		if not closed:
			return -1
		lo = n - 1   # (between its last point and round to its first)
	var hi := (lo + 1) % n
	var a: int = l[lo][1]
	var b: int = l[hi][1]
	var span := float(l[hi][0]) - float(l[lo][0])
	if span <= 0.0:
		span += 1.0
	var into := pt - float(l[lo][0])
	if into < 0.0:
		into += 1.0
	var s := clampf(into / span, 0.0, 1.0)
	var nv := _cut(st, a, b, s, pos)
	if nv < 0:
		return -1
	if k >= 0:
		(st["fv"] as Array).append([nv, k, pt])
		if not (st["on"] as Dictionary).has(nv):
			st["on"][nv] = {}
		st["on"][nv][k] = pt
	l.insert(lo + 1, [pt, nv])   # (after its last point, round a closed edge: at the end)
	return nv


## A loop cut from the open side a-b, at `s` of the way from a to b (the new point at `pos`): the face
## there split, and on through each quad across from it (each split into two quads) till an open side
## or a triangle. The point made on a-b, or -1 (a-b isn't an open side).
static func _cut(st: Dictionary, a: int, b: int, s: float, pos: Vector3) -> int:
	var em: Dictionary = st["emap"]
	var fs: Array = em.get(_sk(a, b), [])
	if fs.size() != 1:
		return -1
	var v: Array = st["v"]
	var nrm: Array = st["nrm"]
	var faces: Array = st["faces"]
	var fmat: Array = st["fmat"]
	var p := v.size()
	v.append(pos)
	nrm.append(((nrm[a] as Vector3).lerp(nrm[b], s)).normalized())
	st["vfaces"][p] = true
	var first := p
	var f: int = fs[0]
	var ea := a
	var eb := b
	var guard := faces.size() * 4 + 8
	while guard > 0:
		guard -= 1
		var F: Array = faces[f]
		var nF := F.size()
		var i := F.find(ea)
		if i < 0:
			break
		if int(F[(i + 1) % nF]) != eb:
			if int(F[(i - 1 + nF) % nF]) == eb:
				# (this face runs the other way round: from b to a)
				var tmp := ea
				ea = eb
				eb = tmp
				s = 1.0 - s
				i = F.find(ea)
			else:
				break
		_drop_sides(em, F, f)
		if nF == 3:
			var c3: int = F[(i + 2) % 3]
			faces[f] = [ea, p, c3]
			faces.append([p, eb, c3])
			fmat.append(fmat[f])
			st["fsrc"].append(st["fsrc"][f])
			_add_sides(em, faces[f], f)
			_add_sides(em, faces[faces.size() - 1], faces.size() - 1)
			break
		var c: int = F[(i + 2) % 4]
		var d: int = F[(i + 3) % 4]
		# (the side across: d (across from a) to c (across from b) - the point on it at s)
		var q: int = _between(st, d, c, s)
		faces[f] = [ea, p, q, d]
		faces.append([p, eb, c, q])
		fmat.append(fmat[f])
		st["fsrc"].append(st["fsrc"][f])
		_add_sides(em, faces[f], f)
		_add_sides(em, faces[faces.size() - 1], faces.size() - 1)
		var nxt: Array = (em.get(_sk(d, c), []) as Array).filter(func(x): return int(x) != f and int(x) != faces.size() - 1)
		if nxt.is_empty():
			break
		f = nxt[0]
		ea = d
		eb = c
		p = q
	return first


## A new point on side d-c at `s` of the way from d: on the surface (bent by the two ends' normals where
## they're near alike - a curved surface's row stays on it), on an edge if both ends are on it.
static func _between(st: Dictionary, d: int, c: int, s: float) -> int:
	var v: Array = st["v"]
	var nrm: Array = st["nrm"]
	var p0: Vector3 = v[d]
	var p1: Vector3 = v[c]
	var n0: Vector3 = nrm[d]
	var n1: Vector3 = nrm[c]
	var w := p1 - p0
	var pos := p0.lerp(p1, s)
	if n0 != Vector3.ZERO and n1 != Vector3.ZERO and n0.dot(n1) > cos(deg_to_rad(40.0)):
		var b1 := p0 + (w - w.dot(n0) * n0) / 3.0
		var b2 := p1 - (w - w.dot(n1) * n1) / 3.0
		var u := 1.0 - s
		pos = p0 * u * u * u + b1 * 3.0 * u * u * s + b2 * 3.0 * u * s * s + p1 * s * s * s
	var q := v.size()
	v.append(pos)
	st["vfaces"][q] = true
	nrm.append(n0.lerp(n1, s).normalized() if n0.lerp(n1, s).length_squared() > 1e-30 else n0)
	# (on an edge both its ends are on, next to each other along it: there too)
	var on: Dictionary = st["on"]
	if on.has(d) and on.has(c):
		for k in on[d]:
			if not (on[c] as Dictionary).has(k):
				continue
			var td: float = on[d][k]
			var tc: float = on[c][k]
			var tq := lerpf(td, tc, s)
			if absf(tc - td) > 0.5:
				# (across a closed edge's start: round it the short way)
				tc += 1.0 if tc < td else -1.0
				tq = fposmod(lerpf(td, tc, s), 1.0)
			(st["fv"] as Array).append([q, int(k), tq])
			if not on.has(q):
				on[q] = {}
			on[q][k] = tq
	return q


## Each material's places inside it: [[a point, material]...] - one a stretch of each material (the
## triangle nearest the middle of it). Found again after edits: the stretch holding the triangle nearest a
## point is that point's material.
static func anchors(v: PackedVector3Array, t: PackedInt32Array, tmat: PackedInt32Array) -> Array:
	var comp := _stretches(v, t, func(ta: int, tb: int) -> bool: return tmat[ta] == tmat[tb])
	var sums := {}
	for ti in comp.size():
		var c := comp[ti]
		var ctr := (v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0
		if not sums.has(c):
			sums[c] = [Vector3.ZERO, 0]
		sums[c][0] += ctr
		sums[c][1] += 1
	var out := []
	for c in sums:
		var mid: Vector3 = sums[c][0] / float(sums[c][1])
		var best := -1
		var bd := INF
		for ti in comp.size():
			if comp[ti] != c:
				continue
			var ctr := (v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0
			if ctr.distance_squared_to(mid) < bd:
				bd = ctr.distance_squared_to(mid)
				best = ti
		var ctr2 := (v[t[best * 3]] + v[t[best * 3 + 1]] + v[t[best * 3 + 2]]) / 3.0
		out.append([[ctr2.x, ctr2.y, ctr2.z], tmat[best]])
	return out


## Triangles in stretches: joined across a side when `same(ta, tb)` says so. Each triangle's stretch.
static func _stretches(_v: PackedVector3Array, t: PackedInt32Array, same: Callable) -> PackedInt32Array:
	var nt := t.size() / 3
	var by_e := {}
	for ti in nt:
		for j in 3:
			var k := _sk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])
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
		comp[t0] = nc
		var todo := [t0]
		while not todo.is_empty():
			var ti: int = todo.pop_back()
			for j in 3:
				for o in by_e[_sk(t[ti * 3 + j], t[ti * 3 + (j + 1) % 3])]:
					if comp[o] < 0 and same.call(ti, o):
						comp[o] = nc
						todo.append(o)
		nc += 1
	return comp


## Each triangle's material in a joined solid as it is now: its stretches (split at the edges between two
## materials - `seams`, by chain index), each the material of the anchor nearest it.
static func tri_materials(v: PackedVector3Array, t: PackedInt32Array, fv: Array, seam_chains: Dictionary, anchor_list: Array) -> PackedInt32Array:
	# (the sides along a seam: two points next to each other on it)
	var blocked := {}
	var by_c := {}
	for e in fv:
		if seam_chains.has(int(e[1])):
			if not by_c.has(int(e[1])):
				by_c[int(e[1])] = []
			by_c[int(e[1])].append([float(e[2]), int(e[0])])
	for k in by_c:
		var l: Array = by_c[k]
		l.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for i in range(1, l.size()):
			blocked[_sk(int(l[i - 1][1]), int(l[i][1]))] = true
		if l.size() > 2:
			blocked[_sk(int(l[0][1]), int(l.back()[1]))] = true   # (a closed one's last side - harmless on an open one: not a side)
	var nt := t.size() / 3
	var shared := func(ta: int, tb: int) -> bool:
		var a := [t[ta * 3], t[ta * 3 + 1], t[ta * 3 + 2]]
		var cnt := 0
		var x := -1
		var y := -1
		for j in 3:
			var q := t[tb * 3 + j]
			if q in a:
				if cnt == 0:
					x = q
				else:
					y = q
				cnt += 1
		return cnt < 2 or not blocked.has(_sk(x, y))
	var comp := _stretches(v, t, shared)
	var out := PackedInt32Array()
	out.resize(nt)
	out.fill(0)
	if anchor_list.is_empty():
		return out
	var cm := {}
	var ctrs := PackedVector3Array()
	ctrs.resize(nt)
	for ti in nt:
		ctrs[ti] = (v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0
	for an in anchor_list:
		var ap := Vector3(an[0][0], an[0][1], an[0][2])
		var best := -1
		var bd := INF
		for ti in nt:
			var d := ctrs[ti].distance_squared_to(ap)
			if d < bd:
				bd = d
				best = ti
		if best >= 0 and not cm.has(comp[best]):
			cm[comp[best]] = int(an[1])
	# (a stretch no anchor fell in: the material of the anchor nearest its middle)
	var mids := {}
	for ti in nt:
		if not mids.has(comp[ti]):
			mids[comp[ti]] = [Vector3.ZERO, 0]
		mids[comp[ti]][0] += ctrs[ti]
		mids[comp[ti]][1] += 1
	for c in mids:
		if cm.has(c):
			continue
		var mid: Vector3 = mids[c][0] / float(mids[c][1])
		var bd := INF
		for an in anchor_list:
			var d := Vector3(an[0][0], an[0][1], an[0][2]).distance_squared_to(mid)
			if d < bd:
				bd = d
				cm[c] = int(an[1])
	for ti in nt:
		out[ti] = int(cm.get(comp[ti], 0))
	return out


## A one-surface mesh split into a surface a material (`labels`: each triangle's; `mats`: the materials) -
## every surface there, in order (an empty one a single point-sized triangle), each point's normal and
## everything else as it was (no seam in the shading where two materials meet).
static func split_by(m: ArrayMesh, labels: PackedInt32Array, mats: Array) -> ArrayMesh:
	var a := m.surface_get_arrays(0)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
	var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var fmt := m.surface_get_format(0)
	var flags := 0
	for ch in 4:
		flags |= fmt & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + ch * Mesh.ARRAY_FORMAT_CUSTOM_BITS))
	var out := ArrayMesh.new()
	for L in mats.size():
		var remap := PackedInt32Array()
		remap.resize(nv)
		remap.fill(-1)
		var order := PackedInt32Array()
		var ix := PackedInt32Array()
		for ti in idx.size() / 3:
			if (labels[ti] if ti < labels.size() else 0) != L:
				continue
			for j in 3:
				var vi := idx[ti * 3 + j]
				if remap[vi] < 0:
					remap[vi] = order.size()
					order.append(vi)
				ix.append(remap[vi])
		if ix.is_empty():
			order = PackedInt32Array([0])
			ix = PackedInt32Array([0, 0, 0])
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		for slot in Mesh.ARRAY_MAX:
			var src = a[slot]
			if src == null or slot == Mesh.ARRAY_INDEX:
				continue
			var sz: int = src.size()
			if sz == 0 or sz % nv != 0:
				continue
			var per := sz / nv
			var dst = src.duplicate()
			dst.resize(order.size() * per)
			for o in order.size():
				for c in per:
					dst[o * per + c] = src[order[o] * per + c]
			na[slot] = dst
		na[Mesh.ARRAY_INDEX] = ix
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na, [], {}, flags)
		out.surface_set_material(L, mats[L])
	return out
