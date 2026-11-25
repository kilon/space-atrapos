class_name HydraBeast
extends SpaceMonster
## The Hydra of Lerna, the many-headed serpent - a creature of the monster
## signals (SignalSite.CREATURES). The reference art itself
## (external/images/hydra/), cut by tools/hydra_parts.py: from the top view
## the knot of its coils and its eight heads; the front view whole. It stays
## upright on screen as in the art; its heads sway and weave, each out of step,
## and every one of them fires from its own jaws.
## Cut off a head and two grow back: every PORTION of its hull lost, the head
## nearest you is severed (a burst of venom from the stump) and a double head
## (HydraHead) bursts out of the stump and keeps round the Hydra, spitting from both jaws - at most MAX_DOUBLE at once.
## They can't be targeted or hurt (Enemy.untouchable; out of the "enemies"
## group, so shots, targeting and the boss bar pass them by): they die only
## with the Hydra. The severed head grows back REGROW s later.
## Attacks, in turn (SEQUENCE):
##   orbs    its own patterns (POOLS, denser by fight_stage): every head in turn
##           spitting along its own neck, volleys of fangs from all the heads at
##           you, drifting clouds of poison, a storm turning round all eight;
##   bite    the head nearest you draws back (BITE_WINDUP s) and strikes at
##           where you were (BITE_REACH), BITE_DAMAGE if it catches you - and
##           spits a fan of fangs as it strikes;
##   breath  it rears up out of the waves (the front view rising over it) and
##           breathes poison: rings of miasma rolling out, a gap in each.

const ART := "res://data/sprites/monster_hydra"
const SCALES := Color(0.3, 0.45, 0.95)
const VENOM := Color(0.55, 1.0, 0.25)
const POISON := Color(0.4, 0.8, 0.2)
const GOLD := Color(1.0, 0.8, 0.3)
const SEQUENCE := ["orbs", "bite", "orbs", "breath", "orbs", "bite", "bite", "breath"]
const POOLS := [["eight_heads", "volley", "miasma"], ["eight_heads", "volley", "miasma", "storm"], ["storm", "volley", "eight_heads", "miasma"]]
const PORTION := 1.0 / 12.0         # of its hull: lose this much and a head is cut (and a double head grows)
const MAX_DOUBLE := 12
const DOUBLE_HULL := 0.1            # a double head's hull: this much of the Hydra's
const REGROW := 6.0
const BITE_WINDUP := 0.55
const BITE_STRIKE := 0.18
const BITE_HOLD := 0.15
const BITE_BACK := 0.4
const BITE_REACH := 300.0           # world px the head darts out at most
const BITE_RADIUS := 95.0
const BITE_DAMAGE := 24.0
const BREATH_WINDUP := 0.9
const BREATH_TIME := 1.8

var meta := {}
var art_scale := 0.4
var demo := false
var special := ""
var specials_done := {}
var severed := {}                   # head -> seconds until it grows back
var heads_severed := 0
var _sp := 0.0
var _aim := 0.0
var _rig: Node2D
var _body: Node2D
var _joints := {}
var _base := {}                     # head -> its joint's rest position (art px)
var _front: Sprite2D
var _over: Node2D
var _attacks := 0
var _biter := ""
var _bite_to := Vector2.ZERO        # where it strikes (world)
var _bite_hit := false
var _cuts := 0                      # PORTIONs of its hull lost so far
var double_heads: Array = []        # its double heads (Enemy ships) alive


func _ready() -> void:
	super()
	glow = VENOM
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.5 / 1536.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	var hub := _v(meta["hub"])
	_body = Node2D.new()
	_rig.add_child(_body)
	_body.add_child(_part("body", hub))
	for h in meta["heads"]:
		_joint(h, hub)
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
	_base[part] = j.position


## The top view (1536 x 1024 art px), upright.
func visual_size() -> Vector2:
	return Vector2(1536, 1024) * length * 1.5 / 1536.0


## The heads still on their necks.
func heads() -> Array:
	return (meta.get("heads", []) as Array).filter(func(h): return not severed.has(h))


## Head `h`'s jaws (world).
func jaw(h: String) -> Vector2:
	var j: Node2D = _joints[h]
	var piv := _v(meta[h + "_pivot"])
	return j.to_global(_v(meta["mouths"][h]) - piv)


