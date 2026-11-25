class_name CosmosShipInterior
extends Node3D
## The inside of your ship (the 3D game), in the Minoan way (EmpireKit's look):
## the bridge in the nose - the captain's throne on its lit dais (E takes the
## controls), two crew seats at the consoles under the windows, the bull's
## banners, a hologram of the stars; through an arch the quarters (a bed, a
## couch, shelves, a rug); then the loading bay - your cargo in the stores'
## crates, a crane over them, lamps along the deck - and the tail's door, its
## ramp let down when landed (the way in and out). The ship's terminals (the
## Automaton's pages) on the bridge and in the bay. A deck for
## CosmosWalker: floor_y / ceiling_y / confine in the ship's own space.

const FLOOR := -1.4
const CEIL := 2.0
## The rooms: [name, x half width, z from, z to, ceiling] (ship space: -z is the nose).
const ROOMS := [["bridge", 5.2, -20.0, -9.0, 2.4], ["quarters", 3.8, -9.0, 2.0, 2.0],
	["hold", 5.4, 2.0, 18.0, 2.8], ["aft", 3.4, 18.0, 22.4, 2.0]]
const RAMP := [3.0, 22.4, 6.6]           # half width, its hinge's z (the tail's door), its length
const DOOR_TIME := 2.2                   # (the door swinging down, on its hinge at the deck)
const RAMP_TIME := 1.4                   # (its second section sliding out to the ground)
const DOOR_T := 0.26                     # the door's thickness
const SEAT := Vector3(0, FLOOR, -14.0)
## [label, what it opens - an Automaton tab (int) or a device of the ship's own ("refinery", "fabricator": DeviceMenu), position]
const TERMINALS := [["Fabricator", "fabricator", Vector3(4.5, 0, -17.2)], ["Star Map", 2, Vector3(3.3, 0, -11.2)],
	["Inventory", 0, Vector3(-4.7, 0, 6.0)], ["Refinery", "refinery", Vector3(4.7, 0, 6.0)]]
const HOLO := Vector3(3.3, FLOOR, -11.2)   # (the star map's globe, on its pedestal)

var ramp_down := false                   # (open and out: walkable)
var want_open := false
var door_t := 0.0                        # 0 shut .. 1 up in the hull
var ramp_t := 0.0                        # 0 in .. 1 out on the ground
var ramp_end_y := -CosmosShip.GEAR       # where the ground is under its foot (ship space)
var _ramp: Node3D                        # (the hinge, at the deck's end)
var _ramp_plank: MeshInstance3D          # (the second section, sliding out of the door)
var _door: MeshInstance3D                # (the door: shut it stands in the tail; down, the ramp's first part)
var _struts: Array = []                  # [cylinder, its end on the hull] - the rams pushing it
var _crates: Array = []                  # [plain, red]: MultiMeshInstance3D
var _globe: Node3D
var _lights: Array = []
var _labels: Array = []
var _lit := false

static var _arrays: Array = []
static var _task := -1


## The rooms' mesh (all that doesn't move): on a worker from the title (CosmosWarm), else here.
static func start_dress(soon := false) -> void:
	if _arrays.is_empty() and _task < 0:
		_task = Jobs.add(func(): _arrays = dress(), soon, "ship interior")


static func dress_ready() -> bool:
	return not _arrays.is_empty() or (_task >= 0 and Jobs.done(_task))


## Its build collected if it was started (leaving the game: no task left in the pool).
static func finish_tasks() -> void:
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1


static func dress_arrays() -> Array:
	start_dress()
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1
	return _arrays


var built := false      # (its rooms made - CosmosShip.parts_in: when their worker's done)
var _cargo_wait := -1   # (cargo stacked before the rooms were in)


func _ready() -> void:
	name = "Interior"


