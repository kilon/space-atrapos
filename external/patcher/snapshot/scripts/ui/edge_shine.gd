extends Control
## A glint running round a panel's edge - a bright point with a lens flare's cross and a fading trail,
## and a dimmer twin on the far side. Over the panel, never catching the mouse. Paced by time.
##   EdgeShine.add_to(panel)     (fills it; freed with it)

## Seconds for a glint to go once round.
@export var lap := 8.0
## The glint's colour (the theme's gold).
@export var tint := Color(1.0, 0.82, 0.3)
## How far in from the edge it runs (px).
@export var inset := 1.5

var _t := 0.0


static func add_to(panel: Node) -> Control:
	var s: Control = load("res://scripts/ui/edge_shine.gd").new()
	s.name = "EdgeShine"
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(s)
	return s


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	queue_redraw()


## The point a share `f` (0..1) round the rect's edge, clockwise from the top left.
func _at(f: float) -> Vector2:
	var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	var per := 2.0 * (r.size.x + r.size.y)
	if per <= 0.0:
		return r.position
	var d := fposmod(f, 1.0) * per
	if d < r.size.x:
		return r.position + Vector2(d, 0)
	d -= r.size.x
	if d < r.size.y:
		return r.position + Vector2(r.size.x, d)
	d -= r.size.y
	if d < r.size.x:
		return r.position + Vector2(r.size.x - d, r.size.y)
	d -= r.size.x
	return r.position + Vector2(0, r.size.y - d)


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var per := 2.0 * (size.x + size.y)
	var head := fposmod(_t / maxf(lap, 0.1), 1.0)
	_glint(head, per, 1.0)
	_glint(head + 0.5, per, 0.45)


func _glint(head: float, per: float, strength: float) -> void:
	# the trail: short pieces behind the head, thinner and fainter towards its end
	var tail_px := 150.0
	var steps := 18
	var prev := _at(head)
	for i in range(1, steps + 1):
		var f := head - (tail_px / per) * float(i) / steps
		var p := _at(f)
		var k := 1.0 - float(i) / steps
		draw_line(prev, p, Color(tint, 0.95 * k * k * strength), 1.0 + 2.5 * k, true)
		prev = p
	var c := _at(head)
	# the glow: soft rings
	for r in [16.0, 10.0, 6.0, 3.5]:
		draw_circle(c, r, Color(tint, 0.12 * strength * (12.0 / (r + 2.0))))
	# the flare: a long thin cross and a short diagonal one, fading out from the core
	var arm := 26.0 * strength + 8.0
	for dirv in [Vector2(1, 0), Vector2(0, 1)]:
		for sgn in [-1.0, 1.0]:
			var a := c
			for j in 6:
				var b2: Vector2 = c + dirv * sgn * arm * float(j + 1) / 6.0
				draw_line(a, b2, Color(1, 0.97, 0.85, 0.7 * strength * (1.0 - float(j) / 6.0)), 1.0, true)
				a = b2
	for dirv in [Vector2(1, 1).normalized(), Vector2(1, -1).normalized()]:
		draw_line(c - dirv * arm * 0.35, c + dirv * arm * 0.35, Color(1, 0.95, 0.8, 0.35 * strength), 1.0, true)
	draw_circle(c, 1.8, Color(1, 1, 0.95, 0.95 * strength))
