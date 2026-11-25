class_name BuildKit
extends RefCounted
## The building kit: modular pieces that snap together on a 4 m grid - your
## own buildings (CosmosBuilds) and the towns' (CosmosTown) alike.
##
## Pieces (PIECES, by category - CATS): foundations (square, triangle, front
## steps), floors / ceilings (square, triangle, a hatch with its ladder), walls
## (full, half, an upper wall hanging from a ceiling, a sloped gable wall),
## openings (doorway, door, window with shutters, arch, a gate - its doors
## swing), roofs (sloped, hip, valley, a pyramid cap, a triangle's, flat),
## stairs (straight, spiral, a ramp, a ladder), supports (pillars - the
## empire's columns - and beams between them), fences (balustrade, fence,
## a fence's gate) and furniture (lamps that light the rooms, a wall sconce,
## a chest that keeps things, a bed, a workbench and a kiln - the ship's
## fabricator and refinery - a table, a bench, a storage jar).
## Every piece in any of four TIERS - timber, stone, marble, bronze: each its
## own look and cost and strength (how far it reaches out unsupported:
## `span`) - in any empire's STYLE (its palette, columns, frieze, roof tiles:
## CosmosTown's looks), painted (PAINTS) if you like.
##
## A piece record (saved as JSON): {t: its id, p: [x, y, z] its anchor in its
## structure's frame, r: its turn (30 degree steps), m: tier, s: style, c:
## paint, d: a foundation's depth, o: open (doors), inv: a chest's things}.
## Anchors: a plate's (foundation, floor, roof) middle at its top - a roof's
## at its foot; an edge piece's (walls, fences...) middle of its edge at its
## foot, x along the edge; a corner piece's (pillar) corner at its foot; a
## cell piece's (stairs) middle of its cell at its foot, climbing along +z; a
## free piece's (furniture) spot on the floor.
##
## emit() lays a piece's faces into a CosmosTown.Builder (the building shader:
## each face's palette slot in its vertex colour; COLOR.a its paint) and
## returns what's solid of it (AABBs, or CosmosSolids.Prism for anything turned
## off the grid's axes or sloped), what moves (doors, shutters, gates, a hatch's
## lid: hinged leaves of their own), its lamps' lights and what you can use
## (a chest, a bed, a workbench). Plain data: built on workers.

## Free building (a sandbox: the user arg --free-build, or set live): nothing costs
## anything, nothing needs holding up (nor falls), towns are no bar. Pieces still
## fit their sockets and don't overlap.
static var free_build := "--free-build" in OS.get_cmdline_user_args()

const CELL := 4.0              # m: the grid
const WALL_H := 3.2            # m: a storey (floor to floor)
const SLAB := 0.22             # m: a floor / ceiling's thickness
const H := WALL_H - SLAB       # m: a wall's height (under the ceiling over it)
const WALL_T := 0.3
const POST := 0.5              # m: the posts where walls meet
const DOOR_W := 1.5
const DOOR_H := 2.45
const RISE := 2.0              # m: a sloped roof's rise over a cell
const TRI_R := 1.1547005       # a triangle's inradius (side CELL)
const TRI_H := 3.4641016       # its height
const FLAME := 12              # (the building shader's lit slot: a lamp's flame)
## The palette's slots (CosmosTown's, the building shader's).
enum { WALL, STONE, PALE, RED, BLACK, FRESCO, TRIM, DARK, HORNS, WOOD, JAR, ROOF }

## The tiers: [id, name, span (cells reached out from a support), toughness].
const TIERS := [
	{"id": "timber", "name": "Timber", "span": 2, "hp": 300},
	{"id": "stone", "name": "Stone", "span": 3, "hp": 800},
	{"id": "marble", "name": "Marble", "span": 3, "hp": 1100},
	{"id": "bronze", "name": "Bronze", "span": 4, "hp": 2000},
]
const STYLES := ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades"]
const STYLE_NAMES := {"minoa": "Minoan", "athens": "Athenian", "sparta": "Spartan", "mycenae": "Mycenaean", "ionia": "Ionian", "cyclades": "Cycladic"}
## Paints (0: the material's own colour).
const PAINTS := [Color(0, 0, 0, 0), Color(0.86, 0.62, 0.3), Color(0.6, 0.11, 0.08), Color(0.17, 0.34, 0.7), Color(0.95, 0.94, 0.9),
	Color(0.14, 0.13, 0.12), Color(0.3, 0.48, 0.3), Color(0.95, 0.76, 0.24), Color(0.42, 0.14, 0.38)]
const PAINT_NAMES := ["None", "Ochre", "Red", "Blue", "White", "Black", "Green", "Saffron", "Purple"]

const CATS := [["found", "Foundations"], ["floor", "Floors"], ["wall", "Walls"], ["open", "Doors & windows"], ["roof", "Roofs"],
	["stair", "Stairs"], ["support", "Supports"], ["fence", "Fences"], ["furn", "Furniture"]]
## The pieces: name, category, kind (plate / edge / corner / cell / free), shape
## (a plate's: sq / tri), units (its cost in its tier's materials) and its
## nature: found (on the ground), roof, bear (carries what's over it), post
## (posts where it meets another), hang (from the ceiling over it), mover
## (what swings), use (what it's for), light.
const PIECES := {
	"foundation": {"name": "Foundation", "cat": "found", "kind": "plate", "shape": "sq", "u": 6, "found": true},
	"foundation_tri": {"name": "Triangle foundation", "cat": "found", "kind": "plate", "shape": "tri", "u": 4, "found": true},
	"foundation_half": {"name": "Half foundation", "cat": "found", "kind": "plate", "shape": "half", "u": 3, "found": true},
	"foundation_quarter": {"name": "Quarter foundation", "cat": "found", "kind": "plate", "shape": "quarter", "u": 2, "found": true},
	"steps": {"name": "Front steps", "cat": "found", "kind": "edge", "u": 3, "outside": true},
	"floor": {"name": "Floor / ceiling", "cat": "floor", "kind": "plate", "shape": "sq", "u": 4},
	"floor_tri": {"name": "Triangle floor", "cat": "floor", "kind": "plate", "shape": "tri", "u": 3},
	"floor_half": {"name": "Half floor", "cat": "floor", "kind": "plate", "shape": "half", "u": 2},
	"floor_quarter": {"name": "Quarter floor", "cat": "floor", "kind": "plate", "shape": "quarter", "u": 1},
	"hatch": {"name": "Floor hatch", "cat": "floor", "kind": "plate", "shape": "sq", "u": 5, "mover": "hatch"},
	"wall": {"name": "Wall", "cat": "wall", "kind": "edge", "u": 4, "bear": true, "post": true},
	"half_wall": {"name": "Half wall", "cat": "wall", "kind": "edge", "u": 2, "post": true, "low": true},
	"wall_top": {"name": "Upper wall", "cat": "wall", "kind": "edge", "u": 2, "hang": true},
	"wall_slope": {"name": "Gable wall", "cat": "wall", "kind": "edge", "u": 2, "gable": true},
	"doorway": {"name": "Doorway", "cat": "open", "kind": "edge", "u": 3, "bear": true, "post": true},
	"door": {"name": "Door", "cat": "open", "kind": "edge", "u": 5, "bear": true, "post": true, "mover": "door"},
	"window": {"name": "Window", "cat": "open", "kind": "edge", "u": 4, "bear": true, "post": true, "mover": "shutters"},
	"arch": {"name": "Archway", "cat": "open", "kind": "edge", "u": 3, "bear": true, "post": true},
	"gate": {"name": "Gate", "cat": "open", "kind": "edge", "u": 8, "bear": true, "post": true, "mover": "gate"},
	"roof": {"name": "Sloped roof", "cat": "roof", "kind": "plate", "shape": "sq", "u": 4, "roof": true},
	"roof_hip": {"name": "Hip corner", "cat": "roof", "kind": "plate", "shape": "sq", "u": 4, "roof": true},
	"roof_valley": {"name": "Valley corner", "cat": "roof", "kind": "plate", "shape": "sq", "u": 4, "roof": true},
	"roof_peak": {"name": "Pyramid roof", "cat": "roof", "kind": "plate", "shape": "sq", "u": 4, "roof": true},
	"roof_tri": {"name": "Triangle roof", "cat": "roof", "kind": "plate", "shape": "tri", "u": 3, "roof": true},
	"roof_flat": {"name": "Flat roof", "cat": "roof", "kind": "plate", "shape": "sq", "u": 4},
	"stairs": {"name": "Stairs", "cat": "stair", "kind": "cell", "u": 5},
	"stairs_spiral": {"name": "Spiral stairs", "cat": "stair", "kind": "cell", "u": 6},
	"ramp": {"name": "Ramp", "cat": "stair", "kind": "cell", "u": 4},
	"ladder": {"name": "Ladder", "cat": "stair", "kind": "edge", "u": 2, "ladder": true},
	"pillar": {"name": "Pillar", "cat": "support", "kind": "corner", "u": 2, "bear": true},
	"beam": {"name": "Beam", "cat": "support", "kind": "edge", "u": 2, "bear": true, "beam": true},
	"railing": {"name": "Balustrade", "cat": "fence", "kind": "edge", "u": 2, "low": true},
	"fence": {"name": "Fence", "cat": "fence", "kind": "edge", "u": 2, "low": true},
	"fence_gate": {"name": "Fence gate", "cat": "fence", "kind": "edge", "u": 3, "low": true, "mover": "fence_gate"},
	"lamp": {"name": "Brazier", "cat": "furn", "kind": "free", "u": 2, "light": true},
	"sconce": {"name": "Wall lamp", "cat": "furn", "kind": "free", "u": 1, "light": true, "wallfix": true},
	"chest": {"name": "Chest", "cat": "furn", "kind": "free", "u": 4, "use": "chest"},
	"bed": {"name": "Bed", "cat": "furn", "kind": "free", "u": 4, "use": "bed"},
	"workbench": {"name": "Workbench", "cat": "furn", "kind": "free", "u": 5, "use": "fabricator"},
	"kiln": {"name": "Kiln", "cat": "furn", "kind": "free", "u": 6, "use": "refinery", "light": true},
	"table": {"name": "Table", "cat": "furn", "kind": "free", "u": 3},
	"bench": {"name": "Bench", "cat": "furn", "kind": "free", "u": 2},
	"pithos": {"name": "Storage jar", "cat": "furn", "kind": "free", "u": 2},
}
const CHEST_SLOTS := 12


static func info(id: String) -> Dictionary:
	return PIECES.get(id, {})


static func kind(id: String) -> String:
	return str(info(id).get("kind", ""))


static func ids_in(cat: String) -> Array:
	return PIECES.keys().filter(func(k): return PIECES[k]["cat"] == cat)


static func tier_name(m: int) -> String:
	return str(TIERS[clampi(m, 0, TIERS.size() - 1)]["name"])


static func span_of(m: int) -> int:
	return int(TIERS[clampi(m, 0, TIERS.size() - 1)]["span"])


static func hp_of(id: String, m: int) -> int:
	return roundi(float(TIERS[clampi(m, 0, TIERS.size() - 1)]["hp"]) * maxi(1, int(info(id).get("u", 1))) / 4.0)


