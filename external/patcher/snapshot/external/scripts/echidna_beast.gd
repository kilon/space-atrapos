class_name EchidnaBeast
extends SpaceMonster
## Echidna, the mother of monsters - half woman, half serpent - a creature of
## the monster signals (SignalSite.CREATURES). The reference art itself
## (external/images/echidna/), cut by tools/echidna_parts.py: from the top
## view her body and coils, both arms and the crescent of her tail; the front
## view whole. She stays upright on screen as in the art: her arms reach and
## claw, her tail sways, she breathes, her eyes burn gold as she gathers.
## Attacks, in turn (SEQUENCE):
##   orbs    her own patterns (POOLS, denser by fight_stage): fangs of venom,
##           a coil of serpents closing round you, a hissing spiral, a nest of
##           her brood loosed every way;
##   brood   she rears up (the front view rising over her, BROOD_WINDUP s) and
##           looses her brood - serpents that slither after you;
##   venom   she raises her arms (VENOM_WINDUP s, three marks following you)
##           and spits three globs of venom at where you were: each bursts into
##           a pool that burns POOL_DPS while you're in it, POOL_TIME s.

const ART := "res://data/sprites/monster_echidna"
const SCALES := Color(0.35, 0.4, 0.95)
const VENOM := Color(0.55, 1.0, 0.25)
const GOLD := Color(1.0, 0.75, 0.3)
const SEQUENCE := ["orbs", "brood", "orbs", "venom", "orbs", "brood", "venom"]
const POOLS := [["fangs", "coil", "hiss"], ["fangs", "coil", "nest", "hiss"], ["coil", "nest", "fangs", "hiss"]]
const BROOD_WINDUP := 1.0
const BROOD_TIME := 1.6
const VENOM_WINDUP := 0.8
const GLOB_SPEED := 620.0
const POOL_RADIUS := 150.0
const POOL_TIME := 4.0
const POOL_DPS := 22.0

var meta := {}
var art_scale := 0.4
var demo := false
var special := ""
var specials_done := {}
var _sp := 0.0
var _aim := 0.0
var _rig: Node2D
var _body: Node2D
var _joints := {}
var _front: Sprite2D
var _over: Node2D
var _attacks := 0
var _globs: Array = []              # [{at, to}] (world) in flight
var pools: Array = []               # [{at, t}] (world) burning
var _marks: Array = []              # the venom's three targets (world)


func _ready() -> void:
	super()
	glow = VENOM
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.5 / 1312.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	var hub := _v(meta["hub"])
	_body = Node2D.new()
	_rig.add_child(_body)
	_joint("tail", hub)
	_body.add_child(_part("body", hub))
	_joint("left_arm", hub)
	_joint("right_arm", hub)
	# Rearing: the front view, upright, hidden until she calls her brood.
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


## The top view (1199 x 1312 art px), upright.
func visual_size() -> Vector2:
	return Vector2(1199, 1312) * length * 1.5 / 1312.0


## Her mouth (world): the venom and her brood come from there.
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
			if kind != "orbs" and tgt != null:
				pattern = ""
				special = kind
				_sp = 0.0
				_aim = (tgt.global_position - mouth()).angle()
				Sfx.play_world("space/monster_roar", global_position, -4.0, 0.3)
	_run_venom(delta)
	if _rig == null:
		return
	_rig.global_rotation = 0.0
	var charge := _charge()
	var reach := charge * (1.0 if special != "venom" else 2.0)
	_joints["left_arm"].rotation = 0.07 * sin(_t * 1.3) + 0.1 * reach
	_joints["right_arm"].rotation = -0.07 * sin(_t * 1.3 + 0.8) - 0.1 * reach
	_joints["tail"].rotation = 0.09 * sin(_t * 0.9) + 0.04 * sin(_t * 2.3)
	_body.scale = Vector2(1.0, 1.0 + 0.012 * sin(_t * 1.6))
	if _over:
		_over.global_position = global_position
		_over.queue_redraw()
	queue_redraw()


## Her brood (rearing up, the front view) and her venom (three globs).
func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"brood":
			var k := length * 1.4 / 1389.0
			var rise := smoothstep(0.0, BROOD_WINDUP, _sp)
			var fall := 1.0 - smoothstep(BROOD_WINDUP + BROOD_TIME - 0.5, BROOD_WINDUP + BROOD_TIME, _sp)
			_front.visible = true
			_front.global_position = global_position + Vector2(0, -length * 0.25 * rise)
			_front.scale = Vector2.ONE * k * (0.85 + 0.2 * rise)
			_front.modulate.a = rise * fall
			_rig.modulate.a = 1.0 - 0.75 * rise * fall
			if _crossed_sp(BROOD_WINDUP, delta):
				Sfx.play_world("space/monster_roar", global_position, 0.0, 0.25)
				var n := 8 + 2 * fight_stage()
				var a := (tgt.global_position - mouth()).angle() if tgt else _aim
				for i in n:
					var o := _shot(Vector2.from_angle(a + (i - (n - 1) / 2.0) * 0.28) * randf_range(115.0, 145.0), SCALES, "serpent")
					o.home = 0.8
					o.wobble = 40.0
			if _sp >= BROOD_WINDUP + BROOD_TIME:
				_front.visible = false
				_rig.modulate.a = 1.0
				_end_special()
		"venom":
			if _sp < VENOM_WINDUP and tgt:
				var p := tgt.global_position
				_marks = [p, p + Vector2.from_angle(_t * 2.0) * 190.0, p + Vector2.from_angle(_t * 2.0 + PI) * 190.0]
			if _crossed_sp(VENOM_WINDUP, delta):
				for m in _marks:
					_globs.append({"at": mouth(), "to": m})
				Sfx.play_world("space/monster_roar", global_position, -8.0, 0.5)
			if _sp >= VENOM_WINDUP + 0.6:
				_marks = []
				_end_special()


