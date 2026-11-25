class_name ExhaustTrail
extends Node2D
## A ship's exhaust trail, after the reference sheet (Downloads, 80s-anime
## jets): a billowing, lumpy cloud of exhaust in the trail's colour, darker and
## more smoky as it drifts back, with crackling lightning-like streaks of light
## running through it, a white-hot plume at the nozzle, and a thin curling tip.
## It follows where the nozzle has been (world space), so turns leave curves;
## each puff leaves the nozzle with the ship's own velocity plus a push out
## backward (EJECT), then slows to rest (DRAG) - so it streams straight out
## behind the nozzle whichever way the ship points, even turning hard at full
## speed (the flame and the trail agree), and settles along the path behind -
## and every part fades with age - a trail is a few hundred px long, never
## the whole window. Styles: "blue", "orange", "magenta" (the reference's three).
##
## Added to a ship by ExhaustTrail.attach(ship, style); reads the ship's
## nozzle position, heading and thrust each frame (player Ship or Enemy).

const STYLES := {
	# cloud near the nozzle, cloud far back, streaks / core, plume tip
	"blue": [Color(0.16, 0.56, 1.0), Color(0.12, 0.3, 0.8), Color(0.72, 0.95, 1.0), Color(0.35, 0.8, 1.0)],
	"orange": [Color(1.0, 0.5, 0.1), Color(0.8, 0.28, 0.12), Color(1.0, 0.92, 0.55), Color(1.0, 0.75, 0.2)],
	"magenta": [Color(0.98, 0.28, 0.78), Color(0.56, 0.3, 0.9), Color(1.0, 0.85, 0.96), Color(1.0, 0.45, 0.85)],
}
const LIFE := 1.6                   # seconds a puff of exhaust lasts
const SPACING := 12.0               # px between trail points (the puffs overlap well: fewer to draw)
const STREAKS := 3
const EJECT := 2.2                  # a puff's speed out of the nozzle at full thrust: max_len per second this many (far quicker than the ship: a straight jet)
const ATTACH := 0.25                # s: fresh exhaust drawn fixed to the nozzle, easing free
const DRAG := 5.0                   # how fast it slows (per second: it comes to rest ~EJECT/DRAG max_len out)

var ship: Node2D
var style := "blue"
var width := 14.0                   # the cloud's half-width at its fullest
var max_len := 600.0                # never longer than this (px)
# The trail's points, newest first (packed arrays: dictionaries per point
# were most of a trail's cost): where, born when, thrust 0..1, its puff's seed.
var _pp := PackedVector2Array()
var _pt := PackedFloat32Array()
var _pk := PackedFloat32Array()
var _ps := PackedFloat32Array()
var _pv := PackedVector2Array()     # each point's drift (px/s: thrown out of the nozzle)
var _moved_at := -1.0               # (_time the points last drifted)
var _time := 0.0
var _glow: Node2D                   # additive layer: streaks and core
var _plume: Node2D                  # additive layer: the plume at the nozzle (every frame)
## The cloud and its streaks are redrawn this often (a second): the points
## move on every frame, but a picture of the cloud 60 times a second is what
## a screen shows - at 240 FPS, redrawing every trail every frame was the
## biggest cost of a battle.
const CLOUD_HZ := 60.0
var _flick := 0                     # re-jags the streaks a few times a second
var _seed := 0
var _count := 0                    # points made so far (puffs follow it)


## Gives `ship` a trail (sized from its length): returns it.
static func attach(s: Node2D, trail_style: String, ship_length: float) -> ExhaustTrail:
	var t := ExhaustTrail.new()
	t.ship = s
	t.style = trail_style if STYLES.has(trail_style) else "blue"
	t.width = clampf(ship_length * 0.22, 11.0, 50.0)
	t.max_len = clampf(ship_length * 5.0, 320.0, 760.0)
	s.add_child(t)
	return t


