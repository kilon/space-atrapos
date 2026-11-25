extends RefCounted
## A planet surface's ground (PlanetSurface._generate_terrain; worker thread,
## static, touches no nodes): rugged land after the hills of Greece - ridged
## limestone mountains, rolling lowlands, rocky crags - and ONE body of water
## instead of pools everywhere: a coastline (with a few islets off it), a lake
## or a river (with fords), or islands (platforms). pdata "water" picks it ("coast", "lake", "river", "islands",
## "none"); otherwise the seed does. A planet without unwalkable ground (Kamares)
## has none.
##
## Returns {"height": PackedFloat32Array (-1..1, the terrain bands' scale),
## "rock": PackedByteArray (0..255)}: crags stand where rock >= ROCK_SOLID,
## after bilinear filtering - the ground shader draws them from the same
## bytes and PlanetSurface._ground_ok blocks them, so they match exactly.
##
## Elevation, after the limestone hills of Greece: TERRACES - flat ledges
## (tilted a little) one STEP above another, with a sheer cliff where the land
## climbs fast and a gentle slope where it climbs slowly; `ramp` (0..1 per
## tile) turns a cliff into a slope you can walk (around villages, the landing
## site, gates, and some by nature). Zero at the site height (building plots
## are levelled to it, at a ledge's foot - zero ramp or not), so buildings need no lifting; the water
## lies flat at its level; crags stand CRAG_H higher; elevation eases to the
## rim's level near the map's edge (the cube's brick sides).
## PlanetSurface computes it per tile (_compute_elev) into the ground texture;
## the ground shader lifts its mesh by it, lift_at lifts what stands on it,
## and tiles where it jumps (cliffs) are solid (_mark_cliffs).

const ROCK_SOLID := 0.4
const TERRACE := 0.2        # height (terrain units) from one ledge to the next
const STEP := 110.0            # px one ledge stands above the one below
const CLIFF_W := 0.12         # the part of a ledge's rise that is cliff (fast climbs: sheer)
const CLIFF_PX := 22.0        # px between neighbouring tiles that make a cliff (solid)
const CRAG_H := 72.0          # px a crag stands above the ground round it
const RIM := 10.0             # tiles over which elevation eases to the rim's
const ELEV_SCALE := 1000.0    # (elevation in the texture: px / this)


## Ledges: x in ledges -> the elevation in ledges (flat-ish, then the cliff).
static func terrace(x: float, ramp: float) -> float:
	var f := x - floorf(x)
	var s := 0.15 * f + 0.85 * smoothstep(1.0 - CLIFF_W, 1.0, f)
	return floorf(x) + lerpf(s, f, ramp)


## Screen px the ground is raised at a tile: height h, ramp, crag (0..1), grid point g.
static func elevation(h: float, ramp: float, crag: float, g: Vector2, n: int, water_top: float, site_h: float) -> float:
	var x := (maxf(h, water_top) - site_h) / TERRACE   # (the site height at a ledge's foot: 0 with or without a ramp)
	var e := STEP * terrace(x, ramp) + CRAG_H * smoothstep(ROCK_SOLID, 0.7, crag)
	var edge := minf(minf(g.x + 0.5, g.y + 0.5), minf(n - 0.5 - g.x, n - 0.5 - g.y))
	return lerpf(rim_lift(water_top, site_h), e, smoothstep(0.0, RIM, edge))


## The elevation at the map's rim: the water's level (or the site's, dry).
static func rim_lift(water_top: float, site_h: float) -> float:
	if water_top <= -1.0:
		return 0.0
	return STEP * terrace((water_top - site_h) / TERRACE, 0.0)


