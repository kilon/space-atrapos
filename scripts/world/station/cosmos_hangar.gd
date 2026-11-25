class_name CosmosHangar
extends Node3D
## A station's port - the module under one of its landing platforms
## (CosmosStation.port_transform): the pads' lifts come down through its roof
## into its hall, your ship and the traders' side by side on their decks, and
## past the hall a concourse (windows onto the ships) and a row of rooms along
## the station's outer wall, a band of windows out to space in each: the
## services hall (its terminals - the market, outfitting, the shipyard...),
## the bar, the lounge, the harbour offices (missions), the stores. All in the
## empire's look (EmpireKit, one mesh: built on a worker), lit by its lamps.
## Its people - the empire's own (CosmosNpc.people_id) - work the deck (some
## carrying crates), stand at the terminals, keep the bar, sit at their desks,
## walk from room to room; you can talk to them (E) - who they are, the news,
## work (a mission). You walk it on foot (CosmosWalker's deck mode: floor at
## y = 0 in its own space, its walls the rects of `_walk`, the furniture's
## `_blocks`).
## Its frame (the port's): x out from the station (the pads at x = 0), z along
## the platform, y up from the floor.

const HALL_H := CosmosStation.PORT_CEIL - CosmosStation.PORT_FLOOR   # the hall's height (33.6 m)
const ROOM_H := 7.5             # the concourse's and the rooms' ceilings
const CONC := 12.0              # the concourse's depth
const ROOM_W := 24.0            # a room's width (about)
## [label, the Station Menu's tab, the room it's in] (StationMenu.TABS: WORKSHOP 0, MARKET 1, OUTFITTING 2, SHIPYARD 3, DESIGNER 4, REPUTATION 6, MISSIONS 8)
const TERMINALS := [["Market", 1, "services"], ["Outfitting", 2, "services"], ["Shipyard", 3, "services"], ["Designer", 4, "services"],
	["Reputation", 6, "services"], ["Missions", 8, "offices"], ["Workshop", 0, "hall"], ["Salvage", 5, "stores"]]
const KINDS := ["services", "bar", "offices", "lounge", "stores", "lounge", "bar", "offices", "stores", "lounge"]   # (outward from the middle)
const ROOM_NAMES := {"services": "Services", "bar": "Bar", "offices": "Harbour office", "lounge": "Lounge", "stores": "Stores"}
## Who works where: [role, room kind ("hall": the deck), how many]
const STAFF := [["dock", "hall", 3], ["carrier", "hall", 2], ["guard", "hall", 2], ["visitor", "services", 3], ["bartender", "bar", 1],
	["patron", "bar", 2], ["officer", "offices", 2], ["traveller", "lounge", 2], ["traveller", "walk", 3]]
const CREW := 20                # (STAFF's total)
const ROLE_NAMES := {"dock": "Dock worker", "carrier": "Dock worker", "guard": "Port guard", "visitor": "Merchant", "bartender": "Bartender",
	"patron": "Spacer", "officer": "Harbour officer", "traveller": "Traveller"}
const GIVEN := ["Alkmene", "Ariston", "Damon", "Eudora", "Glaukos", "Hermione", "Iason", "Kallias", "Lysandra", "Melitta", "Nikias",
	"Phaidra", "Philon", "Rhode", "Sostratos", "Thais", "Timon", "Xanthe", "Zenon", "Kleio", "Myron", "Ione", "Teukros", "Eirene"]

var station: CosmosStation
var platform := 0
var H := 80.0                   # half the platform's depth (the hall: x -H .. H + 2)
var W := 175.0                  # half its width
var xi := -74.0                 # the hall's inner wall (clear of the ring: CosmosStation.PORT_INSET in from the platform's inner edge)
var xa := 82.0                  # the hall's wall (to the concourse)
var xb := 92.0                  # the concourse's wall (to the rooms)
var xr := 120.0                 # the outer wall (the windows)
var emp := ""
var built := false              # (its mesh built - the walls, the furniture)
var terminals: Array = []       # [label, tab, local position (where you stand)]
var rooms: Array = []           # {kind, z0, z1, door (B, its middle), name}
var people: Array = []          # {node, anim, role, name, path, wait, stand, walk, home, talk, area, offer}
var _crew: Array = []           # (people: the old name the tests use)
var _walk: Array = []           # walkable rects [x0, z0, x1, z1, ceiling]
var _blocks: Array = []         # furniture [x0, z0, x1, z1]
var _cells := {}                # (the blocks by where they are: Vector2i cell -> their indices; see _near_blocks)
var _cells_n := -1
var _boxes: Array = []          # the camera's solids [centre, half size]
var _glass: Array = []          # panes [centre, size, normal axis 0 x / 2 z]
var seats: Array = []           # {at (floor under it), yaw (its sitter's facing), face, kind "sit" / "stool", who (its sitter or null)}
var _lamps: Array = []          # room lights [position, colour]
var _spots: Dictionary = {}     # room kind / "hall" -> [[position, facing yaw, used]]
var _rng := RandomNumberGenerator.new()
var _task := -1
var _mesh: ArrayMesh
var _spawned := 0
var _staff: Array = []          # [role, area] to bring in, one a frame
var _near_t := 0.0
var _sync_t := 2.0
var _present := {}              # person id -> true: who's in the port now (its people, from People)
const MAX_PEOPLE := 26
const JOB_ROLE := {"bartender": ["bartender", "bar"], "officer": ["officer", "offices"], "guard": ["guard", "hall"],
	"dock": ["dock", "hall"], "carrier": ["carrier", "hall"]}
var _lights: Array = []         # the rooms' (on near the camera)


func setup(st: CosmosStation, i := 0) -> void:
	station = st
	platform = clampi(i, 0, maxi(st.platforms.size() - 1, 0))
	name = "Port%d" % platform
	add_to_group("cam_solid")   # (the camera stops short of its walls)
	_rng.seed = hash(str(st.record.get("id", ""))) + platform
	emp = str(st.record.get("empire", ""))
	if not EmpireKit.LOOKS.has(emp):
		emp = ""
	set_meta("edit_key", "hangar/%s/%s/%d" % [emp, str(st.record.get("id", "")), platform])   # (the Live Editor's edits: this port - its station's id and platform lay it out)
	if not st.platforms.is_empty():
		var pf: Dictionary = st.platforms[platform]
		H = float(pf["pd"]) * 0.5
		W = float(pf["pw"]) * 0.5
		transform = st.port_transform(platform)
	xi = -H + CosmosStation.PORT_INSET
	xa = H + 2.0
	xb = xa + 1.0 + CONC
	xr = H + CosmosStation.PORT_ROOMS
	set_meta("cam_reach", H + W + 60.0)
	_layout()
	var holes: Array = st.platforms[platform]["holes"] if not st.platforms.is_empty() else [[0.0, CosmosStation.PAD_SMALL]]
	_task = WorkerThreadPool.add_task(_build.bind(holes, _rng.seed))
	_staff = _plan_people()
	if _staff.is_empty():   # (no one in the records - a test's bare galaxy: the port's usual hands)
		for s in STAFF:
			for k in int(s[2]):
				_staff.append([s[0], s[1], "", ""])


## The rooms, the walls' rects, the terminals' places - plain numbers.
func _layout() -> void:
	var n := maxi(4, int(W * 2.0 / ROOM_W))
	var rw := W * 2.0 / n
	# (the kinds outward from the middle room)
	var order: Array = range(n)
	order.sort_custom(func(a, b): return absf(a - (n - 1) * 0.5) < absf(b - (n - 1) * 0.5))
	var kinds: Array = []
	kinds.resize(n)
	for k in n:   # (one services hall - the terminals' - the rest cycling through the others)
		kinds[order[k]] = KINDS[k] if k < KINDS.size() else KINDS[1 + (k - 1) % (KINDS.size() - 1)]
	for r in n:
		var z0 := -W + r * rw
		rooms.append({"kind": kinds[r], "z0": z0, "z1": z0 + rw, "door": Vector3(xb + 0.3, 0, z0 + rw * 0.5), "name": ROOM_NAMES[kinds[r]]})
	# Where you can walk: the hall, the concourse, the rooms, the doors between (overlapping both sides).
	_walk.append([xi + 1.0, -W + 1.0, xa, W - 1.0, HALL_H])
	_walk.append([xa + 1.0, -W + 0.5, xb, W - 0.5, ROOM_H])
	for r in rooms:
		_walk.append([xb + 0.6, float(r["z0"]) + 0.3, xr, float(r["z1"]) - 0.3, ROOM_H])
		var zc: float = r["door"].z
		_walk.append([xb - 3.0, zc - 1.6, xb + 4.0, zc + 1.6, ROOM_H])
	for zc in doors_a():
		_walk.append([xa - 4.0, zc - 2.5, xa + 5.0, zc + 2.5, ROOM_H])
	# The terminals: in the services hall along its two side walls, missions in the
	# harbour office, the workshop on the deck by the middle door.
	var serv := rooms.filter(func(r): return r["kind"] == "services")
	var offi := rooms.filter(func(r): return r["kind"] == "offices")
	var si := 0
	for t in TERMINALS:
		var at := Vector3.ZERO
		var yaw := 0.0
		match str(t[2]):
			"services":
				var r: Dictionary = serv[0]
				var side := -1.0 if si % 2 == 0 else 1.0
				var along := xb + 7.0 + (si >> 1) * 6.5
				at = Vector3(along, 0, (float(r["z0"]) + 1.6 if side < 0 else float(r["z1"]) - 1.6))
				yaw = PI if side < 0 else 0.0    # (facing the wall: -z / +z)
				si += 1
			"offices":
				var r: Dictionary = offi[0] if not offi.is_empty() else serv[0]
				at = Vector3(xb + 3.0, 0, float(r["z0"]) + 1.6)
				yaw = PI
			"stores":
				var st_r := rooms.filter(func(x): return x["kind"] == "stores")
				var r: Dictionary = st_r[0] if not st_r.is_empty() else serv[0]
				at = Vector3(xb + 3.0, 0, float(r["z1"]) - 1.6)
				yaw = 0.0
			_:
				var zs := doors_a()
				var zm: float = zs[0]
				for z in zs:
					if absf(z) < absf(zm):
						zm = z
				at = Vector3(xa - 1.6, 0, zm + 7.0)
				yaw = PI * 0.5    # (its screen to the wall: +x)
		terminals.append([t[0], t[1], at - Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.6), yaw, at])


## The doors from the hall to the concourse (z): one each side of every other room.
func doors_a() -> Array:
	var out: Array = []
	for i in rooms.size():
		if i % 2 == 0 or i == rooms.size() - 1:
			out.append(float(rooms[i]["door"].z) + (6.0 if i % 2 == 0 else -6.0))
	return out


# --- The mesh (a worker's) -----------------------------------------------------------

