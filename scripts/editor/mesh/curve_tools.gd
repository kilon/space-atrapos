extends Node
## The mesh editor's CURVE MODELING (its own tab on the right, and in the right-click menu): curves
## sketched on a construction plane, then made into solids - the quick way to model hard surfaces.
##
## - **Curves** (the model's, kept beside it: <model file>.curves.json): a line (a polyline, its
##   corners rounded by Fillet corners), a spline (a smooth curve through its points), a circle, a
##   three-point arc, a bezier (a bridge, its two handles), rectangles and polygons (closed lines).
##   Each is its control points `ctrl` in the model's own space, `closed`, the normal of its plane
##   `n`, a line's corner radii `radii`. sample(c) turns one into points along it.
## - **Sketching**: a tool (Line L, Spline P, Circle C, Arc Shift+C, Rectangle Shift+R, Polygon
##   Shift+P) clicks points onto the construction plane - Auto: the surface under the first click
##   (a face of a part: the curve drawn on it), else the ground; or Ground / Front / Side / View /
##   the selection's. Points snap to the plane's grid and to the curves' and parts' points (Ctrl: off).
##   Typed numbers give sizes: a length, a radius, "w h" (Enter takes them).
## - **Editing**: a click picks a curve (Shift: more); its points dragged (snapped), the curve dragged
##   by its line moves along its plane. Delete, duplicate, mirror, radial array, offset, fillet
##   corners, join, reverse, close / open, bridge two ends.
## - **Solids** (new parts, one undo step each): extrude (the mouse sets how far - or typed), revolve,
##   loft, sweep (a profile along a path), pipe, fill (a flat face). Closed outlines make closed
##   solids, so the booleans work on them.
## - **Procedural**: a solid keeps its recipe on its part (meta "curve_solid": {kind, ids - its curves'
##   ids, value - height / angle / radius, segs, axis - a revolve's axis curve}; saved in the glb's extras
##   as "atrapos_curves") and is made again from its curves whenever they change - a point dragged, a
##   corner filleted, an undo - or its settings do (the tab's SOLID box). Editing its mesh (edit mode) or
##   a boolean makes it a plain mesh. Closed curves inside a closed curve are holes (extrude, fill).
## Drawn over the view by a layer of its own (curves, handles, the plane's grid, the snap marker).

const Shapes := preload("res://scripts/editor/mesh/shapes.gd")
const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")

const KINDS := ["line", "spline", "circle", "arc", "bezier", "path"]
const TOOLS := {
	"line": ["Line", "m_cv_line", "L", "Click points on the plane: a polyline. Click its first point to close it; Enter, right-click\nor a double click ends it. Type a length + Enter for the next segment along the mouse's way."],
	"spline": ["Spline", "m_cv_spline", "P", "Click points: a smooth curve through them. Click the first point to close it; Enter or\nright-click ends it."],
	"circle": ["Circle", "m_cv_circle", "C", "Click the centre, then a point on the rim (or type the radius + Enter)."],
	"arc": ["Arc", "m_cv_arc", "Shift+C", "Three points: its start, its end, then one it passes through."],
	"rect": ["Rectangle", "m_cv_rect", "Shift+R", "Click a corner, then the opposite one (or type \"width height\" + Enter).\nAlt held: from the centre."],
	"polygon": ["Polygon", "m_cv_polygon", "Shift+P", "Click the centre, then a corner. The wheel or + / - sets how many sides (or type the radius + Enter)."],
}
const PICK_PX := 9.0
const HANDLE_PX := 10.0
const SNAP_PX := 12.0
const CURVE_COL := Color(0.45, 0.85, 1.0)
const SEL_COL := Color(1.0, 0.72, 0.38)

var ed: Control
var layer: Control                 # (draws over the view)
var curves: Array = []             # the model's curves (Dictionaries)
var sel: Array = []                # selected curve indices, in the order picked
var tool := ""                     # the sketching tool on ("" - none)
var placed := PackedVector3Array() # the tool's points so far (model space)
var cursor := Vector3.INF          # where the next point would go (snapped)
var snap_kind := ""                # "grid", "point", "end", "mid", "centre", "vertex", "" (free)
var typed := ""                    # numbers typed while sketching / in an operation
var sides := 6
## The construction plane: "auto", "ground", "front", "side", "view", "selection".
var plane_mode := "auto"
var plane := {}                    # {o, n, u, v} model space (the one in use)
var grid_step := 0.05
var snap_grid := true
var snap_points := true
var pipe_r := 0.05
var segs := 32                     # (revolve / round things: steps round)
var op := {}                       # an interactive operation (extrude / offset / fillet): its state
var _drag := {}                    # a handle or curve being dragged
var _cam_was := Transform3D()
var _vertex_cache := PackedVector3Array()
var _vertex_key := -1
var _preview: MeshInstance3D
var _panel_btns := {}
var _plane_btns := {}
var _info: Label
var _last_click := 0
# (The SOLID box's controls are kept in _panel_btns as "w_<name>", and the next curve id in a meta:
# no new member variables - so a change hot reloads into an editor that's open.)


## Each curve's placement in the model, by id: the part made from it (the first) carries it - move,
## turn or scale a solid and its curves go with it; a live boolean's B: A's place times B's place in A.
## Curves no solid uses aren't in it (they're where their points say).
func owner_xfs() -> Dictionary:
	var out := {}
	if ed == null or ed.model == null:
		return out
	var inv := _mx().affine_inverse()
	for p: MeshInstance3D in ed.parts():
		if p.has_meta("curve_solid"):
			_own(p.get_meta("curve_solid"), inv * p.global_transform, out)
	return out


static func _own(spec: Dictionary, xf: Transform3D, out: Dictionary) -> void:
	if str(spec.get("kind", "")) == "bool":
		_own(spec.get("a", {}), xf, out)
		_own(spec.get("b", {}), xf * xf_of(spec.get("b_xf", [])), out)
		return
	for id in spec.get("ids", []) + [spec.get("axis", -1)]:
		if int(id) >= 0 and not out.has(int(id)):
			out[int(id)] = xf


## Curve `c`'s placement (from owner_xfs()).
static func cx(c: Dictionary, own: Dictionary) -> Transform3D:
	return own.get(int(c.get("id", -1)), Transform3D())


## A copy of `c` with its placement put into its points (a copy made from a placed curve: where it shows).
static func baked(c: Dictionary, x: Transform3D) -> Dictionary:
	var o := c.duplicate(true)
	if x == Transform3D():
		return o
	var k: PackedVector3Array = (o["ctrl"] as PackedVector3Array).duplicate()
	for j in k.size():
		k[j] = x * k[j]
	o["ctrl"] = k
	o["n"] = (x.basis * (c.get("n", Vector3.UP) as Vector3)).normalized()
	return o


## A transform as 12 numbers (JSON, the glb's extras) and back.
static func xf_arr(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func xf_of(a: Variant) -> Transform3D:
	if not a is Array or (a as Array).size() < 12:
		return Transform3D()
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))


## The next id a curve gets (each curve's id: what a solid's recipe names it by).
func _nid() -> int:
	return int(get_meta("next_curve_id", 1))


func _set_nid(n: int) -> void:
	set_meta("next_curve_id", n)


## A control of the SOLID box (null: not built).
func _w(k: String) -> Variant:
	var c = _panel_btns.get("w_" + k)
	return c if c != null and is_instance_valid(c) else null


func setup(editor: Control) -> void:
	ed = editor
	name = "CurveTools"


## The overlay, once the view is made.
func attach(view: Control) -> void:
	layer = Control.new()
	layer.name = "CurveLayer"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(_draw_layer)
	view.add_child(layer)


func _process(_dt: float) -> void:
	if layer == null or ed.view == null or ed.view.cam == null:
		return
	if has_meta("solids_pending") and Time.get_ticks_msec() - int(get_meta("bool_at", 0)) >= 120:
		remove_meta("solids_pending")
		refresh_solids()
	var t: Transform3D = ed.view.cam.global_transform
	if t != _cam_was:
		_cam_was = t
		if not curves.is_empty() or tool != "":
			layer.queue_redraw()
	# (a solid carrying curves moved - G, the gizmo, a drag, typed numbers: its curves drawn with it at once)
	if not curves.is_empty() and ed.model:
		var sig := 0
		for p: MeshInstance3D in ed.parts():
			if p.has_meta("curve_solid"):
				sig = hash([sig, p.transform])
		if sig != int(get_meta("placed_sig", 0)):
			set_meta("placed_sig", sig)
			layer.queue_redraw()
	# (the ghosts of the solids inside recipes: made again when a recipe, a place or a part's showing changes)
	var gs := ghost_sig()
	if gs != int(get_meta("ghost_sig", 0)):
		set_meta("ghost_sig", gs)
		update_ghosts()


func _exit_tree() -> void:
	# (a baked solid's weights still being worked out on a worker: waited for - never left running)
	if has_meta("edge_bases"):
		for k in (get_meta("edge_bases") as Dictionary):
			var c = get_meta("edge_bases")[k]
			if c is Dictionary and (c as Dictionary).has("bw_job"):
				WorkerThreadPool.wait_for_task_completion(int(c["bw_job"][0]))
				(c as Dictionary).erase("bw_job")


func active() -> bool:
	return tool != "" or not op.is_empty() or not _drag.is_empty()


# --- the curves' shapes (static: tests call them) ---------------------------------------

## Points along curve `c` (model space): a line's corners (rounded by its radii), a spline through
## its points, a circle, an arc, a bezier.
static func sample(c: Dictionary, per := 12) -> PackedVector3Array:
	var k: PackedVector3Array = c["ctrl"]
	var closed: bool = c.get("closed", false)
	match str(c["kind"]):
		"line":
			return _rounded(k, c.get("radii", PackedFloat32Array()), closed, c.get("n", Vector3.UP))
		"spline":
			return catmull(k, closed, per)
		"path":
			return path_pts(k, c.get("sharp", PackedByteArray()), closed, per)
		"circle":
			if k.size() < 2:
				return k.duplicate()
			return circle_pts(k[0], k[0].distance_to(k[1]), c.get("n", Vector3.UP), k[1] - k[0], 64)
		"arc":
			return arc3(k[0], k[2], k[1], 48) if k.size() >= 3 else k.duplicate()
		"bezier":
			var out := PackedVector3Array()
			if k.size() < 4:
				return k.duplicate()
			for i in 33:
				var t := i / 32.0
				var u := 1.0 - t
				out.append(k[0] * (u * u * u) + k[1] * (3.0 * u * u * t) + k[2] * (3.0 * u * t * t) + k[3] * (t * t * t))
			return out
	return k.duplicate()


## A path: a curve through its points, smooth through most, broken at the `sharp` ones (corners):
## between two corners a smooth run (a spline through the points between) or, with none between, a
## straight side. (What a boolean of curves leaves: straight sides and arcs with few points.)
static func path_pts(k: PackedVector3Array, sharp: PackedByteArray, closed: bool, per := 12) -> PackedVector3Array:
	var n := k.size()
	var corners := PackedInt32Array()
	for i in n:
		if (i < sharp.size() and sharp[i] == 1) or (not closed and (i == 0 or i == n - 1)):
			corners.append(i)
	if corners.is_empty():
		return catmull(k, closed, per)
	var out := PackedVector3Array()
	var cn := corners.size()
	var runs := cn if closed else cn - 1
	for r in runs:
		var a := corners[r]
		var b := corners[(r + 1) % cn]
		var piece := PackedVector3Array()
		var j := a
		while true:
			piece.append(k[j])
			if j == b and piece.size() > 1:
				break
			j = (j + 1) % n
			if piece.size() > n + 1:
				break
		if piece.size() <= 2:
			out.append(piece[0])   # (a straight side: its corner)
		else:
			var arc := _arc_run(piece)   # (its points on one circle - a boolean's arc: drawn exactly)
			var sp := arc if not arc.is_empty() else catmull(piece, false, per)
			sp.remove_at(sp.size() - 1)
			out.append_array(sp)
	if not closed:
		out.append(k[n - 1])
	return out


## A centripetal Catmull-Rom spline through `k` (`per` points a span).
static func catmull(k: PackedVector3Array, closed: bool, per := 12) -> PackedVector3Array:
	var n := k.size()
	if n < 3:
		return k.duplicate()
	var out := PackedVector3Array()
	var spans := n if closed else n - 1
	for s in spans:
		var p1 := k[s]
		var p2 := k[(s + 1) % n]
		# (an open end: a point beyond it carrying on the bend of the last three - an arc stays round
		# to its end, not straightened)
		var p0 := k[(s - 1 + n) % n] if (closed or s > 0) else _beyond(k[0], k[1], k[2])
		var p3 := k[(s + 2) % n] if (closed or s + 2 < n) else _beyond(k[n - 1], k[n - 2], k[n - 3])
		var t0 := 0.0
		var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 1e-4)
		var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
		var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
		for i in per:
			var t := lerpf(t1, t2, float(i) / per)
			var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
			var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
			var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			out.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
	if not closed:
		out.append(k[n - 1])
	return out


## The run of points `piece` as an exact arc when they all lie on one circle (through its ends and
## middle point; [] - they don't: a spline then).
static func _arc_run(piece: PackedVector3Array) -> PackedVector3Array:
	var a := piece[0]
	var b := piece[piece.size() - 1]
	var mid := piece[piece.size() / 2]
	var ctr := circumcentre(a, mid, b)
	if ctr == Vector3.INF:
		return PackedVector3Array()
	var r := a.distance_to(ctr)
	var tol := maxf(r * 4e-3, 1e-5)   # (a boolean's corners lie on the outline's straight sides: up to ~0.12% of r inside the circle)
	var nn := (mid - a).cross(b - a)
	for q in piece:
		if absf(q.distance_to(ctr) - r) > tol or absf((q - a).dot(nn.normalized())) > tol:
			return PackedVector3Array()
	var ang := (a - ctr).angle_to(mid - ctr) + (mid - ctr).angle_to(b - ctr)
	return arc3(a, b, mid, maxi(4, int(ceil(rad_to_deg(ang) / 4.0))))


## A point beyond end `a` carrying on the bend of `a`, `b`, `c` (the circle through them, as far
## before `a` as `b` is after it; in a row: straight on).
static func _beyond(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ctr := circumcentre(a, b, c)
	var nn := (b - a).cross(c - a)
	if ctr == Vector3.INF or nn.length() < 1e-12:
		return a * 2.0 - b
	nn = nn.normalized()
	var ang := (a - ctr).signed_angle_to(b - ctr, nn)
	return ctr + (a - ctr).rotated(nn, -ang)


## A circle round `c` of radius `r` in the plane facing `n`, starting towards `start`.
static func circle_pts(c: Vector3, r: float, n: Vector3, start: Vector3, count := 64) -> PackedVector3Array:
	var nn := n.normalized()
	var u := (start - nn * start.dot(nn))
	u = u.normalized() if u.length() > 1e-6 else _any_perp(nn)
	var v := nn.cross(u)
	var out := PackedVector3Array()
	for i in count:
		var a := TAU * i / count
		out.append(c + (u * cos(a) + v * sin(a)) * r)
	return out


## The arc from `a` to `b` through `m` (a straight line if the three are in a row).
static func arc3(a: Vector3, b: Vector3, m: Vector3, count := 48) -> PackedVector3Array:
	var ctr := circumcentre(a, m, b)
	if ctr == Vector3.INF:
		return PackedVector3Array([a, b])
	var n := (m - a).cross(b - a).normalized()
	var u := (a - ctr).normalized()
	var v := n.cross(u)
	var r := a.distance_to(ctr)
	var ang_b := fposmod(atan2((b - ctr).dot(v), (b - ctr).dot(u)), TAU)
	var out := PackedVector3Array()
	for i in count + 1:
		var t := ang_b * i / count
		out.append(ctr + (u * cos(t) + v * sin(t)) * r)
	return out


## The centre of the circle through three points (INF: they're in a row).
static func circumcentre(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var n := ab.cross(ac)
	var d := 2.0 * n.length_squared()
	if d < 1e-12:
		return Vector3.INF
	return a + (n.cross(ab) * ac.length_squared() + ac.cross(n) * ab.length_squared()) / d


static func _any_perp(n: Vector3) -> Vector3:
	var a := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	return n.cross(a).normalized()


## A polyline with its corners rounded: corner i by radii[i] (an arc tangent to both sides).
static func _rounded(k: PackedVector3Array, radii: PackedFloat32Array, closed: bool, n: Vector3) -> PackedVector3Array:
	var m := k.size()
	if radii.is_empty() or m < 3:
		return k.duplicate()   # (a copy: callers turn it round - never the curve's own points)
	var out := PackedVector3Array()
	for i in m:
		var r := radii[i] if i < radii.size() else 0.0
		var ends := (i == 0 or i == m - 1) and not closed
		if r <= 1e-6 or ends:
			out.append(k[i])
			continue
		var p := k[i]
		var a := k[(i - 1 + m) % m]
		var b := k[(i + 1) % m]
		var da := (a - p).normalized()
		var db := (b - p).normalized()
		var cosang := clampf(da.dot(db), -1.0, 1.0)
		var half := acos(cosang) * 0.5
		if half < 1e-3 or half > PI * 0.5 - 1e-3:
			out.append(p)
			continue
		# (the tangent points: as far back as the radius needs, no further than half a side)
		var back := r / tan(half)
		var lim := minf(p.distance_to(a), p.distance_to(b)) * 0.5
		if back > lim:
			back = lim
			r = back * tan(half)
		if r < 1e-6 or (da + db).length() < 1e-6:
			out.append(p)   # (a point on top of its neighbour, or no room: left sharp)
			continue
		var t0 := p + da * back
		var t1 := p + db * back
		var ctr := p + (da + db).normalized() * (r / sin(half))
		var steps := maxi(3, int(ceil((PI - 2.0 * half) / deg_to_rad(10.0))))
		var u := (t0 - ctr).normalized()
		var ax := (t0 - ctr).cross(t1 - ctr).normalized()
		var sweep := (PI - 2.0 * half)
		for s in steps + 1:
			out.append(ctr + u.rotated(ax, sweep * s / steps) * r)
	return out


# --- the construction plane ----------------------------------------------------------------

static func plane_of(mode: String, cam_basis := Basis()) -> Dictionary:
	match mode:
		"front": return _plane(Vector3.ZERO, Vector3.BACK, Vector3.RIGHT)
		"side": return _plane(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK * -1.0)
		"view": return _plane(Vector3.ZERO, cam_basis.z, cam_basis.x)
	return _plane(Vector3.ZERO, Vector3.UP, Vector3.RIGHT)


static func _plane(o: Vector3, n: Vector3, u: Vector3) -> Dictionary:
	n = n.normalized()
	u = (u - n * u.dot(n))
	u = u.normalized() if u.length() > 1e-6 else _any_perp(n)
	return {"o": o, "n": n, "u": u, "v": n.cross(u)}


## The model's transform (model space <-> the view's world).
func _mx() -> Transform3D:
	return ed.model.global_transform if ed.model else Transform3D()


## The plane for a new sketch from the mouse at `at`: Auto - the part's surface under it.
func _plane_for(at: Vector2) -> Dictionary:
	if plane_mode == "auto":
		var hit := _surface_hit(at)
		if not hit.is_empty():
			return _plane(hit["p"], hit["n"], Vector3.RIGHT if absf(hit["n"].x) < 0.9 else Vector3.BACK)
		return plane_of("ground")
	if plane_mode == "view":
		return plane_of("view", _mx().basis.inverse() * ed.view.cam.global_basis)
	if plane_mode == "selection":
		var p := selection_plane()
		return p if not p.is_empty() else plane_of("ground")
	return plane_of(plane_mode)


## The selection's plane: the selected faces' (edit mode), else the first selected curve's.
func selection_plane() -> Dictionary:
	if ed.mode == "edit" and ed.em != null and ed.part != null:
		var ids: PackedInt32Array = ed.selected_points()
		if ids.size() >= 3:
			var DT: GDScript = load("res://scripts/editor/mesh/deform_tools.gd")
			var n: Vector3 = DT.faces_normal(ed.em, ed.sel_t) if ed.sel_kind != 0 else Vector3.ZERO
			if n == Vector3.ZERO:
				n = DT.fit_normal(ed.em.points, ids)
			var pxf: Transform3D = _mx().affine_inverse() * ed.part.global_transform
			var c: Vector3 = pxf * ed.em.centroid(ids)
			return _plane(c, (pxf.basis * n).normalized(), Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.BACK)
	if not sel.is_empty():
		var c := baked(curves[sel[0]], cx(curves[sel[0]], owner_xfs()))
		var k: PackedVector3Array = c["ctrl"]
		return _plane(k[0], c.get("n", Vector3.UP), (k[1] - k[0]) if k.size() > 1 else Vector3.RIGHT)
	return {}


## A part's surface under the mouse: {p, n} in model space ({} - none).
func _surface_hit(at: Vector2) -> Dictionary:
	var r: Array = ed.view.ray(at)
	var best := INF
	var out := {}
	for p: MeshInstance3D in ed.parts():
		if not p.visible or p.mesh == null:
			continue
		var tm := p.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var inv := p.global_transform.affine_inverse()
		var o: Vector3 = inv * (r[0] as Vector3)
		var d: Vector3 = (inv.basis * (r[1] as Vector3)).normalized()
		var hit := tm.intersect_ray(o, d)
		if hit.is_empty():
			continue
		var wp: Vector3 = p.global_transform * (hit["position"] as Vector3)
		var dist := wp.distance_to(r[0])
		if dist < best:
			best = dist
			var mi := _mx().affine_inverse()
			var wn: Vector3 = (p.global_transform.basis.inverse().transposed() * (hit["normal"] as Vector3)).normalized()
			out = {"p": mi * wp, "n": (mi.basis * wn).normalized()}
	return out


## The mouse on plane `pl` (model space), INF if the plane's edge-on.
func _on_plane(at: Vector2, pl: Dictionary) -> Vector3:
	var mx := _mx()
	var hit = ed.view.on_plane(at, mx * (pl["o"] as Vector3), (mx.basis * (pl["n"] as Vector3)).normalized())
	return mx.affine_inverse() * (hit as Vector3) if hit != null else Vector3.INF


func _screen(p: Vector3) -> Vector2:
	var w := _mx() * p
	return Vector2(-1e6, -1e6) if ed.view.behind(w) else ed.view.project(w)


## Where a point goes for the mouse at `at` on plane `pl`: a curve's or part's point near it, else
## the grid (Ctrl: free). Sets snap_kind.
func snap(at: Vector2, pl: Dictionary, free := false) -> Vector3:
	var p := _on_plane(at, pl)
	snap_kind = ""
	if p == Vector3.INF or free:
		return p
	if snap_points:
		var best := SNAP_PX
		var got := Vector3.INF
		for cand in _snap_candidates():
			var d := _screen(cand[0]).distance_to(at)
			if d < best:
				best = d
				got = cand[0]
				snap_kind = cand[1]
		if got != Vector3.INF:
			return got
	if snap_grid and grid_step > 0.0:
		var o: Vector3 = pl["o"]
		var u: Vector3 = pl["u"]
		var v: Vector3 = pl["v"]
		var a := snappedf((p - o).dot(u), grid_step)
		var b := snappedf((p - o).dot(v), grid_step)
		snap_kind = "grid"
		return o + u * a + v * b
	return p


## Points to snap to: [model-space point, kind].
func _snap_candidates() -> Array:
	var out := []
	var own := owner_xfs()
	for c0 in curves:
		if c0.get("hidden", false):
			continue
		var c := baked(c0, cx(c0, own))
		var k: PackedVector3Array = c["ctrl"]
		match str(c["kind"]):
			"circle":
				out.append([k[0], "centre"])
				for q in circle_pts(k[0], k[0].distance_to(k[1]), c["n"], k[1] - k[0], 4):
					out.append([q, "point"])
			_:
				var s := sample(c)
				if not s.is_empty() and not c.get("closed", false):
					out.append([s[0], "end"])
					out.append([s[s.size() - 1], "end"])
				for i in k.size():
					out.append([k[i], "point"])
					if str(c["kind"]) == "line" and (i + 1 < k.size() or c.get("closed", false)):
						out.append([(k[i] + k[(i + 1) % k.size()]) * 0.5, "mid"])
	for q in placed:
		out.append([q, "point"])
	for q in _part_vertices():
		out.append([q, "vertex"])
	return out


## The visible parts' corner points (model space; kept till the model changes) - at most a few thousand.
func _part_vertices() -> PackedVector3Array:
	var key: int = ed._edit_count * 7919 + ed.parts().size() * 31 + (ed._undo.size() as int)
	if key == _vertex_key:
		return _vertex_cache
	_vertex_key = key
	var out := PackedVector3Array()
	var seen := {}
	var mi := _mx().affine_inverse()
	for p: MeshInstance3D in ed.parts():
		if not p.visible or p.mesh == null:
			continue
		var xf := mi * p.global_transform
		var fs := p.mesh.get_faces()
		if fs.size() > 12000:
			continue
		for q in fs:
			var w := xf * q
			var kk := Vector3i((w * 1000.0).round())
			if not seen.has(kk):
				seen[kk] = true
				out.append(w)
	_vertex_cache = out
	return out


# --- sketching ----------------------------------------------------------------------------

func begin(t: String) -> void:
	if not TOOLS.has(t):
		return
	cancel_op()
	if ed.model == null:
		ed.new_model(true)
	tool = t
	placed = PackedVector3Array()
	typed = ""
	plane = {}
	cursor = Vector3.INF
	ed.show_right_tab(1)
	_hint()
	_refresh_panel()
	layer.queue_redraw()


func stop() -> void:
	tool = ""
	placed = PackedVector3Array()
	typed = ""
	plane = {}
	ed.view.hint = ""
	ed.view.queue_redraw()
	_refresh_panel()
	layer.queue_redraw()


func _hint() -> void:
	if tool == "":
		return
	var t: Array = TOOLS[tool]
	var what := ""
	match tool:
		"line", "spline": what = "click points · Enter / right-click: done · click the first: closed · Backspace: back"
		"circle": what = "centre, then the rim" if placed.is_empty() else "the rim (or type the radius)"
		"arc": what = ["its start", "its end", "a point it passes through"][mini(placed.size(), 2)]
		"rect": what = "a corner" if placed.is_empty() else "the opposite corner (or type \"w h\")"
		"polygon": what = ("the centre" if placed.is_empty() else "a corner (or type the radius)") + " · %d sides (wheel / + -)" % sides
	var pl: String = ["Auto", "Ground", "Front", "Side", "View", "Selection"][["auto", "ground", "front", "side", "view", "selection"].find(plane_mode)]
	ed.view.hint = "%s:  %s   [%s plane%s]%s" % [t[0], what, pl, "" if snap_kind == "" else " · snap: " + snap_kind, ("   typed: " + typed) if typed != "" else ""]
	ed.view.queue_redraw()


## A sketch click at `at` (`free`: no snapping). True - taken.
func click(at: Vector2, free := false) -> bool:
	if tool == "":
		return false
	if plane.is_empty():
		plane = _plane_for(at)
	var p := snap(at, plane, free)
	if p == Vector3.INF:
		ed._say("The construction plane is edge-on: turn the view a little.")
		return true
	var now := Time.get_ticks_msec()
	# (a double click: quick, and on the point just placed)
	var dbl := now - _last_click < 300 and not placed.is_empty() and _screen(placed[placed.size() - 1]).distance_to(at) < SNAP_PX
	_last_click = now
	match tool:
		"line", "spline":
			if placed.size() >= 3 and _screen(placed[0]).distance_to(at) < SNAP_PX:
				_finish(true)
				return true
			if dbl and placed.size() >= 2:
				_finish(false)
				return true
			if placed.is_empty() or placed[placed.size() - 1].distance_to(p) > 1e-6:
				placed.append(p)
		"circle":
			placed.append(p)
			if placed.size() == 2:
				_finish(true)
		"arc":
			placed.append(p)
			if placed.size() == 3:
				_finish(false)
		"rect":
			placed.append(p)
			if placed.size() == 2:
				_finish(true)
		"polygon":
			placed.append(p)
			if placed.size() == 2:
				_finish(true)
	_hint()
	layer.queue_redraw()
	return true


## The curve sketched so far for the tool (with the cursor as its next point).
func _draft() -> Dictionary:
	var pts := placed.duplicate()
	if cursor != Vector3.INF:
		pts.append(cursor)
	var n: Vector3 = plane.get("n", Vector3.UP)
	match tool:
		"line": return {"kind": "line", "ctrl": pts, "closed": false, "n": n}
		"spline": return {"kind": "spline", "ctrl": pts, "closed": false, "n": n}
		"circle":
			return {"kind": "circle", "ctrl": pts, "closed": true, "n": n} if pts.size() >= 2 else {}
		"arc":
			if pts.size() == 2:
				return {"kind": "line", "ctrl": pts, "closed": false, "n": n}
			if pts.size() >= 3:
				return {"kind": "arc", "ctrl": PackedVector3Array([pts[0], pts[2], pts[1]]), "closed": false, "n": n}
			return {}
		"rect":
			if pts.size() < 2:
				return {}
			return {"kind": "line", "ctrl": rect_pts(pts[0], pts[1], plane, Input.is_key_pressed(KEY_ALT)), "closed": true, "n": n}
		"polygon":
			if pts.size() < 2:
				return {}
			return {"kind": "line", "ctrl": polygon_pts(pts[0], pts[1], n, sides), "closed": true, "n": n}
	return {}


## A rectangle's corners from `a` to `b` on plane `pl` (`centred`: `a` is its middle).
static func rect_pts(a: Vector3, b: Vector3, pl: Dictionary, centred := false) -> PackedVector3Array:
	var u: Vector3 = pl.get("u", Vector3.RIGHT)
	var v: Vector3 = pl.get("v", Vector3.BACK)
	var d := b - a
	var du := u * d.dot(u)
	var dv := v * d.dot(v)
	if centred:
		return PackedVector3Array([a - du - dv, a + du - dv, a + du + dv, a - du + dv])
	return PackedVector3Array([a, a + du, a + du + dv, a + dv])


## A regular polygon's corners round `c`, one of them at `corner`.
static func polygon_pts(c: Vector3, corner: Vector3, n: Vector3, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var r := corner - c
	for i in count:
		out.append(c + r.rotated(n.normalized(), TAU * i / count))
	return out


func _finish(closed: bool) -> void:
	var save_cursor := cursor
	cursor = Vector3.INF
	var c := _draft()
	cursor = save_cursor
	if tool in ["line", "spline"]:
		if placed.size() < 2:
			stop()
			return
		c["closed"] = closed and placed.size() >= 3
	if c.is_empty():
		stop()
		return
	var kept_tool := tool
	add_curve(c)
	placed = PackedVector3Array()
	plane = {} if plane_mode in ["auto", "view"] else plane
	typed = ""
	tool = kept_tool   # (the tool stays on: another one, at once - Esc stops it)
	_hint()


## Adds curve `c` (one undo step); its index.
func add_curve(c: Dictionary) -> int:
	c = c.duplicate(true)
	_fresh(c)
	if not c.has("name"):
		c["name"] = "%s %d" % [str(c["kind"]).capitalize(), curves.size() + 1]
	var before := _state()
	curves.append(c)
	sel = [curves.size() - 1]
	_changed("Add " + str(c["kind"]), before)
	return curves.size() - 1


## `c` given an id of its own (a new curve, or a copy).
func _fresh(c: Dictionary) -> Dictionary:
	c["id"] = _nid()
	_set_nid(_nid() + 1)
	return c


## The curve with id `id` ({} - none).
func curve_by_id(id: int) -> Dictionary:
	for c in curves:
		if int(c.get("id", -1)) == id:
			return c
	return {}


## The curves with these ids, in order ([] if one of them is gone).
func curves_of(ids: Array) -> Array:
	var out := []
	for id in ids:
		var c := curve_by_id(int(id))
		if c.is_empty():
			return []
		out.append(c)
	return out


## Typed numbers while sketching: a length / radius / "w h".
func apply_typed() -> bool:
	var nums := []
	for s in typed.replace(",", " ").split(" ", false):
		if s.is_valid_float():
			nums.append(float(s))
	typed = ""
	if nums.is_empty() or placed.is_empty():
		return false
	var a := placed[placed.size() - 1]
	var dir: Vector3 = (cursor - a) if cursor != Vector3.INF else plane.get("u", Vector3.RIGHT)
	if dir.length() < 1e-6:
		dir = plane.get("u", Vector3.RIGHT)
	dir = dir.normalized()
	match tool:
		"line", "spline":
			placed.append(a + dir * nums[0])
		"circle", "polygon":
			cursor = Vector3.INF
			placed.append(a + dir * nums[0])
			_finish(true)
		"rect":
			var u: Vector3 = plane["u"]
			var v: Vector3 = plane["v"]
			var sx := signf((cursor - a).dot(u)) if cursor != Vector3.INF and absf((cursor - a).dot(u)) > 1e-6 else 1.0
			var sy := signf((cursor - a).dot(v)) if cursor != Vector3.INF and absf((cursor - a).dot(v)) > 1e-6 else 1.0
			cursor = Vector3.INF
			placed.append(a + u * nums[0] * sx + v * (nums[1] if nums.size() > 1 else nums[0]) * sy)
			_finish(true)
	_hint()
	layer.queue_redraw()
	return true


# --- undo -----------------------------------------------------------------------------------

func _state() -> Array:
	# (baked solids' recipes too: an edit settles their meshes - undo puts each back as it was)
	var specs := {}
	if ed and ed.model:
		for p: MeshInstance3D in ed.parts():
			var sp: Dictionary = p.get_meta("curve_solid", {})
			if str(sp.get("kind", "")) == "edges" and sp.has("mesh"):
				specs[p.get_instance_id()] = sp.duplicate(true)
	return [curves.duplicate(true), sel.duplicate(), specs]


func _set_state(st: Array) -> void:
	curves = st[0].duplicate(true)
	sel = st[1].duplicate()
	if st.size() > 2:
		for pid in st[2]:
			var p = instance_from_id(int(pid))
			if p is MeshInstance3D and is_instance_valid(p):
				var sp: Dictionary = (st[2][pid] as Dictionary).duplicate(true)
				(p as MeshInstance3D).set_meta("curve_solid", sp)
				(p as MeshInstance3D).remove_meta("curve_solid_key")
				_edge_bases().erase(int(sp.get("net", 0)))
	refresh_solids()
	_refresh_panel()
	layer.queue_redraw()


## One undo step from `before` to now (a baked solid an edit reshaped: settled first - in the step).
func _changed(name: String, before: Array) -> void:
	refresh_solids()
	settle_edges()
	var after := _state()
	var e := {"name": name, "undo": _set_state.bind(before), "redo": _set_state.bind(after)}
	if ed.mode == "edit":
		ed._eundo.append(e)
		ed._eredo.clear()
		ed.dirty = true
		ed._update_ui()
	else:
		ed._push(name, _set_state.bind(before), _set_state.bind(after))
	refresh_solids()
	_refresh_panel()
	layer.queue_redraw()


# --- picking and dragging ----------------------------------------------------------------------

## The curve whose line passes nearest `at` (-1: none within PICK_PX; a run behind the solid isn't picked).
func pick(at: Vector2) -> int:
	return int(pick_at(at).get("i", -1))


## pick()'s curve and where on it: {i, p - the point (the curve's own space)} ({}: none).
func pick_at(at: Vector2) -> Dictionary:
	var best := PICK_PX
	var got := {}
	var own := owner_xfs()
	var mx := _mx()
	_begin_occ(false)
	for i in curves.size():
		if curves[i].get("hidden", false):
			continue
		var s := sample(curves[i])
		var x := cx(curves[i], own)
		if curves[i].get("closed", false) and s.size() > 1:
			s.append(s[0])
		for k in s.size() - 1:
			var a := _screen(x * s[k])
			var b := _screen(x * s[k + 1])
			var q := Geometry2D.get_closest_point_to_segment(at, a, b)
			var d := q.distance_to(at)
			if d < best:
				var ab := b - a
				var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab.length_squared() > 1e-9 else 0.0
				var p := s[k].lerp(s[k + 1], t)
				if _hidden(mx * (x * p)):
					continue
				best = d
				got = {"i": i, "p": p}
	_end_occ()
	return got


## Double-click on a curve: a point put into it there (a circle, an arc or a bezier becomes a path of
## points first - the same shape). False: not one to add to.
func insert_point(at: Vector2) -> bool:
	var hit := pick_at(at)
	if hit.is_empty():
		return false
	var i := int(hit["i"])
	var c: Dictionary = curves[i]
	var p: Vector3 = hit["p"]
	var before := _state()
	var e := as_points(c)
	if e.is_empty():
		return false
	if str(c["kind"]) in ["circle"]:
		var k0: PackedVector3Array = c["ctrl"]
		var n := (c.get("n", Vector3.UP) as Vector3).normalized()
		var off := p - k0[0]
		off -= n * off.dot(n)
		if off.length() > 1e-9:
			p = k0[0] + off.normalized() * k0[0].distance_to(k0[1])   # (exactly on the circle)
	var k: PackedVector3Array = e["ctrl"]
	var closed: bool = e.get("closed", false)
	var spans := k.size() if closed else k.size() - 1
	var at_j := -1
	var cost := INF
	for j in spans:
		var a := k[j]
		var b := k[(j + 1) % k.size()]
		var dc := a.distance_to(p) + p.distance_to(b) - a.distance_to(b)   # (the detour: least where it lies between them)
		if dc < cost:
			cost = dc
			at_j = j
	if at_j < 0:
		return false
	for q in k:
		if q.distance_to(p) < 1e-4:
			return false   # (a point's already there)
	k.insert(at_j + 1, p)
	e["ctrl"] = k
	if e.has("radii"):
		var r: PackedFloat32Array = e["radii"]
		if r.size() >= at_j + 1:
			r.insert(at_j + 1, 0.0)
		e["radii"] = r
	if str(e["kind"]) == "path":
		var sh: PackedByteArray = e.get("sharp", PackedByteArray())
		sh.resize(k.size() - 1)
		sh.insert(at_j + 1, 0)
		e["sharp"] = sh
	curves[i] = e
	if not i in sel:
		sel = [i]
	_changed("Insert curve point", before)
	return true


## Double-click on a point: it's taken out - the curve runs on between its neighbours (an arc's middle
## point: a straight line between its ends). Not when that leaves too few (2 for an open curve, 3 for a
## closed one), nor a baked solid's edge end (a corner other edges share). One undo step.
func dissolve_point(ci: int, j: int) -> bool:
	if ci < 0 or ci >= curves.size():
		return false
	var c: Dictionary = curves[ci]
	var k: PackedVector3Array = c["ctrl"]
	var closed := bool(c.get("closed", false))
	var kind := str(c["kind"])
	var e := c.duplicate(true)
	if kind == "arc":
		if j != 1 or k.size() < 3:
			return false
		e["kind"] = "line"
		e["ctrl"] = PackedVector3Array([k[0], k[2]])
	elif kind in ["line", "spline", "path"]:
		if k.size() <= (3 if closed else 2) or j < 0 or j >= k.size():
			return false
		if not closed and (j == 0 or j == k.size() - 1) and _any_baked([ci]):
			return false
		var nk := k.duplicate()
		nk.remove_at(j)
		e["ctrl"] = nk
		for key_ in ["sharp", "radii"]:
			if e.has(key_):
				var a = e[key_]
				if j < a.size():
					a.remove_at(j)
				e[key_] = a
	else:
		return false
	var before := _state()
	curves[ci] = e
	_changed("Dissolve curve point", before)
	return true


## The menu's items for a picked curve's point under `at` - Smooth point / Sharp point ([]: none there).
func point_items(at: Vector2) -> Array:
	var h := pick_handle(at) if at.x > -1e5 else []
	if h.is_empty():
		return []
	var c: Dictionary = curves[int(h[0])]
	var j := int(h[1])
	var n := (c["ctrl"] as PackedVector3Array).size()
	var can := str(c["kind"]) in ["line", "spline", "path", "arc"] and (bool(c.get("closed", false)) or (j > 0 and j < n - 1))
	var sharp := point_sharp(c, j)
	return [
		["m_cv_pt_smooth", "Smooth point", "", "The curve runs through this point in a smooth bend (curved either side of it).", set_point_sharp.bind(int(h[0]), j, false), can and sharp],
		["m_cv_pt_sharp", "Sharp point", "", "A corner at this point: the curve runs straight to it and straight on from it.", set_point_sharp.bind(int(h[0]), j, true), can and not sharp],
	]


## Point `j` of curve `c` a corner (a line's every point; a spline's none; a path's as marked).
static func point_sharp(c: Dictionary, j: int) -> bool:
	match str(c["kind"]):
		"line", "rect", "polygon":
			return true
		"path":
			var sh: PackedByteArray = c.get("sharp", PackedByteArray())
			return j < sh.size() and sh[j] == 1
	return false


## Curve `ci`'s point `j` made a corner (`sharp`) or a smooth bend: the curve becomes a path of points -
## sharp ones joined by straight sides, smooth ones bent through. One undo step.
func set_point_sharp(ci: int, j: int, sharp: bool) -> void:
	if ci < 0 or ci >= curves.size():
		return
	var c: Dictionary = curves[ci]
	var before := _state()
	var e: Dictionary
	match str(c["kind"]):
		"line", "spline":
			e = c.duplicate(true)
			var sh := PackedByteArray()
			sh.resize((c["ctrl"] as PackedVector3Array).size())
			sh.fill(1 if str(c["kind"]) == "line" else 0)
			e["kind"] = "path"
			e["sharp"] = sh
			e.erase("radii")
		_:
			e = as_points(c)
	if e.is_empty() or j >= (e["ctrl"] as PackedVector3Array).size():
		return
	var sh: PackedByteArray = e.get("sharp", PackedByteArray())
	sh.resize((e["ctrl"] as PackedVector3Array).size())
	sh[j] = 1 if sharp else 0
	e["sharp"] = sh
	curves[ci] = e
	_changed("Sharp point" if sharp else "Smooth point", before)


## Curve `c` as points (line, spline, path as they are; a circle or an arc as a path through points on it
## - drawn as the same exact arcs; a bezier as a path through points along it).
static func as_points(c: Dictionary) -> Dictionary:
	var e := c.duplicate(true)
	var k: PackedVector3Array = c["ctrl"]
	match str(c["kind"]):
		"line", "spline", "path":
			return e
		"circle":
			if k.size() < 2:
				return {}
			var n := (c.get("n", Vector3.UP) as Vector3).normalized()
			var r0 := k[1] - k[0]
			var s := sample(c)
			var turn := 1.0   # (the way it's drawn round)
			if s.size() > 2 and s[1].distance_to(k[0] + r0.rotated(n, TAU / 64.0)) > s[1].distance_to(k[0] + r0.rotated(n, -TAU / 64.0)):
				turn = -1.0
			var pts := PackedVector3Array()
			for j in 8:
				pts.append(k[0] + r0.rotated(n, turn * TAU * j / 8.0))   # (from its start round, as it's drawn)
			e["kind"] = "path"
			e["ctrl"] = pts
			e["closed"] = true
			e["sharp"] = PackedByteArray([1, 0, 0, 0, 1, 0, 0, 0])   # (two halves, each one exact arc)
		"arc":
			if k.size() < 3:
				return {}
			e["kind"] = "path"
			e["ctrl"] = PackedVector3Array([k[0], k[1], k[2]])   # (start, a point on it, end - in order)
			e["closed"] = false
			e["sharp"] = PackedByteArray([0, 0, 0])
		"bezier":
			var s := sample(c)
			var pts := PackedVector3Array()
			for j in 9:
				pts.append(s[int(round(j * (s.size() - 1) / 8.0))])
			e["kind"] = "path"
			e["ctrl"] = pts
			e["closed"] = false
			e["sharp"] = PackedByteArray()
			e["sharp"].resize(pts.size())
		_:
			return {}
	e.erase("radii")
	return e


## A selected curve's control point under `at`: [curve, point] ([] - none).
func pick_handle(at: Vector2) -> Array:
	var own := owner_xfs()
	for i in sel:
		var k: PackedVector3Array = curves[i]["ctrl"]
		var x := cx(curves[i], own)
		for j in k.size():
			if _screen(x * k[j]).distance_to(at) < HANDLE_PX:
				return [i, j]
	return []


func select(i: int, add := false) -> void:
	if not add:
		sel = []
	if i >= 0:
		if i in sel:
			if add:
				sel.erase(i)
		else:
			sel.append(i)
	_refresh_panel()
	layer.queue_redraw()


# --- the view's input (the editor asks first) ---------------------------------------------------

## True - the event was the curve tools'.
func view_input(e: InputEvent) -> bool:
	if layer == null or ed.model == null and tool == "":
		return false
	var mm := e as InputEventMouseMotion
	if mm:
		if not op.is_empty():
			_op_motion(mm.position)
			return true
		if not _drag.is_empty():
			_drag_to(mm.position, mm.ctrl_pressed)
			return true
		if tool != "":
			if plane.is_empty():
				var pl := _plane_for(mm.position)
				cursor = snap(mm.position, pl, mm.ctrl_pressed)
				_hover_plane = pl
			else:
				cursor = snap(mm.position, plane, mm.ctrl_pressed)
			_hint()
			layer.queue_redraw()
		return false   # (the view still turns with the middle button / Alt)
	var mb := e as InputEventMouseButton
	if mb == null:
		return false
	if not op.is_empty():
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			confirm_op()
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel_op()
			return true
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and op.get("kind", "") == "revolve":
			return false
		return false
	if tool != "":
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and tool == "polygon" and mb.pressed and not placed.is_empty():
			sides = clampi(sides + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 3, 64)
			_hint()
			layer.queue_redraw()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed:
			click(mb.position, mb.ctrl_pressed)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			return not mb.alt_pressed
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if tool in ["line", "spline"] and placed.size() >= 2:
				_finish(false)
			elif not placed.is_empty():
				placed = PackedVector3Array()
				plane = {}
				_hint()
				layer.queue_redraw()
			else:
				stop()
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			return true
		return false
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.alt_pressed:
		return false
	if mb.pressed:
		if not ed.xf.is_empty():
			return false
		if mb.double_click:
			var hd := pick_handle(mb.position)
			if (dissolve_point(int(hd[0]), int(hd[1])) if not hd.is_empty() else insert_point(mb.position)):
				_drag = {}
				return true
		var h := pick_handle(mb.position)
		var own := owner_xfs()
		if not h.is_empty():
			# (dragged on its plane as it's placed - the part it belongs to moved or turned too)
			var hx := cx(curves[h[0]], own)
			_drag = {"handle": h, "before": _state(), "x": hx, "own": own, "press": mb.position,
				"start": hx * (curves[h[0]]["ctrl"][h[1]] as Vector3), "moved": false}
			return true
		var i := pick(mb.position)
		if i >= 0:
			if not mb.shift_pressed and not i in sel:
				select(i)
			elif mb.shift_pressed:
				select(i, true)
				return true
			if _any_baked([i]):
				return true   # (picked; a baked solid's curve isn't dragged off it - only its points)
			var hit := pick_at(mb.position)
			var at3: Vector3 = cx(curves[i], own) * (hit["p"] as Vector3) if not hit.is_empty() else cx(curves[i], own) * (curves[i]["ctrl"][0] as Vector3)
			_drag = {"curve": i, "before": _state(), "press": mb.position, "start": at3, "orig": curves.duplicate(true), "moved": false, "own": own}
			return true
		if not sel.is_empty() and not mb.shift_pressed:
			select(-1)
		return false
	if not _drag.is_empty():
		var d := _drag
		_drag = {}
		ed.view.hint = ""
		if d.get("moved", false):
			_changed("Move curve point" if d.has("handle") else "Move curve", d["before"])
		return true
	return false


var _hover_plane := {}


## The curve ids baked solids are made of (their curves are part of them: reshaped by their points, not
## moved off them).
func baked_ids() -> Dictionary:
	var out := {}
	if ed == null or ed.model == null:
		return out
	for p: MeshInstance3D in ed.parts():
		if p.has_meta("curve_solid"):
			_baked_walk(p.get_meta("curve_solid"), out)
	return out


static func _baked_walk(spec: Dictionary, out: Dictionary) -> void:
	if str(spec.get("kind", "")) == "bool":
		_baked_walk(spec.get("a", {}), out)
		_baked_walk(spec.get("b", {}), out)
	elif str(spec.get("kind", "")) in ["baked", "edges"]:
		for id in spec.get("ids", []):
			out[int(id)] = true


## One of curves `idx` (indices) is a baked solid's.
func _any_baked(idx: Array) -> bool:
	var b := baked_ids()
	for i in idx:
		if int(i) < curves.size() and b.has(int(curves[int(i)].get("id", -1))):
			return true
	return false


## A baked solid's edge point moved from `was` to `to`: the same corner on its other edges moves too (the
## edges stay joined).
func _move_corner(ci: int, was: Vector3, to: Vector3) -> void:
	var id := int(curves[ci].get("id", -1))
	var net_ids := []
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if str(spec.get("kind", "")) == "edges" and id in (spec.get("ids", []) as Array).map(func(x): return int(x)):
			net_ids = (spec["ids"] as Array).map(func(x): return int(x))
	if net_ids.is_empty():
		return
	for j in curves.size():
		if j == ci or not int(curves[j].get("id", -1)) in net_ids:
			continue
		var k: PackedVector3Array = curves[j]["ctrl"]
		var hit := false
		for m in k.size():
			if k[m].distance_to(was) < 1e-4:
				k[m] = to
				hit = true
		if hit:
			curves[j]["ctrl"] = k


## Dragging points and curves in 3D, measured from where the press was (nothing jumps): still for the
## first few pixels, then - Smart axis move (the editor's move mode) - along the model's X, Y or Z,
## whichever runs closest to the drag on screen (drawn through it, in its colour); X / Y / Z while
## dragging pick one (again: free); Shift, or Perspective move: free over the axis plane facing the view
## most squarely. Smooth - no snapping (Ctrl held: whole grid steps).
const DRAG_DEAD_PX := 6.0
const AXIS_COLS := [Color(1.0, 0.36, 0.33), Color(0.45, 0.95, 0.4), Color(0.4, 0.62, 1.0)]


## The model's axis `k` as the screen shows it at model point `o` (ZERO: pointing at the camera).
func _axis_on_screen(o: Vector3, k: int) -> Vector2:
	var mx := _mx()
	var a: Vector2 = ed.view.project(mx * o)
	var b: Vector2 = ed.view.project(mx * (o + ([Vector3.RIGHT, Vector3.UP, Vector3.BACK][k] as Vector3) * 0.1))
	return b - a if (b - a).length() > 0.5 else Vector2.ZERO


## Where along the line through `o` along `a` (model space) the mouse at `at` is nearest (INF: looking
## straight along it).
func _line_t(at: Vector2, o: Vector3, a: Vector3) -> float:
	var inv := _mx().affine_inverse()
	var r: Array = ed.view.ray(at)
	var r0: Vector3 = inv * (r[0] as Vector3)
	var rd: Vector3 = (inv.basis * (r[1] as Vector3)).normalized()
	var w := o - r0
	var b := a.dot(rd)
	var den := 1.0 - b * b
	if den < 1e-6:
		return INF
	return (b * rd.dot(w) - a.dot(w)) / den


## The drag's move so far (model space; INF - none yet). Smooth - `stepped` (Ctrl held): in whole grid steps.
func _drag_delta(at: Vector2, stepped: bool) -> Vector3:
	var press: Vector2 = _drag["press"]
	var o: Vector3 = _drag["start"]
	if not _drag.has("axis") and not _drag.has("plane_n"):
		if at.distance_to(press) < DRAG_DEAD_PX:
			return Vector3.INF
		if ed.get("move_mode") == "perspective" or Input.is_key_pressed(KEY_SHIFT):
			_drag["plane_n"] = _facing_axis()
		else:
			var d := (at - press).normalized()
			var best := 1
			var bd := -1.0
			for k in 3:
				var sd := _axis_on_screen(o, k)
				if sd == Vector2.ZERO:
					continue   # (pointing at the camera: not what a drag across the screen means)
				var al := absf(d.dot(sd.normalized()))
				if al > bd:
					bd = al
					best = k
			_drag["axis"] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][best]
		_drag_hint()
	var step := grid_step if stepped else 0.0
	if _drag.has("axis"):
		var a: Vector3 = _drag["axis"]
		var t0 := _line_t(press, o, a)
		var t1 := _line_t(at, o, a)
		if t0 == INF or t1 == INF:
			return Vector3.INF
		var t := t1 - t0
		if step > 0.0:
			t = snappedf(t, step)
		return a * t
	var n: Vector3 = _drag["plane_n"]
	var pl := _plane(o, n, Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP)
	var h0 := _on_plane(press, pl)
	var h1 := _on_plane(at, pl)
	if h0 == Vector3.INF or h1 == Vector3.INF:
		return Vector3.INF
	var dv := h1 - h0
	if step > 0.0:
		dv = dv.snapped(Vector3.ONE * step)
		dv -= n * dv.dot(n)   # (kept on the plane)
	return dv


## The model's axis plane the view looks at most squarely: its normal (model space).
func _facing_axis() -> Vector3:
	var fwd: Vector3 = _mx().basis.inverse() * (-ed.view.cam.global_basis.z)
	var k := 0
	for i in 3:
		if absf(fwd[i]) > absf(fwd[k]):
			k = i
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][k]


func _drag_hint() -> void:
	if _drag.has("axis"):
		var k := [Vector3.RIGHT, Vector3.UP, Vector3.BACK].find(_drag["axis"])
		ed.view.hint = "Along %s - X / Y / Z: another axis (again: free), Ctrl: grid steps" % "XYZ"[k]
	elif _drag.has("plane_n"):
		var k := [Vector3.RIGHT, Vector3.UP, Vector3.BACK].find(_drag["plane_n"])
		ed.view.hint = "Free on the %s plane - X / Y / Z: along an axis, Ctrl: grid steps" % ["YZ", "XZ", "XY"][k]


## Guides on (the Guides box; a meta - hot reload safe).
func guides_on() -> bool:
	return not bool(get_meta("guides_off", false))


const GUIDE_PX := 8.0


## What a dragged point can line up with (model space), once a drag: [{k: axis, v: level, at: a point
## there, kind: "own" (its own curve's point) / "point" / "face" (a flat face square to that axis)}].
func _guide_levels() -> Array:
	var out := []
	var own: Dictionary = _drag.get("own", {})
	var mine: Array = _drag.get("handle", [-1, -1])
	var moving := {}
	if not _drag.has("handle"):
		for i in sel:
			moving[i] = true
	for ci in curves.size():
		if curves[ci].get("hidden", false) or moving.has(ci):
			continue
		var x := cx(curves[ci], own)
		var k: PackedVector3Array = curves[ci]["ctrl"]
		var circle := str(curves[ci]["kind"]) == "circle"
		for j in k.size():
			if ci == int(mine[0]) and j == int(mine[1]):
				continue
			if circle and j == 1:
				continue   # (a circle's rim handle: not a point on it worth lining up with)
			var q := x * k[j]
			for a in 3:
				out.append({"k": a, "v": q[a], "at": q, "kind": "own" if ci == int(mine[0]) else "point"})
	# flat faces square to an axis: their levels
	var inv := _mx().affine_inverse()
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree() or p.mesh == null or p.mesh.get_surface_count() == 0:
			continue
		var rel := inv * p.global_transform
		var levels := {}
		for si in p.mesh.get_surface_count():
			var arr := p.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			for t in range(0, ix.size(), 3):
				var a3 := rel * vs[ix[t]]
				var b3 := rel * vs[ix[t + 1]]
				var c3 := rel * vs[ix[t + 2]]
				var cr := (b3 - a3).cross(c3 - a3)
				var ar := cr.length()
				if ar < 1e-10:
					continue
				var n := cr / ar
				for a in 3:
					if absf(n[a]) > 0.9995:
						var lk := "%d:%.4f" % [a, a3[a]]
						var e: Array = levels.get(lk, [a, a3[a], 0.0, Vector3.ZERO])
						e[2] = float(e[2]) + ar
						e[3] = (e[3] as Vector3) + (a3 + b3 + c3) / 3.0 * ar
						levels[lk] = e
		for lk in levels:
			var e: Array = levels[lk]
			if float(e[2]) > 1e-6:
				out.append({"k": int(e[0]), "v": float(e[1]), "at": (e[3] as Vector3) / float(e[2]), "kind": "face"})
	return out


## Point `p` (model space) lined up with the guides along the axes it's free to move on: snapped to the
## nearest level within GUIDE_PX on screen (its own curve's points first); _drag["guides"]: those used.
func _apply_guides(p: Vector3) -> Vector3:
	_drag["guides"] = []
	if not guides_on() or Input.is_key_pressed(KEY_ALT):
		return p
	if not _drag.has("levels"):
		_drag["levels"] = _guide_levels()
	var free_k := []
	if _drag.has("axis"):
		free_k = [[Vector3.RIGHT, Vector3.UP, Vector3.BACK].find(_drag["axis"])]
	elif _drag.has("plane_n"):
		var nk := [Vector3.RIGHT, Vector3.UP, Vector3.BACK].find(_drag["plane_n"])
		for a in 3:
			if a != nk:
				free_k.append(a)
	var out := p
	for a in free_k:
		var sd := _axis_on_screen(p, a)
		if sd == Vector2.ZERO:
			continue
		var tol := GUIDE_PX / (sd.length() / 0.1)   # (the screen's GUIDE_PX in metres along this axis, here)
		var best = null
		var bs := INF
		for g: Dictionary in _drag["levels"]:
			if int(g["k"]) != a:
				continue
			var dv := absf(float(g["v"]) - p[a])
			if dv > tol:
				continue
			var score: float = dv / tol + {"own": 0.0, "point": 0.15, "face": 0.3}[g["kind"]]
			if score < bs:
				bs = score
				best = g
		if best != null:
			out[a] = float(best["v"])
			(_drag["guides"] as Array).append(best)
	return out


func _drag_to(at: Vector2, stepped: bool) -> void:
	var d := _drag_delta(at, stepped)
	if d == Vector3.INF:
		return
	if not stepped:
		d = _apply_guides((_drag["start"] as Vector3) + d) - (_drag["start"] as Vector3)
	_drag["moved"] = true
	_drag["delta"] = d
	if _drag.has("handle"):
		var h: Array = _drag["handle"]
		var p: Vector3 = (_drag["start"] as Vector3) + d
		var k: PackedVector3Array = curves[h[0]]["ctrl"]
		var was := k[h[1]]
		k[h[1]] = (_drag.get("x", Transform3D()) as Transform3D).affine_inverse() * p
		curves[h[0]]["ctrl"] = k
		_move_corner(h[0], was, k[h[1]])
	else:
		for i in sel:
			var k: PackedVector3Array = (_drag["orig"][i]["ctrl"] as PackedVector3Array).duplicate()
			var dl: Vector3 = cx(curves[i], _drag.get("own", {})).basis.inverse() * d   # (the move in the curve's own space)
			for j in k.size():
				k[j] += dl
			curves[i]["ctrl"] = k
	refresh_solids()   # (the solids made of them follow as they're dragged)
	layer.queue_redraw()


## (while dragging) the axis it moves along, through where it started, and how far it's gone.
func _draw_drag() -> void:
	if _drag.is_empty() or not _drag.has("start") or not _drag.get("moved", false):
		return
	var mx := _mx()
	var o: Vector3 = _drag["start"]
	var f := layer.get_theme_default_font()
	var fs := maxi(Settings.MIN_FONT, 14)
	var d: Vector3 = _drag.get("delta", Vector3.ZERO)
	var txt := ""
	if _drag.has("axis"):
		var a: Vector3 = _drag["axis"]
		var k := [Vector3.RIGHT, Vector3.UP, Vector3.BACK].find(a)
		var col: Color = AXIS_COLS[k]
		var pts := PackedVector2Array()
		for t in [-50.0, -5.0, -1.0, 0.0, 1.0, 5.0, 50.0]:
			var w: Vector3 = mx * (o + a * float(t))
			if not ed.view.behind(w):
				pts.append(ed.view.project(w))
		if pts.size() >= 2:
			layer.draw_polyline(pts, Color(col, 0.75), 1.5, true)
		txt = "%s %+.3f m" % ["XYZ"[k], d.dot(a)]
	elif _drag.has("plane_n"):
		txt = "%+.3f  %+.3f  %+.3f m" % [d.x, d.y, d.z]
	# the guides it's lined up with: dashed, in the axis's colour, from what it lines up with
	var p := o + d
	var sp := _screen(p)
	var notes := []
	for g: Dictionary in _drag.get("guides", []):
		var k := int(g["k"])
		var col: Color = AXIS_COLS[k]
		var src: Vector3 = g["at"]
		if str(g["kind"]) == "face":
			# (a level line across the view through the point - the flat face's height)
			var other := (k + 1) % 3 if _axis_on_screen(p, (k + 1) % 3) != Vector2.ZERO else (k + 2) % 3
			var ax: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][other]
			var a2 := _screen(p - ax * 0.3)
			var b2 := _screen(p + ax * 0.3)
			layer.draw_dashed_line(a2, b2, Color(col, 0.9), 1.5, 6.0)
			layer.draw_dashed_line(sp, _screen(src), Color(col, 0.45), 1.0, 4.0)
			notes.append("%s level with a flat face" % "XYZ"[k])
		else:
			var ss := _screen(src)
			layer.draw_dashed_line(ss, sp, Color(col, 0.95), 1.5, 6.0)
			layer.draw_arc(ss, 5.0, 0, TAU, 16, Color(col, 0.95), 1.5)
			notes.append("%s same as %s" % ["XYZ"[k], "a point on this curve" if str(g["kind"]) == "own" else "a point"])
	if not notes.is_empty():
		layer.draw_arc(sp, 6.0, 0, TAU, 16, Color(1, 0.92, 0.8), 1.5)
	if txt != "":
		layer.draw_string(f, sp + Vector2(14, -12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.8))
	for ni in notes.size():
		layer.draw_string(f, sp + Vector2(14, 8 + ni * (fs + 4)), notes[ni], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, AXIS_COLS[int(_drag["guides"][ni]["k"])])


