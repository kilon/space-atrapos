extends RefCounted
## The mesh editor's shape generators: parametric solids (a box with a bevel, a
## lathe, an extrusion, a gear, a knot...) - each a function of a few numbers, made
## into one mesh surface with normals, UVs and tangents, closed (every edge shared by
## two faces) where the shape is solid, so booleans work on it. Static and
## thread-safe: the library (shape_library.gd) and the browser make them on workers.
##   Shapes.make("cylinder", {"r_top": 0.0})       -> ArrayMesh (a cone)
##   Shapes.GENS["gear"]["params"]                 -> the gear's parameters
##
## Inside, every shape is built from sheets: grids of points P[i][j] whose quads
## face out along dP/di x dP/dj; a sheet splits into blocks at hard creases (each
## block its own vertices - the same positions, so the shape stays closed), and
## each block's normals are its faces' normals averaged.

## The generators: label, solid (closed), params [[key, label, min, max, step, default]]
## (step 1: a whole number). Array-valued params (a lathe's profile, an outline) come
## from the library entry and aren't shown as fields.
const GENS := {
	"box": {"label": "Box", "solid": true, "params": [["w", "Width", 0.01, 10.0, 0.01, 1.0], ["h", "Height", 0.01, 10.0, 0.01, 1.0],
		["d", "Depth", 0.01, 10.0, 0.01, 1.0], ["bevel", "Bevel", 0.0, 1.0, 0.005, 0.0], ["bevel_segs", "Bevel steps", 1, 8, 1, 3]]},
	"superellipsoid": {"label": "Superellipsoid", "solid": true, "params": [["w", "Width", 0.01, 10.0, 0.01, 1.0], ["h", "Height", 0.01, 10.0, 0.01, 1.0],
		["d", "Depth", 0.01, 10.0, 0.01, 1.0], ["e1", "Roundness (up)", 0.1, 4.0, 0.01, 1.0], ["e2", "Roundness (around)", 0.1, 4.0, 0.01, 1.0],
		["res", "Detail", 3, 32, 1, 12]]},
	"sphere": {"label": "Sphere", "solid": true, "params": [["r", "Radius", 0.01, 10.0, 0.01, 0.5], ["segs", "Segments", 3, 96, 1, 32],
		["rings", "Rings", 2, 64, 1, 16], ["lat0", "From latitude", -90.0, 89.0, 1.0, -90.0], ["lat1", "To latitude", -89.0, 90.0, 1.0, 90.0],
		["thickness", "Shell thickness", 0.0, 5.0, 0.005, 0.0], ["sy", "Height scale", 0.05, 5.0, 0.01, 1.0]]},
	"ico": {"label": "Ico sphere", "solid": true, "params": [["r", "Radius", 0.01, 10.0, 0.01, 0.5], ["subdiv", "Subdivisions", 0, 4, 1, 2],
		["faceted", "Faceted", 0, 1, 1, 0], ["noise", "Roughness", 0.0, 1.0, 0.01, 0.0], ["freq", "Bumpiness", 0.1, 8.0, 0.05, 1.5],
		["seed", "Seed", 0, 999, 1, 1], ["sx", "Width scale", 0.05, 5.0, 0.01, 1.0], ["sy", "Height scale", 0.05, 5.0, 0.01, 1.0],
		["sz", "Depth scale", 0.05, 5.0, 0.01, 1.0]]},
	"cylinder": {"label": "Cylinder / cone / prism", "solid": true, "params": [["r", "Radius (bottom)", 0.0, 10.0, 0.01, 0.5],
		["r_top", "Radius (top)", 0.0, 10.0, 0.01, 0.5], ["h", "Height", 0.01, 20.0, 0.01, 1.0], ["segs", "Sides", 3, 128, 1, 32],
		["hole", "Hole radius", 0.0, 10.0, 0.01, 0.0], ["bevel", "Bevel", 0.0, 1.0, 0.005, 0.0], ["phase", "Turn (degrees)", 0.0, 360.0, 1.0, 0.0]]},
	"capsule": {"label": "Capsule", "solid": true, "params": [["r", "Radius", 0.01, 10.0, 0.01, 0.25], ["h", "Height", 0.02, 20.0, 0.01, 1.0],
		["segs", "Segments", 3, 96, 1, 24], ["rings", "Rings (each end)", 1, 32, 1, 6]]},
	"torus": {"label": "Torus", "solid": true, "params": [["R", "Ring radius", 0.01, 10.0, 0.01, 0.4], ["r", "Tube radius", 0.005, 5.0, 0.005, 0.1],
		["segs", "Segments", 3, 192, 1, 36], ["sides", "Tube sides", 3, 64, 1, 16], ["angle", "Sweep (degrees)", 5.0, 360.0, 1.0, 360.0],
		["sy", "Tube height scale", 0.05, 5.0, 0.01, 1.0]]},
	"lathe": {"label": "Lathe (a profile revolved)", "solid": true, "params": [["sr", "Width scale", 0.05, 10.0, 0.01, 1.0],
		["sy", "Height scale", 0.05, 10.0, 0.01, 1.0], ["segs", "Segments", 3, 128, 1, 32], ["angle", "Sweep (degrees)", 5.0, 360.0, 1.0, 360.0],
		["phase", "Turn (degrees)", 0.0, 360.0, 1.0, 0.0]]},
	"extrude": {"label": "Extrusion (an outline with depth)", "solid": true, "params": [["sx", "Width scale", 0.05, 10.0, 0.01, 1.0],
		["sz", "Length scale", 0.05, 10.0, 0.01, 1.0], ["h", "Depth", 0.005, 20.0, 0.005, 0.2], ["bevel", "Bevel", 0.0, 0.5, 0.002, 0.0]]},
	"loft": {"label": "Loft (one outline to another)", "solid": true, "params": [["sides_a", "Sides (bottom)", 3, 64, 1, 4],
		["sides_b", "Sides (top)", 3, 64, 1, 32], ["r_a", "Radius (bottom)", 0.0, 10.0, 0.01, 0.5], ["r_b", "Radius (top)", 0.0, 10.0, 0.01, 0.35],
		["h", "Height", 0.01, 20.0, 0.01, 1.0], ["twist", "Twist (degrees)", -720.0, 720.0, 1.0, 0.0], ["layers", "Layers", 1, 64, 1, 8],
		["bulge", "Bulge", -1.0, 1.0, 0.01, 0.0]]},
	"star": {"label": "Star prism", "solid": true, "params": [["n", "Points", 3, 24, 1, 5], ["r_out", "Outer radius", 0.01, 10.0, 0.01, 0.5],
		["r_in", "Inner radius", 0.01, 10.0, 0.01, 0.22], ["h", "Thickness", 0.005, 10.0, 0.005, 0.2], ["bevel", "Bevel", 0.0, 0.2, 0.002, 0.0]]},
	"gear": {"label": "Gear / ring plate", "solid": true, "params": [["teeth", "Teeth (0: a plain plate)", 0, 96, 1, 12],
		["r", "Radius", 0.02, 10.0, 0.01, 0.5], ["depth", "Tooth depth", 0.0, 2.0, 0.005, 0.08], ["tooth_w", "Tooth width", 0.1, 0.9, 0.01, 0.45],
		["h", "Thickness", 0.005, 10.0, 0.005, 0.2], ["bore", "Hole radius", 0.0, 9.0, 0.01, 0.0], ["sides", "Sides (no teeth)", 3, 64, 1, 6]]},
	"wedge": {"label": "Wedge", "solid": true, "params": [["w", "Width", 0.01, 10.0, 0.01, 1.0], ["h", "Height", 0.01, 10.0, 0.01, 1.0],
		["d", "Depth", 0.01, 10.0, 0.01, 1.0], ["top", "Top depth", 0.0, 10.0, 0.01, 0.0]]},
	"arch": {"label": "Arch", "solid": true, "params": [["w", "Width", 0.1, 20.0, 0.01, 1.6], ["h", "Height", 0.1, 20.0, 0.01, 2.0],
		["d", "Depth", 0.01, 10.0, 0.01, 0.4], ["opening", "Opening", 0.05, 19.0, 0.01, 1.0], ["spring", "Springing height", 0.0, 19.0, 0.01, 0.9],
		["pointed", "Pointed", 0.0, 1.0, 0.01, 0.0], ["segs", "Arc segments", 2, 64, 1, 16]]},
	"stairs": {"label": "Stairs", "solid": true, "params": [["steps", "Steps", 1, 64, 1, 6], ["w", "Width", 0.05, 20.0, 0.01, 1.0],
		["h", "Height", 0.05, 20.0, 0.01, 1.0], ["d", "Run", 0.05, 20.0, 0.01, 1.5], ["under", "Underside (0 open, 1 filled)", 0, 1, 1, 1],
		["t", "Slab thickness", 0.01, 5.0, 0.01, 0.15]]},
	"spiral_stairs": {"label": "Spiral stairs", "solid": true, "params": [["steps", "Steps", 2, 64, 1, 12], ["r", "Radius", 0.1, 10.0, 0.01, 1.0],
		["h", "Height", 0.1, 20.0, 0.01, 2.4], ["turn", "Turn (degrees)", 30.0, 1080.0, 1.0, 360.0], ["column", "Column radius", 0.0, 2.0, 0.01, 0.12],
		["t", "Step thickness", 0.01, 1.0, 0.005, 0.05]]},
	"spring": {"label": "Spring / helix", "solid": true, "params": [["R", "Coil radius", 0.01, 10.0, 0.01, 0.3], ["r", "Wire radius", 0.002, 2.0, 0.002, 0.04],
		["turns", "Turns", 0.25, 40.0, 0.25, 5.0], ["h", "Length", 0.01, 20.0, 0.01, 1.0], ["segs", "Segments a turn", 6, 96, 1, 24],
		["sides", "Wire sides", 3, 32, 1, 10], ["taper", "Taper", 0.0, 1.0, 0.01, 0.0]]},
	"knot": {"label": "Torus knot", "solid": true, "params": [["p", "Windings (p)", 1, 12, 1, 2], ["q", "Turns (q)", 1, 12, 1, 3],
		["R", "Radius", 0.05, 10.0, 0.01, 0.35], ["r", "Tube radius", 0.005, 2.0, 0.005, 0.08], ["segs", "Segments", 32, 600, 1, 180],
		["sides", "Tube sides", 3, 32, 1, 12]]},
	"column": {"label": "Column", "solid": true, "params": [["r", "Radius", 0.02, 5.0, 0.01, 0.22], ["h", "Height", 0.1, 30.0, 0.01, 2.2],
		["flutes", "Flutes", 0, 48, 1, 20], ["depth", "Flute depth", 0.0, 0.5, 0.002, 0.02], ["taper", "Top / bottom", 0.3, 2.0, 0.01, 0.85],
		["capital", "Capital (0 none, 1 Doric, 2 Ionic, 3 Corinthian, 4 Minoan)", 0, 4, 1, 1], ["base", "Base (0 none, 1 torus, 2 plinth)", 0, 2, 1, 1],
		["segs", "Segments", 8, 192, 1, 64]]},
	"bolt": {"label": "Bolt / screw", "solid": true, "params": [["head_sides", "Head sides (0: round)", 0, 12, 1, 6], ["head_r", "Head radius", 0.005, 5.0, 0.005, 0.12],
		["head_h", "Head height", 0.002, 5.0, 0.002, 0.07], ["r", "Shaft radius", 0.002, 5.0, 0.002, 0.06], ["length", "Length", 0.01, 20.0, 0.01, 0.5],
		["pitch", "Thread pitch", 0.002, 1.0, 0.001, 0.03], ["thread", "Thread depth", 0.0, 0.5, 0.001, 0.008]]},
	"chain": {"label": "Chain link", "solid": true, "params": [["L", "Length", 0.02, 10.0, 0.01, 0.5], ["W", "Width", 0.02, 10.0, 0.01, 0.28],
		["r", "Wire radius", 0.002, 2.0, 0.002, 0.04], ["segs", "Segments", 12, 192, 1, 48], ["sides", "Wire sides", 3, 32, 1, 10]]},
	"horn": {"label": "Horn / tentacle / shell", "solid": true, "params": [["r", "Base radius", 0.005, 5.0, 0.005, 0.15], ["r_tip", "Tip radius", 0.0, 5.0, 0.005, 0.0],
		["length", "Length", 0.05, 20.0, 0.01, 1.0], ["curl", "Curl (degrees)", 0.0, 1440.0, 1.0, 90.0], ["spiral", "Spiral in", 0.0, 1.0, 0.01, 0.0],
		["rise", "Rise (a helix)", 0.0, 10.0, 0.01, 0.0], ["segs", "Segments", 4, 256, 1, 48], ["sides", "Sides", 3, 48, 1, 16], ["ribs", "Ribs", 0, 64, 1, 0]]},
	"greeble": {"label": "Greeble panel", "solid": true, "params": [["w", "Width", 0.05, 20.0, 0.01, 1.0], ["d", "Depth", 0.05, 20.0, 0.01, 1.0],
		["t", "Plate thickness", 0.005, 2.0, 0.005, 0.05], ["count", "Details", 0, 120, 1, 14], ["height", "Detail height", 0.002, 2.0, 0.002, 0.06],
		["kind", "Kind (0 blocks, 1 vents, 2 pipes, 3 tiles)", 0, 3, 1, 0], ["seed", "Seed", 0, 999, 1, 1]]},
	"dish": {"label": "Dish / bowl", "solid": true, "params": [["r", "Radius", 0.02, 20.0, 0.01, 0.5], ["depth", "Depth", 0.0, 10.0, 0.01, 0.2],
		["t", "Thickness", 0.002, 2.0, 0.002, 0.03], ["segs", "Segments", 6, 128, 1, 40], ["rings", "Rings", 2, 48, 1, 10], ["foot", "Foot height", 0.0, 5.0, 0.01, 0.0]]},
	"plane": {"label": "Plane (open)", "solid": false, "params": [["w", "Width", 0.01, 50.0, 0.01, 1.0], ["d", "Depth", 0.01, 50.0, 0.01, 1.0],
		["subdiv", "Subdivisions", 0, 64, 1, 0]]},
}


