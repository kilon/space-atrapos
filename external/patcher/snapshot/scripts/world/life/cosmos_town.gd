class_name CosmosTown
extends CosmosSolids
## A town on a planet (the 3D game): the Aegean towns of the 2D game in 3D -
## a city round a palace, or a village - in the empire's looks (its palette:
## BuildingLook's themes - Minoan ochre walls and red columns, Athenian white
## and blue, Spartan bronze...). Assembled from modular pieces by its seed:
##   the palace - wings of 1-3 storeys round a central court (stepped
##     masses, fresco bands, cornices, windows, horns of consecration on the
##     roofs), a colonnade of Aegean columns (wider at the top, dark
##     capitals), a gateway, an altar, a grand staircase up onto the roofs;
##   houses - flat-roofed blocks of 1-3 storeys on lots along lanes, doors,
##     windows, parapets, now and then horns, a roof pergola;
##   a shrine (three rooms, the middle one tallest, columns in front), a
##     storehouse with its jars (pithoi), a landing field for your ship.
## Each empire builds its own way (from its tile sheet - data/sprites/tile_<empire>_*):
##   Minoa - plaster and timber, red columns wider at the top, horns of
##     consecration, running spirals;
##   Athens - marble ashlar, white Doric columns, the meander, tiled gable
##     roofs with pediments on its temple and its great hall, acroteria;
##   Sparta - grey limestone on a crimson base, bronze shields hung on its
##     walls, lambdas, plain flat roofs;
##   Mycenae - cyclopean masonry (great many-sided blocks), a gold band, the
##     relieving triangle over its doors, red columns, a beehive tholos for a
##     shrine;
##   Ionia - marble between lapis bands, slim lapis columns under gold
##     volutes, a gold armillary on a roof here and there, a temple;
##   the Cyclades - whitewashed cubes with blue bands and blue domes, square
##     pillars, a marble figure before the chapel.
## Every piece is a box or a column in the town's frame (y up, 0 the ground):
## all drawn as one mesh - colours in its vertices as slots (building
## shader: the palette's colours are shader parameters - recolour a town by
## setting them), built on a worker. The same pieces are solid (Cosmos:
## walker_bumps, the camera) and low ones are floors: stairs, roofs.
## The ground under a town is levelled (PlanetShape.flats).

const WALL_T := BuildKit.WALL_T   # m: the buildings' walls (the kit's)
const DOOR_W := BuildKit.DOOR_W
const DOOR_H := BuildKit.DOOR_H
const CELL := 8.0              # the solids' grid
const CHUNK := 48.0            # m: a mesh a block this size
const FLOOR := 0.15             # m: a building's floor over the ground
const STOREY := FLOOR + BuildKit.WALL_H   # (a storey's top: the kit's)
const SHADER := preload("res://shaders/world/building.gdshader")
## Slots (the vertices' red channel): the palette's parts.
enum { WALL, STONE, PALE, RED, BLACK, FRESCO, TRIM, DARK, HORNS, WOOD, JAR, ROOF }
## The empires' looks: [wall, stone, pale, column, capital, fresco, trim, dark, horns, wood, jar, roof],
## and the columns' taper (> 1: wider at the top, the Aegean way).
const LOOKS := {
	"minoa": [[0.93, 0.83, 0.64], [0.76, 0.72, 0.64], [0.9, 0.88, 0.82], [0.62, 0.1, 0.07], [0.08, 0.07, 0.07], [0.18, 0.42, 0.75],
		[0.55, 0.14, 0.08], [0.05, 0.04, 0.035], [0.93, 0.9, 0.84], [0.36, 0.22, 0.12], [0.7, 0.38, 0.2], [0.82, 0.74, 0.6], 1.35],
	"athens": [[0.94, 0.94, 0.95], [0.82, 0.82, 0.8], [0.95, 0.95, 0.96], [0.2, 0.33, 0.7], [0.86, 0.76, 0.48], [0.18, 0.32, 0.72],
		[0.84, 0.72, 0.42], [0.05, 0.05, 0.07], [0.97, 0.97, 0.97], [0.36, 0.24, 0.14], [0.72, 0.52, 0.4], [0.88, 0.88, 0.88], 0.8],
	"sparta": [[0.62, 0.58, 0.52], [0.52, 0.5, 0.46], [0.72, 0.68, 0.62], [0.5, 0.09, 0.06], [0.6, 0.4, 0.18], [0.55, 0.1, 0.06],
		[0.7, 0.45, 0.2], [0.06, 0.04, 0.03], [0.78, 0.7, 0.6], [0.3, 0.18, 0.1], [0.6, 0.4, 0.3], [0.56, 0.52, 0.47], 0.85],
	"mycenae": [[0.64, 0.62, 0.57], [0.5, 0.48, 0.45], [0.75, 0.72, 0.66], [0.45, 0.18, 0.1], [0.95, 0.76, 0.28], [0.5, 0.2, 0.12],
		[0.9, 0.72, 0.28], [0.05, 0.045, 0.04], [0.85, 0.82, 0.75], [0.33, 0.22, 0.13], [0.62, 0.36, 0.2], [0.55, 0.53, 0.5], 1.3],
	"ionia": [[0.95, 0.93, 0.88], [0.8, 0.78, 0.72], [0.93, 0.92, 0.88], [0.16, 0.24, 0.62], [0.95, 0.78, 0.35], [0.25, 0.4, 0.95],
		[0.95, 0.78, 0.35], [0.04, 0.05, 0.08], [0.96, 0.94, 0.9], [0.35, 0.23, 0.13], [0.7, 0.4, 0.22], [0.85, 0.82, 0.76], 0.85],
	"cyclades": [[0.98, 0.98, 0.97], [0.86, 0.85, 0.82], [0.97, 0.97, 0.96], [0.12, 0.42, 0.78], [0.95, 0.95, 0.95], [0.1, 0.5, 0.85],
		[0.12, 0.42, 0.78], [0.05, 0.08, 0.12], [0.98, 0.98, 0.98], [0.3, 0.24, 0.18], [0.72, 0.44, 0.26], [0.95, 0.95, 0.94], 1.25],
	"pirates": [[0.34, 0.32, 0.36], [0.3, 0.28, 0.3], [0.4, 0.38, 0.4], [0.35, 0.05, 0.08], [0.12, 0.1, 0.1], [1.0, 0.25, 0.15],
		[0.25, 0.08, 0.08], [0.03, 0.03, 0.03], [0.6, 0.55, 0.5], [0.2, 0.15, 0.1], [0.4, 0.25, 0.18], [0.3, 0.28, 0.3], 1.0],
	# (underground: the old labyrinths' dressed stone, a cave's rock - CosmosDungeon)
	"dungeon": [[0.36, 0.34, 0.31], [0.26, 0.24, 0.22], [0.5, 0.47, 0.42], [0.5, 0.1, 0.07], [0.08, 0.07, 0.06], [0.2, 0.3, 0.45],
		[0.55, 0.42, 0.2], [0.03, 0.03, 0.03], [0.7, 0.66, 0.58], [0.3, 0.2, 0.12], [0.5, 0.3, 0.18], [0.2, 0.19, 0.18], 1.35],
	"cave": [[0.33, 0.28, 0.23], [0.25, 0.21, 0.17], [0.4, 0.35, 0.29], [0.4, 0.3, 0.22], [0.1, 0.08, 0.07], [0.3, 0.32, 0.3],
		[0.3, 0.25, 0.2], [0.03, 0.03, 0.03], [0.5, 0.45, 0.4], [0.3, 0.2, 0.12], [0.45, 0.3, 0.2], [0.18, 0.16, 0.14], 1.0],
	"": [[0.9, 0.72, 0.48], [0.78, 0.64, 0.46], [0.9, 0.8, 0.64], [0.75, 0.4, 0.2], [0.25, 0.16, 0.1], [0.2, 0.6, 0.6],
		[0.7, 0.4, 0.2], [0.05, 0.04, 0.03], [0.92, 0.85, 0.72], [0.36, 0.22, 0.12], [0.7, 0.38, 0.2], [0.8, 0.66, 0.48], 1.2]}
const ROUGH := [0.85, 0.9, 0.7, 0.55, 0.5, 0.75, 0.6, 0.9, 0.8, 0.85, 0.8, 0.9]
## The fresco band's pattern (the building shader's band_style): 0 running spirals, 1 the meander, 2 lambdas, 3 rosettes, 4 egg and dart.
const BANDS := {"athens": 1, "sparta": 2, "mycenae": 3, "ionia": 4, "cyclades": 0, "minoa": 0}
const NAMES := ["Amnisos", "Phaistos", "Zakros", "Malia", "Gournia", "Tylissos", "Archanes", "Myrtos", "Pyrgos",
	"Palaikastro", "Kommos", "Mochlos", "Vathypetro", "Galatas", "Petras", "Sklavokampos", "Pseira", "Kato Zakros"]
