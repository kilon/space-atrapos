class_name CosmosGate
extends Node3D
## A jump gate in the 3D game (Cosmos): a great ring facing the system's
## middle, its field swirling inside; fly through it to jump to `to`.

const RADIUS := 320.0
const SHADER := preload("res://shaders/cosmos/gate.gdshader")

var to := ""


func setup(dest: String, noise: Texture3D) -> void:
	to = dest
	name = "Gate_" + dest
	var accent: Color = Galaxy.empire_color(Galaxy.owner_of(dest))
	var t := TorusMesh.new()
	t.inner_radius = RADIUS
	t.outer_radius = RADIUS + 34.0
	t.rings = 96
	t.ring_segments = 16
	var ring := MeshInstance3D.new()
	ring.mesh = t
	ring.material_override = CosmosStation._mat(Color(0.5, 0.52, 0.56), 0.7, 0.4)
	ring.rotation.x = PI * 0.5
	add_child(ring)
	var t2 := TorusMesh.new()
	t2.inner_radius = RADIUS - 3.0
	t2.outer_radius = RADIUS + 2.0
	t2.rings = 96
	t2.ring_segments = 6
	var lit := MeshInstance3D.new()
	lit.mesh = t2
	lit.material_override = CosmosStation._mat(accent, 0.0, 0.5, accent * 4.0)
	lit.rotation.x = PI * 0.5
	add_child(lit)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", accent.lerp(Color(0.6, 0.9, 1.0), 0.5))
	m.set_shader_parameter("noise_tex", noise)
	var q := QuadMesh.new()
	q.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	var field := MeshInstance3D.new()
	field.mesh = q
	field.material_override = m
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	for i in 8:
		var a := TAU * i / 8.0
		var pod := MeshInstance3D.new()
		pod.mesh = CosmosStation._box(Vector3(40, 40, 60))
		pod.material_override = CosmosStation._mat(Color(0.3, 0.31, 0.34), 0.7, 0.5)
		pod.position = Vector3(cos(a), sin(a), 0) * (RADIUS + 30.0)
		pod.rotation.z = a
		add_child(pod)


## How far `p` (global) is through the ring's plane, and from its axis.
func crossing(p: Vector3) -> Vector2:
	var l := global_transform.affine_inverse() * p
	return Vector2(l.z, Vector2(l.x, l.y).length())
