class_name SurfacePlanner
extends RefCounted
## A tiled planet made a piece at a time (PlanetSurface streams it): nothing
## is generated for the whole planet at once. On a worker thread, one job at a
## time (the surface queues them):
##   setup()        the planet's constants (noise, the water's shape, the height
##                  scale and the site height from a coarse sample) - a moment
##   plan()         where the villages, palaces, gates, pirate bands and
##                  industrial sites go - looking only at the terrain near them
##   chunk(cx, cy)  a GEN x GEN square: its ground (bands, ledges, plots
##                  levelled, ramps natural and linking), its tiles, its map
##                  pixels and its animals - returned as small arrays the
##                  surface copies into its own (it never touches these)
## The terrain is computed lazily in BLOCK x BLOCK blocks, on demand, and kept
## (_raw): the plan's edits (levelled plots, slopes) are applied to it, so every
## chunk sees them. The same planet (seed) always comes out the same, chunk by
## chunk, in any order.

const N := 440
const BLOCK := 16
const GEN := 32                     # a chunk (2 x the surface's scenery CHUNK)
const NB := N / BLOCK + 1
const REGION := 110
const VILLAGE_CHANCE := 0.45
const PIRATE_BANDS := 23
const WILD_GATES := 6
const GATE_APART := 45.0
const GATE_NAMES := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa",
	"Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho", "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"]
const PLOT_EASE := 10
const INDUSTRY_SITES := 14
const INDUSTRY_R := 4
## Islands (sky platforms): walkways along a lattice, LATTICE tiles apart, BRIDGE wide.
const LATTICE := 36
const BRIDGE := 3
const MAP_SEA := Color(0.014, 0.02, 0.032)
const MAP_SHALLOW := Color(0.03, 0.045, 0.062)
const MAP_LAND := Color(0.085, 0.06, 0.032)
const MAP_LIT := Color(1.0, 0.56, 0.16)
const MAP_COAST := Color(1.0, 0.76, 0.42)
const MAP_GRID := 44
const MAP_ELEV_HIGH := Color(0.88, 0.92, 0.8)
const NB4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]

const TTILES := preload("res://scripts/terrain_tiles.gd")
const BUILDINGS := ["warehouse", "temple"]

# Given by the surface.
var pdata: Dictionary
var planet_id := ""
var seed_ := 0
var tile_set_id := ""
var tile_pieces: Array = []
var culture_name := "Minoan"
var sky := false
var g2w: Transform2D                 # grid -> world (the surface's _g2w)

# The planet's constants (setup).
var th := PackedFloat32Array()
var walk_t := PackedByteArray()
var water_top := -1.0
var site_h := 0.0
var plot_lvl := 0
var lvl_top := 1
var _wl := 0
var _land_lo := -0.62
var _water := ""
var _lo := 0.0
var _hi := 1.0
var _ridge: FastNoiseLite
var _hills: FastNoiseLite
var _crag: FastNoiseLite
var _bumps: FastNoiseLite
var _wiggle: FastNoiseLite
var _meander: FastNoiseLite
var _rn: FastNoiseLite
var _isle: FastNoiseLite
var _n1: FastNoiseLite               # tile looks (TerrainTiles.ground_piece)
var _n2: FastNoiseLite
var _coast_dir := Vector2.RIGHT
var _islets: Array = []
var _lake := {}
var _river := {}
var _cen := Vector2(N / 2.0, N / 2.0)

# The terrain, made lazily by block, with the plan's edits.
var _height := PackedFloat32Array()
var _ramp := PackedFloat32Array()
var _terrain := PackedByteArray()
var _block_done := PackedByteArray()

# The plan (plan()).
var plans: Array = []                # {spec, built: null}
var npc_plans: Array = []
var plot_cells := {}
var clear_spots: Array = []          # [cell, radius]
var village_spots: Array = []
var gates: Array = []
var industry: Array = []
var village_fauna: Array = []        # fauna plans by the villages (the rest: a chunk's own)
var atlas_looks: Array = []
var tile_ts: TileSet
var planned := false
var _rng := RandomNumberGenerator.new()


