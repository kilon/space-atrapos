extends RefCounted
## How well a solid's mesh follows the topology rules (data/docs/editor.md, "mesh-curves-topology"): quads in
## grids, few poles, square and even quads, smooth shading inside the faces. Measures only - changes nothing.
## Static; safe on a worker (no scene tree).
##
## score(v, t, fv, chains) -> {
##   faces, quads, tris, quad_ratio          - the triangles paired into faces as edge_net._pair_faces does
##   interior, poles, pole_ratio, valence     - interior points (not on an edge of the solid, not on an open
##                                              side): how many faces meet at each; a pole: other than 4;
##                                              valence = {faces meeting: points}
##   angle_dev                                - quads' mean |corner angle - 90| (degrees)
##   aspect                                   - quads' mean longest side / shortest side
##   slivers, sliver_ratio                    - quads with aspect > 3 or a corner under 30 degrees
##   area_cv                                  - faces' areas: standard deviation / mean
##   inner_sides, shade_bad, shade_ratio,     - sides inside the faces (not a stretch of one of the solid's
##   shade_bad_deg                              edges): those whose two triangles' normals differ by over 20
##                                              degrees (shading artefacts) and their mean angle
##   misoriented                              - inner sides whose triangles face opposite ways
##   sides, open_sides, nonmanifold           - mesh sides; with one triangle; with three or more
##   score                                    - 0..100, below
## }
##
## The score's weights (each term 0..1 times its points; 100 = a perfect regular grid):
##   30  good quads: quad_ratio * (1 - sliver_ratio) (a sliver isn't a quad worth having)
##   20  poles: 1 - pole_ratio / 0.2 (a fifth of the interior points poles or more: 0)
##   15  square corners: 1 - angle_dev / 45
##   10  no slivers: 1 - sliver_ratio
##   10  even sizes: 1 - area_cv (a CV of 1 or more: 0)
##   10  smooth shading: 1 - shade_ratio / 0.1 (a tenth of the inner sides creased or more: 0)
##    5  manifold: 1 - 20 * nonmanifold / sides
## Open sides aren't penalised (a solid may be open on purpose).

const SHADE_DEG := 20.0
const SLIVER_ASPECT := 3.0
const SLIVER_DEG := 30.0
const W_QUADS := 30.0
const W_POLES := 20.0
const W_ANGLE := 15.0
const W_SLIVER := 10.0
const W_EVEN := 10.0
const W_SHADE := 10.0
const W_MANIFOLD := 5.0

static var _net: GDScript


