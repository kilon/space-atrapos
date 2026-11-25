class_name CharybdisBeast
extends SpaceMonster
## Charybdis, the whirlpool that swallows the sea three times a day and spews
## it out again - a creature of the monster signals (SignalSite.CREATURES).
## The reference art itself (external/images/charybdis/charybdis_top.png, cut
## by tools/charybdis_parts.py), whole: it turns slowly as a whirlpool does, its
## vortex spinning inside the ring of teeth (the eye fastest) and the
## tentacles and spray at its rim writhing (shaders/charybdis_whirl.gdshader).
## Attacks, in turn (SEQUENCE):
##   orbs      its own patterns (POOLS, denser by fight_stage): spiral arms of
##             waves, the undertow (bubbles from all round, drawn into its maw),
##             its tentacles lashing waves, rings of waves whirling;
##   whirlpool it churns (WHIRL_WINDUP s) and drags everything toward its maw
##             (PULL x your top speed, less further out - fly away at full
##             speed and you just get out), currents
##             spiralling in; reach its maw and it bites: MAW_DAMAGE, and you're
##             thrown clear;
##   spew      it swells (SPEW_WINDUP s) and spews the swallowed sea back out:
##             waves and bubbles bursting every way, three times.

const ART := "res://data/sprites/monster_charybdis"
const WHIRL_SHADER := preload("res://shaders/charybdis_whirl.gdshader")
const SEA := Color(0.25, 0.6, 1.0)
const FOAM := Color(0.8, 0.95, 1.0)
const SEQUENCE := ["orbs", "whirlpool", "orbs", "spew", "orbs", "whirlpool", "spew"]
const POOLS := [["maelstrom", "undertow", "lash"], ["maelstrom", "undertow", "lash", "whirl_rings"], ["whirl_rings", "maelstrom", "undertow", "lash"]]
const TURN := 0.12                  # rad/s: the whole whirlpool turning
const WHIRL_WINDUP := 0.8
const WHIRL_TIME := 4.0
const PULL := 0.85                  # x the dragged ship's top speed, toward its maw (full speed away just gets out)
const PULL_REACH := 2000.0
const MAW_DAMAGE := 30.0
const SPEW_WINDUP := 0.9
const SPEW_TIME := 1.6

var meta := {}
var art_scale := 0.4
var demo := false
var special := ""
var specials_done := {}
var _sp := 0.0
var _rig: Node2D
var _spr: Sprite2D
var _mat: ShaderMaterial
var _over: Node2D
var _attacks := 0
var _eye := 0.0                     # rad the vortex's eye has turned
var _writhe := 0.0
var _churn := 0.0
var _bit := 0.0                     # cooldown after a bite


func _ready() -> void:
	super()
	glow = SEA
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.5 / 1352.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	_spr = Sprite2D.new()
	_spr.texture = load(ART + ".png")
	_spr.centered = false
	var centre := _v(meta["centre"]) - _v(meta["origin"])   # (texture px)
	_spr.position = -centre
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat = ShaderMaterial.new()
	_mat.shader = WHIRL_SHADER
	_mat.set_shader_parameter("tex_size", _spr.texture.get_size())
	_mat.set_shader_parameter("centre", centre)
	_mat.set_shader_parameter("vortex", float(meta["vortex"]))
	_mat.set_shader_parameter("reach", float(meta["reach"]))
	_spr.material = _mat
	_rig.add_child(_spr)
	_over = Node2D.new()
	_over.top_level = true
	_over.z_index = 2
	_over.draw.connect(_draw_over)
	add_child(_over)


func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## The picture (1352 x 1082 art px).
func visual_size() -> Vector2:
	return Vector2(1352, 1082) * length * 1.5 / 1352.0


## Its maw: the eye of the vortex - everything comes from there.
func mouth() -> Vector2:
	return global_position