## (worker) The planet's constants; heavy-ish parts are coarse (1/8 sample).
func setup() -> void:
	th = PackedFloat32Array(pdata["thresholds"])
	var terr: Array = pdata["terrain"]
	walk_t = PackedByteArray()
	for t in terr:
		walk_t.append(1 if t[2] else 0)
	_wl = 0
	while _wl < terr.size() and not terr[_wl][2]:
		_wl += 1
	water_top = th[_wl - 1] if _wl > 0 else -1.0
	_land_lo = water_top + 0.012 if _wl > 0 else -0.62
	if _wl + 1 < terr.size() and terr[_wl][3] == "sand":
		_land_lo = th[_wl] + 0.012
	_water = str(pdata.get("water", ""))
	if _wl == 0:
		_water = "none"
	elif _water == "":
		_water = ["coast", "lake", "river"][posmod(seed_, 3)]
	_ridge = _noise(seed_, 0.0065, 5, 0.42, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_RIDGED)
	_ridge.domain_warp_enabled = true
	_ridge.domain_warp_amplitude = 30.0
	_ridge.domain_warp_frequency = 0.01
	_hills = _noise(seed_ + 1, 0.011, 3, 0.4)
	_crag = _noise(seed_ + 2, 0.028, 3, 0.45)
	_bumps = _noise(seed_ + 5, 0.07, 2)
	_wiggle = _noise(seed_ + 3, 0.008, 3)
	_meander = _noise(seed_ + 4, 0.007, 1)
	_meander.fractal_type = FastNoiseLite.FRACTAL_NONE
	_rn = _noise(seed_ + 6, 0.03, 5)
	_isle = _noise(seed_ + 21, 0.028, 2, 0.5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	_n1 = _noise(seed_ + 11, 0.08, 5)
	_n2 = _noise(seed_ + 12, 0.03, 5)
	# The water's shape: drawn from the planet's own rng, once.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7919 + 13
	match _water:
		"coast":
			_coast_dir = Vector2.from_angle(rng.randf() * TAU)
			for k in rng.randi_range(2, 4):
				var along := Vector2(-_coast_dir.y, _coast_dir.x) * rng.randf_range(-0.38, 0.38) * N
				_islets.append([_cen + _coast_dir * rng.randf_range(0.37, 0.44) * N + along, rng.randf_range(6.0, 13.0)])
		"lake":
			_lake = {"c": _cen + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.3) * N,
				"r": rng.randf_range(18.0, 30.0), "sq": Vector2(rng.randf_range(0.7, 1.0), rng.randf_range(0.7, 1.0)),
				"rot": rng.randf() * PI}
		"river":
			var u := Vector2.from_angle(rng.randf() * TAU)
			var fords := []
			var lat0 := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.2, 0.28) * N
			for k in 3:
				fords.append(rng.randf_range(-0.4, 0.4) * N)
			_river = {"u": u, "side": Vector2(-u.y, u.x), "lat0": lat0, "amp": 0.12 * N, "fords": fords}
	# The height scale (the relief's range) and the site height (the commonest
	# walkable band) from a coarse sample of the whole planet.
	_lo = INF
	_hi = -INF
	for i in range(0, N, 8):
		for j in range(0, N, 8):
			var v := _relief(i, j)
			_lo = minf(_lo, v)
			_hi = maxf(_hi, v)
	var counts := {}
	var top_h := -1.0
	for i in range(0, N, 8):
		for j in range(0, N, 8):
			var h := _raw_height(i, j)
			var t := _band(h)
			if walk_t[t] == 1:
				counts[t] = counts.get(t, 0) + 1
			top_h = maxf(top_h, h)
	var best := 0
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best = t
			best_n = counts[t]
	var lo: float = th[best - 1] if best > 0 else th[0] - 0.3
	var hi: float = th[best] if best < th.size() else th[-1] + 0.3
	site_h = (lo + hi) * 0.5
	plot_lvl = clampi(floori(maxf(0.0, site_h - water_top - 0.03) / TTILES.TERRACE), 0, 20)
	if sky:
		plot_lvl = maxi(plot_lvl, 1)
	lvl_top = maxi(1, clampi(floori(maxf(0.0, top_h - water_top - 0.03) / TTILES.TERRACE), 0, 20))
	_height.resize(N * N)
	_ramp.resize(N * N)
	_terrain.resize(N * N)
	_block_done.resize(NB * NB)


