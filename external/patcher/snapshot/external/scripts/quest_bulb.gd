class_name QuestBulb
extends Node2D
## The quest-giver sign: a targeting mark floating above someone (or
## something) that has a quest for you - on the planets above a quest giver's
## head (SurfaceProps.QuestGiver, any citizen with quest_giver set), in space
## above a station with missions to take. A hollow yellow triangle pointing
## down at them, drawn in thin bright lines over a soft glow, a bright point at
## each corner; it bobs gently and its lines breathe. `lit` false hides it.
## Drawn above its neighbours (z_index). (The class keeps its old name: it
## was a light bulb.)

const COLOR := Color(1.0, 0.82, 0.12)      # quest yellow
const CORE := Color(1.0, 0.97, 0.75)       # the lines' hot centre

## On-screen size: the triangle's half-width (px).
var radius := 11.0
var lit := true:
	set(v):
		lit = v
		visible = v
var _t := 0.0


func _ready() -> void:
	z_index = 30
	z_as_relative = false
	_t = randf() * TAU


func _process(delta: float) -> void:
	if visible:
		_t += delta
		if UI.redraw_due(self):
			queue_redraw()


func _draw() -> void:
	var r := radius * 1.65
	var bob := sin(_t * 2.2) * radius * 0.25
	var pulse := 0.5 + 0.5 * sin(_t * 3.4)
	var c := Vector2(0, bob)
	# Pointing down: two corners above, the tip below (towards whoever it marks).
	var pts := PackedVector2Array([c + Vector2(-r, -r * 0.62), c + Vector2(r, -r * 0.62), c + Vector2(0, r * 1.1)])
	var loop := PackedVector2Array([pts[0], pts[1], pts[2], pts[0]])
	var w := maxf(1.4, r * 0.09)
	# Glow under the lines, then the line and its hot core - empty inside.
	draw_polyline(loop, Color(COLOR, 0.16 + 0.12 * pulse), w * 4.0, true)
	draw_polyline(loop, Color(COLOR, 0.85), w * 1.6, true)
	draw_polyline(loop, Color(CORE, 0.6 + 0.4 * pulse), w * 0.6, true)
	# A bright point at each corner, flaring on the pulse.
	for p in pts:
		draw_circle(p, w * (2.2 + 1.4 * pulse), Color(COLOR, 0.25))
		draw_circle(p, w * 1.3, COLOR)
		draw_circle(p, w * 0.6, CORE)
