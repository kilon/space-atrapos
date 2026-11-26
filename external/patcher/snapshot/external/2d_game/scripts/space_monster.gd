class_name SpaceMonster
extends Node2D
## The look and the attacks of an alien creature (EnemyTypes.MONSTERS): an
## Enemy whose ship picture is hidden (Enemy._apply_type) and this in its
## place. Head toward -y (the way a ship's nose points).
##
## Drawn in layers, all moving: tentacles that writhe in travelling waves
## (suckers, glowing tips, curling at the ends), two fins that beat, a body of
## overlapping plates that undulates along its spine with rim light and dark
## mottling, veins of light pulsing from head to tail, eyes that track you and
## blink, mandibles that open as it charges, a ball of energy gathering in
## its maw.
##
## It doesn't fire like a ship (Enemy._shoot skips monsters): it attacks in
## bullet-hell patterns of slow glowing orbs (Orb) - rings with a gap to slip
## through, spinning spirals, aimed fans, curving blooms - each telegraphed by
## a CHARGE (its maw glowing, the mandibles opening), PAUSE seconds apart. The
## orbs are slower than your ship and your hitbox against them is smaller
## than your hull (HITBOX), so they're hard to dodge but always dodgeable.

const PATTERNS := ["ring", "spiral", "fan", "bloom"]
const CHARGE := 0.7
const PAUSE := 1.6
const REACH := 1400.0               # attacks only a target this close
const ORB_DAMAGE := 7.0
const FLEE_CATCHUP := 200.0         # px/s of you fleeing that doubles its bullets' speed (_orb)
const ORB_COLOR := Color(0.55, 1.0, 0.45)
const ORB_COLOR_2 := Color(0.85, 0.45, 1.0)

var length := 260.0
var enemy: Node2D                   # the Enemy it belongs to
var body_color := Color(0.1, 0.27, 0.3)
var glow := Color(0.45, 1.0, 0.6)
var pattern := ""                   # the attack under way ("" none)
var orbs_fired := 0
var _t := 0.0
var _pt := 0.0                      # time into the attack (negative: charging)
var _cool := 2.0
var pause := PAUSE                  # rest between its attacks
var _next := 0
var _emit := 0.0
var _spin := 0.0
var _blink := 3.0
var _look := Vector2.UP             # where the eyes look (local)


func _ready() -> void:
	_t = randf() * 10.0
	_spin = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	_blink -= delta
	if _blink < -0.15:
		_blink = randf_range(2.0, 5.0)
	var tgt := _target()
	if tgt:
		_fight_t += delta
		_look = _look.lerp(to_local(tgt.global_position).normalized(), minf(1.0, delta * 4.0))
	_attack(delta, tgt)
	if UI.redraw_due(self):   # (its tentacles' sway: 60 a second is smooth - every frame cost 1.4 ms)
		queue_redraw()


func _target() -> Node2D:
	if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
		return null
	var t = enemy.get("_target")
	if t is Node2D and is_instance_valid(t) and t.is_alive() and t.global_position.distance_to(global_position) < REACH:
		return t
	return null


# --- Attacks -------------------------------------------------------------------------------

func _attack(delta: float, tgt: Node2D) -> void:
	if dying:
		return
	if pattern == "":
		_cool -= delta
		if _cool <= 0.0 and tgt != null:
			var pool := pattern_pool()
			pattern = pool[_next % pool.size()]
			_next += 1
			_pt = -CHARGE
			_emit = 0.0
			Sfx.play_world("space/monster_roar", global_position, -8.0, 0.15)
		return
	var before := _pt
	_pt += delta
	if _pt < 0.0:
		return
	var aim := (tgt.global_position - mouth()).angle() if tgt else global_rotation - PI / 2.0
	_before = before
	var end := _pattern_step(pattern, delta, aim)
	if _pt >= end:
		pattern = ""
		_cool = pause
		_spin += 1.1


## The patterns it chooses from now: its own, by fight_stage(). (Subclasses
## give their own pools; the Leviathan keeps PATTERNS.)
func pattern_pool() -> Array:
	return PATTERNS


## How far into the fight (0, 1, 2): later stages use denser, faster patterns.
## Up a stage every 40 s of fighting, or as its hull falls below 2/3 and 1/3.
var _fight_t := 0.0
func fight_stage() -> int:
	var by_time := int(_fight_t / 40.0)
	var by_hull := 0
	if enemy and is_instance_valid(enemy) and enemy.max_hull > 0.0:
		var f: float = enemy.hull / enemy.max_hull
		by_hull = 2 if f < 0.34 else (1 if f < 0.67 else 0)
	return clampi(maxi(by_time, by_hull), 0, 2)


var _before := 0.0
func _crossed(at: float) -> bool:
	return _before < at and _pt >= at