static func _noise(s: int, f: float, oct := 5, gain := 0.5, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, frac := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = type
	n.fractal_type = frac
	n.fractal_octaves = oct
	n.fractal_gain = gain
	n.frequency = f
	return n


func _relief(i: int, j: int) -> float:
	return 0.62 * _ridge.get_noise_2d(i, j) + 0.38 * _hills.get_noise_2d(i, j)


## The water's signed distance at a cell (> 0 land), as SurfaceTerrain draws it.
func _sd(i: int, j: int) -> float:
	var p := Vector2(i, j)
	match _water:
		"coast":
			var s := (p - _cen).dot(_coast_dir) - 0.3 * N + N * (0.07 * _wiggle.get_noise_2d(i, j) + 0.015 * _crag.get_noise_2d(i * 2, j * 2))
			var d := -s
			for isl in _islets:
				d = maxf(d, isl[1] * (1.0 + 0.45 * _crag.get_noise_2d(i * 2, j * 2)) - p.distance_to(isl[0]))
			return d
		"lake":
			var lc: Vector2 = _lake["c"]
			var lsq: Vector2 = _lake["sq"]
			var q: Vector2 = (p - lc).rotated(float(_lake["rot"])) / lsq
			return q.length() - _lake["r"] * (1.0 + 0.3 * _wiggle.get_noise_2d(i * 3, j * 3))
		"islands":
			var d := (_isle.get_noise_2d(i, j) - 0.08) * 40.0
			d = maxf(d, 22.0 - p.distance_to(_cen))
			# (walkways between the platforms: a lattice of them across the sky)
			var li := posmod(i - N / 2 + BRIDGE / 2, LATTICE) < BRIDGE
			var lj := posmod(j - N / 2 + BRIDGE / 2, LATTICE) < BRIDGE
			if li or lj:
				d = maxf(d, 1.0)
			d = minf(d, float(mini(mini(i, j), mini(N - 1 - i, N - 1 - j))) - 5.0)
			return d
		"river":
			var q := p - _cen
			var a := q.dot(_river["u"])
			var amp: float = _river["amp"]
			var off: float = _river["lat0"] + amp * _meander.get_noise_1d(a)
			var slope := amp * (_meander.get_noise_1d(a + 1.0) - _meander.get_noise_1d(a - 1.0)) * 0.5
			var hw := 3.2 + 1.2 * _crag.get_noise_1d(a * 0.3)
			var d := absf(q.dot(_river["side"]) - off) / sqrt(1.0 + slope * slope) - hw
			for f in _river["fords"]:
				d = maxf(d, (3.0 - absf(a - f)) * 3.0)
			return d
	return 1e6


func _raw_height(i: int, j: int) -> float:
	var r := (_relief(i, j) - _lo) / maxf(_hi - _lo, 1e-5)
	r = pow(clampf(r, 0.0, 1.0), 1.7)
	var inland := lerpf(_land_lo, 0.8, r) + (0.01 + 0.015 * r) * _bumps.get_noise_2d(i, j)
	var d := _sd(i, j)
	var h: float
	if d <= 0.0:
		h = lerpf(water_top - 0.015, -0.78, smoothstep(0.0, 10.0, -d))
	else:
		h = lerpf(water_top + 0.012, inland, smoothstep(0.0, 30.0, d)) if _wl > 0 else inland
	return clampf(h, -1.0, 1.0)


func _band(h: float) -> int:
	var t := 0
	while t < th.size() and h > th[t]:
		t += 1
	return t


## (worker) The terrain of every block overlapping `r` made (once).
func ensure(r: Rect2i) -> void:
	var a := r.intersection(Rect2i(0, 0, N, N))
	if not a.has_area():
		return
	for bx in range(a.position.x / BLOCK, (a.end.x - 1) / BLOCK + 1):
		for by in range(a.position.y / BLOCK, (a.end.y - 1) / BLOCK + 1):
			if _block_done[bx * NB + by] == 1:
				continue
			_block_done[bx * NB + by] = 1
			for i in range(bx * BLOCK, mini(bx * BLOCK + BLOCK, N)):
				for j in range(by * BLOCK, mini(by * BLOCK + BLOCK, N)):
					var k := i * N + j
					var h := _raw_height(i, j)
					_height[k] = h
					_terrain[k] = _band(h)
					var rr := smoothstep(0.0, 0.15, _rn.get_noise_2d(i, j))
					_ramp[k] = maxf(rr, 1.0 - smoothstep(8.0, 14.0, _sd(i, j)))


func walkable(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return false
	ensure(Rect2i(c, Vector2i.ONE))
	return walk_t[_terrain[c.x * N + c.y]] == 1


func _set_height(c: Vector2i, h: float) -> void:
	var k := c.x * N + c.y
	_height[k] = h
	_terrain[k] = _band(h)


func cell_pos(c: Vector2i) -> Vector2:
	return g2w * Vector2(c)


# --- The plan ----------------------------------------------------------------------------

## (worker) The villages, gates, pirates and industry of the whole planet -
## only the terrain near them is made to plan them.
func plan() -> void:
	_rng.seed = seed_
	var center := Vector2i(N / 2, N / 2)
	_level_disc(center, 9.0, 14.0)   # the landing site, at the site height
	_add_clear_spot(center, 3.2)
	if pdata.get("villages", true):
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_plan_village(center, center + Vector2i(dir * 28.0), true, 0)
		var vid := 1
		var quarters := {}   # (a village in every quarter of the planet: the second pass makes sure)
		var spare := {}
		for gx in N / REGION:
			for gy in N / REGION:
				var vr := RandomNumberGenerator.new()
				vr.seed = hash([seed_, "village", gx, gy])
				var c := Vector2i(gx * REGION + REGION / 2, gy * REGION + REGION / 2) + Vector2i(vr.randi_range(-25, 25), vr.randi_range(-25, 25))
				var qk := Vector2i(gx * 2 / (N / REGION), gy * 2 / (N / REGION))
				var palace := vr.randf() < 0.35
				if Vector2(c).distance_to(Vector2(center)) < REGION * 0.8:
					continue
				if vr.randf() > VILLAGE_CHANCE:
					if not spare.has(qk):
						spare[qk] = [c, palace]
					continue
				_rng.seed = hash([seed_, "v", vid])
				_plan_village(c, c, palace, vid)
				quarters[qk] = true
				vid += 1
		for qk in spare:
			if not quarters.has(qk):
				_rng.seed = hash([seed_, "v", vid])
				_plan_village(spare[qk][0], spare[qk][0], spare[qk][1], vid)
				vid += 1
	elif pdata.get("industry", true):
		_plan_industry()
	var pr := RandomNumberGenerator.new()
	pr.seed = hash([seed_, "pirates"])
	for b in PIRATE_BANDS:
		var c := Vector2i(pr.randi_range(20, N - 21), pr.randi_range(20, N - 21))
		if Vector2(c).distance_to(Vector2(center)) < 30.0:
			continue
		_rng.seed = hash([seed_, "band", b])
		_plan_pirate_band(c, pr.randi_range(2, 4))
	_plan_gates()
	_plan_village_fauna()
	planned = true


func _plan_village(palace_near: Vector2i, near: Vector2i, palace: bool, vid: int) -> void:
	village_spots.append(near)
	var homes: Array = []
	if palace:
		var pr := _find_clear_site(Vector2i(16, 14), palace_near, 22)
		if pr.size != Vector2i.ZERO:
			_clear_site(pr)
			var x0 := pr.position.x
			var y0 := pr.position.y
			var x1 := pr.end.x - 1
			var y1 := pr.end.y - 1
			var cols := []
			for c in [Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 11), Vector2i(4, 11),
					Vector2i(8, 8), Vector2i(12, 8), Vector2i(8, 11), Vector2i(12, 11)]:
				cols.append([x0 + c.x, y0 + c.y])
			_add_plan({"rect": [x0, y0, 16, 14], "material": "minoan", "style": "palace", "title": "%s palace" % culture_name,
				"doors": [[x0 + 3, y1, "sw"], [x1, y0 + 10, "se"], [x0 + 10, y0, "ne"]],
				"inner": [["i", x0 + 6, y0, y1, y0 + 6], ["j", y0 + 6, x0 + 6, x1, x0 + 10]],
				"mosaic": [x0 + 1, y0 + 4, 4, 6], "columns": cols})
	for hi in BUILDINGS.size():
		var size: Vector2i = [Vector2i(13, 12), Vector2i(12, 12)][hi]
		var hr := _find_clear_site(size, near, 20)
		if hr.size == Vector2i.ZERO:
			continue
		_clear_site(hr)
		var door := Vector2i(hr.position.x + size.x / 2, hr.end.y - 1)
		_add_plan({"rect": [hr.position.x, hr.position.y, size.x, size.y], "material": "minoan", "style": BUILDINGS[hi],
			"title": "%s %s" % [culture_name, BUILDINGS[hi]], "doors": [[door.x, door.y, "sw"]],
			"inner": _divider(hr, [[door, "sw"]]), "mosaic": [], "columns": []})
		homes.append(hr.get_center())
	_add_clear_spot(near, 4.0)
	var count := 9 if vid == 0 else 4
	for k in count:
		var home := cell_pos(near)
		var spread := Vector2(120, 60)
		if k / 2 < homes.size():
			home = cell_pos(homes[k / 2])
			spread = Vector2(40, 20)
		var pos := home + Vector2(_rng.randf_range(-spread.x, spread.x), _rng.randf_range(-spread.y, spread.y))
		npc_plans.append({"pos": pos, "variant": k + vid * 9, "home": home, "spawned": false, "kind": ""})
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(30.0, 38.0) if vid == 0 else _rng.randf_range(18.0, 26.0)
	_plan_pirate_band(near + Vector2i(Vector2.from_angle(ang) * dist), 2 if vid == 0 else 3)


func _add_plan(spec: Dictionary) -> void:
	plans.append({"spec": spec, "built": null})
	var r := Rect2i(spec["rect"][0], spec["rect"][1], spec["rect"][2], spec["rect"][3])
	var g := r.grow(3)
	for i in range(g.position.x, g.end.x):
		for j in range(g.position.y, g.end.y):
			plot_cells[Vector2i(i, j)] = true


static func plan_rect(p: Dictionary) -> Rect2i:
	var r: Array = p["spec"]["rect"]
	return Rect2i(r[0], r[1], r[2], r[3])


func _divider(r: Rect2i, doors: Array) -> Array:
	if r.size.x < 4:
		return []
	var door_x: Array = doors.map(func(d): return (d[0] as Vector2i).x)
	var best := -1
	var best_w := -1
	for x in range(r.position.x + 1, r.end.x):
		if x in door_x:
			continue
		var w := mini(x - r.position.x, r.end.x - x)
		if w > best_w:
			best_w = w
			best = x
	if best < 0 or best_w < 2:
		return []
	return [["i", best, r.position.y, r.end.y - 1, r.position.y + r.size.y / 2]]


func _find_clear_site(size: Vector2i, near: Vector2i, radius: int) -> Rect2i:
	var center := Vector2i(N / 2, N / 2)
	ensure(Rect2i(near - Vector2i(radius, radius) - size, Vector2i(radius, radius) * 2 + size * 2).grow(3))
	var best := Rect2i()
	var best_cost := INF
	for attempt in 90:
		var pos := near + Vector2i(_rng.randi_range(-radius, radius), _rng.randi_range(-radius, radius)) - size / 2
		var r := Rect2i(pos, size)
		var g := r.grow(2)
		if g.position.x < 5 or g.position.y < 5 or g.end.x > N - 5 or g.end.y > N - 5:
			continue
		if g.grow(3).has_point(center) or g.grow(3).has_point(center + Vector2i(1, 1)):
			continue
		var ok := true
		for c in [g.position, Vector2i(g.end.x, g.position.y), g.end, Vector2i(g.position.x, g.end.y)]:
			if Vector2(c).distance_to(Vector2(center)) > N * 0.5 * 0.82:
				ok = false
		for p in plans:
			if plan_rect(p).grow(4).intersects(r):
				ok = false
		if not ok:
			continue
		var cost := 0.0
		for i in range(g.position.x, g.end.x, 2):
			for j in range(g.position.y, g.end.y, 2):
				if walk_t[_terrain[i * N + j]] == 0:
					cost += 4.0
				cost += absf(_height[i * N + j] - site_h) * 6.0
		cost += Vector2(r.get_center()).distance_to(Vector2(near)) * 0.15
		if cost < best_cost:
			best = r
			best_cost = cost
	return best


func _clear_site(r: Rect2i) -> void:
	var g := r.grow(2 + PLOT_EASE)
	ensure(g)
	for i in range(maxi(g.position.x, 0), mini(g.end.x, N)):
		for j in range(maxi(g.position.y, 0), mini(g.end.y, N)):
			var d := maxi(maxi(r.position.x - i, i - (r.end.x - 1)), maxi(r.position.y - j, j - (r.end.y - 1)))
			_ramp[i * N + j] = 1.0
			if d <= 2:
				_set_height(Vector2i(i, j), site_h)
			else:
				_set_height(Vector2i(i, j), lerpf(_height[i * N + j], site_h, 1.0 - smoothstep(2.0, 2.0 + PLOT_EASE, d)))


func _level_disc(c: Vector2i, r: float, ease: float) -> void:
	var R := ceili(r + ease)
	ensure(Rect2i(c - Vector2i(R, R), Vector2i(2 * R + 1, 2 * R + 1)))
	for dx in range(-R, R + 1):
		for dy in range(-R, R + 1):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
				continue
			var d := Vector2(dx, dy).length()
			if d > r + ease:
				continue
			var k := 1.0 - smoothstep(r, r + ease, d)
			_set_height(q, lerpf(_height[q.x * N + q.y], site_h, k))
			_ramp[q.x * N + q.y] = 1.0


func _add_clear_spot(cell: Vector2i, radius: float) -> void:
	clear_spots.append([cell, radius])
	var rr := radius + 2.0
	var r := ceili(rr + 3.0)
	ensure(Rect2i(cell - Vector2i(r, r), Vector2i(2 * r + 1, 2 * r + 1)))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var q := cell + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < N and q.y < N:
				var k := 1.0 - smoothstep(rr, rr + 3.0, Vector2(dx, dy).length())
				_ramp[q.x * N + q.y] = maxf(_ramp[q.x * N + q.y], k)


func _plan_pirate_band(c: Vector2i, count: int) -> void:
	var cc := c.clamp(Vector2i(8, 8), Vector2i(N - 9, N - 9))
	var home := cell_pos(cc)
	ensure(Rect2i(cc - Vector2i(4, 4), Vector2i(9, 9)))
	for k in count:
		var pos := home + Vector2(_rng.randf_range(-160, 160), _rng.randf_range(-80, 80))
		npc_plans.append({"pos": pos, "variant": _rng.randi_range(0, 9999), "home": home, "spawned": false, "kind": "pirate"})


func _plan_industry() -> void:
	var center := Vector2i(N / 2, N / 2)
	var kinds := ["refinery", "factory", "depot", "relay"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_, "industry"])
	var tries := 0
	while industry.size() < INDUSTRY_SITES and tries < 400:
		tries += 1
		var c := Vector2i(rng.randi_range(12, N - 13), rng.randi_range(12, N - 13))
		if Vector2(c).distance_to(Vector2(center)) < 24.0:
			continue
		if industry.any(func(s): return Vector2(s["cell"]).distance_to(Vector2(c)) < 22.0):
			continue
		ensure(Rect2i(c - Vector2i(INDUSTRY_R, INDUSTRY_R), Vector2i(2 * INDUSTRY_R + 1, 2 * INDUSTRY_R + 1)))
		var ok := true
		for dx in range(-INDUSTRY_R, INDUSTRY_R + 1):
			for dy in range(-INDUSTRY_R, INDUSTRY_R + 1):
				var q := c + Vector2i(dx, dy)
				if walk_t[_terrain[q.x * N + q.y]] == 0:
					ok = false
		if not ok:
			continue
		_clear_site(Rect2i(c - Vector2i(INDUSTRY_R - 1, INDUSTRY_R - 1), Vector2i(2 * INDUSTRY_R - 1, 2 * INDUSTRY_R - 1)))
		for dx in range(-INDUSTRY_R, INDUSTRY_R + 1):
			for dy in range(-INDUSTRY_R, INDUSTRY_R + 1):
				plot_cells[c + Vector2i(dx, dy)] = true
		industry.append({"kind": kinds[industry.size() % kinds.size()], "cell": c})


