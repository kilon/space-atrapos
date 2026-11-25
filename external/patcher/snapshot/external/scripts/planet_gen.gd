class_name PlanetGen
## Procedural planets (shaders/planet.gdshader) built from seven templates,
## modelled on the reference planets in external/images/planet_refs/:
##   alien      - jagged rock, glowing teal seas, rust deserts      (ref 1)
##   glacier    - snow-capped ranges, blue ice and dark seas         (ref 2)
##   ocean      - deep oceans, island chains, clouds and a cyclone   (ref 3)
##   inferno    - black crust split by lava rivers, smoke            (ref 4)
##   barren     - cratered, dusty rock                               (ref 5)
##   storm_giant  - turbulent banded giant with a great storm        (ref 6)
##   ringed_giant - calm banded giant with bright rings              (ref 7)
## generate(template, variant) mixes them: variant 0 is the template itself;
## every other variant borrows features from the other templates (craters,
## ice caps, glowing seas, lava, cyclones, rings...), shifts the palette
## around the colour wheel (golden-ratio steps, so variants never repeat a
## hue) and jitters the shapes - so every planet is visually distinct.

const SHADER := preload("res://shaders/planet.gdshader")
const DISK := 0.86

const ROCKY := ["alien", "glacier", "ocean", "inferno", "barren"]
const GIANTS := ["storm_giant", "ringed_giant"]

## Template parameters (shader uniforms) + "name" and "hue_range" (how far
## variants may rotate the palette: 1 = anywhere on the colour wheel).
const TEMPLATES := {
	"alien": {"name": "Alien world", "hue_range": 1.0, "mode": 0,
		"terrain_scale": 2.8, "warp": 0.8, "ridges": 0.95, "relief": 1.4,
		"land_low": Color(0.17, 0.16, 0.15), "land_mid": Color(0.3, 0.27, 0.24), "land_high": Color(0.44, 0.41, 0.39), "land_peak": Color(0.86, 0.87, 0.89),
		"biome": 0.85, "biome_scale": 1.4, "biome_color": Color(0.72, 0.38, 0.17),
		"water_level": 0.37, "water_shallow": Color(0.14, 0.86, 0.74), "water_deep": Color(0.02, 0.3, 0.33), "water_glow": 0.45,
		"ice_cover": 0.12, "clouds": 0.12, "cloud_scale": 2.6,
		"atmosphere": Color(0.4, 0.78, 0.9), "atmo_strength": 0.55},
	"glacier": {"name": "Glacier world", "hue_range": 0.18, "mode": 0,
		"terrain_scale": 2.4, "warp": 0.55, "ridges": 0.92, "relief": 1.3,
		"land_low": Color(0.2, 0.24, 0.3), "land_mid": Color(0.32, 0.36, 0.43), "land_high": Color(0.2, 0.22, 0.27), "land_peak": Color(0.93, 0.96, 1.0),
		"water_level": 0.42, "water_shallow": Color(0.38, 0.65, 0.8), "water_deep": Color(0.05, 0.16, 0.32),
		"ice_cover": 0.42, "ice_color": Color(0.88, 0.94, 1.0), "clouds": 0.3, "cloud_scale": 2.2,
		"atmosphere": Color(0.55, 0.8, 1.0), "atmo_strength": 0.7},
	"ocean": {"name": "Ocean world", "hue_range": 0.14, "mode": 0,
		"terrain_scale": 1.8, "warp": 0.6, "ridges": 0.4, "relief": 0.9,
		"land_low": Color(0.72, 0.67, 0.48), "land_mid": Color(0.28, 0.48, 0.24), "land_high": Color(0.33, 0.31, 0.26), "land_peak": Color(0.82, 0.82, 0.8),
		"water_level": 0.64, "water_shallow": Color(0.1, 0.56, 0.62), "water_deep": Color(0.03, 0.14, 0.36), "water_glow": 0.12,
		"clouds": 0.62, "cloud_scale": 2.4, "cyclone": 1.0, "cyclone_dir": Vector3(0.35, 0.45, 0.82),
		"atmosphere": Color(0.4, 0.7, 1.0), "atmo_strength": 0.85},
	"inferno": {"name": "Lava world", "hue_range": 0.1, "mode": 0,
		"terrain_scale": 2.2, "warp": 0.6, "ridges": 0.75, "relief": 1.3,
		"land_low": Color(0.12, 0.08, 0.07), "land_mid": Color(0.2, 0.15, 0.13), "land_high": Color(0.3, 0.25, 0.22), "land_peak": Color(0.42, 0.38, 0.35),
		"lava": 1.0, "lava_scale": 2.4, "lava_color": Color(1.0, 0.32, 0.05), "lava_hot": Color(1.0, 0.85, 0.4),
		"clouds": 0.3, "cloud_scale": 3.0, "cloud_color": Color(0.24, 0.21, 0.21),
		"atmosphere": Color(1.0, 0.45, 0.15), "atmo_strength": 0.55},
	"barren": {"name": "Cratered world", "hue_range": 0.5, "mode": 0,
		"terrain_scale": 2.0, "warp": 0.45, "ridges": 0.55, "relief": 1.5,
		"land_low": Color(0.3, 0.26, 0.23), "land_mid": Color(0.5, 0.41, 0.34), "land_high": Color(0.62, 0.58, 0.55), "land_peak": Color(0.78, 0.76, 0.72),
		"craters": 1.0, "crater_scale": 2.0, "biome": 0.5, "biome_scale": 1.2, "biome_color": Color(0.56, 0.3, 0.18),
		"atmosphere": Color(0.6, 0.55, 0.5), "atmo_strength": 0.22},
	"storm_giant": {"name": "Storm giant", "hue_range": 1.0, "mode": 1,
		"gas_a": Color(0.85, 0.78, 0.68), "gas_b": Color(0.25, 0.38, 0.56), "gas_c": Color(0.95, 0.92, 0.88), "gas_d": Color(0.86, 0.45, 0.17),
		"band_count": 9.0, "band_turb": 1.0, "storm": 1.0, "storm_pos": Vector2(1.9, -0.38), "storm_size": 0.2,
		"storm_color": Color(0.95, 0.5, 0.2), "atmosphere": Color(0.6, 0.75, 0.95), "atmo_strength": 0.6},
	"ringed_giant": {"name": "Ringed giant", "hue_range": 1.0, "mode": 1,
		"gas_a": Color(0.88, 0.76, 0.55), "gas_b": Color(0.72, 0.58, 0.4), "gas_c": Color(0.96, 0.9, 0.75), "gas_d": Color(0.6, 0.45, 0.3),
		"band_count": 8.0, "band_turb": 0.25, "storm": 0.35, "storm_pos": Vector2(1.2, -0.3), "storm_size": 0.1,
		"storm_color": Color(0.82, 0.62, 0.38), "rings": 1.0, "ring_inner": 1.3, "ring_outer": 2.2,
		"ring_a": Color(0.88, 0.8, 0.68), "ring_b": Color(0.5, 0.45, 0.4), "incline": 0.3, "tilt": -0.18,
		"atmosphere": Color(1.0, 0.9, 0.7), "atmo_strength": 0.4},
}

