class_name CosmosNpc
extends Node3D
## A pirate android on a planet in the 3D game (stage 3): its actual model
## (art/pirate_3d - rendered from Blender's pirate.blend; its cel shaders and
## clips: walk, guard, gun_idle, gun_walk, fire, hit, ko). It guards its camp
## - pacing about it - until you come within SIGHT: then it raises its rifle,
## keeps 14-26 m from you, strafing, and fires bolts (CosmosBolt, a little
## wide - the further, the wider). Hit, it flinches; at no health it drops
## (ko) and is gone a few seconds later.

const SIGHT := 48.0
const SPEED := 3.0
const FIRE_EVERY := 1.15
const DAMAGE := 7.0

var planet: CosmosPlanet
var cosmos: Node
var camp := Vector3.ZERO         # planet-local
var hp := 80.0
var max_hp := 80.0
var dead := false
var reach := 0.55
var facing := Vector3.FORWARD
var _goal := Vector3.ZERO
var _t := 0.0
var _fire := 0.0
var _anim: AnimationPlayer
var _clip := ""
var _strafe := 1.0
var _dead_t := 0.0
var _rng := RandomNumberGenerator.new()
var label := "Pirate android"


func setup(pl: CosmosPlanet, camp_local: Vector3, seed: int) -> void:
	planet = pl
	camp = camp_local
	_rng.seed = seed
	_fire = _rng.randf_range(0.5, 1.5)
	name = "Pirate"


func _ready() -> void:
	if Stage3D.has_model("pirate"):
		var model: Node3D = Stage3D._scene("pirate").instantiate()
		model.rotation.y = PI
		add_child(model)
		CosmosModels.apply(model, "pirate")   # (two draws: its parts merged, colours in the vertices)
		_anim = model.find_child("AnimationPlayer", true, false)
		if _anim:
			for c in ["walk", "guard", "gun_idle", "gun_walk"]:
				if _anim.has_animation(c):
					_anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	else:
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.9
		cap.mesh = cm
		cap.position.y = 0.95
		add_child(cap)
	_play("guard")


func up() -> Vector3:
	return (global_position - planet.global_position).normalized()


func hurt(dmg: float, _from: Vector3) -> void:
	if dead:
		return
	hp -= dmg
	_play("hit", true)
	_t = 0.0
	if hp <= 0.0:
		dead = true
		_play("ko", true)
		if cosmos:
			cosmos.npc_died(self)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if planet == null:
		return
	if dead:
		_dead_t += delta
		if _dead_t > 6.0:
			queue_free()
		return
	var u := up()
	var me := global_position - planet.global_position
	var player: Node3D = cosmos.walker if cosmos else null
	var to := Vector3.ZERO
	var pd := INF
	if player and not player.get("downed"):
		to = player.global_position - global_position
		pd = to.length()
	var move := Vector3.ZERO
	var busy := _anim != null and _clip in ["hit", "fire"] and _anim.is_playing()
	if pd < SIGHT:
		var flat := to - u * to.dot(u)
		facing = flat.normalized()
		var side := facing.cross(u) * _strafe
		var want := 0.0
		if pd > 26.0:
			want = 1.0
		elif pd < 14.0:
			want = -1.0
		move = facing * want + side * 0.6
		_t -= delta
		if _t <= 0.0:
			_t = _rng.randf_range(1.5, 3.5)
			_strafe = -_strafe
		_fire -= delta
		if _fire <= 0.0 and not busy:
			_fire = FIRE_EVERY * _rng.randf_range(0.8, 1.3)
			var muzzle := global_position + u * 1.35 + facing * 0.7
			var aim: Vector3 = player.global_position + player.up() * 1.1 - muzzle
			var spread := 0.008 + pd * 0.0004
			aim = aim.normalized() + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))
			CosmosBolt.fire(cosmos, muzzle, aim, "enemy", DAMAGE)
			_play("fire", true)
		elif not busy:
			_play("gun_walk" if move.length() > 0.3 else "gun_idle")
	else:
		# On guard: pacing about the camp.
		_t -= delta
		if _t <= 0.0:
			_t = _rng.randf_range(3.0, 7.0)
			var t := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _rng.randf() * TAU)
			_goal = camp + t * _rng.randf_range(3.0, 14.0)
		var g := _goal - me
		g -= u * g.dot(u)
		if g.length() > 1.0:
			move = g.normalized() * 0.6
			facing = g.normalized()
		if not busy:
			_play("walk" if move.length() > 0.1 else "guard")
	global_position += move * SPEED * delta
	var local := global_position - planet.global_position
	var d := local.normalized()
	global_position = planet.global_position + d * (planet.radius + maxf(planet.shape.height(d), 0.0))
	facing = (facing - d * facing.dot(d)).normalized()
	if facing.length() < 0.5:
		facing = d.cross(Vector3.RIGHT).normalized()
	global_basis = Basis.looking_at(facing, d)


func _play(clip: String, restart := false) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if clip != _clip or restart:
		_anim.play(clip, 0.15)
		if restart:
			_anim.seek(0.0, true)
		_clip = clip