## Keys (the editor asks first). True - taken.
func key(k: InputEventKey) -> bool:
	if not _drag.is_empty() and _drag.has("start") and k.pressed and not k.echo and not k.ctrl_pressed and k.keycode in [KEY_X, KEY_Y, KEY_Z]:
		# (a point or curve being dragged: along that axis - again: free on the plane facing the view)
		var a: Vector3 = {KEY_X: Vector3.RIGHT, KEY_Y: Vector3.UP, KEY_Z: Vector3.BACK}[k.keycode]
		if _drag.get("axis", Vector3.ZERO) == a:
			_drag.erase("axis")
			_drag["plane_n"] = _facing_axis()
		else:
			_drag.erase("plane_n")
			_drag["axis"] = a
		_drag_hint()
		_drag_to(ed._mouse, Input.is_key_pressed(KEY_CTRL))
		return true
	if not op.is_empty():
		match k.keycode:
			KEY_ESCAPE:
				cancel_op()
				return true
			KEY_ENTER, KEY_KP_ENTER:
				if typed != "" and typed.is_valid_float():
					op["value"] = float(typed)
					typed = ""
					_op_update()
				confirm_op()
				return true
			KEY_BACKSPACE:
				typed = typed.substr(0, maxi(0, typed.length() - 1))
				_op_hint()
				return true
			KEY_N:
				if str(op.get("kind", "")) == "extrude":
					op["neg"] = not bool(op.get("neg", false))
					_op_update()
					_op_hint()
					return true
			KEY_X, KEY_Y, KEY_Z:
				if str(op.get("kind", "")) in ["move", "turn", "scale"]:
					# (an axis: again - free again)
					var ax := [KEY_X, KEY_Y, KEY_Z].find(k.keycode)
					op["axis"] = -1 if int(op.get("axis", -1)) == ax else ax
					op.erase("delta")
					if typed == "":
						_xf_motion(ed._mouse)
					else:
						_op_update()
					_op_hint()
				return true   # (while an operation runs, X never reaches the editor's Delete)
		var ch := _typed_char(k)
		if ch != "":
			typed += ch
			if typed.is_valid_float():
				op["value"] = float(typed)
				op.erase("delta")   # (a typed amount: along the axis - X if none)
				_op_update()
			_op_hint()
			return true
		if op.get("kind", "") == "revolve" or op.get("kind", "") == "pipe":
			pass
		return false
	if tool != "":
		match k.keycode:
			KEY_ESCAPE:
				if not placed.is_empty():
					placed = PackedVector3Array()
					plane = {}
					_hint()
					layer.queue_redraw()
				else:
					stop()
				return true
			KEY_ENTER, KEY_KP_ENTER:
				if typed != "":
					apply_typed()
				elif tool in ["line", "spline"] and placed.size() >= 2:
					_finish(false)
				return true
			KEY_BACKSPACE:
				if typed != "":
					typed = typed.substr(0, typed.length() - 1)
				elif not placed.is_empty():
					placed.remove_at(placed.size() - 1)
				_hint()
				layer.queue_redraw()
				return true
			KEY_EQUAL, KEY_KP_ADD:
				sides = mini(sides + 1, 64)
				_hint()
				layer.queue_redraw()
				return true
			KEY_MINUS, KEY_KP_SUBTRACT:
				if typed == "" and tool == "polygon":
					sides = maxi(sides - 1, 3)
					_hint()
					layer.queue_redraw()
					return true
		var ch := _typed_char(k)
		if ch != "" and not placed.is_empty():
			typed += ch
			_hint()
			return true
	# tool keys: only with the Curve modeling tab showing (so they don't clash with the mesh keys)
	if not ed.curve_tab_shown() or k.ctrl_pressed:
		return _sel_keys(k)
	match k.keycode:
		KEY_L:
			if not k.shift_pressed:
				begin("line"); return true
		KEY_P:
			begin("polygon" if k.shift_pressed else "spline"); return true
		KEY_C:
			begin("arc" if k.shift_pressed else "circle"); return true
		KEY_R:
			if k.shift_pressed:
				begin("rect"); return true
		KEY_E:
			if not sel.is_empty() and not k.shift_pressed:
				begin_extrude(); return true
	return _sel_keys(k)


## Keys on the selected curves (any tab): Delete / X, Shift+D, Esc.
func _sel_keys(k: InputEventKey) -> bool:
	if sel.is_empty() or k.ctrl_pressed:
		return false
	match k.keycode:
		KEY_DELETE, KEY_X:
			delete_selected(); return true
		KEY_D:
			if k.shift_pressed:
				duplicate_selected(); return true
		KEY_G:
			if not k.shift_pressed and not k.alt_pressed:
				begin_xf("move"); return true
		KEY_R:
			if not k.shift_pressed and not k.alt_pressed:
				begin_xf("turn"); return true
		KEY_S:
			if not k.shift_pressed and not k.alt_pressed:
				begin_xf("scale"); return true
		KEY_ESCAPE:
			select(-1); return true
	return false


static func _typed_char(k: InputEventKey) -> String:
	var u := k.unicode
	if u >= 48 and u <= 57:
		return char(u)
	if u in [46, 45, 32, 44]:   # . - space ,
		return char(u)
	return ""


# --- curve operations ----------------------------------------------------------------------

func _need(n: int, what: String) -> bool:
	if sel.size() < n:
		ed._say("%s: select %s first (click a curve in the view; Shift+click: more)." % [what, "a curve" if n == 1 else "%d curves" % n])
		return false
	return true


func delete_selected() -> void:
	if not _need(1, "Delete"):
		return
	var before := _state()
	var keep := []
	for i in curves.size():
		if not i in sel:
			keep.append(curves[i])
	curves = keep
	sel = []
	_changed("Delete curves", before)


func duplicate_selected() -> void:
	if not _need(1, "Duplicate"):
		return
	var before := _state()
	var shift: Vector3 = Vector3.RIGHT * grid_step * 4.0
	var made := []
	var own := owner_xfs()
	for i in sel:
		var c: Dictionary = _fresh(baked(curves[i], cx(curves[i], own)))
		var k: PackedVector3Array = c["ctrl"]
		for j in k.size():
			k[j] += shift
		c["ctrl"] = k
		curves.append(c)
		made.append(curves.size() - 1)
	sel = made
	_changed("Duplicate curves", before)


## The selected curves mirrored across the model's `axis` plane (copies; `copy` false: in place).
func mirror_selected(axis := 0, copy := true) -> void:
	if not _need(1, "Mirror"):
		return
	var before := _state()
	var made := []
	var own := owner_xfs()
	for i in sel:
		var c: Dictionary = baked(curves[i], cx(curves[i], own)) if copy else curves[i].duplicate(true)
		var k: PackedVector3Array = c["ctrl"]
		for j in k.size():
			k[j][axis] = -k[j][axis]
		c["ctrl"] = k
		var n: Vector3 = c.get("n", Vector3.UP)
		n[axis] = -n[axis]
		c["n"] = n
		if copy:
			curves.append(_fresh(c))
			made.append(curves.size() - 1)
		else:
			curves[i] = c
	if copy:
		sel = made
	_changed("Mirror curves", before)


## `count` copies of the selected curves round the model's Y axis (the originals among them).
func radial_array(count := 6, axis := Vector3.UP) -> void:
	if not _need(1, "Radial array"):
		return
	var before := _state()
	var src := sel.duplicate()
	var own := owner_xfs()
	for s in range(1, count):
		var ang := TAU * s / count
		for i in src:
			var c: Dictionary = _fresh(baked(curves[i], cx(curves[i], own)))
			var k: PackedVector3Array = c["ctrl"]
			for j in k.size():
				k[j] = k[j].rotated(axis, ang)
			c["ctrl"] = k
			c["n"] = (c.get("n", Vector3.UP) as Vector3).rotated(axis, ang)
			curves.append(c)
			sel.append(curves.size() - 1)
	_changed("Radial array", before)


func reverse_selected() -> void:
	if not _need(1, "Reverse"):
		return
	var before := _state()
	for i in sel:
		var c: Dictionary = curves[i]
		var k: PackedVector3Array = c["ctrl"]
		if str(c["kind"]) == "circle":
			continue
		k.reverse()
		c["ctrl"] = k
		if c.has("radii"):
			var r: PackedFloat32Array = c["radii"]
			r.reverse()
			c["radii"] = r
		if c.has("sharp"):
			var sh: PackedByteArray = c["sharp"]
			sh.reverse()
			c["sharp"] = sh
	_changed("Reverse curves", before)


func toggle_closed() -> void:
	if not _need(1, "Close / open"):
		return
	var before := _state()
	for i in sel:
		var c: Dictionary = curves[i]
		if str(c["kind"]) in ["line", "spline", "path"] and (c["ctrl"] as PackedVector3Array).size() >= 3:
			c["closed"] = not c.get("closed", false)
	_changed("Close / open curves", before)


## Two open curves joined into one at their nearest ends (a line and a spline: a spline).
func join_selected() -> void:
	if not _need(2, "Join"):
		return
	var a: Dictionary = curves[sel[0]]
	var b: Dictionary = curves[sel[1]]
	if not (str(a["kind"]) in ["line", "spline"] and str(b["kind"]) in ["line", "spline"]) or a.get("closed", false) or b.get("closed", false):
		ed._say("Join: two open lines or splines.")
		return
	var before := _state()
	var own := owner_xfs()
	var c := join(baked(a, cx(a, own)), baked(b, cx(b, own)))
	var keep := []
	for i in curves.size():
		if not i in [sel[0], sel[1]]:
			keep.append(curves[i])
	keep.append(_fresh(c))
	curves = keep
	sel = [curves.size() - 1]
	_changed("Join curves", before)


static func join(a: Dictionary, b: Dictionary) -> Dictionary:
	var ka: PackedVector3Array = (a["ctrl"] as PackedVector3Array).duplicate()
	var kb: PackedVector3Array = (b["ctrl"] as PackedVector3Array).duplicate()
	var ends := [[ka[ka.size() - 1], kb[0], false, false], [ka[ka.size() - 1], kb[kb.size() - 1], false, true],
		[ka[0], kb[0], true, false], [ka[0], kb[kb.size() - 1], true, true]]
	var best: Array = ends[0]
	for e in ends:
		if (e[0] as Vector3).distance_to(e[1]) < (best[0] as Vector3).distance_to(best[1]):
			best = e
	if best[2]:
		ka.reverse()
	if best[3]:
		kb.reverse()
	var start := 1 if ka[ka.size() - 1].distance_to(kb[0]) < 1e-5 else 0
	for j in range(start, kb.size()):
		ka.append(kb[j])
	var kind := "line" if str(a["kind"]) == "line" and str(b["kind"]) == "line" else "spline"
	var closed := ka.size() >= 4 and ka[0].distance_to(ka[ka.size() - 1]) < 1e-5
	if closed:
		ka.remove_at(ka.size() - 1)
	return {"kind": kind, "ctrl": ka, "closed": closed, "n": a.get("n", Vector3.UP), "name": a.get("name", "Curve")}


## The picked closed curves combined on their plane - "union" (one outline), "subtract" (the first
## picked minus the others: what's inside it becomes holes), "intersect" (what they all share) - the
## results (outlines and holes, as closed lines) in place of them. One undo step.
func curve_boolean(op: String) -> void:
	var what: String = {"union": "Union curves", "subtract": "Subtract curves", "intersect": "Intersect curves"}[op]
	if not _need(2, what):
		return
	var own := owner_xfs()
	var cs := []
	for i in sel:
		if not curves[i].get("closed", false):
			ed._say("%s: closed curves only (%s is open)." % [what, curves[i].get("name", "a curve")])
			return
		cs.append(baked(curves[i], cx(curves[i], own)))
	var out := curve_bool(cs, op)
	# (what was brought onto the first one's plane, and what couldn't be)
	var n0: Vector3 = (cs[0].get("n", Vector3.UP) as Vector3).normalized()
	var o0: Vector3 = (cs[0]["ctrl"] as PackedVector3Array)[0]
	var lifted := 0
	var angled := 0
	var edge := []
	for ci in range(1, cs.size()):
		var c: Dictionary = cs[ci]
		if not projectable(c, n0):
			edge.append(str(c.get("name", "a curve")))
		elif not _parallel(c, n0):
			angled += 1
		elif not coplanar([cs[0], c]):
			lifted += 1
	var note := ""
	if lifted > 0:
		note += " %d on %s brought onto the first's plane." % [lifted, "a parallel plane" if lifted == 1 else "parallel planes"]
	if angled > 0:
		note += " %d at an angle projected onto it (as seen square-on from it)." % angled
	if not edge.is_empty():
		note += " Left out, edge-on to it: %s." % ", ".join(edge)
	if out.is_empty():
		ed._say("%s: nothing is left.%s" % [what, note])
		return
	var before := _state()
	var keep := []
	for i in curves.size():
		if not i in sel:
			keep.append(curves[i])
	sel = []
	for c in out:
		c["name"] = "%s %d" % [{"union": "Union", "subtract": "Cut", "intersect": "Common"}[op], _nid()]
		keep.append(_fresh(c))
		sel.append(keep.size() - 1)
	curves = keep
	_changed(what, before)
	ed._say("%s: %d curve%s made on the first picked curve's plane (holes among them: extrude or fill them all together).%s" % [what, out.size(), "" if out.size() == 1 else "s", note])


## The picked closed curves with many points (a boolean's result from before, a dense outline) made
## lean: their corners and straight sides kept, a point every ~40° along their bends (a path). Their
## ids stay: the solids made from them follow. One undo step.
func simplify_selected() -> void:
	if not _need(1, "Simplify curve"):
		return
	var before := _state()
	var done := 0
	var was := 0
	var now_n := 0
	for i in sel:
		var c: Dictionary = curves[i]
		var lean := simplified(c)
		if lean.is_empty():
			continue
		was += (c["ctrl"] as PackedVector3Array).size()
		now_n += (lean["ctrl"] as PackedVector3Array).size()
		for k in ["kind", "ctrl", "sharp", "closed"]:
			if lean.has(k):
				c[k] = lean[k]
		if not lean.has("sharp"):
			c.erase("sharp")
		c.erase("radii")
		done += 1
	if done == 0:
		ed._say("Simplify curve: pick closed lines or paths with more points than they need.")
		return
	_changed("Simplify curve", before)
	ed._say("Simplified %d curve%s: %d points -> %d." % [done, "" if done == 1 else "s", was, now_n])


