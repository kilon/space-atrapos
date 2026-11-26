class_name CetusBeast
extends SpaceMonster
## Cetus, the sea monster Poseidon sent against Andromeda - a creature of the
## monster signals (SignalSite.CREATURES). The reference art itself
## (external/images/cetus/), cut by tools/cetus_parts.py: from the top view
## the body, both pectoral fins and the tail fin; the side view whole.
## Unlike the other creatures it swims where it heads (its rig turns with its
## heading): the body bends in a travelling wave (shaders/cetus_swim.gdshader),
## the tail fin rides the bend and sweeps, the fins beat, its golden eyes glow.
## Attacks, in turn (SEQUENCE):
##   orbs   its own patterns (POOLS, denser by fight_stage): rings of breaking
##          waves, jets of bubbles from its maw, a whirl of waves, an undertow;
##   dive   it sinks into the void (its shadow sliding toward you), a ring
##          marks where you were, and it BREACHES there - the side view leaping
##          out with a burst of waves: BREACH_DAMAGE within BREACH_RADIUS.

const ART := "res://data/sprites/monster_cetus"
const SWIM_SHADER := preload("res://shaders/cetus_swim.gdshader")
const SEA := Color(0.25, 0.6, 1.0)
const FOAM := Color(0.8, 0.95, 1.0)
const GOLD := Color(1.0, 0.75, 0.3)
const SEQUENCE := ["orbs", "orbs", "dive", "orbs", "dive", "orbs"]
const POOLS := [["tidal_ring", "spout", "undertow"], ["tidal_ring", "whirl", "spout", "undertow"], ["deluge", "whirl", "spout", "tidal_ring"]]
const SINK := 0.8
const SUBMERGED := 1.6
const WARN := 1.3
const BREACH := 1.1
const BREACH_RADIUS := 230.0
const BREACH_DAMAGE := 32.0
const AMP := 34.0                   # art px of sway at the tail

var meta := {}
var art_scale := 0.4
var demo := false
var special := ""
var specials_done := {}
var _sp := 0.0
var _aim := 0.0
var _rig: Node2D
var _bodyspr: Sprite2D
var _joints := {}
var _side: Sprite2D
var _over: Node2D
var _phase := 0.0
var _attacks := 0
var _from := Vector2.ZERO           # where it dived (world)
var _to := Vector2.ZERO             # where it will breach (world)
var _breach_hit := false


func _ready() -> void:
	super()
	glow = SEA
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.45 / 1774.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	_rig.rotation = PI / 2.0   # (the art's head points left; the creature's forward is -y)
	add_child(_rig)
	var hub := _v(meta["hub"])
	_joint("fin_top", hub)
	_joint("fin_bottom", hub)
	_bodyspr = _part("body", hub)
	var m := ShaderMaterial.new()
	m.shader = SWIM_SHADER
	m.set_shader_parameter("tex_size", _bodyspr.texture.get_size())
	m.set_shader_parameter("head_x", float(meta["head_x"]) - float(meta["parts"]["body"][0]))
	m.set_shader_parameter("body_len", 1500.0)
	m.set_shader_parameter("amp", AMP)
	_bodyspr.material = m
	_rig.add_child(_bodyspr)
	_joint("tail", hub)
	# The breach: the side view, upright, hidden until it leaps.
	_side = Sprite2D.new()
	_side.texture = load(ART + "_side.png")
	_side.visible = false
	_side.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_side.top_level = true
	_side.z_index = 3
	add_child(_side)
	_over = Node2D.new()
	_over.top_level = true
	_over.z_index = 2
	_over.draw.connect(_draw_over)
	add_child(_over)