static func title(id: String, m := -1, s := "") -> String:
	var n := str(info(id).get("name", id))
	if m >= 0:
		n = "%s %s" % [tier_name(m), n.to_lower()]
	if s != "":
		n += " (%s)" % STYLE_NAMES.get(s, s)
	return n


## What a piece costs in tier `m`: {item: units}. Timber: timber (felled trees,
## the markets); stone: building stone (dug ground); marble: stone and marble
## blocks; bronze: stone and bronze ingots (the fabricator casts them).
static func cost(id: String, m: int) -> Dictionary:
	var u := int(info(id).get("u", 1))
	match m:
		0: return {"timber": u}
		1: return {"stone": u}
		2: return {"stone": ceili(u * 0.5), "marble": ceili(u * 0.5)}
	return {"stone": ceili(u * 0.5), "bronze_ingots": ceili(u / 3.0)}


## A piece's toughness now (its record's "hp"; whole when it has none) and at full.
static func hp_now(pc: Dictionary) -> float:
	return float(pc.get("hp", hp_of(str(pc["t"]), int(pc.get("m", 1)))))


## How worn it shows: 0 (over 3/4 of its toughness left) .. 3 (under 1/4).
static func wear_level(pc: Dictionary) -> int:
	if not pc.has("hp"):
		return 0
	var f := hp_now(pc) / maxf(1.0, hp_of(str(pc["t"]), int(pc.get("m", 1))))
	return 0 if f > 0.75 else (1 if f > 0.5 else (2 if f > 0.25 else 3))


static func lockable(id: String) -> bool:
	return str(info(id).get("mover", "")) in ["door", "gate", "hatch", "fence_gate"]


## What you get back taking a piece down: half its cost (all of it within a
## minute of placing it - a mistake undone).
static func refund(pc: Dictionary, now: float) -> Dictionary:
	var full := now - float(pc.get("at", -1e9)) < 60.0
	var out := {}
	var c := cost(str(pc["t"]), int(pc.get("m", 1)))
	for k in c:
		var n := int(c[k]) if full else floori(int(c[k]) * 0.5)
		if n > 0:
			out[k] = n
	return out


static func cost_text(c: Dictionary) -> String:
	var parts := []
	for k in c:
		parts.append("%d %s" % [int(c[k]), Items.display_name(k)])
	return ", ".join(parts)


# --- Geometry -------------------------------------------------------------------------

static func yaw(r: int) -> float:
	return float(r) * PI / 6.0


static func turn(r: int) -> Basis:
	return Basis(Vector3.UP, yaw(r))


static func vec(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## A place's key (to the quarter metre): sockets that meet are one key.
static func key(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 4.0), roundi(v.y * 4.0), roundi(v.z * 4.0)]


## The turn (30 degree steps) whose +z is `n` (along the ground).
static func r_facing(n: Vector3) -> int:
	return posmod(roundi(atan2(n.x, n.z) / (PI / 6.0)), 12)


## The turn whose +x is `e`.
static func r_along(e: Vector3) -> int:
	return posmod(roundi(atan2(-e.z, e.x) / (PI / 6.0)), 12)


## A plate's outline, its own (x, z).
static func outline(shape: String) -> PackedVector2Array:
	if shape == "tri":
		return PackedVector2Array([Vector2(-CELL * 0.5, -TRI_R), Vector2(CELL * 0.5, -TRI_R), Vector2(0, TRI_H - TRI_R)])
	var e := extent(shape)
	if shape != "sq":   # (a half: 4 m along x, 2 m deep; a quarter: 2 x 2)
		return PackedVector2Array([Vector2(-e.x, -e.y), Vector2(e.x, -e.y), Vector2(e.x, e.y), Vector2(-e.x, e.y)])
	var h := CELL * 0.5
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])


## A plate's half size (x along its first edge, y its depth): squares 2 x 2 m, halves 2 x 1, quarters 1 x 1.
static func extent(shape: String) -> Vector2:
	match shape:
		"half": return Vector2(CELL * 0.5, CELL * 0.25)
		"quarter": return Vector2(CELL * 0.25, CELL * 0.25)
		"tri": return Vector2(CELL * 0.5, TRI_R)
	return Vector2(CELL * 0.5, CELL * 0.5)


## A plate piece's corners in the frame (at its anchor's height).
static func corners(pc: Dictionary) -> Array:
	var p := vec(pc["p"])
	var b := turn(int(pc.get("r", 0)))
	var out := []
	for q in outline(str(info(str(pc["t"])).get("shape", "sq"))):
		out.append(p + b * Vector3(q.x, 0, q.y))
	return out


## Its edges: [a, b, middle, out (unit, along the ground)].
static func edges(pc: Dictionary) -> Array:
	var cs := corners(pc)
	var c := vec(pc["p"])
	var out := []
	for i in cs.size():
		var a: Vector3 = cs[i]
		var b: Vector3 = cs[(i + 1) % cs.size()]
		var m := (a + b) * 0.5
		var e := (b - a).normalized()
		var n := Vector3(e.z, 0, -e.x)
		if n.dot(m - c) < 0.0:
			n = -n
		out.append([a, b, m, n])
	return out


## An edge piece's two ends (frame, at its foot).
static func ends(pc: Dictionary) -> Array:
	var p := vec(pc["p"])
	var x := turn(int(pc.get("r", 0))) * Vector3(CELL * 0.5, 0, 0)
	return [p - x, p + x]


## How tall a piece stands over its anchor (its top - the next storey's floor for walls).
static func height(id: String) -> float:
	var I := info(id)
	if I.get("low", false):
		return 1.15
	match id:
		"steps": return 0.0
		"wall_slope": return H + RISE
		"stairs", "stairs_spiral", "ramp", "ladder": return WALL_H
	if I["kind"] in ["edge", "corner"]:
		return WALL_H
	return 0.0


# --- Materials -------------------------------------------------------------------------

static var _ghosts := {}


## The building shader in style `s`'s palette, for built pieces: CosmosTown's
## look with its trim always metal (bronze), the paints and the flames' glow.
static func material(s: String) -> ShaderMaterial:
	return CosmosTown.material(s, true)


## The preview's: "ok" green, "bad" red, "pick" amber (what you'd take down).
static func ghost_material(k: String) -> StandardMaterial3D:
	if _ghosts.has(k):
		return _ghosts[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = {"ok": Color(0.35, 1.0, 0.55, 0.38), "bad": Color(1.0, 0.25, 0.18, 0.42), "pick": Color(1.0, 0.7, 0.2, 0.45)}.get(k, Color(1, 1, 1, 0.3))
	m.render_priority = 1
	_ghosts[k] = m
	return m


# --- A piece's faces --------------------------------------------------------------------

## A piece's faces into `out` (its frame's), at its place; what's solid of it,
## what swings, its lights and uses: {solids, movers, lights, uses}.
## `at_origin`: at the frame's middle, unturned (a preview's mesh).
## `leaves`: its hinged leaves made too (a town's buildings: none - their doorways open).
static func emit(out: CosmosTown.Builder, pc: Dictionary, at_origin := false, leaves := true) -> Dictionary:
	var id := str(pc["t"])
	var s := str(pc.get("s", "minoa"))
	var p := Vector3.ZERO if at_origin else vec(pc["p"])
	var r := 0 if at_origin else int(pc.get("r", 0))
	var lb := CosmosTown.Builder.new()
	lb.emp = s
	lb.taper = float((CosmosTown.LOOKS.get(s, CosmosTown.LOOKS[""]) as Array)[12])
	lb.rng.seed = hash([id, roundi(p.x * 10), roundi(p.y * 10), roundi(p.z * 10)])
	var res := {"solids": [], "movers": [], "lights": [], "uses": [], "leaves": leaves}
	_piece(lb, id, p.y, int(pc.get("m", 1)), s, pc, res)
	merge(out, lb, r, p, int(pc.get("c", 0)), wear_level(pc))
	var xf := Transform3D(turn(r), Vector3(p.x, 0.0, p.z))
	res["solids"] = res["solids"].map(func(so): return place_solid(so, r, p))
	for mv: Dictionary in res["movers"]:
		mv["xf"] = xf * (mv["xf"] as Transform3D)
	res["lights"] = res["lights"].map(func(l): return xf * (l as Vector3))
	res["uses"] = res["uses"].map(func(u): return [u[0], xf * (u[1] as Vector3)])
	return res


## `src`'s faces turned by `r` round the vertical and moved to `p` (x, z: its
## heights are already the frame's), into `dst`; painted `paint` (COLOR.a).
## `wear`: how worn it is, 0 sound - 3 nearly broken (cracks, soot: the shader). COLOR.a = 1 - (paint + 9 wear) / 64.
static func merge(dst: CosmosTown.Builder, src: CosmosTown.Builder, r: int, p: Vector3, paint := 0, wear := 0) -> void:
	var base := dst.verts.size()
	var xf := Transform3D(turn(r), Vector3(p.x, 0.0, p.z))
	dst.verts.append_array(xf * src.verts)
	dst.norms.append_array(Transform3D(turn(r), Vector3.ZERO) * src.norms)
	if paint == 0 and wear == 0:
		dst.cols.append_array(src.cols)
	else:
		var a := 1.0 - (paint + 9 * wear) / 64.0
		for c in src.cols:
			dst.cols.append(Color(c.r, c.g, c.b, a))
	var idx := src.idx.duplicate()
	if base > 0:
		for i in idx.size():
			idx[i] += base
	dst.idx.append_array(idx)


## A solid of a piece's own (an AABB, or ["prism", outline, y0, y1, planes,
## mode] - its x, z its own) into the frame: an AABB still when turned a
## quarter, else a Prism.
static func place_solid(so, r: int, p: Vector3):
	var b := turn(r)
	var xz := Vector3(p.x, 0.0, p.z)
	if so is AABB:
		var box: AABB = so
		if r % 3 == 0:
			var a := b * box.position + xz
			var e := b * box.end + xz
			return AABB(a.min(e), (a.max(e) - a.min(e)))
		so = ["prism", PackedVector2Array([Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
			Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)]), box.position.y, box.end.y, [], 0]
	var poly := PackedVector2Array()
	for q: Vector2 in so[1]:
		var w := b * Vector3(q.x, 0, q.y) + xz
		poly.append(Vector2(w.x, w.z))
	var c := cos(yaw(r))
	var sn := sin(yaw(r))
	var planes := []
	for pl: Vector3 in so[4]:
		var A := pl.x * c + pl.y * sn
		var Bz := -pl.x * sn + pl.y * c
		planes.append(Vector3(A, Bz, pl.z - A * p.x - Bz * p.z))
	return CosmosSolids.Prism.new(poly, float(so[2]), float(so[3]), planes, int(so[5]))


## What each tier's parts are made of (palette slots).
static func slots(m: int, s := "minoa") -> Dictionary:
	match m:
		0: return {"body": PALE, "base": STONE, "band": -1, "cap": WOOD, "frame": WOOD, "deck": WOOD, "floor": WOOD, "roof": WOOD, "post": WOOD, "metal": BLACK}
		2: return {"body": PALE, "base": STONE, "band": FRESCO, "cap": PALE, "frame": PALE, "deck": PALE, "floor": PALE, "roof": JAR, "post": PALE, "metal": TRIM}
		3: return {"body": STONE, "base": BLACK, "band": TRIM, "cap": TRIM, "frame": TRIM, "deck": PALE, "floor": PALE, "roof": TRIM, "post": TRIM, "metal": BLACK}
	var tiled := s in ["athens", "sparta", "mycenae", "ionia"]
	return {"body": WALL, "base": RED if s in ["sparta", "ionia"] else STONE, "band": FRESCO, "cap": TRIM, "frame": WOOD, "deck": PALE,
		"floor": PALE, "roof": JAR if tiled else ROOF, "post": STONE, "metal": TRIM}


