class_name CosmosWalker
extends Node3D
## You on foot in the 3D game (Cosmos, stage 2): the automaton's actual model
## (art/player_3d - its cel shaders and animations: idle, walk, run, leap)
## walking a planet's procedural ground. "Down" is the planet's middle: the
## walker stands along the local up, the ground under it is the planet's
## height field (PlanetShape - the same one the terrain patches are built
## from), seas are waded (shallows) or swum (head above water), an ice sheet
## walked on. W A S D move relative to the camera, Shift runs, Space jumps;
## it turns to face where it goes. Boulders and the landed ship are solid.
## The jet pack on its back: Space held after a jump fires it - a climb while
## its charge lasts (refilled on the ground), the arms out, the legs hanging,
## flames from its nozzles. Upgraded (Leg Servos: Jet pack, five levels) it
## burns longer and harder - and at the top for as long as you like: out of
## the air into space, hovering when Space is let go, F / Ctrl to come down,
## W A S D faster the higher you are (Shift: faster still) - to another world,
## whose gravity then takes you.

const WALK := 3.4               # m/s
const RUN := 8.0
const ACCEL := 22.0
const AIR_ACCEL := 6.0
const JUMP := 5.6               # m/s up
const GRAVITY := 11.0
const TURN := 10.0              # how fast it turns to face its way
var _turn := SmoothTurn.new(8.0, 7.5, 14.0)
var _still_t := 0.0   # (how long it's been all but still: standing only after a moment)
var _aim_turn := SmoothTurn.new(14.0, 12.0, 24.0)
const SWIM_DEPTH := 1.25        # deeper water than this: swimming, head above it
const BODY_R := 0.45
const CLIPS := {"idle": "idle", "walk": "walk", "run": "run", "air": "fall", "jump": "jump", "jet": "jet", "down": "ko",
	"gun_idle": "gun_idle", "gun_walk": "gun_walk", "gun_run": "gun_run", "sit": "sit", "stool": "stool",
	"carry": "carry", "carry_idle": "carry_idle", "put_down": "put_down", "pick_up": "pick_up",
	"swim": "swim", "swim_idle": "swim_idle", "dive": "dive", "dive_idle": "dive_idle"}
const DIVE_SPEED := 3.2         # m/s under water (Shift: faster)
const DIVE_RISE := 2.6          # m/s up (Space) or down (F / Ctrl)
const DIVE_DRIFT := 0.3         # m/s: a slow drift up when you neither rise nor sink
## A package carried in both hands: its middle between them (as the port's cargo hands' crates).
const CARRY_AT := Vector3(0, 1.06, -0.33)
const PUT_DOWN_LET_GO := 0.733  # s into "put_down" the hands let go (moves.py: frame 22)
const PICK_UP_GRIP := 0.6       # s into "pick_up" the hands take hold
## The jet pack by its level (0: as it comes): [charge (s of burn), thrust (m/s2), its top climb (m/s)].
const JET := [[0.7, 17.0, 6.0], [1.6, 20.0, 9.0], [3.2, 24.0, 14.0], [6.5, 30.0, 22.0], [14.0, 38.0, 40.0], [INF, 46.0, 60.0]]
const JET_DELAY := 0.22          # s after the jump before holding Space fires it
const SPACE_TOP := 2600.0        # m/s: the top level's speed across, far out (W A S D; Shift x2)
const MAX_HP := 100.0
const REGEN := 6.0              # health a second, 5 s after the last hit
const FIRE_EVERY := 0.17        # s between bolts, the trigger held
const BOLT_DAMAGE := 18.0

var planet: CosmosPlanet
var deck: Node3D = null         # (a hangar's or a ship's inside - CosmosHangar / CosmosShipInterior: its floor instead of a planet's ground)
var _dl := Vector3.ZERO         # (where on the deck: kept in its own space - a moving ship carries you)
var cosmos: Node
var velocity := Vector3.ZERO    # world
var on_ground := false
var swimming := false
var diving := false              # (under the sea: F / Ctrl down, Space up - swimming in three dimensions)
var control := true
var facing := Vector3.FORWARD   # world, along the ground
var drive := {}                 # (tests: {move: Vector2 (x right, y forward), run, jump})
var heading := Vector3.FORWARD  # the camera's way along the ground (CosmosCam keeps it)
var hp := MAX_HP
var downed := false
var trigger := false            # (the fire button held: Cosmos sets it)
var _scan_was := false          # (the fire button held last frame, the scanner in hand)
var reach := 0.6
var _cool := 0.0
var _gun_t := 0.0               # (the rifle out for a while after firing)
## The rifle: "slung" on the back, "drawing" it off, "carry" in hand, "aiming" (shooting), "holstering" it back.
var gun_state := "slung"
var arms: ArmsLayer = null
var _shot_t := 9.0              # (since the last shot)
var _aim_flat := Vector3.ZERO   # (to where the shots go, along the ground)
const DRAW_SPEED := 1.25        # (the draw and the holster a little brisker than authored: ~0.45 s)
var _since_hit := 99.0
var _anim: AnimationPlayer
var _clip := ""
var _model: Node3D
var jet_level := 0
var jet_fuel := 0.7              # s of burn left
var jetting := false
var _flying := false             # (the top level's pack on: flying, hovering)
var _air_t := 0.0                # (s since it left the ground)
var _jet_t := 0.0                # (the level re-read now and then)
var _pack: Node3D
var _plumes: Array = []


