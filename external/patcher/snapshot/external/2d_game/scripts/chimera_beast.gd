class_name ChimeraBeast
extends SpaceMonster
## The Chimera - a lion in front, a goat's head rising from its back, a
## serpent for a tail - a creature of the monster signals
## (SignalSite.CREATURES). The reference art itself (external/images/chimera/),
## cut by tools/chimera_parts.py: from the top view its body, the lion's head,
## the goat's head, the serpent tail and three legs; the front view whole.
## It stays upright on screen as in the art: the lion snarls, the goat tosses
## its horns, the serpent sways and strikes, the legs paw. Each head fights its
## own way - the lion with fire, the goat with embers, the serpent with venom.
## Attacks, in turn (SEQUENCE) - the breath and the ram aim at you while it
## winds up, then commit:
##   orbs     its own patterns (POOLS, denser by fight_stage);
##   breath   the lion draws breath (BREATH_WINDUP s, a faint cone following you)
##            and breathes fire, the cone sweeping across (BREATH_SWEEP rad over
##            BREATH_TIME s): BREATH_DPS while you're in it;
##   ram      the goat lowers its horns (an arrow following you) and the beast
##            charges where you were (RAM_SPEED), RAM_DAMAGE, embers in its wake;
##   rampage  it rears up (the front view rising over it) and all three heads
##            fire at once: a ring of flame, a burst of embers, venom at you.

const ART := "res://data/sprites/monster_chimera"
const FIRE := Color(1.0, 0.45, 0.1)
const EMBER := Color(1.0, 0.8, 0.3)
const VENOM := Color(0.55, 1.0, 0.25)
const SEQUENCE := ["orbs", "breath", "orbs", "ram", "orbs", "rampage", "breath", "orbs", "ram"]
const POOLS := [["lion_roar", "goat_embers", "serpent_spit"], ["three_heads", "lion_roar", "serpent_spit", "goat_embers"], ["chimera_storm", "three_heads", "lion_roar", "serpent_spit"]]
const LEGS := ["front_left_leg", "front_right_leg", "back_right_leg"]
const BREATH_WINDUP := 0.8
const BREATH_TIME := 1.6
const BREATH_LENGTH := 760.0
const BREATH_HALF := 0.24
const BREATH_SWEEP := 0.9
const BREATH_DPS := 40.0
const RAM_WINDUP := 0.75
const RAM_TIME := 0.65
const RAM_SPEED := 1100.0
const RAM_DAMAGE := 28.0
const RAMPAGE_WINDUP := 0.9
const RAMPAGE_TIME := 1.6

var meta := {}
var art_scale := 0.4
var demo := false
var special := ""
var specials_done := {}
var _sp := 0.0
var _aim := 0.0
var _side := 1.0                    # which way the breath sweeps
var _ram_hit := false
var _rig: Node2D
var _body: Node2D
var _joints := {}
var _front: Sprite2D
var _over: Node2D
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
	_joint("serpent", hub)
	_joint("back_right_leg", hub)
	_body.add_child(_part("body", hub))
	_joint("goat", hub)
	_joint("front_left_leg", hub)
	_joint("front_right_leg", hub)
	_joint("lion", hub)
	_front = Sprite2D.new()
	_front.texture = load(ART + "_front.png")
	_front.visible = false
	_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_front.top_level = true
	_front.z_index = 3
	add_child(_front)
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


## The top view (1536 x 1024 art px), upright.
func visual_size() -> Vector2:
	return Vector2(1536, 1024) * length * 1.5 / 1536.0


## The jaws of "lion", "goat" or "serpent" (world).
func jaw(head: String) -> Vector2:
	if meta.is_empty() or _rig == null:
		return global_position
	var j: Node2D = _joints[head]
	return j.to_global(_v(meta["mouths"][head]) - _v(meta[head + "_pivot"]))


func mouth() -> Vector2:
	return jaw("lion")


