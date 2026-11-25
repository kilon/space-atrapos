class_name NebulaGen
## Procedural deep-space backdrops (shaders/nebula.gdshader) from four
## templates, modelled on the references in external/images/nebula_refs/:
##   remnant   - supernova remnant: a shell of orange / blue filaments  (ref 1)
##   planetary - planetary nebula: shells and bubbles, a central star,
##               twin jets, faint outer rings                          (ref 2)
##   emission  - emission nebula: pink / red clouds, dust lanes, a
##               bright core and young stars                           (ref 3)
##   galaxy    - a tilted spiral galaxy with dust lanes and satellites  (ref 4)
## generate(template, variant): variant 0 is the template; others borrow
## features, step round the colour wheel (golden ratio) and change shape,
## so every nebula is different. for_system(id) gives a system its own set.

const SHADER := preload("res://shaders/nebula.gdshader")

const TEMPLATES := {
	"remnant": {"name": "Supernova remnant", "mode": 0, "hue_range": 0.5,
		"color_a": Color(0.95, 0.38, 0.1), "color_b": Color(0.25, 0.55, 1.0), "color_c": Color(0.95, 0.95, 1.0), "color_d": Color(0.55, 0.85, 0.3),
		"drift": 0.0, "filaments": 0.9, "dust": 0.0, "core": 0.0, "stars": 0.0, "jets": 0.0, "stretch": Vector2(1.0, 0.75), "intensity": 0.8},
	"planetary": {"name": "Planetary nebula", "mode": 1, "hue_range": 0.6,
		"color_a": Color(1.0, 0.5, 0.15), "color_b": Color(0.3, 0.7, 1.0), "color_c": Color(0.95, 0.95, 1.0), "color_d": Color(0.15, 0.55, 0.6),
		"drift": 0.0, "shells": 1.0, "jets": 1.0, "core": 1.0, "stars": 0.0, "rot": -0.75, "stretch": Vector2(1.0, 0.9), "intensity": 0.75},
	"emission": {"name": "Emission nebula", "mode": 2, "hue_range": 0.4,
		"color_a": Color(0.85, 0.15, 0.35), "color_b": Color(0.95, 0.4, 0.7), "color_c": Color(1.0, 0.92, 0.85), "color_d": Color(0.2, 0.6, 0.65),
		"drift": 0.0, "filaments": 0.8, "dust": 0.55, "core": 0.9, "stars": 0.6, "jets": 0.0, "stretch": Vector2(1.15, 0.95), "intensity": 0.9},
	"galaxy": {"name": "Spiral galaxy", "mode": 3, "hue_range": 0.25,
		"color_a": Color(1.0, 0.75, 0.45), "color_b": Color(0.45, 0.55, 1.0), "color_c": Color(1.0, 0.95, 0.85), "color_d": Color(1.0, 0.4, 0.7),
		"arms": 2.0, "wind": 2.6, "incline": 0.38, "dust": 0.7, "core": 0.8, "stars": 0.5, "satellites": 1.0, "jets": 0.0, "rot": -0.6, "intensity": 0.9},
}

