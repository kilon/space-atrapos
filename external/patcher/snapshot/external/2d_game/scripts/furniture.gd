class_name Furniture
extends SurfaceProps.Thing
## Furniture inside the Minoan buildings: painted pieces (art/furniture/, cut
## by tools/furniture_sheet.py from external/images/minoan_furniture_sheet.png)
## standing against a room's back wall (the north-west or north-east one, so it
## never hides you), facing into the room. Pieces drawn in two facings (a
## throne, a bed...) use the one turned into the room: "<art>_a" faces down-left
## (against the "ne" wall), "<art>_b" down-right (against the "nw" wall).
##
## Decoration:  a palace's throne, chairs, benches, couches, beds, dining
##              tables, shelves, pithoi, rugs, cushions, plants and a loom; a
##              warehouse's workbenches, consoles, power cores, weapon racks...;
##              a temple's altars, statues, the double axe, lamps, incense
##              (see KINDS)
## Containers:  chest, locker, vault - click one: you walk up, open it and take
##              what's inside (once; PlanetSurface.open_container keeps track).
##              The vault is drawn in code (no painted vault).
##
## Geometry: a piece lives in one floor cell; its footprint is given in the
## cell's grid units (di, dj in -0.5..0.5 around the cell's centre; +i is
## down-right on screen, +j down-left). A piece against the "nw" wall has its
## back on di = -0.5 and faces +i; against "ne", its back on dj = -0.5, facing
## +j. The node sits at the footprint's centre (for y-sorting) - where the
## picture's anchor goes (art/furniture/anchors.json); `footprint` (world
## polygon) blocks walking - but for the flat pieces (rugs, shards: is_flat()).

const I := Vector2(64, 32)          # one cell along +i (world px)
const J := Vector2(-64, 32)         # one cell along +j
const CONTAINERS := ["chest", "locker", "vault"]
## The pictures are drawn at this scale: the chair as tall as a seated
## character's knee... (the characters are 122 px / 1.8 m; the chair 62 px).
const ART_K := 0.534
## Every kind: [name, the picture ("" = drawn in code), two facings?,
##   depth into the room / width along the wall (footprint), blocks walking?]
const KINDS := {
	"table": ["Dining table", "dining_table", true, 0.55, true],
	"chair": ["Chair", "chair", true, 1.0, true],
	"throne": ["Gryphon throne", "throne", true, 0.8, true],
	"bench": ["Stone bench", "bench", true, 0.5, true],
	"couch": ["Couch", "couch", true, 0.55, true],
	"bed": ["Bed", "bed", true, 0.8, true],
	"desk": ["Desk", "tech_desk", true, 0.6, true],
	"closet": ["Cabinet", "cabinet", true, 0.45, true],
	"bookshelf": ["Shelves", "cabinet", true, 0.45, true],
	"pithos": ["Storage jars", "pithoi", false, 1.0, true],
	"crates": ["Amphora rack", "amphora_rack", false, 0.6, true],
	"chest": ["Chest", "chest", false, 0.6, true],
	"locker": ["Locker", "locker", false, 0.6, true],
	"vault": ["Vault", "", false, 0.9, true],
	"round_table": ["Round table", "round_table", false, 1.0, true],
	"cauldron": ["Bronze cauldron", "cauldron", false, 1.0, true],
	"hearth": ["Hearth", "hearth", false, 1.0, true],
	"fruit": ["Basket of fruit", "fruit_basket", false, 1.0, true],
	"basin": ["Water basin", "water_basin", false, 1.0, true],
	"altar": ["Altar", "altar", false, 0.8, true],
	"goddess": ["Snake goddess", "goddess_statue", false, 1.0, true],
	"rhyton": ["Bull's-head rhyton", "bull_rhyton", false, 1.0, true],
	"labrys": ["The double axe", "labrys_stand", false, 1.0, true],
	"offering_table": ["Offering table", "offering_table", false, 0.8, true],
	"lamp": ["Oil lamp", "lamp_stand", false, 1.0, true],
	"incense": ["Incense burner", "incense_burner", false, 1.0, true],
	"lustral_basin": ["Lustral basin", "lustral_basin", false, 1.0, false],
	"console": ["Console", "console", false, 0.6, true],
	"holo_table": ["Holo-table", "holo_table", false, 1.0, true],
	"power_core": ["Power core", "power_core", false, 1.0, true],
	"med_pod": ["Medical pod", "med_pod", false, 0.7, true],
	"weapon_rack": ["Weapon rack", "weapon_rack", false, 0.5, true],
	"alcove": ["Charging alcove", "charging_alcove", false, 0.6, true],
	"workbench": ["Workbench", "workbench", false, 0.6, true],
	"rug": ["Rug", "rug_spiral", false, 1.0, false],
	"rug_dolphins": ["Rug", "rug_dolphins", false, 1.0, false],
	"cushions": ["Cushions", "cushions", false, 1.0, true],
	"lilies": ["Lilies", "lilies", false, 1.0, true],
	"olive": ["Olive tree", "olive_pot", false, 1.0, true],
	"tablets": ["Clay tablets", "tablets", false, 0.8, true],
	"loom": ["Loom", "loom", false, 0.5, true],
	"shards": ["Broken pottery", "shards", false, 1.0, false],
	# The other empires' pieces: drawn in code (placeholders - change their
	# shapes and colours in the _draw_* below; sizes in CODE_SIZE).
	"owl": ["Athena's owl", "", false, 1.0, true],
	"krater": ["Painted krater", "", false, 1.0, true],
	"shield_rack": ["Rack of lambda shields", "", false, 0.5, true],
	"lion_relief": ["Lion Gate relief", "", false, 0.5, true],
	"ionic_column": ["Ionic column", "", false, 1.0, true],
	"star_globe": ["Star globe", "", false, 1.0, true],
	"idol": ["Folded-arm figure", "", false, 1.0, true],
}
## The code-drawn pieces' size: [width along the wall, depth, height px].
const CODE_SIZE := {"owl": [0.34, 0.34, 58.0], "krater": [0.36, 0.36, 46.0], "shield_rack": [0.62, 0.22, 52.0],
	"lion_relief": [0.6, 0.16, 76.0], "ionic_column": [0.26, 0.26, 92.0], "star_globe": [0.36, 0.36, 60.0],
	"idol": [0.28, 0.28, 52.0]}
