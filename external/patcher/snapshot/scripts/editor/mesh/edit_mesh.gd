extends RefCounted
## The mesh editor's working copy of one part's mesh (its edit mode): every
## triangle surface's vertex arrays (positions, normals, colours, UVs and, on a
## skinned mesh, the bones and weights - kept through every edit), and over them
## the *points*: vertices at the same place welded into one (a UV seam or a hard
## edge splits a vertex in the arrays; you see and select one). Edits move points
## (each moves its vertices with it) or change the topology (extrude, delete,
## merge, subdivide, the knife), then derive() works out the triangles, edges and
## neighbours again (the knife patches them where it cut instead).
## Over the triangles, the *faces* (n-gons): each triangle has a face id (Surf.face),
## the triangles of one face are edge-joined and flat; the edges inside a face (its
## triangulation's diagonals) aren't shown. A model read from a file has its faces
## found again: flat triangles paired into quads (squarest first), then joined into
## n-gons along the flat face's rim (no corner made straight, none left inside).
##   var em := EditMesh.from_mesh(part.mesh)       # (or build() on a worker, then derive())
##   em.points[i] = ...; em.sync(ids); em.update_mesh()
## Plain data: no nodes, so it can be built on a worker thread. (Packed arrays
## are shared by reference: snapshots copy them; derived arrays are never changed
## in place - made anew, or copied first - so snapshots keep them as they are.)

## A vertex in a point's list: (surface << SHIFT) | vertex.
const SHIFT := 24
const VMASK := (1 << SHIFT) - 1
## An edge's key in edge_of: a * KEY + b (a < b) - the same however many points are added.
const KEY := 1 << 32
## Triangles this close to parallel (cos 1°) are one flat face; a corner this straight (179°) isn't one.
const COPLANAR := 0.99985
const STRAIGHT := -0.99985
## The faces last edited of each mesh (instance id -> [WeakRef, faces per surface]): editing it
## again finds its faces as you left them, not guessed again from the triangles.
static var _kept := {}
static var _kept_lock := Mutex.new()
## Falloffs of proportional editing (the weight at distance d of radius r).
const FALLOFFS := ["smooth", "sphere", "root", "linear", "sharp", "constant"]
## The 26 cells around one.
static var _AROUND: Array = _around()

static func _around() -> Array:
	var out := []
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if x != 0 or y != 0 or z != 0:
					out.append(Vector3i(x, y, z))
	return out

var surfs: Array = []            # Surf, the triangle surfaces
var other: Array = []            # [primitive, arrays, flags, material, name] - non-triangle surfaces, kept as they are
var points := PackedVector3Array()
# Derived (derive()):
var tris := PackedInt32Array()       # 3 points a triangle - surfaces in order, as Mesh.get_faces() lists them
var tri_surf := PackedInt32Array()   # triangle -> its surface
var tri_at := PackedInt32Array()     # triangle -> its first index in the surface's index array
var edges := PackedInt32Array()      # 2 points an edge (a < b)
var edge_of := {}                    # a * n + b -> edge
var pv_start := PackedInt32Array()   # point -> its vertices: pv[pv_start[p] .. pv_start[p + 1]]
var pv := PackedInt32Array()
var adj_start := PackedInt32Array()  # point -> its neighbours: adj[adj_start[p] .. adj_start[p + 1]]
var adj := PackedInt32Array()
var tri_face := PackedInt32Array()   # triangle -> its face (0 .. face_n - 1 after derive())
var tri_edges := PackedInt32Array()  # 3 edges a triangle (edge k: corner k -> k + 1; -1: none)
var edge_tris := PackedInt32Array()  # 2 triangles an edge (-1: none)
var edge_tn := PackedInt32Array()    # how many triangles use an edge
var edge_more := {}                  # edge -> its third triangle and on (a non-manifold edge): PackedInt32Array
var edge_inner := PackedByteArray()  # 1: an edge inside a face (a diagonal of its triangles - not shown)
var face_n := 0                       # (the next face id: ids below it, some unused after a dissolve)
var face_live := 0                    # how many faces
var _wire := PackedInt32Array()
var _wire_topo := -1
var _eps_topo := -1
var _eps := 1e-7
## Points dissolved, left with no triangle (compact() drops them; edit mode does when it ends).
var unused := false
## Which topology the derived arrays describe (snapshots with the same one restore without derive()).
var topo := 0
static var _topo_ids := 0
## The mesh shown (update_mesh() refills it).
var mesh := ArrayMesh.new()


## One triangle surface, its vertex attributes as typed arrays.
class Surf extends RefCounted:
	var name := ""
	var material: Material
	var flags := 0
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var nb := 0                       # bones a vertex (0: not skinned)
	var idx := PackedInt32Array()
	var vp := PackedInt32Array()      # vertex -> point
	var face := PackedInt32Array()    # triangle (idx / 3) -> its face (-1: to be found from the shape)

	func count() -> int:
		return pos.size()

	func copy() -> Surf:
		var s := Surf.new()
		s.name = name
		s.material = material
		s.flags = flags
		s.pos = pos.duplicate()
		s.nrm = nrm.duplicate()
		s.col = col.duplicate()
		s.uv = uv.duplicate()
		s.uv2 = uv2.duplicate()
		s.bones = bones.duplicate()
		s.weights = weights.duplicate()
		s.nb = nb
		s.idx = idx.duplicate()
		s.vp = vp.duplicate()
		s.face = face.duplicate()
		return s

	func bytes() -> int:
		return pos.size() * 36 + col.size() * 16 + (uv.size() + uv2.size()) * 8 + (bones.size() + weights.size()) * 4 + idx.size() * 4 + face.size() * 4

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = pos
		a[Mesh.ARRAY_NORMAL] = nrm
		if not col.is_empty():
			a[Mesh.ARRAY_COLOR] = col
		if not uv.is_empty():
			a[Mesh.ARRAY_TEX_UV] = uv
		if not uv2.is_empty():
			a[Mesh.ARRAY_TEX_UV2] = uv2
		if nb > 0:
			a[Mesh.ARRAY_BONES] = bones
			a[Mesh.ARRAY_WEIGHTS] = weights
		a[Mesh.ARRAY_INDEX] = idx
		return a

	## Appends a copy of vertex `v` (all its attributes) as point `point`; its index.
	func copy_vertex(v: int, point: int) -> int:
		pos.append(pos[v])
		nrm.append(nrm[v])
		if not col.is_empty():
			col.append(col[v])
		if not uv.is_empty():
			uv.append(uv[v])
		if not uv2.is_empty():
			uv2.append(uv2[v])
		for k in nb:
			bones.append(bones[v * nb + k])
			weights.append(weights[v * nb + k])
		vp.append(point)
		return pos.size() - 1

	## Appends the vertex halfway between `a` and `b` (attributes mixed; the
	## bone weights of both, the strongest kept) as point `point`.
	func mix_vertex(a: int, b: int, point: int) -> int:
		return blend_vertex(PackedInt32Array([a, b]), PackedFloat32Array([0.5, 0.5]), point)

	## Appends a vertex mixed from vertices `vs`, each `ws` of it (the weights add up to 1):
	## position, normal (smooth where theirs is), colour, UVs, and the bone weights of all
	## of them (the strongest kept) - as point `point`.
	func blend_vertex(vs: PackedInt32Array, ws: PackedFloat32Array, point: int) -> int:
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var c := Color(0, 0, 0, 0)
		var u := Vector2.ZERO
		var u2 := Vector2.ZERO
		for i in vs.size():
			var v := vs[i]
			var f := ws[i]
			p += pos[v] * f
			n += nrm[v] * f
			if not col.is_empty():
				c += col[v] * f
			if not uv.is_empty():
				u += uv[v] * f
			if not uv2.is_empty():
				u2 += uv2[v] * f
		pos.append(p)
		nrm.append(n.normalized() if n.length_squared() > 1e-20 else nrm[vs[0]])
		if not col.is_empty():
			col.append(c)
		if not uv.is_empty():
			uv.append(u)
		if not uv2.is_empty():
			uv2.append(u2)
		if nb > 0:
			var w := {}
			for i in vs.size():
				var v := vs[i]
				for k in nb:
					var wt: float = weights[v * nb + k]
					if wt > 0.0:
						var bn: int = bones[v * nb + k]
						w[bn] = w.get(bn, 0.0) + wt * ws[i]
			var ks: Array = w.keys()
			ks.sort_custom(func(x, y): return w[x] > w[y])
			var total := 0.0
			for k in mini(nb, ks.size()):
				total += w[ks[k]]
			for k in nb:
				if k < ks.size() and total > 0.0:
					bones.append(ks[k])
					weights.append(w[ks[k]] / total)
				else:
					bones.append(0)
					weights.append(0.0)
		vp.append(point)
		return pos.size() - 1

	## Positions from the points: every vertex (`only` empty) or those listed.
	func sync(points: PackedVector3Array, only: PackedInt32Array) -> void:
		if only.is_empty():
			for v in pos.size():
				pos[v] = points[vp[v]]
		else:
			for v in only:
				pos[v] = points[vp[v]]

	## Shading normals from the faces (area-weighted; a vertex split in the
	## arrays - a hard edge - keeps its sides apart).
	func recalc_normals() -> void:
		var n := PackedVector3Array()
		n.resize(pos.size())
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			var fn := (pos[a] - pos[c]).cross(pos[a] - pos[b])
			n[a] += fn
			n[b] += fn
			n[c] += fn
		for v in n.size():
			var l := n[v].length()
			n[v] = n[v] / l if l > 1e-12 else Vector3.UP
		nrm = n

	## Drops the vertices no triangle uses (indices remapped).
	func compact() -> void:
		var used := PackedInt32Array()
		used.resize(pos.size())
		used.fill(-1)
		var order := PackedInt32Array()
		for i in idx.size():
			var v := idx[i]
			if used[v] < 0:
				used[v] = order.size()
				order.append(v)
			idx[i] = used[v]
		if order.size() == pos.size():
			var same := true
			for k in order.size():
				if order[k] != k:
					same = false
					break
			if same:
				return
		var p2 := PackedVector3Array(); var n2 := PackedVector3Array(); var c2 := PackedColorArray()
		var u2 := PackedVector2Array(); var uu2 := PackedVector2Array(); var b2 := PackedInt32Array()
		var w2 := PackedFloat32Array(); var vp2 := PackedInt32Array()
		for v in order:
			p2.append(pos[v])
			n2.append(nrm[v])
			if not col.is_empty():
				c2.append(col[v])
			if not uv.is_empty():
				u2.append(uv[v])
			if not uv2.is_empty():
				uu2.append(uv2[v])
			for k in nb:
				b2.append(bones[v * nb + k])
				w2.append(weights[v * nb + k])
			vp2.append(vp[v])
		pos = p2; nrm = n2; col = c2; uv = u2; uv2 = uu2; bones = b2; weights = w2; vp = vp2

	## Points renumbered (`map`: old -> new).
	func remap_points(map: PackedInt32Array) -> void:
		for v in vp.size():
			vp[v] = map[vp[v]]

	## Triangles whose corners aren't three different points dropped.
	func drop_degenerate() -> void:
		var ni := PackedInt32Array()
		var nf := PackedInt32Array()
		var has_f := face.size() == idx.size() / 3
		for i in range(0, idx.size() - 2, 3):
			var a := vp[idx[i]]
			var b := vp[idx[i + 1]]
			var c := vp[idx[i + 2]]
			if a != b and b != c and a != c:
				ni.append(idx[i]); ni.append(idx[i + 1]); ni.append(idx[i + 2])
				nf.append(face[i / 3] if has_f else -1)
		idx = ni
		face = nf

	## Drops the triangles starting at the indices in `kill`.
	func drop_tris(kill: Dictionary) -> void:
		var ni := PackedInt32Array()
		var nf := PackedInt32Array()
		var has_f := face.size() == idx.size() / 3
		for i in range(0, idx.size() - 2, 3):
			if not kill.has(i):
				ni.append(idx[i]); ni.append(idx[i + 1]); ni.append(idx[i + 2])
				nf.append(face[i / 3] if has_f else -1)
		idx = ni
		face = nf

	## The vertices of the points flagged become point `target` at `at`.
	func merge_points(flag: PackedByteArray, target: int, at: Vector3) -> void:
		for v in vp.size():
			if flag[vp[v]]:
				vp[v] = target
				pos[v] = at

	## Mirror across `axis`: every vertex copied (`pm`: point -> its twin; itself
	## on the seam, where the vertex is shared), the copies' faces turned round.
	## True if any vertex was on the seam. (The copies' faces: `foff` added to the ids.)
	## (`bones`: each bone's twin - an arm's copy weighted to the other arm; empty: the same bones.)
	func mirror(pm: PackedInt32Array, points: PackedVector3Array, axis: int, clip: bool, foff := 0, bones_twin := PackedInt32Array()) -> bool:
		var nv := count()
		var vm := PackedInt32Array()
		vm.resize(nv)
		var seam := false
		for v in nv:
			var p := vp[v]
			if pm[p] == p:
				vm[v] = v
				seam = true
				if clip:
					var q := pos[v]
					q[axis] = 0.0
					pos[v] = q
			else:
				var c := copy_vertex(v, pm[p])
				pos[c] = points[pm[p]]
				var nn := nrm[v]
				nn[axis] = -nn[axis]
				nrm[c] = nn
				if not bones_twin.is_empty():
					for k in nb:
						var bn := bones[c * nb + k]
						if bn >= 0 and bn < bones_twin.size():
							bones[c * nb + k] = bones_twin[bn]
				vm[v] = c
		var ni := idx.size()
		if face.size() != ni / 3:
			face.resize(ni / 3)
			face.fill(-1)
		for i in range(0, ni, 3):
			idx.append(vm[idx[i]])
			idx.append(vm[idx[i + 2]])
			idx.append(vm[idx[i + 1]])
			face.append(face[i / 3] + foff if face[i / 3] >= 0 else -1)
		return seam

	## Extrudes the triangles starting at `starts`: their corners moved to the
	## points' copies (`np`), walls along the region's border (`border`: the
	## edges - keys a * n0 + b - used by one triangle of the region), each wall a
	## face of its own (ids from `next`). Returns the next free face id.
	func extrude(starts: PackedInt32Array, np: PackedInt32Array, border: Dictionary, n0: int, next := 0) -> int:
		var vm := {}
		for i0 in starts:
			var ov := [idx[i0], idx[i0 + 1], idx[i0 + 2]]
			for k in 3:
				var v: int = ov[k]
				if not vm.has(v):
					vm[v] = copy_vertex(v, np[vp[v]])
				idx[i0 + k] = vm[v]
			for k in 3:
				var va: int = ov[k]
				var vb: int = ov[(k + 1) % 3]
				var a := vp[va]
				var b := vp[vb]
				if border.get(mini(a, b) * n0 + maxi(a, b), 0) != 1:
					continue
				var wa := copy_vertex(va, a)
				var wb := copy_vertex(vb, b)
				var wa2 := copy_vertex(va, np[a])
				var wb2 := copy_vertex(vb, np[b])
				idx.append_array(PackedInt32Array([wa, wb, wb2, wa, wb2, wa2]))
				face.append(next)
				face.append(next)
				next += 1
		return next

	## Splits every triangle with an edge in `mid` (key a * n0 + b -> the new
	## middle point): one edge - in two, two - in three (both still in their face:
	## it gets a corner more), all - in four (their faces found again: -1).
	func subdivide(mid: Dictionary, n0: int, points: PackedVector3Array) -> void:
		var vmid := {}
		var old := idx
		var ni := PackedInt32Array()
		var nf := PackedInt32Array()
		var has_f := face.size() == old.size() / 3
		for i in range(0, old.size() - 2, 3):
			var f: int = face[i / 3] if has_f else -1
			var n_before := ni.size()
			var v := [old[i], old[i + 1], old[i + 2]]
			var m := [-1, -1, -1]   # the middle of edge k (v[k] -> v[k + 1])
			var split := 0
			for k in 3:
				var va: int = v[k]
				var vb: int = v[(k + 1) % 3]
				var a := vp[va]
				var b := vp[vb]
				var key := mini(a, b) * n0 + maxi(a, b)
				if mid.has(key):
					var vk := Vector2i(mini(va, vb), maxi(va, vb))
					if not vmid.has(vk):
						var c := mix_vertex(va, vb, mid[key])
						pos[c] = points[mid[key]]
						vmid[vk] = c
					m[k] = vmid[vk]
					split += 1
			match split:
				0:
					ni.append_array(PackedInt32Array(v))
				3:
					ni.append_array(PackedInt32Array([v[0], m[0], m[2], m[0], v[1], m[1], m[2], m[1], v[2], m[0], m[1], m[2]]))
				1:
					var k := 0
					while m[k] < 0:
						k += 1
					var x: int = v[k]; var y: int = v[(k + 1) % 3]; var z: int = v[(k + 2) % 3]
					ni.append_array(PackedInt32Array([x, m[k], z, m[k], y, z]))
				2:
					var k: int = m.find(-1)   # the edge not split, v[k] -> v[k + 1]: turned to be z -> x
					var x: int = v[(k + 1) % 3]; var y: int = v[(k + 2) % 3]; var z: int = v[k]
					var m1: int = m[(k + 1) % 3]; var m2: int = m[(k + 2) % 3]
					ni.append_array(PackedInt32Array([m1, y, m2, x, m1, m2, x, m2, z]))
			for j in (ni.size() - n_before) / 3:
				nf.append(-1 if split == 3 else f)
		idx = ni
		face = nf

	## The triangles starting at `starts` turned round, their vertices' normals too.
	func flip(starts: PackedInt32Array) -> void:
		var f := PackedByteArray()
		f.resize(count())
		for i in starts:
			var b := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = b
			for k in 3:
				f[idx[i + k]] = 1
		for v in count():
			if f[v]:
				nrm[v] = -nrm[v]


