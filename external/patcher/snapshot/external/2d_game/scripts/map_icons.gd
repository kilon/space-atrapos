class_name MapIcons
## Map markers in the reference console's style: a glowing ring on dark
## glass with a line glyph inside, in cyan (places), orange (you, your ship,
## what's active) or red (danger). Used by the planet map, the system map and
## the galaxy map, drawn on any CanvasItem:
##   MapIcons.badge(ci, at, radius, colour, kind)
##   MapIcons.glyph(ci, at, size, colour, kind)       (the glyph alone)
## Kinds: temple, city, ship, you, warning, star, planet, moon, ringed,
## station, gate, asteroid, signal, quest, pirate, trader, mountain.

## (Stations, planets, gates: the GUI's second colour, steel blue - NeonTheme.INFO. The name is older.)
const CYAN := Color(0.42, 0.7, 1.0)
const ORANGE := Color(1.0, 0.55, 0.15)
const RED := Color(1.0, 0.25, 0.2)


## A circled marker: soft glow, dark glass, a double ring and the glyph.
static func badge(ci: CanvasItem, at: Vector2, r: float, col: Color, kind: String, pulse := 0.0) -> void:
	# (discs as one texture, batched - draw_circle by the hundred on the galaxy
	# map was ~10 ms a redraw)
	var d := ExhaustTrail.disc()
	for k in 3:
		var rr := r * (1.25 + 0.22 * k) + pulse * 3.0
		ci.draw_texture_rect(d, Rect2(at - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(col, 0.07 + 0.03 * pulse))
	ci.draw_texture_rect(d, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(NeonTheme.BG, 0.88))
	ci.draw_arc(at, r, 0.0, TAU, 32, col, maxf(1.5, r * 0.11), true)
	ci.draw_arc(at, r * 0.8, 0.0, TAU, 24, Color(col, 0.35), 1.0, false)
	glyph(ci, at, r * 0.62, col.lightened(0.25), kind)


## The line glyph for `kind`, about 2 x s across.
static func glyph(ci: CanvasItem, at: Vector2, s: float, col: Color, kind: String) -> void:
	var w := maxf(1.3, s * 0.16)
	var P := func(x: float, y: float) -> Vector2: return at + Vector2(x, y) * s
	var line := func(pts: Array, closed := false):
		var arr := PackedVector2Array()
		for p in pts:
			arr.append(P.call(p[0], p[1]))
		if closed:
			arr.append(arr[0])
		ci.draw_polyline(arr, col, w, true)
	match kind:
		"temple":   # pediment, columns, base (a Greek temple / the palace)
			line.call([[-0.9, -0.35], [0.0, -0.9], [0.9, -0.35]], true)
			for x in [-0.6, -0.2, 0.2, 0.6]:
				line.call([[x, -0.25], [x, 0.55]])
			line.call([[-0.95, 0.7], [0.95, 0.7]])
		"city":     # a skyline of towers
			line.call([[-0.9, 0.75], [-0.9, -0.1], [-0.5, -0.1], [-0.5, 0.75]])
			line.call([[-0.4, 0.75], [-0.4, -0.75], [0.05, -0.75], [0.05, 0.75]])
			line.call([[0.15, 0.75], [0.15, -0.35], [0.55, -0.35], [0.55, 0.75]])
			line.call([[0.62, 0.75], [0.62, 0.1], [0.9, 0.1], [0.9, 0.75]])
			line.call([[-1.0, 0.75], [1.0, 0.75]])
		"ship":     # your lander: a small delta ship, nose up
			line.call([[0.0, -0.95], [0.75, 0.75], [0.0, 0.4], [-0.75, 0.75]], true)
			line.call([[0.0, -0.3], [0.0, 0.4]])
		"you":      # a walking figure
			ci.draw_circle(P.call(0.0, -0.62), s * 0.22, col)
			line.call([[0.0, -0.35], [0.0, 0.25]])
			line.call([[-0.5, -0.05], [0.0, -0.2], [0.5, -0.05]])
			line.call([[-0.4, 0.85], [0.0, 0.25], [0.4, 0.85]])
		"warning":  # a hazard triangle with "!"
			line.call([[0.0, -0.9], [0.9, 0.7], [-0.9, 0.7]], true)
			line.call([[0.0, -0.35], [0.0, 0.2]])
			ci.draw_circle(P.call(0.0, 0.45), w * 0.7, col)
		"pirate":   # a skull
			ci.draw_arc(P.call(0.0, -0.15), s * 0.6, PI * 0.85, PI * 2.15, 18, col, w, true)
			line.call([[-0.5, 0.1], [-0.35, 0.6], [0.35, 0.6], [0.5, 0.1]])
			ci.draw_circle(P.call(-0.25, -0.15), s * 0.16, col)
			ci.draw_circle(P.call(0.25, -0.15), s * 0.16, col)
		"mountain":
			line.call([[-0.95, 0.7], [-0.3, -0.5], [0.05, 0.05], [0.35, -0.75], [0.95, 0.7]], true)
		"star":     # a sun: disc and rays
			ci.draw_circle(at, s * 0.42, col)
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				ci.draw_line(at + d * s * 0.62, at + d * s * 0.95, col, w, true)
		"planet":   # a globe with a meridian and a parallel
			ci.draw_arc(at, s * 0.8, 0.0, TAU, 28, col, w, true)
			ci.draw_line(P.call(-0.8, 0.0), P.call(0.8, 0.0), Color(col, 0.7), w * 0.7, true)
			_ellipse(ci, at, Vector2(s * 0.32, s * 0.8), Color(col, 0.7), w * 0.7)
		"ringed":   # a planet with rings
			ci.draw_arc(at, s * 0.55, 0.0, TAU, 24, col, w, true)
			_ellipse(ci, at, Vector2(s * 1.0, s * 0.3), col, w, -0.35)
		"moon":     # a crescent
			ci.draw_arc(at, s * 0.75, PI * 0.35, PI * 1.65, 20, col, w, true)
			ci.draw_arc(at + Vector2(s * 0.35, 0), s * 0.6, PI * 0.55, PI * 1.45, 16, col, w, true)
		"station":  # a space station: a hub with docking arms and two solar wings
			line.call([[-0.28, -0.28], [0.28, -0.28], [0.28, 0.28], [-0.28, 0.28]], true)
			line.call([[0.0, -0.28], [0.0, -0.75]])
			line.call([[0.0, 0.28], [0.0, 0.75]])
			line.call([[-0.28, 0.0], [-0.45, 0.0]])
			line.call([[0.28, 0.0], [0.45, 0.0]])
			line.call([[-0.95, -0.3], [-0.45, -0.3], [-0.45, 0.3], [-0.95, 0.3]], true)
			line.call([[0.45, -0.3], [0.95, -0.3], [0.95, 0.3], [0.45, 0.3]], true)
		"gate":     # a jump gate: a portal with a through-arrow
			_ellipse(ci, at, Vector2(s * 0.45, s * 0.9), col, w)
			line.call([[-0.95, 0.0], [0.95, 0.0]])
			line.call([[0.55, -0.35], [0.95, 0.0], [0.55, 0.35]])
		"asteroid": # a lumpy rock with a crater
			line.call([[-0.8, -0.1], [-0.45, -0.7], [0.25, -0.75], [0.85, -0.2], [0.7, 0.5], [0.05, 0.85], [-0.6, 0.55]], true)
			ci.draw_arc(P.call(0.1, 0.0), s * 0.22, 0.0, TAU, 12, col, w * 0.7, true)
		"signal":   # radio waves from a point
			ci.draw_circle(P.call(-0.55, 0.0), s * 0.16, col)
			for k in 3:
				ci.draw_arc(P.call(-0.55, 0.0), s * (0.45 + k * 0.4), -0.7, 0.7, 10, col, w, true)
		"quest":    # an exclamation in a diamond
			line.call([[0.0, -0.95], [0.95, 0.0], [0.0, 0.95], [-0.95, 0.0]], true)
			line.call([[0.0, -0.45], [0.0, 0.15]])
			ci.draw_circle(P.call(0.0, 0.42), w * 0.7, col)
		"trader":   # a crate
			line.call([[-0.75, -0.55], [0.75, -0.55], [0.75, 0.65], [-0.75, 0.65]], true)
			line.call([[-0.75, -0.05], [0.75, -0.05]])
			line.call([[-0.15, -0.55], [-0.15, -0.05]])
		_:
			ci.draw_circle(at, s * 0.35, col)


static func _ellipse(ci: CanvasItem, at: Vector2, r: Vector2, col: Color, w: float, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for k in 33:
		var a := k * TAU / 32.0
		pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	ci.draw_polyline(pts, col, w, true)


## A route between two points: a glowing orange curve (or a dotted cyan one),
## bowed sideways by `bend` px, with small nodes along it.
static func route(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, bend := 0.0, dotted := false, width := 3.0) -> void:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * bend
	var pts := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var u := float(i) / n
		pts.append(a.lerp(mid, u).lerp(mid.lerp(b, u), u))
	if dotted:
		for i in range(0, n, 2):
			ci.draw_line(pts[i], pts[i + 1], Color(col, 0.85), width * 0.6, true)
		return
	ci.draw_polyline(pts, Color(col, 0.18), width * 4.0, true)
	ci.draw_polyline(pts, Color(col, 0.35), width * 2.0, true)
	ci.draw_polyline(pts, col.lightened(0.15), width, true)
	for i in [7, 14, 21]:
		ci.draw_circle(pts[i], width * 1.3, col.lightened(0.4))
