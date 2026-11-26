class_name JumpGate
extends Node2D
## A jump gate to a neighbouring system: the painted gate ring (data/sprites/
## gate_*, cut from external/images/stargate_1.png by tools/extract_sprites.py)
## around a turning energy vortex, a soft glow behind it in the colour of the
## destination's owner. Fly into it to jump (Main._check_gates); flash() plays
## the burst a ship makes going through. Without the sprites: drawn as before
## (a ring of pylons around swirling arcs).

var target := ""            # destination system id
var target_name := ""
var accent := Color(0.5, 0.8, 1.0)
const RADIUS := 230.0
## Fly within this distance to use the gate.
const USE_RADIUS := 260.0
## The ring sprite's half-width (sheet px) is drawn at RADIUS * RING_SIZE.
const RING_SIZE := 1.2
const VORTEX_SPIN := -0.22      # rad/s (the swirl's arms trail clockwise)
const FRAME_TIME := 0.7         # s per vortex frame (cross-faded)
const BURST_TIME := 1.2         # s

var _t := 0.0
var _burst := -1.0              # time since flash(), < 0 = none
var _ring: Texture2D
var _ring_lit: Texture2D
var _vortex: Array[Texture2D] = []
var _sparkle: Texture2D
var _burst_tex: Texture2D


static func available() -> bool:
	return ProcArt.has_sprite("gate_ring_lit")


func _ready() -> void:
	Sfx.loop_at("space/gate_hum", self, -4.0, 1100.0)
	add_to_group("gates")
	z_index = -3
	_t = randf() * 10.0
	if available():
		_ring = ProcArt.sprite("gate_ring")
		_ring_lit = ProcArt.sprite("gate_ring_lit")
		for i in 3:
			var v := ProcArt.sprite("gate_vortex%d" % (i + 1))
			if v:
				_vortex.append(v)
		_sparkle = ProcArt.sprite("gate_sparkle")
		_burst_tex = ProcArt.sprite("gate_burst")
	var enabler := VisibleOnScreenEnabler2D.new()
	enabler.rect = Rect2(-Vector2.ONE * 650, Vector2.ONE * 1300)   # (the burst reaches 2.6 x RADIUS)
	add_child(enabler)


func _process(delta: float) -> void:
	_t += delta
	if _burst >= 0.0:
		_burst += delta
		if _burst > BURST_TIME:
			_burst = -1.0
	queue_redraw()


## A ship goes through: a ring of light bursts out of the gate.
func flash() -> void:
	_burst = 0.0


## The sprites' scale: the ring's half-width at RADIUS * RING_SIZE.
func _k() -> float:
	return RADIUS * RING_SIZE / (_ring_lit.get_width() * 0.5)


func _draw() -> void:
	if _ring_lit and not _vortex.is_empty():
		_draw_painted()
	else:
		_draw_procedural()
	var font := ThemeDB.fallback_font
	var label := "GATE  ›  " + target_name.to_upper()
	var ly := RADIUS * (RING_SIZE * 0.92 if _ring_lit else 1.0) + 60.0
	draw_string_outline(font, Vector2(-250, ly), label, HORIZONTAL_ALIGNMENT_CENTER, 500, Settings.fs("world", 22), 6, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(-250, ly), label, HORIZONTAL_ALIGNMENT_CENTER, 500, Settings.fs("world", 22), accent.lightened(0.35))