## `c` (a closed line or path with many points) as a lean line or path ({} - nothing to gain).
static func simplified(c: Dictionary) -> Dictionary:
	if not c.get("closed", false) or not str(c["kind"]) in ["line", "path"] or (c["ctrl"] as PackedVector3Array).size() < 7:
		return {}
	var n: Vector3 = (c.get("n", Vector3.UP) as Vector3).normalized()
	var k: PackedVector3Array = c["ctrl"]
	var o := k[0]
	var u := _any_perp(n)
	var v := n.cross(u)
	var f := PackedVector2Array()
	for q in sample(c):
		f.append(Vector2((q - o).dot(u), (q - o).dot(v)))
	var fit := fit_path(_tidy(f))
	if fit.is_empty() or (fit["pts"] as PackedVector2Array).size() >= k.size():
		return {}
	var k3 := PackedVector3Array()
	for q: Vector2 in fit["pts"]:
		k3.append(o + u * q.x + v * q.y)
	var e := {"kind": "path" if fit["curved"] else "line", "ctrl": k3, "closed": true}
	if fit["curved"]:
		e["sharp"] = fit["sharp"]
	return e


## The closed curves `cs` (placed) all on the first one's plane.
static func coplanar(cs: Array) -> bool:
	var n: Vector3 = (cs[0].get("n", Vector3.UP) as Vector3).normalized()
	var o: Vector3 = (cs[0]["ctrl"] as PackedVector3Array)[0]
	for c in cs:
		if absf((c.get("n", Vector3.UP) as Vector3).normalized().dot(n)) < 0.999:
			return false
		for q in sample(c):
			if absf((q - o).dot(n)) > 1e-3:
				return false
	return true


## The 2D boolean of closed curves on one plane (static: tests call it): new closed line curves -
## outlines, and holes (wound the other way) where one's left inside another. [] - not on one plane,
## or nothing left.
static func curve_bool(cs: Array, op: String, ops := []) -> Array:
	if cs.size() < 2:
		return []
	# (worked out on the first curve's plane: the others projected onto it along its normal - on a
	# parallel plane, lifted or lowered, they land as they are; at an angle, as seen square-on from it;
	# edge-on, they'd be a line: left out - projectable() says which)
	var n: Vector3 = (cs[0].get("n", Vector3.UP) as Vector3).normalized()
	var o: Vector3 = (cs[0]["ctrl"] as PackedVector3Array)[0]
	var u := _any_perp(n)
	var v := n.cross(u)
	var polys := []
	var used := []
	for ci in cs.size():
		var c: Dictionary = cs[ci]
		var f := PackedVector2Array()
		for q in sample(c):
			f.append(Vector2((q - o).dot(u), (q - o).dot(v)))
		if ci > 0 and not projectable(c, n):
			continue
		polys.append(f)
		used.append(_flat_copy(c, n, o) if _parallel(c, n) else {})
	if polys.size() < 2:
		return []
	var outers: Array = [polys[0]]
	var holes: Array = []
	for k in range(1, polys.size()):
		var p: PackedVector2Array = polys[k]
		var next := []
		match (str(ops[k]) if k < ops.size() else op):
			"union":
				var merged := p
				for ol: PackedVector2Array in outers:
					var r := Geometry2D.merge_polygons(ol, merged)
					var outs := r.filter(func(q): return not Geometry2D.is_polygon_clockwise(q))
					if outs.size() == 1:
						merged = outs[0]
						holes.append_array(r.filter(func(q): return Geometry2D.is_polygon_clockwise(q)))
					else:
						next.append(ol)   # (apart: kept as it is)
				next.append(merged)
			"subtract":
				for ol: PackedVector2Array in outers:
					for q in Geometry2D.clip_polygons(ol, p):
						(holes if Geometry2D.is_polygon_clockwise(q) else next).append(q)
			"intersect":
				for ol: PackedVector2Array in outers:
					for q in Geometry2D.intersect_polygons(ol, p):
						if not Geometry2D.is_polygon_clockwise(q):
							next.append(q)
		outers = next
	var out := []
	for f: PackedVector2Array in outers + holes:
		# (one of the curves come through whole - a hole inside, an outline untouched: that curve
		# itself, as it was - a circle stays a circle)
		var same := _same_curve(f, polys, used)
		if not same.is_empty():
			out.append(same)
			continue
		var c := fit_path(_tidy(f))
		if c.is_empty():
			continue
		var k3 := PackedVector3Array()
		for q: Vector2 in c["pts"]:
			k3.append(o + u * q.x + v * q.y)
		var e := {"kind": "path" if c["curved"] else "line", "ctrl": k3, "closed": true, "n": n}
		if c["curved"]:
			e["sharp"] = c["sharp"]
		out.append(e)
	return out


## The curve of `cs` whose outline `f` is (its 2D outline in `polys`: the same area, every point of
## `f` on it) - a copy of it ({} - none).
static func _same_curve(f: PackedVector2Array, polys: Array, cs: Array) -> Dictionary:
	var af := absf(_area2(f))
	for i in polys.size():
		var pf: PackedVector2Array = polys[i]
		var ap := absf(_area2(pf))
		if absf(af - ap) > maxf(ap, 1e-9) * 1e-3:
			continue
		var on := true
		for q in f:
			var best := INF
			for k in pf.size():
				best = minf(best, Geometry2D.get_closest_point_to_segment(q, pf[k], pf[(k + 1) % pf.size()]).distance_squared_to(q))
			if best > 1e-8:
				on = false
				break
		if on and not (cs[i] as Dictionary).is_empty():
			return (cs[i] as Dictionary).duplicate(true)
	return {}


## `c` on a plane parallel to the one facing `n` through `o`: its points brought onto that plane (it
## keeps its shape - a lifted circle lands as the same circle).
static func _flat_copy(c: Dictionary, n: Vector3, o: Vector3) -> Dictionary:
	var out := c.duplicate(true)
	var k: PackedVector3Array = (c["ctrl"] as PackedVector3Array).duplicate()
	for j in k.size():
		k[j] -= n * (k[j] - o).dot(n)
	out["ctrl"] = k
	out["n"] = n if (c.get("n", Vector3.UP) as Vector3).dot(n) >= 0.0 else -n
	return out


static func _parallel(c: Dictionary, n: Vector3) -> bool:
	return absf((c.get("n", Vector3.UP) as Vector3).normalized().dot(n)) > 0.999


## `c` seen along `n` still has an area (it isn't standing edge-on to the plane).
static func projectable(c: Dictionary, n: Vector3) -> bool:
	var u := _any_perp(n)
	var v := n.cross(u)
	var f := PackedVector2Array()
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for q in sample(c):
		var p := Vector2(q.dot(u), q.dot(v))
		f.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	var size := maxf((hi - lo).length(), 1e-9)
	return absf(_area2(f)) > size * size * 1e-3


static func _area2(f: PackedVector2Array) -> float:
	var a := 0.0
	for i in f.size():
		a += f[i].cross(f[(i + 1) % f.size()])
	return a * 0.5


## A dense closed outline (from a boolean) as few points as keep its shape: its corners (a turn over
## 25°) and the ends of its straight sides kept and marked sharp; along a curved stretch a point each
## ~40° of turning (the path's spline runs smooth through them). {pts, sharp, curved} ({} - too small).
static func fit_path(f: PackedVector2Array) -> Dictionary:
	var m := f.size()
	if m < 3:
		return {}
	var turn := PackedFloat32Array()
	for i in m:
		var a := f[(i - 1 + m) % m]
		var b := f[i]
		var c := f[(i + 1) % m]
		turn.append((b - a).angle_to(c - b))
	# straight sides: corner to corner, or far longer than the sides beside it (a curve's sides are
	# about as long as their neighbours, however big it is), or barely turning at either end
	var lens := PackedFloat32Array()
	for i in m:
		lens.append(f[i].distance_to(f[(i + 1) % m]))
	var corner := deg_to_rad(25.0)
	var straight := PackedByteArray()
	for i in m:
		var j := (i + 1) % m
		var ends_corners := absf(turn[i]) > corner and absf(turn[j]) > corner
		# (compared with the sides it joins smoothly - not across a corner, where a boolean leaves slivers)
		var near := 0.0
		if absf(turn[i]) <= corner:
			near = maxf(near, lens[(i - 1 + m) % m])
		if absf(turn[j]) <= corner:
			near = maxf(near, lens[j])
		var longer := near > 0.0 and lens[i] > 3.0 * near
		var flat := absf(turn[i]) < deg_to_rad(1.0) and absf(turn[j]) < deg_to_rad(1.0)
		straight.append(1 if ends_corners or longer or flat else 0)
	var keep := PackedByteArray()
	keep.resize(m)
	var sharp := PackedByteArray()
	sharp.resize(m)
	var curved := false
	for i in m:
		var prev_straight := straight[(i - 1 + m) % m] == 1
		var next_straight := straight[i] == 1
		if absf(turn[i]) > deg_to_rad(25.0) or prev_straight != next_straight or (prev_straight and next_straight and absf(turn[i]) > deg_to_rad(1.0)):
			keep[i] = 1
			sharp[i] = 1
		if not next_straight:
			curved = true
	# each curved stretch (between two corners - or the whole loop if it has none) gets points spread
	# evenly along its turning: a point per ~35°, at least one in its middle (a short arc needs it to
	# stay round)
	var corners := PackedInt32Array()
	for i in m:
		if sharp[i] == 1:
			corners.append(i)
	if corners.is_empty():
		corners.append(0)
		keep[0] = 1
	for ci in corners.size():
		var a := corners[ci]
		var b := corners[(ci + 1) % corners.size()]
		var span := (b - a + m) % m
		if span == 0:
			span = m   # (one corner: the whole loop)
		if span < 2 or straight[a] == 1:
			continue
		# the turning so far at each point inside the stretch
		var cum := PackedFloat32Array()
		var tot := 0.0
		for t in range(1, span):
			tot += absf(turn[(a + t) % m])
			cum.append(tot)
		tot += absf(turn[b]) * 0.0
		var whole := tot + 1e-9
		var parts := maxi(2, int(ceil(whole / deg_to_rad(35.0))))
		# (a stretch on one circle - an arc of a circle the boolean cut: its two ends and its middle are
		# enough, the path draws it as that exact arc)
		var run := PackedVector3Array()
		for t in span + 1:
			var q := f[(a + t) % m]
			run.append(Vector3(q.x, q.y, 0.0))
		if not _arc_run(run).is_empty():
			parts = 2
		for j in range(1, parts):
			var want := whole * j / parts
			var best := 0
			for t in cum.size():
				if absf(cum[t] - want) < absf(cum[best] - want):
					best = t
			keep[(a + 1 + best) % m] = 1
	var pts := PackedVector2Array()
	var sh := PackedByteArray()
	for i in m:
		if keep[i] == 1:
			pts.append(f[i])
			sh.append(sharp[i])
	if pts.size() < 3:
		return {}
	return {"pts": pts, "sharp": sh, "curved": curved}


## A polygon without repeated points or points on a straight line between their neighbours.
static func _tidy(f: PackedVector2Array) -> PackedVector2Array:
	# (points nearly on top of each other - an offset's or a clip's pairs, a fraction of a millimetre
	# apart - made one: each would read as a corner)
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for q in f:
		lo = lo.min(q)
		hi = hi.max(q)
	var tol := maxf(1e-6, (hi - lo).length() * 2e-3)
	var merged := PackedVector2Array()
	for q in f:
		if merged.is_empty() or q.distance_to(merged[merged.size() - 1]) >= tol:
			merged.append(q)
	while merged.size() > 3 and merged[0].distance_to(merged[merged.size() - 1]) < tol:
		merged.remove_at(merged.size() - 1)
	f = merged
	var out := PackedVector2Array()
	var m := f.size()
	for i in m:
		var a := f[(i - 1 + m) % m]
		var b := f[i]
		var c := f[(i + 1) % m]
		if b.distance_to(a) < 1e-6:
			continue
		if absf((b - a).normalized().cross((c - b).normalized())) < 1e-4 and (b - a).dot(c - b) > 0.0:
			continue
		out.append(b)
	return out


## A bezier between the nearest ends of two selected curves, leaving each along its own direction.
func bridge_selected() -> void:
	if not _need(2, "Bridge"):
		return
	var own := owner_xfs()
	var ca := baked(curves[sel[0]], cx(curves[sel[0]], own))
	var sa := sample(ca)
	var sb := sample(baked(curves[sel[1]], cx(curves[sel[1]], own)))
	var c := bridge(sa, sb)
	if c.is_empty():
		return
	c["n"] = ca.get("n", Vector3.UP)
	add_curve(c)


static func bridge(sa: PackedVector3Array, sb: PackedVector3Array) -> Dictionary:
	if sa.size() < 2 or sb.size() < 2:
		return {}
	var best := INF
	var pick := [0, 0]
	for ea in [0, sa.size() - 1]:
		for eb in [0, sb.size() - 1]:
			var d := sa[ea].distance_to(sb[eb])
			if d < best:
				best = d
				pick = [ea, eb]
	var a := sa[pick[0]]
	var b := sb[pick[1]]
	var ta := (a - sa[1 if pick[0] == 0 else sa.size() - 2]).normalized()
	var tb := (b - sb[1 if pick[1] == 0 else sb.size() - 2]).normalized()
	var L := maxf(a.distance_to(b) / 3.0, 1e-4)
	return {"kind": "bezier", "ctrl": PackedVector3Array([a, a + ta * L, b + tb * L, b]), "closed": false}


## Curve `c` offset by `d` in its plane (outward for a closed one turning left): a line's corners
## mitred, a circle's radius, a spline's points moved along the curve's side.
static func offset(c: Dictionary, d: float) -> Dictionary:
	var out := c.duplicate(true)
	var k: PackedVector3Array = (c["ctrl"] as PackedVector3Array).duplicate()
	var n: Vector3 = (c.get("n", Vector3.UP) as Vector3).normalized()
	var closed: bool = c.get("closed", false)
	match str(c["kind"]):
		"circle":
			var r := k[0].distance_to(k[1])
			k[1] = k[0] + (k[1] - k[0]).normalized() * maxf(r + d, 1e-4)
		"line", "spline", "path":
			var m := k.size()
			var s := _side_sign(k, n, closed)
			var res := PackedVector3Array()
			for i in m:
				var has_prev := closed or i > 0
				var has_next := closed or i < m - 1
				var e0 := (k[i] - k[(i - 1 + m) % m]).normalized() if has_prev else Vector3.ZERO
				var e1 := (k[(i + 1) % m] - k[i]).normalized() if has_next else Vector3.ZERO
				var n0 := e0.cross(n) * s
				var n1 := e1.cross(n) * s
				if not has_prev:
					n0 = n1
				if not has_next:
					n1 = n0
				var bis := (n0 + n1)
				if bis.length() < 1e-6:
					bis = n0
				bis = bis.normalized()
				var cosh := maxf(bis.dot(n0), 0.2)
				res.append(k[i] + bis * (d / cosh))
			k = res
		_:
			var s2 := sample(c)
			k = s2
			out["kind"] = "spline"
			return offset(out.merged({"ctrl": s2}, true), d)
	out["ctrl"] = k
	if out.has("radii"):
		var rr: PackedFloat32Array = (out["radii"] as PackedFloat32Array).duplicate()
		for i in rr.size():
			rr[i] = maxf(0.0, rr[i] + d) if rr[i] > 0.0 else 0.0
		out["radii"] = rr
	return out


## +1 if the edge x normal points outward of closed loop `k` (it turns left about `n`), else -1.
static func _side_sign(k: PackedVector3Array, n: Vector3, closed: bool) -> float:
	if not closed:
		return 1.0
	var a := 0.0
	for i in k.size():
		a += k[i].cross(k[(i + 1) % k.size()]).dot(n)
	return 1.0 if a > 0.0 else -1.0


# --- interactive operations: extrude, offset, fillet corners, revolve, pipe -----------------------

## The picked curves moved (G), turned (R) or scaled (S) in 3D with the mouse - X / Y / Z: along /
## about an axis, a typed number: exactly that far / many degrees / times; click keeps it. The solids
## made from them follow. (A placed curve - its solid moved - turns where it shows.)
func begin_xf(mode: String) -> void:
	if not _need(1, {"move": "Move curves", "turn": "Turn curves", "scale": "Scale curves"}[mode]):
		return
	if _any_baked(sel):
		ed._say("A baked solid's curves are part of it: drag their points to reshape it (move the solid to move them).")
		return
	stop()
	var own := owner_xfs()
	var centre := Vector3.ZERO
	var cnt := 0
	for i in sel:
		for q in sample(baked(curves[i], cx(curves[i], own))):
			centre += q
			cnt += 1
	centre /= maxf(1, cnt)
	op = {"kind": mode, "value": 1.0 if mode == "scale" else 0.0, "start": 0.0, "before": _state(), "pivot": centre,
		"axis": -1, "m0": ed._mouse, "orig": curves.duplicate(true), "own": own, "centre": centre, "n": Vector3.UP}
	typed = ""
	_op_update()
	_op_hint()


func _axis_dir(ax: int) -> Vector3:
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][ax]


## The move / turn / scale from the mouse at `at` (from where it was when it started).
func _xf_motion(at: Vector2) -> void:
	var mode: String = op["kind"]
	var mx := _mx()
	var pv: Vector3 = op["pivot"]
	var pw := mx * pv
	var ps: Vector2 = ed.view.project(pw)
	var m0: Vector2 = op["m0"]
	var ax: int = op.get("axis", -1)
	var free := Input.is_key_pressed(KEY_CTRL)
	match mode:
		"move":
			if ax >= 0:
				var dw: Vector3 = (mx.basis * _axis_dir(ax)).normalized()
				var d: float = (ed.view.on_line(at, pw, dw) - ed.view.on_line(m0, pw, dw)).dot(dw) / maxf(mx.basis.get_scale().x, 1e-6)
				op["value"] = d if free else snappedf(d, grid_step)
				op.erase("delta")
			else:
				# (over the plane facing the view, through the curves' middle)
				var dw: Vector3 = ed.view.on_view_plane(at, pw) - ed.view.on_view_plane(m0, pw)
				var d: Vector3 = mx.basis.inverse() * dw
				if not free:
					d = d.snapped(Vector3.ONE * grid_step)
				op["delta"] = d
				op["value"] = d.length()
		"turn":
			var a0 := (m0 - ps).angle()
			var a1 := (at - ps).angle()
			var deg := rad_to_deg(wrapf(a1 - a0, -PI, PI))
			op["value"] = deg if free else snappedf(deg, 15.0)
		"scale":
			var f := (at - ps).length() / maxf((m0 - ps).length(), 1.0)
			op["value"] = f if free else snappedf(f, 0.05)
	_op_update()
	_op_hint()


## The transform (model space, about the pivot) the operation makes now.
func _xf_now() -> Transform3D:
	var mode: String = op["kind"]
	var pv: Vector3 = op["pivot"]
	var ax: int = op.get("axis", -1)
	var v: float = op["value"]
	match mode:
		"move":
			var d: Vector3 = op["delta"] if op.has("delta") else _axis_dir(maxi(ax, 0)) * v
			return Transform3D(Basis(), d)
		"turn":
			# (about the axis, or the line of sight - turning the way the mouse goes round on screen)
			var dir: Vector3
			if ax >= 0:
				dir = _axis_dir(ax)
				var vz: Vector3 = _mx().basis.inverse() * ed.view.cam.global_basis.z
				if dir.dot(vz) < 0.0:
					dir = -dir
			else:
				dir = (_mx().basis.inverse() * ed.view.cam.global_basis.z).normalized()
			var b := Basis(dir.normalized(), deg_to_rad(-v))
			return Transform3D(b, pv - b * pv)
		"scale":
			var s := Vector3.ONE * v
			if ax >= 0:
				s = Vector3.ONE
				s[ax] = v
			var b := Basis.from_scale(s)
			return Transform3D(b, pv - b * pv)
	return Transform3D()


## The picked curves (from where they were) put through the operation's transform.
func _xf_apply() -> void:
	var t := _xf_now()
	var own: Dictionary = op.get("own", {})
	for i in sel:
		var c: Dictionary = curves[i]
		var x := cx(c, own)
		var xi := x.affine_inverse()
		var k: PackedVector3Array = (c["ctrl"] as PackedVector3Array).duplicate()
		for j in k.size():
			k[j] = xi * (t * (x * k[j]))
		c["ctrl"] = k
		var n: Vector3 = c.get("n", Vector3.UP)
		var nw: Vector3 = (x.basis * n)
		nw = (t.basis.inverse().transposed() * nw).normalized()
		c["n"] = (xi.basis * nw).normalized()
		if c.has("radii") and str(op["kind"]) == "scale" and int(op.get("axis", -1)) < 0:
			var r: PackedFloat32Array = (c["radii"] as PackedFloat32Array).duplicate()
			for j in r.size():
				r[j] *= absf(float(op["value"]))
			c["radii"] = r


## The solid an extrusion of height `v` cuts when negative: the one its middle is inside (else the one
## its box overlaps most) - op["target"].
func _neg_target(v: float) -> void:
	if not op.get("neg", false):
		op["target"] = null
		return
	var x := xf_of(op.get("x", []))
	var c: Vector3 = op["centre"]
	var n: Vector3 = op["n"]
	var mid := c + n * v * 0.5
	var t := part_containing(mid)
	if t == null:
		var m := _solid("extrude", v)
		if m:
			t = part_overlapping(x * m.get_aabb())
	op["target"] = t


## The visible part model-space point `pm` is inside (null: none) - a ray from it crosses its skin an
## odd number of times. `skip`: parts not to count.
func part_containing(pm: Vector3, skip := []) -> MeshInstance3D:
	var inv := _mx().affine_inverse()
	for p: MeshInstance3D in ed.parts():
		if p in skip or not p.visible or p.mesh == null:
			continue
		var lp: Vector3 = (inv * p.global_transform).affine_inverse() * pm
		if not p.mesh.get_aabb().grow(1e-4).has_point(lp):
			continue
		var tm := _tri_mesh(p)
		if tm == null:
			continue
		var d := Vector3(0.5773, 0.5774, 0.5772)
		var q := lp
		var hits := 0
		for i in 64:
			var h := tm.intersect_ray(q, d)
			if h.is_empty():
				break
			hits += 1
			q = (h["position"] as Vector3) + d * 1e-5
		if hits % 2 == 1:
			return p
	return null


## The visible part whose box (model space) overlaps `box` most (null: none).
func part_overlapping(box: AABB, skip := []) -> MeshInstance3D:
	var inv := _mx().affine_inverse()
	var best: MeshInstance3D = null
	var most := 0.0
	for p: MeshInstance3D in ed.parts():
		if p in skip or not p.visible or p.mesh == null:
			continue
		var pb: AABB = (inv * p.global_transform) * p.mesh.get_aabb()
		var i := pb.intersection(box)
		var vol := i.size.x * i.size.y * i.size.z
		if vol > most:
			most = vol
			best = p
	return best


func _tri_mesh(p: MeshInstance3D) -> TriangleMesh:
	var cache: Dictionary = get_meta("tri_cache", {})
	var k := p.mesh.get_instance_id()
	if not cache.has(k):
		if cache.size() > 32:
			cache.clear()
		cache[k] = p.mesh.generate_triangle_mesh()
		set_meta("tri_cache", cache)
	return cache[k]


## Solid `cutter` made negative: cut from `target` - a live subtraction when both are made from curves
## (`target` keeps the recipe "it minus the cutter", following both's curves; the cutter's part goes,
## its curves stay). One undo step (with the cutter's own: two).
func cut_from(cutter: MeshInstance3D, target: MeshInstance3D) -> bool:
	if cutter == null or target == null or cutter == target:
		return false
	var keep: bool = ed.shape_tools.keep_b
	ed.shape_tools.keep_b = false
	var ok: bool = ed.shape_tools.boolean("difference", target, cutter, true)
	ed.shape_tools.keep_b = keep
	return ok


const SOLID_ROLES := ["new", "difference", "union", "intersection"]


## The selected solid's role toward the solid it's in: "new" (a solid of its own - positive), or cut /
## join / common with it (a live boolean: the solid it's in keeps the recipe, its role switchable there).
func set_solid_role(i: int) -> void:
	var role: String = SOLID_ROLES[i]
	if role == "new":
		return
	var p: MeshInstance3D = ed.part
	if p == null or not p.has_meta("curve_solid"):
		return
	var inv := _mx().affine_inverse()
	var box: AABB = (inv * p.global_transform) * p.mesh.get_aabb()
	var t := part_containing(box.get_center(), [p])
	if t == null:
		t = part_overlapping(box, [p])
	if t == null:
		ed._say("%s isn't in another solid - nothing to %s." % [p.name, {"difference": "cut", "union": "join", "intersection": "share"}[role]])
		_refresh_panel()
		return
	var keep: bool = ed.shape_tools.keep_b
	ed.shape_tools.keep_b = false
	ed.shape_tools.boolean(role, t, p, true)
	ed.shape_tools.keep_b = keep


func _add_role() -> String:
	var o = _w("add_role")
	return ["difference", "union", "intersection"][(o as OptionButton).selected if o else 0]


## The selected solid's first extrusion height found in its recipe (else 0.5): a new tool's height.
static func _spec_height(spec: Dictionary) -> float:
	if str(spec.get("kind", "")) == "bool":
		return _spec_height(spec.get("a", {}))
	if str(spec.get("kind", "")) in ["extrude", "baked"]:
		return absf(float(spec.get("value", 0.5)))
	return 0.5


## The picked curves added to the selected solid as a new step (extruded both ways from their plane to
## the solid's height), cutting / joined / in common as the Add row says. One undo step.
func add_tool_curves(role := "") -> void:
	var p: MeshInstance3D = ed.part
	var spec := part_spec()
	if p == null or spec.is_empty():
		ed._say("Add: select a solid made from curves first (and pick the curves to add).")
		return
	if role == "":
		role = _add_role()
	var mine := spec_ids(spec)
	var ids := []
	for i in sel:
		var id := int(curves[i].get("id", -1))
		if not id in mine:
			ids.append(id)
	if ids.is_empty():
		ed._say("Add: pick the curves to add (curves this solid isn't made from).")
		return
	var own := owner_xfs()
	var cx0 := cx(curve_by_id(ids[0]), own)
	var inv := _mx().affine_inverse()
	var px: Transform3D = inv * p.global_transform
	var tool := {"kind": "extrude", "ids": ids, "value": _spec_height(spec), "both": true, "segs": segs, "axis": -1}
	var new := {"kind": "bool", "op": role, "a": spec, "b": tool, "b_xf": xf_arr(px.affine_inverse() * cx0)}
	set_recipe(new, {"difference": "Add a cut", "union": "Add a join", "intersection": "Add a common part"}[role])
	sel = []
	_refresh_panel()
	ed._say("%s: %d curve%s added as a %s - its height and role in the recipe." % [p.name, ids.size(), "" if ids.size() == 1 else "s", {"difference": "cut", "union": "join", "intersection": "common part"}[role]])


## The other selected solid added to the selected one as a new step (as the Add row says).
func add_tool_solid(role := "") -> void:
	var p: MeshInstance3D = ed.part
	if p == null:
		ed._say("Add: select the solid, then Ctrl+click the solid to add to it.")
		return
	var other: MeshInstance3D = null
	for q in ed.selected_parts():
		if q != p:
			other = q
	if other == null:
		ed._say("Add: Ctrl+click the other solid too (in the view or the overview) - the last one clicked is this one.")
		return
	if role == "":
		role = _add_role()
	var keep: bool = ed.shape_tools.keep_b
	ed.shape_tools.keep_b = false
	ed.shape_tools.boolean(role, p, other, true)
	ed.shape_tools.keep_b = keep


## The selected solid made negative: cut from the solid it's in (live, both made from curves).
func make_negative() -> void:
	var p: MeshInstance3D = ed.part
	if p == null or not p.has_meta("curve_solid"):
		ed._say("Negative: select a solid made from curves.")
		return
	var inv := _mx().affine_inverse()
	var box: AABB = (inv * p.global_transform) * p.mesh.get_aabb()
	var t := part_containing(box.get_center(), [p])
	if t == null:
		t = part_overlapping(box, [p])
	if t == null:
		ed._say("Negative: %s isn't in another solid - nothing to cut." % p.name)
		return
	cut_from(p, t)


## The latest cut of the selected solid made positive again: it gets back what it was before that cut,
## and the cutter its own part (where it was) - one undo step.
func make_positive() -> void:
	var p: MeshInstance3D = ed.part
	var spec := part_spec()
	if p == null or str(spec.get("kind", "")) != "bool" or str(spec.get("op", "")) != "difference":
		ed._say("Make the cut positive: select a solid with a cut in it.")
		return
	var a_spec: Dictionary = spec["a"]
	var b_spec: Dictionary = spec["b"]
	var ma := solid_of(a_spec)
	var mb := solid_of(b_spec)
	if ma == null or mb == null:
		ed._say("Make the cut positive: its curves are gone.")
		return
	var mat: Material = p.mesh.surface_get_material(0) if p.mesh.get_surface_count() > 0 else null
	ma.surface_set_material(0, mat if mat else MeshIO.default_material())
	mb.surface_set_material(0, MeshIO.default_material())
	var cutter := MeshInstance3D.new()
	cutter.mesh = mb
	cutter.name = ed._unique("Extrusion" if str(b_spec.get("kind", "")) == "extrude" else "Solid")
	cutter.transform = p.transform * xf_of(spec.get("b_xf", []))
	cutter.set_meta("curve_solid", b_spec)
	cutter.set_meta("curve_solid_key", _solid_key(b_spec))
	var old_mesh: Mesh = p.mesh
	var old_key: String = p.get_meta("curve_solid_key", "")
	var model: Node3D = ed.model
	var do_it := func():
		p.mesh = ma
		p.set_meta("curve_solid", a_spec)
		p.set_meta("curve_solid_key", _solid_key(a_spec))
		model.add_child(cutter)
		cutter.owner = model
		ed._fill_parts()
		ed.select_part(cutter)
	var undo_it := func():
		p.mesh = old_mesh
		p.set_meta("curve_solid", spec)
		p.set_meta("curve_solid_key", old_key)
		if cutter.get_parent():
			cutter.get_parent().remove_child(cutter)
		ed._fill_parts()
		ed.select_part(p)
	ed._do("Make the cut positive", do_it, undo_it, [cutter])
	ed._say("%s is a positive solid again (%s no longer cut by it)." % [cutter.name, p.name])


func begin_extrude() -> void:
	if not _need(1, "Extrude"):
		return
	_begin_op("extrude", 0.2)


func begin_offset() -> void:
	if not _need(1, "Offset"):
		return
	_begin_op("offset", 0.05)


func begin_fillet_corners() -> void:
	if not _need(1, "Fillet corners"):
		return
	for i in sel:
		if str(curves[i]["kind"]) == "line":
			_begin_op("fillet", 0.05)
			return
	ed._say("Fillet corners: select a line, rectangle or polygon (curves with corners).")


func begin_revolve() -> void:
	if not _need(1, "Revolve"):
		return
	_begin_op("revolve", 360.0)


func begin_pipe() -> void:
	if not _need(1, "Pipe"):
		return
	_begin_op("pipe", pipe_r)


func _begin_op(kind: String, value: float) -> void:
	stop()
	var x := cx(curves[sel[0]], owner_xfs())
	var c := baked(curves[sel[0]], x)
	var centre := Vector3.ZERO
	var s := sample(c)
	for q in s:
		centre += q
	centre /= maxf(1, s.size())
	op = {"kind": kind, "value": value, "start": value, "before": _state(), "centre": centre, "x": xf_arr(x),
		"n": (c.get("n", Vector3.UP) as Vector3).normalized(), "m0": ed._mouse, "orig": curves.duplicate(true)}
	typed = ""
	_op_update()
	_op_hint()


func _op_hint() -> void:
	if str(op.get("kind", "")) in ["move", "turn", "scale"]:
		var ax: int = op.get("axis", -1)
		var what: String = {"move": "Move curves: %.3f m", "turn": "Turn curves: %.1f°", "scale": "Scale curves: x%.3f"}[op["kind"]] % op["value"]
		ed.view.hint = what + ("  along " + "XYZ"[ax] if ax >= 0 and op["kind"] != "turn" else ("  about " + "XYZ"[ax] if ax >= 0 else "")) \
			+ "   (X / Y / Z: an axis · type a number · Ctrl: no snapping · click or Enter: done · Esc: cancel)" + (("   typed: " + typed) if typed != "" else "")
		ed.view.queue_redraw()
		return
	if str(op.get("kind", "")) == "extrude":
		var t = op.get("target")
		var cut := ""
		if op.get("neg", false):
			cut = "   NEGATIVE: cuts %s (N: positive)" % (t.name if t and is_instance_valid(t) else "nothing here - it's in no solid")
		else:
			cut = "   positive (N: negative - cut it from the solid it's in)"
		ed.view.hint = "Extrude: %.3f m%s   (mouse / type a number · click or Enter: done · Esc: cancel)%s" % [op["value"], cut, ("   typed: " + typed) if typed != "" else ""]
		ed.view.queue_redraw()
		return
	var names := {"extrude": "Extrude: %.3f m", "offset": "Offset: %.3f m", "fillet": "Fillet corners: radius %.3f m", "revolve": "Revolve: %.0f°", "pipe": "Pipe: radius %.3f m"}
	ed.view.hint = (names[op["kind"]] % op["value"]) + "   (mouse / type a number · click or Enter: done · Esc: cancel)" + (("   typed: " + typed) if typed != "" else "")
	ed.view.queue_redraw()


func _op_motion(at: Vector2) -> void:
	if typed != "":
		return
	if str(op.get("kind", "")) in ["move", "turn", "scale"]:
		_xf_motion(at)
		return
	var kind: String = op["kind"]
	var mx := _mx()
	var c: Vector3 = mx * (op["centre"] as Vector3)
	var a: Vector2 = ed.view.project(c)
	var m0: Vector2 = op["m0"]
	match kind:
		"extrude":
			# (along the curve's normal: how far the mouse went along the normal's line on screen)
			var hit: Vector3 = ed.view.on_line(at, c, (mx.basis * (op["n"] as Vector3)).normalized())
			op["value"] = snappedf((hit - c).dot((mx.basis * (op["n"] as Vector3)).normalized()), grid_step if snap_grid and not Input.is_key_pressed(KEY_CTRL) else 0.0)
		"revolve":
			# (from a whole turn: the mouse to the left takes degrees off - a degree a pixel, by 15°; Ctrl: by 1°)
			op["value"] = clampf(snappedf(360.0 + (at.x - m0.x), 1.0 if Input.is_key_pressed(KEY_CTRL) else 15.0), 1.0, 360.0)
		_:
			var d0 := a.distance_to(m0)
			var d1 := a.distance_to(at)
			var px_m: float = maxf(ed.view.project(c + ed.view.cam.global_basis.x * 1.0).distance_to(a), 1.0)
			var v: float = op["start"] + (d1 - d0) / px_m
			if kind == "pipe" or kind == "fillet":
				v = maxf(v, 0.001)
			op["value"] = snappedf(v, 0.005 if not Input.is_key_pressed(KEY_CTRL) else 0.0)
	_op_update()
	_op_hint()


## The operation's preview: curves changed in place; solids shown as a preview part.
func _op_update() -> void:
	var kind: String = op["kind"]
	var v: float = op["value"]
	curves = op["orig"].duplicate(true)
	if kind in ["move", "turn", "scale"]:
		_xf_apply()
		refresh_solids()
		layer.queue_redraw()
		return
	match kind:
		"offset":
			var made := []
			var nid := _nid()
			var own := owner_xfs()
			for i in sel:
				var oc := offset(baked(curves[i], cx(curves[i], own)), v)
				oc["id"] = nid
				nid += 1
				curves.append(oc)
				made.append(curves.size() - 1)
			op["made"] = made
		"fillet":
			for i in sel:
				var c: Dictionary = curves[i]
				if str(c["kind"]) == "line":
					var r := PackedFloat32Array()
					r.resize((c["ctrl"] as PackedVector3Array).size())
					r.fill(v)
					c["radii"] = r
		_:
			if kind == "extrude":
				_neg_target(v)
			_show_preview(_solid(kind, v))
	if kind in ["fillet", "offset"]:
		refresh_solids()
	layer.queue_redraw()


func confirm_op() -> void:
	if op.is_empty():
		return
	var neg := bool(op.get("neg", false))   # (an extrusion made negative: it cuts this solid)
	var target = op.get("target") if neg else null
	var kind: String = op["kind"]
	var v: float = op["value"]
	var before: Array = op["before"]
	_clear_preview()
	op = {}
	ed.view.hint = ""
	ed.view.queue_redraw()
	match kind:
		"move", "turn", "scale":
			_changed({"move": "Move curves", "turn": "Turn curves", "scale": "Scale curves"}[kind], before)
		"offset":
			_set_nid(_nid() + sel.size())
			_changed("Offset curve", before)
		"fillet":
			_changed("Fillet corners", before)
		_:
			curves = before[0].duplicate(true)
			if kind == "pipe":
				pipe_r = v
			var made := make_part(kind, v)
			if made and neg and target and is_instance_valid(target):
				cut_from(made, target)


func cancel_op() -> void:
	if op.is_empty():
		return
	curves = op["before"][0].duplicate(true)
	sel = op["before"][1].duplicate()
	refresh_solids()
	_clear_preview()
	op = {}
	typed = ""
	ed.view.hint = ""
	ed.view.queue_redraw()
	layer.queue_redraw()


func _show_preview(m: ArrayMesh) -> void:
	if _preview == null or not is_instance_valid(_preview):
		_preview = MeshInstance3D.new()
		_preview.name = "CurvePreview"
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.72, 0.38, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_preview.material_override = mat
		ed.view.world.add_child(_preview)
	# (a negative solid - it cuts: red)
	(_preview.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.25, 0.2, 0.55) if op.get("neg", false) else Color(1.0, 0.72, 0.38, 0.55)
	_preview.global_transform = _mx() * xf_of(op.get("x", []))
	_preview.mesh = m
	ed.view.request()


func _clear_preview() -> void:
	if _preview and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	ed.view.request()


# --- solids from curves ----------------------------------------------------------------------

## The solid `kind` makes of the selected curves with value `v` (null: it can't).
func _solid(kind: String, v: float) -> ArrayMesh:
	return solid_of(spec_of(kind, v))


## The recipe for solid `kind` of the selected curves: {kind, ids, value, segs, axis}.
func spec_of(kind: String, v: float) -> Dictionary:
	var ids := []
	var axis := -1
	for i in sel:
		var c: Dictionary = curves[i]
		# (a revolve's axis: a straight two-point line picked with the profile)
		if kind == "revolve" and axis < 0 and sel.size() > 1 and str(c["kind"]) == "line" and (c["ctrl"] as PackedVector3Array).size() == 2:
			axis = int(c.get("id", -1))
			continue
		ids.append(int(c.get("id", -1)))
	return {"kind": kind, "ids": ids, "value": v, "segs": segs, "axis": axis}


