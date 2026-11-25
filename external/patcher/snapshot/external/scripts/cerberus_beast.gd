class_name CerberusBeast
extends SpaceMonster
## Cerberus, the three-headed hound - a creature of the monster signals
## (SignalSite.CREATURES). The reference art itself (external/images/cerberus/),
## cut into parts by tools/cerberus_parts.py - the body (with the centre head,
## the temple medallion and the shoulder plates), the scorpion-like tail, the
## two side heads and the four legs, each running on under the body at its
## joint - and assembled here as a rig that moves:
##   - the side heads snap and snarl, out of step with each other;
##   - the legs paw, the tail lashes;
##   - he breathes; the six eyes glow;
##   - he stays upright on screen as in the art.
## Attacks, in turn (SEQUENCE) - the breath and the pounce aim at you while he
## winds up, then commit:
##   orbs    his own bullet patterns (POOLS, denser by fight_stage): fireballs and
##           embers from each jaw in turn, and the souls of Hades - pale wailing
##           ghosts that drift after you;
##   breath  all three heads rear back (0.8 s, faint cones following you), then
##           breathe fire for BREATH_TIME s along those cones - the centre one
##           at you, the side ones fanned out: get out of the cones;
##   pounce  he crouches (0.7 s, an arrow following you), then leaps at where
##           you were (POUNCE_SPEED), POUNCE_DAMAGE on contact.
## Dying: SpaceMonster.death_throes.

const ART := "res://data/sprites/monster_cerberus"
const FIRE := Color(1.0, 0.45, 0.1)
const EMBER := Color(1.0, 0.8, 0.3)
const JAWS := ["left_head", "body", "right_head"]
const SEQUENCE := ["orbs", "breath", "orbs", "pounce", "breath", "orbs", "pounce"]
const BREATH_WINDUP := 0.8
const BREATH_TIME := 1.4
const BREATH_LENGTH := 720.0
const BREATH_HALF := 0.2            # rad: each cone's half-angle
const BREATH_FAN := 0.45            # rad: the side heads' cones, off the centre one
const BREATH_DPS := 38.0
const POUNCE_WINDUP := 0.7
const POUNCE_TIME := 0.6
const POUNCE_SPEED := 1150.0
const POUNCE_DAMAGE := 26.0

var meta := {}
var art_scale := 0.5
var demo := false                   # the Library: no target, he winds up now and then
var _rig: Node2D
var _body: Node2D
var _joints := {}                   # part -> pivot node
var _fx: Node2D
var _over: Node2D                   # above everything, world space: breath cones, pounce arrow
var special := ""
var specials_done := {}
var _sp := 0.0
var _aim := 0.0                     # world angle of the centre cone / the pounce
var _pounce_hit := false
var _attacks := 0


func _ready() -> void:
	super()
	glow = FIRE
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.5 / 1536.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	var hub := _v(meta["hub"])
	_body = Node2D.new()
	_rig.add_child(_body)
	# The tail behind the body, the legs and heads in front.
	_joint("tail", hub)
	_body.add_child(_part("body", hub))
	for p in ["left_leg", "right_leg", "front_left_leg", "front_right_leg", "left_head", "right_head"]:
		_joint(p, hub)
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	_body.add_child(_fx)
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
	_body.add_child(j)
	j.add_child(_part(part, piv))
	_joints[part] = j


## The art (1536 x 1024), upright.
func visual_size() -> Vector2:
	return Vector2(1536, 1024) * length * 1.5 / 1536.0


## One of his jaws (0 left, 1 centre, 2 right), in world space.
func jaw(i: int) -> Vector2:
	if meta.is_empty() or _body == null:
		return super.mouth()
	var part: String = JAWS[i]
	var p := _v(meta["mouths"][part])
	if _joints.has(part):   # (a side head turns at its neck)
		var piv := _v(meta[part + "_pivot"])
		p = piv + (p - piv).rotated(_joints[part].rotation)
	return _rig.to_global(p - _v(meta["hub"]) + _body.position)


func mouth() -> Vector2:
	return jaw(1)


func _charge() -> float:
	if demo:
		return smoothstep(0.55, 0.85, sin(_t * 0.7))
	if special != "":
		return 1.0
	if pattern == "":
		return 0.0
	return clampf(1.0 + _pt / CHARGE, 0.0, 1.0) if _pt < 0.0 else 1.0


## Fire from each jaw in turn.
func _orb(vel: Vector2, col: Color, style := "orb") -> Orb:
	var o := super(vel, col, style)
	if col == ORB_COLOR or col == ORB_COLOR_2:
		o.color = FIRE if col == ORB_COLOR else EMBER
	o.global_position = jaw(orbs_fired % 3)
	return o


# --- His own bullet patterns: fireballs and embers from three jaws ----------------

const POOLS := [["three_heads", "souls", "hellfire", "triple_spiral"], ["three_heads", "firestorm", "souls", "triple_spiral", "hellfire"], ["inferno", "souls", "firestorm", "triple_spiral", "three_heads"]]