static func _piece(lb: CosmosTown.Builder, id: String, y: float, m: int, s: String, pc: Dictionary, res: Dictionary) -> void:
	var S := slots(m, s)
	var sol: Array = res["solids"]
	var t := WALL_T * 0.5
	match id:
		"foundation", "foundation_tri", "foundation_half", "foundation_quarter":
			var poly := outline(str(info(id)["shape"]))
			var d := maxf(0.6, float(pc.get("d", 1.2)))
			var top := y - (0.08 if m != 0 else 0.12)
			prism(lb, poly, y - d, top, S["base"] if m != 3 else STONE, false)
			prism(lb, poly, top, y, S["deck"] if m != 0 else WOOD)
			if m == 3:   # (a bronze kerb round its top)
				_rim(lb, poly, y - 0.32, y - 0.1, 0.03, TRIM)
			elif m != 0:
				_rim(lb, poly, y - 0.5, y - 0.38, 0.025, S["cap"] if m == 1 else STONE)
			sol.append(_poly_solid(poly, y - d, y))
		"floor", "floor_tri", "floor_half", "floor_quarter", "roof_flat":
			var poly := outline(str(info(id)["shape"]))
			if id == "roof_flat":
				prism(lb, poly, y - SLAB, y - 0.06, S["floor"])
				prism(lb, poly, y - 0.06, y, S["roof"] if m != 0 else WOOD)
				_rim(lb, poly, y - 0.16, y + 0.02, 0.05, S["cap"] if m != 0 else WOOD)
			else:
				prism(lb, poly, y - SLAB, y, S["floor"])
				if m == 3:
					_rim(lb, poly, y - SLAB, y - SLAB + 0.08, 0.02, TRIM)
			sol.append(_poly_solid(poly, y - SLAB, y))
		"hatch":
			_hatch(lb, y, m, S, res)
		"wall", "doorway", "door", "window", "arch", "gate":
			var holes := []
			match id:
				"doorway", "door": holes = [Rect2(-DOOR_W * 0.5, 0.0, DOOR_W, DOOR_H)]
				"window": holes = [Rect2(-0.7, 1.0, 1.4, 1.0)]
				"arch": holes = [Rect2(-1.35, 0.0, 2.7, 2.55)]
				"gate": holes = [Rect2(-1.62, 0.0, 3.24, 2.72)]
			for b in wall(lb, y, m, s, holes):
				sol.append(b)
			for hole: Rect2 in holes:
				_frame(lb, y, hole, m, s, S, id)
			if res["leaves"]:
				match id:
					"door": _door_leaf(y, m, s, res)
					"window": _shutters(y, m, s, res)
					"gate": _gate_leaves(y, m, s, res)
		"half_wall":
			var L := CELL - WALL_T - 0.04
			lb.box(Vector3(-L * 0.5, y, -t), Vector3(L * 0.5, y + 1.0, t), S["body"], false)
			lb.box(Vector3(-L * 0.5, y, -t - 0.04), Vector3(L * 0.5, y + 0.35, t + 0.04), S["base"], false)
			lb.box(Vector3(-L * 0.5 - 0.01, y + 1.0, -t - 0.06), Vector3(L * 0.5 + 0.01, y + 1.15, t + 0.06), S["cap"], false)
			sol.append(AABB(Vector3(-L * 0.5, y, -t), Vector3(L, 1.15, WALL_T)))
		"wall_top":
			var L := CELL - WALL_T - 0.04
			var y0 := y + H - 0.95
			lb.box(Vector3(-L * 0.5, y0, -t), Vector3(L * 0.5, y + H, t), S["body"], false)
			if S["band"] >= 0:
				lb.box(Vector3(-L * 0.5, y + H - 0.9, -t - 0.03), Vector3(L * 0.5, y + H - 0.4, t + 0.03), S["band"], false)
			lb.box(Vector3(-L * 0.5 - 0.01, y + H - 0.28, -t - 0.07), Vector3(L * 0.5 + 0.01, y + H, t + 0.07), S["cap"], false)
			lb.box(Vector3(-L * 0.5 - 0.01, y0 - 0.1, -t - 0.05), Vector3(L * 0.5 + 0.01, y0 + 0.02, t + 0.05), S["frame"], false)   # (its lintel beam)
			sol.append(AABB(Vector3(-L * 0.5, y0 - 0.1, -t), Vector3(L, H - y0 + y + 0.1, WALL_T)))
		"wall_slope":
			# (a right triangle on the wall under it: 0 at -x up to RISE at +x - turned, the other way)
			var L := CELL - WALL_T - 0.04
			var a := Vector3(-L * 0.5, y - SLAB, 0)
			var bb := Vector3(L * 0.5, y - SLAB, 0)
			var c := Vector3(L * 0.5, y + RISE * ((L * 0.5 + CELL * 0.5) / CELL), 0)
			var col := Color(S["body"] / 255.0, lb.rng.randf(), fposmod(y, 8.0) / 8.0)
			lb.quad(a + Vector3(0, 0, t), bb + Vector3(0, 0, t), c + Vector3(0, 0, t), c + Vector3(0, 0, t), Vector3.BACK, col)
			lb.quad(a - Vector3(0, 0, t), c - Vector3(0, 0, t), bb - Vector3(0, 0, t), bb - Vector3(0, 0, t), Vector3.FORWARD, col)
			var sl := (c - a).normalized()
			var up := Vector3(-sl.y, sl.x, 0)
			lb.quad(a - Vector3(0, 0, t), a + Vector3(0, 0, t), c + Vector3(0, 0, t), c - Vector3(0, 0, t), up, col)
			lb.quad(bb - Vector3(0, 0, t), c - Vector3(0, 0, t), c + Vector3(0, 0, t), bb + Vector3(0, 0, t), Vector3.RIGHT, col)
			var n := 5
			for k in n:   # (stepped blocks: what's solid of it)
				var x0 := -L * 0.5 + L * k / n
				var x1 := -L * 0.5 + L * (k + 1) / n
				sol.append(AABB(Vector3(x0, y - SLAB, -t), Vector3(x1 - x0, SLAB + RISE * ((x1 + CELL * 0.5) / CELL), WALL_T)))
		"steps":
			var w := 2.6
			for k in 4:
				var top := y - 0.16 * (k + 1)
				lb.box(Vector3(-w * 0.5, y - 1.6, t + k * 0.36), Vector3(w * 0.5, top, t + (k + 1) * 0.36), S["base"] if m != 0 else WOOD, false)
				sol.append(AABB(Vector3(-w * 0.5, y - 2.0, t + k * 0.36), Vector3(w, top - y + 2.0, 0.36)))
			for sx: float in [-1.0, 1.0]:   # (its cheeks)
				lb.box(Vector3(sx * w * 0.5 - 0.12, y - 1.0, t), Vector3(sx * w * 0.5 + 0.12, y - 0.05, t + 1.44), S["base"] if m != 0 else WOOD, false)
		"roof", "roof_hip", "roof_valley", "roof_peak", "roof_tri":
			_roof(lb, id, y, m, s, S, sol)
		"stairs":
			# Masonry (stone, marble): each step a block down to the floor; timber and
			# bronze: treads between sloping stringers. A handrail either side.
			var w := 2.3
			var n := 8
			var solid_steps := m == 1 or m == 2
			for k in n:
				var z0 := -CELL * 0.5 + k * CELL / n
				var top := y + (k + 1) * WALL_H / n
				var z1 := z0 + CELL / n + (0.0 if k == n - 1 else 0.02)
				if solid_steps:   # (a block from the floor up: the flight solid, its sides stepped)
					lb.box(Vector3(-w * 0.5, y, z0), Vector3(w * 0.5, top, z1), S["floor"], false, 2)
				else:
					lb.box(Vector3(-w * 0.5, top - 0.1, z0), Vector3(w * 0.5, top, z1), S["floor"] if m != 3 else PALE, false)
					if m == 3:
						lb.box(Vector3(-w * 0.5, top - 0.04, z0 - 0.02), Vector3(w * 0.5, top + 0.01, z0 + 0.06), TRIM, false)
				sol.append(AABB(Vector3(-w * 0.5, y, z0), Vector3(w, top - y, CELL / n)))
			for sx: float in [-1.0, 1.0]:
				var a := Vector3(sx * (w * 0.5 + 0.09), y, -CELL * 0.5)
				if not solid_steps:   # (the stringers)
					_beam_between(lb, a + Vector3(0, -0.05, 0), a + Vector3(0, WALL_H - 0.05, CELL), 0.16, 0.36, S["post"])
				var rs: int = [WOOD, STONE, PALE, TRIM][clampi(m, 0, 3)]
				_rail(lb, a + Vector3(0, 0.95, 0.2), a + Vector3(0, WALL_H + 0.95, CELL), 0.06, rs)
				for t2: float in [0.2, 2.0, CELL]:   # (its posts)
					var q := a + Vector3(0, t2 / CELL * WALL_H, t2)
					lb.box(q + Vector3(-0.035, 0, -0.035), q + Vector3(0.035, 0.97, 0.035), rs, false)
		"stairs_spiral":
			var n := 12
			var R := 1.8
			var col: int = S["floor"] if m != 3 else PALE
			lb.lathe(Vector3(0, y, 0), [Vector2(0.22, 0.0), Vector2(0.2, WALL_H + 1.0), Vector2(0.28, WALL_H + 1.06)], 10, S["post"])
			var rail: Array = []
			var radii: Array = []
			for k in n:
				var a0 := TAU * k / n
				var a1 := TAU * (k + 1) / n + 0.04
				var top := y + (k + 1) * WALL_H / n
				var poly := PackedVector2Array([Vector2(cos(a0), sin(a0)) * 0.18, Vector2(cos(a0), sin(a0)) * R, Vector2(cos(a1), sin(a1)) * R, Vector2(cos(a1), sin(a1)) * 0.18])
				prism(lb, poly, top - 0.12, top, col)
				sol.append(["prism", poly, top - 0.12, top, [], 0])
			for k in 25:
				var a := TAU * k / 24.0
				rail.append(Vector3(cos(a) * (R - 0.05), y + WALL_H * k / 24.0 + 1.0, sin(a) * (R - 0.05)))
				radii.append(0.04)
			lb.tube(rail, radii, 6, S["metal"] if m >= 2 else WOOD)
			for k in range(0, 12, 2):   # (its balusters)
				var a := TAU * (k + 0.5) / n
				var at := Vector3(cos(a) * (R - 0.05), y + (k + 1) * WALL_H / n, sin(a) * (R - 0.05))
				lb.box(at - Vector3(0.025, 0, 0.025), at + Vector3(0.025, 1.0 - WALL_H / 24.0, 0.025), S["metal"] if m >= 2 else WOOD, false)
			sol.append(AABB(Vector3(-0.22, y, -0.22), Vector3(0.44, WALL_H + 1.0, 0.44)))
		"ramp":
			var w := 3.0
			var a0 := Vector3(-w * 0.5, y, -CELL * 0.5)
			var col := Color(S["floor"] / 255.0, lb.rng.randf(), fposmod(y, 8.0) / 8.0)
			var nrm := Vector3(0, CELL, -WALL_H).normalized()
			lb.quad(a0 + Vector3(0, 0.02, 0), a0 + Vector3(w, 0.02, 0), a0 + Vector3(w, WALL_H, CELL), a0 + Vector3(0, WALL_H, CELL), nrm, col)
			for sx in [0.0, w]:
				var side := Color(S["frame"] / 255.0, lb.rng.randf(), fposmod(y, 8.0) / 8.0)
				var o := Vector3(sx, 0, 0)
				var n2 := Vector3.LEFT if sx == 0.0 else Vector3.RIGHT
				lb.quad(a0 + o, a0 + o + Vector3(0, 0, CELL), a0 + o + Vector3(0, WALL_H, CELL), a0 + o + Vector3(0, WALL_H, CELL), n2, side)
				_rail(lb, a0 + o + Vector3(0, 1.0, 0), a0 + o + Vector3(0, WALL_H + 1.0, CELL), 0.05, S["metal"] if m >= 2 else WOOD)
				lb.box(a0 + o + Vector3(-0.04, 0, -0.04), a0 + o + Vector3(0.04, 1.0, 0.04), S["metal"] if m >= 2 else WOOD, false)
			lb.quad(a0 + Vector3(0, 0, CELL), a0 + Vector3(w, 0, CELL), a0 + Vector3(w, WALL_H, CELL), a0 + Vector3(0, WALL_H, CELL), Vector3.BACK, col)
			var k := WALL_H / CELL
			sol.append(["prism", PackedVector2Array([Vector2(-w * 0.5, -CELL * 0.5), Vector2(w * 0.5, -CELL * 0.5), Vector2(w * 0.5, CELL * 0.5), Vector2(-w * 0.5, CELL * 0.5)]),
				y, y + WALL_H, [Vector3(0.0, k, y + WALL_H * 0.5)], 1])
		"ladder":
			_ladder(lb, Vector3(0, y, t + 0.12), y + WALL_H + 0.9, m, S)
			for k in 8:   # (climbed: steep steps in front of it, each nearer the wall)
				var top := y + (k + 1) * WALL_H / 8.0
				sol.append(AABB(Vector3(-0.35, y, t), Vector3(0.7, top - y, maxf(0.12, 0.95 - k * 0.11))))
		"pillar":
			_pillar(lb, Vector3(0, y, 0), H, m, s, S)
			lb.solids.clear()
			sol.append(AABB(Vector3(-0.3, y, -0.3), Vector3(0.6, H, 0.6)))
		"beam":
			var L := CELL - 0.5
			lb.box(Vector3(-L * 0.5, y + H - 0.42, -0.17), Vector3(L * 0.5, y + H, 0.17), S["frame"] if m != 2 else PALE, false)
			if m == 1 and s in ["minoa", "mycenae"]:
				for k in 6:   # (the round ends of the joists over it)
					lb.disc(Vector3(-L * 0.5 + L * (k + 0.5) / 6.0, y + H - 0.2, 0.17), Vector3.BACK, 0.09, 0.06, WOOD, 7)
			elif m >= 1:
				lb.box(Vector3(-L * 0.5, y + H - 0.62, -0.19), Vector3(L * 0.5, y + H - 0.42, 0.19), S["cap"], false)
			sol.append(AABB(Vector3(-L * 0.5, y + H - 0.62, -0.19), Vector3(L, 0.62, 0.38)))
		"railing":
			var L := CELL - 0.36
			lb.box(Vector3(-L * 0.5, y + 0.98, -0.1), Vector3(L * 0.5, y + 1.1, 0.1), S["cap"], false)
			lb.box(Vector3(-L * 0.5, y, -0.08), Vector3(L * 0.5, y + 0.14, 0.08), S["base"] if m != 0 else WOOD, false)
			for k in 9:
				var x := -L * 0.5 + L * (k + 0.5) / 9.0
				if m == 0 or m == 3:
					lb.box(Vector3(x - 0.035, y + 0.14, -0.035), Vector3(x + 0.035, y + 0.98, 0.035), S["frame"] if m == 0 else TRIM, false)
				else:   # (turned balusters)
					lb.lathe(Vector3(x, y + 0.14, 0), [Vector2(0.06, 0.0), Vector2(0.04, 0.12), Vector2(0.075, 0.42), Vector2(0.035, 0.76), Vector2(0.06, 0.84)], 6, S["body"] if m == 1 else PALE, false)
			for sx: float in [-1.0, 1.0]:
				lb.box(Vector3(sx * L * 0.5 - 0.1, y, -0.12), Vector3(sx * L * 0.5 + 0.1, y + 1.16, 0.12), S["post"], false)
			sol.append(AABB(Vector3(-L * 0.5 - 0.1, y, -0.1), Vector3(L + 0.2, 1.16, 0.2)))
		"fence", "fence_gate":
			var L := CELL - 0.2
			var gap := 2.4 if id == "fence_gate" else 0.0
			_fence(lb, y, -L * 0.5, -gap * 0.5, m, S, sol)
			_fence(lb, y, gap * 0.5, L * 0.5, m, S, sol)
			if id == "fence_gate" and res["leaves"]:
				_fence_leaf(y, gap, m, s, res)
		"lamp":
			var h := 1.25
			for k in 3:
				var a := TAU * k / 3.0
				_beam_between(lb, Vector3(cos(a) * 0.32, y, sin(a) * 0.32), Vector3(cos(a) * 0.12, y + h - 0.1, sin(a) * 0.12), 0.05, 0.05, S["metal"] if m != 0 else WOOD)
			lb.lathe(Vector3(0, y + h - 0.15, 0), [Vector2(0.1, 0.0), Vector2(0.36, 0.14), Vector2(0.42, 0.26), Vector2(0.4, 0.3)], 12, TRIM if m != 0 else BLACK, false)
			lb.lathe(Vector3(0, y + h + 0.05, 0), [Vector2(0.3, 0.0), Vector2(0.16, 0.3), Vector2(0.0, 0.55)], 8, FLAME, false)
			sol.append(AABB(Vector3(-0.35, y, -0.35), Vector3(0.7, h + 0.2, 0.7)))
			res["lights"].append(Vector3(0, y + h + 0.6, 0))
		"sconce":
			# (on a wall: its back at z = 0, out along +z)
			lb.box(Vector3(-0.08, y + 1.75, 0.0), Vector3(0.08, y + 2.0, 0.06), S["metal"] if m != 0 else WOOD, false)
			_beam_between(lb, Vector3(0, y + 1.85, 0.04), Vector3(0, y + 2.05, 0.3), 0.04, 0.04, S["metal"] if m != 0 else BLACK)
			lb.lathe(Vector3(0, y + 2.02, 0.32), [Vector2(0.04, 0.0), Vector2(0.14, 0.08), Vector2(0.15, 0.12)], 8, TRIM, false)
			lb.lathe(Vector3(0, y + 2.1, 0.32), [Vector2(0.1, 0.0), Vector2(0.05, 0.12), Vector2(0.0, 0.24)], 6, FLAME, false)
			res["lights"].append(Vector3(0, y + 2.4, 0.4))
		"chest":
			var w := Vector3(0.55, 0.0, 0.33)
			lb.box(Vector3(-w.x, y, -w.z), Vector3(w.x, y + 0.5, w.z), WOOD if m != 3 else TRIM, false)
			lb.box(Vector3(-w.x - 0.02, y + 0.5, -w.z - 0.02), Vector3(w.x + 0.02, y + 0.66, w.z + 0.02), WOOD if m != 3 else TRIM, false)
			for x: float in [-0.36, 0.36]:   # (its bands)
				lb.box(Vector3(x - 0.05, y - 0.005, -w.z - 0.03), Vector3(x + 0.05, y + 0.67, w.z + 0.03), TRIM if m != 3 else BLACK, false)
			lb.box(Vector3(-0.07, y + 0.36, w.z), Vector3(0.07, y + 0.52, w.z + 0.04), TRIM, false)
			sol.append(AABB(Vector3(-w.x, y, -w.z), Vector3(w.x * 2.0, 0.66, w.z * 2.0)))
			res["uses"].append(["chest", Vector3(0, y, w.z + 0.6)])
		"bed":
			var fs: int = WOOD if m != 3 else TRIM
			lb.box(Vector3(-0.55, y + 0.25, -1.05), Vector3(0.55, y + 0.45, 1.05), fs, false)
			for k in 4:
				var q := Vector3(0.5 * (1 if k % 2 else -1), y, 1.0 * (1 if k < 2 else -1))
				lb.box(q - Vector3(0.05, 0, 0.05), q + Vector3(0.05, 0.3, 0.05), fs, false)
			lb.box(Vector3(-0.56, y + 0.25, -1.12), Vector3(0.56, y + 1.0, -1.04), fs, false)   # (its headboard)
			lb.box(Vector3(-0.5, y + 0.45, -1.0), Vector3(0.5, y + 0.6, 1.0), PALE, false)
			lb.box(Vector3(-0.5, y + 0.6, -0.15), Vector3(0.5, y + 0.64, 1.0), RED if s != "athens" else FRESCO, false)   # (a cover)
			lb.box(Vector3(-0.35, y + 0.6, -0.95), Vector3(0.35, y + 0.72, -0.6), PALE, false)
			sol.append(AABB(Vector3(-0.56, y, -1.12), Vector3(1.12, 0.64, 2.17)))
			res["uses"].append(["bed", Vector3(0.95, y, 0)])
		"workbench", "table":
			var w := Vector3(0.9, 0.0, 0.45) if id == "workbench" else Vector3(0.75, 0.0, 0.5)
			var top := 0.9 if id == "workbench" else 0.78
			lb.box(Vector3(-w.x, y + top - 0.08, -w.z), Vector3(w.x, y + top, w.z), WOOD if m != 2 else PALE, false)
			for k in 4:
				var q := Vector3((w.x - 0.08) * (1 if k % 2 else -1), y, (w.z - 0.08) * (1 if k < 2 else -1))
				lb.box(q - Vector3(0.05, 0, 0.05), q + Vector3(0.05, top - 0.08, 0.05), WOOD if m != 3 else TRIM, false)
			if id == "workbench":
				lb.box(Vector3(-w.x + 0.06, y + 0.25, -w.z + 0.06), Vector3(w.x - 0.06, y + 0.31, w.z - 0.06), WOOD, false)   # (a shelf)
				lb.box(Vector3(-0.6, y + top, -0.1), Vector3(-0.2, y + top + 0.12, 0.15), BLACK, false)   # (an anvil, tools)
				lb.box(Vector3(0.1, y + top, -0.3), Vector3(0.14, y + top + 0.04, 0.2), TRIM, false)
				lb.box(Vector3(0.3, y + top, -0.25), Vector3(0.6, y + top + 0.2, -0.05), JAR, false)
				res["uses"].append(["fabricator", Vector3(0, y, w.z + 0.65)])
			sol.append(AABB(Vector3(-w.x, y, -w.z), Vector3(w.x * 2.0, top, w.z * 2.0)))
		"bench":
			lb.box(Vector3(-0.8, y + 0.38, -0.2), Vector3(0.8, y + 0.45, 0.2), WOOD if m < 2 else S["body"], false)
			for x: float in [-0.65, 0.65]:
				lb.box(Vector3(x - 0.06, y, -0.17), Vector3(x + 0.06, y + 0.38, 0.17), WOOD if m < 2 else S["base"], false)
			sol.append(AABB(Vector3(-0.8, y, -0.2), Vector3(1.6, 0.45, 0.4)))
		"pithos":
			var h := 1.35
			var R := h * 0.34
			lb.lathe(Vector3(0, y, 0), [Vector2(R * 0.45, 0.0), Vector2(R * 0.8, h * 0.18), Vector2(R, h * 0.42), Vector2(R * 0.96, h * 0.58),
				Vector2(R * 0.75, h * 0.8), Vector2(R * 0.5, h * 0.9), Vector2(R * 0.52, h * 0.95), Vector2(R * 0.62, h)], 12, [JAR, JAR, TRIM, JAR, JAR, JAR, TRIM], false)
			sol.append(AABB(Vector3(-R, y, -R), Vector3(R * 2.0, h, R * 2.0)))
		"kiln":
			lb.lathe(Vector3(0, y, 0), [Vector2(0.75, 0.0), Vector2(0.78, 0.5), Vector2(0.7, 1.1), Vector2(0.45, 1.5), Vector2(0.18, 1.7), Vector2(0.16, 2.0)], 14, STONE if m != 3 else TRIM, false)
			lb.box(Vector3(-0.26, y + 0.18, 0.62), Vector3(0.26, y + 0.62, 0.8), FLAME, false)   # (its mouth, glowing)
			lb.box(Vector3(-0.34, y + 0.62, 0.6), Vector3(0.34, y + 0.72, 0.84), STONE if m != 3 else BLACK, false)
			sol.append(AABB(Vector3(-0.75, y, -0.75), Vector3(1.5, 1.6, 1.5)))
			res["lights"].append(Vector3(0, y + 0.6, 1.2))
			res["uses"].append(["refinery", Vector3(0, y, 1.45)])


