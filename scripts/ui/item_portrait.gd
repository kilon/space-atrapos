class_name ItemPortrait
extends Control
## A large framed picture of an item - the outfitter's selection: the item
## drawn big over a dark radial backdrop, a slow glow and bob, a frame in
## its quality's colour with corner brackets, and its quality's letter.
## Redrawn at most at 60 Hz (UI.redraw_due).

var item_id := ""
var accent := Color(0.4, 0.85, 1.0)
var badge := ""   # (a quality letter in the corner, or "")
var _t := 0.0
static var _backdrop: GradientTexture2D


func show_item(id: String) -> void:
	item_id = id
	accent = Color(0.4, 0.85, 1.0)
	badge = ""
	if Gear.is_gear(id):
		var q := Gear.quality(id)
		accent = Gear.QUALITY_COLORS[q]
		badge = Gear.QUALITY[q]
	queue_redraw()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if _backdrop == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.16, 0.2, 0.3))
		g.set_color(1, Color(0.02, 0.03, 0.06))
		_backdrop = GradientTexture2D.new()
		_backdrop.gradient = g
		_backdrop.fill = GradientTexture2D.FILL_RADIAL
		_backdrop.fill_from = Vector2(0.5, 0.45)
		_backdrop.fill_to = Vector2(1.0, 1.0)
		_backdrop.width = 128
		_backdrop.height = 128


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree() and UI.redraw_due(self):
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_texture_rect(_backdrop, r, false)
	# A soft glow behind the item, breathing.
	var c := size / 2.0
	var s := minf(size.x, size.y)
	var pulse := 0.5 + 0.5 * sin(_t * 1.6)
	draw_circle(c, s * 0.36, Color(accent, 0.07 + 0.05 * pulse))
	draw_circle(c, s * 0.26, Color(accent, 0.08 + 0.05 * pulse))
	draw_arc(c, s * 0.40, 0.0, TAU, 64, Color(accent, 0.25), 1.5, true)
	draw_arc(c, s * 0.40, _t * 0.4, _t * 0.4 + 1.2, 24, Color(accent, 0.8), 2.5, true)
	draw_arc(c, s * 0.40, _t * 0.4 + PI, _t * 0.4 + PI + 1.2, 24, Color(accent, 0.8), 2.5, true)
	if item_id != "":
		var k := s * 0.56
		var bob := Vector2(0, sin(_t * 1.2) * s * 0.015)
		Items.draw_icon(self, item_id, Rect2(c - Vector2(k, k) / 2.0 + bob, Vector2(k, k)))
	# The frame: a thin line round it, brackets at the corners.
	draw_rect(r.grow(-1), Color(accent, 0.45), false, 1.5)
	var b := s * 0.12
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := Vector2(corner.x * size.x, corner.y * size.y)
		var dx := Vector2(b if corner.x == 0 else -b, 0)
		var dy := Vector2(0, b if corner.y == 0 else -b)
		var q := p + Vector2(3 if corner.x == 0 else -3, 3 if corner.y == 0 else -3)
		draw_line(q, q + dx, accent, 3.0)
		draw_line(q, q + dy, accent, 3.0)
	if badge != "":
		var f := ThemeDB.fallback_font
		var fs := maxi(Settings.MIN_FONT, int(s * 0.1))
		draw_string(f, Vector2(size.x - fs * 1.4, fs * 1.5), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)
