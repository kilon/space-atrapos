extends Node2D
## Pulsing ring that shows where the ship is heading.

var _time := 0.0
var _fade := 0.0
var _tween: Tween


func show_at(point: Vector2) -> void:
	global_position = point
	_time = 0.0
	if _tween:
		_tween.kill()
	_fade = 1.0
	visible = true


func hide_marker() -> void:
	_tween = create_tween()
	_tween.tween_property(self, "_fade", 0.0, 0.3)


func _process(delta: float) -> void:
	_time += delta
	visible = _fade > 0.0
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var color := Color(0.4, 0.9, 1.0, 0.8 * _fade)
	draw_arc(Vector2.ZERO, 14.0 + 4.0 * pulse, 0.0, TAU, 32, color, 2.0, true)
	draw_circle(Vector2.ZERO, 3.0, color)
	# Expanding "ping" right after the click.
	if _time < 0.4:
		var t := _time / 0.4
		draw_arc(Vector2.ZERO, 10.0 + 30.0 * t, 0.0, TAU, 32, Color(color, (1.0 - t) * _fade), 2.0, true)