## The mesh recipe `spec` makes of the curves as they are now (null: it can't - a curve gone...).
func solid_of(spec: Dictionary) -> ArrayMesh:
	if str(spec.get("kind", "")) == "bool":
		# (a live boolean: both solids made from their curves, then A op B - B where it was in A)
		var ma := solid_of(spec.get("a", {}))
		var mb := solid_of(spec.get("b", {}))
		if ma == null or mb == null:
			return null
		var MB: GDScript = load("res://scripts/editor/mesh/mesh_bool.gd")
		var r: Dictionary = MB.run(ma, mb, xf_of(spec.get("b_xf", [])), str(spec.get("op", "difference")))
		var ms: Array = r.get("meshes", [])
		return auto_smooth(ms[ms.size() - 1]) if str(r.get("error", "")) == "" and not ms.is_empty() else null
	var cs := curves_of(spec.get("ids", []))
	if cs.is_empty():
		return null
	var v := float(spec.get("value", 0.0))
	if str(spec.get("kind", "")) == "baked":
		return edge_mesh(spec) if spec.has("pieces") else baked_mesh(spec, cs)
	if str(spec.get("kind", "")) == "extrude":
		return _extrude_step(spec, cs, v)
	if str(spec.get("kind", "")) == "fill" and spec.get("roles") is Dictionary and cs.size() >= 2:
		cs = combined(cs, spec["roles"])
		if cs.is_empty():
			return null
	match str(spec.get("kind", "")):
		"revolve":
			var ax := curve_by_id(int(spec.get("axis", -1)))
			var axis: Array
			if not ax.is_empty() and (ax["ctrl"] as PackedVector3Array).size() >= 2:
				var k: PackedVector3Array = ax["ctrl"]
				axis = [k[0], (k[k.size() - 1] - k[0]).normalized(), -1]
			else:
				axis = default_axis(cs[0])
			return revolve_mesh(cs, deg_to_rad(v), int(spec.get("segs", segs)), axis)
		"pipe": return pipe_mesh(cs, v, 16)
		"loft": return loft_mesh(cs)
		"sweep": return sweep_mesh(cs[0], cs[1]) if cs.size() >= 2 else null
		"fill": return fill_mesh(cs)
	return null


## A baked solid made from its edges: each piece (pieces: [{role: add|cut, loops: [[bottom id, top id],
## ...]}] - the first loop its outline, the others holes in it) the solid between its bottom and top
## edge curves - walls from each point of the bottom edge to the same point of the top one, the ends
## filled; the adds joined, the cuts (made a hair longer each way: they cut cleanly through the faces
## they open from) taken out. Move a point of an edge and only that edge moves.
func edge_mesh(spec: Dictionary) -> ArrayMesh:
	var adds := []
	var cuts := []
	for pc: Dictionary in spec.get("pieces", []):
		var loops := []
		for pair in pc.get("loops", []):
			var b := curve_by_id(int(pair[0]))
			var t := curve_by_id(int(pair[1]))
			if b.is_empty() or t.is_empty():
				return null
			loops.append([b, t])
		var m := loft_piece(loops, 1e-3 if str(pc.get("role", "add")) == "cut" else 0.0)
		if m:
			(cuts if str(pc.get("role", "add")) == "cut" else adds).append(m)
	if adds.is_empty():
		return null
	var MB: GDScript = load("res://scripts/editor/mesh/mesh_bool.gd")
	var m: ArrayMesh = adds[0]
	for i in range(1, adds.size()):
		var r: Dictionary = MB.run(m, adds[i], Transform3D(), "union")
		var ms: Array = r.get("meshes", [])
		if str(r.get("error", "")) == "" and not ms.is_empty():
			m = ms[ms.size() - 1]
	for k in cuts:
		var r: Dictionary = MB.run(m, k, Transform3D(), "difference")
		var ms: Array = r.get("meshes", [])
		if str(r.get("error", "")) == "" and not ms.is_empty():
			m = ms[ms.size() - 1]
	return auto_smooth(m) if adds.size() > 1 or not cuts.is_empty() else m


## The solid between edge loops: loops [[bottom curve, top curve]...] (the first the outline, the rest
## holes); `ext`: each end pushed out that much further (a cutter's).
static func loft_piece(loops: Array, ext := 0.0) -> ArrayMesh:
	if loops.is_empty():
		return null
	var b := Shapes.B.new()
	var rings := []   # [bottom points, top points] each loop, matched point for point
	for L in loops:
		var sb := sample(L[0])
		var st := sample(L[1])
		if sb.size() < 3 or st.size() < 3:
			return null
		var m := maxi(sb.size(), st.size())
		if sb.size() != m:
			sb = _resample_loop(sb, m)
		if st.size() != m:
			st = _resample_loop(st, m)
		rings.append([sb, _matched(sb, st, (L[0].get("n", Vector3.UP) as Vector3).normalized())])
	var up := (_middle(rings[0][1]) - _middle(rings[0][0]))
	var n: Vector3 = (loops[0][0].get("n", Vector3.UP) as Vector3).normalized()
	if up.dot(n) < 0.0:
		n = -n
	if ext > 0.0:
		for r in rings:
			var lb: PackedVector3Array = r[0]
			var lt: PackedVector3Array = r[1]
			for i in lb.size():
				lb[i] -= n * ext
				lt[i] += n * ext
			r[0] = lb
			r[1] = lt
	var outer_b: PackedVector3Array
	var outer_t: PackedVector3Array
	var holes_b := []
	var holes_t := []
	for li in rings.size():
		var sb: PackedVector3Array = rings[li][0]
		var st: PackedVector3Array = rings[li][1]
		var hole := li > 0
		if (_winding(sb, n) < 0.0) != hole:   # (the outline turning left about up, its holes right: walls face out)
			sb.reverse()
			st.reverse()
		var P := []
		for i in sb.size():
			P.append(PackedVector3Array([sb[i], st[i]]))
		P.append(P[0])
		b.sheet(P, _creases(sb, true), PackedInt32Array(), true)
		if hole:
			holes_b.append(sb)
			holes_t.append(st)
		else:
			outer_b = sb
			outer_t = st
	var u := (outer_b[1] - outer_b[0]).normalized()
	cap(b, keyhole(outer_b, holes_b), -n, u)
	cap(b, keyhole(outer_t, holes_t), n, u)
	return _commit(b, true)


## Top loop `st` matched to bottom loop `sb` point for point: going round the same way, starting where
## it lines up best (each wall runs straight up, not twisted - however the two curves were drawn).
static func _matched(sb: PackedVector3Array, st: PackedVector3Array, n: Vector3) -> PackedVector3Array:
	var out := st.duplicate()
	if (_winding(sb, n) < 0.0) != (_winding(out, n) < 0.0):
		out.reverse()
	var m := out.size()
	var cb := _middle(sb)
	var ct := _middle(out)
	var best := 0
	var best_d := INF
	for off in m:
		var d := 0.0
		for i in m:
			var a := sb[i] - cb
			var b := out[(i + off) % m] - ct
			d += (a - n * a.dot(n)).distance_squared_to(b - n * b.dot(n))
			if d >= best_d:
				break
		if d < best_d:
			best_d = d
			best = off
	var r := PackedVector3Array()
	for i in m:
		r.append(out[(i + best) % m])
	return r


## A closed loop of points resampled to `m` points spread evenly along it.
static func _resample_loop(s: PackedVector3Array, m: int) -> PackedVector3Array:
	var lens := PackedFloat32Array([0.0])
	for i in s.size():
		lens.append(lens[i] + s[i].distance_to(s[(i + 1) % s.size()]))
	var total := lens[lens.size() - 1]
	var out := PackedVector3Array()
	var k := 0
	for j in m:
		var d := total * j / m
		while k < s.size() - 1 and lens[k + 1] < d:
			k += 1
		var w := (d - lens[k]) / maxf(lens[k + 1] - lens[k], 1e-9)
		out.append(s[k].lerp(s[(k + 1) % s.size()], w))
	return out


## A baked solid's mesh: its curves at their levels (each curve's plane up its height; outlines
## adding, holes - "cut" - taking away), the levels stacked: each level's walls, and its floor and
## roof only where the level below / above doesn't cover it - one closed solid, no booleans.
static func baked_mesh(spec: Dictionary, cs: Array) -> ArrayMesh:
	if cs.is_empty():
		return null
	var n: Vector3 = (cs[0].get("n", Vector3.UP) as Vector3).normalized()
	var u := _any_perp(n)
	var v := n.cross(u)
	var roles: Dictionary = spec.get("roles", {}) if spec.get("roles") is Dictionary else {}
	var per: Dictionary = spec.get("per", {}) if spec.get("per") is Dictionary else {}
	var prs := []   # each curve: its outline, the heights it spans, adds or cuts
	for c: Dictionary in cs:
		var s := sample(c)
		if s.size() < 3 or not c.get("closed", false):
			continue
		var f := PackedVector2Array()
		var off := PackedFloat32Array()   # (each point's height off the curve's plane - a point lifted or lowered)
		var s0 := _plane_height(s, n)
		for q in s:
			f.append(Vector2(q.dot(u), q.dot(v)))
			off.append(q.dot(n) - s0)
		if Geometry2D.is_polygon_clockwise(f):
			f.reverse()
			off.reverse()
		var id := str(int(c.get("id", -1)))
		var h := float((per.get(id, {}) as Dictionary).get("value", spec.get("value", 0.0)))
		if absf(h) < 1e-6:
			continue
		prs.append({"f": f, "off": off, "lo": minf(s0, s0 + h), "hi": maxf(s0, s0 + h), "cut": str(roles.get(id, "add")) == "cut"})
	# the levels: between each two heights where one starts or ends (the same curves at work: one level)
	var hs := []
	for pr: Dictionary in prs:
		for t in [pr["lo"], pr["hi"]]:
			if not hs.any(func(q): return absf(q - t) < 1e-6):
				hs.append(t)
	hs.sort()
	var levels := []
	for i in range(hs.size() - 1):
		var mid := (float(hs[i]) + float(hs[i + 1])) * 0.5
		var key := []
		for k in prs.size():
			if prs[k]["lo"] < mid and mid < prs[k]["hi"]:
				key.append(k)
		if not levels.is_empty() and levels.back()["key"] == key:
			levels.back()["hi"] = hs[i + 1]
			continue
		levels.append({"lo": hs[i], "hi": hs[i + 1], "key": key})
	for L: Dictionary in levels:
		var adds := []
		var cuts := []
		for k in L["key"]:
			(cuts if prs[k]["cut"] else adds).append({"o": prs[k]["f"], "h": []})
		L["r"] = _rs_sub(_rs_union([], adds), cuts)
	levels = levels.filter(func(L): return not (L["r"] as Array).is_empty())
	var b := Shapes.B.new()
	var to3 := func(f: PackedVector2Array, t: float) -> PackedVector3Array:
		var o := PackedVector3Array()
		for q in f:
			o.append(u * q.x + v * q.y + n * t)
		return o
	for i in levels.size():
		var L: Dictionary = levels[i]
		var lo: float = L["lo"]
		var hi: float = L["hi"]
		var h := hi - lo
		for r: Dictionary in L["r"]:   # (walls: the outline facing out, its holes in)
			var loops: Array = [[to3.call(r["o"], lo), false]]
			for hl in r["h"]:
				loops.append([to3.call(hl, lo), true])
			for lp in loops:
				var loop: PackedVector3Array = lp[0]
				if (_winding(loop, n) < 0.0) != bool(lp[1]):
					loop.reverse()
				var P := []
				for q in loop:
					P.append(PackedVector3Array([q, q + n * h]))
				P.append(P[0])
				b.sheet(P, _creases(loop, true), PackedInt32Array(), true)
		var below: Array = levels[i - 1]["r"] if i > 0 and absf(float(levels[i - 1]["hi"]) - lo) < 1e-5 else []
		var above: Array = levels[i + 1]["r"] if i + 1 < levels.size() and absf(float(levels[i + 1]["lo"]) - hi) < 1e-5 else []
		for side in [[_rs_sub(L["r"], below), lo, -n], [_rs_sub(L["r"], above), hi, n]]:
			for r: Dictionary in side[0]:
				var outer: PackedVector3Array = to3.call(r["o"], side[1])
				if _winding(outer, n) < 0.0:
					outer.reverse()
				var holes := []
				for hl in r["h"]:
					var h3: PackedVector3Array = to3.call(hl, side[1])
					if _winding(h3, n) > 0.0:
						h3.reverse()
					holes.append(h3)
				cap(b, keyhole(outer, holes), side[2], u)
	var m := _commit(b, true)
	var lifted := false
	for pr: Dictionary in prs:
		for o in (pr["off"] as PackedFloat32Array):
			if absf(o) > 1e-6:
				lifted = true
	return _lifted(m, prs, n, u, v) if m != null and lifted else m


## The curve's height on its plane (most of its points': one point lifted doesn't move the plane).
static func _plane_height(s: PackedVector3Array, n: Vector3) -> float:
	var hs := []
	for q in s:
		hs.append(q.dot(n))
	hs.sort()
	return hs[hs.size() / 2]


## A baked solid's mesh with its curves' lifted points: every point of it on a curve's edge (in the
## heights that curve's extrusion spans) moved up / down as much as the curve is there - its walls
## follow the point, the faces beside it tilt to meet it. Shaded again.
static func _lifted(m: ArrayMesh, prs: Array, n: Vector3, u: Vector3, v: Vector3) -> ArrayMesh:
	var a := m.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in vs.size():
		var q := vs[i]
		var p2 := Vector2(q.dot(u), q.dot(v))
		var t := q.dot(n)
		var best := 1e-4
		var lift := 0.0
		for pr: Dictionary in prs:
			if t < float(pr["lo"]) - 1e-5 or t > float(pr["hi"]) + 1e-5:
				continue
			var f: PackedVector2Array = pr["f"]
			var off: PackedFloat32Array = pr["off"]
			for k in f.size():
				var a2 := f[k]
				var b2 := f[(k + 1) % f.size()]
				var c2 := Geometry2D.get_closest_point_to_segment(p2, a2, b2)
				var d := c2.distance_to(p2)
				if d < best:
					best = d
					var w := c2.distance_to(a2) / maxf(a2.distance_to(b2), 1e-9)
					lift = lerpf(off[k], off[(k + 1) % f.size()], w)
		if lift != 0.0:
			vs[i] = q + n * lift
	a[Mesh.ARRAY_VERTEX] = vs
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	out.surface_set_material(0, m.surface_get_material(0))
	return auto_smooth(out)



## Curves `cs` combined by their roles (curve id -> "add" / "cut"; add if not given) into the outlines
## (and holes) they make together: the added ones joined, the cut ones taken away - on the first added
## one's plane. (An extrusion or fill with roles: one clean solid, made again from them live.)
static func combined(cs: Array, roles: Dictionary) -> Array:
	var adds := []
	var cuts := []
	for c in cs:
		if str(roles.get(str(int(c.get("id", -1))), "add")) == "cut":
			cuts.append(c)
		else:
			adds.append(c)
	if adds.is_empty():
		return []
	if adds.size() == 1 and cuts.is_empty():
		return adds
	var ops := ["union"]
	for i in range(1, adds.size()):
		ops.append("union")
	for i in cuts.size():
		ops.append("subtract")
	return curve_bool(adds + cuts, "union", ops)


## An extrusion step: the curves sharing its height combined by their roles (in 2D) and extruded; each
## curve with a height of its own ("per": {id: {value, both}}) extruded alone and joined to it / cut from
## it (a 3D boolean, made again live) - a cut curve can be a shallow pocket or go right through.
func _extrude_step(spec: Dictionary, cs: Array, v: float) -> ArrayMesh:
	var roles: Dictionary = spec.get("roles", {}) if spec.get("roles") is Dictionary else {}
	var per: Dictionary = spec.get("per", {}) if spec.get("per") is Dictionary else {}
	var both := bool(spec.get("both", false))
	if per.is_empty():
		# (one height for all: worked out in 2D - the cleanest solid)
		var flat := combined(cs, roles) if not roles.is_empty() and cs.size() >= 2 else cs
		return _ext(flat, v, both) if not flat.is_empty() else null
	# Heights of their own: everything that adds first, then everything that cuts - in that order,
	# whatever height each has (an added curve never fills a cut back in).
	var add_same := []
	var cut_same := []
	var add_own := []
	var cut_own := []
	for c in cs:
		var id := str(int(c.get("id", -1)))
		var cut := str(roles.get(id, "add")) == "cut"
		if per.has(id):
			(cut_own if cut else add_own).append(c)
		else:
			(cut_same if cut else add_same).append(c)
	var adds := []   # meshes
	if not add_same.is_empty():
		adds.append(_ext(_joined(add_same), v, both))
	for c in add_own:
		var o: Dictionary = per[str(int(c.get("id", -1)))]
		adds.append(_ext([c], float(o.get("value", v)), bool(o.get("both", both))))
	var cuts := []
	if not cut_same.is_empty():
		cuts.append(_ext(_joined(cut_same), v, both))
	for c in cut_own:
		var o: Dictionary = per[str(int(c.get("id", -1)))]
		cuts.append(_ext([c], float(o.get("value", v)), bool(o.get("both", both))))
	var MB: GDScript = load("res://scripts/editor/mesh/mesh_bool.gd")
	var m: ArrayMesh = null
	for a in adds:
		if a == null:
			continue
		if m == null:
			m = a
			continue
		var r: Dictionary = MB.run(m, a, Transform3D(), "union")
		var ms: Array = r.get("meshes", [])
		if str(r.get("error", "")) == "" and not ms.is_empty():
			m = ms[ms.size() - 1]
	if m == null:
		return null
	for k in cuts:
		if k == null:
			continue
		var r: Dictionary = MB.run(m, k, Transform3D(), "difference")
		var ms: Array = r.get("meshes", [])
		if str(r.get("error", "")) == "" and not ms.is_empty():
			m = ms[ms.size() - 1]
	return auto_smooth(m) if (adds.size() > 1 or not cuts.is_empty()) else m


## Curves joined into the outlines they make together (overlapping ones as one, so their extrusion is a
## clean solid); one curve as it is.
static func _joined(cs: Array) -> Array:
	if cs.size() < 2:
		return cs
	var j := combined(cs, {})
	return j if not j.is_empty() else cs


## A boolean's mesh shaded again (its faces come out lit flat - a round wall faceted): faces meeting at
## under `deg` share their normals (smooth), sharper edges stay crisp. Each surface kept (its material).
static func auto_smooth(m: ArrayMesh, deg := 35.0) -> ArrayMesh:
	if m == null:
		return null
	var lim := cos(deg_to_rad(deg))
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var tn := PackedVector3Array()   # each triangle's normal
		var ang := PackedFloat32Array()   # each triangle's angle at each corner
		var at := {}   # position -> its triangles' corners (triangle * 3 + corner)
		for t in range(0, ix.size(), 3):
			var p0 := v[ix[t]]
			var p1 := v[ix[t + 1]]
			var p2 := v[ix[t + 2]]
			tn.append((p2 - p0).cross(p1 - p0).normalized())   # (Godot's clockwise fronts: this points out)
			var ps := [p0, p1, p2]
			for k in 3:
				var e1: Vector3 = ps[(k + 1) % 3] - ps[k]
				var e2: Vector3 = ps[(k + 2) % 3] - ps[k]
				ang.append(e1.angle_to(e2) if e1.length() > 1e-12 and e2.length() > 1e-12 else 0.0)
				var key := Vector3i((v[ix[t + k]] * 1e5).round())
				if not at.has(key):
					at[key] = PackedInt32Array()
				(at[key] as PackedInt32Array).append(t + k)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in range(0, ix.size(), 3):
			var own := tn[t / 3]
			for k in 3:
				var key := Vector3i((v[ix[t + k]] * 1e5).round())
				var n := Vector3.ZERO
				for o in (at[key] as PackedInt32Array):
					# (each face at this point counted by its angle there - a long thin sliver, its
					# corner a sliver of an angle, hardly at all - if it's near enough this face)
					var fo := tn[o / 3]
					if fo.dot(own) >= lim:
						n += fo * ang[o]
				st.set_normal(n.normalized() if n.length() > 1e-12 else own)
				if not uv.is_empty():
					st.set_uv(uv[ix[t + k]])
				st.add_vertex(v[ix[t + k]])
		st.index()
		if not uv.is_empty():
			st.generate_tangents()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		out.surface_set_material(out.get_surface_count() - 1, m.surface_get_material(si))
	return out


## Curves extruded `v` (both ways: half each side of their plane).
static func _ext(cs: Array, v: float, both: bool) -> ArrayMesh:
	if both:
		var mid := []
		for c in cs:
			var n: Vector3 = (c.get("n", Vector3.UP) as Vector3).normalized()
			mid.append(baked(c, Transform3D(Basis(), -n * v * 0.5)))
		return extrude_mesh(mid, v)
	return extrude_mesh(cs, v)


## The axis a profile revolves about with no axis line picked: the model's Y through the origin -
## or, for a curve drawn flat on the ground, the X line at its height.
static func default_axis(c: Dictionary) -> Array:
	var n: Vector3 = c.get("n", Vector3.UP)
	if absf(n.normalized().dot(Vector3.UP)) > 0.9:
		var k0: Vector3 = (c["ctrl"] as PackedVector3Array)[0]
		return [Vector3(0, k0.y, 0), Vector3.RIGHT, -1]
	return [Vector3.ZERO, Vector3.UP, -1]


## What a solid's mesh is made from, as text (the same text: no need to make it again).
func _solid_key(spec: Dictionary) -> String:
	if str(spec.get("kind", "")) == "edges":
		return "edges %d %d %d %s" % [int(spec.get("net", 0)), (spec.get("faces", []) as Array).size(), (spec.get("mesh", {}).get("v", []) as Array).size(), JSON.stringify(to_json(curves_of(spec.get("ids", []))))]
	var cs := []
	for id in spec_ids(spec):
		var c := curve_by_id(int(id))
		if not c.is_empty():
			cs.append(c)
	return JSON.stringify([spec, to_json(cs)])


## Every curve id recipe `spec` uses (a live boolean's: both sides').
static func spec_ids(spec: Dictionary) -> Array:
	if str(spec.get("kind", "")) == "bool":
		return spec_ids(spec.get("a", {})) + spec_ids(spec.get("b", {}))
	var out: Array = (spec.get("ids", []) as Array).duplicate()
	if int(spec.get("axis", -1)) >= 0:
		out.append(spec["axis"])
	return out


## Every procedural part made again whose curves or recipe changed (a part being edited in edit mode,
## or one whose curves are gone, is left as it is).
func refresh_solids() -> void:
	if ed == null or ed.model == null:
		return
	var any := false
	var now := Time.get_ticks_msec()
	for p: MeshInstance3D in ed.parts():
		if not p.has_meta("curve_solid") or (ed.mode == "edit" and p == ed.part):
			continue
		var spec: Dictionary = p.get_meta("curve_solid")
		var key := _solid_key(spec)
		if key == str(p.get_meta("curve_solid_key", "")):
			continue
		# (made again at once, live booleans too - no waiting while a curve's dragged)
		var m := edge_solid(p, spec) if str(spec.get("kind", "")) == "edges" else solid_of(spec)
		if m == null:
			continue
		# (each surface keeps its material - a boolean's B faces theirs)
		for si in m.get_surface_count():
			var mat: Material = null
			if p.mesh and p.mesh.get_surface_count() > 0:
				mat = p.mesh.surface_get_material(mini(si, p.mesh.get_surface_count() - 1))
			m.surface_set_material(si, mat if mat else MeshIO.default_material())
		p.mesh = m
		p.set_meta("curve_solid_key", key)
		any = true
	if any:
		_vertex_key = -1
		ed._outline_part()
		ed.show_stats()
		ed.view.request()


## Makes the solid as a new part (one undo step).
func make_part(kind: String, v := 0.0) -> MeshInstance3D:
	if sel.is_empty():
		_need(1, kind.capitalize())
		return null
	var spec := spec_of(kind, v)
	var m := solid_of(spec)
	if m == null or m.get_surface_count() == 0:
		var why := {"loft": "Loft: select two or more curves, in the order to go through.", "sweep": "Sweep: select the profile (a closed curve) first, then the path.",
			"fill": "Fill: select closed curves.", "extrude": "Extrude: select curves (closed ones make solids).", "revolve": "Revolve: select a profile (and a two-point line as the axis, if not the model's Y)."}
		ed._say(why.get(kind, "%s: that didn't make anything." % kind.capitalize()))
		return null
	# (placed where its curves are: the part their first one belongs to, if it's been moved)
	return add_part(m, {"extrude": "Extrusion", "revolve": "Revolve", "pipe": "Pipe", "loft": "Loft", "sweep": "Sweep", "fill": "Fill"}.get(kind, "Solid"), spec, cx(curves[sel[0]], owner_xfs()))


func add_part(m: ArrayMesh, base: String, spec := {}, place := Transform3D()) -> MeshInstance3D:
	if ed.mode == "edit":
		ed._leave_edit(true)
	if ed.model == null:
		ed.new_model(true)
	m.surface_set_material(0, MeshIO.default_material())
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.name = ed._unique(base)
	mi.transform = place
	if not spec.is_empty():
		mi.set_meta("curve_solid", spec)   # (procedural: made again when its curves change)
		mi.set_meta("curve_solid_key", _solid_key(spec))
	var model: Node3D = ed.model
	# (into the part (group) the selected solid's in, if any - placed as it would be in the model)
	var home: Node3D = group_of(ed.part) if ed.part and is_instance_valid(ed.part) else null
	if home:
		mi.transform = ((model.global_transform.affine_inverse() * home.global_transform).affine_inverse()) * place
	var holder: Node3D = home if home else model
	var add := func():
		holder.add_child(mi)
		mi.owner = model
		ed._bind_new(mi)
		ed._fill_parts()
		ed.select_part(mi)
	var remove := func():
		holder.remove_child(mi)
		if ed.part == mi:
			ed.part = null
		ed._fill_parts()
		ed._show_part()
		ed._update_ui()
		ed.view.request()
	ed._do(base, add, remove, [mi])
	_vertex_key = -1
	ed._say("%s made: a new part (%d triangles)." % [base, m.surface_get_array_index_len(0) / 3])
	return mi


## A builder's mesh, turned outward (a closed one by its volume's sign).
static func _commit(b: Shapes.B, closed: bool) -> ArrayMesh:
	if b.idx.is_empty():
		return null
	if closed:
		var vol := 0.0
		for t in range(0, b.idx.size(), 3):
			vol += b.v[b.idx[t]].dot(b.v[b.idx[t + 1]].cross(b.v[b.idx[t + 2]]))
		if vol < 0.0:
			for t in range(0, b.idx.size(), 3):
				var x := b.idx[t + 1]
				b.idx[t + 1] = b.idx[t + 2]
				b.idx[t + 2] = x
			for i in b.n.size():
				b.n[i] = -b.n[i]
	var a := b.commit()
	if a.is_empty():
		return null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## Corners sharper than 35° in a loop of points (their indices): they crease.