func _ready() -> void:
	name = "Walker"
	process_priority = 5   # (after the ships have moved this frame - on a deck it's put where its ship is now, not a frame behind; before the camera, 10)
	if Stage3D.has_model("player"):
		_model = Stage3D._scene("player").instantiate()
		_model.rotation.y = PI       # (the model faces +z; the walker's forward is -z)
		add_child(_model)
		CosmosModels.apply(_model, "player")   # (two draws: its parts merged, colours in the vertices)
		_anim = _model.find_child("AnimationPlayer", true, false)
		if _anim:
			Stage3D.loop_clips(_anim, "player", ["idle", "walk", "run", "gun_idle", "gun_walk", "gun_run"])   # (every clip model.json marks a loop - swim, dive, carry too - a whole cycle long: no jump at the seam)
			var sks := _model.find_children("*", "Skeleton3D", true, false)
			if not sks.is_empty() and _anim.has_animation("draw"):
				arms = ArmsLayer.new()   # (the upper body over the legs: drawing, slinging and aiming the rifle)
				arms.name = "Arms"
				arms.setup(_anim)
				(sks[0] as Skeleton3D).add_child(arms)
		_pack_on()
	else:
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.9
		cap.mesh = cm
		cap.position.y = 0.95
		add_child(cap)
	_read_jet()
	jet_fuel = float(JET[jet_level][0]) if jet_level < JET.size() - 1 else 1.0
	_play("idle")
	lamp = SpotLight3D.new()   # (the lamp on the shoulder: down in dug ground, at night - lamp_step)
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.93, 0.82)
	lamp.light_energy = 0.0
	lamp.spot_range = 32.0
	lamp.spot_angle = 38.0
	lamp.spot_attenuation = 0.9
	lamp.shadow_enabled = false
	lamp.visible = false
	add_child(lamp)


## The lamp: on (faded in) down in dug ground - a pit, a tunnel, under the
## ground as it was - or where the sun's down; it shines where the camera looks.
var lamp: SpotLight3D
var lamp_on := false
var _lamp_t := 0.0
const LAMP_ENERGY := 2.6


func _lamp_step(delta: float) -> void:
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 0.3   # (looked at a few times a second)
		lamp_on = false
		if planet and deck == null:
			var local := global_position - planet.global_position
			var u := local.normalized()
			if planet.shape.carved_near(local) and planet.shape.height(u) - (local.length() - planet.radius) > 1.2:
				lamp_on = true   # (down in what's been dug)
			elif u.dot(planet.sun_dir) < -0.05:
				lamp_on = true   # (night)
	var want := LAMP_ENERGY if lamp_on else 0.0
	lamp.light_energy = move_toward(lamp.light_energy, want, delta * LAMP_ENERGY * 2.5)
	lamp.visible = lamp.light_energy > 0.01
	if lamp.visible:
		var cam := get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_basis.z if cam else facing
		var u := up()
		lamp.global_transform = Transform3D(Basis.looking_at(fwd, u if absf(fwd.dot(u)) < 0.98 else facing), global_position + u * 1.55 + facing.cross(u) * 0.2)


func up() -> Vector3:
	if deck:
		return deck.global_basis.y
	return (global_position - planet.global_position).normalized()


## The ground's height (metres above the radius) under `local` - and the
## level to stand on there (the sea's surface less the swim depth, an ice
## sheet's top).
## Onto `d` (a deck) at its point `local`, or off it (null).
func set_deck(d: Node3D) -> void:
	if d is CosmosShipInterior and not (d as CosmosShipInterior).built and d.get_parent() is CosmosShip:
		(d.get_parent() as CosmosShip).parts_in(true)   # (aboard before its rooms were in: made now)
	deck = d
	if d:
		_dl = d.to_local(global_position)


func floor_at(local: Vector3) -> float:
	if deck:
		return 0.0
	var h := planet.shape.floor_below(local) if planet.shape.carved_near(local) else planet.shape.height(local.normalized())   # (dug: the voxels' floor - a pit's, a tunnel's)
	if cosmos:
		h = maxf(h, cosmos.town_floor(planet, local))   # (a town's steps and roofs)
	match planet.shape.sea:
		1:
			return h if diving else maxf(h, -SWIM_DEPTH)   # (diving: the sea floor; else afloat at swimming depth)
		2:
			return maxf(h, 0.0)
		3:
			return maxf(h, -0.4)
	return h