## The editable properties (the zoo's property panel builds itself from
## these): [key, label, type, min, max, help, modes ([] = both; [0] rocky,
## [1] gas giant)]. Types: float, int, color, vec2, vec3, enum:<a>,<b>.
const PROPERTIES := [
	["#", "Type and view"],
	["mode", "Type", "enum:Rocky world,Gas giant", 0, 1, "A rocky surface, or a banded gas giant.", []],
	["seed", "Seed", "float", 0.0, 400.0, "Offsets every noise pattern: a different world with the same settings.", []],
	["detail", "Detail", "int", 2, 8, "Noise octaves: finer detail (costs more).", []],
	["spin", "Spin", "float", -0.06, 0.06, "Rotation speed (rad/s); negative turns the other way.", []],
	["tilt", "Axis tilt", "float", -1.2, 1.2, "Tilt of the axis in the screen plane (rad).", []],
	["incline", "View incline", "float", 0.05, 1.2, "How far we look down on the equator (rings open wider).", []],
	["#", "Terrain"],
	["terrain_scale", "Terrain scale", "float", 0.5, 6.0, "Size of continents and mountain ranges: higher = smaller, more of them.", [0]],
	["warp", "Warp", "float", 0.0, 1.5, "Twists the terrain into swirls and winding coasts.", [0]],
	["ridges", "Ridges", "float", 0.0, 1.0, "Rolling hills (0) to sharp mountain ranges (1).", [0]],
	["relief", "Relief", "float", 0.0, 2.5, "How strongly the terrain is lit as relief.", [0]],
	["#", "Ground"],
	["land_low", "Lowlands", "color", 0, 0, "Ground colour of the lowest land.", [0]],
	["land_mid", "Midlands", "color", 0, 0, "Ground colour of the middle heights.", [0]],
	["land_high", "Highlands", "color", 0, 0, "Ground colour of the high ground.", [0]],
	["land_peak", "Peaks", "color", 0, 0, "Colour of the highest peaks.", [0]],
	["biome", "Biome patches", "float", 0.0, 1.0, "Patches of a second ground colour (deserts, rust, moss).", [0]],
	["biome_scale", "Patch scale", "float", 0.3, 5.0, "Size of the patches.", [0]],
	["biome_color", "Patch colour", "color", 0, 0, "Colour of the patches.", [0]],
	["#", "Water and ice"],
	["water_level", "Sea level", "float", -1.0, 0.95, "Height of the seas (-1: no water at all).", [0]],
	["water_shallow", "Shallows", "color", 0, 0, "Colour of shallow water.", [0]],
	["water_deep", "Deep water", "color", 0, 0, "Colour of deep water.", [0]],
	["water_glow", "Sea glow", "float", 0.0, 1.5, "Glowing shallows (bioluminescent seas).", [0]],
	["ice_cover", "Ice cover", "float", 0.0, 1.0, "Snow on the heights and polar ice caps.", [0]],
	["ice_color", "Ice colour", "color", 0, 0, "Colour of snow and ice.", [0]],
	["#", "Craters and lava"],
	["craters", "Craters", "float", 0.0, 1.5, "Depth and number of impact craters.", [0]],
	["crater_scale", "Crater scale", "float", 0.5, 6.0, "Higher = smaller, more numerous craters.", [0]],
	["lava", "Lava", "float", 0.0, 1.2, "Glowing lava rivers and pools.", [0]],
	["lava_scale", "Lava scale", "float", 0.5, 6.0, "Size of the lava network.", [0]],
	["lava_color", "Lava colour", "color", 0, 0, "Colour of the lava.", [0]],
	["lava_hot", "Hot lava", "color", 0, 0, "Colour of the hottest lava.", [0]],
	["#", "Clouds"],
	["clouds", "Clouds", "float", 0.0, 1.0, "Cloud cover.", [0]],
	["cloud_scale", "Cloud scale", "float", 0.5, 6.0, "Size of the cloud systems.", [0]],
	["cloud_color", "Cloud colour", "color", 0, 0, "Colour of the clouds (dark for smoke).", [0]],
	["cyclone", "Cyclone", "float", 0.0, 1.5, "A spiral storm in the clouds.", [0]],
	["cyclone_dir", "Cyclone position", "vec3", -1.0, 1.0, "Where the cyclone sits on the sphere (a direction).", [0]],
	["#", "Bands"],
	["band_count", "Band count", "float", 1.0, 20.0, "How many cloud bands.", [1]],
	["band_turb", "Turbulence", "float", 0.0, 2.0, "Calm, straight bands (0) to swirling turbulence (2).", [1]],
	["gas_a", "Band colour A", "color", 0, 0, "First band colour.", [1]],
	["gas_b", "Band colour B", "color", 0, 0, "Second band colour.", [1]],
	["gas_c", "Light bands", "color", 0, 0, "The light zones.", [1]],
	["gas_d", "Streaks", "color", 0, 0, "Thin streaks between the bands.", [1]],
	["#", "Great storm"],
	["storm", "Storm", "float", 0.0, 1.2, "Strength of the great storm.", [1]],
	["storm_pos", "Storm position", "vec2", -3.15, 3.15, "Longitude (x) and latitude (y) of the storm, radians.", [1]],
	["storm_size", "Storm size", "float", 0.03, 0.5, "Size of the storm.", [1]],
	["storm_color", "Storm colour", "color", 0, 0, "Colour of the storm.", [1]],
	["#", "Rings"],
	["rings", "Rings", "float", 0.0, 1.0, "Opacity of the rings (0: none).", []],
	["ring_inner", "Inner edge", "float", 1.05, 3.0, "Inner edge of the rings (planet radii).", []],
	["ring_outer", "Outer edge", "float", 1.2, 3.5, "Outer edge of the rings (planet radii).", []],
	["ring_a", "Ring colour A", "color", 0, 0, "Bright ring colour.", []],
	["ring_b", "Ring colour B", "color", 0, 0, "Dark ring colour.", []],
	["#", "Atmosphere"],
	["atmosphere", "Atmosphere", "color", 0, 0, "Colour of the atmosphere's rim and halo.", []],
	["atmo_strength", "Atmosphere strength", "float", 0.0, 1.5, "Thickness of the atmosphere glow.", []],
]
## Properties that change the node's size (rings): rebuilt rather than set.
const STRUCTURAL := ["rings", "ring_outer", "mode"]


