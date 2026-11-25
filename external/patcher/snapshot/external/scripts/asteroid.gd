class_name Asteroid
extends Node2D
## A mineable asteroid. Shooting it chips off ore (every DAMAGE_PER_ORE damage
## spawns one ore pickup); it shrinks as it's mined and shatters when its ore
## runs out. Drawn by AsteroidGen (shaders/asteroid.gdshader): a ray-marched,
## slowly tumbling 3D rock - one of the templates, mixed per seed - with its
## ore type's colours and glowing veins. The lock-on outline is drawn by the
## shader too; the brackets and label here.

signal depleted(asteroid: Node2D)

const DAMAGE_PER_ORE := 18.0
## Rocks hold this many times the ore of their size (mining a rock out takes
## a long time; depleted rocks are gone for good - see Galaxy.rocks).
const ORE_SCALE := 100
const LIGHT_DIR := Vector2(-0.6, -0.5)


## The procedural rock (AsteroidGen) for an ore type and seed, its long
## half-axis `radius` px. Used in space and by the encyclopedia.
static func make_rock(kind_id: String, radius: float, seed_: int, themed := true) -> ColorRect:
	return AsteroidGen.make(AsteroidGen.for_rock(kind_id, seed_, themed), radius)

## Mineral kinds: ore item, rock colour, vein colour, spawn weight.
const KINDS := {
	"iron": {"name": "Iron Asteroid", "ore": "iron_ore", "rock": Color(0.46, 0.4, 0.35),
		"vein": Color(0.85, 0.48, 0.3), "glow": false, "weight": 60},
	"titanium": {"name": "Titanium Asteroid", "ore": "titanium_ore", "rock": Color(0.38, 0.42, 0.48),
		"vein": Color(0.4, 0.88, 1.0), "glow": true, "weight": 30},
	"platinum": {"name": "Platinum Asteroid", "ore": "platinum_ore", "rock": Color(0.3, 0.28, 0.31),
		"vein": Color(1.0, 0.84, 0.4), "glow": true, "weight": 10},
	# Only in the planetary rings (their local spaces), never the open fields.
	"ice": {"name": "Ice Asteroid", "ore": "ice", "rock": Color(0.72, 0.82, 0.9),
		"vein": Color(0.6, 0.9, 1.0), "glow": true, "weight": 0},
}

var kind := "iron"
var base_radius := 60.0
var ore_total := 8
var ore_left := 8
var shape_seed := 0
var spin := 0.1
var velocity := Vector2.ZERO  # asteroids don't move (used for aim leading)
var display_name: String:
	get:
		return KINDS[kind]["name"]
var hit_radius := 60.0
var click_radius := 70.0
var targeted := false:
	set(v):
		targeted = v
		queue_redraw()
		if _sprite:
			(_sprite.material as ShaderMaterial).set_shader_parameter("outline", 1.0 if v else 0.0)
## What it's made of and where its ore lies (Mining.generate): `comp`
## {mineral: share}, `veins` [{a, d, mineral, units, max, heat, res...}] -
## shown (and cut) once scanned. Generated from its seed; the veins' units saved.
var comp := {}
var veins: Array = []
## Scanned by your ship (ShipScanner): highlighted with its kind and ore left.
var scanned := false:
	set(v):
		scanned = v
		queue_redraw()
var _sprite: ColorRect   # the procedural rock
var _baked: Sprite2D     # ...or, for the rings' ice (dozens on screen at once), a baked picture of one
var _last_debris := -100000
const DEBRIS_EVERY := 150


# --- Baked ice (the rings) ----------------------------------------------------------------------
# A ring's local space shows dozens of ice rocks at once; drawn by the rock
# shader each would cost the GPU too much (186 FPS). So a few ice rocks are
# rendered once into pictures (ICE_VARIANTS, off screen - SubViewports) and
# the rings' rocks draw those, turning slowly: a rock made before the
# pictures are ready switches over as soon as they are.
const ICE_VARIANTS := 8
const ICE_BAKE_RADIUS := 80.0
static var _ice_tex: Array = []
static var _ice_baking := false


