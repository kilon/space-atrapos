class_name OrbitRings
extends Node2D
## Faint dashed orbit lines of the system's planets (and moons).

var bodies: Array = []


var _moons := {}   # moon body -> its ring (a node riding its planet)


## The planets' rings drawn once (they're round the star: they never move);
## each moon's ring is a node of its own moved along with its planet - no
## redrawing (256-segment arcs drawn again as the planets orbited cost up to
## half a millisecond a frame).
func _process(_delta: float) -> void:
	for b in bodies:
		if not is_instance_valid(b) or b.parent_body == null:
			continue
		var ring: Node2D = _moons.get(b)
		if ring == null:
			ring = MoonRing.new()
			ring.radius = b.orbit
			add_child(ring)
			_moons[b] = ring
		if is_instance_valid(b.parent_body):
			ring.position = b.parent_body.position


func _draw() -> void:
	for b in bodies:
		if not is_instance_valid(b) or b.parent_body != null:
			continue
		draw_arc(Vector2.ZERO, b.orbit, 0, TAU, 256, Color(0.55, 0.75, 1.0, 0.07), 2.0, true)


class MoonRing extends Node2D:
	var radius := 100.0

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0, TAU, 96, Color(0.55, 0.75, 1.0, 0.07), 2.0, true)
