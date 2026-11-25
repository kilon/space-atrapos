class_name AsteroidGen
## Procedural asteroids (shaders/asteroid.gdshader) from two templates,
## modelled on the reference rocks in external/images/asteroid_refs/:
##   contact_binary - two fused, rounded lobes; grey-tan, crisp craters  (ref 1)
##   craggy         - long, broken rock; deep pits, rust-orange patches   (ref 2)
## generate(template, variant) mixes them: variant 0 is the template itself;
## every other variant blends the two by a random amount, adds two mutations
## (shard, rubble pile, heavily cratered, dark carbon...), jitters colours,
## shape, pose and spin - so no two rocks in a field look alike.
## ORE adds each ore type's look (colour, veins) on top.

const SHADER := preload("res://shaders/asteroid.gdshader")
## The quad is FRAME times the rock's radius (room for the lock-on glow).
const FRAME := 1.35

const TEMPLATES := {
	"contact_binary": {"name": "Contact binary",
		"binary": 1.0, "lobe_ratio": 0.86, "neck": 0.12, "elongation": 1.05, "flatten": 0.9,
		"lumps": 0.35, "lump_scale": 1.5, "crags": 0.12, "craters": 0.85, "crater_scale": 2.6, "crater_depth": 1.0,
		"small_craters": 0.9, "pitting": 0.6,
		"c_rock": Color(0.53, 0.51, 0.48), "c_dark": Color(0.17, 0.15, 0.14), "c_light": Color(0.7, 0.68, 0.64),
		"c_rust": Color(0.6, 0.42, 0.28), "rust": 0.15, "rust_scale": 2.2, "cavity_rust": 0.75, "dust": 0.25, "color_noise": 0.3,
		"ambient": 0.12, "contrast": 1.0, "rim": 0.15, "rim_color": Color(1.0, 0.85, 0.7), "specular": 0.1},
	"craggy": {"name": "Craggy rock",
		"binary": 0.0, "lobe_ratio": 0.7, "neck": 0.3, "elongation": 1.75, "flatten": 0.68,
		"lumps": 0.8, "lump_scale": 1.8, "crags": 0.75, "craters": 1.0, "crater_scale": 1.9, "crater_depth": 1.5,
		"small_craters": 0.8, "pitting": 0.85,
		"c_rock": Color(0.36, 0.37, 0.4), "c_dark": Color(0.1, 0.09, 0.1), "c_light": Color(0.75, 0.74, 0.76),
		"c_rust": Color(0.82, 0.45, 0.18), "rust": 0.32, "rust_scale": 2.4, "cavity_rust": 0.45, "dust": 0.45, "color_noise": 0.4,
		"ambient": 0.08, "contrast": 1.3, "rim": 0.5, "rim_color": Color(1.0, 0.62, 0.32), "specular": 0.25},
}

## What each ore type adds (its asteroids are told apart by these).
const ORE := {
	"iron": {"rust": 0.45, "cavity_rust": 0.7, "c_rust": Color(0.72, 0.38, 0.18),
		"veins": 0.35, "vein_color": Color(0.85, 0.48, 0.3), "vein_glow": 0.0},
	"titanium": {"c_rock": Color(0.38, 0.43, 0.5), "c_light": Color(0.72, 0.8, 0.88), "rust": 0.08, "cavity_rust": 0.25,
		"c_rust": Color(0.4, 0.5, 0.62), "veins": 0.8, "vein_color": Color(0.4, 0.88, 1.0), "vein_glow": 1.2, "vein_width": 0.08},
	"platinum": {"c_rock": Color(0.27, 0.26, 0.29), "c_dark": Color(0.07, 0.06, 0.08), "c_light": Color(0.62, 0.6, 0.58),
		"rust": 0.1, "cavity_rust": 0.3, "c_rust": Color(0.55, 0.5, 0.4),
		"veins": 0.8, "vein_color": Color(1.0, 0.82, 0.38), "vein_glow": 1.2, "vein_width": 0.08},
	# A ring's ice (the rings' local spaces: SignalSite "ring").
	"ice": {"c_rock": Color(0.72, 0.82, 0.9), "c_dark": Color(0.25, 0.36, 0.5), "c_light": Color(0.95, 0.98, 1.0),
		"rust": 0.0, "cavity_rust": 0.15, "c_rust": Color(0.55, 0.75, 0.95),
		"veins": 0.5, "vein_color": Color(0.6, 0.9, 1.0), "vein_glow": 0.6, "vein_width": 0.06},
}

