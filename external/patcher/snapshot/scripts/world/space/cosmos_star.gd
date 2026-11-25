class_name CosmosStar
extends Node3D
## The system's star in the 3D game (Cosmos): a boiling sphere (its StarGen
## colours - the 2D game's sun) and a glow around it seen from anywhere in the
## system.

const SIZE_TO_R := 9.0         # a 2D star's radius (px) -> its radius (m)
const SHADER := preload("res://shaders/world/star.gdshader")
const GLOW := preload("res://shaders/world/glow.gdshader")

var radius := 8000.0
var color := Color(1.0, 0.9, 0.6)


func setup(system_id: String, noise: Texture3D) -> void:
	name = "Star"
	var t: Dictionary = Galaxy.STARS.get(str(Galaxy.system(system_id).get("star", "yellow")), Galaxy.STARS["yellow"])
	radius = float(t["radius"]) * SIZE_TO_R
	color = t["color"]
	var spec := {}
	if Galaxy.SYSTEMS.has(system_id):
		spec = Galaxy.star_spec(system_id)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("c_dark", spec.get("c_dark", color.darkened(0.6)))
	m.set_shader_parameter("c_mid", spec.get("c_mid", color))
	m.set_shader_parameter("c_hot", spec.get("c_hot", color.lightened(0.6)))
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 96
	s.rings = 48
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = s
	body.material_override = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	for g in [[radius * 5.0, 0.9, 0.2], [radius * 16.0, 0.12, 0.0]]:
		var gm := ShaderMaterial.new()
		gm.shader = GLOW
		gm.set_shader_parameter("tint", spec.get("c_corona", color))
		gm.set_shader_parameter("intensity", g[1])
		gm.set_shader_parameter("core", g[2])
		var q := QuadMesh.new()
		q.size = Vector2(g[0], g[0])
		var glow := MeshInstance3D.new()
		glow.mesh = q
		glow.material_override = gm
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.extra_cull_margin = g[0]
		add_child(glow)
