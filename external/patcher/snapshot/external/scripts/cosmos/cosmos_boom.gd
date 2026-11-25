class_name CosmosBoom
extends Node3D
## A ship blowing up in the 3D game (stage 4): a flash swelling and fading
## (glows), and pieces of hull tumbling away, gone in a few seconds.

const LIFE := 2.6

var _t := 0.0
var _size := 10.0
var _flash: Array = []
var _bits: Array = []           # [node, velocity, spin]

static var _mat_hot: ShaderMaterial
static var _mat_smoke: ShaderMaterial
static var _bit_mat: StandardMaterial3D


static func at(c: Node, p: Vector3, size: float) -> void:
	if c == null:
		return
	var b := CosmosBoom.new()
	b._size = size
	c.world.add_child(b)
	b.global_position = p


func _ready() -> void:
	if _mat_hot == null:
		_mat_hot = ShaderMaterial.new()
		_mat_hot.shader = preload("res://shaders/cosmos/glow.gdshader")
		_mat_hot.set_shader_parameter("tint", Color(1.0, 0.6, 0.25))
		_mat_hot.set_shader_parameter("intensity", 3.0)
		_mat_smoke = ShaderMaterial.new()
		_mat_smoke.shader = preload("res://shaders/cosmos/glow.gdshader")
		_mat_smoke.set_shader_parameter("tint", Color(1.0, 0.85, 0.6))
		_mat_smoke.set_shader_parameter("intensity", 1.2)
		_bit_mat = CosmosStation._mat(Color(0.3, 0.3, 0.32), 0.6, 0.5, Color(1.0, 0.4, 0.1) * 0.6)
	for m in [_mat_hot, _mat_smoke]:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_flash.append(mi)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = CosmosStation._box(Vector3(rng.randf_range(0.5, 2.0), rng.randf_range(0.2, 1.0), rng.randf_range(0.5, 2.5)) * _size * 0.12)
		mi.material_override = _bit_mat
		add_child(mi)
		_bits.append([mi, Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf_range(10.0, 40.0) * _size * 0.08,
			Vector3(rng.randfn(), rng.randfn(), rng.randfn())])


func _process(delta: float) -> void:
	_t += delta
	var k := _t / LIFE
	if k >= 1.0:
		queue_free()
		return
	(_flash[0] as Node3D).scale = Vector3.ONE * _size * (1.0 + k * 6.0) * (1.0 - k)
	(_flash[1] as Node3D).scale = Vector3.ONE * _size * (2.0 + k * 9.0) * (1.0 - k) * 0.8
	for b in _bits:
		var n: Node3D = b[0]
		n.position += (b[1] as Vector3) * delta
		n.rotation += (b[2] as Vector3) * delta
