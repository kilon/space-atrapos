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
const WIDTH := 4.4              # m: the road across (a track to a village)
const MAIN_WIDTH := 5.6         # m: a main road's (city to city)
const CHUNK_PTS := 64           # points a mesh piece (~190 m)
const BARE_PTS := 128           # points a bare-ground entry (no plants on it)
const NEAR := 1100.0            # m: a piece built within this, let go past 1.4 x
const PAVED := 260.0             # m out of a city its roads are paved
const MAIN_PAVED := 900.0       # (a main road's: further out)
const MAX_LINK := 7000.0        # m: towns further apart get no road of their own (unless it's the only way to join them)
const SHADER := preload("res://shaders/world/road.gdshader")
const ROAD_CLASS := "res://scripts/world/life/cosmos_roads.gd"
const Bridges := preload("res://scripts/world/life/road_bridges.gd")   # (the roads over water: road_bridges.gd)

static var _cache := {}         # planet record id -> its roads (made once a session)
static var _mats := {}          # planet record id -> its ShaderMaterial

var cosmos: Node
var _jobs := {}                 # CosmosPlanet -> [job id, {"r": its roads}] (its network being made)
static var _quit := false       # (leaving: the searches on the workers stop where they are - not waited out)
var _bared := {}                # planet key -> true: its roads cleared of plants
var _pieces := {}               # "pid:road:piece" -> MeshInstance3D, or [job id, holder] while being made
var _t := 0.0
static var _decks := {}         # planet key -> its bridges' hash (Bridges.index: deck_probe)
var _djobs := {}                # planet key -> [job id, holder, planet]: its bridges found (roads made before them) / hashed
var _lit: Array = []            # the bridges' meshes (their lamps lit by night: lamp_lit)


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


## The key a world's roads are kept by, from its record (the planet map: no node needed).
static func key_of(rec: Dictionary) -> String:
	return "%s:%d" % [str(rec.get("id", "")), int(rec.get("seed", 0))]


## A world's roads made elsewhere (the planet map's worker): kept as if made here.
static func store(key: String, roads: Array, radius: float) -> void:
	if not _cache.has(key):
		_cache[key] = roads
		_ways[key] = way_hash(roads, radius)


## A world's roads by its key, if made ([] if not yet).
static func cached(key: String) -> Array:
	return _cache.get(key, [])


static func has_roads(key: String) -> bool:
	return _cache.has(key)


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
			_jobs[pl] = [Jobs.add(func(): _network_job(sh, towns, holder), false, "roads"), holder]
		if _cache.has(pid):
			if not _bared.has(pid):   # (made here or by the planet map's worker: nothing growing on them)
				_bared[pid] = true
				_bare(pl, _cache[pid])
			if not _decks.has(pid) and not _djobs.has(pid):
				_deck_job(pl, pid)
			_pieces_near(pl, pl.to_local(f.global_position), d < NEAR * 2.0)   # (planet-local, as its roads)
	_light_bridges()


## The bridges' lamps within `reach` m of global `at`, lit: [[key, global position, how lit, its planet]] (TownLamps' lights).
func lamps_near(at: Vector3, reach: float) -> Array:
	var out: Array = []
	for bmi in _lit:
		if not is_instance_valid(bmi) or not (bmi as Node).has_meta("lamps") or not (bmi as Node3D).is_visible_in_tree():
			continue
		var lv = (bmi as GeometryInstance3D).get_instance_shader_parameter("lamp_lit")
		var lit := float(lv) if lv != null else 0.0
		if lit <= 0.01:
			continue
		var pl := (bmi as Node).get_parent().get_parent() as Node3D
		var n3 := bmi as Node3D
		if n3.global_position.distance_to(at) > 260.0 + reach:
			continue
		var ls: PackedVector3Array = n3.get_meta("lamps")
		for i in ls.size():
			var g := n3.to_global(ls[i])
			if g.distance_to(at) < reach:
				out.append(["b%d:%d" % [n3.get_instance_id(), i], g, lit, pl])
	return out