## A hit (a bite, a bolt).
func hurt(dmg: float, _from: Variant = null) -> void:
	if downed:
		return
	hp -= dmg
	_since_hit = 0.0
	if cosmos and cosmos.hud:
		cosmos.hud.hit_flash = 0.5
	if hp <= 0.0:
		hp = 0.0
		downed = true
		_play("down")
		if cosmos:
			cosmos.walker_downed()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if planet == null and deck == null:
		return
	if downed:
		return
	if typeof(deck) == TYPE_OBJECT and not is_instance_valid(deck):
		return   # (its deck gone under it: Cosmos sets it down - _npc_boarding)
	if deck:
		global_position = deck.to_global(_dl)   # (carried along with the deck)
	if not seat.is_empty():
		_seated()
		return
	if lamp:
		_lamp_step(delta)
	_since_hit += delta
	if _since_hit > 5.0:
		hp = minf(MAX_HP, hp + REGEN * delta)
	_cool -= delta
	_gun_t -= delta
	var firing := (trigger or bool(drive.get("fire", false))) and not carrying and _hands == ""   # (hands full: no rifle, no beam)
	if cosmos and ToolbarUse.held(cosmos) == "tool:scanner":   # (the scanner in hand: a click sends its pulse - once a press)
		if firing and not _scan_was and cosmos.get("sandbox"):
			cosmos.sandbox.scan()
		_scan_was = firing
		firing = false
	if cosmos and deck == null and ToolbarUse.held(cosmos) == "tool:build" and cosmos.get("builds"):   # (the builder in hand: a click places a piece)
		cosmos.builds.trigger(firing)
		firing = false
	var dep: CosmosDeposits = cosmos.deposits if cosmos and deck == null else null
	var aim_req := false
	if dep and dep.planet == planet and dep.step(delta, firing):
		_gun_t = 3.0   # (the mining beam on a deposit: the rifle holds its fire)
		aim_req = true
	elif firing:
		_gun_t = 3.0
		aim_req = true
		if _cool <= 0.0 and cosmos and (arms == null or (gun_state == "aiming" and arms.weight > 0.85 and arms.blended())):
			_cool = FIRE_EVERY
			_shot_t = 0.0
			cosmos.walker_fire(self)   # (from the rifle's muzzle, raised and aimed - not till it is)
			if arms:
				arms.play("fire", 0.0, 0.0)   # (its recoil)
	_gun_step(delta, aim_req)
	var u := up()
	# The way the camera looks, along the ground.
	heading = (heading - u * heading.dot(u)).normalized()
	var right := heading.cross(u).normalized()
	var mv := Vector2.ZERO
	var running := false
	var jump := false
	if not drive.is_empty():
		mv = drive.get("move", Vector2.ZERO)
		running = bool(drive.get("run", false))
		jump = bool(drive.get("jump", false))
	elif control:
		mv.x = float(Input.is_action_pressed("right")) - float(Input.is_action_pressed("left"))
		mv.y = float(Input.is_action_pressed("forward")) - float(Input.is_action_pressed("back"))
		mv.x += float(Input.is_action_pressed("use")) - float(Input.is_action_pressed("strafe_left"))   # (E / Q: strafing, as the ship's thrusters)
		var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if joy.length() > 0.2:
			mv = joy
		running = Input.is_action_pressed("boost") or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
		jump = Input.is_action_pressed("up") or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if _hands != "":   # (setting a package down or picking it up: standing still for it)
		mv = Vector2.ZERO
		jump = false
	if carrying:
		running = false   # (a package in both hands: walking)
	mv = mv.limit_length(1.0)
	var top := (RUN if running else WALK) * (0.45 if swimming else 1.0)
	# The jet pack: its level, its charge (refilled on the ground), how high above the ground and the air.
	_jet_t -= delta
	if _jet_t <= 0.0:
		_jet_t = 1.0
		_read_jet()
	var j: Array = JET[jet_level]
	var unlimited := jet_level >= JET.size() - 1
	var alt := 0.0
	var gk := 1.0                    # (gravity, weaker far out: the inverse square)
	if deck == null and planet:
		var r0 := (global_position - planet.global_position).length()
		alt = r0 - planet.radius
		gk = pow(planet.radius / maxf(r0, planet.radius), 2.0)
	if on_ground or swimming or deck:
		_air_t = 0.0
		if not unlimited:
			jet_fuel = minf(float(j[0]), jet_fuel + float(j[0]) / 1.5 * delta)
	else:
		_air_t += delta
	var descend := (control and drive.is_empty() and Input.is_action_pressed("down")) or bool(drive.get("dive", false))
	if swimming and not diving and descend and deck == null:
		diving = true   # (under: F / Ctrl at the surface)
	# (the top level: once fired it flies on - hovering when Space is let go - till you're down again)
	_flying = _flying and unlimited and not on_ground and not swimming and deck == null
	jetting = deck == null and not swimming and not on_ground and _air_t > JET_DELAY and (jump or _flying) and (unlimited or jet_fuel > 0.0)
	if jetting and unlimited:
		_flying = true
	if jetting:
		var far := unlimited and alt > maxf(planet.atmo_radius - planet.radius, 400.0) * 0.5
		top = RUN * 1.6 if not unlimited else clampf(alt * 0.9, RUN * 2.0, SPACE_TOP) * (2.0 if running and far else 1.0)
	var want := (heading * mv.y + right * mv.x) * top
	var vert := velocity.dot(u)
	var flat := velocity - u * vert
	var acc := ACCEL if on_ground or swimming else (maxf(14.0, top * 0.6) if jetting else AIR_ACCEL)
	flat = flat.move_toward(want, acc * delta)
	if jump and (on_ground or swimming) and vert <= 0.5:
		vert = JUMP * (0.6 if swimming else 1.0)
		on_ground = false
		_air_t = 0.0
	if jetting:
		if not unlimited:
			jet_fuel = maxf(0.0, jet_fuel - delta)
		var climb := float(j[2]) if not unlimited else clampf(alt * 0.5, float(j[2]), SPACE_TOP * 0.5)
		if descend and unlimited:
			vert = move_toward(vert, -climb * 0.6, float(j[1]) * 2.0 * delta)   # (F / Ctrl: down, braking)
		elif jump:
			vert = minf(vert + float(j[1]) * delta, maxf(climb, vert))
		elif unlimited:
			vert = move_toward(vert, 0.0, float(j[1]) * 3.0 * delta)   # (hovering: neither up nor down - braking hard)
	if diving:   # (under water: no weight - up and down by hand, a slow drift up between)
		if mv.length() > 0.01:
			flat = flat.move_toward((heading * mv.y + right * mv.x) * DIVE_SPEED * (1.6 if running else 1.0), 6.0 * delta)
		else:
			flat = flat.move_toward(Vector3.ZERO, 3.0 * delta)
		var want_v := DIVE_RISE if jump else (-DIVE_RISE if descend else DIVE_DRIFT)
		vert = move_toward(vert, want_v, 6.0 * delta)
	elif not (jetting and unlimited and not descend):
		vert -= GRAVITY * gk * delta
	velocity = flat + u * vert
	global_position += velocity * delta
	# The ground (or the hangar's deck, within its walls).
	var was_ground := on_ground
	var fall_v := -velocity.dot(u)
	if deck:
		var hl := deck.to_local(global_position)
		var fy: float = deck.floor_y(hl)
		if hl.y < fy or (hl.y <= fy + 0.02 and velocity.dot(u) <= 0.0):   # (not while rising: a jump's first frames at a high frame rate are within the 2 cm)
			hl.y = fy
			if velocity.dot(u) < 0.0:
				velocity -= u * velocity.dot(u)
			on_ground = true
		elif hl.y > fy + 0.3:
			on_ground = false
		hl.y = minf(hl.y, float(deck.ceiling_y(hl)) - 1.9)
		hl = deck.confine(hl, 0.45)
		global_position = deck.to_global(hl)
		_dl = hl
		swimming = false
	else:
		var local := global_position - planet.global_position
		var r := local.length()
		var stand := planet.radius + floor_at(local)
		u = local / r
		swimming = planet.shape.sea == 1 and planet.shape.height(u) < -SWIM_DEPTH * 0.8 and r <= planet.radius + 0.2
		if diving and (not swimming or (r >= planet.radius - SWIM_DEPTH and velocity.dot(u) >= 0.0)):
			diving = false   # (back up at swimming depth, or into the shallows: afloat again)
			stand = planet.radius + floor_at(local)
		if r < stand or (r <= stand + 0.02 and velocity.dot(u) <= 0.0):   # (not while rising: a jump's first frames at a high frame rate are within the 2 cm)
			global_position = planet.global_position + u * stand
			if velocity.dot(u) < 0.0:
				velocity -= u * velocity.dot(u)
			on_ground = true
		elif r > stand + 0.25:
			on_ground = false
	if on_ground and not was_ground:
		_landed(fall_v, u)
	if deck == null and jetting and cosmos and _dust_t <= 0.0 and height_above_ground() < 3.5:
		_dust_t = 0.12   # (the jet's blast raising dust off the ground under it)
		_puff(global_position - u * height_above_ground(), u, 1.6, 2)
	_dust_t -= delta
	_jet_sound(delta)
	if deck == null and not on_ground and cosmos and alt > 200.0:
		_nearer_world()
	if cosmos:
		cosmos.walker_bumps(self)
	# Face the way it goes; stand along the local up.
	var go := velocity - u * velocity.dot(u)
	if _gun_t > 0.0:
		var aim_way := _aim_flat if gun_state == "aiming" and _aim_flat.length() > 0.5 else heading
		facing = _aim_turn.step(facing, aim_way, u, delta)   # (the rifle out: facing where the camera looks; aiming, where the shots go - quicker)
		_turn.w = _aim_turn.w
	elif go.length() > 0.4:
		facing = _turn.step(facing, go, u, delta)   # (round to its way: speeding up, easing off - a reversal a half-second turn, never a snap)
		_aim_turn.w = _turn.w
	facing = (facing - u * facing.dot(u)).normalized()
	if facing.length() < 0.5:
		facing = heading
	global_basis = Basis.looking_at(facing, u)
	# Animation.
	var speed := go.length()
	var gun := "gun_" if (gun_state in ["carry", "aiming", "holstering"] if arms else _gun_t > 0.0) else ""
	_pack_step(delta, go)
	if _hands_step(delta):
		pass   # (setting a package down or picking one up)
	elif (diving or swimming) and deck == null:
		var stroke := speed > 0.3 or (diving and absf(velocity.dot(u)) > 0.5)
		var k := ("dive" if diving else "swim") + ("" if stroke else "_idle")
		if _anim and _anim.has_animation(k):
			_play(k, maxf(speed, 1.0) / 2.0)
		else:
			_play("walk" if stroke else "idle", speed / WALK)
	elif carrying and on_ground and _anim and _anim.has_animation("carry"):
		if speed > 0.3:
			_play("carry", speed / WALK)
		else:
			_play("carry_idle" if _anim.has_animation("carry_idle") else "idle")
	elif not on_ground and not swimming:
		_play("jet" if jetting else ("jump" if _air_t < 0.42 and velocity.dot(u) > 0.0 else "air"))
	elif speed > (WALK + RUN) * 0.5 - 0.5:
		_still_t = 0.0
		_play(gun + "run", speed / RUN)
	elif speed > 0.3:
		_still_t = 0.0
		_play(gun + "walk", speed / WALK)
	else:
		_still_t += delta
		if _still_t > 0.15 or not (_clip.ends_with("walk") or _clip.ends_with("run")):
			_play(gun + "idle")   # (stopped a moment: a reversal passing through still keeps its stride, no flick to standing and back)
		else:
			_play(gun + ("run" if _clip.ends_with("run") else "walk"), 0.5)


