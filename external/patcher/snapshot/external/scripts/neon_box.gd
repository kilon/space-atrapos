class_name NeonBox
extends StyleBox
## The GUI's panel / button box (the "Helm" look - NeonTheme): dark smoked
## glass with two chamfered corners (top-left, bottom-right), a thin amber
## border and only a faint glow. Its own touches, all optional:
##   rail     a lit bar down the left edge (buttons: where the eye starts)
##   accent   bracket corners just outside the two square corners (top-right,
##            bottom-left) and, on boxes big enough, a hatch of slanted ticks
##            in the top-right corner - the signature of every panel
##   skew     a slant (tabs, menu buttons); border_width_bottom: a thick
##            bottom edge (selected tabs)
## A box with `fill_solid` is lit all over in its border colour (hovered
## buttons, the selected tab) - text on it uses NeonTheme.INK.

## Darkest colour (bottom of the gradient); its alpha is the box's opacity.
@export var bg_color := Color(0.03, 0.018, 0.008, 0.92)
@export var border_color := Color(1.0, 0.5, 0.1)
@export var border_width := 1.0
## Thicker bottom edge (tabs); <= border_width to disable.
@export var border_width_bottom := -1.0
## Width of the outer glow in px (0 = none).
@export var glow := 4.0
@export var cut := 10.0
## Horizontal slant, as StyleBoxFlat.skew.
@export var skew := Vector2.ZERO
@export var draw_center := true
## How much of the border colour lights the top of the gradient (0..1).
@export var light := 0.12
## Bracket corners and the corner hatch, in this colour. Clear = none.
@export var accent := Color(0, 0, 0, 0)
## The lit bar down the left edge, px (0 = none).
@export var rail := 0.0
## Filled with the border colour (a lit button / tab).
@export var fill_solid := false


func _init() -> void:
	content_margin_left = 12
	content_margin_right = 12
	content_margin_top = 6
	content_margin_bottom = 6


## StyleBoxFlat-compatible helper.
func set_border_width_all(w: int) -> void:
	border_width = w


func _shape(r: Rect2, grow := 0.0) -> PackedVector2Array:
	r = r.grow(grow)
	var c := minf(cut + grow * 0.4, minf(r.size.x, r.size.y) / 3.0)
	var pts := PackedVector2Array([Vector2(r.position.x + c, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x, r.end.y),
		Vector2(r.position.x, r.position.y + c)])
	_slant(pts, r.get_center().y)
	return pts


func _slant(pts: PackedVector2Array, cy: float) -> void:
	if skew.x != 0.0:
		for i in pts.size():
			pts[i].x += skew.x * (cy - pts[i].y)


func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var pts := _shape(rect)
	var loop := pts.duplicate()
	loop.append(pts[0])
	var cy := rect.get_center().y
	# Faint glow: a few translucent outlines, widest first.
	if glow > 0.0 and border_color.a > 0.0:
		for k in range(3, 0, -1):
			RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([Color(border_color, border_color.a * 0.08)]), glow * 2.0 * k / 3.0, true)
	if draw_center and (bg_color.a > 0.0 or fill_solid):
		var top: Color
		var bottom: Color
		if fill_solid:
			# Lit: the border colour itself, a touch brighter at the top.
			top = border_color.lightened(0.12)
			bottom = border_color.darkened(0.1)
			top.a = maxf(bg_color.a, 0.92)
			bottom.a = top.a
		else:
			top = bg_color.lerp(Color(border_color.r, border_color.g, border_color.b, bg_color.a), light)
			top.a = bg_color.a
			bottom = bg_color.darkened(0.3)
			bottom.a = bg_color.a
		var cols := PackedColorArray()
		for p in pts:
			cols.append(top.lerp(bottom, clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
		if not Geometry2D.triangulate_polygon(pts).is_empty():   # (a box too thin to fill: skip the fill)
			RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	# The rail: a lit bar just inside the left edge (below the top-left chamfer).
	if rail > 0.0 and border_color.a > 0.0 and rect.size.y > 10.0:
		var c := minf(cut, minf(rect.size.x, rect.size.y) / 3.0)
		var x := rect.position.x + rail / 2.0 + 2.0
		var seg := PackedVector2Array([Vector2(x, rect.position.y + c + 3.0), Vector2(x, rect.end.y - 3.0)])
		_slant(seg, cy)
		RenderingServer.canvas_item_add_line(ci, seg[0], seg[1], Color(border_color, minf(1.0, border_color.a * 1.6)), rail)
	# Border (and the optional thick bottom edge).
	if border_width > 0.0 and border_color.a > 0.0:
		RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([border_color]), border_width, true)
	if border_width_bottom > border_width:
		var a := pts[4] + Vector2(0, -border_width_bottom / 2.0)
		var b := pts[3] + Vector2(0, -border_width_bottom / 2.0)
		RenderingServer.canvas_item_add_line(ci, a, b, border_color, border_width_bottom, true)
	if accent.a > 0.0 and rect.size.x > 60.0 and rect.size.y > 40.0:
		_brackets(ci, rect, cy)
		if rect.size.x > 160.0 and rect.size.y > 120.0:   # (short bars keep their corner free for a button)
			_hatch(ci, rect, cy)


## Bracket corners: short L's just outside the two square corners (top-right
## and bottom-left), standing off the border by a few px.
func _brackets(ci: RID, r: Rect2, cy: float) -> void:
	var run := clampf(minf(r.size.x, r.size.y) * 0.18, 10.0, 34.0)
	var o := 4.0
	var w := maxf(1.5, border_width + 0.5)
	for b in [[Vector2(r.end.x - run, r.position.y - o), Vector2(r.end.x + o, r.position.y - o), Vector2(r.end.x + o, r.position.y + run)],
			[Vector2(r.position.x + run, r.end.y + o), Vector2(r.position.x - o, r.end.y + o), Vector2(r.position.x - o, r.end.y - run)]]:
		var line := PackedVector2Array(b)
		_slant(line, cy)
		RenderingServer.canvas_item_add_polyline(ci, line, PackedColorArray([accent]), w, true)


## The corner hatch: six slanted ticks inside the top-right corner, fading
## toward the corner.
func _hatch(ci: RID, r: Rect2, cy: float) -> void:
	var h := 7.0
	var y := r.position.y + border_width + 5.0
	for i in 6:
		var x := r.end.x - 14.0 - i * 7.0
		var seg := PackedVector2Array([Vector2(x, y + h), Vector2(x + 4.0, y)])
		_slant(seg, cy)
		RenderingServer.canvas_item_add_line(ci, seg[0], seg[1], Color(accent, accent.a * (0.9 - i * 0.12)), 2.0, true)