## World px: the ring of teeth.
func maw_radius() -> float:
	return float(meta.get("maw", 255)) * art_scale


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
			if kind != "orbs" and _target() != null:
				pattern = ""
				special = kind
				_sp = 0.0
				Sfx.play_world("space/monster_roar", global_position, -3.0, 0.2)
	_bit = maxf(0.0, _bit - delta)
	if _rig == null:
		return
	var charge := _charge()
	var whirling := special == "whirlpool" and _sp >= WHIRL_WINDUP
	_churn = move_toward(_churn, 1.0 if whirling else (0.4 * charge), delta * 1.5)
	_rig.global_rotation += TURN * (1.0 + 2.0 * _churn) * delta
	_eye += delta * (1.4 + 4.0 * _churn)
	_writhe += delta * (1.8 + 2.0 * _churn)
	var swell := 0.0
	if special == "spew":
		swell = smoothstep(0.0, SPEW_WINDUP, _sp) * (1.0 - smoothstep(SPEW_WINDUP, SPEW_WINDUP + 0.3, _sp))
	_rig.scale = Vector2.ONE * art_scale * (1.0 + 0.015 * sin(_t * 1.3) + 0.08 * swell)
	_mat.set_shader_parameter("spin", _eye)
	_mat.set_shader_parameter("writhe", _writhe)
	_mat.set_shader_parameter("churn", _churn)
	if _over:
		_over.global_position = global_position
		_over.queue_redraw()
	queue_redraw()


func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"whirlpool":
			if _sp >= WHIRL_WINDUP:
				# Everything near drawn in, spiralling (you can fly out at full speed).
				for s in _pulled():
					var rel: Vector2 = global_position - s.global_position
					var d := rel.length()
					if d < PULL_REACH and d > 1.0:
						var k := 1.0 - d / PULL_REACH * 0.4
						var pull: float = PULL * float(s.get("max_speed") if s.get("max_speed") != null else 400.0) * k
						s.global_position += (rel / d * pull + rel.orthogonal() / d * pull * 0.3) * delta
				if tgt and _bit <= 0.0 and tgt.global_position.distance_to(global_position) < maw_radius() * 0.75:
					_bit = 1.5
					tgt.take_damage(MAW_DAMAGE, global_position, enemy)
					Effects.spark(tgt.global_position, FOAM)
					Sfx.play_world("space/monster_roar", global_position, 0.0, 0.5)
					tgt.global_position = global_position + (tgt.global_position - global_position).normalized() * maw_radius() * 2.2
				# The currents carry bubbles in from all round.
				if fmod(_sp, 0.25) < delta:
					for i in 6:
						var a := randf() * TAU
						var o := _shot(Vector2.from_angle(a + PI * 0.6) * 120.0, FOAM, "bubble", global_position + Vector2.from_angle(a) * maw_radius() * 3.2)
						o.home = 0.0
						o.curve = 0.5
			if _sp >= WHIRL_WINDUP + WHIRL_TIME:
				_end_special()
		"spew":
			for w in 3:
				if _sp >= SPEW_WINDUP + w * 0.45 and _sp - delta < SPEW_WINDUP + w * 0.45:
					Sfx.play_world("space/monster_roar", global_position, -2.0, 0.6)
					var n := 20 + 2 * fight_stage()
					var off := randf() * TAU
					for i in n:
						_shot(Vector2.from_angle(off + i * TAU / n) * 160.0, SEA, "wave", global_position + Vector2.from_angle(off + i * TAU / n) * maw_radius() * 0.8)
					for i in 10:
						_shot(Vector2.from_angle(randf() * TAU) * randf_range(120.0, 220.0), FOAM, "bubble", global_position + Vector2.from_angle(randf() * TAU) * maw_radius() * 0.5)
			if _sp >= SPEW_WINDUP + SPEW_TIME:
				_end_special()