const MARBLE := Color(0.93, 0.92, 0.88)
const LAPIS := Color(0.16, 0.24, 0.62)
const GOLD := Color(0.95, 0.76, 0.3)
## The vault's size: [width along the wall, depth into the room, height px].
const VAULT := [0.48, 0.42, 60.0]
const BRONZE := Color(0.83, 0.62, 0.3)
const METAL := Color(0.5, 0.55, 0.6)
const STEEL := Color(0.33, 0.36, 0.42)

static var _anchors := {}

var kind := "chest"
var wall := "nw"                    # the wall it stands against: "nw" or "ne"
var style := "palace"               # the building's style (palace / warehouse / temple)
var cell := Vector2i.ZERO
var key := ""                       # for containers: "<i>,<j>" (opened ones stay opened)
var opened := false
var footprint := PackedVector2Array()   # world polygon (blocks walking)
var seed_ := 0
var _cell_c := Vector2.ZERO         # the cell's centre (world)
var _fp := [0.0, 0.0, 0.0, 0.0]     # di0, di1, dj0, dj1


var texture: Texture2D              # its picture (null: the vault, drawn)
var _depth := 0.3                   # into the room (cell units)
var _anchor := Vector2.ZERO         # the picture's point standing on the footprint's centre


## The picture of a kind against a wall (or null), and where it stands in it:
## the culture's own (art/furniture/<culture>/, tools/empire_furniture.py) on
## a world an empire holds (MinoanTiles.culture), if it has one; else the
## Minoan painted piece.
static func picture(kind_: String, wall_: String) -> Array:
	var k: Array = KINDS[kind_]
	if k[1] == "":
		return [null, Vector2.ZERO]
	var name: String = k[1] + (("_a" if wall_ == "ne" else "_b") if k[2] else "")
	var dir := "res://art/furniture/"
	var own := "res://art/furniture/%s/" % MinoanTiles.culture
	if MinoanTiles.culture != "" and ResourceLoader.exists(own + name + ".png"):
		dir = own
	if not _anchors.has(dir):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir + "anchors.json"))
		_anchors[dir] = parsed if parsed is Dictionary else {}
	var at: Array = _anchors[dir].get(name, [0.0, 0.0])
	return [load(dir + name + ".png"), Vector2(at[0], at[1])]