## Runs one frame of pattern `name` (_pt: time into it); returns when it ends.
## Subclasses handle their own names and pass the rest here.
func _pattern_step(name: String, delta: float, aim: float) -> float:
	match name:
		"ring":   # two rings, the second turned half a step: weave through the gaps
			for k in 2:
				if _crossed(k * 0.6):
					_ring(18, 155.0, _spin + k * PI / 18.0, ORB_COLOR)
			return 0.7
		"spiral":   # two arms turning: circle round it against the spin
			_emit -= delta
			while _emit <= 0.0 and _pt < 2.6:
				_emit += 0.09
				_spin += 0.31
				for arm in 2:
					_orb(Vector2.from_angle(_spin + arm * PI) * 175.0, ORB_COLOR_2)
			return 2.7
		"fan":   # three aimed fans of seven: sidestep
			for k in 3:
				if _crossed(k * 0.45):
					for i in 7:
						_orb(Vector2.from_angle(aim + (i - 3) * 0.12) * 235.0, ORB_COLOR)
			return 1.0
		"bloom":   # four rings whose orbs curve, alternately left and right
			for k in 4:
				if _crossed(k * 0.5):
					var curve := 0.55 if k % 2 == 0 else -0.55
					for i in 10:
						var o := _orb(Vector2.from_angle(_spin + i * TAU / 10.0 + k * 0.3) * 145.0, ORB_COLOR_2)
						o.curve = curve
			return 1.7
	return 0.0


## An orb of `style` (Orb.STYLES) - the creatures' own bullets.
func _shot(vel: Vector2, col: Color, style: String, at := Vector2.INF) -> Orb:
	var o := _orb(vel, col, style)
	if at != Vector2.INF:
		o.global_position = at
	return o


## Breaks off whatever attack is under way (MonsterPursuit: stashed while it
## waits to follow you); subclasses also end their specials.
func calm() -> void:
	pattern = ""
	_cool = PAUSE
	if get("special") != null:
		set("special", "")


## Dying (Enemy._die): THROES s of shaking - harder and harder, flickering
## red-hot, explosions bursting across its body - then a very large explosion
## (and a few more round it); then it's gone. Only the creature shakes; the
## camera glides over to centre on it meanwhile, and back to your ship after.
const THROES := 2.4
var dying := false
var cinematic := true               # its death takes the camera (not a Hydra's double head)
var throes_time := THROES
static var _cam_taken := false      # one dying creature at a time has the camera

