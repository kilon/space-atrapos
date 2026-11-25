class_name CosmosShipProxy
extends Node2D
## The 3D ship as the Automaton sees it (stage 5: the computer's
## pages - inventory, industry, tech, maps, quest - run on the 3D
## ship's terminals): the 2D ship's face (hull, shields, speed, weapons,
## position in map units, a course) over CosmosShip and PlayerData.

signal health_changed(hull: float, max_hull: float, shields: float, max_shields: float)
signal message(text: String)

var cosmos: Node
var sprite: Sprite2D = null
var _last := Vector4(-1, -1, -1, -1)
var course: Array = []
var has_target := false
var weapon_range := 900.0
var evasion := 0.05
var invulnerable := false
var attack_target: Node2D = null
var mining_at := Vector2.ZERO
var mining_auto := false
var mining_hold := 0.0
var mining_last := 0.0
var mining_vein = null
var boost_time := 0.0
var system_cooldown := {}
var _base := {}


func _ready() -> void:
	add_to_group("player")   # (the missions look for "the player" to measure distances)
	sprite = Sprite2D.new()
	sprite.visible = false
	sprite.texture = ProcArt.get_tex("ship_player")
	add_child(sprite)


func _process(_delta: float) -> void:
	if cosmos and is_instance_valid(cosmos) and cosmos.ship:
		var p: Vector3 = cosmos.system_position()
		global_position = Vector2(p.x, p.z) / PlanetShape.PX_TO_M
		rotation = 0.0
		var now := Vector4(hull, max_hull, shields, max_shields)
		if now != _last:
			_last = now
			health_changed.emit(now.x, now.y, now.z, now.w)


var hull: float:
	get: return cosmos.ship.hull if cosmos else 100.0
	set(v): if cosmos: cosmos.ship.hull = v
var max_hull: float:
	get: return cosmos.ship.max_hull if cosmos else 100.0
var shields: float:
	get: return cosmos.ship.shield if cosmos else 100.0
	set(v): if cosmos: cosmos.ship.shield = v
var max_shields: float:
	get: return cosmos.ship.max_shield if cosmos else 100.0
var max_speed: float:
	get: return CosmosShip.MAX_SPEED * (cosmos.ship.speed_k if cosmos else 1.0)


func is_alive() -> bool:
	return true


func accuracy() -> float:
	return 0.85


func cooldown_left(_id: String) -> float:
	return 0.0


func weapon_on(_id: String) -> bool:
	return true


func apply_tech() -> void:
	if cosmos:
		cosmos.ship.apply_upgrades()


func recharge_shields() -> void:
	if cosmos:
		cosmos.ship.shield = cosmos.ship.max_shield


func move_to(_p: Vector2) -> void:
	pass


func set_course_point(_p: Vector2) -> void:
	pass


func add_waypoint(_p: Vector2) -> void:
	pass
