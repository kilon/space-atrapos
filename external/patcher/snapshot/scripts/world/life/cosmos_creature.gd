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

const SHADER := preload("res://shaders/world/creature.gdshader")
const SIGHT := {"grazer": 14.0, "skittish": 26.0, "predator": 38.0}

var _turn := SmoothTurn.new(6.0, 6.0, 12.0)
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
var _wings: Array = []           # [pivot, side] (birds, moths, rays)
var _tentacles: Array = []       # [pivot, phase] (drifting jellies)
var _alt := 0.0                  # (how high it flies or floats now)
var _fly: MeshInstance3D         # (a dragonfly: its own model - CosmosDragonfly)
var _wmat: ShaderMaterial        # (... its wings, beaten in their shader)
var _fly_wait := false           # (... its mesh still being made on a worker)
var _beat := 0.0
var _dart_t := 0.0
var _darting := false
var _hover := 0.0
var _last_flat := Vector3.ZERO
var _ray: MeshInstance3D         # (an aeromanta: its own model - CosmosAeromanta)
var _ray_wait := false
var _wave := 0.3                 # (... how deep its wing waves are now)
var _stroking := false
var _bend := 0.0
var _fox: MeshInstance3D         # (a red fox: its own model - CosmosFox - on its own rig)
var _rig: CosmosFox.Rig
var _fox_wait := false
var _pace := 1.0

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
	_mat.set_shader_parameter("glow", float(k.get("glow", 0.0)))
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
	if str(k.get("model", "")) == "dragonfly":
		_dragonfly(k)
		reach = maxf(b.z, b.x) * 0.55 * s + 0.2
		_new_goal()
		return
	if str(k.get("model", "")) == "fox":
		_fox_build(k)
		reach = maxf(b.z, b.x) * 0.55 * s + 0.2
		_new_goal()
		return
	if str(k.get("model", "")) == "aeromanta":
		_aeromanta(k)
		reach = maxf(b.z, b.x) * 0.55 * s + 0.2
		_new_goal()
		return
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
			if k.get("splay", false):
				piv.rotation.z = side * 0.75   # (an insect's legs, out to the sides)
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
	if float(k.get("ears", 0.0)) > 0.0:
		for side in [-1.0, 1.0]:
			var ear := _part(_cone, _head, Vector3(side * hs * 0.25, hs * 0.5, hs * 0.15), Vector3(hs * 0.18, float(k["ears"]), hs * 0.1))
			ear.rotation = Vector3(0.35, 0, -side * 0.25)
	if float(k.get("antlers", 0.0)) > 0.0:
		var a: float = k["antlers"]
		for side in [-1.0, 1.0]:
			var beam := _part(_limb, _head, Vector3(side * hs * 0.35, hs * 0.5 + a * 0.35, hs * 0.2), Vector3(0.05, a * 0.4, 0.05))
			beam.rotation = Vector3(0.45, 0, -side * 0.55)
			for t in 3:
				var tine := _part(_cone, _head, Vector3(side * (hs * 0.35 + a * (0.12 + t * 0.12)), hs * 0.5 + a * (0.3 + t * 0.2), hs * 0.2 + a * 0.1 * t), Vector3(0.06, a * 0.3, 0.06))
				tine.rotation = Vector3(-0.3, 0, -side * 0.2)
	if float(k.get("shell", 0.0)) > 0.0:
		var sh: float = k["shell"]
		_part(_ball, _body, Vector3(0, b.y * 0.2, 0), Vector3(b.x * 1.18, b.y * (0.6 + 0.5 * sh), b.z * 1.08))
	if float(k.get("cap", 0.0)) > 0.0:
		var cap := MeshInstance3D.new()
		var cm := StandardMaterial3D.new()
		cm.albedo_color = k["c2"]
		cm.roughness = 0.7
		cap.mesh = _ball
		cap.material_override = cm
		cap.position = Vector3(0, b.y * 0.55, 0)
		cap.scale = Vector3(b.x * 1.8, 0.35 + b.y * 0.3, b.z * 1.15) * float(k["cap"])
		cap.visibility_range_end = 220.0
		_body.add_child(cap)
	if float(k.get("wings", 0.0)) > 0.0:
		var span: float = k["wings"]
		for side in [-1.0, 1.0]:
			var piv := Node3D.new()
			piv.position = Vector3(side * b.x * 0.35, b.y * 0.2, -b.z * 0.05)
			_body.add_child(piv)
			_part(_ball, piv, Vector3(side * span * 0.5, 0, 0), Vector3(span, 0.05, b.z * 0.75))
			_wings.append([piv, side])
	for i in int(k.get("tentacles", 0)):
		var a := TAU * i / float(k["tentacles"])
		var piv := Node3D.new()
		piv.position = Vector3(cos(a) * b.x * 0.3, -b.y * 0.3, sin(a) * b.z * 0.3)
		_body.add_child(piv)
		_part(_limb, piv, Vector3(0, -0.6, 0), Vector3(0.05, 0.6, 0.05))
		_tentacles.append([piv, a])
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