func _draw_painted() -> void:
	var k := _k()
	var pulse := 0.5 + 0.5 * sin(_t * 1.6)
	# The owner's colour: a soft glow behind the ring.
	for i in 4:
		draw_circle(Vector2.ZERO, RADIUS * (1.35 - i * 0.1), Color(accent, 0.035 + 0.02 * pulse))
	# The vortex: a little bigger than the opening (the rim covers its edge),
	# turning, its frames cross-faded.
	var n := _vortex.size()
	var f := _t / FRAME_TIME
	var a := int(f) % n
	var b := (a + 1) % n
	var vk := k * (1.1 + 0.015 * sin(_t * 2.3))
	var ang := _t * VORTEX_SPIN
	_draw_centred(_vortex[a], ang, vk, Color.WHITE)
	_draw_centred(_vortex[b], ang, vk, Color(1, 1, 1, f - floorf(f)))
	# The core: a twinkling star.
	if _sparkle:
		var sk := k * (0.55 + 0.15 * sin(_t * 3.1))
		_draw_centred(_sparkle, sin(_t * 0.5) * 0.3, sk, Color(1, 1, 1, 0.6 + 0.4 * pulse))
	# The ring: idle under the powered one, its lights breathing.
	if _ring:
		_draw_centred(_ring, 0.0, k, Color.WHITE)
	_draw_centred(_ring_lit, 0.0, k, Color(1, 1, 1, 0.6 + 0.4 * pulse))
	# A ship going through: the burst ring flies out and fades (the sheet
	# draws it as a tilted ellipse: stretched round here, the gate faces you).
	if _burst >= 0.0 and _burst_tex:
		var p := _burst / BURST_TIME
		var w := RADIUS * (1.0 + 1.6 * p) * 2.0
		var sx := w / _burst_tex.get_width()
		var sy := w * 0.9 / _burst_tex.get_height()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(sx, sy))
		draw_texture(_burst_tex, -_burst_tex.get_size() * 0.5, Color(1, 1, 1, 1.0 - p * p))
		draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2.ZERO, RADIUS * 0.9, Color(0.8, 0.95, 1.0, 0.5 * (1.0 - p) * (1.0 - p)))


func _draw_centred(tex: Texture2D, angle: float, scale_: float, mod: Color) -> void:
	draw_set_transform(Vector2.ZERO, angle, Vector2(scale_, scale_))
	draw_texture(tex, -tex.get_size() * 0.5, mod)
	draw_set_transform(Vector2.ZERO)


func _draw_procedural() -> void:
	var r := RADIUS
	# Energy field: swirling arcs and a bright core.
	for i in 6:
		draw_circle(Vector2.ZERO, r * (0.95 - i * 0.12), Color(accent, 0.05 + i * 0.015))
	for k in 10:
		var a0 := _t * (0.6 + k * 0.08) + k * 0.7
		var rr := r * (0.25 + 0.07 * k)
		draw_arc(Vector2.ZERO, rr, a0, a0 + 1.6 + 0.2 * sin(_t + k), 24, Color(accent.lightened(0.4), 0.35), 3.0, true)
	draw_circle(Vector2.ZERO, r * 0.16 + 4.0 * sin(_t * 3.0), Color(1, 1, 1, 0.75))
	if _burst >= 0.0:
		draw_arc(Vector2.ZERO, r * (1.0 + 1.6 * _burst / BURST_TIME), 0, TAU, 64, Color(accent.lightened(0.5), 1.0 - _burst / BURST_TIME), 6.0, true)
	# Ring and pylons.
	draw_arc(Vector2.ZERO, r, 0, TAU, 96, Color(0.2, 0.22, 0.28), 26.0, true)
	draw_arc(Vector2.ZERO, r, 0, TAU, 96, Color(0.55, 0.58, 0.65), 16.0, true)
	draw_arc(Vector2.ZERO, r - 6.0, 0, TAU, 96, Color(accent, 0.9), 3.0, true)
	for i in 8:
		var d := Vector2.from_angle(i * TAU / 8.0 + 0.2)
		var p := d * r
		draw_rect(Rect2(p - Vector2(14, 14), Vector2(28, 28)), Color(0.3, 0.32, 0.38))
		var on := fmod(_t * 1.2 + i * 0.125, 1.0) < 0.35
		draw_circle(p, 7.0, accent.lightened(0.3) if on else Color(accent, 0.4))
