class_name CosmosDungeon
extends Node3D
## A cave system or a dungeon under a planet (the 3D game), entered from its
## mouth on the surface (Cosmos.dungeons_of / enter_dungeon): a world of its
## own, set far off out of sight, walked as a deck (the walker's floor_y /
## ceiling_y / confine - like the station's hangar). Laid out by its seed on a
## grid: rooms joined by corridors (a tree from the entrance - its stairs back
## up - to the deepest room, where its chest waits). Built from the towns'
## pieces (CosmosTown.Builder: one mesh, the building shader in its own
## palette - "dungeon": the old labyrinths, dressed stone, red pillars,
## horns; "cave": rough rock, boulders, stalagmites), its walls solid (you,
## your bolts, the camera). Torches burn on the walls (a few lights, no
## shadows). Its dead walk in it: skeleton warriors in the rooms, demons
## deeper in, a demon lord by the chest (CosmosNpc, roles skeleton / demon).

const CELL := 15.0             # m: a grid cell (a room and the way to the next)
const H := 4.6                 # m: the ceiling's height
const WALL := 0.6
const LAMPS := 6               # torch lights at once (the nearest torches')

var style := "dungeon"
var planet: CosmosPlanet
var site := {}
var built := false
var start := Vector3.ZERO      # (dungeon-local) where you come down
var exit_at := Vector3.ZERO    # the stairs back up
var chest_at := Vector3.ZERO
var chest_open := false
var rooms: Array = []          # [Rect2 (x, z), depth from the entrance]
var spots: Array = []
var lights: Array = []         # torch positions (dungeon-local)
var _solids: Array = []
var _grid := {}
var _task := -1
var _out := {}
var _lamps: Array = []         # the torches' lights: on the torches nearest you
var _lamp_t := 0.0


func setup(pl: CosmosPlanet, s: Dictionary) -> void:
	planet = pl
	site = s
	style = str(s.get("kind", "dungeon"))
	name = "Dungeon" if style == "dungeon" else "Cave"
	add_to_group("cam_solid")
	set_meta("cam_reach", CELL * 8.0)
	var seed: int = s["seed"]
	set_meta("edit_key", "dungeon/%s/%d" % [style, seed])   # (the Live Editor's edits: this one - its seed lays it out)
	var st := style
	_task = Jobs.add(func(): _out = _make(st, seed), false, "dungeon")


func poll() -> bool:
	if built:
		return true
	if _task < 0 or not Jobs.done(_task):
		return false
	Jobs.wait(_task)
	_task = -1
	var mi := MeshInstance3D.new()
	mi.mesh = _out["mesh"]
	mi.material_override = CosmosTown.material(style)
	add_child(mi)
	var flames := MeshInstance3D.new()
	flames.mesh = _out["flames"]
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.5, 0.12)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.42, 0.08) * 2.5
	flames.material_override = fm
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	var rocks: PackedFloat32Array = _out["rocks"]
	if rocks.size() > 0:   # (a cave's boulders, one draw)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = CosmosPlanet.rock_mesh()
		mm.instance_count = rocks.size() / 12
		mm.buffer = rocks
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = CosmosStation._mat(Color(0.3, 0.26, 0.22), 0.0, 0.92)
		add_child(mmi)
	_solids = _out["solids"]
	_grid = _out["grid"]
	SolidsEdit.installed(self)   # (its solids as edited in the Live Editor, if they were)
	spots = _out["spots"]
	rooms = _out["rooms"]
	start = _out["start"]
	exit_at = _out["exit"]
	chest_at = _out["chest"]
	lights = _out["lights"]
	for p in lights.slice(0, LAMPS):   # (the torches' light, no shadows: moved to the ones round you)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 4.0
		l.omni_range = 12.0
		l.omni_attenuation = 1.0
		l.shadow_enabled = false
		l.position = p
		add_child(l)
		_lamps.append(l)
	_out = {}
	built = true
	return true


