class_name PlanetWeather
extends RefCounted
## A world's weather (the 3D game): local, not global - weather systems (cells)
## each over its own part of the world, drifting round it on its own path at its
## own pace, growing, raining (or snowing, or ash falling) and dying away in
## their own time, then coming back elsewhere on their path. A pure function of
## the world's seed and the galaxy's clock (Galaxy.time): the same storm in the
## same place for anyone, after a save too. Read by the clouds (thick and dark
## under a cell), the ground (wet, muddy, snow lying - the last of it lingering
## after the cell's gone on), the rain / snow / ash round you and the storms'
## lightning (CosmosWeatherFx), and the HUD's readout: the weather, the
## temperature, the radioactivity where you are.

const CELLS := 8                # (the shaders' arrays)
const KINDS := ["clear", "cloudy", "rain", "storm", "snow", "blizzard", "ash", "ash storm"]

var kind := "none"              # what falls: "rain" (snow where it's cold), "snow", "ash", "none" (no air)
var type := "moon"
var air := false
var radius := 1000.0
var cells: Array = []           # [{home, axis, w (rad/s), r (rad), period (s), offset, storm}]
var base_temp := 15.0
var base_rad := 0.15            # µSv/h
var shape: PlanetShape


## The weather of a world (its record, its shape): nothing on a world without air.
static func of(rec: Dictionary, sh: PlanetShape, has_air: bool) -> PlanetWeather:
	var w := PlanetWeather.new()
	w.shape = sh
	w.radius = sh.radius
	w.type = str(rec.get("type", "moon"))
	w.air = has_air and sh.kind == "rocky"
	match w.type:
		"ocean":
			w.base_temp = 17.0
			w.base_rad = 0.12
		"ice":
			w.base_temp = -16.0
			w.base_rad = 0.18
		"volcanic":
			w.base_temp = 46.0
			w.base_rad = 0.65
		"gas_giant":
			w.base_temp = -120.0
			w.base_rad = 2.0
		_:
			w.base_temp = 10.0
			w.base_rad = 30.0   # (an airless moon: the star's and the sky's rays, unshielded)
	if not w.air:
		return w
	w.kind = "ash" if w.type == "volcanic" else ("snow" if w.type == "ice" else "rain")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec.get("seed", 1)) * 101 + 7
	var n: int = {"ocean": 7, "ice": 6, "volcanic": 5}.get(w.type, 5)
	for i in n:
		var home := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var axis := home.cross(Vector3(rng.randfn(), rng.randfn(), rng.randfn())).normalized()
		var r_m := rng.randf_range(0.28, 0.42) * w.radius   # (its reach, m: wide enough that under it the clouds you see are its own)
		var speed := rng.randf_range(0.8, 2.2)   # m/s across the ground
		w.cells.append({"home": home, "axis": axis, "w": speed / w.radius, "r": r_m / w.radius,
			"period": rng.randf_range(700.0, 1300.0), "offset": rng.randf(), "storm": rng.randf() < 0.45})
	return w


## Cell `i` at time `t`: [its middle (unit), its reach (rad), how strong (0..1: building,
## raining, dying away), how wet it's left the ground under it, how much snow lies there].
func cell(i: int, t: float) -> Array:
	var c: Dictionary = cells[i]
	var dir: Vector3 = (c["home"] as Vector3).rotated(c["axis"], fposmod(float(c["w"]) * t, TAU))
	var p := fposmod(t / float(c["period"]) + float(c["offset"]), 1.0)
	# (its life: 0 - 0.55 there, strongest mid-way; after it, what it left on the ground fading)
	var strong := pow(sin(PI * clampf(p / 0.55, 0.0, 1.0)), 2.0) if p < 0.55 else 0.0
	var wet := smoothstep(0.05, 0.22, p) if p < 0.55 else 1.0 - smoothstep(0.55, 0.85, p)
	var snow := smoothstep(0.1, 0.4, p) if p < 0.55 else 1.0 - smoothstep(0.6, 0.98, p)
	return [dir, float(c["r"]) * (0.6 + 0.4 * strong + 0.2 * wet), strong, wet, snow]