## The editable properties (the Library's property panel builds itself from
## these): [key, label, type, min, max, help, (unused: [] = every rock)].
const PROPERTIES := [
	["#", "Shape"],
	["seed", "Seed", "float", 0.0, 100.0, "Offsets every noise pattern: a different rock with the same settings.", []],
	["elongation", "Elongation", "float", 0.8, 2.4, "Stretch of the long axis.", []],
	["flatten", "Thickness", "float", 0.4, 1.0, "The short axis: low makes a flat slab or shard.", []],
	["binary", "Two lobes", "float", 0.0, 1.0, "0: one body; 1: two lobes fused together (a contact binary).", []],
	["lobe_ratio", "Second lobe size", "float", 0.4, 1.0, "Size of the second lobe against the first.", []],
	["neck", "Neck", "float", 0.02, 0.6, "How smoothly the lobes merge: low leaves a sharp crease.", []],
	["lumps", "Lumps", "float", 0.0, 1.5, "Large bulges and dents in the outline.", []],
	["lump_scale", "Lump size", "float", 0.6, 4.0, "Frequency of the lumps: higher = smaller, more of them.", []],
	["crags", "Crags", "float", 0.0, 1.5, "Ridged, broken relief: sharp crests and gullies.", []],
	["#", "Craters"],
	["craters", "Craters", "float", 0.0, 1.5, "Large crater bowls (they also notch the outline).", []],
	["crater_scale", "Crater spacing", "float", 1.0, 5.0, "Higher = more, smaller craters.", []],
	["crater_depth", "Crater depth", "float", 0.2, 2.5, "Depth of the bowls and height of their rims.", []],
	["small_craters", "Small craters", "float", 0.0, 1.5, "A second, finer layer of craters.", []],
	["pitting", "Pitting", "float", 0.0, 1.5, "Tiny pits and grain all over the surface.", []],
	["detail", "Detail", "int", 1, 6, "Noise octaves of the fine grain (costs more).", []],
	["#", "Colour"],
	["c_rock", "Rock colour", "color", 0, 0, "The main colour of the rock.", []],
	["c_dark", "Shadow colour", "color", 0, 0, "Crevices, pits and the soft edge.", []],
	["c_light", "Dust colour", "color", 0, 0, "Pale dust on the crests.", []],
	["dust", "Dust", "float", 0.0, 1.0, "How much pale dust lies on the crests.", []],
	["c_rust", "Rust colour", "color", 0, 0, "Mineral patches (rust-orange on iron rocks).", []],
	["rust", "Rust patches", "float", 0.0, 1.0, "Large patches of the rust colour.", []],
	["rust_scale", "Patch size", "float", 0.6, 6.0, "Higher = smaller patches.", []],
	["cavity_rust", "Rust in pits", "float", 0.0, 1.0, "Rust gathered in craters and crevices.", []],
	["color_noise", "Mottling", "float", 0.0, 1.0, "Light and dark mottling of the rock colour.", []],
	["#", "Ore veins"],
	["veins", "Veins", "float", 0.0, 1.0, "Seams of ore across the surface.", []],
	["vein_color", "Vein colour", "color", 0, 0, "The ore's colour.", []],
	["vein_glow", "Vein glow", "float", 0.0, 2.5, "How brightly the veins glow (precious ores glow).", []],
	["vein_scale", "Vein spacing", "float", 0.8, 6.0, "Higher = more, closer veins.", []],
	["vein_width", "Vein width", "float", 0.02, 0.25, "Thickness of the seams.", []],
	["#", "Light"],
	["ambient", "Ambient", "float", 0.0, 0.5, "Light on the dark side.", []],
	["contrast", "Contrast", "float", 0.5, 2.5, "Harder light: deeper shadows, brighter faces.", []],
	["light_color", "Light colour", "color", 0, 0, "Colour of the sunlight.", []],
	["rim", "Rim light", "float", 0.0, 1.5, "A bright edge on the lit side.", []],
	["rim_color", "Rim colour", "color", 0, 0, "Colour of the rim light.", []],
	["specular", "Shine", "float", 0.0, 1.0, "Sharp highlights on the crests.", []],
	["#", "Motion"],
	["spin", "Spin", "float", -0.6, 0.6, "Turning speed (rad/s).", []],
	["tumble", "Tumble", "float", 0.0, 1.5, "Tilt of the spin axis: 0 turns flat, higher rolls the rock over.", []],
	["pose", "Pose", "vec3", -3.15, 3.15, "Starting orientation (three angles): which face it shows.", []],
]
## Shape keys: changing them changes the rock's extent (the fit is redone).
const STRUCTURAL := []
const SHAPE_KEYS := ["elongation", "binary", "lobe_ratio", "lumps", "crags"]

