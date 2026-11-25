class_name Projectile
extends Node2D
## A weapon bolt. Flies straight (or homes in, for missiles) and damages the
## first node of `target_group` it gets close enough to (nodes need
## hit_radius, is_alive(), take_damage()).

var velocity := Vector2.ZERO
var damage := 10.0
var target_group: StringName
var color := Color.WHITE
var life := 1.2
var style := "laser"          # "laser", "plasma" or "missile"
var homing_target: Node2D = null
var shooter: Node2D = null    # who fired it (so the victim can fight back)
var ignore: Node2D = null     # a target it missed (Accuracy): it flies by, never touching it
var turn_rate := 3.5          # radians/second, for homing
var _time := 0.0


## Creates a bolt in the FX layer (the node in group "fx_layer").
static func fire(tree: SceneTree, from: Vector2, direction: Vector2, speed: float,
		dmg: float, group: StringName, col: Color, kind := "laser", from_ship: Node2D = null) -> Projectile:
	var p := Projectile.new()
	p.global_position = from
	p.velocity = direction.normalized() * speed
	p.rotation = direction.angle()
	p.damage = dmg
	p.target_group = group
	p.color = col
	p.style = kind
	p.shooter = from_ship
	if kind == "missile":
		p.life = 3.0
	var layer := tree.get_first_node_in_group("fx_layer")
	if layer == null:
		layer = tree.current_scene
	layer.add_child(p)
	return p


## Moves every rendered frame (smooth at any refresh rate). A long frame is
## split into sub-steps of at most 1/60 s so fast bolts can't skip past a
## target between checks.
func _process(delta: float) -> void:
	var steps := maxi(1, ceili(delta * 60.0))
	for i in steps:
		if _step(delta / steps):
			return
	if style == "missile":
		queue_redraw()  # flickering exhaust


## Advances by dt; returns true if the projectile is gone (hit or expired).
func _step(dt: float) -> bool:
	_time += dt
	if homing_target != null and is_instance_valid(homing_target) and homing_target.is_alive():
		var want := global_position.direction_to(homing_target.global_position).angle()
		var ang := rotate_toward(velocity.angle(), want, turn_rate * dt)
		velocity = Vector2.from_angle(ang) * velocity.length()
		rotation = ang

	global_position += velocity * dt
	life -= dt
	if life <= 0.0:
		queue_free()
		return true

	var src_empire = shooter.get("empire") if is_instance_valid(shooter) else null
	for target in get_tree().get_nodes_in_group(target_group):
		if target == shooter or target == ignore or (src_empire != null and src_empire != "" and target.get("empire") == src_empire):
			continue   # no hitting yourself or your own empire's ships
		if target.is_alive() and global_position.distance_to(target.global_position) < target.hit_radius:
			var src: Node2D = shooter if is_instance_valid(shooter) else null
			target.take_damage(damage, global_position, src, {"laser": "energy", "plasma": "heat", "missile": "explosive"}.get(style, "energy"))
			if style == "laser":
				Effects.spark(global_position, color)
			else:
				Effects.explosion(global_position, 0.45)
			queue_free()
			return true
	return false


func _draw() -> void:
	match style:
		"plasma":
			draw_circle(Vector2.ZERO, 11.0, Color(color, 0.18))
			draw_circle(Vector2.ZERO, 7.0, Color(color, 0.5))
			draw_circle(Vector2.ZERO, 4.0, color.lightened(0.7))
			draw_line(Vector2(-22, 0), Vector2(-6, 0), Color(color, 0.3), 6.0, true)
		"missile":
			var flame := 10.0 + randf() * 8.0
			draw_line(Vector2(-8 - flame, 0), Vector2(-8, 0), Color(1.0, 0.6, 0.2, 0.7), 5.0, true)
			draw_line(Vector2(-8 - flame * 0.5, 0), Vector2(-8, 0), Color(1.0, 0.95, 0.6), 2.5, true)
			draw_rect(Rect2(-8, -2.5, 14, 5), Color(0.88, 0.9, 0.92))
			draw_colored_polygon(PackedVector2Array([Vector2(6, -2.5), Vector2(11, 0), Vector2(6, 2.5)]), Color(0.9, 0.25, 0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -2.5), Vector2(-11, -6), Vector2(-4, -2.5)]), Color(0.9, 0.25, 0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(-8, 2.5), Vector2(-11, 6), Vector2(-4, 2.5)]), Color(0.9, 0.25, 0.2))
		_:
			draw_line(Vector2(-18, 0), Vector2(4, 0), Color(color, 0.35), 7.0, true)
			draw_line(Vector2(-14, 0), Vector2(2, 0), Color(color.lightened(0.6), 1.0), 2.5, true)