## Every so often the lights go to the torches nearest the camera (paced by time).
func _process(delta: float) -> void:
	if not built or lights.size() <= LAMPS:
		return
	_lamp_t -= delta
	if _lamp_t > 0.0:
		return
	_lamp_t = 0.4
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := to_local(cam.global_position)
	var near := lights.duplicate()
	near.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(at) < b.distance_squared_to(at))
	for i in _lamps.size():
		(_lamps[i] as OmniLight3D).position = near[i]


func _exit_tree() -> void:
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1


# --- The walker's deck --------------------------------------------------------------------

func floor_y(hl: Vector3) -> float:
	return floor_top(hl)


func ceiling_y(hl: Vector3) -> float:
	var best := H + 3.0
	for i in _grid.get(_cell(hl), PackedInt32Array()):
		var b: AABB = _solids[i]
		if hl.x > b.position.x and hl.z > b.position.z and hl.x < b.end.x and hl.z < b.end.z and b.position.y > hl.y + 1.0:
			best = minf(best, b.position.y)
	return best


func confine(hl: Vector3, r: float) -> Vector3:
	return hl + push(hl, r)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CosmosTown.CELL), floori(p.z / CosmosTown.CELL))


func floor_top(p: Vector3) -> float:
	var best := -50.0
	for i in _grid.get(_cell(p), PackedInt32Array()):
		var b: AABB = _solids[i]
		if p.x < b.position.x or p.z < b.position.z or p.x > b.end.x or p.z > b.end.z:
			continue
		if b.end.y <= p.y + CosmosSolids.STEP and b.end.y > best:
			best = b.end.y
	return best


func push(p: Vector3, r: float) -> Vector3:
	var out := Vector3.ZERO
	for i in _grid.get(_cell(p), PackedInt32Array()):
		var b: AABB = _solids[i]
		if b.end.y <= p.y + CosmosSolids.STEP or b.position.y >= p.y + 1.8:
			continue
		var q := p + out
		var dx0 := q.x - (b.position.x - r)
		var dx1 := (b.end.x + r) - q.x
		var dz0 := q.z - (b.position.z - r)
		var dz1 := (b.end.z + r) - q.z
		if dx0 <= 0.0 or dx1 <= 0.0 or dz0 <= 0.0 or dz1 <= 0.0:
			continue
		var m := minf(minf(dx0, dx1), minf(dz0, dz1))
		if m == dx0:
			out.x -= dx0
		elif m == dx1:
			out.x += dx1
		elif m == dz0:
			out.z -= dz0
		else:
			out.z += dz1
	return out


## A line through it (the camera, your bolts, the sights): where it first meets a block, or INF.
func cam_hit(o: Vector3, dir: Vector3, limit: float) -> float:
	if not built:
		return INF
	var lo := to_local(o)
	var ld := global_basis.inverse() * dir
	var seen := {}
	var best := INF
	var steps := int(limit / (CosmosTown.CELL * 0.5)) + 1
	for k in mini(steps, 60) + 1:
		var p := lo + ld * minf(k * CosmosTown.CELL * 0.5, limit)
		for i in _grid.get(_cell(p), PackedInt32Array()):
			if seen.has(i):
				continue
			seen[i] = true
			var t := CosmosSolids._ray_box(lo, ld, _solids[i], minf(limit, best))
			if t < best:
				best = t
	return best


## Indoors everywhere (the light that goes with you).
func indoors(_p: Vector3) -> bool:
	return true


# --- The layout (on a worker) ----------------------------------------------------------