func build(_accent: Color) -> void:
	built = true
	name = "Interior"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, dress_arrays())
	var mi := MeshInstance3D.new()
	mi.name = "Rooms"
	mi.mesh = mesh
	mi.material_override = EmpireKit.mat("inside")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # (the inside: lit by its lamps)
	add_child(mi)
	# The terminals' names over them.
	for t in TERMINALS:
		var at: Vector3 = t[2] + Vector3(0, FLOOR, 0)
		var l := Label3D.new()
		l.text = t[0]
		l.font_size = 48
		l.pixel_size = 0.006
		l.position = at + Vector3(-signf(at.x) * 0.4 if t[0] != "Star Map" else 0.0, 2.35, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color(1.0, 0.86, 0.66)
		l.visible = false   # (aboard only: not through the windows)
		add_child(l)
		_labels.append(l)
	# The star map's globe: a hologram over its pedestal, turning.
	_globe = Node3D.new()
	_globe.position = HOLO + Vector3(0, 1.75, 0)
	add_child(_globe)
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	sphere.radial_segments = 24
	sphere.rings = 12
	for k in 3:
		var part := MeshInstance3D.new()
		if k == 0:
			part.mesh = sphere
		else:
			var t := TorusMesh.new()
			t.inner_radius = 0.72 + k * 0.12
			t.outer_radius = 0.75 + k * 0.12
			t.rings = 48
			t.ring_segments = 4
			part.mesh = t
			part.rotation = Vector3(0.35 * k, 0, 0.25 * k)
		part.material_override = EmpireKit.holo()
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_globe.add_child(part)
	# The tail's door (slides up into the hull).
	var aft: Array = ROOMS[ROOMS.size() - 1]
	# The loading door: hinged at the deck's end - shut, it stands in the tail's
	# opening (its outside the hull's paint); it swings out and down, its inside
	# (a steel deck, hazard edges, lamps) the ramp's first part; the second part
	# slides out of it to the ground. Two rams push it.
	_ramp = Node3D.new()
	_ramp.position = Vector3(0, FLOOR, RAMP[1])
	add_child(_ramp)
	_door = MeshInstance3D.new()
	_door.mesh = _door_mesh(float(aft[1]), float(aft[4]) - FLOOR)
	_door.material_override = EmpireKit.mat("hull")
	_ramp.add_child(_door)
	_ramp_plank = MeshInstance3D.new()
	_ramp_plank.mesh = _plank_mesh(RAMP[0] - 0.2, _ext_len())
	_ramp_plank.material_override = EmpireKit.mat("hull")
	_ramp_plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ramp.add_child(_ramp_plank)
	for sx in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		c.mesh = CosmosStation._cyl(0.09, 0.13, 1.0, 8)
		c.material_override = EmpireKit.zone_mat(EmpireKit.STEEL)
		add_child(c)
		_struts.append([c, Vector3(sx * (float(aft[1]) - 0.35), float(aft[4]) - 0.4, RAMP[1] - 0.9)])
	for red in [false, true]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = EmpireKit.crate_mesh(red)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = EmpireKit.mat("inside")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_crates.append(mmi)
	# Warm lamps (on while you're aboard - CosmosShip.set_aboard): the bridge, the quarters, the bay.
	for l in [[Vector3(0, 1.9, -14.5), 10.0, 0.7], [Vector3(0, 1.6, -3.5), 7.0, 0.5], [Vector3(0, 2.3, 10.0), 11.0, 0.6]]:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.omni_range = l[1]
		o.light_energy = l[2]
		o.light_color = Color(1.0, 0.78, 0.55)
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_lights.append(o)
	set_ramp(false)
	if _cargo_wait >= 0:
		stack_cargo(_cargo_wait)
		_cargo_wait = -1
	if _lit:
		_lit = false
		set_lit(true)


## The door's first part (its length the opening's height): `hw` half wide, `l` long, along +z from its hinge.
static func _door_mesh(hw: float, l: float) -> ArrayMesh:
	var m := EmpireKit.Mesher.new()
	var t := DOOR_T
	m.box(Vector3(hw * 2.0, t, l), Transform3D(Basis.IDENTITY, Vector3(0, -t * 0.5, l * 0.5)), EmpireKit.STEEL)
	# (its outside - the hull's when shut: cream, a red band, the frame's ribs)
	m.panel(Vector3(0, -t - 0.01, l * 0.5), Vector3(hw - 0.05, 0, 0), Vector3(0, 0, l * 0.5 - 0.05), EmpireKit.MAIN, Vector3.DOWN)
	m.panel(Vector3(0, -t - 0.02, l * 0.62), Vector3(hw - 0.05, 0, 0), Vector3(0, 0, 0.32), EmpireKit.ACCENT, Vector3.DOWN)
	for z in [0.35, l - 0.35]:
		m.box(Vector3(hw * 2.0 - 0.2, 0.08, 0.16), Transform3D(Basis.IDENTITY, Vector3(0, -t - 0.04, z)), EmpireKit.IRON)
	# (its inside - the deck down: hazard edges, treads, lamps along it)
	for sx in [-1.0, 1.0]:
		m.box(Vector3(0.35, 0.03, l - 0.1), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.2), 0.015, l * 0.5)), EmpireKit.HAZARD)
		m.box(Vector3(0.08, 0.06, l - 0.4), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.42), 0.03, l * 0.5)), EmpireKit.LAMP)
	for k in int(l / 0.45):
		m.box(Vector3(hw * 2.0 - 1.0, 0.03, 0.06), Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0.3 + k * 0.45)), EmpireKit.IRON)
	return m.commit()


