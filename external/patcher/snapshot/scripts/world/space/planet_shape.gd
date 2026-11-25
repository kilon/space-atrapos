class_name PlanetShape
extends RefCounted
## A planet's ground in the 3D game (Cosmos): one height field over the whole
## sphere - `height(dir)` metres above (or below) its radius, the same for the
## planet seen from orbit and the ground under your feet (CosmosPlanet builds
## its terrain patches from it, finer as you come closer; the ship's and the
## walker's collisions read it too). Continents, ridged mountain ranges,
## craters (moons) and a sea level, by the planet's type and its PlanetGen
## look (the 2D game's: the same colours, water level, ice, lava, clouds).
## Thread-safe: the noises are only read (patches are built on workers).

const PX_TO_M := 10.0       # the 2D map's units -> metres (orbits, stations)
const SIZE_TO_R := 4.0      # a 2D planet's size (px across) -> its radius (m)

var radius := 3000.0
var amp := 80.0             # the relief's scale (m): continents +-amp, ranges up to ~2 amp more
var sea := 0                # 0 none, 1 water, 2 ice sheet, 3 lava
var kind := "rocky"         # rocky / gas
var look := {}              # PlanetGen params (colours etc.)
var ridges := 0.5
var craters := 0.0
var shift := 0.0            # the continents' noise below this is under the sea
## Level ground for the towns (CosmosTown): set_flats() once, before any
## ground is built (then only read - by the workers too). Packed: height()
## runs hundreds of times a frame.
var flats: Array = []
var _fdir := PackedVector3Array()   # each town's direction
var _fin := PackedFloat32Array()    # cos of its level part's angle
var _fout := PackedFloat32Array()   # cos of where it's blended back
var _fh := PackedFloat32Array()     # radius + its height
var _fclear := PackedFloat32Array() # cos of where nothing grows


## [unit dir, cos in, cos out, height, cos clear] per town.
func set_flats(list: Array) -> void:
	flats = list
	_fdir.clear()
	_fin.clear()
	_fout.clear()
	_fh.clear()
	_fclear.clear()
	for f in list:
		_fdir.append(f[0])
		_fin.append(float(f[1]))
		_fout.append(float(f[2]))
		_fh.append(radius + float(f[3]))
		_fclear.append(float(f[4]))


var _cont := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _crater := FastNoiseLite.new()
var _crumble := FastNoiseLite.new()   # (the carves' walls: rough, not a sphere's)


## The shape of a planet record ({type, template, variant, size, seed}).
static func of(rec: Dictionary) -> PlanetShape:
	var s := PlanetShape.new()
	s.look = PlanetGen.generate(str(rec.get("template", "barren")), int(rec.get("variant", 0)))
	_empire_tint(s.look, Galaxy.owner_of(str(rec.get("system", Galaxy.HOME))), str(rec.get("type", "moon")))
	s.radius = float(rec.get("size", 500.0)) * SIZE_TO_R
	var type := str(rec.get("type", "moon"))
	s.kind = "gas" if int(s.look.get("mode", 0)) == 1 or type == "gas_giant" else "rocky"
	var seed := int(rec.get("seed", 1))
	var ts := float(s.look.get("terrain_scale", 2.2))
	s.ridges = float(s.look.get("ridges", 0.5))
	s.craters = float(s.look.get("craters", 0.0))
	s.amp = s.radius * (0.022 + 0.012 * s.ridges)
	var wl := float(s.look.get("water_level", -1.0))
	match type:
		"ocean":
			s.sea = 1
		"ice":
			s.sea = 2
		"volcanic":
			s.sea = 3
			wl = 0.42
		_:
			s.sea = 1 if wl > 0.0 else 0
	s.shift = (wl - 0.5) * 0.9 if s.sea > 0 else -0.25
	for n: FastNoiseLite in [s._cont, s._ridge, s._mid, s._fine, s._crater]:
		n.seed = seed
		seed = seed * 7919 + 13
	s._cont.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	s._cont.frequency = ts * 0.5
	s._cont.fractal_type = FastNoiseLite.FRACTAL_FBM
	s._cont.fractal_octaves = 7
	s._cont.fractal_gain = 0.45
	s._cont.domain_warp_enabled = true
	s._cont.domain_warp_amplitude = 0.08 + 0.18 * float(s.look.get("warp", 0.5))
	s._cont.domain_warp_frequency = ts * 0.35
	# (the warp's own octaves: two, doubling - its defaults, five at x6 each,
	# warp the ground by tens of metres every 17 m: a field of needles)
	s._cont.domain_warp_fractal_octaves = 2
	s._cont.domain_warp_fractal_lacunarity = 2.0
	s._cont.domain_warp_fractal_gain = 0.5
	s._ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	s._ridge.frequency = ts * 0.8
	s._ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	s._ridge.fractal_octaves = 5
	s._ridge.fractal_gain = 0.45
	s._mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	s._mid.frequency = 1.0 / 240.0          # (metres) hills between the big octaves
	s._mid.fractal_type = FastNoiseLite.FRACTAL_FBM
	s._mid.fractal_octaves = 3
	s._fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	s._fine.frequency = 1.0 / 18.0          # (metres) the ground underfoot
	s._fine.fractal_type = FastNoiseLite.FRACTAL_FBM
	s._fine.fractal_octaves = 2
	s._crater.noise_type = FastNoiseLite.TYPE_CELLULAR
	s._crater.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	s._crater.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	s._crater.cellular_jitter = 0.85
	s._crater.frequency = float(s.look.get("crater_scale", 2.5)) * 2.2
	s._crater.fractal_type = FastNoiseLite.FRACTAL_NONE
	s._crumble.seed = s._crater.seed + 7
	s._crumble.frequency = 0.55
	s._crumble.fractal_octaves = 2
	return s