# --- A package in your hands -----------------------------------------------------------

var carrying := false
var _box: Node3D
var _hands := ""                 # (setting it down / picking it up: "put_down" / "pick_up")
var _hands_t := 0.0
var _hands_done := Callable()


## The package in your hands (`on`), or not - at once.
func set_carry(on: bool) -> void:
	carrying = on
	if on and _box == null:
		var c := MeshInstance3D.new()
		c.mesh = EmpireKit.crate_mesh(true)
		c.material_override = EmpireKit.mat("inside", "minoa")
		c.scale = Vector3(0.33, 0.36, 0.25)
		c.position = CARRY_AT - Vector3(0, 0.88 * 0.36 * 0.5, 0)   # (the crate's foot below its middle)
		add_child(c)
		_box = c
	elif not on and _box:
		_box.queue_free()
		_box = null


## Setting it down (its clip; `done` when the hands let go) or picking one up.
func hands(clip: String, done: Callable) -> void:
	_hands = clip
	_hands_t = 0.0
	_hands_done = done
	velocity = Vector3.ZERO


func busy() -> bool:
	return _hands != ""


func _hands_step(delta: float) -> bool:
	if _hands == "":
		return false
	_hands_t += delta
	var at := PUT_DOWN_LET_GO if _hands == "put_down" else PICK_UP_GRIP
	if _hands_done.is_valid() and _hands_t >= at:
		var d := _hands_done
		_hands_done = Callable()
		d.call()
	var long := 1.4
	if _anim and _anim.has_animation(_hands):
		long = _anim.get_animation(_hands).length
	_play(_hands)
	if _hands_t >= long:
		_hands = ""
	return true