func _ready() -> void:
	name = "ExhaustTrail"
	top_level = true                # (world coordinates: the trail stays where it was left)
	z_as_relative = true
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # (the puffs' disc, small far back)
	_seed = randi()
	_glow = Node2D.new()
	_glow.top_level = true
	_glow.z_index = -1
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = m
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_plume = Node2D.new()
	_plume.top_level = true
	_plume.z_index = -1
	_plume.material = m
	_plume.draw.connect(_draw_plume)
	add_child(_plume)


## The ship's nozzle (world), backwards direction, thrust 0..1 and velocity.
func _engine() -> Array:
	if ship.get("engine_offset") != null:   # the player's Ship: rotates as a whole, nose to -Y
		var back: Vector2 = (ship.global_transform.basis_xform(Vector2(0, 1))).normalized()
		var nozzle: Vector2 = ship.global_transform * (ship.engine_offset + Vector2(0, 4))
		var boost := 1.25 if float(ship.get("boost_time")) > 0.0 else 1.0
		var sv: Vector2 = ship.get("velocity") if ship.get("velocity") != null else Vector2.ZERO
		return [nozzle, back, clampf(float(ship.thrust) * boost, 0.0, 1.3), sv]
	# An Enemy: its body turns (nose to -Y), the node doesn't.
	var body: Node2D = ship.get("body")
	var rot: float = body.global_rotation if body else 0.0
	var back2 := Vector2(0, 1).rotated(rot)
	var half: float = float(ship.get("_half_height")) if ship.get("_half_height") != null else 40.0
	var v: Vector2 = ship.get("velocity") if ship.get("velocity") != null else Vector2.ZERO
	var top: float = maxf(float(ship.get("max_speed")), 1.0)
	return [ship.global_position + back2 * half * 0.82, back2, clampf(v.length() / top, 0.0, 1.0), v]


func _process(delta: float) -> void:
	_time += delta
	global_position = Vector2.ZERO
	global_rotation = 0.0
	_glow.global_position = Vector2.ZERO
	# The plume rides the nozzle: its node moved there each frame (no redraw),
	# its picture redrawn CLOUD_HZ times a second like the cloud (redrawing
	# every ship's plume every frame was a battle's biggest drawing cost).
	var live: bool = is_instance_valid(ship) and ship.has_method("is_alive") and ship.is_alive()
	if live:
		var pe := _engine()
		if (pe[0] as Vector2).is_finite() and (pe[1] as Vector2).length() > 0.5:
			_plume.global_position = pe[0]
			_plume.global_rotation = (pe[1] as Vector2).angle() - PI * 0.5   # (its +Y: backward out of the nozzle)
			_plume_k = pe[2]
	# (the cloud: kept up and redrawn CLOUD_HZ times a second for your ship;
	# others' half as often, and off screen just kept up, 10 times a second -
	# the trails were the biggest script cost in space)
	var hz := CLOUD_HZ if ship != null and ship.get("engine_offset") != null else (CLOUD_HZ * 0.5 if _on_screen() else 10.0)
	if not UI.redraw_due(self, hz):
		return
	_plume.queue_redraw()
	# The exhaust drifts the way it was thrown, slowing.
	var dt := clampf(_time - _moved_at, 0.0, 0.1) if _moved_at >= 0.0 else 0.0
	_moved_at = _time
	if dt > 0.0:
		var slow := exp(-DRAG * dt)
		for i in range(1, _pp.size()):
			_pp[i] += _pv[i] * dt
			_pv[i] *= slow
	var alive: bool = is_instance_valid(ship) and ship.has_method("is_alive") and ship.is_alive() and ship.visible
	if alive:
		var e := _engine()
		var nozzle: Vector2 = e[0]
		var k: float = e[2]
		# (Pushed out hard even at low thrust - turning, the ship throttles back,
		# and a weak push would leave the newest exhaust on the old path, off
		# the flame; low thrust shows as faint exhaust instead.)
		var thrown: Vector2 = e[3] + e[1] * EJECT * max_len * (0.6 + 0.4 * minf(k, 1.0))
		# The newest point rides the nozzle; once it's SPACING past the last
		# fixed one it stays put and a new one starts.
		if _pp.size() < 2 or nozzle.distance_to(_pp[1]) >= SPACING:
			_count += 1
			_pp.insert(0, nozzle)
			_pt.insert(0, _time)
			_pk.insert(0, k)
			_ps.insert(0, float(_count))
			_pv.insert(0, thrown)
		else:
			_pp[0] = nozzle
			_pk[0] = k
			_pt[0] = _time
			_pv[0] = thrown
	# Old puffs fade out; the trail never reaches past max_len from the nozzle
	# (straight out: measured along it, a spin's spray of exhaust - zigzagging
	# from one direction to the next - would be cut off early).
	var keep := 0
	for i in _pp.size():
		if _time - _pt[i] > LIFE or (i > 0 and _pp[i].distance_to(_pp[0]) > max_len):
			break
		keep = i + 1
	_pp.resize(keep)
	_pt.resize(keep)
	_pk.resize(keep)
	_ps.resize(keep)
	_pv.resize(keep)
	if Engine.get_process_frames() % 4 == 0:
		_flick += 1
	queue_redraw()
	_glow.queue_redraw()


