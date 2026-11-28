extends RefCounted
## The roads' bridges (CosmosRoads: `const Bridges`): wherever a road runs over
## water - the sea, a lake, a river (PlanetShape.water_level) - it crosses on a
## bridge: a stone deck a few metres over the water (CLEAR_SEA over the sea's
## waves, CLEAR_RIVER over a river; over a gorge level with its banks), ramping
## up from the banks at a gentle grade (RAMP), the road paved over it, parapets
## either side, stone piers every ~SPAN m standing in the water with arches
## between them and cutwaters on them, and lamps at the bridge's ends and on
## every other pier - each empire its own way (its town palette: CosmosTown's
## building shader slots; Minoa: red timber railings on stone posts, horns of
## consecration over the piers; the others solid parapets in their own stone,
## their frieze on the deck's edge). Static: fixed geometry, nothing in it moves
## (only the lamps' flames - by night: `lamp_lit`).
##
## Worked out with the network (make, on its worker: deterministic, from the
## ground) into each road's "bridges": [{i0, i1 (its points, inclusive), s0,
## h (the deck's top at each point, m above the radius), g (the ground under
## it), wl (the water's level), half (the walkable half width), piers (m along
## the road), spans ([from, to, spring, crown] each), emp}]. A hash a world
## (index) of its bridges' stretches by cells of BCELL m, planet-local, finds
## the one under a point (probe) in one look-up: the walker's floor (floor_at),
## its walls (push - the parapets, and the piers and abutments from below), the
## camera's and the bolts' hits (solid), the travellers' and donkeys' deck
## (deck_top), the ship kept from landing on one (near). Their meshes are made on
## the road pieces' workers (piece) - arrays and LOD chains there, the mesh on
## the main thread.

const CLEAR_SEA := 4.5          # m: the deck's top over the sea (its waves ~0.7 m at most)
const CLEAR_RIVER := 3.2        # m: over a river or a lake
const MAX_RISE := 16.0          # m: over a gorge, level with its banks - up to this over the water
const RAMP := 0.075             # the approaches' grade
const WET_DEPTH := 0.15         # m of water over the ground for a road point to need the bridge
const MERGE_GAP := 14           # points: wet stretches this close are one bridge (an islet, a sandbar)
const SLAB := 0.8               # m: the deck's thickness
const PARAPET := 1.0            # m: the parapets' height over the deck
const PARA_T := 0.45            # m: their thickness
const KERB := 0.9               # m: stone deck beyond the road's half width (to the parapet)
const SPAN := 24.0              # m between piers (about)
const PIER_H := 1.1             # m: a pier's half thickness along the road
const CUT := 1.4                # m: a cutwater's reach out from the side
const OPEN := 1.6               # m of clear height under the slab for an arch (less: a solid embankment)
const LAMP_PIERS := 2           # a lamp each side on every this many piers
const BCELL := 16.0             # m: the hash's cells
const STEP_UP := 0.6            # m: a deck this far above the feet is stepped onto
const ROWS_PER_PT := 2          # mesh rows a road point (1.5 m apart)


# --- Where (on the network's worker) ------------------------------------------------------

## Every road's bridges worked out (into road["bridges"]); `towns` for whose they are.
static func make(shape: PlanetShape, roads: Array, towns: Array) -> void:
	for r in roads:
		if CosmosRoads._quit:   # (leaving: given up - not waited out)
			r["bridges"] = []
			continue
		var emp := ""
		var a := int(r.get("a", -1))
		if a >= 0 and a < towns.size():
			emp = str((towns[a] as Dictionary).get("empire", ""))
		r["bridges"] = of_road(shape, r, emp)


## The water's level at `d` (m above the radius), or -INF: the sea's, a lake's, a river's (lava: the sea's).
static func water_at(shape: PlanetShape, d: Vector3) -> float:
	var lv := -INF
	if shape.sea == 1:
		lv = shape.water_level(d)
	elif shape.sea == 3:
		lv = 0.0
	return lv


