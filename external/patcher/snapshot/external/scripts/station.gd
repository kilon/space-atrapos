class_name SpaceStation
extends Node2D
## A space station, drawn procedurally: central hub, rotating habitat ring
## with spokes and modules, solar panels, blinking navigation lights and a
## name label. Shows on the minimap (group "stations").

@export var station_name := "Station"
@export var accent := Color(0.3, 0.85, 1.0)
@export var radius := 170.0
@export var spin_speed := 0.12  # ring rotation, radians per second
## Sandbox: the station's Galaxy record (market) and owning empire.
var station_id := ""
var empire := ""
## A siege target (an invasion's warships shoot it - Fleets): its condition is
## the Galaxy record's (Galaxy.station_health, 0..100); HIT_POINTS of damage
## take 1 of it. Below Galaxy.DAMAGED it burns (flames on its sprite); at 0 it
## blows up and is gone from the galaxy.
const HIT_POINTS := 25.0
var velocity := Vector2.ZERO        # (aimed at like a ship)
var hit_radius: float:
	get:
		return radius * 0.85
## Under siege: an invasion of an empire at war with its owner is in its system
## (its safe zone then protects nobody - Fleets.besieged).
var under_attack := false

## Fly within this distance and press E to dock.
var dock_radius: float:
	get:
		return radius + 170.0
## Enemies won't attack the player inside this distance.
var safe_radius: float:
	get:
		return radius + 420.0

var _time := 0.0
## The quest-giver sign: lit while you can take one of its missions.
var bulb: QuestBulb
var _bulb_check := 0.0


## The station whose safe zone contains `pos`, or null.
static func protecting(pos: Vector2) -> Node2D:
	var f := Engine.get_process_frames()
	if f != _list_frame:   # (the stations list once a frame: hundreds of calls in a battle)
		_list_frame = f
		_list = (Engine.get_main_loop() as SceneTree).get_nodes_in_group("stations")
	for st in _list:
		if is_instance_valid(st) and st.is_inside_tree() and not st.under_attack and pos.distance_to(st.global_position) < st.safe_radius:
			return st
	return null

static var _list: Array = []
static var _list_frame := -1



func _ready() -> void:
	Sfx.loop_at("space/station_hum", self, -3.0, 1400.0)   # (heard near it, fading with distance)
	add_to_group("stations")
	add_to_group("station_targets")
	# Only animate/redraw while on screen (includes the safe-zone ring).
	var enabler := VisibleOnScreenEnabler2D.new()
	var reach := safe_radius + 10.0
	enabler.rect = Rect2(-Vector2.ONE * reach, Vector2.ONE * reach * 2.0)
	add_child(enabler)
	_time = randf() * 10.0  # so stations don't spin/blink in sync
	bulb = QuestBulb.new()
	bulb.radius = 26.0
	bulb.position = Vector2(0, -radius - 90.0)
	add_child(bulb)
	_update_bulb()


func _process(delta: float) -> void:
	_time += delta
	_bulb_check -= delta
	if _bulb_check <= 0.0:
		_bulb_check = 0.5
		_update_bulb()
		under_attack = station_id != "" and Fleets.besieged(station_id)
	if UI.near_view(self, safe_radius) and UI.redraw_due(self):   # (its lights and rings: 60 pictures a second - and none off screen)
		queue_redraw()


func is_alive() -> bool:
	return station_id == "" or Galaxy.stations.has(station_id)


func faction_group() -> StringName:
	return &"station_targets"


func health() -> float:
	return Galaxy.station_health(station_id) if station_id != "" else 100.0


## Hit by a bolt (an invader's - or yours: the owner won't like it).
func take_damage(amount: float, from: Vector2, attacker: Node2D = null, dtype := "") -> void:
	if station_id == "" or not is_alive():
		return
	amount = Gear.split(dtype, 0.0, amount).y   # (no shields: a beam barely scratches it)
	if attacker != null and attacker.is_in_group("player"):
		Galaxy.change_reputation(empire, -0.5, "you fired on their station")
		var ms: Node = get_tree().get_first_node_in_group("missions")
		if ms:
			ms.on_station_hit(station_id, amount / HIT_POINTS)   # (strike missions)
	elif is_instance_valid(attacker) and attacker.get("empire") is String and attacker.get("empire") != "":
		# Under attack: a distress call to its own and its allies' fleets nearby
		# (Fleets: at most once a minute a system).
		Fleets.distress(Galaxy.current_system, empire, attacker.get("empire"))
	Galaxy.damage_station(station_id, amount / HIT_POINTS)
	if not Galaxy.stations.has(station_id):
		blow_up()