func _build(holes: Array, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := EmpireKit.Mesher.new()
	var bright := float(EmpireKit.look(emp)["marble"]) > 0.3
	var wall := EmpireKit.MAIN if bright else EmpireKit.IRON
	_hall(m, rng, holes, wall)
	_walls(m, wall)
	for r in rooms:
		match str(r["kind"]):
			"services": _services(m, r)
			"bar": _bar(m, rng, r)
			"lounge": _lounge(m, rng, r)
			"offices": _offices(m, rng, r)
			_: _stores(m, rng, r)
	for t in terminals:
		_terminal(m, t[4], t[3])
	_mesh = m.commit()
	_nav = _make_nav(holes)


## A box in the mesh, solid to the camera (and, `block`, to your feet).
func _solid(m: EmpireKit.Mesher, size: Vector3, at: Vector3, zone: int, block := false) -> void:
	m.boxat(size, at, zone)
	_boxes.append([at, size * 0.5])
	if block:
		_blocks.append([at.x - size.x * 0.5, at.z - size.z * 0.5, at.x + size.x * 0.5, at.z + size.z * 0.5])


func _furn(m: EmpireKit.Mesher, size: Vector3, at: Vector3, zone: int) -> void:   # (furniture: in the way of your feet, not the camera)
	m.boxat(size, at, zone)
	_blocks.append([at.x - size.x * 0.5, at.z - size.z * 0.5, at.x + size.x * 0.5, at.z + size.z * 0.5])


## A wall across x (at x0..x1) along z from z0 to z1, `top` high, its gaps
## [[z middle, half width, height]] and, `win`, a band of windows (y0, y1).
func _wall_z(m: EmpireKit.Mesher, x0: float, x1: float, z0: float, z1: float, top: float, gaps: Array, zone: int, win := Vector2.ZERO) -> void:
	var gs := gaps.duplicate()
	gs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var x := (x0 + x1) * 0.5
	var t := x1 - x0
	var z := z0
	var seg := func(a: float, b: float) -> void:
		if b - a < 0.05:
			return
		if win.y > win.x:
			_solid(m, Vector3(t, win.x, b - a), Vector3(x, win.x * 0.5, (a + b) * 0.5), zone)
			_solid(m, Vector3(t, top - win.y, b - a), Vector3(x, (win.y + top) * 0.5, (a + b) * 0.5), zone)
			_glass.append([Vector3(x, (win.x + win.y) * 0.5, (a + b) * 0.5), Vector2(b - a, win.y - win.x), 0])
			m.boxat(Vector3(t + 0.3, 0.25, b - a), Vector3(x, win.x, (a + b) * 0.5), EmpireKit.STEEL)
			m.boxat(Vector3(t + 0.3, 0.25, b - a), Vector3(x, win.y, (a + b) * 0.5), EmpireKit.STEEL)
			var k := int((b - a) / 5.0)
			for q in range(1, k):
				m.boxat(Vector3(t + 0.2, win.y - win.x, 0.25), Vector3(x, (win.x + win.y) * 0.5, a + (b - a) * q / k), EmpireKit.STEEL)
		else:
			_solid(m, Vector3(t, top, b - a), Vector3(x, top * 0.5, (a + b) * 0.5), zone)
	for g in gs:
		var a := float(g[0]) - float(g[1])
		var b := float(g[0]) + float(g[1])
		seg.call(z, a)
		_solid(m, Vector3(t, top - float(g[2]), b - a), Vector3(x, (float(g[2]) + top) * 0.5, (a + b) * 0.5), zone)
		# (its frame, a lit sill over it)
		for e in [a, b]:
			m.boxat(Vector3(t + 0.4, float(g[2]), 0.35), Vector3(x, float(g[2]) * 0.5, e), EmpireKit.ACCENT)
		m.boxat(Vector3(t + 0.4, 0.35, b - a + 0.7), Vector3(x, float(g[2]) + 0.17, float(g[0])), EmpireKit.ACCENT)
		m.boxat(Vector3(t + 0.5, 0.12, b - a - 0.4), Vector3(x, float(g[2]) - 0.1, float(g[0])), EmpireKit.LAMP)
		z = b
	seg.call(z, z1)


## The concourse's and the rooms' walls, ceilings, floors, lamps; the doors.
func _walls(m: EmpireKit.Mesher, wall: int) -> void:
	# The hall's wall: the doors to the concourse, windows onto the ships, its frieze high up.
	var ga: Array = []
	for zc in doors_a():
		ga.append([zc, 2.2, 4.6])
	_wall_z(m, xa, xa + 1.0, -W, W, HALL_H, ga, wall, Vector2(1.1, 6.2))
	m.panel(Vector3(xa - 0.05, 10.0, 0), Vector3(0, 0, W), Vector3(0, -0.8, 0), EmpireKit.FRIEZE, Vector3(-1, 0, 0), 1.0)
	m.boxat(Vector3(0.3, 0.3, W * 2.0), Vector3(xa - 0.1, 9.05, 0), EmpireKit.GOLD)
	m.boxat(Vector3(0.3, 0.3, W * 2.0), Vector3(xa - 0.1, 10.95, 0), EmpireKit.GOLD)
	m.cyl(Vector3(xa - 0.1, 21.0, 0), Vector3(xa - 0.8, 21.0, 0), 8.6, 8.6, EmpireKit.GOLD, 40)
	m.disc(Vector3(xa - 0.85, 21.0, 0), Vector3(-1, 0, 0), Vector3.UP, 8.0, EmpireKit.ROUNDEL, 48)
	for z in [-W * 0.55, W * 0.55]:
		m.panel(Vector3(xa - 0.7, 22.0, z), Vector3(0, 0, 4.0), Vector3(0, -8.5, 0), EmpireKit.BANNER, Vector3(-1, 0, 0))   # (hung clear of the wall's blocks: 0.1 m off, they cut through it)
	# The concourse's wall to the rooms: a door into each.
	var gb: Array = []
	for r in rooms:
		gb.append([float(r["door"].z), 1.6, 3.4])
	_wall_z(m, xb, xb + 0.6, -W, W, ROOM_H, gb, EmpireKit.MAIN)
	# The partitions between the rooms.
	for r in rooms.slice(1):
		_solid(m, Vector3(xr - xb, ROOM_H, 0.6), Vector3((xb + xr) * 0.5, ROOM_H * 0.5, float(r["z0"])), EmpireKit.MAIN)
	# The ceiling over the concourse and the rooms, its lamps; the floor's carpet / tiles; the concourse's light line.
	_solid(m, Vector3(xr - xa, 0.5, W * 2.0), Vector3((xa + xr) * 0.5, ROOM_H + 0.25, 0), EmpireKit.IRON)
	m.boxat(Vector3(0.5, 0.06, W * 2.0 - 2.0), Vector3(xa + 1.0 + CONC * 0.5, ROOM_H - 0.03, 0), EmpireKit.LAMP)
	m.boxat(Vector3(CONC, 0.04, W * 2.0), Vector3(xa + 1.0 + CONC * 0.5, 0.02, 0), EmpireKit.STEEL)
	for r in rooms:
		var zc: float = r["door"].z
		var z0: float = r["z0"]
		var z1: float = r["z1"]
		var x := xb + 3.0
		while x < xr - 2.0:   # (lamp strips across the ceiling, coffers between)
			m.boxat(Vector3(0.25, 0.06, (z1 - z0) - 5.0), Vector3(x, ROOM_H - 0.03, zc), EmpireKit.LAMP)
			m.boxat(Vector3(0.5, 0.35, (z1 - z0) - 0.6), Vector3(x + 2.5, ROOM_H - 0.17, zc), EmpireKit.MAIN)
			x += 5.0
		m.boxat(Vector3(xr - xb - 1.2, 0.04, z1 - z0 - 1.2), Vector3((xb + xr) * 0.5 + 0.3, 0.02, zc), EmpireKit.MAIN if r["kind"] != "stores" else EmpireKit.STEEL)
		# (the walls panelled: a dado of the accent, pilasters with gold heads, a lit cornice)
		for sz in [-1.0, 1.0]:
			var wz := (z0 + 0.32) if sz < 0 else (z1 - 0.32)
			m.boxat(Vector3(xr - xb - 0.6, 1.1, 0.08), Vector3((xb + xr) * 0.5 + 0.3, 0.55, wz - sz * 0.04), EmpireKit.ACCENT)
			m.boxat(Vector3(xr - xb - 0.6, 0.08, 0.14), Vector3((xb + xr) * 0.5 + 0.3, 1.12, wz - sz * 0.06), EmpireKit.GOLD)
			m.boxat(Vector3(xr - xb - 0.6, 0.12, 0.1), Vector3((xb + xr) * 0.5 + 0.3, ROOM_H - 0.5, wz - sz * 0.05), EmpireKit.LAMP)
			var px := xb + 4.0
			while px < xr - 1.0:
				m.boxat(Vector3(0.45, ROOM_H - 0.6, 0.22), Vector3(px, (ROOM_H - 0.6) * 0.5, wz - sz * 0.11), EmpireKit.MAIN)
				m.boxat(Vector3(0.6, 0.3, 0.3), Vector3(px, ROOM_H - 0.75, wz - sz * 0.15), EmpireKit.GOLD)
				px += 4.0
		# (the window wall's sill and its lamps, the room's frieze over the door)
		m.boxat(Vector3(0.6, 1.3, z1 - z0 - 0.6), Vector3(xr - 0.3, 0.65, zc), EmpireKit.MAIN)
		m.panel(Vector3(xb + 0.65, ROOM_H - 1.1, zc), Vector3(0, 0, (z1 - z0) * 0.5 - 0.5), Vector3(0, -0.45, 0), EmpireKit.FRIEZE, Vector3(1, 0, 0), 1.0)
		_lamps.append([Vector3((xb + xr) * 0.5, ROOM_H - 1.2, zc), str(r["kind"])])
	# (the concourse: benches between the doors, plants)
	for i in rooms.size():
		var z: float = rooms[i]["z0"]
		if i > 0:
			_furn(m, Vector3(1.0, 0.45, 4.0), Vector3(xb - 1.2, 0.22, z), EmpireKit.LEATHER)
			m.boxat(Vector3(0.3, 0.8, 4.0), Vector3(xb - 0.55, 0.6, z), EmpireKit.LEATHER)
			_plant(m, Vector3(xb - 1.2, 0, z + 3.2))
	_lamps.append([Vector3(xa + 5.0, ROOM_H - 1.0, -W * 0.5), "concourse"])
	_lamps.append([Vector3(xa + 5.0, ROOM_H - 1.0, W * 0.5), "concourse"])


## The hall: the lifts' rings of light (the pads), pillars down its inner wall
## and its ends, its frieze, banners, stacks of crates, a gantry crane, lamp
## panels overhead, lines of light on the deck.
func _hall(m: EmpireKit.Mesher, rng: RandomNumberGenerator, holes: Array, wall: int) -> void:
	var columns := emp in ["athens", "ionia", "cyclades"]
	var shaft := EmpireKit.ACCENT if emp == "ionia" else EmpireKit.MAIN
	var pillar := func(at: Vector3) -> void:
		if columns:
			m.boxat(Vector3(3.4, 1.2, 3.4), at + Vector3(0, 0.6, 0), EmpireKit.MAIN)
			m.cyl(at + Vector3(0, 1.2, 0), at + Vector3(0, HALL_H - 2.2, 0), 1.25, 1.05, shaft, 14, false)
			m.boxat(Vector3(3.6, 0.9, 3.6), at + Vector3(0, HALL_H - 1.75, 0), EmpireKit.GOLD if emp != "cyclades" else EmpireKit.MAIN)
			m.boxat(Vector3(3.0, 1.3, 3.0), at + Vector3(0, HALL_H - 0.65, 0), EmpireKit.MAIN)
		else:
			m.boxat(Vector3(2.6, HALL_H, 2.4), at + Vector3(0, HALL_H * 0.5, 0), EmpireKit.MAIN)
			if emp in ["sparta", "mycenae"]:
				m.boxat(Vector3(2.7, 0.6, 2.5), at + Vector3(0, HALL_H * 0.72, 0), EmpireKit.GOLD)
				m.boxat(Vector3(2.7, 2.4, 2.5), at + Vector3(0, 1.2, 0), EmpireKit.ACCENT)
		var px := 1.75 if columns else 1.35   # (as built: a column's plinth, or a pier and its band)
		var pz := 1.75 if columns else 1.25
		_blocks.append([at.x - px, at.z - pz, at.x + px, at.z + pz])
	var nz := int(W * 2.0 / 16.0)
	for k in nz:
		var z := -W + 8.0 + k * (W * 2.0 - 16.0) / maxf(nz - 1, 1)
		pillar.call(Vector3(xi + 1.6, 0, z))
		m.boxat(Vector3(0.25, HALL_H - 6.0, 0.2), Vector3(xi + 3.0, HALL_H * 0.5, z), EmpireKit.LAMP)
	for sz in [-1.0, 1.0]:
		var nx := int(H * 2.0 / 18.0)
		for k in nx:
			var x := xi + 12.0 + k * (H * 2.0 - 16.0) / maxf(nx, 1)
			pillar.call(Vector3(x, 0, sz * (W - 1.6)))
		m.boxat(Vector3(xa - xi, 8.0, 0.6), Vector3((xi + xa) * 0.5, 4.0, sz * (W - 0.3)), wall)
		m.panel(Vector3(1.0, 9.0, sz * (W - 0.64)), Vector3(H, 0, 0), Vector3(0, -0.7, 0), EmpireKit.FRIEZE, Vector3(0, 0, -sz), 1.0)
		m.panel(Vector3(-H * 0.4, HALL_H * 0.62, sz * (W - 1.0)), Vector3(3.5, 0, 0), Vector3(0, -7.5, 0), EmpireKit.BANNER, Vector3(0, 0, -sz))
		m.panel(Vector3(H * 0.4, HALL_H * 0.62, sz * (W - 1.0)), Vector3(3.5, 0, 0), Vector3(0, -7.5, 0), EmpireKit.BANNER, Vector3(0, 0, -sz))
	# (the inner wall's foot, its frieze and banners between the pillars)
	m.boxat(Vector3(0.6, 8.0, W * 2.0), Vector3(xi + 0.3, 4.0, 0), wall)
	m.panel(Vector3(xi + 0.64, 9.0, 0), Vector3(0, 0, W), Vector3(0, -0.7, 0), EmpireKit.FRIEZE, Vector3(1, 0, 0), 1.0)
	for k in range(1, nz, 3):
		var z := -W + 16.0 + k * (W * 2.0 - 16.0) / maxf(nz - 1, 1)
		m.panel(Vector3(xi + 1.0, HALL_H * 0.6, z), Vector3(0, 0, 3.0), Vector3(0, -6.5, 0), EmpireKit.BANNER, Vector3(1, 0, 0))
	# The pads' lifts: rings of light round each, hazard stripes, the deck's light lines between.
	var spots: Array = []
	for h in holes:
		var zc := float(h[0])
		var s := float(h[1]) * 0.5 + 1.5
		var seg := 48
		for e in seg:
			var a0 := TAU * e / seg
			var a1 := TAU * (e + 1) / seg
			for r in [s + 1.0, s + 2.2]:
				var p0 := Vector3(cos(a0) * r, 0.04, zc + sin(a0) * r)
				var p1 := Vector3(cos(a1) * r, 0.04, zc + sin(a1) * r)
				m.boxat(Vector3(0.3, 0.08, p0.distance_to(p1) + 0.05), (p0 + p1) * 0.5, EmpireKit.LAMP, atan2(p1.x - p0.x, p1.z - p0.z))
		var q := s * 0.68   # (the hazard square inside the rings: its corners clear of them)
		for e in [[Vector3(q * 2.0, 0.05, 1.0), Vector3(0, 0.025, zc + q)], [Vector3(q * 2.0, 0.05, 1.0), Vector3(0, 0.025, zc - q)],
				[Vector3(1.0, 0.05, q * 2.0), Vector3(q, 0.025, zc)], [Vector3(1.0, 0.05, q * 2.0), Vector3(-q, 0.025, zc)]]:
			m.boxat(e[0], e[1], EmpireKit.HAZARD)
		spots.append([zc, s + 3.0])
	for x in [xi + 8.0, xa - 6.0]:
		m.boxat(Vector3(0.3, 0.06, W * 1.9), Vector3(x, 0.03, 0), EmpireKit.LAMP)
	# Lamp panels overhead (under the port's roof), round the shafts.
	for i in int(H * 2.0 / 30.0):
		for j in int(W * 2.0 / 30.0):
			var at := Vector3(xi + 15.0 + i * 30.0, HALL_H - 0.3, -W + 15.0 + j * 30.0)
			var clear := true
			for sp in spots:
				if absf(at.x) < float(sp[1]) and absf(at.z - float(sp[0])) < float(sp[1]):
					clear = false
			if clear:
				m.boxat(Vector3(16.0, 0.3, 3.5), at, EmpireKit.LAMP)
	# Crates: stacks along the walls, out of the lifts' way and the doors'.
	var hall_spots: Array = []
	for k in 60:
		var at := Vector3(rng.randf_range(xi + 7.0, xa - 6.0), 0, rng.randf_range(-W + 7.0, W - 7.0))
		var bad := absf(at.x) < H * 0.55 and absf(at.z) < W * 0.9
		for sp in spots:
			if absf(at.x) < float(sp[1]) + 6.0 and absf(at.z - float(sp[0])) < float(sp[1]) + 6.0:
				bad = true
		for zc in doors_a():
			if absf(at.z - zc) < 10.0 and at.x > xa - 20.0:
				bad = true
		var yaw := rng.randf_range(-0.2, 0.2)
		var w := rng.randi_range(1, 3)
		# (never into another stack or a pillar: overlapping crates' faces fight for the same pixels)
		var foot := [at.x - 2.0, at.z - 2.3, at.x + w * 2.6 + 0.8, at.z + 2.3]
		for b in _blocks:
			if foot[0] < b[2] and foot[2] > b[0] and foot[1] < b[3] and foot[3] > b[1]:
				bad = true
				break
		if bad:
			continue
		for hh in rng.randi_range(1, 3):
			for j in w:
				EmpireKit.crate(m, at + Basis(Vector3.UP, yaw) * Vector3(j * 2.6, hh * 2.2, 0), Vector3(2.4, 2.1, 2.6), (k + hh + j) % 4 == 0, yaw)
		for j in w:   # (each column of crates solid as it stands: its turned footprint, nothing round it)
			var cc: Vector3 = at + Basis(Vector3.UP, yaw) * Vector3(j * 2.6, 0, 0)
			var hx := 1.24 * absf(cos(yaw)) + 1.34 * absf(sin(yaw))
			var hz := 1.24 * absf(sin(yaw)) + 1.34 * absf(cos(yaw))
			_blocks.append([cc.x - hx, cc.z - hz, cc.x + hx, cc.z + hz])
		hall_spots.append([at + Vector3(-2.5, 0, 0), -PI * 0.5])
	_spots["hall"] = hall_spots
	_spots["pads"] = spots
	# The gantry crane: a beam across the hall on rails, a crate on its hook.
	for sx in [-1.0, 1.0]:
		m.boxat(Vector3(xa - xi - 4.0, 1.4, 1.6), Vector3((xi + xa) * 0.5, HALL_H - 4.0, sx * (W - 8.0)), EmpireKit.IRON)
	m.boxat(Vector3(2.4, 2.2, W * 2.0 - 14.0), Vector3(-H * 0.55, HALL_H - 5.4, 0), EmpireKit.ACCENT)
	m.boxat(Vector3(4.0, 2.0, 4.0), Vector3(-H * 0.55, HALL_H - 7.4, W * 0.3), EmpireKit.IRON)
	for dz in [-0.8, 0.8]:
		m.cyl(Vector3(-H * 0.55, HALL_H - 8.4, W * 0.3 + dz), Vector3(-H * 0.55, 9.2, W * 0.3 + dz), 0.08, 0.08, EmpireKit.STEEL, 4, false)
	EmpireKit.crate(m, Vector3(-H * 0.55, 7.0, W * 0.3), Vector3(3.0, 2.2, 4.2))


## A terminal (`at` its foot, facing `yaw`): its pedestal, a console with keys
## lit, its screen tilted back, two side screens, a lamp line at its foot.
func _terminal(m: EmpireKit.Mesher, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var p := func(v: Vector3) -> Vector3: return at + b * v
	var f := b * Vector3(0, 0, -1)    # (towards you)
	m.box(Vector3(1.6, 1.0, 0.8), Transform3D(b, p.call(Vector3(0, 0.5, 0))), EmpireKit.IRON)
	m.box(Vector3(2.0, 0.12, 0.9), Transform3D(b * Basis(Vector3.RIGHT, 0.25), p.call(Vector3(0, 1.08, -0.2))), EmpireKit.STEEL)
	m.panel(p.call(Vector3(0, 1.16, -0.25)), b * Vector3(0.8, 0, 0), b * Vector3(0, -0.05, 0.25), EmpireKit.SCREEN, f + Vector3(0, 1.5, 0), 0.5)
	m.box(Vector3(2.2, 1.5, 0.15), Transform3D(b * Basis(Vector3.RIGHT, -0.12), p.call(Vector3(0, 2.1, 0.3))), EmpireKit.IRON)
	m.panel(p.call(Vector3(0, 2.1, 0.21)), b * Vector3(1.0, 0, 0), b * Basis(Vector3.RIGHT, -0.12) * Vector3(0, -0.65, 0), EmpireKit.SCREEN, f, 1.0)
	for sx in [-1.0, 1.0]:
		var sb := b * Basis(Vector3.UP, sx * 0.45)
		m.box(Vector3(0.9, 0.7, 0.1), Transform3D(sb, p.call(Vector3(sx * 1.45, 1.9, 0.15))), EmpireKit.IRON)
		m.panel(p.call(Vector3(sx * 1.45, 1.9, 0.15)) + sb * Vector3(0, 0, -0.06), sb * Vector3(0.38, 0, 0), Vector3(0, -0.28, 0), EmpireKit.SCREEN, sb * Vector3(0, 0, -1), 0.0)
	m.box(Vector3(2.4, 0.06, 0.08), Transform3D(b, p.call(Vector3(0, 0.12, -0.45))), EmpireKit.LAMP)
	m.box(Vector3(2.4, 0.2, 0.25), Transform3D(b, p.call(Vector3(0, 2.95, 0.3))), EmpireKit.ACCENT)
	var hx := absf(b.x.x) * 1.25 + absf(b.z.x) * 0.55   # (its footprint, turned)
	var hz := absf(b.x.z) * 1.25 + absf(b.z.z) * 0.55
	_blocks.append([at.x - hx, at.z - hz, at.x + hx, at.z + hz])


func _plant(m: EmpireKit.Mesher, at: Vector3) -> void:
	m.cyl(at, at + Vector3(0, 0.9, 0), 0.45, 0.55, EmpireKit.MAIN, 10)
	m.cyl(at + Vector3(0, 0.9, 0), at + Vector3(0, 1.0, 0), 0.5, 0.5, EmpireKit.GOLD, 10)
	for k in 7:
		var a := TAU * k / 7.0
		var tip := at + Vector3(cos(a) * 0.75, 1.9 + (k % 3) * 0.25, sin(a) * 0.75)
		m.cyl(at + Vector3(0, 0.95, 0), tip, 0.12, 0.03, EmpireKit.LEAVES, 4, false)
	_blocks.append([at.x - 0.6, at.z - 0.6, at.x + 0.6, at.z + 0.6])
	_boxes.append([at + Vector3(0, 1.2, 0), Vector3(0.75, 1.2, 0.75)])   # (the camera stops short of it)


func _room_spots(kind: String, list: Array) -> void:
	if not _spots.has(kind):
		_spots[kind] = []
	_spots[kind].append_array(list)


## The services hall: its terminals (placed in _layout), benches down the
## middle, the empire's emblem in the floor, a sign of the services over the window.
func _services(m: EmpireKit.Mesher, r: Dictionary) -> void:
	var zc: float = r["door"].z
	for q in 2:
		var x := xb + 9.0 + q * 9.0
		_furn(m, Vector3(5.0, 0.45, 1.0), Vector3(x, 0.22, zc), EmpireKit.LEATHER)
		m.boxat(Vector3(5.0, 0.1, 0.2), Vector3(x, 0.5, zc), EmpireKit.STEEL)
	m.disc(Vector3(xb + 13.5, 0.09, zc), Vector3.UP, Vector3(1, 0, 0), 3.2, EmpireKit.ROUNDEL, 40)
	m.cyl(Vector3(xb + 13.5, 0.0, zc), Vector3(xb + 13.5, 0.075, zc), 3.6, 3.6, EmpireKit.GOLD, 40)   # (proud of the floor: not in its plane)
	_plant(m, Vector3(xr - 2.0, 0, float(r["z0"]) + 2.0))
	_plant(m, Vector3(xr - 2.0, 0, float(r["z1"]) - 2.0))
	_room_spots("services", [[Vector3(xb + 6.0, 0, zc - 3.0), 0.0], [Vector3(xr - 4.0, 0, zc + 2.0), -PI * 0.5], [Vector3(xb + 20.0, 0, zc - 2.0), PI]])


## A seat: `at` the floor under its middle, facing `f` (the way the one in it
## looks); kind "sit" (a chair, an armchair: seat 0.46 m) or "stool" (0.80 m).
func _seat(at: Vector3, f: Vector3, kind: String) -> void:
	var g := Vector3(f.x, 0, f.z).normalized()
	seats.append({"at": at, "yaw": atan2(-g.x, -g.z), "face": g, "kind": kind, "who": null})


## A chair facing `f`: four legs, a cushioned seat, a back of two posts and a
## padded panel - wood and leather.
func _chair(m: EmpireKit.Mesher, at: Vector3, f: Vector3) -> void:
	var b := Basis(Vector3.UP, atan2(-f.x, -f.z))   # (its -z the way it faces; its back +z)
	var p := func(v: Vector3) -> Vector3: return at + b * v
	for sx in [-0.2, 0.2]:
		for sz in [-0.2, 0.2]:
			m.cyl(p.call(Vector3(sx, 0, sz)), p.call(Vector3(sx, 0.4, sz)), 0.022, 0.026, EmpireKit.WOOD, 6)
	m.box(Vector3(0.48, 0.04, 0.46), Transform3D(b, p.call(Vector3(0, 0.41, 0))), EmpireKit.WOOD)
	m.box(Vector3(0.46, 0.12, 0.44), Transform3D(b, p.call(Vector3(0, 0.34, 0))), EmpireKit.WOOD)   # (its seat rail, round under it)
	m.box(Vector3(0.44, 0.04, 0.42), Transform3D(b, p.call(Vector3(0, 0.445, -0.01))), EmpireKit.ACCENT)
	for sx in [-0.2, 0.2]:
		m.cyl(p.call(Vector3(sx, 0.43, 0.22)), p.call(Vector3(sx, 0.98, 0.25)), 0.022, 0.02, EmpireKit.WOOD, 6)
	m.box(Vector3(0.42, 0.34, 0.04), Transform3D(b * Basis(Vector3.RIGHT, -0.06), p.call(Vector3(0, 0.74, 0.24))), EmpireKit.ACCENT)
	m.box(Vector3(0.46, 0.05, 0.05), Transform3D(b, p.call(Vector3(0, 0.97, 0.25))), EmpireKit.WOOD)
	_blocks.append([at.x - 0.32, at.z - 0.32, at.x + 0.32, at.z + 0.32])
	_seat(at, f, "sit")


## A deep armchair facing `f`: a leather body, arms, a raked back.
func _armchair(m: EmpireKit.Mesher, at: Vector3, f: Vector3) -> void:
	var b := Basis(Vector3.UP, atan2(-f.x, -f.z))
	var p := func(v: Vector3) -> Vector3: return at + b * v
	m.box(Vector3(0.78, 0.3, 0.74), Transform3D(b, p.call(Vector3(0, 0.2, 0.02))), EmpireKit.ACCENT)
	m.box(Vector3(0.6, 0.1, 0.6), Transform3D(b, p.call(Vector3(0, 0.41, -0.02))), EmpireKit.ACCENT)
	for sx in [-0.34, 0.34]:
		m.box(Vector3(0.12, 0.62, 0.74), Transform3D(b, p.call(Vector3(sx, 0.31, 0.02))), EmpireKit.ACCENT)
	m.box(Vector3(0.78, 0.6, 0.14), Transform3D(b * Basis(Vector3.RIGHT, -0.12), p.call(Vector3(0, 0.72, 0.36))), EmpireKit.ACCENT)
	for sx in [-0.32, 0.32]:
		for sz in [-0.3, 0.34]:
			m.cyl(p.call(Vector3(sx, 0, sz)), p.call(Vector3(sx, 0.06, sz)), 0.03, 0.03, EmpireKit.GOLD, 6)
	_blocks.append([at.x - 0.46, at.z - 0.46, at.x + 0.46, at.z + 0.46])
	_seat(at, f, "sit")


## A bar stool facing `f`: a weighted foot, a column, a foot ring, a cushion at 0.80 m.
func _stool(m: EmpireKit.Mesher, at: Vector3, f: Vector3) -> void:
	m.cyl(at, at + Vector3(0, 0.03, 0), 0.24, 0.26, EmpireKit.STEEL, 14)
	m.cyl(at + Vector3(0, 0.03, 0), at + Vector3(0, 0.74, 0), 0.04, 0.04, EmpireKit.STEEL, 8)
	for e in 10:   # (its foot ring)
		var a0 := TAU * e / 10.0
		var a1 := TAU * (e + 1) / 10.0
		m.cyl(at + Vector3(cos(a0) * 0.2, 0.3, sin(a0) * 0.2), at + Vector3(cos(a1) * 0.2, 0.3, sin(a1) * 0.2), 0.012, 0.012, EmpireKit.STEEL, 4, false)
	m.cyl(at + Vector3(0, 0.74, 0), at + Vector3(0, 0.76, 0), 0.2, 0.2, EmpireKit.WOOD, 14)
	m.cyl(at + Vector3(0, 0.76, 0), at + Vector3(0, 0.80, 0), 0.19, 0.18, EmpireKit.ACCENT, 14)
	_blocks.append([at.x - 0.25, at.z - 0.25, at.x + 0.25, at.z + 0.25])
	_seat(at, f, "stool")


## A round table on a pedestal: a weighted foot, a column, a wooden top with a gold rim.
func _table(m: EmpireKit.Mesher, at: Vector3, r: float, h := 0.76) -> void:
	m.cyl(at, at + Vector3(0, 0.04, 0), r * 0.45, r * 0.5, EmpireKit.STEEL, 16)
	m.cyl(at + Vector3(0, 0.04, 0), at + Vector3(0, h - 0.05, 0), 0.06, 0.06, EmpireKit.STEEL, 8)
	m.cyl(at + Vector3(0, h - 0.05, 0), at + Vector3(0, h, 0), r, r, EmpireKit.WOOD, 24)
	m.cyl(at + Vector3(0, h - 0.055, 0), at + Vector3(0, h - 0.01, 0), r + 0.02, r + 0.02, EmpireKit.GOLD, 24, false)
	_blocks.append([at.x - r, at.z - r, at.x + r, at.z + r])


## The bar: its counter (a lit gold top, stools along it), shelves of bottles
## behind, round tables by the windows with their chairs.
func _bar(m: EmpireKit.Mesher, rng: RandomNumberGenerator, r: Dictionary) -> void:
	var z0: float = r["z0"]
	var z1: float = r["z1"]
	var cx0 := xb + 4.0
	var cx1 := xb + 15.0
	var cz := z0 + 4.2
	_furn(m, Vector3(cx1 - cx0, 1.05, 1.0), Vector3((cx0 + cx1) * 0.5, 0.525, cz), EmpireKit.WOOD)
	m.boxat(Vector3(cx1 - cx0 - 0.2, 0.7, 0.04), Vector3((cx0 + cx1) * 0.5, 0.5, cz + 0.51), EmpireKit.ACCENT)
	m.boxat(Vector3(cx1 - cx0 + 0.3, 0.06, 1.4), Vector3((cx0 + cx1) * 0.5, 1.08, cz), EmpireKit.GOLD)
	m.boxat(Vector3(cx1 - cx0, 0.05, 0.05), Vector3((cx0 + cx1) * 0.5, 0.18, cz + 0.55), EmpireKit.LAMP)
	m.cyl(Vector3(cx0, 0.3, cz + 0.62), Vector3(cx1, 0.3, cz + 0.62), 0.025, 0.025, EmpireKit.GOLD, 6)   # (the foot rail)
	# (the shelves on the wall behind, bottles on them)
	for sh in 3:
		var y := 1.4 + sh * 0.75
		m.boxat(Vector3(cx1 - cx0, 0.06, 0.4), Vector3((cx0 + cx1) * 0.5, y, z0 + 0.6), EmpireKit.WOOD)
		m.boxat(Vector3(cx1 - cx0, 0.04, 0.05), Vector3((cx0 + cx1) * 0.5, y - 0.05, z0 + 0.82), EmpireKit.LAMP)
		var x := cx0 + 0.3
		while x < cx1 - 0.3:
			var tall := rng.randf_range(0.28, 0.5)
			m.cyl(Vector3(x, y + 0.03, z0 + 0.6), Vector3(x, y + 0.03 + tall, z0 + 0.6), 0.07, 0.06, [EmpireKit.ACCENT, EmpireKit.GOLD, EmpireKit.ACCENT2, EmpireKit.STEEL][rng.randi() % 4], 6)
			x += rng.randf_range(0.18, 0.32)
	_blocks.append([cx0, z0 + 0.3, cx1, z0 + 0.9])
	for k in 6:   # (stools along the counter, facing it)
		_stool(m, Vector3(cx0 + 1.2 + k * (cx1 - cx0 - 2.4) / 5.0, 0, cz + 1.05), Vector3(0, 0, -1))
	# (tables by the windows, chairs round them)
	for k in 4:
		var at := Vector3(xr - 4.0 - (k % 2) * 6.0, 0, z0 + 11.0 + (k >> 1) * (z1 - z0 - 15.0))
		_table(m, at, 0.6)
		for c in 3:
			var a := TAU * c / 3.0 + 0.4
			var ch := at + Vector3(cos(a) * 0.95, 0, sin(a) * 0.95)
			_chair(m, ch, (at - ch).normalized())
	_spots["bartender"] = [[Vector3((cx0 + cx1) * 0.5, 0, z0 + 2.1), PI]]
	_room_spots("bar", [[Vector3(xr - 2.0, 0, (z0 + z1) * 0.5), -PI * 0.5]])
	_plant(m, Vector3(xb + 1.6, 0, z1 - 1.6))


## The lounge: deep sofas facing the windows, low tables, rugs, plants; armchairs round a table.
func _lounge(m: EmpireKit.Mesher, rng: RandomNumberGenerator, r: Dictionary) -> void:
	var z0: float = r["z0"]
	var z1: float = r["z1"]
	var spots: Array = []
	for k in 2:
		var z := z0 + 6.0 + k * (z1 - z0 - 12.0)
		var x := xr - 7.0
		# (a row of armchairs facing out, a low table before them)
		for q in 3:
			_armchair(m, Vector3(x, 0, z - 1.0 + q * 1.0 - 0.0), Vector3(1, 0, 0))
		_furn(m, Vector3(1.0, 0.06, 2.2), Vector3(x + 1.5, 0.4, z + 0.0), EmpireKit.WOOD)
		for sx in [-0.4, 0.4]:
			for sz in [-0.95, 0.95]:
				m.cyl(Vector3(x + 1.5 + sx, 0, z + sz), Vector3(x + 1.5 + sx, 0.37, z + sz), 0.03, 0.03, EmpireKit.GOLD, 6)
		m.boxat(Vector3(4.2, 0.03, 4.6), Vector3(x + 0.8, 0.055, z), EmpireKit.CLOTH)
		m.boxat(Vector3(4.5, 0.025, 4.9), Vector3(x + 0.8, 0.045, z), EmpireKit.GOLD)
		# (a second group back from the windows: armchairs round a table)
		var bx := xb + 7.0
		_table(m, Vector3(bx, 0, z), 0.55, 0.5)
		for e in 4:
			var a := TAU * e / 4.0 + 0.785
			var ch := Vector3(bx + cos(a) * 1.35, 0, z + sin(a) * 1.35)
			_armchair(m, ch, (Vector3(bx, 0, z) - ch).normalized())
		m.boxat(Vector3(4.0, 0.03, 4.0), Vector3(bx, 0.055, z), EmpireKit.CLOTH)
		spots.append([Vector3(x + 3.6, 0, z + rng.randf_range(-1.5, 1.5)), -PI * 0.5])   # (at the window)
	for z in [z0 + 1.6, z1 - 1.6]:
		_plant(m, Vector3(xb + 2.0, 0, z))
		_plant(m, Vector3(xr - 2.0, 0, z))
	_room_spots("lounge", spots)


## The harbour office: desks with their screens and chairs, cabinets, a great
## display of the traffic on the wall.
func _offices(m: EmpireKit.Mesher, rng: RandomNumberGenerator, r: Dictionary) -> void:
	var z0: float = r["z0"]
	var z1: float = r["z1"]
	for k in 4:
		var at := Vector3(xb + 8.0 + (k % 2) * 8.0, 0, z0 + 7.0 + (k >> 1) * (z1 - z0 - 13.0))
		m.boxat(Vector3(4.0, 0.03, 3.6), at + Vector3(0, 0.05, -0.4), EmpireKit.CLOTH)
		_furn(m, Vector3(1.9, 0.05, 0.9), at + Vector3(0, 0.75, 0), EmpireKit.WOOD)
		for sx in [-0.9, 0.9]:   # (its sides; drawers on one)
			m.boxat(Vector3(0.06, 0.73, 0.84), at + Vector3(sx, 0.365, 0), EmpireKit.WOOD)
		m.boxat(Vector3(0.45, 0.6, 0.8), at + Vector3(0.62, 0.42, 0), EmpireKit.WOOD)
		for d in 3:
			m.boxat(Vector3(0.1, 0.02, 0.02), at + Vector3(0.62, 0.25 + d * 0.18, -0.41), EmpireKit.GOLD)
		m.boxat(Vector3(1.6, 0.5, 0.03), at + Vector3(0, 0.45, 0.4), EmpireKit.WOOD)   # (its modesty panel)
		m.boxat(Vector3(0.75, 0.46, 0.04), at + Vector3(0, 1.08, 0.25), EmpireKit.IRON)
		m.cyl(at + Vector3(0, 0.775, 0.28), at + Vector3(0, 0.85, 0.28), 0.03, 0.03, EmpireKit.STEEL, 6)
		m.panel(at + Vector3(0, 1.08, 0.228), Vector3(0.35, 0, 0), Vector3(0, -0.2, 0), EmpireKit.SCREEN, Vector3(0, 0, -1), float(k) * 0.25)
		m.boxat(Vector3(0.45, 0.02, 0.16), at + Vector3(0, 0.785, -0.15), EmpireKit.IRON)   # (keys)
		_chair(m, at + Vector3(0, 0, -0.75), Vector3(0, 0, 1))
	for k in 5:   # (cabinets along the far wall)
		_furn(m, Vector3(1.4, 2.0, 0.7), Vector3(xb + 6.0 + k * 1.5, 1.0, z1 - 0.8), EmpireKit.STEEL)
		m.boxat(Vector3(1.0, 0.05, 0.05), Vector3(xb + 6.0 + k * 1.5, 1.6, z1 - 1.16), EmpireKit.LAMP)
	m.boxat(Vector3(8.0, 3.2, 0.12), Vector3(xb + 13.0, 3.8, z0 + 0.4), EmpireKit.IRON)
	m.panel(Vector3(xb + 13.0, 3.8, z0 + 0.48), Vector3(3.8, 0, 0), Vector3(0, -1.45, 0), EmpireKit.SCREEN, Vector3(0, 0, 1), 0.75)
	_room_spots("offices", [[Vector3(xb + 13.0, 0, z0 + 3.0), PI]])
	_plant(m, Vector3(xr - 2.0, 0, z1 - 2.0))


## The stores: racks of crates, a cargo lift.
func _stores(m: EmpireKit.Mesher, rng: RandomNumberGenerator, r: Dictionary) -> void:
	var z0: float = r["z0"]
	var z1: float = r["z1"]
	for row in 3:
		var x := xb + 6.0 + row * 6.0
		var za := z0 + 4.0
		var zb := z1 - 4.0
		_blocks.append([x - 0.9, za, x + 0.9, zb])
		var z := za
		while z <= zb + 0.01:   # (its uprights)
			for sx in [-0.8, 0.8]:
				m.boxat(Vector3(0.12, 5.0, 0.12), Vector3(x + sx, 2.5, z), EmpireKit.STEEL)
			z += (zb - za) / 4.0
		for lv in 3:
			var y := 0.15 + lv * 1.6
			m.boxat(Vector3(1.7, 0.08, zb - za), Vector3(x, y, (za + zb) * 0.5), EmpireKit.IRON)
			m.boxat(Vector3(0.08, 0.14, zb - za), Vector3(x - 0.85, y + 0.08, (za + zb) * 0.5), EmpireKit.HAZARD)
			z = za + 0.9
			while z < zb - 0.9:
				if rng.randf() < 0.75:
					EmpireKit.crate(m, Vector3(x, y + 0.04, z), Vector3(1.3, 1.1 + rng.randf() * 0.3, 1.4), rng.randf() < 0.25)
				z += 1.7
	_room_spots("stores", [[Vector3(xb + 10.5, 0, (z0 + z1) * 0.5), PI * 0.5]])


# --- On the main thread: the mesh in, the glass, lights, signs, its people ----------

func _process(delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish()
		return
	if _spawned < _staff.size():   # (its people: one a frame)
		var e: Array = _staff[_spawned]
		_person(e[0], e[1], _spawned, str(e[2]) if e.size() > 2 else "", str(e[3]) if e.size() > 3 else "", e.size() > 4 and bool(e[4]))
		_spawned += 1
		return
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 2.0
		_sync_people()
	_near_t -= delta
	var f := _focus_local()
	if _near_t <= 0.0:   # (far ones stand still - their animations off - and further, not drawn; the rooms' lights only near)
		_near_t = 0.4
		for p in people:
			var n: Node3D = p["node"]
			var d := n.position.distance_to(f)
			var anim: AnimationPlayer = p["anim"]
			if anim:
				anim.active = d < 60.0
			n.visible = d < 110.0
		for o: OmniLight3D in _lights:
			o.visible = o.position.distance_to(f) < 34.0
	for p in people:
		_step(p, delta)
	var gone := people.filter(func(q): return q.get("gone", false))
	for q in gone:
		people.erase(q)
		_present.erase(str(q.get("pid", "")))
		(q["node"] as Node3D).queue_free()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _focus_local() -> Vector3:
	var c := get_viewport().get_camera_3d() if is_inside_tree() else null
	return to_local(c.global_position) if c else Vector3.ZERO


func _finish() -> void:
	built = true
	SolidsEdit.installed(self)   # (its walls and things as edited in the Live Editor, if they were)
	var mi := MeshInstance3D.new()
	mi.name = "Bay"
	mi.mesh = _mesh
	mi.material_override = EmpireKit.mat("inside", emp)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# The windows onto the hall (the concourse's): glass seen from both sides.
	var gm := _glass_mat()
	for g in _glass:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = g[1]
		q.mesh = qm
		q.material_override = gm
		q.position = g[0]
		q.rotation.y = PI * 0.5 if int(g[2]) == 0 else 0.0
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	# Lights: each room its own (warm in the bar, cool in the offices); the hall's the station's "sun" overhead.
	for l in _lamps:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.omni_range = 20.0
		o.omni_attenuation = 0.8
		o.light_energy = 1.4
		o.light_color = {"bar": Color(1.0, 0.72, 0.45), "offices": Color(0.85, 0.92, 1.0), "lounge": Color(1.0, 0.86, 0.7)}.get(l[1], Color(1.0, 0.95, 0.88))
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_lights.append(o)
	# Signs: each room's name over its door, the terminals' over them.
	var accent: Color = Galaxy.empire_color(str(station.record.get("empire", ""))) if station else Color.WHITE
	for r in rooms:
		_sign(str(r["name"]), (r["door"] as Vector3) + Vector3(-0.45, 4.3, 0), -PI * 0.5, accent, 56)
	for t in terminals:
		_sign(str(t[0]), (t[4] as Vector3) + Basis(Vector3.UP, float(t[3])) * Vector3(0, 3.5, 0.3), float(t[3]) + PI, accent, 48)


func _sign(text: String, at: Vector3, yaw: float, accent: Color, size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.position = at
	l.rotation.y = yaw
	l.modulate = accent.lerp(Color.WHITE, 0.55)
	l.outline_size = 0
	add_child(l)


static var _gm: StandardMaterial3D


static func _glass_mat() -> StandardMaterial3D:
	if _gm == null:
		_gm = EmpireKit.glass().duplicate()
		_gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_gm.albedo_color = Color(0.3, 0.38, 0.42, 0.18)
	return _gm


# --- Its people ----------------------------------------------------------------------

func _person(role: String, area: String, i: int, pid := "", tid := "", arriving := false) -> void:
	var e := str(station.record.get("empire", "")) if station else ""
	var who: Dictionary = People.person(pid) if pid != "" else {}
	if not who.is_empty() and str(who.get("emp", "")) != "":
		e = str(who["emp"])   # (their own people's look: a ship's crew from elsewhere)
	var face := RandomNumberGenerator.new()   # (the same face every time you meet them)
	face.seed = hash(pid) if pid != "" else _rng.randi()
	var id := CosmosNpc.people_id(e, face)
	if not Stage3D.has_model(id):
		id = "player"
		if not Stage3D.has_model(id):
			return
	var armed := role == "guard" and not CosmosNpc.weapons_of(id).is_empty()
	var m: Node3D = Stage3D._scene(id).instantiate()
	if id == "player":
		CosmosModels.apply(m, id)
	else:
		CosmosNpc.dress(m, id, e, "rifle" if armed else "")
	var holder := Node3D.new()
	holder.name = "Crew%d" % i
	holder.set_meta("model", id)
	holder.add_child(m)
	m.rotation.y = PI
	add_child(holder)
	if role == "carrier":   # (a crate in its arms, between its hands)
		var c := MeshInstance3D.new()
		c.mesh = EmpireKit.crate_mesh(i % 2 == 0)
		c.material_override = EmpireKit.mat("inside", emp)
		c.scale = Vector3(0.33, 0.36, 0.25)   # (0.40 wide - between the hands, 0.42 apart - 0.32 high, 0.33 deep)
		c.position = Vector3(0, CARRY_AT.y - 0.88 * 0.36 * 0.5, -CARRY_AT.z)   # (the crate's foot at the origin: its middle at the hands)
		holder.add_child(c)
	var anim: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	var stand := ""
	var walk := ""
	if anim:
		Stage3D.loop_clips(anim, id, ["walk", "idle", "gun_idle", "gun_walk", "guard", "sit", "stool", "carry", "carry_idle"])   # (a whole cycle long: no jump at the seam)
		for c in (["gun_idle", "guard", "idle"] if armed else ["idle"]):   # (the "guard" clip is a fighter's stance: only the armed)
			if stand == "" and anim.has_animation(c):
				stand = c
		for c in (["gun_walk", "walk"] if armed else ["walk", "gun_walk"]):
			if walk == "" and anim.has_animation(c):
				walk = c
		if role == "carrier" and anim.has_animation("carry"):
			walk = "carry"
			stand = "carry_idle" if anim.has_animation("carry_idle") else stand
		if stand != "":
			anim.play(stand)
			anim.seek(_rng.randf() * 2.0, true)
	var p := {"node": holder, "anim": anim, "role": role, "name": GIVEN[(i * 7 + int(_rng.seed % 97)) % GIVEN.size()], "path": [],
		"wait": _rng.randf_range(1.0, 6.0), "stand": stand, "walk": walk, "area": area, "home": Vector3.ZERO, "yaw": 0.0, "talking": false,
		"pid": pid, "tid": tid}
	if not who.is_empty():
		p["name"] = People.full_name(who)
	var spot := _take_spot(role, area)
	# (the bar's spacers, the officers at their desks, the lounge's travellers: in a seat)
	var room_kind: String = {"patron": "bar", "officer": "offices"}.get(role, "lounge" if role == "traveller" and area == "lounge" else "")
	var seat: Dictionary = _free_seat(room_kind) if room_kind != "" else {}
	if not seat.is_empty():
		seat["who"] = holder
		p["seat"] = seat
		spot = [sit_point(seat), float(seat["yaw"])]
		if anim and anim.has_animation(str(seat["kind"])):
			p["stand"] = str(seat["kind"])
			anim.play(p["stand"])
			anim.seek(_rng.randf() * 2.0, true)
	if role == "visitor":
		p["state"] = "using" if spot.size() > 2 else "leaving"
		p["term"] = int(spot[2]) if spot.size() > 2 else -1
		p["idle"] = p["stand"]
		if spot.size() > 2:
			p["stand"] = _console_clip(anim, p["stand"])
			if anim and p["stand"] != "":
				anim.play(p["stand"])
		p["wait"] = _rng.randf_range(3.0, 12.0)
	holder.position = spot[0]
	holder.rotation.y = spot[1]
	p["home"] = spot[0]
	p["yaw"] = spot[1]
	if arriving:   # (in from their ship on its lift, or from the quarters: walking to it)
		var from := _ship_spot(tid) if tid != "" else _quarters_door()
		holder.position = from
		p["path"] = _way(from, spot[0])
		if p.has("seat"):   # (the seat theirs when they get there)
			p["seat_pending"] = p["seat"]
			p.erase("seat")
			p["stand"] = str(p["idle"]) if p.has("idle") else stand
		if role == "visitor" and spot.size() > 2:
			p["state"] = "to_term"
			p["stand"] = stand
	if area == "walk":
		p["area"] = str(rooms[_rng.randi() % rooms.size()]["kind"])
	people.append(p)
	_crew.append([holder, anim, holder.position, 0.0, armed, stand, walk])


## Where one of `role` stands (and faces) to start: its post.
func _take_spot(role: String, area: String) -> Array:
	match role:
		"guard":
			var zs := doors_a()
			var z: float = zs[(people.filter(func(q): return q["role"] == "guard").size()) % zs.size()]
			return [Vector3(xa - 3.0, 0, z + (4.0 if people.size() % 2 == 0 else -4.0)), PI * 0.5]
		"visitor":   # (at a free terminal of the services hall, using it)
			var k := _free_terminal()
			if k >= 0:
				_term_busy[k] = true
				return [terminals[k][2], _term_yaw(k), k]
		"bartender":
			return _spots.get("bartender", [[Vector3(xb + 8.0, 0, 0), 0.0]])[0]
		"dock", "carrier":
			var hs: Array = _spots.get("hall", [])
			if not hs.is_empty():
				return hs[_rng.randi() % hs.size()]
			return [Vector3(_rng.randf_range(-H * 0.5, H * 0.5), 0, _rng.randf_range(-W * 0.8, W * 0.8)), 0.0]
	var list: Array = _spots.get(area if area != "walk" else str(rooms[_rng.randi() % rooms.size()]["kind"]), [])
	for s in list:
		if s.size() < 3:
			s.append(true)
			return s
	if not list.is_empty():
		return list[_rng.randi() % list.size()]
	return [Vector3(xb - 4.0, 0, _rng.randf_range(-W * 0.8, W * 0.8)), PI * 0.5]


## Its walk: dock workers about the hall (carriers from a stack to the lifts and
## back), travellers from room to room by the concourse; the rest at their posts.
func _step(p: Dictionary, delta: float) -> void:
	var n: Node3D = p["node"]
	var anim: AnimationPlayer = p["anim"]
	if p["talking"]:
		return
	if p.get("leaving", false) and (p["path"] as Array).is_empty():
		p["gone"] = true   # (aboard their ship, or home in the quarters)
		return
	if p.has("seat_pending") and (p["path"] as Array).is_empty():   # (at the seat they came for: sitting)
		var seat: Dictionary = p["seat_pending"]
		p.erase("seat_pending")
		p["seat"] = seat
		p["sit_at"] = sit_point(seat)
		p["yaw"] = float(seat["yaw"])
		if anim and anim.has_animation(str(seat["kind"])):
			p["stand"] = str(seat["kind"])
			anim.play(p["stand"], 0.3)
	if p.has("seat"):   # (seated: where it sits - eased onto the seat and round, not snapped)
		var k := minf(delta * 6.0, 1.0)
		n.rotation.y = lerp_angle(n.rotation.y, float(p["yaw"]), k)
		if p.has("sit_at"):
			n.position = n.position.lerp(p["sit_at"], k)
		return
	var path: Array = p["path"]
	if path.is_empty() and p.get("state", "") == "to_term":   # (at the terminal: using it a while)
		p["state"] = "using"
		p["stand"] = _console_clip(anim, str(p["idle"]))
		p["wait"] = _rng.randf_range(5.0, 12.0)
	if path.is_empty():
		p["wait"] -= delta
		if anim and p["stand"] != "" and anim.current_animation != p["stand"]:
			anim.play(p["stand"], 0.25)
		n.rotation.y = lerp_angle(n.rotation.y, float(p["yaw"]), minf(delta * 3.0, 1.0))
		if p["wait"] > 0.0:
			return
		p["wait"] = _rng.randf_range(5.0, 14.0)
		match str(p["role"]):
			"visitor":
				_visitor_next(p)
			"dock", "carrier":
				var hs: Array = _spots.get("hall", [])
				var pads: Array = _spots.get("pads", [])
				if p["role"] == "carrier" and not pads.is_empty() and n.position.distance_to(p["home"]) < 3.0:
					var sp: Array = pads[_rng.randi() % pads.size()]
					var a := _rng.randf_range(-PI, PI)
					p["path"] = _way(n.position, Vector3(cos(a) * float(sp[1]), 0, float(sp[0]) + sin(a) * float(sp[1])))
					p["wait"] = _rng.randf_range(2.0, 4.0)
				elif p["role"] == "carrier":
					p["path"] = _way(n.position, p["home"])
					p["wait"] = _rng.randf_range(2.0, 4.0)
				elif not hs.is_empty():
					var s: Array = hs[_rng.randi() % hs.size()]
					p["path"] = _way(n.position, s[0])
					p["yaw"] = s[1]
			"traveller":
				if _rng.randf() < 0.5:
					var to: Dictionary = rooms[_rng.randi() % rooms.size()]
					var list: Array = _spots.get(str(to["kind"]), [])
					var goal: Vector3 = (list[_rng.randi() % list.size()][0] as Vector3) if not list.is_empty() else (to["door"] as Vector3) + Vector3(6, 0, 0)
					# (goal in that room: the nearest spot of its kind to its door)
					var best := goal
					for s in list:
						if absf((s[0] as Vector3).z - float(to["door"].z)) < (float(to["z1"]) - float(to["z0"])) * 0.5:
							best = s[0]
							p["yaw"] = s[1]
					p["path"] = _way(n.position, best)
		return
	var goal: Vector3 = path[0]
	var to: Vector3 = goal - n.position
	to.y = 0.0
	var speed := 1.3 if p["role"] != "carrier" else 1.1
	if to.length() < 0.25:
		path.pop_front()
		return
	n.position += to.normalized() * minf(speed * delta, to.length())
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), minf(delta * 6.0, 1.0))
	if anim and p["walk"] != "" and anim.current_animation != p["walk"]:
		anim.play(p["walk"], 0.25)


## Its floor as a grid for its people's ways (1 m cells): walkable where its
## floor's rects are, solid where its furniture, pillars and stacks stand (a
## margin round them) - found by the engine's A* (AStarGrid2D): round things,
## through doors, never through a crate. Built on the worker with the mesh.
var _nav: AStarGrid2D
var _nav_o := Vector2i.ZERO


func _make_nav(holes: Array) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	_nav_o = Vector2i(floori(xi) - 1, floori(-W) - 1)
	var size := Vector2i(ceili(xr - xi) + 3, ceili(W * 2.0) + 3)
	g.region = Rect2i(Vector2i.ZERO, size)
	g.cell_size = Vector2.ONE
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	g.fill_solid_region(g.region, true)
	for r in _walk:   # (the floor: a cell walkable when its middle is 0.5 m inside a rect)
		for x in range(ceili(float(r[0]) + 0.5 - 0.5), floori(float(r[2]) - 0.5 - 0.5) + 1):
			for z in range(ceili(float(r[1]) + 0.5 - 0.5), floori(float(r[3]) - 0.5 - 0.5) + 1):
				g.set_point_solid(Vector2i(x, z) - _nav_o, false)
	for b in _blocks:   # (round its things: 0.5 m clear)
		for x in range(floori(float(b[0]) - 0.5 - 0.5), ceili(float(b[2]) + 0.5 - 0.5) + 1):
			for z in range(floori(float(b[1]) - 0.5 - 0.5), ceili(float(b[3]) + 0.5 - 0.5) + 1):
				var c := Vector2i(x, z) - _nav_o
				if g.is_in_boundsv(c):
					g.set_point_solid(c, true)
	for h in holes:   # (the lifts: ships come down on them - walked round, not across)
		var hs := float(h[1]) * 0.5 + 1.0
		for x in range(floori(-hs), ceili(hs) + 1):
			for z in range(floori(float(h[0]) - hs), ceili(float(h[0]) + hs) + 1):
				var c := Vector2i(x, z) - _nav_o
				if g.is_in_boundsv(c):
					g.set_point_solid(c, true)
	return g


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.z)) - _nav_o