## A road's bridges (see the header).
static func of_road(shape: PlanetShape, road: Dictionary, emp: String) -> Array:
	var out: Array = []
	if shape.sea != 1 and shape.sea != 3:
		return out
	var pts: PackedVector3Array = road["pts"]
	var cum: PackedFloat32Array = road["cum"]
	var dr: Vector2i = road.get("drawn", Vector2i(0, pts.size() - 1))
	var n := dr.y - dr.x + 1
	if n < 3:
		return out
	var G := PackedFloat32Array()
	var Wl := PackedFloat32Array()
	G.resize(n)
	Wl.resize(n)
	var wet := PackedByteArray()
	wet.resize(n)
	var any := false
	for j in n:
		var d := pts[dr.x + j]
		G[j] = shape.height(d)
		Wl[j] = water_at(shape, d)
		if Wl[j] > -INF and G[j] < Wl[j] - WET_DEPTH:
			wet[j] = 1
			any = true
	if not any:
		return out
	# The wet stretches (near ones one).
	var runs: Array = []
	var j0 := -1
	for j in n:
		if wet[j]:
			if j0 < 0:
				j0 = j
		elif j0 >= 0:
			runs.append([j0, j - 1])
			j0 = -1
	if j0 >= 0:
		runs.append([j0, n - 1])
	var merged: Array = []
	for rn in runs:
		if not merged.is_empty() and int(rn[0]) - int(merged[-1][1]) <= MERGE_GAP:
			merged[-1][1] = rn[1]
		else:
			merged.append(rn)
	# The deck over each, and its approaches down to the banks.
	var H := PackedFloat32Array()
	H.resize(n)
	H.fill(-INF)
	var S := func(j: int) -> float: return cum[dr.x + j]
	for rn in merged:
		var a: int = rn[0]
		var b: int = rn[1]
		var lv := -INF
		for j in range(a, b + 1):
			lv = maxf(lv, Wl[j])
		var clear := CLEAR_SEA if lv < 0.05 else CLEAR_RIVER
		var ga := G[maxi(a - 1, 0)]
		var gb := G[mini(b + 1, n - 1)]
		for k in range(1, 7):
			ga = maxf(ga, G[maxi(a - k, 0)])
			gb = maxf(gb, G[mini(b + k, n - 1)])
		var ea := clampf(ga, lv + clear, lv + MAX_RISE)
		var eb := clampf(gb, lv + clear, lv + MAX_RISE)
		var sa: float = S.call(a)
		var sb: float = S.call(b)
		for j in range(a, b + 1):
			var t := (float(S.call(j)) - sa) / maxf(sb - sa, 0.01)
			H[j] = maxf(H[j], lerpf(ea, eb, t))
		for side in [-1, 1]:
			var jr: int = a - 1 if side < 0 else b + 1
			var e := ea if side < 0 else eb
			var se := sa if side < 0 else sb
			while jr >= 0 and jr < n:
				var target := e - RAMP * absf(float(S.call(jr)) - se)
				if G[jr] >= target - 0.05:
					H[jr] = maxf(H[jr], G[jr] + 0.05)   # (on the bank: the deck meets the ground)
					break
				H[jr] = maxf(H[jr], target)
				jr += side
	# Each bridge: smoothed (no kinks where a ramp meets the level), never under the ground or near the water.
	var jj := 0
	while jj < n:
		if H[jj] == -INF:
			jj += 1
			continue
		var a := jj
		while jj < n and H[jj] > -INF:
			jj += 1
		var b := jj - 1
		if b - a < 2:
			continue
		for it in 4:
			var prev := H.duplicate()
			for q in range(a + 1, b):
				H[q] = prev[q - 1] * 0.25 + prev[q] * 0.5 + prev[q + 1] * 0.25
		var lvmax := -INF
		var rise := 0.0
		for q in range(a, b + 1):
			H[q] = maxf(H[q], G[q] + 0.05)
			if Wl[q] > -INF:
				lvmax = maxf(lvmax, Wl[q])
				if wet[q]:
					H[q] = maxf(H[q], Wl[q] + 1.5)
			rise = maxf(rise, H[q] - G[q])
		if rise < 1.0:
			continue
		var br := {"i0": dr.x + a, "i1": dr.x + b, "s0": float(S.call(a)), "h": H.slice(a, b + 1), "g": G.slice(a, b + 1),
			"wl": lvmax, "half": float(road.get("width", 4.4)) * 0.5 + KERB, "emp": emp}
		_piers(br, cum)
		out.append(br)
	return out


## Its piers and arches: where there's room under the slab (OPEN), piers about
## SPAN apart (the open stretch's ends among them), each span an arch from its
## spring (just over the water, or the ground) up to its crown under the deck.
static func _piers(br: Dictionary, cum: PackedFloat32Array) -> void:
	var h: PackedFloat32Array = br["h"]
	var g: PackedFloat32Array = br["g"]
	var i0: int = br["i0"]
	var wl: float = br["wl"]
	var piers := PackedFloat32Array()
	var spans := PackedFloat32Array()
	var q := 0
	var n := h.size()
	while q < n:
		if h[q] - SLAB - g[q] <= OPEN:
			q += 1
			continue
		var a := q
		while q < n and h[q] - SLAB - g[q] > OPEN:
			q += 1
		var b := q - 1
		var sa := cum[i0 + maxi(a - 1, 0)]
		var sb := cum[i0 + mini(b + 1, n - 1)]
		if sb - sa < 8.0:
			continue
		var m := maxi(1, roundi((sb - sa) / SPAN))
		for k in m + 1:
			piers.append(sa + (sb - sa) * k / m)
		for k in m:
			var p0 := sa + (sb - sa) * k / m
			var p1 := sa + (sb - sa) * (k + 1) / m
			var lo := INF
			var base := -INF
			for qq in range(a, b + 1):
				var s := cum[i0 + qq]
				if s >= p0 - 1.5 and s <= p1 + 1.5:
					lo = minf(lo, h[qq])
					base = maxf(base, wl if wl > -INF else g[qq])
			if lo == INF:
				lo = h[a]
				base = g[a]
			var crown := lo - SLAB - 0.45
			var spring := maxf(base + 0.7, crown - (p1 - p0 - 2.0 * PIER_H) * 0.5)
			if crown - spring < 0.6:
				spring = crown   # (too low for an arch: a flat lintel)
			spans.append_array([p0, p1, spring, crown])
	br["piers"] = piers
	br["spans"] = spans


