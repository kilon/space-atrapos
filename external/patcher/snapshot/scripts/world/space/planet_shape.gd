class_name PlanetShape
extends RefCounted
## A planet's ground in the 3D game (Cosmos): one height field over the whole
## sphere - `height(dir)` metres above (or below) its radius, the same for the
## planet seen from orbit and the ground under your feet (CosmosPlanet builds
## its terrain patches from it, finer as you come closer; the ship's and the
## walker's collisions read it too). Continents, ridged mountain ranges, long
## mountain chains, valleys and canyons, craters (moons) and a sea level, by the planet's type and its PlanetGen
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
## The land's big shapes (x amp; by the planet's type - TERRAIN): mountain
## chains (long belts of high peaks), valleys (a branching network, deepest in
## the high ground), canyons (narrow terraced gorges in the basins between the
## chains; below the sea: rivers - water, ice or lava).
var mountains := 0.0
var valleys := 0.0
var canyons := 0.0
## The abysses (sea worlds): deep sinkholes in the sea floor, walls in ledges -
## each its middle's direction, the cos of its reach, its radius (m), its floor (m).
var _ab_dir := PackedVector3Array()
var _ab_cos := PackedFloat32Array()
var _ab_r := PackedFloat32Array()
var _ab_floor := PackedFloat32Array()
## The caves: tunnels carved into the ground (the carves, like digging - drawn
## by CosmosVoxels, walked, swum) from a mouth in a hillside or an abyss's wall,
## down and branching, opening into chambers - one world with the surface, no
## instance of its own. Each {mouth (planet-local: the entrance's floor), way
## (unit: in), under (an abyss's: flooded), seed, chambers [[centre, r]...],
## deepest (index)}. Made with the shape (its seed): not saved.
var caves: Array = []
var cave_n := 0             # (the caves' carves)
var _cave_new: Array = []   # (made, not yet merged: make_caves on a worker, merge_caves on the main thread)
## The dungeons: under a gateway on level ground, deep enough for the ground to
## roof them everywhere - each {mouth (planet-local: the gateway's ground), way
## (unit: the passage down, along its rooms' x), seed, frame (planet-local:
## CosmosDungeon's), dir}; their rooms and corridors carved out as boxes
## (CosmosDungeon.boxes_of), the passage down to them as carves.
var dungeons: Array = []
var _dg_new: Array = []
var _dg_inv: Array = []                  # (planet-local -> each dungeon's own)
var _dg_c := PackedVector3Array()        # (its middle)
var _dg_reach := PackedFloat32Array()    # (round it, all of it)
var _dg_box: Array = []                  # (its boxes: PackedVector3Array of [centre, half size] pairs)
const DUNGEONS := 2
const DUNGEON_ROCK := 4.0   # m of rock at least over a dungeon's roof
var _cave_dig_new := PackedFloat64Array()   # (their carves: dir x y z, r, top, the ground's height)
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
var _belt := FastNoiseLite.new()      # mountain chains along its zero lines; basins far from them
var _valley := FastNoiseLite.new()    # (metres) valleys along its zero lines
var _canyon := FastNoiseLite.new()    # (metres, warped: winding) canyons along its zero lines

## [mountains, valleys, canyons] by planet type: the sea worlds green valleys
## between high ranges, the ice worlds deep glacial valleys, the volcanic ones
## jagged chains and lava gorges, the moons low ranges and long rilles.
const TERRAIN := {"ocean": [1.0, 1.0, 0.45], "ice": [0.9, 1.2, 0.4], "volcanic": [1.2, 0.5, 1.0], "moon": [0.55, 0.35, 0.8]}
const CANYON_W := 0.045     # a canyon's half-width in its noise (~25-35 m)
const LAND_CAVES := 3       # caves into the hillsides of a rocky world
const ABYSSES := 3          # abysses on a sea world's floor (a cave in the wall of each)
const CAVE_CARVES := 6000   # (the caves' carves at most)
const VALLEY_W := 0.11      # a valley's (~150 m)


