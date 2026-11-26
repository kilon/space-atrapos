extends Node2D
## AI ship, hostile or neutral. Look, stats and faction come from EnemyTypes
## (set type_id before adding it to the tree).
##
## Hostile ships patrol around their home point and attack the nearest target
## in range - the player or a neutral ship.
## Neutral ships travel between stations and explore open space. They fight
## back against whoever attacks them, and only turn on the player if the
## player shoots them (staying hostile for PROVOKE_TIME seconds).
## Nobody fights inside a station's safe zone.
## The root node never rotates (so bars stay upright); $Body does.

signal died(ship: Node2D)
## A trader ship reached the end of its current route leg (Galaxy record).
signal leg_reached(ship: Node2D)

enum State { PATROL, ATTACK }

const PROVOKE_TIME := 30.0
const RETARGET_INTERVAL := 0.4

@export var type_id := "interceptor"
@export var acceleration := 320.0
@export var turn_speed := 3.0
@export var leash_range := 1100.0
## Shields recharge this fast after shield_regen_delay seconds without a hit.
@export var shield_regen := 8.0
@export var shield_regen_delay := 4.0

# Filled from the type in _ready().
var faction := "enemy"   # "enemy" or "neutral"
var display_name := ""
var max_hull := 60.0
var max_shields := 30.0
var max_speed := 230.0
var aggro_range := 520.0
var preferred_distance := 320.0
var fire_interval := 1.1
var bullet_speed := 650.0
var bullet_damage := 8.0
var shots := 1
var bolt_color := Color(1.0, 0.35, 0.2)
var travel_bias := 0.5   # neutral: chance to head for a station vs. explore
var hit_radius := 34.0
var click_radius := 48.0
var _half_height := 50.0

# Sandbox: who flies this ship, what it's doing and what it carries.
var empire := ""            # Galaxy.EMPIRES id ("" = plain hostile / neutral)
## A war fleet's ship (Fleets: its id - a loss counts there), and, for an
## invasion, the station it besieges (attacked when no enemy ship is near).
var fleet_id := ""
var siege_target: Node2D = null
var role := ""              # trader, miner, explorer, patrol, pirate
var cargo: Dictionary = {}  # item id -> units (traders share it with their Galaxy record)
var credits := 0
var record_id := ""         # the Galaxy trader record this ship flies
var leg_target := Vector2.ZERO
var has_leg := false
var surrendered := 0.0      # seconds left: hijacked, pirates leave it alone

var hull := -1.0     # -1 = not set yet (full health)
var shields := -1.0  # -1 = not set yet (full shields)
var velocity := Vector2.ZERO
var home := Vector2.ZERO
var state := State.PATROL
var targeted := false:
	set(v):
		targeted = v
		queue_redraw()
		_update_outline()
var _outline: TargetOutline   # glowing red outline round the sprite while targeted
## Whoever damaged this ship last (used to credit kills and to fight back).
var last_attacker: Node2D = null
## Set by the main quest for its own ships: they don't respawn and aren't saved.
var quest_tag := ""
## Unique story bosses (Asterion, Talos).
var boss := false
var _tint := Color.WHITE

var _target: Node2D = null
var _retarget_cd := 0.0
var hunting := false       # a creature on your trail (_creature_target)
var leader: Node2D         # (a Hydra's double head) it keeps its place round this ship
var damage_mult := 1.0     # everything it hurts takes this x the damage (a signal's level: SignalSites)
var untouchable := false   # (a Hydra's double head) can't be targeted or hurt: it dies only with its leader
var leader_slot := 0.0     # ... at this angle
var _led := false
const HUNT_SPACE := 60000.0  # (a signal site is far beyond this: no hunting across)
const PREY_REACH := 450.0    # a hunting creature attacks NPC ships this close
var _provoked := 0.0       # neutral: seconds left being hostile to the player
var _rep_hit := false
## Fitted with an Electro (Items.WEAPONS "electro"): fires lightning instead
## of bolts - and a salvaged wreck may give it up (Wreck). Saved.
var electro := false
var _stun_t := 0.0
## Caught in a Bouncer Plasma's web (PlasmaBouncer.PlasmaWeb): slowed, tied to the others.
var web: Node2D = null      # the player's first shot at it has cost reputation already
var _alive := true
var _since_hit := 99.0
var _shield_fx: ShieldEffect
var _patrol_point := Vector2.ZERO
var _wait := 0.0           # neutral: pause at a destination
var _fire_cd := 0.0
var _strafe_dir := 1.0
var _time := 0.0
var _pending_rotation := 0.0

## Civilian miners cut ore from the asteroid fields with a mining beam, fill
## their hold, sell it at a station and go back for more.
const MINER_DPS := 22.0
const MINER_HOLD := 40
var _mine_rock: Node2D = null
var _beam: MiningBeam
var _unloading := false
var _mine_face := Vector2.ZERO

@onready var body: Sprite2D = $Body


func _ready() -> void:
	_apply_type()
	if not condition.is_empty():
		_apply_parts()   # (damage it had when saved)
	add_to_group(faction_group())
	if hull < 0.0:
		hull = max_hull
	if shields < 0.0:
		shields = max_shields
	body.rotation = _pending_rotation
	_outline = TargetOutline.new()
	body.add_child(_outline)
	_update_outline()
	if home == Vector2.ZERO:
		home = global_position
	_patrol_point = home
	if is_neutral():
		_pick_destination()
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_fire_cd = randf_range(0.3, fire_interval)
	# Some warships and raiders carry an Electro (none of the civilians, nor creatures).
	if not _electro_set and not boss and not is_creature() and role in ["patrol", "pirate"]:
		_electro_set = true
		var cls := str(EnemyTypes.get_type(type_id).get("class", "fighter"))
		electro = randf() < ELECTRO_CHANCE.get(cls, 0.08)
		bouncer = not electro and randf() < BOUNCER_CHANCE.get(cls, 0.05)
	if loadout.is_empty() and not boss and not is_creature() and not electro and not bouncer:
		loadout = Hardpoints.loadout(type_id, role, randi())
	_arm()


## ...and (those without one) with a Bouncer Plasma.
const BOUNCER_CHANCE := {"fighter": 0.05, "interceptor": 0.06, "gunship": 0.15, "frigate": 0.18}
## Fitted with a Bouncer Plasma (Items.WEAPONS "bouncer"): fires a bouncing
## ball of plasma that webs you to its ship and its wingmen. Saved.
var bouncer := false

## The share of warships of each hull class fitted with an Electro.
const ELECTRO_CHANCE := {"fighter": 0.08, "interceptor": 0.1, "gunship": 0.22, "frigate": 0.25}
var _electro_set := false


## Struck by lightning: drifting, guns silent, for `t` s.
func stun(t: float) -> void:
	if boss or is_creature():
		t *= 0.3   # (the great beasts shrug most of it off)
	_stun_t = maxf(_stun_t, t)


