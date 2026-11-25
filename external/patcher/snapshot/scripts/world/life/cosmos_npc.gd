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
var scale_k := 1.0


## One of a dungeon's dead: "skeleton" (a sword and a shield), "demon"
## (claws and fire), `boss`: the demon lord by its chest.
func foe_of(d: CosmosDungeon, seed: int, kind: String, boss := false) -> void:
	dungeon = d
	planet = d.planet
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
		if dungeon:
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
	_play("guard" if dungeon else (("gun_idle" if weapon != "" else "idle") if town else "guard"))


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
	if town:
		var d := _lazy_step(delta)
		if d >= 0.0:
			_citizen(d)
		return
	if dungeon:
		_dungeon_fight(delta)
		return
	var u := up()
	var me := global_position - planet.global_position
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
			_goal = camp + t * _rng.randf_range(3.0, 14.0)
		var g := _goal - me
		g -= u * g.dot(u)
		if g.length() > 1.0:
			move = g.normalized() * 0.6
			facing = g.normalized()
		if not busy:
			_play("walk" if move.length() > 0.1 else "guard")
	global_position += move * SPEED * delta
	var local := global_position - planet.global_position
	var d := local.normalized()
	global_position = planet.global_position + d * (planet.radius + maxf(planet.shape.height(d), 0.0))
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
	elif near:
		var to: Vector3 = town.to_local(me.global_position) - _tl
		to.y = 0.0
		if to.length() > 0.1:
			facing = _turn.step(facing, to, Vector3.UP, delta)   # (round smoothly - never snapped)
		_play("gun_idle" if armed else "idle")
	elif role in ["vendor", "courier", "pilot"] or _wait > 0.0:
		_wait -= delta
		_play("gun_idle" if armed else "idle")
	else:
		var g := _goal - _tl
		g.y = 0.0
		_t -= delta
		if g.length() < 1.0 or _t <= 0.0:
			_goal = town.spots[_rng.randi() % town.spots.size()] + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
			_t = 25.0
			_wait = _rng.randf_range(1.0, 6.0) if _rng.randf() < 0.6 else 0.0
		else:
			move = g.normalized()
			facing = _turn.step(facing, move, Vector3.UP, delta)
			_play("gun_walk" if armed else "walk")
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
	if me and me.get("deck") == dungeon and not me.get("downed"):
		to = dungeon.to_local(me.global_position) - _tl
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


## The nearest pirate or hunting beast within `reach` m.
func _nearest_foe(reach: float) -> Node3D:
	var best: Node3D = null
	var bd := reach
	for list in [cosmos.npcs, cosmos.creatures]:
		for x in list:
			if not is_instance_valid(x) or x.get("dead") or x == self:
				continue
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
