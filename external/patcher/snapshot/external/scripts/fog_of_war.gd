class_name FogOfWar
extends RefCounted
## Fog of war for a map: a grid of how well each patch has been seen (0
## never .. 255 seen), revealed in soft-edged circles around you, saved as
## base64. The planet surfaces (PlanetSurface.fog: one cell per 4 tiles,
## grid coordinates) and the star systems (Galaxy.fog: one cell per CELL
## world units round the star) use it; the maps draw texture() over what
## they show - dark where you haven't been - and hide what lies in the dark.

## Seen at least this much: explored (its things show on the maps).
const SEEN := 110

var cols := 0
var rows := 0
var origin := Vector2.ZERO          # the grid's corner, in the map's own coordinates
var cell := 1.0                     # one cell's size, in the same units
var data := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _dirty := true
var _la := PackedByteArray()        # the texture's texels (luminance 0, alpha: the fog)
var _la_shade := -1.0
## How dark the unexplored parts are drawn (alpha).
var shade := 0.93
## The texture is this many texels per cell, smoothed (soft edges even where
## the map draws without filtering).
var smooth := 4


func _init(cols_: int, rows_: int, origin_ := Vector2.ZERO, cell_ := 1.0) -> void:
	cols = cols_
	rows = rows_
	origin = origin_
	cell = cell_
	data.resize(cols * rows)


## Reveals a circle (radius r, map units) round p; true if anything new was seen.
func reveal(p: Vector2, r: float) -> bool:
	var g := (p - origin) / cell
	var rc := r / cell
	var soft := maxf(rc * 0.3, 1.0)
	var changed := false
	for y in range(maxi(0, floori(g.y - rc)), mini(rows, ceili(g.y + rc) + 1)):
		for x in range(maxi(0, floori(g.x - rc)), mini(cols, ceili(g.x + rc) + 1)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(g)
			if d > rc:
				continue
			var v := int(clampf((rc - d) / soft, 0.0, 1.0) * 255.0)
			var i := y * cols + x
			if v > data[i]:
				data[i] = v
				changed = true
				if _la.size() == data.size() * 2:
					_la[i * 2 + 1] = int((255 - v) * shade)
	if changed:
		_dirty = true
	return changed


## Everything seen (a system charted by its navigation beacon).
func reveal_all() -> void:
	data.fill(255)
	_la = PackedByteArray()   # (rebuilt from it)
	_dirty = true


## How well the patch at p has been seen (0..255; outside the grid: 0).
func seen_at(p: Vector2) -> int:
	var g := (p - origin) / cell
	var x := floori(g.x)
	var y := floori(g.y)
	if x < 0 or y < 0 or x >= cols or y >= rows:
		return 0
	return data[y * cols + x]


func explored(p: Vector2) -> bool:
	return seen_at(p) >= SEEN


## Share of the map explored (0..1).
func explored_share() -> float:
	var n := 0
	for v in data:
		if v >= SEEN:
			n += 1
	return float(n) / maxf(data.size(), 1)


## The fog to draw over the map (covering cols x rows cells): black,
## transparent where seen, smoothed.
func texture() -> ImageTexture:
	if _dirty or _texture == null:
		# (The texels kept up to date as cells are revealed - rebuilding them
		# all in a loop each time cost a frame 2-3 ms as you walk.)
		if _la.size() != data.size() * 2 or _la_shade != shade:
			_la_shade = shade
			_la.resize(data.size() * 2)
			for i in data.size():
				_la[i * 2] = 0
				_la[i * 2 + 1] = int((255 - data[i]) * shade)
		_image = Image.create_from_data(cols, rows, false, Image.FORMAT_LA8, _la)
		if smooth > 1:
			_image.resize(cols * smooth, rows * smooth, Image.INTERPOLATE_BILINEAR)
		if _texture == null or _texture.get_size() != Vector2(_image.get_size()):
			_texture = ImageTexture.create_from_image(_image)
		else:
			_texture.update(_image)
		_dirty = false
	return _texture


func save() -> String:
	return Marshalls.raw_to_base64(data.compress(FileAccess.COMPRESSION_DEFLATE))


func load_from(s: String) -> void:
	if s == "":
		return
	var raw := Marshalls.base64_to_raw(s).decompress(cols * rows, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() == cols * rows:
		data = raw
		_la = PackedByteArray()   # (rebuilt from it)
		_dirty = true
