class_name RepairArt
extends RefCounted
## Drawings for the Repair Bay (RepairBay) and the spare parts' icons: each
## component kind (Parts.COMP_FAULTS) as a machined part, the bolts, sockets,
## clamps, gauges, the tools in your hand, the table and the casing.
## They're rendered in Blender (external/blender/repair_parts/build.py: lit,
## shaded, with their shadows) and packed into one atlas (pack.py ->
## art/repair/atlas.png + atlas.json; the table and the casing on their own),
## so a whole table draws from one texture. Loaded in the background at game
## start (warm()).
##   RepairArt.component(ci, "servo", centre, half_size)

const ATLAS := "res://art/repair/atlas.png"
const TABLE := "res://art/repair/table.png"
const LID := "res://art/repair/lid.png"
const REGIONS := "res://art/repair/atlas.json"
## A component's picture spans this x its half size (room round it for its shadow: build.py R).
const COMP_SPAN := 2.6
## Where a tool's tip is in its picture (a fraction of its size from the top left: build.py).
const TOOL_TIP := 1.0 / 6.0

static var _tex := {}       # path -> Texture2D
static var _asked := {}     # path -> true (a background load requested)
static var _regions := {}


## Start loading the pictures on a worker thread (the first Repair Bay then opens without a hitch).
static func warm() -> void:
	for p in [ATLAS, TABLE, LID]:
		if not _asked.has(p) and not _tex.has(p):
			_asked[p] = true
			ResourceLoader.load_threaded_request(p)


static func texture(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if _asked.has(path):
		t = ResourceLoader.load_threaded_get(path)   # (waits if it's still on its way)
		_asked.erase(path)
	if t == null:
		t = load(path)
	_tex[path] = t
	return t


static func region(name: String) -> Rect2:
	if _regions.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(REGIONS))
		if d is Dictionary:
			for k in d:
				_regions[k] = Rect2(d[k][0], d[k][1], d[k][2], d[k][3])
	return _regions.get(name, Rect2())


