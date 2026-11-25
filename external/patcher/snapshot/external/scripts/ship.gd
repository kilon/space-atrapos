extends Node2D
## Player ship: flies toward the point set with move_to(), attacks the enemy
## set with set_attack_target() (flying into weapon range first if needed),
## has shields (regenerate) and hull, switchable weapons and active systems.

signal arrived
## Passed a waypoint: `target` is now the next point of the course.
signal waypoint_passed
signal health_changed(hull: float, max_hull: float, shields: float, max_shields: float)
signal destroyed
signal attacked   # (took damage from someone - Main closes the full-window menus)
signal message(text: String)

@export_group("Flight")
@export var max_speed := 420.0
@export var acceleration := 600.0
@export var turn_speed := 4.0          # radians per second
@export var arrive_radius := 6.0
@export var engine_offset := Vector2(0, 40)  # local position of the engine nozzle
@export var boost_multiplier := 1.8    # afterburner speed factor

@export_group("Defense")
@export var max_hull := 100.0
@export var max_shields := 100.0
@export var shield_regen := 12.0       # per second
@export var shield_regen_delay := 3.0  # seconds without damage before regen
@export var hit_radius := 36.0

## Set by the game scene: credits, ammo and installed equipment.
var player_data: Node

var velocity := Vector2.ZERO
var target := Vector2.ZERO
var has_target := false
var thrust := 0.0  # 0..1, used for the engine flame

var hull := max_hull
var shields := max_shields
var attack_target: Node2D = null
## True when the ship should fly into weapon range of attack_target.
var chasing := false

## The fitted weapon kinds' first that's switched on (for the HUD; all of them fire: _update_weapons).
var weapon_id: String:
	get:
		for id in weapons():
			if id != "" and weapon_on(Hardpoints.kind(id)):
				return Hardpoints.kind(id)
		return ""
## How close to get to fight: the shortest reach of the weapons switched on
## (they all reach from there).
var weapon_range: float:
	get:
		if is_instance_valid(attack_target) and attack_target is Asteroid:   # (a target can be freed under us)
			return MINING_RANGE * (1.0 + _mod("range_mult"))
		var r := INF
		for id in weapons():
			if id != "" and weapon_on(Hardpoints.kind(id)):
				r = minf(r, float(Hardpoints.stats(id)["range"]))
		return (r if r < INF else float(Items.WEAPONS["laser"]["range"])) * (1.0 + _mod("range_mult"))

## Asteroids are mined with a continuous beam (MiningBeam), whatever weapon is
## selected: damage per second (tech's damage bonus applies) and its reach.
const MINING_DPS := 45.0
const MINING_RANGE := 560.0
var _beam: MiningBeam

var hull_regen := 0.0   # per second, from tech
## The hull's own slow self-repair (per second, SELF_REPAIR_CALM s after a hit) -
## frozen while a part is damaged (_frozen: Parts.regen_frozen, apply_tech).
const SELF_REPAIR := 0.5
const SELF_REPAIR_CALM := 6.0
var _frozen := false
var _base := {}         # exported stats before tech modifiers

var cooldowns := {}     # system id -> seconds left
var boost_time := 0.0   # afterburner seconds left

var _alive := true
var _since_hit := 99.0
var _fire_cd := 0.0   # (stun: everything held)
var _slot_cd := PackedFloat32Array()   # each hardpoint's cooldown
var _sound_at := {}   # style -> when its shot sounded last (24 guns: not 24 sounds at once)
## Shield visual (child node, rotates with the ship).
const SHIELD_SIZE := Vector2(150, 196)
var _shield_fx: ShieldEffect
var _ammo_warned := false

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("player")
	_use_procedural_sprite()
	hull = max_hull
	shields = max_shields
	_create_shield_fx()
	ExhaustTrail.attach(self, "blue", 116.0)   # (a blue exhaust trail, like the reference's lead jet)
	_attach_sparks()
	_base = {"hull": max_hull, "shields": max_shields, "regen": shield_regen,
			"delay": shield_regen_delay, "speed": max_speed, "accel": acceleration, "turn": turn_speed}


var _sparks: FaultSparks

## Electrical faults crackling off the ship the worse its hull (FaultSparks).
func _attach_sparks() -> void:
	if _sparks == null:
		_sparks = FaultSparks.attach(self, maxf(40.0, hit_radius * 1.2), func(): return 1.0 - hull / maxf(1.0, max_hull) if _alive else 0.0)


func _create_shield_fx() -> void:
	var size := ShieldEffect.sphere_for(sprite.texture.get_size() * sprite.scale) if sprite.texture else Vector2.ONE * SHIELD_SIZE.length()
	_shield_fx = ShieldEffect.new().setup(size, Color(0.3, 0.75, 1.0), Color(0.75, 0.95, 1.0))
	add_child(_shield_fx)



## Swap in the procedural ship picture (same on-screen length, ~116 px).
func _use_procedural_sprite() -> void:
	var art: Node = get_node_or_null("/root/ProcArt")
	if art == null:
		return
	var cls: String = player_data.ship_class if player_data else "player"
	# (a placeholder of its size while its picture is still loading: ProcArt.sprite)
	var tex: Texture2D = art.sprite("ship_player") if cls == "player" else EnemyTypes.texture(cls)
	# Ship Designer paint job (a shader on the sprite).
	sprite.material = ShipParts.material(player_data.ship_look) if player_data else null
	if tex:
		var length: float = Shipyard.stats(cls)["length"]
		sprite.texture = tex
		sprite.scale = Vector2.ONE * (length / tex.get_height())
		hit_radius = 36.0 * length / 116.0
		if _shield_fx:   # (a sphere round the whole ship)
			_shield_fx.resize(ShieldEffect.sphere_for(tex.get_size() * sprite.scale))


func _mod(key: String) -> float:
	return player_data.mod(key) if player_data else 0.0


## The share of damage of type `dtype` your ship shrugs off (fitted gear and tech).
func resistance(dtype: String) -> float:
	return clampf(_mod("resist_" + dtype), 0.0, Gear.RESIST_CAP)