## Places it in `cell` (centre `c`, world) against `wall_`.
func setup(kind_: String, wall_: String, cell_: Vector2i, c: Vector2, style_ := "palace") -> Furniture:
	kind = kind_
	wall = wall_
	cell = cell_
	style = style_
	_cell_c = c
	key = "%d,%d" % [cell.x, cell.y]
	seed_ = hash(key + kind)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # (the pictures, shrunk)
	var pic := picture(kind, wall)
	texture = pic[0]
	_anchor = pic[1]
	var w: float
	var d: float
	if texture:
		# Its footprint from its picture: a footprint w x d cells spans (w + d) * 64 px across.
		var span := texture.get_width() * ART_K / 64.0
		var ratio: float = KINDS[kind][3]
		w = minf(span / (1.0 + ratio), 0.7)
		d = minf(span - w, 0.42)   # (never far into the room: the way past stays open)
		height = texture.get_height() * ART_K * 0.85
	else:
		var cs: Array = CODE_SIZE.get(kind, VAULT)
		w = cs[0]
		d = cs[1]
		height = cs[2]
	_depth = d
	var gap := 0.06
	if wall == "nw":
		_fp = [-0.5 + gap, -0.5 + gap + d, -w / 2.0, w / 2.0]
	else:
		_fp = [-w / 2.0, w / 2.0, -0.5 + gap, -0.5 + gap + d]
	var mid := Vector2((_fp[0] + _fp[1]) / 2.0, (_fp[2] + _fp[3]) / 2.0)
	position = c + I * mid.x + J * mid.y
	footprint = PackedVector2Array([_w(_fp[0], _fp[2]), _w(_fp[1], _fp[2]), _w(_fp[1], _fp[3]), _w(_fp[0], _fp[3])])
	click_radius = clampf(height * 0.45 + 18.0, 28.0, 48.0)
	_update_title()
	return self


## Flat on the floor (a rug, shards): you walk over it.
func is_flat() -> bool:
	return not KINDS[kind][4]


func is_container() -> bool:
	return kind in CONTAINERS


func display_name() -> String:
	if kind == "bookshelf" and style == "temple":
		return "Scroll rack"
	return KINDS[kind][0]


func _update_title() -> void:
	var n := display_name()
	if is_container():
		title = "%s  -  %s" % [n, "empty" if opened else "click to open"]
	else:
		title = n


## Where you stand to open it: in front of it.
func approach() -> Vector2:
	var front := (I if wall == "nw" else J).normalized()
	return position + front * (_depth * 70.0 + 46.0)


func click_center() -> Vector2:
	return global_position + Vector2(0, -height * 0.5)


func interact(surface: Node) -> void:
	if is_container() and surface.has_method("open_container"):
		surface.open_container(self)


func set_opened(v: bool) -> void:
	opened = v
	_update_title()
	queue_redraw()


# --- Drawing ---------------------------------------------------------------------------

## World point of grid offset (di, dj) in the cell, at height h.
func _w(di: float, dj: float, h := 0.0) -> Vector2:
	return _cell_c + I * di + J * dj - Vector2(0, h)


## Local (node) point.
func _p(di: float, dj: float, h := 0.0) -> Vector2:
	return _w(di, dj, h) - position


## An isometric box: the top and the two faces you see (+i, +j).
func _box(di0: float, di1: float, dj0: float, dj1: float, h0: float, h1: float, col: Color, outline := true) -> void:
	var top := PackedVector2Array([_p(di0, dj0, h1), _p(di1, dj0, h1), _p(di1, dj1, h1), _p(di0, dj1, h1)])
	var fi := PackedVector2Array([_p(di1, dj0, h0), _p(di1, dj1, h0), _p(di1, dj1, h1), _p(di1, dj0, h1)])   # +i face (down-right)
	var fj := PackedVector2Array([_p(di0, dj1, h0), _p(di1, dj1, h0), _p(di1, dj1, h1), _p(di0, dj1, h1)])   # +j face (down-left)
	if h1 - h0 > 0.5:
		draw_colored_polygon(fi, col.darkened(0.28))
		draw_colored_polygon(fj, col.darkened(0.08))
	draw_colored_polygon(top, col.lightened(0.14))
	if outline:
		var o := Color(0.06, 0.04, 0.03, 0.55)
		for poly in ([top, fi, fj] if h1 - h0 > 0.5 else [top]):
			draw_polyline(poly + PackedVector2Array([poly[0]]), o, 1.0, true)


