class_name AfflictionBar
extends HBoxContainer
## The afflictions under the health bar (the space HUD's hull, the surface
## HUD's health): an icon each (Parts.afflictions) - the frozen self-repair
## first, then each damaged part, the worst first - its tooltip what it does
## and what's wrong in it. Looked at four times a second; rebuilt only when
## they change. `source` gives the condition (PlayerData's / the surface's).
##   var bar := AfflictionBar.new(); bar.which = "ship"; bar.source = func(): return data.condition

var which := "ship"
var source: Callable
const ICON := 26.0
var _sig := "-"   # (not yet looked: the first refresh always sets it up)
var _t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = MOUSE_FILTER_IGNORE
	refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	refresh()


func refresh() -> void:
	if not source.is_valid():
		return
	var cond = source.call()
	var list: Array = Parts.afflictions(cond, which) if cond is Dictionary else []
	var sig := ",".join(list.map(func(a): return "%s:%d" % [a["id"], roundi(float(a["loss"]) * 20.0)]))
	if sig == _sig:
		return
	_sig = sig
	for c in get_children():
		c.queue_free()
	for a in list:
		add_child(icon_for(a, which))
	visible = not list.is_empty()


## One affliction's badge (Parts.afflictions' entry), with its tooltip - the bar's, and HealthGauge's round its circle.
static func icon_for(a: Dictionary, which_: String) -> Control:
	var ic := Icon.new()
	ic.which = which_
	ic.id = a["id"]
	ic.loss = a["loss"]
	ic.custom_minimum_size = Vector2(ICON, ICON)
	ic.size = Vector2(ICON, ICON)
	ic.tooltip_text = "%s\n%s\nRepair it: the Repair Bay (%s > Repair), or a station's repair service." % [a["name"], a["desc"],
		"Ship Computer" if which_ == "ship" else "Field Computer / Ship Computer"]
	return ic


## One affliction's badge: a glyph for its part (or the frozen self-repair), amber to red by how bad.
class Icon extends Control:
	var which := "ship"
	var id := ""
	var loss := 0.5
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		if loss > 0.6:   # (a bad one throbs)
			_t += delta
			if UI.redraw_due(self, 20.0):
				queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.5
		var col := Color(1.0, 0.78, 0.25).lerp(Color(1.0, 0.25, 0.2), clampf(loss, 0.0, 1.0))
		if id == "regen":
			col = Color(0.45, 0.8, 1.0)
		var a := 1.0 if loss <= 0.6 else 0.75 + 0.25 * sin(_t * 6.0)
		draw_rect(r, Color(0.04, 0.03, 0.03, 0.85))
		draw_rect(r, Color(col, 0.22 * a))
		draw_rect(r.grow(-0.5), Color(col, a), false, 1.5)
		var g := Color(col.lightened(0.35), a)
		var w := maxf(1.5, s * 0.14)
		match id:
			"regen":   # a cross (repair) with a snowflake's bar through it: frozen
				draw_line(c + Vector2(0, -s * 0.6), c + Vector2(0, s * 0.6), g, w * 1.4)
				draw_line(c + Vector2(-s * 0.6, 0), c + Vector2(s * 0.6, 0), g, w * 1.4)
				for k in 3:
					var d := Vector2.from_angle(PI / 6.0 + k * PI / 3.0) * s * 0.55
					draw_line(c - d, c + d, Color(1, 1, 1, 0.8 * a), w * 0.6)
			"engines", "legs":   # a nozzle / a leg: down-pointing chevrons (speed)
				for k in 2:
					var y := c.y - s * 0.35 + k * s * 0.42
					draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5, y - c.y), c + Vector2(0, y - c.y + s * 0.35), c + Vector2(s * 0.5, y - c.y)]), g, w)
			"thrusters":
				draw_arc(c, s * 0.5, -PI * 0.9, PI * 0.4, 12, g, w)
				draw_line(c + Vector2.from_angle(PI * 0.4) * s * 0.5, c + Vector2.from_angle(PI * 0.4) * s * 0.5 + Vector2(-s * 0.3, 0), g, w)
			"shields":
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.5), c + Vector2(s * 0.5, -s * 0.5), c + Vector2(s * 0.45, s * 0.1), c + Vector2(0, s * 0.6),
					c + Vector2(-s * 0.45, s * 0.1), c + Vector2(-s * 0.5, -s * 0.5)]), g, w)
				draw_line(c + Vector2(-s * 0.3, -s * 0.2), c + Vector2(s * 0.2, s * 0.3), g, w)
			"weapons", "arms":   # crosshair
				draw_arc(c, s * 0.45, 0, TAU, 16, g, w)
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(c + d * s * 0.25, c + d * s * 0.65, g, w)
			"sensors", "optics":   # an eye
				draw_arc(c + Vector2(0, s * 0.35), s * 0.6, -PI * 0.8, -PI * 0.2, 10, g, w)
				draw_arc(c - Vector2(0, s * 0.35), s * 0.6, PI * 0.2, PI * 0.8, 10, g, w)
				draw_circle(c, s * 0.18, g)
			"reactor", "core":   # a heart / a power cell: a bolt
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.65), c + Vector2(-s * 0.3, s * 0.05), c + Vector2(s * 0.15, s * 0.05), c + Vector2(-s * 0.1, s * 0.65)]), g, w)
			"fuel", "cooling":   # a drop
				draw_arc(c + Vector2(0, s * 0.15), s * 0.38, -PI * 0.15, PI * 1.15, 12, g, w)
				draw_line(c + Vector2(-s * 0.36, s * 0.05), c + Vector2(0, -s * 0.6), g, w)
				draw_line(c + Vector2(s * 0.36, s * 0.05), c + Vector2(0, -s * 0.6), g, w)
			_:   # plating, frame: a cracked plate
				draw_rect(Rect2(c - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), g, false, w)
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.1, -s * 0.5), c + Vector2(s * 0.1, -s * 0.1), c + Vector2(-s * 0.05, s * 0.15), c + Vector2(s * 0.15, s * 0.5)]), g, w * 0.8)