## The generator's parameters with their defaults, overlaid by `params`.
static func full_params(gen: String, params: Dictionary) -> Dictionary:
	var out := {}
	for p in GENS.get(gen, {}).get("params", []):
		out[p[0]] = p[5]
	for k in params:
		out[k] = params[k]
	return out


## The shape as a mesh (one surface; no material) - null for an unknown generator.
static func make(gen: String, params: Dictionary) -> ArrayMesh:
	var a := arrays(gen, params)
	if a.is_empty():
		return null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.resource_name = str(GENS.get(gen, {}).get("label", gen))
	return m


## The shape's surface arrays (vertex, normal, tangent, UV, index), [] if it can't.
static func arrays(gen: String, params: Dictionary) -> Array:
	if not GENS.has(gen):
		return []
	var p := full_params(gen, params)
	var b := B.new()
	match gen:
		"box": _box(b, p)
		"superellipsoid": _superellipsoid(b, p)
		"sphere": _sphere(b, p)
		"ico": _ico(b, p)
		"cylinder": _cylinder(b, p)
		"capsule": _capsule(b, p)
		"torus": _torus(b, p)
		"lathe": _lathe_gen(b, p)
		"extrude": _extrude_gen(b, p)
		"loft": _loft(b, p)
		"star": _star(b, p)
		"gear": _gear(b, p)
		"wedge": _wedge(b, p)
		"arch": _arch(b, p)
		"stairs": _stairs(b, p)
		"spiral_stairs": _spiral_stairs(b, p)
		"spring": _spring(b, p)
		"knot": _knot(b, p)
		"column": _column(b, p)
		"bolt": _bolt(b, p)
		"chain": _chain(b, p)
		"horn": _horn(b, p)
		"greeble": _greeble(b, p)
		"dish": _dish(b, p)
		"plane": _plane(b, p)
	return b.commit()


# --- the builder -------------------------------------------------------------------

## Vertices, normals, UVs and triangles; triangles given outward-facing by the right-hand
## rule ((b - a) x (c - a) points out) - turned to Godot's clockwise order when committed.
class B:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	## Applied to what's added from now on (parts placed in a composite shape).
	var xf := Transform3D()

	func add(p: Vector3, nn: Vector3, t: Vector2) -> int:
		v.append(xf * p)
		n.append((xf.basis * nn).normalized())
		uv.append(t)
		return v.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		if v[a] == v[b] or v[b] == v[c] or v[a] == v[c]:
			return   # (collapsed at a pole: left out)
		idx.append(a); idx.append(b); idx.append(c)

	## A triangle turned to face `want` (local direction).
	func tri_facing(a: int, b: int, c: int, want: Vector3) -> void:
		if (v[b] - v[a]).cross(v[c] - v[a]).dot(xf.basis * want) < 0.0:
			tri(a, c, b)
		else:
			tri(a, b, c)

	## A sheet: P[i][j] (PackedVector3Array columns). Quads face dP/di x dP/dj. `ihard` /
	## `jhard`: the columns / rows where it creases (its own vertices each side); `wrap_i` /
	## `wrap_j`: the last column (row) is the first again - smooth across (unless creased).
	## `u` / `v`: texture coordinates per column / row ([]: by index). `nfn`: normals given
	## (Callable(i, j) -> Vector3) instead of worked out.
	func sheet(P: Array, ihard := PackedInt32Array(), jhard := PackedInt32Array(), wrap_i := false, wrap_j := false,
			u := PackedFloat32Array(), vv := PackedFloat32Array(), nfn := Callable()) -> void:
		var ni := P.size() - 1
		var nj: int = (P[0] as PackedVector3Array).size() - 1
		if ni < 1 or nj < 1:
			return
		if u.is_empty():
			for i in ni + 1:
				u.append(float(i) / ni)
		if vv.is_empty():
			for j in nj + 1:
				vv.append(float(j) / nj)
		var ib := _bounds(ihard, ni)
		var jb := _bounds(jhard, nj)
		var wi := wrap_i and ib.size() == 2
		var wj := wrap_j and jb.size() == 2
		for bi in ib.size() - 1:
			for bj in jb.size() - 1:
				_block(P, ib[bi], ib[bi + 1], jb[bj], jb[bj + 1], wi, wj, u, vv, nfn)

	func _bounds(hard: PackedInt32Array, nmax: int) -> PackedInt32Array:
		var s := {0: true, nmax: true}
		for h in hard:
			if h > 0 and h < nmax:
				s[h] = true
		var out := PackedInt32Array(s.keys())
		out.sort()
		return out

	func _block(P: Array, i0: int, i1: int, j0: int, j1: int, wi: bool, wj: bool, u: PackedFloat32Array, vv: PackedFloat32Array, nfn: Callable) -> void:
		var w := i1 - i0 + 1
		var hgt := j1 - j0 + 1
		var acc := PackedVector3Array()
		acc.resize(w * hgt)
		var pos := PackedVector3Array()
		pos.resize(w * hgt)
		for a in w:
			var col: PackedVector3Array = P[i0 + a]
			for c in hgt:
				pos[a * hgt + c] = col[j0 + c]
		if not nfn.is_valid():
			for a in w - 1:
				for c in hgt - 1:
					var p00 := pos[a * hgt + c]
					var p10 := pos[(a + 1) * hgt + c]
					var p11 := pos[(a + 1) * hgt + c + 1]
					var p01 := pos[a * hgt + c + 1]
					var f1 := (p10 - p00).cross(p11 - p00)
					var f2 := (p11 - p00).cross(p01 - p00)
					acc[a * hgt + c] += f1 + f2
					acc[(a + 1) * hgt + c] += f1
					acc[(a + 1) * hgt + c + 1] += f1 + f2
					acc[a * hgt + c + 1] += f2
			if wi:   # (the seam column shares its normals)
				for c in hgt:
					var s := acc[c] + acc[(w - 1) * hgt + c]
					acc[c] = s
					acc[(w - 1) * hgt + c] = s
			if wj:
				for a in w:
					var s := acc[a * hgt] + acc[a * hgt + hgt - 1]
					acc[a * hgt] = s
					acc[a * hgt + hgt - 1] = s
			# a row (column) collapsed to one point - a pole: its normals averaged
			for c in hgt:
				var same := true
				for a in range(1, w):
					if pos[a * hgt + c] != pos[c]:
						same = false
						break
				if same and w > 1:
					var s := Vector3.ZERO
					for a in w:
						s += acc[a * hgt + c]
					for a in w:
						acc[a * hgt + c] = s
			for a in w:
				var same := true
				for c in range(1, hgt):
					if pos[a * hgt + c] != pos[a * hgt]:
						same = false
						break
				if same and hgt > 1:
					var s := Vector3.ZERO
					for c in hgt:
						s += acc[a * hgt + c]
					for c in hgt:
						acc[a * hgt + c] = s
		var base := v.size()
		for a in w:
			for c in hgt:
				var nn: Vector3 = nfn.call(i0 + a, j0 + c) if nfn.is_valid() else acc[a * hgt + c]
				if nn.length_squared() < 1e-20:
					nn = Vector3.UP
				add(pos[a * hgt + c], nn.normalized(), Vector2(u[i0 + a], vv[j0 + c]))
		for a in w - 1:
			for c in hgt - 1:
				var k00 := base + a * hgt + c
				var k10 := base + (a + 1) * hgt + c
				var k11 := k10 + 1
				var k01 := k00 + 1
				tri(k00, k10, k11)
				tri(k00, k11, k01)

	## A flat polygon (`pts`, any order of turning) facing `normal`, triangulated; `uvs`
	## from `uv_basis` ([origin, u axis, v axis]).
	func cap(pts: PackedVector3Array, normal: Vector3, tex_u: Vector3, tex_v: Vector3) -> void:
		if pts.size() < 3:
			return
		var flat := PackedVector2Array()
		var ax_u := tex_u.normalized()
		var ax_v := normal.cross(ax_u).normalized()
		for p in pts:
			flat.append(Vector2(p.dot(ax_u), p.dot(ax_v)))
		var t := Geometry2D.triangulate_polygon(flat)
		if t.is_empty():
			var rev := flat.duplicate()
			rev.reverse()
			t = Geometry2D.triangulate_polygon(rev)
			if t.is_empty():
				return
			for k in t.size():
				t[k] = pts.size() - 1 - t[k]
		var base := v.size()
		for p in pts:
			add(p, normal, Vector2(p.dot(tex_u), p.dot(tex_v)))
		for k in range(0, t.size(), 3):
			tri_facing(base + t[k], base + t[k + 1], base + t[k + 2], normal)

	## A ring of quads between two loops (same count, closed) facing `normal` (a flat annulus).
	func ring_cap(outer: PackedVector3Array, inner: PackedVector3Array, normal: Vector3, tex_u: Vector3, tex_v: Vector3) -> void:
		var m := outer.size()
		var base := v.size()
		for p in outer:
			add(p, normal, Vector2(p.dot(tex_u), p.dot(tex_v)))
		for p in inner:
			add(p, normal, Vector2(p.dot(tex_u), p.dot(tex_v)))
		for k in m:
			var k2 := (k + 1) % m
			tri_facing(base + k, base + k2, base + m + k2, normal)
			tri_facing(base + k, base + m + k2, base + m + k, normal)

	## Another builder's mesh added (placed by `t`).
	func merge(o: B, t := Transform3D()) -> void:
		var base := v.size()
		for k in o.v.size():
			v.append(xf * (t * o.v[k]))
			n.append((xf.basis * (t.basis * o.n[k])).normalized())
			uv.append(o.uv[k])
		var flip := (xf.basis * t.basis).determinant() < 0.0
		for k in range(0, o.idx.size(), 3):
			if flip:
				idx.append(base + o.idx[k]); idx.append(base + o.idx[k + 2]); idx.append(base + o.idx[k + 1])
			else:
				idx.append(base + o.idx[k]); idx.append(base + o.idx[k + 1]); idx.append(base + o.idx[k + 2])

	## The surface arrays: triangles turned clockwise (Godot's front faces), tangents made.
	func commit() -> Array:
		if idx.is_empty():
			return []
		var out_idx := PackedInt32Array()
		out_idx.resize(idx.size())
		for k in range(0, idx.size(), 3):
			out_idx[k] = idx[k]
			out_idx[k + 1] = idx[k + 2]
			out_idx[k + 2] = idx[k + 1]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_INDEX] = out_idx
		var st := SurfaceTool.new()
		st.create_from_arrays(a)
		st.generate_tangents()
		return st.commit_to_arrays()