## Recomputes stats from the base values plus unlocked tech.
func apply_tech() -> void:
	var old_hull_max := max_hull
	var old_shield_max := max_shields
	# The ship class sets the base stats (shipyard); tech and modules add on.
	if player_data:
		var cls := Shipyard.stats(player_data.ship_class)
		_base["hull"] = cls["hull"]
		_base["shields"] = cls["shields"]
		_base["speed"] = cls["speed"]
		_use_procedural_sprite()
	max_hull = _base["hull"] + _mod("max_hull")
	max_shields = (_base["shields"] + _mod("max_shields")) * maxf(0.1, 1.0 + _mod("max_shields_mult"))   # (a damaged emitter: less)
	# A bigger maximum also fills the new capacity.
	hull = minf(max_hull, hull + maxf(0.0, max_hull - old_hull_max))
	shields = minf(max_shields, shields + maxf(0.0, max_shields - old_shield_max))
	shield_regen = _base["regen"] * (1.0 + _mod("shield_regen_mult"))
	shield_regen_delay = maxf(0.5, _base["delay"] + _mod("regen_delay"))
	max_speed = _base["speed"] * (1.0 + _mod("speed_mult"))
	acceleration = _base["accel"] * (1.0 + _mod("handling_mult"))
	turn_speed = _base["turn"] * (1.0 + _mod("handling_mult"))
	hull_regen = _mod("hull_regen")
	_frozen = player_data != null and Parts.regen_frozen(player_data.condition, "ship")
	_fuel_leak = _mod("fuel_leak")
	_jitter = _mod("jitter")
	_misfire = _mod("misfire")
	_scatter = _mod("scatter")
	_emit_health()


## The weapons on the hardpoints (Hardpoints: an item id or "" each).
func weapons() -> Array:
	return Hardpoints.fitted(player_data) if player_data else Hardpoints.START


## Is weapon kind `k` switched on (the toolbar)?
func weapon_on(k: String) -> bool:
	return not (player_data and player_data.weapons_off.has(k))


## A weapon's stat ("damage", "interval", "range", "speed") with tech -
## `id`: a weapon item (Hardpoints), "" the first fitted one.
func weapon_stat(key: String, id := "") -> float:
	if id == "":
		for w in weapons():
			if w != "":
				id = w
				break
	var v: float = Hardpoints.stats(id)[key]
	match key:
		"damage":
			v *= 1.0 + _mod("damage_mult")
		"interval":
			v *= maxf(0.2, 1.0 + _mod("fire_rate_mult"))
		"range":
			v *= 1.0 + _mod("range_mult")
	return v


## A system's cooldown with tech applied.
func system_cooldown(id: String) -> float:
	var cd: float = Items.SYSTEMS[id]["cooldown"]
	if id == "afterburner":
		cd *= maxf(0.2, 1.0 + _mod("afterburner_cd_mult"))
	return cd


func is_alive() -> bool:
	return _alive


## Manual move order (cancels chasing an enemy, or following a ship, and any
## waypoints after it).
func move_to(point: Vector2) -> void:
	chasing = false
	follow_target = null
	target = point
	has_target = true
	waypoints.clear()


## The course's further points (Shift + click on the sector map): flown in
## order after `target`, passing through each without stopping (within
## WAYPOINT_PASS); the ship stops only at the last.
var waypoints: Array[Vector2] = []
const WAYPOINT_PASS := 180.0


## Adds a point to the end of the course (no course: flies there).
func add_waypoint(point: Vector2) -> void:
	if not has_target or chasing or follow_target != null:
		move_to(point)
	else:
		waypoints.append(point)


## The whole course still ahead: the target, then the waypoints (empty: none).
func course() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if has_target:
		out.append(target)
		out.append_array(waypoints)
	return out


## Moves point `i` of the course (0: the target, then the waypoints).
func set_course_point(i: int, p: Vector2) -> void:
	if i == 0 and has_target:
		target = p
	elif i >= 1 and i - 1 < waypoints.size():
		waypoints[i - 1] = p


## Stop moving (the ship glides to a halt).
func stop() -> void:
	chasing = false
	follow_target = null
	has_target = false
	waypoints.clear()


## A ship you're following (a neutral you clicked once): you keep FOLLOW_DIST
## behind it without firing. Clicking it again attacks (main.gd).
var follow_target: Node2D
const FOLLOW_DIST := 260.0

func follow(other: Node2D) -> void:
	set_attack_target(null)
	follow_target = other
	_follow_dir = Vector2.ZERO
	_update_chase()


func set_attack_target(enemy: Node2D, chase := false) -> void:
	if chase and enemy != null:
		waypoints.clear()   # (off to fight: the course is dropped)
	if enemy != null:
		follow_target = null
	if _target_valid():
		attack_target.targeted = false
	attack_target = enemy
	chasing = chase and enemy != null
	if enemy:
		enemy.targeted = true


# --- Weapons & systems ---------------------------------------------------------

## A weapon kind's toolbar key: switches every weapon of that kind on or off
## (all the fitted ones fire together; hold the missiles for later...).
func select_weapon(id: String) -> void:
	if player_data == null:
		return
	if not player_data.has_equipment(id):
		message.emit("No %s fitted - buy one at a station's outfitter" % Items.EQUIPMENT[id]["name"])
		return
	if player_data.weapons_off.has(id):
		player_data.weapons_off.erase(id)
	else:
		player_data.weapons_off[id] = true
	var on := weapon_on(id)
	Sfx.play("space/select")
	_ammo_warned = false
	var n := weapons().filter(func(w): return w != "" and Hardpoints.kind(w) == id).size()
	message.emit("%s %s (%d fitted)" % [Items.WEAPONS[id]["name"], "on" if on else "off - holding fire", n])
	player_data.changed.emit()


# --- Stun, fuel, the Star Energizer -------------------------------------------------------

var _stun_t := 0.0
## Caught in an enemy Bouncer Plasma's web (PlasmaBouncer.PlasmaWeb): slowed,
## tied to the enemy ships in it.
var web: Node2D = null

## Struck by an Electro: the drive and guns stutter for `t` s (less your
## electric resistance).
func stun(t: float) -> void:
	var k := 1.0 - resistance("electric")
	if t * k > _stun_t:
		if _stun_t <= 0.0:
			message.emit("Stunned by lightning!")
		_stun_t = t * k


# --- The cloak ---------------------------------------------------------------------------
# A Cloak (equipment, a toolbar system): switched on, the ship is half seen
# through and no enemy can see it (Enemy._valid_target) - until it fires a
# weapon (or you switch it off). While cloaked the shields are down; when the
# cloak ends they come back to where they were over CLOAK_SHIELD_BACK s.