func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _part(part: String, origin: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = part
	s.texture = load(ART + "_" + part + ".png")
	s.centered = false
	s.position = _v(meta["parts"][part]) - origin
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


func _joint(part: String, hub: Vector2) -> void:
	var piv := _v(meta[part + "_pivot"])
	var j := Node2D.new()
	j.position = piv - hub
	_rig.add_child(j)
	j.add_child(_part(part, piv))
	_joints[part] = j


## The body's sideways offset (art px) at art x - the shader's curve.
func bend(x: float) -> float:
	var s := clampf((x - float(meta["head_x"])) / 1500.0, 0.0, 1.0)
	return AMP * pow(s, 1.6) * sin(s * TAU * 0.8 - _phase)


## The top view (1774 x 887 art px) - its shield is a sphere round its length.
func visual_size() -> Vector2:
	return Vector2(1774, 887) * length * 1.45 / 1774.0


## Its maw (world): the bubbles and waves come from there.
func mouth() -> Vector2:
	if meta.is_empty() or _rig == null:
		return super()
	return _rig.to_global(_v(meta["mouth"]) - _v(meta["hub"]))


func _charge() -> float:
	if demo:
		return smoothstep(0.55, 0.85, sin(_t * 0.7))
	if special != "":
		return 1.0
	if pattern == "":
		return 0.0
	return clampf(1.0 + _pt / CHARGE, 0.0, 1.0) if _pt < 0.0 else 1.0


func pattern_pool() -> Array:
	return POOLS[fight_stage()]


func _process(delta: float) -> void:
	if special != "" and not dying:
		_t += delta
		_run_special(delta)
	else:
		var was := pattern
		super(delta)
		if was == "" and pattern != "" and not dying:
			var kind: String = SEQUENCE[_attacks % SEQUENCE.size()]
			_attacks += 1
			var tgt := _target()
			if kind == "dive" and tgt != null:
				pattern = ""
				special = "dive"
				_sp = 0.0
				_breach_hit = false
				_from = _centre()
				Sfx.play_world("space/monster_roar", global_position, -6.0, 0.4)
	if _rig == null:
		return
	# Swimming: the stroke faster while it charges.
	var charge := _charge()
	_phase += delta * (2.4 + 1.6 * charge)
	(_bodyspr.material as ShaderMaterial).set_shader_parameter("phase", _phase)
	var tail_x := float(meta["tail_pivot"][0])
	var hub := _v(meta["hub"])
	_joints["tail"].position = Vector2(tail_x - hub.x, float(meta["tail_pivot"][1]) - hub.y + bend(tail_x))
	_joints["tail"].rotation = atan((bend(tail_x + 30.0) - bend(tail_x - 30.0)) / 60.0) * 1.8 + 0.12 * sin(_phase - 1.2)
	for f in ["fin_top", "fin_bottom"]:
		var sgn := -1.0 if f == "fin_top" else 1.0
		var px := float(meta[f + "_pivot"][0])
		_joints[f].position = Vector2(px - hub.x, float(meta[f + "_pivot"][1]) - hub.y + bend(px))
		_joints[f].rotation = sgn * (0.16 * sin(_phase * 0.9) + 0.1 * charge)
	if _over:
		_over.global_position = _centre()
		_over.queue_redraw()
	queue_redraw()


func _centre() -> Vector2:
	return enemy.global_position if enemy and is_instance_valid(enemy) else global_position


## The dive: sink, slide under toward you (submerged), a ring where you were,
## breach there.
func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	var t1 := SINK
	var t2 := SINK + SUBMERGED
	var t3 := t2 + WARN
	var t4 := t3 + BREACH
	if _sp < t1:
		_rig.modulate.a = 1.0 - _sp / SINK * 0.9
	elif _sp < t2:
		_rig.modulate.a = 0.1
		if tgt and enemy and is_instance_valid(enemy):   # sliding under toward you
			enemy.global_position = enemy.global_position.move_toward(tgt.global_position, 700.0 * delta)
			_to = tgt.global_position
	elif _sp < t3:
		_rig.modulate.a = 0.0   # (the ring is fixed: where you were)
		if enemy and is_instance_valid(enemy):
			enemy.global_position = _to
	elif _sp < t4:
		var u := (_sp - t3) / BREACH
		if not _breach_hit:
			_breach_hit = true
			_side.visible = true
			Sfx.play_world("space/monster_roar", _to, 0.0, 0.1)
			if tgt and tgt.global_position.distance_to(_to) < BREACH_RADIUS + float(tgt.get("hit_radius")) * 0.5:
				tgt.take_damage(BREACH_DAMAGE, _to, enemy)
			for i in 16:   # a burst of breaking waves, rolling out from the ring
				var d := Vector2.from_angle(i * TAU / 16.0)
				_shot(d * 160.0, SEA, "wave", _to + d * BREACH_RADIUS)
		# The leap: the side view rising out of the void and falling back.
		var arc := sin(u * PI)
		var k := length * 1.3 / 1604.0
		_side.global_position = _to + Vector2(0, -arc * length * 0.5)
		_side.scale = Vector2.ONE * k * (0.6 + 0.5 * arc)
		_side.rotation = lerpf(-0.35, 0.45, u)
		_side.modulate.a = clampf(arc * 2.0, 0.0, 1.0)
		_rig.modulate.a = clampf((u - 0.6) / 0.4, 0.0, 1.0)
	else:
		_side.visible = false
		_rig.modulate.a = 1.0
		specials_done["dive"] = int(specials_done.get("dive", 0)) + 1
		special = ""
		_cool = PAUSE


## Above everything (relative to it): the dive's ripples, its shadow under the
## void, the breach ring.
func _draw_over() -> void:
	if special != "dive":
		return
	var o := _over.global_position
	var t2 := SINK + SUBMERGED
	var t3 := t2 + WARN
	if _sp < SINK:
		for k in 3:
			var r := length * (0.3 + 0.25 * k) * (_sp / SINK)
			_over.draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(FOAM, 0.5 * (1.0 - _sp / SINK)), 3.0, true)
	elif _sp < t2:
		_over.draw_set_transform(Vector2.ZERO, (_to - o).angle(), Vector2(1.0, 0.45))
		_over.draw_circle(Vector2.ZERO, length * 0.6, Color(0.0, 0.05, 0.12, 0.35))
		_over.draw_set_transform(Vector2.ZERO)
	elif _sp < t3:
		var u := (_sp - t2) / WARN
		var c := _to - o
		_over.draw_circle(c, BREACH_RADIUS, Color(SEA, 0.08 + 0.12 * u))
		_over.draw_arc(c, BREACH_RADIUS, 0, TAU, 64, Color(FOAM, 0.4 + 0.5 * u), 4.0, true)
		_over.draw_arc(c, BREACH_RADIUS * u, 0, TAU, 64, Color(FOAM, 0.6), 2.0, true)