static func score(v: PackedVector3Array, t: PackedInt32Array, fv: Array, chains: Array) -> Dictionary:
	if _net == null:
		_net = load("res://scripts/editor/mesh/edge_net.gd")
	var nv := v.size()
	var nt := t.size() / 3
	var out := {}
	# --- sides: Vector2i(lo, hi) -> index; per side its triangle count, first two triangles, direction in the first
	var side_of := {}
	var s_n := PackedInt32Array()
	var s_t0 := PackedInt32Array()
	var s_t1 := PackedInt32Array()
	var s_same := PackedByteArray()   # (1: the second triangle runs the side the same way as the first)
	var s_dir0 := PackedByteArray()
	var tn := PackedVector3Array()
	tn.resize(nt)
	for ti in nt:
		var a := v[t[ti * 3]]
		var n := (v[t[ti * 3 + 1]] - a).cross(v[t[ti * 3 + 2]] - a)
		tn[ti] = n.normalized() if n.length_squared() > 1e-30 else Vector3.ZERO
		for j in 3:
			var p := t[ti * 3 + j]
			var q := t[ti * 3 + (j + 1) % 3]
			var k := Vector2i(mini(p, q), maxi(p, q))
			var fwd := 1 if p < q else 0
			var si: int = side_of.get(k, -1)
			if si < 0:
				si = s_n.size()
				side_of[k] = si
				s_n.append(1)
				s_t0.append(ti)
				s_t1.append(-1)
				s_same.append(0)
				s_dir0.append(fwd)
			else:
				s_n[si] += 1
				if s_n[si] == 2:
					s_t1[si] = ti
					s_same[si] = 1 if s_dir0[si] == fwd else 0
	var sides := s_n.size()
	var keys: Array = side_of.keys()
	var open_sides := 0
	var nonmanifold := 0
	var boundary := PackedByteArray()
	boundary.resize(nv)
	for k: Vector2i in keys:
		var c := s_n[side_of[k]]
		if c == 1:
			open_sides += 1
			boundary[k.x] = 1
			boundary[k.y] = 1
		elif c > 2:
			nonmanifold += 1
	# --- the points on the solid's edges: vertex -> {chain: rank along it}
	var on_edge := PackedByteArray()
	on_edge.resize(nv)
	var by_chain := {}   # chain -> [[place, vertex]...]
	for e in fv:
		var vi := int(e[0])
		if vi < 0 or vi >= nv:
			continue
		on_edge[vi] = 1
		var ci := int(e[1])
		if not by_chain.has(ci):
			by_chain[ci] = []
		(by_chain[ci] as Array).append([float(e[2]), vi])
	var rank := {}   # Vector2i(vertex, chain) -> rank
	var vch := {}   # vertex -> [chains it's on]
	var chain_n := {}
	for ci in by_chain:
		var l: Array = by_chain[ci]
		l.sort_custom(func(x, y): return x[0] < y[0])
		chain_n[ci] = l.size()
		for r in l.size():
			var vi := int(l[r][1])
			rank[Vector2i(vi, ci)] = r
			if not vch.has(vi):
				vch[vi] = []
			(vch[vi] as Array).append(ci)
	var closed := {}
	for ci in chains.size():
		var c = chains[ci]
		closed[ci] = c is Dictionary and bool(c.get("closed", false))
	# --- shading across the sides inside the faces
	var inner := 0
	var bad := 0
	var bad_sum := 0.0
	var misoriented := 0
	var cos_lim := cos(deg_to_rad(SHADE_DEG))
	for k: Vector2i in keys:
		var si: int = side_of[k]
		if s_n[si] != 2:
			continue
		if on_edge[k.x] == 1 and on_edge[k.y] == 1 and _along_chain(k.x, k.y, vch, rank, chain_n, closed):
			continue
		inner += 1
		var n0 := tn[s_t0[si]]
		var n1 := tn[s_t1[si]]
		if s_same[si] == 1:
			misoriented += 1
			n1 = -n1
		var d := n0.dot(n1)
		if d < cos_lim:
			bad += 1
			bad_sum += rad_to_deg(acos(clampf(d, -1.0, 1.0)))
	# --- faces
	var faces: Array = _net._pair_faces(v, t, fv)
	var quads := 0
	var tris := 0
	var val := PackedInt32Array()
	val.resize(nv)
	var used := PackedByteArray()
	used.resize(nv)
	var dev_sum := 0.0
	var asp_sum := 0.0
	var slivers := 0
	var areas := PackedFloat64Array()
	for f: Array in faces:
		var m := f.size()
		for c in f:
			val[c] += 1
		if m == 3:
			tris += 1
			areas.append(0.5 * (v[f[1]] - v[f[0]]).cross(v[f[2]] - v[f[0]]).length())
			continue
		quads += 1
		var p0 := v[f[0]]
		var p1 := v[f[1]]
		var p2 := v[f[2]]
		var p3 := v[f[3]]
		areas.append(0.5 * ((p1 - p0).cross(p2 - p0).length() + (p2 - p0).cross(p3 - p0).length()))
		var pts := [p0, p1, p2, p3]
		var lo := INF
		var hi := 0.0
		var min_ang := 180.0
		for j in 4:
			var a: Vector3 = pts[j]
			var b: Vector3 = pts[(j + 1) % 4]
			var z: Vector3 = pts[(j + 3) % 4]
			var l := a.distance_to(b)
			lo = minf(lo, l)
			hi = maxf(hi, l)
			var ang := rad_to_deg((b - a).angle_to(z - a))
			dev_sum += absf(ang - 90.0)
			min_ang = minf(min_ang, ang)
		var asp := hi / lo if lo > 1e-12 else 1000.0
		asp_sum += asp
		if asp > SLIVER_ASPECT or min_ang < SLIVER_DEG:
			slivers += 1
	# --- poles
	var interior := 0
	var poles := 0
	var hist := {}
	for i in nv:
		if val[i] == 0 or on_edge[i] == 1 or boundary[i] == 1:
			continue
		interior += 1
		hist[val[i]] = int(hist.get(val[i], 0)) + 1
		if val[i] != 4:
			poles += 1
	# --- evenness
	var cv := 0.0
	if areas.size() > 1:
		var mean := 0.0
		for a in areas:
			mean += a
		mean /= areas.size()
		var var_sum := 0.0
		for a in areas:
			var_sum += (a - mean) * (a - mean)
		cv = sqrt(var_sum / areas.size()) / mean if mean > 1e-30 else 0.0
	var nf := faces.size()
	var quad_ratio := float(quads) / nf if nf > 0 else 0.0
	var pole_ratio := float(poles) / interior if interior > 0 else 0.0
	var angle_dev := dev_sum / (4.0 * quads) if quads > 0 else 90.0
	var sliver_ratio := float(slivers) / quads if quads > 0 else 1.0
	var shade_ratio := float(bad) / inner if inner > 0 else 0.0
	var s := W_QUADS * quad_ratio * (1.0 - sliver_ratio if quads > 0 else 0.0)
	s += W_POLES * (1.0 - clampf(pole_ratio / 0.2, 0.0, 1.0))
	s += W_ANGLE * (1.0 - clampf(angle_dev / 45.0, 0.0, 1.0))
	s += W_SLIVER * (1.0 - sliver_ratio)
	s += W_EVEN * (1.0 - clampf(cv, 0.0, 1.0))
	s += W_SHADE * (1.0 - clampf(shade_ratio / 0.1, 0.0, 1.0))
	s += W_MANIFOLD * (1.0 - clampf(20.0 * nonmanifold / maxf(1.0, sides), 0.0, 1.0))
	if nf == 0:
		s = 0.0
	out["vertices"] = nv
	out["triangles"] = nt
	out["faces"] = nf
	out["quads"] = quads
	out["tris"] = tris
	out["quad_ratio"] = quad_ratio
	out["interior"] = interior
	out["poles"] = poles
	out["pole_ratio"] = pole_ratio
	out["valence"] = hist
	out["angle_dev"] = angle_dev
	out["aspect"] = asp_sum / quads if quads > 0 else 0.0
	out["slivers"] = slivers
	out["sliver_ratio"] = sliver_ratio
	out["area_cv"] = cv
	out["inner_sides"] = inner
	out["shade_bad"] = bad
	out["shade_ratio"] = shade_ratio
	out["shade_bad_deg"] = bad_sum / bad if bad > 0 else 0.0
	out["misoriented"] = misoriented
	out["sides"] = sides
	out["open_sides"] = open_sides
	out["nonmanifold"] = nonmanifold
	out["score"] = s
	return out


## Is the side a..b a stretch of one of the solid's edges: both on the same chain, next to each other along it?
static func _along_chain(a: int, b: int, vch: Dictionary, rank: Dictionary, chain_n: Dictionary, closed: Dictionary) -> bool:
	for ci in vch.get(a, []):
		var ka := Vector2i(a, ci)
		var kb := Vector2i(b, ci)
		if not rank.has(ka) or not rank.has(kb):
			continue
		var d := absi(int(rank[ka]) - int(rank[kb]))
		if d == 1 or (closed.get(ci, false) and d == int(chain_n[ci]) - 1):
			return true
	return false