## A point on the front face of the box (di0..dj1, h0..h1): s 0..1 left to
## right as you look at it, t 0..1 bottom to top, pushed `out` a little.
func _face(b: Array, s: float, t: float, out := 0.004) -> Vector2:
	var h: float = lerpf(b[4], b[5], t)
	if wall == "nw":   # front = the +i face; left to right on screen = dj high -> low
		return _p(b[1] + out, lerpf(b[3], b[2], s), h)
	return _p(lerpf(b[0], b[1], s), b[3] + out, h)   # front = the +j face; left to right = di low -> high


func _face_quad(b: Array, s0: float, s1: float, t0: float, t1: float, col: Color, out := 0.004) -> void:
	draw_colored_polygon(PackedVector2Array([_face(b, s0, t0, out), _face(b, s1, t0, out), _face(b, s1, t1, out), _face(b, s0, t1, out)]), col)


func _face_line(b: Array, s0: float, t0: float, s1: float, t1: float, col: Color, w := 1.2) -> void:
	draw_line(_face(b, s0, t0, 0.006), _face(b, s1, t1, 0.006), col, w, true)


## The main box covering the footprint, from h0 to h1.
func _main(h0: float, h1: float) -> Array:
	return [_fp[0], _fp[1], _fp[2], _fp[3], h0, h1]


func _draw() -> void:
	if texture == null:
		SurfaceProps.shadow(self, 26.0 * float(CODE_SIZE.get(kind, VAULT)[0]) / 0.5, 9.0, 0.22)
		match kind:
			"owl": _draw_owl()
			"krater": _draw_krater()
			"shield_rack": _draw_shield_rack()
			"lion_relief": _draw_lion_relief()
			"ionic_column": _draw_ionic_column()
			"star_globe": _draw_star_globe()
			"idol": _draw_idol()
			_: _draw_vault()
		return
	if not is_flat():
		SurfaceProps.shadow(self, texture.get_width() * ART_K * 0.36, texture.get_width() * ART_K * 0.13, 0.2)
	var sz := Vector2(texture.get_width(), texture.get_height()) * ART_K
	# An opened chest or locker: darker, its loot gone.
	var tint := Color(0.72, 0.68, 0.64) if opened else Color.WHITE
	draw_texture_rect(texture, Rect2(-_anchor * ART_K, sz), false, tint)


func _draw_vault() -> void:
	var b := _main(0.0, 58.0)
	_box(b[0], b[1], b[2], b[3], 0.0, 58.0, STEEL)
	# Rivets around the door.
	for s in [0.08, 0.92]:
		for t in [0.1, 0.5, 0.9]:
			draw_circle(_face(b, s, t, 0.01), 1.5, METAL.lightened(0.2))
	if opened:
		_face_quad(b, 0.14, 0.86, 0.1, 0.9, Color(0.05, 0.05, 0.06))
		# The door swung open beside it.
		var d := 0.18
		if wall == "nw":
			_box(b[1], b[1] + d, b[3], b[3] + 0.05, 2.0, 54.0, STEEL.lightened(0.05))
		else:
			_box(b[1], b[1] + 0.05, b[3], b[3] + d, 2.0, 54.0, STEEL.lightened(0.05))
		return
	_face_quad(b, 0.14, 0.86, 0.1, 0.9, STEEL.lightened(0.08))
	# The wheel: a ring with spokes, a gold hub.
	var c := _face(b, 0.5, 0.52, 0.012)
	var r := 11.0
	draw_arc(c, r, 0.0, TAU, 24, Color(0.75, 0.75, 0.78), 2.4, true)
	for k in 4:
		var a := k * PI / 2.0 + 0.4
		draw_line(c, c + Vector2.from_angle(a) * r, Color(0.7, 0.7, 0.74), 2.0, true)
	draw_circle(c, 3.0, BRONZE)


# --- The empires' pieces, drawn in code --------------------------------------------

## The footprint's centre at height h (screen).
func _mid(h: float) -> Vector2:
	return _p((_fp[0] + _fp[1]) / 2.0, (_fp[2] + _fp[3]) / 2.0, h)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		pts.append(c + Vector2(cos(TAU * k / 20.0) * rx, sin(TAU * k / 20.0) * ry))
	draw_colored_polygon(pts, col)


