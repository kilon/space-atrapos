class_name Wreck
extends Node2D
## What a destroyed ship or station leaves behind: its own sprite, greyed out,
## scorched and torn open (shaders/wreck.gdshader), drifting and turning
## slowly. With a Salvage Rig fitted (Items.EQUIPMENT "salvage_rig") you can
## salvage it: click it - the ship flies up and cuts it apart (main.gd:
## _update_salvage, SALVAGE_TIME) - for scrap, spare parts for the Repair Bay (always some), now and then a piece
## of gear, and the Electro emitter of a ship that had one (salvage()).
## Wrecks aren't saved; they drift away after LIFE seconds (a station's
## stays longer), MAX of them in a system at once.

const MAX := 14
const LIFE_SHIP := 300.0
const LIFE_STATION := 900.0
const FADE := 4.0
## Close enough to cut it (from its edge).
const SALVAGE_REACH := 320.0
const SALVAGE_TIME_SHIP := 4.0
const SALVAGE_TIME_STATION := 10.0
## A ship with an Electro gives it up this often.
const ELECTRO_SALVAGE := 0.6
## A ship's chance to give up one of its weapons (Hardpoints) when salvaged.
const WEAPON_SALVAGE := 0.35

static var _shader: Shader

var kind := "ship"            # "ship" / "station"
var title := ""               # what it was ("Spartan Hoplite-class Gunship", "Kastor Phalanx")
var empire := ""
var toughness := 100.0        # its hull (and shields): the bigger, the more salvage
var electro := false
var weapons: Array = []       # the ship's loadout (Hardpoints item ids)
var radius := 60.0            # roughly (for clicking it, and the salvage reach)
var progress := 0.0           # salvaging: seconds of cutting done
var salvaged := false
var _life := 0.0
var _spin := 0.0
var _drift := Vector2.ZERO
var _sprite: Sprite2D
var _mat: ShaderMaterial


## Leaves a wreck at `at` (global) under `host` (the space scene): `tex` drawn
## at `scl`, turned `rot`. `info`: kind, title, empire, toughness, electro.
## Null without a texture.
static func spawn(host: Node, at: Vector2, tex: Texture2D, scl: Vector2, rot: float, info: Dictionary) -> Wreck:
	if tex == null or host == null or not host.is_inside_tree():
		return null
	var all := host.get_tree().get_nodes_in_group("wrecks")
	if all.size() >= MAX:
		all[0].queue_free()   # (the oldest drifts off)
	var w := Wreck.new()
	w.kind = str(info.get("kind", "ship"))
	w.title = str(info.get("title", "ship"))
	w.empire = str(info.get("empire", ""))
	w.toughness = float(info.get("toughness", 100.0))
	w.electro = bool(info.get("electro", false))
	w.weapons = Array(info.get("weapons", []))
	w.radius = maxf(tex.get_width() * absf(scl.x), tex.get_height() * absf(scl.y)) * 0.42
	w._sprite = Sprite2D.new()
	w._sprite.texture = tex
	w._sprite.scale = scl
	w.rotation = rot
	host.add_child(w)
	w.global_position = at
	return w


## A wreck's material drawn once under `host` (Effects.warm), with a tiny picture.
static func warm(host: Node2D) -> void:
	if _shader == null:
		_shader = load("res://shaders/wreck.gdshader")
	var s := Sprite2D.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	s.texture = ImageTexture.create_from_image(img)
	var m := ShaderMaterial.new()
	m.shader = _shader
	s.material = m
	host.add_child(s)