## Lock-on: a glowing red outline round the ship's shape.
func _update_outline() -> void:
	if _outline != null:
		_outline.on = targeted and not body.has_node("Monster")


func _apply_type() -> void:
	var t: Dictionary = EnemyTypes.get_type(type_id)
	faction = t.get("faction", "enemy")
	display_name = t["name"]
	max_hull = t["hull"]
	max_shields = t.get("shields", 0.0)
	max_speed = t["speed"]
	aggro_range = t["aggro"]
	preferred_distance = t["distance"]
	fire_interval = t["fire_interval"]
	bullet_speed = t["bullet_speed"]
	bullet_damage = t["damage"]
	shots = t["shots"]
	bolt_color = t["color"]
	boss = t.get("unique", false)
	capital = t.get("capital", false)
	shield_regen = t.get("shield_regen", shield_regen)
	shield_regen_delay = t.get("shield_delay", shield_regen_delay)
	travel_bias = t.get("travel_bias", 0.5)
	# Empire ships: pirates are hostile, everyone else is neutral to you
	# (unless your reputation with their empire is bad).
	if empire != "":
		faction = "enemy" if empire == "pirates" else "neutral"
	if empire == "pirates":
		role = "pirate"
	elif t.get("role", "") in ["trader", "miner", "explorer"]:
		role = t["role"]
	elif empire != "":
		role = "patrol"
	if empire != "" and empire != "pirates":
		display_name = "%s %s" % [Galaxy.EMPIRES[empire]["short"], t["name"]]
	elif empire == "pirates":
		display_name = "Sea Raider " + t["name"]

	body.texture = EnemyTypes.texture(type_id)
	_tint = t.get("tint", Color.WHITE)
	body.modulate = _tint
	var length: float = maxf(t["length"], EnemyTypes.MIN_LENGTH)
	var s := length / body.texture.get_size().y
	body.scale = Vector2(s, s)
	var size: Vector2 = body.texture.get_size() * s
	_half_height = size.y / 2.0
	hit_radius = (size.x + size.y) / 4.0 * 0.75
	click_radius = maxf(hit_radius * 1.3, 40.0)
	# Hostile shields glow red-orange, neutral ones green.
	var shield_col := Color(0.3, 1.0, 0.55) if is_neutral() else Color(1.0, 0.35, 0.2)
	var hit_col := Color(0.8, 1.0, 0.85) if is_neutral() else Color(1.0, 0.85, 0.6)
	if t.get("monster", false):   # a creature: drawn as a SpaceMonster, not its sizing ship
		body.self_modulate = Color(1, 1, 1, 0)
		if not body.has_node("Monster"):
			var look: String = t.get("look", "")
			var m: SpaceMonster
			match look:
				"sea_witch": m = SeaWitch.new()
				"minotaur": m = MinotaurBoss.new()
				"cerberus": m = CerberusBeast.new()
				"cetus": m = CetusBeast.new()
				"echidna": m = EchidnaBeast.new()
				"hydra": m = HydraBeast.new()
				"hydra_head": m = HydraHead.new()
				"chimera": m = ChimeraBeast.new()
				"charybdis": m = CharybdisBeast.new()
				_: m = SpaceMonster.new()
			m.name = "Monster"
			m.length = length
			m.enemy = self
			m.scale = Vector2.ONE / body.scale
			body.add_child(m)
		display_name = t["name"]
		# Its shield round the creature as drawn (not the hidden sizing ship),
		# and shots hit what you see.
		var m2: SpaceMonster = body.get_node("Monster")
		size = m2.visual_size()
		hit_radius = (size.x + size.y) / 4.0 * 0.62
		click_radius = maxf(hit_radius * 1.1, 40.0)
	# A sphere round the whole sprite, ships and creatures alike.
	_shield_fx = ShieldEffect.new().setup(ShieldEffect.sphere_for(size), shield_col, hit_col)
	add_child(_shield_fx)
	if t.get("monster", false):   # (a creature's shield behind it, and softer: it glows round the art, not over it)
		move_child(_shield_fx, 0)
		_shield_fx.modulate.a = 0.28
	# The exhaust trail (ExhaustTrail): pirates and Spartans burn orange,
	# Athenians and Ionians blue, the others magenta. Creatures have none.
	if not t.get("monster", false) and not has_node("ExhaustTrail"):
		var trail_style := "magenta"
		if empire == "pirates" or empire == "sparta" or faction == "enemy":
			trail_style = "orange"
		elif empire in ["athens", "ionia"]:
			trail_style = "blue"
		ExhaustTrail.attach(self, trail_style, length)


func is_alive() -> bool:
	return _alive


func is_neutral() -> bool:
	return faction == "neutral"


## Group projectiles must target to hit this ship.
func faction_group() -> StringName:
	return &"neutrals" if is_neutral() else &"enemies"


## Neutral ships that the player provoked show up as hostile, as do the
## warships of empires that consider you an enemy.
func is_hostile_to_player() -> bool:
	return not is_neutral() or _provoked > 0.0 or _empire_hates_player()


func _empire_hates_player() -> bool:
	return role == "patrol" and empire != "" and Galaxy.is_hostile_to_player(empire)


## Is `other` an enemy of this ship's empire (war, or pirates)?
func _is_foe(other: Node) -> bool:
	if other == null or not is_instance_valid(other) or other.get("empire") == null:
		return false
	var e: String = other.empire
	if empire == "" or e == "":
		return false
	return Galaxy.at_war(empire, e)


## Hijacked: hand over the cargo and leave pirates alone for a while.
func surrender() -> void:
	surrendered = 60.0
	_target = null
	state = State.PATROL


## Pirates board a disabled ship and take its cargo.
func _hijack(victim: Node2D) -> void:
	var stolen := []
	for c in victim.cargo.keys():
		var n: int = victim.cargo[c]
		cargo[c] = cargo.get(c, 0) + n
		stolen.append("%d %s" % [n, Items.display_name(c)])
	victim.cargo.clear()
	victim.surrender()
	_target = null
	_retarget_cd = 3.0
	var text := "%s hijacked the %s%s" % [display_name, victim.display_name,
		(" - stole " + ", ".join(stolen)) if not stolen.is_empty() else " - its hold was empty"]
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var near := player != null and player.global_position.distance_to(global_position) < 4000.0
	GameLog.post(text, "danger" if near else "info")
	Galaxy.news.push_front({"t": Galaxy.time, "text": text, "kind": "news"})