## Which way head `h` faces (world angle): from its neck to its jaws.
func facing(h: String) -> float:
	return (jaw(h) - _joints[h].global_position).angle()


func mouth() -> Vector2:
	if meta.is_empty() or _rig == null:
		return super()
	var hs := heads()
	return jaw(hs[orbs_fired % hs.size()]) if not hs.is_empty() else global_position


## The head nearest `p` (world).
func nearest_head(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for h in heads():
		var d := jaw(h).distance_to(p)
		if d < best_d:
			best = h
			best_d = d
	return best


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
			if kind != "orbs" and tgt != null and not heads().is_empty():
				pattern = ""
				special = kind
				_sp = 0.0
				_bite_hit = false
				_biter = nearest_head(tgt.global_position)
				Sfx.play_world("space/monster_roar", global_position, -5.0, 0.35)
	if _rig == null:
		return
	_rig.global_rotation = 0.0
	_run_heads(delta)
	if _over:
		_over.global_position = global_position
		_over.queue_redraw()
	queue_redraw()


## The heads weaving; cut off past each SEVER_AT; growing back.
func _run_heads(delta: float) -> void:
	var charge := _charge()
	var i := 0
	for h in meta["heads"]:
		var j: Node2D = _joints[h]
		if not (special == "bite" and h == _biter):
			j.position = _base[h] + Vector2(sin(_t * 1.1 + i * 1.3), cos(_t * 0.9 + i * 0.7)) * 6.0
			j.rotation = 0.08 * sin(_t * 1.5 + i * 0.8) + 0.05 * charge * sin(_t * 9.0 + i)
		i += 1
	# A head cut for every PORTION of hull lost (the one nearest you), growing back.
	if enemy and is_instance_valid(enemy) and not dying and enemy.max_hull > 0.0:
		var lost := int((1.0 - enemy.hull / enemy.max_hull) / PORTION)
		if lost > _cuts and enemy.is_alive():
			_cuts += 1   # (one a frame: a big hit cuts several, one after another)
			var tgt := _target()
			var h := nearest_head(tgt.global_position if tgt else global_position + Vector2(0, 400))
			if h != "":
				_sever(h)
	for h in severed.keys():
		severed[h] -= delta
		var j: Node2D = _joints[h]
		if severed[h] <= 0.0:
			severed.erase(h)
			j.visible = true
			j.scale = Vector2.ONE * 0.2
			j.create_tween().tween_property(j, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Sfx.play_world("space/monster_roar", global_position, -6.0, 0.5)


func _sever(h: String) -> void:
	var at := jaw(h)
	var stump: Vector2 = _joints[h].global_position
	severed[h] = REGROW
	heads_severed += 1
	_joints[h].visible = false
	if special == "bite" and h == _biter:
		_end_special()
	Effects.explosion(at, 1.0)
	for i in 10:   # venom bursting from the stump
		_shot(Vector2.from_angle(i * TAU / 10.0) * 150.0, VENOM, "venom", stump)
	_grow_double(stump, h)


## Two heads where one was cut: a double head (HydraHead), its own ship,
## keeping its place round the Hydra (Enemy.leader).
func _grow_double(at: Vector2, h: String) -> void:
	double_heads = double_heads.filter(func(d): return is_instance_valid(d) and d.is_alive())
	if double_heads.size() >= MAX_DOUBLE or enemy == null or not is_instance_valid(enemy):
		GameLog.post("You cut off one of the Hydra's heads - it will grow back", "combat")
		return
	var main: Node = enemy
	while main != null and not main.has_method("spawn_ship"):
		main = main.get_parent()
	if main == null:
		return
	var d: Node2D = main.spawn_ship(at, "hydra_head", {}, "pirates")
	d.leader = enemy
	d._led = true
	d.max_hull = enemy.max_hull * DOUBLE_HULL
	d.hull = d.max_hull
	# Not to be fought: no target, no health bar, no loot - it dies with the Hydra.
	d.untouchable = true
	d.damage_mult = enemy.damage_mult
	d.boss = false
	d.click_radius = 0.0
	d.remove_from_group(&"enemies")
	if d.died.is_connected(main._on_ship_died):
		d.died.disconnect(main._on_ship_died)
	d.leader_slot = (at - global_position).angle()
	d.hunting = true
	d.home = at
	double_heads.append(d)
	GameLog.post("You cut off one of the Hydra's heads - and two grow in its place (%d)" % double_heads.size(), "combat")


func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"bite":
			var j: Node2D = _joints.get(_biter)
			if j == null or severed.has(_biter):
				_end_special()
				return
			var base: Vector2 = _base[_biter]
			var t1 := BITE_WINDUP
			var t2 := t1 + BITE_STRIKE
			var t3 := t2 + BITE_HOLD
			var t4 := t3 + BITE_BACK
			if _sp < t1:   # drawing back, its aim following you
				if tgt:
					var from := jaw(_biter)
					_bite_to = from + (tgt.global_position - from).limit_length(BITE_REACH)
				var u := _sp / t1
				j.position = base - _dart_dir(base) * 40.0 * u
				j.rotation = 0.15 * sin(_sp * 30.0) * u
			elif _sp < t3:
				var u := clampf((_sp - t1) / BITE_STRIKE, 0.0, 1.0)
				j.position = base + _dart(base) * u
				j.rotation = 0.0
				if u >= 1.0 and not _bite_hit:
					_bite_hit = true
					Sfx.play_world("space/monster_roar", _bite_to, -3.0, 0.6)
					if tgt and tgt.global_position.distance_to(jaw(_biter)) < BITE_RADIUS + float(tgt.get("hit_radius")) * 0.5:
						tgt.take_damage(BITE_DAMAGE, jaw(_biter), enemy)
					var a := (_bite_to - global_position).angle()
					for i in 7:
						_shot(Vector2.from_angle(a + (i - 3) * 0.14) * 230.0, Color(1, 1, 1), "fang", jaw(_biter))
			elif _sp < t4:
				j.position = base + _dart(base) * (1.0 - (_sp - t3) / BITE_BACK)
			else:
				j.position = base
				_end_special()
		"breath":
			var k := length * 1.45 / 1569.0
			var rise := smoothstep(0.0, BREATH_WINDUP, _sp)
			var fall := 1.0 - smoothstep(BREATH_WINDUP + BREATH_TIME - 0.5, BREATH_WINDUP + BREATH_TIME, _sp)
			_front.visible = true
			_front.global_position = global_position + Vector2(0, -length * 0.2 * rise)
			_front.scale = Vector2.ONE * k * (0.85 + 0.2 * rise)
			_front.modulate.a = rise * fall
			_rig.modulate.a = 1.0 - 0.75 * rise * fall
			for w in 3:
				if _crossed_sp(BREATH_WINDUP + w * 0.55, delta):
					var n := 20 + fight_stage() * 2
					var gap := randi() % n
					var a0 := (tgt.global_position - global_position).angle() if tgt else 0.0
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) != n - 1:
							var o := _shot(Vector2.from_angle(a0 + i * TAU / n + w * 0.12) * 120.0, POISON, "miasma", global_position + Vector2.from_angle(a0 + i * TAU / n) * length * 0.3)
							o.accel = -12.0
			if _sp >= BREATH_WINDUP + BREATH_TIME:
				_front.visible = false
				_rig.modulate.a = 1.0
				_end_special()


## The bite's dart (art px, rig space): carrying the jaws from rest to where it strikes.
func _dart(base: Vector2) -> Vector2:
	var jaw_rest := _rig.to_global(base + _v(meta["mouths"][_biter]) - _v(meta[_biter + "_pivot"]))
	return (_bite_to - jaw_rest) / art_scale if art_scale > 0.0 else Vector2.ZERO


func _dart_dir(base: Vector2) -> Vector2:
	var d := _dart(base)
	return d.normalized() if d.length() > 0.01 else Vector2.ZERO


func _crossed_sp(at: float, delta: float) -> bool:
	return _sp >= at and _sp - delta < at


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	if special == "bite" and _joints.has(_biter):
		_joints[_biter].position = _base[_biter]
	special = ""
	_cool = PAUSE


## Above everything (relative to it): where the bite will land.
func _draw_over() -> void:
	if special == "bite" and _sp < BITE_WINDUP + BITE_STRIKE:
		var c := _bite_to - _over.global_position
		var u := clampf(_sp / BITE_WINDUP, 0.0, 1.0)
		_over.draw_arc(c, BITE_RADIUS, 0, TAU, 40, Color(1.0, 0.3, 0.2, 0.3 + 0.5 * u), 3.0, true)
		_over.draw_circle(c, BITE_RADIUS * u, Color(1.0, 0.3, 0.2, 0.12))


## Under the rig: the biting head's neck, stretched out after it. On the
## body: the heads' eyes burning gold as it gathers; the stumps.
func _draw() -> void:
	if meta.is_empty() or _rig == null:
		return
	var charge := _charge()
	if special == "bite" and _joints.has(_biter):
		var from := to_local(_rig.to_global(_base[_biter]))
		var to := to_local(_joints[_biter].global_position)
		if from.distance_to(to) > 4.0:
			var w := 120.0 * art_scale
			_neck(from, to, w)
	for h in meta["heads"]:
		if severed.has(h):
			var stump := to_local(_joints[h].global_position)
			draw_circle(stump, 22.0 * art_scale * 2.5, Color(0.5, 0.05, 0.05, 0.8))
			draw_circle(stump, 12.0 * art_scale * 2.5, Color(VENOM, 0.5 + 0.3 * sin(_t * 6.0)))
		elif charge > 0.0:
			var p := to_local(jaw(h).lerp(_joints[h].global_position, 0.45))
			draw_circle(p, 22.0 * art_scale * 2.5 * charge, Color(GOLD, 0.25 * charge * _rig.modulate.a))


## A scaly neck from `a` to `b` (local), `w` wide: dark edge, blue scales,
## the pale belly down the middle, scale rings along it.
func _neck(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a, b, Color(0.05, 0.05, 0.12), w + 4.0, true)
	draw_line(a, b, Color(0.17, 0.25, 0.6), w, true)
	draw_line(a, b, Color(0.9, 0.78, 0.55), w * 0.4, true)
	var n := int(a.distance_to(b) / (w * 0.6))
	var side := (b - a).normalized().orthogonal()
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		draw_line(p - side * w * 0.5, p + side * w * 0.5, Color(0.05, 0.05, 0.12, 0.6), 1.5, true)


## Its own bullet patterns: from all its heads.
func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	var hs := heads()
	if hs.is_empty():
		return super(name, delta, aim)
	match name:
		"eight_heads":   # each head in turn spits venom along its own neck
			for r in 2:
				for i in hs.size():
					if _crossed(r * 0.9 + i * 0.1):
						var h: String = hs[i]
						var a := facing(h)
						for k in 3 + st:
							_shot(Vector2.from_angle(a + (k - (2 + st) / 2.0) * 0.2) * 175.0 * spd, VENOM, "venom", jaw(h))
			return 1.9
		"volley":   # every head at once: fangs at you, three times
			for r in 3:
				if _crossed(r * 0.55):
					var tgt := _target()
					for h in hs:
						var from := jaw(h)
						var a: float = (tgt.global_position - from).angle() if tgt else facing(h)
						_shot(Vector2.from_angle(a + randf_range(-0.05, 0.05)) * 235.0 * spd, Color(1, 1, 1), "fang", from)
			return 1.6
		"miasma":   # poison clouds drifting from its jaws, finding you
			for r in 3:
				if _crossed(r * 0.5):
					for h in hs:
						if randf() < 0.6:
							var o := _shot(Vector2.from_angle(facing(h) + randf_range(-0.4, 0.4)) * randf_range(80.0, 110.0), POISON, "miasma", jaw(h))
							o.home = 0.3
			return 1.5
		"storm":   # all the heads spitting round and round
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.2:
				_emit += 0.13
				_spin += 0.22
				for h in hs:
					_shot(Vector2.from_angle(facing(h) + _spin) * 160.0 * spd, VENOM, "venom", jaw(h))
			return 2.3
	return super(name, delta, aim)


func calm() -> void:
	super()
	if _joints.has(_biter):
		_joints[_biter].position = _base[_biter]
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