func _ready() -> void:
	add_to_group("wrecks")
	z_index = -2
	if _shader == null:
		_shader = load("res://shaders/wreck.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_mat.set_shader_parameter("burn", randf_range(0.35, 0.8) if kind == "ship" else randf_range(0.5, 0.9))
	if _sprite:
		_sprite.material = _mat
		add_child(_sprite)
	_spin = randf_range(-0.12, 0.12) if kind == "ship" else randf_range(-0.02, 0.02)
	_drift = Vector2.from_angle(randf() * TAU) * (randf_range(6.0, 18.0) if kind == "ship" else 2.0)


func life() -> float:
	return LIFE_STATION if kind == "station" else LIFE_SHIP


func salvage_time() -> float:
	return SALVAGE_TIME_STATION if kind == "station" else SALVAGE_TIME_SHIP


func _process(delta: float) -> void:
	_life += delta
	rotation += _spin * delta
	position += _drift * delta
	var left := life() - _life
	if left < FADE:
		_mat.set_shader_parameter("fade", clampf(left / FADE, 0.0, 1.0))
		if left <= 0.0:
			queue_free()


## Cut apart: what it gives drifts out (Pickup - tractor it in); the wreck
## falls to pieces. Returns what it was, for the log.
func salvage(data: Node) -> String:
	if salvaged:
		return ""
	salvaged = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var level := clampf(toughness / 900.0, 0.0, 1.0)
	var drops := []
	var gear_rolls := 0
	if kind == "station":
		drops = [["scrap", rng.randi_range(14, 24)], ["machinery", rng.randi_range(2, 5)], ["electronics", rng.randi_range(1, 4)],
			["alien_alloy", rng.randi_range(0, 2)], ["fuel", rng.randi_range(2, 6)]]
		drops += spare_drops(rng, rng.randi_range(4, 7))
		gear_rolls = 2
		level = 0.7
	else:
		drops = [["scrap", 2 + int(level * 6.0) + rng.randi_range(0, 2)]]
		if rng.randf() < 0.35:
			drops.append(["electronics", rng.randi_range(1, 2)])
		if rng.randf() < 0.25:
			drops.append(["machinery", 1])
		if rng.randf() < 0.3:
			drops.append(["fuel", rng.randi_range(1, 3)])
		# Components that survived: spare parts for the Repair Bay - always some,
		# more from a bigger ship.
		drops += spare_drops(rng, 1 + int(level * 2.0) + (1 if rng.randf() < 0.5 else 0))
		gear_rolls = 1 if rng.randf() < 0.25 + level * 0.3 else 0
	for d in drops:
		if int(d[1]) > 0:
			Pickup.spawn(get_tree(), global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, radius), d[0], int(d[1]))
	for i in gear_rolls:
		Pickup.spawn(get_tree(), global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, radius), Gear.roll(rng, "", level), 1)
	var said := ""
	var spares := 0
	for d in drops:
		if str(d[0]).begins_with("spare_"):
			spares += int(d[1])
	if spares > 0:
		said = "%d spare part%s" % [spares, "" if spares == 1 else "s"]
	if not weapons.is_empty() and rng.randf() < WEAPON_SALVAGE:
		var wid: String = str(weapons[rng.randi() % weapons.size()])
		Pickup.spawn(get_tree(), global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, radius), wid, 1)
		said = Hardpoints.title(wid) if said == "" else said + ", " + Hardpoints.title(wid)
	if electro and rng.randf() < ELECTRO_SALVAGE and data:
		var e := _salvage_electro(data)
		said = e if said == "" else said + ", " + e
	# It comes apart: a few bursts, then it fades fast.
	for i in 3:
		Effects.explosion(global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, radius * 0.6), 0.6, "space/rock_break")
	_life = maxf(_life, life() - 1.5)
	return said


## n spare parts of random kinds (Parts.SPARE_OF), as [[item, count]...].
static func spare_drops(rng: RandomNumberGenerator, n: int) -> Array:
	var got := {}
	var kinds := Parts.SPARE_OF.values()
	for i in n:
		var k: String = kinds[rng.randi() % kinds.size()]
		got[k] = int(got.get(k, 0)) + 1
	var out := []
	for k in got:
		out.append([k, got[k]])
	return out


## A ship's Electro emitter (an Electro S), salvaged: fitted to a free
## hardpoint that takes it; else it's yours all the same - in your hold, to
## sell, swap in or keep. Sold for parts only when the hold has no room.
func _salvage_electro(data: Node) -> String:
	var wid := Hardpoints.item_id("electro", Hardpoints.BASE)
	if Hardpoints.free_slot_for(data, wid) >= 0:
		Hardpoints.fit(data, wid, -1, false)
		return "an Electro emitter - fitted to a free hardpoint (on your toolbar)"
	if Inventory.room_for(data.items, wid, Shipyard.cargo_capacity(data)) >= 1:
		Inventory.add(data.items, wid, 1, Shipyard.cargo_capacity(data))
		data.changed.emit()
		return "an Electro emitter - into your hold"
	var worth := roundi(Hardpoints.price(wid) * 0.4)
	data.add_credits(worth)
	return "an Electro emitter - your hold is full: sold for parts, %d dr" % worth
