extends RefCounted
## The mesh editor's T-pose: a character laid out for editing - its arms straight out to
## the sides, its weapon stood beside it - the skinned mesh baked into that pose (each
## vertex by its bones' blend, as the game would draw it), edited as plain geometry, and
## turned back exactly (each vertex by the inverse of its own blend) to the character's
## own pose when saved or when the T-pose is turned off. The weights stay with the
## vertices, so animations play as before. And its weapons: the parts made of weapon
## materials, hidden or shown.

## Arm bones (turned to point straight out to their side), by name.
const ARM := ["upper", "fore", "hand", "finger", "arm", "elbow", "wrist"]
const NOT_ARM := ["armor", "armour", "pauldron"]
## A weapon's bone (stood beside the body) and materials (hidden by Weapons off).
const WEAPON_BONES := ["gun", "weapon", "rifle"]
const WEAPON_MATS := ["gun", "rifle", "bow", "quiver", "axe", "sword", "spear", "blade", "shield", "pistol"]
const NOT_WEAPON := ["gunmetal"]


static func skeleton_of(mi: MeshInstance3D) -> Skeleton3D:
	if mi.skeleton == NodePath(""):
		return null
	return mi.get_node_or_null(mi.skeleton) as Skeleton3D


## The part is a skinned character mesh (it can be T-posed).
static func can(mi: MeshInstance3D) -> bool:
	return mi != null and mi.mesh is ArrayMesh and skeleton_of(mi) != null and not mi.has_meta("tpose")


static func _is_arm(name: String) -> bool:
	var n := name.to_lower()
	for x in NOT_ARM:
		if n.contains(x):
			return false
	for x in ARM:
		if n.contains(x):
			return true
	return false


static func is_weapon_material(name: String) -> bool:
	var n := name.to_lower()
	for x in NOT_WEAPON:
		if n.contains(x):
			return false
	for x in WEAPON_MATS:
		if n.contains(x):
			return true
	return false


## The skeleton's bones in the T-pose (global, the skeleton's space): from their rest,
## each arm bone turned to point along its side (+X or -X), a weapon bone moved beside
## the body, upright.
static func pose(sk: Skeleton3D) -> Array:
	var n := sk.get_bone_count()
	var g: Array = []
	g.resize(n)
	var top := 0.0
	var half := 0.0
	for i in n:
		var r := sk.get_bone_global_rest(i)
		top = maxf(top, r.origin.y)
		half = maxf(half, absf(r.origin.x))
	for i in n:   # (parents come before their children)
		var p := sk.get_bone_parent(i)
		var local := sk.get_bone_rest(i)
		var gi: Transform3D = (g[p] as Transform3D) * local if p >= 0 else local
		var name := sk.get_bone_name(i)
		if _is_arm(name):
			var side := signf(gi.origin.x)
			if side == 0.0:
				side = 1.0 if name.ends_with("L") or name.to_lower().contains("left") else -1.0
			var now := gi.basis.y.normalized()
			var want := Vector3(side, 0, 0)
			if now.dot(want) < 0.9999:
				var axis := now.cross(want)
				var ang := now.angle_to(want)
				var q := Quaternion(axis.normalized(), ang) if axis.length() > 1e-6 else Quaternion(Vector3.BACK, PI)
				gi = Transform3D(Basis(q) * gi.basis, gi.origin)
		elif p < 0 and name.to_lower() in WEAPON_BONES:
			# (beside the body, below the arm, standing on its butt: out of the way)
			gi = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * gi.basis.orthonormalized(), Vector3(-(half + 0.75), top * 0.18, 0.0))
		g[i] = gi
	return g


## Each skin bind's matrix for bone poses `g` (global): pose * bind.
static func matrices(mi: MeshInstance3D, sk: Skeleton3D, g: Array) -> Array:
	var out: Array = []
	var skin := mi.skin
	if skin:
		for k in skin.get_bind_count():
			var b := skin.get_bind_bone(k)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(k))
			out.append(((g[b] as Transform3D) if b >= 0 else Transform3D()) * skin.get_bind_pose(k))
	else:
		for i in sk.get_bone_count():
			out.append((g[i] as Transform3D) * sk.get_bone_global_rest(i).affine_inverse())
	return out


