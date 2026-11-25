class_name FpsCounter
extends CanvasLayer
## The FPS counter: a small readout at the top right, beside the minimap -
## frames a second and the frame time - over every scene (Settings adds one
## to the root at startup, like the CRT filter). Shown while
## Settings.fps_counter is on (the settings page's "FPS counter" switch);
## the number is refreshed EVERY s, coloured green at 60 and above, amber
## down to 45, red below.

const EVERY := 0.25

var label: Label
var graph: Graph
var _t := 0.0
var _frames := 0
var _time := 0.0


func _ready() -> void:
	layer = 4   # (over the HUD - beside the minimap - under the full-screen windows: the computers, a station, the Esc menu)
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	# Top right, just left of the minimap (it fills the corner's ~320 px).
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = -470
	label.offset_right = -330
	label.offset_top = 10
	label.offset_bottom = 34
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(label)
	# The live graph under it: each frame's time, the last SAMPLES frames.
	graph = Graph.new()
	graph.anchor_left = 1.0
	graph.anchor_right = 1.0
	graph.offset_left = -470
	graph.offset_right = -330
	graph.offset_top = 36
	graph.offset_bottom = 84
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(graph)
	_update()


func _process(delta: float) -> void:
	visible = Settings.fps_counter
	if not visible:
		return
	_frames += 1
	_time += delta
	_t += delta
	graph.push(delta * 1000.0)
	if _t >= EVERY:
		_update()


## The readout from the frames counted since the last one.
func _update() -> void:
	var fps := _frames / _time if _time > 0.0 else Engine.get_frames_per_second()
	var ms := _time / _frames * 1000.0 if _frames > 0 else 0.0
	label.text = "%d FPS  %.1f ms" % [roundi(fps), ms]
	label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55) if fps >= 59.0 else (Color(1.0, 0.8, 0.3) if fps >= 45.0 else Color(1.0, 0.4, 0.35)))
	_t = 0.0
	_frames = 0
	_time = 0.0


## The real-time frame-time graph: the last SAMPLES frames (newest at the
## right), on a scale that fits the worst of them (8, 17, 34 or 67 ms - shown
## top left), with lines at 600, 240 and 60 FPS (1.7, 4.2 and 16.7 ms); a frame
## over even 67 ms shows a red bar at the top. Redrawn 30 times
## a second (one polyline - it mustn't cost what it measures).
class Graph extends Control:
	const SAMPLES := 140
	const TOP := 8.0   # ms at the top of the graph
	var _ms := PackedFloat32Array()
	var _i := 0
	var _t := 0.0

	func _init() -> void:
		_ms.resize(SAMPLES)

	func push(ms: float) -> void:
		_ms[_i] = ms
		_i = (_i + 1) % SAMPLES
		_t += ms / 1000.0
		if _t >= 1.0 / 30.0:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		var worst := 0.0
		for v in _ms:
			worst = maxf(worst, v)
		# The scale: the smallest of these that holds the worst recent frame.
		var top := TOP
		for t in [8.0, 17.0, 34.0, 67.0]:
			top = t
			if worst <= t:
				break
		for ref in [[1000.0 / 600.0, Color(0.45, 1.0, 0.55, 0.45)], [1000.0 / 240.0, Color(1.0, 0.8, 0.3, 0.45)], [1000.0 / 60.0, Color(1.0, 0.4, 0.35, 0.45)]]:
			if float(ref[0]) < top:
				var y: float = h - h * float(ref[0]) / top
				draw_line(Vector2(0, y), Vector2(w, y), ref[1], 1.0)
		var pts := PackedVector2Array()
		pts.resize(SAMPLES)
		for k in SAMPLES:
			var v := _ms[(_i + k) % SAMPLES]
			pts[k] = Vector2(w * k / float(SAMPLES - 1), h - h * minf(v, top) / top)
		draw_polyline(pts, Color(0.55, 0.85, 1.0), 1.0)
		if worst > top:
			draw_rect(Rect2(0, 0, w, 2), Color(1.0, 0.35, 0.3))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(3, 11), "%d ms" % roundi(top), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