## The editable properties (the zoo's property panel builds itself from
## these): [key, label, type, min, max, help, kinds it applies to ([] = all)].
## Types: float, int, color, vec2, enum:<a>,<b>,...  ["#", "Group"] starts a group.
const PROPERTIES := [
	["#", "Kind and shape"],
	["mode", "Kind", "enum:Supernova remnant,Planetary nebula,Emission nebula,Spiral galaxy", 0, 3, "What kind of object this is: each draws differently.", []],
	["seed", "Seed", "float", 0.0, 100.0, "Offsets every noise pattern: a different cloud with the same settings.", []],
	["intensity", "Brightness", "float", 0.0, 2.0, "Overall brightness (it's added onto the sky).", []],
	["rot", "Rotation", "float", -3.15, 3.15, "Turns the whole object (radians).", []],
	["stretch", "Stretch", "vec2", 0.3, 2.0, "Scales the object across (x) and along (y) - elongates or squashes it.", []],
	["drift", "Drift", "float", -0.1, 0.1, "Slow rotation over time (radians per second); spins a galaxy's arms.", []],
	["#", "Colours"],
	["color_a", "Outer colour", "color", 0, 0, "The outer shell, cloud edges and jets (remnant: orange filaments).", []],
	["color_b", "Inner colour", "color", 0, 0, "The inner glow (remnant: the blue core; galaxy: the arms).", []],
	["color_c", "Highlights", "color", 0, 0, "The hottest parts: bright filaments, central star, a galaxy's bulge.", []],
	["color_d", "Patches", "color", 0, 0, "Patches and knots: green patches, outer rings, pink star-forming knots.", []],
	["#", "Structure"],
	["filaments", "Filaments", "float", 0.0, 2.0, "Strength of the glowing web / wisps.", [0, 2]],
	["dust", "Dust lanes", "float", 0.0, 1.0, "Dark lanes that eat the glow.", [0, 2, 3]],
	["core", "Core", "float", 0.0, 2.0, "Brightness of the centre (central star, bright core, bulge).", []],
	["stars", "Stars", "float", 0.0, 2.0, "Young stars sparkling inside it.", []],
	["jets", "Jets", "float", 0.0, 2.0, "Twin jets along its axis.", []],
	["shells", "Shells", "float", 0.0, 2.0, "Brightness of the nested shells, bubbles and outer rings.", [1]],
	["#", "Galaxy"],
	["arms", "Arms", "float", 1.0, 6.0, "Number of spiral arms.", [3]],
	["wind", "Winding", "float", 0.5, 6.0, "How tightly the arms wind.", [3]],
	["incline", "Incline", "float", 0.1, 1.0, "How far we see the disc face-on (1) or edge-on (small).", [3]],
	["satellites", "Satellites", "float", 0.0, 2.0, "Brightness of the two dwarf satellite galaxies.", [3]],
]
## Properties that need the node rebuilt (none: everything is a shader value).
const STRUCTURAL := []


## Applies one property to a nebula node made by make() (live editing).
static func apply(node: Node, key: String, value: Variant) -> void:
	var mat: ShaderMaterial = node.material if node is CanvasItem else null
	if mat:
		mat.set_shader_parameter(key, value)


const MUTATIONS := {
	"remnant": ["dense web", "faint web", "green patches", "elongated", "bright core"],
	"planetary": ["no jets", "double rings", "faint rings", "elongated", "bright star"],
	"emission": ["dusty", "clear", "wispy", "bright core", "star cluster"],
	"galaxy": ["tight arms", "loose arms", "four arms", "face-on", "edge-on", "no satellites"],
}
const META := ["name", "hue_range", "template", "variant", "tags"]


static func generate(template: String, variant := 0) -> Dictionary:
	var t: Dictionary = TEMPLATES.get(template, TEMPLATES["emission"])
	var p: Dictionary = t.duplicate()
	p["template"] = template
	p["variant"] = variant
	p["seed"] = float(variant) * 3.71 + float(TEMPLATES.keys().find(template)) * 9.1
	var tags := []
	if variant != 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["nebula", template, variant])
		var list: Array = MUTATIONS[template]
		tags.append(list[posmod(variant * 3, list.size())])
		var other = list[rng.randi() % list.size()]
		if not other in tags and not ([other, tags[0]] in [["tight arms", "loose arms"], ["loose arms", "tight arms"], ["face-on", "edge-on"], ["edge-on", "face-on"],
				["dusty", "clear"], ["clear", "dusty"], ["dense web", "faint web"], ["faint web", "dense web"]]):
			tags.append(other)
		for m in tags:
			_mutate(p, m, rng)
		p["rot"] = float(p.get("rot", 0.0)) + rng.randf_range(-1.2, 1.2)
		var st: Vector2 = p.get("stretch", Vector2.ONE)
		p["stretch"] = st * Vector2(rng.randf_range(0.85, 1.15), rng.randf_range(0.85, 1.15))
		var g: float = fposmod(float(variant) * 0.618034, 1.0) - 0.5
		var shift: float = g * 2.0 * float(t["hue_range"])
		for k in p:
			if p[k] is Color and k != "color_c":
				var c: Color = p[k]
				p[k] = Color.from_hsv(_nebular(fposmod(c.h + shift, 1.0)), clampf(c.s * rng.randf_range(0.85, 1.1), 0.0, 1.0), c.v)
	p["tags"] = tags
	return p


