class_name ChainLightning
extends Node2D
## The Electro weapon's lightning (Items.WEAPONS "electro"): a bolt that
## strikes its target at once and leaps on to the nearest other ship of the
## same side within `leap`, up to `chain` more, each hit `falloff` of the
## last. Electric damage (Gear: "electric"); each ship hit may be stunned for
## a moment (stun(): it drifts, its guns silent). The player's ship and NPC
## ships fit it alike (an NPC with `electro` fires it instead of bolts).
##
## The node itself is the flash: jagged lines between the hits, re-jagged as
## it flickers, gone in LIFE seconds. Cheap - a handful of polylines.

const LIFE := 0.3

var _points: PackedVector2Array      # the hits, in order (global)
var _t := 0.0
var _color := Color(0.6, 0.8, 1.0)
var _rng := RandomNumberGenerator.new()


## Strikes `first` from `from` (the firer, null for a hazard): returns the
## ships hit. `w`: the weapon's stats (Items.WEAPONS["electro"]), `damage`
## its first hit (tech and modules applied by the firer).
static func strike(tree: SceneTree, from: Node2D, first: Node2D, damage: float, w: Dictionary) -> Array:
	if not is_instance_valid(first):
		return []
	var group: StringName = first.faction_group() if first.has_method("faction_group") else &"enemies"
	if first.is_in_group("player"):
		group = &"player"
	var hit: Array = [first]
	var pts := PackedVector2Array([from.global_position if is_instance_valid(from) else first.global_position, first.global_position])
	var d := damage
	_hit(first, d, from, w)
	var at: Node2D = first
	for i in int(w.get("chain", 3)):
		var best: Node2D = null
		var best_d: float = w.get("leap", 420.0)
		for n in tree.get_nodes_in_group(group):
			if n in hit or not is_instance_valid(n) or not n is Node2D or (n.has_method("is_alive") and not n.is_alive()):
				continue
			if n.get("untouchable") == true or not _foe_of(from, n):
				continue
			var dd: float = n.global_position.distance_to(at.global_position)
			if dd < best_d:
				best = n
				best_d = dd
		if best == null:
			break
		d *= float(w.get("falloff", 0.75))
		_hit(best, d, from, w)
		hit.append(best)
		pts.append(best.global_position)
		at = best
	var fx := ChainLightning.new()
	fx._points = pts
	fx._color = w.get("color", Color(0.6, 0.8, 1.0))
	var host: Node = tree.get_first_node_in_group("fx_layer")
	if host == null:
		host = from.get_parent() if is_instance_valid(from) else first.get_parent()
	host.add_child(fx)
	Sfx.play_world("space/hazard_zap", first.global_position, -2.0, 0.15)
	return hit


## Would `from`'s lightning leap to `n`? Only to its foes: from you, to
## hostile ships (not the neutrals minding their business); from an NPC, not
## to its own empire's ships.
static func _foe_of(from: Node2D, n: Node2D) -> bool:
	if not is_instance_valid(from):
		return true
	if from.is_in_group("player"):
		return not (n.has_method("is_neutral") and n.is_neutral() and not n.is_hostile_to_player())
	var fe = from.get("empire")
	var ne = n.get("empire")
	if fe is String and ne is String and fe != "" and fe == ne:
		return false
	return true


static func _hit(n: Node2D, dmg: float, from: Node2D, w: Dictionary) -> void:
	if n.has_method("take_damage"):
		n.take_damage(dmg, from.global_position if is_instance_valid(from) else n.global_position, from if is_instance_valid(from) else null, "electric")
	if is_instance_valid(n) and n.has_method("stun") and randf() < float(w.get("stun", 0.25)):
		n.stun(float(w.get("stun_time", 1.5)))


func _ready() -> void:
	z_index = 5
	_rng.randomize()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var a := 1.0 - _t / LIFE
	for i in _points.size() - 1:
		var p0 := _points[i]
		var p1 := _points[i + 1]
		var line := PackedVector2Array([p0])
		var n := maxi(3, int(p0.distance_to(p1) / 45.0))
		var side := (p1 - p0).orthogonal().normalized()
		for k in range(1, n):
			line.append(p0.lerp(p1, float(k) / n) + side * _rng.randf_range(-18.0, 18.0))
		line.append(p1)
		draw_polyline(line, Color(_color, 0.35 * a), 9.0)
		draw_polyline(line, Color(_color.lightened(0.5), 0.9 * a), 3.0)
		draw_polyline(line, Color(1, 1, 1, a), 1.2)
		draw_circle(p1, 14.0 * a, Color(_color, 0.5 * a))