## A dragonfly: one mesh (its body and four wings - two surfaces), shared by
## them all; its own two materials (the flash, the beat). The mesh is made on a
## worker - until it's ready nothing shows.
func _dragonfly(k: Dictionary) -> void:
	var mats := CosmosDragonfly.materials(k["c1"], k["c2"])
	_mat = mats[0]
	_wmat = mats[1]
	_fly = MeshInstance3D.new()
	_fly.visibility_range_end = 220.0
	_body.add_child(_fly)
	_head = Node3D.new()   # (its head part of the one mesh: nothing to turn)
	_body.add_child(_head)
	_beat = _rng.randf() * TAU
	_dart_t = _rng.randf_range(0.3, 1.5)
	_hover = _rng.randf() * 10.0
	if CosmosDragonfly.is_ready():
		_fly_attach()
	else:
		CosmosDragonfly.start()
		_fly_wait = true


func _fly_attach() -> void:
	_fly_wait = false
	_fly.mesh = CosmosDragonfly.mesh()
	_fly.set_surface_override_material(0, _mat)
	_fly.set_surface_override_material(1, _wmat)


## A red fox: one skinned mesh (one surface) shared by them all - made on a
## worker, nothing shown until it's ready - on its own skeleton, which its Rig poses.
func _fox_build(k: Dictionary) -> void:
	_mat = CosmosFox.material(k["c1"], k["c2"])
	_body.position.y = 0.0   # (its model stands on the ground)
	var sk := CosmosFox.skeleton()
	_body.add_child(sk)
	_fox = MeshInstance3D.new()
	_fox.visibility_range_end = 220.0
	sk.add_child(_fox)
	_fox.skeleton = NodePath("..")
	_fox.skin = CosmosFox.skin()
	_head = Node3D.new()
	_body.add_child(_head)
	_rig = CosmosFox.Rig.new(sk, _rng.randi())
	if CosmosFox.is_ready():
		_fox_attach()
	else:
		CosmosFox.start()
		_fox_wait = true


func _fox_attach() -> void:
	_fox_wait = false
	_fox.mesh = CosmosFox.mesh()
	_fox.material_override = _mat


## An aeromanta: one mesh of one surface, shared by them all (made on a worker -
## nothing shows until it's ready), its own material (the flash, the waves).
func _aeromanta(k: Dictionary) -> void:
	_mat = CosmosAeromanta.material(k["c1"], k["c2"])
	_ray = MeshInstance3D.new()
	_ray.visibility_range_end = 260.0
	_body.add_child(_ray)
	_head = Node3D.new()
	_body.add_child(_head)
	_beat = _rng.randf() * TAU
	_dart_t = _rng.randf_range(1.0, 4.0)
	_hover = _rng.randf() * 10.0
	if CosmosAeromanta.is_ready():
		_ray_attach()
	else:
		CosmosAeromanta.start()
		_ray_wait = true


func _ray_attach() -> void:
	_ray_wait = false
	_ray.mesh = CosmosAeromanta.mesh()
	_ray.material_override = _mat


## The aeromanta swimming the air: bouts of strokes - waves rolling out along
## its wings - and long glides between them (fleeing, strokes all the way);
## banking into its turns, pitching a little with the beat, its tail trailing
## the turn.
func _ray_motion(delta: float, flat: Vector3, d: Vector3) -> void:
	_dart_t -= delta
	if _dart_t <= 0.0:
		_stroking = not _stroking
		_dart_t = _rng.randf_range(2.5, 5.0) if _stroking else _rng.randf_range(3.0, 7.0)
	var hard := state == "flee"
	var want_wave := 1.0 if hard else (0.75 if _stroking else 0.12)
	_wave = lerpf(_wave, want_wave, 1.0 - exp(-delta * 0.8))
	_beat = fmod(_beat + delta * lerpf(1.0, 2.6 if hard else 2.0, clampf(_wave, 0.0, 1.0)), TAU * 64.0)
	var acc := (flat - _last_flat) / maxf(delta, 1e-4)
	_last_flat = flat
	var lat := facing.cross(d).dot(acc)
	var k := 1.0 - exp(-delta * 1.8)
	_body.rotation.z = lerpf(_body.rotation.z, clampf(lat * 0.09, -0.6, 0.6), k)
	_body.rotation.x = lerpf(_body.rotation.x, sin(_beat - 0.6) * 0.06 * _wave + clampf(facing.dot(acc) * -0.02, -0.15, 0.15), k)
	_bend = lerpf(_bend, clampf(-lat * 0.06, -0.5, 0.5), 1.0 - exp(-delta * 1.2))
	_mat.set_shader_parameter("phase", _beat)
	_mat.set_shader_parameter("wave", _wave)
	_mat.set_shader_parameter("bend", _bend)


