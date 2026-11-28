class_name TownStreets
extends RefCounted
## A town's streets (CosmosTown): its plan - blocks of houses between paved
## streets, each empire's way, round the palace's court (a city) or a crossing
## (a village):
##   Minoa (and the others' default) - a ring of streets round the palace, the
##     avenues out of its gates, a street or two more each way;
##   Athens, Ionia - a regular grid: long narrow blocks, the temple at a street's end;
##   Sparta - few streets, long blocks (its villages grown together);
##   Mycenae - rings round the citadel and the avenues out through them (a radial plan);
##   the Cyclades - many narrow lanes, small blocks.
## Streets are lines across the town's square (a street a line, its width),
## cut round what stands in their way (the palace, the shrine, the storehouse -
## keep_out) and where they cross (the streets along x stop at those along z:
## nothing drawn twice). Where one meets the square's edge is a gate: a road
## out of the town begins there (CosmosRoads). All town-local (x, z metres,
## the town's frame - CosmosTown.frame), the same for every town of its kind
## and empire (cached).
##   TownStreets.pieces(kind, emp)   # [{r: Rect2, w, along: 0 x / 1 z, main}]
##   TownStreets.gates(kind, emp)    # [{at: Vector3, out: Vector3, w, inner: [Vector3...]}]
##   TownStreets.cells(kind, emp)    # the blocks between them: [{r: Rect2, sides: [-x, +x, -z, +z] street-facing}]

const KERB := 1.5               # m: a street's edge to its block's lots
const EDGE := 2.0               # m: the square's edge to the lots
const MIN_PIECE := 8.0          # m: shorter stubs left out
const FIELD_Z := 44.0           # (the +x side's middle: the landing field - no gate there)

static var _cache := {}


## The street lines: {"x": [[x, width]...] (running along z), "z": [[z, width]...] (along x)}.
static func lines(kind: String, emp: String) -> Dictionary:
	if kind != "city":
		var w := 4.0 if emp == "cyclades" else 4.5
		if emp == "sparta":
			return {"x": [[0.0, 5.0]], "z": [[0.0, 6.0]]}
		return {"x": [[-30.0, w], [0.0, 5.0], [30.0, w]], "z": [[0.0, 6.0], [26.0, w]]}
	var m := 5.0 if emp == "cyclades" else 7.0   # (the ring round the palace, the avenues)
	var xs: Array = [[-42.0, m], [0.0, m], [42.0, m]]
	var zs: Array = [[-36.0, m], [0.0, m], [36.0, m]]
	match emp:
		"athens", "ionia":
			xs.append_array([[-63.0, 5.0], [-21.0, 5.0], [21.0, 5.0], [63.0, 5.0]])
			zs.append_array([[-60.0, 5.0], [60.0, 5.0]])
		"sparta":
			xs.append_array([[-66.0, 6.0], [66.0, 6.0]])
		"mycenae":
			xs.append_array([[-70.0, 6.0], [70.0, 6.0]])
			zs.append_array([[-66.0, 6.0], [66.0, 6.0]])
		"cyclades":
			xs.append_array([[-63.0, 4.0], [-21.0, 4.0], [21.0, 4.0], [63.0, 4.0]])
			zs.append_array([[-60.0, 4.0], [-18.0, 4.0], [18.0, 4.0], [60.0, 4.0]])
		_:
			xs.append_array([[-66.0, 5.0], [66.0, 5.0]])
			zs.append_array([[-62.0, 5.0], [62.0, 5.0]])
	xs.sort_custom(func(a, b): return a[0] < b[0])
	zs.sort_custom(func(a, b): return a[0] < b[0])
	return {"x": xs, "z": zs}


## What stands in the streets' way (town-local Rect2s): the palace, the shrine, the storehouse.
static func keep_out(kind: String) -> Array:
	var lay := CosmosTown.layout(kind)
	var out: Array = []
	if kind == "city":
		out.append(Rect2(-34.5, -26.5, 67.0, 53.0))
	out.append(shrine_rect(lay["shrine"]))
	out.append(store_rect(lay["store"]))
	return out


static func shrine_rect(c: Vector3) -> Rect2:
	return Rect2(c.x - 11.5, c.z - 7.5, 23.0, 18.5)   # (its platform, the steps up at its front: +z)


static func store_rect(c: Vector3) -> Rect2:
	return Rect2(c.x - 11.0, c.z - 7.5, 22.0, 15.5)   # (the long hall, its jars in front: +z)


## The streets: [{r: Rect2 (town-local x, z), w: its width, along: 0 (runs along x) / 1 (along z), main: a ring or avenue}].
static func pieces(kind: String, emp: String) -> Array:
	var key := "%s|%s" % [kind, emp]
	if _cache.has(key):
		return _cache[key]
	var H: float = CosmosTown.layout(kind)["half"]
	var L := lines(kind, emp)
	var cuts := keep_out(kind)
	var out: Array = []
	for ln in L["x"]:   # (along z first: whole)
		var r := Rect2(float(ln[0]) - float(ln[1]) * 0.5, -H, float(ln[1]), H * 2.0)
		for p in _minus(r, cuts, 1):
			out.append({"r": p, "w": float(ln[1]), "along": 1, "main": float(ln[1]) >= 6.0 or absf(float(ln[0])) < 0.1})
	var cross: Array = cuts.duplicate()
	for q in out:
		cross.append(q["r"])
	for ln in L["z"]:   # (along x: between those - each crossing drawn once)
		var r := Rect2(-H, float(ln[0]) - float(ln[1]) * 0.5, H * 2.0, float(ln[1]))
		for p in _minus(r, cross, 0):
			out.append({"r": p, "w": float(ln[1]), "along": 0, "main": float(ln[1]) >= 6.0 or absf(float(ln[0])) < 0.1})
	_cache[key] = out
	return out


