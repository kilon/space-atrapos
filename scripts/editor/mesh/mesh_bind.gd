extends RefCounted
## Parts bound to a character's skeleton (the mesh editor's Bind): a part added beside a
## skinned Body is skinned to the same skeleton - each vertex weighted to its nearest
## bones (up to four, by inverse distance squared to each bone's segment, normalised), or
## all to one bone - so it moves with the character's animations. Its vertices are put
## where its skin draws them as they are on screen now: in the character's T-pose (the
## part then carries the Body's T-pose metas, and is turned back with it when saved) or
## in the pose the skeleton has.

const TPose := preload("res://scripts/editor/mesh/tpose.gd")
const MAX_BONES := 4


## The model's rig: the skinned part (named Body if there is one) among `parts` - {"body",
## "skel", "skin", "tpose": T-posed, "g": each bone's global pose (the skeleton's space,
## as drawn now), "mats": each skin bind's matrix (pose * bind)} - or {} (none).
static func rig_of(parts: Array) -> Dictionary:
	var body: MeshInstance3D = null
	for p: MeshInstance3D in parts:
		var skinned := p.has_meta("tpose") or (p.skin != null and TPose.skeleton_of(p) != null)
		if skinned and not p.has_meta("bound_part") and (body == null or str(p.name) == "Body"):
			body = p
	if body == null:
		return {}
	var tp := body.has_meta("tpose")
	var skel: Skeleton3D = body.get_node_or_null(body.get_meta("tpose_skel")) as Skeleton3D if tp else TPose.skeleton_of(body)
	var skin: Skin = body.get_meta("tpose_skin") if tp else body.skin
	if skel == null or skin == null:
		return {}
	var g: Array
	var mats: Array
	if tp:
		g = TPose.pose(skel)
		mats = body.get_meta("tpose_mats")
	else:
		g = []
		for i in skel.get_bone_count():
			g.append(skel.get_bone_global_pose(i))
		mats = TPose.matrices(body, skel, g)
	return {"body": body, "skel": skel, "skin": skin, "tpose": tp, "g": g, "mats": mats}


## Each skin bind's bone (-1: none) and its name.
static func binds(rig: Dictionary) -> Array:
	var skin: Skin = rig["skin"]
	var skel: Skeleton3D = rig["skel"]
	var out := []
	for k in skin.get_bind_count():
		var b := skin.get_bind_bone(k)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(k))
		out.append([b, skel.get_bone_name(b) if b >= 0 else str(skin.get_bind_name(k))])
	return out


## Each bind's bone as a segment (skeleton space): [from, to] - to its first child, or (a
## bone at the end) along its own axis.
static func _segments(rig: Dictionary) -> Array:
	var skel: Skeleton3D = rig["skel"]
	var g: Array = rig["g"]
	var out := []
	for bk in binds(rig):
		var b: int = bk[0]
		if b < 0:
			out.append([])
			continue
		var a: Vector3 = (g[b] as Transform3D).origin
		var e := a
		var kids := skel.get_bone_children(b)
		if not kids.is_empty():
			e = (g[kids[0]] as Transform3D).origin
		if e.distance_to(a) < 1e-4:
			var p := skel.get_bone_parent(b)
			var l := 0.08 if p < 0 else maxf(0.04, (g[p] as Transform3D).origin.distance_to(a) * 0.5)
			e = a + (g[b] as Transform3D).basis.y.normalized() * l
		out.append([a, e])
	return out


## The bind matrix blend of bones `bs` weights `ws`.
static func _blend(mats: Array, bs: PackedInt32Array, ws: PackedFloat32Array) -> Transform3D:
	var basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var origin := Vector3.ZERO
	for i in bs.size():
		var t: Transform3D = mats[bs[i]]
		basis.x += t.basis.x * ws[i]
		basis.y += t.basis.y * ws[i]
		basis.z += t.basis.z * ws[i]
		origin += t.origin * ws[i]
	return Transform3D(basis, origin)


