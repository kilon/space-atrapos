class_name CompassIcons
## The compass bar's icons (CosmosHud): one for each kind of thing it marks - in space the star, a
## world, a moon, a gas giant, a station, a jump gate, a trader, a pirate, a monster, a lair, your
## ship; on foot a village, a city, a cave, a dungeon, a pirate camp, ore, a vein, a creature, the
## package's destination. White line art (tinted when drawn: the theme's orange, hostile red, ore
## gold), each in a CELL-pixel square of one atlas - drawn once into a small viewport (make()), then
## each mark is one draw_texture_rect_region. The places' icons are the planet map's (a square,
## a roofed square, an arch, an X).

const CELL := 20
const KINDS := ["star", "planet", "moon", "gas", "station", "gate", "trader", "pirate", "monster", "lair",
	"ship", "village", "city", "cave", "dungeon", "camp", "ore", "vein", "creature", "package", "rock"]
const COLS := 7


## The atlas: a viewport drawn once (kept under `parent`); its texture.
static func make(parent: Node) -> Texture2D:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(CELL * COLS, CELL * ceili(KINDS.size() / float(COLS)))
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var c := Control.new()
	c.size = Vector2(vp.size)
	c.draw.connect(func():
		for i in KINDS.size():
			paint(c, KINDS[i], cell(i).get_center()))
	vp.add_child(c)
	parent.add_child(vp)
	return vp.get_texture()


## Where kind number i sits in the atlas.
static func cell(i: int) -> Rect2:
	return Rect2((i % COLS) * CELL, (i / COLS) * CELL, CELL, CELL)


static func index(kind: String) -> int:
	var i := KINDS.find(kind)
	return i if i >= 0 else KINDS.size() - 1


