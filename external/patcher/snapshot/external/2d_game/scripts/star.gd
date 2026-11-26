class_name Star
extends Node2D
## The system's sun at the centre: a procedural star (StarGen) with a huge
## light halo. Purely visual (ships can fly over it).

var color := Color(1.0, 0.86, 0.5)
var radius := 420.0
var star_name := ""
var spec := {}               # StarGen parameters (default: the yellow sun)


func setup(c: Color, r: float, label: String, spec_ := {}) -> Star:
	color = c
	radius = r
	star_name = label
	spec = spec_
	return self


func _ready() -> void:
	z_index = -16
	add_to_group("star")
	# Faint light halo far around the star.
	var halo := Sprite2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(color, 0.35), Color(color, 0.08), Color(color, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	halo.texture = gt
	halo.scale = Vector2.ONE * radius * 9.0 / 256.0
	add_child(halo)
	if spec.is_empty():
		spec = StarGen.generate("yellow_sun", 0)
	add_child(StarGen.make(spec, radius))