static func _make(st: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := 5
	# A tree of rooms over the grid, from the entrance (west edge, middle).
	var start_c := Vector2i(0, n / 2)
	var depth := {start_c: 0}
	var parent := {}
	var frontier: Array = [start_c]
	var want := rng.randi_range(9, 13)
	while depth.size() < want and not frontier.is_empty():
		var c: Vector2i = frontier[rng.randi() % frontier.size()]
		var opts: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if nb.x >= 0 and nb.y >= 0 and nb.x < n and nb.y < n and not depth.has(nb):
				opts.append(nb)
		if opts.is_empty():
			frontier.erase(c)
			continue
		var nb: Vector2i = opts[rng.randi() % opts.size()]
		depth[nb] = int(depth[c]) + 1
		parent[nb] = c
		frontier.append(nb)
	var deepest := start_c
	for c in depth:
		if int(depth[c]) > int(depth[deepest]):
			deepest = c
	var b := CosmosTown.Builder.new()
	b.rng.seed = seed + 1
	b.taper = 1.35
	var W := CELL * n
	# The floor and the roof over all of it.
	b.box(Vector3(-2, -0.6, -2), Vector3(W + 2, 0.0, W + 2), CosmosTown.STONE)
	b.box(Vector3(-2, H, -2), Vector3(W + 2, H + 0.6, W + 2), CosmosTown.ROOF)
	var rects := {}
	var out_rooms: Array = []
	for c in depth:
		var size := Vector2(rng.randf_range(8.0, 12.0), rng.randf_range(8.0, 12.0)) if c != start_c else Vector2(9, 9)
		var ctr := Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)
		var r := Rect2(ctr - size * 0.5, size)
		rects[c] = r
		out_rooms.append([r, int(depth[c])])
	# Walls round every room, a doorway where a corridor meets it; the corridors' walls.
	var links := {}
	for c in parent:
		links[[c, parent[c]]] = true
		links[[parent[c], c]] = true
	var flames: Array = []
	var torch_pos: Array = []
	var rocks := PackedFloat32Array()   # (a cave's: boulders lining its walls, lumps overhead - one multimesh)
	for c in depth:
		var r: Rect2 = rects[c]
		for side in 4:
			var d: Vector2i = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)][side]
			var open := links.has([c, c + d])
			_room_wall(b, r, side, open)
			if open and (side == 1 or side == 3):
				_corridor(b, r, rects[c + d], side == 1)
		# Its torches (two a room), its dressing.
		for k in 2:
			var tp := Vector3(r.position.x + WALL + 0.25, 2.6, r.position.y + r.size.y * (0.3 + 0.4 * k)) if k == 0 else Vector3(r.end.x - WALL - 0.25, 2.6, r.position.y + r.size.y * 0.6)
			b.box(tp + Vector3(-0.08, -0.5, -0.08), tp + Vector3(0.08, 0.0, 0.08), CosmosTown.BLACK, false)
			flames.append(tp)
			torch_pos.append(tp + Vector3(0, 0.3, 0))
		if st == "cave":
			var per := 2.0 * (r.size.x + r.size.y)
			for k in int(per / 1.4):
				var t := float(k) / int(per / 1.4) * per
				var p: Vector3
				if t < r.size.x:
					p = Vector3(r.position.x + t, 0, r.position.y)
				elif t < r.size.x + r.size.y:
					p = Vector3(r.end.x, 0, r.position.y + t - r.size.x)
				elif t < 2.0 * r.size.x + r.size.y:
					p = Vector3(r.end.x - (t - r.size.x - r.size.y), 0, r.end.y)
				else:
					p = Vector3(r.position.x, 0, r.end.y - (t - 2.0 * r.size.x - r.size.y))
				# (not in a doorway)
				var c2 := r.get_center()
				if (absf(p.x - c2.x) < 2.0 and (absf(p.z - r.position.y) < 0.1 or absf(p.z - r.end.y) < 0.1)) or (absf(p.z - c2.y) < 2.0 and (absf(p.x - r.position.x) < 0.1 or absf(p.x - r.end.x) < 0.1)):
					continue
				var sc := rng.randf_range(0.55, 1.0)
				var bas := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(sc, sc * rng.randf_range(1.0, 1.8), sc))
				var outward := (p - Vector3(c2.x, 0, c2.y))
				outward = Vector3(signf(outward.x) if absf(p.x - r.position.x) < 0.1 or absf(p.x - r.end.x) < 0.1 else 0.0, 0,
					signf(outward.z) if absf(p.z - r.position.y) < 0.1 or absf(p.z - r.end.y) < 0.1 else 0.0)
				_rock(rocks, Transform3D(bas, p + outward * 0.5 + Vector3(0, rng.randf_range(0.0, 2.2), 0)))   # (set into the wall)
			for k in int(r.size.x * r.size.y / 14.0):   # (lumps overhead)
				var p := Vector3(rng.randf_range(r.position.x, r.end.x), H - 0.2, rng.randf_range(r.position.y, r.end.y))
				var sc := rng.randf_range(0.6, 1.3)
				_rock(rocks, Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * 0.5, sc)), p + Vector3(0, 0.3, 0)))
			for k in rng.randi_range(4, 9):   # (boulders along the walls, stalagmites)
				var p := Vector3(rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), 0, rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
				var near_edge := minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.z - r.position.y, r.end.y - p.z)) < 2.2
				if near_edge:
					var sz := rng.randf_range(0.8, 2.2)
					b.box(p - Vector3(sz, 0, sz) * 0.5, p + Vector3(sz * 0.5, sz * rng.randf_range(0.5, 1.2), sz * 0.5), CosmosTown.WALL)
				elif rng.randf() < 0.5:
					var hh := rng.randf_range(0.6, 2.4)
					b.box(p - Vector3(0.25, 0, 0.25), p + Vector3(0.25, hh, 0.25), CosmosTown.STONE)
					b.box(p - Vector3(0.12, -hh, 0.12), p + Vector3(0.12, hh + 0.4, 0.12), CosmosTown.STONE)
				var drip := p + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))   # (stalactites, overhead)
				b.box(drip + Vector3(-0.2, H - rng.randf_range(0.6, 1.6), -0.2), drip + Vector3(0.2, H, 0.2), CosmosTown.STONE, false)
		elif r.size.x > 9.5 and r.size.y > 9.5 and c != start_c:
			for k in 4:   # (the old labyrinth's pillars - red, wider at the top)
				var p := Vector3(r.position.x + r.size.x * (0.3 if k % 2 == 0 else 0.7), 0, r.position.y + r.size.y * (0.3 if k < 2 else 0.7))
				b.column(p, H, 0.35)
		b.spots.append(Vector3(r.get_center().x, 0, r.get_center().y))
	# The entrance: stairs up against the west wall of the first room.
	var sr: Rect2 = rects[start_c]
	b.stairs(Vector3(sr.position.x + WALL + 0.3, 0.0, sr.get_center().y), Vector3(1, 0, 0), 6, 2.4, 0.4, 0.5)
	var exit := Vector3(sr.position.x + WALL + 3.6, 0.0, sr.get_center().y)
	var start := Vector3(sr.position.x + WALL + 4.5, 0.0, sr.get_center().y)
	# The chest in the deepest room, on a dais; horns on it in the labyrinth.
	var dr: Rect2 = rects[deepest]
	var chest := Vector3(dr.get_center().x, 0.3, dr.get_center().y)
	b.box(chest + Vector3(-1.6, -0.3, -1.2), chest + Vector3(1.6, 0.0, 1.2), CosmosTown.STONE)
	b.box(chest + Vector3(-0.6, 0.0, -0.4), chest + Vector3(0.6, 0.7, 0.4), CosmosTown.WOOD)
	b.box(chest + Vector3(-0.65, 0.7, -0.45), chest + Vector3(0.65, 0.8, 0.45), CosmosTown.TRIM, false)
	if st == "dungeon":
		b.horns(chest + Vector3(0, 0.0, -1.0), true)
	# The flames: a separate mesh (they glow).
	var fb := CosmosTown.Builder.new()
	for p: Vector3 in flames:
		fb.box(p + Vector3(-0.1, 0.0, -0.1), p + Vector3(0.1, 0.32, 0.1), 0, false)
	return {"mesh": b.mesh(), "flames": fb.mesh(), "solids": b.solids, "grid": b.grid(), "spots": b.spots, "rooms": out_rooms,
		"start": start, "exit": exit, "chest": chest, "lights": torch_pos, "rocks": rocks}


