class_name GasSky
extends Node2D
## A gas giant's cloud deck under the platforms (PlanetSurface._build_background,
## in the background CanvasLayer: screen space). Six painted bands
## (data/sprites/sky_gg_band1..6, cut seamless by tools/gas_sky.py) stacked
## top to bottom to fill the window, each scrolling sideways at its own speed
## - alternating directions, like Jupiter's zonal winds - and sliding a little
## with the camera (parallax: far below, so slowly). Storms and eddies
## (sky_gg_storm_*, eddy_*, festoon_* ...) drift along their bands, turning
## slowly, and come round again off the other side.

const BANDS := 6
## Each band's wind: px/s on screen (alternating, the dark belts faster).
const WINDS := [6.0, -14.0, 9.0, -18.0, 7.0, -5.0]
const PARALLAX := Vector2(0.045, 0.006)  # of the camera's movement from `origin` (the deck is far below)
const PARALLAX_Y_MAX := 0.09             # of the window's height: the stack always covers the window
const OVERLAP := 0.12                    # of a band's height, over the band above (its top is the boundary)
const STORMS := [
	# [sprite, band index (0 top), x (of the wrap width, 0..1), scale, turn (deg/s), own drift (px/s)]
	["storm_red", 3, 0.15, 0.55, 0.6, 2.0], ["storm_white", 2, 0.55, 0.4, -0.5, -1.5], ["storm_salmon", 4, 0.8, 0.45, 0.4, 1.0],
	["storm_brown", 1, 0.4, 0.4, -0.7, 2.5], ["eddy_cream", 3, 0.7, 0.45, 1.2, -2.0], ["eddy_rust", 1, 0.05, 0.5, -1.4, 1.5],
	["oval_white", 2, 0.25, 0.5, 0.3, 1.0], ["hotspot", 0, 0.6, 0.5, 0.0, -1.0], ["festoon_cream", 3, 0.95, 0.55, 0.0, 0.5],
	["festoon_brown", 1, 0.75, 0.5, 0.0, -0.8], ["ovals_three", 2, 0.9, 0.5, 0.2, 2.0], ["filament", 4, 0.35, 0.6, 0.0, -1.2],
	["eddy_cream", 5, 0.5, 0.4, 0.9, 1.5], ["oval_white", 0, 0.2, 0.35, -0.2, 0.8],
]

## Where the camera's movement is measured from (the landing pad): the stack
## is centred on the window there.
var origin := Vector2.ZERO
var _bands: Array[Texture2D] = []
var _storms: Array = []      # [texture, band, x, scale, turn, drift, angle]
var _t := 0.0
var _scroll := PackedFloat32Array()


static func available() -> bool:
	return ProcArt.has_sprite("sky_gg_band1")


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for i in BANDS:
		_bands.append(ProcArt.sprite("sky_gg_band%d" % (i + 1)))
	_scroll.resize(BANDS)
	for s in STORMS:
		var tex: Texture2D = ProcArt.sprite("sky_gg_" + str(s[0]))
		if tex:
			_storms.append([tex, int(s[1]), float(s[2]), float(s[3]), float(s[4]), float(s[5]), randf() * 0.3])


func _process(delta: float) -> void:
	_t += delta
	for i in BANDS:
		_scroll[i] += WINDS[i] * delta
	queue_redraw()


## Where a band sits on screen: [y, height], the stack filling the window
## with a margin for the parallax (bands overlap the one above a little:
## their top is painted as the boundary with it).
func _band_rect(i: int, size: Vector2, cam_off: Vector2) -> Rect2:
	var h := size.y * (1.0 + 2.0 * PARALLAX_Y_MAX + 0.02) / (BANDS - OVERLAP * (BANDS - 1))
	var y := -size.y * (PARALLAX_Y_MAX + 0.01) + i * h * (1.0 - OVERLAP) - cam_off.y
	return Rect2(0, y, size.x, h)


func _draw() -> void:
	if _bands.is_empty() or _bands[0] == null:
		return
	var cam := get_viewport().get_camera_2d()
	var cam_pos: Vector2 = cam.get_screen_center_position() if cam else Vector2.ZERO
	var size := get_viewport_rect().size
	var rel := cam_pos - origin
	var cam_off := Vector2(rel.x * PARALLAX.x, clampf(rel.y * PARALLAX.y, -size.y * PARALLAX_Y_MAX, size.y * PARALLAX_Y_MAX))
	for i in BANDS:
		var tex := _bands[i]
		if tex == null:
			continue
		var r := _band_rect(i, size, cam_off)
		var k := r.size.y / tex.get_height()          # (the band scaled to its height; its width scales with it)
		var w := tex.get_width() * k
		var off := fposmod(_scroll[i] - cam_off.x * (1.0 + 0.15 * i), w)
		# One tiled rect from the first tile left of the screen, drawn in the
		# texture's own pixels (the tiling repeats the texture, not the rect).
		draw_set_transform(Vector2(-off - w, r.position.y), 0.0, Vector2(k, k))
		draw_texture_rect(tex, Rect2(0, 0, (size.x + 2.0 * w) / k, tex.get_height()), true)
		draw_set_transform(Vector2.ZERO)
	# The storms, each on its band, drifting with it (and a little on its own).
	for s in _storms:
		var tex: Texture2D = s[0]
		var i: int = s[1]
		var r := _band_rect(i, size, cam_off)
		var k := r.size.y / _bands[i].get_height() if _bands[i] else 1.0
		var w: float = (_bands[i].get_width() if _bands[i] else 1354) * k
		var x := fposmod(s[2] * w + _scroll[i] - cam_off.x * (1.0 + 0.15 * i) + s[5] * _t, w + size.x) - w * 0.5
		var y := r.position.y + r.size.y * 0.55 + sin(_t * 0.07 + s[2] * 6.0) * r.size.y * 0.04
		var sc: float = s[3] * k * 1.6
		var ang: float = deg_to_rad(float(s[4]) * _t) + float(s[6])
		draw_set_transform(Vector2(x, y), ang, Vector2(sc, sc))
		draw_texture(tex, -tex.get_size() * 0.5)
		draw_set_transform(Vector2.ZERO)