## The nearest walkable cell to `c` (itself if it is): from a seat, a terminal's foot.
func _open_cell(c: Vector2i) -> Vector2i:
	if _nav.is_in_boundsv(c) and not _nav.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				for q in [c + Vector2i(dx, dz), c + Vector2i(dz, dx)]:
					if _nav.is_in_boundsv(q) and not _nav.is_point_solid(q):
						return q
	return c


## A way for one of its people from `a` to `b` (port-local): the grid's path,
## its corners only, then `b` itself. (Without the grid: straight.)
func _way(a: Vector3, b: Vector3) -> Array:
	if _nav == null:
		return [b]
	var pts := _nav.get_point_path(_open_cell(_cell(a)), _open_cell(_cell(b)), true)
	var out: Array = []
	var last_dir := Vector2.ZERO
	for i in range(1, pts.size()):
		var d := (pts[i] - pts[i - 1]).normalized()
		if i > 1 and not d.is_equal_approx(last_dir):
			var q: Vector2 = pts[i - 1] + Vector2(_nav_o) + Vector2(0.5, 0.5)
			out.append(Vector3(q.x, 0, q.y))
		last_dir = d
	out.append(b)
	return out


## A way from `a` to `b` (in room `to`): out of the room it's in by its door,
## along the concourse, in by the other's door.
func _route(a: Vector3, b: Vector3, to: Dictionary) -> Array:
	var out: Array = []
	var cx := xa + 1.0 + CONC * 0.5
	if a.x > xb:   # (in a room: out by its door)
		for r in rooms:
			if a.z >= float(r["z0"]) and a.z <= float(r["z1"]):
				out.append(Vector3(xb + 2.0, 0, float(r["door"].z)))
				out.append(Vector3(cx, 0, float(r["door"].z)))
	elif a.x < xa:
		var zs := doors_a()
		var best: float = zs[0]
		for z in zs:
			if absf(z - a.z) < absf(best - a.z):
				best = z
		out.append(Vector3(xa - 2.0, 0, best))
		out.append(Vector3(cx, 0, best))
	out.append(Vector3(cx, 0, float(to["door"].z)))
	out.append(Vector3(xb + 2.0, 0, float(to["door"].z)))
	out.append(b)
	return out