func _plan_gates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planet_id + ":gates")
	var center := Vector2i(N / 2, N / 2)
	var spots: Array = [[center, 8, 14]]
	for v in village_spots:
		spots.append([v, 10, 22])
	for k in WILD_GATES * 4:
		spots.append([Vector2i(rng.randi_range(40, N - 41), rng.randi_range(40, N - 41)), 0, 12])
	var wild := 0
	for sp in spots:
		if gates.size() >= GATE_NAMES.size():
			break
		var is_wild: bool = sp[1] == 0
		if is_wild and wild >= WILD_GATES:
			continue
		var cell := _gate_cell(sp[0], sp[1], sp[2], rng)
		if cell == Vector2i(-1, -1):
			continue
		if gates.any(func(g): return Vector2(g["cell"]).distance_to(Vector2(cell)) < GATE_APART):
			continue
		gates.append({"cell": cell, "name": "Gate " + GATE_NAMES[gates.size()], "node": null})
		_add_clear_spot(cell, 2.6)
		if is_wild:
			wild += 1


func _gate_cell(near: Vector2i, r0: int, r1: int, rng: RandomNumberGenerator) -> Vector2i:
	ensure(Rect2i(near - Vector2i(r1 + 3, r1 + 3), Vector2i(2 * r1 + 7, 2 * r1 + 7)))
	for attempt in 60:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r0, r1)
		var c := near + Vector2i(roundi(cos(a) * d), roundi(sin(a) * d))
		if c.x < 12 or c.y < 12 or c.x > N - 13 or c.y > N - 13:
			continue
		if Vector2(c).distance_to(_cen) > N * 0.5 * 0.8 or Vector2(c).distance_to(_cen) < 6.0:
			continue
		var ok := true
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var q := c + Vector2i(dx, dy)
				if plot_cells.has(q) or not walkable(q):
					ok = false
		for p in plans:
			if plan_rect(p).grow(3).has_point(c):
				ok = false
		if ok:
			return c
	return Vector2i(-1, -1)