## The second part: a steel plank, treads, lamps; along +z from its back end.
static func _plank_mesh(hw: float, l: float) -> ArrayMesh:
	var m := EmpireKit.Mesher.new()
	m.box(Vector3(hw * 2.0, 0.16, l), Transform3D(Basis.IDENTITY, Vector3(0, -0.08, l * 0.5)), EmpireKit.STEEL)
	for sx in [-1.0, 1.0]:
		m.box(Vector3(0.3, 0.03, l - 0.1), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.18), 0.015, l * 0.5)), EmpireKit.HAZARD)
		m.box(Vector3(0.07, 0.05, 0.5), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.4), 0.025, l - 0.35)), EmpireKit.LAMP)
	for k in int(l / 0.45):
		m.box(Vector3(hw * 2.0 - 0.9, 0.03, 0.06), Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0.25 + k * 0.45)), EmpireKit.IRON)
	return m.commit()


## How long the second part is (with the door, the ramp's whole length; a little overlap).
static func _ext_len() -> float:
	var aft: Array = ROOMS[ROOMS.size() - 1]
	return RAMP[2] - (float(aft[4]) - FLOOR) + 0.3


## Its lamps on (you're aboard) or off (nothing in here to see from outside).
func set_lit(on: bool) -> void:
	if on == _lit:
		return
	_lit = on
	for o: OmniLight3D in _lights:
		o.visible = on
	for l: Label3D in _labels:
		l.visible = on


# --- The rooms' mesh ---------------------------------------------------------------

static func dress() -> Array:
	var m := EmpireKit.Mesher.new()
	_shell(m)
	_bridge(m)
	_quarters(m)
	_bay(m)
	return m.arrays()