## Destroyed: a chain of explosions, then gone.
func blow_up() -> void:
	if is_queued_for_deletion():
		return
	for i in 7:
		Effects.explosion(global_position + Vector2.from_angle(randf() * TAU) * randf_range(0.0, radius), randf_range(1.2, 2.6),
			"space/boom_big")
	# Its wreck stays: a great hulk to salvage (Wreck).
	var tex := ProcArt.station_texture(design())
	if tex:
		var k := radius * 2.6 / maxf(tex.get_width(), tex.get_height())
		Wreck.spawn(get_parent(), global_position, tex, Vector2(k, k), _time * spin_speed * 0.35,
			{"kind": "station", "title": station_name, "empire": empire, "toughness": 3000.0})
	queue_free()


## Lit while it gives missions you have room for (Missions.MAX_ACTIVE).
func _update_bulb() -> void:
	var m: Node = get_tree().get_first_node_in_group("missions") if is_inside_tree() else null
	bulb.lit = m != null and m.active.size() < m.MAX_ACTIVE


func _draw() -> void:
	var r := radius
	var spin := _time * spin_speed

	# Safe-zone boundary (faint dashed ring).
	# (one batch of short lines - 24 antialiased arcs each redraw cost the most of it)
	var dashes := 48
	var segs := PackedVector2Array()
	for i in dashes:
		if i % 2 == 0:
			var a0 := TAU * i / dashes + spin * 0.3
			for k in 4:
				segs.append(Vector2.from_angle(a0 + TAU / dashes * k / 4.0) * safe_radius)
				segs.append(Vector2.from_angle(a0 + TAU / dashes * (k + 1) / 4.0) * safe_radius)
	draw_multiline(segs, Color(accent, 0.18), 2.0)
	# Soft glow behind the station (discs of one texture, batched).
	var disc := ExhaustTrail.disc()
	for i in 4:
		var gr := r * (1.25 - i * 0.08)
		draw_texture_rect(disc, Rect2(-Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(accent, 0.03))

	# One of the twelve station designs, picked by the owning empire.
	var tex := ProcArt.station_texture(design())
	if tex != null:
		var k := r * 2.6 / maxf(tex.get_width(), tex.get_height())
		draw_set_transform(Vector2.ZERO, spin * 0.35, Vector2(k, k))
		draw_texture(tex, -ProcArt.origin("station_" + design()))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_nav_lights(r * 1.12, spin * 0.35, 8, StationArt.DESIGNS[design()]["glow"])
		if health() < Galaxy.DAMAGED:
			_draw_fire(r, spin * 0.35)
		elif _fire_layer != null:
			_fire_layer.queue_free()   # (mended: the fires are out)
			_fire_layer = null

	# Docking bay glow, pulsing.
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	draw_circle(Vector2.ZERO, r * 0.07, Color(accent, 0.6 + 0.4 * pulse))
	_draw_label(r)


## The station design (StationArt) this station uses.
func design() -> String:
	return StationArt.design_for(empire, station_id if station_id != "" else station_name)


func _draw_label(r: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-220, r + 56.0), station_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, 440, Settings.fs("world", 20), 6, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-220, r + 56.0), station_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, 440, Settings.fs("world", 20), accent.lightened(0.3))


