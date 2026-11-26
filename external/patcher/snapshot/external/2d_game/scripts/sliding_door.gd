extends Node2D
## A sliding door in a building's doorway: two panels that slide apart into
## the wall when you come close and close again behind you, with a glowing
## seam and a status light (red closed, green open). Drawn in the wall's
## plane: ground line `start` -> `start + dir`, the opening between
## SurfaceTiles.DOOR.x and .y along it, rising `height` px.
## It opens for you within REACH (or earlier when your path goes through it),
## for citizens within NPC_REACH, and you hear it: Sfx "surface/door_open"
## and "surface/door_close" (tools/sfx_surface.py) as it starts to move.

var start := Vector2.ZERO
var dir := Vector2(64, 32)
var height := 76.0
var panel := Color(0.55, 0.6, 0.68)
var trim := Color(0.9, 0.8, 0.5)
var glow := Color(0.35, 0.9, 1.0)
var wall: Sprite2D           # the wall tile it sits in (fades together)
var surface: Node            # for the pilot's position
var open := 0.0              # 0 closed .. 1 open
const REACH := 95.0
const NPC_REACH := 55.0
## How far ahead your path through the doorway opens it (so you don't wait).
const ROUTE_REACH := 150.0
## Opening / closing speed (fraction of the way per second).
const SPEED := 3.2
const VOLUME_DB := -4.0
var _held := 0.0             # kept open this long (someone's route goes through)
var last_sound: AudioStreamPlayer2D   # the last open / close sound played
var _going := 0.0            # where it was last heading (1 open, 0 closed): a sound on each change


## Someone is about to walk through: open now and stay open a moment.
func request_open() -> void:
	_held = 0.6


var _skip := randi() % 8
var _skipped := 0.0

func _process(delta: float) -> void:
	if surface == null or surface.pilot == null:
		return
	# Off screen and still: every 8th frame (the time in between added up) -
	# it only has to be open by the time someone's at it.
	var vr = surface.get("view_rect")
	if vr is Rect2 and vr.has_area() and not vr.has_point(start) and open == _going and _held <= 0.0:
		_skipped += delta
		_skip = (_skip + 1) % 8
		if _skip != 0:
			return
		delta = _skipped
	_skipped = 0.0
	_held = maxf(0.0, _held - delta)
	var mid := start + dir * 0.5 + Vector2(0, -10)
	var near: bool = _held > 0.0 or surface.pilot.position.distance_to(mid) < REACH or _route_through()
	if not near:
		for a in surface.npcs:
			if is_instance_valid(a) and a.position.distance_to(mid) < NPC_REACH:
				near = true
				break
	var target := 1.0 if near else 0.0
	if target != _going:
		_going = target
		last_sound = Sfx.play_at("surface/door_open" if target > 0.5 else "surface/door_close", start + dir * 0.5 - Vector2(0, height * 0.4),
			get_parent(), VOLUME_DB)
	if open != target:
		open = move_toward(open, target, delta * SPEED)
		queue_redraw()
	if wall:
		modulate.a = wall.modulate.a


## The pilot's route crosses this doorway within the next couple of legs
## (and not too far away): open early so they never have to break stride.
func _route_through() -> bool:
	var pilot = surface.pilot
	if not pilot.moving or pilot.path.is_empty() or pilot.position.distance_to(start + dir * 0.5) > ROUTE_REACH:
		return false
	var a: Vector2 = pilot.position
	for i in mini(2, pilot.path.size()):
		var b: Vector2 = pilot.path[i]
		if Geometry2D.segment_intersects_segment(a, b, start, start + dir) != null:
			return a.distance_to(start + dir * 0.5) < ROUTE_REACH
		a = b
	return false


func _p(t: float, z: float) -> Vector2:
	return start + dir * t - Vector2(0, z) - position


func _draw() -> void:
	var a := SurfaceTiles.DOOR.x
	var b := SurfaceTiles.DOOR.y
	var m := (a + b) * 0.5
	var half := (b - a) * 0.5
	var ease := open * open * (3.0 - 2.0 * open)   # smooth start / stop
	var gap := half * ease
	# Dark interior glimpsed through the opening.
	draw_colored_polygon(PackedVector2Array([_p(a, 0), _p(b, 0), _p(b, height), _p(a, height)]), Color(0.04, 0.05, 0.08, 0.85 * (0.4 + 0.6 * ease)))
	# Left and right panels (each shrinks into the wall as it slides).
	for side in [-1.0, 1.0]:
		var inner: float = m + side * gap
		var outer: float = a if side < 0 else b
		if absf(outer - inner) < 0.004:
			continue
		var t0: float = minf(inner, outer)
		var t1: float = maxf(inner, outer)
		var poly := PackedVector2Array([_p(t0, 0), _p(t1, 0), _p(t1, height), _p(t0, height)])
		var shade := 1.0 if side < 0 else 0.86
		draw_polygon(poly, PackedColorArray([panel.lightened(0.15) * shade, panel * shade, panel.darkened(0.25) * shade, panel.lightened(0.05) * shade]))
		# Horizontal ribs and a trim stripe.
		for k in [0.28, 0.62]:
			draw_line(_p(t0, height * k), _p(t1, height * k), Color(0, 0, 0, 0.35), 2.0)
		draw_line(_p(t0, height * 0.45), _p(t1, height * 0.45), trim, 3.0)
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.05, 0.06, 0.08), 1.5)
		# Glowing leading edge where the panels meet.
		draw_line(_p(inner, 2), _p(inner, height - 2), Color(glow, 0.9 * (1.0 - ease * 0.6)), 2.5)
	# Frame lintel and the status light above the door.
	draw_line(_p(a, height), _p(b, height), trim.darkened(0.2), 4.0)
	var light := Color(0.35, 1.0, 0.5) if open > 0.5 else Color(1.0, 0.3, 0.25)
	var lp := _p(m, height + 8)
	draw_circle(lp, 7.0, Color(light, 0.3))
	draw_circle(lp, 3.5, light)
