class_name OrbitBody
extends Node2D
## A planet orbiting the system's star (positions follow Galaxy.time).
## Group "planet_bodies": the LAND tags, maps and landing use it.

var planet_id := ""         # Planets.PLANETS id for landable home planets ("" otherwise)
var title := ""
var desc := ""
var landable := false
var radius := 300.0          # on-screen disc radius
var orbit := 3000.0
var phase := 0.0
var parent_body: OrbitBody   # moons orbit a planet instead of the star
var data := {}               # Galaxy planet entry (for position)
var spec := {}               # its PlanetGen parameters (look, map colours)
var planet: Control          # the PlanetGen node (lit from the star)


func _ready() -> void:
	add_to_group("planet_bodies")
	z_index = -15


## Orbits are slow and stately: a planet takes about an hour of play to go
## round (moons about 15 minutes).
const ORBIT_SLOWDOWN := 4.0


func _process(_delta: float) -> void:
	var period: float = 900.0 * pow(orbit / 3000.0, 1.5) * ORBIT_SLOWDOWN
	if parent_body:
		period = 240.0 * ORBIT_SLOWDOWN
	var p := Vector2.from_angle(phase + Galaxy.time * TAU / period) * orbit
	position = (parent_body.position if parent_body else Vector2.ZERO) + p
	# The star is at the system's centre: light the side facing it (set again
	# only when it has turned a little - a shader parameter every frame for
	# every planet added up).
	if planet:
		var a := (-position).angle()
		if absf(angle_difference(a, _lit_at)) > 0.002:
			_lit_at = a
			PlanetGen.set_light(planet, -position)


var _lit_at := 99.0
