class_name CosmosNpc
extends Node3D
## A pirate android on a planet in the 3D game (stage 3): its actual model
## (art/pirate_3d - rendered from Blender's pirate.blend; its cel shaders and
## clips: walk, guard, gun_idle, gun_walk, fire, hit, ko). It guards its camp
## - pacing about it - until you come within SIGHT: then it raises its rifle,
## keeps 14-26 m from you, strafing, and fires bolts (CosmosBolt, a little
## wide - the further, the wider). Hit, it flinches; at no health it drops
## (ko) and is gone a few seconds later.
## Or a town's citizen (citizen_of): the automaton's model in its empire's
## colours (CosmosModels' recolouring), walking between the town's open
## spots, pausing, turning to look at you when you come close.

const SIGHT := 48.0
const SPEED := 3.0
const FIRE_EVERY := 1.15
const DAMAGE := 7.0

var _turn := SmoothTurn.new(5.0, 4.5, 9.0)   # (a citizen turns unhurried, smoothly)
var planet: CosmosPlanet
var cosmos: Node
var camp := Vector3.ZERO         # planet-local
var hp := 80.0
var max_hp := 80.0
var dead := false
var reach := 0.55
var facing := Vector3.FORWARD
var _goal := Vector3.ZERO
var _t := 0.0
var _fire := 0.0
var _anim: AnimationPlayer
var _clip := ""
var _strafe := 1.0
var _dead_t := 0.0
var _rng := RandomNumberGenerator.new()
var label := "Pirate android"
var town: CosmosTown = null      # (a citizen's)
var _tl := Vector3.ZERO          # (a citizen's place, town-local)
var _wait := 0.0


var model_id := "pirate"
var weapon := ""                 # (a townsperson's: rifle, bow, axe - or none)
var pid := ""                   # a town's resident: their record (People)
var role := "pirate"             # pirate, guard (armed townsfolk), kilon
var _foe: Node3D = null
var _scan := 0.0
const WEAPON_HIDE := {"rifle": ["MIN_Bow", "MIN_Axe"], "bow": ["MIN_Rifle", "MIN_Axe"], "axe": ["MIN_Rifle", "MIN_Bow"]}
const WEAPON_NAME := {"rifle": "laser rifle", "bow": "laser bow", "axe": "labrys"}


## The empires' people: each its own android (art/<id>_3d - built in Blender,
## external/blender/automaton/<id>.py): the Minoans' triceratops and palace
## guard, Athens' horned owl-eyed theropod, Sparta's crested tyrant, Mycenae's
## gold-domed mask, Ionia's lapis duck-bill with its long crest, the Cyclades'
## pale idol; the Sea Peoples' pirate.
const PEOPLE := {"minoa": "minoan", "athens": "athenian", "sparta": "spartan", "mycenae": "mycenaean", "ionia": "ionian", "cyclades": "cycladic",
	"pirates": "pirate"}
const WEAPONS := ["MIN_Rifle", "MIN_Bow", "MIN_Axe"]


## Which model one of `empire`'s people wears (an empire without its own yet:
## the Minoan android, recoloured - `dress`; the independents: anyone's).
static func people_id(empire: String, rng: RandomNumberGenerator) -> String:
	var emp := empire
	if not PEOPLE.has(emp):
		emp = Galaxy.MAJOR[rng.randi() % Galaxy.MAJOR.size()]
	if emp == "minoa" and rng.randf() < 0.35 and Stage3D.has_model("guard"):
		return "guard"
	var id: String = PEOPLE[emp]
	return id if Stage3D.has_model(id) else "minoan"


## The weapons `id`'s model can carry.
static func weapons_of(id: String) -> Array:
	return ["rifle", "bow", "axe"] if id == "minoan" else (["rifle"] if id in ["guard", "athenian", "spartan", "mycenaean", "ionian", "cycladic"] else [])


## Dresses a person's model (`id`, just instantiated): its parts merged into one
## draw, `weapon` shown ("": unarmed - none of them), and - the Minoan android
## standing in for another empire's - that empire's colours.
static func dress(model: Node3D, id: String, empire: String, weapon := "") -> void:
	var hide: Array = WEAPONS if weapon == "" else WEAPON_HIDE.get(weapon, [])
	var recolor: Array = []
	if id == "minoan" and empire != "minoa" and PEOPLE.has(empire):
		var L: Array = CosmosTown.LOOKS.get(empire, CosmosTown.LOOKS[""])
		var main: Array = L[CosmosTown.WALL]
		var acc: Array = L[CosmosTown.RED]
		recolor = [Color(main[0], main[1], main[2], 0.85), Color(acc[0], acc[1], acc[2], 1.0), Color(Galaxy.empire_color(empire), 0.8)]
	CosmosModels.apply(model, id, recolor, hide)


var dungeon: CosmosDungeon = null   # (the dead's: a skeleton's, a demon's)
var in_cave := false                # (the dead of a cave in the ground - PlanetShape.caves: walking its carved floor)
var scale_k := 1.0


## One of a dungeon's dead: "skeleton" (a sword and a shield), "demon"
## (claws and fire), `boss`: the demon lord by its chest.
func foe_of(d: CosmosDungeon, seed: int, kind: String, boss := false) -> void:
	dungeon = d
	planet = d.planet
	_as_foe(seed, kind, boss)


## One of a cave's dead (a cave in the planet's ground: Cosmos._cave_wake).
func cave_foe(pl: CosmosPlanet, seed: int, kind: String, boss := false) -> void:
	in_cave = true
	planet = pl
	_as_foe(seed, kind, boss)


