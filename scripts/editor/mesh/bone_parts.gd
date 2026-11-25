extends RefCounted
## The mesh editor's Parts from bones: a character's skeleton given simple body parts - one a
## bone, a rounded loft from the bone's head to its child's head (the child the bone points
## at; an end bone: a short cap along its own axis), its cross-sections fitted to the Body's
## vertices weighted to that bone (their spread around the bone's axis, ring by ring: an
## ellipse each, centred on them), or - none weighted to it - a fraction of the bone's length.
## Each part is named after its bone and skinned all to it, so it moves with the animations
## (the game merges parts bound to the skeleton into the Body). Made where the bones are drawn
## now: in the character's T-pose (the part then carries the Body's T-pose metas and is turned
## back with it when saved) or in its own pose.
##   BoneParts.make(rig, "children", bind, material) -> [{"name", "bone", "bind", "mesh"}...]

const TPose := preload("res://scripts/editor/mesh/tpose.gd")
const MeshBind := preload("res://scripts/editor/mesh/mesh_bind.gd")
const Shapes := preload("res://scripts/editor/mesh/shapes.gd")

## Which bones: the one picked, it and every bone below it, or every bone of the skin.
const SCOPES := ["bone", "children", "all"]
const RINGS := 6        # cross-sections fitted along a bone
const SIDES := 12       # points around each
const CAP_RINGS := 3    # rings rounding each end (the last a point)
const MIN_WEIGHT := 0.35   # a vertex counts for its strongest bone when weighted at least this
const SPREAD := 0.85    # the part's radius: this share of the vertices within it


## The skin binds scope `scope` covers from bind `k`: "bone" - k; "children" - k and every
## bind whose bone descends from k's; "all" - every bind with a bone. Weapon bones only when
## picked themselves.
static func binds_in(rig: Dictionary, k: int, scope: String) -> PackedInt32Array:
	var bs := MeshBind.binds(rig)
	var skel: Skeleton3D = rig["skel"]
	var out := PackedInt32Array()
	if scope == "bone":
		if k >= 0 and k < bs.size() and int(bs[k][0]) >= 0:
			out.append(k)
		return out
	var top := int(bs[k][0]) if scope == "children" and k >= 0 and k < bs.size() else -1
	if scope == "children" and top < 0:
		return out
	for j in bs.size():
		var b: int = bs[j][0]
		if b < 0:
			continue
		if (scope == "all" or j != k) and str(bs[j][1]).to_lower() in TPose.WEAPON_BONES:
			continue
		if scope == "children":
			var c := b
			while c >= 0 and c != top:
				c = skel.get_bone_parent(c)
			if c != top:
				continue
		out.append(j)
	return out


## The Body's vertices as drawn now (the skeleton's space), each under the bind weighing on
## it most (when at least MIN_WEIGHT) - for binds `want` only: {bind: PackedVector3Array}.
static func weighted(rig: Dictionary, want: PackedInt32Array) -> Dictionary:
	var out := {}
	var acc := {}   # (Arrays while gathering: appended in place)
	for k in want:
		acc[k] = []
		out[k] = PackedVector3Array()
	var body: MeshInstance3D = rig["body"]
	var skel: Skeleton3D = rig["skel"]
	var body_to_skel := skel.global_transform.affine_inverse() * body.global_transform
	var m: Mesh = body.mesh
	if m == null:
		return out
	_gather(rig, m, body_to_skel, acc)
	for k in want:
		out[k] = PackedVector3Array(acc[k])
	return out


static func _gather(rig: Dictionary, m: Mesh, body_to_skel: Transform3D, acc: Dictionary) -> void:
	var mats: Array = rig["mats"]
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if a[Mesh.ARRAY_BONES] == null or a[Mesh.ARRAY_WEIGHTS] == null or vs.is_empty():
			continue
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / vs.size()
		if per <= 0:
			continue
		for i in vs.size():
			var best := -1
			var bw := MIN_WEIGHT
			for j in per:
				if ws[i * per + j] >= bw:
					bw = ws[i * per + j]
					best = bones[i * per + j]
			if best < 0 or not acc.has(best):
				continue
			var q: Vector3
			if rig["tpose"]:   # (the T-posed Body's mesh is as it's drawn)
				q = body_to_skel * vs[i]
			else:
				q = MeshBind._blend(mats, bones.slice(i * per, i * per + per), ws.slice(i * per, i * per + per)) * vs[i]
			(acc[best] as Array).append(q)


## The `p`-th share (0..1) of the values `xs`.
static func _quantile(xs: PackedFloat32Array, p: float) -> float:
	if xs.is_empty():
		return 0.0
	var s := xs.duplicate()
	s.sort()
	return s[clampi(int(round(p * (s.size() - 1))), 0, s.size() - 1)]


