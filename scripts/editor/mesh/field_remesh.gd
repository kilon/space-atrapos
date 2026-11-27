extends RefCounted
## Field-aligned quads for one face of a solid (the ECurves topology rules, data/docs/editor.md
## "mesh-curves-topology") - for the big organic faces the patch templates of edge_net.gd can't lay out (one
## curved face with holes and few corners). In the spirit of Instant Field-Aligned Meshes (Jakob, Tarini,
## Panozzo, Sorkine-Hornung 2015):
##   1. a helper mesh: the face's triangles (flaps folded back on themselves left out), its rim's samples put
##      into its rim and the rim's other points taken out (their triangles laid out again between the samples
##      either side, or the point pushed inside), then remeshed evenly (sides ~0.55 L; the rim's triangles as
##      big as its samples' spacing) - its rim exactly the samples, its points on the face (found along the
##      surface's normal, not by nearest point: that piles points on a bent surface's corners). Changes are
##      taken when they make nothing worse, so a messy face's folds and slivers don't block the work; what
##      folds is untangled after.
##   2. an orientation field (4-RoSy: a direction per point, mod 90 degrees) smoothed over it, held along the
##      rim's tangent (not at its corners), Gauss-Seidel on a hierarchy of coarser graphs (neighbours matched
##      in pairs) - coarse first, each level starting from the one above;
##   3. a position field (each point's nearest corner of a lattice of spacing L in its tangent plane) smoothed
##      the same way, the rim's samples fixed lattice points;
##   4. extraction: neighbours whose lattice points coincide collapsed into one (valid collapses only - the
##      mesh stays a manifold with the same rim), moved to their lattice point; points too close merged,
##      triangles flipped to the better diagonal; the triangles paired into quads (greedy by quality, then
##      augmenting paths); pole pairs undone (a quad whose two opposite corners merging leaves fewer poles);
##      a squaring relaxation on the surface (each point toward where its quads are parallelograms).
## Static, pure computation - safe on a worker (no scene tree; `why`, `stats` and the tuning switches are
## shared statics, as in edge_net.gd).
##
## fill_face(v, t, tris, loops, L) -> {"pts": PackedVector3Array, "faces": Array} or {} (why: `why`)
##   v, t: the solid's mesh; tris: the face's triangles (indices into t / 3), consistently wound - a disc or a
##   disc with holes; loops: the face's rim(s) resampled (outer first, then holes), each a PackedVector3Array
##   in order (either way round), three samples or more; L: the quads' size.
##   faces: corner lists (3 or 4), wound as the input triangles; an entry >= 0 indexes pts, < 0 is the rim
##   sample -1 - k (k counting the loops' samples in order). Checked (validate) before it's returned.

static var H_RATIO := 0.85   # (tuning: the helper mesh's sides, times L)
static var MERGE := 0.5   # (tuning: two points whose lattice points are nearer than this times L: the same point)
static var PAIR_MIN := 0.2   # (tuning: a quad worse than this - quality 0..1 - isn't made)
static var ORI_SWEEPS := 6   # (tuning: smoothing sweeps on each coarse level, and on the finest)
static var ORI_SWEEPS0 := 3
static var POS_SWEEPS := 6
static var POS_SWEEPS0 := 4

static var why := ""   # (why fill_face gave {})
static var stats := {}   # (the last fill_face's timings, ms a stage, and its helper mesh's size)
static var trace := false   # (tuning: print each stage as it ends, and its thin triangles)


