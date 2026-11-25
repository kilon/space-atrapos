class_name HealthGauge
extends Control
## The health gauge (the space HUD's, and on foot the surface HUD's): the
## outline of your ship (or of the automaton) filled with red liquid as high as
## its hull (health) is - a wavy, moving surface (shaders/gauge_fill) - inside a
## blue ring filled the same way as high as its shields are (gauge_ring); round
## the circle, clockwise from the top, an icon for each affliction (a damaged
## part: AfflictionBar's badges, their tooltips); the numbers in its tooltip.
## A ship's gauge (`fuel` given) has a third ring outside the shield's: its
## fuel, amber liquid as high as the tank is full (its rim red when there's
## not enough left for a jump). The automaton's has its stamina there, in
## green (`fuel` reading Stamina, `fuel_name` "Stamina", `fuel_liquid`).
##   var g := HealthGauge.new(); g.which = "ship"; g.read = func(): return [hull, max_hull, shields, max_shields]
##   g.silhouette = ship's texture; g.condition = func(): return data.condition

const RING := 150.0           # the ring's diameter (px)
const ICON_GAP := 6.0
const STEP_DEG := 30.0        # between two affliction icons, clockwise from the top
const FILL := preload("res://shaders/gauge_fill.gdshader")
const RING_SHADER := preload("res://shaders/gauge_ring.gdshader")
const FUEL_W := 18.0          # the fuel ring's thickness and gap outside the shield ring (px)

var which := "ship"
## [hull, max hull, shields, max shields] - read a few times a second.
var read: Callable
## The parts' condition (Parts.afflictions) - for the icons round the circle.
var condition: Callable
## The outline's picture, looked at a few times a second (a new ship: its outline).
var shape_source: Callable
## [fuel, max fuel, too little to jump below] - the fuel ring (ships only; none if not given).
var fuel: Callable
var hull_name := "HULL"
## The outer ring's name (tooltip) and colours.
var fuel_name := "Fuel"
var fuel_liquid := Color(1.0, 0.62, 0.15)
var fuel_rim := Color(1.0, 0.82, 0.45)
var fuel_low_note := "  (not enough to jump)"
var shield_name := "SHIELDS"
var silhouette: Texture2D:
	set(t):
		silhouette = t
		if _shape:
			_shape.texture = t
			_fit_shape()

var _ring: ColorRect
var _fuel_ring: ColorRect
var _fuel_shown := [-1.0, false]
var _shape: TextureRect
var _icons: Control
var _vals := [1.0, 1.0, 1.0, 1.0]
var _shown := [-1.0, -1.0]
var _sig := "-"
var _t := 0.0


## The outermost ring's diameter (the fuel ring's, else the shield's).
func _outer() -> float:
	return RING + 2.0 * FUEL_W if fuel.is_valid() else RING


func _ready() -> void:
	var side := _outer() + 2.0 * (AfflictionBar.ICON + ICON_GAP)
	custom_minimum_size = Vector2(side, side)
	mouse_filter = MOUSE_FILTER_IGNORE
	if fuel.is_valid():
		var d := _outer()
		_fuel_ring = ColorRect.new()
		_fuel_ring.size = Vector2(d, d)
		_fuel_ring.position = Vector2((side - d) / 2.0, (side - d) / 2.0)
		_fuel_ring.mouse_filter = MOUSE_FILTER_STOP
		var fm_ := ShaderMaterial.new()
		fm_.shader = RING_SHADER
		# (as thick as the shield's ring, just outside it)
		fm_.set_shader_parameter("inner", (RING / 2.0 + 3.0) / (d / 2.0))
		fm_.set_shader_parameter("outer", 0.98)
		fm_.set_shader_parameter("liquid", fuel_liquid)
		fm_.set_shader_parameter("rim", fuel_rim)
		fm_.set_shader_parameter("seed", randf() * 10.0)
		_fuel_ring.material = fm_
		add_child(_fuel_ring)
	_ring = ColorRect.new()
	_ring.size = Vector2(RING, RING)
	_ring.position = Vector2((side - RING) / 2.0, (side - RING) / 2.0)
	_ring.mouse_filter = MOUSE_FILTER_STOP
	_ring.tooltip_text = "Shields (the blue ring) and hull (the red inside)"
	var rm := ShaderMaterial.new()
	rm.shader = RING_SHADER
	_ring.material = rm
	add_child(_ring)
	_shape = TextureRect.new()
	_shape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shape.mouse_filter = MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = FILL
	fm.set_shader_parameter("seed", randf() * 10.0)
	_shape.material = fm
	_shape.texture = silhouette
	add_child(_shape)
	_fit_shape()
	_icons = Control.new()
	_icons.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_icons)
	_refresh()


