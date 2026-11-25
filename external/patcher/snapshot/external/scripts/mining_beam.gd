class_name MiningBeam
extends Node2D
## A continuous mining beam: a red, glowing, flickering ray from a ship's
## emitter to the spot on a rock it's cutting, with a muzzle flare and sparks
## at the impact. Drawn in world space (top level); the owner calls aim()
## every frame while it mines and off() when it stops.

const RED := Color(1.0, 0.12, 0.08)
const CORE := Color(1.0, 0.78, 0.7)

var color := RED
var width := 1.0          # scale of the beam's thickness (NPC miners: thinner)
var active := false
var from := Vector2.ZERO
var to := Vector2.ZERO
var _t := 0.0
var _power := 0.0         # fades in and out
var _sparks: Array = []   # [pos, vel, life]


func _ready() -> void:
	top_level = true
	z_index = 5
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func aim(a: Vector2, b: Vector2) -> void:
	from = a
	to = b
	active = true


func off() -> void:
	active = false


func _process(delta: float) -> void:
	_t += delta
	_power = move_toward(_power, 1.0 if active else 0.0, delta * (8.0 if active else 5.0))
	if active and randf() < delta * 30.0:
		var n := (from - to).normalized()
		var v := n.rotated(randf_range(-1.2, 1.2)) * randf_range(80.0, 260.0)
		_sparks.append([to, v, randf_range(0.2, 0.45)])
	for s in _sparks:
		s[0] += s[1] * delta
		s[1] *= 1.0 - delta * 3.0
		s[2] -= delta
	_sparks = _sparks.filter(func(s): return s[2] > 0.0)
	if (_power > 0.0 or not _sparks.is_empty()) and UI.redraw_due(self):
		queue_redraw()


func _draw() -> void:
	if _power <= 0.0 and _sparks.is_empty():
		return
	var flick := 0.85 + 0.15 * sin(_t * 47.0) * sin(_t * 31.0 + 1.3)
	var p := _power * flick
	if _power > 0.0:
		# Glow layers, widest and faintest first, then the hot core.
		for g in [[34.0, 0.07], [22.0, 0.14], [13.0, 0.3], [7.0, 0.6], [4.0, 0.85]]:
			draw_line(from, to, Color(color, g[1] * p), g[0] * width * flick)
		draw_line(from, to, Color(CORE, 0.95 * p), 2.2 * width)
		# Muzzle flare and the cutting spot.
		for g in [[14.0, 0.15], [7.0, 0.4], [3.0, 0.9]]:
			draw_circle(from, g[0] * width * p, Color(color.lerp(CORE, 0.3), g[1]))
		var hot := 0.8 + 0.2 * sin(_t * 23.0)
		for g in [[34.0, 0.08], [20.0, 0.18], [10.0, 0.45], [4.5, 1.0]]:
			draw_circle(to, g[0] * width * p * hot, Color(color.lerp(CORE, 0.5 if g[0] < 6.0 else 0.0), g[1]))
	for s in _sparks:
		var a: float = clampf(s[2] / 0.3, 0.0, 1.0)
		draw_line(s[0], s[0] - (s[1] as Vector2) * 0.04, Color(1.0, 0.55, 0.3, a), 2.0)
