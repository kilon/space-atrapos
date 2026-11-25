class_name SeaWitch
extends SpaceMonster
## Skylla, the sea witch of the monster signal: the reference art itself
## (external/images/skylla/), cut into parts by tools/skylla_parts.py - the
## tentacle cluster, the upper body, and each arm as an upper arm and a
## forearm with its clawed hand (data/sprites/monster_skylla_*.png, joints in
## monster_skylla.json) - so every line, shape and colour of the picture is
## kept, and assembled here as a rig that moves:
##   - the tentacles writhe (shaders/skylla_tentacles.gdshader): waves running
##     out along each, the tips swaying most, the roots holding;
##   - her hair drifts as if in water (shaders/skylla_hair.gdshader);
##   - the arms swing at the shoulders and elbows, reaching and clawing;
##     charging an attack she draws them back and up, her eyes blaze and
##     energy gathers at her open, snarling mouth - where the orbs come from;
##   - she breathes, and bobs gently above her tentacles.
## Attacks, in turn (SEQUENCE): SpaceMonster's orb patterns in pink and magenta,
## and two of her own - both aimed at you while she winds up, then fixed:
##   waves  breakers: walls of sea waves crested with foam roll out at you,
##          each wall with a gap - slip through it (a bullet pattern);
##   ink    she spits a blob of ink at where you were (0.6 s wind-up); it bursts
##          into a cloud that lingers INK_TIME s - inside, your ship crawls at
##          INK_SLOW of its speed (Ship.slow) and the whole window goes dark.
##          Fly round it.
## She stays upright on screen as in the art, whichever way she moves.
## Head toward -y (her forward). The attacks are SpaceMonster's.

const ART := "res://data/sprites/monster_skylla"
const TENTACLE_SHADER := preload("res://shaders/skylla_tentacles.gdshader")
const HAIR_SHADER := preload("res://shaders/skylla_hair.gdshader")
## The art's pixel her rig is centred on (between the body and the tentacles).
const CENTRE := Vector2(800, 470)

const PINK := Color(1.0, 0.45, 0.75)
const MAGENTA := Color(0.85, 0.3, 1.0)
const SEQUENCE := ["orbs", "waves", "orbs", "ink", "waves", "orbs", "ink"]
const INK_WINDUP := 0.6
const INK_SPEED := 750.0
const INK_RADIUS := 300.0
const INK_TIME := 6.0
const INK_SLOW := 0.4

var meta := {}
var special := ""                   # "ink" under way
var specials_done := {}
var _sp := 0.0
var _aim := 0.0                     # world angle she aims the ink
var _ink_to := Vector2.ZERO         # where the ink blob is going (world)
var _attacks := 0
var _inks: Array = []               # [{at: Vector2 (world), t: age, flying: bool, from: Vector2}]
var _over: Node2D
var _inked := 0.0                   # s left of "you are in the ink"
var _blind: Node2D                  # the window darkened while you are in it
var _blind_a := 0.0
var art_scale := 0.5                # world px per art px
var _rig: Node2D
var _torso: Node2D
var _tentacles: Sprite2D
var _arms := {}                     # side -> [shoulder pivot, elbow pivot]
var _fx: Node2D                     # the eyes' blaze and the gathering energy, on top
## Demo (the Library): no target, she charges now and then by herself, firing nothing.
var demo := false


