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

const WALK := 3.4               # m/s
const RUN := 8.0
const ACCEL := 22.0
const AIR_ACCEL := 6.0
const JUMP := 5.6               # m/s up
const GRAVITY := 11.0
const TURN := 10.0              # how fast it turns to face its way
const SWIM_DEPTH := 1.25        # deeper water than this: swimming, head above it
const BODY_R := 0.45
const CLIPS := {"idle": "idle", "walk": "walk", "run": "run", "air": "leap", "down": "ko",
	"gun_idle": "gun_idle", "gun_walk": "gun_walk", "gun_run": "gun_run"}
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
var control := true
var facing := Vector3.FORWARD   # world, along the ground
var drive := {}                 # (tests: {move: Vector2 (x right, y forward), run, jump})
var heading := Vector3.FORWARD  # the camera's way along the ground (CosmosCam keeps it)
var hp := MAX_HP
var downed := false
var trigger := false            # (the fire button held: Cosmos sets it)
var reach := 0.6
var _cool := 0.0
var _gun_t := 0.0               # (the rifle up for a while after firing)
var _since_hit := 99.0
var _anim: AnimationPlayer
var _clip := ""
var _model: Node3D


func _ready() -> void:
	name = "Walker"
	if Stage3D.has_model("player"):
		_model = Stage3D._scene("player").instantiate()
		_model.rotation.y = PI       # (the model faces +z; the walker's forward is -z)
		add_child(_model)
		CosmosModels.apply(_model, "player")   # (two draws: its parts merged, colours in the vertices)
		_anim = _model.find_child("AnimationPlayer", true, false)
		if _anim:
			for c in ["idle", "walk", "run", "gun_idle", "gun_walk", "gun_run"]:
				if _anim.has_animation(c):
					_anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	else:
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.9
		cap.mesh = cm
		cap.position.y = 0.95
		add_child(cap)
	_play("idle")


func up() -> Vector3:
	if deck:
		return deck.global_basis.y
	return (global_position - planet.global_position).normalized()


## The ground's height (metres above the radius) under `local` - and the
## level to stand on there (the sea's surface less the swim depth, an ice
## sheet's top).
## Onto `d` (a deck) at its point `local`, or off it (null).
func set_deck(d: Node3D) -> void:
	deck = d
	if d:
		_dl = d.to_local(global_position)


func floor_at(local: Vector3) -> float:
	if deck:
		return 0.0
	var h := planet.shape.height(local.normalized())
	match planet.shape.sea:
		1:
			return maxf(h, -SWIM_DEPTH)
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
	if deck:
		global_position = deck.to_global(_dl)   # (carried along with the deck)
	_since_hit += delta
	if _since_hit > 5.0:
		hp = minf(MAX_HP, hp + REGEN * delta)
	_cool -= delta
	_gun_t -= delta
	if (trigger or bool(drive.get("fire", false))) and _cool <= 0.0 and cosmos:
		_cool = FIRE_EVERY
		_gun_t = 3.0
		cosmos.walker_fire(self)
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
		mv.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		mv.y = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if joy.length() > 0.2:
			mv = joy
		running = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
		jump = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	mv = mv.limit_length(1.0)
	var top := (RUN if running else WALK) * (0.45 if swimming else 1.0)
	var want := (heading * mv.y + right * mv.x) * top
	var vert := velocity.dot(u)
	var flat := velocity - u * vert
	flat = flat.move_toward(want, (ACCEL if on_ground or swimming else AIR_ACCEL) * delta)
	if jump and (on_ground or swimming) and vert <= 0.5:
		vert = JUMP * (0.6 if swimming else 1.0)
		on_ground = false
	vert -= GRAVITY * delta
	velocity = flat + u * vert
	global_position += velocity * delta
	# The ground (or the hangar's deck, within its walls).
	if deck:
		var hl := deck.to_local(global_position)
		var fy: float = deck.floor_y(hl)
		if hl.y <= fy + 0.02:
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
		if r <= stand + 0.02:
			global_position = planet.global_position + u * stand
			if velocity.dot(u) < 0.0:
				velocity -= u * velocity.dot(u)
			on_ground = true
		elif r > stand + 0.25:
			on_ground = false
	if cosmos:
		cosmos.walker_bumps(self)
	# Face the way it goes; stand along the local up.
	var go := velocity - u * velocity.dot(u)
	if _gun_t > 0.0:
		facing = facing.slerp(heading, 1.0 - exp(-delta * 18.0))   # (aiming: facing where the camera looks)
	elif go.length() > 0.4:
		facing = facing.slerp(go.normalized(), 1.0 - exp(-delta * TURN)) if facing.dot(go.normalized()) > -0.99 else go.normalized()
	facing = (facing - u * facing.dot(u)).normalized()
	if facing.length() < 0.5:
		facing = heading
	global_basis = Basis.looking_at(facing, u)
	# Animation.
	var speed := go.length()
	var gun := "gun_" if _gun_t > 0.0 else ""
	if not on_ground and not swimming:
		_play("air")
	elif speed > (WALK + RUN) * 0.5 - 0.5:
		_play(gun + "run", speed / RUN)
	elif speed > 0.3:
		_play(gun + "walk", speed / WALK)
	else:
		_play(gun + "idle")


func _play(kind: String, rate := 1.0) -> void:
	if _anim == null:
		return
	var clip: String = CLIPS[kind]
	if not _anim.has_animation(clip):
		return
	if clip != _clip:
		_anim.play(clip, 0.18)
		_clip = clip
	_anim.speed_scale = clampf(rate, 0.5, 1.6) if kind.ends_with("walk") or kind.ends_with("run") else 1.0


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