## Applies one property to a planet node made by make() (live editing).
static func apply(node: Node, key: String, value: Variant) -> void:
	var mat: ShaderMaterial = node.get_meta("planet_mat", null)
	if mat:
		mat.set_shader_parameter(key, value)


## Features a variant can borrow from the other templates.
const ROCKY_MUTATIONS := ["craters", "ice caps", "glowing seas", "oceans", "lava rivers", "deserts", "cyclones", "dry", "jagged ranges", "dense clouds"]
const GAS_MUTATIONS := ["rings", "great storm", "turbulent", "calm", "many bands", "few bands", "dark bands"]
## Features that don't go together (or with a template).
const CLASH := [["dry", "oceans"], ["dry", "glowing seas"], ["oceans", "glowing seas"], ["calm", "turbulent"],
	["many bands", "few bands"], ["inferno", "oceans"], ["inferno", "glowing seas"], ["inferno", "ice caps"],
	["inferno", "lava rivers"], ["glacier", "lava rivers"], ["ocean", "dry"], ["barren", "craters"],
	["glacier", "ice caps"], ["ocean", "oceans"], ["ringed_giant", "rings"], ["storm_giant", "great storm"],
	["alien", "glowing seas"], ["ocean", "cyclones"], ["glowing seas", "lava rivers"]]