## Where the one sitting in `seat` stands its feet (its origin): the seat's
## middle, moved by where its hips come down in the sitting clip (SIT_FWD).
const SIT_FWD := {"sit": 0.02, "stool": 0.02}   # m forward of the origin the hips sit (moves.py's seated clips: 0.46 / 0.80 m up)
const CARRY_AT := Vector3(0, 1.06, 0.33)        # (the carrying clips' crate: its middle between the hands, up and forward of the origin)


func sit_point(seat: Dictionary) -> Vector3:
	return (seat["at"] as Vector3) - (seat["face"] as Vector3) * float(SIT_FWD.get(seat["kind"], 0.0))


## A free seat in a room of `kind` (none: {}).
func _free_seat(kind: String) -> Dictionary:
	var list: Array = []
	for st in seats:
		if _taken(st):
			continue
		for r in rooms:
			if r["kind"] == kind and (st["at"] as Vector3).z > float(r["z0"]) and (st["at"] as Vector3).z < float(r["z1"]) and (st["at"] as Vector3).x > xb:
				list.append(st)
				break
	return list[_rng.randi() % list.size()] if not list.is_empty() else {}


static func _taken(st: Dictionary) -> bool:
	return st["who"] != null and is_instance_valid(st["who"])


## The free seat within reach of port-local `p` (its index), or -1.
func seat_near(p: Vector3, reach := 1.3) -> int:
	var best := -1
	var bd := reach
	for i in seats.size():
		if _taken(seats[i]):
			continue
		var d := Vector2(p.x - (seats[i]["at"] as Vector3).x, p.z - (seats[i]["at"] as Vector3).z).length()
		if d < bd:
			bd = d
			best = i
	return best