## A labyrinth room's things: storage jars in its corners, the bones of the
## ones who came before (heaps of them, a skull), a bench along a wall.
static func _dress(b: CosmosTown.Builder, rng: RandomNumberGenerator, r: Rect2) -> void:
	var m := 1.0
	var corners := [Vector3(r.position.x + m, 0, r.position.y + m), Vector3(r.end.x - m, 0, r.position.y + m),
		Vector3(r.position.x + m, 0, r.end.y - m), Vector3(r.end.x - m, 0, r.end.y - m)]
	for k in corners.size():
		match rng.randi() % 3:
			0:
				b._jar(corners[k])
				if rng.randf() < 0.5:
					b._jar(corners[k] + Vector3(0.9 * (1.0 if k % 2 == 0 else -1.0), 0, 0))
			1:   # (bones: long ones strewn, a skull)
				var at: Vector3 = corners[k] + Vector3(0.6 * (1.0 if k % 2 == 0 else -1.0), 0, 0.6 * (1.0 if k < 2 else -1.0))
				for j in rng.randi_range(3, 6):
					var o := at + Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
					if rng.randf() < 0.5:
						b.box(o + Vector3(-0.35, 0, -0.04), o + Vector3(0.35, 0.07, 0.04), CosmosTown.HORNS, false)
					else:
						b.box(o + Vector3(-0.04, 0, -0.35), o + Vector3(0.04, 0.07, 0.35), CosmosTown.HORNS, false)
				b.box(at + Vector3(-0.1, 0, -0.12), at + Vector3(0.1, 0.18, 0.12), CosmosTown.HORNS, false)
	if rng.randf() < 0.5:   # (a stone bench)
		var z := r.position.y + 0.3
		b.box(Vector3(r.get_center().x - 1.8, 0, z), Vector3(r.get_center().x - 0.6, 0.45, z + 0.5), CosmosTown.STONE)
		b.box(Vector3(r.get_center().x + 0.6, 0, z), Vector3(r.get_center().x + 1.8, 0.45, z + 0.5), CosmosTown.STONE)