func death_throes() -> void:
	dying = true
	pattern = ""
	var size := visual_size()
	var home := position
	var t := 0.0
	var next_burst := 0.0
	Sfx.play_world("space/monster_roar", global_position, 2.0, 0.05)
	# The camera leaves your ship and glides over to watch it die.
	var cam := get_viewport().get_camera_2d()
	var cam_home := Vector2.ZERO
	var centre := (enemy.global_position if enemy and is_instance_valid(enemy) else global_position)
	if cam and (not cinematic or _cam_taken or cam.top_level or cam.global_position.distance_to(centre) > 2500.0):
		cam = null   # (dying far away, a small one, or another creature has the camera: leave the view alone)
	if cam:
		_cam_taken = true
		cam_home = cam.position
		var g := cam.global_position
		cam.top_level = true
		cam.global_position = g
		cam.create_tween().tween_property(cam, "global_position", centre, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while t < throes_time:
		await get_tree().process_frame
		if not is_inside_tree():
			_give_camera_back(cam, cam_home)
			return
		var dt := get_process_delta_time()
		t += dt
		var k := t / throes_time
		position = home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (4.0 + 26.0 * k) / maxf(global_scale.x, 0.01)
		var flick := 0.5 + 0.5 * sin(t * (18.0 + 30.0 * k))
		modulate = Color(1.0 + 0.8 * k * flick, 1.0 - 0.3 * k * flick, 1.0 - 0.45 * k * flick)
		next_burst -= dt
		if next_burst <= 0.0:
			next_burst = lerpf(0.28, 0.07, k)
			var at := global_position + Vector2(randf_range(-0.4, 0.4) * size.x, randf_range(-0.4, 0.4) * size.y)
			Effects.explosion(at, randf_range(0.5, 0.9) + k, "space/boom_small" if randf() < 0.7 else "space/boom_big")
	# The big one.
	var at := global_position
	if not cinematic:   # (a small one: one blast, done)
		Effects.explosion(at, clampf(length / 60.0, 1.5, 4.0), "space/boom_big")
		visible = false
		return
	Effects.explosion(at, 6.5, "space/ship_boom_large")
	visible = false
	for i in 4:
		await get_tree().create_timer(0.1 + 0.09 * i).timeout
		Effects.explosion(at + Vector2.from_angle(randf() * TAU) * size.length() * randf_range(0.15, 0.35), randf_range(2.4, 3.4), "space/boom_big")
	await get_tree().create_timer(0.9).timeout
	# And back to your ship.
	if cam and is_instance_valid(cam):
		var parent := cam.get_parent() as Node2D
		if parent:
			var tw := cam.create_tween()
			tw.tween_method(func(u: float):
				if is_instance_valid(cam) and is_instance_valid(parent):
					cam.global_position = centre.lerp(parent.to_global(cam_home), u), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			await tw.finished
	_give_camera_back(cam, cam_home)


func _give_camera_back(cam: Camera2D, cam_home: Vector2) -> void:
	if cam == null:
		return
	_cam_taken = false
	if is_instance_valid(cam):
		cam.top_level = false
		cam.position = cam_home


## How big it looks (world px, upright): its shield and hit radius are sized
## from this (Enemy), not from the hidden sizing ship.
func visual_size() -> Vector2:
	return Vector2(length, length) * 0.9


func mouth() -> Vector2:
	return to_global(Vector2(0, -length * 0.5))


func _ring(n: int, speed: float, offset: float, col: Color) -> void:
	for i in n:
		_orb(Vector2.from_angle(offset + i * TAU / n) * speed, col)


func _orb(vel: Vector2, col: Color, style := "orb") -> Orb:
	var o := Orb.new()
	o.style = style
	o.velocity = vel
	o.color = col
	o.damage = ORB_DAMAGE
	o.source = enemy
	# In the effects layer - never among the ships (code walking the enemies
	# node expects only ships there: click picking, saving...).
	var parent: Node = get_tree().get_first_node_in_group("fx_layer")
	if parent == null:
		parent = get_tree().current_scene if get_tree().current_scene else get_parent()
	parent.add_child(o)
	o.global_position = mouth()
	orbs_fired += 1
	# Running away doesn't save you: fleeing from it, its bullets fly faster -
	# by your speed away from it over FLEE_CATCHUP (at full speed, about 3x).
	var tgt := _target()
	if tgt and tgt.get("velocity") is Vector2:
		var flee := maxf(0.0, (tgt.velocity as Vector2).dot((tgt.global_position - global_position).normalized()))
		if flee > 20.0:
			o.velocity *= 1.0 + flee / FLEE_CATCHUP
			o.top = maxf(o.top, o.velocity.length())
	return o


# --- Drawing -------------------------------------------------------------------------------

## The spine's sideways sway at s (0 head .. 1 tail): a wave running back.
func _sway(s: float) -> float:
	return sin(_t * 2.3 - s * 4.5) * length * 0.04 * (0.3 + s)


func _draw() -> void:
	var L := length
	var pulse := 0.5 + 0.5 * sin(_t * 2.0)
	var charge := clampf(1.0 + _pt / CHARGE, 0.0, 1.0) if pattern != "" and _pt < 0.0 else (1.0 if pattern != "" else 0.0)
	_draw_tentacles(L, pulse)
	# A soft halo, brighter when it charges.
	for k in 5:   # (layered, so its edge is soft)
		draw_circle(Vector2(0, -L * 0.1), L * (0.46 - k * 0.06), Color(glow, (0.012 + 0.01 * pulse + 0.02 * charge) * (k + 1) * 0.6))
	_draw_fins(L)
	# The body: plates from tail to head (the head's drawn last, on top).
	var segs := [[0.95, 0.07], [0.8, 0.1], [0.66, 0.13], [0.52, 0.16], [0.38, 0.19], [0.25, 0.2], [0.13, 0.18], [0.03, 0.15]]
	for sg in segs:
		var s: float = sg[0]
		var c := Vector2(_sway(s), lerpf(-0.42, 0.2, s) * L)
		var r: float = sg[1] * L * (1.0 + 0.04 * sin(_t * 2.6 + s * 6.0))
		draw_circle(c, r, body_color.darkened(0.25))
		draw_circle(c + Vector2(-r * 0.12, -r * 0.1), r * 0.88, body_color)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.25), r * 0.45, body_color.lightened(0.08))
		draw_arc(c, r * 0.97, PI * 1.05, PI * 1.95, 18, Color(glow, 0.45), 2.0, true)   # rim light
		for m in 3:   # dark mottling
			var a := s * 17.0 + m * 2.1
			draw_circle(c + Vector2.from_angle(a) * r * 0.55, r * 0.12, Color(0.03, 0.08, 0.1, 0.5))
	# Veins of light, a pulse running from head to tail.
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 14:
			var s := i / 13.0
			pts.append(Vector2(_sway(s) + side * L * 0.07 * sin(PI * clampf(s * 1.1, 0.0, 1.0)), lerpf(-0.36, 0.17, s) * L))
		draw_polyline(pts, Color(glow, 0.25), 2.0, true)
		var head_s := fmod(_t * 0.7, 1.0)
		for i in pts.size():
			var d := absf(i / 13.0 - head_s)
			if d < 0.12:
				draw_circle(pts[i], 3.5 * (1.0 - d / 0.12) + 1.0, Color(glow.lightened(0.3), 0.9 * (1.0 - d / 0.12)))
	# Glowing spots along its back.
	for i in 8:
		var s := 0.1 + i * 0.1
		var p := Vector2(_sway(s), lerpf(-0.42, 0.2, s) * L)
		draw_circle(p, 2.5 + 1.5 * sin(_t * 4.0 - i), Color(glow, 0.5 + 0.4 * pulse))
	_draw_head(L, charge)