## Bind `k`'s part fitted (the skeleton's space): {"a": its head, "axis", "len", "u", "w" (the
## cross-sections' axes), "rings": [[along, centre u, centre w, radius u, radius w]...],
## "end": no child to reach}. `verts`: the Body's vertices weighted to it (drawn).
static func fit(rig: Dictionary, k: int, verts: PackedVector3Array) -> Dictionary:
	var skel: Skeleton3D = rig["skel"]
	var g: Array = rig["g"]
	var b: int = MeshBind.binds(rig)[k][0]
	var gb: Transform3D = g[b]
	var a := gb.origin
	var y := gb.basis.y.normalized()
	if y.length_squared() < 0.5:
		y = Vector3.UP
	# the child the bone points at (most along its own axis; heads on top of it don't count)
	var axis := y
	var length := 0.0
	var best := 0.7
	for c in skel.get_bone_children(b):
		var d: Vector3 = (g[c] as Transform3D).origin - a
		if d.length() < 1e-3 or d.dot(y) <= 0.0:
			continue
		var al := d.dot(y) / d.length()
		if al > best:
			best = al
			axis = d.normalized()
			length = d.length()
	var end := length <= 0.0
	if end:   # (an end bone: as far as its vertices go along it, or a short cap)
		var along := PackedFloat32Array()
		for v in verts:
			along.append(maxf(0.0, (v - a).dot(axis)))
		length = _quantile(along, 0.9) if verts.size() >= 8 else 0.0
		if length < 0.02:
			var p := skel.get_bone_parent(b)
			var pl := (g[p] as Transform3D).origin.distance_to(a) if p >= 0 else 0.0
			length = clampf(pl * 0.3, 0.02, 0.12) if pl > 0.0 else 0.06
	var u := gb.basis.x - axis * gb.basis.x.dot(axis)
	if u.length_squared() < 1e-8:
		u = axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD)
	u = u.normalized()
	var w := axis.cross(u).normalized()
	# each cross-section: the vertices within half a step either side of it, from where they sit
	var step := length / float(RINGS - 1)
	var rows := []   # per ring: [its vertices' u offsets, their w offsets] (Arrays: appended in place)
	for r in RINGS:
		rows.append([[], []])
	for v in verts:
		var rel := v - a
		var s := rel.dot(axis)
		if s < -step * 0.75 or s > length + step * 0.75:
			continue
		var r := clampi(int(round(s / step)), 0, RINGS - 1)
		rows[r][0].append(rel.dot(u))
		rows[r][1].append(rel.dot(w))
	var fall := clampf(length * (0.45 if end and verts.size() < 8 else 0.16), 0.01, 0.09)
	var rings := []
	var have := []
	for r in RINGS:
		var pu := PackedFloat32Array(rows[r][0])
		var pw := PackedFloat32Array(rows[r][1])
		if pu.size() < 6:
			rings.append([step * r, 0.0, 0.0, fall * (1.0 - 0.2 * r / (RINGS - 1)), fall * (1.0 - 0.2 * r / (RINGS - 1))])
			have.append(false)
			continue
		var cu := 0.0
		var cw := 0.0
		for i in pu.size():
			cu += pu[i]
			cw += pw[i]
		cu /= pu.size()
		cw /= pw.size()
		var du := PackedFloat32Array()
		var dw := PackedFloat32Array()
		for i in pu.size():
			du.append(absf(pu[i] - cu))
			dw.append(absf(pw[i] - cw))
		rings.append([step * r, cu, cw, _quantile(du, SPREAD), _quantile(dw, SPREAD)])
		have.append(true)
	# rings without vertices: from their nearest neighbours that have some
	if have.has(true):
		for r in RINGS:
			if have[r]:
				continue
			var lo := r - 1
			while lo >= 0 and not have[lo]:
				lo -= 1
			var hi := r + 1
			while hi < RINGS and not have[hi]:
				hi += 1
			var src: Array = rings[lo] if hi >= RINGS else (rings[hi] if lo < 0 else [])
			if src.is_empty():
				var t := float(r - lo) / float(hi - lo)
				src = []
				for q in 5:
					src.append(lerpf(rings[lo][q], rings[hi][q], t))
			for q in range(1, 5):
				rings[r][q] = src[q]
	# smoothed a little (no lumps), kept round enough, not too thin, centres near the bone
	var smooth := []
	for r in RINGS:
		var row: Array = rings[r].duplicate()
		for q in range(1, 5):
			var n := 0.0
			var sum := 0.0
			for o in [-1, 0, 1]:
				if r + o >= 0 and r + o < RINGS:
					var wt := 2.0 if o == 0 else 1.0
					sum += float(rings[r + o][q]) * wt
					n += wt
			row[q] = sum / n
		var rmin := maxf(0.006, length * 0.04)
		row[3] = clampf(row[3], rmin, 0.6)
		row[4] = clampf(row[4], rmin, 0.6)
		row[3] = minf(row[3], row[4] * 3.0)
		row[4] = minf(row[4], row[3] * 3.0)
		var off := Vector2(row[1], row[2])
		var lim := maxf(row[3], row[4]) * 1.5
		if off.length() > lim:
			off = off.normalized() * lim
		row[1] = off.x
		row[2] = off.y
		smooth.append(row)
	return {"a": a, "axis": axis, "len": length, "u": u, "w": w, "rings": smooth, "end": end}


