extends Node2D
## The Labyrinth of the main quest: a vast ruin laid out as a classical
## seven-circuit Cretan labyrinth (the design stamped on coins of Knossos),
## ringed with red Minoan columns and horns of consecration. Sealed by a
## shimmering field until the quest opens it.

const STONE := Color(0.78, 0.66, 0.48)
const STONE_DARK := Color(0.42, 0.34, 0.24)
const MINOAN_RED := Color(0.72, 0.18, 0.12)
const GOLD := Color(1.0, 0.82, 0.38)
const CIRCUITS := 7
const INNER := 90.0
const STEP := 52.0

var sealed := true:
	set(v):
		sealed = v
		queue_redraw()

var _time := 0.0


func _ready() -> void:
	z_index = -6
	add_to_group("labyrinth")
	var enabler := VisibleOnScreenEnabler2D.new()
	var r := INNER + STEP * (CIRCUITS + 1) + 120.0
	enabler.rect = Rect2(-r, -r, r * 2.0, r * 2.0)
	add_child(enabler)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var outer := INNER + STEP * CIRCUITS

	# Floor of the ruin.
	draw_circle(Vector2.ZERO, outer + 40.0, Color(0.16, 0.12, 0.09))
	draw_circle(Vector2.ZERO, outer + 40.0, Color(STONE, 0.06))

	# Walls: concentric rings, each broken by a doorway. Alternating the
	# doorway side makes the path wind back and forth like the Cretan design.
	for i in CIRCUITS + 1:
		var r := INNER + STEP * i
		var gap := 0.32 * (110.0 / (r + 20.0)) + 0.06
		var door := -PI / 2.0 if i % 2 == 0 else PI / 2.0
		if i == CIRCUITS:
			door = PI / 2.0  # the entrance faces "south"
		var a0 := door + gap
		var a1 := door + TAU - gap
		draw_arc(Vector2.ZERO, r, a0, a1, 96, STONE_DARK, 16.0, true)
		draw_arc(Vector2.ZERO, r, a0, a1, 96, STONE, 10.0, true)
		# Short radial walls beside the doorways turn the path around.
		if i > 0 and i < CIRCUITS:
			var wall_ang := door + PI
			draw_line(Vector2.from_angle(wall_ang) * (r - STEP + 8.0), Vector2.from_angle(wall_ang) * (r - 8.0), STONE, 9.0, true)

	# Centre chamber with the glowing archive.
	var pulse := 0.5 + 0.5 * sin(_time * 1.6)
	draw_circle(Vector2.ZERO, INNER - 14.0, Color(0.1, 0.08, 0.07))
	draw_circle(Vector2.ZERO, 48.0 + 6.0 * pulse, Color(GOLD, 0.12))
	draw_circle(Vector2.ZERO, 26.0, Color(GOLD, 0.35 + 0.2 * pulse))
	preload("res://scripts/quest_beacon.gd").draw_labrys(self, Vector2.ZERO, 30.0, GOLD)

	# Red Minoan columns around the outside: wider at the top (outer end).
	for k in 12:
		var ang := TAU * k / 12.0 + PI / 12.0
		var base := Vector2.from_angle(ang) * (outer + 30.0)
		var top := Vector2.from_angle(ang) * (outer + 82.0)
		var n := Vector2.from_angle(ang).orthogonal()
		var col := PackedVector2Array([base - n * 7.0, base + n * 7.0, top + n * 11.0, top - n * 11.0])
		draw_colored_polygon(col, MINOAN_RED)
		draw_line(top - n * 14.0, top + n * 14.0, Color(0.15, 0.1, 0.08), 6.0)   # black capital
		draw_line(base - n * 9.0, base + n * 9.0, STONE_DARK, 4.0)

	# Horns of consecration over the entrance.
	var gate := Vector2(0, outer + 70.0)
	draw_rect(Rect2(gate + Vector2(-36, 6), Vector2(72, 12)), STONE)
	for side in [-1.0, 1.0]:
		var horn := PackedVector2Array([gate + Vector2(side * 36, 8), gate + Vector2(side * 22, 8),
			gate + Vector2(side * 24, -14), gate + Vector2(side * 40, -34)])
		draw_colored_polygon(horn, STONE)

	# The seal: a shimmering field around the whole structure.
	if sealed:
		var sr := outer + 110.0
		for k in 3:
			var a := _time * (0.4 + 0.2 * k) + k * 2.0
			draw_arc(Vector2.ZERO, sr + k * 6.0, a, a + PI * 1.3, 64, Color(0.5, 0.9, 1.0, 0.35 - 0.08 * k), 3.0, true)
		draw_circle(Vector2.ZERO, sr, Color(0.4, 0.8, 1.0, 0.04 + 0.03 * pulse))