func _as_foe(seed: int, kind: String, boss: bool) -> void:
	_rng.seed = seed
	role = kind
	model_id = kind
	if kind == "skeleton":
		label = "Skeleton warrior"
		max_hp = 60.0
	else:
		label = "Demon lord" if boss else "Demon"
		max_hp = 600.0 if boss else 150.0
		scale_k = 1.7 if boss else 1.25
	hp = max_hp
	reach = 0.55 * scale_k
	name = label.replace(" ", "_")
	_fire = _rng.randf_range(0.5, 1.5)


## One of a town's people: in a Minoan town its palace guards and its
## androids (laser rifle, laser bow or labrys), in another empire's the
## android in that empire's colours; `kind` "kilon": Kilon Alios.
func citizen_of(t: CosmosTown, seed: int, kind := "") -> void:
	town = t
	planet = t.planet
	_rng.seed = seed
	_wait = _rng.randf_range(0.0, 3.0)
	var empire := str(t.site["empire"])
	if kind in ["vendor", "courier", "pilot"]:   # (the city's people by its landing field: CosmosSandbox)
		role = kind
		model_id = people_id(empire, _rng)
		weapon = ""
		label = str(CosmosSandbox.ROLES[kind]).capitalize()
		name = kind.capitalize()
		return
	role = "guard"
	name = "Citizen"
	model_id = people_id(empire, _rng)
	var ws := weapons_of(model_id)
	weapon = ws[_rng.randi() % ws.size()] if not ws.is_empty() else ""
	if model_id == "guard":
		label = "Minoan palace guard"
		return
	label = "%s android (%s)" % [Galaxy.EMPIRES.get(empire, {}).get("short", "Independent"), WEAPON_NAME.get(weapon, "unarmed")]


func setup(pl: CosmosPlanet, camp_local: Vector3, seed: int) -> void:
	planet = pl
	camp = camp_local
	_rng.seed = seed
	_fire = _rng.randf_range(0.5, 1.5)
	name = "Pirate"


func _ready() -> void:
	var id := model_id
	if not Stage3D.has_model(id):
		id = "player"
	if Stage3D.has_model(id):
		var model: Node3D = Stage3D._scene(id).instantiate()
		model.rotation.y = PI
		model.scale = Vector3.ONE * scale_k
		add_child(model)
		if dungeon or in_cave:
			CosmosModels.apply(model, id)
		elif town:
			dress(model, id, str(town.site["empire"]), weapon if weapon != "" else "rifle")
			_tl = town.to_local(global_position) if is_inside_tree() else Vector3.ZERO
		else:
			CosmosModels.apply(model, id)   # (two draws: its parts merged, colours in the vertices)
		_anim = model.find_child("AnimationPlayer", true, false)
		Stage3D.loop_clips(_anim, id, ["walk", "guard", "idle", "gun_idle", "gun_walk", "run", "sit"])   # (a whole cycle long: no jump at the seam)
	else:
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.9
		cap.mesh = cm
		cap.position.y = 0.95
		add_child(cap)
	_play("guard" if dungeon or in_cave else (("gun_idle" if weapon != "" else "idle") if town else "guard"))


## Its `facing` in a town's or a dungeon's own frame (not the world's): not turned
## with the world's spin by Cosmos._spin_carry (its place comes from that frame).
func spin_local() -> bool:
	return is_instance_valid(town) or is_instance_valid(dungeon)


func up() -> Vector3:
	if dungeon:
		return dungeon.global_basis.y
	return (global_position - planet.global_position).normalized()


func hurt(dmg: float, _from: Vector3) -> void:
	if dead:
		return
	hp -= dmg
	_play("hit", true)
	_t = 0.0
	if hp <= 0.0:
		dead = true
		_play("ko", true)
		if cosmos:
			cosmos.npc_died(self)


## Far from you (LAZY_FAR m) it thinks one frame in three - the time it
## missed added in (at hundreds of frames a second that's still smooth); near, every frame.
const LAZY_FAR := 35.0
var _lazy := 0
var _lazy_dt := 0.0
var _anim_manual := false