## The rifle's states each frame: drawn off the back when it's wanted (shooting, mining),
## raised to aim while shooting (the chest pitched to where the shots go), lowered to
## carry a moment after, slung back when it's no longer wanted - each over the legs'
## walk or stand (ArmsLayer), each move eased in and out of.
func _gun_step(delta: float, aim_req: bool) -> void:
	_shot_t += delta
	if arms == null:
		return
	var want := _gun_t > 0.0 and not carrying and _hands == "" and not swimming and not diving and seat.is_empty()
	var w_to := 0.0
	match gun_state:
		"slung":
			if want:
				gun_state = "drawing"
				arms.play("draw", 0.0, 0.0)
		"drawing":
			arms.step(delta, DRAW_SPEED)
			w_to = 1.0
			if arms.done():
				gun_state = "aiming" if aim_req else "carry"
				if aim_req:
					arms.play("fire", 0.0, 0.15)   # (from the draw's end straight up to the aim)
		"carry":
			if not want:
				gun_state = "holstering"
				arms.play("holster", 0.0, 0.0)
			elif aim_req:
				gun_state = "aiming"
				arms.play("fire", 0.0, 0.0)
				arms.weight = 0.0   # (raised from the carry: the weight eases it up)
		"aiming":
			arms.step(delta)
			w_to = 1.0
			if not want:
				gun_state = "holstering"
				arms.play("holster", 0.0, 0.25)
			elif not aim_req and _shot_t > 0.8:
				gun_state = "carry"
		"holstering":
			arms.step(delta, DRAW_SPEED)
			w_to = 1.0
			if arms.done():
				gun_state = "slung"
	if gun_state == "carry" or gun_state == "slung":
		w_to = 0.0
	var rate := 9.0 if w_to > arms.weight else 4.0   # (up to an aim in ~0.12 s; let go of over ~0.25 s)
	arms.weight = move_toward(arms.weight, w_to, delta * rate)
	# The aim: up or down to where the shots go, and round to it along the ground.
	var aiming := gun_state == "aiming"
	if aiming and cosmos and cosmos.has_method("aim"):
		var u := up()
		var to: Vector3 = (cosmos.aim()[1] as Vector3) - (global_position + u * 1.3)
		var flat := to - u * to.dot(u)
		_aim_flat = flat.normalized() if flat.length() > 0.5 else Vector3.ZERO
		var p := clampf(atan2(to.dot(u), maxf(flat.length(), 0.01)), -1.1, 1.1)
		arms.pitch = lerpf(arms.pitch, p, 1.0 - exp(-delta * 14.0))
	arms.aim_k = move_toward(arms.aim_k, 1.0 if aiming else 0.0, delta * (8.0 if aiming else 4.0))