func _draw_tentacles(L: float, pulse: float) -> void:
	for k in 8:
		var side := (k - 3.5) / 3.5
		var root := Vector2(_sway(0.85) + side * L * 0.12, L * 0.14)
		var pts := PackedVector2Array()
		var long := L * (0.55 + 0.12 * ((k * 7) % 3) / 2.0)
		for i in 18:
			var u := i / 17.0
			var wave := sin(_t * 3.2 - u * 6.0 + k * 0.8) * L * 0.1 * u
			var curl := Vector2(sin(_t * 1.3 + k), 0) * L * 0.08 * pow(u, 3.0)
			pts.append(root + Vector2(side * L * 0.26 * u + wave, u * long) + curl)
		# (Two tapered strips - its dark edge, then its body - not 34 antialiased
		# segments: that was ~1 ms a redraw.)
		var edge := _taper(pts, L * 0.055 + 2.0, 3.5)
		_strip(edge, body_color.darkened(0.1))
		draw_polyline(edge, body_color.darkened(0.1), 1.0, true)   # (its outline smooths the edge)
		_strip(_taper(pts, L * 0.055, 1.5), body_color.lerp(glow, 0.12))
		for i in range(2, pts.size() - 2, 2):   # suckers
			var n := (pts[i + 1] - pts[i]).orthogonal().normalized()
			draw_circle(pts[i] + n * lerpf(L * 0.02, 0.5, float(i) / pts.size()), 1.6, Color(0.75, 0.9, 0.8, 0.6))
		draw_circle(pts[pts.size() - 1], 3.0 + 1.5 * pulse, Color(glow, 0.8))   # glowing tip


## The outline of a strip along `pts`, `w0` wide at its root narrowing to `w1`.
static func _taper(pts: PackedVector2Array, w0: float, w1: float) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	out.resize(n * 2)
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized().orthogonal()
		var h := lerpf(w0, w1, float(i) / (n - 1)) * 0.5
		out[i] = pts[i] + d * h
		out[n * 2 - 1 - i] = pts[i] - d * h
	return out


## A _taper outline filled as the triangles between its two sides (never
## mis-triangulated where a tentacle curls over itself).
func _strip(outline: PackedVector2Array, col: Color) -> void:
	var n := outline.size() / 2
	var idx := PackedInt32Array()
	for i in n - 1:
		var a := i
		var b := i + 1
		var c := n * 2 - 1 - i
		var d := n * 2 - 2 - i
		idx.append_array([a, b, c, b, d, c])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, outline, PackedColorArray([col]))


func _draw_fins(L: float) -> void:
	var beat := sin(_t * 3.4) * 0.35
	for side in [-1.0, 1.0]:
		var base := Vector2(_sway(0.3) + side * L * 0.15, -L * 0.18)
		var tip := base + Vector2(side * L * 0.3, L * 0.12).rotated(side * beat)
		var back := base + Vector2(side * L * 0.05, L * 0.26)
		var fin := PackedVector2Array([base, tip, tip.lerp(back, 0.5) + Vector2(side * L * 0.04, 0), back])
		draw_colored_polygon(fin, Color(body_color.lightened(0.05), 0.85))
		for r in 4:   # the fin's rays
			draw_line(base, tip.lerp(back, r / 3.0), Color(glow, 0.3), 1.5, true)
		draw_polyline(PackedVector2Array([tip, tip.lerp(back, 0.5) + Vector2(side * L * 0.04, 0), back]), Color(glow, 0.55), 2.0, true)


