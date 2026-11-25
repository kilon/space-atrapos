extends Node
## The mesh editor's deforming tools for edit mode (a node of the editor, `ed`):
## - **Curve deform** (V; transform kind "CRV"): a cubic curve laid along the selection, from one
##   end of its longest extent to the other - two end points and two handles dragged in the view.
##   Each moved point keeps its offset from the straight line, carried (and turned) by the curve
##   at its place along it: a straight row of points bends into the curve.
## - **Flatten** (Shift+Alt+F; kind "FLT"): the selected points pushed onto a plane through their
##   middle - the best fit (least squares; the selected faces' average normal when faces are
##   selected) or, X / Y / Z typed, the part's own axis plane - by a strength from the mouse or a digit.
## Both are transforms of the editor's (begin_transform / _xf_update / confirm_transform /
## _cancel_xf): proportional editing, symmetry and the mirror's clipping apply, one undo step.
## Their state lives in the editor's `xf`; while one runs a small bar shows in the view
## (keep / cancel; Flatten's plane), and the curve is drawn over the model (MeshView.curve_pts).

const MeshView := preload("res://scripts/editor/mesh/mesh_view.gd")
const KINDS := ["CRV", "FLT"]
const HANDLE_PX := 12.0   # (how near the mouse picks an end point or handle)

var ed: Control
var _bar: PanelContainer
var _crv_btns: Array = []
var _flt_btns: Array = []   # fit, X, Y, Z
var _shown := ""
## Curve deform: the selected points snapped exactly onto the curve (spaced along it as they were
## along the straight line) - off: each keeps its offset from the line (an area bent by the curve).
## (Kept as a meta, not a variable: hot reloaded into an open editor.)
func snaps() -> bool:
	return bool(get_meta("snap_on_curve", true))


func setup(editor: Control) -> void:
	ed = editor
	name = "DeformTools"


# --- starting -------------------------------------------------------------------

## Curve deform (V): the curve along the selection, its ends and handles dragged in the view.
func begin_curve() -> void:
	if ed.mode != "edit" or ed.em == null:
		ed._say("Curve deform works on points: Tab into edit mode and select some.")
		return
	if ed.selected_points().size() < 2:
		ed._say("Curve deform needs at least two points selected.")
		return
	ed.begin_transform("CRV")
	if ed.xf.get("kind", "") != "CRV":
		return
	var line := curve_line(ed.em.points, ed.xf["sel"])
	if line.is_empty():
		ed._cancel_xf()
		ed._say("Curve deform: the selected points are all in one place.")
		return
	for k in line:
		ed.xf[k] = line[k]
	# (the curve fitted through the selected points - and each point bound to its place on it: none
	# moves till the curve is changed)
	# (faces selected - face mode, or Auto with whole faces picked: the curve goes through their
	# middles and carries the faces whole, every point keeping its offset - no snapping)
	var centres := face_centres(ed.em, ed.sel_t) if ed.sel_kind in [2, 3] else PackedVector3Array()
	ed.xf["crv_faces"] = centres.size() >= 2
	var cp: PackedVector3Array
	if centres.size() >= 2:
		var fl := curve_line(centres, PackedInt32Array(range(centres.size())))
		cp = fit_curve(centres, PackedInt32Array(range(centres.size())), fl) if not fl.is_empty() else fit_curve(ed.em.points, ed.xf["sel"], line)
	else:
		cp = fit_curve(ed.em.points, ed.xf["sel"], line)
	ed.xf["crv_p"] = cp
	ed.xf["crv_start"] = cp.duplicate()
	var bind := bind_points(ed.xf["orig"], cp)
	for k in bind:
		ed.xf[k] = bind[k]
	ed.xf["crv_drag"] = -1
	ed.xf["crv_hot"] = -1
	ed.xf["crv_snap"] = snaps()
	ed._xf_update()