## Part `p`'s mesh bound to `rig`: each vertex's bones and weights (to its nearest bones, or
## all to skin bind `bind` when >= 0), and its place in the Body's mesh space - where its
## skin draws it now is where it is on screen. Returns the new mesh (the part is then to
## take the Body's global transform, skin and skeleton - or, T-posed, its T-pose metas).
static func bound_mesh(p: MeshInstance3D, rig: Dictionary, bind := -1) -> ArrayMesh:
	var body: MeshInstance3D = rig["body"]
	var skel: Skeleton3D = rig["skel"]
	var mats: Array = rig["mats"]
	var to_skel := skel.global_transform.affine_inverse() * p.global_transform
	var to_body := body.global_transform.affine_inverse() * p.global_transform
	var segs := _segments(rig)
	var names := binds(rig)
	var src: Mesh = p.mesh
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for i in vs.size():
			var q: Vector3 = to_skel * vs[i]
			var bs := PackedInt32Array()
			var ws := PackedFloat32Array()
			if bind >= 0:
				bs.append(bind)
				ws.append(1.0)
			else:
				var near := []   # [distance, bind]
				for k in segs.size():
					var sg: Array = segs[k]
					if sg.is_empty() or str(names[k][1]).to_lower() in TPose.WEAPON_BONES:
						continue
					var d := q.distance_to(Geometry3D.get_closest_point_to_segment(q, sg[0], sg[1]))
					near.append([d, k])
				near.sort_custom(func(x, y): return x[0] < y[0])
				var total := 0.0
				for j in mini(MAX_BONES, near.size()):
					if j > 0 and near[j][0] > near[0][0] * 2.5 + 0.02:
						break   # (only bones about as near as the nearest)
					var w := 1.0 / pow(maxf(near[j][0], 0.005), 2.0)
					bs.append(near[j][1])
					ws.append(w)
					total += w
				for j in ws.size():
					ws[j] /= total
			for j in MAX_BONES:
				bones.append(bs[j] if j < bs.size() else 0)
				weights.append(ws[j] if j < ws.size() else 0.0)
			if rig["tpose"]:
				vs[i] = to_body * vs[i]
				if i < ns.size():
					ns[i] = (to_body.basis * ns[i]).normalized()
			else:
				var m := _blend(mats, bs, ws)
				vs[i] = m.affine_inverse() * q
				if i < ns.size():
					ns[i] = (m.basis.inverse() * (to_skel.basis * ns[i])).normalized()
		a[Mesh.ARRAY_VERTEX] = vs
		if not ns.is_empty():
			a[Mesh.ARRAY_NORMAL] = ns
		a[Mesh.ARRAY_TANGENT] = null
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), a)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(si))
		out.surface_set_name(out.get_surface_count() - 1, src.surface_get_name(si) if src is ArrayMesh else "")
	return out


## A bound part's mesh let go of its bones: its vertices where they're drawn now (in the
## Body's space, the part to keep the Body's global transform), no weights.
static func unbound_mesh(p: MeshInstance3D, rig: Dictionary) -> ArrayMesh:
	var src: Mesh = p.mesh
	var skel: Skeleton3D = rig["skel"]
	var body: MeshInstance3D = rig["body"]
	var mats: Array = rig["mats"]
	var skel_to_body := body.global_transform.affine_inverse() * skel.global_transform
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var per := bones.size() / vs.size() if vs.size() > 0 else 0
		if not rig["tpose"] and per > 0:
			for i in vs.size():
				var m := _blend(mats, bones.slice(i * per, i * per + per), weights.slice(i * per, i * per + per))
				vs[i] = skel_to_body * (m * vs[i])
				if i < ns.size():
					ns[i] = (skel_to_body.basis * (m.basis * ns[i])).normalized()
		a[Mesh.ARRAY_VERTEX] = vs
		if not ns.is_empty():
			a[Mesh.ARRAY_NORMAL] = ns
		a[Mesh.ARRAY_BONES] = null
		a[Mesh.ARRAY_WEIGHTS] = null
		a[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), a)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(si))
		out.surface_set_name(out.get_surface_count() - 1, src.surface_get_name(si) if src is ArrayMesh else "")
	return out