static func bake_ice(host: Node) -> void:
	if _ice_baking or not _ice_tex.is_empty() or host == null or not host.is_inside_tree():
		return
	_ice_baking = true
	# One variant at a time, a few frames each (all eight at once: ~80 ms in
	# one frame); the rocks keep their shader until the pictures are there.
	var tree := host.get_tree()
	var out := []
	for i in ICE_VARIANTS:
		var rock := make_rock("ice", ICE_BAKE_RADIUS, 7919 * (i + 1), false)
		var mat := rock.material as ShaderMaterial
		mat.set_shader_parameter("spin", 0.0)
		mat.set_shader_parameter("light", LIGHT_DIR)
		var vp := SubViewport.new()
		vp.size = Vector2i(ceili(rock.size.x), ceili(rock.size.y))
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		rock.position = Vector2.ZERO
		vp.add_child(rock)
		tree.root.add_child(vp)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		vp.queue_free()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			out.append(ImageTexture.create_from_image(img))
	_ice_tex = out   # (empty when there's no renderer - headless: the shader rocks stay)
	_ice_baking = false


## A ring's rock: its baked picture in place of the shader, once there is one.
func _use_baked_ice() -> void:
	if kind != "ice" or _ice_tex.is_empty() or _baked != null:
		return
	_baked = Sprite2D.new()
	_baked.texture = _ice_tex[absi(shape_seed) % _ice_tex.size()]
	_baked.scale = Vector2.ONE * (base_radius * 1.2) / ICE_BAKE_RADIUS
	_baked.rotation = -rotation   # (lit from the same side as every rock)
	_baked.show_behind_parent = true
	add_child(_baked)
	if _sprite:
		_sprite.queue_free()
		_sprite = null
var _alive := true
var _damage_acc := 0.0
var _flash := 0.0
var _time := 0.0


## Random asteroid: kind by weight, ore by size.
static func random_data(at: Vector2) -> Dictionary:
	var total := 0
	for k in KINDS:
		total += KINDS[k]["weight"]
	var pick := randi() % total
	var kind_id := "iron"
	for k in KINDS:
		pick -= KINDS[k]["weight"]
		if pick < 0:
			kind_id = k
			break
	var r := randf_range(38.0, 105.0)
	var ore := int(round(r / 7.5))
	if kind_id == "platinum":
		ore = maxi(2, ore / 2)
	ore *= ORE_SCALE
	return {"kind": kind_id, "position": [at.x, at.y], "radius": r, "ore_total": ore,
		"ore_left": ore, "seed": randi(), "spin": randf_range(-0.25, 0.25)}


func setup(data: Dictionary) -> Asteroid:
	kind = data.get("kind", "iron")
	var p: Array = data.get("position", [0, 0])
	position = Vector2(p[0], p[1])
	base_radius = data.get("radius", 60.0)
	ore_total = int(data.get("ore_total", 8))
	ore_left = int(data.get("ore_left", ore_total))
	scanned = bool(data.get("scanned", false))
	if ore_total < ORE_SCALE:   # (older saves and layouts: rocks from before ORE_SCALE)
		ore_total *= ORE_SCALE
		ore_left *= ORE_SCALE
	shape_seed = int(data.get("seed", 0))
	spin = data.get("spin", 0.1)
	rotation = data.get("rotation", randf() * TAU)
	var g := Mining.generate(kind, base_radius, ore_total, shape_seed)
	comp = g["comp"]
	veins = g["veins"]
	var left = data.get("veins")
	if left is Array:
		for i in mini(veins.size(), left.size()):
			veins[i]["units"] = clampi(int(left[i]), 0, int(veins[i]["max"]))
	return self


func _ready() -> void:
	add_to_group("asteroids")
	z_index = -2
	# The rock (it turns in its shader), behind the brackets drawn in _draw().
	if kind == "ice":
		bake_ice(self)
		_use_baked_ice()
	if _baked == null:
		_sprite = make_rock(kind, base_radius * 1.2, shape_seed)
		var mat := _sprite.material as ShaderMaterial
		mat.set_shader_parameter("spin", spin)
		mat.set_shader_parameter("light", LIGHT_DIR.rotated(-rotation))   # (the node keeps its angle)
		# (Drawn into a picture ten times a second - ShaderCache - not every
		# frame: a field's ray-marched rocks close up were 2 ms of GPU a frame;
		# they turn slowly.)
		var cache := ShaderCache.wrap(_sprite, 10.0, 384.0)
		cache.show_behind_parent = true
		add_child(cache)
	_update_size()
	# Only process while on screen.
	var enabler := VisibleOnScreenEnabler2D.new()
	enabler.rect = Rect2(-Vector2.ONE * base_radius * 1.4, Vector2.ONE * base_radius * 2.8)
	add_child(enabler)


