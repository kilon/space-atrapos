extends RefCounted
## Fillet (the mesh editor's Ctrl+B - mesh_ops.begin_fillet): edges rounded off. Each selected edge
## between two faces becomes a strip of `segments` rows of quads; its sides move `width` back along
## the two faces and its profile is an arc tangent to both (segments 1: a flat chamfer). Where
## filleted edges meet, the corner is closed:
## - one filleted edge ending at a point: its arc joins the face across the end when it lies flat
##   in it (a box's edge: the end faces get the rounded corner), else a face of its own;
## - two with nothing between them (a loop going on, a frame's corner): their arcs welded into one
##   (a mitre);
## - more (a box's corner with all three): a fan rounded out towards the old corner.
## A closed mesh stays closed. The faces round the edges' ends are rebuilt from their outlines (UVs,
## colours and bone weights blended from their old corners); the rest keep their triangles.
##   var r := MeshBevel.fillet(em, edge_ids, 0.05, 4)   # {"ok", "new_points", "msg", ...}
## Every new point is its old point plus an offset times the width (a width of 1 worked out first).

const EditMesh := preload("res://scripts/editor/mesh/edit_mesh.gd")
const MAX_SEGMENTS := 32


## The new points as they're made: each one's old point and its offset for a width of 1.
class NewPts extends RefCounted:
	var n0 := 0
	var base := PackedInt32Array()
	var off := PackedVector3Array()

	func add(p: int, d: Vector3) -> int:
		base.append(p)
		off.append(d)
		return n0 + base.size() - 1

	## Point x's offset from `p` (its old point) for a width of 1 (an old point: none).
	func of(x: int) -> Vector3:
		return off[x - n0] if x >= n0 else Vector3.ZERO


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "new_points": PackedInt32Array(), "msg": msg}