# --- Each empire's worlds -----------------------------------------------------------------
## The land of each empire's systems, a nudge on the planet type's own colours
## (PlanetGen's): soil and rock, the green lowlands (and the plants: `flora`,
## CosmosFlora), the beaches, the sea's shallows and deeps, the air. Minoa warm
## ochre and lush green over turquoise shallows; Athens pale limestone and
## silver-green olive by clear blue seas; Sparta rust-red earth, khaki grass,
## dark seas; Mycenae golden-brown and amber grass; Ionia dark soil, emerald,
## lapis seas; the Cyclades white-grey rock, dry scrub, aquamarine shallows;
## the Sea Peoples' ashen, scorched worlds.
const EMPIRE_LAND := {
	"minoa": {"soil": Color(0.64, 0.45, 0.22), "green": Color(0.12, 0.42, 0.14), "sand": Color(0.86, 0.73, 0.5),
		"shallow": Color(0.08, 0.74, 0.7), "deep": Color(0.02, 0.2, 0.34), "air": Color(0.45, 0.8, 1.0), "flora": Color(0.1, 0.44, 0.12)},
	"athens": {"soil": Color(0.78, 0.76, 0.7), "green": Color(0.44, 0.52, 0.4), "sand": Color(0.9, 0.88, 0.82),
		"shallow": Color(0.2, 0.56, 0.9), "deep": Color(0.03, 0.15, 0.46), "air": Color(0.5, 0.75, 1.0), "flora": Color(0.5, 0.58, 0.46)},
	"sparta": {"soil": Color(0.58, 0.24, 0.12), "green": Color(0.48, 0.45, 0.22), "sand": Color(0.72, 0.5, 0.34),
		"shallow": Color(0.08, 0.32, 0.42), "deep": Color(0.01, 0.05, 0.14), "air": Color(0.6, 0.66, 0.85), "flora": Color(0.5, 0.47, 0.22)},
	"mycenae": {"soil": Color(0.6, 0.44, 0.22), "green": Color(0.6, 0.5, 0.18), "sand": Color(0.88, 0.72, 0.42),
		"shallow": Color(0.16, 0.52, 0.58), "deep": Color(0.04, 0.13, 0.28), "air": Color(0.66, 0.74, 0.92), "flora": Color(0.66, 0.5, 0.16)},
	"ionia": {"soil": Color(0.22, 0.15, 0.1), "green": Color(0.05, 0.44, 0.22), "sand": Color(0.6, 0.54, 0.42),
		"shallow": Color(0.08, 0.32, 0.74), "deep": Color(0.03, 0.05, 0.34), "air": Color(0.42, 0.6, 1.0), "flora": Color(0.04, 0.48, 0.24)},
	"cyclades": {"soil": Color(0.86, 0.85, 0.82), "green": Color(0.52, 0.5, 0.34), "sand": Color(0.95, 0.93, 0.87),
		"shallow": Color(0.12, 0.84, 0.8), "deep": Color(0.02, 0.28, 0.42), "air": Color(0.55, 0.84, 1.0), "flora": Color(0.54, 0.52, 0.32)},
	"pirates": {"soil": Color(0.19, 0.17, 0.16), "green": Color(0.27, 0.25, 0.19), "sand": Color(0.4, 0.37, 0.34),
		"shallow": Color(0.16, 0.28, 0.3), "deep": Color(0.03, 0.06, 0.09), "air": Color(0.62, 0.58, 0.55), "flora": Color(0.25, 0.22, 0.16)},
}
## How far each planet type leans to its empire's land (an ice world stays
## icy, a volcanic one volcanic; the moons a faint touch, the giants none).
const EMPIRE_LEAN := {"ocean": 0.4, "ice": 0.18, "volcanic": 0.15, "moon": 0.07}


