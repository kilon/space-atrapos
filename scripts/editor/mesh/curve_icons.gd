extends RefCounted
## The Curve modeling tab's icons (m_cv_*), in the editor icons' style (EditorIcons' helpers):
## the curve in gold, the solid it makes in amber, white points.

const E := preload("res://scripts/editor/editor_icons.gd")
const NAMES := ["m_cv_line", "m_cv_wire", "m_cv_spline", "m_cv_pt_smooth", "m_cv_pt_sharp", "m_cv_pt_manual", "m_cv_circle", "m_cv_arc", "m_cv_rect", "m_cv_polygon", "m_cv_radial",
	"m_cv_offset", "m_cv_fillet", "m_cv_join", "m_cv_bridge", "m_cv_reverse", "m_cv_close", "m_cv_extrude",
	"m_cv_revolve", "m_cv_loft", "m_cv_sweep", "m_cv_pipe", "m_cv_fill", "m_cv_plane", "m_cv_pt_separate", "m_cv_pt_merge",
	"m_cv_pt_extrude", "m_cv_pt_subdivide", "m_cv_pt_connect", "m_cv_pt_delete", "m_cv_patch_finer", "m_cv_patch_coarser", "m_cv_merge",
	"m_cv_ol_collection", "m_cv_ol_solid", "m_cv_ol_mesh", "m_cv_ol_edge", "m_cv_ol_step", "m_cv_ol_sel", "m_cv_ol_sel_off"]


static func _pts(arr: PackedVector2Array) -> Array:
	var out := []
	for q in arr:
		out.append([q.x, q.y])
	return out


static func _dot(x: float, y: float) -> Dictionary:
	return E._c(Vector2(x, y), 1.6, E.W)


## The point a point icon is about: a bigger blue dot.
static func _c_hi(x: float, y: float) -> Dictionary:
	return E._c(Vector2(x, y), 2.4, E.BLUE)


static func _bez(a: Vector2, b: Vector2, c: Vector2, d: Vector2, n := 14) -> Array:
	var out := []
	for i in n + 1:
		var t := float(i) / n
		var u := 1.0 - t
		var q := a * (u * u * u) + b * (3.0 * u * u * t) + c * (3.0 * u * t * t) + d * (t * t * t)
		out.append([q.x, q.y])
	return out


static func _arc(c: Vector2, r: float, a0: float, a1: float) -> Array:
	return _pts(Icons.arc(c, r, a0, a1, 24))