## The rifle's muzzle, as the model holds it now (shots leave from here).
func muzzle() -> Vector3:
	if arms and arms.is_inside_tree():
		return arms.muzzle()
	var u := up()
	return global_position + u * 1.35 + facing * 0.7 + facing.cross(u) * -0.25


## Cross-fade times into a clip (s): a third of a second unless listed.
const BLENDS := {"jump": 0.12, "jet": 0.25, "air": 0.3, "gun_idle": 0.22, "gun_walk": 0.22, "gun_run": 0.22, "pick_up": 0.25, "put_down": 0.25}


func _play(kind: String, rate := 1.0) -> void:
	if _anim == null:
		return
	var clip: String = CLIPS[kind]
	if not _anim.has_animation(clip):
		return
	if clip != _clip:
		_anim.play(clip, BLENDS.get(kind, 0.3))   # (cross-faded: locomotion and poses a third of a second, a jump's spring quicker)
		_clip = clip
	_anim.speed_scale = clampf(rate, 0.5, 1.6) if kind.ends_with("walk") or kind.ends_with("run") or kind == "carry" or kind == "swim" or kind == "dive" else 1.0


## The jet pack's level: its upgrade (the automaton's Leg Servos), as much as they work.
func _read_jet() -> void:
	var lv := 0
	var data = CosmosGame.data if Engine.get_main_loop() and CosmosGame.data else null
	if data:
		lv = roundi(Upgrades.mod(data.upgrades, "automaton", "jet_pack"))
	jet_level = clampi(lv, 0, JET.size() - 1)
	if jet_level < JET.size() - 1:
		jet_fuel = minf(jet_fuel, float(JET[jet_level][0]))


## Flying: the world whose ground is nearest takes over (its gravity, its ground) - not a gas giant's.
func _nearer_world() -> void:
	var best: CosmosPlanet = planet
	var bd := INF
	for p: CosmosPlanet in cosmos.planets:
		if p.shape.kind == "gas" and p != planet:
			continue
		var d := global_position.distance_to(p.global_position) - p.radius
		if d < bd:
			bd = d
			best = p
	if best != planet:
		planet = best
		if cosmos.hud:
			cosmos.hud.flash("Over %s" % best.rec.get("name", ""), 3.0)


## The jet pack on its back (the chest's bone carries it): a frame, two tanks,
## two nozzles in the Minoan look; each nozzle's flame (the ship's engine shader).
func _pack_on() -> void:
	var sk: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	if sk == null or sk.find_bone("chest") < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "chest"
	sk.add_child(att)
	_pack = Node3D.new()
	_pack.name = "JetPack"
	_pack.position = Vector3(0, 0.06, -0.2)   # (the model faces +z: its back is -z)
	att.add_child(_pack)
	var mi := MeshInstance3D.new()
	mi.mesh = pack_mesh()
	mi.material_override = pack_mat()
	_pack.add_child(mi)
	for sx in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.position = Vector3(sx * 0.12, -0.28, -0.05)
		_pack.add_child(holder)
		var c := CylinderMesh.new()
		c.top_radius = 0.055
		c.bottom_radius = 0.005
		c.height = 0.7
		c.radial_segments = 10
		c.rings = 1
		var pl := MeshInstance3D.new()
		pl.mesh = c
		pl.material_override = _flame_mat()
		pl.position = Vector3(0, -0.35, 0)
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(pl)
		var hz := MeshInstance3D.new()   # (the heat haze below it)
		var q := QuadMesh.new()
		q.size = Vector2(0.32, 0.5)
		hz.mesh = q
		hz.material_override = shimmer_mat()
		hz.position = Vector3(0, -0.8, 0)
		hz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(hz)
		holder.visible = false
		_plumes.append([holder, pl])