## Keys that aren't shader uniforms.
const META := ["name", "hue_range", "template", "variant", "tags", "color_light", "color_dark"]


## A planet's parameters: the template's, mixed and recoloured for `variant`
## (0 = the template as it is). `overrides` replace any of them last.
static func generate(template: String, variant := 0, overrides := {}) -> Dictionary:
	var t: Dictionary = TEMPLATES.get(template, TEMPLATES["alien"])
	var p: Dictionary = t.duplicate()
	p["template"] = template
	p["variant"] = variant
	p["seed"] = float(variant) * 7.31 + float(TEMPLATES.keys().find(template)) * 13.7
	var tags := []
	var tags_colors := []
	if variant != 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([template, variant])
		if int(p["mode"]) == 0:
			_jitter_rocky(p, rng)
			for m in _pick(ROCKY_MUTATIONS, 2, variant, rng, template):
				tags_colors.append_array(_mutate_rocky(p, m, rng))
				tags.append(m)
		else:
			_jitter_gas(p, rng)
			for m in _pick(GAS_MUTATIONS, 2, variant, rng, template):
				tags_colors.append_array(_mutate_gas(p, m, rng))
				tags.append(m)
		# Palette: a golden-ratio step round the colour wheel per variant, so
		# no two variants share a hue. Ground and gas colours move freely
		# (within the template's range, saturation capped); water stays
		# near blue / teal, ice, lava and clouds stay natural.
		var g: float = fposmod(float(variant) * 0.618034, 1.0) - 0.5
		var shift: float = g * 2.0 * float(t["hue_range"])
		var sat := rng.randf_range(0.8, 1.15)
		var val := rng.randf_range(0.9, 1.1)
		var natural := {"water": [0.07, 0.75], "ice": [0.03, 0.35], "lava": [0.04, 1.0], "cloud": [0.0, 0.25], "ring": [shift, 0.6]}
		for k in p:
			if not p[k] is Color or k in tags_colors:
				continue
			var c: Color = p[k]
			var dh := shift
			var smax := 0.6 if int(p["mode"]) == 0 else 0.62
			for pre in natural:
				if (k as String).begins_with(pre):
					dh = g * natural[pre][0] * 2.0 if pre != "ring" else shift
					smax = natural[pre][1]
			if k == "atmosphere":
				dh = shift * 0.5
			p[k] = Color.from_hsv(fposmod(c.h + dh, 1.0), clampf(c.s * sat, 0.0, smax), clampf(c.v * val, 0.0, 1.0))
		p["tilt"] = rng.randf_range(-0.5, 0.5)
		p["incline"] = rng.randf_range(0.2, 0.5)
		p["spin"] = rng.randf_range(0.006, 0.02) * (1.0 if rng.randf() < 0.8 else -1.0)
	p["tags"] = tags
	p.merge(overrides, true)
	if int(p["mode"]) == 0:
		p["color_light"] = p.get("land_mid", Color.GRAY).lerp(p.get("land_peak", Color.WHITE), 0.3)
		p["color_dark"] = p["water_deep"] if float(p.get("water_level", -1.0)) > 0.0 else p.get("land_low", Color.DIM_GRAY)
	else:
		p["color_light"] = p["gas_a"]
		p["color_dark"] = p["gas_b"]
	return p