## The shape of a planet record ({type, template, variant, size, seed}).
static func of(rec: Dictionary, with_caves := true) -> PlanetShape:
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
	var tk: Array = TERRAIN.get(type, [0.8, 0.8, 0.6])
	s.mountains = float(tk[0]) * (0.75 + 0.5 * s.ridges)
	s.valleys = float(tk[1])
	s.canyons = float(tk[2])
	for n: FastNoiseLite in [s._cont, s._ridge, s._mid, s._fine, s._crater, s._belt, s._valley, s._canyon]:
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
	s._belt.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	s._belt.frequency = ts * 0.42
	s._belt.fractal_type = FastNoiseLite.FRACTAL_FBM
	s._belt.fractal_octaves = 2
	s._belt.fractal_gain = 0.35
	s._valley.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	s._valley.frequency = 1.0 / 1500.0
	s._valley.fractal_type = FastNoiseLite.FRACTAL_FBM
	s._valley.fractal_octaves = 3
	s._valley.fractal_gain = 0.4
	s._canyon.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	s._canyon.frequency = 1.0 / 1100.0
	s._canyon.fractal_type = FastNoiseLite.FRACTAL_FBM
	s._canyon.fractal_octaves = 2
	s._canyon.fractal_gain = 0.3
	s._canyon.domain_warp_enabled = true
	s._canyon.domain_warp_amplitude = 160.0
	s._canyon.domain_warp_frequency = 1.0 / 700.0
	s._canyon.domain_warp_fractal_octaves = 1
	s._crumble.frequency = 0.55
	s._crumble.fractal_octaves = 2
	if s.kind == "rocky":
		s._make_abysses(int(rec.get("seed", 1)) * 13 + 5)
		s.cave_seed = int(rec.get("seed", 1)) * 29 + 11
		s.dungeon_seed = int(rec.get("seed", 1)) * 17 + 3   # (the old sites' seed: Cosmos.dungeons_of's)
		if with_caves:   # (else: make_caves on a worker - CosmosPlanet)
			s.make_caves()
			s.merge_caves()
	return s


# --- Abysses and caves --------------------------------------------------------------------

func _make_abysses(seed: int) -> void:
	if sea != 1:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tries := 0
	while _ab_dir.size() < ABYSSES and tries < 300:
		tries += 1
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h := raw_height(d)
		if h > -amp * 0.3:
			continue   # (out in the deep sea)
		var r := rng.randf_range(55.0, 85.0)
		var ok := true
		for i in _ab_dir.size():
			if _ab_dir[i].dot(d) > cos(600.0 / radius):
				ok = false
		if not ok:
			continue
		_ab_dir.append(d)
		_ab_cos.append(cos(r * 1.3 / radius))
		_ab_r.append(r)
		_ab_floor.append(-amp * rng.randf_range(1.8, 2.3))


var cave_seed := 0


## (Worker-safe: reads only the noises) The caves made - LAND_CAVES into
## hillsides (dry: above the sea), one into each abyss's wall - kept aside till
## merge_caves (the main thread) carves them.
func make_caves() -> void:
	if kind != "rocky":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = cave_seed
	var tries := 0
	var land := 0
	var dry := radius + 3.0 if sea in [1, 3] else -INF   # (a sea world's caves kept above its sea level)
	while land < LAND_CAVES and tries < 400:
		tries += 1
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h := raw_height(d)
		if sea > 0 and h < 22.0:
			continue
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := d.cross(t1)
		var e := 12.0 / radius
		var g := t1 * (raw_height((d + t1 * e).normalized()) - raw_height((d - t1 * e).normalized())) / 24.0 \
			+ t2 * (raw_height((d + t2 * e).normalized()) - raw_height((d - t2 * e).normalized())) / 24.0
		if g.length() < 0.3 or g.length() > 1.2:
			continue   # (a hillside: into it, level at first)
		var ok := true
		for c in _cave_new:
			if (c["mouth"] as Vector3).normalized().dot(d) > cos(500.0 / radius):
				ok = false
		if not ok:
			continue
		_cave(rng, d * (radius + h + 0.3), g.normalized(), false, dry)
		land += 1
	_make_dungeons()
	for i in _ab_dir.size():   # (in the abyss's wall, down by its floor: out under the sea floor)
		var a := _ab_dir[i]
		var t1 := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized().rotated(a, rng.randf() * TAU)
		var d := (a + t1 * (_ab_r[i] * 0.55 / radius)).normalized()
		_cave(rng, d * (radius + raw_height(d) + 2.5), t1, true, -INF)


