extends Node2D
## Endless parallax starfield, drawn in screen space (put it in a CanvasLayer
## behind the game). Each layer's stars are rendered once into a seamless
## tiling texture at startup, so drawing is just one tiled texture per layer
## per frame (instead of hundreds of individual circles).

const TILE := 1024
const CELL := 256.0  # star density is defined per 256x256 cell

## Each layer: [parallax factor, stars per cell, radius, brightness]
var layers := [
	[0.15, 6, 1.0, 0.45],
	[0.35, 3, 1.5, 0.7],
	[0.6, 1, 2.2, 1.0],
]

## Scroll speed used when there is no camera (e.g. in the main menu).
@export var drift := Vector2.ZERO

var _scroll := Vector2.ZERO
var _textures: Array[ImageTexture] = []


## Baked once a run (the same stars every time - a scene built again, after
## a jump or taking off, reuses them: ~10 ms of its first frame).
static var _baked := {}


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for i in layers.size():
		var key := var_to_str(layers[i]) + str(i)
		if not _baked.has(key):
			_baked[key] = _bake_layer(i)
		_textures.append(_baked[key])


func _bake_layer(index: int) -> ImageTexture:
	var count: int = layers[index][1] * int((TILE / CELL) * (TILE / CELL))
	var radius: float = layers[index][2]
	var brightness: float = layers[index][3]
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + index
	for s in count:
		var c := Vector2(rng.randf() * TILE, rng.randf() * TILE)
		var tint := Color(rng.randf_range(0.75, 1.0), rng.randf_range(0.8, 1.0), 1.0)
		var reach := int(ceil(radius + 1.0))
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var px := int(floor(c.x)) + dx
				var py := int(floor(c.y)) + dy
				var d := Vector2(px + 0.5, py + 0.5).distance_to(c)
				var a := clampf(radius + 0.5 - d, 0.0, 1.0) * brightness  # anti-aliased disc
				if a <= 0.0:
					continue
				# Wrap around the edges so the tile repeats seamlessly.
				var x := posmod(px, TILE)
				var y := posmod(py, TILE)
				var old := img.get_pixel(x, y)
				if a > old.a:
					img.set_pixel(x, y, Color(tint, a))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_scroll += drift * delta
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cam_pos := cam.get_screen_center_position() if cam else _scroll
	var size := get_viewport_rect().size
	var half := size / 2.0

	for i in layers.size():
		var factor: float = layers[i][0]
		var offset := half - cam_pos * factor
		# Top-left of the first visible tile, then one big tiled rect.
		var start := Vector2(fposmod(offset.x, TILE), fposmod(offset.y, TILE)) - Vector2(TILE, TILE)
		draw_texture_rect(_textures[i], Rect2(start, size + Vector2(TILE, TILE) * 2.0), true)