## A short description of a generated planet ("Ocean world · craters, lava rivers").
static func describe(p: Dictionary) -> String:
	var s: String = p.get("name", "Planet")
	if not p.get("tags", []).is_empty():
		s += " · " + ", ".join(p["tags"])
	return s


## `n` different mutations that don't clash with each other or the template;
## consecutive variants start at different ones.
static func _pick(list: Array, n: int, variant: int, rng: RandomNumberGenerator, template: String) -> Array:
	var out := []
	var tries := 0
	var first := posmod(variant * 3, list.size())
	while out.size() < n and tries < 100:
		var m: String = list[(first + tries) % list.size()] if tries < list.size() and out.is_empty() else list[rng.randi() % list.size()]
		tries += 1
		if m in out or _clashes(m, template):
			continue
		var ok := true
		for o in out:
			if _clashes(m, o):
				ok = false
		if ok:
			out.append(m)
	return out


static func _clashes(a: String, b: String) -> bool:
	for c in CLASH:
		if (c[0] == a and c[1] == b) or (c[0] == b and c[1] == a):
			return true
	return false


static func _jitter_rocky(p: Dictionary, rng: RandomNumberGenerator) -> void:
	p["terrain_scale"] = float(p["terrain_scale"]) * rng.randf_range(0.7, 1.45)
	p["warp"] = clampf(float(p["warp"]) + rng.randf_range(-0.25, 0.35), 0.1, 1.2)
	p["ridges"] = clampf(float(p["ridges"]) + rng.randf_range(-0.3, 0.2), 0.1, 1.0)
	if float(p.get("water_level", -1.0)) > 0.0:
		p["water_level"] = clampf(float(p["water_level"]) + rng.randf_range(-0.08, 0.08), 0.3, 0.75)
	if p.has("clouds"):
		p["clouds"] = clampf(float(p["clouds"]) + rng.randf_range(-0.15, 0.15), 0.0, 0.8)
	p["cyclone_dir"] = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 0.5), 0.8).normalized()


static func _jitter_gas(p: Dictionary, rng: RandomNumberGenerator) -> void:
	p["band_count"] = float(p["band_count"]) * rng.randf_range(0.75, 1.35)
	p["band_turb"] = clampf(float(p["band_turb"]) * rng.randf_range(0.7, 1.3), 0.1, 1.4)
	p["storm_pos"] = Vector2(PI / 2.0 + rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))
	p["storm_size"] = float(p["storm_size"]) * rng.randf_range(0.7, 1.4)


static func _rand_color(rng: RandomNumberGenerator, s := 0.6, v := 0.75) -> Color:
	return Color.from_hsv(rng.randf(), clampf(s + rng.randf_range(-0.2, 0.2), 0.0, 1.0), clampf(v + rng.randf_range(-0.15, 0.15), 0.0, 1.0))