## A wall's body with its openings (`holes`: x along it, y up from its foot),
## its base course, frieze band and cornice (the tier's and style's) - broken
## at the openings. What's solid of it: its body's blocks.
static func wall(lb: CosmosTown.Builder, y: float, m: int, s: String, holes: Array, h := H) -> Array:
	var S := slots(m, s)
	var L := CELL - WALL_T - 0.04
	var t := WALL_T * 0.5
	var blocks := holed(lb, -L * 0.5, L * 0.5, y, y + h, -t, t, holes, S["body"])
	strip(lb, -L * 0.5, L * 0.5, y, y + (0.45 if m != 3 else 0.35), t + 0.04, holes, S["base"], y)
	if S["band"] >= 0:
		strip(lb, -L * 0.5, L * 0.5, y + h - 1.05, y + h - 0.55, t + 0.03, holes, S["band"], y)   # (half a metre: one repeat of the frieze's pattern, whole)
	strip(lb, -L * 0.5, L * 0.5, y + h - 0.28, y + h, t + 0.07, holes, S["cap"], y)
	if m == 0:   # (timber framing: sill, top plate, a rail, studs - in the daub's face)
		strip(lb, -L * 0.5, L * 0.5, y + h - 0.5, y + h - 0.32, t + 0.03, holes, WOOD, y)
		strip(lb, -L * 0.5, L * 0.5, y + 1.3, y + 1.45, t + 0.03, holes, WOOD, y)
		for x: float in [-0.95, 0.95]:
			var free := true
			for hole: Rect2 in holes:
				if x > hole.position.x - 0.15 and x < hole.end.x + 0.15:
					free = false
			if free:
				lb.box(Vector3(x - 0.07, y + 0.45, -t - 0.03), Vector3(x + 0.07, y + h - 0.5, t + 0.03), WOOD, false)
	elif m == 3:   # (bronze plates riveted on, a band at waist height)
		strip(lb, -L * 0.5, L * 0.5, y + 0.95, y + 1.25, t + 0.05, holes, TRIM, y)
	return blocks