## The animals that keep to the villages (one herd a village in turn).
func _plan_village_fauna() -> void:
	var table: Array = SurfaceCreature.FAUNA.get(tile_set_id, [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planet_id + ":fauna")
	var towns: Array = [Vector2i(N / 2, N / 2)] + village_spots
	for row in table:
		if str(row[4]) != "village":
			continue
		for g in int(row[1]) * SurfaceCreature.DENSITY:
			var t: Vector2i = towns[(g + 1) % towns.size()]
			for attempt in 20:
				var c := t + Vector2i(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 24.0))
				if c.x < 4 or c.y < 4 or c.x > N - 5 or c.y > N - 5 or plot_cells.has(c) or not walkable(c):
					continue
				_herd(row, c, rng, village_fauna)
				break


func _herd(row: Array, c: Vector2i, rng: RandomNumberGenerator, out: Array) -> void:
	var home := cell_pos(c)
	for k in rng.randi_range(int(row[2]), int(row[3])):
		var pos := home + Vector2(rng.randf_range(-90, 90), rng.randf_range(-45, 45))
		out.append({"species": str(row[0]), "pos": pos, "home": home, "node": null, "dead": false})


# --- A chunk -----------------------------------------------------------------------------

## (worker) Square (cx, cy): its ground arrays, its tiles and map pixels, its animals.
##   {rect, height, terrain, ramp, lvl, rampd, tiles (level, x, y, source - PackedInt32Array),
##    map (Image), fauna}
func chunk(cx: int, cy: int) -> Dictionary:
	var r := Rect2i(cx * GEN, cy * GEN, GEN, GEN).intersection(Rect2i(0, 0, N, N))
	var E := r.grow(4).intersection(Rect2i(0, 0, N, N))
	ensure(r.grow(14))
	var w := E.size.x
	var h := E.size.y
	var walk := PackedByteArray()
	walk.resize(w * h)
	var lv := PackedByteArray()
	lv.resize(w * h)
	for a in w:
		for b in h:
			var i := E.position.x + a
			var j := E.position.y + b
			var k := i * N + j
			var e := a * h + b
			walk[e] = walk_t[_terrain[k]]
			if walk[e] == 1:
				var l := clampi(floori(maxf(0.0, _height[k] - water_top - 0.03) / TTILES.TERRACE), 0, 20)
				if sky:
					l = maxi(l, 1)
				if mini(mini(i, j), mini(N - 1 - i, N - 1 - j)) < 3:
					l = 0
				lv[e] = l
	# Each tile to the commonest level round it (3 x 3), twice: tidy ledges.
	var cnt := PackedInt32Array()
	cnt.resize(32)
	for pass_ in 2:
		var tmp := lv.duplicate()
		for a in range(1, w - 1):
			for b in range(1, h - 1):
				var e := a * h + b
				if walk[e] == 0:
					continue
				var best := int(lv[e])
				var best_n := 0
				for da in [-1, 0, 1]:
					for db in [-1, 0, 1]:
						var q: int = (a + da) * h + b + db
						if walk[q] == 0:
							continue
						var v := int(lv[q])
						cnt[v] += 1
						if cnt[v] > best_n:
							best_n = cnt[v]
							best = v
				for da in [-1, 0, 1]:
					for db in [-1, 0, 1]:
						cnt[lv[(a + da) * h + b + db]] = 0
				tmp[e] = best if best_n >= 5 else lv[e]
		lv = tmp
	# Plots, spots and the landing site flat at the plots' level.
	for a in w:
		for b in h:
			var e := a * h + b
			if walk[e] == 1 and plot_cells.has(Vector2i(E.position.x + a, E.position.y + b)):
				lv[e] = plot_lvl
	for sp in clear_spots:
		var c0: Vector2i = sp[0]
		var rad := ceili(float(sp[1]) + 2.0)
		if not E.grow(rad).has_point(c0):
			continue
		var sl := plot_lvl if plot_cells.has(c0) else _level_at(c0)
		for dx in range(-rad, rad + 1):
			for dy in range(-rad, rad + 1):
				var q := c0 + Vector2i(dx, dy)
				if E.has_point(q) and Vector2(dx, dy).length() <= rad:
					var e := (q.x - E.position.x) * h + (q.y - E.position.y)
					if walk[e] == 1:
						lv[e] = sl
	var c0 := Vector2i(N / 2, N / 2)
	for a in w:
		for b in h:
			var q := E.position + Vector2i(a, b)
			if Vector2(q - c0).length() <= 10.0 and walk[a * h + b] == 1:
				lv[a * h + b] = plot_lvl
	# Ramps: here and there by nature, then where they link the chunk's ledges.
	var rd := PackedByteArray()
	rd.resize(w * h)
	for a in range(2, w - 2):
		for b in range(2, h - 2):
			var e := a * h + b
			var cell := E.position + Vector2i(a, b)
			if walk[e] == 0 or hash(cell * 7 + Vector2i(seed_, 3)) % 100 >= 9:
				continue
			for rr in range(1, 5):
				if _ramp_fits(a, b, rr, walk, lv, rd, w, h, cell):
					rd[e] = rr
					break
	_link(r, E, walk, lv, rd, w, h)
	# What the surface keeps: the chunk's own cells.
	var out := {"rect": r}
	var hh := PackedFloat32Array()
	var tt := PackedByteArray()
	var rp := PackedFloat32Array()
	var ll := PackedByteArray()
	var rr2 := PackedByteArray()
	var n := r.size.x * r.size.y
	hh.resize(n); tt.resize(n); rp.resize(n); ll.resize(n); rr2.resize(n)
	for a in r.size.x:
		for b in r.size.y:
			var i := r.position.x + a
			var j := r.position.y + b
			var k := i * N + j
			var e := (i - E.position.x) * h + (j - E.position.y)
			var o := a * r.size.y + b
			hh[o] = _height[k]
			tt[o] = _terrain[k]
			rp[o] = _ramp[k]
			ll[o] = lv[e]
			rr2[o] = rd[e]
	out["height"] = hh
	out["terrain"] = tt
	out["ramp"] = rp
	out["lvl"] = ll
	out["rampd"] = rr2
	out["tiles"] = _tiles(r, E, walk, lv, rd, w, h)
	out["map"] = _map(r, E, walk, lv, rd, w, h)
	out["fauna"] = _chunk_fauna(r, cx, cy)
	return out