func _lazy_step(delta: float) -> float:
	_lazy_dt += delta
	var f: Node3D = cosmos.focus() if cosmos and cosmos.has_method("focus") else null
	var far: bool = f != null and f.global_position.distance_squared_to(global_position) > LAZY_FAR * LAZY_FAR
	if _anim and far != _anim_manual:   # (its animation too: far, posed a frame in three)
		_anim_manual = far
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if far else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if far:
		_lazy += 1
		if _lazy % 3 != 0:
			return -1.0
	var d := minf(_lazy_dt, 0.15)
	_lazy_dt = 0.0
	if _anim_manual and _anim:
		_anim.advance(d)
	return d


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if planet == null:
		return
	if dead:
		_dead_t += delta
		if _dead_t > 6.0:
			queue_free()
		return
	if ride != null:   # (a local pilot off to his hired ship: across the field, up its ramp, to its pilot's seat)
		if _crew == 4:
			_lazy_step(delta)   # (seated: a child of its insides, carried with it - only its clip to pose)
			return
		var d := _lazy_step(delta)
		if d >= 0.0:
			_to_ride(d)
		elif _crew == 1 and _dl != Vector3.INF and is_instance_valid(ride):
			global_position = ride.to_global(_dl)   # (a frame he doesn't think: still where he was by it)
		return
	if _off in [1, 4]:   # (a landing field's pilot on his ship's ramp: down it, or back up it)
		if not is_instance_valid(off_ship):
			_off = 2 if _off == 1 else 5
			return
		var d := _lazy_step(delta)
		if d >= 0.0:
			_walk_ramp(d)
		else:
			global_position = off_ship.to_global(_dl)
		return
	if _off == 5:
		return   # (back aboard: gone with it)
	if town:
		var d := _lazy_step(delta)
		if d >= 0.0:
			_citizen(d)
		return
	if dungeon:
		_dungeon_fight(delta)
		return
	if in_cave:
		_cave_fight(delta)
		return
	var u := up()
	var me := planet.to_local(global_position)   # (planet-local, as its camp: the world turns)
	var player: Node3D = cosmos.walker if cosmos else null
	var to := Vector3.ZERO
	var pd := INF
	if player and not player.get("downed"):
		to = player.global_position - global_position
		pd = to.length()
	var move := Vector3.ZERO
	var busy := _anim != null and _clip in ["hit", "fire"] and _anim.is_playing()
	if pd < SIGHT:
		var flat := to - u * to.dot(u)
		facing = flat.normalized()
		var side := facing.cross(u) * _strafe
		var want := 0.0
		if pd > 26.0:
			want = 1.0
		elif pd < 14.0:
			want = -1.0
		move = facing * want + side * 0.6
		_t -= delta
		if _t <= 0.0:
			_t = _rng.randf_range(1.5, 3.5)
			_strafe = -_strafe
		_fire -= delta
		if _fire <= 0.0 and not busy:
			_fire = FIRE_EVERY * _rng.randf_range(0.8, 1.3)
			var muzzle := global_position + u * 1.35 + facing * 0.7
			var aim: Vector3 = player.global_position + player.up() * 1.1 - muzzle
			var spread := 0.008 + pd * 0.0004
			aim = aim.normalized() + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))
			CosmosBolt.fire(cosmos, muzzle, aim, "enemy", DAMAGE)
			_play("fire", true)
		elif not busy:
			_play("gun_walk" if move.length() > 0.3 else "gun_idle")
	else:
		# On guard: pacing about the camp.
		_t -= delta
		if _t <= 0.0:
			_t = _rng.randf_range(3.0, 7.0)
			var t := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _rng.randf() * TAU)
			_goal = camp + planet.dir_local(t) * _rng.randf_range(3.0, 14.0)
		var g := planet.dir_world(_goal - me)
		g -= u * g.dot(u)
		if g.length() > 1.0:
			move = g.normalized() * 0.6
			facing = g.normalized()
		if not busy:
			_play("walk" if move.length() > 0.1 else "guard")
	global_position += move * SPEED * delta
	var local := global_position - planet.global_position
	var d := local.normalized()
	global_position = planet.global_position + d * (planet.radius + maxf(planet.shape.height(planet.dir_local(d)), 0.0))
	if cosmos and cosmos.get("builds") and cosmos.builds.planet == planet:   # (kept out of what you've built - an unlocked door pushed open)
		global_position += cosmos.builds.push_body(global_position, 0.45, true)
	facing = (facing - d * facing.dot(d)).normalized()
	if facing.length() < 0.5:
		facing = d.cross(Vector3.RIGHT).normalized()
	global_basis = Basis.looking_at(facing, d)


## A citizen's day: to a spot, a pause, the next; facing you when you're near.
## Armed, it takes on the pirates and the hunting beasts that come near (rifle
## and bow fire; the labrys closes in and strikes). Kilon Alios stays where he
## stands, watching you.
const FAR_TOWN := 110.0


func _citizen(delta: float) -> void:
	if not is_instance_valid(town) or not town.built:
		return
	_tl = town.to_local(global_position)
	_tl.y = 0.0
	# (across town, out past FAR_TOWN: not drawn, not animated - they walk on unseen)
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > FAR_TOWN * FAR_TOWN
	if visible == far:
		visible = not far
		if _anim:
			_anim.active = not far
	var me: Node3D = cosmos.walker if cosmos else null
	var move := Vector3.ZERO
	var speed := 1.3
	var near := me != null and me.global_position.distance_to(global_position) < (9.0 if role in ["vendor", "courier", "pilot"] else 3.5)
	var armed := weapon != ""
	_scan -= delta
	if role == "guard" and _scan <= 0.0:
		_scan = 0.4
		_foe = _nearest_foe(45.0)
	if role == "guard" and _foe and is_instance_valid(_foe) and not _foe.get("dead"):
		var to: Vector3 = town.to_local(_foe.global_position) - _tl
		to.y = 0.0
		facing = to.normalized() if to.length() > 0.1 else facing
		_fire -= delta
		if weapon == "axe":
			if to.length() > 2.0:
				move = to.normalized()
				speed = 4.5
				_play("run")
			elif _fire <= 0.0:
				_fire = 1.1
				_foe.hurt(18.0, global_position)
				_play("cross", true)
		else:
			if _fire <= 0.0:
				_fire = (1.0 if weapon == "rifle" else 1.6) * _rng.randf_range(0.85, 1.2)
				var muzzle := global_position + up() * 1.35 + (town.global_basis * facing) * 0.7
				var aim: Vector3 = _foe.global_position + (_foe.up() if _foe.has_method("up") else Vector3.UP) * 0.8 - muzzle
				var b := CosmosBolt.fire(cosmos, muzzle, aim, "player", 14.0 if weapon == "rifle" else 22.0)
				if weapon == "bow":
					b.tint = Color(0.4, 0.95, 1.0)
				_play("fire", true)
			elif not (_clip == "fire" and _anim and _anim.is_playing()):
				_play("gun_idle")
	elif role == "captain" and _off == 3 and (not is_instance_valid(off_ship) or (not (off_ship.get("hire") as Dictionary).is_empty() and off_ship.call("hire_state") != "wait")):
		_off = 2   # (his ship gone without him: one of the town's people a while yet)
		off_ship = null
		_off_goal = Vector3.INF
	elif role == "captain" and _off == 3:   # (his time ashore up: back through the town to his ship's ramp)
		move = _ashore_step(_ramp_foot(), delta)
		speed = CREW_RUN if _off_hurry else CREW_SPEED
		if move == Vector3.ZERO:
			if is_instance_valid(off_ship) and (off_ship.get("hire") as Dictionary).is_empty():
				_off = 4   # (up his ramp, in)
				_dl = off_ship.to_local(global_position)
				var e := _ramp_ends(off_ship)
				_off_path = [e[1], e[0]]
			_play("idle")
		else:
			_play("run" if _off_hurry else "walk")
	elif near:
		var to: Vector3 = town.to_local(me.global_position) - _tl
		to.y = 0.0
		if to.length() > 0.1:
			facing = _turn.step(facing, to, Vector3.UP, delta)   # (round smoothly - never snapped)
		_play("gun_idle" if armed else "idle")
	elif role == "captain":   # (ashore: to where he spends his time - the square, a door, the colonnade - and there a while)
		move = _ashore_step(stay_at, delta)
		_play("walk" if move != Vector3.ZERO else "idle")
	elif role in ["vendor", "courier", "pilot"] or _wait > 0.0:
		_wait -= delta
		_play("gun_idle" if armed else "idle")
	else:
		var g := _goal - _tl
		g.y = 0.0
		_t -= delta
		if g.length() < 1.0 or _t <= 0.0:
			_goal = _next_spot() + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
			_t = 25.0
			_wait = _rng.randf_range(1.0, 6.0) if _rng.randf() < 0.6 else 0.0
		else:
			move = g.normalized()
			facing = _turn.step(facing, move, Vector3.UP, delta)
			_play("gun_walk" if armed else "walk")
			_stuck_t += delta
			if _stuck_t > 2.0:   # (held up - a post, a wall, someone in the way: not walking on the spot - elsewhere)
				if _tl.distance_to(_stuck_at) < 0.5:
					_t = 0.0
				_stuck_t = 0.0
				_stuck_at = _tl
	_tl += move * speed * delta
	_tl += town.push(_tl, 0.4)
	var r: float = town.site["r"]
	_tl.x = clampf(_tl.x, -r, r)
	_tl.z = clampf(_tl.z, -r, r)
	global_position = town.to_global(_tl)
	var u := town.global_basis.y
	var f := town.global_basis * facing
	f = (f - u * f.dot(u)).normalized()
	if f.length() > 0.5:
		global_basis = Basis.looking_at(f, u)


