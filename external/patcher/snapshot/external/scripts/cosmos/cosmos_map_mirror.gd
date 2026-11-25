class_name CosmosMapMirror
extends Node2D
## The 3D system as the 2D game's HUD radar (Minimap) sees it: unseen 2D
## stand-ins for the star, planets, stations, gates and the ships round you,
## in the radar's groups, at their places in map units (3D / PX_TO_M, the
## system's plane) - kept up a few times a second.

const HZ := 8.0

var cosmos: Node
var _dots := {}                  # 3D node -> its stand-in
var _t := 0.0


class Dot extends Node2D:
	var accent := Color(0.3, 0.85, 1.0)
	var color := Color(1.0, 0.9, 0.6)
	var spec := {}
	var radius := 300.0
	var landable := true
	var parent_body: Node2D = null
	var hostile := false
	var neutral := true
	var targeted := false
	func is_hostile_to_player() -> bool:
		return hostile
	func is_neutral() -> bool:
		return neutral
	func is_alive() -> bool:
		return true


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0 / HZ or cosmos == null or not cosmos.built:
		return
	_t = 0.0
	var seen := {}
	_put(cosmos.star, "star", seen)
	for p in cosmos.planets:
		var d := _put(p, "planet_bodies", seen)
		d.spec = p.shape.look
		d.radius = p.radius / PlanetShape.PX_TO_M
		d.landable = p.shape.kind != "gas"
	for s in cosmos.stations:
		_put(s, "stations", seen).accent = Galaxy.empire_color(str(s.record.get("empire", "")))
	for g in cosmos.gates:
		_put(g, "gates", seen).accent = Galaxy.empire_color(Galaxy.owner_of(g.to))
	for x in cosmos.npc_ships:
		if is_instance_valid(x) and not x.dead:
			var d := _put(x, "enemies" if x.kind == "pirate" else "neutrals", seen)
			d.hostile = x.hostile
			d.neutral = x.kind != "pirate"
			d.targeted = x == cosmos.target
	for k in _dots.keys():
		if not seen.has(k):
			(_dots[k] as Node).queue_free()
			_dots.erase(k)


func _put(n: Node3D, group: String, seen: Dictionary) -> Dot:
	var d: Dot = _dots.get(n)
	if d == null:
		d = Dot.new()
		d.add_to_group(group)
		add_child(d)
		_dots[n] = d
		if n is CosmosStar:
			d.color = (n as CosmosStar).color
	var p: Vector3 = n.global_position + cosmos.origin
	d.global_position = Vector2(p.x, p.z) / PlanetShape.PX_TO_M
	seen[n] = true
	return d