## Nudges PlanetGen look `L` (in place) towards `empire`'s land, by `type`.
static func _empire_tint(L: Dictionary, empire: String, type: String) -> void:
	var E: Dictionary = EMPIRE_LAND.get(empire, {})
	var k := float(EMPIRE_LEAN.get(type, 0.0))
	if E.is_empty() or k <= 0.0 or int(L.get("mode", 0)) == 1:
		return
	var green := type == "ocean"   # (the lowlands green: the sea worlds; the others' land is bare)
	var pairs := {"land_low": ["sand" if green else "soil", k * 0.9], "land_mid": ["green" if green else "soil", k],
		"land_high": ["soil", k], "land_peak": ["soil", k * 0.25], "biome_color": ["green" if green else "soil", k]}
	if type == "ocean":
		pairs["water_shallow"] = ["shallow", k * 1.1]
		pairs["water_deep"] = ["deep", k]
	for key in pairs:
		if L.has(key):
			L[key] = (L[key] as Color).lerp(E[pairs[key][0]], pairs[key][1])
	if L.has("atmosphere") and type != "volcanic":
		L["atmosphere"] = (L["atmosphere"] as Color).lerp(E["air"], k * 0.7)
	L["flora"] = E["flora"]
	L["flora_k"] = k * 1.3


## Metres above the radius at unit direction `d` (from the planet's centre) -
## the ground as it was made (what's dug out of it: the carves, `density`).
func height(d: Vector3) -> float:
	var h := raw_height(d)
	for i in _fdir.size():
		var c := d.dot(_fdir[i])
		if c > _fout[i]:   # (the town's plane, through its middle, flat - not round)
			h = lerpf(h, _fh[i] / c - radius, smoothstep(_fout[i], _fin[i], c))
	return h


# --- Dug ground: the carves --------------------------------------------------------------
## Digging (CosmosDeposits) carves spheres out of the solid ground - true 3D:
## pits, trenches, tunnels, overhangs. The ground is solid below the
## heightfield (height()) except inside a carve: `density` (> 0 air, < 0
## solid). Where they are, the ground's drawn by CosmosVoxels (its voxels
## meshed round the carves) and the heightfield isn't drawn inside them (the
## terrain shader's `cuts`). Each carve: its middle `top` m above the radius in
## direction `d`, `r` wide; kept per planet in the save (CosmosGame.extra
## "digs": [x, y, z, r, top] each - `saved`, the same Array, appended to).
## Looked up on the main thread through a hash of DIG_CELL cells (by their
## direction); the workers get snapshots (digs_near).
const DIG_CELL := 16.0
const DIG_MAX := 8000
const CRUMBLE := 0.35       # m: a carve's wall rough by up to this
var dig_n := 0
var _digs := PackedFloat64Array()    # per carve (6 floats): dir x y z, radius m, its middle's height m, (spare)
var _dig_hash := {}                  # Vector3i -> PackedInt32Array of carves
var saved: Array = []                # (the save's list)


## Carve a sphere `r` wide at `d` (unit), its middle `top` m above the radius -
## unless one's already within a fifth of `r` of it. Its index, or -1.
func dig(d: Vector3, r: float, top: float) -> int:
	var p := d * (radius + top)
	for k in _cell_digs(p):
		if _centre(k).distance_to(p) < r * 0.2:
			return -1
	if dig_n >= DIG_MAX:
		return -1
	add_dig(d, r, top)
	saved.append([snappedf(d.x, 0.000001), snappedf(d.y, 0.000001), snappedf(d.z, 0.000001), snappedf(r, 0.01), snappedf(top, 0.01)])
	return dig_n - 1