## A cell's level as a chunk would make it (raw, then the 3 x 3 tidy twice) - for
## a clear spot whose centre lies in another chunk.
func _level_at(c: Vector2i) -> int:
	var E := Rect2i(c - Vector2i(2, 2), Vector2i(5, 5)).intersection(Rect2i(0, 0, N, N))
	ensure(E.grow(1))
	var lvls := {}
	var get_raw := func(q: Vector2i) -> int:
		var k := q.x * N + q.y
		if walk_t[_terrain[k]] == 0:
			return -1
		var l := clampi(floori(maxf(0.0, _height[k] - water_top - 0.03) / TTILES.TERRACE), 0, 20)
		if sky:
			l = maxi(l, 1)
		return l
	var cur := {}
	for i in range(E.position.x, E.end.x):
		for j in range(E.position.y, E.end.y):
			cur[Vector2i(i, j)] = get_raw.call(Vector2i(i, j))
	for pass_ in 2:
		var nxt := {}
		for q in cur:
			if cur[q] < 0:
				nxt[q] = -1
				continue
			var cn := {}
			var best: int = cur[q]
			var best_n := 0
			var full := true
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var p: Vector2i = q + Vector2i(dx, dy)
					if not cur.has(p):
						full = false
						continue
					if cur[p] < 0:
						continue
					cn[cur[p]] = cn.get(cur[p], 0) + 1
					if cn[cur[p]] > best_n:
						best_n = cn[cur[p]]
						best = cur[p]
			nxt[q] = best if full and best_n >= 5 else cur[q]
		cur = nxt
	return maxi(0, int(cur.get(c, plot_lvl)))


func _ramp_fits(a: int, b: int, rr: int, walk: PackedByteArray, lv: PackedByteArray, rd: PackedByteArray, w: int, h: int, cell: Vector2i) -> bool:
	var d: Vector2i = TTILES.RAMP_DIRS[rr]
	var side := Vector2i(d.y, d.x)
	for q in [Vector2i(a, b) + d, Vector2i(a, b) - d, Vector2i(a, b) + side, Vector2i(a, b) - side]:
		if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or walk[q.x * h + q.y] == 0:
			return false
	var l := lv[a * h + b]
	var hi := Vector2i(a, b) + d
	if lv[hi.x * h + hi.y] != l + 1 or rd[hi.x * h + hi.y] != 0:
		return false
	for q in [Vector2i(a, b) - d, Vector2i(a, b) + side, Vector2i(a, b) - side]:
		if lv[q.x * h + q.y] != l:
			return false
	return not plot_cells.has(cell)


func _step_ok(a: int, b: int, walk: PackedByteArray, lv: PackedByteArray, rd: PackedByteArray, h: int) -> bool:
	if walk[b] == 0:
		return false
	var la := lv[a]
	var lb := lv[b]
	var d := Vector2i(b / h - a / h, b % h - a % h)
	if la == lb:
		if rd[a] != 0 and _perp(TTILES.RAMP_DIRS[rd[a]], d):
			return false
		if rd[b] != 0 and _perp(TTILES.RAMP_DIRS[rd[b]], d):
			return false
		return true
	if lb == la + 1 and rd[a] != 0 and TTILES.RAMP_DIRS[rd[a]] == d:
		return true
	if la == lb + 1 and rd[b] != 0 and TTILES.RAMP_DIRS[rd[b]] == -d:
		return true
	return false