## Floors, ceilings, walls (open where the rooms join; the bridge's front open
## above its consoles - the windows in the nose), ribs, lamps, trims.
static func _shell(m: EmpireKit.Mesher) -> void:
	for i in ROOMS.size():
		var r: Array = ROOMS[i]
		var hw: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var ceil: float = r[4]
		var h := ceil - FLOOR
		var mid := (z0 + z1) * 0.5
		var len := z1 - z0
		m.boxat(Vector3(hw * 2.0, 0.2, len), Vector3(0, FLOOR - 0.1, mid), EmpireKit.IRON)
		m.boxat(Vector3(hw * 2.0, 0.2, len), Vector3(0, ceil + 0.1, mid), EmpireKit.IRON)
		for side in [-1.0, 1.0]:
			m.boxat(Vector3(0.2, h, len), Vector3(side * (hw + 0.1), FLOOR + h * 0.5, mid), EmpireKit.MAIN)
			m.boxat(Vector3(0.05, 0.14, len), Vector3(side * hw, FLOOR + 1.05, mid), EmpireKit.ACCENT)     # (a red band)
			m.boxat(Vector3(0.12, 0.04, len - 0.4), Vector3(side * (hw - 0.06), FLOOR + 0.02, mid), EmpireKit.LAMP)   # (the deck's edge lit)
		# Ribs across, lamps between them.
		var n := maxi(2, int(len / 2.6))
		for k in n + 1:
			var z := z0 + 0.2 + (len - 0.4) * k / n
			for side in [-1.0, 1.0]:
				m.boxat(Vector3(0.3, h, 0.35), Vector3(side * (hw - 0.15), FLOOR + h * 0.5, z), EmpireKit.STEEL)
			m.boxat(Vector3(hw * 2.0, 0.28, 0.35), Vector3(0, ceil - 0.14, z), EmpireKit.STEEL)
			if k < n:
				for side in [-1.0, 1.0]:
					m.boxat(Vector3(0.5, 0.06, len / n - 0.9), Vector3(side * hw * 0.45, ceil - 0.03, z + (len - 0.4) / n * 0.5), EmpireKit.LAMP)
		# End walls, open where the next room joins (the tail: its door; the bridge's front: the windows).
		for e in [[z0, i - 1], [z1, i + 1]]:
			if e[1] >= ROOMS.size():
				continue
			if e[1] < 0:
				m.boxat(Vector3(hw * 2.0, 1.0, 0.2), Vector3(0, FLOOR + 0.5, e[0]), EmpireKit.MAIN)
				for sx in [-2.6, 2.6]:   # (the windows' posts)
					m.boxat(Vector3(0.22, h - 1.0, 0.22), Vector3(sx, FLOOR + 1.0 + (h - 1.0) * 0.5, e[0]), EmpireKit.STEEL)
				continue
			var other_hw := minf(ROOMS[e[1]][1], hw)
			var other_ceil := minf(ROOMS[e[1]][4], ceil)
			if other_hw < hw:
				for side in [-1.0, 1.0]:
					m.boxat(Vector3(hw - other_hw, h, 0.2), Vector3(side * (hw + other_hw) * 0.5, FLOOR + h * 0.5, e[0]), EmpireKit.MAIN)
			if other_ceil < ceil:
				m.boxat(Vector3(other_hw * 2.0, ceil - other_ceil, 0.2), Vector3(0, (ceil + other_ceil) * 0.5, e[0]), EmpireKit.MAIN)
	# The nose under the windows (not walked): a lower deck, consoles facing back.
	m.boxat(Vector3(9.0, 0.2, 2.6), Vector3(0, FLOOR - 0.1, -21.3), EmpireKit.IRON)
	m.boxat(Vector3(6.0, 0.2, 2.6), Vector3(0, FLOOR - 0.1, -23.9), EmpireKit.IRON)
	for sx in [-1.0, 1.0]:
		m.boxat(Vector3(2.4, 0.8, 0.7), Vector3(sx * 1.8, FLOOR + 0.4, -23.2), EmpireKit.IRON)
		m.panel(Vector3(sx * 1.8, FLOOR + 0.95, -22.9), Vector3(1.0, 0, 0), Vector3(0, -0.15, 0.2), EmpireKit.SCREEN, Vector3(0, 0.8, 0.6))
	# The tail's door frame, lamps up its sides.
	var aft: Array = ROOMS[ROOMS.size() - 1]
	var dz: float = aft[3]
	for sx in [-1.0, 1.0]:
		m.boxat(Vector3(0.1, float(aft[4]) - FLOOR - 0.3, 0.12), Vector3(sx * (float(aft[1]) - 0.1), (float(aft[4]) + FLOOR) * 0.5, dz - 0.2), EmpireKit.LAMP)
	m.boxat(Vector3(float(aft[1]) * 2.0, 0.04, 0.6), Vector3(0, FLOOR + 0.01, dz - 0.4), EmpireKit.HAZARD)