## The fine ground mesh near the camera (worker thread): a w x w-tile window,
## `sub` x `sub` quads per tile, in grid coordinates from (0, 0) - the shader
## places it (its origin follows the camera, in whole tiles) and lifts it.
## Triangles back to front, like ground_mesh.
static func window_mesh(w: int, sub: int) -> Array:
	var m := w * sub
	var verts := PackedVector2Array()
	verts.resize((m + 1) * (m + 1))
	for i in m + 1:
		for j in m + 1:
			verts[i * (m + 1) + j] = Vector2(i, j) / sub - Vector2(0.5, 0.5)
	var idx := PackedInt32Array()
	idx.resize(m * m * 6)
	var k := 0
	for s in 2 * m - 1:
		for i in range(maxi(0, s - m + 1), mini(s, m - 1) + 1):
			var j := s - i
			var a := i * (m + 1) + j
			var b := a + m + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = a + 1
			idx[k + 3] = a + 1; idx[k + 4] = b; idx[k + 5] = b + 1
			k += 6
	return [verts, idx]


## The ground mesh (worker thread): a vertex at every tile corner (grid
## coordinates -0.5 .. n - 0.5) in world space (`g2w`), triangles ordered back
## to front (by i + j) so nearer hills are drawn over the land behind them.
static func ground_mesh(n: int, g2w: Transform2D) -> Array:
	var verts := PackedVector2Array()
	verts.resize((n + 1) * (n + 1))
	for i in n + 1:
		for j in n + 1:
			verts[i * (n + 1) + j] = g2w * Vector2(i - 0.5, j - 0.5)
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var w := 0
	for s in 2 * n - 1:
		for i in range(maxi(0, s - n + 1), mini(s, n - 1) + 1):
			var j := s - i
			var a := i * (n + 1) + j
			var b := a + n + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = a + 1
			idx[w + 3] = a + 1; idx[w + 4] = b; idx[w + 5] = b + 1
			w += 6
	return [verts, idx]


