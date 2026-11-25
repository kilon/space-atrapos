class_name ProjectionArray
extends Node2D
## The Projection Array (equipment, a toolbar system): it projects two
## illusions of your ship that fly in formation beside you - the same hull,
## heading and engines, nothing to tell them apart. Enemies can't tell either:
## every ship attacking you picks one of the three at random, and so does one
## that turns on you while they're up (Enemy._choose_target). An illusion is
## gone the moment anything hits it (a flicker and it's nothing). Every
## SHUFFLE seconds your ship swaps places with one of them - a flash on all
## three hides it - so you can't be followed by where you were. They last
## LIFE seconds at most.
##   ProjectionArray.project(ship)

const LIFE := 15.0
const SHUFFLE := 4.0
const SPACING := 170.0

var ship: Node2D
var decoys: Array = []
var _t := 0.0
var _shuffle_t := SHUFFLE


static func project(ship: Node2D) -> ProjectionArray:
	for old in ship.get_tree().get_nodes_in_group("projection_arrays"):
		old.end()   # (a fresh pair replaces the old)
	var pa := ProjectionArray.new()
	pa.ship = ship
	ship.get_parent().add_child(pa)
	for side in [-1.0, 1.0]:
		var d := Decoy.new()
		d.ship = ship
		d.offset = Vector2(side * SPACING, 40.0)
		pa.add_child(d)
		pa.decoys.append(d)
		d.global_position = ship.global_position + d.offset.rotated(ship.rotation)
	# Whoever was shooting at you now takes its pick of the three.
	for e in ship.get_tree().get_nodes_in_group("enemies") + ship.get_tree().get_nodes_in_group("neutrals"):
		if e.get("_target") == ship:
			e._target = pa.pick(ship)
	pa._flash_all()
	Sfx.play_world("space/scan_pulse", ship.global_position, -3.0, 0.15)
	GameLog.post("Projection Array: two illusions of your ship fly with you - enemies can't tell which is real.", "good")
	return pa


func _ready() -> void:
	add_to_group("projection_arrays")


## For an enemy about to attack you: you or one of the illusions, at random.
func pick(real: Node2D) -> Node2D:
	var all: Array = [real] + decoys.filter(func(d): return is_instance_valid(d) and d.is_alive())
	return all.pick_random()


func _process(delta: float) -> void:
	_t += delta
	decoys = decoys.filter(func(d): return is_instance_valid(d) and d.is_alive())
	if _t >= LIFE or decoys.is_empty() or not is_instance_valid(ship) or not ship.is_alive():
		end()
		return
	_shuffle_t -= delta
	if _shuffle_t <= 0.0:
		_shuffle_t = SHUFFLE
		_shuffle()


## Your ship and one illusion trade places (each keeps its own motion).
func _shuffle() -> void:
	var live := decoys.filter(func(x): return is_instance_valid(x) and x.is_alive())
	if live.is_empty():
		return
	var d: Decoy = live.pick_random()
	var here: Vector2 = ship.global_position
	var there: Vector2 = d.global_position
	ship.global_position = there
	d.global_position = here
	# Back into formation (one each side): they glide to their places.
	var local := (here - there).rotated(-ship.rotation)
	d.offset = Vector2(signf(local.x if absf(local.x) > 1.0 else 1.0) * SPACING, 40.0)
	for o in live:
		if o != d:
			o.offset = Vector2(-d.offset.x, 40.0)
	var cam: Camera2D = ship.get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()   # (the view stays on you)
	_flash_all()


func _flash_all() -> void:
	for p in [ship] + decoys:
		if is_instance_valid(p):
			var ring := FlashRing.new()
			p.get_parent().add_child(ring)
			ring.global_position = p.global_position


## Gone: the illusions fade out.
func end() -> void:
	for d in decoys:
		if is_instance_valid(d):
			d.vanish()
	queue_free()


## A flash round each ship as the illusions appear or shuffle.
class FlashRing extends Node2D:
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.35:
			queue_free()
		queue_redraw()
	func _draw() -> void:
		var k := _t / 0.35
		draw_arc(Vector2.ZERO, 40.0 + 90.0 * k, 0, TAU, 40, Color(0.7, 0.9, 1.0, 0.7 * (1.0 - k)), 3.0, true)
		draw_circle(Vector2.ZERO, 60.0 * (1.0 - k), Color(0.8, 0.95, 1.0, 0.25 * (1.0 - k)))


## An illusion: your ship's look, flying where you fly (its offset beside you,
## turned with you). Something enemies aim at (group "player_decoys"); hit,
## it's gone.
class Decoy extends Node2D:
	var ship: Node2D
	var offset := Vector2.ZERO
	var hit_radius := 40.0
	var velocity := Vector2.ZERO
	var display_name := "your ship"
	# (what its engine trail reads - your ship's, mirrored: ExhaustTrail)
	var engine_offset := Vector2.ZERO
	var thrust := 0.0
	var boost_time := 0.0
	var _alive := true
	var _sprite: Sprite2D
	var _fade := 1.0

	func _ready() -> void:
		add_to_group("player_decoys")
		z_index = ship.z_index
		var src: Sprite2D = ship.get("sprite")
		_sprite = Sprite2D.new()
		if src:
			_sprite.texture = src.texture
			_sprite.scale = src.scale
			_sprite.offset = src.offset
			_sprite.material = src.material
		add_child(_sprite)
		# The same engine trail as yours.
		if ship.get("engine_offset") != null:
			engine_offset = ship.engine_offset
			ExhaustTrail.attach(self, "blue", 116.0)

	func is_alive() -> bool:
		return _alive

	func faction_group() -> StringName:
		return &"player_decoys"

	func is_neutral() -> bool:
		return false

	func take_damage(_amount: float, _from: Vector2, _attacker: Node2D = null, _dtype := "") -> void:
		vanish()

	func vanish() -> void:
		if not _alive:
			return
		_alive = false
		remove_from_group("player_decoys")
		Sfx.play_world("space/scan_pulse", global_position, -8.0, 0.3)

	func _process(delta: float) -> void:
		if not _alive:
			_fade -= delta * 4.0
			modulate = Color(0.7, 0.9, 1.0, maxf(0.0, _fade) * (0.5 + 0.5 * sin(_fade * 60.0)))
			if _fade <= 0.0:
				queue_free()
			return
		if not is_instance_valid(ship):
			vanish()
			return
		var to: Vector2 = ship.global_position + offset.rotated(ship.rotation)
		velocity = ship.velocity
		global_position = global_position.lerp(to, minf(1.0, delta * 6.0))
		rotation = ship.rotation
		thrust = float(ship.get("thrust")) if ship.get("thrust") != null else 0.0
		boost_time = float(ship.get("boost_time")) if ship.get("boost_time") != null else 0.0
		if _sprite and ship.get("sprite"):
			_sprite.rotation = ship.sprite.rotation
			_sprite.modulate = ship.sprite.modulate
