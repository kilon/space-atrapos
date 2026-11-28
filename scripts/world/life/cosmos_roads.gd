class_name CosmosRoads
extends Node3D
## The roads between a world's towns (its cities and villages: CosmosTown.sites)
## in the 3D game. A network for each inhabited world, made once on a worker as
## you come near it (network): the towns joined by a minimum spanning tree of
## the shortest ways between them, plus a few extra links where they save a
## long way round; each way found by a path search over the ground (path: A* on
## a band of cells along the great circle between the two towns - steep ground
## dear, the sea and lava closed, the ice of a frozen sea dear), smoothed and
## laid out a point every STEP m (unit directions from the planet's middle).
## Drawn as ribbons draped on the ground (road.gdshader: packed earth with ruts,
## the roads out of a city paved), a piece of CHUNK_PTS points a mesh, built on
## a worker when you're within NEAR of it and let go when you're far. Nothing
## grows on them (PlanetShape.set_bare). CosmosCaravans walks them.
##   CosmosRoads.of(cosmos).roads_of(planet)   # [] until made: [{a, b, pts, cum, length, pave}]
##   CosmosRoads.point(road, s)               # unit direction s m along it

const STEP := 3.0               # m between a road's points
const SUB := 2                  # a piece's mesh rows a point (1.5 m apart: the ground's finest quads are ~1.4 m)
const CELL := 34.0              # m: the path search's cells
const WIDTH := 4.4              # m: the road across
const CHUNK_PTS := 64           # points a mesh piece (~190 m)
const BARE_PTS := 128           # points a bare-ground entry (no plants on it)
const NEAR := 1100.0            # m: a piece built within this, let go past 1.4 x
const PAVED := 260.0             # m out of a city its roads are paved
const MAX_LINK := 7000.0        # m: towns further apart get no road of their own (unless it's the only way to join them)
const SHADER := preload("res://shaders/world/road.gdshader")
const ROAD_CLASS := "res://scripts/world/life/cosmos_roads.gd"

static var _cache := {}         # planet record id -> its roads (made once a session)
static var _mats := {}          # planet record id -> its ShaderMaterial

var cosmos: Node
var _jobs := {}                 # CosmosPlanet -> [job id, {"r": its roads}] (its network being made)
static var _quit := false       # (leaving: the searches on the workers stop where they are - not waited out)
var _pieces := {}               # "pid:road:piece" -> MeshInstance3D, or [job id, holder] while being made
var _t := 0.0


## The Cosmos's roads (made, as its child, the first time it's asked for).
static func of(c: Node) -> CosmosRoads:
	var n := c.get_node_or_null("Roads") as CosmosRoads
	if n == null:
		n = load(ROAD_CLASS).new()
		n.name = "Roads"
		n.cosmos = c
		c.add_child(n)
	return n


## A planet's roads once they're made: [{a, b, pts, cum, length, pave}], else [].
func roads_of(pl: CosmosPlanet) -> Array:
	if pl == null:
		return []
	return _cache.get(_pid(pl), [])


static func _pid(pl: CosmosPlanet) -> String:
	return "%s:%d" % [str(pl.rec.get("id", pl.name)), int(pl.rec.get("seed", 0))]


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		_poll_jobs()
		return
	_t = 0.0
	_poll_jobs()
	if cosmos == null or not cosmos.get("built"):
		return
	var f: Node3D = cosmos.focus()
	if f == null:
		return
	for pl: CosmosPlanet in cosmos.planets:
		if pl.towns.size() < 2:
			continue
		var d := pl.global_position.distance_to(f.global_position) - pl.radius
		var pid := _pid(pl)
		if d < 9000.0 and not _cache.has(pid) and not _jobs.has(pl):
			var sh := pl.shape
			var towns: Array = pl.towns.duplicate(true)
			var holder := {}
			_jobs[pl] = [Jobs.add(func(): holder["r"] = network(sh, towns), false, "roads"), holder]
		if _cache.has(pid):
			_pieces_near(pl, f.global_position - pl.global_position, d < NEAR * 2.0)