## A Minoan seat: a steel base on a pedestal, cream leather, red bolsters, its armrests' screens; facing -z.
static func _chair(m: EmpireKit.Mesher, at: Vector3, k: float, crest := false) -> void:
	var b := func(size: Vector3, p: Vector3, zone: int, tilt: float) -> void:
		m.box(size * k, Transform3D(Basis(Vector3.RIGHT, tilt), at + p * k), zone)
	m.cyl(at, at + Vector3(0, 0.38 * k, 0), 0.42 * k, 0.32 * k, EmpireKit.STEEL, 12)
	b.call(Vector3(1.0, 0.22, 0.9), Vector3(0, 0.5, 0), EmpireKit.STEEL, 0.0)
	b.call(Vector3(0.62, 0.18, 0.84), Vector3(0, 0.68, -0.02), EmpireKit.LEATHER, 0.0)
	for sx in [-1.0, 1.0]:
		b.call(Vector3(0.14, 0.22, 0.86), Vector3(sx * 0.36, 0.72, -0.02), EmpireKit.CLOTH, 0.0)
		b.call(Vector3(0.26, 0.5, 0.9), Vector3(sx * 0.56, 0.75, -0.05), EmpireKit.STEEL, 0.0)
		b.call(Vector3(0.26, 0.08, 0.86), Vector3(sx * 0.56, 1.03, -0.05), EmpireKit.LEATHER, 0.0)
		m.panel(at + Vector3(sx * 0.56, 1.075, -0.32) * k, Vector3(0.1 * k, 0, 0), Vector3(0, 0, 0.13 * k), EmpireKit.SCREEN, Vector3.UP)
		b.call(Vector3(0.16, 1.0, 0.24), Vector3(sx * 0.4, 1.3, 0.42), EmpireKit.CLOTH, 0.12)
	b.call(Vector3(0.66, 1.0, 0.22), Vector3(0, 1.3, 0.44), EmpireKit.LEATHER, 0.12)
	b.call(Vector3(0.9, 1.1, 0.12), Vector3(0, 1.3, 0.58), EmpireKit.STEEL, 0.12)
	b.call(Vector3(0.7, 0.32, 0.26), Vector3(0, 1.95, 0.52), EmpireKit.CLOTH, 0.12)
	if crest:
		m.disc(at + Vector3(0, 1.95, 0.37) * k, Vector3(0, 0.12, -1).normalized(), Vector3.UP, 0.12 * k, EmpireKit.ROUNDEL, 16)


## A potted plant (a few broad leaves).
static func _plant(m: EmpireKit.Mesher, at: Vector3, s := 1.0) -> void:
	m.cyl(at, at + Vector3(0, 0.55 * s, 0), 0.26 * s, 0.34 * s, EmpireKit.MAIN, 10)
	for i in 9:
		var a := TAU * i / 9.0 + 0.3
		var lean := 0.5 + 0.35 * float(i % 3) / 2.0
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, lean)
		m.box(Vector3(0.28, 0.9, 0.05) * s, Transform3D(b, at + Vector3(0, 0.55 * s, 0) + b * Vector3(0, 0.45 * s, 0)), EmpireKit.LEAVES)


## A console against a wall (`side`: which wall), its screen tilted to you.
static func _console(m: EmpireKit.Mesher, at: Vector3, side: float) -> void:
	m.boxat(Vector3(0.7, 1.05, 1.5), at + Vector3(side * 0.1, 0.525, 0), EmpireKit.STEEL)
	m.boxat(Vector3(0.72, 0.06, 1.52), at + Vector3(side * 0.1, 1.06, 0), EmpireKit.IRON)
	m.boxat(Vector3(0.06, 0.06, 1.3), at + Vector3(side * -0.26, 0.2, 0), EmpireKit.LAMP)
	var scr := at + Vector3(side * -0.05, 1.5, 0)
	m.boxat(Vector3(0.12, 0.85, 1.4), scr + Vector3(side * 0.08, 0, 0), EmpireKit.IRON)
	m.panel(scr + Vector3(side * 0.01, 0, 0), Vector3(0, 0, 0.62), Vector3(side * 0.08, -0.38, 0), EmpireKit.SCREEN, Vector3(-side, 0.2, 0))


static func _banner(m: EmpireKit.Mesher, at: Vector3, facing: Vector3, w := 0.75, h := 1.3) -> void:
	var right := facing.cross(Vector3.UP).normalized() * w
	m.panel(at, right, Vector3(0, -h, 0), EmpireKit.BANNER, facing)
	m.cyl(at + Vector3(0, h + 0.06, 0) - right * 1.15, at + Vector3(0, h + 0.06, 0) + right * 1.15, 0.035, 0.035, EmpireKit.STEEL, 6)


