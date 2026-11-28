class_name CosmosTraveller
extends CosmosNpc
## Someone on a world's roads (CosmosCaravans): a caravan's traders and its
## guards, a courier running between towns, pilgrims, a patrol - their empire's
## people (CosmosNpc.dress: its android, its weapons) - or a raider of the
## pirates' camps (the pirate android) come to rob them.
## The road's people walk to where their caravan wants them (`goal`: their place
## in its column, set every frame by CosmosCaravans); when something hostile
## comes near - a raider, a camp's pirate, a hunting beast, or you, if you've
## shot at them - the armed turn and fight it (their rifles' and bows' bolts,
## the labrys up close) and the unarmed run from it. The raiders go for the
## nearest traveller (their bolts land by chance, the further the less: their
## hits dealt here - CosmosBolt's enemy fire is aimed at you) and for you, if
## you're nearer. Hurt to nothing they drop (ko) and their loot with them
## (CosmosLoot). Town guards leave the friendly ones be (CosmosNpc._nearest_foe).

const RAIDER_DAMAGE := 8.0
const GUARD_DAMAGE := 14.0
const BOLT_SPEED := 150.0       # (CosmosBolt.SPEED: when a raider's shot lands)

var friendly := true            # (a raider's false)
var group: Dictionary = {}      # its caravan's (CosmosCaravans)
var goods := {}                 # what it carries: item id -> n (a trader's, a courier's...)
var empire := ""
var speed := 1.4                # m/s on the road
var goal := Vector3.INF         # (global) where its caravan wants it now
var threat: Node3D = null       # what it's fighting or running from
var _hits: Array = []           # (a raider's shots on their way: [s to go, target, damage])
var _look := 0.0
var _fire_t := 0.0
var _flee_t := 0.0
var _gone_t := 0.0              # (a raider's: how long it's had nothing to rob)


## One of the road's people: `kind` trader / guard / courier / pilgrim / raider.
func traveller(pl: CosmosPlanet, kind: String, emp: String, seed: int) -> void:
	planet = pl
	role = kind
	empire = emp
	_rng.seed = seed
	_fire = _rng.randf_range(0.4, 1.2)
	friendly = kind != "raider"
	if kind == "raider":
		model_id = "pirate"
		weapon = "rifle"
		label = "Raider"
		max_hp = 70.0
	else:
		model_id = people_id(emp, _rng)
		var ws := weapons_of(model_id)
		if kind == "guard" and not ws.is_empty():
			weapon = ws[_rng.randi() % ws.size()]
		elif kind == "trader" and not ws.is_empty() and _rng.randf() < 0.3:
			weapon = "rifle" if "rifle" in ws else ws[0]   # (now and then a trader who's armed)
		else:
			weapon = ""
		var who: String = {"trader": "trader", "guard": "caravan guard", "courier": "courier", "pilgrim": "pilgrim"}.get(kind, kind)
		label = "%s %s" % [Galaxy.EMPIRES.get(emp, {}).get("short", "Independent"), who]
		max_hp = 90.0 if kind == "guard" else 60.0
	hp = max_hp
	name = kind.capitalize()


func _ready() -> void:
	var id := model_id
	if not Stage3D.has_model(id):
		id = "player"
	if Stage3D.has_model(id):
		var model: Node3D = Stage3D._scene(id).instantiate()
		model.rotation.y = PI
		add_child(model)
		if id == "pirate" or id == "player":
			CosmosModels.apply(model, id)
		else:
			dress(model, id, empire, weapon)
		_anim = model.find_child("AnimationPlayer", true, false)
		Stage3D.loop_clips(_anim, id, ["walk", "guard", "idle", "gun_idle", "gun_walk", "run"])
	_play("gun_idle" if weapon != "" else "idle")


func hurt(dmg: float, from: Vector3) -> void:
	if dead:
		return
	# (shot by you? the bolt came from where you stand: the caravan turns on you)
	if friendly and cosmos and cosmos.walker and not group.is_empty():
		var w: Node3D = cosmos.walker
		var to_w: Vector3 = w.global_position - global_position
		var to_f := from - global_position
		if to_w.length() < 160.0 and to_f.length() > 0.2 and to_w.normalized().dot(to_f.normalized()) > 0.97:
			if not group.get("angry", false) and cosmos.get("hud"):
				cosmos.hud.flash("The %s turns on you!" % str(group.get("title", "caravan")), 3.0)
			group["angry"] = true
	hp -= dmg
	_play("hit", true)
	if hp <= 0.0:
		dead = true
		_play("ko", true)
		if not friendly and cosmos and cosmos.has_method("npc_died"):
			cosmos.npc_died(self)   # (a raider: one of yours, or the guards')
		return
	if weapon == "" or hp < max_hp * 0.25:
		_flee_t = 5.0


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if planet == null:
		return
	if dead:
		_dead_t += delta
		if _dead_t > 8.0:
			queue_free()
		return
	_land_hits(delta)
	var d := _lazy_step(delta)
	if d < 0.0:
		return
	_think(d)


## A raider's shots landing (on a traveller): by chance - the further, the less.
func _land_hits(delta: float) -> void:
	var i := 0
	while i < _hits.size():
		_hits[i][0] -= delta
		if _hits[i][0] <= 0.0:
			var t: Node3D = _hits[i][1]
			if is_instance_valid(t) and not t.get("dead"):
				t.hurt(float(_hits[i][2]), global_position)
			_hits.remove_at(i)
		else:
			i += 1