func _poll_jobs() -> void:
	for pl in _jobs.keys():
		var job: Array = _jobs[pl]
		if not Jobs.done(job[0]):
			continue
		Jobs.wait(job[0])
		_jobs.erase(pl)
		if not is_instance_valid(pl):
			continue
		var roads: Array = job[1].get("r", [])
		_cache[_pid(pl)] = roads
		_bare(pl, roads)


## No plants or boulders on its roads (and the ground near you redone without them).
func _bare(pl: CosmosPlanet, roads: Array) -> void:
	var f: Node3D = cosmos.focus() if cosmos else null
	var here := f.global_position - pl.global_position if f else Vector3.INF
	var c := cos((WIDTH * 0.5 + 1.6) / pl.radius)
	for k in roads.size():
		var pts: PackedVector3Array = roads[k]["pts"]
		var i0 := 0
		while i0 < pts.size():
			var dirs := PackedVector3Array()
			var coss := PackedFloat32Array()
			for i in range(i0, mini(i0 + BARE_PTS, pts.size()), 2):
				dirs.append(pts[i])
				coss.append(c)
			pl.shape.set_bare("road:%d:%d" % [k, i0], dirs, coss)
			var mid: Vector3 = pts[mini(i0 + BARE_PTS / 2, pts.size() - 1)] * pl.radius
			if here != Vector3.INF and mid.distance_to(here) < 1500.0 and pl.has_method("_rebuild_near"):
				pl._rebuild_near(mid, BARE_PTS * STEP * 0.6)
			i0 += BARE_PTS


## Its road pieces near `here` (planet-local) built, far ones let go.
func _pieces_near(pl: CosmosPlanet, here: Vector3, near_planet: bool) -> void:
	var pid := _pid(pl)
	var roads: Array = _cache[pid]
	var R := pl.radius
	for k in roads.size():
		var pts: PackedVector3Array = roads[k]["pts"]
		for c in ceili(float(pts.size()) / CHUNK_PTS):
			var key := "%s:%d:%d" % [pid, k, c]
			var mid: Vector3 = pts[mini(c * CHUNK_PTS + CHUNK_PTS / 2, pts.size() - 1)] * R
			var d := mid.distance_to(here) if near_planet else INF
			var have = _pieces.get(key)
			if d < NEAR and have == null:
				var i0 := c * CHUNK_PTS
				var i1 := mini(i0 + CHUNK_PTS + 1, pts.size())
				var sh := pl.shape
				var holder := {}
				var s0: float = (roads[k]["cum"] as PackedFloat32Array)[i0]
				var pave: Vector2 = roads[k].get("pave", Vector2(-1, -1))
				var L: float = roads[k]["length"]
				var job := Jobs.add(func(): holder["m"] = piece_mesh(sh, pts, i0, i1, s0, pave, L), false, "road piece")
				_pieces[key] = [job, holder, pl]
			elif have is Array and Jobs.done(have[0]):
				Jobs.wait(have[0])
				var res: Array = have[1].get("m", [])
				if res.is_empty() or not is_instance_valid(have[2]):
					_pieces[key] = null
					_pieces.erase(key)
					continue
				var mi := MeshInstance3D.new()
				mi.name = "Road%d_%d" % [k, c]
				mi.mesh = res[0]
				mi.material_override = material(pl)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = NEAR * 1.25
				mi.visibility_range_end_margin = 60.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				pl.add_child(mi)
				mi.position = res[1]
				_pieces[key] = mi
			elif have is MeshInstance3D and d > NEAR * 1.4:
				(have as Node).queue_free()
				_pieces.erase(key)


func _exit_tree() -> void:
	_quit = true   # (a world's search took up to 1.6 s: a gate's jump froze for it)
	for pl in _jobs:
		Jobs.wait(_jobs[pl][0])
	_jobs.clear()
	for key in _pieces:
		var have = _pieces[key]
		if have is Array:
			Jobs.wait(have[0])
	_pieces.clear()
	_quit = false


## The road material: the planet's soil in it (one a world).
static func material(pl: CosmosPlanet) -> ShaderMaterial:
	var pid := _pid(pl) if pl else ""
	if not _mats.has(pid):
		var L: Dictionary = pl.shape.look if pl else {}
		var low: Color = L.get("land_low", Color(0.45, 0.36, 0.27))
		var mid: Color = L.get("land_mid", Color(0.4, 0.42, 0.25))
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("soil", low.lerp(Color(0.46, 0.36, 0.26), 0.6))
		m.set_shader_parameter("verge", mid.lerp(Color(0.32, 0.35, 0.2), 0.4))
		m.set_shader_parameter("stone", Color(0.62, 0.59, 0.54).lerp(low, 0.15))
		_mats[pid] = m
	return _mats[pid]