const CLOAK_SHIELD_BACK := 2.0
const CLOAK_ALPHA := 1.0   # (the cloak shader shows what's behind the hull: no fading needed)
const CLOAK_SWEEP := 0.6   # s for the ripple to sweep over the hull, on and off
static var _cloak_shader: Shader
var _paint_mat: Material   # the ship's paint (ShipParts), put back when the cloak is off
var _cloak_tween: Tween
const CLOAK_COOLDOWN := 4.0
var cloaked := false
var _cloak_shields := 0.0
var _shield_back_t := 0.0


func cloak() -> void:
	if cloaked:
		return
	cloaked = true
	_cloak_shields = shields if _shield_back_t <= 0.0 else maxf(shields, _cloak_shields)
	_shield_back_t = 0.0
	shields = 0.0
	_shield_fx.visible = false
	_cloak_fx(true)
	# Anything hunting you loses you.
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("neutrals"):
		if e.get("_target") == self:
			e._target = null
	Sfx.play_world("space/scan_pulse", global_position, -4.0, 0.2)
	GameLog.post("Cloaked: no enemy can see you - until you fire. Your shields are down.", "good")
	message.emit("Cloaked")
	_emit_health()


## The cloak's look (shaders/cloak.gdshader): the hull a shimmering lens on
## what's behind it, a ripple sweeping over it as it comes on (or goes off);
## the paint back once it's gone.
func _cloak_fx(on: bool) -> void:
	if _cloak_shader == null:
		_cloak_shader = load("res://shaders/cloak.gdshader")
	var m: ShaderMaterial
	if sprite.material is ShaderMaterial and (sprite.material as ShaderMaterial).shader == _cloak_shader:
		m = sprite.material
	else:
		_paint_mat = sprite.material
		m = ShaderMaterial.new()
		m.shader = _cloak_shader
		m.set_shader_parameter("amount", 0.0)
		sprite.material = m
	if _cloak_tween:
		_cloak_tween.kill()
	_cloak_tween = create_tween()
	var from: float = float(m.get_shader_parameter("amount"))
	_cloak_tween.tween_method(func(v: float): m.set_shader_parameter("amount", v), from, 1.0 if on else 0.0, CLOAK_SWEEP)
	if not on:
		_cloak_tween.tween_callback(func():
			if not cloaked:
				sprite.material = _paint_mat)


## The cloak ends (`why`: you fired, switched it off): shields come back.
func decloak(why := "") -> void:
	if not cloaked:
		return
	cloaked = false
	_shield_back_t = CLOAK_SHIELD_BACK
	_shield_fx.visible = true
	_cloak_fx(false)
	cooldowns["cloak"] = CLOAK_COOLDOWN
	Sfx.play_world("space/shield_boost", global_position, -4.0)
	message.emit("Cloak off%s - shields coming back" % ((": " + why) if why != "" else ""))
	GameLog.post("Cloak off%s. Shields back in %d seconds." % [(" (" + why + ")") if why != "" else "", CLOAK_SHIELD_BACK], "info")


## An empty tank leaves this much of your speed (emergency thrusters).
const FUEL_EMPTY_SPEED := 0.35
## The Star Energizer: fuel a second, within this much of the star's edge.
const ENERGIZE_RATE := 6.0
const ENERGIZE_REACH := 1800.0

var energizing := false
var _energizer_beam: Node2D
var _fuel_warned := false


## Flying burns a trickle of fuel; the energizer, switched on near the star,
## fills the tank.
func _update_fuel(delta: float) -> void:
	if player_data == null:
		return
	if velocity.length() > 40.0:
		player_data.drain_fuel(Shipyard.FUEL_FLIGHT * delta * (2.0 if boost_time > 0.0 else 1.0) * maxf(0.3, 1.0 - _mod("fuel_efficiency")))
	if _fuel_leak > 0.0:   # (damaged fuel lines: Parts)
		player_data.drain_fuel(_fuel_leak * 0.1 * delta)
	var empty: bool = player_data.fuel_level() <= 0.0
	if empty and not _fuel_warned:
		_fuel_warned = true
		message.emit("Out of fuel: emergency thrusters only - refuel at a station")
		GameLog.post("Out of fuel. Emergency thrusters only; you can't jump. Refuel at a station, pump in fuel from your hold, or drain a star with a Star Energizer.", "danger")
	elif not empty:
		_fuel_warned = false
	_update_energizer(delta)


## How far from the system's centre the energizer reaches (0: no star here -
## a local space has none).
func energizer_reach() -> float:
	var main := get_parent()   # (the space scene)
	if main == null or main.get("site") != null:
		return 0.0
	var sys: Dictionary = Galaxy.system(Galaxy.current_system)
	var star: Dictionary = Galaxy.STARS.get(str(sys.get("star", "yellow")), {})
	return float(star.get("radius", 420.0)) + ENERGIZE_REACH


func _update_energizer(delta: float) -> void:
	if not energizing:
		if _energizer_beam:
			_energizer_beam.queue_free()
			_energizer_beam = null
		return
	var reach := energizer_reach()
	if reach <= 0.0 or global_position.length() > reach:
		energizing = false
		message.emit("Star Energizer off: too far from the star")
		return
	if player_data.fuel_level() >= player_data.fuel_max() - 0.01:
		energizing = false
		message.emit("Tank full - Star Energizer off")
		GameLog.post("Star Energizer: the tank is full.", "good")
		return
	player_data.fuel = minf(player_data.fuel_max(), player_data.fuel_level() + ENERGIZE_RATE * (1.0 + _mod("energize_mult")) * delta)
	if _energizer_beam == null:
		_energizer_beam = EnergizerBeam.new()
		_energizer_beam.ship = self
		get_parent().add_child(_energizer_beam)