func is_alive() -> bool:
	return _alive


func is_neutral() -> bool:
	return false


func faction_group() -> StringName:
	return &"asteroids"




func take_damage(amount: float, from: Vector2, _attacker: Node2D = null, _dtype := "") -> void:
	if not _alive:
		return
	_flash = 1.0
	Effects.debris(from, KINDS[kind]["rock"].lightened(0.3), 0.5)
	_damage_acc += amount
	# Chip off one chunk of ore per DAMAGE_PER_ORE damage.
	while _damage_acc >= DAMAGE_PER_ORE and ore_left > 0:
		_damage_acc -= DAMAGE_PER_ORE
		ore_left -= 1
		Pickup.spawn(get_tree(), from, KINDS[kind]["ore"], 1)
	_update_size()
	if ore_left <= 0:
		_shatter()


## Mining beam (player or NPC miners): continuous, so no hit flash - a little
## dust where it cuts, ore chipped off as it goes. The player's ore floats to
## them as pickups; an NPC miner's goes straight into its hold.
func mine(amount: float, at: Vector2, by: Node = null) -> void:
	if not _alive:
		return
	# Chips flying off - a burst every DEBRIS_EVERY ms at most (it was a 35%
	# chance a frame: at 300 FPS with five miners at work, hundreds of
	# particle bursts alive at once).
	var now := Time.get_ticks_msec()
	if now - _last_debris >= DEBRIS_EVERY:
		_last_debris = now
		Effects.debris(at, KINDS[kind]["rock"].lightened(0.3), 0.25)
	_damage_acc += amount
	var chipped := false
	while _damage_acc >= DAMAGE_PER_ORE and ore_left > 0:
		_damage_acc -= DAMAGE_PER_ORE
		ore_left -= 1
		chipped = true
		var ore: String = KINDS[kind]["ore"]
		if by != null and not by.is_in_group("player") and by.get("cargo") is Dictionary:
			by.cargo[ore] = int(by.cargo.get(ore, 0)) + 1
		else:
			Pickup.spawn(get_tree(), at, ore, 1).tractor = by != null
	if chipped:
		_update_size()
	if ore_left <= 0:
		_shatter()


# --- Cutting by hand (the player's mining laser: Mining) --------------------------------------

## Where vein `i` lies (global).
func vein_pos(i: int) -> Vector2:
	var v: Dictionary = veins[i]
	return global_position + Vector2.from_angle(float(v["a"]) + rotation) * hit_radius * float(v["d"])