## Flatten (Shift+Alt+F): the selected points onto a plane - the mouse sets how far.
func begin_flatten() -> void:
	if ed.mode != "edit" or ed.em == null:
		ed._say("Flatten works on points: Tab into edit mode and select some.")
		return
	if ed.selected_points().size() < 3:
		ed._say("Flatten needs at least three points selected.")
		return
	ed.begin_transform("FLT")
	if ed.xf.get("kind", "") != "FLT":
		return
	var sel: PackedInt32Array = ed.xf["sel"]
	ed.xf["flt_c"] = ed.em.centroid(sel)
	var n: Vector3 = faces_normal(ed.em, ed.sel_t) if ed.sel_kind != 0 else Vector3.ZERO
	ed.xf["flt_fit"] = n if n != Vector3.ZERO else fit_normal(ed.em.points, sel)
	ed.xf["flt_faces"] = n != Vector3.ZERO
	ed.xf["flt_f"] = -1.0   # (by the mouse until a digit's typed)
	ed._xf_update()


# --- the maths (static: tests call them) --------------------------------------------

## The straight curve along `ids` of `pts`: from one end of their longest extent to the other
## (the farthest point from their middle, then the farthest from it - all of them projected on
## that line). {crv_a0, crv_dir, crv_len, crv_p: its 4 control points (thirds: straight)} - {} if
## they're all at one place.
static func curve_line(pts: PackedVector3Array, ids: PackedInt32Array) -> Dictionary:
	if ids.size() < 2:
		return {}
	var c := Vector3.ZERO
	for i in ids:
		c += pts[i]
	c /= ids.size()
	var a := c
	for i in ids:
		if pts[i].distance_squared_to(c) > a.distance_squared_to(c):
			a = pts[i]
	var b := a
	for i in ids:
		if pts[i].distance_squared_to(a) > b.distance_squared_to(a):
			b = pts[i]
	if a.distance_to(b) < 1e-6:
		return {}
	var dir := (b - a).normalized()
	var lo := INF
	var hi := -INF
	for i in ids:
		var t := (pts[i] - c).dot(dir)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	var a0 := c + dir * lo
	var ln := hi - lo
	return {"crv_a0": a0, "crv_dir": dir, "crv_len": ln,
		"crv_p": PackedVector3Array([a0, a0 + dir * (ln / 3.0), a0 + dir * (ln * 2.0 / 3.0), a0 + dir * ln])}


static func bez(cp: PackedVector3Array, t: float) -> Vector3:
	var u := 1.0 - t
	return cp[0] * (u * u * u) + cp[1] * (3.0 * u * u * t) + cp[2] * (3.0 * u * t * t) + cp[3] * (t * t * t)


static func bez_d(cp: PackedVector3Array, t: float) -> Vector3:
	var u := 1.0 - t
	return (cp[1] - cp[0]) * (3.0 * u * u) + (cp[2] - cp[1]) * (6.0 * u * t) + (cp[3] - cp[2]) * (3.0 * t * t)


## The curve's length table: N + 1 cumulative lengths at t = i / N (arc_t reads it).
static func arc_table(cp: PackedVector3Array, n := 64) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	var prev := cp[0]
	var acc := 0.0
	for i in range(1, n + 1):
		var q := bez(cp, float(i) / n)
		acc += prev.distance_to(q)
		out.append(acc)
		prev = q
	return out


## The curve's parameter at fraction `f` (0..1) of its length.
static func arc_t(table: PackedFloat32Array, f: float) -> float:
	var n := table.size() - 1
	var total := table[n]
	if total <= 1e-12:
		return f
	var want := clampf(f, 0.0, 1.0) * total
	var i := table.bsearch(want)
	if i <= 0:
		return 0.0
	if i > n:
		return 1.0
	var a := table[i - 1]
	var b := table[i]
	return (float(i - 1) + ((want - a) / (b - a) if b > a else 0.0)) / n