static func _rock(buf: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	buf.append_array([b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y, b.x.z, b.y.z, b.z.z, t.origin.z])


## One side of a room's walls (0 -x, 1 +x, 2 -z, 3 +z), a doorway in its middle if `open`.
static func _room_wall(b: CosmosTown.Builder, r: Rect2, side: int, open: bool) -> void:
	var gap := 3.0
	var a: Vector3
	var e: Vector3
	match side:
		0: a = Vector3(r.position.x - WALL, 0, r.position.y - WALL); e = Vector3(r.position.x, H, r.end.y + WALL)
		1: a = Vector3(r.end.x, 0, r.position.y - WALL); e = Vector3(r.end.x + WALL, H, r.end.y + WALL)
		2: a = Vector3(r.position.x, 0, r.position.y - WALL); e = Vector3(r.end.x, H, r.position.y)
		_: a = Vector3(r.position.x, 0, r.end.y); e = Vector3(r.end.x, H, r.end.y + WALL)
	if not open:
		b.box(a, e, CosmosTown.WALL)
		return
	var ax := 2 if side < 2 else 0
	var mid := (a[ax] + e[ax]) * 0.5
	var e1 := e
	e1[ax] = mid - gap * 0.5
	b.box(a, e1, CosmosTown.WALL)
	var a2 := a
	a2[ax] = mid + gap * 0.5
	b.box(a2, e, CosmosTown.WALL)


## The walls of the way from room `r` to the next (`along_x`: to the east, else south).
static func _corridor(b: CosmosTown.Builder, r: Rect2, r2: Rect2, along_x: bool) -> void:
	var gap := 3.0
	if along_x:
		var z := r.get_center().y
		var x0 := r.end.x + WALL
		var x1 := r2.position.x - WALL
		b.box(Vector3(x0, 0, z - gap * 0.5 - WALL), Vector3(x1, H, z - gap * 0.5), CosmosTown.WALL)
		b.box(Vector3(x0, 0, z + gap * 0.5), Vector3(x1, H, z + gap * 0.5 + WALL), CosmosTown.WALL)
	else:
		var x := r.get_center().x
		var z0 := r.end.y + WALL
		var z1 := r2.position.y - WALL
		b.box(Vector3(x - gap * 0.5 - WALL, 0, z0), Vector3(x - gap * 0.5, H, z1), CosmosTown.WALL)
		b.box(Vector3(x + gap * 0.5, 0, z0), Vector3(x + gap * 0.5 + WALL, H, z1), CosmosTown.WALL)