static var _pack_mesh: ArrayMesh
static var _pack_mat: ShaderMaterial


## The jet pack's look: its empire's hull material, its shader marking the stencil as a
## character's does (pbr_vc) - the scanned veins' hologram never drawn over it. Made once.
static func pack_mat() -> ShaderMaterial:
	if _pack_mat == null:
		var base: ShaderMaterial = EmpireKit.mat("hull", "minoa")
		_pack_mat = base.duplicate()
		var sh := Shader.new()
		var code: String = base.shader.code
		var at := code.find("render_mode")
		at = code.find(";", at) + 1
		sh.code = code.substr(0, at) + "\nstencil_mode write, compare_always, 1;" + code.substr(at)
		_pack_mat.shader = sh
	return _pack_mat
static var _flame: ShaderMaterial


static func pack_mesh() -> ArrayMesh:
	if _pack_mesh == null:
		var m := EmpireKit.Mesher.new()
		m.boxat(Vector3(0.34, 0.42, 0.05), Vector3(0, 0, 0.02), EmpireKit.IRON)          # (the frame against its back)
		for sx in [-1.0, 1.0]:
			m.cyl(Vector3(sx * 0.12, -0.2, -0.05), Vector3(sx * 0.12, 0.2, -0.05), 0.075, 0.075, EmpireKit.MAIN, 14)   # (a tank)
			m.cyl(Vector3(sx * 0.12, 0.06, -0.05), Vector3(sx * 0.12, 0.1, -0.05), 0.079, 0.079, EmpireKit.ACCENT, 14, false)
			m.cyl(Vector3(sx * 0.12, 0.2, -0.05), Vector3(sx * 0.12, 0.24, -0.05), 0.05, 0.03, EmpireKit.STEEL, 10)
			m.cyl(Vector3(sx * 0.12, -0.2, -0.05), Vector3(sx * 0.12, -0.28, -0.05), 0.045, 0.065, EmpireKit.IRON, 12)   # (its nozzle)
			m.boxat(Vector3(0.012, 0.22, 0.012), Vector3(sx * 0.21, -0.02, -0.05), EmpireKit.LAMP)
		m.boxat(Vector3(0.1, 0.12, 0.04), Vector3(0, 0.05, -0.04), EmpireKit.STEEL)
		m.disc(Vector3(0, 0.05, -0.062), Vector3(0, 0, -1), Vector3.UP, 0.04, EmpireKit.ROUNDEL, 16)
		_pack_mesh = m.commit()
	return _pack_mesh


static func _flame_mat() -> ShaderMaterial:
	if _flame == null:
		_flame = ShaderMaterial.new()
		_flame.shader = preload("res://shaders/world/engine.gdshader")
		_flame.set_shader_parameter("glow", false)
		_flame.set_shader_parameter("tint", Color(0.45, 0.75, 1.0))
	return _flame


## In a seat (a port's chair, stool: CosmosHangar.seats): `seat` its record,
## sat still in its clip till you move or stand (E). The deck's point it sits at: `at`.
var seat := {}


func sit(s: Dictionary, at: Vector3) -> void:
	if deck == null:
		return
	seat = s
	s["who"] = self
	_dl = at
	velocity = Vector3.ZERO
	global_position = deck.to_global(at)


func stand_up() -> void:
	if seat.is_empty():
		return
	if seat.get("who") == self:
		seat["who"] = null
	var f: Vector3 = seat["face"]
	seat = {}
	if deck:   # (a step forward, clear of the seat)
		_dl = deck.confine(_dl + f * 0.75, 0.45)
		global_position = deck.to_global(_dl)


func _seated() -> void:
	if not is_instance_valid(deck):
		return   # (its deck gone under it: Cosmos sets it down - _npc_boarding)
	var u := up()
	velocity = Vector3.ZERO
	facing = (deck.global_basis * (seat["face"] as Vector3)).normalized()
	global_basis = Basis.looking_at(facing, u)
	_play(str(seat["kind"]) if _anim and _anim.has_animation(str(seat["kind"])) else "idle")
	var mv := Vector2.ZERO
	if not drive.is_empty():
		mv = drive.get("move", Vector2.ZERO)
	elif control:
		mv = Vector2(float(Input.is_action_pressed("right")) - float(Input.is_action_pressed("left")), float(Input.is_action_pressed("forward")) - float(Input.is_action_pressed("back")))
	if mv.length() > 0.3 or (control and drive.is_empty() and Input.is_action_pressed("up")):
		stand_up()