## The editable copy of `m` (welded and derived) - on the calling thread.
static func from_mesh(m: Mesh) -> RefCounted:
	var em = load("res://scripts/editor/mesh/edit_mesh.gd").new()
	em.build(m)
	em.derive()
	return em


## The faces `m`'s triangle surfaces had when it was last edited ([] - none kept).
static func kept_faces(m: Mesh) -> Array:
	if m == null:
		return []
	_kept_lock.lock()
	var k: Array = _kept.get(m.get_instance_id(), [])
	_kept_lock.unlock()
	if k.is_empty() or (k[0] as WeakRef).get_ref() != m:
		return []
	return k[1]


static func _keep_faces(m: Mesh, faces: Array) -> void:
	_kept_lock.lock()
	if _kept.size() > 64:
		for id in _kept.keys():
			if (_kept[id][0] as WeakRef).get_ref() == null:
				_kept.erase(id)
	_kept[m.get_instance_id()] = [weakref(m), faces]
	_kept_lock.unlock()


## Reads `m`'s surfaces and welds their vertices into points.
func build(m: Mesh) -> void:
	surfs = []
	other = []
	points = PackedVector3Array()
	if m == null:
		return
	var kept := kept_faces(m)
	var at := {}   # position -> point
	for i in m.get_surface_count():
		var a: Array = m.surface_get_arrays(i)
		var prim := Mesh.PRIMITIVE_TRIANGLES
		var flags := 0
		if m is ArrayMesh:
			prim = (m as ArrayMesh).surface_get_primitive_type(i)
			flags = (m as ArrayMesh).surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var mat: Material = m.surface_get_material(i)
		var nm: String = (m as ArrayMesh).surface_get_name(i) if m is ArrayMesh else ""
		if prim != Mesh.PRIMITIVE_TRIANGLES or a[Mesh.ARRAY_VERTEX] == null:
			other.append([prim, a, flags, mat, nm])
			continue
		var s := Surf.new()
		s.name = nm
		s.material = mat
		s.flags = flags
		s.pos = a[Mesh.ARRAY_VERTEX]
		var nv := s.pos.size()
		s.nrm = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		if a[Mesh.ARRAY_COLOR] != null:
			s.col = a[Mesh.ARRAY_COLOR]
		if a[Mesh.ARRAY_TEX_UV] != null:
			s.uv = a[Mesh.ARRAY_TEX_UV]
		if a[Mesh.ARRAY_TEX_UV2] != null:
			s.uv2 = a[Mesh.ARRAY_TEX_UV2]
		if a[Mesh.ARRAY_BONES] != null and a[Mesh.ARRAY_WEIGHTS] != null and nv > 0:
			var bn = a[Mesh.ARRAY_BONES]
			s.bones = bn if bn is PackedInt32Array else PackedInt32Array(bn)
			var wt = a[Mesh.ARRAY_WEIGHTS]
			s.weights = wt if wt is PackedFloat32Array else PackedFloat32Array(wt)
			s.nb = s.bones.size() / nv
			s.flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if s.nb == 8 else 0
		var idx := PackedInt32Array()
		if a[Mesh.ARRAY_INDEX] != null:
			idx = a[Mesh.ARRAY_INDEX]
		else:
			idx.resize(nv - nv % 3)
			for k in idx.size():
				idx[k] = k
		s.idx = idx
		var vp := PackedInt32Array()
		vp.resize(nv)
		var pos := s.pos
		for v in nv:
			var p: Vector3 = pos[v]
			var id: int = at.get(p, -1)
			if id < 0:
				id = points.size()
				at[p] = id
				points.append(p)
			vp[v] = id
		s.vp = vp
		if s.nrm.size() != nv:
			s.recalc_normals()
		s.drop_degenerate()   # (triangles with two corners at one point - a sphere's poles: no face, nothing drawn)
		var ks := surfs.size()
		if ks < kept.size() and (kept[ks] as PackedInt32Array).size() == s.idx.size() / 3:
			s.face = (kept[ks] as PackedInt32Array).duplicate()
		surfs.append(s)


## Works out the triangles, edges, neighbours and faces from the surfaces (the
## triangles of no face yet - a mesh just read, a subdivision's - grouped into faces).
func derive() -> void:
	var n := points.size()
	tris = PackedInt32Array()
	tri_surf = PackedInt32Array()
	tri_at = PackedInt32Array()
	tri_face = PackedInt32Array()
	var ungrouped := false
	var count := PackedInt32Array()
	count.resize(n + 1)
	for si in surfs.size():
		var s: Surf = surfs[si]
		var vp := s.vp
		var idx := s.idx
		var nt := idx.size() / 3
		if s.face.size() != nt:
			s.face = PackedInt32Array()
			s.face.resize(nt)
			s.face.fill(-1)
		var face := s.face
		for i in range(0, nt * 3, 3):
			tris.append(vp[idx[i]])
			tris.append(vp[idx[i + 1]])
			tris.append(vp[idx[i + 2]])
			tri_surf.append(si)
			tri_at.append(i)
			var f := face[i / 3]
			tri_face.append(f)
			if f < 0:
				ungrouped = true
		for v in vp:
			count[v + 1] += 1
	# point -> vertices (counting sort)
	for p in n:
		count[p + 1] += count[p]
	pv_start = count.duplicate()
	pv = PackedInt32Array()
	pv.resize(count[n])
	var fill := count.duplicate()
	for si in surfs.size():
		var vp: PackedInt32Array = surfs[si].vp
		for v in vp.size():
			var p := vp[v]
			pv[fill[p]] = (si << SHIFT) | v
			fill[p] += 1
	# edges, and the triangles each one has
	edges = PackedInt32Array()
	edge_of = {}
	edge_tris = PackedInt32Array()
	edge_tn = PackedInt32Array()
	edge_more = {}
	tri_edges = PackedInt32Array()
	tri_edges.resize(tris.size())
	var deg := PackedInt32Array()
	deg.resize(n + 1)
	for i in tris.size():
		var t := i / 3
		var a := tris[i]
		var b := tris[i + 1 if i % 3 != 2 else i - 2]
		if a == b:
			tri_edges[i] = -1
			continue
		if a > b:
			var tmp := a; a = b; b = tmp
		var key := a * KEY + b
		var e: int = edge_of.get(key, -1)
		if e < 0:
			e = edges.size() / 2
			edge_of[key] = e
			edges.append(a)
			edges.append(b)
			edge_tris.append(t)
			edge_tris.append(-1)
			edge_tn.append(1)
			deg[a + 1] += 1
			deg[b + 1] += 1
		else:
			if edge_tn[e] == 1:
				edge_tris[e * 2 + 1] = t
			else:
				_nb(edge_more, e, t)
			edge_tn[e] += 1
		tri_edges[i] = e
	for p in n:
		deg[p + 1] += deg[p]
	adj_start = deg.duplicate()
	adj = PackedInt32Array()
	adj.resize(deg[n])
	fill = deg
	for e in range(0, edges.size(), 2):
		var a := edges[e]
		var b := edges[e + 1]
		adj[fill[a]] = b
		fill[a] += 1
		adj[fill[b]] = a
		fill[b] += 1
	# faces
	if ungrouped:
		var flag := PackedByteArray()
		flag.resize(tri_face.size())
		for t in tri_face.size():
			if tri_face[t] < 0:
				flag[t] = 1
		_group(flag)
	_number_faces()
	edge_inner = PackedByteArray()
	edge_inner.resize(edge_tn.size())
	for e in edge_tn.size():
		if edge_tn[e] == 2 and tri_face[edge_tris[e * 2]] == tri_face[edge_tris[e * 2 + 1]]:
			edge_inner[e] = 1
	_topo_ids += 1
	topo = _topo_ids


## The faces numbered 0 .. face_n - 1 (in the triangles' order), in the surfaces too.
func _number_faces() -> void:
	var top := -1
	for f in tri_face:
		top = maxi(top, f)
	var map := PackedInt32Array()
	map.resize(top + 1)
	map.fill(-1)
	var nf := 0
	for t in tri_face.size():
		var f := tri_face[t]
		if map[f] < 0:
			map[f] = nf
			nf += 1
		var g := map[f]
		tri_face[t] = g
		(surfs[tri_surf[t]] as Surf).face[tri_at[t] / 3] = g
	face_n = nf
	face_live = nf