## A piece of the atlas, centred on `c`, `w` wide (its height in proportion), turned `rot`.
static func piece(ci: CanvasItem, name: String, c: Vector2, w: float, tint := Color.WHITE, rot := 0.0) -> void:
	var r := region(name)
	if r.size.x <= 0.0:
		return
	var h := w * r.size.y / r.size.x
	ci.draw_set_transform(c, rot, Vector2.ONE)
	ci.draw_texture_rect_region(texture(ATLAS), Rect2(-w * 0.5, -h * 0.5, w, h), r, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func component(ci: CanvasItem, kind: String, c: Vector2, s: float, tint := Color.WHITE, wrecked := false, rot := 0.0) -> void:
	# (A wrecked one has its own picture: burnt out, pieces off it, embers in its cracks.)
	piece(ci, kind + "_wreck" if wrecked else kind, c, s * COMP_SPAN, tint, rot)


## A soft round glow (white at the middle, clear at the rim) - tinted where it's drawn.
static var _glow: GradientTexture2D

static func glow_tex() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		g.add_point(0.7, Color(1, 1, 1, 0.1))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64
	return _glow


static func glow(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(glow_tex(), Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## The circuit board's two status LEDs, in its half sizes from its centre (build.py: circuit).
const LEDS := [Vector2(0.62, -0.36), Vector2(0.76, -0.36)]

## A working, powered component's signs of life over its picture, at time `t`
## (`k`: which one - they don't all pulse together): the board's LEDs, the
## cell's charge glowing, the lens's sensor and a glint crossing its glass,
## the flow down the conduit.
static func live(ci: CanvasItem, kind: String, c: Vector2, s: float, t: float, k := 0) -> void:
	var ph := t + k * 1.7
	match kind:
		"circuit":
			var on := 0.6 + 0.4 * sin(ph * 2.2)
			glow(ci, c + LEDS[0] * s, s * 0.16, Color(0.3, 1.0, 0.45, 0.9 * on))
			ci.draw_circle(c + LEDS[0] * s, s * 0.025, Color(0.8, 1.0, 0.85, on))
			if fmod(ph * 1.3, 1.0) < 0.35:   # (the amber one: busy)
				glow(ci, c + LEDS[1] * s, s * 0.16, Color(1.0, 0.7, 0.2, 0.9))
				ci.draw_circle(c + LEDS[1] * s, s * 0.025, Color(1.0, 0.95, 0.75))
		"cell":
			var charge := 0.5 + 0.5 * sin(ph * 1.4)
			glow(ci, c, s * 1.15, Color(1.0, 0.72, 0.2, 0.16 + 0.12 * charge))
			# (the charge running up its window)
			var y := s * 0.6 - fmod(ph * 0.5, 1.0) * s * 1.2
			ci.draw_texture_rect(glow_tex(), Rect2(c + Vector2(-s * 0.38, y - s * 0.12), Vector2(s * 0.76, s * 0.24)), false, Color(1.0, 0.95, 0.7, 0.5))
		"lens":
			glow(ci, c, s * 0.62, Color(0.25, 0.6, 1.0, 0.3 + 0.14 * sin(ph * 1.8)))
			var a := ph * 0.5
			ci.draw_arc(c, s * 0.5, a, a + 0.5, 8, Color(0.8, 0.95, 1.0, 0.3), maxf(1.5, s * 0.035), true)
			ci.draw_arc(c, s * 0.38, a + PI, a + PI + 0.35, 6, Color(0.8, 0.95, 1.0, 0.18), maxf(1.0, s * 0.025), true)
		"conduit":
			for i in 3:
				var u := fmod(ph * 0.45 + i / 3.0, 1.0)
				var x := -s * 0.55 + u * s * 1.1
				if absf(x) > s * 0.3:   # (not across the valve)
					glow(ci, c + Vector2(x, -s * 0.05), s * 0.16, Color(0.5, 0.85, 1.0, 0.55 * sin(u * PI)))
		"servo":
			glow(ci, c, s * 0.34, Color(1.0, 0.8, 0.4, 0.1 + 0.08 * sin(ph * 3.0)))


## A bolt head (`out`: the empty hole), turned `turn` radians; `hot`: glowing.
static func bolt(ci: CanvasItem, c: Vector2, r: float, out: bool, turn := 0.0, hot := false) -> void:
	if out:
		piece(ci, "bolt_hole", c, r * 2.8)
		return
	piece(ci, "bolt", c, r * 2.8, Color(1.6, 1.1, 0.6) if hot else Color.WHITE, turn)


## The well a component sits in (s: the component's half size).
static func socket(ci: CanvasItem, c: Vector2, s: float) -> void:
	piece(ci, "socket", c, s * 2.5, Color(0.55, 0.57, 0.62))


## A wrecked component's socket, the part lifted out (its plate 2.1 x s across).
static func empty_socket(ci: CanvasItem, c: Vector2, s: float) -> void:
	piece(ci, "empty_socket", c, s * 2.1 * 2.4 / 2.2)


## A toggle clamp (about 36 x 58), shut or flipped open.
static func clamp_(ci: CanvasItem, c: Vector2, shut: bool, tint := Color.WHITE) -> void:
	piece(ci, "clamp_shut" if shut else "clamp_open", c, 36.0, tint)


## A gauge's bezel and face (r: the face's radius); the marks and the needle are drawn over it.
static func gauge(ci: CanvasItem, c: Vector2, r: float) -> void:
	piece(ci, "gauge", c, r * 2.2 / 0.86)


## A knurled dial knob (r: its radius).
static func knob(ci: CanvasItem, c: Vector2, r: float) -> void:
	piece(ci, "knob", c, r * 2.2)


## A tool in the hand, its tip at `tip`, `w` px across.
static func tool(ci: CanvasItem, name: String, tip: Vector2, w := 84.0, tint := Color.WHITE) -> void:
	var r := region(name)
	if r.size.x <= 0.0:
		return
	ci.draw_texture_rect_region(texture(ATLAS), Rect2(tip - Vector2(w, w) * TOOL_TIP, Vector2(w, w)), r, tint)


## The table top filling `rect`.
static func table(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_texture_rect(texture(TABLE), rect, false, Color(0.5, 0.52, 0.56))


## The casing's lid over `rect` (its picture has a margin for the shadow: build.py 3.6 / 3.333).
static func lid(ci: CanvasItem, rect: Rect2, tint := Color.WHITE) -> void:
	var k := 3.6 / 3.333
	var big := Rect2(rect.get_center() - rect.size * k * 0.5, rect.size * k)
	ci.draw_texture_rect(texture(LID), big, false, Color(0.58, 0.6, 0.64) * tint)
