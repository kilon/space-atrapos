class_name CosmosShipInterior
extends Node3D
## The inside of your ship (the 3D game): rooms you walk, inside the hull -
## the cockpit at the nose (the pilot's seat: E takes the controls), a
## corridor, the main deck with the ship's terminals (the Ship Computer's
## pages: inventory, repair bay, fabricator, refinery, tech, star map) and the
## cargo hold at the back, crates stacked by what you carry - and its ramp,
## let down through the belly when landed (the way in and out). A deck for
## CosmosWalker: floor_y / ceiling_y / confine in the ship's own space.

const FLOOR := -1.4
const CEIL := 1.8
## The rooms: [name, x half width, z from, z to, ceiling] (ship space: -z is the nose).
const ROOMS := [["cockpit", 2.0, -15.0, -10.0, 1.8], ["corridor", 1.2, -10.0, -4.0, 1.8], ["deck", 3.6, -4.0, 6.0, 1.8],
	["hold", 3.2, 6.0, 17.0, 1.8], ["aft", 2.4, 17.0, 21.2, 1.15]]
const RAMP := [2.0, 21.2, 6.6]           # half width, its hinge's z (the tail's door), its length
const DOOR_TIME := 1.3
const RAMP_TIME := 2.0
const SEAT := Vector3(0, FLOOR, -13.2)
const TERMINALS := [["Inventory", 0, Vector3(-3.1, 0, -2.0)], ["Repair Bay", 5, Vector3(-3.1, 0, 1.5)], ["Tech", 4, Vector3(-3.1, 0, 4.5)],
	["Fabricator", 7, Vector3(3.1, 0, -2.0)], ["Refinery", 7, Vector3(3.1, 0, 1.5)], ["Star Map", 2, Vector3(3.1, 0, 4.5)]]

var ramp_down := false                   # (open and out: walkable)
var want_open := false
var door_t := 0.0                        # 0 shut .. 1 up in the hull
var ramp_t := 0.0                        # 0 in .. 1 out on the ground
var ramp_end_y := -CosmosShip.GEAR       # where the ground is under its foot (ship space)
var _ramp: Node3D                        # (the hinge)
var _ramp_plank: MeshInstance3D
var _door: MeshInstance3D
var _crates: Node3D
var _mats := {}