## Its bridges' hash made on a worker (and, roads made before there were bridges -
## a hot reload, the planet map's - the bridges themselves: its pieces made again with them).
func _deck_job(pl: CosmosPlanet, pid: String) -> void:
	var roads: Array = _cache[pid]
	var sh := pl.shape
	var towns: Array = pl.towns.duplicate(true)
	var need := roads.any(func(r): return not (r as Dictionary).has("bridges"))
	var holder := {}
	var mine: Array = []
	for r in roads:   # (copies: the bridges added on the main thread when it's done)
		mine.append({"pts": r["pts"], "cum": r["cum"], "drawn": r.get("drawn", Vector2i(0, (r["pts"] as PackedVector3Array).size() - 1)),
			"width": r.get("width", WIDTH), "a": r.get("a", 0), "bridges": r.get("bridges", [])})
	_djobs[pid] = [Jobs.add(func(): _bridges_job(sh, mine, towns, need, holder), false, "road bridges"), holder, pl, need]


static func _bridges_job(sh: PlanetShape, mine: Array, towns: Array, need: bool, holder: Dictionary) -> void:
	if need:
		Bridges.make(sh, mine, towns)
	holder["d"] = Bridges.index(mine, sh.radius)
	holder["b"] = mine.map(func(r): return r["bridges"])


func _poll_decks() -> void:
	for pid in _djobs.keys():
		var job: Array = _djobs[pid]
		if not Jobs.done(job[0]):
			continue
		if job[3] and _pieces.keys().any(func(key): return str(key).begins_with(pid + ":") and _pieces[key] is Array):
			continue   # (its pieces being made read its roads: the bridges put in once they're done)
		Jobs.wait(job[0])
		_djobs.erase(pid)
		var roads: Array = _cache.get(pid, [])
		var bl: Array = job[1].get("b", [])
		if bl.size() != roads.size():
			continue
		if job[3]:
			for k in roads.size():
				roads[k]["bridges"] = bl[k]
			for key in _pieces.keys():   # (its pieces made again: on their bridges)
				if str(key).begins_with(pid + ":") and _pieces[key] is MeshInstance3D:
					(_pieces[key] as Node).queue_free()
					_pieces.erase(key)
				elif str(key).begins_with(pid + ":") and not (_pieces[key] is Array):
					_pieces.erase(key)
		_decks[pid] = job[1].get("d", {})


## The bridges' lamps: lit from a little before sunset to a little after sunrise (as the towns').
func _light_bridges() -> void:
	for i in range(_lit.size() - 1, -1, -1):
		var bmi = _lit[i]
		if not is_instance_valid(bmi) or not (bmi as Node).is_inside_tree():
			_lit.remove_at(i)
			continue
		var pl := (bmi as Node).get_parent().get_parent() as CosmosPlanet
		if pl == null:
			pl = (bmi as Node).get_parent().get_parent().get_parent() as CosmosPlanet   # (its glows: under the bridge's mesh)
		if pl == null:
			continue
		var night := TownLamps.test_night
		if night < 0.0:
			var e: float = ((bmi as Node3D).global_position - pl.global_position).normalized().dot(pl.sun_dir)
			night = 1.0 - smoothstep(-0.07, 0.1, e)
		(bmi as GeometryInstance3D).set_instance_shader_parameter("lamp_lit", night)


static func _network_job(sh: PlanetShape, towns: Array, holder: Dictionary) -> void:
	holder["r"] = network(sh, towns)
	holder["h"] = way_hash(holder["r"], sh.radius)   # (and where they run: on_way)
	holder["d"] = Bridges.index(holder["r"], sh.radius)   # (its bridges': deck_probe)


func _poll_jobs() -> void:
	_poll_decks()
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
		_ways[_pid(pl)] = job[1].get("h", {})
		if job[1].has("d"):
			_decks[_pid(pl)] = job[1]["d"]
		_bared[_pid(pl)] = true
		_bare(pl, roads)