## A dragonfly's pace: hovering still (a slow creep), then a dart - fast, short -
## and hovering again; fleeing, the hovers short.
func _fly_speed(delta: float, want: Vector3, speed: float) -> float:
	_dart_t -= delta
	if _dart_t <= 0.0:
		_darting = not _darting
		var hurry := 0.35 if state == "flee" else 1.0
		_dart_t = _rng.randf_range(0.25, 0.55) if _darting else _rng.randf_range(0.5, 2.0) * hurry
	if want == Vector3.ZERO:
		return 0.0
	return maxf(speed, 1.0) * (4.0 if _darting else 0.12)


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


## Far from you (LAZY_FAR m) it thinks one frame in three - the time it
## missed added in (at hundreds of frames a second that's still smooth); near, every frame.
const LAZY_FAR := 35.0
var _lazy := 0
var _lazy_dt := 0.0


func _lazy_step(delta: float) -> float:
	_lazy_dt += delta
	var f: Node3D = cosmos.focus() if cosmos and cosmos.has_method("focus") else null
	if f and f.global_position.distance_squared_to(global_position) > LAZY_FAR * LAZY_FAR:
		_lazy += 1
		if _lazy % 3 != 0:
			return -1.0
	var d := minf(_lazy_dt, 0.15)
	_lazy_dt = 0.0
	return d