func build(accent: Color) -> void:
	name = "Interior"
	_mats = {"floor": _inner(Color(0.24, 0.25, 0.27), 0.8), "wall": _inner(Color(0.66, 0.68, 0.7), 0.7),
		"trim": _inner(accent.darkened(0.2), 0.5), "lamp": _inner(Color(1, 0.97, 0.9), 0.5, Color(1.0, 0.95, 0.85) * 1.3),
		"screen": _inner(accent.lerp(Color(0.1, 0.2, 0.3), 0.3), 0.3, accent * 0.9), "dark": _inner(Color(0.13, 0.14, 0.16), 0.6),
		"crate": _inner(Color(0.45, 0.4, 0.3), 0.85)}
	for i in ROOMS.size():
		var r: Array = ROOMS[i]
		var hw: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var ceil: float = r[4]
		var h := ceil - FLOOR
		var mid := (z0 + z1) * 0.5
		var len := z1 - z0
		_box(Vector3(hw * 2.0, 0.2, len), Vector3(0, FLOOR - 0.1, mid), "floor")
		_box(Vector3(hw * 2.0, 0.2, len), Vector3(0, ceil + 0.1, mid), "wall")
		_box(Vector3(minf(hw, 1.0), 0.06, len * 0.8), Vector3(0, ceil - 0.03, mid), "lamp")
		for side in [-1.0, 1.0]:
			_box(Vector3(0.2, h, len), Vector3(side * (hw + 0.1), FLOOR + h * 0.5, mid), "wall")
			_box(Vector3(0.05, 0.12, len), Vector3(side * hw, FLOOR + 1.0, mid), "trim")
		# End walls, open where the next room joins (and the tail: its door).
		for e in [[z0, i - 1], [z1, i + 1]]:
			var other_hw := 0.0
			var other_ceil := ceil
			if e[1] >= 0 and e[1] < ROOMS.size():
				other_hw = minf(ROOMS[e[1]][1], hw)
				other_ceil = minf(ROOMS[e[1]][4], ceil)
			if e[1] >= ROOMS.size():
				continue   # (the tail: the door)
			if other_hw <= 0.0:
				_box(Vector3(hw * 2.0, h, 0.2), Vector3(0, FLOOR + h * 0.5, e[0]), "wall")
				continue
			if other_hw < hw:
				for side in [-1.0, 1.0]:
					_box(Vector3(hw - other_hw, h, 0.2), Vector3(side * (hw + other_hw) * 0.5, FLOOR + h * 0.5, e[0]), "wall")
			if other_ceil < ceil:
				_box(Vector3(other_hw * 2.0, ceil - other_ceil, 0.2), Vector3(0, (ceil + other_ceil) * 0.5, e[0]), "wall")
	# The tail's door (slides up into the hull) and its frame.
	var aft: Array = ROOMS[ROOMS.size() - 1]
	_door = _box(Vector3(float(aft[1]) * 2.0, float(aft[4]) - FLOOR, 0.15), Vector3(0, (float(aft[4]) + FLOOR) * 0.5, float(aft[3])), "trim")
	_box(Vector3(float(aft[1]) * 2.0 + 0.4, 0.18, 0.3), Vector3(0, FLOOR - 0.05, float(aft[3])), "dark")
	# The cockpit: the seat, the console, the canopy's window (glowing).
	_box(Vector3(1.0, 1.0, 1.0), SEAT + Vector3(0, 0.5, 0), "dark")
	_box(Vector3(1.0, 1.2, 0.2), SEAT + Vector3(0, 1.2, 0.5), "dark")
	_box(Vector3(3.6, 0.9, 0.8), Vector3(0, FLOOR + 0.45, -14.4), "dark")
	_box(Vector3(3.2, 0.5, 0.06), Vector3(0, FLOOR + 1.2, -14.6), "screen").rotation.x = -0.4
	# The terminals: a console, a screen, a label.
	for t in TERMINALS:
		var at: Vector3 = t[2] + Vector3(0, FLOOR, 0)
		var side := signf(at.x)
		_box(Vector3(0.6, 1.0, 1.4), at + Vector3(side * 0.1, 0.5, 0), "dark")
		var scr := _box(Vector3(0.06, 0.8, 1.2), at + Vector3(side * -0.15, 1.45, 0), "screen")
		scr.rotation.z = side * 0.25
		var l := Label3D.new()
		l.text = t[0]
		l.font_size = 48
		l.pixel_size = 0.006
		l.position = at + Vector3(side * -0.4, 2.25, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = accent.lerp(Color.WHITE, 0.6)
		add_child(l)
	# The ramp: out of the floor at the tail, on its hinge.
	_ramp = Node3D.new()
	_ramp.position = Vector3(0, FLOOR, RAMP[1])
	add_child(_ramp)
	_ramp_plank = MeshInstance3D.new()
	_ramp_plank.mesh = CosmosStation._box(Vector3(RAMP[0] * 2.0, 0.18, RAMP[2]))
	_ramp_plank.material_override = _mats["trim"]
	_ramp_plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ramp.add_child(_ramp_plank)
	_crates = Node3D.new()
	add_child(_crates)
	set_ramp(false)


## An inside surface: matte, no metal (it would mirror the sky outside), dull specular.
static func _inner(c: Color, rough: float, glow := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.0
	m.metallic_specular = 0.15
	m.roughness = rough
	if glow != Color.BLACK:
		m.emission_enabled = true
		m.emission = glow
	return m


func _box(size: Vector3, at: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = CosmosStation._box(size)
	mi.material_override = _mats[mat]
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # (the inside: lit from its ceiling)
	add_child(mi)
	return mi


## Opens (the door up, then the ramp out) or shuts (the ramp in, then the door) - over a few seconds.
func set_ramp(down: bool) -> void:
	want_open = down


func _process(delta: float) -> void:
	if want_open:
		if door_t < 1.0:
			door_t = minf(1.0, door_t + delta / DOOR_TIME)
		else:
			ramp_t = minf(1.0, ramp_t + delta / RAMP_TIME)
	else:
		if ramp_t > 0.0:
			ramp_t = maxf(0.0, ramp_t - delta / RAMP_TIME)
		else:
			door_t = maxf(0.0, door_t - delta / DOOR_TIME)
	ramp_down = ramp_t >= 1.0
	_pose()


## The door and ramp where door_t / ramp_t put them.
func _pose() -> void:
	if _door == null:
		return
	var aft: Array = ROOMS[ROOMS.size() - 1]
	var dh := float(aft[4]) - FLOOR
	_door.position.y = FLOOR + dh * 0.5 + dh * smoothstep(0.0, 1.0, door_t)
	_door.visible = door_t < 0.99
	var drop := FLOOR - ramp_end_y
	var ang := asin(clampf(drop / RAMP[2], -1.0, 1.0))
	_ramp.rotation.x = -ang
	var out := smoothstep(0.0, 1.0, ramp_t)
	_ramp.visible = out > 0.01
	_ramp_plank.scale = Vector3(1.0, 1.0, maxf(out, 0.01))
	_ramp_plank.position = Vector3(0, -0.09, RAMP[2] * out * 0.5)


## The ramp's foot (its z, ship space) as it lies now.
func foot_z() -> float:
	var drop := FLOOR - ramp_end_y
	return RAMP[1] + sqrt(maxf(RAMP[2] * RAMP[2] - drop * drop, 1.0))


## Crates in the hold for what you carry (a crate a few units).
func stack_cargo(units: int) -> void:
	for c in _crates.get_children():
		c.queue_free()
	var n := mini(units / 4 + (1 if units > 0 else 0), 24)
	for i in n:
		var row := i / 6
		var col := i % 6
		var side := -1.0 if col < 3 else 1.0
		var x := side * (2.6 - (col % 3) * 0.0)
		var z := 7.0 + (col % 3) * 1.3 + row * 0.0
		var y := FLOOR + 0.45 + row * 0.9
		var c := MeshInstance3D.new()
		c.mesh = CosmosStation._box(Vector3(1.0, 0.85, 1.2))
		c.material_override = _mats["crate"]
		c.position = Vector3(x, y, z)
		_crates.add_child(c)


# --- The walker's deck --------------------------------------------------------

func _rects() -> Array:
	var out: Array = []
	for r in ROOMS:
		out.append([-float(r[1]), float(r[2]), float(r[1]), float(r[3])])
	if ramp_down:
		out.append([-float(RAMP[0]), float(RAMP[1]), float(RAMP[0]), foot_z()])
	return out


## On the ramp (ship space)?
func on_ramp(l: Vector3) -> bool:
	return ramp_down and absf(l.x) <= RAMP[0] + 0.01 and l.z > RAMP[1]   # (past its foot: its foot's height - you step off level)


## The floor's height at ship-space `l` (the ramp slopes down to the ground).
func floor_y(l: Vector3) -> float:
	if on_ramp(l):
		var k := clampf((l.z - RAMP[1]) / (foot_z() - RAMP[1]), 0.0, 1.0)
		return lerpf(FLOOR, ramp_end_y, k)
	return FLOOR


func ceiling_y(l: Vector3) -> float:
	if on_ramp(l):
		return floor_y(l) + 3.2
	for r in ROOMS:
		if l.z >= float(r[2]) - 0.01 and l.z <= float(r[3]) + 0.01 and absf(l.x) <= float(r[1]) + 0.01:
			return float(r[4])
	return CEIL


## `l` kept within the rooms (and the ramp), `m` in from their walls.
func confine(l: Vector3, m: float) -> Vector3:
	var best := l
	var bd := INF
	var first := float(ROOMS[0][2])
	var last := float(ROOMS[ROOMS.size() - 1][3])
	for r in _rects():
		# (margins off the side walls and the outer ends - not where rooms join)
		var x := clampf(l.x, r[0] + m, r[2] - m)
		# (the tail's end: a wall only while the door's shut - open, the ramp goes on from it)
		var z := clampf(l.z, r[1] + (m if is_equal_approx(r[1], first) else 0.0), r[3] - (m if is_equal_approx(r[3], last) and not ramp_down else 0.0))
		var d := Vector2(x - l.x, z - l.z).length()
		if d < bd:
			bd = d
			best = Vector3(x, l.y, z)
	return best


## The terminal within reach of ship-space `l`: [label, Ship Computer tab, position] or [].
func terminal_near(l: Vector3) -> Array:
	for t in TERMINALS:
		if Vector2(l.x - t[2].x, l.z - t[2].z).length() < 1.6:
			return t
	return []


func at_seat(l: Vector3) -> bool:
	return Vector2(l.x - SEAT.x, l.z - SEAT.z).length() < 1.8


## The end of the lowered ramp (ship space): stepping off it, you're outside.
func ramp_foot() -> Vector3:
	return Vector3(0, ramp_end_y, foot_z())