## The dungeons' sites: level, dry ground away from the towns (the old
## sites' seed: the same places as before), each laid out (CosmosDungeon) and
## sunk under its gateway, the ground over all of it DUNGEON_ROCK thick at least.
func _make_dungeons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = dungeon_seed
	var tries := 0
	var k := 0
	var DG: GDScript = load("res://scripts/world/life/cosmos_dungeon.gd")
	while _dg_new.size() < DUNGEONS and tries < 600:
		tries += 1
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h := height(d)
		if sea > 0 and h < 2.0 or cleared(d):
			continue
		var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		if absf(height((d * radius + t * 10.0).normalized()) - h) > 2.5:
			continue
		var site_seed := rng.randi()
		k += 1
		if k % 2 == 1:
			continue   # (the old sites alternated with caves - in the ground now, their own)
		var way := t.rotated(d, rng.randf() * TAU)
		var dg := _sink(DG, d, h, way, site_seed)
		if not dg.is_empty():
			_dg_new.append(dg)


## A dungeon laid out under the gateway at `d` (its ground `h`), its passage
## down along `way`: its frame, its boxes - {} if it can't be (the sea over it).
func _sink(DG: GDScript, d: Vector3, h: float, way: Vector3, seed: int) -> Dictionary:
	var L: Dictionary = DG.layout(seed)
	var door: Vector3 = L["door"]
	var W: float = DG.CELL * float(L["n"])
	var mouth := d * (radius + h)
	var floor_h := h - 12.0
	var xf := Transform3D()
	for pass_ in 3:   # (deep enough under all of it: looked at again where it lands)
		var drop := h - floor_h
		var run := drop * 1.73 + 6.0   # (down at 30 degrees, the last 6 m level)
		var door_at := mouth + way * run
		door_at = door_at.normalized() * (radius + floor_h)
		var u := door_at.normalized()
		var f := (way - u * way.dot(u)).normalized()
		var bas := Basis(f, u, f.cross(u))
		xf = Transform3D(bas, door_at - bas * door)
		var low := INF
		for i in 6:
			for j in 6:
				var q := xf * Vector3(-2.0 + (W + 4.0) * i / 5.0, 0.0, -2.0 + (W + 4.0) * j / 5.0)
				low = minf(low, height(q.normalized()))
		if sea > 0 and low < 2.0:
			return {}   # (the sea over it)
		var want := minf(low - DG.H - 0.6 - DUNGEON_ROCK, h - 8.0)
		if sea > 0 and want < 1.0:
			return {}   # (its floor under the sea's level: the sea's face would cut through its rooms)
		if want >= floor_h - 0.5:
			break
		floor_h = want
	# The passage: from the gateway down to the doorway (2 m wide carves, floor at their bottom).
	var door_w := xf * door
	var u0 := door_w.normalized()
	var level := door_w - (xf.basis.x * 6.0)
	var r := 2.0
	var a := mouth - d * 0.5
	var steps := int(ceil(a.distance_to(level) / 1.0))
	for i in steps + 1:
		var p := a.lerp(level, float(i) / steps)
		_cave_dig(p + p.normalized() * r, r)
	for i in 7:
		var p := level.lerp(door_w, i / 6.0)
		_cave_dig(p + u0 * r, r)
	var boxes := PackedVector3Array()
	for b: AABB in DG.boxes_of(seed):
		boxes.append(b.get_center())
		boxes.append(b.size * 0.5)
	var centre := xf * Vector3(W * 0.5, DG.H * 0.5, W * 0.5)
	return {"mouth": mouth, "way": way, "seed": seed, "frame": xf, "dir": d, "boxes": boxes, "centre": centre, "reach": W * 0.75 + 6.0}


var dungeon_seed := 0