var _flash_on := false


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if _fly_wait and CosmosDragonfly.is_ready():
		_fly_attach()
	if _ray_wait and CosmosAeromanta.is_ready():
		_ray_attach()
	if _fox_wait and CosmosFox.is_ready():
		_fox_attach()
	if planet == null:
		return
	var u := up()
	if dead:
		_dead_t += delta
		_body.rotation.z = lerpf(_body.rotation.z, PI * 0.5, 1.0 - exp(-delta * 5.0))
		if _wmat and _dead_t < 0.1:
			_wmat.set_shader_parameter("flap", 0.0)
		if _ray and _dead_t < 0.1:
			_mat.set_shader_parameter("wave", 0.0)
		if _dead_t > 4.0:
			_body.position.y -= delta * 0.6
		if _dead_t > 7.0:
			queue_free()
		return
	var ld := _lazy_step(delta)
	if ld < 0.0:
		return
	delta = ld
	if _hurt > 0.0 or _flash_on:   # (its hit flash: set only while it shows)
		_hurt = maxf(0.0, _hurt - delta)
		_mat.set_shader_parameter("flash", _hurt * 4.0)
		_flash_on = _hurt > 0.0
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
	if _fly:
		speed = _fly_speed(delta, want, speed)
	if _rig:   # (a fox: wandering, now trotting, now walking with its nose down; leaping when it pounces)
		if state == "wander" and _rng.randf() < delta * 0.12:
			_pace = 0.4 if _pace > 0.5 else 1.0
		if state == "wander":
			speed *= _pace
		var leap := _rig.leap_speed()
		if leap >= 0.0:
			want = facing
			speed = leap
	if _ray:   # (a manta never stops: it cruises on, gliding)
		if want == Vector3.ZERO:
			want = facing
		if state != "flee":
			speed = maxf(speed, 2.2)
	var flat := velocity - u * velocity.dot(u)
	flat = flat.move_toward(want * speed, (30.0 if _fly else 10.0) * delta)
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
	# Flying or floating: its height over the ground (birds take off when they flee).
	var fly_to := float(kind.get("alt", 0.0))
	if state == "hunt":
		fly_to = minf(fly_to, 0.4)   # (hunters come down to bite)
	if _wings.size() > 0 and fly_to <= 0.0 and state == "flee":
		fly_to = 7.0
	_alt = lerpf(_alt, fly_to, 1.0 - exp(-delta * 1.5))
	var bob := sin(_phase * 0.3) * 0.25 if fly_to > 0.0 else 0.0
	if _fly:   # (a dragonfly hovers steady: tiny bobs)
		_hover += delta
		bob = sin(_hover * 5.3) * 0.025 + sin(_hover * 1.9) * 0.06
	if _ray:   # (rising a little with each stroke, sinking in the glides)
		_hover += delta
		bob = sin(_beat) * 0.12 * _wave + sin(_hover * 0.3) * 0.5
	global_position = planet.global_position + d * (planet.radius + h + _alt + bob)
	if cosmos and cosmos.get("builds") and cosmos.builds.planet == planet:   # (kept out of what's built - a hunter pushes an unlocked door open)
		global_position += cosmos.builds.push_body(global_position, 0.5, state == "hunt")
	if flat.length() > 0.3:
		facing = _turn.step(facing, flat, d, delta)   # (round smoothly - a reversal turned, not snapped)
	facing = (facing - d * facing.dot(d)).normalized()
	if facing.length() < 0.5:
		facing = d.cross(Vector3.RIGHT).normalized()
	global_basis = Basis.looking_at(facing, d)
	if _fly:
		_fly_motion(delta, flat, d)
		return
	if _ray:
		_ray_motion(delta, flat, d)
		return
	if _rig:
		_rig.step(delta, flat.length(), float(kind["size"]) * float(kind["scale"]), state == "idle", state == "flee")
		_body.position.y = _rig.leap_height()
		return
	# The gait.
	var v := flat.length()
	_phase += delta * (2.0 + v * 2.2 / maxf(float(kind["size"]) * float(kind["scale"]), 0.5))
	var swing := clampf(v / maxf(float(kind["walk"]), 0.5), 0.0, 1.6) * 0.45
	for l in _legs:
		(l[0] as Node3D).rotation.x = sin(_phase + l[1]) * swing
	_body.position.y += (absf(sin(_phase)) * 0.06 * swing - (_body.position.y - _body_base())) * minf(1.0, delta * 10.0)
	if _tail:
		_tail.rotation.y = sin(_phase * 0.5) * 0.4
	var flying := _alt > 0.5
	for w in _wings:
		(w[0] as Node3D).rotation.z = float(w[1]) * (sin(_phase * (2.5 if flying else 0.6)) * (0.6 if flying else 0.08) + (0.0 if flying else 0.9))
	for t in _tentacles:
		(t[0] as Node3D).rotation = Vector3(sin(_phase * 0.8 + float(t[1])) * 0.3, 0, cos(_phase * 0.7 + float(t[1])) * 0.3)
	_head.rotation.x = sin(_phase * 0.5) * 0.08 + (0.25 if state == "idle" else 0.0)
	_head.position.z = lerpf(_head.position.z, -float(kind["body"].z) * 0.5 - float(kind["neck"]) * 0.3, delta * 4.0)


## The dragonfly's wings beating (faster darting), its body pitching with how it
## speeds up or slows, rolling a little in turns, the abdomen held straight with a slight flex.
func _fly_motion(delta: float, flat: Vector3, d: Vector3) -> void:
	var acc := (flat - _last_flat) / maxf(delta, 1e-4)
	_last_flat = flat
	var fwd := facing.dot(acc)
	var lat := facing.cross(d).dot(acc)
	var k := 1.0 - exp(-delta * 6.0)
	_body.rotation.x = lerpf(_body.rotation.x, clampf(-fwd * 0.02, -0.35, 0.3) + sin(_hover * 1.3) * 0.02, k)
	_body.rotation.z = lerpf(_body.rotation.z, clampf(lat * 0.015, -0.3, 0.3), k)
	var hz := 18.0 if _darting and flat.length() > 1.0 else 13.0
	_beat = fmod(_beat + delta * hz * TAU, TAU * 64.0)
	_wmat.set_shader_parameter("phase", _beat)
	_wmat.set_shader_parameter("flap", 1.0 if _alt > 0.3 else 0.15)
	_mat.set_shader_parameter("flex", sin(_hover * 0.9) * 0.25 + clampf(fwd * 0.01, -0.4, 0.4))
	_mat.set_shader_parameter("sway", sin(_hover * 0.7 + 1.0) * 0.2)


func _body_base() -> float:
	var b: Vector3 = kind["body"]
	var ll: float = kind["leg_len"]
	return (ll if int(kind["legs"]) > 0 else b.y * 0.45) + b.y * 0.35
