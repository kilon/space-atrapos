class_name FaultSparks
extends Node2D
## Electrical faults crackling off a damaged body (your ship, other ships,
## your automaton): now and then a short jagged arc jumps across it and sparks
## spray off - more often and bigger the worse it's hurt (`hurt`: a Callable
## giving 0 (sound) .. 1 (nearly dead)). Idle and undrawn while it's fine;
## between bursts it isn't redrawn.
##   FaultSparks.attach(ship, 60.0, func(): return 1.0 - ship.hull / ship.max_hull)

var hurt: Callable
var radius := 50.0
var _bursts: Array = []     # {arc: PackedVector2Array, sparks: [[pos, vel]], t, life, col}
var _wait := 1.0


static func attach(host: Node2D, r: float, how_hurt: Callable) -> FaultSparks:
	var s := FaultSparks.new()
	s.radius = r
	s.hurt = how_hurt
	s.z_index = 3
	host.add_child(s)
	return s


func _process(delta: float) -> void:
	var h := clampf(float(hurt.call()), 0.0, 1.0) if hurt.is_valid() else 0.0
	if h > 0.25 and visible:
		_wait -= delta
		if _wait <= 0.0:
			# (at a quarter hurt one every 3-4 s; nearly dead several a second)
			_wait = lerpf(3.5, 0.25, (h - 0.25) / 0.75) * randf_range(0.6, 1.4)
			_burst(h)
	if _bursts.is_empty():
		return
	for b in _bursts:
		b["t"] = float(b["t"]) + delta
		for sp in b["sparks"]:
			sp[0] += sp[1] * delta
			sp[1] *= 0.92
	_bursts = _bursts.filter(func(b): return float(b["t"]) < float(b["life"]))
	queue_redraw()


func _burst(h: float) -> void:
	var a := Vector2.from_angle(randf() * TAU) * radius * randf_range(0.2, 0.8)
	var arc := PackedVector2Array([a])
	var d := Vector2.from_angle(randf() * TAU)
	var ln := radius * randf_range(0.3, 0.6) * (0.7 + h * 0.6)
	var p := a
	for i in 5:
		p += d.rotated(randf_range(-0.9, 0.9)) * ln / 5.0
		arc.append(p)
	var sparks := []
	for i in 4 + int(h * 8.0):
		sparks.append([p, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0)])
	var col := Color(0.6, 0.85, 1.0) if randf() < 0.7 else Color(1.0, 0.8, 0.45)
	_bursts.append({"arc": arc, "sparks": sparks, "t": 0.0, "life": randf_range(0.18, 0.35), "col": col})
	if randf() < 0.4:
		Sfx.play_world("space/spark", global_position, -14.0)


func _draw() -> void:
	# (drawn level with the screen: the body's turn doesn't spin the sparks)
	draw_set_transform(Vector2.ZERO, -global_rotation, Vector2.ONE / global_scale)
	for b in _bursts:
		var u: float = float(b["t"]) / float(b["life"])
		var col: Color = b["col"]
		if u < 0.6:
			var arc: PackedVector2Array = b["arc"]
			draw_polyline(arc, Color(col, 0.35 * (1.0 - u)), 6.0, true)
			draw_polyline(arc, Color(1, 1, 1, 0.95 * (1.0 - u)), 1.6, true)
		for sp in b["sparks"]:
			var v: Vector2 = sp[1]
			draw_line(sp[0], sp[0] - v * 0.03, Color(col.lightened(0.3), 1.0 - u), 1.5, true)
