extends Node2D
## The planet surface is the top of a cube: its two visible front faces are
## drawn below the map's front edges as walls of orange bricks
## (shaders/brick_edge.gdshader: courses, joints, per-brick shade, a stone
## coping, darkening toward the bottom) - two polygons, two draw calls.

## Map corners along the front: [left, bottom, right] (world space).
var corners: Array = []
const DEPTH := 230.0


func _ready() -> void:
	if corners.size() < 3:
		return
	_face(corners[0], corners[1], 1.0)    # front-left face (lit)
	_face(corners[1], corners[2], 0.72)   # front-right face (shaded)


func _face(a: Vector2, b: Vector2, light: float) -> void:
	var down := Vector2(0, DEPTH)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([a, b, b + down, a + down])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/brick_edge.gdshader")
	mat.set_shader_parameter("a", a)
	mat.set_shader_parameter("b", b)
	mat.set_shader_parameter("light", light)
	mat.set_shader_parameter("depth", DEPTH)
	poly.material = mat
	add_child(poly)