static func _perp(p: Vector2i, q: Vector2i) -> bool:
	return p.x * q.x + p.y * q.y == 0


## Within the chunk: from its biggest stretch of ground, a walk; where it meets
## land a level up or down it can't reach, a ramp goes in and the walk goes on -
## every ledge of the chunk linked where a ramp fits (the chunks round link
## theirs; ground carries over between them at the same level).
func _link(r: Rect2i, E: Rect2i, walk: PackedByteArray, lv: PackedByteArray, rd: PackedByteArray, w: int, h: int) -> void:
	var inside := func(e: int) -> bool:
		var q := E.position + Vector2i(e / h, e % h)
		return r.has_point(q)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var c0 := Vector2i(N / 2, N / 2)
	var start := -1
	if r.has_point(c0):
		start = (c0.x - E.position.x) * h + (c0.y - E.position.y)
	else:
		# (the start: the cell of the chunk's commonest level nearest its middle)
		var counts := {}
		for a in range(r.position.x - E.position.x, r.end.x - E.position.x):
			for b in range(r.position.y - E.position.y, r.end.y - E.position.y):
				var e := a * h + b
				if walk[e] == 1:
					counts[lv[e]] = counts.get(lv[e], 0) + 1
		var best := -1
		var best_n := -1
		for l in counts:
			if counts[l] > best_n:
				best_n = counts[l]
				best = l
		var mid := Vector2(r.get_center()) - Vector2(E.position)
		var best_d := INF
		for a in range(r.position.x - E.position.x, r.end.x - E.position.x):
			for b in range(r.position.y - E.position.y, r.end.y - E.position.y):
				var e := a * h + b
				if walk[e] == 1 and lv[e] == best:
					var dd := Vector2(a, b).distance_squared_to(mid)
					if dd < best_d:
						best_d = dd
						start = e
	if start < 0 or walk[start] == 0:
		return
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var cand := PackedInt32Array()
	var head := 0
	var ci := 0
	while true:
		while head < queue.size():
			var c := queue[head]
			head += 1
			var a := c / h
			var b := c % h
			for q in [c - h if a > 0 else -1, c + h if a < w - 1 else -1, c - 1 if b > 0 else -1, c + 1 if b < h - 1 else -1]:
				if q < 0 or seen[q] == 1 or walk[q] == 0 or not inside.call(q):
					continue
				if _step_ok(c, q, walk, lv, rd, h):
					seen[q] = 1
					queue.append(q)
				elif absi(int(lv[q]) - int(lv[c])) == 1:
					cand.append(c)
					cand.append(q)
		var made := false
		while ci < cand.size():
			var a2 := cand[ci]
			var b2 := cand[ci + 1]
			ci += 2
			if seen[b2] == 1:
				continue
			var lo := a2 if lv[a2] < lv[b2] else b2
			var hi := b2 if lo == a2 else a2
			var d := Vector2i(hi / h - lo / h, hi % h - lo % h)
			var rr := TTILES.RAMP_DIRS.find(d)
			if rr <= 0 or rd[lo] != 0 or rd[hi] != 0:
				continue
			rd[lo] = rr
			seen[b2] = 1
			queue.append(b2)
			made = true
			break
		if not made:
			break