## The temperature (°C) at `d` (unit, planet-local) - its latitude, its height, the sun
## over it (`sun`: the way to the star), the weather over it (`cover`, `precip` 0..1).
func temperature(d: Vector3, sun: Vector3, cover := 0.0, precip := 0.0) -> float:
	var h := shape.height(d) if shape else 0.0
	var e := d.dot(sun)
	if not air:   # (no air: blazing in the sun, bitter out of it)
		return base_temp + (110.0 * maxf(e, 0.0) - 150.0 * (1.0 - maxf(e, 0.0)) * smoothstep(0.0, 0.3, -e + 0.2))
	var t := base_temp - 26.0 * pow(absf(d.y), 1.5) - maxf(h, 0.0) * 0.022
	t += 7.0 * clampf(e, -1.0, 1.0) * (1.0 - 0.6 * cover)
	return t - 5.0 * precip


## The radioactivity (µSv/h) at `d`: the world's own, the sky's - more high up and in the sun where the air's thin.
func radiation(d: Vector3, sun: Vector3) -> float:
	var h := shape.height(d) if shape else 0.0
	var e := maxf(d.dot(sun), 0.0)
	if not air:
		return base_rad * (0.6 + 0.8 * e)
	return base_rad * (1.0 + maxf(h, 0.0) / 600.0) * (0.9 + 0.2 * e)


## The weather at `d` (unit, planet-local) at time `t`, the sun towards `sun`:
## {cover 0..1, precip 0..1, storm 0..1, wet, snow (lying), state (KINDS), temp °C, rad µSv/h, falls ("rain", "snow", "ash")}.
func at(d: Vector3, t: float, sun: Vector3) -> Dictionary:
	var cover := 0.0
	var precip := 0.0
	var storm := 0.0
	var wet := 0.0
	var snow_lying := 0.0
	var cold_at := 0.0
	for i in cells.size():
		var s := cell(i, t)
		var k := _reach(d, s[0], s[1])
		if k <= 0.0:
			continue
		var strong: float = s[2]
		cover = maxf(cover, k * (0.35 + 0.65 * strong))
		var fall := k * smoothstep(0.25, 0.6, strong)
		precip = maxf(precip, fall)
		if cells[i]["storm"]:
			storm = maxf(storm, fall * smoothstep(0.6, 0.9, strong))
		wet = maxf(wet, _reach(d, s[0], float(s[1]) * 1.25) * float(s[3]))
		snow_lying = maxf(snow_lying, _reach(d, s[0], float(s[1]) * 1.2) * float(s[4]))
	var temp := temperature(d, sun, cover, precip)
	var falls := kind
	if kind == "rain" and temp < 0.5:
		falls = "snow"
	elif kind == "snow" and temp > 2.0:
		falls = "rain"
	if falls != "snow":
		snow_lying *= clampf(1.0 - temp / 4.0, 0.0, 1.0)   # (melted where it's warm)
	if falls == "snow" or kind == "ash":
		wet *= 0.3
	var state := "clear"
	if not air:
		state = "clear"
	elif precip > 0.08:
		match falls:
			"snow": state = "blizzard" if storm > 0.3 else "snow"
			"ash": state = "ash storm" if storm > 0.3 else "ash"
			_: state = "storm" if storm > 0.3 else "rain"
	elif cover > 0.35:
		state = "cloudy"
	return {"cover": cover, "precip": precip, "storm": storm, "wet": wet, "snow": snow_lying, "state": state,
		"temp": temp, "rad": radiation(d, sun), "falls": falls}


## (0 outside the cell's reach, 1 well inside: soft edged.)
static func _reach(d: Vector3, mid: Vector3, r: float) -> float:
	var a := acos(clampf(d.dot(mid), -1.0, 1.0))
	return 1.0 - smoothstep(r * 0.45, r, a)


## The cells for the shaders at time `t`: [[Vector4 (middle, reach)...], [Vector4 (strength,
## wet, snow lying, storm)...]] - CELLS of each (the rest empty).
func shader_cells(t: float, sun: Vector3) -> Array:
	var a := PackedVector4Array()   # (a shader's vec4[])
	var b := PackedVector4Array()
	for i in CELLS:
		if i < cells.size():
			var s := cell(i, t)
			var mid: Vector3 = s[0]
			var temp := temperature(mid, sun)
			var cold := (kind == "snow" and temp < 2.0) or (kind == "rain" and temp < 0.5)
			var snow: float = float(s[4]) if cold else 0.0   # (snow lies only where it's cold enough to fall as snow)
			var wet: float = float(s[3]) * (0.3 if kind == "ash" else 1.0)
			a.append(Vector4(mid.x, mid.y, mid.z, float(s[1])))
			b.append(Vector4(float(s[2]), wet, snow, 1.0 if cells[i]["storm"] else 0.0))
		else:
			a.append(Vector4(0, 1, 0, 0))
			b.append(Vector4.ZERO)
	return [a, b]
