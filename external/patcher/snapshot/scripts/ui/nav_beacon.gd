class_name NavBeacon
extends Node2D
## The navigation beacon by every system's star: scan it (right-click) and it charts the
## system for good (Galaxy.chart_system) - the fog gone from its maps, every
## star, planet, moon, station and jump gate shown. Its picture (half a
## station's size) turning slowly, amber-labelled until it's scanned. Once
## it has charted the system (a pulse of light sweeps out over it), it comes
## alive, green: a glow, a pulsating ring (ticks and brackets turning round
## it), and scanning waves leaving in random directions that fade fast, each
## leaving a trail of holographic nebula gas (shaders/nav_trail.gdshader)
## that lingers and fades. Labelled CHARTED. Main places it (place()) and handles the right-click
## (_nav_beacon_at / chart_with_beacon).

## Its size: half a station's (a station's picture is ~440 across), about
## twice your ship.
const SIZE := 220.0
const RADIUS := SIZE * 0.5
## A click this near its centre hits it (a bit more than the picture: easy to hit).
const CLICK_RADIUS := 130.0
## Scanning it (right-click): this long, from within this range (Main.scan_beacon).
const SCAN_TIME := 6.0
const SCAN_RANGE := 1600.0
const PULSE_TIME := 2.2          # s: the charting pulse
const PULSE_REACH := 2400.0
## Scanning waves (once charted), each in a random direction: one every WAVE_EVERY s, out to WAVE_REACH, gone in WAVE_TIME.
## (Slowed down SLOW times; one every WAVE_EVERY so at most about two trails overlap.)
const SLOW := 6.0
const WAVE_EVERY := 11.0
const WAVE_TIME := 1.5 * SLOW
const WAVE_REACH := 1100.0
## The nebula a wave leaves behind it (shaders/nav_trail.gdshader) lasts this long where the front passed.
const FOAM_TIME := 2.6 * SLOW
const TRAIL_SEGMENTS := 20       # (quads across a wave's arc)

var sys_id := ""
var _tex: Texture2D               # data/sprites/nav_beacon.png (cut from external/images/nav_beacon.png)
var _t := 0.0
var _pulse := -1.0               # time since charting, < 0 = none
var scan := -1.0                 # being scanned: 0..1 done (Main sets it); < 0 = not
var scanner: Node2D              # the ship scanning it (for the beam)
var _fx: Node2D                  # the waves' fronts, added on (they glow)
var _trail: Node2D               # the nebula trails behind them (a shader)


## Where it stands: by the star (the star's radius + a gap), at an angle of
## its own for each system.
static func place(sys: String, star_radius: float) -> Vector2:
	return Vector2.from_angle(float(hash(sys + ":nav") % 6283) / 1000.0) * (star_radius + 650.0)


func _ready() -> void:
	add_to_group("nav_beacons")
	z_index = -3
	_tex = ProcArt.sprite("nav_beacon")
	_t = randf() * 10.0
	# The nebula trails: a shader on a layer of their own, under the fronts.
	_trail = Node2D.new()
	_trail.z_index = -2
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/nav_trail.gdshader")
	sm.set_shader_parameter("noise", _noise())
	sm.set_shader_parameter("wave_time", WAVE_TIME)
	sm.set_shader_parameter("foam_time", FOAM_TIME)
	sm.set_shader_parameter("slow", SLOW)
	sm.set_shader_parameter("drift", 0.02 / SLOW)
	_trail.material = sm
	_trail.draw.connect(func(): _draw_trails(_trail))
	add_child(_trail)
	# The waves' fronts draw on a layer of their own, blended additively:
	# light added to what's behind, so they glow.
	_fx = Node2D.new()
	_fx.z_index = -1
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx.material = add
	_fx.draw.connect(func(): _draw_waves(_fx, _color()))
	add_child(_fx)
	var enabler := VisibleOnScreenEnabler2D.new()   # (still off screen: no redraws)
	enabler.rect = Rect2(-Vector2.ONE * PULSE_REACH, Vector2.ONE * PULSE_REACH * 2.0)
	add_child(enabler)


func charted() -> bool:
	return Galaxy.charted.has(sys_id)


## (Charted just now) The pulse of light sweeping out over the system.
func pulse() -> void:
	_pulse = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _pulse >= 0.0:
		_pulse += delta
		if _pulse > PULSE_TIME:
			_pulse = -1.0
	if _pulse >= 0.0 or scan >= 0.0 or UI.redraw_due(self):
		queue_redraw()
		var on := charted()   # (the animation only once it's scanned the system)
		for layer in [_fx, _trail]:
			if layer:
				layer.visible = on
				if on:
					layer.queue_redraw()


func _color() -> Color:
	return Color(0.45, 1.0, 0.7) if charted() else Color(1.0, 0.75, 0.3)