## The chunk's tiles: (level, x, y, source) per tile placed - as PlanetSurface._tile_cells.
func _tiles(r: Rect2i, E: Rect2i, walk: PackedByteArray, lv: PackedByteArray, rd: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var src := {}
	for i in tile_pieces.size():
		src[tile_pieces[i]] = i
	var piece_of := {}
	for role in ["deep", "shallow", "shore_corner", "shore_left", "shore_right", "block_corner", "block_left", "block_right"] + TTILES.RAMP_PIECES.slice(1) + TTILES.RIMS:
		var pn := TTILES.pc(tile_set_id, role)
		if pn != "" and src.has(pn):
			piece_of[role] = src[pn]
	var kinds: Array = pdata["terrain"].map(func(t): return t[3])
	var wet := func(e: int) -> int:
		return 1 - walk[e]
	for i in range(r.position.x, r.end.x):
		for j in range(r.position.y, r.end.y):
			var a := i - E.position.x
			var b := j - E.position.y
			var e := a * h + b
			var l := int(lv[e])
			# (water nearby - 2 tiles, the cross - or land nearby, for water)
			var want: int = 1 - wet.call(e)
			var near := 0
			for o in [-2, -1, 1, 2]:
				if a + o >= 0 and a + o < w and wet.call((a + o) * h + b) == want:
					near = 1
				if b + o >= 0 and b + o < h and wet.call(a * h + b + o) == want:
					near = 1
			if wet.call(e) == 1:
				var wrole := "shallow" if near == 1 else "deep"
				if piece_of.has(wrole):
					_put(out, 0, i, j, piece_of[wrole])
				continue
			if rd[e] != 0:
				_put(out, l, i, j, piece_of[TTILES.RAMP_PIECES[rd[e]]])
				continue
			var low_r := _front_drop(e, i < N - 1 and a < w - 1, e + h, Vector2i(1, 0), l, walk, lv, rd)
			var low_l := _front_drop(e, j < N - 1 and b < h - 1, e + 1, Vector2i(0, 1), l, walk, lv, rd)
			if low_r >= 0 or low_l >= 0:
				var piece := "block_corner" if low_r >= 0 and low_l >= 0 else ("block_right" if low_r >= 0 else "block_left")
				var bottom := mini(low_r if low_r >= 0 else l, low_l if low_l >= 0 else l)
				for bb in range(bottom + 1, l + 1):
					_put(out, bb, i, j, piece_of[piece])
				continue
			var water_l: bool = i < N - 1 and a < w - 1 and wet.call(e + h) == 1
			var water_y: bool = j < N - 1 and b < h - 1 and wet.call(e + 1) == 1
			var back_l: bool = a > 0 and ((wet.call(e - h) == 0 and int(lv[e - h]) < l) or (sky and wet.call(e - h) == 1)) and rd[e - h] == 0
			var back_r: bool = b > 0 and ((wet.call(e - 1) == 0 and int(lv[e - 1]) < l) or (sky and wet.call(e - 1) == 1)) and rd[e - 1] == 0
			if (back_l or back_r) and not water_l and not water_y and piece_of.has("rim_l"):
				_put(out, l, i, j, piece_of["rim_lr" if back_l and back_r else ("rim_l" if back_l else "rim_r")])
			elif water_l and water_y and piece_of.has("shore_corner"):
				_put(out, l, i, j, piece_of["shore_corner"])
			elif water_y and piece_of.has("shore_left"):
				_put(out, l, i, j, piece_of["shore_left"])
			elif water_l and piece_of.has("shore_right"):
				_put(out, l, i, j, piece_of["shore_right"])
			else:
				var pn := TTILES.ground_piece(tile_set_id, kinds[_terrain[i * N + j]], l, near == 1, _n1.get_noise_2d(i, j), _n2.get_noise_2d(i, j))
				if src.has(pn):
					_put(out, l, i, j, src[pn])
	return out


static func _put(out: PackedInt32Array, l: int, i: int, j: int, s: int) -> void:
	out.append(l)
	out.append(i)
	out.append(j)
	out.append(s)


func _front_drop(e: int, inside: bool, q: int, d: Vector2i, l: int, walk: PackedByteArray, lv: PackedByteArray, rd: PackedByteArray) -> int:
	if not inside:
		return -1
	if walk[q] == 0:
		return 0 if sky and l > 0 else -1
	var lq := int(lv[q])
	if lq >= l:
		return -1
	if rd[q] != 0 and TTILES.RAMP_DIRS[rd[q]] == -d and lq == l - 1:
		return -1
	return lq


## The chunk's map pixels (the amber console look - PlanetSurface's map).
func _map(r: Rect2i, E: Rect2i, walk: PackedByteArray, lv: PackedByteArray, rd: PackedByteArray, w: int, h: int) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(r.size.x * r.size.y * 3)
	var tcol: Array = pdata["terrain"].map(func(x): return x[1])
	var first_land := 0
	while first_land < walk_t.size() and walk_t[first_land] == 0:
		first_land += 1
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var k := i * N + j
			var t: int = _terrain[k]
			var water := walk_t[t] == 0
			var coast := 0
			for d: Vector2i in NB4:
				var q := Vector2i(i, j) + d
				if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
					continue
				if (walk_t[_terrain[q.x * N + q.y]] == 0) != water:
					coast = 2 if absi(d.x) + absi(d.y) == 1 else maxi(coast, 1)
					if coast == 2:
						break
			var c: Color
			if water:
				c = MAP_SEA.lerp(MAP_SHALLOW, clampf(float(t) / maxf(1.0, first_land - 1.0), 0.0, 1.0))
				if i % MAP_GRID == 0 or j % MAP_GRID == 0:
					c = c.lerp(Color(0.1, 0.35, 0.45), 0.35)
				if coast > 0:
					c = c.lerp(Color(0.1, 0.5, 0.65), 0.55 if coast == 2 else 0.25)
			else:
				var e := (i - E.position.x) * h + (j - E.position.y)
				c = MAP_LAND.lerp(tcol[t], 0.42)
				var l := int(lv[e])
				c = c.darkened(0.35).lerp(MAP_ELEV_HIGH, 0.75 * float(l) / maxf(1.0, float(lvl_top)))
				if rd[e] != 0:
					c = c.lerp(Color(0.95, 0.9, 0.7), 0.6)
				else:
					var a := i - E.position.x
					var b := j - E.position.y
					for q in [e - h if a > 0 else -1, e + h if a < w - 1 else -1, e - 1 if b > 0 else -1, e + 1 if b < h - 1 else -1]:
						if q >= 0 and walk[q] == 1 and int(lv[q]) < l:
							c = c.darkened(0.5)
							break
				var hx := _height[mini(i + 12, N - 1) * N + j] - _height[maxi(i - 12, 0) * N + j]
				var hy := _height[i * N + mini(j + 12, N - 1)] - _height[i * N + maxi(j - 12, 0)]
				var sh := clampf(-(hx + hy) * 1.6, -1.0, 1.0)
				if sh > 0.45:
					c = c.lerp(MAP_LIT, (sh - 0.45) * 0.8)
				elif sh < 0.0:
					c = c.darkened(-sh * 0.35)
				if coast == 2:
					c = MAP_COAST
				elif coast == 1:
					c = c.lerp(MAP_COAST, 0.3)
			var px := ((j - r.position.y) * r.size.x + (i - r.position.x)) * 3
			bytes[px] = c.r8
			bytes[px + 1] = c.g8
			bytes[px + 2] = c.b8
	return Image.create_from_data(r.size.x, r.size.y, false, Image.FORMAT_RGB8, bytes)


## The chunk's own animals (the wild ones and those found anywhere): its share
## of the planet's herds, the same every time.
func _chunk_fauna(r: Rect2i, cx: int, cy: int) -> Array:
	var out := []
	var table: Array = SurfaceCreature.FAUNA.get(tile_set_id, [])
	if table.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([planet_id, "fauna", cx, cy])
	var share := float(r.size.x * r.size.y) / float(N * N)
	var towns: Array = [Vector2i(N / 2, N / 2)] + village_spots
	for row in table:
		if str(row[4]) == "village":
			continue
		var groups := float(int(row[1]) * SurfaceCreature.DENSITY) * share
		var n := floori(groups) + (1 if rng.randf() < groups - floorf(groups) else 0)
		for g in n:
			for attempt in 12:
				var c := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
				if c.x < 10 or c.y < 10 or c.x > N - 11 or c.y > N - 11 or plot_cells.has(c):
					continue
				if str(row[4]) == "wild" and towns.any(func(t): return Vector2(t).distance_to(Vector2(c)) < 30.0):
					continue
				if Vector2(c).distance_to(_cen) < 8.0 or walk_t[_terrain[c.x * N + c.y]] == 0:
					continue
				_herd(row, c, rng, out)
				break
	return out
