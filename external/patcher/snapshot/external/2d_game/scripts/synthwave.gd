class_name Synthwave
extends Control
## Title-screen backdrop: a striped retro sun sinking behind neon-rimmed
## mountains and a glowing perspective grid scrolling toward you. Drawn over
## the starfield (the sky above the horizon stays transparent).

const PINK := Color(1.0, 0.2, 0.7)
const CYAN := Color(0.3, 0.9, 1.0)

var _t := 0.0
var _mountains := []   # [PackedVector2Array] in 0..1 x and height fractions


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	for layer in 2:
		var pts := PackedVector2Array()
		var x := -0.05
		while x < 1.08:
			# Higher peaks toward the sides, keeping the sun visible in the middle.
			var side := absf(x - 0.5) * 2.0
			var h := rng.randf_range(0.2, 1.0) * lerpf(0.25, 1.0, side) * (1.0 if layer == 0 else 0.6)
			pts.append(Vector2(x, h))
			x += rng.randf_range(0.03, 0.08)
		_mountains.append(pts)


func _process(delta: float) -> void:
	_t += delta
	# Parent is a CanvasLayer (no anchors): follow the window size.
	size = get_viewport_rect().size
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var hz := h * 0.66
	# Horizon haze.
	for k in 8:
		var a := 0.05 * (8 - k) / 8.0
		draw_rect(Rect2(0, hz - k * 14 - 14, w, 14), Color(PINK, a * 0.6))
	# The sun: vertical gradient, cut by widening gaps in its lower half.
	var r := h * 0.2
	var c := Vector2(w / 2.0, hz - r * 0.45)
	for k in 6:
		draw_circle(c, r * (1.15 + k * 0.12), Color(1.0, 0.35, 0.6, 0.05))
	var y := c.y - r
	while y < minf(c.y + r, hz):
		var v := (y - (c.y - r)) / (2.0 * r)   # 0 top .. 1 bottom
		var gap := false
		if v > 0.5:
			var band := fmod((v - 0.5) * 14.0 + _t * 0.4, 1.0)
			gap = band < lerpf(0.08, 0.5, (v - 0.5) * 2.0)
		if not gap:
			var half := sqrt(maxf(0.0, r * r - (y - c.y) * (y - c.y)))
			var col := Color(1.0, 0.92, 0.35).lerp(Color(1.0, 0.45, 0.25), smoothstep(0.0, 0.5, v)).lerp(Color(1.0, 0.15, 0.6), smoothstep(0.45, 1.0, v))
			draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), col, 2.0)
		y += 2.0
	# Mountains (back row lighter), neon rims.
	for i in [1, 0]:
		var m: PackedVector2Array = _mountains[i]
		var poly := PackedVector2Array([Vector2(-10, hz + 1)])
		var rim := PackedVector2Array()
		for p in m:
			var q := Vector2(p.x * w, hz - p.y * h * 0.16)
			poly.append(q)
			rim.append(q)
		poly.append(Vector2(w + 10, hz + 1))
		draw_colored_polygon(poly, Color(0.1, 0.03, 0.18) if i == 1 else Color(0.04, 0.01, 0.09))
		draw_polyline(rim, Color(PINK if i == 0 else CYAN, 0.25), 5.0, true)
		draw_polyline(rim, Color(PINK if i == 0 else CYAN, 0.85 if i == 0 else 0.5), 1.5, true)
	# Ground below the horizon.
	draw_polygon(PackedVector2Array([Vector2(0, hz), Vector2(w, hz), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0.14, 0.02, 0.2), Color(0.14, 0.02, 0.2), Color(0.02, 0.0, 0.05), Color(0.02, 0.0, 0.05)]))
	# Perspective grid: lines fanning out from the vanishing point...
	var vp := Vector2(w / 2.0, hz)
	for k in range(-24, 25):
		var bx := w / 2.0 + k * w * 0.09
		var a := Color(PINK, 0.55)
		draw_line(vp + Vector2(k * 6.0, 0), Vector2(bx, h), Color(PINK, 0.12), 4.0, true)
		draw_line(vp + Vector2(k * 6.0, 0), Vector2(bx, h), a, 1.2, true)
	# ...and cross lines rushing toward you.
	var n := 16
	for i in n:
		var z := fmod(float(i) / n + _t * 0.08, 1.0)
		var gy := hz + (h - hz) * pow(z, 2.6)
		var a := clampf(z * 1.4, 0.0, 1.0)
		draw_line(Vector2(0, gy), Vector2(w, gy), Color(PINK, 0.15 * a), 5.0)
		draw_line(Vector2(0, gy), Vector2(w, gy), Color(1.0, 0.45, 0.85, 0.85 * a), 1.3)
	# Bright horizon line.
	draw_line(Vector2(0, hz), Vector2(w, hz), Color(1.0, 0.4, 0.8, 0.35), 8.0)
	draw_line(Vector2(0, hz), Vector2(w, hz), Color(1.0, 0.85, 0.95), 2.0)
