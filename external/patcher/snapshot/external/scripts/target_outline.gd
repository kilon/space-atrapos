class_name TargetOutline
extends Sprite2D
## The red lock-on outline for a sprite: a copy of it, drawn behind it with
## the target_outline shader (glowing shape outline, halo, pulse, running
## dashes). Add as a child of the sprite; it copies the sprite's texture and
## placement every frame and is shown while `on`.

const SHADER := preload("res://shaders/target_outline.gdshader")

var on := false:
	set(v):
		on = v
		visible = v


func _init(col := Color(1.0, 0.12, 0.08)) -> void:
	show_behind_parent = true
	visible = false
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color", col)
	material = mat


func set_color(col: Color) -> void:
	(material as ShaderMaterial).set_shader_parameter("color", col)


func _process(_delta: float) -> void:
	if not visible:
		return
	var src := get_parent() as Sprite2D
	if src == null:
		return
	texture = src.texture
	centered = src.centered
	offset = src.offset
	flip_h = src.flip_h
	flip_v = src.flip_v
	# Keep the outline a similar on-screen width whatever the sprite scale.
	var s := maxf(absf(src.global_scale.x), 0.01)
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("width", clampf(3.5 / s, 2.0, 16.0))
	mat.set_shader_parameter("pad", clampf(18.0 / s, 8.0, 60.0))