## Triangles `flag` grouped into faces: flat (normals within 1°) edge-joined triangles
## of one surface, not across a seam. First pairs into quads - their shared edge the
## longest of both, every corner 20°..160°, the squarest first (a grid's diagonals) -
## then those joined into n-gons across the flat edges between corners on the rim of
## the flat area (a fan's centre, a grid's inner corners stay corners), never making a
## corner straight or a point inside a face. Sets tri_face of those triangles.
func _group(flag: PackedByteArray) -> void:
	var nt := tri_count()
	var nrm := PackedVector3Array()
	nrm.resize(nt)
	for t in nt:
		if flag[t]:
			var a := points[tris[t * 3]]
			var fn := (points[tris[t * 3 + 1]] - a).cross(points[tris[t * 3 + 2]] - a)
			var l := fn.length()
			nrm[t] = fn / l if l > 1e-20 else Vector3.ZERO
	var parent := PackedInt32Array()
	parent.resize(nt)
	for t in nt:
		parent[t] = t
	var cand := PackedInt32Array()
	var rim := PackedByteArray()   # (points on an edge that isn't flat inside the area)
	rim.resize(points.size())
	for e in edge_tn.size():
		var ok := edge_tn[e] == 2
		if ok:
			var t0 := edge_tris[e * 2]
			var t1 := edge_tris[e * 2 + 1]
			ok = flag[t0] == 1 and flag[t1] == 1 and tri_surf[t0] == tri_surf[t1] and nrm[t0] != Vector3.ZERO \
				and nrm[t0].dot(nrm[t1]) > COPLANAR
		if ok:
			# (flat inside the area - a seam along it keeps it from joining faces, not from being inside)
			if _seamless(edge_tris[e * 2], edge_tris[e * 2 + 1], edges[e * 2], edges[e * 2 + 1]):
				cand.append(e)
		else:
			rim[edges[e * 2]] = 1
			rim[edges[e * 2 + 1]] = 1
	# quads, squarest first
	var keys := PackedInt64Array()
	for ci in cand.size():
		var q := _quad_quality(cand[ci])
		if q >= 0.0:
			keys.append((int(q * 1000.0) << 32) | ci)
	keys.sort()
	var paired := PackedByteArray()
	paired.resize(nt)
	for k in keys:
		var e := cand[k & 0xFFFFFFFF]
		var t0 := edge_tris[e * 2]
		var t1 := edge_tris[e * 2 + 1]
		if paired[t0] or paired[t1]:
			continue
		paired[t0] = 1
		paired[t1] = 1
		parent[t1] = t0
	# n-gons
	for round in 3:
		var merged := false
		for e in cand:
			var a := edges[e * 2]
			var b := edges[e * 2 + 1]
			if not rim[a] or not rim[b]:
				continue
			var r0 := _root(parent, edge_tris[e * 2])
			var r1 := _root(parent, edge_tris[e * 2 + 1])
			if r0 == r1:
				continue
			if _joinable(a, r0, r1, parent) and _joinable(b, r0, r1, parent):
				parent[r1] = r0
				merged = true
		if not merged:
			break
	var base := 0
	for f in tri_face:
		base = maxi(base, f + 1)
	for t in nt:
		if flag[t]:
			tri_face[t] = base + _root(parent, t)


static func _root(parent: PackedInt32Array, t: int) -> int:
	while parent[t] != t:
		parent[t] = parent[parent[t]]
		t = parent[t]
	return t


## Triangle `t`'s vertex at point `p` (-1: not a corner).
func _vert_at(t: int, p: int) -> int:
	var s: Surf = surfs[tri_surf[t]]
	var i := tri_at[t]
	for k in 3:
		var v := s.idx[i + k]
		if s.vp[v] == p:
			return v
	return -1


## Triangles t0 and t1 share their vertices along edge a-b (no UV seam or hard edge there).
func _seamless(t0: int, t1: int, a: int, b: int) -> bool:
	return _vert_at(t0, a) == _vert_at(t1, a) and _vert_at(t0, b) == _vert_at(t1, b)


func _third(t: int, a: int, b: int) -> int:
	for k in 3:
		var p := tris[t * 3 + k]
		if p != a and p != b:
			return p
	return -1


## How far from square the quad of edge `e`'s two triangles is (the sum of its corners'
## differences from 90°, degrees); -1: not a quad (the edge isn't the longest of both,
## a corner under 20° or over 160°, not convex).
func _quad_quality(e: int) -> float:
	var t0 := edge_tris[e * 2]
	var t1 := edge_tris[e * 2 + 1]
	var ia := edges[e * 2]
	var ib := edges[e * 2 + 1]
	var i0 := _third(t0, ia, ib)
	var i1 := _third(t1, ia, ib)
	if i0 < 0 or i1 < 0 or i0 == i1:
		return -1.0
	var a := points[ia]
	var b := points[ib]
	var c0 := points[i0]
	var c1 := points[i1]
	var l := a.distance_to(b) / 1.001
	if a.distance_to(c0) >= l or b.distance_to(c0) >= l or a.distance_to(c1) >= l or b.distance_to(c1) >= l:
		return -1.0
	var nn := (b - a).cross(c0 - a)
	var sa := (c1 - c0).cross(a - c0).dot(nn)
	var sb := (c1 - c0).cross(b - c0).dot(nn)
	if sa * sb >= 0.0:
		return -1.0
	var q := 0.0
	for c in [[a, c0, c1], [b, c0, c1], [c0, a, b], [c1, a, b]]:
		var ang := rad_to_deg((c[1] - c[0]).angle_to(c[2] - c[0]))
		if ang < 20.0 or ang > 160.0:
			return -1.0
		q += absf(ang - 90.0)
	return q


## Groups r0 and r1 joined: point `v` still a corner on their rim - two rim edges at it,
## not in a straight line.
func _joinable(v: int, r0: int, r1: int, parent: PackedInt32Array) -> bool:
	var q1 := -1
	var q2 := -1
	for k in range(adj_start[v], adj_start[v + 1]):
		var q := adj[k]
		var e := edge(v, q)
		var tn := edge_tn[e]
		if tn > 2:
			return false
		var r := _root(parent, edge_tris[e * 2])
		var in0 := r == r0 or r == r1
		var in1 := false
		if tn == 2:
			r = _root(parent, edge_tris[e * 2 + 1])
			in1 = r == r0 or r == r1
		if in0 != in1:
			if q1 < 0:
				q1 = q
			elif q2 < 0:
				q2 = q
			else:
				return false
	if q2 < 0:
		return false
	return (points[q1] - points[v]).normalized().dot((points[q2] - points[v]).normalized()) > STRAIGHT


func tri_count() -> int:
	return tris.size() / 3


func edge_count() -> int:
	return edges.size() / 2


## The edge between points a and b (-1: none).
func edge(a: int, b: int) -> int:
	if a > b:
		var t := a; a = b; b = t
	return edge_of.get(a * KEY + b, -1)


# --- faces (n-gons) -------------------------------------------------------------

## How many faces (n-gons, quads, triangles).
func poly_count() -> int:
	return face_live


## The triangles of triangle `t`'s face (it first).
func poly_tris(t: int) -> PackedInt32Array:
	var out := PackedInt32Array([t])
	var i := 0
	while i < out.size():
		var u := out[i]
		i += 1
		for k in 3:
			var e := tri_edges[u * 3 + k]
			if e < 0 or not edge_inner[e]:
				continue
			var o := edge_tris[e * 2] if edge_tris[e * 2] != u else edge_tris[e * 2 + 1]
			if not out.has(o):
				out.append(o)
	return out


## A triangle alone in its face (none of its edges inside a face).
func _lone(t: int) -> bool:
	for k in 3:
		var e := tri_edges[t * 3 + k]
		if e >= 0 and edge_inner[e]:
			return false
	return true


## Flags `tsel` (a flag a triangle) spread to whole faces: any of a face's flagged - all of it.
func grow_to_polys(tsel: PackedByteArray) -> PackedByteArray:
	var out := tsel.duplicate()
	for t in mini(tsel.size(), tri_count()):
		if tsel[t] and not _lone(t):
			for u in poly_tris(t):
				out[u] = 1
	return out


## Flags `tsel` kept only for whole faces (a face with any triangle not flagged: none of it).
func close_to_polys(tsel: PackedByteArray) -> void:
	var done := PackedByteArray()
	done.resize(tsel.size())
	for t in mini(tsel.size(), tri_count()):
		if not tsel[t] or done[t] or _lone(t):
			continue
		var pt := poly_tris(t)
		var all := true
		for u in pt:
			done[u] = 1
			if not tsel[u]:
				all = false
		if not all:
			for u in pt:
				tsel[u] = 0


## The corners of the face made of triangles `pt`, in order round it (the triangles' way
## round); empty if it isn't one simple outline.
func _loop_of(pt: PackedInt32Array) -> PackedInt32Array:
	var nxt := {}
	for t in pt:
		for k in 3:
			var e := tri_edges[t * 3 + k]
			if e >= 0 and edge_inner[e]:
				continue
			var a := tris[t * 3 + k]
			if nxt.has(a):
				return PackedInt32Array()
			nxt[a] = tris[t * 3 + (k + 1) % 3]
	if nxt.is_empty():
		return PackedInt32Array()
	var out := PackedInt32Array()
	var p: int = nxt.keys()[0]
	while out.size() <= nxt.size():
		out.append(p)
		p = nxt.get(p, -1)
		if p < 0:
			return PackedInt32Array()
		if p == out[0]:
			break
	return out if out.size() == nxt.size() else PackedInt32Array()


## The corners of triangle `t`'s face, in order round it.
func poly_loop(t: int) -> PackedInt32Array:
	return _loop_of(poly_tris(t))


## The edges shown (point pairs): those between faces - not the diagonals inside them
## (`all`: every edge, the triangles).
func wire_edges(all := false) -> PackedInt32Array:
	if all or face_live == tri_count():
		return edges
	if _wire_topo != topo:
		_wire = PackedInt32Array()
		for e in edge_inner.size():
			if not edge_inner[e]:
				_wire.append(edges[e * 2])
				_wire.append(edges[e * 2 + 1])
		_wire_topo = topo
	return _wire


## The triangles with point `p` as a corner (along its edges).
func tris_around(p: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in range(adj_start[p], adj_start[p + 1]):
		var e := edge(p, adj[k])
		for t in edge_tri_list(e):
			if not out.has(t):
				out.append(t)
	return out


## The triangles on edge `e` (all of them, a non-manifold edge's too).
func edge_tri_list(e: int) -> PackedInt32Array:
	var out := edge_tris.slice(e * 2, e * 2 + mini(edge_tn[e], 2))
	if edge_tn[e] > 2:
		out.append_array(edge_more[e])
	return out


## The vertices of `ids` (points), surface by surface: [PackedInt32Array per surface].
func verts_of(ids: PackedInt32Array) -> Array:
	var out := []
	for s in surfs:
		out.append(PackedInt32Array())
	for p in ids:
		for k in range(pv_start[p], pv_start[p + 1]):
			var e := pv[k]
			var lst: PackedInt32Array = out[e >> SHIFT]
			out[e >> SHIFT] = PackedInt32Array()   # (one owner: append in place)
			lst.append(e & VMASK)
			out[e >> SHIFT] = lst
	return out


## The vertices' positions from the points: all (`per_surf` empty), or the lists verts_of() made.
func sync(per_surf := []) -> void:
	for si in surfs.size():
		var s: Surf = surfs[si]
		if per_surf.is_empty():
			s.sync(points, PackedInt32Array())
		elif not (per_surf[si] as PackedInt32Array).is_empty():
			s.sync(points, per_surf[si])


func recalc_normals(per_surf := []) -> void:
	for si in surfs.size():
		if per_surf.is_empty() or not (per_surf[si] as PackedInt32Array).is_empty():
			surfs[si].recalc_normals()


## Refills `mesh` (what's shown) from the surfaces.
func update_mesh() -> void:
	mesh.clear_surfaces()
	var faces := []
	for s in surfs:
		if (s as Surf).idx.is_empty():
			continue
		faces.append((s as Surf).face.duplicate())
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s.arrays(), [], {}, s.flags)
		var k := mesh.get_surface_count() - 1
		mesh.surface_set_name(k, s.name)
		if s.material:
			mesh.surface_set_material(k, s.material)
	for o in other:
		mesh.add_surface_from_arrays(o[0], o[1], [], {}, o[2])
		var k := mesh.get_surface_count() - 1
		mesh.surface_set_name(k, o[4])
		if o[3]:
			mesh.surface_set_material(k, o[3])
	_keep_faces(mesh, faces)


## A new mesh of the surfaces (the edit's result, kept).
func to_mesh() -> ArrayMesh:
	var keep := mesh
	mesh = ArrayMesh.new()
	update_mesh()
	var out := mesh
	mesh = keep
	return out


## Triangle `t`'s ray-test mesh: faces in tris order (TriangleMesh's face_index = t).
func triangle_mesh() -> TriangleMesh:
	var f := PackedVector3Array()
	f.resize(tris.size())
	for i in tris.size():
		f[i] = points[tris[i]]
	var tm := TriangleMesh.new()
	tm.create_from_faces(f)
	return tm


# --- moving points ------------------------------------------------------------

## Points `ids` placed from `orig` by `xf`, each `w` of the way (1: all of it).
func place(ids: PackedInt32Array, orig: PackedVector3Array, w: PackedFloat32Array, xf: Transform3D) -> void:
	for k in ids.size():
		var o := orig[k]
		points[ids[k]] = o.lerp(xf * o, w[k]) if w[k] < 1.0 else xf * o