func take_damage(amount: float, from: Vector2, attacker: Node2D = null, dtype := "") -> void:
	if untouchable:
		return
	if not _alive:
		return
	if is_instance_valid(attacker) and attacker.get("damage_mult") != null:
		amount *= float(attacker.damage_mult)   # (a signal's level)
	_since_hit = 0.0
	if attacker:
		last_attacker = attacker
		# Fight back: switch to whoever shot us (unless it's a fellow neutral).
		if not (attacker.has_method("is_neutral") and attacker.is_neutral() and is_neutral()):
			_target = attacker
			state = State.ATTACK
		if is_neutral() and attacker.is_in_group("player"):
			if _provoked <= 0.0:
				GameLog.post("%s is now hostile to you" % display_name, "danger")
			if not _rep_hit and empire != "" and empire != "pirates":
				_rep_hit = true   # (firing on one of their ships costs reputation - once a ship)
				Galaxy.change_reputation(empire, Galaxy.REP_PROVOKE, "you fired on one of their ships")
			_provoked = PROVOKE_TIME
		if fleet_id != "" and is_instance_valid(attacker) and attacker.get("fleet_id") != fleet_id:
			_alert_fleet(attacker)
	elif not is_neutral():
		state = State.ATTACK

	# Shields absorb damage first (a beam drains them twice as fast, and
	# barely scratches the hull: Gear.split).
	var sp := Gear.split(dtype, shields, amount)
	var absorbed := sp.x
	shields -= absorbed
	amount = sp.y
	if attacker and attacker.is_in_group("player"):
		GameLog.damage_dealt(display_name, absorbed, minf(amount, maxf(hull, 0.0)))
	if absorbed > 0.0:
		_shield_fx.hit(from)
	if amount > 0.0 and _fx.has("hull_taken_mult"):
		amount *= maxf(0.1, 1.0 + float(_fx["hull_taken_mult"]))   # (its plating damaged: more gets through)
	if amount > 0.0:
		hull -= amount
		if hull > 0.0:
			_part_hit(amount, from, dtype, attacker)
			if _sparks == null and hull < max_hull * 0.75 and not is_creature():   # (electrical faults crackling off it: FaultSparks)
				_sparks = FaultSparks.attach(self, maxf(40.0, hit_radius), func(): return 1.0 - hull / maxf(1.0, max_hull) if _alive else 0.0)
		body.modulate = Color(1.5, 1.5, 1.5) if body.has_node("Monster") else Color(3, 3, 3)   # (painted creatures: a softer flash)
		create_tween().tween_property(body, "modulate", _tint, 0.15)
	queue_redraw()
	if hull <= 0.0:
		_die()


# --- Its guns: a loadout for its class (Hardpoints) ----------------------------------
# Each weapon on its hardpoints fires from its place on the hull; the same
# weapons fire together as a battery (a volley of bolts). Its damage a second
# is its type's (damage x shots / fire_interval - what it always did) spread
# over the batteries by how hard each kind and size hits; they fire NPC_PACE
# times slower than yours would (fewer, heavier bolts: a battle of a dozen
# capital ships stays a few hundred bolts). Electro and Bouncer ships, the
# bosses and creatures fire as before (_shoot).

const NPC_PACE := 3.0
## At most this many bolts in one battery's volley (more guns: heavier bolts).
const MAX_VOLLEY := 4

var loadout: Array = []     # weapon item ids (Hardpoints), saved
var capital := false        # a cruiser, battleship or dreadnought (ShipDesigns.CAPITALS)
var _batteries: Array = []  # [{id, n, cd, iv, dmg, slots: [hardpoint i]}]

## The batteries from the loadout.
func _arm() -> void:
	_batteries = []
	if loadout.is_empty():
		return
	var t := EnemyTypes.get_type(type_id)
	var dps := float(t["damage"]) * float(t["shots"]) / maxf(0.1, float(t["fire_interval"]))
	var by := {}
	for i in loadout.size():
		by.get_or_add(str(loadout[i]), []).append(i)
	var natural := 0.0
	for id in by:
		var w := Hardpoints.stats(id)
		natural += float(w["damage"]) / float(w["interval"]) * by[id].size()
	for id in by:
		var w := Hardpoints.stats(id)
		var n: int = by[id].size()
		var share := float(w["damage"]) / float(w["interval"]) * n / maxf(0.001, natural)
		var iv := float(w["interval"]) * NPC_PACE
		var bolts := mini(n, MAX_VOLLEY)
		_batteries.append({"id": id, "n": bolts, "cd": randf_range(0.2, iv), "iv": iv, "dmg": dps * share * iv / bolts,
			"slots": by[id], "style": w["style"], "speed": float(w["speed"]), "color": w["color"] if w["style"] != "laser" else bolt_color})


## Its batteries fire at `target` as they come round (`delta`: time since last).
func _fire_batteries(delta: float, target: Node2D) -> void:
	var dist := global_position.distance_to(target.global_position)
	var group: StringName = &"player" if target.is_in_group("player") else target.faction_group()
	var dk := 1.0 + float(_fx.get("damage_mult", 0.0))
	var ik := maxf(0.2, 1.0 + float(_fx.get("fire_rate_mult", 0.0)))
	var half := Vector2(body.texture.get_size().x * body.scale.x * 0.32, _half_height * 0.84) if body.texture else Vector2(20, 40)
	var fired := false
	for b in _batteries:
		b["cd"] = float(b["cd"]) - delta
		if float(b["cd"]) > 0.0:
			continue
		b["cd"] = float(b["iv"]) * ik * randf_range(0.9, 1.1)
		var speed: float = b["speed"]
		var aim: Vector2 = target.global_position + target.velocity * (dist / speed) * 0.6
		var slots: Array = b["slots"]
		for k in int(b["n"]):
			var at: Vector2 = global_position + Hardpoints.mount(int(slots[k % slots.size()]), loadout.size(), half).rotated(body.rotation)
			var d := at.direction_to(aim)
			d = Affliction.scattered(d, float(_fx.get("scatter", 0.0)))
			var hit := _wild == 0 and Accuracy.roll(accuracy(), at, target, aggro_range * 1.2)
			if _wild != 0:
				d = Affliction.wild_dir(Vector2.UP.rotated(body.rotation))
			elif not hit:   # (a miss: aimed past it, flying on by - Accuracy)
				d = Accuracy.miss_dir(at, aim, float(target.get("hit_radius")) if target.get("hit_radius") != null else 30.0)
			var p := Projectile.fire(get_tree(), at, d, speed, float(b["dmg"]) * dk, group, b["color"], b["style"], self)
			if not hit:
				p.ignore = target
			if b["style"] == "missile" and hit:
				p.homing_target = target
		fired = true
	if fired:
		Sfx.play_world("space/enemy_laser", global_position, -2.0)


# --- Damaged parts ---------------------------------------------------------------
# Hits through to the hull damage its parts like yours (Parts.hit on its own
# condition, the side hit deciding which): the shield emitter - weaker shields,
# the engines - slower, the thrusters - sluggish and jerking off course, the
# weapon mounts - slower fire and now and then shooting wild, the sensors -
# shots scattering (Affliction). Not creatures (no parts).

var condition := {}        # Parts condition of its "ship" body (saved)
var _sparks: FaultSparks
var _fx := {}              # Parts.effects of it (_apply_parts)
var _base_stats := {}      # its stats sound (the first time a part is hit)
var _afflict := Affliction.new_state()
var _wild := 0             # Affliction.misfire: 0 on target, else firing wild