## `r` with what `cuts` cover along its run (axis 0: x, 1: z) taken out: the pieces left.
static func _minus(r: Rect2, cuts: Array, axis: int) -> Array:
	var spans: Array = [[r.position[axis], r.end[axis]]]
	for c: Rect2 in cuts:
		if not c.intersects(r):
			continue
		var a: float = c.position[axis]
		var b: float = c.end[axis]
		var next: Array = []
		for s in spans:
			if b <= s[0] or a >= s[1]:
				next.append(s)
				continue
			if a > s[0]:
				next.append([s[0], a])
			if b < s[1]:
				next.append([b, s[1]])
		spans = next
	var out: Array = []
	for s in spans:
		if float(s[1]) - float(s[0]) < MIN_PIECE:
			continue
		var p := r
		p.position[axis] = s[0]
		p.size[axis] = float(s[1]) - float(s[0])
		out.append(p)
	return out


## Where its streets meet the square's edge (none into the landing field's side):
## [{at (town-local, on the edge), out (unit, outward), w, inner: [the gate, ... in along
## the street to the ring round the palace (a city) or the middle crossing (a village),
## or to where the street ends]}].
static func gates(kind: String, emp: String) -> Array:
	var key := "g|%s|%s" % [kind, emp]
	if _cache.has(key):
		return _cache[key]
	var H: float = CosmosTown.layout(kind)["half"]
	var L := lines(kind, emp)
	var ring_x := 0.0
	var ring_z := 0.0
	if kind == "city":
		ring_x = (L["x"] as Array).filter(func(l): return float(l[0]) > 0.1)[0][0]
		ring_z = (L["z"] as Array).filter(func(l): return float(l[0]) > 0.1)[0][0]
	var out: Array = []
	for p in pieces(kind, emp):
		var r: Rect2 = p["r"]
		var c := r.get_center()
		var ax: int = p["along"]
		for sd in [-1.0, 1.0]:
			var edge: float = r.position[ax] if sd < 0.0 else r.end[ax]
			if absf(absf(edge) - H) > 0.01 or signf(edge) != sd:
				continue
			var at := Vector3(sd * H, 0, c.y) if ax == 0 else Vector3(c.x, 0, sd * H)
			var o := Vector3(sd, 0, 0) if ax == 0 else Vector3(0, 0, sd)
			if ax == 0 and sd > 0.0 and absf(c.y) < FIELD_Z:
				continue   # (the field's side)
			# (in: to the ring round the palace (a village: the middle crossing) - an avenue on
			# to the palace's gate - or to whatever stands at the street's end first)
			var ring := ring_x if ax == 0 else ring_z
			var cross := c.y if ax == 0 else c.x
			var stop: float = 0.0 if (kind == "city" and absf(cross) < 0.1) else sd * ring
			var strip := r
			strip.position[ax] = -H
			strip.size[ax] = H * 2.0
			for k: Rect2 in keep_out(kind):
				if not k.intersects(strip.grow(-0.05)):
					continue
				var near: float = k.end[ax] if sd > 0.0 else k.position[ax]
				if sd * near < sd * edge and sd * near > sd * stop:
					stop = near   # (it stands in the way: in up to it)
			var end := Vector3(stop, 0, c.y) if ax == 0 else Vector3(c.x, 0, stop)
			out.append({"at": at, "out": o, "w": float(p["w"]), "inner": [at, end]})
	_cache[key] = out
	return out


## The blocks between the streets: [{r: Rect2 (its lots' ground), sides: [bool -x, +x, -z, +z]: a street on that side}].
static func cells(kind: String, emp: String) -> Array:
	var H: float = CosmosTown.layout(kind)["half"]
	var L := lines(kind, emp)
	var xs: Array = [[-H, 0.0, false]]
	for l in L["x"]:
		xs.append([float(l[0]), float(l[1]), true])
	xs.append([H, 0.0, false])
	var zs: Array = [[-H, 0.0, false]]
	for l in L["z"]:
		zs.append([float(l[0]), float(l[1]), true])
	zs.append([H, 0.0, false])
	var out: Array = []
	for i in xs.size() - 1:
		var x0: float = float(xs[i][0]) + (float(xs[i][1]) * 0.5 + KERB if xs[i][2] else EDGE)
		var x1: float = float(xs[i + 1][0]) - (float(xs[i + 1][1]) * 0.5 + KERB if xs[i + 1][2] else EDGE)
		for j in zs.size() - 1:
			var z0: float = float(zs[j][0]) + (float(zs[j][1]) * 0.5 + KERB if zs[j][2] else EDGE)
			var z1: float = float(zs[j + 1][0]) - (float(zs[j + 1][1]) * 0.5 + KERB if zs[j + 1][2] else EDGE)
			if x1 - x0 < 6.0 or z1 - z0 < 6.0:
				continue
			out.append({"r": Rect2(x0, z0, x1 - x0, z1 - z0), "sides": [xs[i][2], xs[i + 1][2], zs[j][2], zs[j + 1][2]]})
	return out


## Is town-local `p` on one of its streets (or `grow` m by it)?
static func on_street(kind: String, emp: String, p: Vector3, grow := 0.0) -> bool:
	var q := Vector2(p.x, p.z)
	for s in pieces(kind, emp):
		if (s["r"] as Rect2).grow(grow).has_point(q):
			return true
	return false