## A curve through the points `ids` of `pts`: its ends on the two end points (along `line`'s
## direction), its handles solved (least squares, chord-length spacing refined by a few Newton
## steps; held lightly towards the thirds, so two or three points still give a sound curve) for
## it to pass as near every point as a cubic can - through them all when they lie on one.
static func fit_curve(pts: PackedVector3Array, ids: PackedInt32Array, line: Dictionary) -> PackedVector3Array:
	var a0: Vector3 = line["crv_a0"]
	var dir: Vector3 = line["crv_dir"]
	var order := Array(ids)
	order.sort_custom(func(a, b): return (pts[a] - a0).dot(dir) < (pts[b] - a0).dot(dir))
	var q := PackedVector3Array()
	for i in order:
		if q.is_empty() or pts[i].distance_to(q[-1]) > 1e-7:
			q.append(pts[i])
	var p0 := q[0]
	var p3 := q[-1]
	var third1 := p0.lerp(p3, 1.0 / 3.0)
	var third2 := p0.lerp(p3, 2.0 / 3.0)
	if q.size() < 3:
		return PackedVector3Array([p0, third1, third2, p3])
	var u := PackedFloat32Array([0.0])   # (chord-length spacing)
	for i in range(1, q.size()):
		u.append(u[-1] + q[i].distance_to(q[i - 1]))
	for i in u.size():
		u[i] /= maxf(u[-1], 1e-9)
	var cp := PackedVector3Array([p0, third1, third2, p3])
	var lam := 1e-4 * q.size()
	for round in 4:
		var c11 := lam
		var c12 := 0.0
		var c22 := lam
		var x1 := third1 * lam
		var x2 := third2 * lam
		for i in q.size():
			var t := u[i]
			var v := 1.0 - t
			var b0 := v * v * v
			var b1 := 3.0 * v * v * t
			var b2 := 3.0 * v * t * t
			var b3 := t * t * t
			var r := q[i] - p0 * b0 - p3 * b3
			c11 += b1 * b1
			c12 += b1 * b2
			c22 += b2 * b2
			x1 += r * b1
			x2 += r * b2
		var det := c11 * c22 - c12 * c12
		if absf(det) < 1e-12:
			break
		cp[1] = (x1 * c22 - x2 * c12) / det
		cp[2] = (x2 * c11 - x1 * c12) / det
		for i in range(1, q.size() - 1):   # (each point's place on the curve made nearer: a Newton step)
			u[i] = clampf(_newton(cp, q[i], u[i]), 0.0, 1.0)
	return cp


static func _newton(cp: PackedVector3Array, p: Vector3, t: float) -> float:
	var d := bez(cp, t) - p
	var d1 := bez_d(cp, t)
	var u := 1.0 - t
	var d2 := (cp[2] - cp[1] * 2.0 + cp[0]) * (6.0 * u) + (cp[3] - cp[2] * 2.0 + cp[1]) * (6.0 * t)
	var den := d1.dot(d1) + d.dot(d2)
	return t - d.dot(d1) / den if absf(den) > 1e-12 else t


## The middles of the faces with a triangle selected in `tsel` (each face once).
static func face_centres(em, tsel: PackedByteArray) -> PackedVector3Array:
	var out := PackedVector3Array()
	var seen := {}
	for t in mini(tsel.size(), em.tri_count()):
		if not tsel[t] or seen.has(em.tri_face[t]):
			continue
		seen[em.tri_face[t]] = true
		var loop: PackedInt32Array = em.poly_loop(t)
		var c := Vector3.ZERO
		for p in loop:
			c += em.points[p]
		out.append(c / maxf(1, loop.size()))
	return out


## The parameter of the point on curve `cp` nearest `p` (sampled, then refined).
static func nearest_t(cp: PackedVector3Array, p: Vector3) -> float:
	var best := 0.0
	var bd := INF
	for i in 33:
		var t := float(i) / 32.0
		var d := bez(cp, t).distance_squared_to(p)
		if d < bd:
			bd = d
			best = t
	for i in 4:
		best = clampf(_newton(cp, p, best), 0.0, 1.0)
	return best