func _part_hit(amount: float, from: Vector2, dtype: String, attacker: Node2D) -> void:
	if is_creature() or untouchable:
		return
	var local := (from - global_position).rotated(-body.rotation) if from != Vector2.ZERO else Vector2.ZERO
	var f := Parts.hit(condition, "ship", amount, max_hull, dtype if dtype != "" else "kinetic", local)
	if f.is_empty():
		return
	_apply_parts()
	if is_instance_valid(attacker) and attacker.is_in_group("player"):
		var p: Dictionary = Parts.info("ship", str(f["part"]))
		GameLog.post("%s: %s hit - %s down" % [display_name, p["name"].to_lower(), p["what"].get_slice(" (", 0)], "combat")


## Its chance to hit (Accuracy): its class's, less its damaged sensors'.
func accuracy() -> float:
	var cls := str(EnemyTypes.get_type(type_id).get("class", "fighter"))
	return clampf(float(Accuracy.NPC.get(cls, 0.72)) + (0.08 if boss else 0.0) + float(_fx.get("accuracy", 0.0)), 0.2, 0.98)


## How hard it is to hit (Accuracy): the small, fast ones more.
var evasion: float:
	get:
		return {"interceptor": 0.14, "fighter": 0.1, "courier": 0.1}.get(str(EnemyTypes.get_type(type_id).get("class", "")), 0.03)


## Its stats from its sound ones and its parts' damage (Parts.effects).
func _apply_parts() -> void:
	if _base_stats.is_empty():
		_base_stats = {"shields": max_shields, "speed": max_speed, "accel": acceleration, "turn": turn_speed,
			"regen": shield_regen, "delay": shield_regen_delay, "interval": fire_interval, "damage": bullet_damage}
	_fx = Parts.effects(condition, "ship")
	var b := _base_stats
	max_shields = b["shields"] * maxf(0.1, 1.0 + float(_fx.get("max_shields_mult", 0.0)))
	if shields >= 0.0:
		shields = minf(shields, max_shields)
	max_speed = b["speed"] * maxf(0.2, 1.0 + float(_fx.get("speed_mult", 0.0)))
	acceleration = b["accel"] * maxf(0.2, 1.0 + float(_fx.get("handling_mult", 0.0)))
	turn_speed = b["turn"] * maxf(0.2, 1.0 + float(_fx.get("handling_mult", 0.0)))
	shield_regen = b["regen"] * maxf(0.0, 1.0 + float(_fx.get("shield_regen_mult", 0.0)))
	shield_regen_delay = b["delay"] + float(_fx.get("regen_delay", 0.0))
	fire_interval = b["interval"] * maxf(0.2, 1.0 + float(_fx.get("fire_rate_mult", 0.0)))
	bullet_damage = b["damage"] * maxf(0.1, 1.0 + float(_fx.get("damage_mult", 0.0)))


func _die() -> void:
	if not _alive:
		return
	_alive = false
	# A creature dies slowly: it shakes, bursting, then blows up hugely
	# (SpaceMonster.death_throes) - and only then is it gone (the quest moves on).
	var mon := body.get_node_or_null("Monster") as SpaceMonster
	if mon:
		set_process(false)
		velocity = Vector2.ZERO
		_shield_fx.visible = false
		await mon.death_throes()
	else:
		Effects.explosion(global_position, clampf(hit_radius / 30.0, 0.8, 2.2), Effects.ship_sound(max_hull + max_shields))
	died.emit(self)
	queue_free()


# --- Targeting -----------------------------------------------------------------

## A creature (a SpaceMonster's body) - it hunts (_creature_target).
func is_creature() -> bool:
	return body != null and body.has_node("Monster")


## A creature that has once gone for you hunts you down: it never gives up the
## chase (no leash; it matches your ship's speed: _process), and any NPC ship
## that comes within PREY_REACH on the way gets attacked - the nearest first.
## (Not while you're in another space - a signal site far off, or it is.)
func _creature_target(player: Node2D) -> Node2D:
	var hunt_ok := _valid_target(player) and global_position.distance_to(player.global_position) < HUNT_SPACE
	if hunt_ok and not hunting and global_position.distance_to(player.global_position) < aggro_range:
		hunting = true
	var best: Node2D = null
	var best_d := PREY_REACH + hit_radius
	for n in get_tree().get_nodes_in_group("neutrals"):
		if not _valid_target(n):
			continue
		var d := global_position.distance_to(n.global_position)
		if d < best_d:
			best = n
			best_d = d
	if best != null:
		return best
	if hunting and hunt_ok:
		return player
	return null