## `m`'s surfaces with every vertex moved by its bones' blend of `mats` (`inverse`: by its
## inverse - back). Plain arrays (a worker may make them); mesh_from() makes the mesh.
static func bake(m: ArrayMesh, mats: Array, inverse := false) -> Array:
	var out: Array = []
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var fmt := m.surface_get_format(s)
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tan: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var nv := v.size()
		var per := bones.size() / nv if nv > 0 and bones.size() > 0 else 0
		if per > 0:
			for i in nv:
				var basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
				var origin := Vector3.ZERO
				var wsum := 0.0
				for k in per:
					var w := weights[i * per + k]
					if w <= 0.0:
						continue
					var bi := bones[i * per + k]
					if bi < 0 or bi >= mats.size():
						continue
					var t: Transform3D = mats[bi]
					basis.x += t.basis.x * w
					basis.y += t.basis.y * w
					basis.z += t.basis.z * w
					origin += t.origin * w
					wsum += w
				if wsum <= 0.0:
					continue
				var mt := Transform3D(basis, origin)
				if inverse:
					mt = mt.affine_inverse()
				v[i] = mt * v[i]
				if i < nrm.size():
					nrm[i] = (mt.basis * nrm[i]).normalized()
				if i * 4 + 3 < tan.size():
					var tv := (mt.basis * Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])).normalized()
					tan[i * 4] = tv.x
					tan[i * 4 + 1] = tv.y
					tan[i * 4 + 2] = tv.z
		a[Mesh.ARRAY_VERTEX] = v
		if not nrm.is_empty():
			a[Mesh.ARRAY_NORMAL] = nrm
		if not tan.is_empty():
			a[Mesh.ARRAY_TANGENT] = tan
		out.append([m.surface_get_primitive_type(s), a, fmt, m.surface_get_material(s), m.surface_get_name(s)])
	return out