func pattern_pool() -> Array:
	return POOLS[fight_stage()]


func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	match name:
		"three_heads":   # each head in turn barks a fan of fireballs at you
			for r in 3:
				for h in 3:
					if _crossed(r * 0.6 + h * 0.18):
						var from := jaw(h)
						var a: float = (_target().global_position - from).angle() if _target() else aim
						for i in 5:
							_shot(Vector2.from_angle(a + (i - 2) * 0.16) * 190.0 * spd, FIRE, "flame", from)
			return 1.9
		"hellfire":   # bursts of embers scattering and curling
			for k in 3:
				if _crossed(k * 0.5):
					for i in 22 + st * 6:
						var o := _shot(Vector2.from_angle(randf() * TAU) * randf_range(110.0, 200.0) * spd, EMBER, "ember", jaw(randi() % 3))
						o.curve = randf_range(-0.5, 0.5)
			return 1.5
		"triple_spiral":   # an arm of fire from each jaw, turning
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.2:
				_emit += 0.11
				_spin += 0.29
				for h in 3:
					_shot(Vector2.from_angle(_spin + h * TAU / 3.0) * 165.0 * spd, FIRE, "flame", jaw(h))
			return 2.3
		"firestorm":   # all three jaws pouring wobbling fire at you
			_emit -= delta
			while _emit <= 0.0 and _pt < 1.6:
				_emit += 0.09
				var h := randi() % 3
				var o := _shot(Vector2.from_angle(aim + randf_range(-0.35, 0.35)) * 215.0, FIRE, "flame", jaw(h))
				o.wobble = 70.0
			return 1.7
		"souls":   # the souls of Hades pour out of his jaws and drift after you
			for k in 3:
				if _crossed(k * 0.5):
					for h in 3:
						for i in 2 + st:
							var a := aim + randf_range(-1.4, 1.4)
							var o := _shot(Vector2.from_angle(a) * randf_range(95.0, 130.0) * spd, Color(0.5, 1.0, 0.85), "ghost", jaw(h))
							o.home = 0.55
			return 1.4
		"inferno":   # rings of embers from every jaw, with fireballs aimed between
			for k in 4:
				if _crossed(k * 0.5):
					for h in 3:
						for i in 14:
							_shot(Vector2.from_angle(i * TAU / 14.0 + k * 0.2 + h) * 140.0, EMBER, "ember", jaw(h))
					_shot(Vector2.from_angle(aim) * 220.0, FIRE, "flame")
			return 2.1
	return super(name, delta, aim)


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
			if kind != "orbs" and tgt != null:
				pattern = ""
				special = kind
				_sp = 0.0
				_pounce_hit = false
				_aim = (tgt.global_position - _centre()).angle()
				if kind == "pounce":
					Sfx.play_world("space/monster_roar", global_position, -4.0, 0.25)
	if _over:
		_over.global_position = _centre()   # (drawn relative to him: far out, world numbers lose precision)
		_over.queue_redraw()
	if _rig == null:
		return
	_rig.global_rotation = 0.0
	var charge := _charge()
	_body.position = Vector2(sin(_t * 0.8) * 3.0, sin(_t * 1.6) * 4.0 + charge * 8.0) / art_scale
	_body.scale = Vector2.ONE * (1.0 + 0.012 * sin(_t * 1.9))
	# Heads: snapping, out of step; rearing back (outward) as he winds up.
	var snap := func(ph: float) -> float: return 0.07 * sin(_t * 2.1 + ph) + 0.05 * pow(maxf(0.0, sin(_t * 3.7 + ph * 2.0)), 8.0)
	_joints["left_head"].rotation = snap.call(0.0) + 0.16 * charge
	_joints["right_head"].rotation = -snap.call(1.7) - 0.16 * charge
	# Legs pawing, the tail lashing.
	_joints["left_leg"].rotation = 0.06 * sin(_t * 1.4)
	_joints["right_leg"].rotation = -0.06 * sin(_t * 1.4 + 1.2)
	_joints["front_left_leg"].rotation = 0.05 * sin(_t * 1.4 + 2.0) - 0.06 * charge
	_joints["front_right_leg"].rotation = -0.05 * sin(_t * 1.4 + 3.1) + 0.06 * charge
	_joints["tail"].rotation = 0.12 * sin(_t * 1.1) + 0.05 * sin(_t * 2.9)
	_fx.queue_redraw()
	queue_redraw()


func _centre() -> Vector2:
	return enemy.global_position if enemy and is_instance_valid(enemy) else global_position


## The three cones: [from (world), angle] - the centre jaw at the aim, the side
## jaws fanned out.
func _cones() -> Array:
	return [[jaw(0), _aim - BREATH_FAN], [jaw(1), _aim], [jaw(2), _aim + BREATH_FAN]]