## Untyped on purpose: callers may pass a ship that was already freed, and a
## typed parameter would error before is_instance_valid() could check it.
func _valid_target(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is SpaceStation:
		return n.is_alive()   # (a siege: its safe zone doesn't count)
	if n.get("cloaked") == true:
		return false   # (a cloaked ship can't be seen: Ship.cloak)
	return n != null and is_instance_valid(n) and n.is_alive() \
			and SpaceStation.protecting(n.global_position) == null \
			and SpaceStation.protecting(global_position) == null


## The Projection Array's illusions up: an enemy turning on you takes its
## pick of you and them (once for each projection - it keeps to its choice).
var _decoy_pa: Node = null

func _decoyed(t: Node2D) -> Node2D:
	if t == null or not t.is_in_group("player"):
		return t
	var pa: Node = get_tree().get_first_node_in_group("projection_arrays")
	if pa == null or pa == _decoy_pa:
		return t
	_decoy_pa = pa
	return pa.pick(t)


func _choose_target() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if surrendered > 0.0:
		return null
	if is_creature():
		var c := _creature_target(player)
		if c != null:
			return c
	# A war fleet fights as one: the target its leader (or else a wingman) has.
	if fleet_id != "":
		var ft := _fleet_target(player)
		if ft != null:
			return ft

	# Keep fighting the current target while it's in leash range.
	if _valid_target(_target) and global_position.distance_to(_target.global_position) < leash_range \
			and _target.get("surrendered") in [null, 0.0]:
		if _target != player or is_hostile_to_player():
			return _target

	var best: Node2D = null
	var best_d := aggro_range
	if is_neutral():
		# The player: if provoked, or if our empire is hostile (warships only).
		if (_provoked > 0.0 or _empire_hates_player()) and _valid_target(player):
			var d := global_position.distance_to(player.global_position)
			if d < (leash_range if _provoked > 0.0 else aggro_range):
				return player
		# Pirates (warships hunt them; civilians only fight back) ...
		for e in get_tree().get_nodes_in_group("enemies"):
			if (e._target == self or role == "patrol") and _valid_target(e):
				var d := global_position.distance_to(e.global_position)
				if d < best_d:
					best = e
					best_d = d
		# ... and ships of empires at war with ours.
		if empire != "":
			for n in get_tree().get_nodes_in_group("neutrals"):
				if n == self or not _is_foe(n) or not _valid_target(n):
					continue
				if role != "patrol" and n._target != self:
					continue
				var d := global_position.distance_to(n.global_position)
				if d < best_d:
					best = n
					best_d = d
		# An invasion: no enemy ship near - the station it besieges (that one
		# gone: the next of the empires it's at war with, the most damaged).
		if best == null and siege_target != null:
			if not is_instance_valid(siege_target) or not siege_target.is_alive():
				siege_target = null
				var low := INF
				for st in get_tree().get_nodes_in_group("stations"):
					if st.is_alive() and Galaxy.at_war(empire, st.empire) and st.health() < low:
						low = st.health()
						siege_target = st
			if siege_target != null and Galaxy.at_war(empire, siege_target.empire):
				return siege_target
	else:
		# Pirates / hostiles: the nearest of the player and other ships;
		# loaded freighters are the juiciest prey.
		var candidates: Array = get_tree().get_nodes_in_group("neutrals")
		if player:
			candidates.append(player)
		for c in candidates:
			if not _valid_target(c) or c.get("surrendered") not in [null, 0.0]:
				continue
			var d := global_position.distance_to(c.global_position)
			if c.get("role") in ["trader", "miner"] and not c.cargo.is_empty():
				d *= 0.6
			if d < best_d:
				best = c
				best_d = d
	return best


# --- Update -----------------------------------------------------------------------

## What's on screen in space (and a margin) - Main sets it each frame: ships
## out of it think every other frame (the time between added up).
static var view_rect := Rect2()
var _off_k := randi() % 2

func _process(delta: float) -> void:
	if view_rect.has_area() and not boss and not view_rect.has_point(global_position):
		_off_k = (_off_k + 1) % 2
		if _off_k != 0:
			return
		delta *= 2.0
	_time += delta
	_provoked = maxf(0.0, _provoked - delta)
	if is_creature():   # (it keeps up with you: your ship's speed, as upgraded)
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.get("max_speed") != null:
			max_speed = pl.max_speed
			acceleration = maxf(acceleration, float(pl.acceleration))
	surrendered = maxf(0.0, surrendered - delta)
	_retarget_cd -= delta
	# (Look again every RETARGET_INTERVAL, or at once when the target is lost -
	# not every frame while a ship has none: a battle's idle ships searched all
	# the others each frame. Creatures do look every frame: they hunt you.)
	if _retarget_cd <= 0.0 or (not _valid_target(_target) and (_target != null or is_creature())):
		_retarget_cd = RETARGET_INTERVAL
		var before := _target if is_instance_valid(_target) else null
		_target = _decoyed(_choose_target())
		if _target != null and _target != before and _target.is_in_group("player"):
			GameLog.post("%s is attacking you" % display_name, "combat")
	state = State.ATTACK if _target else State.PATROL
	if _beam and (_target or has_leg or role != "miner"):
		_beam.off()

	var desired := Vector2.ZERO
	var face_dir := velocity

	if _target:
		var to_t := _target.global_position - global_position
		var dist := to_t.length()
		face_dir = to_t
		var dir := to_t / maxf(dist, 0.001)
		var lead := _fleet_lead()
		if lead != null and lead._target == _target:
			desired = _arc_slot(lead)   # (a wingman: its place in the fleet's arc round the target)
		elif dist > preferred_distance + 60.0:
			desired = dir * max_speed
		elif dist < preferred_distance - 60.0:
			desired = -dir * max_speed * 0.7
		else:
			desired = dir.orthogonal() * _strafe_dir * max_speed * (0.35 if fleet_id != "" else 0.6)
			if randf() < 0.005:
				_strafe_dir = -_strafe_dir
		# Pirates board disabled civilian ships instead of destroying them.
		if role == "pirate" and _target.get("role") in ["trader", "miner", "explorer"] \
				and _target.hull < _target.max_hull * 0.45 and dist < 500.0:
			_hijack(_target)
			return
		if _fx.has("misfire"):   # (damaged fire control: now and then off the target)
			_wild = Affliction.misfire(_afflict, _fx["misfire"], delta)
		_fire_cd -= delta
		if not _batteries.is_empty():
			if dist < aggro_range * 1.2 and _stun_t <= 0.0:
				_fire_batteries(delta, _target)
		elif _fire_cd <= 0.0 and dist < aggro_range * 1.2 and _stun_t <= 0.0:
			_fire_cd = fire_interval * randf_range(0.85, 1.15)
			if electro:
				_fire_cd = maxf(_fire_cd, float(Items.WEAPONS["electro"]["interval"]) * 1.4)
			elif bouncer:
				_fire_cd = maxf(_fire_cd, float(Items.WEAPONS["bouncer"]["interval"]) * 1.5)
			_shoot(_target)
	elif has_leg:
		# Trade route: fly to the leg's end (station or gate) at cruise speed.
		var to_leg := leg_target - global_position
		if to_leg.length() < 140.0:
			has_leg = false
			leg_reached.emit(self)
		desired = to_leg.normalized() * max_speed * (1.0 if surrendered > 0.0 else 0.85)
		face_dir = to_leg
	elif is_neutral() and role == "miner":
		desired = _mine(delta)
		if _mine_face.length_squared() > 1.0:
			face_dir = _mine_face
	elif is_neutral() and role != "patrol":
		desired = _travel(delta)
	elif fleet_id != "" and _fleet_lead() != null:
		var lead := _wing_lead
		desired = _formation_slot(lead)   # (a wingman: its place in the wedge behind the leader)
		if lead.velocity.length_squared() > 400.0:
			face_dir = lead.velocity
	else:
		desired = _patrol() * (0.8 if fleet_id != "" else 1.0)   # (a fleet's leader: a little slower, the wedge keeps up)

	if _led:   # keeping its place round its leader (Hydra double heads), dying with it
		if not is_instance_valid(leader) or not leader.is_alive() or leader.process_mode == Node.PROCESS_MODE_DISABLED:
			if is_instance_valid(leader) and leader.process_mode == Node.PROCESS_MODE_DISABLED:
				queue_free()   # (it dived into the void after you: they're lost)
			else:
				hull = 0.0
				_die()
			return
		var slot: Vector2 = leader.global_position + Vector2.from_angle(leader_slot + _time * 0.15) * (leader.hit_radius + hit_radius + 70.0)
		desired = (slot - global_position) * 3.0
		desired = desired.limit_length(maxf(max_speed, leader.velocity.length()) * 1.3) + leader.velocity
	else:
		desired += _separation() * max_speed
	if _stun_t > 0.0:   # (stunned: the drive dead - it drifts)
		_stun_t -= delta
		desired = velocity * 0.9
	velocity = velocity.move_toward(desired, acceleration * delta)
	if _fx.has("jitter"):   # (damaged thrusters: kicked off course, the nose wobbling)
		var j: float = _fx["jitter"]
		velocity += Affliction.jitter_push(_afflict, j, delta, max_speed) * delta * 1.5
		body.rotation += Affliction.jitter_turn(_afflict, j) * delta
	if web != null:
		if is_instance_valid(web):
			velocity = web.constrain(self, velocity)
		else:
			web = null
	global_position += velocity * delta

	if face_dir.length_squared() > 1.0:
		body.rotation = rotate_toward(body.rotation, face_dir.angle() + PI / 2.0, turn_speed * delta)
	_shield_fx.rotation = body.rotation

	# Shield recharge.
	_since_hit += delta
	if _since_hit > shield_regen_delay and shields < max_shields:
		shields = minf(max_shields, shields + shield_regen * delta)
		queue_redraw()

	if targeted:
		queue_redraw()


## Miner: pick a rock (at most two miners per rock), park beside it facing
## it and cut ore into the hold; when full, sell it at the nearest station.
## With no rocks left in the system it just wanders like a trader.
func _mine(delta: float) -> Vector2:
	_mine_face = Vector2.ZERO
	if _beam == null:
		_beam = MiningBeam.new()
		_beam.width = 0.7
		add_child(_beam)
	if _unloading or _ore_held() >= MINER_HOLD:
		_beam.off()
		_mine_rock = null
		return _unload(delta)
	if not (is_instance_valid(_mine_rock) and _mine_rock.is_alive()):
		_mine_rock = _pick_rock()
		if _mine_rock == null:
			_beam.off()
			return _travel(delta)
	var rock: Node2D = _mine_rock
	var to_rock := rock.global_position - global_position
	var stand: float = rock.hit_radius + 200.0
	_mine_face = to_rock
	var desired := Vector2.ZERO
	if to_rock.length() > stand + 60.0:
		desired = to_rock.normalized() * minf(max_speed * 0.7, to_rock.length())
	elif to_rock.length() < stand - 60.0:
		desired = -to_rock.normalized() * max_speed * 0.3
	var facing := Vector2.UP.rotated(body.rotation)
	if to_rock.length() < stand + 120.0 and facing.dot(to_rock.normalized()) > 0.9:
		var nose: Vector2 = global_position + facing * _half_height * 0.6
		var hit: Vector2 = rock.global_position - nose.direction_to(rock.global_position) * rock.hit_radius * 0.7
		_beam.aim(nose, hit)
		rock.mine(MINER_DPS * delta, hit, self)
	else:
		_beam.off()
	return desired


func _ore_held() -> int:
	var n := 0
	for c in cargo:
		if str(c).ends_with("_ore"):
			n += int(cargo[c])
	return n


## The nearest live rock not already worked by two other miners.
func _pick_rock() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for rock in get_tree().get_nodes_in_group("asteroids"):
		if not rock.is_alive():
			continue
		var crew := 0
		for m in get_tree().get_nodes_in_group("neutrals"):
			if m != self and m.get("_mine_rock") == rock:
				crew += 1
		if crew >= 2:
			continue
		var d: float = global_position.distance_squared_to(rock.global_position)
		if d < best_d:
			best_d = d
			best = rock
	return best


## Full hold: fly to the nearest station, sell the ore (it leaves the hold),
## rest a moment, then go back to mining.
func _unload(delta: float) -> Vector2:
	_unloading = true
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_unloading = false
		return Vector2.ZERO
	var best: Node2D = null
	for st in get_tree().get_nodes_in_group("stations"):
		if best == null or global_position.distance_squared_to(st.global_position) < global_position.distance_squared_to(best.global_position):
			best = st
	if best == null:
		_unloading = false
		for c in cargo.keys():
			if str(c).ends_with("_ore"):
				cargo.erase(c)
		return Vector2.ZERO
	var dock: Vector2 = best.global_position + best.global_position.direction_to(global_position) * (best.radius + 140.0)
	var to_dock := dock - global_position
	_mine_face = to_dock
	if to_dock.length() < 120.0:
		# The ore goes into the station's market.
		var rec: Dictionary = Galaxy.stations.get(best.get("station_id"), {})
		for c in cargo.keys():
			if str(c).ends_with("_ore"):
				credits += int(cargo[c]) * 8
				if rec.has("stock") and rec["stock"].has(c):
					rec["stock"][c] = float(rec["stock"].get(c, 0.0)) + float(cargo[c])
				cargo.erase(c)
		_wait = randf_range(4.0, 8.0)
		return Vector2.ZERO
	return to_dock.normalized() * minf(max_speed * 0.7, to_dock.length())


## Neutral travel: fly to the destination, wait a moment, pick another.
func _travel(delta: float) -> Vector2:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_pick_destination()
		return Vector2.ZERO
	var to_dest := _patrol_point - global_position
	if to_dest.length() < 90.0:
		_wait = randf_range(3.0, 7.0)
		return Vector2.ZERO
	var speed := minf(max_speed * 0.6, to_dest.length())  # ease in on arrival
	return to_dest.normalized() * speed


## Patrolling (warships, pirates): a circuit of 4-6 waypoints round home,
## flown in order, always the same way round - a ship you follow sweeps
## round its beat instead of zig-zagging to random spots near home (which
## turned it back on itself every few seconds).
var _route := PackedVector2Array()
var _route_i := 0

func _patrol() -> Vector2:
	if _route.is_empty():
		var n := randi_range(4, 6)
		var r := randf_range(700.0, 1400.0)
		var a0 := randf() * TAU
		var way := 1.0 if randf() < 0.5 else -1.0
		for i in n:
			_route.append(home + Vector2.from_angle(a0 + way * i * TAU / n + randf_range(-0.2, 0.2)) * r * randf_range(0.85, 1.15))
		# Join it at the waypoint ahead of us (the nearest one's successor if we're past it).
		var best := 0
		for i in n:
			if global_position.distance_to(_route[i]) < global_position.distance_to(_route[best]):
				best = i
		_route_i = best
	if global_position.distance_to(_route[_route_i]) < 160.0:
		_route_i = (_route_i + 1) % _route.size()
	return global_position.direction_to(_route[_route_i]) * max_speed * 0.45


## Next stop: a station (traders mostly) or a point in open space (explorers).
func _pick_destination() -> void:
	var stations := get_tree().get_nodes_in_group("stations")
	if not stations.is_empty() and randf() < travel_bias:
		var st: Node2D = stations.pick_random()
		_patrol_point = st.global_position + Vector2.from_angle(randf() * TAU) * (st.radius + 120.0)
	else:
		var rocks := get_tree().get_nodes_in_group("asteroids")
		if EnemyTypes.get_type(type_id).get("role", "") == "miner" and not rocks.is_empty():
			# Miners prospect the asteroid fields.
			var rock: Node2D = rocks.pick_random()
			_patrol_point = rock.global_position + Vector2.from_angle(randf() * TAU) * 180.0
			return
		# Onward, roughly the way it was heading (not doubling back).
		var ahead := velocity.angle() if velocity.length() > 20.0 else (body.rotation - PI / 2.0)
		_patrol_point = global_position + Vector2.from_angle(ahead + randf_range(-1.6, 1.6)) * randf_range(1500, 3500)
		_patrol_point = _patrol_point.limit_length(7000.0)  # stay in the sector


# --- War fleets: formation and fighting as one ------------------------------------------

## A war fleet's ships (fleet_id) in the system, oldest first: the oldest
## alive leads; the others are its wingmen, each with a place (_wing_i) in a
## wedge behind it while they patrol or travel, and in an arc round the
## target when they fight - all at the same target (_fleet_target): the
## leader's, or whatever one of them has engaged. Hit one and the whole fleet
## turns on the attacker (_alert_fleet). Listed every WING_EVERY ms, not
## each frame.
const WING_EVERY := 250
const WING_GAP := 170.0
static var _wings := {}        # fleet id -> [ships], oldest first
static var _wings_at := -100000
var _wing_i := 0               # its place in its fleet (0: the leader)
var _wing_lead: Node2D         # the leader it keeps station on (null: it leads) - set with the list


static func _wings_now(tree: SceneTree) -> Dictionary:
	var now := Time.get_ticks_msec()
	if now - _wings_at < WING_EVERY:
		return _wings
	_wings_at = now
	_wings = {}
	for n in tree.get_nodes_in_group(&"neutrals") + tree.get_nodes_in_group(&"enemies"):
		var f = n.get("fleet_id")
		if f == null or f == "" or not n.is_alive():
			continue
		if not _wings.has(f):
			_wings[f] = []
		_wings[f].append(n)
	for f in _wings:
		var w: Array = _wings[f]
		# (a capital ship leads its fleet; else the first in)
		w.sort_custom(func(a, b): return a.capital if a.capital != b.capital else a.get_instance_id() < b.get_instance_id())
		for i in w.size():
			w[i]._wing_i = i
			w[i]._wing_lead = w[0] if i > 0 else null
	return _wings


## Its fleet's ships (alive, oldest first; [] for a ship in no fleet).
func fleet_mates() -> Array:
	if fleet_id == "":
		return []
	return (_wings_now(get_tree()).get(fleet_id, []) as Array).filter(func(m): return is_instance_valid(m) and m.is_alive())


## The leader it keeps station on - null for the leader itself and ships in
## no fleet. (Asked every frame: kept from the last listing, not looked up -
## listed again at once when the leader's gone.)
func _fleet_lead() -> Node2D:
	if fleet_id == "":
		return null
	_wings_now(get_tree())
	if _wing_lead != null and (not is_instance_valid(_wing_lead) or not _wing_lead.is_alive()):
		_wings_at = -100000
		_wing_lead = null
		_wings_now(get_tree())
	return _wing_lead


## The fleet's target: the leader's first, else the first a wingman has
## engaged (within its leash: a foe that got away is let go by all).
func _fleet_target(player: Node2D) -> Node2D:
	for m in fleet_mates():
		if m == self:
			continue
		var t = m._target
		if not _valid_target(t) or global_position.distance_to(t.global_position) > leash_range:
			continue
		if t == player and not is_hostile_to_player():
			continue
		if t.get("fleet_id") == fleet_id:
			continue
		return t
	return null


## Hit by `attacker`: every ship of the fleet turns on it (fired on by you:
## all of them hostile to you - the reputation cost was paid once, by the ship hit).
func _alert_fleet(attacker: Node2D) -> void:
	var by_player := attacker.is_in_group("player")
	var newly := false
	for m in fleet_mates():
		if m == self:
			continue
		if by_player and m.is_neutral():
			newly = newly or m._provoked <= 0.0
			m._provoked = PROVOKE_TIME
		if m._target != attacker:
			m._target = attacker
			m.state = State.ATTACK
			m._retarget_cd = RETARGET_INTERVAL
	if by_player and newly:
		GameLog.post("The %s fleet turns on you" % Galaxy.empire_name(empire), "danger")


## Its place in the wedge: behind the leader, alternately right and left,
## a row further back for every two ships.
func _wing_offset() -> Vector2:
	var row := (_wing_i + 1) / 2
	var side := 1.0 if _wing_i % 2 == 1 else -1.0
	var gap := maxf(WING_GAP, hit_radius * 2.0 + 80.0)
	var lr: float = _wing_lead.hit_radius * 0.7 if is_instance_valid(_wing_lead) else 0.0   # (clear of a big leader's hull)
	return Vector2(side * (row * gap + lr), row * gap * 0.85 + lr)   # (in the leader's frame: +y behind it)


func _formation_slot(lead: Node2D) -> Vector2:
	var heading: float = lead.velocity.angle() + PI / 2.0 if lead.velocity.length_squared() > 400.0 else lead.body.rotation
	var slot: Vector2 = lead.global_position + _wing_offset().rotated(heading)
	return _seek(slot, lead.velocity)


## Its place in the fleet's arc round the target: the leader at the middle,
## the wingmen to either side of it, all at their firing distance - the arc
## swings round as the leader circles.
func _arc_slot(lead: Node2D) -> Vector2:
	var c: Vector2 = _target.global_position
	var r := preferred_distance
	if _target is SpaceStation:
		r = maxf(r, float(_target.radius) + 220.0)
	var k := (_wing_i + 1) / 2 * (1.0 if _wing_i % 2 == 1 else -1.0)
	var step := maxf(WING_GAP, hit_radius * 2.0 + 80.0) / r
	var a := (lead.global_position - c).angle() + k * step
	return _seek(c + Vector2.from_angle(a) * r, lead.velocity)


## A velocity that brings it to `slot` and keeps it there, moving with `carry`.
func _seek(slot: Vector2, carry: Vector2) -> Vector2:
	var to := slot - global_position
	return (to * 2.0).limit_length(max_speed * 1.2) + carry * clampf(1.0 - to.length() / 600.0, 0.0, 1.0)


func _shoot(target: Node2D) -> void:
	if body.has_node("Monster"):
		return   # (a creature attacks in its own patterns: SpaceMonster)
	if _wild != 0 and (bouncer or electro):
		return   # (its fire control off the target: nothing to strike)
	if bouncer:
		# A ball of plasma: bounces between its foes, then webs them to this
		# ship and its wingmen (PlasmaBouncer).
		if global_position.distance_to(target.global_position) <= float(Items.WEAPONS["bouncer"]["range"]):
			PlasmaBouncer.fire(get_tree(), self, target, bullet_damage * 1.6, Items.WEAPONS["bouncer"])
		return
	if electro:
		# Lightning: strikes at once, leaps to the target's side's ships nearby.
		if global_position.distance_to(target.global_position) <= float(Items.WEAPONS["electro"]["range"]):
			ChainLightning.strike(get_tree(), self, target, bullet_damage * 2.0, Items.WEAPONS["electro"])
		return
	# Lead the target a bit, plus some inaccuracy.
	var t := global_position.distance_to(target.global_position) / bullet_speed
	var aim: Vector2 = target.global_position + target.velocity * t * 0.6
	var dir := global_position.direction_to(aim)
	var hit := Accuracy.roll(accuracy(), global_position, target, aggro_range * 1.2)
	if not hit:   # (a miss: the volley aimed past it - Accuracy)
		dir = Accuracy.miss_dir(global_position, aim, float(target.get("hit_radius")) if target.get("hit_radius") != null else 30.0)
	if not _fx.is_empty():
		dir = Affliction.scattered(dir, float(_fx.get("scatter", 0.0)))
		if _wild != 0:
			dir = Affliction.wild_dir(Vector2.UP.rotated(body.rotation))
	var group: StringName = &"player" if target.is_in_group("player") else target.faction_group()
	# Multi-shot types fire a fan of bolts.
	var spread := 0.12
	for i in shots:
		var offset := (i - (shots - 1) / 2.0) * spread
		var d := dir.rotated(offset)
		var pj := Projectile.fire(get_tree(), global_position + d * _half_height * 0.8, d,
				bullet_speed, bullet_damage, group, bolt_color, "laser", self)
		if not hit:
			pj.ignore = target
	Sfx.play_world("space/enemy_laser", global_position, -2.0)


## Push away from nearby ships so they don't stack on top of each other.
static var _ships: Array = []
static var _ships_frame := -1
static var _ship_pos := PackedVector2Array()   # (theirs, gathered once a frame: no node lookups per pair)
static var _ship_r := PackedFloat32Array()
static var _ship_r_max := 0.0

func _separation() -> Vector2:
	var push := Vector2.ZERO
	var f := Engine.get_process_frames()
	if f != _ships_frame:   # (the ships listed once a frame, not twice for each ship)
		_ships_frame = f
		_ships = get_tree().get_nodes_in_group(&"enemies") + get_tree().get_nodes_in_group(&"neutrals")
		_ship_pos.resize(_ships.size())
		_ship_r.resize(_ships.size())
		_ship_r_max = 0.0
		for i in _ships.size():
			var o = _ships[i]
			_ship_pos[i] = o.global_position
			_ship_r[i] = o.hit_radius
			_ship_r_max = maxf(_ship_r_max, o.hit_radius)
	var me := global_position
	var reach := hit_radius + _ship_r_max + 60.0
	for i in _ship_pos.size():
		var away: Vector2 = me - _ship_pos[i]
		if absf(away.x) >= reach or absf(away.y) >= reach:
			continue   # (most of them: far off)
		var d := away.length()
		var min_d: float = hit_radius + _ship_r[i] + 60.0
		if d < min_d and d > 0.01:   # (itself: d 0)
			push += away / d * (1.0 - d / min_d)
	return push


# --- Saving -------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {
		"type": type_id,
		"position": [global_position.x, global_position.y],
		"home": [home.x, home.y],
		"rotation": body.rotation if body else _pending_rotation,
		"hull": hull,
		"shields": shields,
		"empire": empire,
		"cargo": cargo,
		"credits": credits,
		"fleet": fleet_id,
		"electro": electro,
		"bouncer": bouncer,
		"condition": condition,
		"loadout": loadout,
	}