## The deck's top `s` m along its road (interpolated), or -INF off it.
static func deck_h(br: Dictionary, cum: PackedFloat32Array, s: float) -> float:
	var i0: int = br["i0"]
	var i1: int = br["i1"]
	if s < cum[i0] or s > cum[i1]:
		return -INF
	var h: PackedFloat32Array = br["h"]
	var i := i0 + clampi(int((s - cum[i0]) / 3.0), 0, i1 - i0)
	while i > i0 and cum[i] > s:
		i -= 1
	while i < i1 - 1 and cum[i + 1] < s:
		i += 1
	if i >= i1:
		return h[i1 - i0]
	var seg := cum[i + 1] - cum[i]
	return lerpf(h[i - i0], h[i + 1 - i0], (s - cum[i]) / seg if seg > 0.0 else 0.0)


## The structure's underside `s` m along (m above the radius) where the ground is `gr`:
## an arch's curve, a pier's foot (sunk into the bed), the embankment's (into the ground).
static func under(br: Dictionary, s: float, gr: float, top: float) -> float:
	var piers: PackedFloat32Array = br["piers"]
	for sp in piers:
		if absf(s - sp) < PIER_H:
			return gr - 1.0
	var spans: PackedFloat32Array = br["spans"]
	var u := gr - 0.4
	for k in range(0, spans.size(), 4):
		var p0 := spans[k]
		var p1 := spans[k + 1]
		if s >= p0 and s <= p1:
			var L := maxf(p1 - p0 - 2.0 * PIER_H, 0.1)
			var t := clampf((s - p0 - PIER_H) / L, 0.0, 1.0)
			var arc := spans[k + 2] + (spans[k + 3] - spans[k + 2]) * sqrt(maxf(0.0, 1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0)))
			u = maxf(arc, gr - 0.4)
			break
	return minf(u, top - SLAB * 0.6)