## A carve added as it is (loading the save).
func add_dig(d: Vector3, r: float, top: float) -> void:
	_digs.append_array([d.x, d.y, d.z, r, top, 0.0])
	var k := dig_n
	dig_n += 1
	var p := d * radius
	var lo := ((p - Vector3.ONE * (r + 2.0)) / DIG_CELL).floor()
	var hi := ((p + Vector3.ONE * (r + 2.0)) / DIG_CELL).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				var key := Vector3i(x, y, z)
				var l: PackedInt32Array = _dig_hash.get(key, PackedInt32Array())
				l.append(k)
				_dig_hash[key] = l


## Carve `k`'s middle (planet-local).
func _centre(k: int) -> Vector3:
	return Vector3(_digs[k * 6], _digs[k * 6 + 1], _digs[k * 6 + 2]) * (radius + _digs[k * 6 + 4])


func _cell_digs(p: Vector3) -> PackedInt32Array:
	var c := (p.normalized() * radius / DIG_CELL).floor()
	return _dig_hash.get(Vector3i(int(c.x), int(c.y), int(c.z)), PackedInt32Array())


## Any carve near planet-local `p` (main thread)?
func carved_near(p: Vector3) -> bool:
	return dig_n > 0 and not _cell_digs(p).is_empty()


## The carves near planet-local `p`, packed (6 floats each) - the main thread's lookup.
func _near_digs(p: Vector3) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in _cell_digs(p):
		out.append_array(_digs.slice(k * 6, k * 6 + 6))
	return out


