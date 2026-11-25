class_name PlasmaBouncer
extends Node2D
## The Bouncer Plasma weapon (Items.WEAPONS "bouncer"): a ball of plasma that
## flies at its target, hits it (heat damage) and bounces on to the nearest
## enemy it hasn't hit yet (when it has hit them all, back to the nearest -
## never straight back to the one it just left: between two it ping-pongs) -
## up to `bounces` hits, each its full damage. When it's done
## (its last bounce, or no enemy left in reach) it bursts into a PlasmaWeb
## that ties every ship it hit together for `web_time` seconds - an enemy's
## (NPCs carry it too: Enemy.bouncer) ties you to the ship that fired it and
## up to two of its wingmen - slowed to
## `web_slow` of their speed, none able to drift further than the web's
## reach from the others (Enemy.web: they're pulled back in).
##   PlasmaBouncer.fire(tree, ship, target, damage, Items.WEAPONS["bouncer"])

const HIT_REACH := 14.0

var w: Dictionary
var damage := 20.0
var shooter: Node2D
var target: Node2D
var _last: Node2D
var _hits := 0
var _hit: Array = []          # every ship it hit (the web's members)
var _speed := 700.0
var _vel := Vector2.ZERO
var _t := 0.0
var _trail: Array = []        # recent positions (the glow behind it)


static func fire(tree: SceneTree, from: Node2D, first: Node2D, dmg: float, weapon: Dictionary) -> PlasmaBouncer:
	var b := PlasmaBouncer.new()
	b.w = weapon
	b.damage = dmg
	b.shooter = from
	b.target = first
	b._speed = float(weapon.get("speed", 700.0))
	var host: Node = tree.get_first_node_in_group("fx_layer")
	if host == null:
		host = from.get_parent()
	host.add_child(b)
	b.global_position = from.global_position
	b._vel = from.global_position.direction_to(first.global_position) * b._speed
	Sfx.play_world("space/plasma", from.global_position, -2.0, 0.1)
	return b


func _ready() -> void:
	z_index = 4


func _process(delta: float) -> void:
	_t += delta
	if _t > 8.0:   # (lost: burst where it is)
		_burst()
		return
	if not _alive(target):
		target = _next_target()
		if target == null:
			_burst()
			return
	# Homing hard on its target (a ball of plasma, not a bolt).
	var to := target.global_position - global_position
	_vel = _vel.lerp(to.normalized() * _speed, minf(1.0, delta * 9.0))
	global_position += _vel * delta
	_trail.push_front(global_position)
	if _trail.size() > 10:
		_trail.pop_back()
	if to.length() < float(target.get("hit_radius") if target.get("hit_radius") != null else 30.0) + HIT_REACH:
		_strike(target)
	if UI.redraw_due(self):
		queue_redraw()


func _strike(n: Node2D) -> void:
	if n.has_method("take_damage"):
		n.take_damage(damage, global_position, shooter if is_instance_valid(shooter) else null, "heat")
	Effects.debris(global_position, Color(0.6, 1.0, 0.7), 0.4)
	Sfx.play_world("space/plasma", global_position, -6.0, 0.25)
	_hits += 1
	if not n in _hit:
		_hit.append(n)
	_last = n
	if _hits >= int(w.get("bounces", 6)):
		_burst()
		return
	target = _next_target()
	if target == null:
		_burst()


## The next to bounce to: the nearest enemy within reach it hasn't hit yet;
## every one near hit already - the nearest but the one it just left.
func _next_target() -> Node2D:
	if not is_instance_valid(shooter):
		return null   # (whoever fired it is gone - a jump, a death: it bounces no more)
	var fresh: Node2D = null
	var fresh_d: float = float(w.get("leap", 460.0))
	var again: Node2D = null
	var again_d: float = fresh_d
	var from := global_position
	for g in [&"enemies", &"neutrals", &"player"]:
		for n in get_tree().get_nodes_in_group(g):
			if n == _last or n == shooter or not _alive(n) or not ChainLightning._foe_of(shooter, n) or n.get("untouchable") == true:
				continue
			var d: float = n.global_position.distance_to(from)
			if not n in _hit and d < fresh_d:
				fresh = n
				fresh_d = d
			elif n in _hit and d < again_d:
				again = n
				again_d = d
	return fresh if fresh != null else again


static func _alive(n) -> bool:
	return is_instance_valid(n) and n is Node2D and (not n.has_method("is_alive") or n.is_alive())


## Done bouncing: the ships it hit are webbed together.
func _burst() -> void:
	var members := _hit.filter(func(n): return _alive(n))
	# An enemy's ball: what it hit (you) is webbed to the ship that fired it
	# and its wingmen nearby - tethered to them, slowed.
	if not members.is_empty() and _alive(shooter) and not shooter.is_in_group("player"):
		members.append(shooter)
		var mates := []
		var e = shooter.get("empire")
		for n in get_tree().get_nodes_in_group(shooter.faction_group() if shooter.has_method("faction_group") else &"enemies"):
			if n != shooter and _alive(n) and n.get("empire") == e and n.global_position.distance_to(shooter.global_position) < float(w.get("leap", 460.0)):
				mates.append(n)
		mates.sort_custom(func(a, b): return a.global_position.distance_to(shooter.global_position) < b.global_position.distance_to(shooter.global_position))
		members += mates.slice(0, 2)
		for n in members:
			if n.is_in_group("player") and n.has_signal("message"):
				n.message.emit("Webbed by plasma - you're tied to their ships!")
	if not members.is_empty():
		PlasmaWeb.weave(get_parent(), members, w)
	Effects.explosion(global_position, 0.5, "space/plasma")
	queue_free()