# --- Its people from the sector's (People) ------------------------------------------------

## Who's in the port now, as [role, area, person id, their ship's id, arriving]:
## its staff on shift at their posts; off duty and their households - a few - in
## the bar and the lounge; the captains and crews of the ships down on its
## lifts ashore (captains at the terminals, crews in the bar and the lounge).
func _plan_people() -> Array:
	if not People.populated or station == null:
		return []
	var sid := str(station.record.get("id", ""))
	var out: Array = []
	var rest: Array = []
	for id in People.at_station(sid):
		if out.size() >= MAX_PEOPLE:
			break
		var q := People.person(id)
		if q.is_empty() or float(q["age"]) < People.ADULT or _present.has(id):
			continue
		var job := str(q["job"])
		if JOB_ROLE.has(job) and str(q["at"]) == sid:
			if People.on_shift(q):
				out.append([JOB_ROLE[job][0], JOB_ROLE[job][1], id, "", false])
			else:
				rest.append(id)
		elif job in ["crew", "captain"]:
			if _ship_here(str(q["at"])):
				out.append(["visitor" if job == "captain" else "traveller", "bar" if absi(hash(id)) % 2 == 0 else "lounge", id, str(q["at"]), false])
		elif job == "":
			rest.append(id)
	for k in mini(rest.size(), 6):   # (off duty, at home here: a few of them out in the bar and the lounge)
		if out.size() >= MAX_PEOPLE:
			break
		out.append(["patron" if k % 2 == 0 else "traveller", "bar" if k % 2 == 0 else "lounge", rest[k], "", false])
	for e in out:
		_present[e[2]] = true
	return out