# --- The network (on a worker) ----------------------------------------------------------

## A world's roads: the towns joined (a spanning tree of the cheapest ways, and
## a few more), each {a, b (town indices), pts (unit dirs a STEP apart), cum
## (m along at each), length, pave (m paved out of its a and b ends: a city's; -1 none)}.
static func network(shape: PlanetShape, towns: Array) -> Array:
	var n := towns.size()
	var out: Array = []
	if n < 2 or shape.kind != "rocky":
		return out
	var R := shape.radius
	var pairs: Array = []
	for i in n:
		for j in range(i + 1, n):
			var a: Vector3 = towns[i]["dir"]
			var b: Vector3 = towns[j]["dir"]
			pairs.append([acos(clampf(a.dot(b), -1.0, 1.0)) * R, i, j])
	pairs.sort_custom(func(x, y): return x[0] < y[0])
	var root: Array = range(n)
	var find := func(x: int, me: Callable) -> int:
		return x if root[x] == x else me.call(root[x], me)
	var dist: Array = []   # (along the network: town to town, m)
	for i in n:
		var row: Array = []
		row.resize(n)
		row.fill(INF)
		row[i] = 0.0
		dist.append(row)
	var tried := {}
	# The tree: the nearest pairs first, each joined if not yet joined.
	for p in pairs:
		var i: int = p[1]
		var j: int = p[2]
		var ri: int = find.call(i, find)
		var rj: int = find.call(j, find)
		if ri == rj:
			continue
		if float(p[0]) > MAX_LINK * 1.8:
			continue   # (too far for a road: joined some other way, or not at all)
		tried[[i, j]] = true
		var r := _road(shape, towns, i, j)
		if _quit:
			return []
		if r.is_empty():
			continue
		root[ri] = rj
		out.append(r)
		_relax(dist, i, j, float(r["length"]))
	# A few more: where a way of its own is much shorter than round by the others.
	var extra := 0
	for p in pairs:
		if extra >= maxi(1, n / 2):
			break
		var i: int = p[1]
		var j: int = p[2]
		if tried.has([i, j]) or float(p[0]) > MAX_LINK:
			continue
		if float(dist[i][j]) < float(p[0]) * 1.6:
			continue
		var r := _road(shape, towns, i, j)
		if r.is_empty() or float(r["length"]) > float(dist[i][j]) * 0.7:
			continue
		out.append(r)
		_relax(dist, i, j, float(r["length"]))
		extra += 1
	return out


## The towns' distances along the network with a new road i-j of length `L`.
static func _relax(dist: Array, i: int, j: int, L: float) -> void:
	var n := dist.size()
	for a in n:
		for b in n:
			var via := minf(float(dist[a][i]) + L + float(dist[j][b]), float(dist[a][j]) + L + float(dist[i][b]))
			if via < float(dist[a][b]):
				dist[a][b] = via


## The road between towns i and j: from the edge of one's levelled ground to the other's.
static func _road(shape: PlanetShape, towns: Array, i: int, j: int) -> Dictionary:
	var A: Vector3 = towns[i]["dir"]
	var B: Vector3 = towns[j]["dir"]
	var a := rim(shape, towns[i], B)
	var b := rim(shape, towns[j], A)
	var way := path(shape, a, b)
	if way.size() < 2:
		return {}
	# (in from its town's middle - the last stretch over its levelled ground, the gate to the rim)
	var pts := PackedVector3Array()
	pts.append(_inner(shape, towns[i], B))
	pts.append_array(way)
	pts.append(_inner(shape, towns[j], A))
	pts = smooth(pts, 3)
	pts = resample(pts, shape.radius, STEP)
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var L := 0.0
	for k in pts.size():
		if k > 0:
			L += pts[k].distance_to(pts[k - 1]) * shape.radius
		cum[k] = L
	return {"a": i, "b": j, "pts": pts, "cum": cum, "length": L,
		"pave": Vector2(PAVED if str(towns[i]["kind"]) == "city" else -1.0, PAVED if str(towns[j]["kind"]) == "city" else -1.0)}