## Athens: Athena's owl, bronze on a marble plinth - big eyes, ear tufts.
func _draw_owl() -> void:
	var b := _main(0.0, 22.0)
	_box(b[0], b[1], b[2], b[3], 0.0, 22.0, MARBLE)
	_face_line(b, 0.1, 0.75, 0.9, 0.75, LAPIS, 2.0)   # (a blue band round the plinth)
	var bronze := Color(0.62, 0.5, 0.3)
	_ellipse(_mid(34.0), 9.0, 12.0, bronze)
	_ellipse(_mid(48.0), 8.0, 7.0, bronze.lightened(0.08))
	for s in [-1.0, 1.0]:
		var e := _mid(48.0) + Vector2(3.6 * s, 0)
		_ellipse(e, 3.0, 3.0, GOLD)
		draw_circle(e, 1.2, Color(0.05, 0.05, 0.05))
		var ear := _mid(54.0) + Vector2(5.0 * s, 0)
		draw_colored_polygon(PackedVector2Array([ear, ear + Vector2(2.5 * s, -5.0), ear + Vector2(-1.5 * s, -1.0)]), bronze.darkened(0.1))
	draw_colored_polygon(PackedVector2Array([_mid(46.0), _mid(46.0) + Vector2(-1.5, 2.5), _mid(46.0) + Vector2(1.5, 2.5)]), GOLD)   # (the beak)


## Athens: a red-figure krater - black clay, an orange band of figures.
func _draw_krater() -> void:
	var b := _main(0.0, 8.0)
	_box(b[0], b[1], b[2], b[3], 0.0, 8.0, MARBLE.darkened(0.1))
	var black := Color(0.08, 0.07, 0.07)
	var c0 := _mid(8.0)
	var prof := [[4.0, 0.0], [7.0, 6.0], [11.0, 18.0], [12.0, 30.0], [14.0, 38.0]]   # [half width, height] up the vase
	var pts := PackedVector2Array()
	for q in prof:
		pts.append(c0 + Vector2(q[0], -q[1]))
	for k in range(prof.size() - 1, -1, -1):
		pts.append(c0 + Vector2(-prof[k][0], -prof[k][1]))
	draw_colored_polygon(pts, black)
	draw_colored_polygon(PackedVector2Array([c0 + Vector2(-11.2, -20), c0 + Vector2(11.2, -20), c0 + Vector2(11.8, -28), c0 + Vector2(-11.8, -28)]), Color(0.86, 0.45, 0.18))
	for k in 4:   # (the figures: black shapes on the orange)
		var x := -8.0 + k * 5.4
		draw_line(c0 + Vector2(x, -21), c0 + Vector2(x + 1.0, -27), black, 1.6, true)
	_ellipse(c0 + Vector2(0, -38), 14.0, 3.0, black.lightened(0.1))


## Sparta: a wooden rack of round bronze shields, each with its red lambda.
func _draw_shield_rack() -> void:
	var b := _main(0.0, 50.0)
	_box(b[0], b[1], b[2], b[3], 0.0, 8.0, Color(0.42, 0.26, 0.14))
	for s in [0.05, 0.95]:
		_face_line(b, s, 0.12, s, 1.0, Color(0.36, 0.22, 0.12), 3.0)
	_face_line(b, 0.05, 0.98, 0.95, 0.98, Color(0.36, 0.22, 0.12), 3.0)
	for k in 3:
		var c := _face(b, 0.2 + k * 0.3, 0.55, 0.03)
		_ellipse(c, 10.0, 11.0, Color(0.76, 0.56, 0.24))
		_ellipse(c, 7.6, 8.4, Color(0.62, 0.4, 0.16))
		draw_line(c + Vector2(-4.5, 5), c + Vector2(0, -6), Color(0.75, 0.08, 0.06), 2.2, true)   # (Λ - Lakedaimon)
		draw_line(c + Vector2(4.5, 5), c + Vector2(0, -6), Color(0.75, 0.08, 0.06), 2.2, true)