func _ready() -> void:
	super()
	glow = Color(1.0, 0.4, 0.75)
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.5 / 1100.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	# The tentacles, under everything, placed and sized as in the undivided
	# picture: their hub just below her chest (tentacle_at), 1.19x the size.
	_tentacles = _part("tentacles", CENTRE)
	var ts := float(meta["tentacle_scale"])
	var hub_tex := _v(meta["hub"]) - _v(meta["parts"]["tentacles"])
	_tentacles.scale = Vector2.ONE * ts
	_tentacles.position = _v(meta["tentacle_at"]) - CENTRE - hub_tex * ts
	var tm := ShaderMaterial.new()
	tm.shader = TENTACLE_SHADER
	tm.set_shader_parameter("tex_size", _tentacles.texture.get_size())
	tm.set_shader_parameter("hub", hub_tex)
	tm.set_shader_parameter("time_offset", randf() * 100.0)
	_tentacles.material = tm
	_rig.add_child(_tentacles)
	# The upper body (its hair drifting), then the arms on it.
	_torso = Node2D.new()
	_rig.add_child(_torso)
	var torso := _part("torso", CENTRE)
	var hm := ShaderMaterial.new()
	hm.shader = HAIR_SHADER
	hm.set_shader_parameter("tex_size", torso.texture.get_size())
	hm.set_shader_parameter("still_y", 250.0 - float(meta["parts"]["torso"][1]))
	hm.set_shader_parameter("top_y", 40.0 - float(meta["parts"]["torso"][1]))
	hm.set_shader_parameter("time_offset", randf() * 100.0)
	torso.material = hm
	_torso.add_child(torso)
	for side in ["left", "right"]:
		var sh := _v(meta[side + "_shoulder"])
		var el := _v(meta[side + "_elbow"])
		var shoulder := Node2D.new()
		shoulder.position = sh - CENTRE
		_torso.add_child(shoulder)
		# The forearm under the upper arm: the pieces overlap past the elbow
		# (tools/skylla_parts.py OVERLAP), so bending never shows a gap.
		var elbow := Node2D.new()
		elbow.position = el - sh
		shoulder.add_child(elbow)
		elbow.add_child(_part(side + "_fore", el))
		shoulder.add_child(_part(side + "_upper", sh))
		_arms[side] = [shoulder, elbow]
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	_torso.add_child(_fx)
	_over = Node2D.new()
	_over.top_level = true   # (world coordinates: the ink clouds stay where they burst)
	_over.z_index = 2
	_over.draw.connect(_draw_over)
	add_child(_over)