const MUTATIONS := ["contact binary", "elongated", "shard", "rubble pile", "heavily cratered", "smooth",
	"rusty", "dusty", "dark carbon", "pale", "pitted", "tumbling"]
const META := ["name", "template", "variant", "tags", "color", "ore"]


static func generate(template: String, variant := 0, look := {}) -> Dictionary:
	var p: Dictionary = TEMPLATES.get(template, TEMPLATES["craggy"]).duplicate()
	p["template"] = template
	p["variant"] = variant
	p["seed"] = float(posmod(variant, 997)) * 3.71 + float(TEMPLATES.keys().find(template)) * 13.1
	p["pose"] = Vector3(0.3, 0.8, 0.2) if template == "contact_binary" else Vector3(0.5, 0.1, 0.45)
	p["spin"] = 0.12
	p["tumble"] = 0.35
	var tags := []
	if variant != 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["asteroid", template, variant])
		# Blend towards the other template by a random amount.
		var other: String = TEMPLATES.keys()[1 - TEMPLATES.keys().find(template)] if TEMPLATES.has(template) else "contact_binary"
		var o: Dictionary = TEMPLATES[other]
		var t := rng.randf_range(0.0, 0.45)
		for k in o:
			if p[k] is float and o[k] is float:
				p[k] = lerpf(p[k], o[k], t)
			elif p[k] is Color:
				p[k] = (p[k] as Color).lerp(o[k], t)
		var first := posmod(variant * 5, MUTATIONS.size())
		tags.append(MUTATIONS[first])
		while tags.size() < 2:
			var m: String = MUTATIONS[rng.randi() % MUTATIONS.size()]
			if not m in tags and not (m == "smooth" and "heavily cratered" in tags) and not (m == "heavily cratered" and "smooth" in tags):
				tags.append(m)
		for m in tags:
			_mutate(p, m, rng)
		p["elongation"] = clampf(float(p["elongation"]) * rng.randf_range(0.85, 1.15), 0.8, 2.4)
		p["lump_scale"] = float(p["lump_scale"]) * rng.randf_range(0.8, 1.25)
		p["crater_scale"] = float(p["crater_scale"]) * rng.randf_range(0.85, 1.2)
		p["pose"] = Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))
		p["spin"] = rng.randf_range(0.06, 0.22) * (1.0 if rng.randf() < 0.5 else -1.0)
		p["tumble"] = clampf(float(p.get("tumble", 0.35)) * rng.randf_range(0.5, 1.4), 0.0, 1.5)
		p["time_offset"] = rng.randf_range(0.0, 100.0)
		# Colour: rocks stay rocky - small hue and value steps.
		var dh := (fposmod(float(variant) * 0.618034, 1.0) - 0.5) * 0.06
		var val := rng.randf_range(0.85, 1.12)
		for k in ["c_rock", "c_dark", "c_light", "c_rust"]:
			var c: Color = p[k]
			p[k] = Color.from_hsv(fposmod(c.h + dh, 1.0), clampf(c.s * rng.randf_range(0.8, 1.2), 0.0, 1.0), clampf(c.v * val, 0.0, 1.0))
	p.merge(look, true)
	p["tags"] = tags
	p["color"] = p["c_rock"]
	return p


## The look of an in-game asteroid: its ore type and seed pick the template
## and variant; a Themes preset can restyle it (asteroid kind, by system).
static func for_rock(ore: String, seed_: int, themed := true) -> Dictionary:
	var template: String = "contact_binary" if posmod(seed_, 3) == 0 else "craggy"
	var p := generate(template, 1 + posmod(seed_, 100003))
	p.merge(ORE.get(ore, ORE["iron"]), true)
	p["ore"] = ore
	if themed:
		p.merge(Themes.pick("asteroid", Themes.context(), seed_, template), true)
	p["color"] = p["c_rock"]
	return p