## A ship of the economy down on one of this port's lifts, staying a while yet.
func _ship_here(tid: String) -> bool:
	var r: Dictionary = Galaxy.traders.get(tid, {})
	if r.is_empty() or r["state"] != "docked" or str(r["station"]) != str(station.record.get("id", "")) or not r.has("pad"):
		return false
	for pd in station.pads:
		if int(pd["id"]) == int(r["pad"]):
			return int(pd.get("platform", -1)) == platform and float(r.get("wait", 0.0)) > 25.0
	return false


## Where a ship's people come off it and go back aboard: by its lift, toward the concourse.
func _ship_spot(tid: String) -> Vector3:
	var r: Dictionary = Galaxy.traders.get(tid, {})
	for pd in station.pads:
		if int(pd["id"]) == int(r.get("pad", -1)):
			return pad_spot(float(pd.get("along", 0.0)))
	return _quarters_door()


## The way to the station's quarters (where its people live): the concourse's ends.
func _quarters_door() -> Vector3:
	return Vector3(xa + 1.0 + CONC * 0.5, 0, (W - 3.0) * (1.0 if _rng.randf() < 0.5 else -1.0))


## Every couple of seconds: staff off shift go home (the quarters), crews back
## aboard as their ship's time runs out; those new here come in - staff on
## shift from the quarters, a ship's people off its lift.
func _sync_people() -> void:
	if not People.populated or not built:
		return
	var sid := str(station.record.get("id", ""))
	for p in people:
		var pid := str(p.get("pid", ""))
		if pid == "" or p.get("leaving", false):
			continue
		var q := People.person(pid)
		var go: bool = q.is_empty() or not q["alive"]
		var to := _quarters_door()
		if not go and str(p.get("tid", "")) != "":
			go = not _ship_here(str(p["tid"]))
			to = _ship_spot(str(p["tid"]))
		elif not go and JOB_ROLE.has(str(q["job"])) and str(q["at"]) == sid:
			go = not People.on_shift(q)
		if go:
			_send_off(p, to)
	if people.size() >= MAX_PEOPLE:
		return
	for e in _plan_people():
		e[4] = true   # (they walk in)
		_staff.append(e)


