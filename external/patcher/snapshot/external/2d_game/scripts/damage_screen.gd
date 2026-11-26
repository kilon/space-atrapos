class_name DamageScreen
extends CanvasLayer
## What near-death looks like (space: the hull, on foot: the health): the
## whole window starts failing like a broken monitor - static, rolling tear
## lines, a flicker (shaders/damage_screen.gdshader) - and cracks run across
## the glass. It starts below START of health and is worst at the end, but
## never so much you can't see what's happening (the shader caps it). More
## cracks the lower it goes; they stay until you're mended above START.
##   var ds := DamageScreen.new(); ds.health = func(): return hull / max_hull; add_child(ds)

const START := 0.3
var health: Callable
var _rect: ColorRect
var _cracks: Cracks
var _k := 0.0

## The shader, kept for the run once loaded (Warmup loads it at the title: parsing
## it in the frame a new game's scene was made cost ~8 ms there).
static var _shader: Shader

static func shader() -> Shader:
	if _shader == null:
		_shader = load("res://shaders/damage_screen.gdshader")
	return _shader


func _ready() -> void:
	layer = 4   # (over the world and the HUD; under the menus)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("seed", randf() * 100.0)
	_rect.material = m
	_rect.visible = false
	add_child(_rect)
	_cracks = Cracks.new()
	_cracks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cracks)


## How bad it looks at `frac` of the health: 0 above START, 1 at 0.
static func level(frac: float) -> float:
	return clampf((START - frac) / START, 0.0, 1.0)


func _process(delta: float) -> void:
	if not health.is_valid():
		return
	var want := level(float(health.call()))
	_k = move_toward(_k, want, delta * 1.5)
	_rect.visible = _k > 0.01
	if _rect.visible:
		(_rect.material as ShaderMaterial).set_shader_parameter("k", _k * 0.85)
	_cracks.set_level(want)


## The glass's cracks: each from a point of impact, branching - drawn once
## when one more appears (not every frame).
class Cracks extends Control:
	var _lines: Array = []    # [PackedVector2Array, width]
	var _shown := 0
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		_rng.randomize()

	## Cracks for a level 0..1: none above 0, up to 5 at the end; they go when you're mended.
	func set_level(l: float) -> void:
		var want := 0 if l <= 0.0 else 1 + int(l * 4.0)
		if want == _shown:
			return
		if want < _shown and want == 0:
			_lines.clear()
		elif want > _shown:
			for i in want - _shown:
				_crack()
		_shown = want
		queue_redraw()

	func _crack() -> void:
		var sz := get_viewport_rect().size
		# (the impact toward an edge or a corner: the middle - where you fly - stays clear)
		var at := Vector2(_rng.randf_range(0.05, 0.95) * sz.x, _rng.randf_range(0.08, 0.92) * sz.y)
		var from_c := (at - sz * 0.5) / (sz * 0.5)
		if maxf(absf(from_c.x), absf(from_c.y)) < 0.55:
			at = sz * 0.5 + from_c.normalized() * sz * 0.5 * _rng.randf_range(0.6, 0.9) if from_c.length() > 0.01 else Vector2(sz.x * 0.12, sz.y * 0.2)
		for j in _rng.randi_range(4, 6):
			_branch(at, Vector2.from_angle(_rng.randf() * TAU), _rng.randf_range(0.06, 0.16) * sz.y, 1.8, 1)
		# a little star of shatter round the impact
		for j in 10:
			var d := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(8.0, 30.0)
			_lines.append([PackedVector2Array([at, at + d]), 1.2])

	func _branch(from: Vector2, dir: Vector2, length: float, width: float, depth: int) -> void:
		var pts := PackedVector2Array([from])
		var p := from
		var steps := int(length / 22.0) + 2
		for i in steps:
			dir = dir.rotated(_rng.randf_range(-0.35, 0.35))
			p += dir * length / steps
			pts.append(p)
			if depth > 0 and _rng.randf() < 0.12:
				_branch(p, dir.rotated(_rng.randf_range(-1.0, 1.0)), length * 0.4, width * 0.6, depth - 1)
		_lines.append([pts, width])

	## (All the cracks' segments gathered, thick and thin, and drawn as a few
	## multilines - one draw call a layer, not hundreds of polylines.)
	var _thick := PackedVector2Array()
	var _thin := PackedVector2Array()

	func _gather() -> void:
		_thick = PackedVector2Array()
		_thin = PackedVector2Array()
		for l in _lines:
			var pts: PackedVector2Array = l[0]
			var to: PackedVector2Array = _thick if float(l[1]) >= 1.5 else _thin
			for i in pts.size() - 1:
				to.append(pts[i])
				to.append(pts[i + 1])

	func _draw() -> void:
		_gather()
		if not _thick.is_empty():
			draw_multiline(_thick, Color(0, 0, 0, 0.55), 4.0)
			draw_multiline(_thick, Color(0.85, 0.92, 1.0, 0.55), 1.8)
			draw_multiline(_thick, Color(1, 1, 1, 0.35), 0.7)
		if not _thin.is_empty():
			draw_multiline(_thin, Color(0, 0, 0, 0.5), 3.0)
			draw_multiline(_thin, Color(0.85, 0.92, 1.0, 0.5), 1.1)