static func _mutate_rocky(p: Dictionary, m: String, rng: RandomNumberGenerator) -> Array:
	var T := TEMPLATES
	match m:
		"craters":
			p["craters"] = rng.randf_range(0.45, 1.0)
			p["crater_scale"] = rng.randf_range(2.0, 3.6)
		"ice caps":
			p["ice_cover"] = rng.randf_range(0.3, 0.65)
			p["ice_color"] = T["glacier"]["ice_color"]
		"glowing seas":
			if float(p.get("water_level", -1.0)) < 0.0:
				p["water_level"] = rng.randf_range(0.4, 0.52)
				p["water_deep"] = T["alien"]["water_deep"]
			p["water_shallow"] = Color.from_hsv(rng.randf_range(0.42, 0.58), 0.8, 0.88)
			p["water_glow"] = rng.randf_range(0.4, 0.8)
			return ["water_shallow"]
		"oceans":
			p["water_level"] = rng.randf_range(0.52, 0.7)
			p["water_shallow"] = T["ocean"]["water_shallow"]
			p["water_deep"] = T["ocean"]["water_deep"]
		"lava rivers":
			p["lava"] = rng.randf_range(0.4, 0.9)
			p["lava_scale"] = rng.randf_range(1.8, 3.2)
			p["lava_color"] = T["inferno"]["lava_color"]
			p["lava_hot"] = T["inferno"]["lava_hot"]
		"deserts":
			p["biome"] = rng.randf_range(0.55, 1.0)
			p["biome_scale"] = rng.randf_range(1.0, 2.2)
			p["biome_color"] = _rand_color(rng, 0.5, 0.65)
			return ["biome_color"]
		"cyclones":
			p["clouds"] = maxf(float(p.get("clouds", 0.0)), rng.randf_range(0.35, 0.55))
			p["cyclone"] = rng.randf_range(0.7, 1.0)
		"dry":
			p["water_level"] = -1.0
			p["water_glow"] = 0.0
			p["clouds"] = float(p.get("clouds", 0.0)) * 0.3
			p["cyclone"] = 0.0
		"jagged ranges":
			p["ridges"] = rng.randf_range(0.9, 1.0)
			p["relief"] = rng.randf_range(1.3, 1.7)
		"dense clouds":
			p["clouds"] = rng.randf_range(0.55, 0.75)
			p["cloud_scale"] = rng.randf_range(1.6, 3.2)
	return []


static func _mutate_gas(p: Dictionary, m: String, rng: RandomNumberGenerator) -> Array:
	match m:
		"rings":
			p["rings"] = rng.randf_range(0.7, 1.0)
			p["ring_inner"] = rng.randf_range(1.2, 1.45)
			p["ring_outer"] = float(p["ring_inner"]) + rng.randf_range(0.5, 1.0)
			p["ring_a"] = (p["gas_c"] as Color).lerp(Color.WHITE, 0.2)
			p["ring_b"] = (p["gas_b"] as Color).darkened(0.3)
		"great storm":
			p["storm"] = rng.randf_range(0.8, 1.0)
			p["storm_size"] = rng.randf_range(0.16, 0.28)
			p["storm_color"] = _rand_color(rng, 0.65, 0.85)
			return ["storm_color"]
		"turbulent":
			p["band_turb"] = rng.randf_range(1.0, 1.4)
		"calm":
			p["band_turb"] = rng.randf_range(0.12, 0.3)
		"many bands":
			p["band_count"] = rng.randf_range(12.0, 16.0)
		"few bands":
			p["band_count"] = rng.randf_range(3.5, 5.5)
		"dark bands":
			p["gas_b"] = (p["gas_b"] as Color).darkened(0.45)
			p["gas_d"] = _rand_color(rng, 0.6, 0.55)
			return ["gas_d"]
	return []


## A planet node: a Control of `size` px whose disk is `radius` of the
## half-size (the shader rect is bigger when the planet has rings or a halo).
## Its material is in meta "planet_mat" (set_light changes the sun's side).
## `cached`: drawn into a picture a few times a second (ShaderCache - space's
## planets), not by its shader every frame.
static func make(p: Dictionary, size: float, radius := DISK, cached := false) -> Control:
	var holder := Control.new()
	holder.size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disk := size / 2.0 * radius
	var ext := 1.12
	if float(p.get("rings", 0.0)) > 0.0:
		ext = maxf(ext, float(p.get("ring_outer", 2.2)) * 1.02)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2.ONE * disk * ext * 2.0
	rect.position = Vector2.ONE * (size / 2.0 - disk * ext)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for k in p:
		if not k in META:
			mat.set_shader_parameter(k, p[k])
	mat.set_shader_parameter("planet_radius", 1.0 / ext)
	mat.set_shader_parameter("detail", 7 if disk > 250.0 else (6 if disk > 90.0 else 4))
	rect.material = mat
	if cached:
		holder.add_child(ShaderCache.wrap(rect, 12.0, 2048.0))
	else:
		holder.add_child(rect)
	holder.set_meta("planet_mat", mat)
	return holder


## Lights the planet from `dir` (screen direction toward its sun).
static func set_light(planet: Control, dir: Vector2) -> void:
	var mat: ShaderMaterial = planet.get_meta("planet_mat", null)
	if mat and dir != Vector2.ZERO:
		var d := dir.normalized()
		mat.set_shader_parameter("light_dir", Vector3(d.x, d.y, 0.55))