## Where to walk next in its town: one of its spots near (the next along a street,
## mostly - its spots are its streets', a few apart), not where it stands.
func _next_spot() -> Vector3:
	var best: Vector3 = town.spots[_rng.randi() % town.spots.size()]
	var bd := INF
	for k in 6:
		var p: Vector3 = town.spots[_rng.randi() % town.spots.size()]
		var d := Vector2(p.x - _tl.x, p.z - _tl.z).length()
		if d > 5.0 and d < bd:
			bd = d
			best = p
	return best


## A town's local pilot hired (CosmosSandbox._hire): when his ship is down on
## the field, its ramp down (CosmosNpcShip._hire_fly "wait"), he walks to it -
## round its hull to the ramp's foot, up the ramp (from there a child of its
## insides, CosmosNpcInterior, in its space - no longer one of the town's
## people), along the deck to the pilot's seat at its consoles, and sits there,
## carried with the ship wherever it flies. Its ship climbs only once he's
## seated (or after CosmosNpcShip.PILOT_WAIT).
var ride: Node3D = null          # (a local pilot's: the ship he's hired out with)
var _crew := 0                   # 1 across the ground, 2 up the ramp and along the deck, 3 into the seat, 4 seated
var _dl := Vector3.ZERO          # (aboard: where he is in its insides' space)
var _sit_t := 0.0
var _from := Vector3.ZERO
var _path: Array = []            # (aboard: the deck's points to walk through, its space)
const CREW_SPEED := 1.6          # m/s walking to it
const CREW_RUN := 4.2            # (you aboard already, waiting: he runs)


func board_ride(s: Node3D) -> void:
	if role == "captain" and _off in [2, 3]:   # (a landing field's pilot, in the town: back through it to his ship's ramp first)
		if _off == 2:
			go_back(true)
		if not is_instance_valid(town) or Vector2(_tl.x - _ramp_foot().x, _tl.z - _ramp_foot().z).length() > 1.2:
			return
		_off = 0
	ride = s
	process_priority = 4   # (after the ships each frame: moved with his, never a frame behind)
	if _crew == 0:
		_crew = 1
		_dl = Vector3.INF   # (where he is by it: taken on his first step)


## Seated at the consoles (or at the controls of a cabin with no seat).
func seated() -> bool:
	return _crew == 4


## Off the ride before he boarded (it left without him): one of the town's people again.
func drop_ride() -> void:
	if _crew <= 1:
		ride = null
		_crew = 0
		process_priority = 0