## Mycenae: the Lion Gate - a grey slab, a relieving triangle, a column
## between two rearing lions.
func _draw_lion_relief() -> void:
	var b := _main(0.0, 76.0)
	var stone := Color(0.6, 0.58, 0.52)
	_box(b[0], b[1], b[2], b[3], 0.0, 76.0, stone)
	for t in [0.25, 0.5]:   # (the big Cyclopean courses)
		_face_line(b, 0.0, t, 1.0, t, stone.darkened(0.3), 1.0)
	var tri := PackedVector2Array([_face(b, 0.12, 0.55, 0.01), _face(b, 0.88, 0.55, 0.01), _face(b, 0.5, 0.97, 0.01)])
	draw_colored_polygon(tri, stone.lightened(0.12))
	_face_quad(b, 0.47, 0.53, 0.56, 0.86, Color(0.5, 0.42, 0.34), 0.012)   # the column
	for side in [-1.0, 1.0]:
		var s0: float = 0.5 + side * 0.08
		var s1: float = 0.5 + side * 0.3
		draw_colored_polygon(PackedVector2Array([_face(b, s1, 0.57, 0.012), _face(b, s0, 0.57, 0.012), _face(b, s0, 0.8, 0.012),
			_face(b, lerpf(s0, s1, 0.4), 0.9, 0.012), _face(b, s1, 0.72, 0.012)]), GOLD.darkened(0.25))


## Ionia: an Ionic column - lapis shaft, gold scroll capital.
func _draw_ionic_column() -> void:
	var b := _main(0.0, 8.0)
	_box(b[0], b[1], b[2], b[3], 0.0, 8.0, MARBLE)
	var m := [lerpf(b[0], b[1], 0.3), lerpf(b[0], b[1], 0.7), lerpf(b[2], b[3], 0.3), lerpf(b[2], b[3], 0.7)]
	_box(m[0], m[1], m[2], m[3], 8.0, 80.0, LAPIS)
	_box(b[0], b[1], b[2], b[3], 80.0, 86.0, GOLD)
	for side in [-1.0, 1.0]:   # (the volutes: a scroll each side)
		var c: Vector2 = _mid(80.0) + Vector2(side * 11.0, 0)
		draw_arc(c, 5.0, 0.0, TAU, 16, GOLD.lightened(0.2), 2.0, true)
		draw_arc(c, 2.4, 0.0, TAU, 12, GOLD.darkened(0.2), 1.6, true)


## Ionia: an armillary star globe on a tripod - the sky in rings.
func _draw_star_globe() -> void:
	var c := _mid(40.0)
	for k in 3:
		var a := TAU * k / 3.0
		draw_line(c + Vector2(0, 8), _mid(0.0) + Vector2(cos(a) * 10.0, sin(a) * 5.0), Color(0.45, 0.32, 0.18), 2.0, true)
	_ellipse(c, 13.0, 13.0, LAPIS.darkened(0.2))
	for k in 6:   # (stars)
		draw_circle(c + Vector2.from_angle(k * 1.7) * (4.0 + k), 1.0, Color(1, 0.95, 0.7))
	draw_arc(c, 15.0, 0.0, TAU, 28, GOLD, 1.8, true)
	draw_polyline(PackedVector2Array(range(21).map(func(k): return c + Vector2(cos(TAU * k / 20.0) * 15.0, sin(TAU * k / 20.0) * 5.0))), GOLD, 1.6, true)
	draw_line(c + Vector2(0, -17), c + Vector2(0, 17), GOLD.darkened(0.15), 1.4, true)


## The Cyclades: a white marble figure with folded arms and a lyre-shaped
## face, on a dark obsidian base.
func _draw_idol() -> void:
	var b := _main(0.0, 8.0)
	_box(b[0], b[1], b[2], b[3], 0.0, 8.0, Color(0.1, 0.1, 0.12))
	var white := Color(0.97, 0.97, 0.95)
	var c := _mid(8.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(3, 0), c + Vector2(4, -18), c + Vector2(6, -30),
		c + Vector2(3, -38), c + Vector2(-3, -38), c + Vector2(-6, -30), c + Vector2(-4, -18)]), white)
	draw_line(c + Vector2(-5.5, -27), c + Vector2(5.5, -25), white.darkened(0.25), 1.2, true)   # (the folded arms)
	draw_line(c + Vector2(-5.0, -24), c + Vector2(5.0, -22), white.darkened(0.25), 1.2, true)
	_ellipse(c + Vector2(0, -42), 3.4, 4.6, white)   # (the lyre-shaped head, tilted back)
	draw_line(c + Vector2(0, -43), c + Vector2(0, -40), white.darkened(0.3), 1.2, true)

