class_name CosmosNpcShip
extends Node3D
## Another ship in the 3D game's space (stage 4): a procedural hull
## (CosmosHull) of its kind - a trader plying between the system's stations
## and planets (on its own Hyperion drive between them: a streak across the
## sky), a patrol of the system's empire circling a station, or a pirate who
## comes for you: closing in, circling, firing its lasers (CosmosBolt, space
## speed) when its nose is on you. Shields soak hits and come back; the hull
## doesn't. At none it blows up (CosmosBoom).

const TURN := 1.1               # rad/s
const LASER_EVERY := 0.55

var kind := "trader"
var cosmos: Node
var faction := ""
var shield := 60.0
var max_shield := 60.0
var hull := 80.0
var max_hull := 80.0
var dead := false
var velocity := Vector3.ZERO
var speed_max := 160.0
var reach := 12.0
var dest: Node3D = null          # a trader's next stop
var home: Node3D = null          # a patrol's station
var hostile := false
var label := ""
var _cruise := false
var _fire := 1.0
var _since_hit := 99.0
var _rng := RandomNumberGenerator.new()
var _orbit := 1.0
var _glows: Array = []

static var _glow_mat: ShaderMaterial


func setup(k: String, c: Node, seed: int, empire: String) -> void:
	kind = k
	add_to_group("cam_solid")   # (the camera stops short of its parts)
	set_meta("cam_reach", 80.0)
	cosmos = c
	_rng.seed = seed
	faction = empire
	hostile = k == "pirate"
	var accent: Color = Galaxy.empire_color(empire) if k != "pirate" else Color(0.75, 0.15, 0.1)
	var hc := Color(0.75, 0.76, 0.78) if k != "pirate" else Color(0.3, 0.28, 0.27)
	var hk: String = {"trader": "trader" if _rng.randf() < 0.7 else "freighter", "patrol": "patrol", "pirate": "pirate"}.get(k, "fighter")
	var nozzles := CosmosHull.build(self, _rng, hk, accent, hc)
	reach = CosmosHull.SIZE.get(hk, 1.0) * 11.0
	match k:
		"trader":
			max_shield = 80.0
			max_hull = 160.0 * CosmosHull.SIZE.get(hk, 1.0) * 0.5
			speed_max = 120.0
			label = "%s trader" % Galaxy.EMPIRES.get(empire, {}).get("short", "Independent")
		"patrol":
			max_shield = 120.0
			max_hull = 140.0
			speed_max = 200.0
			label = "%s patrol" % Galaxy.EMPIRES.get(empire, {}).get("short", "System")
		"pirate":
			max_shield = 50.0
			max_hull = 90.0
			speed_max = 210.0
			label = "Pirate raider"
	shield = max_shield
	hull = max_hull
	name = label.replace(" ", "_")
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = preload("res://shaders/cosmos/glow.gdshader")
		_glow_mat.set_shader_parameter("tint", Color(0.5, 0.75, 1.0))
		_glow_mat.set_shader_parameter("intensity", 1.6)
	for nz in nozzles:
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * reach * 0.3
		g.mesh = q
		g.material_override = _glow_mat
		g.position = nz
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_glows.append(g)
	_orbit = 1.0 if _rng.randf() < 0.5 else -1.0


func up() -> Vector3:
	return global_basis.y


func hurt(dmg: float, _from: Vector3) -> void:
	if dead:
		return
	_since_hit = 0.0
	var s := minf(shield, dmg)
	shield -= s
	hull -= dmg - s
	if not hostile and cosmos:
		hostile = true   # (fired on: it fights back, or flees - traders run)
	if hull <= 0.0:
		dead = true
		if cosmos:
			cosmos.ship_destroyed(self)
		CosmosBoom.at(cosmos, global_position, reach)
		queue_free()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if dead or cosmos == null:
		return
	_since_hit += delta
	if _since_hit > 4.0:
		shield = minf(max_shield, shield + 10.0 * delta)
	var player: Node3D = cosmos.ship
	var want := -global_basis.z
	var spd := speed_max * 0.6
	if hostile and kind != "trader" and player and cosmos.walker == null and player.state == "fly":
		var to: Vector3 = player.global_position - global_position
		var d := to.length()
		if d > 900.0:
			want = to / d
			spd = speed_max * (4.0 if d > 4000.0 else 1.0)   # (closing in fast from afar)
		else:
			# Circle: aim at the player but slide round it.
			var side := to.cross(global_basis.y).normalized() * _orbit
			want = (to / d + side * (0.6 if d < 350.0 else 0.2)).normalized()
			spd = speed_max * (0.7 if d < 350.0 else 1.0)
		_fire -= delta
		if _fire <= 0.0 and d < 1600.0 and (-global_basis.z).angle_to(to) < 0.18:
			_fire = LASER_EVERY * _rng.randf_range(0.8, 1.4)
			var lead: Vector3 = player.global_position + player.velocity * (d / CosmosBolt.SPACE_SPEED)
			var spread := 0.006
			var aim := (lead - global_position).normalized() + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))
			CosmosBolt.fire(cosmos, global_position - global_basis.z * reach * 0.6, aim, "enemy", 9.0, true)
	elif kind == "trader" and dest:
		var to := dest.global_position - global_position
		var d: float = to.length() - cosmos.radius_of(dest) - 400.0
		want = to.normalized()
		if hostile and player:
			want = (global_position - player.global_position).normalized()   # (fired on: it runs)
			spd = speed_max * 1.6
		elif d > 6000.0:
			spd = clampf(d * 0.4, speed_max, 30000.0)   # (its own Hyperion drive)
		elif d < 200.0:
			cosmos.trader_arrived(self)
			return
		else:
			spd = speed_max
	elif home:
		var to := home.global_position - global_position
		var d := to.length()
		var r: float = cosmos.radius_of(home) + 900.0
		var side := to.cross(Vector3.UP).normalized()
		want = (to.normalized() * clampf((d - r) / 400.0, -1.0, 1.0) + side * 0.8).normalized()
		spd = speed_max * 0.5
	# Turn toward `want`, fly along the nose.
	var f := -global_basis.z
	var ang := f.angle_to(want)
	if ang > 0.001:
		var axis := f.cross(want)
		if axis.length() < 0.001:
			axis = global_basis.y
		global_basis = (Basis(axis.normalized(), minf(ang, TURN * delta)) * global_basis).orthonormalized()
	velocity = velocity.move_toward(-global_basis.z * spd, maxf(spd, 80.0) * 1.2 * delta)
	global_position += velocity * delta
	cosmos.bump_npc(self)