## One icon round `p` (about 8 px from its middle to its edge).
static func paint(ci: CanvasItem, kind: String, p: Vector2) -> void:
	var w := Color.WHITE
	var lw := 1.5
	match kind:
		"star":
			ci.draw_circle(p, 3.5, w)
			for k in 8:
				var d := Vector2.from_angle(k * TAU / 8.0)
				ci.draw_line(p + d * 5.0, p + d * (8.5 if k % 2 == 0 else 7.0), w, lw, true)
		"planet":
			ci.draw_arc(p, 7.0, 0, TAU, 20, w, lw, true)
			ci.draw_arc(p + Vector2(2.5, 0), 5.0, PI * 0.6, PI * 1.4, 10, w, 1.0, true)   # (its night side)
		"moon":
			ci.draw_arc(p, 7.0, 0, TAU, 20, Color(w, 0.45), 1.0, true)
			ci.draw_arc(p, 5.3, PI * 0.55, PI * 1.45, 12, w, 3.4, true)   # (its lit crescent)
		"gas":
			ci.draw_arc(p, 5.0, 0, TAU, 16, w, lw, true)
			var ring := PackedVector2Array()
			for k in 25:
				ring.append(p + (Vector2.from_angle(k * TAU / 24.0) * Vector2(9.0, 2.6)).rotated(-0.35))
			ci.draw_polyline(ring, w, lw, true)
		"station":
			var ring := PackedVector2Array()
			for k in 25:
				ring.append(p + Vector2.from_angle(k * TAU / 24.0) * Vector2(8.5, 3.0))
			ci.draw_polyline(ring, w, lw, true)
			ci.draw_line(p + Vector2(0, -8.5), p + Vector2(0, 8), w, 2.0, true)   # (its spire)
			ci.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), w)
		"gate":
			ci.draw_arc(p, 7.5, 0, TAU, 20, w, 2.5, true)
			ci.draw_arc(p, 3.5, 0, TAU, 12, Color(w, 0.6), 1.0, true)
		"trader":
			var hull := PackedVector2Array([p + Vector2(0, -8), p + Vector2(4, -4), p + Vector2(4, 7), p + Vector2(-4, 7), p + Vector2(-4, -4), p + Vector2(0, -8)])
			ci.draw_polyline(hull, w, lw, true)
			ci.draw_rect(Rect2(p + Vector2(-2, -1), Vector2(4, 5)), w)   # (its hold)
		"pirate":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(7, 7), p + Vector2(0, 3), p + Vector2(-7, 7)]), w)
		"monster":
			ci.draw_circle(p + Vector2(0, -3), 4.5, w)
			for k in 3:
				var x := -4.0 + k * 4.0
				ci.draw_polyline(PackedVector2Array([p + Vector2(x, 0), p + Vector2(x - 1.5, 3), p + Vector2(x + 1.5, 5.5), p + Vector2(x, 8.5)]), w, lw, true)
		"lair":
			ci.draw_circle(p + Vector2(0, 5), 2.0, w)
			ci.draw_arc(p + Vector2(0, 5), 6.0, PI * 1.2, PI * 1.8, 8, w, lw, true)
			ci.draw_arc(p + Vector2(0, 5), 10.5, PI * 1.25, PI * 1.75, 10, w, lw, true)
		"ship":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(6, 7), p + Vector2(-6, 7)]), w)
		"village":
			ci.draw_rect(Rect2(p - Vector2(5, 4), Vector2(10, 10)), w, false, lw)
		"city":
			ci.draw_rect(Rect2(p - Vector2(6, 3), Vector2(12, 10)), w, false, lw)
			ci.draw_line(p + Vector2(-7, -6), p + Vector2(7, -6), w, 2.0)
			ci.draw_rect(Rect2(p - Vector2(1.5, -1.5), Vector2(3, 3)), w)
		"cave":
			ci.draw_arc(p + Vector2(0, 4), 7.0, PI, TAU, 12, w, 2.0, true)
			ci.draw_line(p + Vector2(-8, 4), p + Vector2(8, 4), w, 2.0)
		"dungeon":
			ci.draw_arc(p + Vector2(0, 4), 7.0, PI, TAU, 12, w, 2.0, true)
			ci.draw_line(p + Vector2(-8, 4), p + Vector2(8, 4), w, 2.0)
			for k in 3:   # (its stairs down)
				ci.draw_line(p + Vector2(-3 + k, 1.5 - k * 2.5), p + Vector2(3 - k, 1.5 - k * 2.5), w, 1.0)
		"camp":
			ci.draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), w, 2.0, true)
			ci.draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), w, 2.0, true)
		"ore":
			var gem := PackedVector2Array([p + Vector2(0, -8), p + Vector2(5, -2), p + Vector2(0, 8), p + Vector2(-5, -2), p + Vector2(0, -8)])
			ci.draw_polyline(gem, w, lw, true)
			ci.draw_line(p + Vector2(-5, -2), p + Vector2(5, -2), w, 1.0)
		"vein":
			ci.draw_polyline(PackedVector2Array([p + Vector2(-8, 6), p + Vector2(-3, 2), p + Vector2(1, 5), p + Vector2(8, -1)]), w, 2.0, true)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(2, -8), p + Vector2(5, -4), p + Vector2(2, 0), p + Vector2(-1, -4)]), w)
		"creature":
			ci.draw_circle(p + Vector2(0, 3), 3.5, w)
			for x in [-5.5, -2.0, 2.0, 5.5]:
				ci.draw_circle(p + Vector2(x, -3.5 + absf(x) * 0.3), 1.7, w)
		"package":
			ci.draw_rect(Rect2(p - Vector2(6.5, 5.5), Vector2(13, 11)), w, false, lw)
			ci.draw_line(p + Vector2(0, -5.5), p + Vector2(0, 5.5), w, 1.0)
			ci.draw_line(p + Vector2(-6.5, 0), p + Vector2(6.5, 0), w, 1.0)
		_:   # (the rock you mine, anything else)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -3), p + Vector2(0, -6), p + Vector2(6, -2), p + Vector2(4, 5), p + Vector2(-4, 5)]), Color(w, 0.85))