func _to_ride(delta: float) -> void:
	if not is_instance_valid(ride):
		ride = null
		if _crew >= 2:
			queue_free()   # (its ship gone with him aboard)
		_crew = 0
		return
	var inn: CosmosNpcInterior = ride.get("interior")
	if inn == null:
		inn = ride.call("make_interior")
	if _anim and not visible:
		visible = true
		_anim.active = true
	var hurry: bool = cosmos != null and cosmos.walker != null and cosmos.walker.get("deck") == inn
	var speed := CREW_RUN if hurry else CREW_SPEED
	var clip := "run" if hurry else "walk"
	if _crew == 1:   # (across the field, round its hull, to the foot of its ramp - in its space: carried with its world as it turns)
		var foot: Vector3 = inn.foot if inn and inn.built else Vector3(0, -float(ride.call("rest_height")), 0)
		if _dl == Vector3.INF:
			_dl = ride.to_local(global_position)
		var go := _ground_goal(_dl, foot, inn)
		var to := go - _dl
		to.y = 0.0
		if Vector2(_dl.x - foot.x, _dl.z - foot.z).length() < 0.35:
			if inn and inn.ok and float(ride.get("_ramp_k")) > 0.99:   # (up the ramp: aboard from here, in its space)
				_aboard(inn)
				return
			_play("idle")   # (its insides not made yet, or the ramp not down: he waits at its foot)
		elif to.length() > 0.001:
			var step := to.normalized() * minf(speed * delta, to.length())
			_dl += step
			_play(clip)
			global_basis = Basis.looking_at(ride.global_basis * step.normalized(), ride.global_basis.y)
		_dl.y = foot.y
		global_position = ride.to_global(_dl)
		return
	if _crew == 2:   # (up the ramp, along the deck, through its doorways, round beside the pilot's seat)
		if not inn.ramp_open():
			_dl.z = minf(_dl.z, inn.z_aft - 0.4)   # (its ramp up behind him)
		while not _path.is_empty() and Vector2(_dl.x - _path[0].x, _dl.z - _path[0].z).length() < 0.05:
			_path.pop_front()
		if _path.is_empty():
			if inn.pilot_pos == Vector3.INF:   # (no seat in a cabin this small: he stands at its controls)
				_crew = 4
				transform = Transform3D(Basis(), Vector3(_dl.x, inn.floor_y(_dl), _dl.z))
				_play("idle")
				return
			_crew = 3
			_sit_t = 0.0
			_from = _dl
			return
		var to: Vector3 = _path[0] - _dl
		to.y = 0.0
		var step := to.normalized() * minf(speed * delta, to.length())
		_dl += step
		_dl.y = inn.floor_y(_dl)
		transform = Transform3D(Basis.looking_at(step.normalized(), Vector3.UP), _dl)
		_play(clip)
		return
	# Into the seat: a step across into it from beside it, turning to the consoles, sitting down.
	_sit_t = minf(_sit_t + delta / 0.8, 1.0)
	var k := smoothstep(0.0, 1.0, _sit_t)
	_dl = _from.lerp(inn.pilot_pos, k)
	_dl.y = inn.floor_y(_dl)
	var turn := Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	transform = Transform3D(turn.slerp(Basis(), smoothstep(0.0, 1.0, minf(k * 1.6, 1.0))), _dl)
	_play("sit" if k > 0.35 else "idle")
	if _sit_t >= 1.0:
		_crew = 4
		inn.pilot_seat["who"] = self
		transform = Transform3D(Basis(), inn.pilot_pos)


## The next point of his walk to the ramp's foot (ship space): out to the side
## of its hull if he's beside or ahead of it, back past its stern, in to the foot.
func _ground_goal(l: Vector3, foot: Vector3, inn: CosmosNpcInterior) -> Vector3:
	var hb: AABB = ride.call("_hull_box")
	var side := maxf(absf(hb.position.x), absf(hb.end.x)) + 2.0
	var aft := foot.z + 2.5
	var sx := 1.0 if l.x >= 0.0 else -1.0
	var hw: float = inn.ramp_hw if inn and inn.built else 1.2
	if l.z > foot.z - 0.2 and absf(l.x - foot.x) < hw * 0.6:
		return Vector3(foot.x, foot.y, foot.z)   # (behind it, in line with its ramp: straight in)
	if l.z > aft - 0.3:
		return Vector3(foot.x, foot.y, aft)   # (behind its stern: across, in line with the ramp)
	if absf(l.x) < side - 0.3:
		return Vector3(sx * side, foot.y, l.z)   # (under or ahead of it: out to its side)
	return Vector3(sx * side, foot.y, aft)   # (along its side, back past the stern)


func _aboard(inn: CosmosNpcInterior) -> void:
	_crew = 2
	if cosmos:
		cosmos.citizens.erase(self)   # (no longer the town's: its field may get a new pilot once his ship's gone)
	reparent(inn, true)
	_dl = inn.to_local(global_position)
	_dl.x = clampf(_dl.x, -inn.ramp_hw + 0.4, inn.ramp_hw - 0.4)
	# (his way: in through the door at the ramp's top, along the middle of the deck - its
	# doorways all on it - to behind the pilot's seat, round its left side, beside it)
	_path = [Vector3(0, 0, inn.z_aft - 0.6)]
	if inn.pilot_pos == Vector3.INF:
		_path.append(Vector3(0, 0, inn.z_fore + 1.2))
	else:
		var sz := inn.pilot_pos.z
		var sx := -clampf(inn._hw_at(sz) - 1.15, 0.68, 0.95)   # (clear of its arms, and of the consoles along the walls)
		_path.append_array([Vector3(0, 0, sz + 0.75), Vector3(sx, 0, sz + 0.75), Vector3(sx, 0, sz)])
	if _anim_manual and _anim:   # (aboard, near you: posed every frame)
		_anim_manual = false
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


