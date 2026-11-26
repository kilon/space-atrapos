class_name ShieldEffect
extends Node2D
## Glowing energy shield (shaders/shield.gdshader) - a sphere round the whole
## sprite (sphere_for). flash() lights the
## whole shield; hit(from) also adds a bright flare where the shot struck.
## Rotate this node with the ship so the oval follows its heading.

const MAX_HITS := 4

var _rect: ColorRect
var _mat: ShaderMaterial
var _size := Vector2(150, 196)
var _glow := 0.0
var _hit_dirs := PackedVector2Array()
var _hit_power := PackedFloat32Array()
var _next := 0


func setup(size: Vector2, color: Color, hit_color: Color) -> ShieldEffect:
	_size = size
	_rect = ColorRect.new()
	_rect.size = size
	_rect.position = -size / 2.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/shield.gdshader")
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("hit_color", hit_color)
	_rect.material = _mat
	add_child(_rect)
	_hit_dirs.resize(MAX_HITS)
	_hit_power.resize(MAX_HITS)
	visible = false
	return self


## A sphere whose diameter covers a sprite of `sprite_size` (its diagonal -
## so even the corners are inside - plus a margin).
static func sphere_for(sprite_size: Vector2, margin := 24.0) -> Vector2:
	return Vector2.ONE * (sprite_size.length() + margin)


## A new size (the ship changed).
func resize(size: Vector2) -> void:
	_size = size
	_rect.size = size
	_rect.position = -size / 2.0


## Light up the whole shield (e.g. shield booster).
func flash() -> void:
	_glow = 1.0
	visible = true


## Light up the shield with a flare in the direction of `from` (global).
func hit(from: Vector2) -> void:
	flash()
	var local := to_local(from)
	if local.length() < 1.0:
		return
	# Normalised oval space, so the flare lands on the rim.
	_hit_dirs[_next] = Vector2(local.x / _size.x, local.y / _size.y).normalized()
	_hit_power[_next] = 1.0
	_next = (_next + 1) % MAX_HITS


func _process(delta: float) -> void:
	if not visible:
		return
	_glow = move_toward(_glow, 0.0, delta * 1.4)
	var any := _glow > 0.0
	for i in MAX_HITS:
		_hit_power[i] = move_toward(_hit_power[i], 0.0, delta * 1.8)
		any = any or _hit_power[i] > 0.0
	visible = any
	_mat.set_shader_parameter("glow", _glow)
	_mat.set_shader_parameter("hit_dirs", _hit_dirs)
	_mat.set_shader_parameter("hit_power", _hit_power)