static func generate(n: int, pdata: Dictionary, seed_: int) -> Dictionary:
	var th: Array = pdata["thresholds"]
	var terr: Array = pdata["terrain"]
	var wl := 0                          # the first walkable band
	while wl < terr.size() and not terr[wl][2]:
		wl += 1
	var water_mode: String = pdata.get("water", "")
	if wl == 0:
		water_mode = "none"
	elif water_mode == "":
		water_mode = ["coast", "lake", "river"][posmod(seed_, 3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7919 + 13

	# --- Relief: ridges (mountain crests), hills, and outcrop patches.
	var ridge := FastNoiseLite.new()
	ridge.seed = seed_
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	ridge.fractal_gain = 0.42
	ridge.frequency = 0.0065
	ridge.domain_warp_enabled = true
	ridge.domain_warp_amplitude = 30.0
	ridge.domain_warp_frequency = 0.01
	var hills := FastNoiseLite.new()
	hills.seed = seed_ + 1
	hills.fractal_octaves = 3
	hills.fractal_gain = 0.4
	hills.frequency = 0.011
	var crag := FastNoiseLite.new()
	crag.seed = seed_ + 2
	crag.fractal_octaves = 3
	crag.fractal_gain = 0.45
	crag.frequency = 0.028
	var bumps := FastNoiseLite.new()
	bumps.seed = seed_ + 5
	bumps.fractal_octaves = 2
	bumps.frequency = 0.07
	var wiggle := FastNoiseLite.new()
	wiggle.seed = seed_ + 3
	wiggle.fractal_octaves = 3
	wiggle.frequency = 0.008
	var meander := FastNoiseLite.new()     # (one octave: smooth bends)
	meander.seed = seed_ + 4
	meander.fractal_type = FastNoiseLite.FRACTAL_NONE
	meander.frequency = 0.007

	var rv := PackedFloat32Array()
	rv.resize(n * n)
	var crest := PackedFloat32Array()
	crest.resize(n * n)
	var lo := INF
	var hi := -INF
	var clo := INF
	var chi := -INF
	for i in n:
		for j in n:
			var c := ridge.get_noise_2d(i, j)
			var v := 0.62 * c + 0.38 * hills.get_noise_2d(i, j)
			rv[i * n + j] = v
			crest[i * n + j] = c
			lo = minf(lo, v); hi = maxf(hi, v)
			clo = minf(clo, c); chi = maxf(chi, c)

	# --- The water: a signed distance in cells (> 0 land, <= 0 water).
	var sd := PackedFloat32Array()
	sd.resize(n * n)
	sd.fill(1e6)
	var cen := Vector2(n / 2.0, n / 2.0)
	match water_mode:
		"coast":
			var dir := Vector2.from_angle(rng.randf() * TAU)
			var islets := []
			for k in rng.randi_range(2, 4):
				var along := Vector2(-dir.y, dir.x) * rng.randf_range(-0.38, 0.38) * n
				islets.append([cen + dir * rng.randf_range(0.37, 0.44) * n + along, rng.randf_range(6.0, 13.0)])
			for i in n:
				for j in n:
					var p := Vector2(i, j)
					var s := (p - cen).dot(dir) - 0.3 * n + n * (0.07 * wiggle.get_noise_2d(i, j) + 0.015 * crag.get_noise_2d(i * 2, j * 2))
					var d := -s
					for isl in islets:
						d = maxf(d, isl[1] * (1.0 + 0.45 * crag.get_noise_2d(i * 2, j * 2)) - p.distance_to(isl[0]))
					sd[i * n + j] = d
		"lake":
			var lc := cen + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.3) * n
			var rad := rng.randf_range(18.0, 30.0)
			var squash := Vector2(rng.randf_range(0.7, 1.0), rng.randf_range(0.7, 1.0))
			var rot := rng.randf() * PI
			for i in n:
				for j in n:
					var q := (Vector2(i, j) - lc).rotated(rot) / squash
					sd[i * n + j] = q.length() - rad * (1.0 + 0.3 * wiggle.get_noise_2d(i * 3, j * 3))
		"islands":
			# Platforms in the sky (gas giants): patches of land where a broad
			# noise is high, open air between - the landing site's patch
			# guaranteed, the map's rim open; causeways (bridges) link them.
			var isle := FastNoiseLite.new()
			isle.seed = seed_ + 21
			isle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			isle.frequency = 0.028
			isle.fractal_octaves = 2
			for i in n:
				for j in n:
					var p := Vector2(i, j)
					var d := (isle.get_noise_2d(i, j) - 0.08) * 40.0
					d = maxf(d, 22.0 - p.distance_to(cen))
					d = minf(d, float(mini(mini(i, j), mini(n - 1 - i, n - 1 - j))) - 5.0)
					sd[i * n + j] = d
		"river":
			# Across the map along u, meandering sideways, passing the landing
			# site at a distance; fords every so often.
			var u := Vector2.from_angle(rng.randf() * TAU)
			var side := Vector2(-u.y, u.x)
			var lat0 := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.2, 0.28) * n
			var amp := 0.12 * n
			var fords := []
			for k in 3:
				fords.append(rng.randf_range(-0.4, 0.4) * n)
			for i in n:
				for j in n:
					var p := Vector2(i, j) - cen
					var a := p.dot(u)
					var off := lat0 + amp * meander.get_noise_1d(a)
					var slope := amp * (meander.get_noise_1d(a + 1.0) - meander.get_noise_1d(a - 1.0)) * 0.5
					var hw := 3.2 + 1.2 * crag.get_noise_1d(a * 0.3)
					var d := absf(p.dot(side) - off) / sqrt(1.0 + slope * slope) - hw
					for f in fords:
						d = maxf(d, (3.0 - absf(a - f)) * 3.0)   # (a raised bridge, 6 tiles wide)
					sd[i * n + j] = d

	# --- Heights: water deepens away from its shore; land rises from the
	# shore (a beach band first) into the relief.
	var water_top: float = th[wl - 1] if wl > 0 else -1.0
	var land_lo: float = water_top + 0.012 if wl > 0 else -0.62
	if wl + 1 < terr.size() and terr[wl][3] == "sand":
		land_lo = th[wl] + 0.012                 # inland starts above the beach band
	var height := PackedFloat32Array()
	height.resize(n * n)
	var rock := PackedByteArray()
	rock.resize(n * n)
	for i in n:
		for j in n:
			var k := i * n + j
			var r := (rv[k] - lo) / maxf(hi - lo, 1e-5)
			r = pow(r, 1.7)                       # wide lowlands, steep mountains
			var inland := lerpf(land_lo, 0.8, r)
			# Rocky, uneven ground: knolls and hollows a few tiles across, more on high ground.
			inland += (0.01 + 0.015 * r) * bumps.get_noise_2d(i, j)
			var d := sd[k]
			var h: float
			if d <= 0.0:
				h = lerpf(water_top - 0.015, -0.78, smoothstep(0.0, 10.0, -d))
			else:
				h = lerpf(water_top + 0.012, inland, smoothstep(0.0, 30.0, d)) if wl > 0 else inland
			var dc := Vector2(i, j).distance_to(cen) / (n / 2.0)   # (the landing site: levelled by PlanetSurface)
			height[k] = clampf(h, -1.0, 1.0)
			# Crags: along the mountain crests and in outcrop patches on high ground,
			# not by water or the landing site.
			var cr := (crest[k] - clo) / maxf(chi - clo, 1e-5)
			var o := crag.get_noise_2d(i, j) * 0.5 + 0.5
			var rk := maxf(smoothstep(0.8, 0.87, cr) * smoothstep(0.4, 0.55, o) * smoothstep(0.2, 0.35, r), smoothstep(0.66, 0.72, o) * smoothstep(0.3, 0.5, r))
			rk *= smoothstep(3.0, 7.0, d) * smoothstep(0.14, 0.2, dc)
			rock[k] = clampi(roundi(rk * 255.0), 0, 255)
	_close_gaps(rock, n, 2)
	# Where ledges meet in slopes rather than cliffs by nature (patches).
	var rn := FastNoiseLite.new()
	rn.seed = seed_ + 6
	rn.frequency = 0.03
	var ramp := PackedFloat32Array()
	ramp.resize(n * n)
	for k in n * n:
		ramp[k] = smoothstep(0.0, 0.15, rn.get_noise_2d(k / n, k % n))   # (about half the land: plenty of ways between ledges)
		ramp[k] = maxf(ramp[k], 1.0 - smoothstep(8.0, 14.0, sd[k]))   # (shores: beaches and banks slope up)
	return {"height": height, "rock": rock, "ramp": ramp, "water": water_mode}