## The fraction of curve length at parameter `t` (from arc_table's table).
static func arc_f(table: PackedFloat32Array, t: float) -> float:
	var n := table.size() - 1
	var total := table[n]
	if total <= 1e-12:
		return t
	var x := clampf(t, 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	return lerpf(table[i], table[i + 1], x - i) / total


## The points `orig` bound to curve `cp`: each one's place along it (a fraction of its length - kept
## as the curve changes), its offset from it there and the curve's direction there.
## {crv_f, crv_r, crv_tan}
static func bind_points(orig: PackedVector3Array, cp: PackedVector3Array) -> Dictionary:
	var table := arc_table(cp)
	var f := PackedFloat32Array()
	var r := PackedVector3Array()
	var tan := PackedVector3Array()
	for o in orig:
		var t := nearest_t(cp, o)
		f.append(arc_f(table, t))
		r.append(o - bez(cp, t))
		var d := bez_d(cp, t)
		tan.append(d.normalized() if d.length() > 1e-9 else (cp[3] - cp[0]).normalized())
	return {"crv_f": f, "crv_r": r, "crv_tan": tan}


## Where a selected point `o` goes when snapped: exactly on the curve, as far along it (by length)
## as it was along the straight line.
static func curve_snap(o: Vector3, a0: Vector3, dir: Vector3, ln: float, cp: PackedVector3Array, table: PackedFloat32Array) -> Vector3:
	var f := clampf((o - a0).dot(dir) / maxf(ln, 1e-9), 0.0, 1.0)
	return bez(cp, arc_t(table, f))


## Where point `o` goes: its place along the straight line (0..1, clamped), its offset from it
## turned as the line's direction is turned into the curve's there, added to the curve's point.
static func curve_carry(o: Vector3, a0: Vector3, dir: Vector3, ln: float, cp: PackedVector3Array) -> Vector3:
	var t := clampf((o - a0).dot(dir) / maxf(ln, 1e-9), 0.0, 1.0)
	var off := o - (a0 + dir * (t * ln))
	var tan := bez_d(cp, t)
	if tan.length() > 1e-9:
		off = turn(dir, tan.normalized()) * off
	return bez(cp, t) + off


static func _axis(a: int) -> Vector3:
	var v := Vector3.ZERO
	v[a] = 1.0
	return v


## The shortest turn taking unit `from` onto unit `to`.
static func turn(from: Vector3, to: Vector3) -> Basis:
	var d := from.dot(to)
	if d > 0.999999:
		return Basis()
	if d < -0.999999:   # (opposite: half a turn about any line across)
		var ax := from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT).normalized()
		return Basis(ax, PI)
	return Basis(from.cross(to).normalized(), acos(clampf(d, -1.0, 1.0)))


## The selected faces' average normal (area-weighted; the part's space) - ZERO when none are
## selected or they cancel out.
static func faces_normal(em, tsel: PackedByteArray) -> Vector3:
	var n := Vector3.ZERO
	for t in mini(tsel.size(), em.tri_count()):
		if tsel[t]:
			var a: Vector3 = em.points[em.tris[t * 3]]
			n += (em.points[em.tris[t * 3 + 1]] - a).cross(em.points[em.tris[t * 3 + 2]] - a)
	return n.normalized() if n.length() > 1e-9 else Vector3.ZERO


## The best-fit plane's normal through `ids` of `pts` (least squares): the direction the points
## spread least - their covariance's smallest axis (the two largest found by power iteration,
## the normal across them).
static func fit_normal(pts: PackedVector3Array, ids: PackedInt32Array) -> Vector3:
	var c := Vector3.ZERO
	for i in ids:
		c += pts[i]
	c /= maxf(1, ids.size())
	var cov := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # (rows of the symmetric 3x3)
	for i in ids:
		var d := pts[i] - c
		cov[0] += d * d.x
		cov[1] += d * d.y
		cov[2] += d * d.z
	var mul := func(v: Vector3, m: Array) -> Vector3:
		return Vector3((m[0] as Vector3).dot(v), (m[1] as Vector3).dot(v), (m[2] as Vector3).dot(v))
	var e1 := _power(cov, mul, Vector3(0.6, 0.7, 0.4))
	if e1 == Vector3.ZERO:
		return Vector3.UP
	var l1: float = (mul.call(e1, cov) as Vector3).dot(e1)
	var cov2 := [cov[0] - e1 * (l1 * e1.x), cov[1] - e1 * (l1 * e1.y), cov[2] - e1 * (l1 * e1.z)]
	var seed := e1.cross(Vector3.UP if absf(e1.y) < 0.9 else Vector3.RIGHT)
	var e2 := _power(cov2, mul, seed)
	if e2 == Vector3.ZERO:   # (all on a line: any plane through it)
		return seed.normalized()
	var n := e1.cross(e2)
	return n.normalized() if n.length() > 1e-9 else seed.normalized()