static func _bridge(m: EmpireKit.Mesher) -> void:
	# The dais, its lit rim, the throne.
	m.cyl(SEAT, SEAT + Vector3(0, 0.1, 0), 2.4, 2.4, EmpireKit.STEEL, 40)
	m.cyl(SEAT + Vector3(0, 0.02, 0), SEAT + Vector3(0, 0.08, 0), 2.43, 2.43, EmpireKit.LAMP, 40, false)
	m.cyl(SEAT + Vector3(0, 0.1, 0), SEAT + Vector3(0, 0.16, 0), 1.5, 1.5, EmpireKit.IRON, 32)
	for k in 4:   # (lamps round its foot)
		var a := TAU * (k + 0.5) / 4.0
		m.boxat(Vector3(0.5, 0.14, 0.18), SEAT + Vector3(cos(a) * 2.5, 0.07, sin(a) * 2.5), EmpireKit.LAMP, -a)
	_chair(m, SEAT + Vector3(0, 0.16, 0), 1.15, true)
	# The consoles under the windows, the crew's seats at them.
	m.boxat(Vector3(9.8, 0.95, 0.9), Vector3(0, FLOOR + 0.475, -19.35), EmpireKit.STEEL)
	m.boxat(Vector3(9.8, 0.06, 0.95), Vector3(0, FLOOR + 0.97, -19.35), EmpireKit.IRON)
	m.boxat(Vector3(9.6, 0.05, 0.05), Vector3(0, FLOOR + 0.2, -18.88), EmpireKit.LAMP)
	for x in [-3.6, -1.2, 1.2, 3.6]:
		m.panel(Vector3(x, FLOOR + 1.25, -19.45), Vector3(1.0, 0, 0), Vector3(0, -0.24, -0.12), EmpireKit.SCREEN, Vector3(0, 0.45, 1))
	for sx in [-2.6, 2.6]:
		_chair(m, Vector3(sx, FLOOR, -17.6), 0.85)
	# The banners, the plants, the hologram's pedestal.
	for sx in [-1.0, 1.0]:
		_banner(m, Vector3(sx * 5.15, 0.75, -14.2), Vector3(-sx, 0, 0))
		_plant(m, Vector3(sx * 4.5, FLOOR, -9.8))
	m.cyl(HOLO, HOLO + Vector3(0, 0.9, 0), 0.7, 0.5, EmpireKit.STEEL, 20)
	m.cyl(HOLO + Vector3(0, 0.9, 0), HOLO + Vector3(0, 0.98, 0), 0.62, 0.62, EmpireKit.LAMP, 20)
	m.disc(HOLO + Vector3(0, 0.985, 0), Vector3.UP, Vector3.FORWARD, 0.55, EmpireKit.SCREEN, 24)
	# The other terminals.
	for t in TERMINALS:
		if t[0] == "Star Map" or float(t[2].z) > 0.0:
			continue
		_console(m, t[2] + Vector3(0, FLOOR, 0), signf(t[2].x))
	# The floor's medallion; the runner into the quarters.
	m.disc(Vector3(0, FLOOR + 0.012, -10.4), Vector3.UP, Vector3.FORWARD, 0.75, EmpireKit.ROUNDEL, 32)
	m.panel(Vector3(0, FLOOR + 0.01, -5.0), Vector3(0.7, 0, 0), Vector3(0, 0, 4.2), EmpireKit.CLOTH, Vector3.UP, 1.0)


