class_name MinotaurBoss
extends SpaceMonster
## The Minotaur - the true Asterion, the Labyrinth's ancient guardian and the
## main quest's last boss (QuestData: the stage after "Enter the heart of the
## Labyrinth"). The reference art itself (external/images/minotaur/), cut into
## parts by tools/minotaur_parts.py - his body (with the gold ring and its
## starfield behind his head), both arms and the kicking leg, each running on
## under the body at its joint - and assembled here as a rig that moves:
##   - his red cape ripples (shaders/minotaur_cape.gdshader, with a cape mask);
##   - his arms swing at the shoulders, claws raking; the leg kicks;
##   - he breathes and sways; his eyes and the gem on his crest glow;
##   - he stays upright on screen as in the art.
## His orbs and beams come from his eyes (eye()). Attacks, in turn (SEQUENCE;
## phase 2, below half hull: the orbs 35 % faster and more rushes). The beam
## and the rush aim at you while he winds up, then fire at where you were:
##   orbs   SpaceMonster's bullet-hell patterns, red and gold;
##   rush   he lowers his horns (0.9 s) - a red arrow follows your ship - then
##          charges at the spot you were in when it started, goring whatever
##          he hits: be moving off that line when he goes;
##   beam   a thin red line from each eye follows you (0.8 s), then twin
##          searing beams fire along it for 1.8 s and hold there - they don't
##          follow you: get off the line;
##   pulse  his ring flares (0.8 s), then a golden shockwave rolls out; caught in
##          it your shields go dead for DRAIN_TIME s (Ship.drain_shields), then
##          come back as they were - outrun it, or keep your hull away from him.
## His shields recover after a pause: keep up the pressure.

const ART := "res://data/sprites/monster_minotaur"
const CAPE_SHADER := preload("res://shaders/minotaur_cape.gdshader")
const RED := Color(1.0, 0.32, 0.15)
const GOLD := Color(1.0, 0.8, 0.3)
const RUSH_WINDUP := 0.9            # s lowering his horns (the warning)
const RUSH_TIME := 1.1              # s charging
const RUSH_SPEED := 980.0           # px/s (your ship: 420 - sidestep, don't outrun)
const RUSH_DAMAGE := 28.0
const SEQUENCE := ["orbs", "beam", "rush", "orbs", "pulse", "rush"]
const SEQUENCE_2 := ["orbs", "rush", "beam", "rush", "pulse", "orbs", "rush"]
const BEAM_WINDUP := 0.8
const BEAM_TIME := 1.8
const BEAM_DPS := 45.0
const BEAM_LENGTH := 1500.0
const BEAM_WIDTH := 26.0
const PULSE_WINDUP := 0.8
const PULSE_SPEED := 650.0          # the shockwave's px/s (your ship does 420: fly out early)
const PULSE_REACH := 1500.0
const DRAIN_TIME := 4.0             # s your shields stay dead

var meta := {}
var art_scale := 0.5
var demo := false                   # the Library: no target, he winds up now and then
var rushes := 0
var _rig: Node2D
var _body: Node2D
var _limbs := {}                    # name -> pivot node
var _fx: Node2D
var _over: Node2D                   # drawn above his art (beams, pulse, rush path)
var _rush := -1.0                   # time into a rush (-1: none; < RUSH_WINDUP: winding up)
var _rush_dir := Vector2.ZERO
var _rush_hit := false
var _attacks := 0
var phase := 1                      # 2 below half hull
var special := ""                   # the beam or the pulse under way ("" none)
var specials_done := {}             # kind -> count (tests, playtests)
var _sp := 0.0                      # time into the special
var _beam_ang := 0.0                # world angle of the beam
var _pulse_r := -1.0                # the shockwave's radius (-1: none)
var _pulse_hit := false


func _ready() -> void:
	super()
	glow = RED
	meta = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
	art_scale = length * 1.4 / 1254.0
	_rig = Node2D.new()
	_rig.scale = Vector2.ONE * art_scale
	add_child(_rig)
	var hub := _v(meta["hub"])
	_body = Node2D.new()
	_rig.add_child(_body)
	# The limbs behind? No - in front: they run on under the body at the joint,
	# so they go on top and the body fills in behind when they swing.
	var body := _part("body", hub)
	var cm := ShaderMaterial.new()
	cm.shader = CAPE_SHADER
	cm.set_shader_parameter("cape_mask", load("res://data/masks/monster_minotaur_cape.png"))
	cm.set_shader_parameter("tex_size", body.texture.get_size())
	cm.set_shader_parameter("time_offset", randf() * 100.0)
	body.material = cm
	_body.add_child(body)
	for limb in ["left_leg", "left_arm", "right_arm"]:
		var piv := _v(meta[limb + "_pivot"])
		var joint := Node2D.new()
		joint.position = piv - hub
		_body.add_child(joint)
		joint.add_child(_part(limb, piv))
		_limbs[limb] = joint
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	_body.add_child(_fx)
	# On top of all of him: the beams, the shockwave and the rush's path.
	_over = Node2D.new()
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