## Where a road leaves a town towards `toward`: out at the rim of its levelled ground.
static func rim(shape: PlanetShape, site: Dictionary, toward: Vector3) -> Vector3:
	var d: Vector3 = site["dir"]
	var t := toward - d * toward.dot(d)
	if t.length() < 0.0001:
		t = site["t1"]
	return (d * shape.radius + t.normalized() * float(site["r"]) * 1.05).normalized()


## Its town's end: in past its buildings (a city's ~95 m out, a village's ~70 m).
static func _inner(shape: PlanetShape, site: Dictionary, toward: Vector3) -> Vector3:
	var d: Vector3 = site["dir"]
	var t := toward - d * toward.dot(d)
	if t.length() < 0.0001:
		t = site["t1"]
	var half := CosmosTown.layout(str(site["kind"]))["half"] as float
	return (d * shape.radius + t.normalized() * (half * 1.45 + 6.0)).normalized()


## A way over the ground from a to b (unit dirs): A* over cells CELL m across, in a
## band along the great circle between them (up to 30% of the way to either side).
## Cheapest where it's level; steep slopes dear, very steep ones all but closed;
## no way over the sea or lava (an ice sheet: dear). [] if there's none.
static func path(shape: PlanetShape, a: Vector3, b: Vector3) -> PackedVector3Array:
	var R := shape.radius
	var ang := acos(clampf(a.dot(b), -1.0, 1.0))
	var L := ang * R
	var cs := CELL if L < 5000.0 else CELL * 1.35
	var nu := maxi(2, ceili(L / cs))
	var su := L / nu
	var nv := ceili(clampf(L * 0.3, 260.0, 1800.0) / cs)
	var W := nv * 2 + 1
	var axis := a.cross(b)
	if axis.length() < 1e-6:
		axis = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT)
	axis = axis.normalized()
	var N := (nu + 1) * W
	var dirs := PackedVector3Array()
	dirs.resize(N)
	var hs := PackedFloat32Array()
	hs.resize(N)
	var shut := PackedByteArray()
	shut.resize(N)
	for iu in nu + 1:
		if _quit:
			return PackedVector3Array()
		var base := a.slerp(b, float(iu) / nu)
		for iv in W:
			var va := float(iv - nv) * cs / R
			var d := (base * cos(va) + axis * sin(va)).normalized()
			var k := iu * W + iv
			dirs[k] = d
			var h := shape.height(d)
			hs[k] = h
			if shape.sea in [1, 3] and h < 1.2:
				shut[k] = 1
			elif shape.sea == 2 and h < 0.5:
				shut[k] = 2
	var start := nv
	var goal := nu * W + nv
	shut[start] = 0
	shut[goal] = 0
	var g := PackedFloat32Array()
	g.resize(N)
	g.fill(INF)
	var from := PackedInt32Array()
	from.resize(N)
	from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(N)
	g[start] = 0.0
	# (a binary heap of [f, cell])
	var heap_f := PackedFloat32Array([0.0])
	var heap_k := PackedInt32Array([start])
	var DU := [-1, -1, -1, 0, 0, 1, 1, 1, -2, -2, -1, -1, 1, 1, 2, 2]
	var DV := [-1, 0, 1, -1, 1, -1, 0, 1, -1, 1, -2, 2, -2, 2, -1, 1]
	var found := false
	var pops := 0
	while heap_k.size() > 0:
		if _quit:
			return PackedVector3Array()
		var k := heap_k[0]
		_heap_pop(heap_f, heap_k)
		if closed[k]:
			continue
		closed[k] = 1
		pops += 1
		if k == goal:
			found = true
			break
		if pops > N * 2:
			break
		var iu := k / W
		var iv := k % W
		for m in DU.size():
			var ju: int = iu + DU[m]
			var jv: int = iv + DV[m]
			if ju < 0 or ju > nu or jv < 0 or jv >= W:
				continue
			var j := ju * W + jv
			if closed[j] or shut[j] == 1:
				continue
			var du := float(DU[m]) * su
			var dv := float(DV[m]) * cs
			var run := sqrt(du * du + dv * dv)
			var grade := absf(hs[j] - hs[k]) / run
			var cost := run * (1.0 + 28.0 * grade * grade)
			if grade > 0.28:
				cost += run * 40.0
			if shut[j] == 2:
				cost *= 2.5
			var ng := g[k] + cost
			if ng < g[j]:
				g[j] = ng
				from[j] = k
				var hu := float(nu - ju) * su
				var hv := float(jv - nv) * cs
				_heap_push(heap_f, heap_k, ng + sqrt(hu * hu + hv * hv), j)
	var out := PackedVector3Array()
	if not found:
		return out
	var k := goal
	while k != -1:
		out.append(dirs[k])
		k = from[k]
	out.reverse()
	out[0] = a
	out[out.size() - 1] = b
	return out


