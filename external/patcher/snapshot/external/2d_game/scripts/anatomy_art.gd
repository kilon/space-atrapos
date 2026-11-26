class_name AnatomyArt
extends RefCounted
## The automaton's anatomy, for its operating table (Surgery): four pictures
## of the whole body - its muscles, its vessels and heart, its nerves with the
## brain and the spinal cord, its skeleton - each modelled and rendered in
## Blender (external/blender/anatomy/build.py) from the front, the body lying
## with its head to the LEFT. They're big (4096 x 1848, 10 MB each compressed
## on the card), so they load in the background, one at a time (pump()), and
## tex() gives null until one is in. They're asked for at the TITLE SCREEN
## (MainMenu): the second big picture to reach the card costs one long frame
## (~90 ms, once a run - the driver making room; measured: the first and all
## later ones ~1 ms) - there, not in play. The Repair Bay's Surgery pumps too
## (a game started without the title: tests, a scene run directly).
##
## The body's own coordinates (Parts' automaton components): metres, x across
## (+ its left side - the picture's top) and z up from the soles (the crown at
## 1.80 - the picture's left). px() turns them into a picture's pixels.

const DIR := "res://art/anatomy/"
const SIZE := Vector2(4096, 1848)
## Pixels a metre, and the picture's left edge (z) and top edge (x): build.py's PPM, Z_HI, X_HI.
const PPM := 2100.0
const Z_HI := 0.845 + 4096.0 / 2100.0 / 2.0
const X_HI := 1848.0 / 2100.0 / 2.0

## In a web build (phones among them) the pictures are half the size (art/anatomy/web/:
## 2048 px, 2.5 MB each on the card instead of 10 - the full ones aren't in that build).
## SIZE stays the body's frame: region() scales a rectangle in it to the picture's pixels.
static func path(layer: String) -> String:
	return DIR + ("web/" if OS.has_feature("web") else "") + layer + ".png"


## A rectangle in SIZE's pixels as the loaded picture's pixels (the same on the full ones).
static func region(r: Rect2) -> Rect2:
	var t: Texture2D = _tex.get("muscles")
	if t == null or t.get_width() == int(SIZE.x):
		return r
	var k := float(t.get_width()) / SIZE.x
	return Rect2(r.position * k, r.size * k)


static var _tex := {}       # layer -> Texture2D
static var _loading := ""   # the layer being loaded now
static var _wanted := false
static var _rest := 0       # frames to leave between two pictures


## Ask for the pictures (they come in over the next frames: pump()).
static func warm() -> void:
	_wanted = true


## Moves the loading on: call every frame while the pictures may be wanted
## (the Repair Bay's Surgery does). One picture at a time, a few frames apart.
static func pump() -> void:
	if not _wanted:
		return
	if _loading != "":
		if ResourceLoader.load_threaded_get_status(path(_loading)) == ResourceLoader.THREAD_LOAD_LOADED:
			_tex[_loading] = ResourceLoader.load_threaded_get(path(_loading))
			_pool(_loading)
			_loading = ""
			_rest = 6
		return
	if _rest > 0:
		_rest -= 1
		return
	for l in Parts.LAYERS:
		if not _tex.has(l) and ResourceLoader.exists(path(l)):
			_loading = l
			ResourceLoader.load_threaded_request(path(l))
			return
	_wanted = false   # (all in)


## What the four take on the card (bytes; compressed, a byte a pixel - half the size each way on the web).
static func expected_bytes() -> int:
	var k := 0.25 if OS.has_feature("web") else 1.0
	return int(SIZE.x * SIZE.y * k) * Parts.LAYERS.size()


## In the memory pool - pinned (one costs a long frame to load again: never unloaded).
static func _pool(l: String) -> void:
	var t: Texture2D = _tex.get(l)
	if t:
		AssetPool.add("anatomy_" + l, t.get_width() * t.get_height(), Callable(), Callable(), true, "Anatomy: " + l)


## A layer's picture - null while it's still on its way (never waits for it).
static func tex(layer: String) -> Texture2D:
	return _tex.get(layer)


## Every layer in (the table can be drawn whole)?
static func ready() -> bool:
	for l in Parts.LAYERS:
		if not _tex.has(l):
			return false
	return true


## All of them now (waits: tests, the doc shots).
static func load_now() -> void:
	for l in Parts.LAYERS:
		if not _tex.has(l) and ResourceLoader.exists(path(l)):
			_tex[l] = ResourceLoader.load_threaded_get(path(l)) if _loading == l else load(path(l))
			_pool(l)
	_loading = ""
	_wanted = false


## The body's (x, z) in metres -> a picture's pixel.
static func px(x: float, z: float) -> Vector2:
	return Vector2((Z_HI - z) * PPM, (X_HI - x) * PPM)


## The way a structure runs (degrees: 0 along the body, 90 across it) as a direction in the picture.
static func axis(deg: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(deg))