func _draw_head(L: float, charge: float) -> void:
	var head := Vector2(_sway(0.0), -L * 0.42)
	# Mandibles: open as it charges and fires.
	var open := 0.25 + 0.75 * charge + 0.08 * sin(_t * 5.0)
	for side in [-1.0, 1.0]:
		var root := head + Vector2(side * L * 0.06, -L * 0.04)
		var tip := root + Vector2(side * L * 0.03, -L * 0.13).rotated(side * open * 0.6)
		var mid := root.lerp(tip, 0.5) + Vector2(side * L * 0.035, 0)
		draw_colored_polygon(PackedVector2Array([root, mid, tip, root.lerp(tip, 0.55)]), body_color.lightened(0.15))
		draw_line(mid, tip, Color(1.0, 0.9, 0.7, 0.8), 2.0, true)
	draw_circle(head, L * 0.11, body_color.darkened(0.15))
	draw_circle(head + Vector2(0, -L * 0.01), L * 0.095, body_color.lightened(0.06))
	# The maw, with energy gathering in it.
	var maw := Vector2(head.x, -L * 0.5)
	if charge > 0.0:
		var g := ORB_COLOR.lerp(ORB_COLOR_2, 0.5 + 0.5 * sin(_t * 6.0))
		draw_circle(maw, L * 0.07 * charge, Color(g, 0.25))
		draw_circle(maw, L * 0.04 * charge, Color(g, 0.7))
		draw_circle(maw, L * 0.018 * charge, Color(1, 1, 1, 0.95))
		for k in 6:   # sparks drawn in
			var a := _t * 7.0 + k * TAU / 6.0
			var d := L * 0.12 * (1.0 - fmod(_t * 2.0 + k * 0.17, 1.0))
			draw_circle(maw + Vector2.from_angle(a) * d, 2.0, Color(g, 0.8))
	# Eyes: four, the big pair tracking you, blinking.
	var lid := 1.0 if _blink > 0.0 else 0.15
	for e in [[-0.055, 0.0, 0.032], [0.055, 0.0, 0.032], [-0.075, 0.045, 0.016], [0.075, 0.045, 0.016]]:
		var c: Vector2 = head + Vector2(e[0] * L, e[1] * L)
		var r: float = e[2] * L
		draw_set_transform(c, 0.0, Vector2(1.0, lid))
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.92, 0.45))
		draw_circle(_look * r * 0.35, r * 0.45, Color(0.08, 0.0, 0.05))
		draw_circle(_look * r * 0.35 + Vector2(-r * 0.15, -r * 0.2), r * 0.15, Color(1, 1, 1, 0.8))
		draw_set_transform(Vector2.ZERO)