## (Main thread) The caves made carved into the ground.
func merge_caves() -> void:
	var a := _cave_dig_new
	for i in range(0, a.size(), 6):
		add_dig(Vector3(a[i], a[i + 1], a[i + 2]), a[i + 3], a[i + 4], a[i + 5])
	cave_n += a.size() / 6
	caves.append_array(_cave_new)
	_cave_new = []
	_cave_dig_new = PackedFloat64Array()
	if not _dg_new.is_empty():   # (the dungeons' boxes: new lists, whole - the workers read the old ones meanwhile)
		var inv := _dg_inv.duplicate()
		var cs := _dg_c.duplicate()
		var rs := _dg_reach.duplicate()
		var bx := _dg_box.duplicate()
		for dg in _dg_new:
			inv.append((dg["frame"] as Transform3D).affine_inverse())
			cs.append(dg["centre"])
			rs.append(dg["reach"])
			bx.append(dg["boxes"])
		_dg_box = bx
		_dg_inv = inv
		_dg_reach = rs
		_dg_c = cs
		dungeons.append_array(_dg_new)
		_dg_new = []


func _cave(rng: RandomNumberGenerator, at: Vector3, way: Vector3, under: bool, dry: float) -> void:
	var cave := {"mouth": at, "way": way, "under": under, "seed": rng.randi(), "chambers": []}
	_tunnel(rng, at, way, rng.randf_range(140.0, 220.0), 2.8, 3, dry, cave)
	var best := 0
	var deep := -INF
	for k in (cave["chambers"] as Array).size():
		var c: Vector3 = cave["chambers"][k][0]
		var dd := radius + raw_height(c.normalized()) - c.length()
		if dd > deep:
			deep = dd
			best = k
	cave["deepest"] = best
	var hall: Array = cave["chambers"][best]   # (the deepest: a hall - room to fight its lord)
	var hc: Vector3 = hall[0]
	var hr: float = hall[1]
	var hu := hc.normalized()
	var ht := hu.cross(Vector3.UP if absf(hu.y) < 0.9 else Vector3.RIGHT).normalized()
	for k in 5:
		_cave_dig(hc + ht.rotated(hu, k * TAU / 5.0 + rng.randf() * 0.5) * hr * 0.9 + hu * rng.randf_range(0.0, 2.0), hr * rng.randf_range(0.8, 1.0))
	hall[1] = hr * 1.6
	_cave_new.append(cave)