## No plants or boulders on its roads (and the ground near you redone without them).
func _bare(pl: CosmosPlanet, roads: Array) -> void:
	var f: Node3D = cosmos.focus() if cosmos else null
	var here := pl.to_local(f.global_position) if f else Vector3.INF
	for k in roads.size():
		var c := cos((float(roads[k].get("width", WIDTH)) * 0.5 + 1.6) / pl.radius)
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
				var dr: Vector2i = roads[k].get("drawn", Vector2i(0, pts.size() - 1))   # (drawn from gate to gate: in the towns, their streets)
				var i0 := maxi(c * CHUNK_PTS, dr.x)
				var i1 := mini(mini(c * CHUNK_PTS + CHUNK_PTS + 1, pts.size()), dr.y + 1)
				if i1 - i0 < 2:
					_pieces[key] = false   # (all of it in a town)
					continue
				var sh := pl.shape
				var holder := {}
				var s0: float = (roads[k]["cum"] as PackedFloat32Array)[i0]
				var pave: Vector2 = roads[k].get("pave", Vector2(-1, -1))
				var L: float = roads[k]["length"]
				var wd: float = roads[k].get("width", WIDTH)
				var rd: Dictionary = roads[k]
				var job := Jobs.add(func(): _piece_job(sh, rd, i0, i1, s0, pave, L, wd, holder), false, "road piece")
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
				var rm := ArrayMesh.new()
				rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[0])
				mi.mesh = rm
				mi.material_override = material(pl)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = NEAR * 1.25
				mi.visibility_range_end_margin = 60.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				pl.add_child(mi)
				mi.position = res[1]
				_pieces[key] = mi
				var bres: Array = have[1].get("b", [])
				if not bres.is_empty():   # (its bridges: their stone, the empire's - Bridges.piece)
					var bm := ArrayMesh.new()
					bm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bres[0], [], bres[1])
					var bmi := MeshInstance3D.new()
					bmi.name = "Bridge"
					bmi.mesh = bm
					bmi.material_override = CosmosTown.material(str(have[1].get("emp", "")))
					bmi.transform = Transform3D(bres[2], Vector3.ZERO)
					bmi.visibility_range_end = NEAR * 1.4
					bmi.visibility_range_end_margin = 80.0
					bmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
					mi.add_child(bmi)
					bmi.set_meta("lamps", bres[3])   # (its lamps' lights: TownLamps lights the nearest - lamps_near)
					_lit.append(bmi)
					if not (bres[4] as Array).is_empty():   # (their glows on the deck)
						var pm := ArrayMesh.new()
						pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bres[4])
						var gmi := MeshInstance3D.new()
						gmi.name = "LampPools"
						gmi.mesh = pm
						gmi.material_override = TownLamps.pool_material()
						gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						gmi.visibility_range_end = 400.0
						bmi.add_child(gmi)
						_lit.append(gmi)
					_light_bridges()
			elif have is MeshInstance3D and d > NEAR * 1.4:
				(have as Node).queue_free()
				_pieces.erase(key)


## A piece's ribbon (laid on its bridges' decks where there are any) and its bridges' stone (on a worker).
static func _piece_job(sh: PlanetShape, rd: Dictionary, i0: int, i1: int, s0: float, pave: Vector2, L: float, wd: float, holder: Dictionary) -> void:
	var deck := Bridges.decks(rd, i0, i1)
	var m := piece_mesh(sh, rd["pts"], i0, i1, s0, pave, L, wd, deck)
	holder["m"] = m
	if not deck.is_empty() and not m.is_empty() and not _quit:
		holder["b"] = Bridges.piece(sh, rd, i0, i1, m[1])
		holder["emp"] = str((rd["bridges"] as Array)[0]["emp"]) if not (rd["bridges"] as Array).is_empty() else ""


func _exit_tree() -> void:
	_quit = true   # (a world's search took up to 1.6 s: a gate's jump froze for it)
	for pl in _jobs:
		Jobs.wait(_jobs[pl][0])
	_jobs.clear()
	for pid in _djobs:
		Jobs.wait(_djobs[pid][0])
	_djobs.clear()
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
	_main_roads(shape, towns, out, dist)
	if not _quit:
		Bridges.make(shape, out, towns)   # (over the water: its bridges)
	return out