static func _power(m: Array, mul: Callable, v0: Vector3) -> Vector3:
	var v := v0.normalized()
	for i in 64:
		var w: Vector3 = mul.call(v, m)
		if w.length() < 1e-12:
			return Vector3.ZERO
		v = w.normalized()
	return v


# --- the transform's step (from the editor's _xf_update) ------------------------------

func step(m0: Vector2, m: Vector2, ps: Vector2) -> void:
	var x: Dictionary = ed.xf
	var ids: PackedInt32Array = x["ids"]
	var orig: PackedVector3Array = x["orig"]
	var w: PackedFloat32Array = x["w"]
	var em = ed.em
	var g: Transform3D = ed.part.global_transform
	if x["kind"] == "CRV":
		if not x.has("crv_p"):
			return   # (begin_curve sets it up next)
		var cp: PackedVector3Array = x["crv_p"]
		if not x.has("crv_f"):
			return
		# Each point at its place along the curve (by length): the selected ones on it (snapped), the
		# rest - and all of them with snapping off - keeping their offsets, turned with the curve.
		# The curve as it started: nothing moves.
		var changed: bool = cp != (x["crv_start"] as PackedVector3Array)
		var snap: bool = x.get("crv_snap", snaps())
		var table := arc_table(cp)
		var on := {}
		if snap and not x.get("crv_faces", false):
			for i in x["sel"]:
				on[i] = true
		if (x["crv_f"] as PackedFloat32Array).size() != ids.size():   # (the points changed - proportional radius)
			var bind := bind_points(orig, x["crv_start"])
			for key in bind:
				x[key] = bind[key]
		var f: PackedFloat32Array = x["crv_f"]
		var r: PackedVector3Array = x["crv_r"]
		var tan0: PackedVector3Array = x["crv_tan"]
		for k in ids.size():
			var o := orig[k]
			if not changed:
				em.points[ids[k]] = o
				continue
			var t := arc_t(table, f[k])
			var to := bez(cp, t)
			if not on.has(ids[k]):
				var d := bez_d(cp, t)
				to += (turn(tan0[k], d.normalized()) * r[k]) if d.length() > 1e-9 else r[k]
			em.points[ids[k]] = o.lerp(to, w[k])
		var gp := PackedVector3Array()
		for p in cp:
			gp.append(g * p)
		ed.view.curve_pts = gp
		ed.view.curve_hot = int(x["crv_drag"]) if int(x["crv_drag"]) >= 0 else int(x["crv_hot"])
		var ax: int = x["axis"]
		ed.view.axis_line = {"at": gp[int(x["crv_drag"])], "dir": g.basis * _axis(ax), "col": MeshView.AXIS_COL[ax]} \
			if ax >= 0 and int(x["crv_drag"]) >= 0 else {}
		ed.view.hint = ("Curve deform: the faces" if x.get("crv_faces", false) else "Curve deform") + "   (drag ends / handles · X Y Z: axis · Enter: done · Esc: cancel)"
		return
	# Flatten
	if not x.has("flt_c"):
		return   # (begin_flatten sets it up next)
	var f: float = x["flt_f"]
	if f < 0.0:
		f = clampf((m - ps).length() / maxf(1.0, (m0 - ps).length()) - 1.0, 0.0, 1.0)
	var ax: int = x["axis"]
	var n: Vector3 = x["flt_fit"]
	if ax >= 0:
		n = Vector3.ZERO
		n[ax] = 1.0
	var c: Vector3 = x["flt_c"]
	for k in ids.size():
		var o := orig[k]
		em.points[ids[k]] = o - n * ((o - c).dot(n) * f * w[k])
	ed.view.axis_line = {"at": g * c, "dir": (g.basis * n).normalized(), "col": MeshView.AXIS_COL[ax] if ax >= 0 else Color(1, 1, 1, 0.9)}
	var onto := "the %s plane" % ["YZ", "XZ", "XY"][ax] if ax >= 0 else ("the faces' plane" if x.get("flt_faces", false) else "the best-fit plane")
	ed.view.hint = "Flatten  %d%%  onto %s   (mouse / 0-9: how flat · X Y Z: axis plane · click: done · Esc: cancel)" % [roundi(f * 100.0), onto]


