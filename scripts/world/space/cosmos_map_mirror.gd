class_name CosmosMapMirror
extends Node2D
## The 3D system as the 2D game's maps and missions see it: unseen 2D
## stand-ins for the star, planets, stations, gates and the ships round you,
## in their groups (the Automaton's map pages, missions, discovery), at their places in map units (3D / PX_TO_M, the
## system's plane) - kept up a few times a second.
## And what the maps know: your sensors sweep the system's fog of war round
## your ship as you fly (Galaxy.reveal - the solar map shows what's swept),
## and on a planet you see its ground round you as you walk or fly low
## (Galaxy.reveal_planet - the planet map's fog; the towns you walk into
## marked visited: their plans on the map),
## and on arriving along a planned route (Galaxy.route) your course is set to
## the gate toward its next system (the galaxy map's course planner).

const HZ := 8.0

var cosmos: Node
var _dots := {}                  # 3D node -> its stand-in
var _t := 0.0
var _swept_at := Vector2(INF, INF)   # (where the sensors last swept: map units)
var _aimed := false              # (the route's next gate targeted once, on arrival)


class Dot extends Node2D:
	var accent := Color(0.3, 0.85, 1.0)
	var color := Color(1.0, 0.9, 0.6)
	var spec := {}
	var radius := 300.0
	var landable := true
	var parent_body: Node2D = null
	var planet_id := ""          # (the sector map's: a planet's id, name and orbit)
	var title := ""
	var station_name := ""       # (a station's: missions look up their givers by it)
	var station_id := ""
	var orbit := 0.0
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
	_sweep()
	_sweep_planet()
	_aim_route()
	var seen := {}
	_put(cosmos.star, "star", seen)
	for p in cosmos.planets:
		var d := _put(p, "planet_bodies", seen)
		d.spec = p.shape.look
		d.radius = p.radius / PlanetShape.PX_TO_M
		d.landable = p.shape.kind != "gas"
		d.planet_id = str(p.rec.get("id", ""))
		d.title = str(p.rec.get("name", ""))
		d.orbit = float(p.rec.get("orbit", 0.0))
	for s in cosmos.stations:
		var d := _put(s, "stations", seen)
		d.accent = Galaxy.empire_color(str(s.record.get("empire", "")))
		d.station_name = str(s.record.get("name", ""))
		d.station_id = str(s.record.get("id", ""))
	for g in cosmos.gates:
		_put(g, "gates", seen).accent = Galaxy.empire_color(Galaxy.owner_of(g.to))
	for x in cosmos.npc_ships:
		if is_instance_valid(x) and not x.dead:
			var d := _put(x, "enemies" if x.kind == "pirate" or x.hostile else "neutrals", seen)
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


## Your sensors sweep the fog round you - your ship, or you on foot (each
## time you've moved a little); the worlds within their reach known from then
## on (the solar map shows them wherever their orbits take them), and the world
## you're on always.
func _sweep() -> void:
	var me: Node3D = cosmos.focus() if cosmos.has_method("focus") else cosmos.get("ship")
	if me == null or not is_instance_valid(me):
		return
	var here: Node = cosmos.life_planet() if cosmos.has_method("life_planet") else null
	if here:
		Galaxy.know_planet(str(here.rec.get("id", here.name)))
	var p3: Vector3 = me.global_position + cosmos.origin
	var p := Vector2(p3.x, p3.z) / PlanetShape.PX_TO_M
	if p.distance_to(_swept_at) < Galaxy.SENSOR_RANGE * 0.1:
		return
	_swept_at = p
	Galaxy.reveal(p)
	var sensor := Galaxy.SENSOR_RANGE * PlanetShape.PX_TO_M
	for pl in cosmos.planets:
		if pl.global_position.distance_to(me.global_position) < sensor + pl.radius:
			Galaxy.know_planet(str(pl.rec.get("id", pl.name)))


## The planet's ground seen round you (on foot: SIGHT_FOOT m; flying low:
## wider the higher you are, up to SIGHT_FLY) - each time you've moved a
## little; a town you come into marked visited.
const SIGHT_FOOT := 320.0
const SIGHT_FLY := 2600.0
const FLY_REACH := 5000.0       # (m above the ground: higher sees nothing new of it)
var _planet_at := Vector3(INF, INF, INF)
var _planet_id := ""

func _sweep_planet() -> void:
	var w: Node3D = cosmos.get("walker")
	var pl: CosmosPlanet = null
	var at := Vector3.ZERO
	var reach := SIGHT_FOOT
	if w != null and is_instance_valid(w) and w.get("planet") != null:
		pl = w.planet
		at = w.global_position
	else:
		var sh: Node3D = cosmos.get("ship")
		if sh == null or not is_instance_valid(sh) or not cosmos.has_method("planet_below"):
			return
		pl = cosmos.planet_below(sh.global_position, FLY_REACH)
		if pl == null:
			return
		at = sh.global_position
		var local := pl.to_local(at)
		var alt := local.length() - pl.radius - maxf(pl.shape.surface(local.normalized()), 0.0)
		reach = clampf(SIGHT_FOOT + alt * 0.8, SIGHT_FOOT, SIGHT_FLY)
	var lp := pl.to_local(at)   # (planet-local: what's been seen is its ground's)
	var pid := str(pl.rec.get("id", pl.name))
	if pid == _planet_id and lp.distance_to(_planet_at) < reach * 0.2:
		return
	_planet_id = pid
	_planet_at = lp
	var d := lp.normalized()
	Galaxy.reveal_planet(pid, d, reach / pl.radius)
	for s in pl.towns:
		if reach < SIGHT_FOOT + 400.0 and d.angle_to(s["dir"]) * pl.radius < float(s["r"]) + 40.0:
			Galaxy.visit_town(pid, str(s["name"]))


## Arrived on a route: your course set to the gate toward its next system
## (once - unless you'd already picked a target of your own).
func _aim_route() -> void:
	if _aimed:
		return
	_aimed = true
	var r: Array = Galaxy.route
	if r.size() < 2 or r[0] != Galaxy.current_system or cosmos.get("target") != null:
		return
	for g in cosmos.gates:
		if is_instance_valid(g) and str(g.to) == r[1]:
			cosmos.target = g
			return