static func _heap_push(hf: PackedFloat32Array, hk: PackedInt32Array, f: float, k: int) -> void:
	hf.append(f)
	hk.append(k)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if hf[p] <= hf[i]:
			break
		var tf := hf[p]
		hf[p] = hf[i]
		hf[i] = tf
		var tk := hk[p]
		hk[p] = hk[i]
		hk[i] = tk
		i = p


static func _heap_pop(hf: PackedFloat32Array, hk: PackedInt32Array) -> void:
	var last := hf.size() - 1
	hf[0] = hf[last]
	hk[0] = hk[last]
	hf.resize(last)
	hk.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var s := i
		if l < last and hf[l] < hf[s]:
			s = l
		if r < last and hf[r] < hf[s]:
			s = r
		if s == i:
			break
		var tf := hf[s]
		hf[s] = hf[i]
		hf[i] = tf
		var tk := hk[s]
		hk[s] = hk[i]
		hk[i] = tk
		i = s


## Corners rounded off (Chaikin, `n` times; its ends kept).
static func smooth(pts: PackedVector3Array, n: int) -> PackedVector3Array:
	var p := pts
	for it in n:
		if p.size() < 3:
			return p
		var q := PackedVector3Array()
		q.append(p[0])
		for i in p.size() - 1:
			q.append(p[i].lerp(p[i + 1], 0.25).normalized())
			q.append(p[i].lerp(p[i + 1], 0.75).normalized())
		q.append(p[p.size() - 1])
		p = q
	return p


## Laid out a point every `step` m along it.
static func resample(pts: PackedVector3Array, radius: float, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b) * radius
		var s := step - carry
		while s <= seg:
			out.append(a.slerp(b, s / seg).normalized() if seg > 0.0 else a)
			s += step
		carry = seg - (s - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) * radius > step * 0.3:
		out.append(pts[pts.size() - 1])
	return out


# --- Along a road ------------------------------------------------------------------------