## Symmetry: each (source, twin, axis) triple's twin put opposite its source, in order.
func follow(pairs: PackedInt32Array) -> void:
	for i in range(0, pairs.size(), 3):
		points[pairs[i + 1]] = mirrored(points[pairs[i]], pairs[i + 2])


## The mirror modifier's clipping: points never cross the seam of the axes in
## `axes`; `side` (3 a point of `ids`): the side each started on (0: on the seam - stays there).
func clip(ids: PackedInt32Array, side: PackedFloat32Array, axes: Array) -> void:
	for k in ids.size():
		var p := points[ids[k]]
		for a in 3:
			if axes[a]:
				var sd := side[k * 3 + a]
				if sd == 0.0 or p[a] * sd < 0.0:
					p[a] = 0.0
		points[ids[k]] = p


# --- undo ---------------------------------------------------------------------

## Everything an edit can change (copies: packed arrays are shared by reference).
func snapshot() -> Dictionary:
	return {"points": points.duplicate(), "surfs": surfs.map(func(s): return s.copy()), "topo": topo, "derived": _derived()}


## The derived arrays as they are (never changed in place: a snapshot can keep them).
func _derived() -> Array:
	return [tris, tri_surf, tri_at, tri_face, tri_edges, edges, edge_of, edge_tris, edge_tn, edge_inner,
		pv_start, pv, adj_start, adj, face_n, edge_more, face_live]


## About how much memory a snapshot takes.
func snapshot_bytes() -> int:
	var b := points.size() * 12
	for s in surfs:
		b += s.bytes()
	return b


func restore(snap: Dictionary) -> void:
	points = (snap["points"] as PackedVector3Array).duplicate()
	surfs = (snap["surfs"] as Array).map(func(s): return s.copy())
	if int(snap["topo"]) != topo:
		var d: Array = snap.get("derived", [])
		if d.size() == 17:
			tris = d[0]; tri_surf = d[1]; tri_at = d[2]; tri_face = d[3]; tri_edges = d[4]; edges = d[5]
			edge_of = d[6]; edge_tris = d[7]; edge_tn = d[8]; edge_inner = d[9]; pv_start = d[10]; pv = d[11]
			adj_start = d[12]; adj = d[13]; face_n = d[14]; edge_more = d[15]; face_live = d[16]
		else:
			derive()
		topo = int(snap["topo"])


# --- selection helpers --------------------------------------------------------

## The points of triangles `tsel` (a flag a triangle).
func points_of_tris(tsel: PackedByteArray) -> PackedInt32Array:
	var flag := PackedByteArray()
	flag.resize(points.size())
	var out := PackedInt32Array()
	for t in tsel.size():
		if tsel[t]:
			for k in 3:
				var p := tris[t * 3 + k]
				if not flag[p]:
					flag[p] = 1
					out.append(p)
	return out


func points_of_edges(esel: PackedByteArray) -> PackedInt32Array:
	var flag := PackedByteArray()
	flag.resize(points.size())
	var out := PackedInt32Array()
	for e in esel.size():
		if esel[e]:
			for k in 2:
				var p := edges[e * 2 + k]
				if not flag[p]:
					flag[p] = 1
					out.append(p)
	return out