# --- helpers ---------------------------------------------------------------------------

static func _num(p: Dictionary, k: String) -> float:
	return float(p.get(k, 0.0))


static func _int(p: Dictionary, k: String) -> int:
	return int(round(float(p.get(k, 0))))


## Signed area of a 2D loop (positive: counter-clockwise).
static func _area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _ccw(pts: PackedVector2Array) -> PackedVector2Array:
	if _area(pts) < 0.0:
		var r := pts.duplicate()
		r.reverse()
		return r
	return pts


## Points from JSON ([[x, y], ...]).
static func _pts(arr: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if arr is Array:
		for q in arr:
			if q is Array and q.size() >= 2:
				out.append(Vector2(float(q[0]), float(q[1])))
	return out


## Corners sharper than `deg` in a closed loop (their indices).
static func _sharp(pts: PackedVector2Array, deg := 35.0, closed := true) -> PackedInt32Array:
	var out := PackedInt32Array()
	var m := pts.size()
	var lim := cos(deg_to_rad(deg))
	for k in m:
		if not closed and (k == 0 or k == m - 1):
			continue
		var a := (pts[k] - pts[(k - 1 + m) % m]).normalized()
		var b := (pts[(k + 1) % m] - pts[k]).normalized()
		if a.dot(b) < lim:
			out.append(k)
	return out


## A loop rotated to start at index `k`.
static func _roll(pts: PackedVector2Array, k: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts.size():
		out.append(pts[(q + k) % pts.size()])
	return out


static func _circle(n: int, r: float, phase := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var a := phase + TAU * k / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## Lengths along a polyline (closed: back to the start too), 0 .. total.
static func _lengths(pts: PackedVector2Array, closed: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	var m := pts.size() + (1 if closed else 0)
	for k in range(1, m):
		out.append(out[k - 1] + pts[k % pts.size()].distance_to(pts[k - 1]))
	return out


# --- the lathe: a profile (r, y) revolved about Y ----------------------------------------

## `prof`: a closed loop in (r, y) (r >= 0; points on the axis close it there). Revolved
## `angle` radians in `segs` steps (faceted when segs <= 8 or `facet`); sharp profile corners
## crease. A partial sweep gets flat ends.
static func lathe(b: B, prof: PackedVector2Array, segs: int, angle := TAU, phase := 0.0, facet := false) -> void:
	prof = _ccw(prof)
	var m := prof.size()
	if m < 2:
		return
	var full := angle >= TAU - 1e-4
	facet = facet or segs <= 8
	# the loop opened at an axis point (or a sharp corner), so each edge is a step of j
	var start := 0
	for k in m:
		if prof[k].x <= 1e-7 and prof[(k + 1) % m].x <= 1e-7:   # (an edge along the axis: it isn't swept)
			start = (k + 1) % m
			break
	var sharp := _sharp(prof)
	if start == 0 and not sharp.is_empty():
		start = sharp[0]
	var loop := _roll(prof, start)
	# along the axis edge (if any) the loop ends; otherwise it's closed (j wraps)
	var on_axis := loop[m - 1].x <= 1e-7 and loop[0].x <= 1e-7
	var path := loop.duplicate()
	if not on_axis:
		path.append(loop[0])
	var nj := path.size() - 1
	var jh := PackedInt32Array()
	var sh := _sharp(loop, 35.0, not on_axis)
	for k in sh:
		jh.append(k)
	if not on_axis and not sh.is_empty():
		jh.append(0)   # (the loop starts at a crease: no smoothing across its seam)
	var lens := _lengths(path, false)
	var tot := maxf(lens[nj], 1e-9)
	var vv := PackedFloat32Array()
	for j in nj + 1:
		vv.append(lens[j] / tot)
	var P := []
	var u := PackedFloat32Array()
	for i in segs + 1:
		var col := PackedVector3Array()
		for j in nj + 1:
			col.append(_rev(path[j], i, segs, angle, phase))
		P.append(col)
		u.append(float(i) / segs)
	var ih := PackedInt32Array()
	if facet:
		for i in range(1, segs):
			ih.append(i)
	b.sheet(P, ih, jh, full and not facet, not on_axis and sh.is_empty(), u, vv)
	if not full:
		# the ends: the profile, flat
		var c0 := PackedVector3Array()
		var c1 := PackedVector3Array()
		for k in m:
			c0.append(_rev(loop[k], 0, segs, angle, phase))
			c1.append(_rev(loop[k], segs, segs, angle, phase))
		var a0 := phase
		var a1 := phase + angle
		var n0 := Vector3(sin(a0), 0, cos(a0))    # (the swept direction's opposite at the start)
		var n1 := -Vector3(sin(a1), 0, cos(a1))
		b.cap(c0, n0, Vector3(cos(a0), 0, -sin(a0)), Vector3.UP)
		b.cap(c1, n1, Vector3(cos(a1), 0, -sin(a1)), Vector3.UP)


## Profile point `q` (r, y) at step i of segs (the same float math for every use, so
## shared points are equal).
static func _rev(q: Vector2, i: int, segs: int, angle: float, phase: float) -> Vector3:
	var a := phase + angle * float(i) / float(segs)
	if i == segs and angle >= TAU - 1e-4:
		a = phase
	return Vector3(q.x * cos(a), q.y, -q.x * sin(a))


# --- the prism: outlines (x, z) in layers up Y -----------------------------------------

## `layers`: [[y, PackedVector2Array outline], ...] bottom to top, outlines with the same
## count (counter-clockwise seen from above, i.e. in (x, -z)... given as (x, z) and turned
## as needed). Capped at both ends. `hole`: inner loops per layer (same count) - a ring.
static func prism(b: B, layers: Array, hole_layers := [], crease_deg := 35.0) -> void:
	if layers.size() < 2:
		return
	var first: PackedVector2Array = layers[0][1]
	var m := first.size()
	# (x, z) loops counter-clockwise looking down from +Y means clockwise in the (x, z) plane
	var flip := _area(first) > 0.0
	var L := []
	for ly in layers:
		var o: PackedVector2Array = ly[1]
		if flip:
			o = o.duplicate()
			o.reverse()
		L.append([float(ly[0]), o])
	var sharp := _sharp(L[int(L.size() / 2)][1], crease_deg)
	var start := sharp[0] if not sharp.is_empty() else 0
	for k in L.size():
		L[k][1] = _roll(L[k][1], start)
	var sh := PackedInt32Array()
	for k in sharp:
		sh.append((k - start + m) % m)
	_walls(b, L, sh, true)
	var bot: PackedVector2Array = L[0][1]
	var top: PackedVector2Array = L[L.size() - 1][1]
	var y0: float = L[0][0]
	var y1: float = L[L.size() - 1][0]
	if hole_layers.is_empty():
		var c0 := PackedVector3Array()
		var c1 := PackedVector3Array()
		for k in m:
			c0.append(Vector3(bot[k].x, y0, bot[k].y))
			c1.append(Vector3(top[k].x, y1, top[k].y))
		b.cap(c0, Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
		b.cap(c1, Vector3.UP, Vector3.RIGHT, Vector3.BACK)
		return
	var H := []
	for k in hole_layers.size():
		var o: PackedVector2Array = (hole_layers[k][1] as PackedVector2Array).duplicate()
		if _area(o) < 0.0:
			o.reverse()   # (the hole's walls face in: the other way round)
		H.append([float(hole_layers[k][0]), _roll_to(o, bot[0])])
	_walls(b, H, PackedInt32Array(), false)
	var hb: PackedVector2Array = H[0][1]
	var ht: PackedVector2Array = H[H.size() - 1][1]
	# annulus caps: outer and inner matched by angle (both star-shaped round the origin)
	b.ring_cap(_v3(bot, y0), _match(bot, hb, y0), Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
	b.ring_cap(_v3(top, y1), _match(top, ht, y1), Vector3.UP, Vector3.RIGHT, Vector3.BACK)


static func _v3(o: PackedVector2Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in o:
		out.append(Vector3(q.x, y, q.y))
	return out


## For each outer point, the inner loop's point at its angle (inner loops are made with the
## same count, so the same index after rolling to the nearest).
static func _match(outer: PackedVector2Array, inner: PackedVector2Array, y: float) -> PackedVector3Array:
	var rev := inner.duplicate()
	rev.reverse()   # (back to the outer's turning)
	rev = _roll_to(rev, outer[0])
	return _v3(rev, y)


static func _roll_to(o: PackedVector2Array, near: Vector2) -> PackedVector2Array:
	var best := 0
	var ba := INF
	for k in o.size():
		var d := absf(angle_difference(o[k].angle(), near.angle()))
		if d < ba:
			ba = d
			best = k
	return _roll(o, best)


## The side walls between layer loops; `outward`: the loops turn so the walls face out.
static func _walls(b: B, L: Array, sharp: PackedInt32Array, _outward: bool) -> void:
	var m: int = (L[0][1] as PackedVector2Array).size()
	var P := []
	var u := PackedFloat32Array()
	var mid: PackedVector2Array = L[int(L.size() / 2)][1]
	var lens := _lengths(mid, true)
	for i in m + 1:
		var col := PackedVector3Array()
		for ly in L:
			var o: PackedVector2Array = ly[1]
			var q := o[i % m]
			col.append(Vector3(q.x, float(ly[0]), q.y))
		P.append(col)
		u.append(lens[i])
	var vv := PackedFloat32Array()
	for ly in L:
		vv.append(float(ly[0]))
	# creases between layers that bend sharply (a bevel's edge)
	var jh := PackedInt32Array()
	var col0: PackedVector3Array = P[0]
	for j in range(1, L.size() - 1):
		var a := (col0[j] - col0[j - 1]).normalized()
		var c := (col0[j + 1] - col0[j]).normalized()
		if a.dot(c) < cos(deg_to_rad(30.0)):
			jh.append(j)
	b.sheet(P, sharp, jh, sharp.is_empty(), false, u, vv)


## Each point of a loop moved `d` inwards along its corner's bisector.
static func _inset(o: PackedVector2Array, d: float) -> PackedVector2Array:
	var m := o.size()
	var ccw := _area(o) > 0.0
	var out := PackedVector2Array()
	for k in m:
		var a := (o[k] - o[(k - 1 + m) % m]).normalized()
		var c := (o[(k + 1) % m] - o[k]).normalized()
		var n1 := Vector2(-a.y, a.x)
		var n2 := Vector2(-c.y, c.x)
		if not ccw:
			n1 = -n1
			n2 = -n2
		var bis := (n1 + n2)
		if bis.length() < 1e-6:
			bis = n1
		bis = bis.normalized()
		var s := clampf(1.0 / maxf(bis.dot(n1), 0.25), 1.0, 4.0)
		out.append(o[k] + bis * d * s)
	return out


## An outline extruded `h` up Y (centred), with a chamfer `bevel`.
static func extrude(b: B, o: PackedVector2Array, h: float, bevel := 0.0) -> void:
	var y0 := -h * 0.5
	var y1 := h * 0.5
	if bevel <= 1e-5:
		prism(b, [[y0, o], [y1, o]])
		return
	bevel = minf(bevel, h * 0.49)
	var inn := _inset(o, bevel)
	prism(b, [[y0, inn], [y0 + bevel, o], [y1 - bevel, o], [y1, inn]])


# --- the generators ----------------------------------------------------------------------

## A box (w, h, d) - rounded edges with a bevel: a cube's six faces, each a grid whose
## points are pushed round a rounded box (the bevel bands get `bevel_segs` rows each).
static func _box(b: B, p: Dictionary) -> void:
	var he := Vector3(_num(p, "w"), _num(p, "h"), _num(p, "d")) * 0.5
	var r := clampf(_num(p, "bevel"), 0.0, minf(he.x, minf(he.y, he.z)) * 0.999)
	var k := _int(p, "bevel_segs") if r > 0.0 else 0
	rounded_box(b, he, r, k)


static func rounded_box(b: B, he: Vector3, r: float, k: int) -> void:
	# the coordinates along each axis: -h, the bevel band, -(h - r), (h - r), the band, h
	var axes := []
	for a in 3:
		var h: float = he[a]
		var c := PackedFloat32Array()
		if k <= 0:
			c.append(-h); c.append(h)
		else:
			for s in k + 1:
				c.append(-(h - r) - r * tan(deg_to_rad(45.0) * (k - s) / k) if s < k else -(h - r))
			for s in k + 1:
				c.append((h - r) + r * tan(deg_to_rad(45.0) * s / k) if s > 0 else (h - r))
			c[0] = -h
			c[c.size() - 1] = h
		axes.append(c)
	var inner := he - Vector3.ONE * r
	var place := func(q: Vector3) -> Vector3:
		if r <= 0.0:
			return q
		var c := q.clamp(-inner, inner)
		var d := q - c
		return c + d.normalized() * r if d.length_squared() > 1e-20 else q
	var norm := func(q: Vector3) -> Vector3:
		var c := q.clamp(-inner, inner)
		return (q - c).normalized()
	# each face: (axis, sign); its grid runs over the other two axes so that di x dj = out
	for f in 6:
		var ax := f / 2
		var sg := 1.0 if f % 2 == 0 else -1.0
		var ua := (ax + 1) % 3
		var va := (ax + 2) % 3
		if sg < 0.0:
			var t := ua
			ua = va
			va = t
		var cu: PackedFloat32Array = axes[ua]
		var cv: PackedFloat32Array = axes[va]
		var P := []
		var Q := []   # (the cube points, for the normals)
		var u := PackedFloat32Array()
		var vv := PackedFloat32Array()
		for i in cu.size():
			var col := PackedVector3Array()
			var qc := PackedVector3Array()
			for j in cv.size():
				var q := Vector3.ZERO
				q[ax] = sg * he[ax]
				q[ua] = cu[i]
				q[va] = cv[j]
				qc.append(q)
				col.append(place.call(q))
			P.append(col)
			Q.append(qc)
			u.append(cu[i] / maxf(he[ua] * 2.0, 1e-6) + 0.5)
		for j in cv.size():
			vv.append(cv[j] / maxf(he[va] * 2.0, 1e-6) + 0.5)
		var fn := Callable()
		if r > 0.0:
			fn = func(i: int, j: int) -> Vector3:
				var n: Vector3 = norm.call((Q[i] as PackedVector3Array)[j])
				if n.length_squared() < 0.5:
					n = Vector3.ZERO
					n[ax] = sg
				return n
		b.sheet(P, PackedInt32Array(), PackedInt32Array(), false, false, u, vv, fn)


## A superellipsoid: |x|^(2/e2) + |z|^(2/e2) ... - from round (1, 1) to boxy (0.1) to
## star-like (3+); a cube's faces' points sent along their direction.
static func _superellipsoid(b: B, p: Dictionary) -> void:
	var he := Vector3(_num(p, "w"), _num(p, "h"), _num(p, "d")) * 0.5
	var e1 := maxf(_num(p, "e1"), 0.05)
	var e2 := maxf(_num(p, "e2"), 0.05)
	var res := maxi(_int(p, "res"), 2)
	var se := func(x: float, e: float) -> float:
		return signf(x) * pow(absf(x), e)
	var at := func(dir: Vector3) -> Array:
		var d := dir.normalized()
		var eta := asin(clampf(d.y, -1.0, 1.0))
		var om := atan2(d.z, d.x)
		var ce := cos(eta)
		var pos := Vector3(he.x * se.call(ce, e1) * se.call(cos(om), e2), he.y * se.call(sin(eta), e1), he.z * se.call(ce, e1) * se.call(sin(om), e2))
		var nrm := Vector3(se.call(ce, 2.0 - e1) * se.call(cos(om), 2.0 - e2) / he.x, se.call(sin(eta), 2.0 - e1) / he.y,
			se.call(ce, 2.0 - e1) * se.call(sin(om), 2.0 - e2) / he.z)
		if absf(d.y) > 0.99999:
			pos = Vector3(0, he.y * signf(d.y), 0)
			nrm = Vector3(0, signf(d.y), 0)
		return [pos, nrm.normalized() if nrm.length_squared() > 1e-20 else d]
	_cube_sphere(b, res, at)


## A cube's faces (res x res each, points spaced by angle) sent through `at(dir) -> [pos, normal]`.
static func _cube_sphere(b: B, res: int, at: Callable) -> void:
	var cs := PackedFloat32Array()
	for s in res + 1:
		cs.append(tan(deg_to_rad(-45.0 + 90.0 * s / res)) if s != 0 and s != res else (-1.0 if s == 0 else 1.0))
	for f in 6:
		var ax := f / 2
		var sg := 1.0 if f % 2 == 0 else -1.0
		var ua := (ax + 1) % 3
		var va := (ax + 2) % 3
		if sg < 0.0:
			var t := ua
			ua = va
			va = t
		var P := []
		var N := []
		for i in res + 1:
			var col := PackedVector3Array()
			var nc := PackedVector3Array()
			for j in res + 1:
				var q := Vector3.ZERO
				q[ax] = sg
				q[ua] = cs[i]
				q[va] = cs[j]
				var r: Array = at.call(q)
				col.append(r[0])
				nc.append(r[1])
			P.append(col)
			N.append(nc)
		b.sheet(P, PackedInt32Array(), PackedInt32Array(), false, false, PackedFloat32Array(), PackedFloat32Array(),
			func(i: int, j: int) -> Vector3: return (N[i] as PackedVector3Array)[j])


## A UV sphere (or a band of it: from / to latitude - a hemisphere, a dome; a shell
## `thickness` makes it hollow).
static func _sphere(b: B, p: Dictionary) -> void:
	var r := _num(p, "r")
	var segs := maxi(_int(p, "segs"), 3)
	var rings := maxi(_int(p, "rings"), 2)
	var l0 := deg_to_rad(_num(p, "lat0"))
	var l1 := deg_to_rad(maxf(_num(p, "lat1"), _num(p, "lat0") + 1.0))
	var sy := _num(p, "sy")
	var t := clampf(_num(p, "thickness"), 0.0, r * 0.95)
	var prof := PackedVector2Array()
	var n := maxi(2, int(ceil(rings * (l1 - l0) / PI)))
	if t <= 0.0:
		if l0 > -PI * 0.5 + 1e-4:
			prof.append(Vector2(0, sin(l0) * r * sy))
		for k in n + 1:
			var a := l0 + (l1 - l0) * k / n
			prof.append(Vector2(cos(a) * r if absf(cos(a)) > 1e-6 else 0.0, sin(a) * r * sy))
		if l1 < PI * 0.5 - 1e-4:
			prof.append(Vector2(0, sin(l1) * r * sy))
	else:
		var ri := r - t
		for k in n + 1:
			var a := l0 + (l1 - l0) * k / n
			prof.append(Vector2(cos(a) * r if absf(cos(a)) > 1e-6 else 0.0, sin(a) * r * sy))
		for k in n + 1:
			var a := l1 - (l1 - l0) * k / n
			prof.append(Vector2(cos(a) * ri if absf(cos(a)) > 1e-6 else 0.0, sin(a) * ri * sy))
		prof = _dedupe(prof)
	lathe(b, prof, segs, TAU, 0.0, false)


## Consecutive equal points dropped (a loop).
static func _dedupe(o: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in o:
		if out.is_empty() or out[out.size() - 1].distance_to(q) > 1e-7:
			out.append(q)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 1e-7:
		out.remove_at(out.size() - 1)
	return out


## An icosahedron subdivided onto a sphere - with noise a rock or a pebble.
static func _ico(b: B, p: Dictionary) -> void:
	var r := _num(p, "r")
	var t := (1.0 + sqrt(5.0)) * 0.5
	var pts := PackedVector3Array([Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for k in pts.size():
		pts[k] = pts[k].normalized()
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for k in range(0, faces.size(), 3):   # (each face turned outward)
		var a := pts[faces[k]]
		if (pts[faces[k + 1]] - a).cross(pts[faces[k + 2]] - a).dot(a) < 0.0:
			var s := faces[k + 1]
			faces[k + 1] = faces[k + 2]
			faces[k + 2] = s
	for s in clampi(_int(p, "subdiv"), 0, 5):
		var mid := {}
		var nf := PackedInt32Array()
		for k in range(0, faces.size(), 3):
			var m := PackedInt32Array()
			for e in 3:
				var i0 := faces[k + e]
				var i1 := faces[k + (e + 1) % 3]
				var key := Vector2i(mini(i0, i1), maxi(i0, i1))
				if not mid.has(key):
					mid[key] = pts.size()
					pts.append(((pts[i0] + pts[i1]) * 0.5).normalized())
				m.append(mid[key])
			var a := faces[k]; var bb := faces[k + 1]; var c := faces[k + 2]
			nf.append_array(PackedInt32Array([a, m[0], m[2], bb, m[1], m[0], c, m[2], m[1], m[0], m[1], m[2]]))
		faces = nf
	var sc := Vector3(_num(p, "sx"), _num(p, "sy"), _num(p, "sz")) * r
	var amt := _num(p, "noise")
	var noise: FastNoiseLite = null
	if amt > 0.0:
		noise = FastNoiseLite.new()
		noise.seed = _int(p, "seed")
		noise.frequency = _num(p, "freq")
		noise.fractal_octaves = 3
	var pos := PackedVector3Array()
	for q in pts:
		var k := 1.0
		if noise:
			k = maxf(0.2, 1.0 + amt * noise.get_noise_3dv(q * 1.7))
		pos.append(q * k * sc)
	var faceted := _int(p, "faceted") > 0
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for k in range(0, faces.size(), 3):
		var a := pos[faces[k]]
		var f := (pos[faces[k + 1]] - a).cross(pos[faces[k + 2]] - a)
		for e in 3:
			nrm[faces[k + e]] += f
	# each triangle its own corners (the UVs wrap round without a seam stretch)
	for k in range(0, faces.size(), 3):
		var uvs := []
		for e in 3:
			var d := pts[faces[k + e]]
			uvs.append(Vector2(0.5 + atan2(d.x, d.z) / TAU, 0.5 - asin(clampf(d.y, -1.0, 1.0)) / PI))
		var us := [uvs[0].x, uvs[1].x, uvs[2].x]
		for e in 3:
			if absf(pts[faces[k + e]].y) > 0.9999:   # (a pole: the other two's u)
				var o: Array = []
				for e2 in 3:
					if e2 != e:
						o.append(us[e2])
				us[e] = (o[0] + o[1]) * 0.5
		var mx: float = maxf(us[0], maxf(us[1], us[2]))
		for e in 3:
			if mx - us[e] > 0.5:
				us[e] += 1.0
		var fnrm := (pos[faces[k + 1]] - pos[faces[k]]).cross(pos[faces[k + 2]] - pos[faces[k]]).normalized()
		var ids := []
		for e in 3:
			ids.append(b.add(pos[faces[k + e]], fnrm if faceted else nrm[faces[k + e]].normalized(), Vector2(us[e], uvs[e].y)))
		b.tri(ids[0], ids[1], ids[2])


## Cylinder, cone, frustum, tube, prism, pyramid: a profile revolved (sides <= 8: faceted).
static func _cylinder(b: B, p: Dictionary) -> void:
	var r0 := _num(p, "r")
	var r1 := _num(p, "r_top")
	var h := _num(p, "h")
	var segs := maxi(_int(p, "segs"), 3)
	var hole := minf(_num(p, "hole"), minf(r0, r1) * 0.98) if _num(p, "hole") > 0.0 else 0.0
	var bev := clampf(_num(p, "bevel"), 0.0, minf(h * 0.45, maxf(minf(r0, r1) - hole, 0.0) * 0.45))
	var y0 := -h * 0.5
	var y1 := h * 0.5
	var prof := PackedVector2Array()
	prof.append(Vector2(hole, y0))
	if bev > 0.0 and r0 > bev:
		prof.append(Vector2(r0 - bev, y0))
		prof.append(Vector2(r0, y0 + bev))
	else:
		prof.append(Vector2(r0, y0))
	if bev > 0.0 and r1 > bev:
		prof.append(Vector2(r1, y1 - bev))
		prof.append(Vector2(r1 - bev, y1))
	else:
		prof.append(Vector2(r1, y1))
	prof.append(Vector2(hole, y1))
	prof = _dedupe(prof)
	lathe(b, prof, segs, TAU, deg_to_rad(_num(p, "phase")))


static func _capsule(b: B, p: Dictionary) -> void:
	var r := _num(p, "r")
	var h := maxf(_num(p, "h"), r * 2.0)
	var rings := maxi(_int(p, "rings"), 1)
	var prof := PackedVector2Array()
	var c := h * 0.5 - r
	for k in rings + 1:
		var a := -PI * 0.5 + PI * 0.5 * k / rings
		prof.append(Vector2(cos(a) * r if k > 0 else 0.0, -c + sin(a) * r))
	for k in rings + 1:
		var a := PI * 0.5 * k / rings
		prof.append(Vector2(cos(a) * r if k < rings else 0.0, c + sin(a) * r))
	lathe(b, _dedupe(prof), maxi(_int(p, "segs"), 3))


static func _torus(b: B, p: Dictionary) -> void:
	var R := _num(p, "R")
	var r := minf(_num(p, "r"), R * 0.999)
	var sides := maxi(_int(p, "sides"), 3)
	var prof := PackedVector2Array()
	for k in sides:
		var a := TAU * k / sides
		prof.append(Vector2(R + cos(a) * r, sin(a) * r * _num(p, "sy")))
	lathe(b, prof, maxi(_int(p, "segs"), 3), deg_to_rad(_num(p, "angle")), 0.0, false)


static func _lathe_gen(b: B, p: Dictionary) -> void:
	var prof := _pts(p.get("points", []))
	if prof.size() < 2:
		prof = PackedVector2Array([Vector2(0, -0.5), Vector2(0.5, -0.5), Vector2(0.3, 0.5), Vector2(0, 0.5)])
	var sr := _num(p, "sr")
	var sy := _num(p, "sy")
	for k in prof.size():
		prof[k] = Vector2(maxf(prof[k].x, 0.0) * sr, prof[k].y * sy)
	lathe(b, _dedupe(prof), maxi(_int(p, "segs"), 3), deg_to_rad(_num(p, "angle")), deg_to_rad(_num(p, "phase")), _int(p, "facet") > 0)


static func _extrude_gen(b: B, p: Dictionary) -> void:
	var o := _pts(p.get("points", []))
	if o.size() < 3:
		o = _circle(6, 0.5)
	var sx := _num(p, "sx")
	var sz := _num(p, "sz")
	for k in o.size():
		o[k] = Vector2(o[k].x * sx, o[k].y * sz)
	var t := Transform3D()
	if str(p.get("axis", "y")) == "z":   # (stood up: the outline in x, y; the depth along z)
		t = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		for k in o.size():
			o[k] = Vector2(o[k].x, -o[k].y)
	var keep := b.xf
	b.xf = keep * t
	extrude(b, _dedupe(o), _num(p, "h"), _num(p, "bevel"))
	b.xf = keep


static func _loft(b: B, p: Dictionary) -> void:
	var na := maxi(_int(p, "sides_a"), 3)
	var nb := maxi(_int(p, "sides_b"), 3)
	var n := maxi(na, nb)
	n = n * maxi(1, 48 / n) if na != nb else n   # (a fine common count when the two differ)
	var A := _poly_resampled(na, _num(p, "r_a"), n)
	var Bo := _poly_resampled(nb, _num(p, "r_b"), n)
	var lay := maxi(_int(p, "layers"), 1)
	var h := _num(p, "h")
	var tw := deg_to_rad(_num(p, "twist"))
	var bulge := _num(p, "bulge")
	var layers := []
	for k in lay + 1:
		var t := float(k) / lay
		var o := PackedVector2Array()
		var s := 1.0 + bulge * sin(PI * t)
		for q in n:
			o.append(A[q].lerp(Bo[q], t).rotated(tw * t) * s)
		layers.append([-h * 0.5 + h * t, o])
	# (the ends: a point when a radius is 0 - made a tiny polygon so the walls close on it)
	prism(b, layers, [], 35.0 if na == nb else 89.0)


## A regular polygon (`sides`, circumradius r) as `n` points spaced along its outline.
static func _poly_resampled(sides: int, r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ph := PI / sides + PI * 0.5 if sides % 2 == 0 else PI * 0.5
	for k in n:
		var t := float(k) / n * sides
		var e := int(floor(t))
		var f := t - e
		var a0 := ph + TAU * e / sides
		var a1 := ph + TAU * (e + 1) / sides
		out.append(Vector2(cos(a0), sin(a0)).lerp(Vector2(cos(a1), sin(a1)), f) * maxf(r, 1e-4))
	return out


static func _star(b: B, p: Dictionary) -> void:
	var n := maxi(_int(p, "n"), 3)
	var o := PackedVector2Array()
	for k in n * 2:
		var a := PI * 0.5 + PI * k / n
		var r := _num(p, "r_out") if k % 2 == 0 else _num(p, "r_in")
		o.append(Vector2(cos(a), -sin(a)) * r)
	extrude(b, o, _num(p, "h"), _num(p, "bevel"))


static func _gear(b: B, p: Dictionary) -> void:
	var teeth := _int(p, "teeth")
	var r := _num(p, "r")
	var dep := minf(_num(p, "depth"), r * 0.8)
	var h := _num(p, "h")
	var bore := _num(p, "bore")
	var o := PackedVector2Array()
	if teeth <= 0:
		o = _circle(maxi(_int(p, "sides"), 3), r, PI / maxi(_int(p, "sides"), 3))
	else:
		var tw := clampf(_num(p, "tooth_w"), 0.1, 0.9)
		var ri := r - dep
		for k in teeth:
			var a := TAU * k / teeth
			var step := TAU / teeth
			var w := step * tw
			var tip := w * 0.7
			for q in [[a - w * 0.5, ri], [a - tip * 0.5, r], [a + tip * 0.5, r], [a + w * 0.5, ri]]:
				o.append(Vector2(cos(q[0]), sin(q[0])) * q[1])
			# the root between teeth: a few points on the inner circle
			for s in 2:
				var aa := a + w * 0.5 + (step - w) * (s + 1) / 3.0
				o.append(Vector2(cos(aa), sin(aa)) * ri)
	if bore <= 0.0:
		extrude(b, o, h)
		return
	bore = minf(bore, (r - dep) * 0.95)
	var inner := PackedVector2Array()
	for q in o:   # (the hole: the outline's angles on a circle - the same count)
		inner.append(q.normalized() * bore)
	prism(b, [[-h * 0.5, o], [h * 0.5, o]], [[-h * 0.5, inner], [h * 0.5, inner]])


static func _wedge(b: B, p: Dictionary) -> void:
	var w := _num(p, "w")
	var h := _num(p, "h")
	var d := _num(p, "d")
	var top := clampf(_num(p, "top"), 0.0, d)
	var o := PackedVector2Array([Vector2(-d * 0.5, -h * 0.5), Vector2(d * 0.5, -h * 0.5), Vector2(-d * 0.5 + top, h * 0.5)])
	if top > 1e-4:
		o.append(Vector2(-d * 0.5, h * 0.5))
	# the side outline (z, y) extruded along x
	_side_extrude(b, o, w)


## An outline in (z, y) extruded `w` along X (centred).
static func _side_extrude(b: B, o: PackedVector2Array, w: float) -> void:
	var keep := b.xf
	# the prism runs up Y with its outline in (x, z): turn it so Y becomes X, x -> z, z -> y
	b.xf = keep * Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3.ZERO)
	extrude(b, o, w)
	b.xf = keep


static func _arch(b: B, p: Dictionary) -> void:
	var w := _num(p, "w")
	var h := _num(p, "h")
	var op := clampf(_num(p, "opening"), 0.02, w * 0.96)
	var sp := clampf(_num(p, "spring"), 0.0, h * 0.95)
	var segs := maxi(_int(p, "segs"), 2)
	var pointed := clampf(_num(p, "pointed"), 0.0, 1.0)
	var ro := op * 0.5
	var crown := minf(sp + ro * (1.0 + pointed * 0.8), h - 0.02 * h)
	var o := PackedVector2Array()
	o.append(Vector2(-w * 0.5, 0))
	o.append(Vector2(-ro, 0))
	o.append(Vector2(-ro, sp))
	for k in range(1, segs):
		var t := float(k) / segs
		var a := PI - PI * t
		var q := Vector2(cos(a) * ro, sp + sin(a) * (crown - sp))
		if pointed > 0.0:   # (two arcs meeting in a point: the round arch pinched up)
			var s := 1.0 - absf(2.0 * t - 1.0)
			q.y = sp + (crown - sp) * lerpf(sin(a), s * (2.0 - s), pointed)
		o.append(q)
	o.append(Vector2(ro, sp))
	o.append(Vector2(ro, 0))
	o.append(Vector2(w * 0.5, 0))
	o.append(Vector2(w * 0.5, h))
	o.append(Vector2(-w * 0.5, h))
	for k in o.size():
		o[k].y -= h * 0.5
	# outline in (x, y), depth along z
	var keep := b.xf
	b.xf = keep * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	for k in o.size():
		o[k] = Vector2(o[k].x, -o[k].y)
	extrude(b, o, _num(p, "d"))
	b.xf = keep


static func _stairs(b: B, p: Dictionary) -> void:
	var n := maxi(_int(p, "steps"), 1)
	var w := _num(p, "w")
	var h := _num(p, "h")
	var d := _num(p, "d")
	var sh := h / n
	var sd := d / n
	var o := PackedVector2Array()
	# side outline in (z, y): front at -d/2, rising toward +z
	var z0 := -d * 0.5
	var y0 := -h * 0.5
	o.append(Vector2(z0, y0))
	for k in n:
		o.append(Vector2(z0 + sd * k, y0 + sh * (k + 1)))
		o.append(Vector2(z0 + sd * (k + 1), y0 + sh * (k + 1)))
	var t := clampf(_num(p, "t"), 0.005, h)
	var yb := y0 + h - sh - t
	var zf := z0 + sd + t * sd / sh
	if _int(p, "under") > 0 or n < 2 or yb <= y0 or zf >= z0 + d - 1e-4:
		o.append(Vector2(z0 + d, y0))
	else:   # (a slab under the steps, parallel to their slope)
		o.append(Vector2(z0 + d, yb))
		o.append(Vector2(zf, y0))
	o = _dedupe(o)
	_side_extrude(b, o, w)


static func _spiral_stairs(b: B, p: Dictionary) -> void:
	var n := maxi(_int(p, "steps"), 2)
	var r := _num(p, "r")
	var h := _num(p, "h")
	var turn := deg_to_rad(_num(p, "turn"))
	var col := _num(p, "column")
	var t := _num(p, "t")
	var sh := h / n
	var ang := turn / n
	if col > 0.0:
		var c := B.new()
		lathe(c, PackedVector2Array([Vector2(0, 0), Vector2(col, 0), Vector2(col, h + t), Vector2(0, h + t)]), 24)
		b.merge(c, Transform3D(Basis(), Vector3(0, -h * 0.5, 0)))
	for k in n:
		# each step a wedge of the circle (from the column out), overlapping the next a little
		var s := B.new()
		var a0 := -ang * 0.62
		var a1 := ang * 0.62
		var ri := maxf(col * 0.5, 0.0)
		var o := PackedVector2Array([Vector2(cos(a0), sin(a0)) * ri, Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a1), sin(a1)) * r, Vector2(cos(a1), sin(a1)) * ri])
		if ri <= 1e-4:
			o.remove_at(3)
			o[0] = Vector2.ZERO
		extrude(s, _dedupe(o), t)
		var y := -h * 0.5 + sh * (k + 1)
		b.merge(s, Transform3D(Basis(Vector3.UP, ang * k), Vector3(0, y, 0)))


## A tube of `profile` (a loop, counter-clockwise) along the path `C` (points; `closed`:
## a loop) with radius scale per point `sc` - parallel-transported frames.
static func sweep(b: B, C: PackedVector3Array, profile: PackedVector2Array, closed: bool, sc := PackedFloat32Array(), up := Vector3.UP) -> void:
	var m := C.size()
	if m < 2:
		return
	profile = _ccw(profile)
	if sc.is_empty():
		for k in m:
			sc.append(1.0)
	var T := PackedVector3Array()
	for k in m:
		var a := C[(k - 1 + m) % m] if (closed or k > 0) else C[k]
		var c := C[(k + 1) % m] if (closed or k < m - 1) else C[k]
		T.append((c - a).normalized())
	var N := PackedVector3Array()
	var n0 := up.cross(T[0])
	if n0.length() < 1e-4:
		n0 = Vector3.RIGHT.cross(T[0])
	n0 = n0.normalized()
	N.append(n0)
	for k in range(1, m):
		var prev := N[k - 1]
		var nn := prev - T[k] * prev.dot(T[k])
		if nn.length() < 1e-6:
			nn = prev
		N.append(nn.normalized())
	if closed:   # (the frame's turn round the loop shared out along it)
		var last := N[m - 1] - T[0] * N[m - 1].dot(T[0])
		var tw := last.normalized().signed_angle_to(N[0], T[0])
		for k in m:
			N[k] = N[k].rotated(T[k], tw * k / m)
	var ns := profile.size()
	var cols := []
	var path_n := m + (1 if closed else 0)
	for i in ns + 1:
		var q := profile[i % ns]
		var col := PackedVector3Array()
		for j in path_n:
			var k := j % m
			var bn := T[k].cross(N[k])
			col.append(C[k] + (N[k] * q.x + bn * q.y) * sc[k])
		cols.append(col)
	# columns run round the profile (i), rows along the path (j): faces di x dj = out
	var u := PackedFloat32Array()
	for i in ns + 1:
		u.append(float(i) / ns)
	var lens := PackedFloat32Array([0.0])
	for j in range(1, path_n):
		lens.append(lens[j - 1] + C[j % m].distance_to(C[(j - 1) % m]))
	var sharp := _sharp(profile, 50.0)
	b.sheet(cols, sharp, PackedInt32Array(), sharp.is_empty(), closed, u, lens)
	if not closed:
		var c0 := PackedVector3Array()
		var c1 := PackedVector3Array()
		for i in ns:
			c0.append((cols[i] as PackedVector3Array)[0])
			c1.append((cols[i] as PackedVector3Array)[m - 1])
		if sc[0] > 1e-6:
			b.cap(c0, -T[0], N[0], T[0].cross(N[0]))
		if sc[m - 1] > 1e-6:
			b.cap(c1, T[m - 1], N[m - 1], T[m - 1].cross(N[m - 1]))


static func _spring(b: B, p: Dictionary) -> void:
	var R := _num(p, "R")
	var turns := maxf(_num(p, "turns"), 0.05)
	var h := _num(p, "h")
	var segs := maxi(int(_int(p, "segs") * turns), 4)
	var taper := _num(p, "taper")
	var C := PackedVector3Array()
	for k in segs + 1:
		var t := float(k) / segs
		var a := TAU * turns * t
		var rr := R * (1.0 - taper * t)
		C.append(Vector3(cos(a) * rr, -h * 0.5 + h * t, -sin(a) * rr))
	sweep(b, C, _circle(maxi(_int(p, "sides"), 3), _num(p, "r")), false)


static func _knot(b: B, p: Dictionary) -> void:
	var pp := maxi(_int(p, "p"), 1)
	var q := maxi(_int(p, "q"), 1)
	var R := _num(p, "R")
	var segs := maxi(_int(p, "segs"), 16)
	var C := PackedVector3Array()
	for k in segs:
		var t := TAU * k / segs
		var rr := R * (2.0 + cos(q * t)) / 3.0
		C.append(Vector3(rr * cos(pp * t), R * sin(q * t) / 3.0, rr * sin(pp * t)))
	sweep(b, C, _circle(maxi(_int(p, "sides"), 3), _num(p, "r")), true)


static func _chain(b: B, p: Dictionary) -> void:
	var L := _num(p, "L")
	var W := _num(p, "W")
	var r := _num(p, "r")
	var segs := maxi(_int(p, "segs"), 8)
	var rr := maxf(W * 0.5 - r, r * 1.1)
	var st := maxf(L * 0.5 - r - rr, 0.0)
	# a stadium in the (x, y) plane: two half circles joined by straights
	var half := maxi(segs / 2, 3)
	var D := PackedVector3Array()
	for side in 2:
		var cy := st if side == 0 else -st
		for k in half + 1:
			var a := PI * side + PI * k / half
			D.append(Vector3(cos(a) * rr, cy + sin(a) * rr, 0))
		if st > 1e-4:   # (the straight down / up to the other arc)
			var from := D[D.size() - 1]
			var to := Vector3(from.x, -cy, 0)
			for s in range(1, 4):
				D.append(from.lerp(to, s / 4.0))
		else:
			D.remove_at(D.size() - 1)
	sweep(b, D, _circle(maxi(_int(p, "sides"), 3), r), true, PackedFloat32Array(), Vector3.FORWARD)


static func _column(b: B, p: Dictionary) -> void:
	var r := _num(p, "r")
	var h := _num(p, "h")
	var fl := _int(p, "flutes")
	var dep := _num(p, "depth")
	var taper := _num(p, "taper")
	var segs := maxi(_int(p, "segs"), 8)
	if fl > 0:
		segs = maxi(segs / fl, 3) * fl
	var cap := _int(p, "capital")
	var base := _int(p, "base")
	var cap_h := 0.0 if cap == 0 else r * (0.9 if cap != 3 else 2.2)
	var base_h := 0.0 if base == 0 else r * 0.5
	var y0 := -h * 0.5 + base_h
	var y1 := h * 0.5 - cap_h
	var shaft_h := y1 - y0
	var rings := 12
	var P := []
	var u := PackedFloat32Array()
	for i in segs + 1:
		var a := TAU * float(i % segs) / segs
		var col := PackedVector3Array()
		# a flute: a shallow scallop; the shaft swells a little (entasis) and narrows up
		var f := 0.0
		if fl > 0:
			var x := fposmod(a * fl / TAU, 1.0)
			f = dep * sin(PI * x)
		for j in rings + 1:
			var t := float(j) / rings
			var rad := (r * lerpf(1.0, taper, t) * (1.0 + 0.025 * sin(PI * t))) - f
			col.append(Vector3(cos(a) * rad, y0 + shaft_h * t, -sin(a) * rad))
		P.append(col)
		u.append(float(i) / segs)
	var ih := PackedInt32Array()
	if fl > 0:
		for k in range(1, fl):
			ih.append(k * segs / fl)
	b.sheet(P, ih, PackedInt32Array(), fl == 0, false, u)
	# its ends: flat (the column's base and capital overlap them)
	var c0 := PackedVector3Array()
	var c1 := PackedVector3Array()
	for i in segs:
		c0.append((P[i] as PackedVector3Array)[0])
		c1.append((P[i] as PackedVector3Array)[rings])
	b.cap(c0, Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
	b.cap(c1, Vector3.UP, Vector3.RIGHT, Vector3.BACK)
	var rt := r * taper
	var ov := 0.002 * h   # (the pieces overlap their neighbours a hair)
	match base:
		1:   # a torus moulding on a low disc
			var c := B.new()
			lathe(c, PackedVector2Array([Vector2(0, 0), Vector2(r * 1.3, 0), Vector2(r * 1.3, base_h * 0.35), Vector2(r * 1.22, base_h * 0.55),
				Vector2(r * 1.18, base_h * 0.8), Vector2(r * 1.08, base_h), Vector2(r * 0.95, base_h + ov), Vector2(0, base_h + ov)]), 40)
			b.merge(c, Transform3D(Basis(), Vector3(0, -h * 0.5, 0)))
		2:   # a square plinth
			var c := B.new()
			rounded_box(c, Vector3(r * 1.35, base_h * 0.5 + ov * 0.5, r * 1.35), 0.0, 0)
			b.merge(c, Transform3D(Basis(), Vector3(0, -h * 0.5 + base_h * 0.5 + ov * 0.5, 0)))
	match cap:
		1, 2:   # Doric: an echinus (a cushion) under an abacus (a slab); Ionic: thinner, with volutes
			var c := B.new()
			var ech := cap_h * (0.55 if cap == 1 else 0.4)
			lathe(c, PackedVector2Array([Vector2(0, -ov), Vector2(rt * 0.98, -ov), Vector2(rt * 1.08, ech * 0.3), Vector2(rt * 1.28, ech * 0.75),
				Vector2(rt * 1.35, ech + ov), Vector2(0, ech + ov)]), 40)
			b.merge(c, Transform3D(Basis(), Vector3(0, y1, 0)))
			var ab := B.new()
			var abh := cap_h - ech
			rounded_box(ab, Vector3(rt * 1.45, abh * 0.5, rt * 1.45), 0.0, 0)
			b.merge(ab, Transform3D(Basis(), Vector3(0, y1 + ech + abh * 0.5, 0)))
			if cap == 2:   # two volutes: scrolls either side
				for s in [-1.0, 1.0]:
					var v := B.new()
					lathe(v, PackedVector2Array([Vector2(0, -rt * 1.4), Vector2(ech * 0.55, -rt * 1.4), Vector2(ech * 0.62, -rt * 1.3),
						Vector2(ech * 0.62, rt * 1.3), Vector2(ech * 0.55, rt * 1.4), Vector2(0, rt * 1.4)]), 20)
					b.merge(v, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s * rt * 1.15, y1 + ech * 0.55, 0)))
		3:   # Corinthian: a bell flaring out, leaves as a ribbed band, a thin abacus
			var c := B.new()
			var bell := cap_h * 0.82
			var prof := PackedVector2Array([Vector2(0, -ov), Vector2(rt * 0.98, -ov)])
			for k in range(1, 9):
				var t := float(k) / 8
				prof.append(Vector2(rt * (1.0 + 0.45 * t * t) + rt * 0.06 * sin(t * PI * 3.0), bell * t))
			prof.append(Vector2(0, bell))
			lathe(c, prof, 48)
			b.merge(c, Transform3D(Basis(), Vector3(0, y1, 0)))
			var ab := B.new()
			rounded_box(ab, Vector3(rt * 1.6, (cap_h - bell) * 0.5 + ov, rt * 1.6), 0.0, 0)
			b.merge(ab, Transform3D(Basis(), Vector3(0, y1 + bell + (cap_h - bell) * 0.5 - ov, 0)))
		4:   # Minoan: a round cushion and a square slab (the shaft below usually narrows down: taper > 1)
			var c := B.new()
			lathe(c, PackedVector2Array([Vector2(0, -ov), Vector2(rt * 1.0, -ov), Vector2(rt * 1.4, cap_h * 0.2), Vector2(rt * 1.5, cap_h * 0.4),
				Vector2(rt * 1.4, cap_h * 0.6), Vector2(rt * 1.1, cap_h * 0.7), Vector2(0, cap_h * 0.7)]), 40)
			b.merge(c, Transform3D(Basis(), Vector3(0, y1, 0)))
			var ab := B.new()
			rounded_box(ab, Vector3(rt * 1.55, cap_h * 0.15 + ov, rt * 1.55), 0.0, 0)
			b.merge(ab, Transform3D(Basis(), Vector3(0, y1 + cap_h * 0.85 - ov, 0)))


static func _bolt(b: B, p: Dictionary) -> void:
	var hs := _int(p, "head_sides")
	var hr := _num(p, "head_r")
	var hh := _num(p, "head_h")
	var r := _num(p, "r")
	var L := _num(p, "length")
	var pitch := maxf(_num(p, "pitch"), 0.001)
	var th := minf(_num(p, "thread"), r * 0.4)
	# the head (on top) - a prism with a little chamfer, or a dome
	var hd := B.new()
	if hs >= 3:
		_cylinder(hd, {"r": hr, "r_top": hr, "h": hh, "segs": hs, "bevel": minf(hh, hr) * 0.12, "phase": 0.0, "hole": 0.0})
	else:
		_sphere(hd, {"r": hr, "segs": 32, "rings": 12, "lat0": 0.0, "lat1": 90.0, "thickness": 0.0, "sy": hh / maxf(hr, 1e-4)})
	b.merge(hd, Transform3D(Basis(), Vector3(0, L * 0.5 + (hh * 0.5 if hs >= 3 else 0.0), 0)))
	# the shaft: its radius rising and falling along a helix (the thread), a point at the tip
	var segs := 32
	var rows := maxi(int(L / pitch * 6.0), 8)
	var P := []
	for i in segs + 1:
		var a := TAU * float(i % segs) / segs
		var col := PackedVector3Array()
		col.append(Vector3(0, -L * 0.5 - r * 0.4, 0))
		for j in rows + 1:
			var t := float(j) / rows
			var y := -L * 0.5 + L * t
			var ph := fposmod(a / TAU + y / pitch, 1.0)
			var rad := r - th * 2.0 * absf(ph - 0.5)   # (a triangle wave: the crest at r, the root th in)
			if t < 0.04:
				rad *= lerpf(0.7, 1.0, t / 0.04)
			col.append(Vector3(cos(a) * rad, y + (hh * 0.05 if j == rows else 0.0), -sin(a) * rad))
		col.append(Vector3(0, L * 0.5 + hh * 0.05, 0))
		P.append(col)
	b.sheet(P, PackedInt32Array(), PackedInt32Array([1, rows + 1]), true, false)


static func _horn(b: B, p: Dictionary) -> void:
	var r0 := _num(p, "r")
	var r1 := _num(p, "r_tip")
	var L := _num(p, "length")
	var curl := deg_to_rad(_num(p, "curl"))
	var spiral := _num(p, "spiral")
	var rise := _num(p, "rise")
	var segs := maxi(_int(p, "segs"), 4)
	var ribs := _int(p, "ribs")
	var C := PackedVector3Array()
	var S := PackedFloat32Array()
	# the path: up from the base, bending through `curl` (a circle - shrinking with spiral)
	var pos := Vector3.ZERO
	var dir := Vector3.UP
	var step := L / segs
	for k in segs + 1:
		var t := float(k) / segs
		C.append(pos)
		var rad := lerpf(r0, r1, pow(t, 0.9))
		if ribs > 0:
			rad *= 1.0 + 0.08 * maxf(0.0, sin(t * PI * ribs * 2.0))
		S.append(maxf(rad, 0.0) / maxf(r0, 1e-6))
		var turn := curl / segs * (1.0 + spiral * 2.5 * t)
		dir = dir.rotated(Vector3.BACK, -turn).normalized()
		pos += dir * step * (1.0 - spiral * 0.7 * t) + Vector3(0, 0, rise / segs)
	# (the tip a point: the last ring scaled to nothing closes the tube)
	if S[segs] <= 1e-4:
		S[segs] = 0.0
	var sides := maxi(_int(p, "sides"), 3)
	sweep(b, C, _circle(sides, r0), false, S, Vector3.BACK)
	if S[segs] <= 0.0:   # (a closed tip: the collapsed ring is its own point - done)
		pass
	var box := AABB(C[0], Vector3.ZERO)
	for q in C:
		box = box.expand(q)
	var off := -box.get_center()
	for k in b.v.size():
		b.v[k] += off


static func _greeble(b: B, p: Dictionary) -> void:
	var w := _num(p, "w")
	var d := _num(p, "d")
	var t := _num(p, "t")
	var n := _int(p, "count")
	var hh := _num(p, "height")
	var kind := _int(p, "kind")
	var rng := RandomNumberGenerator.new()
	rng.seed = _int(p, "seed") * 7919 + 13
	rounded_box(b, Vector3(w, t, d) * 0.5, minf(t * 0.2, 0.01), 1)
	var top := t * 0.5
	var sink := t * 0.25   # (details sink into the plate a little: closed pieces overlapping)
	match kind:
		0:   # blocks of a few sizes
			for k in n:
				var s := Vector3(rng.randf_range(0.06, 0.28) * w, rng.randf_range(0.3, 1.0) * hh, rng.randf_range(0.06, 0.28) * d)
				var c := Vector3(rng.randf_range(-0.5, 0.5) * (w - s.x), top + s.y * 0.5 - sink * 0.5, rng.randf_range(-0.5, 0.5) * (d - s.z))
				var q := B.new()
				rounded_box(q, Vector3(s.x * 0.5, s.y * 0.5 + sink * 0.5, s.z * 0.5), minf(s.y, minf(s.x, s.z)) * 0.08, 1)
				b.merge(q, Transform3D(Basis(), c))
		1:   # vents: a row of slats in a frame
			var cnt := maxi(n, 2)
			for k in cnt:
				var q := B.new()
				var sw := d / cnt * 0.45
				rounded_box(q, Vector3(w * 0.4, hh * 0.5 + sink * 0.5, sw * 0.5), 0.0, 0)
				b.merge(q, Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, top + hh * 0.3, -d * 0.45 + (k + 0.5) * d * 0.9 / cnt)))
		2:   # pipes along the plate, and boxes
			for k in n:
				var q := B.new()
				var pr := rng.randf_range(0.2, 0.5) * hh
				_cylinder(q, {"r": pr, "r_top": pr, "h": rng.randf_range(0.4, 0.95) * w, "segs": 12, "hole": 0.0, "bevel": 0.0, "phase": 0.0})
				var z := rng.randf_range(-0.45, 0.45) * d
				b.merge(q, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(rng.randf_range(-0.05, 0.05) * w, top + pr - sink * 0.5, z)))
		3:   # raised tiles in a grid
			var g := maxi(int(sqrt(maxf(n, 1))), 1)
			for i in g:
				for j in g:
					if rng.randf() < 0.2:
						continue
					var q := B.new()
					var sx := w / g * 0.86
					var sz := d / g * 0.86
					var sy := hh * rng.randf_range(0.3, 1.0)
					rounded_box(q, Vector3(sx * 0.5, sy * 0.5 + sink * 0.5, sz * 0.5), minf(sy, minf(sx, sz)) * 0.15, 1)
					b.merge(q, Transform3D(Basis(), Vector3(-w * 0.5 + (i + 0.5) * w / g, top + sy * 0.5 - sink * 0.5, -d * 0.5 + (j + 0.5) * d / g)))


static func _dish(b: B, p: Dictionary) -> void:
	var r := _num(p, "r")
	var dep := _num(p, "depth")
	var t := minf(_num(p, "t"), r * 0.5)
	var rings := maxi(_int(p, "rings"), 2)
	var foot := _num(p, "foot")
	var prof := PackedVector2Array()
	# outside: from the axis at the bottom up the paraboloid to the rim; inside: back down
	var x0 := 0.0
	if foot > 0.0:
		prof.append(Vector2(0, -foot))
		prof.append(Vector2(r * 0.3, -foot))
		prof.append(Vector2(r * 0.22, 0.0))
		x0 = 0.24
	else:
		prof.append(Vector2(0, 0))
	for k in range(1, rings + 1):
		var x := float(k) / rings
		if x > x0:
			prof.append(Vector2(r * x, dep * x * x))
	prof.append(Vector2(r, dep + t))
	for k in range(rings, 0, -1):
		var x := float(k) / rings
		if r * x - t > 1e-4:
			prof.append(Vector2(r * x - t, t + dep * x * x))
	prof.append(Vector2(0, t))
	lathe(b, _dedupe(prof), maxi(_int(p, "segs"), 3))


static func _plane(b: B, p: Dictionary) -> void:
	var w := _num(p, "w")
	var d := _num(p, "d")
	var n := _int(p, "subdiv") + 1
	var P := []
	for i in n + 1:
		var col := PackedVector3Array()
		for j in n + 1:
			col.append(Vector3(-w * 0.5 + w * i / n, 0, d * 0.5 - d * j / n))
		P.append(col)
	b.sheet(P)


# --- checks ----------------------------------------------------------------------------

## How many edges of the mesh's triangles aren't shared with a face running the other
## way (0: closed - a solid's skin). Points closer than `weld` (relative to the mesh's
## size) count as one.
static func open_edges(mesh: Mesh, weld := 1e-5) -> int:
	if mesh == null:
		return -1
	var size := maxf(mesh.get_aabb().get_longest_axis_size(), 1e-6)
	var q := 1.0 / (size * weld)
	var ids := {}
	var edges := {}
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return -1
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		var wid := PackedInt32Array()
		wid.resize(v.size())
		for k in v.size():
			var key := Vector3i((v[k] * q).round())
			if not ids.has(key):
				ids[key] = ids.size()
			wid[k] = ids[key]
		for k in range(0, idx.size() - 2, 3):
			var t := [wid[idx[k]], wid[idx[k + 1]], wid[idx[k + 2]]]
			if t[0] == t[1] or t[1] == t[2] or t[0] == t[2]:
				continue
			for e in 3:
				var key := Vector2i(t[e], t[(e + 1) % 3])
				edges[key] = int(edges.get(key, 0)) + 1
	var open := 0
	for e: Vector2i in edges:
		if int(edges.get(Vector2i(e.y, e.x), 0)) != int(edges[e]):
			open += 1
	return open


## The volume a closed mesh holds (Godot's front faces clockwise: positive for an outward skin).
static func volume(mesh: Mesh) -> float:
	var vol := 0.0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		for k in range(0, idx.size() - 2, 3):
			vol += v[idx[k]].dot(v[idx[k + 2]].cross(v[idx[k + 1]])) / 6.0
	return vol