static func mesh_from(surfs: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keep := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for i in 4:   # (the four custom arrays)
		keep |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + i * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
	for s in surfs:
		mesh.add_surface_from_arrays(s[0], s[1], [], {}, int(s[2]) & keep)
		var k := mesh.get_surface_count() - 1
		mesh.surface_set_material(k, s[3])
		mesh.surface_set_name(k, s[4])
	return mesh


## The part's surfaces made of weapon materials.
static func weapon_surfaces(mi: MeshInstance3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	if mi.mesh == null:
		return out
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		var n := m.resource_name if m else ""
		if n == "":
			n = mi.mesh.surface_get_name(s)
		if is_weapon_material(n):
			out.append(s)
	return out


## The skin binds (as the mesh's ARRAY_BONES name them) that are a weapon's bones.
static func weapon_binds(mi: MeshInstance3D) -> Dictionary:
	var out := {}
	var sk: Skeleton3D = null
	if mi.skeleton != NodePath(""):
		sk = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	elif mi.has_meta("tpose_skel"):
		sk = mi.get_node_or_null(mi.get_meta("tpose_skel")) as Skeleton3D
	var skin: Skin = mi.skin
	if skin == null and mi.has_meta("tpose_skin"):
		skin = mi.get_meta("tpose_skin")
	if sk == null:
		return out
	if skin:
		for k in skin.get_bind_count():
			var b := skin.get_bind_bone(k)
			var bname := sk.get_bone_name(b) if b >= 0 else str(skin.get_bind_name(k))
			if bname.to_lower() in WEAPON_BONES:
				out[k] = true
	else:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower() in WEAPON_BONES:
				out[i] = true
	return out


## `mi`'s mesh split: [the body, the weapons (null - none)] - the weapons every triangle whose
## points all hang mostly on a weapon's bone (the rifle, whatever its materials), and every
## surface of a weapon's material (a bow or an axe held in the hand).
static func split_weapons(mi: MeshInstance3D) -> Array:
	var m := mi.mesh as ArrayMesh
	if m == null:
		return [mi.mesh, null]
	var wb := weapon_binds(mi)
	var ws := weapon_surfaces(mi)
	var body := []
	var arms := []
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var e := [m.surface_get_primitive_type(s), a, m.surface_get_format(s), m.surface_get_material(s), m.surface_get_name(s)]
		if s in ws:
			arms.append(e)
			continue
		if wb.is_empty() or m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			body.append(e)
			continue
		var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var per := bones.size() / nv if nv > 0 else 0
		if per == 0:
			body.append(e)
			continue
		var on_weapon := PackedByteArray()
		on_weapon.resize(nv)
		for v in nv:
			var bw := 0.0
			var bb := -1
			for k in per:
				if weights[v * per + k] > bw:
					bw = weights[v * per + k]
					bb = bones[v * per + k]
			on_weapon[v] = 1 if wb.has(bb) else 0
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(nv))
		var keep := PackedInt32Array()
		var take := PackedInt32Array()
		for t in idx.size() / 3:
			var w: bool = on_weapon[idx[t * 3]] == 1 and on_weapon[idx[t * 3 + 1]] == 1 and on_weapon[idx[t * 3 + 2]] == 1
			if w:
				take.append_array(idx.slice(t * 3, t * 3 + 3))
			else:
				keep.append_array(idx.slice(t * 3, t * 3 + 3))
		if take.is_empty():
			body.append(e)
			continue
		if not keep.is_empty():
			body.append([e[0], _sub(a, keep), e[2], e[3], e[4]])
		arms.append([e[0], _sub(a, take), e[2], e[3], e[4]])
	if arms.is_empty():
		return [mi.mesh, null]
	return [mesh_from(body), mesh_from(arms)]


## A surface's arrays cut to the vertices `idx` uses (compacted, re-indexed).
static func _sub(a: Array, idx: PackedInt32Array) -> Array:
	var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var map := PackedInt32Array()
	map.resize(nv)
	map.fill(-1)
	var used := PackedInt32Array()
	for i in idx:
		if map[i] < 0:
			map[i] = used.size()
			used.append(i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var arr = a[k]
		if arr == null or k == Mesh.ARRAY_INDEX:
			continue
		var n: int = arr.size()
		var per := n / nv if nv > 0 else 0
		if per <= 0 or n != per * nv:
			continue   # (an array not one per vertex: left out)
		var o = arr.duplicate()
		o.resize(used.size() * per)
		for j in used.size():
			for c in per:
				o[j * per + c] = arr[used[j] * per + c]
		out[k] = o
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	for i in idx.size():
		ni[i] = map[idx[i]]
	out[Mesh.ARRAY_INDEX] = ni
	return out


## The weapons put back: each of `b`'s surfaces into `a`'s surface of the same material (its
## vertices and triangles appended), else as a surface of its own - no surfaces pile up.
static func join(a: ArrayMesh, b: ArrayMesh) -> ArrayMesh:
	var all := []
	for s in a.get_surface_count():
		all.append([a.surface_get_primitive_type(s), a.surface_get_arrays(s), a.surface_get_format(s), a.surface_get_material(s), a.surface_get_name(s)])
	for s in b.get_surface_count():
		var e := [b.surface_get_primitive_type(s), b.surface_get_arrays(s), b.surface_get_format(s), b.surface_get_material(s), b.surface_get_name(s)]
		var into := -1
		for i in all.size():
			if all[i][3] == e[3] and all[i][0] == e[0] and int(all[i][2]) == int(e[2]):
				into = i
				break
		if into < 0:
			all.append(e)
		else:
			all[into][1] = _append(all[into][1], e[1])
	return mesh_from(all)


static func _append(x: Array, y: Array) -> Array:
	var nx: int = (x[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var ny: int = (y[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		if k == Mesh.ARRAY_INDEX or x[k] == null or y[k] == null:
			continue
		var o = x[k].duplicate()
		o.append_array(y[k])
		out[k] = o
	var ix: PackedInt32Array = x[Mesh.ARRAY_INDEX] if x[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(nx))
	var iy: PackedInt32Array = y[Mesh.ARRAY_INDEX] if y[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(ny))
	var ni := ix.duplicate()
	for i in iy:
		ni.append(i + nx)
	out[Mesh.ARRAY_INDEX] = ni
	return out