## Down on the ground (or a deck) at `v` m/s: a thud, dust kicked up, and from
## higher than a few storeys a hurt (FALL_SAFE m/s and up - the jet pack held
## on the way down brakes it).
const FALL_SAFE := 13.0          # m/s (a fall of ~7.7 m)
const FALL_HURT := 7.0           # hp a m/s over it
var _dust_t := 0.0


func _landed(v: float, u: Vector3) -> void:
	if v < 4.0 or cosmos == null:
		return
	if not _headless():
		Sfx.play("skill/land", clampf(-14.0 + v * 0.6, -14.0, 0.0), 0.08)
	if deck == null:
		_puff(global_position, u, clampf(v * 0.25, 1.2, 4.0), clampi(int(v * 0.6), 4, 12))
	if v > FALL_SAFE:
		hurt((v - FALL_SAFE) * FALL_HURT)
		if cosmos.hud:
			cosmos.hud.flash("A hard landing" if hp > 0.0 else "A fall too far")


## Dust round `at` on ground with up `u`, `size` m across (the effect "dust_land", or
## "dust_jet" for the jet's: data/effects.json - Fx), in the ground's colour.
func _puff(at: Vector3, u: Vector3, size: float, n: int) -> void:
	if _headless() or cosmos == null or planet == null:
		return
	var fx: Fx = Fx.spawn("dust_jet" if n <= 2 else "dust_land", cosmos.world, at + u * 0.2, size / 2.0, Fx.basis_up(u))
	if fx:
		var col = planet.shape.look.get("land_low", Color(0.55, 0.5, 0.42))
		fx.set_tint((col if col is Color else Color(0.55, 0.5, 0.42)).lerp(Color(0.8, 0.74, 0.64), 0.65))


static var _puff_mesh: QuadMesh
static var _shimmer: ShaderMaterial


static func puff_mesh() -> QuadMesh:
	if _puff_mesh == null:
		_puff_mesh = QuadMesh.new()
		_puff_mesh.size = Vector2.ONE
	return _puff_mesh


static func shimmer_mat() -> ShaderMaterial:
	if _shimmer == null:
		_shimmer = ShaderMaterial.new()
		_shimmer.shader = preload("res://shaders/world/shimmer.gdshader")
		_shimmer.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	return _shimmer


## The jet's roar: a loop while it fires, louder with its thrust.
var _roar: AudioStreamPlayer


func _jet_sound(delta: float) -> void:
	if _headless():
		return
	var want := -60.0
	if jetting:
		want = -8.0 if velocity.dot(up()) > 0.5 else -13.0
	if _roar == null:
		if not jetting:
			return
		var takes: Array = Sfx.takes("space/afterburner")
		if takes.is_empty():
			return
		var st: AudioStream = takes[0]
		if st is AudioStreamOggVorbis:
			st = st.duplicate()
			st.loop = true
		_roar = AudioStreamPlayer.new()
		_roar.stream = st
		_roar.bus = Sfx.BUS
		_roar.volume_db = -40.0
		add_child(_roar)
		_roar.play()
	_roar.volume_db = move_toward(_roar.volume_db, want, delta * (90.0 if jetting else 45.0))
	if _roar.volume_db <= -55.0 and not jetting:
		_roar.queue_free()
		_roar = null


## The flames with the thrust; the body leaning into its flight across.
func _pack_step(delta: float, go: Vector3) -> void:
	var k := 0.0
	if jetting:
		k = 1.0 if velocity.dot(up()) > 0.5 or jet_level >= JET.size() - 1 else 0.6
	for e in _plumes:
		var holder: Node3D = e[0]
		holder.visible = k > 0.0
		if k > 0.0:
			holder.scale = Vector3(1.0, 0.6 + k * (0.8 + 0.25 * sin(Time.get_ticks_msec() * 0.03)), 1.0)
			if not _headless():
				(e[1] as MeshInstance3D).set_instance_shader_parameter("level", 0.8 + k)
	if _model:
		var lean := clampf(go.length() / 30.0, 0.0, 0.75) if jetting else 0.0
		var cur := _model.get_meta("lean", 0.0) as float
		cur = lerpf(cur, lean, 1.0 - exp(-delta * 4.0))
		_model.set_meta("lean", cur)
		var b := Basis(Vector3.RIGHT, -cur) * Basis(Vector3.UP, PI)
		_model.transform = Transform3D(b, Vector3(0, 1.0, 0) - b * Vector3(0, 1.0, 0))


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Back on its feet (beside the ship), whole.
func revive(at: Vector3) -> void:
	downed = false
	hp = MAX_HP
	velocity = Vector3.ZERO
	global_position = at
	_clip = ""
	_play("idle")


## Metres from its feet to the ground below (tests, the HUD).
func height_above_ground() -> float:
	if deck:
		var l := deck.to_local(global_position)
		return l.y - float(deck.floor_y(l))
	var local := global_position - planet.global_position
	return local.length() - planet.radius - floor_at(local)