## The beam: the star's light drawn in a twisting stream to the ship.
class EnergizerBeam extends Node2D:
	var ship: Node2D
	var _t := 0.0

	func _ready() -> void:
		z_index = -1

	func _process(delta: float) -> void:
		_t += delta
		if not is_instance_valid(ship):
			queue_free()
			return
		if UI.redraw_due(self):
			queue_redraw()

	func _draw() -> void:
		var to: Vector2 = ship.global_position
		var from := to.normalized() * minf(to.length(), 450.0)   # (the star's edge, roughly)
		var n := 18
		var side := (to - from).orthogonal().normalized()
		for strand in 3:
			var pts := PackedVector2Array()
			for k in n + 1:
				var u := float(k) / n
				pts.append(from.lerp(to, u) + side * sin(u * 9.0 - _t * 6.0 + strand * 2.1) * 26.0 * sin(u * PI))
			draw_polyline(pts, Color(1.0, 0.75, 0.3, 0.25), 10.0)
			draw_polyline(pts, Color(1.0, 0.92, 0.6, 0.8), 2.0)
		draw_circle(to, 38.0 + sin(_t * 8.0) * 4.0, Color(1.0, 0.8, 0.35, 0.22))


func use_system(id: String) -> void:
	var sys: Dictionary = Items.SYSTEMS[id]
	if not _alive or cooldown_left(id) > 0.0:
		return
	if sys.has("equipment") and not player_data.has_equipment(sys["equipment"]):
		message.emit("%s not installed - buy one at a station" % sys["name"])
		return

	match id:
		"projection_array":
			ProjectionArray.project(self)
		"cloak":
			if cloaked:
				decloak()
			else:
				cloak()
			return   # (its cooldown starts when it ends)
		"star_energizer":
			energizing = not energizing
			if energizing:
				var reach := energizer_reach()
				if reach <= 0.0:
					energizing = false
					message.emit("No star here to drain")
					return
				if global_position.length() > reach:
					energizing = false
					message.emit("Too far from the star - fly within %d of its surface" % ENERGIZE_REACH)
					return
				GameLog.post("Star Energizer on: draining the star's power into your tank.", "good")
				Sfx.play_world("space/scan_pulse", global_position)
			else:
				message.emit("Star Energizer off")
		"afterburner":
			if player_data and not player_data.use_fuel(2.0):
				message.emit("Not enough fuel for the afterburner")
				return
			boost_time = sys["duration"]
			Sfx.play_world("space/afterburner", global_position)
			GameLog.post("Afterburner engaged", "good")
		"shield_booster":
			if shields >= max_shields:
				message.emit("Shields already full")
				return
			shields = minf(max_shields, shields + sys["amount"])
			_shield_fx.flash()
			Sfx.play_world("space/shield_boost", global_position)
			GameLog.post("Shield Booster: +%d shields" % sys["amount"], "good")
			_emit_health()
		"repair_kit":
			if player_data.count("repair_kit") <= 0:
				message.emit("No repair kits - buy some at a station")
				return
			if hull >= max_hull:
				message.emit("Hull already intact")
				return
			player_data.remove_item("repair_kit")
			hull = minf(max_hull, hull + sys["amount"])
			Sfx.play_world("space/repair", global_position)
			GameLog.post("Repair kit used: +%d hull" % sys["amount"], "good")
			Effects.float_text(global_position + Vector2(0, -70), "+%d hull" % sys["amount"], Color(0.5, 1.0, 0.6))
			_emit_health()
	cooldowns[id] = system_cooldown(id)


func cooldown_left(id: String) -> float:
	return cooldowns.get(id, 0.0)


# --- Damage --------------------------------------------------------------------

## Can't be hurt (the title screen's attract mode).
var invulnerable := false

## `dtype`: the damage's type (Gear.DAMAGE_TYPES) - your resistance to it
## (gear and tech: "resist_<type>") takes its share off.
func take_damage(amount: float, from: Vector2, attacker: Node2D = null, dtype := "kinetic") -> void:
	if not _alive or invulnerable:
		return
	amount *= 1.0 - resistance(dtype)
	if is_instance_valid(attacker) and attacker.get("damage_mult") != null:
		amount *= float(attacker.damage_mult)   # (a signal's level)
	_since_hit = 0.0
	var had_shields := shields > 0.0
	var sp := Gear.split(dtype, shields, amount)   # (a beam: shields x2, hull x0.35)
	var absorbed := sp.x
	shields -= absorbed
	amount = sp.y
	var who: String = attacker.display_name if attacker and "display_name" in attacker else "Stray fire"
	GameLog.damage_taken(who, absorbed, amount)
	if had_shields and shields <= 0.0:
		GameLog.post("Shields down!", "danger")
		Sfx.play("space/shields_down")
	if absorbed > 0.0:
		_shield_fx.hit(from)
		Sfx.play_world("space/hit_shield", from, -2.0)
	if amount > 0.0:
		amount *= maxf(0.1, 1.0 + _mod("hull_taken_mult"))   # (damaged plating lets more through)
		hull = maxf(hull - amount, 0.0)
		_part_hit(amount, from, dtype)
		Sfx.play_world("space/hit_hull", from)
		sprite.modulate = Color(2.5, 0.6, 0.6, CLOAK_ALPHA if cloaked else 1.0)
		create_tween().tween_property(sprite, "modulate", Color(1, 1, 1, CLOAK_ALPHA if cloaked else 1.0), 0.25)
	_emit_health()
	if is_instance_valid(attacker):
		attacked.emit()
	if hull <= 0.0:
		_die()


## Damage from a hazard you're inside (a signal site's anomaly field): drains
## the shields first, then the hull - steadily, every frame, so without the
## hit sounds and flashes of a weapon; a crackle at most twice a second.
var _hazard_sound := 0
func hazard_damage(amount: float, at: Vector2) -> void:
	if not _alive or amount <= 0.0 or invulnerable:
		return
	amount *= 1.0 - resistance("energy")   # (the anomalies: raw energy)
	_since_hit = 0.0
	var had_shields := shields > 0.0
	var absorbed := minf(shields, amount)
	shields -= absorbed
	hull = maxf(hull - (amount - absorbed), 0.0)
	if had_shields and shields <= 0.0:
		GameLog.post("Shields down!", "danger")
		Sfx.play("space/shields_down")
	if Time.get_ticks_msec() - _hazard_sound > 500:
		_hazard_sound = Time.get_ticks_msec()
		Sfx.play_world("space/hazard_zap", at, -4.0)
		if absorbed > 0.0:
			_shield_fx.hit(at)
	_emit_health()
	if hull <= 0.0:
		_die()