## The art (1254 px square round his chest), upright.
func visual_size() -> Vector2:
	return Vector2(length, length) * 1.43


## One of his eyes (0, 1) in world space: his orbs and beams come from them.
func eye(i: int) -> Vector2:
	if meta.is_empty() or _body == null:
		return super.mouth()
	return _rig.to_global(_v(meta["eyes"][i]) - _v(meta["hub"]) + _body.position)


## Between his eyes: where the attacks aim from.
func mouth() -> Vector2:
	if meta.is_empty() or _body == null:
		return super()
	return (eye(0) + eye(1)) * 0.5


## 0..1: winding up an attack (or a rush), for the look.
func _charge() -> float:
	if demo:
		return smoothstep(0.55, 0.85, sin(_t * 0.7))
	if _rush >= 0.0 or special != "":
		return 1.0
	if pattern == "":
		return 0.0
	return clampf(1.0 + _pt / CHARGE, 0.0, 1.0) if _pt < 0.0 else 1.0


## Dying: stop whatever he was doing first.
func death_throes() -> void:
	_rush = -1.0
	special = ""
	await super()


func _process(delta: float) -> void:
	if enemy and is_instance_valid(enemy) and phase == 1 and enemy.hull < enemy.max_hull * 0.5:
		phase = 2
		Sfx.play_world("space/monster_roar", global_position, 0.0, 0.05)
		GameLog.post("The Minotaur roars - he's enraged!", "danger")
	if dying:
		_t += delta
	elif _rush >= 0.0:
		_t += delta
		_run_rush(delta)
	elif special != "":
		_t += delta
		_run_special(delta)
	else:
		var was := pattern
		super(delta)
		if was == "" and pattern != "":   # a new attack began: which one is up?
			var seq: Array = SEQUENCE if phase == 1 else SEQUENCE_2
			var kind: String = seq[_attacks % seq.size()]
			_attacks += 1
			if kind != "orbs" and _target() != null:
				pattern = ""
				if kind == "rush":
					_rush = 0.0
					_rush_hit = false
					Sfx.play_world("space/monster_roar", global_position, -4.0, 0.1)
				else:
					special = kind
					_sp = 0.0
					_pulse_r = -1.0
					_pulse_hit = false
					var tgt := _target()
					_beam_ang = (tgt.global_position - mouth()).angle()
	_update_pulse(delta)
	if _rig == null:
		return
	_rig.global_rotation = 0.0
	var charge := _charge()
	_body.position = Vector2(sin(_t * 0.9) * 5.0, sin(_t * 1.4) * 5.0 + charge * 14.0) / art_scale
	_body.scale = Vector2.ONE * (1.0 + 0.01 * sin(_t * 1.6))
	var swing := sin(_t * 1.25)
	_limbs["left_arm"].rotation = 0.09 * swing - 0.25 * charge
	_limbs["right_arm"].rotation = -0.08 * sin(_t * 1.25 + 1.6) + 0.18 * charge
	_limbs["left_leg"].rotation = 0.06 * sin(_t * 1.1 + 0.8) + 0.12 * charge
	_fx.queue_redraw()
	_over.queue_redraw()
	queue_redraw()


## The bull rush: wind up (facing you), then charge straight on.
func _run_rush(delta: float) -> void:
	var tgt := _target()
	_rush += delta
	if _rush < RUSH_WINDUP:
		if tgt:   # following you; when he charges, it's at the spot you were in
			_rush_dir = (tgt.global_position - enemy.global_position).normalized()
		return
	if _rush < RUSH_WINDUP + RUSH_TIME and enemy and is_instance_valid(enemy):
		enemy.global_position += _rush_dir * RUSH_SPEED * delta
		if tgt and not _rush_hit and tgt.global_position.distance_to(enemy.global_position) < length * 0.3 + float(tgt.get("hit_radius")):
			_rush_hit = true
			tgt.take_damage(RUSH_DAMAGE, enemy.global_position, enemy)
		return
	_rush = -1.0
	rushes += 1
	_cool = PAUSE * (0.7 if phase == 2 else 1.0)


