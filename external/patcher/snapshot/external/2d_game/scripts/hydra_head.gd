class_name HydraHead
extends SpaceMonster
## A double head of the Hydra (HydraBeast): two heads on one neck, grown where
## one of its heads was cut off - the reference art itself
## (external/images/hydra/hydra_double_head.png, cut by tools/hydra_parts.py).
## Its own ship (EnemyTypes "hydra_head") but untouchable - no target, no
## health bar - it keeps its place round the Hydra (Enemy.leader) and dies
## only with it. Upright,
## its necks swaying; it spits from both jaws in turn, resting longer than
## the Hydra between attacks (pause) - there can be twelve of them.

const ART := "res://data/sprites/monster_hydra"
const VENOM := Color(0.55, 1.0, 0.25)
const POOL := ["twin_fangs", "twin_spit", "twin_ring"]

var meta := {}
var art_scale := 0.1
var demo := false
var _rig: Node2D
var _spr: Sprite2D


func _ready() -> void:
	super()
	glow = VENOM
	cinematic = false   # (a quick death: no camera, one blast)
	throes_time = 0.7
	pause = randf_range(3.2, 4.4)
	_cool = randf_range(0.8, 2.0)
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.5 / 1536.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	_spr = Sprite2D.new()
	_spr.texture = load(ART + "_double_head.png")
	_spr.centered = false
	_spr.position = _v(meta["parts"]["double_head"]) - _v(meta["double_head_neck"])
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rig.add_child(_spr)


func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Its picture (1333 x 905 art px), upright.
func visual_size() -> Vector2:
	return Vector2(1333, 905) * length * 1.5 / 1536.0


## Jaw 0 (left) or 1 (right), world.
func jaw(i: int) -> Vector2:
	if meta.is_empty() or _rig == null:
		return global_position
	return _rig.to_global(_v(meta["double_head_mouths"][i]) - _v(meta["double_head_neck"]))


func mouth() -> Vector2:
	return jaw(orbs_fired % 2)


func pattern_pool() -> Array:
	return POOL


func _process(delta: float) -> void:
	super(delta)
	if _rig == null:
		return
	_rig.global_rotation = 0.06 * sin(_t * 1.7)
	var charge := 0.0 if pattern == "" else (clampf(1.0 + _pt / CHARGE, 0.0, 1.0) if _pt < 0.0 else 1.0)
	_rig.scale = Vector2(art_scale * (1.0 + 0.04 * charge), art_scale * (1.0 + 0.02 * sin(_t * 2.2)))


## Only its picture (not the procedural creature SpaceMonster draws).
func _draw() -> void:
	pass


func _pattern_step(name: String, delta: float, aim: float) -> float:
	match name:
		"twin_fangs":   # a fang from each jaw at you, three times
			for r in 3:
				if _crossed(r * 0.3):
					for i in 2:
						var tgt := _target()
						var from := jaw(i)
						var a: float = (tgt.global_position - from).angle() if tgt else aim
						_shot(Vector2.from_angle(a) * 220.0, Color(1, 1, 1), "fang", from)
			return 0.9
		"twin_spit":   # a short fan of venom from each jaw
			if _crossed(0.0):
				for i in 2:
					for k in 3:
						_shot(Vector2.from_angle(aim + (k - 1) * 0.22) * 175.0, VENOM, "venom", jaw(i))
			return 0.6
		"twin_ring":   # a little ring of venom
			if _crossed(0.0):
				for k in 10:
					_shot(Vector2.from_angle(k * TAU / 10.0 + randf()) * 140.0, VENOM, "venom", jaw(k % 2))
			return 0.6
	return super(name, delta, aim)