static func _quarters(m: EmpireKit.Mesher) -> void:
	# The arch from the bridge: a lintel with a red band.
	m.boxat(Vector3(7.6, 0.4, 0.3), Vector3(0, 1.8, -8.9), EmpireKit.STEEL)
	m.panel(Vector3(0, 1.8, -9.06), Vector3(3.6, 0, 0), Vector3(0, -0.14, 0), EmpireKit.CLOTH, Vector3(0, 0, -1), 1.0)
	# The bed (head to the front wall), its lamp, the shelves.
	var bed := Vector3(-2.65, FLOOR, -6.6)
	m.boxat(Vector3(1.9, 0.42, 2.5), bed + Vector3(0, 0.21, 0), EmpireKit.STEEL)
	m.boxat(Vector3(1.8, 0.22, 2.4), bed + Vector3(0, 0.53, 0), EmpireKit.LEATHER)
	m.boxat(Vector3(1.84, 0.06, 1.5), bed + Vector3(0, 0.66, 0.45), EmpireKit.CLOTH)
	for sx in [-0.45, 0.45]:
		m.boxat(Vector3(0.7, 0.14, 0.42), bed + Vector3(sx, 0.7, -0.9), EmpireKit.LEATHER)
	m.boxat(Vector3(1.9, 1.0, 0.16), bed + Vector3(0, 0.6, -1.32), EmpireKit.CLOTH)
	m.boxat(Vector3(0.5, 0.5, 0.5), bed + Vector3(1.25, 0.25, -1.0), EmpireKit.STEEL)
	m.cyl(bed + Vector3(1.25, 0.5, -1.0), bed + Vector3(1.25, 0.85, -1.0), 0.04, 0.04, EmpireKit.STEEL, 6)
	m.boxat(Vector3(0.22, 0.2, 0.22), bed + Vector3(1.25, 0.92, -1.0), EmpireKit.LAMP)
	for k in 3:
		var y := FLOOR + 0.8 + k * 0.5
		m.boxat(Vector3(0.36, 0.05, 2.2), Vector3(-3.6, y, -2.8), EmpireKit.STEEL)
		for j in 4:
			m.boxat(Vector3(0.22, 0.2 + 0.08 * ((j + k) % 3), 0.18), Vector3(-3.55, y + 0.13, -3.6 + j * 0.5 + k * 0.1), [EmpireKit.ACCENT, EmpireKit.MAIN, EmpireKit.LEATHER, EmpireKit.IRON][(j + k) % 4])
	# The couch, a low table, a plant, the rug.
	var couch := Vector3(2.85, FLOOR, -4.6)
	m.boxat(Vector3(0.9, 0.42, 2.6), couch + Vector3(0, 0.21, 0), EmpireKit.STEEL)
	m.boxat(Vector3(0.84, 0.18, 2.4), couch + Vector3(-0.02, 0.51, 0), EmpireKit.LEATHER)
	m.boxat(Vector3(0.22, 0.7, 2.6), couch + Vector3(0.38, 0.75, 0), EmpireKit.CLOTH)
	for sz in [-1.0, 1.0]:
		m.boxat(Vector3(0.9, 0.62, 0.2), couch + Vector3(0, 0.45, sz * 1.3), EmpireKit.CLOTH)
	m.boxat(Vector3(0.7, 0.36, 1.2), Vector3(1.5, FLOOR + 0.18, -4.6), EmpireKit.STEEL)
	_plant(m, Vector3(3.1, FLOOR, -1.2), 0.9)
	_plant(m, Vector3(-3.2, FLOOR, -8.3), 0.8)
	m.panel(Vector3(-1.2, FLOOR + 0.012, -4.2), Vector3(1.0, 0, 0), Vector3(0, 0, 1.6), EmpireKit.CLOTH, Vector3.UP, 1.0)
	_banner(m, Vector3(0, 0.6, 1.82), Vector3(0, 0, -1), 0.55, 0.9)   # (over the way into the bay - hung high)


static func _bay(m: EmpireKit.Mesher) -> void:
	for t in TERMINALS:
		if float(t[2].z) > 0.0:
			_console(m, t[2] + Vector3(0, FLOOR, 0), signf(t[2].x))
	# The crane: rails overhead, its bridge, a crate on the hook.
	for sx in [-2.2, 2.2]:
		m.boxat(Vector3(0.25, 0.3, 15.0), Vector3(sx, 2.45, 10.0), EmpireKit.STEEL)
	m.boxat(Vector3(5.0, 0.35, 0.5), Vector3(0, 2.2, 11.5), EmpireKit.ACCENT)
	m.boxat(Vector3(0.6, 0.4, 0.6), Vector3(0.4, 1.9, 11.5), EmpireKit.IRON)
	for sx in [0.1, 0.7]:
		m.cyl(Vector3(sx, 1.7, 11.5), Vector3(sx, 1.15, 11.5), 0.025, 0.025, EmpireKit.IRON, 4, false)
	EmpireKit.crate(m, Vector3(0.4, 0.45, 11.5), Vector3(1.3, 0.7, 1.0))
	# Hazard stripes round the bay's floor, its banner.
	m.boxat(Vector3(10.4, 0.02, 0.4), Vector3(0, FLOOR + 0.01, 2.4), EmpireKit.HAZARD)
	m.boxat(Vector3(10.4, 0.02, 0.4), Vector3(0, FLOOR + 0.01, 17.6), EmpireKit.HAZARD)
	_banner(m, Vector3(-5.25, 1.1, 11.0), Vector3(1, 0, 0), 0.7, 1.3)
	_banner(m, Vector3(5.25, 1.1, 11.0), Vector3(-1, 0, 0), 0.7, 1.3)


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
	if _lit and _globe:
		_globe.rotation.y += delta * 0.4
	_pose()