## A dungeon's dead: they come for you when you're near (in its rooms), the
## skeletons with their swords, the demons hurling fire from afar and clawing
## up close.
func _dungeon_fight(delta: float) -> void:
	if not is_instance_valid(dungeon) or not dungeon.built:
		return
	_tl = dungeon.to_local(global_position)
	var me: Node3D = cosmos.walker if cosmos else null
	var to := Vector3.ZERO
	var d := INF
	if me and me.get("deck") == null and me.get("planet") == dungeon.planet and not me.get("downed"):
		to = dungeon.to_local(me.global_position) - _tl
		if absf(to.y) < 3.0:   # (in its rooms with it - not up on the ground over them)
			to.y = 0.0
			d = to.length()
	# (rooms away, behind its walls: not drawn, not animated - nor moving, it waits)
	var far := d > 36.0 * scale_k
	if visible == far:
		visible = not far
		if _anim:
			_anim.active = not far
	if far:
		return
	var move := Vector3.ZERO
	var speed := 1.0
	var demon := role == "demon"
	_fire -= delta
	var busy := _anim != null and _clip in ["jab", "cross", "hook", "hit"] and _anim.is_playing()
	if d < (30.0 if scale_k > 1.5 else 22.0):
		facing = to.normalized() if d > 0.1 else facing
		var hit_at := 1.7 * scale_k
		if d > hit_at:
			move = facing
			speed = 3.9 if demon else 3.3
			if demon and d > 5.0 and _fire <= 0.0:
				_fire = _rng.randf_range(2.2, 3.2)
				var muzzle := global_position + up() * 1.6 * scale_k + (dungeon.global_basis * facing) * 0.6 * scale_k
				var aim: Vector3 = me.global_position + me.up() * 1.0 - muzzle
				var b := CosmosBolt.fire(cosmos, muzzle, aim, "enemy", 12.0 * (2.0 if scale_k > 1.5 else 1.0))
				b.tint = Color(1.0, 0.45, 0.1)
				_play("cross", true)
			elif not busy:
				_play("run")
		else:
			if _fire <= 0.0:
				_fire = 1.1 if demon else 1.3
				me.hurt((16.0 if demon else 10.0) * (2.0 if scale_k > 1.5 else 1.0), self)
				_play(["jab", "cross", "hook"][_rng.randi() % 3], true)
			elif not busy:
				_play("guard")
	elif not busy:
		_play("guard")
	_tl += move * speed * delta
	_tl += dungeon.push(_tl, 0.4 * scale_k)
	_tl.y = dungeon.floor_top(_tl + Vector3(0, 0.05, 0))   # (up a step at most, like you)
	global_position = dungeon.to_global(_tl)
	var u := dungeon.global_basis.y
	var f := dungeon.global_basis * facing
	f = (f - u * f.dot(u)).normalized()
	if f.length() > 0.5:
		global_basis = Basis.looking_at(f, u)


## A cave's dead: as a dungeon's (they come for you when you're near, the
## skeletons' swords, the demons' fire and claws), on the planet's carved
## ground - its floor, kept out of its walls; out of sight, still.
func _cave_fight(delta: float) -> void:
	var me: Node3D = cosmos.walker if cosmos else null
	var u := up()
	var to := Vector3.ZERO
	var d := INF
	var far := true
	if me and me.get("deck") == null and me.get("planet") == planet and not me.get("downed"):
		to = me.global_position - global_position
		far = to.length() > 40.0 * scale_k
		var vd := to.dot(u)
		if absf(vd) < 3.5 * scale_k:   # (about its level: a passage above or below isn't the way to you)
			to -= u * vd
			d = to.length()
	if visible == far:
		visible = not far
		if _anim:
			_anim.active = not far
	if far:
		return
	var move := Vector3.ZERO
	var speed := 1.0
	var demon := role == "demon"
	_fire -= delta
	var busy := _anim != null and _clip in ["jab", "cross", "hook", "hit"] and _anim.is_playing()
	if d < (30.0 if scale_k > 1.5 else 22.0):
		facing = to.normalized() if d > 0.1 else facing
		if d > 1.7 * scale_k:
			move = facing
			speed = 3.9 if demon else 3.3
			if demon and d > 5.0 and _fire <= 0.0:
				_fire = _rng.randf_range(2.2, 3.2)
				var muzzle := global_position + u * 1.6 * scale_k + facing * 0.6 * scale_k
				var b := CosmosBolt.fire(cosmos, muzzle, me.global_position + me.up() * 1.0 - muzzle, "enemy", 12.0 * (2.0 if scale_k > 1.5 else 1.0))
				b.tint = Color(1.0, 0.45, 0.1)
				_play("cross", true)
			elif not busy:
				_play("run")
		else:
			if _fire <= 0.0:
				_fire = 1.1 if demon else 1.3
				me.hurt((16.0 if demon else 10.0) * (2.0 if scale_k > 1.5 else 1.0), self)
				_play(["jab", "cross", "hook"][_rng.randi() % 3], true)
			elif not busy:
				_play("guard")
	elif not busy:
		_play("guard")
	var sh := planet.shape
	var local := planet.to_local(global_position) + planet.dir_local(move * speed * delta)   # (planet-local: the carved ground's frame)
	var ul := local.normalized()
	for hgt: float in [0.55, 1.5]:   # (its walls: the knees and the head kept out of them, along the ground)
		var pt: Vector3 = local + ul * hgt * scale_k
		var mv: Vector3 = sh.push_out(pt, 0.4 * scale_k) - pt
		local += mv - ul * mv.dot(ul)
	local = local.normalized() * (planet.radius + sh.floor_below(local))
	global_position = planet.to_global(local)
	u = planet.dir_world(local.normalized())
	var f := (facing - u * facing.dot(u)).normalized()
	if f.length() > 0.5:
		facing = f
		global_basis = Basis.looking_at(f, u)


## The nearest pirate or hunting beast within `reach` m.
func _nearest_foe(reach: float) -> Node3D:
	var best: Node3D = null
	var bd := reach
	for list in [cosmos.npcs, cosmos.creatures]:
		for x in list:
			if not is_instance_valid(x) or x.get("dead") or x == self:
				continue
			if x.get("friendly"):
				continue   # (roads: the travellers - CosmosTraveller - aren't the town's foes; their raiders are)
			if x is CosmosCreature and (x as CosmosCreature).kind.get("temper") != "predator":
				continue
			var d: float = x.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = x
	return best


func _play(clip: String, restart := false) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if clip != _clip or restart:
		_anim.play(clip, 0.3)   # (cross-faded a third of a second: no jump to the new pose)
		if restart:
			_anim.seek(0.0, true)
		_clip = clip