func _send_off(p: Dictionary, to: Vector3) -> void:
	p["leaving"] = true
	p["talking"] = false
	var n: Node3D = p["node"]
	if p.has("seat"):
		(p["seat"] as Dictionary)["who"] = null
		p.erase("seat")
	if p.has("seat_pending"):
		(p["seat_pending"] as Dictionary)["who"] = null
		p.erase("seat_pending")
	if int(p.get("term", -1)) >= 0:
		_term_busy.erase(int(p["term"]))
		p["term"] = -1
	p["state"] = "leaving_port"
	p["path"] = _way(n.position, to)
	p["stand"] = str(p.get("idle", p["stand"]))


## The services hall's terminals a visitor may use: free ones (index), or -1.
var _term_busy := {}


func _free_terminal() -> int:
	var free: Array = []
	for k in terminals.size():
		if not _term_busy.has(k) and str(TERMINALS[k][2]) == "services":
			free.append(k)
	return free[_rng.randi() % free.size()] if not free.is_empty() else -1


## Facing terminal `k` from where one stands to use it.
func _term_yaw(k: int) -> float:
	var f: Vector3 = (terminals[k][4] as Vector3) - (terminals[k][2] as Vector3)
	return atan2(-f.x, -f.z)


## Working a console: the clip for it if the model has one, else the hands held forward as on a panel.
static func _console_clip(anim: AnimationPlayer, fallback: String) -> String:
	if anim:
		for c in ["console", "carry_idle"]:
			if anim.has_animation(c):
				return c
	return fallback