## The skin bind nearest point `at` (global) - for "Bind to bone" with none picked.
static func nearest_bind(rig: Dictionary, at: Vector3) -> int:
	var skel: Skeleton3D = rig["skel"]
	var q := skel.global_transform.affine_inverse() * at
	var best := -1
	var bd := INF
	var segs := _segments(rig)
	for k in segs.size():
		var sg: Array = segs[k]
		if sg.is_empty():
			continue
		var d := q.distance_to(Geometry3D.get_closest_point_to_segment(q, sg[0], sg[1]))
		if d < bd:
			bd = d
			best = k
	return best


## Mesh `m` (no bones) given the bone weights of mesh `src` (skinned, the same shape before it was made
## again - an ECurve solid converted from it): each point the weights of `src`'s nearest point. null -
## `src` has no weights.
static func transfer_weights(m: Mesh, src: Mesh) -> ArrayMesh:
	var ms := []
	var mats := []
	for si in m.get_surface_count():
		ms.append(m.surface_get_arrays(si))
		mats.append(m.surface_get_material(si))
	var ss := []
	for si in src.get_surface_count():
		ss.append(src.surface_get_arrays(si))
	var out := weighted_arrays(ms, ss)
	return mesh_of(out, mats)


## A mesh from surfaces' arrays (`out`: [[arrays, per (bones a point)]...]) and their materials.
static func mesh_of(out: Array, mats: Array) -> ArrayMesh:
	if out.is_empty():
		return null
	var m := ArrayMesh.new()
	for i in out.size():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out[i][0], [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if int(out[i][1]) == 8 else 0)
		m.surface_set_material(i, mats[i] if i < mats.size() else null)
	return m


## (safe on a worker: arrays only) Surfaces `ms` given the bone weights of surfaces `ss` - each point those
## of the nearest point of `ss` (found in a grid of cells). [[arrays, per]...] ([] - `ss` has none).
static func weighted_arrays(ms: Array, ss: Array) -> Array:
	var sv := PackedVector3Array()
	var sb := PackedInt32Array()
	var sw := PackedFloat32Array()
	var per := 4
	for a in ss:
		if a[Mesh.ARRAY_BONES] == null or a[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		per = b.size() / maxi(v.size(), 1)
		sv.append_array(v)
		sb.append_array(b)
		sw.append_array(w)
	if sv.is_empty() or per <= 0:
		return []
	var box := AABB(sv[0], Vector3.ZERO)
	for q in sv:
		box = box.expand(q)
	var cell := maxf(box.get_longest_axis_size() / 24.0, 1e-4)
	var grid := {}
	for i in sv.size():
		var k := Vector3i((sv[i] / cell).floor())
		if not grid.has(k):
			grid[k] = PackedInt32Array()
		grid[k].append(i)
	var out := []
	for a0 in ms:
		var a: Array = (a0 as Array).duplicate()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(v.size() * per)
		weights.resize(v.size() * per)
		for i in v.size():
			var k0 := Vector3i((v[i] / cell).floor())
			var best := -1
			var bd := INF
			for r in 4:   # (rings of cells outwards till one has points)
				for dx in range(-r, r + 1):
					for dy in range(-r, r + 1):
						for dz in range(-r, r + 1):
							if maxi(absi(dx), maxi(absi(dy), absi(dz))) != r:
								continue
							var c = grid.get(k0 + Vector3i(dx, dy, dz))
							if c == null:
								continue
							for j in (c as PackedInt32Array):
								var d := sv[j].distance_squared_to(v[i])
								if d < bd:
									bd = d
									best = j
				if best >= 0:
					break
			if best < 0:
				best = 0
			for k in per:
				bones[i * per + k] = sb[best * per + k]
				weights[i * per + k] = sw[best * per + k]
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights
		out.append([a, per])
	return out
