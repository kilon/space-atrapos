class_name SurfaceSprites
extends RefCounted
## Detailed, procedurally painted character sprites (the pilot's suit has a
## walk cycle) for planet
## surfaces: the astronaut pilot. Painted at 2x size
## from layered shapes with per-pixel lighting (upper-left light, specular
## highlights) and a dark outline, then cached.

static var _cache := {}


## Paints shaded shapes into an Image.
class Painter:
	var img: Image
	var w: int
	var h: int
	var light := Vector3(-0.5, -0.65, 0.58).normalized()

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

	func blend(x: int, y: int, c: Color, a: float) -> void:
		if a <= 0.0 or x < 0 or y < 0 or x >= w or y >= h:
			return
		var d := img.get_pixel(x, y)
		var out := Color(c.r, c.g, c.b, a)
		if d.a > 0.0:
			out = d.lerp(Color(c.r, c.g, c.b, 1.0), a)
			out.a = maxf(d.a, a)
		img.set_pixel(x, y, out)

	func lit(base: Color, n: Vector3, gloss := 0.0) -> Color:
		var l := clampf(n.dot(light), 0.0, 1.0)
		var c := Color(base.r * (0.4 + 0.75 * l), base.g * (0.4 + 0.75 * l), base.b * (0.4 + 0.75 * l))
		if gloss > 0.0:
			c = c.lerp(Color.WHITE, clampf(pow(l, 16.0) * gloss, 0.0, 1.0))
		return c

	## Shaded ellipse (sphere-like normal). mask: only paint over existing pixels.
	func ellipse(cx: float, cy: float, rx: float, ry: float, base: Color, gloss := 0.0, mask := false, flat := false) -> void:
		var m := minf(rx, ry)
		for y in range(floori(cy - ry) - 1, ceili(cy + ry) + 2):
			for x in range(floori(cx - rx) - 1, ceili(cx + rx) + 2):
				var u := (x + 0.5 - cx) / rx
				var v := (y + 0.5 - cy) / ry
				var d := sqrt(u * u + v * v)
				var cover := clampf((1.0 - d) * m + 0.5, 0.0, 1.0)
				if cover <= 0.0:
					continue
				if mask and (x < 0 or y < 0 or x >= w or y >= h or img.get_pixel(x, y).a < 0.5):
					continue
				var dd := minf(d, 1.0)
				var n := Vector3(u * 0.85, v * 0.85, sqrt(1.0 - dd * dd) + 0.3).normalized()
				blend(x, y, base if flat else lit(base, n, gloss), cover)

	## Rounded rectangle, shaded like a cylinder (round across its width).
	func rrect(x0: float, y0: float, x1: float, y1: float, r: float, base: Color, gloss := 0.0) -> void:
		var cx := (x0 + x1) * 0.5
		var cy := (y0 + y1) * 0.5
		var hx := (x1 - x0) * 0.5
		var hy := (y1 - y0) * 0.5
		for y in range(floori(y0) - 1, ceili(y1) + 1):
			for x in range(floori(x0) - 1, ceili(x1) + 1):
				var qx := absf(x + 0.5 - cx) - (hx - r)
				var qy := absf(y + 0.5 - cy) - (hy - r)
				var dist := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r
				var cover := clampf(0.5 - dist, 0.0, 1.0)
				if cover <= 0.0:
					continue
				var u := clampf((x + 0.5 - cx) / hx, -1.0, 1.0)
				var v := clampf((y + 0.5 - cy) / hy, -1.0, 1.0)
				var n := Vector3(u * 0.8, v * 0.3, sqrt(maxf(0.05, 1.0 - u * u * 0.64))).normalized()
				blend(x, y, lit(base, n, gloss), cover)

	func poly(points: PackedVector2Array, base: Color, n := Vector3(0, 0, 1)) -> void:
		var r := Rect2(points[0], Vector2.ZERO)
		for p in points:
			r = r.expand(p)
		var c := lit(base, n.normalized())
		for y in range(floori(r.position.y), ceili(r.end.y) + 1):
			for x in range(floori(r.position.x), ceili(r.end.x) + 1):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
					# Slightly lighter toward the top for a bit of form.
					var k := 1.0 + 0.15 * (1.0 - (y - r.position.y) / maxf(1.0, r.size.y))
					blend(x, y, Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0)), 1.0)

	func line(a: Vector2, b: Vector2, width: float, base: Color) -> void:
		var r := Rect2(a, Vector2.ZERO).expand(b).grow(width)
		for y in range(floori(r.position.y), ceili(r.end.y)):
			for x in range(floori(r.position.x), ceili(r.end.x)):
				var p := Vector2(x + 0.5, y + 0.5)
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				var cover := clampf(width * 0.5 - d + 0.5, 0.0, 1.0)
				if cover > 0.0:
					var side := clampf((p - a).cross(b - a) / maxf(1.0, (b - a).length()) / (width * 0.5), -1.0, 1.0)
					blend(x, y, lit(base, Vector3(side * 0.7, -0.3, 0.8).normalized()), cover)

	## Dark outline around everything painted so far.
	func outline(col := Color(0.05, 0.05, 0.08)) -> void:
		var data := img.get_data()
		for y in h:
			for x in w:
				if data[(y * w + x) * 4 + 3] > 100:
					continue
				var edge := false
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var nx := x + ox
						var ny := y + oy
						if nx >= 0 and ny >= 0 and nx < w and ny < h and data[(ny * w + nx) * 4 + 3] > 160:
							edge = true
				if edge:
					img.set_pixel(x, y, col)

	func texture() -> ImageTexture:
		return ImageTexture.create_from_image(img)