## On the body: its golden eyes glowing (blazing as it charges).
func _draw() -> void:
	if meta.is_empty() or _rig == null:
		return
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	for e in meta["eyes"]:
		var p := to_local(_rig.to_global(_v(e) - _v(meta["hub"])))
		draw_circle(p, (10.0 + 8.0 * charge) * art_scale * 2.5, Color(GOLD, (0.15 + 0.08 * pulse + 0.3 * charge) * _rig.modulate.a))


## Its own bullet patterns: waves and bubbles.
func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	match name:
		"tidal_ring":   # rings of breaking waves rolling out, each with a gap
			for k in 3:
				if _crossed(k * 0.6):
					var n := 18 + st * 2
					var gap := randi() % n
					for i in n:
						if absi(i - gap) > 1:
							_shot(Vector2.from_angle(i * TAU / n + k * 0.17) * 130.0 * spd, SEA, "wave")
			return 1.6
		"spout":   # jets of bubbles from the maw, three bursts, aimed
			_emit -= delta
			while _emit <= 0.0 and _pt < 1.5:
				_emit += 0.07
				_shot(Vector2.from_angle(aim + randf_range(-0.12, 0.12)) * 215.0 * spd, FOAM, "bubble")
			return 1.6
		"undertow":   # bubbles flung wide that curl back toward the middle
			for k in 2:
				if _crossed(k * 0.7):
					for i in 14:
						var side := -1.0 if i < 7 else 1.0
						var o := _shot(Vector2.from_angle(aim + side * (0.9 + (i % 7) * 0.12)) * 170.0 * spd, FOAM, "bubble")
						o.curve = -side * 0.6
			return 1.5
		"whirl":   # a whirl of waves, two arms turning
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.2:
				_emit += 0.12
				_spin += 0.3
				for arm in 2:
					_shot(Vector2.from_angle(_spin + arm * PI) * 150.0 * spd, SEA, "wave").curve = 0.25
			return 2.3
		"deluge":   # rings of waves with jets of bubbles between them
			for k in 4:
				if _crossed(k * 0.5):
					var gap := randi() % 22
					for i in 22:
						if absi(i - gap) > 1:
							_shot(Vector2.from_angle(i * TAU / 22.0) * 125.0, SEA, "wave")
					for j in 4:
						_shot(Vector2.from_angle(aim + (j - 1.5) * 0.08) * 220.0, FOAM, "bubble")
			return 2.1
	return super(name, delta, aim)


func calm() -> void:
	super()
	if _side:
		_side.visible = false
	if _rig:
		_rig.modulate.a = 1.0


func death_throes() -> void:
	special = ""
	if _side:
		_side.visible = false
	if _rig:
		_rig.modulate.a = 1.0
	await super()