var _fuel_leak := 0.0   # fuel a second lost to damaged fuel lines (x 0.1; apply_tech)
# Damaged parts acting up (Affliction; apply_tech): the thrusters jerking it
# off course, the fire control losing the target, the sensors scattering shots.
var _jitter := 0.0
var _misfire := 0.0
var _scatter := 0.0
var _afflict := Affliction.new_state()
var _wild := 0   # Affliction.misfire: 0 on target, else firing wild

## A hit through to the hull may leave a fault in a part (Parts) - the side
## it came from decides which: the engines from behind, the sensors ahead.
func _part_hit(amount: float, from: Vector2, dtype: String) -> void:
	if player_data == null or hull <= 0.0:
		return
	var local := (from - global_position).rotated(-rotation) if from != Vector2.ZERO else Vector2.ZERO
	var f := Parts.hit(player_data.condition, "ship", amount, max_hull, dtype, local)
	if not f.is_empty():
		GameLog.post(Parts.hit_text("ship", f), "danger")
	# (the worse the hull, the more is damaged: Parts.by_health)
	var more := Parts.by_health(player_data.condition, "ship", hull / maxf(1.0, max_hull), dtype)
	for m in more:
		GameLog.post(Parts.hit_text("ship", m), "danger")
	if not f.is_empty() or not more.is_empty():
		apply_tech()


func repair(amount: float) -> void:
	hull = minf(max_hull, hull + amount)
	_emit_health()


func recharge_shields() -> void:
	shields = max_shields
	_emit_health()


func _die() -> void:
	_alive = false
	if _beam:
		_beam.off()
	set_attack_target(null)
	GameLog.post("Your ship was destroyed!", "danger")
	_engine_off()
	Effects.explosion(global_position, 2.0, "space/ship_boom_player")
	hide()
	destroyed.emit()


func _emit_health() -> void:
	health_changed.emit(hull, max_hull, shields, max_shields)


func _target_valid() -> bool:
	return attack_target != null and is_instance_valid(attack_target) and attack_target.is_alive()


# --- Saving ----------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y],
		"rotation": rotation,
		"velocity": [velocity.x, velocity.y],
		"target": [target.x, target.y],
		"has_target": has_target,
		"waypoints": waypoints.map(func(w): return [w.x, w.y]),
		"hull": hull,
		"shields": shields,
	}


func load_save_data(data: Dictionary) -> void:
	global_position = _vec(data.get("position"), global_position)
	rotation = data.get("rotation", rotation)
	velocity = _vec(data.get("velocity"), Vector2.ZERO)
	target = _vec(data.get("target"), global_position)
	has_target = data.get("has_target", false)
	waypoints.clear()
	for w in data.get("waypoints", []):
		waypoints.append(_vec(w, global_position))
	hull = data.get("hull", max_hull)
	shields = data.get("shields", max_shields)
	_emit_health()