## A ball of energy: drifts (curving if `curve`), glowing, for LIFE seconds;
## touching your ship (within HITBOX of its centre) hurts it.
class Orb extends Node2D:
	## Its damage type by its look (Gear.DAMAGE_TYPES; the rest kinetic).
	const ORB_TYPES := {"flame": "heat", "ember": "heat", "frost": "cold", "ice": "cold", "venom": "energy",
		"miasma": "energy", "ghost": "energy", "wave": "energy"}
	const LIFE := 7.0
	const HITBOX := 0.55                # x your ship's hit radius
	## orb (glowing ball), bubble (Skylla: a pink bubble with a highlight,
	## wobbling), ink (Skylla: a dark teardrop), spear (the Minotaur: a gold
	## arrowhead with a red edge), flame (Cerberus: a fireball with a
	## flickering tail), ember (Cerberus: a small spark), wave (Skylla: a
	## curling sea wave with foam on its crest), ghost (Cerberus: a wailing
	## soul of Hades, drifting toward you), serpent (Echidna: a little snake
	## of her brood, slithering), venom (Echidna: a glowing green drop), fang
	## (the Hydra: a curved ivory tooth, its tip bloody), miasma (the Hydra's
	## poison breath: a dark green cloud, swelling as it drifts).
	const STYLES := ["orb", "bubble", "ink", "spear", "flame", "ember", "wave", "ghost", "serpent", "venom", "fang", "miasma"]
	var velocity := Vector2.ZERO
	var curve := 0.0                    # turning, rad / s
	var wobble := 0.0                   # sideways sway, px / s
	var accel := 0.0                    # speeding up (+) or slowing (-), px / s2
	var home := 0.0                     # turning toward you, rad / s (souls)
	var top := 245.0                    # fastest it accelerates to (more if fired at you fleeing)
	var style := "orb"
	var color := Color(0.55, 1.0, 0.45)
	var damage := 7.0
	var radius := 11.0
	var source: Node2D
	var _age := 0.0
	var _seed := 0.0

	static var _ships_cache: Array = []
	static var _ships_frame := -1

	## The NPC ships (looked up once a frame for all the orbs).
	func _ships() -> Array:
		var f := Engine.get_process_frames()
		if f != _ships_frame:
			_ships_frame = f
			_ships_cache = get_tree().get_nodes_in_group("neutrals")
		return _ships_cache

	func _ready() -> void:
		add_to_group("monster_orbs")
		z_index = 6
		_seed = randf() * TAU
		if not style in ["ink", "wave", "ghost", "serpent", "fang", "miasma"]:   # (these have dark parts: drawn normally, the rest glow)
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			material = m
		match style:
			"bubble": radius = 13.0
			"ember": radius = 7.0
			"spear": radius = 9.0
			"flame": radius = 12.0
			"wave": radius = 16.0
			"ghost": radius = 13.0
			"serpent": radius = 12.0
			"venom": radius = 10.0
			"fang": radius = 9.0
			"miasma": radius = 20.0

	func _process(delta: float) -> void:
		_age += delta
		velocity = velocity.rotated(curve * delta)
		if home > 0.0:
			var pl := get_tree().get_first_node_in_group("player") as Node2D
			if pl:
				var want := (pl.global_position - global_position).angle()
				velocity = velocity.rotated(clampf(wrapf(want - velocity.angle(), -PI, PI), -home * delta, home * delta))
		if accel != 0.0:
			velocity = velocity.normalized() * clampf(velocity.length() + accel * delta, 40.0, top)
		position += velocity * delta
		if wobble != 0.0:
			position += velocity.normalized().orthogonal() * cos(_age * 5.0 + _seed) * wobble * delta
		if _age > LIFE:
			queue_free()
			return
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p and p.is_alive():
			var hr: float = float(p.get("hit_radius")) if p.get("hit_radius") != null else 36.0
			if global_position.distance_to(p.global_position) < hr * HITBOX + radius:
				p.take_damage(damage, global_position, source if is_instance_valid(source) else null, ORB_TYPES.get(style, "kinetic"))
				Effects.spark(global_position, color)
				queue_free()
				return
		# NPC ships in its path are hit too (a creature hunting you through a system).
		for n in _ships():
			if is_instance_valid(n) and n.is_alive() and global_position.distance_to(n.global_position) < float(n.hit_radius) * HITBOX + radius:
				n.take_damage(damage, global_position, source if is_instance_valid(source) else null, ORB_TYPES.get(style, "kinetic"))
				Effects.spark(global_position, color)
				queue_free()
				return
		if UI.redraw_due(self):   # (its pulse; it moves with its node every frame)
			queue_redraw()

	## A filled circle from the baked disc (batched; draw_circle by the dozen cost a fight 0.4 ms).
	func _disc(at: Vector2, r: float, c: Color) -> void:
		draw_texture_rect(ExhaustTrail.disc(), Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, c)

	func _draw() -> void:
		var fade := clampf((LIFE - _age) / 0.6, 0.0, 1.0) * clampf(_age / 0.12, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_age * 12.0 + _seed)
		var dir := velocity.normalized() if velocity.length() > 1.0 else Vector2.UP
		var side := dir.orthogonal()
		var r := radius
		match style:
			"bubble":
				var rr := r * (1.0 + 0.08 * sin(_age * 9.0 + _seed))
				_disc(Vector2.ZERO, rr * 1.6, Color(color, 0.1 * fade))
				_disc(Vector2.ZERO, rr, Color(color, 0.22 * fade))
				draw_arc(Vector2.ZERO, rr, 0, TAU, 24, Color(color.lightened(0.3), 0.85 * fade), 2.0, true)
				_disc(Vector2(-rr * 0.35, -rr * 0.35), rr * 0.28, Color(1, 1, 1, 0.85 * fade))
			"ink":
				var tail := -dir * r * 2.2
				draw_colored_polygon(PackedVector2Array([side * r * 0.8, tail, -side * r * 0.8]), Color(0.1, 0.0, 0.16, 0.9 * fade))
				_disc(Vector2.ZERO, r, Color(0.12, 0.0, 0.2, 0.95 * fade))
				draw_arc(Vector2.ZERO, r, 0, TAU, 20, Color(0.85, 0.3, 1.0, 0.8 * fade), 2.0, true)
				_disc(dir * r * 0.3 - side * r * 0.3, r * 0.22, Color(0.9, 0.6, 1.0, 0.8 * fade))
			"spear":
				var tip := dir * r * 2.2
				var back := -dir * r * 1.6
				draw_line(back * 2.0, back, Color(color, 0.25 * fade), r * 0.8, true)
				draw_colored_polygon(PackedVector2Array([tip, side * r * 0.75 - dir * r * 0.3, back, -side * r * 0.75 - dir * r * 0.3]), Color(color, 0.9 * fade))
				draw_colored_polygon(PackedVector2Array([tip * 0.8, side * r * 0.3, back * 0.6, -side * r * 0.3]), Color(1.0, 0.95, 0.75, 0.95 * fade))
			"flame":
				for k in 5:
					var t := float(k) / 5.0
					var p := -dir * r * (0.6 + t * 2.4) + side * sin(_age * 22.0 + k + _seed) * r * 0.35 * t
					_disc(p, r * (1.0 - t * 0.7), Color(1.0, 0.75 - t * 0.45, 0.15, (0.6 - t * 0.45) * fade))
				_disc(Vector2.ZERO, r * (1.5 + 0.25 * pulse), Color(color, 0.18 * fade))
				_disc(Vector2.ZERO, r, Color(1.0, 0.55, 0.1, 0.85 * fade))
				_disc(Vector2.ZERO, r * 0.5, Color(1.0, 0.95, 0.7, 0.95 * fade))
			"wave":   # a breaking wave: a crescent of water bulging the way it rolls, its tips curling back, foam on the crest
				var span := 1.15
				var outer := PackedVector2Array()
				var inner := PackedVector2Array()
				for i in 17:
					var a := -span + 2.0 * span * i / 16.0
					var swell := 1.0 + 0.06 * sin(a * 5.0 + _age * 7.0 + _seed)
					outer.append((dir * cos(a) + side * sin(a)) * r * 1.5 * swell - dir * r * 0.6)
					inner.append((dir * cos(a) + side * sin(a)) * r * 0.85 - dir * r * 1.05)
				var body := outer.duplicate()
				for i in range(16, -1, -1):
					body.append(inner[i])
				if not Geometry2D.triangulate_polygon(body).is_empty():
					draw_colored_polygon(body, Color(0.07, 0.25, 0.65, 0.92 * fade))
				# The lit face just behind the crest, then the crest itself.
				var face := PackedVector2Array()
				for i in 17:
					face.append(outer[i].lerp(inner[i], 0.35))
				draw_polyline(face, Color(0.25, 0.6, 1.0, 0.85 * fade), r * 0.35, true)
				draw_polyline(outer, Color(0.6, 0.9, 1.0, 0.95 * fade), 2.5, true)
				# The tips curling back.
				for e in [0, 16]:
					var tip := outer[e]
					var back := (inner[e] - outer[e]).normalized()
					draw_arc(tip + back * r * 0.35, r * 0.35, back.angle() + PI * 0.4, back.angle() + PI * 1.6, 8, Color(0.6, 0.9, 1.0, 0.9 * fade), 2.5, true)
				# Foam along the crest, and spray flying ahead of it.
				for i in range(1, 16, 2):
					_disc(outer[i] + dir * r * 0.05, r * (0.17 + 0.07 * sin(_age * 9.0 + i + _seed)), Color(0.95, 0.98, 1.0, 0.95 * fade))
				for i in 4:
					var sp := outer[3 + i * 3] + dir * r * (0.35 + 0.25 * fposmod(_age * 2.0 + i * 0.37 + _seed, 1.0))
					_disc(sp, r * 0.08, Color(1, 1, 1, 0.8 * fade))
			"ghost":   # a wailing soul: a pale head with hollow eyes, a wisp of tail trailing
				var sway := sin(_age * 6.0 + _seed)
				for k in 6:
					var t := float(k) / 6.0
					var p := -dir * r * (0.6 + t * 2.6) + side * sin(_age * 7.0 + k * 0.9 + _seed) * r * 0.5 * t
					_disc(p, r * (0.85 - t * 0.6), Color(0.55, 1.0, 0.85, (0.35 - t * 0.28) * fade))
				_disc(Vector2.ZERO, r * 1.7, Color(0.4, 1.0, 0.8, 0.12 * fade))
				_disc(Vector2.ZERO, r, Color(0.75, 1.0, 0.92, 0.75 * fade))
				for e in [-1.0, 1.0]:
					_disc(dir * r * 0.15 + side * e * r * 0.35, r * 0.2, Color(0.02, 0.08, 0.06, 0.9 * fade))
				_disc(-dir * r * 0.35 + side * sway * r * 0.05, r * 0.22, Color(0.02, 0.08, 0.06, 0.8 * fade))   # the wailing mouth
			"serpent":   # Echidna's brood: a little snake slithering, scaled, gold-banded, its tongue flicking
				var pts := PackedVector2Array()
				for k in 9:
					var t := float(k) / 8.0
					pts.append(-dir * r * (0.5 + t * 3.4) + side * sin(_age * 11.0 - k * 0.9 + _seed) * r * 0.55 * (0.3 + t))
				for k in range(8, -1, -1):   # tail first, the head on top
					var t := float(k) / 8.0
					var w := r * (0.62 - t * 0.42)
					_disc(pts[k], w + 1.5, Color(0.05, 0.04, 0.12, 0.9 * fade))
					_disc(pts[k], w, Color(0.22, 0.27, 0.62, fade) if k % 3 else Color(0.95, 0.72, 0.2, fade))
				var head := PackedVector2Array([dir * r * 1.05, side * r * 0.62, -dir * r * 0.55 + side * r * 0.45, -dir * r * 0.55 - side * r * 0.45, -side * r * 0.62])
				draw_colored_polygon(head, Color(0.18, 0.22, 0.55, fade))
				draw_polyline(head + PackedVector2Array([head[0]]), Color(0.05, 0.04, 0.12, 0.9 * fade), 1.5, true)
				for e in [-1.0, 1.0]:
					_disc(dir * r * 0.2 + side * e * r * 0.3, r * 0.16, Color(1.0, 0.8, 0.2, fade))
				if fmod(_age + _seed, 0.6) < 0.25:   # the forked tongue
					var tt := dir * r * 1.7
					draw_line(dir * r * 1.0, tt, Color(0.9, 0.1, 0.15, fade), 1.5, true)
					draw_line(tt, tt + (dir + side * 0.6) * r * 0.35, Color(0.9, 0.1, 0.15, fade), 1.2, true)
					draw_line(tt, tt + (dir - side * 0.6) * r * 0.35, Color(0.9, 0.1, 0.15, fade), 1.2, true)
			"venom":   # Echidna's venom: a glowing green drop, dripping
				for k in 4:
					var t := float(k + 1) / 5.0
					_disc(-dir * r * (0.8 + t * 2.0) + side * sin(_age * 9.0 + k + _seed) * r * 0.2, r * (0.5 - t * 0.35), Color(color, (0.5 - t * 0.35) * fade))
				_disc(Vector2.ZERO, r * (1.7 + 0.3 * pulse), Color(color, 0.15 * fade))
				draw_colored_polygon(PackedVector2Array([dir * r * 1.5, side * r * 0.85, -dir * r * 0.9, -side * r * 0.85]), Color(color, 0.85 * fade))
				_disc(Vector2.ZERO, r * 0.85, Color(color, 0.9 * fade))
				_disc(dir * r * 0.2 - side * r * 0.25, r * 0.3, Color(0.9, 1.0, 0.8, 0.95 * fade))
			"fang":   # the Hydra's tooth: a curved ivory fang, point first, its tip bloody
				var pts := PackedVector2Array()
				for k in 7:
					var t := float(k) / 6.0
					pts.append(dir * r * (1.6 - t * 3.0) + side * r * 0.6 * t * t)
				var outline := PackedVector2Array()
				for k in 7:
					outline.append(pts[k] + side * r * 0.55 * float(k) / 6.0)
				for k in range(6, -1, -1):
					outline.append(pts[k] - side * r * 0.25 * float(k) / 6.0)
				if not Geometry2D.triangulate_polygon(outline).is_empty():
					draw_colored_polygon(outline, Color(0.98, 0.95, 0.85, fade))
					draw_polyline(outline + PackedVector2Array([outline[0]]), Color(0.25, 0.15, 0.1, 0.9 * fade), 1.5, true)
				_disc(pts[0] - dir * r * 0.25, r * 0.22, Color(0.85, 0.08, 0.1, 0.95 * fade))
				draw_line(pts[1], pts[4], Color(1, 1, 1, 0.7 * fade), 1.2, true)
			"miasma":   # poison breath: a dark green cloud of puffs, churning, swelling as it drifts
				var grow := 1.0 + minf(_age, 4.0) * 0.12
				for k in 6:
					var a := k * TAU / 6.0 + _age * (0.8 if k % 2 else -0.6) + _seed
					var p := Vector2.from_angle(a) * r * 0.55 * grow
					_disc(p, r * 0.62 * grow, Color(0.12, 0.3, 0.08, 0.55 * fade))
				_disc(Vector2.ZERO, r * 0.75 * grow, Color(0.2, 0.42, 0.1, 0.65 * fade))
				for k in 3:
					var a := k * TAU / 3.0 - _age * 1.3 + _seed
					_disc(Vector2.from_angle(a) * r * 0.35 * grow, r * 0.22, Color(0.55, 0.85, 0.3, 0.6 * fade))
			"ember":
				draw_line(Vector2.ZERO, -dir * r * 3.0, Color(color, 0.35 * fade), r * 0.9, true)
				_disc(Vector2.ZERO, r * (1.4 + 0.4 * pulse), Color(color, 0.25 * fade))
				_disc(Vector2.ZERO, r * 0.6, Color(1.0, 0.9, 0.6, 0.95 * fade))
			_:
				draw_line(Vector2.ZERO, -dir * r * 1.6, Color(color, 0.25 * fade), r * 1.4, true)   # a short trail
				_disc(Vector2.ZERO, r * (1.9 + 0.3 * pulse), Color(color, 0.16 * fade))
				_disc(Vector2.ZERO, r, Color(color, 0.75 * fade))
				_disc(Vector2.ZERO, r * 0.5, Color(1, 1, 1, 0.95 * fade))