## The unit direction `s` m along `road` (clamped to its ends).
static func point(road: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = road["pts"]
	var cum: PackedFloat32Array = road["cum"]
	if s <= 0.0:
		return pts[0]
	var L: float = road["length"]
	if s >= L:
		return pts[pts.size() - 1]
	var i := clampi(int(s / STEP), 0, pts.size() - 2)
	while i > 0 and cum[i] > s:
		i -= 1
	while i < pts.size() - 2 and cum[i + 1] < s:
		i += 1
	var seg := cum[i + 1] - cum[i]
	return pts[i].slerp(pts[i + 1], (s - cum[i]) / seg if seg > 0.0 else 0.0).normalized()


## The nearest point of any of `roads` to unit direction `d`: [road index, s m along, distance m] (or [-1, 0, INF]).
static func nearest(roads: Array, d: Vector3, radius: float) -> Array:
	var best := [-1, 0.0, INF]
	for k in roads.size():
		var pts: PackedVector3Array = roads[k]["pts"]
		for i in range(0, pts.size(), 4):
			var m := pts[i].distance_to(d) * radius
			if m < best[2]:
				best = [k, float(roads[k]["cum"][i]), m]
	return best


# --- A piece's mesh (on a worker) ---------------------------------------------------------

## Points i0..i1 of a road as a ribbon on the ground: [ArrayMesh, its centre
## (planet-local)]; `s0` its first point's distance along (the shader's UV.y).
## Six columns across: the road's four, and its shoulders (cut out by the
## shader - its edge ragged). `pave`: how far from its a and b ends it's paved
## (a city's: PAVED m; -1 not) - in its vertices' red, the shader's flagstones;
## `length` the whole road's.
static func piece_mesh(shape: PlanetShape, pts: PackedVector3Array, i0: int, i1: int, s0: float, pave := Vector2(-1.0, -1.0), length := 0.0) -> Array:
	var R := shape.radius
	var np := i1 - i0
	if np < 2:
		return []
	var n := (np - 1) * SUB + 1   # (rows: SUB a point - as fine as the ground's mesh, no crest between them over it)
	var cols := [-1.25, -0.9, -0.35, 0.35, 0.9, 1.25]
	var lift := [0.03, 0.07, 0.09, 0.09, 0.07, 0.03]
	var half := WIDTH * 0.5
	var mid := pts[i0 + np / 2]
	var centre := mid * (R + maxf(shape.surface(mid), 0.0))
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var nor := PackedVector3Array()
	var tan := PackedFloat32Array()
	var vc := PackedColorArray()
	var C := cols.size()
	vc.resize(n * C)
	verts.resize(n * C)
	uvs.resize(n * C)
	nor.resize(n * C)
	tan.resize(n * C * 4)
	var sides := PackedVector3Array()
	sides.resize(n)
	for r in n:
		var i := i0 + r / SUB
		var t := float(r % SUB) / SUB
		var d := pts[i] if t == 0.0 else pts[i].slerp(pts[i + 1], t).normalized()
		var fwd := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		var side := d.cross(fwd).normalized()
		sides[r] = side
		var along := s0 + float(r) * STEP / SUB
		var pv := 0.0   # (paved: near a city's end, worn into earth further out)
		if pave.x >= 0.0:
			pv = maxf(pv, smoothstep(pave.x + 40.0, pave.x - 40.0, along))
		if pave.y >= 0.0:
			pv = maxf(pv, smoothstep(pave.y + 40.0, pave.y - 40.0, length - along))
		for c in C:
			vc[r * C + c] = Color(pv, 0, 0, 1)
			var off: float = cols[c] * half
			var q := (d * R + side * off).normalized()
			var h := shape.surface(q)
			verts[r * C + c] = q * (R + h + float(lift[c])) - centre
			uvs[r * C + c] = Vector2(cols[c], along)
	for r in n:
		for c in C:
			var k := r * C + c
			var ra := maxi(r - 1, 0)
			var rb := mini(r + 1, n - 1)
			var ca := maxi(c - 1, 0)
			var cb := mini(c + 1, C - 1)
			var ax := verts[rb * C + c] - verts[ra * C + c]
			var cx := verts[r * C + cb] - verts[r * C + ca]
			var nn := cx.cross(ax).normalized()
			var up := (verts[k] + centre).normalized()
			if nn.dot(up) < 0.0:
				nn = -nn
			nor[k] = nn
			var t := (cx - nn * cx.dot(nn)).normalized()
			tan[k * 4] = t.x
			tan[k * 4 + 1] = t.y
			tan[k * 4 + 2] = t.z
			tan[k * 4 + 3] = 1.0 if nn.cross(t).dot(ax) >= 0.0 else -1.0
	var idx := PackedInt32Array()
	for r in n - 1:
		for c in C - 1:
			var a := r * C + c
			var b := a + 1
			var e := a + C
			var f := e + 1
			# (wound so its top faces up: side x forward is the ground's up)
			idx.append_array([a, e, b, b, e, f])
	# (the winding checked against the ground's up: flipped if it came out facing down)
	var t0 := (verts[idx[1]] - verts[idx[0]]).cross(verts[idx[2]] - verts[idx[0]])
	if t0.dot((verts[idx[0]] + centre).normalized()) > 0.0:
		for k in range(0, idx.size(), 3):
			var tmp := idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = tmp
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = vc
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return [m, centre]


## A small road piece for CosmosWarm (its shader compiled at the title).
static func warm_mesh() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 2), Vector2(1, 2)])
	arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color(0, 0, 0), Color(1, 0, 0), Color(0, 0, 0), Color(1, 0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