static func layers(name: String) -> Array:
	var G := E.GOLD
	var B := E.BLUE
	match name:
		"m_cv_line":   # a polyline, its corner points
			return E._gl([[3, 16], [8, 5], [13, 13], [17, 4]], 1.6, G) + [_dot(3, 16), _dot(8, 5), _dot(13, 13), _dot(17, 4)]
		"m_cv_wire":   # a cube's edges seen through: the wireframe
			return E._gl([[3, 7], [12, 7], [12, 17], [3, 17], [3, 7]], 1.4, B) + E._gl([[3, 7], [8, 3], [17, 3], [12, 7]], 1.4, B) \
				+ E._gl([[17, 3], [17, 13], [12, 17]], 1.4, B) + E._gl([[3, 12], [12, 12]], 1.0, G) + E._gl([[7.5, 7], [7.5, 17]], 1.0, G)
		"m_cv_pt_smooth":   # a smooth bend through a point
			return E._gl(_bez(Vector2(2.5, 15), Vector2(7, 3), Vector2(13, 3), Vector2(17.5, 15)), 1.6, G) + [_dot(2.5, 15), _dot(17.5, 15), _c_hi(10, 6.1)]
		"m_cv_pt_sharp":   # a corner at a point: straight either side
			return E._gl([[2.5, 16], [10, 4], [17.5, 16]], 1.6, G) + [_dot(2.5, 16), _dot(17.5, 16), _c_hi(10, 4)]
		"m_cv_pt_manual":   # a bend shaped by hand at its point: a handle pulled out of it, the part near it glowing green
			return E._gl(_bez(Vector2(2.5, 16), Vector2(5, 9), Vector2(8, 5), Vector2(10, 5)), 1.6, G) + E._gl(_bez(Vector2(10, 5), Vector2(13, 5), Vector2(15, 11), Vector2(17.5, 16)), 2.0, Color(0.35, 1.0, 0.45)) \
				+ E._gl([[10, 5], [16, 2.5]], 1.0, B) + [_dot(2.5, 16), _dot(17.5, 16), _c_hi(10, 5), _dot(16, 2.5)]
		# the overview's rows (as an outliner shows them): a collection, an ECurve solid, a plain mesh, an edge, a step
		"m_cv_ol_collection":   # a crate: a box with its lid - what holds solids
			var pale := Color(0.92, 0.9, 0.86)
			return [E._f([[3, 8], [17, 8], [17, 17], [3, 17]], Color(pale, 0.16))] + E._gl([[3, 8], [17, 8], [17, 17], [3, 17]], 1.4, pale, true) \
				+ E._gl([[2, 4.5], [18, 4.5], [18, 8], [2, 8]], 1.4, pale, true) + E._gl([[8, 11], [12, 11]], 1.4, pale)
		"m_cv_ol_solid":   # a solid made of edges: an amber triangle, its corners its vertices
			return [E._f([[3, 4], [17, 4], [10, 16.5]], Color(E.BLUE, 0.35))] + E._gl([[3, 4], [17, 4], [10, 16.5]], 1.5, E.BLUE, true) \
				+ [_dot(3, 4), _dot(17, 4), _dot(10, 16.5)]
		"m_cv_ol_mesh":   # a plain mesh: a green triangle, no vertices of its own to edit
			var g := Color(0.45, 0.85, 0.45)
			return [E._f([[3, 4], [17, 4], [10, 16.5]], Color(g, 0.3))] + E._gl([[3, 4], [17, 4], [10, 16.5]], 1.5, g, true)
		"m_cv_ol_edge":   # an edge: a gold curve between its two vertices
			return E._gl(_bez(Vector2(3, 15.5), Vector2(4, 5), Vector2(15, 15), Vector2(17, 4.5)), 1.6, E.GOLD) + [_dot(3, 15.5), _dot(17, 4.5)]
		"m_cv_ol_step":   # a boolean step: two solids overlapping
			return E._gring(Vector2(7.5, 10), 5.0, 1.4, E.BLUE) + E._gring(Vector2(12.5, 10), 5.0, 1.4, E.GOLD)
		"m_cv_ol_sel":   # selectable: the pointer's arrow
			var arrow := [[6, 3], [6, 16], [9, 13], [11.5, 18], [13.5, 17], [11, 12], [15, 12]]
			return [E._f(arrow, Color(E.W, 0.85))] + E._gl(arrow, 1.0, E.W, true)
		"m_cv_ol_sel_off":   # not selectable: the arrow dim, struck through
			var arrow2 := [[6, 3], [6, 16], [9, 13], [11.5, 18], [13.5, 17], [11, 12], [15, 12]]
			return E._gl(arrow2, 1.0, Color(E.W, 0.35), true) + E._gl([[3, 17], [17, 3]], 1.6, E.RED)
		"m_cv_merge":   # two curves running into one point (a ring round it: the merge distance) - one curve
			return E._gl(_bez(Vector2(2.5, 16), Vector2(4, 9), Vector2(7, 10), Vector2(10, 10)), 1.6, G) + E._gl(_bez(Vector2(10, 10), Vector2(13, 10), Vector2(16, 11), Vector2(17.5, 4)), 1.6, G) \
				+ E._gring(Vector2(10, 10), 3.2, 1.0, B) + [_dot(2.5, 16), _dot(17.5, 4), _c_hi(10, 10)]
		"m_cv_pt_separate":   # a curve broken in two at its picked points, the piece lifted off
			return E._gl([[2.5, 16], [7, 12]], 1.6, G) + E._gl([[8.5, 8], [11.5, 5.5]], 1.6, B) + E._gl([[13, 12], [17.5, 16]], 1.6, G) \
				+ [_dot(2.5, 16), _dot(17.5, 16), _c_hi(8.5, 8), _c_hi(11.5, 5.5)]
		"m_cv_pt_merge":   # two curves' ends drawn together into one point
			return E._gl([[2.5, 15], [9, 9]], 1.6, G) + E._gl([[11, 9], [17.5, 15]], 1.6, G) + E._gl([[7, 4], [9.5, 6.5]], 1.2, B) \
				+ E._gl([[13, 4], [10.5, 6.5]], 1.2, B) + [_dot(2.5, 15), _dot(17.5, 15), _c_hi(10, 9)]
		"m_cv_pt_extrude":   # a curve's end pulled out into a new point
			return E._gl([[2.5, 16], [9, 10]], 1.6, G) + E._gl([[9, 10], [16, 4]], 1.4, B) + E._gl([[12.5, 4], [16, 4], [16, 7.5]], 1.2, B) \
				+ [_dot(2.5, 16), _dot(9, 10), _c_hi(16, 4)]
		"m_cv_pt_subdivide":   # a new point between two picked ones
			return E._gl(_bez(Vector2(2.5, 14), Vector2(7, 4), Vector2(13, 4), Vector2(17.5, 14)), 1.6, G) + [_c_hi(2.5, 14), _c_hi(17.5, 14), _dot(10, 6.5)] \
				+ E._gl([[10, 10.5], [10, 16]], 1.2, B) + E._gl([[7.5, 13.5], [12.5, 13.5]], 1.2, B)
		"m_cv_pt_connect":   # a straight line between two points
			return E._gl([[3, 15], [17, 5]], 1.6, B) + E._gl(_bez(Vector2(3, 15), Vector2(3, 9), Vector2(1, 6), Vector2(2, 3)), 1.2, G) \
				+ E._gl(_bez(Vector2(17, 5), Vector2(17, 11), Vector2(19, 14), Vector2(18, 17)), 1.2, G) + [_c_hi(3, 15), _c_hi(17, 5)]
		"m_cv_pt_delete":   # a point taken out: the curve runs on past it
			return E._gl([[2.5, 15], [17.5, 15]], 1.6, G) + [_dot(2.5, 15), _dot(17.5, 15)] + E._gl([[7, 3], [13, 9]], 1.6, E.RED) + E._gl([[13, 3], [7, 9]], 1.6, E.RED)
		"m_cv_patch_finer":   # a patch's grid made twice as fine
			return E._gl([[3, 3], [17, 3], [17, 17], [3, 17]], 1.4, G, true) + E._gl([[10, 3], [10, 17]], 1.0, B) + E._gl([[3, 10], [17, 10]], 1.0, B) \
				+ E._gl([[6.5, 3], [6.5, 17]], 0.7, B) + E._gl([[13.5, 3], [13.5, 17]], 0.7, B) + E._gl([[3, 6.5], [17, 6.5]], 0.7, B) + E._gl([[3, 13.5], [17, 13.5]], 0.7, B)
		"m_cv_patch_coarser":   # a patch's grid made coarser again
			return E._gl([[3, 3], [17, 3], [17, 17], [3, 17]], 1.4, G, true) + E._gl([[10, 3], [10, 17]], 1.2, B) + E._gl([[3, 10], [17, 10]], 1.2, B)
		"m_cv_spline":   # a smooth curve through points
			return E._gl(_bez(Vector2(2.5, 15), Vector2(6, 0), Vector2(13, 22), Vector2(17.5, 5)), 1.6, G) + [_dot(2.5, 15), _dot(10, 10), _dot(17.5, 5)]
		"m_cv_circle":
			return E._gring(Vector2(10, 10), 7.0, 1.6, G) + [_dot(10, 10), _dot(17, 10)]
		"m_cv_arc":
			return E._gl(_arc(Vector2(10, 13), 7.0, PI, TAU), 1.6, G) + [_dot(3, 13), _dot(10, 6), _dot(17, 13)]
		"m_cv_rect":
			return E._gl([[3, 5], [17, 5], [17, 15], [3, 15]], 1.6, G, true) + [_dot(3, 5), _dot(17, 15)]
		"m_cv_polygon":
			var p := PackedVector2Array()
			for i in 6:
				p.append(Vector2(10, 10) + Vector2(cos(TAU * i / 6.0), sin(TAU * i / 6.0)) * 7.5)
			return E._gl(_pts(p), 1.6, G, true) + [_dot(10, 10)]
		"m_cv_radial":   # copies round a centre
			var out := [E._c(Vector2(10, 10), 1.3, E.W)]
			for i in 6:
				var a := TAU * i / 6.0
				var q := Vector2(10, 10) + Vector2(cos(a), sin(a)) * 6.5
				out.append(E._ring(q, 1.8, 1.2, G))
			return out
		"m_cv_offset":   # a curve and a copy beside it
			return E._gl(_bez(Vector2(2, 14), Vector2(6, 4), Vector2(14, 4), Vector2(18, 14)), 1.4, Color(G, 0.6)) \
				+ E._gl(_bez(Vector2(2, 18), Vector2(6, 8), Vector2(14, 8), Vector2(18, 18)), 1.6, G) + E._arrow(Vector2(10, 7), Vector2(10, 11.5), E.W, 1.1)
		"m_cv_fillet":   # a corner rounded
			return [E._l([[3, 17], [3, 3], [17, 3]], 1.0, Color(E.W, 0.4))] + E._gl([[3, 17], [3, 11]] + _arc(Vector2(11, 11), 8.0, PI, PI * 1.5) + [[17, 3]], 1.6, G)
		"m_cv_join":   # two curves meeting at a point
			return E._gl([[2, 14], [9, 8]], 1.6, G) + E._gl([[11, 8], [18, 14]], 1.6, Color(G, 0.7)) + [E._c(Vector2(10, 8), 2.2, B)]
		"m_cv_bridge":   # a smooth curve between two ends
			return E._gl([[2, 16], [6, 10]], 1.6, Color(G, 0.6)) + E._gl([[14, 10], [18, 16]], 1.6, Color(G, 0.6)) \
				+ E._gl(_bez(Vector2(6, 10), Vector2(8, 3), Vector2(12, 3), Vector2(14, 10)), 1.6, G) + [_dot(6, 10), _dot(14, 10)]
		"m_cv_reverse":
			return E._gl(_bez(Vector2(3, 14), Vector2(6, 4), Vector2(14, 4), Vector2(17, 14)), 1.4, G) + E._arrow(Vector2(15, 17), Vector2(5, 17), E.W, 1.2)
		"m_cv_close":   # an open loop with its gap closed
			return E._gl(_arc(Vector2(10, 10), 7.0, 0.5, TAU - 0.5), 1.6, G) + [E._l([[16.1, 6.6], [16.1, 13.4]], 1.6, E.GREEN)]
		"m_cv_extrude":   # an outline pushed up into a block
			return [E._f([[3, 13], [12, 13], [17, 16], [8, 16]], Color(B, 0.35)), E._f([[3, 6], [12, 6], [17, 9], [8, 9]], Color(B, 0.75)),
				E._l([[3, 6], [3, 13]], 1.0, E.W), E._l([[17, 9], [17, 16]], 1.0, E.W), E._l([[12, 6], [12, 13]], 1.0, Color(E.W, 0.5))] \
				+ E._gl([[3, 13], [12, 13], [17, 16], [8, 16]], 1.4, G, true) + E._arrow(Vector2(10, 12), Vector2(10, 3.5), E.W, 1.2)
		"m_cv_revolve":   # a profile turned round an axis
			return [E._l([[10, 1.5], [10, 18.5]], 1.0, Color(E.W, 0.6)), E._f(_pts(Icons.arc(Vector2(10, 15), 7.0, 0, PI, 16)) + [[3, 15]], Color(B, 0.3))] \
				+ E._gl([[10, 4], [15, 6], [13, 10], [16.5, 15]], 1.5, G) + E._gring(Vector2(10, 15), 6.5, 1.0, Color(E.W, 0.7), PI * 0.1, PI * 0.9)
		"m_cv_loft":   # a skin through three rings
			return E._gring(Vector2(10, 4.5), 4.0, 1.2, G) + E._gring(Vector2(10, 10), 6.5, 1.2, G) + E._gring(Vector2(10, 16), 3.0, 1.2, G) \
				+ [E._l([[6, 4.5], [3.5, 10], [7, 16]], 1.0, E.W), E._l([[14, 4.5], [16.5, 10], [13, 16]], 1.0, E.W)]
		"m_cv_sweep":   # a profile carried along a path
			return E._gl(_bez(Vector2(3, 17), Vector2(4, 6), Vector2(14, 14), Vector2(17, 3)), 1.1, Color(E.W, 0.8)) \
				+ [E._f([[1, 15], [5, 15], [5, 19], [1, 19]], Color(B, 0.85)), E._f([[15, 1], [19, 1], [19, 5], [15, 5]], Color(B, 0.85))] + E._gl([[1, 15], [5, 15], [5, 19], [1, 19]], 1.0, G, true)
		"m_cv_pipe":   # a tube along a curve
			return E._gl(_bez(Vector2(3, 15), Vector2(5, 3), Vector2(15, 17), Vector2(17, 5)), 5.0, Color(B, 0.7)) + E._gl(_bez(Vector2(3, 15), Vector2(5, 3), Vector2(15, 17), Vector2(17, 5)), 1.0, G)
		"m_cv_fill":   # a closed outline filled
			return [E._f([[3, 7], [9, 3], [17, 6], [15, 16], [5, 15]], Color(B, 0.6))] + E._gl([[3, 7], [9, 3], [17, 6], [15, 16], [5, 15]], 1.4, G, true)
		"m_cv_plane":   # a grid plane in perspective
			return [E._f([[1, 15], [13, 15], [19, 8], [7, 8]], Color(B, 0.35)), E._l([[1, 15], [13, 15], [19, 8], [7, 8], [1, 15]], 1.2, G),
				E._l([[4, 11.5], [16, 11.5]], 0.9, Color(E.W, 0.6)), E._l([[7, 15], [13, 8]], 0.9, Color(E.W, 0.6))]
	return []
