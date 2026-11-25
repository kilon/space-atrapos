class_name PlanetFog
extends RefCounted
## Fog of war on a planet (the planet map's - PlanetMapPage): a coarse grid
## of how well each patch of its ground has been seen (0 never .. 255 seen),
## COLS x ROWS cells of longitude and latitude (planet-local directions, north
## +Y - the HUD's), revealed in soft-edged caps round you as you walk or fly
## low (CosmosMapMirror: Galaxy.reveal_planet), saved as base64 (deflated:
## Galaxy "planet_explored"). The globe draws texture() over its ground (dark
## where you haven't been) and hides what lies in the dark.

const COLS := 128
const ROWS := 64
## Seen at least this much: explored (its things show on the map).
const SEEN := 110

var data := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _dirty := true
var version := 0                    # (counts the changes: the map redraws when it moves on)


func _init() -> void:
	data.resize(COLS * ROWS)


## The cell of a planet-local direction.
static func cell_of(d: Vector3) -> Vector2i:
	var u := d.normalized()
	var lat := asin(clampf(u.y, -1.0, 1.0))
	var lon := atan2(u.x, u.z)
	return Vector2i(clampi(int((lon + PI) / TAU * COLS), 0, COLS - 1), clampi(int((PI * 0.5 - lat) / PI * ROWS), 0, ROWS - 1))


## A cell's middle as a direction.
static func dir_of(x: int, y: int) -> Vector3:
	var lon := (x + 0.5) / COLS * TAU - PI
	var lat := PI * 0.5 - (y + 0.5) / ROWS * PI
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))


## Reveals a cap round `d` (planet-local) `ang` radians wide; true if anything
## new was seen. Only the rows and columns it can touch are visited.
func reveal(d: Vector3, ang: float) -> bool:
	var u := d.normalized()
	var lat := asin(clampf(u.y, -1.0, 1.0))
	var ang_c := maxf(ang, PI / ROWS * 0.75)
	var soft := maxf(ang_c * 0.35, PI / ROWS)
	var y0 := clampi(int((PI * 0.5 - (lat + ang_c)) / PI * ROWS) - 1, 0, ROWS - 1)
	var y1 := clampi(int((PI * 0.5 - (lat - ang_c)) / PI * ROWS) + 1, 0, ROWS - 1)
	var lon := atan2(u.x, u.z)
	var cl := cos(lat)
	var full := cl < 0.05 or absf(lat) + ang_c > PI * 0.5 - 0.05
	var span := 0 if full else mini(COLS >> 1, int(ang_c / maxf(cl * cos(minf(absf(lat) + ang_c, 1.5)), 0.05) / TAU * COLS) + 2)
	var xc := int((lon + PI) / TAU * COLS)
	var xs := range(COLS) if full else range(xc - span, xc + span + 1)
	var changed := false
	for y in range(y0, y1 + 1):
		for xk in xs:
			var x := posmod(xk, COLS)
			var a := u.angle_to(dir_of(x, y))
			if a > ang_c:
				continue
			var v := int(clampf((ang_c - a) / soft, 0.0, 1.0) * 255.0)
			var i := y * COLS + x
			if v > data[i]:
				data[i] = v
				changed = true
	if changed:
		_dirty = true
		version += 1
	return changed


func seen_at(d: Vector3) -> int:
	var c := cell_of(d)
	return data[c.y * COLS + c.x]


func explored(d: Vector3) -> bool:
	return seen_at(d) >= SEEN


## Share of the world explored (0..1).
func explored_share() -> float:
	var n := 0
	for v in data:
		if v >= SEEN:
			n += 1
	return float(n) / data.size()


func reveal_all() -> void:
	data.fill(255)
	_dirty = true
	version += 1


## The fog as a texture (L8: 0 unseen .. 1 seen), its cells in longitude
## (x, from -180) and latitude (y, from the north).
func texture() -> ImageTexture:
	if _dirty or _texture == null:
		_image = Image.create_from_data(COLS, ROWS, false, Image.FORMAT_L8, data)
		if _texture == null:
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
	var raw := Marshalls.base64_to_raw(s).decompress(COLS * ROWS, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() == COLS * ROWS:
		data = raw
		_dirty = true
		version += 1