## A visitor's next move: done at its terminal - off to another room a while;
## back from there - to a free terminal (or a little longer where it is).
func _visitor_next(p: Dictionary) -> void:
	var n: Node3D = p["node"]
	if p["state"] == "using":
		_term_busy.erase(int(p["term"]))
		p["term"] = -1
		var sz: float = rooms.filter(func(r): return r["kind"] == "services")[0]["door"].z
		var away := rooms.filter(func(r): return r["kind"] in ["bar", "lounge", "offices", "stores"] and absf(float(r["door"].z) - sz) < 70.0)   # (an errand nearby, not the port's far end)
		if away.is_empty():
			away = rooms.filter(func(r): return r["kind"] != "services")
		var to: Dictionary = away[_rng.randi() % away.size()]
		var goal := (to["door"] as Vector3) + Vector3(_rng.randf_range(4.0, 10.0), 0, _rng.randf_range(-4.0, 4.0))
		p["path"] = _way(n.position, goal)
		p["state"] = "leaving"
		p["stand"] = str(p["idle"])
		p["yaw"] = _rng.randf_range(-PI, PI)
		p["wait"] = _rng.randf_range(6.0, 16.0)   # (lingering there once it arrives)
	else:
		var k := _free_terminal()
		if k < 0:
			p["wait"] = _rng.randf_range(2.0, 5.0)
			return
		_term_busy[k] = true
		p["term"] = k
		var serv: Dictionary = rooms.filter(func(r): return r["kind"] == "services")[0]
		p["path"] = _way(n.position, terminals[k][2])
		p["state"] = "to_term"
		p["yaw"] = _term_yaw(k)


## The person within talking reach of port-local `p` (its index), or -1.
func person_near(p: Vector3, reach := 3.0) -> int:
	var best := -1
	var bd := reach
	for i in people.size():
		var d := (people[i]["node"] as Node3D).position.distance_to(Vector3(p.x, 0, p.z))
		if d < bd:
			bd = d
			best = i
	return best


## Turns them to you while you talk (and back to their walk after).
func face(i: int, at: Vector3, talking: bool) -> void:
	var p: Dictionary = people[i]
	p["talking"] = talking
	var n: Node3D = p["node"]
	if talking:
		var to := at - n.position
		n.rotation.y = atan2(-to.x, -to.z)
		var anim: AnimationPlayer = p["anim"]
		if anim and p["stand"] != "":
			anim.play(p["stand"], 0.2)


func role_name(i: int) -> String:
	var q := People.person(str(people[i].get("pid", "")))
	if not q.is_empty():
		return People.job_name(q).capitalize()
	return str(ROLE_NAMES.get(people[i]["role"], "Spacer"))


## The terminal within reach of port-local `p`, or [].
func terminal_near(p: Vector3) -> Array:
	for t in terminals:
		if (t[2] as Vector3).distance_to(Vector3(p.x, 0, p.z)) < 2.0:
			return t
	return []


## Port-local spot where a ship's ramp comes down on pad `along` (for tests and
## tours): beside the lift, towards the concourse.
func pad_spot(along: float) -> Vector3:
	var s := CosmosStation.PAD_SMALL * 0.5
	for h in (station.platforms[platform]["holes"] if station and not station.platforms.is_empty() else []):
		if absf(float(h[0]) - along) < 1.0:
			s = float(h[1]) * 0.5
	return Vector3(s + 6.0, 0, along)


# --- The walker's deck (as CosmosShipInterior's) ---------------------------------

func floor_y(_l: Vector3) -> float:
	return 0.0


func ceiling_y(l: Vector3) -> float:
	var c := ROOM_H
	for r in _walk:
		if l.x >= r[0] and l.x <= r[2] and l.z >= r[1] and l.z <= r[3]:
			c = maxf(c, float(r[4]))
	return c


func confine(l: Vector3, m: float) -> Vector3:
	var c := inside(l, m)
	return Vector3(c.x, l.y, c.z)


## Keeps port-local `p` on its floor: in a room, the hall, the concourse or a
## door between (a margin `m` in), out of the furniture.
func inside(p: Vector3, m: float) -> Vector3:
	var q := Vector3(p.x, clampf(p.y, 0.0, ceiling_y(p) - m), p.z)
	var best := Vector3.INF
	var bd := INF
	for r in _walk:
		var x0: float = r[0] + m
		var z0: float = r[1] + m
		var x1: float = r[2] - m
		var z1: float = r[3] - m
		if x0 > x1 or z0 > z1:
			continue
		var c := Vector3(clampf(q.x, x0, x1), q.y, clampf(q.z, z0, z1))
		var d := Vector2(c.x - q.x, c.z - q.z).length_squared()
		if d < bd:
			bd = d
			best = c
			if d == 0.0:
				break
	if best == Vector3.INF:
		return q
	if built:
		var solids := _round_solids()
		for pass_n in 2:   # (twice: out of one piece, not left in the next)
			for b in _near_blocks(best, m):
				var x0: float = b[0] - m
				var z0: float = b[1] - m
				var x1: float = b[2] + m
				var z1: float = b[3] + m
				if best.x > x0 and best.x < x1 and best.z > z0 and best.z < z1:
					var opts := [[best.x - x0, Vector3(x0, best.y, best.z)], [x1 - best.x, Vector3(x1, best.y, best.z)],
						[best.z - z0, Vector3(best.x, best.y, z0)], [z1 - best.z, Vector3(best.x, best.y, z1)]]
					opts.sort_custom(func(a, b): return a[0] < b[0])
					best = opts[0][1]
			# (its people, and the traders parked on their lifts: round, solid)
			for c in solids:
				var d := Vector2(best.x - c.x, best.z - c.z)
				var r: float = c.y + m
				if d.length() < r:
					var dir := d.normalized() if d.length() > 0.001 else Vector2(1, 0)
					best = Vector3(c.x + dir.x * r, best.y, c.z + dir.y * r)
	return best


const CELL := 6.0
const CELL_PAD := 2.0


## The blocks that might hold `p` (with a margin `m` round them): those of its
## cell - each cell lists the blocks within CELL_PAD of it (all of them for a wider margin).
func _near_blocks(p: Vector3, m: float) -> Array:
	if m > CELL_PAD:
		return _blocks
	if _cells_n != _blocks.size():
		_cells = {}
		_cells_n = _blocks.size()
		for i in _blocks.size():
			var b: Array = _blocks[i]
			for cx in range(floori((b[0] - CELL_PAD) / CELL), floori((b[2] + CELL_PAD) / CELL) + 1):
				for cz in range(floori((b[1] - CELL_PAD) / CELL), floori((b[3] + CELL_PAD) / CELL) + 1):
					var k := Vector2i(cx, cz)
					if not _cells.has(k):
						_cells[k] = []
					_cells[k].append(b)
	return _cells.get(Vector2i(floori(p.x / CELL), floori(p.z / CELL)), [])


## Round things in the way: [x, radius, z] as Vector3(x, r, z) - the people
## (seated ones too), the traders' ships down on this port's lifts.
func _round_solids() -> Array:
	var out: Array = []
	for p in people:
		if (p["node"] as Node3D).visible:
			var q: Vector3 = (p["node"] as Node3D).position
			out.append(Vector3(q.x, 0.38, q.z))
	if station:
		for pd in station.pads:
			var o = pd.get("owner")
			if int(pd.get("platform", -1)) == platform and o is CosmosNpcShip and is_instance_valid(o) and float(o._down) > 40.0:
				var l := to_local((o as Node3D).global_position)
				out.append(Vector3(l.x, float(o.reach) * 0.55, l.z))
	return out


## The camera stopped short of its walls (`o`, `dir` in the world).
func cam_hit(o: Vector3, dir: Vector3, limit: float) -> float:
	if not built:
		return INF
	var lo := to_local(o)
	var ld := global_basis.inverse() * dir
	var best := INF
	for bx in _boxes:
		var c: Vector3 = bx[0]
		var h: Vector3 = bx[1]
		var a := lo - c
		var t0 := 0.0
		var t1 := minf(limit, best)
		var hit := true
		for k in 3:
			if absf(ld[k]) < 1e-8:
				if absf(a[k]) > h[k]:
					hit = false
					break
				continue
			var ta := (-h[k] - a[k]) / ld[k]
			var tb := (h[k] - a[k]) / ld[k]
			if ta > tb:
				var x := ta
				ta = tb
				tb = x
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				hit = false
				break
		if hit and t0 > 0.0:
			best = t0
	return best