## The box x0..x1, ya..yb, z0..z1 less the openings (`holes`, y from `ya`): as few blocks as it takes.
static func holed(lb: CosmosTown.Builder, x0: float, x1: float, ya: float, yb: float, z0: float, z1: float, holes: Array, slot: int) -> Array:
	var xs := [x0, x1]
	for hole: Rect2 in holes:
		for x in [hole.position.x, hole.end.x]:
			if x > x0 and x < x1:
				xs.append(x)
	xs.sort()
	var out := []
	for i in xs.size() - 1:
		var xa: float = xs[i]
		var xb: float = xs[i + 1]
		if xb - xa < 0.001:
			continue
		var mid := (xa + xb) * 0.5
		var ends := (32 if xa <= x0 + 0.001 else 0) | (16 if xb >= x1 - 0.001 else 0)   # (its ends in the posts: never seen)
		var cuts := []
		for hole: Rect2 in holes:
			if mid > hole.position.x and mid < hole.end.x:
				cuts.append([ya + hole.position.y, ya + hole.end.y])
		cuts.sort_custom(func(a, b): return a[0] < b[0])
		var yy := ya
		for c in cuts:
			if c[0] > yy + 0.001:
				lb.box(Vector3(xa, yy, z0), Vector3(xb, minf(c[0], yb), z1), slot, false, ends | (2 if yy == ya else 0))
				out.append(AABB(Vector3(xa, yy, z0), Vector3(xb - xa, minf(c[0], yb) - yy, z1 - z0)))
			yy = maxf(yy, c[1])
		if yb > yy + 0.001:   # (its top under the cornice: never seen)
			lb.box(Vector3(xa, yy, z0), Vector3(xb, yb, z1), slot, false, ends | (2 if yy == ya else 0) | 1)
			out.append(AABB(Vector3(xa, yy, z0), Vector3(xb - xa, yb - yy, z1 - z0)))
	return out


## A band along a wall (y0..y1, out `o` either side), stopped 2 cm short of the openings it meets.
static func strip(lb: CosmosTown.Builder, x0: float, x1: float, y0: float, y1: float, o: float, holes: Array, slot: int, foot: float) -> void:
	var runs := [[x0 - 0.01, x1 + 0.01]]
	for hole: Rect2 in holes:
		if foot + hole.end.y <= y0 or foot + hole.position.y >= y1:
			continue
		var next := []
		for rn in runs:
			if hole.end.x + 0.02 <= rn[0] or hole.position.x - 0.02 >= rn[1]:
				next.append(rn)
				continue
			if hole.position.x - 0.02 > rn[0]:
				next.append([rn[0], hole.position.x - 0.02])
			if hole.end.x + 0.02 < rn[1]:
				next.append([hole.end.x + 0.02, rn[1]])
		runs = next
	for rn in runs:
		if rn[1] - rn[0] > 0.05:
			var skip := (32 if rn[0] <= x0 else 0) | (16 if rn[1] >= x1 else 0) | (2 if y0 <= foot + 0.001 else 0)
			lb.box(Vector3(rn[0], y0, -o), Vector3(rn[1], y1, o), slot, false, skip)


## An opening's frame: its jambs (inside the opening: no face on a wall's
## face), lintel, a window's sill; Mycenae's relieving triangle over a door.
static func _frame(lb: CosmosTown.Builder, y: float, hole: Rect2, m: int, s: String, S: Dictionary, id: String) -> void:
	var t := WALL_T * 0.5 + 0.04
	var f: int = S["frame"]
	var x0 := hole.position.x
	var x1 := hole.end.x
	var top := y + hole.end.y
	var j := 0.1 if id == "gate" else 0.07
	lb.box(Vector3(x0, y + hole.position.y, -t), Vector3(x0 + j, top - 0.02, t), f, false)
	lb.box(Vector3(x1 - j, y + hole.position.y, -t), Vector3(x1, top - 0.02, t), f, false)
	lb.box(Vector3(x0 - 0.16, top - 0.04, -t - 0.01), Vector3(x1 + 0.16, top + (0.32 if id == "gate" else 0.22), t + 0.01), f if id != "arch" or m == 0 else S["cap"], false)
	if id == "window":
		lb.box(Vector3(x0 - 0.1, y + hole.position.y - 0.1, -t - 0.05), Vector3(x1 + 0.1, y + hole.position.y + 0.03, t + 0.05), S["base"] if m != 0 else WOOD, false)
	if id == "door" or id == "doorway" or id == "gate":   # (the threshold)
		lb.box(Vector3(x0 + j, y - 0.02, -t + 0.02), Vector3(x1 - j, y + 0.025, t - 0.02), STONE if m != 3 else TRIM, false)
	if m >= 1 and s == "mycenae" and id != "window":
		var yy := top + (0.32 if id == "gate" else 0.22)
		var w := (x1 - x0) * 0.45
		for sd: float in [-1.0, 1.0]:
			lb.quad(Vector3(-w, yy, sd * (t + 0.02)), Vector3(w, yy, sd * (t + 0.02)), Vector3(0, yy + 0.7, sd * (t + 0.02)), Vector3(0, yy + 0.7, sd * (t + 0.02)),
				Vector3(0, 0, sd), Color(RED / 255.0, lb.rng.randf(), 0.0))


## Round a plate's outline (out `o`), y0..y1: a band (a kerb, a rim).
static func _rim(lb: CosmosTown.Builder, poly: PackedVector2Array, y0: float, y1: float, o: float, slot: int) -> void:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= poly.size()
	var grown := PackedVector2Array()
	for q in poly:
		grown.append(c + (q - c) * (1.0 + o / maxf((q - c).length() * 0.5, 0.01)))
	var col := Color(slot / 255.0, lb.rng.randf(), fposmod(y0, 8.0) / 8.0)
	for i in poly.size():
		var a := grown[i]
		var b := grown[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var n := Vector3(e.y, 0, -e.x)
		if n.dot(Vector3(a.x - c.x, 0, a.y - c.y)) < 0.0:
			n = -n
		lb.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), n, col)
		lb.quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(poly[(i + 1) % poly.size()].x, y1, poly[(i + 1) % poly.size()].y), Vector3(poly[i].x, y1, poly[i].y), Vector3.UP, col)


## A block standing on outline `poly` (convex), y0..y1: its top, its sides (and its foot, `foot`).
static func prism(lb: CosmosTown.Builder, poly: PackedVector2Array, y0: float, y1: float, slot: int, foot := true) -> void:
	var col := Color(slot / 255.0, lb.rng.randf(), fposmod(y0, 8.0) / 8.0)
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= poly.size()
	var n := poly.size()
	if n == 4:   # (a square: one quad over, one under)
		lb.quad(Vector3(poly[0].x, y1, poly[0].y), Vector3(poly[1].x, y1, poly[1].y), Vector3(poly[2].x, y1, poly[2].y), Vector3(poly[3].x, y1, poly[3].y), Vector3.UP, col)
		if foot:
			lb.quad(Vector3(poly[0].x, y0, poly[0].y), Vector3(poly[3].x, y0, poly[3].y), Vector3(poly[2].x, y0, poly[2].y), Vector3(poly[1].x, y0, poly[1].y), Vector3.DOWN, col)
	for i in (range(1, n - 1) if n != 4 else []):
		lb.quad(Vector3(poly[0].x, y1, poly[0].y), Vector3(poly[i].x, y1, poly[i].y), Vector3(poly[i + 1].x, y1, poly[i + 1].y), Vector3(poly[i + 1].x, y1, poly[i + 1].y), Vector3.UP, col)
		if foot:
			lb.quad(Vector3(poly[0].x, y0, poly[0].y), Vector3(poly[i + 1].x, y0, poly[i + 1].y), Vector3(poly[i].x, y0, poly[i].y), Vector3(poly[i].x, y0, poly[i].y), Vector3.DOWN, col)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := (b - a).normalized()
		var nr := Vector3(e.y, 0, -e.x)
		if nr.dot(Vector3(a.x - c.x, 0, a.y - c.y)) < 0.0:
			nr = -nr
		lb.quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), nr, col)