func centroid(ids: PackedInt32Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ids:
		c += points[p]
	return c / maxf(1, ids.size())


func aabb() -> AABB:
	if points.is_empty():
		return AABB()
	var b := AABB(points[0], Vector3.ZERO)
	for p in points:
		b = b.expand(p)
	return b


# --- proportional editing -----------------------------------------------------

static func falloff(kind: String, d: float, r: float) -> float:
	if d >= r:
		return 0.0
	var x := d / r
	var t := 1.0 - x
	match kind:
		"sphere": return sqrt(maxf(0.0, 1.0 - x * x))
		"root": return sqrt(t)
		"linear": return t
		"sharp": return t * t
		"constant": return 1.0
	return t * t * (3.0 - 2.0 * t)   # smooth


## The points a transform of `sel` moves and how much: [ids, weights] - the
## selection (1) and, with proportional editing, everything within `radius`
## of it (by straight distance, or `connected`: along the edges, only what's
## joined to it), weighted by the falloff.
func influence(sel: PackedInt32Array, radius: float, kind: String, connected: bool) -> Array:
	var n := points.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	for p in sel:
		dist[p] = 0.0
	if connected:
		var queue := sel.duplicate()
		var head := 0
		while head < queue.size():
			var p := queue[head]
			head += 1
			var dp := dist[p]
			for k in range(adj_start[p], adj_start[p + 1]):
				var q := adj[k]
				var d := dp + points[p].distance_to(points[q])
				if d < dist[q] and d < radius:
					dist[q] = d
					queue.append(q)
	elif radius > 0.0 and not sel.is_empty():
		# selected points hashed in cells of `radius`: each point looks at the 27 around it
		# (a big selection is thinned to one point in each tenth of the radius:
		# distances off by under 9% of it, at a fraction of the work)
		var cells := {}
		var seen := {}
		var box := AABB(points[sel[0]], Vector3.ZERO)
		for p in sel:
			if sel.size() > 64:
				var fine := Vector3i((points[p] / (radius * 0.1)).floor())
				if seen.has(fine):
					continue
				seen[fine] = true
			var c := Vector3i((points[p] / radius).floor())
			if not cells.has(c):
				cells[c] = PackedInt32Array()
			var l: PackedInt32Array = cells[c]
			cells[c] = PackedInt32Array()
			l.append(p)
			cells[c] = l
			box = box.expand(points[p])
		box = box.grow(radius)
		var r2 := radius * radius
		for q in n:
			var pq := points[q]
			if dist[q] == 0.0 or not box.has_point(pq):
				continue
			var c := Vector3i((pq / radius).floor())
			var best := r2
			# its own cell first, then the cells around it nearer than the best yet
			var l = cells.get(c)
			if l != null:
				for p in l:
					best = minf(best, pq.distance_squared_to(points[p]))
			var lo := Vector3(c) * radius
			for o in _AROUND:
				var cc: Vector3i = c + o
				# (the gap from it to that cell)
				var dx := pq.x - lo.x if o.x < 0 else (lo.x + radius - pq.x if o.x > 0 else 0.0)
				var dy := pq.y - lo.y if o.y < 0 else (lo.y + radius - pq.y if o.y > 0 else 0.0)
				var dz := pq.z - lo.z if o.z < 0 else (lo.z + radius - pq.z if o.z > 0 else 0.0)
				if dx * dx + dy * dy + dz * dz >= best:
					continue
				l = cells.get(cc)
				if l == null:
					continue
				for p in l:
					best = minf(best, pq.distance_squared_to(points[p]))
			if best < r2:
				dist[q] = sqrt(best)
	var ids := PackedInt32Array()
	var w := PackedFloat32Array()
	for p in sel:
		ids.append(p)
		w.append(1.0)
	if radius > 0.0:
		for q in n:
			var d := dist[q]
			if d > 0.0 and d < radius:
				var f := falloff(kind, d, radius)
				if f > 0.0:
					ids.append(q)
					w.append(f)
	return [ids, w]


# --- symmetry -----------------------------------------------------------------

static func mirrored(p: Vector3, axis: int) -> Vector3:
	p[axis] = -p[axis]
	return p


## Each point's twin across `axis` (itself on the seam; -1: none), by position
## (within `tol`).
func mirror_map(axis: int, tol := 0.001) -> PackedInt32Array:
	var cells := {}
	for i in points.size():
		var c := Vector3i((points[i] / tol).round())
		if not cells.has(c):
			cells[c] = i
	var out := PackedInt32Array()
	out.resize(points.size())
	for i in points.size():
		var m := mirrored(points[i], axis)
		var c := Vector3i((m / tol).round())
		var j: int = cells.get(c, -1)
		if j < 0:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var k: int = cells.get(c + Vector3i(dx, dy, dz), -1)
						if k >= 0 and points[k].distance_to(m) <= tol * 1.8:
							j = k
		if absf(points[i][axis]) <= tol * 0.5:
			j = i
		out[i] = j
	return out


## Symmetrize: the `positive` side (+axis) copied onto the other (or the
## reverse). Each point of the side made to match is paired with the nearest
## mirrored point of the other side within `tol`; points on the seam (within
## `seam`) are put on it. The points changed.
func symmetrize(axis: int, positive := true, tol := -1.0, seam := 0.0005) -> PackedInt32Array:
	if tol < 0.0:
		tol = maxf(0.002, aabb().size.length() * 0.03)
	var sgn := 1.0 if positive else -1.0
	var cells := {}
	for i in points.size():
		if points[i][axis] * sgn > seam:
			var c := Vector3i((points[i] / tol).floor())
			if not cells.has(c):
				cells[c] = PackedInt32Array()
			var l: PackedInt32Array = cells[c]
			cells[c] = PackedInt32Array()
			l.append(i)
			cells[c] = l
	var changed := PackedInt32Array()
	for i in points.size():
		var v := points[i][axis] * sgn
		if v > seam:
			continue
		if v >= -seam:
			if points[i][axis] != 0.0:
				points[i][axis] = 0.0
				changed.append(i)
			continue
		var m := mirrored(points[i], axis)
		var c := Vector3i((m / tol).floor())
		var best := -1
		var bd := tol * tol
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var l = cells.get(c + Vector3i(dx, dy, dz))
					if l == null:
						continue
					for k in l:
						var d := points[k].distance_squared_to(m)
						if d <= bd:
							bd = d
							best = k
		if best >= 0:
			points[i] = mirrored(points[best], axis)
			changed.append(i)
	return changed




# --- topology edits -----------------------------------------------------------

## The triangles flagged in `tsel`, surface by surface: their first indices.
func _starts(tsel: PackedByteArray) -> Array:
	var out := []
	for s in surfs:
		out.append(PackedInt32Array())
	for t in mini(tsel.size(), tri_count()):
		if tsel[t]:
			var l: PackedInt32Array = out[tri_surf[t]]
			out[tri_surf[t]] = PackedInt32Array()
			l.append(tri_at[t])
			out[tri_surf[t]] = l
	return out


## Mirror (the modifier, applied): across each of `axes` ([x, y, z] bools) in
## turn, the mesh copied (faces turned the right way round); points on the
## seam (within `merge`) are shared by both halves - put on it when `clip`.
## The vertex count becomes twice what it was, less the seam's.
## (`recalc` false: the normals kept - the copies' mirrored, those on the seam put along it.)
func apply_mirror(axes: Array, merge := 0.001, clip := true, recalc := true, bones_twin := PackedInt32Array()) -> void:
	for axis in 3:
		if not axes[axis]:
			continue
		var n0 := points.size()
		var pm := PackedInt32Array()
		pm.resize(n0)
		for i in n0:
			if absf(points[i][axis]) <= merge:
				pm[i] = i
				if clip:
					points[i][axis] = 0.0
			else:
				pm[i] = points.size()
				points.append(mirrored(points[i], axis))
		var seam := false
		var foff := 0
		for s: Surf in surfs:
			for f in s.face:
				foff = maxi(foff, f + 1)
		for s: Surf in surfs:
			seam = s.mirror(pm, points, axis, clip, foff, bones_twin) or seam
		if seam and recalc:
			for s: Surf in surfs:
				s.recalc_normals()
		elif seam:
			for s: Surf in surfs:
				for v in s.count():
					if s.vp[v] < n0 and pm[s.vp[v]] == s.vp[v]:
						var nn := s.nrm[v]
						nn[axis] = 0.0
						if nn.length_squared() > 1e-12:
							s.nrm[v] = nn.normalized()
	for s: Surf in surfs:
		s.drop_degenerate()
	compact()
	derive()


## Deletes triangles (flagged), then the points nothing uses any more.
func delete_tris(tsel: PackedByteArray) -> void:
	var st := _starts(tsel)
	for si in surfs.size():
		if not (st[si] as PackedInt32Array).is_empty():
			var kill := {}
			for i in st[si]:
				kill[i] = true
			surfs[si].drop_tris(kill)
	compact()
	derive()


## Material `mat` given to the triangles flagged in `tsel` (whole faces): a surface all of whose
## triangles are flagged just gets it; flagged ones that are only some of their surface's move
## into a new surface of their own (their vertices copied, the same points - nothing moves),
## added after the others. The triangles that have `mat` afterwards (flags, in the new order).
func split_to_surface(tsel: PackedByteArray, mat: Material) -> PackedByteArray:
	var st := _starts(tsel)
	var whole := {}
	var added := []
	for si in surfs.size():
		var starts: PackedInt32Array = st[si]
		if starts.is_empty():
			continue
		var s: Surf = surfs[si]
		if starts.size() * 3 >= s.idx.size():
			s.material = mat
			whole[si] = true
			continue
		var n := Surf.new()
		n.name = s.name + "_" + (mat.resource_name if mat and mat.resource_name != "" else "material")
		n.material = mat
		n.flags = s.flags
		n.nb = s.nb
		var has_f := s.face.size() == s.idx.size() / 3
		var map := {}
		var kill := {}
		for i in starts:
			kill[i] = true
			for k in 3:
				var v := s.idx[i + k]
				if not map.has(v):
					map[v] = n.pos.size()
					n.pos.append(s.pos[v])
					n.nrm.append(s.nrm[v])
					if not s.col.is_empty():
						n.col.append(s.col[v])
					if not s.uv.is_empty():
						n.uv.append(s.uv[v])
					if not s.uv2.is_empty():
						n.uv2.append(s.uv2[v])
					for b in s.nb:
						n.bones.append(s.bones[v * s.nb + b])
						n.weights.append(s.weights[v * s.nb + b])
					n.vp.append(s.vp[v])
				n.idx.append(map[v])
			n.face.append(s.face[i / 3] if has_f else -1)
		s.drop_tris(kill)
		added.append(n)
	var first := surfs.size()
	surfs.append_array(added)
	compact()
	derive()
	var out := PackedByteArray()
	out.resize(tri_count())
	for t in tri_count():
		var si := tri_surf[t]
		out[t] = 1 if whole.has(si) or si >= first else 0
	return out


## Unused vertices and points dropped (renumbered in order).
func compact() -> void:
	for s: Surf in surfs:
		s.compact()
	var used := PackedByteArray()
	used.resize(points.size())
	for s: Surf in surfs:
		for p in s.vp:
			used[p] = 1
	var map := PackedInt32Array()
	map.resize(points.size())
	var np := PackedVector3Array()
	for p in points.size():
		if used[p]:
			map[p] = np.size()
			np.append(points[p])
		else:
			map[p] = -1
	if np.size() == points.size():
		return
	for s: Surf in surfs:
		s.remap_points(map)
	points = np


## Merges points `ids` into one at their centre; its index afterwards.
func merge(ids: PackedInt32Array) -> int:
	if ids.size() < 2:
		return ids[0] if ids.size() == 1 else -1
	var target := ids[0]
	var at := centroid(ids)
	points[target] = at
	var flag := PackedByteArray()
	flag.resize(points.size())
	for p in ids:
		flag[p] = 1
	for s: Surf in surfs:
		s.merge_points(flag, target, at)
		s.drop_degenerate()
		s.compact()
	var used := PackedByteArray()
	used.resize(points.size())
	for s: Surf in surfs:
		for p in s.vp:
			used[p] = 1
	var keep := 0
	for p in target:
		keep += used[p]
	compact()
	derive()
	return keep


## Extrudes triangles `tsel`: the region's points doubled (the region's
## triangles moved onto the copies) and walls along its border. Returns the
## copies (what to move next).
func extrude(tsel: PackedByteArray) -> PackedInt32Array:
	var n0 := points.size()
	var np := PackedInt32Array()   # point -> its copy
	np.resize(n0)
	np.fill(-1)
	var border := {}
	for t in mini(tsel.size(), tri_count()):
		if not tsel[t]:
			continue
		for k in 3:
			var a := tris[t * 3 + k]
			var b := tris[t * 3 + (k + 1) % 3]
			var key := mini(a, b) * n0 + maxi(a, b)
			border[key] = border.get(key, 0) + 1
			if np[a] < 0:
				np[a] = points.size()
				points.append(points[a])
	var st := _starts(tsel)
	var next := face_n
	for si in surfs.size():
		if not (st[si] as PackedInt32Array).is_empty():
			next = surfs[si].extrude(st[si], np, border, n0, next)
			surfs[si].recalc_normals()
	derive()
	var out := PackedInt32Array()
	for p in n0:
		if np[p] >= 0:
			out.append(np[p])
	return out


## Subdivides triangles `tsel`: each into four at its edges' middles (the
## triangles beside them split to match - no cracks). Returns the points of
## the new, smaller triangles.
func subdivide(tsel: PackedByteArray) -> PackedInt32Array:
	var n0 := points.size()
	var mid := {}
	var region := PackedByteArray()
	region.resize(n0)
	for t in mini(tsel.size(), tri_count()):
		if not tsel[t]:
			continue
		for k in 3:
			var a := tris[t * 3 + k]
			var b := tris[t * 3 + (k + 1) % 3]
			region[a] = 1
			var key := mini(a, b) * n0 + maxi(a, b)
			if not mid.has(key):
				mid[key] = points.size()
				points.append((points[a] + points[b]) * 0.5)
	# each quad cut whole: its four quads (corner, two side middles, its middle), whichever
	# way their triangles come out - the rest of the pieces' faces found from their shape
	var quad_of := {}   # sorted corners of a piece triangle -> its quad
	var nq := 0
	var done := {}
	for t in mini(tsel.size(), tri_count()):
		if not tsel[t] or done.has(tri_face[t]):
			continue
		done[tri_face[t]] = true
		var pt := poly_tris(t)
		var whole := pt.size() == 2
		for u in pt:
			whole = whole and u < tsel.size() and tsel[u] == 1
		var lp := _loop_of(pt)
		if not whole or lp.size() != 4:
			continue
		var c := _mid_of(mid, n0, lp[0], lp[2])
		if c < 0:
			c = _mid_of(mid, n0, lp[1], lp[3])
		if c < 0:
			continue
		for i in 4:
			var q := [lp[i], _mid_of(mid, n0, lp[i], lp[(i + 1) % 4]), c, _mid_of(mid, n0, lp[i], lp[(i + 3) % 4])]
			for j in 4:
				var k := [q[j], q[(j + 1) % 4], q[(j + 2) % 4]]
				k.sort()
				quad_of[Vector3i(k[0], k[1], k[2])] = nq
			nq += 1
	var base := face_n
	for s: Surf in surfs:
		s.subdivide(mid, n0, points)
		if not quad_of.is_empty():
			for i in s.face.size():
				if s.face[i] < 0:
					var k := [s.vp[s.idx[i * 3]], s.vp[s.idx[i * 3 + 1]], s.vp[s.idx[i * 3 + 2]]]
					k.sort()
					var q: int = quad_of.get(Vector3i(k[0], k[1], k[2]), -1)
					if q >= 0:
						s.face[i] = base + q
	derive()
	var out := PackedInt32Array()
	for p in points.size():
		if p >= n0 or region[p]:
			out.append(p)
	return out


static func _mid_of(mid: Dictionary, n0: int, a: int, b: int) -> int:
	return mid.get(mini(a, b) * n0 + maxi(a, b), -1)


## Turns triangles `tsel` (all, if empty) the other way round, their normals too.
func flip(tsel: PackedByteArray) -> void:
	if tsel.is_empty():
		tsel.resize(tri_count())
		tsel.fill(1)
	var st := _starts(tsel)
	for si in surfs.size():
		if not (st[si] as PackedInt32Array).is_empty():
			surfs[si].flip(st[si])
	derive()


# --- the knife ------------------------------------------------------------------
# A cut is drawn as *nodes* - spots the knife passes: on a point {"k": 0, "p"}, on an
# edge {"k": 1, "e", "t": the way along it from its first point to its second}, or
# inside a triangle {"k": 2, "tri"} - each with its "pos". Between two nodes the cut
# follows the surface where a plane (through both, along the view) meets it:
# knife_walk() steps from triangle to triangle, each edge it crosses a node. A chain
# ({"nodes", "segs": the triangle each step goes through, -1 along an edge}) is then
# made by knife_apply(): each face it crosses is made again - its outline with the new
# points on its sides, split along the cut into two faces, each triangulated.

static func node_point(p: int, pos: Vector3) -> Dictionary:
	return {"k": 0, "p": p, "pos": pos}


static func node_face(tri: int, pos: Vector3) -> Dictionary:
	return {"k": 2, "tri": tri, "pos": pos}


## The node `t` of the way along edge `e` (at an end: that point).
func node_on_edge(e: int, t: float) -> Dictionary:
	var a := edges[e * 2]
	var b := edges[e * 2 + 1]
	if t <= 1e-4:
		return node_point(a, points[a])
	if t >= 1.0 - 1e-4:
		return node_point(b, points[b])
	return {"k": 1, "e": e, "t": t, "pos": points[a].lerp(points[b], t)}


## Where a cut at `pos` on triangle `tri` starts or bends: `kind` 0 the nearest corner of
## its face, 1 the nearest spot on a side of the face, 2 the face itself; -1: a corner or a
## side within `tol` of it, else the face.
func knife_node(tri: int, pos: Vector3, kind := -1, tol := 0.0) -> Dictionary:
	var loop := poly_loop(tri)
	if loop.is_empty():
		loop = tris.slice(tri * 3, tri * 3 + 3)
	if kind != 2:
		var bp := -1
		var bd := INF
		for p in loop:
			var d := points[p].distance_to(pos)
			if d < bd:
				bd = d
				bp = p
		if kind == 0 or bd <= tol:
			return node_point(bp, points[bp])
		var be := -1
		var bt := 0.0
		bd = INF
		for i in loop.size():
			var a := loop[i]
			var b := loop[(i + 1) % loop.size()]
			var q := Geometry3D.get_closest_point_to_segment(pos, points[a], points[b])
			var d := q.distance_to(pos)
			if d < bd:
				bd = d
				be = edge(a, b)
				var l := points[a].distance_to(points[b])
				bt = points[a].distance_to(q) / l if l > 0.0 else 0.0
				if be >= 0 and edges[be * 2] != a:
					bt = 1.0 - bt
		if be >= 0 and (kind == 1 or bd <= tol):
			return node_on_edge(be, bt)
	return node_face(tri, pos)


## How near a point must be to the knife's plane to be on it (a millionth of the mesh's size).
func knife_eps() -> float:
	if _eps_topo != topo:
		_eps = maxf(aabb().size.length(), 0.001) * 1e-6
		_eps_topo = topo
	return _eps


static func _node_key(x: Dictionary) -> String:
	match int(x["k"]):
		0: return "p%d" % x["p"]
		1: return "e%d:%d" % [x["e"], roundi(float(x["t"]) * 100000.0)]
	return "f%d:%s" % [x["tri"], x["pos"]]


## The triangles node `x` lies on.
func _node_tris(x: Dictionary) -> PackedInt32Array:
	match int(x["k"]):
		0: return tris_around(x["p"])
		1: return edge_tri_list(x["e"])
	return PackedInt32Array([x["tri"]])


func _node_on(x: Dictionary, t: int) -> bool:
	match int(x["k"]):
		0:
			var p: int = x["p"]
			return tris[t * 3] == p or tris[t * 3 + 1] == p or tris[t * 3 + 2] == p
		1:
			var e: int = x["e"]
			return tri_edges[t * 3] == e or tri_edges[t * 3 + 1] == e or tri_edges[t * 3 + 2] == e
	return int(x["tri"]) == t


## A node not on a face's inside: a corner, or a spot on an edge between faces.
func _border(x: Dictionary) -> bool:
	match int(x["k"]):
		0: return true
		1: return not edge_inner[x["e"]]
	return false


## The ways on from node `x` along the plane (normal `n`, through `o`) - not back through
## triangle `came`: [[the triangle it goes through (-1: along an edge), the next node], ...].
func _steps(x: Dictionary, n: Vector3, o: Vector3, eps: float, came: int) -> Array:
	var out := []
	var k: int = x["k"]
	var xp: int = x["p"] if k == 0 else -1
	var xa := -1
	var xb := -1
	if k == 1:
		xa = edges[int(x["e"]) * 2]
		xb = edges[int(x["e"]) * 2 + 1]
		var da := n.dot(points[xa] - o)
		var db := n.dot(points[xb] - o)
		if absf(da) <= eps and absf(db) <= eps:   # (the plane along this edge: on to its ends)
			return [[-1, node_point(xa, points[xa])], [-1, node_point(xb, points[xb])]]
	for t in _node_tris(x):
		if t == came:
			continue
		var c := [tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]]
		var d := [n.dot(points[c[0]] - o), n.dot(points[c[1]] - o), n.dot(points[c[2]] - o)]
		for i in 3:
			var p: int = c[i]
			if p == xp or p == xa or p == xb or absf(d[i]) > eps:
				continue
			out.append([-1 if k == 0 else t, node_point(p, points[p])])
		for i in 3:
			var j := (i + 1) % 3
			if absf(d[i]) <= eps or absf(d[j]) <= eps or (d[i] > 0.0) == (d[j] > 0.0):
				continue
			var p: int = c[i]
			var q: int = c[j]
			if p == xp or q == xp:
				continue
			var e := edge(p, q)
			if e < 0 or (k == 1 and e == int(x["e"])):
				continue
			var f: float = d[i] / (d[i] - d[j])
			if edges[e * 2] != p:
				f = 1.0 - f
			out.append([t, node_on_edge(e, f)])
	return out


