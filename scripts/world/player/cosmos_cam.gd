class_name CosmosCam
extends Camera3D
## The third-person camera of the 3D game (Cosmos): behind and above the
## ship, turning after it a moment late (you see the ship bank and pitch),
## widening its view with speed. The wheel pulls it in and out; holding the
## right button looks round the ship with the mouse (let go: it swings back).
## It never dips under the ground.

const OFFSET := Vector3(0.0, 13.0, 54.0)   # (the ship's ~49 m long)
const LOOK_AHEAD := 70.0
## How high over the ship the camera aims (in OFFSET.y): the ship low in the view, clear of the
## centre's reticle - about a quarter of the screen's height under the middle (was 0.35: ~an eighth).
const LOOK_UP := 1.85

const ZOOM_HOME := 1.35        # (the wheel's zoom to start with - and after a middle click)
const FOOT_ZOOM_HOME := 1.0

var target: Node3D
var zoom := ZOOM_HOME
var zoom_max := 4.0               # (a big ship watched from its passenger seat: further out)
var cosmos: Node
var _q := Quaternion.IDENTITY
var _look := Vector2.ZERO       # free look (yaw, pitch)
var free_look := false          # (watching a ship you're aboard from its passenger seat: the mouse turns the view round it, as on foot - and it stays)
var _fov := 70.0
## On foot (stage 2): the walker it orbits instead of the ship - the mouse
## turns the view round it (its `heading`) and up and down.
var walker: Node3D = null
var foot_zoom := FOOT_ZOOM_HOME
var _pitch := 0.25


func _ready() -> void:
	near = 0.25
	far = 600000.0
	fov = 70.0
	if target:
		_q = target.global_basis.get_rotation_quaternion()


func _unhandled_input(event: InputEvent) -> void:
	if walker:
		if event is InputEventMouseMotion and (cosmos.mouse_steers() if cosmos else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
			var u: Vector3 = walker.up()
			walker.heading = walker.heading.rotated(u, -event.relative.x * 0.004).normalized()
			_pitch = clampf(_pitch + event.relative.y * 0.003, -1.35, 1.25)   # (up to ~77 degrees up: the sky)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				foot_zoom = maxf(0.4, foot_zoom / 1.12)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				foot_zoom = minf(5.0, foot_zoom * 1.12)
			elif event.button_index == MOUSE_BUTTON_MIDDLE and not _builder_out():
				foot_zoom = FOOT_ZOOM_HOME   # (the middle button: the wheel's zoom back to its start)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(0.45, zoom / 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(zoom_max, zoom * 1.12)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			zoom = float(get_meta("zoom_home", ZOOM_HOME))   # (the middle button: the wheel's zoom back to its start - the stick centred too, CosmosShip)
	elif event is InputEventMouseMotion and free_look and (cosmos.mouse_steers() if cosmos else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_look += event.relative * 0.004
		_look.y = clampf(_look.y, -1.3, 1.3)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look += event.relative * 0.005
		_look.y = clampf(_look.y, -1.2, 1.2)


## The builder out (on foot): the middle button turns its piece instead.
func _builder_out() -> bool:
	var b = cosmos.get("builds") if cosmos else null
	return b != null and is_instance_valid(b) and b.tool_out()


func _process(delta: float) -> void:
	follow(minf(delta, 0.05))


func follow(delta: float) -> void:
	if walker:
		_follow_walker(delta)
		return
	if target == null:
		return
	var tq := target.global_basis.get_rotation_quaternion()
	_q = _q.slerp(tq, 1.0 - exp(-delta * 7.0)).normalized()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not free_look:
		_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-delta * 3.0))
	var b := Basis(_q) * Basis(Vector3.UP, -_look.x) * Basis(Vector3.RIGHT, -_look.y)
	var at := target.global_position
	var pos := at + b * (OFFSET * zoom)
	if cosmos:
		pos = cosmos.keep_above_ground(pos, 2.0)
		pos = cosmos.camera_clear(at + b * Vector3(0, OFFSET.y * zoom * 0.5, 0), pos, target)
	global_position = pos
	var ahead := at + (Basis(_q) * Vector3.FORWARD) * LOOK_AHEAD * (1.0 if _look.length() < 0.05 else 0.0)
	if ahead.distance_to(pos) > 0.01:
		look_at(ahead + b * Vector3(0, OFFSET.y * zoom * LOOK_UP, 0), b * Vector3.UP)
	var spd: float = target.speed() if target.has_method("speed") else 0.0
	var want := 70.0 + clampf(spd / 400.0, 0.0, 1.0) * 6.0 + clampf(log(maxf(spd, 1.0)) / log(40000.0), 0.0, 1.0) * 10.0
	_fov = lerpf(_fov, want, 1.0 - exp(-delta * 3.0))
	fov = _fov


## Behind the walker, over its shoulder, along the camera's heading on the ground.
func _follow_walker(delta: float) -> void:
	var u: Vector3 = walker.up()
	var h: Vector3 = walker.heading
	var right := h.cross(u).normalized()
	var pivot: Vector3 = walker.global_position + u * 1.55
	# Where it looks comes from the pitch itself (the sky too, when the ground
	# holds the camera up behind you); it sits back along that line, over the shoulder.
	var look := (h * cos(_pitch) - u * sin(_pitch)).normalized()
	var pos := pivot - look * 4.6 * foot_zoom + right * 0.55 * minf(foot_zoom, 1.5)
	if cosmos:
		pos = cosmos.keep_above_ground(pos, 0.6)
		pos = cosmos.camera_clear(pivot, pos)
	global_position = pos
	look_at(pos + look * 10.0 + right * 0.05, u if absf(look.dot(u)) < 0.98 else h)
	_fov = lerpf(_fov, 68.0, 1.0 - exp(-delta * 3.0))
	fov = _fov
	_q = global_basis.get_rotation_quaternion()


## Back to the ship: its view from behind, from where the camera is now.
func to_ship() -> void:
	walker = null
	if target:
		_q = target.global_basis.get_rotation_quaternion()
