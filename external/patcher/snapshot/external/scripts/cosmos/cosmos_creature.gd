class_name CosmosCreature
extends Node3D
## An animal of a planet in the 3D game (stage 3), built from its species
## (CosmosFauna): a body, legs on hip pivots, a neck and head (eyes that
## glow, horns, a crest), a tail - all shared unit meshes scaled, in the
## species' patterned skin (creature.gdshader). It walks the planet's ground
## (PlanetShape) like the walker, legs swinging with its speed. Grazers
## wander and flee when you come close; skittish ones bolt sooner; predators
## hunt you within their range and bite; hit, it flinches, and at no health
## it falls over and is gone a few seconds later.

const SHADER := preload("res://shaders/cosmos/creature.gdshader")
const SIGHT := {"grazer": 14.0, "skittish": 26.0, "predator": 38.0}

var kind := {}
var planet: CosmosPlanet
var cosmos: Node
var hp := 40.0
var max_hp := 40.0
var dead := false
var velocity := Vector3.ZERO
var facing := Vector3.FORWARD
var state := "wander"            # wander, idle, flee, hunt, dead
var _goal := Vector3.ZERO        # planet-local
var _t := 0.0
var _phase := 0.0
var _bite_cd := 0.0
var _hurt := 0.0
var _dead_t := 0.0
var _legs: Array = []            # [pivot, side offset in the gait]
var _head: Node3D
var _tail: Node3D
var _body: Node3D
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial
var reach := 1.0                 # its size (collisions, bites, hits)

static var _ball: SphereMesh
static var _limb: CapsuleMesh
static var _cone: CylinderMesh


func setup(k: Dictionary, pl: CosmosPlanet, seed: int) -> void:
	kind = k
	planet = pl
	_rng.seed = seed
	max_hp = float(k["hp"])
	hp = max_hp
	name = str(k["name"])
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 0.5
		_ball.height = 1.0
		_ball.radial_segments = 14
		_ball.rings = 8
		_limb = CapsuleMesh.new()
		_limb.radius = 0.5
		_limb.height = 2.0
		_limb.radial_segments = 8
		_limb.rings = 2
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.0
		_cone.bottom_radius = 0.5
		_cone.height = 1.0
		_cone.radial_segments = 8
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("c1", k["c1"])
	_mat.set_shader_parameter("c2", k["c2"])
	_mat.set_shader_parameter("pattern", int(k["pattern"]))
	_mat.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color.BLACK
	eye.emission_enabled = true
	eye.emission = k["eyes"] * 2.5
	var s: float = float(k["size"]) * float(k["scale"])
	var root := Node3D.new()
	root.scale = Vector3.ONE * s
	add_child(root)
	var b: Vector3 = k["body"]
	var legs: int = k["legs"]
	var ll: float = k["leg_len"]
	var hip := ll if legs > 0 else b.y * 0.45
	_body = Node3D.new()
	_body.position.y = hip + b.y * 0.35
	root.add_child(_body)
	_part(_ball, _body, Vector3.ZERO, b)
	if k["crest"]:
		_part(_cone, _body, Vector3(0, b.y * 0.5, 0), Vector3(0.12, b.y * 0.6, b.z * 0.6))
	# Legs: pairs along the body.
	var pairs := legs / 2
	for i in pairs:
		var z := 0.0 if pairs == 1 else lerpf(-b.z * 0.32, b.z * 0.32, float(i) / (pairs - 1))
		for side in [-1.0, 1.0]:
			var piv := Node3D.new()
			piv.position = Vector3(side * b.x * 0.38, 0.0, z)
			_body.add_child(piv)
			_part(_limb, piv, Vector3(0, -ll * 0.5 - b.y * 0.1, 0), Vector3(k["leg_w"], (ll + b.y * 0.3) * 0.5, k["leg_w"]))
			_legs.append([piv, (0.0 if side < 0 else PI) + i * PI * 0.5])
	# Neck and head (forward is -z).
	var neck: float = k["neck"]
	var hs: float = k["head"]
	_head = Node3D.new()
	_head.position = Vector3(0, b.y * 0.25 + neck * 0.7, -b.z * 0.5 - neck * 0.3)
	_body.add_child(_head)
	if neck > 0.15:
		var n := _part(_limb, _body, (_head.position + Vector3(0, 0, -b.z * 0.35)) * 0.5, Vector3(hs * 0.45, neck * 0.45 + 0.1, hs * 0.45))
		n.rotation.x = -0.5
	_part(_ball, _head, Vector3.ZERO, Vector3(hs, hs * 0.85, hs * 1.1))
	if float(k["snout"]) > 0.1:
		_part(_ball, _head, Vector3(0, -hs * 0.1, -hs * 0.55), Vector3(hs * 0.6, hs * 0.5, float(k["snout"]) + hs * 0.4))
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = _ball
		e.material_override = eye
		e.position = Vector3(side * hs * 0.3, hs * 0.18, -hs * 0.42)
		e.scale = Vector3.ONE * hs * 0.22
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_head.add_child(e)
	for h in int(k["horns"]):
		var side := -1.0 if h == 0 else 1.0
		var horn := _part(_cone, _head, Vector3(side * hs * 0.3, hs * 0.55, 0), Vector3(hs * 0.18, hs * 0.9, hs * 0.18))
		horn.rotation.z = -side * 0.4
	if float(k["tail"]) > 0.15:
		_tail = Node3D.new()
		_tail.position = Vector3(0, b.y * 0.1, b.z * 0.5)
		_body.add_child(_tail)
		var t := _part(_cone, _tail, Vector3(0, 0, float(k["tail"]) * 0.5), Vector3(b.x * 0.35, float(k["tail"]), b.x * 0.35))
		t.rotation.x = PI * 0.5 + 0.3
	reach = maxf(b.z, b.x) * 0.55 * s + 0.2
	_new_goal()