## The cut from node `a` to node `b` over the surface, along the plane through both with
## normal `n`: {"nodes", "segs"}, or {} if it can't get there (a gap, the mesh's border).
## `look`: the way it's seen - where it could go either way, over the faces facing you.
func knife_walk(a: Dictionary, b: Dictionary, n: Vector3, look := Vector3.ZERO) -> Dictionary:
	if n.length_squared() < 1e-24:
		return {}
	n = n.normalized()
	var o: Vector3 = a["pos"]
	var eps := knife_eps()
	var ab: Vector3 = b["pos"] - o
	var l2 := ab.length_squared()
	var nodes := [a]
	var segs := PackedInt32Array()
	if _node_key(a) == _node_key(b):
		return {"nodes": nodes, "segs": segs}
	var tb := _node_tris(b)
	var x := a
	var came := -2
	var seen := {_node_key(a): true}
	var px := 0.0
	for step in tri_count() + 8:
		# b in a triangle with x: straight there
		for t in tb:
			if _node_on(x, t):
				nodes.append(b)
				segs.append(-1 if x["k"] == 0 and b["k"] == 0 else t)
				return {"nodes": nodes, "segs": segs}
		var opts := _steps(x, n, o, eps, came)
		var pick := -1
		var best := -INF
		var best_score := -INF
		var forced: bool = int(x["k"]) == 1 and came >= 0 and opts.size() == 1   # (through an edge: one way on)
		for i in opts.size():
			var y: Dictionary = opts[i][1]
			if seen.has(_node_key(y)):
				continue
			var py: float = (y["pos"] - o).dot(ab) / l2 if l2 > 0.0 else 0.0
			if not forced and py <= px + 1e-9:
				continue
			var score := py
			var t: int = opts[i][0]
			if look != Vector3.ZERO and t >= 0:
				var tn := (points[tris[t * 3 + 1]] - points[tris[t * 3]]).cross(points[tris[t * 3 + 2]] - points[tris[t * 3]])
				if tn.dot(look) < 0.0:   # (Godot's faces wind clockwise: this cross product points in)
					score -= 10.0   # (a face turned away: only if there's no other way)
			if score > best_score:
				best_score = score
				best = py
				pick = i
		if pick < 0 or best > 1.5 or best < -0.5:
			return {}
		var y: Dictionary = opts[pick][1]
		seen[_node_key(y)] = true
		nodes.append(y)
		segs.append(opts[pick][0])
		came = opts[pick][0] if int(opts[pick][0]) >= 0 else -2
		px = best
		x = y
	return {}


## A cut right through the mesh, front and back: everywhere the plane (normal `n`, through
## `o`) meets it within `sides` ([[point, normal], ...]: the half-spaces it stays in) -
## chains for knife_apply() (each a run of it over the surface; a ring closes on itself).
func knife_slice(o: Vector3, n: Vector3, sides: Array) -> Array:
	n = n.normalized()
	var eps := knife_eps()
	var chains := []
	var seen := {}
	for e in edge_count():
		var a := edges[e * 2]
		var b := edges[e * 2 + 1]
		var da := n.dot(points[a] - o)
		var db := n.dot(points[b] - o)
		if absf(da) <= eps or absf(db) <= eps or (da > 0.0) == (db > 0.0):
			continue
		var x := node_on_edge(e, da / (da - db))
		if x["k"] != 1 or seen.has(_node_key(x)) or not _inside(x["pos"], sides, eps):
			continue
		seen[_node_key(x)] = true
		var et := edge_tri_list(e)
		var fwd := _trace(x, et[1] if et.size() > 1 else -2, n, o, eps, sides, seen)
		var nodes := [x]
		var segs := PackedInt32Array()
		if not fwd["closed"] and et.size() > 1:
			var back := _trace(x, et[0], n, o, eps, sides, seen)
			var bn: Array = back["nodes"]
			var bs: PackedInt32Array = back["segs"]
			bn.reverse()
			bs.reverse()
			nodes = bn + nodes
			segs = bs
		nodes += fwd["nodes"]
		segs.append_array(fwd["segs"])
		if nodes.size() > 1:
			chains.append({"nodes": nodes, "segs": segs})
	return chains


static func _inside(pos: Vector3, sides: Array, eps: float) -> bool:
	for s in sides:
		if (pos - (s[0] as Vector3)).dot(s[1]) < -eps:
			return false
	return true


## From node `x` on along the plane, not back through `came`, as far as it goes within `sides`.
func _trace(x: Dictionary, came: int, n: Vector3, o: Vector3, eps: float, sides: Array, seen: Dictionary) -> Dictionary:
	var start := _node_key(x)
	var nodes := []
	var segs := PackedInt32Array()
	var closed := false
	for step in tri_count() + 8:
		var go := -1
		var opts := _steps(x, n, o, eps, came)
		for i in opts.size():
			var y: Dictionary = opts[i][1]
			var k := _node_key(y)
			if k == start and nodes.size() > 1:
				go = i
				closed = true
				break
			if not seen.has(k) and _inside(y["pos"], sides, eps):
				go = i
				break
		if go < 0:
			break
		var y: Dictionary = opts[go][1]
		nodes.append(y)
		segs.append(opts[go][0])
		if closed:
			break
		seen[_node_key(y)] = true
		came = opts[go][0] if int(opts[go][0]) >= 0 else -2
		x = y
	return {"nodes": nodes, "segs": segs, "closed": closed}


## Makes the cut of `chains` (knife_walk / knife_slice): each face it crosses side to side
## split along it into two faces (its ends inside a face are let go: a cut runs from side
## to side), the new points on the edges it crosses - each with its vertices' attributes
## mixed from the edge's ends (UVs, normals, colours, bone weights; one vertex a side of
## a seam or hard edge, so those stay) - and the faces beside them given the new points
## as corners (n-gons). Only the faces cut are made again; the derived arrays are patched
## where they changed. {"ok", "why", "cut": the new edges (point pairs), "points": the new points}.
func knife_apply(chains: Array) -> Dictionary:
	var cs := []
	for c in chains:
		var nodes: Array = c["nodes"]
		var segs: PackedInt32Array = c["segs"]
		if nodes.size() < 2:
			continue
		var closed: bool = nodes.size() > 2 and _node_key(nodes[0]) == _node_key(nodes[nodes.size() - 1])
		if not closed:
			var i0 := 0
			while i0 < nodes.size() and not _border(nodes[i0]):
				i0 += 1
			var i1 := nodes.size() - 1
			while i1 > i0 and not _border(nodes[i1]):
				i1 -= 1
			if i1 <= i0:
				continue
			nodes = nodes.slice(i0, i1 + 1)
			segs = segs.slice(i0, i1)
		cs.append([nodes, segs])
	if cs.is_empty():
		return {"ok": false, "why": "the cut doesn't cross a face from side to side"}
	var n0 := points.size()
	var st := {"n0": n0, "pos": PackedVector3Array(), "pid": {}, "ins": {}, "face_pts": {}}
	var chords := {}   # face -> [[points along the cut], ...]
	var seed := {}     # face -> one of its triangles
	var cut := PackedInt32Array()
	for c in cs:
		var nodes: Array = c[0]
		var segs: PackedInt32Array = c[1]
		var cur := PackedInt32Array()
		var cur_f := -1
		for i in segs.size():
			var x: Dictionary = nodes[i]
			var y: Dictionary = nodes[i + 1]
			var t := segs[i]
			if t < 0:
				cur = PackedInt32Array()
				if x["k"] == 0 and y["k"] == 0:
					var e := edge(x["p"], y["p"])
					if e >= 0:
						cut.append(x["p"])
						cut.append(y["p"])
						if edge_inner[e]:   # (a face's diagonal: the face split along it)
							_add_chord(chords, seed, tri_face[edge_tris[e * 2]], edge_tris[e * 2], PackedInt32Array([x["p"], y["p"]]))
				continue
			var f := tri_face[t]
			if cur.is_empty() or f != cur_f:
				cur = PackedInt32Array([_cut_point(x, st)])
				cur_f = f
			if _border(y):
				cur.append(_cut_point(y, st))
				_add_chord(chords, seed, f, t, cur)
				for j in cur.size() - 1:
					cut.append(cur[j])
					cut.append(cur[j + 1])
				cur = PackedInt32Array()
			elif y["k"] == 2:
				cur.append(_cut_point(y, st))
	# the faces beside the edges that get points
	var ins: Dictionary = st["ins"]
	for e in ins:
		for t in edge_tri_list(e):
			var f := tri_face[t]
			if not chords.has(f):
				chords[f] = []
				seed[f] = t
	if chords.is_empty():
		return {"ok": false, "why": "nothing to cut"}
	# each face made again (worked out first: nothing changes if one can't be)
	var new_pos: PackedVector3Array = st["pos"]
	var plans := []
	for f in chords:
		var plan := _replan(f, seed[f], chords[f], st)
		if plan.is_empty():
			return {"ok": false, "why": "a face it crosses isn't a simple outline"}
		plans.append(plan)
	_apply_plans(plans, new_pos, n0)
	var news := PackedInt32Array()
	for i in new_pos.size():
		news.append(n0 + i)
	return {"ok": true, "cut": cut, "points": news}


## Faces made again by `plans` (_replan / dissolve: each {"si", "old" triangles, "tris" new
## (points), "piece", "f", "pmap", "spec"}), with points `new_pos` (from `n0`) added; the
## triangles `also` (their faces changed only) patched too. A plan with fewer triangles than
## it had lets the rest go.
func _apply_plans(plans: Array, new_pos: PackedVector3Array, n0: int, also := PackedInt32Array()) -> void:
	points.append_array(new_pos)
	var nv0 := []
	for s: Surf in surfs:
		nv0.append(s.count())
	var memo := {}
	var changed := PackedInt32Array()
	var added := []
	var removed := PackedInt32Array()
	for plan in plans:
		var si: int = plan["si"]
		var s: Surf = surfs[si]
		var vmap: Dictionary = plan["pmap"]
		var spec: Dictionary = plan["spec"]
		for p in spec:
			var sp: Array = spec[p]
			var key: Vector4i
			var v := -1
			if sp[0] == "l":
				var va: int = sp[1]
				var vb: int = sp[2]
				var f: float = sp[3]
				if va > vb:
					var tmp := va; va = vb; vb = tmp
					f = 1.0 - f
				key = Vector4i(si, va, vb, p)
				v = memo.get(key, -1)
				if v < 0:
					v = s.blend_vertex(PackedInt32Array([va, vb]), PackedFloat32Array([1.0 - f, f]), p)
			else:
				key = Vector4i(si, -1, -1, p)
				v = memo.get(key, -1)
				if v < 0:
					var t: int = sp[1]
					var i := tri_at[t]
					var vs := PackedInt32Array([s.idx[i], s.idx[i + 1], s.idx[i + 2]])
					var w := Geometry3D.get_triangle_barycentric_coords(new_pos[p - n0], points[tris[t * 3]], points[tris[t * 3 + 1]], points[tris[t * 3 + 2]])
					v = s.blend_vertex(vs, PackedFloat32Array([w.x, w.y, w.z]), p)
			if not memo.has(key):
				s.pos[v] = new_pos[p - n0]
				memo[key] = v
			vmap[p] = v
		var old: PackedInt32Array = plan["old"]
		var nt: PackedInt32Array = plan["tris"]
		var piece: PackedInt32Array = plan["piece"]
		var fid := {0: int(plan["f"])}
		for k in nt.size() / 3:
			if not fid.has(piece[k]):
				fid[piece[k]] = face_n
				face_n += 1
				face_live += 1
			var f: int = fid[piece[k]]
			var a: int = vmap[nt[k * 3]]
			var b: int = vmap[nt[k * 3 + 1]]
			var c: int = vmap[nt[k * 3 + 2]]
			if k < old.size():
				var i := tri_at[old[k]]
				s.idx[i] = a
				s.idx[i + 1] = b
				s.idx[i + 2] = c
				s.face[i / 3] = f
				changed.append(old[k])
			else:
				s.idx.append_array(PackedInt32Array([a, b, c]))
				s.face.append(f)
				added.append([si, s.idx.size() - 3])
		for k in range(nt.size() / 3, old.size()):
			removed.append(old[k])
	for t in also:
		if not changed.has(t):
			changed.append(t)
	if not _patch(changed, added, removed, n0, nv0):
		var kill := {}
		for t in removed:
			if not kill.has(tri_surf[t]):
				kill[tri_surf[t]] = {}
			kill[tri_surf[t]][tri_at[t]] = true
		for si in kill:
			(surfs[si] as Surf).drop_tris(kill[si])
		derive()


func _add_chord(chords: Dictionary, seed: Dictionary, f: int, t: int, ch: PackedInt32Array) -> void:
	if not chords.has(f):
		chords[f] = []
		seed[f] = t
	(chords[f] as Array).append(ch)


## The point of node `x` in the cut being made (st: its new points so far).
func _cut_point(x: Dictionary, st: Dictionary) -> int:
	if x["k"] == 0:
		return x["p"]
	var key := _node_key(x)
	var pid: Dictionary = st["pid"]
	if pid.has(key):
		return pid[key]
	var pos: PackedVector3Array = st["pos"]
	var p: int = int(st["n0"]) + pos.size()
	pos.append(x["pos"])
	pid[key] = p
	if x["k"] == 1:
		var ins: Dictionary = st["ins"]
		if not ins.has(x["e"]):
			ins[x["e"]] = []
		(ins[x["e"]] as Array).append([float(x["t"]), p])
	else:
		(st["face_pts"] as Dictionary)[p] = int(x["tri"])
	return p