## Every city on a main road (to another city): the nearest it can be joined to -
## over dry land, or a causeway over a strait (CosmosTown.CAUSEWAY m of water at
## most); failing both, a road to any town it can reach (a village's track).
static func _main_roads(shape: PlanetShape, towns: Array, out: Array, dist: Array) -> void:
	var n := towns.size()
	for i in n:
		if str(towns[i]["kind"]) != "city":
			continue
		if out.any(func(r): return r.get("main", false) and (int(r["a"]) == i or int(r["b"]) == i)):
			continue
		var others: Array = []
		for j in n:
			if j != i:
				var A: Vector3 = towns[i]["dir"]
				others.append([acos(clampf(A.dot(towns[j]["dir"]), -1.0, 1.0)) * shape.radius, j, str(towns[j]["kind"]) == "city"])
		others.sort_custom(func(x, y): return x[0] < y[0])
		var done := false
		for wet in [0.0, CosmosTown.CAUSEWAY, CosmosTown.LONG_CAUSEWAY]:
			for o in others:
				if not o[2] or float(o[0]) > MAX_LINK * (1.8 if wet < CosmosTown.LONG_CAUSEWAY else 2.6):
					continue
				if _quit:
					return
				if out.any(func(r): return (int(r["a"]) == i and int(r["b"]) == int(o[1])) or (int(r["b"]) == i and int(r["a"]) == int(o[1]))):
					continue
				var r := _road(shape, towns, i, o[1], wet)
				if r.is_empty():
					continue
				out.append(r)
				_relax(dist, i, o[1], float(r["length"]))
				done = true
				break
			if done:
				break
		if not done:   # (the search found no way: straight across, if a causeway's water at most lies between)
			for o in others:
				if not o[2] or float(o[0]) > 9000.0:
					continue
				var r := _road(shape, towns, i, o[1], CosmosTown.LONG_CAUSEWAY, true)
				if not r.is_empty():
					out.append(r)
					_relax(dist, i, o[1], float(r["length"]))
					done = true
					break
		if not done and not out.any(func(r): return int(r["a"]) == i or int(r["b"]) == i):
			for o in others:   # (no city in reach: a track to whatever town is)
				if float(o[0]) > MAX_LINK * 1.8:
					continue
				var r := _road(shape, towns, i, o[1], CosmosTown.LONG_CAUSEWAY)
				if not r.is_empty():
					out.append(r)
					_relax(dist, i, o[1], float(r["length"]))
					break


## The towns' distances along the network with a new road i-j of length `L`.
static func _relax(dist: Array, i: int, j: int, L: float) -> void:
	var n := dist.size()
	for a in n:
		for b in n:
			var via := minf(float(dist[a][i]) + L + float(dist[j][b]), float(dist[a][j]) + L + float(dist[i][b]))
			if via < float(dist[a][b]):
				dist[a][b] = via


## The road between towns i and j: out of a gate of each (where one of its
## streets meets its square's edge - TownStreets.gates - the one facing the
## other town), straight out over its levelled ground, then the way found over
## the ground between. Its ends go on in along the gate's street (to the ring
## round the palace, or the village's middle crossing): walked (the caravans),
## not drawn - the street is paved there; "drawn" its points from gate to gate.
static func _road(shape: PlanetShape, towns: Array, i: int, j: int, wet := 0.0, straight := false) -> Dictionary:
	var A: Vector3 = towns[i]["dir"]
	var B: Vector3 = towns[j]["dir"]
	var ga := gate_of(shape, towns[i], B)
	var gb := gate_of(shape, towns[j], A)
	var way := path(shape, ga["rim"], gb["rim"], wet, fields_of(shape, towns)) if not straight else _straight(shape, ga["rim"], gb["rim"], wet)
	if way.size() < 2:
		return {}
	var main := str(towns[i]["kind"]) == "city" and str(towns[j]["kind"]) == "city"
	var R := shape.radius
	var out := PackedVector3Array(ga["lead"])
	out.append_array(way.slice(1, way.size() - 1))
	var lb: PackedVector3Array = gb["lead"]
	lb.reverse()
	out.append_array(lb)
	out = _ended(resample(smooth(out, 3), R, STEP), ga["at"], gb["at"], R)
	var in_a := _ended(resample(ga["inner"], R, STEP), ga["inner"][0], ga["at"], R)
	var ib: PackedVector3Array = gb["inner"]
	ib.reverse()
	var in_b := _ended(resample(ib, R, STEP), gb["at"], ib[ib.size() - 1], R)
	var pts := PackedVector3Array(in_a)
	pts.append_array(out.slice(1))
	var drawn := Vector2i(in_a.size() - 1, pts.size() - 1)
	pts.append_array(in_b.slice(1))
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	var L := 0.0
	for k in pts.size():
		if k > 0:
			L += pts[k].distance_to(pts[k - 1]) * R
		cum[k] = L
	var wet_m := 0.0   # (over the water: a causeway)
	for k in range(drawn.x, drawn.y):
		if shape.sea in [1, 3] and shape.height(pts[k]) < 0.6:
			wet_m += pts[k].distance_to(pts[k + 1]) * R
	var pv := MAIN_PAVED if main else PAVED
	return {"a": i, "b": j, "pts": pts, "cum": cum, "length": L, "drawn": drawn, "main": main, "wet": wet_m,
		"width": MAIN_WIDTH if main else WIDTH,
		"pave": Vector2(pv if str(towns[i]["kind"]) == "city" else -1.0, pv if str(towns[j]["kind"]) == "city" else -1.0)}