static func _creases(s: PackedVector3Array, closed: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	var m := s.size()
	for k in m:
		if not closed and (k == 0 or k == m - 1):
			continue
		var a := (s[k] - s[(k - 1 + m) % m]).normalized()
		var b := (s[(k + 1) % m] - s[k]).normalized()
		if a.dot(b) < cos(deg_to_rad(35.0)):
			out.append(k)
	return out


## Each curve pushed `h` along its plane's normal: a closed one a capped solid, an open one a wall.
static func extrude_mesh(cs: Array, h: float) -> ArrayMesh:
	if absf(h) < 1e-5:
		return null
	var b := Shapes.B.new()
	var all_closed := true
	var closed_cs := []
	for c in cs:
		if c.get("closed", false):
			closed_cs.append(c)
			continue
		all_closed = false
		var s := sample(c)   # (an open curve: a wall)
		if s.size() < 2:
			continue
		var n: Vector3 = (c.get("n", Vector3.UP) as Vector3).normalized()
		var P := []
		for q in s:
			P.append(PackedVector3Array([q, q + n * h]))
		b.sheet(P, _creases(s, false), PackedInt32Array(), false)
	for r in regions(closed_cs):
		var n: Vector3 = r["n"]
		var outer: PackedVector3Array = r["s"]
		# (the outline turning left about the way it's pushed, its holes right: every wall faces out of
		# the solid, as the caps do)
		if _winding(outer, n) * h < 0.0:
			outer.reverse()
		var holes := []
		for hs: PackedVector3Array in r["holes"]:
			if _winding(hs, n) * h > 0.0:
				hs.reverse()
			holes.append(hs)
		for loop: PackedVector3Array in [outer] + holes:
			var P := []
			for q in loop:
				P.append(PackedVector3Array([q, q + n * h]))
			P.append(P[0])
			b.sheet(P, _creases(loop, true), PackedInt32Array(), true)
		var base := keyhole(outer, holes)
		var top := PackedVector3Array()
		for q in base:
			top.append(q + n * h)
		var u := (outer[1] - outer[0]).normalized()
		cap(b, base, -n * signf(h), u)
		cap(b, top, n * signf(h), u)
	return _commit(b, all_closed)


## Closed curves sorted into regions: each outline with the curves inside it (in its plane) as its holes
## - a curve inside a hole is an outline again. [{s: points, n: normal, holes: [points...]}...]
static func regions(cs: Array) -> Array:
	var loops := []
	for c in cs:
		var s := sample(c)
		if s.size() < 3:
			continue
		var n: Vector3 = (c.get("n", Vector3.UP) as Vector3).normalized()
		loops.append({"s": s, "n": n, "area": absf(_winding(s, n)), "parent": -1})
	for j in loops.size():
		var best := -1
		for i in loops.size():
			if i == j or loops[i]["area"] <= loops[j]["area"]:
				continue
			var ni: Vector3 = loops[i]["n"]
			if absf(ni.dot(loops[j]["n"])) < 0.999:
				continue
			var si: PackedVector3Array = loops[i]["s"]
			var sj: PackedVector3Array = loops[j]["s"]
			if absf((sj[0] - si[0]).dot(ni)) > 1e-4:
				continue
			var u := _any_perp(ni)
			var v := ni.cross(u)
			var flat := PackedVector2Array()
			for q in si:
				flat.append(Vector2((q - si[0]).dot(u), (q - si[0]).dot(v)))
			var inside := true
			for q in [sj[0], sj[sj.size() / 2]]:
				if not Geometry2D.is_point_in_polygon(Vector2((q - si[0]).dot(u), (q - si[0]).dot(v)), flat):
					inside = false
			if inside and (best < 0 or loops[i]["area"] < loops[best]["area"]):
				best = i
		loops[j]["parent"] = best
	var depth := []
	for j in loops.size():
		var d := 0
		var k: int = loops[j]["parent"]
		while k >= 0 and d < 64:
			d += 1
			k = loops[k]["parent"]
		depth.append(d)
	var out := []
	var at := {}
	for j in loops.size():
		if depth[j] % 2 == 0:
			at[j] = out.size()
			out.append({"s": loops[j]["s"], "n": loops[j]["n"], "holes": []})
	for j in loops.size():
		if depth[j] % 2 == 1 and at.has(loops[j]["parent"]):
			out[at[loops[j]["parent"]]]["holes"].append(loops[j]["s"])
	return out


## A flat polygon (an outline joined to its holes by slits - keyhole()) as faces facing `normal`:
## cut into triangles by the editor's own ear clipping, which keeps to a slit's two sides (the
## engine's triangulator strays into holes).
static func cap(b: Shapes.B, pts: PackedVector3Array, normal: Vector3, tex_u: Vector3) -> void:
	if pts.size() < 3:
		return
	var EM: GDScript = load("res://scripts/editor/mesh/edit_mesh.gd")
	var u := tex_u.normalized()
	var v := normal.normalized().cross(u)
	var flat := PackedVector2Array()
	for q in pts:
		flat.append(Vector2(q.dot(u), q.dot(v)))
	var area := 0.0
	for i in flat.size():
		area += flat[i].cross(flat[(i + 1) % flat.size()])
	var order := PackedInt32Array()
	for i in pts.size():
		order.append(i if area > 0.0 else pts.size() - 1 - i)
	var ccw := PackedVector2Array()
	for i in order:
		ccw.append(flat[i])
	var t: PackedInt32Array = EM.ear_clip(ccw)
	var base := b.v.size()
	for q in pts:
		b.add(q, normal.normalized(), Vector2(q.dot(u), q.dot(v)))
	for k in range(0, t.size(), 3):
		b.tri_facing(base + order[t[k]], base + order[t[k + 1]], base + order[t[k + 2]], normal)


## One outline with its holes as a single loop: each hole joined to the outline by a slit from its
## nearest point (a hole winds the other way round; the result triangulates as a plain polygon).
static func keyhole(outer: PackedVector3Array, holes: Array) -> PackedVector3Array:
	var poly := outer.duplicate()
	for hs: PackedVector3Array in holes:
		var best := INF
		var pi := 0
		var hj := 0
		for i in poly.size():
			for j in hs.size():
				var d := poly[i].distance_squared_to(hs[j])
				if d < best:
					best = d
					pi = i
					hj = j
		var np := PackedVector3Array()
		for i in pi + 1:
			np.append(poly[i])
		for k in hs.size() + 1:
			np.append(hs[(hj + k) % hs.size()])
		for i in range(pi, poly.size()):
			np.append(poly[i])
		poly = np
	return poly


## A profile revolved `angle` about the line through `axis[0]` along `axis[1]` in `steps` steps
## (the axis line itself, if one of the curves, left out). Closed profiles make closed solids
## (a full turn); an open one reaching the axis closes there.
static func revolve_mesh(cs: Array, angle: float, steps: int, axis: Array) -> ArrayMesh:
	var b := Shapes.B.new()
	var o: Vector3 = axis[0]
	var ax: Vector3 = (axis[1] as Vector3).normalized()
	var full := angle >= TAU - 1e-4
	var n_steps := maxi(3, int(ceil(steps * angle / TAU)))
	var any_closed := false
	for ci in cs.size():
		var c: Dictionary = cs[ci]
		var s := sample(c)
		var closed: bool = c.get("closed", false)
		any_closed = any_closed or closed
		if s.size() < 2:
			continue
		if closed:
			s.append(s[0])
		var P := []
		for j in n_steps + 1:
			var a := angle * j / n_steps
			var col := PackedVector3Array()
			for q in s:
				col.append(o + (q - o).rotated(ax, a))
			P.append(col)
		var crease := _creases(s, false)
		b.sheet(P, PackedInt32Array(), crease, full, closed)
		if closed and not full:
			# (a partial turn: the profile's two flat ends)
			var p0 := PackedVector3Array()
			var p1 := PackedVector3Array()
			for k in s.size() - 1:
				p0.append(o + (s[k] - o))
				p1.append(o + (s[k] - o).rotated(ax, angle))
			var cn := ((s[1] - s[0]).cross(s[2 % s.size()] - s[0])).normalized()
			var u := (s[1] - s[0]).normalized()
			b.cap(p0, -cn if cn.dot(ax.cross(s[0] - o)) > 0 else cn, u, cn.cross(u))
			var cn1 := cn.rotated(ax, angle)
			b.cap(p1, cn1 if cn.dot(ax.cross(s[0] - o)) > 0 else -cn1, u.rotated(ax, angle), cn1.cross(u.rotated(ax, angle)))
	return _commit(b, any_closed or full)


## Curves resampled to `n` points each, evenly along their length (closed: a loop).
static func resample(s: PackedVector3Array, closed: bool, n: int) -> PackedVector3Array:
	var pts := s.duplicate()
	if closed:
		pts.append(pts[0])
	var L := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		L.append(L[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := L[L.size() - 1]
	var out := PackedVector3Array()
	var cnt := n if closed else n
	var j := 0
	for i in cnt:
		var d := total * i / (float(n) if closed else maxf(1.0, n - 1.0))
		while j < L.size() - 2 and L[j + 1] < d:
			j += 1
		var seg := maxf(L[j + 1] - L[j], 1e-9)
		out.append(pts[j].lerp(pts[j + 1], clampf((d - L[j]) / seg, 0.0, 1.0)))
	return out


## A surface through the curves in order (each resampled to the same count, the loops turned to
## start near each other); closed ones capped at both ends.
static func loft_mesh(cs: Array) -> ArrayMesh:
	if cs.size() < 2:
		return null
	var closed: bool = cs[0].get("closed", false)
	var n := 48
	var rows := []
	for c in cs:
		var s := resample(sample(c), closed, n)
		if not rows.is_empty():
			var prev: PackedVector3Array = rows[rows.size() - 1]
			if closed:
				# (the loop turned and started where it's nearest the one before; reversed if it runs the other way)
				var best := INF
				var best_s := s
				for rev in 2:
					var t := s.duplicate()
					if rev == 1:
						t.reverse()
					for k in n:
						var d := 0.0
						for q in range(0, n, 4):
							d += t[(q + k) % n].distance_squared_to(prev[q])
						if d < best:
							best = d
							var r := PackedVector3Array()
							for q in n:
								r.append(t[(q + k) % n])
							best_s = r
				s = best_s
			elif s[0].distance_to(prev[0]) > s[s.size() - 1].distance_to(prev[0]):
				s.reverse()
		rows.append(s)
	if closed:
		# (the loops turning left about the way the loft goes: its sides face out, as its caps do)
		var dirn := _middle(rows[rows.size() - 1]) - _middle(rows[0])
		if _winding(rows[0], dirn) < 0.0:
			for r in rows:
				(r as PackedVector3Array).reverse()
	var P := []
	for i in n + (1 if closed else 0):
		var col := PackedVector3Array()
		for r in rows:
			col.append((r as PackedVector3Array)[i % n])
		P.append(col)
	var b := Shapes.B.new()
	b.sheet(P, PackedInt32Array(), PackedInt32Array(), closed)
	if closed:
		var dirn := (_middle(rows[rows.size() - 1]) - _middle(rows[0])).normalized()
		for e in [0, rows.size() - 1]:
			var r: PackedVector3Array = rows[e]
			var nn := -dirn if e == 0 else dirn
			var u := (r[1] - r[0]).normalized()
			b.cap(r, nn, u, nn.cross(u))
	return _commit(b, closed)


static func _middle(s: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for q in s:
		c += q
	return c / maxf(1, s.size())


## How loop `s` turns about `n` (+: left / counter-clockwise looking down `n`).
static func _winding(s: PackedVector3Array, n: Vector3) -> float:
	var c := _middle(s)
	var a := 0.0
	for k in s.size():
		a += (s[k] - c).cross(s[(k + 1) % s.size()] - c).dot(n)
	return a


## Profile `prof` (a closed curve: a solid; open: a sheet) carried along `path`, turned with it
## (frames that don't twist), its plane square to the path.
static func sweep_mesh(prof: Dictionary, path: Dictionary) -> ArrayMesh:
	var ps := sample(path)
	var pclosed: bool = path.get("closed", false)
	if ps.size() < 2:
		return null
	var s := sample(prof)
	var closed: bool = prof.get("closed", false)
	if s.size() < 2:
		return null
	# the profile in its own plane's coordinates round its middle
	var pn: Vector3 = (prof.get("n", Vector3.UP) as Vector3).normalized()
	var c := Vector3.ZERO
	for q in s:
		c += q
	c /= s.size()
	var pu := _any_perp(pn)
	var pv := pn.cross(pu)
	var flat := PackedVector2Array()
	for q in s:
		flat.append(Vector2((q - c).dot(pu), (q - c).dot(pv)))
	return _tube(ps, pclosed, flat, closed)


## Points `flat` (2D) carried along `ps` by rotation-minimising frames.
static func _tube(ps: PackedVector3Array, pclosed: bool, flat: PackedVector2Array, closed: bool) -> ArrayMesh:
	if closed and Shapes._area(flat) < 0.0:
		flat = flat.duplicate()
		flat.reverse()   # (turning left about the path: the sides face out, as the ends do)
	var m := ps.size()
	var T := PackedVector3Array()
	for i in m:
		var a := ps[maxi(i - 1, 0)] if not pclosed else ps[(i - 1 + m) % m]
		var b := ps[mini(i + 1, m - 1)] if not pclosed else ps[(i + 1) % m]
		T.append((b - a).normalized())
	var N := _any_perp(T[0])
	var rows := []
	for i in m + (1 if pclosed else 0):
		var t := T[i % m]
		if i > 0:
			var tp := T[(i - 1) % m]
			var ax := tp.cross(t)
			if ax.length() > 1e-6:
				N = N.rotated(ax.normalized(), tp.angle_to(t))
			N = (N - t * N.dot(t)).normalized()
		var Bn := t.cross(N)
		var row := PackedVector3Array()
		for q in flat:
			row.append(ps[i % m] + N * q.x + Bn * q.y)
		rows.append(row)
	var P := []
	var k := flat.size()
	for j in k + (1 if closed else 0):
		var col := PackedVector3Array()
		for r in rows:
			col.append((r as PackedVector3Array)[j % k])
		P.append(col)
	var b := Shapes.B.new()
	var crease := PackedInt32Array()
	if closed:
		var fl3 := PackedVector3Array()
		for q in flat:
			fl3.append(Vector3(q.x, q.y, 0))
		crease = _creases(fl3, true)
	b.sheet(P, crease, PackedInt32Array(), closed, pclosed)
	if closed and not pclosed:
		for e in [0, rows.size() - 1]:
			var r: PackedVector3Array = rows[e]
			var tt := T[0] if e == 0 else T[m - 1]
			b.cap(r, -tt if e == 0 else tt, _any_perp(tt), tt.cross(_any_perp(tt)))
	return _commit(b, closed)


## A round tube of radius `r` along each curve (open ones capped).
static func pipe_mesh(cs: Array, r: float, around := 16) -> ArrayMesh:
	var flat := PackedVector2Array()
	for i in around:
		flat.append(Vector2(cos(TAU * i / around), sin(TAU * i / around)) * r)
	var out: ArrayMesh = null
	var b := Shapes.B.new()
	for c in cs:
		var m := _tube(sample(c), c.get("closed", false), flat, true)
		if m == null:
			continue
		var a := m.surface_get_arrays(0)
		var base := b.v.size()
		b.v.append_array(a[Mesh.ARRAY_VERTEX])
		b.n.append_array(a[Mesh.ARRAY_NORMAL])
		b.uv.append_array(a[Mesh.ARRAY_TEX_UV])
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):   # (back to the builder's order: commit turns them again)
			b.idx.append(base + ix[t]); b.idx.append(base + ix[t + 2]); b.idx.append(base + ix[t + 1])
	var arr := b.commit()
	if arr.is_empty():
		return null
	out = ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Closed curves filled: flat faces (one-sided, facing their plane's normal).
static func fill_mesh(cs: Array) -> ArrayMesh:
	var b := Shapes.B.new()
	var closed_cs := []
	for c in cs:
		if c.get("closed", false):
			closed_cs.append(c)
	for r in regions(closed_cs):
		var n: Vector3 = r["n"]
		var outer: PackedVector3Array = r["s"]
		if _winding(outer, n) < 0.0:
			outer.reverse()
		var holes := []
		for hs: PackedVector3Array in r["holes"]:
			if _winding(hs, n) > 0.0:
				hs.reverse()
			holes.append(hs)
		var u := (outer[1] - outer[0]).normalized()
		cap(b, keyhole(outer, holes), n, u)
	return _commit(b, false)


# --- keeping them with the model --------------------------------------------------------------

static func to_json(cs: Array) -> Array:
	var out := []
	for c in cs:
		var k := []
		for q in (c["ctrl"] as PackedVector3Array):
			k.append([q.x, q.y, q.z])
		var n: Vector3 = c.get("n", Vector3.UP)
		var e := {"kind": c["kind"], "ctrl": k, "closed": c.get("closed", false), "n": [n.x, n.y, n.z], "name": c.get("name", ""), "id": int(c.get("id", -1))}
		if c.has("radii"):
			e["radii"] = Array(c["radii"])
		if c.has("sharp"):
			e["sharp"] = Array(c["sharp"])
		if c.get("hidden", false):
			e["hidden"] = true
		out.append(e)
	return out


static func from_json(arr: Variant) -> Array:
	var out := []
	if not arr is Array:
		return out
	for e in arr:
		if not e is Dictionary or not KINDS.has(str(e.get("kind", ""))):
			continue
		var k := PackedVector3Array()
		for q in e.get("ctrl", []):
			if q is Array and q.size() >= 3:
				k.append(Vector3(q[0], q[1], q[2]))
		if k.size() < 2:
			continue
		var n: Array = e.get("n", [0, 1, 0])
		var c := {"kind": str(e["kind"]), "ctrl": k, "closed": bool(e.get("closed", false)), "n": Vector3(n[0], n[1], n[2]), "name": str(e.get("name", ""))}
		if e.has("radii"):
			c["radii"] = PackedFloat32Array(e["radii"])
		if e.has("sharp"):
			c["sharp"] = PackedByteArray(e["sharp"])
		if e.get("hidden", false):
			c["hidden"] = true
		if int(e.get("id", -1)) > 0:
			c["id"] = int(e["id"])
		out.append(c)
	return out


## The model `res_path` opened: its curves read ("" - a new model: none).
func model_opened(res_path: String) -> void:
	cancel_op()
	if tool != "":
		stop()
	curves = []
	sel = []
	_vertex_key = -1
	if res_path != "":
		var f: String = ed._read_source(res_path, res_path.get_file() + ".curves.json")
		if FileAccess.file_exists(f):
			var j = JSON.parse_string(FileAccess.get_file_as_string(f))
			if j is Dictionary:
				curves = from_json(j.get("curves", []))
	# (ids: past every one in use - by a curve, or by a solid's recipe - and given to curves without one)
	var nid := 1
	for c in curves:
		nid = maxi(nid, int(c.get("id", 0)) + 1)
	if ed.model:
		for p: MeshInstance3D in ed.model.find_children("*", "MeshInstance3D", true, false):
			var ex = p.get_meta("extras", {})
			if ex is Dictionary and ex.get("atrapos_curves") is Dictionary:
				for id in ex["atrapos_curves"].get("ids", []) + [ex["atrapos_curves"].get("axis", -1)]:
					nid = maxi(nid, int(id) + 1)
	_set_nid(nid)
	for c in curves:
		if not c.has("id"):
			_fresh(c)
	refresh_solids.call_deferred()
	_refresh_panel()
	if layer:
		layer.queue_redraw()


## Saved beside model file `file` (none: any old file removed).
func save_beside(file: String) -> void:
	var f := file + ".curves.json"
	if curves.is_empty():
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
		return
	var fa := FileAccess.open(f, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify({"curves": to_json(curves)}, "\t"))


# --- the tab --------------------------------------------------------------------------------

## The selected part's recipe ({} - not made from curves, or a plain mesh now).
func part_spec() -> Dictionary:
	var p: MeshInstance3D = ed.part
	return p.get_meta("curve_solid") if p and is_instance_valid(p) and p.has_meta("curve_solid") else {}


## A setting of the selected solid changed (`key`: value / segs) - it's made again; one undo step.
func set_spec(key: String, v: float) -> void:
	var p: MeshInstance3D = ed.part
	var old := part_spec()
	if old.is_empty() or is_equal_approx(float(old.get(key, 0.0)), v):
		return
	var new := old.duplicate(true)
	new[key] = int(v) if key == "segs" else v
	var apply := func(spec: Dictionary):
		if is_instance_valid(p):
			p.set_meta("curve_solid", spec)
			refresh_solids()
			_refresh_panel()
	apply.call(new)
	ed._push("Solid " + key, apply.bind(old), apply.bind(new))


## The selected solid made a plain mesh: its curves no longer change it (one undo step).
func unlink_part() -> void:
	var p: MeshInstance3D = ed.part
	var old := part_spec()
	if old.is_empty():
		return
	var key: String = p.get_meta("curve_solid_key", "")
	p.remove_meta("curve_solid")
	ed._push("Make plain mesh", func():
		p.set_meta("curve_solid", old)
		p.set_meta("curve_solid_key", key)
		_refresh_panel(), func():
		p.remove_meta("curve_solid")
		_refresh_panel())
	ed._say("%s is a plain mesh now: its curves no longer change it." % p.name)
	_refresh_panel()


## The selected solid's curves picked (to reshape them).
func pick_part_curves() -> void:
	var spec := part_spec()
	sel = []
	for id in spec_ids(spec):
		for i in curves.size():
			if int(curves[i].get("id", -1)) == int(id):
				sel.append(i)
	_refresh_panel()
	layer.queue_redraw()


# --- the recipe: every step of a solid, editable ----------------------------------------------------

const ROLES := ["union", "difference", "intersection"]
const ROLE_NAMES := ["Join", "Cut", "Common"]


## The step at `path` (keys "a" / "b" down a boolean's sides) of recipe `spec`.
static func node_at(spec: Dictionary, path: Array) -> Dictionary:
	var n := spec
	for k in path:
		n = n.get(k, {})
	return n


## Recipe `spec` with the step at `path` replaced by `node` (a new copy).
static func with_node(spec: Dictionary, path: Array, node: Dictionary) -> Dictionary:
	if path.is_empty():
		return node.duplicate(true)
	var out := spec.duplicate(true)
	out[path[0]] = with_node(spec.get(path[0], {}), path.slice(1), node)
	return out


## The selected solid's recipe changed to `new` (made again at once; one undo step called `what`).
func set_recipe(new: Dictionary, what: String) -> void:
	var p: MeshInstance3D = ed.part
	var old := part_spec()
	if p == null or old.is_empty() or JSON.stringify(old) == JSON.stringify(new):
		return
	var apply := func(spec: Dictionary):
		if is_instance_valid(p):
			p.set_meta("curve_solid", spec)
			refresh_solids()
			_refresh_panel()
	apply.call(new)
	ed._push(what, apply.bind(old), apply.bind(new))


## A setting `key` of the step at `path` set to `v`.
func set_node(path: Array, key: String, v: Variant) -> void:
	var spec := part_spec()
	var node := node_at(spec, path).duplicate(true)
	if node.is_empty() or node.get(key) == v:
		return
	node[key] = v
	set_recipe(with_node(spec, path, node), "Solid: " + key)


func _node_value(v: float, path: Array) -> void:
	set_node(path, "value", v)


func _node_segs(v: float, path: Array) -> void:
	set_node(path, "segs", int(v))


## A curve's own height inside the step at `path` (the step's height again: its own setting dropped).
func _curve_value(v: float, path: Array, id: String) -> void:
	var node := node_at(part_spec(), path)
	var per: Dictionary = (node.get("per", {}) as Dictionary).duplicate(true) if node.get("per") is Dictionary else {}
	var o: Dictionary = per.get(id, {})
	o["value"] = v
	if absf(v - float(node.get("value", 0.0))) < 1e-6 and not o.has("both"):
		per.erase(id)
	else:
		per[id] = o
	set_node(path, "per", per)


func _curve_both(on: bool, path: Array, id: String) -> void:
	var node := node_at(part_spec(), path)
	var per: Dictionary = (node.get("per", {}) as Dictionary).duplicate(true) if node.get("per") is Dictionary else {}
	var o: Dictionary = per.get(id, {"value": float(node.get("value", 0.0))})
	o["both"] = on
	per[id] = o
	set_node(path, "per", per)


## A curve's role inside the step at `path` (0 add, 1 cut).
func _curve_role(i: int, path: Array, id: String) -> void:
	var spec := part_spec()
	var node := node_at(spec, path)
	var roles: Dictionary = (node.get("roles", {}) as Dictionary).duplicate()
	if roles.is_empty():
		for cid in node.get("ids", []):
			roles[str(int(cid))] = "add"
	roles[id] = ["add", "cut"][i]
	set_node(path, "roles", roles)


func _node_both(on: bool, path: Array) -> void:
	set_node(path, "both", on)


## A boolean step's role: join (union), cut (difference) or common (intersection).
func _node_role(i: int, path: Array) -> void:
	set_node(path, "op", ROLES[i])


## The boolean step at `path` taken apart: the step becomes its first side again, and the second side
## (the tool solid) a positive part of its own, where it was. One undo step.
func separate_node(path: Array) -> void:
	var p: MeshInstance3D = ed.part
	var spec := part_spec()
	var node := node_at(spec, path)
	if p == null or str(node.get("kind", "")) != "bool":
		return
	# (where the tool sits: the part's place, through each "b" side's place on the way down)
	var xf := Transform3D()
	var n := spec
	for k in path:
		if k == "b":
			xf = xf * xf_of(n.get("b_xf", []))
		n = n[k]
	xf = xf * xf_of(node.get("b_xf", []))
	var b_spec: Dictionary = node["b"]
	var mb := solid_of(b_spec)
	if mb == null:
		ed._say("Separate: its curves are gone.")
		return
	mb.surface_set_material(0, MeshIO.default_material())
	var tool_part := MeshInstance3D.new()
	tool_part.mesh = mb
	tool_part.name = ed._unique({"extrude": "Extrusion", "baked": "Baked", "revolve": "Revolve", "pipe": "Pipe", "loft": "Loft", "sweep": "Sweep"}.get(str(b_spec.get("kind", "")), "Solid"))
	tool_part.transform = p.transform * xf
	tool_part.set_meta("curve_solid", b_spec)
	tool_part.set_meta("curve_solid_key", _solid_key(b_spec))
	var new_spec := with_node(spec, path, node["a"])
	var model: Node3D = ed.model
	var do_it := func():
		p.set_meta("curve_solid", new_spec)
		refresh_solids()
		model.add_child(tool_part)
		tool_part.owner = model
		ed._fill_parts()
		ed.select_part(p)
	var undo_it := func():
		p.set_meta("curve_solid", spec)
		refresh_solids()
		if tool_part.get_parent():
			tool_part.get_parent().remove_child(tool_part)
		ed._fill_parts()
		ed.select_part(p)
	ed._do("Separate", do_it, undo_it, [tool_part])
	ed._say("%s separated: a solid of its own again." % tool_part.name)


## The recipe tree's rows: made again when its shape changes (steps added or taken apart), else just
## their values brought up to date (so a spin box being typed into keeps its focus).
func _fill_recipe(box: VBoxContainer, spec: Dictionary) -> void:
	var shape := str(ed.part.get_instance_id()) + "|" + _recipe_shape(spec, [])
	if str(box.get_meta("shape", "")) == shape:
		_recipe_values(box, spec)
		return
	box.set_meta("shape", shape)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	_recipe_rows(box, spec, [], 0)
	UI.scale_fonts(box, "menu", 1.0)
	_recipe_values(box, spec)


static func _recipe_shape(spec: Dictionary, path: Array) -> String:
	var k := str(spec.get("kind", ""))
	if k == "bool":
		return "(" + _recipe_shape(spec.get("a", {}), path + ["a"]) + "," + _recipe_shape(spec.get("b", {}), path + ["b"]) + ")"
	return k


func _recipe_rows(box: VBoxContainer, node: Dictionary, path: Array, depth: int) -> void:
	var kind := str(node.get("kind", ""))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	var pad := Control.new()
	pad.custom_minimum_size.x = depth * 14
	row.add_child(pad)
	var key := "/".join(path)
	if kind == "bool":
		var role := OptionButton.new()
		role.focus_mode = Control.FOCUS_NONE
		for i in ROLE_NAMES.size():
			role.add_item(ROLE_NAMES[i])
		role.tooltip_text = EditorIcons.tip("Role", "", "What the second solid does to the first: Join (union - added), Cut (subtract - taken away),\nCommon (intersect - only what both share). Change it any time: worked out again at once.")
		role.item_selected.connect(_node_role.bind(path))
		role.set_meta("recipe", [key, "op"])
		row.add_child(role)
		var sep: Button = ed._small("Separate", EditorIcons.tip("Separate", "", "This step taken apart: the second solid a positive part of its own again, where it was."), separate_node.bind(path))
		row.add_child(sep)
		box.add_child(row)
		_recipe_rows(box, node.get("a", {}), path + ["a"], depth + 1)
		_recipe_rows(box, node.get("b", {}), path + ["b"], depth + 1)
		return
	var name := UI.label({"extrude": "Extrusion", "baked": "Baked", "edges": "Baked", "revolve": "Revolve", "pipe": "Pipe", "loft": "Loft", "sweep": "Sweep", "fill": "Fill"}.get(kind, kind.capitalize()), 14, UI.TEXT_DIM)
	name.custom_minimum_size.x = 64
	name.tooltip_text = "A step of this solid made from %d curve%s." % [(node.get("ids", []) as Array).size(), "" if (node.get("ids", []) as Array).size() == 1 else "s"]
	if kind in ["baked", "edges"]:
		name.tooltip_text = "A baked solid: shaped by its %d curves only - pick them (Pick its curves) and reshape them; it follows." % (node.get("ids", []) as Array).size()
	name.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(name)
	if kind in ["extrude", "revolve", "pipe"]:
		var sp := SpinBox.new()
		sp.min_value = {"extrude": -100.0, "revolve": 1.0, "pipe": 0.001}[kind]
		sp.max_value = {"extrude": 100.0, "revolve": 360.0, "pipe": 10.0}[kind]
		sp.step = 1.0 if kind == "revolve" else 0.001
		sp.allow_greater = kind != "revolve"
		sp.allow_lesser = kind == "extrude"
		sp.custom_minimum_size.x = 84
		sp.suffix = {"extrude": "m", "revolve": "°", "pipe": "m"}[kind]
		sp.tooltip_text = EditorIcons.tip({"extrude": "Height", "revolve": "Angle", "pipe": "Radius"}[kind], "", "This step's %s - change it any time: the solid is made again at once." % {"extrude": "height (minus: the other way)", "revolve": "angle", "pipe": "radius"}[kind])
		sp.value_changed.connect(_node_value.bind(path))
		sp.set_meta("recipe", [key, "value"])
		row.add_child(sp)
	if kind == "revolve":
		var st := SpinBox.new()
		st.min_value = 3
		st.max_value = 256
		st.custom_minimum_size.x = 70
		st.tooltip_text = EditorIcons.tip("Steps round", "", "How many steps the revolve takes for a whole turn.")
		st.value_changed.connect(_node_segs.bind(path))
		st.set_meta("recipe", [key, "segs"])
		row.add_child(st)
	if kind == "extrude":
		var both := CheckBox.new()
		both.text = "Both ways"
		both.focus_mode = Control.FOCUS_NONE
		both.tooltip_text = EditorIcons.tip("Both ways", "", "The extrusion goes half its height each way from its curves' plane.")
		both.toggled.connect(_node_both.bind(path))
		both.set_meta("recipe", [key, "both"])
		row.add_child(both)
	box.add_child(row)
	# each of its curves' role (an extrusion or fill of several): add, or cut from the others
	if kind in ["extrude", "fill"] and (node.get("ids", []) as Array).size() >= 2:
		for id in node.get("ids", []):
			var c := curve_by_id(int(id))
			var cr := HFlowContainer.new()   # (its name, role, own height, both ways: one row)
			cr.add_theme_constant_override("h_separation", 3)
			var pad2 := Control.new()
			pad2.custom_minimum_size.x = depth * 14 + 10
			cr.add_child(pad2)
			var cl := UI.label(str(c.get("name", "Curve")) if not c.is_empty() else "(gone)", 14, UI.TEXT_DIM)
			cl.custom_minimum_size.x = 64
			cl.clip_text = true
			cl.tooltip_text = "One of the curves this step is made from."
			cl.mouse_filter = Control.MOUSE_FILTER_STOP
			cr.add_child(cl)
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.add_item("Add")
			ob.add_item("Cut")
			ob.tooltip_text = EditorIcons.tip("Curve role", "", "Add: this curve's outline is part of the solid. Cut: it's taken out of the others (a hole or\na bite) - one clean solid, made again from its curves live. (No roles set: a curve inside\nanother is a hole, as drawn.)")
			ob.item_selected.connect(_curve_role.bind(path, str(int(id))))
			ob.set_meta("recipe", [key, "role:" + str(int(id))])
			cr.add_child(ob)
			box.add_child(cr)
			if kind == "extrude":
				# its own height and both ways (the step's till changed) - on its row
				var hr := cr
				var hs := SpinBox.new()
				hs.min_value = -100.0
				hs.max_value = 100.0
				hs.step = 0.001
				hs.allow_greater = true
				hs.allow_lesser = true
				hs.suffix = "m"
				hs.custom_minimum_size.x = 84
				hs.tooltip_text = EditorIcons.tip("Curve's height", "", "This curve's own extrusion height (minus: the other way) - the step's until you change it.\nA cut curve with its own height: a pocket that deep, or right through.")
				hs.value_changed.connect(_curve_value.bind(path, str(int(id))))
				hs.set_meta("recipe", [key, "per_value:" + str(int(id))])
				hr.add_child(hs)
				var hb := CheckBox.new()
				hb.text = "Both"
				hb.focus_mode = Control.FOCUS_NONE
				hb.tooltip_text = EditorIcons.tip("Curve both ways", "", "This curve extruded half its height each way from its plane.")
				hb.toggled.connect(_curve_both.bind(path, str(int(id))))
				hb.set_meta("recipe", [key, "per_both:" + str(int(id))])
				hr.add_child(hb)


## The recipe rows' controls showing the recipe's values (without signals).
func _recipe_values(box: VBoxContainer, spec: Dictionary) -> void:
	for c in box.find_children("*", "", true, false):
		if not c.has_meta("recipe"):
			continue
		var m: Array = c.get_meta("recipe")
		var path: Array = [] if str(m[0]) == "" else Array(str(m[0]).split("/"))
		var node := node_at(spec, path)
		match str(m[1]):
			"op": (c as OptionButton).select(maxi(0, ROLES.find(str(node.get("op", "difference")))))
			"value": (c as SpinBox).set_value_no_signal(float(node.get("value", 0.0)))
			"segs": (c as SpinBox).set_value_no_signal(int(node.get("segs", segs)))
			"both": (c as CheckBox).set_pressed_no_signal(bool(node.get("both", false)))
			_:
				if str(m[1]).begins_with("role:"):
					var r := str((node.get("roles", {}) as Dictionary).get(str(m[1]).substr(5), "add"))
					(c as OptionButton).select(1 if r == "cut" else 0)
				elif str(m[1]).begins_with("per_"):
					var id := str(m[1]).get_slice(":", 1)
					var per: Dictionary = node.get("per", {}) if node.get("per") is Dictionary else {}
					var o: Dictionary = per.get(id, {})
					if str(m[1]).begins_with("per_value:"):
						(c as SpinBox).set_value_no_signal(float(o.get("value", node.get("value", 0.0))))
					else:
						(c as CheckBox).set_pressed_no_signal(bool(o.get("both", node.get("both", false))))


## The picked curve's own properties (its name, a circle's radius, a line's corner radius, closed) -
## changed here at any time, live: the solids made from it follow. (Several picked: set on all that
## have it.)
func build_curve_box(box: VBoxContainer) -> void:
	var cb := HFlowContainer.new()   # (name, radius / corner, closed - flowing onto as few rows as fit)
	cb.add_theme_constant_override("h_separation", 4)
	cb.add_theme_constant_override("v_separation", 1)
	var nr := HBoxContainer.new()
	nr.custom_minimum_size.x = 200
	var nl := UI.label("Name", 14, UI.TEXT_DIM)
	nr.add_child(nl)
	var name_e := LineEdit.new()
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_e.tooltip_text = EditorIcons.tip("Curve name", "Enter", "The picked curve's name.")
	name_e.text_submitted.connect(_cv_name)
	nr.add_child(name_e)
	cb.add_child(nr)
	for f in [["radius", "Radius", "The picked circles' radius (metres) - the solids made from them follow.", 0.001, 100.0],
			["corner", "Corner radius", "The picked lines', rectangles' and polygons' corners rounded by this radius (0: sharp).", 0.0, 100.0]]:
		var r := HBoxContainer.new()
		var l := UI.label(f[1], 14, UI.TEXT_DIM)
		r.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = f[3]
		sp.max_value = f[4]
		sp.step = 0.001
		sp.allow_greater = true
		sp.suffix = "m"
		sp.custom_minimum_size.x = 84
		sp.tooltip_text = EditorIcons.tip(f[1], "", f[2])
		sp.value_changed.connect(_cv_radius if f[0] == "radius" else _cv_corner)
		r.add_child(sp)
		cb.add_child(r)
		_panel_btns["w_cv_" + f[0]] = sp
		_panel_btns["w_cv_" + f[0] + "_row"] = r
	var closed := CheckBox.new()
	closed.text = "Closed"
	closed.focus_mode = Control.FOCUS_NONE
	closed.tooltip_text = EditorIcons.tip("Closed", "", "The picked lines, splines and paths as loops (closed) or open.")
	closed.toggled.connect(_cv_closed)
	cb.add_child(closed)
	box.add_child(cb)
	_panel_btns["w_cv_box"] = cb
	_panel_btns["w_cv_name"] = name_e
	_panel_btns["w_cv_closed"] = closed


func _cv_name(t: String) -> void:
	if sel.is_empty() or t.strip_edges() == "":
		return
	var before := _state()
	curves[sel[0]]["name"] = t.strip_edges()
	_changed("Rename curve", before)


func _cv_radius(v: float) -> void:
	var before := _state()
	var any := false
	for i in sel:
		var c: Dictionary = curves[i]
		if str(c["kind"]) == "circle":
			var k: PackedVector3Array = (c["ctrl"] as PackedVector3Array).duplicate()
			var d := k[1] - k[0]
			k[1] = k[0] + (d.normalized() if d.length() > 1e-9 else _any_perp(c.get("n", Vector3.UP))) * maxf(v, 1e-4)
			c["ctrl"] = k
			any = true
	if any:
		_changed("Curve radius", before)


func _cv_corner(v: float) -> void:
	var before := _state()
	var any := false
	for i in sel:
		var c: Dictionary = curves[i]
		if str(c["kind"]) == "line":
			var r := PackedFloat32Array()
			r.resize((c["ctrl"] as PackedVector3Array).size())
			r.fill(maxf(v, 0.0))
			c["radii"] = r
			any = true
	if any:
		_changed("Corner radius", before)


func _cv_closed(on: bool) -> void:
	var before := _state()
	var any := false
	for i in sel:
		var c: Dictionary = curves[i]
		if str(c["kind"]) in ["line", "spline", "path"] and (c["ctrl"] as PackedVector3Array).size() >= 3 and bool(c.get("closed", false)) != on:
			c["closed"] = on
			any = true
	if any:
		_changed("Close / open curves", before)


## The CURVE box showing the first picked curve (hidden with none).
func _curve_box_values() -> void:
	var cb = _w("cv_box")
	if cb == null:
		return
	(cb as Control).visible = not sel.is_empty()
	if sel.is_empty():
		return
	var c: Dictionary = curves[sel[0]]
	var kind := str(c["kind"])
	var ne: LineEdit = _w("cv_name")
	if not ne.has_focus():
		ne.text = str(c.get("name", ""))
	var kinds := []
	for i in sel:
		kinds.append(str(curves[i]["kind"]))
	(_w("cv_radius_row") as Control).visible = "circle" in kinds
	(_w("cv_corner_row") as Control).visible = "line" in kinds
	for i in sel:
		var ci: Dictionary = curves[i]
		if str(ci["kind"]) == "circle":
			(_w("cv_radius") as SpinBox).set_value_no_signal((ci["ctrl"][0] as Vector3).distance_to(ci["ctrl"][1]))
			break
	for i in sel:
		var ci: Dictionary = curves[i]
		if str(ci["kind"]) == "line":
			var r: PackedFloat32Array = ci.get("radii", PackedFloat32Array())
			(_w("cv_corner") as SpinBox).set_value_no_signal(r[0] if not r.is_empty() else 0.0)
			break
	var cl: CheckBox = _w("cv_closed")
	cl.visible = kind in ["line", "spline", "path"]
	cl.set_pressed_no_signal(bool(c.get("closed", false)))


## The SOLID box (the selected procedural part's settings) at the top of the tab's `box`.
func build_solid_box(box: VBoxContainer) -> void:
	var _solid_box := VBoxContainer.new()
	_solid_box.add_theme_constant_override("separation", 1)
	_solid_box.add_child(EditorIcons.tipped(UI.section("SOLID"), EditorIcons.tip("Solid", "", "The selected solid: what it's made of (its recipe - every step and curve, editable any time),\nits role, and what you can do with it (pick its curves, bake it, make it a plain mesh).")))
	var _solid_label := UI.label("", 14, UI.TEXT_DIM)
	_solid_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_solid_box.add_child(_solid_label)
	# the recipe: every step of the solid, its settings and (a boolean's) role - editable any time
	var recipe := VBoxContainer.new()
	recipe.add_theme_constant_override("separation", 2)
	_solid_box.add_child(recipe)
	_panel_btns["w_recipe"] = recipe
	var _solid_value_row := HBoxContainer.new()
	var _solid_value_label := UI.label("Height", 14, UI.TEXT_DIM)
	_solid_value_label.custom_minimum_size.x = 70
	_solid_value_row.add_child(_solid_value_label)
	var _solid_value := SpinBox.new()
	_solid_value.min_value = -100.0
	_solid_value.max_value = 100.0
	_solid_value.step = 0.001
	_solid_value.allow_greater = true
	_solid_value.allow_lesser = true
	_solid_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solid_value.tooltip_text = EditorIcons.tip("The solid's setting", "", "An extrusion's height (minus: the other way), a revolve's angle, a pipe's radius.\nChanged, the solid is made again at once from its curves.")
	_solid_value.value_changed.connect(_spec_value)
	_solid_value_row.add_child(_solid_value)
	_solid_box.add_child(_solid_value_row)
	var _solid_segs_row := HBoxContainer.new()
	var sl := UI.label("Steps", 14, UI.TEXT_DIM)
	sl.custom_minimum_size.x = 70
	_solid_segs_row.add_child(sl)
	var _solid_segs := SpinBox.new()
	_solid_segs.min_value = 3
	_solid_segs.max_value = 256
	_solid_segs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_solid_segs.tooltip_text = EditorIcons.tip("Steps round", "", "How many steps the revolve takes for a whole turn: more is smoother.")
	_solid_segs.value_changed.connect(_spec_segs)
	_solid_segs_row.add_child(_solid_segs)
	_solid_box.add_child(_solid_segs_row)
	var sb := HFlowContainer.new()
	sb.add_theme_constant_override("h_separation", 2)
	sb.add_child(ed._small("Pick its curves", EditorIcons.tip("Pick its curves", "", "Picks the curves this solid is made from: drag their points and the solid follows."), pick_part_curves))
	sb.add_child(ed._small("Bake", EditorIcons.tip("Bake", "", "Its tools (the solids cut from it, joined to it, in common with it) and its curves worked out\ninto new curves on its surfaces - the outlines they make together, a set for each level. The tools\nand their curves go; reshape the new ones and the solid follows. A tool not touching it stays live."), _bake_btn))
	sb.add_child(ed._small("Make plain mesh", EditorIcons.tip("Make plain mesh", "", "The solid stops following its curves: a plain mesh from now on (editing its mesh, or a\nboolean, does this too). Undo brings the link back."), unlink_part))
	var neg: Button = ed._small("Negative", EditorIcons.tip("Negative", "", "Solids are positive (they add) unless you say so: this one made negative - cut from the solid\nit's in, live (both made from curves: reshape either's curves and the cut follows)."), make_negative)
	sb.add_child(neg)
	var rr := HBoxContainer.new()
	var rl := UI.label("Role", 14, UI.TEXT_DIM)
	rl.custom_minimum_size.x = 48
	rr.add_child(rl)
	var role := OptionButton.new()
	role.focus_mode = Control.FOCUS_NONE
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in ["New solid (positive)", "Cut the solid it's in", "Join the solid it's in", "Common with the solid it's in"]:
		role.add_item(t)
	role.tooltip_text = EditorIcons.tip("Role", "", "What this solid does: a solid of its own (positive - the default), or cut from / joined to /\nshared with the solid it's in - a live boolean, switchable later in that solid's recipe.")
	role.item_selected.connect(set_solid_role)
	rr.add_child(role)
	_panel_btns["w_role_row"] = rr
	var pos: Button = ed._small("Make the cut positive", EditorIcons.tip("Make the cut positive", "", "The latest cut in this solid undone as a cut: the cutter is a positive solid of its own again,\nwhere it was (its curves as they are)."), make_positive)
	sb.add_child(pos)
	_solid_box.add_child(sb)
	_solid_box.add_child(rr)
	_solid_box.move_child(rr, 2)
	# new tools for this solid: the picked curves, or another selected solid, as a cut / join / common
	var ar := HFlowContainer.new()
	ar.add_theme_constant_override("h_separation", 3)
	var al := UI.label("Add", 14, UI.TEXT_DIM)
	al.custom_minimum_size.x = 48
	ar.add_child(al)
	var aro := OptionButton.new()
	aro.focus_mode = Control.FOCUS_NONE
	for t in ["Cut", "Join", "Common"]:
		aro.add_item(t)
	aro.tooltip_text = EditorIcons.tip("New tool's role", "", "What the tool you add does to this solid: Cut (subtract), Join (union) or Common (intersect).")
	ar.add_child(aro)
	_panel_btns["w_add_role"] = aro
	ar.add_child(ed._small("Picked curves", EditorIcons.tip("Add the picked curves", "", "The picked curves made a new step of this solid: extruded both ways from their plane (this solid's\nheight - change it in the recipe), cutting / joined / in common as chosen. Live from then on."), add_tool_curves))
	ar.add_child(ed._small("Other solid", EditorIcons.tip("Add the other selected solid", "", "The other selected solid (Ctrl+click it in the view or the overview) made a new step of this one,\ncutting / joined / in common as chosen. Live when both are made from curves."), add_tool_solid))
	_solid_box.add_child(ar)
	_solid_box.move_child(ar, 3)
	_solid_box.visible = false
	box.add_child(_solid_box)
	_panel_btns["w_neg"] = neg
	_panel_btns["w_pos"] = pos
	var tr = _w("tree")
	box.move_child(_solid_box, (tr as Node).get_index() + 1 if tr and (tr as Node).get_parent() == box else 0)   # (under the overview)
	for k in [["solid_box", _solid_box], ["solid_label", _solid_label], ["solid_value_row", _solid_value_row], ["solid_value_label", _solid_value_label],
			["solid_value", _solid_value], ["solid_segs_row", _solid_segs_row], ["solid_segs", _solid_segs]]:
		_panel_btns["w_" + k[0]] = k[1]


# --- the overview: every solid and curve of the model, as a tree ----------------------------------

## The OVERVIEW at the top of the tab: the solids (each with the curves it's made from under it), the
## plain meshes, and the curves no solid uses. Click to select (Ctrl / Shift: more - solids and curves
## together: the same selection the view and the boxes below use); double-click a name to rename it;
## the eye hides or shows it.
func build_overview(box: VBoxContainer) -> void:
	box.add_child(EditorIcons.tipped(UI.section("OVERVIEW"), EditorIcons.tip("Overview", "Ctrl / Shift: more", "Every part, solid (its curves under it), mesh and curve of the model. Click a row to select it -\none or several - and edit it in the boxes below or the view; double-click a name to rename it;\nthe eye hides or shows it; right-click a row for its menu.")))
	var t := Tree.new()
	t.hide_root = true
	t.select_mode = Tree.SELECT_MULTI
	t.columns = 2
	t.set_column_expand(1, false)
	t.set_column_custom_minimum_width(1, 30)
	t.custom_minimum_size.y = 84
	t.add_theme_font_size_override("font_size", 14)
	t.tooltip_text = ""   # (each row its own tooltip - none for the list as a whole)
	t.set_meta("tip_fn", t.get_tooltip)   # (PinTips: the row's under the mouse)
	t.multi_selected.connect(_tree_selected)
	t.item_edited.connect(_tree_edited.bind(t))
	t.button_clicked.connect(_tree_button)
	t.allow_rmb_select = true
	t.item_mouse_selected.connect(_tree_click.bind(t))
	box.add_child(t)
	_panel_btns["w_tree"] = t


func _tree_sig() -> int:
	var sig := hash(sel)
	if ed == null or ed.model == null:
		return sig
	for g in groups():
		sig = hash([sig, g.get_instance_id(), str(g.name), g.visible])
	for p: MeshInstance3D in ed.parts():
		sig = hash([sig, p.get_instance_id(), str(p.name), p.visible, JSON.stringify(p.get_meta("curve_solid", {})), p in ed.selected_parts()])
	for c in curves:
		sig = hash([sig, c.get("id"), c.get("name"), c.get("hidden", false)])
	return sig


## The overview made again when what it shows changed.
func _fill_tree() -> void:
	var t = _w("tree")
	if t == null or ed.model == null:
		return
	var tree: Tree = t
	var sig := _tree_sig()
	if sig == int(tree.get_meta("sig", 0)):   # (kept on the tree: a panel built anew fills its own)
		return
	tree.set_meta("sig", sig)
	set_meta("tree_sync", true)
	tree.clear()
	var root := tree.create_item()
	var eye_on := EditorIcons.get_icon("eye")
	var eye_off := EditorIcons.get_icon("eye_off")
	var used := {}
	var selp: Array = ed.selected_parts()
	var groups := {}
	for g in [["solids", "Solids"], ["meshes", "Meshes"], ["curves", "Curves (not in a solid)"]]:
		var gi := tree.create_item(root)
		gi.set_text(0, g[1])
		gi.set_tooltip_text(0, {"solids": "The solids in no part: each with the curves it's made from under it.", "meshes": "The plain meshes in no part (made by hand, not from curves).",
			"curves": "Curves no solid is made from yet."}[g[0]])
		gi.set_selectable(0, false)
		gi.set_selectable(1, false)
		gi.set_custom_color(0, UI.TEXT_DIM)
		groups[g[0]] = gi
	# parts (groups) first: each with its solids and meshes under it
	var gitem := {}
	for g in groups():
		var gi := tree.create_item(root, 0)
		gi.set_text(0, str(g.name))
		gi.set_editable(0, true)
		gi.set_metadata(0, {"group": g})
		gi.set_tooltip_text(0, "A part: a group of solids (a part of the model - as in the Mesh tab). Click: select its solids.\nRight-click: more.")
		gi.add_button(1, eye_on if g.visible else eye_off, 0, false, "Hide / show this part.")
		gitem[g] = gi
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		var pg := group_of(p)
		var it := tree.create_item(gitem[pg] if pg and gitem.has(pg) else groups["solids" if not spec.is_empty() else "meshes"])
		it.set_text(0, str(p.name))
		it.set_editable(0, true)
		it.set_metadata(0, {"part": p})
		it.set_tooltip_text(0, "%s - %s. Click: select; double-click: rename." % [p.name, _spec_words(spec) if not spec.is_empty() else "a mesh"])
		it.add_button(1, eye_on if p.visible else eye_off, 0, false, "Hide / show this solid.")
		if p in selp:
			it.select(0)
		for id in spec_ids(spec):
			used[int(id)] = true
		_tree_steps(tree, it, p, spec, [])
	for i in curves.size():
		if used.has(int(curves[i].get("id", -1))):
			continue
		var ci := tree.create_item(groups["curves"])
		ci.set_text(0, str(curves[i].get("name", "Curve")))
		ci.set_editable(0, true)
		ci.set_metadata(0, {"curve": i})
		ci.set_tooltip_text(0, "A %s. Click: pick it (Ctrl / Shift: more)." % str(curves[i]["kind"]))
		ci.add_button(1, eye_off if curves[i].get("hidden", false) else eye_on, 0, false, "Hide / show this curve.")
		if i in sel:
			ci.select(0)
	# (as tall as its rows, no taller - 3 to 9 rows)
	var rows := 0
	var it2 := root.get_first_child()
	while it2:
		rows += 1
		it2 = it2.get_next_in_tree()
	tree.custom_minimum_size.y = clampi(rows, 3, 9) * 30 + 8
	set_meta("tree_sync", false)


# --- parts: groups of solids (a Node3D in the model, saved in the glb) -------------------------------

## `n` is a part - a group of solids / meshes (made here, or read back from a glb: its extras say so).
static func is_group(n: Node) -> bool:
	if n == null or not n is Node3D or n is MeshInstance3D:
		return false
	if n.has_meta("part_group"):
		return true
	var ex = n.get_meta("extras", {})
	return ex is Dictionary and bool(ex.get("atrapos_group", false))


## The model's parts (groups), in tree order.
func groups() -> Array:
	if ed == null or ed.model == null:
		return []
	return ed.model.find_children("*", "Node3D", true, false).filter(func(n): return is_group(n))


## The part (group) solid / mesh `p` is in (null: none).
func group_of(p: Node) -> Node3D:
	var n := p.get_parent() if p else null
	while n and n != ed.model:
		if is_group(n):
			return n
		n = n.get_parent()
	return null


## The solids and meshes in part `g`.
func group_parts(g: Node) -> Array:
	return ed.parts().filter(func(p): return g.is_ancestor_of(p))


func _mark_group(g: Node3D) -> void:
	g.set_meta("part_group", true)
	var ex: Dictionary = (g.get_meta("extras", {}) as Dictionary).duplicate() if g.get_meta("extras", {}) is Dictionary else {}
	ex["atrapos_group"] = true
	g.set_meta("extras", ex)


## `n` moved under `to` at `index` (-1: last), keeping where it is in the world.
static func _reparent(n: Node3D, to: Node, index := -1) -> void:
	var gx := n.global_transform
	n.get_parent().remove_child(n)
	to.add_child(n)
	if index >= 0:
		to.move_child(n, mini(index, to.get_child_count() - 1))
	n.owner = to.owner if to.owner else to
	n.global_transform = gx
	for c in n.find_children("*", "", true, false):
		c.owner = n.owner


## A new part made of solids / meshes `ps` (one undo step): a group they're moved into.
func make_group(ps: Array) -> Node3D:
	ps = ps.filter(func(p): return is_instance_valid(p) and p.get_parent())
	if ps.is_empty() or ed.model == null:
		ed._say("New part: select the solids / meshes to put in it.")
		return null
	var model: Node3D = ed.model
	var g := Node3D.new()
	g.name = ed._unique("Part")
	_mark_group(g)
	var was := []
	for p in ps:
		was.append([p, p.get_parent(), p.get_index()])
	var do_it := func():
		model.add_child(g)
		g.owner = model
		for w in was:
			_reparent(w[0], g)
		ed._fill_parts()
		ed.select_part(ps[0])
		_refresh_panel()
	var undo_it := func():
		for k in range(was.size() - 1, -1, -1):
			_reparent(was[k][0], was[k][1], was[k][2])
		model.remove_child(g)
		ed._fill_parts()
		_refresh_panel()
	ed._do("New part", do_it, undo_it, [g])
	ed._say("%s: %d solid%s in it." % [g.name, ps.size(), "" if ps.size() == 1 else "s"])
	return g


## Part `g` taken apart: its solids / meshes back where it is (one undo step).
func ungroup(g: Node3D) -> void:
	if not is_group(g):
		return
	var parent := g.get_parent()
	var at := g.get_index()
	var kids := g.get_children().filter(func(c): return c is Node3D)
	var do_it := func():
		for c in kids:
			_reparent(c, parent)
		parent.remove_child(g)
		ed._fill_parts()
		_refresh_panel()
	var undo_it := func():
		parent.add_child(g)
		parent.move_child(g, mini(at, parent.get_child_count() - 1))
		g.owner = ed.model
		for c in kids:
			_reparent(c, g)
		ed._fill_parts()
		_refresh_panel()
	ed._do("Ungroup", do_it, undo_it, [g])


## Solids / meshes `ps` moved into part `g` (null: out of any part, to the top). One undo step.
func move_to_group(ps: Array, g: Node3D) -> void:
	var to: Node = g if g else ed.model
	var was := []
	for p in ps:
		if is_instance_valid(p) and p.get_parent() != to:
			was.append([p, p.get_parent(), p.get_index()])
	if was.is_empty():
		return
	var do_it := func():
		for w in was:
			_reparent(w[0], to)
		ed._fill_parts()
		_refresh_panel()
	var undo_it := func():
		for k in range(was.size() - 1, -1, -1):
			_reparent(was[k][0], was[k][1], was[k][2])
		ed._fill_parts()
		_refresh_panel()
	ed._do("Move to " + (str(g.name) if g else "no part"), do_it, undo_it)


## Part `g` and what's in it deleted / duplicated (one undo step).
func delete_group(g: Node3D) -> void:
	var parent := g.get_parent()
	var at := g.get_index()
	ed._do("Delete part", func():
		parent.remove_child(g)
		if ed.part and g.is_ancestor_of(ed.part):
			ed.part = null
			ed.sel_parts = []
		ed._fill_parts()
		ed._show_part()
		_refresh_panel()
		ed.view.request(), func():
		parent.add_child(g)
		parent.move_child(g, mini(at, parent.get_child_count() - 1))
		ed._fill_parts()
		_refresh_panel()
		ed.view.request(), [g])


func duplicate_group(g: Node3D) -> void:
	var d: Node3D = g.duplicate()
	d.name = ed._unique(str(g.name))
	_mark_group(d)
	var parent := g.get_parent()
	ed._do("Duplicate part", func():
		parent.add_child(d)
		d.owner = ed.model
		for c in d.find_children("*", "", true, false):
			c.owner = ed.model
		ed._fill_parts()
		_refresh_panel()
		ed.view.request(), func():
		parent.remove_child(d)
		ed._fill_parts()
		_refresh_panel()
		ed.view.request(), [d])


## Part `g`'s solids and meshes selected.
func select_group(g: Node3D) -> void:
	var ps := group_parts(g)
	if ps.is_empty():
		return
	ed.select_part(ps[0])
	for k in range(1, ps.size()):
		ed.select_part(ps[k], true)


## The Mesh tab's parts list's right-click menu (a part / group row): the common actions.
func parts_menu(target: Node) -> PopupMenu:
	var pm := _new_menu()
	var acts: Array = pm.get_meta("acts")
	var add := func(menu: PopupMenu, text: String, act: Callable, on := true):
		menu.add_item(text, acts.size())
		menu.set_item_disabled(menu.item_count - 1, not on)
		acts.append(act)
	if is_group(target):
		var g: Node3D = target
		add.call(pm, "Select its solids", select_group.bind(g))
		add.call(pm, "Rename", start_rename.bind(g))
		add.call(pm, "Show" if not g.visible else "Hide", _act_toggle_node.bind(g))
		add.call(pm, "Duplicate", duplicate_group.bind(g))
		add.call(pm, "Ungroup", ungroup.bind(g))
		add.call(pm, "Delete (with its solids)", delete_group.bind(g))
	elif target is MeshInstance3D:
		var p: MeshInstance3D = target
		var sel_ps: Array = ed.selected_parts() if p in ed.selected_parts() else [p]
		add.call(pm, "Rename", start_rename.bind(p))
		add.call(pm, "Show" if not p.visible else "Hide", _act_toggle_node.bind(p))
		add.call(pm, "Duplicate", _act_part.bind(p, "duplicate"))
		add.call(pm, "Delete", _act_part.bind(p, "delete"))
		add.call(pm, "Bake (its tools into its curves)", _act_part.bind(p, "bake"), can_bake(p))
		pm.add_separator()
		add.call(pm, "New part from the selected (%d)" % sel_ps.size(), make_group.bind(sel_ps))
		var sub := PopupMenu.new()
		sub.add_theme_font_size_override("font_size", 14)
		for g in groups():
			if g != group_of(p):
				sub.add_item(str(g.name), acts.size())
				acts.append(move_to_group.bind(sel_ps, g))
		if group_of(p):
			sub.add_item("(no part - the top)", acts.size())
			acts.append(move_to_group.bind(sel_ps, null))
		sub.id_pressed.connect(_menu_act)
		pm.add_submenu_node_item("Move to", sub)
		pm.set_item_disabled(pm.item_count - 1, sub.item_count == 0)
	return pm


func _new_menu() -> PopupMenu:
	var old = get_meta("tree_menu") if has_meta("tree_menu") else null
	if old and is_instance_valid(old):
		old.queue_free()
	var pm := PopupMenu.new()
	pm.name = "OverviewMenu"
	pm.add_theme_font_size_override("font_size", 14)
	pm.set_meta("acts", [])
	pm.id_pressed.connect(_menu_act)
	ed.add_child(pm)
	set_meta("tree_menu", pm)
	return pm


func _act_toggle_node(n: Node3D) -> void:
	n.visible = not n.visible
	ed._place_ghosts()
	ed._fill_parts()
	ed.view.request()
	_refresh_panel()


## The Mesh tab's parts list: a right click on a row - its menu.
func parts_click(_pos: Vector2, button: int, t: Tree) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var it := t.get_selected()
	if it == null or not it.get_metadata(0) is Node:
		return
	parts_menu(it.get_metadata(0)).popup(Rect2i(Vector2i(t.get_global_mouse_position()), Vector2i.ZERO))


## A part / group renamed in the Mesh tab's list (double-click).
func parts_renamed(t: Tree) -> void:
	var it := t.get_edited()
	if it == null or not it.get_metadata(0) is Node:
		return
	var n: Node = it.get_metadata(0)
	var text := it.get_text(0).replace("  (mirror)", "").replace("  (bound)", "").strip_edges().validate_node_name()
	if text == "" or text == str(n.name):
		ed._fill_parts()
		return
	var old := str(n.name)
	ed._do("Rename", func(): n.name = text; ed._fill_parts(); _refresh_panel(), func(): n.name = old; ed._fill_parts(); _refresh_panel())


## Rename (the menus' Rename, F2): `target`'s row - a node in the Mesh tab's list, or a
## {"group"|"part"|"curve": ...} row in the overview - opened for typing, holding its plain name.
func start_rename(target) -> void:
	var t: Tree = ed._parts if target is Node else _w("tree")
	if t == null:
		return
	var it := _find_row(t.get_root(), target)
	if it == null or not it.is_editable(0):
		return
	var plain := ""
	if target is Node:
		plain = str(target.name)
	elif target.has("group"):
		plain = str(target["group"].name)
	elif target.has("part"):
		plain = str(target["part"].name)
	elif target.has("curve") and int(target["curve"]) < curves.size():
		plain = str(curves[int(target["curve"])].get("name", ""))
	var was: bool = ed._syncing
	ed._syncing = true   # (selecting the row: no list rebuilt under the typing)
	set_meta("tree_sync", true)
	it.uncollapse_tree()
	t.set_selected(it, 0)
	ed._syncing = was
	set_meta("tree_sync", false)
	it.set_text(0, plain)
	t.scroll_to_item(it)
	t.edit_selected(true)


func _find_row(it: TreeItem, target) -> TreeItem:
	if it == null:
		return null
	var m = it.get_metadata(0)
	if target is Node:
		if m is Node and m == target:
			return it
	elif m is Dictionary and not m.has("step"):
		var same := true
		for k in target:
			if not m.has(k) or typeof(m[k]) != typeof(target[k]) or m[k] != target[k]:
				same = false
		if same:
			return it
	for c in it.get_children():
		var r := _find_row(c, target)
		if r:
			return r
	return null


## F2: the selection renamed - the part moving as one (a group) or the selected solid; in the
## overview when the Curve modeling tab is shown, else in the Mesh tab's list.
func rename_selected() -> void:
	if ed.part == null:
		return
	var ns: Array = ed.xf_nodes()
	var n: Node3D = ns[0] if ns.size() == 1 else ed.part
	if ed.curve_tab_shown():
		start_rename({"group": n} if is_group(n) else {"part": n})
	else:
		start_rename(n)


# --- bake: a solid's recipe worked out into curves of its own ------------------------------------

## Bake solid `p` (the selected one): its tools (the solids cut from it / joined to it / in common
## with it) and the curves it's made from worked out into the outlines they make together - new
## curves on its surfaces, one set a level (a pocket, a step: a level of its own), each level an
## extrusion of them. The tools go, and the curves they and it were made from (unless another solid
## uses them); the new curves are ordinary curves - reshape them and the solid follows. A tool that
## doesn't touch the solid isn't baked (it stays a step of it, its curves kept), nor one that's
## not an extrusion along the solid's own axis (it - and the steps after it - stay live). One undo step.
func bake_solid(p: MeshInstance3D = null) -> bool:
	return bake_edges(p)


## (The bake before its curves were the solid's edges: pieces between bottom and top curves.)
func bake_solid_pieces(p: MeshInstance3D = null) -> bool:
	if p == null:
		p = ed.part
	if p == null or not is_instance_valid(p) or not p.has_meta("curve_solid"):
		ed._say("Bake: select a solid made from curves.")
		return false
	var spec: Dictionary = p.get_meta("curve_solid")
	# (every other solid made from curves, where it is from this one: one touching it is baked in too)
	var extra := []
	for q: MeshInstance3D in ed.parts():
		if q != p and q.has_meta("curve_solid") and q.is_visible_in_tree():
			extra.append({"part": q, "b": q.get_meta("curve_solid"), "b_xf": xf_arr(p.global_transform.affine_inverse() * q.global_transform)})
	var plan := bake_plan(spec, extra)
	if plan.has("error"):
		ed._say("Bake: " + str(plan["error"]))
		return false
	var before := _state()
	var used_elsewhere := {}
	var merged: Array = plan.get("merged", [])
	for q: MeshInstance3D in ed.parts():
		if q != p and q.has_meta("curve_solid") and not q in merged:
			for id in spec_ids(q.get_meta("curve_solid")):
				used_elsewhere[int(id)] = true
	for id in plan["keep_ids"]:
		used_elsewhere[int(id)] = true
	var gone := {}
	for id in plan["gone_ids"]:
		if not used_elsewhere.has(int(id)):
			gone[int(id)] = true
	var kept := []
	for c in curves:
		if not gone.has(int(c.get("id", -1))):
			kept.append(c)
	# (one solid, its curves its edges: each piece of it - the body, a hole, a recess - a curve on its
	# bottom edge and one on its top edge; the piece made between them; the body's pieces joined, the
	# holes and recesses taken out)
	var ids := []
	var pieces := []
	var h0 := absf(float(plan["items"][0]["h"]))
	var old_name := str(p.name)
	var new_name := old_name
	if RegEx.create_from_string("^(Extrusion|Solid)\\d*$").search(old_name):
		new_name = str(ed._unique("Baked"))   # (its kind's name: a baked solid now)
	var counts := {}
	var nrm: Vector3 = Vector3.UP
	for item: Dictionary in plan["items"]:
		var c: Dictionary = item["c"]
		c.erase("hole")
		var hole: bool = item["role"] == "cut"
		var what: String = ("hole" if absf(absf(float(item["h"])) - h0) < 1e-6 else "recess") if hole else "outline"
		counts[what] = int(counts.get(what, 0)) + 1
		nrm = (c.get("n", Vector3.UP) as Vector3).normalized()
		var h := float(item["h"])
		var a := c.duplicate(true)   # (at its plane)
		var b := baked(c, Transform3D(Basis(), nrm * h))   # (the other end)
		b["n"] = c.get("n", Vector3.UP)
		var lo := a if h > 0.0 else b
		var hi := b if h > 0.0 else a
		var ends := []
		for e in [[lo, "bottom"], [hi, "top"]]:
			var nc := _fresh((e[0] as Dictionary).duplicate(true))
			nc["name"] = "%s %s %d %s" % [new_name, what, counts[what], e[1]]
			kept.append(nc)
			ids.append(int(nc["id"]))
			ends.append(int(nc["id"]))
		pieces.append({"role": item["role"], "loops": [ends]})
	var core := {"kind": "baked", "ids": ids, "pieces": pieces, "segs": int(plan["segs"]), "axis": -1}
	for st: Dictionary in plan["live"]:
		core = {"kind": "bool", "op": st["op"], "a": core, "b": st["b"], "b_xf": st["b_xf"]}
	curves = kept
	sel = []
	var after := _state()
	var out := []   # (the solids baked in: out of the model - undo puts them back where they were)
	for q: MeshInstance3D in merged:
		out.append([q, q.get_parent(), q.get_index()])
	_bake_set(p, after, core, new_name, out, true)
	ed._push("Bake solid", _bake_set.bind(p, before, spec, old_name, out, false), _bake_set.bind(p, after, core, new_name, out, true))
	var left := int(plan["skipped"])
	ed._say("Baked: one solid, its %d edge curves%s." % [ids.size(),
		(" - %d tool%s left live (not touching it, or not along its axis)" % [left, "" if left == 1 else "s"]) if left > 0 else ""])
	return true


## Solid `p` can be baked: any solid made from curves (a baked one: to take in solids touching it).
func can_bake(p: MeshInstance3D) -> bool:
	var spec: Dictionary = p.get_meta("curve_solid", {}) if is_instance_valid(p) else {}
	return not spec.is_empty()


## Bake solid `p` (the selected one): the solid as it is - its tools worked in - and every other solid
## touching it (overlapping or meeting it) joined into one mesh, and that mesh's edges (where its faces
## meet at an angle) traced into curves - each edge one curve, corner to corner or a closed loop, with as
## few points as keep its shape. The curves are the solid's edges: move a point and that edge of the
## mesh moves, the faces at it follow; a corner shared by edges moves with all of them. Its old curves
## and the solids baked in go. One undo step.
func bake_edges(p: MeshInstance3D = null) -> bool:
	if p == null:
		p = ed.part
	if p == null or not is_instance_valid(p) or not p.has_meta("curve_solid") or p.mesh == null:
		ed._say("Bake: select a solid made from curves.")
		return false
	var spec: Dictionary = p.get_meta("curve_solid")
	var MB: GDScript = load("res://scripts/editor/mesh/mesh_bool.gd")
	var m: ArrayMesh = p.mesh
	var box := m.get_aabb()
	var merged := []
	for q: MeshInstance3D in ed.parts():
		if q == p or not q.has_meta("curve_solid") or not q.is_visible_in_tree() or q.mesh == null:
			continue
		var rel := p.global_transform.affine_inverse() * q.global_transform
		var qb: AABB = rel * q.mesh.get_aabb()
		if not box.grow(1e-3).intersects(qb):
			continue   # (nowhere near it: not part of the bake)
		var r: Dictionary = MB.run(m, q.mesh, rel, "union")
		var ms: Array = r.get("meshes", [])
		if str(r.get("error", "")) != "" or ms.is_empty():
			continue
		var u: ArrayMesh = ms[ms.size() - 1]
		var overlap := Shapes.volume(m) + Shapes.volume(q.mesh) - Shapes.volume(u)
		var touching := box.intersection(qb).get_volume() < 1e-9   # (only meeting - face to face)
		if overlap < 1e-9 and not touching:
			continue   # (near, not touching: not part of it)
		m = u
		box = m.get_aabb()
		merged.append(q)
	var base := auto_smooth(m) if not merged.is_empty() or str(spec.get("kind", "")) == "bool" else m
	for si in base.get_surface_count():
		base.surface_set_material(si, p.mesh.surface_get_material(mini(si, p.mesh.get_surface_count() - 1)))
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var net: Dictionary = EN.trace(base)
	if (net["chains"] as Array).is_empty():
		ed._say("Bake: no edges to make curves of.")
		return false
	var before := _state()
	# the curves it and the solids baked in were made from go (unless another solid uses them)
	var used_elsewhere := {}
	for q: MeshInstance3D in ed.parts():
		if q != p and q.has_meta("curve_solid") and not q in merged:
			for id in spec_ids(q.get_meta("curve_solid")):
				used_elsewhere[int(id)] = true
	var gone := {}
	for id in spec_ids(spec):
		gone[int(id)] = true
	for q in merged:
		for id in spec_ids(q.get_meta("curve_solid")):
			gone[int(id)] = true
	var kept := []
	for c in curves:
		var id := int(c.get("id", -1))
		if not gone.has(id) or used_elsewhere.has(id):
			kept.append(c)
	var old_name := str(p.name)
	var new_name := old_name
	if RegEx.create_from_string("^(Extrusion|Solid|Baked)\\d*$").search(old_name):
		new_name = old_name if old_name.begins_with("Baked") else str(ed._unique("Baked"))
	var ids := []
	var chains := []
	var c0 := {}
	var i := 0
	for ch: Dictionary in net["chains"]:
		var pts: PackedVector3Array = ch["pts"]
		var c: Dictionary = EN.chain_curve(pts, bool(ch["closed"]))
		c = _fresh(c)
		i += 1
		c["name"] = "%s edge %d" % [new_name, i]
		kept.append(c)
		var id := int(c["id"])
		ids.append(id)
		var pa := []
		for q in pts:
			pa.append([q.x, q.y, q.z])
		chains.append({"id": id, "pts": pa, "t": Array(EN.params(pts, c))})
		c0[str(id)] = to_json([c])[0]
	var net_id := int(Time.get_ticks_usec() % 2000000000)
	for ci in chains.size():
		chains[ci]["closed"] = bool(net["chains"][ci]["closed"])
	# (a clean, even mesh - its edges kept exactly;
	# each edge point placed along its curve)
	var area := 0.0
	for si in base.get_surface_count():
		var sa := base.surface_get_arrays(si)
		var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
		var sx: PackedInt32Array = sa[Mesh.ARRAY_INDEX] if sa[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
		for ti in range(0, sx.size(), 3):
			area += (sv[sx[ti + 1]] - sv[sx[ti]]).cross(sv[sx[ti + 2]] - sv[sx[ti]]).length() * 0.5
	var L := clampf(sqrt(area / 380.0), 0.003, 1.0)   # (a few thousand triangles, whatever its size - splitting leaves them about half this across)
	var rm: Dictionary = EN.quad_mesh(base, net["chains"], L * 0.6)   # (walls as rows of quads between their edges)
	if rm.is_empty():
		rm = EN.remesh(base, net["chains"], L)   # (not a solid standing along one axis: an even mesh)
	var vv: PackedVector3Array = rm["v"]
	var fv := []
	for ci in chains.size():
		var vis: Array = (rm["chains"][ci] as Array).filter(func(x): return x >= 0)
		var pts := PackedVector3Array()
		for vi in vis:
			pts.append(vv[vi])
		var cur: Dictionary = from_json([c0[str(int(chains[ci]["id"]))]])[0]
		var ts: PackedFloat32Array = EN.params(pts, cur)
		for j in vis.size():
			fv.append([vis[j], ci, ts[j]])
	var flat := []
	for q in vv:
		flat.append_array([q.x, q.y, q.z])
	for ch in chains:
		ch.erase("pts")
		ch.erase("t")
	var core := {"kind": "edges", "ids": ids, "net": net_id, "chains": chains, "c0": c0, "mesh": {"v": flat, "t": Array(rm["t"])}, "fv": fv}
	if rm.has("axis"):
		core["up"] = rm["axis"]   # (the way it stands - its walls along it)
	curves = kept
	sel = []
	var after := _state()
	var out := []   # (the solids baked in: out of the model - undo puts them back where they were)
	for q: MeshInstance3D in merged:
		out.append([q, q.get_parent(), q.get_index()])
	_bake_set(p, after, core, new_name, out, true)
	ed._push("Bake solid", _bake_set.bind(p, before, spec, old_name, out, false), _bake_set.bind(p, after, core, new_name, out, true))
	ed._say("Baked: one solid, %d edge curves%s." % [ids.size(), (" - %d solid%s touching it joined in" % [merged.size(), "" if merged.size() == 1 else "s"]) if not merged.is_empty() else ""])
	return true


## The meshes baked solids' edges move (by their net id; kept for the session - after a load, the
## part's mesh as it was saved).
func _edge_bases() -> Dictionary:
	if not has_meta("edge_bases"):
		set_meta("edge_bases", {})
	return get_meta("edge_bases")


## A baked solid's mesh with its edges where its curves are now.
func edge_solid(p: MeshInstance3D, spec: Dictionary) -> ArrayMesh:
	if spec.has("mesh"):
		return _edge_mesh(p, spec)
	var bases := _edge_bases()
	var nid := int(spec.get("net", 0))
	if not bases.has(nid):
		bases[nid] = p.mesh   # (opened from a file: as it was saved - its curves then were its curves now)
	var old := {}
	var c0: Dictionary = spec.get("c0", {})
	for k in c0:
		var cs := from_json([c0[k]])
		if not cs.is_empty():
			old[int(k)] = cs[0]
	var now := {}
	for id in spec.get("ids", []):
		var c := curve_by_id(int(id))
		if not c.is_empty():
			now[int(id)] = c
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	if not spec.has("faces"):
		return EN.deform(bases[nid], spec.get("chains", []), old, now)
	var mat: Material = p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null
	var moved: Array = EN.moved_arrays(bases[nid], spec.get("chains", []), old, now)
	return EN.build(spec["faces"], spec.get("chains", []), now, moved, mat)


## A baked solid's even mesh with its edges where its curves are now: the edge points moved as their
## curves moved, every other point blended smoothly from them (from last time's blend: a drag is quick).
func _edge_mesh(p: MeshInstance3D, spec: Dictionary) -> ArrayMesh:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var nid := int(spec.get("net", 0))
	var caches := _edge_bases()
	var c: Dictionary = caches.get(nid, {}) if caches.get(nid) is Dictionary else {}
	var mv: Array = spec["mesh"]["v"]
	if c.is_empty() or int(c.get("n", -1)) != mv.size():
		var v := PackedVector3Array()
		for i in range(0, mv.size(), 3):
			v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
		var t := PackedInt32Array(spec["mesh"]["t"])
		c = {"n": mv.size(), "v": v, "t": t, "nb": EN.neighbours(t, v.size()), "last": PackedVector3Array()}
		caches[nid] = c
	var old := {}
	var c0: Dictionary = spec.get("c0", {})
	for k in c0:
		var cs := from_json([c0[k]])
		if not cs.is_empty():
			old[int(k)] = cs[0]
	var now := {}
	for id in spec.get("ids", []):
		var cv := curve_by_id(int(id))
		if not cv.is_empty():
			now[int(id)] = cv
	var v0: PackedVector3Array = c["v"]
	if not spec.get("tied", false):
		# (points on its edges not yet theirs - a wall's rows up a side edge: made theirs, once)
		var tt: PackedInt32Array = c["t"]
		var tied = EN.tie_edges(v0, tt, spec.get("fv", []), spec.get("chains", []), old)
		if tied != null:
			tt = tied["t"]
			spec["fv"] = tied["fv"]
			spec["mesh"]["t"] = Array(tt)
			c["t"] = tt
			c["nb"] = EN.neighbours(tt, v0.size())
			c.erase("bw")
			c.erase("cg")
			c.erase("r_last")
		spec["tied"] = true
	if not spec.get("qcaps", false):
		# (flat faces made of quads, once: an edge moved, they follow cleanly - its seams closed first, so
		# each face's rim has every point its neighbours put on their shared edges)
		var cs0: Dictionary = EN.close_seams(v0, c["t"], spec.get("fv", []))
		if not cs0.is_empty():
			c["t"] = cs0["t"]
			spec["fv"] = cs0["fv"]
		var tt: PackedInt32Array = c["t"]
		var area := 0.0
		for i in range(0, tt.size(), 3):
			area += (v0[tt[i + 1]] - v0[tt[i]]).cross(v0[tt[i + 2]] - v0[tt[i]]).length() * 0.5
		var L := clampf(sqrt(area / 380.0), 0.003, 1.0) * 0.6
		var feat0: Dictionary = EN.feature_edges(v0, tt, spec.get("fv", []), spec.get("chains", []), old)
		var upa: Array = spec.get("up", [0, 0, 0])
		var rf: Dictionary = EN.quad_caps(v0, tt, spec.get("fv", []), feat0, L, Vector3(upa[0], upa[1], upa[2]).normalized() if Vector3(upa[0], upa[1], upa[2]) != Vector3.ZERO else Vector3.ZERO, spec.get("chains", []))
		if not rf.is_empty():
			v0 = rf["v"]
			tt = rf["t"]
			spec["fv"] = rf["fv"]
			var flat := []
			for q in v0:
				flat.append_array([q.x, q.y, q.z])
			spec["mesh"]["v"] = flat
			spec["mesh"]["t"] = Array(tt)
			c["v"] = v0
			c["t"] = tt
			c["n"] = flat.size()
			c["nb"] = EN.neighbours(tt, v0.size())
			c.erase("bw")
			c.erase("cg")
			c.erase("r_last")
			c["last"] = PackedVector3Array()
		spec["qcaps"] = true
	if not spec.get("sealed", false):
		# (edges where the faces either side had their points in different places: closed, once)
		var cs: Dictionary = EN.close_seams(v0, c["t"], spec.get("fv", []))
		if not cs.is_empty():
			c["t"] = cs["t"]
			spec["fv"] = cs["fv"]
			spec["mesh"]["t"] = Array(cs["t"])
			c["nb"] = EN.neighbours(cs["t"], v0.size())
			c.erase("bw")
			c.erase("cg")
			c.erase("r_last")
		spec["sealed"] = true
	if not spec.get("oriented", false):
		# (every triangle turned outwards, once - one turned inside out shows as a dark notch)
		var ot: PackedInt32Array = EN.orient(v0, c["t"])
		if ot != (c["t"] as PackedInt32Array):
			c["t"] = ot
			spec["mesh"]["t"] = Array(ot)
			c.erase("bw")
			c.erase("cg")
			c.erase("r_last")
			if c.has("bw_job"):
				WorkerThreadPool.wait_for_task_completion(int(c["bw_job"][0]))
				c.erase("bw_job")
		spec["oriented"] = true
	var moves: Dictionary = EN.edge_moves(spec.get("fv", []), spec.get("chains", []), old, now, v0)
	var still := true
	for vi in moves:
		if (moves[vi] as Vector3).length_squared() > 1e-14:
			still = false
			break
	if c.has("bw_job") and (WorkerThreadPool.is_task_completed(int(c["bw_job"][0])) or not still):
		# (the weights worked out in the background: taken - waited for if a drag's already begun)
		WorkerThreadPool.wait_for_task_completion(int(c["bw_job"][0]))
		c["bw"] = c["bw_job"][1][0]
		c.erase("bw_job")
		c.erase("cg")
		c.erase("r_last")
	if not c.has("bw"):   # (each face's points, and each inside point's edge points and weights: once)
		var all_edge := {}
		var fvl: Array = spec.get("fv", [])
		for e in fvl:
			all_edge[int(e[0])] = true
		# (the solid's edges: the mesh's own edges lying along a curve - between two of its points, its
		# middle on the curve too; the faces either side of an edge may each have their own points on it)
		var feat: Dictionary = EN.feature_edges(v0, c["t"], fvl, spec.get("chains", []), old)
		var ax: Array = spec.get("up", [0, 0, 0])
		c["edge"] = all_edge
		if still and not c.has("bw_job"):
			# (just settled - nothing moves yet: drawn as it is, the weights for the next drag worked out
			# on a worker meanwhile - letting go never waits for them)
			var holder := [null]
			var vv := v0.duplicate()
			var tt2: PackedInt32Array = (c["t"] as PackedInt32Array).duplicate()
			var up3 := Vector3(ax[0], ax[1], ax[2])
			var job := WorkerThreadPool.add_task(func(): holder[0] = EN.blend_weights(vv, tt2, all_edge.duplicate(), feat.duplicate(), up3))
			c["bw_job"] = [job, holder]
			c["last"] = PackedVector3Array()
			c["pv"] = v0
			var fo: PackedInt32Array = EN.face_of(v0, c["t"], feat)
			c["t_draw"] = c["t"]
			return EN.shaded(v0, c["t"], fo, p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null)
		if not c.has("bw"):
			c["bw"] = EN.blend_weights(v0, c["t"], all_edge, feat, Vector3(ax[0], ax[1], ax[2]))
	if not c.has("edge"):
		var all_e := {}
		for e in spec.get("fv", []):
			all_e[int(e[0])] = true
		c["edge"] = all_e
	if c.has("bw_job"):
		WorkerThreadPool.wait_for_task_completion(int(c["bw_job"][0]))
		c["bw"] = c["bw_job"][1][0]
		c.erase("bw_job")
		c.erase("cg")
		c.erase("r_last")
	for vi in c["edge"]:
		if not moves.has(vi):
			moves[vi] = Vector3.ZERO   # (an edge point whose curve didn't move: held)
	if not c.has("cg"):
		c["cg"] = EN.cg_setup(v0, c["t"], c["bw"])
	# (solved smooth: a drag goes on from the last frame's solution, a few dozen rounds a frame; settling
	# - the drag let go - all the way)
	var full := bool(get_meta("cg_full", false))
	var sol: Dictionary = EN.cg_moves(v0.size(), c["cg"], c["bw"], moves, c.get("r_last", PackedVector3Array()), 2000 if full else 40, 1e-6 if full else 1e-4)
	var d: PackedVector3Array = sol["d"]
	c["r_last"] = sol["r"]
	c["last"] = d
	var pv := PackedVector3Array()
	pv.resize(v0.size())
	for i in v0.size():
		pv[i] = v0[i] + d[i]
	pv = EN.untangle(pv, v0, c["t"], c["nb"], c["edge"])   # (no triangle turned over where an edge pushed in)
	var ff: Dictionary = EN.flip_fix(pv, v0, c["t"], c["bw"]["tri_face"])
	c["pv"] = pv
	c["t_draw"] = ff["t"]
	# (shaded by its faces: smooth across each, sharp at its edges)
	return EN.shaded(pv, ff["t"], ff["face"], p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null)


## After an edit (a drag let go, a point put in...): each baked solid whose edges changed settled - its
## mesh made from its shape now, even and fine enough, quads kept (EdgeNet.settle) - and that its new
## start (its curves now its curves as made).
func settle_edges() -> void:
	if ed == null or ed.model == null:
		return
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if str(spec.get("kind", "")) != "edges" or not spec.has("mesh"):
			continue
		var c0: Dictionary = spec.get("c0", {})
		var now := {}
		var moved := false
		for id in spec.get("ids", []):
			var cv := curve_by_id(int(id))
			if cv.is_empty():
				continue
			now[int(id)] = cv
			if c0.has(str(int(id))) and JSON.stringify(to_json([cv])[0]) != JSON.stringify(c0[str(int(id))]):
				moved = true
		if not moved:
			continue
		# (its shape solved all the way first - not a drag frame's few rounds)
		set_meta("cg_full", true)
		p.remove_meta("curve_solid_key")
		refresh_solids()
		remove_meta("cg_full")
		var cache: Dictionary = _edge_bases().get(int(spec.get("net", 0)), {}) if _edge_bases().get(int(spec.get("net", 0))) is Dictionary else {}
		if cache.is_empty() or not cache.has("pv"):
			continue
		var pv: PackedVector3Array = cache["pv"]
		var td: PackedInt32Array = cache["t_draw"]
		var area := 0.0
		for i in range(0, td.size(), 3):
			area += (pv[td[i + 1]] - pv[td[i]]).cross(pv[td[i + 2]] - pv[td[i]]).length() * 0.5
		var L := clampf(sqrt(area / 380.0), 0.003, 1.0) * 0.6
		var r: Dictionary = EN.settle(pv, td, spec.get("fv", []), spec.get("chains", []), now, 25.0, L * 0.35)
		var nv: PackedVector3Array = r["v"]
		var flat := []
		for q in nv:
			flat.append_array([q.x, q.y, q.z])
		spec = spec.duplicate(true)
		spec["mesh"] = {"v": flat, "t": Array(r["t"])}
		spec["fv"] = r["fv"]
		var cz := {}
		for id in now:
			cz[str(int(id))] = to_json([now[id]])[0]
		spec["c0"] = cz
		spec["tied"] = true
		spec["qcaps"] = true
		spec["sealed"] = true
		spec.erase("oriented")   # (turned outwards again on its next drawing)
		_edge_bases().erase(int(spec.get("net", 0)))
		p.set_meta("curve_solid", spec)
		p.remove_meta("curve_solid_key")
	refresh_solids()


## Before a save: each baked solid's edges made its own again from where they are now (its mesh as it
## is, its curves as they are) - what's saved opens as it was.
func rebase_edges() -> void:
	if ed == null or ed.model == null:
		return
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if str(spec.get("kind", "")) != "edges":
			continue
		spec = spec.duplicate(true)
		if spec.has("mesh"):
			# (the even mesh as it is now - its points where they've been moved - and its curves now)
			var cache: Dictionary = _edge_bases().get(int(spec.get("net", 0)), {}) if _edge_bases().get(int(spec.get("net", 0))) is Dictionary else {}
			if not cache.is_empty() and not (cache["last"] as PackedVector3Array).is_empty():
				var v0: PackedVector3Array = cache["v"]
				var d: PackedVector3Array = cache["last"]
				var flat := []
				for i in v0.size():
					var q := v0[i] + d[i]
					flat.append_array([q.x, q.y, q.z])
				spec["mesh"]["v"] = flat
				_edge_bases().erase(int(spec.get("net", 0)))
			var cz := {}
			for id in spec.get("ids", []):
				var cv := curve_by_id(int(id))
				if not cv.is_empty():
					cz[str(int(id))] = to_json([cv])[0]
			spec["c0"] = cz
			p.set_meta("curve_solid", spec)
			p.set_meta("curve_solid_key", _solid_key(spec))
			continue
		var c0: Dictionary = spec.get("c0", {})
		for ch: Dictionary in spec.get("chains", []):
			var id := int(ch["id"])
			var c := curve_by_id(id)
			var olds := from_json([c0.get(str(id), {})]) if c0.has(str(id)) else []
			if c.is_empty() or olds.is_empty():
				continue
			var pts: Array = ch["pts"]
			for i in pts.size():
				var q: Vector3 = EN._v3(pts[i]) + (EN.at(c, float(ch["t"][i])) - EN.at(olds[0], float(ch["t"][i])))
				pts[i] = [q.x, q.y, q.z]
			c0[str(id)] = to_json([c])[0]
		spec["c0"] = c0
		_edge_bases()[int(spec.get("net", 0))] = p.mesh
		p.set_meta("curve_solid", spec)
		p.set_meta("curve_solid_key", _solid_key(spec))


func _bake_btn() -> void:
	bake_solid()


func _bake_set(p: MeshInstance3D, st: Array, spec: Dictionary, nm := "", parts_out := [], gone := false) -> void:
	for e in parts_out:
		var q: Node = e[0]
		if not is_instance_valid(q):
			continue
		if gone and q.get_parent():
			q.get_parent().remove_child(q)
		elif not gone and q.get_parent() == null and is_instance_valid(e[1]):
			(e[1] as Node).add_child(q)
			(e[1] as Node).move_child(q, mini(int(e[2]), (e[1] as Node).get_child_count() - 1))
	if gone and not parts_out.is_empty():
		ed.sel_parts = (ed.sel_parts as Array).filter(func(q): return is_instance_valid(q) and q.is_inside_tree())
		if is_instance_valid(p):
			ed.select_part(p)
	if is_instance_valid(p):
		p.set_meta("curve_solid", spec)
		if nm != "":
			p.name = nm
		ed._fill_parts()
	_set_state(st)
	var t = _w("tree")
	if t:
		(t as Node).set_meta("sig", 0)
	_refresh_panel()


## What baking recipe `spec` makes: {levels: [{lo, hi, curves}], live: [steps kept], gone_ids, keep_ids,
## skipped, segs} or {error}.
func bake_plan(spec: Dictionary, extra := []) -> Dictionary:
	var chain := []   # the steps on top of the base, first to last: {op, b, b_xf}
	var base := spec
	while str(base.get("kind", "")) == "bool":
		chain.push_front({"op": str(base.get("op", "difference")), "b": base.get("b", {}), "b_xf": base.get("b_xf", [])})
		base = base.get("a", {})
	if base.has("pieces"):
		if chain.is_empty() and extra.is_empty():
			return {"error": "it's baked already - its curves are its edges: reshape them."}
		return {"error": "it's baked already: its edges are its own curves (bake the other solids into it from them)."}
	if not str(base.get("kind", "")) in ["extrude", "baked"]:
		return {"error": "only extrusions bake (this solid is a %s)." % str(base.get("kind", "?"))}
	var cs0 := curves_of(base.get("ids", []))
	if cs0.is_empty():
		return {"error": "its curves are gone."}
	var n: Vector3 = (cs0[0].get("n", Vector3.UP) as Vector3).normalized()
	var u := _any_perp(n)
	var v := n.cross(u)
	var bk := {"n": n, "u": u, "v": v, "prisms": []}
	var bt = _bake_leaf(base, Transform3D(), bk)
	if bt == null:
		return {"error": "its curves must be closed and flat across its axis."}
	var gone := spec_ids(base)
	var keep := []
	var live := []
	var skipped := 0
	var stop := false
	for st: Dictionary in chain:
		var b_tree = null if stop else _bake_tree(st["b"], xf_of(st["b_xf"]), bk)
		if b_tree == null:
			stop = true   # (not along the axis / not an extrusion: it - and all after it - stay live)
		elif not _bake_touch(bt, b_tree, bk):
			b_tree = null   # (it doesn't touch the solid: not part of the bake)
		if b_tree == null:
			live.append(st)
			keep.append_array(spec_ids(st["b"]))
			skipped += 1
			continue
		bt = {"op": st["op"], "a": bt, "b": b_tree}
		gone.append_array(spec_ids(st["b"]))
	# other solids touching it (or touching one that does): joined in - their parts go
	var merged := []
	var more := true
	while more:
		more = false
		for e: Dictionary in extra:
			if e["part"] in merged:
				continue
			var n0: int = bk["prisms"].size()
			var e_tree = _bake_tree(e["b"], xf_of(e["b_xf"]), bk)
			if e_tree == null or not _bake_touch(bt, e_tree, bk):
				bk["prisms"].resize(n0)   # (not part of it: its prisms forgotten)
				continue
			bt = {"op": "union", "a": bt, "b": e_tree}
			gone.append_array(spec_ids(e["b"]))
			merged.append(e["part"])
			more = true
	# the levels: between each two heights where a curve's extrusion starts or ends - the same curves
	# at work: one level
	var cuts := []
	for pr: Dictionary in bk["prisms"]:
		for h in [pr["lo"], pr["hi"]]:
			if not cuts.any(func(q): return absf(q - h) < 1e-6):
				cuts.append(h)
	cuts.sort()
	var levels := []
	for i in range(cuts.size() - 1):
		var lo: float = cuts[i]
		var hi: float = cuts[i + 1]
		var mid := (lo + hi) * 0.5
		var key := []
		for k in bk["prisms"].size():
			if bk["prisms"][k]["lo"] < mid and mid < bk["prisms"][k]["hi"]:
				key.append(k)
		if not levels.is_empty() and levels.back()["key"] == key and absf(levels.back()["hi"] - lo) < 1e-6:
			levels.back()["hi"] = hi
		else:
			levels.append({"lo": lo, "hi": hi, "key": key})
	if chain.size() == skipped and merged.is_empty() and not base.has("roles") and not base.has("per") and cs0.size() == 1:
		return {"error": "nothing to bake - it's made of one curve already."}
	var items := _bake_features(bt, bk)   # (its features: one body outline, the cuts in it)
	if items.is_empty():
		for lv: Dictionary in levels:   # (else: a set of curves a level)
			var rs := _bake_eval(bt, (float(lv["lo"]) + float(lv["hi"])) * 0.5, bk)
			for c: Dictionary in _bake_curves(rs, float(lv["lo"]), bk):
				items.append({"c": c, "role": "cut" if c.get("hole", false) else "add", "h": float(lv["hi"]) - float(lv["lo"])})
	if items.is_empty():
		return {"error": "nothing's left of it to bake."}
	return {"items": items, "live": live, "gone_ids": gone, "keep_ids": keep, "skipped": skipped, "merged": merged, "segs": int(base.get("segs", segs))}


## The bake as the solid's features (what it was made as - one body, the cuts in it), not slices:
## the added outlines that span the same heights joined into one body outline (a cut going right
## through it: a hole or bite of that outline); each other cut trimmed to the body (the part of it
## that cuts) - its curve on the surface it enters from (a pocket from the top: on the top, cut
## down). [{c: curve dict at its plane, role: add|cut, h: height from its plane (minus: down)}]
## ([] - it can't be said so: a common part, or the result isn't the same - then levels).
func _bake_features(bt: Dictionary, bk: Dictionary) -> Array:
	var adds := []
	var cuts := []
	if not _feat_walk(bt, 1, adds, cuts, bk):
		return []
	if adds.is_empty():
		return []
	var groups := {}
	for k in adds:
		var pr: Dictionary = bk["prisms"][k]
		var key := "%.5f|%.5f" % [pr["lo"], pr["hi"]]
		if not groups.has(key):
			groups[key] = {"lo": pr["lo"], "hi": pr["hi"], "r": [], "r0": []}
		groups[key]["r"] = _rs_union(groups[key]["r"], [{"o": pr["f"], "h": []}])
	for g: Dictionary in groups.values():
		g["r0"] = g["r"].duplicate()
	var top := -INF
	var bottom := INF
	for g: Dictionary in groups.values():
		top = maxf(top, g["hi"])
		bottom = minf(bottom, g["lo"])
	var kept_cuts := []
	for k in cuts:
		var pr: Dictionary = bk["prisms"][k]
		var cut := [{"o": pr["f"], "h": []}]
		var touched := []
		var all_through := true
		for g: Dictionary in groups.values():
			if pr["hi"] <= g["lo"] + 1e-6 or pr["lo"] >= g["hi"] - 1e-6 or _rs_and(g["r0"], cut).is_empty():
				continue
			touched.append(g)
			if pr["lo"] <= g["lo"] + 1e-6 and pr["hi"] >= g["hi"] - 1e-6:
				g["r"] = _rs_sub(g["r"], cut)   # (right through: part of its outline)
			else:
				all_through = false
		if touched.is_empty() or all_through:
			continue
		var body := []
		var lo := INF
		var hi := -INF
		for g: Dictionary in touched:
			body = _rs_union(body, g["r0"])
			lo = minf(lo, g["lo"])
			hi = maxf(hi, g["hi"])
		# (trimmed to the body grown a hair: its edge just outside the body's, never along it - two
		# outlines drawn along the same edge leave slivers between them)
		var size := 0.0
		for r: Dictionary in body:
			size = maxf(size, sqrt(absf(_area2(r["o"]))))
		var grown := []
		for r: Dictionary in body:
			for g: PackedVector2Array in Geometry2D.offset_polygon(r["o"], maxf(1e-3, size * 0.005)):
				if not Geometry2D.is_polygon_clockwise(g):
					grown.append({"o": g, "h": []})
		var trimmed := _rs_and(cut, grown)
		for r: Dictionary in trimmed:
			if not (r["h"] as Array).is_empty():
				return []   # (a cut with an island left in it: not a feature)
		kept_cuts.append({"r": trimmed, "lo": maxf(pr["lo"], lo), "hi": minf(pr["hi"], hi), "bottom": lo, "top": hi})
	var polys := []
	var used := []
	for pr: Dictionary in bk["prisms"]:
		polys.append(pr["f"])
		used.append(pr["c"])
	var out := []
	for g: Dictionary in groups.values():
		for r: Dictionary in g["r"]:
			out.append({"f": r["o"], "role": "add", "lo": g["lo"], "hi": g["hi"], "at": g["lo"]})
			for hl in r["h"]:
				out.append({"f": hl, "role": "cut", "lo": g["lo"], "hi": g["hi"], "at": g["lo"]})
	for kc: Dictionary in kept_cuts:
		# (on the surface it enters from: the top - cut down; else the bottom - cut up)
		var from_top: bool = not (kc["lo"] <= kc["bottom"] + 1e-5)   # (open at the bottom of what it cuts: there; else the top)
		for r: Dictionary in kc["r"]:
			out.append({"f": r["o"], "role": "cut", "lo": kc["lo"], "hi": kc["hi"], "at": kc["hi"] if from_top else kc["lo"]})
	# the same solid? (each height's cross-section as the tree makes it, against the features')
	var hs := []
	for it: Dictionary in out:
		hs.append_array([it["lo"], it["hi"]])
	for pr: Dictionary in bk["prisms"]:
		hs.append_array([pr["lo"], pr["hi"]])
	hs.sort()
	for i in range(hs.size() - 1):
		if hs[i + 1] - hs[i] < 1e-6:
			continue
		var t := (float(hs[i]) + float(hs[i + 1])) * 0.5
		var want := _bake_eval(bt, t, bk)
		var a := []
		var c := []
		for it: Dictionary in out:
			if it["lo"] < t and t < it["hi"]:
				(a if it["role"] == "add" else c).append({"o": it["f"], "h": []})
		var got := _rs_sub(_rs_union([], a), c)
		var size := _rs_area(want)
		var diff := _rs_area(_rs_sub(want, got)) + _rs_area(_rs_sub(got, want))
		if diff > maxf(size * 0.01, 1e-7):
			return []
	var items := []
	for it: Dictionary in out:
		var e := _loop_curve(it["f"], float(it["at"]), bk, polys, used)
		if e.is_empty():
			continue
		var h: float = float(it["hi"]) - float(it["lo"])
		items.append({"c": e, "role": it["role"], "h": -h if absf(float(it["at"]) - float(it["hi"])) < 1e-6 and absf(float(it["at"]) - float(it["lo"])) > 1e-6 else h})
	return items


## The tree's prisms by what they end up doing: adds and cuts (false: a common part - not features).
func _feat_walk(node: Dictionary, sign: int, adds: Array, cuts: Array, bk: Dictionary) -> bool:
	if node.has("adds"):
		for k in node["adds"]:
			(adds if sign > 0 else cuts).append(k)
		for k in node["cuts"]:
			(cuts if sign > 0 else adds).append(k)
		return true
	match str(node["op"]):
		"union":
			return _feat_walk(node["a"], sign, adds, cuts, bk) and _feat_walk(node["b"], sign, adds, cuts, bk)
		"difference":
			return _feat_walk(node["a"], sign, adds, cuts, bk) and _feat_walk(node["b"], -sign, adds, cuts, bk)
	return false


static func _rs_area(rs: Array) -> float:
	var a := 0.0
	for r: Dictionary in rs:
		a += absf(_area2(r["o"]))
		for hl in r["h"]:
			a -= absf(_area2(hl))
	return a


## Loop `f` (the bake's 2D) as a curve on the plane at height `t`: one of the old curves come through
## whole - that curve (a circle stays a circle); else a lean path through its corners.
func _loop_curve(f: PackedVector2Array, t: float, bk: Dictionary, polys: Array, used: Array) -> Dictionary:
	var n: Vector3 = bk["n"]
	var e := _same_curve(f, polys, used)
	if not e.is_empty():
		e = _flat_copy(e, n, n * t)
		e["n"] = n
		return e
	var c := fit_path(_tidy(f))
	if c.is_empty():
		return {}
	var k3 := PackedVector3Array()
	for q: Vector2 in c["pts"]:
		k3.append(bk["u"] * q.x + bk["v"] * q.y + n * t)
	e = {"kind": "path" if c["curved"] else "line", "ctrl": k3, "closed": true, "n": n}
	if c["curved"]:
		e["sharp"] = c["sharp"]
	return e


## Recipe `spec` placed by `xf` as the bake's tree (null: it can't bake - not extrusions along the axis).
func _bake_tree(spec: Dictionary, xf: Transform3D, bk: Dictionary):
	if str(spec.get("kind", "")) == "bool":
		var a = _bake_tree(spec.get("a", {}), xf, bk)
		var b = _bake_tree(spec.get("b", {}), xf * xf_of(spec.get("b_xf", [])), bk)
		if a == null or b == null:
			return null
		return {"op": str(spec.get("op", "difference")), "a": a, "b": b}
	if not str(spec.get("kind", "")) in ["extrude", "baked"] or spec.has("pieces"):
		return null
	return _bake_leaf(spec, xf, bk)


## An extrusion step as prisms (each curve's outline and the heights along the axis it spans):
## {adds: [prism index...], cuts: [...]} (null: a curve open, gone, or not across the axis).
func _bake_leaf(spec: Dictionary, xf: Transform3D, bk: Dictionary):
	var cs := curves_of(spec.get("ids", []))
	if cs.is_empty():
		return null
	var n: Vector3 = bk["n"]
	var roles: Dictionary = spec.get("roles", {}) if spec.get("roles") is Dictionary else {}
	var per: Dictionary = spec.get("per", {}) if spec.get("per") is Dictionary else {}
	var leaf := {"adds": [], "cuts": []}
	for c0: Dictionary in cs:
		var c := baked(c0, xf)
		var cn: Vector3 = (c.get("n", Vector3.UP) as Vector3).normalized()
		if not c.get("closed", false) or absf(cn.dot(n)) < 0.999:
			return null
		var s := sample(c)
		if s.size() < 3:
			return null
		var f := PackedVector2Array()
		for q in s:
			f.append(Vector2(q.dot(bk["u"]), q.dot(bk["v"])))
		if Geometry2D.is_polygon_clockwise(f):
			f.reverse()
		var id := str(int(c0.get("id", -1)))
		var o: Dictionary = per.get(id, {})
		var h := float(o.get("value", spec.get("value", 0.0)))
		var both := bool(o.get("both", spec.get("both", false)))
		var s0 := _plane_height(s, n)
		var lo := s0 - absf(h) * 0.5 if both else minf(s0, s0 + h * signf(cn.dot(n)))
		var hi := s0 + absf(h) * 0.5 if both else maxf(s0, s0 + h * signf(cn.dot(n)))
		if hi - lo < 1e-6:
			continue
		var flat := c.duplicate(true)
		flat.erase("id")
		flat.erase("name")
		flat.erase("hidden")
		bk["prisms"].append({"f": f, "lo": lo, "hi": hi, "c": flat})
		var k: int = bk["prisms"].size() - 1
		(leaf["cuts"] if str(roles.get(id, "add")) == "cut" else leaf["adds"]).append(k)
	return leaf


## The bake tree's cross-section at height `t` along the axis: regions [{o: outline, h: [holes]}].
func _bake_eval(node: Dictionary, t: float, bk: Dictionary, g := 0.0) -> Array:
	if node.has("adds"):
		var adds := []
		var cuts := []
		for k in node["adds"]:
			if bk["prisms"][k]["lo"] - g < t and t < bk["prisms"][k]["hi"] + g:
				adds.append({"o": bk["prisms"][k]["f"], "h": []})
		for k in node["cuts"]:
			if bk["prisms"][k]["lo"] - g < t and t < bk["prisms"][k]["hi"] + g:
				cuts.append({"o": bk["prisms"][k]["f"], "h": []})
		return _rs_sub(_rs_union([], adds), cuts)
	var a := _bake_eval(node["a"], t, bk, g)
	var b := _bake_eval(node["b"], t, bk, g)
	match str(node["op"]):
		"union": return _rs_union(a, b)
		"intersection": return _rs_and(a, b)
	return _rs_sub(a, b)


## Tool tree `b` touches (overlaps, or meets) solid tree `a` somewhere.
func _bake_touch(a: Dictionary, b: Dictionary, bk: Dictionary) -> bool:
	var hs := []
	for pr: Dictionary in bk["prisms"]:
		hs.append_array([pr["lo"], pr["hi"]])
	hs.sort()
	var ts := hs.duplicate()   # (every height where one starts or ends - one stacked on another touches - and between them)
	for i in range(hs.size() - 1):
		ts.append((float(hs[i]) + float(hs[i + 1])) * 0.5)
	for t in ts:
		var ra := _bake_eval(a, t, bk, 1e-4)
		var rb := _bake_eval(b, t, bk, 1e-4)
		for x in ra:
			for y in rb:
				for gp: PackedVector2Array in Geometry2D.offset_polygon(_rs_key(y), 1e-4):
					if not Geometry2D.intersect_polygons(_rs_key(x), gp).is_empty():
						return true
	return false


## Regions as curves on the plane at height `lo` (an outline or hole that is one of the curves come
## through whole: that curve - a circle stays a circle; otherwise a lean path through its corners).
func _bake_curves(rs: Array, lo: float, bk: Dictionary) -> Array:
	var n: Vector3 = bk["n"]
	var u: Vector3 = bk["u"]
	var v: Vector3 = bk["v"]
	var polys := []
	var used := []
	for pr: Dictionary in bk["prisms"]:
		polys.append(pr["f"])
		used.append(pr["c"])
	var out := []
	for r: Dictionary in rs:
		var loops: Array = [[r["o"], false]]
		for hl in r["h"]:
			loops.append([hl, true])
		for L in loops:
			var f: PackedVector2Array = L[0]
			var e := _same_curve(f, polys, used)
			if not e.is_empty():
				e = _flat_copy(e, n, n * lo)
				e["n"] = n
			else:
				var c := fit_path(_tidy(f))
				if c.is_empty():
					continue
				var k3 := PackedVector3Array()
				for q: Vector2 in c["pts"]:
					k3.append(u * q.x + v * q.y + n * lo)
				e = {"kind": "path" if c["curved"] else "line", "ctrl": k3, "closed": true, "n": n}
				if c["curved"]:
					e["sharp"] = c["sharp"]
			e["hole"] = L[1]
			out.append(e)
	return out


# (regions - outlines with their holes - combined: each as one outline cut to its holes (a keyhole),
# the result's outlines given back their holes)

static func _rs_key(r: Dictionary) -> PackedVector2Array:
	if (r["h"] as Array).is_empty():
		return r["o"]
	var o3 := PackedVector3Array()
	for q: Vector2 in r["o"]:
		o3.append(Vector3(q.x, q.y, 0))
	var hs := []
	for hl: PackedVector2Array in r["h"]:
		var h3 := PackedVector3Array()
		for q in hl:
			h3.append(Vector3(q.x, q.y, 0))
		hs.append(h3)
	var out := PackedVector2Array()
	for q in keyhole(o3, hs):
		out.append(Vector2(q.x, q.y))
	return out


static func _rs_group(ps: Array) -> Array:
	var outs := []
	var holes := []
	for p: PackedVector2Array in ps:
		if p.size() < 3 or _sliver(p):
			continue
		if Geometry2D.is_polygon_clockwise(p):
			holes.append(p)
		else:
			outs.append({"o": p, "h": [], "a": absf(_area2(p))})
	for hl: PackedVector2Array in holes:
		var best := -1
		for i in outs.size():
			if Geometry2D.is_point_in_polygon(hl[0], outs[i]["o"]) and (best < 0 or outs[i]["a"] < outs[best]["a"]):
				best = i
		if best >= 0:
			outs[best]["h"].append(hl)
	for o in outs:
		o.erase("a")
	return outs


## A hair-thin piece left between two edges drawn almost alike (its area tiny for its length).
static func _sliver(p: PackedVector2Array) -> bool:
	var per := 0.0
	for i in p.size():
		per += p[i].distance_to(p[(i + 1) % p.size()])
	return per <= 0.0 or 2.0 * absf(_area2(p)) / per < 1e-3   # (under a millimetre thick, on average)


static func _rs_union(a: Array, b: Array) -> Array:
	var all := a.duplicate()
	for t: Dictionary in b:
		var cur := t
		var rest := []
		for s: Dictionary in all:
			var g := _rs_group(Geometry2D.merge_polygons(_rs_key(s), _rs_key(cur)))
			if g.size() == 1:
				cur = g[0]
			else:
				rest.append(s)
		rest.append(cur)
		all = rest
	return all


static func _rs_sub(a: Array, b: Array) -> Array:
	var cur := a
	for t: Dictionary in b:
		var nx := []
		for s: Dictionary in cur:
			nx.append_array(_rs_group(Geometry2D.clip_polygons(_rs_key(s), _rs_key(t))))
		cur = nx
	return cur


static func _rs_and(a: Array, b: Array) -> Array:
	var out := []
	for s: Dictionary in a:
		for t: Dictionary in b:
			out.append_array(_rs_group(Geometry2D.intersect_polygons(_rs_key(s), _rs_key(t))))
	return out


# --- the overview's right-click menu ------------------------------------------------------------

## A right click on an overview row: its menu (what fits a solid, a tool step or a curve).
func _tree_click(_pos: Vector2, button: int, t: Tree) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var it := t.get_selected()
	if it == null:
		return
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	tree_menu(m).popup(Rect2i(Vector2i(t.get_global_mouse_position()), Vector2i.ZERO))


## The menu for overview row metadata `m` (made anew each time; its actions methods bound to their row).
func tree_menu(m: Dictionary) -> PopupMenu:
	var old = get_meta("tree_menu") if has_meta("tree_menu") else null
	if old and is_instance_valid(old):
		old.queue_free()
	var pm := PopupMenu.new()
	pm.name = "OverviewMenu"
	pm.add_theme_font_size_override("font_size", 14)
	var acts := []
	var item := func(menu: PopupMenu, text: String, act: Callable, on := true):
		menu.add_item(text, acts.size())
		menu.set_item_disabled(menu.item_count - 1, not on)
		acts.append(act)
	var solids := []
	for q: MeshInstance3D in ed.parts():
		if q.has_meta("curve_solid"):
			solids.append(q)
	var attach := func(menu: PopupMenu, title: String, mk: Callable, skip: Node):
		# (a submenu: each other solid, as a cut / a join / a common part)
		var sub := PopupMenu.new()
		sub.add_theme_font_size_override("font_size", 14)
		for q: MeshInstance3D in solids:
			if q == skip:
				continue
			for r in [["difference", "Cut from"], ["union", "Join to"], ["intersection", "Common with"]]:
				sub.add_item("%s %s" % [r[1], q.name], acts.size())
				acts.append(mk.call(q, r[0]))
		sub.id_pressed.connect(_menu_act)
		menu.add_submenu_node_item(title, sub)
		menu.set_item_disabled(menu.item_count - 1, sub.item_count == 0)
	if m.has("group") and is_instance_valid(m["group"]):
		var g: Node3D = m["group"]
		item.call(pm, "Select its solids", select_group.bind(g))
		item.call(pm, "Rename", start_rename.bind({"group": g}))
		item.call(pm, "Show" if not g.visible else "Hide", _act_toggle_node.bind(g))
		item.call(pm, "Duplicate", duplicate_group.bind(g))
		item.call(pm, "Ungroup", ungroup.bind(g))
		item.call(pm, "Delete (with its solids)", delete_group.bind(g))
	elif m.has("part") and is_instance_valid(m["part"]):
		var p: MeshInstance3D = m["part"]
		var spec: Dictionary = p.get_meta("curve_solid", {})
		var sel_ps: Array = ed.selected_parts() if p in ed.selected_parts() else [p]
		item.call(pm, "Rename", start_rename.bind({"part": p}))
		item.call(pm, "New part from the selected (%d)" % sel_ps.size(), make_group.bind(sel_ps))
		var mv := PopupMenu.new()
		mv.add_theme_font_size_override("font_size", 14)
		for g in groups():
			if g != group_of(p):
				mv.add_item(str(g.name), acts.size())
				acts.append(move_to_group.bind(sel_ps, g))
		if group_of(p):
			mv.add_item("(no part - the top)", acts.size())
			acts.append(move_to_group.bind(sel_ps, null))
		mv.id_pressed.connect(_menu_act)
		pm.add_submenu_node_item("Move to part", mv)
		pm.set_item_disabled(pm.item_count - 1, mv.item_count == 0)
		item.call(pm, "Show" if not p.visible else "Hide", _act_toggle_part.bind(p))
		item.call(pm, "Duplicate", _act_part.bind(p, "duplicate"))
		item.call(pm, "Delete", _act_part.bind(p, "delete"))
		pm.add_separator()
		item.call(pm, "Pick its curves", _act_part.bind(p, "pick"), not spec.is_empty())
		item.call(pm, "Bake (its tools into its curves)", _act_part.bind(p, "bake"), can_bake(p))
		item.call(pm, "Make plain mesh", _act_part.bind(p, "plain"), not spec.is_empty())
		item.call(pm, "Detach its last tool", _act_part.bind(p, "detach"), str(spec.get("kind", "")) == "bool")
		attach.call(pm, "Attach to", func(q, op): return _act_attach_part.bind(p, q, op), p)
	elif m.has("step") and is_instance_valid(m["of"]):
		var p: MeshInstance3D = m["of"]
		var parent: Array = (m["step"] as Array).slice(0, -1)
		var node := node_at(p.get_meta("curve_solid", {}), parent)
		for r in [["difference", "Role: Cut"], ["union", "Role: Join"], ["intersection", "Role: Common"]]:
			item.call(pm, r[1] + ("  (now)" if str(node.get("op", "")) == r[0] else ""), _act_step.bind(p, parent, "role:" + r[0]))
		pm.add_separator()
		item.call(pm, "Show its ghost" if bool(node_at(node, ["b"]).get("ghost_hidden", false)) else "Hide its ghost", _act_step.bind(p, parent, "ghost"))
		item.call(pm, "Detach (a solid of its own)", _act_step.bind(p, parent, "detach"))
		attach.call(pm, "Attach to", func(q, op): return _act_step_attach.bind(p, parent, q, op), p)
		item.call(pm, "Delete step (its curves stay)", _act_step.bind(p, parent, "delete"))
	elif m.has("curve"):
		var i := int(m["curve"])
		if i >= curves.size():
			return pm
		item.call(pm, "Show" if curves[i].get("hidden", false) else "Hide", _act_curve.bind(i, "hide"))
		item.call(pm, "Pick", _act_curve.bind(i, "pick"))
		item.call(pm, "Duplicate", _act_curve.bind(i, "duplicate"))
		item.call(pm, "Delete", _act_curve.bind(i, "delete"))
		pm.add_separator()
		var of = m.get("of")
		item.call(pm, "Detach from %s" % (of.name if of and is_instance_valid(of) else "its solid"), _act_detach_curve.bind(i, of, m.get("leaf", [])), of != null and is_instance_valid(of))
		attach.call(pm, "Attach to", func(q, op): return _act_attach_curve.bind(i, q, op), of if of and is_instance_valid(of) else null)
	pm.id_pressed.connect(_menu_act)
	pm.set_meta("acts", acts)
	ed.add_child(pm)
	set_meta("tree_menu", pm)
	return pm


## A menu's item `id` chosen: its action.
func _menu_act(id: int) -> void:
	var pm = get_meta("tree_menu") if has_meta("tree_menu") else null
	if pm == null or not is_instance_valid(pm):
		return
	var acts: Array = (pm as Node).get_meta("acts", [])
	if id >= 0 and id < acts.size():
		(acts[id] as Callable).call()


func _act_toggle_part(p: MeshInstance3D) -> void:
	p.visible = not p.visible
	ed._place_ghosts()
	ed._fill_parts()
	ed.view.request()
	_refresh_panel()


func _act_part(p: MeshInstance3D, what: String) -> void:
	ed.select_part(p)
	match what:
		"duplicate": ed.duplicate_part()
		"delete": ed.delete_part()
		"pick": pick_part_curves()
		"plain": unlink_part()
		"bake": bake_solid(p)
		"detach": separate_node([])


## Solid `p` made a tool of solid `q` (cut from / joined to / in common with it - live).
func _act_attach_part(p: MeshInstance3D, q: MeshInstance3D, op: String) -> void:
	var keep: bool = ed.shape_tools.keep_b
	ed.shape_tools.keep_b = false
	ed.shape_tools.boolean(op, q, p, true)
	ed.shape_tools.keep_b = keep


## A tool step (the bool at `parent` in `p`'s recipe): its role, its ghost, detached, deleted.
func _act_step(p: MeshInstance3D, parent: Array, what: String) -> void:
	ed.select_part(p)
	var spec := part_spec()
	var node := node_at(spec, parent)
	if what.begins_with("role:"):
		set_node(parent, "op", what.substr(5))
	elif what == "ghost":
		set_node(parent + ["b"], "ghost_hidden", not bool(node_at(node, ["b"]).get("ghost_hidden", false)))
		update_ghosts()
	elif what == "detach":
		separate_node(parent)
	elif what == "delete":
		set_recipe(with_node(spec, parent, node.get("a", {})), "Delete step")


## A tool step moved: detached from `p`, then made a tool of `q`.
func _act_step_attach(p: MeshInstance3D, parent: Array, q: MeshInstance3D, op: String) -> void:
	ed.select_part(p)
	var before: Array = ed.parts().duplicate()
	separate_node(parent)
	var made: MeshInstance3D = null
	for x in ed.parts():
		if not x in before:
			made = x
	if made:
		_act_attach_part(made, q, op)


func _act_curve(i: int, what: String) -> void:
	if i >= curves.size():
		return
	match what:
		"hide":
			var before := _state()
			curves[i]["hidden"] = not curves[i].get("hidden", false)
			_changed("Hide curve" if curves[i]["hidden"] else "Show curve", before)
		"pick":
			select(i)
		"duplicate":
			select(i)
			duplicate_selected()
		"delete":
			select(i)
			delete_selected()


## Curve `i` taken out of solid `p`'s step at `leaf`: the step keeps its other curves; a tool step with
## no other curve goes; a solid's last own curve can't (delete or detach the solid instead).
func _act_detach_curve(i: int, p, leaf: Array) -> void:
	if p == null or not is_instance_valid(p):
		return
	ed.select_part(p)
	var spec := part_spec()
	var node := node_at(spec, leaf)
	var id := int(curves[i].get("id", -1))
	var ids: Array = (node.get("ids", []) as Array).duplicate()
	if ids.size() > 1:
		ids.erase(id)
		ids = ids.filter(func(x): return int(x) != id)
		var n2 := node.duplicate(true)
		n2["ids"] = ids
		for k in ["roles", "per"]:
			if n2.get(k) is Dictionary:
				(n2[k] as Dictionary).erase(str(id))
		set_recipe(with_node(spec, leaf, n2), "Detach curve")
	elif not leaf.is_empty() and leaf.back() == "b":
		var parent := leaf.slice(0, -1)
		set_recipe(with_node(spec, parent, node_at(spec, parent).get("a", {})), "Detach curve")
	else:
		ed._say("%s is the only curve %s is made from - delete or detach the solid instead." % [curves[i].get("name", "This curve"), p.name])


## Curve `i` added to solid `q` as a new step (cut / join / common).
func _act_attach_curve(i: int, q: MeshInstance3D, op: String) -> void:
	ed.select_part(q)
	sel = [i]
	add_tool_curves(op)


## A solid's recipe under its row: its own curves, and each tool step (cut / join / common) as a row of
## its own with that step's curves under it - the step's eye hides its ghost.
func _tree_steps(tree: Tree, parent: TreeItem, p: MeshInstance3D, node: Dictionary, path: Array) -> void:
	var eye_on := EditorIcons.get_icon("eye")
	var eye_off := EditorIcons.get_icon("eye_off")
	if str(node.get("kind", "")) == "bool":
		_tree_steps(tree, parent, p, node.get("a", {}), path + ["a"])
		var b: Dictionary = node.get("b", {})
		var si := tree.create_item(parent)
		si.set_text(0, "%s: %s" % [{"union": "Join", "difference": "Cut", "intersection": "Common"}.get(str(node.get("op", "")), "Tool"), _spec_words(b)])
		si.set_metadata(0, {"step": path + ["b"], "of": p})
		si.set_tooltip_text(0, "A tool step of %s. Click: select the solid and pick this step's curves. The eye hides its ghost." % p.name)
		si.add_button(1, eye_off if bool(b.get("ghost_hidden", false)) else eye_on, 0, false, "Hide / show this step's ghost.")
		_tree_steps(tree, si, p, b, path + ["b"])
		return
	var roles: Dictionary = node.get("roles", {}) if node.get("roles") is Dictionary else {}
	for id in spec_ids(node):
		var i := _curve_index(int(id))
		if i < 0:
			continue
		var ci := tree.create_item(parent)
		var baked := str(node.get("kind", "")) in ["baked", "edges"]
		ci.set_text(0, "%s%s" % [curves[i].get("name", "Curve"), "  (cut)" if str(roles.get(str(int(id)), "")) == "cut" and not baked else ""])
		ci.set_editable(0, true)
		ci.set_metadata(0, {"curve": i, "of": p, "leaf": path})
		ci.set_tooltip_text(0, ("A curve on %s's surface: one of the edges that shape it. Click: pick it (Ctrl / Shift: more) and\nreshape it - the solid follows. Right-click: more." if baked else "A curve %s is made from. Click: pick it (Ctrl / Shift: more). The eye hides it (and its ghost).\nRight-click: more.") % p.name)
		ci.add_button(1, eye_off if curves[i].get("hidden", false) else eye_on, 0, false, "Hide / show this curve (and its ghost).")
		if i in sel:
			ci.select(0)


func _curve_index(id: int) -> int:
	for i in curves.size():
		if int(curves[i].get("id", -1)) == id:
			return i
	return -1


static func _spec_words(spec: Dictionary) -> String:
	var k := str(spec.get("kind", ""))
	if k == "bool":
		return "%s of two solids" % {"union": "a join", "difference": "a cut", "intersection": "the common part"}.get(str(spec.get("op", "")), "a boolean")
	return {"extrude": "an extrusion", "baked": "a baked solid", "edges": "a baked solid", "revolve": "a revolve", "pipe": "a pipe", "loft": "a loft", "sweep": "a sweep", "fill": "a fill"}.get(k, "a solid")


## (Clicks come one item at a time: the whole selection is read once they're in.)
func _tree_selected(_item: TreeItem, _col: int, _on: bool) -> void:
	if bool(get_meta("tree_sync", false)) or bool(get_meta("tree_pending", false)):
		return
	set_meta("tree_pending", true)
	_tree_apply.call_deferred()


## The overview's selection made the editor's: its solids the selected parts, its curves the picked ones.
func _tree_apply() -> void:
	set_meta("tree_pending", false)
	var t = _w("tree")
	if t == null:
		return
	var parts := []
	var cidx := []
	var it: TreeItem = (t as Tree).get_next_selected(null)
	while it:
		var m = it.get_metadata(0)
		if m is Dictionary:
			if m.has("part") and is_instance_valid(m["part"]):
				parts.append(m["part"])
			elif m.has("group") and is_instance_valid(m["group"]):
				for q in group_parts(m["group"]):
					if not q in parts:
						parts.append(q)
			elif m.has("curve") and not int(m["curve"]) in cidx:
				cidx.append(int(m["curve"]))
			elif m.has("step") and is_instance_valid(m["of"]):
				# (a tool step: its solid selected, its curves picked)
				if not m["of"] in parts:
					parts.append(m["of"])
				for id in spec_ids(node_at((m["of"] as Node).get_meta("curve_solid", {}), m["step"])):
					var ci := _curve_index(int(id))
					if ci >= 0 and not ci in cidx:
						cidx.append(ci)
		it = (t as Tree).get_next_selected(it)
	sel = cidx
	if not parts.is_empty():
		ed.select_part(parts[0])
		for k in range(1, parts.size()):
			ed.select_part(parts[k], true)
	elif sel.is_empty():
		ed.select_part(null)
	_refresh_panel()
	layer.queue_redraw()


## A name typed in the overview: the solid or the curve renamed (one undo step).
func _tree_edited(t: Tree) -> void:
	var it := t.get_edited()
	if it == null:
		return
	var m = it.get_metadata(0)
	var text := it.get_text(0).strip_edges()
	if not m is Dictionary or text == "":
		return
	if m.has("group") and is_instance_valid(m["group"]):
		var g: Node = m["group"]
		var old := str(g.name)
		var nm := text.validate_node_name()
		ed._do("Rename", func(): g.name = nm; ed._fill_parts(); _refresh_panel(), func(): g.name = old; ed._fill_parts(); _refresh_panel())
	elif m.has("part") and is_instance_valid(m["part"]):
		ed.select_part(m["part"])
		ed.rename_part(text)
	elif m.has("curve"):
		var i := int(m["curve"])
		if i < curves.size():
			var before := _state()
			curves[i]["name"] = text.trim_suffix("  (cut)")
			_changed("Rename curve", before)


## The eye: a solid shown / hidden (as the parts list's eye), a curve hidden from the view (one undo step).
func _tree_button(it: TreeItem, _col: int, _id: int, _mb: int) -> void:
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	if m.has("group") and is_instance_valid(m["group"]):
		_act_toggle_node(m["group"])
		var t = _w("tree")
		if t:
			(t as Node).set_meta("sig", 0)
		_refresh_panel()
		return
	if m.has("step") and is_instance_valid(m["of"]):
		var p: MeshInstance3D = m["of"]
		var node := node_at(p.get_meta("curve_solid", {}), m["step"])
		if ed.part != p:
			ed.select_part(p)
		set_node(m["step"], "ghost_hidden", not bool(node.get("ghost_hidden", false)))
		update_ghosts()
		return
	if m.has("part") and is_instance_valid(m["part"]):
		var p: MeshInstance3D = m["part"]
		p.visible = not p.visible
		ed._place_ghosts()
		ed._fill_parts()
		ed.view.request()
		var t = _w("tree")
		if t:
			(t as Node).set_meta("sig", 0)
		_refresh_panel()
	elif m.has("curve"):
		var i := int(m["curve"])
		var before := _state()
		curves[i]["hidden"] = not curves[i].get("hidden", false)
		if curves[i]["hidden"]:
			sel.erase(i)
		_changed("Hide curve" if curves[i]["hidden"] else "Show curve", before)


## The Curve modeling tab's contents.
func build_panel(box: VBoxContainer) -> void:
	build_overview(box)
	build_solid_box(box)
	box.add_child(EditorIcons.tipped(UI.section("SKETCH"), EditorIcons.tip("Sketch", "", "Draw curves on the construction plane: lines, splines, circles, arcs, rectangles, polygons -\nsnapped to the grid and to points.")))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 2)
	for t in ["line", "spline", "circle", "arc", "rect", "polygon"]:
		var d: Array = TOOLS[t]
		var b: Button = ed._btn(d[0], d[1], d[2], d[3], begin.bind(t))
		b.toggle_mode = true
		_panel_btns["tool_" + t] = b
		row.add_child(b)
	box.add_child(row)
	# the construction plane (a dropdown) and snapping, one row under the tools
	var sr := HFlowContainer.new()
	sr.add_theme_constant_override("h_separation", 4)
	sr.add_theme_constant_override("v_separation", 2)
	var po := OptionButton.new()
	po.focus_mode = Control.FOCUS_NONE
	po.add_theme_font_size_override("font_size", 14)
	for p in PLANES:
		po.add_item(p[1])
	po.tooltip_text = EditorIcons.tip("Construction plane", "", "Where new curves are drawn - Auto: the surface under your first click (a part's face: drawn on\nit), else the ground; Ground (X Z); Front (X Y); Side (Z Y); View (square to the view); Selection\n(the selected faces in edit mode, or the picked curve).")
	po.item_selected.connect(_plane_picked)
	_panel_btns["w_plane"] = po
	sr.add_child(po)
	var g := CheckBox.new()
	g.text = "Grid"
	g.button_pressed = snap_grid
	g.focus_mode = Control.FOCUS_NONE
	g.add_theme_font_size_override("font_size", 14)
	g.tooltip_text = EditorIcons.tip("Snap to the grid", "Ctrl: off while held", "Points land on the construction plane's grid.")
	g.toggled.connect(_set_snap_grid)
	sr.add_child(g)
	var step := SpinBox.new()
	step.min_value = 0.001
	step.max_value = 10.0
	step.step = 0.001
	step.value = grid_step
	step.custom_minimum_size.x = 70
	step.tooltip_text = EditorIcons.tip("Grid step", "", "The grid's spacing in metres (also the step of a dragged extrusion).")
	step.value_changed.connect(_set_grid_step)
	sr.add_child(step)
	var sp := CheckBox.new()
	sp.text = "Points"
	sp.button_pressed = snap_points
	sp.focus_mode = Control.FOCUS_NONE
	sp.add_theme_font_size_override("font_size", 14)
	sp.tooltip_text = EditorIcons.tip("Snap to points", "Ctrl: off while held", "Points land on the curves' points, ends, middles and centres, and on the parts' corners.")
	sp.toggled.connect(_set_snap_points)
	sr.add_child(sp)
	var gd := CheckBox.new()
	gd.text = "Guides"
	gd.button_pressed = guides_on()
	gd.focus_mode = Control.FOCUS_NONE
	gd.add_theme_font_size_override("font_size", 14)
	gd.tooltip_text = EditorIcons.tip("Guides", "Alt: off while dragging", "A dragged point lines up with the others: when its X, Y or Z comes close to another point's\n(its own curve's first) or to a flat face's level, it snaps there - a dashed guide shows to what.")
	gd.toggled.connect(func(on): set_meta("guides_off", not on))
	sr.add_child(gd)
	var gh := CheckBox.new()
	gh.text = "Ghosts"
	gh.button_pressed = ghosts_on()
	gh.focus_mode = Control.FOCUS_NONE
	gh.add_theme_font_size_override("font_size", 14)
	gh.tooltip_text = EditorIcons.tip("Ghosts", "", "The solids inside recipes shown where they are, see-through: red - cutting, green - joined,\nblue - common. (Only a preview: never saved.)")
	gh.toggled.connect(_set_ghosts)
	sr.add_child(gh)
	box.add_child(sr)
	box.add_child(EditorIcons.tipped(UI.section("CURVES"), EditorIcons.tip("Curves", "", "Change the picked curves: move, turn, scale, offset, fillet, join, bridge, close, mirror,\nand combine them (union, subtract, intersect).")))
	_info = UI.label("", 14, UI.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	build_curve_box(box)
	var er := HFlowContainer.new()
	er.add_theme_constant_override("h_separation", 2)
	er.add_theme_constant_override("v_separation", 2)
	for it in edit_items():
		er.add_child(_item_button(it))
	box.add_child(er)
	box.add_child(EditorIcons.tipped(UI.section("SOLIDS FROM CURVES"), EditorIcons.tip("Solids from curves", "", "Make the picked curves into solids - extrude, revolve, loft, sweep, pipe, fill. They stay\nmade from the curves: reshape a curve and its solid follows.")))
	var so := HFlowContainer.new()
	so.add_theme_constant_override("h_separation", 2)
	so.add_theme_constant_override("v_separation", 2)
	for it in solid_items():
		so.add_child(_item_button(it))
	box.add_child(so)
	var nr := so   # (steps round: on the same row as the solid buttons)
	nr.add_child(UI.label("Steps", 14, UI.TEXT_DIM))
	var st := SpinBox.new()
	st.min_value = 6
	st.max_value = 128
	st.value = segs
	st.tooltip_text = EditorIcons.tip("Steps round", "", "How many steps a revolve takes for a whole turn.")
	st.value_changed.connect(_set_segs)
	nr.add_child(st)
	box.add_child(EditorIcons.tipped(UI.section("ON THE MESH"), EditorIcons.tip("On the mesh", "", "Edit-mode tools that work on the mesh itself: push / pull faces, fillet edges, inset, flatten.")))
	var mr := HFlowContainer.new()
	mr.add_theme_constant_override("h_separation", 2)
	mr.add_theme_constant_override("v_separation", 2)
	for it in mesh_items():
		mr.add_child(_item_button(it))
	box.add_child(mr)
	_refresh_panel()


## A panel button for item `it`: pressed, it runs the item looked up by its name then (a method, not
## a lambda kept from when the panel was built: those go stale when the script's hot reloaded - the
## buttons stuck disabled and dead).
func _item_button(it: Array) -> Button:
	var b: Button = ed._btn(it[1], it[0], it[2], it[3], _run_item.bind(str(it[1])))
	_panel_btns["op_" + str(it[1])] = [b]
	return b


func _all_items() -> Array:
	return edit_items() + solid_items() + mesh_items()


## The item called `name` run (as the items are now).
func _run_item(name: String) -> void:
	for it in _all_items():
		if str(it[1]) == name:
			(it[4] as Callable).call()
			return


func _spec_value(v: float) -> void:
	set_spec("value", v)


func _spec_segs(v: float) -> void:
	set_spec("segs", v)


func _set_snap_grid(on: bool) -> void:
	snap_grid = on


func _set_grid_step(v: float) -> void:
	grid_step = v
	if layer:
		layer.queue_redraw()


func _set_snap_points(on: bool) -> void:
	snap_points = on


# --- ghosts: the solids inside recipes, seen through -----------------------------------------------

## Ghosts on (the Ghosts box; kept as a meta - hot reload safe).
func ghosts_on() -> bool:
	return bool(get_meta("ghosts_on", true))


func _set_ghosts(on: bool) -> void:
	set_meta("ghosts_on", on)
	update_ghosts()


## What the ghosts show, as a number (made again when it changes).
func ghost_sig() -> int:
	var sig := hash(ghosts_on())
	for c in curves:
		if c.get("hidden", false):
			sig = hash([sig, c.get("id")])
	if ed == null or ed.model == null:
		return sig
	for p: MeshInstance3D in ed.parts():
		if p.has_meta("curve_solid"):
			sig = hash([sig, p.get_instance_id(), str(p.get_meta("curve_solid_key", "")), p.global_transform, p.is_visible_in_tree()])
	return sig


## Every solid used inside a recipe (a cut, joined or common one) shown where it is, see-through: red
## for a cut, green joined, blue common - drawn through the solid, never saved (in the view's world,
## not the model).
func update_ghosts() -> void:
	for n in get_meta("ghost_nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	var nodes := []
	if ghosts_on() and ed and ed.model:
		for p: MeshInstance3D in ed.parts():
			var spec: Dictionary = p.get_meta("curve_solid", {})
			if not spec.is_empty() and p.is_visible_in_tree():
				_ghost_walk(spec, p.global_transform, nodes)
	set_meta("ghost_nodes", nodes)
	if ed and ed.view:
		ed.view.request()


func _ghost_walk(spec: Dictionary, xf: Transform3D, nodes: Array) -> void:
	if str(spec.get("kind", "")) == "baked":
		return   # (a baked solid is one solid: its curves shape it - no tools, no ghosts)
	if str(spec.get("kind", "")) != "bool":
		# (a step's curves with the Cut role: each one made as the step would make it alone - a red ghost)
		var roles: Dictionary = spec.get("roles", {}) if spec.get("roles") is Dictionary else {}
		for id in roles:
			if str(roles[id]) == "cut" and not _all_hidden([id]):
				var one := spec.duplicate(true)
				one.erase("roles")
				one.erase("per")
				one["ids"] = [int(id)]
				var per: Dictionary = spec.get("per", {}) if spec.get("per") is Dictionary else {}
				if per.has(str(id)):
					one["value"] = float(per[str(id)].get("value", one.get("value", 0.0)))
					one["both"] = bool(per[str(id)].get("both", one.get("both", false)))
				_ghost_add(solid_of(one), xf, "difference", nodes)
		return
	_ghost_walk(spec.get("a", {}), xf, nodes)
	var bx := xf * xf_of(spec.get("b_xf", []))
	var b: Dictionary = spec.get("b", {})
	if not bool(b.get("ghost_hidden", false)) and not _all_hidden(spec_ids(b)):
		_ghost_add(solid_of(b), bx, str(spec.get("op", "difference")), nodes)
	_ghost_walk(spec.get("b", {}), bx, nodes)


## Every one of these curves hidden in the overview (a ghost made only of hidden curves isn't shown).
func _all_hidden(ids: Array) -> bool:
	if ids.is_empty():
		return false
	for id in ids:
		var c := curve_by_id(int(id))
		if c.is_empty() or not c.get("hidden", false):
			return false
	return true


func _ghost_add(m: Mesh, xf: Transform3D, op: String, nodes: Array) -> void:
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Ghost"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _ghost_mat(op)
	ed.view.world.add_child(mi)
	mi.global_transform = xf
	nodes.append(mi)


func _ghost_mat(op: String) -> StandardMaterial3D:
	var mats: Dictionary = get_meta("ghost_mats", {})
	if not mats.has(op):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		m.albedo_color = {"difference": Color(1.0, 0.3, 0.25, 0.16), "union": Color(0.35, 1.0, 0.45, 0.16), "intersection": Color(0.4, 0.65, 1.0, 0.16)}.get(op, Color(1, 1, 1, 0.16))
		mats[op] = m
		set_meta("ghost_mats", mats)
	return mats[op]


func _set_segs(v: float) -> void:
	segs = int(v)


## [icon, name, keys, help, callable, enabled (for the menu), needs (Callable -> bool)]
func edit_items() -> Array:
	var any := func(): return not sel.is_empty()
	var two := func(): return sel.size() >= 2
	return [
		["m_move", "Move curves", "G", "Moves the picked curves in 3D with the mouse (over the plane facing you; X / Y / Z: along an\naxis; a typed number: that far). Snapped to the grid (Ctrl: free). Their solids follow.", func(): begin_xf("move"), any.call(), any],
		["m_rotate", "Turn curves", "R", "Turns the picked curves about their middle (the line of sight; X / Y / Z: an axis) - by 15°\n(Ctrl: free), or type the degrees.", func(): begin_xf("turn"), any.call(), any],
		["m_scale", "Scale curves", "S", "Scales the picked curves about their middle (X / Y / Z: along one axis), or type the factor.", func(): begin_xf("scale"), any.call(), any],
		["delete", "Delete curves", "X / Delete", "Removes the selected curves.", delete_selected, any.call(), any],
		["duplicate", "Duplicate curves", "Shift+D", "Copies of the selected curves, beside them.", duplicate_selected, any.call(), any],
		["m_mirror_x", "Mirror curves", "", "Copies of the selected curves mirrored across the model's X (left-right).", func(): mirror_selected(0), any.call(), any],
		["m_cv_radial", "Radial array", "", "Six copies of the selected curves round the model's Y axis (the originals among them).", func(): radial_array(6), any.call(), any],
		["m_cv_offset", "Offset curve", "", "A copy of the curve moved out (or in) by a distance in its plane: the mouse sets it, or type it.", begin_offset, any.call(), any],
		["m_cv_fillet", "Fillet corners", "", "Rounds the corners of the selected lines, rectangles and polygons: the mouse sets the radius,\nor type it (0: sharp again). Kept with the curve - change it any time.", begin_fillet_corners, any.call(), any],
		["m_cv_join", "Join curves", "", "The two selected open curves made one, at their nearest ends.", join_selected, two.call(), two],
		["m_cv_bridge", "Bridge curve", "", "A smooth curve between the nearest ends of the two selected curves, leaving each along\nits own direction (its two handles drag).", bridge_selected, two.call(), two],
		["m_cv_reverse", "Reverse curve", "", "The selected curves run the other way (a loft or sweep follows their direction).", reverse_selected, any.call(), any],
		["m_union", "Union curves", "", "The picked closed curves (on one plane) made one outline. Curves round a gap leave it as a hole.", func(): curve_boolean("union"), two.call(), two],
		["m_difference", "Subtract curves", "", "The first picked closed curve minus the others (on its plane): what's inside it becomes holes.\nExtrude the results together: a solid with its holes, still following its curves.", func(): curve_boolean("subtract"), two.call(), two],
		["m_cv_spline", "Simplify curve", "", "The picked closed curves with more points than they need (a dense outline) made lean: corners\nand straight sides kept, a point every ~40° along the bends. Solids made from them follow.", simplify_selected, any.call(), any],
		["m_intersect", "Intersect curves", "", "Only what the picked closed curves all share (on one plane).", func(): curve_boolean("intersect"), two.call(), two],
		["m_cv_close", "Close / open", "", "Closes the selected lines and splines into loops, or opens them.", toggle_closed, any.call(), any],
	]


func solid_items() -> Array:
	var any := func(): return not sel.is_empty()
	var two := func(): return sel.size() >= 2
	return [
		["m_cv_extrude", "Extrude", "E", "The selected curves pushed out along their plane's normal: closed ones become solids, open\nones walls. The mouse sets how far (snapped to the grid; Ctrl: free) - or type it.", begin_extrude, any.call(), any],
		["m_cv_revolve", "Revolve", "", "The profile turned round an axis: a two-point line selected with it, else the model's Y axis.\nThe mouse sets the angle (or type it): 360° makes a closed solid.", begin_revolve, any.call(), any],
		["m_cv_loft", "Loft", "", "A skin through the selected curves, in the order you picked them (closed ones: capped).", func(): make_part("loft"), two.call(), two],
		["m_cv_sweep", "Sweep", "", "The first selected curve (the profile) carried along the second (the path).", func(): make_part("sweep"), two.call(), two],
		["m_cv_pipe", "Pipe", "", "A round tube along each selected curve: the mouse sets its radius (or type it).", begin_pipe, any.call(), any],
		["m_cv_fill", "Fill", "", "The selected closed curves filled with flat faces.", func(): make_part("fill"), any.call(), any],
	]


func mesh_items() -> Array:
	var edit := func(): return ed.mode == "edit"
	var items := [
		["m_extrude", "Push / pull faces", "E", "The selected faces pulled out (or pushed in) along their normal, walls round them.", func(): ed.extrude(), edit.call(), edit],
	]
	var can_fillet := func(): return ed.mode == "edit" and ed.mesh_ops.has_method("begin_fillet")
	items.append(["m_fillet", "Fillet edges", "Ctrl+B", "The selected edges rounded: the mouse sets the width, the wheel the steps.", func(): ed.mesh_ops.call("begin_fillet"), can_fillet.call(), can_fillet])
	items.append(["m_inset", "Inset faces", "I", "A smaller copy of the selected faces inside them.", func(): ed.mesh_ops.begin_inset(), edit.call(), edit])
	items.append(["m_flatten", "Flatten", "Shift+Alt+F", "The selected points pressed onto a plane.", func(): ed.deform.begin_flatten(), edit.call(), edit])
	return items


## The right-click menu's Curve modeling tab: its groups (as the menu takes them).
func menu_groups(at := Vector2(-1e6, -1e6)) -> Array:
	var pts := point_items(at)
	var sketch := []
	for t in ["line", "spline", "circle", "arc", "rect", "polygon"]:
		var d: Array = TOOLS[t]
		sketch.append([d[1], d[0], d[2], d[3], begin.bind(t), true])
	var planes := []
	for p in [["auto", "Auto plane", "The surface under your first click, else the ground."], ["ground", "Ground plane", "X and Z, facing up."],
			["front", "Front plane", "X and Y."], ["side", "Side plane", "Z and Y."], ["view", "View plane", "Square to the view."], ["selection", "Selection's plane", "The selected faces' or curve's."]]:
		planes.append([{"auto": "m_cv_plane", "ground": "m_top", "front": "m_front", "side": "m_side", "view": "m_ortho", "selection": "m_face"}[p[0]], p[1] + (" (on)" if plane_mode == p[0] else ""), "", p[2], set_plane_mode.bind(p[0]), plane_mode != p[0]])
	var out := [sketch, planes]
	if not pts.is_empty():
		out.push_front(pts)   # (right-clicked on a picked curve's point: what it can be, first)
	var p: MeshInstance3D = ed.part
	out.append([["bake", "Bake solid", "", "The selected solid's tools and curves worked out into new curves on its surfaces: one Baked\nsolid, shaped by them only. Tools not touching it stay live.", _bake_btn, p != null and can_bake(p)]])
	for g in [edit_items(), solid_items(), mesh_items()]:
		var grp := []
		for it in g:
			grp.append([it[0], it[1], it[2], it[3], it[4], it[5]])
		out.append(grp)
	return out


const PLANES := [["auto", "Plane: Auto"], ["ground", "Plane: Ground"], ["front", "Plane: Front"], ["side", "Plane: Side"],
	["view", "Plane: View"], ["selection", "Plane: Selection"]]


func _plane_picked(i: int) -> void:
	set_plane_mode(PLANES[i][0])


func set_plane_mode(m: String) -> void:
	plane_mode = m
	plane = {}
	for k in _plane_btns:
		if is_instance_valid(_plane_btns[k]):
			(_plane_btns[k] as Button).set_pressed_no_signal(k == m)
	_refresh_panel()
	_hint()
	if layer:
		layer.queue_redraw()


func _refresh_panel() -> void:
	# (each item's enabled state worked out now, from the items as they are - looked up by name)
	var on := {}
	for it in _all_items():
		on["op_" + str(it[1])] = bool(it[5])
	for k in _panel_btns:
		var e = _panel_btns[k]
		if e is Button:
			(e as Button).set_pressed_no_signal(k == "tool_" + tool)
		elif e is Array and on.has(k) and is_instance_valid(e[0]):
			(e[0] as Button).disabled = not on[k]
	for k in _plane_btns:
		if is_instance_valid(_plane_btns[k]):
			(_plane_btns[k] as Button).set_pressed_no_signal(k == plane_mode)
	var pob = _w("plane")
	if pob:
		(pob as OptionButton).select(maxi(0, PLANES.map(func(q): return q[0]).find(plane_mode)))
	var _solid_box: VBoxContainer = _w("solid_box")
	var _solid_label: Label = _w("solid_label")
	var _solid_value_row: Control = _w("solid_value_row")
	var _solid_value_label: Label = _w("solid_value_label")
	var _solid_value: SpinBox = _w("solid_value")
	var _solid_segs_row: Control = _w("solid_segs_row")
	var _solid_segs: SpinBox = _w("solid_segs")
	if _solid_box:
		var spec := part_spec()
		_solid_box.visible = not spec.is_empty()
		if not spec.is_empty():
			var kind := str(spec.get("kind", ""))
			var cs := curves_of(spec.get("ids", []))
			var ids := spec_ids(spec)
			cs = curves_of(ids)
			_solid_label.text = "%s · %d curve%s · %s" % [
				{"extrude": "Extrusion", "baked": "Baked", "edges": "Baked", "revolve": "Revolve", "pipe": "Pipe", "loft": "Loft", "sweep": "Sweep", "fill": "Fill",
					"bool": "Live " + {"union": "join", "difference": "cut", "intersection": "common"}.get(str(spec.get("op", "")), "boolean")}.get(kind, "Solid"),
				ids.size(), "" if ids.size() == 1 else "s", "follows its curves" if not cs.is_empty() else "curves gone: kept as is"]
			_solid_label.tooltip_text = "Made from its curves: it's made again whenever they (or its settings below) change."
			_solid_label.mouse_filter = Control.MOUSE_FILTER_STOP
			_solid_value_row.visible = kind in ["extrude", "revolve", "pipe"]
			_solid_value_label.text = {"extrude": "Height", "revolve": "Angle", "pipe": "Radius"}.get(kind, "")
			_solid_value.min_value = {"extrude": -100.0, "revolve": 1.0, "pipe": 0.001}.get(kind, -100.0)
			_solid_value.max_value = {"extrude": 100.0, "revolve": 360.0, "pipe": 10.0}.get(kind, 100.0)
			_solid_value.allow_lesser = kind == "extrude"
			_solid_value.allow_greater = kind != "revolve"
			_solid_value.step = 1.0 if kind == "revolve" else 0.001
			_solid_value.set_value_no_signal(float(spec.get("value", 0.0)))
			_solid_segs_row.visible = kind == "revolve"
			var rrow = _w("role_row")
			if rrow:
				(rrow as Control).visible = kind != "bool"   # (a boolean's role: in its recipe below)
				var ob: OptionButton = (rrow as Node).get_child(1)
				ob.select(0)
			var recipe = _w("recipe")
			if recipe:
				# (the recipe tree shows every setting: the single rows aren't needed)
				_solid_value_row.visible = false
				_solid_segs_row.visible = false
				_fill_recipe(recipe, spec)
			var nb = _w("neg")
			var pb = _w("pos")
			if nb:
				(nb as Control).visible = true
			if pb:
				(pb as Control).visible = kind == "bool" and str(spec.get("op", "")) == "difference"
			_solid_segs.set_value_no_signal(int(spec.get("segs", segs)))
	_curve_box_values()
	_fill_tree()
	if _info:
		if curves.is_empty():
			_info.text = "No curves yet - pick a sketch tool."
		elif sel.is_empty():
			_info.text = "%d curves - click one to pick it (Shift: more)." % curves.size()
		else:
			var names := []
			for i in sel:
				names.append(str(curves[i].get("name", "Curve")))
			_info.text = "%d of %d picked: %s" % [sel.size(), curves.size(), ", ".join(names)]


# --- drawing ----------------------------------------------------------------------------------

func _draw_layer() -> void:
	if ed.model == null:
		return
	# the construction plane's grid round the cursor while sketching
	if tool != "":
		var pl := plane if not plane.is_empty() else _hover_plane
		if not pl.is_empty():
			_draw_plane(pl)
	var own := owner_xfs()
	var clips := edge_clips()
	_begin_occ(true)
	for i in curves.size():
		if curves[i].get("hidden", false):
			continue   # (hidden in the overview)
		var on := i in sel
		var x := cx(curves[i], own)
		_draw_curve(curves[i], SEL_COL if on else CURVE_COL, 2.5 if on else 1.8, x, clips.get(int(curves[i].get("id", -1)), {}))
		if on:
			var k: PackedVector3Array = baked(curves[i], x)["ctrl"]
			if str(curves[i]["kind"]) == "bezier" and k.size() == 4:
				layer.draw_dashed_line(_screen(k[0]), _screen(k[1]), Color(1, 1, 1, 0.6), 1.2, 4.0)
				layer.draw_dashed_line(_screen(k[3]), _screen(k[2]), Color(1, 1, 1, 0.6), 1.2, 4.0)
			for q in k:
				var s := _screen(q)
				var a := 0.3 if _hidden(_mx() * q) else 1.0   # (a point behind the solid: faint)
				layer.draw_rect(Rect2(s - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.6 * a))
				layer.draw_rect(Rect2(s - Vector2(3.5, 3.5), Vector2(7, 7)), Color(1, 1, 1, a))
	_end_occ()
	_draw_drag()
	if tool != "":
		var d := _draft()
		if not d.is_empty():
			_draw_curve(d, Color(1, 1, 1, 0.9), 1.6)
		for q in placed:
			layer.draw_circle(_screen(q), 4.0, Color.WHITE)
		if cursor != Vector3.INF:
			var s := _screen(cursor)
			var col: Color = {"grid": Color(0.7, 0.7, 0.7), "point": Color(1, 0.85, 0.3), "end": Color(1, 0.5, 0.3), "mid": Color(0.4, 1, 0.5), "centre": Color(0.5, 0.8, 1), "vertex": Color(1, 0.6, 1)}.get(snap_kind, Color.WHITE)
			layer.draw_arc(s, 7.0, 0, TAU, 20, Color(0, 0, 0, 0.6), 3.0)
			layer.draw_arc(s, 7.0, 0, TAU, 20, col, 1.5)
			if not placed.is_empty():
				var a := placed[placed.size() - 1]
				var dist := a.distance_to(cursor)
				var f := layer.get_theme_default_font()
				layer.draw_string(f, s + Vector2(12, -10), "%.3f m" % dist, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(Settings.MIN_FONT, 14), Color(1, 0.92, 0.8))


func _draw_curve(c: Dictionary, col: Color, w: float, x := Transform3D(), clip := {}) -> void:
	var s := sample(c)
	if s.size() < 2:
		return
	if c.get("closed", false):
		s.append(s[0])
	var pts := PackedVector2Array()
	var mx := _mx() * x
	# (the solid hides what's behind it: a curve's run behind the surface isn't drawn - where it goes
	# out of sight between two points found closer, so the line ends there)
	var inv := mx.affine_inverse()
	var w3s := PackedVector3Array()
	var off := PackedByteArray()
	for j in s.size():
		var w3 := mx * s[j]
		var gone: bool = ed.view.behind(w3) or (not clip.is_empty() and not _in_clip(s[j], clip))
		var hid: bool = not gone and _hidden(w3)
		if j > 0 and not gone and off[off.size() - 1] != 2 and hid != (off[off.size() - 1] == 1):
			var a: Vector3 = w3s[w3s.size() - 1]
			var b := w3
			for it in 5:
				var m := a.lerp(b, 0.5)
				if _hidden(m) == hid:
					b = m
				else:
					a = m
			w3s.append(a)
			off.append(0 if hid else 1)
			w3s.append(b)
			off.append(1 if hid else 0)
		w3s.append(w3)
		off.append(2 if gone else (1 if hid else 0))
	for j in w3s.size():
		if off[j] != 0:
			if pts.size() >= 2:
				layer.draw_polyline(pts, Color(0, 0, 0, 0.5), w + 2.0, true)
				layer.draw_polyline(pts, col, w, true)
			pts = PackedVector2Array()
			continue
		pts.append(ed.view.project(w3s[j]))
	if pts.size() >= 2:
		layer.draw_polyline(pts, Color(0, 0, 0, 0.5), w + 2.0, true)
		layer.draw_polyline(pts, col, w, true)


## (while drawing or picking: meta "occlusion") what hides the curves behind it - {o: [[world -> part,
## TriangleMesh]...] of the visible parts, quick: the camera moving (one ray a point, the outline
## tolerance left till it stops), cache: point -> hidden, kept while the view and the parts stay}.
func _begin_occ(drawing: bool) -> void:
	var o := _occluders()
	var cam: Transform3D = ed.view.cam.global_transform
	var sig := hash([cam, ed.view.cam.fov, ed.view.cam.projection, ed.view.cam.size, ed.view.sv.size, o.map(func(e): return [e[0], (e[1] as Object).get_instance_id()])])
	var st: Dictionary = get_meta("occlusion", {})
	var quick := false
	if drawing:
		quick = cam != st.get("cam_was", cam)   # (moved since the last drawing)
		if quick:
			layer.queue_redraw.call_deferred()   # (drawn again exactly once it's still)
	var cache: Dictionary = st.get("cache", {}) if int(st.get("sig", 0)) == sig else {}
	set_meta("occlusion", {"o": o, "quick": quick, "cache": cache, "sig": sig, "cam_was": cam})


func _end_occ() -> void:
	var st: Dictionary = get_meta("occlusion", {})
	st["o"] = []
	if st.get("cache", {}).size() > 20000:
		st["cache"] = {}


func _occluders() -> Array:
	var out := []
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree() or p.mesh == null:
			continue
		var tm := p.mesh.generate_triangle_mesh()   # (the mesh keeps it - built once a mesh)
		if tm:
			out.append([p.global_transform.affine_inverse(), tm])
	return out


## A world point hidden from the camera by a part's surface (one it lies on doesn't hide it).
func _hidden(w3: Vector3) -> bool:
	var st: Dictionary = get_meta("occlusion", {})
	if (st.get("o", []) as Array).is_empty() or ed.view.behind(w3):
		return false
	var cache: Dictionary = st["cache"]
	if cache.has(w3):
		return cache[w3]
	var cam: Camera3D = ed.view.cam
	var sp: Vector2 = ed.view.project(w3)
	if not _blocked(cam.project_ray_origin(sp), w3):
		cache[w3] = false
		return false
	if st.get("quick", false):
		return true
	# (on the outline as seen - a wall edge-on: hidden only if it's still behind 3 px off each way - as
	# wide as the line drawn)
	var depth := -(cam.global_transform.affine_inverse() * w3).z
	var out := true
	for d in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		var q: Vector2 = sp + d
		if not _blocked(cam.project_ray_origin(q), cam.project_position(q, depth)):
			out = false
			break
	cache[w3] = out
	return out


func _blocked(o: Vector3, w3: Vector3) -> bool:
	var d := w3.distance_to(o)
	if d < 1e-6:
		return false
	var tip := w3 + (o - w3) * (maxf(0.002, d * 0.004) / d)   # (a hair in front of the point)
	for e: Array in get_meta("occlusion", {}).get("o", []):
		var t: Transform3D = e[0]
		if not (e[1] as TriangleMesh).intersect_segment(t * o, t * tip).is_empty():
			return true
	return false


## A baked solid's hole and recess edges, shown only where they're on or in it: curve id -> {u, v,
## polys - the body's cross-section at that edge's height (between the body's bottom and top edges, a
## hair wider)}.
func edge_clips() -> Dictionary:
	var out := {}
	if ed == null or ed.model == null:
		return out
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		while str(spec.get("kind", "")) == "bool":
			spec = spec.get("a", {})
		if not spec.has("pieces"):
			continue
		var bodies := []   # each body outline: [bottom points, top points, its piece]
		var n := Vector3.UP
		for pc: Dictionary in spec["pieces"]:
			if str(pc.get("role", "add")) != "add" or (pc.get("loops", []) as Array).is_empty():
				continue
			var pair: Array = pc["loops"][0]
			var b := curve_by_id(int(pair[0]))
			var t := curve_by_id(int(pair[1]))
			if b.is_empty() or t.is_empty():
				continue
			n = (b.get("n", Vector3.UP) as Vector3).normalized()
			var sb := sample(b)
			var st := sample(t)
			var m := maxi(sb.size(), st.size())
			bodies.append([_resample_loop(sb, m) if sb.size() != m else sb, _resample_loop(st, m) if st.size() != m else st, pc])
		if bodies.is_empty():
			continue
		var u := _any_perp(n)
		var v := n.cross(u)
		for pc: Dictionary in spec["pieces"]:
			var cut := str(pc.get("role", "add")) == "cut"
			for pair in pc.get("loops", []):
				for id in pair:
					var c := curve_by_id(int(id))
					if c.is_empty():
						continue
					var h := _plane_height(sample(c), n)
					# (a hole's or recess's edge: only where it's in the body - a hair wider; a body's
					# edge: not where it's inside another body piece - a hair narrower)
					var ins := []
					var outs := []
					for bd in bodies:
						if not cut and bd[2] == pc:
							continue
						var f := _section(bd[0], bd[1], h, n, u, v)
						if f.size() >= 3:
							(ins if cut else outs).append_array(Geometry2D.offset_polygon(f, 2e-3 if cut else -2e-3))
					if cut or not outs.is_empty():
						out[int(id)] = {"u": u, "v": v, "polys": ins, "not": outs, "cut": cut}
	return out


## A body's cross-section at height `h` (between its bottom and top edges, point by point) in 2D.
static func _section(sb: PackedVector3Array, st: PackedVector3Array, h: float, n: Vector3, u: Vector3, v: Vector3) -> PackedVector2Array:
	var f := PackedVector2Array()
	for k in sb.size():
		var hb := sb[k].dot(n)
		var ht := st[k].dot(n)
		if h < minf(hb, ht) - 1e-3 or h > maxf(hb, ht) + 1e-3:
			return PackedVector2Array()
		var w := clampf((h - hb) / (ht - hb), 0.0, 1.0) if absf(ht - hb) > 1e-6 else 0.0
		var q := sb[k].lerp(st[k], w)
		f.append(Vector2(q.dot(u), q.dot(v)))
	if Geometry2D.is_polygon_clockwise(f):
		f.reverse()
	return f


static func _in_clip(q: Vector3, clip: Dictionary) -> bool:
	var p2 := Vector2(q.dot(clip["u"]), q.dot(clip["v"]))
	for f: PackedVector2Array in clip.get("not", []):
		if Geometry2D.is_point_in_polygon(p2, f):
			return false
	if not bool(clip.get("cut", false)):
		return true
	for f: PackedVector2Array in clip["polys"]:
		if Geometry2D.is_point_in_polygon(p2, f):
			return true
	return false


func _draw_plane(pl: Dictionary) -> void:
	var o: Vector3 = pl["o"]
	var u: Vector3 = pl["u"]
	var v: Vector3 = pl["v"]
	var c := cursor if cursor != Vector3.INF else o
	var step := grid_step
	while step < 0.02:
		step *= 5.0
	# (about 20 cells each way round the cursor, on the grid)
	var cu := snappedf((c - o).dot(u), step)
	var cv := snappedf((c - o).dot(v), step)
	var n := 10
	for i in range(-n, n + 1):
		var al := 0.22 * (1.0 - absf(i) / (n + 1))
		var a := o + u * (cu + i * step) + v * (cv - n * step)
		var b := o + u * (cu + i * step) + v * (cv + n * step)
		layer.draw_line(_screen(a), _screen(b), Color(0.6, 0.85, 1.0, al), 1.0)
		a = o + v * (cv + i * step) + u * (cu - n * step)
		b = o + v * (cv + i * step) + u * (cu + n * step)
		layer.draw_line(_screen(a), _screen(b), Color(0.6, 0.85, 1.0, al), 1.0)