## Opens (the door up, then the ramp out) or shuts (the ramp in, then the door) - over a few seconds.
func set_ramp(down: bool) -> void:
	want_open = down


## The door and ramp where door_t / ramp_t put them: the door swung from
## standing (shut) down to the ground's slope, then the second part slid out
## along it; the rams from the hull to the door's middle.
func _pose() -> void:
	if not is_instance_valid(_door) or not is_instance_valid(_ramp) or not is_inside_tree():   # (not while it's being freed)
		return
	var aft: Array = ROOMS[ROOMS.size() - 1]
	var dl := float(aft[4]) - FLOOR
	var drop := FLOOR - ramp_end_y
	var ang := asin(clampf(drop / RAMP[2], -1.0, 1.0))
	# (about x: -90 degrees stands the door's +z up; +ang turns it out of the tail and down to the ground)
	var swing := smoothstep(0.0, 1.0, door_t)
	swing = swing * swing * (3.0 - 2.0 * swing)   # (slow to unlatch, slow to settle)
	_ramp.rotation.x = lerpf(-PI * 0.5, ang, swing)
	var e := _ext_len()
	var out := smoothstep(0.0, 1.0, ramp_t)
	_ramp_plank.visible = door_t > 0.98
	_ramp_plank.position = Vector3(0, -0.05, lerpf(dl - e + 0.05, RAMP[2] - e, out))   # (in under the door's deck, then out past its end)
	for st in _struts:
		var c: MeshInstance3D = st[0]
		var a: Vector3 = st[1]
		var b: Vector3 = _ramp.transform * Vector3(a.x, 0.0, dl * 0.55)   # (on the door's inner face)
		var d := b - a
		var len := d.length()
		if len < 0.05:
			c.visible = false
			continue
		c.visible = true
		var y := d / len
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		c.transform = Transform3D(Basis(x, y * len, x.cross(y)), (a + b) * 0.5)


## The ramp's foot (its z, ship space) as it lies now.
func foot_z() -> float:
	var drop := FLOOR - ramp_end_y
	return RAMP[1] + sqrt(maxf(RAMP[2] * RAMP[2] - drop * drop, 1.0))


## Crates in the bay for what you carry (a crate a few units): the stores'
## crates, plain and red, stacked two high along both walls - instances of
## two meshes (no mesh made when the cargo changes).
func stack_cargo(units: int) -> void:
	if _crates.size() < 2:
		_cargo_wait = units   # (the rooms not in yet: stacked when they are)
		return
	var n := mini(units / 4 + (1 if units > 0 else 0), 32)
	var xfs := [[], []]
	for i in n:
		var row := i / 16              # (the second layer)
		var j := i % 16
		var side := -1.0 if j % 2 == 0 else 1.0
		var slot := j / 2
		var x := side * (3.85 - (slot % 2) * 1.35)
		var z := 3.4 + (slot / 2) * 1.5 + (0.6 if slot % 2 else 0.0)
		xfs[1 if (i * 7) % 5 == 0 else 0].append(Transform3D(Basis(Vector3.UP, sin(i * 1.7) * 0.08), Vector3(x, FLOOR + row * 0.9, z)))
	for k in 2:
		var mm: MultiMesh = _crates[k].multimesh
		mm.instance_count = xfs[k].size()
		for i in xfs[k].size():
			mm.set_instance_transform(i, xfs[k][i])


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


## The terminal within reach of ship-space `l`: [label, Automaton tab or device, position] or [].
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