static func _poly_solid(poly: PackedVector2Array, y0: float, y1: float):
	if poly.size() == 4 and absf(poly[0].x - poly[3].x) < 0.001 and absf(poly[0].y - poly[1].y) < 0.001:
		return AABB(Vector3(poly[0].x, y0, poly[0].y), Vector3(poly[2].x - poly[0].x, y1 - y0, poly[2].y - poly[0].y))
	return ["prism", poly, y0, y1, [], 0]


## A square beam from `a` to `b` (its section w x h, level or sloping).
static func _beam_between(lb: CosmosTown.Builder, a: Vector3, b: Vector3, w: float, h: float, slot: int) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized() * (w * 0.5)
	var up := side.cross(d).normalized() * (h * 0.5)
	if up.y < 0.0:
		up = -up
	var col := Color(slot / 255.0, lb.rng.randf(), 0.0)
	var c := [a - side - up, a + side - up, a + side + up, a - side + up]
	var e := [b - side - up, b + side - up, b + side + up, b - side + up]
	for i in 4:
		var j := (i + 1) % 4
		var mid: Vector3 = ((c[i] as Vector3) + (c[j] as Vector3)) * 0.5 - a
		lb.quad(c[i], c[j], e[j], e[i], mid.normalized(), col)
	lb.quad(c[0], c[3], c[2], c[1], -d, col)
	lb.quad(e[0], e[1], e[2], e[3], d, col)


static func _rail(lb: CosmosTown.Builder, a: Vector3, b: Vector3, r: float, slot: int) -> void:
	lb.tube([a, b], [r, r], 6, slot)


## A ladder: two rails and rungs, its foot at `at`, up to `top`.
static func _ladder(lb: CosmosTown.Builder, at: Vector3, top: float, m: int, S: Dictionary) -> void:
	var slot: int = S["metal"] if m >= 2 else WOOD
	for sx: float in [-0.26, 0.26]:
		lb.box(at + Vector3(sx - 0.03, 0, -0.03), Vector3(at.x + sx + 0.03, top, at.z + 0.03), slot, false)
	var y := at.y + 0.3
	while y < top - 0.1:
		lb.box(Vector3(at.x - 0.26, y - 0.02, at.z - 0.02), Vector3(at.x + 0.26, y + 0.02, at.z + 0.02), slot, false)
		y += 0.3


## A pillar on `at`, `h` tall: the style's column in stone (CosmosTown's -
## Minoan, Doric, Ionic, a Cycladic pier), a squared post in timber, a white
## column in marble, a bronze shaft.
static func _pillar(lb: CosmosTown.Builder, at: Vector3, h: float, m: int, s: String, S: Dictionary) -> void:
	match m:
		0:
			lb.box(at + Vector3(-0.17, 0, -0.17), at + Vector3(0.17, h - 0.3, 0.17), WOOD, false)
			lb.box(at + Vector3(-0.22, 0, -0.22), at + Vector3(0.22, 0.25, 0.22), STONE, false)
			lb.box(at + Vector3(-0.3, h - 0.3, -0.22), at + Vector3(0.3, h, 0.22), WOOD, false)
		1:
			lb.column(at, h, 0.28)
		2:
			lb.lathe(at, [Vector2(0.4, 0.0), Vector2(0.4, 0.12), Vector2(0.3, 0.22), Vector2(0.27, h - 0.4), Vector2(0.36, h - 0.25), Vector2(0.4, h - 0.2)], 14, PALE)
			lb.box(at + Vector3(-0.42, h - 0.2, -0.42), at + Vector3(0.42, h, 0.42), PALE, false)
		_:
			lb.lathe(at, [Vector2(0.36, 0.0), Vector2(0.36, 0.2), Vector2(0.24, 0.3), Vector2(0.22, h - 0.35), Vector2(0.33, h - 0.2)], 12, [BLACK, BLACK, TRIM, BLACK], false)
			lb.box(at + Vector3(-0.36, h - 0.2, -0.36), at + Vector3(0.36, h, 0.36), BLACK, false)


## A post where walls meet (one a corner, at `at`, `h` tall): a pilaster of the tier's.
static func post(lb: CosmosTown.Builder, at: Vector3, h: float, m: int, s: String) -> Array:
	var S := slots(m, s)
	var q := POST * 0.5
	if m == 0:
		lb.box(at + Vector3(-q, 0, -q), at + Vector3(q, h, q), S["post"], false, 2)
	else:   # (its shaft, a capital - the walls' base course runs round its foot)
		lb.box(at + Vector3(-q, 0, -q), at + Vector3(q, h - 0.22, q), S["post"], false, 3)
		lb.box(at + Vector3(-q - 0.04, h - 0.22, -q - 0.04), at + Vector3(q + 0.04, h, q + 0.04), S["cap"], false)
	return [AABB(at + Vector3(-q, 0, -q), Vector3(POST, h, POST))]


## Roofs: a slab of `id`'s shape over the cell from its foot `y` (the tops of
## the walls) - sloped (rising along +z), a hip (two slopes rising to the +x +z
## corner), a valley (falling to the -x -z corner), a pyramid (four slopes to its
## middle), a triangle's (three) - eaves trimmed; what's solid: its slopes as planes.
static func _roof(lb: CosmosTown.Builder, id: String, y: float, m: int, s: String, S: Dictionary, sol: Array) -> void:
	var h := CELL * 0.5
	var k := RISE / CELL
	var th := 0.18
	var cover: int = S["roof"]
	var under: int = S["floor"] if m != 3 else STONE
	var tris := []   # [a, b, c] - the top's triangles (local, y up from 0)
	var planes := []
	var mode := 1
	var poly := outline("tri" if id == "roof_tri" else "sq")
	match id:
		"roof":
			tris = [[Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, RISE, h)], [Vector3(-h, 0, -h), Vector3(h, RISE, h), Vector3(-h, RISE, h)]]
			planes = [Vector3(0, k, y + RISE * 0.5)]
		"roof_hip":
			tris = [[Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, RISE, h)], [Vector3(-h, 0, -h), Vector3(h, RISE, h), Vector3(-h, 0, h)]]
			planes = [Vector3(0, k, y + RISE * 0.5), Vector3(k, 0, y + RISE * 0.5)]
		"roof_valley":
			tris = [[Vector3(-h, 0, -h), Vector3(h, RISE, -h), Vector3(h, RISE, h)], [Vector3(-h, 0, -h), Vector3(h, RISE, h), Vector3(-h, RISE, h)]]
			planes = [Vector3(0, k, y + RISE * 0.5), Vector3(k, 0, y + RISE * 0.5)]
			mode = 2
		"roof_peak":
			var apex := Vector3(0, RISE * 0.5, 0)
			var cs := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
			for i in 4:
				tris.append([cs[i], cs[(i + 1) % 4], apex])
			planes = [Vector3(0, k, y + RISE * 0.5), Vector3(0, -k, y + RISE * 0.5), Vector3(k, 0, y + RISE * 0.5), Vector3(-k, 0, y + RISE * 0.5)]
		"roof_tri":
			var ap := Vector3(0, RISE * 0.5, 0)
			for i in 3:
				tris.append([Vector3(poly[i].x, 0, poly[i].y), Vector3(poly[(i + 1) % 3].x, 0, poly[(i + 1) % 3].y), ap])
			var kk := (RISE * 0.5) / TRI_R
			for i in 3:   # (each slope rising from its edge to the apex)
				var a := poly[i]
				var b := poly[(i + 1) % 3]
				var e := (b - a).normalized()
				var inward := Vector2(-e.y, e.x)
				if inward.dot(-a) < 0.0:
					inward = -inward
				# height = kk * (distance in from the edge) = kk * ((q - a) . inward)
				planes.append(Vector3(kk * inward.x, kk * inward.y, y - kk * a.dot(inward)))
	var ccol := Color(cover / 255.0, lb.rng.randf(), 0.0)
	var ucol := Color(under / 255.0, lb.rng.randf(), 0.0)
	var top := 0.0
	for tr in tris:
		var a: Vector3 = tr[0] + Vector3(0, y + 0.02, 0)
		var b: Vector3 = tr[1] + Vector3(0, y + 0.02, 0)
		var c: Vector3 = tr[2] + Vector3(0, y + 0.02, 0)
		var n := (b - a).cross(c - a).normalized()
		if n.y < 0.0:
			n = -n
		lb.quad(a, b, c, c, n, ccol)
		lb.quad(a - Vector3(0, th, 0), c - Vector3(0, th, 0), b - Vector3(0, th, 0), b - Vector3(0, th, 0), -n, ucol)
		top = maxf(top, maxf(a.y, maxf(b.y, c.y)))
	# Its eaves and verges: the slab's edges round its outline.
	for i in poly.size():
		var a2 := poly[i]
		var b2 := poly[(i + 1) % poly.size()]
		var ha := _h_at(tris, a2) + y + 0.02
		var hb := _h_at(tris, b2) + y + 0.02
		var e := (b2 - a2).normalized()
		var n := Vector3(e.y, 0, -e.x)
		if n.dot(Vector3(a2.x, 0, a2.y)) < 0.0:
			n = -n
		lb.quad(Vector3(a2.x, ha - th, a2.y), Vector3(b2.x, hb - th, b2.y), Vector3(b2.x, hb, b2.y), Vector3(a2.x, ha, a2.y), n, Color((S["cap"] if m != 0 else WOOD) / 255.0, lb.rng.randf(), 0.0))
	if m == 1 and s == "minoa" and id == "roof_peak":   # (horns of consecration on a Minoan cap)
		lb.horns(Vector3(0, y + RISE * 0.5 - 0.05, 0), true)
	if m >= 1 and s == "cyclades" and id == "roof_peak":
		lb.dome(Vector3(0, y + RISE * 0.5 - 0.1, 0), 0.6, RED)
		lb.solids.clear()
	sol.append(["prism", poly, y - th, top, planes, mode])


static func _h_at(tris: Array, q: Vector2) -> float:
	for tr in tris:
		for v: Vector3 in tr:
			if absf(v.x - q.x) < 0.01 and absf(v.z - q.y) < 0.01:
				return v.y
	return 0.0