## Crags as solid blobs: fills the gullies, nooks and gaps narrower than about
## 2r + 1 tiles between them (a morphological closing of the solid cells,
## Chebyshev radius r) - narrow ground in a crag is no way through.
static func _close_gaps(rock: PackedByteArray, n: int, r: int) -> void:
	var grown := PackedByteArray()
	grown.resize(n * n)
	var near := PackedInt32Array()          # cells the dilation reached
	for k in n * n:
		if rock[k] < 102:
			continue
		var i := k / n
		var j := k % n
		for di in range(-r, r + 1):
			for dj in range(-r, r + 1):
				var a := i + di
				var b := j + dj
				if a >= 0 and b >= 0 and a < n and b < n and grown[a * n + b] == 0:
					grown[a * n + b] = 1
					near.append(a * n + b)
	for k in near:
		if rock[k] >= 102:
			continue
		var i := k / n
		var j := k % n
		var all := true
		for di in range(-r, r + 1):
			for dj in range(-r, r + 1):
				var a := i + di
				var b := j + dj
				if a < 0 or b < 0 or a >= n or b >= n or grown[a * n + b] == 0:
					all = false
					break
			if not all:
				break
		if all:
			rock[k] = 255


## Bilinear rock (0..1) at fractional grid coordinates, as the shader filters it.
static func rock_interp(rock: PackedByteArray, n: int, g: Vector2) -> float:
	var x0 := clampi(floori(g.x), 0, n - 1)
	var y0 := clampi(floori(g.y), 0, n - 1)
	var x1 := mini(x0 + 1, n - 1)
	var y1 := mini(y0 + 1, n - 1)
	var fx := clampf(g.x - x0, 0.0, 1.0)
	var fy := clampf(g.y - y0, 0.0, 1.0)
	var a := lerpf(rock[x0 * n + y0], rock[x1 * n + y0], fx)
	var b := lerpf(rock[x0 * n + y1], rock[x1 * n + y1], fx)
	return lerpf(a, b, fy) / 255.0