# --- the mouse (from the editor's _view_input) ---------------------------------------

## The mouse moved during a transform: true when it's handled here (the curve: a handle hovered,
## nothing to work out); a handle being dragged is moved (false: the editor works the step out).
func hover(at: Vector2) -> bool:
	var x: Dictionary = ed.xf
	if x.get("kind", "") != "CRV" or not x.has("crv_p"):
		return false
	var i: int = x["crv_drag"]
	if i < 0:
		var hot := pick(at)
		if hot != int(x["crv_hot"]):
			x["crv_hot"] = hot
			ed.view.curve_hot = hot
			ed.view.queue_redraw()
		return true
	drag_to(i, at)
	return false


## A button of the mouse during a transform: true when it's taken here (the curve: a press on an
## end or handle starts dragging it, elsewhere nothing - Enter keeps, right-click cancels).
func mouse_button(mb: InputEventMouseButton) -> bool:
	var x: Dictionary = ed.xf
	if x.get("kind", "") != "CRV" or mb.button_index != MOUSE_BUTTON_LEFT or not x.has("crv_p"):
		return false
	if mb.pressed:
		var i := pick(mb.position)
		x["crv_drag"] = i
		if i >= 0:
			x["crv_m0"] = mb.position
			x["crv_p0"] = (x["crv_p"] as PackedVector3Array).duplicate()
	else:
		x["crv_drag"] = -1
		ed._xf_update()
	return true


## The end point or handle (0-3) nearest `at` on screen, within HANDLE_PX - else -1.
func pick(at: Vector2) -> int:
	var cp: PackedVector3Array = ed.xf.get("crv_p", PackedVector3Array())
	var g: Transform3D = ed.part.global_transform
	var best := -1
	var bd := HANDLE_PX
	for i in [0, 3, 1, 2]:   # (the ends first: a handle on top of its end lets the end be taken)
		var p := g * cp[i]
		if ed.view.behind(p):
			continue
		var d: float = ((ed.view.project(p) as Vector2) - at).length()
		if d < bd - 0.5:
			bd = d
			best = i
	return best


## Control point `i` dragged to the mouse at `at` - over the plane facing the view through where it
## was, or along the locked axis; an end carries its handle with it.
func drag_to(i: int, at: Vector2) -> void:
	var x: Dictionary = ed.xf
	var g: Transform3D = ed.part.global_transform
	var p0: PackedVector3Array = x["crv_p0"]
	var start := g * p0[i]
	var m0: Vector2 = x["crv_m0"]
	var ax: int = x["axis"]
	var d: Vector3
	if ax >= 0:
		var l := (g.basis * _axis(ax)).normalized()
		d = ed.view.on_line(at, start, l) - ed.view.on_line(m0, start, l)
	else:
		d = ed.view.on_view_plane(at, start) - ed.view.on_view_plane(m0, start)
	var dl := g.basis.inverse() * d
	var cp := p0.duplicate()
	cp[i] = p0[i] + dl
	if i == 0:
		cp[1] = p0[1] + dl
	elif i == 3:
		cp[2] = p0[2] + dl
	x["crv_p"] = cp