## own_rim: the face's rim is its own triangles' rim, its samples given by `rim` - {"keep": {old point: sample id}
## (rim points kept as samples - the others taken out), "split": {Vector2i(old a, old b): [[u, sample id, point]...]}
## (samples put into that rim side, either way round)}; in the result, -1 - a sample's id.
static func fill_face(v: PackedVector3Array, t: PackedInt32Array, tris: Array, loops: Array, L: float, own_rim := false, rim := {}) -> Dictionary:
	why = ""
	stats = {}
	var t0 := Time.get_ticks_usec()
	if L <= 0.0 or tris.is_empty() or (loops.is_empty() and not own_rim):
		why = "nothing to fill"
		return {}
	var surf := Surf.new()
	var m := HM.new()
	if not m.from_face(v, t, tris, surf, L):
		why = m.err
		return {}
	if own_rim:
		if not _put_own_samples(m, rim):
			return {}
	elif not _put_samples(m, loops, L):
		return {}
	var tk := [Time.get_ticks_usec()]
	var lap := func(name: String) -> void:
		var now := Time.get_ticks_usec()
		stats[name + "_ms"] = (now - int(tk[0])) / 1000.0
		tk[0] = now
		if trace:
			print("  field_remesh: ", name, " ", stats[name + "_ms"], " ms")
			_audit(m, name)
	lap.call("samples")
	if not _drop_rim_extras(m, L * H_RATIO):
		return {}
	lap.call("rim")
	_refine(m, L * H_RATIO)
	lap.call("refine")
	_remesh(m, L * H_RATIO, 2)
	_untangle(m)
	lap.call("remesh")
	var g := _graph(m)
	var levels := _hierarchy(g)
	lap.call("graph")
	_orient_field(levels)
	lap.call("orient")
	_position_field(levels, L)
	lap.call("position")
	_extract(m, g, levels[0], L)
	lap.call("extract")
	_tidy(m, L)
	_untangle(m)
	lap.call("tidy")
	var faces := _pair(m)
	lap.call("pair")
	faces = _fewer_poles(m, faces)
	_relax(m, faces, 8)
	lap.call("relax")
	var out := _output(m, faces)
	stats["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	stats["helper_points"] = g["n"]
	if out.is_empty():
		return {}
	var bad := "" if own_rim else validate(v, t, tris, loops, out)
	if bad != "":
		why = "a bad result: " + bad
		return {}
	return out


# ---------------------------------------------------------------- the face's surface (projection)

class Surf:
	var P := PackedVector3Array()
	var N := PackedVector3Array()   # (smooth normals at the points)
	var T := PackedInt32Array()
	var TN := PackedInt32Array()   # (each triangle's three neighbours across its sides, -1: none)
	var VT := []   # (each point's triangles)

	func build(p: PackedVector3Array, tt: PackedInt32Array, scale: float) -> void:
		P = p
		T = tt
		var nv := P.size()
		var nt := T.size() / 3
		N.resize(nv)
		N.fill(Vector3.ZERO)
		VT.resize(nv)
		for i in nv:
			VT[i] = PackedInt32Array()
		var side := {}
		TN.resize(nt * 3)
		TN.fill(-1)
		for ti in nt:
			var a := T[ti * 3]
			var b := T[ti * 3 + 1]
			var c := T[ti * 3 + 2]
			var n := (P[b] - P[a]).cross(P[c] - P[a])
			for x in [a, b, c]:
				N[x] += n
				VT[x].append(ti)
			for j in 3:
				var p0 := T[ti * 3 + j]
				var p1 := T[ti * 3 + (j + 1) % 3]
				var k := Vector2i(mini(p0, p1), maxi(p0, p1))
				if side.has(k):
					var o: int = side[k]
					TN[ti * 3 + j] = o / 3
					TN[o] = ti
				else:
					side[k] = ti * 3 + j
		for i in nv:
			N[i] = N[i].normalized() if N[i].length_squared() > 1e-40 else Vector3.UP
		# (smoothed over a few rings: a messy face's folds and slivers don't turn its normals round)
		var nb := []
		nb.resize(nv)
		for i in nv:
			nb[i] = PackedInt32Array()
		for ti in nt:
			for j in 3:
				var a := T[ti * 3 + j]
				var b := T[ti * 3 + (j + 1) % 3]
				if not (nb[a] as PackedInt32Array).has(b):
					nb[a].append(b)
					nb[b].append(a)
		# (only within about `scale` of each point: a coarse face's real bends kept)
		for it in 4:
			var M := N.duplicate()
			for i in nv:
				var acc := N[i] * 2.0
				for x in nb[i]:
					var w := 1.0 - P[i].distance_to(P[x]) / scale
					if w > 0.0:
						acc += N[x] * w
				M[i] = acc.normalized() if acc.length_squared() > 1e-40 else N[i]
			N = M

	## Where the line through p along n (the surface's normal there; zero: the hint triangle's) meets the
	## surface, walking from triangle `hint`: [point, normal, triangle]. (Not the nearest point: that maps
	## whole regions onto a corner of a bent surface - points piled on one place.) Off the face's rim, or a
	## walk that doesn't settle: the nearest point.
	func project(p: Vector3, hint: int, n := Vector3.ZERO) -> Array:
		var cur := hint
		if n == Vector3.ZERO:
			n = (P[T[cur * 3 + 1]] - P[T[cur * 3]]).cross(P[T[cur * 3 + 2]] - P[T[cur * 3]]).normalized()
		var last := -1
		for step in 200:
			var a := P[T[cur * 3]]
			var b := P[T[cur * 3 + 1]]
			var c := P[T[cur * 3 + 2]]
			var nt := (b - a).cross(c - a)
			var den := n.dot(nt)
			if absf(den) < 1e-12 * nt.length():
				break
			var q := p + n * ((a - p).dot(nt) / den)
			# (q's weights in the triangle's plane)
			var w0 := (c - b).cross(q - b).dot(nt)
			var w1 := (a - c).cross(q - c).dot(nt)
			var w2 := (b - a).cross(q - a).dot(nt)
			var s := nt.length_squared()
			w0 /= s
			w1 /= s
			w2 /= s
			var tol := -1e-7
			if w0 >= tol and w1 >= tol and w2 >= tol:
				var w := Vector3(maxf(w0, 0.0), maxf(w1, 0.0), maxf(w2, 0.0))
				w /= (w.x + w.y + w.z)
				var nn := N[T[cur * 3]] * w.x + N[T[cur * 3 + 1]] * w.y + N[T[cur * 3 + 2]] * w.z
				return [_at(cur, w), nn.normalized() if nn.length_squared() > 1e-40 else nt.normalized(), cur]
			# (across the side opposite the most negative weight)
			var j := 0
			if w1 < w0 and w1 <= w2:
				j = 1
			elif w2 < w0 and w2 < w1:
				j = 2
			var nb := TN[cur * 3 + (j + 1) % 3]
			if nb < 0 or nb == last:
				break
			last = cur
			cur = nb
		return nearest(p, cur)

	## The nearest point of the surface to p, starting the search at triangle `hint`: [point, normal, triangle].
	func nearest(p: Vector3, hint: int) -> Array:
		var cur := hint
		var bw := FieldRemeshMath.cpt(p, P[T[cur * 3]], P[T[cur * 3 + 1]], P[T[cur * 3 + 2]])
		var bd := p.distance_squared_to(_at(cur, bw))
		for step in 64:
			var moved := false
			for j in 3:
				var o := TN[cur * 3 + j]
				if o < 0:
					continue
				var w := FieldRemeshMath.cpt(p, P[T[o * 3]], P[T[o * 3 + 1]], P[T[o * 3 + 2]])
				var d := p.distance_squared_to(_at(o, w))
				if d < bd - 1e-30:
					bd = d
					bw = w
					cur = o
					moved = true
			if not moved:
				break
		# (round its corners too: a nearest point at a corner may lie in a triangle not across a side)
		var best := cur
		for j in 3:
			for o in VT[T[cur * 3 + j]]:
				if o == cur:
					continue
				var w := FieldRemeshMath.cpt(p, P[T[o * 3]], P[T[o * 3 + 1]], P[T[o * 3 + 2]])
				var d := p.distance_squared_to(_at(o, w))
				if d < bd - 1e-30:
					bd = d
					bw = w
					best = o
		cur = best
		var n := N[T[cur * 3]] * bw.x + N[T[cur * 3 + 1]] * bw.y + N[T[cur * 3 + 2]] * bw.z
		return [_at(cur, bw), n.normalized() if n.length_squared() > 1e-40 else N[T[cur * 3]], cur]

	func _at(ti: int, w: Vector3) -> Vector3:
		return P[T[ti * 3]] * w.x + P[T[ti * 3 + 1]] * w.y + P[T[ti * 3 + 2]] * w.z


# ---------------------------------------------------------------- the helper mesh

class HM:
	var P := PackedVector3Array()
	var N := PackedVector3Array()   # (the surface's normal at each point)
	var home := PackedInt32Array()   # (the surface triangle each point lies on - projection's start)
	var T := PackedInt32Array()   # (3 a triangle; a dead one: -1s)
	var VT := []   # (each point's triangles: PackedInt32Array)
	var smp := PackedInt32Array()   # (each point: its rim sample, -1: none)
	var orig := PackedInt32Array()   # (each of the face's first points: its vertex in the v given)
	var rim := PackedByteArray()   # (1: on the rim)
	var rnext := {}   # (the rim's order: point -> next point, the way the triangles run round)
	var rprev := {}
	var surf: Surf
	var err := ""

	func from_face(v: PackedVector3Array, t: PackedInt32Array, tris: Array, s: Surf, scale: float) -> bool:
		surf = s
		var loc := {}
		var lp := PackedVector3Array()
		var lt := PackedInt32Array()
		# (no degenerate triangles; a triangle there more than once - a flap folded back on itself - its copies
		# wound opposite ways cancelling out: one kept if one's left over)
		var net := {}
		for ti in tris:
			var k := _tri_key(t, int(ti))
			net[k] = int(net.get(k, 0)) + _tri_sign(t, int(ti))
		var kept := {}
		for ti in tris:
			var a := t[int(ti) * 3]
			var b := t[int(ti) * 3 + 1]
			var c := t[int(ti) * 3 + 2]
			if a == b or b == c or a == c:
				continue
			var k := _tri_key(t, int(ti))
			if kept.has(k) or int(net[k]) == 0 or signi(int(net[k])) != _tri_sign(t, int(ti)):
				continue
			kept[k] = true
			for j in 3:
				var x := t[int(ti) * 3 + j]
				if not loc.has(x):
					loc[x] = lp.size()
					lp.append(v[x])
				lt.append(loc[x])
		orig.resize(lp.size())
		for x in loc:
			orig[loc[x]] = x
		var up := _unpinch(lp, lt, orig)   # (packed arrays come back, not changed in place)
		lp = up[0]
		lt = up[1]
		orig = up[2]
		surf.build(lp, lt, scale)
		var nt := lt.size() / 3
		for i in lp.size():
			add_v(lp[i], surf.N[i], (surf.VT[i] as PackedInt32Array)[0])
		var dir := {}
		for ti in nt:
			var a := lt[ti * 3]
			var b := lt[ti * 3 + 1]
			var c := lt[ti * 3 + 2]
			if a == b or b == c or a == c:
				err = "a degenerate triangle"
				return false
			add_t(a, b, c)
			for j in 3:
				var k := Vector2i(lt[ti * 3 + j], lt[ti * 3 + (j + 1) % 3])
				if dir.has(k):
					err = "triangles not wound consistently (or a side shared by three)"
					return false
				dir[k] = true
		for k: Vector2i in dir:
			if not dir.has(Vector2i(k.y, k.x)):
				if rnext.has(k.x):
					err = "a rim touching itself"
					return false
				rnext[k.x] = k.y
				rprev[k.y] = k.x
				rim[k.x] = 1
				rim[k.y] = 1
		if rnext.is_empty():
			err = "a closed face (no rim)"
			return false
		return true

	## A vertex the rim passes twice (two fans of triangles meeting only at it): a copy of it a fan, so each rim
	## loop goes round once (lp, lt changed in place).
	func _unpinch(lp: PackedVector3Array, lt: PackedInt32Array, og: PackedInt32Array) -> Array:
		var cnt := {}
		for ti in lt.size() / 3:
			for j in 3:
				var a := lt[ti * 3 + j]
				var b := lt[ti * 3 + (j + 1) % 3]
				var k := Vector2i(mini(a, b), maxi(a, b))
				cnt[k] = int(cnt.get(k, 0)) + 1
		var outs := {}
		var at := {}   # vertex -> its triangles
		for ti in lt.size() / 3:
			for j in 3:
				var a := lt[ti * 3 + j]
				var b := lt[ti * 3 + (j + 1) % 3]
				if not at.has(a):
					at[a] = []
				at[a].append(ti)
				if int(cnt[Vector2i(mini(a, b), maxi(a, b))]) == 1:
					outs[a] = int(outs.get(a, 0)) + 1
		for x in outs:
			if int(outs[x]) < 2:
				continue
			var tl: Array = at[x]
			var grp := {}
			for ti in tl:
				grp[ti] = ti
			var root := func(q):
				while grp[q] != q:
					q = grp[q]
				return q
			# (triangles round x joined across their inner sides at x)
			var by_side := {}
			for ti in tl:
				for j in 3:
					var y := lt[ti * 3 + j]
					if y == x:
						continue
					var k := Vector2i(mini(x, y), maxi(x, y))
					if int(cnt[k]) != 2:
						continue
					if by_side.has(y):
						var ra = root.call(by_side[y])
						var rb = root.call(ti)
						if ra != rb:
							grp[ra] = rb
					else:
						by_side[y] = ti
			var first = null
			var copy_of := {}
			for ti in tl:
				var r = root.call(ti)
				if first == null:
					first = r
				if r == first:
					continue
				if not copy_of.has(r):
					copy_of[r] = lp.size()
					lp.append(lp[x])
					og.append(og[x])
				for j in 3:
					if lt[ti * 3 + j] == x:
						lt[ti * 3 + j] = copy_of[r]
		return [lp, lt, og]

	static func _tri_key(t: PackedInt32Array, ti: int) -> Vector3i:
		var a := t[ti * 3]
		var b := t[ti * 3 + 1]
		var c := t[ti * 3 + 2]
		var lo := mini(a, mini(b, c))
		var hi := maxi(a, maxi(b, c))
		return Vector3i(lo, a + b + c - lo - hi, hi)

	## +1 if the triangle runs round its corners in rising order (turned), -1 the other way.
	static func _tri_sign(t: PackedInt32Array, ti: int) -> int:
		var a := t[ti * 3]
		var b := t[ti * 3 + 1]
		var c := t[ti * 3 + 2]
		return 1 if (a < b and b < c) or (b < c and c < a) or (c < a and a < b) else -1

	func add_v(p: Vector3, n: Vector3, h: int) -> int:
		P.append(p)
		N.append(n)
		home.append(h)
		VT.append(PackedInt32Array())
		smp.append(-1)
		rim.append(0)
		return P.size() - 1

	func add_t(a: int, b: int, c: int) -> int:
		var ti := T.size() / 3
		T.append(a)
		T.append(b)
		T.append(c)
		VT[a].append(ti)
		VT[b].append(ti)
		VT[c].append(ti)
		return ti

	func del_t(ti: int) -> void:
		for j in 3:
			var x := T[ti * 3 + j]
			var at: int = VT[x].find(ti)
			if at >= 0:
				VT[x].remove_at(at)
			T[ti * 3 + j] = -1

	func edge_tris(a: int, b: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		for ti in VT[a]:
			if T[ti * 3] == b or T[ti * 3 + 1] == b or T[ti * 3 + 2] == b:
				out.append(ti)
		return out

	func has_edge(a: int, b: int) -> bool:
		for ti in VT[a]:
			if T[ti * 3] == b or T[ti * 3 + 1] == b or T[ti * 3 + 2] == b:
				return true
		return false

	func nbrs(a: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		for ti in VT[a]:
			for j in 3:
				var x := T[ti * 3 + j]
				if x != a and not out.has(x):
					out.append(x)
		return out

	## The triangle `ti` turned to start at `a`: [the next corner, the one after].
	func rot(ti: int, a: int) -> Vector2i:
		for j in 3:
			if T[ti * 3 + j] == a:
				return Vector2i(T[ti * 3 + (j + 1) % 3], T[ti * 3 + (j + 2) % 3])
		return Vector2i(-1, -1)

	## A triangle's quality at points pa, pb, pc: 1 equilateral, toward 0 thin; -1 facing away from the surface.
	func qual_at(a: int, b: int, c: int, pa: Vector3, pb: Vector3, pc: Vector3) -> float:
		var n := (pb - pa).cross(pc - pa)
		var ref := N[a] + N[b] + N[c]
		var nl := n.length()
		if nl < 1e-30 or n.dot(ref) <= 0.2 * nl * ref.length():
			return -1.0
		var s := pa.distance_squared_to(pb) + pb.distance_squared_to(pc) + pc.distance_squared_to(pa)
		return 2.0 * sqrt(3.0) * nl / s if s > 1e-40 else -1.0

	func qual(a: int, b: int, c: int) -> float:
		return qual_at(a, b, c, P[a], P[b], P[c])

	func tri_q(ti: int) -> float:
		return qual(T[ti * 3], T[ti * 3 + 1], T[ti * 3 + 2])

	## Splits side a-b at p (one or two triangles): the new point.
	func split(a: int, b: int, p: Vector3, n: Vector3, h: int) -> int:
		var ts := edge_tris(a, b)
		var mi := add_v(p, n, h)
		for ti in ts:
			var x := T[ti * 3]
			var y := T[ti * 3 + 1]
			var z := T[ti * 3 + 2]
			del_t(ti)
			# (rotate so the side runs first: (s0, s1, o))
			var tri := [x, y, z]
			for r in 3:
				var s0: int = tri[r]
				var s1: int = tri[(r + 1) % 3]
				if (s0 == a and s1 == b) or (s0 == b and s1 == a):
					var o: int = tri[(r + 2) % 3]
					add_t(s0, mi, o)
					add_t(mi, s1, o)
					break
		if rim[a] == 1 and rim[b] == 1 and ts.size() == 1:
			rim[mi] = 1
			if rnext.get(a, -1) == b:
				rnext[a] = mi
				rnext[mi] = b
				rprev[b] = mi
				rprev[mi] = a
			else:
				rnext[b] = mi
				rnext[mi] = a
				rprev[a] = mi
				rprev[mi] = b
		return mi

	## Turns side a-b (two triangles) round to the other diagonal, if that's no worse than `min_gain` better.
	func flip(a: int, b: int, min_gain: float) -> bool:
		var ts := edge_tris(a, b)
		if ts.size() != 2:
			return false
		var t1 := ts[0]
		var t2 := ts[1]
		var r1 := rot(t1, a)
		if r1.x != b:
			var tmp := t1
			t1 = t2
			t2 = tmp
			r1 = rot(t1, a)
			if r1.x != b:
				return false
		var c := r1.y
		var r2 := rot(t2, b)
		if r2.x != a:
			return false
		var d := r2.y
		if min_gain > 0.0:
			# (quick: a pair already well split - its far corners' angles under 180 degrees together - stays)
			var ca := (P[a] - P[c]).normalized()
			var cb := (P[b] - P[c]).normalized()
			var da := (P[a] - P[d]).normalized()
			var db := (P[b] - P[d]).normalized()
			if acos(clampf(ca.dot(cb), -1.0, 1.0)) + acos(clampf(da.dot(db), -1.0, 1.0)) < PI * 0.97:
				return false
		if c == d or has_edge(c, d):
			return false
		var old := minf(qual(a, b, c), qual(b, a, d))
		var q1 := qual(a, d, c)
		var q2 := qual(d, b, c)
		if minf(q1, q2) < old + min_gain:
			return false
		# (not across a fold: the new pair as flat as the old)
		var n1 := (P[d] - P[a]).cross(P[c] - P[a]).normalized()
		var n2 := (P[b] - P[d]).cross(P[c] - P[d]).normalized()
		var o1 := (P[b] - P[a]).cross(P[c] - P[a]).normalized()
		var o2 := (P[a] - P[b]).cross(P[d] - P[b]).normalized()
		if n1.dot(n2) < minf(o1.dot(o2), 0.95) - 0.05:
			return false
		del_t(t1)
		del_t(t2)
		add_t(a, d, c)
		add_t(d, b, c)
		return true

	## Takes point `gone` (inside the face) into `keep` (moved to np): false if it would fold or tear the mesh.
	func collapse(keep: int, gone: int, np: Vector3, nn: Vector3, nh: int, min_q: float) -> bool:
		if rim[gone] == 1 or keep == gone:
			return false
		var shared := edge_tris(keep, gone)
		if shared.size() != 2:
			return false
		var opp := PackedInt32Array()
		for ti in shared:
			for j in 3:
				var x := T[ti * 3 + j]
				if x != keep and x != gone:
					opp.append(x)
		if opp.size() != 2 or opp[0] == opp[1] or has_edge(opp[0], opp[1]) and (VT[opp[0]] as PackedInt32Array).size() <= 3:
			return false
		var nk := nbrs(keep)
		var common := 0
		for x in nbrs(gone):
			if nk.has(x):
				common += 1
		if common != 2:
			return false
		# (a rim point's other points: no new side between two rim points through the inside... fine; but
		# the kept point can't move off the rim)
		if rim[keep] == 1:
			np = P[keep]
			nn = N[keep]
			nh = home[keep]
		# (no worse than before: its triangles all good enough, or fewer bad ones - a messy face's folds and
		# slivers are there from the start, and mustn't stop the work round them)
		var old_min := INF
		var old_bad := 0
		for x in [keep, gone]:
			for ti in VT[x]:
				var q := tri_q(ti)
				old_min = minf(old_min, q)
				if q < min_q:
					old_bad += 1
		var old_p := P[keep]
		var old_n := N[keep]
		P[keep] = np
		N[keep] = nn
		var new_min := INF
		var new_bad := 0
		for x in [gone, keep]:
			if x == keep and np == old_p:
				continue
			for ti in VT[x]:
				if shared.has(ti):
					continue
				var tri := [T[ti * 3], T[ti * 3 + 1], T[ti * 3 + 2]]
				for j in 3:
					if tri[j] == gone:
						tri[j] = keep
				var q := qual(tri[0], tri[1], tri[2])
				new_min = minf(new_min, q)
				if q < min_q:
					new_bad += 1
		if not _no_worse(old_min, old_bad, new_min, new_bad, min_q):
			P[keep] = old_p
			N[keep] = old_n
			return false
		home[keep] = nh
		for ti in shared:
			del_t(ti)
		for ti in (VT[gone] as PackedInt32Array).duplicate():
			var tri := [T[ti * 3], T[ti * 3 + 1], T[ti * 3 + 2]]
			del_t(ti)
			for j in 3:
				if tri[j] == gone:
					tri[j] = keep
			add_t(tri[0], tri[1], tri[2])
		return true

	## Moves point i toward p (projected on the surface), if nothing folds: true if it moved.
	func move(i: int, p: Vector3, min_q: float) -> bool:
		var pr := surf.project(p, home[i], N[i])
		var old_min := INF
		var old_bad := 0
		for ti in VT[i]:
			var q := tri_q(ti)
			old_min = minf(old_min, q)
			if q < min_q:
				old_bad += 1
		var old_p := P[i]
		var old_n := N[i]
		P[i] = pr[0]
		N[i] = pr[1]
		var new_min := INF
		var new_bad := 0
		for ti in VT[i]:
			var q := tri_q(ti)
			new_min = minf(new_min, q)
			if q < min_q:
				new_bad += 1
		if not _no_worse(old_min, old_bad, new_min, new_bad, min_q):
			P[i] = old_p
			N[i] = old_n
			return false
		home[i] = pr[2]
		return true

	## A change's triangles: all good enough, or fewer bad ones than before, or as many and the worst no worse.
	func _no_worse(old_min: float, old_bad: int, new_min: float, new_bad: int, min_q: float) -> bool:
		if new_bad == 0:
			return new_min >= min_q
		if new_bad < old_bad:
			return true
		return new_bad == old_bad and new_min >= old_min


## Barycentric helpers (an inner-class-free namespace for Surf).
class FieldRemeshMath:
	## The nearest point of triangle a, b, c to p, as weights of a, b, c (Ericson).
	static func cpt(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var ab := b - a
		var ac := c - a
		var ap := p - a
		var d1 := ab.dot(ap)
		var d2 := ac.dot(ap)
		if d1 <= 0.0 and d2 <= 0.0:
			return Vector3(1, 0, 0)
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0.0 and d4 <= d3:
			return Vector3(0, 1, 0)
		var vc := d1 * d4 - d3 * d2
		if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
			var w := d1 / (d1 - d3) if d1 - d3 != 0.0 else 0.0
			return Vector3(1.0 - w, w, 0)
		var cp := p - c
		var d5 := ab.dot(cp)
		var d6 := ac.dot(cp)
		if d6 >= 0.0 and d5 <= d6:
			return Vector3(0, 0, 1)
		var vb := d5 * d2 - d1 * d6
		if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
			var w := d2 / (d2 - d6) if d2 - d6 != 0.0 else 0.0
			return Vector3(1.0 - w, 0, w)
		var va := d3 * d6 - d5 * d4
		if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
			var den := (d4 - d3) + (d5 - d6)
			var w := (d4 - d3) / den if den != 0.0 else 0.0
			return Vector3(0, 1.0 - w, w)
		var s := va + vb + vc
		if absf(s) < 1e-40:
			return Vector3(1, 0, 0)
		var vv := vb / s
		var ww := vc / s
		return Vector3(1.0 - vv - ww, vv, ww)


# ---------------------------------------------------------------- 1. the helper mesh

## The rim's samples put into the face's rim (its sides split at them, or a rim point taken as one).
static func _put_samples(m: HM, loops: Array, L: float) -> bool:
	# the face's rim loops (in the triangles' order)
	var left := m.rnext.duplicate()
	var rims := []
	while not left.is_empty():
		var st: int = left.keys()[0]
		var loop := PackedInt32Array([st])
		var cur: int = left[st]
		left.erase(st)
		while cur != st:
			if not left.has(cur):
				why = "a rim that doesn't close"
				return false
			loop.append(cur)
			var nx: int = left[cur]
			left.erase(cur)
			cur = nx
		rims.append(loop)
	if rims.size() != loops.size():
		why = "%d rim loops given, the face has %d" % [loops.size(), rims.size()]
		return false
	var used := {}
	var base := 0
	for li in loops.size():
		var S: PackedVector3Array = loops[li]
		if S.size() < 3:
			why = "a rim loop of under three samples"
			return false
		# (its rim: the face's loop nearest its samples)
		var best := -1
		var bd := INF
		for ri in rims.size():
			if used.has(ri):
				continue
			var d := 0.0
			var step := maxi(1, S.size() / 8)
			for k in range(0, S.size(), step):
				d += _poly_dist(m.P, rims[ri], S[k])
			if d < bd:
				bd = d
				best = ri
		used[best] = true
		var B: PackedInt32Array = rims[best]
		var nb := B.size()
		var cum := PackedFloat64Array([0.0])
		for j in nb:
			cum.append(cum[j] + m.P[B[j]].distance_to(m.P[B[(j + 1) % nb]]))
		var total := cum[nb]
		var seg := PackedInt32Array()
		var uu := PackedFloat64Array()
		var par := PackedFloat64Array()
		var off := 0.0
		for k in S.size():
			var bj := 0
			var bu := 0.0
			var bdd := INF
			for j in nb:
				var a := m.P[B[j]]
				var b := m.P[B[(j + 1) % nb]]
				var ab := b - a
				var l2 := ab.length_squared()
				var u := clampf((S[k] - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-40 else 0.0
				var d := S[k].distance_squared_to(a + ab * u)
				if d < bdd:
					bdd = d
					bj = j
					bu = u
			off = maxf(off, sqrt(bdd))
			seg.append(bj)
			uu.append(bu)
			par.append(cum[bj] + bu * (cum[bj + 1] - cum[bj]))
		if off > 0.25 * L:
			why = "a rim sample off the face's rim (%.3g L)" % (off / L)
			return false
		# (which way the samples run round it - and once round, in order)
		var sgn := 0.0
		for k in S.size():
			var d := fposmod(par[(k + 1) % S.size()] - par[k], total)
			sgn += d if d < total * 0.5 else d - total
		var fwd := sgn >= 0.0
		var sum := 0.0
		for k in S.size():
			var d := par[(k + 1) % S.size()] - par[k] if fwd else par[k] - par[(k + 1) % S.size()]
			d = fposmod(d, total)
			if d <= total * 1e-9:
				why = "rim samples out of order (or two at one place)"
				return false
			sum += d
		if absf(sum - total) > total * 1e-3:
			why = "rim samples not once round their loop"
			return false
		# put them in: each rim side's samples in order along it
		var by_seg := {}
		for k in S.size():
			if not by_seg.has(seg[k]):
				by_seg[seg[k]] = []
			(by_seg[seg[k]] as Array).append([uu[k], k])
		var eps := 1e-3 * L
		for j in by_seg:
			var lst: Array = by_seg[j]
			lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			var a0 := B[j]
			var b0 := B[(j + 1) % nb]
			var ln := m.P[a0].distance_to(m.P[b0])
			var cur_a := a0
			for e in lst:
				var u: float = e[0]
				var k: int = e[1]
				var gk := base + k
				var at := -1
				if u * ln < eps:
					at = a0
				elif (1.0 - u) * ln < eps:
					at = b0
				if at >= 0:
					if m.smp[at] >= 0:
						why = "two rim samples at one point"
						return false
					m.smp[at] = gk
					m.P[at] = S[k]
					continue
				var nrm := m.N[cur_a].lerp(m.N[b0], u).normalized()
				var mi := m.split(cur_a, b0, S[k], nrm, m.home[cur_a])
				m.smp[mi] = gk
				cur_a = mi
		base += S.size()
	return true


## (own_rim) The samples put into the face's own rim: old points kept, others split into its sides.
static func _put_own_samples(m: HM, rim: Dictionary) -> bool:
	var keep: Dictionary = rim.get("keep", {})
	var split: Dictionary = rim.get("split", {})
	var n0 := m.orig.size()
	var sides := []
	for a in m.rnext:
		sides.append(Vector2i(a, m.rnext[a]))
	for i in n0:
		if m.rim[i] == 1 and keep.has(m.orig[i]):
			m.smp[i] = int(keep[m.orig[i]])
	var any := false
	for sd: Vector2i in sides:
		var a := sd.x
		var b := sd.y
		var oa := m.orig[a]
		var ob := m.orig[b]
		var lst := []
		if split.has(Vector2i(oa, ob)):
			for e in split[Vector2i(oa, ob)]:
				lst.append([float(e[0]), int(e[1]), e[2]])
		if split.has(Vector2i(ob, oa)):
			for e in split[Vector2i(ob, oa)]:
				lst.append([1.0 - float(e[0]), int(e[1]), e[2]])
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var cur := a
		for e in lst:
			var u: float = e[0]
			var nrm := m.N[a].lerp(m.N[b], u).normalized()
			var mi := m.split(cur, b, e[2], nrm, m.home[cur])
			if mi < 0:
				why = "a rim sample that won't go in"
				return false
			m.smp[mi] = int(e[1])
			cur = mi
	if trace:
		var left := m.rnext.duplicate()
		while not left.is_empty():
			var st: int = left.keys()[0]
			var cur := st
			var ns := 0
			var np := 0
			var ln := 0.0
			while left.has(cur):
				var nx: int = left[cur]
				left.erase(cur)
				ns += 1 if m.smp[cur] >= 0 else 0
				np += 1
				ln += m.P[cur].distance_to(m.P[nx])
				cur = nx
			print("  rim loop: %d points, %d samples, length %.4f" % [np, ns, ln])
	for i in m.P.size():
		if m.smp[i] >= 0:
			any = true
			break
	if not any:
		why = "no rim samples"
		return false
	return true


## The distance from p to a loop of points.
static func _poly_dist(P: PackedVector3Array, loop: PackedInt32Array, p: Vector3) -> float:
	var bd := INF
	var n := loop.size()
	for j in n:
		var a := P[loop[j]]
		var ab := P[loop[(j + 1) % n]] - a
		var l2 := ab.length_squared()
		var u := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-40 else 0.0
		bd = minf(bd, p.distance_to(a + ab * u))
	return bd


## The rim's points that aren't samples taken out - their triangles laid out again between the samples
## either side (the side between them a fan from each, meeting at one inner point: the best such fan).
static func _drop_rim_extras(m: HM, h: float) -> bool:
	var todo := PackedInt32Array()
	for b in m.P.size():
		if m.rim[b] == 1 and m.smp[b] < 0 and not (m.VT[b] as PackedInt32Array).is_empty():
			todo.append(b)
	for attempt in 6:
		if attempt == 1:
			_refine(m, h)   # (first on the face as it is - big triangles leave room; then finer)
		var left := PackedInt32Array()
		for b in todo:
			if not _rim_remove(m, b, attempt >= 3):
				left.append(b)
				if trace:
					print("  rim point %d stays (attempt %d): a %d c %d, %d triangles: %s" % [b, attempt, m.rprev[b], m.rnext[b], (m.VT[b] as PackedInt32Array).size(), m.err])
		if left.is_empty():
			return true
		todo = left
		# (some couldn't go yet: the triangles near them evened out a little, then again)
		var near := {}
		for b in todo:
			for x in m.nbrs(b):
				near[x] = true
				for y in m.nbrs(x):
					near[y] = true
		var pts := PackedInt32Array(near.keys())
		for i in pts:
			if m.rim[i] == 0:
				_smooth_one(m, i, 0.5, 0.02)
		_flip_near(m, pts, 0.02)
	why = "rim points that won't come out"
	return false


static func _rim_remove(m: HM, b: int, force := false) -> bool:
	var a: int = m.rprev[b]
	var c: int = m.rnext[b]
	if a == c:
		m.err = "two-point rim"
		return false
	var xs := PackedInt32Array()
	var fan := PackedInt32Array()
	var u := c
	while true:
		var found := -1
		var w := -1
		for ti in m.VT[b]:
			var r := m.rot(ti, b)
			if r.x == u:
				found = ti
				w = r.y
				break
		if found < 0 or fan.size() > 200:
			m.err = "fan broken"
			return false
		fan.append(found)
		if w == a:
			break
		xs.append(w)
		u = w
	if fan.size() != (m.VT[b] as PackedInt32Array).size():
		m.err = "two fans"
		return false
	var k := xs.size()
	var best: Array = []
	if k == 0:
		if m.edge_tris(c, a).size() != 2:
			m.err = "ear on the rim"
			return false
	else:
		if m.has_edge(a, c):
			# (a and c already joined across the face - a thin place: that side split at its middle, so the fan
			# can close a-c)
			if m.edge_tris(a, c).size() != 2 or m.rim[a] == 1 and m.rim[c] == 1 and m.rnext.get(c, -1) == a:
				m.err = "a-c a side already (k %d, its triangles %d, c->a %s, smp a %d c %d)" % [k, m.edge_tris(a, c).size(), m.rnext.get(c, -1) == a, m.smp[a], m.smp[c]]
				return false
			var mid := (m.P[a] + m.P[c]) * 0.5
			var hit: Array = m.surf.project(mid, m.home[a], (m.N[a] + m.N[c]).normalized())
			m.split(a, c, hit[0], hit[1], int(hit[2]))
			if m.has_edge(a, c):
				m.err = "a-c a side already (k %d)" % k
				return false
		var old_min := INF
		for ti in fan:
			old_min = minf(old_min, m.tri_q(ti))
		var bq := minf(0.0, old_min) - 1e-6   # (better than nothing, or no worse than it was)
		var any_q := -INF
		var any_best: Array = []   # (forced: the option with the best triangles on the whole)
		for s in range(1, k + 1):
			var nt := []
			var ok := true
			for i in range(1, s):
				nt.append([c, xs[i - 1], xs[i]])
			nt.append([a, c, xs[s - 1]])
			for i in range(s, k):
				nt.append([a, xs[i - 1], xs[i]])
			for i in range(2, s + 1):
				if m.has_edge(c, xs[i - 1]):
					ok = false
			for i in range(s, k):
				if m.has_edge(a, xs[i - 1]):
					ok = false
			if not ok:
				continue
			var q := INF
			var qs := 0.0
			for tr in nt:
				var x := m.qual(tr[0], tr[1], tr[2])
				q = minf(q, x)
				qs += x
			if q > bq:
				bq = q
				best = nt
			if qs > any_q:
				any_q = qs
				any_best = nt
		if best.is_empty():
			m.err = "no fan fits (old min %.3f, k %d)" % [old_min, k]
			if _rim_push_in(m, a, b, c):
				return true
			if not force or any_best.is_empty():
				return false
			best = any_best
	for ti in fan:
		m.del_t(ti)
	for tr in best:
		m.add_t(tr[0], tr[1], tr[2])
	m.rnext[a] = c
	m.rprev[c] = a
	m.rnext.erase(b)
	m.rprev.erase(b)
	m.rim[b] = 0
	if force:
		# (what folded: its inner points eased toward their neighbours' middle till it doesn't)
		for it in 8:
			var folded := false
			for x in xs:
				for ti in m.VT[x]:
					if m.tri_q(ti) < 0.0:
						folded = true
				var nb := m.nbrs(x)
				var cc := Vector3.ZERO
				for y in nb:
					cc += m.P[y]
				m.move(x, cc / nb.size(), 0.02)
			if not folded:
				break
	return true


## A rim point that can't be taken out pushed inside instead: a new triangle a, c, b on the rim's side a-c,
## b moved in off it (as far as that folds nothing) - an inner point from then on.
static func _rim_push_in(m: HM, a: int, b: int, c: int) -> bool:
	var ac := m.P[c] - m.P[a]
	var l := ac.length()
	if l < 1e-12:
		return false
	var u := clampf((m.P[b] - m.P[a]).dot(ac) / (l * l), 0.2, 0.8)
	var foot := m.P[a] + ac * u
	var inward := m.N[b].cross(ac).normalized()
	# (inward: the side where the triangle a, c, b faces the surface's way)
	if ac.cross(inward).dot(m.N[b]) < 0.0:
		inward = -inward
	var old_p := m.P[b]
	var old_n := m.N[b]
	var old_h := m.home[b]
	for f in [0.25, 0.4, 0.15, 0.6]:
		var pr := m.surf.project(foot + inward * (l * f), m.home[b], m.N[b])
		m.P[b] = pr[0]
		m.N[b] = pr[1]
		var ok := m.qual(a, c, b) > 0.05
		if ok:
			for ti in m.VT[b]:
				if m.tri_q(ti) < 0.02:
					ok = false
					break
		if ok:
			m.home[b] = pr[2]
			m.add_t(a, c, b)
			m.rnext[a] = c
			m.rprev[c] = a
			m.rnext.erase(b)
			m.rprev.erase(b)
			m.rim[b] = 0
			return true
	m.P[b] = old_p
	m.N[b] = old_n
	m.home[b] = old_h
	return false


## (tuning) Thin or turned-over triangles and points on top of each other.
static func _audit(m: HM, label: String) -> void:
	var bad := 0
	var worst := []
	var kinds := {}
	for ti in m.T.size() / 3:
		if m.T[ti * 3] < 0:
			continue
		var q := m.tri_q(ti)
		if q < 0.02:
			bad += 1
			var pa := m.P[m.T[ti * 3]]
			var nn := (m.P[m.T[ti * 3 + 1]] - pa).cross(m.P[m.T[ti * 3 + 2]] - pa)
			var ref := m.N[m.T[ti * 3]] + m.N[m.T[ti * 3 + 1]] + m.N[m.T[ti * 3 + 2]]
			var kind := "zero" if nn.length() < 1e-14 else ("away" if nn.dot(ref) <= 0.0 else ("steep" if q < 0.0 else "thin"))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			if worst.size() < 3:
				worst.append([ti, m.T[ti * 3], m.T[ti * 3 + 1], m.T[ti * 3 + 2], q])
	print("  audit %s: %d thin/turned triangles %s %s" % [label, bad, str(kinds), str(worst)])


## Triangles turned over or flat (a messy face's, or left by forced changes) put right where they can be: their
## sides flipped, their inner points moved to their neighbours' middle - rounds while it helps.
static func _untangle(m: HM) -> int:
	var bad := PackedInt32Array()
	for round_i in 12:
		bad = PackedInt32Array()
		var thin := PackedInt32Array()
		for ti in m.T.size() / 3:
			if m.T[ti * 3] < 0:
				continue
			var q := m.tri_q(ti)
			if q <= 0.0:
				bad.append(ti)
			elif q < 0.02:
				thin.append(ti)
		for ti in thin:
			# (a sliver: its longest side flipped, if that's better)
			if m.T[ti * 3] < 0:
				continue
			var bj := 0
			var bl := -1.0
			for j in 3:
				var l := m.P[m.T[ti * 3 + j]].distance_squared_to(m.P[m.T[ti * 3 + (j + 1) % 3]])
				if l > bl:
					bl = l
					bj = j
			m.flip(m.T[ti * 3 + bj], m.T[ti * 3 + (bj + 1) % 3], 0.0)
		if bad.is_empty():
			return 0
		var pts := {}
		for ti in bad:
			if m.T[ti * 3] < 0:
				continue
			for j in 3:
				var a := m.T[ti * 3 + j]
				var b := m.T[ti * 3 + (j + 1) % 3]
				pts[a] = true
				m.flip(a, b, 0.0)
		# (a widening neighbourhood: a fold's points first, then theirs)
		var ring := pts.keys()
		if round_i >= 4:
			for x in ring.duplicate():
				for y in m.nbrs(x):
					pts[y] = true
			ring = pts.keys()
		for x in ring:
			if m.rim[x] == 0 and not (m.VT[x] as PackedInt32Array).is_empty():
				_smooth_one(m, x, 1.0, 0.02)
	return bad.size()


## Every side of the mesh once: Vector2i(lo, hi).
static func _edges(m: HM) -> Array:
	var seen := {}
	for ti in m.T.size() / 3:
		if m.T[ti * 3] < 0:
			continue
		for j in 3:
			var a := m.T[ti * 3 + j]
			var b := m.T[ti * 3 + (j + 1) % 3]
			seen[Vector2i(mini(a, b), maxi(a, b))] = true
	return seen.keys()


## Long inner sides split (longest first, in rounds) till none is over 4/3 h - thin triangles of a coarse face
## cut down; after each round the triangles round the new points flipped to better ones.
static func _refine(m: HM, h: float) -> void:
	var lim2 := (h * 4.0 / 3.0) * (h * 4.0 / 3.0)
	# (a cap: a few times the triangles the face's area needs at this spacing - a badly folded face's projections
	# can land far off and split on and on)
	var area := 0.0
	for ti in m.T.size() / 3:
		if m.T[ti * 3] >= 0:
			area += (m.P[m.T[ti * 3 + 1]] - m.P[m.T[ti * 3]]).cross(m.P[m.T[ti * 3 + 2]] - m.P[m.T[ti * 3]]).length() * 0.5
	var cap := maxi(m.T.size() / 3 * 2, int(area / (0.433 * h * h) * 4.0) + 1000)
	for round_i in 14:
		if m.T.size() / 3 > cap:
			break
		var long := []
		for e: Vector2i in _edges(m):
			if _splittable(m, e.x, e.y, lim2):
				long.append([m.P[e.x].distance_squared_to(m.P[e.y]), e])
		if long.is_empty():
			break
		long.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
		var made := PackedInt32Array()
		for x in long:
			var e: Vector2i = x[1]
			if not _splittable(m, e.x, e.y, lim2):
				continue
			var pr := m.surf.project((m.P[e.x] + m.P[e.y]) * 0.5, m.home[e.x], (m.N[e.x] + m.N[e.y]).normalized())
			made.append(m.split(e.x, e.y, pr[0], pr[1], pr[2]))
			if m.T.size() / 3 > cap:
				break
		_flip_near(m, made, 0.02)


## The sides round points `pts` (theirs and their triangles' far sides) flipped where that makes better triangles.
static func _flip_near(m: HM, pts: PackedInt32Array, gain: float) -> void:
	var todo := {}
	for i in pts:
		for ti in m.VT[i]:
			for j in 3:
				var a := m.T[ti * 3 + j]
				var b := m.T[ti * 3 + (j + 1) % 3]
				todo[Vector2i(mini(a, b), maxi(a, b))] = true
	for e: Vector2i in todo:
		m.flip(e.x, e.y, gain)


static func _splittable(m: HM, a: int, b: int, lim2: float) -> bool:
	var d2 := m.P[a].distance_squared_to(m.P[b])
	if d2 <= lim2 or not m.has_edge(a, b):
		return false
	# (a rim point's sides: as long as most of its rim sides - the triangles on the rim as big as its samples'
	# spacing; splitting them shorter only makes thin ones)
	for r in [a, b]:
		if m.rim[r] == 1:
			var rs := maxf(m.P[r].distance_squared_to(m.P[m.rnext[r]]), m.P[r].distance_squared_to(m.P[m.rprev[r]]))
			if d2 <= 0.64 * rs:
				return false
	return not (m.rim[a] == 1 and m.rim[b] == 1 and m.edge_tris(a, b).size() == 1)


## Isotropic remeshing rounds: split long, collapse short, flip to better triangles, smooth along the surface.
static func _remesh(m: HM, h: float, rounds: int) -> void:
	for r in rounds:
		var q0 := Time.get_ticks_usec()
		_refine(m, h)
		if trace:
			print("    remesh refine %d ms, %d triangles" % [(Time.get_ticks_usec() - q0) / 1000, m.T.size() / 3])
			q0 = Time.get_ticks_usec()
		var lo2 := (h * 0.6) * (h * 0.6)
		for e: Vector2i in _edges(m):
			if not m.has_edge(e.x, e.y) or m.P[e.x].distance_squared_to(m.P[e.y]) > lo2:
				continue
			var keep := e.x
			var gone := e.y
			if m.rim[gone] == 1:
				keep = e.y
				gone = e.x
			if m.rim[gone] == 1:
				continue
			var np := m.P[keep] if m.rim[keep] == 1 else (m.P[keep] + m.P[gone]) * 0.5
			var pr := m.surf.project(np, m.home[keep], m.N[keep])
			m.collapse(keep, gone, pr[0], pr[1], pr[2], 0.1)
		if trace:
			print("    remesh collapse %d ms" % ((Time.get_ticks_usec() - q0) / 1000))
			q0 = Time.get_ticks_usec()
		for e: Vector2i in _edges(m):
			m.flip(e.x, e.y, 0.01)
		if trace:
			print("    remesh flip %d ms" % ((Time.get_ticks_usec() - q0) / 1000))
			q0 = Time.get_ticks_usec()
		_smooth(m, 0.6, 0.05)
		if trace:
			print("    remesh smooth %d ms" % ((Time.get_ticks_usec() - q0) / 1000))


## Each inner point moved part way to its neighbours' middle (along the surface), where nothing folds.
static func _smooth(m: HM, amount: float, min_q: float) -> void:
	for i in m.P.size():
		if m.rim[i] == 1 or (m.VT[i] as PackedInt32Array).is_empty():
			continue
		_smooth_one(m, i, amount, min_q)


static func _smooth_one(m: HM, i: int, amount: float, min_q: float) -> void:
	var nb := m.nbrs(i)
	if nb.is_empty():
		return
	var c := Vector3.ZERO
	for x in nb:
		c += m.P[x]
	c /= nb.size()
	var d := c - m.P[i]
	d -= m.N[i] * m.N[i].dot(d)
	m.move(i, m.P[i] + d * amount, min_q)


# ---------------------------------------------------------------- 2-3. the fields

## The helper mesh's points as a graph: {n, ids (graph -> mesh point), of (mesh point -> graph), off, adj}.
static func _graph(m: HM) -> Dictionary:
	var of := PackedInt32Array()
	of.resize(m.P.size())
	of.fill(-1)
	var ids := PackedInt32Array()
	for i in m.P.size():
		if not (m.VT[i] as PackedInt32Array).is_empty():
			of[i] = ids.size()
			ids.append(i)
	var off := PackedInt32Array([0])
	var adj := PackedInt32Array()
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	var fq := PackedVector3Array()   # (a fixed direction - the rim's tangent - or zero)
	var fo := PackedByteArray()   # (1: a fixed lattice point - a rim sample)
	for gi in ids.size():
		var i := ids[gi]
		for x in m.nbrs(i):
			adj.append(of[x])
		off.append(adj.size())
		p.append(m.P[i])
		n.append(m.N[i])
		var q := Vector3.ZERO
		var f := 0
		if m.rim[i] == 1:
			f = 1
			var a := m.P[m.rprev[i]]
			var b := m.P[m.rnext[i]]
			var d0 := (m.P[i] - a).normalized()
			var d1 := (b - m.P[i]).normalized()
			if d0.dot(d1) > cos(deg_to_rad(40.0)):
				q = (b - a)
				q -= m.N[i] * m.N[i].dot(q)
				q = q.normalized()
		fq.append(q)
		fo.append(f)
	return {"n": ids.size(), "ids": ids, "of": of, "off": off, "adj": adj, "p": p, "nrm": n, "fq": fq, "fo": fo}


## Coarser and coarser graphs (neighbours matched in pairs): levels[0] the graph itself; each level's
## "parent" maps its points to the next level's.
static func _hierarchy(g: Dictionary) -> Array:
	var levels := [g]
	while true:
		var cur: Dictionary = levels.back()
		var n: int = cur["n"]
		if n < 40:
			break
		var off: PackedInt32Array = cur["off"]
		var adj: PackedInt32Array = cur["adj"]
		var nrm: PackedVector3Array = cur["nrm"]
		var parent := PackedInt32Array()
		parent.resize(n)
		parent.fill(-1)
		var cn := 0
		for i in n:
			if parent[i] >= 0:
				continue
			var best := -1
			var bd := -2.0
			for k in range(off[i], off[i + 1]):
				var j := adj[k]
				if parent[j] >= 0:
					continue
				var d := nrm[i].dot(nrm[j])
				if d > bd:
					bd = d
					best = j
			parent[i] = cn
			if best >= 0:
				parent[best] = cn
			cn += 1
		if cn > n * 0.85:
			break
		var p := PackedVector3Array()
		var nn := PackedVector3Array()
		var cnt := PackedInt32Array()
		var fq := PackedVector3Array()
		var fo := PackedByteArray()
		var fop := PackedVector3Array()   # (the fixed lattice point: a rim sample's place)
		p.resize(cn)
		nn.resize(cn)
		cnt.resize(cn)
		fq.resize(cn)
		fo.resize(cn)
		fop.resize(cn)
		var cp: PackedVector3Array = cur["p"]
		var cfq: PackedVector3Array = cur["fq"]
		var cfo: PackedByteArray = cur["fo"]
		var cfop: PackedVector3Array = cur.get("fop", cp)
		for i in n:
			var c := parent[i]
			p[c] += cp[i]
			nn[c] += nrm[i]
			cnt[c] += 1
			if cfq[i] != Vector3.ZERO and fq[c] == Vector3.ZERO:
				fq[c] = cfq[i]
			if cfo[i] == 1 and fo[c] == 0:
				fo[c] = 1
				fop[c] = cfop[i]
		for c in cn:
			p[c] /= cnt[c]
			nn[c] = nn[c].normalized() if nn[c].length_squared() > 1e-30 else Vector3.UP
			if fq[c] != Vector3.ZERO:
				var q := fq[c] - nn[c] * nn[c].dot(fq[c])
				fq[c] = q.normalized() if q.length_squared() > 1e-30 else Vector3.ZERO
		var lists := []
		lists.resize(cn)
		for c in cn:
			lists[c] = PackedInt32Array()
		for i in n:
			var a := parent[i]
			for k in range(off[i], off[i + 1]):
				var b := parent[adj[k]]
				if a != b and not (lists[a] as PackedInt32Array).has(b):
					lists[a].append(b)
		var coff := PackedInt32Array([0])
		var cadj := PackedInt32Array()
		for c in cn:
			cadj.append_array(lists[c])
			coff.append(cadj.size())
		cur["parent"] = parent
		levels.append({"n": cn, "off": coff, "adj": cadj, "p": p, "nrm": nn, "fq": fq, "fo": fo, "fop": fop})
	return levels


static func _orient_field(levels: Array) -> void:
	var top: Dictionary = levels.back()
	var tn: int = top["n"]
	var q := PackedVector3Array()
	q.resize(tn)
	var tnrm: PackedVector3Array = top["nrm"]
	var tfq: PackedVector3Array = top["fq"]
	for i in tn:
		if tfq[i] != Vector3.ZERO:
			q[i] = tfq[i]
		else:
			var any := Vector3.RIGHT if absf(tnrm[i].x) < 0.9 else Vector3.UP
			q[i] = (any - tnrm[i] * tnrm[i].dot(any)).normalized()
	for li in range(levels.size() - 1, -1, -1):
		var lv: Dictionary = levels[li]
		if li < levels.size() - 1:
			# (from the coarser level: each point its parent's direction, laid in its own tangent plane)
			var coarse_q := q
			var parent: PackedInt32Array = lv["parent"]
			var n0: int = lv["n"]
			var nrm0: PackedVector3Array = lv["nrm"]
			q = PackedVector3Array()
			q.resize(n0)
			for i in n0:
				var x := coarse_q[parent[i]]
				x -= nrm0[i] * nrm0[i].dot(x)
				q[i] = x.normalized() if x.length_squared() > 1e-30 else coarse_q[parent[i]]
		var fq: PackedVector3Array = lv["fq"]
		for i in (lv["n"] as int):
			if fq[i] != Vector3.ZERO:
				q[i] = fq[i]
		var sweeps := ORI_SWEEPS if li > 0 else ORI_SWEEPS0
		if li == levels.size() - 1:
			sweeps = 100
		_orient_sweeps(lv, q, sweeps)
		lv["q"] = q


static func _orient_sweeps(lv: Dictionary, q: PackedVector3Array, sweeps: int) -> void:
	var n: int = lv["n"]
	var off: PackedInt32Array = lv["off"]
	var adj: PackedInt32Array = lv["adj"]
	var nrm: PackedVector3Array = lv["nrm"]
	var fq: PackedVector3Array = lv["fq"]
	for s in sweeps:
		for ii in n:
			var i := ii if s % 2 == 0 else n - 1 - ii
			if fq[i] != Vector3.ZERO:
				continue
			var ni := nrm[i]
			var sum := q[i]
			var w := 0.0
			for k in range(off[i], off[i + 1]):
				var j := adj[k]
				var nj := nrm[j]
				var q1 := q[j]
				var a1 := ni.cross(sum)
				var b1 := nj.cross(q1)
				var d00 := sum.dot(q1)
				var d01 := sum.dot(b1)
				var d10 := a1.dot(q1)
				var d11 := a1.dot(b1)
				var A := sum
				var B := q1 if d00 >= 0.0 else -q1
				var best := absf(d00)
				if absf(d01) > best:
					best = absf(d01)
					B = b1 if d01 >= 0.0 else -b1
				if absf(d10) > best:
					best = absf(d10)
					A = a1
					B = q1 if d10 >= 0.0 else -q1
				if absf(d11) > best:
					A = a1
					B = b1 if d11 >= 0.0 else -b1
				sum = A * w + B
				w += 1.0
				sum -= ni * ni.dot(sum)
				var l := sum.length()
				if l > 1e-30:
					sum /= l
			q[i] = sum


## The lattice point nearest p.
static func _round4(o: Vector3, q: Vector3, n: Vector3, p: Vector3, L: float) -> Vector3:
	var t := n.cross(q)
	var d := p - o
	return o + q * (roundf(q.dot(d) / L) * L) + t * (roundf(t.dot(d) / L) * L)


static func _position_field(levels: Array, L: float) -> void:
	var o := PackedVector3Array()
	for li in range(levels.size() - 1, -1, -1):
		var lv: Dictionary = levels[li]
		var n: int = lv["n"]
		var p: PackedVector3Array = lv["p"]
		var nrm: PackedVector3Array = lv["nrm"]
		var q: PackedVector3Array = lv["q"]
		var fo: PackedByteArray = lv["fo"]
		var fop: PackedVector3Array = lv.get("fop", p)
		if li == levels.size() - 1:
			o = p.duplicate()
		else:
			var coarse := o
			var parent: PackedInt32Array = lv["parent"]
			o = PackedVector3Array()
			o.resize(n)
			for i in n:
				var x := coarse[parent[i]]
				x -= nrm[i] * nrm[i].dot(x - p[i])
				o[i] = _round4(x, q[i], nrm[i], p[i], L)
		for i in n:
			if fo[i] == 1:
				o[i] = fop[i]
		var sweeps := POS_SWEEPS if li > 0 else POS_SWEEPS0
		if li == levels.size() - 1:
			sweeps = 100
		_position_sweeps(lv, o, sweeps, L)
		lv["o"] = o


static func _position_sweeps(lv: Dictionary, o: PackedVector3Array, sweeps: int, L: float) -> void:
	var n: int = lv["n"]
	var off: PackedInt32Array = lv["off"]
	var adj: PackedInt32Array = lv["adj"]
	var p: PackedVector3Array = lv["p"]
	var nrm: PackedVector3Array = lv["nrm"]
	var q: PackedVector3Array = lv["q"]
	var fo: PackedByteArray = lv["fo"]
	var inv := 1.0 / L
	for s in sweeps:
		for ii in n:
			var i := ii if s % 2 == 0 else n - 1 - ii
			if fo[i] == 1:
				continue
			var ni := nrm[i]
			var qi := q[i]
			var pi := p[i]
			var sum := o[i]
			var w := 0.0
			var ti := ni.cross(qi)
			for k in range(off[i], off[i + 1]):
				var j := adj[k]
				var nj := nrm[j]
				var pj := p[j]
				# (j's direction turned to match i's)
				var q1 := q[j]
				var b1 := nj.cross(q1)
				var qj := q1
				var dq := qi.dot(q1)
				var db := qi.dot(b1)
				if absf(db) > absf(dq):
					qj = b1 if db >= 0.0 else -b1
				elif dq < 0.0:
					qj = -q1
				var tj := nj.cross(qj)
				# (where their tangent planes meet: each lattice's cell there, then the nearest pair of corners)
				var n0p0 := ni.dot(pi)
				var n0p1 := ni.dot(pj)
				var n1p0 := nj.dot(pi)
				var n1p1 := nj.dot(pj)
				var n0n1 := ni.dot(nj)
				var den := 1.0 / (1.0 - n0n1 * n0n1 + 1e-4)
				var l0 := 2.0 * (n0p1 - n0p0 - n0n1 * (n1p0 - n1p1)) * den
				var l1 := 2.0 * (n1p0 - n1p1 - n0n1 * (n0p1 - n0p0)) * den
				var mid := 0.5 * (pi + pj) - 0.25 * (ni * l0 + nj * l1)
				var da := mid - sum
				var a := sum + qi * (floorf(qi.dot(da) * inv) * L) + ti * (floorf(ti.dot(da) * inv) * L)
				var o1 := o[j]
				var dbv := mid - o1
				var b := o1 + qj * (floorf(qj.dot(dbv) * inv) * L) + tj * (floorf(tj.dot(dbv) * inv) * L)
				# (the corners of the two cells nearest each other: with j's frame turned to match i's, a step of
				# -1, 0 or 1 along each axis - the step that undoes most of their difference)
				var d := (b - a) * inv
				var kx := clampi(roundi(d.dot(qi)), -1, 1)
				var ky := clampi(roundi(d.dot(ti)), -1, 1)
				var ba := Vector3.ZERO
				var bb := Vector3.ZERO
				if kx > 0:
					ba += qi * L
				elif kx < 0:
					bb += qj * L
				if ky > 0:
					ba += ti * L
				elif ky < 0:
					bb += tj * L
				sum = ((a + ba) * w + (b + bb)) / (w + 1.0)
				w += 1.0
				sum -= ni * ni.dot(sum - pi)
			o[i] = _round4(sum, qi, ni, pi, L)


# ---------------------------------------------------------------- 4. extraction

## Points whose lattice points coincide collapsed into one, then moved there.
static func _extract(m: HM, g: Dictionary, lv: Dictionary, L: float) -> void:
	var of: PackedInt32Array = g["of"]
	var lo: PackedVector3Array = lv["o"]
	var np := m.P.size()
	var o := PackedVector3Array()   # (each mesh point: its cluster's lattice point sum, and count)
	o.resize(np)
	var cnt := PackedInt32Array()
	cnt.resize(np)
	var psum := PackedVector3Array()
	psum.resize(np)
	for i in np:
		if of[i] >= 0:
			o[i] = lo[of[i]]
			cnt[i] = 1
			psum[i] = m.P[i]
	var lim := MERGE * L
	for pass_i in 4:
		var cand := []
		for e: Vector2i in _edges(m):
			if m.rim[e.x] == 1 and m.rim[e.y] == 1:
				continue
			var d := (o[e.x] / cnt[e.x]).distance_to(o[e.y] / cnt[e.y])
			if d < lim:
				cand.append([d, e])
		if cand.is_empty():
			break
		cand.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var done := 0
		for x in cand:
			var e: Vector2i = x[1]
			if not m.has_edge(e.x, e.y):
				continue
			var keep := e.x
			var gone := e.y
			if m.rim[gone] == 1:
				keep = e.y
				gone = e.x
			var c := cnt[keep] + cnt[gone]
			var at := (psum[keep] + psum[gone]) / c
			var pr := m.surf.project(at, m.home[keep], m.N[keep])
			if m.collapse(keep, gone, pr[0], pr[1], pr[2], 0.02):
				o[keep] += o[gone]
				cnt[keep] = c
				psum[keep] += psum[gone]
				done += 1
		if done == 0:
			break
	# (each to its lattice point - part way where all the way would fold)
	for pass_i in 3:
		for i in np:
			if m.rim[i] == 1 or cnt[i] == 0 or (m.VT[i] as PackedInt32Array).is_empty():
				continue
			var target := o[i] / cnt[i]
			if m.P[i].distance_squared_to(target) < 1e-4 * L * L:
				continue
			if not m.move(i, target, 0.01):
				m.move(i, m.P[i].lerp(target, 0.5), 0.01)


## Points too near each other merged, triangles flipped to the better diagonal.
static func _tidy(m: HM, L: float) -> void:
	var lo2 := (0.35 * L) * (0.35 * L)
	for e: Vector2i in _edges(m):
		if not m.has_edge(e.x, e.y) or m.P[e.x].distance_squared_to(m.P[e.y]) > lo2:
			continue
		var keep := e.x
		var gone := e.y
		if m.rim[gone] == 1:
			keep = e.y
			gone = e.x
		if m.rim[gone] == 1:
			continue
		var at := m.P[keep] if m.rim[keep] == 1 else (m.P[keep] + m.P[gone]) * 0.5
		var pr := m.surf.project(at, m.home[keep], m.N[keep])
		m.collapse(keep, gone, pr[0], pr[1], pr[2], 0.02)
	for pass_i in 3:
		for e: Vector2i in _edges(m):
			m.flip(e.x, e.y, 0.05)


## How good a quad a, b, c, d (in order round it) is: 0..1 (square: 1), -1 not convex / turned over.
static func _quad_q(m: HM, a: int, b: int, c: int, d: int) -> float:
	var ids := [a, b, c, d]
	var nr := m.N[a] + m.N[b] + m.N[c] + m.N[d]
	var worst := 0.0
	var lo := INF
	var hi := 0.0
	for k in 4:
		var p: Vector3 = m.P[ids[k]]
		var nx: Vector3 = m.P[ids[(k + 1) % 4]]
		var pv: Vector3 = m.P[ids[(k + 3) % 4]]
		var e0 := nx - p
		var e1 := pv - p
		# (convex: each corner turns the surface's way)
		if e0.cross(e1).dot(nr) <= 0.0:
			return -1.0
		var ang := rad_to_deg(e0.angle_to(e1))
		worst = maxf(worst, absf(ang - 90.0))
		var l := e0.length()
		lo = minf(lo, l)
		hi = maxf(hi, l)
	if lo <= 1e-20:
		return -1.0
	return (1.0 - worst / 90.0) * sqrt(lo / hi)


## Triangles paired into quads across their sides: greedy by quality, then augmenting paths to pair the
## ones left. Faces: Arrays of mesh points (3 or 4), wound as the triangles.
static func _pair(m: HM) -> Array:
	var tl := PackedInt32Array()
	var idx := {}
	for ti in m.T.size() / 3:
		if m.T[ti * 3] >= 0:
			idx[ti] = tl.size()
			tl.append(ti)
	var nt := tl.size()
	# candidate pairs: [quality, tri a, tri b, quad corners]
	var cand := []
	var by_tri := []
	by_tri.resize(nt)
	for i in nt:
		by_tri[i] = []
	for i in nt:
		var ti := tl[i]
		for j in 3:
			var a := m.T[ti * 3 + j]
			var b := m.T[ti * 3 + (j + 1) % 3]
			var c := m.T[ti * 3 + (j + 2) % 3]
			if a > b:
				continue
			for o in m.edge_tris(a, b):
				if o == ti:
					continue
				var r := m.rot(o, b)
				if r.x != a:
					continue
				var d := r.y
				var q := _quad_q(m, a, d, b, c)
				if q < PAIR_MIN:
					continue
				var ci := cand.size()
				cand.append([q, i, idx[o], [a, d, b, c]])
				(by_tri[i] as Array).append(ci)
				(by_tri[idx[o]] as Array).append(ci)
	var order := range(cand.size())
	order.sort_custom(func(x, y): return float(cand[x][0]) > float(cand[y][0]))
	var mate := PackedInt32Array()   # (each triangle: the candidate pairing it, -1)
	mate.resize(nt)
	mate.fill(-1)
	for ci in order:
		var c: Array = cand[ci]
		if mate[c[1]] < 0 and mate[c[2]] < 0:
			mate[c[1]] = ci
			mate[c[2]] = ci
	# augmenting paths: from a lone triangle, alternately an unused pairing and a used one, to another lone one
	for round_i in 3:
		var gained := 0
		for s in nt:
			if mate[s] >= 0:
				continue
			var prev := {s: -1}   # (triangle -> the candidate it was reached by)
			var queue := [s]
			var end := -1
			var qi := 0
			while qi < queue.size() and end < 0 and qi < 400:
				var x: int = queue[qi]
				qi += 1
				for ci in by_tri[x]:
					var c: Array = cand[ci]
					var y: int = c[2] if int(c[1]) == x else c[1]
					if prev.has(y) or ci == mate[x]:
						continue
					if mate[y] < 0:
						prev[y] = ci
						end = y
						break
					var mc: Array = cand[mate[y]]
					var z: int = mc[2] if int(mc[1]) == y else mc[1]
					if prev.has(z):
						continue
					prev[y] = ci
					prev[z] = mate[y]
					queue.append(z)
			if end < 0:
				continue
			# (walk back: the path's unused pairings used, its used ones dropped)
			var path := []
			var cur := end
			var seen := {}
			var ok := true
			while cur != s:
				var ci: int = prev[cur]
				if seen.has(ci):
					ok = false
					break
				seen[ci] = true
				path.append(ci)
				var c: Array = cand[ci]
				cur = c[2] if int(c[1]) == cur else c[1]
				if path.size() > 2 * nt:
					ok = false
					break
			if not ok:
				continue
			for k in path.size():
				if k % 2 == 0:
					var c: Array = cand[path[k]]
					mate[c[1]] = path[k]
					mate[c[2]] = path[k]
			gained += 1
		if gained == 0:
			break
	var faces := []
	var done := {}
	for i in nt:
		if mate[i] >= 0:
			if done.has(mate[i]):
				continue
			done[mate[i]] = true
			faces.append((cand[mate[i]][3] as Array).duplicate())
		else:
			var ti := tl[i]
			faces.append([m.T[ti * 3], m.T[ti * 3 + 1], m.T[ti * 3 + 2]])
	return faces


## A face's validity at its points' places: quads with a diagonal that keeps both halves facing the surface's
## way, triangles facing it, none degenerate.
static func _face_ok(m: HM, f: Array, lim := 0.02) -> bool:
	if f.size() == 3:
		return m.qual(f[0], f[1], f[2]) > lim
	var a: int = f[0]
	var b: int = f[1]
	var c: int = f[2]
	var d: int = f[3]
	var ac := m.qual(a, b, c) > lim and m.qual(a, c, d) > lim
	var bd := m.qual(a, b, d) > lim and m.qual(b, c, d) > lim
	return ac or bd


## Pole pairs undone: a quad whose two opposite inner corners merged (its diagonal collapsed) leaves fewer
## poles - two corners of 3 faces each become one of 4, its other two corners lose a face (5 -> 4). Merged
## where nothing folds or tears. The faces left.
static func _fewer_poles(m: HM, faces: Array) -> Array:
	var vf := {}
	for fi in faces.size():
		for x in faces[fi]:
			if not vf.has(x):
				vf[x] = []
			(vf[x] as Array).append(fi)
	var alive := PackedByteArray()
	alive.resize(faces.size())
	alive.fill(1)
	var val := func(x: int) -> int:
		return (vf[x] as Array).size()
	var pole := func(x: int, n: int) -> int:
		return 1 if m.rim[x] == 0 and n != 4 else 0
	for round_i in 3:
		var done := 0
		for fi in faces.size():
			if alive[fi] == 0 or (faces[fi] as Array).size() != 4:
				continue
			var f: Array = faces[fi]
			for k in 2:
				var a: int = f[k]
				var b: int = f[k + 1]
				var c: int = f[(k + 2) % 4]
				var d: int = f[(k + 3) % 4]
				if m.rim[a] == 1 or m.rim[c] == 1:
					continue
				var va: int = val.call(a)
				var vc: int = val.call(c)
				var vb: int = val.call(b)
				var vd: int = val.call(d)
				var before: int = pole.call(a, va) + pole.call(c, vc) + pole.call(b, vb) + pole.call(d, vd)
				var after: int = pole.call(a, va + vc - 2) + pole.call(b, vb - 1) + pole.call(d, vd - 1)
				if after >= before or vb < 3 or vd < 3:
					continue
				# (a and c share only this quad - their other faces meet only at b and d)
				var ok := true
				var fa := {}
				for g in vf[a]:
					if g != fi:
						for x in faces[g]:
							fa[x] = true
				for g in vf[c]:
					if g == fi:
						continue
					for x in faces[g]:
						if x != c and x != b and x != d and fa.has(x):
							ok = false
				if not ok:
					continue
				# (merged at the middle, on the surface: every face round it still facing the right way)
				var pr := m.surf.project((m.P[a] + m.P[c]) * 0.5, m.home[a], m.N[a])
				var old_p := m.P[a]
				var old_n := m.N[a]
				m.P[a] = pr[0]
				m.N[a] = pr[1]
				var changed := []
				for g in vf[c]:
					if g == fi:
						continue
					var h: Array = (faces[g] as Array).duplicate()
					h[h.find(c)] = a
					changed.append([g, h])
				for g in vf[a]:
					if g != fi and not _face_ok(m, faces[g], 0.05):
						ok = false
				for e in changed:
					if not _face_ok(m, e[1], 0.05):
						ok = false
				if not ok:
					m.P[a] = old_p
					m.N[a] = old_n
					continue
				m.home[a] = pr[2]
				alive[fi] = 0
				for x in f:
					(vf[x] as Array).erase(fi)
				for e in changed:
					faces[e[0]] = e[1]
					(vf[a] as Array).append(e[0])
				vf.erase(c)
				done += 1
				break
		if done == 0:
			break
	var out := []
	for fi in faces.size():
		if alive[fi] == 1:
			out.append(faces[fi])
	return out


## A squaring relaxation: each inner point toward where its quads would be parallelograms (and its triangles'
## neighbours' middle), on the surface, where nothing folds.
static func _relax(m: HM, faces: Array, rounds: int) -> void:
	var vf := {}
	for fi in faces.size():
		for x in faces[fi]:
			if not vf.has(x):
				vf[x] = []
			(vf[x] as Array).append(fi)
	for r in rounds:
		for i in vf:
			if m.rim[i] == 1:
				continue
			var tgt := Vector3.ZERO
			var w := 0.0
			var lap := Vector3.ZERO
			var ln := 0
			for fi in vf[i]:
				var f: Array = faces[fi]
				var k := f.find(i)
				var n := f.size()
				var nx: int = f[(k + 1) % n]
				var pv: int = f[(k + n - 1) % n]
				lap += m.P[nx] + m.P[pv]
				ln += 2
				if n == 4:
					var op: int = f[(k + 2) % 4]
					tgt += m.P[nx] + m.P[pv] - m.P[op]
					w += 1.0
			var aim := lap / ln
			if w > 0.0:
				aim = aim * 0.4 + (tgt / w) * 0.6
			var d := aim - m.P[i]
			d -= m.N[i] * m.N[i].dot(d)
			var pr := m.surf.project(m.P[i] + d * 0.5, m.home[i], m.N[i])
			var old_p := m.P[i]
			var old_n := m.N[i]
			m.P[i] = pr[0]
			m.N[i] = pr[1]
			var ok := true
			for fi in vf[i]:
				if not _face_ok(m, faces[fi]):
					ok = false
					break
			if ok:
				m.home[i] = pr[2]
			else:
				m.P[i] = old_p
				m.N[i] = old_n


static func _output(m: HM, faces: Array) -> Dictionary:
	var pts := PackedVector3Array()
	var of := {}
	var out := []
	var folded := 0
	for f in faces:
		if not _face_ok(m, f, 1e-4):
			# (a few folded faces on a badly folded surface: kept - far better than giving up the whole face)
			folded += 1
			if folded > maxi(3, faces.size() * 3 / 100):   # (the layouts are compared after - a worse one loses)
				why = "a folded face after extraction (%d)" % folded
				return {}
		var g := []
		for x in f:
			if m.smp[x] >= 0:
				g.append(-1 - m.smp[x])
			else:
				if not of.has(x):
					of[x] = pts.size()
					pts.append(m.P[x])
				g.append(of[x])
		out.append(g)
	stats["folded"] = folded
	return {"pts": pts, "faces": out}


# ---------------------------------------------------------------- checks

## "" if `res` fills the face properly: every rim sample used, each pair of consecutive samples a side of
## exactly one face, every other side shared by two faces running it opposite ways, no face degenerate or
## facing away from the face's own triangles - else what's wrong.
static func validate(v: PackedVector3Array, t: PackedInt32Array, tris: Array, loops: Array, res: Dictionary) -> String:
	if res.is_empty():
		return "empty"
	var pts: PackedVector3Array = res["pts"]
	var faces: Array = res["faces"]
	var samples := PackedVector3Array()
	var starts := []
	for l in loops:
		starts.append(samples.size())
		samples.append_array(l)
	var at := func(x: int) -> Vector3:
		return samples[-1 - x] if x < 0 else pts[x]
	var dir := {}
	var used := {}
	# the face's own facing (its normals smoothed - a messy face's folds don't count), near each output face
	var sf := Surf.new()
	var loc := {}
	var lp := PackedVector3Array()
	var lt := PackedInt32Array()
	for ti in tris:
		for j in 3:
			var x := t[int(ti) * 3 + j]
			if not loc.has(x):
				loc[x] = lp.size()
				lp.append(v[x])
			lt.append(loc[x])
	var per := 0.0
	for l in loops:
		var pl: PackedVector3Array = l
		for k in pl.size():
			per += pl[k].distance_to(pl[(k + 1) % pl.size()])
	sf.build(lp, lt, maxf(per / maxf(1.0, samples.size()), 1e-9))
	var cen := PackedVector3Array()
	var tn := PackedVector3Array()
	for k in lt.size() / 3:
		cen.append((lp[lt[k * 3]] + lp[lt[k * 3 + 1]] + lp[lt[k * 3 + 2]]) / 3.0)
		tn.append((sf.N[lt[k * 3]] + sf.N[lt[k * 3 + 1]] + sf.N[lt[k * 3 + 2]]).normalized())
	var flipped := 0
	for f in faces:
		var n := (f as Array).size()
		if n != 3 and n != 4:
			return "a face of %d corners" % n
		var fc := Vector3.ZERO
		for k in n:
			var x: int = f[k]
			if x >= pts.size() or -1 - x >= samples.size():
				return "a corner out of range"
			used[x] = true
			fc += at.call(x)
			var y: int = f[(k + 1) % n]
			var key := Vector2i(x, y)
			if dir.has(key):
				return "a side run the same way twice"
			dir[key] = true
		fc /= n
		var p0: Vector3 = at.call(f[0])
		var p1: Vector3 = at.call(f[1])
		var p2: Vector3 = at.call(f[2])
		var fn := (p1 - p0).cross(p2 - p0)
		if n == 4:
			var p3: Vector3 = at.call(f[3])
			fn = (p2 - p0).cross(p3 - p1)
		if fn.length_squared() < 1e-30:
			return "a degenerate face"
		var bi := 0
		var bd := INF
		for k in cen.size():
			var d := cen[k].distance_squared_to(fc)
			if d < bd:
				bd = d
				bi = k
		if fn.normalized().dot(tn[bi]) < 0.0:
			flipped += 1
	if flipped > 0:
		return "%d faces facing away" % flipped
	for k in samples.size():
		if not used.has(-1 - k):
			return "rim sample %d unused" % k
	# rim sides: once each; inner sides: both ways
	var rim := {}
	for li in loops.size():
		var n: int = (loops[li] as PackedVector3Array).size()
		var s0: int = starts[li]
		for k in n:
			var a := -1 - (s0 + k)
			var b := -1 - (s0 + (k + 1) % n)
			rim[Vector2i(a, b)] = true
			rim[Vector2i(b, a)] = true
			if dir.has(Vector2i(a, b)) == dir.has(Vector2i(b, a)):
				return "rim side %d-%d not on exactly one face" % [s0 + k, s0 + (k + 1) % n]
	for key: Vector2i in dir:
		if rim.has(key):
			continue
		if not dir.has(Vector2i(key.y, key.x)):
			return "an open side inside (%d, %d)" % [key.x, key.y]
	return ""