func _draw() -> void:
	var c := _color()
	var done := charted()
	var beat := 0.5 + 0.5 * sin(_t * 1.3)   # (the pulse: 0..1)
	var rr := RADIUS * 1.12 + 6.0 * beat
	# Charted: a soft glow behind it, breathing with the pulse (before, just the beacon).
	if done:
		var gr := RADIUS * (2.0 + 0.15 * beat)
		draw_texture_rect(_glow(), Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(c, 0.28 + 0.14 * beat))
	# The beacon itself, turning slowly.
	if _tex:
		var k := SIZE / maxf(_tex.get_width(), _tex.get_height())
		draw_set_transform(Vector2.ZERO, _t * 0.15, Vector2(k, k))
		draw_texture(_tex, -_tex.get_size() / 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, RADIUS * 0.6, Color(0.9, 0.85, 0.7))
	if scan >= 0.0 and not done:
		_draw_scan()
	if done:
		# The pulsating ring: a wide faint glow, a narrower one and a bright core line.
		draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(c, 0.08 + 0.06 * beat), 18.0, true)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(c, 0.2 + 0.15 * beat), 7.0, true)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(c.lightened(0.35), 0.75 + 0.25 * beat), 2.0, true)
		# Ticks round it, turning one way; three brackets further out, the other.
		var ticks := PackedVector2Array()
		for i in 36:
			var a := i * TAU / 36.0 + _t * 0.2
			var long := 9.0 if i % 3 == 0 else 4.0
			ticks.append(Vector2.from_angle(a) * (rr + 13.0))
			ticks.append(Vector2.from_angle(a) * (rr + 13.0 + long))
		draw_multiline(ticks, Color(c, 0.55), 1.5)
		for i in 3:
			var a0 := i * TAU / 3.0 - _t * 0.35
			draw_arc(Vector2.ZERO, rr + 32.0, a0, a0 + 0.9, 16, Color(c, 0.12), 8.0, true)
			draw_arc(Vector2.ZERO, rr + 32.0, a0, a0 + 0.9, 16, Color(c, 0.7), 2.0, true)
	# The charting pulse: rings of light sweeping out over the system.
	if _pulse >= 0.0:
		for k2 in 3:
			var f := _pulse / PULSE_TIME - k2 * 0.18
			if f > 0.0 and f < 1.0:
				draw_arc(Vector2.ZERO, RADIUS + f * PULSE_REACH, 0, TAU, 96, Color(c, (1.0 - f) * 0.6), 6.0 * (1.0 - f) + 2.0, true)
	var font := ThemeDB.fallback_font
	var label := "NAV BEACON  ·  CHARTED" if done else ("NAV BEACON  ·  SCANNING  %d%%" % int(scan * 100.0) if scan >= 0.0 else "NAV BEACON  ·  RIGHT-CLICK TO SCAN")
	var fs := Settings.fs("world", 20)
	var ly := (rr + 70.0) if done else (RADIUS * 1.45 + 30.0 if scan >= 0.0 else RADIUS + 34.0)
	draw_string_outline(font, Vector2(-220, ly), label, HORIZONTAL_ALIGNMENT_CENTER, 440, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(-220, ly), label, HORIZONTAL_ALIGNMENT_CENTER, 440, fs, c.lightened(0.2))


## Being scanned: a beam from the ship, a scan line sweeping up and down
## over the beacon with a band of light behind it, a ring filling round it
## as the scan goes (amber, a bright head), and its corners bracketed.
func _draw_scan() -> void:
	var c := Color(1.0, 0.75, 0.3)
	var cyan := Color(0.4, 0.95, 1.0)
	var flick := 0.75 + 0.25 * sin(_t * 23.0)
	# The beam from the ship: a glow, a core, light running along it.
	if is_instance_valid(scanner):
		var from := to_local(scanner.global_position)
		var to := from.normalized() * RADIUS * 0.9 if from.length() > 1.0 else Vector2.ZERO
		draw_line(from, to, Color(cyan, 0.12 * flick), 14.0, true)
		draw_line(from, to, Color(cyan, 0.7 * flick), 2.5, true)
		var along := to - from
		for i in 5:
			var f := fmod(_t * 1.6 + i / 5.0, 1.0)
			draw_circle(from + along * f, 4.0, Color(cyan.lightened(0.4), 0.8 * flick))
	# The scan line sweeping over the beacon, up and down (twice a second), its chord across the disc.
	var sweep := sin(_t * TAU * 0.5)
	var y := sweep * RADIUS * 0.85
	var half := sqrt(maxf(RADIUS * RADIUS - y * y, 0.0))
	for k in 6:   # (a band of light trailing it)
		var yy := y - signf(cos(_t * TAU * 0.5)) * k * 6.0
		var hh := sqrt(maxf(RADIUS * RADIUS - yy * yy, 0.0))
		draw_line(Vector2(-hh, yy), Vector2(hh, yy), Color(cyan, 0.12 * (1.0 - k / 6.0)), 6.0, true)
	draw_line(Vector2(-half, y), Vector2(half, y), Color(cyan.lightened(0.5), 0.9), 2.5, true)
	# The progress ring, filling from the top, a bright head where it's got to.
	var rr := RADIUS * 1.18
	draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(c, 0.15), 6.0, true)
	var a1 := -PI / 2.0 + TAU * scan
	draw_arc(Vector2.ZERO, rr, -PI / 2.0, a1, 64, Color(c, 0.3), 14.0, true)
	draw_arc(Vector2.ZERO, rr, -PI / 2.0, a1, 64, Color(c.lightened(0.3), 0.95), 4.0, true)
	draw_circle(Vector2.from_angle(a1) * rr, 7.0, Color(1, 1, 1, 0.9))
	# Corner brackets, closing in as it goes.
	var bs := RADIUS * (1.45 - 0.2 * scan)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := Vector2(sx, sy) * bs
			draw_polyline(PackedVector2Array([p - Vector2(sx * 22.0, 0), p, p - Vector2(0, sy * 22.0)]), Color(cyan, 0.85), 2.5, true)