## The beam and the pulse.
func _run_special(delta: float) -> void:
	var tgt := _target()
	_sp += delta
	match special:
		"beam":
			if _sp <= BEAM_WINDUP:   # aiming: following you
				if tgt:
					_beam_ang = (tgt.global_position - mouth()).angle()
			elif tgt:   # firing: fixed where you were - it doesn't follow
				var dir := Vector2.from_angle(_beam_ang)
				for i in 2:   # a beam from each eye
					var from := eye(i)
					var rel: Vector2 = tgt.global_position - from
					var along := rel.dot(dir)
					if along > 0.0 and along < BEAM_LENGTH and absf(rel.cross(dir)) < BEAM_WIDTH + float(tgt.get("hit_radius")) * 0.5:
						tgt.take_damage(BEAM_DPS * 0.5 * delta, from + dir * along, enemy, "energy")
			if _sp > BEAM_WINDUP + BEAM_TIME:
				_end_special()
		"pulse":
			if _sp >= PULSE_WINDUP and _pulse_r < 0.0:
				_pulse_r = 0.0
				Sfx.play_world("space/monster_roar", global_position, -2.0, 0.2)
			if _sp > PULSE_WINDUP + 0.2:
				_end_special()


## The shockwave keeps rolling out after he's moved on to the next attack.
func _update_pulse(delta: float) -> void:
	if _pulse_r < 0.0:
		return
	_pulse_r += PULSE_SPEED * delta
	var tgt := _target()
	if tgt and not _pulse_hit and enemy and is_instance_valid(enemy) and absf(tgt.global_position.distance_to(enemy.global_position) - _pulse_r) < 40.0:
		_pulse_hit = true
		if tgt.has_method("drain_shields"):
			tgt.drain_shields(DRAIN_TIME)
	if _pulse_r > PULSE_REACH:
		_pulse_r = -1.0


func _end_special() -> void:
	specials_done[special] = int(specials_done.get(special, 0)) + 1
	special = ""
	_cool = PAUSE * (0.7 if phase == 2 else 1.0)


## Above his art: the twin beams from his eyes, the pulse, the rush's path.
func _draw_over() -> void:
	# The beam (world -> local), its warning line while he aims.
	if special == "beam":
		for i in 2:   # twin beams, one from each eye
			var from := to_local(eye(i))
			var to := to_local(eye(i) + Vector2.from_angle(_beam_ang) * BEAM_LENGTH)
			if _sp < BEAM_WINDUP:
				_over.draw_line(from, to, Color(1.0, 0.2, 0.15, 0.25 + 0.4 * (_sp / BEAM_WINDUP)), 2.0, true)
			else:
				var flick := 1.0 + 0.15 * sin(_t * 50.0 + i)
				_over.draw_line(from, to, Color(1.0, 0.25, 0.1, 0.18), BEAM_WIDTH * 1.8 * flick, true)
				_over.draw_line(from, to, Color(1.0, 0.45, 0.2, 0.55), BEAM_WIDTH * 0.8 * flick, true)
				_over.draw_line(from, to, Color(1.0, 0.95, 0.8, 0.95), BEAM_WIDTH * 0.25, true)
				_over.draw_circle(from, BEAM_WIDTH * 0.9, Color(1.0, 0.8, 0.5, 0.85))
	# The pulse: his ring flaring, then the golden shockwave.
	if special == "pulse" and _sp < PULSE_WINDUP:
		_over.draw_arc(Vector2.ZERO, length * (0.5 + 0.2 * _sp / PULSE_WINDUP), 0, TAU, 64, Color(GOLD, 0.3 + 0.5 * _sp / PULSE_WINDUP), 8.0, true)
	if _pulse_r >= 0.0:
		var fade := 1.0 - _pulse_r / PULSE_REACH
		_over.draw_arc(Vector2.ZERO, _pulse_r, 0, TAU, 128, Color(GOLD, 0.15 * fade), 60.0, true)
		_over.draw_arc(Vector2.ZERO, _pulse_r, 0, TAU, 128, Color(GOLD.lightened(0.3), 0.8 * fade), 6.0, true)
	# The rush's path, following you while he winds up (brighter just before he goes).
	if _rush >= 0.0 and _rush < RUSH_WINDUP:
		var dir := _rush_dir.rotated(-global_rotation)
		var locked := _rush >= RUSH_WINDUP * 0.75   # (brighter just before he goes)
		var reach := RUSH_SPEED * RUSH_TIME
		var col := Color(1.0, 0.25, 0.15, 0.55 if locked else 0.2 + 0.25 * _rush / RUSH_WINDUP)
		_over.draw_line(dir * length * 0.4, dir * reach, Color(col, col.a * 0.35), 70.0, true)
		_over.draw_line(dir * length * 0.4, dir * reach, col, 4.0, true)
		var tip := dir * reach
		_over.draw_colored_polygon(PackedVector2Array([tip + dir * 40.0, tip + dir.orthogonal() * 30.0, tip - dir.orthogonal() * 30.0]), col)