## Its first and last points exactly `a` and `b` (a resample's last can fall short).
static func _ended(pts: PackedVector3Array, a: Vector3, b: Vector3, radius: float) -> PackedVector3Array:
	if pts.is_empty():
		return PackedVector3Array([a, b])
	pts[0] = a
	if pts.size() > 1 and pts[pts.size() - 1].distance_to(b) * radius < STEP * 0.4:
		pts[pts.size() - 1] = b
	elif not pts[pts.size() - 1].is_equal_approx(b):
		pts.append(b)
	return pts


## The gate a road leaves a town by towards `toward` (unit dirs, planet-local):
## {at: the gate (where its street meets the square's edge), lead: from it straight
## out past its levelled ground (a point every 10 m), rim: the last of them, inner:
## from in along its street out to the gate}.
static func gate_of(shape: PlanetShape, site: Dictionary, toward: Vector3) -> Dictionary:
	var R := shape.radius
	var xf := CosmosTown.frame(site, R)
	var up := xf.basis.y.normalized()
	var tw := toward * R - xf.origin
	tw = (tw - up * tw.dot(up)).normalized()
	var best := {}
	var bs := -INF
	var half0: float = CosmosTown.layout(str(site["kind"]))["half"]
	var run0 := float(site["r"]) - half0 + 30.0
	var own := fields_of(shape, [site])
	for g in TownStreets.gates(str(site["kind"]), str(site.get("empire", ""))):
		var sc := (xf.basis * (g["out"] as Vector3)).normalized().dot(tw)
		var crosses := false   # (its way out straight over the town's landing field or its pads: not that gate)
		for k in 9:
			if in_field(own, xf * ((g["at"] as Vector3) + (g["out"] as Vector3) * (run0 * k / 8.0))):
				crosses = true
				break
		if not crosses and sc > bs:
			bs = sc
			best = g
	if best.is_empty():   # (none: straight out from its middle)
		var at := (xf.origin + tw * float(CosmosTown.layout(str(site["kind"]))["half"])).normalized()
		best = {"at": xf.affine_inverse() * (at * (R + float(site["h"]))), "out": xf.basis.inverse() * tw, "inner": [Vector3.ZERO]}
	var g_at: Vector3 = best["at"]
	var o: Vector3 = best["out"]
	var half: float = CosmosTown.layout(str(site["kind"]))["half"]
	var lead := PackedVector3Array()
	var run := float(site["r"]) - half + 30.0
	var n := ceili(run / 10.0)
	for k in n + 1:
		lead.append((xf * (g_at + o * (run * k / n))).normalized())
	var inner := PackedVector3Array()
	for q in best["inner"]:
		inner.append((xf * (q as Vector3)).normalized())
	inner.reverse()   # (from in, out to the gate)
	if inner.size() < 2:
		inner = PackedVector3Array([lead[0], lead[0]])
	inner[inner.size() - 1] = lead[0]
	return {"at": lead[0], "lead": lead, "rim": lead[lead.size() - 1], "inner": inner}