## Face `f` (one of its triangles: `seed_t`) made again: its outline with the cut's new
## points on its sides, split along `chs` (point runs from side to side), triangulated.
## {"f", "si", "old": its triangles, "tris": the new ones (points), "piece": each one's part
## of the split face, "pmap": point -> vertex, "spec": new point -> how its vertex is made}.
func _replan(f: int, seed_t: int, chs: Array, st: Dictionary) -> Dictionary:
	var n0: int = st["n0"]
	var new_pos: PackedVector3Array = st["pos"]
	var ins: Dictionary = st["ins"]
	var face_pts: Dictionary = st["face_pts"]
	var pt := poly_tris(seed_t)
	var si := tri_surf[seed_t]
	var s: Surf = surfs[si]
	var pmap := {}
	for t in pt:
		for k in 3:
			var v := s.idx[tri_at[t] + k]
			pmap[s.vp[v]] = v
	var loop := _loop_of(pt)
	if loop.is_empty():
		return {}
	var ring := PackedInt32Array()
	var spec := {}
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		ring.append(a)
		var e := edge(a, b)
		if ins.has(e):
			var lst: Array = (ins[e] as Array).duplicate()
			lst.sort_custom(func(x, y): return x[0] < y[0])
			if edges[e * 2] != a:
				lst.reverse()
			for it in lst:
				ring.append(it[1])
				spec[it[1]] = ["l", pmap[edges[e * 2]], pmap[edges[e * 2 + 1]], it[0]]
	var pos := func(p: int) -> Vector3: return points[p] if p < n0 else new_pos[p - n0]
	# the face's plane, as 2D
	var nn := Vector3.ZERO
	for i in ring.size():
		var a: Vector3 = pos.call(ring[i])
		var b: Vector3 = pos.call(ring[(i + 1) % ring.size()])
		nn += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if nn.length_squared() < 1e-30:
		return {}
	nn = nn.normalized()
	var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := nn.cross(u)
	var flat := func(p: int) -> Vector2:
		var q: Vector3 = pos.call(p)
		return Vector2(q.dot(u), q.dot(w))
	var pieces := [ring]
	for ch: PackedInt32Array in chs:
		for p in ch:
			if face_pts.has(p):
				if not pt.has(face_pts[p]):
					return {}
				spec[p] = ["b", face_pts[p]]
		pieces = _split(pieces, ch, flat)
	var out := PackedInt32Array()
	var piece := PackedInt32Array()
	for pi in pieces.size():
		var poly: PackedInt32Array = pieces[pi]
		var p2 := PackedVector2Array()
		for p in poly:
			p2.append(flat.call(p))
		var tr := ear_clip(p2)
		for k in range(0, tr.size(), 3):
			out.append(poly[tr[k]])
			out.append(poly[tr[k + 1]])
			out.append(poly[tr[k + 2]])
			piece.append(pi)
	return {"f": f, "si": si, "old": pt, "tris": out, "piece": piece, "pmap": pmap, "spec": spec}


## The outlines `pieces` with the one holding chord `ch` (from one of its corners to another)
## split in two along it.
static func _split(pieces: Array, ch: PackedInt32Array, flat: Callable) -> Array:
	var u := ch[0]
	var v := ch[ch.size() - 1]
	if u == v or ch.size() < 2:
		return pieces
	var mids := ch.slice(1, ch.size() - 1)
	var probe: Vector2 = (flat.call(u) as Vector2).lerp(flat.call(ch[1]), 0.5)
	for i in pieces.size():
		var poly: PackedInt32Array = pieces[i]
		var iu := poly.find(u)
		var iv := poly.find(v)
		if iu < 0 or iv < 0:
			continue
		var m := poly.size()
		if mids.is_empty() and ((iu + 1) % m == iv or (iv + 1) % m == iu):
			return pieces   # (along a side already)
		var p2 := PackedVector2Array()
		for p in poly:
			p2.append(flat.call(p))
		if not Geometry2D.is_point_in_polygon(probe, p2):
			continue
		var a := PackedInt32Array()
		var j := iu
		while true:
			a.append(poly[j])
			if j == iv:
				break
			j = (j + 1) % m
		var rev := mids.duplicate()
		rev.reverse()
		a.append_array(rev)
		var b := PackedInt32Array()
		j = iv
		while true:
			b.append(poly[j])
			if j == iu:
				break
			j = (j + 1) % m
		b.append_array(mids)
		var out := pieces.duplicate()
		out[i] = a
		out.append(b)
		return out
	return pieces