## A winding passage from `p` along `dir` (level for its first metres, then down
## to its depth and wandering there), `branches` side passages off it, a
## chamber at its end (a few overlapping carves).
func _tunnel(rng: RandomNumberGenerator, p: Vector3, dir: Vector3, length: float, r: float, branches: int, dry: float, cave: Dictionary) -> void:
	var went := 0.0
	var pitch := 0.0
	while went < length and _cave_dig_new.size() < CAVE_CARVES * 6:
		var u := p.normalized()
		var gh := raw_height(u)
		var depth := radius + gh - p.length()
		var want := 0.0
		if went > 10.0:
			want = -0.45 if depth < r + 6.0 else (-0.2 if depth < 28.0 else rng.randf_range(-0.12, 0.08))
		if p.length() - r < dry:
			want = 0.2
		pitch = lerpf(pitch, want, 0.25)
		var f := (dir - u * dir.dot(u)).normalized().rotated(u, rng.randfn(0.0, 0.09))
		dir = f
		var step := r * 0.55
		p += (f * cos(pitch) + u * sin(pitch)) * step
		r = clampf(r + rng.randfn(0.0, 0.12), 2.4, 3.4)
		_cave_dig(p, r, gh)   # (the ground's height a step back: near enough to know if it opens it)
		went += step
		if branches > 0 and went > 25.0 and rng.randf() < step / 55.0:
			branches -= 1
			var turn := rng.randf_range(0.6, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
			_tunnel(rng, p, f.rotated(u, turn), length * rng.randf_range(0.3, 0.55), r, 0, dry, cave)
	var u := p.normalized()
	var cr := rng.randf_range(5.0, 7.5)
	var c := p + u * (cr - r - 0.4)   # (its floor about the passage's)
	_cave_dig(c, cr)
	var t1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	for k in 3:
		var o := t1.rotated(u, rng.randf() * TAU) * cr * rng.randf_range(0.5, 0.8)
		_cave_dig(c + o + u * rng.randf_range(-0.5, 1.5), cr * rng.randf_range(0.6, 0.85))
	(cave["chambers"] as Array).append([c, cr])


func _cave_dig(p: Vector3, r: float, ground := NAN) -> void:
	var d := p.normalized()
	_cave_dig_new.append_array([d.x, d.y, d.z, r, p.length() - radius, raw_height(d) if is_nan(ground) else ground])


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
	if dig_n - cave_n >= DIG_MAX:
		return -1
	add_dig(d, r, top)
	saved.append([snappedf(d.x, 0.000001), snappedf(d.y, 0.000001), snappedf(d.z, 0.000001), snappedf(r, 0.01), snappedf(top, 0.01)])
	return dig_n - 1


## A carve added as it is (loading the save).
func add_dig(d: Vector3, r: float, top: float, ground := NAN) -> void:
	var opens := 1.0 if top + r + CRUMBLE + 0.6 > (height(d) if is_nan(ground) else ground) else 0.0   # (it breaks the ground's face: the heightfield cut there)
	_digs.append_array([d.x, d.y, d.z, r, top, opens])
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
	for i in _dg_c.size():   # (a dungeon's rooms)
		if p.distance_to(_dg_c[i]) < _dg_reach[i]:
			return true
	return dig_n > 0 and not _cell_digs(p).is_empty()


## The carves near planet-local `p`, packed (6 floats each) - the main thread's lookup.
func _near_digs(p: Vector3) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in _cell_digs(p):
		out.append_array(_digs.slice(k * 6, k * 6 + 6))
	return out


## A snapshot of the carves within `reach` m of planet-local `p`, packed - for a
## worker (`opening`: only those that break the ground's face - a patch's). From
## the hash's cells round it (thousands of carves: the caves).
func digs_near(p: Vector3, reach: float, opening := false) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if dig_n == 0:
		return out
	var q := p.normalized() * radius
	var lo := ((q - Vector3.ONE * reach) / DIG_CELL).floor()
	var hi := ((q + Vector3.ONE * reach) / DIG_CELL).floor()
	var seen := {}
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				var l = _dig_hash.get(Vector3i(x, y, z))
				if l == null:
					continue
				for k: int in l:
					if seen.has(k):
						continue
					seen[k] = true
					if opening and _digs[k * 6 + 5] < 0.5:
						continue
					if _centre(k).distance_to(p) < reach + _digs[k * 6 + 3]:
						out.append_array(_digs.slice(k * 6, k * 6 + 6))
	return out


## Every carve within `reach` of `p`: [distance, centre, r], nearest first, `most`
## of them (`opening`: only those breaking the ground's face - the terrain shader's cuts).
func cuts_near(p: Vector3, reach: float, most: int, opening := false) -> Array:
	var out := []
	for k in dig_n:
		if opening and _digs[k * 6 + 5] < 0.5:
			continue
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
	var cs := _dg_c   # (the dungeons' boxes: straight-walled, no crumble)
	for i in cs.size():
		if p.distance_to(cs[i]) < _dg_reach[i]:
			var l: Vector3 = (_dg_inv[i] as Transform3D) * p
			var bx: PackedVector3Array = _dg_box[i]
			for j in range(0, bx.size(), 2):
				var q := (l - bx[j]).abs() - bx[j + 1]
				var sd := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
				dn = maxf(dn, -sd)
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
	var hg := height(u)
	if p.length() > radius + hg + 0.6:
		p = u * (radius + hg)   # (high above: looked for from the ground's face down - a pit's floor; not 24 m under you in the air)
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
	var land := smoothstep(-0.02, 0.3, e)
	# Mountain ranges on land, rising from the coasts inland.
	h += ridges * amp * 1.6 * m * m * m * land
	var p := d * radius
	var mid := _mid.get_noise_3dv(p)
	# Mountain chains: long belts along the belt noise's zero lines, ridged
	# peaks on a broad rise - inland, the coasts left low (the towns' ground).
	var bn := _belt.get_noise_3dv(d)
	var belt := smoothstep(0.5, 0.92, 1.0 - absf(bn) * 3.2) * smoothstep(0.12, 0.42, e)
	if belt > 0.0:
		h += mountains * amp * belt * (0.5 + 2.6 * m * m + 0.35 * mid)
	# Valleys: wide U-shaped troughs, cut deepest into the high ground; dry
	# on the sea worlds (their floors kept above the shore).
	if valleys > 0.0 and h > 0.0:
		var v := absf(_valley.get_noise_3dv(p))
		if v < VALLEY_W:
			var u := smoothstep(VALLEY_W, VALLEY_W * 0.2, v)
			var cut := valleys * u * (amp * 0.05 + 0.72 * maxf(h - amp * 0.15, 0.0))   # (shallow in the lowlands, deep in the heights)
			h = maxf(h - cut, minf(h, 4.0)) if sea > 0 else h - cut
	# Canyons: narrow, winding, steep walls in ledges, flat floors - in the
	# basins between the chains; their floors below the sea: rivers.
	var cm := canyons * land * smoothstep(0.3, 0.55, absf(bn)) * (1.0 - belt)
	if sea == 1 and e < 0.0:   # (and on the sea floor: trenches out across it)
		cm = maxf(cm, canyons * smoothstep(0.0, -0.12, e) * smoothstep(0.2, 0.45, absf(bn)) * 1.2)
	if cm > 0.0:
		var c := absf(_canyon.get_noise_3dv(p))
		if c < CANYON_W:
			var t := clampf((CANYON_W - c) / (CANYON_W * 0.75), 0.0, 1.0)   # 0 at the rim, 1 on the floor
			var k := t * 3.0
			var f := minf(floorf(k), 2.0)
			var step := (f + smoothstep(0.35, 1.0, k - f)) / 3.0             # (ledges)
			var cut := cm * step * (amp * 0.7 + 0.5 * maxf(h, 0.0))
			h = maxf(h - cut, minf(h, -amp * 0.06)) if sea > 0 and h > -amp * 0.06 else h - cut   # (on land a river's depth; the sea floor's: all of it)
	if craters > 0.0:
		var c := _crater.get_noise_3dv(d) * 0.5 + 0.5      # 0 at a crater's middle
		var bowl := smoothstep(0.05, 0.45, c) - 1.0
		var rim := exp(-pow((c - 0.47) * 9.0, 2.0)) * 0.45
		h += craters * amp * 0.9 * (bowl + rim)
	h += mid * (2.5 + amp * 0.035)
	h += _fine.get_noise_3dv(p) * 1.4
	if sea > 0 and h < 0.0:
		h *= 0.55          # (gentler sea floors)
	elif sea > 0 and h < amp * 0.05:
		h *= lerpf(0.4, 1.0, h / (amp * 0.05))   # (beaches: flat near the shore)
	for i in _ab_dir.size():   # (the abysses: down in ledges to their floors, a low lip round them)
		if d.dot(_ab_dir[i]) > _ab_cos[i]:
			var t := (d - _ab_dir[i]).length() * radius / _ab_r[i]   # (0 its middle, 1 its rim)
			var k := clampf((1.0 - t) / 0.35, 0.0, 1.0) * 4.0
			var f := minf(floorf(k), 3.0)
			var step := (f + smoothstep(0.4, 1.0, k - f)) / 4.0
			var lip := exp(-pow((t - 1.06) * 7.0, 2.0)) * amp * 0.06
			h = lerpf(h + lip, _ab_floor[i] + mid * amp * 0.03, step)
	return h


## The ground's height at `d`, or the sea's (0) if that's above it.
func surface(d: Vector3) -> float:
	var h := height(d)
	return maxf(h, 0.0) if sea > 0 else h


## The highest the ground gets (m above the radius) - bounds, horizons.
func top() -> float:
	return amp * (1.0 + ridges * 1.7 + mountains * 3.1) + 12.0


## Unit cube face `f`'s axes: normal n, and u, v across it (u x v = n).
static func face_axes(f: int) -> Array:
	var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD][f]
	var u := Vector3(n.y, n.z, n.x)
	return [n, u, n.cross(u)]


## The direction of cube face point (a, b) in [-1, 1]^2 (the tangent warp
## evens the patches' sizes over the face).
static func face_dir(n: Vector3, u: Vector3, v: Vector3, a: float, b: float) -> Vector3:
	return (n + u * tan(a * PI * 0.25) + v * tan(b * PI * 0.25)).normalized()