## The towns' landing fields as zones to keep roads off: [[the town's frame inverted, its zone's box
## (town-local x0, x1, half-width in z)]] - the field's stone and the pads beside it (CosmosLandingField.pads_of).
static func fields_of(shape: PlanetShape, towns: Array) -> Array:
	var out: Array = []
	for t: Dictionary in towns:
		var lay := CosmosTown.layout(str(t["kind"]))
		var half: float = lay["half"]
		var port: Vector3 = lay["port"]
		var x1 := port.x + 40.0
		var zw := 40.0
		for p in CosmosLandingField.pads_of(t):
			var at: Vector3 = p["at"]
			var sz: Vector2 = p["size"]
			x1 = maxf(x1, at.x + sz.x * 0.5 + 6.0)
			zw = maxf(zw, absf(at.z) + sz.y * 0.5 + 6.0)
		var xf := CosmosTown.frame(t, shape.radius)
		out.append([xf.affine_inverse(), Vector3(half - 2.0, x1, zw)])
	return out


## Whether planet-local point `p` (on the ground) is in a town's landing field zone (fields_of).
static func in_field(fields: Array, p: Vector3, margin := 0.0) -> bool:
	for f: Array in fields:
		var l: Vector3 = (f[0] as Transform3D) * p
		var z: Vector3 = f[1]
		if l.x > z.x - margin and l.x < z.y + margin and absf(l.z) < z.z + margin and absf(l.y) < 200.0:
			return true
	return false


## A way over the ground from a to b (unit dirs): A* over cells CELL m across, in a
## band along the great circle between them (up to 30% of the way to either side).
## Cheapest where it's level; steep slopes dear, very steep ones all but closed;
## no way over the sea or lava (an ice sheet: dear). [] if there's none.
static func path(shape: PlanetShape, a: Vector3, b: Vector3, wet := 0.0, fields: Array = []) -> PackedVector3Array:
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
	var wt := shape.water   # (its lakes and rivers: PlanetWater - a lake or a deep river closed like the sea, a shallow stretch forded)
	var near_w := PackedByteArray()
	near_w.resize(N)
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
			elif wt and wt.near_water(d):
				near_w[k] = 1
				var wc := wt.crossing(d)
				shut[k] = 1 if wc == 2 else (3 if wc == 1 else 0)
			if not fields.is_empty() and in_field(fields, d * R, cs):   # (a cell's width more: the grid judged at its cells' middles, the smoothing cutting corners)
				shut[k] = 1   # (a town's landing field and its pads: no road over them)
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
			if closed[j] or (shut[j] == 1 and wet <= 0.0):
				continue
			var du := float(DU[m]) * su
			var dv := float(DV[m]) * cs
			var run := sqrt(du * du + dv * dv)
			var grade := absf(hs[j] - hs[k]) / run
			var cost := run * (1.0 + 28.0 * grade * grade)
			if grade > 0.28:
				cost += run * 40.0
			if near_w[k] or near_w[j]:   # (a river between the cells: crossed only where it's shallow - a ford)
				var wc := 0
				for t in [0.2, 0.4, 0.6, 0.8]:
					wc = maxi(wc, wt.crossing(dirs[k].lerp(dirs[j], t).normalized()))
				if wc == 2 and wet <= 0.0:
					continue
				if wc >= 1 or shut[j] == 3:
					cost *= 5.0
			if shut[j] == 2:
				cost *= 2.5
			elif shut[j] == 1:
				cost = run * 14.0   # (a causeway over the water: dear - only where there's no way round)
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
	if wet > 0.0:   # (no more water than a causeway can cross)
		var w := 0.0
		for i in out.size() - 1:
			if shut[0] >= 0 and shape.sea in [1, 3] and shape.height(out[i]) < 1.2:
				w += out[i].distance_to(out[i + 1]) * R
		if w > wet:
			return PackedVector3Array()
	return out


## A way straight along the great circle a..b (a point every CELL m) - if no more than `wet` m of it is water ([] if more).
static func _straight(shape: PlanetShape, a: Vector3, b: Vector3, wet: float) -> PackedVector3Array:
	if CosmosTown.water_between(shape, a, b) > wet:
		return PackedVector3Array()
	var n := maxi(2, ceili(acos(clampf(a.dot(b), -1.0, 1.0)) * shape.radius / CELL))
	var out := PackedVector3Array()
	for k in n + 1:
		out.append(a.slerp(b, float(k) / n).normalized())
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