## The other empires' towns: their own places (the Attic demes, Sparta's villages
## and Laconia's towns, the Argolid's, Ionia's cities, the Cyclades' old settlements).
const TOWN_NAMES := {
	"athens": ["Acharnai", "Kephisia", "Kolonos", "Melite", "Alopeke", "Kydathenaion", "Paiania", "Aixone", "Halai",
		"Lamptrai", "Anaphlystos", "Kollytos", "Skambonidai", "Probalinthos"],
	"sparta": ["Pitane", "Mesoa", "Limnai", "Kynosoura", "Aigys", "Leuktron", "Pharis", "Bryseai", "Thalamai", "Pephnos",
		"Krokeai", "Glympeis"],
	"mycenae": ["Midea", "Dendra", "Prosymna", "Berbati", "Asine", "Lerna", "Nauplion", "Kleonai", "Phlious", "Hysiai",
		"Zygouries", "Mases"],
	"ionia": ["Teos", "Priene", "Myous", "Kolophon", "Erythrai", "Klazomenai", "Phokaia", "Lebedos", "Magnesia", "Didyma",
		"Notion", "Larisa"],
	"cyclades": ["Phylakopi", "Ayia Irini", "Grotta", "Skarkos", "Markiani", "Daskalio", "Koukounaries", "Mikri Vigla",
		"Panormos", "Arkesine", "Aigiale", "Zas"],
}

var site := {}                 # {dir, h, r, kind, seed, yaw, empire, name}
var planet: CosmosPlanet
var spots: Array = []          # open ground (town-local): where people walk
var port := Vector3.ZERO       # the landing field's middle (town-local)
var doors: Array = []          # [threshold, out] (town-local): its buildings' doorways
var built := false
var _task := -1
var _out := {}                 # the worker's: mesh, solids, grid, spots
static var _mats := {}         # empire -> ShaderMaterial


## A planet's town sites: a city (with its palace) and a village or two, on
## dry ground level enough, apart. Ocean and ice worlds only (the inhabited
## kinds); none on a pirates' world.
## `day`: towards its star (planets don't turn): the towns on the lit side -
## the city near the middle of the day, the villages anywhere it's light.
static func sites(shape: PlanetShape, rec: Dictionary, empire: String, day := Vector3.ZERO) -> Array:
	var out: Array = []
	var type := str(rec.get("type", ""))
	if shape.kind != "rocky" or empire == "pirates" or type in ["moon", "volcanic", "akrotiri", "selene"]:
		return out
	if not (shape.sea in [1, 2] or type in ["ocean", "ice", "thalassa", "krystallos"]):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec.get("seed", 1)) * 31 + 7
	var want := rng.randi_range(3, 5)
	var tries := 0
	while out.size() < want and tries < 120:
		tries += 1
		var kind := "city" if out.is_empty() else "village"
		var r := 175.0 if kind == "city" else 130.0     # (the town, its landing field)
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		if day != Vector3.ZERO and d.dot(day) < (0.55 if kind == "city" else 0.15) - tries * 0.004:
			continue
		var far := true
		for o in out:
			if (o["dir"] as Vector3).dot(d) > cos(2500.0 / shape.radius):
				far = false
		if not far:
			continue
		var h0 := shape.raw_height(d)
		if h0 < 4.0 or h0 > shape.amp * 0.6:
			continue
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := d.cross(t1)
		var lo := h0
		var hi := h0
		var sum := h0
		for k in 8:
			var o := t1.rotated(d, k * TAU / 8.0) * r * (0.6 if k % 2 else 1.0)
			var hh := shape.raw_height((d * shape.radius + o).normalized())
			lo = minf(lo, hh)
			hi = maxf(hi, hh)
			sum += hh
		if hi - lo > 14.0 or lo < 2.5:
			continue
		var h := sum / 9.0
		var names: Array = TOWN_NAMES.get(empire, NAMES)
		var name: String = names[(int(rec.get("seed", 1)) + out.size() * 7) % names.size()]
		out.append({"dir": d, "h": h, "r": r, "kind": kind, "seed": rng.randi(), "yaw": rng.randf() * TAU,
			"empire": empire, "name": name, "t1": t1, "t2": t2})
	return out


## Its levelled ground: PlanetShape.flats entries.
static func flats_of(towns: Array, radius: float) -> Array:
	var out: Array = []
	for s in towns:
		var r: float = s["r"]
		out.append([s["dir"], cos(r / radius), cos((r + 60.0) / radius), float(s["h"]), cos((r + 12.0) / radius)])
	return out


## The town's frame on its planet (planet-local).
static func frame(s: Dictionary, radius: float) -> Transform3D:
	var u: Vector3 = s["dir"]
	var x: Vector3 = (s["t1"] as Vector3).rotated(u, float(s["yaw"]))
	return Transform3D(Basis(x, u, x.cross(u)), u * (radius + float(s["h"])))


func setup(pl: CosmosPlanet, s: Dictionary) -> void:
	planet = pl
	site = s
	name = str(s["name"]).replace(" ", "_")
	add_to_group("cam_solid")
	set_meta("cam_reach", float(s["r"]) + 60.0)
	set_meta("edit_key", "town/%s/%s/%d" % [str(s.get("empire", "")), str(s["kind"]), int(s["seed"])])   # (the Live Editor's edits: this town - its seed lays it out)



## Its buildings wanted (near) or not (far): built on a worker, or let go.
func want(on: bool) -> void:
	if on and not built and _task < 0:
		var seed: int = site["seed"]
		var kind: String = site["kind"]
		var empire: String = site["empire"]
		_task = Jobs.add(func(): _out = _make(kind, seed, empire), false, "town")
	elif not on and built:
		for ch in get_children():
			ch.queue_free()
		_solids = []
		_grid = {}
		built = false


## Its name on the HUD: the palace's for a city.
func title() -> String:
	return ("Palace of %s" if str(site["kind"]) == "city" else "%s") % str(site["name"])


## Its meshes and solids in, once the worker's done (Cosmos checks).
func poll() -> bool:
	if built:
		return true
	if not _blocks.is_empty():
		_add_block()   # (its blocks put in one a frame: each a GPU upload - all at once, a long frame in a browser)
		if not _blocks.is_empty():
			return false
		built = true
		return true
	if _task < 0 or not Jobs.done(_task):
		return false
	Jobs.wait(_task)
	_task = -1
	_blocks = (_out["meshes"] as Array).duplicate()   # (a block of the town a mesh: off-screen ones and far shadows not drawn)
	_solids = _out["solids"]
	_grid = _out["grid"]
	SolidsEdit.installed(self)   # (its solids as edited in the Live Editor, if they were)
	spots = _out["spots"]
	port = _out["port"]
	doors = _out["doors"]
	_out = {}
	if not _blocks.is_empty():
		_add_block()
	if _blocks.is_empty():
		built = true
	return built


var _blocks: Array = []   # (the town's meshes still to put in - poll, one a frame)
var _block_n := 0


func _add_block() -> void:
	var m: ArrayMesh = _blocks.pop_front()
	var mi := MeshInstance3D.new()
	mi.name = "Buildings%d" % _block_n
	mi.mesh = m
	mi.material_override = material(str(site["empire"]))
	mi.visibility_range_end = 6000.0
	add_child(mi)
	_block_n += 1


func _exit_tree() -> void:
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1


## The building shader with an empire's palette (shared by its towns).
## `kit`: the building kit's own (BuildKit.material) - its trim and its black
## always metal (bronze), its paints and its flames' glow.
static func material(empire: String, kit := false) -> ShaderMaterial:
	var mk := empire + ("|kit" if kit else "")
	if _mats.has(mk):
		return _mats[mk]
	var L: Array = LOOKS.get(empire, LOOKS[""])
	var cols := PackedColorArray()
	var looks := PackedVector4Array()
	for i in 12:
		var c: Array = L[i]
		cols.append(Color(c[0], c[1], c[2]).srgb_to_linear())
		var metal := (i == BLACK and empire in ["sparta", "mycenae", "ionia"]) or (i == TRIM and empire in ["sparta", "mycenae", "ionia", "athens"])
		if kit and i in [TRIM, BLACK]:
			looks.append(Vector4(0.34 if i == TRIM else 0.45, 0.92 if i == TRIM else 0.8, 0.0, 0.0))
			continue
		looks.append(Vector4(0.4 if metal else ROUGH[i], 0.85 if metal else 0.0, 0.0, 0.0))
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("slot_color", cols)
	m.set_shader_parameter("slot_look", looks)
	var nz := Cosmos.noise_ready()
	if nz:
		m.set_shader_parameter("noise_tex", nz)
	# (cut stone: 1 the stone, 2 the walls too, 0 none - rough rock; Mycenae's: cyclopean)
	m.set_shader_parameter("ashlar", 0.0 if empire == "cave" else (2.0 if empire in ["dungeon", "athens", "ionia", "sparta", "mycenae"] else 1.0))
	m.set_shader_parameter("cyclopean", 1.0 if empire == "mycenae" else 0.0)
	m.set_shader_parameter("band_style", int(BANDS.get(empire, 0)))
	var ink: Array = L[TRIM] if empire in ["sparta", "mycenae"] else [0.93, 0.88, 0.74]
	m.set_shader_parameter("band_ink", Color(ink[0], ink[1], ink[2]).srgb_to_linear())
	if kit:
		var pc := PackedColorArray()
		for c in BuildKit.PAINTS:
			pc.append(Color(c.r, c.g, c.b).srgb_to_linear())
		m.set_shader_parameter("paint_color", pc)
		m.set_shader_parameter("glow_color", Color(1.0, 0.55, 0.18))
	_mats[mk] = m
	return m