## A floor with a hatch: the slab round a 1.5 m opening, the lid (it swings
## up), a ladder down to the floor under it - climbed by walking into it.
static func _hatch(lb: CosmosTown.Builder, y: float, m: int, S: Dictionary, res: Dictionary) -> void:
	var h := CELL * 0.5
	var x0 := 0.25
	var x1 := 1.75
	var z0 := -1.75
	var z1 := -0.25
	var f: int = S["floor"]
	var sol: Array = res["solids"]
	for b in [[Vector3(-h, y - SLAB, -h), Vector3(x0, y, h)], [Vector3(x1, y - SLAB, -h), Vector3(h, y, h)],
			[Vector3(x0, y - SLAB, -h), Vector3(x1, y, z0)], [Vector3(x0, y - SLAB, z1), Vector3(x1, y, h)]]:
		lb.box(b[0], b[1], f, false)
		sol.append(AABB(b[0], b[1] - b[0]))
	lb.box(Vector3(x0 - 0.06, y - 0.02, z0 - 0.06), Vector3(x1 + 0.06, y + 0.02, z0), S["frame"], false)
	_ladder(lb, Vector3((x0 + x1) * 0.5, y - WALL_H, z0 + 0.12), y + 0.9, m, S)
	for k in 8:
		var top := y - WALL_H + (k + 1) * WALL_H / 8.0
		sol.append(AABB(Vector3(x0 + 0.15, y - WALL_H, z0), Vector3(x1 - x0 - 0.3, top - y + WALL_H, maxf(0.12, 1.05 - k * 0.12))))
	if not res["leaves"]:
		return
	# The lid: hinged along its -x side, it swings up about z.
	var lid := CosmosTown.Builder.new()
	lid.box(Vector3(0, -0.06, 0), Vector3(x1 - x0, 0.0, z1 - z0), WOOD if m != 3 else TRIM, false)
	for zz in [0.3, z1 - z0 - 0.3]:
		lid.box(Vector3(0.05, 0.0, zz - 0.04), Vector3(x1 - x0 - 0.05, 0.03, zz + 0.04), TRIM if m != 3 else BLACK, false)
	res["movers"].append({"lb": lid, "xf": Transform3D(Basis(), Vector3(x0, y, z0)), "axis": Vector3(0, 0, -1), "angle": deg_to_rad(105.0),
		"box": AABB(Vector3(0, -0.06, 0), Vector3(x1 - x0, 0.06, z1 - z0)), "walk": true})


## A door's leaf: hinged at the doorway's -x jamb, swinging out to +z.
static func _door_leaf(y: float, m: int, s: String, res: Dictionary) -> void:
	var w := DOOR_W - 0.16
	var b := CosmosTown.Builder.new()
	b.emp = s
	var slot := TRIM if m == 3 else WOOD
	b.box(Vector3(0.02, 0.02, -0.04), Vector3(w - 0.02, DOOR_H - 0.06, 0.04), slot, false)
	for yy: float in [0.35, 1.2, 2.05]:   # (its battens, studs)
		b.box(Vector3(0.06, yy, 0.04), Vector3(w - 0.06, yy + 0.12, 0.07), WOOD if m == 3 else BLACK if m >= 1 else WOOD, false)
		b.box(Vector3(0.06, yy, -0.07), Vector3(w - 0.06, yy + 0.12, -0.04), WOOD if m == 3 else BLACK if m >= 1 else WOOD, false)
	b.disc(Vector3(w - 0.2, 1.05, 0.04), Vector3.BACK, 0.07, 0.05, TRIM, 8)
	b.disc(Vector3(w - 0.2, 1.05, -0.04), Vector3.FORWARD, 0.07, 0.05, TRIM, 8)
	res["movers"].append({"lb": b, "xf": Transform3D(Basis(), Vector3(-DOOR_W * 0.5 + 0.08, y, 0.0)), "axis": Vector3.UP, "angle": -deg_to_rad(100.0),
		"box": AABB(Vector3(0, 0, -0.07), Vector3(w, DOOR_H - 0.06, 0.14))})


## A window's two shutters, hinged either side outside, swung open flat against the wall.
static func _shutters(y: float, m: int, s: String, res: Dictionary) -> void:
	var w := 0.66
	var b := CosmosTown.Builder.new()
	var slot := TRIM if m == 3 else WOOD
	b.box(Vector3(0.0, 0.0, 0.0), Vector3(w, 0.96, 0.05), slot, false)
	for yy: float in [0.12, 0.42, 0.72]:
		b.box(Vector3(0.05, yy, 0.05), Vector3(w - 0.05, yy + 0.1, 0.075), DARK if m != 3 else BLACK, false)
	var z := WALL_T * 0.5 + 0.06
	res["movers"].append({"lb": b, "xf": Transform3D(Basis(), Vector3(-0.71, y + 1.02, z)), "axis": Vector3.UP, "angle": -deg_to_rad(165.0), "box": AABB(), "open0": true})
	res["movers"].append({"lb": b, "xf": Transform3D(Basis(Vector3.UP, PI), Vector3(0.71, y + 1.02, z + 0.05)), "axis": Vector3.UP, "angle": deg_to_rad(165.0), "box": AABB(), "open0": true})


## A gate's two great doors (bronze-bound), swinging out to +z.
static func _gate_leaves(y: float, m: int, s: String, res: Dictionary) -> void:
	var w := 1.52
	var hgt := 2.66
	var b := CosmosTown.Builder.new()
	var slot := TRIM if m == 3 else WOOD
	b.box(Vector3(0.0, 0.03, -0.06), Vector3(w, hgt, 0.06), slot, false)
	for yy: float in [0.3, 1.2, 2.15]:
		b.box(Vector3(0.04, yy, 0.06), Vector3(w - 0.04, yy + 0.16, 0.09), BLACK if slot == WOOD else WOOD, false)
		b.box(Vector3(0.04, yy, -0.09), Vector3(w - 0.04, yy + 0.16, -0.06), BLACK if slot == WOOD else WOOD, false)
	for k in 5:
		b.disc(Vector3(0.2 + k * 0.28, 1.65, 0.06), Vector3.BACK, 0.05, 0.04, TRIM, 6)
	res["movers"].append({"lb": b, "xf": Transform3D(Basis(), Vector3(-1.52, y, 0.0)), "axis": Vector3.UP, "angle": -deg_to_rad(95.0),
		"box": AABB(Vector3(0, 0, -0.06), Vector3(w, hgt, 0.12))})
	res["movers"].append({"lb": b, "xf": Transform3D(Basis(Vector3.UP, PI), Vector3(1.52, y, 0.0)), "axis": Vector3.UP, "angle": deg_to_rad(95.0),
		"box": AABB(Vector3(0, 0, -0.06), Vector3(w, hgt, 0.12))})


## A run of fence from x0 to x1: posts and rails (timber), a dry-stone wall
## (stone), a marble balustrade's plain cousin, bronze railings.
static func _fence(lb: CosmosTown.Builder, y: float, x0: float, x1: float, m: int, S: Dictionary, sol: Array) -> void:
	if x1 - x0 < 0.1:
		return
	match m:
		1:
			lb.box(Vector3(x0, y, -0.25), Vector3(x1, y + 0.95, 0.25), STONE, false)
			lb.box(Vector3(x0 - 0.01, y + 0.95, -0.28), Vector3(x1 + 0.01, y + 1.08, 0.28), STONE, false)
			sol.append(AABB(Vector3(x0, y, -0.28), Vector3(x1 - x0, 1.08, 0.56)))
			return
		2:
			lb.box(Vector3(x0, y, -0.12), Vector3(x1, y + 0.3, 0.12), PALE, false)
			lb.box(Vector3(x0, y + 0.95, -0.12), Vector3(x1, y + 1.07, 0.12), PALE, false)
			var n := maxi(1, int((x1 - x0) / 0.5))
			for k in n:
				var x := x0 + (x1 - x0) * (k + 0.5) / n
				lb.box(Vector3(x - 0.06, y + 0.3, -0.06), Vector3(x + 0.06, y + 0.95, 0.06), PALE, false)
			sol.append(AABB(Vector3(x0, y, -0.12), Vector3(x1 - x0, 1.07, 0.24)))
			return
	var slot := WOOD if m == 0 else BLACK
	for x in [x0 + 0.06, x1 - 0.06]:
		lb.box(Vector3(x - 0.07, y, -0.07), Vector3(x + 0.07, y + 1.2, 0.07), slot, false)
	for yy: float in [0.45, 0.95]:
		lb.box(Vector3(x0, y + yy, -0.04), Vector3(x1, y + yy + 0.1, 0.04), slot if m == 0 else TRIM, false)
	if m == 3:
		var n := maxi(1, int((x1 - x0) / 0.25))
		for k in n:
			var x := x0 + (x1 - x0) * (k + 0.5) / n
			lb.box(Vector3(x - 0.015, y + 0.05, -0.015), Vector3(x + 0.015, y + 1.12, 0.015), BLACK, false)
	sol.append(AABB(Vector3(x0, y, -0.07), Vector3(x1 - x0, 1.2, 0.14)))


static func _fence_leaf(y: float, gap: float, m: int, s: String, res: Dictionary) -> void:
	var w := gap - 0.08
	var b := CosmosTown.Builder.new()
	var slot := WOOD if m < 2 else (PALE if m == 2 else TRIM)
	for yy: float in [0.3, 0.9]:
		b.box(Vector3(0, yy, -0.035), Vector3(w, yy + 0.1, 0.035), slot, false)
	for x in [0.05, w * 0.5, w - 0.05]:
		b.box(Vector3(x - 0.05, 0.15, -0.035), Vector3(x + 0.05, 1.1, 0.035), slot, false)
	_beam_between(b, Vector3(0.1, 0.35, 0), Vector3(w - 0.1, 0.95, 0), 0.06, 0.06, slot)
	res["movers"].append({"lb": b, "xf": Transform3D(Basis(), Vector3(-gap * 0.5 + 0.04, y, 0.0)), "axis": Vector3.UP, "angle": -deg_to_rad(100.0),
		"box": AABB(Vector3(0, 0, -0.05), Vector3(w, 1.15, 0.1))})


# --- A piece's picture (the build menu, the HUD) --------------------------------------

