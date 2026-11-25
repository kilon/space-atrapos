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

var _cont := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _mid := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _crater := FastNoiseLite.new()


## The shape of a planet record ({type, template, variant, size, seed}).
static func of(rec: Dictionary) -> PlanetShape:
	var s := PlanetShape.new()
	s.look = PlanetGen.generate(str(rec.get("template", "barren")), int(rec.get("variant", 0)))
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
	return s


## Metres above the radius at unit direction `d` (from the planet's centre).
func height(d: Vector3) -> float:
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