# (Walking, the ship's and the camera's obstacles: CosmosSolids - floor_top, push, indoors, push_ball, cam_hit.)

func is_built() -> bool:
	return built


# --- The layout and its mesh (on a worker) --------------------------------------------

## Everything built: {mesh, solids, grid, spots, port}.
static func _make(kind: String, seed: int, empire: String) -> Dictionary:
	var b := Builder.new()
	b.rng.seed = seed
	b.taper = float((LOOKS.get(empire, LOOKS[""]) as Array)[12])
	b.emp = empire
	var lay := layout(kind)
	var half: float = lay["half"]
	if kind == "city":
		b.palace(Vector3.ZERO)
		b.houses(half, Rect2(-46, -38, 92, 76))
		b.shrine(lay["shrine"])
		b.storehouse(lay["store"])
	else:
		b.shrine(lay["shrine"])
		b.houses(half, Rect2(-14, -22, 28, 26))
		b.storehouse(lay["store"])
	# The paved square and the landing field beyond the houses.
	var port: Vector3 = lay["port"]
	b.box(Vector3(-half, -0.6, -half), Vector3(half, 0.04, half), PALE, false)
	b.box(port - Vector3(34, 0.6, 34), port + Vector3(34, 0.05, 34), STONE, false)
	for k in 4:   # (its corner lights: dark posts with red tops - solid: you walk round them, not through)
		var c := port + Vector3(32.0 * (1 if k % 2 else -1), 0, 32.0 * (1 if k < 2 else -1))
		b.box(c - Vector3(0.3, 0, 0.3), c + Vector3(0.3, 2.2, 0.3), BLACK)
		b.box(c + Vector3(-0.4, 2.2, -0.4), c + Vector3(0.4, 2.6, 0.4), RED)
	b.spots.append(port + Vector3(-36, 0, 0))
	b.solids = CosmosSolids.merge_boxes(b.solids)   # (the kit's walls, piece by piece, made long blocks: fewer to look through)
	return {"meshes": b.meshes_by(CHUNK), "solids": b.solids, "grid": b.grid(), "spots": b.spots, "port": port, "doors": b.doors}


## Where a town's parts stand (town-local, y up): its square's half-size,
## the landing field's middle, the shrine and the storehouse (_make builds
## them there; the planet map's town plans label them).
static func layout(kind: String) -> Dictionary:
	var half := 85.0 if kind == "city" else 45.0
	if kind == "city":
		return {"half": half, "port": Vector3(half + 38.0, 0, 0), "shrine": Vector3(-half + 16, 0, half - 16), "store": Vector3(half - 18, 0, -half + 14)}
	return {"half": half, "port": Vector3(half + 38.0, 0, 0), "shrine": Vector3(0, 0, -10), "store": Vector3(half - 14, 0, half - 12)}


## A town's points of interest for its map: [id, name, town-local position] -
## the palace (a city's), the shrine, the storehouse, the landing field and,
## by a city's field, its ore buyer, courier's office and local pilot
## (CosmosSandbox.spots).
static func places(kind: String) -> Array:
	var lay := layout(kind)
	var out: Array = []
	if kind == "city":
		out.append(["palace", "Palace", Vector3.ZERO])
	out.append(["shrine", "Shrine", lay["shrine"]])
	out.append(["store", "Storehouse", lay["store"]])
	out.append(["field", "Landing field", lay["port"]])
	if kind == "city":
		var names := {"vendor": "Ore buyer", "courier": "Courier's office", "pilot": "Local pilot"}
		for sp in CosmosSandbox.spots():
			out.append([str(sp[0]), str(names.get(sp[0], sp[0])), (lay["port"] as Vector3) + (sp[1] as Vector3)])
	return out


## A town's plan (for its map - on a worker): its buildings' solids (AABBs,
## town-local), as _make lays them out for its seed.
static func plan_of(kind: String, seed: int, empire: String) -> Array:
	return _make(kind, seed, empire)["solids"]