static func describe(p: Dictionary) -> String:
	var s: String = p.get("name", "Asteroid")
	if not p.get("tags", []).is_empty():
		s += " · " + ", ".join(p["tags"])
	return s


static func _mutate(p: Dictionary, m: String, rng: RandomNumberGenerator) -> void:
	match m:
		"contact binary":
			p["binary"] = rng.randf_range(0.7, 1.0)
			p["lobe_ratio"] = rng.randf_range(0.6, 0.95)
			p["neck"] = rng.randf_range(0.06, 0.25)
			p["elongation"] = minf(float(p["elongation"]), 1.25)
		"elongated":
			p["elongation"] = rng.randf_range(1.7, 2.2)
			p["binary"] = float(p["binary"]) * 0.5
		"shard":
			p["flatten"] = rng.randf_range(0.42, 0.58)
			p["crags"] = maxf(float(p["crags"]), rng.randf_range(0.8, 1.1))
			p["binary"] = 0.0
		"rubble pile":
			p["lumps"] = rng.randf_range(1.0, 1.3)
			p["lump_scale"] = rng.randf_range(2.4, 3.2)
			p["crags"] = float(p["crags"]) * 0.5
		"heavily cratered":
			p["craters"] = rng.randf_range(1.2, 1.5)
			p["small_craters"] = rng.randf_range(1.1, 1.4)
			p["crater_scale"] = rng.randf_range(2.6, 3.4)
		"smooth":
			p["craters"] = float(p["craters"]) * 0.4
			p["pitting"] = float(p["pitting"]) * 0.4
			p["crags"] = float(p["crags"]) * 0.3
		"rusty":
			p["rust"] = rng.randf_range(0.65, 0.9)
			p["rust_scale"] = rng.randf_range(1.4, 2.6)
		"dusty":
			p["dust"] = rng.randf_range(0.6, 0.9)
		"dark carbon":
			p["c_rock"] = (p["c_rock"] as Color).darkened(0.4)
			p["c_light"] = (p["c_light"] as Color).darkened(0.3)
			p["rust"] = float(p["rust"]) * 0.4
		"pale":
			p["c_rock"] = (p["c_rock"] as Color).lightened(0.2)
		"pitted":
			p["pitting"] = rng.randf_range(1.1, 1.4)
		"tumbling":
			p["tumble"] = rng.randf_range(0.9, 1.3)


## Half the rock's longest axis, in body units (the shader's shapes).
static func extent(p: Dictionary) -> float:
	var b := float(p.get("binary", 0.0))
	var e := float(p.get("elongation", 1.3)) * lerpf(1.0, 0.72, b)
	var lr := float(p.get("lobe_ratio", 0.8))
	var x := maxf(0.62 * b + e, 0.62 * b * lr + 0.05 + e * lr) if b > 0.01 else e
	return maxf(x, 1.0) + 0.08 * float(p.get("lumps", 0.5)) + 0.05 * float(p.get("crags", 0.3))


## A ColorRect showing the rock, its long half-axis `radius` px, centred on (0, 0).
static func make(p: Dictionary, radius: float) -> ColorRect:
	var rect := ColorRect.new()
	var size := radius * FRAME * 2.0
	rect.size = Vector2(size, size)
	rect.position = -rect.size / 2.0
	rect.pivot_offset = rect.size / 2.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for k in p:
		if not k in META:
			mat.set_shader_parameter(k, p[k])
	mat.set_shader_parameter("detail", 4 if radius > 90.0 else 3)
	mat.set_shader_parameter("fit", 1.0 / (FRAME * extent(p)))
	rect.material = mat
	rect.set_meta("spec", p.duplicate())
	return rect


## Applies one property to a rock made by make() (live editing).
static func apply(node: Node, key: String, value: Variant) -> void:
	var mat: ShaderMaterial = node.material if node is CanvasItem else null
	if mat == null:
		return
	mat.set_shader_parameter(key, value)
	var spec: Dictionary = node.get_meta("spec", {})
	spec[key] = value
	node.set_meta("spec", spec)
	if key in SHAPE_KEYS:
		mat.set_shader_parameter("fit", 1.0 / (FRAME * extent(spec)))