static func _vec(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(value[0], value[1])
	return fallback


# --- Update ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _alive:
		return

	_update_defense(delta)
	_update_systems(delta)
	_update_chase()
	_update_weapons(delta)

	var boosting := boost_time > 0.0
	var speed_cap := max_speed * (boost_multiplier if boosting else 1.0)
	if _stun_t > 0.0:   # (struck by an Electro: the drive stutters)
		_stun_t -= delta
		speed_cap *= 0.15
	_update_fuel(delta)
	if player_data and player_data.fuel_level() <= 0.0:
		speed_cap *= FUEL_EMPTY_SPEED   # (empty tank: emergency thrusters only)
	if _slow_t > 0.0:   # (Skylla's ink: slowed while in it)
		_slow_t -= delta
		speed_cap *= _slow_k
	var accel := acceleration * (1.6 if boosting else 1.0)
	var desired_velocity := Vector2.ZERO

	if follow_target != null:
		# Following: match its velocity, eased toward a slot FOLLOW_DIST behind
		# it - one continuous motion at its speed, no stopping and starting.
		desired_velocity = _follow_velocity(speed_cap)
		var face := desired_velocity if desired_velocity.length() > 30.0 else follow_target.global_position - global_position
		rotation = rotate_toward(rotation, face.angle() + PI / 2.0, turn_speed * delta)
	elif has_target:
		var to_target := target - global_position
		var dist := to_target.length()

		if not chasing and not waypoints.is_empty() and dist < maxf(arrive_radius, WAYPOINT_PASS):
			target = waypoints.pop_front()   # (on through the waypoint to the next)
			waypoint_passed.emit()
		elif dist < arrive_radius and velocity.length() < 40.0:
			has_target = false
			arrived.emit()
		else:
			# The sprite points up, so add PI/2 to the direction angle.
			var desired_angle := to_target.angle() + PI / 2.0
			rotation = rotate_toward(rotation, desired_angle, turn_speed * delta)

			# Only push forward when roughly facing the target.
			var facing := Vector2.UP.rotated(rotation)
			var alignment := maxf(0.0, facing.dot(to_target.normalized()))

			# Slow down smoothly as we approach: v = sqrt(2 * a * d).
			var speed := minf(speed_cap, sqrt(2.0 * accel * dist))
			desired_velocity = to_target.normalized() * speed * alignment
	elif _target_valid():
		# Idle: turn to face the enemy we're attacking.
		var to_enemy := attack_target.global_position - global_position
		rotation = rotate_toward(rotation, to_enemy.angle() + PI / 2.0, turn_speed * delta)

	velocity = velocity.move_toward(desired_velocity, accel * delta)
	if _jitter > 0.01:   # (damaged thrusters: kicked off course, the nose wobbling)
		velocity += Affliction.jitter_push(_afflict, _jitter, delta, max_speed) * delta * 1.5
		rotation += Affliction.jitter_turn(_afflict, _jitter) * delta
	if web != null:   # (caught in an enemy's plasma web: slowed, tied to their ships)
		if is_instance_valid(web):
			velocity = web.constrain(self, velocity)
		else:
			web = null
	global_position += velocity * delta

	var target_thrust := clampf(desired_velocity.length() / max_speed, 0.0, 1.0)
	thrust = move_toward(thrust, target_thrust, 4.0 * delta)
	_engine_sound(boosting)
	queue_redraw()


# --- Sounds (Sfx: sounds/space/, made by tools/sfx_space.py) -------------------

var _engine: AudioStreamPlayer2D     # the engine's hum: always on, louder and higher with thrust
var _mining: AudioStreamPlayer2D

func _engine_sound(boosting: bool) -> void:
	if _engine == null:
		_engine = Sfx.loop_at("space/engine_loop", self, -40.0)
		if _engine == null:
			return
	var k := clampf(thrust, 0.0, 1.0)
	_engine.volume_db = lerpf(-22.0, -4.0, k) + (3.0 if boosting else 0.0)
	_engine.pitch_scale = lerpf(0.75, 1.15, k) * (1.2 if boosting else 1.0)


func _engine_off() -> void:
	if _engine:
		_engine.queue_free()
		_engine = null
	_mining_sound(false)


func _mining_sound(on: bool) -> void:
	if on and _mining == null:
		_mining = Sfx.loop_at("space/mining_loop", self, -4.0)
	elif not on and _mining:
		_mining.queue_free()
		_mining = null


## Slowed to `factor` of top speed for `seconds` (Skylla's ink cloud keeps
## renewing it while you're inside).
var _slow_t := 0.0
var _slow_k := 1.0

func slow(seconds: float, factor: float) -> void:
	if invulnerable:
		return
	_slow_t = maxf(_slow_t, seconds)
	_slow_k = factor


func slowed() -> bool:
	return _slow_t > 0.0


## The Minotaur's pulse: shields dead for `seconds`, then back as they were.
var _drain := 0.0
var _drain_saved := 0.0

func drain_shields(seconds: float) -> void:
	if not _alive or invulnerable:
		return
	if _drain <= 0.0:
		_drain_saved = shields
	_drain = seconds
	shields = 0.0
	message.emit("Shields drained!")
	_emit_health()


func shields_drained() -> bool:
	return _drain > 0.0


func _update_defense(delta: float) -> void:
	if cloaked:
		shields = 0.0   # (down while cloaked)
		return
	if _shield_back_t > 0.0:   # (after the cloak: back to where they were in CLOAK_SHIELD_BACK s)
		_shield_back_t -= delta
		var k := 1.0 - maxf(0.0, _shield_back_t) / CLOAK_SHIELD_BACK
		shields = maxf(shields, minf(max_shields, _cloak_shields * k))
		_emit_health()
		return
	if _drain > 0.0:
		_drain -= delta
		shields = 0.0
		if _drain <= 0.0:
			shields = minf(max_shields, _drain_saved)
			message.emit("Shields restored")
			_emit_health()
		return
	_since_hit += delta
	if _since_hit > shield_regen_delay and shields < max_shields:
		var got := _regen_fuel(minf(max_shields - shields, shield_regen * delta), Shipyard.FUEL_PER_SHIELD)
		if got > 0.0:
			shields = minf(max_shields, shields + got)
			_emit_health()
	# The hull mends itself slowly out of a fight (SELF_REPAIR, and Nanite
	# Repair's) - not while anything in the ship is damaged (Parts.regen_frozen).
	var mend := hull_regen + (SELF_REPAIR if _since_hit > SELF_REPAIR_CALM else 0.0)
	if mend > 0.0 and hull < max_hull and not _frozen:
		var got := _regen_fuel(minf(max_hull - hull, mend * delta), Shipyard.FUEL_PER_HULL)
		if got > 0.0:
			hull = minf(max_hull, hull + got)
			_emit_health()


var _regen_starved := false

## Shields recharging and the hull mending burn fuel (`per` a point): how many of
## `points` the tank pays for now (all, what's left, or none - out of fuel, with
## a warning once till there's fuel again).
func _regen_fuel(points: float, per: float) -> float:
	if player_data == null or points <= 0.0:
		return points
	var f: float = player_data.fuel_level()
	if f <= 0.0:
		if not _regen_starved:
			_regen_starved = true
			message.emit("Out of fuel: shields and hull can't recharge")
			GameLog.post("Out of fuel: your shields and hull don't recharge without it. Refuel at a station, pump fuel from your hold, or drain a star with a Star Energizer.", "danger")
		return 0.0
	_regen_starved = false
	var cost := minf(points * per, f)
	player_data.drain_fuel(cost)
	return cost / per


func _update_systems(delta: float) -> void:
	boost_time = maxf(0.0, boost_time - delta)
	for id in cooldowns.keys():
		cooldowns[id] = maxf(0.0, cooldowns[id] - delta)


## Following a ship: hold a slot FOLLOW_DIST from it, on a bearing that
## swings round behind it only while it's really travelling (and then only
## gradually) - so a ship that hovers or drifts back and forth doesn't drag
## you from side to side. Your velocity: its own (when it travels) plus an
## easing toward the slot; near the slot, just hold station.
const FOLLOW_TRAVEL := 70.0         # its speed above this: it's going somewhere
const FOLLOW_TURN := 0.9            # how fast the slot swings round behind it (rad / s)
const FOLLOW_SLACK := 40.0          # this close to the slot: no correction
var _follow_dir := Vector2.ZERO     # from it to your slot (unit)

func _follow_velocity(cap: float) -> Vector2:
	var other := follow_target
	var v: Vector2 = other.get("velocity") if other.get("velocity") is Vector2 else Vector2.ZERO
	var dt := get_process_delta_time()
	if _follow_dir == Vector2.ZERO:
		_follow_dir = (global_position - other.global_position).normalized()
		if _follow_dir == Vector2.ZERO:
			_follow_dir = Vector2.DOWN
	var travelling := v.length() > FOLLOW_TRAVEL
	if travelling:   # swing round behind it, gradually
		var want_dir := -v.normalized()
		var ang := _follow_dir.angle_to(want_dir)
		_follow_dir = _follow_dir.rotated(clampf(ang, -FOLLOW_TURN * dt, FOLLOW_TURN * dt))
	var slot: Vector2 = other.global_position + _follow_dir * FOLLOW_DIST
	var off := slot - global_position
	var catch_up := Vector2.ZERO
	if off.length() > FOLLOW_SLACK:
		catch_up = off.normalized() * minf((off.length() - FOLLOW_SLACK) * 1.2, cap)
	# Match its motion only while it travels (a hovering ship's jitter isn't followed).
	var want := (v if travelling else Vector2.ZERO) + catch_up
	return want.limit_length(cap)


## When attacking an enemy that's out of range, fly to a point inside range.
func _update_chase() -> void:
	if follow_target != null:
		if not is_instance_valid(follow_target) or not follow_target.is_inside_tree() or \
				(follow_target.has_method("is_alive") and not follow_target.is_alive()):
			follow_target = null
		else:
			has_target = false   # (following steers by velocity: _follow_velocity)
		return
	if not chasing:
		return
	if not _target_valid():
		chasing = false
		return
	var to_enemy := attack_target.global_position - global_position
	if to_enemy.length() > weapon_range * 0.9:
		target = attack_target.global_position - to_enemy.normalized() * weapon_range * 0.7
		has_target = true


func _update_weapons(delta: float) -> void:
	_fire_cd -= delta
	# (Damaged fire control: now and then off the target, firing wild - timed every frame.)
	_wild = Affliction.misfire(_afflict, _misfire if attack_target != null else 0.0, delta)
	if _wild == 1:
		message.emit("Fire control lost the target - shots going wild")
	if attack_target != null and not _target_valid():
		attack_target = null  # target destroyed
		chasing = false
	if is_instance_valid(attack_target) and attack_target is Asteroid:
		_update_mining(delta)
		return
	_mining_sound(false)
	# Every weapon fitted fires on its own cooldown, from its own hardpoint
	# (Hardpoints.mount); the beams together as one (their damage summed).
	var ws := weapons()
	if _slot_cd.size() != ws.size():
		_slot_cd.resize(ws.size())
	var dist := global_position.distance_to(attack_target.global_position) if attack_target != null else INF
	var ready := attack_target != null and _stun_t <= 0.0 and _fire_cd <= 0.0
	var beam_dps := 0.0
	var beam_id := ""
	for i in ws.size():
		var id: String = ws[i]
		if id == "":
			continue
		_slot_cd[i] -= delta
		var k := Hardpoints.kind(id)
		if not ready or not weapon_on(k):
			continue
		if Items.WEAPONS[k]["style"] == "beam":
			if dist <= weapon_stat("range", id):
				beam_dps += weapon_stat("damage", id)
				beam_id = id
			continue
		if _slot_cd[i] > 0.0 or dist > weapon_stat("range", id):
			continue
		if _fire_one(i, id, dist):
			_slot_cd[i] = weapon_stat("interval", id)
		else:
			_slot_cd[i] = 0.5   # (out of ammo: look again in a while)
	_update_beam(delta, beam_dps, beam_id)


## Hardpoint `i`'s weapon `id` fires at the target (`dist` away). False if it
## couldn't (no ammo).
func _fire_one(i: int, id: String, dist: float) -> bool:
	var w := Hardpoints.stats(id)
	var ammo: String = w["ammo"]
	if ammo != "" and player_data and player_data.count(ammo) <= 0:
		if not _ammo_warned:
			_ammo_warned = true
			message.emit("Out of %ss - buy more at a station" % Items.display_name(ammo).to_lower())
		return false
	if ammo != "" and player_data:
		player_data.remove_item(ammo)
	decloak("you fired")
	var wild := _wild
	var cr := Upgrades.crit(weapon_stat("damage", id), _mod("crit_chance"), _mod("crit_mult"))   # (a weak spot now and then)
	var dmg: float = cr[0]
	if w["style"] in ["electro", "bouncer"] and (wild != 0 or not Accuracy.roll(accuracy(), global_position, attack_target, weapon_stat("range", id))):
		_sound("spark", global_position, -6.0)   # (off target, or a miss: it fizzles)
		if wild == 0:
			Effects.float_text(attack_target.global_position + Vector2(0, -40), "MISS", Color(0.8, 0.85, 0.95))
		return true
	if w["style"] == "electro":   # (lightning: strikes at once, leaps on - ChainLightning)
		ChainLightning.strike(get_tree(), self, attack_target, dmg, w)
		return true
	if w["style"] == "bouncer":   # (a ball of plasma that bounces on and webs them - PlasmaBouncer)
		PlasmaBouncer.fire(get_tree(), self, attack_target, dmg, w)
		return true
	var speed: float = w["speed"]
	# Lead the target so moving enemies can be hit.
	var aim: Vector2 = attack_target.global_position + attack_target.velocity * (dist / speed)
	var gun: Vector2 = global_transform * mount(i)
	var dir := Affliction.scattered(gun.direction_to(aim), _scatter)
	# (a miss: aimed past it, it flies on by - Accuracy)
	var hit := wild == 0 and Accuracy.roll(accuracy(), gun, attack_target, weapon_stat("range", id))
	if wild != 0:
		dir = Affliction.wild_dir(Vector2.UP.rotated(rotation))
	elif not hit:
		dir = Accuracy.miss_dir(gun, aim, float(attack_target.get("hit_radius")) if attack_target.get("hit_radius") != null else 30.0)
	var p := Projectile.fire(get_tree(), gun, dir, speed, dmg, attack_target.faction_group(),
			w["color"], w["style"], self)
	if not hit:
		p.ignore = attack_target
	_sound({"laser": "laser", "plasma": "plasma", "missile": "missile"}.get(w["style"], "laser"), gun)
	if w["style"] == "missile" and hit:
		p.homing_target = attack_target
	return true


## The chance to hit a still target close by (Accuracy): the ship's own, its
## upgrades' and tech's ("accuracy"), less damaged sensors'.
func accuracy() -> float:
	return clampf(Accuracy.BASE_SHIP + _mod("accuracy"), 0.2, 0.99)


## How hard the ship is to hit (Accuracy: upgrades' "evasion").
var evasion: float:
	get:
		return clampf(_mod("evasion"), 0.0, 0.6)


## Where hardpoint `i` is on the hull (local: the nose up).
func mount(i: int) -> Vector2:
	var half := Vector2(20.0, 50.0)
	if sprite and sprite.texture:
		half = sprite.texture.get_size() * sprite.scale * Vector2(0.32, 0.42)
	return Hardpoints.mount(i, weapons().size(), half)


## A shot's sound - one of a style every 60 ms at most (a broadside of 24 guns is one sound, not 24).
func _sound(name: String, at: Vector2, db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_sound_at.get(name, -1000)) < 60:
		return
	_sound_at[name] = now
	Sfx.play_world("space/" + name, at, db)


## The Beam Emitters: one continuous beam from the nose while the target is in
## reach - their damage a second together (`dps`), of type "beam" (shields
## drained twice as fast, a third on the hull: Gear.SHIELD_HULL), dealt ten
## times a second; wider the more of them.
var _beam_acc := 0.0
var _beam_tick := 0.0
var _beam_miss := 0.0          # s the beam's off the target (a missed tick)
var _beam_off := Vector2.ZERO

func _update_beam(delta: float, dps: float, id: String) -> void:
	var on := false
	if dps > 0.0 and attack_target != null:
		var dist := global_position.distance_to(attack_target.global_position)
		on = true
		if _beam == null:
			_beam = MiningBeam.new()
			add_child(_beam)
		_beam.color = Items.WEAPONS["beam"]["color"]
		_beam.width = 1.3 * sqrt(dps / maxf(1.0, weapon_stat("damage", id)))
		var nose: Vector2 = global_transform * Vector2(0, -34.0)
		var r: float = float(attack_target.get("hit_radius")) if attack_target.get("hit_radius") != null else 30.0
		var hit := attack_target.global_position - nose.direction_to(attack_target.global_position) * r * 0.6
		decloak("you fired")
		if _wild != 0:   # (damaged fire control: the beam swings off the target)
			var off := Vector2.UP.rotated(rotation + sin(Time.get_ticks_msec() * 0.003) * Affliction.WILD_ARC)
			_beam.aim(nose, nose + off * dist)
			_beam_acc = 0.0
		elif _beam_miss > 0.0:
			# (a missed moment: the beam slides off past its edge, nothing dealt - Accuracy)
			_beam_miss -= delta
			_beam.aim(nose, attack_target.global_position + _beam_off * r * 1.6)
			_beam_acc = 0.0
		else:
			_beam.aim(nose, hit)
			_beam_acc += dps * delta
			_beam_tick -= delta
			if _beam_tick <= 0.0:
				_beam_tick = 0.1
				if Accuracy.roll(accuracy(), nose, attack_target, weapon_stat("range", id)):
					attack_target.take_damage(_beam_acc, hit, self, "beam")
				else:
					_beam_miss = 0.25
					_beam_off = (attack_target.global_position - nose).orthogonal().normalized() * (1.0 if randf() < 0.5 else -1.0)
				_beam_acc = 0.0
	if not on:
		_beam_acc = 0.0
		if _beam:
			_beam.off()
	if on:
		_mining_sound(true)


var _hold_msg_t := -100000

## Room in the hold for one more piece of ore, counting the ore already on
## its way to you (cut by your beam, being tractored in).
func hold_has_room() -> bool:
	if player_data == null:
		return true
	var coming := 0
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.tractor and p.collectible and p.item_id != "credits":
			coming += p.amount
	var ore: String = attack_target.ore_id() if attack_target and attack_target.has_method("ore_id") else "iron_ore"
	return player_data.room_for(ore) - coming > 0


## Mining: a continuous red beam from the nose to the rock's near side,
## cutting ore off while the rock is in reach and roughly ahead - until the
## cargo hold is full.
## Mining by hand (Mining): the laser fires while you hold the button on the
## rock (`mining_hold`, main.gd); it cuts the vein picked (`mining_vein`: a
## click near one picks it; else the nearest) - keep its heat in the band; an
## unscanned rock gives only rubble. `mining_auto`: an autopilot that pulses the
## laser to keep the heat in the band (the attract mode, tests).
var mining_hold := false
var mining_vein := -1
var mining_auto := false
var mining_last := ""          # what the last cut did ("cut" / "fracture" / "empty" / "bulk")
var mining_at := -1000.0      # when the laser last cut (s, Time): the mining panel shows a while after
var _bulk_said := false

func _update_mining(delta: float) -> void:
	if _beam == null:
		_beam = MiningBeam.new()
		add_child(_beam)
	_beam.color = MiningBeam.RED   # (the Beam Emitter shares it, in blue)
	_beam.width = 1.0
	var rock: Asteroid = attack_target
	var to_rock := rock.global_position - global_position
	var facing := Vector2.UP.rotated(rotation)
	if to_rock.length() > weapon_range or facing.dot(to_rock.normalized()) < 0.85:
		_beam.off()
		_mining_sound(false)
		return
	# A full hold (counting the ore already floating to you): the beam stops.
	if not hold_has_room():
		_beam.off()
		_mining_sound(false)
		if Time.get_ticks_msec() - _hold_msg_t > 4000:
			_hold_msg_t = Time.get_ticks_msec()
			message.emit("Cargo hold full (%d slots) - refine or sell what you carry" % Shipyard.cargo_capacity(player_data))
			GameLog.post("Mining stopped: your cargo hold is full.", "danger")
		return
	if rock.scanned and (mining_vein < 0 or mining_vein >= rock.veins.size() or int(rock.veins[mining_vein]["units"]) <= 0):
		mining_vein = rock.vein_near(global_position)
	rock.picked_vein = mining_vein if rock.scanned else -1
	var firing := mining_hold
	rock.settle()
	if mining_auto and rock.scanned and mining_vein >= 0:
		# (the autopilot: on below the band's middle, off above it)
		var h := float(rock.veins[mining_vein]["heat"])
		firing = h < (Mining.BAND.x + Mining.BAND.y) * 0.5
	elif mining_auto:
		firing = true
	if not firing:
		_beam.off()
		_mining_sound(false)
		return
	mining_at = Time.get_ticks_msec() / 1000.0
	var nose: Vector2 = global_transform * Vector2(0, -34.0)
	var hit: Vector2
	if rock.scanned and mining_vein >= 0:
		hit = rock.vein_pos(mining_vein)
		mining_last = rock.cut_vein(mining_vein, delta, 1.0 + _mod("mining_speed"), _mod("mining_yield"), self)
		if mining_last == "fracture":
			message.emit("The vein fractured - too hot! Let it cool into the green")
			GameLog.post("A vein fractured: part of it lost as rubble.", "danger")
		elif mining_last == "empty":
			mining_vein = -1
	else:
		hit = rock.global_position - nose.direction_to(rock.global_position) * rock.hit_radius * 0.7
		rock.cut_bulk(delta, self)
		mining_last = "bulk"
		if not _bulk_said:
			_bulk_said = true
			message.emit("Hacking at bulk rock: rubble only. Scan it (right-click) to find its veins")
	_beam.aim(nose, hit)
	_mining_sound(true)


func _draw() -> void:
	pass   # (the engine flame is drawn by the exhaust trail - ExhaustTrail)