## The vein nearest `at` with ore left (-1: none).
func vein_near(at: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in veins.size():
		if int(veins[i]["units"]) <= 0:
			continue
		var d := vein_pos(i).distance_to(at)
		if d < bd:
			bd = d
			best = i
	return best


## Every vein cools with time (fire or not) - while any is warm (_hot): by
## the clock (settle()), so a rock off screen (not processing) cools all the same.
var _hot := false
var _cool_at := 0

func settle() -> void:
	var now := Time.get_ticks_msec()
	if _hot and _cool_at > 0:
		cool((now - _cool_at) / 1000.0)
	_cool_at = now


func cool(delta: float) -> void:
	_hot = false
	for v in veins:
		if float(v["heat"]) > 0.0:
			v["heat"] = maxf(0.0, float(v["heat"]) - Mining.COOL * delta)
			_hot = true


## The laser on vein `i` for `delta` s (`speed`, `yield_k`: the mining upgrades;
## `by`: the ship - fragments float to it). Returns what happened: "" / "cut" / "fracture" / "empty".
func cut_vein(i: int, delta: float, speed: float, yield_k: float, by: Node2D) -> String:
	if not _alive or i < 0 or i >= veins.size():
		return ""
	var v: Dictionary = veins[i]
	if int(v["units"]) <= 0:
		return "empty"
	settle()
	var hard: float = float(Mining.MINERALS.get(v["mineral"], {"hard": 1.0})["hard"])
	v["heat"] = float(v["heat"]) + Mining.HEAT * hard * delta   # (the cooling: settle())
	_hot = true
	var heat := float(v["heat"])
	var at := vein_pos(i)
	if heat >= 1.0:
		# Fractured: a share of what's left breaks off as rubble; the heat drops.
		var lost := maxi(1, int(int(v["units"]) * Mining.FRACTURE_LOSS))
		v["units"] = int(v["units"]) - lost
		ore_left = maxi(0, ore_left - lost)
		v["heat"] = 0.45
		v["res"] = 1.0
		for k in mini(3, lost):
			Pickup.spawn(get_tree(), at + Vector2.from_angle(randf() * TAU) * 20.0, Mining.frag_id("rubble"), 1).tractor = by != null
		Effects.debris(at, KINDS[kind]["rock"].lightened(0.3), 0.8)
		Sfx.play_world("space/rock_break", at, -4.0)
		_update_size()
		_check_empty()
		return "fracture"
	if Mining.in_band(heat):
		v["res"] = minf(Mining.RESONANCE_MAX, float(v["res"]) + Mining.RESONANCE_RATE * delta)
	else:
		v["res"] = 1.0
	var rate := Mining.cut_rate(heat) * Mining.RATE * float(v["res"]) * speed
	v["acc"] = float(v["acc"]) + rate * delta
	var out := ""
	while float(v["acc"]) >= 1.0 and int(v["units"]) > 0:
		v["acc"] = float(v["acc"]) - 1.0
		v["units"] = int(v["units"]) - 1
		ore_left = maxi(0, ore_left - 1)
		var n := 2 if randf() < yield_k else 1   # (the ore yield upgrade: now and then two)
		Pickup.spawn(get_tree(), at, Mining.frag_id(v["mineral"]), n).tractor = by != null
		out = "cut"
	var now := Time.get_ticks_msec()
	if rate > 0.0 and now - _last_debris >= DEBRIS_EVERY:
		_last_debris = now
		Effects.debris(at, Mining.mineral_color(v["mineral"]), 0.25)
	if out == "cut":
		_update_size()
	_check_empty()
	return out


## Hacking at the bulk of an unscanned rock: rubble, slowly.
func cut_bulk(delta: float, by: Node2D) -> void:
	if not _alive:
		return
	_damage_acc += Mining.RATE * 0.35 * delta
	var at := global_position + Vector2.from_angle(randf() * TAU) * hit_radius * 0.5
	while _damage_acc >= 1.0 and ore_left > 0:
		_damage_acc -= 1.0
		ore_left -= 1
		Pickup.spawn(get_tree(), at, Mining.frag_id("rubble"), 1).tractor = by != null
	var now := Time.get_ticks_msec()
	if now - _last_debris >= DEBRIS_EVERY:
		_last_debris = now
		Effects.debris(at, KINDS[kind]["rock"].lightened(0.3), 0.25)
	_update_size()
	if ore_left <= 0:
		_shatter()


func _check_empty() -> void:
	if ore_left <= 0 or veins.all(func(v): return int(v["units"]) <= 0):
		if ore_left > 0 and not scanned:
			return
		if veins.all(func(v): return int(v["units"]) <= 0):
			_shatter()


func _shatter() -> void:
	Sfx.play_world("space/rock_break", global_position)
	_alive = false
	GameLog.post("%s mined out - gone for good" % display_name, "loot")
	Effects.debris(global_position, KINDS[kind]["rock"].lightened(0.2), base_radius / 30.0)
	Effects.explosion(global_position, 0.6)
	depleted.emit(self)
	queue_free()


## Shrinks with the ore that's left.
func _update_size() -> void:
	var frac := float(ore_left) / maxf(1.0, ore_total)
	scale = Vector2.ONE * (0.45 + 0.55 * frac)
	hit_radius = base_radius * scale.x * 0.9
	click_radius = maxf(hit_radius + 15.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if kind == "ice":
		if _baked == null:
			_use_baked_ice()
		else:
			_baked.rotation += spin * 0.3 * delta
	if _flash > 0.0:
		_flash = move_toward(_flash, 0.0, delta * 4.0)
		var pic: CanvasItem = _baked if _baked else _sprite
		if pic:
			pic.modulate = Color.WHITE.lerp(Color(1.8, 1.8, 1.8), _flash * 0.6)
	if _hot:
		settle()
	if (targeted or scanned) and UI.redraw_due(self, 30.0):
		queue_redraw()


func _draw() -> void:
	var k: Dictionary = KINDS[kind]
	var vein: Color = k["vein"]
	# Lock-on brackets (drawn counter-rotated so they stay upright).
	if targeted:
		if scanned:
			draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE / scale)
			_draw_veins()
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE / scale)
		var s := hit_radius * 1.25 + 3.0 * sin(_time * 8.0)
		var c := Color(0.85, 0.9, 1.0, 0.9)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = corner * s
			draw_line(p, p - Vector2(corner.x * 12, 0), c, 2.0)
			draw_line(p, p - Vector2(0, corner.y * 12), c, 2.0)
		var font := ThemeDB.fallback_font
		var label := "%s  ·  %d ore left" % [k["name"].to_upper(), ore_left]
		draw_string(font, Vector2(-150, s + 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, 300, Settings.fs("world", 13), vein.lightened(0.3))
		draw_set_transform(Vector2.ZERO)
	elif scanned:
		# Scanned: a glowing ring in the ore's colour (the console style: soft
		# glow, bright core, light nodes turning round it) and what it holds.
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE / scale)
		var rr := hit_radius * 1.3
		var pulse := 0.6 + 0.4 * sin(_time * 3.0)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(vein, 0.12 * pulse), 12.0, true)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(vein.lightened(0.4), 0.75 * pulse), 2.0, true)
		for i in 6:
			var np := Vector2.from_angle(i * TAU / 6.0 + _time * 0.4) * rr
			draw_circle(np, 6.0, Color(vein, 0.25 * pulse))
			draw_circle(np, 2.6, Color(vein.lightened(0.6), pulse))
		_draw_veins()
		var font := NeonTheme.heavy_font()
		var fs := Settings.fs("world", 16)
		var label := "%s  ·  %d units in %d vein%s" % [k["name"].to_upper(), veins.reduce(func(a, v): return a + int(v["units"]), 0),
			veins.filter(func(v): return int(v["units"]) > 0).size(), "" if veins.filter(func(v): return int(v["units"]) > 0).size() == 1 else "s"]
		draw_string_outline(font, Vector2(-170, rr + 22.0), label, HORIZONTAL_ALIGNMENT_CENTER, 340, fs, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(-170, rr + 22.0), label, HORIZONTAL_ALIGNMENT_CENTER, 340, fs, vein.lightened(0.35))
		draw_set_transform(Vector2.ZERO)