func _draw() -> void:
	var disc := ExhaustTrail.disc()
	var col: Color = w.get("color", Color(0.45, 1.0, 0.6))
	for i in _trail.size():
		var p: Vector2 = _trail[i] - global_position
		var r := 14.0 * (1.0 - i / 10.0)
		draw_texture_rect(disc, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, 0.25 * (1.0 - i / 10.0)))
	var pulse := 1.0 + 0.15 * sin(_t * 30.0)
	draw_texture_rect(disc, Rect2(-Vector2(26, 26) * pulse, Vector2(52, 52) * pulse), false, Color(col, 0.3))
	draw_texture_rect(disc, Rect2(-Vector2(13, 13), Vector2(26, 26)), false, Color(col.lightened(0.4), 0.9))
	draw_texture_rect(disc, Rect2(-Vector2(6, 6), Vector2(12, 12)), false, Color(1, 1, 1, 0.95))


# --- The web ------------------------------------------------------------------------------------

## The plasma web: the ships a Bouncer hit, tied together - slowed, and kept
## within `reach` of the web's centre (pulled back if they pull away). Its
## strands glow between each ship and the centre. Gone after `web_time`.
class PlasmaWeb extends Node2D:
	var members: Array = []
	var life := 6.0
	var slow := 0.45
	var reach := 260.0
	var color := Color(0.45, 1.0, 0.6)
	var _t := 0.0

	static func weave(host: Node, ships: Array, weapon: Dictionary) -> PlasmaWeb:
		var web := PlasmaWeb.new()
		web.members = ships.duplicate()
		web.life = float(weapon.get("web_time", 6.0))
		web.slow = float(weapon.get("web_slow", 0.45))
		web.reach = float(weapon.get("tether", 220.0)) + 30.0 * ships.size()
		web.color = weapon.get("color", web.color)
		host.add_child(web)
		for s in ships:
			if is_instance_valid(s):
				if s.get("web") != null and is_instance_valid(s.web) and s.web != web:
					s.web.members.erase(s)   # (in one web at a time: the newest)
				s.set("web", web)
		Sfx.play_world("space/scan_pulse", web.centre(), -4.0, 0.1)
		return web

	func _ready() -> void:
		z_index = 3

	## The web's centre: the middle of its live ships (but `without`: a ship
	## is held to the others, not to a centre it drags along).
	func centre(without: Node2D = null) -> Vector2:
		var c := Vector2.ZERO
		var n := 0
		for s in members:
			if PlasmaBouncer._alive(s) and s != without:
				c += s.global_position
				n += 1
		return c / maxf(1.0, n)

	## What a webbed ship's velocity becomes (Enemy calls it every frame):
	## slowed, and turned back toward the centre when it's at the edge.
	func constrain(s: Node2D, v: Vector2) -> Vector2:
		var c := centre(s) if members.size() > 1 else centre()
		var off := s.global_position - c
		if off.length() > reach:
			s.global_position = c + off.normalized() * reach   # (it can't pull further away)
			var out := v.dot(off.normalized())
			if out > 0.0:
				v -= off.normalized() * out
		return v.limit_length(maxf(40.0, float(s.get("max_speed") if s.get("max_speed") != null else 200.0) * slow))

	func _process(delta: float) -> void:
		_t += delta
		members = members.filter(func(s): return PlasmaBouncer._alive(s))
		if _t >= life or members.size() == 0:
			for s in members:
				if s.get("web") == self:
					s.set("web", null)
			queue_free()
			return
		if UI.redraw_due(self):
			queue_redraw()

	func _draw() -> void:
		var c := centre()
		var fade := clampf((life - _t) / 0.8, 0.0, 1.0)
		var origin := global_position
		for s in members:
			var a: Vector2 = c - origin
			var b: Vector2 = s.global_position - origin
			var pts := PackedVector2Array()
			var side := (b - a).orthogonal().normalized()
			for k in 13:
				var u := k / 12.0
				pts.append(a.lerp(b, u) + side * sin(u * TAU * 1.5 + _t * 7.0) * 10.0 * sin(u * PI))
			draw_polyline(pts, Color(color, 0.25 * fade), 8.0)
			draw_polyline(pts, Color(color.lightened(0.4), 0.85 * fade), 2.0)
			draw_circle(b, 10.0, Color(color, 0.35 * fade))
		draw_circle(c - origin, 9.0 + 2.0 * sin(_t * 9.0), Color(color.lightened(0.5), 0.9 * fade))
		draw_arc(c - origin, reach, 0, TAU, 48, Color(color, 0.12 * fade), 1.5, true)