## A fitted part's surface (fit()): a closed loft through its rings, each end rounded to a
## point - in the skeleton's space.
static func loft(f: Dictionary) -> Array:
	var a: Vector3 = f["a"]
	var axis: Vector3 = f["axis"]
	var u: Vector3 = f["u"]
	var w: Vector3 = f["w"]
	var length: float = f["len"]
	var rings: Array = f["rings"]
	# the rows from end to end: [along, centre u, centre w, radius u, radius w]
	var rows := []
	var r0: Array = rings[0]
	var r1: Array = rings[rings.size() - 1]
	var d0 := clampf(minf(r0[3], r0[4]) * 0.9, 0.004, length * 0.45)
	var d1 := clampf(minf(r1[3], r1[4]) * 0.9, 0.004, length * 0.45)
	for c in range(CAP_RINGS, 0, -1):
		var th := PI * 0.5 * c / CAP_RINGS
		rows.append([r0[0] - d0 * sin(th), r0[1], r0[2], r0[3] * cos(th), r0[4] * cos(th)])
	rows += rings
	for c in range(1, CAP_RINGS + 1):
		var th := PI * 0.5 * c / CAP_RINGS
		rows.append([r1[0] + d1 * sin(th), r1[1], r1[2], r1[3] * cos(th), r1[4] * cos(th)])
	# a sheet: columns around (u towards w - with the rows along the axis, faces outwards)
	var P := []
	for i in SIDES + 1:
		var ang := TAU * float(i % SIDES) / SIDES
		var col := PackedVector3Array()
		for row: Array in rows:
			var rr := Vector2(float(row[3]) * cos(ang), float(row[4]) * sin(ang))
			if rr.length() < 1e-6:
				rr = Vector2.ZERO   # (a pole: one point)
			col.append(a + axis * float(row[0]) + u * (float(row[1]) + rr.x) + w * (float(row[2]) + rr.y))
		P.append(col)
	var b := Shapes.B.new()
	var vv := PackedFloat32Array()
	for j in rows.size():
		vv.append(float(j) / (rows.size() - 1))
	b.sheet(P, PackedInt32Array(), PackedInt32Array(), true, false, PackedFloat32Array(), vv)
	return b.commit()


## Surface `arr` (the skeleton's space) skinned all to bind `k` of `rig`: its vertices where the
## bind draws them as they are now - the Body's mesh space (T-posed: as drawn; else by the
## inverse of the bind's matrix).
static func bound(rig: Dictionary, k: int, arr: Array, mat: Material) -> ArrayMesh:
	var body: MeshInstance3D = rig["body"]
	var skel: Skeleton3D = rig["skel"]
	var to: Transform3D = body.global_transform.affine_inverse() * skel.global_transform if rig["tpose"] \
		else (rig["mats"][k] as Transform3D).affine_inverse()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var nb := to.basis.inverse().transposed()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in vs.size():
		vs[i] = to * vs[i]
		ns[i] = (nb * ns[i]).normalized()
		bones.append_array([k, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TANGENT] = null
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


## The parts for scope `scope` from bind `k` ("all": any k): [{"name": the part's name (the
## bone's made a node name, + "_part": a saved model's nodes and bones share their names, the
## bone would keep it), "bone", "bind", "mesh": bound (bound())}...].
static func make(rig: Dictionary, scope: String, k: int, mat: Material) -> Array:
	var out := []
	if rig.is_empty():
		return out
	var want := binds_in(rig, k, scope)
	if want.is_empty():
		return out
	var verts := weighted(rig, want)
	var bs := MeshBind.binds(rig)
	for j in want:
		var f := fit(rig, j, verts[j])
		var arr := loft(f)
		if arr.is_empty():
			continue
		var bone := str(bs[j][1])
		out.append({"name": bone.validate_node_name() + "_part", "bone": bone, "bind": j, "mesh": bound(rig, j, arr, mat)})
	return out