## Call before adding to the tree.
func load_save_data(data: Dictionary) -> void:
	type_id = data.get("type", type_id)
	var p: Array = data.get("position", [0, 0])
	var h: Array = data.get("home", p)
	position = Vector2(p[0], p[1])
	home = Vector2(h[0], h[1])
	_pending_rotation = data.get("rotation", 0.0)
	hull = data.get("hull", -1.0)
	shields = data.get("shields", -1.0)
	empire = data.get("empire", "")
	fleet_id = str(data.get("fleet", ""))
	electro = bool(data.get("electro", false))
	bouncer = bool(data.get("bouncer", false))
	_electro_set = true
	condition = Parts.load_condition(data.get("condition", {})) if data.get("condition", {}) is Dictionary and not data.get("condition", {}).is_empty() else {}
	loadout = Array(data.get("loadout", [])).map(func(x): return str(x)).filter(func(x): return not Hardpoints.parse(x).is_empty())
	credits = int(data.get("credits", 0))
	cargo = {}
	for c in data.get("cargo", {}):
		cargo[c] = int(data["cargo"][c])


# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var top := -_half_height - 14.0

	# Shield + hull bars once damaged.
	if hull < max_hull or shields < max_shields:
		var w := clampf(hit_radius * 2.0, 50.0, 110.0)
		var pos := Vector2(-w / 2.0, top)
		if max_shields > 0.0:
			var spos := pos - Vector2(0, 7)
			var scol := Color(0.4, 1.0, 0.6) if is_neutral() else Color(1.0, 0.6, 0.3)
			draw_rect(Rect2(spos, Vector2(w, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(spos, Vector2(w * clampf(shields / max_shields, 0, 1), 4)), scol)
		draw_rect(Rect2(pos, Vector2(w, 6)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(pos, Vector2(w * clampf(hull / max_hull, 0, 1), 6)), Color(1.0, 0.3, 0.25))

	# Empire marker: a small chevron in the empire's colour.
	if empire != "":
		var ec := Galaxy.empire_color(empire)
		var y := -_half_height - 4.0
		draw_colored_polygon(PackedVector2Array([Vector2(-7, y - 6), Vector2(0, y), Vector2(7, y - 6), Vector2(0, y - 3)]), Color(ec, 0.9))

	# Lock-on brackets + ship class (red = hostile, yellow = neutral).
	if targeted:
		var s := hit_radius * 1.35 + 4.0 * sin(_time * 8.0)
		var l := 14.0
		var c := Color(1.0, 0.25, 0.2, 0.9)
		var label := display_name.to_upper()
		if is_neutral():
			var hostile := is_hostile_to_player()
			c = Color(1.0, 0.6, 0.2, 0.95) if hostile else Color(1.0, 0.9, 0.3, 0.95)
			label += "  ·  HOSTILE" if hostile else "  ·  NEUTRAL"
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p: Vector2 = corner * s
			draw_line(p, p - Vector2(corner.x * l, 0), c, 2.0)
			draw_line(p, p - Vector2(0, corner.y * l), c, 2.0)
		var font := ThemeDB.fallback_font
		var fs := Settings.fs("world", 13)
		draw_string(font, Vector2(-170, s + 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, 340, fs, c.lightened(0.2))
		# Role and cargo hold.
		var info := role.capitalize() if role != "" else ""
		if surrendered > 0.0:
			info += "  ·  SURRENDERED"
		if not cargo.is_empty():
			var parts := []
			for k in cargo:
				parts.append("%d %s" % [cargo[k], Items.display_name(k)])
			info += ("  ·  " if info != "" else "") + "Cargo: " + ", ".join(parts)
		elif role in ["trader", "miner"]:
			info += "  ·  hold empty"
		if info != "":
			draw_string(font, Vector2(-220, s + 22.0 + fs), info, HORIZONTAL_ALIGNMENT_CENTER, 440, maxi(Settings.MIN_FONT, fs - 1), Color(0.85, 0.9, 1.0, 0.85))