## The pieces, as they're laid out: vertex arrays and solids.
class Builder:
	var rng := RandomNumberGenerator.new()
	var taper := 1.3
	var emp := ""                # (whose town: its own columns, roofs, ornaments)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var solids: Array = []
	var spots: Array = []
	var taken: Array = []        # Rect2s (ground taken)
	var doors: Array = []        # [threshold (town-local), out] - each building's way in

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	## Its faces in blocks `size` m square (by where each quad stands): a mesh a block.
	func meshes_by(size: float) -> Array:
		var bins := {}
		for q in verts.size() / 4:
			var v0 := verts[q * 4]
			var key := Vector2i(floori(v0.x / size), floori(v0.z / size))
			if not bins.has(key):
				bins[key] = CosmosTown.Builder.new()
			var o: CosmosTown.Builder = bins[key]
			var base := o.verts.size()
			for j in 4:
				o.verts.append(verts[q * 4 + j])
				o.norms.append(norms[q * 4 + j])
				o.cols.append(cols[q * 4 + j])
			for j in 6:
				o.idx.append(idx[q * 6 + j] - q * 4 + base)
		var out := []
		for key in bins:
			out.append((bins[key] as CosmosTown.Builder).mesh())
		return out

	func grid() -> Dictionary:
		return CosmosSolids.grid_of(solids)

	## A quad a, b, c, d (in order round it) facing `n`.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		var base := verts.size()
		verts.append_array([a, b, c, d])
		for k in 4:
			norms.append(n)
			cols.append(col)
		if (b - a).cross(c - a).dot(n) > 0.0:   # (Godot's front faces wind clockwise)
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	## A quad with a normal at each corner (smooth shading: lathes, tubes).
	func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color) -> void:
		var base := verts.size()
		verts.append_array([a, b, c, d])
		norms.append_array([na, nb, nc, nd])
		for k in 4:
			cols.append(col)
		if (b - a).cross(c - a).dot(na + nb + nc + nd) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	## A shape turned on a lathe round the vertical through `at`: `profile` is
	## [Vector2(radius, height)...] from the bottom up, `segs` round; each
	## stretch's slot (one for all, or one per stretch). Smooth normals.
	func lathe(at: Vector3, profile: Array, segs: int, slots, cap := true) -> void:
		var nrm2: Array = []   # (each profile point's 2D normal: averaged from its stretches)
		for i in profile.size():
			var a: Vector2 = profile[maxi(i - 1, 0)]
			var b: Vector2 = profile[mini(i + 1, profile.size() - 1)]
			var t := (b - a).normalized()
			nrm2.append(Vector2(t.y, -t.x))
		for i in profile.size() - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			if p0.distance_to(p1) < 0.0001:
				continue
			var sl: int = slots if slots is int else slots[mini(i, slots.size() - 1)]
			var col := Color(sl / 255.0, rng.randf(), 0.0)
			var n0: Vector2 = nrm2[i]
			var n1: Vector2 = nrm2[i + 1]
			if absf(p1.x - p0.x) > 2.0 * absf(p1.y - p0.y):   # (a flat ledge: its own normal, crisp)
				var t := (p1 - p0).normalized()
				n0 = Vector2(t.y, -t.x)
				n1 = n0
			for k in segs:
				var a0 := TAU * k / segs
				var a1 := TAU * (k + 1) / segs
				var d0 := Vector3(cos(a0), 0, sin(a0))
				var d1 := Vector3(cos(a1), 0, sin(a1))
				quad_n(at + d0 * p0.x + Vector3(0, p0.y, 0), at + d1 * p0.x + Vector3(0, p0.y, 0),
					at + d1 * p1.x + Vector3(0, p1.y, 0), at + d0 * p1.x + Vector3(0, p1.y, 0),
					(d0 * n0.x + Vector3(0, n0.y, 0)).normalized(), (d1 * n0.x + Vector3(0, n0.y, 0)).normalized(),
					(d1 * n1.x + Vector3(0, n1.y, 0)).normalized(), (d0 * n1.x + Vector3(0, n1.y, 0)).normalized(), col)
		var last: Vector2 = profile[profile.size() - 1]
		if cap and last.x > 0.001:   # (its top, flat)
			var sl: int = slots if slots is int else slots[slots.size() - 1]
			var col := Color(sl / 255.0, rng.randf(), 0.0)
			var c := at + Vector3(0, last.y, 0)
			for k in segs:
				var a0 := TAU * k / segs
				var a1 := TAU * (k + 1) / segs
				var e0 := c + Vector3(cos(a0), 0, sin(a0)) * last.x
				var e1 := c + Vector3(cos(a1), 0, sin(a1)) * last.x
				quad(c, e0, e1, c, Vector3.UP, col)

	## A tube along `pts` (radius `radii[i]` at each), `segs` round (horns).
	func tube(pts: Array, radii: Array, segs: int, slot: int) -> void:
		var col := Color(slot / 255.0, rng.randf(), 0.0)
		var rings: Array = []
		for i in pts.size():
			var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			var u := t.cross(Vector3.FORWARD if absf(t.z) < 0.9 else Vector3.RIGHT).normalized()
			var v := t.cross(u)
			var ring: Array = []
			for k in segs:
				var a := TAU * k / segs
				ring.append(u * cos(a) + v * sin(a))
			rings.append(ring)
		for i in pts.size() - 1:
			for k in segs:
				var k1 := (k + 1) % segs
				var n00: Vector3 = rings[i][k]
				var n01: Vector3 = rings[i][k1]
				var n11: Vector3 = rings[i + 1][k1]
				var n10: Vector3 = rings[i + 1][k]
				quad_n(pts[i] + n00 * radii[i], pts[i] + n01 * radii[i], pts[i + 1] + n11 * radii[i + 1], pts[i + 1] + n10 * radii[i + 1],
					n00, n01, n11, n10, col)

	## A round end standing out of a wall at `at` along `n` (a beam's end, a rosette).
	func disc(at: Vector3, n: Vector3, r: float, depth: float, slot: int, segs := 8) -> void:
		var col := Color(slot / 255.0, rng.randf(), 0.0)
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := n.cross(u)
		var f := at + n * depth
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var e0 := u * cos(a0) + v * sin(a0)
			var e1 := u * cos(a1) + v * sin(a1)
			quad_n(at + e0 * r, at + e1 * r, f + e1 * r, f + e0 * r, e0, e1, e1, e0, col)
			quad(f, f + e0 * r, f + e1 * r, f, n, col)

	## A box a..b in palette slot `slot`; `skip`: faces never seen, left out
	## (1 top, 2 foot, 4 -z, 8 +z, 16 +x, 32 -x).
	func box(a: Vector3, b: Vector3, slot: int, solid := true, skip := 0) -> void:
		var mn := a.min(b)   # (its corners in any order)
		var mx := a.max(b)
		var col := Color(slot / 255.0, rng.randf(), fposmod(mn.y, 8.0) / 8.0)   # (b: its base's height, for the frescoes' bands)
		var p := [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
			Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]
		if not skip & 1:
			quad(p[4], p[5], p[6], p[7], Vector3.UP, col)
		if mn.y > -0.5 and not skip & 2:
			quad(p[0], p[3], p[2], p[1], Vector3.DOWN, col)
		if not skip & 4:
			quad(p[0], p[1], p[5], p[4], Vector3.FORWARD, col)
		if not skip & 8:
			quad(p[2], p[3], p[7], p[6], Vector3.BACK, col)
		if not skip & 16:
			quad(p[1], p[2], p[6], p[5], Vector3.RIGHT, col)
		if not skip & 32:
			quad(p[3], p[0], p[4], p[7], Vector3.LEFT, col)
		if solid:
			solids.append(AABB(mn, mx - mn))

	## An Aegean column on `at` (a lathe): a dark stone base, the red shaft
	## (wider at the top when taper > 1), the round cushion capital and its
	## square block - dark, the Minoan way.
	func column(at: Vector3, h: float, r := 0.32) -> void:
		match emp:
			"athens", "sparta":
				# Doric: no base, a white shaft narrowing upward with a little swell, the echinus, a square abacus.
				var top := r * 0.8
				lathe(at, [Vector2(r, 0.0), Vector2(r * 0.99, h * 0.3), Vector2(r * 0.93, h * 0.6), Vector2(top, h - 0.5)], 14, PALE, false)
				lathe(at, [Vector2(top, h - 0.5), Vector2(top * 1.05, h - 0.44), Vector2(top * 1.5, h - 0.28), Vector2(top * 1.55, h - 0.24)], 14,
					TRIM if emp == "sparta" else PALE)
				box(at + Vector3(-top * 1.7, h - 0.24, -top * 1.7), at + Vector3(top * 1.7, h, top * 1.7), PALE, false)
				solids.append(AABB(at - Vector3(r, 0, r), Vector3(r * 2.0, h, r * 2.0)))
				return
			"ionia":
				# Ionic: a moulded base, a slim lapis shaft, gold volutes either side under the abacus.
				var rs := r * 0.78
				lathe(at, [Vector2(rs * 1.5, 0.0), Vector2(rs * 1.5, 0.1), Vector2(rs * 1.25, 0.16), Vector2(rs * 1.4, 0.24), Vector2(rs * 1.1, 0.32)], 14, PALE)
				lathe(at, [Vector2(rs, 0.32), Vector2(rs * 0.88, h - 0.5)], 14, RED, false)
				box(at + Vector3(-rs * 1.5, h - 0.5, -rs * 1.2), at + Vector3(rs * 1.5, h - 0.2, rs * 1.2), BLACK, false)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						disc(at + Vector3(sx * rs * 1.55, h - 0.4, sz * rs * 1.05), Vector3(0, 0, sz), rs * 0.62, 0.12, BLACK, 10)
				box(at + Vector3(-rs * 1.7, h - 0.2, -rs * 1.4), at + Vector3(rs * 1.7, h, rs * 1.4), PALE, false)
				solids.append(AABB(at - Vector3(r, 0, r), Vector3(r * 2.0, h, r * 2.0)))
				return
			"cyclades":
				# A plain square pillar of marble, a blue band low on it.
				box(at + Vector3(-r, 0, -r), at + Vector3(r, h, r), PALE)
				box(at + Vector3(-r * 1.06, 0.5, -r * 1.06), at + Vector3(r * 1.06, 0.72, r * 1.06), RED, false)
				box(at + Vector3(-r * 1.3, h - 0.22, -r * 1.3), at + Vector3(r * 1.3, h, r * 1.3), PALE, false)
				return
		var r1 := r * taper
		var shaft := h - 0.75
		lathe(at, [Vector2(r * 1.45, 0.0), Vector2(r * 1.45, 0.14), Vector2(r * 1.15, 0.2)], 12, BLACK)
		lathe(at, [Vector2(r, 0.2), Vector2(lerpf(r, r1, 0.5), 0.2 + shaft * 0.5), Vector2(r1, 0.2 + shaft)], 12, RED, false)
		var cy := 0.2 + shaft
		var cap: Array = [Vector2(r1, cy), Vector2(r1 * 1.25, cy + 0.04)]
		for k in 5:   # (the cushion: a round roll)
			var a := PI * (0.25 + 0.5 * k / 4.0)
			cap.append(Vector2(r1 * 1.05 + r1 * 0.35 * sin(a), cy + 0.12 - 0.12 * cos(a) + 0.04))
		cap.append(Vector2(r1 * 1.1, cy + 0.3))
		lathe(at, cap, 12, BLACK)
		box(at + Vector3(-r1 * 1.55, cy + 0.3, -r1 * 1.55), at + Vector3(r1 * 1.55, h, r1 * 1.55), BLACK, false)
		solids.append(AABB(at - Vector3(r1, 0, r1), Vector3(r1 * 2.0, h, r1 * 2.0)))

	## A tiled gable roof over mn..mx from `y`: two slopes (their eaves a
	## little out), the pediments at its ends - the ridge along its longer side.
	func gable(mn: Vector2, mx: Vector2, y: float, rise: float) -> void:
		var along_x := (mx.x - mn.x) >= (mx.y - mn.y)
		var o := 0.5
		var col := Color(JAR / 255.0, rng.randf(), 0.0)   # (terracotta tiles: the jars' clay)
		var ped := Color(PALE / 255.0, rng.randf(), 0.0)
		var trim := Color(TRIM / 255.0, rng.randf(), 0.0)
		if along_x:
			var zm := (mn.y + mx.y) * 0.5
			for sd in [-1.0, 1.0]:
				var ze := mn.y - o if sd < 0.0 else mx.y + o
				var n := Vector3(0, absf(ze - zm), sd * rise).normalized()
				quad(Vector3(mn.x - o, y, ze), Vector3(mx.x + o, y, ze), Vector3(mx.x + o, y + rise, zm), Vector3(mn.x - o, y + rise, zm), n, col)
			for x in [mn.x - o * 0.5, mx.x + o * 0.5]:
				var nx := Vector3(-1 if x < mn.x else 1, 0, 0)
				quad(Vector3(x, y, mn.y), Vector3(x, y, mx.y), Vector3(x, y + rise * 0.92, zm), Vector3(x, y + rise * 0.92, zm), nx, ped)
				disc(Vector3(x, y + rise * 0.36, zm), nx, rise * 0.24, 0.08, TRIM, 12)
				box(Vector3(x - 0.15, y + rise, zm - 0.3), Vector3(x + 0.15, y + rise + 0.7, zm + 0.3), TRIM, false)   # (the acroterion)
			quad(Vector3(mn.x - o, y + rise, zm - 0.12), Vector3(mx.x + o, y + rise, zm - 0.12), Vector3(mx.x + o, y + rise, zm + 0.12), Vector3(mn.x - o, y + rise, zm + 0.12), Vector3.UP, trim)
		else:
			var xm := (mn.x + mx.x) * 0.5
			for sd in [-1.0, 1.0]:
				var xe := mn.x - o if sd < 0.0 else mx.x + o
				var n := Vector3(sd * rise, absf(xe - xm), 0).normalized()
				quad(Vector3(xe, y, mn.y - o), Vector3(xe, y, mx.y + o), Vector3(xm, y + rise, mx.y + o), Vector3(xm, y + rise, mn.y - o), n, col)
			for z in [mn.y - o * 0.5, mx.y + o * 0.5]:
				var nz := Vector3(0, 0, -1 if z < mn.y else 1)
				quad(Vector3(mn.x, y, z), Vector3(mx.x, y, z), Vector3(xm, y + rise * 0.92, z), Vector3(xm, y + rise * 0.92, z), nz, ped)
				disc(Vector3(xm, y + rise * 0.36, z), nz, rise * 0.24, 0.08, TRIM, 12)
				box(Vector3(xm - 0.3, y + rise, z - 0.15), Vector3(xm + 0.3, y + rise + 0.7, z + 0.15), TRIM, false)
			quad(Vector3(xm - 0.12, y + rise, mn.y - o), Vector3(xm + 0.12, y + rise, mn.y - o), Vector3(xm + 0.12, y + rise, mx.y + o), Vector3(xm - 0.12, y + rise, mx.y + o), Vector3.UP, trim)
		solids.append(AABB(Vector3(mn.x, y, mn.y), Vector3(mx.x - mn.x, rise * 0.6, mx.y - mn.y)))

	## A dome on `at` (its foot's middle): a low drum, the dome on it (`slot`), a finial.
	func dome(at: Vector3, r: float, slot: int, tall := 1.0) -> void:
		var prof: Array = [Vector2(r * 1.04, 0.0), Vector2(r * 1.04, r * 0.18)]
		for k in 8:
			var a := PI * 0.5 * k / 7.0
			prof.append(Vector2(r * cos(a), r * 0.18 + r * tall * sin(a)))
		var slots: Array = [PALE]
		for k in 8:
			slots.append(slot)
		lathe(at, prof, 16, slots, false)
		box(at + Vector3(-0.1, r * 0.18 + r * tall, -0.1), at + Vector3(0.1, r * 0.18 + r * tall + 0.5, 0.1), TRIM, false)
		solids.append(AABB(at - Vector3(r, 0, r), Vector3(r * 2.0, r * (0.18 + tall), r * 2.0)))

	## A shield hung on a wall at `at`, facing `n`: bronze, a boss on it.
	func shield(at: Vector3, n: Vector3, r := 0.62) -> void:
		disc(at, n, r, 0.1, TRIM, 14)
		disc(at + n * 0.1, n, r * 0.72, 0.04, RED, 12)
		disc(at + n * 0.14, n, r * 0.2, 0.06, TRIM, 8)

	## What crowns a roof (`mn`..`mx` at `top`) or hangs on the walls, the empire's way.
	func _crown(mn: Vector2, mx: Vector2, y0: float, top: float, kind: String) -> void:
		var along := (mx.x - mn.x) > (mx.y - mn.y)
		var c := Vector3((mn.x + mx.x) * 0.5, top, (mn.y + mx.y) * 0.5)
		match emp:
			"minoa", "", "dungeon", "cave", "pirates":
				if rng.randf() < 0.5:
					if along:
						horns(Vector3(c.x, top, mn.y + 0.6), true)
					else:
						horns(Vector3(mn.x + 0.6, top, c.z), false)
			"athens":
				if kind == "throne":
					gable(mn, mx, top + 0.5, minf(mx.x - mn.x, mx.y - mn.y) * 0.2)
				else:   # (acroteria at the corners)
					for p in [Vector3(mn.x, top + 0.5, mn.y), Vector3(mx.x, top + 0.5, mn.y), Vector3(mx.x, top + 0.5, mx.y), Vector3(mn.x, top + 0.5, mx.y)]:
						box(p - Vector3(0.22, 0, 0.22), p + Vector3(0.22, 0.6, 0.22), TRIM, false)
			"sparta":
				# (shields along its longer walls)
				var n := 2 + int(maxf(mx.x - mn.x, mx.y - mn.y) / 7.0)
				for i in n:
					var t := (i + 0.5) / n
					if along:
						shield(Vector3(lerpf(mn.x, mx.x, t), y0 + 2.2, mx.y), Vector3(0, 0, 1))
						shield(Vector3(lerpf(mn.x, mx.x, t), y0 + 2.2, mn.y), Vector3(0, 0, -1))
					else:
						shield(Vector3(mx.x, y0 + 2.2, lerpf(mn.y, mx.y, t)), Vector3(1, 0, 0))
						shield(Vector3(mn.x, y0 + 2.2, lerpf(mn.y, mx.y, t)), Vector3(-1, 0, 0))
			"mycenae":
				ring(mn, mx, y0 + 1.1, y0 + 1.3, 0.05, TRIM)   # (the gold band)
			"ionia":
				if rng.randf() < 0.4:   # (an armillary: gold rings on a post)
					box(c - Vector3(0.1, 0, 0.1), c + Vector3(0.1, 1.2, 0.1), BLACK, false)
					for k in 3:
						var pts: Array = []
						var radii: Array = []
						var bs := Basis(Vector3(1, 0, 0.4 * k).normalized(), 0.6 + 0.6 * k)
						for j in 13:
							pts.append(c + Vector3(0, 2.0, 0) + bs * (Vector3(cos(TAU * j / 12.0), 0, sin(TAU * j / 12.0)) * 0.8))
							radii.append(0.035)
						tube(pts, radii, 5, BLACK)
			"cyclades":
				if kind in ["house", "none"] and rng.randf() < 0.45:
					dome(c, minf(mx.x - mn.x, mx.y - mn.y) * 0.3, RED)

	## Horns of consecration at `at` (facing along x or z): a base, two horns
	## curving up and out from it (tubes).
	func horns(at: Vector3, along_x: bool) -> void:
		var w := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var t := Vector3(0, 0, 0.2) if along_x else Vector3(0.2, 0, 0)
		box(at - w * 0.85 - t, at + w * 0.85 + t + Vector3(0, 0.28, 0), HORNS, false)
		for s in [-1.0, 1.0]:
			var pts: Array = []
			var radii: Array = []
			for k in 6:
				var q := k / 5.0
				pts.append(at + w * s * (0.45 + 0.22 * q * q) + Vector3(0, 0.24 + 0.85 * q, 0))
				radii.append(lerpf(0.17, 0.05, q))
			tube(pts, radii, 8, HORNS)

	## A building of `storeys` from y0 put together from the building kit's
	## pieces (BuildKit - the same pieces you build with) in the town's style -
	## walk in: its footprint whole 4 m cells within mn..mx (held to its door's
	## side), a floor, walls round each storey with a doorway on side `door` (0
	## -x, 1 +x, 2 -z, 3 +z; -1 none) at `door_at` along it and windows, `rooms`:
	## partitions across its length with doorways, upper floors with stairs up to
	## them in a corner cell, a flat roof; a low parapet, the empire's crown on it
	## (horns, shields, a gold band...), its furniture (`kind`). Its roof's height.
	func block(mn: Vector2, mx: Vector2, storeys: int, y0 := 0.0, door := -1, roof_horns := true, rooms := false, kind := "house", door_at := 0.5) -> float:
		var C := BuildKit.CELL
		var nx := maxi(1, floori((mx.x - mn.x + 1.0) / C))
		var nz := maxi(1, floori((mx.y - mn.y + 1.0) / C))
		var ox := mn.x if door == 0 else (mx.x - nx * C if door == 1 else (mn.x + mx.x - nx * C) * 0.5)
		var oz := mn.y if door == 2 else (mx.y - nz * C if door == 3 else (mn.y + mx.y - nz * C) * 0.5)
		mn = Vector2(ox, oz)
		mx = mn + Vector2(nx * C, nz * C)
		if nx == 1 and nz == 1:
			storeys = 1   # (no room for stairs)
		var base := y0 + FLOOR
		var top := base + storeys * BuildKit.WALL_H
		var at := func(i: float, j: float, y: float) -> Vector3:
			return Vector3(mn.x + i * C, y, mn.y + j * C)
		var stair_r := 0 if nz >= 2 else 3   # (up along +z - or +x in a one-cell-deep block)
		var dlen := nz if door < 2 else nx
		var dcell := clampi(roundi(door_at * (dlen - 1)), 0, dlen - 1)
		if storeys > 1 and dcell == 0 and dlen > 1 and door in [0, 2]:
			dcell = 1   # (not into the stairs' side)
		var pcs := []
		var pc := func(t: String, p: Vector3, r: int) -> void:
			pcs.append({"t": t, "p": [p.x, p.y, p.z], "r": r, "m": 1, "s": emp, "c": 0})
		for st in storeys + 1:   # (its floors and its roof: the kit's slabs, one a storey - the stairwell's cell left open)
			var y := base + st * BuildKit.WALL_H
			var sl: int = ROOF if st == storeys else PALE
			var a0: Vector3 = at.call(0, 0, y)
			var a1: Vector3 = at.call(nx, nz, y)
			if st == 0 or st == storeys:
				box(Vector3(a0.x, y - BuildKit.SLAB, a0.z), a1, sl, true, 2 if st == 0 else 0)
			elif stair_r == 0:
				box(Vector3(a0.x + C, y - BuildKit.SLAB, a0.z), a1, sl)
				box(Vector3(a0.x, y - BuildKit.SLAB, a0.z + C), Vector3(a0.x + C, y, a1.z), sl)
			else:
				box(Vector3(a0.x, y - BuildKit.SLAB, a0.z + C), a1, sl)
				box(Vector3(a0.x + C, y - BuildKit.SLAB, a0.z), Vector3(a1.x, y, a0.z + C), sl)
		for st in storeys:
			var y := base + st * BuildKit.WALL_H
			if st < storeys - 1:
				pc.call("stairs", at.call(0.5, 0.5, y), stair_r)
			for side in 4:
				var n := nz if side < 2 else nx
				for k in n:
					var e: Vector3
					var r: int
					match side:
						0: e = at.call(0, k + 0.5, y); r = 9
						1: e = at.call(nx, k + 0.5, y); r = 3
						2: e = at.call(k + 0.5, 0, y); r = 6
						_: e = at.call(k + 0.5, nz, y); r = 0
					var t := "wall"
					if st == 0 and side == door and k == dcell:
						t = "doorway"
					elif rng.randf() < (0.4 if st > 0 else 0.25) and not (st < storeys - 1 and k == 0 and side in [0, 2]):
						t = "window"
					pc.call(t, e, r)
			if rooms:   # (partitions every two cells along its length, a doorway in each)
				var along_x := nx >= nz
				var L := nx if along_x else nz
				var W := nz if along_x else nx
				for cut in range(2, L, 2):
					for k in W:
						var e2: Vector3 = at.call(cut, k + 0.5, y) if along_x else at.call(k + 0.5, cut, y)
						pc.call("doorway" if k == W / 2 else "wall", e2, 3 if along_x else 0)
		for q: Dictionary in pcs:
			var res := BuildKit.emit(self, q, false, false)
			for so in res["solids"]:
				solids.append(so)
		for pt in BuildPlan.new(pcs, false).posts():
			var lb := CosmosTown.Builder.new()
			lb.rng.seed = rng.randi()
			BuildKit.post(lb, Vector3(0, (pt[0] as Vector3).y, 0), float(pt[1]), int(pt[2]), emp)
			BuildKit.merge(self, lb, int(pt[4]), pt[0])   # (no block of its own: the walls either side, merged, cover it)
		if door >= 0:
			var dp: Vector3 = [at.call(0, dcell + 0.5, base), at.call(nx, dcell + 0.5, base), at.call(dcell + 0.5, 0, base), at.call(dcell + 0.5, nz, base)][door]
			doors.append([dp, [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK][door]])
		# Outside the walls (their faces half a wall out from the cells' edges): the parapet, the beams' ends, the crown.
		var o := Vector2(BuildKit.WALL_T * 0.5, BuildKit.WALL_T * 0.5)
		ring(mn - o, mx + o, top, top + 0.5, 0.25, ROOF)   # (the parapet - low: stepped over)
		if kind in ["wing", "throne"]:
			_beam_ends(mn - o, mx + o, top - BuildKit.SLAB - 0.62)
		_furnish(mn, mx, base, storeys, kind)
		if roof_horns or emp in ["sparta", "mycenae"]:
			_crown(mn - o, mx + o, base, top, kind)
		return top


	## The palace's frieze: the round ends of its roof beams in a row round
	## the top of its walls, under the cornice.
	func _beam_ends(mn: Vector2, mx: Vector2, y: float) -> void:
		var o := 0.06
		var sides := [[Vector3(mn.x, y, mn.y - o), Vector3(1, 0, 0), mx.x - mn.x, Vector3(0, 0, -1)],
			[Vector3(mn.x, y, mx.y + o), Vector3(1, 0, 0), mx.x - mn.x, Vector3(0, 0, 1)],
			[Vector3(mn.x - o, y, mn.y), Vector3(0, 0, 1), mx.y - mn.y, Vector3(-1, 0, 0)],
			[Vector3(mx.x + o, y, mn.y), Vector3(0, 0, 1), mx.y - mn.y, Vector3(1, 0, 0)]]
		for sd in sides:
			var n := int((sd[2] - 0.6) / 0.62)
			for i in n:
				disc(sd[0] + sd[1] * (0.3 + (sd[2] - 0.6) * (i + 0.5) / n), sd[3], 0.13, 0.12, WOOD, 7)

	## A band round the outside of the walls (out `o`), y0..y1: four boxes, none inside.
	func ring(mn: Vector2, mx: Vector2, y0: float, y1: float, o: float, slot: int) -> void:
		box(Vector3(mn.x - o, y0, mn.y - o), Vector3(mx.x + o, y1, mn.y), slot, false)
		box(Vector3(mn.x - o, y0, mx.y), Vector3(mx.x + o, y1, mx.y + o), slot, false)
		box(Vector3(mn.x - o, y0, mn.y), Vector3(mn.x, y1, mx.y), slot, false)
		box(Vector3(mx.x, y0, mn.y), Vector3(mx.x + o, y1, mx.y), slot, false)

	## What's in it: a house's hearth, bench, jars and beds upstairs; a palace
	## wing's benches and jars - the throne room's throne; a shrine's altar.
	func _furnish(mn: Vector2, mx: Vector2, y0: float, storeys: int, kind: String) -> void:
		var T := WALL_T + 0.05
		var c := (mn + mx) * 0.5
		match kind:
			"house":
				box(Vector3(c.x - 0.6, y0, mx.y - T - 1.0), Vector3(c.x + 0.6, y0 + 0.5, mx.y - T), STONE)          # (the hearth)
				box(Vector3(c.x - 0.25, y0 + 0.5, mx.y - T - 0.6), Vector3(c.x + 0.25, y0 + 0.55, mx.y - T - 0.4), RED, false)
				box(Vector3(mx.x - T - 0.5, y0, mn.y + T + 1.0), Vector3(mx.x - T, y0 + 0.45, mx.y - T - 1.5), WOOD)  # (a bench)
				_jar(Vector3(mx.x - T - 0.6, y0, mx.y - T - 0.6))
				if storeys > 1:
					var ys := y0 + BuildKit.WALL_H
					box(Vector3(mx.x - T - 1.0, ys, mx.y - T - 2.2), Vector3(mx.x - T, ys + 0.45, mx.y - T), WOOD)     # (a bed)
					box(Vector3(mx.x - T - 0.95, ys + 0.45, mx.y - T - 2.15), Vector3(mx.x - T - 0.05, ys + 0.55, mx.y - T - 0.05), PALE, false)
			"wing":
				box(Vector3(mn.x + T, y0, mn.y + T + (BuildKit.CELL if storeys > 1 else 1.0)), Vector3(mn.x + T + 0.5, y0 + 0.45, mx.y - T - 1.0), STONE)
				for k in 3:
					_jar(Vector3(mx.x - T - 0.6, y0, mn.y + T + 1.0 + k * 1.3))
			"throne":
				# The throne against the back wall, gypsum, benches either side, griffins painted behind it.
				var b := Vector3(mn.x + T, y0, c.y)
				box(b + Vector3(0, 0, -0.5), b + Vector3(0.7, 0.5, 0.5), PALE)
				box(b + Vector3(0, 0.5, -0.5), b + Vector3(0.15, 1.6, 0.5), PALE)
				for sd in [-1.0, 1.0]:
					box(b + Vector3(0, 0, 0.9 * sd), b + Vector3(0.5, 0.45, 3.5 * sd), STONE)
					box(Vector3(mn.x + BuildKit.WALL_T * 0.5, y0 + 1.0, c.y + 0.7 * sd), Vector3(mn.x + BuildKit.WALL_T * 0.5 + 0.03, y0 + 2.4, c.y + 3.0 * sd), FRESCO, false)
			"shrine":
				box(Vector3(c.x - 0.8, y0, c.y - 0.5), Vector3(c.x + 0.8, y0 + 1.0, c.y + 0.5), HORNS)
				_sacred(Vector3(c.x, y0 + 1.0, c.y))

	## Steps from `at` along `dir` (unit x or z), `n` of them, rising `rise`
	## each, `w` wide - each a block you walk up onto.
	func stairs(at: Vector3, dir: Vector3, n: int, w: float, rise := 0.4, run := 0.55) -> void:
		var side := Vector3(dir.z, 0, dir.x).abs() * w * 0.5
		for i in n:
			var p := at + dir * (i * run)
			var q := p + dir * run
			var mn := Vector3(minf(p.x, q.x), at.y, minf(p.z, q.z)) - side
			var mx := Vector3(maxf(p.x, q.x), at.y + (i + 1) * rise, maxf(p.z, q.z)) + side
			box(mn, mx, STONE)

	## The palace: wings round a court 36 x 24, a colonnade, a gateway, stairs.
	func palace(c: Vector3) -> void:
		var cx := 18.0
		var cz := 12.0
		taken.append(Rect2(c.x - cx - 18, c.z - cz - 18, (cx + 18) * 2, (cz + 18) * 2))
		box(Vector3(c.x - cx, -0.3, c.z - cz), Vector3(c.x + cx, 0.08, c.z + cz), PALE, false)   # (the court's gypsum)
		# West wing: three storeys, stepped; the colonnade before it.
		# (blocks that would touch stand 0.6 m apart: their cornices meet, never overlap)
		var west := [[Vector2(-cx - 16, -cz - 14), Vector2(-cx, -4.3), 3, "throne", 0.85], [Vector2(-cx - 16, -3.7), Vector2(-cx, cz + 14), 2, "wing", 0.3]]
		for wg in west:
			block(wg[0] + Vector2(c.x, c.z), wg[1] + Vector2(c.x, c.z), wg[2], 0.0, 1, true, true, wg[3], wg[4])
		for i in 6:
			column(Vector3(c.x - cx + 2.6, 0.08, c.z - cz + 2.0 + i * 4.0), STOREY)
		box(Vector3(c.x - cx, STOREY, c.z - cz), Vector3(c.x - cx + 3.6, STOREY + 0.45, c.z + cz), TRIM, false)
		# East wing: two storeys; north and south wings, a gap for the way in.
		block(Vector2(c.x + cx, c.z - cz - 14), Vector2(c.x + cx + 14, c.z + cz + 14), 2, 0.0, 0, true, true, "wing")
		block(Vector2(c.x - cx + 0.6, c.z - cz - 14), Vector2(c.x - 4, c.z - cz), 2, 0.0, 3, true, true, "wing")
		block(Vector2(c.x + 4, c.z - cz - 14), Vector2(c.x + cx - 0.6, c.z - cz), 2, 0.0, 3, true, true, "wing")
		var s_top := block(Vector2(c.x - cx + 0.6, c.z + cz), Vector2(c.x - 5, c.z + cz + 14), 1, 0.0, 2, true, false, "wing", 0.2)
		block(Vector2(c.x + 5, c.z + cz), Vector2(c.x + cx - 0.6, c.z + cz + 14), 1, 0.0, 2, true, false, "wing")
		# The gateways (north and south): columns and a lintel.
		for z in [c.z + cz + 7.0, c.z - cz - 7.0]:
			for x in [c.x - 2.0, c.x + 2.0]:
				column(Vector3(x, 0, z), STOREY)
		box(Vector3(c.x - 5, STOREY, c.z + cz), Vector3(c.x + 5, STOREY + 0.6, c.z + cz + 14), TRIM, false)
		# The grand staircase: from the court up onto the south wing's roof.
		stairs(Vector3(c.x - 6.5, 0.08, c.z + cz - 5.6), Vector3(0, 0, 1), 10, 3.0, (s_top - 0.08) / 10.0, 0.56)
		# The altar in the court, with horns.
		box(Vector3(c.x - 1.2, 0, c.z - 1.2), Vector3(c.x + 1.2, 1.0, c.z + 1.2), HORNS)
		_sacred(Vector3(c.x, 1.0, c.z))
		for p in [Vector3(c.x + 8, 0, c.z + 6), Vector3(c.x - 8, 0, c.z - 6), Vector3(c.x + 10, 0, c.z - 8), Vector3(c.x - 10, 0, c.z + 8)]:
			spots.append(p)
		spots.append(Vector3(c.x, 0, c.z + cz + 20))
		spots.append(Vector3(c.x, 0, c.z - cz - 20))

	## Houses on lots along lanes, within `half`, round what's taken.
	func houses(half: float, keep_out: Rect2) -> void:
		taken.append(keep_out)
		var lot := 13.0
		var x := -half + 4.0
		while x + lot <= half - 2.0:
			var z := -half + 4.0
			while z + lot <= half - 2.0:
				var r := Rect2(x, z, lot - 3.0, lot - 3.0)
				var free := true
				for t: Rect2 in taken:
					if t.intersects(r.grow(2.0)):
						free = false
						break
				if free and rng.randf() < 0.82:
					_house(r)
				elif free:
					_garden(r)
				spots.append(Vector3(x - 1.5, 0, z - 1.5))
				z += lot
			x += lot

	func _house(r: Rect2) -> void:
		var w := rng.randf_range(6.0, r.size.x)
		var d := rng.randf_range(6.0, r.size.y)
		var mn := r.position + Vector2(rng.randf() * (r.size.x - w), rng.randf() * (r.size.y - d))
		var mx := mn + Vector2(w, d)
		var st := 1 if rng.randf() < 0.45 else (2 if rng.randf() < 0.8 else 3)
		var top := block(mn, mx, st, 0.0, rng.randi() % 4)
		# A smaller storey on part of it, now and then; or a pergola on the roof.
		if st < 3 and rng.randf() < 0.35:
			block(mn + Vector2(0.5, 0.5), mn + Vector2(w * 0.5, d * 0.6), 1, top, -1, false, false, "none")
		elif rng.randf() < 0.3:
			for k in 4:
				var p := Vector3(mx.x - 0.6 - (k % 2) * minf(3.0, w - 1.5), top, mx.y - 0.6 - (k / 2) * minf(3.0, d - 1.5))
				box(p - Vector3(0.12, 0, 0.12), p + Vector3(0.12, 2.4, 0.12), WOOD, false)
			box(Vector3(mx.x - 0.8 - minf(3.0, w - 1.5), top + 2.4, mx.y - 0.8 - minf(3.0, d - 1.5)), Vector3(mx.x - 0.4, top + 2.55, mx.y - 0.4), WOOD, false)

	## A garden: storage jars and a low wall.
	func _garden(r: Rect2) -> void:
		box(Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0.9, r.position.y + 0.4), STONE)
		for k in rng.randi_range(2, 5):
			_jar(Vector3(r.position.x + rng.randf_range(1.0, r.size.x - 1.0), 0, r.position.y + rng.randf_range(1.5, r.size.y - 1.0)))

	## A pithos: a storage jar on the lathe, its rope bands (the trim).
	func _jar(at: Vector3) -> void:
		var h := rng.randf_range(1.1, 1.6)
		var R := h * 0.34
		var pr: Array = [Vector2(R * 0.45, 0.0), Vector2(R * 0.8, h * 0.18), Vector2(R, h * 0.42), Vector2(R * 0.96, h * 0.58),
			Vector2(R * 0.75, h * 0.8), Vector2(R * 0.5, h * 0.9), Vector2(R * 0.52, h * 0.95), Vector2(R * 0.62, h)]
		lathe(at, pr, 10, [JAR, JAR, TRIM, JAR, JAR, JAR, TRIM], false)
		solids.append(AABB(at - Vector3(R, 0, R), Vector3(R * 2.0, h, R * 2.0)))

	## What stands on an altar: the Minoans' horns; Athens' and Ionia's gold
	## tripod bowl; Sparta's shield on a post; Mycenae's gold mask; the
	## Cyclades' marble figure.
	func _sacred(at: Vector3) -> void:
		match emp:
			"athens", "ionia":
				lathe(at, [Vector2(0.12, 0.0), Vector2(0.08, 0.5), Vector2(0.4, 0.7), Vector2(0.44, 0.85)], 10, TRIM if emp == "athens" else BLACK)
			"sparta":
				box(at - Vector3(0.08, 0, 0.08), at + Vector3(0.08, 1.4, 0.08), WOOD, false)
				shield(at + Vector3(0, 1.1, 0.1), Vector3(0, 0, 1), 0.5)
				shield(at + Vector3(0, 1.1, -0.1), Vector3(0, 0, -1), 0.5)
			"mycenae":
				box(at - Vector3(0.06, 0, 0.06), at + Vector3(0.06, 0.9, 0.06), WOOD, false)
				lathe(at + Vector3(0, 0.9, 0), [Vector2(0.0, 0.0), Vector2(0.22, 0.12), Vector2(0.3, 0.4), Vector2(0.24, 0.66), Vector2(0.0, 0.74)], 10, BLACK)
			"cyclades":
				_figure(at, 1.0)
			_:
				horns(at, true)

	## A Cycladic figure: marble, tall and flat - legs, a body with folded arms, a long tilted head.
	func _figure(at: Vector3, k: float) -> void:
		box(at + Vector3(-0.16, 0, -0.08) * k, at + Vector3(0.16, 0.7, 0.08) * k, PALE, false)
		box(at + Vector3(-0.24, 0.7, -0.09) * k, at + Vector3(0.24, 1.3, 0.09) * k, PALE, false)
		box(at + Vector3(-0.25, 0.92, -0.1) * k, at + Vector3(0.25, 1.0, 0.1) * k, STONE, false)
		box(at + Vector3(-0.07, 1.3, -0.06) * k, at + Vector3(0.07, 1.45, 0.06) * k, PALE, false)
		lathe(at + Vector3(0, 1.45, 0) * k, [Vector2(0.09 * k, 0.0), Vector2(0.15 * k, 0.14 * k), Vector2(0.15 * k, 0.36 * k), Vector2(0.1 * k, 0.46 * k)], 8, PALE)

	## A shrine, the empire's way: the Minoans' three rooms (the middle tallest,
	## columns before it, horns); Athens' and Ionia's temple - a cella in a
	## ring of columns under a tiled gable; Mycenae's tholos - a beehive dome,
	## a passage in to its door; the Cyclades' domed chapel, a marble figure
	## before it; Sparta's plain hall hung with shields.
	func shrine(c: Vector3) -> void:
		taken.append(Rect2(c.x - 12, c.z - 8, 24, 18))
		match emp:
			"athens", "ionia":
				for k in 3:   # (the stepped platform)
					box(Vector3(c.x - 11 + k * 0.5, k * 0.3, c.z - 7 + k * 0.5), Vector3(c.x + 11 - k * 0.5, (k + 1) * 0.3, c.z + 8 - k * 0.5), STONE)
				var y := 0.9
				block(Vector2(c.x - 6.5, c.z - 4), Vector2(c.x + 6.5, c.z + 4.5), 1, y, 3, false, false, "shrine")
				var h := STOREY + 0.5
				for i in 7:   # (the peristyle: columns down both long sides, across both ends)
					var x := c.x - 9.0 + i * 3.0
					column(Vector3(x, y, c.z - 5.6), h, 0.36)
					column(Vector3(x, y, c.z + 6.4), h, 0.36)
				for z in [c.z - 2.6, c.z + 0.4, c.z + 3.4]:
					column(Vector3(c.x - 9.0, y, z), h, 0.36)
					column(Vector3(c.x + 9.0, y, z), h, 0.36)
				box(Vector3(c.x - 9.8, y + h, c.z - 6.4), Vector3(c.x + 9.8, y + h + 0.5, c.z + 7.2), PALE, false)      # (the architrave)
				ring(Vector2(c.x - 9.8, c.z - 6.4), Vector2(c.x + 9.8, c.z + 7.2), y + h + 0.5, y + h + 1.0, 0.02, FRESCO)  # (the frieze)
				box(Vector3(c.x - 10.1, y + h + 1.0, c.z - 6.7), Vector3(c.x + 10.1, y + h + 1.2, c.z + 7.5), TRIM, false)
				gable(Vector2(c.x - 10.1, c.z - 6.7), Vector2(c.x + 10.1, c.z + 7.5), y + h + 1.2, 2.6)
			"mycenae":
				# The tholos: a beehive of stone on a round wall, the passage to its door.
				var at := Vector3(c.x, 0, c.z - 1.0)
				var R := 6.0
				var prof: Array = [Vector2(R, 0.0), Vector2(R, 2.0)]
				for k in 9:
					var a := PI * 0.5 * (k + 1) / 9.0
					prof.append(Vector2(R * cos(a), 2.0 + 7.5 * sin(a)))
				lathe(at, prof, 20, STONE, false)
				lathe(at, [Vector2(0.9, 9.5), Vector2(0.5, 10.1), Vector2(0.0, 10.3)], 10, BLACK, false)
				solids.append(AABB(at - Vector3(R * 0.8, 0, R * 0.8), Vector3(R * 1.6, 8.0, R * 1.6)))
				for sx in [-1.0, 1.0]:   # (the passage's walls, stepping down outward)
					box(Vector3(c.x + sx * 1.6, 0, c.z + 4.6), Vector3(c.x + sx * 2.6, 3.6, c.z + 8.0), STONE)
					box(Vector3(c.x + sx * 1.6, 0, c.z + 8.0), Vector3(c.x + sx * 2.6, 2.2, c.z + 10.0), STONE)
				box(Vector3(c.x - 1.5, 0, c.z + 4.2), Vector3(c.x + 1.5, 3.2, c.z + 4.7), DARK)                          # (the doorway, dark)
				box(Vector3(c.x - 2.2, 3.2, c.z + 4.3), Vector3(c.x + 2.2, 3.8, c.z + 4.9), STONE, false)                 # (its great lintel)
				quad(Vector3(c.x - 1.6, 3.8, c.z + 4.92), Vector3(c.x + 1.6, 3.8, c.z + 4.92), Vector3(c.x, 5.6, c.z + 4.92), Vector3(c.x, 5.6, c.z + 4.92),
					Vector3(0, 0, 1), Color(RED / 255.0, rng.randf(), 0.0))
				lathe(at + Vector3(0, 2.0, 0), [Vector2(R + 0.06, 0.0), Vector2(R + 0.06, 0.22)], 20, TRIM, false)        # (a gold band round it)
			"cyclades":
				box(Vector3(c.x - 8, 0, c.z - 6), Vector3(c.x + 8, 0.4, c.z + 7), STONE)
				var t2 := block(Vector2(c.x - 5, c.z - 5), Vector2(c.x + 5, c.z + 2), 1, 0.4, 3, false, false, "shrine")
				dome(Vector3(c.x, t2 + 0.5, c.z - 1.5), 3.4, RED)
				_figure(Vector3(c.x - 3.6, 0.4, c.z + 4.6), 2.2)
				_figure(Vector3(c.x + 3.6, 0.4, c.z + 4.6), 2.2)
				for x in [-6.5, 6.5]:
					column(Vector3(c.x + x, 0.4, c.z + 4.0), STOREY)
			"sparta":
				box(Vector3(c.x - 11, 0, c.z - 6), Vector3(c.x + 11, 0.6, c.z + 8), STONE)
				block(Vector2(c.x - 8, c.z - 5), Vector2(c.x + 8, c.z + 1), 1, 0.6, 3, false, false, "shrine")
				for x in [-6.0, -2.0, 2.0, 6.0]:
					column(Vector3(c.x + x, 0.6, c.z + 4), STOREY)
				box(Vector3(c.x - 8.4, 0.6 + STOREY, c.z + 1), Vector3(c.x + 8.4, 0.6 + STOREY + 0.5, c.z + 5), PALE, false)
				gable(Vector2(c.x - 8.4, c.z - 5.2), Vector2(c.x + 8.4, c.z + 5.0), 0.6 + STOREY + 0.5, 1.8)
			_:
				box(Vector3(c.x - 11, 0, c.z - 6), Vector3(c.x + 11, 0.6, c.z + 8), STONE)
				block(Vector2(c.x - 9, c.z - 5), Vector2(c.x - 3.6, c.z + 1), 1, 0.6, -1, false, false, "none")
				var t := block(Vector2(c.x - 3, c.z - 5), Vector2(c.x + 3, c.z + 1), 2, 0.6, 3, false, false, "shrine")
				block(Vector2(c.x + 3.6, c.z - 5), Vector2(c.x + 9, c.z + 1), 1, 0.6, -1, false, false, "none")
				horns(Vector3(c.x, t, c.z - 2), true)
				horns(Vector3(c.x - 6, 0.6 + STOREY, c.z - 2), true)
				horns(Vector3(c.x + 6, 0.6 + STOREY, c.z - 2), true)
				for x in [-7.0, -2.0, 2.0, 7.0]:
					column(Vector3(c.x + x, 0.6, c.z + 4), STOREY)
				box(Vector3(c.x - 9, 0.6 + STOREY, c.z + 1), Vector3(c.x + 9, 0.6 + STOREY + 0.4, c.z + 5), TRIM, false)
		stairs(Vector3(c.x - 3, 0, c.z + 9.6), Vector3(0, 0, -1), 2, 6.0, 0.3, 0.8)
		spots.append(Vector3(c.x, 0, c.z + 12))

	## A storehouse: a long block, a loading porch, jars in rows.
	func storehouse(c: Vector3) -> void:
		taken.append(Rect2(c.x - 12, c.z - 9, 24, 20))
		block(Vector2(c.x - 10, c.z - 7), Vector2(c.x + 10, c.z + 1), 1, 0.0, 3, false, true, "wing")
		for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
			_jar(Vector3(c.x + x, 0, c.z + 4.0))
			if rng.randf() < 0.6:
				_jar(Vector3(c.x + x + 1.6, 0, c.z + 6.0))
		spots.append(Vector3(c.x, 0, c.z + 9))
