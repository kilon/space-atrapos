class_name CosmosBolt
extends Node3D
## A rifle bolt on a planet in the 3D game: a streak of light flying straight,
## hitting the first creature, pirate or walker (whoever it's aimed at: `side`
## "player" hits animals and pirates, "enemy" hits you) in its way, or the
## ground. Checked as a segment each frame - no tunnelling at 150 m/s.

const SPEED := 150.0
const LIFE := 1.4
const SPACE_SPEED := 900.0       # (ships' lasers in space)
const SPACE_LIFE := 2.6
const GLOW := preload("res://shaders/cosmos/glow.gdshader")

static var _mesh: QuadMesh
static var _mats := {}

var side := "player"
var damage := 20.0
var cosmos: Node
var velocity := Vector3.ZERO
var space := false
var tint := Color(0, 0, 0, 0)    # (a gun's own colour; none: the side's)
var _t := 0.0
var _streak: MeshInstance3D


static func fire(c: Node, from: Vector3, dir: Vector3, who: String, dmg: float, in_space := false) -> CosmosBolt:
	var b := CosmosBolt.new()
	b.cosmos = c
	b.side = who
	b.damage = dmg
	b.space = in_space
	b.velocity = dir.normalized() * (SPACE_SPEED if in_space else SPEED)
	c.world.add_child(b)
	b.global_position = from
	return b


func _ready() -> void:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(1.1, 1.1)
	if not _mats.has(side):
		var m := ShaderMaterial.new()
		m.shader = GLOW
		m.set_shader_parameter("tint", Color(0.4, 0.9, 1.0) if side == "player" else Color(1.0, 0.35, 0.2))
		m.set_shader_parameter("intensity", 3.0)
		m.set_shader_parameter("core", 0.3)
		_mats[side] = m
	var mi := MeshInstance3D.new()   # (one glow: a bolt is one draw)
	mi.mesh = _mesh
	if tint.a > 0.0:
		var key := tint.to_html()
		if not _mats.has(key):
			var m := ShaderMaterial.new()
			m.shader = GLOW
			m.set_shader_parameter("tint", tint)
			m.set_shader_parameter("intensity", 3.0)
			m.set_shader_parameter("core", 0.3)
			_mats[key] = m
		mi.material_override = _mats[key]
	if space:
		mi.scale = Vector3.ONE * 5.0
	if mi.material_override == null:
		mi.material_override = _mats[side]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	var a := global_position
	var b := a + velocity * delta
	if _t > (SPACE_LIFE if space else LIFE) or step(a, b):
		queue_free()
		return
	global_position = b


## The segment a -> b this frame: true if it hit something (and dealt it).
func step(a: Vector3, b: Vector3) -> bool:
	if cosmos == null:
		return false
	var targets: Array = []
	if side == "player":
		if space:
			targets.append_array(cosmos.npc_ships)
		else:
			targets.append_array(cosmos.creatures)
			targets.append_array(cosmos.npcs)
	elif space:
		targets.append(cosmos.ship)
	elif cosmos.walker:
		targets.append(cosmos.walker)
	var seg := b - a
	var L := seg.length()
	var dir := seg / maxf(L, 0.0001)
	for t in targets:
		if not is_instance_valid(t) or t.get("dead"):
			continue
		var r: float = t.get("reach") if t.get("reach") != null else 0.6
		var centre: Vector3 = t.global_position if space else t.global_position + (t.up() if t.has_method("up") else Vector3.UP) * maxf(r * 0.8, 0.9)
		var tc := clampf((centre - a).dot(dir), 0.0, L)
		if (a + dir * tc).distance_to(centre) < r + 0.25:
			t.hurt(damage, a)
			return true
	# The ground.
	var pl: CosmosPlanet = cosmos.planet_below(b, 50.0)
	if pl:
		var local := b - pl.global_position
		if local.length() < pl.radius + pl.shape.surface(local.normalized()):
			return true
	return false