## The waves (once charted): every WAVE_EVERY seconds one leaves the ring in
## a direction of its own (random - its number seeds it: no state kept),
## widening as it goes and fading fast (WAVE_TIME); behind it a nebula trail
## (_draw_trails) lingers FOAM_TIME. Its front: a glowing arc with
## holographic fringes, cyan inside and violet outside.
func _wave(k: int) -> Array:   # [direction, spread, seed 0..1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sys_id) ^ (k * 7919)
	return [rng.randf() * TAU, rng.randf_range(0.35, 0.7), rng.randf()]


func _waves_alive() -> Array:   # [[k, age]...]
	var out := []
	var now_k := floori(_t / WAVE_EVERY)
	for back in ceili((WAVE_TIME + FOAM_TIME) / WAVE_EVERY) + 1:
		var k := now_k - back
		var age := _t - k * WAVE_EVERY
		if age >= 0.0 and age <= WAVE_TIME + FOAM_TIME:
			out.append([k, age])
	return out


func _draw_waves(ci: CanvasItem, c: Color) -> void:
	var r0 := RADIUS * 1.2
	for ka in _waves_alive():
		var f: float = ka[1] / WAVE_TIME
		if f >= 1.0:
			continue
		var w := _wave(ka[0])
		var dir: float = w[0]
		var fade := pow(1.0 - f, 1.6)
		var r := r0 + f * WAVE_REACH
		var half: float = w[1] * (0.6 + 0.4 * f)
		var th := 1.0 + f * 1.5
		ci.draw_arc(Vector2.ZERO, r, dir - half, dir + half, 40, Color(c, 0.14 * fade), 44.0 * th, true)
		ci.draw_arc(Vector2.ZERO, r, dir - half, dir + half, 40, Color(c, 0.3 * fade), 16.0 * th, true)
		ci.draw_arc(Vector2.ZERO, r - 5.0 * th, dir - half * 0.9, dir + half * 0.9, 40, Color(0.35, 0.95, 1.0, 0.55 * fade), 2.5, true)
		ci.draw_arc(Vector2.ZERO, r + 5.0 * th, dir - half * 0.9, dir + half * 0.9, 40, Color(1.0, 0.45, 0.95, 0.45 * fade), 2.5, true)
		ci.draw_arc(Vector2.ZERO, r, dir - half * 0.85, dir + half * 0.85, 40, Color(c.lightened(0.6), fade), 3.0, true)


## The nebula trails: for each wave a sector of quads over the whole way it
## goes - the shader (nav_trail.gdshader) shows the gas only where the front
## has passed, and fades it. UV: x across the arc, y out along the way; the
## vertex colour: r the wave's age (of its whole life), g its seed.
func _draw_trails(ci: CanvasItem) -> void:
	var r0 := RADIUS * 1.2
	var r1 := r0 + WAVE_REACH
	var life := WAVE_TIME + FOAM_TIME
	(ci.material as ShaderMaterial).set_shader_parameter("tint", _color())
	for ka in _waves_alive():
		var w := _wave(ka[0])
		var col := Color(ka[1] / life, w[2], 0.0, 1.0)
		var cols := PackedColorArray([col, col, col, col])
		var span: float = w[1] * 1.15
		for i in TRAIL_SEGMENTS:
			var u0 := float(i) / TRAIL_SEGMENTS
			var u1 := float(i + 1) / TRAIL_SEGMENTS
			var a0: float = w[0] - span + u0 * span * 2.0
			var a1: float = w[0] - span + u1 * span * 2.0
			var d0 := Vector2.from_angle(a0)
			var d1 := Vector2.from_angle(a1)
			ci.draw_primitive(PackedVector2Array([d0 * r0, d1 * r0, d1 * r1, d0 * r1]), cols,
				PackedVector2Array([Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)]), _noise())   # (a texture: else the UVs are dropped)


## The trails' noise: soft fractal noise that tiles, made once, shared.
static var _noise_tex: NoiseTexture2D
static func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 5
		fn.seed = 1717
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 256
		_noise_tex.height = 256
		_noise_tex.seamless = true
		_noise_tex.generate_mipmaps = true
		_noise_tex.noise = fn
	return _noise_tex


## The glow: one radial gradient (white to clear), shared by every beacon.
static var _glow_tex: GradientTexture2D
static func _glow() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	return _glow_tex