## The edges of `edge_ids` a fillet can round: shown ones (not a face's diagonal) between two faces.
static func usable_edges(em, edge_ids: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for e in edge_ids:
		if e < 0 or e >= em.edge_count() or seen.has(e):
			continue
		seen[e] = true
		if em.edge_tn[e] != 2 or em.edge_inner[e]:
			continue
		if em.tri_face[em.edge_tris[e * 2]] == em.tri_face[em.edge_tris[e * 2 + 1]]:
			continue
		out.append(e)
	return out


## The (Newell) normal of the outline `lp` (point ids, or offsets with `offs`) - its length twice the area.
static func _newell(pts: PackedVector3Array, lp: PackedInt32Array) -> Vector3:
	var nn := Vector3.ZERO
	for i in lp.size():
		var a := pts[lp[i]]
		var b := pts[lp[(i + 1) % lp.size()]]
		nn += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return nn


## The triangles of outline `lp` (indices into it), in its own turn.
static func _triangulate(pts: PackedVector3Array, lp: PackedInt32Array) -> PackedInt32Array:
	if lp.size() == 3:
		return PackedInt32Array([0, 1, 2])
	var nn := _newell(pts, lp)
	var out := PackedInt32Array()
	if nn.length_squared() < 1e-30:
		for i in range(1, lp.size() - 1):
			out.append_array(PackedInt32Array([0, i, i + 1]))
		return out
	nn = nn.normalized()
	var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := nn.cross(u)
	var p2 := PackedVector2Array()
	for p in lp:
		p2.append(Vector2(pts[p].dot(u), pts[p].dot(w)))
	out = EditMesh.ear_clip(p2)
	if out.size() < 3:
		for i in range(1, lp.size() - 1):
			out.append_array(PackedInt32Array([0, i, i + 1]))
	return out


## `lp` without a point repeated next to itself (`cyclic`: the last and first too).
static func _dedupe(lp: PackedInt32Array, cyclic := true) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x in lp:
		if out.is_empty() or out[out.size() - 1] != x:
			out.append(x)
	while cyclic and out.size() > 1 and out[0] == out[out.size() - 1]:
		out.remove_at(out.size() - 1)
	return out


static func _root(parent: Dictionary, x: int) -> int:
	while parent.has(x):
		x = parent[x]
	return x


static func _remap(parent: Dictionary, lp: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x in lp:
		out.append(_root(parent, x))
	return out


## Point x's vertex in face `f`'s old triangles (`pt`), -1 if none.
static func _vert_in(em, pt: PackedInt32Array, x: int) -> int:
	for t in pt:
		var v: int = em._vert_at(t, x)
		if v >= 0:
			return v
	return -1


## A vertex for point x at `at`, blended from the old face's triangle it's in (`pt`).
static func _blend_in(em, s, pt: PackedInt32Array, at: Vector3, x: int) -> int:
	var best := -INF
	var bw := Vector3(1, 0, 0)
	var bt: int = pt[0]
	for t in pt:
		var w := Geometry3D.get_triangle_barycentric_coords(at, em.points[em.tris[t * 3]], em.points[em.tris[t * 3 + 1]], em.points[em.tris[t * 3 + 2]])
		var m := minf(w.x, minf(w.y, w.z))
		if m > best:
			best = m
			bw = w
			bt = t
	bw = Vector3(maxf(bw.x, 0.0), maxf(bw.y, 0.0), maxf(bw.z, 0.0))
	var sum := bw.x + bw.y + bw.z
	bw = bw / sum if sum > 1e-12 else Vector3(1, 0, 0)
	var i: int = em.tri_at[bt]
	var v: int = s.blend_vertex(PackedInt32Array([s.idx[i], s.idx[i + 1], s.idx[i + 2]]), PackedFloat32Array([bw.x, bw.y, bw.z]), x)
	s.pos[v] = at
	return v


## Fillets edges `edge_ids` of `em` (derived; edited in place, then compacted and derived again):
## `width` how far each side moves back along its face, `segments` the rows of quads across (1: a
## chamfer). Returns {"ok", "new_points" (the strips' and corners' points), "edges" (how many were
## rounded), "width" (as used: held below where corners would pass each other), "faces" (new),
## "msg"}; on failure ("ok" false) the mesh is as it was.
static func fillet(em, edge_ids: PackedInt32Array, width: float, segments: int) -> Dictionary:
	var seg := clampi(segments, 1, MAX_SEGMENTS)
	width = maxf(width, 0.0)
	var es := usable_edges(em, edge_ids)
	if es.is_empty():
		return _fail("no edge between two faces to round")
	var n0: int = em.points.size()
	var pts: PackedVector3Array = em.points.duplicate()
	var st := NewPts.new()
	st.n0 = n0
	var sel := {}
	var ends := {}
	for e in es:
		sel[e] = true
		ends[em.edges[e * 2]] = true
		ends[em.edges[e * 2 + 1]] = true
	# the faces round the ends: their outlines, and which face runs each way along each side
	var face_t := {}    # face -> a triangle of it
	var faces_at := {}  # point -> [faces with it as a corner]
	for p in ends:
		var fl := []
		for t in em.tris_around(p):
			var f: int = em.tri_face[t]
			if not face_t.has(f):
				face_t[f] = t
			if not fl.has(f):
				fl.append(f)
		faces_at[p] = fl
	var loops := {}
	var nrm := {}
	var dedge := {}   # Vector2i(a, b) -> the face going a -> b
	for f in face_t:
		var lp: PackedInt32Array = em.poly_loop(face_t[f])
		if lp.size() < 3:
			return _fail("a face beside the edges isn't one simple outline")
		loops[f] = lp
		nrm[f] = _newell(pts, lp).normalized()
		for i in lp.size():
			var k := Vector2i(lp[i], lp[(i + 1) % lp.size()])
			if dedge.has(k):
				return _fail("the faces beside the edges don't all turn the same way (flipped or non-manifold)")
			dedge[k] = f
	for e in es:
		if not dedge.has(Vector2i(em.edges[e * 2], em.edges[e * 2 + 1])) or not dedge.has(Vector2i(em.edges[e * 2 + 1], em.edges[e * 2])):
			return _fail("an edge's two faces don't turn the same way (flipped normals?)")
	# each face's corner at each end: moved in from the filleted sides
	var around := {}   # Vector2i(f, p) -> Vector2i(the corner before p, the one after)
	var ckind := {}    # Vector2i(f, p) -> 0 no filleted side there, 1 one, 2 both
	var cn := {}       # Vector2i(f, p) -> PackedInt32Array: the points that corner becomes
	var slid := {}     # Vector2i(p, q) -> [offset sum, n]: the point slid from p along the unfilleted side p-q
	var reach := {}    # new point -> how far it can go from its old point (not past the next one's)
	for p in ends:
		for f in faces_at[p]:
			var lp: PackedInt32Array = loops[f]
			var i := lp.find(p)
			var prv := lp[(i + lp.size() - 1) % lp.size()]
			var nxt := lp[(i + 1) % lp.size()]
			var key := Vector2i(f, p)
			around[key] = Vector2i(prv, nxt)
			var s_in := sel.has(em.edge(prv, p))
			var s_out := sel.has(em.edge(p, nxt))
			var n: Vector3 = nrm[f]
			var d1 := (pts[p] - pts[prv]).normalized()
			var d2 := (pts[nxt] - pts[p]).normalized()
			var n1 := n.cross(d1).normalized()   # (into the face from side prv -> p)
			var n2 := n.cross(d2).normalized()
			if s_in and s_out:   # (both sides: in from each by the width)
				var id := st.add(p, (n1 + n2) / maxf(1.0 + n1.dot(n2), 0.1))
				cn[key] = PackedInt32Array([id])
				ckind[key] = 2
				reach[id] = 0.45 * minf(pts[p].distance_to(pts[prv]), pts[p].distance_to(pts[nxt]))
			elif s_in:   # (one: along the other side until the width from it)
				_slide(slid, Vector2i(p, nxt), d2 / maxf(d2.dot(n1), 0.1))
				ckind[key] = 1
			elif s_out:
				_slide(slid, Vector2i(p, prv), -d1 / maxf(-d1.dot(n2), 0.1))
				ckind[key] = 1
			else:
				ckind[key] = 0
	var slide_id := {}
	var on_edge := {}   # slid point -> Vector2i(p, q): the side it's on
	for k: Vector2i in slid:
		var sl: Array = slid[k]
		var id := st.add(k.x, (sl[0] as Vector3) / float(sl[1]))   # (faces either side wanting it a bit apart: between)
		slide_id[k] = id
		on_edge[id] = k
		reach[id] = pts[k.x].distance_to(pts[k.y]) * (0.45 if ends.has(k.y) else 0.9)
	for key: Vector2i in ckind:
		if ckind[key] == 2:
			continue
		var p := key.y
		var pn: Vector2i = around[key]
		var a: int = slide_id.get(Vector2i(p, pn.x), p)
		var b: int = slide_id.get(Vector2i(p, pn.y), p)
		if ckind[key] == 1:
			var e_in := sel.has(em.edge(pn.x, p))
			cn[key] = PackedInt32Array([b if e_in else a])
		else:
			cn[key] = PackedInt32Array([a]) if a == b else PackedInt32Array([a, b])
	# the strips: across each end, an arc from face A's corner (A going a -> b) to face B's
	var rows := {}     # Vector2i(e, p) -> PackedInt32Array, A's corner first
	var radius := {}   # p -> [the arcs' radii there, for a width of 1]
	for e in es:
		var a: int = em.edges[e * 2]
		var b: int = em.edges[e * 2 + 1]
		var fa: int = dedge[Vector2i(a, b)]
		var fb: int = dedge[Vector2i(b, a)]
		for p in [a, b]:
			var q: int = b if p == a else a
			var ca: int = (cn[Vector2i(fa, p)] as PackedInt32Array)[0]
			var cb: int = (cn[Vector2i(fb, p)] as PackedInt32Array)[0]
			var ka := st.of(ca)
			var kb := st.of(cb)
			var ax := (pts[q] - pts[p]).normalized()
			var kk := ax * (0.5 * (ka.dot(ax) + kb.dot(ax)))   # (the arc's corner, on the old edge)
			var va := ka - kk
			var vb := kb - kk
			var phi := va.angle_to(vb)
			var wt := sin(phi * 0.5)   # (a rational curve's weight: a circle's arc)
			var row := PackedInt32Array([ca])
			for j in range(1, seg):
				var t := float(j) / seg
				var u0 := (1.0 - t) * (1.0 - t)
				var u1 := 2.0 * t * (1.0 - t) * wt
				var u2 := t * t
				row.append(st.add(p, (ka * u0 + kk * u1 + kb * u2) / (u0 + u1 + u2)))
			row.append(cb)
			rows[Vector2i(e, p)] = row
			if seg > 1:
				var r := va.length() * tan(minf(phi * 0.5, 1.47))
				if not radius.has(p):
					radius[p] = []
				(radius[p] as Array).append(minf(r, 10.0 * va.length()))
	# the corners: round each end, its faces' new corners and the strips' arcs - welded, joined to
	# a face, or a patch of their own
	var parent := {}   # a welded point -> the one it's now
	var patches := []  # {"pts", "fan", "c", "p", "f0"}
	for p in ends:
		var fl: Array = faces_at[p]
		var start: int = fl[0]
		var closed := false
		var guard := 0
		while true:
			guard += 1
			var g: int = dedge.get(Vector2i(p, (around[Vector2i(start, p)] as Vector2i).x), -1)
			if g < 0:
				break
			start = g
			if start == fl[0]:
				closed = true
				break
			if guard > fl.size():
				return _fail("the faces round a point don't make one fan (a non-manifold point)")
		var order := [start]
		while true:
			var g: int = dedge.get(Vector2i((around[Vector2i(order[order.size() - 1], p)] as Vector2i).y, p), -1)
			if g < 0 or g == start:
				break
			if order.has(g) or not faces_at[p].has(g):
				return _fail("the faces round a point don't make one fan (a non-manifold point)")
			order.append(g)
		if order.size() != fl.size():
			return _fail("the faces round a point don't make one fan (a non-manifold point)")
		var pieces := []   # [0 a face's corner / 1 an arc / 2 the point itself, points, face]
		for i in order.size():
			var f: int = order[i]
			pieces.append([0, cn[Vector2i(f, p)], f])
			if i < order.size() - 1 or closed:
				var nx: int = (around[Vector2i(f, p)] as Vector2i).y
				var e: int = em.edge(p, nx)
				if sel.has(e):
					var row: PackedInt32Array = rows[Vector2i(e, p)]
					var inner := row.slice(1, row.size() - 1)
					if em.edges[e * 2] != p:
						inner.reverse()
					pieces.append([1, inner, -1])
		if not closed:
			pieces.append([2, PackedInt32Array([p]), -1])
		var cyc := PackedInt32Array()
		for pc in pieces:
			cyc.append_array(pc[1])
		cyc = _dedupe(cyc)
		if cyc.size() < 3:
			continue
		var arcs := []
		var corner_pts := {}
		var chords := []
		for pc in pieces:
			if pc[0] == 1:
				if not (pc[1] as PackedInt32Array).is_empty():
					arcs.append(pc[1])
				continue
			for x in pc[1]:
				corner_pts[x] = true
			if pc[0] == 0 and ckind[Vector2i(pc[2], p)] == 0 and (pc[1] as PackedInt32Array).size() >= 2:
				chords.append(pc)
		if arcs.size() == 2 and corner_pts.size() == 2 and (arcs[0] as PackedInt32Array).size() == (arcs[1] as PackedInt32Array).size():
			# two arcs between the same two corners (nothing else there): one, halfway between
			var a1: PackedInt32Array = arcs[0]
			var a2: PackedInt32Array = arcs[1]
			for k in a1.size():
				var keep := a1[a1.size() - 1 - k]
				st.off[keep - n0] = (st.of(keep) + st.of(a2[k])) * 0.5
				parent[a2[k]] = keep
			continue
		if chords.size() == 1:
			# one face across the end with its corner cut: the arc joins it if it lies in it
			var f: int = chords[0][2]
			var fnrm: Vector3 = nrm[f]
			var flat := true
			for x in cyc:
				if absf(st.of(x).dot(fnrm)) > 1e-4 * maxf(st.of(x).length(), 1.0):
					flat = false
					break
			if flat:
				var at := pieces.find(chords[0])
				var rest := PackedInt32Array()
				for k in range(1, pieces.size()):
					rest.append_array(pieces[(at + k) % pieces.size()][1])
				rest.reverse()
				var mine: PackedInt32Array = chords[0][1]
				var lst := PackedInt32Array([mine[0]])
				lst.append_array(rest)
				lst.append(mine[mine.size() - 1])
				cn[Vector2i(f, p)] = _dedupe(lst, false)
				continue
		# a patch of its own: flat - one face; else a fan rounded out towards the old corner
		var poly := cyc.duplicate()
		poly.reverse()
		var offs := PackedVector3Array()
		var c0 := Vector3.ZERO
		for x in poly:
			offs.append(st.of(x))
			c0 += st.of(x)
		c0 /= poly.size()
		var ids := PackedInt32Array()
		for k in poly.size():
			ids.append(k)
		var pn := _newell(offs, ids)
		var size := 0.0
		for o in offs:
			size = maxf(size, (o - c0).length())
		var planar := pn.length_squared() > 1e-20
		if planar:
			pn = pn.normalized()
			for o in offs:
				if absf((o - c0).dot(pn)) > 1e-3 * maxf(size, 1e-9):
					planar = false
					break
		var c := -1
		if not planar:
			var rho := 0.0
			for o in offs:
				rho += (o - c0).length()
			rho /= offs.size()
			var r := 0.0
			for x in radius.get(p, []):
				r += x
			r = r / (radius[p] as Array).size() if radius.has(p) else 0.0
			var sag := (r - sqrt(maxf(r * r - rho * rho, 0.0))) if r > 0.0 else 0.0
			var out := -c0.normalized() if c0.length() > 1e-9 else pn.normalized()
			c = st.add(p, c0 + out * minf(sag, r))
		patches.append({"pts": poly, "fan": not planar, "c": c, "p": p, "f0": order[0]})
	# no wider than the faces allow (corners moved past each other would fold the faces over)
	var asked := width
	for id in reach:
		var l := st.of(id).length()
		if l > 1e-9:
			width = minf(width, float(reach[id]) / l)
	# the points where they end up
	pts.resize(n0 + st.base.size())
	for k in st.base.size():
		pts[n0 + k] = pts[st.base[k]] + st.off[k] * width
	# the outlines: faces changed, strips, patches (welded points as the ones they went into)
	var faces := []   # [face, outline]
	for f in loops:
		var lp: PackedInt32Array = loops[f]
		var out := PackedInt32Array()
		var changed := false
		for p in lp:
			if not ends.has(p):
				out.append(p)
				continue
			var cc: PackedInt32Array = cn[Vector2i(f, p)]
			if cc.size() != 1 or cc[0] != p:
				changed = true
			out.append_array(_remap(parent, cc))
		if changed:
			faces.append([f, _dedupe(out)])
	var used := {}   # Vector2i(a, b) of the faces and strips (a patch turned to fit them)
	for fo in faces:
		var lp: PackedInt32Array = fo[1]
		for i in lp.size():
			used[Vector2i(lp[i], lp[(i + 1) % lp.size()])] = true
	for e in es:
		var ra: PackedInt32Array = _remap(parent, rows[Vector2i(e, em.edges[e * 2])])
		var rb: PackedInt32Array = _remap(parent, rows[Vector2i(e, em.edges[e * 2 + 1])])
		for j in seg:
			for pair in [[rb[j], ra[j]], [ra[j], ra[j + 1]], [ra[j + 1], rb[j + 1]], [rb[j + 1], rb[j]]]:
				used[Vector2i(pair[0], pair[1])] = true
	for pa: Dictionary in patches:
		var poly := _remap(parent, pa["pts"])
		var good := 0
		var bad := 0
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if used.has(Vector2i(a, b)):
				bad += 1
			elif used.has(Vector2i(b, a)):
				good += 1
		if bad > good:
			poly.reverse()
		pa["pts"] = _dedupe(poly)
	# the surfaces: the changed faces' old triangles out, new ones in
	em.points = pts
	var kill := {}    # surface -> {old triangle's first index: true}
	var memo := {}    # a new point's vertex, shared where the faces either side share theirs
	var fverts := {}  # Vector2i(face, point) -> its vertex
	var anyv := {}    # Vector2i(surface, point) -> a vertex of it
	var olds := {}    # face -> its old triangles
	var next: int = em.face_n
	var touched := {}
	var made := 0
	for fo in faces:
		var f: int = fo[0]
		var lp: PackedInt32Array = fo[1]
		var t0: int = face_t[f]
		var si: int = em.tri_surf[t0]
		var s = em.surfs[si]
		touched[si] = true
		var pt: PackedInt32Array = em.poly_tris(t0)
		olds[f] = pt
		if not kill.has(si):
			kill[si] = {}
		var pmap := {}
		for t in pt:
			(kill[si] as Dictionary)[em.tri_at[t]] = true
			for k in 3:
				var v: int = s.idx[em.tri_at[t] + k]
				pmap[s.vp[v]] = v
		if lp.size() < 3:
			continue
		var vl := PackedInt32Array()
		for x in lp:
			var v := -1
			if pmap.has(x):
				v = pmap[x]
			elif on_edge.has(x) and pmap.has((on_edge[x] as Vector2i).x) and pmap.has((on_edge[x] as Vector2i).y):
				var ab: Vector2i = on_edge[x]
				var va: int = pmap[ab.x]
				var vb: int = pmap[ab.y]
				var key := Vector4i(si, mini(va, vb), maxi(va, vb), x)
				v = memo.get(key, -1)
				if v < 0:
					var l := pts[ab.y].distance_to(pts[ab.x])
					var fr := clampf(pts[x].distance_to(pts[ab.x]) / maxf(l, 1e-12), 0.0, 1.0)
					v = s.blend_vertex(PackedInt32Array([va, vb]), PackedFloat32Array([1.0 - fr, fr]), x)
					s.pos[v] = pts[x]
					memo[key] = v
			else:
				var key := Vector4i(si, -1, f, x)
				v = memo.get(key, -1)
				if v < 0:
					v = _blend_in(em, s, pt, pts[x], x)
					memo[key] = v
			vl.append(v)
			fverts[Vector2i(f, x)] = v
			anyv[Vector2i(si, x)] = v
		var tr := _triangulate(pts, lp)
		for k in range(0, tr.size(), 3):
			s.idx.append_array(PackedInt32Array([vl[tr[k]], vl[tr[k + 1]], vl[tr[k + 2]]]))
			s.face.append(f)
	for e in es:
		var a: int = em.edges[e * 2]
		var b: int = em.edges[e * 2 + 1]
		var fa: int = dedge[Vector2i(a, b)]
		var fb: int = dedge[Vector2i(b, a)]
		var si: int = em.tri_surf[face_t[fa]]
		var s = em.surfs[si]
		touched[si] = true
		var same: bool = em.tri_surf[face_t[fb]] == si
		var vr := {}
		for p in [a, b]:
			var row := _remap(parent, rows[Vector2i(e, p)])
			var va: int = fverts.get(Vector2i(fa, row[0]), -1)
			if va < 0:
				va = _vert_in(em, olds.get(fa, em.poly_tris(face_t[fa])), p)
			var vb: int = fverts.get(Vector2i(fb, row[seg]), -1) if same else -1
			for j in seg + 1:
				var x := row[j]
				var t := float(j) / seg
				var v: int
				if vb >= 0:
					v = s.blend_vertex(PackedInt32Array([va, vb]), PackedFloat32Array([1.0 - t, t]), x)
				else:
					v = s.copy_vertex(va, x)
				s.pos[v] = pts[x]
				vr[Vector2i(p, j)] = v
				if not anyv.has(Vector2i(si, x)):
					anyv[Vector2i(si, x)] = v
		var ra := _remap(parent, rows[Vector2i(e, a)])
		var rb := _remap(parent, rows[Vector2i(e, b)])
		for j in seg:
			var qp := [rb[j], ra[j], ra[j + 1], rb[j + 1]]
			var qv := [vr[Vector2i(b, j)], vr[Vector2i(a, j)], vr[Vector2i(a, j + 1)], vr[Vector2i(b, j + 1)]]
			var lp := PackedInt32Array()
			var lv := PackedInt32Array()
			for k in 4:
				if not lp.has(qp[k]):
					lp.append(qp[k])
					lv.append(qv[k])
			if lp.size() < 3:
				continue
			for k in range(1, lp.size() - 1):
				s.idx.append_array(PackedInt32Array([lv[0], lv[k], lv[k + 1]]))
				s.face.append(next)
			next += 1
			made += 1
	for pa: Dictionary in patches:
		var poly: PackedInt32Array = pa["pts"]
		if poly.size() < 3:
			continue
		var f0: int = pa["f0"]
		var si: int = em.tri_surf[face_t[f0]]
		var s = em.surfs[si]
		touched[si] = true
		var fallback := _vert_in(em, olds.get(f0, em.poly_tris(face_t[f0])), int(pa["p"]))
		var vl := PackedInt32Array()
		for x in poly:
			var from: int = anyv.get(Vector2i(si, x), fallback)
			var v: int = s.copy_vertex(maxi(from, 0), x)
			s.pos[v] = pts[x]
			vl.append(v)
		if pa["fan"]:
			var c: int = pa["c"]
			var w := PackedFloat32Array()
			w.resize(vl.size())
			w.fill(1.0 / vl.size())
			var vc: int = s.blend_vertex(vl, w, c)
			s.pos[vc] = pts[c]
			for k in poly.size():
				s.idx.append_array(PackedInt32Array([vc, vl[k], vl[(k + 1) % vl.size()]]))
				s.face.append(next)
				next += 1
				made += 1
		else:
			var tr := _triangulate(pts, poly)
			for k in range(0, tr.size(), 3):
				s.idx.append_array(PackedInt32Array([vl[tr[k]], vl[tr[k + 1]], vl[tr[k + 2]]]))
				s.face.append(next)
			next += 1
			made += 1
	for si in kill:
		(em.surfs[si]).drop_tris(kill[si])
	for si in touched:
		(em.surfs[si]).recalc_normals()
	# old points left with no face (a box's corner) dropped, the rest renumbered
	var usedp := PackedByteArray()
	usedp.resize(pts.size())
	for s in em.surfs:
		s.compact()
		for p in s.vp:
			usedp[p] = 1
	var map := PackedInt32Array()
	map.resize(pts.size())
	var k2 := 0
	for p in pts.size():
		map[p] = k2 if usedp[p] else -1
		k2 += usedp[p]
	em.compact()
	em.derive()
	var news := PackedInt32Array()
	for k in st.base.size():
		if map[n0 + k] >= 0:
			news.append(map[n0 + k])
	return {"ok": true, "new_points": news, "edges": es.size(), "faces": made, "width": width,
		"msg": "%d edge%s rounded, %d segment%s%s" % [es.size(), "" if es.size() == 1 else "s", seg, "" if seg == 1 else "s",
			(", the width held to %s by the faces' size" % String.num(width, 4)) if width < asked - 1e-9 else ""]}


static func _slide(slid: Dictionary, k: Vector2i, d: Vector3) -> void:
	if slid.has(k):
		slid[k][0] += d
		slid[k][1] += 1
	else:
		slid[k] = [d, 1]