## A snapshot of the carves within `reach` m of planet-local `p`, packed - for a worker.
func digs_near(p: Vector3, reach: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in dig_n:
		if _centre(k).distance_to(p) < reach + _digs[k * 6 + 3]:
			out.append_array(_digs.slice(k * 6, k * 6 + 6))
	return out


## Every carve within `reach` of `p`: [centre, r] (the terrain shader's cuts).
func cuts_near(p: Vector3, reach: float, most: int) -> Array:
	var out := []
	for k in dig_n:
		var c := _centre(k)
		var dd := c.distance_to(p)
		if dd < reach:
			out.append([dd, c, _digs[k * 6 + 3]])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out.slice(0, most)


## The ground at planet-local `p`: > 0 air (m to the surface, roughly), < 0
## solid - the heightfield's, then the carves `pk` (a worker's snapshot; none
## given: looked up here, main thread).
func density(p: Vector3, pk: Variant = null) -> float:
	var r0 := p.length()
	var dn := r0 - (radius + height(p / r0))
	var k: PackedFloat64Array = pk if pk != null else _near_digs(p)
	return carve(p, dn, k)


## Density `dn` at `p` with the carves `pk` cut out of it.
## A carve's wall in and out by up to CRUMBLE (a noise): rough, crumbled
## edges, not a ball's - the same for the voxels, the walker, the shader (its
## cut reaches CRUMBLE further).
func carve(p: Vector3, dn: float, pk: PackedFloat64Array) -> float:
	var nz := INF
	for i in range(0, pk.size(), 6):
		var c := Vector3(pk[i], pk[i + 1], pk[i + 2]) * (radius + pk[i + 4])
		var gap := pk[i + 3] + CRUMBLE - p.distance_to(c)
		if gap <= dn:
			continue   # (can't beat what's there even at its roughest)
		if nz == INF:
			nz = _crumble.get_noise_3dv(p) * CRUMBLE
		dn = maxf(dn, gap - CRUMBLE + nz)
	return dn


## The floor under planet-local `p` (m above the radius): down from a little
## over `p` to the first solid ground - into a pit, along a tunnel's floor;
## from inside the solid, up to where it ends (main thread).
func floor_below(p: Vector3) -> float:
	var u := p.normalized()
	var pk := _near_digs(p)
	var at := p + u * 0.6
	if density(at, pk) < 0.0:
		for k in 12:   # (in the rock: up out of it)
			at += u * 0.25
			if density(at, pk) >= 0.0:
				break
		return at.length() - radius
	var step := 0.3
	var lo := at
	for k in 80:
		var nx := lo - u * step
		if density(nx, pk) < 0.0:
			var hi := nx
			for q in 6:
				var mid := (lo + hi) * 0.5
				if density(mid, pk) < 0.0:
					hi = mid
				else:
					lo = mid
			return lo.length() - radius
		lo = nx
	return lo.length() - radius


## Planet-local `p` pushed out of the solid ground (along the way to air), `m` clear.
func push_out(p: Vector3, m: float) -> Vector3:
	var pk := _near_digs(p)
	for k in 6:
		var dn := density(p, pk)
		if dn >= m:
			return p
		var e := 0.15
		var g := Vector3(density(p + Vector3(e, 0, 0), pk) - density(p - Vector3(e, 0, 0), pk),
			density(p + Vector3(0, e, 0), pk) - density(p - Vector3(0, e, 0), pk),
			density(p + Vector3(0, 0, e), pk) - density(p - Vector3(0, 0, e), pk))
		if g.length() < 0.0001:
			g = p
		p += g.normalized() * (m - dn + 0.02)
	return p


## (Worker) Whether the carves `pk` cut the ground at `d` (its plants and boulders go).
func dug_here(d: Vector3, pk: PackedFloat64Array) -> bool:
	if pk.is_empty():
		return false
	var g := d * (radius + height(d))
	for i in range(0, pk.size(), 6):
		var c := Vector3(pk[i], pk[i + 1], pk[i + 2]) * (radius + pk[i + 4])
		if g.distance_to(c) < pk[i + 3] + CRUMBLE + 0.3:
			return true
	return false


## Ground built over (CosmosStructure: foundations, furniture set on the ground) -
## no boulders or plants: owner -> [cap dir, cap cos, dirs, cos each].
var _bare := {}
var _bare_list: Array = []


func set_bare(owner: String, dirs: PackedVector3Array, coss: PackedFloat32Array) -> void:
	if dirs.is_empty():
		_bare.erase(owner)
	else:
		var c := Vector3.ZERO
		for d in dirs:
			c += d
		c = c.normalized()
		var lo := 1.0
		for i in dirs.size():
			lo = minf(lo, cos(acos(clampf(c.dot(dirs[i]), -1.0, 1.0)) + acos(clampf(coss[i], -1.0, 1.0))))
		_bare[owner] = [c, lo, dirs, coss]
	_bare_list = _bare.values()   # (a new list: the workers reading the old one keep it)


func bare(d: Vector3) -> bool:
	for b in _bare_list:
		if d.dot(b[0]) < b[1]:
			continue
		var dirs: PackedVector3Array = b[2]
		var coss: PackedFloat32Array = b[3]
		for i in dirs.size():
			if d.dot(dirs[i]) > coss[i]:
				return true
	return false


## True where a town stands (no boulders or plants).
func cleared(d: Vector3) -> bool:
	for i in _fdir.size():
		if d.dot(_fdir[i]) > _fclear[i]:
			return true
	return false


## The land as the noises make it (before the towns' levelling).
func raw_height(d: Vector3) -> float:
	if kind == "gas":
		return 0.0
	var e := _cont.get_noise_3dv(d) - shift
	var m := _ridge.get_noise_3dv(d) * 0.5 + 0.5
	var h := e * amp
	# Mountain ranges on land, rising from the coasts inland.
	h += ridges * amp * 1.6 * m * m * m * smoothstep(-0.02, 0.3, e)
	if craters > 0.0:
		var c := _crater.get_noise_3dv(d) * 0.5 + 0.5      # 0 at a crater's middle
		var bowl := smoothstep(0.05, 0.45, c) - 1.0
		var rim := exp(-pow((c - 0.47) * 9.0, 2.0)) * 0.45
		h += craters * amp * 0.9 * (bowl + rim)
	var p := d * radius
	h += _mid.get_noise_3dv(p) * (2.5 + amp * 0.035)
	h += _fine.get_noise_3dv(p) * 1.4
	if sea > 0 and h < 0.0:
		h *= 0.55          # (gentler sea floors)
	elif sea > 0 and h < amp * 0.05:
		h *= lerpf(0.4, 1.0, h / (amp * 0.05))   # (beaches: flat near the shore)
	return h


## The ground's height at `d`, or the sea's (0) if that's above it.
func surface(d: Vector3) -> float:
	var h := height(d)
	return maxf(h, 0.0) if sea > 0 else h


## The highest the ground gets (m above the radius) - bounds, horizons.
func top() -> float:
	return amp * (1.0 + ridges * 1.7) + 12.0


## Unit cube face `f`'s axes: normal n, and u, v across it (u x v = n).
static func face_axes(f: int) -> Array:
	var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD][f]
	var u := Vector3(n.y, n.z, n.x)
	return [n, u, n.cross(u)]


## The direction of cube face point (a, b) in [-1, 1]^2 (the tangent warp
## evens the patches' sizes over the face).
static func face_dir(n: Vector3, u: Vector3, v: Vector3, a: float, b: float) -> Vector3:
	return (n + u * tan(a * PI * 0.25) + v * tan(b * PI * 0.25)).normalized()