# --- Astronaut ---------------------------------------------------------------------

## The pilot in a spacesuit, 112 x 176 (shown at half size, feet at the bottom).
static func astronaut() -> ImageTexture:
	if _cache.has("astronaut"):
		return _cache["astronaut"]
	var p := Painter.new(112, 176)
	var suit := Color(0.92, 0.93, 0.95)
	var grey := Color(0.56, 0.58, 0.63)
	var dark := Color(0.24, 0.25, 0.3)
	var red := Color(0.86, 0.28, 0.22)
	var gold := Color(0.95, 0.76, 0.3)
	# Backpack (behind the body).
	p.rrect(18, 58, 50, 120, 9, grey, 0.2)
	p.rrect(22, 66, 30, 112, 3, dark)
	p.ellipse(40, 66, 5, 4, Color(0.3, 0.75, 1.0), 0.8)
	# Legs, knee pads and boots.
	p.rrect(34, 108, 55, 158, 9, suit, 0.25)
	p.rrect(57, 108, 78, 158, 9, suit, 0.25)
	p.ellipse(44.5, 132, 9, 7, grey, 0.3)
	p.ellipse(67.5, 132, 9, 7, grey, 0.3)
	p.rrect(29, 148, 56, 172, 8, dark, 0.3)
	p.rrect(56, 148, 83, 172, 8, dark, 0.3)
	p.rrect(29, 166, 56, 173, 3, Color(0.45, 0.45, 0.5))
	p.rrect(56, 166, 83, 173, 3, Color(0.45, 0.45, 0.5))
	# Arms with red cuff stripes and orange gloves.
	p.rrect(16, 64, 34, 114, 9, suit, 0.25)
	p.rrect(78, 64, 96, 114, 9, suit, 0.25)
	p.rrect(16, 96, 34, 103, 2, red)
	p.rrect(78, 96, 96, 103, 2, red)
	p.ellipse(25, 117, 10, 9, Color(0.95, 0.55, 0.16), 0.4)
	p.ellipse(87, 117, 10, 9, Color(0.95, 0.55, 0.16), 0.4)
	# Torso: suit, red chest stripe, control panel, belt with gold buckle.
	p.rrect(29, 58, 83, 122, 13, suit, 0.3)
	p.rrect(31, 68, 81, 73, 2, red)
	p.rrect(41, 77, 71, 101, 4, Color(0.3, 0.32, 0.38), 0.2)
	p.ellipse(48, 84, 3, 3, Color(1, 0.3, 0.25), 0.9)
	p.ellipse(56, 84, 3, 3, Color(0.35, 1, 0.45), 0.9)
	p.ellipse(64, 84, 3, 3, Color(0.35, 0.75, 1), 0.9)
	p.rrect(45, 90, 67, 97, 2, Color(0.15, 0.6, 0.9), 0.6)
	p.rrect(29, 108, 83, 116, 2, dark)
	p.rrect(50, 106, 62, 118, 2, gold, 0.7)
	# Mission patch on the shoulder: blue disc with a gold labrys.
	p.ellipse(87, 76, 6, 6, Color(0.15, 0.3, 0.72), 0.3)
	p.line(Vector2(87, 72), Vector2(87, 80), 1.2, gold)
	p.ellipse(85, 75, 1.8, 2.5, gold, 0.0, false, true)
	p.ellipse(89, 75, 1.8, 2.5, gold, 0.0, false, true)
	# Neck ring and helmet.
	p.ellipse(56, 62, 27, 8, grey, 0.4)
	p.ellipse(56, 37, 30, 30, suit, 0.7)
	p.ellipse(60, 39, 23, 19, gold, 0.9)  # visor rim
	_visor(p, 60, 39, 21, 17)
	# Helmet lamp and antenna.
	p.rrect(80, 20, 92, 30, 3, grey, 0.4)
	p.ellipse(89, 25, 3.5, 3.5, Color(1, 1, 0.8), 1.0)
	p.line(Vector2(38, 12), Vector2(31, 1), 2.0, grey)
	p.ellipse(31, 2, 2.5, 2.5, Color(1, 0.3, 0.25), 0.9)
	p.outline()
	_cache["astronaut"] = p.texture()
	return _cache["astronaut"]


