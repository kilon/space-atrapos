extends Node2D
## Main-quest beacon. "signal": the Phaistos-style spiral disc at the signal
## source. "thread": a beacon of Ariadne's Thread, crowned with a glowing
## labrys (Minoan double axe).

const GOLD := Color(1.0, 0.82, 0.38)
const CLAY := Color(0.78, 0.45, 0.28)

var style := "thread"
var _time := 0.0


func _ready() -> void:
	z_index = -3
	var enabler := VisibleOnScreenEnabler2D.new()
	enabler.rect = Rect2(-200, -200, 400, 400)
	add_child(enabler)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)

	# Expanding ping rings.
	for k in 2:
		var t := fmod(_time * 0.4 + k * 0.5, 1.0)
		draw_arc(Vector2.ZERO, 40.0 + 140.0 * t, 0, TAU, 48, Color(GOLD, 0.5 * (1.0 - t)), 2.0, true)
	draw_circle(Vector2.ZERO, 70.0, Color(GOLD, 0.06 + 0.04 * pulse))

	if style == "signal":
		_draw_disc(Vector2.ZERO, 46.0, _time * 0.3)
	else:
		# Pedestal with Minoan red/black bands, labrys floating above.
		draw_circle(Vector2.ZERO, 30.0, Color(0.22, 0.12, 0.1))
		draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(0.75, 0.2, 0.15), 5.0, true)
		draw_arc(Vector2.ZERO, 22.0, 0, TAU, 32, GOLD, 2.0, true)
		draw_labrys(self, Vector2(0, -6), 34.0, Color(GOLD, 0.85 + 0.15 * pulse), _time)


## A Phaistos-style clay disc: stamped signs spiralling toward the centre.
func _draw_disc(c: Vector2, r: float, spin: float) -> void:
	draw_circle(c, r + 3.0, CLAY.darkened(0.45))
	draw_circle(c, r, CLAY)
	draw_circle(c + Vector2(-r, -r) * 0.15, r * 0.8, CLAY.lightened(0.1))
	# Spiral line of "stamped" signs.
	var turns := 3.2
	var n := 44
	for i in n:
		var t := float(i) / n
		var ang := spin + t * turns * TAU
		var rad := r * (0.9 - 0.75 * t)
		var p := c + Vector2.from_angle(ang) * rad
		var s := 3.2 * (1.0 - 0.5 * t)
		if i % 3 == 0:
			draw_circle(p, s, CLAY.darkened(0.5))
		elif i % 3 == 1:
			draw_rect(Rect2(p - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6), CLAY.darkened(0.45))
		else:
			draw_line(p - Vector2(s, 0).rotated(ang), p + Vector2(s, 0).rotated(ang), CLAY.darkened(0.5), 1.6)
	# Spiral guide line.
	var pts := PackedVector2Array()
	for i in 80:
		var t := float(i) / 79.0
		pts.append(c + Vector2.from_angle(spin + t * turns * TAU + 0.12) * r * (0.97 - 0.75 * t))
	draw_polyline(pts, CLAY.darkened(0.3), 1.0, true)


## Minoan double axe. Static so the HUD/encyclopedia can draw it too.
static func draw_labrys(ci: CanvasItem, c: Vector2, size: float, col: Color, t := 0.0) -> void:
	var s := size
	ci.draw_line(c + Vector2(0, -s * 0.9), c + Vector2(0, s * 1.1), col.darkened(0.3), s * 0.09, true)
	for side in [-1.0, 1.0]:
		var blade := PackedVector2Array([
			c + Vector2(side * s * 0.08, -s * 0.35),
			c + Vector2(side * s * 0.75, -s * 0.75),
			c + Vector2(side * s * 0.62, 0.0),
			c + Vector2(side * s * 0.75, s * 0.75),
			c + Vector2(side * s * 0.08, s * 0.35)])
		ci.draw_colored_polygon(blade, col)
		var outline := blade.duplicate()
		outline.append(blade[0])
		ci.draw_polyline(outline, col.lightened(0.4), 1.5, true)
	ci.draw_circle(c, s * 0.12, col.lightened(0.3))
	if t > 0.0:
		ci.draw_circle(c, s * (1.1 + 0.08 * sin(t * 3.0)), Color(col, 0.08))