# --- On a road? (CosmosWalker's pace) ----------------------------------------------------

const HASH := 12.0              # m: the cells a world's road points are kept in (on_way)
static var _ways := {}          # planet key -> {Vector3i cell: [road, point, road, point...]} (each point: its stretch to the next)
static var _town_frames := {}   # planet key -> [[its dir, cos of its reach, its frame inverted, kind, empire]] (its towns')


## A world's road stretches by where they are (made with its network, on the worker).
static func way_hash(roads: Array, radius: float) -> Dictionary:
	var h := {}
	for k in roads.size():
		var pts: PackedVector3Array = roads[k]["pts"]
		for i in pts.size() - 1:
			var key := Vector3i((pts[i] * radius / HASH).floor())
			var a: PackedInt32Array = h.get(key, PackedInt32Array())
			a.append(k)
			a.append(i)
			h[key] = a
	return h


## Is planet-local `local` (pl.to_local - the worlds turn) on one of its roads, or a street of one of its towns?
static func on_way(pl: CosmosPlanet, local: Vector3) -> bool:
	if pl == null or pl.towns.is_empty():
		return false
	var pid := _pid(pl)
	var R := pl.radius
	var d := local.normalized()
	if not _town_frames.has(pid):
		var tf: Array = []
		for s in pl.towns:
			tf.append([s["dir"], cos((float(s["r"]) + 5.0) / R), CosmosTown.frame(s, R).affine_inverse(), str(s["kind"]), str(s.get("empire", ""))])
		_town_frames[pid] = tf
	for t in _town_frames[pid]:
		if (t[0] as Vector3).dot(d) < float(t[1]):
			continue
		var tl: Vector3 = (t[2] as Transform3D) * local
		if absf(tl.y) < 3.0 and TownStreets.on_street(t[3], t[4], tl, 0.25):
			return true
	var h: Dictionary = _ways.get(pid, {})
	if h.is_empty():
		return false
	var roads: Array = _cache.get(pid, [])
	var p := d * R
	var c := Vector3i((p / HASH).floor())
	for x in 3:
		for y in 3:
			for z in 3:
				var a = h.get(c + Vector3i(x - 1, y - 1, z - 1))
				if a == null:
					continue
				for m in range(0, (a as PackedInt32Array).size(), 2):
					var pts: PackedVector3Array = roads[a[m]]["pts"]
					var i: int = a[m + 1]
					var lim: float = float(roads[a[m]].get("width", WIDTH)) * 0.5 + 0.3
					if Geometry3D.get_closest_point_to_segment(p, pts[i] * R, pts[i + 1] * R).distance_to(p) < lim:
						return true
	return false


# --- On a bridge? (the walker, the camera, bolts, travellers) ---------------------------

static var _pid_of := {}        # planet node id -> its key (asked every frame: not formatted each time)


## The bridge under planet-local `local` on `pl` (Bridges.probe: [bridge, s, x, deck top, ...]) or [].
static func deck_probe(pl: CosmosPlanet, local: Vector3) -> Array:
	if pl == null or _decks.is_empty():
		return []
	var pid = _pid_of.get(pl.get_instance_id())
	if pid == null:
		pid = _pid(pl)
		_pid_of[pl.get_instance_id()] = pid
	var h = _decks.get(pid)
	if h == null or (h as Dictionary).is_empty():
		return []
	return Bridges.probe(_cache.get(pid, []), h, pl.radius, local)


## A bridge's floor at planet-local `local` (its deck, a parapet's top - stepped onto
## from no more than Bridges.STEP_UP below; under it, none): m above the radius, or -INF.
static func deck_floor(pl: CosmosPlanet, local: Vector3) -> float:
	var pr := deck_probe(pl, local)
	return Bridges.floor_at(pr, local.length() - pl.radius) if not pr.is_empty() else -INF


## A bridge's deck under `local` (any height: a traveller, a donkey kept on it) - or -INF off it.
static func deck_top(pl: CosmosPlanet, local: Vector3) -> float:
	var pr := deck_probe(pl, local)
	if pr.is_empty() or absf(float(pr[2])) > float(pr[0]["half"]):
		return -INF
	return pr[3]