## Severely damaged: fires on its sprite, at spots fixed by its id (turning
## with it), more and bigger the worse it is. Each fire: a charred scorch on
## the hull, billowing smoke and licking tongues of flame that cool from
## yellow to orange to deep red as they rise (normal blending: they cover the
## hull), and on the additive layer (_fire_layer: light adds up) the heat
## glow, a white-hot heart and embers. One atlas texture (_fire_tex): they all batch.
const FIRE_SOFT := Rect2(0, 0, 128, 128)     # a soft round puff
const FIRE_TONGUE := Rect2(128, 0, 128, 128) # a tongue of flame, pointing up
static var _fire_tex: Texture2D
var _fire_layer: Node2D


static func fire_texture() -> Texture2D:
	if _fire_tex == null:
		var img := Image.create(256, 128, true, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				# Soft puff: a smooth falloff.
				var d := Vector2(x - 63.5, y - 63.5).length() / 60.0
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
				# Tongue: wide and round at the base (bottom), tapering to a
				# point at the top, its sides wavering.
				var v := 1.0 - y / 127.0                 # 0 base .. 1 tip
				var half := 0.48 * pow(1.0 - v, 0.6) * (1.0 + 0.08 * sin(v * 17.0))
				var base := clampf((v - 0.0) / 0.18, 0.0, 1.0)   # rounded bottom
				half *= sqrt(base)
				var dx := absf(x - 63.5) / 63.5
				var t := clampf(1.0 - dx / maxf(half, 0.001), 0.0, 1.0) if half > 0.0 else 0.0
				var ta := t * t * (3.0 - 2.0 * t) * clampf((1.0 - v) * 1.6, 0.0, 1.0)
				img.set_pixel(128 + x, y, Color(1, 1, 1, ta))
		img.generate_mipmaps()
		_fire_tex = ImageTexture.create_from_image(img)
	return _fire_tex


## The fire sites: [position, size, phase] - fixed by the station's id.
func _fire_sites(r: float, spin: float) -> Array:
	var worse := 1.0 - health() / Galaxy.DAMAGED   # 0 at the threshold, 1 at ruin
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(station_id)
	var out := []
	for i in 3 + int(worse * 4.0):
		var p := Vector2.from_angle(rng.randf() * TAU + spin) * r * rng.randf_range(0.15, 0.85)
		var phase := rng.randf() * 10.0
		out.append([p, r * rng.randf_range(0.16, 0.24) * (0.85 + worse * 0.5), phase])
	return out


## On the station: scorches, smoke and the flames themselves (normal blending).
func _draw_fire(r: float, spin: float) -> void:
	var tex := fire_texture()
	if _fire_layer == null:
		_fire_layer = Node2D.new()
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_fire_layer.material = m
		_fire_layer.draw.connect(_draw_flames.bind(_fire_layer))
		add_child(_fire_layer)
	_fire_layer.set_meta("rs", [r, spin])
	_fire_layer.queue_redraw()
	for site in _fire_sites(r, spin):
		var p: Vector2 = site[0]
		var big: float = site[1]
		var phase: float = site[2]
		# Charred hull round the fire.
		draw_texture_rect_region(tex, Rect2(p - Vector2(big, big * 0.8) * 1.9, Vector2(big, big * 0.8) * 3.8), FIRE_SOFT,
			Color(0.05, 0.03, 0.02, 0.85))
		# Smoke: puffs rising, swelling, drifting with a slow wind, grey-brown
		# and dark near the fire, paler and thinner as they spread.
		for k in 8:
			var u := fposmod(_time * 0.22 + phase + k / 8.0, 1.0)
			var drift := Vector2(sin(phase * 3.0 + u * 4.0 + _time * 0.3) * big * 0.5 + u * u * big * 1.8, -big * (0.8 + u * 6.5))
			var sr := big * (1.0 + u * 3.0)
			var shade := lerpf(0.04, 0.25, u)
			var alpha := 0.85 * sin(sqrt(u) * PI) * (1.0 - u * 0.3)
			draw_texture_rect_region(tex, Rect2(p + drift - Vector2.ONE * sr, Vector2.ONE * sr * 2.0), FIRE_SOFT,
				Color(shade, shade * 0.9, shade * 0.85, alpha))
		# Flames, opaque enough to hide the hull: an outer body of red-orange
		# tongues, then an inner one of yellow; each tongue rises from the
		# base, stretching, swaying and cooling darker as it fades.
		for layer_i in 2:
			var inner := layer_i == 1
			var sz := 0.62 if inner else 1.0
			var count := 7 if inner else 10
			for k in count:
				var u := fposmod(_time * (1.5 if inner else 1.15) + phase + float(k) / count + 0.13 * sin(phase * 5.0 + k), 1.0)
				var sway := sin(_time * 4.5 + phase + k * 1.7) * big * (0.08 + u * 0.3) * sz
				var off := sin(phase * 3.1 + k * 2.39) * big * (0.25 if inner else 0.55) * sz
				var w := big * (1.6 - u * 0.8) * sz * (0.75 + 0.5 * absf(sin(k * 1.9 + phase)))
				var h := big * (1.7 + u * 2.0) * sz * (0.8 + 0.4 * absf(cos(k * 2.7 + phase)))
				var at := p + Vector2(off + sway, -big * u * 1.3 * sz)
				var col: Color
				if inner:
					col = Color(1.0, 0.95, 0.6).lerp(Color(1.0, 0.62, 0.12), u)
				else:
					col = Color(1.0, 0.5, 0.08).lerp(Color(0.55, 0.07, 0.02), u)
				col.a = (0.9 if inner else 0.8) * (1.0 - u * u)
				draw_texture_rect_region(tex, Rect2(at - Vector2(w * 0.5, h * 0.88), Vector2(w, h)), FIRE_TONGUE, col)


## On the additive layer: the light of the fires (glow, heart, embers).
func _draw_flames(layer: Node2D) -> void:
	if health() >= Galaxy.DAMAGED or not layer.has_meta("rs"):
		return
	var rs: Array = layer.get_meta("rs")
	var tex := fire_texture()
	for site in _fire_sites(rs[0], rs[1]):
		var p: Vector2 = site[0]
		var big: float = site[1]
		var phase: float = site[2]
		var flick := 0.85 + 0.15 * sin(_time * 11.0 + phase) * sin(_time * 7.3 + phase * 2.0)
		# Heat glow lighting the hull round it.
		var g := big * 2.6 * flick
		layer.draw_texture_rect_region(tex, Rect2(p - Vector2(g, g * 0.9), Vector2(g, g * 0.9) * 2.0), FIRE_SOFT, Color(0.6, 0.2, 0.03, 0.45))
		# The white-hot heart.
		var c := big * 0.55 * flick
		layer.draw_texture_rect_region(tex, Rect2(p - Vector2(c, c * 1.7), Vector2(c * 2.0, c * 2.0)), FIRE_TONGUE, Color(0.9, 0.7, 0.35, 0.7))
		# Embers: sparks thrown up, flickering out.
		for k in 4:
			var u := fposmod(_time * 0.7 + phase * 1.3 + k / 4.0, 1.0)
			var e := p + Vector2(sin(phase * 7.0 + k * 2.3) * big * (0.4 + u * 1.5), -big * (0.6 + u * 4.0))
			var es := big * 0.09 * (1.0 - u * 0.6)
			layer.draw_texture_rect_region(tex, Rect2(e - Vector2.ONE * es, Vector2.ONE * es * 2.0), FIRE_SOFT,
				Color(1.0, 0.6, 0.2, (1.0 - u) * (0.5 + 0.5 * sin(_time * 23.0 + k + phase))))


func _nav_lights(r: float, spin: float, n: int, col: Color) -> void:
	for i in n:
		var a := spin + i * TAU / n + TAU / (n * 2.0)
		var on := fmod(_time * 1.5 + float(i) / n, 1.0) < 0.2
		var p := Vector2.from_angle(a) * (r + 15.0)
		var d := ExhaustTrail.disc()
		if on:
			draw_texture_rect(d, Rect2(p - Vector2(9, 9), Vector2(18, 18)), false, Color(col, 0.35))
			draw_texture_rect(d, Rect2(p - Vector2(4, 4), Vector2(8, 8)), false, Color(1, 1, 1))
		else:
			draw_texture_rect(d, Rect2(p - Vector2(3, 3), Vector2(6, 6)), false, Color(col, 0.6))