func _centre() -> Vector2:
	return enemy.global_position if enemy and is_instance_valid(enemy) else global_position


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
			if kind != "orbs" and tgt != null:
				pattern = ""
				special = kind
				_sp = 0.0
				_ram_hit = false
				_side = -_side
				_aim = (tgt.global_position - (jaw("lion") if kind == "breath" else _centre())).angle()
				Sfx.play_world("space/monster_roar", global_position, -4.0, 0.25)
	if _over:
		_over.global_position = _centre()   # (drawn relative to it: far out, world numbers lose precision)
		_over.queue_redraw()
	if _rig == null:
		return
	_rig.global_rotation = 0.0
	var charge := _charge()
	_body.position = Vector2(sin(_t * 0.8) * 3.0, sin(_t * 1.6) * 4.0 + charge * 8.0) / art_scale
	_body.scale = Vector2.ONE * (1.0 + 0.012 * sin(_t * 1.9))
	var breathing := special == "breath" and _sp >= BREATH_WINDUP
	_joints["lion"].rotation = 0.05 * sin(_t * 1.3) + (0.06 * sin(_t * 25.0) if breathing else 0.0)
	_joints["goat"].rotation = 0.08 * sin(_t * 1.7 + 1.0) + 0.06 * pow(maxf(0.0, sin(_t * 3.1)), 8.0) - (0.18 if special == "ram" and _sp < RAM_WINDUP else 0.0)
	_joints["serpent"].rotation = 0.12 * sin(_t * 1.2) + 0.05 * sin(_t * 3.3) + 0.08 * charge * sin(_t * 9.0)
	var i := 0
	for l in LEGS:
		_joints[l].rotation = 0.05 * sin(_t * 1.4 + i * 1.3) * (1.0 if i % 2 == 0 else -1.0)
		i += 1
	queue_redraw()


func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"breath":
			if _sp < BREATH_WINDUP:
				if tgt:
					_aim = (tgt.global_position - jaw("lion")).angle() - _side * BREATH_SWEEP * 0.5
			else:
				if tgt:
					var rel: Vector2 = tgt.global_position - jaw("lion")
					if rel.length() < BREATH_LENGTH and absf(wrapf(rel.angle() - _breath_angle(), -PI, PI)) < BREATH_HALF:
						tgt.take_damage(BREATH_DPS * delta, tgt.global_position, enemy, "heat")
				if _sp > BREATH_WINDUP + BREATH_TIME:
					_end_special()
		"ram":
			if _sp < RAM_WINDUP:
				if tgt:
					_aim = (tgt.global_position - _centre()).angle()
			elif _sp < RAM_WINDUP + RAM_TIME:
				if enemy and is_instance_valid(enemy):
					enemy.global_position += Vector2.from_angle(_aim) * RAM_SPEED * delta
					if randf() < 0.5:   # embers in its wake
						_shot(Vector2.from_angle(_aim + PI + randf_range(-0.8, 0.8)) * 90.0, EMBER, "ember", jaw("goat"))
					if tgt and not _ram_hit and tgt.global_position.distance_to(enemy.global_position) < length * 0.3 + float(tgt.get("hit_radius")):
						_ram_hit = true
						tgt.take_damage(RAM_DAMAGE, enemy.global_position, enemy)
			else:
				_end_special()
		"rampage":
			var k := length * 1.45 / 1146.0
			var rise := smoothstep(0.0, RAMPAGE_WINDUP, _sp)
			var fall := 1.0 - smoothstep(RAMPAGE_WINDUP + RAMPAGE_TIME - 0.5, RAMPAGE_WINDUP + RAMPAGE_TIME, _sp)
			_front.visible = true
			_front.global_position = global_position + Vector2(0, -length * 0.2 * rise)
			_front.scale = Vector2.ONE * k * (0.85 + 0.2 * rise)
			_front.modulate.a = rise * fall
			_rig.modulate.a = 1.0 - 0.75 * rise * fall
			for w in 2:
				if _sp >= RAMPAGE_WINDUP + w * 0.7 and _sp - delta < RAMPAGE_WINDUP + w * 0.7:
					var c := global_position
					var a0 := (tgt.global_position - c).angle() if tgt else 0.0
					var n := 18 + 2 * fight_stage()
					var gap := randi() % n
					for i in n:   # the lion: a ring of flame (with a gap)
						if absi(i - gap) > 1 and absi(i - gap) != n - 1:
							_shot(Vector2.from_angle(a0 + i * TAU / n + w * 0.17) * 150.0, FIRE, "flame", c)
					for i in 12:   # the goat: a burst of embers
						_shot(Vector2.from_angle(randf() * TAU) * randf_range(100.0, 180.0), EMBER, "ember", c + Vector2(-length * 0.2, -length * 0.15)).curve = randf_range(-0.5, 0.5)
					for i in 3:   # the serpent: venom at you
						_shot(Vector2.from_angle(a0 + (i - 1) * 0.12) * 230.0, VENOM, "venom", c + Vector2(length * 0.25, -length * 0.15))
			if _sp >= RAMPAGE_WINDUP + RAMPAGE_TIME:
				_front.visible = false
				_rig.modulate.a = 1.0
				_end_special()