func _on_screen() -> bool:
	if _pp.is_empty():
		return false
	var vr := get_viewport_rect()
	var ct := get_canvas_transform()
	var p: Vector2 = ct * _pp[0]
	return vr.grow(max_len * ct.get_scale().x + 50.0).has_point(p)


## Per point (worked out once a frame - the cloud and the glow both use it):
## its place, side vector, distance along the trail (0..1), age (0..1), fade
## and the cloud's half-width there.
var _fp := PackedVector2Array()
var _fs := PackedVector2Array()
var _fu := PackedFloat32Array()
var _fa := PackedFloat32Array()
var _ff := PackedFloat32Array()
var _fh := PackedFloat32Array()
var _f_at := -1

func _frame() -> void:
	var now := Engine.get_process_frames()
	if now == _f_at:
		return
	_f_at = now
	var n := _pp.size()
	_fp = _pp.duplicate()   # (packed arrays are shared, not copied, by `=`: the points may change before it's drawn)
	# The fresh exhaust is drawn as a flame fixed to the nozzle: straight out
	# behind it (at each puff's own distance), easing over ATTACH seconds into
	# where it has really drifted - so however hard the ship turns or changes
	# speed, the trail leaves the nozzle along the flame, then bends away.
	if n > 1 and is_instance_valid(ship) and ship.has_method("is_alive") and ship.is_alive():
		var e := _engine()
		var nozzle: Vector2 = e[0]
		var back: Vector2 = e[1]
		for i in range(1, n):
			var w := 1.0 - smoothstep(0.0, ATTACH, _time - _pt[i])
			if w <= 0.0:
				break
			_fp[i] = _pp[i].lerp(nozzle + back * nozzle.distance_to(_pp[i]), w)
	_fs.resize(n)
	_fu.resize(n)
	_fa.resize(n)
	_ff.resize(n)
	_fh.resize(n)
	var along := 0.0
	var inv := 1.0 / maxf(max_len, 1.0)
	for i in n:
		var p: Vector2 = _fp[i]
		if i > 0:
			along += p.distance_to(_fp[i - 1])
		var dir: Vector2 = _fp[mini(i + 1, n - 1)] - _fp[maxi(i - 1, 0)]
		if dir.length() < 0.01:
			dir = Vector2(0, 1)
		_fs[i] = dir.normalized().orthogonal()
		var age := (_time - _pt[i]) / LIFE
		var u := along * inv
		_fu[i] = u
		_fa[i] = age
		# (sqrt: turning, the ship throttles right back - its exhaust still shows,
		# streaming out along the flame, instead of only the jet from before the turn)
		_ff[i] = pow(clampf(1.0 - age, 0.0, 1.0), 1.4) * clampf(sqrt(maxf(_pk[i], 0.0)) * 1.4, 0.0, 1.0)
		_fh[i] = _half(u, age, _ps[i])