## Who the whirlpool drags: you, and any ship near.
func _pulled() -> Array:
	var out := []
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p and p.is_alive():
		out.append(p)
	for n in get_tree().get_nodes_in_group("neutrals"):
		if n.is_alive():
			out.append(n)
	return out


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	special = ""
	_cool = PAUSE


## Above everything (relative to it): the whirlpool's currents spiralling in;
## the spew's swell.
func _draw_over() -> void:
	if special == "whirlpool":
		var on := smoothstep(0.0, WHIRL_WINDUP, _sp) * (1.0 - smoothstep(WHIRL_WINDUP + WHIRL_TIME - 0.5, WHIRL_WINDUP + WHIRL_TIME, _sp))
		for arm in 6:
			var pts := PackedVector2Array()
			for i in 24:
				var u := float(i) / 23.0
				var r := lerpf(maw_radius() * 0.9, PULL_REACH * 0.85, u)
				var a := arm * TAU / 6.0 - _t * 2.2 + u * 3.2
				pts.append(Vector2.from_angle(a) * r)
			_over.draw_polyline(pts, Color(FOAM, 0.28 * on), 3.0, true)
		_over.draw_arc(Vector2.ZERO, maw_radius() * 0.75, 0, TAU, 48, Color(1.0, 0.3, 0.2, 0.35 * on), 3.0, true)
	elif special == "spew" and _sp < SPEW_WINDUP:
		var u := _sp / SPEW_WINDUP
		_over.draw_arc(Vector2.ZERO, maw_radius() * (0.5 + 0.6 * u), 0, TAU, 48, Color(FOAM, 0.2 + 0.5 * u), 4.0, true)


## Its eye glowing as it gathers.
func _draw() -> void:
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	draw_circle(Vector2.ZERO, maw_radius() * (0.25 + 0.15 * charge), Color(0.4, 0.8, 1.0, 0.06 + 0.04 * pulse + 0.2 * charge))


## Its own bullet patterns: waves and bubbles, round and round.
func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	match name:
		"maelstrom":   # spiral arms of waves, turning
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.2:
				_emit += 0.12
				_spin_p += 0.21
				for arm in 3 + st:
					var a := _spin_p + arm * TAU / (3 + st)
					_shot(Vector2.from_angle(a) * 150.0 * spd, SEA, "wave", global_position + Vector2.from_angle(a) * maw_radius() * 0.6).curve = 0.3
			return 2.3
		"undertow":   # bubbles from all round you, drawn in toward its maw
			for k in 2:
				if _crossed(k * 0.9):
					var tgt := _target()
					if tgt == null:
						continue
					var n := 14 + st * 2
					var gap := randi() % n
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) != n - 1:
							var d := Vector2.from_angle(i * TAU / n)
							var from := tgt.global_position + d * 520.0
							_shot((global_position - from).normalized() * 110.0 * spd, FOAM, "bubble", from)
			return 2.2
		"lash":   # its tentacles lash: a fan of waves from each of eight
			for k in 2:
				if _crossed(k * 0.7):
					for t in 8:
						var a := _rig.global_rotation + t * TAU / 8.0 + k * 0.2
						var from := global_position + Vector2.from_angle(a) * float(meta["reach"]) * art_scale * 0.8
						for i in 3:
							_shot(Vector2.from_angle(a + (i - 1) * 0.25) * 170.0 * spd, SEA, "wave", from)
			return 1.6
		"whirl_rings":   # rings of waves whirling out, each with a gap
			for k in 3:
				if _crossed(k * 0.6):
					var n := 18 + st * 2
					var gap := randi() % n
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) != n - 1:
							var o := _shot(Vector2.from_angle(i * TAU / n + k * 0.3) * 135.0 * spd, SEA, "wave", global_position + Vector2.from_angle(i * TAU / n) * maw_radius() * 0.7)
							o.curve = 0.35
			return 2.0
	return super(name, delta, aim)


var _spin_p := 0.0


func death_throes() -> void:
	special = ""
	await super()