func _part(mesh: Mesh, parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.position = at
	mi.scale = size
	mi.visibility_range_end = 220.0
	if size.length() < 0.5:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func up() -> Vector3:
	return (global_position - planet.global_position).normalized()


func _new_goal() -> void:
	var u := up() if planet and is_inside_tree() else Vector3.UP
	var t := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _rng.randf() * TAU)
	_goal = (global_position - planet.global_position) + t * _rng.randf_range(8.0, 30.0) if planet and is_inside_tree() else Vector3.ZERO
	_t = _rng.randf_range(3.0, 8.0)
	state = "wander" if _rng.randf() < 0.7 else "idle"


## A hit: `dmg` from `from` (a world point).
func hurt(dmg: float, from: Vector3) -> void:
	if dead:
		return
	hp -= dmg
	_hurt = 0.25
	if hp <= 0.0:
		dead = true
		state = "dead"
		_dead_t = 0.0
		if cosmos:
			cosmos.creature_died(self)
		return
	if kind["temper"] == "predator":
		state = "hunt"
	else:
		state = "flee"
		_t = 6.0


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if planet == null:
		return
	var u := up()
	if dead:
		_dead_t += delta
		_body.rotation.z = lerpf(_body.rotation.z, PI * 0.5, 1.0 - exp(-delta * 5.0))
		if _dead_t > 4.0:
			_body.position.y -= delta * 0.6
		if _dead_t > 7.0:
			queue_free()
		return
	_hurt = maxf(0.0, _hurt - delta)
	_mat.set_shader_parameter("flash", _hurt * 4.0)
	_bite_cd = maxf(0.0, _bite_cd - delta)
	var me := global_position - planet.global_position
	var player: Node3D = cosmos.walker if cosmos else null
	var to_player := Vector3.ZERO
	var pd := INF
	if player and not player.get("downed"):
		to_player = player.global_position - global_position
		pd = to_player.length()
	var sight: float = SIGHT[kind["temper"]] * (1.4 if kind["monster"] else 1.0)
	var want := Vector3.ZERO
	var speed := 0.0
	match state:
		"wander", "idle":
			_t -= delta
			if _t <= 0.0:
				_new_goal()
			if state == "wander":
				var g := _goal - me
				g -= u * g.dot(u)
				if g.length() < 1.5:
					state = "idle"
				else:
					want = g.normalized()
					speed = float(kind["walk"])
			if pd < sight:
				state = "hunt" if kind["temper"] == "predator" else "flee"
				_t = 6.0
		"flee":
			_t -= delta
			if pd < INF:
				var away := -to_player
				away -= u * away.dot(u)
				want = away.normalized()
			speed = float(kind["run"])
			if _t <= 0.0 and pd > sight * 1.5:
				_new_goal()
		"hunt":
			if pd > sight * 2.2:
				_new_goal()
			elif pd < INF:
				var go := to_player - u * to_player.dot(u)
				want = go.normalized()
				var bite_at := reach + 0.9
				speed = float(kind["run"]) if pd > bite_at else 0.0
				if pd <= bite_at + 0.3:
					facing = want
					if _bite_cd <= 0.0:
						_bite_cd = 1.2
						player.hurt(float(kind["bite"]), self)
						_head.position.z -= 0.15
	var flat := velocity - u * velocity.dot(u)
	flat = flat.move_toward(want * speed, 10.0 * delta)
	velocity = flat
	global_position += velocity * delta
	# Stand on the ground (out of the sea: grazers don't swim - turn back).
	var local := global_position - planet.global_position
	var d := local.normalized()
	var h := planet.shape.height(d)
	if planet.shape.sea > 0 and h < 0.3:
		global_position -= velocity * delta * 2.0
		velocity = -velocity * 0.5
		_new_goal()
		local = global_position - planet.global_position
		d = local.normalized()
		h = maxf(planet.shape.height(d), 0.3)
	global_position = planet.global_position + d * (planet.radius + h)
	if flat.length() > 0.3:
		facing = facing.slerp(flat.normalized(), 1.0 - exp(-delta * 6.0)) if facing.dot(flat.normalized()) > -0.95 else flat.normalized()
	facing = (facing - d * facing.dot(d)).normalized()
	if facing.length() < 0.5:
		facing = d.cross(Vector3.RIGHT).normalized()
	global_basis = Basis.looking_at(facing, d)
	# The gait.
	var v := flat.length()
	_phase += delta * (2.0 + v * 2.2 / maxf(float(kind["size"]) * float(kind["scale"]), 0.5))
	var swing := clampf(v / maxf(float(kind["walk"]), 0.5), 0.0, 1.6) * 0.45
	for l in _legs:
		(l[0] as Node3D).rotation.x = sin(_phase + l[1]) * swing
	_body.position.y += (absf(sin(_phase)) * 0.06 * swing - (_body.position.y - _body_base())) * minf(1.0, delta * 10.0)
	if _tail:
		_tail.rotation.y = sin(_phase * 0.5) * 0.4
	_head.rotation.x = sin(_phase * 0.5) * 0.08 + (0.25 if state == "idle" else 0.0)
	_head.position.z = lerpf(_head.position.z, -float(kind["body"].z) * 0.5 - float(kind["neck"]) * 0.3, delta * 4.0)


func _body_base() -> float:
	var b: Vector3 = kind["body"]
	var ll: float = kind["leg_len"]
	return (ll if int(kind["legs"]) > 0 else b.y * 0.45) + b.y * 0.35