## The player's armoured suit (a procedural recreation of the red-and-gold
## mech sprite), 112 x 200: red armour plates, gold trim, black joints,
## glowing cyan eye slit, chest core and thigh lights. Standing pose.
static func mech() -> ImageTexture:
	if not _cache.has("mech"):
		_cache["mech"] = ImageTexture.create_from_image(_mech_image(0.0, false))
	return _cache["mech"]


static var _images := {}


## Paints the suit's images (standing + walk cycle) ahead of time - safe on a
## worker thread (only Images, no textures); mech() / mech_walk() then just
## upload them.
static func prepare_images() -> void:
	var out := {"stand": _paint_mech(0.0, false)}
	for i in WALK_FRAMES:
		out["walk%d" % i] = _paint_mech(TAU * i / WALK_FRAMES, true)
	_images = out


static func _mech_image(phase: float, walking: bool) -> Image:
	if not walking and _images.has("stand"):
		return _images["stand"]
	if walking:
		var k := "walk%d" % roundi(phase / TAU * WALK_FRAMES)
		if _images.has(k):
			return _images[k]
	return _paint_mech(phase, walking)


## Walk cycle of the suit: WALK_FRAMES frames (one full stride, two steps).
const WALK_FRAMES := 8

static func mech_walk() -> Array[ImageTexture]:
	if not _cache.has("mech_walk"):
		var frames: Array[ImageTexture] = []
		for i in WALK_FRAMES:
			frames.append(ImageTexture.create_from_image(_mech_image(TAU * i / WALK_FRAMES, true)))
		_cache["mech_walk"] = frames
	return _cache["mech_walk"]