## The cloud's half-width at a point: narrow at the nozzle, billowing out as
## it spreads with age, lumpy (each puff its own size), tapering to a thin tip.
func _half(u: float, age: float, seed: float) -> float:
	var grow := 0.3 + 0.7 * smoothstep(0.0, 0.28, u)
	var tip := pow(1.0 - smoothstep(0.42, 1.0, u), 1.2)
	# Puffs: round billows of different sizes, fixed to the exhaust as it drifts.
	var lump := 0.78 + 0.22 * sin(seed * 0.83) + 0.12 * sin(seed * 2.1 + 1.0)
	return width * grow * tip * lump * (1.0 + 1.1 * age * (1.0 - u * 0.6))


func _draw() -> void:
	if not _on_screen() or _pp.size() < 2:
		return
	var s: Array = STYLES[style]
	_frame()
	var n := _fp.size()
	# The billowing exhaust, cel-shaded like the reference: round puffs in three
	# flat tones - a darker shade on one side, the body, a light band along the
	# other - drawn tail first so the fresh puffs sit on top.
	var c0: Color = s[0]
	var c1: Color = s[1]
	var cols := PackedColorArray()
	var alpha := PackedFloat32Array()
	cols.resize(n)
	alpha.resize(n)
	for i in n:
		cols[i] = c0.lerp(c1, clampf(_fu[i] * 1.2, 0.0, 1.0))
		alpha[i] = clampf(_ff[i] * 1.8, 0.0, 1.0)   # (opaque, like the reference, until the tail fades)
	var tex := disc()
	for tone in 3:
		for i in range(n - 1, -1, -1):
			var a: float = alpha[i]
			var r: float = _fh[i]
			if a <= 0.02 or r < 0.8:
				continue
			var side: Vector2 = _fs[i]
			var at: Vector2
			var rr: float
			var c: Color
			match tone:
				0:
					at = _fp[i] + side * r * 0.18
					rr = r * 1.06
					c = Color(cols[i].darkened(0.42), 0.9 * a)
				1:
					at = _fp[i] - side * r * 0.04
					rr = r * 0.9
					c = Color(cols[i], 0.92 * a)
				_:
					at = _fp[i] - side * r * 0.34
					rr = r * 0.46
					c = Color(cols[i].lightened(0.3), 0.8 * a)
			draw_texture_rect(tex, Rect2(at.x - rr, at.y - rr, rr * 2.0, rr * 2.0), false, c)


## A puff: the baked disc (one texture for every puff of every trail - Godot
## batches them into a few draw calls; anti-aliased draw_circle()s, hundreds a
## frame, cost a battle half its frame time).
func _puff(at: Vector2, r: float, c: Color) -> void:
	draw_texture_rect(disc(), Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, c)


static var _disc: Texture2D

## A white disc with a one-pixel soft edge (as draw_circle's anti-aliasing), 128 px.
static func disc() -> Texture2D:
	if _disc == null:
		var n := 128
		var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
		var c := (n - 1) * 0.5
		for y in n:
			for x in n:
				var d := Vector2(x - c, y - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(c - d + 0.5, 0.0, 1.0)))
		img.generate_mipmaps()
		_disc = ImageTexture.create_from_image(img)
	return _disc


