class_name SurfaceTiles
extends RefCounted
## Procedural tile set for buildings on planet surfaces. Every texture is
## painted pixel by pixel and cached:
##   floor  - isometric diamond tiles (used in a TileMapLayer)
##   wall   - wall faces for the two isometric edge directions ("x" runs
##            down-right, "y" runs up-right), plain / window / door
##   roof   - diamond tiles drawn on top of the walls
##   column - a red Minoan column (wider at the top, black capital)
## Materials: "minoan" (red plaster, fresco band), "alien" (metal plating with
## glowing strips).

const TILE := Vector2i(128, 64)
const WALL_H := 120          # wall height in pixels
const DOOR := Vector2(0.27, 0.73)  # doorway opening along the edge (0..1)

static var _cache := {}
static var _noise: FastNoiseLite


static func _n(x: float, y: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 1234
		_noise.frequency = 0.08
		_noise.fractal_octaves = 3
	return _noise.get_noise_2d(x, y)


static func _hash(a: int, b: int, s := 0) -> float:
	var n := (a * 374761393 + b * 668265263 + s * 982451653) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


static func _cached(key: String, painter: Callable) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(painter.call())
	return _cache[key]


# --- Walls -------------------------------------------------------------------------

## Wall face texture. Image is 64 x (WALL_H + 32): the face rises WALL_H
## pixels above an edge that drops ("x") or climbs ("y") 32 px over 64.
static func wall(material: String, orient: String, kind: String, base: Color, light: Color) -> ImageTexture:
	var key := "wall|%s|%s|%s|%s|%s" % [material, orient, kind, base.to_html(), light.to_html()]
	return _cached(key, func(): return _paint_wall(material, orient, kind, base, light))


static func _paint_wall(material: String, orient: String, kind: String, base: Color, light: Color) -> Image:
	var w := 64
	var h := WALL_H + 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var shade := 1.0 if orient == "x" else 0.74   # lit from the upper left
	for x in w:
		var t := (x + 0.5) / w
		var top := x * 0.5 if orient == "x" else 32.0 - x * 0.5
		for y in h:
			var v := (y + 0.5 - top) / WALL_H
			if v < 0.0 or v > 1.0:
				continue
			var c := _wall_color(material, kind, t, v, x, y, shade, base, light)
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	return img


## Colour of a wall at (t along the edge, v down from the top).
static func _wall_color(material: String, kind: String, t: float, v: float, px: int, py: int,
		shade: float, base: Color, light: Color) -> Color:
	var trim := Color(0.88, 0.8, 0.62) if material == "minoan" else base.lightened(0.35)
	# Top of the wall: a lighter cap shows the wall's thickness.
	if v < 0.03:
		return trim.lightened(0.15)
	# Doorway: a see-through opening with a frame.
	if kind == "door":
		if t > DOOR.x and t < DOOR.y and v > 0.36:
			return Color(0, 0, 0, 0)
		if (t > DOOR.x - 0.05 and t < DOOR.y + 0.05 and v > 0.31) \
				and (t <= DOOR.x or t >= DOOR.y or v <= 0.36):
			var f := trim if material == "minoan" else light
			return _shaded(f, shade * (0.9 + 0.1 * _n(px * 4, py * 4)))
	var c: Color
	var emissive := false
	if material == "minoan":
		c = Color(0.7, 0.2, 0.13).lightened(_n(px * 2.5, py * 2.5) * 0.08)
		if v > 0.9:
			c = Color(0.22, 0.1, 0.08)                     # dark dado
		elif v < 0.075:
			c = trim                                     # cornice
			if v > 0.05 and fmod(t * 18.0, 1.0) < 0.5:
				c = trim.darkened(0.3)                   # dentils
		elif v > 0.15 and v < 0.33:
			# Fresco band: blue with white running waves and gold dots.
			var vv := (v - 0.15) / 0.18
			var s := fmod(t * 3.0, 1.0)
			c = Color(0.16, 0.38, 0.64)
			var wave := 0.5 + 0.28 * sin(s * TAU)
			if absf(vv - wave) < 0.09:
				c = Color(0.95, 0.94, 0.88)
			elif Vector2((s - 0.25) * 3.0, vv - 0.22).length() < 0.07 or Vector2((s - 0.75) * 3.0, vv - 0.78).length() < 0.07:
				c = Color(0.98, 0.78, 0.3)
			if vv < 0.07 or vv > 0.93:
				c = Color(0.1, 0.08, 0.08)
		elif v > 0.35 and v < 0.39:
			c = trim if fmod(t * 12.0, 1.0) < 0.5 else Color(0.12, 0.08, 0.07)
		if kind == "window" and t > 0.36 and t < 0.64 and v > 0.47 and v < 0.73:
			if t < 0.39 or t > 0.61 or v < 0.5 or v > 0.7 or absf(t - 0.5) < 0.012:
				c = trim
			else:
				c = Color(0.07, 0.05, 0.05).lerp(Color(0.25, 0.15, 0.08), (v - 0.5) * 3.0)
	else:
		# Alien plating: panels with seams, rivets and a glowing strip.
		c = base.lerp(base.darkened(0.25), v * 0.6).lightened(_n(px * 1.5, py * 1.5) * 0.05)
		var seam_t := fmod(t * 4.0, 1.0)
		if seam_t < 0.035 or absf(v - 0.62) < 0.008:
			c = base.darkened(0.45)
		elif (seam_t < 0.09 or seam_t > 0.95) and fmod(v * 10.0, 1.0) < 0.12:
			c = base.lightened(0.35)                     # rivets
		if absf(v - 0.3) < 0.016:
			c = light
			emissive = true
		if v > 0.94:
			c = base.darkened(0.5)
		if kind == "window":
			var d := Vector2((t - 0.5) * 64.0, (v - 0.5) * WALL_H).length()
			if d < 14.0:
				c = light.darkened(0.25).lerp(light.lightened(0.3), 1.0 - d / 14.0)
				emissive = true
			elif d < 17.0:
				c = base.lightened(0.3)
	return c if emissive else _shaded(c, shade)


static func _shaded(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


# --- Floors & roofs ------------------------------------------------------------------

## Isometric floor tile, 128 x 64. Kinds: minoan (flagstones), mosaic
## (Minoan rosette), alien (glowing hex plating).
static func floor_tile(kind: String, base: Color, light: Color, variant := 0) -> ImageTexture:
	var key := "floor|%s|%s|%s|%d" % [kind, base.to_html(), light.to_html(), variant]
	return _cached(key, func(): return _paint_diamond(kind, base, light, variant))


static func roof_tile(kind: String, base: Color, light: Color, variant := 0) -> ImageTexture:
	return floor_tile("roof_" + kind, base, light, variant)


static func _paint_diamond(kind: String, base: Color, light: Color, variant: int) -> Image:
	var img := Image.create_empty(TILE.x, TILE.y, false, Image.FORMAT_RGBA8)
	for x in TILE.x:
		for y in TILE.y:
			var dx := x + 0.5 - TILE.x / 2.0
			var dy := y + 0.5 - TILE.y / 2.0
			if absf(dx) / (TILE.x / 2.0) + absf(dy) / (TILE.y / 2.0) > 1.0:
				continue
			# Position inside the tile along the two grid axes, 0..1.
			var u := dx / TILE.x + dy / TILE.y + 0.5
			var v := -dx / TILE.x + dy / TILE.y + 0.5
			var c := _diamond_color(kind, u, v, x, y, base, light, variant)
			# Faint tile border so the grid reads as laid tiles.
			if u < 0.02 or v < 0.02 or u > 0.98 or v > 0.98:
				c = c.darkened(0.2)
			img.set_pixel(x, y, c)
	return img


static func _diamond_color(kind: String, u: float, v: float, px: int, py: int, base: Color, light: Color, variant: int) -> Color:
	var nz := _n(px * 3.0 + variant * 50, py * 3.0)
	match kind:
		"minoan":
			# Irregular flagstones on a jittered 3x3 grid.
			var gu := u * 3.0 + 0.15 * sin(v * 9.0 + variant)
			var gv := v * 3.0 + 0.15 * sin(u * 7.0 + variant * 2)
			var cu := int(floor(gu))
			var cv := int(floor(gv))
			if fmod(gu, 1.0) < 0.07 or fmod(gv, 1.0) < 0.07:
				return Color(0.42, 0.36, 0.28)
			var k := 0.84 + 0.26 * _hash(cu, cv, variant)
			return Color(0.84, 0.76, 0.6) * k + Color(nz, nz, nz) * 0.05
		"mosaic":
			var p := Vector2(u - 0.5, v - 0.5)
			var r := p.length()
			var a := atan2(p.y, p.x)
			var c := Color(0.9, 0.86, 0.76)
			if r < 0.36:
				c = Color(0.16, 0.36, 0.6) if fmod(a / TAU * 8.0 + 1.0, 1.0) < 0.5 else Color(0.72, 0.2, 0.13)
				if r < 0.1:
					c = Color(0.95, 0.78, 0.3)
				if absf(r - 0.36) < 0.025:
					c = Color(0.12, 0.08, 0.07)
			elif u < 0.08 or v < 0.08 or u > 0.92 or v > 0.92:
				c = Color(0.72, 0.2, 0.13)
			# Tesserae: small squares.
			if fmod(u * 32.0, 1.0) < 0.12 or fmod(v * 32.0, 1.0) < 0.12:
				c = c.darkened(0.18)
			return c.lightened(nz * 0.05)
		"alien":
			# Hexagonal plating with glowing seams.
			var q := Vector2(u * 6.0, v * 6.0 + fmod(floor(u * 6.0), 2.0) * 0.5)
			var f := Vector2(fmod(q.x, 1.0), fmod(q.y, 1.0))
			var edge := minf(minf(f.x, 1.0 - f.x), minf(f.y, 1.0 - f.y))
			var c := base.darkened(0.35).lightened(nz * 0.06)
			if edge < 0.06:
				c = light.darkened(0.45)
			elif _hash(int(q.x), int(q.y), variant) > 0.88:
				c = c.lightened(0.12)
			return c
		"roof_minoan":
			var c := Color(0.8, 0.66, 0.48).lightened(nz * 0.08)
			if fmod(u * 4.0, 1.0) < 0.05:
				c = c.darkened(0.12)
			return c
		"roof_alien":
			var c := base.darkened(0.15).lightened(nz * 0.06)
			if fmod(u * 3.0, 1.0) < 0.04 or fmod(v * 3.0, 1.0) < 0.04:
				c = base.darkened(0.45)
			if Vector2(u - 0.5, v - 0.5).length() < 0.07:
				c = light
			return c
	return base


# --- Column ------------------------------------------------------------------------

## Red Minoan column, 40 x (WALL_H + 16): tapers wider toward the top,
## cylinder-shaded, black cushion capital, stone base.
static func column() -> ImageTexture:
	return _cached("column", func():
		var w := 40
		var h := WALL_H + 16
		var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var dx := x + 0.5 - w / 2.0
				var c := Color(0, 0, 0, 0)
				if y < 14:  # capital: dark cushion with a light abacus slab on top
					var cap_w := 18.0 - absf(y - 9.0) * 0.6
					if absf(dx) < cap_w:
						c = Color(0.86, 0.8, 0.66) if y < 4 else Color(0.1, 0.07, 0.06)
				elif y > h - 8:  # base
					if absf(dx) < 14.0:
						c = Color(0.78, 0.72, 0.6)
				else:
					var f := float(y - 14) / (h - 22)
					var hw := lerpf(12.5, 8.0, f)   # wider at the top
					if absf(dx) < hw:
						c = Color(0.72, 0.19, 0.12)
				if c.a > 0.0:
					var s := 0.65 + 0.5 * clampf(1.0 - (dx + 6.0) / 16.0, 0.0, 1.0)  # light from the left
					img.set_pixel(x, y, Color(minf(c.r * s, 1.0), minf(c.g * s, 1.0), minf(c.b * s, 1.0)))
		return img)