## Triangles (index triples into `p`) of the simple polygon `p` (counter-clockwise), corners
## in a straight line along a side included (never a corner of a sliver).
static func ear_clip(p: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if p.size() < 3:
		return out
	var box := Rect2(p[0], Vector2.ZERO)
	for q in p:
		box = box.expand(q)
	var tol := maxf(box.size.length_squared(), 1e-12) * 1e-10
	var idx := PackedInt32Array()
	for i in p.size():
		idx.append(i)
	while idx.size() > 3:
		var m := idx.size()
		var found := -1
		var best := -1.0
		for i in m:
			var ia := idx[(i + m - 1) % m]
			var ib := idx[i]
			var ic := idx[(i + 1) % m]
			var a := p[ia]
			var b := p[ib]
			var c := p[ic]
			if (b - a).cross(c - b) <= tol:
				continue
			var ok := true
			for j in m:
				var iq := idx[j]
				if iq == ia or iq == ib or iq == ic:
					continue
				var q := p[iq]
				if q == a or q == b or q == c:
					continue
				if (b - a).cross(q - a) >= -tol and (c - b).cross(q - b) >= -tol and (a - c).cross(q - c) >= -tol:
					ok = false
					break
			if not ok:
				continue
			# (the fattest ear: its smallest angle)
			var qa := minf(minf(absf((b - a).angle_to(c - a)), absf((c - b).angle_to(a - b))), absf((a - c).angle_to(b - c)))
			if qa > best:
				best = qa
				found = i
			if m > 48:
				break
		if found < 0:
			break
		out.append(idx[(found + m - 1) % m])
		out.append(idx[found])
		out.append(idx[(found + 1) % m])
		idx.remove_at(found)
	if idx.size() == 3:
		if (p[idx[1]] - p[idx[0]]).cross(p[idx[2]] - p[idx[1]]) > tol:
			out.append_array(idx)
	elif idx.size() > 3:
		# (stuck: what's left as the engine triangulates it)
		var rest := PackedVector2Array()
		for i in idx:
			rest.append(p[i])
		for i in Geometry2D.triangulate_polygon(rest):
			out.append(idx[i])
	return out


## The derived arrays patched for a cut: triangles `changed` (rewritten in place) and
## `added` ([surface, index] - appended to their surfaces), the points from `n_old` on
## new (their vertices: those from `nv0` - each surface's count before - on). Edges
## dropped and added, faces' insides, neighbours - only where they changed. False:
## can't (an edge of three triangles or more): derive() instead.
func _patch(changed: PackedInt32Array, added: Array, removed: PackedInt32Array, n_old: int, nv0: Array) -> bool:
	var n := points.size()
	# the new points' vertices (first: nothing changed if it can't)
	var per := []
	for i in n - n_old:
		per.append(PackedInt32Array())
	for si in surfs.size():
		var s: Surf = surfs[si]
		for v in range(nv0[si], s.count()):
			var p := s.vp[v] - n_old
			if p < 0:
				return false
			var l: PackedInt32Array = per[p]
			per[p] = PackedInt32Array()
			l.append((si << SHIFT) | v)
			per[p] = l
	pv_start = pv_start.duplicate()
	pv = pv.duplicate()
	for l: PackedInt32Array in per:
		pv.append_array(l)
		pv_start.append(pv.size())
	tris = tris.duplicate()
	tri_surf = tri_surf.duplicate()
	tri_at = tri_at.duplicate()
	tri_face = tri_face.duplicate()
	tri_edges = tri_edges.duplicate()
	edges = edges.duplicate()
	edge_of = edge_of.duplicate()
	edge_tris = edge_tris.duplicate()
	edge_tn = edge_tn.duplicate()
	edge_inner = edge_inner.duplicate()
	edge_more = edge_more.duplicate(true)
	var add_nb := {}
	var del_nb := {}
	var dead := {}
	var touched := {}
	for t in changed + removed:
		for k in 3:
			var e := tri_edges[t * 3 + k]
			if e < 0:
				continue
			_unlink(e, t)
			touched[e] = true
			if edge_tn[e] == 0:
				dead[e] = true
	var all := changed.duplicate()
	for t in changed:
		_set_tri(t)
	for ad in added:
		var t := tri_count()
		tris.append_array(PackedInt32Array([0, 0, 0]))
		tri_surf.append(ad[0])
		tri_at.append(ad[1])
		tri_face.append(0)
		tri_edges.append_array(PackedInt32Array([-1, -1, -1]))
		_set_tri(t)
		all.append(t)
	for t in all:
		for k in 3:
			var a := tris[t * 3 + k]
			var b := tris[t * 3 + (k + 1) % 3]
			if a == b:
				tri_edges[t * 3 + k] = -1
				continue
			var lo := mini(a, b)
			var hi := maxi(a, b)
			var e: int = edge_of.get(lo * KEY + hi, -1)
			if e < 0:
				e = edge_tn.size()
				edge_of[lo * KEY + hi] = e
				edges.append(lo)
				edges.append(hi)
				edge_tris.append(t)
				edge_tris.append(-1)
				edge_tn.append(1)
				edge_inner.append(0)
				_nb(add_nb, lo, hi)
				_nb(add_nb, hi, lo)
			else:
				if edge_tn[e] == 0:
					edge_tris[e * 2] = t
					dead.erase(e)
				elif edge_tn[e] == 1:
					edge_tris[e * 2 + 1] = t
				else:
					_nb(edge_more, e, t)
				edge_tn[e] += 1
			tri_edges[t * 3 + k] = e
			touched[e] = true
	# triangles let go: each surface's last one moved into its place, and the last triangle
	# into its place in the derived arrays
	if not removed.is_empty():
		var smap := {}   # surface -> {index: triangle}
		for t in removed:
			smap[tri_surf[t]] = {}
		for t in tri_count():
			if smap.has(tri_surf[t]):
				smap[tri_surf[t]][tri_at[t]] = t
		var gone_t := Array(removed)
		gone_t.sort()
		gone_t.reverse()
		for r: int in gone_t:
			var si := tri_surf[r]
			var sm: Dictionary = smap[si]
			var s: Surf = surfs[si]
			var slot := tri_at[r]
			var last := s.idx.size() - 3
			if slot != last:
				var u: int = sm[last]
				for k in 3:
					s.idx[slot + k] = s.idx[last + k]
				s.face[slot / 3] = s.face[last / 3]
				tri_at[u] = slot
				sm[slot] = u
			sm.erase(last)
			s.idx.resize(last)
			s.face.resize(last / 3)
			var lt := tri_count() - 1
			if r != lt:
				for k in 3:
					tris[r * 3 + k] = tris[lt * 3 + k]
					tri_edges[r * 3 + k] = tri_edges[lt * 3 + k]
				tri_surf[r] = tri_surf[lt]
				tri_at[r] = tri_at[lt]
				tri_face[r] = tri_face[lt]
				if smap.has(tri_surf[r]):
					smap[tri_surf[r]][tri_at[r]] = r
				for k in 3:
					var e := tri_edges[r * 3 + k]
					if e < 0:
						continue
					if edge_tris[e * 2] == lt:
						edge_tris[e * 2] = r
					elif edge_tris[e * 2 + 1] == lt:
						edge_tris[e * 2 + 1] = r
					elif edge_more.has(e):
						var m: PackedInt32Array = edge_more[e]
						var at := m.find(lt)
						if at >= 0:
							m[at] = r
			tris.resize(lt * 3)
			tri_edges.resize(lt * 3)
			tri_surf.resize(lt)
			tri_at.resize(lt)
			tri_face.resize(lt)
	for e in touched:
		if not dead.has(e):
			edge_inner[e] = 1 if edge_tn[e] == 2 and tri_face[edge_tris[e * 2]] == tri_face[edge_tris[e * 2 + 1]] else 0
	# edges no triangle has any more: the last edge moved into each one's place
	var gone: Array = dead.keys()
	gone.sort()
	gone.reverse()
	for e: int in gone:
		var a := edges[e * 2]
		var b := edges[e * 2 + 1]
		_nb(del_nb, a, b)
		_nb(del_nb, b, a)
		edge_of.erase(a * KEY + b)
		var last := edge_tn.size() - 1
		if e != last:
			var la := edges[last * 2]
			var lb := edges[last * 2 + 1]
			edges[e * 2] = la
			edges[e * 2 + 1] = lb
			edge_of[la * KEY + lb] = e
			edge_tris[e * 2] = edge_tris[last * 2]
			edge_tris[e * 2 + 1] = edge_tris[last * 2 + 1]
			edge_tn[e] = edge_tn[last]
			edge_inner[e] = edge_inner[last]
			if edge_more.has(last):
				edge_more[e] = edge_more[last]
				edge_more.erase(last)
			for t in edge_tri_list(e):
				if t >= 0:
					for k in 3:
						if tri_edges[t * 3 + k] == last:
							tri_edges[t * 3 + k] = e
		edges.resize(last * 2)
		edge_tris.resize(last * 2)
		edge_tn.resize(last)
		edge_inner.resize(last)
	# neighbours: the lists of the points whose edges changed made again, the rest copied
	var chg := {}
	for p in add_nb:
		chg[p] = true
	for p in del_nb:
		chg[p] = true
	var order: Array = chg.keys()
	order.sort()
	order.append(n)
	var old_n := adj_start.size() - 1
	var na := PackedInt32Array()
	var ns := PackedInt32Array()
	ns.resize(n + 1)
	var run := 0
	for c: int in order:
		var hi := mini(c, old_n)
		if hi > run:
			var shift := na.size() - adj_start[run]
			na.append_array(adj.slice(adj_start[run], adj_start[hi]))
			for p in range(run, hi):
				ns[p + 1] = adj_start[p + 1] + shift
		for p in range(maxi(run, old_n), c):
			ns[p + 1] = ns[p]
		if c >= n:
			break
		var lst := PackedInt32Array()
		if c < old_n:
			lst = adj.slice(adj_start[c], adj_start[c + 1])
		for q in del_nb.get(c, PackedInt32Array()):
			var at := lst.find(q)
			if at >= 0:
				lst.remove_at(at)
		lst.append_array(add_nb.get(c, PackedInt32Array()))
		na.append_array(lst)
		ns[c + 1] = na.size()
		run = c + 1
	adj = na
	adj_start = ns
	_topo_ids += 1
	topo = _topo_ids
	return true


## Triangle `t` let go of edge `e`.
func _unlink(e: int, t: int) -> void:
	var more: PackedInt32Array = edge_more.get(e, PackedInt32Array())
	var slot := -1
	if edge_tris[e * 2] == t:
		slot = 0
	elif edge_tris[e * 2 + 1] == t:
		slot = 1
	if slot < 0:
		var at := more.find(t)
		if at < 0:
			return
		more.remove_at(at)
	elif not more.is_empty():
		edge_tris[e * 2 + slot] = more[more.size() - 1]
		more.remove_at(more.size() - 1)
	elif slot == 0:
		edge_tris[e * 2] = edge_tris[e * 2 + 1]
		edge_tris[e * 2 + 1] = -1
	else:
		edge_tris[e * 2 + 1] = -1
	if edge_more.has(e) and more.is_empty():
		edge_more.erase(e)
	edge_tn[e] -= 1


func _set_tri(t: int) -> void:
	var s: Surf = surfs[tri_surf[t]]
	var i := tri_at[t]
	for k in 3:
		tris[t * 3 + k] = s.vp[s.idx[i + k]]
	tri_face[t] = s.face[i / 3]


static func _nb(d: Dictionary, p: int, q: int) -> void:
	if not d.has(p):
		d[p] = PackedInt32Array()
	var l: PackedInt32Array = d[p]
	l.append(q)


## A ray-test mesh of triangles `tr` over `pts` (TriangleMesh's face_index = the triangle) -
## for a worker thread (copies given).
static func make_triangle_mesh(pts: PackedVector3Array, tr: PackedInt32Array) -> TriangleMesh:
	var f := PackedVector3Array()
	f.resize(tr.size())
	for i in tr.size():
		f[i] = pts[tr[i]]
	var tm := TriangleMesh.new()
	tm.create_from_faces(f)
	return tm



# --- dissolve -------------------------------------------------------------------
# Faces joined into one and points taken out, the faces round them filled again:
# points `pts` (the faces round each made one, the point gone - one in a straight run
# along a side just leaves it), edges `eds` (the two faces either side made one: the
# triangles as they are) and the faces of triangles `tsel` (those side by side made one,
# the points inside them gone). Points left in a straight run along a side, or inside a
# face, by the joins go too. A face made again is its outline without the points gone,
# triangulated (its corners keep their vertices: UVs, normals, weights). Only the faces
# changed are patched. {"ok", "why", "keep": an edge (point pair) on each face made}.
func dissolve(pts: PackedInt32Array, eds: PackedInt32Array, tsel: PackedByteArray) -> Dictionary:
	var parent := {}   # face -> the face it's joined to (only the faces touched)
	var seed := {}     # face -> one of its triangles
	var cand := {}
	var straight := {}   # (points an edge dissolved ends at: in a straight run after, they go too)
	var rem := {}
	var join := func(t0: int, t1: int) -> void:
		seed[tri_face[t0]] = t0
		seed[tri_face[t1]] = t1
		var r0 := _froot(parent, tri_face[t0])
		var r1 := _froot(parent, tri_face[t1])
		if r0 != r1:
			parent[r1] = r0
	# faces side by side
	var fsel := {}
	for t in mini(tsel.size(), tri_count()):
		if tsel[t]:
			fsel[tri_face[t]] = true
	for t in mini(tsel.size(), tri_count()):
		if not tsel[t]:
			continue
		for k in 3:
			var e := tri_edges[t * 3 + k]
			if e >= 0 and edge_tn[e] == 2 and not edge_inner[e]:
				var t0 := edge_tris[e * 2]
				var t1 := edge_tris[e * 2 + 1]
				if fsel.has(tri_face[t0]) and fsel.has(tri_face[t1]) and tri_surf[t0] == tri_surf[t1]:
					join.call(t0, t1)
					cand[edges[e * 2]] = true
					cand[edges[e * 2 + 1]] = true
	# edges
	for e in eds:
		if e < 0 or e >= edge_count() or edge_tn[e] != 2 or edge_inner[e]:
			continue
		var t0 := edge_tris[e * 2]
		var t1 := edge_tris[e * 2 + 1]
		if tri_surf[t0] != tri_surf[t1]:
			continue
		join.call(t0, t1)
		cand[edges[e * 2]] = true
		cand[edges[e * 2 + 1]] = true
		straight[edges[e * 2]] = true
		straight[edges[e * 2 + 1]] = true
	# points
	for p in pts:
		if p < 0 or p >= points.size() or adj_start[p] == adj_start[p + 1]:
			continue
		var vis := _shown_at(p, parent)
		if vis.size() == 2 and _straight(p, vis[0], vis[1]):
			rem[p] = true   # (in a straight run: it just leaves the side)
			continue
		# (the faces round it made one - those of each surface: a point two layers share, each layer's)
		var first := {}
		for t in tris_around(p):
			var si := tri_surf[t]
			seed[tri_face[t]] = t
			if not first.has(si):
				first[si] = t
			else:
				join.call(first[si], t)
		rem[p] = true
	# points the joins left inside a face, or in a straight run along a side
	for p in cand:
		if rem.has(p):
			continue
		var vis := _shown_at(p, parent)
		if vis.is_empty() or (straight.has(p) and vis.size() == 2 and _straight(p, vis[0], vis[1])):
			rem[p] = true
	# the faces to make: those joined, and those a point goes from
	for p in rem:
		for t in tris_around(p):
			if not seed.has(tri_face[t]):
				seed[tri_face[t]] = t
	var members := {}
	for f in seed:
		var r := _froot(parent, f)
		if not members.has(r):
			members[r] = []
		(members[r] as Array).append(f)
	if members.is_empty():
		return {"ok": false, "why": "nothing to dissolve there"}
	var plans := []
	var also := PackedInt32Array()
	var keep := []
	var joined := 0
	for r in members:
		var rt := PackedInt32Array()
		for f in members[r]:
			rt.append_array(poly_tris(seed[f]))
		joined += (members[r] as Array).size() - 1
		var loop := _loop_of_set(rt)
		if loop.size() < 3:
			return {"ok": false, "why": "the faces joined wouldn't make one simple outline (a hole in them?)"}
		var gone := false
		for t in rt:
			for k in 3:
				gone = gone or rem.has(tris[t * 3 + k])
		if not gone:
			# (only joined: the triangles stay, all in one face)
			for t in rt:
				(surfs[tri_surf[t]] as Surf).face[tri_at[t] / 3] = r
				also.append(t)
			keep.append([loop[0], loop[1]])
			continue
		var ring := PackedInt32Array()
		for q in loop:
			if not rem.has(q):
				ring.append(q)
		if ring.size() < 3:
			return {"ok": false, "why": "too few corners would be left"}
		var si := tri_surf[rt[0]]
		var s: Surf = surfs[si]
		var pmap := {}
		for t in rt:
			for k in 3:
				var v := s.idx[tri_at[t] + k]
				if not pmap.has(s.vp[v]):
					pmap[s.vp[v]] = v
		var nn := Vector3.ZERO
		for i in ring.size():
			var a := points[ring[i]]
			var b := points[ring[(i + 1) % ring.size()]]
			nn += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		if nn.length_squared() < 1e-30:
			return {"ok": false, "why": "a face would have no area"}
		nn = nn.normalized()
		var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := nn.cross(u)
		var p2 := PackedVector2Array()
		for q in ring:
			p2.append(Vector2(points[q].dot(u), points[q].dot(w)))
		var tr := ear_clip(p2)
		if tr.size() / 3 != ring.size() - 2:
			return {"ok": false, "why": "a face joined is too bent to fill again"}
		var out := PackedInt32Array()
		var piece := PackedInt32Array()
		for k in tr.size():
			out.append(ring[tr[k]])
		piece.resize(tr.size() / 3)
		plans.append({"f": r, "si": si, "old": rt, "tris": out, "piece": piece, "pmap": pmap, "spec": {}})
		keep.append([ring[0], ring[1]])
	_apply_plans(plans, PackedVector3Array(), points.size(), also)
	unused = unused or not rem.is_empty()
	face_live -= joined
	_wire_topo = -1
	return {"ok": true, "keep": keep, "points": rem.size()}


static func _froot(parent: Dictionary, f: int) -> int:
	var r := f
	while parent.has(r) and parent[r] != r:
		r = parent[r]
	while parent.has(f) and parent[f] != r:   # (shortened)
		var nx: int = parent[f]
		parent[f] = r
		f = nx
	return r


## The edges at point `p` shown with faces joined as in `parent` (between two of them,
## or on the border): their other points.
func _shown_at(p: int, parent: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in range(adj_start[p], adj_start[p + 1]):
		var q := adj[k]
		var e := edge(p, q)
		if edge_tn[e] != 2:
			out.append(q)
		elif _froot(parent, tri_face[edge_tris[e * 2]]) != _froot(parent, tri_face[edge_tris[e * 2 + 1]]):
			out.append(q)
	return out


func _straight(p: int, a: int, b: int) -> bool:
	return (points[a] - points[p]).normalized().dot((points[b] - points[p]).normalized()) < STRAIGHT


## The outline of triangles `pt` (one face or several side by side), in order round it
## (the triangles' way round); empty if it isn't one simple outline.
func _loop_of_set(pt: PackedInt32Array) -> PackedInt32Array:
	var inset := {}
	for t in pt:
		inset[t] = true
	var nxt := {}
	for t in pt:
		for k in 3:
			var e := tri_edges[t * 3 + k]
			if e >= 0:
				var inside := false
				for o in edge_tri_list(e):   # (another of the set on it: inside - a layer's own, where layers share edges)
					if o != t and inset.has(o):
						inside = true
				if inside:
					continue
			var a := tris[t * 3 + k]
			if nxt.has(a):
				return PackedInt32Array()
			nxt[a] = tris[t * 3 + (k + 1) % 3]
	if nxt.is_empty():
		return PackedInt32Array()
	var out := PackedInt32Array()
	var p: int = nxt.keys()[0]
	while out.size() <= nxt.size():
		out.append(p)
		p = nxt.get(p, -1)
		if p < 0:
			return PackedInt32Array()
		if p == out[0]:
			break
	return out if out.size() == nxt.size() else PackedInt32Array()



# --- symmetrize topology -----------------------------------------------------------

## The `positive` side of `axis` (the part's own plane through its origin) made the whole:
## the faces crossing the plane cut along it (the knife's slice: new points on the edges,
## their attributes mixed), the other side deleted, the kept side mirrored onto it (faces
## turned the right way round, normals mirrored, UVs as they are, bone weights onto each
## bone's twin by `bones_twin`) and welded along the seam (points within `tol` of the plane
## put on it and shared). Each face stays a face. {"ok", "why", "new": the points of the new half}.
func symmetrize_topology(axis: int, positive := true, tol := -1.0, bones_twin := PackedInt32Array()) -> Dictionary:
	if tol < 0.0:
		tol = maxf(aabb().size.length() * 0.0005, 1e-5)
	var sgn := 1.0 if positive else -1.0
	var n := Vector3.ZERO
	n[axis] = 1.0
	# points next to the plane put on it (they're the seam)
	for i in points.size():
		if absf(points[i][axis]) <= tol and points[i][axis] != 0.0:
			points[i][axis] = 0.0
	sync()
	# the faces crossing it cut along it
	var chains := knife_slice(Vector3.ZERO, n, [])
	if not chains.is_empty():
		knife_apply(chains)
	# the other side gone (and anything flat on the plane)
	var kill := PackedByteArray()
	kill.resize(tri_count())
	var keep := 0
	for t in tri_count():
		var c := (points[tris[t * 3]][axis] + points[tris[t * 3 + 1]][axis] + points[tris[t * 3 + 2]][axis]) / 3.0
		if c * sgn <= tol * 0.01:
			kill[t] = 1
		else:
			keep += 1
	if keep == 0:
		return {"ok": false, "why": "nothing on the %s%s side to keep" % ["+" if positive else "-", "XYZ"[axis]]}
	if kill.has(1):
		# (as delete_tris, without working the derived arrays out: the mirror does that)
		var st := _starts(kill)
		for si in surfs.size():
			if not (st[si] as PackedInt32Array).is_empty():
				var d := {}
				for i in st[si]:
					d[i] = true
				(surfs[si] as Surf).drop_tris(d)
		compact()
	# mirrored onto it, welded along the seam
	var axes := [false, false, false]
	axes[axis] = true
	apply_mirror(axes, tol * 0.5, true, false, bones_twin)
	unused = false
	var out := PackedInt32Array()
	for i in points.size():
		if points[i][axis] * sgn < -tol * 0.5:
			out.append(i)
	return {"ok": true, "new": out}