func _draw_glow() -> void:
	if not _on_screen() or _pp.size() < 2:
		return
	var s: Array = STYLES[style]
	_frame()
	var n := _fp.size()
	var ci := _glow
	var hot: Color = s[2]
	# The hot core: white-hot near the nozzle, gone a quarter of the way back.
	var core := PackedVector2Array()
	var core_c := PackedColorArray()
	for i in n:
		if _fu[i] > 0.28:
			break
		core.append(_fp[i])
		core_c.append(Color(hot, _ff[i] * 0.8 * (1.0 - _fu[i] / 0.28)))
	if core.size() >= 2:
		ci.draw_polyline_colors(core, core_c, width * 0.45, true)
	# Lightning-like streaks crackling through the cloud (re-jagged often) -
	# all three in one pass over the points, the jags from a cheap hash.
	var l0 := PackedVector2Array()
	var l1 := PackedVector2Array()
	var l2 := PackedVector2Array()
	var k0 := PackedColorArray()
	var k1 := PackedColorArray()
	var k2 := PackedColorArray()
	var ph0 := fposmod(sin(float(_seed % 9973) * 0.731) * 43758.5453, 1.0) * TAU
	var ph1 := fposmod(sin(float(_seed % 9973) * 0.731 + 12.9898) * 43758.5453, 1.0) * TAU
	var ph2 := fposmod(sin(float(_seed % 9973) * 0.731 + 25.9796) * 43758.5453, 1.0) * TAU
	var flick := float(_flick) * 37.719
	var t3 := _time * 3.0
	for i in range(0, n, 2):   # (every other point: jagged enough, half the cost - the costliest drawing of a battle)
		var u: float = _fu[i]
		if u > 0.9:
			break
		var w: float = _fh[i] * 0.7
		var sw: Vector2 = _fs[i] * w
		var base: float = _ff[i] * (1.0 - u * 0.8)
		var fi := i * 12.9898 + flick
		l0.append(_fp[i] + sw * (sin(ph0 + u * 9.0 + t3) * 0.55 + fposmod(sin(fi) * 43758.5453, 1.0) * 0.5 - 0.25))
		l1.append(_fp[i] + sw * (sin(ph1 + u * 13.0 + t3) * 0.55 + fposmod(sin(fi + 78.233) * 43758.5453, 1.0) * 0.5 - 0.25))
		l2.append(_fp[i] + sw * (sin(ph2 + u * 17.0 + t3) * 0.55 + fposmod(sin(fi + 156.466) * 43758.5453, 1.0) * 0.5 - 0.25))
		k0.append(Color(hot, base))
		k1.append(Color(hot, base * 0.8))
		k2.append(Color(hot, base * 0.6))
	if l0.size() >= 2:
		ci.draw_polyline_colors(l0, k0, 2.2, true)
		ci.draw_polyline_colors(l1, k1, 1.4, true)
		ci.draw_polyline_colors(l2, k2, 1.4, true)


## The plume: white-hot at the nozzle, a flame of the trail's colour behind -
## redrawn every frame (it rides the nozzle; the cloud behind it at CLOUD_HZ).
var _plume_k := 0.0   # the thrust the plume shows (set each frame)

func _draw_plume() -> void:
	var s: Array = STYLES[style]
	var ci := _plume
	if not _on_screen():
		return
	if is_instance_valid(ship) and ship.has_method("is_alive") and ship.is_alive():
		var k2 := _plume_k
		if k2 > 0.03:
			# (In the plume node's own space - it sits on the nozzle, +Y backward -
			# which also keeps the small triangles precise far out, at the signal sites.)
			var back := Vector2(0, 1)
			var side := Vector2(1, 0)
			var length := width * (2.2 + 2.0 * k2) * randf_range(0.9, 1.1)
			var wd := width * 0.5
			if length < 2.0:
				return
			ci.draw_colored_polygon(PackedVector2Array([side * wd, -side * wd, back * length]), Color(s[3], 0.55 * k2))
			ci.draw_colored_polygon(PackedVector2Array([side * wd * 0.5, -side * wd * 0.5, back * length * 0.6]), Color(1, 1, 1, 0.75 * k2))
			var dt := disc()
			ci.draw_texture_rect(dt, Rect2(-Vector2.ONE * wd * 1.6, Vector2.ONE * wd * 3.2), false, Color(s[3], 0.22 * k2))
			ci.draw_texture_rect(dt, Rect2(-Vector2.ONE * wd * 0.75, Vector2.ONE * wd * 1.5), false, Color(1, 1, 1, 0.65 * k2))