func _think(delta: float) -> void:
	var u := up()
	_look -= delta
	if _look <= 0.0:
		_look = 0.35
		threat = _pick_threat()
	if threat != null and (not is_instance_valid(threat) or threat.get("dead") or threat.get("downed")):
		threat = null
	_fire_t -= delta
	_flee_t -= delta
	var move := Vector3.ZERO
	var spd := speed
	var clip := ""
	var busy := _anim != null and _clip in ["hit", "fire", "cross"] and _anim.is_playing()
	if threat:
		var to := threat.global_position - global_position
		var flat := to - u * to.dot(u)
		var dist := flat.length()
		if weapon != "" and _flee_t <= 0.0:
			if dist > 0.1:
				facing = flat / dist
			if weapon == "axe":
				if dist > 2.0:
					move = facing
					spd = 4.5
					clip = "run"
				elif _fire_t <= 0.0:
					_fire_t = 1.1
					threat.hurt(18.0, global_position)
					_play("cross", true)
			else:
				var side := facing.cross(u) * (1.0 if (get_instance_id() % 2) == 0 else -1.0)
				if dist > 32.0:
					move = facing
					spd = 3.2
					clip = "gun_walk"
				elif dist < 9.0:
					move = -facing * 0.7 + side * 0.4
					clip = "gun_walk"
				if _fire_t <= 0.0 and not busy:
					_fire_t = (1.15 if weapon == "rifle" else 1.7) * _rng.randf_range(0.8, 1.25)
					_shoot(threat, dist)
		else:
			move = -flat.normalized() if dist > 0.1 else facing
			facing = move
			spd = 4.2
			clip = "run"
	if move == Vector3.ZERO and clip == "" and goal != Vector3.INF:
		var g := goal - global_position
		g -= u * g.dot(u)
		var gl := g.length()
		if gl > 0.5:
			move = g / gl
			spd = minf(speed * clampf(gl / 2.0, 0.6, 1.8), 4.5)
			if threat == null:
				facing = move
			clip = "run" if spd > 2.6 else ("gun_walk" if weapon != "" else "walk")
	if clip == "":
		clip = "gun_idle" if weapon != "" else "idle"
	if not busy:
		_play(clip)
	global_position += move * spd * delta
	var local := global_position - planet.global_position
	var dn := local.normalized()
	global_position = planet.global_position + dn * (planet.radius + maxf(planet.shape.height(dn), 0.0))
	if cosmos and cosmos.get("builds") and cosmos.builds.planet == planet:
		global_position += cosmos.builds.push_body(global_position, 0.45, false)
	facing = (facing - dn * facing.dot(dn)).normalized()
	if facing.length() < 0.5:
		facing = dn.cross(Vector3.RIGHT).normalized()
	global_basis = Basis.looking_at(facing, dn)


## A shot at `t`: a guard's bolt at its foe (it hurts what it strikes), a raider's at you
## (CosmosBolt's enemy fire) or at a traveller (it flies past; its hit, by chance, dealt here).
func _shoot(t: Node3D, dist: float) -> void:
	var u := up()
	var muzzle := global_position + u * 1.35 + facing * 0.7
	var tu: Vector3 = t.up() if t.has_method("up") else u
	var aim: Vector3 = t.global_position + tu * 0.9 - muzzle
	var spread := 0.01 + dist * 0.0005
	aim = aim.normalized() + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))
	var at_you: bool = cosmos != null and t == cosmos.walker
	if friendly and not at_you:
		var b := CosmosBolt.fire(cosmos, muzzle, aim, "player", GUARD_DAMAGE if weapon == "rifle" else 22.0)
		if weapon == "bow" and b:
			b.tint = Color(0.4, 0.95, 1.0)
	else:
		CosmosBolt.fire(cosmos, muzzle, aim, "enemy", RAIDER_DAMAGE if not friendly else DAMAGE)
		if not at_you and _rng.randf() < clampf(0.8 - dist * 0.012, 0.25, 0.8):
			_hits.append([dist / BOLT_SPEED, t, RAIDER_DAMAGE])
	_play("fire", true)


## What it fights or runs from now (or null): the nearest of what's hostile to it in reach.
func _pick_threat() -> Node3D:
	if cosmos == null:
		return null
	var best: Node3D = null
	var bd := INF
	var me := global_position
	var w: Node3D = cosmos.walker
	if friendly:
		var reach := 55.0 if weapon != "" else 26.0
		for x in cosmos.npcs:
			if not is_instance_valid(x) or x.get("dead") or x == self or x.get("friendly"):
				continue
			if x.get("planet") != planet or x.get("dungeon") != null or x.get("in_cave"):
				continue
			var dd: float = x.global_position.distance_to(me)
			if dd < reach and dd < bd:
				bd = dd
				best = x
		for c in cosmos.creatures:
			if not is_instance_valid(c) or c.dead or c.kind.get("temper") != "predator":
				continue
			var dd: float = c.global_position.distance_to(me)
			if dd < minf(reach, 32.0) and dd < bd:
				bd = dd
				best = c
		if w and group.get("angry", false) and w.get("deck") == null and not w.get("downed"):
			var dd: float = w.global_position.distance_to(me)
			if dd < reach and dd < bd:
				best = w
		return best
	# A raider: the nearest traveller - or you, if you're nearer (or there's no one else).
	for x in cosmos.npcs:
		if not is_instance_valid(x) or x.get("dead") or not x.get("friendly") or x.get("planet") != planet:
			continue
		var dd: float = x.global_position.distance_to(me)
		if dd < 90.0 and dd < bd:
			bd = dd
			best = x
	if w and w.get("deck") == null and not w.get("downed") and w.get("planet") == planet:
		var dd: float = w.global_position.distance_to(me)
		if dd < 40.0 and dd < bd + 6.0:
			best = w
	return best