## One pose. phase: 0..TAU through the stride. The left leg lifts in the
## first half, the right in the second; arms swing against the legs; the
## upper body dips as the weight lands on each foot.
static func _paint_mech(phase: float, walking: bool) -> Image:
	var p := Painter.new(112, 200)
	var red := Color(0.86, 0.12, 0.1)
	var red_d := Color(0.6, 0.07, 0.07)
	var gold := Color(0.96, 0.66, 0.16)
	var joint := Color(0.16, 0.16, 0.2)
	var cyan := Color(0.35, 0.9, 1.0)
	var sn := sin(phase) if walking else 0.0
	var cs := cos(phase) if walking else 0.0
	var lift := [maxf(0.0, sn) * 12.0, maxf(0.0, -sn) * 12.0]      # left, right foot raised
	var stride := [cs * 5.0, -cs * 5.0]                             # feet forward / back (+x = facing)
	var swing := [-cs * 6.0, cs * 6.0]                              # forearms (opposite to the legs)
	var dip := (1.0 - absf(sn)) * 3.0 if walking else 0.0          # body lowest when both feet are down
	# Legs (back leg first: the one swinging back is behind).
	var order := [0, 1] if stride[0] < stride[1] else [1, 0]
	for side in order:
		var x0: float = [33.0, 56.0][side]
		var l: float = lift[side]
		var dx: float = stride[side]
		var shade := 1.0 if stride[side] >= stride[1 - side] else 0.88  # the trailing leg a touch darker
		var r := Color(red.r * shade, red.g * shade, red.b * shade)
		p.rrect(x0 + 3 + dx * 0.4, 112 + dip, x0 + 21 + dx, 186 - l, 7, joint, 0.2)
		p.rrect(x0 + dx * 0.3, 114 + dip, x0 + 23 + dx * 0.3, 146 + dip - l * 0.3, 9, r, 0.6)
		p.rrect(x0 + 7 + dx * 0.3, 124 + dip, x0 + 12 + dx * 0.3, 138 + dip - l * 0.3, 2, cyan, 0.9)
		p.ellipse(x0 + 11.5 + dx * 0.6, 152 - l * 0.6, 9, 8, gold, 0.6)
		p.rrect(x0 + 2 + dx * 0.8, 158 - l, x0 + 22 + dx * 0.8, 182 - l, 7, r, 0.6)
		var bx: float = [29.0, 55.0][side] + dx
		p.rrect(bx, 180 - l, bx + 28, 197 - l, 6, red_d, 0.4)
		p.rrect(bx, 192 - l, bx + 28, 198 - l, 2, joint)
	# Arms: big shoulder pauldrons, red forearms, gold cuffs, black fists.
	for side in 2:
		var ax: float = [12.0, 79.0][side]
		var sw: float = swing[side]
		var sx := sw * 0.35   # the hand swings slightly forward / back too
		p.rrect(ax + 2, 66 + dip, ax + 20, 112 + dip + sw * 0.5, 8, joint, 0.2)
		p.rrect(ax + sx, 84 + dip + sw * 0.5, ax + 21 + sx, 112 + dip + sw, 8, red, 0.6)
		p.rrect(ax + sx, 106 + dip + sw, ax + 21 + sx, 113 + dip + sw, 2, gold, 0.6)
		p.ellipse(ax + 10 + sx, 120 + dip + sw, 9, 9, joint, 0.5)
	# Torso: red chest plates over a black core, gold abdomen segments.
	var d := dip
	p.rrect(30, 60 + d, 82, 116 + d, 12, joint, 0.2)
	p.rrect(28, 58 + d, 84, 92 + d, 14, red, 0.7)
	for k in 4:
		p.rrect(42, 92 + k * 6 + d, 70, 96 + k * 6 + d, 2, gold, 0.5)
	p.ellipse(56, 72 + d, 8, 7, cyan, 1.0)                 # chest core
	p.ellipse(56, 72 + d, 4, 3.5, Color(0.9, 1.0, 1.0), 1.0, false, true)
	p.rrect(36, 66 + d, 46, 70 + d, 2, cyan, 0.9)
	p.rrect(66, 66 + d, 76, 70 + d, 2, cyan, 0.9)
	p.ellipse(22, 64 + d, 16, 14, red, 0.8)                # pauldrons
	p.ellipse(90, 64 + d, 16, 14, red, 0.8)
	p.ellipse(22, 68 + d, 9, 5, gold, 0.5)
	p.ellipse(90, 68 + d, 9, 5, gold, 0.5)
	# Helmet: red, swept back crest, gold cheek plates, glowing eye slit.
	var o := Vector2(0, d)
	p.ellipse(56, 54 + d, 10, 6, joint, 0.3)
	p.ellipse(56, 34 + d, 20, 22, red, 0.8)
	p.poly(PackedVector2Array([Vector2(56, 8) + o, Vector2(74, 2) + o, Vector2(66, 22) + o]), red_d, Vector3(0.2, -0.5, 1))
	p.poly(PackedVector2Array([Vector2(40, 40) + o, Vector2(48, 44) + o, Vector2(46, 54) + o, Vector2(40, 50) + o]), gold, Vector3(-0.5, 0, 1))
	p.poly(PackedVector2Array([Vector2(72, 40) + o, Vector2(64, 44) + o, Vector2(66, 54) + o, Vector2(72, 50) + o]), gold, Vector3(0.5, 0, 1))
	p.rrect(42, 32 + d, 70, 37 + d, 2, cyan, 1.0)
	p.rrect(46, 33 + d, 66, 35 + d, 1, Color(0.95, 1.0, 1.0), 1.0)
	p.outline()
	return p.img


## Reflective visor: deep blue to cyan gradient with a curved highlight.
static func _visor(p: Painter, cx: float, cy: float, rx: float, ry: float) -> void:
	for y in range(floori(cy - ry) - 1, ceili(cy + ry) + 2):
		for x in range(floori(cx - rx) - 1, ceili(cx + rx) + 2):
			var u := (x + 0.5 - cx) / rx
			var v := (y + 0.5 - cy) / ry
			var d := sqrt(u * u + v * v)
			var cover := clampf((1.0 - d) * ry + 0.5, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var c := Color(0.04, 0.07, 0.2).lerp(Color(0.15, 0.62, 0.92), clampf((v + 1.0) * 0.5, 0.0, 1.0) * 0.9)
			c = c.lerp(Color(0.95, 0.65, 0.3), clampf(d - 0.8, 0.0, 0.2) * 2.0)  # warm rim reflection
			var arc := absf(Vector2(u + 0.15, v + 0.15).length() - 0.62)
			if arc < 0.09 and u < 0.1 and v < 0.05:
				c = c.lerp(Color.WHITE, 0.85)
			if Vector2(u - 0.35, v + 0.45).length() < 0.12:
				c = Color.WHITE
			p.blend(x, y, c, cover)