# --- A landing field's pilot (CosmosLandingField) ---------------------------------------

## Down his ship's ramp from inside its door into the town (`ashore`: in it already,
## where he spends his time), there a while, back to it and up the ramp (go_back) - or,
## hired, to its pilot's seat (board_ride). His walk through the town: the spots of its
## streets one after another toward where he's going (_route), round what's in the way.
var off_ship: Node3D = null      # (his ship on its pad)
var stay_at := Vector3.ZERO      # (town-local: where he spends his time ashore)
var _off := 0                    # 1 down its ramp, 2 ashore, 3 back to its ramp's foot, 4 up it, 5 aboard (gone)
var _off_path: Array = []        # (on the ramp: ship-space points; ashore: town-local spots on his way)
var _off_goal := Vector3.INF
var _off_end := Vector3.ZERO     # (where his walk ends: his goal, or the nearest the streets go to it)
var _off_hurry := false
var _stuck_t := 0.0
var _stuck_at := Vector3.ZERO


func leave_ship(s: Node3D, ashore := false) -> void:
	off_ship = s
	process_priority = 4   # (after the ships: moved with his, never a frame behind)
	_off_goal = Vector3.INF
	if ashore:   # (in the town already: where he spends his time - or as near as its streets go)
		_off = 2
		if is_instance_valid(town):
			var entry := Vector3(float(CosmosTown.layout(str(town.site.get("kind", "")))["half"]) + 3.0, 0, town.to_local(s.global_position).z)
			var way := _route(entry, stay_at)
			if not way.is_empty() and not _clear(way[way.size() - 1], stay_at):
				stay_at = way[way.size() - 1]
			_tl = stay_at
			global_position = town.to_global(stay_at)
		return
	_off = 1
	var e := _ramp_ends(s)
	_off_path = [e[1], e[2], e[3]]
	_dl = e[0]
	global_position = s.to_global(_dl)


## Back to his ship (his time ashore up - or hired: `hurry`, he runs).
func go_back(hurry := false) -> void:
	_off_hurry = _off_hurry or hurry
	if _off == 1:   # (still on its ramp: straight back up it)
		var e := _ramp_ends(off_ship)
		_off = 4
		_off_path = [e[1], e[0]]
	elif _off == 2:
		_off = 3
		_off_goal = Vector3.INF


## Gone back aboard (up its ramp, in at its door).
func back_aboard() -> bool:
	return _off == 5