func _fit_shape() -> void:
	if _shape == null or _ring == null:
		return
	var inner := RING * 0.74
	_shape.size = Vector2(inner, inner)
	_shape.position = _ring.position + Vector2(RING - inner, RING - inner) / 2.0
	if silhouette:
		var s := silhouette.get_size()
		(_shape.material as ShaderMaterial).set_shader_parameter("px", Vector2(2.5, 2.5) / (inner * Vector2(1.0, s.y / maxf(1.0, s.x)).max(Vector2.ONE)))


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.1
	_refresh()


## Looked at again now (the icons too).
func refresh() -> void:
	_sig = "-"
	_refresh()


## The affliction icons round the circle (in clockwise order).
func icons() -> Array:
	return _icons.get_children().filter(func(c): return not c.is_queued_for_deletion())


func _refresh() -> void:
	if shape_source.is_valid():
		var t = shape_source.call()
		if t is Texture2D and t != silhouette:
			silhouette = t
	if read.is_valid():
		_vals = read.call()
	var hk := clampf(float(_vals[0]) / maxf(1.0, float(_vals[1])), 0.0, 1.0)
	var sk := clampf(float(_vals[2]) / maxf(1.0, float(_vals[3])), 0.0, 1.0) if float(_vals[3]) > 0.0 else 0.0
	if hk != _shown[0] or sk != _shown[1]:
		_shown = [hk, sk]
		(_shape.material as ShaderMaterial).set_shader_parameter("level", hk)
		(_ring.material as ShaderMaterial).set_shader_parameter("level", sk)
		# (no numbers drawn: they're in the ring's tooltip)
		_retip()
	if _fuel_ring and fuel.is_valid():
		var f: Array = fuel.call()
		var fk := clampf(float(f[0]) / maxf(1.0, float(f[1])), 0.0, 1.0)
		var low := f.size() > 2 and float(f[0]) < float(f[2])
		if fk != _fuel_shown[0] or low != _fuel_shown[1]:
			_fuel_shown = [fk, low]
			_fuel_f = f
			var m := _fuel_ring.material as ShaderMaterial
			m.set_shader_parameter("level", fk)
			m.set_shader_parameter("rim", Color(1.0, 0.3, 0.25) if low else fuel_rim)
			_retip()
	_refresh_icons()


var _fuel_f := []

## The numbers (none drawn) in the rings' tooltip.
func _retip() -> void:
	var t := "%s %d / %d    %s %d / %d" % [hull_name.capitalize(), ceili(float(_vals[0])), ceili(float(_vals[1])),
		shield_name.capitalize(), ceili(float(_vals[2])), ceili(float(_vals[3]))]
	if _fuel_ring and _fuel_f.size() > 1:
		t += "    %s %d / %d%s" % [fuel_name, floori(float(_fuel_f[0])), ceili(float(_fuel_f[1])),
			fuel_low_note if _fuel_f.size() > 2 and float(_fuel_f[0]) < float(_fuel_f[2]) else ""]
	t += "\n" + (tooltip_text if tooltip_text != "" else ("Fuel (the amber ring), shields (the blue ring) and hull (the red inside)" if _fuel_ring else "Shields (the blue ring) and hull (the red inside)"))
	_ring.tooltip_text = t
	if _fuel_ring:
		_fuel_ring.tooltip_text = t


## The afflictions round the circle, clockwise from the top (rebuilt only when they change).
func _refresh_icons() -> void:
	var cond = condition.call() if condition.is_valid() else null
	var list: Array = Parts.afflictions(cond, which) if cond is Dictionary else []
	var sig := ",".join(list.map(func(a): return "%s:%d" % [a["id"], roundi(float(a["loss"]) * 20.0)]))
	if sig == _sig:
		return
	_sig = sig
	for c in _icons.get_children():
		c.queue_free()
	var centre := _ring.position + Vector2(RING, RING) / 2.0
	var r := _outer() / 2.0 + ICON_GAP + AfflictionBar.ICON / 2.0
	for i in list.size():
		var ang := deg_to_rad(-90.0 + i * STEP_DEG)
		var ic := AfflictionBar.icon_for(list[i], which)
		ic.position = centre + Vector2.from_angle(ang) * r - Vector2(AfflictionBar.ICON, AfflictionBar.ICON) / 2.0
		_icons.add_child(ic)