## Was _sp below `at` a frame ago and isn't now (the moment a step fires).
func _crossed_sp(at: float, delta: float) -> bool:
	return _sp >= at and _sp - delta < at


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	special = ""
	_cool = PAUSE


## The globs in flight and the pools burning (going on after the special).
func _run_venom(delta: float) -> void:
	for g in _globs.duplicate():
		var at: Vector2 = g["at"]
		var to: Vector2 = g["to"]
		if at.distance_to(to) <= GLOB_SPEED * delta:
			_globs.erase(g)
			pools.append({"at": to, "t": 0.0})
			Effects.spark(to, VENOM)
		else:
			g["at"] = at + (to - at).normalized() * GLOB_SPEED * delta
	var tgt := _target()
	for p in pools.duplicate():
		p["t"] += delta
		if p["t"] > POOL_TIME:
			pools.erase(p)
		elif tgt and tgt.global_position.distance_to(p["at"]) < POOL_RADIUS:
			tgt.take_damage(POOL_DPS * delta, p["at"], enemy)


## Above everything (relative to her): the venom's marks, globs and pools.
func _draw_over() -> void:
	var o := _over.global_position
	for p in pools:
		var t: float = p["t"]
		var a := clampf(t / 0.25, 0.0, 1.0) * clampf((POOL_TIME - t) / 0.6, 0.0, 1.0)
		var c: Vector2 = p["at"] - o
		_over.draw_circle(c, POOL_RADIUS, Color(0.2, 0.5, 0.05, 0.35 * a))
		_over.draw_circle(c, POOL_RADIUS * 0.7, Color(VENOM, 0.18 * a))
		_over.draw_arc(c, POOL_RADIUS, 0, TAU, 48, Color(VENOM, 0.7 * a), 3.0, true)
		for i in 6:   # bubbling
			var b := c + Vector2.from_angle(i * 1.7 + t * 0.6) * POOL_RADIUS * (0.25 + 0.5 * fposmod(t * 0.4 + i * 0.23, 1.0))
			_over.draw_circle(b, 6.0 + 4.0 * sin(t * 5.0 + i), Color(0.8, 1.0, 0.5, 0.5 * a))
	for m in _marks:
		var u := clampf(_sp / VENOM_WINDUP, 0.0, 1.0)
		var c: Vector2 = m - o
		_over.draw_arc(c, POOL_RADIUS, 0, TAU, 48, Color(VENOM, 0.3 + 0.5 * u), 2.5, true)
		_over.draw_arc(c, POOL_RADIUS * u, 0, TAU, 48, Color(VENOM, 0.5), 1.5, true)
	for g in _globs:
		var c: Vector2 = g["at"] - o
		_over.draw_circle(c, 26.0, Color(VENOM, 0.25))
		_over.draw_circle(c, 15.0, Color(VENOM, 0.95))
		_over.draw_circle(c + Vector2(-4, -4), 5.0, Color(0.95, 1.0, 0.85, 0.95))


## On her body: her golden eyes burning as she gathers.
func _draw() -> void:
	if meta.is_empty() or _rig == null:
		return
	var charge := _charge()
	for e in meta["eyes"]:
		var p := to_local(_rig.to_global(_v(e) - _v(meta["hub"])))
		draw_circle(p, (8.0 + 10.0 * charge) * art_scale * 2.5, Color(GOLD, (0.08 + 0.4 * charge) * _rig.modulate.a))


## Her own bullet patterns: venom and her brood.
func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	match name:
		"fangs":   # two streams of venom curving in on you from either side, like fangs
			_emit -= delta
			while _emit <= 0.0 and _pt < 1.4:
				_emit += 0.09
				for s in [-1.0, 1.0]:
					_shot(Vector2.from_angle(aim + s * 0.55) * 200.0 * spd, VENOM, "venom").curve = -s * 0.42
			return 1.5
		"coil":   # a ring of serpents round you, closing in - find the gap
			for k in 2:
				if _crossed(k * 1.1):
					var tgt := _target()
					if tgt == null:
						continue
					var c := tgt.global_position
					var n := 16 + st * 2
					var gap := randi() % n
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) != n - 1:
							var d := Vector2.from_angle(i * TAU / n)
							_shot(-d * 105.0 * spd, SCALES, "serpent", c + d * 470.0)
			return 2.4
		"hiss":   # a hissing spiral of venom, three arms
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.0:
				_emit += 0.1
				_spin += 0.24
				for arm in 3:
					_shot(Vector2.from_angle(_spin + arm * TAU / 3.0) * 160.0 * spd, VENOM, "venom")
			return 2.1
		"nest":   # her brood loosed every way, turning to find you
			for k in 2:
				if _crossed(k * 0.8):
					for i in 10 + st * 2:
						var o := _shot(Vector2.from_angle(randf() * TAU) * randf_range(100.0, 140.0), SCALES, "serpent")
						o.home = 0.45
			return 1.8
	return super(name, delta, aim)


func calm() -> void:
	super()
	_marks = []
	if _front:
		_front.visible = false
	if _rig:
		_rig.modulate.a = 1.0


func death_throes() -> void:
	special = ""
	_marks = []
	_globs = []
	pools = []
	if _front:
		_front.visible = false
	if _rig:
		_rig.modulate.a = 1.0
	await super()