## The ground under it `s` m along (the stored heights, interpolated).
static func ground_h(br: Dictionary, cum: PackedFloat32Array, s: float) -> float:
	var i0: int = br["i0"]
	var g: PackedFloat32Array = br["g"]
	var f := 0.0
	var i := i0
	while i < int(br["i1"]) and cum[i + 1] < s:
		i += 1
	var seg := cum[mini(i + 1, int(br["i1"]))] - cum[i]
	f = clampf((s - cum[i]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
	return lerpf(g[i - i0], g[mini(i + 1 - i0, g.size() - 1)], f)


# --- Found again (any thread: the hash) ---------------------------------------------------

## A world's bridges' stretches by where they are: {Vector3i cell: [road, bridge, point, ...]}
## - each stretch in every cell its footprint (and a margin) touches.
static func index(roads: Array, radius: float) -> Dictionary:
	var hsh := {}
	for k in roads.size():
		if CosmosRoads._quit:
			return {}
		var bl: Array = roads[k].get("bridges", [])
		var pts: PackedVector3Array = roads[k]["pts"]
		for b in bl.size():
			var br: Dictionary = bl[b]
			var pad: float = float(br["half"]) + PARA_T + CUT + 2.0
			for i in range(int(br["i0"]), int(br["i1"])):
				var A := pts[i] * radius
				var B := pts[i + 1] * radius
				var lo := ((A.min(B) - Vector3.ONE * pad) / BCELL).floor()
				var hi := ((A.max(B) + Vector3.ONE * pad) / BCELL).floor()
				for x in range(int(lo.x), int(hi.x) + 1):
					for y in range(int(lo.y), int(hi.y) + 1):
						for z in range(int(lo.z), int(hi.z) + 1):
							var c := Vector3i(x, y, z)
							var a = hsh.get(c)
							if a == null:
								a = []
								hsh[c] = a
							(a as Array).append_array([k, b, i])
	return hsh


## The bridge under planet-local `local`: [bridge, s (m along its road), x (m to the
## right of its middle), deck top there, along (unit, planet-local), side (unit)], or [].
static func probe(roads: Array, hsh: Dictionary, radius: float, local: Vector3) -> Array:
	if hsh.is_empty():
		return []
	var d := local.normalized()
	var p := d * radius
	var a = hsh.get(Vector3i((p / BCELL).floor()))
	if a == null:
		return []
	var best: Array = []
	var bd := INF
	var ai: Array = a
	for m in range(0, ai.size(), 3):
		var road: Dictionary = roads[ai[m]]
		var br: Dictionary = road["bridges"][ai[m + 1]]
		var i: int = ai[m + 2]
		var pts: PackedVector3Array = road["pts"]
		var A := pts[i] * radius
		var B := pts[i + 1] * radius
		var ab := B - A
		var L2 := ab.length_squared()
		if L2 < 1e-6:
			continue
		var t := (p - A).dot(ab) / L2
		if (t < 0.0 and i == int(br["i0"])) or (t > 1.0 and i == int(br["i1"]) - 1):
			continue   # (past its end: off it)
		t = clampf(t, 0.0, 1.0)
		var off := p - (A + ab * t)
		var dist := off.length()
		if dist < bd:
			var side := pts[i].cross(ab).normalized()
			var cum: PackedFloat32Array = road["cum"]
			var s := cum[i] + (cum[i + 1] - cum[i]) * t
			var hh: PackedFloat32Array = br["h"]
			var top := lerpf(hh[i - int(br["i0"])], hh[i + 1 - int(br["i0"])], t)
			bd = dist
			best = [br, s, off.dot(side), top, ab / sqrt(L2), side, cum]
	return best


## The floor a body stands on at `local` (m above the radius): the deck, a parapet's
## top - if its feet are no more than STEP_UP under it (under the bridge: none) - or -INF.
static func floor_at(pr: Array, y: float) -> float:
	if pr.is_empty():
		return -INF
	var ax := absf(float(pr[2]))
	var W: float = pr[0]["half"]
	if ax > W + PARA_T:
		return -INF
	var top: float = float(pr[3]) + (PARAPET if ax > W else 0.0)
	return top if y >= top - STEP_UP else -INF


## Its walls: how far (planet-local) to move a body of radius `r` whose feet are
## at height `y` - off a parapet (in, to the deck - or out, if it came at it from
## the outside), out of the abutments and the piers from below.
static func push(pr: Array, y: float, r: float) -> Vector3:
	if pr.is_empty():
		return Vector3.ZERO
	var br: Dictionary = pr[0]
	var x: float = pr[2]
	var ax := absf(x)
	var W: float = br["half"]
	var Wo := W + PARA_T
	if ax > Wo + r:
		return Vector3.ZERO
	var top: float = pr[3]
	var side: Vector3 = pr[5]
	var sg := 1.0 if x >= 0.0 else -1.0
	if y >= top + PARAPET - 0.05:
		return Vector3.ZERO   # (over the parapets: free - jumped up onto one)
	if y >= top - 0.35:   # (on the deck's level: the parapets)
		if ax < W - r:
			return Vector3.ZERO
		if ax < (W + Wo) * 0.5:
			return side * sg * ((W - r) - ax)
		return side * sg * (Wo + r - ax)
	# Under the deck: in the solid part (an abutment, a pier)?
	var cum: PackedFloat32Array = pr[6]
	var s: float = pr[1]
	var gr := ground_h(br, cum, s)
	var u := under(br, s, gr, top)
	var in_pier := -1.0
	for sp in (br["piers"] as PackedFloat32Array):
		if absf(s - sp) < PIER_H + r:
			in_pier = sp
	if y + 0.1 < u and in_pier < 0.0:
		return Vector3.ZERO   # (under an arch)
	var out := side * sg * (Wo + r - ax)
	if in_pier >= 0.0:
		var along: Vector3 = pr[4]
		var ds := PIER_H + r - absf(s - in_pier)
		if ds < Wo + r - ax:
			out = along * (1.0 if s >= in_pier else -1.0) * ds
	return out


## Whether `local` (its height `y`) is in its stone (`pad` m of margin): the camera, bolts.
static func solid(pr: Array, y: float, pad: float) -> bool:
	if pr.is_empty():
		return false
	var br: Dictionary = pr[0]
	var ax := absf(float(pr[2]))
	var W: float = br["half"]
	if ax > W + PARA_T + pad:
		return false
	var top: float = pr[3]
	if y > top + PARAPET + pad:
		return false
	if y >= top - pad:
		return ax > W - pad   # (the parapets)
	if y > top - SLAB - pad:
		return true   # (the deck)
	var cum: PackedFloat32Array = pr[6]
	var s: float = pr[1]
	return y > under(br, s, ground_h(br, cum, s), top) - pad


# --- Its mesh (on a road piece's worker) --------------------------------------------------

## The building shader's slots (CosmosTown's).
const _STONE := 1
const _PALE := 2
const _RED := 3
const _FRESCO := 5
const _TRIM := 6
const _HORNS := 8
## Each empire's: [its walls' stone, its parapets', their coping, the frieze band on the deck's edge (-1 none), railings (Minoa)].
const LOOK := {
	"minoa": [_STONE, _STONE, _PALE, _FRESCO, true],
	"athens": [_STONE, _PALE, _PALE, _FRESCO, false],
	"sparta": [_STONE, _STONE, _RED, -1, false],
	"mycenae": [_STONE, _STONE, _TRIM, _FRESCO, false],
	"ionia": [_STONE, _PALE, _TRIM, _FRESCO, false],
	"cyclades": [_STONE, 0, _RED, -1, false],
	"": [_STONE, _STONE, _PALE, -1, false],
}


## A road's decks over its points i0..i1 - 1 (a piece's: its ribbon laid on them), -INF
## off them; [] if no bridge there.
static func decks(road: Dictionary, i0: int, i1: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for br: Dictionary in road.get("bridges", []):
		var a := maxi(int(br["i0"]), i0)
		var z := mini(int(br["i1"]), i1 - 1)
		if z < a:
			continue
		if out.is_empty():
			out.resize(i1 - i0)
			out.fill(-INF)
		var h: PackedFloat32Array = br["h"]
		for i in range(a, z + 1):
			out[i - i0] = h[i - int(br["i0"])]
	return out


## The bridges' parts on points i0..i1 of a road (its piece's: the same frame as its
## ribbon - `centre`, planet-local): [arrays, LOD chain, its basis, its lamps' lights (piece-local),
## their glows on the deck (TownLamps' pool arrays)] or [] if none there.
## `stop`: give up (the world left).
static func piece(shape: PlanetShape, road: Dictionary, i0: int, i1: int, centre: Vector3, stop: Array = [false]) -> Array:
	var bl: Array = road.get("bridges", [])
	if bl.is_empty():
		return []
	var pts: PackedVector3Array = road["pts"]
	var mid := pts[clampi((i0 + i1) / 2, 0, pts.size() - 1)]
	var fw := pts[mini((i0 + i1) / 2 + 1, pts.size() - 1)] - pts[maxi((i0 + i1) / 2 - 1, 0)]
	var up := mid.normalized()
	var xa := (fw - up * fw.dot(up)).cross(up).normalized()
	if xa.length() < 0.5:
		xa = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP).normalized()
	var basis := Basis(xa, up, xa.cross(up).normalized())
	var inv := basis.transposed()
	var b = CosmosTown.Builder.new()
	b.rng.seed = hash([i0, i1, int(road.get("a", 0)), int(road.get("b", 0))])
	var made := false
	var lamps: Array = []   # [[flame, the deck's spot under its light]...] (piece-local)
	for br: Dictionary in bl:
		if stop[0] or CosmosRoads._quit:
			return []
		var a := maxi(int(br["i0"]), i0)
		var z := mini(int(br["i1"]), i1 - 1)
		if z - a < 1:
			continue
		b.emp = str(br["emp"])
		_build(b, shape, road, br, a, z, centre, inv, lamps)
		made = true
	if not made or b.verts.is_empty() or CosmosRoads._quit:
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b.verts
	arr[Mesh.ARRAY_NORMAL] = b.norms
	arr[Mesh.ARRAY_COLOR] = b.cols
	arr[Mesh.ARRAY_INDEX] = b.idx
	var lit := PackedVector3Array()   # (its lamps' lights: just over each flame)
	var pools: Array = []
	for L in lamps:
		lit.append((L[0] as Vector3) + Vector3.UP * 0.3)
		pools.append([L[0], TownLamps.POST, (L[0] as Vector3) + Vector3.UP * 0.3, L[1]])
	return [arr, LodKit.lods(arr), basis, lit, TownLamps._pools(pools)]


## One bridge's points a..z: the swept section row by row (its walls, deck, parapets, the
## arches' and piers' undersides), its railings or coping, cutwaters, lamps.
static func _build(b, shape: PlanetShape, road: Dictionary, br: Dictionary, a: int, z: int, centre: Vector3, inv: Basis, lamps: Array) -> void:
	var R := shape.radius
	var pts: PackedVector3Array = road["pts"]
	var cum: PackedFloat32Array = road["cum"]
	var emp: String = br["emp"]
	var look: Array = LOOK.get(emp, LOOK[""])
	var W: float = br["half"]
	var Wo := W + PARA_T
	var rails: bool = look[4]
	var piers: PackedFloat32Array = br["piers"]
	# The rows: every 1.5 m, and each pier's faces twice (the arch's side, the pier's) - its vertical faces.
	var ss: Array = []   # [s, pier side: -1 outside / 1 in / 0 as it falls]
	var s_a := cum[a]
	var s_z := cum[z]
	for i in range(a, z + 1):
		for k in (ROWS_PER_PT if i < z else 1):
			var s := lerpf(cum[i], cum[mini(i + 1, z)], float(k) / ROWS_PER_PT)
			var near_face := false
			for sp in piers:
				if absf(absf(s - sp) - PIER_H) < 0.35:
					near_face = true
			if not near_face:
				ss.append([s, 0])
	for sp in piers:
		for f in [sp - PIER_H, sp + PIER_H]:
			if f > s_a + 0.05 and f < s_z - 0.05:
				var into := 1 if f < sp else -1   # (going on along: into the pier at its near face, out at its far one)
				ss.append([f, -into])
				ss.append([f + 0.0001, into])
	ss.sort_custom(func(p, q): return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
	# Each row's frame: its middle on the deck, across (x), up; the deck's top, the underside.
	var rows: Array = []
	for e in ss:
		if CosmosRoads._quit:
			return
		var s: float = e[0]
		var i := a
		while i < z - 1 and cum[i + 1] < s:
			i += 1
		var seg := cum[i + 1] - cum[i]
		var t := clampf((s - cum[i]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
		var d := pts[i].slerp(pts[i + 1], t).normalized()
		var fwd := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		var side := d.cross(fwd).normalized()
		var top := lerpf((br["h"] as PackedFloat32Array)[i - int(br["i0"])], (br["h"] as PackedFloat32Array)[i + 1 - int(br["i0"])], t)
		var gr := shape.height(d)
		var u := gr - 1.0 if int(e[1]) == 1 else under(br, s, gr, top)   # (a face's pair: the pier's foot, the arch's spring)
		rows.append({"s": s, "d": d, "x": inv * side, "u3": inv * d, "c": inv * (d * (R + top) - centre), "top": top, "u": u, "g": gr})
	var P := func(row: Dictionary, x: float, y: float) -> Vector3:
		return (row["c"] as Vector3) + (row["x"] as Vector3) * x + (row["u3"] as Vector3) * (y - float(row["top"]))
	var band: int = look[3]
	for k in rows.size() - 1:
		var r0: Dictionary = rows[k]
		var r1: Dictionary = rows[k + 1]
		var same := float(r1["s"]) - float(r0["s"]) < 0.01
		var t0: float = r0["top"]
		var t1: float = r1["top"]
		var upn := ((r0["u3"] as Vector3) + (r1["u3"] as Vector3)).normalized()
		var xn := ((r0["x"] as Vector3) + (r1["x"] as Vector3)).normalized()
		if same:   # (a pier's face: across, from its foot up to the arch's spring)
			var lo := minf(float(r0["u"]), float(r1["u"]))
			var hi := maxf(float(r0["u"]), float(r1["u"]))
			if hi - lo > 0.01:
				var nrm := upn.cross(xn).normalized() * (1.0 if float(r0["u"]) > float(r1["u"]) else -1.0)   # (up x across: back along the road - the face into the pier looks back)
				_q(b, P.call(r0, -Wo, lo), P.call(r0, Wo, lo), P.call(r0, Wo, hi), P.call(r0, -Wo, hi), nrm, look[0], lo)
			continue
		var below_g := float(r0["u"]) < float(r0["g"]) - 0.35 and float(r1["u"]) < float(r1["g"]) - 0.35   # (underground: the embankment's foot - no underside to see)
		for sg in [-1.0, 1.0]:
			var on: Vector3 = xn * sg
			var ys: Array = [[r0["u"], r1["u"]], [t0 - SLAB, t1 - SLAB]]
			if band >= 0:
				ys.append([t0 - 0.5, t1 - 0.5])
			ys.append([t0, t1])
			for m in range(1, ys.size()):   # (each band's foot no lower than the last's top: a low underside)
				ys[m] = [maxf(float(ys[m][0]), float(ys[m - 1][0])), maxf(float(ys[m][1]), float(ys[m - 1][1]))]
			var slots: Array = [look[0], look[0] if band < 0 else _STONE]
			if band >= 0:
				slots.append(band)
			for m in ys.size() - 1:   # (its outer face in bands: the wall or pier, the slab's edge, the frieze)
				var ya: Array = ys[m]
				var yb: Array = ys[m + 1]
				if float(yb[0]) - float(ya[0]) < 0.01 and float(yb[1]) - float(ya[1]) < 0.01:
					continue
				_q(b, P.call(r0, sg * Wo, ya[0]), P.call(r1, sg * Wo, ya[1]), P.call(r1, sg * Wo, yb[1]), P.call(r0, sg * Wo, yb[0]), on, slots[m], minf(float(ya[0]), float(ya[1])))
			if rails:   # (a low stone kerb: the railings' posts on it)
				var kh := 0.32
				_q(b, P.call(r0, sg * Wo, t0), P.call(r1, sg * Wo, t1), P.call(r1, sg * Wo, t1 + kh), P.call(r0, sg * Wo, t0 + kh), on, look[0], t0)
				_q(b, P.call(r0, sg * Wo, t0 + kh), P.call(r1, sg * Wo, t1 + kh), P.call(r1, sg * W, t1 + kh), P.call(r0, sg * W, t0 + kh), upn, look[2], t0 + kh)
				_q(b, P.call(r0, sg * W, t0 + kh), P.call(r1, sg * W, t1 + kh), P.call(r1, sg * W, t1), P.call(r0, sg * W, t0), -on, look[0], t0)
			else:   # (a solid parapet, its coping)
				_q(b, P.call(r0, sg * Wo, t0), P.call(r1, sg * Wo, t1), P.call(r1, sg * Wo, t1 + PARAPET), P.call(r0, sg * Wo, t0 + PARAPET), on, look[1], t0)
				_q(b, P.call(r0, sg * (Wo + 0.06), t0 + PARAPET), P.call(r1, sg * (Wo + 0.06), t1 + PARAPET), P.call(r1, sg * (W - 0.06), t1 + PARAPET), P.call(r0, sg * (W - 0.06), t0 + PARAPET), upn, look[2], t0 + PARAPET)
				_q(b, P.call(r0, sg * W, t0 + PARAPET), P.call(r1, sg * W, t1 + PARAPET), P.call(r1, sg * W, t1), P.call(r0, sg * W, t0), -on, look[1], t0)
		# The deck's stone (the road's ribbon over its middle) and the underside.
		_q(b, P.call(r0, -W, t0 - 0.02), P.call(r0, W, t0 - 0.02), P.call(r1, W, t1 - 0.02), P.call(r1, -W, t1 - 0.02), upn, look[0], t0)
		if not below_g:
			_q(b, P.call(r0, -Wo, r0["u"]), P.call(r1, -Wo, r1["u"]), P.call(r1, Wo, r1["u"]), P.call(r0, Wo, r0["u"]), -upn, look[0], float(r0["u"]))
	# Its ends (where it meets the bank): the section closed.
	for e in [[rows[0], -1.0, int(br["i0"]) >= a], [rows[rows.size() - 1], 1.0, int(br["i1"]) <= z]]:
		var row: Dictionary = e[0]
		if not e[2]:
			continue
		var fn: Vector3 = (row["u3"] as Vector3).cross(row["x"] as Vector3).normalized() * -float(e[1])
		var t: float = row["top"]
		_q(b, P.call(row, -Wo, row["u"]), P.call(row, Wo, row["u"]), P.call(row, Wo, t + (0.32 if rails else PARAPET)), P.call(row, -Wo, t + (0.32 if rails else PARAPET)), fn, look[0], float(row["u"]))
	# Railings (Minoa): red timber on stone posts, every road point; horns over the piers.
	if rails:
		var prev := {}
		for i in range(a, z + 1):
			var row := _row_at(shape, road, br, i, 0.0, centre, inv)
			for sg in [-1.0, 1.0] if (i < z or z == int(br["i1"])) else []:   # (the piece's last point: the next piece's first post)
				var foot: Vector3 = P.call(row, sg * (W + PARA_T * 0.5), float(row["top"]) + 0.32)
				_obox(b, foot, row["u3"], row["x"], 0.22, 0.22, 0.85, _STONE)
			if not prev.is_empty():
				for sg in [-1.0, 1.0]:
					for hy in [0.62, 1.0]:
						var p0: Vector3 = P.call(prev, sg * (W + PARA_T * 0.5), float(prev["top"]) + hy)
						var p1: Vector3 = P.call(row, sg * (W + PARA_T * 0.5), float(row["top"]) + hy)
						_rail(b, p0, p1, row["u3"], 0.12, 0.13, _RED)
			prev = row
	# Over each pier: cutwaters in the water, lamps on every other one; lamps at the bridge's ends.
	var lamp_n := 0
	for sp in piers:
		if sp < s_a or sp > s_z:
			lamp_n += 1
			continue
		var row := _row_at_s(shape, road, br, sp, centre, inv)
		var t: float = row["top"]
		var gr: float = row["g"]
		var wet_pier := float(br["wl"]) > -INF and gr < float(br["wl"]) and t - SLAB - gr > OPEN
		if wet_pier:
			var fwl: Vector3 = (row["u3"] as Vector3).cross(row["x"] as Vector3).normalized()
			for sg in [-1.0, 1.0]:
				_cutwater(b, P, row, sg, Wo, fwl, gr - 1.0, t - SLAB, look[0], _STONE)
				if rails:
					TownLamps._little_horns(b, P.call(row, sg * (W + PARA_T * 0.5), t + 1.12))
				if lamp_n % LAMP_PIERS == 0:
					var foot: Vector3 = P.call(row, sg * (Wo + CUT * 0.5), t - SLAB + 0.02)
					lamps.append([_lamp(b, foot, emp), P.call(row, sg * (W - 2.0), t)])
		lamp_n += 1
	for e in [[int(br["i0"]), 1], [int(br["i1"]), -1]]:
		var ie: int = e[0]
		if ie < a or ie > z:
			continue
		var row := _row_at(shape, road, br, ie, 0.0, centre, inv)
		for sg in [-1.0, 1.0]:
			var post_at: Vector3 = P.call(row, sg * (Wo + 0.55), float(row["top"]))
			var g2 := shape.height(((row["d"] as Vector3) * R + _side_of(road, ie) * sg * (Wo + 0.55)).normalized())
			post_at += (row["u3"] as Vector3) * (g2 - float(row["top"]))
			lamps.append([_lamp(b, post_at, emp), P.call(row, sg * (W - 2.0), float(row["top"]))])


static func _side_of(road: Dictionary, i: int) -> Vector3:
	var pts: PackedVector3Array = road["pts"]
	var fwd := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
	return pts[i].cross(fwd).normalized()


## A row's frame at road point i (+ t of the way to the next).
static func _row_at(shape: PlanetShape, road: Dictionary, br: Dictionary, i: int, t: float, centre: Vector3, inv: Basis) -> Dictionary:
	var pts: PackedVector3Array = road["pts"]
	var ia := clampi(i, int(br["i0"]), int(br["i1"]))
	var ib := mini(ia + 1, int(br["i1"]))
	var d := pts[ia].slerp(pts[ib], t).normalized() if ib != ia else pts[ia]
	var hh: PackedFloat32Array = br["h"]
	var top := lerpf(hh[ia - int(br["i0"])], hh[ib - int(br["i0"])], t)
	var R := shape.radius
	return {"d": d, "x": inv * _side_of(road, ia), "u3": inv * d, "c": inv * (d * (R + top) - centre), "top": top, "g": shape.height(d)}


static func _row_at_s(shape: PlanetShape, road: Dictionary, br: Dictionary, s: float, centre: Vector3, inv: Basis) -> Dictionary:
	var cum: PackedFloat32Array = road["cum"]
	var i := int(br["i0"])
	while i < int(br["i1"]) - 1 and cum[i + 1] < s:
		i += 1
	var seg := cum[i + 1] - cum[i]
	return _row_at(shape, road, br, i, clampf((s - cum[i]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0, centre, inv)


## A quad in the builder (its slot; `y0` its foot's height - the frieze's bands).
static func _q(b, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, slot: int, y0: float) -> void:
	b.quad(p0, p1, p2, p3, n, Color(slot / 255.0, b.rng.randf(), fposmod(y0, 8.0) / 8.0))


## A box standing on `foot`: `w` across (along `xv`), `l` along the road, `h` up (`uv`).
static func _obox(b, foot: Vector3, uv: Vector3, xv: Vector3, w: float, l: float, h: float, slot: int) -> void:
	var zv := xv.cross(uv).normalized()
	var c := [foot - xv * w * 0.5 - zv * l * 0.5, foot + xv * w * 0.5 - zv * l * 0.5, foot + xv * w * 0.5 + zv * l * 0.5, foot - xv * w * 0.5 + zv * l * 0.5]
	var t := [c[0] + uv * h, c[1] + uv * h, c[2] + uv * h, c[3] + uv * h]
	var y0 := foot.dot(uv)
	_q(b, t[0], t[1], t[2], t[3], uv, slot, y0)
	_q(b, c[0], c[1], t[1], t[0], -zv, slot, y0)
	_q(b, c[1], c[2], t[2], t[1], xv, slot, y0)
	_q(b, c[2], c[3], t[3], t[2], zv, slot, y0)
	_q(b, c[3], c[0], t[0], t[3], -xv, slot, y0)


## A rail from p0 to p1 (its centre line): `w` wide, `h` deep.
static func _rail(b, p0: Vector3, p1: Vector3, uv: Vector3, w: float, h: float, slot: int) -> void:
	var along := p1 - p0
	if along.length() < 0.01:
		return
	var xv := along.cross(uv).normalized()
	var u2 := xv.cross(along).normalized()
	var o := [xv * w * 0.5 + u2 * h * 0.5, -xv * w * 0.5 + u2 * h * 0.5, -xv * w * 0.5 - u2 * h * 0.5, xv * w * 0.5 - u2 * h * 0.5]
	var ns := [u2, -xv, -u2, xv]   # (each face's: between corners k and k + 1)
	for k in 4:
		var oa: Vector3 = o[k]
		var ob: Vector3 = o[(k + 1) % 4]
		var nn: Vector3 = ns[k]
		_q(b, p0 + oa, p1 + oa, p1 + ob, p0 + ob, nn, slot, p0.dot(uv))


## A pier's cutwater on side `sg`: a wedge out of its face (CUT m), from `y0` up to `y1`,
## its top a little platform (a lamp's place).
static func _cutwater(b, P: Callable, row: Dictionary, sg: float, Wo: float, fwl: Vector3, y0: float, y1: float, slot: int, cap: int) -> void:
	var xv: Vector3 = row["x"]
	var uv: Vector3 = row["u3"]
	var base0: Vector3 = P.call(row, sg * Wo, y0)
	var hgt := y1 - y0
	var pa := base0 - fwl * PIER_H
	var pb := base0 + fwl * PIER_H
	var pc := base0 + xv * sg * CUT
	var ta := pa + uv * hgt
	var tb := pb + uv * hgt
	var tc := pc + uv * hgt
	var na := ((pc - pa).cross(uv)).normalized()
	if na.dot(xv * sg) < 0.0:
		na = -na
	var nb := ((pc - pb).cross(uv)).normalized()
	if nb.dot(xv * sg) < 0.0:
		nb = -nb
	_q(b, pa, pc, tc, ta, na, slot, y0)
	_q(b, pc, pb, tb, tc, nb, slot, y0)
	# (its cap: a little triangle platform)
	var base: int = b.verts.size()
	b.verts.append_array([ta, tb, tc])
	b.norms.append_array([uv, uv, uv])
	var col := Color(cap / 255.0, b.rng.randf(), fposmod(y1, 8.0) / 8.0)
	b.cols.append_array([col, col, col])
	if (tb - ta).cross(tc - ta).dot(uv) > 0.0:   # (Godot's front faces wind clockwise)
		b.idx.append_array([base, base + 2, base + 1])
	else:
		b.idx.append_array([base, base + 1, base + 2])


## A lamp post on `foot` (the empire's: TownLamps').
static func _lamp(b, foot: Vector3, emp: String) -> Vector3:
	return TownLamps.post(b, foot, "" if emp == "minoa" else emp, 0)
