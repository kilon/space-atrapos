class_name Paint
## Small immediate-mode painting helpers for things drawn live on screen
## (comms portraits of the other empires): filled polygons and ellipses with
## a flat colour or a linear / radial gradient, outlines and soft lights.
## Gradients are evaluated per vertex (polygons are tessellated finely enough).


## Linear gradient from a to b. stops: [[t, Color], ...]
static func linear(a: Vector2, b: Vector2, stops: Array) -> Dictionary:
	return {"type": "linear", "a": a, "b": b, "stops": stops}


## Radial gradient around c of radius r; ratio < 1 squashes it vertically.
static func radial(c: Vector2, r: float, stops: Array, ratio := 1.0) -> Dictionary:
	return {"type": "radial", "c": c, "r": r, "stops": stops, "ratio": ratio}


static func _stop_color(stops: Array, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var prev: Array = stops[0]
	if t <= float(prev[0]):
		return prev[1]
	for s in stops:
		if t <= float(s[0]):
			var span := float(s[0]) - float(prev[0])
			return (prev[1] as Color).lerp(s[1], (t - float(prev[0])) / span if span > 0.0 else 1.0)
		prev = s
	return prev[1]


static func color_at(fill: Variant, p: Vector2) -> Color:
	if fill is Color:
		return fill
	var f: Dictionary = fill
	if f["type"] == "linear":
		var d: Vector2 = f["b"] - f["a"]
		var t: float = (p - f["a"]).dot(d) / maxf(d.length_squared(), 0.0001)
		return _stop_color(f["stops"], t)
	var q: Vector2 = p - f["c"]
	q.y /= maxf(float(f["ratio"]), 0.01)
	return _stop_color(f["stops"], q.length() / maxf(float(f["r"]), 0.0001))


## Subdivides a polygon's edges so gradients shade smoothly.
static func _fine(pts: PackedVector2Array, step := 10.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	return out


static func gpoly(ci: CanvasItem, pts: PackedVector2Array, fill: Variant, stroke := Color(0, 0, 0, 0), width := 0.0, _name := "") -> void:
	if pts.size() < 3:
		return
	if fill is Color:
		if (fill as Color).a > 0.0 and not Geometry2D.triangulate_polygon(pts).is_empty():
			ci.draw_colored_polygon(pts, fill)
	else:
		# Fan from the centroid with per-vertex colours.
		var fine := _fine(pts)
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var cc := color_at(fill, c)
		for i in fine.size():
			var a := fine[i]
			var b := fine[(i + 1) % fine.size()]
			ci.draw_polygon(PackedVector2Array([c, a, b]), PackedColorArray([cc, color_at(fill, a), color_at(fill, b)]))
	if width > 0.0 and stroke.a > 0.0:
		var line := pts.duplicate()
		line.append(pts[0])
		ci.draw_polyline(line, stroke, width, true)


static func gellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Variant, stroke := Color(0, 0, 0, 0), width := 0.0, _name := "") -> void:
	var pts := PackedVector2Array()
	var n := clampi(int((rx + ry) * 0.5), 16, 64)
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	gpoly(ci, pts, fill, stroke, width)


## A soft light: a radial disc with a white-hot centre.
static func glow(ci: CanvasItem, p: Vector2, col: Color, r: float) -> void:
	gellipse(ci, p, r * 2.8, r * 2.8, radial(p, r * 2.8, [[0.0, Color(1, 1, 1, 0.95)], [0.14, Color(col.lightened(0.4), 1.0)],
		[0.34, Color(col, 0.75)], [0.6, Color(col, 0.2)], [1.0, Color(col, 0.0)]]))