func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"breath":
			if _sp < BREATH_WINDUP:
				if tgt:
					_aim = (tgt.global_position - jaw(1)).angle()
			else:
				if tgt:
					for c in _cones():
						var rel: Vector2 = tgt.global_position - c[0]
						if rel.length() < BREATH_LENGTH and absf(wrapf(rel.angle() - c[1], -PI, PI)) < BREATH_HALF:
							tgt.take_damage(BREATH_DPS * delta, tgt.global_position, enemy, "heat")
							break
				if _sp > BREATH_WINDUP + BREATH_TIME:
					_end_special()
		"pounce":
			if _sp < POUNCE_WINDUP:
				if tgt:
					_aim = (tgt.global_position - _centre()).angle()
			elif _sp < POUNCE_WINDUP + POUNCE_TIME:
				if enemy and is_instance_valid(enemy):
					enemy.global_position += Vector2.from_angle(_aim) * POUNCE_SPEED * delta
					if tgt and not _pounce_hit and tgt.global_position.distance_to(enemy.global_position) < length * 0.3 + float(tgt.get("hit_radius")):
						_pounce_hit = true
						tgt.take_damage(POUNCE_DAMAGE, enemy.global_position, enemy)
			else:
				_end_special()


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	special = ""
	_cool = PAUSE


## Above everything, in world space: the breath's cones (faint while he aims,
## then fire) and the pounce's arrow.
func _draw_over() -> void:
	var o := _over.global_position   # (points made relative to him: far out, world numbers lose precision)
	if special == "breath":
		var firing := _sp >= BREATH_WINDUP
		for c in _cones():
			var from: Vector2 = c[0] - o
			var a: float = c[1]
			if not firing:
				var k := _sp / BREATH_WINDUP
				for side in [-1.0, 1.0]:
					_over.draw_line(from, from + Vector2.from_angle(a + side * BREATH_HALF) * BREATH_LENGTH, Color(1.0, 0.45, 0.1, 0.15 + 0.35 * k), 2.0, true)
			else:
				var u := _sp - BREATH_WINDUP
				var fade := 1.0 - smoothstep(BREATH_TIME - 0.3, BREATH_TIME, u)
				var pts := PackedVector2Array([from])
				for i in 9:
					pts.append(from + Vector2.from_angle(a - BREATH_HALF + 2.0 * BREATH_HALF * i / 8.0) * BREATH_LENGTH * (0.92 + 0.08 * sin(_t * 20.0 + i)))
				_over.draw_colored_polygon(pts, Color(1.0, 0.35, 0.05, 0.22 * fade))
				# Billows of flame rolling out along the cone.
				for i in 18:
					var d := fposmod(u * 900.0 + i * BREATH_LENGTH / 18.0, BREATH_LENGTH)
					var spread := sin(i * 2.3 + _t * 7.0) * BREATH_HALF * 0.8
					var p := from + Vector2.from_angle(a + spread) * d
					var r := 14.0 + d * 0.11
					_over.draw_circle(p, r, Color(1.0, 0.55 - d / BREATH_LENGTH * 0.35, 0.1, 0.45 * fade * (1.0 - d / BREATH_LENGTH * 0.5)))
				_over.draw_circle(from, 22.0, Color(1.0, 0.9, 0.6, 0.85 * fade))
	if special == "pounce" and _sp < POUNCE_WINDUP:
		var c0 := _centre() - o
		var dir := Vector2.from_angle(_aim)
		var reach := POUNCE_SPEED * POUNCE_TIME
		var col := Color(1.0, 0.4, 0.1, 0.2 + 0.4 * _sp / POUNCE_WINDUP)
		_over.draw_line(c0 + dir * length * 0.3, c0 + dir * reach, Color(col, col.a * 0.35), 60.0, true)
		_over.draw_line(c0 + dir * length * 0.3, c0 + dir * reach, col, 4.0, true)
		var tip := c0 + dir * reach
		_over.draw_colored_polygon(PackedVector2Array([tip + dir * 40.0, tip + dir.orthogonal() * 30.0, tip - dir.orthogonal() * 30.0]), col)


## Dying: stop whatever he was doing.
func death_throes() -> void:
	special = ""
	await super()


## On the body, in art px: six glowing eyes; the jaws glowing as he winds up.
func _draw_fx() -> void:
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var hub := _v(meta["hub"])
	for e in meta["eyes"]:
		var p := _v(e) - hub
		_fx.draw_circle(p, 16.0 + 10.0 * charge, Color(1.0, 0.25, 0.05, 0.1 + 0.08 * pulse + 0.25 * charge))
	if charge > 0.0:
		for i in 3:
			var m := _rig.to_local(jaw(i)) - _body.position
			for k in 3:
				_fx.draw_circle(m, (12.0 + 30.0 * charge) * (1.6 - k * 0.4), Color(FIRE, 0.12 + 0.1 * k))
			_fx.draw_circle(m, 6.0 + 10.0 * charge, Color(1.0, 0.9, 0.6, 0.85))


func _draw() -> void:
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	for k in 5:
		draw_circle(Vector2.ZERO, length * (0.7 - k * 0.1), Color(FIRE, (0.01 + 0.006 * pulse + 0.02 * charge) * (k + 1) * 0.6))