## Sets the curve's control points (the part's space) and works the step out - for tests and typed values.
func set_curve(cp: PackedVector3Array) -> void:
	if ed.xf.get("kind", "") == "CRV":
		ed.xf["crv_p"] = cp
		ed._xf_update()


## The curve as it started (fitted through the points: they're back where they were).
func reset_curve() -> void:
	var x: Dictionary = ed.xf
	if x.get("kind", "") != "CRV":
		return
	set_curve((x["crv_start"] as PackedVector3Array).duplicate())


## Flatten's plane: -1 the best fit, 0-2 the part's X / Y / Z axis plane.
## Curve deform's snapping on or off (the open curve follows at once).
func set_snap(on: bool) -> void:
	set_meta("snap_on_curve", on)
	if _crv_btns.size() > 1:
		(_crv_btns[1] as Button).set_pressed_no_signal(on)
	if ed.xf.get("kind", "") == "CRV":
		ed.xf["crv_snap"] = on
		ed._xf_update()


func set_plane(ax: int) -> void:
	if ed.xf.get("kind", "") == "FLT":
		ed.xf["axis"] = ax
		ed.xf["dir"] = Vector3.ZERO
		ed._xf_update()


# --- the bar in the view ----------------------------------------------------------------

func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.name = "DeformBar"
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.offset_top = 8
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_bar.add_child(row)
	var fit: Button = ed._btn("Best-fit plane", "m_flatten", "", "Flattens onto the plane that fits the selected points best (the selected faces' own plane\nwhen faces are selected).", func(): set_plane(-1))
	_flt_btns.append(fit)
	for a in 3:
		_flt_btns.append(ed._btn("%s plane" % "XYZ"[a], ["m_sym_x", "m_sym_y", "m_sym_z"][a], "XYZ"[a],
			"Flattens onto the plane across the part's own %s axis through the selection's middle\n(every point given the middle's %s)." % ["XYZ"[a], "XYZ"[a]], set_plane.bind(a)))
	for b in _flt_btns:
		(b as Button).toggle_mode = true
		row.add_child(b)
	_crv_btns.append(ed._btn("Reset the curve", "reload", "", "The curve back as it started - fitted through the points (they're back where they were).", reset_curve))
	var sn: Button = ed._btn("Snap onto the curve", "snap", "", "On: the selected points sit exactly on the curve, spaced along it as they were along the line.\nOff: each keeps its offset from the line - an area of points bent by the curve.", func(): set_snap(not snaps()))
	sn.toggle_mode = true
	sn.set_pressed_no_signal(snaps())
	_crv_btns.append(sn)
	for b in _crv_btns:
		row.add_child(b)
	row.add_child(ed._btn("Keep", "accept", "Enter", "Keeps the change (one undo step).", func(): ed.confirm_transform()))
	row.add_child(ed._btn("Cancel", "close", "Esc / right-click", "Puts the points back as they were.", func(): ed._cancel_xf()))
	ed.view.add_child(_bar)


func _process(_dt: float) -> void:
	if ed == null or ed.view == null:
		return
	if _bar and _crv_btns.size() < 2:   # (a bar made by older code: made again, with every button)
		_bar.queue_free()
		_bar = null
		_crv_btns = []
		_flt_btns = []
		_shown = "?"
	var k: String = ed.xf.get("kind", "") if ed.mode == "edit" else ""
	if not k in KINDS:
		k = ""
	if k != _shown:
		_shown = k
		if _bar == null and k != "":
			_build_bar()
		if _bar:
			_bar.visible = k != ""
			for b in _crv_btns:
				b.visible = k == "CRV"
			for b in _flt_btns:
				b.visible = k == "FLT"
	if k != "CRV" and not ed.view.curve_pts.is_empty():
		ed.view.curve_pts = PackedVector3Array()
		ed.view.curve_hot = -1
		ed.view.queue_redraw()
	if k == "FLT":
		var ax: int = ed.xf.get("axis", -1)
		for i in _flt_btns.size():
			(_flt_btns[i] as Button).set_pressed_no_signal(i == ax + 1)
