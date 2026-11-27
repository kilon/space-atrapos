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
	"line": ["Line", "m_cv_line", "L", "Click vertices on the plane: a polyline. Click its first vertex to close it; Enter, right-click\nor a double click ends it. Type a length + Enter for the next segment along the mouse's way."],
	"spline": ["Spline", "m_cv_spline", "P", "Click vertices: a smooth edge through them. Click the first vertex to close it; Enter or\nright-click ends it."],
	"circle": ["Circle", "m_cv_circle", "C", "Click the centre, then a vertex on the rim (or type the radius + Enter)."],
	"arc": ["Arc", "m_cv_arc", "Shift+C", "Three vertices: its start, its end, then one it passes through."],
	"rect": ["Rectangle", "m_cv_rect", "Shift+R", "Click a corner, then the opposite one (or type \"width height\" + Enter).\nAlt held: from the centre."],
	"polygon": ["Polygon", "m_cv_polygon", "Shift+P", "Click the centre, then a corner. The wheel or + / - sets how many sides (or type the radius + Enter)."],
}
const PICK_PX := 9.0
const HANDLE_PX := 10.0
const SNAP_PX := 12.0
const CURVE_COL := Color(0.45, 0.85, 1.0)
const PICKED_PT_COL := Color(1.0, 0.62, 0.15)
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
	_xf_tangents(o, x.basis)
	return o


## A manual vertex's tangents (directions: no move) turned by `b` with the curve's points.
static func _xf_tangents(c: Dictionary, b: Basis) -> void:
	for key_ in ["tin", "tout"]:
		if c.has(key_):
			var tv: PackedVector3Array = (c[key_] as PackedVector3Array).duplicate()
			for j in tv.size():
				tv[j] = b * tv[j]
			c[key_] = tv


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
	if has_meta("settling"):
		_settle_finish(false)   # (a let-go drag's settling: applied once worked out)
	_quads_step()
	if has_meta("finer_due") and not has_meta("settling"):
		var fd: Array = get_meta("finer_due")
		var fp = fd[0]
		if not is_instance_valid(fp) or not (fp as Node).has_meta("force_settle"):
			remove_meta("finer_due")
		else:
			var fsp: Dictionary = (fp as Node).get_meta("curve_solid", {})
			var bnet := -absi(int(fsp.get("net", 0))) - 1
			var fc = _edge_bases().get(bnet)
			if fc is Dictionary and (fc as Dictionary).has("bw") and not (fc as Dictionary).has("bw_job"):
				_changed_async("Finer mesh", fd[1])   # (its solver ready: made again from the finer bake)
				remove_meta("finer_due")
			elif not (fc is Dictionary) or (fc as Dictionary).is_empty():
				# (its bake's solver not made - it's made only while an edge differs from its last settle: made
				# now, on a worker; looked at again next frame)
				set_meta("cg_full", true)
				_edge_mesh(fp, _orig_view(fsp))
				remove_meta("cg_full")
	if has_meta("knife_due"):
		_knife_step()
	if has_meta("drag_due") and Engine.get_process_frames() > int((get_meta("drag_due") as Array)[2]):
		_flush_drag_due()   # (a frame after it began)
	if has_meta("panel_after_drag") and _drag.is_empty():
		# (held while something was dragged: filled the frame after it's over - not with the let-go's own work)
		if not has_meta("panel_after_at"):
			set_meta("panel_after_at", Engine.get_process_frames())
		elif Engine.get_process_frames() > int(get_meta("panel_after_at")):
			remove_meta("panel_after_drag")
			remove_meta("panel_after_at")
			_refresh_panel()
	if has_meta("lines_due"):
		remove_meta("lines_due")
		layer.queue_redraw()   # (the edges' lines still being made: on with them this frame)
	var idle_due := Time.get_ticks_msec() >= int(get_meta("warm_idle_at", 0))   # (all made ahead last time: looked at again 5 times a second, not every frame)
	if idle_due and not curves.is_empty() and guides_on() and not has_meta("settling") and not _converting():
		if _warm_face_levels() and (not has_meta("guides_warm_at") or Time.get_ticks_msec() - int(get_meta("guides_warm_at")) > 250):
			set_meta("guides_warm_at", Time.get_ticks_msec())   # (looked at four times a second, not every frame)
			_warm_guides()
	if idle_due and ed.model and not has_meta("settling") and not _converting():
		if not _warm_faces():
			set_meta("warm_idle_at", Time.get_ticks_msec() + 200)
		if not has_meta("pick_mi") and _drag.is_empty() and ed.model.get_parent():
			_pick_mi()
	if has_meta("remesh_job"):
		_remesh_step()
	if has_meta("join_job"):
		_join_step()
	elif has_meta("remesh_after") and not has_meta("remesh_job") and not has_meta("join_after") and not _converting():
		# (a bake done - and its joining: the full layout, field-aligned fill and all, worked out in the background)
		var ra = get_meta("remesh_after")
		remove_meta("remesh_after")
		var only_ch: Array = get_meta("remesh_after_only", [])
		remove_meta("remesh_after_only")
		var merge: bool = get_meta("remesh_after_merge", false)
		remove_meta("remesh_after_merge")
		if is_instance_valid(ra) and (ra as Node).is_inside_tree():
			remesh_solid(ra, "Lay out (the edit's faces)" if merge else ("Lay out (the knife's faces)" if not only_ch.is_empty() else "Lay out (the bake's topology)"), only_ch, merge)
	elif has_meta("join_after") and not _converting():
		# (a conversion done: the solids it made that meet along an edge joined)
		var ja: Array = get_meta("join_after")
		remove_meta("join_after")
		auto_join(ja.filter(func(x): return is_instance_valid(x)), true)
	_mats_step()
	if _converting():
		_convert_step()
	else:
		if has_meta("panel_due"):
			remove_meta("panel_due")
			ed._fill_parts()
			_refresh_panel()
		if has_meta("convert_batches"):
			_batches_step()
	if has_meta("orphans") and not (get_meta("orphans") as Array).is_empty():
		var left := []
		for id in get_meta("orphans"):
			if WorkerThreadPool.is_task_completed(int(id)):
				WorkerThreadPool.wait_for_task_completion(int(id))
			else:
				left.append(id)
		set_meta("orphans", left)
	if has_meta("edge_jobs"):
		# (a drag's frame worked out on a worker: shown once it's done)
		var waiting := false
		for p: MeshInstance3D in ed.parts():
			var sp: Dictionary = p.get_meta("curve_solid", {})
			if str(sp.get("kind", "")) != "edges":
				continue
			# (its own caches only - its mesh and its bake's: one solid's frame done doesn't make the
			# other ninety made again)
			var nid := int(sp.get("net", 0))
			for k in [nid, -absi(nid) - 1]:
				var cc = _edge_bases().get(k)
				if not (cc is Dictionary):
					continue
				for jk in ["drag_job", "look_job", "bw_job"]:
					if jk == "bw_job" and (_drag.is_empty() and op.is_empty() or not (cc as Dictionary).has("bw_wait")):
						continue   # (weights done for a solid no drag's waiting on: nothing to show for them)
					if (cc as Dictionary).has(jk):
						if WorkerThreadPool.is_task_completed(int(cc[jk][0])):
							p.remove_meta("curve_solid_key")
						else:
							waiting = true
		if not waiting:
			remove_meta("edge_jobs")
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
				sig = hash([sig, p.global_transform])   # (its collection moved: its edges with it)
		if sig != int(get_meta("placed_sig", 0)):
			set_meta("placed_sig", sig)
			layer.queue_redraw()
	# (the ghosts of the solids inside recipes: made again when a recipe, a place or a part's showing changes)
	var gs := ghost_sig()
	if gs != int(get_meta("ghost_sig", 0)):
		set_meta("ghost_sig", gs)
		update_ghosts()


func _exit_tree() -> void:
	if has_meta("remesh_job"):
		WorkerThreadPool.wait_for_task_completion(int(get_meta("remesh_job")[0]))   # (a remesh being worked out: never left running)
	for id in get_meta("orphans", []):
		WorkerThreadPool.wait_for_task_completion(int(id))
	for j in get_meta("convert_running", []):
		WorkerThreadPool.wait_for_task_completion(int(j[0]))   # (every solid still being made: never left running)
	if has_meta("edge_bases"):
		for k in (get_meta("edge_bases") as Dictionary):
			var c = get_meta("edge_bases")[k]
			if c is Dictionary and (c as Dictionary).has("drag_job"):
				WorkerThreadPool.wait_for_task_completion(int(c["drag_job"][0]))   # (a drag frame still being worked out)
	if has_meta("settling"):
		for h in (get_meta("settling") as Dictionary)["jobs"]:
			WorkerThreadPool.wait_for_task_completion(int(h[0]))
	for k in ["pick_mi", "lines_mi"]:
		if has_meta(k) and is_instance_valid(get_meta(k)):
			(get_meta(k) as Node).queue_free()   # (the picked patch's shading, the curves' lines: not left in the view)
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
			return path_pts(k, c.get("sharp", PackedByteArray()), closed, per, c.get("tin", PackedVector3Array()), c.get("tout", PackedVector3Array()))
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
static func path_pts(k: PackedVector3Array, sharp: PackedByteArray, closed: bool, per := 12, tin := PackedVector3Array(), tout := PackedVector3Array()) -> PackedVector3Array:
	var n := k.size()
	var corners := PackedInt32Array()
	for i in n:
		if (i < sharp.size() and sharp[i] >= 1) or (not closed and (i == 0 or i == n - 1)):
			corners.append(i)   # (a corner - or a vertex shaped by hand: the runs either side end there)
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
		var manual := (a < sharp.size() and sharp[a] == 2) or (b < sharp.size() and sharp[b] == 2)
		if manual:
			# (a run ending at a vertex shaped by hand: span by span, each a cubic - its tangent there the
			# one dragged out, the others as a smooth run's)
			var s := a
			while true:
				var t := (s + 1) % n
				var sp := _path_span(k, sharp, closed, tin, tout, s, per)
				sp.remove_at(sp.size() - 1)
				out.append_array(sp)
				s = t
				if s == b:
					break
		elif piece.size() <= 2:
			out.append(piece[0])   # (a straight side: its corner)
		else:
			var arc := _arc_run(piece)   # (its points on one circle - a boolean's arc: drawn exactly)
			var sp := arc if not arc.is_empty() else catmull(piece, false, per)
			sp.remove_at(sp.size() - 1)
			out.append_array(sp)
	if not closed:
		out.append(k[n - 1])
	return out


## A path's span from point `a` to the next: a cubic whose ends leave and arrive along each point's tangent
## (_path_tangent) - `per` + 1 points, both ends included.
static func _path_span(k: PackedVector3Array, sharp: PackedByteArray, closed: bool, tin: PackedVector3Array, tout: PackedVector3Array, a: int, per := 12) -> PackedVector3Array:
	var n := k.size()
	var b := (a + 1) % n
	var p0 := k[a]
	var p3 := k[b]
	var p1 := p0 + _path_tangent(k, sharp, closed, tin, tout, a, true) / 3.0
	var p2 := p3 - _path_tangent(k, sharp, closed, tin, tout, b, false) / 3.0
	var out := PackedVector3Array()
	for i in per + 1:
		var t := float(i) / per
		var u := 1.0 - t
		out.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
	return out


## A path's tangent at point `i`, leaving it (`out`) or arriving: a vertex shaped by hand - the one dragged
## out of it (tout / tin); a corner or an open end - straight along its side; a smooth bend - along the line
## from the point before it to the one after.
static func _path_tangent(k: PackedVector3Array, sharp: PackedByteArray, closed: bool, tin: PackedVector3Array, tout: PackedVector3Array, i: int, out: bool) -> Vector3:
	var n := k.size()
	var mode := int(sharp[i]) if i < sharp.size() else 0
	if mode == 2:
		var tv := tout if out else tin
		if i < tv.size():
			return tv[i]
	var has_prev := closed or i > 0
	var has_next := closed or i < n - 1
	var prev := k[(i - 1 + n) % n]
	var next := k[(i + 1) % n]
	if mode == 1 or mode == 2 or not has_prev or not has_next:
		# (a corner or an end: along the bend of the next two points that way, as a smooth run keeps it to
		# its end - straight when the next is a corner too: a straight side)
		var dir_ok := has_next if out else has_prev
		if not dir_ok:
			return (next - k[i]) if has_next else (k[i] - prev)
		var i1 := (i + 1) % n if out else (i - 1 + n) % n
		var i2 := (i + 2) % n if out else (i - 2 + n) % n
		var far_ok := closed or (i + 2 < n if out else i - 2 >= 0)
		var m1 := int(sharp[i1]) if i1 < sharp.size() else 0
		if not far_ok or m1 == 1 or (not closed and (i1 == 0 or i1 == n - 1)):
			return (k[i1] - k[i]) if out else (k[i] - k[i1])
		var d := (-3.0 * k[i] + 4.0 * k[i1] - k[i2]) * 0.5
		return d if out else -d
	return (next - prev) * 0.5


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
		"line", "spline": what = "click vertices · Enter / right-click: done · click the first: closed · Backspace: back"
		"circle": what = "centre, then the rim" if placed.is_empty() else "the rim (or type the radius)"
		"arc": what = ["its start", "its end", "a vertex it passes through"][mini(placed.size(), 2)]
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
	# (looked up by id through a map that checks itself - made again when it's out of date: thousands of
	# edges, a search each, every frame of a drag was most of its time)
	var i := int(_id_index.get(id, -1))
	if i >= 0 and i < curves.size() and int(curves[i].get("id", -1)) == id:
		return curves[i]
	if i < 0 and id <= int(_id_index.get(-2, -1)) and int(_id_index.get(-3, -1)) == curves.size():
		return {}   # (not there when the map was made, and older than it: gone - no search)
	_id_index = {}
	var top := -1
	for k in curves.size():
		var ck := int(curves[k].get("id", -1))
		_id_index[ck] = k
		top = maxi(top, ck)
	_id_index[-2] = top   # (the newest id then)
	_id_index[-3] = curves.size()
	i = int(_id_index.get(id, -1))
	return curves[i] if i >= 0 else {}


var _id_index := {}   # curve id -> its index in curves (checked on each use; -2: the newest id, -3: how many)


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
	if has_meta("knife_due"):
		_knife_step(true)   # (a knife cut still being finished: done first - this edit builds on it)
	_settle_finish()   # (a let-go drag still settling: landed first - an edit starting now builds on it)
	# (baked solids' recipes too: an edit settles their meshes - undo puts each back as it was)
	var specs := {}
	if ed and ed.model:
		for p: MeshInstance3D in ed.parts():
			var sp: Dictionary = p.get_meta("curve_solid", {})
			if str(sp.get("kind", "")) == "edges" and sp.has("mesh"):
				# (the copy made last time, when it's still the same - copies are never changed, so undo
				# states share them: ninety solids copied on every press were most of 10 ms)
				var last = p.get_meta("spec_snap") if p.has_meta("spec_snap") else null
				if last is Dictionary and _same_spec(sp, last):
					specs[p.get_instance_id()] = last
				else:
					var cp := _spec_copy(sp)
					p.set_meta("spec_snap", cp)
					specs[p.get_instance_id()] = cp
	return [curves.duplicate(true), sel.duplicate(), specs]


## Baked solid recipes `a` (as it is) and `b` (a copy for undo) the same - their meshes the very same lists
## (shared by _spec_copy: only ever replaced), the rest equal.
static func _same_spec(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
		if k == "mesh" or k == "orig":
			var am = a[k]
			var bm = b[k]
			if not (am is Dictionary and bm is Dictionary) or (am as Dictionary).size() != (bm as Dictionary).size():
				return false
			for k2 in am:
				if not (bm as Dictionary).has(k2):
					return false
				var x = am[k2]
				var y = bm[k2]
				if k2 == "mesh" and x is Dictionary and y is Dictionary:
					if not (is_same(x.get("v"), y.get("v")) and is_same(x.get("t"), y.get("t"))):
						return false
				elif (x is Array and y is Array and (x as Array).size() > 64) or k2 in ["v", "t"]:
					if not is_same(x, y):
						return false
				elif x != y:
					return false
		elif k == "fv":
			if not is_same(a[k], b[k]):
				return false
		elif a[k] != b[k]:
			return false
	return true


## A baked solid's recipe copied for undo - all of it but its meshes' point and triangle lists, shared
## (those are only ever replaced, never changed in place: ninety solids' meshes copied on every press
## were 20 ms of it).
static func _spec_copy(sp: Dictionary) -> Dictionary:
	var top := sp.duplicate(false)
	var mesh = top.get("mesh")
	var orig = top.get("orig")
	var fv = top.get("fv")
	for k in ["mesh", "orig", "fv"]:
		top.erase(k)
	var out := top.duplicate(true)   # (its edges' curves as made, chains, ids: changed in place at times - copied)
	if mesh is Dictionary:
		out["mesh"] = (mesh as Dictionary).duplicate(false)
	if fv != null:
		out["fv"] = fv   # (edge points: a new list each time they change)
	if orig is Dictionary:
		var o: Dictionary = (orig as Dictionary).duplicate(false)   # (the bake: its parts only ever replaced)
		if o.get("mesh") is Dictionary:
			o["mesh"] = (o["mesh"] as Dictionary).duplicate(false)
		out["orig"] = o
	return out


func _set_state(st: Array) -> void:
	curves = st[0].duplicate(true)
	sel = st[1].duplicate()
	if st.size() > 2:
		for pid in st[2]:
			var p = instance_from_id(int(pid))
			if p is MeshInstance3D and is_instance_valid(p):
				if _same_spec((p as MeshInstance3D).get_meta("curve_solid", {}), st[2][pid]):
					continue   # (as it was: its mesh, solver and look kept - not ninety solids made again)
				var sp: Dictionary = _spec_copy(st[2][pid])
				(p as MeshInstance3D).set_meta("curve_solid", sp)
				(p as MeshInstance3D).remove_meta("curve_solid_key")
				_edge_bases().erase(int(sp.get("net", 0)))
	refresh_solids()
	_refresh_panel()
	layer.queue_redraw()


## One undo step from `before` to now (a baked solid an edit reshaped: settled first - in the step).
func _changed(name: String, before: Array) -> void:
	_settle_finish()
	refresh_solids()
	settle_edges()
	_record(name, before)


## The undo step from `before` to now.
func _record(name: String, before: Array) -> void:
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


# --- every model an ECurve object: solids that aren't yet made of edges converted -------------------

## The most edges a converted solid may have (more: it stays a mesh - a character's faceted body).
const MAX_CONVERT_EDGES := 600   # (traced edges; the sharp mesh edges before tracing: 8 times this)


## Parts `ps` that aren't ECurve solids yet (plain meshes - an imported or older model, a game model)
## queued to be made ones: each in its turn on a worker - its edges traced (EdgeNet.trace), each a curve,
## an even mesh of quads made between them and readied for editing - then put in its place. A part with
## no edges to trace stays a mesh (said so).
func convert_parts(ps: Array, batch := {}) -> void:
	var q: Array = get_meta("convert_queue", [])
	if not _converting():
		set_meta("convert_done", 0)   # (a new batch: counted from here, for the progress bar)
	if not batch.is_empty():
		# (when all of them are done: what to do - store the object as an ECurve object; nothing to
		# convert - stored as one already: nothing stored again)
		batch["parts"] = ps.filter(func(x): return x is MeshInstance3D and is_instance_valid(x) and not (x as Node).has_meta("curve_solid"))
		if not (batch["parts"] as Array).is_empty():
			var bs: Array = get_meta("convert_batches", [])
			bs.append(batch)
			set_meta("convert_batches", bs)
	for p in ps:
		if p is MeshInstance3D and is_instance_valid(p) and not (p as Node).has_meta("curve_solid") and (p as MeshInstance3D).mesh != null and not (p as Node).has_meta("ecurve_failed") and not p in q:
			q.append(p)
	set_meta("convert_queue", q)


## How the conversion's going: {name (the solid being made), stage, frac (0..1 of it), index, total} -
## {} when nothing's being converted.
func convert_progress() -> Dictionary:
	var q: Array = get_meta("convert_queue", [])
	if not _converting():
		return {}
	var done := int(get_meta("convert_done", 0))
	var later := q.size() + (get_meta("convert_running", []) as Array).size() + (get_meta("convert_ready", []) as Array).size()
	if has_meta("convert_reveal"):
		var rv: Dictionary = get_meta("convert_reveal")
		var nf := int(rv.get("n", 1))
		return {"name": str((rv["p"] as Node).name) if is_instance_valid(rv["p"]) else "", "stage": "face %d of %d" % [mini(int(rv["shown"]), nf), nf],
			"frac": 0.9 + 0.1 * clampf(float(rv["shown"]) / maxf(1.0, nf), 0.0, 1.0), "index": done, "total": done + later + 1, "at_once": (get_meta("convert_running", []) as Array).size()}
	var out := {"name": "", "stage": "waiting", "frac": 0.0, "index": done, "total": done + later, "at_once": (get_meta("convert_running", []) as Array).size()}
	if has_meta("convert_job"):
		var j: Array = get_meta("convert_job")
		var h: Array = j[1]
		out["name"] = str((j[2] as Node).name) if is_instance_valid(j[2]) else ""
		out["frac"] = float(h[1]) if h.size() > 1 else 0.0
		out["stage"] = str(h[2]) if h.size() > 2 else ""
		if j.size() > 3 and str(j[3]) == "split":
			out["stage"] = "finding its pieces"
	return out


## (while a solid's converted) Its edges, as soon as they're traced, drawn over it in the view - orange
## lines, seen through it - so the work shows step by step; gone when it's done.
func _convert_preview(j: Array) -> void:
	var h: Array = j[1]
	var p = j[2]
	if h.size() < 4 or h[3] == null or not (p is MeshInstance3D) or not is_instance_valid(p) or ed.model == null or ed.model.get_parent() == null:
		return
	var made := int(h[4]) if h.size() > 4 else 0
	var mi := _convert_preview_node(p)
	if mi == null:
		return
	if mi.get_meta("made", -1) != made or (mi.get_meta("for") if mi.has_meta("for") else null) != h:
		mi.set_meta("made", made)
		mi.set_meta("for", h)
		mi.mesh = _edge_lines_mesh(h[3], made)
	ed.view.request()


## The preview's node (made once, over part `p`).
func _convert_preview_node(p: MeshInstance3D) -> MeshInstance3D:
	var mi: MeshInstance3D = get_meta("convert_preview") if has_meta("convert_preview") and is_instance_valid(get_meta("convert_preview")) else null
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "ConvertPreview"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ed.model.get_parent().add_child(mi)
		set_meta("convert_preview", mi)
	mi.global_transform = p.global_transform
	return mi


static func _preview_mat(col: Color, through: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = through
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## The traced edges as lines: the first `made` (made curves already) bright, the rest faint.
func _edge_lines_mesh(traced: Array, made: int) -> ArrayMesh:
	var m := ArrayMesh.new()
	for part in 2:
		var v := PackedVector3Array()
		for i in traced.size():
			if (i < made) != (part == 0):
				continue
			var pts: PackedVector3Array = traced[i][0]
			for k in pts.size() - 1:
				v.append(pts[k])
				v.append(pts[k + 1])
			if bool(traced[i][1]) and pts.size() > 2:
				v.append(pts[pts.size() - 1])
				v.append(pts[0])
		if v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
		m.surface_set_material(m.get_surface_count() - 1, _preview_mat(Color(PICKED_PT_COL, 1.0) if part == 0 else Color(1, 1, 1, 0.35), true))
	return m


## (revealing a converted solid) Its first `shown` faces drawn over it, with all its edges.
func _convert_preview_faces(rv: Dictionary) -> void:
	var p = rv["p"]
	if not (p is MeshInstance3D) or not is_instance_valid(p):
		return
	var mi := _convert_preview_node(p)
	if not rv.has("mat"):
		# (made once: every face's triangles, each with its face's number - the shader shows the first
		# `shown` of them; each frame after that sets one number, nothing rebuilt)
		var r: Dictionary = rv["r"]
		var v: PackedVector3Array = r["v"]
		var t: PackedInt32Array = r["t"]
		var fo: PackedInt32Array = r["face_of"]
		var tv := PackedVector3Array()
		var uv := PackedVector2Array()
		tv.resize(fo.size() * 3)
		uv.resize(fo.size() * 3)
		for ti in fo.size():
			for j in 3:
				tv[ti * 3 + j] = v[t[ti * 3 + j]]
				uv[ti * 3 + j] = Vector2(fo[ti] + 0.5, 0.0)
		var h: Array = rv["h"]
		var m := _edge_lines_mesh(h[3] if h.size() > 3 and h[3] != null else [], 1 << 30)
		var mat := ShaderMaterial.new()
		mat.shader = _reveal_shader()
		mat.set_shader_parameter("col", Color(PICKED_PT_COL, 0.45))
		if not tv.is_empty():
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = tv
			arr[Mesh.ARRAY_TEX_UV] = uv
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(m.get_surface_count() - 1, mat)
		mi.mesh = m
		rv["mat"] = mat
	(rv["mat"] as ShaderMaterial).set_shader_parameter("shown", float(rv["shown"]))
	ed.view.request()


static var _reveal_sh: Shader = null

## The face reveal's shader: a see-through tint on the faces numbered under `shown`, the rest not drawn.
static func _reveal_shader() -> Shader:
	if _reveal_sh == null:
		_reveal_sh = Shader.new()
		_reveal_sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, blend_mix, depth_draw_never;\nuniform vec4 col : source_color;\nuniform float shown = 0.0;\nvarying float face;\nvoid vertex() { face = UV.x; }\nvoid fragment() {\n\tif (face > shown) { discard; }\n\tALBEDO = col.rgb;\n\tALPHA = col.a;\n}\n"
	return _reveal_sh


func _convert_preview_clear() -> void:
	if has_meta("convert_preview"):
		var mi = get_meta("convert_preview")
		if is_instance_valid(mi):
			(mi as Node).queue_free()
		remove_meta("convert_preview")
		if ed and ed.view:
			ed.view.request()


## (on a worker) A mesh's separate pieces (`surfaces`: its surfaces' arrays): triangles of one surface
## (one material) joined through shared points (by place) are one piece; a triangle doubled back to back (a two-sided face) kept once.
## [piece: [per surface: its arrays (only that piece's triangles and points; [] - none there)]], or []
## when it's all one piece.
static func _split_islands(EN: GDScript, surfaces: Array) -> Array:
	var uf := {}
	var root_of := func(k):
		var r = k
		while uf[r] != r:
			uf[r] = uf[uf[r]]
			r = uf[r]
		return r
	var tri_keys := []   # per surface: [keys of each triangle]
	var seen := {}
	var keep := []   # per surface: PackedByteArray - the triangle kept
	for si in surfaces.size():
		var a: Array = surfaces[si]
		var tk := []
		var kp := PackedByteArray()
		if a.is_empty():
			tri_keys.append(tk)
			keep.append(kp)
			continue
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		kp.resize(ix.size() / 3)
		for t in range(0, ix.size(), 3):
			# (a point's place and its surface: a piece never spans two materials - each solid keeps its own)
			var ks := [[si, EN.key(v[ix[t]])], [si, EN.key(v[ix[t + 1]])], [si, EN.key(v[ix[t + 2]])]]
			tk.append(ks)
			var sk := ks.duplicate()
			sk.sort()
			var dk := hash(sk)
			if seen.has(dk) or ks[0] == ks[1] or ks[1] == ks[2] or ks[0] == ks[2]:
				continue   # (back to back with one kept, or no area)
			seen[dk] = true
			kp[t / 3] = 1
			for k in ks:
				if not uf.has(k):
					uf[k] = k
			var r0 = root_of.call(ks[0])
			for jj in [1, 2]:
				var rj = root_of.call(ks[jj])
				if rj != r0:
					uf[rj] = r0
		tri_keys.append(tk)
		keep.append(kp)
	var piece_of := {}   # root -> piece index
	for si in surfaces.size():
		for ti in (tri_keys[si] as Array).size():
			if keep[si][ti] == 1:
				var r = root_of.call(tri_keys[si][ti][0])
				if not piece_of.has(r):
					piece_of[r] = piece_of.size()
	if piece_of.size() <= 1:
		return []
	var out := []
	for k in piece_of.size():
		var per := []
		for si in surfaces.size():
			per.append([])
		out.append(per)
	for si in surfaces.size():
		var a: Array = surfaces[si]
		if a.is_empty():
			continue
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nv := v.size()
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(nv))
		var tris_of := {}   # piece -> [triangle indices]
		for ti in (tri_keys[si] as Array).size():
			if keep[si][ti] == 0:
				continue
			var pc: int = piece_of[root_of.call(tri_keys[si][ti][0])]
			if not tris_of.has(pc):
				tris_of[pc] = PackedInt32Array()
			tris_of[pc].append(ti)
		for pc in tris_of:
			var remap := {}
			var order := PackedInt32Array()
			var nix := PackedInt32Array()
			for ti in (tris_of[pc] as PackedInt32Array):
				for j in 3:
					var vi := ix[ti * 3 + j]
					if not remap.has(vi):
						remap[vi] = order.size()
						order.append(vi)
					nix.append(remap[vi])
			var na := []
			na.resize(Mesh.ARRAY_MAX)
			for at in Mesh.ARRAY_MAX:
				if at == Mesh.ARRAY_INDEX or a[at] == null:
					continue
				var arr = a[at]
				var per_v: int = arr.size() / maxi(nv, 1) if nv > 0 else 0
				if per_v <= 0 or arr.size() != per_v * nv:
					continue
				var dst = arr.duplicate()
				dst.resize(order.size() * per_v)
				for i in order.size():
					for c in per_v:
						dst[i * per_v + c] = arr[order[i] * per_v + c]
				na[at] = dst
			na[Mesh.ARRAY_INDEX] = nix
			out[pc][si] = na
	return out


## (worker) Each piece's mesh made there ({pieces, bones} from _group_pieces; "meshes" added): putting
## dozens of them in on the editor's thread was a 30 ms frame.
static func _piece_meshes(gp: Dictionary) -> Dictionary:
	var ms := []
	for per in gp["pieces"]:
		ms.append(_piece_mesh(per))
	gp["meshes"] = ms
	return gp


## A piece's arrays (one a surface; [] - none there) as a mesh, its surfaces in order, no materials yet.
static func _piece_mesh(per: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	for arr: Array in per:
		if arr.is_empty():
			continue
		var flags := 0
		var w = arr[Mesh.ARRAY_WEIGHTS]
		var vv = arr[Mesh.ARRAY_VERTEX]
		if w != null and vv != null and (w as PackedFloat32Array).size() == (vv as PackedVector3Array).size() * 8:
			flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return m


## (on a worker) A part's pieces (_split_islands) joined into as few solids as make sense: the pieces of
## one material that move with the same bone (most of their weight on it) one solid - a hand's fingers,
## a boot's buckles - up to GROUP_TRIS triangles a solid (an ECurve solid that big is slow to reshape).
## {"pieces": [as _split_islands], "bones": [per piece: its bone's index in the skin, -1: none]}.
const GROUP_TRIS := 6000

static func _group_pieces(pieces: Array) -> Dictionary:
	if pieces.is_empty():
		return {"pieces": [], "bones": []}
	var groups := {}   # [surface, bone] -> [[piece indices], triangles]
	var order := []
	for k in pieces.size():
		var per: Array = pieces[k]
		var si := -1
		for s2 in per.size():
			if not (per[s2] as Array).is_empty():
				si = s2
				break
		if si < 0:
			continue
		var a: Array = per[si]
		var bone := -1
		var bo = a[Mesh.ARRAY_BONES]
		var wt = a[Mesh.ARRAY_WEIGHTS]
		var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if bo != null and wt != null and vv.size() > 0 and (bo as PackedInt32Array).size() == (wt as PackedFloat32Array).size():
			var per_v: int = (bo as PackedInt32Array).size() / vv.size()
			var sum := {}
			for i in (bo as PackedInt32Array).size():
				var w: float = wt[i]
				if w > 0.0:
					sum[bo[i]] = float(sum.get(bo[i], 0.0)) + w
			var best := 0.0
			for b in sum:
				if float(sum[b]) > best:
					best = sum[b]
					bone = int(b)
			if per_v <= 0:
				bone = -1
		var tris: int = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var gk := [si, bone]
		if groups.has(gk) and int(groups[gk][1]) + tris > GROUP_TRIS:
			groups[[si, bone, order.size()]] = groups[gk]   # (full: kept under another key, a new one started)
			groups.erase(gk)
		if not groups.has(gk):
			groups[gk] = [[], 0, si, bone]
			order.append(groups[gk])
		groups[gk][0].append(k)
		groups[gk][1] = int(groups[gk][1]) + tris
	var out := []
	var bones := []
	for g in order:
		var ks: Array = g[0]
		var si: int = g[2]
		var per := []
		for s2 in (pieces[ks[0]] as Array).size():
			per.append([])
		per[si] = _join_arrays(ks.map(func(k): return pieces[k][si]))
		out.append(per)
		bones.append(int(g[3]))
	return {"pieces": out, "bones": bones}


## (on a worker) Surfaces' arrays (same format) made one: their points one after another, their
## triangles renumbered.
static func _join_arrays(list: Array) -> Array:
	if list.size() == 1:
		return list[0]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var nv := 0
	var ix := PackedInt32Array()
	for a: Array in list:
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for at in Mesh.ARRAY_MAX:
			if at == Mesh.ARRAY_INDEX or a[at] == null:
				continue
			if out[at] == null:
				out[at] = a[at].duplicate()
			else:
				out[at].append_array(a[at])
		for q in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
			ix.append(q + nv)
		nv += v.size()
	out[Mesh.ARRAY_INDEX] = ix
	return out


## A solid's name from what it is: the bone it moves with ("upper_arm.L" -> "Upper arm L"), else its
## material's name, else its part's - with a number when the collection has one of that name already.
static func _piece_name(bone: String, mat_name: String, fallback: String, taken: Dictionary) -> String:
	var base := ""
	var b := bone
	for pre in ["DEF-", "DEF_", "ORG-", "MCH-", "mixamorig:", "Bone_", "AUT_", "MIN_"]:
		if b.begins_with(pre):
			b = b.substr(pre.length())
	if b != "":
		base = b.replace("_", " ").replace(".", " ").replace("-", " ").strip_edges().capitalize()
	var m := mat_name
	for pre in ["AUT_", "MIN_", "PIR_", "KIL_"]:
		if m.begins_with(pre):
			m = m.substr(pre.length())
	m = m.replace("_", " ").strip_edges().capitalize()
	if base != "" and m != "" and m.to_lower().begins_with(base.to_lower()):
		base = m   # ("Gun" + "Gun Orange": "Gun Orange")
	elif base != "" and m != "" and m.to_lower() != base.to_lower():
		base = "%s %s" % [base, m]
	elif base == "":
		base = m if m != "" else fallback
	var name := base
	var n := 2
	while taken.has(name.to_lower()):
		name = "%s %d" % [base, n]
		n += 1
	taken[name.to_lower()] = true
	return name.validate_node_name()


## A part found to be several pieces made a collection of them (named after it, where it was): each
## piece a solid of its own (its materials, its skin) - then each made an ECurve solid in its turn.
func _split_apply(p: MeshInstance3D, pieces: Array, bones := [], made_meshes := []) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	p.set_meta("ecurve_split", true)
	if pieces.is_empty():
		convert_parts([p])   # (all one piece: made an ECurve solid as it is)
		var q0: Array = get_meta("convert_queue", [])
		q0.erase(p)
		q0.push_front(p)
		set_meta("convert_queue", q0)
		return
	var parent := p.get_parent()
	var pname := str(p.name)
	p.name = pname + "_was"   # (its collection takes its name)
	var g := Node3D.new()
	# (a character's Body: the game finds its body by that name - the biggest piece keeps it, the
	# collection is its solids)
	g.name = pname + " solids" if pname == "Body" else pname
	_mark_group(g)
	g.transform = p.transform
	parent.add_child(g)
	parent.move_child(g, p.get_index())
	g.owner = ed.model
	var skel: Node = p.get_node_or_null(p.skeleton) if p.skin != null else null
	var skin: Skin = p.skin if p.skin != null else (p.get_meta("src_skin") if p.has_meta("src_skin") and p.get_meta("src_skin") is Skin else null)
	var taken := {}
	var made := []
	for k in pieces.size():
		var per: Array = pieces[k]
		var m: ArrayMesh = made_meshes[k] if k < made_meshes.size() and made_meshes[k] != null else _piece_mesh(per)
		var surf_i := 0
		for si in per.size():
			if (per[si] as Array).is_empty():
				continue
			var mat: Material = p.get_surface_override_material(si) if si < p.mesh.get_surface_count() and p.get_surface_override_material(si) else (p.mesh.surface_get_material(si) if si < p.mesh.get_surface_count() else null)
			m.surface_set_material(surf_i, mat)
			surf_i += 1
		if m.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		# (named after the bone it moves with and its material: "Forearm L Armor", not "Body 37")
		var bname := ""
		var bi: int = int(bones[k]) if k < bones.size() else -1
		var src_bones: PackedStringArray = p.get_meta("src_bones") if p.has_meta("src_bones") else PackedStringArray()
		if bi >= 0:
			if bi < src_bones.size() and src_bones[bi] != "":
				bname = src_bones[bi]
			elif skin and bi < skin.get_bind_count():
				bname = str(skin.get_bind_name(bi))
				if bname == "" and skel is Skeleton3D and skin.get_bind_bone(bi) >= 0:
					bname = (skel as Skeleton3D).get_bone_name(skin.get_bind_bone(bi))
			elif skel is Skeleton3D and bi < (skel as Skeleton3D).get_bone_count():
				bname = (skel as Skeleton3D).get_bone_name(bi)
		var m0: Material = m.surface_get_material(0)
		var mname := str(m0.resource_name) if m0 else ""
		mi.name = _piece_name(bname, mname, "%s %d" % [pname, k + 1], taken)
		if bname != "":
			mi.set_meta("ecurve_bone", bname)   # (the bone it moves with: kept in its recipe - the T-pose turns it by it)
		mi.mesh = m
		mi.material_override = p.material_override
		mi.set_meta("ecurve_split", true)
		g.add_child(mi)
		mi.owner = ed.model
		if skel:
			mi.skin = p.skin
			mi.skeleton = mi.get_path_to(skel)
		elif p.has_meta("src_skin"):
			mi.set_meta("src_skin", p.get_meta("src_skin"))
		if p.has_meta("src_bones"):
			mi.set_meta("src_bones", p.get_meta("src_bones"))
		made.append(mi)
	if pname == "Body" and not made.is_empty():
		var big: MeshInstance3D = made[0]
		for mi2: MeshInstance3D in made:
			if mi2.mesh.get_faces().size() > big.mesh.get_faces().size():
				big = mi2
		big.name = "Body"
	if ed.part == p:
		ed.part = null
	parent.remove_child(p)
	p.queue_free()
	var q: Array = get_meta("convert_queue", [])
	for i in range(made.size() - 1, -1, -1):
		q.push_front(made[i])
	set_meta("convert_queue", q)
	set_meta("panel_due", true)
	ed.view.request()
	ed._say("%s: %d pieces - each made an ECurve solid in turn." % [g.name, made.size()])
	_batch_swap(p, made)


## A part of a batch split into pieces: the pieces stand for it.
func _batch_swap(p: Node, pieces: Array) -> void:
	for b in get_meta("convert_batches", []):
		var ps: Array = b["parts"]
		if p in ps:
			ps.erase(p)
			ps.append_array(pieces)


## (each frame, when nothing's being converted) Each batch whose parts are all done: finished - its object
## stored as an ECurve object (MeshEditor.store_converted), so it isn't converted again.
func _batches_step() -> void:
	var bs: Array = get_meta("convert_batches", [])
	if bs.is_empty() or _converting() or has_meta("join_after") or has_meta("join_job"):
		return   # (its solids joined first, then stored)
	set_meta("convert_batches", [])
	for b in bs:
		ed.store_converted(b)


## Whether parts are being made ECurve solids (queued, on workers, or being shown and put in place).
func _converting() -> bool:
	return has_meta("convert_reveal") or not (get_meta("convert_queue", []) as Array).is_empty() \
		or not (get_meta("convert_running", []) as Array).is_empty() or not (get_meta("convert_ready", []) as Array).is_empty()


## How many solids are made at once: each on a worker of its own - all but two of the machine's cores
## (the editor's frames and the renderer keep theirs).
static func convert_workers() -> int:
	return clampi(OS.get_processor_count() - 2, 1, 16)


## (each frame) Solids finished on their workers taken in (in the order they were queued: shown face by
## face, then put in place, one at a time); more started while workers are free - several at once.
func _convert_step() -> void:
	var run: Array = get_meta("convert_running", [])
	var ready: Array = get_meta("convert_ready", [])
	for j in run.duplicate():
		if not WorkerThreadPool.is_task_completed(int(j[0])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(j[0]))
		run.erase(j)
		if j.size() > 3 and str(j[3]) == "split":
			var gp: Dictionary = j[1][0]
			_split_apply(j[2], gp["pieces"], gp["bones"], gp.get("meshes", []))
		else:
			ready.append(j)
	# (in the order they were started: a quick small one waits for the big one before it)
	ready.sort_custom(func(x, y): return int(x[4]) < int(y[4]))
	var waiting := (get_meta("convert_queue", []) as Array).size() + run.size() + ready.size()
	if has_meta("convert_reveal"):
		var rv: Dictionary = get_meta("convert_reveal")
		var fo: PackedInt32Array = rv["r"]["face_of"]
		var nf := 0
		for f in fo:
			nf = maxi(nf, f + 1)
		rv["n"] = nf
		var frames := 40.0 if waiting < 4 else (12.0 if waiting < 40 else 3.0)   # (many still to make: quicker)
		rv["shown"] = int(rv["shown"]) + maxi(1, ceili(nf / frames))   # (about two-thirds of a second when few)
		_convert_preview_faces(rv)
		if int(rv["shown"]) >= nf + maxi(1, ceili(nf / frames)) * (6 if waiting < 4 else 1):   # (a moment with all of them shown)
			remove_meta("convert_reveal")
			_convert_preview_clear()
			set_meta("convert_done", int(get_meta("convert_done", 0)) + 1)
			_convert_apply(rv["p"], rv["r"])
	elif not ready.is_empty() and (run.is_empty() or int(ready[0][4]) < int(run.map(func(x): return int(x[4])).min())):
		var j: Array = ready.pop_front()
		var res: Dictionary = j[1][0]
		_convert_preview_clear()
		if res.has("face_of") and is_instance_valid(j[2]):
			# (made: its faces shown one by one over it, then it's put in place)
			set_meta("convert_reveal", {"p": j[2], "r": res, "shown": 0, "h": j[1]})
		else:
			set_meta("convert_done", int(get_meta("convert_done", 0)) + 1)
			_convert_apply(j[2], res)
	var q: Array = get_meta("convert_queue", [])
	var splitting := run.any(func(x): return x.size() > 3 and str(x[3]) == "split")
	var t_start := Time.get_ticks_usec()
	# (a few started a frame - each one's mesh copied here first: two dozen at once was a 60 ms frame)
	while not q.is_empty() and run.size() < convert_workers() and not splitting and Time.get_ticks_usec() - t_start < 4000:
		var p = q.front()
		if not (p is MeshInstance3D) or not is_instance_valid(p) or not (p as Node).is_inside_tree() or (p as Node).has_meta("curve_solid"):
			q.pop_front()
			continue
		if not (p as Node).has_meta("ecurve_split"):
			# (first: its separate pieces - a character's body is dozens of parts in one mesh - each a solid
			# of its own, in a collection named after it; worked out on a worker, the others waiting for it)
			if not run.is_empty():
				break
			q.pop_front()
			var surf := []
			var mm: Mesh = (p as MeshInstance3D).mesh
			for si in mm.get_surface_count():
				surf.append(mm.surface_get_arrays(si) if mm.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES else [])
			var EN0: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
			var hs := [null, 0.0, "finding its pieces"]
			var sid := WorkerThreadPool.add_task(func(): hs[0] = _piece_meshes(_group_pieces(_split_islands(EN0, surf))))
			run.append([sid, hs, p, "split", _next_order()])
			splitting = true
			break
		q.pop_front()
		var src = _flat_copy_mesh((p as MeshInstance3D).mesh)
		if src == null:
			continue
		var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
		var mat: Material = (p as MeshInstance3D).get_surface_override_material(0) if (p as MeshInstance3D).mesh.get_surface_count() > 0 and (p as MeshInstance3D).get_surface_override_material(0) else ((p as MeshInstance3D).mesh.surface_get_material(0) if (p as MeshInstance3D).mesh.get_surface_count() > 0 else null)
		var h := [null, 0.0, "starting", null, 0]   # (its result; how far it's got, at what, its edges once traced, how many made curves - written by the worker)
		var id := WorkerThreadPool.add_task(func(): h[0] = _convert_compute(EN, src, mat, h))
		(p as Node).set_meta("convert_from", (p as MeshInstance3D).mesh)   # (what it was made from: changed meanwhile - not put in)
		run.append([id, h, p, "solid", _next_order()])
	set_meta("convert_queue", q)
	set_meta("convert_running", run)
	set_meta("convert_ready", ready)
	# (the one being made that's next to be put in: its edges drawn over it as they're traced)
	if run.is_empty():
		remove_meta("convert_job")
	else:
		var first: Array = run[0]
		for x in run:
			if int(x[4]) < int(first[4]):
				first = x
		set_meta("convert_job", first)
		if not has_meta("convert_reveal") and str(first[3]) != "split":
			_convert_preview(first)


func _next_order() -> int:
	var n := int(get_meta("convert_order", 0)) + 1
	set_meta("convert_order", n)
	return n


## A part's mesh as one plain surface (points and triangles only - what tracing reads).
static func _flat_copy_mesh(m: Mesh) -> RefCounted:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for si in m.get_surface_count():
		if m.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a: Array = m.surface_get_arrays(si)
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var sx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
		var base := v.size()
		v.append_array(sv)
		for i in sx:
			idx.append(base + i)
	if idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var out = load("res://scripts/editor/mesh/mesh_data.gd").new()   # (plain arrays: read on a worker safely)
	out.surfaces.append(arr)
	return out


## (on a worker) Mesh `src` made an ECurve solid: its edges traced, each a lean curve, an even mesh of
## quads between them, readied (_prepare_edges). {curves (no ids yet), closed, v, t, fv, up, cache, mesh}
## - or {error}.
static func _convert_compute(EN: GDScript, src: RefCounted, mat: Material, progress := [null, 0.0, ""]) -> Dictionary:
	progress[1] = 0.02
	progress[2] = "looking at its edges"
	var t_start := Time.get_ticks_msec()
	var times := {}
	# (a quick look first: how many of its edges are sharp - a faceted body has thousands; tracing those
	# would take long and make nothing worth editing)
	var a0: Array = src.surface_get_arrays(0)
	var v0: PackedVector3Array = a0[Mesh.ARRAY_VERTEX]
	var x0: PackedInt32Array = a0[Mesh.ARRAY_INDEX]
	var weld := {}
	var wi := PackedInt32Array()
	wi.resize(v0.size())
	for i in v0.size():
		var k: Vector3i = EN.key(v0[i])
		if not weld.has(k):
			weld[k] = weld.size()
		wi[i] = weld[k]
	var by_e := {}
	for ti in range(0, x0.size(), 3):
		var n := (v0[x0[ti + 2]] - v0[x0[ti]]).cross(v0[x0[ti + 1]] - v0[x0[ti]]).normalized()
		for j in 3:
			var a := wi[x0[ti + j]]
			var b := wi[x0[ti + (j + 1) % 3]]
			var ek := Vector2i(mini(a, b), maxi(a, b))
			if not by_e.has(ek):
				by_e[ek] = []
			by_e[ek].append(n)
	# (how sharp an edge must be to be one: the least of these that keeps its edges few - a faceted
	# piece's facets are faces, not edges)
	# (from 45°: softer creases are part of a face's curve, not edges of their own - fewer edges, each one
	# that matters)
	var ths := [45.0, 60.0, 75.0, 89.0]
	var counts := [0, 0, 0, 0]
	var open_n := 0
	for ek in by_e:
		var ns: Array = by_e[ek]
		if ns.size() != 2:
			open_n += 1
			continue
		var ang := rad_to_deg((ns[0] as Vector3).angle_to(ns[1]))
		for k in ths.size():
			if ang > ths[k]:
				counts[k] += 1
	var th := -1.0
	for k in ths.size():
		if counts[k] + open_n <= MAX_CONVERT_EDGES * 4:
			th = ths[k]
			break
	if th < 0.0:
		return {"error": "too finely faceted to be made of edges (%d sharp edges even at 89°)" % (counts[ths.size() - 1] + open_n)}
	progress[1] = 0.1
	progress[2] = "tracing its edges"
	var net: Dictionary = EN.trace(src, th)
	if (net["chains"] as Array).is_empty():
		# (smooth all over - an eye, a ball, a rounded cap: a seam round its middle, along its own mesh's
		# edges, is its edge - an ECurve solid all the same)
		net = {"chains": _seam_loops(EN, a0)}
		if (net["chains"] as Array).is_empty():
			return {"error": "no edges to trace (smooth all over)"}
	if (net["chains"] as Array).size() > MAX_CONVERT_EDGES:
		# (a sculpted or faceted body - a character's: every facet's edge an edge; no ECurve object worth
		# editing comes of it)
		return {"error": "too finely faceted to be made of edges (%d of them)" % (net["chains"] as Array).size()}
	var must_keep := {}
	var seen_k := {}
	for ch0: Dictionary in net["chains"]:
		var mine := {}
		for q in (ch0["pts"] as PackedVector3Array):
			var kq: Vector3i = EN.key(q)
			if mine.has(kq):
				continue
			mine[kq] = true
			if seen_k.has(kq):
				must_keep[kq] = true
			seen_k[kq] = true
	times["traced"] = Time.get_ticks_msec() - t_start
	progress[1] = 0.35
	progress[2] = "making its edges curves"
	var traced := []
	for ch: Dictionary in net["chains"]:
		traced.append([(ch["pts"] as PackedVector3Array).duplicate(), bool(ch["closed"])])
	if progress.size() > 3:
		progress[3] = traced   # (shown in the view as they are, while the rest is worked out)
	var cs := []
	var closed := []
	var nch := (net["chains"] as Array).size()
	for ci in nch:
		var ch: Dictionary = net["chains"][ci]
		cs.append(EN.chain_curve(ch["pts"], bool(ch["closed"]), must_keep))
		closed.append(bool(ch["closed"]))
		progress[1] = 0.35 + 0.15 * float(ci + 1) / nch
		progress[2] = "edge %d of %d" % [ci + 1, nch]
		if progress.size() > 4:
			progress[4] = ci + 1
	times["curves"] = Time.get_ticks_msec() - t_start
	# (first its own triangles, exactly as they were, its edges laid along them: nothing moved, nothing
	# lost, as fast as it gets. The safeguard then looks it over against what it was made from - its
	# surface where the old one was, both ways; no triangles turned inside out, no slivers it didn't have,
	# none doubled (z-fighting), no new holes, its shading the way its faces face. Not good enough: an
	# even mesh of quads made between its edges instead, looked over too - the better of the two kept)
	progress[1] = 0.5
	progress[2] = "laying its faces between them"
	var r := {}
	var q := {"ok": false, "score": INF, "issues": ["its edges aren't on its points"]}
	var ex := _exact_mesh(EN, a0, net["chains"], cs)
	if not ex.is_empty():
		# (finer where it's coarse - the same surface, vertices for its edges to bend it with)
		var bx := AABB(ex["v"][0], Vector3.ZERO)
		for qx in (ex["v"] as PackedVector3Array):
			bx = bx.expand(qx)
		var cl := []
		for ch in ex["chains"]:
			cl.append(bool(ch["closed"]))
		# (quads: the model's triangles paired, then split as a subdivision's first step - every face a quad)
		var dn: Array = EN.quadify(ex["v"], ex["t"], _tie_on_chains(ex["v"], ex["t"], ex["fv"], cl), cl, maxf(bx.size.length() / 4.0, 0.003), 1200)
		ex["v"] = dn[0]
		ex["t"] = dn[1]
		ex["fv"] = _tie_on_chains(dn[0], dn[1], dn[2], cl)
		ex["dense"] = true
		progress[1] = 0.7
		progress[2] = "readying it for editing"
		r = _prepare_edges(EN, ex["v"], ex["t"], ex["fv"], ex["chains"], ex["old"], [0, 0, 0], mat, true)
		times["prepared"] = Time.get_ticks_msec() - t_start
		progress[2] = "checking it"
		q = _quality(EN, a0, r)
		times["checked"] = Time.get_ticks_msec() - t_start
	if not bool(q["ok"]) and not ex.is_empty():
		# (its triangles not touched at all: what it was, exactly - seams and all)
		progress[2] = "made again just as it was"
		var r1 := _prepare_edges(EN, ex["v"], ex["t"], ex["fv"], ex["chains"], ex["old"], [0, 0, 0], mat, true, [], true)
		var q1 := _quality(EN, a0, r1)
		if bool(q1["ok"]) or float(q1["score"]) < float(q["score"]):
			r1["first_try"] = q["issues"]
			r = r1
			q = q1
		times["raw"] = Time.get_ticks_msec() - t_start
	if ex.is_empty():
		# (its edges not on its points - a mesh of quads made between them instead)
		progress[1] = 0.75
		progress[2] = "a mesh of quads between them"
		var r2 := _remeshed(EN, src, a0, net["chains"], cs, closed, mat)
		if not r2.is_empty():
			var q2 := _quality(EN, a0, r2)
			r2["fallback"] = q["issues"]
			if bool(q2["ok"]) or float(q2["score"]) < float(q["score"]):
				r = r2
				q = q2
		times["remeshed"] = Time.get_ticks_msec() - t_start
	if r.is_empty():
		return {"error": "its surface couldn't be made of faces"}
	r["quality"] = q
	r["times"] = times
	r["dense"] = 3   # (quads, fine enough already - not made again on its first edit)
	# (its faces, for showing them one by one: each triangle's face, flooded between its edges)
	var featf := {}
	var byc := {}
	for e in r["fv"]:
		if not byc.has(int(e[1])):
			byc[int(e[1])] = []
		byc[int(e[1])].append([float(e[2]), int(e[0])])
	for ci in byc:
		var lst: Array = byc[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in lst.size() - 1:
			featf[EN._pk(int(lst[m][1]), int(lst[m + 1][1]))] = true
		if ci < closed.size() and closed[ci] and lst.size() > 2:
			featf[EN._pk(int(lst[lst.size() - 1][1]), int(lst[0][1]))] = true
	EN.corner_edges(r["v"], r["t"], featf)
	r["face_of"] = EN.face_of(r["v"], r["t"], featf)
	progress[1] = 1.0
	r["curves"] = cs
	r["closed"] = closed
	r["up"] = r.get("up", [0, 0, 0])
	return r


## (worker) Mesh `v` / `t` with its edges' vertices `fv` ([vertex, chain, t]) made finer where it's coarse:
## each triangle cut in four at its sides' middles (the surface exactly as it was - every new point on a
## straight side), again till its longest side is under `max_len` or it'd pass `max_tris`; a new point on an
## edge's side (two of its vertices next to each other along it) joins that edge. An edge then has the
## vertices to bend the surface with - two vertices are a straight line, whatever its curve. [v, t, fv].
static func _densify(v: PackedVector3Array, t: PackedInt32Array, fv: Array, closed: Array, max_len: float, max_tris: int) -> Array:
	var vv := v.duplicate()
	var tt := t.duplicate()
	var ff := fv.duplicate(true)
	for round_ in 4:
		var longest := 0.0
		for i in range(0, tt.size(), 3):
			for j in 3:
				longest = maxf(longest, vv[tt[i + j]].distance_squared_to(vv[tt[i + (j + 1) % 3]]))
		if sqrt(longest) <= max_len or tt.size() / 3 * 4 > max_tris:
			break
		# each point's edges and where along them it is: a side's middle joins an edge both its ends are on
		var on := {}   # vertex -> {chain: t}
		for e in ff:
			var vi := int(e[0])
			if not on.has(vi):
				on[vi] = {}
			on[vi][int(e[1])] = float(e[2])
		var mid := {}
		var nt := PackedInt32Array()
		var mid_of := func(a: int, b: int) -> int:
			var k := "%d|%d" % [mini(a, b), maxi(a, b)]
			if mid.has(k):
				return mid[k]
			var m := vv.size()
			vv.append((vv[a] + vv[b]) * 0.5)
			mid[k] = m
			if on.has(a) and on.has(b):
				var best_c := -1
				var best_d := INF
				var best_t := 0.0
				for ci in on[a]:
					if not (on[b] as Dictionary).has(ci):
						continue
					var ta: float = on[a][ci]
					var tb: float = on[b][ci]
					var d := absf(ta - tb)
					var tm := (ta + tb) * 0.5
					var cl: bool = int(ci) < closed.size() and bool(closed[int(ci)])
					if cl and d > 0.5:
						d = 1.0 - d   # (round the end of a closed edge)
						tm = fposmod(tm + 0.5, 1.0)
					if d < best_d:
						best_d = d
						best_c = int(ci)
						best_t = tm
				if best_c >= 0:
					ff.append([m, best_c, best_t])
			return m
		for i in range(0, tt.size(), 3):
			var a := tt[i]
			var b := tt[i + 1]
			var c := tt[i + 2]
			var ab: int = mid_of.call(a, b)
			var bc: int = mid_of.call(b, c)
			var ca: int = mid_of.call(c, a)
			nt.append_array(PackedInt32Array([a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca]))
		tt = nt
	return [vv, tt, ff]


## Whether solid `p` was converted from a model (its own triangles, made quads here) - not a solid baked from
## a recipe, which has its own grids.
func _from_model(p) -> bool:
	if not (p is Node) or not is_instance_valid(p):
		return false
	var sp: Dictionary = (p as Node).get_meta("curve_solid", {})
	return bool(sp.get("converted", false)) or sp.has("bone_name") or int(sp.get("dense", 0)) > 0 or (p as Node).has_meta("ecurve_skin") or (p as Node).has_meta("weight_src")


## (each frame) Solids made of edges that aren't quads yet - converted before - made so in the background,
## their shapes kept: ~6 ms of them a frame; an edited one made again from its bake in quads (its settle, in
## turn). Looked for once a second.
func _quads_step() -> void:
	if ed == null or ed.model == null or _converting() or not _drag.is_empty() or has_meta("settling") or has_meta("finer_due"):
		return
	var now := Time.get_ticks_msec()
	if not has_meta("quad_queue"):
		if now - int(get_meta("quad_looked", 0)) < 1000:
			return
		set_meta("quad_looked", now)
		var q := []
		for p: MeshInstance3D in ed.parts():
			var sp: Dictionary = p.get_meta("curve_solid", {})
			if str(sp.get("kind", "")) == "edges" and sp.has("mesh") and int(sp.get("dense", 0)) < 3 and _from_model(p):
				q.append(p)
		if q.is_empty():
			return
		set_meta("quad_queue", q)
	var queue: Array = get_meta("quad_queue")
	var t0 := Time.get_ticks_usec()
	var any := false
	while not queue.is_empty() and Time.get_ticks_usec() - t0 < 6000:
		var p = queue.pop_front()
		if not (p is MeshInstance3D) or not is_instance_valid(p) or not (p as Node).is_inside_tree():
			continue
		var edited: bool = ((p as Node).get_meta("curve_solid", {}) as Dictionary).has("orig")
		if _densify_solid(p):
			any = true
			if edited:
				(p as Node).set_meta("force_settle", true)
				set_meta("finer_due", [p, _state()])   # (its edits made again from its bake in quads)
				break
	if queue.is_empty():
		remove_meta("quad_queue")
	if any:
		refresh_solids()


## A baked solid whose edge is picked to be edited, too coarse for its edges to bend it: made finer now
## (its shape as it was, made again from the finer bake - one undo step "Finer mesh"), so the drag that
## follows has vertices to bend it with.
func _finer_for_edit(p) -> void:
	if not (p is MeshInstance3D) or not is_instance_valid(p):
		return
	var sp0: Dictionary = (p as Node).get_meta("curve_solid", {})
	if str(sp0.get("kind", "")) != "edges" or int(sp0.get("dense", 0)) >= 3 or not _from_model(p):
		return
	var before := _state()
	if not _densify_solid(p):
		return
	if ((p as Node).get_meta("curve_solid") as Dictionary).has("orig"):
		(p as Node).set_meta("force_settle", true)   # (its edits made again from the finer bake)
		set_meta("finer_due", [p, before])   # (once its solver's made - _process tries each frame)
	else:
		refresh_solids()
		_record("Finer mesh", before)


## (worker) Edges' vertices `fv` given every mesh point lying on their lines that isn't counted as theirs:
## from each edge's points, along the mesh's sides to points on the line through them (within a thousandth
## of its length) - each put in at its place along the edge. Points on an edge not counted as its are left
## behind when it bends: a saw-tooth along it. The fv, with them.
static func _tie_on_chains(v: PackedVector3Array, t: PackedInt32Array, fv: Array, closed: Array) -> Array:
	var nb := {}
	for i in range(0, t.size(), 3):
		for j in 3:
			var a := t[i + j]
			var b := t[i + (j + 1) % 3]
			if not nb.has(a):
				nb[a] = {}
			if not nb.has(b):
				nb[b] = {}
			nb[a][b] = true
			nb[b][a] = true
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	var out := fv.duplicate(true)
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		if lst.size() < 2:
			continue
		var cl: bool = int(ci) < closed.size() and bool(closed[int(ci)])
		var segs := []   # [a pos, b pos, ta, tb]
		var length := 0.0
		for m in (lst.size() if cl else lst.size() - 1):
			var x: Array = lst[m]
			var y: Array = lst[(m + 1) % lst.size()]
			var tb: float = float(y[0]) if m < lst.size() - 1 else float(y[0]) + 1.0
			segs.append([v[int(x[1])], v[int(y[1])], float(x[0]), tb])
			length += v[int(x[1])].distance_to(v[int(y[1])])
		var tol := maxf(length * 1e-3, 1e-6)
		var mine := {}
		var queue := []
		for x in lst:
			mine[int(x[1])] = true
			queue.append(int(x[1]))
		while not queue.is_empty():
			var q: int = queue.pop_back()
			for n in nb.get(q, {}):
				if mine.has(n):
					continue
				var p := v[n]
				for sg in segs:
					var a3: Vector3 = sg[0]
					var b3: Vector3 = sg[1]
					var cp := Geometry3D.get_closest_point_to_segment(p, a3, b3)
					if cp.distance_to(p) < tol:
						var l := a3.distance_to(b3)
						var u := a3.distance_to(cp) / l if l > 0.0 else 0.0
						var tt := lerpf(float(sg[2]), float(sg[3]), u)
						out.append([int(n), int(ci), fposmod(tt, 1.0) if cl else tt])
						mine[n] = true
						queue.append(n)
						break
	return out


## A baked solid made finer where it's too coarse for its edges to bend it (_densify) - its bake under its
## edits (orig) if it has one, else its mesh; once. True - it was.
func _densify_solid(p: MeshInstance3D) -> bool:
	var spec: Dictionary = p.get_meta("curve_solid", {})
	if str(spec.get("kind", "")) != "edges" or not spec.has("mesh") or int(spec.get("dense", 0)) >= 3:
		return false
	var src: Dictionary = spec["orig"] if spec.has("orig") else spec
	var flat: Array = src["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, flat.size(), 3):
		v.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	var box := AABB(v[0], Vector3.ZERO) if not v.is_empty() else AABB()
	for q in v:
		box = box.expand(q)
	var closed := []
	for ch in spec.get("chains", []):
		closed.append(bool(ch.get("closed", false)))
	var t0 := PackedInt32Array(src["mesh"]["t"])
	var fv0 := _tie_on_chains(v, t0, src.get("fv", []), closed)   # (the points already on its edges counted as theirs)
	# (made of quads: paired and split - one round when it's fine already, more when it's coarse)
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var fine := int(spec.get("dense", 0)) >= 1
	var r: Array = EN.quadify(v, t0, fv0, closed, INF if fine else maxf(box.size.length() / 4.0, 0.003), 1200)
	r[2] = _tie_on_chains(r[0], r[1], r[2], closed)
	var changed: bool = (r[1] as PackedInt32Array).size() != t0.size() or (r[2] as Array).size() != (src.get("fv", []) as Array).size()
	spec["dense"] = 3
	if not changed:
		p.set_meta("curve_solid", spec)
		return false
	var nflat := []
	for q in (r[0] as PackedVector3Array):
		nflat.append_array([q.x, q.y, q.z])
	src["mesh"] = {"v": nflat, "t": Array(r[1])}
	src["fv"] = r[2]
	if spec.has("orig"):
		_edge_bases().erase(-absi(int(spec.get("net", 0))) - 1)   # (the bake's solver: made again for the finer mesh)
	else:
		_edge_bases().erase(int(spec.get("net", 0)))
		p.remove_meta("curve_solid_key")
	p.remove_meta("settled_key")
	p.remove_meta("hit_tm")
	p.set_meta("curve_solid", spec)
	return true


## (worker) Seams for a smooth surface (`a0`: its arrays) with no edges of its own: where its triangles on
## one side of the plane through its middle across its longest way meet those on the other - closed loops
## along its own mesh's edges (nothing moved). [{pts, closed}].
static func _seam_loops(EN: GDScript, a0: Array) -> Array:
	var sv: PackedVector3Array = a0[Mesh.ARRAY_VERTEX]
	var sx: PackedInt32Array = a0[Mesh.ARRAY_INDEX] if a0[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
	if sx.size() < 3:
		return []
	var box := AABB(sv[0], Vector3.ZERO)
	for q in sv:
		box = box.expand(q)
	# (across its longest way first, then the others)
	var order := [box.get_longest_axis_index()]
	for k in 3:
		if not k in order:
			order.append(k)
	for ax in order:
		var loops := _seam_across(EN, sv, sx, ax, box.get_center()[ax])
		if not loops.is_empty():
			return loops
	# (too small to cut across: one of its triangles' outline)
	return [{"pts": PackedVector3Array([sv[sx[0]], sv[sx[1]], sv[sx[2]]]), "closed": true}]


static func _seam_across(EN: GDScript, sv: PackedVector3Array, sx: PackedInt32Array, ax: int, mid: float) -> Array:
	var side := {}   # edge (welded keys) -> [in, out] counts
	var pos := {}
	for ti in range(0, sx.size(), 3):
		var c := (sv[sx[ti]] + sv[sx[ti + 1]] + sv[sx[ti + 2]]) / 3.0
		var up := c[ax] > mid
		for j in 3:
			var a := sv[sx[ti + j]]
			var b := sv[sx[ti + (j + 1) % 3]]
			var ka: Vector3i = EN.key(a)
			var kb: Vector3i = EN.key(b)
			if ka == kb:
				continue
			pos[ka] = a
			pos[kb] = b
			var ek := [ka, kb] if ka < kb else [kb, ka]
			if not side.has(ek):
				side[ek] = [0, 0]
			side[ek][0 if up else 1] += 1
	var adj := {}
	for ek in side:
		if int(side[ek][0]) == 1 and int(side[ek][1]) == 1:
			for k in 2:
				if not adj.has(ek[k]):
					adj[ek[k]] = []
				adj[ek[k]].append(ek[1 - k])
	var loops := []
	var used := {}
	for start in adj:
		if used.has(start) or (adj[start] as Array).size() != 2:
			continue
		var pts := PackedVector3Array()
		var cur = start
		var prev = null
		while true:
			used[cur] = true
			pts.append(pos[cur])
			var nxt = null
			for n in adj[cur]:
				if n != prev and not used.has(n):
					nxt = n
					break
			if nxt == null:
				break
			prev = cur
			cur = nxt
		if pts.size() >= 3 and (adj[cur] as Array).has(start):
			loops.append({"pts": pts, "closed": true})
	return loops


## (worker) Solid `a0` made an even mesh of quads between its traced edges (`net_chains`, curves `cs`),
## about as fine as it was made, readied for editing (_prepare_edges) - {} when it can't be.
static func _remeshed(EN: GDScript, src: RefCounted, a0: Array, net_chains: Array, cs: Array, closed: Array, mat: Material) -> Dictionary:
	var area := 0.0
	var sv: PackedVector3Array = a0[Mesh.ARRAY_VERTEX]
	var sx: PackedInt32Array = a0[Mesh.ARRAY_INDEX]
	for ti in range(0, sx.size(), 3):
		area += (sv[sx[ti + 1]] - sv[sx[ti]]).cross(sv[sx[ti + 2]] - sv[sx[ti]]).length() * 0.5
	# (as fine as it was made, about - a small piece isn't made of hundreds of triangles, a big one keeps its detail)
	var target := clampf(sx.size() / 3.0, 24.0, 6000.0)
	var L := clampf(sqrt(area / (target * 0.5)), 0.0005, 1.0)
	var rm: Dictionary = EN.quad_mesh(src, net_chains, L * 0.6)
	var to_quads := false
	if rm.is_empty() or EN._open_edges(rm["t"]) > 0:
		rm = EN.remesh(src, net_chains, L)
		to_quads = true
	if rm.is_empty():
		return {}
	var vv: PackedVector3Array = rm["v"]
	var fv := []
	var chains := []
	var old := {}
	for ci in cs.size():
		chains.append({"id": ci, "closed": closed[ci]})
		old[ci] = cs[ci]
		var vis: Array = (rm["chains"][ci] as Array).filter(func(x): return x >= 0)
		var pts := PackedVector3Array()
		for vi in vis:
			pts.append(vv[vi])
		var ts: PackedFloat32Array = EN.params(pts, cs[ci])
		for j in vis.size():
			fv.append([vis[j], ci, ts[j]])
	var tt: PackedInt32Array = rm["t"]
	if to_quads:
		# (the topology rules: each face between its edges laid out as grids or along its flow - the full layout,
		# on this worker; editor.md "mesh-curves-topology")
		var gq: Dictionary = EN.grid_any(vv, tt, fv, chains, L * 0.55)
		if not gq.is_empty() and EN._open_edges(gq["t"]) <= EN._open_edges(tt):
			vv = gq["v"]
			tt = gq["t"]
			fv = gq["fv"]
	return _prepare_edges(EN, vv, tt, fv, chains, old, rm.get("axis", [0, 0, 0]), mat, false, a0)


## (safe on a worker) How good converted solid `r` ({v, t, shaded}) is against the surface it was made from
## (`a0`: its arrays): {ok, score (0 perfect), issues: [words], dev, mean_dev, back_dev, flipped, slivers,
## doubled, holes, shading}. Distances against the size of the piece (its box's diagonal): the new surface
## at most 2% of it off the old (0.4% on average) and the old one at most 3% from the new (nothing lost);
## under 0.5% of its area facing the wrong way; under 1% slivers (a corner under 1 degree); under 0.5% of
## its corners shaded more than 60 degrees off their face; no triangles doubled; no new holes.
static func _quality(EN: GDScript, a0: Array, r: Dictionary) -> Dictionary:
	var sv: PackedVector3Array = a0[Mesh.ARRAY_VERTEX]
	var sx: PackedInt32Array = a0[Mesh.ARRAY_INDEX] if a0[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
	var rv: PackedVector3Array = r["v"]
	var rt: PackedInt32Array = r["t"]
	var out := {"ok": true, "score": 0.0, "issues": []}
	if rt.size() < 3 or sx.size() < 3:
		out["ok"] = rt.size() >= 3
		out["score"] = 0.0 if out["ok"] else 1e9
		return out
	var box := AABB(sv[0], Vector3.ZERO)
	for q in sv:
		box = box.expand(q)
	var diag := maxf(box.size.length(), 1e-4)
	# (the old surface's own triangles - corners by place, the way round they run: one of them in the new
	# surface as it was needs no measuring - only what's new is looked at closely)
	var kv := PackedInt32Array()   # (each old point: its welded number)
	kv.resize(sv.size())
	var wk := {}
	for i in sv.size():
		var k: Vector3i = EN.key(sv[i])
		if not wk.has(k):
			wk[k] = wk.size()
		kv[i] = wk[k]
	var own := {}
	for ti in range(0, sx.size(), 3):
		own[_tri_key(kv[sx[ti]], kv[sx[ti + 1]], kv[sx[ti + 2]])] = true
	var rk := PackedInt32Array()   # (each new point: the old point it is, -1: a new one)
	rk.resize(rv.size())
	var new_pts := 0
	for i in rv.size():
		rk[i] = int(wk.get(EN.key(rv[i]), -1))
		if rk[i] < 0:
			new_pts += 1
	var src_grid := {}   # (made only when something new is to be measured)
	var res_grid := {}
	# the new surface where the old one is (its points and its triangles' middles)
	var dmax := 0.0
	var dsum := 0.0
	var dn := 0
	var flipped_area := 0.0
	var area := 0.0
	var slivers := 0
	var looked := 0
	var tstep := maxi(1, rt.size() / 3 / 2500) * 3   # (at most ~2,500 triangles looked at closely: a big solid sampled)
	for ti in range(0, rt.size(), 3):
		var A := rv[rt[ti]]
		var B := rv[rt[ti + 1]]
		var C := rv[rt[ti + 2]]
		var cr := (B - A).cross(C - A)
		var ar := cr.length() * 0.5
		area += ar
		if _min_angle(A, B, C) < 1.0:
			slivers += 1
		if rk[rt[ti]] >= 0 and rk[rt[ti + 1]] >= 0 and rk[rt[ti + 2]] >= 0 and own.has(_tri_key(rk[rt[ti]], rk[rt[ti + 1]], rk[rt[ti + 2]])):
			dn += 1
			continue   # (one of the old surface's own, as it was: on it, facing its way)
		if ti % tstep != 0:
			continue
		looked += 1
		if src_grid.is_empty():
			src_grid = _tri_grid(sv, sx, diag)
		var near := _nearest_on(src_grid, sv, sx, (A + B + C) / 3.0, cr)
		var d: float = near[0]
		dmax = maxf(dmax, d)
		dsum += d
		dn += 1
		if ar > 1e-12 and int(near[1]) >= 0:
			var si: int = near[1]
			var sn := (sv[sx[si + 1]] - sv[sx[si]]).cross(sv[sx[si + 2]] - sv[sx[si]])
			# (facing away from the nearest of the old surface - and nothing of it facing its way as near: a
			# thin shell's two walls face both ways)
			if sn.length_squared() > 1e-20 and cr.normalized().dot(sn.normalized()) < -0.5 and float(near[2]) > d + diag * 0.002:
				flipped_area += ar * tstep / 3.0
	if new_pts > 0:
		if src_grid.is_empty():
			src_grid = _tri_grid(sv, sx, diag)
		for i in range(0, rv.size(), maxi(1, rv.size() / 2500)):
			if rk[i] < 0:
				dmax = maxf(dmax, float(_nearest_on(src_grid, sv, sx, rv[i])[0]))
	# (slivers it didn't have: a model's own thin triangles - fans, lofts' ends - aren't the conversion's)
	var src_slivers := 0
	for ti in range(0, sx.size(), 3):
		if _min_angle(sv[sx[ti]], sv[sx[ti + 1]], sv[sx[ti + 2]]) < 1.0:
			src_slivers += 1
	# the old surface where the new one is (nothing of it lost)
	var bmax := 0.0
	var kept := {}   # (old points still points of the new surface: on it)
	for i in rv.size():
		if rk[i] >= 0:
			kept[rk[i]] = true
	if kept.size() < wk.size():
		res_grid = _tri_grid(rv, rt, diag)
		var step := maxi(1, sv.size() / 2500)
		for i in range(0, sv.size(), step):
			if not kept.has(kv[i]):
				bmax = maxf(bmax, float(_nearest_on(res_grid, rv, rt, sv[i])[0]))
	# doubled triangles (z-fighting) and holes
	var seen := {}
	var doubled := 0
	for ti in range(0, rt.size(), 3):
		var ks := [EN.key(rv[rt[ti]]), EN.key(rv[rt[ti + 1]]), EN.key(rv[rt[ti + 2]])]
		ks.sort()
		var h := hash(ks)
		if seen.has(h):
			doubled += 1
		seen[h] = true
	# (holes by the open border's length, not its count: a finer mesh's border has more, shorter sides)
	var ol_new := _open_length(EN, rv, rt)
	var ol_old := _open_length(EN, sv, sx)
	var holes := 0 if ol_new <= ol_old * 1.001 + diag * 1e-4 else maxi(1, _open_count(EN, rv, rt) - _open_count(EN, sv, sx))
	# shading: each corner's normal against the face it's on
	var shading := 0
	var sh: Array = r.get("shaded", [])
	if not sh.is_empty() and sh[Mesh.ARRAY_NORMAL] != null:
		var pv: PackedVector3Array = sh[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = sh[Mesh.ARRAY_NORMAL]
		var px: PackedInt32Array = sh[Mesh.ARRAY_INDEX] if sh[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(pv.size()))
		for ti in range(0, px.size(), 3):
			var fn := (pv[px[ti + 1]] - pv[px[ti]]).cross(pv[px[ti + 2]] - pv[px[ti]])
			if fn.length_squared() < 1e-20:
				continue
			fn = fn.normalized()
			for j in 3:
				# (Godot's triangles wind clockwise: the face's normal is the other way round)
				if absf(pn[px[ti + j]].dot(fn)) < 0.5:
					shading += 1
	var nt := rt.size() / 3
	out["dev"] = dmax / diag
	out["mean_dev"] = dsum / maxf(dn, 1) / diag
	out["looked"] = looked
	out["back_dev"] = bmax / diag
	out["flipped"] = flipped_area / maxf(area, 1e-12)
	out["slivers"] = float(slivers) / nt
	out["src_slivers"] = float(src_slivers) / maxf(sx.size() / 3, 1)
	out["doubled"] = doubled
	out["holes"] = holes
	out["shading"] = float(shading) / maxf(nt * 3, 1)
	var issues: Array = out["issues"]
	if float(out["dev"]) > 0.02 or float(out["mean_dev"]) > 0.004:
		issues.append("off its old surface by %.1f%%" % (float(out["dev"]) * 100.0))
	if float(out["back_dev"]) > 0.03:
		issues.append("part of it lost (%.1f%%)" % (float(out["back_dev"]) * 100.0))
	if float(out["flipped"]) > 0.005:
		issues.append("%.1f%% of it inside out" % (float(out["flipped"]) * 100.0))
	if slivers - out["src_slivers"] * nt > maxf(4.0, nt * 0.03):
		issues.append("%d slivers" % slivers)
	if doubled > 0:
		issues.append("%d triangles doubled" % doubled)
	if holes > 0:
		issues.append("%d new open edges" % holes)
	if float(out["shading"]) > 0.005:
		issues.append("shading off on %.1f%%" % (float(out["shading"]) * 100.0))
	out["ok"] = issues.is_empty()
	out["score"] = float(out["dev"]) * 10.0 + float(out["back_dev"]) * 10.0 + float(out["flipped"]) * 50.0 + maxf(0.0, float(out["slivers"]) - float(out["src_slivers"])) * 5.0 + doubled * 0.1 + holes * 0.05 + float(out["shading"]) * 20.0
	return out


## A triangle by its corners' numbers, the same whichever corner it's started from (not when turned over).
static func _tri_key(a: int, b: int, c: int) -> Vector3i:
	if a <= b and a <= c:
		return Vector3i(a, b, c)
	if b <= a and b <= c:
		return Vector3i(b, c, a)
	return Vector3i(c, a, b)


## (worker) A grid of a mesh's triangles by place: {cell size, cell -> [triangle starts]}.
static func _tri_grid(v: PackedVector3Array, t: PackedInt32Array, diag: float) -> Dictionary:
	var cs := diag / 24.0
	var cells := {}
	for ti in range(0, t.size(), 3):
		var a := v[t[ti]]
		var b := v[t[ti + 1]]
		var c := v[t[ti + 2]]
		var b0 := AABB(a, Vector3.ZERO).expand(b).expand(c)
		var lo := Vector3i((b0.position / cs).floor())
		var hi := Vector3i((b0.end / cs).floor())
		var span := hi - lo
		if span.x <= 2 and span.y <= 2 and span.z <= 2:
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var k := Vector3i(x, y, z)
						if not cells.has(k):
							cells[k] = PackedInt32Array()
						cells[k].append(ti)
			continue
		# (a big triangle: the cells it passes through, found by points across it half a cell apart -
		# not its whole box: a long diagonal panel's box is mostly empty)
		var n := ceili(maxf((b - a).length(), maxf((c - a).length(), (c - b).length())) / cs * 2.0)
		var put := {}
		for i in n + 1:
			for j in n + 1 - i:
				var k := Vector3i(((a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n)) / cs).floor())
				if put.has(k):
					continue
				put[k] = true
				if not cells.has(k):
					cells[k] = PackedInt32Array()
				cells[k].append(ti)
	return {"cs": cs, "cells": cells}


## (worker) The nearest point of the mesh in grid `g` to `p`: [distance, its triangle's start (-1: none
## near)], a ring of cells further out each time until one's found close enough.
static func _nearest_on(g: Dictionary, v: PackedVector3Array, t: PackedInt32Array, p: Vector3, facing := Vector3.ZERO) -> Array:
	var cs: float = g["cs"]
	var cells: Dictionary = g["cells"]
	var c := Vector3i((p / cs).floor())
	var best := INF
	var bt := -1
	var agree := INF   # (the nearest facing the way `facing` does)
	for ring in 4:
		for x in range(-ring, ring + 1):
			for y in range(-ring, ring + 1):
				for z in range(-ring, ring + 1):
					if maxi(absi(x), maxi(absi(y), absi(z))) != ring:
						continue
					var k := c + Vector3i(x, y, z)
					if not cells.has(k):
						continue
					for ti in (cells[k] as PackedInt32Array):
						var d := p.distance_to(_closest_on_tri(p, v[t[ti]], v[t[ti + 1]], v[t[ti + 2]]))
						if d < best:
							best = d
							bt = ti
						if facing != Vector3.ZERO and d < agree and (v[t[ti + 1]] - v[t[ti]]).cross(v[t[ti + 2]] - v[t[ti]]).dot(facing) > 0.0:
							agree = d
		if bt >= 0 and best <= ring * cs:
			break
	if bt < 0:
		best = cs * 4.0
	return [best, bt, agree]


## The point of triangle abc nearest to p.
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / maxf(va + vb + vc, 1e-30)
	return a + ab * (vb * den) + ac * (vc * den)


## A triangle's smallest corner, in degrees.
static func _min_angle(a: Vector3, b: Vector3, c: Vector3) -> float:
	var m := 180.0
	for e in [[a, b, c], [b, c, a], [c, a, b]]:
		var u: Vector3 = e[1] - e[0]
		var w: Vector3 = e[2] - e[0]
		if u.length_squared() < 1e-24 or w.length_squared() < 1e-24:
			return 0.0
		m = minf(m, rad_to_deg(u.angle_to(w)))
	return m


## How many edges of a mesh have one triangle only (its points welded by place).
static func _open_count(EN: GDScript, v: PackedVector3Array, t: PackedInt32Array) -> int:
	var n := {}
	for ti in range(0, t.size(), 3):
		for j in 3:
			var a: Vector3i = EN.key(v[t[ti + j]])
			var b: Vector3i = EN.key(v[t[ti + (j + 1) % 3]])
			if a == b:
				continue
			var h := hash([a, b] if a < b else [b, a])
			n[h] = int(n.get(h, 0)) + 1
	var o := 0
	for h in n:
		if int(n[h]) == 1:
			o += 1
	return o


## How long a mesh's open border is (its sides with one triangle, points welded by place).
static func _open_length(EN: GDScript, v: PackedVector3Array, t: PackedInt32Array) -> float:
	var n := {}
	var len_of := {}
	for ti in range(0, t.size(), 3):
		for j in 3:
			var pa := v[t[ti + j]]
			var pb := v[t[ti + (j + 1) % 3]]
			var a: Vector3i = EN.key(pa)
			var b: Vector3i = EN.key(pb)
			if a == b:
				continue
			var h := hash([a, b] if a < b else [b, a])
			n[h] = int(n.get(h, 0)) + 1
			len_of[h] = pa.distance_to(pb)
	var total := 0.0
	for h in n:
		if int(n[h]) == 1:
			total += float(len_of[h])
	return total


## (worker) An exact copy of the surface in `a0` as a baked solid's mesh: its own points (welded by place)
## and triangles (none with no area, none doubled), the traced edges `net_chains` (curves `cs`) laid along
## it. {v, t, fv, chains, old}, or {} when an edge's points aren't all the surface's points.
static func _exact_mesh(EN: GDScript, a0: Array, net_chains: Array, cs: Array) -> Dictionary:
	var sv: PackedVector3Array = a0[Mesh.ARRAY_VERTEX]
	var sx: PackedInt32Array = a0[Mesh.ARRAY_INDEX] if a0[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
	var idx := {}
	var v := PackedVector3Array()
	var wi := PackedInt32Array()
	wi.resize(sv.size())
	for i in sv.size():
		var k: Vector3i = EN.key(sv[i])
		if not idx.has(k):
			idx[k] = v.size()
			v.append(sv[i])
		wi[i] = idx[k]
	var t := PackedInt32Array()
	var seen := {}
	for ti in range(0, sx.size(), 3):
		var a := wi[sx[ti]]
		var b := wi[sx[ti + 1]]
		var c := wi[sx[ti + 2]]
		if a == b or b == c or a == c:
			continue
		var ks := [a, b, c]
		ks.sort()
		var h := hash(ks)
		if seen.has(h):
			continue
		seen[h] = true
		t.append_array(PackedInt32Array([a, b, c]))
	var fv := []
	var chains := []
	var old := {}
	for ci in cs.size():
		var pts: PackedVector3Array = net_chains[ci]["pts"]
		var vis := []
		for q in pts:
			var k: Vector3i = EN.key(q)
			if not idx.has(k):
				return {}
			vis.append(idx[k])
		chains.append({"id": ci, "closed": bool(net_chains[ci]["closed"])})
		old[ci] = cs[ci]
		var ts: PackedFloat32Array = EN.params(pts, cs[ci])
		var once := {}
		for j in vis.size():
			if once.has(vis[j]):
				continue
			once[vis[j]] = true
			fv.append([vis[j], ci, ts[j]])
	return {"v": v, "t": t, "fv": fv, "chains": chains, "old": old}


## (safe on a worker) A baked solid's mesh readied as its first drawing would: its edges' points tied in,
## its seams closed, its flat faces quads, lone triangles paired, turned outwards - then its weights,
## solver and shading for editing. {v, t, fv, cache, mesh}.
static func _prepare_edges(EN: GDScript, v: PackedVector3Array, t_in: PackedInt32Array, fv_in: Array, chains: Array, old: Dictionary, up: Array, mat: Material, exact := false, ref := [], raw := false) -> Dictionary:
	# (`raw`: its triangles kept just as they are - no seams closed, none paired - the safeguard's last resort)
	var t := t_in
	var fv := fv_in
	# (an exact copy's edges run through its own points, every one: nothing to tie in - 200 ms saved on a big piece)
	var tied = null if raw or exact else EN.tie_edges(v, t, fv, chains, old)
	if tied != null:
		t = tied["t"]
		fv = tied["fv"]
	var cs0: Dictionary = {} if raw else EN.close_seams(v, t, fv)
	if not cs0.is_empty():
		t = cs0["t"]
		fv = cs0["fv"]
	var area := 0.0
	for i in range(0, t.size(), 3):
		area += (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]]).length() * 0.5
	var L := clampf(sqrt(area / 380.0), 0.003, 1.0) * 0.6
	var upv := Vector3(up[0], up[1], up[2])
	var feat0: Dictionary = {} if exact else EN.feature_edges(v, t, fv, chains, old)
	var rf: Dictionary = {} if exact or EN._open_edges(t) > 0 else EN.quad_caps(v, t, fv, feat0, L, upv.normalized() if upv != Vector3.ZERO else Vector3.ZERO, chains)
	if not rf.is_empty():
		var csq: Dictionary = EN.close_seams(rf["v"], rf["t"], rf["fv"])
		if EN._open_edges(csq["t"] if not csq.is_empty() else rf["t"]) > 0:
			rf = {}
	if not rf.is_empty():
		v = rf["v"]
		t = rf["t"]
		fv = rf["fv"]
	var cs: Dictionary = {} if raw or exact else EN.close_seams(v, t, fv)   # (after new caps only)
	if not cs.is_empty():
		t = cs["t"]
		fv = cs["fv"]
	# (lone triangles side by side made quads: the solid's edges by their curves' order, real corners)
	var featp := {}
	var by_c := {}
	for e in fv:
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in lst.size() - 1:
			featp[EN._pk(int(lst[m][1]), int(lst[m + 1][1]))] = true
	EN.corner_edges(v, t, featp)
	if not raw:
		t = EN.pair_quads(v, t, featp)
	if not exact:
		t = EN.orient(v, t)   # (an exact copy keeps the way its triangles faced)
		if not ref.is_empty() and _faces_away(v, t, ref):
			for i in range(0, t.size(), 3):
				var k := t[i + 1]
				t[i + 1] = t[i + 2]
				t[i + 2] = k   # (turned outwards the wrong way for an open piece: as the old one faced)
	t = _no_doubles(v, t)
	var all_edge := {}
	for e in fv:
		all_edge[int(e[0])] = true
	var feat: Dictionary = EN.feature_edges(v, t, fv, chains, old)
	var bw: Dictionary = EN.blend_weights(v, t, all_edge, feat, upv)
	var topo: Dictionary = EN.corner_topo(v.size(), t)
	var cache := {"n": v.size() * 3, "v": v, "t": t, "nb": EN.neighbours(t, v.size()), "last": PackedVector3Array(), "edge": all_edge,
		"bw": bw, "cg": EN.cg_setup(v, t, bw), "pv": v, "t_draw": t, "topo": topo, "topo_n": t.size()}
	var shaded: Array = EN.shaded_fast(v, t, topo, null, 40.0, true)
	return {"v": v, "t": t, "fv": fv, "cache": cache, "shaded": shaded, "mesh": with_lods(shaded, mat), "up": up}


## (worker) Triangles `t` without the ones that are another's same corners (either way round - back to
## back): two triangles in one place fight over which is drawn (z-fighting).
static func _no_doubles(v: PackedVector3Array, t: PackedInt32Array) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	for i in range(0, t.size(), 3):
		var ks := [t[i], t[i + 1], t[i + 2]]
		ks.sort()
		var h := hash(ks)
		if seen.has(h):
			continue
		seen[h] = true
		out.append_array(PackedInt32Array([t[i], t[i + 1], t[i + 2]]))
	return out


## (worker) Whether mesh v/t mostly faces the other way from surface `ref` (arrays) where they overlap -
## by area, a few hundred triangles looked at.
static func _faces_away(v: PackedVector3Array, t: PackedInt32Array, ref: Array) -> bool:
	var sv: PackedVector3Array = ref[Mesh.ARRAY_VERTEX]
	var sx: PackedInt32Array = ref[Mesh.ARRAY_INDEX] if ref[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
	if sx.size() < 3 or t.size() < 3:
		return false
	var box := AABB(sv[0], Vector3.ZERO)
	for q in sv:
		box = box.expand(q)
	var g := _tri_grid(sv, sx, maxf(box.size.length(), 1e-4))
	var same := 0.0
	var away := 0.0
	var step := maxi(1, t.size() / 3 / 300) * 3
	for i in range(0, t.size(), step):
		var cr := (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]])
		var near := _nearest_on(g, sv, sx, (v[t[i]] + v[t[i + 1]] + v[t[i + 2]]) / 3.0)
		if int(near[1]) < 0:
			continue
		var si: int = near[1]
		var sn := (sv[sx[si + 1]] - sv[sx[si]]).cross(sv[sx[si + 2]] - sv[sx[si]])
		var d := cr.dot(sn)
		if d >= 0.0:
			same += cr.length()
		else:
			away += cr.length()
	return away > same


## A mesh from `arrays` (one surface, material `mat`) with levels of detail (each a coarser copy the renderer switches to as it gets small on
## screen - ImporterMesh's, as the game's imported models have). Safe on a worker.
static func with_lods(arrays: Array, mat: Material) -> ArrayMesh:
	# (its corners that are the same point with the same shading made one - a third the points to draw,
	# to store, to skin)
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.index()
	arrays = st.commit_to_arrays()
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## A finished conversion put in place: the part made an ECurve solid - its curves (edges) added, its
## mesh, drawn and ready to edit. A skinned part keeps its skin and its old mesh as where its weights come
## from (put back on its new mesh when the object's saved).
func _convert_apply(p: MeshInstance3D, r: Dictionary) -> void:
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	var from = p.get_meta("convert_from") if p.has_meta("convert_from") else null
	p.remove_meta("convert_from")
	if p.has_meta("curve_solid") or (from != null and from != p.mesh):
		convert_parts([p])   # (edited while it was worked out: made again from what it is now)
		return
	if r.has("error"):
		p.set_meta("ecurve_failed", str(r["error"]))
		ed._say("%s stays a mesh: %s." % [p.name, r["error"]])
		ed._fill_parts()
		_refresh_panel()
		return
	var ids := []
	var chains := []
	var c0 := {}
	var cs: Array = r["curves"]
	for ci in cs.size():
		var c: Dictionary = _fresh((cs[ci] as Dictionary).duplicate(true))
		c["name"] = "%s edge %d" % [p.name, ci + 1]
		if p != null and p.get_parent() != ed.model:
			pass
		curves.append(c)
		ids.append(int(c["id"]))
		chains.append({"id": int(c["id"]), "closed": bool(r["closed"][ci])})
		c0[str(int(c["id"]))] = to_json([c])[0]
	var vv: PackedVector3Array = r["v"]
	var flat := []
	flat.resize(vv.size() * 3)
	for i in vv.size():
		flat[i * 3] = vv[i].x
		flat[i * 3 + 1] = vv[i].y
		flat[i * 3 + 2] = vv[i].z
	var net_id := int(Time.get_ticks_usec() % 2000000000)
	var spec := {"kind": "edges", "ids": ids, "net": net_id, "chains": chains, "c0": c0, "mesh": {"v": flat, "t": Array(r["t"])}, "fv": r["fv"],
		"tied": true, "qcaps": true, "sealed": true, "paired": true, "oriented": true, "dense": int(r.get("dense", 0)), "converted": true}
	if r.get("up", [0, 0, 0]) != [0, 0, 0]:
		spec["up"] = r["up"]
	if str(p.get_meta("ecurve_bone", "")) != "":
		spec["bone_name"] = str(p.get_meta("ecurve_bone"))
	var m: ArrayMesh = r["mesh"]
	var skin: Skin = p.skin if p.skin != null else (p.get_meta("src_skin") if p.has_meta("src_skin") else null)
	if skin != null:
		# (a skinned part: its old mesh where its weights come from, its skin kept for saving - bone
		# associations; drawn at rest while it's edited)
		p.set_meta("weight_src", p.mesh)
		p.set_meta("ecurve_skin", skin)
		p.skin = null
		spec["bone"] = "auto"
	_edge_bases()[net_id] = r["cache"]
	p.mesh = m
	p.set_meta("curve_solid", spec)
	p.set_meta("curve_solid_key", _solid_key(spec))
	var ja: Array = get_meta("join_after", [])
	ja.append(p)
	set_meta("join_after", ja)   # (once all are made: those meeting along an edge joined)
	layer.queue_redraw()
	ed.view.request()
	# (the lists made again once all are done - not after each of hundreds of pieces)
	if (get_meta("convert_queue", []) as Array).is_empty():
		ed._fill_parts()
		_refresh_panel()
	else:
		set_meta("panel_due", true)

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
	var gone := _solid_curve_ids()
	gone.merge(_locked_ids())   # (a solid that can't be picked: its edges neither)
	for i in curves.size():
		if curves[i].get("hidden", false) or gone.has(int(curves[i].get("id", -1))):
			continue
		var x := cx(curves[i], own)
		if not _near_on_screen(curves[i], mx * x, at, best):
			continue   # (nowhere near the mouse: not sampled, nor its points put on screen)
		var s := sample(curves[i])
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


## Whether curve `c` (placed by `wx`, its space -> the view's world) may come within `px` of `at` on
## screen: the box round its points (and handles; a circle or an arc its radius round them) - its eight
## corners on screen. True when unsure (a corner behind the camera).
func _near_on_screen(c: Dictionary, wx: Transform3D, at: Vector2, px: float) -> bool:
	var k: PackedVector3Array = c["ctrl"]
	if k.is_empty():
		return false
	var b := AABB(k[0], Vector3.ZERO)
	for q in k:
		b = b.expand(q)
	var kind := str(c.get("kind", ""))
	if kind in ["circle", "arc"]:
		b = b.grow(b.size.length() + (k[0].distance_to(k[1]) if k.size() > 1 else 0.0))
	elif kind == "path":
		for key in ["tin", "tout"]:
			var tg: PackedVector3Array = c.get(key, PackedVector3Array())
			for j in mini(tg.size(), k.size()):
				b = b.expand(k[j] + tg[j])
		b = b.grow(b.size.length() * 0.15)
	else:
		b = b.grow(b.size.length() * 0.15)   # (a spline's swing past its points)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for n in 8:
		var w := wx * b.get_endpoint(n)
		if ed.view.behind(w):
			return true
		var sp: Vector2 = ed.view.project(w)
		lo = lo.min(sp)
		hi = hi.max(sp)
	return at.x >= lo.x - px and at.x <= hi.x + px and at.y >= lo.y - px and at.y <= hi.y + px


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
	for key_ in ["tin", "tout"]:
		if e.has(key_):
			var tv: PackedVector3Array = e[key_]
			tv.resize(k.size() - 1)
			tv.insert(at_j + 1, Vector3.ZERO)
			e[key_] = tv
	curves[i] = e
	if not i in sel:
		sel = [i]
	_changed("Insert edge vertex", before)
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
		for key_ in ["sharp", "radii", "tin", "tout"]:
			if e.has(key_):
				var a = e[key_]
				if j < a.size():
					a.remove_at(j)
				e[key_] = a
	else:
		return false
	var before := _state()
	curves[ci] = e
	_changed("Dissolve edge vertex", before)
	return true


## The menu's items for a picked curve's point under `at` - Smooth point / Sharp point ([]: none there).
func point_items(at: Vector2) -> Array:
	var h := pick_handle(at) if at.x > -1e5 else []
	if h.is_empty() and at.x > -1e5:
		h = _any_handle(at)
	if h.is_empty():
		return []
	var c: Dictionary = curves[int(h[0])]
	var j := int(h[1])
	var n := (c["ctrl"] as PackedVector3Array).size()
	var can := str(c["kind"]) in ["line", "spline", "path", "arc"] and (bool(c.get("closed", false)) or (j > 0 and j < n - 1))
	var mode := point_mode(c, j)
	return [
		["m_cv_pt_smooth", "Smooth vertex", "", "The edge runs through this vertex in a smooth bend (curved either side of it).", set_point_sharp.bind(int(h[0]), j, false), can and mode != 0],
		["m_cv_pt_sharp", "Sharp vertex", "", "A corner at this vertex: the edge runs straight to it and straight on from it.", set_point_sharp.bind(int(h[0]), j, true), can and mode != 1],
		["m_cv_pt_manual", "Manual vertex", "", "The edge's bend into this vertex shaped by hand: drag the part of the edge beside it (it\nglows green) - each side, and each edge meeting here, on its own.", set_point_manual.bind(int(h[0]), j),
			str(c["kind"]) in ["line", "spline", "path", "arc", "circle", "bezier"] and mode != 2],
	]


# --- points picked: one, or many (Shift+click a point); the tools that work on them ----------------

## The picked points, [[curve index, point index]...] (meta "points" keeps them by curve id - they
## survive curves added or taken out before them).
func picked_points() -> Array:
	var out := []
	for e in get_meta("points", []):
		var ci := _curve_index(int(e[0]))
		if ci >= 0 and int(e[1]) < (curves[ci]["ctrl"] as PackedVector3Array).size():
			out.append([ci, int(e[1])])
	return out


func _set_points(pts: Array) -> void:
	var keep := []
	for e in pts:
		if int(e[0]) >= 0 and int(e[0]) < curves.size():
			keep.append([int(curves[int(e[0])].get("id", -1)), int(e[1])])
	set_meta("points", keep)
	if layer:
		layer.queue_redraw()
	_refresh_panel()


func point_picked(ci: int, j: int) -> bool:
	for e in picked_points():
		if int(e[0]) == ci and int(e[1]) == j:
			return true
	return false


## Point `j` of curve `ci` picked (`add`: added to the picked ones - again: left out).
func pick_point(ci: int, j: int, add := false) -> void:
	var pts := picked_points() if add else []
	var at := -1
	for i in pts.size():
		if int(pts[i][0]) == ci and int(pts[i][1]) == j:
			at = i
	if at >= 0:
		pts.remove_at(at)
	else:
		pts.append([ci, j])
		if not ci in sel:
			sel.append(ci)
	set_meta("last_handle", [ci, j])
	_set_points(pts)


## The picked points by curve: {curve index: [point indices, in order]}.
func _points_by_curve() -> Dictionary:
	var by := {}
	for e in picked_points():
		if not by.has(int(e[0])):
			by[int(e[0])] = []
		if not int(e[1]) in by[int(e[0])]:
			by[int(e[0])].append(int(e[1]))
	for ci in by:
		(by[ci] as Array).sort()
	return by


## The baked solid (part) whose edges curve id `id` is one of (null - none).
func _edges_part_of(id: int) -> MeshInstance3D:
	if ed == null or ed.model == null:
		return null
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if str(spec.get("kind", "")) == "edges" and id in (spec.get("ids", []) as Array).map(func(x): return int(x)):
			return p
	return null


## A baked solid made its own again from how it is now: its mesh as settled, its curves now its start
## (no bake under it) - so its edges can be split or joined, and later edits bend from here.
func _rebase_part(p: MeshInstance3D) -> Dictionary:
	var spec: Dictionary = (p.get_meta("curve_solid", {}) as Dictionary).duplicate(true)
	spec.erase("orig")
	var cz := {}
	for id in spec.get("ids", []):
		var cv := curve_by_id(int(id))
		if not cv.is_empty():
			cz[str(int(id))] = to_json([cv])[0]
	spec["c0"] = cz
	return spec


func _set_edges_spec(p: MeshInstance3D, spec: Dictionary) -> void:
	_edge_bases().erase(int(spec.get("net", 0)))
	p.set_meta("curve_solid", spec)
	p.remove_meta("curve_solid_key")


## The baked solids holding curves `ids` rebased (their curves' points changed in number - an inserted
## or taken out point: places along them carry over point by point from here).
func _rebase_holding(ids: Array) -> void:
	var done := {}
	for id in ids:
		var p := _edges_part_of(int(id))
		if p != null and not done.has(p):
			done[p] = true
			_set_edges_spec(p, _rebase_part(p))


## Separate: each curve's picked points made a curve of their own - a run of picked points one curve,
## the rest of it the curves either side (a single picked point: the curve split there). The pieces
## meet where they were cut, so nothing moves; a baked solid's edge split the same way, its mesh as it
## is - each piece still shapes it.
func separate_points() -> bool:
	var by := _points_by_curve()
	if by.is_empty():
		ed._say("Separate: pick vertices of an edge first (click a vertex; Shift+click more).")
		return false
	var before := _state()
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var made := []
	var cis := by.keys()
	cis.sort()
	cis.reverse()   # (from the last: the indices before stay as they are)
	var any := false
	for ci in cis:
		var c0: Dictionary = curves[ci]
		if not str(c0["kind"]) in ["line", "spline", "path"]:
			continue   # (a circle's, an arc's points are its centre, ends... - not points along it)
		var c := as_points(c0)
		if c.is_empty():
			continue
		var k: PackedVector3Array = c["ctrl"]
		var n := k.size()
		var closed := bool(c.get("closed", false))
		var picked: Array = by[ci]
		# the cuts: where each run of picked points starts and ends
		var cuts := []
		for j in picked:
			var prev: int = (j - 1 + n) % n if closed else j - 1
			var nxt: int = (j + 1) % n if closed else j + 1
			if not prev in picked or picked.size() == 1:
				cuts.append(j)
			if not nxt in picked:
				cuts.append(j)
		var cs := {}
		for j in cuts:
			if closed or (j > 0 and j < n - 1):
				cs[j] = true
		cuts = cs.keys()
		cuts.sort()
		if cuts.is_empty() or (closed and cuts.size() < 1):
			continue
		# the pieces: from cut to cut (an open curve: from its start and to its end too)
		var ranges := []
		if closed:
			if cuts.size() == 1:
				ranges.append([cuts[0], cuts[0] + n])
			else:
				for m in cuts.size():
					var a: int = cuts[m]
					var b: int = cuts[(m + 1) % cuts.size()]
					ranges.append([a, b if b > a else b + n])
		else:
			var marks := [0] + cuts + [n - 1]
			for m in marks.size() - 1:
				if int(marks[m + 1]) > int(marks[m]):
					ranges.append([marks[m], marks[m + 1]])
		if ranges.size() < 2 and not closed:
			continue
		var sharp: PackedByteArray = c.get("sharp", PackedByteArray())
		var line := str(c["kind"]) == "line"
		var fr: PackedFloat32Array = EN.params(k, c)
		var pieces := []
		var new_curves := []
		for r in ranges:
			var pk := PackedVector3Array()
			var sh := PackedByteArray()
			var ti := PackedVector3Array()
			var to := PackedVector3Array()
			var tin0: PackedVector3Array = c.get("tin", PackedVector3Array())
			var tout0: PackedVector3Array = c.get("tout", PackedVector3Array())
			for j in range(int(r[0]), int(r[1]) + 1):
				pk.append(k[j % n])
				sh.append(1 if line else (sharp[j % n] if j % n < sharp.size() else (1 if str(c["kind"]) == "line" else 0)))
				ti.append(tin0[j % n] if j % n < tin0.size() else Vector3.ZERO)
				to.append(tout0[j % n] if j % n < tout0.size() else Vector3.ZERO)
			var pc := {"kind": "line" if line else "path", "ctrl": pk, "closed": false}
			if not tin0.is_empty():
				pc["tin"] = ti
				pc["tout"] = to
			for key_ in ["n", "owner", "hidden", "name"]:
				if c0.has(key_) and key_ != "name":
					pc[key_] = c0[key_]
			if not line:
				pc["sharp"] = sh
			new_curves.append(pc)
			var fa: float = fr[int(r[0]) % n]
			var fb: float = fr[int(r[1]) % n]
			if not closed and int(r[1]) == n - 1:
				fb = 1.0
			if int(r[0]) == 0 and not closed:
				fa = 0.0
			pieces.append([fa, fb])
		# the first piece keeps the curve's id (and name), the rest get new ones
		var id0 := int(c0.get("id", -1))
		var pdesc := []
		for m in new_curves.size():
			var pc: Dictionary = new_curves[m]
			if m == 0:
				pc["id"] = id0
				if c0.has("name"):
					pc["name"] = c0["name"]
				curves[ci] = pc
			else:
				_fresh(pc)
				curves.append(pc)
				made.append(curves.size() - 1)
			pdesc.append([int(pc["id"]), pieces[m][0], pieces[m][1]])
		# its baked solid: the edge split the same way, the mesh as it is
		var bp := _edges_part_of(id0)
		if bp != null:
			var spec := _rebase_part(bp)
			var chs: Array = spec["chains"]
			for cj in chs.size():
				if int(chs[cj]["id"]) == id0:
					EN.split_chain(spec, cj, pdesc)
					break
			var cz := {}
			for id in spec["ids"]:
				var cv := curve_by_id(int(id))
				if not cv.is_empty():
					cz[str(int(id))] = to_json([cv])[0]
			spec["c0"] = cz
			_set_edges_spec(bp, spec)
		any = true
	if not any:
		ed._say("Separate: pick vertices inside an edge (not only its ends).")
		return false
	sel = made.duplicate()
	set_meta("points", [])
	_changed("Separate vertices", before)
	ed._say("Separated: %d new edge%s." % [made.size(), "" if made.size() == 1 else "s"])
	return true


## Merge: two picked curve ends (one on each of two curves) - the two curves made one, running on
## through where they met (a corner there: neither changes shape); both ends of one curve - closed.
## Other points picked: moved together to their middle (welded). A baked solid's two edges joined the
## same way - its mesh as it is.
func merge_points() -> bool:
	var pts := picked_points()
	if pts.size() < 2:
		ed._say("Merge: pick two vertices (Shift+click the second).")
		return false
	var before := _state()
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var own := owner_xfs()
	var end_of := func(e: Array) -> int:   # 0: start, 1: end, -1: inside (or a closed curve)
		var c: Dictionary = curves[int(e[0])]
		if bool(c.get("closed", false)) or not str(c["kind"]) in ["line", "spline", "path", "arc", "bezier"]:
			return -1
		var n := (as_points(c)["ctrl"] as PackedVector3Array).size() if str(c["kind"]) in ["arc", "bezier"] else (c["ctrl"] as PackedVector3Array).size()
		var j := int(e[1])
		if str(c["kind"]) == "arc":
			return 0 if j == 0 else (1 if j == 1 else -1)
		if str(c["kind"]) == "bezier":
			return 0 if j == 0 else (1 if j == 3 else -1)
		return 0 if j == 0 else (1 if j == n - 1 else -1)
	if pts.size() == 2 and int(end_of.call(pts[0])) >= 0 and int(end_of.call(pts[1])) >= 0:
		var ca := int(pts[0][0])
		var cb := int(pts[1][0])
		var ea := int(end_of.call(pts[0]))
		var eb := int(end_of.call(pts[1]))
		if ca == cb:
			if ea == eb:
				return false
			_close_ends(ca)
			set_meta("points", [])
			_changed("Close edge", before)
			return true
		if not _join_ends(ca, ea, cb, eb):
			return false
		sel = [ca if ca < cb else ca - 1]
		set_meta("points", [])
		_changed("Merge edges", before)
		ed._say("Merged: one edge.")
		return true
	# any other points: welded at their middle
	var mid := Vector3.ZERO
	for e in pts:
		mid += cx(curves[int(e[0])], own) * (curves[int(e[0])]["ctrl"][int(e[1])] as Vector3)
	mid /= pts.size()
	for e in pts:
		var x := cx(curves[int(e[0])], own)
		var k: PackedVector3Array = curves[int(e[0])]["ctrl"]
		var was := k[int(e[1])]
		k[int(e[1])] = x.affine_inverse() * mid
		curves[int(e[0])]["ctrl"] = k
		_move_corner(int(e[0]), was, k[int(e[1])])
	_changed("Merge vertices", before)
	return true


## Curve `ca`'s two ends made one point (their middle): closed - a baked solid's edge closed with it.
func _close_ends(ca: int) -> void:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var c := as_points(curves[ca])
	var k: PackedVector3Array = c["ctrl"]
	var mid := (k[0] + k[k.size() - 1]) * 0.5
	k.remove_at(k.size() - 1)
	k[0] = mid
	c["ctrl"] = k
	c["closed"] = true
	if c.has("sharp"):
		var sh: PackedByteArray = c["sharp"]
		sh.resize(k.size())
		sh[0] = 1
		c["sharp"] = sh
	curves[ca] = c
	var bp := _edges_part_of(int(c.get("id", -1)))
	if bp != null:
		var spec := _rebase_part(bp)
		for cj in (spec["chains"] as Array).size():
			if int(spec["chains"][cj]["id"]) == int(c["id"]):
				EN.merge_chains(spec, cj, cj, false, false, 1.0, 0.0, int(c["id"]))
		spec["c0"][str(int(c["id"]))] = to_json([c])[0]
		_set_edges_spec(bp, spec)


## Curves `ca` and `cb` made one where end `ea` of the one meets end `eb` of the other (0 its start, 1
## its end): their points in a row, a corner where they met (neither changes shape) - `cb` taken out; a
## baked solid's two edges joined the same way. False - not done (they shape different solids).
func _join_ends(ca: int, ea: int, cb: int, eb: int) -> bool:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var own := owner_xfs()
	# two curves: A run so it ends at its picked end, B so it starts at its
	var A := as_points(curves[ca])
	var B := as_points(curves[cb])
	var xa := cx(curves[ca], own)
	var xb := cx(curves[cb], own)
	var ka: PackedVector3Array = (A["ctrl"] as PackedVector3Array).duplicate()
	var kb := PackedVector3Array()
	for q in (B["ctrl"] as PackedVector3Array):
		kb.append(xa.affine_inverse() * (xb * q))   # (in A's space)
	var sa: PackedByteArray = A.get("sharp", PackedByteArray())
	var sb: PackedByteArray = B.get("sharp", PackedByteArray())
	var line_a := str(A["kind"]) == "line"
	var line_b := str(B["kind"]) == "line"
	sa = _sharp_of(A, ka.size())
	sb = _sharp_of(B, kb.size())
	var ra := ea == 0
	var rb := eb == 1
	if ra:
		ka.reverse()
		sa.reverse()
	if rb:
		kb.reverse()
		sb.reverse()
	var meet := (ka[ka.size() - 1] + kb[0]) * 0.5
	ka[ka.size() - 1] = meet
	var k := ka.duplicate()
	var sh := sa.duplicate()
	sh[sh.size() - 1] = 1   # (a corner where they met: each keeps its shape)
	for m in range(1, kb.size()):
		k.append(kb[m])
		sh.append(sb[m])
	var la := 0.0
	var lb := 0.0
	var pa := sample(A)
	for m in range(1, pa.size()):
		la += pa[m - 1].distance_to(pa[m])
	var pb := sample(B)
	for m in range(1, pb.size()):
		lb += pb[m - 1].distance_to(pb[m])
	var M := {"kind": "line" if line_a and line_b else "path", "ctrl": k, "closed": false, "id": int(curves[ca].get("id", -1))}
	if not (line_a and line_b):
		M["sharp"] = sh
	for key_ in ["owner", "hidden", "name", "n"]:
		if curves[ca].has(key_):
			M[key_] = curves[ca][key_]
	var ida := int(curves[ca].get("id", -1))
	var idb := int(curves[cb].get("id", -1))
	var pa_ := _edges_part_of(ida)
	var pb_ := _edges_part_of(idb)
	if (pa_ != null or pb_ != null) and pa_ != pb_:
		ed._say("Merge: those two edges shape different solids.")
		return false
	curves[ca] = M
	curves.remove_at(cb)
	if pa_ != null:
		var spec := _rebase_part(pa_)
		var ia := -1
		var ib := -1
		for cj in (spec["chains"] as Array).size():
			if int(spec["chains"][cj]["id"]) == ida:
				ia = cj
			if int(spec["chains"][cj]["id"]) == idb:
				ib = cj
		if ia >= 0 and ib >= 0:
			EN.merge_chains(spec, ia, ib, ra, rb, la, lb, ida)
			spec["chains"] = (spec["chains"] as Array).duplicate()   # (a new list: what was worked out for the old one - its faces - not taken for it)
			_faces_memo.clear()   # (the old list changed in place: no faces found by it)
			spec["c0"].erase(str(idb))
			spec["c0"][str(ida)] = to_json([M])[0]
			_set_edges_spec(pa_, spec)
	return true


## Ready-made solids from curves - each a curve and the solid made from it (live: reshape the curve and
## the solid follows): [kind, icon, name, how it's made].
const CURVE_PRIMS := [
	["box", "m_box", "Box", "A square (1 m) on the ground, extruded 1 m up."],
	["cylinder", "m_cylinder", "Cylinder", "A circle (1 m across) on the ground, extruded 1 m up."],
	["prism", "m_cv_polygon", "Prism", "A hexagon (1 m across) on the ground, extruded 1 m up."],
	["cone", "m_cone", "Cone", "A slanted line (1 m across, 1 m high) turned round the Y axis."],
	["sphere", "m_sphere", "Sphere", "A half circle (1 m across) turned round the Y axis."],
	["torus", "m_torus", "Torus", "A circle (0.3 m across) beside the Y axis, turned round it."],
]


## A ready-made solid from curves (CURVE_PRIMS' `kind`) at the model's middle, on the ground: its curve
## added and its solid made from it - a solid that follows its curve. The new part (null - none).
func add_curve_primitive(kind: String, at := Vector3.INF) -> MeshInstance3D:
	var c := {}
	var op := "extrude"
	var v := 1.0
	match kind:
		"box":
			c = {"kind": "line", "ctrl": PackedVector3Array([Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]), "closed": true, "n": Vector3.UP}
		"cylinder":
			c = {"kind": "circle", "ctrl": PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0, 0)]), "closed": true, "n": Vector3.UP}
		"prism":
			var k := PackedVector3Array()
			for j in 6:
				k.append(Vector3(0.5, 0, 0).rotated(Vector3.UP, TAU * j / 6.0))
			c = {"kind": "line", "ctrl": k, "closed": true, "n": Vector3.UP}
		"cone":
			c = {"kind": "line", "ctrl": PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(0, 1, 0)]), "closed": false, "n": Vector3.BACK}
			op = "revolve"
			v = 360.0
		"sphere":
			c = {"kind": "arc", "ctrl": PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0.5, 0), Vector3(0, 1, 0)]), "closed": false, "n": Vector3.BACK}
			op = "revolve"
			v = 360.0
		"torus":
			c = {"kind": "circle", "ctrl": PackedVector3Array([Vector3(0.35, 0.15, 0), Vector3(0.5, 0.15, 0)]), "closed": true, "n": Vector3.BACK}
			op = "revolve"
			v = 360.0
		_:
			return null
	stop()
	c["name"] = "%s edge" % kind.capitalize()
	add_curve(c)
	var p := make_part(op, v)
	if p:
		p.name = ed._unique(kind.capitalize())
		_refresh_panel()
		if at != Vector3.INF:
			p.position = at   # (dropped in the view: standing where it was dropped - its edge goes with it)
		ed._fill_parts()
		ed._say("%s made from its edge - reshape the edge and it follows." % kind.capitalize())
	return p


func prim_items() -> Array:
	var out := []
	for d in CURVE_PRIMS:
		out.append([d[1], "Add " + str(d[2]).to_lower(), "", "%s\nA solid made from an edge: drag the edge's vertices and it follows." % d[3], add_curve_primitive.bind(str(d[0])), true])
	return out


## Recipe `spec` with its curve ids renamed by `idmap` (old -> new) - an object's edges brought into
## another, made new. A copy.
static func remap_spec(spec: Dictionary, idmap: Dictionary) -> Dictionary:
	var sp := spec.duplicate(true)
	var mp := func(x): return idmap.get(int(x), int(x))
	if sp.has("ids"):
		sp["ids"] = (sp["ids"] as Array).map(mp)
	if sp.has("axis") and int(sp["axis"]) >= 0:
		sp["axis"] = mp.call(sp["axis"])
	if sp.has("chains"):
		for ch in sp["chains"]:
			ch["id"] = mp.call(ch["id"])
	for key_ in ["c0"]:
		if sp.has(key_):
			var nc := {}
			for k in sp[key_]:
				nc[str(mp.call(int(k)))] = sp[key_][k]
			sp[key_] = nc
	if sp.has("orig") and (sp["orig"] as Dictionary).has("c0"):
		var oc := {}
		for k in sp["orig"]["c0"]:
			oc[str(mp.call(int(k)))] = sp["orig"]["c0"][k]
		sp["orig"]["c0"] = oc
	for key_ in ["a", "b"]:
		if sp.get(key_) is Dictionary:
			sp[key_] = remap_spec(sp[key_], idmap)
	if sp.has("res_stack"):
		sp["res_stack"] = []
	return sp


## The merge distance: ends this close count as one point (Merge curves).
func merge_dist() -> float:
	return float(get_meta("merge_dist", 0.001))


func set_merge_dist(v: float) -> void:
	set_meta("merge_dist", maxf(v, 0.0))


## Merge curves: the picked curves (the picked solid's, when it's picked whole) joined wherever their ends
## meet - a point they share, or ends within the merge distance: the two that run on straightest through
## each such point made one curve (a corner there - neither changes shape), again till none meet; a
## curve whose own two ends meet is closed. Baked solids' edges are joined the same way, their meshes as
## they are. One undo step. How many joins were made.
func merge_curves_selected() -> int:
	var ids := []
	for i in sel:
		ids.append(int(curves[i].get("id", -1)))
	if ids.size() < 2 and picked_solid() != null:
		ids = ((picked_solid().get_meta("curve_solid") as Dictionary).get("ids", []) as Array).map(func(x): return int(x))
	if ids.size() < 2:
		ed._say("Merge edges: pick two edges or more (or a whole solid).")
		return 0
	var before := _state()
	var md := maxf(merge_dist(), 1e-6)
	var own := owner_xfs()
	var joins := 0
	for guard in 500:
		# every open curve's two ends (world), and the way it runs into each
		var ends := []   # [curve index, end (0 start / 1 end), position, the way out of the curve there]
		for id in ids:
			var ci := _curve_index(int(id))
			if ci < 0:
				continue
			var c: Dictionary = curves[ci]
			if bool(c.get("closed", false)) or not str(c["kind"]) in ["line", "spline", "path", "arc", "bezier"]:
				continue
			var e := as_points(c)
			var s := sample(e)
			if s.size() < 2:
				continue
			var x := cx(c, own)
			var a := x * s[0]
			var b := x * s[s.size() - 1]
			ends.append([ci, 0, a, (a - x * s[1]).normalized()])
			ends.append([ci, 1, b, (b - x * s[s.size() - 2]).normalized()])
		var best := []
		var best_score := INF
		for m in ends.size():
			for n in range(m + 1, ends.size()):
				var p: Array = ends[m]
				var q: Array = ends[n]
				if (p[2] as Vector3).distance_to(q[2]) > md:
					continue
				var score := 0.0
				if int(p[0]) == int(q[0]):
					var c: Dictionary = curves[int(p[0])]
					if (as_points(c)["ctrl"] as PackedVector3Array).size() < 3:
						continue   # (a two-point line's ends: nothing to close)
					score = 1.5   # (a curve closing on itself: after any straight join)
				else:
					# (running on straight through the point: one's way out opposite the other's)
					score = 1.0 + (p[3] as Vector3).dot(q[3])
				if score < best_score:
					best_score = score
					best = [p, q]
		if best.is_empty():
			break
		var p: Array = best[0]
		var q: Array = best[1]
		if int(p[0]) == int(q[0]):
			_close_ends(int(p[0]))
		elif not _join_ends(int(p[0]), int(p[1]), int(q[0]), int(q[1])):
			ids.erase(int(curves[int(q[0])].get("id", -1)))   # (different solids: left apart)
			continue
		joins += 1
	if joins == 0:
		ed._say("Merge edges: no ends meet within %s m." % String.num(md, 4))
		return 0
	sel = []
	for id in ids:
		var ci := _curve_index(int(id))
		if ci >= 0:
			sel.append(ci)
	set_meta("points", [])
	_changed("Merge edges", before)
	ed._say("Merged: %d join%s - %d edge%s now." % [joins, "" if joins == 1 else "s", sel.size(), "" if sel.size() == 1 else "s"])
	return joins


## A curve's corners as flags, one a point (a line: all; a spline: none; a path: as marked).
static func _sharp_of(c: Dictionary, n: int) -> PackedByteArray:
	var sh := PackedByteArray()
	sh.resize(n)
	for j in n:
		sh[j] = 1 if point_sharp(c, j) else 0
	if not bool(c.get("closed", false)) and n > 0:
		sh[0] = 1
		sh[n - 1] = 1
	return sh


## Extrude: each picked point pulled out into a new one, then moved with the mouse (click keeps,
## right-click takes it back): an open curve's end (not a baked solid's edge) grows on from it; any other
## point - a new line starts from it.
func extrude_points() -> bool:
	var pts := picked_points()
	if pts.is_empty():
		ed._say("Extrude: pick vertices first.")
		return false
	var before := _state()
	var own := owner_xfs()
	var grown := []
	for e in pts:
		var ci := int(e[0])
		var j := int(e[1])
		var c: Dictionary = curves[ci]
		var k: PackedVector3Array = c["ctrl"]
		var x := cx(c, own)
		var at_end := not bool(c.get("closed", false)) and str(c["kind"]) in ["line", "spline", "path"] and (j == 0 or j == k.size() - 1) and not _any_baked([ci])
		if at_end:
			var nk := k.duplicate()
			if j == 0:
				nk.insert(0, k[0])
			else:
				nk.append(k[j])
			c["ctrl"] = nk
			if c.has("sharp"):
				var sh: PackedByteArray = c["sharp"]
				if j == 0:
					sh.insert(0, 1)
				else:
					sh.append(1)
				c["sharp"] = sh
			if c.has("radii"):
				var r: PackedFloat32Array = c["radii"]
				if j == 0:
					r.insert(0, 0.0)
				else:
					r.append(0.0)
				c["radii"] = r
			for key_ in ["tin", "tout"]:
				if c.has(key_):
					var tv: PackedVector3Array = c[key_]
					tv.resize(k.size())
					if j == 0:
						tv.insert(0, Vector3.ZERO)
					else:
						tv.append(Vector3.ZERO)
					c[key_] = tv
			curves[ci] = c
			grown.append([ci, 0 if j == 0 else nk.size() - 1, x])
		else:
			var w := x * k[j]
			var nc := {"kind": "line", "ctrl": PackedVector3Array([w, w]), "closed": false}
			_fresh(nc)
			curves.append(nc)
			grown.append([curves.size() - 1, 1, Transform3D()])
	var multi := []
	for g in grown:
		multi.append([int(g[0]), int(g[1]), (g[2] as Transform3D) * (curves[int(g[0])]["ctrl"][int(g[1])] as Vector3), g[2]])
	var pts2 := []
	for g in grown:
		pts2.append([int(g[0]), int(g[1])])
		if not int(g[0]) in sel:
			sel.append(int(g[0]))
	_set_points(pts2)
	var h: Array = pts2[0]
	_drag = {"handle": h, "before": before, "x": multi[0][3], "own": own, "press": ed._mouse, "start": multi[0][2], "moved": true,
		"grab": "Extrude vertices", "multi": multi.slice(1)}
	ed.view.hint = "Extrude: move the mouse - click keeps it, right-click takes it back (X / Y / Z: along an axis)."
	layer.queue_redraw()
	return true


## Subdivide: a new point on the curve between each two picked points next to each other (on one
## curve) - its shape as it was.
func subdivide_points() -> bool:
	var by := _points_by_curve()
	var before := _state()
	var any := false
	var touched := []
	for ci in by:
		var c := as_points(curves[ci])
		if c.is_empty():
			continue
		var k: PackedVector3Array = c["ctrl"]
		var n := k.size()
		var closed := bool(c.get("closed", false))
		var picked: Array = by[ci]
		var s := sample(c)
		var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
		var fr: PackedFloat32Array = EN.params(k, c)
		var adds := []
		for j in picked:
			var nx: int = (j + 1) % n if closed else j + 1
			if nx < n and nx in picked:
				var fa: float = fr[j]
				var fb: float = fr[nx] if fr[nx] > fa else fr[nx] + 1.0
				adds.append([j, EN.at(c, fposmod((fa + fb) * 0.5, 1.0))])
		if adds.is_empty():
			continue
		adds.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
		var sh := _sharp_of(c, n) if str(c["kind"]) != "spline" else PackedByteArray()
		if str(c["kind"]) == "spline":
			sh.resize(n)
		var tvs := {}
		for key_ in ["tin", "tout"]:
			if c.has(key_):
				var tv0: PackedVector3Array = c[key_]
				tv0.resize(n)
				tvs[key_] = tv0
		for a in adds:
			k.insert(int(a[0]) + 1, a[1])
			sh.insert(int(a[0]) + 1, 0 if str(c["kind"]) != "line" else 1)
			for key_ in tvs:
				(tvs[key_] as PackedVector3Array).insert(int(a[0]) + 1, Vector3.ZERO)
		for key_ in tvs:
			c[key_] = tvs[key_]
		c["ctrl"] = k
		if str(c["kind"]) != "line":
			c["kind"] = "path"
			c["sharp"] = sh
		curves[ci] = c
		touched.append(int(c.get("id", -1)))
		any = true
	if not any:
		ed._say("Subdivide: pick two or more vertices next to each other on an edge.")
		return false
	set_meta("points", [])
	_changed("Subdivide vertices", before)
	_rebase_holding(touched)
	return true


## Connect: a straight line between the two picked points (a new curve, its ends on them).
func connect_points() -> bool:
	var pts := picked_points()
	if pts.size() != 2:
		ed._say("Connect: pick two vertices.")
		return false
	var own := owner_xfs()
	var before := _state()
	var a: Vector3 = cx(curves[int(pts[0][0])], own) * (curves[int(pts[0][0])]["ctrl"][int(pts[0][1])] as Vector3)
	var b: Vector3 = cx(curves[int(pts[1][0])], own) * (curves[int(pts[1][0])]["ctrl"][int(pts[1][1])] as Vector3)
	var nc := {"kind": "line", "ctrl": PackedVector3Array([a, b]), "closed": false}
	_fresh(nc)
	curves.append(nc)
	sel = [curves.size() - 1]
	set_meta("points", [])
	_changed("Connect vertices", before)
	return true


## Delete points: the picked points taken out of their curves (each runs on between its neighbours).
func delete_points() -> bool:
	var pts := picked_points()
	if pts.is_empty():
		return false
	pts.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var before := _state()
	var touched := []
	var n_done := 0
	for e in pts:
		var c: Dictionary = curves[int(e[0])]
		var k: PackedVector3Array = c["ctrl"]
		var j := int(e[1])
		var closed := bool(c.get("closed", false))
		if not str(c["kind"]) in ["line", "spline", "path"] or k.size() <= (3 if closed else 2):
			continue
		if not closed and (j == 0 or j == k.size() - 1) and _any_baked([int(e[0])]):
			continue
		var e2 := c.duplicate(true)
		var nk := k.duplicate()
		nk.remove_at(j)
		e2["ctrl"] = nk
		for key_ in ["sharp", "radii", "tin", "tout"]:
			if e2.has(key_) and j < (e2[key_] as Variant).size():
				var a = e2[key_]
				a.remove_at(j)
				e2[key_] = a
		curves[int(e[0])] = e2
		touched.append(int(c.get("id", -1)))
		n_done += 1
	if n_done == 0:
		ed._say("Delete vertices: none of those can go (a baked solid's edge keeps its ends).")
		return false
	set_meta("points", [])
	_changed("Delete vertices", before)
	_rebase_holding(touched)
	return true


## What a move / turn / scale works on when it's not the picked curves: the picked points, else the
## picked patch's every point ([] - neither).
func _xf_points() -> Array:
	var pts := picked_points()
	if not pts.is_empty():
		return pts
	var pa := picked_patch()
	var ps := picked_solid()
	if pa.is_empty() and ps == null:
		return []
	var out := []
	for id in (pa["ids"] if not pa.is_empty() else (ps.get_meta("curve_solid") as Dictionary).get("ids", [])):
		var ci := _curve_index(int(id))
		if ci >= 0:
			for j in (curves[ci]["ctrl"] as PackedVector3Array).size():
				out.append([ci, j])
	return out


# --- patches: a baked solid's face between its edges, picked by clicking on it -------------------

## The picked patch: {part, ids (its edges' curve ids), tris (its triangles in the part's mesh now)} -
## {} none. (Meta "patch" keeps the part and the ids; its triangles found again as the mesh changes.)
func picked_patch() -> Dictionary:
	var m: Dictionary = get_meta("patch", {})
	if m.is_empty():
		return {}
	var p = instance_from_id(int(m.get("part", 0)))
	if not (p is MeshInstance3D) or not is_instance_valid(p) or not (p as Node).is_inside_tree():
		return {}
	var spec: Dictionary = (p as MeshInstance3D).get_meta("curve_solid", {})
	if str(spec.get("kind", "")) != "edges" or not spec.has("mesh"):
		return {}
	# (its triangles worked out once for the mesh as it is - kept till the mesh changes)
	var pc: Dictionary = get_meta("patch_cache", {})
	var tris: PackedInt32Array
	if pc.get("m") == m and is_same(pc.get("t"), spec["mesh"]["t"]) and is_same(pc.get("fv"), spec.get("fv")):
		tris = pc["tris"]   # (the same mesh: its arrays the very same ones)
	else:
		tris = _patch_tris(spec, m["ids"], m.get("seed", Vector3.INF))
		set_meta("patch_cache", {"m": m.duplicate(true), "t": spec["mesh"]["t"], "fv": spec.get("fv"), "tris": tris})
	if tris.is_empty():
		return {}
	return {"part": p, "ids": m["ids"], "tris": tris, "spec": spec}


## Baked solid `spec`'s faces: {face: [triangle indices]} and each triangle's face, flooded between
## its edges (mesh edges between neighbouring points of one curve, and real corners).
static func _faces_of(spec: Dictionary) -> Dictionary:
	# (kept for the last few meshes - the same lists (they're only ever replaced): a press on a face
	# worked them out four times over, 100 ms)
	for e in _faces_memo:
		if is_same(e[0], spec["mesh"]["v"]) and is_same(e[1], spec["mesh"]["t"]) and is_same(e[2], spec.get("fv")) and (is_same(e[3], spec.get("chains")) or e[3] == spec.get("chains")):
			return e[4]
	var fs := _faces_make(spec)
	_faces_ids(spec, fs)   # (every face's edges too, kept with them)
	_faces_memo.push_front([spec["mesh"]["v"], spec["mesh"]["t"], spec.get("fv"), spec.get("chains"), fs])
	if _faces_memo.size() > FACES_MEMO:
		_faces_memo.resize(FACES_MEMO)
	return fs


static var _faces_memo := []
const FACES_MEMO := 160   # (a character's ninety solids' faces kept - made ahead while nothing's going on)


## Solid `spec`'s faces already worked out (in the memo).
static func _faces_known(spec: Dictionary) -> bool:
	for e in _faces_memo:
		if is_same(e[0], spec["mesh"]["v"]) and is_same(e[1], spec["mesh"]["t"]) and is_same(e[2], spec.get("fv")) and (is_same(e[3], spec.get("chains")) or e[3] == spec.get("chains")):
			return true
	return false


## (nothing being dragged) The next solid's faces worked out on a worker, one at a time - a press on a
## face finds them ready (worked out then, a big solid's were 50 ms).
func _warm_faces() -> bool:
	if has_meta("faces_job"):
		var fj: Array = get_meta("faces_job")
		if not WorkerThreadPool.is_task_completed(int(fj[0])):
			return true
		WorkerThreadPool.wait_for_task_completion(int(fj[0]))
		remove_meta("faces_job")
		var key: Array = fj[2]
		if fj[1][0] is Dictionary:
			_faces_memo.push_front([key[0], key[1], key[2], key[3], fj[1][0]])
			if _faces_memo.size() > FACES_MEMO:
				_faces_memo.resize(FACES_MEMO)   # (the oldest - most likely meshes since replaced - let go)
		return true
	if not _drag.is_empty() or not op.is_empty():
		return true
	for p: MeshInstance3D in ed.parts():
		var sp: Dictionary = p.get_meta("curve_solid", {})
		if str(sp.get("kind", "")) != "edges" or not sp.has("mesh"):
			continue
		# (looked up once a mesh: its lists noted on the part - each frame's look is four comparisons a solid)
		var fw: Array = p.get_meta("faces_warm", [])
		if fw.size() == 4 and is_same(fw[0], sp["mesh"]["v"]) and is_same(fw[1], sp["mesh"]["t"]) and is_same(fw[2], sp.get("fv")) and is_same(fw[3], sp.get("chains")):
			continue
		p.set_meta("faces_warm", [sp["mesh"]["v"], sp["mesh"]["t"], sp.get("fv"), sp.get("chains")])
		if _faces_known(sp):
			continue
		var work := {"mesh": {"v": sp["mesh"]["v"], "t": sp["mesh"]["t"]}, "fv": sp.get("fv", []), "chains": (sp.get("chains", []) as Array).duplicate(true)}
		var hold := [null]
		var id := WorkerThreadPool.add_task(func():
			hold[0] = _faces_make(work)
			_faces_ids(work, hold[0]))   # (every face's edges too)
		set_meta("faces_job", [id, hold, [sp["mesh"]["v"], sp["mesh"]["t"], sp.get("fv"), sp.get("chains")]])
		return true
	return _drag.is_empty() and not _warm_face_levels_done()


static func _faces_make(spec: Dictionary) -> Dictionary:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var mv: Array = spec["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, mv.size(), 3):
		v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
	var t := PackedInt32Array(spec["mesh"]["t"])
	var feat := {}
	var by_c := {}
	for e in spec.get("fv", []):
		if not by_c.has(int(e[1])):
			by_c[int(e[1])] = []
		by_c[int(e[1])].append([float(e[2]), int(e[0])])
	var chains: Array = spec.get("chains", [])
	for ci in by_c:
		var lst: Array = by_c[ci]
		lst.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		for m in lst.size() - 1:
			feat[EN._pk(int(lst[m][1]), int(lst[m + 1][1]))] = true
		if ci < chains.size() and bool(chains[ci].get("closed", false)) and lst.size() > 2:
			feat[EN._pk(int(lst[lst.size() - 1][1]), int(lst[0][1]))] = true
	EN.corner_edges(v, t, feat)
	var face: PackedInt32Array = EN.face_of(v, t, feat)
	return {"v": v, "t": t, "face": face, "feat": feat, "by_c": by_c}


## A face's edges: the curve ids of the chains along its rim.
static func _face_ids(spec: Dictionary, fs: Dictionary, f: int) -> Array:
	var all_ids := _faces_ids(spec, fs)   # (every face's at once, kept with the faces)
	return (all_ids[f] as Array).duplicate() if f >= 0 and f < all_ids.size() else []


## Every face's edges (curve ids along its rim, sorted) - _face_ids for all of them in one go (kept in
## `fs`).
static func _faces_ids(spec: Dictionary, fs: Dictionary) -> Array:
	if fs.has("ids_by_face"):
		return fs["ids_by_face"]
	var t: PackedInt32Array = fs["t"]
	var face: PackedInt32Array = fs["face"]
	var nf := 0
	for f in face:
		nf = maxi(nf, f + 1)
	var on := {}
	for e in spec.get("fv", []):
		if not on.has(int(e[0])):
			on[int(e[0])] = []
		on[int(e[0])].append(int(e[1]))
	var nv := 0
	for q in t:
		nv = maxi(nv, q + 1)
	var cnt := {}
	for ti in face.size():
		var f := face[ti]
		for j in 3:
			var a := t[ti * 3 + j]
			var b := t[ti * 3 + (j + 1) % 3]
			var key := (f * nv + mini(a, b)) * nv + maxi(a, b)
			cnt[key] = int(cnt.get(key, 0)) + 1
	var sets := []
	for f in nf:
		sets.append({})
	var chains: Array = spec.get("chains", [])
	for key in cnt:
		if int(cnt[key]) != 1:
			continue
		var b := int(key) % nv
		var a := (int(key) / nv) % nv
		var f := int(key) / nv / nv
		for ci in on.get(a, []):
			if ci in on.get(b, []) and ci < chains.size():
				(sets[f] as Dictionary)[int(chains[ci]["id"])] = true
	var out := []
	for f in nf:
		var ids: Array = (sets[f] as Dictionary).keys()
		ids.sort()
		out.append(ids)
	fs["ids_by_face"] = out
	return out


## The triangles of the face of `spec` whose edges are `ids` (the one nearest `seed` when several).
static func _patch_tris(spec: Dictionary, ids: Array, seed := Vector3.INF) -> PackedInt32Array:
	var fs := _faces_of(spec)
	var face: PackedInt32Array = fs["face"]
	var nf := 0
	for f in face:
		nf = maxi(nf, f + 1)
	var want := ids.duplicate()
	want.sort()
	var best := -1
	var best_d := INF
	var v: PackedVector3Array = fs["v"]
	var t: PackedInt32Array = fs["t"]
	var all_ids := _faces_ids(spec, fs)
	for f in nf:
		if all_ids[f] != want:
			continue
		var d := 0.0
		if seed != Vector3.INF:
			d = INF
			for ti in face.size():
				if face[ti] == f:
					d = minf(d, ((v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0).distance_to(seed))
		if d < best_d:
			best_d = d
			best = f
	var out := PackedInt32Array()
	if best < 0:
		return out
	for ti in face.size():
		if face[ti] == best:
			out.append(ti)
	return out


## The baked solid's surface under `at`: {part, tri, at (the part's own space), world} ({} - none).
func _baked_hit(at: Vector2) -> Dictionary:
	if ed == null or ed.model == null:
		return {}
	var o: Vector3 = ed.view.cam.project_ray_origin(at)
	var dir: Vector3 = ed.view.cam.project_ray_normal(at)
	var best := INF
	var hit := {}
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if str(spec.get("kind", "")) != "edges" or not spec.has("mesh") or not p.is_visible_in_tree() or p.mesh == null or locked(p):
			continue
		var inv := p.global_transform.affine_inverse()
		var lo := inv * o
		var ld := (inv.basis * dir).normalized()
		var t: Array = spec["mesh"]["t"]
		# (the drawn mesh's triangles, found by the engine - each is the solid's own triangle when it's
		# drawn as settled; else - mid-edit - looked for one by one)
		var tmc: Array = p.get_meta("hit_tm", [])
		if tmc.is_empty() or tmc[0] != p.mesh:
			tmc = [p.mesh, p.mesh.generate_triangle_mesh()]
			p.set_meta("hit_tm", tmc)
		var r: Dictionary = (tmc[1] as TriangleMesh).intersect_ray(lo, ld) if tmc[1] != null else {}
		if r.is_empty():
			continue
		var w := p.global_transform * (r["position"] as Vector3)
		var dd := w.distance_to(o)
		if dd >= best:
			continue
		var tri := int(r.get("face_index", -1))
		if p.mesh.get_surface_count() != 1 or p.mesh.surface_get_array_index_len(0) != t.size() or tri < 0:
			tri = _nearest_tri(spec, r["position"])
		best = dd
		hit = {"part": p, "tri": tri, "at": r["position"], "world": w}
	return hit


## The solid's triangle nearest `q` (its own space) - by their middles.
static func _nearest_tri(spec: Dictionary, q: Vector3) -> int:
	var mv: Array = spec["mesh"]["v"]
	var t: Array = spec["mesh"]["t"]
	var best := INF
	var bi := 0
	for i in range(0, t.size(), 3):
		var c := Vector3.ZERO
		for j in 3:
			var vi := int(t[i + j])
			c += Vector3(mv[vi * 3], mv[vi * 3 + 1], mv[vi * 3 + 2])
		var d := (c / 3.0).distance_squared_to(q)
		if d < best:
			best = d
			bi = i / 3
	return bi


## A press on a face (or a baked edge) turned into a drag: what's picked there moved with the mouse -
## the picked solid or patch if the press is on it, else the patch under it (picked now) - or the
## pressed edge's points.
func _begin_group_drag() -> void:
	var d := _drag
	var pts := []
	var what := "patch"
	if d.has("baked_curve"):
		var ci := int(d["baked_curve"])
		if not ci in sel:
			select(ci)
		for j in (curves[ci]["ctrl"] as PackedVector3Array).size():
			pts.append([ci, j])
		what = "curve"
	else:
		var sh := _baked_hit(d["press"])
		var ps := picked_solid()
		if ps != null and not sh.is_empty() and sh["part"] == ps:
			what = "solid"
		else:
			var pa := picked_patch()
			var on_it := false
			if not pa.is_empty() and not sh.is_empty() and pa["part"] == sh["part"]:
				on_it = int(sh["tri"]) in (pa["tris"] as PackedInt32Array)
			if not on_it:
				set_meta("patch", {})
				set_meta("solid", 0)
				pick_patch(d["press"])
		pts = _xf_points()
	var own := owner_xfs()
	var group := []
	for e in pts:
		var x := cx(curves[int(e[0])], own)
		group.append([int(e[0]), int(e[1]), x * (curves[int(e[0])]["ctrl"][int(e[1])] as Vector3), x])
	d.erase("surface")
	d.erase("baked_curve")
	d.erase("grow_c")
	d["group"] = group
	d["what"] = what
	d["before"] = _state()   # (the pick as it is now: undo leaves it so)
	_drag = d
	_drag["solids_only"] = _drag_solids()   # (worked out now: the lines' first drawing already knows them)


## A click at `at` on a baked solid's surface (no curve there): the face under it picked as a patch -
## its edges' curves picked with it. True - one was.
func pick_patch(at: Vector2) -> bool:
	if ed == null or ed.model == null:
		return false
	var hit := _baked_hit(at)
	if hit.is_empty():
		return false
	var hp: MeshInstance3D = hit["part"]
	var hs: Dictionary = hp.get_meta("curve_solid")
	var fs := _faces_of(hs)
	var f: int = (fs["face"] as PackedInt32Array)[int(hit["tri"])]
	var ids := _face_ids(hs, fs, f)
	if ids.is_empty():
		return false
	var was := picked_patch()
	if picked_group() != null and picked_group().is_ancestor_of(hp):
		pass   # (its collection picked, clicked again: down to the face)
	elif picked_solid() == hp and group_of(hp) != null:
		pick_group(group_of(hp))   # (the picked solid clicked again: its whole collection)
		return true
	elif not was.is_empty() and was["part"] == hp and (was["ids"] as Array) == ids and picked_solid() == null:
		pick_solid(hp)   # (the picked patch clicked again: the whole solid)
		return true
	set_meta("group_pick", 0)
	set_meta("solid", 0)
	set_meta("patch", {"part": hp.get_instance_id(), "ids": ids, "seed": hit["at"]})
	set_meta("points", [])
	sel = []
	for id in ids:
		var ci := _curve_index(int(id))
		if ci >= 0:
			sel.append(ci)
	if ed.part != hp:
		ed.select_part(hp)
	_refresh_panel()
	layer.queue_redraw()
	ed._say("Face: %d edges - G / R / S move, turn, scale it; its resolution in the panel (or the menu)." % ids.size())
	return true


## The curve ids of the solid picked whole ({} - none): not drawn, not picked.
func _solid_curve_ids() -> Dictionary:
	var out := {}
	var ps := picked_solid()
	if ps != null:
		for id in (ps.get_meta("curve_solid") as Dictionary).get("ids", []):
			out[int(id)] = true
	# (and a hidden solid's - its eye shut, a weapon hidden: its edges neither drawn nor picked)
	if ed and ed.model:
		for p: MeshInstance3D in ed.parts():
			if p.has_meta("curve_solid") and not p.is_visible_in_tree():
				for id in spec_ids(p.get_meta("curve_solid")):
					out[int(id)] = true
	return out


## Solid or collection `n` made selectable or not (a collection: everything in it). One undo step.
func set_selectable(n: Node, on: bool) -> void:
	var put := func(v: bool):
		if v:
			n.remove_meta("no_select")
		else:
			n.set_meta("no_select", true)
		var t = _w("tree")
		if t:
			(t as Node).set_meta("sig", 0)
		_refresh_panel()
		layer.queue_redraw()
	ed._do("Selectable" if on else "Not selectable", put.bind(on), put.bind(not on))
	ed._say("%s: %s." % [n.name, "selectable again" if on else "can't be picked or let go now (its arrow in the overview)"])


## Whether `n` (a solid) can't be picked or let go - it, or a collection it's in, made not selectable.
func locked(n: Node) -> bool:
	var q := n
	while q != null and ed != null and q != ed.model:
		if q.has_meta("no_select"):
			return true
		q = q.get_parent()
	return false


## The solid under `at` that can't be picked (the nearest one hit, if it's not selectable) - null: none.
func _locked_hit(at: Vector2) -> MeshInstance3D:
	if ed == null or ed.model == null or _locked_ids().is_empty() and not ed.parts().any(func(q): return locked(q)):
		return null
	var r: Array = ed.view.ray(at)
	var best: MeshInstance3D = null
	var bd := INF
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree() or p.mesh == null:
			continue
		var tm: TriangleMesh = p.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var inv := p.global_transform.affine_inverse()
		var hit := tm.intersect_ray(inv * (r[0] as Vector3), (inv.basis * (r[1] as Vector3)).normalized())
		if hit.is_empty():
			continue
		var d: float = (p.global_transform * (hit["position"] as Vector3)).distance_to(r[0])
		if d < bd:
			bd = d
			best = p
	return best if best != null and locked(best) else null


## The edges of solids that can't be picked: {id: true}.
func _locked_ids() -> Dictionary:
	var out := {}
	if ed == null or ed.model == null:
		return out
	for p: MeshInstance3D in ed.parts():
		if p.has_meta("curve_solid") and locked(p):
			for id in spec_ids(p.get_meta("curve_solid")):
				out[int(id)] = true
	return out


## The picked edges that stay picked whatever's clicked: those of solids that can't be let go.
func _kept_sel() -> Array:
	var lk := _locked_ids()
	if lk.is_empty():
		return []
	return sel.filter(func(i): return i < curves.size() and lk.has(int(curves[i].get("id", -1))))


## The collection picked whole (its row in the overview, or a picked solid clicked again) - null: none.
func picked_group() -> Node3D:
	var g = instance_from_id(int(get_meta("group_pick", 0))) if int(get_meta("group_pick", 0)) != 0 else null
	if g is Node3D and is_instance_valid(g) and (g as Node).is_inside_tree() and is_group(g):
		return g
	return null


## Collection `g` picked whole: all its solids selected (outlined), moved as one - drag any of them in
## the view, or G / R / S.
func pick_group(g: Node3D) -> void:
	sel = []
	set_meta("points", [])
	set_meta("patch", {})
	set_meta("solid", 0)
	set_meta("group_pick", g.get_instance_id())
	var ps := group_parts(g)
	if not ps.is_empty():
		ed.select_parts(ps)   # (all at once: the panels filled once)
	_refresh_panel()
	_sync_pick_overlay()
	layer.queue_redraw()
	ed.view.request()
	ed._say("Collection %s: %d solids - drag any of them to move it whole (G / R / S too); click again for a face." % [g.name, ps.size()])


## (dragging a collection) the line chunks made only of its edges moved with it as they are - a move of the
## whole player was every edge sampled again, ~400 ms a frame; the rest left. Made again where they are
## once it's let go (a few a frame).
func _coll_lines(mi: MeshInstance3D) -> void:
	var g: Node3D = _drag["coll"]
	if not _drag.has("coll_chunks"):
		var ids := {}
		for p in group_parts(g):
			for id in spec_ids((p as Node).get_meta("curve_solid", {})):
				ids[int(id)] = true
		var parts := mi.get_children()
		var inside := []
		for k in parts.size():
			var all_in := true
			for i in range(k * LINE_CHUNK, mini((k + 1) * LINE_CHUNK, curves.size())):
				if not curves[i].get("hidden", false) and not ids.has(int(curves[i].get("id", -1))):
					all_in = false
					break
			if all_in:
				inside.append([parts[k], (parts[k] as Node3D).transform])
		var pg: Transform3D = g.get_parent().global_transform if g.get_parent() is Node3D else Transform3D()
		_drag["coll_chunks"] = inside
		_drag["coll_g0"] = pg * (_drag["orig"] as Transform3D)
	var d: Transform3D = g.global_transform * (_drag["coll_g0"] as Transform3D).affine_inverse()   # (the move, in the world)
	var m := mi.global_transform
	var local := m.affine_inverse() * d * m
	for e in _drag["coll_chunks"]:
		var cm = e[0]
		if is_instance_valid(cm):
			(cm as Node3D).transform = local * (e[1] as Transform3D)


## (dragging a picked collection) the collection moved with the mouse - along an axis or on the plane facing
## you, as an edge's drag (X / Y / Z, Ctrl: grid steps).
func _coll_to(at: Vector2, stepped: bool) -> void:
	var d := _drag_delta(at, stepped)
	if d == Vector3.INF:
		return
	_drag["moved"] = true
	_drag["delta"] = d
	var g: Node3D = _drag["coll"]
	var o: Transform3D = _drag["orig"]
	var pb: Basis = g.get_parent().global_transform.basis if g.get_parent() is Node3D else Basis()
	g.transform = Transform3D(o.basis, o.origin + pb.inverse() * (_mx().basis * d))
	layer.queue_redraw()
	ed.view.request()


## The part (any mesh) under `at` - null: none.
func _part_hit(at: Vector2) -> Node3D:
	return ed._pick_part(at)


## The baked solid picked whole (a patch of it clicked again) - null: none.
func picked_solid() -> MeshInstance3D:
	var p = instance_from_id(int(get_meta("solid", 0))) if int(get_meta("solid", 0)) != 0 else null
	if p is MeshInstance3D and is_instance_valid(p) and (p as Node).is_inside_tree() and str(((p as MeshInstance3D).get_meta("curve_solid", {}) as Dictionary).get("kind", "")) == "edges":
		return p
	return null


## A part chosen as a whole (clicked in the view's object mode, or its row in a parts list): a baked
## solid - picked as the solid alone; anything else (null: several) - the solid pick let go.
func solid_chosen(p: MeshInstance3D) -> void:
	if p != null and str((p.get_meta("curve_solid", {}) as Dictionary).get("kind", "")) == "edges":
		pick_solid(p)
	elif picked_solid() != null:
		set_meta("solid", 0)
		_sync_pick_overlay()
		_refresh_panel()
		layer.queue_redraw()


## Baked solid `p` picked whole: only the solid - its edges and their points hidden (G / R / S move,
## turn, scale it all).
func pick_solid(p: MeshInstance3D) -> void:
	set_meta("patch", {})
	set_meta("points", [])
	set_meta("solid", p.get_instance_id())
	sel = []   # (the solid alone - its edges and their points not picked, not even shown)
	if ed.part != p:
		ed.select_part(p)
	_refresh_panel()
	_sync_pick_overlay()
	layer.queue_redraw()
	ed._say("The whole solid - G / R / S move, turn, scale it; click its face: a face of it.")


## How many times the picked patch has been made finer (0: as baked).
func patch_level() -> int:
	var pa := picked_patch()
	if pa.is_empty():
		return 0
	var n := 0
	for e in (pa["spec"] as Dictionary).get("res_stack", []):
		if (e["ids"] as Array) == pa["ids"]:
			n += 1
	return n


## The picked patch made finer: every quad of it cut in four - each cut a loop running on through the
## quads beyond it (the surface stays quads, no triangles to join the finer part to the rest). Its
## mesh before kept (Coarser puts it back).
func patch_finer() -> bool:
	var pa := picked_patch()
	if pa.is_empty():
		ed._say("Subdivide face: click on a baked solid's face first.")
		return false
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var p: MeshInstance3D = pa["part"]
	var before := _state()
	var spec := _rebase_part(p)
	var fs := _faces_of(spec)
	var vv: PackedVector3Array = fs["v"]
	var tt: PackedInt32Array = fs["t"]
	var v := []
	for q in vv:
		v.append(q)
	var t := []
	for i in range(0, tt.size(), 3):
		t.append([tt[i], tt[i + 1], tt[i + 2]])
	var fv: Array = (spec["fv"] as Array).duplicate(true)
	var seeds := {}
	for ti in pa["tris"]:
		for j in 3:
			var k: String = EN._pk(int(t[ti][j]), int(t[ti][(j + 1) % 3]))
			seeds[k] = true
	var now := {}
	for id in spec["ids"]:
		var cv := curve_by_id(int(id))
		if not cv.is_empty():
			now[int(id)] = cv
	var chains: Array = spec["chains"]
	if not EN._split_bent(v, t, fv, chains, now, EN._feat_now(v, t, fv, chains, now), 180.0, 0.0, seeds):
		ed._say("Subdivide face: nothing to cut there.")
		return false
	var vp := PackedVector3Array()
	for q in v:
		vp.append(q)
	var tp := PackedInt32Array()
	for tr in t:
		tp.append_array(PackedInt32Array(tr))
	var cs: Dictionary = EN.close_seams(vp, tp, fv)
	if not cs.is_empty():
		tp = cs["t"]
		fv = cs["fv"]
	if EN._open_edges(tp) > 0:
		ed._say("Subdivide face: that would leave holes - kept as it was.")
		return false
	var st: Array = (spec.get("res_stack", []) as Array).duplicate(true)
	st.append({"ids": (pa["ids"] as Array).duplicate(), "mesh": (spec["mesh"] as Dictionary).duplicate(true), "fv": (spec["fv"] as Array).duplicate(true),
		"c0": (spec["c0"] as Dictionary).duplicate(true), "chains": (spec["chains"] as Array).duplicate(true)})
	spec["res_stack"] = st
	var flat := []
	for q in vp:
		flat.append_array([q.x, q.y, q.z])
	spec["mesh"] = {"v": flat, "t": Array(tp)}
	spec["fv"] = fv
	spec.erase("oriented")
	spec.erase("paired")
	_set_edges_spec(p, spec)
	_changed("Subdivide face", before)
	return true


## The picked patch back as it was before it was last made finer (its edges' shapes now kept: the
## mesh then bent to them).
func patch_coarser() -> bool:
	var pa := picked_patch()
	if pa.is_empty():
		return false
	var p: MeshInstance3D = pa["part"]
	var spec: Dictionary = (p.get_meta("curve_solid") as Dictionary).duplicate(true)
	var st: Array = spec.get("res_stack", [])
	var at := -1
	for i in st.size():
		if (st[i]["ids"] as Array) == pa["ids"]:
			at = i
	if at < 0:
		ed._say("Unsubdivide face: this face isn't subdivided.")
		return false
	var e: Dictionary = st[at]
	if JSON.stringify((e["chains"] as Array).map(func(ch): return int(ch["id"]))) != JSON.stringify((spec["chains"] as Array).map(func(ch): return int(ch["id"]))):
		ed._say("Unsubdivide face: its edges have been split or joined since - kept as it is.")
		return false
	var before := _state()
	st.remove_at(at)
	spec["res_stack"] = st
	spec["mesh"] = e["mesh"]
	spec["fv"] = e["fv"]
	spec["c0"] = e["c0"]
	spec.erase("orig")
	spec.erase("oriented")
	_set_edges_spec(p, spec)
	_changed("Unsubdivide face", before)   # (settled to the curves as they are now)
	return true


## The patch resolution spin set to `lv`: made finer or coarser till it's there.
func set_patch_level(lv: float) -> void:
	var want := int(lv)
	for guard in 6:
		var now := patch_level()
		if now == want:
			break
		if (patch_finer() if now < want else patch_coarser()) == false:
			break
	_refresh_panel()


func patch_items() -> Array:
	var on := not picked_patch().is_empty()
	return [
		["m_cv_patch_finer", "Subdivide face", "", "The picked face subdivided: each of its quads cut in four - the cuts run on as loops\nthrough the quads beyond (quads kept everywhere), the new points on the surface. More points\nto shape detail with; the layout itself isn't changed (Remesh does that). Unsubdivide face\ntakes it back.", patch_finer, on],
		["m_extrude", "Extrude face", "E", "The picked face pulled out along its normal - the mouse sets how far (or type it; minus:\npushed in) - walls of quads from its old rim to its new one; its edges copied at the new rim and\na straight edge up each corner, so the solid stays made of its edges. Click or Enter: done.", begin_face_extrude, on],
		["m_cv_patch_coarser", "Unsubdivide face", "", "The picked face as it was before it was last subdivided.", patch_coarser, on and patch_level() > 0],
	]


## A vertex of any shown edge under `at` (not only a picked edge's) - [curve, vertex] or [].
func _any_handle(at: Vector2) -> Array:
	var own := owner_xfs()
	var gone := _solid_curve_ids()
	gone.merge(_locked_ids())
	var best := HANDLE_PX
	var got := []
	for i in curves.size():
		if curves[i].get("hidden", false) or gone.has(int(curves[i].get("id", -1))):
			continue
		var k: PackedVector3Array = curves[i]["ctrl"]
		var x := cx(curves[i], own)
		for j in k.size():
			var d := _screen(x * k[j]).distance_to(at)
			if d < best:
				best = d
				got = [i, j]
	return got


## The menu's tools for the picked points.
func points_items() -> Array:
	var pts := picked_points()
	var n := pts.size()
	return [
		["m_cv_pt_separate", "Separate vertices", "Y", "The picked vertices made an edge of their own (a run of them one edge; one vertex: the edge split\nthere) - nothing moves, a baked solid's edge splits with it and each piece still shapes it.", separate_points, n >= 1],
		["m_cv_pt_merge", "Merge vertices", "M", "Two edge ends picked: their edges made one (both ends of one edge: closed) - a baked solid's\nedges joined with them. Other vertices: moved together to their middle.", merge_points, n >= 2],
		["m_cv_pt_extrude", "Extrude vertices", "E", "Each picked vertex pulled out into a new one, moved with the mouse: an open edge grows from its\nend; from any other vertex a new line starts.", extrude_points, n >= 1],
		["m_cv_pt_subdivide", "Subdivide vertices", "", "A new vertex on the edge between each two picked vertices next to each other.", subdivide_points, n >= 2],
		["m_cv_pt_connect", "Connect vertices", "F", "A straight line between the two picked vertices.", connect_points, n == 2],
		["m_cv_pt_delete", "Delete vertices", "X / Delete", "The picked vertices taken out (each edge runs on between its neighbours).", delete_points, n >= 1],
		["m_cv_pt_smooth", "Smooth vertex", "", "The edge runs through the picked vertices in a smooth bend (curved either side of each).", set_points_mode.bind(0), n >= 1],
		["m_cv_pt_sharp", "Sharp vertex", "", "A corner at each picked vertex: the edge runs straight to it and straight on from it.", set_points_mode.bind(1), n >= 1],
		["m_cv_pt_manual", "Manual vertex", "", "The edge's bend into each picked vertex shaped by hand: drag the part of the edge beside it\n(it glows green) - each side, and each edge meeting there, on its own.", set_points_mode.bind(2), n >= 1],
	]


## The picked vertices all made smooth (0), sharp (1) or manual (2) - one undo step.
func set_points_mode(mode: int) -> void:
	var pts := picked_points()
	if pts.is_empty():
		return
	var before := _state()
	var any := false
	for e in pts:
		any = _point_mode_to(int(e[0]), int(e[1]), mode) or any
	if any:
		_changed(["Smooth vertex", "Sharp vertex", "Manual vertex"][mode], before)


## Curve `ci`'s point `j` given mode `mode` (no undo step of its own): the curve a path of points if it
## isn't one; a manual point's tangents as the edge runs there now. True - done.
func _point_mode_to(ci: int, j: int, mode: int) -> bool:
	if ci < 0 or ci >= curves.size():
		return false
	var c: Dictionary = curves[ci]
	var e: Dictionary
	match str(c["kind"]):
		"line", "spline":
			e = c.duplicate(true)
			var sh0 := PackedByteArray()
			sh0.resize((c["ctrl"] as PackedVector3Array).size())
			sh0.fill(1 if str(c["kind"]) == "line" else 0)
			e["kind"] = "path"
			e["sharp"] = sh0
			e.erase("radii")
		"path":
			e = c.duplicate(true)
		_:
			e = as_points(c)
	if e.is_empty() or j >= (e["ctrl"] as PackedVector3Array).size():
		return false
	var k: PackedVector3Array = e["ctrl"]
	var sh: PackedByteArray = e.get("sharp", PackedByteArray())
	sh.resize(k.size())
	if mode == 2:
		var tin: PackedVector3Array = e.get("tin", PackedVector3Array())
		var tout: PackedVector3Array = e.get("tout", PackedVector3Array())
		tin.resize(k.size())
		tout.resize(k.size())
		var closed := bool(e.get("closed", false))
		tin[j] = _path_tangent(k, sh, closed, tin, tout, j, false)
		tout[j] = _path_tangent(k, sh, closed, tin, tout, j, true)
		e["tin"] = tin
		e["tout"] = tout
	sh[j] = mode
	e["sharp"] = sh
	curves[ci] = e
	return true


## Point `j` of curve `c` a corner (a line's every point; a spline's none; a path's as marked).
## A point's mode: 0 smooth, 1 sharp (a corner), 2 shaped by hand (manual).
static func point_mode(c: Dictionary, j: int) -> int:
	if str(c["kind"]) == "path":
		var sh: PackedByteArray = c.get("sharp", PackedByteArray())
		return int(sh[j]) if j < sh.size() else 0
	return 1 if point_sharp(c, j) else 0


## Curve `ci`'s point `j` shaped by hand: the edge's bend into it set by dragging the part of the edge
## beside it - each side on its own (its tangents start as the edge runs there now: nothing moves).
func set_point_manual(ci: int, j: int) -> void:
	if ci < 0 or ci >= curves.size():
		return
	var before := _state()
	var c: Dictionary = curves[ci]
	var e: Dictionary
	match str(c["kind"]):
		"line", "spline":
			e = c.duplicate(true)
			var sh0 := PackedByteArray()
			sh0.resize((c["ctrl"] as PackedVector3Array).size())
			sh0.fill(1 if str(c["kind"]) == "line" else 0)
			e["kind"] = "path"
			e["sharp"] = sh0
			e.erase("radii")
		_:
			e = as_points(c)
	if e.is_empty():
		return
	var k: PackedVector3Array = e["ctrl"]
	if j >= k.size():
		return
	var sh: PackedByteArray = e.get("sharp", PackedByteArray())
	sh.resize(k.size())
	var tin: PackedVector3Array = e.get("tin", PackedVector3Array())
	var tout: PackedVector3Array = e.get("tout", PackedVector3Array())
	tin.resize(k.size())
	tout.resize(k.size())
	var closed := bool(e.get("closed", false))
	tin[j] = _path_tangent(k, sh, closed, tin, tout, j, false)
	tout[j] = _path_tangent(k, sh, closed, tin, tout, j, true)
	sh[j] = 2
	e["sharp"] = sh
	e["tin"] = tin
	e["tout"] = tout
	curves[ci] = e
	_changed("Manual vertex", before)


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
	_changed("Sharp vertex" if sharp else "Smooth vertex", before)


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


## Where the view turns round (world space; INF - nothing picked here): the curve point last pressed
## (while its curve is still picked), else the middle of the picked curves.
func selection_centre() -> Vector3:
	if ed == null or ed.model == null or sel.is_empty():
		return Vector3.INF
	var own := owner_xfs()
	var lh: Array = get_meta("last_handle", [])
	if lh.size() == 2 and int(lh[0]) in sel and int(lh[0]) < curves.size():
		var k: PackedVector3Array = curves[int(lh[0])]["ctrl"]
		if int(lh[1]) < k.size():
			return _mx() * (cx(curves[int(lh[0])], own) * k[int(lh[1])])
	var box := AABB()
	var first := true
	for i in sel:
		if int(i) >= curves.size():
			continue
		var x := cx(curves[int(i)], own)
		for q in sample(curves[int(i)]):
			var w := _mx() * (x * q)
			box = AABB(w, Vector3.ZERO) if first else box.expand(w)
			first = false
	return box.get_center() if not first else Vector3.INF


## A selected curve's control point under `at`: [curve, point] ([] - none).
func pick_handle(at: Vector2) -> Array:
	var own := owner_xfs()
	var lk := _locked_ids()
	for i in sel:
		if lk.has(int(curves[i].get("id", -1))):
			continue
		var k: PackedVector3Array = curves[i]["ctrl"]
		var x := cx(curves[i], own)
		for j in k.size():
			if _screen(x * k[j]).distance_to(at) < HANDLE_PX:
				return [i, j]
	return []


func select(i: int, add := false) -> void:
	if i >= 0 and i < curves.size() and _locked_ids().has(int(curves[i].get("id", -1))):
		return   # (an edge of a solid that can't be picked: left as it is)
	if has_meta("step_pick"):
		remove_meta("step_pick")   # (a tool step no longer the pick: its ghost back to its own colour)
		update_ghosts()
	if not add:
		sel = _kept_sel()
		remove_meta("last_handle")
		set_meta("points", [])
		set_meta("patch", {})
		set_meta("solid", 0)
		set_meta("group_pick", 0)
	if i >= 0:
		if i in sel:
			if add:
				sel.erase(i)
		else:
			sel.append(i)
		_finer_for_edit(_edges_part_of(int(curves[i].get("id", -1))))
	_refresh_panel()
	_sync_pick_overlay()   # (a picked solid's or patch's shading gone at once)
	layer.queue_redraw()


# --- the view's input (the editor asks first) ---------------------------------------------------

## True - the event was the curve tools'.
func view_input(e: InputEvent) -> bool:
	if e is InputEventMouseMotion and has_meta("drag_due"):
		remove_meta("drag_due")   # (a newer move: it's made instead - moves are from the press, not added up)
	_flush_drag_due()
	if layer == null or ed.model == null and tool == "":
		return false
	if has_meta("knife"):
		return _knife_input(e)
	var mm := e as InputEventMouseMotion
	if mm:
		if not op.is_empty():
			_op_motion(mm.position)
			return true
		if _drag.has("tangent"):
			if mm.position.distance_to(_drag["press"]) >= DRAG_DEAD_PX or _drag.get("moved", false):
				_tangent_to(mm.position, mm.ctrl_pressed)
			return true
		if _drag.has("coll"):
			if mm.position.distance_to(_drag["press"]) >= DRAG_DEAD_PX or _drag.get("moved", false):
				_coll_to(mm.position, mm.ctrl_pressed)
			return true
		if _drag.has("step"):
			_step_to(mm.position, mm.ctrl_pressed)
			return true
		if not _drag.is_empty():
			if _drag.has("surface") or _drag.has("baked_curve"):
				if mm.position.distance_to(_drag["press"]) < DRAG_DEAD_PX:
					return true
				_begin_group_drag()
				# (what's picked worked out this frame, the move made next - or at the next event, whichever's
				# first: the two in one frame were ~90 ms on a character)
				set_meta("drag_due", [mm.position, mm.ctrl_pressed, Engine.get_process_frames()])
				return true
			_drag_to(mm.position, mm.ctrl_pressed)
			return true
		if tool == "" and _has_manual():
			# (over the part of an edge beside a manual vertex: it glows green - what a drag would shape)
			var hv := pick_tangent(mm.position)
			if hv != get_meta("tan_hover", []):
				set_meta("tan_hover", hv)
				layer.queue_redraw()
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
	if _drag.has("grab"):
		# (extruded points following the mouse: a click keeps them, a right-click takes them back)
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var g := _drag
			_drag = {}
			ed.view.hint = ""
			_changed(str(g["grab"]), g["before"])
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var g := _drag
			_drag = {}
			ed.view.hint = ""
			_set_state(g["before"])
			set_meta("points", [])
			return true
		return mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and not _drag.is_empty():
		# (a right-click while dragging: the drag called off - everything back as it was when it began)
		cancel_drag()
		return true
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.alt_pressed:
		return false
	if mb.pressed:
		if not ed.xf.is_empty():
			return false
		_settle_finish()   # (the last drag's settling, if it's still being worked out: taken first)
		if mb.double_click:
			var hd := pick_handle(mb.position)
			if (dissolve_point(int(hd[0]), int(hd[1])) if not hd.is_empty() else insert_point(mb.position)):
				_drag = {}
				return true
		var pg := picked_group()
		if pg != null and not mb.shift_pressed and not locked(pg):
			# (its collection picked: pressing on any of its solids - a face, an edge - drags the whole
			# collection; a click picks down to the face)
			var sh0 := _baked_hit(mb.position)
			var hit_p = sh0.get("part") if not sh0.is_empty() else _part_hit(mb.position)
			if hit_p != null and pg.is_ancestor_of(hit_p):
				var at_w: Vector3 = sh0["world"] if not sh0.is_empty() else (hit_p as Node3D).global_position
				_drag = {"coll": pg, "orig": pg.transform, "press": mb.position, "start": _mx().affine_inverse() * at_w, "moved": false}
				return true
		var h := pick_handle(mb.position)
		var own := owner_xfs()
		if not h.is_empty():
			# (Shift+click: picked too - or left out again; a click: picked, and dragged with the other
			# picked points - on its plane as it's placed, the part it belongs to moved or turned too)
			if mb.shift_pressed:
				pick_point(int(h[0]), int(h[1]), true)
				return true
			# (clicked again where it was just picked: the next bigger thing - the point, its curve, a
			# patch it bounds, the point again... - on letting go, unless it was dragged)
			var grow := -1
			if not (point_picked(int(h[0]), int(h[1])) and picked_points().size() > 1):
				var lv := _cycle_level(int(h[0]), int(h[1]))
				grow = 0 if lv < 0 else (lv + 1) % 4
				if grow == 0:
					pick_only_point(int(h[0]), int(h[1]))
			set_meta("last_handle", [int(h[0]), int(h[1])])   # (the view turns round it now)
			var hx := cx(curves[h[0]], own)
			var multi := []
			for pe in picked_points():
				if int(pe[0]) == int(h[0]) and int(pe[1]) == int(h[1]):
					continue
				var ex := cx(curves[int(pe[0])], own)
				multi.append([int(pe[0]), int(pe[1]), ex * (curves[int(pe[0])]["ctrl"][int(pe[1])] as Vector3), ex])
			_drag = {"handle": h, "before": _state(), "x": hx, "own": own, "press": mb.position,
				"start": hx * (curves[h[0]]["ctrl"][h[1]] as Vector3), "moved": false, "multi": multi, "grow": grow}
			return true
		var tg := pick_tangent(mb.position)
		if not tg.is_empty():
			# (the part of an edge beside a manual vertex pressed: dragging it shapes the edge's bend into
			# that vertex - this edge, this side, alone)
			var c_t: Dictionary = curves[int(tg[0])]
			var x_t := cx(c_t, own)
			var kt: PackedVector3Array = c_t["ctrl"]
			var tv: Vector3 = (c_t["tout"] if bool(tg[2]) else c_t["tin"])[int(tg[1])]
			var hl: Vector3 = kt[int(tg[1])] + tv / 3.0 if bool(tg[2]) else kt[int(tg[1])] - tv / 3.0
			_drag = {"tangent": tg, "before": _state(), "press": mb.position, "start": x_t * hl, "x": x_t, "moved": false, "what": "edge's bend at its vertex"}
			layer.queue_redraw()
			return true
		var i := pick(mb.position)
		if i >= 0:
			var grow_c := false
			if mb.shift_pressed:
				select(i, true)
				return true
			var id := int(curves[i].get("id", -1))
			var pa := picked_patch()
			if (not pa.is_empty() and id in (pa["ids"] as Array)) or picked_solid() != null:
				select(i)   # (a patch or the solid picked, one of its edges clicked: just that curve)
			elif sel == [i] and picked_points().is_empty() and pa.is_empty():
				grow_c = true   # (the curve clicked again: the patch beside it, on letting go)
			elif not i in sel or not picked_points().is_empty() or not pa.is_empty():
				select(i)
			set_meta("cycle", {})
			if _any_baked([i]):
				# (a baked solid's edge: a drag moves its points - the faces beside it follow; a click
				# picks on letting go)
				var hb := pick_at(mb.position)
				var at_b: Vector3 = cx(curves[i], own) * (hb["p"] as Vector3) if not hb.is_empty() else cx(curves[i], own) * (curves[i]["ctrl"][0] as Vector3)
				_drag = {"baked_curve": i, "before": _state(), "press": mb.position, "start": at_b, "moved": false, "grow_c": grow_c}
				return true
			var hit := pick_at(mb.position)
			var at3: Vector3 = cx(curves[i], own) * (hit["p"] as Vector3) if not hit.is_empty() else cx(curves[i], own) * (curves[i]["ctrl"][0] as Vector3)
			_drag = {"curve": i, "before": _state(), "press": mb.position, "start": at3, "orig": curves.duplicate(true), "moved": false, "own": own, "grow_c": grow_c}
			return true
		if not mb.shift_pressed:
			var gh := _ghost_hit(mb.position)
			if not gh.is_empty():
				# (a tool step's ghost - a cut's, a join's - under the mouse: that step picked, its solid selected;
				# a drag moves the whole step - its place in the recipe - the solid following)
				pick_step(gh["part"], gh["step"])
				var gp: MeshInstance3D = gh["part"]
				var parent: Array = (gh["step"] as Array).slice(0, -1)
				_drag = {"step": [gp, gh["step"]], "spec0": (gp.get_meta("curve_solid") as Dictionary).duplicate(true), "press": mb.position,
					"start": _mx().affine_inverse() * (gh["world"] as Vector3), "xf0": xf_of(node_at(gp.get_meta("curve_solid"), parent).get("b_xf", [])), "moved": false}
				return true
		if ed.curve_tab_shown() and not mb.shift_pressed:
			var sh := _baked_hit(mb.position)
			if not sh.is_empty():
				# (a baked solid's face pressed: a click picks - its patch, again the solid...; a drag
				# moves what's picked there, picking its patch first if nothing of it is)
				_drag = {"surface": true, "before": _state(), "press": mb.position, "start": _mx().affine_inverse() * (sh["world"] as Vector3), "moved": false}
				return true
		var lk := _locked_hit(mb.position)
		if lk != null:
			# (a click on something that can't be picked: why nothing happens, said)
			var why: Node = lk if lk.has_meta("no_select") else group_of(lk)
			while why != null and not why.has_meta("no_select"):
				why = group_of(why)
			ed._say("%s can't be picked: %s isn't selectable - its arrow in the overview (next to the eye) turns that back on." % [lk.name, why.name if why else lk.name])
		if not mb.shift_pressed and (not sel.is_empty() or not picked_points().is_empty() or not (get_meta("patch", {}) as Dictionary).is_empty() or picked_solid() != null):
			select(-1)   # (a click on nothing: everything let go - a picked solid's or patch's shading too)
		return false
	if _drag.has("step"):
		var ds := _drag
		_drag = {}
		ed.view.hint = ""
		var sp: MeshInstance3D = ds["step"][0]
		if ds.get("moved", false) and is_instance_valid(sp):
			var new_spec: Dictionary = sp.get_meta("curve_solid")
			var apply := func(spec: Dictionary):
				if is_instance_valid(sp):
					sp.set_meta("curve_solid", spec)
					refresh_solids()
					update_ghosts()
					_refresh_panel()
			ed._push("Move %s" % _step_word(sp, ds["step"][1]), apply.bind(ds["spec0"]), apply.bind(new_spec.duplicate(true)))
			ed.dirty = true
		layer.queue_redraw()
		return true
	if _drag.has("coll"):
		var dc := _drag
		_drag = {}
		ed.view.hint = ""
		var g: Node3D = dc["coll"]
		if dc.get("moved", false) and is_instance_valid(g):
			var to := g.transform
			var from: Transform3D = dc["orig"]
			ed._do("Move collection", func(): g.transform = to; ed.view.request(), func(): g.transform = from; ed.view.request())
			ed.dirty = true
		else:
			pick_patch(dc["press"])   # (a click, not a drag: down to the face under it)
		return true
	if not _drag.is_empty():
		var d := _drag
		_drag = {}
		ed.view.hint = ""
		if d.get("moved", false):
			_changed_async("Shape edge at vertex" if d.has("tangent") else ("Move edge vertex" if d.has("handle") else ("Move " + str(d.get("what", "curve")))), d["before"])
		elif d.has("surface"):
			pick_patch(d["press"])
		elif int(d.get("grow", -1)) > 0:
			_grow_selection(d["handle"], int(d["grow"]), d["press"])
		elif d.get("grow_c", false):
			grow_to_patch(int(d.get("curve", d.get("baked_curve", -1))), d["press"])
		return true
	return false


# --- clicking again picks bigger: point -> its curve -> a patch it bounds -> the point ... ----------

## Only point `j` of curve `ci` picked (its curve's points shown, nothing else picked).
func pick_only_point(ci: int, j: int) -> void:
	sel = [ci]
	set_meta("patch", {})
	set_meta("solid", 0)
	set_meta("points", [])
	pick_point(ci, j)
	set_meta("cycle", {"id": int(curves[ci].get("id", -1)), "j": j, "level": 0})


## What's picked now, seen from point `j` of curve `ci` as the last click left it: 0 the point, 1 its
## curve, 2 a patch beside it; -1 - something else (a fresh click starts at the point).
func _cycle_level(ci: int, j: int) -> int:
	var m: Dictionary = get_meta("cycle", {})
	if m.is_empty() or int(m.get("id", -2)) != int(curves[ci].get("id", -1)) or int(m.get("j", -1)) != j:
		return -1
	match int(m.get("level", -1)):
		0:
			return 0 if picked_points() == [[ci, j]] else -1
		1:
			return 1 if sel == [ci] and picked_points().is_empty() and picked_patch().is_empty() else -1
		2:
			var pa := picked_patch()
			return 2 if not pa.is_empty() and int(curves[ci].get("id", -1)) in (pa["ids"] as Array) else -1
		3:
			var ps := picked_solid()
			return 3 if ps != null and ps == _edges_part_of(int(curves[ci].get("id", -1))) else -1
	return -1


## The pick grown to `level` from the point `h` [curve, point] clicked at `at`: its curve (1), a patch
## beside it (2 - none: back to the point).
func _grow_selection(h: Array, level: int, at: Vector2) -> void:
	var ci := int(h[0])
	var j := int(h[1])
	if level == 1:
		sel = [ci]
		set_meta("points", [])
		set_meta("patch", {})
		set_meta("solid", 0)
		set_meta("cycle", {"id": int(curves[ci].get("id", -1)), "j": j, "level": 1})
		ed._say("The edge (click again: a face it bounds).")
	elif level == 2 and grow_to_patch(ci, at):
		set_meta("cycle", {"id": int(curves[ci].get("id", -1)), "j": j, "level": 2})
	elif level == 3 and _edges_part_of(int(curves[ci].get("id", -1))) != null:
		pick_solid(_edges_part_of(int(curves[ci].get("id", -1))))
		set_meta("cycle", {"id": int(curves[ci].get("id", -1)), "j": j, "level": 3})
	else:
		pick_only_point(ci, j)
	_refresh_panel()
	layer.queue_redraw()


## A patch curve `ci` bounds picked - the one under `at` if it's one of them, else the first beside it.
## False - it bounds none (not a baked solid's edge).
func grow_to_patch(ci: int, at: Vector2) -> bool:
	var id := int(curves[ci].get("id", -1))
	var p := _edges_part_of(id)
	if p == null:
		return false
	if pick_patch(at) and id in (picked_patch().get("ids", []) as Array):
		return true
	var spec: Dictionary = p.get_meta("curve_solid")
	var fs := _faces_of(spec)
	var face: PackedInt32Array = fs["face"]
	var seen := {}
	var v: PackedVector3Array = fs["v"]
	var t: PackedInt32Array = fs["t"]
	for ti in face.size():
		var f := face[ti]
		if seen.has(f):
			continue
		seen[f] = true
		var ids := _face_ids(spec, fs, f)
		if id in ids:
			set_meta("patch", {"part": p.get_instance_id(), "ids": ids, "seed": (v[t[ti * 3]] + v[t[ti * 3 + 1]] + v[t[ti * 3 + 2]]) / 3.0})
			set_meta("points", [])
			sel = []
			for pid in ids:
				var k := _curve_index(int(pid))
				if k >= 0:
					sel.append(k)
			_refresh_panel()
			layer.queue_redraw()
			ed._say("A face it bounds (click again: back to the edge).")
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
	var nets := _corner_nets()
	if not nets.has(id):
		return
	for j0 in nets[id]:
		var j := _curve_index(int(j0))
		if j < 0 or j == ci:
			continue
		var k: PackedVector3Array = curves[j]["ctrl"]
		var hit := false
		for m in k.size():
			if k[m].distance_to(was) < 1e-4:
				k[m] = to
				hit = true
		if hit:
			curves[j]["ctrl"] = k


## The curves (indices) of points `group` ([curve, point, ...] each) whose solid moves whole with them -
## every point of every edge of it in the group: no corner of theirs left to carry along.
func _whole_nets(group: Array) -> Dictionary:
	var count := {}
	for e in group:
		count[int(e[0])] = int(count.get(int(e[0]), 0)) + 1
	var nets := _corner_nets()
	var out := {}
	for ci in count:
		var id := int(curves[ci].get("id", -1))
		if not nets.has(id):
			continue
		var whole := true
		for j0 in nets[id]:
			var j := _curve_index(int(j0))
			if j < 0 or int(count.get(j, 0)) < (curves[j]["ctrl"] as PackedVector3Array).size():
				whole = false
				break
		if whole:
			out[ci] = true
	return out


## A drag's first move held over from the frame it began in (drag_due): made now.
func _flush_drag_due() -> void:
	if not has_meta("drag_due"):
		return
	var dd: Array = get_meta("drag_due")
	remove_meta("drag_due")
	if not _drag.is_empty() and _drag.has("group"):
		_drag_to(dd[0], dd[1])


## The solids a drag can change: those of its points' curves (and their twins'), the whole solid of each
## (its corners move along) - {part: true}; a placeholder entry when it's none, so the rest still aren't looked at.
func _drag_solids() -> Dictionary:
	var cis := {}
	for e in _dragged_points():
		cis[int(e[0])] = true
	for e in _drag.get("twins", []):
		cis[int(e[0])] = true
	if not _drag.has("group") and not _drag.has("handle"):
		for i in sel:
			cis[int(i)] = true
	var ids := {}
	var nets := _corner_nets()
	for ci in cis:
		if int(ci) < 0 or int(ci) >= curves.size():
			continue
		var id := int(curves[int(ci)].get("id", -1))
		ids[id] = true
		if nets.has(id):
			for x in nets[id]:
				ids[int(x)] = true
	var out := {}
	for p: MeshInstance3D in ed.parts():
		var sp: Dictionary = p.get_meta("curve_solid", {})
		if sp.is_empty():
			continue
		for id in spec_ids(sp):
			if ids.has(int(id)):
				out[p] = true
				break
	if out.is_empty():
		out[null] = true
	return out


## Each baked solid's curve id -> the ids of its solid's curves (made once a frame: a solid dragged moves
## hundreds of corners, each looked up here, not in every solid and curve).
func _corner_nets() -> Dictionary:
	var fr := Engine.get_process_frames()
	if has_meta("corner_nets") and int(get_meta("corner_nets_at", -1)) == fr and int(get_meta("corner_nets_n", -1)) == curves.size():
		return get_meta("corner_nets")
	var out := {}
	if ed and ed.model:
		for p: MeshInstance3D in ed.parts():
			var spec: Dictionary = p.get_meta("curve_solid", {})
			if str(spec.get("kind", "")) != "edges":
				continue
			var ids := PackedInt64Array()
			for x in spec.get("ids", []):
				ids.append(int(x))
			for x in ids:
				out[x] = ids
	set_meta("corner_nets", out)
	set_meta("corner_nets_at", fr)
	set_meta("corner_nets_n", curves.size())
	return out


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


## What a dragged point can line up with (model space), once a drag - an axis each: {v: its levels
## (PackedFloat64Array), at: a point there each, kind: 0 its own curve's point / 1 a point / 2 a flat
## face square to that axis}. Packed - tens of thousands of them, no dictionary each.
const GUIDE_KINDS := ["own", "point", "face"]


## What the guide levels were made for: the edges' number, newest id, places and which are hidden, and
## the solids' places - when any of these change they're made again.
func _guide_sig() -> int:
	var places := []
	if ed and ed.model:
		var inv := _mx().affine_inverse()
		for p: MeshInstance3D in ed.parts():
			places.append([p.get_instance_id(), inv * p.global_transform, p.mesh.get_instance_id() if p.mesh else 0, p.is_visible_in_tree()])
	return hash([curves, places])   # (the edges as they are - hidden ones too: one native hash)


## Model axis `a`'s guide levels - every edge vertex and flat face square to it: [values (sorted), their
## points, their curves (-1: a face), their vertices] - kept (guide_static) till _guide_sig changes;
## a drag's own points are passed over where they're used.
func _guide_static(a: int) -> Array:
	var gs: Dictionary = get_meta("guide_static", {})
	# (checked once a drag, as it begins - its own moves don't count)
	if not _drag.has("guide_checked"):
		if not _drag.is_empty():
			_drag["guide_checked"] = true
		var sig := _guide_sig()
		if gs.is_empty() or int(gs.get("sig", 0)) != sig:
			gs = {"sig": sig, "axes": [null, null, null]}
			set_meta("guide_static", gs)
	if (gs["axes"] as Array)[a] == null:
		(gs["axes"] as Array)[a] = _guide_axis_make(a)
	return gs["axes"][a]


func _guide_axis_make(a: int) -> Array:
	var vs := PackedFloat64Array()
	var ats := PackedVector3Array()
	var cis := PackedInt32Array()
	var js := PackedInt32Array()
	var own := owner_xfs()
	for ci in curves.size():
		if curves[ci].get("hidden", false):
			continue
		var x := cx(curves[ci], own)
		var k: PackedVector3Array = curves[ci]["ctrl"]
		var circle := str(curves[ci]["kind"]) == "circle"
		for j in k.size():
			if circle and j == 1:
				continue   # (a circle's rim handle: not a point on it worth lining up with)
			var q := x * k[j]
			vs.append(q[a])
			ats.append(q)
			cis.append(ci)
			js.append(j)
	var inv := _mx().affine_inverse()
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree() or p.mesh == null or p.mesh.get_surface_count() == 0:
			continue
		for fe in _face_levels(p, inv * p.global_transform)[2]:
			if int(fe[0]) != a:
				continue
			vs.append(float(fe[1]))
			ats.append(fe[2])
			cis.append(-1)
			js.append(-1)
	var order := PackedVector2Array()
	order.resize(vs.size())
	for i in vs.size():
		order[i] = Vector2(vs[i], i)
	order.sort()
	var sv := PackedFloat64Array()
	var sa := PackedVector3Array()
	var sc := PackedInt32Array()
	var sj := PackedInt32Array()
	sv.resize(vs.size())
	sa.resize(vs.size())
	sc.resize(vs.size())
	sj.resize(vs.size())
	for i in order.size():
		var o := int(order[i].y)
		sv[i] = vs[o]
		sa[i] = ats[o]
		sc[i] = cis[o]
		sj[i] = js[o]
	return [sv, sa, sc, sj]


## The curves (indices) this drag moves whole - no guide from them ({curve: true}).
func _guide_moving() -> Dictionary:
	if _drag.has("guide_moving"):
		return _drag["guide_moving"]
	var moving := {}
	if not _drag.has("handle"):
		for i in sel:
			moving[int(i)] = true
	for e in _drag.get("group", []):
		moving[int(e[0])] = true
	_drag["guide_moving"] = moving
	return moving


## (nothing being dragged) The guide levels made ahead, an axis a frame, when the edges changed.
func _warm_guides() -> void:
	if not _drag.is_empty() or not op.is_empty() or curves.is_empty():
		return
	var gs: Dictionary = get_meta("guide_static", {})
	var sig := _guide_sig()
	if gs.is_empty() or int(gs.get("sig", 0)) != sig:
		gs = {"sig": sig, "axes": [null, null, null]}
		set_meta("guide_static", gs)
	for a in 3:
		if (gs["axes"] as Array)[a] == null:
			(gs["axes"] as Array)[a] = _guide_axis_make(a)
			return


## Part `p`'s flat faces square to an axis, `rel` its place in the model: [mesh, rel, [[axis, level,
## middle]...]] - kept till its mesh or place changes (worked out over every triangle of ninety solids at
## each drag's start was its first frame's 80 ms; made ahead while nothing's going on: _warm_face_levels).
func _face_levels(p: MeshInstance3D, rel: Transform3D) -> Array:
	var fc: Array = p.get_meta("face_levels", [])
	if fc.size() == 3 and fc[0] == p.mesh and fc[1] == rel:
		return fc
	var levels := {}
	for si in p.mesh.get_surface_count():
		var arr := p.mesh.surface_get_arrays(si)
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(pv.size()))
		for t in range(0, ix.size(), 3):
			var a3 := rel * pv[ix[t]]
			var b3 := rel * pv[ix[t + 1]]
			var c3 := rel * pv[ix[t + 2]]
			var cr := (b3 - a3).cross(c3 - a3)
			var ar := cr.length()
			if ar < 1e-10:
				continue
			var n := cr / ar
			for ax in 3:
				if absf(n[ax]) > 0.9995:
					var lk := "%d:%.4f" % [ax, a3[ax]]
					var le: Array = levels.get(lk, [ax, a3[ax], 0.0, Vector3.ZERO])
					le[2] = float(le[2]) + ar
					le[3] = (le[3] as Vector3) + (a3 + b3 + c3) / 3.0 * ar
					levels[lk] = le
	var flist := []
	for lk in levels:
		var le: Array = levels[lk]
		if float(le[2]) > 1e-6:
			flist.append([int(le[0]), float(le[1]), (le[3] as Vector3) / float(le[2])])
	fc = [p.mesh, rel, flist]
	p.set_meta("face_levels", fc)
	return fc


## One solid's guide levels worked out ahead, a frame at a time while nothing's dragged (a drag's first
## frame then finds them ready).
func _warm_face_levels() -> bool:
	if ed == null or ed.model == null or not _drag.is_empty() or not op.is_empty():
		return false
	var t0 := Time.get_ticks_usec()
	var inv := _mx().affine_inverse()
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree() or p.mesh == null or p.mesh.get_surface_count() == 0:
			continue
		var fc: Array = p.get_meta("face_levels", [])
		var rel := inv * p.global_transform
		if fc.size() == 3 and fc[0] == p.mesh and fc[1] == rel:
			continue
		_face_levels(p, rel)
		if Time.get_ticks_usec() - t0 > 3000:
			set_meta("face_levels_done", false)
			return false
	set_meta("face_levels_done", true)
	return true   # (all ready)


func _warm_face_levels_done() -> bool:
	return bool(get_meta("face_levels_done", true))


## Point `p` (model space) lined up with the guides along the axes it's free to move on: snapped to the
## nearest level within GUIDE_PX on screen (its own curve's points first); _drag["guides"]: those used.
func _apply_guides(p: Vector3) -> Vector3:
	_drag["guides"] = []
	if not guides_on() or Input.is_key_pressed(KEY_ALT):
		return p
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
		# (every vertex's and flat face's level along this axis, sorted, kept till the edges change - made
		# ahead while nothing's going on; this drag's own moving points passed over here)
		var ax: Array = _guide_static(a)
		var vs: PackedFloat64Array = ax[0]
		var cis: PackedInt32Array = ax[2]
		var js: PackedInt32Array = ax[3]
		var mv := _guide_moving()
		var mine: Array = _drag.get("handle", [-1, -1])
		var from := vs.bsearch(p[a] - tol)
		var upto := vs.bsearch(p[a] + tol, false)
		for gi in range(from, upto):
			var gci := cis[gi]
			if gci >= 0 and (mv.has(gci) or (gci == int(mine[0]) and js[gi] == int(mine[1]))):
				continue
			var g := {"k": a, "v": vs[gi], "at": (ax[1] as PackedVector3Array)[gi], "kind": GUIDE_KINDS[2 if gci < 0 else (0 if gci == int(mine[0]) else 1)]}
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
	if _sym_on() and not _drag.has("twins"):
		_drag["twins"] = _find_twins(_dragged_points())   # (found once, where they started)
	if not _drag.has("solids_only") or (_drag.has("twins") and not _drag.has("solids_twins")):
		_drag["solids_only"] = _drag_solids()   # (with the twins' solids, once they're known)
		if _drag.has("twins"):
			_drag["solids_twins"] = true
		_drag.erase("line_cis")
	if _drag.has("group"):
		var moved := []
		for e in _drag["group"]:
			var km: PackedVector3Array = curves[int(e[0])]["ctrl"]
			var wm := km[int(e[1])]
			km[int(e[1])] = (e[3] as Transform3D).affine_inverse() * ((e[2] as Vector3) + d)
			curves[int(e[0])]["ctrl"] = km
			moved.append([int(e[0]), wm, km[int(e[1])]])
		if not _drag.has("corner_skip"):
			_drag["corner_skip"] = _whole_nets(_drag["group"])
		var skip: Dictionary = _drag["corner_skip"]
		for m in moved:
			if not skip.has(int(m[0])):
				_move_corner(int(m[0]), m[1], m[2])
	elif _drag.has("handle"):
		var h: Array = _drag["handle"]
		var p: Vector3 = (_drag["start"] as Vector3) + d
		var k: PackedVector3Array = curves[h[0]]["ctrl"]
		var was := k[h[1]]
		k[h[1]] = (_drag.get("x", Transform3D()) as Transform3D).affine_inverse() * p
		curves[h[0]]["ctrl"] = k
		_move_corner(h[0], was, k[h[1]])
		for e in _drag.get("multi", []):
			# (the other picked points: the same move)
			var km: PackedVector3Array = curves[int(e[0])]["ctrl"]
			var wm := km[int(e[1])]
			km[int(e[1])] = (e[3] as Transform3D).affine_inverse() * ((e[2] as Vector3) + d)
			curves[int(e[0])]["ctrl"] = km
			_move_corner(int(e[0]), wm, km[int(e[1])])
	else:
		for i in sel:
			var k: PackedVector3Array = (_drag["orig"][i]["ctrl"] as PackedVector3Array).duplicate()
			var dl: Vector3 = cx(curves[i], _drag.get("own", {})).basis.inverse() * d   # (the move in the curve's own space)
			for j in k.size():
				k[j] += dl
			curves[i]["ctrl"] = k
	if _drag.has("twins"):
		_move_twins(_drag["twins"])
	refresh_solids()   # (the solids made of them follow as they're dragged)
	layer.queue_redraw()


# --- manual vertices: an edge's bend into a vertex shaped by hand ----------------------------------

## Whether any edge has a manual vertex (the hover check is skipped otherwise).
func _has_manual() -> bool:
	for c in curves:
		if str(c.get("kind", "")) == "path" and (c.get("sharp", PackedByteArray()) as PackedByteArray).has(2):
			return true
	return false


## The part of an edge beside a manual vertex under `at` (the half of the span nearest the vertex, within
## PICK_PX on screen): [curve, vertex, leaving it (true) or arriving, the span's points (model space)] -
## [] when none. Several edges meeting at one vertex: the one under the mouse.
func pick_tangent(at: Vector2) -> Array:
	var own := owner_xfs()
	var gone := _solid_curve_ids()
	gone.merge(_locked_ids())
	var best := PICK_PX
	var got := []
	for ci in curves.size():
		var c: Dictionary = curves[ci]
		if str(c.get("kind", "")) != "path" or c.get("hidden", false) or gone.has(int(c.get("id", -1))):
			continue
		var sh: PackedByteArray = c.get("sharp", PackedByteArray())
		if not sh.has(2):
			continue
		var k: PackedVector3Array = c["ctrl"]
		var n := k.size()
		var closed := bool(c.get("closed", false))
		var x := cx(c, own)
		var tin: PackedVector3Array = c.get("tin", PackedVector3Array())
		var tout: PackedVector3Array = c.get("tout", PackedVector3Array())
		for j in mini(n, sh.size()):
			if sh[j] != 2:
				continue
			for leaving in [true, false]:
				var a := j if leaving else j - 1
				if not closed and (a < 0 or a >= n - 1):
					continue
				a = (a + n) % n
				var sp := _path_span(k, sh, closed, tin, tout, a, 16)
				var half := sp.slice(0, 9) if leaving else sp.slice(8)
				for m in half.size() - 1:
					var s0 := _screen(x * half[m])
					var s1 := _screen(x * half[m + 1])
					var d := Geometry2D.get_closest_point_to_segment(at, s0, s1).distance_to(at)
					if d < best:
						best = d
						var model_pts := PackedVector3Array()
						for q in sp:
							model_pts.append(x * q)
						got = [ci, j, leaving, model_pts]
	return got


## (dragging the part of an edge beside a manual vertex) its tangent there set so the edge's handle on
## that side - a third of the way along it - follows the mouse.
func _tangent_to(at: Vector2, stepped: bool) -> void:
	var d := _drag_delta(at, stepped)
	if d == Vector3.INF:
		return
	_drag["moved"] = true
	_drag["delta"] = d
	var tg: Array = _drag["tangent"]
	var ci := int(tg[0])
	var j := int(tg[1])
	var c: Dictionary = curves[ci]
	var x: Transform3D = _drag["x"]
	var hl := x.affine_inverse() * ((_drag["start"] as Vector3) + d)
	var v: Vector3 = (c["ctrl"] as PackedVector3Array)[j]
	var key_ := "tout" if bool(tg[2]) else "tin"
	var tv: PackedVector3Array = (c[key_] as PackedVector3Array).duplicate()
	tv[j] = (hl - v) * 3.0 if bool(tg[2]) else (v - hl) * 3.0
	c[key_] = tv
	curves[ci] = c
	refresh_solids()   # (a solid made of it follows)
	layer.queue_redraw()


## The part of the edge being shaped (or under the mouse, ready to be) glowing green: the span beside the
## manual vertex, and its handle.
func _draw_tangent_glow() -> void:
	var tg: Array = []
	if _drag.has("tangent"):
		var t0: Array = _drag["tangent"]
		var c: Dictionary = curves[int(t0[0])]
		var k: PackedVector3Array = c["ctrl"]
		var n := k.size()
		var a := int(t0[1]) if bool(t0[2]) else (int(t0[1]) - 1 + n) % n
		var x := cx(c, owner_xfs())
		var sp := _path_span(k, c.get("sharp", PackedByteArray()), bool(c.get("closed", false)), c.get("tin", PackedVector3Array()), c.get("tout", PackedVector3Array()), a, 16)
		var mp := PackedVector3Array()
		for q in sp:
			mp.append(x * q)
		tg = [t0[0], t0[1], t0[2], mp]
	elif has_meta("tan_hover"):
		tg = get_meta("tan_hover")
	if tg.is_empty() or int(tg[0]) >= curves.size():
		return
	var pts := PackedVector2Array()
	for q in (tg[3] as PackedVector3Array):
		var s2 := _screen(q)
		if s2.x > -1e5:
			pts.append(s2)
	if pts.size() < 2:
		return
	var live := _drag.has("tangent")
	var green := Color(0.3, 1.0, 0.45)
	layer.draw_polyline(pts, Color(green, 0.22 if live else 0.14), 14.0, true)   # (the glow)
	layer.draw_polyline(pts, Color(green, 0.45 if live else 0.3), 7.0, true)
	layer.draw_polyline(pts, Color(green.lightened(0.4), 1.0 if live else 0.8), 2.5, true)
	# its handle: from the vertex to a third of the way along
	var c2: Dictionary = curves[int(tg[0])]
	var x2 := cx(c2, owner_xfs())
	var v: Vector3 = (c2["ctrl"] as PackedVector3Array)[int(tg[1])]
	var tv: PackedVector3Array = c2.get("tout" if bool(tg[2]) else "tin", PackedVector3Array())
	if int(tg[1]) < tv.size():
		var hpt: Vector3 = v + tv[int(tg[1])] / 3.0 if bool(tg[2]) else v - tv[int(tg[1])] / 3.0
		var sv := _screen(x2 * v)
		var sh2 := _screen(x2 * hpt)
		if sv.x > -1e5 and sh2.x > -1e5:
			layer.draw_line(sv, sh2, Color(green, 0.9), 1.5, true)
			layer.draw_circle(sh2, 5.0, Color(0, 0, 0, 0.6))
			layer.draw_circle(sh2, 3.5, green.lightened(0.5))


# --- the knife: a new edge cut across a solid's surface ---------------------------------------------

const EditMeshK := preload("res://scripts/editor/mesh/edit_mesh.gd")


## After an edit lets go: the faces at the edges it moved laid out again by the topology rules (in the background).
const SETTLE_RELAYOUT := false   # (the user: no remesh after a vertex move - an edit only settles)
## After a cut: the faces either side of it laid out again by the topology rules (in the background).
const KNIFE_RELAYOUT := true


func knife_item() -> Array:
	return ["m_knife", "Knife", "K", "Cuts a new edge across a solid's surface: click points along it (the cut follows the surface\nbetween them; near a vertex or an edge a point snaps onto it - Ctrl: free),\nEnter or right-click to cut, Backspace to take a point back, Esc to stop. The new edge splits the faces it crosses, and shapes the solid like any of its edges.", begin_knife, true]


## The knife started: clicks on a solid now place the cut's points.
func begin_knife() -> void:
	cancel_op()
	set_meta("knife", {"part": null, "clicks": []})
	ed._say("Knife: click points across a solid's surface - Enter or right-click cuts, Backspace takes one back, Esc stops.")
	layer.queue_redraw()


func knife_stop() -> void:
	remove_meta("knife")
	ed._say("")
	layer.queue_redraw()


func knife_back() -> void:
	var kn: Dictionary = get_meta("knife")
	var cl: Array = kn["clicks"]
	if not cl.is_empty():
		cl.pop_back()
	if cl.is_empty():
		kn["part"] = null
	layer.queue_redraw()


## The knife's mouse: a click on the solid places a point (the first picks the solid); moving shows where
## the next would go.
func _knife_input(e: InputEvent) -> bool:
	var kn: Dictionary = get_meta("knife")
	var mm := e as InputEventMouseMotion
	if mm:
		kn["mouse"] = mm.position
		kn["snap"] = _knife_snap(mm.position, kn["part"]) if not mm.ctrl_pressed else {}
		layer.queue_redraw()
		return false   # (the view still turns with the middle button)
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return mb != null and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		knife_cut()
		return true
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.alt_pressed:
		return false
	var hit := _baked_hit(mb.position)
	var sn: Dictionary = _knife_snap(mb.position, kn["part"]) if not mb.ctrl_pressed else {}
	if not sn.is_empty():
		hit = {"part": sn["part"], "world": sn["world"]}   # (on a vertex or an edge: exactly there)
	if hit.is_empty():
		ed._say("Knife: click on a solid's surface.")
		return true
	var p: MeshInstance3D = hit["part"]
	if kn["part"] != null and kn["part"] != p:
		ed._say("Knife: the cut stays on one solid (%s)." % (kn["part"] as Node).name)
		return true
	kn["part"] = p
	var inv := p.global_transform.affine_inverse()
	(kn["clicks"] as Array).append({"pos": inv * (hit["world"] as Vector3), "eye": inv * ed.view.cam.global_position})
	if mb.double_click:
		knife_cut()
	layer.queue_redraw()
	return true


## Where the knife snaps near `at` (Blender's way): a vertex of the solid's edges within SNAP_PX first, else
## the nearest point of one of its edges within SNAP_PX - only ones in sight (not behind the surface).
## {part, world, screen, kind ("vertex" / "edge")} or {} - free. `part`: the knife's solid (null: the one
## under the mouse).
func _knife_snap(at: Vector2, part) -> Dictionary:
	var p = part
	if not (p is MeshInstance3D) or not is_instance_valid(p):
		var h := _baked_hit(at)
		p = h.get("part")
	if not (p is MeshInstance3D) or not is_instance_valid(p):
		return {}
	var mx := _mx()
	var own := owner_xfs()
	var best_v := SNAP_PX
	var best_e := SNAP_PX
	var got_v := {}
	var got_e := {}
	for id in spec_ids((p as Node).get_meta("curve_solid", {})):
		var c := curve_by_id(int(id))
		if c.is_empty() or c.get("hidden", false):
			continue
		var x := mx * cx(c, own)
		if str(c.get("kind", "")) in ["line", "spline", "path"]:
			for q in (c["ctrl"] as PackedVector3Array):
				var w: Vector3 = x * q
				if ed.view.cam.is_position_behind(w):
					continue
				var sp: Vector2 = ed.view.cam.unproject_position(w)
				var d := sp.distance_to(at)
				if d < best_v:
					best_v = d
					got_v = {"part": p, "world": w, "screen": sp, "kind": "vertex"}
		var smp := sample(c)
		if bool(c.get("closed", false)) and smp.size() > 1:
			smp.append(smp[0])
		for i in range(1, smp.size()):
			var a: Vector3 = x * smp[i - 1]
			var b: Vector3 = x * smp[i]
			if ed.view.cam.is_position_behind(a) or ed.view.cam.is_position_behind(b):
				continue
			var sa: Vector2 = ed.view.cam.unproject_position(a)
			var sb: Vector2 = ed.view.cam.unproject_position(b)
			var cp := Geometry2D.get_closest_point_to_segment(at, sa, sb)
			var d := cp.distance_to(at)
			if d < best_e:
				# (the point of the edge nearest the mouse's line of sight - in 3D: a blend made on the screen
				# is off in perspective)
				var ro: Vector3 = ed.view.cam.project_ray_origin(cp)
				var rd: Vector3 = ed.view.cam.project_ray_normal(cp)
				var cl := Geometry3D.get_closest_points_between_segments(ro, ro + rd * 1e5, a, b)
				best_e = d
				got_e = {"part": p, "world": cl[1], "screen": ed.view.cam.unproject_position(cl[1]), "kind": "edge"}
	for g in [got_v, got_e]:
		if g.is_empty():
			continue
		# (in sight: nothing of the solids nearer the camera along its line)
		var hit := _baked_hit(g["screen"])
		var cam: Vector3 = ed.view.cam.global_position
		if hit.is_empty() or (hit["world"] as Vector3).distance_to(cam) >= (g["world"] as Vector3).distance_to(cam) - _snap_slack(g["world"]):
			return g
	return {}


## How far behind the surface a point on it may seem (the mesh between its points is flat - a curved
## edge's point lies a little under or over it): a hundredth of the way to the camera.
func _snap_slack(w: Vector3) -> float:
	return maxf(w.distance_to(ed.view.cam.global_position) * 0.01, 1e-4)


## The cut's path drawn: its points, the lines between them, and on to the mouse.
func _draw_knife() -> void:
	if not has_meta("knife"):
		return
	var kn: Dictionary = get_meta("knife")
	var p = kn["part"]
	var pts := PackedVector2Array()
	if p is MeshInstance3D and is_instance_valid(p):
		var m := _mx().affine_inverse() * (p as MeshInstance3D).global_transform
		for c in kn["clicks"]:
			pts.append(_screen(m * (c["pos"] as Vector3)))
	var sn: Dictionary = kn.get("snap", {})
	if kn.has("mouse"):
		pts.append(sn["screen"] if not sn.is_empty() else kn["mouse"])
	var col := Color(1.0, 0.85, 0.3)
	if not sn.is_empty():
		# (snapped: a square on a vertex, a ring on an edge - as Blender's knife shows it)
		var sp: Vector2 = sn["screen"]
		if str(sn["kind"]) == "vertex":
			layer.draw_rect(Rect2(sp - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.6), false, 4.0)
			layer.draw_rect(Rect2(sp - Vector2(7, 7), Vector2(14, 14)), PICKED_PT_COL, false, 2.0)
		else:
			layer.draw_arc(sp, 8.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0, true)
			layer.draw_arc(sp, 8.0, 0.0, TAU, 24, PICKED_PT_COL, 2.0, true)
	if pts.size() >= 2:
		layer.draw_polyline(pts, Color(0, 0, 0, 0.6), 4.0, true)
		layer.draw_polyline(pts, col, 2.0, true)
	for i in pts.size() - (1 if kn.has("mouse") else 0):
		layer.draw_circle(pts[i], 5.0, Color(0, 0, 0, 0.6))
		layer.draw_circle(pts[i], 3.5, col)


## The cut made: the solid's mesh cut along the path (EditMesh's knife: across each face it crosses, the
## surface followed between the points), the cut a new edge of the solid - its faces split by it, its other
## edges kept as they were. One undo step.
func knife_cut() -> void:
	var kn: Dictionary = get_meta("knife")
	var p = kn["part"]
	var clicks: Array = kn["clicks"]
	if not (p is MeshInstance3D) or not is_instance_valid(p) or clicks.size() < 2:
		ed._say("Knife: place two points or more on a solid (Esc: stop).")
		return
	var before := _state()
	var res := knife_apply_to(p, clicks, false)
	if res.has("error"):
		ed._say("Knife: %s - nothing cut." % res["error"])
		return
	remove_meta("knife")
	# (the cut made this frame; the solid drawn anew the next (its look on a worker), the undo step the
	# frame after - all in one frame was ~90 ms. Anything done meanwhile finishes it first)
	set_meta("knife_due", {"before": before, "stage": 0, "at": Engine.get_process_frames(), "part": p, "edges": res.get("chains", [])})
	ed._say("Knife: a new edge across %s (%d vertices)." % [(p as Node).name, int(res["n"])])


## A knife cut's drawing and undo step, a frame each (`all`: whatever's left, now).
func _knife_step(all := false) -> void:
	if not has_meta("knife_due"):
		return
	var kd: Dictionary = get_meta("knife_due")
	if not all and Engine.get_process_frames() <= int(kd["at"]):
		return
	if int(kd["stage"]) == 0:
		set_meta("look_async", true)   # (the cut solid's new look made on a worker - the view keeps its frame rate)
		refresh_solids()
		remove_meta("look_async")
		kd["stage"] = 1
		kd["at"] = Engine.get_process_frames()
		if not all:
			return
	remove_meta("knife_due")
	set_meta("panel_hold", true)   # (the overview filled the frame after)
	_changed("Knife", kd["before"])
	remove_meta("panel_hold")
	# (the faces either side of the cut laid out again by the topology rules - only those, the rest as it was -
	# in the background, its own undo step)
	if KNIFE_RELAYOUT and kd.has("part") and is_instance_valid(kd["part"]) and not (kd["edges"] as Array).is_empty():
		set_meta("remesh_after", kd["part"])
		set_meta("remesh_after_only", kd["edges"])


## Solid `p` (a baked solid) cut along `clicks` ([{pos, eye}] in its own space): its spec made again -
## its mesh with the cut, its edges remapped to it, the cut a new edge. {n: the new edge's vertices} or
## {error}.
func knife_apply_to(p: MeshInstance3D, clicks: Array, redraw := true) -> Dictionary:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var spec: Dictionary = p.get_meta("curve_solid", {})
	if str(spec.get("kind", "")) != "edges" or not spec.has("mesh"):
		return {"error": "only a solid made of edges can be cut"}
	var flat: Array = spec["mesh"]["v"]
	var v := PackedVector3Array()
	for i in range(0, flat.size(), 3):
		v.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	var t := PackedInt32Array(spec["mesh"]["t"])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = t
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# (each triangle a face of its own: a flat side with points inside it - a finer solid's - isn't one
	# face with points in it, which the knife can't cut)
	EditMeshK._keep_faces(am, [PackedInt32Array(range(t.size() / 3))])
	var em = EditMeshK.from_mesh(am)
	var tm: TriangleMesh = em.triangle_mesh()
	var tol: float = em.aabb().size.length() * 0.002
	# each click: where it is on the surface (a ray from where it was seen), a node of the cut
	var nodes := []
	for c in clicks:
		var eye: Vector3 = c["eye"]
		var pos: Vector3 = c["pos"]
		var dir := (pos - eye).normalized()
		var hit := tm.intersect_ray(eye, dir)
		if hit.is_empty():
			hit = tm.intersect_ray(pos - dir * tol * 10.0, dir)
		if hit.is_empty():
			return {"error": "a point isn't on the solid"}
		nodes.append([em.knife_node(int(hit["face_index"]), hit["position"], -1, tol), eye])
	# (walked over the surface from each point to the next; where it can't be - a gap between a solid's
	# pieces - the cut ends there and a new one starts: each run its own edge)
	var runs := []
	var path := []
	var segs := PackedInt32Array()
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i][0]
		var b: Dictionary = nodes[i + 1][0]
		var eye: Vector3 = nodes[i][1]
		var n := ((a["pos"] as Vector3) - eye).cross((b["pos"] as Vector3) - eye)
		if n.length_squared() < 1e-20:
			n = ((b["pos"] as Vector3) - (a["pos"] as Vector3)).cross(Vector3.UP)
		var w: Dictionary = em.knife_walk(a, b, n, (a["pos"] as Vector3) - eye)
		if w.is_empty():
			if not path.is_empty():
				runs.append([path, segs])
			path = []
			segs = PackedInt32Array()
			# (no surface between them - a gap between pieces: the plane through the eye and both points
			# slices what's between them instead, only the side facing the eye kept - each piece crossed
			# its own cut)
			var d0 := ((a["pos"] as Vector3) - eye).normalized()
			var d1 := ((b["pos"] as Vector3) - eye).normalized()
			var m0 := n.cross(d0)
			var m1 := n.cross(d1)
			var sides := [[eye, m0 if m0.dot(d1) > 0.0 else -m0], [eye, m1 if m1.dot(d0) > 0.0 else -m1]]
			var mid_d: float = ((em.aabb() as AABB).get_center() - eye).length()
			for ch in em.knife_slice(eye, n, sides):
				var cn: Array = ch["nodes"]
				if cn.size() < 2:
					continue
				var avg := Vector3.ZERO
				for x in cn:
					avg += x["pos"]
				avg /= cn.size()
				if (avg - eye).length() <= mid_d:
					runs.append([cn, ch["segs"]])
			continue
		var wn: Array = w["nodes"]
		path += wn if path.is_empty() else wn.slice(1)
		segs.append_array(w["segs"])
	if not path.is_empty():
		runs.append([path, segs])
	# (each run's ends: a cut runs from side to side of the faces it crosses - inside a face, let go)
	var chains := []
	var paths := []
	for r in runs:
		var rp: Array = r[0]
		var i0 := 0
		while i0 < rp.size() and not em._border(rp[i0]):
			i0 += 1
		var i1 := rp.size() - 1
		while i1 > i0 and not em._border(rp[i1]):
			i1 -= 1
		if i1 <= i0:
			continue
		var pts := PackedVector3Array()
		for k in range(i0, i1 + 1):
			var q: Vector3 = rp[k]["pos"]
			if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 1e-7:
				pts.append(q)
		if pts.size() < 2:
			continue
		chains.append({"nodes": rp, "segs": r[1]})
		paths.append(pts)
	if chains.is_empty():
		return {"error": "it can't follow the surface across a face from side to side there" if runs.is_empty() else "the cut doesn't cross a face from side to side"}
	var res: Dictionary = em.knife_apply(chains)
	if not bool(res.get("ok", false)) and chains.size() > 1:
		# (one of the cuts crosses a face it can't split cleanly: the others made without it - each tried
		# on a fresh copy, kept if it cuts)
		var keep := []
		var keep_paths := []
		var why := str(res.get("why", ""))
		for ci2 in chains.size():
			var em2 = EditMeshK.from_mesh(am)
			if bool(em2.knife_apply(keep + [chains[ci2]]).get("ok", false)):
				keep.append(chains[ci2])
				keep_paths.append(paths[ci2])
		if keep.is_empty():
			return {"error": why if why != "" else "the mesh couldn't be cut there"}
		em = EditMeshK.from_mesh(am)
		res = em.knife_apply(keep)
		paths = keep_paths
	if not bool(res.get("ok", false)):
		# (the path runs along the mesh's own edges, point to point: nothing to split - the new edge is
		# made through those points as they are)
		var along := str(res.get("why", "")) == "nothing to cut"
		for ch in chains:
			for x in ch["nodes"]:
				if int(x["k"]) != 0:
					along = false
		if not along:
			return {"error": str(res.get("why", "the mesh couldn't be cut"))}
	var cut: ArrayMesh = em.to_mesh()
	# the cut mesh welded: its points by place, the old ones kept by where they were
	var key_of := {}
	var nv := PackedVector3Array()
	var nt := PackedInt32Array()
	for si in cut.get_surface_count():
		var a2 := cut.surface_get_arrays(si)
		var cv: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
		var cx2: PackedInt32Array = a2[Mesh.ARRAY_INDEX] if a2[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(cv.size()))
		var remap := PackedInt32Array()
		remap.resize(cv.size())
		for i in cv.size():
			var kq: Vector3i = EN.key(cv[i])
			if not key_of.has(kq):
				key_of[kq] = nv.size()
				nv.append(cv[i])
			remap[i] = key_of[kq]
		for ti in range(0, cx2.size(), 3):
			var x0 := remap[cx2[ti]]
			var x1 := remap[cx2[ti + 1]]
			var x2 := remap[cx2[ti + 2]]
			if x0 != x1 and x1 != x2 and x0 != x2:
				nt.append_array(PackedInt32Array([x0, x1, x2]))
	var old_to_new := {}
	for i in v.size():
		var kq: Vector3i = EN.key(v[i])
		if not key_of.has(kq):
			return {"error": "the cut moved the solid's points"}
		old_to_new[i] = key_of[kq]
	var fv := []
	for e in spec.get("fv", []):
		fv.append([int(old_to_new[int(e[0])]), int(e[1]), float(e[2])])
	# the new edges: a curve through each cut, its vertices the cut's points
	var sp: Dictionary = spec.duplicate(true)
	var c0: Dictionary = sp.get("c0", {})
	var made := []
	var n_pts := 0
	for pts: PackedVector3Array in paths:
		var closed := pts.size() > 3 and pts[0].distance_to(pts[pts.size() - 1]) < tol
		if closed:
			pts.remove_at(pts.size() - 1)
		var c := _fresh(EN.chain_curve(pts, closed, {}).duplicate(true))
		c["name"] = "%s cut %d" % [p.name, (sp.get("ids", []) as Array).size() + 1]
		var ci: int = (sp.get("chains", []) as Array).size()
		var ts: PackedFloat32Array = EN.params(pts, c)
		var seen := {}
		for j in pts.size():
			var kq: Vector3i = EN.key(pts[j])
			if not key_of.has(kq) or seen.has(key_of[kq]):
				continue
			seen[key_of[kq]] = true
			fv.append([int(key_of[kq]), ci, ts[j]])
		(sp["chains"] as Array).append({"id": int(c["id"]), "closed": closed})
		(sp["ids"] as Array).append(int(c["id"]))
		c0[str(int(c["id"]))] = to_json([c])[0]
		made.append(c)
		n_pts += pts.size()
	sp["c0"] = c0
	var flat2 := []
	flat2.resize(nv.size() * 3)
	for i in nv.size():
		flat2[i * 3] = nv[i].x
		flat2[i * 3 + 1] = nv[i].y
		flat2[i * 3 + 2] = nv[i].z
	sp["mesh"] = {"v": flat2, "t": Array(nt)}
	sp["fv"] = fv
	sp.erase("orig")
	sp.erase("res_stack")
	sp.erase("faces")
	_edge_bases().erase(int(spec.get("net", 0)))
	sp["net"] = int(Time.get_ticks_usec() % 2000000000)
	curves.append_array(made)
	p.set_meta("curve_solid", sp)
	p.remove_meta("curve_solid_key")
	p.remove_meta("settled_key")
	p.remove_meta("hit_tm")
	if redraw:
		refresh_solids()
	var new_ci := []
	for k in made.size():
		new_ci.append((sp["chains"] as Array).size() - made.size() + k)
	return {"n": n_pts, "id": int(made[0]["id"]), "edges": made.size(), "chains": new_ci}


## The drag going on called off (a right-click while dragging, as Esc does in a transform): what it moved
## put back as it was when it began - a collection to its place, edges and solids to their state - and no
## undo step made.
func cancel_drag() -> void:
	if _drag.is_empty():
		return
	var d := _drag
	_drag = {}
	ed.view.hint = ""
	if d.has("step"):
		var sp0 = d["step"][0]
		if is_instance_valid(sp0):
			(sp0 as Node).set_meta("curve_solid", d["spec0"])
			update_ghosts()
	elif d.has("coll"):
		var g = d["coll"]
		if is_instance_valid(g):
			(g as Node3D).transform = d["orig"]
	elif d.get("moved", false) and d.has("before"):
		# (only the edges it moved put back, only their solids made again - a drag changes no solid's recipe:
		# setting the whole state back remade all ninety of a character's solids)
		var was: Array = d["before"][0]
		var changed := {}
		for c in was:
			var now_c := curve_by_id(int(c.get("id", -1)))
			if now_c.is_empty() or hash(now_c) != hash(c):
				changed[int(c.get("id", -1))] = true
		curves = was.duplicate(true)
		sel = (d["before"][1] as Array).duplicate()
		for p: MeshInstance3D in ed.parts():
			var sp: Dictionary = p.get_meta("curve_solid", {})
			if sp.is_empty():
				continue
			var hit := false
			for id in spec_ids(sp):
				if changed.has(int(id)):
					hit = true
					break
			if not hit:
				continue
			var cache = _edge_bases().get(int(sp.get("net", 0)))
			if cache is Dictionary:
				_drag_job_drop(cache)   # (a drag frame still being worked out: let go)
			p.remove_meta("curve_solid_key")
		set_meta("panel_hold", true)   # (the overview filled the frame after - not with the solid put back)
		_refresh_panel()
		remove_meta("panel_hold")
	refresh_solids()
	layer.queue_redraw()
	ed.view.request()
	ed._say("Drag cancelled.")


# --- symmetry and mirroring -------------------------------------------------------------------

## Whether symmetry's on (the editor's X / Y / Z: a dragged vertex's twin across the model follows).
func _sym_on() -> bool:
	return ed != null and (ed.sym[0] or ed.sym[1] or ed.sym[2])


## The points this drag moves: [[curve, point]...].
func _dragged_points() -> Array:
	var out := []
	if _drag.has("group"):
		for e in _drag["group"]:
			out.append([int(e[0]), int(e[1])])
	elif _drag.has("handle"):
		var h: Array = _drag["handle"]
		out.append([int(h[0]), int(h[1])])
		for e in _drag.get("multi", []):
			out.append([int(e[0]), int(e[1])])
	return out


## The model-space mirror of `q` across each symmetry axis that's on.
func _sym_mirror(q: Vector3) -> Vector3:
	var m := q
	for a in 3:
		if ed.sym[a]:
			m[a] = -m[a]
	return m


## Each dragged point's twin across the symmetry plane - the vertex (of any edge) where its mirror image is,
## within a millimetre or so: [[curve, point, its curve's placement, the dragged one (index into `pts`),
## on the plane]...]. A point on the plane is its own twin: kept on it.
func _find_twins(pts: Array) -> Array:
	var own := owner_xfs()
	var moving := {}
	for e in pts:
		moving[Vector2i(int(e[0]), int(e[1]))] = true
	var tol := 0.002
	var grid := {}   # (every vertex by place, a cell of `tol` - not a search over thousands each)
	for ci in curves.size():
		var x := cx(curves[ci], own)
		var k: PackedVector3Array = curves[ci]["ctrl"]
		for j in k.size():
			var w := x * k[j]
			var cell := Vector3i((w / tol).floor())
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append([ci, j, w])
	var out := []
	for n in pts.size():
		var ci: int = pts[n][0]
		var j: int = pts[n][1]
		var w: Vector3 = cx(curves[ci], own) * (curves[ci]["ctrl"] as PackedVector3Array)[j]
		var m := _sym_mirror(w)
		if m.distance_to(w) < tol:
			out.append([ci, j, cx(curves[ci], own), n, true])
			continue
		var c0 := Vector3i((m / tol).floor())
		var best = null
		var bd := tol
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for e in grid.get(c0 + Vector3i(dx, dy, dz), []):
						if moving.has(Vector2i(int(e[0]), int(e[1]))):
							continue
						var dd: float = (e[2] as Vector3).distance_to(m)
						if dd < bd:
							bd = dd
							best = e
		if best != null:
			out.append([int(best[0]), int(best[1]), cx(curves[int(best[0])], own), n, false])
	return out


## The twins put where their dragged points' mirror images are now (a point on the plane kept on it).
func _move_twins(twins: Array) -> void:
	var pts := _dragged_points()
	var own := owner_xfs()
	for t in twins:
		var src: Array = pts[int(t[3])]
		var sx := cx(curves[int(src[0])], own)
		var w: Vector3 = sx * (curves[int(src[0])]["ctrl"] as PackedVector3Array)[int(src[1])]
		var x: Transform3D = t[2]
		var k: PackedVector3Array = curves[int(t[0])]["ctrl"]
		var was := k[int(t[1])]
		if bool(t[4]):
			for a in 3:
				if ed.sym[a]:
					w[a] = 0.0   # (on the mirror's plane: stays on it)
			k[int(t[1])] = sx.affine_inverse() * w
		else:
			k[int(t[1])] = x.affine_inverse() * _sym_mirror(w)
		curves[int(t[0])]["ctrl"] = k
		_move_corner(int(t[0]), was, k[int(t[1])])


## The symmetry tools for the right-click menu: X / Y / Z on or off, and the picked solids mirrored.
func sym_items() -> Array:
	var out := []
	for a in 3:
		var ax: int = a
		out.append(["m_sym_" + "xyz"[a], "Symmetry %s%s" % ["XYZ"[a], " (on)" if ed.sym[a] else ""], "",
			"Dragging a vertex moves its twin across the model's %s too (the vertex where its mirror image\nis); a vertex on the mirror's plane stays on it." % "XYZ"[a],
			func(): ed.sym[ax] = not ed.sym[ax]; ed._update_ui(), true])
	var targets := _mirror_targets()
	for a in 3:
		var ax: int = a
		out.append(["m_mirror_x", "Mirror solid%s across %s" % ["s" if targets.size() > 1 else "", "XYZ"[a]], "",
			"A copy of the picked solid on the other side of the model's %s - its own edges, mirrored\n(a left arm's copy is a right arm: bone and name too). Edit it as any solid." % "XYZ"[a],
			func(): mirror_solids(ax), not targets.is_empty()])
	return out


## The solids a Mirror would copy: the one picked whole, else the selected ECurve solids.
func _mirror_targets() -> Array:
	if picked_solid() != null:
		return [picked_solid()]
	return ed.selected_parts().filter(func(p): return (p as Node).has_meta("curve_solid"))


## The picked solids mirrored across the model's `axis` plane: each a copy beside it on the other side -
## its edges copied (new ones of its own), placed mirrored; a skinned one's bone and name swapped side
## (" L" / " R"). One undo step.
func mirror_solids(axis := 0) -> void:
	var targets := _mirror_targets()
	if targets.is_empty():
		ed._say("Mirror solid: pick a solid first.")
		return
	var scl := Vector3.ONE
	scl[axis] = -1.0
	var mg: Transform3D = ed.model.global_transform
	var mw := mg * Transform3D(Basis.from_scale(scl)) * mg.affine_inverse()
	var made := []   # [copy, parent, its new curves]
	for p: MeshInstance3D in targets:
		var spec: Dictionary = p.get_meta("curve_solid")
		var idmap := {}
		var new_cs := []
		for id in spec_ids(spec):
			var i := _curve_index(int(id))
			if i < 0:
				continue
			var c: Dictionary = (curves[i] as Dictionary).duplicate(true)
			_fresh(c)
			c["name"] = _side_swap(str(c.get("name", "Edge")))
			idmap[int(id)] = int(c["id"])
			new_cs.append(c)
		var sp := remap_spec(spec, idmap)
		sp["net"] = int(Time.get_ticks_usec() % 2000000000) + made.size()   # (its own edge net: worked out afresh)
		if sp.has("bone_name"):
			sp["bone_name"] = _side_swap(str(sp["bone_name"]))
		if str(sp.get("bone", "")) != "":
			sp["bone"] = "auto"   # (its weights from the bones on its own side when it's saved)
		var d := MeshInstance3D.new()
		d.name = ed._unique(_side_swap(str(p.name)) if _side_swap(str(p.name)) != str(p.name) else str(p.name) + " mirrored")
		d.mesh = p.mesh
		d.material_override = p.material_override
		for si in p.mesh.get_surface_count():
			if p.get_surface_override_material(si):
				d.set_surface_override_material(si, p.get_surface_override_material(si))
		var pg: Transform3D = p.get_parent().global_transform
		d.transform = pg.affine_inverse() * mw * pg * p.transform
		d.set_meta("curve_solid", sp)
		d.set_meta("curve_solid_key", _solid_key(sp))
		if p.has_meta("ecurve_skin"):
			d.set_meta("ecurve_skin", p.get_meta("ecurve_skin"))
		made.append([d, p.get_parent(), new_cs, p.get_index() + 1])
	var add := func():
		for e in made:
			var dn: MeshInstance3D = e[0]
			(e[1] as Node).add_child(dn)
			(e[1] as Node).move_child(dn, mini(int(e[3]), (e[1] as Node).get_child_count() - 1))
			dn.owner = ed.model
			for c in e[2]:
				curves.append(c)
		ed._fill_parts()
		refresh_solids()
		_refresh_panel()
		ed.view.request()
	var remove := func():
		var gone := {}
		for e in made:
			(e[1] as Node).remove_child(e[0])
			for c in e[2]:
				gone[int(c["id"])] = true
		curves = curves.filter(func(c): return not gone.has(int(c.get("id", -1))))
		sel.clear()
		ed._fill_parts()
		refresh_solids()
		_refresh_panel()
		ed.view.request()
	ed._do("Mirror solid", add, remove, made.map(func(e): return e[0]))
	ed._say("%d solid%s mirrored across %s." % [made.size(), "" if made.size() == 1 else "s", "XYZ"[axis]])


## A name with its side swapped: "Fore L Armor" <-> "Fore R Armor", "hand.L" <-> "hand.R", Left <-> Right.
static func _side_swap(n: String) -> String:
	var rx := RegEx.create_from_string("(?<![A-Za-z])([LR])(?![A-Za-z])|Left|Right|left|right")
	var out := ""
	var at := 0
	for m in rx.search_all(n):
		out += n.substr(at, m.get_start() - at)
		var t := m.get_string()
		out += {"L": "R", "R": "L", "Left": "Right", "Right": "Left", "left": "right", "right": "left"}.get(t, t)
		at = m.get_end()
	return out + n.substr(at)


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
			notes.append("%s same as %s" % ["XYZ"[k], "a vertex on this edge" if str(g["kind"]) == "own" else "a vertex"])
	if not notes.is_empty():
		layer.draw_arc(sp, 6.0, 0, TAU, 16, Color(1, 0.92, 0.8), 1.5)
	if txt != "":
		layer.draw_string(f, sp + Vector2(14, -12), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.8))
	for ni in notes.size():
		layer.draw_string(f, sp + Vector2(14, 8 + ni * (fs + 4)), notes[ni], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, AXIS_COLS[int(_drag["guides"][ni]["k"])])


## Keys (the editor asks first). True - taken.
func key(k: InputEventKey) -> bool:
	if has_meta("knife") and k.pressed and not k.echo:
		match k.keycode:
			KEY_ESCAPE:
				knife_stop(); return true
			KEY_ENTER, KEY_KP_ENTER:
				knife_cut(); return true
			KEY_BACKSPACE:
				knife_back(); return true
		return false
	if k.pressed and not k.echo and k.keycode == KEY_K and not k.ctrl_pressed and not k.alt_pressed and op.is_empty() and tool == "":
		begin_knife(); return true
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
	if k.pressed and k.ctrl_pressed and k.keycode == KEY_J and ed.curve_tab_shown() and (sel.size() >= 2 or picked_solid() != null):
		merge_curves_selected()
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
			if not picked_patch().is_empty() and picked_points().is_empty() and not k.shift_pressed:
				begin_face_extrude(); return true
			if not picked_points().is_empty() and not k.shift_pressed:
				extrude_points(); return true
			if not sel.is_empty() and not k.shift_pressed:
				begin_extrude(); return true
		KEY_M:
			if k.alt_pressed and not k.shift_pressed and not curves.is_empty():
				merge_by_distance(); return true
			if picked_points().size() >= 2 and not k.shift_pressed:
				merge_points(); return true
		KEY_Y:
			if not picked_points().is_empty() and not k.shift_pressed:
				separate_points(); return true
		KEY_F:
			if picked_points().size() == 2 and not k.shift_pressed:
				connect_points(); return true
	return _sel_keys(k)


## Keys on the selected curves (any tab): Delete / X, Shift+D, Esc.
func _sel_keys(k: InputEventKey) -> bool:
	if sel.is_empty() or k.ctrl_pressed:
		return false
	match k.keycode:
		KEY_DELETE, KEY_X:
			if not picked_points().is_empty():
				delete_points(); return true
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
		ed._say("%s: select %s first (click an edge in the view; Shift+click: more)." % [what, "an edge" if n == 1 else "%d edges" % n])
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
	_changed("Delete edges", before)


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
	_changed("Duplicate edges", before)


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
		var ms := Vector3.ONE
		ms[axis] = -1.0
		_xf_tangents(c, Basis.from_scale(ms))
		if copy:
			curves.append(_fresh(c))
			made.append(curves.size() - 1)
		else:
			curves[i] = c
	if copy:
		sel = made
	_changed("Mirror edges", before)


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
	_changed("Reverse edges", before)


func toggle_closed() -> void:
	if not _need(1, "Close / open"):
		return
	var before := _state()
	for i in sel:
		var c: Dictionary = curves[i]
		if str(c["kind"]) in ["line", "spline", "path"] and (c["ctrl"] as PackedVector3Array).size() >= 3:
			c["closed"] = not c.get("closed", false)
	_changed("Close / open edges", before)


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
	_changed("Join edges", before)


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
	var what: String = {"union": "Union edges", "subtract": "Subtract edges", "intersect": "Intersect edges"}[op]
	if not _need(2, what):
		return
	var own := owner_xfs()
	var cs := []
	for i in sel:
		if not curves[i].get("closed", false):
			ed._say("%s: closed edges only (%s is open)." % [what, curves[i].get("name", "an edge")])
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
			edge.append(str(c.get("name", "an edge")))
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
	ed._say("%s: %d edge%s made on the first picked edge's plane (holes among them: extrude or fill them all together).%s" % [what, out.size(), "" if out.size() == 1 else "s", note])


## The picked closed curves with many points (a boolean's result from before, a dense outline) made
## lean: their corners and straight sides kept, a point every ~40° along their bends (a path). Their
## ids stay: the solids made from them follow. One undo step.
func simplify_selected() -> void:
	if not _need(1, "Simplify edge"):
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
		for k in ["radii", "tin", "tout"]:
			c.erase(k)
		_reparam_holding(int(c.get("id", -1)))   # (a baked solid's edge: its mesh kept, its edge points placed along it anew)
		done += 1
	if done == 0:
		ed._say("Simplify edge: pick closed lines or paths with more vertices than they need.")
		return
	_changed("Simplify edge", before)
	ed._say("Simplified %d edge%s: %d vertices -> %d." % [done, "" if done == 1 else "s", was, now_n])


## `c` (a closed line or path with many points) as a lean line or path ({} - nothing to gain): its vertices
## that matter kept (in 3D - a rim round a curved solid isn't flat), the corners sharp, the bends smooth;
## checked against the edge as it was and made finer till it keeps its shape within half a percent of its size.
static func simplified(c: Dictionary) -> Dictionary:
	if not c.get("closed", false) or not str(c["kind"]) in ["line", "path"] or (c["ctrl"] as PackedVector3Array).size() < 7:
		return {}
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var k: PackedVector3Array = c["ctrl"]
	var n := k.size()
	var orig := sample(c)
	var box := AABB(k[0], Vector3.ZERO)
	for q in k:
		box = box.expand(q)
	var size := maxf(box.size.length(), 1e-6)
	# (split at the vertex farthest from the first: two runs, each made lean on its own)
	var far := 0
	for i in n:
		if k[i].distance_to(k[0]) > k[far].distance_to(k[0]):
			far = i
	var loop := k.duplicate()
	loop.append(k[0])
	var tol := size * 0.06   # (loose first - a smooth path through few vertices follows a bend chords can't - then finer till it fits)
	for attempt in 9:
		var keep := PackedByteArray()
		keep.resize(loop.size())
		keep[0] = 1
		keep[far] = 1
		keep[loop.size() - 1] = 1
		EN._dp(loop, 0, far, tol, keep)
		EN._dp(loop, far, loop.size() - 1, tol, keep)
		var idx := []
		for i in n:
			if keep[i] == 1:
				idx.append(i)
		if idx.size() < 3 or idx.size() >= n:
			return {}
		var pts := PackedVector3Array()
		var sh := PackedByteArray()
		var any_smooth := false
		for i in idx:
			pts.append(k[i])
			# (a corner of the edge as it was - a turn over 40 degrees at that vertex: kept sharp)
			var d0 := (k[i] - k[(i - 1 + n) % n]).normalized()
			var d1 := (k[(i + 1) % n] - k[i]).normalized()
			var corner := d0.angle_to(d1) > deg_to_rad(40.0)
			sh.append(1 if corner else 0)
			any_smooth = any_smooth or not corner
		var e := {"kind": "path" if any_smooth else "line", "ctrl": pts, "closed": true}
		if any_smooth:
			e["sharp"] = sh
		# (its shape checked: every point of the edge as it was near the new one)
		var s := sample(e)
		s.append(s[0])
		var worst := 0.0
		for q in orig:
			var best := INF
			for j in range(1, s.size()):
				best = minf(best, Geometry3D.get_closest_point_to_segment(q, s[j - 1], s[j]).distance_to(q))
			worst = maxf(worst, best)
		if worst <= size * 0.005:
			return e
		tol *= 0.5
	return {}


## A baked solid holding the curve with id `id` (its points just changed in number and place - simplified):
## its mesh kept as it is, its edge points on that curve placed along it anew (by where they are), the
## curves as they are now its start.
func _reparam_holding(id: int) -> void:
	var p := _edges_part_of(id)
	if p == null:
		return
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var spec := _rebase_part(p)
	var chs: Array = spec.get("chains", [])
	var ci := -1
	for j in chs.size():
		if int(chs[j].get("id", -1)) == id:
			ci = j
	var cv := curve_by_id(id)
	if ci < 0 or cv.is_empty():
		_set_edges_spec(p, spec)
		return
	var flat: Array = spec["mesh"]["v"]
	var fv: Array = (spec.get("fv", []) as Array).duplicate(true)
	var on := []
	var pts := PackedVector3Array()
	for e in fv:
		if int(e[1]) == ci:
			var vi := int(e[0])
			on.append(e)
			pts.append(Vector3(flat[vi * 3], flat[vi * 3 + 1], flat[vi * 3 + 2]))
	var ts: PackedFloat32Array = EN.params(pts, cv)
	for j in on.size():
		on[j][2] = ts[j]
	spec["fv"] = fv
	_set_edges_spec(p, spec)


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
	var pts := _xf_points()
	if not pts.is_empty():
		# (picked points - or a picked patch's every point: moved, turned or scaled about their middle;
		# a baked solid's edges joined to them follow at the corners they share)
		stop()
		var own0 := owner_xfs()
		var c0 := Vector3.ZERO
		for e in pts:
			c0 += cx(curves[int(e[0])], own0) * (curves[int(e[0])]["ctrl"][int(e[1])] as Vector3)
		c0 /= pts.size()
		op = {"kind": mode, "value": 1.0 if mode == "scale" else 0.0, "start": 0.0, "before": _state(), "pivot": c0,
			"axis": -1, "m0": ed._mouse, "orig": curves.duplicate(true), "own": own0, "centre": c0, "n": Vector3.UP, "points": pts}
		typed = ""
		_op_update()
		_op_hint()
		return
	if not _need(1, {"move": "Move edges", "turn": "Turn edges", "scale": "Scale edges"}[mode]):
		return
	if _any_baked(sel):
		ed._say("A baked solid's edges are part of it: drag their vertices to reshape it (move the solid to move them).")
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
	if op.has("points"):
		var moved := []
		for e in op["points"]:
			var c: Dictionary = curves[int(e[0])]
			var x := cx(c, own)
			var k: PackedVector3Array = c["ctrl"]
			var was := k[int(e[1])]
			k[int(e[1])] = x.affine_inverse() * (t * (x * was))
			c["ctrl"] = k
			moved.append([int(e[0]), was, k[int(e[1])]])
		for m in moved:
			_move_corner(int(m[0]), m[1], m[2])
		return
	for i in sel:
		var c: Dictionary = curves[i]
		var x := cx(c, own)
		var xi := x.affine_inverse()
		var k: PackedVector3Array = (c["ctrl"] as PackedVector3Array).duplicate()
		for j in k.size():
			k[j] = xi * (t * (x * k[j]))
		c["ctrl"] = k
		_xf_tangents(c, xi.basis * t.basis * x.basis)
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
		ed._say("Add: select a solid made from edges first (and pick the edges to add).")
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
		ed._say("Add: pick the edges to add (edges this solid isn't made from).")
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
	ed._say("%s: %d edge%s added as a %s - its height and role in the recipe." % [p.name, ids.size(), "" if ids.size() == 1 else "s", {"difference": "cut", "union": "join", "intersection": "common part"}[role]])


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
		ed._say("Negative: select a solid made from edges.")
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
		ed._say("Make the cut positive: its edges are gone.")
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
	ed._say("Fillet corners: select a line, rectangle or polygon (edges with corners).")


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
		var what: String = {"move": "Move edges: %.3f m", "turn": "Turn edges: %.1f°", "scale": "Scale edges: x%.3f"}[op["kind"]] % op["value"]
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
	var names := {"face_extrude": "Extrude face: %.3f m (minus: pushed in)", "extrude": "Extrude: %.3f m", "offset": "Offset: %.3f m", "fillet": "Fillet corners: radius %.3f m", "revolve": "Revolve: %.0f°", "pipe": "Pipe: radius %.3f m"}
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
		"extrude", "face_extrude":
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
		"face_extrude":
			_face_extrude_preview(v)
			layer.queue_redraw()
			return
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
	if kind == "face_extrude":
		set_meta("face_op", op)   # (what it pulls out, for the apply - op is cleared first)
	_clear_preview()
	op = {}
	ed.view.hint = ""
	ed.view.queue_redraw()
	match kind:
		"move", "turn", "scale":
			_changed_async({"move": "Move edges", "turn": "Turn edges", "scale": "Scale edges"}[kind], before)
		"offset":
			_set_nid(_nid() + sel.size())
			_changed("Offset edge", before)
		"fillet":
			_changed("Fillet corners", before)
		"face_extrude":
			_face_extrude_apply(v, before)
			remove_meta("face_op")
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


## The mesh recipe `spec` makes of the curves as they are now (null: it can't - a curve gone...). `p`: the
## part it's for (a baked solid inside a boolean is moved with its edges through that part's cache).
func solid_of(spec: Dictionary, p: MeshInstance3D = null) -> ArrayMesh:
	if str(spec.get("kind", "")) == "edges":
		if p == null and ed and ed.model:
			for q: MeshInstance3D in ed.parts():
				if _holds_spec(q.get_meta("curve_solid", {}), int(spec.get("net", 0))):
					p = q
		return edge_solid(p, spec) if p else null
	if str(spec.get("kind", "")) == "bool":
		# (a live boolean: both solids made from their curves, then A op B - B where it was in A)
		var ma := solid_of(spec.get("a", {}), p)
		var mb := solid_of(spec.get("b", {}), p)
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
	var a: Array = m.surface_get_arrays(0)
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
		var a: Array = m.surface_get_arrays(si)
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
## A recipe (a boolean's sides too) holding the baked solid whose net is `net`.
static func _holds_spec(spec: Dictionary, net: int) -> bool:
	if str(spec.get("kind", "")) == "bool":
		return _holds_spec(spec.get("a", {}), net) or _holds_spec(spec.get("b", {}), net)
	return str(spec.get("kind", "")) == "edges" and int(spec.get("net", 0)) == net


func _solid_key(spec: Dictionary) -> String:
	if str(spec.get("kind", "")) == "bool":
		# (a live boolean: each side's own key - a baked side by its brief, not its whole mesh)
		return "bool %s %s %s %s" % [str(spec.get("op", "")), str(spec.get("b_xf", [])), _solid_key(spec.get("a", {})), _solid_key(spec.get("b", {}))]
	if str(spec.get("kind", "")) == "edges":
		# (its edges by a hash of what they are, not written out as text: 91 solids' keys were 120 ms a frame)
		return "edges %d %d %d %d" % [int(spec.get("net", 0)), (spec.get("faces", []) as Array).size(), (spec.get("mesh", {}).get("v", []) as Array).size(), hash(curves_of(spec.get("ids", [])))]
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
	var only: Dictionary = _drag.get("solids_only", {})
	for p: MeshInstance3D in ed.parts():
		if not p.has_meta("curve_solid") or (ed.mode == "edit" and p == ed.part):
			continue
		var spec: Dictionary = p.get_meta("curve_solid")
		if not only.is_empty() and not only.has(p) and str(spec.get("kind", "")) != "bool":
			continue   # (a drag: only the solids its points can change looked at - not ninety keys a frame, twice)
		var key := _solid_key(spec)
		if key == str(p.get_meta("curve_solid_key", "")):
			continue
		# (made again at once, live booleans too - no waiting while a curve's dragged)
		var m := edge_solid(p, spec) if str(spec.get("kind", "")) == "edges" else solid_of(spec, p)
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
		var why := {"loft": "Loft: select two or more edges, in the order to go through.", "sweep": "Sweep: select the profile (a closed edge) first, then the path.",
			"fill": "Fill: select closed edges.", "extrude": "Extrude: select edges (closed ones make solids).", "revolve": "Revolve: select a profile (and a two-vertex line as the axis, if not the model's Y)."}
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
	ed._say("%s made: a new collection (%d triangles)." % [base, m.surface_get_array_index_len(0) / 3])
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
		if not closed:
			# (an end a hair off the axis - a thousandth of the profile's size - put on it: the turn closes there
			# to a point, not a pinhole a boolean can't use as a solid)
			var ext := AABB(s[0], Vector3.ZERO)
			for q in s:
				ext = ext.expand(q)
			var tol := maxf(ext.size.length() * 1e-3, 1e-6)
			for e in [0, s.size() - 1]:
				var off: Vector3 = (s[e] - o) - ax * (s[e] - o).dot(ax)
				if off.length() < tol:
					s[e] -= off
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
		var a: Array = m.surface_get_arrays(0)
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
		for key_ in ["tin", "tout"]:   # (a manual vertex's tangents)
			if c.has(key_):
				var tv := []
				for q in (c[key_] as PackedVector3Array):
					tv.append([q.x, q.y, q.z])
				e[key_] = tv
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
		for key_ in ["tin", "tout"]:
			if e.get(key_) is Array:
				var tv := PackedVector3Array()
				for q in e[key_]:
					tv.append(Vector3(q[0], q[1], q[2]) if q is Array and q.size() >= 3 else Vector3.ZERO)
				c[key_] = tv
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
	ed._say("%s is a plain mesh now: its edges no longer change it." % p.name)
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


func _node_value(v: float, path: Array, pid := 0) -> void:
	if has_meta("recipe_rebuild") or (pid != 0 and (ed.part == null or ed.part.get_instance_id() != pid)):
		return   # (a row of another solid's recipe, going: not this one's)
	set_node(path, "value", v)


func _node_segs(v: float, path: Array, pid := 0) -> void:
	if has_meta("recipe_rebuild") or (pid != 0 and (ed.part == null or ed.part.get_instance_id() != pid)):
		return
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
		ed._say("Separate: its edges are gone.")
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
	set_meta("recipe_rebuild", true)   # (the old rows going: a spin box let go of says its value - not for this solid)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	remove_meta("recipe_rebuild")
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
		var sep: Button = ed._small("Separate", EditorIcons.tip("Separate", "", "This step taken apart: the second solid a positive collection of its own again, where it was."), separate_node.bind(path))
		row.add_child(sep)
		box.add_child(row)
		_recipe_rows(box, node.get("a", {}), path + ["a"], depth + 1)
		_recipe_rows(box, node.get("b", {}), path + ["b"], depth + 1)
		return
	var name := UI.label({"extrude": "Extrusion", "baked": "Baked", "edges": "Baked", "revolve": "Revolve", "pipe": "Pipe", "loft": "Loft", "sweep": "Sweep", "fill": "Fill"}.get(kind, kind.capitalize()), 14, UI.TEXT_DIM)
	name.custom_minimum_size.x = 64
	name.tooltip_text = "A step of this solid made from %d edge%s." % [(node.get("ids", []) as Array).size(), "" if (node.get("ids", []) as Array).size() == 1 else "s"]
	if kind in ["baked", "edges"]:
		name.tooltip_text = "A baked solid: shaped by its %d edges only - pick them (Pick its edges) and reshape them; it follows." % (node.get("ids", []) as Array).size()
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
		sp.value_changed.connect(_node_value.bind(path, ed.part.get_instance_id() if ed.part else 0))
		sp.set_meta("recipe", [key, "value"])
		row.add_child(sp)
	if kind == "revolve":
		var st := SpinBox.new()
		st.min_value = 3
		st.max_value = 256
		st.custom_minimum_size.x = 70
		st.tooltip_text = EditorIcons.tip("Steps round", "", "How many steps the revolve takes for a whole turn.")
		st.value_changed.connect(_node_segs.bind(path, ed.part.get_instance_id() if ed.part else 0))
		st.set_meta("recipe", [key, "segs"])
		row.add_child(st)
	if kind == "extrude":
		var both := CheckBox.new()
		both.text = "Both ways"
		both.focus_mode = Control.FOCUS_NONE
		both.tooltip_text = EditorIcons.tip("Both ways", "", "The extrusion goes half its height each way from its edges' plane.")
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
			cl.tooltip_text = "One of the edges this step is made from."
			cl.mouse_filter = Control.MOUSE_FILTER_STOP
			cr.add_child(cl)
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.add_item("Add")
			ob.add_item("Cut")
			ob.tooltip_text = EditorIcons.tip("Edge role", "", "Add: this edge's outline is part of the solid. Cut: it's taken out of the others (a hole or\na bite) - one clean solid, made again from its edges live. (No roles set: an edge inside\nanother is a hole, as drawn.)")
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
				hs.tooltip_text = EditorIcons.tip("Edge's height", "", "This edge's own extrusion height (minus: the other way) - the step's until you change it.\nA cut edge with its own height: a pocket that deep, or right through.")
				hs.value_changed.connect(_curve_value.bind(path, str(int(id))))
				hs.set_meta("recipe", [key, "per_value:" + str(int(id))])
				hr.add_child(hs)
				var hb := CheckBox.new()
				hb.text = "Both"
				hb.focus_mode = Control.FOCUS_NONE
				hb.tooltip_text = EditorIcons.tip("Edge both ways", "", "This edge extruded half its height each way from its plane.")
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
	name_e.tooltip_text = EditorIcons.tip("Edge name", "Enter", "The picked edge's name.")
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
	_changed("Rename edge", before)


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
		_changed("Edge radius", before)


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
		_changed("Close / open edges", before)


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
	_solid_box.add_child(EditorIcons.tipped(UI.section("RECIPE"), EditorIcons.tip("Recipe", "", "The selected solid: what it's made of (its recipe - every step and edge, editable any time),\nits role, and what you can do with it (pick its edges, bake it, make it a plain mesh).")))
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
	_solid_value.tooltip_text = EditorIcons.tip("The solid's setting", "", "An extrusion's height (minus: the other way), a revolve's angle, a pipe's radius.\nChanged, the solid is made again at once from its edges.")
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
	sb.add_child(ed._small("Pick its edges", EditorIcons.tip("Pick its edges", "", "Picks the edges this solid is made from: drag their vertices and the solid follows."), pick_part_curves))
	sb.add_child(ed._small("Bake", EditorIcons.tip("Bake", "", "Its tools (the solids cut from it, joined to it, in common with it) and its edges worked out\ninto new edges on its surfaces - the outlines they make together, a set for each level. The tools\nand their edges go; reshape the new ones and the solid follows. A tool not touching it stays live."), _bake_btn))
	sb.add_child(ed._small("Make plain mesh", EditorIcons.tip("Make plain mesh", "", "The solid stops following its edges: a plain mesh from now on (editing its mesh, or a\nboolean, does this too). Undo brings the link back."), unlink_part))
	var neg: Button = ed._small("Negative", EditorIcons.tip("Negative", "", "Solids are positive (they add) unless you say so: this one made negative - cut from the solid\nit's in, live (both made from edges: reshape either's edges and the cut follows)."), make_negative)
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
	var pos: Button = ed._small("Make the cut positive", EditorIcons.tip("Make the cut positive", "", "The latest cut in this solid undone as a cut: the cutter is a positive solid of its own again,\nwhere it was (its edges as they are)."), make_positive)
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
	ar.add_child(ed._small("Picked edges", EditorIcons.tip("Add the picked edges", "", "The picked edges made a new step of this solid: extruded both ways from their plane (this solid's\nheight - change it in the recipe), cutting / joined / in common as chosen. Live from then on."), add_tool_curves))
	ar.add_child(ed._small("Other solid", EditorIcons.tip("Add the other selected solid", "", "The other selected solid (Ctrl+click it in the view or the overview) made a new step of this one,\ncutting / joined / in common as chosen. Live when both are made from edges."), add_tool_solid))
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
	box.add_child(EditorIcons.tipped(UI.section("OVERVIEW"), EditorIcons.tip("Overview", "Ctrl / Shift: more", "Every collection, solid (its edges under it), mesh and edge of the model. Click a row to select it -\none or several - and edit it in the boxes below or the view; double-click a name to rename it;\nthe eye hides or shows it; right-click a row for its menu.")))
	var t := Tree.new()
	t.hide_root = true
	t.select_mode = Tree.SELECT_MULTI
	t.columns = 2
	t.set_column_expand(1, false)
	t.set_column_custom_minimum_width(1, 58)
	t.custom_minimum_size.y = 84
	t.add_theme_font_size_override("font_size", 14)
	t.tooltip_text = ""   # (each row its own tooltip - none for the list as a whole)
	t.auto_tooltip = false   # (nor Godot's own - a row's name as its tooltip, over PinTips' one)
	t.set_meta("tip_fn", func(at: Vector2) -> String: return ed.tree_tip(t, at))   # (PinTips: the row's under the mouse - rows keep theirs for it alone)
	t.multi_selected.connect(_tree_selected)
	t.item_collapsed.connect(_tree_folded)
	t.item_edited.connect(_tree_edited.bind(t))
	t.button_clicked.connect(_tree_button)
	t.allow_rmb_select = true
	t.item_mouse_selected.connect(_tree_click.bind(t))
	t.item_activated.connect(_tree_rename_row.bind(t))
	box.add_child(t)
	_panel_btns["w_tree"] = t


func _tree_sig() -> int:
	var sig := hash([sel, _unfolded().keys()])
	if ed == null or ed.model == null:
		return sig
	for g in groups():
		sig = hash([sig, g.get_instance_id(), str(g.name), g.visible])
	var selp := {}
	for q in ed.selected_parts():
		selp[q] = true   # (once - not asked again for each of ninety solids)
	for p: MeshInstance3D in ed.parts():
		sig = hash([sig, p.get_instance_id(), str(p.name), p.visible, p.has_meta("no_select"), _spec_brief(p.get_meta("curve_solid", {})), selp.has(p)])
	for c in curves:
		sig = hash([sig, c.get("id"), c.get("name"), c.get("hidden", false)])
	return sig


## A recipe as the overview sees it: its steps, kinds and curve ids - not a baked solid's mesh, edge
## points or curves as made (thousands of numbers: hashing them on every panel refresh cost ~15 ms).
static func _spec_brief(spec: Dictionary) -> int:
	# (a hash, not text: written out, ninety recipes were 7 ms a refresh)
	var out := []
	for k in spec:
		if k in ["mesh", "fv", "c0", "chains"]:
			continue
		var v = spec[k]
		out.append(k)
		out.append(_spec_brief(v) if v is Dictionary else v)
	return hash(out)


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
	var idx_of := {}
	for i in curves.size():
		idx_of[int(curves[i].get("id", -1))] = i
	set_meta("idx_of", idx_of)
	tree.clear()
	var root := tree.create_item()
	var eye_on := EditorIcons.get_icon("eye")
	var eye_off := EditorIcons.get_icon("eye_off")
	var used := {}
	var selp: Array = ed.selected_parts()
	var groups := {}
	for g in [["solids", "Solids"], ["meshes", "Meshes"], ["curves", "Edges (not in a solid)"]]:
		var gi := tree.create_item(root)
		gi.set_text(0, g[1])
		gi.set_meta("tip_0", {"solids": "The solids in no collection: each with the edges it's made from under it.", "meshes": "The plain meshes in no collection (made by hand, not from edges).",
			"curves": "Edges no solid is made from yet."}[g[0]])   # (PinTips only - never Godot's own beside it)
		gi.set_selectable(0, false)
		gi.set_selectable(1, false)
		gi.set_custom_color(0, UI.TEXT_DIM)
		gi.set_icon(0, EditorIcons.get_icon("m_cv_ol_edge" if g[0] == "curves" else "m_cv_ol_collection"))
		gi.set_icon_modulate(0, Color(1, 1, 1, 0.55))
		groups[g[0]] = gi
	# parts (groups) first: each with its solids and meshes under it
	var gitem := {}
	for g in groups():
		var gi := tree.create_item(root, 0)
		gi.set_text(0, str(g.name))
		gi.set_meta("renamable", true)   # (renamed on a double-click only - a click picks)
		gi.set_metadata(0, {"group": g})
		gi.set_icon(0, EditorIcons.get_icon("m_cv_ol_collection"))
		gi.set_meta("tip_0", EditorIcons.tip(str(g.name), "", "A collection: a group of solids (a collection of the model - as in the Mesh tab). Click: select its solids.\nRight-click: more."))   # (PinTips only - never Godot's own beside it)
		gi.add_button(1, eye_on if g.visible else eye_off, 0, false, "")
		gi.set_meta("btip_%d" % (0), "Hide / show this collection.")
		gi.add_button(1, EditorIcons.get_icon("m_cv_ol_sel_off" if locked(g) else "m_cv_ol_sel"), 1, false, "")
		gi.set_meta("btip_%d" % (1), "Selectable or not: off - nothing in this collection (its solids, their faces, edges, vertices)\ncan be picked or let go.")
		gitem[g] = gi
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		var pg := group_of(p)
		var it := tree.create_item(gitem[pg] if pg and gitem.has(pg) else groups["solids" if not spec.is_empty() else "meshes"])
		it.set_text(0, str(p.name))
		it.set_meta("renamable", true)   # (renamed on a double-click only - a click picks)
		it.set_metadata(0, {"part": p})
		it.set_icon(0, EditorIcons.get_icon("m_cv_ol_solid" if not spec.is_empty() else "m_cv_ol_mesh"))
		var words := _spec_words(spec) if not spec.is_empty() else "a mesh"
		it.set_meta("tip_0", EditorIcons.tip(str(p.name), "", words.left(1).to_upper() + words.substr(1) + ".\nClick: select; double-click: rename."))   # (PinTips only - never Godot's own beside it)
		it.add_button(1, eye_on if p.visible else eye_off, 0, false, "")
		it.set_meta("btip_%d" % (0), "Hide / show this solid.")
		it.add_button(1, EditorIcons.get_icon("m_cv_ol_sel_off" if locked(p) else "m_cv_ol_sel"), 1, false, "")
		it.set_meta("btip_%d" % (1), "Selectable or not: off - neither this solid nor its faces, edges or vertices can be picked\nor let go.")
		if locked(p):
			it.set_custom_color(0, UI.TEXT_DIM)
		if p in selp:
			it.select(0)
		for id in spec_ids(spec):
			used[int(id)] = true
		# (a solid's edges folded away until it's opened - rows made only then: a converted character's
		# thousands of edges don't fill the overview, nor take half a second to list)
		if spec.is_empty():
			pass
		elif _unfolded().has(p.get_instance_id()):
			_tree_steps(tree, it, p, spec, [])
			it.collapsed = false
		else:
			_tree_step_rows(tree, it, p, spec, [])   # (its cuts / joins shown even folded - each a thing of its own)
			var ph := tree.create_item(it)
			ph.set_text(0, "%d edges" % spec_ids(spec).size())
			ph.set_icon(0, EditorIcons.get_icon("m_cv_ol_edge"))
			ph.set_icon_modulate(0, Color(1, 1, 1, 0.55))
			ph.set_custom_color(0, UI.TEXT_DIM)
			ph.set_selectable(0, false)
			ph.set_metadata(0, {"fold": p})
			it.collapsed = true
	for i in curves.size():
		if used.has(int(curves[i].get("id", -1))):
			continue
		var ci := tree.create_item(groups["curves"])
		ci.set_text(0, str(curves[i].get("name", "Curve")))
		ci.set_meta("renamable", true)   # (renamed on a double-click only - a click picks)
		ci.set_metadata(0, {"curve": i})
		ci.set_icon(0, EditorIcons.get_icon("m_cv_ol_edge"))
		ci.set_meta("tip_0", "A %s. Click: pick it (Ctrl / Shift: more)." % str(curves[i]["kind"]))   # (PinTips only - never Godot's own beside it)
		ci.add_button(1, eye_off if curves[i].get("hidden", false) else eye_on, 0, false, "")
		ci.set_meta("btip_%d" % (0), "Hide / show this edge.")
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
	remove_meta("idx_of")


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
		ed._say("New collection: select the solids / meshes to put in it.")
		return null
	var model: Node3D = ed.model
	var g := Node3D.new()
	g.name = ed._unique("Collection")
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
	ed._do("New collection", do_it, undo_it, [g])
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
	ed._do("Move to " + (str(g.name) if g else "no collection"), do_it, undo_it)


## Part `g` and what's in it deleted / duplicated (one undo step).
func delete_group(g: Node3D) -> void:
	var parent := g.get_parent()
	var at := g.get_index()
	ed._do("Delete collection", func():
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
	ed._do("Duplicate collection", func():
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
	ed.select_parts(ps)


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
		add.call(pm, "Auto join its solids", func(): auto_join(g.find_children("*", "MeshInstance3D", true, false)))
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
		add.call(pm, "Bake (its tools into its edges)", _act_part.bind(p, "bake"), can_bake(p))
		add.call(pm, "Auto join (%s)" % ("the selected" if sel_ps.size() >= 2 else "with what meets it"), func(): auto_join(sel_ps if sel_ps.size() >= 2 else [], false, [] if sel_ps.size() >= 2 else [p]))
		add.call(pm, "Remesh (quads along its edges)", func(): remesh_solid(p), str((p.get_meta("curve_solid", {}) as Dictionary).get("kind", "")) == "edges")
		pm.add_separator()
		add.call(pm, "New collection from the selected (%d)" % sel_ps.size(), make_group.bind(sel_ps))
		var sub := PopupMenu.new()
		sub.add_theme_font_size_override("font_size", 14)
		for g in groups():
			if g != group_of(p):
				sub.add_item(str(g.name), acts.size())
				acts.append(move_to_group.bind(sel_ps, g))
		if group_of(p):
			sub.add_item("(no collection - the top)", acts.size())
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
	if it == null or not (it.is_editable(0) or it.has_meta("renamable")):
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


## A row double-clicked in the overview: its name opened for typing (a collection's, a solid's, an edge's).
func _tree_rename_row(t: Tree) -> void:
	var it := t.get_selected()
	if it == null or not it.has_meta("renamable"):
		return
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	for k in ["group", "part"]:
		if m.has(k):
			start_rename({k: m[k]})
			return
	if m.has("curve"):
		start_rename({"curve": m["curve"]} if not m.has("of") else {"curve": m["curve"], "of": m["of"], "leaf": m["leaf"]})


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
		ed._say("Bake: select a solid made from edges.")
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
	ed._say("Baked: one solid, its %d edges%s." % [ids.size(),
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
		ed._say("Bake: select a solid made from edges.")
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
		ed._say("Bake: no curves to make edges of.")
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
	# (the points two edges or more share: kept on every curve that has them - they stay joined)
	var must_keep := {}
	var seen_k := {}
	for ch0: Dictionary in net["chains"]:
		var mine := {}
		for q in (ch0["pts"] as PackedVector3Array):
			var kq: Vector3i = EN.key(q)
			if mine.has(kq):
				continue
			mine[kq] = true
			if seen_k.has(kq):
				must_keep[kq] = true
			seen_k[kq] = true
	for ch: Dictionary in net["chains"]:
		var pts: PackedVector3Array = ch["pts"]
		var c: Dictionary = EN.chain_curve(pts, bool(ch["closed"]), must_keep)
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
	var to_quads := false
	if rm.is_empty() or EN._open_edges(rm["t"]) > 0:
		# (not a solid standing along one axis - or its quads left holes: an even mesh - made grids of quads
		# following its edges below)
		rm = EN.remesh(base, net["chains"], L)
		to_quads = true
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
	var tt: PackedInt32Array = rm["t"]
	var gridded := false
	if to_quads:
		# (the rules for any topology: quads, laid out evenly, following the edges - each face a grid between
		# its edges, mapped onto its surface)
		var gq: Dictionary = EN.grid_any(vv, tt, fv, chains, L * 0.55, false)   # (the quick layout: its facing, folds, holes, grids - the full one follows on a worker, remesh_after)
		if not gq.is_empty():
			vv = gq["v"]
			tt = gq["t"]
			fv = gq["fv"]
			gridded = true
	var thin := 0
	for ti in range(0, tt.size(), 3):
		if _min_angle(vv[tt[ti]], vv[tt[ti + 1]], vv[tt[ti + 2]]) < 15.0:
			thin += 1
	if not gridded and thin > tt.size() / 3 / 20:
		# (no grids possible - a face with a hole...: slivers cleared - points too close merged, the
		# triangles made even inside each face, its shape kept - then they pair into quads)
		var nowc := {}
		for ch in chains:
			nowc[int(ch["id"])] = from_json([c0[str(int(ch["id"]))]])[0]
		var td: Dictionary = EN.tidy_mesh(vv, tt, fv, chains, nowc, L * 0.6 * 0.35)
		var ev: Dictionary = EN.even_faces(vv, td["t"], td["fv"], 8, true)
		vv = ev["v"]
		tt = ev["t"]
		fv = td["fv"]
	var flat := []
	for q in vv:
		flat.append_array([q.x, q.y, q.z])
	for ch in chains:
		ch.erase("pts")
		ch.erase("t")
	var core := {"kind": "edges", "ids": ids, "net": net_id, "chains": chains, "c0": c0, "mesh": {"v": flat, "t": Array(tt)}, "fv": fv}
	if gridded:
		core["dense"] = 3   # (quads: its settles even it out without regridding or turning diagonals)
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
	auto_join([], true, [p])   # (other solids meeting it along an edge: joined to it - a step of its own)
	if gridded:
		set_meta("remesh_after", p)
	ed._say("Baked: one solid, %d edges%s." % [ids.size(), (" - %d solid%s touching it joined in" % [merged.size(), "" if merged.size() == 1 else "s"]) if not merged.is_empty() else ""])
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
## A baked solid as its original bake: the same edges, its mesh, edge points and curves as baked
## (spec "orig") - every edit is bent from this, never from an earlier edit's result (nothing piles up).
func _orig_view(spec: Dictionary) -> Dictionary:
	var o: Dictionary = spec["orig"]
	var v := spec.duplicate()
	v.erase("orig")   # (the bake itself: no bake under it)
	v["mesh"] = o["mesh"]
	v["fv"] = o["fv"]
	v["c0"] = o["c0"]
	v["net"] = -absi(int(spec.get("net", 0))) - 1
	v["view"] = true
	for k in ["tied", "qcaps", "sealed", "oriented", "paired"]:
		v[k] = true
	return v


## Part `p`'s mesh at rest (kept as a drag began) still the one for recipe `spec` - its very mesh lists.
static func _rest_ok(p: MeshInstance3D, spec: Dictionary) -> bool:
	var r: Array = p.get_meta("rest_mesh", [])
	return r.size() == 3 and spec.has("mesh") and is_same(r[1], spec["mesh"]["v"]) and is_same(r[2], spec["mesh"]["t"])


## Its curves are not the ones its settled mesh was made for (a drag going on).
func _edges_moved(spec: Dictionary) -> bool:
	var c0: Dictionary = spec.get("c0", {})
	for id in spec.get("ids", []):
		var cv := curve_by_id(int(id))
		if not cv.is_empty() and c0.has(str(int(id))) and JSON.stringify(to_json([cv])[0]) != JSON.stringify(c0[str(int(id))]):
			return true
	return false


func _edge_mesh(p: MeshInstance3D, spec: Dictionary) -> ArrayMesh:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	if not spec.get("view", false) and not (_drag.is_empty() and op.is_empty()) and p.mesh is ArrayMesh and spec.has("mesh") and not _rest_ok(p, spec):
		p.set_meta("rest_mesh", [p.mesh, spec["mesh"]["v"], spec["mesh"]["t"]])   # (a drag begins: the mesh at rest kept - a cancel puts it back as it is)
	var rigid := _rigid_drag(p, spec)
	if not rigid.is_empty():
		return rigid[0]   # (dragged whole: its settled mesh shifted, nothing solved)
	if spec.has("orig") and _edges_moved(spec):
		return _edge_mesh(p, _orig_view(spec))   # (bent from the bake, not from the last edit's mesh)
	var nid := int(spec.get("net", 0))
	var caches := _edge_bases()
	var c: Dictionary = caches.get(nid, {}) if caches.get(nid) is Dictionary else {}
	if has_meta("settling") and _drag.is_empty() and op.is_empty() and not bool(get_meta("cg_full", false)):
		if c.has("drag_job") or c.get("drag_mesh") is ArrayMesh:
			# (let go, settling on a worker: the last drag frame shown till it lands - not solved here meanwhile)
			return _drag_job_take(c) if c.has("drag_job") else c["drag_mesh"]
		if c.has("bw_job") or not c.has("bw"):
			return null   # (let go before its weights were ready: the settling makes its own - nothing made here meanwhile)
	var mv: Array = spec["mesh"]["v"]
	if c.is_empty() or int(c.get("n", -1)) != mv.size():
		var v := PackedVector3Array()
		for i in range(0, mv.size(), 3):
			v.append(Vector3(mv[i], mv[i + 1], mv[i + 2]))
		var t := PackedInt32Array(spec["mesh"]["t"])
		c = {"n": mv.size(), "v": v, "t": t, "last": PackedVector3Array()}   # (its neighbours made where they're wanted)
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
		var rf: Dictionary = {} if EN._open_edges(tt) > 0 else EN.quad_caps(v0, tt, spec.get("fv", []), feat0, L, Vector3(upa[0], upa[1], upa[2]).normalized() if Vector3(upa[0], upa[1], upa[2]) != Vector3.ZERO else Vector3.ZERO, spec.get("chains", []))
		if not rf.is_empty():
			var csq: Dictionary = EN.close_seams(rf["v"], rf["t"], rf["fv"])
			if EN._open_edges(csq["t"] if not csq.is_empty() else rf["t"]) > 0:
				rf = {}   # (its flat faces' quads would leave holes: kept as they were)
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
	if not spec.get("paired", false):
		# (lone triangles side by side turned into quads where they can be, once - quads all over)
		var fs := _faces_of({"mesh": {"v": spec["mesh"]["v"], "t": Array(c["t"])}, "fv": spec.get("fv", []), "chains": spec.get("chains", [])})
		var pt: PackedInt32Array = EN.pair_quads(v0, c["t"], fs["feat"])
		if pt != (c["t"] as PackedInt32Array):
			c["t"] = pt
			spec["mesh"]["t"] = Array(pt)
			c["nb"] = EN.neighbours(pt, v0.size())
			c.erase("bw")
			c.erase("cg")
			c.erase("r_last")
			if c.has("bw_job"):
				WorkerThreadPool.wait_for_task_completion(int(c["bw_job"][0]))
				c.erase("bw_job")
		spec["paired"] = true
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
	if not (_drag.is_empty() and op.is_empty()) and not bool(get_meta("cg_full", false)) and not c.has("bw") and not c.has("bw_job") and not c.has("look_job"):
		return _cold_drag(spec, c, v0, old)   # (a drag on a solid not edited yet: straight to its weights - its moves not worked out here for nothing)
	if c.has("bw_job") and not WorkerThreadPool.is_task_completed(int(c["bw_job"][0])) and not (_drag.is_empty() and op.is_empty()) and not bool(get_meta("cg_full", false)):
		c["bw_wait"] = true
		set_meta("edge_jobs", true)
		return null   # (a drag before its weights are worked out: the mesh as it is till they are - not waited for)
	if not (_drag.is_empty() and op.is_empty()) and not bool(get_meta("cg_full", false)) and c.has("bw") and c.has("cg") and c.has("edge") \
			and c.has("topo") and int(c.get("topo_n", -1)) == (c["t"] as PackedInt32Array).size() and not c.has("bw_job"):
		# (a drag with everything set up: even its edges' moves worked out on the worker - the frame here
		# only hands it the curves as they are now)
		var nd := {}
		for id in now:
			nd[id] = (now[id] as Dictionary).duplicate(true)
		return _drag_frame(c, {-2: hash(nd), -3: [spec.get("fv", []).duplicate(true), spec.get("chains", []).duplicate(true), old, nd]}, p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null, _patch_for(p, spec, c))
	var moves: Dictionary = EN.edge_moves(spec.get("fv", []), spec.get("chains", []), old, now, v0)
	var still := true
	for vi in moves:
		if (moves[vi] as Vector3).length_squared() > 1e-14:
			still = false
			break
	if still and _drag.is_empty() and op.is_empty() and not bool(get_meta("cg_full", false)) and not spec.get("view", false) and _rest_ok(p, spec):
		# (back where it was - a drag called off: the mesh it had then, not solved and shaded again)
		_drag_job_drop(c)
		c["last"] = PackedVector3Array()
		c["pv"] = v0
		c["t_draw"] = c["t"]
		c.erase("r_last")
		return p.get_meta("rest_mesh")[0]
	if c.has("bw_job") and (WorkerThreadPool.is_task_completed(int(c["bw_job"][0])) or not still):
		# (the weights worked out in the background: taken - waited for if a drag's already begun)
		WorkerThreadPool.wait_for_task_completion(int(c["bw_job"][0]))
		c["bw"] = c["bw_job"][1][0]
		if (c["bw_job"][1] as Array).size() > 1 and c["bw_job"][1][1] != null:
			c["cg"] = c["bw_job"][1][1]
		else:
			c.erase("cg")
		c.erase("bw_job")
		c.erase("bw_wait")
		c.erase("r_last")
	if not c.has("bw"):   # (each face's points, and each inside point's edge points and weights: once)
		var all_edge := {}
		var fvl: Array = spec.get("fv", [])
		for e in fvl:
			all_edge[int(e[0])] = true
		if still and has_meta("look_async") and not c.has("look_job") and not c.has("bw_job") and not bool(get_meta("cg_full", false)) and (c["t"] as PackedInt32Array).size() > LOOK_ASYNC_TRIS * 3 \
				or c.has("look_job"):
			return _look_async(p, spec, c, v0, all_edge, old)
		if not still and not c.has("bw_job") and not (_drag.is_empty() and op.is_empty()) and not bool(get_meta("cg_full", false)):
			return _cold_drag(spec, c, v0, old)
		# (the solid's edges: the mesh's own edges lying along a curve - between two of its points, its
		# middle on the curve too; the faces either side of an edge may each have their own points on it)
		var feat: Dictionary = EN.feature_edges(v0, c["t"], fvl, spec.get("chains", []), old)
		var ax: Array = spec.get("up", [0, 0, 0])
		c["edge"] = all_edge
		if still and not c.has("bw_job"):
			# (just settled - nothing moves yet: drawn as it is, the weights for the next drag worked out
			# on a worker meanwhile - letting go never waits for them)
			var holder := [null, null]
			var vv := v0.duplicate()
			var tt2: PackedInt32Array = (c["t"] as PackedInt32Array).duplicate()
			var up3 := Vector3(ax[0], ax[1], ax[2])
			var job := WorkerThreadPool.add_task(func():
				holder[0] = EN.blend_weights(vv, tt2, all_edge.duplicate(), feat.duplicate(), up3)
				holder[1] = EN.cg_setup(vv, tt2, holder[0]))   # (the solver set up there too - a drag's first frame doesn't)
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
		if (c["bw_job"][1] as Array).size() > 1 and c["bw_job"][1][1] != null:
			c["cg"] = c["bw_job"][1][1]
		else:
			c.erase("cg")
		c.erase("bw_job")
		c.erase("r_last")
	for vi in c["edge"]:
		if not moves.has(vi):
			moves[vi] = Vector3.ZERO   # (an edge point whose curve didn't move: held)
	if not c.has("cg"):
		c["cg"] = EN.cg_setup(v0, c["t"], c["bw"])
	# (solved smooth: a drag goes on from the last frame's solution, a few dozen rounds a frame; settling
	# - the drag let go - all the way)
	var full := bool(get_meta("cg_full", false))
	var mat: Material = p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null
	if not c.has("topo") or int(c.get("topo_n", -1)) != (c["t"] as PackedInt32Array).size():
		c["topo"] = EN.corner_topo(v0.size(), c["t"])
		c["topo_n"] = (c["t"] as PackedInt32Array).size()
	if full or (_drag.is_empty() and op.is_empty()):
		_drag_job_drop(c)   # (not dragging: worked out here and now)
	else:
		# (a drag: solved and shaded on a worker - the view keeps its frame rate; the newest move waits
		# for the one being worked out, the finished one shown as it comes)
		var out: ArrayMesh = null
		if c.has("drag_job"):
			if not WorkerThreadPool.is_task_completed(int(c["drag_job"][0])):
				c["drag_want"] = moves
				set_meta("edge_jobs", true)
				return null
			out = _drag_job_take(c)
		elif c.get("drag_mesh") is ArrayMesh:
			out = c["drag_mesh"]   # (nothing new worked out: the last frame's mesh still stands)
		if c.has("drag_want") or not c.has("drag_done_moves") or c["drag_done_moves"] != moves:
			c.erase("drag_want")
			_drag_job_start(c, moves, mat)
		return out
	var sol: Dictionary = EN.cg_moves(v0.size(), c["cg"], c["bw"], moves, c.get("r_last", PackedVector3Array()), 2000 if full else 8, 1e-6 if full else 1e-4, 6 if full else 1)
	var d: PackedVector3Array = sol["d"]
	c["r_last"] = sol["r"]
	c["last"] = d
	var pv := PackedVector3Array()
	pv.resize(v0.size())
	for i in v0.size():
		pv[i] = v0[i] + d[i]
	var td: PackedInt32Array = c["t"]
	if full:
		# (letting go: no triangle left turned over where an edge pushed in - not every drag frame, it's slow)
		if not c.has("nb"):
			c["nb"] = EN.neighbours(c["t"], v0.size())
		pv = EN.untangle(pv, v0, c["t"], c["nb"], c["edge"])
		td = EN.flip_fix(pv, v0, c["t"], c["bw"]["tri_face"])["t"]
	c["pv"] = pv
	c["t_draw"] = td
	if not c.has("topo") or int(c.get("topo_n", -1)) != td.size() or td != (c["t"] as PackedInt32Array):
		c["topo"] = EN.corner_topo(v0.size(), td)
		c["topo_n"] = td.size()
	# (smooth across curves, sharp at every real edge)
	return EN.shaded_fast(pv, td, c["topo"], p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null)


const LOOK_ASYNC_TRIS := 2000   # a big solid's first look after a change (its edges, faces, shading) made on a worker


## (a big solid changed - a knife's cut, a settle - and nothing moving) Its edges, faces and shading
## worked out on a worker, the mesh it shows now kept meanwhile (null) - then shown, and the weights for
## the next drag started on a worker as usual.
func _look_async(p: MeshInstance3D, spec: Dictionary, c: Dictionary, v0: PackedVector3Array, all_edge: Dictionary, old: Dictionary) -> ArrayMesh:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var tt: PackedInt32Array = c["t"]
	if c.has("look_job"):
		var lj: Array = c["look_job"]
		if not WorkerThreadPool.is_task_completed(int(lj[0])):
			set_meta("edge_jobs", true)
			return null
		WorkerThreadPool.wait_for_task_completion(int(lj[0]))
		c.erase("look_job")
		var r: Dictionary = lj[1][0]
		if r["t"] == tt and r["v"] == v0:
			var feat: Dictionary = r["feat"]
			var holder := [null, null]
			var ax: Array = spec.get("up", [0, 0, 0])
			var up3 := Vector3(ax[0], ax[1], ax[2])
			var vv := v0.duplicate()
			var tt2 := tt.duplicate()
			var ae := all_edge.duplicate()
			var job := WorkerThreadPool.add_task(func():
				holder[0] = EN.blend_weights(vv, tt2, ae, feat.duplicate(), up3)
				holder[1] = EN.cg_setup(vv, tt2, holder[0]))
			c["bw_job"] = [job, holder]
			c["edge"] = all_edge
			c["last"] = PackedVector3Array()
			c["pv"] = v0
			c["t_draw"] = tt
			return r["mesh"]
	var hold := [null]
	var vw := v0.duplicate()
	var tw := tt.duplicate()
	var fvw: Array = (spec.get("fv", []) as Array).duplicate(true)
	var chw: Array = (spec.get("chains", []) as Array).duplicate(true)
	var mat: Material = p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null
	var lj2 := WorkerThreadPool.add_task(func():
		var feat: Dictionary = EN.feature_edges(vw, tw, fvw, chw, old)
		var fo: PackedInt32Array = EN.face_of(vw, tw, feat)
		hold[0] = {"v": vw, "t": tw, "feat": feat, "mesh": EN.shaded(vw, tw, fo, mat)})
	c["look_job"] = [lj2, hold]
	set_meta("edge_jobs", true)
	return null


## A solid being dragged whole (every edge of it moved by one same shift from where it settled): its
## settled mesh shifted on a worker - no solving, no edge matching. [] - not that (made the usual way);
## [mesh or null] - done here (null: still being worked out).
func _rigid_drag(p: MeshInstance3D, spec: Dictionary) -> Array:
	if (_drag.is_empty() and op.is_empty()) or bool(get_meta("cg_full", false)) or not spec.has("mesh"):
		return []
	var c = _edge_bases().get(int(spec.get("net", 0)))
	if not (c is Dictionary and (c as Dictionary).has("topo") and (c as Dictionary).has("v") and int(c.get("n", -1)) == (spec["mesh"]["v"] as Array).size()):
		return []
	var c0: Dictionary = spec.get("c0", {})
	var cc: Array = c.get("c0_ctrl", [])
	if cc.size() != 2 or not is_same(cc[0], c0):
		var ctrls := {}
		for k in c0:
			var cs := from_json([c0[k]])
			if not cs.is_empty():
				ctrls[int(k)] = cs[0]["ctrl"]
		cc = [c0, ctrls]
		c["c0_ctrl"] = cc
	var ctrls: Dictionary = cc[1]
	var shift := Vector3.INF
	for id in spec.get("ids", []):
		var cv := curve_by_id(int(id))
		if cv.is_empty() or not ctrls.has(int(id)):
			return []
		var a: PackedVector3Array = ctrls[int(id)]
		var b: PackedVector3Array = cv["ctrl"]
		if a.size() != b.size() or a.is_empty():
			return []
		if shift == Vector3.INF:
			shift = b[0] - a[0]
		for i in a.size():
			if (b[i] - a[i]).distance_squared_to(shift) > 1e-12:
				return []
	if shift == Vector3.INF or shift.length_squared() < 1e-14:
		return []
	var moves := {-1: shift}
	var mat: Material = p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null
	var out: ArrayMesh = null
	if c.has("drag_job"):
		if not WorkerThreadPool.is_task_completed(int(c["drag_job"][0])):
			c["drag_want"] = moves
			set_meta("edge_jobs", true)
			return [null]
		out = _drag_job_take(c)
	elif c.get("drag_mesh") is ArrayMesh:
		out = c["drag_mesh"]
	if c.has("drag_want") or c.get("drag_done_moves") != moves:
		c.erase("drag_want")
		_drag_job_start(c, moves, mat, _patch_for(p, spec, c))
	return [out]


## (a drag's first frame on a solid not edited yet) Its edges, weights and solver worked out on a worker -
## the mesh as it is till then; the edges move at once (made here they were a second's freeze). null.
func _cold_drag(spec: Dictionary, c: Dictionary, v0: PackedVector3Array, old: Dictionary) -> ArrayMesh:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var all_edge := {}
	var fvl: Array = spec.get("fv", [])
	for e in fvl:
		all_edge[int(e[0])] = true
	var hold := [null, null]
	var vw := v0.duplicate()
	var tw: PackedInt32Array = (c["t"] as PackedInt32Array).duplicate()
	var fvw: Array = fvl.duplicate(true)
	var chw: Array = (spec.get("chains", []) as Array).duplicate(true)
	var aw := all_edge.duplicate()
	var axw: Array = spec.get("up", [0, 0, 0])
	var upw := Vector3(axw[0], axw[1], axw[2])
	var bj := WorkerThreadPool.add_task(func():
		var fw: Dictionary = EN.feature_edges(vw, tw, fvw, chw, old)
		hold[0] = EN.blend_weights(vw, tw, aw, fw, upw)
		hold[1] = EN.cg_setup(vw, tw, hold[0]))
	c["bw_job"] = [bj, hold]
	c["bw_wait"] = true
	c["edge"] = all_edge
	set_meta("edge_jobs", true)
	return null


## A drag's frame for cache `c` with `moves` (or what to work them out from): the newest one shown as it
## comes, the next started once the one being worked out is done (null: none ready yet).
func _drag_frame(c: Dictionary, moves: Dictionary, mat: Material, ptris := PackedInt32Array()) -> ArrayMesh:
	var want := moves.duplicate()
	want.erase(-3)   # (compared by what they'd make: the curves' hash)
	var out: ArrayMesh = null
	if c.has("drag_job"):
		if not WorkerThreadPool.is_task_completed(int(c["drag_job"][0])):
			c["drag_want"] = moves
			set_meta("edge_jobs", true)
			return null
		out = _drag_job_take(c)
	elif c.get("drag_mesh") is ArrayMesh:
		out = c["drag_mesh"]
	var done = c.get("drag_done_moves")
	if c.has("drag_want") or not (done is Dictionary) or done != want:
		c.erase("drag_want")
		_drag_job_start(c, moves, mat, ptris)   # (the newest: the curves as they are now)
		c["drag_job"][2] = want
	return out


## The picked face's triangles when it's on part `p` and drawn from cache `c` (the same triangles as its
## recipe's) - its overlay made with the drag's frame; empty otherwise.
func _patch_for(p: MeshInstance3D, spec: Dictionary, c: Dictionary) -> PackedInt32Array:
	if spec.get("view", false) or not has_meta("patch") or (get_meta("patch") as Dictionary).is_empty():
		return PackedInt32Array()
	var pa := picked_patch()
	if pa.is_empty() or pa["part"] != p or (c["t"] as PackedInt32Array).size() != (spec["mesh"]["t"] as Array).size():
		return PackedInt32Array()
	return pa["tris"]


## (worker) Triangles `ptris` of mesh pv / t as an overlay's arrays: [ptris, points, smooth normals] ([] - none).
static func _patch_arrays(pv: PackedVector3Array, t: PackedInt32Array, ptris: PackedInt32Array) -> Array:
	if ptris.is_empty():
		return []
	var vn := {}
	for ti in ptris:
		var a := pv[t[ti * 3]]
		var fn := (pv[t[ti * 3 + 2]] - a).cross(pv[t[ti * 3 + 1]] - a)
		for j in 3:
			var vi := t[ti * 3 + j]
			vn[vi] = (vn.get(vi, Vector3.ZERO) as Vector3) + fn
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for ti in ptris:
		for j in 3:
			var vi := t[ti * 3 + j]
			verts.append(pv[vi])
			norms.append((vn[vi] as Vector3).normalized())
	return [ptris, verts, norms]


## A drag's frame for cache `c` started on a worker: the edges' `moves` solved (a few rounds from the last
## solution) and the mesh shaded - nothing in `c` written there (taken back by _drag_job_take).
func _drag_job_start(c: Dictionary, moves: Dictionary, mat: Material, ptris := PackedInt32Array()) -> void:
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var v0: PackedVector3Array = c["v"]
	var cg: Dictionary = c.get("cg", {})
	var bw: Dictionary = c.get("bw", {})
	var warm: PackedVector3Array = c.get("r_last", PackedVector3Array())
	var t: PackedInt32Array = c["t"]
	var topo: Dictionary = c["topo"]
	var edge: Dictionary = c.get("edge", {})
	var mv := moves.duplicate()
	var holder := [null]
	var job := WorkerThreadPool.add_task(func():
		var sol: Dictionary
		if mv.has(-1):
			# (dragged whole: every point the same shift - the solver's warm start dropped, it's not its)
			var dd := PackedVector3Array()
			dd.resize(v0.size())
			dd.fill(mv[-1])
			sol = {"d": dd, "r": PackedVector3Array()}
		elif mv.has(-3):
			# (the edges' moves worked out here too, from the curves as they were handed over)
			var src: Array = mv[-3]
			var em: Dictionary = EN.edge_moves(src[0], src[1], src[2], src[3], v0)
			for vi in edge:
				if not em.has(vi):
					em[vi] = Vector3.ZERO
			sol = EN.cg_moves(v0.size(), cg, bw, em, warm, 8, 1e-4, 1)
		else:
			sol = EN.cg_moves(v0.size(), cg, bw, mv, warm, 8, 1e-4, 1)
		var d: PackedVector3Array = sol["d"]
		var pv := PackedVector3Array()
		pv.resize(v0.size())
		for i in v0.size():
			pv[i] = v0[i] + d[i]
		holder[0] = {"r": sol["r"], "d": d, "pv": pv, "mesh": EN.shaded_fast(pv, t, topo, mat), "patch": _patch_arrays(pv, t, ptris)})
	c["drag_job"] = [job, holder, mv]
	set_meta("edge_jobs", true)


## A finished drag frame taken into cache `c`: its solution kept (the next goes on from it), its mesh.
func _drag_job_take(c: Dictionary) -> ArrayMesh:
	WorkerThreadPool.wait_for_task_completion(int(c["drag_job"][0]))
	var r: Dictionary = c["drag_job"][1][0]
	c["drag_done_moves"] = c["drag_job"][2]
	c.erase("drag_job")
	c["r_last"] = r["r"]
	c["last"] = r["d"]
	c["pv"] = r["pv"]
	c["t_draw"] = c["t"]
	c["drag_mesh"] = r["mesh"]
	if r["mesh"] is ArrayMesh:
		(r["mesh"] as ArrayMesh).set_meta("src", [r["pv"], c["t"]])   # (its points: a picked face's overlay made from them, not read back)
		if not (r.get("patch", []) as Array).is_empty():
			(r["mesh"] as ArrayMesh).set_meta("patch_arrays", r["patch"])   # (the picked face's overlay itself, made with it)
	return r["mesh"]


## (letting go) A drag frame still being worked out: waited for and left (the full solve goes on from it).
func _drag_job_drop(c: Dictionary) -> void:
	if c.has("drag_job"):
		_drag_job_take(c)
	c.erase("drag_want")
	c.erase("drag_mesh")


## After an edit (a drag let go, a point put in...): each baked solid whose edges changed settled - its
## mesh made from its shape now, even and fine enough, quads kept (EdgeNet.settle) - and that its new
## start (its curves now its curves as made).
func settle_edges() -> void:
	for job in _settle_inputs():
		_settle_apply(job, _settle_compute(job))
	refresh_solids()


## (settling, on the main thread) What each baked solid whose edges changed needs to be settled: its
## bake (made once, kept: every later edit bends from it), the solver ready for it, the edges' moves
## from the bake to now, its edge points' places carried over, which curves moved. [{p, spec, ...}].
func _settle_inputs() -> Array:
	var out := []
	if ed == null or ed.model == null:
		return out
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	for p: MeshInstance3D in ed.parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if str(spec.get("kind", "")) != "edges" or not spec.has("mesh"):
			continue
		# (its edges as they were when last found unmoved: not looked at again - ninety solids' edges
		# read back and compared at every let-go was 200 ms)
		var skey := _solid_key(spec)
		var forced := p.has_meta("force_settle")
		if str(p.get_meta("settled_key", "")) == skey and not forced:
			continue
		var c0: Dictionary = spec.get("c0", {})
		var now := {}
		var moved := false
		var c0p := {}
		for k in c0:
			var cs0 := from_json([c0[k]])
			if not cs0.is_empty():
				c0p[int(k)] = cs0[0]
		for id in spec.get("ids", []):
			var cv := curve_by_id(int(id))
			if cv.is_empty():
				continue
			now[int(id)] = cv.duplicate(true)
			if c0p.has(int(id)) and not EN._same_curve(cv, c0p[int(id)]):
				moved = true
		if not moved and not (forced and spec.has("orig")):
			p.set_meta("settled_key", skey)
			continue
		# (a solid too coarse for its edges to bend it - a converted model's own triangles: made finer first,
		# its surface as it was)
		if int(spec.get("dense", 0)) < 3 and _from_model(p) and _densify_solid(p):
			spec = p.get_meta("curve_solid")
		# (the bake kept as it was - every later edit bent from it)
		if not spec.has("orig"):
			spec["orig"] = {"mesh": (spec["mesh"] as Dictionary).duplicate(true), "fv": (spec.get("fv", []) as Array).duplicate(true), "c0": c0.duplicate(true)}
		var base := _orig_view(spec)
		c0 = base["c0"]
		var bnet := int(base["net"])
		var cache: Dictionary = _edge_bases().get(bnet, {}) if _edge_bases().get(bnet) is Dictionary else {}
		if cache.has("bw_job") and WorkerThreadPool.is_task_completed(int(cache["bw_job"][0])):
			# (its weights done on a worker: taken)
			WorkerThreadPool.wait_for_task_completion(int(cache["bw_job"][0]))
			cache["bw"] = cache["bw_job"][1][0]
			if cache["bw_job"][1][1] != null:
				cache["cg"] = cache["bw_job"][1][1]
			cache.erase("bw_job")
			cache.erase("r_last")
		if cache.is_empty() or not cache.has("bw") or cache.has("bw_job") or not cache.has("edge"):
			# (its solver not made yet - a first edit, or let go before its weights were done: worked out
			# with the settling, on its worker - not here, it's a second's freeze on a big solid)
			var bm: Dictionary = base["mesh"]
			var bv := PackedVector3Array()
			var bflat: Array = bm["v"]
			for i in range(0, bflat.size(), 3):
				bv.append(Vector3(bflat[i], bflat[i + 1], bflat[i + 2]))
			var be := {}
			for e in base.get("fv", []):
				be[int(e[0])] = true
			var oldc := {}
			for k in c0:
				var csc := from_json([c0[k]])
				if not csc.is_empty():
					oldc[int(k)] = csc[0]
			var upc: Array = spec.get("up", [0, 0, 0])
			p.remove_meta("force_settle")
			out.append({"p": p, "spec": spec, "EN": EN, "v0": bv, "t": PackedInt32Array(bm["t"]), "cold": true, "edge": be, "old": oldc,
				"fv0": base.get("fv", []), "warm": PackedVector3Array(), "chains": (spec.get("chains", []) as Array).duplicate(true),
				"now": now, "moved": {}, "up": Vector3(upc[0], upc[1], upc[2]),
				"mat": p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null})
			for id in now:
				if not oldc.has(int(id)) or not EN._same_curve(now[id], oldc[int(id)]):
					(out.back()["moved"] as Dictionary)[int(id)] = true
			continue
		if cache.has("drag_job"):
			# (a drag frame still being worked out: left to finish on its own - waited for later)
			_orphans().append(int(cache["drag_job"][0]))
			cache.erase("drag_job")
			cache.erase("drag_want")
		if not cache.has("cg"):
			cache["cg"] = EN.cg_setup(cache["v"], cache["t"], cache["bw"])
		var old := {}
		for k in c0:
			var cs := from_json([c0[k]])
			if not cs.is_empty():
				old[int(k)] = cs[0]
		var v0: PackedVector3Array = cache["v"]
		var moved_ids := {}
		for id in now:
			if not old.has(int(id)) or not EN._same_curve(now[id], old[int(id)]):
				moved_ids[int(id)] = true
		var chs0: Array = spec.get("chains", [])
		var upa: Array = spec.get("up", [0, 0, 0])
		p.remove_meta("force_settle")   # (its forced settle made - till then kept: its solver may still be on its way)
		out.append({"p": p, "spec": spec, "EN": EN, "v0": v0, "t": cache["t"], "cg": cache["cg"], "bw": cache["bw"], "nb": cache.get("nb", []),
			"edge": cache["edge"], "old": old, "fv0": base.get("fv", []), "warm": cache.get("r_last", PackedVector3Array()), "chains": (chs0 as Array).duplicate(true),
			"now": now, "moved": moved_ids, "up": Vector3(upa[0], upa[1], upa[2]),
			"mat": p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null})
	return out


## Worker tasks no longer wanted, still to be waited for (in _process, once they're done).
func _orphans() -> Array:
	if not has_meta("orphans"):
		set_meta("orphans", [])
	return get_meta("orphans")


## (settling - safe on a worker: it reads only what `job` holds) The bake bent to the edges now, solved
## all the way, nothing turned over, the walls' columns straightened, then settled (EdgeNet.settle).
## {v, t, fv}.
static func _settle_compute(job: Dictionary) -> Dictionary:
	var EN: GDScript = job["EN"]
	var v0: PackedVector3Array = job["v0"]
	var t: PackedInt32Array = job["t"]
	if not job.get("cold", false) and (job.get("nb", []) as Array).is_empty():
		job["nb"] = EN.neighbours(t, v0.size())   # (not made with its cache: made here)
	if job.get("cold", false):
		# (its solver made here first - the bake's edges, weights and set-up)
		job["nb"] = EN.neighbours(t, v0.size())
		var feat: Dictionary = EN.feature_edges(v0, t, job["fv0"], job["chains"], job["old"])
		job["bw"] = EN.blend_weights(v0, t, job["edge"], feat, job["up"])
		job["cg"] = EN.cg_setup(v0, t, job["bw"])
	var chs: Array = job["chains"]
	var now: Dictionary = job["now"]
	var old: Dictionary = job["old"]
	# the edges' moves from the bake to now (an unmoved edge point held)
	var moves: Dictionary = EN.edge_moves(job["fv0"], chs, old, now, v0)
	for vi in job["edge"]:
		if not moves.has(vi):
			moves[vi] = Vector3.ZERO
	# (each edge point's place carried over span by span - as the drag moved it)
	var fv_now: Array = (job["fv0"] as Array).duplicate(true)
	var maps := {}
	for e in fv_now:
		var cid := int(chs[int(e[1])]["id"]) if int(e[1]) < chs.size() else -1
		if not now.has(cid) or not old.has(cid):
			continue
		if not maps.has(cid):
			maps[cid] = EN.span_map(old[cid], now[cid])
		e[2] = EN.map_t(maps[cid], float(e[2]))
	var sol: Dictionary = EN.cg_moves(v0.size(), job["cg"], job["bw"], moves, job["warm"], 2000, 1e-6, 6)
	var d: PackedVector3Array = sol["d"]
	var pv := PackedVector3Array()
	pv.resize(v0.size())
	for i in v0.size():
		pv[i] = v0[i] + d[i]
	pv = EN.untangle(pv, v0, t, job["nb"], job["edge"])
	var td: PackedInt32Array = EN.flip_fix(pv, v0, t, job["bw"]["tri_face"])["t"]
	EN.straighten_columns(pv, fv_now, job["chains"], job["now"], job["moved"], job["bw"], job["up"], td)
	var area := 0.0
	for i in range(0, td.size(), 3):
		area += (pv[td[i + 1]] - pv[td[i]]).cross(pv[td[i + 2]] - pv[td[i]]).length() * 0.5
	var L := clampf(sqrt(area / 380.0), 0.003, 1.0) * 0.6
	# (a solid of a model's own triangles made finer: its faces not made again as grids where its edges
	# moved - fine enough to follow them already; on its thin shells the new grids folded, a saw-tooth)
	# (a solid of a model's own triangles made finer: its faces not made again as grids or cut through where
	# its edges moved - on its thin shells those folded, a saw-tooth - but its triangles made even inside
	# its faces, its shape kept: no long thin ones shading badly)
	var dense := int((job["spec"] as Dictionary).get("dense", 0)) >= 1
	var r: Dictionary = EN.settle(pv, td, fv_now, job["chains"], job["now"], 180.0, L * 0.35, {} if dense else job["moved"], L)   # (loop cuts off: they added rows on every edit, the mesh only grew)
	if dense:
		var ev: Dictionary = EN.even_faces(r["v"], r["t"], r["fv"], 6, false)   # (slid even, no flips: its quads kept)
		r["v"] = ev["v"]
		r["t"] = ev["t"]
	# (and what its first drawing and its next drag need, here too: turned outwards, its neighbours,
	# edges, weights and solver, the mesh shaded - letting go never waits on the main thread)
	var vv: PackedVector3Array = r["v"]
	# (each triangle facing the way the mesh it was bent from faces there - not turned outwards from one
	# triangle across the whole: a thin open shell, a converted plate, came out with its triangles facing
	# both ways along its folds - a saw-tooth)
	var tt: PackedInt32Array = _orient_like(vv, r["t"], pv, td) if dense and td.size() >= 3 else EN.orient(vv, r["t"])
	r["t"] = tt
	var all_edge := {}
	for e in r["fv"]:
		all_edge[int(e[0])] = true
	var feat: Dictionary = EN.feature_edges(vv, tt, r["fv"], job["chains"], job["now"])
	var bw: Dictionary = EN.blend_weights(vv, tt, all_edge, feat, job["up"])
	var topo: Dictionary = EN.corner_topo(vv.size(), tt)
	r["cache"] = {"n": vv.size() * 3, "v": vv, "t": tt, "nb": EN.neighbours(tt, vv.size()), "last": PackedVector3Array(), "edge": all_edge,
		"bw": bw, "cg": EN.cg_setup(vv, tt, bw), "pv": vv, "t_draw": tt, "topo": topo, "topo_n": tt.size()}
	r["mesh"] = with_lods(EN.shaded_fast(vv, tt, topo, null, 40.0, true), job.get("mat"))
	var flat := []
	flat.resize(vv.size() * 3)
	for i in vv.size():
		flat[i * 3] = vv[i].x
		flat[i * 3 + 1] = vv[i].y
		flat[i * 3 + 2] = vv[i].z
	r["flat"] = flat
	r["t_arr"] = Array(tt)
	# (its faces too - a press on one of them right after finds them ready)
	var fspec := {"mesh": {"v": flat, "t": r["t_arr"]}, "fv": r["fv"], "chains": job["chains"]}
	r["faces"] = _faces_make(fspec)
	_faces_ids(fspec, r["faces"])
	return r


## (worker) Mesh v / t's triangles each turned to face as the nearest triangle of mesh bv / bt faces (the one
## it was made from). A copy of t.
static func _orient_like(v: PackedVector3Array, t: PackedInt32Array, bv: PackedVector3Array, bt: PackedInt32Array) -> PackedInt32Array:
	var out := t.duplicate()
	if bv.is_empty():
		return out
	var box := AABB(bv[0], Vector3.ZERO)
	for q in bv:
		box = box.expand(q)
	# (cells about two of its triangles across - by its own edges' length, not a 24th of its size: a dense
	# solid's cells held hundreds of triangles each, every one looked at for every triangle - seconds)
	var el := 0.0
	var ne := 0
	for i in range(0, bt.size(), 3):
		el += bv[bt[i]].distance_to(bv[bt[i + 1]]) + bv[bt[i + 1]].distance_to(bv[bt[i + 2]]) + bv[bt[i + 2]].distance_to(bv[bt[i]])
		ne += 3
	var cell := maxf(el / maxf(ne, 1) * 2.0, box.size.length() / 200.0)
	var g := _tri_grid(bv, bt, maxf(minf(box.size.length(), cell * 24.0), 1e-4))
	for i in range(0, out.size(), 3):
		var a := v[out[i]]
		var b := v[out[i + 1]]
		var c := v[out[i + 2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-24:
			continue
		var near := _nearest_on(g, bv, bt, (a + b + c) / 3.0)
		var bi := int(near[1])
		if bi < 0:
			continue
		var bn := (bv[bt[bi + 1]] - bv[bt[bi]]).cross(bv[bt[bi + 2]] - bv[bt[bi]])
		if n.dot(bn) < 0.0:
			var k := out[i + 1]
			out[i + 1] = out[i + 2]
			out[i + 2] = k
	return out


## (settling, on the main thread) A settled mesh `r` made the solid's new start: its mesh, edge points and
## curves now.
func _settle_apply(job: Dictionary, r: Dictionary) -> void:
	var p: MeshInstance3D = job["p"]
	if not is_instance_valid(p):
		return
	var spec: Dictionary = (job["spec"] as Dictionary).duplicate()   # (its arrays replaced below, not changed: a shallow copy)
	var flat: Array = r["flat"] if r.has("flat") else []
	if not r.has("flat"):
		for q in (r["v"] as PackedVector3Array):
			flat.append_array([q.x, q.y, q.z])
	spec["mesh"] = {"v": flat, "t": r["t_arr"] if r.has("t_arr") else Array(r["t"])}
	spec["fv"] = r["fv"]
	if r.get("faces") is Dictionary:
		_faces_memo.push_front([spec["mesh"]["v"], spec["mesh"]["t"], spec["fv"], spec.get("chains"), r["faces"]])
		if _faces_memo.size() > FACES_MEMO:
			_faces_memo.resize(FACES_MEMO)
	var cz := {}
	for id in job["now"]:
		cz[str(int(id))] = to_json([job["now"][id]])[0]
	spec["c0"] = cz
	spec["tied"] = true
	spec["qcaps"] = true
	spec["sealed"] = true
	if r.has("cache"):
		# (drawn and ready for the next drag already - worked out with it)
		spec["oriented"] = true
		_edge_bases()[int(spec.get("net", 0))] = r["cache"]
		p.set_meta("curve_solid", spec)
		var m: ArrayMesh = r["mesh"]
		if m and p.mesh and p.mesh.get_surface_count() > 0 and m.get_surface_count() > 0:
			m.surface_set_material(0, p.mesh.surface_get_material(0))
		p.mesh = m
		p.set_meta("curve_solid_key", _solid_key(spec))
		ed.view.request()
		return
	spec.erase("oriented")   # (turned outwards again on its next drawing)
	_edge_bases().erase(int(spec.get("net", 0)))
	p.set_meta("curve_solid", spec)
	p.remove_meta("curve_solid_key")


## An interactive edit let go (a drag): its undo step made once its baked solids have settled - worked
## out on a worker meanwhile (the view keeps its frame rate; the last drag frame shows till then). Any
## new edit first waits for it (_settle_finish).
func _changed_async(name: String, before: Array) -> void:
	_settle_finish()
	var jobs := _settle_inputs()
	if jobs.is_empty():
		_changed(name, before)
		return
	var holders := []
	for job in jobs:
		var h := [null]
		var j: Dictionary = job
		var id := WorkerThreadPool.add_task(func(): h[0] = _settle_compute(j))
		holders.append([id, h, job])
	set_meta("settling", {"name": name, "before": before, "jobs": holders})


## The settling started by _changed_async: taken when its work's done (`wait`: waited for) - the meshes
## applied and the undo step made. True - nothing left settling.
func _settle_finish(wait := true) -> bool:
	if not has_meta("settling"):
		return true
	var st: Dictionary = get_meta("settling")
	for h in st["jobs"]:
		if not wait and not WorkerThreadPool.is_task_completed(int(h[0])):
			return false
	remove_meta("settling")
	for h in st["jobs"]:
		WorkerThreadPool.wait_for_task_completion(int(h[0]))
		_settle_apply(h[2], h[1][0])
	refresh_solids()
	_record(str(st["name"]), st["before"])
	# (the faces at the edges it moved laid out again by the topology rules - the full layout, in the background,
	# put into this same undo step when it's done)
	if SETTLE_RELAYOUT:
		for h in st["jobs"]:
			var job: Dictionary = h[2]
			var p = job["p"]
			if not is_instance_valid(p) or int((job["spec"] as Dictionary).get("dense", 0)) >= 1 or (job.get("moved", {}) as Dictionary).is_empty():
				continue
			var chs: Array = ((p as Node).get_meta("curve_solid", {}) as Dictionary).get("chains", [])
			var idx := []
			for ci in chs.size():
				if (job["moved"] as Dictionary).has(int(chs[ci]["id"])):
					idx.append(ci)
			if not idx.is_empty():
				set_meta("remesh_after", p)
				set_meta("remesh_after_only", idx)
				set_meta("remesh_after_merge", true)
				break
	return true


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
			return {"error": "it's baked already - its edges are its own: reshape them."}
		return {"error": "it's baked already: its edges are its own (bake the other solids into it from them)."}
	if not str(base.get("kind", "")) in ["extrude", "baked"]:
		return {"error": "only extrusions bake (this solid is a %s)." % str(base.get("kind", "?"))}
	var cs0 := curves_of(base.get("ids", []))
	if cs0.is_empty():
		return {"error": "its edges are gone."}
	var n: Vector3 = (cs0[0].get("n", Vector3.UP) as Vector3).normalized()
	var u := _any_perp(n)
	var v := n.cross(u)
	var bk := {"n": n, "u": u, "v": v, "prisms": []}
	var bt = _bake_leaf(base, Transform3D(), bk)
	if bt == null:
		return {"error": "its edges must be closed and flat across its axis."}
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
		return {"error": "nothing to bake - it's made of one edge already."}
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
		item.call(pm, "New collection from the selected (%d)" % sel_ps.size(), make_group.bind(sel_ps))
		var mv := PopupMenu.new()
		mv.add_theme_font_size_override("font_size", 14)
		for g in groups():
			if g != group_of(p):
				mv.add_item(str(g.name), acts.size())
				acts.append(move_to_group.bind(sel_ps, g))
		if group_of(p):
			mv.add_item("(no collection - the top)", acts.size())
			acts.append(move_to_group.bind(sel_ps, null))
		mv.id_pressed.connect(_menu_act)
		pm.add_submenu_node_item("Move to collection", mv)
		pm.set_item_disabled(pm.item_count - 1, mv.item_count == 0)
		item.call(pm, "Show" if not p.visible else "Hide", _act_toggle_part.bind(p))
		item.call(pm, "Duplicate", _act_part.bind(p, "duplicate"))
		item.call(pm, "Delete", _act_part.bind(p, "delete"))
		pm.add_separator()
		item.call(pm, "Pick its edges", _act_part.bind(p, "pick"), not spec.is_empty())
		item.call(pm, "Bake (its tools into its edges)", _act_part.bind(p, "bake"), can_bake(p))
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
		item.call(pm, "Delete step (its edges stay)", _act_step.bind(p, parent, "delete"))
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
			_changed("Hide edge" if curves[i]["hidden"] else "Show edge", before)
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
		set_recipe(with_node(spec, leaf, n2), "Detach edge")
	elif not leaf.is_empty() and leaf.back() == "b":
		var parent := leaf.slice(0, -1)
		set_recipe(with_node(spec, parent, node_at(spec, parent).get("a", {})), "Detach edge")
	else:
		ed._say("%s is the only edge %s is made from - delete or detach the solid instead." % [curves[i].get("name", "This edge"), p.name])


## Curve `i` added to solid `q` as a new step (cut / join / common).
func _act_attach_curve(i: int, q: MeshInstance3D, op: String) -> void:
	ed.select_part(q)
	sel = [i]
	add_tool_curves(op)


## (a folded solid) Its tool steps' rows - each cut / join / common with its own edges under it.
func _tree_step_rows(tree: Tree, parent: TreeItem, p: MeshInstance3D, node: Dictionary, path: Array) -> void:
	if str(node.get("kind", "")) != "bool":
		return
	_tree_step_rows(tree, parent, p, node.get("a", {}), path + ["a"])
	var eye_on := EditorIcons.get_icon("eye")
	var eye_off := EditorIcons.get_icon("eye_off")
	var b: Dictionary = node.get("b", {})
	var si := tree.create_item(parent)
	si.set_text(0, "%s: %s" % [{"union": "Join", "difference": "Cut", "intersection": "Common"}.get(str(node.get("op", "")), "Tool"), _spec_words(b)])
	si.set_metadata(0, {"step": path + ["b"], "of": p})
	si.set_icon(0, EditorIcons.get_icon("m_cv_ol_step"))
	si.set_meta("tip_0", "A tool step of %s. Click: select the solid and pick this step's edges. The eye hides its ghost." % p.name)   # (PinTips only - never Godot's own beside it)
	si.add_button(1, eye_off if bool(b.get("ghost_hidden", false)) else eye_on, 0, false, "")
	si.set_meta("btip_%d" % (0), "Hide / show this step's ghost.")
	_tree_steps(tree, si, p, b, path + ["b"])
	si.collapsed = true


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
		si.set_icon(0, EditorIcons.get_icon("m_cv_ol_step"))
		si.set_meta("tip_0", "A tool step of %s. Click: select the solid and pick this step's edges. The eye hides its ghost." % p.name)   # (PinTips only - never Godot's own beside it)
		si.add_button(1, eye_off if bool(b.get("ghost_hidden", false)) else eye_on, 0, false, "")
		si.set_meta("btip_%d" % (0), "Hide / show this step's ghost.")
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
		ci.set_meta("renamable", true)   # (renamed on a double-click only - a click picks)
		ci.set_metadata(0, {"curve": i, "of": p, "leaf": path})
		ci.set_icon(0, EditorIcons.get_icon("m_cv_ol_edge"))
		ci.set_meta("tip_0", ("An edge on %s's surface: one of the edges that shape it. Click: pick it (Ctrl / Shift: more) and\nreshape it - the solid follows. Right-click: more." if baked else "An edge %s is made from. Click: pick it (Ctrl / Shift: more). The eye hides it (and its ghost).\nRight-click: more.") % p.name)   # (PinTips only - never Godot's own beside it)
		ci.add_button(1, eye_off if curves[i].get("hidden", false) else eye_on, 0, false, "")
		ci.set_meta("btip_%d" % (0), "Hide / show this edge (and its ghost).")
		if i in sel:
			ci.select(0)


func _curve_index(id: int) -> int:
	if has_meta("idx_of"):
		return int((get_meta("idx_of") as Dictionary).get(id, -1))   # (while the overview's filled: looked up, not searched)
	if not curve_by_id(id).is_empty():
		return int(_id_index.get(id, -1))   # (the id map, made again if it's out of date)
	for i in curves.size():
		if int(curves[i].get("id", -1)) == id:
			return i
	return -1


static func _spec_words(spec: Dictionary) -> String:
	var k := str(spec.get("kind", ""))
	if k == "bool":
		return "%s of two solids" % {"union": "a join", "difference": "a cut", "intersection": "the common part"}.get(str(spec.get("op", "")), "a boolean")
	return {"extrude": "an extrusion", "baked": "a baked solid", "edges": "a baked solid", "revolve": "a revolve", "pipe": "a pipe", "loft": "a loft", "sweep": "a sweep", "fill": "a fill"}.get(k, "a solid")


## The solids opened in the overview (their edges listed), by instance id.
func _unfolded() -> Dictionary:
	if not has_meta("unfolded"):
		set_meta("unfolded", {})
	return get_meta("unfolded")


## A solid's row opened or closed: its edge rows made (or dropped) the next time the overview's filled.
func _tree_folded(item: TreeItem) -> void:
	if bool(get_meta("tree_sync", false)):
		return
	var md = item.get_metadata(0)
	if not (md is Dictionary and (md as Dictionary).has("part")):
		return
	var p = md["part"]
	if not is_instance_valid(p):
		return
	var id: int = (p as Object).get_instance_id()
	if item.collapsed:
		_unfolded().erase(id)
	else:
		_unfolded()[id] = true
	_fill_tree.call_deferred()


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
			var nd = m.get("part", m.get("group", m.get("of")))
			if nd is Node and is_instance_valid(nd) and locked(nd):
				pass   # (not selectable: left as it is)
			elif m.has("part") and is_instance_valid(m["part"]):
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
	var only_group: Node3D = null
	var it2: TreeItem = (t as Tree).get_next_selected(null)
	var rows := 0
	while it2:
		rows += 1
		var m2 = it2.get_metadata(0)
		if m2 is Dictionary and m2.has("group") and is_instance_valid(m2["group"]):
			only_group = m2["group"]
		it2 = (t as Tree).get_next_selected(it2)
	if rows == 1 and only_group != null and not locked(only_group):
		pick_group(only_group)   # (a collection's row: the collection picked whole)
		return
	set_meta("group_pick", 0)
	if not parts.is_empty():
		ed.select_parts(parts)
		if cidx.is_empty() and parts.size() == 1:
			solid_chosen(parts[0])
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
			_changed("Rename edge", before)


## The eye: a solid shown / hidden (as the parts list's eye), a curve hidden from the view (one undo step).
func _tree_button(it: TreeItem, _col: int, _id: int, _mb: int) -> void:
	var m = it.get_metadata(0)
	if not m is Dictionary:
		return
	if _id == 1:
		var n = m.get("group", m.get("part"))
		if n is Node and is_instance_valid(n):
			if locked(n) and not (n as Node).has_meta("no_select"):
				ed._say("%s: its collection isn't selectable - turn its collection's arrow on." % n.name)
				return
			set_selectable(n, (n as Node).has_meta("no_select"))
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
		_changed("Hide edge" if curves[i]["hidden"] else "Show edge", before)


## The Curve modeling tab's contents.
func build_panel(box: VBoxContainer) -> void:
	build_overview(box)
	build_solid_box(box)
	box.add_child(EditorIcons.tipped(UI.section("SKETCH"), EditorIcons.tip("Sketch", "", "Draw edges on the construction plane: lines, splines, circles, arcs, rectangles, polygons -\nsnapped to the grid and to vertices.")))
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
	po.tooltip_text = EditorIcons.tip("Construction plane", "", "Where new edges are drawn - Auto: the surface under your first click (a collection's face: drawn on\nit), else the ground; Ground (X Z); Front (X Y); Side (Z Y); View (square to the view); Selection\n(the selected faces in edit mode, or the picked edge).")
	po.item_selected.connect(_plane_picked)
	_panel_btns["w_plane"] = po
	sr.add_child(po)
	var g := CheckBox.new()
	g.text = "Grid"
	g.button_pressed = snap_grid
	g.focus_mode = Control.FOCUS_NONE
	g.add_theme_font_size_override("font_size", 14)
	g.tooltip_text = EditorIcons.tip("Snap to the grid", "Ctrl: off while held", "Vertices land on the construction plane's grid.")
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
	sp.tooltip_text = EditorIcons.tip("Snap to vertices", "Ctrl: off while held", "Vertices land on the edges' vertices, ends, middles and centres, and on the collections' corners.")
	sp.toggled.connect(_set_snap_points)
	sr.add_child(sp)
	var gd := CheckBox.new()
	gd.text = "Guides"
	gd.button_pressed = guides_on()
	gd.focus_mode = Control.FOCUS_NONE
	gd.add_theme_font_size_override("font_size", 14)
	gd.tooltip_text = EditorIcons.tip("Guides", "Alt: off while dragging", "A dragged vertex lines up with the others: when its X, Y or Z comes close to another vertex's\n(its own edge's first) or to a flat face's level, it snaps there - a dashed guide shows to what.")
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
	box.add_child(EditorIcons.tipped(UI.section("EDGES"), EditorIcons.tip("Edges", "", "Change the picked edges: move, turn, scale, offset, fillet, join, bridge, close, mirror,\nand combine them (union, subtract, intersect).")))
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
	box.add_child(EditorIcons.tipped(UI.section("SOLIDS FROM EDGES"), EditorIcons.tip("Solids from edges", "", "Make the picked edges into solids - extrude, revolve, loft, sweep, pipe, fill. They stay\nmade from the edges: reshape an edge and its solid follows.")))
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
	var mr := HFlowContainer.new()   # (the mesh's tools: in the right-click menu - kept here hidden, for their state)
	mr.visible = false
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
				_ghost_walk(spec, p.global_transform, nodes, p, [])
	set_meta("ghost_nodes", nodes)
	if ed and ed.view:
		ed.view.request()


func _ghost_walk(spec: Dictionary, xf: Transform3D, nodes: Array, part: MeshInstance3D = null, path := []) -> void:
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
	_ghost_walk(spec.get("a", {}), xf, nodes, part, path + ["a"])
	var bx := xf * xf_of(spec.get("b_xf", []))
	var b: Dictionary = spec.get("b", {})
	if not bool(b.get("ghost_hidden", false)) and not _all_hidden(spec_ids(b)):
		var picked_step := false
		if part != null and has_meta("step_pick"):
			var spk: Array = get_meta("step_pick")
			picked_step = spk.size() == 2 and spk[0] == part and spk[1] == path + ["b"]
		_ghost_add(solid_of(b), bx, str(spec.get("op", "difference")) + ("_picked" if picked_step else ""), nodes)
		if not nodes.is_empty() and part != null:
			(nodes.back() as Node).set_meta("step", [part, path + ["b"]])   # (clicked in the view: this step picked)
	_ghost_walk(spec.get("b", {}), bx, nodes, part, path + ["b"])


## The tool step whose ghost is under `at` (the nearest, when several): {part, step, world} ({} - none).
func _ghost_hit(at: Vector2) -> Dictionary:
	if ed == null or ed.view == null or not ghosts_on():
		return {}
	var o: Vector3 = ed.view.cam.project_ray_origin(at)
	var dir: Vector3 = ed.view.cam.project_ray_normal(at)
	var best := INF
	var got := {}
	for g in get_meta("ghost_nodes", []):
		if not is_instance_valid(g) or not (g as Node).has_meta("step"):
			continue
		var st: Array = (g as Node).get_meta("step")
		if not is_instance_valid(st[0]) or locked(st[0]):
			continue
		var d := _ray_mesh(g, o, dir)
		if d < best:
			best = d
			got = {"part": st[0], "step": st[1], "world": o + dir * d}
	return got   # (ghosts are drawn over everything: one seen under the mouse is the one clicked, a solid in front or not)


## How far along the ray (world space) mesh instance `mi` is first hit (INF: missed) - its triangles kept per mesh.
func _ray_mesh(mi: MeshInstance3D, o: Vector3, dir: Vector3) -> float:
	if mi.mesh == null:
		return INF
	var tmc: Array = mi.get_meta("hit_tm", [])
	if tmc.is_empty() or tmc[0] != mi.mesh:
		tmc = [mi.mesh, mi.mesh.generate_triangle_mesh()]
		mi.set_meta("hit_tm", tmc)
	if tmc[1] == null:
		return INF
	var inv := mi.global_transform.affine_inverse()
	var r: Dictionary = (tmc[1] as TriangleMesh).intersect_ray(inv * o, (inv.basis * dir).normalized())
	if r.is_empty():
		return INF
	return o.distance_to(mi.global_transform * (r["position"] as Vector3))


## Tool step `step` (a path in solid `p`'s recipe) picked: its solid selected, the step's edges picked - as
## its row in the overview does.
func pick_step(p: MeshInstance3D, step: Array) -> void:
	set_meta("patch", {})
	set_meta("solid", 0)
	set_meta("group_pick", 0)
	set_meta("points", [])
	if ed.part != p:
		ed.select_part(p)
	var cidx := []
	for id in spec_ids(node_at(p.get_meta("curve_solid", {}), step)):
		var ci := _curve_index(int(id))
		if ci >= 0:
			cidx.append(ci)
	sel = cidx
	set_meta("step_pick", [p, step])
	update_ghosts()
	_refresh_panel()
	layer.queue_redraw()
	ed.view.request()
	var node := node_at(p.get_meta("curve_solid", {}), step.slice(0, -1))
	ed._say("%s's %s step picked - drag it to move the %s whole (its edges reshape it)." % [p.name, {"union": "join", "difference": "cut", "intersection": "common"}.get(str(node.get("op", "")), "tool"),
		{"union": "join", "difference": "cut", "intersection": "common part"}.get(str(node.get("op", "")), "tool")])


## (dragging a tool step) The step moved whole - its placement in the recipe, not its edges: a revolved
## cut keeps its shape and goes where it's dragged; along the axis nearest the drag, as any drag.
func _step_to(at: Vector2, stepped: bool) -> void:
	var p = _drag["step"][0]
	if not is_instance_valid(p):
		return
	var d := _drag_delta(at, stepped)
	if d == Vector3.INF:
		return
	_drag["moved"] = true
	var rel: Transform3D = _mx().affine_inverse() * (p as Node3D).global_transform
	var dl: Vector3 = rel.basis.inverse() * d
	var step: Array = _drag["step"][1]
	var parent := step.slice(0, -1)
	var spec: Dictionary = (_drag["spec0"] as Dictionary).duplicate(true)
	var node := node_at(spec, parent).duplicate(true)
	node["b_xf"] = xf_arr(Transform3D(Basis.IDENTITY, dl) * (_drag["xf0"] as Transform3D))
	(p as Node).set_meta("curve_solid", with_node(spec, parent, node))
	refresh_solids()
	update_ghosts()
	layer.queue_redraw()


## A tool step's word: cut, join or common part.
func _step_word(p: MeshInstance3D, step: Array) -> String:
	var node := node_at(p.get_meta("curve_solid", {}), step.slice(0, -1))
	return {"union": "join", "difference": "cut", "intersection": "common part"}.get(str(node.get("op", "")), "tool step")


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
		if op.ends_with("_picked"):
			m.albedo_color = Color(PICKED_PT_COL, 0.38)   # (the picked step: in the picked colour, stronger)
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
		["m_move", "Move edges", "G", "Moves the picked edges in 3D with the mouse (over the plane facing you; X / Y / Z: along an\naxis; a typed number: that far). Snapped to the grid (Ctrl: free). Their solids follow.", func(): begin_xf("move"), any.call(), any],
		["m_rotate", "Turn edges", "R", "Turns the picked edges about their middle (the line of sight; X / Y / Z: an axis) - by 15°\n(Ctrl: free), or type the degrees.", func(): begin_xf("turn"), any.call(), any],
		["m_scale", "Scale edges", "S", "Scales the picked edges about their middle (X / Y / Z: along one axis), or type the factor.", func(): begin_xf("scale"), any.call(), any],
		["delete", "Delete edges", "X / Delete", "Removes the selected edges.", delete_selected, any.call(), any],
		["duplicate", "Duplicate edges", "Shift+D", "Copies of the selected edges, beside them.", duplicate_selected, any.call(), any],
		["m_mirror_x", "Mirror edges", "", "Copies of the selected edges mirrored across the model's X (left-right).", func(): mirror_selected(0), any.call(), any],
		["m_cv_radial", "Radial array", "", "Six copies of the selected edges round the model's Y axis (the originals among them).", func(): radial_array(6), any.call(), any],
		["m_cv_offset", "Offset edge", "", "A copy of the edge moved out (or in) by a distance in its plane: the mouse sets it, or type it.", begin_offset, any.call(), any],
		["m_cv_fillet", "Fillet corners", "", "Rounds the corners of the selected lines, rectangles and polygons: the mouse sets the radius,\nor type it (0: sharp again). Kept with the edge - change it any time.", begin_fillet_corners, any.call(), any],
		["m_cv_merge", "Merge edges", "Ctrl+J", "The picked edges joined wherever their ends meet - a vertex they share, or ends within the\nmerge distance (the panel): the two running on straightest through each vertex made one\n(an edge meeting itself: closed). Baked solids' edges too - their meshes as they are.", merge_curves_selected, two.call() or picked_solid() != null, two],
		["m_cv_join", "Join edges", "", "The two selected open edges made one, at their nearest ends.", join_selected, two.call(), two],
		["m_cv_bridge", "Bridge edge", "", "A smooth edge between the nearest ends of the two selected edges, leaving each along\nits own direction (its two handles drag).", bridge_selected, two.call(), two],
		["m_cv_reverse", "Reverse edge", "", "The selected edges run the other way (a loft or sweep follows their direction).", reverse_selected, any.call(), any],
		["m_union", "Union edges", "", "The picked closed edges (on one plane) made one outline. Edges round a gap leave it as a hole.", func(): curve_boolean("union"), two.call(), two],
		["m_difference", "Subtract edges", "", "The first picked closed edge minus the others (on its plane): what's inside it becomes holes.\nExtrude the results together: a solid with its holes, still following its edges.", func(): curve_boolean("subtract"), two.call(), two],
		["m_cv_spline", "Simplify edge", "", "The picked closed edges with more vertices than they need (a dense outline) made lean: corners\nand straight sides kept, a vertex every ~40° along the bends. Solids made from them follow.", simplify_selected, any.call(), any],
		["m_intersect", "Intersect edges", "", "Only what the picked closed edges all share (on one plane).", func(): curve_boolean("intersect"), two.call(), two],
		["m_cv_close", "Close / open", "", "Closes the selected lines and splines into loops, or opens them.", toggle_closed, any.call(), any],
	]


func solid_items() -> Array:
	var any := func(): return not sel.is_empty()
	var two := func(): return sel.size() >= 2
	return [
		["m_cv_extrude", "Extrude", "E", "The selected edges pushed out along their plane's normal: closed ones become solids, open\nones walls. The mouse sets how far (snapped to the grid; Ctrl: free) - or type it.", begin_extrude, any.call(), any],
		["m_cv_revolve", "Revolve", "", "The profile turned round an axis: a two-vertex line selected with it, else the model's Y axis.\nThe mouse sets the angle (or type it): 360° makes a closed solid.", begin_revolve, any.call(), any],
		["m_cv_loft", "Loft", "", "A skin through the selected edges, in the order you picked them (closed ones: capped).", func(): make_part("loft"), two.call(), two],
		["m_cv_sweep", "Sweep", "", "The first selected edge (the profile) carried along the second (the path).", func(): make_part("sweep"), two.call(), two],
		["m_cv_pipe", "Pipe", "", "A round tube along each selected edge: the mouse sets its radius (or type it).", begin_pipe, any.call(), any],
		["m_cv_fill", "Fill", "", "The selected closed edges filled with flat faces.", func(): make_part("fill"), any.call(), any],
	]


func mesh_items() -> Array:
	var edit := func(): return ed.mode == "edit"
	var items := [
		["m_extrude", "Push / pull faces", "E", "The selected faces pulled out (or pushed in) along their normal, walls round them.", func(): ed.extrude(), edit.call(), edit],
	]
	var can_fillet := func(): return ed.mode == "edit" and ed.mesh_ops.has_method("begin_fillet")
	items.append(["m_fillet", "Fillet edges", "Ctrl+B", "The selected edges rounded: the mouse sets the width, the wheel the steps.", func(): ed.mesh_ops.call("begin_fillet"), can_fillet.call(), can_fillet])
	items.append(["m_inset", "Inset faces", "I", "A smaller copy of the selected faces inside them.", func(): ed.mesh_ops.begin_inset(), edit.call(), edit])
	items.append(["m_flatten", "Flatten", "Shift+Alt+F", "The selected vertices pressed onto a plane.", func(): ed.deform.begin_flatten(), edit.call(), edit])
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
			["front", "Front plane", "X and Y."], ["side", "Side plane", "Z and Y."], ["view", "View plane", "Square to the view."], ["selection", "Selection's plane", "The selected faces' or edge's."]]:
		planes.append([{"auto": "m_cv_plane", "ground": "m_top", "front": "m_front", "side": "m_side", "view": "m_ortho", "selection": "m_face"}[p[0]], p[1] + (" (on)" if plane_mode == p[0] else ""), "", p[2], set_plane_mode.bind(p[0]), plane_mode != p[0]])
	# (only what fits what's picked: a point under the mouse - what it can be; points picked - their
	# tools; a patch - its tools; curves - what's done to curves; nothing - drawing new ones)
	var xf := []
	for it in edit_items():
		if str(it[0]) in ["m_move", "m_rotate", "m_scale"]:
			xf.append([it[0], it[1].replace("curves", "points" if not picked_points().is_empty() else "patch"), it[2], it[3], it[4], true])
	var out := []
	if not pts.is_empty() and picked_points().is_empty():
		out.append(pts)   # (picked vertices: their own list has the modes - not twice)
	if not picked_points().is_empty():
		out.append(points_items() + [merge_dist_item()])
		out.append(xf)
		out.append(sym_items())
		return out
	if not pts.is_empty():
		var one := pick_handle(at)
		if one.is_empty():
			one = _any_handle(at)
		out.append(points_items().filter(func(it): return str(it[0]) in ["m_cv_pt_separate", "m_cv_pt_extrude", "m_cv_pt_delete"]).map(func(it):
			return [it[0], it[1], it[2], it[3], func(): pick_point(int(one[0]), int(one[1])); (it[4] as Callable).call(), true]))
		return out
	if not picked_patch().is_empty():
		out.append(patch_items() + [knife_item(), _remesh_of(_patch_part())])
		out.append(xf)
		return out
	if picked_solid() != null:
		out.append(xf.map(func(it): return [it[0], str(it[1]).replace("patch", "solid"), it[2], it[3], it[4], true]))
		out.append([merge_dist_item(), ["m_cv_merge", "Merge edges", "Ctrl+J", "The solid's edges joined wherever their ends meet (a shared vertex, or within the merge\ndistance): the straightest pairs made one edge - its mesh as it is.", merge_curves_selected, true]])
		out.append(sym_items() + [knife_item(), _remesh_of(picked_solid())])
		return out
	var p: MeshInstance3D = ed.part
	var bake := [["bake", "Bake solid", "", "The selected solid's tools and edges worked out into new edges on its surfaces: one Baked\nsolid, shaped by them only. Tools not touching it stay live.", _bake_btn, p != null and can_bake(p)]]
	bake.append(join_item())
	bake.append(remesh_item())
	bake.append(merge_dist_item())
	if not sel.is_empty():
		for g in [edit_items(), solid_items()]:
			var grp := []
			for it in g:
				grp.append([it[0], it[1], it[2], it[3], it[4], it[5]])
			out.append(grp)
		out.append(bake)
		return out
	out.append(sketch)
	out.append(prim_items())
	out.append(planes)
	out.append(bake + [knife_item()])
	out.append(sym_items())
	if ed.mode == "edit":
		var grp := []
		for it in mesh_items():
			grp.append([it[0], it[1], it[2], it[3], it[4], it[5]])
		out.append(grp)
	return out


## The menu's Auto join.
func join_item() -> Array:
	return ["m_cv_merge", "Auto join", "", "Solids that meet along an edge (an edge of each in the same place, the same shape, the surface\nstopping there on both sides) made one solid: one of the two edges kept, the meshes welded\nalong it - no gap, quads kept, each part its own material and bone weights still. Only solids\non the same bone join. The selected solids (two or more), else all. Done by itself after a\nconversion and a bake too.", func(): auto_join(), ed.model != null]


## Every tool the right-click menu's Curve modeling page can show, whatever's picked (one group).
func every_menu_item() -> Array:
	var out := []
	for t in TOOLS:
		out.append([TOOLS[t][1], TOOLS[t][0], "", "", Callable(), true])
	for ic in ["m_cv_plane", "m_cv_pt_smooth", "m_cv_pt_sharp", "bake"]:
		out.append([ic, ic, "", "", Callable(), true])
	return out + _all_items() + points_items() + patch_items() + prim_items() + sym_items() + [knife_item(), join_item(), merge_dist_item(), remesh_item()]


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


## The merge distance row (under the curves' line; made the first time it's needed).
func _merge_row() -> Control:
	var r = _panel_btns.get("w_merge_row")
	if r != null and is_instance_valid(r):
		return r
	if _info == null or not is_instance_valid(_info) or _info.get_parent() == null:
		return null
	var row := HBoxContainer.new()
	row.name = "MergeRow"
	row.add_theme_constant_override("separation", 6)
	var l := UI.label("Merge distance", 14, UI.TEXT_DIM)
	l.tooltip_text = EditorIcons.tip("Merge distance", "", "Merge edges joins edges whose ends are this close (metres) - a vertex they share is 0 apart.")
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(l)
	var sp := SpinBox.new()
	sp.min_value = 0.0
	sp.max_value = 1.0
	sp.step = 0.0001
	sp.value = merge_dist()
	sp.custom_minimum_size.x = 80
	sp.tooltip_text = l.tooltip_text
	sp.value_changed.connect(set_merge_dist)
	row.add_child(sp)
	_info.get_parent().add_child(row)
	_info.get_parent().move_child(row, _info.get_index() + 1)
	_panel_btns["w_merge_row"] = row
	return row


## The patch's resolution row (under the curves' line in the panel; made the first time it's needed).
func _patch_row() -> Control:
	var r = _panel_btns.get("w_patch_row")
	if r != null and is_instance_valid(r):
		return r
	if _info == null or not is_instance_valid(_info) or _info.get_parent() == null:
		return null
	var row := HBoxContainer.new()
	row.name = "PatchRow"
	row.add_theme_constant_override("separation", 6)
	var l := UI.label("Face subdivisions", 14, UI.TEXT_DIM)
	l.tooltip_text = EditorIcons.tip("Face subdivisions", "", "How many times the picked face has been subdivided - its quads cut in four (0: as baked),\neach cut a loop running on through the quads beyond, so the surface stays quads. Lower: back\nas it was.")
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(l)
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 3
	sp.step = 1
	sp.tooltip_text = l.tooltip_text
	sp.value_changed.connect(set_patch_level)
	row.add_child(sp)
	_info.get_parent().add_child(row)
	_info.get_parent().move_child(row, _info.get_index() + 1)
	_panel_btns["w_patch_row"] = row
	return row


func _refresh_panel() -> void:
	if has_meta("panel_hold") or not _drag.is_empty() and (_drag.has("group") or _drag.has("surface") or _drag.has("baked_curve")) and not _drag.has("coll"):
		set_meta("panel_after_drag", true)   # (a drag beginning: the overview filled once it's over - 10 ms off its first frame)
		return
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
			_solid_label.text = "%s · %d edge%s · %s" % [
				{"extrude": "Extrusion", "baked": "Baked", "edges": "Baked", "revolve": "Revolve", "pipe": "Pipe", "loft": "Loft", "sweep": "Sweep", "fill": "Fill",
					"bool": "Live " + {"union": "join", "difference": "cut", "intersection": "common"}.get(str(spec.get("op", "")), "boolean")}.get(kind, "Solid"),
				ids.size(), "" if ids.size() == 1 else "s", "follows its edges" if not cs.is_empty() else "edges gone: kept as is"]
			_solid_label.tooltip_text = "Made from its edges: it's made again whenever they (or its settings below) change."
			_solid_label.mouse_filter = Control.MOUSE_FILTER_STOP
			_solid_value_row.visible = kind in ["extrude", "revolve", "pipe"]
			_solid_value_label.text = {"extrude": "Height", "revolve": "Angle", "pipe": "Radius"}.get(kind, "")
			_solid_value.set_block_signals(true)   # (its range changed for this solid: clamping it isn't an edit)
			_solid_value.min_value = {"extrude": -100.0, "revolve": 1.0, "pipe": 0.001}.get(kind, -100.0)
			_solid_value.max_value = {"extrude": 100.0, "revolve": 360.0, "pipe": 10.0}.get(kind, 100.0)
			_solid_value.allow_lesser = kind == "extrude"
			_solid_value.allow_greater = kind != "revolve"
			_solid_value.step = 1.0 if kind == "revolve" else 0.001
			_solid_value.set_value_no_signal(float(spec.get("value", 0.0)))
			_solid_value.set_block_signals(false)
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
	_merge_row()
	if ed and ed.has_method("update_side_panel"):
		ed.update_side_panel()
	var mr = _panel_btns.get("w_merge_row")
	if mr != null and is_instance_valid(mr):
		(mr as Control).visible = sel.size() >= 2 or picked_solid() != null
	var pr = _patch_row()
	var pa_now := picked_patch()
	if pr:
		(pr as Control).visible = not pa_now.is_empty()
		if not pa_now.is_empty():
			((pr as Node).get_child(1) as SpinBox).set_value_no_signal(patch_level())
	if _info and picked_solid() != null:
		_info.text = "The whole solid picked (G / R / S move, turn, scale it; click its face for a face)."
	elif _info and not pa_now.is_empty():
		_info.text = "A face picked: %d edges (G / R / S move, turn, scale it)." % (pa_now["ids"] as Array).size()
	elif _info and not picked_points().is_empty():
		_info.text = "%d vertex%s picked (Shift+click: more) - the right-click menu: separate, merge, extrude..." % [picked_points().size(), "" if picked_points().size() == 1 else "s"]
	elif _info:
		if curves.is_empty():
			_info.text = "No edges yet - pick a sketch tool."
		elif sel.is_empty():
			_info.text = "%d edges - click one to pick it (Shift: more)." % curves.size()
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
	var picked := {}
	var pt_of := {}
	for e in picked_points():
		picked[Vector2i(int(e[0]), int(e[1]))] = true
		pt_of[int(e[0])] = true
	var gone := _solid_curve_ids()
	# (the curves themselves: lines in the 3D view, the solids hiding them - made again only when they change)
	_sync_curve_lines(own, pt_of, gone)
	var occ := not sel.is_empty() and _drag.is_empty() and op.is_empty()
	if occ:
		_begin_occ(true)   # (only the picked curves' points are drawn here: they need to know what hides them)
	else:
		set_meta("occlusion", {})   # (while something's dragged: its solid changes every frame - points drawn plain)
	for i in curves.size():
		if curves[i].get("hidden", false) or gone.has(int(curves[i].get("id", -1))):
			continue   # (hidden in the overview - or its solid picked whole: the solid alone shows)
		var on := i in sel
		var x := cx(curves[i], own)
		if on:
			var k: PackedVector3Array = baked(curves[i], x)["ctrl"]
			if str(curves[i]["kind"]) == "bezier" and k.size() == 4:
				layer.draw_dashed_line(_screen(k[0]), _screen(k[1]), Color(1, 1, 1, 0.6), 1.2, 4.0)
				layer.draw_dashed_line(_screen(k[3]), _screen(k[2]), Color(1, 1, 1, 0.6), 1.2, 4.0)
			for qj in k.size():
				var q := k[qj]
				var s := _screen(q)
				var a := 0.3 if _hidden(_mx() * q) else 1.0   # (a point behind the solid: faint)
				if picked.has(Vector2i(i, qj)):
					# (picked: bigger, in the picked colour, a ring round it)
					layer.draw_rect(Rect2(s - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.7 * a))
					layer.draw_rect(Rect2(s - Vector2(5.5, 5.5), Vector2(11, 11)), Color(PICKED_PT_COL, a))
					layer.draw_arc(s, 10.0, 0, TAU, 20, Color(PICKED_PT_COL, 0.8 * a), 1.5)
				else:
					layer.draw_rect(Rect2(s - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.6 * a))
					layer.draw_rect(Rect2(s - Vector2(3.5, 3.5), Vector2(7, 7)), Color(1, 1, 1, a))
	if occ:
		_end_occ()
	_sync_pick_overlay()
	_draw_drag()
	_draw_tangent_glow()
	_draw_knife()
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


## The curves as lines in the 3D view (shaders/curve_line.gdshader): each sampled curve a strip of screen-
## wide quads, picked ones amber and wider, with a dark rim - drawn with the scene, so solids hide what's
## behind them (the GPU's depth, not a ray a point). Kept beside the model (never saved); made again only
## when the curves, the picks or the solids' places change - turning the view costs nothing.
const LINE_CHUNK := 96

func _sync_curve_lines(own: Dictionary, pt_of: Dictionary, gone: Dictionary) -> void:
	if ed.model == null or ed.model.get_parent() == null:
		return
	var mi: MeshInstance3D = get_meta("lines_mi") if has_meta("lines_mi") and is_instance_valid(get_meta("lines_mi")) else null
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "CurveLines"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh: Shader = load("res://shaders/curve_line.gdshader")
		var rim := ShaderMaterial.new()
		rim.shader = sh
		rim.set_shader_parameter("dark", true)
		rim.set_shader_parameter("extra", 2.0)
		rim.render_priority = 10
		var top := ShaderMaterial.new()
		top.shader = sh
		top.render_priority = 11
		rim.next_pass = top
		mi.material_override = rim   # (its chunks' look; it draws nothing itself)
		mi.extra_cull_margin = 16384.0   # (pushed out on screen: never culled for its box)
		set_meta("lines_mi", mi)
	if mi.get_parent() != ed.model.get_parent():
		if mi.get_parent():
			mi.get_parent().remove_child(mi)
		ed.model.get_parent().add_child(mi)
	if mi.global_transform != _mx():
		mi.global_transform = _mx()
	if _drag.has("coll") and is_instance_valid(_drag["coll"]):
		_coll_lines(mi)   # (a collection dragged: its edges' lines carried along whole - none sampled again)
		return
	# (a drag: only the curves of the solids it changes can differ from last time - the rest's keys taken as
	# they were, nothing else hashed; the whole set hashed every frame was most of 8 ms)
	var ctx := hash([gone.keys(), get_meta("placed_sig", 0), own, curves.size()])   # (the placements themselves: a moved tool step's edges go with it)
	var drag_cis: Dictionary = _drag_line_curves()
	if not drag_cis.is_empty():
		mi.set_meta("last_cis", drag_cis)
	elif mi.has_meta("last_cis"):
		drag_cis = mi.get_meta("last_cis")   # (just let go or called off: only that drag's edges can have changed)
		mi.remove_meta("last_cis")
	var reuse: bool = not drag_cis.is_empty() and int(mi.get_meta("ctx", 0)) == ctx and (mi.get_meta("keys_by_i", PackedInt64Array()) as PackedInt64Array).size() == curves.size()
	if reuse:
		# (the picked ones then and now looked at again too - picked or not, a line's colour changes)
		var cur_sel := {}
		for i in sel:
			cur_sel[int(i)] = true
		var was_sel: Dictionary = mi.get_meta("sel_was", {})
		var was_pt: Dictionary = mi.get_meta("pt_was", {})
		if cur_sel != was_sel or pt_of != was_pt:
			drag_cis = drag_cis.duplicate()
			for d in [cur_sel, was_sel, pt_of, was_pt]:
				for i in d:
					drag_cis[int(i)] = true
	if not reuse:
		var sig := hash([curves, sel, pt_of.keys(), gone.keys(), get_meta("placed_sig", 0), own])
		if int(mi.get_meta("sig", 0)) == sig:
			return   # (nothing changed: turning the view costs one hash)
		mi.set_meta("sig", sig)
	else:
		mi.set_meta("sig", 0)
	var old_keys: PackedInt64Array = mi.get_meta("keys_by_i", PackedInt64Array())
	var keys_by_i := PackedInt64Array()
	keys_by_i.resize(curves.size())
	var clips := edge_clips()
	# (each curve's strip kept by its shape, place and look: a drag samples only the curves it changes)
	var memo: Dictionary = mi.get_meta("memo", {})
	var memo2 := {}
	# (strips not made yet sampled ~6 ms a frame at most - thousands of edges at once, after a conversion,
	# show over a few frames instead of freezing the editor for a third of a second)
	var spent := 0
	var whole := true
	# (the lines in chunks of LINE_CHUNK edges, a mesh each: a chunk is put together again only when one of
	# its strips changed - a drag on a model of thousands of edges remakes one small mesh, not all of them)
	var chunks := []
	var keys := []
	var ready := true
	for i in curves.size():
		if i % LINE_CHUNK == 0 and i > 0:
			chunks.append([keys, ready])
			keys = []
			ready = true
		var c: Dictionary = curves[i]
		if c.get("hidden", false) or gone.has(int(c.get("id", -1))):
			continue
		var ck: int
		if reuse and not drag_cis.has(i) and old_keys[i] != 0 and (memo.has(old_keys[i]) or memo2.has(old_keys[i])):
			ck = old_keys[i]   # (not one the drag changes: as it was)
		else:
			var lit := i in sel and not pt_of.has(i)
			var x := cx(c, own)
			var clip: Dictionary = clips.get(int(c.get("id", -1)), {})
			ck = hash([c, lit, x, clip])
			if not memo.has(ck) and not memo2.has(ck):
				keys.append(ck)
				if spent > 6000:
					whole = false
					ready = false
					continue   # (made next frame - its key not noted, so it's looked at again)
				var t0 := Time.get_ticks_usec()
				memo2[ck] = _line_strip(c, x, clip, SEL_COL if lit else CURVE_COL, 3.0 if lit else 2.2)
				spent += Time.get_ticks_usec() - t0
				keys_by_i[i] = ck
				continue
		keys_by_i[i] = ck
		keys.append(ck)
		if not memo2.has(ck):
			memo2[ck] = memo[ck]
	if not keys.is_empty():
		chunks.append([keys, ready])
	var parts := mi.get_children()
	for k in chunks.size():
		var ck_keys: Array = chunks[k][0]
		if not chunks[k][1]:
			continue   # (strips still to make: its old lines shown meanwhile)
		var cm: MeshInstance3D = parts[k] if k < parts.size() else null
		if cm == null:
			cm = MeshInstance3D.new()
			cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cm.material_override = mi.material_override
			cm.extra_cull_margin = 16384.0
			mi.add_child(cm)
			parts.append(cm)
		var h := hash(ck_keys)
		if int(cm.get_meta("sig", 0)) == h and (cm.mesh != null or ck_keys.is_empty()):
			continue
		cm.set_meta("sig", h)
		cm.transform = Transform3D()   # (carried along by a collection's drag till now: made where it is)
		var pos := PackedVector3Array()
		var oth := PackedFloat32Array()
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		for key in ck_keys:
			var strip: Array = memo2[key]
			pos.append_array(strip[0])
			oth.append_array(strip[1])
			cols.append_array(strip[2])
			uvs.append_array(strip[3])
		if pos.is_empty():
			cm.mesh = null
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_CUSTOM0] = oth
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_TEX_UV] = uvs
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		cm.mesh = m
	for k in range(parts.size() - 1, chunks.size() - 1, -1):
		mi.remove_child(parts[k])
		parts[k].queue_free()
	if not whole:
		for k in memo:
			if not memo2.has(k):
				memo2[k] = memo[k]   # (strips made earlier this round kept till it's done)
		mi.set_meta("sig", 0)   # (the rest next frame)
		set_meta("lines_due", true)   # (_process asks for the next frame's drawing - a deferred redraw ran again in the same frame, every pass in one)
	mi.set_meta("memo", memo2)
	mi.set_meta("keys_by_i", keys_by_i)
	mi.set_meta("ctx", ctx)
	var sel_now := {}
	for i in sel:
		sel_now[int(i)] = true
	mi.set_meta("sel_was", sel_now)
	mi.set_meta("pt_was", pt_of.duplicate())
	ed.view.request()


## (a drag) The curves (indices) whose lines it can change - every curve of the solids it changes, and
## the dragged ones; {} when nothing's dragged (every line looked at).
func _drag_line_curves() -> Dictionary:
	if _drag.is_empty() or not _drag.has("solids_only"):
		return {}
	if _drag.has("line_cis"):
		return _drag["line_cis"]
	var out := {}
	for p in _drag["solids_only"]:
		if p == null or not is_instance_valid(p):
			continue
		for id in spec_ids((p as Node).get_meta("curve_solid", {})):
			var j := _curve_index(int(id))
			if j >= 0:
				out[j] = true
	for e in _dragged_points():
		out[int(e[0])] = true
	for e in _drag.get("twins", []):
		out[int(e[0])] = true
	if not _drag.has("group") and not _drag.has("handle"):
		for i in sel:
			out[int(i)] = true
	out[-1] = true   # (never empty: a drag)
	return out


## One curve's strip of line quads (see _sync_curve_lines): [points, other ends + sides, colours, widths,
## triangles (from 0)].
func _line_strip(c: Dictionary, x: Transform3D, clip: Dictionary, col: Color, w: float) -> Array:
	var pos := PackedVector3Array()
	var oth := PackedFloat32Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var s := sample(c)
	if c.get("closed", false) and s.size() > 1:
		s.append(s[0])
	for j in s.size() - 1:
		if not clip.is_empty() and (not _in_clip(s[j], clip) or not _in_clip(s[j + 1], clip)):
			continue
		var a := x * s[j]
		var b := x * s[j + 1]
		if a.distance_squared_to(b) < 1e-14:
			continue
		# (a's two sides, then b's - seen from b the way to a runs backwards: its sides swap; two triangles
		# written out whole - no index buffer, so the strips join by appending, no renumbering)
		for corner in [[a, b, -1.0], [a, b, 1.0], [b, a, -1.0], [a, b, -1.0], [b, a, -1.0], [b, a, 1.0]]:
			pos.append(corner[0])
			var o: Vector3 = corner[1]
			oth.append_array(PackedFloat32Array([o.x, o.y, o.z, corner[2]]))
			cols.append(col)
			uvs.append(Vector2(w, 0))
	return [pos, oth, cols, uvs]


## The picked patch (or the whole picked solid) shaded in the 3D view: a see-through orange skin a hair
## outside its surface, drawn with the scene - hidden wherever the solid itself hides it (no faces from
## behind showing through). Kept beside the model (not one of its parts, never saved), placed where the
## part is; made again only when the patch or the part's mesh changes.
func _sync_pick_overlay() -> void:
	var pa := picked_patch()
	var ps := picked_solid()
	var target: MeshInstance3D = ps if ps != null else (pa["part"] if not pa.is_empty() else null)
	var mi: MeshInstance3D = get_meta("pick_mi") if has_meta("pick_mi") and is_instance_valid(get_meta("pick_mi")) else null
	if target == null or target.mesh == null or ed.model == null or ed.model.get_parent() == null:
		if mi and mi.visible:
			mi.visible = false
			ed.view.request()   # (the view draws on request: shown again without it)
		return
	if mi == null:
		mi = _pick_mi()
	if mi.get_parent() != ed.model.get_parent():
		if mi.get_parent():
			mi.get_parent().remove_child(mi)
		ed.model.get_parent().add_child(mi)
	var moved := mi.global_transform != target.global_transform
	mi.global_transform = target.global_transform
	if moved:
		ed.view.request()
	# (a face's overlay follows the drawn mesh only when it has the face's own triangles - a drag's frame
	# from its recipe's mesh; else it's the recipe's points, made again only when they change)
	var mk := target.mesh.get_instance_id()
	if ps == null and not pa.is_empty():
		var srcm: Array = target.mesh.get_meta("src", [])
		if srcm.size() != 2 or (srcm[1] as PackedInt32Array).size() != (pa["spec"]["mesh"]["t"] as Array).size():
			mk = hash(pa["spec"]["mesh"]["v"])
	var key := [target.get_instance_id(), mk, pa.get("tris", PackedInt32Array()) if ps == null else "all"]
	if mi.get_meta("key", []) != key:
		mi.set_meta("key", key)
		if ps != null:
			mi.mesh = target.mesh   # (the whole solid: its own mesh, shared)
		else:
			mi.mesh = _patch_mesh(target, pa)
	(mi.material_override as StandardMaterial3D).grow_amount = maxf(0.0015, target.mesh.get_aabb().get_longest_axis_size() * 0.002)
	var show := mi.mesh != null
	if mi.visible != show or mi.global_transform != target.global_transform or mi.get_meta("drawn_key", []) != key:
		mi.set_meta("drawn_key", key)
		ed.view.request()   # (the view draws on request)
	mi.visible = show


## The picked face's / solid's overlay (made once - ahead, while nothing's going on: its material made at the
## first pick was 7 ms of that frame).
func _pick_mi() -> MeshInstance3D:
	if has_meta("pick_mi") and is_instance_valid(get_meta("pick_mi")):
		return get_meta("pick_mi")
	var mi := MeshInstance3D.new()
	mi.name = "PickOverlay"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(PICKED_PT_COL, 0.3)
	mat.grow = true
	mat.grow_amount = 0.002
	mi.material_override = mat
	set_meta("pick_mi", mi)
	if ed and ed.model and ed.model.get_parent():
		ed.model.get_parent().add_child(mi)   # (in the scene at once - freed with it)
	return mi


## The patch's triangles as a mesh of their own, where the part shows them now (its drawn mesh when it
## has the same triangles, else the solid's own points).
static func _patch_mesh(p: MeshInstance3D, pa: Dictionary) -> ArrayMesh:
	var tris: PackedInt32Array = pa["tris"]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var spec: Dictionary = pa["spec"]
	var st: Array = spec["mesh"]["t"]
	var made: Array = p.mesh.get_meta("patch_arrays", []) if p.mesh else []
	if made.size() == 3 and (made[0] as PackedInt32Array) == tris and not (made[1] as PackedVector3Array).is_empty():
		var arr1 := []
		arr1.resize(Mesh.ARRAY_MAX)
		arr1[Mesh.ARRAY_VERTEX] = made[1]
		arr1[Mesh.ARRAY_NORMAL] = made[2]
		var m1 := ArrayMesh.new()
		m1.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr1)
		return m1   # (made on the worker with the drag's frame)
	var src: Array = p.mesh.get_meta("src", []) if p.mesh else []
	if src.size() == 2 and (src[1] as PackedInt32Array).size() == st.size():
		# (a drag's frame: its points as worked out - smooth normals over the patch's own triangles)
		var pv: PackedVector3Array = src[0]
		var tt: PackedInt32Array = src[1]
		var vn := {}
		for ti in tris:
			var a := pv[tt[ti * 3]]
			var fn := (pv[tt[ti * 3 + 2]] - a).cross(pv[tt[ti * 3 + 1]] - a)
			for j in 3:
				var vi := tt[ti * 3 + j]
				vn[vi] = (vn.get(vi, Vector3.ZERO) as Vector3) + fn
		for ti in tris:
			for j in 3:
				var vi := tt[ti * 3 + j]
				verts.append(pv[vi])
				norms.append((vn[vi] as Vector3).normalized())
		if verts.is_empty():
			return null
		var arr0 := []
		arr0.resize(Mesh.ARRAY_MAX)
		arr0[Mesh.ARRAY_VERTEX] = verts
		arr0[Mesh.ARRAY_NORMAL] = norms
		var m0 := ArrayMesh.new()
		m0.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr0)
		return m0
	# (otherwise its own points - the mesh drawn at rest is made of them; not read back from the drawn mesh)
	var dv := PackedVector3Array()
	var dn := PackedVector3Array()
	var di := PackedInt32Array()
	var same := false
	var mv: Array = spec["mesh"]["v"]
	for ti in tris:
		for j in 3:
			var q: Vector3
			var n := Vector3.ZERO
			if same:
				q = dv[di[ti * 3 + j]]
				if not dn.is_empty():
					n = dn[di[ti * 3 + j]]
			else:
				var vi := int(st[ti * 3 + j])
				q = Vector3(mv[vi * 3], mv[vi * 3 + 1], mv[vi * 3 + 2])
			verts.append(q)
			norms.append(n)
		if norms[norms.size() - 1] == Vector3.ZERO:
			var fn := (verts[verts.size() - 1] - verts[verts.size() - 3]).cross(verts[verts.size() - 2] - verts[verts.size() - 3]).normalized()
			for j in 3:
				norms[norms.size() - 1 - j] = fn
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


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


# --- auto join: solids meeting along one edge made one ---------------------------------------------

## Auto join: the solids (made from edges) that meet along an edge - an edge of each in nearly the same
## place, nearly the same shape, the surface stopping at it on both sides - made one solid each group: one
## of each pair of edges kept, the meshes welded along it (no gap, quads kept - auto_join.gd), each part of
## it its own material still, its bone weights from its old solid's. Only solids on the same bone join.
## Worked out on a worker; one undo step when it lands. `ps`: the solids to look at ([] - the selected, two
## or more, else all); `must`: only groups with one of these in. False - nothing to look at, or already going.
func auto_join(ps: Array = [], quiet := false, must: Array = []) -> bool:
	if ed == null or ed.model == null or has_meta("join_job"):
		return false
	if ps.is_empty():
		var sp0: Array = ed.selected_parts()
		ps = sp0 if sp0.size() >= 2 else ed.parts()
	var AJ: GDScript = load("res://scripts/editor/mesh/auto_join.gd")
	var inv := _mx().affine_inverse()
	var cand := []
	var solids := []
	var mats := []   # (every material, once: the solids' by their number in it)
	var users := {}   # curve id -> how many solids use it
	for q: MeshInstance3D in ed.parts():
		for id in spec_ids(q.get_meta("curve_solid", {})):
			users[int(id)] = int(users.get(int(id), 0)) + 1
	for p in ps:
		if not (p is MeshInstance3D) or not is_instance_valid(p) or not (p as Node).is_inside_tree() or not (p as Node3D).is_visible_in_tree():
			continue
		var sp: Dictionary = (p as Node).get_meta("curve_solid", {})
		if str(sp.get("kind", "")) != "edges" or not sp.has("mesh") or sp.has("faces") or (p as MeshInstance3D).mesh == null:
			continue
		if (sp.get("ids", []) as Array).any(func(id): return int(users.get(int(id), 0)) > 1):
			continue   # (an edge another solid uses too: left as it is)
		var cs := {}
		for id in sp.get("ids", []):
			cs[int(id)] = curve_by_id(int(id))
		var mat := _join_material(p)
		var mi := mats.find(mat)
		if mi < 0:
			mi = mats.size()
			mats.append(mat)
		var skinned: bool = (p as Node).has_meta("weight_src") or (p as MeshInstance3D).skin != null
		solids.append({"group": "%s|%s" % [str(sp.get("bone_name", "")), skinned], "xf": inv * (p as Node3D).global_transform, "spec": sp,
			"curves": cs, "mat": mi, "v": sp["mesh"]["v"], "t": sp["mesh"]["t"], "fv": sp.get("fv", []), "chains": sp.get("chains", []), "c0": sp.get("c0", {})})
		cand.append(p)
	if solids.size() < 2:
		if not quiet:
			ed._say("Auto join: no two solids made from edges to look at.")
		return false
	var must_i := {}
	for p in must:
		var i := cand.find(p)
		if i >= 0:
			must_i[i] = true
	var tol := merge_dist()
	var h := [null]
	var id := WorkerThreadPool.add_task(func(): h[0] = _join_compute(AJ, solids, tol, must_i), false, "ECurves: auto join")
	set_meta("join_job", [id, h, cand, solids, mats, quiet])
	if not quiet:
		ed._say("Auto join: looking for solids that meet...")
	return true


## A solid's material (what it's drawn with).
static func _join_material(p: MeshInstance3D) -> Material:
	if p.material_override:
		return p.material_override
	if p.mesh and p.mesh.get_surface_count() > 0:
		return p.get_surface_override_material(0) if p.get_surface_override_material(0) else p.mesh.surface_get_material(0)
	return null


## (on a worker) The pairs of edges, the groups of solids they join, each group joined. [{members (solids by
## number, the first kept), rels (each one's place in the first's), r (auto_join.join's result)}...].
static func _join_compute(AJ: GDScript, solids: Array, tol: float, must_i: Dictionary) -> Array:
	var pairs: Array = AJ.find_pairs(solids, tol)
	if pairs.is_empty():
		return []
	# groups: solids linked by pairs
	var root := range(solids.size())
	var find := func(x: int, rt: Array) -> int:
		while int(rt[x]) != x:
			x = int(rt[x])
		return x
	for pr in pairs:
		var a: int = find.call(int(pr[0]), root)
		var b: int = find.call(int(pr[2]), root)
		if a != b:
			root[b] = a
	var groups := {}
	for pr in pairs:
		var g: int = find.call(int(pr[0]), root)
		if not groups.has(g):
			groups[g] = {"members": [], "pairs": []}
		for k in [int(pr[0]), int(pr[2])]:
			if not k in groups[g]["members"]:
				(groups[g]["members"] as Array).append(k)
		(groups[g]["pairs"] as Array).append(pr)
	var out := []
	for g in groups:
		var mem: Array = groups[g]["members"]
		if not must_i.is_empty() and not mem.any(func(k): return must_i.has(int(k))):
			continue
		# (the one with the most triangles kept - the others brought into its place)
		mem.sort_custom(func(x, y): return (solids[x]["t"] as Array).size() > (solids[y]["t"] as Array).size())
		var a_xf: Transform3D = solids[mem[0]]["xf"]
		var parts := []
		var rels := {}
		var where := {}
		for li in mem.size():
			var s: Dictionary = solids[mem[li]]
			where[int(mem[li])] = li
			var rel: Transform3D = a_xf.affine_inverse() * (s["xf"] as Transform3D)
			rels[int(mem[li])] = rel
			var mv: Array = s["v"]
			var v := PackedVector3Array()
			v.resize(mv.size() / 3)
			for i in v.size():
				v[i] = rel * Vector3(mv[i * 3], mv[i * 3 + 1], mv[i * 3 + 2])
			var c0 := {}
			var src_c0: Dictionary = s["c0"]
			for k in src_c0:
				var cs := from_json([src_c0[k]])
				if not cs.is_empty():
					c0[k] = to_json([baked(cs[0], rel) if li > 0 else cs[0]])[0]
			parts.append({"v": v, "t": PackedInt32Array(s["t"]), "fv": s["fv"], "chains": s["chains"], "c0": c0, "mat": int(s["mat"])})
		var jp := []
		for pr in groups[g]["pairs"]:
			var ca := _chain_at(solids[int(pr[0])]["chains"], int(pr[1]))
			var cb := _chain_at(solids[int(pr[2])]["chains"], int(pr[3]))
			var la: int = where[int(pr[0])]
			var lb: int = where[int(pr[2])]
			if lb < la:
				# (the kept solid's edge kept: the pair turned round)
				jp.append([lb, cb, la, ca])
			else:
				jp.append([la, ca, lb, cb])
		jp.sort_custom(func(x, y): return int(x[2]) < int(y[2]))
		out.append({"members": mem, "rels": rels, "r": AJ.join(parts, jp)})
	return out


static func _chain_at(chains: Array, id: int) -> int:
	for ci in chains.size():
		if int(chains[ci]["id"]) == id:
			return ci
	return -1


## (each frame) An auto join worked out: put in - one undo step for all its groups.
func _join_step() -> void:
	var j: Array = get_meta("join_job")
	if not WorkerThreadPool.is_task_completed(int(j[0])):
		return
	WorkerThreadPool.wait_for_task_completion(int(j[0]))
	remove_meta("join_job")
	var res = j[1][0]
	var cand: Array = j[2]
	var solids: Array = j[3]
	var mats: Array = j[4]
	var quiet: bool = j[5]
	var groups := []
	var failed := 0
	for g: Dictionary in (res if res is Array else []):
		if (g["r"] as Dictionary).has("error"):
			failed += 1
			continue
		var ok := true
		for k in g["members"]:
			var p = cand[int(k)]
			# (changed since it was looked at - edited, deleted: that group left out)
			if not is_instance_valid(p) or not (p as Node).is_inside_tree() or (p as Node).get_meta("curve_solid", {}) != solids[int(k)]["spec"]:
				ok = false
		if ok:
			groups.append(g)
	if groups.is_empty():
		if not quiet or failed > 0:
			ed._say("Auto join: no solids meet along an edge%s." % ((" (%d group%s couldn't be welded)" % [failed, "" if failed == 1 else "s"]) if failed > 0 else ""))
		return
	var before := _state()
	var rows_before := []
	var rows_after := []
	var outs := []
	var n_parts := 0
	var n_shared := 0
	for g: Dictionary in groups:
		var mem: Array = g["members"]
		var r: Dictionary = g["r"]
		var a: MeshInstance3D = cand[int(mem[0])]
		var keep_ids := {}
		for id in r["ids"]:
			keep_ids[int(id)] = true
		# the others' edges brought into the kept one's place (it carries them now); the dropped ones gone
		var dropped := {}
		for li in range(1, mem.size()):
			var rel: Transform3D = g["rels"][int(mem[li])]
			for id in (solids[int(mem[li])]["spec"] as Dictionary).get("ids", []):
				var ci := _curve_index(int(id))
				if ci < 0:
					continue
				if keep_ids.has(int(id)):
					curves[ci] = baked(curves[ci], rel)
				else:
					dropped[int(id)] = true
		for id in (solids[int(mem[0])]["spec"] as Dictionary).get("ids", []):
			if not keep_ids.has(int(id)):
				dropped[int(id)] = true
		curves = curves.filter(func(c): return not dropped.has(int(c.get("id", -1))))
		n_shared += dropped.size()
		# the materials: the kept one's first
		var local := []
		var gl := []
		for k in mem:
			var gi: int = solids[int(k)]["mat"]
			if not gi in gl:
				gl.append(gi)
				local.append(mats[gi])
		var flat := []
		for q in (r["v"] as PackedVector3Array):
			flat.append_array([q.x, q.y, q.z])
		var a_spec: Dictionary = solids[int(mem[0])]["spec"]
		var spec := {"kind": "edges", "ids": r["ids"], "net": int(Time.get_ticks_usec() % 2000000000) + n_parts, "chains": r["chains"], "c0": r["c0"],
			"mesh": {"v": flat, "t": Array(r["t"])}, "fv": r["fv"], "tied": true, "qcaps": true, "sealed": false, "paired": false,
			"dense": (mem.map(func(k): return int((solids[int(k)]["spec"] as Dictionary).get("dense", 0))) as Array).max(), "joined": mem.size()}
		for key in ["converted", "up", "bone", "bone_name"]:
			if a_spec.has(key):
				spec[key] = a_spec[key]
		if local.size() > 1:
			spec["mats"] = {"anchors": (r["anchors"] as Array).map(func(an): return [an[0], gl.find(int(an[1]))]),
				"seams": r["seams"]}
		var metas_before := {}
		var metas_after := {}
		for key in ["ecurve_mats", "mats_mesh", "weight_src", "ecurve_skin", "weighted"]:
			metas_before[key] = a.get_meta(key) if a.has_meta(key) else null
			metas_after[key] = null
		metas_after["ecurve_mats"] = local if local.size() > 1 else null
		var wm := _joined_weights(a, mem.map(func(k): return cand[int(k)]), mem.map(func(k): return g["rels"][int(k)]))
		for key in ["weight_src", "ecurve_skin"]:
			metas_after[key] = wm.get(key, metas_before[key])
		rows_before.append([a, a_spec, metas_before, a.mesh])
		rows_after.append([a, spec, metas_after, null])
		for li in range(1, mem.size()):
			var q: MeshInstance3D = cand[int(mem[li])]
			outs.append([q, q.get_parent(), q.get_index()])
		n_parts += mem.size()
	sel = []
	_join_set(rows_after, [], outs, true)
	var after := _state()
	_join_set(rows_after, after, outs, true)
	ed._push("Auto join", _join_set.bind(rows_before, before, outs, false), _join_set.bind(rows_after, after, outs, true))
	ed._say("Auto join: %d solids made %d - %d shared edge%s welded%s." % [n_parts, groups.size(), n_shared, "" if n_shared == 1 else "s",
		(" (%d group%s couldn't be welded)" % [failed, "" if failed == 1 else "s"]) if failed > 0 else ""])


## Rows of [solid, recipe, metas ({name: value or null - none}), mesh or null] put in; `outs` taken out of the
## model (`gone`) or put back; then the edges as in state `st` (when it's given).
func _join_set(rows: Array, st: Array, outs: Array, gone: bool) -> void:
	for e in outs:
		var q: Node = e[0]
		if not is_instance_valid(q):
			continue
		if gone and q.get_parent():
			q.get_parent().remove_child(q)
		elif not gone and q.get_parent() == null and is_instance_valid(e[1]):
			(e[1] as Node).add_child(q)
			(e[1] as Node).move_child(q, mini(int(e[2]), (e[1] as Node).get_child_count() - 1))
	if gone:
		ed.sel_parts = (ed.sel_parts as Array).filter(func(q): return is_instance_valid(q) and q.is_inside_tree())
		if ed.part != null and (not is_instance_valid(ed.part) or not (ed.part as Node).is_inside_tree()):
			ed.select_part(null)
	for row in rows:
		var p: MeshInstance3D = row[0]
		if not is_instance_valid(p):
			continue
		p.set_meta("curve_solid", row[1])
		p.remove_meta("curve_solid_key")
		for key in (row[2] as Dictionary):
			if row[2][key] == null:
				p.remove_meta(key)
			else:
				p.set_meta(key, row[2][key])
		if row[3] != null:
			p.mesh = row[3]
	remove_meta("mat_parts_at")   # (the solids with materials of their own: looked for again)
	if not st.is_empty():
		_set_state(st)
	else:
		refresh_solids()
	ed._fill_parts()
	var t = _w("tree")
	if t:
		(t as Node).set_meta("sig", 0)
	_refresh_panel()


## The joined solid's bone weights: the solids' old meshes (where their weights come from) as one, in the
## kept one's place, their bones numbered as the kept one's skin numbers them (a bone it hasn't, added).
## {weight_src, ecurve_skin} - or {} (no weights).
func _joined_weights(a: MeshInstance3D, members: Array, rels: Array) -> Dictionary:
	var skin_of := func(q: MeshInstance3D) -> Skin:
		if q.has_meta("ecurve_skin"):
			return q.get_meta("ecurve_skin")
		if q.has_meta("src_skin"):
			return q.get_meta("src_skin")
		return q.skin
	if not members.any(func(q): return (q as Node).has_meta("weight_src")):
		return {}
	var base: Skin = skin_of.call(a)
	var skin: Skin = base.duplicate() if base else Skin.new()
	var bind_key := func(s: Skin, i: int) -> String:
		var nm := str(s.get_bind_name(i))
		return nm if nm != "" else "#%d" % s.get_bind_bone(i)
	var index := {}
	for i in skin.get_bind_count():
		index[bind_key.call(skin, i)] = i
	var out := ArrayMesh.new()
	for mi in members.size():
		var q: MeshInstance3D = members[mi]
		if not q.has_meta("weight_src"):
			continue
		var src: Mesh = q.get_meta("weight_src")
		var qs: Skin = skin_of.call(q)
		var remap := PackedInt32Array()
		if qs:
			for i in qs.get_bind_count():
				var k: String = bind_key.call(qs, i)
				if not index.has(k):
					index[k] = skin.get_bind_count()
					if str(qs.get_bind_name(i)) != "":
						skin.add_named_bind(qs.get_bind_name(i), qs.get_bind_pose(i))
					else:
						skin.add_bind(qs.get_bind_bone(i), qs.get_bind_pose(i))
				remap.append(int(index[k]))
		var rel: Transform3D = rels[mi]
		for si in src.get_surface_count():
			if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := src.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] = rel * v[i]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in n.size():
					n[i] = (rel.basis * n[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = n
			arr[Mesh.ARRAY_TANGENT] = null
			var flags := 0
			if arr[Mesh.ARRAY_BONES] != null and not remap.is_empty():
				var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				for i in b.size():
					b[i] = remap[b[i]] if b[i] >= 0 and b[i] < remap.size() else b[i]
				arr[Mesh.ARRAY_BONES] = b
				if b.size() == v.size() * 8:
					flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return {"weight_src": out, "ecurve_skin": skin}


## (each frame) Joined solids with more than one material: each time its mesh is made (one surface, as every
## solid made from edges is), split into a surface a material - every triangle the material of the solid it
## came from (found from its anchors, so edits and settles keep it).
func _mats_step() -> void:
	if not has_meta("mat_parts_at") or Time.get_ticks_msec() >= int(get_meta("mat_parts_at")):
		set_meta("mat_parts_at", Time.get_ticks_msec() + 500)   # (looked for twice a second - a model opened, an undo)
		var lst := []
		if ed.model:
			for p: MeshInstance3D in ed.parts():
				if (p.get_meta("curve_solid", {}) as Dictionary).has("mats"):
					lst.append(p)
		set_meta("mat_parts", lst)
	for p in get_meta("mat_parts", []):
		if is_instance_valid(p) and (p as Node).is_inside_tree():
			_mats_apply(p)


func _mats_apply(p: MeshInstance3D) -> void:
	var sp: Dictionary = p.get_meta("curve_solid", {})
	var md = sp.get("mats")
	var m := p.mesh as ArrayMesh
	if not (md is Dictionary) or m == null or (p.has_meta("mats_mesh") and p.get_meta("mats_mesh") == m):
		return
	var n := 0
	for an in md.get("anchors", []):
		n = maxi(n, int(an[1]) + 1)
	var mats: Array = p.get_meta("ecurve_mats") if p.has_meta("ecurve_mats") else []
	if mats.size() != n:
		# (opened from a file: saved a surface a material, in order - its materials from there)
		if m.get_surface_count() == n:
			mats = []
			for si in n:
				mats.append(m.surface_get_material(si))
			p.set_meta("ecurve_mats", mats)
		p.set_meta("mats_mesh", m)
		return
	if m.get_surface_count() != 1:
		p.set_meta("mats_mesh", m)
		return
	var AJ: GDScript = load("res://scripts/editor/mesh/auto_join.gd")
	var t: Array = sp["mesh"]["t"]
	var key := [int(sp.get("net", 0)), t.size(), hash(t)]
	var lab: PackedInt32Array
	var cached = p.get_meta("mats_lab") if p.has_meta("mats_lab") else null
	if cached is Array and (cached as Array)[0] == key:
		lab = cached[1]
	else:
		var mv: Array = sp["mesh"]["v"]
		var v := PackedVector3Array()
		v.resize(mv.size() / 3)
		for i in v.size():
			v[i] = Vector3(mv[i * 3], mv[i * 3 + 1], mv[i * 3 + 2])
		var seam := {}
		var chains: Array = sp.get("chains", [])
		for ci in chains.size():
			if int(chains[ci]["id"]) in (md.get("seams", []) as Array).map(func(x): return int(x)):
				seam[ci] = true
		lab = AJ.tri_materials(v, PackedInt32Array(t), sp.get("fv", []), seam, md.get("anchors", []))
		p.set_meta("mats_lab", [key, lab])
	var nt := 0
	var idx = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	nt = (idx as PackedInt32Array).size() / 3 if idx != null else 0
	if nt != lab.size():
		return   # (drawn from other triangles than its recipe's - a moment mid-edit: split once they agree)
	var out: ArrayMesh = AJ.split_by(m, lab, mats)
	p.mesh = out
	p.set_meta("mats_mesh", out)


# --- merge by distance ---------------------------------------------------------------------------------

## Merge by distance: the vertices within the merge distance of each other made one - next to each other
## on one edge: the later one dissolved (its edge keeps its shape through the other); on different edges:
## moved together to their middle, so the edges meet there (the solids made from them follow). The picked
## vertices (two or more), else the picked edges', else the picked solid's, else every edge's. One undo
## step. How many vertices were merged away or welded.
func merge_by_distance() -> int:
	var md := maxf(merge_dist(), 1e-6)
	var scope := {}   # curve index -> {j: true} (or true: all its points)
	var pp := picked_points()
	if pp.size() >= 2:
		for e in pp:
			if not scope.has(int(e[0])):
				scope[int(e[0])] = {}
			scope[int(e[0])][int(e[1])] = true
	elif not sel.is_empty():
		for ci in sel:
			scope[int(ci)] = true
	elif picked_solid() != null:
		for id in spec_ids(picked_solid().get_meta("curve_solid", {})):
			var ci := _curve_index(int(id))
			if ci >= 0:
				scope[ci] = true
	else:
		for ci in curves.size():
			scope[ci] = true
	var own := owner_xfs()
	var pts := []   # [curve, point, position in the model]
	for ci in scope:
		var c: Dictionary = curves[ci]
		if not str(c.get("kind", "")) in ["line", "spline", "path"]:
			continue   # (a circle's, an arc's points aren't its vertices along it)
		var x := cx(c, own)
		var k: PackedVector3Array = c["ctrl"]
		for j in k.size():
			if scope[ci] is Dictionary and not (scope[ci] as Dictionary).has(j):
				continue
			pts.append([ci, j, x * k[j]])
	if pts.size() < 2:
		ed._say("Merge by distance: no vertices to merge.")
		return 0
	# groups of points within the distance of each other (a grid of cells the distance across)
	var root := range(pts.size())
	var find := func(i: int) -> int:
		while int(root[i]) != i:
			root[i] = root[int(root[i])]
			i = int(root[i])
		return i
	var grid := {}
	for i in pts.size():
		var cell := Vector3i(((pts[i][2] as Vector3) / md).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for o in grid.get(cell + Vector3i(dx, dy, dz), []):
						if (pts[o][2] as Vector3).distance_to(pts[i][2]) <= md:
							var a: int = find.call(i)
							var b: int = find.call(o)
							if a != b:
								root[b] = a
		if not grid.has(cell):
			grid[cell] = []
		(grid[cell] as Array).append(i)
	var groups := {}
	for i in pts.size():
		var g: int = find.call(i)
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append(i)
	var before := _state()
	var merged := 0
	var drop := {}   # curve -> [points to dissolve]
	for g in groups:
		var mem: Array = groups[g]
		if mem.size() < 2:
			continue
		# (on one edge, next to each other: the later ones dissolved - each edge keeps one point here)
		var kept := []
		var by_curve := {}
		for i in mem:
			var ci: int = pts[i][0]
			if not by_curve.has(ci):
				by_curve[ci] = []
			(by_curve[ci] as Array).append(int(pts[i][1]))
		for ci in by_curve:
			var js: Array = by_curve[ci]
			js.sort()
			var c: Dictionary = curves[ci]
			var n: int = (c["ctrl"] as PackedVector3Array).size()
			var closed := bool(c.get("closed", false))
			var keep: int = js[0]
			if closed and js.size() > 1 and js.has(0) and js.has(n - 1) and not js.has(1):
				keep = n - 1   # (round a closed edge's start: its last point next to its first)
			for j in js:
				if j == keep:
					continue
				var nb: bool = absi(j - keep) == 1 or (closed and absi(j - keep) == n - 1) or js.has(j - 1) or js.has(j + 1)
				var ends_baked: bool = not closed and (j == 0 or j == n - 1) and _any_baked([ci])
				if nb and not ends_baked:
					if not drop.has(ci):
						drop[ci] = []
					(drop[ci] as Array).append(j)
				else:
					kept.append([ci, j])
			kept.append([ci, keep])
		if kept.size() < 2:
			continue
		# (on different edges: together at their middle)
		var mid := Vector3.ZERO
		for e in kept:
			mid += cx(curves[e[0]], own) * (curves[e[0]]["ctrl"][e[1]] as Vector3)
		mid /= kept.size()
		var apart := false
		for e in kept:
			if (cx(curves[e[0]], own) * (curves[e[0]]["ctrl"][e[1]] as Vector3)).distance_to(mid) > 1e-9:
				apart = true
		if not apart:
			continue   # (in one place already: welded before)
		for e in kept:
			var x := cx(curves[e[0]], own)
			var k: PackedVector3Array = curves[e[0]]["ctrl"]
			var was := k[e[1]]
			k[e[1]] = x.affine_inverse() * mid
			curves[e[0]]["ctrl"] = k
			_move_corner(int(e[0]), was, k[e[1]])
			merged += 1
		merged -= 1
	for ci in drop:
		var js: Array = drop[ci]
		js.sort()
		js.reverse()
		var c: Dictionary = (curves[ci] as Dictionary).duplicate(true)
		var closed := bool(c.get("closed", false))
		for j in js:
			var k: PackedVector3Array = c["ctrl"]
			if k.size() <= (3 if closed else 2):
				break
			k.remove_at(j)
			c["ctrl"] = k
			for key_ in ["sharp", "radii", "tin", "tout"]:
				if c.has(key_) and j < (c[key_] as Variant).size():
					var arr = c[key_]
					arr.remove_at(j)
					c[key_] = arr
			merged += 1
		curves[ci] = c
	if merged == 0:
		ed._say("Merge by distance: no vertices within %s m of each other." % String.num(md, 4))
		return 0
	set_meta("points", [])
	_changed("Merge by distance", before)
	ed._say("Merge by distance: %d vertex%s merged (within %s m)." % [merged, "" if merged == 1 else "es", String.num(md, 4)])
	return merged


## The menu's Merge by distance.
func merge_dist_item() -> Array:
	return ["m_cv_pt_merge", "Merge by distance", "Alt+M", "Vertices within the merge distance (the Mirror box's Merge) of each other made one: next to\neach other on one edge - one dissolved; on different edges - moved together to their middle,\nso the edges meet there. The picked vertices, else the picked edges' or solid's, else all.", func(): merge_by_distance(), not curves.is_empty()]


# --- extrude face ------------------------------------------------------------------------------------------

## Extrude face (the picked face's menu, E): the face pulled out along its normal - the mouse sets how far
## (or a typed number; minus: pushed in) - walls of quads from its old rim to its new one, rows about as tall
## as its quads are wide; a copy of each of its edges at the new rim and a straight edge up each corner, so
## the solid stays made of its edges. One undo step.
func begin_face_extrude() -> void:
	var pa := picked_patch()
	if pa.is_empty():
		ed._say("Extrude face: click on a baked solid's face first.")
		return
	stop()
	var p: MeshInstance3D = pa["part"]
	var spec := _rebase_part(p)
	var fs := _faces_of(spec)
	var vv: PackedVector3Array = fs["v"]
	var tt: PackedInt32Array = fs["t"]
	var n := Vector3.ZERO
	var ctr := Vector3.ZERO
	var area := 0.0
	for ti in pa["tris"]:
		var a := vv[tt[ti * 3]]
		var b := vv[tt[ti * 3 + 1]]
		var c := vv[tt[ti * 3 + 2]]
		var cr := (c - a).cross(b - a)   # (Godot's front faces wind the other way round: outwards)
		n += cr
		ctr += (a + b + c) / 3.0 * cr.length()
		area += cr.length()
	if n.length() < 1e-12 or area <= 0.0:
		ed._say("Extrude face: that face has no area.")
		return
	n = n.normalized()
	ctr /= area
	var px := _mx().affine_inverse() * p.global_transform
	op = {"kind": "face_extrude", "value": 0.0, "start": 0.0, "before": _state(), "centre": px * ctr, "x": xf_arr(px),
		"n": (px.basis * n).normalized(), "n_local": n, "m0": ed._mouse, "orig": curves.duplicate(true),
		"part": p, "spec": spec, "v": vv, "t": tt, "tris": pa["tris"], "ids": (pa["ids"] as Array).duplicate()}
	typed = ""
	_op_update()
	_op_hint()


## The picked face pulled out by `d` (part space): {v, t, fv, new: [[old chain index, new chain index]...],
## corners: [[bottom point, top point]...], rows} - the face's points moved (its rim's copied), walls of
## `rows` quads high from the old rim to the new.
static func face_extruded(v0: PackedVector3Array, t0: PackedInt32Array, fv0: Array, chains: Array, tris: PackedInt32Array, ids: Array, n: Vector3, d: float) -> Dictionary:
	var in_f := {}
	for ti in tris:
		in_f[ti] = true
	var dir_e := {}   # "a_b" (as the face's triangles run) -> true
	var fverts := {}
	for ti in tris:
		for j in 3:
			var a := t0[ti * 3 + j]
			var b := t0[ti * 3 + (j + 1) % 3]
			dir_e[Vector2i(a, b)] = true
			fverts[a] = true
	var rim := []   # the face's rim, as its triangles run: [a, b]
	var rim_v := {}
	for e in dir_e:
		if not dir_e.has(Vector2i(e.y, e.x)):
			rim.append([e.x, e.y])
			rim_v[e.x] = true
			rim_v[e.y] = true
	if rim.is_empty():
		return {}
	var L := 0.0
	for e in rim:
		L += v0[e[0]].distance_to(v0[e[1]])
	L /= rim.size()
	var rows := clampi(roundi(absf(d) / maxf(L, 1e-6)), 1, 64)
	var v := v0.duplicate()
	var off := n * d
	# (inside the face: its points moved; on its rim: copied, a copy a row)
	var top := {}
	var layer := []   # each row's copy of the rim, rows 1 .. rows - 1
	for k in range(1, rows):
		var lk := {}
		for vi in rim_v:
			lk[vi] = v.size()
			v.append(v0[vi] + off * float(k) / rows)
		layer.append(lk)
	for vi in fverts:
		if rim_v.has(vi):
			top[vi] = v.size()
			v.append(v0[vi] + off)
		else:
			v[vi] = v0[vi] + off
			top[vi] = vi
	var t := t0.duplicate()
	for ti in tris:
		for j in 3:
			t[ti * 3 + j] = top[t0[ti * 3 + j]]
	var at := func(vi: int, k: int) -> int:   # (rim point vi at row k: 0 the old rim, rows the new)
		if k == 0:
			return vi
		if k == rows:
			return top[vi]
		return layer[k - 1][vi]
	for e in rim:
		for k in rows:
			var a0: int = at.call(e[0], k)
			var b0: int = at.call(e[1], k)
			var a1: int = at.call(e[0], k + 1)
			var b1: int = at.call(e[1], k + 1)
			t.append_array(PackedInt32Array([a0, b0, b1, a0, b1, a1]))
	# its edges: each of the face's edges again at the new rim; a straight edge up each corner
	var fv := fv0.duplicate(true)
	var face_ci := {}
	for ci in chains.size():
		if int(chains[ci]["id"]) in ids:
			face_ci[ci] = chains.size() + face_ci.size()
	var on := {}
	for e in fv0:
		if rim_v.has(int(e[0])) and face_ci.has(int(e[1])):
			fv.append([top[int(e[0])], face_ci[int(e[1])], float(e[2])])
			if not on.has(int(e[0])):
				on[int(e[0])] = {}
			on[int(e[0])][int(e[1])] = true
	var corners := []
	var nci := chains.size() + face_ci.size()
	for vi in on:
		if (on[vi] as Dictionary).size() < 2:
			continue
		fv.append([vi, nci, 0.0])
		for k in range(1, rows):
			fv.append([layer[k - 1][vi], nci, float(k) / rows])
		fv.append([top[vi], nci, 1.0])
		corners.append([v0[vi], v0[vi] + off])
		nci += 1
	var made := []
	for ci in face_ci:
		made.append([ci, face_ci[ci]])
	made.sort_custom(func(x, y): return int(x[1]) < int(y[1]))
	return {"v": v, "t": t, "fv": fv, "new": made, "corners": corners, "rows": rows}


## (the operation) The extruded face shown over its solid.
func _face_extrude_preview(d: float) -> void:
	var r := face_extruded(op["v"], op["t"], (op["spec"] as Dictionary).get("fv", []), (op["spec"] as Dictionary).get("chains", []), op["tris"], op["ids"], op["n_local"], d)
	if r.is_empty() or absf(d) < 1e-6:
		_clear_preview()
		return
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	_show_preview(EN.shaded(r["v"], r["t"], PackedInt32Array(), null))


## (the operation, let go) The face extruded into its solid: its mesh, its new edges. One undo step.
func _face_extrude_apply(d: float, before: Array) -> void:
	var p = op.get("part") if not op.is_empty() else null
	var o: Dictionary = get_meta("face_op", {})
	if absf(d) < 1e-6 or o.is_empty():
		return
	p = o["part"]
	var spec: Dictionary = o["spec"]
	var chains: Array = (spec.get("chains", []) as Array).duplicate(true)
	var r := face_extruded(o["v"], o["t"], spec.get("fv", []), chains, o["tris"], o["ids"], o["n_local"], d)
	if r.is_empty() or not is_instance_valid(p):
		ed._say("Extrude face: nothing to pull out there.")
		return
	var off: Vector3 = (o["n_local"] as Vector3) * d
	var ids: Array = (spec.get("ids", []) as Array).duplicate()
	var c0: Dictionary = (spec.get("c0", {}) as Dictionary).duplicate()
	for pr in r["new"]:
		var src := curve_by_id(int(chains[int(pr[0])]["id"]))
		if src.is_empty():
			continue
		var nc := _fresh(baked(src, Transform3D(Basis(), off)))
		nc["name"] = "%s %s" % [str(src.get("name", "Edge")), "pulled out"]
		curves.append(nc)
		ids.append(int(nc["id"]))
		chains.append({"id": int(nc["id"]), "closed": bool(src.get("closed", false))})
		c0[str(int(nc["id"]))] = to_json([nc])[0]
	var nf: Vector3 = o["n_local"]
	for cn in r["corners"]:
		var a: Vector3 = cn[0]
		var b: Vector3 = cn[1]
		var side := nf.cross(Vector3.UP if absf(nf.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var lc := _fresh({"kind": "line", "ctrl": PackedVector3Array([a, b]), "closed": false, "n": side})
		lc["name"] = "%s side edge" % str(p.name)
		curves.append(lc)
		ids.append(int(lc["id"]))
		chains.append({"id": int(lc["id"]), "closed": false})
		c0[str(int(lc["id"]))] = to_json([lc])[0]
	var flat := []
	for q in (r["v"] as PackedVector3Array):
		flat.append_array([q.x, q.y, q.z])
	spec = spec.duplicate()
	spec["mesh"] = {"v": flat, "t": Array(r["t"])}
	spec["fv"] = r["fv"]
	spec["chains"] = chains
	spec["ids"] = ids
	spec["c0"] = c0
	spec.erase("oriented")
	spec.erase("paired")
	spec.erase("res_stack")
	_set_edges_spec(p, spec)
	set_meta("patch", {})
	_changed("Extrude face", before)
	ed._say("Extruded: %.3f m, %d row%s of quads, %d new edges." % [d, int(r["rows"]), "" if int(r["rows"]) == 1 else "s", (r["new"] as Array).size() + (r["corners"] as Array).size()])


# --- remesh: a solid laid out again by the topology rules ---------------------------------------------------

## The menu's Remesh.
func remesh_item() -> Array:
	return ["m_cv_patch_finer", "Remesh", "", "The selected solid's mesh laid out again by the topology rules (the editor manual's \"How\nECurves lays out its quads\"): each face between its edges quads in grids that follow them,\nfew poles, even and square; sharp folds followed by rows. Its edges stay as they are. Worked\nout in the background; one undo step.", func(): remesh_solid(ed.part), ed.part != null and str((ed.part.get_meta("curve_solid", {}) as Dictionary).get("kind", "")) == "edges"]


## Remesh for solid `p` (the picked face's or the picked solid's) - else the selected one.
func _remesh_of(p) -> Array:
	var it := remesh_item()
	if p is MeshInstance3D and is_instance_valid(p):
		it[4] = func(): remesh_solid(p)
		it[5] = str(((p as Node).get_meta("curve_solid", {}) as Dictionary).get("kind", "")) == "edges"
	return it


## The part the picked face is on (or null).
func _patch_part():
	var pa: Dictionary = get_meta("patch", {})
	if pa.is_empty():
		return null
	var o = instance_from_id(int(pa.get("part", 0)))
	return o if o is MeshInstance3D else null


## Solid `p` (made of edges) laid out again by EdgeNet.grid_any - on a worker; put in when done, one undo step.
## only_chains: only the faces along those edges (chain indices) laid out - the rest kept exactly.
## merge: put into the undo step on top now (the edit it follows) rather than one of its own.
func remesh_solid(p, label := "Remesh", only_chains := [], merge := false) -> void:
	if not (p is MeshInstance3D) or not is_instance_valid(p) or str(((p as Node).get_meta("curve_solid", {}) as Dictionary).get("kind", "")) != "edges":
		ed._say("Remesh: select a solid made of edges.")
		return
	if has_meta("remesh_job"):
		ed._say("Remesh: one is still being worked out.")
		return
	var spec := _rebase_part(p)
	var fs := _faces_of(spec)
	var v: PackedVector3Array = fs["v"]
	var t: PackedInt32Array = fs["t"]
	var fv: Array = (spec.get("fv", []) as Array).map(func(e): return [int(e[0]), int(e[1]), float(e[2])])
	var chains: Array = spec.get("chains", [])
	var area := 0.0
	for i in range(0, t.size(), 3):
		area += (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]]).length() * 0.5
	var L := clampf(sqrt(area / 380.0), 0.003, 1.0) * 0.55
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var only := {}
	if not only_chains.is_empty():
		var on_cut := {}
		for e in fv:
			if only_chains.has(int(e[1])):
				on_cut[int(e[0])] = true
		for i in range(0, t.size(), 3):
			if on_cut.has(t[i]) or on_cut.has(t[i + 1]) or on_cut.has(t[i + 2]):
				only[i / 3] = true
		if only.is_empty():
			return
	var h := [null]
	var id := WorkerThreadPool.add_task(func(): h[0] = EN.grid_any(v, t, fv, chains, L, true, only), false, "ECurves: remesh")
	var top = null
	if merge:
		var stack: Array = ed._eundo if ed.mode == "edit" else ed._undo
		top = stack.back() if not stack.is_empty() else null
	set_meta("remesh_job", [id, h, p, spec, _state(), label, str((p as Node).get_meta("curve_solid", {})).hash(), top])
	if not merge:
		ed._say("%s: laying %s out..." % [label, (p as Node).name])


## The remesh going on (`j`: its job; empty: none - the bar taken away) shown in the view's lower left corner:
## the solid, what the layout's doing and a bar of how far it's got (EdgeNet.progress).
func _remesh_bar(j: Array) -> void:
	var box: Control = get_meta("remesh_bar") if has_meta("remesh_bar") and is_instance_valid(get_meta("remesh_bar")) else null
	if j.is_empty() or ed == null or ed.view == null:
		if box:
			box.queue_free()
			remove_meta("remesh_bar")
		return
	if box == null:
		box = PanelContainer.new()
		box.name = "RemeshProgress"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.035, 0.015, 0.85)
		sb.border_color = Color(1.0, 0.55, 0.15, 0.7)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 8
		box.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(vb)
		var l := UI.label("", 14)
		l.name = "What"
		vb.add_child(l)
		var l2 := UI.label("", 14, UI.TEXT_DIM)
		l2.name = "Stage"
		vb.add_child(l2)
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(280, 12)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(bar)
		ed.view.add_child(box)
		set_meta("remesh_bar", box)
	var EN: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var pr: Array = EN.get("progress")
	var p = j[2]
	var lab: Label = box.find_child("What", true, false)
	var lab2: Label = box.find_child("Stage", true, false)
	var bar: ProgressBar = box.find_child("Bar", true, false)
	var label := str(j[5]) if j.size() > 5 else "Remesh"
	lab.text = "%s: %s  %d%%" % [label, (p as Node).name if is_instance_valid(p) else "", roundi(float(pr[0]) * 100.0)]
	var st := str(pr[1])
	lab2.text = (st.left(1).to_upper() + st.substr(1)) if st != "" else ""
	bar.value = float(pr[0])
	# (the view's lower left corner, a margin in)
	box.reset_size()
	box.position = Vector2(12.0, ed.view.size.y - box.size.y - 12.0)


## (each frame) A remesh worked out: put in.
func _remesh_step() -> void:
	var j: Array = get_meta("remesh_job")
	if not WorkerThreadPool.is_task_completed(int(j[0])):
		_remesh_bar(j)
		return
	WorkerThreadPool.wait_for_task_completion(int(j[0]))
	remove_meta("remesh_job")
	_remesh_bar([])
	var g = j[1][0]
	var p = j[2]
	if not is_instance_valid(p) or not (p as Node).is_inside_tree():
		return
	if not (g is Dictionary) or (g as Dictionary).is_empty():
		ed._say("Remesh: %s couldn't be laid out again - kept as it was." % (p as Node).name)
		return
	if j.size() > 6 and str((p as Node).get_meta("curve_solid", {})).hash() != int(j[6]):
		ed._say("Remesh: %s was changed meanwhile - kept as you left it (Remesh it again)." % (p as Node).name)
		return
	var spec: Dictionary = j[3]
	var flat := []
	for q in (g["v"] as PackedVector3Array):
		flat.append_array([q.x, q.y, q.z])
	spec["mesh"] = {"v": flat, "t": Array(g["t"])}
	spec["fv"] = g["fv"]
	for k in ["oriented", "paired", "res_stack", "orig"]:
		spec.erase(k)
	_set_edges_spec(p, spec)
	refresh_solids()
	var top = j[7] if j.size() > 7 else null
	var stack: Array = ed._eundo if ed.mode == "edit" else ed._undo
	if top != null and not stack.is_empty() and is_same(stack.back(), top):
		# (the edit it follows still the last step: its redo now ends with this layout - one step)
		(top as Dictionary)["redo"] = _set_state.bind(_state())
		refresh_solids()
		_refresh_panel()
		layer.queue_redraw()
		return
	_record(str(j[5]) if j.size() > 5 else "Remesh", j[4])
	ed._say("Remeshed %s: %d triangles%s." % [(p as Node).name, (g["t"] as PackedInt32Array).size() / 3, (", %d faces kept as they were" % int(g.get("kept", 0))) if int(g.get("kept", 0)) > 0 else ""])