## The veins (scanned): glowing seams in their mineral's colour, brighter the
## hotter; the picked one ringed (`picked_vein`); empty ones dark scars.
var picked_vein := -1

func _draw_veins() -> void:
	for i in veins.size():
		var v: Dictionary = veins[i]
		var p := Vector2.from_angle(float(v["a"]) + rotation) * hit_radius * float(v["d"])
		var d := Vector2.from_angle(float(v["a"]) + rotation + PI * 0.5) * hit_radius * float(v["len"])
		var col := Mining.mineral_color(v["mineral"])
		if int(v["units"]) <= 0:
			draw_line(p - d, p + d, Color(0.08, 0.06, 0.05, 0.8), 4.0, true)
			continue
		var heat := float(v["heat"])
		var hot := Color(1.0, 0.55, 0.2).lerp(Color(1.0, 0.95, 0.8), clampf((heat - 0.6) / 0.4, 0.0, 1.0))
		var c := col.lerp(hot, clampf(heat, 0.0, 1.0) * 0.8)
		var pulse := 0.7 + 0.3 * sin(_time * 3.0 + i)
		draw_line(p - d, p + d, Color(c, 0.25 * pulse), 10.0, true)
		draw_line(p - d, p + d, Color(c.lightened(0.3), 0.9), 2.5, true)
		draw_line(p - d * 0.4 + d.orthogonal() * 0.15, p + d * 0.3 - d.orthogonal() * 0.1, Color(c, 0.6), 1.5, true)
		if i == picked_vein:
			draw_arc(p, 14.0 + 2.0 * sin(_time * 6.0), 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0, true)


func get_save_data() -> Dictionary:
	return {"kind": kind, "position": [position.x, position.y], "radius": base_radius,
		"ore_total": ore_total, "ore_left": ore_left, "scanned": scanned, "seed": shape_seed, "spin": spin, "rotation": rotation,
		"veins": veins.map(func(v): return int(v["units"]))}
