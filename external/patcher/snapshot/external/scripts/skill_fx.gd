class_name SkillFx
extends RefCounted
## What the automaton's skills look like (Skills; PlanetSurface casts them):
## each a short-lived Node2D standing on the ground where it happens (group
## "surface_lift": drawn lifted with the ground), drawn additively from a few
## lines, arcs and soft discs - a blow's spark and arc, the leap's dust ring,
## the Helios Lance (Beam), Phlox (Fireball, its Burst), Keraunos (Bolt), the
## Aegis Dome (Dome, a child of the pilot), the eidola's summoning circle
## (Circle) and a spell gathering in the hands (Charge). Redrawn 60 times a
## second (UI.redraw_due), not every frame.

const UP := Vector2(0, -58.0)        # chest height over the ground point (px)


static func _add(parent: Node, n: Node2D, at: Vector2) -> Node2D:
	n.position = at
	n.z_index = 15
	n.material = Effects._additive_material()
	n.add_to_group("surface_lift")
	parent.add_child(n)
	return n


static func _disc(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(Effects._glow_texture(), Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## A blow landing: a star of sparks and a flash.
static func impact(parent: Node, at: Vector2, color := Color(1.0, 0.85, 0.5), size := 1.0) -> void:
	var n := Spark.new()
	n.color = color
	n.size = size
	_add(parent, n, at)


## A kick's arc through the air in front (dir: the way it faces; ring: all around).
static func arc(parent: Node, at: Vector2, dir: Vector2, radius: float, color: Color, ring := false) -> void:
	var n := Arc.new()
	n.dir = dir
	n.radius = radius
	n.color = color
	n.ring = ring
	_add(parent, n, at)


## A ring spreading over the ground (a landing, a burst, the dome's shock).
static func ring(parent: Node, at: Vector2, radius: float, color: Color, life := 0.4) -> void:
	var n := Ring.new()
	n.radius = radius
	n.color = color
	n.life = life
	_add(parent, n, at)


## A burst of fire (Phlox landing): a ball swelling and fading, embers thrown out.
static func burst(parent: Node, at: Vector2, radius: float, color: Color) -> void:
	var n := Burst.new()
	n.radius = radius
	n.color = color
	n.life = 0.45
	_add(parent, n, at)


static func beam(parent: Node, from: Vector2, to: Vector2, width: float, color: Color, life := 0.5) -> void:
	var n := Beam.new()
	n.to = to - from
	n.width = width
	n.color = color
	n.life = life
	_add(parent, n, from)


static func bolt(parent: Node, at: Vector2, color := Color(0.75, 0.85, 1.0), from := Vector2.INF) -> void:
	var n := Bolt.new()
	n.color = color
	n.from = (from - at) if from != Vector2.INF else Vector2.INF
	n.seed_ = randi()
	_add(parent, n, at)


static func charge(parent: Node2D, at: Vector2, color: Color, life: float) -> void:
	var n := Charge.new()
	n.color = color
	n.life = life
	n.position = at
	n.z_index = 15
	n.material = Effects._additive_material()
	parent.add_child(n)


static func circle(parent: Node, at: Vector2, radius: float, color: Color, life := 1.0) -> void:
	var n := Circle.new()
	n.radius = radius
	n.color = color
	n.life = life
	_add(parent, n, at)
	n.z_index = 0


class Timed extends Node2D:
	var life := 0.3
	var color := Color.WHITE
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		if UI.redraw_due(self):       # (60 times a second, however fast the game runs)
			queue_redraw()

	func k() -> float:
		return clampf(_t / life, 0.0, 1.0)


class Spark extends Timed:
	var size := 1.0

	func _ready() -> void:
		life = 0.18
		rotation = randf() * TAU

	func _draw() -> void:
		var f := k()
		var a := 1.0 - f
		SkillFx._disc(self, Vector2.ZERO, (26.0 + 30.0 * f) * size, Color(color, 0.8 * a))
		for i in 6:
			var d := Vector2.from_angle(TAU * i / 6.0)
			draw_line(d * (8.0 + 30.0 * f) * size, d * (20.0 + 46.0 * f) * size, Color(1, 1, 1, a), 3.0 * size * a + 0.5, true)


class Arc extends Timed:
	var dir := Vector2.RIGHT
	var radius := 80.0
	var ring := false

	func _ready() -> void:
		life = 0.22

	func _draw() -> void:
		var f := k()
		var a := 1.0 - f
		# (on the ground plane: squashed)
		draw_set_transform(SkillFx.UP * 0.6, 0.0, Vector2(1.0, 0.5))
		var ang := Vector2(dir.x, dir.y * 2.0).angle()
		var half := PI if ring else 1.15
		var sweep := half * 2.0 * minf(1.0, f * 2.2)
		var a0 := ang - half
		draw_arc(Vector2.ZERO, radius * (0.75 + 0.25 * f), a0, a0 + sweep, 20, Color(color, 0.85 * a), 9.0 * a + 1.0, true)
		draw_arc(Vector2.ZERO, radius * (0.75 + 0.25 * f), a0, a0 + sweep, 20, Color(1, 1, 1, 0.8 * a), 3.0 * a + 0.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Ring extends Timed:
	var radius := 100.0

	func _draw() -> void:
		var f := k()
		var e := 1.0 - (1.0 - f) * (1.0 - f)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, radius * e, 0, TAU, 40, Color(color, 0.9 * (1.0 - f)), 10.0 * (1.0 - f) + 1.0, true)
		draw_arc(Vector2.ZERO, radius * e * 0.8, 0, TAU, 32, Color(color, 0.35 * (1.0 - f)), 4.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Burst extends Timed:
	var radius := 100.0
	var _dirs := PackedVector2Array()

	func _ready() -> void:
		for i in 10:
			_dirs.append(Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.0))

	func _draw() -> void:
		var f := k()
		var e := 1.0 - (1.0 - f) * (1.0 - f)
		var a := 1.0 - f
		var c := Vector2(0, -30.0)
		SkillFx._disc(self, c, radius * (0.5 + 0.7 * e), Color(color, 0.85 * a))
		SkillFx._disc(self, c, radius * (0.25 + 0.4 * e), Color(1.0, 0.9, 0.55, a))
		for d in _dirs:
			var p := c + d * Vector2(1.0, 0.6) * radius * (0.3 + 0.9 * e)
			SkillFx._disc(self, p, 9.0 * a + 3.0, Color(1.0, 0.75, 0.3, a))


## The Helios Lance: a beam from the hands, flaring up and dying away.
class Beam extends Timed:
	var to := Vector2.RIGHT * 300.0
	var width := 26.0

	func _draw() -> void:
		var f := k()
		var a := sin(minf(1.0, f * 3.0) * PI * 0.5) * (1.0 - maxf(0.0, f - 0.55) / 0.45)
		var flick := 0.85 + 0.15 * sin(_t * 90.0)
		var p0 := SkillFx.UP
		var p1 := to + SkillFx.UP * 0.75
		draw_line(p0, p1, Color(color, 0.28 * a), width * 1.5 * flick, true)
		draw_line(p0, p1, Color(color, 0.7 * a), width * 0.7 * flick, true)
		draw_line(p0, p1, Color(1, 1, 1, 0.95 * a), width * 0.26, true)
		SkillFx._disc(self, p0, width * 1.6, Color(color, 0.9 * a))
		SkillFx._disc(self, p1, width * 1.9 * flick, Color(1, 1, 1, 0.8 * a))


## Keraunos: a jagged bolt down from the sky onto the spot (or an arc leaping
## there from `from`), flashing twice.
class Bolt extends Timed:
	var from := Vector2.INF
	var seed_ := 0
	var _pts := PackedVector2Array()

	func _ready() -> void:
		life = 0.32
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_
		var a := SkillFx.UP * 0.6
		var b := (from + SkillFx.UP) if from != Vector2.INF else Vector2(rng.randf_range(-90.0, 90.0), -760.0)
		var n := 9
		for i in n + 1:
			var t := i / float(n)
			var p := b.lerp(a, t)
			if i > 0 and i < n:
				p += (a - b).orthogonal().normalized() * rng.randf_range(-26.0, 26.0)
			_pts.append(p)

	func _draw() -> void:
		var f := k()
		var a := (1.0 - f) * (0.55 + 0.45 * absf(sin(f * 14.0)))
		draw_polyline(_pts, Color(color, 0.45 * a), 16.0, true)
		draw_polyline(_pts, Color(color, 0.9 * a), 6.0, true)
		draw_polyline(_pts, Color(1, 1, 1, a), 2.5, true)
		SkillFx._disc(self, SkillFx.UP * 0.6, 60.0 * (1.0 - f * 0.5), Color(color, 0.9 * a))


## A spell gathering between the hands.
class Charge extends Timed:
	func _draw() -> void:
		var f := k()
		var r := 8.0 + 20.0 * f
		SkillFx._disc(self, Vector2.ZERO, r * 1.8, Color(color, 0.55 + 0.3 * f))
		SkillFx._disc(self, Vector2.ZERO, r * 0.8, Color(1, 1, 1, 0.9))
		for i in 4:
			var d := Vector2.from_angle(_t * 9.0 + TAU * i / 4.0)
			draw_line(d * r * (2.6 - 1.4 * f), d * r * 0.9, Color(color, 0.7), 2.0, true)


## The eidola's summoning circle on the ground: rings and a rune star, turning.
class Circle extends Timed:
	var radius := 80.0

	func _draw() -> void:
		var f := k()
		var a := sin(f * PI)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(color, 0.9 * a), 3.0, true)
		draw_arc(Vector2.ZERO, radius * 0.72, 0, TAU, 32, Color(color, 0.6 * a), 2.0, true)
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(Vector2.from_angle(_t * 1.6 + TAU * i * 2.0 / 5.0) * radius * 0.72)
		draw_polyline(pts, Color(1, 1, 1, 0.7 * a), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		SkillFx._disc(self, Vector2.ZERO, radius * 0.9, Color(color, 0.25 * a))


## Phlox: a ball of fire flying to where it was thrown (PlanetSurface bursts
## it there: `landed`), a tail of embers behind it.
class Fireball extends Node2D:
	signal landed(at: Vector2)
	var goal := Vector2.ZERO           # (the ground point it flies to)
	var speed := 620.0
	var color := Color(1.0, 0.5, 0.15)
	var height := 58.0                  # (how high it flies: comes down as it nears)
	var _t := 0.0
	var _from := Vector2.ZERO
	var _trail := PackedVector2Array()

	func _ready() -> void:
		_from = position
		z_index = 15
		material = Effects._additive_material()
		add_to_group("surface_lift")

	func _process(delta: float) -> void:
		_t += delta
		var to := goal - position
		var step := speed * delta
		_trail.append(position)
		if _trail.size() > 9:
			_trail.remove_at(0)
		if to.length() <= step:
			position = goal
			landed.emit(goal)
			queue_free()
			return
		position += to.normalized() * step
		if UI.redraw_due(self):
			queue_redraw()

	func _draw() -> void:
		var total := maxf(1.0, _from.distance_to(goal))
		var left := position.distance_to(goal) / total
		var up := Vector2(0, -height * (0.35 + 0.65 * left) - 26.0 * sin((1.0 - left) * PI))
		for i in _trail.size():
			var f := (i + 1) / float(_trail.size() + 1)
			SkillFx._disc(self, _trail[i] - position + up, 10.0 + 12.0 * f, Color(color, 0.35 * f))
		var pulse := 1.0 + 0.12 * sin(_t * 40.0)
		SkillFx._disc(self, up, 34.0 * pulse, Color(color, 0.9))
		SkillFx._disc(self, up, 17.0 * pulse, Color(1.0, 0.95, 0.6, 1.0))


## The Aegis Dome round the pilot (its child): a shimmering shell, flaring
## when it soaks a hit (flash()), thinning as its time runs out.
class Dome extends Node2D:
	var radius := 120.0
	var color := Color(0.45, 0.8, 1.0)
	var left := 1.0                     # 0..1 of its strength left (the pilot sets it)
	var _t := 0.0
	var _flash := 0.0
	var _in := 0.0

	func _ready() -> void:
		z_index = 14
		material = Effects._additive_material()

	func flash() -> void:
		_flash = 1.0

	func _process(delta: float) -> void:
		_t += delta
		_in = minf(1.0, _in + delta * 4.0)
		_flash = maxf(0.0, _flash - delta * 5.0)
		if UI.redraw_due(self):
			queue_redraw()

	func _draw() -> void:
		var r := radius * (0.6 + 0.4 * _in)
		var a := (0.35 + 0.4 * left) * _in + 0.4 * _flash
		# the foot of it on the ground, then the shell's arcs
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(color, 0.9 * a), 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 5:
			var w := 0.35 + 0.65 * absf(sin(_t * 0.9 + i * 1.3))
			var sx := cos(_t * 0.7 + i * TAU / 5.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx, 1.0))
			draw_arc(Vector2(0, 0), r, PI, TAU, 24, Color(color, 0.32 * a * w), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_arc(Vector2.ZERO, r, PI, TAU, 40, Color(color, 0.85 * a), 3.5, true)
		SkillFx._disc(self, Vector2(0, -r * 0.45), r * 1.05, Color(color, 0.16 * a + 0.2 * _flash))