## The breath's angle now: sweeping across from where it aimed.
func _breath_angle() -> float:
	var u := clampf((_sp - BREATH_WINDUP) / BREATH_TIME, 0.0, 1.0)
	return _aim + _side * BREATH_SWEEP * u


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	special = ""
	_cool = PAUSE


## Above everything (relative to it): the breath's cone, the ram's arrow.
func _draw_over() -> void:
	var o := _over.global_position
	if special == "breath":
		var from := jaw("lion") - o
		var a := _breath_angle()
		if _sp < BREATH_WINDUP:
			var k := _sp / BREATH_WINDUP
			for s in [-1.0, 1.0]:
				_over.draw_line(from, from + Vector2.from_angle(a + s * BREATH_HALF) * BREATH_LENGTH, Color(1.0, 0.45, 0.1, 0.15 + 0.35 * k), 2.0, true)
			# (and where it will sweep to)
			_over.draw_arc(from, BREATH_LENGTH, minf(a, a + _side * BREATH_SWEEP) - BREATH_HALF, maxf(a, a + _side * BREATH_SWEEP) + BREATH_HALF, 24, Color(1.0, 0.45, 0.1, 0.2 + 0.3 * k), 2.0, true)
		else:
			var u := _sp - BREATH_WINDUP
			var fade := 1.0 - smoothstep(BREATH_TIME - 0.3, BREATH_TIME, u)
			var pts := PackedVector2Array([from])
			for i in 9:
				pts.append(from + Vector2.from_angle(a - BREATH_HALF + 2.0 * BREATH_HALF * i / 8.0) * BREATH_LENGTH * (0.92 + 0.08 * sin(_t * 20.0 + i)))
			_over.draw_colored_polygon(pts, Color(1.0, 0.35, 0.05, 0.22 * fade))
			for i in 18:
				var d := fposmod(u * 900.0 + i * BREATH_LENGTH / 18.0, BREATH_LENGTH)
				var spread := sin(i * 2.3 + _t * 7.0) * BREATH_HALF * 0.8
				var p := from + Vector2.from_angle(a + spread) * d
				_over.draw_circle(p, 14.0 + d * 0.11, Color(1.0, 0.55 - d / BREATH_LENGTH * 0.35, 0.1, 0.45 * fade * (1.0 - d / BREATH_LENGTH * 0.5)))
			_over.draw_circle(from, 24.0, Color(1.0, 0.9, 0.6, 0.85 * fade))
	if special == "ram" and _sp < RAM_WINDUP:
		var c0 := _centre() - o
		var dir := Vector2.from_angle(_aim)
		var reach := RAM_SPEED * RAM_TIME
		var col := Color(1.0, 0.75, 0.3, 0.2 + 0.4 * _sp / RAM_WINDUP)
		_over.draw_line(c0 + dir * length * 0.3, c0 + dir * reach, Color(col, col.a * 0.35), 70.0, true)
		_over.draw_line(c0 + dir * length * 0.3, c0 + dir * reach, col, 4.0, true)
		var tip := c0 + dir * reach
		_over.draw_colored_polygon(PackedVector2Array([tip + dir * 40.0, tip + dir.orthogonal() * 30.0, tip - dir.orthogonal() * 30.0]), col)