## A line drawing of piece `id` in `rect` (its elevation, or plan for plates).
static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, col: Color) -> void:
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) * 0.42
	var w := maxf(1.5, s * 0.07)
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + (p as Vector2) * s)
		return out
	var fill := Color(col, 0.22)
	var line := func(pts: Array, closed := true) -> void:
		var pp: PackedVector2Array = P.call(pts)
		if closed:
			pp.append(pp[0])
		ci.draw_polyline(pp, col, w, true)
	var poly := func(pts: Array) -> void:
		ci.draw_colored_polygon(P.call(pts), fill)
		line.call(pts)
	match id:
		"foundation", "floor", "hatch", "roof_flat":
			var y0 := 0.1 if id == "foundation" else -0.05
			poly.call([Vector2(-0.9, y0 - 0.35), Vector2(0.2, y0 - 0.7), Vector2(0.9, y0 - 0.35), Vector2(-0.2, y0)])
			if id == "foundation":
				poly.call([Vector2(-0.9, y0 - 0.35), Vector2(-0.2, y0), Vector2(-0.2, y0 + 0.5), Vector2(-0.9, y0 + 0.15)])
				poly.call([Vector2(-0.2, y0), Vector2(0.9, y0 - 0.35), Vector2(0.9, y0 + 0.15), Vector2(-0.2, y0 + 0.5)])
			else:
				line.call([Vector2(-0.9, y0 - 0.35), Vector2(-0.9, y0 - 0.25), Vector2(-0.2, y0 + 0.1), Vector2(0.9, y0 - 0.25), Vector2(0.9, y0 - 0.35)], false)
			if id == "hatch":
				poly.call([Vector2(0.0, y0 - 0.45), Vector2(0.35, y0 - 0.58), Vector2(0.55, y0 - 0.47), Vector2(0.2, y0 - 0.34)])
			if id == "roof_flat":
				line.call([Vector2(-0.95, y0 - 0.45), Vector2(0.2, y0 - 0.82), Vector2(0.95, y0 - 0.45)], false)
		"foundation_tri", "floor_tri":
			poly.call([Vector2(-0.9, 0.3), Vector2(0.9, 0.3), Vector2(0.0, -0.6)])
			if id == "foundation_tri":
				line.call([Vector2(-0.9, 0.3), Vector2(-0.9, 0.6), Vector2(0.9, 0.6), Vector2(0.9, 0.3)], false)
		"steps":
			poly.call([Vector2(-0.8, 0.7), Vector2(-0.8, 0.3), Vector2(-0.3, 0.3), Vector2(-0.3, -0.1), Vector2(0.2, -0.1), Vector2(0.2, -0.5), Vector2(0.8, -0.5), Vector2(0.8, 0.7)])
		"wall", "half_wall", "wall_top", "doorway", "door", "window", "arch", "gate":
			var top := -0.75 if id != "half_wall" else 0.1
			var bot := 0.75 if id != "wall_top" else -0.1
			poly.call([Vector2(-0.85, top), Vector2(0.85, top), Vector2(0.85, bot), Vector2(-0.85, bot)])
			ci.draw_line(c + Vector2(-0.85, top + 0.18) * s, c + Vector2(0.85, top + 0.18) * s, col, w * 0.7)
			match id:
				"doorway", "door":
					ci.draw_rect(Rect2(c + Vector2(-0.28, -0.25) * s, Vector2(0.56, 1.0) * s), Color(0, 0, 0, 0.55) if id == "doorway" else fill)
					line.call([Vector2(-0.28, 0.75), Vector2(-0.28, -0.25), Vector2(0.28, -0.25), Vector2(0.28, 0.75)], false)
					if id == "door":
						ci.draw_circle(c + Vector2(0.16, 0.25) * s, w, col)
				"window":
					ci.draw_rect(Rect2(c + Vector2(-0.3, -0.35) * s, Vector2(0.6, 0.45) * s), Color(0, 0, 0, 0.55))
					line.call([Vector2(-0.3, -0.35), Vector2(0.3, -0.35), Vector2(0.3, 0.1), Vector2(-0.3, 0.1)])
					line.call([Vector2(-0.3, -0.35), Vector2(-0.55, -0.3), Vector2(-0.55, 0.05), Vector2(-0.3, 0.1)])
					line.call([Vector2(0.3, -0.35), Vector2(0.55, -0.3), Vector2(0.55, 0.05), Vector2(0.3, 0.1)])
				"arch":
					ci.draw_rect(Rect2(c + Vector2(-0.6, -0.3) * s, Vector2(1.2, 1.05) * s), Color(0, 0, 0, 0.55))
					line.call([Vector2(-0.6, 0.75), Vector2(-0.6, -0.3), Vector2(0.6, -0.3), Vector2(0.6, 0.75)], false)
				"gate":
					ci.draw_rect(Rect2(c + Vector2(-0.72, -0.45) * s, Vector2(1.44, 1.2) * s), fill)
					line.call([Vector2(-0.72, 0.75), Vector2(-0.72, -0.45), Vector2(0.72, -0.45), Vector2(0.72, 0.75)], false)
					ci.draw_line(c + Vector2(0, -0.45) * s, c + Vector2(0, 0.75) * s, col, w)
		"wall_slope":
			poly.call([Vector2(-0.85, 0.6), Vector2(0.85, 0.6), Vector2(0.85, -0.6)])
		"roof", "roof_hip", "roof_valley", "roof_peak", "roof_tri":
			match id:
				"roof": poly.call([Vector2(-0.9, 0.5), Vector2(0.3, 0.5), Vector2(0.9, -0.4), Vector2(-0.3, -0.4)])
				"roof_hip":
					poly.call([Vector2(-0.9, 0.5), Vector2(0.5, 0.5), Vector2(0.6, -0.4)])
					poly.call([Vector2(0.5, 0.5), Vector2(0.95, 0.2), Vector2(0.6, -0.4)])
				"roof_valley":
					poly.call([Vector2(-0.9, -0.3), Vector2(0.5, -0.3), Vector2(0.0, 0.5)])
					poly.call([Vector2(0.5, -0.3), Vector2(0.95, -0.55), Vector2(0.0, 0.5)])
				"roof_peak":
					poly.call([Vector2(-0.9, 0.45), Vector2(0.0, -0.55), Vector2(0.9, 0.45)])
					line.call([Vector2(0.0, -0.55), Vector2(0.25, 0.6)], false)
				"roof_tri":
					poly.call([Vector2(-0.8, 0.5), Vector2(0.0, -0.5), Vector2(0.8, 0.5)])
					line.call([Vector2(0.0, -0.5), Vector2(0.0, 0.62), Vector2(-0.8, 0.5)], false)
		"stairs", "ramp":
			if id == "ramp":
				poly.call([Vector2(-0.85, 0.7), Vector2(0.85, -0.7), Vector2(0.85, 0.7)])
			else:
				var pts := [Vector2(-0.85, 0.7)]
				for k in 5:
					pts.append(Vector2(-0.85 + k * 0.34, 0.7 - (k + 1) * 0.28))
					pts.append(Vector2(-0.85 + (k + 1) * 0.34, 0.7 - (k + 1) * 0.28))
				pts.append(Vector2(0.85, 0.7))
				poly.call(pts)
		"stairs_spiral":
			ci.draw_line(c + Vector2(0, -0.85) * s, c + Vector2(0, 0.85) * s, col, w * 1.5)
			for k in 6:
				var yy := 0.7 - k * 0.28
				var x := 0.7 if k % 2 == 0 else -0.7
				line.call([Vector2(0, yy), Vector2(x, yy - 0.1), Vector2(x, yy + 0.02)], false)
		"ladder":
			for sx: float in [-0.35, 0.35]:
				ci.draw_line(c + Vector2(sx, -0.85) * s, c + Vector2(sx, 0.85) * s, col, w * 1.3)
			for k in 6:
				ci.draw_line(c + Vector2(-0.35, -0.65 + k * 0.27) * s, c + Vector2(0.35, -0.65 + k * 0.27) * s, col, w)
		"pillar":
			poly.call([Vector2(-0.18, -0.65), Vector2(0.18, -0.65), Vector2(0.24, 0.7), Vector2(-0.24, 0.7)])
			poly.call([Vector2(-0.4, -0.85), Vector2(0.4, -0.85), Vector2(0.3, -0.65), Vector2(-0.3, -0.65)])
		"beam":
			poly.call([Vector2(-0.9, -0.6), Vector2(0.9, -0.6), Vector2(0.9, -0.3), Vector2(-0.9, -0.3)])
			for sx: float in [-0.8, 0.8]:
				line.call([Vector2(sx - 0.1, -0.3), Vector2(sx - 0.1, 0.8), Vector2(sx + 0.1, 0.8), Vector2(sx + 0.1, -0.3)], false)
		"railing", "fence", "fence_gate":
			ci.draw_line(c + Vector2(-0.9, -0.3) * s, c + Vector2(0.9, -0.3) * s, col, w * 1.4)
			ci.draw_line(c + Vector2(-0.9, 0.2) * s, c + Vector2(0.9, 0.2) * s, col, w)
			for k in (7 if id == "railing" else 3):
				var x := -0.8 + k * (1.6 / (6.0 if id == "railing" else 2.0))
				ci.draw_line(c + Vector2(x, -0.45) * s, c + Vector2(x, 0.6) * s, col, w)
			if id == "fence_gate":
				ci.draw_line(c + Vector2(-0.6, 0.2) * s, c + Vector2(0.6, -0.3) * s, col, w)
		"lamp", "sconce", "kiln":
			if id == "kiln":
				poly.call([Vector2(-0.6, 0.75), Vector2(-0.55, -0.1), Vector2(-0.2, -0.6), Vector2(0.2, -0.6), Vector2(0.55, -0.1), Vector2(0.6, 0.75)])
				ci.draw_rect(Rect2(c + Vector2(-0.2, 0.2) * s, Vector2(0.4, 0.35) * s), Color(1.0, 0.55, 0.15, 0.9))
			else:
				if id == "lamp":
					line.call([Vector2(-0.4, 0.8), Vector2(0.0, -0.1), Vector2(0.4, 0.8)], false)
				else:
					line.call([Vector2(-0.6, -0.8), Vector2(-0.6, 0.4), Vector2(0.0, 0.0)], false)
				poly.call([Vector2(-0.4, -0.15), Vector2(0.4, -0.15), Vector2(0.25, 0.05), Vector2(-0.25, 0.05)])
				ci.draw_colored_polygon(P.call([Vector2(-0.22, -0.18), Vector2(0.0, -0.75), Vector2(0.22, -0.18)]), Color(1.0, 0.6, 0.2, 0.9))
		"chest":
			poly.call([Vector2(-0.75, -0.15), Vector2(0.75, -0.15), Vector2(0.75, 0.6), Vector2(-0.75, 0.6)])
			poly.call([Vector2(-0.8, -0.45), Vector2(0.8, -0.45), Vector2(0.8, -0.15), Vector2(-0.8, -0.15)])
			ci.draw_rect(Rect2(c + Vector2(-0.1, -0.2) * s, Vector2(0.2, 0.25) * s), col)
		"bed":
			poly.call([Vector2(-0.9, 0.1), Vector2(0.9, 0.1), Vector2(0.9, 0.4), Vector2(-0.9, 0.4)])
			poly.call([Vector2(-0.9, -0.45), Vector2(-0.75, -0.45), Vector2(-0.75, 0.6), Vector2(-0.9, 0.6)])
			poly.call([Vector2(-0.7, -0.05), Vector2(-0.35, -0.05), Vector2(-0.35, 0.1), Vector2(-0.7, 0.1)])
		"workbench", "table", "bench":
			var yt := -0.2 if id != "bench" else 0.1
			poly.call([Vector2(-0.9, yt - 0.12), Vector2(0.9, yt - 0.12), Vector2(0.9, yt), Vector2(-0.9, yt)])
			for sx: float in [-0.75, 0.75]:
				ci.draw_line(c + Vector2(sx, yt) * s, c + Vector2(sx, 0.75) * s, col, w * 1.3)
			if id == "workbench":
				poly.call([Vector2(-0.6, yt - 0.42), Vector2(-0.15, yt - 0.42), Vector2(-0.15, yt - 0.12), Vector2(-0.6, yt - 0.12)])
				ci.draw_line(c + Vector2(0.2, yt - 0.12) * s, c + Vector2(0.55, yt - 0.5) * s, col, w * 1.2)
		"pithos":
			poly.call([Vector2(-0.25, -0.75), Vector2(0.25, -0.75), Vector2(0.55, -0.2), Vector2(0.45, 0.4), Vector2(0.18, 0.78), Vector2(-0.18, 0.78), Vector2(-0.45, 0.4), Vector2(-0.55, -0.2)])
			ci.draw_line(c + Vector2(-0.52, -0.05) * s, c + Vector2(0.52, -0.05) * s, col, w)
		_:
			poly.call([Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)])