## His ship's ramp (ship space): [inside its door, its top, its foot, a step past it].
func _ramp_ends(s: Node3D) -> Array:
	var ramp: Node3D = s.get("_ramp")
	if ramp == null:
		return [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var plank: Node3D = ramp.get_child(0)
	var top: Vector3 = ramp.position + Vector3(0, plank.scale.y * 0.5, 0)
	var ang: float = s.get("_ramp_ang")
	var foot: Vector3 = ramp.position + Vector3(0, -sin(ang), cos(ang)) * float(s.get("_ramp_len"))
	foot.y = -float(s.call("rest_height"))   # (on the deck it stands on)
	return [top + Vector3(0, 0, -2.2), top, foot, foot + Vector3(0, 0, 2.5)]


## The step past his ship's ramp's foot (town-local).
func _ramp_foot() -> Vector3:
	if not is_instance_valid(off_ship) or not is_instance_valid(town):
		return _tl
	var p := town.to_local(off_ship.to_global(_ramp_ends(off_ship)[3]))
	p.y = 0.0
	return p


func _walk_ramp(delta: float) -> void:
	if _anim and not visible:
		visible = true
		_anim.active = true
	var left := (CREW_RUN if _off_hurry else CREW_SPEED) * delta
	var dir := Vector3.ZERO
	while left > 0.0 and not _off_path.is_empty():
		var to: Vector3 = _off_path[0] - _dl
		if to.length() <= left:
			_dl = _off_path.pop_front()
			left -= to.length()
		else:
			dir = to.normalized()
			_dl += dir * left
			left = 0.0
	global_position = off_ship.to_global(_dl)
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.01:
		global_basis = Basis.looking_at(off_ship.global_basis * flat.normalized(), off_ship.global_basis.y)
	_play("run" if _off_hurry else "walk")
	if not _off_path.is_empty():
		return
	if _off == 1:   # (off it: one of the town's people a while)
		_off = 2
		_off_goal = Vector3.INF
		if is_instance_valid(town):
			var f := town.global_basis.inverse() * (off_ship.global_basis * flat)
			f.y = 0.0
			if f.length() > 0.01:
				facing = f.normalized()
	else:
		_off = 5   # (in at its door: aboard - CosmosLandingField takes him off with it)
		visible = false


## A step of his walk ashore toward `goal` (town-local): the way along the town's
## spots, then straight to it - ZERO once he's there.
func _ashore_step(goal: Vector3, delta: float) -> Vector3:
	if _off_goal != goal:
		_off_goal = goal
		_off_path = _route(_tl, goal)
		_off_end = goal
		if not _off_path.is_empty() and not _clear(_off_path[_off_path.size() - 1], goal):
			_off_end = _off_path[_off_path.size() - 1]   # (no way to it from the streets: as near as they go)
		_stuck_t = 0.0
		_stuck_at = _tl
	var at: Vector3 = _off_path[0] if not _off_path.is_empty() else _off_end
	var g := at - _tl
	g.y = 0.0
	if g.length() < (0.35 if _off_path.is_empty() else 1.2):
		if _off_path.is_empty():
			return Vector3.ZERO
		_off_path.pop_front()
		return _ashore_step(goal, delta)
	_stuck_t += delta
	if _stuck_t > 3.0:   # (held up against a wall: on to the next spot of his way - or, its last stretch, there as near as he gets)
		if _tl.distance_to(_stuck_at) < 0.6:
			if not _off_path.is_empty():
				_off_path.pop_front()
			else:
				_off_end = _tl   # (no walking on the spot against it for ever: he stands where he is)
				_stuck_t = 0.0
				return Vector3.ZERO
		_stuck_t = 0.0
		_stuck_at = _tl
	var mv := g.normalized()
	facing = _turn.step(facing, mv, Vector3.UP, delta)
	return mv


## A way across the town from `a` to `b` (town-local): along its spots (its streets'),
## the shortest chain of them from the nearest to `a` to the nearest to `b` - each hop
## along a street (TownStreets' pieces) or a short one (a crossing) - then `b`.
const HOP := 26.0
const PALACE_WAY := [Vector3(0, 0, 19), Vector3(0, 0, -19), Vector3(0, 0, 8), Vector3(0, 0, -8)]   # (a city's palace: through its gateways into its court)
static var _spot_graphs := {}   # town instance id -> {cells: Vector2i -> [spot index]}


func _route(a: Vector3, b: Vector3) -> Array:
	var out: Array = []
	if not is_instance_valid(town) or town.spots.is_empty() or Vector2(b.x - a.x, b.z - a.z).length() < HOP:
		return out
	var sp: Array = town.spots + (PALACE_WAY if str(town.site.get("kind", "")) == "city" else [])
	var gk := town.get_instance_id()
	if not _spot_graphs.has(gk) or int(_spot_graphs[gk]["n"]) != sp.size():
		var cells := {}
		for i in sp.size():
			var k := Vector2i(floori(sp[i].x / HOP), floori(sp[i].z / HOP))
			if not cells.has(k):
				cells[k] = []
			cells[k].append(i)
		_spot_graphs[gk] = {"cells": cells, "n": sp.size()}
	var cells: Dictionary = _spot_graphs[gk]["cells"]
	var near := func(p: Vector3) -> int:
		var best := -1
		var bd := INF
		for i in sp.size():
			var d := Vector2(sp[i].x - p.x, sp[i].z - p.z).length_squared()
			if d < bd:
				bd = d
				best = i
		return best
	var s0: int = near.call(a)
	var s1: int = near.call(b)
	if s0 < 0 or s0 == s1:
		return out
	# (A*: the spots as nodes, a hop between any two within HOP of each other)
	var g := {s0: 0.0}
	var from := {}
	var open: Array = [s0]
	var done := {}
	var found := false
	var closest := s0   # (no way to b's: the nearest to it there is a way to)
	var cd := INF
	for guard in 4000:
		if open.is_empty():
			break
		var bi := 0
		var bf := INF
		for j in open.size():
			var n: int = open[j]
			var f: float = g[n] + Vector2(sp[n].x - sp[s1].x, sp[n].z - sp[s1].z).length()
			if f < bf:
				bf = f
				bi = j
		var cur: int = open[bi]
		open.remove_at(bi)
		if cur == s1:
			found = true
			break
		var hd := Vector2(sp[cur].x - b.x, sp[cur].z - b.z).length()
		if hd < cd:
			cd = hd
			closest = cur
		done[cur] = true
		var c := Vector2i(floori(sp[cur].x / HOP), floori(sp[cur].z / HOP))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for nb in cells.get(c + Vector2i(dx, dz), []):
					if done.has(nb):
						continue
					var hop := Vector2(sp[nb].x - sp[cur].x, sp[nb].z - sp[cur].z).length()
					if hop > HOP or (hop > 9.0 and not _on_street(sp[cur], sp[nb]) and not _clear(sp[cur], sp[nb])):
						continue
					var ng: float = g[cur] + hop
					if not g.has(nb) or ng < float(g[nb]):
						g[nb] = ng
						from[nb] = cur
						if not nb in open:
							open.append(nb)
	if not found:
		s1 = closest
		if s1 == s0:
			return [Vector3(sp[s0].x, 0, sp[s0].z)]
	var n: int = s1
	while n != s0:
		out.push_front(Vector3(sp[n].x, 0, sp[n].z))
		n = from[n]
	out.push_front(Vector3(sp[s0].x, 0, sp[s0].z))
	# (to or from the landing field, out past the town's edge: along the street out of it, then along its edge)
	var edge: float = float(CosmosTown.layout(str(town.site.get("kind", "")))["half"]) + 3.0
	if b.x > edge - 3.0:
		var last: Vector3 = out[out.size() - 1]
		out.append_array([Vector3(edge, 0, last.z), Vector3(edge, 0, b.z)])
	if a.x > edge - 3.0:
		var first: Vector3 = out[0]
		out = [Vector3(edge, 0, a.z), Vector3(edge, 0, first.z)] + out
	return out


## Nothing of the town's in the way from `p` to `q` (town-local), at a body's height (a little to each side).
func _clear(p: Vector3, q: Vector3) -> bool:
	var d := Vector3(q.x - p.x, 0, q.z - p.z)
	var l := d.length()
	if l < 0.01:
		return true
	d /= l
	var side := Vector3(-d.z, 0, d.x) * 0.45
	for o in [Vector3.ZERO, side, -side]:
		if float(town.ray_hit(Vector3(p.x, 0.9, p.z) + o, d, l)[0]) < l:
			return false
	return true


## The way from `p` to `q` (town-local) along one of the town's streets (its middle and quarters on its paving).
func _on_street(p: Vector3, q: Vector3) -> bool:
	for k in [0.25, 0.5, 0.75]:
		var m := Vector2(lerpf(p.x, q.x, k), lerpf(p.z, q.z, k))
		var on := false
		for st in town.streets:
			if (st["r"] as Rect2).grow(1.5).has_point(m):
				on = true
				break
		if not on:
			return false
	return true