## On the body: each head's jaws glowing in its colour as it gathers.
func _draw() -> void:
	if meta.is_empty() or _rig == null:
		return
	var charge := _charge()
	if charge <= 0.0:
		return
	for h in [["lion", FIRE], ["goat", EMBER], ["serpent", VENOM]]:
		var p := to_local(jaw(h[0]))
		draw_circle(p, (10.0 + 18.0 * charge) * art_scale * 3.0, Color(h[1], 0.22 * charge * _rig.modulate.a))
		draw_circle(p, (4.0 + 6.0 * charge) * art_scale * 3.0, Color(1.0, 0.95, 0.7, 0.7 * charge * _rig.modulate.a))


## Its own bullet patterns: each head its own.
func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	match name:
		"lion_roar":   # the lion roars rings of flame, a gap in each
			for k in 3:
				if _crossed(k * 0.55):
					var n := 16 + st * 2
					var gap := randi() % n
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) != n - 1:
							_shot(Vector2.from_angle(i * TAU / n + k * 0.2) * 150.0 * spd, FIRE, "flame", jaw("lion"))
			return 1.7
		"goat_embers":   # the goat bleats out bursts of embers, curling
			for k in 3:
				if _crossed(k * 0.45):
					for i in 18 + st * 4:
						_shot(Vector2.from_angle(randf() * TAU) * randf_range(110.0, 190.0) * spd, EMBER, "ember", jaw("goat")).curve = randf_range(-0.6, 0.6)
			return 1.4
		"serpent_spit":   # the serpent strikes: streams of venom curving in on you
			_emit -= delta
			while _emit <= 0.0 and _pt < 1.4:
				_emit += 0.1
				var from := jaw("serpent")
				var tgt := _target()
				var a: float = (tgt.global_position - from).angle() if tgt else aim
				for s in [-1.0, 1.0]:
					_shot(Vector2.from_angle(a + s * 0.45) * 205.0 * spd, VENOM, "venom", from).curve = -s * 0.38
			return 1.5
		"three_heads":   # each head in turn: the lion's fan of flame, the goat's embers, the serpent's venom
			for r in 3:
				if _crossed(r * 0.75):
					for i in 5:
						_shot(Vector2.from_angle(aim + (i - 2) * 0.17) * 190.0 * spd, FIRE, "flame", jaw("lion"))
				if _crossed(r * 0.75 + 0.25):
					for i in 10:
						_shot(Vector2.from_angle(randf() * TAU) * randf_range(120.0, 170.0), EMBER, "ember", jaw("goat"))
				if _crossed(r * 0.75 + 0.5):
					var from := jaw("serpent")
					var tgt := _target()
					var a: float = (tgt.global_position - from).angle() if tgt else aim
					for i in 3:
						_shot(Vector2.from_angle(a + (i - 1) * 0.1) * 230.0 * spd, VENOM, "venom", from)
			return 2.3
		"chimera_storm":   # all three heads spinning their fire, embers and venom round
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.2:
				_emit += 0.12
				_spin += 0.27
				_shot(Vector2.from_angle(_spin) * 165.0 * spd, FIRE, "flame", jaw("lion"))
				_shot(Vector2.from_angle(_spin + TAU / 3.0) * 165.0 * spd, EMBER, "ember", jaw("goat"))
				_shot(Vector2.from_angle(_spin + 2.0 * TAU / 3.0) * 165.0 * spd, VENOM, "venom", jaw("serpent"))
			return 2.3
	return super(name, delta, aim)


func calm() -> void:
	super()
	if _front:
		_front.visible = false
	if _rig:
		_rig.modulate.a = 1.0


func death_throes() -> void:
	special = ""
	if _front:
		_front.visible = false
	if _rig:
		_rig.modulate.a = 1.0
	await super()