## Orbs in his colours, red and gold.
func _orb(vel: Vector2, col: Color, style := "orb") -> Orb:
	var o := super(vel * (1.35 if phase == 2 else 1.0), col, style)
	if col == ORB_COLOR or col == ORB_COLOR_2:
		o.color = RED if col == ORB_COLOR else GOLD
	o.global_position = eye(orbs_fired % 2)   # (each eye in turn)
	return o


# --- His own bullet patterns: spears and golden labyrinth rings ------------------

const POOLS := [["volley", "labyrinth", "horns"], ["labyrinth", "stampede", "horns", "volley"], ["maze", "stampede", "horns", "volley"]]

func pattern_pool() -> Array:
	return POOLS[maxi(fight_stage(), 2 if phase == 2 else 0)]


func _pattern_step(name: String, delta: float, aim: float) -> float:
	var st := fight_stage()
	match name:
		"volley":   # three lines of spears, each a row arriving together
			for k in 3:
				if _crossed(k * 0.35):
					var a := aim + (k - 1) * 0.28
					for i in 5:
						_shot(Vector2.from_angle(a) * (150.0 + i * 22.0), RED, "spear")
			return 1.0
		"labyrinth":   # rings of gold with one gap, turning ring by ring: find the way out
			for k in 4:
				if _crossed(k * 0.55):
					var n := 26
					var gap := int(fposmod((aim + PI) / TAU * n + k * 3, n))
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) < n - 1:
							_shot(Vector2.from_angle(i * TAU / n) * 130.0, GOLD, "orb")
			return 2.0
		"horns":   # spears raking from each eye, sweeping in opposite directions
			_emit -= delta
			while _emit <= 0.0 and _pt < 1.6:
				_emit += 0.08
				var u := _pt / 1.6
				for e in 2:
					var a := aim + (0.9 - 1.8 * u) * (1.0 if e == 0 else -1.0)
					_shot(Vector2.from_angle(a) * 200.0, RED, "spear", eye(e))
			return 1.7
		"stampede":   # wide fans of spears that start slow and charge
			for k in 3:
				if _crossed(k * 0.5):
					for i in 9 + st * 2:
						var o := _shot(Vector2.from_angle(aim + (i - (8 + st * 2) / 2.0) * 0.14) * 80.0, RED, "spear")
						o.accel = 110.0
			return 1.6
		"maze":   # gold rings with gaps that alternate sides, spears aimed between them
			for k in 5:
				if _crossed(k * 0.45):
					var n := 28
					var gap := int(fposmod((aim + PI) / TAU * n + (8 if k % 2 == 0 else -8), n))
					for i in n:
						if absi(i - gap) > 1 and absi(i - gap) < n - 1:
							_shot(Vector2.from_angle(i * TAU / n) * 125.0, GOLD, "orb")
					_shot(Vector2.from_angle(aim) * 210.0, RED, "spear")
			return 2.4
	return super(name, delta, aim)


## On the body, in art px: the eyes and the crest gem glowing (blazing as he
## winds up), and a trail of red light behind him while he rushes.
func _draw_fx() -> void:
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var hub := _v(meta["hub"])
	for e in meta["eyes"]:
		var p := _v(e) - hub
		_fx.draw_circle(p, 18.0 + 14.0 * charge, Color(1.0, 0.1, 0.1, 0.12 + 0.08 * pulse + 0.3 * charge))
		_fx.draw_circle(p, 6.0 + 4.0 * charge, Color(1.0, 0.55, 0.45, 0.25 + 0.5 * charge))
	var c := _v(meta["crest"]) - hub
	_fx.draw_circle(c, 20.0 + 16.0 * charge, Color(0.4, 0.5, 1.0, 0.1 + 0.08 * pulse + 0.25 * charge))


func _draw() -> void:
	var charge := _charge()
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	for k in 5:
		draw_circle(Vector2.ZERO, length * (0.75 - k * 0.11), Color(RED, (0.01 + 0.006 * pulse + 0.02 * charge) * (k + 1) * 0.6))
	if _rush >= RUSH_WINDUP:
		var back := -_rush_dir.rotated(-global_rotation)
		for k in 6:
			draw_circle(back * (60.0 + k * 55.0), length * (0.35 - k * 0.04), Color(RED, 0.12 - k * 0.015))