## How far (planet-local) a body of radius `r` at `local` (its feet) is moved out of a bridge's stone.
static func deck_push(pl: CosmosPlanet, local: Vector3, r: float) -> Vector3:
	var pr := deck_probe(pl, local)
	return Bridges.push(pr, local.length() - pl.radius, r) if not pr.is_empty() else Vector3.ZERO


## Whether planet-local `local` is in a bridge's stone (`pad` m of margin): the camera, bolts.
static func deck_solid(pl: CosmosPlanet, local: Vector3, pad := 0.0) -> bool:
	var pr := deck_probe(pl, local)
	return Bridges.solid(pr, local.length() - pl.radius, pad) if not pr.is_empty() else false


## A bridge within `reach` m of planet-local `local` (along the ground): the ship won't land there.
static func bridge_near(pl: CosmosPlanet, local: Vector3, reach: float) -> bool:
	if pl == null or _decks.is_empty():
		return false
	var u := local.normalized()
	var t1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := u.cross(t1)
	for o in [Vector3.ZERO, t1, -t1, t2, -t2, (t1 + t2) * 0.7, (t1 - t2) * 0.7, (-t1 + t2) * 0.7, (-t1 - t2) * 0.7]:
		var pr := deck_probe(pl, u * pl.radius + (o as Vector3) * reach * 0.75)
		if not pr.is_empty() and absf(float(pr[2])) < float(pr[0]["half"]) + Bridges.PARA_T + reach * 0.5:
			return true
	return false


## The deck `s` m along `road` (Bridges), or -INF where it's not on a bridge.
static func deck_along(road: Dictionary, s: float) -> float:
	for br: Dictionary in road.get("bridges", []):
		var h := Bridges.deck_h(br, road["cum"], s)
		if h > -INF:
			return h
	return -INF


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
static func piece_mesh(shape: PlanetShape, pts: PackedVector3Array, i0: int, i1: int, s0: float, pave := Vector2(-1.0, -1.0), length := 0.0, width := WIDTH, deck := PackedFloat32Array()) -> Array:
	var R := shape.radius
	var np := i1 - i0
	if np < 2:
		return []
	var n := (np - 1) * SUB + 1   # (rows: SUB a point - as fine as the ground's mesh, no crest between them over it)
	var cols := [-1.25, -0.9, -0.35, 0.35, 0.9, 1.25]
	var lift := [0.03, 0.07, 0.09, 0.09, 0.07, 0.03]
	var half := width * 0.5
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
		var dk := -INF   # (on a bridge - `deck`, Bridges.decks: laid on its deck, level across, paved)
		if not deck.is_empty():
			var da := deck[r / SUB]
			var db := deck[mini(r / SUB + 1, np - 1)]
			if da > -INF and (db > -INF or t == 0.0):
				dk = lerpf(da, db, t) if db > -INF else da
		var cw := 0.0   # (over the sea's edge: a causeway - its paved top 1.1 m over the water, its sides sloping into it)
		if dk > -INF:
			pv = 1.0
		elif shape.sea in [1, 3]:
			cw = smoothstep(0.8, -0.3, shape.height(d))
			pv = maxf(pv, cw)
		for c in C:
			vc[r * C + c] = Color(pv, 1.0 if dk > -INF else 0.0, 0, 1)   # (g: on a bridge - the shader's verge off)
			var off: float = cols[c] * half
			if dk > -INF and (c == 0 or c == C - 1):
				off = signf(cols[c]) * (half + Bridges.KERB)   # (its deck paved to the parapets)
			var q := (d * R + side * off).normalized()
			var h := dk if dk > -INF else shape.surface(q)
			if cw > 0.0:
				h = maxf(h, 1.1 * cw * (1.0 if c > 0 and c < C - 1 else 0.15))
			verts[r * C + c] = q * (R + h + float(lift[c])) - centre
			uvs[r * C + c] = Vector2(off / half, along)
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
	return [arr, centre]   # (the arrays: its mesh made on the main thread - meshes made on many workers at once race in the renderer)


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