## Emission colours: real nebulae glow red, pink, violet, blue and teal,
## rarely yellow-green - hues in that band are moved toward orange or teal.
static func _nebular(h: float) -> float:
	if h > 0.11 and h < 0.24:
		return lerpf(0.06, 0.1, (h - 0.11) / 0.13)
	if h >= 0.24 and h < 0.42:
		return lerpf(0.45, 0.5, (h - 0.24) / 0.18)
	return h


static func describe(p: Dictionary) -> String:
	var s: String = p.get("name", "Nebula")
	if not p.get("tags", []).is_empty():
		s += " · " + ", ".join(p["tags"])
	return s


static func _mutate(p: Dictionary, m: String, rng: RandomNumberGenerator) -> void:
	match m:
		"dense web": p["filaments"] = rng.randf_range(1.1, 1.4)
		"faint web": p["filaments"] = rng.randf_range(0.4, 0.6)
		"green patches": p["color_d"] = Color.from_hsv(rng.randf_range(0.2, 0.4), 0.7, 0.85)
		"elongated": p["stretch"] = Vector2(1.0, rng.randf_range(0.5, 0.65))
		"bright core": p["core"] = rng.randf_range(1.0, 1.4)
		"no jets": p["jets"] = 0.0
		"double rings": p["shells"] = rng.randf_range(1.15, 1.3)
		"faint rings": p["shells"] = rng.randf_range(0.5, 0.7)
		"bright star": p["core"] = rng.randf_range(1.3, 1.6)
		"dusty": p["dust"] = rng.randf_range(0.8, 1.0)
		"clear": p["dust"] = rng.randf_range(0.1, 0.25)
		"wispy": p["filaments"] = rng.randf_range(1.0, 1.4)
		"star cluster": p["stars"] = rng.randf_range(1.0, 1.4)
		"tight arms": p["wind"] = rng.randf_range(3.4, 4.2)
		"loose arms": p["wind"] = rng.randf_range(1.6, 2.0)
		"four arms": p["arms"] = 4.0
		"face-on": p["incline"] = rng.randf_range(0.7, 0.9)
		"edge-on": p["incline"] = rng.randf_range(0.18, 0.24)
		"no satellites": p["satellites"] = 0.0


## A ColorRect of `size` px showing the nebula (additive, edges faded).
static func make(p: Dictionary, size: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(size, size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for k in p:
		if not k in META:
			mat.set_shader_parameter(k, p[k])
	rect.material = mat
	return rect


## The backdrop of system `id`: 2-3 nebulae / galaxies, each a variant no
## other system uses. [[params, position, size], ...]
static func for_system(id: String, index: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["nebulae", id])
	var out := []
	var n := rng.randi_range(2, 3)
	var kinds := ["emission", "remnant", "planetary", "galaxy"]
	for i in n:
		var t: String = kinds[(index + i * 3 + rng.randi() % 2) % kinds.size()]
		var size := rng.randf_range(1300.0, 1900.0) if t in ["emission", "remnant"] else rng.randf_range(800.0, 1200.0)
		var pos := Vector2(rng.randf_range(-1600, 1400), rng.randf_range(-1400, 1400))
		out.append([generate(t, 1 + index * 4 + i), pos, size])
	return out