func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## A part's sprite, placed relative to `origin` (art px) and shifted by `shift`.
func _part(part: String, origin: Vector2, shift := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = part
	s.texture = load(ART + "_" + part + ".png")
	s.centered = false
	s.position = _v(meta["parts"][part]) + shift - origin
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


## Her rig's extent (tentacles 1434 x hair-to-tips ~920 art px round CENTRE).
func visual_size() -> Vector2:
	return Vector2(length * 1.96, length * 1.25)


## Her mouth: the orbs come from there.
func mouth() -> Vector2:
	if meta.is_empty() or _torso == null:
		return super()
	return _rig.to_global((_v(meta["mouth"]) - CENTRE) + _torso.position)


func _charge() -> float:
	if demo:
		return smoothstep(0.55, 0.85, sin(_t * 0.7))   # (a charge every 9 s or so)
	if special != "":
		return 1.0
	if pattern == "":
		return 0.0
	return clampf(1.0 + _pt / CHARGE, 0.0, 1.0) if _pt < 0.0 else 1.0


func _process(delta: float) -> void:
	if special != "" and not dying:
		_t += delta
		_run_special(delta)
	else:
		var was := pattern
		super(delta)
		if was == "" and pattern != "" and not dying:   # a new attack: which one?
			var kind: String = SEQUENCE[_attacks % SEQUENCE.size()]
			_attacks += 1
			var tgt := _target()
			if kind == "waves":
				pattern = "breakers"   # (a bullet pattern: the waves)
			elif kind != "orbs" and tgt != null:
				pattern = ""
				special = kind
				_sp = 0.0
				_aim = (tgt.global_position - _centre()).angle()
	_update_inks(delta)
	if _rig == null:
		return
	# Her tentacles writhe harder while she raises the waves.
	var tm := _tentacles.material as ShaderMaterial
	if tm:
		tm.set_shader_parameter("sway", 26.0 * (2.4 if pattern == "breakers" else 1.0))
	var charge := _charge()
	# Always upright on screen, as in the art (her ship-like heading doesn't turn her).
	_rig.global_rotation = 0.0
	# Breathing, and a gentle bob above the tentacles (rising as she charges).
	_torso.position = Vector2(sin(_t * 0.8) * 4.0, sin(_t * 1.3) * 6.0 - charge * 12.0) / art_scale
	_torso.scale = Vector2.ONE * (1.0 + 0.012 * sin(_t * 1.8))
	# The arms: reaching and clawing; drawn back and up as she charges.
	for side in _arms:
		var s := -1.0 if side == "left" else 1.0
		var reach := sin(_t * 1.2 + (0.0 if side == "left" else 1.9))
		var claw := sin(_t * 2.3 + (0.6 if side == "left" else 2.4))
		_arms[side][0].rotation = s * (0.1 * reach - 0.35 * charge)
		_arms[side][1].rotation = s * (0.14 * claw - 0.3 * charge)
	_fx.queue_redraw()
	_over.global_position = Vector2.ZERO
	_over.queue_redraw()


func _centre() -> Vector2:
	return enemy.global_position if enemy and is_instance_valid(enemy) else global_position


func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"ink":
			if _sp < INK_WINDUP:
				if tgt:
					_ink_to = tgt.global_position
			else:
				_inks.append({"at": mouth(), "from": mouth(), "to": _ink_to, "t": 0.0, "flying": true})
				Sfx.play_world("space/monster_roar", global_position, -8.0, 0.3)
				_end_special()


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	special = ""
	_cool = PAUSE


## The ink: blobs flying to where you were, then clouds that slow you.
func _update_inks(delta: float) -> void:
	var tgt := get_tree().get_first_node_in_group("player") as Node2D
	for ink in _inks:
		if ink["flying"]:
			var to: Vector2 = ink["to"]
			var at: Vector2 = ink["at"]
			if at.distance_to(to) <= INK_SPEED * delta:
				ink["at"] = to
				ink["flying"] = false
				ink["t"] = 0.0
			else:
				ink["at"] = at + (to - at).normalized() * INK_SPEED * delta
		else:
			ink["t"] += delta
			if tgt and tgt.has_method("slow") and tgt.global_position.distance_to(ink["at"]) < INK_RADIUS:
				tgt.slow(0.25, INK_SLOW)
				_inked = 0.25
	# In the ink, the whole window goes dark (fading in and out).
	_inked -= delta
	if _blind == null and is_inside_tree():
		_blind = Node2D.new()
		_blind.top_level = true
		_blind.z_index = 100   # (over the whole world; the HUD stays on top)
		_blind.draw.connect(func():
			var view := _blind.get_viewport_rect()
			var inv := _blind.get_canvas_transform().affine_inverse()
			_blind.draw_rect(Rect2(inv * view.position, inv.basis_xform(view.size)), Color(0.03, 0.0, 0.06, _blind_a)))
		add_child(_blind)
	if _blind:
		_blind_a = move_toward(_blind_a, 0.93 if _inked > 0.0 else 0.0, delta * (2.5 if _inked > 0.0 else 1.5))
		_blind.global_position = Vector2.ZERO
		_blind.visible = _blind_a > 0.01
		_blind.queue_redraw()
	_inks = _inks.filter(func(i): return i["flying"] or i["t"] < INK_TIME)


## On top of everything, in world space: the ink blobs and clouds.
func _draw_over() -> void:
	var c := _centre()
	for ink in _inks:
		var at: Vector2 = ink["at"]
		if ink["flying"]:
			_over.draw_circle(at, 22.0, Color(0.12, 0.02, 0.18, 0.95))
			_over.draw_circle(at, 12.0, Color(MAGENTA, 0.8))
		else:
			var t: float = ink["t"]
			var grow := minf(1.0, t / 0.35)
			var fade := 1.0 - smoothstep(INK_TIME - 1.0, INK_TIME, t)
			for k in 7:
				var a := k * TAU / 7.0 + t * 0.4
				var p := at + Vector2.from_angle(a) * INK_RADIUS * 0.42 * grow
				_over.draw_circle(p, INK_RADIUS * 0.5 * grow, Color(0.07, 0.01, 0.12, 0.32 * fade))
			_over.draw_circle(at, INK_RADIUS * 0.7 * grow, Color(0.05, 0.0, 0.09, 0.45 * fade))
			_over.draw_arc(at, INK_RADIUS * grow, 0, TAU, 48, Color(MAGENTA, 0.35 * fade), 3.0, true)


## Orbs in her colours, pink and magenta.
func _orb(vel: Vector2, col: Color, style := "orb") -> Orb:
	var o := super(vel, col, style)
	if col == ORB_COLOR or col == ORB_COLOR_2:
		o.color = PINK if col == ORB_COLOR else MAGENTA
	return o


# --- Her own bullet patterns: bubbles and ink, denser as the fight goes on -------

const POOLS := [["tide", "whirlpool", "lash"], ["tide", "lash", "ink_rain", "whirlpool"], ["maelstrom", "ink_rain", "lash", "tide"]]

func pattern_pool() -> Array:
	return POOLS[fight_stage()]


func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	var spd := 1.0 + 0.08 * st
	match name:
		"tide":   # three waves of wobbling bubbles rolling at you
			for k in 3:
				if _crossed(k * 0.55):
					var n := 9 + st * 2
					for i in n:
						var o := _shot(Vector2.from_angle(aim + (i - (n - 1) / 2.0) * 0.13) * 150.0 * spd, PINK, "bubble")
						o.wobble = 60.0
			return 1.3
		"whirlpool":   # two arms of bubbles, curling as they go
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.4:
				_emit += 0.12
				_spin += 0.33
				for arm in 2:
					var o := _shot(Vector2.from_angle(_spin + arm * PI) * 140.0 * spd, PINK, "bubble")
					o.curve = 0.4 if arm == 0 else -0.4
			return 2.5
		"lash":   # ink flung down each tentacle: eight streams, turning
			for k in 5:
				if _crossed(k * 0.1):
					for i in 8:
						var o := _shot(Vector2.from_angle(_spin + i * TAU / 8.0 + k * 0.05) * 170.0 * spd, MAGENTA, "ink")
						o.accel = 25.0
			if _crossed(0.5):
				_spin += 0.39
			return 0.9
		"ink_rain":   # aimed fans of ink, curving alternately left and right
			for k in 4:
				if _crossed(k * 0.4):
					for i in 5 + st:
						var o := _shot(Vector2.from_angle(aim + (i - 2) * 0.2) * 200.0 * spd, MAGENTA, "ink")
						o.curve = 0.35 if k % 2 == 0 else -0.35
			return 1.7
		"breakers":   # walls of waves crested with foam roll out at you, each with a gap
			for k in 3 + st:
				if _crossed(k * 0.6):
					var n := 11
					var gap := randi_range(2, n - 3)
					for i in n:
						if absi(i - gap) <= 1:
							continue
						var a := aim + (i - (n - 1) / 2.0) * 0.11
						var o := _shot(Vector2.from_angle(a) * 135.0 * spd, Color(0.25, 0.6, 1.0), "wave")
						o.wobble = 25.0
			return 0.6 * (3 + st) + 0.3
		"maelstrom":   # four counter-turning arms: bubbles one way, ink the other
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.8:
				_emit += 0.1
				_spin += 0.27
				for arm in 2:
					_shot(Vector2.from_angle(_spin + arm * PI) * 150.0, PINK, "bubble").curve = 0.3
					_shot(Vector2.from_angle(-_spin + arm * PI + PI / 2.0) * 170.0, MAGENTA, "ink").curve = -0.3
			return 2.9
	return super(name, delta, aim)


## Dying: stop whatever she was doing.
func death_throes() -> void:
	special = ""
	await super()


## On the torso, in art px: her eyes blazing and the energy at her mouth.
func _draw_fx() -> void:
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	for e in meta["eyes"]:
		var p := _v(e) - CENTRE
		_fx.draw_circle(p, 14.0 + 10.0 * charge, Color(1.0, 0.15, 0.3, 0.1 + 0.06 * pulse + 0.3 * charge))
		_fx.draw_circle(p, 5.0 + 3.0 * charge, Color(1.0, 0.5, 0.6, 0.2 + 0.5 * charge))
	if charge > 0.0:
		var m := _v(meta["mouth"]) - CENTRE
		var r := (4.0 + 12.0 * charge) * (1.0 + 0.15 * sin(_t * 30.0))
		for k in 4:
			_fx.draw_circle(m, r * (2.6 - k * 0.45), Color(glow, 0.08 + 0.06 * k))
		_fx.draw_circle(m, r, Color(1.0, 0.9, 1.0, 0.9))


func _draw() -> void:
	# A soft magenta halo behind her, brighter as she charges.
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	for k in 5:
		draw_circle(Vector2(0, length * 0.1), length * (0.7 - k * 0.1), Color(glow, (0.01 + 0.006 * pulse + 0.02 * charge) * (k + 1) * 0.6))
